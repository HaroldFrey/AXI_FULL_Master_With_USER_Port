# AXI-FULL Master with USER Port

基于 FPGA 的 **AXI4-Full 协议主机模块**，封装简化的 USER Port 用户接口，将复杂 AXI 总线协议抽象为 Valid/Ready 握手 + Start 触发式接口。

> **版本**: v2 (读写分离) | **更新**: 2026-07-23

---

## 功能特性

| 特性 | 说明 |
|------|------|
| AXI 协议 | AXI4-Full，兼容 AXI3 LOCK 信号 |
| 突发类型 | FIXED / INCR / WRAP（`user_wr/rd_burst_type` 端口，默认 INCR） |
| 数据宽度 | 8 bit（可参数化） |
| 地址宽度 | 32 bit（可参数化） |
| 突发长度 | 1 ~ 256 |
| 读写并发 | ✅ 读写完全独立，双 FSM 零耦合 |
| 错误响应 | ✅ BRESP/RRESP 非 OKAY 检测，`user_wr/rd_error` 输出 |
| USER 信号 | AWUSER / WUSER / ARUSER 可配置（参数化位宽） |
| 反压 | 读写路径均支持流量控制（FIFO + AXI 握手） |
| 仿真 | 独立 RTL FIFO（FWFT/Standard 双模式），脱离 Vivado IP |

---

## 工程目录

```
14_AXI_FULL_Master_With_USER_Port_0522/
├── README.md                               # 本文件
├── doc/                                    # 文档
│   ├── architecture.md                     #   架构设计文档
│   ├── issue_tracker.md                    #   问题跟踪文档 (16 个问题)
│   ├── fifo_design.md                      #   FIFO 设计文档
│   ├── tb_design_plan.md                   #   测试平台设计方案 (23 个用例)
│   ├── outstanding_design.md               #   Outstanding 事务设计
│   ├── out_of_order_design.md              #   Out-of-Order 响应设计
│   └── 绘图.vsdx                           #   原始框图
├── rtl/
│   ├── AXI_FULL_Master_With_USER_Port/     # 核心 RTL
│   │   ├── AXI_FULL_Master_With_USER_Port.v  # 顶层封装
│   │   ├── axi_wr_master.v                   # 写通道控制器 (2-state FSM)
│   │   ├── axi_rd_master.v                   # 读通道控制器 (2-state FSM)
│   │   ├── Data_RX.v                         # 写数据通路 (FWFT FIFO)
│   │   └── Data_TX.v                         # 读数据通路 (FWFT FIFO)
│   └── FIFO/
│       └── fifo_async.v                      # 异步 FIFO (FWFT / Standard 双模式)
├── sim/
│   ├── complex/                              # 完整验证 TB (Vivado 流程)
│   │   ├── tb_axi_master.sv                  #   顶层 Testbench (23 个用例)
│   │   ├── axi_slave_bfm.sv                  #   AXI Slave BFM
│   │   └── tb_pkg.sv                         #   公共参数 / 时钟场景 / Scoreboard
│   ├── tb_axi_master_simple.sv               # 简单 TB (iverilog 流程)
│   ├── check_vcd.py                          # VCD 波形检查脚本
│   └── run_sim.sh                            # iverilog 一键仿真 (编译→仿真→波形检查)
├── Makefile                                  # make 自动化入口 (project/sim/check/synth/all/clean)
├── scripts/                                  # Vivado 自动化子脚本 (每步独立)
│   ├── project.tcl                           #   建工程 (幂等) + 配置中心
│   ├── add_sources.tcl                       #   加源文件 (幂等, 公共子脚本)
│   ├── sim.tcl                               #   仿真主脚本
│   ├── check_vcd.tcl                         #   VCD 波形检查子脚本
│   ├── synth.tcl                             #   综合主脚本
│   └── doc/                                  #   使用说明与教程
│       ├── make_tcl自动化使用说明.md         #     快速使用文档
│       └── Vivado自动化脚本设计教程.md       #     环境搭建/架构/原理教程
├── log/                                      # [生成] vivado 会话日志
├── make_run/                                 # [生成] 每次 make 命令的打印信息
├── vivado_prj/                               # [生成] Vivado 工程 (.xpr)
├── sim_run/                                  # [生成] 仿真日志 + VCD 波形
└── synth_run/                                # [生成] 综合报告 + 网表 checkpoint
```

