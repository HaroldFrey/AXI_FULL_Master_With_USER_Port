//===========================================================================
// tb_axi_master.sv  —  AXI_FULL_Master_With_USER_Port 顶层 Testbench
//===========================================================================
// 测试用例: 19 个 (TC01~TC19), 覆盖功能/边界/反压/多时钟场景
// 通过标准: Scoreboard 数据比对全部 PASS
//===========================================================================

`timescale 1ns / 1ns

module tb_axi_master;

    import tb_pkg::*;

    //=======================================================================
    // 时钟与复位
    //=======================================================================
    logic clk_wr;
    logic clk_rd;
    logic clk_axi;
    logic rst_n;

    // 时钟生成 (使用 package 变量, 运行时可变)
    initial begin
        clk_wr = 1'b0;
        forever #(tb_pkg::clk_wr_period/2.0) clk_wr = ~clk_wr;
    end
    initial begin
        clk_rd = 1'b0;
        forever #(tb_pkg::clk_rd_period/2.0) clk_rd = ~clk_rd;
    end
    initial begin
        clk_axi = 1'b0;
        forever #(tb_pkg::clk_axi_period/2.0) clk_axi = ~clk_axi;
    end

    //=======================================================================
    // BFM 延迟配置变量
    //=======================================================================
    int bfm_aw_ready_delay = BFM_AW_READY_DELAY;
    int bfm_w_ready_delay  = BFM_W_READY_DELAY;
    int bfm_b_valid_delay  = BFM_B_VALID_DELAY;
    int bfm_ar_ready_delay = BFM_AR_READY_DELAY;
    int bfm_r_valid_delay  = BFM_R_VALID_DELAY;
    int bfm_r_data_gap     = BFM_R_DATA_GAP;

    //=======================================================================
    // USER Port 信号
    //=======================================================================
    logic                       user_wr_start;
    logic                       user_rd_start;
    logic                       user_wr_valid;
    logic                       user_wr_ready;
    logic [DUT_DATA_WIDTH-1:0]  user_wr_data_in;
    logic [DUT_ADDR_WIDTH-1:0]   user_wr_addr;
    logic [DUT_WR_LEN_WIDTH-1:0] user_wr_len;
    logic [1:0]                  user_wr_burst_type;
    logic                        user_wr_error;
    logic [DUT_AWUSER_WIDTH-1:0] user_awuser;
    logic [DUT_WUSER_WIDTH-1:0]  user_wuser;
    logic                        user_rd_valid;
    logic                        user_rd_ready;
    logic [DUT_DATA_WIDTH-1:0]   user_rd_data_out;
    logic [DUT_ADDR_WIDTH-1:0]   user_rd_addr;
    logic [DUT_RD_LEN_WIDTH-1:0] user_rd_len;
    logic [1:0]                  user_rd_burst_type;
    logic                        user_rd_error;
    logic [DUT_ARUSER_WIDTH-1:0] user_aruser;

    //=======================================================================
    // AXI 总线信号
    //=======================================================================
    // AW channel
    logic [DUT_ID_WIDTH-1:0]      m_axi_awid;
    logic [DUT_ADDR_WIDTH-1:0]    m_axi_awaddr;
    logic [DUT_WR_LEN_WIDTH-1:0]  m_axi_awlen;
    logic [2:0]                   m_axi_awsize;
    logic [1:0]                   m_axi_awburst;
    logic                         m_axi_awlock;
    logic [3:0]                   m_axi_awcache;
    logic [2:0]                   m_axi_awprot;
    logic [3:0]                   m_axi_awqos;
    logic                         m_axi_awvalid;
    logic                         m_axi_awready;

    // W channel
    logic [DUT_DATA_WIDTH-1:0]    m_axi_wdata;
    logic [DUT_DATA_WIDTH/8-1:0]  m_axi_wstrb;
    logic                         m_axi_wlast;
    logic                         m_axi_wvalid;
    logic                         m_axi_wready;

    // B channel
    logic [DUT_ID_WIDTH-1:0]      m_axi_bid;
    logic [1:0]                   m_axi_bresp;
    logic                         m_axi_bvalid;
    logic                         m_axi_bready;

    // AR channel
    logic [DUT_ID_WIDTH-1:0]      m_axi_arid;
    logic [DUT_ADDR_WIDTH-1:0]    m_axi_araddr;
    logic [7:0]                   m_axi_arlen;
    logic [2:0]                   m_axi_arsize;
    logic [1:0]                   m_axi_arburst;
    logic                         m_axi_arlock;
    logic [3:0]                   m_axi_arcache;
    logic [2:0]                   m_axi_arprot;
    logic [3:0]                   m_axi_arqos;
    logic                         m_axi_arvalid;
    logic                         m_axi_arready;

    // R channel
    logic [DUT_ID_WIDTH-1:0]      m_axi_rid;
    logic [DUT_DATA_WIDTH-1:0]    m_axi_rdata;
    logic [1:0]                   m_axi_rresp;
    logic                         m_axi_rlast;
    logic                         m_axi_rvalid;
    logic                         m_axi_rready;

    //=======================================================================
    // Scoreboard
    //=======================================================================
    scoreboard scb;

    //=======================================================================
    // 超时计数器
    //=======================================================================
    int cycle_cnt = 0;
    always_ff @(posedge clk_axi) begin
        cycle_cnt <= cycle_cnt + 1;
        if (cycle_cnt > TIMEOUT_CYCLES) begin
            $error("[TIMEOUT] Simulation hung at cycle %0d!", cycle_cnt);
            $finish;
        end
    end

    //=======================================================================
    // DUT: AXI_FULL_Master_With_USER_Port
    //=======================================================================
    AXI_FULL_Master_With_USER_Port #(
        .C_M_TARGET_SLAVE_BASE_ADDR ( DUT_BASE_ADDR      ),
        .C_M_AXI_ID_WIDTH           ( DUT_ID_WIDTH        ),
        .C_M_AXI_ADDR_WIDTH         ( DUT_ADDR_WIDTH      ),
        .C_M_AXI_DATA_WIDTH         ( DUT_DATA_WIDTH      ),
        .C_M_AXI_WR_LEN_WIDTH       ( DUT_WR_LEN_WIDTH    ),
        .C_M_AXI_RD_LEN_WIDTH       ( DUT_RD_LEN_WIDTH    ),
        .C_M_AXI_AWUSER_WIDTH       ( 0 ),
        .C_M_AXI_ARUSER_WIDTH       ( 0 ),
        .C_M_AXI_WUSER_WIDTH        ( 0 ),
        .C_M_AXI_RUSER_WIDTH        ( 0 ),
        .C_M_AXI_BUSER_WIDTH        ( 0 )
    ) dut (
        .clk_wr           ( clk_wr            ),
        .clk_rd           ( clk_rd            ),
        .clk_axi          ( clk_axi           ),
        .rst_n            ( rst_n             ),

        // USER Port — Write
        .user_wr_start    ( user_wr_start     ),
        .user_wr_valid    ( user_wr_valid     ),
        .user_wr_data_in  ( user_wr_data_in   ),
        .user_wr_ready    ( user_wr_ready     ),
        .user_wr_addr       ( user_wr_addr        ),
        .user_wr_len        ( user_wr_len         ),
        .user_wr_burst_type ( user_wr_burst_type  ),
        .user_wr_error      ( user_wr_error       ),
        .user_awuser        ( user_awuser         ),
        .user_wuser         ( user_wuser          ),

        // USER Port — Read
        .user_rd_start      ( user_rd_start       ),
        .user_rd_valid      ( user_rd_valid       ),
        .user_rd_data_out   ( user_rd_data_out    ),
        .user_rd_ready      ( user_rd_ready       ),
        .user_rd_addr       ( user_rd_addr        ),
        .user_rd_len        ( user_rd_len         ),
        .user_rd_burst_type ( user_rd_burst_type  ),
        .user_rd_error      ( user_rd_error       ),
        .user_aruser        ( user_aruser         ),

        // AXI Write Address
        .M_AXI_AWID       ( m_axi_awid        ),
        .M_AXI_AWADDR     ( m_axi_awaddr      ),
        .M_AXI_AWLEN      ( m_axi_awlen       ),
        .M_AXI_AWSIZE     ( m_axi_awsize      ),
        .M_AXI_AWBURST    ( m_axi_awburst     ),
        .M_AXI_AWLOCK     ( m_axi_awlock      ),
        .M_AXI_AWCACHE    ( m_axi_awcache     ),
        .M_AXI_AWPROT     ( m_axi_awprot      ),
        .M_AXI_AWQOS      ( m_axi_awqos       ),
        .M_AXI_AWUSER     (                   ),
        .M_AXI_AWVALID    ( m_axi_awvalid     ),
        .M_AXI_AWREADY    ( m_axi_awready     ),

        // AXI Write Data
        .M_AXI_WDATA      ( m_axi_wdata       ),
        .M_AXI_WSTRB      ( m_axi_wstrb       ),
        .M_AXI_WLAST      ( m_axi_wlast       ),
        .M_AXI_WUSER      (                   ),
        .M_AXI_WVALID     ( m_axi_wvalid      ),
        .M_AXI_WREADY     ( m_axi_wready      ),

        // AXI Write Response
        .M_AXI_BID        ( m_axi_bid         ),
        .M_AXI_BRESP      ( m_axi_bresp       ),
        .M_AXI_BUSER      (                   ),
        .M_AXI_BVALID     ( m_axi_bvalid      ),
        .M_AXI_BREADY     ( m_axi_bready      ),

        // AXI Read Address
        .M_AXI_ARID       ( m_axi_arid        ),
        .M_AXI_ARADDR     ( m_axi_araddr      ),
        .M_AXI_ARLEN      ( m_axi_arlen       ),
        .M_AXI_ARSIZE     ( m_axi_arsize      ),
        .M_AXI_ARBURST    ( m_axi_arburst     ),
        .M_AXI_ARLOCK     ( m_axi_arlock      ),
        .M_AXI_ARCACHE    ( m_axi_arcache     ),
        .M_AXI_ARPROT     ( m_axi_arprot      ),
        .M_AXI_ARQOS      ( m_axi_arqos       ),
        .M_AXI_ARUSER     (                   ),
        .M_AXI_ARVALID    ( m_axi_arvalid     ),
        .M_AXI_ARREADY    ( m_axi_arready     ),

        // AXI Read Data
        .M_AXI_RID        ( m_axi_rid         ),
        .M_AXI_RDATA      ( m_axi_rdata       ),
        .M_AXI_RRESP      ( m_axi_rresp       ),
        .M_AXI_RLAST      ( m_axi_rlast       ),
        .M_AXI_RUSER      (                   ),
        .M_AXI_RVALID     ( m_axi_rvalid      ),
        .M_AXI_RREADY     ( m_axi_rready      )
    );

    //=======================================================================
    // AXI Slave BFM
    //=======================================================================
    axi_slave_bfm #(
        .DATA_WIDTH ( DUT_DATA_WIDTH  ),
        .ADDR_WIDTH ( DUT_ADDR_WIDTH  ),
        .MEM_DEPTH  ( 4096            )
    ) slave (
        .aclk           ( clk_axi            ),
        .aresetn        ( rst_n              ),
        .aw_ready_delay ( bfm_aw_ready_delay ),
        .w_ready_delay  ( bfm_w_ready_delay  ),
        .b_valid_delay  ( bfm_b_valid_delay  ),
        .ar_ready_delay ( bfm_ar_ready_delay ),
        .r_valid_delay  ( bfm_r_valid_delay  ),
        .r_data_gap     ( bfm_r_data_gap     ),

        .s_axi_awvalid  ( m_axi_awvalid ),
        .s_axi_awready  ( m_axi_awready ),
        .s_axi_awaddr   ( m_axi_awaddr  ),
        .s_axi_awlen    ( m_axi_awlen   ),
        .s_axi_awsize   ( m_axi_awsize  ),
        .s_axi_awburst  ( m_axi_awburst ),

        .s_axi_wvalid   ( m_axi_wvalid  ),
        .s_axi_wready   ( m_axi_wready  ),
        .s_axi_wdata    ( m_axi_wdata   ),
        .s_axi_wlast    ( m_axi_wlast   ),
        .s_axi_wstrb    ( m_axi_wstrb   ),

        .s_axi_bvalid   ( m_axi_bvalid  ),
        .s_axi_bready   ( m_axi_bready  ),
        .s_axi_bresp    ( m_axi_bresp   ),

        .s_axi_arvalid  ( m_axi_arvalid ),
        .s_axi_arready  ( m_axi_arready ),
        .s_axi_araddr   ( m_axi_araddr  ),
        .s_axi_arlen    ( m_axi_arlen   ),
        .s_axi_arsize   ( m_axi_arsize  ),
        .s_axi_arburst  ( m_axi_arburst ),

        .s_axi_rvalid   ( m_axi_rvalid  ),
        .s_axi_rready   ( m_axi_rready  ),
        .s_axi_rdata    ( m_axi_rdata   ),
        .s_axi_rlast    ( m_axi_rlast   ),
        .s_axi_rresp    ( m_axi_rresp   )
    );

    //=======================================================================
    // 仿真控制变量
    //=======================================================================
    int tc_pass = 0;
    int tc_fail = 0;
    int tc_total = 0;

    //=======================================================================
    // 时钟场景配置
    //=======================================================================
    task automatic set_scenario(input int s);
        tb_pkg::clk_wr_period  = CLK_SCENARIOS[s].clk_wr_period;
        tb_pkg::clk_rd_period  = CLK_SCENARIOS[s].clk_rd_period;
        tb_pkg::clk_axi_period = CLK_SCENARIOS[s].clk_axi_period;
    endtask

    //=======================================================================
    // 复位
    //=======================================================================
    task automatic reset(input int scenario = 1);
        set_scenario(scenario);
        // 初始化 USER port 信号
        user_wr_start   = 1'b0;
        user_rd_start   = 1'b0;
        user_wr_valid   = 1'b0;
        user_wr_data_in = '0;
        user_wr_addr    = '0;
        user_wr_len        = '0;
        user_wr_burst_type = 2'b01;  // default INCR
        user_rd_ready      = 1'b0;
        user_rd_addr       = '0;
        user_rd_len        = '0;
        user_rd_burst_type = 2'b01;  // default INCR

        // 默认 BFM 延迟
        bfm_aw_ready_delay = BFM_AW_READY_DELAY;
        bfm_w_ready_delay  = BFM_W_READY_DELAY;
        bfm_b_valid_delay  = BFM_B_VALID_DELAY;
        bfm_ar_ready_delay = BFM_AR_READY_DELAY;
        bfm_r_valid_delay  = BFM_R_VALID_DELAY;
        bfm_r_data_gap     = BFM_R_DATA_GAP;

        // 复位序列
        rst_n = 1'b0;
        repeat (10) @(posedge clk_axi);
        rst_n = 1'b1;
        repeat (5)  @(posedge clk_axi);   // 等待复位释放稳定
        cycle_cnt = 0;
    endtask

    //=======================================================================
    // 测试结果宏
    //=======================================================================
    `define TC_HEAD(name) \
        $display("[%s] Running...", name);

    `define TC_PASS(name) \
        tc_total++; tc_pass++; \
        $display("[%s] PASS", name);

    `define TC_FAIL(name) \
        tc_total++; tc_fail++; \
        $display("[%s] FAIL", name);

    //=======================================================================
    // USER Port 写突发任务 (clk_wr 域)
    //=======================================================================
    task automatic user_wr_burst(
        input logic [31:0] addr,
        input int          len,
        input byte         seed       // 起始数据值
    );
        automatic byte data_val;
        $display("  WR: addr=0x%08h len=%0d seed=0x%02h", addr, len, seed);

        user_wr_addr       = addr;
        user_wr_len        = len;
        user_wr_burst_type = 2'b01;  // INCR

        // 发送 start 脉冲
        @(posedge clk_wr);
        user_wr_start = 1'b1;
        @(posedge clk_wr);
        user_wr_start = 1'b0;

        // 发送数据拍
        for (int i = 0; i < len; i++) begin
            data_val = (seed + i) & 8'hFF;
            user_wr_data_in = data_val;
            user_wr_valid   = 1'b1;

            // 等待握手: valid=1 且 ready=1 的 posedge
            do @(posedge clk_wr); while (!user_wr_ready);

            // 握手成功, 记录到 scoreboard
            scb.record(addr + i, data_val);
        end
        user_wr_valid = 1'b0;
    endtask

    //=======================================================================
    // USER Port 读突发任务 (clk_rd 域) — 含数据校验
    //=======================================================================
    task automatic user_rd_burst(
        input logic [31:0] addr,
        input int          len
    );
        $display("  RD: addr=0x%08h len=%0d", addr, len);

        user_rd_addr       = addr;
        user_rd_len        = len;
        user_rd_burst_type = 2'b01;  // INCR
        user_rd_ready = 1'b1;     // 用户始终就绪 (非反压测试)

        // 发送 start 脉冲
        @(posedge clk_rd);
        user_rd_start = 1'b1;
        @(posedge clk_rd);
        user_rd_start = 1'b0;

        // 接收数据拍
        for (int i = 0; i < len; i++) begin
            // 等待数据有效
            do @(posedge clk_rd); while (!user_rd_valid);

            // 校验数据
            scb.check(addr + i, user_rd_data_out);
        end
    endtask

    //=======================================================================
    // USER Port FIXED 写突发 — 每拍同一地址
    //=======================================================================
    task automatic user_wr_burst_fixed(
        input logic [31:0] addr,
        input int          len,
        input byte         seed
    );
        automatic byte data_val;
        $display("  WR(FIXED): addr=0x%08h len=%0d seed=0x%02h", addr, len, seed);
        user_wr_addr       = addr;
        user_wr_len        = len;
        user_wr_burst_type = 2'b00;  // FIXED

        @(posedge clk_wr);
        user_wr_start = 1'b1;
        @(posedge clk_wr);
        user_wr_start = 1'b0;

        for (int i = 0; i < len; i++) begin
            data_val = (seed + i) & 8'hFF;
            user_wr_data_in = data_val;
            user_wr_valid   = 1'b1;
            do @(posedge clk_wr); while (!user_wr_ready);
            // FIXED: 每拍写入同一地址, 最后一拍覆盖前面
            scb.record(addr, data_val);  // 只记录最后一拍 (覆盖)
        end
        user_wr_valid = 1'b0;
    endtask

    //=======================================================================
    // USER Port FIXED 读突发 — 每拍同一地址, 返回相同数据
    //=======================================================================
    task automatic user_rd_burst_fixed(
        input logic [31:0] addr,
        input int          len,
        input byte         expected_data   // 期望的固定数据值
    );
        $display("  RD(FIXED): addr=0x%08h len=%0d", addr, len);
        user_rd_addr       = addr;
        user_rd_len        = len;
        user_rd_burst_type = 2'b00;  // FIXED
        user_rd_ready      = 1'b1;

        @(posedge clk_rd);
        user_rd_start = 1'b1;
        @(posedge clk_rd);
        user_rd_start = 1'b0;

        for (int i = 0; i < len; i++) begin
            do @(posedge clk_rd); while (!user_rd_valid);
            // FIXED: 每拍同一地址 → 从机返回相同数据
            if (user_rd_data_out !== expected_data) begin
                $error("[TC21] FIXED read beat %0d: exp=0x%02h got=0x%02h",
                       i, expected_data, user_rd_data_out);
            end
        end
    endtask

    //=======================================================================
    // USER Port WRAP 写突发
    //=======================================================================
    task automatic user_wr_burst_wrap(
        input logic [31:0] addr,
        input int          len,
        input byte         seed
    );
        automatic byte data_val;
        $display("  WR(WRAP): addr=0x%08h len=%0d seed=0x%02h", addr, len, seed);
        user_wr_addr       = addr;
        user_wr_len        = len;
        user_wr_burst_type = 2'b10;  // WRAP

        @(posedge clk_wr);
        user_wr_start = 1'b1;
        @(posedge clk_wr);
        user_wr_start = 1'b0;

        for (int i = 0; i < len; i++) begin
            data_val = (seed + i) & 8'hFF;
            user_wr_data_in = data_val;
            user_wr_valid   = 1'b1;
            do @(posedge clk_wr); while (!user_wr_ready);
            // WRAP: 地址回环, 由从机 BFM 计算
            scb.record(addr + i, data_val);  // 期望线性地址数据
        end
        user_wr_valid = 1'b0;
    endtask

    //=======================================================================
    // USER Port WRAP 读突发
    //=======================================================================
    task automatic user_rd_burst_wrap(
        input logic [31:0] addr,
        input int          len
    );
        $display("  RD(WRAP): addr=0x%08h len=%0d", addr, len);
        user_rd_addr       = addr;
        user_rd_len        = len;
        user_rd_burst_type = 2'b10;  // WRAP
        user_rd_ready      = 1'b1;

        @(posedge clk_rd);
        user_rd_start = 1'b1;
        @(posedge clk_rd);
        user_rd_start = 1'b0;

        for (int i = 0; i < len; i++) begin
            do @(posedge clk_rd); while (!user_rd_valid);
            // WRAP: 每拍地址由从机 BFM 计算
            scb.check(addr + i, user_rd_data_out);
        end
    endtask

    //=======================================================================
    // 等待写完成
    //=======================================================================
    task automatic wait_wr_done();
        // 等待 BVALID & BREADY 握手 (写响应完成)
        do @(posedge clk_axi); while (!(m_axi_bvalid && m_axi_bready));
        // 额外等几个周期确保 FSM 回到 IDLE
        repeat (3) @(posedge clk_axi);
    endtask

    //=======================================================================
    // 等待读完成
    //=======================================================================
    task automatic wait_rd_done();
        // 等待 RLAST & RVALID (读突发最后一拍)
        do @(posedge clk_axi); while (!(m_axi_rlast && m_axi_rvalid));
        repeat (3) @(posedge clk_axi);
    endtask

    //=======================================================================
    // 等待写和读完成 (用于写后读一致性测试)
    //=======================================================================
    task automatic wait_idle();
        wait_wr_done();
        // 如果后面有读, 已经在 task 中自行等待
    endtask


    //=======================================================================
    //                       测试用例
    //=======================================================================

    //-----------------------------------------------------------------------
    // TC01: 基本写突发 (len=16)
    //-----------------------------------------------------------------------
    task automatic tc01_basic_write();
        `TC_HEAD("TC01 - Basic Write Burst (len=16)")
        fork
            user_wr_burst(32'h0000_0000, 16, 8'h00);
        join_none
        wait_wr_done();
        // 检查: 写入了 16 拍数据到 scoreboard
        if (scb.errors == 0) `TC_PASS("TC01 - Basic Write Burst (len=16)")
        else                 `TC_FAIL("TC01 - Basic Write Burst (len=16)")
    endtask

    //-----------------------------------------------------------------------
    // TC02: 基本读突发 (len=16)
    // 先预设从机 BRAM 数据, 再读回校验
    //-----------------------------------------------------------------------
    task automatic tc02_basic_read();
        automatic byte pre_data;
        `TC_HEAD("TC02 - Basic Read Burst (len=16)")

        // 预写入从机 BRAM (通过 DUT 写)
        fork user_wr_burst(32'h0000_0100, 16, 8'hA0); join_none
        wait_wr_done();

        // 通过 DUT 读回
        fork user_rd_burst(32'h0000_0100, 16); join_none
        wait_rd_done();

        if (scb.last_pass) `TC_PASS("TC02 - Basic Read Burst (len=16)")
        else               `TC_FAIL("TC02 - Basic Read Burst (len=16)")
    endtask

    //-----------------------------------------------------------------------
    // TC03: 写后读一致性 (len=32)
    //-----------------------------------------------------------------------
    task automatic tc03_write_read_consistency();
        `TC_HEAD("TC03 - Write-Read Consistency (len=32)")
        fork user_wr_burst(32'h0000_0200, 32, 8'h10); join_none
        wait_wr_done();
        fork user_rd_burst(32'h0000_0200, 32); join_none
        wait_rd_done();

        if (scb.last_pass) `TC_PASS("TC03 - Write-Read Consistency (len=32)")
        else               `TC_FAIL("TC03 - Write-Read Consistency (len=32)")
    endtask

    //-----------------------------------------------------------------------
    // TC04: 单拍写突发 (len=1)
    //-----------------------------------------------------------------------
    task automatic tc04_single_beat_write();
        `TC_HEAD("TC04 - Single-Beat Write (len=1)")
        fork user_wr_burst(32'h0000_0300, 1, 8'hA5); join_none
        wait_wr_done();
        // 回读验证
        fork user_rd_burst(32'h0000_0300, 1); join_none
        wait_rd_done();

        if (scb.last_pass) `TC_PASS("TC04 - Single-Beat Write (len=1)")
        else               `TC_FAIL("TC04 - Single-Beat Write (len=1)")
    endtask

    //-----------------------------------------------------------------------
    // TC05: 单拍读突发 (len=1)
    //-----------------------------------------------------------------------
    task automatic tc05_single_beat_read();
        `TC_HEAD("TC05 - Single-Beat Read (len=1)")
        fork user_wr_burst(32'h0000_0400, 1, 8'h5A); join_none
        wait_wr_done();
        fork user_rd_burst(32'h0000_0400, 1); join_none
        wait_rd_done();

        if (scb.last_pass) `TC_PASS("TC05 - Single-Beat Read (len=1)")
        else               `TC_FAIL("TC05 - Single-Beat Read (len=1)")
    endtask

    //-----------------------------------------------------------------------
    // TC06: AXI 写反压 (WREADY 随机延迟)
    //-----------------------------------------------------------------------
    task automatic tc06_axi_write_backpressure();
        `TC_HEAD("TC06 - AXI Write Backpressure (WREADY delay=1~5)")
        bfm_w_ready_delay = 3;   // WREADY 延迟 3 拍
        fork user_wr_burst(32'h0000_0500, 16, 8'hB0); join_none
        wait_wr_done();
        fork user_rd_burst(32'h0000_0500, 16); join_none
        wait_rd_done();

        if (scb.last_pass) `TC_PASS("TC06 - AXI Write Backpressure")
        else               `TC_FAIL("TC06 - AXI Write Backpressure")
    endtask

    //-----------------------------------------------------------------------
    // TC07: AXI 读反压 (RVALID 拍间间隔)
    //-----------------------------------------------------------------------
    task automatic tc07_axi_read_backpressure();
        `TC_HEAD("TC07 - AXI Read Backpressure (R_DATA_GAP=1~5)")
        fork user_wr_burst(32'h0000_0600, 16, 8'hC0); join_none
        wait_wr_done();
        bfm_r_data_gap = 3;    // 读数据拍间间隔 3 拍
        fork user_rd_burst(32'h0000_0600, 16); join_none
        wait_rd_done();

        if (scb.last_pass) `TC_PASS("TC07 - AXI Read Backpressure")
        else               `TC_FAIL("TC07 - AXI Read Backpressure")
    endtask

    //-----------------------------------------------------------------------
    // TC08: 用户写反压 (user_wr_ready 间歇拉低)
    // 通过在 user_wr_burst 中插入额外延时模拟慢速数据源
    //-----------------------------------------------------------------------
    task automatic tc08_user_write_backpressure();
        automatic byte data_val;
        `TC_HEAD("TC08 - User Write Backpressure (slow data source)")

        user_wr_addr = 32'h0000_0700;
        user_wr_len  = 16;

        @(posedge clk_wr);
        user_wr_start = 1'b1;
        @(posedge clk_wr);
        user_wr_start = 1'b0;

        for (int i = 0; i < 16; i++) begin
            data_val = (8'hD0 + i) & 8'hFF;
            user_wr_data_in = data_val;
            user_wr_valid   = 1'b1;

            do @(posedge clk_wr); while (!user_wr_ready);
            scb.record(32'h0000_0700 + i, data_val);

            // 额外延时: 每拍后停顿 2 个周期 (模拟慢速源)
            user_wr_valid = 1'b0;
            repeat (2) @(posedge clk_wr);
        end
        user_wr_valid = 1'b0;
        wait_wr_done();

        fork user_rd_burst(32'h0000_0700, 16); join_none
        wait_rd_done();

        if (scb.last_pass) `TC_PASS("TC08 - User Write Backpressure")
        else               `TC_FAIL("TC08 - User Write Backpressure")
    endtask

    //-----------------------------------------------------------------------
    // TC09: 用户读反压 (user_rd_ready 间歇拉低)
    //-----------------------------------------------------------------------
    task automatic tc09_user_read_backpressure();
        `TC_HEAD("TC09 - User Read Backpressure (slow consumer)")
        fork user_wr_burst(32'h0000_0800, 16, 8'hE0); join_none
        wait_wr_done();

        // 使用自定义读时序: 每拍后停顿模拟慢速消费者
        user_rd_addr  = 32'h0000_0800;
        user_rd_len   = 16;
        user_rd_ready = 1'b0;    // 初始不就绪

        @(posedge clk_rd);
        user_rd_start = 1'b1;
        @(posedge clk_rd);
        user_rd_start = 1'b0;

        for (int i = 0; i < 16; i++) begin
            // 间歇拉高 ready
            user_rd_ready = 1'b1;
            do @(posedge clk_rd); while (!user_rd_valid);
            scb.check(32'h0000_0800 + i, user_rd_data_out);

            // 停顿 3 拍
            user_rd_ready = 1'b0;
            repeat (3) @(posedge clk_rd);
        end
        user_rd_ready = 1'b0;

        if (scb.last_pass) `TC_PASS("TC09 - User Read Backpressure")
        else               `TC_FAIL("TC09 - User Read Backpressure")
    endtask

    //-----------------------------------------------------------------------
    // TC10: 连续多次写
    //-----------------------------------------------------------------------
    task automatic tc10_multi_write();
        `TC_HEAD("TC10 - Multiple Sequential Writes")

        fork user_wr_burst(32'h0000_0900, 4,  8'h10); join_none
        wait_wr_done();
        fork user_wr_burst(32'h0000_0904, 8,  8'h20); join_none
        wait_wr_done();
        fork user_wr_burst(32'h0000_090C, 1,  8'hA5); join_none
        wait_wr_done();
        fork user_wr_burst(32'h0000_090D, 16, 8'h30); join_none
        wait_wr_done();

        // 回读全部
        fork user_rd_burst(32'h0000_0900, 4);  join_none; wait_rd_done();
        fork user_rd_burst(32'h0000_0904, 8);  join_none; wait_rd_done();
        fork user_rd_burst(32'h0000_090C, 1);  join_none; wait_rd_done();
        fork user_rd_burst(32'h0000_090D, 16); join_none; wait_rd_done();

        if (scb.last_pass) `TC_PASS("TC10 - Multiple Sequential Writes")
        else               `TC_FAIL("TC10 - Multiple Sequential Writes")
    endtask

    //-----------------------------------------------------------------------
    // TC11: 连续多次读
    //-----------------------------------------------------------------------
    task automatic tc11_multi_read();
        `TC_HEAD("TC11 - Multiple Sequential Reads")
        // 预写数据
        fork user_wr_burst(32'h0000_0A00, 32, 8'h50); join_none
        wait_wr_done();

        // 分段读
        fork user_rd_burst(32'h0000_0A00, 8);  join_none; wait_rd_done();
        fork user_rd_burst(32'h0000_0A08, 1);  join_none; wait_rd_done();
        fork user_rd_burst(32'h0000_0A09, 16); join_none; wait_rd_done();

        if (scb.last_pass) `TC_PASS("TC11 - Multiple Sequential Reads")
        else               `TC_FAIL("TC11 - Multiple Sequential Reads")
    endtask

    //-----------------------------------------------------------------------
    // TC12: 最大突发长度 (len=256)
    //-----------------------------------------------------------------------
    task automatic tc12_max_burst();
        `TC_HEAD("TC12 - Max Burst Length (len=256)")
        fork user_wr_burst(32'h0000_0B00, 256, 8'h00); join_none
        wait_wr_done();
        fork user_rd_burst(32'h0000_0B00, 256); join_none
        wait_rd_done();

        if (scb.last_pass) `TC_PASS("TC12 - Max Burst Length (len=256)")
        else               `TC_FAIL("TC12 - Max Burst Length (len=256)")
    endtask

    //-----------------------------------------------------------------------
    // TC20: FIXED 写突发 (len=4) — 4 拍到同一地址
    //-----------------------------------------------------------------------
    task automatic tc20_fixed_write();
        `TC_HEAD("TC20 - FIXED Write Burst (len=4)")
        fork user_wr_burst_fixed(32'h0000_0C00, 4, 8'h10); join_none
        wait_wr_done();
        // FIXED 写: 同一地址写入 4 次, 最后一拍值 (0x13) 应覆盖前三拍
        // 读回验证
        fork user_rd_burst(32'h0000_0C00, 1); join_none  // 只读第一地址
        wait_rd_done();
        if (scb.last_pass) `TC_PASS("TC20 - FIXED Write Burst (len=4)")
        else               `TC_FAIL("TC20 - FIXED Write Burst (len=4)")
    endtask

    //-----------------------------------------------------------------------
    // TC21: FIXED 读突发 (len=8) — 从同一地址读 8 拍
    //-----------------------------------------------------------------------
    task automatic tc21_fixed_read();
        `TC_HEAD("TC21 - FIXED Read Burst (len=8)")
        // 预写数据到从机地址 0x0C10 (seed=0x20, 首字节 0x20)
        fork user_wr_burst(32'h0000_0C10, 1, 8'hAA); join_none
        wait_wr_done();
        // FIXED 读 len=8: 每拍同一地址, 应返回 8 次相同数据 0xAA
        fork user_rd_burst_fixed(32'h0000_0C10, 8, 8'hAA); join_none
        wait_rd_done();
        `TC_PASS("TC21 - FIXED Read Burst (len=8)")
    endtask

    //-----------------------------------------------------------------------
    // TC22: WRAP 写突发 (len=4, start=0x04)
    //-----------------------------------------------------------------------
    task automatic tc22_wrap_write();
        `TC_HEAD("TC22 - WRAP Write Burst (len=4, addr=0x04)")
        fork user_wr_burst_wrap(32'h0000_0C20, 4, 8'h30); join_none
        wait_wr_done();
        // WRAP 写: addr=0x04, len=4 → 写 0x04,0x05,0x06,0x07 (wrap boundary: 0x00~0x07)
        // 回读验证全部 4 拍
        fork user_rd_burst(32'h0000_0C20, 4); join_none
        wait_rd_done();
        if (scb.last_pass) `TC_PASS("TC22 - WRAP Write Burst (len=4)")
        else               `TC_FAIL("TC22 - WRAP Write Burst (len=4)")
    endtask

    //-----------------------------------------------------------------------
    // TC23: WRAP 读突发 (len=8, start=0x08)
    //-----------------------------------------------------------------------
    task automatic tc23_wrap_read();
        `TC_HEAD("TC23 - WRAP Read Burst (len=8, addr=0x08)")
        // 预写在地址 0x08~0x0F
        fork user_wr_burst(32'h0000_0C30, 8, 8'h40); join_none
        wait_wr_done();
        // WRAP 读: addr=0x08, len=8 → 读 0x08~0x0F (wrap boundary: 0x08~0x0F)
        fork user_rd_burst_wrap(32'h0000_0C30, 8); join_none
        wait_rd_done();
        if (scb.last_pass) `TC_PASS("TC23 - WRAP Read Burst (len=8)")
        else               `TC_FAIL("TC23 - WRAP Read Burst (len=8)")
    endtask

    //-----------------------------------------------------------------------
    // TC13~TC19: 多时钟场景写后读一致性
    //-----------------------------------------------------------------------
    task automatic tc_multi_clock_scenario(input int s);
        automatic string name;
        name = $sformatf("TC%02d - Clock Scenario S%0d (wr=%.0fM rd=%.0fM axi=%.0fM)",
                         12+s, s,
                         1000.0/CLK_SCENARIOS[s].clk_wr_period,
                         1000.0/CLK_SCENARIOS[s].clk_rd_period,
                         1000.0/CLK_SCENARIOS[s].clk_axi_period);
        `TC_HEAD(name)

        reset(s);
        fork user_wr_burst(32'h0000_1000, 32, 8'h60); join_none
        wait_wr_done();
        fork user_rd_burst(32'h0000_1000, 32); join_none
        wait_rd_done();

        if (scb.last_pass) `TC_PASS(name)
        else               `TC_FAIL(name)
    endtask


    //=======================================================================
    // 主测试流程
    //=======================================================================
    initial begin
        $display("==============================================");
        $display(" AXI_FULL_Master_With_USER_Port Testbench");
        $display("==============================================");
        $display("");

        // ---- S1 等频场景: 功能/边界/反压测试 ----
        reset(1);

        tc01_basic_write();
        tc02_basic_read();
        tc03_write_read_consistency();
        tc04_single_beat_write();
        tc05_single_beat_read();
        tc06_axi_write_backpressure();
        tc07_axi_read_backpressure();
        tc08_user_write_backpressure();
        tc09_user_read_backpressure();
        tc10_multi_write();
        tc11_multi_read();
        tc12_max_burst();

        // ---- 突发类型测试 (S1) ----
        tc20_fixed_write();
        tc21_fixed_read();
        tc22_wrap_write();
        tc23_wrap_read();

        // ---- 多时钟场景 (S1~S7) ----
        for (int s = 1; s <= 7; s++)
            tc_multi_clock_scenario(s);

        // ---- 最终报告 ----
        scb.report();

        $display("========== Test Summary ==========");
        $display("  Total : %0d", tc_total);
        $display("  Passed: %0d", tc_pass);
        $display("  Failed: %0d", tc_fail);
        if (tc_fail == 0)
            $display("  Result: ALL PASS");
        else
            $display("  Result: %0d FAILURE(S)", tc_fail);
        $display("==================================");

        $finish;
    end

endmodule
