# AXI_FULL_Master_With_USER_Port 测试平台设计方案

> **状态**: 待审核
> **日期**: 2026-07-23
> **被测模块**: `AXI_FULL_Master_With_USER_Port`

---

## 1. 测试目标

验证 `AXI_FULL_Master_With_USER_Port` 模块的以下功能：

| 类别 | 验证点 |
|------|--------|
| 基本写传输 | INCR 突发写，多拍 (len≥2) 及单拍 (len=1)，WLAST 正确 |
| 基本读传输 | INCR 突发读，多拍及单拍，数据正确返回 |
| 写后读一致性 | 写入从机 BRAM 后回读，验证数据一致 |
| 写反压 | AXI 从机 WREADY 延迟 / 用户 wr_ready 反压 |
| 读反压 | 用户 rd_ready 延迟 / AXI 从机 RREADY 反压 |
| 地址正确性 | 不同偏移地址的读写访问 |
| 多事务连续 | 连续多次写、多次读，状态机正确复位 |
| 边界条件 | 最大突发长度 (256)、len=1 单拍 |
| 多时钟场景 | 7 种三时钟频率组合下的读写一致性 |

---

## 2. 测试平台架构

```
┌─────────────────────────────────────────────────────────────┐
│                         tb_axi_master                       │
│                                                             │
│  ┌──────────┐    USER Port     ┌───────────┐    AXI Bus    │
│  │ user_wr  │ ──valid/ready──> │           │ ──AW/W/B───> │
│  │  driver  │                  │   DUT     │               │
│  │          │                  │ AXI_FULL_ │               │
│  │ user_rd  │ <──valid/ready── │ Master    │ <──AR/R────  │
│  │  monitor │                  │ _With_    │               │
│  └──────────┘                  │ USER_Port │               │
│                                └───────────┘               │
│  ┌──────────┐                                   ┌────────┐ │
│  │  clock   │                                   │  AXI   │ │
│  │  reset   │                                   │ Slave  │ │
│  │  gen     │                                   │  BFM   │ │
│  └──────────┘                                   │(BRAM)  │ │
│                                                 └────────┘ │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                    Scoreboard                        │  │
│  │  写数据记录 → 期望队列 → 读数据比对 → PASS/FAIL       │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 2.1 组件说明

| 组件 | 类型 | 功能 |
|------|------|------|
| `clk_rst_gen` | module | 生成 clk_wr / clk_rd / clk_axi 及 rst_n，支持 7 种时钟场景 |
| `axi_slave_bfm` | module | AXI4-Full 从机行为模型，内含 BRAM，支持可配置握手延迟 |
| `user_wr_driver` | task | 通过 USER Port 发起写事务（start→发送数据→等待完成） |
| `user_rd_driver` | task | 通过 USER Port 发起读事务（start→接收数据→校验） |
| `scoreboard` | class | 记录每次写数据的黄金参考值，读回时逐拍比对 |

> **FIFO IP**: DUT 内部已实例化 `rx_data_fifo` / `tx_data_fifo`（Vivado FIFO Generator IP），TB 无需额外处理。仿真时由 Vivado 工程自动编译 IP 仿真模型。

---

## 3. 文件组织

```
sim/
├── tb_axi_master.sv              # 顶层 Testbench
├── axi_slave_bfm.sv              # AXI 从机 BFM
└── tb_pkg.sv                     # 公共参数、类型定义、时钟场景配置
```

共 3 个 SystemVerilog 文件。FIFO IP (`rx_data_fifo`/`tx_data_fifo`) 由 Vivado 工程管理，仿真时自动包含其仿真模型。

---

## 4. 接口与时序

### 4.1 时钟与复位

#### 7 种时钟场景

覆盖三时钟域（clk_wr / clk_rd / clk_axi）的所有快慢组合：

| 场景 | clk_wr | clk_rd | clk_axi | 说明 |
|------|--------|--------|---------|------|
| S1 | 100MHz | 100MHz | 100MHz | 等频（默认） |
| S2 | 300MHz | 200MHz | 100MHz | 写最快，AXI 最慢 |
| S3 | 300MHz | 100MHz | 200MHz | 写最快，读最慢 |
| S4 | 200MHz | 300MHz | 100MHz | 读最快，AXI 最慢 |
| S5 | 100MHz | 300MHz | 200MHz | 读最快，写最慢 |
| S6 | 200MHz | 100MHz | 300MHz | AXI 最快，读最慢 |
| S7 | 100MHz | 200MHz | 300MHz | AXI 最快，写最慢 |

#### 实现方式

`tb_pkg.sv` 中定义场景配置，`clk_rst_gen` 通过参数选择：

```systemverilog
// tb_pkg.sv
typedef struct {
    real clk_wr_period;     // ns
    real clk_rd_period;
    real clk_axi_period;
} clk_scenario_t;

