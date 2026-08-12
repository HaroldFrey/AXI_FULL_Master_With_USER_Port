//===========================================================================
// axi_rd_master.v  —  AXI4-Full 读通道控制器 (Outstanding 版)
//===========================================================================
// 功能: 独立管理 AXI 读事务 (AR + R 通道), 支持多个在途事务
//   - 槽位表 (MAX_OUTSTANDING_RD 个), 每槽跟踪一个事务
//   - 槽位状态机: FREE → AR_PEND → R_ACTIVE → FREE
//   - AR 按 start 顺序流水线发出 (轮询指针)
//   - 同 ARID=0 保序方案: 从机对同 ID 必须按 AR 顺序返回 R 数据,
//     Master 按 next_r 轮询匹配槽位, R 数据直接透传用户 (无乱序逻辑)
//   - rd_ready_start: 有空闲槽位时拉高
// 设计: doc/outstanding_设计方案.md
//===========================================================================

`timescale 1ns / 1ns

module axi_rd_master #(
    parameter       C_M_TARGET_SLAVE_BASE_ADDR      =   32'h00000000    ,// 目标从机基地址
    parameter       C_M_AXI_ID_WIDTH                =   1               ,// ID 信号位宽
    parameter       C_M_AXI_ADDR_WIDTH              =   32              ,// 地址位宽
    parameter       C_M_AXI_DATA_WIDTH              =   8               ,// 数据位宽
    parameter       C_M_AXI_RD_LEN_WIDTH            =   8               ,// 读突发长度位宽
    parameter       C_M_AXI_ARUSER_WIDTH            =   0               ,// 读地址 USER 位宽
    parameter       C_M_AXI_RUSER_WIDTH             =   0               ,// 读数据 USER 位宽
    parameter       integer MAX_OUTSTANDING_RD      =   4                // 槽位数 (1~8)
)(
    // --------------------------Global Signals---------------------------//
    input   wire                                        M_AXI_ACLK      ,// AXI 时钟
    input   wire                                        M_AXI_ARESETN   ,// AXI 复位 (低有效)

    // --------------------------USER PORTS (读侧)-----------------------//
    input   wire                                        rd_start        ,// 读操作开始 (单周期脉冲)
    input   wire    [1 : 0]                             rd_burst_type   ,// 突发类型: 00=FIXED 01=INCR 10=WRAP
    input   wire    [C_M_AXI_ADDR_WIDTH-1 : 0]          rd_addr_in      ,// 突发读地址
    input   wire    [C_M_AXI_RD_LEN_WIDTH-1 : 0]        rd_len_in       ,// 突发读长度 (1~256)
    input   wire                                        rd_fifo_full    ,// 读 FIFO 满标志
    input   wire    [C_M_AXI_ARUSER_WIDTH-1 : 0]        user_aruser     ,// 读地址 USER 信号
    output  wire    [C_M_AXI_DATA_WIDTH-1 : 0]          data_out        ,// 输出读数据
    output  wire                                        data_out_vld    ,// 输出读数据有效
    output  reg                                         rd_error        ,// 读事务错误 (RRESP != OKAY)
    output  wire                                        rd_ready_start  ,// 有空闲槽位 (可接受新事务)

    // -------------------------AXI READ CHANNELS------------------------//
    // AR Channel
    output          [C_M_AXI_ID_WIDTH-1 : 0]            M_AXI_ARID      ,
    output  reg     [C_M_AXI_ADDR_WIDTH-1 : 0]          M_AXI_ARADDR    ,
    output          [7 : 0]                             M_AXI_ARLEN     ,
    output          [2 : 0]                             M_AXI_ARSIZE    ,
    output          [1 : 0]                             M_AXI_ARBURST   ,
    output                                              M_AXI_ARLOCK    ,
    output          [3 : 0]                             M_AXI_ARCACHE   ,
    output          [2 : 0]                             M_AXI_ARPROT    ,
    output          [3 : 0]                             M_AXI_ARQOS     ,
    output          [C_M_AXI_ARUSER_WIDTH-1 : 0]        M_AXI_ARUSER    ,
    output  reg                                         M_AXI_ARVALID   ,
    input                                               M_AXI_ARREADY   ,

    // R Channel
    input           [C_M_AXI_ID_WIDTH-1 : 0]            M_AXI_RID       ,
    input           [C_M_AXI_DATA_WIDTH-1 : 0]          M_AXI_RDATA     ,
    input           [1 : 0]                             M_AXI_RRESP     ,
    input                                               M_AXI_RLAST     ,
    input           [C_M_AXI_RUSER_WIDTH-1 : 0]         M_AXI_RUSER     ,
    input                                               M_AXI_RVALID    ,
    output  reg                                         M_AXI_RREADY
);

    //===================================================================
    // 参数与函数
    //===================================================================
    localparam          SIZE        = clogb2(C_M_AXI_DATA_WIDTH/8-1);
    localparam          SLOT_NUM    = MAX_OUTSTANDING_RD;     // 槽位数
    localparam          SLOT_ID_W   = (SLOT_NUM > 1) ? $clog2(SLOT_NUM) : 1; // 槽号位宽 (≥1)
    localparam          BYTES_PER_BEAT = C_M_AXI_DATA_WIDTH/8;

    function integer clogb2(input integer depth); begin
        if (depth == 0)
            clogb2 = 0;
        else if (depth != 0)
            for (clogb2 = 0; depth > 0; clogb2 = clogb2 + 1)
                depth = depth >> 1;
    end
    endfunction

    //===================================================================
    // 槽位状态编码
    //===================================================================
    localparam          S_FREE      = 2'b00;    // 空闲
    localparam          S_AR_PEND   = 2'b01;    // 待发 AR
    localparam          S_R_ACTIVE  = 2'b10;    // 等待 R 数据 (保序调度)

    //===================================================================
    // 槽位表 (寄存器阵列)
    //===================================================================
    reg [1:0]                       slot_state  [0:SLOT_NUM-1];
    reg [C_M_AXI_ADDR_WIDTH-1:0]    slot_addr   [0:SLOT_NUM-1];
    reg [C_M_AXI_RD_LEN_WIDTH-1:0]  slot_len    [0:SLOT_NUM-1];
    reg [1:0]                       slot_burst  [0:SLOT_NUM-1];

    // 调度指针 (轮询, 天然保持 start 顺序)
    reg [SLOT_ID_W-1:0]             alloc_ptr;      // 分配轮询指针
    reg [SLOT_ID_W-1:0]             next_ar_slot;   // AR 调度扫描起点
    reg [SLOT_ID_W-1:0]             next_r_slot;    // R 保序匹配扫描起点

    // AR 通道锁存寄存器
    reg                             ar_valid;
    reg [C_M_AXI_ADDR_WIDTH-1:0]    ar_addr_reg;
    reg [7:0]                       ar_len_reg;
    reg [SLOT_ID_W-1:0]             ar_id_reg;
    reg [1:0]                       ar_burst_reg;

    //===================================================================
    // 组合扫描: 从 base 起第一个满足条件的槽位 (轮询回绕)
    //===================================================================
    integer i;
    reg [SLOT_ID_W-1:0] ar_target, r_target, alloc_target;
    reg                 ar_found,  r_found,  alloc_found;

    always_comb begin
        ar_target = next_ar_slot;
        ar_found  = 1'b0;
        for (i = 0; i < SLOT_NUM; i = i + 1) begin
            if (ar_found == 1'b0) begin
                if (slot_state[(next_ar_slot + i) % SLOT_NUM] == S_AR_PEND) begin
                    ar_target = (next_ar_slot + i) % SLOT_NUM;
                    ar_found  = 1'b1;
                end
            end
        end
    end

    always_comb begin
        r_target = next_r_slot;
        r_found  = 1'b0;
        for (i = 0; i < SLOT_NUM; i = i + 1) begin
            if (r_found == 1'b0) begin
                if (slot_state[(next_r_slot + i) % SLOT_NUM] == S_R_ACTIVE) begin
                    r_target = (next_r_slot + i) % SLOT_NUM;
                    r_found  = 1'b1;
                end
            end
        end
    end

    always_comb begin
        alloc_target = alloc_ptr;
        alloc_found  = 1'b0;
        for (i = 0; i < SLOT_NUM; i = i + 1) begin
            if (alloc_found == 1'b0) begin
                if (slot_state[(alloc_ptr + i) % SLOT_NUM] == S_FREE) begin
                    alloc_target = (alloc_ptr + i) % SLOT_NUM;
                    alloc_found  = 1'b1;
                end
            end
        end
    end

    //===================================================================
    // 槽位状态更新 (逐槽)
    //===================================================================
    always @(posedge M_AXI_ACLK) begin
        if (M_AXI_ARESETN == 1'b0) begin
            for (i = 0; i < SLOT_NUM; i = i + 1) begin
                slot_state[i] <= S_FREE;
                slot_addr[i]  <= C_M_TARGET_SLAVE_BASE_ADDR;
                slot_len[i]   <= 0;
                slot_burst[i] <= 2'b01;   // 默认 INCR
            end
        end else begin
            for (i = 0; i < SLOT_NUM; i = i + 1) begin
                case (slot_state[i])
                    S_FREE: begin
                        // 分配: rd_start 且该槽被分配器选中
                        if (rd_start && alloc_found && (alloc_target == i)) begin
                            slot_state[i] <= S_AR_PEND;
                            slot_addr[i]  <= C_M_TARGET_SLAVE_BASE_ADDR + rd_addr_in;
                            slot_len[i]   <= rd_len_in;
                            slot_burst[i] <= (rd_burst_type === 2'bxx) ? 2'b01 : rd_burst_type;
                        end
                    end
                    S_AR_PEND: begin
                        // AR 握手 (该槽被 AR 调度选中)
                        if (ar_valid && M_AXI_ARREADY && (ar_id_reg == i))
                            slot_state[i] <= S_R_ACTIVE;
                    end
                    S_R_ACTIVE: begin
                        // RLAST 握手 (真实握手: 从机 RVALID + 本机 RREADY + RLAST, 槽匹配)
                        // 注意: 必须含 RVALID — 单拍事务时从机 RLAST 组合输出
                        // 比 RVALID 早一拍成立, 漏掉 RVALID 会提前释放槽导致死锁
                        if (M_AXI_RVALID && M_AXI_RREADY && M_AXI_RLAST && (r_target == i)) begin
                            slot_state[i] <= S_FREE;
                            // 地址自增: 突发拍数(len)×beat 字节 (INCR 覆盖 len×W 字节)
                            slot_addr[i]  <= slot_addr[i] + slot_len[i] * BYTES_PER_BEAT;
                        end
                    end
                    default: slot_state[i] <= S_FREE;
                endcase
            end
        end
    end

    //===================================================================
    // 分配指针推进
    //===================================================================
    always @(posedge M_AXI_ACLK) begin
        if (M_AXI_ARESETN == 1'b0) begin
            alloc_ptr <= 0;
        end else if (rd_start && alloc_found) begin
            alloc_ptr <= (alloc_target + 1) % SLOT_NUM;
        end
    end

    //===================================================================
    // AR 调度: 空闲时扫描 AR_PEND 槽发出 (锁存数据, 保序)
    //===================================================================
    always @(posedge M_AXI_ACLK) begin
        if (M_AXI_ARESETN == 1'b0) begin
            ar_valid    <= 1'b0;
            ar_addr_reg <= '0;
            ar_len_reg  <= '0;
            ar_id_reg   <= '0;
            ar_burst_reg <= 2'b01;
        end else if (ar_valid && M_AXI_ARREADY) begin
            ar_valid <= 1'b0;                                   // 握手完成
        end else if (ar_valid == 1'b0 && ar_found) begin
            // 发起新 AR: 锁存数据 (VALID 期间数据稳定)
            ar_valid     <= 1'b1;
            ar_addr_reg  <= slot_addr[ar_target];
            ar_len_reg   <= slot_len[ar_target] - 1;            // AXI ARLEN = 长度-1
            ar_id_reg    <= ar_target;                          // 槽号 (ARID 输出恒 0, 见下)
            ar_burst_reg <= slot_burst[ar_target];
        end
    end

    // AR 调度指针推进 (AR 握手后从下一槽开始扫描)
    always @(posedge M_AXI_ACLK) begin
        if (M_AXI_ARESETN == 1'b0) begin
            next_ar_slot <= 0;
        end else if (ar_valid && M_AXI_ARREADY) begin
            next_ar_slot <= (ar_id_reg + 1) % SLOT_NUM;
        end
    end

    //===================================================================
    // R 保序匹配: r_target 槽位接收 R 数据 (同 ARID=0, 从机保序返回)
    //===================================================================
    assign r_valid     = r_found;
    assign M_AXI_RREADY = r_valid && (rd_fifo_full == 1'b0);    // FIFO 满反压
    assign data_out     = M_AXI_RDATA;                          // 透传用户
    assign data_out_vld = M_AXI_RVALID && M_AXI_RREADY;         // 握手拍有效

    // R 保序指针推进 (RLAST 握手后从下一槽开始)
    always @(posedge M_AXI_ACLK) begin
        if (M_AXI_ARESETN == 1'b0) begin
            next_r_slot <= 0;
        end else if (M_AXI_RVALID && M_AXI_RREADY && M_AXI_RLAST) begin
            next_r_slot <= (r_target + 1) % SLOT_NUM;
        end
    end

    //===================================================================
    // AXI 固定配置信号
    //===================================================================
    assign M_AXI_ARVALID = ar_valid;                               // 调度器输出
    assign M_AXI_ARID    = '0;                                   // 同 ID 保序方案: ARID 恒 0
    assign M_AXI_ARADDR  = ar_addr_reg;
    assign M_AXI_ARLEN   = ar_len_reg;
    assign M_AXI_ARSIZE  = SIZE;
    assign M_AXI_ARBURST = ar_burst_reg;    // FIXED/INCR/WRAP
    assign M_AXI_ARLOCK  = 1'b0;
    assign M_AXI_ARCACHE = 4'b0010;
    assign M_AXI_ARPROT  = 3'd0;
    assign M_AXI_ARQOS   = 4'd0;
    assign M_AXI_ARUSER  = user_aruser;

    //===================================================================
    // 读错误检测 (任一槽位 RRESP != OKAY, 新 start 清零)
    //===================================================================
    always @(posedge M_AXI_ACLK) begin
        if (M_AXI_ARESETN == 1'b0) begin
            rd_error <= 1'b0;
        end else if (rd_start) begin
            rd_error <= 1'b0;
        end else if (M_AXI_RVALID & M_AXI_RREADY && (M_AXI_RRESP != 2'b00)) begin
            rd_error <= 1'b1;
        end
    end

    //===================================================================
    // 空闲槽位指示 (供顶层 user_rd_ready_start)
    //===================================================================
    assign rd_ready_start = alloc_found;

endmodule
