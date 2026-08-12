#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
check_vcd.py — 解析 VCD 波形文件, 判断 AXI_FULL_Master_With_USER_Port 简单仿真是否成功

用法:
    python check_vcd.py [波形文件] [--expect 0x10,0xA5,0x20,0x30]

检查项:
  1. TB 判定: 仿真是否正常结束 (test_done), 测试结果 (test_pass)
  2. 写事务次数: m_axi_bvalid 上升沿个数 == 15
     (TC1/3/4/5 各 1 + TC6 3 + TC8 2 + TC9 4 + TC10 2)
  3. 读事务次数: m_axi_rlast 上升沿个数 == 20
     (TC2/3/4/5 各 1 + TC6 3 + TC7 3 + TC8 4 + TC9 4 + TC10 2)
  4. 数据抽查: 前 4 个读事务首拍数据 (user_rd_valid 上升沿时刻的 user_rd_data_out)
     应依次等于 0x10 / 0xA5 / 0x20 / 0x30 (TC1-5 回归, 事务间 valid 下降可识别首拍)
     注: TC6-10 为背靠背事务, user_rd_valid 跨事务可能保持 1 (无上升沿),
     首拍识别不可靠 — 这些事务的数据正确性由 TB 逐拍比对 (test_pass) 保证

说明:
  - 只使用 Python 标准库, 无需安装第三方包
  - 退出码: 0 = 全部通过, 1 = 存在失败或异常
  - 时间单位为 VCD 头部声明的时间刻度 (本工程为 ns)
