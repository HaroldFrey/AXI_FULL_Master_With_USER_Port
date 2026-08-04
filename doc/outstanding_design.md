# Outstanding 事务支持 — 设计文档

> **状态**: 设计中
> **日期**: 2026-07-23
> **目标**: 支持 Master 同时发起多个未完成事务，提升总线利用率

---

## 1. 背景

当前架构中，`axi_wr_master` 和 `axi_rd_master` 各有一个简单的 2 状态 FSM：
- **写**: IDLE → WRITE → (BVALID) → IDLE
- **读**: IDLE → READ → (RLAST) → IDLE

在 FSM 处于 WRITE/READ 状态期间，新的 `wr_start`/`rd_start` 被忽略（FSM 不响应），导致**串行执行**——每个事务必须等待前一个完成才能发起下一个。

Outstanding 能力允许多个事务同时在 AXI 总线上进行，显著提升吞吐量。

---

## 2. 核心概念

### 2.1 事务生命周期

```
写事务:  wr_start → AW → W_data → B_response → 事务完成
读事务:  rd_start → AR → R_data(RLAST) → 事务完成
```

Outstanding 意味着：

```
写1:  wr_start ──> AW1 ──> W1 ────────────────────> B1 ──>
写2:            wr_start ──> AW2 ──> W2 ──> B2 ──────────>
读1:            rd_start ──> AR1 ─────────────────> R1 ──>
读2:                        rd_start ──> AR2 ──> R2 ──────>

时间 ──────────────────────────────────────────────────────>
      多个事务的 AW/AR 可以交错发出，不必等待前一个完成
```

### 2.2 AXI 协议支持

AXI 协议天然支持 Outstanding：
- 每个事务有独立的 ID（AWID / ARID）
- 从机通过 BID / RID 告知 Master 哪个事务完成了
- W 数据必须在 AW 之后按顺序发送（同一 ID 内）
- 不同 ID 的 W 数据可以交织（需要 WID，但 AXI4 移除了 WID）

**关键约束 — AXI4 无 WID**：AXI4 移除了 WID 信号。这意味着 **W 数据必须严格按 AW 发出顺序传输**，不同事务的 W 数据不能交织。写通道的 Outstanding 实质是"地址流水线"——可以提前发送多个 AW，但 W 数据串行跟随。读通道则无此限制，AR 和 R 均可完全并发。

---

## 3. 设计方案

### 3.1 事务槽 (Transaction Slot)

引入可配置数量的事务槽，每个槽跟踪一个进行中的事务：

```
┌─────────────────────────────────────────────────────────┐
│               Transaction Slot Table                     │
│                                                         │
│  Slot 0: [ID=0] [State: ACTIVE] [addr: 0x100] [len: 4] │
│  Slot 1: [ID=1] [State: ACTIVE] [addr: 0x200] [len: 8] │
│  Slot 2: [ID=x] [State: FREE]                           │
│  Slot 3: [ID=x] [State: FREE]                           │
│                                                         │
│  MAX_OUTSTANDING = 4 (可参数化, 建议 4~8)                │
└─────────────────────────────────────────────────────────┘
```

### 3.2 写通道 FSM 变更

```
当前:  IDLE ←→ WRITE (单事务)

改为:
       ┌────────────────────────────────────────┐
       │           axi_wr_master_v2              │
       │                                         │
       │  wr_start ──> 分配空闲 slot              │
       │              │                          │
       │              ├─> 发送 AW (使用 slot ID)  │
       │              ├─> 等待 W 数据 (FIFO)      │
       │              │                          │
       │  B channel ──> 匹配 BID → 释放 slot     │
       │              └─> 拉高 wr_done (可选)     │
       │                                         │
       │  可同时有 N 个 slot 处于 ACTIVE 状态     │
       └────────────────────────────────────────┘
```

### 3.3 读通道 FSM 变更

