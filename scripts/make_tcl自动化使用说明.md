# Make + TCL 自动化 Vivado 仿真使用说明

> 用 **make + tcl + bash** 三种脚本语言，自动完成 Vivado 工程建立、仿真、波形检查与综合。
> 每个步骤一个独立子脚本，方便扩展和迁移。

---

## 1. 快速开始

在**项目根目录**执行（Git Bash 或任何终端）：

```bash
make all       # 全流程: 建工程 → 仿真 → 综合 → 最终检查 (不执行 clean)
make sim       # 仿真: 建/开工程 + xsim 仿真 + VCD 波形检查
make check     # 仅检查已有 VCD 波形 (不启动 Vivado, 快)
make synth     # 综合: 建/开工程 + synth_design + 报告
make project   # 仅创建工程 (已存在则复用)
make clean     # 删除日志与所有输出产物
```

预期输出（`make sim` 末尾）：

```
============ 仿真结果摘要 ============
   结果    : ALL PASS
  $finish called at time : 2935 ns : ...
=====================================
INFO: 波形已保存 -> .../sim_run/tb_axi_master_simple.vcd
INFO: 运行 check_vcd.py 检查波形
INFO: VCD 检查通过 (ALL PASS)
```

- **xsim 结果** `ALL PASS` = TB 5 个用例全部通过
- **VCD 检查通过** = check_vcd.py 4 项检查（TB 判定/读写事务次数/数据抽查）全过
- **检查日志**保存在 `sim/check_vcd.log`（每次检查覆盖写入）

---

## 2. 环境要求

| 工具 | 位置 | 说明 |
|------|------|------|
| make (GNU Make 4.4.1) | `D:\App_install_Lcoation\make\bin\make.exe` | 免安装, 已加入用户 PATH |
| Vivado 2019.2 | `D:\App_install_Lcoation\Vivado201902\Vivado\2019.2\bin\vivado.bat` | Makefile `VIVADO` 变量 |
| Python 3.12 (embeddable) | `D:\App_install_Lcoation\python\python.exe` | 免安装, 供 VCD 检查 |
| 目标器件 | `xc7z020clg400-2` (ZYNQ-7020) | `scripts/project.tcl` 的 `prj_part` |

> 三者的完整安装过程见 [Vivado自动化脚本设计教程.md](Vivado自动化脚本设计教程.md)。

---

## 3. 脚本架构（每个步骤一个子脚本）

```
项目根/
├── Makefile                # make 入口 (调度)
└── scripts/
    ├── project.tcl         # 建工程 (幂等) — 工程名/器件/Python 路径配置中心
    ├── add_sources.tcl     # 加源文件 (幂等, 公共子脚本)
    ├── sim.tcl             # 仿真 (xvlog → xelab → xsim → 结果摘要)
    ├── check_vcd.tcl       # VCD 波形检查 (调 sim/check_vcd.py)
    └── synth.tcl           # 综合 (synth_design → 报告 → checkpoint)
```

| 步骤 | 子脚本 | 被谁调用 | 产物 |
|------|--------|----------|------|
| 建工程 | `project.tcl` | make project / sim / synth | `vivado_prj/` |
| 加源文件 | `add_sources.tcl` | sim / synth | (工程内) |
| 仿真 | `sim.tcl` | make sim | `sim_run/` (日志+VCD) |
| 波形检查 | `check_vcd.tcl` | make sim (内置) / make check | 检查结果 |
| 综合 | `synth.tcl` | make synth | `synth_run/` (报告+网表) |

**设计原则**：每步独立 → 可单独调用、可替换实现、方便迁移到其他工程/工具链。

---

## 4. 工作原理

```
┌──────────┐  make 目标    ┌───────────────┐  -source  ┌────────────────────┐
│  make    │ ────────────▶ │  vivado.bat   │ ────────▶ │  scripts/*.tcl     │
│ (Makefile)│ project/sim/  │  -mode batch  │           │  (Tcl 核心脚本)     │
│          │ check/synth/  └───────────────┘           └─────────┬──────────┘
└──────────┘   all/clean                                            │
                                                  ┌───────────────┼───────────────┐
                                                  ▼               ▼               ▼
                                            ┌──────────┐   ┌──────────┐   ┌──────────┐
                                            │ project  │   │ add_     │   │ check_   │
                                            │ .tcl     │   │ sources  │   │ vcd.tcl  │
                                            └──────────┘   └──────────┘   └──────────┘
                                             (幂等建工程)   (幂等加文件)   (VCD 检查)
```

