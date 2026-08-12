//===========================================================================
// axi_wr_master.v  —  AXI4-Full 写通道控制器 (Outstanding 版)
//===========================================================================
// 功能: 独立管理 AXI 写事务 (AW + W + B 通道), 支持多个在途事务
//   - 槽位表 (MAX_OUTSTANDING_WR 个), 每槽跟踪一个事务
//   - 槽位状态机: FREE → AW_PEND → W_DATA → B_WAIT → FREE
//   - AW 按 start 顺序流水线发出 (轮询指针, 保 W 顺序 = AW 顺序)
//   - W 数据串行发送 (AXI4 无 WID: 写数据顺序必须等于写地址顺序),
//     数据来自 Data_RX FIFO (FIFO 顺序 = 用户写入顺序 = start 顺序)
//   - B 响应按 BID(=槽号) 匹配, 天然支持乱序返回
//   - wr_ready_start: 有空闲槽位时拉高 (用户仅在此时可发起新事务)
// 设计: doc/outstanding_设计方案.md
//===========================================================================

`timescale 1ns / 1ns

module axi_wr_master #(
    parameter       C_M_TARGET_SLAVE_BASE_ADDR      =   32'h00000000    ,// 目标从机基地址
    parameter       C_M_AXI_ID_WIDTH                =   1               ,// ID 信号位宽
    parameter       C_M_AXI_ADDR_WIDTH              =   32              ,// 地址位宽
    parameter       C_M_AXI_DATA_WIDTH              =   8               ,// 数据位宽
    parameter       C_M_AXI_WR_LEN_WIDTH            =   8               ,// 写突发长度位宽
    parameter       C_M_AXI_AWUSER_WIDTH            =   0               ,// 写地址 USER 位宽
    parameter       C_M_AXI_WUSER_WIDTH             =   0               ,// 写数据 USER 位宽
    parameter       C_M_AXI_BUSER_WIDTH             =   0               ,// 写响应 USER 位宽
    parameter       integer MAX_OUTSTANDING_WR      =   4                // 槽位数 (1~8)
)(
    // --------------------------Global Signals---------------------------//
    input   wire                                        M_AXI_ACLK      ,// AXI 时钟
    input   wire                                        M_AXI_ARESETN   ,// AXI 复位 (低有效)

    // --------------------------USER PORTS (写侧)-----------------------//
    input   wire                                        wr_start        ,// 写操作开始 (单周期脉冲)
    input   wire    [1 : 0]                             wr_burst_type   ,// 突发类型: 00=FIXED 01=INCR 10=WRAP
    output  wire                                        data_rd_en      ,// FIFO 读使能
    input   wire                                        wr_fifo_empty   ,// 写 FIFO 空标志
    input   wire    [C_M_AXI_ADDR_WIDTH-1 : 0]          wr_addr_in      ,// 突发写地址
    input   wire    [C_M_AXI_WR_LEN_WIDTH-1 : 0]        wr_len_in       ,// 突发写长度 (1~256)
    input   wire    [C_M_AXI_DATA_WIDTH-1 : 0]          wr_data_in      ,// 写数据 (来自 FIFO)
    input   wire    [C_M_AXI_AWUSER_WIDTH-1 : 0]        user_awuser     ,// 写地址 USER 信号
    input   wire    [C_M_AXI_WUSER_WIDTH-1 : 0]         user_wuser      ,// 写数据 USER 信号
    output  reg                                         wr_error        ,// 写事务错误 (BRESP != OKAY)
    output  wire                                        wr_ready_start  ,// 有空闲槽位 (可接受新事务)

    // -------------------------AXI WRITE CHANNELS-----------------------//
    // AW Channel
    output          [C_M_AXI_ID_WIDTH-1 : 0]            M_AXI_AWID      ,
    output  reg     [C_M_AXI_ADDR_WIDTH-1 : 0]          M_AXI_AWADDR    ,
    output          [C_M_AXI_WR_LEN_WIDTH-1 : 0]        M_AXI_AWLEN     ,
    output          [2 : 0]                             M_AXI_AWSIZE    ,
    output          [1 : 0]                             M_AXI_AWBURST   ,
    output                                              M_AXI_AWLOCK    ,
    output          [3 : 0]                             M_AXI_AWCACHE   ,
    output          [2 : 0]                             M_AXI_AWPROT    ,
    output          [3 : 0]                             M_AXI_AWQOS     ,
    output          [C_M_AXI_AWUSER_WIDTH-1 : 0]        M_AXI_AWUSER    ,
    output  reg                                         M_AXI_AWVALID   ,
    input                                               M_AXI_AWREADY   ,

    // W Channel
    output  wire    [C_M_AXI_DATA_WIDTH-1 : 0]          M_AXI_WDATA     ,
    output          [C_M_AXI_DATA_WIDTH/8-1 : 0]        M_AXI_WSTRB     ,
    output                                              M_AXI_WLAST     ,
    output          [C_M_AXI_WUSER_WIDTH-1 : 0]         M_AXI_WUSER     ,
    output                                              M_AXI_WVALID    ,
    input                                               M_AXI_WREADY    ,

    // B Channel
    input           [C_M_AXI_ID_WIDTH-1 : 0]            M_AXI_BID       ,
    input           [1 : 0]                             M_AXI_BRESP     ,
    input           [C_M_AXI_BUSER_WIDTH-1 : 0]         M_AXI_BUSER     ,
    input                                               M_AXI_BVALID    ,
    output  reg                                         M_AXI_BREADY
);

    //===================================================================
    // 参数与函数
    //===================================================================
    localparam          SIZE        = clogb2(C_M_AXI_DATA_WIDTH/8-1);
    localparam          WSTRB_WIDTH = C_M_AXI_DATA_WIDTH/8;   // 便于 iverilog 编译
    localparam          SLOT_NUM    = MAX_OUTSTANDING_WR;     // 槽位数
    localparam          SLOT_ID_W   = (SLOT_NUM > 1) ? $clog2(SLOT_NUM) : 1; // 槽号位宽 (≥1 避免 [-1:0])
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
    localparam          S_AW_PEND   = 2'b01;    // 待发 AW
    localparam          S_W_DATA    = 2'b10;    // 等待/发送 W 数据 (串行调度)
    localparam          S_B_WAIT    = 2'b11;    // W 完成, 等待 B

    //===================================================================
    // 槽位表 (寄存器阵列)
    //===================================================================
    reg [1:0]                       slot_state  [0:SLOT_NUM-1];   // 槽位状态
    reg [C_M_AXI_ADDR_WIDTH-1:0]    slot_addr   [0:SLOT_NUM-1];   // 槽位地址
    reg [C_M_AXI_WR_LEN_WIDTH-1:0]  slot_len    [0:SLOT_NUM-1];   // 槽位突发长度
    reg [1:0]                       slot_burst  [0:SLOT_NUM-1];   // 槽位突发类型

    // 调度指针 (轮询, 天然保持 start 顺序)
    reg [SLOT_ID_W-1:0]             alloc_ptr;      // 分配轮询指针
    reg [SLOT_ID_W-1:0]             next_aw_slot;   // AW 调度扫描起点
    reg [SLOT_ID_W-1:0]             next_w_slot;    // W 调度扫描起点

    reg [31:0]                      wr_cnt;         // 当前 W 事务拍计数

    // AW 通道锁存寄存器 (aw_valid 拉高拍锁存, 保证 VALID 期间数据稳定)
    reg                             aw_valid;
    reg [C_M_AXI_ADDR_WIDTH-1:0]    aw_addr_reg;
    reg [C_M_AXI_WR_LEN_WIDTH-1:0]  aw_len_reg;
    reg [SLOT_ID_W-1:0]             aw_id_reg;
    reg [1:0]                       aw_burst_reg;

    //===================================================================
    // 组合扫描: 从 base 起第一个满足条件的槽位 (轮询回绕)
    //===================================================================
    integer i;
    reg [SLOT_ID_W-1:0] aw_target, w_target, alloc_target;
    reg                 aw_found,  w_found,  alloc_found;
    reg                 any_bwait;

    always_comb begin
        // 槽号计算辅助: (base + i) 回绕
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

    always_comb begin
        w_target = next_w_slot;
        w_found  = 1'b0;
        for (i = 0; i < SLOT_NUM; i = i + 1) begin
            if (w_found == 1'b0) begin
                if (slot_state[(next_w_slot + i) % SLOT_NUM] == S_W_DATA) begin
                    w_target = (next_w_slot + i) % SLOT_NUM;
                    w_found  = 1'b1;
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

    always_comb begin
        any_bwait = 1'b0;
        for (i = 0; i < SLOT_NUM; i = i + 1) begin
            if (slot_state[i] == S_B_WAIT)
                any_bwait = 1'b1;
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
                        // 分配: wr_start 且该槽被分配器选中
                        if (wr_start && alloc_found && (alloc_target == i)) begin
                            slot_state[i] <= S_AW_PEND;
                            slot_addr[i]  <= C_M_TARGET_SLAVE_BASE_ADDR + wr_addr_in;
                            slot_len[i]   <= wr_len_in;
                            slot_burst[i] <= (wr_burst_type === 2'bxx) ? 2'b01 : wr_burst_type;
                        end
                    end
                    S_AW_PEND: begin
                        // AW 握手 (该槽被 AW 调度选中)
                        if (aw_valid && M_AXI_AWREADY && (aw_id_reg == i))
                            slot_state[i] <= S_W_DATA;
                    end
                    S_W_DATA: begin
                        // WLAST 握手 (该槽被 W 调度选中)
                        if (w_valid && M_AXI_WREADY && M_AXI_WLAST && (w_target == i))
                            slot_state[i] <= S_B_WAIT;
                    end
                    S_B_WAIT: begin
                        // B 握手 (BID 匹配, 乱序兼容)
                        if (M_AXI_BVALID && b_ready && (M_AXI_BID[SLOT_ID_W-1:0] == i)) begin
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
    // 分配指针推进 (分配拍后指向下一槽)
    //===================================================================
    always @(posedge M_AXI_ACLK) begin
        if (M_AXI_ARESETN == 1'b0) begin
            alloc_ptr <= 0;
        end else if (wr_start && alloc_found) begin
            alloc_ptr <= (alloc_target + 1) % SLOT_NUM;
        end
    end

    //===================================================================
    // AW 调度: 空闲时扫描 AW_PEND 槽发出 (锁存数据, 保序)
    //===================================================================
    always @(posedge M_AXI_ACLK) begin
        if (M_AXI_ARESETN == 1'b0) begin
            aw_valid   <= 1'b0;
            aw_addr_reg <= '0;
            aw_len_reg  <= '0;
            aw_id_reg   <= '0;
            aw_burst_reg <= 2'b01;
        end else if (aw_valid && M_AXI_AWREADY) begin
            aw_valid <= 1'b0;                                   // 握手完成
        end else if (aw_valid == 1'b0 && aw_found) begin
            // 发起新 AW: 锁存数据 (VALID 期间数据稳定)
            aw_valid     <= 1'b1;
            aw_addr_reg  <= slot_addr[aw_target];
            aw_len_reg   <= slot_len[aw_target] - 1;            // AXI ALEN = 长度-1
            aw_id_reg    <= aw_target;                          // AWID = 槽号
            aw_burst_reg <= slot_burst[aw_target];
        end
    end

    // AW 调度指针推进 (AW 握手后从下一槽开始扫描)
    always @(posedge M_AXI_ACLK) begin
        if (M_AXI_ARESETN == 1'b0) begin
            next_aw_slot <= 0;
        end else if (aw_valid && M_AXI_AWREADY) begin
            next_aw_slot <= (aw_id_reg + 1) % SLOT_NUM;
        end
    end

    //===================================================================
    // W 调度 (串行): w_target 槽位有数据待发且 FIFO 非空
    //===================================================================
    assign w_valid     = w_found && (wr_fifo_empty == 1'b0) && (wr_cnt != slot_len[w_target]);
    assign M_AXI_WVALID = w_valid;
    assign M_AXI_WLAST  = w_valid && (wr_cnt == slot_len[w_target] - 1);
    assign data_rd_en   = w_valid && M_AXI_WREADY;              // FIFO 读使能 (与握手同步)
    assign M_AXI_WDATA  = data_rd_en ? wr_data_in : {C_M_AXI_DATA_WIDTH{1'b0}};

    // W 拍计数 (WLAST 握手后清零, 供下一事务)
    always @(posedge M_AXI_ACLK) begin
        if (M_AXI_ARESETN == 1'b0) begin
            wr_cnt <= 32'd0;
        end else if (w_valid && M_AXI_WREADY) begin
            if (M_AXI_WLAST) wr_cnt <= 32'd0;
            else             wr_cnt <= wr_cnt + 1;
        end
    end

    // W 调度指针推进 (WLAST 握手后从下一槽开始扫描)
    always @(posedge M_AXI_ACLK) begin
        if (M_AXI_ARESETN == 1'b0) begin
            next_w_slot <= 0;
        end else if (w_valid && M_AXI_WREADY && M_AXI_WLAST) begin
            next_w_slot <= (w_target + 1) % SLOT_NUM;
        end
    end

    //===================================================================
    // B 通道: 仅当存在 B_WAIT 槽位时接受 (B 到达时槽位必已 B_WAIT)
    //===================================================================
    assign b_ready     = any_bwait;
    assign M_AXI_BREADY = b_ready;

    //===================================================================
    // AXI 固定配置信号
    //===================================================================
    // AWID = 槽号高位补 0; ID 位宽不足槽号位宽时编译报错 (BID 无法区分槽位)
    initial if (C_M_AXI_ID_WIDTH < SLOT_ID_W)
        $error("axi_wr_master: C_M_AXI_ID_WIDTH(%0d) < 槽号位宽(%0d), 无法区分 outstanding 槽位",
               C_M_AXI_ID_WIDTH, SLOT_ID_W);
    assign M_AXI_AWVALID = aw_valid;                                  // 调度器输出
    assign M_AXI_AWID    = {{(C_M_AXI_ID_WIDTH - SLOT_ID_W){1'b0}}, aw_id_reg};  // 高位补 0
    assign M_AXI_AWADDR  = aw_addr_reg;
    assign M_AXI_AWLEN   = aw_len_reg;
    assign M_AXI_AWSIZE  = SIZE;
    assign M_AXI_AWBURST = aw_burst_reg;    // FIXED/INCR/WRAP
    assign M_AXI_AWLOCK  = 1'b0;
    assign M_AXI_AWCACHE = 4'b0010;
    assign M_AXI_AWPROT  = 3'd0;
    assign M_AXI_AWQOS   = 4'd0;
    assign M_AXI_AWUSER  = user_awuser;
    assign M_AXI_WUSER   = user_wuser;
    assign M_AXI_WSTRB   = {{WSTRB_WIDTH}{1'b1}};

    //===================================================================
    // 写错误检测 (任一槽位 BRESP != OKAY, 新 start 清零)
    //===================================================================
    always @(posedge M_AXI_ACLK) begin
        if (M_AXI_ARESETN == 1'b0) begin
            wr_error <= 1'b0;
        end else if (wr_start) begin
            wr_error <= 1'b0;
        end else if (M_AXI_BVALID && b_ready && (M_AXI_BRESP != 2'b00)) begin
            wr_error <= 1'b1;
        end
    end

    //===================================================================
    // 空闲槽位指示 (供顶层 user_wr_ready_start)
    //===================================================================
    assign wr_ready_start = alloc_found;

endmodule
