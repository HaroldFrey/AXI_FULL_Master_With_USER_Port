#===============================================================================
# Makefile — Vivado 自动化仿真入口 (make + tcl)
#
# 用法 (在项目根目录执行):
#   make sim      # 自动创建 Vivado 工程 + xsim 仿真 (一步完成)
#   make clean    # 删除日志目录与所有输出产物 (工程/仿真/波形)
#
# 前提:
#   - make 可用 (免安装版: D:\App_install_Lcoation\make\bin\make.exe)
#   - Vivado 2019.2 (D:\App_install_Lcoation\Vivado201902)
#
# 流程: make -> vivado.bat -mode batch -> scripts/sim.tcl
#       (tcl 内: 建工程 -> 加源文件 -> xvlog/xelab/xsim 编译仿真)
# 日志: 统一输出到 log/ 目录 (vivado.log / vivado.jou)
#===============================================================================

VIVADO := D:/App_install_Lcoation/Vivado201902/Vivado/2019.2/bin/vivado.bat
LOG_DIR := log

.PHONY: sim clean

sim:
	mkdir -p $(LOG_DIR)
	$(VIVADO) -mode batch -notrace \
		-log $(LOG_DIR)/vivado.log -journal $(LOG_DIR)/vivado.jou \
		-source scripts/sim.tcl

clean:
	rm -rf $(LOG_DIR) vivado_prj sim_run xsim.dir .Xil \
		vivado.log vivado.jou vivado_*.backup.jou vivado_*.backup.log \
		webtalk* xsim.jou xsim_*.backup.jou xelab.jou xvlog.jou \
		*.xsim *.wdb *.pb *.vcd tb_sim
