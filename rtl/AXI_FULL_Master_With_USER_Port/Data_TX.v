
`timescale 1ns / 1ns

module  Data_TX#(
parameter  C_M_AXI_DATA_WIDTH     = 8 ,  //数据位宽
parameter  C_M_AXI_ADDR_WIDTH     = 8 ,  //地址位宽
parameter  C_M_AXI_RD_LEN_WIDTH   = 8    //突发长度位宽
)(
// Global ports
input    wire                               clk_rd,  // 读数据时钟
input    wire                               clk_axi, // axi总线时钟
input    wire                               rst_n,

//valid、ready、data
output   wire                               rd_valid ,
output   wire [C_M_AXI_DATA_WIDTH-1 : 0]    rd_data_out,
input    wire  			                    rd_ready,

// ADDR LEN
input    wire [C_M_AXI_ADDR_WIDTH-1 : 0]    rd_addr,
input    wire [C_M_AXI_RD_LEN_WIDTH-1 : 0] 	rd_len,

// ports intr with AXI_Master
output   wire [C_M_AXI_ADDR_WIDTH-1 : 0]    rd_addr_out,
output   wire [C_M_AXI_RD_LEN_WIDTH-1 : 0] 	rd_len_out,
output   wire                               rd_fifo_full,
input    wire [C_M_AXI_DATA_WIDTH-1 : 0]    data_in,
input    wire                               data_in_vld
);

//----------------- 数据缓存 ---------------------- //
wire                        fifo_wr_en;
wire                        fifo_rd_en;
wire                        fifo_empty;
wire                        fifo_full ;

assign fifo_wr_en   =  data_in_vld;
assign fifo_rd_en   = (rd_valid & rd_ready) ;
assign rd_fifo_full =  fifo_full;

//valid
assign rd_valid = (fifo_empty == 1'b0) ? 1'b1 : 1'b0 ;

// 异步 FIFO (等效 Vivado FIFO Generator IP)
// 注意: 读侧用标准模式 (MODE=1) 而非 FWFT — FWFT 的预取/弹空依赖"读指针追平
// 同步写指针"的精确判断, 在同步时钟 (同频同相) 且背靠背连续流水场景下, 写指针
// 同步滞后 (2 拍) 会导致弹空误判与预取竞争 (读到未写入位置), 数据错位。
// 标准模式 dout 组合直读 mem[rd_ptr], 无预取/弹空: "多余弹出"只是 rd_ptr 推进
// (数据仍在 RAM), valid (empty) 滞后只造成等待, 数据不丢不错。
fifo_async #(
    .MODE       (1),           // 1=STANDARD (读侧; 见上注释)
    .DATA_WIDTH (C_M_AXI_DATA_WIDTH),
    .DEPTH      (32),
    .ADDR_WIDTH (5)
) tx_data_fifo_inst (
    .wr_clk       (clk_axi),
    .rd_clk       (clk_rd),
    .din          (data_in),
    .wr_en        (fifo_wr_en),
    .rd_en        (fifo_rd_en),
    .dout         (rd_data_out),
    .full         (fifo_full),
    .almost_full  (),
    .empty        (fifo_empty),
    .almost_empty ()
);


// ADDR LEN
assign   rd_addr_out =  rd_addr;
assign   rd_len_out  =  rd_len;

endmodule