---

## 模块层次

```
top_tb (Testbench)
└── AXI_FULL_Master_With_USER_Port      # 核心顶层
    ├── Data_RX                         # 写数据通路 + FWFT 异步 FIFO
    │   └── fifo_async
    ├── Data_TX                         # 读数据通路 + FWFT 异步 FIFO
    │   └── fifo_async
    ├── axi_wr_master                   # 写通道控制器 (IDLE ↔ WRITE)
    └── axi_rd_master                   # 读通道控制器 (IDLE ↔ READ)
```

---

## 快速使用

### USER Port 写操作时序

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

### 步骤

1. 设置 `user_wr_addr`、`user_wr_len`、`user_wr_burst_type`
2. 发送 `user_wr_start` 单周期脉冲
3. 在 `user_wr_valid & user_wr_ready` 握手时逐拍发送数据
4. 发送完毕，模块自动完成 AXI 写事务
5. 检查 `user_wr_error`：若为高，BRESP 返回了非 OKAY 响应

### USER Port 读操作时序

```
user_rd_start  ──┐┌──
                 └┘
user_rd_valid  ──────────┐┌┐┌┐────
user_rd_data   ──────────XaXbXc───
user_rd_ready  ─────────────┐┌┐┌──
```

1. 设置 `user_rd_addr` 和 `user_rd_len`
2. 发送 `user_rd_start` 单周期脉冲
3. 在 `user_rd_valid & user_rd_ready` 握手时逐拍接收数据

### 仿真运行

两套仿真流程：

```bash
# ① iverilog 流程 (快, 无需 Vivado)
cd sim && ./run_sim.sh            # 编译 → 仿真 → 波形检查 → 打开 gtkwave

# ② Vivado 自动化流程 (make + tcl, 每步独立子脚本)
make all                         # 全流程: 建工程 → 仿真(+VCD检查) → 综合 → 最终检查
make sim                         # 仿真: 建/开工程 + xsim 仿真 + VCD 波形检查
make synth                       # 综合: synth_design + 报告 + 网表 checkpoint
make check                       # 仅检查已有 VCD 波形 (不启动 Vivado)
make project                     # 仅创建工程 (已存在则复用)
make clean                       # 删除日志与全部产物
```

> 详细说明见 [scripts/doc/make_tcl自动化使用说明.md](scripts/doc/make_tcl自动化使用说明.md)，
> 环境搭建与脚本原理见 [scripts/doc/Vivado自动化脚本设计教程.md](scripts/doc/Vivado自动化脚本设计教程.md)。

---

## 文档索引

| 文档 | 内容 |
|------|------|
| [AXI_FULL_Master_With_USER_Port使用说明.md](doc/AXI_FULL_Master_With_USER_Port使用说明.md) | **模块使用说明**（端口/时序/使用流程/注意事项）|
| [architecture.md](doc/architecture.md) | 完整架构设计、模块接口、数据流 |
| [issue_tracker.md](doc/issue_tracker.md) | 16 个问题的发现、分析与修复记录 |
| [fifo_design.md](doc/fifo_design.md) | 异步 FIFO 设计 (格雷码 CDC) |
| [tb_design_plan.md](doc/tb_design_plan.md) | Testbench 设计 (23 个测试用例) |
| [outstanding_design.md](doc/outstanding_design.md) | Outstanding 事务支持设计 |
| [out_of_order_design.md](doc/out_of_order_design.md) | Out-of-Order 响应支持设计 |
| [make_tcl自动化使用说明.md](scripts/doc/make_tcl自动化使用说明.md) | make/tcl/bash 自动化快速使用 |
| [Vivado自动化脚本设计教程.md](scripts/doc/Vivado自动化脚本设计教程.md) | 环境搭建 → 脚本架构 → 原理教程 |
