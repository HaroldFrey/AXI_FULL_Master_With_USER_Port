# AXI-FULL Master with USER Port 架构文档

> **工程状态**: 开发中（未完成）
> **创建日期**: 2025-05-04
> **最后更新**: 2026-07-23 (v2 重构完成)

---

## 1. 工程概述

本工程实现了一个 **AXI4-Full 协议主机（Master）模块**，并在其上层封装了简化的 **USER Port 用户接口**。设计目标是将复杂的 AXI4-Full 总线协议抽象为简洁的 Valid/Ready 握手 + Start 触发式接口，降低用户侧逻辑的开发难度。

### 核心特性

| 特性 | 说明 |
|------|------|
| 突发类型 | FIXED / INCR / WRAP（通过 `user_wr/rd_burst_type` 端口配置，默认 INCR） |
| 时钟域 | 三时钟域：`clk_wr` / `clk_rd` / `clk_axi`，异步 FIFO 跨时钟域 |
| 跨时钟域 | 异步 FIFO（FWFT 模式，深度 32，位宽 8，格雷码指针 + 两级同步器） |
| 读写并发 | ✅ 读写完全独立，双 FSM 零耦合，支持同时读写 |
| 反压支持 | 读写路径均支持流量控制（FIFO 满/空反压 + AXI 握手反压） |
| AXI 协议 | AXI4-Full，兼容 AXI3 LOCK 信号 |

---

## 2. 工程目录结构

```
14_AXI_FULL_Master_With_USER_Port_0522/
├── doc/
│   ├── 绘图.vsdx                         # Visio 框图（原始设计图）
│   ├── architecture.md                   # 本架构文档
│   └── issue_tracker.md                  # 问题跟踪文档（15 个问题记录）
├── rtl/
│   ├── AXI_FULL_Master_With_USER_Port/   # 核心 RTL 模块
│   │   ├── AXI_FULL_Master_With_USER_Port.v  # 顶层封装（含 USER Port）
│   │   ├── axi_wr_master.v                  # 写通道控制器
│   │   ├── axi_rd_master.v                  # 读通道控制器
│   │   ├── Data_RX.v                        # 写数据通路（含异步 FIFO）
│   │   └── Data_TX.v                        # 读数据通路（含异步 FIFO）
│   └── FIFO/
│       └── fifo_async.v                    # 异步 FIFO（FWFT/Standard 双模式）
├── sim/
│   └── top_tb.v                          # 顶层仿真 Testbench
└── old/                                  # 废弃/旧版文件
    ├── axi_full_master.v                 # [v1] 旧版单 FSM 控制器
    ├── Data_send.v                       # 旧版测试数据发送
    ├── Data_receive.v                    # 旧版测试数据接收
    ├── axi_full_slave.v                  # 旧版 AXI Slave 模型
    └── top_tb.v                          # 旧版 Testbench
```

---

## 3. 模块层次结构

```
top_tb (Testbench)
└── AXI_FULL_Master_With_USER_Port   # 核心顶层
    ├── Data_RX                      # 写数据通路 + FWFT 异步 FIFO
    ├── Data_TX                      # 读数据通路 + FWFT 异步 FIFO
    ├── axi_wr_master                # 写通道控制器 (IDLE ↔ WRITE)
    └── axi_rd_master                # 读通道控制器 (IDLE ↔ READ)
```
> 旧版模块 (`Data_send`, `Data_receive`, `axi_full_slave`, `axi_full_master`) 已移至 `old/` 目录。

---

## 4. 模块详细说明

### 4.1 AXI_FULL_Master_With_USER_Port（顶层封装）

**文件**: [AXI_FULL_Master_With_USER_Port.v](../rtl/AXI_FULL_Master_With_USER_Port/AXI_FULL_Master_With_USER_Port.v)

顶层封装模块，对外提供两套接口：

