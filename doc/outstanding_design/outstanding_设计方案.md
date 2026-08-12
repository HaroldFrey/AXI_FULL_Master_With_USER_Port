# 设计方案 — AXI FULL Master Outstanding 事务支持

> 基于 doc/outstanding_design.md（原设计）+ A0 需求分析（doc/outstanding_需求分析.md）
> 对原设计的修订说明：
> 1. **W 数据严格串行**（AXI4 无 WID：写数据顺序必须等于写地址顺序）——原设计"多个 slot 同时处于 W_DATA"表述不成立，改为集中式 W 调度器
> 2. **AW 必须按 start 顺序发出**（保 W 顺序 = AW 顺序），用轮询指针实现
> 3. **读通道采用同 ARID=0 保序方案**（A0 决策），R 数据按 AR 顺序匹配槽位，无需乱序逻辑
> 4. **槽位地址自增**：突发拍数(len)×W 字节（与原实现一致；len 语义 = 突发拍数 1~256）

**规模判定**：多模块——改造 `axi_wr_master` / `axi_rd_master`（核心），`AXI_FULL_Master_With_USER_Port` 顶层接线，`Data_RX` / `Data_TX` / `fifo_async` 不动。

## 功能概述

为写/读控制器各增加**槽位表（slot table）**：每通道可同时跟踪多个进行中的事务。写通道：AW 按 start 顺序流水线发出，W 数据由 Data_RX FIFO 串行发送（一次一个事务），B 响应按 BID（槽号）匹配释放槽位；读通道：AR 流水线发出（ARID 恒 0），R 数据保序按 AR 顺序匹配槽位并透传用户。用户接口新增 ready_start 指示（有空闲槽位），ID 完全自动管理。

## 设计思路

### 需求与目标

- 解决：现 2 态 FSM 串行执行，事务间存在大量总线空闲周期，吞吐低
- 目标：总线利用率提升（AW/AR 流水线重叠），读写通道各支持 MAX_OUTSTANDING（默认 4）个在途事务
- 非功能：可综合、参数化、与现有读写独立架构一致、iverilog 兼容

### 方案选型

| 候选方案 | 优点 | 缺点 | 结论 |
|---------|------|------|------|
| A. 槽位表 + 集中式调度（本方案） | 每槽状态简单；W/R 串行调度集中管理；B 乱序匹配天然支持 | 槽位数受限（寄存器阵列） | **采用** |
| B. 事务 FIFO 队列（顺序队列） | 实现直观 | B 乱序需按 ID 索引队列，退化回槽位表 | 不采用 |
| C. 每槽独立 FSM + 仲裁 | 并行度最高 | 仲裁/互斥逻辑复杂（AW/W/R 通道竞争），验证面大 | 不采用 |

**关键技术取舍**：
- **槽位用寄存器阵列**（≤8 槽），不用 RAM（面积小、无 BRAM 推断问题）
- **AW/W 保序用轮询指针**（next_aw_slot / next_w_slot）而非优先级仲裁——天然保持 start 顺序，无饥饿
- **B 匹配用 BID=槽号直接索引**，乱序响应天然支持
- **读通道同 ID 保序**：R 数据按 next_r_slot 顺序匹配，无 ID 路由逻辑
- **W 数据不改 FIFO 结构**：Data_RX FIFO 顺序 = 用户写入顺序 = start 顺序，直接串行输出

### 架构设计

