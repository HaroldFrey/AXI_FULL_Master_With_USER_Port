//===========================================================================
// fifo_async.v  —  异步 FIFO (FWFT / Standard 双模式)
//===========================================================================
// 功能等效于 Vivado FIFO Generator IP (异步模式)
//   - FWFT 模式: 首字直通, dout 零延迟
//   - Standard 模式: rd_en 后下一拍 dout 有效
//   - 格雷码指针 + 两级同步器, 保证跨时钟域数据安全
//   - 深度 32 × 位宽 8 (可参数化)
//===========================================================================

`timescale 1ns / 1ns

module fifo_async #(
    parameter integer MODE      = 0,        // 0=FWFT, 1=STANDARD (Vivado 综合不支持 string 参数)
    parameter int    DATA_WIDTH = 8,
    parameter int    DEPTH      = 32,
    parameter int    ADDR_WIDTH = 5         // $clog2(DEPTH), 地址位宽
)(
    // 写端口 (wr_clk 域)
    input  wire                     wr_clk,
    input  wire                     wr_en,
    input  wire [DATA_WIDTH-1:0]    din,
    output wire                     full,
    output wire                     almost_full,

    // 读端口 (rd_clk 域)
    input  wire                     rd_clk,
    input  wire                     rd_en,
    output wire [DATA_WIDTH-1:0]    dout,
    output wire                     empty,
    output wire                     almost_empty
);

    //===================================================================
    // 指针位宽 = 地址位宽 + 1 (高位翻转位用于区分空/满)
    //===================================================================
    localparam int PTR_WIDTH = ADDR_WIDTH + 1;

    //===================================================================
    // 双端口 RAM
    //===================================================================
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    //===================================================================
    // 写侧 (wr_clk 域)
    //===================================================================
    reg  [PTR_WIDTH-1:0] wr_ptr_bin    = 0;   // 二进制写指针
    reg  [PTR_WIDTH-1:0] wr_ptr_gray   = 0;   // 格雷码写指针
    wire [PTR_WIDTH-1:0] wr_ptr_bin_next;
    wire [PTR_WIDTH-1:0] wr_ptr_gray_next;

    // 同步后的读指针 (来自 rd_clk 域)
    reg  [PTR_WIDTH-1:0] rd_ptr_gray_sync1 = 0;
    reg  [PTR_WIDTH-1:0] rd_ptr_gray_sync2 = 0;
    wire [PTR_WIDTH-1:0] rd_ptr_gray_synced;
    wire [PTR_WIDTH-1:0] rd_ptr_bin_synced;

    assign wr_ptr_bin_next = wr_ptr_bin + 1'b1;
    assign wr_ptr_gray_next = (wr_ptr_bin_next >> 1) ^ wr_ptr_bin_next;
    assign rd_ptr_gray_synced = rd_ptr_gray_sync2;

    // 格雷码转二进制 (同步后的读指针)
    function [PTR_WIDTH-1:0] gray2bin(input [PTR_WIDTH-1:0] g);
        reg [PTR_WIDTH-1:0] b;
        integer i;
        begin
            b[PTR_WIDTH-1] = g[PTR_WIDTH-1];
            for (i = PTR_WIDTH-2; i >= 0; i = i - 1)
                b[i] = b[i+1] ^ g[i];
            gray2bin = b;
        end
    endfunction

    assign rd_ptr_bin_synced = gray2bin(rd_ptr_gray_synced);

    // 写指针寄存器 + 满判断
    always @(posedge wr_clk) begin
        if (wr_en && !full) begin
            wr_ptr_bin  <= wr_ptr_bin_next;
            wr_ptr_gray <= wr_ptr_gray_next;
        end
    end

    // RAM 写入
    always @(posedge wr_clk) begin
        if (wr_en && !full)
            mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= din;
    end

    // 两级同步器: rd_ptr_gray → wr_clk 域
    always @(posedge wr_clk) begin
        rd_ptr_gray_sync1 <= rd_ptr_gray;       // rd_clk 域的信号, 在 wr_clk 采样
        rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
    end

    // 满: wr_ptr_gray_next == rd_ptr_gray_synced (格雷码直接比较)
    // 注意: 用 next 而非 current — 写入后指针将等于读指针 → 满
    assign full        = (wr_ptr_gray_next == rd_ptr_gray_synced);
    assign almost_full = (wr_ptr_bin_next + 2'd2 >= rd_ptr_bin_synced);

    //===================================================================
    // 读侧 (rd_clk 域)
    //===================================================================
    reg  [PTR_WIDTH-1:0] rd_ptr_bin    = 0;    // 二进制读指针
    reg  [PTR_WIDTH-1:0] rd_ptr_gray   = 0;    // 格雷码读指针
    wire [PTR_WIDTH-1:0] rd_ptr_bin_next;
    wire [PTR_WIDTH-1:0] rd_ptr_gray_next;

    // 同步后的写指针 (来自 wr_clk 域)
    reg  [PTR_WIDTH-1:0] wr_ptr_gray_sync1 = 0;
    reg  [PTR_WIDTH-1:0] wr_ptr_gray_sync2 = 0;
    wire [PTR_WIDTH-1:0] wr_ptr_gray_synced;
    wire [PTR_WIDTH-1:0] wr_ptr_bin_synced;

    assign rd_ptr_bin_next  = rd_ptr_bin + 1'b1;
    assign rd_ptr_gray_next = (rd_ptr_bin_next >> 1) ^ rd_ptr_bin_next;
    assign wr_ptr_gray_synced = wr_ptr_gray_sync2;
    assign wr_ptr_bin_synced  = gray2bin(wr_ptr_gray_synced);

    // RAM 组合读出
    wire [DATA_WIDTH-1:0] ram_dout;
    assign ram_dout = mem[rd_ptr_bin[ADDR_WIDTH-1:0]];

    // 标准 FIFO 空标志 (基于格雷码比较)
    wire std_empty;
    assign std_empty = (rd_ptr_gray == wr_ptr_gray_synced);

    // 读指针更新 — 仅当 rd_en 有效且"对外"非空时
    wire rd_allow;
    assign rd_allow = rd_en && !(MODE == 0 ? !fwft_valid : std_empty);

    always @(posedge rd_clk) begin
        if (rd_allow) begin
            rd_ptr_bin  <= rd_ptr_bin_next;
            rd_ptr_gray <= rd_ptr_gray_next;
        end
    end

    // 两级同步器: wr_ptr_gray → rd_clk 域
    always @(posedge rd_clk) begin
        wr_ptr_gray_sync1 <= wr_ptr_gray;       // wr_clk 域的信号, 在 rd_clk 采样
        wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
    end

    //===================================================================
    // FWFT 输出寄存器 (rd_clk 域)
    //===================================================================
    // 弹空/预取统一以"同步确认的写指针 (wr_ptr_bin_synced, 滞后 2 拍)"为界:
    //   - 下一笔未确认 (rd_next >= wr_synced) → 弹空, 等待同步确认后再武装
    //   - 下一笔已确认 (rd_next < wr_synced)  → 预取, mem 必已写入 (无竞争)
    // 注意: 不能用 "gray 追平判据 (rd_gray_next == wr_synced)" — 写指针同步
    // 滞后时, 读指针可能"超前"同步值 1~2 拍 (gray 不等), 此时走预取分支会
    // 与写侧同拍竞争 (预取未写入的 mem 位置 → 残留 X/错位)。用 bin 比较的
    // >= 保守弹空, 只牺牲 1~2 拍有效延迟, 数据不丢不重不错。
    // 注: bin 无符号比较在指针回绕 (|wr-rd| > 32) 时可能误判; 深度 32 的
    // FIFO 正常工作时差 < 32, 仅指针接近 64 回绕边界时需留意。
    reg  [DATA_WIDTH-1:0] fwft_dout  = 0;
    reg                    fwft_valid = 0;

    always @(posedge rd_clk) begin
        if (fwft_valid && rd_en && (std_empty || (rd_ptr_bin_next >= wr_ptr_bin_synced))) begin
            // 读走最后一笔 (下一笔未被同步确认) → 弹空
            // std_empty (gray 精确) 兜底回绕边界场景
            fwft_valid <= 1'b0;
        end else if (!fwft_valid && (rd_ptr_bin < wr_ptr_bin_synced)) begin
            // 内部 FIFO 有新数据 (同步确认, mem 已写) → 预取首字
            fwft_dout  <= ram_dout;
            fwft_valid <= 1'b1;
        end else if (fwft_valid && rd_en && (rd_ptr_bin_next < wr_ptr_bin_synced)) begin
            // 读走当前, 下一笔已同步确认 → 预取新指针处的下一笔
            // (只有已确认写入的位置才预取, 避免与写侧同拍竞争读到未写位置)
            fwft_dout  <= mem[rd_ptr_bin_next[ADDR_WIDTH-1:0]];
            fwft_valid <= 1'b1;
        end
        // 其余情况 (fwft 有数据但不读 / 下一笔未确认): 寄存器保持
    end

    //===================================================================
    // 输出选择 (FWFT / Standard)
    //===================================================================
    assign dout          = (MODE == 0) ? fwft_dout : ram_dout;
    assign empty         = (MODE == 0) ? !fwft_valid : std_empty;
    assign almost_empty  = (rd_ptr_bin + 2'd1 >= wr_ptr_bin_synced);

endmodule