- **USER Port（面向用户逻辑）**：简化的 Valid/Ready 握手 + Start 触发
- **AXI-Full Port（面向 AXI 互连）**：标准 AXI4-Full 主机接口（5通道）

#### 参数列表

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `C_M_TARGET_SLAVE_BASE_ADDR` | `32'h00000000` | 目标从机基地址 |
| `C_M_AXI_ID_WIDTH` | `1` | AXI ID 位宽 |
| `C_M_AXI_ADDR_WIDTH` | `32` | 地址总线位宽 |
| `C_M_AXI_DATA_WIDTH` | `8` | 数据总线位宽 |
| `C_M_AXI_WR_LEN_WIDTH` | `8` | 写突发长度位宽 |
| `C_M_AXI_RD_LEN_WIDTH` | `8` | 读突发长度位宽 |
| `C_M_AXI_AWUSER_WIDTH` | `0` | 写地址通道 USER 位宽 |
| `C_M_AXI_ARUSER_WIDTH` | `0` | 读地址通道 USER 位宽 |
| `C_M_AXI_WUSER_WIDTH` | `0` | 写数据通道 USER 位宽 |
| `C_M_AXI_RUSER_WIDTH` | `0` | 读数据通道 USER 位宽 |
| `C_M_AXI_BUSER_WIDTH` | `0` | 写响应通道 USER 位宽 |

#### USER Port 接口

**写操作**:
| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `user_wr_start` | I | 1 | 写操作触发（单周期脉冲） |
| `user_wr_burst_type` | I | 2 | 突发类型: 00=FIXED, 01=INCR, 10=WRAP |
| `user_wr_addr` | I | 32 | 突发写起始地址 |
| `user_wr_len` | I | 8 | 突发写长度 |
| `user_wr_valid` | I | 1 | 写数据有效 |
| `user_wr_data_in` | I | 8 | 写数据 |
| `user_wr_ready` | O | 1 | 写数据就绪（FIFO 非满） |
| `user_wr_error` | O | 1 | 写事务错误标志（BRESP ≠ OKAY） |
| `user_awuser` | I | AWUSER | 写地址通道用户信号（宽度参数化） |
| `user_wuser` | I | WUSER | 写数据通道用户信号（宽度参数化） |

**读操作**:
| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| `user_rd_start` | I | 1 | 读操作触发（单周期脉冲） |
| `user_rd_burst_type` | I | 2 | 突发类型 |
| `user_rd_addr` | I | 32 | 突发读起始地址 |
| `user_rd_len` | I | 8 | 突发读长度 |
| `user_rd_valid` | O | 1 | 读数据有效 |
| `user_rd_data_out` | O | 8 | 读数据 |
| `user_rd_ready` | I | 1 | 用户准备好接收数据 |
| `user_rd_error` | O | 1 | 读事务错误标志（RRESP ≠ OKAY） |
| `user_aruser` | I | ARUSER | 读地址通道用户信号（宽度参数化） |

> **BUSER / RUSER**（来自从机的用户信号）当前不暴露到 USER Port，模块内部接收但不传递。

#### 内部连接关系

```
user_wr_* ──> axi_wr_master  (start/addr/len/burst/error/user)
user_wr_valid/data ──> Data_RX(FIFO) ──> axi_wr_master
user_rd_* ──> axi_rd_master  (start/addr/len/burst/error/user)
axi_rd_master ──> Data_TX(FIFO) ──> user_rd_valid/data
```

---

### 4.2 axi_wr_master / axi_rd_master（读写控制器）

> 原单 FSM 版本 `axi_full_master.v` 已移至 `old/`。当前架构为读写分离的双模块设计。

**文件**: [axi_wr_master.v](../rtl/AXI_Full_Master_With_USER_Port/axi_wr_master.v) / [axi_rd_master.v](../rtl/AXI_Full_Master_With_USER_Port/axi_rd_master.v)

