//===========================================================================
// tb_axi_master_simple.sv — AXI_FULL_Master_With_USER_Port 简单测试平台
//===========================================================================
// 目的: 用尽量简单的 SystemVerilog 语法验证模块最基本的功能
// 语法: 只使用 reg / wire / always / initial / task
//       (不使用 class / package / interface / typedef 等复杂语法)
// 工具: iverilog + gtkwave
//   编译: iverilog -g2012 -o tb_axi_master_simple.out -s tb_axi_master_simple \
//            ../rtl/AXI_FULL_Master_With_USER_Port/*.v \
//            ../rtl/FIFO/fifo_async.v tb_axi_master_simple.sv
//   仿真: vvp tb_axi_master_simple.out
//   波形: tb_axi_master_simple.vcd (可用 gtkwave 打开)
// 测试用例 (INCR 突发):
//   TC1  基本写突发 len=8  @0x100  seed=0x10
//   TC2  基本读突发 len=8  @0x100  (逐拍比对数据)
//   TC3  单拍写 + 单拍读   @0x108  seed=0xA5
//   TC4  用户读反压        @0x200  (每拍后 user_rd_ready 拉低 2 拍)
//   TC5  用户写反压        @0x300  (每拍后 user_wr_valid 拉低 2 拍)
// 结果: test_done / test_pass 寄存器写入 VCD, 供 check_vcd.py 解析
//===========================================================================