"""

import argparse
import sys


# ---------------------------------------------------------------------------
# VCD 解析
# ---------------------------------------------------------------------------

def parse_vcd(path):
    """解析 VCD 文件。

    返回: (timescale, sigs, changes)
      timescale: 时间刻度字符串, 如 "1ns"
      sigs:      [(id, 名称), ...]  (列表, 允许重复 id — iverilog 会对数值相同的
                 信号复用同一 id, 如 m_axi_rlast 与从机内部 rlast 共用 id)
      changes:   {id: [(时刻, 值字符串), ...]}  按时间升序
    """
    timescale = "1ns"
    sigs = []
    changes = {}
    cur_time = 0

    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            if line.startswith("$timescale"):
                parts = line.split()
                if len(parts) >= 2:
                    timescale = parts[1]
            elif line.startswith("$var"):
                # 格式: $var wire 1 ! clk $end  或  $var reg 8 " name [7:0] $end
                parts = line.split()
                if len(parts) >= 5:
                    vid = parts[3]
                    name = " ".join(parts[4:-1]).split("[")[0].strip()   # 去掉位宽后缀
                    sigs.append((vid, name))
                    changes[vid] = []
            elif line.startswith("$"):
                # $dumpvars / $end / $enddefinitions 等节标记, 跳过
                continue
            elif line.startswith("#"):
                cur_time = int(line[1:])
            elif line.startswith("b"):
                # 总线值: b00010000 !
                parts = line.split()
                if len(parts) == 2:
                    changes.setdefault(parts[1], []).append((cur_time, parts[0][1:]))
            elif len(line) >= 2 and line[0] in "01xXzZ":
                # 标量值: 0!  1"  x#  (id 可能多字符, 取到行尾)
                changes.setdefault(line[1:], []).append((cur_time, line[0]))
            # 其他行 (注释等) 忽略

    return timescale, sigs, changes


# ---------------------------------------------------------------------------
# 查询工具
# ---------------------------------------------------------------------------

def find_id(sigs, name):
    """按信号名查找 id (名称已去除位宽后缀)。未找到返回 None。"""
    for vid, n in sigs:
        if n == name:
            return vid
    return None


def value_at(changes, vid, t):
    """时刻 t 的信号值 (取不晚于 t 的最近一次变化)。从未变化返回 None。"""
    lst = changes.get(vid, [])
    if not lst:
        return None
    lo, hi = 0, len(lst) - 1
    best = None
    while lo <= hi:
        mid = (lo + hi) // 2
        if lst[mid][0] <= t:
            best = mid
            lo = mid + 1
        else:
            hi = mid - 1
    return lst[best][1] if best is not None else None


def find_rises(changes, vids):
    """统计信号组合 (vids) 的上升沿: '全部为 1' 且 '上一时刻不全部为 1' 的时刻列表。

    用于握手/事务计数, 不受信号同时变化的时间戳歧义影响。
    """
    times = set()
    for v in vids:
        for (t, _val) in changes.get(v, []):
            times.add(t)
    times = sorted(times)

    cur = {v: None for v in vids}
    prev_all_one = False
    rises = []
    for t in times:
        for v in vids:
            cur[v] = value_at(changes, v, t)
        all_one = all(c == "1" for c in cur.values())
        if all_one and not prev_all_one:
            rises.append(t)
        prev_all_one = all_one
    return rises


# ---------------------------------------------------------------------------
# 主检查流程
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(
        description="解析 VCD 波形, 检查 AXI_FULL_Master 简单仿真结果")
    ap.add_argument("vcd", nargs="?", default="tb_axi_master_simple.vcd",
                    help="VCD 波形文件 (默认: tb_axi_master_simple.vcd)")
    ap.add_argument("--expect", default="0x10,0xA5,0x20,0x30",
                    help="TC1-5 回归: 每次读事务首拍期望数据, 逗号分隔 (默认: 0x10,0xA5,0x20,0x30)")
    args = ap.parse_args()

    try:
        timescale, sigs, changes = parse_vcd(args.vcd)
    except FileNotFoundError:
        print(f"[错误] 找不到波形文件: {args.vcd}")
        print("       请先运行仿真: iverilog ... && vvp tb_axi_master_simple.out")
        sys.exit(1)

    expect = [int(x.strip(), 16) for x in args.expect.split(",")]

    print("=" * 62)
    print(" VCD 检查报告:", args.vcd)
    print("=" * 62)
    print(f"  时间刻度: {timescale}    信号总数: {len(sigs)}")

    # 检查关键信号是否存在 (便于定位波形不完整的问题)
    missing = [n for n in
               ("test_done", "test_pass", "m_axi_bvalid", "m_axi_rlast",
                "user_rd_valid", "user_rd_data_out")
               if find_id(sigs, n) is None]
    if missing:
        print(f"  [警告] VCD 中未找到信号: {', '.join(missing)}")

    failed = 0

    # ------------------------------------------------------------------
    # 1. TB 判定: test_done / test_pass
    # ------------------------------------------------------------------
    print("-" * 62)
    print(" [1] TB 判定 (test_done / test_pass)")
    done_id = find_id(sigs, "test_done")
    pass_id = find_id(sigs, "test_pass")
    if done_id is None or pass_id is None:
        print("      [FAIL] 波形缺少 test_done/test_pass 信号, 无法判定")
        failed += 1
    else:
        done_rises = find_rises(changes, [done_id])
        if not done_rises:
            print("      [FAIL] test_done 从未置 1 -> 仿真未正常结束 (超时/中断)")
            failed += 1
        else:
            t_done = done_rises[-1]
            print(f"      test_done 置位时刻: {t_done} {timescale}")
            pv = value_at(changes, pass_id, t_done)
            if pv == "1":
                print("      test_pass = 1 -> [PASS] TB 判定: 数据比对全部通过")
            else:
                print(f"      test_pass = {pv} -> [FAIL] TB 判定: 存在数据错误")
                failed += 1

    # ------------------------------------------------------------------
    # 2. 写事务次数: bvalid 上升沿 (每个写事务一次)
    #    期望 15: TC1/3/4/5(4) + TC6(3) + TC8(2) + TC9(4) + TC10(2)
    # ------------------------------------------------------------------
    print("-" * 62)
    print(" [2] 写事务次数 (m_axi_bvalid 上升沿, 期望 15)")
    bv_id = find_id(sigs, "m_axi_bvalid")
    if bv_id is None:
        print("      [FAIL] 缺少 m_axi_bvalid 信号")
        failed += 1
    else:
        n_wr = len(find_rises(changes, [bv_id]))
        if n_wr == 15:
            print(f"      bvalid 上升沿 = {n_wr} -> [PASS]")
        else:
            print(f"      bvalid 上升沿 = {n_wr} -> [FAIL] (期望 15)")
            failed += 1

    # ------------------------------------------------------------------
    # 3. 读事务次数: rlast 上升沿 (每个读事务一次)
    #    期望 20: TC2/3/4/5(4) + TC6校验(3) + TC7(3) + TC8(4) + TC9(4) + TC10(2)
    # ------------------------------------------------------------------
    print("-" * 62)
    print(" [3] 读事务次数 (m_axi_rlast 上升沿, 期望 20)")
    rl_id = find_id(sigs, "m_axi_rlast")
    if rl_id is None:
        print("      [FAIL] 缺少 m_axi_rlast 信号")
        failed += 1
    else:
        n_rd = len(find_rises(changes, [rl_id]))
        if n_rd == 20:
            print(f"      rlast 上升沿 = {n_rd} -> [PASS]")
        else:
            print(f"      rlast 上升沿 = {n_rd} -> [FAIL] (期望 20)")
            failed += 1

    # ------------------------------------------------------------------
    # 4. 数据抽查: 每次读事务首拍数据
    # ------------------------------------------------------------------
    print("-" * 62)
    print(f" [4] 读事务首拍数据抽查 (期望: {', '.join('0x%02X' % e for e in expect)})")
    rv_id = find_id(sigs, "user_rd_valid")
    rd_id = find_id(sigs, "user_rd_data_out")
    if rv_id is None or rd_id is None:
        print("      [FAIL] 缺少 user_rd_valid / user_rd_data_out 信号")
        failed += 1
    else:
        rises = find_rises(changes, [rv_id])
        print(f"      user_rd_valid 上升沿 = {len(rises)} (前 {len(expect)} 个为 TC1-5 回归)")
        if len(rises) < len(expect):
            print("      [FAIL] 读事务首拍次数不足 (TC1-5 回归未完整)")
            failed += 1
        for i, t in enumerate(rises):
            if i >= len(expect):
                # 超出 TC1-5 的读 (TC6-10 背靠背, valid 连续无法识别首拍):
                # 数据正确性由 TB 逐拍比对保证, 仅报告
                print(f"      第 {i+1} 次读: 时刻 {t} {timescale} -> [TC6-10 事务, 仅报告]")
                continue
            v = value_at(changes, rd_id, t)
            if v is None or v.lower() in ("x", "z") or not v:
                print(f"      第 {i+1} 次读: 时刻 {t} {timescale} 数据={v} -> [FAIL] (未知值)")
                failed += 1
                continue
            try:
                got = int(v, 2)
            except ValueError:
                print(f"      第 {i+1} 次读: 时刻 {t} {timescale} 数据={v} -> [FAIL] (非二进制值)")
                failed += 1
                continue
            if got == expect[i]:
                print(f"      第 {i+1} 次读: 时刻 {t} {timescale} 数据=0x{got:02X} -> [PASS]")
            else:
                print(f"      第 {i+1} 次读: 时刻 {t} {timescale} 数据=0x{got:02X} "
                      f"-> [FAIL] (期望 0x{expect[i]:02X})")
                failed += 1

    # ------------------------------------------------------------------
    # 汇总
    # ------------------------------------------------------------------
    print("=" * 62)
    if failed == 0:
        print(" 结论: 仿真成功 (ALL PASS)")
        print(" 可用 gtkwave 打开波形: gtkwave %s" % args.vcd)
        print("=" * 62)
        sys.exit(0)
    else:
        print(f" 结论: 仿真失败或存在异常 ({failed} 项未通过)")
        print("=" * 62)
        sys.exit(1)


if __name__ == "__main__":
    main()