利用 AXI 协议读写通道天然独立的特性，将控制器拆分为两个完全解耦的 2 状态 FSM，支持读写同时进行。

#### axi_wr_master — 写通道控制器

```
┌─────────────────────────────────┐
│           axi_wr_master          │
│   ┌────────┐      ┌────────┐    │
│   │  IDLE  │ ────>│ WRITE  │    │
│   │        │start │        │    │
│   │        │<──── │        │    │
│   └────────┘BVALID└────────┘    │
│            &BREADY               │
│  管理: AWADDR, AWVALID, AWLEN,  │
│        WDATA, WLAST, WVALID,    │
│        BREADY, data_rd_en       │
└─────────────────────────────────┘
```

| 通道 | 关键逻辑 |
|------|----------|
| **AW** | AWADDR 在 `wr_start` 时锁存 = BASE + addr_in；写完成后按 burst 字节数偏移 |
| **W** | WDATA 来自 FIFO；WLAST 单拍(len=1)立即置位，多拍在 wr_cnt==len-2 预测置位 |
| **B** | BREADY 在 WLAST 握手后置位，BVALID 握手后清零 |
| **反压** | FIFO 空时 WVALID 自动拉低 (#15)；WVALID 最后一拍清零 |

#### axi_rd_master — 读通道控制器

```
┌─────────────────────────────────┐
│           axi_rd_master          │
│   ┌────────┐      ┌────────┐    │
│   │  IDLE  │ ────>│  READ  │    │
│   │        │start │        │    │
│   │        │<──── │        │    │
│   └────────┘RLAST └────────┘    │
│            &RVALID               │
│  管理: ARADDR, ARVALID, ARLEN,  │
│        RREADY, rd_data_flag     │
└─────────────────────────────────┘
```

| 通道 | 关键逻辑 |
|------|----------|
| **AR** | ARADDR 在 `rd_start` 时锁存 = BASE + addr_in；读完成后按 burst 字节数偏移 |
| **R** | RVALID&RREADY 时数据有效；`rd_data_flag` 在 AR 握手后置位、RLAST&RVALID 清零 |
| **反压** | `rd_fifo_full` 为高时拉低 RREADY |

#### 模块内部架构

```
===================== AXI_FULL_Master_With_USER_Port =====================
                                                                          |
  USER 写侧 (clk_wr 域)              AXI 写通道 (clk_axi 域)              |
  ┌────────────────────┐    ┌──────────┐    ┌─────────────────────────┐   |
  │ user_wr_start ─────┼───>│          │    │                         │   |
  │ user_wr_burst_type─┼───>│  Data_RX │    │     axi_wr_master       │   |
  │ user_wr_valid ─────┼───>│          │───>│                         │   |
  │ user_wr_data  ─────┼───>│ ┌──────┐ │    │ ┌────┐   ┌──────┐      │   |
  │ user_wr_ready <─────┼───│ │FIFO  │ │───>│ │FSM │──>│ AW   │──────┼──>│
  │ user_wr_addr  ──────┼───│ │async │ │    │ │IDLE│   │channel│      │   |
  │ user_wr_len   ──────┼───│ └──────┘ │    │ │ ↔  │   ├──────┤      │   |
  └────────────────────┘    │  (FWFT)  │    │ │WR  │   │ W    │──────┼──>│
                            └──────────┘    │ │    │   │channel│      │   |
                                            │ └────┘   ├──────┤      │   |
  USER 读侧 (clk_rd 域)                     │          │ B    │<─────┼───│
  ┌────────────────────┐    ┌──────────┐    │          │channel│      │   |
  │ user_rd_start ─────┼───>│          │    └─────────────────────────┘   |
  │ user_rd_burst_type─┼───>│  Data_TX │                                    |
  │ user_rd_addr  ─────┼───>│          │    ┌─────────────────────────┐   |
  │ user_rd_len   ─────┼───>│ ┌──────┐ │    │     axi_rd_master       │   |
  │ user_rd_valid <─────┼───│ │FIFO  │<───│                         │   |
  │ user_rd_data  <─────┼───│ │async │ │    │ ┌────┐   ┌──────┐      │   |
  │ user_rd_ready ──────┼──>│ └──────┘ │    │ │FSM │──>│ AR   │──────┼──>│
  └────────────────────┘    │  (FWFT)  │    │ │IDLE│   │channel│      │   |
                            └──────────┘    │ │ ↔  │   ├──────┤      │   |
                                            │ │RD  │   │ R    │<─────┼───│
  clk_wr ──┐                               │ │    │   │channel│      │   |
  clk_rd ──┼── 三时钟域                      │ └────┘   └──────┘      │   |
  clk_axi ─┘                               └─────────────────────────┘   |
                                                                          |
=======================================================================---
```

**数据流**:
- 写路径: `user_wr_*` → Data_RX (clk_wr→clk_axi FIFO) → axi_wr_master → AXI AW/W/B
- 读路径: AXI AR/R → axi_rd_master → Data_TX (clk_axi→clk_rd FIFO) → `user_rd_*`

**控制流**:
- `user_wr_start` + `user_wr_burst_type` 直接进入 axi_wr_master，在 start 脉冲时锁存
- `user_rd_start` + `user_rd_burst_type` 直接进入 axi_rd_master，在 start 脉冲时锁存
- 读写路径独立、零耦合，可同时进行

#### 突发传输模式设计

AXI4 协议定义了三种突发类型，通过 `AxBURST[1:0]` 信号指定。本模块通过 `user_wr/rd_burst_type` 输入端口让用户选择，在 `start` 脉冲时锁存。

| 模式 | 编码 | 每拍地址变化 | 典型场景 | 约束 |
|------|------|-------------|----------|------|
| FIXED | `2'b00` | 不变（始终访问同一地址） | FIFO 类外设寄存器 | 无 |
| INCR | `2'b01` | 递增 `AxSIZE` 字节 | 顺序存储读写 | 无 |
| WRAP | `2'b10` | 递增至边界后回环至对齐地址 | Cache line 填充 | 长度须为 2/4/8/16 |

**实现原理**：AXI 协议中**地址计算由从机负责**，Master 仅需在 AW/AR 通道上给出起始地址和突发类型，后续每拍地址由从机根据 `AxBURST` 和 `AxSIZE` 自行计算。因此 Master 实现极为简洁：

```
Master 职责:                          Slave 职责:
┌──────────────────────┐              ┌──────────────────────────┐
│ 1. 锁存 burst_type   │              │ 根据 AxBURST 计算每拍地址  │
│ 2. 设置 AxBURST 值   │   ──────>   │ FIXED: addr = AWADDR     │
│ 3. 发出起始地址       │              │ INCR:  addr += AxSIZE   │
│ 4. 逐拍发送/接收数据   │              │ WRAP:  addr 递增至边界回环 │
└──────────────────────┘              └──────────────────────────┘
```

**X 态保护**：锁存时若端口悬空（未连接），自动回退为 INCR：
```verilog
wr_burst_latched <= (wr_burst_type === 2'bxx) ? 2'b01 : wr_burst_type;
```
这保证了未修改的旧代码（不连接新端口）仍以 INCR 模式正常工作。

#### 错误响应处理

AXI4 协议定义了 4 种响应码（BRESP / RRESP）：

| 编码 | 含义 | Master 行为 |
|------|------|------------|
| `2'b00` | OKAY | 正常完成 |
| `2'b01` | EXOKAY | 独占访问成功（本模块不使用独占访问） |
| `2'b10` | SLVERR | 从机错误——事务到达从机但从机返回错误 |
| `2'b11` | DECERR | 解码错误——地址无对应从机 |

**实现**：
- **写通道**：BVALID & BREADY 握手时检查 BRESP。若非 OKAY，拉高 `wr_error`，保持至下次 `wr_start`
- **读通道**：RVALID & RREADY 每拍握手时检查 RRESP。任意一拍非 OKAY，拉高 `rd_error`，保持至下次 `rd_start`
- 错误标志为电平信号，在下一次 start 时自动清除
- 错误不影响事务完成——FSM 正常跳回 IDLE，数据通道正常关闭

#### USER 信号可配置

`AWUSER` / `ARUSER` / `WUSER` 之前硬编码为 0。现在通过 USER Port 输入端口配置：

```verilog
// 顶层新增端口（位宽由参数决定, 默认 0 时端口不存在）
input [C_M_AXI_AWUSER_WIDTH-1:0] user_awuser,  // 写地址 USER
input [C_M_AXI_WUSER_WIDTH-1:0]  user_wuser,   // 写数据 USER
input [C_M_AXI_ARUSER_WIDTH-1:0] user_aruser,  // 读地址 USER
```

- 默认参数值为 0（位宽为 0 时端口退化消失，向后兼容）
- `BUSER` / `RUSER`（来自从机）当前不暴露，模块内部接收但不传递到 USER Port

#### AXI 固定配置信号（两模块共用）

| 信号 | 值 | 说明 |
|------|-----|------|
| `AWBURST` / `ARBURST` | `wr/rd_burst_latched` | FIXED/INCR/WRAP，由 `user_*_burst_type` 控制 |
| `AWCACHE` / `ARCACHE` | `4'b0010` | 不使用缓存 |
| `AWSIZE` / `ARSIZE` | `clogb2(DATA_WIDTH/8-1)` | 自动计算（DATA_WIDTH=8→0，即 1 字节/拍） |
| `AWUSER` / `WUSER` | `user_awuser` / `user_wuser` | 用户配置 |
| `ARUSER` | `user_aruser` | 用户配置 |

#### 代码审查历史

本工程累计发现并修复 16 个问题，详见 [issue_tracker.md](issue_tracker.md)。所有修复均已完整迁移至 v2 模块中。关键修复包括 AxSIZE 计算、地址/长度锁存、单拍 WLAST、FIFO 反压、脉冲触发等。

---

### 4.3 Data_RX（写数据通路）

**文件**: [Data_RX.v](../rtl/AXI_Full_Master_With_USER_Port/Data_RX.v)

写方向的数据缓冲与时钟域 crossing 模块。

```
clk_wr 域                        clk_axi 域
 ┌────────┐     ┌──────────────────┐     ┌──────────────┐
 │ 用户    │────>│  rx_data_fifo    │────>│ axi_full     │
 │ 写接口  │     │  (FWFT, 32×8)   │     │ _master      │
 │        │<────│  wr_ready = !full│     │              │
 └────────┘     └──────────────────┘     │ data_rd_en──>│
                                         │<─fifo_empty  │
                                         │<─fifo_data   │
                                         └──────────────┘
```

| 信号 | 说明 |
|------|------|
| `wr_ready` | 反压信号：FIFO 满时拉低，阻止用户继续发送数据 |
| `wr_fifo_empty` | 传至 axi_wr_master，FIFO 空时暂停 AXI 写操作 |
| `data_rd_en` | 来自 axi_wr_master，控制 FIFO 读出 |

---

### 4.4 Data_TX（读数据通路）

**文件**: [Data_TX.v](../rtl/AXI_Full_Master_With_USER_Port/Data_TX.v)

读方向的数据缓冲与时钟域 crossing 模块。

```
clk_axi 域                       clk_rd 域
 ┌──────────────┐     ┌──────────────────┐     ┌────────┐
 │ axi_full     │────>│  tx_data_fifo    │────>│ 用户    │
 │ _master      │     │  (FWFT, 32×8)   │     │ 读接口  │
 │              │     │                  │     │        │
 │ rd_fifo_full │<────│ full             │     │        │
 └──────────────┘     └──────────────────┘     └────────┘
```

| 信号 | 说明 |
|------|------|
| `rd_fifo_full` | 反压信号：FIFO 满时阻止 AXI Master 继续读取从机数据 |
| `rd_valid` | FIFO 非空即有效（FWFT 模式特性） |
| `fifo_rd_en` | `rd_valid & rd_ready`，握手成功时读出下一个数据 |

---

### 4.5 Data_send（测试数据生成器）[已废弃]

> **注意**: 此模块已移至 `old/` 目录，拟在新的测试架构中替换。

**文件**: [Data_send.v](../rtl/Data_send.v)

仿真测试用写数据激励模块。

- 产生 0 → DATA_MAX-1 的递增序列数据
- `work_start` 脉冲启动，完成后自动清零 `work_flag`
- `valid = work_flag`，数据在握手成功时更新

### 4.6 Data_receive（测试数据接收器）[已废弃]

> **注意**: 此模块已移至 `old/` 目录，拟在新的测试架构中替换。

**文件**: [Data_receive.v](../rtl/Data_receive.v)

仿真测试用读数据接收模块。

- 计数接收到的数据个数 `re_cnt`
- `re_ready = work_flag`：工作期间始终就绪
- `re_data_out_vld` 仅在握手成功时有效

### 4.7 axi_full_slave（AXI 从机存储模型）[已废弃]

> **注意**: 此模块已移至 `old/` 目录，拟在新的测试架构中替换。

**文件**: [axi_full_slave.v](../rtl/axi_full_slave.v)

标准 AXI4-Full Slave 实现，用于仿真验证。

- 内部 Block RAM：256 字节（`byte_ram[0:255]`）
- 支持三种突发类型：FIXED / INCR / WRAP
- 支持 WSTRB 字节掩码
- 读写地址各有独立的锁存与计数器
- AW/AR 通道有互斥标志（`awv_awr_flag` / `arv_arr_flag`），不允许同时处理

---

## 5. 时钟架构

```
          ┌──────────────┐
          │   clk_wr     │──── 写数据时钟 (用户写侧)
          │   clk_rd     │──── 读数据时钟 (用户读侧)
          │   clk_axi    │──── AXI 总线时钟 (Master + Slave)
          └──────────────┘
```

| 时钟域 | 使用者 | 说明 |
|--------|--------|------|
| `clk_wr` | Data_RX（写侧） | 用户写逻辑时钟 |
| `clk_rd` | Data_TX（读侧） | 用户读逻辑时钟 |
| `clk_axi` | axi_wr_master, axi_rd_master, Data_RX（AXI侧）, Data_TX（AXI侧） | AXI 总线时钟 |

### 跨时钟域方案

两个异步 FIFO 实现三时钟域之间的数据传递：

```
clk_wr ──[rx_data_fifo]──> clk_axi ──[tx_data_fifo]──> clk_rd
```

Testbench 中预设了 7 种时钟频率组合用来验证跨时钟域可靠性（默认全部使用 100MHz）。

---

## 6. 数据流

### 6.1 写数据流

```
USER 写侧 (clk_wr)              顶层封装 (clk_axi)            AXI 总线 (clk_axi)
─────────────────────    ┌──────────────────────────┐    ─────────────────────
user_wr_start ─────────>│ axi_wr_master             │
user_wr_burst_type ────>│   FSM: IDLE → WRITE       │──> AWADDR/AWLEN/AWBURST
user_wr_addr ──────────>│   AWADDR 锁存             │──> WDATA/WLAST/WVALID
user_wr_len ───────────>│   WDATA 从 FIFO 读取       │<── BVALID
user_wr_valid ─────────>│   BREADY 响应             │
user_wr_data ───>│FIFO│──> data_rd_en / wr_data     │
user_wr_ready <──│   │<── wr_fifo_empty             │
                └──────┘                             │
                   ↑                                 │
              clk_wr → clk_axi                       │
```

1. 用户设置 `user_wr_addr/len/burst_type`，发送 `user_wr_start` 脉冲
2. axi_wr_master 锁存参数，FSM 跳转到 WRITE，发出 AW 通道
3. 用户逐拍发送数据到 Data_RX FIFO（clk_wr→clk_axi），axi_wr_master 从 FIFO 读出并驱动 W 通道
4. 突发完成后，从机返回 BVALID，FSM 跳回 IDLE

### 6.2 读数据流

```
AXI 总线 (clk_axi)            顶层封装 (clk_rd)         USER 读侧 (clk_rd)
─────────────────────    ┌──────────────────────────┐    ─────────────────
                         │ axi_rd_master             │
<── ARADDR/ARLEN/ARBURST │   FSM: IDLE → READ       │<── user_rd_start
<── RVALID/RDATA/RLAST   │   ARADDR 锁存             │<── user_rd_burst_type
                         │   RREADY 控制             │<── user_rd_addr/len
                         │   rd_data_flag 窗口       │──> user_rd_valid
                         │           │               │──> user_rd_data
                         │       ┌───┴───┐           │
                         │       │ FIFO  │──────────>│
                         │       └───────┘           │
                         │  clk_axi → clk_rd         │
```

1. 用户设置 `user_rd_addr/len/burst_type`，发送 `user_rd_start` 脉冲
2. axi_rd_master 锁存参数，FSM 跳转到 READ，发出 AR 通道
3. 从机返回读数据，经 Data_TX FIFO（clk_axi→clk_rd）传递给用户
4. RLAST 到达，FSM 跳回 IDLE

---

## 7. AXI 协议实现细节

### 7.1 通道握手规范

所有 AXI 通道均遵循标准 Valid/Ready 握手协议：

```
VALID  ────┐         ┌──────────
           └─────────┘
READY  ────────┐     ┌──────────
               └─────┘
                    ↑
                 握手点 (VALID & READY)
```

### 7.2 突发传输时序示例（写操作）

```
Cycle:    T0    T1    T2    T3    T4    T5    T6    T7
         ─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────
AWVALID      │█████│     │     │     │     │     │
AWREADY      │     │█████│     │     │     │     │
WVALID       │     │     │█████████████████████│     │
WREADY       │     │     │█████████████████████│     │
WDATA        │     │     │ D0  │ D1  │ D2  │ D3  │
WLAST        │     │     │     │     │     │█████│
BVALID       │     │     │     │     │     │     │█████│
BREADY       │     │     │     │     │     │     │█████│
```

### 7.3 当前局限性

| 项目 | 状态 | 计划 |
|------|------|------|
| Outstanding | 不支持 | 支持多事务未完成 |
| Out of Order | 不支持 | 支持乱序返回 |
| 错误响应处理 | 未处理 | ✅ 已支持 BRESP/RRESP 非 OKAY 检测，通过 `user_wr/rd_error` 输出 |
| 约束文件 | 无 XDC | 添加时序约束 |
| 约束文件 | 无 XDC | 添加时序约束 |

---

## 8. 仿真 Testbench

**文件**: [top_tb.v](../sim/top_tb.v)

### 时钟配置

Testbench 预设了 7 种三时钟频率组合（默认全部 100MHz），覆盖了不同快慢关系：

| 场景 | clk_wr | clk_rd | clk_axi | 说明 |
|------|--------|--------|---------|------|
| 1 | 100MHz | 100MHz | 100MHz | 等频（默认激活） |
| 2 | 300MHz | 200MHz | 100MHz | 写最快，AXI最慢 |
| 3 | 300MHz | 100MHz | 200MHz | 写最快，读最慢 |
| 4 | 200MHz | 300MHz | 100MHz | 读最快，AXI最慢 |
| 5 | 100MHz | 300MHz | 200MHz | 读最快，写最慢 |
| 6 | 200MHz | 100MHz | 300MHz | AXI最快，读最慢 |
| 7 | 100MHz | 200MHz | 300MHz | AXI最快，写最慢 |

### 测试流程

```
1. 复位释放 (T=10 cycles)
2. 等待 300ns
3. 发送 write_start 脉冲 → 执行一次写突发
4. 等待 3000ns
5. 发送 read_start 脉冲  → 执行一次读突发
6. 结束
```

### 顶层实例化

Testbench 实例化 `design_1_wrapper`（Vivado Block Design 自动生成的封装模块），该模块内部连接所有 RTL 模块和 FIFO IP 核。

---

## 9. Vivado IP 依赖

> **v2 更新**: 已编写纯 RTL 等效模块 `fifo_async.v`，可脱离 Vivado IP 独立仿真。

| IP 核 | 实例名 | 用途 | 替代方案 |
|-------|--------|------|----------|
| FIFO Generator | `rx_data_fifo` | 写数据跨时钟域 | `rtl/FIFO/fifo_async.v` (FWFT, 深度32, 位宽8) |
| FIFO Generator | `tx_data_fifo` | 读数据跨时钟域 | `rtl/FIFO/fifo_async.v` (FWFT, 深度32, 位宽8) |

- 在 Vivado 工程中可继续使用 FIFO IP
- 在独立仿真 (Questa/Modelsim) 中使用 `fifo_async.v` 替代
- 两个模块对外接口完全一致，切换无需修改 Data_RX/Data_TX 以外代码

---

## 10. 待完善事项

1. **功能扩展**
   - [ ] 支持 Outstanding 事务 → 见 [outstanding_design.md](outstanding_design.md)
   - [ ] 支持 Out-of-Order 响应 → 见 [out_of_order_design.md](out_of_order_design.md)

2. **已知 Bug 修复**

   见 [issue_tracker.md](issue_tracker.md)（16 个问题，全部已解决或不予处理）

3. **完善性**
   - [ ] 添加约束文件（XDC）
   - [ ] Testbench 增加 corner case 覆盖（错误注入测试）

---

## 11. 使用方式

### 写操作时序

```
user_wr_start     ──┐┌── (单周期脉冲)
                    └┘
user_wr_burst_type ──X──────────────────── (保持, 00=FIXED 01=INCR 10=WRAP)
user_wr_addr      ───X──────────────────── (保持)
user_wr_len       ───X──────────────────── (保持)
user_wr_valid     ──────┐┌┐┌┐┌┐┌─────── (每个数据拍)
user_wr_data      ──────X X X X─────────
user_wr_ready     ─────────┐┌┐┌┐┌─────── (FIFO非满时高)
```

1. 设置 `user_wr_addr` 和 `user_wr_len`
2. 发送 `user_wr_start` 单周期脉冲
3. 在 `user_wr_valid & user_wr_ready` 握手成功时发送数据
4. 全部数据发送完毕后等待模块自动完成（无需额外操作）

### 读操作时序

```
user_rd_start  ──┐┌── (单周期脉冲)
                 └┘
user_rd_addr   ────X────────────────────── (保持)
user_rd_len    ────X────────────────────── (保持)
user_rd_valid  ──────────┐┌┐┌┐┌┐─────── (数据有效)
user_rd_data   ──────────X X X X────────
user_rd_ready  ─────────────┐┌┐┌┐┌────── (用户就绪)
```

1. 设置 `user_rd_addr` 和 `user_rd_len`
2. 发送 `user_rd_start` 单周期脉冲
3. 在 `user_rd_valid & user_rd_ready` 握手成功时接收数据
4. 读数据由模块自动从从机获取

---

*本文档基于 2025-05-04 版本的 RTL 代码编写，v2 重构完成于 2026-07-23，v3 突发类型扩展完成于 2026-07-23。后续代码变更时请同步更新。*