```
┌───────────────────────────────────────────────────────────────┐
│ AXI_FULL_Master_With_USER_Port（顶层：加参数 + ready_start 端口）│
│                                                               │
│  user_wr_ready_start ──┐                                     │
│  ┌─────────────────────▼───────────────────┐                  │
│  │ axi_wr_master (v2)                       │                 │
│  │  ┌──────────────┐  ┌──────────────────┐ │                 │
│  │  │ Slot Table ×N │  │ 集中式调度器       │ │                 │
│  │  │ [状态/地址/长度]│◄─┤ next_aw/next_w   │ │                 │
│  │  │ BID→槽索引匹配  │  │ B匹配/W串行/AW保序 │ │                 │
│  │  └──────────────┘  └──────────────────┘ │                 │
│  └─────────────────────────────────────────┘                 │
│  ┌─────────────────────────────────────────┐                 │
│  │ axi_rd_master (v2)                       │                 │
│  │  Slot Table ×N + next_ar/next_r 调度      │                 │
│  └─────────────────────────────────────────┘                 │
│  Data_RX / Data_TX / fifo_async（不动）                       │
└───────────────────────────────────────────────────────────────┘
```

**数据流**：
- 写：user_wr_data → Data_RX FIFO →（W 调度器，串行）→ M_AXI_WDATA；AW 由槽位调度发出；B 返回按 BID 释放槽位
- 读：M_AXI_RDATA →（R 保序匹配）→ user_rd_data_out；AR 由槽位调度发出

**控制流**：
- 槽位状态机：FREE → AW_PEND → W_DATA → B_WAIT → FREE（写）；FREE → AR_PEND → R_ACTIVE → FREE（读）
- 调度器（组合+时序）：next_*_slot 轮询指针驱动各通道握手

### 具体实现要点

**1. 槽位分配（写）**：wr_start 脉冲时，轮询扫描（round-robin，从 0 递增回绕）找 FREE 槽位：
- 采样 addr/len/burst_type 到槽位 → 槽位状态 = AW_PEND（标记"待发 AW"）
- 无空闲槽时忽略 wr_start（user_wr_ready_start=0 已禁止，防御性忽略）
- ready_start = |(任一槽 FREE)

**2. AW 调度（保序）**：next_aw_slot 轮询指针（0..N-1 递增回绕）：
- 条件：指向槽位状态 == AW_PEND 且 AW 通道空闲（无未握手 AW）
- 动作：M_AXI_AWVALID=1，AWADDR=槽位地址，AWID=槽号，AWLEN=槽位 len-1
- AW 握手 → 槽位 → W_DATA，next_aw_slot 前进（扫描下一 AW_PEND 槽）
- 空闲时（指向槽非 AW_PEND）也前进（扫描）——保证指针最终到达 AW_PEND 槽

**3. W 调度（串行）**：next_w_slot 轮询指针：
- 条件：指向槽位状态 == W_DATA 且 Data_RX FIFO 非空且全局 wr_cnt != 槽位 len
- 动作：M_AXI_WVALID = 上述条件；M_AXI_WDATA = FIFO 输出；M_AXI_WLAST = (wr_cnt == len-1)
- WLAST 握手 → 槽位 → B_WAIT；wr_cnt 清零；next_w_slot 前进
- 反压：FIFO 空 → WVALID=0（等待数据）；无 W_DATA 槽位 → WVALID=0

**4. B 匹配（乱序）**：M_AXI_BID 直接作为槽号索引：
- M_AXI_BREADY = |(任一槽位 B_WAIT)（B 到达时槽位必已 B_WAIT：从机 WLAST 握手后至少 1 拍才回 B）
- B 握手且槽位 B_WAIT → 槽位 FREE；BRESP≠OKAY → wr_error 置位（新 start 清零）

**5. 读通道（同 ID 保序）**：
- 槽位分配/AR 调度同写侧（next_ar_slot 轮询），ARID 恒 0，ARLEN=槽位 len-1
- R 保序匹配：next_r_slot 轮询指向"最早 AR 已发出且 R 未完成"的槽位
- M_AXI_RREADY = (next_r_slot 槽位 R_ACTIVE) && !rd_fifo_full（Data_TX 满反压）
- RLAST 握手 → 槽位 FREE，next_r_slot 前进；R 数据透传 user_rd_data_out（data_out=RVALID 对应拍）

