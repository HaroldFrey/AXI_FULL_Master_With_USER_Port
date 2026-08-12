//===========================================================================
// tb_pkg.sv  —  公共参数、类型定义、时钟场景配置、Scoreboard
//===========================================================================

package tb_pkg;

    //=======================================================================
    // 时钟场景定义
    //=======================================================================
    typedef struct {
        real clk_wr_period;      // 写时钟周期 (ns)
        real clk_rd_period;      // 读时钟周期 (ns)
        real clk_axi_period;     // AXI 总线时钟周期 (ns)
    } clk_scenario_t;

    // 7 种时钟场景 (wr / rd / axi)
    localparam clk_scenario_t CLK_SCENARIOS[1:7] = '{
        '{10.0, 10.0, 10.0},    // S1: 100M / 100M / 100M  (等频)
        '{3.33, 5.0,  10.0},    // S2: 300M / 200M / 100M  (写最快,AXI最慢)
        '{3.33, 10.0, 5.0 },    // S3: 300M / 100M / 200M  (写最快,读最慢)
        '{5.0,  3.33, 10.0},    // S4: 200M / 300M / 100M  (读最快,AXI最慢)
        '{10.0, 3.33, 5.0 },    // S5: 100M / 300M / 200M  (读最快,写最慢)
        '{5.0,  10.0, 3.33},    // S6: 200M / 100M / 300M  (AXI最快,读最慢)
        '{10.0, 5.0,  3.33}     // S7: 100M / 200M / 300M  (AXI最快,写最慢)
    };

    // 运行时可变时钟周期 (通过 hierarchy 访问或 import 使用)
    real clk_wr_period  = 10.0;
    real clk_rd_period  = 10.0;
    real clk_axi_period = 10.0;

    //=======================================================================
    // DUT 参数常量
    //=======================================================================
    localparam int DUT_ADDR_WIDTH    = 32;
    localparam int DUT_DATA_WIDTH    = 8;
    localparam int DUT_WR_LEN_WIDTH  = 8;
    localparam int DUT_RD_LEN_WIDTH  = 8;
    localparam int DUT_ID_WIDTH      = 1;
    localparam int DUT_BASE_ADDR     = 32'h0000_0000;
    localparam int DUT_AWUSER_WIDTH  = 0;
    localparam int DUT_WUSER_WIDTH   = 0;
    localparam int DUT_ARUSER_WIDTH  = 0;

    //=======================================================================
    // 超时保护
    //=======================================================================
    localparam int TIMEOUT_CYCLES = 100000;

    //=======================================================================
    // AXI Slave BFM 默认延迟
    //=======================================================================
    localparam int BFM_AW_READY_DELAY = 0;
    localparam int BFM_W_READY_DELAY  = 0;
    localparam int BFM_B_VALID_DELAY  = 0;
    localparam int BFM_AR_READY_DELAY = 0;
    localparam int BFM_R_VALID_DELAY  = 1;
    localparam int BFM_R_DATA_GAP     = 0;

    //=======================================================================
    // Scoreboard
    //=======================================================================
    class scoreboard;
        byte    expected[logic [31:0]];  // 地址 → 期望数据
        int     checked = 0;             // 已检查拍数
        int     errors  = 0;             // 错误拍数
        bit     last_pass;               // 最近一次检查结果

        // 记录一次写操作的数据
        function void record(input logic [31:0] addr, input byte data);
            expected[addr] = data;
        endfunction

        // 检查一次读操作的数据
        function automatic void check(input logic [31:0] addr, input byte actual);
            checked++;
            if (!expected.exists(addr)) begin
                $error("[SCB] ERROR @ addr=0x%08h: no expected data", addr);
                errors++;
                last_pass = 1'b0;
            end else if (expected[addr] !== actual) begin
                $error("[SCB] ERROR @ addr=0x%08h: exp=0x%02h, got=0x%02h",
                       addr, expected[addr], actual);
                errors++;
                last_pass = 1'b0;
            end else begin
                last_pass = 1'b1;
            end
        endfunction

        // 打印最终报告
        function void report();
            $display("");
            $display("========== Scoreboard Report ==========");
            $display("  Total checked : %0d", checked);
            $display("  Total errors  : %0d", errors);
            if (errors == 0)
                $display("  Result        : ALL PASS");
            else
                $display("  Result        : %0d FAILURE(S)", errors);
            $display("========================================");
            $display("");
        endfunction
    endclass

endpackage
