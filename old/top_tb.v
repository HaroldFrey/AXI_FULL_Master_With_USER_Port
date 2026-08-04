`timescale 1ns / 1ns

module top_tb();
parameter	CYCLE		=   10              ;//时钟周期，单位ns,默认10ns，100MHz频率
parameter	RST_TIME	=   10              ;//系统复位持续时间，默认10个时钟周期；
parameter   DATA_WIDTH  =   8               ;//数据位宽  
	
//时钟复位信号；
reg                         clk_axi;
reg                         clk_rd;
reg                         clk_wr;
reg                         rst_n;

reg                         read_start;
reg                         write_start;

wire    [DATA_WIDTH-1:0]    read_data_out;
wire                        read_data_out_vld;

///////////////////////////////////////////////////////////
// 合计七种情况 时钟频率情况

// 情况1：写时钟=读时钟=AXI时钟
//WR时钟;
initial begin
    clk_wr = 0;
    forever #(CYCLE) clk_wr = ~clk_wr; //100MHZ
end

//RD时钟;
initial begin
    clk_rd = 0;
    forever #(CYCLE) clk_rd = ~clk_rd; //100MHZ
end

//AXI时钟;
initial begin
    clk_axi = 0;
    forever #(CYCLE) clk_axi = ~clk_axi; // 100MHZ
end


// 情况2：写时钟最快，其次读时钟，AXI时钟最慢
/* //WR时钟;
initial begin
    clk_wr = 0;
    forever #(CYCLE/3) clk_wr = ~clk_wr; // 300MHZ
end

//RD时钟;
initial begin
    clk_rd = 0;
    forever #(CYCLE/2) clk_rd = ~clk_rd; // 200MHZ
end

//AXI时钟;
initial begin
    clk_axi = 0;
    forever #(CYCLE) clk_axi = ~clk_axi; // 100MHZ
end */


// 情况3：写时钟最快，其次AXI时钟，读时钟最慢
//WR时钟;
/* initial begin
    clk_wr = 0;
    forever #(CYCLE/3) clk_wr = ~clk_wr; // 300MHZ
end

//RD时钟;
initial begin
    clk_rd = 0;
    forever #(CYCLE) clk_rd = ~clk_rd; // 100MHZ
end

//AXI时钟;
initial begin
    clk_axi = 0;
    forever #(CYCLE/2) clk_axi = ~clk_axi; // 200MHZ
end
 */

// 情况4：读时钟最快，其次写时钟，AXI时钟最慢
/* //WR时钟;
initial begin
    clk_wr = 0;
    forever #(CYCLE/2) clk_wr = ~clk_wr; // 200MHZ
end

//RD时钟;
initial begin
    clk_rd = 0;
    forever #(CYCLE/3) clk_rd = ~clk_rd; // 300MHZ
end

//AXI时钟;
initial begin
    clk_axi = 0;
    forever #(CYCLE) clk_axi = ~clk_axi; // 100MHZ
end
 */

// 情况5：读时钟最快，其次AXI时钟，写时钟最慢
/* //WR时钟;
initial begin
    clk_wr = 0;
    forever #(CYCLE) clk_wr = ~clk_wr; // 100MHZ
end

//RD时钟;
initial begin
    clk_rd = 0;
    forever #(CYCLE/3) clk_rd = ~clk_rd; // 300MHZ
end

//AXI时钟;
initial begin
    clk_axi = 0;
    forever #(CYCLE/2) clk_axi = ~clk_axi; // 200MHZ
end */


// 情况6：AXI时钟最快，其次写时钟，读时钟最慢
/* //WR时钟;
initial begin
    clk_wr = 0;
    forever #(CYCLE/2) clk_wr = ~clk_wr; // 200MHZ
end

//RD时钟;
initial begin
    clk_rd = 0;
    forever #(CYCLE) clk_rd = ~clk_rd; // 100MHZ
end

//AXI时钟;
initial begin
    clk_axi = 0;
    forever #(CYCLE/3) clk_axi = ~clk_axi; // 300MHZ
end */


// 情况7：AXI时钟最快，其次读时钟，写时钟最慢
/* //WR时钟;
initial begin
    clk_wr = 0;
    forever #(CYCLE) clk_wr = ~clk_wr; // 100MHZ
end

//RD时钟;
initial begin
    clk_rd = 0;
    forever #(CYCLE/2) clk_rd = ~clk_rd; // 200MHZ
end

//AXI时钟;
initial begin
    clk_axi = 0;
    forever #(CYCLE/3) clk_axi = ~clk_axi; // 300MHZ
end */
///////////////////////////////////////////////////////////


//生成复位信号；
initial begin
    rst_n = 1;
    #30;
    rst_n = 0;//开始时复位10个时钟；
    #(RST_TIME*CYCLE);
    rst_n = 1;
end


//生成开始标志信号
initial begin
    write_start = 0;
    read_start  = 0;
    #300;
    write_start = 1; // 写开始
    read_start  = 0;
    #(CYCLE);
    write_start = 0;
    read_start  = 0;
    #3000;
    write_start = 0; 
    read_start  = 1; // 读开始
    #(CYCLE);
    write_start = 0;    
    read_start  = 0;
end


design_1_wrapper    design_1_wrapper_inst(
.clk_axi               (clk_axi            ),
.clk_rd                (clk_rd             ),
.clk_wr                (clk_wr             ),
.read_data_out         (read_data_out      ),
.read_data_out_vld     (read_data_out_vld  ),
.read_start            (read_start         ),
.rst_n                 (rst_n              ),
.write_start           (write_start        )
);
    
   
endmodule