**6. 地址自增**：B 握手（写）后槽位地址 += (len+1)×W；RLAST 握手（读）后同——**修正原 len×W 少 1 拍缺陷**。自增是槽位地址寄存器，供连续写场景（用户也可每次显式给地址）。

**7. 复位**：异步复位，槽位全部 FREE、指针归零、计数清零。

**8. 时序**：全同步单时钟（clk_axi）；组合逻辑为槽位状态译码 + 轮询扫描（≤8 槽，逻辑级低）。

### 方案优劣分析

**优点**：
1. W 串行 + AW 保序 + B 乱序匹配完整覆盖 AXI4 无 WID 约束，协议正确
2. 读通道同 ID 保序：无 ID 路由/缓冲逻辑，R 直接透传，实现最简
3. 轮询指针无饥饿、天然保序，无复杂仲裁
4. MAX=1 时槽位数=1，行为退化为单事务（兼容）
5. 现有 USER 数据接口不变（仅加 ready_start）

**局限**：
1. 写吞吐受 W 串行限制（AW 流水线收益为主）；用户须保证 FIFO 数据顺序 = start 顺序
2. 读要求从机同 ID 保序（AXI 规范保证）；从机乱序返回不支持（out-of-order 独立功能）
3. start 在无空闲槽时被忽略（用户须遵守 ready_start）
4. 槽位数 ≤8（寄存器阵列面积约束）

**量化对比**（MAX=4，8bit 总线）：
| 指标 | 串行（现状） | Outstanding（本方案） |
|------|------------|---------------------|
| 4 个短写事务最小周期 | ~4×(AW+W+B) | AW 流水线重叠，约 1 个 AW+4W+4B |
| 4 个短读事务最小周期 | ~4×(AR+R) | AR 流水线 + R 流水线重叠，约 1×AR+4R |
| 控制逻辑（估） | ~30 FF | ~150 FF（槽位表+指针） |

### 改进与扩展

- out-of-order 读（唯一 ID + RID 路由 + 槽位缓冲）——独立功能，见 out_of_order_design.md
- 写数据交织（AXI3 WID）——AXI4 不支持，不做
- 槽位 FIFO 化（RAM 实现，支持更多槽）——面积优化，未来

## 端口列表（变更部分）

### AXI_FULL_Master_With_USER_Port 新增
| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| user_wr_ready_start | output | 1 | 写通道有空闲槽位（= 可发起新写事务） |
| user_rd_ready_start | output | 1 | 读通道有空闲槽位 |

### axi_wr_master 新增
| 信号 | 方向 | 说明 |
|------|------|------|
| wr_ready_start | output | 有空闲槽位（给顶层） |

### axi_rd_master 新增
| 信号 | 方向 | 说明 |
|------|------|------|
| rd_ready_start | output | 有空闲槽位（给顶层） |

## 参数列表

| 参数 | 默认值 | 范围 | 说明 |
|------|--------|------|------|
| MAX_OUTSTANDING_WR | 4 | 1~8 | 写通道槽位数 |
| MAX_OUTSTANDING_RD | 4 | 1~8 | 读通道槽位数 |
| （沿用）C_M_AXI_ID_WIDTH | 1 | — | AWID 位宽 = clog2(N)+高位补 0 |

## 接口协议与时序

### ready_start 握手规则
- user_wr_ready_start = 存在 FREE 槽位（组合，随槽位状态变化）
- 用户协议：仅在 ready_start=1 时拉高 start；start 与 ready_start 同拍或跨拍均可（start 为单周期脉冲）

### 槽位状态机（写，每槽 2bit）
| 状态 | 编码 | 功能 | 转移条件 | 下一状态 |
|------|------|------|---------|---------|
| FREE | 2'b00 | 空闲 | wr_start（分配） | AW_PEND |
| AW_PEND | 2'b01 | 待发 AW | AW 握手（该槽被 next_aw 选中） | W_DATA |
| W_DATA | 2'b10 | 等待/发送 W（串行调度） | WLAST 握手（该槽被 next_w 选中） | B_WAIT |
| B_WAIT | 2'b11 | 等待 B | B 握手（BID=槽号） | FREE |

