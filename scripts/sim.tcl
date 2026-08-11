#===============================================================================
# sim.tcl — Vivado 自动化仿真脚本 (batch 模式)
#
# 用法 (由 Makefile 调用):
#   vivado.bat -mode batch -notrace -source scripts/sim.tcl
#
# 功能: 创建工程 → 添加 RTL/TB → xvlog/xelab/xsim 编译仿真 → 退出
# 可重复执行: 每次运行先删除旧工程, 保证结果一致
# 运行目录: 项目根目录 (Makefile 里已保证)
#
# 说明: 仿真不走 launch_simulation (该命令在部分 Windows 环境
#       存在 "Spawn failed: Broken pipe" 已知问题), 改为在 Tcl 里
#       手动按非工程流程调用 xvlog → xelab → xsim (全部绝对路径)
#===============================================================================

set project_name "axi_full_master"
set project_dir  "./vivado_prj"
set part         "xc7z020clg400-2"
set top          "tb_axi_master_simple"
set work_dir     [file normalize ./sim_run]
set lib          "xil_defaultlib"

#-------------------------------------------------------------------------------
# 1) 清理旧工程与仿真产物 (保证可重复执行)
#-------------------------------------------------------------------------------
if {[file exists $project_dir]} { file delete -force $project_dir }
if {[file exists $work_dir]}     { file delete -force $work_dir }

#-------------------------------------------------------------------------------
# 2) 创建工程 + 添加源文件 (工程供 GUI 打开 / 后续综合使用)
#-------------------------------------------------------------------------------
puts "INFO: 创建工程 $project_name (part=$part)"
create_project $project_name $project_dir -part $part -force

puts "INFO: 添加 RTL 源文件"
add_files -norecurse [list \
    ./rtl/AXI_FULL_Master_With_USER_Port/AXI_FULL_Master_With_USER_Port.v \
    ./rtl/AXI_FULL_Master_With_USER_Port/axi_wr_master.v \
    ./rtl/AXI_FULL_Master_With_USER_Port/axi_rd_master.v \
    ./rtl/AXI_FULL_Master_With_USER_Port/Data_RX.v \
    ./rtl/AXI_FULL_Master_With_USER_Port/Data_TX.v \
    ./rtl/FIFO/fifo_async.v \
]

puts "INFO: 添加 testbench"
add_files -norecurse -fileset sim_1 ./sim/tb_axi_master_simple.sv

puts "INFO: 设置顶层 (sources_1=设计顶层, sim_1=testbench)"
set_property top AXI_FULL_Master_With_USER_Port [get_filesets sources_1]
set_property top $top [get_filesets sim_1]
update_compile_order -fileset sources_1

#-------------------------------------------------------------------------------
# 3) 手动编译仿真 (xvlog → xelab → xsim, 绝对路径, 绕开 launch_simulation)
#-------------------------------------------------------------------------------
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

puts "INFO: xvlog 编译 (RTL + TB)"
exec xvlog --incr --relax -sv -work $lib \
    -log [file join $work_dir xvlog.log] {*}$rtl_files {*}$tb_files

puts "INFO: xelab 链接顶层 $top"
exec xelab --incr --relax -debug typical -s tb_sim \
    -log [file join $work_dir xelab.log] $lib.$top

puts "INFO: xsim 运行仿真 (TB 内 \$finish 自动结束)"
exec xsim tb_sim -R -log [file join $work_dir xsim.log]

# 打印仿真结果摘要 (从 xsim.log 提取 PASS/FAIL/ERROR 行)
puts "============ 仿真结果摘要 ============"
set log_fp [open [file join $work_dir xsim.log] r]
while {[gets $log_fp line] >= 0} {
    if {[regexp -nocase {PASS|FAIL|ERROR|finish} $line]} { puts "  $line" }
}
close $log_fp
puts "====================================="

#-------------------------------------------------------------------------------
# 4) 收尾: 波形与结果
#-------------------------------------------------------------------------------
set vcd [file join $work_dir tb_axi_master_simple.vcd]
if {[file exists [file normalize ./tb_axi_master_simple.vcd]]} {
    file copy -force [file normalize ./tb_axi_master_simple.vcd] $vcd
    puts "INFO: 波形已保存 -> $vcd"
} else {
    puts "WARNING: 未找到 VCD 波形文件 (TB 内 \$dumpfile 未生效?)"
}

puts "INFO: 仿真完成, 结果见上方 xsim 输出 (PASS/FAIL)"
close_project
exit
