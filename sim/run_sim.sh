#!/usr/bin/env bash
#===============================================================================
# run_sim.sh — 一键: 编译 → 仿真 → 波形检查 → 打开波形 (gtkwave)
#
# 用法:
#   ./run_sim.sh            # 默认: 编译 + 仿真 + check_vcd.py + 打开 gtkwave
#   ./run_sim.sh --no-check # 跳过 check_vcd.py 波形检查
#   ./run_sim.sh --no-gui   # 不自动打开 gtkwave
#   ./run_sim.sh -h         # 帮助
#
# 前提: 已安装 iverilog / vvp / python / gtkwave, 且在本脚本所在目录 (sim/) 执行
#===============================================================================

set -euo pipefail

# 切换到脚本所在目录 (sim/), 保证相对路径正确
cd "$(dirname "$0")"

DO_CHECK=1
DO_GUI=1

for arg in "$@"; do
    case "$arg" in
        --no-check) DO_CHECK=0 ;;
        --no-gui)   DO_GUI=0 ;;
        -h|--help)
            echo "用法: $0 [--no-check] [--no-gui]"
            echo "  默认: 编译 → 仿真 → 波形检查(check_vcd.py) → 打开 gtkwave"
            echo "  --no-check: 跳过波形检查"
            echo "  --no-gui  : 不自动打开 gtkwave"
            exit 0
            ;;
        *) echo "[错误] 未知选项: $arg (用 -h 查看帮助)"; exit 1 ;;
    esac
done

# 工具检查
for tool in iverilog vvp; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[错误] 未找到 $tool, 请先安装 iverilog"
        exit 1
    fi
done

RTL="../rtl/AXI_FULL_Master_With_USER_Port"
OUT="tb_axi_master_simple.out"
VCD="tb_axi_master_simple.vcd"

echo "==================== 1/4 编译 (iverilog) ===================="
iverilog -g2012 -o "$OUT" -s tb_axi_master_simple \
    "$RTL/AXI_FULL_Master_With_USER_Port.v" \
    "$RTL/axi_wr_master.v" \
    "$RTL/axi_rd_master.v" \
    "$RTL/Data_RX.v" \
    "$RTL/Data_TX.v" \
    ../rtl/FIFO/fifo_async.v \
    tb_axi_master_simple.sv
echo "[OK] 编译成功 -> $OUT"

echo "==================== 2/4 仿真 (vvp) ===================="
vvp "$OUT"
echo "[OK] 仿真结束, 波形 -> $VCD"

CHECK_OK="跳过"
if [ "$DO_CHECK" = 1 ]; then
    echo "==================== 3/4 波形检查 (check_vcd.py) ===================="
    if ! command -v python >/dev/null 2>&1; then
        echo "[警告] 未找到 python, 跳过波形检查"
        CHECK_OK="跳过(无python)"
    elif python check_vcd.py "$VCD"; then
        CHECK_OK="通过"
    else
        CHECK_OK="失败"
    fi
fi

if [ "$DO_GUI" = 1 ]; then
    echo "==================== 4/4 打开波形 (gtkwave) ===================="
    if command -v gtkwave >/dev/null 2>&1; then
        (gtkwave "$VCD" &)   # 后台打开, 不阻塞脚本
        echo "[OK] gtkwave 已打开: $VCD"
    else
        echo "[警告] 未找到 gtkwave, 请手动打开: gtkwave $VCD"
    fi
fi

echo ""
echo "==================== 完成 ===================="
echo "  仿真结果: 见上方 vvp 输出 (ALL PASS = 通过)"
echo "  波形检查: $CHECK_OK"
echo "  波形文件: $VCD"
