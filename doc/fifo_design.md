# 异步 FIFO 设计文档 (FWFT / Standard 双模式)

> **状态**: 待审核
> **日期**: 2026-07-23
> **目标**: 编写与 Vivado FIFO Generator IP 功能等效的异步 FIFO，支持 FWFT 和 Standard 两种模式，使仿真可脱离 Vivado IP 独立运行

---

## 1. 背景

当前 `Data_RX.v` 和 `Data_TX.v` 各实例化了一个 Vivado FIFO Generator IP，用于跨时钟域数据缓冲：

| 实例名 | 写时钟域 | 读时钟域 | 用途 |
|--------|----------|----------|------|
| `rx_data_fifo` | `clk_wr` | `clk_axi` | 写数据跨时钟域 |
| `tx_data_fifo` | `clk_axi` | `clk_rd` | 读数据跨时钟域 |

需要编写一个功能等效的纯 RTL 模块，使仿真可脱离 Vivado IP 编译环境独立运行。

---

## 2. 规格参数

### 2.1 模块参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `MODE` | string | `"FWFT"` | 读模式：`"FWFT"`（首字直通）或 `"STANDARD"`（标准） |
| `DATA_WIDTH` | integer | 8 | 数据位宽 |
| `DEPTH` | integer | 32 | FIFO 深度（须为 2 的幂） |
| `ADDR_WIDTH` | integer | 5 | 地址位宽（= log2(DEPTH)） |

### 2.2 端口列表

| 端口 | 方向 | 位宽 | 时钟域 | 说明 |
|------|------|------|--------|------|
| `wr_clk` | I | 1 | — | 写时钟 |
| `wr_en` | I | 1 | wr_clk | 写使能（高有效） |
| `din` | I | DATA_WIDTH | wr_clk | 写数据 |
| `full` | O | 1 | wr_clk | FIFO 满标志 |
| `almost_full` | O | 1 | wr_clk | 将满标志（剩余 ≤ 1） |
| `rd_clk` | I | 1 | — | 读时钟 |
| `rd_en` | I | 1 | rd_clk | 读使能（高有效） |
| `dout` | O | DATA_WIDTH | rd_clk | 读数据 |
| `empty` | O | 1 | rd_clk | FIFO 空标志 |
| `almost_empty` | O | 1 | rd_clk | 将空标志（有效数据 ≤ 1） |

> **端口名称/顺序与 Vivado FIFO Generator IP 完全一致**，可直接替换实例化。

---

## 3. 两种模式的行为规格

### 3.1 写操作（两模式相同）

```
wr_clk:  _/‾\_/‾\_/‾\_/‾\_/‾\_
wr_en:   ___/‾‾‾‾‾‾‾‾‾‾\______
din:     ___X  D0  X  D1  X___
full:    ______________________  (未满)
```

- `wr_en=1` 且 `full=0`：`din` 写入 FIFO，写指针递增
- `full=1` 时 `wr_en` 被忽略
- 写指针在 `wr_clk` 域维护，写操作后转为格雷码同步至读侧

### 3.2 读操作 — FWFT 模式

```
rd_clk:  _/‾\_/‾\_/‾\_/‾\_/‾\_
rd_en:   ________/‾‾‾‾‾\________
dout:    XXXX D0 X D1 X D2 XXXX
empty:   ‾‾‾‾\____________/‾‾‾‾
              └─ 写入后自动变低
```

- **首字直通**：第一笔数据写入后，`dout` 立即有效，`empty` 自动变低——不需要 `rd_en`
- `rd_en=1` 且 `empty=0`：当前 `dout` 被读出，**同一周期** `dout` 更新为下一笔数据
- 最后一笔数据 + `rd_en=1`：`empty` 变高，`dout` 不再有效

### 3.3 读操作 — Standard 模式