`timescale 1ns / 1ns

module tb_axi_master_simple;

    //=======================================================================
    // 时钟与复位 (三时钟域同频 100MHz, 同相位)
    //=======================================================================
    reg clk_wr  = 1'b0;
    reg clk_rd  = 1'b0;
    reg clk_axi = 1'b0;
    reg rst_n   = 1'b0;
    always #5 clk_wr  = ~clk_wr;
    always #5 clk_rd  = ~clk_rd;
    always #5 clk_axi = ~clk_axi;

    //=======================================================================
    // USER Port 信号
    //=======================================================================
    reg         user_wr_start;
    reg         user_wr_valid;
    reg  [7:0]  user_wr_data_in;
    wire        user_wr_ready;
    reg  [31:0] user_wr_addr;
    reg  [7:0]  user_wr_len;
    reg  [1:0]  user_wr_burst_type;
    wire        user_wr_error;

    reg         user_rd_start;
    wire        user_rd_valid;
    wire [7:0]  user_rd_data_out;
    reg         user_rd_ready;
    reg  [31:0] user_rd_addr;
    reg  [7:0]  user_rd_len;
    reg  [1:0]  user_rd_burst_type;
    wire        user_rd_error;

    //=======================================================================
    // AXI 总线信号 (DUT 与 Slave 之间)
    //=======================================================================
    wire        m_axi_awid;
    wire [31:0] m_axi_awaddr;
    wire [7:0]  m_axi_awlen;
    wire [2:0]  m_axi_awsize;
    wire [1:0]  m_axi_awburst;
    wire        m_axi_awlock;
    wire [3:0]  m_axi_awcache;
    wire [2:0]  m_axi_awprot;
    wire [3:0]  m_axi_awqos;
    wire        m_axi_awvalid;
    wire        m_axi_awready;

    wire [7:0]  m_axi_wdata;
    wire        m_axi_wstrb;
    wire        m_axi_wlast;
    wire        m_axi_wvalid;
    wire        m_axi_wready;

    wire        m_axi_bid;
    wire [1:0]  m_axi_bresp;
    wire        m_axi_bvalid;
    wire        m_axi_bready;

    wire        m_axi_arid;
    wire [31:0] m_axi_araddr;
    wire [7:0]  m_axi_arlen;
    wire [2:0]  m_axi_arsize;
    wire [1:0]  m_axi_arburst;
    wire        m_axi_arlock;
    wire [3:0]  m_axi_arcache;
    wire [2:0]  m_axi_arprot;
    wire [3:0]  m_axi_arqos;
    wire        m_axi_arvalid;
    wire        m_axi_arready;

    wire        m_axi_rid;
    wire [7:0]  m_axi_rdata;
    wire [1:0]  m_axi_rresp;
    wire        m_axi_rlast;
    wire        m_axi_rvalid;
    wire        m_axi_rready;

    //=======================================================================
    // 测试控制与数据比对
    //=======================================================================
    reg [7:0]  exp_mem [0:1023];   // 期望数据表 (地址 -> 数据)
    reg [31:0] err_cnt     = 0;    // 数据比对错误计数
    reg [31:0] wr_burst_cnt = 0;   // 已完成的写事务数
    reg [31:0] rd_burst_cnt = 0;   // 已完成的读事务数
    reg        test_pass   = 1'b0; // 最终结果 (写入 VCD 供检查)
    reg        test_done   = 1'b0; // 测试结束标志 (写入 VCD 供检查)

    //=======================================================================
    // DUT: AXI_FULL_Master_With_USER_Port
    //=======================================================================
    AXI_FULL_Master_With_USER_Port #(
        .C_M_TARGET_SLAVE_BASE_ADDR ( 32'h0000_0000 ),
        .C_M_AXI_ID_WIDTH           ( 1 ),
        .C_M_AXI_ADDR_WIDTH         ( 32 ),
        .C_M_AXI_DATA_WIDTH         ( 8 ),
        .C_M_AXI_WR_LEN_WIDTH       ( 8 ),
        .C_M_AXI_RD_LEN_WIDTH       ( 8 ),
        .C_M_AXI_AWUSER_WIDTH       ( 0 ),
        .C_M_AXI_ARUSER_WIDTH       ( 0 ),
        .C_M_AXI_WUSER_WIDTH        ( 0 ),
        .C_M_AXI_RUSER_WIDTH        ( 0 ),
        .C_M_AXI_BUSER_WIDTH        ( 0 )
    ) dut (
        .clk_wr            ( clk_wr             ),
        .clk_rd            ( clk_rd             ),
        .clk_axi           ( clk_axi            ),
        .rst_n             ( rst_n              ),
        // ---- USER 写侧 ----
        .user_wr_start     ( user_wr_start      ),
        .user_wr_valid     ( user_wr_valid      ),
        .user_wr_data_in   ( user_wr_data_in    ),
        .user_wr_ready     ( user_wr_ready      ),
        .user_wr_addr      ( user_wr_addr       ),
        .user_wr_len       ( user_wr_len        ),
        .user_wr_burst_type( user_wr_burst_type ),
        .user_wr_error     ( user_wr_error      ),
        // ---- USER 读侧 ----
        .user_rd_start     ( user_rd_start      ),
        .user_rd_valid     ( user_rd_valid      ),
        .user_rd_data_out  ( user_rd_data_out   ),
        .user_rd_ready     ( user_rd_ready      ),
        .user_rd_addr      ( user_rd_addr       ),
        .user_rd_len       ( user_rd_len        ),
        .user_rd_burst_type( user_rd_burst_type ),
        .user_rd_error     ( user_rd_error      ),
        // ---- AXI 写地址通道 ----
        .M_AXI_AWID        ( m_axi_awid         ),
        .M_AXI_AWADDR      ( m_axi_awaddr       ),
        .M_AXI_AWLEN       ( m_axi_awlen        ),
        .M_AXI_AWSIZE      ( m_axi_awsize       ),
        .M_AXI_AWBURST     ( m_axi_awburst      ),
        .M_AXI_AWLOCK      ( m_axi_awlock       ),
        .M_AXI_AWCACHE     ( m_axi_awcache      ),
        .M_AXI_AWPROT      ( m_axi_awprot       ),
        .M_AXI_AWQOS       ( m_axi_awqos        ),
        .M_AXI_AWVALID     ( m_axi_awvalid      ),
        .M_AXI_AWREADY     ( m_axi_awready      ),
        // ---- AXI 写数据通道 ----
        .M_AXI_WDATA       ( m_axi_wdata        ),
        .M_AXI_WSTRB       ( m_axi_wstrb        ),
        .M_AXI_WLAST       ( m_axi_wlast        ),
        .M_AXI_WVALID      ( m_axi_wvalid       ),
        .M_AXI_WREADY      ( m_axi_wready       ),
        // ---- AXI 写响应通道 ----
        .M_AXI_BID         ( m_axi_bid          ),
        .M_AXI_BRESP       ( m_axi_bresp        ),
        .M_AXI_BVALID      ( m_axi_bvalid       ),
        .M_AXI_BREADY      ( m_axi_bready       ),
        // ---- AXI 读地址通道 ----
        .M_AXI_ARID        ( m_axi_arid         ),
        .M_AXI_ARADDR      ( m_axi_araddr       ),
        .M_AXI_ARLEN       ( m_axi_arlen        ),
        .M_AXI_ARSIZE      ( m_axi_arsize       ),
        .M_AXI_ARBURST     ( m_axi_arburst      ),
        .M_AXI_ARLOCK      ( m_axi_arlock       ),
        .M_AXI_ARCACHE     ( m_axi_arcache      ),
        .M_AXI_ARPROT      ( m_axi_arprot       ),
        .M_AXI_ARQOS       ( m_axi_arqos        ),
        .M_AXI_ARVALID     ( m_axi_arvalid      ),
        .M_AXI_ARREADY     ( m_axi_arready      ),
        // ---- AXI 读数据通道 ----
        .M_AXI_RID         ( m_axi_rid          ),
        .M_AXI_RDATA       ( m_axi_rdata        ),
        .M_AXI_RRESP       ( m_axi_rresp        ),
        .M_AXI_RLAST       ( m_axi_rlast        ),
        .M_AXI_RVALID      ( m_axi_rvalid       ),
        .M_AXI_RREADY      ( m_axi_rready       )
        // 注: 位宽为 0 的 USER 信号 (AWUSER/WUSER/ARUSER/BUSER/RUSER) 不连接
    );

    //=======================================================================
    // 极简 AXI Slave (仅支持 INCR 突发, 8-bit 数据, 字节寻址)
    //=======================================================================
    axi_slave_simple #(.MEM_SIZE ( 4096 )) slave (
        .aclk    ( clk_axi       ),
        .aresetn ( rst_n         ),
        .awvalid ( m_axi_awvalid ),
        .awready ( m_axi_awready ),
        .awaddr  ( m_axi_awaddr  ),
        .awlen   ( m_axi_awlen   ),
        .wvalid  ( m_axi_wvalid  ),
        .wready  ( m_axi_wready  ),
        .wdata   ( m_axi_wdata   ),
        .wlast   ( m_axi_wlast   ),
        .bvalid  ( m_axi_bvalid  ),
        .bready  ( m_axi_bready  ),
        .bresp   ( m_axi_bresp   ),
        .arvalid ( m_axi_arvalid ),
        .arready ( m_axi_arready ),
        .araddr  ( m_axi_araddr  ),
        .arlen   ( m_axi_arlen   ),
        .rvalid  ( m_axi_rvalid  ),
        .rready  ( m_axi_rready  ),
        .rdata   ( m_axi_rdata   ),
        .rlast   ( m_axi_rlast   ),
        .rresp   ( m_axi_rresp   )
    );

    //=======================================================================
    // 写突发任务 (INCR, 每拍等待 user_wr_ready 握手, 数据存入期望表)
    //=======================================================================
    task wr_burst (input [31:0] addr, input [7:0] len, input [7:0] seed);
        integer i;
        reg [7:0] data_val;
        begin
            $display("  [WR] addr=0x%08h len=%0d seed=0x%02h", addr, len, seed);
            user_wr_addr       <= addr;
            user_wr_len        <= len;
            user_wr_burst_type <= 2'b01;     // INCR
            @(posedge clk_wr);
            user_wr_start <= 1'b1;           // 单拍 start 脉冲
            @(posedge clk_wr);
            user_wr_start <= 1'b0;
            for (i = 0; i < len; i = i + 1) begin
                data_val = seed + i;
                user_wr_data_in <= data_val; // 非阻塞: 避免与 FIFO 采样竞态
                user_wr_valid   <= 1'b1;
                do @(posedge clk_wr); while (!user_wr_ready);   // 至少等一拍, 直到握手
                exp_mem[addr + i] = data_val;                   // 记录期望数据
            end
            user_wr_valid <= 1'b0;
            // 等待写事务完成 (FSM 回到 IDLE; 比等 B 握手更稳妥, 不会错过已发生的事件)
            while (dut.axi_wr_master_inst.state == 1'b1) @(posedge clk_axi);
            repeat (2) @(posedge clk_axi);
            if (user_wr_error) begin
                $display("  [ERROR] 写事务返回错误 user_wr_error=1");
                err_cnt = err_cnt + 1;
            end
            wr_burst_cnt = wr_burst_cnt + 1;
        end
    endtask

    //=======================================================================
    // 读突发任务 (INCR, 逐拍与期望数据比对)
    //=======================================================================
    task rd_burst (input [31:0] addr, input [7:0] len);
        integer i;
        begin
            $display("  [RD] addr=0x%08h len=%0d", addr, len);
            user_rd_addr       <= addr;
            user_rd_len        <= len;
            user_rd_burst_type <= 2'b01;     // INCR
            @(posedge clk_rd);
            user_rd_start <= 1'b1;           // 单拍 start 脉冲
            @(posedge clk_rd);
            user_rd_start <= 1'b0;
            user_rd_ready <= 1'b1;
            for (i = 0; i < len; i = i + 1) begin
                while (!user_rd_valid) @(posedge clk_rd);    // 等数据
                if (user_rd_data_out !== exp_mem[addr + i]) begin
                    $display("  [ERROR] 读数据不符 addr=0x%08h beat=%0d exp=0x%02h got=0x%02h",
                             addr, i, exp_mem[addr + i], user_rd_data_out);
                    err_cnt = err_cnt + 1;
                end
                @(posedge clk_rd);
            end
            user_rd_ready <= 1'b0;
            // 等几个周期让读事务收尾 (数据已由用户侧读回, 无需再等 RLAST)
            repeat (5) @(posedge clk_axi);
            if (user_rd_error) begin
                $display("  [ERROR] 读事务返回错误 user_rd_error=1");
                err_cnt = err_cnt + 1;
            end
            rd_burst_cnt = rd_burst_cnt + 1;
        end
    endtask

    //=======================================================================
    // 写突发 (带用户反压: 每拍握手后 user_wr_valid 拉低 2 拍)
    //=======================================================================
    task wr_burst_pause (input [31:0] addr, input [7:0] len, input [7:0] seed);
        integer i;
        reg [7:0] data_val;
        begin
            $display("  [WR-pause] addr=0x%08h len=%0d seed=0x%02h", addr, len, seed);
            user_wr_addr       <= addr;
            user_wr_len        <= len;
            user_wr_burst_type <= 2'b01;     // INCR
            @(posedge clk_wr);
            user_wr_start <= 1'b1;           // 单拍 start 脉冲
            @(posedge clk_wr);
            user_wr_start <= 1'b0;
            for (i = 0; i < len; i = i + 1) begin
                data_val = seed + i;
                user_wr_data_in <= data_val; // 非阻塞: 避免与 FIFO 采样竞态
                user_wr_valid   <= 1'b1;
                do @(posedge clk_wr); while (!user_wr_ready);   // 至少等一拍, 直到握手
                exp_mem[addr + i] = data_val;
                user_wr_valid <= 1'b0;       // 反压: 拉低 2 拍
                repeat (2) @(posedge clk_wr);
            end
            user_wr_valid <= 1'b0;
            // 等待写事务完成 (FSM 回到 IDLE; 比等 B 握手更稳妥, 不会错过已发生的事件)
            while (dut.axi_wr_master_inst.state == 1'b1) @(posedge clk_axi);
            repeat (2) @(posedge clk_axi);
            if (user_wr_error) begin
                $display("  [ERROR] 写事务返回错误 user_wr_error=1");
                err_cnt = err_cnt + 1;
            end
            wr_burst_cnt = wr_burst_cnt + 1;
        end
    endtask

    //=======================================================================
    // 读突发 (带用户反压: 每拍接收后 user_rd_ready 拉低 2 拍)
    //=======================================================================
    task rd_burst_pause (input [31:0] addr, input [7:0] len);
        integer i;
        begin
            $display("  [RD-pause] addr=0x%08h len=%0d", addr, len);
            user_rd_addr       <= addr;
            user_rd_len        <= len;
            user_rd_burst_type <= 2'b01;     // INCR
            @(posedge clk_rd);
            user_rd_start <= 1'b1;           // 单拍 start 脉冲
            @(posedge clk_rd);
            user_rd_start <= 1'b0;
            user_rd_ready <= 1'b1;
            for (i = 0; i < len; i = i + 1) begin
                do @(posedge clk_rd); while (!user_rd_valid);   // 至少等一拍 (让 ready 生效并完成弹出)
                if (user_rd_data_out !== exp_mem[addr + i]) begin
                    $display("  [ERROR] 读数据不符 addr=0x%08h beat=%0d exp=0x%02h got=0x%02h",
                             addr, i, exp_mem[addr + i], user_rd_data_out);
                    err_cnt = err_cnt + 1;
                end
                user_rd_ready <= 1'b0;       // 反压: 拉低 2 拍
                repeat (2) @(posedge clk_rd);
                user_rd_ready <= 1'b1;
            end
            user_rd_ready <= 1'b0;
            // 等几个周期让读事务收尾 (数据已由用户侧读回, 无需再等 RLAST)
            repeat (5) @(posedge clk_axi);
            if (user_rd_error) begin
                $display("  [ERROR] 读事务返回错误 user_rd_error=1");
                err_cnt = err_cnt + 1;
            end
            rd_burst_cnt = rd_burst_cnt + 1;
        end
    endtask

    //=======================================================================
    // 主测试流程
    //=======================================================================
    initial begin
        $dumpfile("tb_axi_master_simple.vcd");
        $dumpvars(0, tb_axi_master_simple);

        $display("==============================================");
        $display(" AXI_FULL_Master_With_USER_Port 简单测试平台");
        $display("==============================================");

        // 复位 10 拍后释放
        repeat (10) @(posedge clk_axi);
        rst_n = 1'b1;
        repeat (5) @(posedge clk_axi);

        // ---- TC1: 基本写突发 ----
        $display("[TC1] 基本写突发 len=8 @0x100");
        wr_burst(32'h0000_0100, 8, 8'h10);

        // ---- TC2: 基本读突发 (逐拍比对) ----
        $display("[TC2] 基本读突发 len=8 @0x100");
        rd_burst(32'h0000_0100, 8);

        // ---- TC3: 单拍写 + 单拍读 ----
        $display("[TC3] 单拍写 + 单拍读 @0x108");
        wr_burst(32'h0000_0108, 1, 8'hA5);
        rd_burst(32'h0000_0108, 1);

        // ---- TC4: 用户读反压 ----
        $display("[TC4] 用户读反压 @0x200");
        wr_burst(32'h0000_0200, 8, 8'h20);
        rd_burst_pause(32'h0000_0200, 8);

        // ---- TC5: 用户写反压 ----
        $display("[TC5] 用户写反压 @0x300");
        wr_burst_pause(32'h0000_0300, 8, 8'h30);
        rd_burst(32'h0000_0300, 8);

        // ---- 汇总结果 ----
        test_pass = (err_cnt == 0);
        test_done = 1'b1;
        $display("==============================================");
        $display(" 写事务数: %0d   读事务数: %0d", wr_burst_cnt, rd_burst_cnt);
        if (err_cnt == 0)
            $display(" 结果    : ALL PASS");
        else
            $display(" 结果    : %0d 个错误", err_cnt);
        $display("==============================================");
        $finish;
    end

    // 超时保护 (500us 内未完成则强制结束)
    initial begin
        #500000;
        if (test_done === 1'b0) begin
            $display("[FAIL] 仿真超时 (500us), 测试未完成");
            $finish;
        end
    end

endmodule


//===========================================================================
// 极简 AXI Slave — 仅支持 INCR 突发 (8-bit 数据, 字节寻址)
// 写通道: AW 握手 -> 收 W 数据写内存 -> 返回 B 响应
// 读通道: AR 握手 -> 逐拍返回内存数据
//===========================================================================
module axi_slave_simple #(
    parameter MEM_SIZE = 4096
)(
    input  wire        aclk,
    input  wire        aresetn,
    // ---- AW ----
    input  wire        awvalid,
    output wire        awready,
    input  wire [31:0] awaddr,
    input  wire [7:0]  awlen,        // 本从机仅按 wlast 计数, 不使用 awlen
    // ---- W ----
    input  wire        wvalid,
    output wire        wready,
    input  wire [7:0]  wdata,
    input  wire        wlast,
    // ---- B ----
    output reg         bvalid,
    input  wire        bready,
    output wire [1:0]  bresp,
    // ---- AR ----
    input  wire        arvalid,
    output wire        arready,
    input  wire [31:0] araddr,
    input  wire [7:0]  arlen,
    // ---- R ----
    output reg         rvalid,
    input  wire        rready,
    output wire [7:0]  rdata,
    output wire        rlast,
    output wire [1:0]  rresp
);
    reg [7:0] mem [0:MEM_SIZE-1];

    //-----------------------------------------------------------------------
    // 写通道
    //-----------------------------------------------------------------------
    reg        aw_latched;    // AW 已接收
    reg [31:0] awaddr_l;      // 锁存的写起始地址
    reg [7:0]  w_cnt;         // 已接收写拍计数
    reg        b_pending;     // 写数据收完, 等待 B 握手

    assign awready = ~aw_latched;
    assign wready  = aw_latched & ~b_pending;

    always @(posedge aclk) begin
        if (!aresetn) begin
            aw_latched <= 1'b0;
            awaddr_l   <= 32'h0;
            w_cnt      <= 8'h0;
            b_pending  <= 1'b0;
            bvalid     <= 1'b0;
        end else begin
            // AW 握手: 锁存起始地址
            if (awvalid && awready) begin
                aw_latched <= 1'b1;
                awaddr_l   <= awaddr;
                w_cnt      <= 8'h0;
            end
            // W 数据: 写入内存 (INCR 地址 = 起始 + 拍数)
            if (wvalid && wready) begin
                mem[awaddr_l + w_cnt] <= wdata;
                w_cnt <= w_cnt + 8'h1;
                if (wlast)
                    b_pending <= 1'b1;
            end
            // B 响应: 收完数据后返回 OKAY
            if (b_pending)
                bvalid <= 1'b1;
            if (bvalid && bready) begin
                bvalid     <= 1'b0;
                b_pending  <= 1'b0;
                aw_latched <= 1'b0;
            end
        end
    end

    //-----------------------------------------------------------------------
    // 读通道
    //-----------------------------------------------------------------------
    reg        ar_latched;    // AR 已接收
    reg [31:0] araddr_l;      // 锁存的读起始地址
    reg [7:0]  r_cnt;         // 已发送读拍计数
    reg        r_active;      // 读数据发送中

    assign arready = ~ar_latched;
    assign rdata   = mem[araddr_l + r_cnt];   // 组合读出 (INCR)
    assign rlast   = r_active & (r_cnt == arlen);
    assign rresp   = 2'b00;

    always @(posedge aclk) begin
        if (!aresetn) begin
            ar_latched <= 1'b0;
            araddr_l   <= 32'h0;
            r_cnt      <= 8'h0;
            r_active   <= 1'b0;
            rvalid     <= 1'b0;
        end else begin
            // AR 握手: 锁存起始地址
            if (arvalid && arready) begin
                ar_latched <= 1'b1;
                araddr_l   <= araddr;
                r_cnt      <= 8'h0;
                r_active   <= 1'b1;
            end
            // 数据未发完时保持 rvalid
            if (r_active && !(rvalid && rready))
                rvalid <= 1'b1;
            // 握手: 最后一拍结束事务, 否则推进计数
            if (rvalid && rready) begin
                if (r_cnt == arlen) begin
                    rvalid     <= 1'b0;
                    r_active   <= 1'b0;
                    ar_latched <= 1'b0;
                end else begin
                    r_cnt <= r_cnt + 8'h1;
                end
            end
        end
    end

endmodule