localparam clk_scenario_t CLK_SCENARIOS[1:7] = '{
    '{10.0, 10.0, 10.0},   // S1: 100M / 100M / 100M
    '{3.33, 5.0,  10.0},   // S2: 300M / 200M / 100M
    '{3.33, 10.0, 5.0 },   // S3: 300M / 100M / 200M
    '{5.0,  3.33, 10.0},   // S4: 200M / 300M / 100M
    '{10.0, 3.33, 5.0 },   // S5: 100M / 300M / 200M
    '{5.0,  10.0, 3.33},   // S6: 200M / 100M / 300M
    '{10.0, 5.0,  3.33}    // S7: 100M / 200M / 300M
};
```

`clk_rst_gen` 模块端口：
```systemverilog
module clk_rst_gen #(
    parameter int SCENARIO = 1       // 选择场景 1~7
)(
    output logic clk_wr, clk_rd, clk_axi, rst_n
);
```

#### 复位

所有场景统一：复位持续 10 个 clk_axi 周期，低电平有效。

### 4.2 用户端口协议

**写操作**:
```
user_wr_start  ──┐┌── (单周期脉冲)
                 └┘
user_wr_burst_type──X──────────────── (保持至下一 start)
user_wr_addr   ────X──────────────── (保持至下一 start)
user_wr_len    ────X────────────────
user_wr_valid  ──────┐┌┐┌┐┌┐────── (每拍握手)
user_wr_data   ──────XiXjXkXl──────
user_wr_ready  ─────────┐┌┐┌┐┌───── (FIFO 非满)
```

**读操作**:
```
user_rd_start  ──┐┌── (单周期脉冲)
                 └┘
