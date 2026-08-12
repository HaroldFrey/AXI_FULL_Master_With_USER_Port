# 语法解析 — Outstanding 功能（RTL 阶段）

## 总体

| 文件 | 行数 | 说明 |
|------|------|------|
| rtl/.../axi_wr_master.v | ~340 | 写通道控制器（Outstanding 改造） |
| rtl/.../axi_rd_master.v | ~330 | 读通道控制器（Outstanding 改造） |
| rtl/.../AXI_FULL_Master_With_USER_Port.v | ~290 | 顶层（参数 + ready_start 端口） |

## 模块调用图

```
AXI_FULL_Master_With_USER_Port（改动）
├── axi_wr_master（重写：槽位表 + 调度器）
├── axi_rd_master（重写：槽位表 + 调度器）
├── Data_RX / Data_TX / fifo_async（不动）
```

## 各模块关键语法（仅复杂/易错部分）

### 1. 槽位表寄存器阵列

```systemverilog
reg [1:0] slot_state [0:SLOT_NUM-1];       // unpacked 数组
reg [C_M_AXI_ADDR_WIDTH-1:0] slot_addr  [0:SLOT_NUM-1];
```

- 数组元素在 always @(posedge) 内用 for 循环逐槽更新（iverilog 支持）
- 数组**变量索引**（`slot_len[w_target]`）可综合 ✓
- `localparam SLOT_ID_W = (SLOT_NUM > 1) ? $clog2(SLOT_NUM) : 1;`——**SLOT_NUM=1 时 $clog2(1)=0 会产生 [-1:0] 位宽**，需取 max(1, clog2(N))

### 2. 轮询扫描（组合循环，回绕）

```systemverilog
always_comb begin
    aw_target = next_aw_slot;
    aw_found  = 1'b0;
    for (i = 0; i < SLOT_NUM; i = i + 1) begin
        if (aw_found == 1'b0) begin
            if (slot_state[(next_aw_slot + i) % SLOT_NUM] == S_AW_PEND) begin
                aw_target = (next_aw_slot + i) % SLOT_NUM;
                aw_found  = 1'b1;
            end
        end
    end
end
```

- `% SLOT_NUM` 对参数取模：SLOT_NUM 为常数 → 综合为回绕比较，可综合
- 循环变量 i 为模块级 integer——iverilog 中 always 块**串行执行**（非抢占），每个 for 都先初始化 i，多进程共享无竞态
- 找到即停（aw_found 短路），天然保序无饥饿

### 3. AW 数据锁存（VALID 期间数据稳定）

```systemverilog
end else if (aw_valid == 1'b0 && aw_found) begin
    aw_valid     <= 1'b1;
    aw_addr_reg  <= slot_addr[aw_target];
    aw_len_reg   <= slot_len[aw_target] - 1;   // AXI ALEN = 长度-1
    aw_id_reg    <= aw_target;                 // AWID = 槽号
end
```

- 扫描结果 aw_target 是组合（可能随槽位状态变化）→ **拉高拍锁存**，保证 AXI VALID 期间地址/ID/长度稳定
- 槽位状态转移用锁存的 `aw_id_reg == i` 判定（而非组合 aw_target），避免握手拍扫描结果漂移

### 4. AWID 位宽适配与防护

```systemverilog
initial if (C_M_AXI_ID_WIDTH < SLOT_ID_W)
    $error("axi_wr_master: C_M_AXI_ID_WIDTH(%0d) < 槽号位宽(%0d), ...", ...);
assign M_AXI_AWID = {{(C_M_AXI_ID_WIDTH - SLOT_ID_W){1'b0}}, aw_id_reg};
```

- 顶层 `C_M_AXI_ID_WIDTH` 默认值自动适配槽位数：`(MAX_OUTSTANDING_WR>1)?$clog2(MAX_OUTSTANDING_WR):1`（参数顺序：MAX 参数声明在前）
- 用户显式传不足位宽时 $error 编译报错（BID 无法区分槽位）
- ⚠️ 负重复拼接（`{(-1){...}}`）是 iverilog 编译错误——参数顺序不当会触发

### 5. W 串行调度组合

```systemverilog
assign w_valid      = w_found && (wr_fifo_empty == 1'b0) && (wr_cnt != slot_len[w_target]);
assign M_AXI_WLAST  = w_valid && (wr_cnt == slot_len[w_target] - 1);
```

- wr_cnt 从 0 计数到 len-1：WVALID 条件 `wr_cnt != len`（未发满）、WLAST 条件 `wr_cnt == len-1`
- len=1 单拍：wr_cnt=0 → WVALID=1 且 WLAST=1 ✓
- WLAST 握手后 wr_cnt 清零、next_w_slot 前进

### 6. B/R 通道

- `b_ready = 任一槽 B_WAIT`（组合归约）；BID 直接索引槽位（乱序兼容）
- 读通道 `M_AXI_ARID = '0`（同 ID 保序方案）；R 保序用 next_r_slot 轮询匹配
- RREADY = r_found && !rd_fifo_full（Data_TX 满反压）

## FSM 分析

| 状态机 | 状态 | 编码 | 复位值 | 说明 |
|--------|------|------|--------|------|
| 写槽位 ×N | FREE/AW_PEND/W_DATA/B_WAIT | 2'b00~11 | FREE | 每槽独立，集中调度 |
| 读槽位 ×N | FREE/AR_PEND/R_ACTIVE | 2'b00~10 | FREE | 每槽独立，集中调度 |
| AW/AR 调度 | valid 保持 + 锁存 | — | 0 | 拉高→握手→拉低→下一槽 |

## 综合属性表

| 属性 | 位置 | 原因 |
|------|------|------|
| 无 | — | 纯同步逻辑；`%` 参数取模综合为回绕比较 |

## 更新记录

| 日期 | 内容 |
|------|------|
| 2026-08-12 | 初版：RTL 改造完成，iverilog 语法检查通过 |
