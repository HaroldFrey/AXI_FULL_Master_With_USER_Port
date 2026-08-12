
`timescale 1ns / 1ns

module AXI_FULL_Master_With_USER_Port #(
	parameter       C_M_TARGET_SLAVE_BASE_ADDR      =   32'h00000000    ,//读写从机的基地址。
	parameter       integer MAX_OUTSTANDING_WR      =   4               ,//写通道槽位数 (1~8, outstanding 事务数)
	parameter       integer MAX_OUTSTANDING_RD      =   4               ,//读通道槽位数 (1~8, outstanding 事务数)
	parameter       C_M_AXI_ID_WIDTH	            =   ((MAX_OUTSTANDING_WR > 1) ? $clog2(MAX_OUTSTANDING_WR) : 1),//ID信号位宽(自动适配槽位数)
	parameter       C_M_AXI_ADDR_WIDTH	            =   32              ,//读、写地址位宽。
	parameter       C_M_AXI_DATA_WIDTH	            =   8               ,//读、写数据位宽。
	parameter       C_M_AXI_WR_LEN_WIDTH            =   8               ,//写突发长度位宽
    parameter       C_M_AXI_RD_LEN_WIDTH            =   8               ,//读突发长度位宽
    parameter       C_M_AXI_AWUSER_WIDTH	        =   0               ,//用户写地址总线的宽度
	parameter       C_M_AXI_ARUSER_WIDTH	        =   0               ,//用户读地址总线的宽度。
	parameter       C_M_AXI_WUSER_WIDTH	            =   0               ,//用户写数据总线宽度。
	parameter       C_M_AXI_RUSER_WIDTH	            =   0               ,//用户读数据总线宽度。
	parameter       C_M_AXI_BUSER_WIDTH	            =   0                //用户写响应总线的宽度。
)(

    // --------------------------Gobal Singals ---------------------------//
    // Global ports
    input   wire                                        clk_wr          ,// 写数据时钟
    input   wire                                        clk_rd          ,// 读数据时钟
    input   wire                                        clk_axi         ,// axi总线时钟
    input   wire                                        rst_n           ,// 全局复位

    // --------------------------USER PORTS-------------------------------//
    input                                               user_wr_start   ,//写操作开始标志信号,每进行一次写操作拉高一次
    input                            	                user_rd_start   ,//读操作开始标志信号,每进行一次读操作拉高一次
    output                                              user_wr_ready_start,//写通道有空闲槽位(可接受新写事务)
    output                                              user_rd_ready_start,//读通道有空闲槽位(可接受新读事务)

    // intr wiyh Data_RX，use in write data
    input                                               user_wr_valid   ,//写数据有效标志信号
    input           [C_M_AXI_DATA_WIDTH-1 : 0]          user_wr_data_in ,//写数据
    output        			                            user_wr_ready   ,//写数据 ready
    input           [C_M_AXI_ADDR_WIDTH-1 : 0]          user_wr_addr    ,//突发写地址
    input           [C_M_AXI_WR_LEN_WIDTH-1 : 0] 	    user_wr_len     ,//突发写长度
    input           [1 : 0]                             user_wr_burst_type,//写突发类型: 00=FIXED 01=INCR 10=WRAP
    output                                              user_wr_error   ,//写事务错误标志
    input           [C_M_AXI_AWUSER_WIDTH-1 : 0]        user_awuser     ,//写地址 USER 信号
    input           [C_M_AXI_WUSER_WIDTH-1 : 0]         user_wuser      ,//写数据 USER 信号

    // intr wiyh Data_TX，use in read data                                          a
    output                                              user_rd_valid   ,//读数据有效标志信号
    output          [C_M_AXI_DATA_WIDTH-1 : 0]          user_rd_data_out,//读数据
    input            			                        user_rd_ready   ,//读数据 ready
    input           [C_M_AXI_ADDR_WIDTH-1 : 0]          user_rd_addr    ,//突发读地址
    input           [C_M_AXI_RD_LEN_WIDTH-1 : 0] 	    user_rd_len     ,//突发读长度
    input           [1 : 0]                             user_rd_burst_type,//读突发类型: 00=FIXED 01=INCR 10=WRAP
    output                                              user_rd_error   ,//读事务错误标志
    input           [C_M_AXI_ARUSER_WIDTH-1 : 0]        user_aruser     ,//读地址 USER 信号

    // -------------------------AXI-FULL PORTS----------------------------//
    //AXI写地址通道
	output          [C_M_AXI_ID_WIDTH-1 : 0]            M_AXI_AWID      ,//AXI写地址通道ID信号。
	output          [C_M_AXI_ADDR_WIDTH-1 : 0]          M_AXI_AWADDR    ,//AXI写地址通道地址信号。
	output          [C_M_AXI_WR_LEN_WIDTH-1 : 0]        M_AXI_AWLEN     ,//AXI写地址通道突发长度信号。
	output          [2 : 0]                             M_AXI_AWSIZE    ,//AXI写地址通道突发大小信号，该信号指示突发中每次传输的数据大小。
	output          [1 : 0]                             M_AXI_AWBURST   ,//AXI写地址通道突发类型信号。
	output                                              M_AXI_AWLOCK    ,//AXI写地址通道锁信号，只是为了兼容AXI3总线。
	output          [3 : 0]                             M_AXI_AWCACHE   ,//AXI写地址通道内存类型信号。
	output          [2 : 0]                             M_AXI_AWPROT    ,//AXI写地址通道保护类型信号。
	output          [3 : 0]                             M_AXI_AWQOS     ,//AXI写地址通道服务质量信号。
	output          [C_M_AXI_AWUSER_WIDTH-1 : 0]        M_AXI_AWUSER    ,//AXI写地址通道用户自定义信号。
	output                                              M_AXI_AWVALID   ,//AXI写地址通道有效指示信号。
	input                                               M_AXI_AWREADY   ,//AXI写地址通道地址应答信号。
    //AXI写数据通道。
	output          [C_M_AXI_DATA_WIDTH-1 : 0]          M_AXI_WDATA     ,//AXI写数据通道写数据信号。
	output          [C_M_AXI_DATA_WIDTH/8-1 : 0]        M_AXI_WSTRB     ,//AXI写数据通道写数据掩码信号。
	output                                              M_AXI_WLAST     ,//AXI写数据通道突发传输最后一个信号。
	output          [C_M_AXI_WUSER_WIDTH-1 : 0]         M_AXI_WUSER     ,//AXI写数据通道用户自定义信号。
	output                                              M_AXI_WVALID    ,//AXI写数据通道有效指示信号。
	input                                               M_AXI_WREADY    ,//AXI写数据通道数据应答信号。
    //AXI写应答通道。
	input           [C_M_AXI_ID_WIDTH-1 : 0]            M_AXI_BID       ,//AXI写响应通道响应ID信号。
	input           [1 : 0]                             M_AXI_BRESP     ,//AXI写响应通道写回复信号。
	input           [C_M_AXI_BUSER_WIDTH-1 : 0]         M_AXI_BUSER     ,//AXI写响应通道用户自定义信号。
	input                                               M_AXI_BVALID    ,//AXI写响应通道有效指示信号。
	output                                              M_AXI_BREADY    ,//AXI写响应通道主机应答信号。
    //AXI读地址通道。
	output          [C_M_AXI_ID_WIDTH-1 : 0]            M_AXI_ARID      ,//AXI读地址通道ID信号。
	output          [C_M_AXI_ADDR_WIDTH-1 : 0]          M_AXI_ARADDR    ,//AXI读地址通道读地址信号。
	output          [7 : 0]                             M_AXI_ARLEN     ,//AXI读地址通道数据突发长度信号。
	output          [2 : 0]                             M_AXI_ARSIZE    ,//AXI读地址通道突发大小信号，该信号指示突发中每次传输的数据大小。
	output          [1 : 0]                             M_AXI_ARBURST   ,//AXI读地址通道突发类型信号。
	output                                              M_AXI_ARLOCK    ,//AXI读地址通道锁信号，只是为了兼容AXI3总线。
	output          [3 : 0]                             M_AXI_ARCACHE   ,//AXI读地址通道内存类型信号。
	output          [2 : 0]                             M_AXI_ARPROT    ,//AXI读地址通道保护类型信号。
	output          [3 : 0]                             M_AXI_ARQOS     ,//AXI读地址通道服务质量信号。
	output          [C_M_AXI_ARUSER_WIDTH-1 : 0]        M_AXI_ARUSER    ,//AXI读地址通道用户自定义信号
	output                                              M_AXI_ARVALID   ,//AXI读地址通道有效指示信号。。
	input                                               M_AXI_ARREADY   ,//AXI读地址通道地址应答信号。。
    //AXI读数据通道。
	input           [C_M_AXI_ID_WIDTH-1 : 0]            M_AXI_RID       ,//AXI读数据通道ID信号。
	input           [C_M_AXI_DATA_WIDTH-1 : 0]          M_AXI_RDATA     ,//AXI读数据通道读数据信号。
	input           [1 : 0]                             M_AXI_RRESP     ,//AXI读数据通道读回复信号。
	input                                               M_AXI_RLAST     ,//AXI读数据通道突发传输最后一个信号。
	input           [C_M_AXI_RUSER_WIDTH-1 : 0]         M_AXI_RUSER     ,//AXI读数据通道用户自定义信号。
	input                                               M_AXI_RVALID    ,//AXI读数据通道有效指示信号。
	output                                              M_AXI_RREADY     //AXI读数据通道主机应答信号。
);


// Data_RX Module ports intr with AXI_Master
wire                               data_rd_en    ;
wire                               wr_fifo_empty ;
wire [C_M_AXI_ADDR_WIDTH-1 : 0]    wr_addr_out   ;
wire [C_M_AXI_WR_LEN_WIDTH-1 : 0]  wr_len_out    ;
wire [C_M_AXI_DATA_WIDTH-1 : 0]    wr_data_out   ;


// Data_TX Module ports intr with AXI_Master
wire [C_M_AXI_ADDR_WIDTH-1 : 0]    rd_addr_out  ;
wire [C_M_AXI_RD_LEN_WIDTH-1 : 0]  rd_len_out   ;
wire                               rd_fifo_full ;
wire [C_M_AXI_DATA_WIDTH-1 : 0]    data_in      ;
wire                               data_in_vld  ;

Data_TX#(
    .C_M_AXI_DATA_WIDTH     (C_M_AXI_DATA_WIDTH  ) ,  //数据位宽
    .C_M_AXI_ADDR_WIDTH     (C_M_AXI_ADDR_WIDTH  ) ,  //地址位宽
    .C_M_AXI_RD_LEN_WIDTH   (C_M_AXI_RD_LEN_WIDTH)    //突发长度位宽
)
Data_TX_inst(
    // Global ports
    .clk_rd         (clk_rd             ),  // 读数据时钟
    .clk_axi        (clk_axi            ),  // axi总线时钟
    .rst_n          (rst_n              ),

    //valid、ready、data
    .rd_valid       (user_rd_valid      ),// output   reg
    .rd_data_out    (user_rd_data_out   ),// output   reg  [C_M_AXI_DATA_WIDTH-1 : 0]
    .rd_ready       (user_rd_ready      ),// input    wire

    // ADDR LEN
    .rd_addr        (user_rd_addr       ),//input    wire [C_M_AXI_ADDR_WIDTH-1 : 0]
    .rd_len         (user_rd_len        ),//input    wire [C_M_AXI_RD_LEN_WIDTH-1 : 0]

    // ports intr with AXI_Master
    .rd_addr_out    (rd_addr_out        ),// output   wire [C_M_AXI_ADDR_WIDTH-1 : 0]
    .rd_len_out     (rd_len_out         ),// output   wire [C_M_AXI_RD_LEN_WIDTH-1 : 0]
    .rd_fifo_full   (rd_fifo_full       ),// output   wire
    .data_in        (data_in            ),// input    wire [C_M_AXI_DATA_WIDTH-1 : 0]
    .data_in_vld    (data_in_vld        ) // input    wire
);



Data_RX#(
    .C_M_AXI_DATA_WIDTH         (C_M_AXI_DATA_WIDTH    ),  //数据位宽
    .C_M_AXI_ADDR_WIDTH         (C_M_AXI_ADDR_WIDTH    ),  //地址位宽
    .C_M_AXI_WR_LEN_WIDTH       (C_M_AXI_WR_LEN_WIDTH  )   //突发长度位宽
)
Data_RX_inst(
    // Global ports
    .clk_wr                 (clk_wr              ), // 写数据时钟
    .clk_axi                (clk_axi             ), // axi总线时钟
    .rst_n                  (rst_n               ),

    //valid、ready、data
    .wr_valid               (user_wr_valid       ),// input    wire
    .wr_data_in             (user_wr_data_in     ),// input    wire [C_M_AXI_DATA_WIDTH-1 : 0]
    .wr_ready               (user_wr_ready       ),// output   wire

    // ADDR LEN DATA
    .wr_addr                (user_wr_addr        ),//input    wire [C_M_AXI_ADDR_WIDTH-1 : 0]
    .wr_len                 (user_wr_len         ),//input    wire [C_M_AXI_WR_LEN_WIDTH-1 : 0]

    // ports intr with AXI_Master
    .data_rd_en             (data_rd_en          ), //input    wire
    .wr_fifo_empty          (wr_fifo_empty       ), //output   wire
    .wr_addr_out            (wr_addr_out         ), //output   wire [C_M_AXI_ADDR_WIDTH-1 : 0]
    .wr_len_out             (wr_len_out          ), //output   wire [C_M_AXI_WR_LEN_WIDTH-1 : 0]
    .wr_data_out            (wr_data_out         )  //output   wire [C_M_AXI_DATA_WIDTH-1 : 0]
);


// ====== v2: 读写分离 —— axi_wr_master + axi_rd_master ======

axi_wr_master  #(
    .C_M_TARGET_SLAVE_BASE_ADDR ( C_M_TARGET_SLAVE_BASE_ADDR    ),
    .C_M_AXI_ID_WIDTH           ( C_M_AXI_ID_WIDTH              ),
    .C_M_AXI_ADDR_WIDTH         ( C_M_AXI_ADDR_WIDTH            ),
    .C_M_AXI_DATA_WIDTH         ( C_M_AXI_DATA_WIDTH            ),
    .C_M_AXI_WR_LEN_WIDTH       ( C_M_AXI_WR_LEN_WIDTH          ),
    .C_M_AXI_AWUSER_WIDTH       ( C_M_AXI_AWUSER_WIDTH          ),
    .C_M_AXI_WUSER_WIDTH        ( C_M_AXI_WUSER_WIDTH           ),
    .C_M_AXI_BUSER_WIDTH        ( C_M_AXI_BUSER_WIDTH           ),
    .MAX_OUTSTANDING_WR         ( MAX_OUTSTANDING_WR            )
)
axi_wr_master_inst (
    .M_AXI_ACLK                 ( clk_axi                       ),
    .M_AXI_ARESETN              ( rst_n                         ),

    .wr_start                   ( user_wr_start                 ),
    .wr_burst_type              ( user_wr_burst_type            ),
    .data_rd_en                 ( data_rd_en                    ),
    .wr_fifo_empty              ( wr_fifo_empty                 ),
    .wr_addr_in                 ( wr_addr_out                   ),
    .wr_len_in                  ( wr_len_out                    ),
    .wr_data_in                 ( wr_data_out                   ),
    .user_awuser                ( user_awuser                   ),
    .user_wuser                 ( user_wuser                    ),
    .wr_error                   ( user_wr_error                 ),
    .wr_ready_start             ( user_wr_ready_start           ),

    .M_AXI_AWID                 ( M_AXI_AWID                    ),
    .M_AXI_AWADDR               ( M_AXI_AWADDR                  ),
    .M_AXI_AWLEN                ( M_AXI_AWLEN                   ),
    .M_AXI_AWSIZE               ( M_AXI_AWSIZE                  ),
    .M_AXI_AWBURST              ( M_AXI_AWBURST                 ),
    .M_AXI_AWLOCK               ( M_AXI_AWLOCK                  ),
    .M_AXI_AWCACHE              ( M_AXI_AWCACHE                 ),
    .M_AXI_AWPROT               ( M_AXI_AWPROT                  ),
    .M_AXI_AWQOS                ( M_AXI_AWQOS                   ),
    .M_AXI_AWUSER               ( M_AXI_AWUSER                  ),
    .M_AXI_AWVALID              ( M_AXI_AWVALID                 ),
    .M_AXI_AWREADY              ( M_AXI_AWREADY                 ),

    .M_AXI_WDATA                ( M_AXI_WDATA                   ),
    .M_AXI_WSTRB                ( M_AXI_WSTRB                   ),
    .M_AXI_WLAST                ( M_AXI_WLAST                   ),
    .M_AXI_WUSER                ( M_AXI_WUSER                   ),
    .M_AXI_WVALID               ( M_AXI_WVALID                  ),
    .M_AXI_WREADY               ( M_AXI_WREADY                  ),

    .M_AXI_BID                  ( M_AXI_BID                     ),
    .M_AXI_BRESP                ( M_AXI_BRESP                   ),
    .M_AXI_BUSER                ( M_AXI_BUSER                   ),
    .M_AXI_BVALID               ( M_AXI_BVALID                  ),
    .M_AXI_BREADY               ( M_AXI_BREADY                  )
);

axi_rd_master  #(
    .C_M_TARGET_SLAVE_BASE_ADDR ( C_M_TARGET_SLAVE_BASE_ADDR    ),
    .C_M_AXI_ID_WIDTH           ( C_M_AXI_ID_WIDTH              ),
    .C_M_AXI_ADDR_WIDTH         ( C_M_AXI_ADDR_WIDTH            ),
    .C_M_AXI_DATA_WIDTH         ( C_M_AXI_DATA_WIDTH            ),
    .C_M_AXI_RD_LEN_WIDTH       ( C_M_AXI_RD_LEN_WIDTH          ),
    .C_M_AXI_ARUSER_WIDTH       ( C_M_AXI_ARUSER_WIDTH          ),
    .C_M_AXI_RUSER_WIDTH        ( C_M_AXI_RUSER_WIDTH           ),
    .MAX_OUTSTANDING_RD         ( MAX_OUTSTANDING_RD            )
)
axi_rd_master_inst (
    .M_AXI_ACLK                 ( clk_axi                       ),
    .M_AXI_ARESETN              ( rst_n                         ),

    .rd_start                   ( user_rd_start                 ),
    .rd_burst_type              ( user_rd_burst_type            ),
    .rd_addr_in                 ( rd_addr_out                   ),
    .rd_len_in                  ( rd_len_out                    ),
    .rd_fifo_full               ( rd_fifo_full                  ),
    .data_out                   ( data_in                       ),
    .data_out_vld               ( data_in_vld                   ),
    .user_aruser                ( user_aruser                   ),
    .rd_error                   ( user_rd_error                 ),
    .rd_ready_start             ( user_rd_ready_start           ),

    .M_AXI_ARID                 ( M_AXI_ARID                    ),
    .M_AXI_ARADDR               ( M_AXI_ARADDR                  ),
    .M_AXI_ARLEN                ( M_AXI_ARLEN                   ),
    .M_AXI_ARSIZE               ( M_AXI_ARSIZE                  ),
    .M_AXI_ARBURST              ( M_AXI_ARBURST                 ),
    .M_AXI_ARLOCK               ( M_AXI_ARLOCK                  ),
    .M_AXI_ARCACHE              ( M_AXI_ARCACHE                 ),
    .M_AXI_ARPROT               ( M_AXI_ARPROT                  ),
    .M_AXI_ARQOS                ( M_AXI_ARQOS                   ),
    .M_AXI_ARUSER               ( M_AXI_ARUSER                  ),
    .M_AXI_ARVALID              ( M_AXI_ARVALID                 ),
    .M_AXI_ARREADY              ( M_AXI_ARREADY                 ),

    .M_AXI_RID                  ( M_AXI_RID                     ),
    .M_AXI_RDATA                ( M_AXI_RDATA                   ),
    .M_AXI_RRESP                ( M_AXI_RRESP                   ),
    .M_AXI_RLAST                ( M_AXI_RLAST                   ),
    .M_AXI_RUSER                ( M_AXI_RUSER                   ),
    .M_AXI_RVALID               ( M_AXI_RVALID                  ),
    .M_AXI_RREADY               ( M_AXI_RREADY                  )
);



endmodule
