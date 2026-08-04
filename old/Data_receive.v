

`timescale 1ns / 1ns

module  Data_receive#(
parameter  RD_ADDR                = 0 ,  //读地址
parameter  RD_LEN                 = 16,  //读突发长度
parameter  ADDR_WIDTH             = 8 ,  //地址位宽 
parameter  RD_LEN_WIDTH           = 8 ,  //突发长度位宽
parameter  DATA_WIDTH             = 8    //数据位宽  
)(
// Global ports
input    wire                               clk_re,
input    wire                               rst_n,
input    wire                               work_start,
       
output   wire [DATA_WIDTH-1 : 0]            re_data_out, 
output   wire                               re_data_out_vld,                                      
        
//valid、ready、data      
input    wire                               re_valid ,
input    wire [DATA_WIDTH-1 : 0]            re_data_in,
output   wire  			                    re_ready, 
        
output   wire [ADDR_WIDTH-1 : 0]            rd_addr,
output   wire [RD_LEN_WIDTH-1 : 0]          rd_len,
output   wire                               rd_start
);


reg work_flag ;
always@(posedge clk_re) begin
    if(rst_n == 1'b0) begin
		work_flag <= 1'b0;
    end
    else if((re_cnt == rd_len -1) & (re_valid & re_ready)) begin  // 握手建立，且数据更新到最大值，清零
        work_flag <= 1'b0;
    end
    else if(work_start) begin  // 模块开始工作标志信号，拉高work_flag，处于读数据状态
        work_flag <= 1'b1;
    end
    else begin
        work_flag <= work_flag; // 保持不变
    end
end
   

reg [32:0]  re_cnt ;
always@(posedge clk_re) begin
    if(rst_n == 1'b0) begin
		re_cnt <= 32'd0;
    end
    else if((re_cnt == rd_len -1) & (re_valid & re_ready)) begin  // 握手建立，且数据更新到最大值，清零
        re_cnt <= 32'd0;
    end
    else if(re_valid & re_ready) begin  // 握手建立,+1
        re_cnt <= re_cnt + 1'b1;
    end
    else begin
        re_cnt <= re_cnt; // 保持不变
    end
end

assign re_ready = work_flag ;
assign rd_addr  = RD_ADDR   ;
assign rd_len   = RD_LEN    ;

assign re_data_out      = (work_flag & (re_valid & re_ready)) ? re_data_in : {DATA_WIDTH{1'b0}} ;
assign re_data_out_vld  = (work_flag & (re_valid & re_ready)) ? 1'b1       : 1'b0 ;

assign rd_start         = work_start;
 
endmodule