user_rd_addr   ────X────────────────
user_rd_len    ────X────────────────
user_rd_valid  ──────────┐┌┐┌┐┌─── (数据到达)
user_rd_data   ──────────XaXbXcXd──
user_rd_ready  ─────────────┐┌┐┌┐┌─ (用户接收)
```

### 4.3 AXI 从机 BFM 握手

```systemverilog
// 可配置延迟参数
parameter AW_READY_DELAY = 0;   // AWREADY 延迟周期数
parameter W_READY_DELAY  = 0;   // WREADY 延迟周期数
parameter B_VALID_DELAY  = 0;   // BVALID 响应延迟
parameter AR_READY_DELAY = 0;   // ARREADY 延迟周期数
parameter R_VALID_DELAY  = 1;   // RVALID 首数据延迟
parameter R_DATA_GAP      = 0;   // 读数据拍间间隔（0=连续）
```

用于注入反压场景。反压测试时修改对应 delay 参数。

---

## 5. 测试用例清单

### TC01 — 基本写突发 (len=16)

| 项目 | 值 |
|------|-----|
| 目标 | 验证基本 INCR 写突发 |
| 参数 | `wr_addr=0x0000`, `wr_len=16` |
| 数据 | 0x00, 0x01, 0x02, ..., 0x0F (递增) |
| 从机 | 零延迟 |
| 检查 | AWADDR/AWLEN/AxSIZE 正确；WDATA 逐拍匹配；WLAST 最后一拍有效；BVALID 正确返回 |

### TC02 — 基本读突发 (len=16)

| 项目 | 值 |
|------|-----|
| 目标 | 验证基本 INCR 读突发 |
| 参数 | `rd_addr=0x0000`, `rd_len=16` |
| 期望数据 | 从机 BRAM 预存数据 |
| 从机 | 零延迟 |
| 检查 | ARADDR/ARLEN 正确；RDATA 逐拍匹配；RLAST 最后一拍有效 |

### TC03 — 写后读一致性

| 项目 | 值 |
|------|-----|
| 目标 | 写完后再读回，验证数据完全一致 |
| 流程 | 写 0x0000, len=32 (数据 0x00~0x1F) → 读 0x0000, len=32 |
| 检查 | 读回数据与写入数据逐拍完全匹配 |

### TC04 — 单拍写突发 (len=1)

| 项目 | 值 |
|------|-----|
| 目标 | 验证 #2 修复：单拍 WLAST 正确置位 |
| 参数 | `wr_addr=0x0100`, `wr_len=1` |
| 数据 | 单拍 0xA5 |
| 检查 | WLAST 在唯一数据拍上为 1；读回验证 |

### TC05 — 单拍读突发 (len=1)

| 项目 | 值 |
|------|-----|
| 目标 | 验证单拍读突发 |
| 参数 | `rd_addr=0x0100`, `rd_len=1` |
| 检查 | RLAST 在唯一数据拍上为 1；数据正确 |

### TC06 — AXI 写反压 (WREADY 延迟)

| 项目 | 值 |
|------|-----|
| 目标 | 从机 WREADY 随机延迟，主机正确等待 |
| 参数 | `W_READY_DELAY = 1~5` 随机 |
| 检查 | 数据逐拍正确，WLAST 正确，突发完成无超时 |

### TC07 — AXI 读反压 (RVALID 延迟 / 拍间间隔)

| 项目 | 值 |
|------|-----|
| 目标 | 从机 RVALID 非连续返回，验证主机 RREADY 控制 |
| 参数 | `R_DATA_GAP = 1~5` 随机 |
| 检查 | 读数据逐拍正确，RLAST 正确 |

### TC08 — 用户写反压 (user_wr_ready 反压)

| 项目 | 值 |
|------|-----|
| 目标 | 用户端 wr_ready 间歇拉低，验证 FIFO 反压 |
| 参数 | user_wr_ready 每 3 拍拉低 1 拍（模拟慢速数据源） |
| 检查 | 数据不丢失，全部正确写入 |

### TC09 — 用户读反压 (user_rd_ready 反压)

| 项目 | 值 |
|------|-----|
| 目标 | 用户端 rd_ready 间歇拉低，验证读 FIFO 反压 |
| 参数 | user_rd_ready 每 3 拍拉低 1 拍（模拟慢速消费者） |
| 检查 | 数据不丢失，全部正确读出 |

### TC10 — 连续多次写

| 项目 | 值 |
|------|-----|
| 目标 | 验证连续多次写事务，状态机正确复位 |
| 流程 | 4 次写：len1=4, len2=8, len3=1, len4=16 |
| 检查 | 每次 AWADDR 正确累加；全部数据正确 |

### TC11 — 连续多次读

| 项目 | 值 |
|------|-----|
| 目标 | 验证连续多次读事务 |
| 流程 | 3 次读：len1=8, len2=1, len3=16 |
| 检查 | 每次 ARADDR 正确；全部数据正确 |

### TC12 — 最大突发长度 (len=256)

| 项目 | 值 |
|------|-----|
| 目标 | 验证边界条件：AXI4 最大突发长度 256 |
| 参数 | `wr_len=256` |
| 检查 | 全部 256 拍数据正确；WLAST/RLAST 正确 |

### TC13~TC19 — 多时钟场景写后读一致性

| 用例 | 场景 | 时钟 (wr/rd/axi) | 说明 |
|------|------|-------------------|------|
| TC13 | S1 | 100M / 100M / 100M | 等频基准 |
| TC14 | S2 | 300M / 200M / 100M | 写快 AXI 慢 |
| TC15 | S3 | 300M / 100M / 200M | 写快读慢 |
| TC16 | S4 | 200M / 300M / 100M | 读快 AXI 慢 |
| TC17 | S5 | 100M / 300M / 200M | 读快写慢 |
| TC18 | S6 | 200M / 100M / 300M | AXI 快读慢 |
| TC19 | S7 | 100M / 200M / 300M | AXI 快写慢 |

### TC20~TC23 — 突发类型测试 (FIXED / WRAP)

| 用例 | 突发类型 | 长度 | 说明 |
|------|----------|------|------|
| TC20 | FIXED 写 | len=4 | 写 4 拍到同一地址，最后一拍值覆盖前三拍 |
| TC21 | FIXED 读 | len=8 | 从 FIXED 外设（FIFO）连续读 8 拍 |
| TC22 | WRAP 写 | len=4 | 起始地址 0x04，4 拍 WRAP 写，验证回环 |
| TC23 | WRAP 读 | len=8 | 起始地址对齐，8 拍 WRAP 读，验证回环 |

**共用流程**：
| 项目 | 值 |
|------|-----|
| 目标 | 在各时钟场景下验证跨时钟域数据完整性 |
| 流程 | 写 0x0000, len=32 → 读 0x0000, len=32 |
| 检查 | 读回数据与写入数据逐拍完全匹配 |

---

## 6. 数据生成与校验

### 6.1 写数据生成

使用递增模式（可辨别每拍数据），起始值为可配置参数：

```systemverilog
function automatic logic [7:0] gen_data(input int beat_idx, input int seed);
    return (seed + beat_idx) & 8'hFF;
