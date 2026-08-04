
`timescale 1ns / 1ns

module  Data_send#( 
parameter  WR_ADDR        = 0  ,  //写地址
parameter  WR_LEN         = 16 ,  //写突发长度
parameter  ADDR_WIDTH     = 8  ,  //地址位宽 
parameter  WR_LEN_WIDTH   = 8  ,  //突发长度位宽
parameter  DATA_MAX       = 16 ,  //数据最大值
parameter  DATA_WIDTH     = 8     //数据位宽  
)(
// Global ports
input  wire                               clk_se,
input  wire                               rst_n,
input  wire                               work_start, // 模块开始工作标志信号

// ADDR LEN DATA
output wire [ADDR_WIDTH-1 : 0]            wr_addr,
output wire [WR_LEN_WIDTH-1 : 0]          wr_len,
output wire                               wr_start,

//valid、ready、data
output wire                               valid ,
output reg  [DATA_WIDTH-1 : 0]            data_out,
input  wire  			                  ready 
);

reg  work_flag ; // 工作标志有效信号，为高，表示数据有效
always@(posedge clk_se) begin
    if(rst_n == 1'b0) begin
		work_flag <= 1'b0;
    end
    else if((valid & ready) & (data_out == DATA_MAX -1)) begin  // 握手建立，且数据更新到最大值，清零
        work_flag <= 1'b0;
    end
    else if(work_start) begin  // 模块开始工作标志信号，拉高work_flag，开始更新数据
        work_flag <= 1'b1;
    end
    else begin
        work_flag <= work_flag; // 保持不变
    end
end
   
assign valid = work_flag ;  // 工作标志信号有效期间，数据为有效数据 

always@(posedge clk_se) begin
    if(rst_n == 1'b0) begin
		data_out <= {DATA_WIDTH{1'b0}};
    end
    else if(work_flag) begin//工作标志信号有效期间，更新数据 
        if((valid & ready) & (data_out == DATA_MAX)) begin 
            data_out <= {DATA_WIDTH{1'b0}}; // 握手建立，且数据更新到最大值，清零
        end                                 // {DATA_WIDTH{1'b0} 含义为 将 1’b0 复制DATA_WIDTH份
        else if(valid & ready) begin
            data_out <= data_out + 1'b1 ; // 握手建立，数据更新
        end
        else begin
            data_out <= data_out ; // 握手未建立，保持不变，不进行数据更新
        end
    end
    else begin
        data_out <= {DATA_WIDTH{1'b0}}; // 不处于工作状态，数据清零
    end
end

assign wr_addr  = WR_ADDR ;
assign wr_len   = WR_LEN  ;

assign wr_start =  work_start;

endmodule