```
rd_clk:  _/‾\_/‾\_/‾\_/‾\_/‾\_
rd_en:   _____/‾‾‾‾‾‾‾\________
dout:    XXXX X D0 X D1 XXXXXX
empty:   ‾‾‾‾\__________/‾‾‾‾‾
              └─ 写入后 empty 变低
              └─ 但 dout 需 rd_en 后才出现
```

- 写入数据后，`empty` 变低，但 `dout` 仍保持上一拍的值
- **首次 `rd_en=1`**：下一拍 `dout` 才出现 `D0`
- `rd_en=1` 且 `empty=0`：下一拍 `dout` 更新为下一笔数据
- Standard 模式读数据比 FWFT **延迟一拍**

### 3.4 almost_full / almost_empty

| 信号 | 条件 | 时钟域 |
|------|------|--------|
| `almost_full` | 写侧剩余空间 ≤ 1，即 `wr_ptr + 2 >= rd_ptr_synced` | wr_clk |
| `almost_empty` | 读侧有效数据 ≤ 1，即 `rd_ptr + 1 >= wr_ptr_synced` | rd_clk |

两个信号均输出正确值，即使实例化时端口悬空也不影响模块行为。

---

## 4. 跨时钟域 (CDC) 设计

### 4.1 整体架构

```
                        wr_clk 域                              rd_clk 域
                ┌─────────────────────────┐       ┌─────────────────────────┐
                │                         │       │                         │
  wr_en ──────>│ 二进制写指针 +1          │       │                         │
  din   ──────>│     │                    │       │                    ┌──> dout (FWFT)
                │     ▼                    │       │                    │
                │ 格雷码编码                │       │                    │
                │     │                    │       │                    │
                │     ├── wr_ptr_gray ──────────>│ 两级同步器 ──> 读侧   │
                │                         │       │ 格雷码解码            │
                │                         │       │     │                │
                │  双端口 RAM             │       │     ▼                │
                │  (32 × 8bit)            │       │ 空判断               │
                │                         │       │ std_empty =          │
                │                         │       │ rd_ptr_gray ==       │
                │  满判断                  │       │ wr_ptr_gray_synced   │
                │  full =                 │       │     │                │
                │  wr_ptr_gray_next ==    │       │     ▼                │
                │  rd_ptr_gray_synced     │       │ ┌──────────┐         │
                │     ▲                    │       │ │  FWFT    │         │
                │     │                    │       │ │ 输出寄存  │──> dout │
                │ 两级同步器 ◀──────────────┤       │ └──────────┘         │
                │                         │       │ (仅 FWFT 模式)        │
                │        rd_ptr_gray ◀────┤       │                       │
                │                         │       │ ◀── rd_en            │
                │                         │       │ ◀── 二进制读指针 +1   │
                └─────────────────────────┘       └─────────────────────────┘
```

### 4.2 格雷码指针与同步器

#### 为什么用格雷码

多 bit 总线跨时钟域时，若多个 bit 同时翻转且采样时刻不巧（亚稳态窗口），采样值可能是错误中间态。格雷码**每次仅变化 1 bit**，即使发生亚稳态，采样值最多"偏一"（旧值或新值），不会出现非法中间值。

#### 指针结构

```
深度 32 → 地址 0..31，需 5 bit 二进制 + 1 bit 翻转位
─────────────────────────────────────────────
二进制:  0_00000 → 0_00001 → ... → 0_11111 → 1_00000 → ...
格雷码:  0_00000 → 0_00001 → ... → 0_10000 → 1_10000 → ...
          ↑
    最高位 (MSB) 用作翻转位，区分"绕回前"和"绕回后"
```

- 地址位宽 = 5 bit (`ADDR_WIDTH`)
- 指针位宽 = 6 bit (`ADDR_WIDTH + 1`)，高位作为翻转位
- 满/空判断需比较完整 6 bit 格雷码

#### 同步器

```verilog
// 两级触发器同步 (rd_clk 域)
reg [ADDR_WIDTH:0] wr_ptr_gray_sync1;
reg [ADDR_WIDTH:0] wr_ptr_gray_sync2;
always @(posedge rd_clk) begin
    wr_ptr_gray_sync1 <= wr_ptr_gray;
    wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
end
// wr_ptr_gray_sync2 即为读侧的同步后写指针
```

