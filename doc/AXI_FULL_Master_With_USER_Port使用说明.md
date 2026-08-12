# AXI_FULL_Master_With_USER_Port 模块使用说明

> 基于 FPGA 的 **AXI4-Full 协议主机模块**，将复杂的 AXI 总线协议抽象为
> **Start 触发 + Valid/Ready 握手**的 USER 接口，用户无需关心 AXI 协议细节。

---

## 1. 模块概述

```
┌──────────────────────────────────────────────────────────┐
│                    AXI_FULL_Master_With_USER_Port        │
│                                                          │
│  USER 接口 (简化)              AXI4-Full 接口 (标准)      │
│  ┌─────────────────┐           ┌──────────────────────┐  │
│  │ user_wr_start    │           │ AW (写地址)           │  │
│  │ user_wr_addr     │──────────▶│ W  (写数据)           │──▶ 从机
│  │ user_wr_len      │           │ B  (写响应)           │  │
│  │ user_wr_data     │           │ AR (读地址)           │  │
│  │ user_rd_start    │           │ R  (读数据)           │◀── 从机
│  │ user_rd_addr     │           └──────────────────────┘  │
│  │ ...              │                                    │
│  └─────────────────┘           内部:                     │
│                                axi_wr_master (写 FSM)    │
│                                axi_rd_master (读 FSM)    │
│                                Data_RX  (写数据 FIFO)    │
│                                Data_TX  (读数据 FIFO)    │
└──────────────────────────────────────────────────────────┘
```

- **写/读完全独立**：双 FSM 零耦合，可同时发起写和读
- 突发类型：**FIXED / INCR / WRAP**（`user_wr/rd_burst_type` 选择）
- 突发长度：1 ~ 256
- 错误处理：BRESP/RRESP 非 OKAY 时输出错误标志

---

## 2. 参数说明

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `C_M_TARGET_SLAVE_BASE_ADDR` | 32'h00000000 | 目标从机基地址（AWADDR/ARADDR = 基地址 + 用户地址）|
| `C_M_AXI_ID_WIDTH` | 1 | AXI ID 位宽 |
| `C_M_AXI_ADDR_WIDTH` | 32 | 地址位宽（读写共用）|
| `C_M_AXI_DATA_WIDTH` | 8 | 数据位宽（读写共用）|
| `C_M_AXI_WR_LEN_WIDTH` | 8 | 写突发长度位宽 |
| `C_M_AXI_RD_LEN_WIDTH` | 8 | 读突发长度位宽 |
| `C_M_AXI_AWUSER_WIDTH` | 0 | 写地址 USER 位宽 |
| `C_M_AXI_ARUSER_WIDTH` | 0 | 读地址 USER 位宽 |
| `C_M_AXI_WUSER_WIDTH` | 0 | 写数据 USER 位宽 |
| `C_M_AXI_RUSER_WIDTH` | 0 | 读数据 USER 位宽 |
| `C_M_AXI_BUSER_WIDTH` | 0 | 写响应 USER 位宽 |

---

## 3. 端口说明

### 3.1 时钟与复位（三时钟域）

| 信号 | 方向 | 说明 |
|------|------|------|
| `clk_wr` | input | **写数据时钟**（Data_RX 写侧，可与其他时钟异步）|
| `clk_rd` | input | **读数据时钟**（Data_TX 读侧，可与其他时钟异步）|
| `clk_axi` | input | **AXI 总线时钟** |
| `rst_n` | input | 全局异步复位，低有效 |

> 三时钟域可通过内部异步 FIFO 跨时钟，也可直接同频同相接（简化使用）。
> 示例：三时钟同频 100MHz。

### 3.2 USER 写接口（写数据通路）

| 信号 | 方向 | 说明 | 锁存时机 |
|------|------|------|---------|
| `user_wr_start` | input | 写事务开始脉冲（**每笔事务拉高一拍**）| — |
| `user_wr_addr` | input | 突发写地址 | **start 沿锁存** |
| `user_wr_len` | input | 突发写长度（1~256）| **start 沿锁存** |
| `user_wr_burst_type` | input | 突发类型 00=FIXED 01=INCR 10=WRAP | **start 沿锁存** |
| `user_wr_valid` | input | 写数据有效（握手）| 不锁存（写入 FIFO）|
| `user_wr_data_in` | input | 写数据 | 不锁存（写入 FIFO）|
| `user_wr_ready` | output | 写数据就绪（FIFO 非满）| — |
| `user_wr_error` | output | 写事务错误（BRESP≠OKAY 时拉高）| — |
| `user_awuser` | input | AWUSER 信号（组合直通到 AXI）| 保持到 AW 握手 |
| `user_wuser` | input | WUSER 信号（组合直通到 AXI）| 保持到 W 握手 |

### 3.3 USER 读接口（读数据通路）

| 信号 | 方向 | 说明 | 锁存时机 |
|------|------|------|---------|
| `user_rd_start` | input | 读事务开始脉冲（**每笔事务拉高一拍**）| — |
| `user_rd_addr` | input | 突发读地址 | **start 沿锁存** |
| `user_rd_len` | input | 突发读长度（1~256）| **start 沿锁存** |
| `user_rd_burst_type` | input | 突发类型 | **start 沿锁存** |
| `user_rd_valid` | output | 读数据有效（握手）| — |
| `user_rd_data_out` | output | 读数据 | — |
| `user_rd_ready` | input | 读数据就绪（用户侧反压）| — |
| `user_rd_error` | output | 读事务错误（RRESP≠OKAY 时拉高）| — |
| `user_aruser` | input | ARUSER 信号（组合直通到 AXI）| 保持到 AR 握手 |