### 槽位状态机（读，每槽 2bit）
| 状态 | 编码 | 功能 | 转移条件 | 下一状态 |
|------|------|------|---------|---------|
| FREE | 2'b00 | 空闲 | rd_start（分配） | AR_PEND |
| AR_PEND | 2'b01 | 待发 AR | AR 握手（该槽被 next_ar 选中） | R_ACTIVE |
| R_ACTIVE | 2'b10 | 等待 R 数据 | RLAST 握手（该槽被 next_r 选中） | FREE |

## 工作流程（逐周期示例，MAX_WR=2，两个写事务）

> 注：组合扫描看到的是**前一拍**的槽位状态——wr_start 分配（NBA）与 AW 发起（组合扫描）**至少隔 1 拍**。

```
周期 0：复位释放。槽 0/1 = FREE。ready_start=1。
周期 1：wr_start=1 → 槽 0 = AW_PEND（addr=0x100, len=3）。ready_start 仍=1（槽 1 空闲）。
周期 2：wr_start=1 → 槽 1 = AW_PEND（addr=0x200, len=1）。扫描到槽 0 → AWVALID=1, AWADDR=0x100, AWID=0。
周期 3：AW 握手（AWID=0）→ 槽 0 = W_DATA。next_aw 前进→扫描到槽 1（AW_PEND）→ 锁存 AWADDR=0x200, AWID=1。
        同时 next_w=0（槽 0 W_DATA）且 FIFO 有数据 → WVALID=1, WDATA=FIFO[0]。
周期 4：AW 握手（AWID=1）→ 槽 1 = W_DATA。W 握手拍 1（wr_cnt=1）→ WLAST 条件 wr_cnt==len-1=2? 否。
周期 5：W 握手拍 2（wr_cnt=2）→ WLAST=1 → 握手 → 槽 0 = B_WAIT。next_w 前进→槽 1（W_DATA）。
周期 6：槽 1 W 数据发送（len=1 单拍 → WLAST=1）→ 握手 → 槽 1 = B_WAIT。next_w 前进。
周期 7：从机回 B：BVALID=1, BID=0 → BREADY=1（槽 0 B_WAIT）→ 握手 → 槽 0 = FREE。ready_start=1。
周期 8：BVALID=1, BID=1 → 槽 1 = FREE。ready_start=1。
```

## 边界情况与错误处理

| 边界场景 | 处理 |
|---------|------|
| start 在无空闲槽时到达 | 忽略（ready_start=0 已禁止；防御性不采样不锁存） |
| 背靠背 start（每周期一个） | 槽位依次分配，AW 依次发出（流水线） |
| B 乱序返回（BID 非按序） | BID 直接索引槽位匹配，天然支持 |
| B 在 WLAST 后同拍到达 | 不可能：从机 WLAST 握手后至少 1 拍才置 BVALID（寄存器输出）；BREADY 仅在有 B_WAIT 槽时拉高 |
| 用户 FIFO 数据顺序 ≠ start 顺序 | 用户责任（FR 约束）；W 数据按 FIFO 顺序发出，错序会错配数据 |
| 从机 R 乱序返回（同 ID 违规） | 从机责任；R 按 next_r 顺序匹配会错配（保序方案前提） |
| 单拍事务（len=0） | 槽位立即 WLAST/RLAST，正常 |
| 槽位回绕（连续 2N 个事务） | 轮询指针回绕扫描，旧槽释放后可复用 |
| wr_error 多事务 | 任一槽 B/RESP≠OKAY 置位，新 start 清零（保持现语义） |
| 复位在事务中途 | 槽位全 FREE、指针清零、AXI valid 拉低；在途事务丢弃（从机侧 B/R 挂起由复位后新事务覆盖） |
| MAX_OUTSTANDING=1 | 单槽：退化为串行行为（每次只能 1 个在途事务） |

