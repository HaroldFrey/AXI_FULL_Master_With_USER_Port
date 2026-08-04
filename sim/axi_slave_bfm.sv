//===========================================================================
// axi_slave_bfm.sv  —  AXI4-Full Slave Bus Functional Model
//===========================================================================
// 功能:
//   - 内置 BRAM 存储 (byte-addressable)
//   - 支持 INCR 突发读写
//   - 可配置握手延迟 (通过 input 端口运行时设置)
//   - 独立读写状态机，可同时处理 (本 TB 中 DUT 不支持同时读写)
//===========================================================================

module axi_slave_bfm #(
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = 32,
    parameter int MEM_DEPTH  = 1024      // BRAM 深度 (字节)
)(
    // 时钟与复位
    input  logic                     aclk,
    input  logic                     aresetn,

    // ---- 延迟配置 (运行时可变) ----
    input  int                       aw_ready_delay,   // AWREADY 延迟周期数
    input  int                       w_ready_delay,    // WREADY 延迟周期数
    input  int                       b_valid_delay,    // BVALID 响应延迟
    input  int                       ar_ready_delay,   // ARREADY 延迟周期数
    input  int                       r_valid_delay,    // 首数据 RVALID 延迟
    input  int                       r_data_gap,       // 读数据拍间间隔

    // ---- AXI Write Address Channel ----
    input  logic                     s_axi_awvalid,
    output logic                     s_axi_awready,
    input  logic [ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  logic [7:0]               s_axi_awlen,
    // 以下信号接收但不使用 (DUT 固定值)
    input  logic [2:0]               s_axi_awsize,
    input  logic [1:0]               s_axi_awburst,

    // ---- AXI Write Data Channel ----
    input  logic                     s_axi_wvalid,
    output logic                     s_axi_wready,
    input  logic [DATA_WIDTH-1:0]    s_axi_wdata,
    input  logic                     s_axi_wlast,
    input  logic [DATA_WIDTH/8-1:0]  s_axi_wstrb,

    // ---- AXI Write Response Channel ----
    output logic                     s_axi_bvalid,
    input  logic                     s_axi_bready,
    output logic [1:0]               s_axi_bresp,

    // ---- AXI Read Address Channel ----
    input  logic                     s_axi_arvalid,
    output logic                     s_axi_arready,
    input  logic [ADDR_WIDTH-1:0]    s_axi_araddr,
    input  logic [7:0]               s_axi_arlen,
    input  logic [2:0]               s_axi_arsize,
    input  logic [1:0]               s_axi_arburst,

    // ---- AXI Read Data Channel ----
    output logic                     s_axi_rvalid,
    input  logic                     s_axi_rready,
    output logic [DATA_WIDTH-1:0]    s_axi_rdata,
    output logic                     s_axi_rlast,
    output logic [1:0]               s_axi_rresp
);

    //=======================================================================
    // BRAM
    //=======================================================================
    byte mem [0:MEM_DEPTH-1];

    //=======================================================================
    // 写通道状态机
    //=======================================================================
    typedef enum logic [1:0] {
        W_IDLE  = 2'b00,
        W_AW    = 2'b01,
        W_DATA  = 2'b10,
        W_B     = 2'b11
    } wr_state_t;

    wr_state_t wr_state;

    logic [ADDR_WIDTH-1:0]  wr_addr_latched;
    logic [7:0]             wr_len_latched;
    logic [1:0]             wr_burst_latched;
    logic [7:0]             wr_beat_cnt;
    int                     wr_delay_cnt;

    // WRAP 地址计算 wire
    wire [ADDR_WIDTH-1:0] wr_total_bytes;
    wire [ADDR_WIDTH-1:0] wr_wrap_mask;
    wire [ADDR_WIDTH-1:0] wr_wrap_lower;
    wire [ADDR_WIDTH-1:0] wr_wrap_upper;
    wire [ADDR_WIDTH-1:0] wr_addr_incr;
    wire [ADDR_WIDTH-1:0] wr_addr_wrap;
    wire [ADDR_WIDTH-1:0] wr_beat_addr;

    assign wr_total_bytes = (wr_len_latched + 1) * (DATA_WIDTH / 8);
    assign wr_wrap_mask   = wr_total_bytes - 1;
    assign wr_wrap_lower  = wr_addr_latched & ~wr_wrap_mask;
    assign wr_wrap_upper  = wr_wrap_lower + wr_total_bytes;
    assign wr_addr_incr   = wr_addr_latched + wr_beat_cnt * (DATA_WIDTH / 8);
    assign wr_addr_wrap   = (wr_addr_incr >= wr_wrap_upper) ? (wr_addr_incr - wr_total_bytes) : wr_addr_incr;
    assign wr_beat_addr   = (wr_burst_latched == 2'b00) ? wr_addr_latched :
                            (wr_burst_latched == 2'b10) ? wr_addr_wrap :
                            wr_addr_incr;  // INCR

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            wr_state       <= W_IDLE;
            s_axi_awready  <= 1'b0;
            s_axi_wready   <= 1'b0;
            s_axi_bvalid   <= 1'b0;
            s_axi_bresp    <= 2'b00;
            wr_beat_cnt    <= '0;
            wr_delay_cnt   <= 0;
        end else begin
            case (wr_state)

                // ---- W_IDLE: 等待 AWVALID ----
                W_IDLE: begin
                    s_axi_awready <= 1'b0;
                    s_axi_wready  <= 1'b0;
                    s_axi_bvalid  <= 1'b0;
                    wr_beat_cnt   <= '0;
                    wr_delay_cnt  <= 0;

                    if (s_axi_awvalid && aw_ready_delay == 0) begin
                        s_axi_awready  <= 1'b1;
                        wr_state       <= W_AW;
                    end else if (s_axi_awvalid && aw_ready_delay > 0) begin
                        wr_state       <= W_AW;
                    end
                end

                // ---- W_AW: AW 握手 → 准备接收数据 ----
                W_AW: begin
                    if (aw_ready_delay > 0 && wr_delay_cnt < aw_ready_delay) begin
                        wr_delay_cnt <= wr_delay_cnt + 1;
                    end else if (aw_ready_delay > 0 && wr_delay_cnt >= aw_ready_delay) begin
                        // 延迟到达，完成 AW 握手
                        if (s_axi_awvalid) begin
                            s_axi_awready   <= 1'b1;
                            wr_addr_latched  <= s_axi_awaddr;
                            wr_len_latched   <= s_axi_awlen;
                            wr_burst_latched <= s_axi_awburst;
                            wr_state         <= W_DATA;
                        end
                    end else if (s_axi_awready && s_axi_awvalid) begin
                        // AW 握手完成
                        s_axi_awready   <= 1'b0;
                        wr_addr_latched  <= s_axi_awaddr;
                        wr_len_latched   <= s_axi_awlen;
                        wr_burst_latched <= s_axi_awburst;
                        wr_state         <= W_DATA;
                    end
                end

                // ---- W_DATA: 接收写数据，写入 BRAM ----
                W_DATA: begin
                    if (w_ready_delay > 0 && wr_delay_cnt < w_ready_delay && !s_axi_wvalid) begin
                        // 首次等待: 计数直到延迟满足
                    end else if (w_ready_delay > 0 && wr_delay_cnt < w_ready_delay) begin
                        wr_delay_cnt <= wr_delay_cnt + 1;
                    end else begin
                        // 就绪: 握手
                        s_axi_wready <= (w_ready_delay == 0 || wr_delay_cnt >= w_ready_delay);

                        if (s_axi_wvalid && s_axi_wready) begin
                            // 写入 BRAM (FIXED/INCR/WRAP 地址计算)
                            mem[wr_beat_addr] <= s_axi_wdata;
                            wr_beat_cnt <= wr_beat_cnt + 8'd1;

                            if (s_axi_wlast) begin
                                s_axi_wready <= 1'b0;
                                wr_state     <= W_B;
                                wr_delay_cnt <= 0;
                            end
                        end
                    end
                end

                // ---- W_B: 写响应 ----
                W_B: begin
                    if (b_valid_delay > 0 && wr_delay_cnt < b_valid_delay) begin
                        wr_delay_cnt <= wr_delay_cnt + 1;
                    end else begin
                        s_axi_bvalid <= 1'b1;
                        s_axi_bresp  <= 2'b00;   // OKAY

                        if (s_axi_bvalid && s_axi_bready) begin
                            s_axi_bvalid <= 1'b0;
                            wr_state     <= W_IDLE;
                        end
                    end
                end

                default: wr_state <= W_IDLE;

            endcase
        end
    end

    //=======================================================================
    // 读通道状态机
    //=======================================================================
    typedef enum logic [1:0] {
        R_IDLE  = 2'b00,
        R_AR    = 2'b01,
        R_DATA  = 2'b10
    } rd_state_t;

    rd_state_t rd_state;

    logic [ADDR_WIDTH-1:0]  rd_addr_latched;
    logic [7:0]             rd_len_latched;
    logic [1:0]             rd_burst_latched;
    logic [7:0]             rd_beat_cnt;
    int                     rd_delay_cnt;
    int                     rd_gap_cnt;

    // WRAP 地址计算 wire (读侧)
    wire [ADDR_WIDTH-1:0] rd_total_bytes;
    wire [ADDR_WIDTH-1:0] rd_wrap_mask;
    wire [ADDR_WIDTH-1:0] rd_wrap_lower;
    wire [ADDR_WIDTH-1:0] rd_wrap_upper;
    wire [ADDR_WIDTH-1:0] rd_addr_incr;
    wire [ADDR_WIDTH-1:0] rd_addr_wrap;
    wire [ADDR_WIDTH-1:0] rd_beat_addr;

    assign rd_total_bytes = (rd_len_latched + 1) * (DATA_WIDTH / 8);
    assign rd_wrap_mask   = rd_total_bytes - 1;
    assign rd_wrap_lower  = rd_addr_latched & ~rd_wrap_mask;
    assign rd_wrap_upper  = rd_wrap_lower + rd_total_bytes;
    assign rd_addr_incr   = rd_addr_latched + rd_beat_cnt * (DATA_WIDTH / 8);
    assign rd_addr_wrap   = (rd_addr_incr >= rd_wrap_upper) ? (rd_addr_incr - rd_total_bytes) : rd_addr_incr;
    assign rd_beat_addr   = (rd_burst_latched == 2'b00) ? rd_addr_latched :
                            (rd_burst_latched == 2'b10) ? rd_addr_wrap :
                            rd_addr_incr;  // INCR

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            rd_state       <= R_IDLE;
            s_axi_arready  <= 1'b0;
            s_axi_rvalid   <= 1'b0;
            s_axi_rdata    <= '0;
            s_axi_rlast    <= 1'b0;
            s_axi_rresp    <= 2'b00;
            rd_beat_cnt    <= '0;
            rd_delay_cnt   <= 0;
            rd_gap_cnt     <= 0;
        end else begin
            case (rd_state)

                // ---- R_IDLE: 等待 ARVALID ----
                R_IDLE: begin
                    s_axi_arready <= 1'b0;
                    s_axi_rvalid  <= 1'b0;
                    s_axi_rlast   <= 1'b0;
                    rd_delay_cnt  <= 0;
                    rd_gap_cnt    <= 0;

                    if (s_axi_arvalid && ar_ready_delay == 0) begin
                        s_axi_arready <= 1'b1;
                        rd_state      <= R_AR;
                    end else if (s_axi_arvalid && ar_ready_delay > 0) begin
                        rd_state      <= R_AR;
                    end
                end

                // ---- R_AR: AR 握手 → 准备发送数据 ----
                R_AR: begin
                    if (ar_ready_delay > 0 && rd_delay_cnt < ar_ready_delay) begin
                        rd_delay_cnt <= rd_delay_cnt + 1;
                    end else if (ar_ready_delay > 0 && rd_delay_cnt >= ar_ready_delay) begin
                        if (s_axi_arvalid) begin
                            s_axi_arready   <= 1'b1;
                            rd_addr_latched  <= s_axi_araddr;
                            rd_len_latched   <= s_axi_arlen;
                            rd_burst_latched <= s_axi_arburst;
                            rd_state         <= R_DATA;
                            rd_beat_cnt      <= '0;
                            rd_delay_cnt     <= 0;
                        end
                    end else if (s_axi_arready && s_axi_arvalid) begin
                        s_axi_arready    <= 1'b0;
                        rd_addr_latched  <= s_axi_araddr;
                        rd_len_latched   <= s_axi_arlen;
                        rd_burst_latched <= s_axi_arburst;
                        rd_state         <= R_DATA;
                        rd_beat_cnt      <= '0;
                    end
                end

                // ---- R_DATA: 发送读数据 ----
                R_DATA: begin
                    // 首数据延迟
                    if (r_valid_delay > 0 && rd_delay_cnt < r_valid_delay) begin
                        rd_delay_cnt <= rd_delay_cnt + 1;
                    end
                    // 拍间间隔
                    else if (r_data_gap > 0 && s_axi_rvalid && s_axi_rready) begin
                        // 上一拍握手完成，插入间隔
                        s_axi_rvalid <= 1'b0;
                        rd_gap_cnt   <= 0;
                    end
                    else if (!s_axi_rvalid && rd_gap_cnt < r_data_gap) begin
                        rd_gap_cnt <= rd_gap_cnt + 1;
                    end
                    // 发送数据
                    else if (r_valid_delay == 0 || rd_delay_cnt >= r_valid_delay) begin
                        s_axi_rvalid <= 1'b1;
                        s_axi_rdata  <= mem[rd_beat_addr];
                        s_axi_rlast  <= (rd_beat_cnt == rd_len_latched);

                        if (s_axi_rvalid && s_axi_rready) begin
                            // 握手成功
                            if (rd_beat_cnt == rd_len_latched) begin
                                // 最后一拍完成
                                s_axi_rvalid <= 1'b0;
                                s_axi_rlast  <= 1'b0;
                                rd_state     <= R_IDLE;
                            end else begin
                                rd_beat_cnt <= rd_beat_cnt + 8'd1;
                            end
                        end
                    end
                end

                default: rd_state <= R_IDLE;

            endcase
        end
    end

    //=======================================================================
    // 未使用的 AXI 信号处理
    //=======================================================================
    // ID, LOCK, CACHE, PROT, QOS — 忽略但保留端口连接
    // BRESP/RRESP 始终返回 OKAY (2'b00)

endmodule
