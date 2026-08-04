# Out-of-Order 响应支持 — 设计文档

> **状态**: 设计中
> **日期**: 2026-07-23
> **目标**: 支持从机以任意顺序返回读写响应，Master 通过 ID 正确匹配

---

## 1. 背景

当前架构中，Master 假设响应按事务发起顺序返回。但在支持 Outstanding 后，从机可能以不同顺序完成事务：

```
发起顺序:  AR(ID=0) → AR(ID=1) → AR(ID=2)
返回顺序:  R(ID=1) → R(ID=2) → R(ID=0)   ← Out-of-Order
```

Master 必须通过 RID/BID 匹配响应到正确的发起事务，而非依赖顺序。

---

## 2. Out-of-Order 的前提条件

Out-of-Order 需要 Outstanding 支持：
1. 多个事务同时进行中（每个有唯一 ID）
2. 从机返回 BID/RID 来标识哪个事务完成
3. Master 根据 ID 路由响应数据

**关键点**：Out-of-Order 是 Outstanding 的自然延伸——如果 Master 已经通过 ID 跟踪多个事务，那么响应顺序就不再重要。

---

## 3. 读通道 Out-of-Order 的挑战

读通道 Out-of-Order 是最复杂的场景：

```
Master 发起:  AR(ID=0, addr=0x100, len=4)  期望数据: D0_0 D0_1 D0_2 D0_3
              AR(ID=1, addr=0x200, len=4)  期望数据: D1_0 D1_1 D1_2 D1_3

Slave 返回:   R(ID=1): D1_0 D1_1 D1_2 D1_3 (RLAST)
              R(ID=0): D0_0 D0_1 D0_2 D0_3 (RLAST)
```

**问题**：用户期望按发起顺序接收数据（先 ID=0 的数据，后 ID=1 的数据），但实际收到了交错的数据。

### 3.1 方案 A：重排序缓冲 (Reorder Buffer)

```
R channel ──> [ID 匹配] ──> [Per-ID Buffer] ──> [顺序输出] ──> USER Port
```

- 每个事务 ID 有独立的 data buffer（FIFO）
- 当 ID=1 的数据先到达：存入 ID=1 的 buffer
- 当 ID=0 的数据后到达：存入 ID=0 的 buffer，立即输出（它是下一个期望的）
- 输出顺序：按事务发起顺序，而非响应到达顺序

**优点**：对用户透明，无需修改 USER Port 协议
**缺点**：需要额外 buffer（最大 = MAX_OUTSTANDING × MAX_BURST_LEN × DATA_WIDTH 字节），资源消耗大

### 3.2 方案 B：带 Tag 的输出

```
USER Port 新增: user_rd_id (output, 当前数据的来源事务 ID)
```

- 数据按到达顺序直接输出
- 每拍附带 `user_rd_id` 告知用户数据属于哪个事务
- 用户负责按 ID 重组数据

**优点**：零额外 buffer，实现简单
**缺点**：用户接口变复杂，需要用户自行处理乱序数据

### 3.3 推荐：方案 A（轻量版）

对于典型应用（MAX_OUTSTANDING ≤ 4，短突发），buffer 开销可控：

```verilog
// 每 slot 一个数据 buffer (深度 = MAX_BURST × DATA_WIDTH 字节)
// MAX_BURST = 256, DATA_WIDTH = 8 → 每 slot 256 字节
// MAX_OUTSTANDING = 4 → 总计 1024 字节 (1 BRAM)
```

使用 Block RAM 实现每 slot 的 buffer，数据到达时写入对应 slot buffer，slot 按顺序释放时读出。

---

## 4. 写通道 Out-of-Order

写通道 Out-of-Order 相对简单：

- B 响应通过 BID 标识完成的事务
- 无需重排序——B 响应不含数据，只需释放对应 slot
- Master 收到 BVALID(BID=x) → 标记 slot x 为 FREE
- 如果用户需要知道完成顺序，可输出 `user_wr_done_id`

**写通道 Out-of-Order 基本无额外开销。**

---

## 5. 与 Outstanding 设计的关系

| 特性 | 依赖 | 复杂度 |
|------|------|--------|
| Outstanding 写 | 独立 | 中等 |
| Outstanding 读 | 独立 | 中等 |
| Out-of-Order 写 | Outstanding 写 | 低（BID 匹配即可） |
| Out-of-Order 读 | Outstanding 读 | 高（需重排序 buffer 或带 tag 输出） |

---

## 6. 实施建议

| 步骤 | 内容 |
|------|------|
| 1 | 先实现 Outstanding（写 + 读），响应仍为 in-order |
| 2 | BID/RID 匹配逻辑 → 自然支持 Out-of-Order 写 |
| 3 | 读通道增加重排序 buffer → 支持 Out-of-Order 读 |
| 4 | 可选：提供带 tag 输出模式（省 buffer） |

**阶段 1+2 即可支持写通道 Out-of-Order，读通道保持 in-order（等 buffer 实现后再支持）。**

---

## 7. 参数

```verilog
parameter int REORDER_BUFFER_DEPTH = 256;  // 每 slot 重排序 buffer 深度 (字节)
parameter bit OUT_OF_ORDER_RD      = 0;    // 0: in-order 读, 1: Out-of-Order 读
```

---

*待审核。*
