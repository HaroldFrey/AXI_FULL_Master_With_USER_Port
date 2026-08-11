#===============================================================================
# sim.tcl — Vivado 自动化仿真脚本 (batch 模式)
#
# 用法 (由 Makefile 调用): make sim
# 流程: 打开/创建工程 → 加源文件 → xvlog/xelab/xsim 编译仿真 → 结果摘要
# 复用: scripts/project.tcl (建工程) + scripts/add_sources.tcl (加文件)
#
# 说明: 仿真不走 launch_simulation (该命令在部分 Windows 环境
#       存在 "Spawn failed: Broken pipe" 已知问题), 改为在 Tcl 里
#       手动按非工程流程调用 xvlog → xelab → xsim (全部绝对路径)
#===============================================================================

# 复用子脚本 (用 info script 定位, 与调用目录无关)
set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir project.tcl]
source [file join $script_dir add_sources.tcl]
source [file join $script_dir check_vcd.tcl]

#------------------------------------------------------------------------------
# 1) 工程准备 (幂等: 已存在则复用, 不重建)
#------------------------------------------------------------------------------
ensure_project
add_all_sources

#------------------------------------------------------------------------------
# 2) 手动编译仿真 (xvlog → xelab → xsim, 绝对路径, 绕开 launch_simulation)
#------------------------------------------------------------------------------
set work_dir [file normalize ./sim_run]
if {[file exists $work_dir]} { file delete -force $work_dir }
file mkdir $work_dir

set rtl_files [list \
    [file normalize ./rtl/FIFO/fifo_async.v] \
    [file normalize ./rtl/AXI_FULL_Master_With_USER_Port/axi_wr_master.v] \
    [file normalize ./rtl/AXI_FULL_Master_With_USER_Port/axi_rd_master.v] \
    [file normalize ./rtl/AXI_FULL_Master_With_USER_Port/Data_RX.v] \
    [file normalize ./rtl/AXI_FULL_Master_With_USER_Port/Data_TX.v] \
    [file normalize ./rtl/AXI_FULL_Master_With_USER_Port/AXI_FULL_Master_With_USER_Port.v] \
]
set tb_files [list [file normalize ./sim/tb_axi_master_simple.sv]]
set lib "xil_defaultlib"

# 说明: Tcl 的 cd 对 exec 子进程不生效 (Vivado Windows 环境),
#       用 cmd /c "cd /d <工作目录> && ..." 把 xvlog/xelab/xsim
#       的工作目录切到 sim_run/, 避免中间文件散落项目根
#       注意: 命令字符串用 concat 构建 ({}* 展开在字符串内不生效)
set cd_cmd "cd /d [file nativename $work_dir] &&"

puts "INFO: xvlog 编译 (RTL + TB)"
exec cmd /c [concat $cd_cmd xvlog --incr --relax -sv -work $lib -log xvlog.log \
    {*}$rtl_files {*}$tb_files]

puts "INFO: xelab 链接顶层 tb_axi_master_simple"
exec cmd /c [concat $cd_cmd xelab --incr --relax -debug typical -s tb_sim -log xelab.log \
    $lib.tb_axi_master_simple]

puts "INFO: xsim 运行仿真 (TB 内 \$finish 自动结束)"
exec cmd /c [concat $cd_cmd xsim tb_sim -R -log xsim.log]

#------------------------------------------------------------------------------
# 3) 收尾: 打印结果摘要 + 保存波形
#------------------------------------------------------------------------------
puts "============ 仿真结果摘要 ============"
set log_fp [open [file join $work_dir xsim.log] r]
while {[gets $log_fp line] >= 0} {
    if {[regexp -nocase {PASS|FAIL|ERROR|finish} $line]} { puts "  $line" }
}
close $log_fp
puts "====================================="

set vcd [file join $work_dir tb_axi_master_simple.vcd]
if {[file exists $vcd]} {
    puts "INFO: 波形已保存 -> $vcd"
} else {
    puts "WARNING: 未找到 VCD 波形文件 (TB 内 \$dumpfile 未生效?)"
}

#------------------------------------------------------------------------------
# 4) VCD 波形检查 (独立子脚本 check_vcd.tcl)
#------------------------------------------------------------------------------
puts "INFO: 开始 VCD 波形检查"
run_vcd_check

close_project
exit
