# Vivado 自动化脚本设计教程

> 从零搭建：环境准备 → 脚本架构设计 → 各脚本原理 → 扩展指南。
> 目标：理解为什么这么设计、每个脚本怎么工作、如何迁移到其他工程。

---

## 目录

1. [为什么要脚本自动化](#1-为什么要脚本自动化)
2. [环境搭建](#2-环境搭建)
3. [脚本架构设计](#3-脚本架构设计)
4. [脚本原理详解](#4-脚本原理详解)
5. [各流程工作原理](#5-各流程工作原理)
6. [扩展与迁移指南](#6-扩展与迁移指南)
7. [常见问题与踩坑记录](#7-常见问题与踩坑记录)

---

## 1. 为什么要脚本自动化

手工 Vivado GUI 操作建工程 → 加文件 → 跑仿真，每次都要重复且易错。脚本自动化的收益：

| 收益 | 说明 |
|------|------|
| 可重复 | 一条命令得到相同结果，无手工遗漏 |
| 可验证 | 仿真结果 + VCD 检查双重确认，可接入 CI |
| 可迁移 | 每个步骤独立脚本，换工程/换工具链只改配置 |
| 可扩展 | 加新步骤（综合、实现、时序分析）只需新增脚本 + make 目标 |

**核心理念**：每个步骤一个独立子脚本，步骤之间通过 proc 复用，互不耦合。

---

## 2. 环境搭建

三个免安装工具（绿色模式：解压即用，不写注册表）：

### 2.1 GNU Make 4.4.1（调度器）

```bash
# 下载 (ezwinports, 无 DLL 依赖, ~400KB)
curl -L -o make.zip "https://sourceforge.net/projects/ezwinports/files/make-4.4.1-without-guile-w32-bin.zip/download"
# 解压到工具目录
mkdir -p D:/App_install_Lcoation/make && unzip make.zip -d D:/App_install_Lcoation/make
# 验证
D:/App_install_Lcoation/make/bin/make.exe --version    # GNU Make 4.4.1
```

> ⚠️ **Windows Git Bash 不自带 make**（便携版 Git 无此组件）。
> 加入 PATH：PowerShell 执行
> `[Environment]::SetEnvironmentVariable("Path", $env:Path + ";D:\App_install_Lcoation\make\bin", "User")`
>
> **实测经验**：重开终端可能仍不生效——Windows 新进程从**父进程**继承环境，
> 已运行的终端主进程（Windows Terminal / VSCode）缓存旧 PATH，新开标签页照样继承旧的。
> 要么完全退出终端程序（含后台进程）再开，要么直接用 `export PATH="/d/App_install_Lcoation/make/bin:$PATH"` 或全路径调用。

### 2.2 Vivado 2019.2（核心工具）

本机路径：`D:\App_install_Lcoation\Vivado201902\Vivado\2019.2\bin\vivado.bat`

batch 模式（无 GUI 跑 TCL 脚本）是自动化的基础：

```bash
vivado.bat -mode batch -notrace -log log/vivado.log -journal log/vivado.jou -source xxx.tcl
```

| 参数 | 作用 |
|------|------|
| `-mode batch` | 批处理模式，无 GUI 全程无人值守 |
| `-notrace` | 不打印 Tcl 命令回显 |
| `-log` / `-journal` | 日志/命令历史写指定文件（集中管理，不散落根目录） |
| `-source` | 执行 Tcl 脚本 |

### 2.3 Python 3.12（波形检查）

check_vcd.py 只用标准库，embeddable 版足够：

```bash
# 下载 (python.org 直连慢, 用华为云镜像 ~10MB, 秒下)
curl -L -o python-embed.zip "https://mirrors.huaweicloud.com/python/3.12.10/python-3.12.10-embed-amd64.zip"
mkdir -p D:/App_install_Lcoation/python && unzip python-embed.zip -d D:/App_install_Lcoation/python
D:/App_install_Lcoation/python/python.exe --version   # Python 3.12.10
```

> ⚠️ Windows 的 `python` 命令可能是 **Microsoft Store 占位符**（运行无输出、退出码非 0）。
> 判断方法：`python --version` 无输出 = 占位符，需装真 Python。

---

## 3. 脚本架构设计

### 3.1 分层结构

```
项目根/
├── Makefile                # L1 调度层: 用户入口, 拼命令管目录
└── scripts/                # L2 执行层: Tcl 脚本, 做 Vivado 内部操作
    ├── project.tcl         #   配置中心 + 幂等建工程
    ├── add_sources.tcl     #   公共源文件管理
    ├── sim.tcl             #   仿真主脚本
    ├── check_vcd.tcl       #   波形检查子脚本
    └── synth.tcl           #   综合主脚本
```

### 3.2 各脚本职责与依赖

```
Makefile (调度)
   │
   ├── project ──────────▶ project.tcl        (独立运行)
   ├── sim ──────────────▶ sim.tcl ──source──▶ project.tcl / add_sources.tcl / check_vcd.tcl
   ├── synth ────────────▶ synth.tcl ─source─▶ project.tcl / add_sources.tcl
   ├── check ────────────▶ (直接 python, 不启动 Vivado)
   └── clean ────────────▶ (rm -rf 产物目录)
```

| 脚本 | 提供/执行 | 设计要点 |
|------|-----------|----------|
| `project.tcl` | 全局配置变量 + `ensure_project` proc | **配置中心**：工程名/器件/Python 路径改一处全局生效 |
| `add_sources.tcl` | `add_design_sources` / `add_testbench_sources` / `add_all_sources` | **幂等**：文件已加则 skip |
| `sim.tcl` | 仿真主流程 | 手动 xvlog/xelab/xsim（绕开 launch_simulation bug） |
| `check_vcd.tcl` | `run_vcd_check` proc | 调 Python 解析 VCD，失败即抛错阻断 |
| `synth.tcl` | 综合主流程 | synth_design + 报告 + checkpoint |

### 3.3 为什么这样划分

用户需求驱动（**每步独立，方便扩展迁移**）：

1. **工程与流程分离**：工程是长期资产（可放约束/IP/后续 GUI 调试），不随每次仿真重建 → `project.tcl` 幂等设计
2. **文件列表集中管理**：RTL 文件增删只改 `add_sources.tcl` 一处 → 加 TB 同理
3. **检查独立**：VCD 检查可用 `make check` 单独重跑（不启动 Vivado，快）
4. **语言分工**：make 管调度、tcl 管 Vivado 内部操作、bash/python 做外部工具（下载、检查）

---

## 4. 脚本原理详解

### 4.1 调用链

```
make sim
  └─> vivado.bat -mode batch -source scripts/sim.tcl
        ├─ source scripts/project.tcl        (拿配置 + ensure_project proc)
        ├─ source scripts/add_sources.tcl    (拿加文件 proc)
        ├─ source scripts/check_vcd.tcl      (拿检查 proc)
        ├─ ensure_project                    # 开/建工程
        ├─ add_all_sources                   # 加文件
        ├─ exec xvlog / xelab / xsim         # 编译仿真
        └─ run_vcd_check                     # 波形检查
```

### 4.2 Tcl source 复用与独立运行判定（关键技巧）

子脚本既要能**独立运行**（`make project`），又要能被**其他脚本 source**（`sim.tcl` 复用其 proc）。
Tcl 里怎么区分？

```tcl
# Tcl 特性:
#   $argv0      = 主脚本路径 (source 时不变)
#   info script = 当前正在执行的脚本 (source 子脚本时变成子脚本路径)

# 独立运行判定: 两者相等 ⇔ 本文件是主脚本
if {[string equal [file tail [info script]] [file tail $argv0]]} {
    # 独立运行分支: 执行 + 退出
    ensure_project
    close_project
    exit
}
# 被 source 时: 只定义 proc 和变量, 不执行任何动作
```

### 4.3 幂等设计

```tcl
# 工程幂等: 已打开/已存在 → 复用; 否则创建
proc ensure_project {} {
    if {![catch {current_project} p] && $p ne ""} { return }   ;# 已打开
    if {[file exists $xpr]} { open_project $xpr }               ;# 已有工程
    else                    { create_project ... }              ;# 新建
}

# 文件幂等: 已在 fileset 则 skip
proc add_file_if_missing {fset path} {
    if {[llength [get_files -quiet [file normalize $path]]] == 0} {
        add_files -norecurse -fileset $fset $path
    }
}
```

### 4.4 exec 子进程的工作目录（Windows 大坑）

Vivado 的 Tcl 里 `cd` 对 `exec` 子进程**不生效**（子进程继承进程启动时的工作目录）。
要在指定目录运行 xvlog/xsim，必须用 cmd 包装：

```tcl
# Tcl 的 cd 无效:
#   cd $work_dir
#   exec xvlog ...            ;# 仍在项目根运行, 产物散落!

# 正确: cmd /c "cd /d <目录> && <命令>"
set cd_cmd "cd /d [file nativename $work_dir] &&"
exec cmd /c [concat $cd_cmd xvlog --incr --relax -sv -work xil_defaultlib -log xvlog.log {*}$files]
```

> 注意：命令字符串必须用 `[concat ...]` 构建——**`{*}` 展开在双引号字符串内不生效**（会把 `{*}D:/...` 当字面量传给工具）。

### 4.5 set_property 的对象必须是对象

Vivado 的 `set_property` 不能传裸路径字符串，必须传 `get_files` 返回的对象：

```tcl
# 错误: 传路径字符串列表
set_property file_type SystemVerilog $path_list
# ERROR: [Common 17-161] Invalid option value '...' specified for 'objects'

# 正确: 先 get_files 取对象
set fobj [get_files -quiet [file normalize $path]]
if {[llength $fobj] > 0} { set_property file_type SystemVerilog $fobj }
```

### 4.6 .v 文件的 SV 语法识别

`.v` 后缀文件在 Vivado 里默认按 **Verilog-2001** 解析——用了 `parameter string/int` 等 SV 语法会报 `unknown type`。需显式设文件类型：

```tcl
set_property file_type SystemVerilog [get_files ...]
```

（iverilog/xsim 无此问题，因为编译时用 `-g2012`/`-sv` 显式指定。）

---

## 5. 各流程工作原理

### 5.1 仿真流程（sim.tcl）

```
xvlog -sv       编译 RTL + TB → xil_defaultlib 库
xelab -s tb_sim 链接顶层 tb_axi_master_simple → tb_sim.xsim 快照
xsim tb_sim -R  运行仿真 (TB 内 $finish 自动结束) → xsim.log + VCD
  ↓
提取 xsim.log 中 PASS/FAIL/ERROR 行 → 结果摘要
  ↓
check_vcd.py 解析 VCD → 4 项检查 (TB判定/写次数/读次数/数据抽查)
  输出重定向 → sim/check_vcd.log (Tcl exec 的 >& 重定向, py 脚本无改动)
```

为什么不用 `launch_simulation`：2019.2 在部分 Windows 环境 spawn 子进程报
`Spawn failed: Broken pipe`（Tcl exec 正常但 launch_simulation 内部 spawn 失败，
诊断为已知问题）。手动流程等价且可控。

### 5.2 综合流程（synth.tcl）

```
ensure_project + add_design_sources   (综合不需要 TB)
  ↓
synth_design -top AXI_FULL_Master_With_USER_Port -part xc7z020clg400-2
  ↓
report_utilization   → synth_run/utilization.rpt     (LUT/FF/DSP/BRAM)
report_timing        → synth_run/timing.rpt          (时序路径)
report_timing_summary → synth_run/timing_summary.rpt
write_checkpoint     → synth_run/post_synth.dcp      (综合后网表)
```

### 5.3 波形检查流程（check_vcd.py）

纯标准库解析 VCD 文本：
1. **TB 判定**：`test_done` 是否置位、`test_pass` 是否为 1
2. **写事务次数**：`m_axi_bvalid` 上升沿数 == 4
3. **读事务次数**：`m_axi_rlast` 上升沿数 == 4
4. **数据抽查**：4 次读事务首拍数据 == 0x10/0xA5/0x20/0x30（与 TB 种子一致）

退出码 0 = 通过 → 在 sim.tcl 里 exec 失败（非 0）会抛 Tcl 错误 → make 失败，
**检查不通过会阻断流程**，不会"看着 PASS 实际失败"。

---

## 6. 扩展与迁移指南

### 6.1 加一个测试平台

1. `add_sources.tcl`：`add_testbench_sources` 里换 TB 文件路径
2. `sim.tcl`：`xelab`/`xsim` 的顶层名改为新 TB
3. 跑 `make sim`

### 6.2 换器件/工程名

只改 `scripts/project.tcl` 顶部配置（`prj_part` / `prj_name` / `prj_dir`），所有脚本自动生效。

### 6.3 迁移到新工程

拷贝 `scripts/` + `Makefile`，修改：
1. `add_sources.tcl` 的 RTL 文件列表
2. `project.tcl` 的工程配置
3. 各主脚本里的顶层名/文件路径

### 6.4 加新步骤（如实现 Implementation）

```tcl
# scripts/impl.tcl — 新步骤
source scripts/project.tcl
source scripts/add_sources.tcl
ensure_project
add_design_sources
# ... place_design / route_design / report_timing_summary ...
close_project
exit
```

```makefile
# Makefile 加一行目标
impl:
	$(VIVADO) -mode batch -notrace -log $(LOG_DIR)/vivado_impl.log -journal $(LOG_DIR)/vivado_impl.jou -source scripts/impl.tcl
```

---

## 7. 常见问题与踩坑记录

| 问题 | 原因 | 解决 |
|------|------|------|
| `Spawn failed: Broken pipe` | launch_simulation 在 Win 环境已知 bug | 手动 xvlog/xelab/xsim |
| `string/int is an unknown type` | .v 文件按 Verilog-2001 解析 | `set_property file_type SystemVerilog` |
| `string type not supported` | **2019.2 综合不支持 string 参数**（仿真支持） | 参数改 integer |
| `concurrent assignment to a non-net` | reg 被 assign 驱动（遗留声明） | 删 reg 声明 |
| `multi-driven net ... GND preserved` | 同信号跨 always 多驱动 | 复位合并到同一 always |
| `set_property ... Invalid option value` | 对象必须来自 get_files | 先 get_files 取对象 |
| exec 产物散落项目根 | Tcl cd 对 exec 无效 | cmd /c "cd /d && ..." |
| `{*}D:/...` 字面量传给工具 | {*} 在字符串内不展开 | 用 `[concat ...]` 构建 |
| python 无输出退出码 49 | Microsoft Store 占位符 | 装真 Python（embeddable） |
| 日志/backup 文件散落 | Vivado 默认写 cwd | `-log`/`-journal` 指到 log/ |
| 偶发 `couldn't read retarget_vhdl.tcl` | 杀软瞬断文件锁 | 重跑即可 |
| python 输出文件中文乱码 | Windows 上 python 按系统 locale(GBK) 写重定向文件 | tcl exec 捕获 → `fconfigure -encoding utf-8` 转码写文件 |
| `PYTHONIOENCODING` 环境变量不生效 | **embeddable python 隔离模式**：`python312._pth` 存在时忽略所有 PYTHON* 环境变量 | 不用环境变量：`python -X utf8` 命令行开关 / exec 捕获转码 |
| `make check` 不改 check_vcd.tcl 也能乱码 | make check 直接跑 python + tee，不经过 Vivado/tcl | 补 `-X utf8` 开关即可 |
| Vivado 输出 INFO 中文乱码 | Vivado 按 ANSI(GBK) 读 tcl 源码，中文一进来就乱 | **暂方案**：所有打印改英文（ASCII 零编码问题）；中文支持记录在案，待解决 |
| 终端显示乱码 | UTF-8 终端渲染 GBK 字节 | 让输出统一 UTF-8（-X utf8 / tcl 转码）|

### ⚠️ 未决问题：tcl 脚本中文打印乱码（已记录，待以后解决）

**现象**：tcl 脚本里 puts 中文（无论 UTF-8 源码还是 `\uXXXX` 转义），输出到日志/终端均乱码。

**排查结论**（2026-08-12，全部实测验证）：

| 尝试 | 结果 |
|------|------|
| `source -encoding utf-8` 读子脚本 | ❌ Vivado 的 source 忽略该参数（proc 内字符串仍按 GBK 处理）|
| `fconfigure stdout -encoding utf-8` | ❌ 对 `\uXXXX` 解析的 Unicode 无效（输出仍按 GBK 编码）；对真中文是"GBK 错读往返"巧合 |
| UTF-8 BOM 文件头 | ❌ Vivado 不识别 BOM，BOM 字节被当命令前缀，第一行直接报错 |
| 主脚本真中文（UTF-8 源码） | ❌ 源码被按 GBK 错读，多字节字符边界错位，部分字节被替换为 `?`（内容损坏）|
| 主脚本 `\uXXXX` 转义 | ⚠️ 内容正确但输出 GBK 编码（配合 iconv 管道可转 UTF-8，但源码不可读）|

**根因**：Vivado 2019.2 的 Tcl 8.5 在 Windows 上按系统 ANSI 代码页（GBK）读取 .tcl 源码，
且 puts 对 Unicode 字符串按系统编码输出，脚本侧无法强制 UTF-8。

**当前方案**：所有 tcl 打印统一英文（ASCII 在任何编码下正确，日志全为 UTF-8/ASCII）。
**遗留**：tcl 中文打印支持留待以后解决（如换 Vivado 新版本、或研究 Vivado Tcl 的
`encoding system` 设置对 stdout 的影响）。

---

*更新日期：2026-08-11 · 配套使用说明：[make_tcl自动化使用说明.md](make_tcl自动化使用说明.md)*