| 关键机制 | 说明 |
|----------|------|
| 幂等工程 | 工程已存在 → `open_project` 复用；不存在 → 创建。**不每次重建** |
| 幂等加文件 | 文件已在 fileset → skip；不在 → add（可重复调用） |
| source 复用 | 子脚本定义 `proc` 供上层调用；独立运行时用 `argv0` 判定 |
| 绕开 launch_simulation | Vivado 2019.2 在部分 Windows 环境 spawn 失败 (Broken pipe)，改手动 xvlog/xelab/xsim |
| 产物隔离 | 工具工作目录切到 `sim_run/`，中间文件不散落项目根 |
| 日志集中 | `-log log/*.log -journal log/*.jou`，make clean 一键清理 |

---

## 5. 目录与产物

```
项目根/
├── log/       [生成] vivado_*.log / *.jou   (Vivado 会话日志)
├── make_run/  [生成] project/sim/synth/check 每次命令的打印信息
├── vivado_prj/ [生成] axi_full_master.xpr    (工程, 可 GUI 打开)
├── sim_run/   [生成] xvlog/xelab/xsim 日志 + tb_axi_master_simple.vcd 波形
├── synth_run/ [生成] utilization.rpt / timing.rpt / post_synth.dcp
└── rtl/ sim/ doc/ scripts/  (源码, make clean 不碰)
```

| 文件 | 来源 | 用途 |
|------|------|------|
| `make_run/sim.log` | make sim 输出 tee 存档 | make 打印信息 (终端+文件同步) |
| `sim_run/xsim.log` | xsim | 仿真日志 (**ALL PASS 在这**) |
| `sim_run/tb_axi_master_simple.vcd` | TB `$dumpfile` | 波形, GTKWave 可打开 |
| `synth_run/utilization.rpt` | report_utilization | 资源利用率 |
| `synth_run/timing.rpt` | report_timing | 时序报告 |
| `synth_run/post_synth.dcp` | write_checkpoint | 综合后网表 |

---

## 6. 常见问题

### Q1: 为什么不用 `launch_simulation`？

Vivado 2019.2 的 `launch_simulation` 在部分 Windows 环境（如 Win11）报
`ERROR: [Common 17-180] Spawn failed: Broken pipe`（0 秒失败，已知问题）。
脚本改为在 Tcl 里手动调用 `xvlog → xelab → xsim`（绝对路径），效果相同且更可控。

### Q2: 输出中文乱码？

**当前状态**：tcl 脚本打印已统一为英文，日志全部 UTF-8/ASCII 无乱码 ✅
（python 检查输出用 `-X utf8` 强制 UTF-8，正常显示中文）。

**遗留问题**（已记录）：Vivado 读 tcl 源码按 GBK，tcl 打印中文乱码无法根治
（详见教程文档 §7"未决问题"一节，含全部尝试与结论）。

### Q3: 换测试平台 / 换器件？

- 换 TB：改 `scripts/add_sources.tcl` 的 TB 文件路径 + `scripts/sim.tcl` 的顶层名
- 换器件：改 `scripts/project.tcl` 的 `prj_part`（一处全局生效）

### Q4: make 命令找不到？

**实测结论：重开终端有时不生效**（终端可能缓存了旧环境快照），以下按推荐度排序：

```bash
# ① 当前终端临时加 PATH (最稳, 实测有效)
export PATH="/d/App_install_Lcoation/make/bin:$PATH"
make clean

# ② 全路径直接调用
D:/App_install_Lcoation/make/bin/make.exe clean
```

> 若想一劳永逸：确认用户 PATH 已含 `D:\App_install_Lcoation\make\bin`
> （PowerShell: `[Environment]::GetEnvironmentVariable("Path","User")`），
> 然后**完整退出并重开终端程序**（若在 VSCode 里则重载窗口）。

---

*更新日期：2026-08-11 · 配套教程：[Vivado自动化脚本设计教程.md](Vivado自动化脚本设计教程.md)*
