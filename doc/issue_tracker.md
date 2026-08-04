# 问题跟踪文档

> 本文件记录工程代码审查中发现的所有问题，以及解决进度。
> 发现问题后追加到对应章节，解决问题后更新状态与解决方案。

---

## 问题状态说明

| 状态 | 含义 |
|------|------|
| 🔴 待修复 | 已确认，尚未处理 |
| 🟡 进行中 | 正在修复 |
| 🟢 已解决 | 已修复并验证 |
| ⚫ 不予处理 | 评估后决定不修 |

---

## 问题汇总

| 编号 | 严重度 | 位置 | 标题 | 状态 |
|------|--------|------|------|------|
| #1 | 🔴 严重 | `axi_full_master.v:85`, `AXI_FULL_Master_With_USER_Port.v:72` | M_AXI_ARADDR 端口位宽使用错误参数 | 🟢 已解决 |
| #2 | 🟡 中等 | `axi_full_master.v:249-267` | 单拍突发 (wr_len=1) 时 WLAST 未置位 | 🟢 已解决 |
| #3 | 🔵 低 | `axi_full_master.v:305-314` | ARVALID 电平触发存在重复触发风险 | 🟢 已解决 |
| #4 | 🟡 中等 | `axi_full_master.v:130-145,185,201,241,255,259-261,285,300` | 读写长度信号 (wr_len_in / rd_len_in) 未锁存 | 🟢 已解决 |
| #5 | 🔵 低 | `axi_full_master.v:127-128` | rd_cnt / wr_cnt 无外部可观测性 | ⚫ 不予处理 |
| #6 | 🟢 已解决 | `AXI_FULL_Master_With_USER_Port.v:202` | data_out_vld 错误连接至 data_in | 🟢 已解决 |
| #7 | 🟢 已解决 | `axi_full_master.v:283` | 读地址偏移计算错误使用 wr_len_in | 🟢 已解决 |
| #8 | 🟢 已解决 | `axi_full_master.v:310-312` | rd_data_flag else 分支无条件清零 | 🟢 已解决 |
| #9 | 🟡 中等 | `axi_full_master.v:195-206, 297-308` | AWADDR/ARADDR 在复位期间计算，首次访问使用错误地址 | 🟢 已解决 |
| #10 | 🔵 低 | `axi_full_master.v:328` | rd_data_flag 清零条件混用 ARVALID（应为 RVALID） | 🟢 已解决 |
| #11 | 🟡 中等 | `axi_full_master.v:137,150-160` | 同时 wr_start+rd_start 导致两者均被丢弃 | ⚫ 暂不修复 |
| #12 | 🔵 低 | `axi_full_master.v:305` | ARADDR 增量更新仅检查 RLAST 未限定 RVALID | 🟢 已解决 |
| #13 | 🔵 低 | `axi_full_master.v:139-145` | wr_len_latched / rd_len_latched 无复位值 | 🟢 已解决 |
| #14 | 🔴 严重 | `axi_full_master.v:111,117-119` | clogb2(0) 返回 1，DATA_WIDTH=8 时 AxSIZE 错误（声明2字节/拍） | 🟢 已解决 |
| #15 | 🟡 中等 | `axi_full_master.v:247-253` | WVALID 在突发中未检查 FIFO 空，时钟不匹配时写入垃圾数据 | 🟢 已解决 |
| #16 | 🔵 低 | `axi_wr_master.v:35` | wr_data_vld 端口未使用 | 🟢 已解决 |

---

## 问题详情

---

### 1 M_AXI_ARADDR 端口位宽使用错误参数

