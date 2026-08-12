# 审查报告 — Outstanding 功能（RTL 阶段）

## 第 1 轮审查（2026-08-12）

### 步骤 1：代码级审查（verilog-sv-language 规范，来源：代码审查）

| # | 级别 | 所属模块 | 问题 | 结论 |
|---|------|---------|------|------|
| O-01 | 🔴 严重 | axi_wr_master / axi_rd_master | 地址自增公式错误：写成 `(len+1)×W`，混淆"长度(拍数)"与"ALEN"。INCR 突发覆盖 **len×W** 字节（原实现正确，审查中发现"修正"是画蛇添足） | [已修复] 改回 `slot_len[i] × BYTES_PER_BEAT`，同步修正需求/设计文档 |
| O-02 | 🟡 中等 | 顶层 | `C_M_AXI_ID_WIDTH` 默认 1 装不下 4 槽的 2 位槽号 → 负重复拼接 `{(−1){...}}` 编译错误 | [已修复] 参数顺序调整 + ID 位宽自动适配 `(MAX_OUTSTANDING_WR>1)?$clog2(MAX_OUTSTANDING_WR):1` + axi_wr_master 内 $error 防护 |
| O-03 | 🟢 低 | 顶层 | 新增 user_rd_ready_start 端口声明缺逗号（语法错误） | [已修复] 补逗号 |

**代码级通过项**：可综合性（无 initial/fork/#delay，$error 为编译期）✓；锁存器（always_comb 全默认赋值）✓；赋值规范（posedge 非阻塞）✓；复位安全（槽位/指针/锁存/计数全复位）✓；CDC（无新增跨时钟逻辑）✓；AXI 协议检查（AW 保序 = W 顺序、AWVALID 期间数据锁存稳定、WVALID 不依赖 WREADY、B 匹配 BID、R 保序）✓。

### 步骤 2：补充审查（full-review，来源：full-review）

| # | 级别 | 位置 | 问题 | 结论 |
|---|------|------|------|------|
| O-04 | 🟡 中等 | 设计方案_工作流程 | 示例时序不准确：组合扫描看到前一拍槽位状态，wr_start 分配与 AW 发起至少隔 1 拍（示例写同拍） | [已修复] 示例修正 + 注释说明 |
| O-05 | 🟡 中等 | 设计方案_资源预估 | FF 估算 ~150 低估：实际 ~400（两通道槽位 176+168 + 指针/锁存 ~50） | [已修复] 更新 ~400 |
| O-06 | 🟢 低 | axi_rd_master | `rd_cnt` 计数器冗余（RLAST 由从机驱动，本地计数无使用） | [已修复] 删除 |

**full-review 通过项**：文档↔代码参数一致（MAX_OUTSTANDING_WR/RD、SLOT_ID_W 规则）✓；端口接线一致（顶层↔子模块 ready_start）✓；跨文件契约（顶层参数顺序、实例化传递）✓；需求 FR-1~FR-10 全覆盖 ✓；旧 TB 兼容性（state 层次引用失效）→ 已知，B 阶段适配。

### 第 1 轮结论

6 个问题全部修复。进入回归审查。

## 第 2 轮审查（回归，2026-08-12）

- 重新编译（iverilog -g2012，RTL 全文件）→ **通过，无警告**
- 逐项核对 O-01~O-06 修复 ✓
- 协议再验（写 2 事务重叠 / 读 2 事务保序 / B 乱序 / 单拍 / 槽位回绕逐拍推演）→ 正确 ✓
- full-review 复查：无新问题 ✓

### 第 2 轮结论

**连续一轮无新问题 → A3 审查通过**，进入 A4 问题追踪。

## 第 3 轮审查（仿真验证后复查，2026-08-12，B 阶段）

仿真（TC1~TC10 + check_vcd.py ALL PASS）后，对 C 阶段全部修改点做代码级复查：

| # | 级别 | 位置 | 修改 | 复查结论 |
|---|------|------|------|---------|
| O-07 | 🔴 | axi_rd_master.v S_R_ACTIVE | 槽释放条件加 `M_AXI_RVALID && M_AXI_RREADY`（真实握手） | ✓ 单拍读死锁解除；多拍读不受影响（RLAST 只在末拍成立） |
| O-08 | 🔴 | tb axi_slave_simple | AW/AR 队列数组扩容 [0:15]（4 位指针全范围） | ✓ 指针 0~15 不再越界；空满判断（head==tail / head+1==tail）语义不变 |
| O-09 | 🟡 | tb exp_mem | 扩容 [0:4095] | ✓ 与从机 mem 同容量，覆盖最大地址 0x70F |
| O-10 | 🔴 | fifo_async.v FWFT + Data_TX.v | 读侧改标准模式（MODE=1）；FWFT 弹空判据改 bin 保守比较 | ✓ 标准模式 dout 组合直读 mem[rd_ptr] 无预取/弹空/竞争；FWFT（Data_RX 写侧）bin 判据在写侧验证通过 |
| O-11 | 🔴 | tb 读任务（rd_burst/rd_collect） | 每笔"拉高→等生效→while 数据拍→阻塞采样→拉低→比对" | ✓ 数据拍与弹出拍同步；末笔后无拉高 → 无多余弹出；采样在数据拍（mem 组合直读无竞态） |
| O-12 | 🟡 | tb TC9 | 背靠背 start（只发 start）+ wr_data_only 补数据 | ✓ 4 槽可同时占用；ready_start 语义验证有效 |

**复查通过项**：
- 修复后 DUT 文件（axi_wr_master / axi_rd_master / 顶层）与 A 阶段审查结论一致，无新增问题 ✓
- fifo_async FWFT 分支（Data_RX 用）bin 判据与注释一致，Standard 分支未改动 ✓
- TB 读协议三个任务（rd_burst / rd_burst_pause / rd_collect）拍级语义一致 ✓

### 第 3 轮结论

**全部修复验证通过，无新问题。** C 阶段仿真（iverilog 快速流程）ALL PASS。