endfunction
```

### 6.2 Scoreboard

```systemverilog
class scoreboard;
    // 写操作 → 将 (addr, data[0..len-1]) 压入期望队列
    task push_expected(addr, len, data[]);
    // 读操作 → 从期望队列取出，逐拍比对
    task check_beat(addr, beat_idx, actual_data) -> pass/fail;
    // 最终报告
    function void report();
endclass
```

### 6.3 结果报告

每个测试用例结束时输出：
```
[TC03] Write-Read Consistency ... PASS (32 beats matched)
[TC04] Single-Beat Write     ... PASS (WLAST=1 verified)
```

最终汇总：
```
========== Test Summary ==========
Total:  23
Passed: 23
Failed:  0
==================================
```

---

## 7. 实现细节

### 7.1 AXI Slave BFM 设计

```systemverilog
module axi_slave_bfm #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 32,
    parameter MEM_DEPTH  = 1024,       // BRAM 深度 (字节)
    // 握手延迟
    parameter AW_READY_DELAY = 0,
    parameter W_READY_DELAY  = 0,
    parameter B_VALID_DELAY  = 0,
    parameter AR_READY_DELAY = 0,
    parameter R_VALID_DELAY  = 1,
    parameter R_DATA_GAP     = 0
)(
    input  wire                     aclk, aresetn,
    // AXI Write Channels
    input  wire [ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire [7:0]               s_axi_awlen,
    input  wire                     s_axi_awvalid,
    output reg                      s_axi_awready,
    input  wire [DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire                     s_axi_wlast,
    input  wire                     s_axi_wvalid,
    output reg                      s_axi_wready,
    output reg                      s_axi_bvalid,
    input  wire                     s_axi_bready,
    // AXI Read Channels
    input  wire [ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire [7:0]               s_axi_arlen,
    input  wire                     s_axi_arvalid,
    output reg                      s_axi_arready,
    output reg  [DATA_WIDTH-1:0]    s_axi_rdata,
    output reg                      s_axi_rlast,
    output reg                      s_axi_rvalid,
    input  wire                     s_axi_rready
);
    // 内部 BRAM: byte mem[0..MEM_DEPTH-1]
    // 写通道状态机：IDLE → AW → WRITE → B
    // 读通道状态机：IDLE → AR → SEND
endmodule
```

### 7.2 测试用例结构

功能测试 (TC01~TC12) 和突发类型测试 (TC20~TC23) 使用默认 S1 等频场景；多时钟测试 (TC13~TC19) 通过参数化 `clk_rst_gen` 遍历各场景：

```systemverilog
// tb_axi_master.sv
initial begin
    // ---- 功能测试 (S1: 等频 100MHz) ----
    reset(SCENARIO=1);
    tc01_basic_write();
    tc02_basic_read();
    // ... TC03~TC12 ...

    // ---- 多时钟测试 (遍历 S1~S7) ----
    for (int s = 1; s <= 7; s++) begin
        reset(SCENARIO=s);
        wr_rd_consistency_check(/* addr=0, len=32 */);
        $display("[TC%02d] Clock Scenario S%d ... %s",
                 12+s, s, scb.last_pass ? "PASS" : "FAIL");
    end

    scb.report();
    $finish;
end
```

> `reset(SCENARIO=s)` 重建 `clk_rst_gen` 实例并等待复位释放。

### 7.3 超时保护

每个测试用例设置全局超时计数器，防止挂死：

```systemverilog
localparam TIMEOUT = 100000;  // 10万周期
always @(posedge clk_axi) begin
    cycle_cnt++;
    if (cycle_cnt > TIMEOUT) begin
        $error("TIMEOUT! Test hung.");
        $finish;
    end
end
```

---

## 8. 使用方式

```bash
# Vivado 仿真
xsim tb_axi_master -R

# Modelsim/Questa
vlog sim/*.sv rtl/**/*.v
vsim tb_axi_master -c -do "run -all"

# 运行特定测试用例
vsim tb_axi_master -gTEST_FILTER=3 -c -do "run -all"
```

---

## 9. 扩展预留

| 扩展项 | 预留方式 |
|------|----------|
| 错误注入 (RRESP/BRESP) | AXI Slave BFM 增加 `error_response` 模式 |
| SVA 协议检查 | 添加 SystemVerilog Assertions 绑定到 AXI 接口 |
| 功能覆盖率 | 添加 covergroup（SystemVerilog 原生支持） |
| UVM 迁移 | BFM 封装为 driver/monitor，scoreboard 保持 |

---

## 10. 确认事项（已确认）

| # | 问题 | 确认结果 |
|---|------|----------|
| 1 | FIFO IP 实例化还是行为模型？ | 实例化 Vivado FIFO IP，由 Vivado 工程管理 |
| 2 | 7 种时钟场景是否覆盖？ | 本阶段覆盖，新增 TC13~TC19 |
| 3 | 是否添加 SVA 协议检查？ | 暂不添加 |
| 4 | 通过标准？ | 仅 Scoreboard 数据比对，不额外检查时序波形 |

---

## 11. 用例汇总

| 编号 | 用例名称 | 时钟场景 | 类别 |
|------|----------|----------|------|
| TC01 | 基本写突发 (len=16) | S1 | 功能 |
| TC02 | 基本读突发 (len=16) | S1 | 功能 |
| TC03 | 写后读一致性 (len=32) | S1 | 功能 |
| TC04 | 单拍写突发 (len=1) | S1 | 边界 |
| TC05 | 单拍读突发 (len=1) | S1 | 边界 |
| TC06 | AXI 写反压 (WREADY 延迟) | S1 | 反压 |
| TC07 | AXI 读反压 (RVALID 延迟) | S1 | 反压 |
| TC08 | 用户写反压 (wr_ready) | S1 | 反压 |
| TC09 | 用户读反压 (rd_ready) | S1 | 反压 |
| TC10 | 连续多次写 | S1 | 多事务 |
| TC11 | 连续多次读 | S1 | 多事务 |
| TC12 | 最大突发长度 (len=256) | S1 | 边界 |
| TC13 | 多时钟-S1 (100M/100M/100M) | S1 | 跨时钟 |
| TC14 | 多时钟-S2 (300M/200M/100M) | S2 | 跨时钟 |
| TC15 | 多时钟-S3 (300M/100M/200M) | S3 | 跨时钟 |
| TC16 | 多时钟-S4 (200M/300M/100M) | S4 | 跨时钟 |
| TC17 | 多时钟-S5 (100M/300M/200M) | S5 | 跨时钟 |
| TC18 | 多时钟-S6 (200M/100M/300M) | S6 | 跨时钟 |
| TC19 | 多时钟-S7 (100M/200M/300M) | S7 | 跨时钟 |
| TC20 | FIXED 写突发 (len=4) | S1 | 突发类型 |
| TC21 | FIXED 读突发 (len=8) | S1 | 突发类型 |
| TC22 | WRAP 写突发 (len=4) | S1 | 突发类型 |
| TC23 | WRAP 读突发 (len=8) | S1 | 突发类型 |

**共 23 个测试用例，通过标准：Scoreboard 数据比对全部 PASS。**

---

*请审核上述方案，确认后开始编写代码。*