### 3.4 AXI 接口

标准 AXI4-Full 主机接口（AW/W/B/AR/R 五个通道），直接连接 AXI 从机，无需额外适配。

---

## 4. 使用流程

### 4.1 写操作（三步）

```
① 配置就绪（至少早于 start 一个周期）
   user_wr_addr = 目标地址
   user_wr_len  = 突发长度
   user_wr_burst_type = 2'b01 (INCR)

② 传输数据（与 start 无依赖）
   user_wr_valid=1 & user_wr_ready=1 时，一拍数据写入内部 FIFO
   （推荐 start 前预填 FIFO，start 后 AW/W 零等待连续发出）

③ 拉高 user_wr_start（单周期脉冲）
   └→ 锁存配置 → 模块自动完成 AXI 写事务（AW→W→B）
   └→ 完成后自动回到空闲；BRESP≠OKAY 时 user_wr_error 拉高
```

**时序图**：

```
user_wr_start     ──┐┌── (单周期脉冲)
                    └┘
user_wr_burst_type ──X────────────────── (00=FIXED 01=INCR 10=WRAP)
user_wr_addr      ───X────────────────── (保持)
user_wr_len       ───X────────────────── (保持)
user_wr_valid     ──────┐┌┐┌┐┌┐─────── (每拍握手)
user_wr_data      ──────XiXjXkXl───────
user_wr_ready     ─────────┐┌┐┌┐┌────── (FIFO 非满)
user_wr_error     ────────────────────── (BRESP≠OKAY 时拉高)
```

### 4.2 读操作（三步）

```
① 配置就绪：user_rd_addr / user_rd_len / user_rd_burst_type
② 拉高 user_rd_start（单周期脉冲）
   └→ 锁存配置 → 模块自动发 AR → 从机返回 R 数据
③ 接收数据：user_rd_valid=1 & user_rd_ready=1 时逐拍取走数据
   （RRESP≠OKAY 时 user_rd_error 拉高）
```

**时序图**：

```
user_rd_start  ──┐┌──
                 └┘
user_rd_valid  ──────────┐┌┐┌┐────
user_rd_data   ──────────XaXbXc───
user_rd_ready  ─────────────┐┌┐┌──
```

---

## 5. 关键注意事项

1. **start 是脉冲**：每笔事务 `user_wr_start` / `user_rd_start` 拉高一拍即可，不能保持电平
2. **配置先于 start**：addr/len/burst_type 必须在 start 沿**之前稳定**（start 沿锁存）；锁存后可以修改（不影响本次事务）
3. **数据不依赖 start**：数据通过握手写入 FIFO，可 start 前预填（推荐）或 start 后边写边发；AXI 侧 WVALID 需要 FIFO 非空
4. **len 与实际数据拍数一致**：写 len 拍了几个数，AXI 侧就发几拍（WLAST 自动收尾）
5. **握手必须完整**：`valid & ready` 同时为高才算一拍传输完成
6. **USER 信号直通**：awuser/wuser/aruser 是组合直通，需要保持到对应 AXI 通道握手完成
7. **错误标志**：`user_wr_error`/`user_rd_error` 在收到非 OKAY 响应时拉高，用户需自行处理（如重试或报错）
8. **读写并发**：写和读可同时发起（双 FSM 独立），互不阻塞
9. **时钟域**：clk_wr/clk_rd/clk_axi 可异步（内部 FIFO 跨时钟），简化使用时同频同相

---

## 6. 仿真与验证

项目提供两套自动化验证流程（详见 [scripts/doc/make_tcl自动化使用说明.md](../scripts/doc/make_tcl自动化使用说明.md)）：

```bash
# ① iverilog 流程（快，无需 Vivado）
cd sim && ./run_sim.sh

# ② Vivado 自动化流程（make + tcl，含仿真 + VCD 检查 + 综合）
make all
```

- 简单测试平台：`sim/tb_axi_master_simple.sv`（5 个用例：基本写/读、单拍、反压）
- 完整验证平台：`sim/complex/`（23 个用例，含 scoreboard/BFM）
- 波形检查：`sim/check_vcd.py`（4 项检查：TB 判定/写次数/读次数/数据抽查）

---

## 7. 快速参考（伪代码）

```systemverilog
// ---- 一次写事务 ----
user_wr_addr       = 32'h1000;      // 地址
user_wr_len        = 8'd4;          // 长度 4
user_wr_burst_type = 2'b01;         // INCR
// 预填数据
repeat (4) begin
    @(posedge clk_wr);
    user_wr_valid   = 1'b1;
    user_wr_data_in = data[i];
    while (!user_wr_ready) @(posedge clk_wr);   // 握手
    @(posedge clk_wr);
    user_wr_valid = 1'b0;
end
// 发起事务
@(posedge clk_axi);
user_wr_start = 1'b1;
@(posedge clk_axi);
user_wr_start = 1'b0;
// 等待完成（或检查 user_wr_error）

// ---- 一次读事务 ----
user_rd_addr       = 32'h1000;
user_rd_len        = 8'd4;
user_rd_burst_type = 2'b01;
@(posedge clk_axi);
user_rd_start = 1'b1;
@(posedge clk_axi);
user_rd_start = 1'b0;
// 接收数据
repeat (4) begin
    @(posedge clk_axi);
    user_rd_ready = 1'b1;           // 逐拍取数
    // user_rd_valid=1 时 user_rd_data_out 有效
end
```

---

*配套文档：[architecture.md](architecture.md)（架构设计）| [issue_tracker.md](issue_tracker.md)（问题记录）*