- 两级触发器将亚稳态概率降至极低 (MTBF >> 设计寿命)
- 同步延迟：写指针更新后，读侧需 **2 个 rd_clk 周期** 才能看到新值
- 这导致：写侧 `full` 的撤销可能延迟 2 个 rd_clk 周期；读侧 `empty` 的撤销可能延迟 2 个 wr_clk 周期
- **这不是 bug**——FIFO 保守地"早报满、晚报空"，绝不会溢出或下溢

### 4.3 空/满判断

```verilog
// === 写侧 (wr_clk) ===
// full: 写指针 + 1 追上了同步后的读指针
wire wr_full_next;
assign wr_full_next = (wr_ptr_gray_next == rd_ptr_gray_synced);
// almost_full: 再写 2 笔就满
wire wr_almost_full;
assign wr_almost_full = (wr_ptr_bin + 2'd2 >= rd_ptr_bin_synced);

// === 读侧 (rd_clk) ===
// empty: 读指针追上了同步后的写指针
wire rd_empty_std;
assign rd_empty_std = (rd_ptr_gray == wr_ptr_gray_synced);
// almost_empty
wire rd_almost_empty;
assign rd_almost_empty = (rd_ptr_bin + 2'd1 >= wr_ptr_bin_synced);
```

**满判断用格雷码直接比较**（最可靠），`almost_full/almost_empty` 用二进制差值比较（允许 1 拍的近似）。

### 4.4 双端口 RAM 与写行为

```verilog
reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

// 写操作 (wr_clk 域)
always @(posedge wr_clk) begin
    if (wr_en && !full)
        mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= din;
end

// 读操作 (rd_clk 域) — 组合逻辑读出
assign ram_dout = mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
```

- RAM 本身是一个寄存器数组，写入需要 `wr_clk` 时钟沿
- 读取是组合逻辑（`assign`），`rd_ptr_bin` 变化后立即反映新地址的数据
- **不存在 CDC 问题**：写操作在 `wr_clk` 沿完成，读侧的 `rd_ptr_bin` 变化是 `rd_clk` 域事件，组合读出的是当前 `rd_ptr` 对应的 RAM 内容——即使写操作正在更新另一个地址，RAM 的双端口特性保证读写地址不同时不冲突

---

## 5. 读侧逻辑：FWFT vs Standard

### 5.1 两种模式的差异来源

两模式的**核心差异仅在读侧输出路径**：

```
              RAM 组合读出 (ram_dout)
                      │
                      ▼
              ┌─────────────────┐
              │  Standard 模式   │──> dout = ram_dout
              │  empty = std_empty │
              └─────────────────┘

              ┌─────────────────┐
              │  FWFT 模式      │──> dout = fwft_reg
              │  empty = !fwft_valid│
              └─────────────────┘
                     ▲
                     │
              fwft_reg 在 rd_clk 域维护:
                - 内部 FIFO 非空时预取首字到 fwft_reg
                - rd_en 时更新 fwft_reg 为下一笔数据
```

### 5.2 FWFT 输出寄存器状态机

```verilog
// rd_clk 域
reg  [DATA_WIDTH-1:0] fwft_dout;
reg                    fwft_valid;  // 实质 = !empty (FWFT视角)

always @(posedge rd_clk or negedge rst_n) begin
    if (!rst_n) begin
        fwft_dout  <= '0;
        fwft_valid <= 1'b0;
    end else begin
        if (fwft_valid && rd_en && std_empty) begin
            // 读走最后一笔 → 变为空
            fwft_valid <= 1'b0;
        end else if (!fwft_valid && !std_empty) begin
            // 内部 FIFO 有新数据 → 预取到 fwft_dout
            fwft_dout  <= ram_dout;
            fwft_valid <= 1'b1;
        end else if (fwft_valid && rd_en && !std_empty) begin
            // 读走当前，还有下一笔 → 更新
            fwft_dout  <= ram_dout;
            fwft_valid <= 1'b1;
        end else if (fwft_valid && !rd_en && !std_empty) begin
            // 不读但内部有数据 (保留当前值)
            fwft_valid <= fwft_valid;
        end
    end
end

// 模式选择
assign dout  = (MODE == "FWFT") ? fwft_dout : ram_dout;
assign empty_out = (MODE == "FWFT") ? !fwft_valid : std_empty;
```

