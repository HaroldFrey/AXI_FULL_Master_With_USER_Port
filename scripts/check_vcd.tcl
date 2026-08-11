#===============================================================================
# check_vcd.tcl — 仿真波形检查 (独立子脚本, 幂等)
#
# 用途: 被 sim.tcl source, 仿真完成后调用 run_vcd_check 检查 VCD 波形
# 独立用法 (make check): 直接调 python 检查已有 VCD, 见 Makefile
#
# 原理: 调用 sim/check_vcd.py 解析 VCD, 验证:
#   1. TB 判定 (test_done / test_pass)
#   2. 写事务次数 == 4
#   3. 读事务次数 == 4
#   4. 读数据抽查 (0x10 / 0xA5 / 0x20 / 0x30)
# 退出码: 0 = 通过, 非 0 = 失败 (使 make sim 报错, 阻断流程)
#===============================================================================

#------------------------------------------------------------------------------
# run_vcd_check — 运行 VCD 波形检查
#   检查日志: 重定向到 sim/check_vcd.log (不改 py 脚本, 用 tcl 重定向实现)
#   返回: 0 = 全部通过; 抛错 = 失败 (VCD 缺失 / 检查不通过)
#------------------------------------------------------------------------------
proc run_vcd_check {} {
    set vcd [file normalize ./sim_run/tb_axi_master_simple.vcd]
    if {![file exists $vcd]} {
        error "VCD 波形不存在: $vcd (请先执行 make sim)"
    }
    set log_file [file normalize ./sim/check_vcd.log]
    puts "INFO: 运行 check_vcd.py 检查波形 (日志 -> sim/check_vcd.log)"
    # >& 把 python 的 stdout+stderr 全部重定向到日志文件
    exec [file normalize $::python_exe] [file normalize ./sim/check_vcd.py] $vcd \
        >& [file nativename $log_file]
    # 回显日志到控制台 (保持 make 输出可见)
    set fp [open $log_file r]
    puts [read $fp]
    close $fp
    puts "INFO: VCD 检查通过 (ALL PASS)"
    return 0
}