## 时序波形（关键场景）

### 场景 1：写 2 个事务重叠（MAX=2）
```
wr_start   ─┐ ┌──────────────────
            └─┘ (槽0分配)        (槽1分配)
AWVALID    ────┐  ┌──────────────
               └──┘ (AWID=0)   (AWID=1)
WVALID     ────────┐ ┌ ┌ ┐ ┌────  (W 串行: 事务0 的 4 拍 → 事务1 的 2 拍)
WLAST      ──────────────┐ ┌ ───
BVALID     ────────────────────┐ ┌── (乱序也可)
                             └─┘
```

### 场景 2：读 2 个事务（同 ARID=0，R 保序）
```
rd_start   ─┐ ┌─────────────────
ARVALID    ───┐  ┌──────────────
              └──┘ (ARID=0)   (ARID=0)
RVALID     ────────┐ ┌ ┐ ┌ ┐ ┌─  (R 保序: 事务0 数据 → 事务1 数据)
RLAST      ────────────────┐ ┌─
```

## 资源预估（MAX_WR=MAX_RD=4，8bit 总线）

| 资源 | 估算 | 依据 |
|------|------|------|
| 触发器 | ~400 | 写通道 4 槽×44 位（状态2+地址32+长度8+burst2）=176；读通道 4 槽×42 位=168；指针/锁存/计数 ~50；合计 ~400（地址 32 位占大头） |
| LUT | ~200 | 槽位状态译码 + 轮询扫描（% 参数取模）+ 握手组合 ×2 通道 |
| BRAM | 0 | 全寄存器 |

## 模块调用关系

```
AXI_FULL_Master_With_USER_Port（改动：参数/端口/接线）
├── axi_wr_master（改造：槽位表 + 调度器）
├── axi_rd_master（改造：槽位表 + 调度器）
├── Data_RX（不动）
├── Data_TX（不动）
└── fifo_async（不动）
```

## 各模块详细说明

### rtl/AXI_FULL_Master_With_USER_Port/axi_wr_master.v（改造）
- **功能**：写通道 Outstanding 控制器
- **内部流程**：1.参数(加 MAX_OUTSTANDING_WR) 2.端口(加 wr_ready_start) 3.槽位寄存器阵列 4.槽位分配 5.AW 调度(next_aw) 6.W 调度(next_w) 7.B 匹配 8.错误/地址自增
- **关键寄存器**：slot_state[N×2]、slot_addr[N×32]、slot_len[N×8]、slot_burst[N×2]、next_aw_slot、next_w_slot、wr_cnt
- **关键 always 块**：槽位状态更新（逐槽）、AW 调度组合+时序、W 调度组合、B 匹配

### rtl/AXI_FULL_Master_With_USER_Port/axi_rd_master.v（改造）
- **功能**：读通道 Outstanding 控制器
- **内部流程**：1.参数(加 MAX_OUTSTANDING_RD) 2.端口(加 rd_ready_start) 3.槽位阵列 4.分配 5.AR 调度 6.R 保序匹配 7.错误/地址自增
- **关键寄存器**：slot_state[N×2]、slot_addr、slot_len、next_ar_slot、next_r_slot、rd_cnt
- **关键 always 块**：槽位状态更新、AR 调度、R 匹配

### rtl/AXI_FULL_Master_With_USER_Port/AXI_FULL_Master_With_USER_Port.v（改动）
- **功能**：顶层接线
- **内部流程**：1.参数(MAX_OUTSTANDING_WR/RD) 2.端口(user_wr/rd_ready_start) 3.接线
- **关键连线**：wr_ready_start → user_wr_ready_start 等
