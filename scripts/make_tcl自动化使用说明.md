# Make + TCL 自动化 Vivado 仿真使用说明

> 用 **make + tcl + bash** 三种脚本语言，一键自动完成 Vivado 工程建立和仿真：
> `make sim` → 自动建工程 → 加源文件 → xsim 编译仿真 → 打印结果 → 保存波形

---

## 1. 快速开始

在**项目根目录**执行（Git Bash 或任何终端）：

```bash
make sim      # 一键: 建工程 + 编译 + 仿真 + 出波形
make clean    # 删除日志与所有输出产物, 恢复干净项目
```

预期输出（`make sim` 末尾）：

```
============ 仿真结果摘要 ============
   结果    : ALL PASS
  $finish called at time : 2935 ns : ...
=====================================
INFO: 波形已保存 -> .../sim_run/tb_axi_master_simple.vcd
```

- **`ALL PASS`** = 仿真验证通过（来自 xsim 日志）
- 波形文件 `sim_run/tb_axi_master_simple.vcd` 可用 GTKWave 打开

---

## 2. 环境要求

| 工具 | 位置 | 说明 |
|------|------|------|
| make (GNU Make 4.4.1) | `D:\App_install_Lcoation\make\bin\make.exe` | 免安装版, 若终端里 `make` 报 not found, 用全路径调用 |
| Vivado 2019.2 | `D:\App_install_Lcoation\Vivado201902\Vivado\2019.2\bin\vivado.bat` | Makefile 里已写死, 换版本改 `VIVADO` 变量即可 |
| 目标器件 | `xc7z020clg400-2` (ZYNQ-7020) | Makefile 里已写死, 换器件改 `scripts/sim.tcl` 的 `part` |

> Windows Git Bash 不自带 make（便携版 Git 无此组件），需要单独放置免安装版。
> 本机已在 `D:\App_install_Lcoation\make\` 安装 GNU Make 4.4.1（ezwinports, 无 DLL 依赖）。

---

## 3. 工作原理：三种脚本语言各司其职

```
┌──────────┐   make 目标  ┌───────────────┐  -source  ┌─────────────────────┐
│  make    │ ───────────▶ │  vivado.bat   │ ────────▶ │  scripts/sim.tcl    │
│ (Makefile)│  sim/clean   │  -mode batch  │           │  (TCL 核心脚本)      │
└──────────┘              └───────────────┘           └──────────┬──────────┘
                                                                  │ 内部步骤:
                                                                  ├─ create_project 建工程 (vivado_prj/)
                                                                  ├─ add_files      加 RTL + TB
                                                                  ├─ xvlog          编译 (SV-2012)
                                                                  ├─ xelab          链接顶层
                                                                  ├─ xsim -R        运行仿真
                                                                  └─ 提取结果打印    ALL PASS + VCD
```

### 3.1 make — 统一入口（调度者）

[Makefile](../Makefile) 只做两件事：**拼命令、管目录**。

```makefile
VIVADO := D:/App_install_Lcoation/Vivado201902/Vivado/2019.2/bin/vivado.bat
LOG_DIR := log

sim:
	mkdir -p $(LOG_DIR)
	$(VIVADO) -mode batch -notrace \
		-log $(LOG_DIR)/vivado.log -journal $(LOG_DIR)/vivado.jou \
		-source scripts/sim.tcl

clean:
	rm -rf $(LOG_DIR) vivado_prj sim_run xsim.dir .Xil ...
