//===========================================================================
// axi_rd_master.v  —  AXI4-Full 读通道控制器
//===========================================================================
// 功能: 独立管理 AXI 读事务 (AR + R 通道)
//   - 2 状态 FSM: IDLE ↔ READ
//   - INCR 突发读, 支持任意长度 (1~256)
//   - rd_fifo_full 自动反压 (RREADY 拉低)
//   - 地址和长度在 rd_start 时锁存
//===========================================================================

`timescale 1ns / 1ns

module axi_rd_master #(
    parameter       C_M_TARGET_SLAVE_BASE_ADDR      =   32'h00000000    ,// 目标从机基地址
    parameter       C_M_AXI_ID_WIDTH                =   1               ,// ID 信号位宽
    parameter       C_M_AXI_ADDR_WIDTH              =   32              ,// 地址位宽
    parameter       C_M_AXI_DATA_WIDTH              =   8               ,// 数据位宽
    parameter       C_M_AXI_RD_LEN_WIDTH            =   8               ,// 读突发长度位宽
    parameter       C_M_AXI_ARUSER_WIDTH            =   0               ,// 读地址 USER 位宽
    parameter       C_M_AXI_RUSER_WIDTH             =   0               // 读数据 USER 位宽
)(
    // --------------------------Global Signals---------------------------//
    input   wire                                        M_AXI_ACLK      ,// AXI 时钟
    input   wire                                        M_AXI_ARESETN   ,// AXI 复位 (低有效)

    // --------------------------USER PORTS (读侧)-----------------------//
    input   wire                                        rd_start        ,// 读操作开始 (单周期脉冲)
    input   wire    [1 : 0]                             rd_burst_type   ,// 突发类型: 00=FIXED 01=INCR 10=WRAP
    input   wire    [C_M_AXI_ADDR_WIDTH-1 : 0]          rd_addr_in      ,// 突发读地址
    input   wire    [C_M_AXI_RD_LEN_WIDTH-1 : 0]        rd_len_in       ,// 突发读长度
    input   wire                                        rd_fifo_full    ,// 读 FIFO 满标志
    input   wire    [C_M_AXI_ARUSER_WIDTH-1 : 0]        user_aruser     ,// 读地址 USER 信号
    output  wire    [C_M_AXI_DATA_WIDTH-1 : 0]          data_out        ,// 输出读数据
    output  wire                                        data_out_vld    ,// 输出读数据有效
    output  reg                                         rd_error        ,// 读事务错误 (RRESP != OKAY)

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
    localparam          IDLE        = 1'b0;
    localparam          READ        = 1'b1;
    localparam          SIZE        = clogb2(C_M_AXI_DATA_WIDTH/8-1);

    function integer clogb2(input integer depth); begin
        if (depth == 0)
            clogb2 = 0;
        else if (depth != 0)
            for (clogb2 = 0; depth > 0; clogb2 = clogb2 + 1)
                depth = depth >> 1;
    end
    endfunction

    //===================================================================
    // 内部寄存器
    //===================================================================
    reg                                     state;
    reg     [C_M_AXI_RD_LEN_WIDTH-1 : 0]    rd_len_latched;
    reg     [1 : 0]                         rd_burst_latched;
    reg                                     rd_data_flag;

    //===================================================================
    // FSM
    //===================================================================
    always @(posedge M_AXI_ACLK) begin
        if (M_AXI_ARESETN == 1'b0) begin
            state           <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    if (rd_start == 1'b1)
                        state <= READ;
                    else
                        state <= IDLE;
                end
                READ: begin
                    // 最后一拍握手完成后才退出 (修复: 单拍读时 RLAST 首拍即置位,
                    // 若 RREADY 尚未拉高, 无握手判定会导致 FSM 提前退出且数据丢失)
                    if (M_AXI_RLAST && M_AXI_RVALID && M_AXI_RREADY)
                        state <= IDLE;
                    else
                        state <= READ;
                end
                default: state <= IDLE;
            endcase
        end
    end

    //===================================================================
    // 长度 / 突发类型锁存
    //===================================================================
    always @(posedge M_AXI_ACLK) begin
        if (M_AXI_ARESETN == 1'b0) begin
            rd_len_latched   <= 0;   // 复位合并到本块, 避免跨 always 多驱动 (综合报 multi-driven)
            rd_burst_latched <= 2'b01;  // 默认 INCR
        end else if (rd_start) begin
            rd_len_latched   <= rd_len_in;
            rd_burst_latched <= (rd_burst_type === 2'bxx) ? 2'b01 : rd_burst_type;
        end
    end

    //===================================================================
    // AXI 固定配置信号
    //===================================================================
    assign M_AXI_ARID    = 0;
    assign M_AXI_ARLEN   = rd_len_latched - 1;
    assign M_AXI_ARSIZE  = SIZE;
    assign M_AXI_ARBURST = rd_burst_latched;  // FIXED/INCR/WRAP
    assign M_AXI_ARLOCK  = 1'b0;
    assign M_AXI_ARCACHE = 4'b0010;
    assign M_AXI_ARPROT  = 3'd0;
    assign M_AXI_ARQOS   = 4'd0;
    assign M_AXI_ARUSER  = user_aruser;

    //===================================================================
    // ARADDR — rd_start 时锁存, 读完成后偏移
    //===================================================================
    always @(posedge M_AXI_ACLK) begin
        if (M_AXI_ARESETN == 1'b0) begin
            M_AXI_ARADDR <= C_M_TARGET_SLAVE_BASE_ADDR;
        end else if (rd_start) begin
            M_AXI_ARADDR <= C_M_TARGET_SLAVE_BASE_ADDR + rd_addr_in;
        end else if (M_AXI_RLAST && M_AXI_RVALID) begin
            M_AXI_ARADDR <= M_AXI_ARADDR + (rd_len_latched * C_M_AXI_DATA_WIDTH/8);
        end
    end

    //===================================================================
    // ARVALID — rd_start 脉冲触发
    //===================================================================
    always @(posedge M_AXI_ACLK) begin
        if (M_AXI_ARESETN == 1'b0) begin
            M_AXI_ARVALID <= 1'b0;
        end else if (M_AXI_ARREADY & M_AXI_ARVALID) begin
            M_AXI_ARVALID <= 1'b0;
        end else if (rd_start == 1'b1) begin
            M_AXI_ARVALID <= 1'b1;
        end
    end

    //===================================================================
    // rd_data_flag — AR 握手后置位, 读数据最后一拍清零
    //===================================================================
    always @(posedge M_AXI_ACLK) begin
        if (M_AXI_ARESETN == 1'b0) begin
            rd_data_flag <= 1'b0;
        end else if (M_AXI_RLAST && M_AXI_RVALID && M_AXI_RREADY) begin
            rd_data_flag <= 1'b0;   // 最后一拍握手完成后清除
        end else if (M_AXI_ARREADY & M_AXI_ARVALID) begin
            rd_data_flag <= 1'b1;
        end else begin
            rd_data_flag <= rd_data_flag;
        end
    end

    //===================================================================
    // RREADY — 读 FIFO 满时反压
    //===================================================================
    always @(posedge M_AXI_ACLK) begin
        if (M_AXI_ARESETN == 1'b0) begin
            M_AXI_RREADY <= 1'b0;
        end else if (rd_fifo_full == 1'b0) begin
            // 仅当最后一拍握手完成才关闭 RREADY (修复: 单拍读时 RLAST 首拍即置位,
            // 若在 RREADY=0 时提前关闭, RREADY 将永远无法再拉高 → 读通道死锁)
            if (M_AXI_RLAST && M_AXI_RVALID && M_AXI_RREADY) begin
                M_AXI_RREADY <= 1'b0;
            end else if (rd_data_flag) begin
                M_AXI_RREADY <= 1'b1;
            end else begin
                M_AXI_RREADY <= M_AXI_RREADY;
            end
        end else begin
            M_AXI_RREADY <= 1'b0;
        end
    end

    //===================================================================
    // 数据输出
    //===================================================================
    assign data_out     = M_AXI_RDATA;
    assign data_out_vld = M_AXI_RVALID & M_AXI_RREADY;

    //===================================================================
    // 读错误检测 (RRESP != OKAY)
    //===================================================================
    always @(posedge M_AXI_ACLK) begin
        if (M_AXI_ARESETN == 1'b0) begin
            rd_error <= 1'b0;
        end else if (rd_start) begin
            rd_error <= 1'b0;                        // 新事务开始, 清除旧错误
        end else if (M_AXI_RVALID & M_AXI_RREADY && M_AXI_RRESP != 2'b00) begin
            rd_error <= 1'b1;                        // 任意拍非 OKAY, 置位错误
        end
    end

endmodule