### 5.3 假空问题与解决

FWFT 模式下，读侧需要知道"内部 FIFO 何时有新数据"来触发预取。我们使用 `std_empty`（标准 FIFO 的空标志，基于格雷码指针比较）作为内部 FIFO 状态的指示：

- `std_empty = 0`：RAM 中至少有一笔数据 → FWFT 输出寄存器可以预取
- `std_empty = 1`：RAM 为空

FWFT 的输出寄存器在 `!fwft_valid && !std_empty` 时自动预取 RAM 的第一笔数据，实现"首字直通"。

**读指针的更新**在两种模式下一致——`rd_en` 有效且 `empty_out` 为低时，读指针递增（消耗 RAM 中一笔数据）。

---

## 6. 模块接口

```verilog
module fifo_async #(
    parameter string MODE       = "FWFT",   // "FWFT" 或 "STANDARD"
    parameter int    DATA_WIDTH = 8,
    parameter int    DEPTH      = 32,
    parameter int    ADDR_WIDTH = 5         // $clog2(DEPTH)
)(
    // 写端口 (wr_clk 域)
    input  wire                     wr_clk,
    input  wire                     wr_en,
    input  wire [DATA_WIDTH-1:0]    din,
    output wire                     full,
    output wire                     almost_full,

    // 读端口 (rd_clk 域)
    input  wire                     rd_clk,
    input  wire                     rd_en,
    output wire [DATA_WIDTH-1:0]    dout,
    output wire                     empty,
    output wire                     almost_empty
);
```

### 实例化变更

`Data_RX.v` 和 `Data_TX.v` 中需要将：

```verilog
rx_data_fifo  rx_data_fifo_inst (...);   // Vivado IP 名称
tx_data_fifo  tx_data_fifo_inst (...);
```

改为：

```verilog
fifo_async #(.MODE("FWFT")) rx_data_fifo_inst (...);
fifo_async #(.MODE("FWFT")) tx_data_fifo_inst (...);
```

实例名保持不变（`rx_data_fifo_inst` / `tx_data_fifo_inst`），便于回归。

---

## 7. 仿真验证计划

| 编号 | 测试 | 描述 |
|------|------|------|
| V1 | 写满读空 | 连续写 32 笔 → full=1；连续读 32 笔 → empty=1 |
| V2 | FWFT 首字 | 写 1 笔 → empty 立即变低，dout 立即有效 (0 延迟) |
| V3 | Standard 延迟 | 写 1 笔 → empty 变低，dout 需 rd_en 后下一拍才出现 |
| V4 | 跨时钟域 | wr=300MHz, rd=100MHz，连续写读无数据丢失 |
| V5 | 同步读写 | 同时读写，FIFO 不空不满时双方不阻塞 |
| V6 | almost 标志 | 接近满/空时 almost_full/almost_empty 正确 |
| V7 | 替换回归 | 用本模块替换 Vivado IP，运行现有 19 个 TB 测试用例，全部 PASS |

---

## 8. 文件规划

| 文件 | 位置 |
|------|------|
| `fifo_async.v` | `rtl/AXI_FULL_Master_With_USER_Port/` |
| `Data_RX.v` | 修改实例化（`rx_data_fifo` → `fifo_async`） |
| `Data_TX.v` | 修改实例化（`tx_data_fifo` → `fifo_async`） |

---

*请审核上述方案，确认后开始编写代码并修改实例化。*