```

| make 目标 | 作用 |
|-----------|------|
| `make sim` | 建工程 + 编译 + 仿真一步完成 |
| `make clean` | 删除 log/、vivado_prj/、sim_run/ 及全部生成物 |

### 3.2 TCL — 核心执行者（做全部脏活）

[scripts/sim.tcl](sim.tcl) 是真正干活的脚本，分 4 段：

| 段 | TCL 命令 | 作用 |
|----|----------|------|
| ① 清理 | `file delete -force` | 删旧工程/产物, 保证可重复执行 |
| ② 建工程 | `create_project` / `add_files` / `set_property top` | 生成 `vivado_prj/*.xpr`（可 GUI 打开）, 加源文件 |
| ③ 编译仿真 | `xvlog` → `xelab` → `xsim -R` | 编译 RTL+TB → 链接顶层 → 运行到 `$finish` |
| ④ 收尾 | 读 xsim.log 提取 PASS/FAIL | 打印结果摘要, 拷贝 VCD 到 sim_run/ |

**运行方式**（Vivado 批处理模式, 无 GUI 全程无人值守）：

```bash
vivado.bat -mode batch -notrace -source scripts/sim.tcl
```

### 3.3 Bash — 替代入口（不想用 make 时）

Makefile 本质就是一行 bash 命令，不用 make 直接敲也完全等价：

```bash
# 等价于 make sim (需先建 log 目录)
mkdir -p log && \
D:/App_install_Lcoation/Vivado201902/Vivado/2019.2/bin/vivado.bat \
    -mode batch -notrace -log log/vivado.log -journal log/vivado.jou \
    -source scripts/sim.tcl

# 等价于 make clean
rm -rf log vivado_prj sim_run xsim.dir .Xil *.wdb *.pb
```

> 三种语言的分工：**make 管调度、tcl 管 Vivado 内部操作、bash 是底层命令**
> （make 的 recipe 和 bash 脚本本质都是 shell 命令）。

---

## 4. 目录与产物说明

```
项目根/
├── Makefile            # make 入口
├── scripts/
│   ├── sim.tcl         # Vivado 自动化脚本 (核心)
│   └── 本说明文档
├── vivado_prj/         # [make sim 生成] Vivado 工程 (.xpr, 可 GUI 打开)
├── sim_run/            # [make sim 生成] xvlog/xelab/xsim 日志 + VCD 波形
├── log/                # [make sim 生成] vivado.log / vivado.jou
└── rtl/  sim/  doc/    # 源码 (make clean 不碰)
```

| 文件 | 来源 | 用途 |
|------|------|------|
| `log/vivado.log` | vivado.bat `-log` | Vivado 运行完整日志 |
| `log/vivado.jou` | vivado.bat `-journal` | Vivado 命令历史 (下次运行会生成 .backup 备份) |
| `sim_run/xvlog.log` | xvlog `-log` | RTL/TB 编译日志 |
| `sim_run/xelab.log` | xelab `-log` | 链接日志 |
| `sim_run/xsim.log` | xsim `-log` | **仿真日志 (ALL PASS 在这)** |
| `sim_run/tb_axi_master_simple.vcd` | TB 内 `$dumpfile` | 波形, GTKWave 可打开 |
| `vivado_prj/axi_full_master.xpr` | `create_project` | 工程文件, 双击可在 GUI 中打开 |

---

## 5. 常见问题

### Q1: `make sim` 报 `Broken pipe` / 仿真没跑起来？

已解决。Vivado 2019.2 的 `launch_simulation` 命令在部分 Windows 环境（本机 Win11）存在
已知 bug：`ERROR: [Common 17-180] Spawn failed: Broken pipe`，0 秒失败。
**绕过方案**：本脚本不用 `launch_simulation`，而是在 TCL 里手动按非工程流程调用
`xvlog → xelab → xsim`（全部绝对路径），效果相同、更可控。

### Q2: 输出中文乱码？

Vivado 输出按本地编码（GBK）显示。在 Windows 终端执行 `chcp 65001` 后再跑；
或直接看日志文件（UTF-8 正常）。乱码不影响功能。

### Q3: 想换测试平台 / 换器件？

- 换 TB：改 `scripts/sim.tcl` 里的 `set top` 变量 + 段② 的 TB 文件路径
- 换器件：改 `scripts/sim.tcl` 里的 `set part` 变量（如 `xc7z035ffg676-2`）

### Q4: 想打开 Vivado GUI 调试波形？

`make sim` 生成工程后，双击 `vivado_prj/axi_full_master.xpr` 用 GUI 打开即可；
GUI 里的仿真（Tools → Launch Simulation）不受本脚本影响。

### Q5: make 命令找不到？

```bash
# 用全路径调用
D:/App_install_Lcoation/make/bin/make.exe sim
```

---

*更新日期：2026-08-11 · 配套脚本：scripts/sim.tcl · 配套入口：Makefile*
