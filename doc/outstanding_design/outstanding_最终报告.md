# 最终报告 — Outstanding 功能（RTL 阶段）

## 交付内容

| 文件 | 说明 |
|------|------|
| rtl/.../axi_wr_master.v | 写通道 Outstanding 控制器（槽位表 + AW/W/B 调度） |
| rtl/.../axi_rd_master.v | 读通道 Outstanding 控制器（槽位表 + AR/R 保序调度） |
| rtl/.../AXI_FULL_Master_With_USER_Port.v | 顶层（MAX 参数 + ready_start 端口） |
| doc/outstanding_需求分析.md | A0 需求（已确认） |
| doc/outstanding_设计方案.md | A1 方案（对原设计 4 点修订） |
| doc/outstanding_语法解析.md | A2 关键语法 |
| doc/outstanding_审查报告.md | A3 审查循环（2 轮通过，6 问题闭环） |
| doc/outstanding_问题追踪.md | A4 问题与局限 |

## 验证状态

- iverilog -g2012 全 RTL 编译通过（无警告）
- 2 轮审查循环通过（修复地址自增公式、ID 位宽适配等 6 项）
- A5 迭代：无需求变更

## 综合策略建议（本设备无 Vivado，供有 Vivado 环境时参考）

- 设计特征：槽位寄存器阵列（≤8 槽）、`%` 参数取模轮询（综合为回绕比较）、桶形无、FSM 少量
- 推荐流程：`synth_design -top AXI_FULL_Master_With_USER_Port -directive default`，无需特殊属性
- 注意：`%` 对非 2 的幂槽位数会多消耗 LUT（建议槽位数用 2/4/8）
- 综合验证留待有 Vivado 的设备执行（本项目另一设备已有完整 make+tcl 自动化流程）

## 仿真验证结论（B/C 阶段，2026-08-12）

**iverilog 快速流程全部通过（本设备验证方式）**：

| 验证项 | 结果 |
|--------|------|
| TC1~TC5 基本回归（写/读/单拍/反压） | ALL PASS |
| TC6 写 Outstanding（3 事务并发 AW 流水 + W 串行 + 读回校验） | ALL PASS |
| TC7 读 Outstanding（3 事务并发 AR 流水 + R 保序） | ALL PASS |
| TC8 混合并发（写 2 + 读 2 交错） | ALL PASS |
| TC9 槽满检查（4 槽全占用 ready_start=0） | ALL PASS |
| TC10 单拍事务并发（len=1 ×2 写 ×2 读） | ALL PASS |
| check_vcd.py 波形独立检查（test_done/test_pass、写 15、读 20、TC1-5 首拍回归） | ALL PASS |

**仿真阶段修复 6 项**（详见 outstanding_问题追踪.md O-07~O-12）：
- DUT：读通道槽释放缺 RVALID 检查（单拍读死锁）
- TB 从机：队列数组越界（8→16）、exp_mem 越界
- FIFO：FWFT 弹空/预取在同步时钟+背靠背流水下的误判与竞争 → 读侧改标准模式
- TB 读协议：ready 时序与数据拍错位 → 每笔拉高/采样/拉低结构
- TC9 用例：wr_burst_nowait 无法制造槽满 → 背靠背 start + 补数据

**遗留**：Vivado 综合验证留待有 Vivado 的设备执行（设计参数 MAX_OUTSTANDING_WR/RD、槽位数 2/4/8 建议保持 2 的幂）。