| 属性 | 内容 |
|------|------|
| **编号** | #1 |
| **严重度** | 🔴 严重 |
| **状态** | 🟢 已解决 |
| **发现日期** | 2026-07-22 |
| **解决日期** | 2026-07-22 |
| **位置** | [axi_full_master.v:85](../rtl/AXI_Full_Master_With_USER_Port/axi_full_master.v#L85), [AXI_FULL_Master_With_USER_Port.v:72](../rtl/AXI_Full_Master_With_USER_Port/AXI_FULL_Master_With_USER_Port.v#L72) |

#### 问题描述

读地址总线 M_AXI_ARADDR 的位宽使用了 `C_M_AXI_RD_LEN_WIDTH`（突发长度位宽，默认 8 bit），而非 `C_M_AXI_ADDR_WIDTH`（地址位宽，默认 32 bit）。

对比写地址端口使用的是正确参数：
```verilog
// axi_full_master.v
output reg [C_M_AXI_ADDR_WIDTH-1 : 0]  M_AXI_AWADDR,  // ✅ 写地址，正确
output reg [C_M_AXI_RD_LEN_WIDTH-1 : 0] M_AXI_ARADDR,  // ❌ 读地址，错误
```

#### 后果

32-bit 地址在综合时被截断为 8-bit，高位地址丢失，读操作必然访问错误地址。默认参数下，地址有效位只有低 8 bit。

#### 修复方案

两个文件中的 M_AXI_ARADDR 声明，位宽从 `C_M_AXI_RD_LEN_WIDTH-1 : 0` 改为 `C_M_AXI_ADDR_WIDTH-1 : 0`：

```verilog
// axi_full_master.v:85
output reg [C_M_AXI_ADDR_WIDTH-1 : 0]  M_AXI_ARADDR,

// AXI_FULL_Master_With_USER_Port.v:72
output [C_M_AXI_ADDR_WIDTH-1 : 0]      M_AXI_ARADDR,
```

#### 解决记录

已手动修复，两个文件中的 M_AXI_ARADDR 位宽均已修正。

---

### 2 单拍突发 (wr_len=1) 时 WLAST 未置位

| 属性 | 内容 |
|------|------|
| **编号** | #2 |
| **严重度** | 🟡 中等 |
| **状态** | 🟢 已解决 |
| **发现日期** | 2026-07-22 |
| **解决日期** | 2026-07-22 |
| **位置** | [axi_full_master.v:249-267](../rtl/AXI_Full_Master_With_USER_Port/axi_full_master.v#L249-L267) |

#### 问题描述

```verilog
if(wr_cnt == wr_len_in-1)          // 分支1: 写完最后一拍 → WLAST=0
    M_AXI_WLAST <= 1'b0;
else if(wr_cnt == wr_len_in-2)     // 分支2: 即将写最后一拍 → WLAST=1
    M_AXI_WLAST <= 1'b1;
```

#### 根因分析

原设计采用**"提前一拍预测"策略**：在倒数第二拍（`wr_cnt == len-2`）将 WLAST 置 1，使其在最后一拍出现在总线上，然后在最后一拍（`wr_cnt == len-1`）清零。

```
len=4:  [D0]  [D1]  [D2]  [D3]      ← 时序正常
         WLAST=0    0   →  1    0    ← D2 握手时将 WLAST 设为 1，D3 时 WLAST=1 ✓

len=1:  [D0]                          ← 单拍突发
         WLAST=0                      ← 没有"倒数第二拍"来做预测！→ 始终为 0 ✗
```

当 `wr_len_in = 1` 时：
- wr_cnt 从 0 开始，只有一个数据拍
- 第一次（也是唯一一次）WVALID & WREADY 握手时，wr_cnt = 0
- `0 == 1-1` → 命中分支1 → WLAST 被设为 0
- WLAST **从未被拉高过**
- 分支2 `wr_cnt == 1-2 = -1`（无符号大数），永远不会命中

**结论：该策略天然要求 len ≥ 2，对单拍突发彻底失效。**

> **注意：** 首次审查时给出的"修复方案"同样存在此问题——它仍然依赖握手后判断且同样先匹配 `wr_cnt == len-1`，对 len=1 无效。该错误方案已废弃，以下为更正后的方案。

#### 后果

AXI4 协议明确要求：**即使是单拍突发，WLAST 也必须为 1**。违反此规范会导致：
- 从机无法识别突发结束，可能等待后续数据而超时
- 写响应通道（B channel）永远不返回 BVALID
- 状态机永远卡在 WRITE 状态（跳回 IDLE 的条件是 `BVALID & BREADY`）

#### 修复方案

单拍突发必须不等握手、在进入 WRITE 状态时就立刻拉高 WLAST。在原有逻辑基础上增加对 `wr_len_in == 1` 的特判：

```verilog
always@(posedge M_AXI_ACLK) begin
    if(M_AXI_ARESETN == 1'b0) begin
        M_AXI_WLAST <= 1'b0;
    end
    // ★ 单拍突发：进入写状态并 FIFO 非空时，立即拉高 WLAST
    else if(state == WRITE && wr_cnt == 0 && wr_len_in == 1 && wr_fifo_empty == 1'b0) begin
        M_AXI_WLAST <= 1'b1;
    end
    else if(M_AXI_WVALID & M_AXI_WREADY) begin
        if(wr_cnt == wr_len_in - 1)
            M_AXI_WLAST <= 1'b0;          // 最后一拍握手完成，清零
        else if(wr_cnt == wr_len_in - 2)
            M_AXI_WLAST <= 1'b1;          // 预测：下一拍是最后一拍
    end
    else begin
        M_AXI_WLAST <= 1'b0;
    end
end
```

**修复逻辑说明：**
- `wr_len_in >= 2`：行为不变，走原有的预测路径（`len-2` 提前拉高 → `len-1` 清零）
- `wr_len_in == 1`：进入 WRITE 状态 + FIFO 非空时立即拉高 WLAST，握手完成后由 `wr_cnt == len-1` 分支清零

#### 解决记录

已修改 [axi_full_master.v:254-256](../rtl/AXI_Full_Master_With_USER_Port/axi_full_master.v#L254-L256)：新增单拍突发特判分支，进入 WRITE 状态且 FIFO 非空时立即将 WLAST 拉高。同时随 #4 修复将 `wr_len_in` 替换为锁存值 `wr_len_latched`。

---

### 3 ARVALID 电平触发存在重复触发风险

| 属性 | 内容 |
|------|------|
| **编号** | #3 |
| **严重度** | 🔵 低 |
| **状态** | 🟢 已解决 |
| **发现日期** | 2026-07-22 |
| **解决日期** | 2026-07-22 |
| **位置** | [axi_full_master.v:305-314](../rtl/AXI_Full_Master_With_USER_Port/axi_full_master.v#L305-L314) |

#### 问题描述

ARVALID 使用 `state == READ` 电平触发，而 AWVALID 使用 `wr_start` 脉冲触发，两者设计风格不一致：

```verilog
// AWVALID（写地址）—— 脉冲触发，只拉高一次 ✓
else if(M_AXI_AWREADY & M_AXI_AWVALID)
    M_AXI_AWVALID <= 1'b0;
else if(wr_start == 1'b1)               // 单周期脉冲
    M_AXI_AWVALID <= 1'b1;

// ARVALID（读地址）—— 电平触发，存在重复风险 ⚠
else if(M_AXI_ARREADY & M_AXI_ARVALID)
    M_AXI_ARVALID <= 1'b0;
else if(state == READ)                  // 整个 READ 状态持续有效
    M_AXI_ARVALID <= 1'b1;
```

#### 触发条件分析

如果从机在 READ 状态期间保持 ARREADY = 1，则每个周期都会发生 AR 握手：

```
Cycle:    T0     T1     T2     T3
state         │ READ │ READ │ READ │
ARVALID       │  1   │  0   │  1   │  ← 反复拉高
ARREADY       │  1   │  1   │  1   │
              │ 握手 │ 握手 │ 握手 │  ← 发出 3 次读事务！
```

#### 当前环境是否触发？

查看当前仿真使用的 [axi_full_slave.v](../rtl/axi_full_slave.v) 从机：

```verilog
// Line 419-420: ARREADY 拉高同时锁住标志
if (~axi_arready && S_AXI_ARVALID && ~axi_awv_awr_flag && ~axi_arv_arr_flag)
    axi_arready <= 1'b1;
    axi_arv_arr_flag <= 1'b1;   // ★ 锁住，阻止再次响应 AR

// Line 424-425: 读事务全部完成后才释放
else if (axi_rvalid && S_AXI_RREADY && axi_arlen_cntr == axi_arlen)
    axi_arv_arr_flag  <= 1'b0;  // 突发全部完成后才清零
```

**当前从机在 AR 握手后立即锁住 `arv_arr_flag`，直到整笔读突发完成后才释放。因此配合此从机时，问题不会触发。**

#### 为什么仍是问题？

Master 的设计不应依赖特定从机行为来保证正确性。如果对接以下类型的从机：
- 支持 Outstanding 的高性能从机（ARREADY 保持高）
- 标准 AXI Interconnect（可以缓存多个 AR 事务）

Master 会意外发出多次重复的 AR 事务。

#### 严重度说明

| 因素 | 评估 |
|------|------|
| 当前仿真环境 | 不触发（从机有互斥保护） |
| 常见简单从机 | 大概率不触发 |
| 高性能/Outstanding 从机 | 会触发 |
| 修复难度 | 极低（改一行为脉冲触发） |

综合考虑：**严重度从 🟡 中等降为 🔵 低**——设计鲁棒性缺陷，当前不阻塞功能，但建议修复以提升可移植性。

#### 修复方案

参考 AWVALID 的写法，将 ARVALID 也改为脉冲触发：

```verilog
else if(M_AXI_ARREADY & M_AXI_ARVALID)
    M_AXI_ARVALID <= 1'b0;
else if(rd_start == 1'b1)           // ★ 脉冲触发，与 AWVALID 一致
    M_AXI_ARVALID <= 1'b1;
```

#### 解决记录

已修改 [axi_full_master.v:312](../rtl/AXI_Full_Master_With_USER_Port/axi_full_master.v#L312)：将 `state == READ`（电平触发）改为 `rd_start == 1'b1`（脉冲触发），与 AWVALID 逻辑保持一致。

---

### 4 读写长度信号 (wr_len_in / rd_len_in) 未锁存

| 属性 | 内容 |
|------|------|
| **编号** | #4 |
| **严重度** | 🟡 中等 |
| **状态** | 🟢 已解决 |
| **发现日期** | 2026-07-22 |
| **解决日期** | 2026-07-22 |
| **位置** | [axi_full_master.v:130-145,185,201,241,255,259-261,285,300](../rtl/AXI_Full_Master_With_USER_Port/axi_full_master.v) |

#### 问题描述

`wr_len_in` 和 `rd_len_in` 在整个突发传输期间被直接使用（如 AWLEN 赋值、地址偏移计算、wr_cnt 比较），但这些信号来自外部用户逻辑，在突发传输进行期间可能发生变化。

例如：
```verilog
assign M_AXI_AWLEN = wr_len_in - 1;                    // 实时取值
M_AXI_AWADDR <= M_AXI_AWADDR + (wr_len_in * ...);      // 实时取值
if((wr_cnt == wr_len_in-1) && (M_AXI_WVALID & ...))    // 实时比较
```

#### 后果

如果用户在突发传输进行中错误地修改了 `wr_len_in` / `rd_len_in`（即使设计规范不允许这样做，但硬件缺乏保护），将导致：
- 地址偏移计算错误
- 突发长度判断错误，WLAST/RREADY 时序紊乱
- 写响应等待错误的拍数

#### 修复方案

在 `wr_start` / `rd_start` 时锁存长度值到内部寄存器：

```verilog
reg [C_M_AXI_WR_LEN_WIDTH-1 : 0] wr_len_latched;
reg [C_M_AXI_RD_LEN_WIDTH-1 : 0] rd_len_latched;

always@(posedge M_AXI_ACLK) begin
    if(wr_start)
        wr_len_latched <= wr_len_in;
    if(rd_start)
        rd_len_latched <= rd_len_in;
end
```

然后将后续所有使用 `wr_len_in` / `rd_len_in` 的地方替换为锁存版本。

#### 解决记录

已修改 [axi_full_master.v](../rtl/AXI_Full_Master_With_USER_Port/axi_full_master.v)：
1. **L130-132**：新增 `wr_len_latched` 和 `rd_len_latched` 寄存器
2. **L139-145**：新增 always 块，在 `wr_start` / `rd_start` 脉冲时锁存长度值
3. 全部 7 处 `wr_len_in` / `rd_len_in` 引用替换为锁存版本：
   - `M_AXI_AWLEN` (L185) → `wr_len_latched`
   - `M_AXI_AWADDR` 偏移 (L201) → `wr_len_latched`
   - `WVALID` 拉低判断 (L241) → `wr_len_latched`
   - `WLAST` 逻辑 (L255, L259-261) → `wr_len_latched`
   - `M_AXI_ARLEN` (L285) → `rd_len_latched`
   - `M_AXI_ARADDR` 偏移 (L300) → `rd_len_latched`

---

### 5 rd_cnt / wr_cnt 无外部可观测性

| 属性 | 内容 |
|------|------|
| **编号** | #5 |
| **严重度** | 🔵 低 |
| **状态** | ⚫ 不予处理 |
| **发现日期** | 2026-07-22 |
| **决策日期** | 2026-07-22 |
| **位置** | [axi_full_master.v:127-128](../rtl/AXI_Full_Master_With_USER_Port/axi_full_master.v#L127-L128) |

#### 问题描述

`wr_cnt` 和 `rd_cnt` 是 32-bit 内部寄存器，仅用于模块内部逻辑控制（WLAST 判断、WVALID 拉低等），没有输出到模块端口。在仿真调试或 IL A 观测时不可访问。

#### 后果

- 仿真时无法直接观察当前突发传输的进度
- 上板调试时无法用 ILA 抓取计数器值
- 影响不大，属于可维护性问题

#### 决策记录

不予处理。理由：

- 计数器输出会增加模块端口，对面积和时序有轻微影响
- 仿真调试时可用 `$display` 或波形窗口直接观察内部信号
- 上板调试如需观测，可通过 ILA 直接探入模块内部信号
- 功能性影响为零，属于纯调试便利性问题

---

### 6 data_out_vld 错误连接至 data_in

| 属性 | 内容 |
|------|------|
| **编号** | #6 |
| **严重度** | 🟢 已解决 |
| **状态** | 🟢 已解决 |
| **发现日期** | 2026-07-22 |
| **解决日期** | 2026-07-22 |
| **位置** | [AXI_FULL_Master_With_USER_Port.v:202](../rtl/AXI_Full_Master_With_USER_Port/AXI_FULL_Master_With_USER_Port.v#L202) |

#### 问题描述

顶层模块中 `axi_full_master` 实例化时，`data_out_vld` 端口错误连接到了 `data_in`（数据总线）而非 `data_in_vld`（有效标志）。

#### 修复

```verilog
// 修复前
.data_out_vld   (data_in),

// 修复后
.data_out_vld   (data_in_vld),
```

---

### 7 读地址偏移计算错误使用 wr_len_in

| 属性 | 内容 |
|------|------|
| **编号** | #7 |
| **严重度** | 🟢 已解决 |
| **状态** | 🟢 已解决 |
| **发现日期** | 2026-07-22 |
| **解决日期** | 2026-07-22 |
| **位置** | [axi_full_master.v:283](../rtl/AXI_Full_Master_With_USER_Port/axi_full_master.v#L283) |

#### 问题描述

读地址偏移计算使用了写突发长度 `wr_len_in` 而非读突发长度 `rd_len_in`：
```verilog
M_AXI_ARADDR <= M_AXI_ARADDR + (wr_len_in * C_M_AXI_DATA_WIDTH/8);
```

#### 修复

```verilog
// 修复后
M_AXI_ARADDR <= M_AXI_ARADDR + (rd_len_in * C_M_AXI_DATA_WIDTH/8);
```

---

### 8 rd_data_flag else 分支无条件清零

| 属性 | 内容 |
|------|------|
| **编号** | #8 |
| **严重度** | 🟢 已解决 |
| **状态** | 🟢 已解决 |
| **发现日期** | 2026-07-22 |
| **解决日期** | 2026-07-22 |
| **位置** | [axi_full_master.v:310-312](../rtl/AXI_Full_Master_With_USER_Port/axi_full_master.v#L310-L312) |

#### 问题描述

`rd_data_flag` 的 else 分支原先无条件清零：
```verilog
else begin
    rd_data_flag <= 1'b0;   // 无条件清零，导致 RREADY 无法保持
end
```

当 AR 握手完成后，在 `rd_data_flag` 应保持为 1 的窗口期内，其他条件均不满足时该寄存器被清零，导致 RREADY 异常拉低，读数据接收中断。

#### 修复

```verilog
// 修复后
else begin
    rd_data_flag <= rd_data_flag;  // 保持当前值
end
```

---

### 9 AWADDR/ARADDR 在复位期间计算，首次访问可能使用错误地址

| 属性 | 内容 |
|------|------|
| **编号** | #9 |
| **严重度** | 🟡 中等 |
| **状态** | 🟢 已解决 |
| **发现日期** | 2026-07-22 |
| **解决日期** | 2026-07-22 |
| **位置** | [axi_full_master.v:195-206](../rtl/AXI_Full_Master_With_USER_Port/axi_full_master.v#L195-L206), [axi_full_master.v:297-308](../rtl/AXI_Full_Master_With_USER_Port/axi_full_master.v#L297-L308) |

#### 问题描述

AWADDR 和 ARADDR 的初始值在复位期间计算，而非在 `wr_start` / `rd_start` 脉冲时锁存：

```verilog
// AWADDR — 复位时从外部信号采样地址
always@(posedge M_AXI_ACLK)begin
    if(M_AXI_ARESETN==1'b0)begin
        M_AXI_AWADDR <= C_M_TARGET_SLAVE_BASE_ADDR + wr_addr_in;  // ← 复位期间采样！
    end
    else if(M_AXI_BREADY & M_AXI_BVALID)begin
        M_AXI_AWADDR <= M_AXI_AWADDR + (wr_len_latched * C_M_AXI_DATA_WIDTH/8);
    end
end

// ARADDR — 同样的问题
always@(posedge M_AXI_ACLK)begin
    if(M_AXI_ARESETN==1'b0)begin
        M_AXI_ARADDR <= C_M_TARGET_SLAVE_BASE_ADDR + rd_addr_in;  // ← 复位期间采样！
    end
    else if(M_AXI_RLAST)begin
        M_AXI_ARADDR <= M_AXI_ARADDR + (rd_len_latched * C_M_AXI_DATA_WIDTH/8);
    end
end
```

**时序分析**：

```
复位期间:
  rst_n = 0, user_wr_addr = X (不确定/复位值)
  AWADDR 持续采样: BASE + X

复位释放:
  rst_n = 1, AWADDR 锁存为 BASE + X_reset

用户设置地址:
  user_wr_addr = NEW_ADDR (期望值)

用户拉高 wr_start:
  AWADDR 仍然是 BASE + X_reset  ← 错误！
```

#### 当前是否触发？

当 `wr_addr_in`/`rd_addr_in` 通过参数固定为 0 时（如 `Data_send` 中 `WR_ADDR=0`），`BASE + 0 = BASE` 恰为正确值，**当前测试不触发**。

但若用户使用非零偏移地址（如 `WR_ADDR=0x100`），且该地址在复位期间和 `wr_start` 之间发生变化，首次写/读将访问错误地址。

#### 后果

- 非零偏移地址的首次访问定向到错误位置
- 连续多次访问中，后续地址通过偏移累加同样错误
- 当前 Testbench（`WR_ADDR=RD_ADDR=0`）不受影响

#### 修复方案

将地址初始化从复位分支改为 `wr_start`/`rd_start` 脉冲触发：

```verilog
// AWADDR
always@(posedge M_AXI_ACLK)begin
    if(M_AXI_ARESETN==1'b0)begin
        M_AXI_AWADDR <= C_M_TARGET_SLAVE_BASE_ADDR;
    end
    else if(wr_start)begin
        M_AXI_AWADDR <= C_M_TARGET_SLAVE_BASE_ADDR + wr_addr_in;  // ★ 在 start 时锁存
    end
    else if(M_AXI_BREADY & M_AXI_BVALID)begin
        M_AXI_AWADDR <= M_AXI_AWADDR + (wr_len_latched * C_M_AXI_DATA_WIDTH/8);
    end
end

// ARADDR — 同样处理
always@(posedge M_AXI_ACLK)begin
    if(M_AXI_ARESETN==1'b0)begin
        M_AXI_ARADDR <= C_M_TARGET_SLAVE_BASE_ADDR;
    end
    else if(rd_start)begin
        M_AXI_ARADDR <= C_M_TARGET_SLAVE_BASE_ADDR + rd_addr_in;  // ★ 在 start 时锁存
    end
    else if(M_AXI_RLAST)begin
        M_AXI_ARADDR <= M_AXI_ARADDR + (rd_len_latched * C_M_AXI_DATA_WIDTH/8);
    end
end
```

**注意**：此修复与 #4（长度锁存）设计思路一致——在 `start` 脉冲时锁存外部输入，确保传输期间稳定。

#### 解决记录

已修改 [axi_full_master.v](../rtl/AXI_Full_Master_With_USER_Port/axi_full_master.v)：
1. **AWADDR (L195-206)**：复位时初始化为 `BASE_ADDR`；`wr_start` 脉冲时锁存 `BASE_ADDR + wr_addr_in`；写突发完成后累加偏移。
2. **ARADDR (L297-308)**：复位时初始化为 `BASE_ADDR`；`rd_start` 脉冲时锁存 `BASE_ADDR + rd_addr_in`；读突发完成后累加偏移。

---

### 10 rd_data_flag 清零条件混用 ARVALID（应为 RVALID）

| 属性 | 内容 |
|------|------|
| **编号** | #10 |
| **严重度** | 🔵 低 |
| **状态** | 🟢 已解决 |
| **发现日期** | 2026-07-22 |
| **解决日期** | 2026-07-22 |
| **位置** | [axi_full_master.v:328](../rtl/AXI_Full_Master_With_USER_Port/axi_full_master.v#L328) |

#### 问题描述

```verilog
always@(posedge M_AXI_ACLK)begin
    if(M_AXI_ARESETN==1'b0)begin
        rd_data_flag <= 1'b0;
    end
    else if(M_AXI_RLAST && M_AXI_ARVALID) begin  // ← ARVALID ？应该是 RVALID
        rd_data_flag <= 1'b0;
    end
    else if(M_AXI_ARREADY & M_AXI_ARVALID)
        rd_data_flag <= 1'b1;
    else begin
        rd_data_flag <= rd_data_flag;
    end
end
```

`rd_data_flag` 用于表示"读数据窗口"是否打开：AR 握手完成后置 1，读突发完成后应清零。但清零条件使用了 `M_AXI_RLAST && M_AXI_ARVALID`，其中 ARVALID 是**读地址通道**的信号，RLAST 是**读数据通道**的信号。

**时序矛盾**：

```
AR 握手 → ARVALID 拉低（当前 #3 修复后为单周期脉冲）
       ↓
   [数据阶段]  ARVALID=0, RVALID=1, 数据流动...
       ↓
   RLAST=1 到达 → M_AXI_RLAST(1) && M_AXI_ARVALID(0) = 0
       ↓
   rd_data_flag 永远不清零！ ← BUG
```

#### 当前是否有功能影响？

**无直接影响**。因为：
1. RREADY 的拉低由 `M_AXI_RLAST` 直接控制（[L338](../rtl/AXI_Full_Master_With_USER_Port/axi_full_master.v#L338)），不依赖 `rd_data_flag`
2. `rd_data_flag` 仅用于在 AR 握手后拉高 RREADY，RREADY 有独立清零路径
3. 下次读操作时 `rd_data_flag` 已为 1，AR 握手后再次置 1（无变化），行为等价

**但存在隐患**：`rd_data_flag` 语义上应在读完成后清零，当前"永久置 1"的行为是巧合下的正确。若未来代码修改依赖 `rd_data_flag` 的低电平状态（如读空闲检测），将引入隐藏 bug。

#### 修复方案

将清零条件改为读数据通道信号：

```verilog
else if(M_AXI_RLAST && M_AXI_RVALID) begin  // ★ 使用 RVALID 替代 ARVALID
    rd_data_flag <= 1'b0;
end
```

#### 解决记录

已修改 [axi_full_master.v:328](../rtl/AXI_Full_Master_With_USER_Port/axi_full_master.v#L328)：清零条件从 `M_AXI_RLAST && M_AXI_ARVALID` 改为 `M_AXI_RLAST && M_AXI_RVALID`。

---

### 11 同时 wr_start + rd_start 导致两者均被丢弃

| 属性 | 内容 |
|------|------|
| **编号** | #11 |
| **严重度** | 🟡 中等 |
| **状态** | ⚫ 暂不修复 |
| **发现日期** | 2026-07-22 |
| **位置** | [axi_full_master.v:137,150-160](../rtl/AXI_Full_Master_With_USER_Port/axi_full_master.v#L137) |

#### 问题描述

```verilog
assign state_flag = {wr_start, rd_start};   // 同时为 1 → 2'b11

IDLE :
    if(state_flag == 2'b10)       // 2'b11 != 2'b10 → 跳过写
        state <= WRITE;
    else if(state_flag == 2'b01)  // 2'b11 != 2'b01 → 跳过读
        state <= READ;
    else                          // ★ 落入此处
        state <= IDLE;            // 两个请求均被丢弃！
```

状态跳转条件使用 `==` 精确匹配，当 `wr_start` 和 `rd_start` 在同一周期均为 1 时，`state_flag = 2'b11`，不匹配任何跳转条件，FSM 停留在 IDLE。更严重的是：ARVALID/AWVALID 使用 `rd_start`/`wr_start` 脉冲触发（#3 修复后），地址也由 `rd_start`/`wr_start` 锁存（#9 修复后），**这些硬件会在该周期锁存地址、发出 valid 脉冲，但 FSM 不会响应**，导致地址和 valid 脉冲被浪费。

#### 当前是否触发？

当前 Testbench 中 `write_start` 和 `read_start` 相隔 3000ns，**不触发**。

#### 修复方案

增加 `2'b11` 的处理分支，或改用优先级编码：

```verilog
IDLE :
    if(state_flag[1])             // wr_start 优先
        state <= WRITE;
    else if(state_flag[0])        // rd_start
        state <= READ;
    else
        state <= IDLE;
```

或显式增加双请求分支（如优先写）：

```verilog
IDLE :
    if(state_flag == 2'b10 || state_flag == 2'b11)
        state <= WRITE;
    else if(state_flag == 2'b01)
        state <= READ;
    else
        state <= IDLE;
```

#### 决策记录

暂不修复。理由：

- 当前模块不支持读写同时进行，FSM 天然只会在 WRITE 或 READ 单一状态
- 用户接口规范为“每进行一次写/读操作拉高一次”，不会同时拉高
- 后续计划支持同时读写时一并修复

---

### 12 ARADDR 增量更新仅检查 RLAST 未限定 RVALID

| 属性 | 内容 |
|------|------|
| **编号** | #12 |
| **严重度** | 🔵 低 |
| **状态** | 🟢 已解决 |
| **发现日期** | 2026-07-22 |
| **解决日期** | 2026-07-22 |
| **位置** | [axi_full_master.v:305](../rtl/AXI_Full_Master_With_USER_Port/axi_full_master.v#L305) |

#### 问题描述

```verilog
// ARADDR 增量 (L305) — 仅检查 RLAST
else if(M_AXI_RLAST)begin
    M_AXI_ARADDR <= M_AXI_ARADDR + (rd_len_latched * C_M_AXI_DATA_WIDTH/8);
end

// 对比 FSM 跳转 (L169) — 同时检查 RLAST 和 RVALID
READ :
    if(M_AXI_RLAST && M_AXI_RVALID)
        state <= IDLE;
```

AXI 协议规定 RLAST 仅在 RVALID=1 时有意义。FSM 正确使用了 `RLAST && RVALID`，但 ARADDR 增量逻辑仅使用了 RLAST。

#### 后果

- 正常操作中无影响（RLAST 总伴随 RVALID）
- 若从机异常（不符合协议），ARADDR 可能被误触发增量
- 设计风格不一致

#### 修复方案

```verilog
else if(M_AXI_RLAST && M_AXI_RVALID)begin
    M_AXI_ARADDR <= M_AXI_ARADDR + (rd_len_latched * C_M_AXI_DATA_WIDTH/8);
end
```

#### 解决记录

已修改 [axi_full_master.v:305](../rtl/AXI_Full_Master_With_USER_Port/axi_full_master.v#L305)：从 `M_AXI_RLAST` 改为 `M_AXI_RLAST && M_AXI_RVALID`，与 FSM 跳转条件保持一致。

---

### 13 wr_len_latched / rd_len_latched 无复位值

| 属性 | 内容 |
|------|------|
| **编号** | #13 |
| **严重度** | 🔵 低 |
| **状态** | 🟢 已解决 |
| **发现日期** | 2026-07-22 |
| **解决日期** | 2026-07-22 |
| **位置** | [axi_full_master.v:139-145](../rtl/AXI_Full_Master_With_USER_Port/axi_full_master.v#L139-L145) |

#### 问题描述

```verilog
always@(posedge M_AXI_ACLK) begin
    if(wr_start)
        wr_len_latched <= wr_len_in;
    if(rd_start)
        rd_len_latched <= rd_len_in;
end
```

这两个寄存器没有复位逻辑。`M_AXI_AWLEN` 和 `M_AXI_ARLEN` 通过组合逻辑使用它们：

```verilog
assign M_AXI_AWLEN = wr_len_latched - 1;  // 复位前 = X - 1 = X
assign M_AXI_ARLEN = rd_len_latched - 1;  // 复位前 = X - 1 = X
```

#### 后果

- FPGA 硬件中：大多数 FPGA 寄存器上电初始化为 0，功能正常
- 仿真中：X 态传播到 AWLEN/ARLEN，导致波形中不可读（但因 AWVALID/ARVALID=0，从机不会采样）
- 对功能无实质性影响，但降低仿真可读性

#### 修复方案

在 FSM 的复位分支中增加初始化：

```verilog
always@(posedge M_AXI_ACLK) 
    if(M_AXI_ARESETN == 1'b0) begin
        state <= IDLE ;
        wr_len_latched <= 0;   // ★ 新增
        rd_len_latched <= 0;   // ★ 新增
    end
    else ...
```

#### 解决记录

已修改 [axi_full_master.v:147-151](../rtl/AXI_Full_Master_With_USER_Port/axi_full_master.v#L147-L151)：在 FSM 复位分支中增加 `wr_len_latched <= 0` 和 `rd_len_latched <= 0`。

---

### 14 clogb2(0) 返回 1，DATA_WIDTH=8 时 AxSIZE 错误

| 属性 | 内容 |
|------|------|
| **编号** | #14 |
| **严重度** | 🔴 严重 |
| **状态** | 🟢 已解决 |
| **发现日期** | 2026-07-22 |
| **解决日期** | 2026-07-23 |
| **位置** | [axi_full_master.v:111,117-119](../rtl/AXI_Full_Master_With_USER_Port/axi_full_master.v#L111) |

#### 问题描述

```verilog
localparam SIZE = clogb2(C_M_AXI_DATA_WIDTH/8-1);

function integer clogb2(input integer depth);begin
    if(depth == 0)
        clogb2 = 1;    // ← 应为 0
```

当默认 `DATA_WIDTH=8` 时：`SIZE = clogb2(8/8-1) = clogb2(0) = 1`。
`M_AXI_AWSIZE = 3'b001`，即 **2 字节/拍 (2¹ = 2)**。但数据总线仅 8 bit = **1 字节**。

#### AXI 协议影响

| 信号 | 实际值 | 应为 |
|------|--------|------|
| AWSIZE / ARSIZE | 3'b001 (2 bytes) | 3'b000 (1 byte) |
| WSTRB 位宽 | 1 bit | 1 bit |
| 数据总线 | 8 bit | 8 bit |

AxSIZE 声称 2 字节/拍，但：
- WSTRB 只有 1 位（按 1 字节正确生成）
- 数据总线只有 8 位

这违反 AXI4 规范：**AxSIZE 定义每次数据传输的字节数，必须 ≤ 数据总线宽度**。

#### 当前为何未触发？

slave 端存在对称偏差——`ADDR_LSB` 公式在 8-bit 时也偏大 1：

```verilog
// axi_full_slave.v
localparam ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1;  // 8/32+1 = 1
```

slave 的 `ADDR_LSB=1` 强制 bit 0 为 0（2 字节对齐），恰好与 master 的 `AxSIZE=1`（2 字节/拍）一致。两者偏差相互抵消，BRAM 读写正确。

**但此 Master 连接标准 AXI 从机时会失败**——从机会认为每拍传输 2 字节，而总线只能提供 1 字节。

#### 各 DATA_WIDTH 下的正确性

| DATA_WIDTH | clogb2 输入 | clogb2 输出 | AxSIZE | 正确 AxSIZE | 是否正确 |
|------------|-------------|-------------|--------|-------------|----------|
| 8 | 0 | **1** | 1 (2B) | 0 (1B) | ❌ |
| 16 | 1 | 1 | 1 (2B) | 1 (2B) | ✅ |
| 32 | 3 | 2 | 2 (4B) | 2 (4B) | ✅ |
| 64 | 7 | 3 | 3 (8B) | 3 (8B) | ✅ |

**仅 DATA_WIDTH=8（默认值）受影响。**

#### 修复方案

```verilog
function integer clogb2(input integer depth);begin
    if(depth == 0)
        clogb2 = 0;    // ★ 修复：0 需要 0 bit 表示
```

#### 解决记录

已修改 [axi_full_master.v:119](../rtl/AXI_Full_Master_With_USER_Port/axi_full_master.v#L119)：`clogb2 = 0`（原为 `clogb2 = 1`）。修复后 DATA_WIDTH=8 时 AxSIZE=0（1字节/拍），符合 AXI 规范。

---

---

### 15 WVALID 在突发传输中未受 FIFO 空标志控制

| 属性 | 内容 |
|------|------|
| **编号** | #15 |
| **严重度** | 🟡 中等 |
| **状态** | 🟢 已解决 |
| **发现日期** | 2026-07-23 |
| **解决日期** | 2026-07-23 |
| **位置** | [axi_full_master.v:247-253](../rtl/AXI_Full_Master_With_USER_Port/axi_full_master.v#L247-L253) |

#### 问题描述

```verilog
// WVALID 仅在进入 WRITE 时判断一次 FIFO 非空
else if((wr_fifo_empty == 1'b0) & (state == WRITE))
    M_AXI_WVALID <= 1'b1;

// 拉低条件仅在最后一拍
else if((wr_cnt == wr_len_latched-1) && (M_AXI_WVALID & M_AXI_WREADY))
    M_AXI_WVALID <= 1'b0;
```

WVALID 一旦拉高，在整个突发传输期间不再检查 `wr_fifo_empty`。当 AXI 时钟快于写数据源时钟（clk_axi > clk_wr）时，FIFO 可能被读空：

```
突发中途 FIFO 变空:
  WVALID=1, WREADY=1 → 握手成立
  data_rd_en = 1 & 1 & 0 = 0 (FIFO 空)
  WDATA = 0x00 (mux 默认值) → 垃圾数据写入从机！
```

#### 触发条件

| 因素 | 说明 |
|------|------|
| 时钟频率 | clk_axi > clk_wr（AXI 读取快于数据源写入） |
| FIFO 深度 | 32，突发长度 16 — 缓冲有限 |
| 当前 Testbench | 等频场景（100MHz）不触发 |

#### 后果

- FIFO 读空后，每个 AXI 写握手传输 0x00（而非实际数据）
- 从机 BRAM 被写入错误数据
- 读回时数据校验失败

#### 修复方案

WVALID 增加 FIFO 空的反压条件：

```verilog
// 拉高条件不变
else if((wr_fifo_empty == 1'b0) & (state == WRITE))
    M_AXI_WVALID <= 1'b1;
// ★ 新增：FIFO 空时立即拉低，暂停传输
else if(wr_fifo_empty == 1'b1)
    M_AXI_WVALID <= 1'b0;
// 最后一拍拉低（保留）
else if((wr_cnt == wr_len_latched-1) && (M_AXI_WVALID & M_AXI_WREADY))
    M_AXI_WVALID <= 1'b0;
```

#### 解决记录

已修改 [axi_full_master.v:250-252](../rtl/AXI_Full_Master_With_USER_Port/axi_full_master.v#L250-L252)：在最后一拍清零和拉高条件之间新增 `wr_fifo_empty == 1'b1` 分支，FIFO 为空时立即拉低 WVALID 暂停传输。

---

### 16 axi_wr_master 中 wr_data_vld 端口未使用

| 属性 | 内容 |
|------|------|
| **编号** | #16 |
| **严重度** | 🔵 低 |
| **状态** | 🟢 已解决 |
| **发现日期** | 2026-07-23 |
| **解决日期** | 2026-07-23 |
| **位置** | [axi_wr_master.v:35](../rtl/AXI_Full_Master_With_USER_Port/axi_wr_master.v#L35) |

#### 问题描述

`axi_wr_master.v` 声明了 `wr_data_vld` 输入端口，但模块内部未使用该信号。此情况继承自原 `axi_full_master.v`（同样声明但未使用）。

#### 解决记录

从 `axi_wr_master.v`、`Data_RX.v`、`AXI_FULL_Master_With_USER_Port.v` 三处移除了 `wr_data_vld` 端口及相关连接。

---

## 变更记录

| 日期 | 变更内容 |
|------|----------|
| 2026-07-22 | 初始创建，记录 #1 ~ #8 共 8 个问题。其中 #6/#7/#8 已解决。 |
| 2026-07-22 | #1 手动修复（M_AXI_ARADDR 位宽修正）；#3 严重度降为 🔵 低（增加触发条件分析）。 |
| 2026-07-22 | #2/#3/#4 代码修复完成；#5 决策为不予处理。 |
| 2026-07-22 | 新增 #9/#10。修复完成。 |
| 2026-07-22 | 新增 #11/#12/#13。#11 暂不修复；#12/#13 修复完成。 |
| 2026-07-22 | 新增 #14。修复完成。 |
| 2026-07-23 | 新增 #15。修复完成。 |
| 2026-07-23 | v2 重构：`axi_full_master` → `axi_wr_master` + `axi_rd_master`。#11 自然解决。新增 #16（wr_data_vld 未使用）。 |
| 2026-07-23 | #16 修复完成。新增 `fifo_async.v`（FWFT/Standard 双模式），替换 Vivado FIFO IP。Data_RX/Data_TX 实例化更新。 |
| 2026-07-23 | v3 突发类型扩展：支持 FIXED/INCR/WRAP。新增 `user_wr/rd_burst_type` 端口，默认 INCR 向后兼容。 |
| 2026-07-23 | 新增错误响应处理（BRESP/RRESP 检测，`user_wr/rd_error` 输出）。USER 端口可配置（AWUSER/WUSER/ARUSER）。 |
