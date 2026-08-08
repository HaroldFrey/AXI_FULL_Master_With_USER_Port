# sim 目录 — 编译与仿真使用说明

本目录提供 AXI_FULL_Master_With_USER_Port 的**简单测试平台**，使用开源工具链
（iverilog + gtkwave）即可完成编译、仿真和波形查看，无需 Vivado。

---

## 文件说明

| 文件 | 说明 |
|------|------|
| `tb_axi_master_simple.sv` | 简单语法测试平台（5 个用例：基本写/基本读/单拍/用户读反压/用户写反压），内置极简 AXI Slave |
| `check_vcd.py` | 解析 VCD 波形、独立判断仿真是否成功的脚本（仅用 Python 标准库） |
| `tb_axi_master_simple.out` | iverilog 编译产物（可重新生成） |
| `tb_axi_master_simple.vcd` | 仿真波形文件（可重新生成） |
| `run_sim.sh` | 一键脚本：编译 → 仿真 → 波形检查 → 打开 gtkwave |

---

## 零、一键脚本（推荐）

```bash
cd D:\Stduy\AXI_FULL_Master_With_USER_Port\sim
./run_sim.sh              # 一键完成编译 + 仿真 + 波形检查 + 打开波形
./run_sim.sh --no-check   # 跳过波形检查
./run_sim.sh --no-gui     # 不自动打开 gtkwave
```

---

## 一、编译

在 **sim 目录**下执行（所有 RTL + 本测试平台一起编译）：

```bash
iverilog -g2012 -o tb_axi_master_simple.out -s tb_axi_master_simple \
  ../rtl/AXI_FULL_Master_With_USER_Port/AXI_FULL_Master_With_USER_Port.v \
  ../rtl/AXI_FULL_Master_With_USER_Port/axi_wr_master.v \
  ../rtl/AXI_FULL_Master_With_USER_Port/axi_rd_master.v \
  ../rtl/AXI_FULL_Master_With_USER_Port/Data_RX.v \
  ../rtl/AXI_FULL_Master_With_USER_Port/Data_TX.v \
  ../rtl/FIFO/fifo_async.v \
  tb_axi_master_simple.sv
```

- `-g2012`：启用 SystemVerilog 语法
- `-s tb_axi_master_simple`：指定顶层模块（避免与从机模块混淆）

---

## 二、仿真

```bash
vvp tb_axi_master_simple.out
```

仿真结束会打印各用例结果，全部通过时显示：

```
 写事务数: 4   读事务数: 4
 结果    : ALL PASS
```

同时自动生成波形文件 `tb_axi_master_simple.vcd`。

---

## 三、查看波形

```bash
gtkwave tb_axi_master_simple.vcd
```

gtkwave 中可观察关键信号，例如：

- `user_wr_start` / `user_wr_valid` / `user_wr_data_in` / `user_wr_ready`：用户写侧握手
- `user_rd_valid` / `user_rd_data_out` / `user_rd_ready`：用户读侧握手
- `m_axi_awvalid/awready`、`m_axi_wvalid/wready/wdata/wlast`、`m_axi_bvalid/bready`：AXI 写通道
- `m_axi_arvalid/arready`、`m_axi_rvalid/rready/rdata/rlast`：AXI 读通道
- `test_done` / `test_pass`：测试结束标志与总体结果（test_pass=1 表示数据比对全部通过）

---

## 四、自动检查仿真结果

```bash
python check_vcd.py tb_axi_master_simple.vcd
```

脚本独立解析 VCD 波形，检查 4 项内容，全部通过时退出码为 0：

1. TB 判定（`test_done` / `test_pass`）
2. 写事务次数（`m_axi_bvalid` 上升沿，应为 4）
3. 读事务次数（`m_axi_rlast` 上升沿，应为 4）
4. 每次读事务首拍数据抽查（应与种子一致：0x10 / 0xA5 / 0x20 / 0x30）

---

## 五、一条龙命令

```bash
cd D:\Stduy\AXI_FULL_Master_With_USER_Port\sim

# 编译 → 仿真 → 自动检查
iverilog -g2012 -o tb_axi_master_simple.out -s tb_axi_master_simple \
  ../rtl/AXI_FULL_Master_With_USER_Port/*.v ../rtl/FIFO/fifo_async.v tb_axi_master_simple.sv
vvp tb_axi_master_simple.out
python check_vcd.py tb_axi_master_simple.vcd

# 查看波形
gtkwave tb_axi_master_simple.vcd
```

---

## 说明

- 测试平台使用简单 SystemVerilog 语法（仅 reg/wire/always/initial/task），便于阅读和修改。
- 三时钟域（clk_wr / clk_rd / clk_axi）在测试平台中均使用 100MHz 同频时钟。
- 本目录的 `tb_axi_master.sv`（复杂 TB）与 `axi_slave_bfm.sv` / `tb_pkg.sv` 为原工程
  测试平台，与本简单测试平台相互独立。