```
       ┌────────────────────────────────────────┐
       │           axi_rd_master_v2              │
       │                                         │
       │  rd_start ──> 分配空闲 slot              │
       │              │                          │
       │              └─> 发送 AR (使用 slot ID)  │
       │                                         │
       │  R channel ──> 匹配 RID → 路由数据       │
       │              └─> RLAST → 释放 slot      │
       │                                         │
       │  可同时有 N 个 slot 处于 ACTIVE 状态     │
       └────────────────────────────────────────┘
```

### 3.4 USER Port 接口变更

| 新增信号 | 方向 | 说明 |
|----------|------|------|
| `user_wr_ready_start` | O | Master 是否可以接受新的写事务（有空闲 slot） |
| `user_rd_ready_start` | O | Master 是否可以接受新的读事务（有空闲 slot） |
| `user_wr_id` | I | 写事务 ID（用户指定，可选） |
| `user_rd_id` | I | 读事务 ID（用户指定，可选） |

或者简化——自动分配 ID，用户仅需检查 ready_start：

```verilog
// 用户侧: 仅在 ready_start=1 时拉高 start
if (user_wr_ready_start) begin
    user_wr_start <= 1'b1;
end
```

### 3.5 ID 管理

- 每个 slot 分配一个唯一 ID
- ID 位宽 = `$clog2(MAX_OUTSTANDING)` 即可区分所有 slot
- `AWID = slot_id`，`ARID = slot_id`
- 从机返回 `BID` / `RID` → Master 通过 ID 定位 slot

### 3.6 地址管理

每个 slot 维护自己的地址寄存器：
- AWADDR 随 W 数据传输从 slot 中获取
- 写完成后按 burst 字节数偏移（支持连续写）

---

## 4. 实施策略

考虑到复杂度，建议**分阶段实施**：

| 阶段 | 内容 | 说明 |
|------|------|------|
| Phase 1 | 写 Outstanding (MAX=4) | AW 可流水线发出，W 数据串行（AXI4 无 WID），B 响应乱序匹配 |
| Phase 2 | 读 Outstanding (MAX=4) | AR 可流水线发出，R 数据并发接收（AXI4 允许 R 乱序） |
| Phase 3 | 读写均支持 + 测试 | 完整验证 |

**重要说明**：
- **写通道**：AXI4 无 WID → W 数据只能串行。Outstanding 写的主要收益是 AW 地址流水线。
- **读通道**：AXI4 允许不同 ARID 的 R 数据乱序返回。若所有读事务使用**同一 ARID**，从机必须按序返回 R 数据（Master 实现简单）。若使用**不同 ARID**，Master 需配合 Out-of-Order 支持。

### Phase 1 详细变更（写通道 Outstanding）

1. `axi_wr_master` 内部增加 slot table（寄存器阵列）
2. Slot 状态机：FREE → AW_PENDING → W_DATA → B_PENDING → FREE
3. AW 通道增加仲裁逻辑：哪个 slot 的 AW 先发（按 wr_start 顺序）
4. W 通道增加 slot 选择：当前传输的数据属于哪个 slot
5. B 通道增加 ID 匹配

### Phase 1 的写通道 slot 状态

```
FREE ──wr_start──> AW (发送 AW)
AW   ──AW握手──> W_DATA (等待/发送 W 数据)
W_DATA ──WLAST──> B_WAIT (等待 B 响应)
B_WAIT ──BVALID──> FREE (释放 slot)
```

多个 slot 可同时处于 W_DATA / B_WAIT 状态。

---

## 5. 参数

```verilog
parameter int MAX_OUTSTANDING_WR = 4;   // 写通道最大进行中事务数
parameter int MAX_OUTSTANDING_RD = 4;   // 读通道最大进行中事务数
```

---

## 6. 兼容性

- 默认 MAX_OUTSTANDING = 1 即退化为当前单事务行为
- USER Port 新增 ready_start 信号，旧代码不连接时需适配
- Testbench 需增加并发事务测试用例

---

*待审核。*
