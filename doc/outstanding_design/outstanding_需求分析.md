# 需求分析 — AXI FULL Master Outstanding 事务支持

> 基于 doc/outstanding_design.md 设计方案（2026-07-23），结合当前代码现状细化
> 日期：2026-08-12 ｜ 分支：feature/outstanding

## 功能目标

为 AXI_FULL_Master_With_USER_Port 增加 Outstanding 能力：**写通道多事务 AW 流水线**（W 数据按 AXI4 无 WID 约束串行）+ **读通道多事务 AR 流水线**（R 数据保序），提升总线利用率。用户接口仅新增"是否有空闲槽"指示信号，ID 由 Master 自动管理。

## 当前代码现状（开发基线）

| 模块 | 现状 |
|------|------|
| axi_wr_master / axi_rd_master | 2 态 FSM（IDLE↔WRITE/READ），串行执行，WRITE/READ 期间忽略新 start |
| AXI_FULL_Master_With_USER_Port.v | 顶层纯实例化，USER 接口无 ID 端口 |
| Data_RX / Data_TX | FWFT 异步 FIFO（32 深），天然串行化写数据；读数据反压 |
| C_M_AXI_ID_WIDTH | 默认 1（当前恒 0） |
| 数据宽度 | 8 bit（参数化） |

## 功能需求（编号 + 优先级）

| 编号 | 需求 | 优先级 | 说明 |
|------|------|--------|------|
| FR-1 | 写通道 Outstanding | P0 | 多个写事务可同时进行：AW 流水线发出（按 start 顺序），W 数据按 FIFO 顺序串行发送（AXI4 无 WID 约束），B 响应按 BID 匹配释放槽位 |
| FR-2 | 读通道 Outstanding | P0 | 多个读事务可同时进行：AR 流水线发出，所有事务**同一 ARID=0**（同 ID 保序方案），R 数据按 AR 顺序匹配槽位并透传用户 |
| FR-3 | 槽位管理 | P0 | 每通道可配置槽位表（MAX_OUTSTANDING_WR / MAX_OUTSTANDING_RD，默认 4），槽位状态机 FREE→ACTIVE→FREE |
| FR-4 | ready_start 指示 | P0 | 新增 user_wr_ready_start / user_rd_ready_start：有空闲槽位时拉高，用户仅在 ready_start=1 时可发起新事务 |
| FR-5 | ID 自动管理 | P0 | 写：槽位分配 ID（AWID=槽号，高位补 0）；读：ARID 恒 0；BID 匹配定位槽位 |
| FR-6 | 每事务地址/长度锁存 | P0 | start 时采样 addr/len 到槽位；写完成后槽位地址按突发拍数×W 字节自增（len 语义 = 拍数 1~256） |
| FR-7 | 错误上报 | P1 | 任一槽位收到非 OKAY 响应即 user_wr_error / user_rd_error 置位，新 start 清零（保持现有语义） |
| FR-8 | 反压 | P1 | 无空闲槽位→ready_start=0；写 FIFO 满→W 反压（现有 Data_RX 逻辑）；读 FIFO 满→RREADY 反压（现有逻辑） |
| FR-9 | 兼容性 | P1 | MAX_OUTSTANDING=1 时退化为单事务行为；新端口有默认值（旧 TB 不连接可编译）；其余 USER 接口不变 |
| FR-10 | 验证 | P0 | 扩展 tb_axi_master_simple.sv + check_vcd.py（run_sim.sh 流程不变），覆盖并发事务场景 |

## 接口规格（变更部分）

### 新增端口（顶层 AXI_FULL_Master_With_USER_Port）
| 信号 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| user_wr_ready_start | output | 1 | 写通道有空闲槽位（可接受新事务） |
| user_rd_ready_start | output | 1 | 读通道有空闲槽位 |

### 新增参数
| 参数 | 默认值 | 说明 |
|------|--------|------|
| MAX_OUTSTANDING_WR | 4 | 写通道槽位数（1~8） |
| MAX_OUTSTANDING_RD | 4 | 读通道槽位数（1~8） |

## 非功能需求

- 可综合：纯时序/组合逻辑，槽位表用寄存器阵列（≤8 槽，面积可控）
- 与现有架构一致：读写通道独立模块（axi_wr_master_v2 / axi_rd_master_v2 或原地改造），顶层只接线
- iverilog 兼容：-g2012 可编译
- 资源：8 槽 × (32 地址 + 8 长度 + 状态) ≈ 数百 FF，可接受

## 约束条件

- **写数据顺序**：用户须按 start 顺序向 FIFO 写入对应事务数据（FIFO 顺序 = W 发送顺序，AXI4 无 WID 无法交叉）
- **读保序**：从机对同一 ARID 必须按 AR 顺序返回 R 数据（AXI 规范保证）；从机乱序返回不属于本功能范围（out-of-order 独立功能）
- 不做 out-of-order / ID 重映射 / 多 ID 交织

## 用户确认（checkbox）

- [x] 读通道：同 ID + 保序（简化方案）
- [x] 开发范围：读写一次完成
- [x] USER 接口：仅 ready_start（ID 自动分配）
- [x] 验证：iverilog 快速流程（run_sim.sh），本设备无 Vivado
- [ ] 以上需求确认，进入 A1 方案设计
