# 测试方案 — Outstanding 功能（TB 阶段）

> 验证环境：iverilog 快速流程（run_sim.sh → tb_axi_master_simple.sv + check_vcd.py），本设备无 Vivado

## 测试目标

验证 Outstanding 改造的正确性：AW/AR 流水线、W 串行（AXI4 无 WID）、B 匹配释放槽位、R 保序匹配、ready_start 指示、与单事务兼容。

## 兼容性适配（旧 TB → 新 TB）

| # | 问题 | 处理 |
|---|------|------|
| A-1 | 从机无 BID 输出（m_axi_bid 悬空 Z → B 匹配死锁） | 从机加 bid 端口，AW 握手锁存 awid 回显 |
| A-2 | TB 显式传 C_M_AXI_ID_WIDTH=1，与 4 槽 2 位槽号冲突（$error） | 删除显式传参（用顶层默认自适应 = 2），m_axi_awid/bid 改 [1:0] |
| A-3 | `dut.axi_wr_master_inst.state` 层次引用失效（v2 无此信号） | 改为等 B 握手（串行场景不会错过） |
| A-4 | 新端口 user_wr/rd_ready_start 未连接 | TB 增加 reg 连接 |
| A-5 | 从机 AW/AR 一次只接受 1 个（awready=~aw_latched） | 从机升级为 AW/AR 队列（深度 16），支持多 outstanding |
| A-6 | 从机队列数组深度 8，但 head/tail 为 4 位指针（0~15）直接作索引 | TC7 起（指针到 8）越界读 x → 数组扩容 [0:15] |
| A-7 | exp_mem [0:1023] 越界（TC6 地址 0x400=1024） | 扩容 [0:4095]（与从机 mem 一致） |

## 测试用例（新增 TC6~TC10，保留 TC1~TC5）

| 编号 | 场景 | 验证点 |
|------|------|--------|
| TC1~TC5 | 原有单事务场景（回归） | 改造后单事务行为不变（MAX=4 但每次 1 个） |
| TC6 | 写 outstanding：3 个写事务背靠背 start（len=4/2/4，不同地址） | AW 流水线、W 串行、B 匹配释放、数据正确（写后读回校验） |
| TC7 | 读 outstanding：3 个读事务背靠背 start | AR 流水线、R 保序匹配、数据逐拍比对 |
| TC8 | 混合并发：写 2 + 读 2 交错 | 读写通道独立并发 |
| TC9 | 槽满检查：连续 4 个写 start 后 user_wr_ready_start=0 | ready_start 语义 |
| TC10 | 单拍事务并发（len=1 ×2 写 + ×2 读） | 单拍 WLAST/RLAST 在 outstanding 下正确 |

## 激励策略

- 数据 pattern：seed+i 递增（沿用），exp_mem 逐拍记录，写后读回比对
- 新增 task：`wr_burst_nowait`（发 start+数据不等完成）、`rd_burst_nowait`（发 start 不等完成）、`wait_wr_all`/`wait_rd_all`（等全部槽位 FREE，层次引用 slot_state 展开）
- 等待完成：等 B 握手（m_axi_bvalid）替代 state 引用

## 检查机制（check_vcd.py 扩展）

| 检查项 | 期望 |
|--------|------|
| test_done/test_pass | 1/1 |
| 写事务数（BVALID 上升沿） | 15：TC1/3/4/5(4) + TC6(3) + TC8(2) + TC9(4) + TC10(2) |
| 读事务数（RLAST 上升沿） | 20：TC2/3/4/5(4) + TC6校验(3) + TC7(3) + TC8(4) + TC9(4) + TC10(2) |
| 数据抽查 | TC1-5 首拍 4 个（0x10/A5/20/30）回归比对；TC6-10 背靠背事务 valid 可能连续（跨事务无上升沿），首拍识别不可靠，由 TB 逐拍比对（test_pass）保证 |

## 非功能

- 语法：reg/wire/always/initial/task（iverilog 兼容）
- 超时保护：沿用 500us
- 运行时间 < 2s
