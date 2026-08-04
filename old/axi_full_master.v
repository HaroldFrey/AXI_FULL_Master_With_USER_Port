
// 第一版功能：
// 时间 2025-05-04
// 可以正常突发读/写
// 读写数据过程中均可以进行数据反压
// 采用状态机实现

// 后续扩展：支持读写同时进行,支持多种突发模式，支持Outstanding、Out of order

// 突发类型：
// 2’b00 FIXED： 突发传输过程中地址固定，用于FIFO访问
// 2’b01 INCR ： 增量突发,传输过程中，地址递增。增加量取决 AxSIZE 的值。
// 2’b10 WRAP ： 回环突发,和增量突发类似，但会在特定高地址的边界处回到低地址处。
//               回环突发的长度只能是 2,4,8,16 次传输，传输首地址和每次传输的大小对齐。 
//               最低的地址整个传输的数据大小对齐。回环边界等于（AxSIZE*AxLEN）
// 2’b11 Reserved


`timescale 1ns / 1ns

module axi_full_master #(
	parameter       C_M_TARGET_SLAVE_BASE_ADDR      =   32'h00000000    ,//读写从机的基地址。根据Address Editor的地址空间划分来添加
	parameter       C_M_AXI_ID_WIDTH	            =   1               ,//ID信号位宽。
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
    input                                               M_AXI_ACLK      ,//AXI时钟信号。
	input                                               M_AXI_ARESETN   ,//AXI复位信号，默认低电平有效。

    // --------------------------USER PORTS-------------------------------//
    input   wire                                        wr_start        ,//写操作开始标志信号,每进行一次写操作拉高一次
    input   wire                      	                rd_start        ,//读操作开始标志信号,每进行一次读操作拉高一次
    // intr wiyh Data_RX，use in write data
    output  wire                                        data_rd_en      ,//FIFO读数据使能
    input   wire                                        wr_fifo_empty   ,//wr fifo空标志信号
    input   wire    [C_M_AXI_ADDR_WIDTH-1 : 0]          wr_addr_in      ,//突发写地址
    input   wire    [C_M_AXI_WR_LEN_WIDTH-1 : 0] 	    wr_len_in       ,//突发写长度
    input   wire    [C_M_AXI_DATA_WIDTH-1 : 0]          wr_data_in      ,//写数据
    input   wire                                        wr_data_vld     ,//写数据有效标志信号                                                                    
    // intr wiyh Data_TX，use in read data                                                 
    input   wire    [C_M_AXI_ADDR_WIDTH-1 : 0]          rd_addr_in      ,//突发读地址
    input   wire    [C_M_AXI_RD_LEN_WIDTH-1 : 0] 	    rd_len_in       ,//突发读长度
    input   wire                                        rd_fifo_full    ,//读FIFO 满标志信号，如果读FIFO已经满，则AXI端口暂停读取从机数据
    output  wire    [C_M_AXI_DATA_WIDTH-1 : 0]          data_out        ,//输出读数据
    output  wire                                        data_out_vld    ,//输出读数据有效标志信号

    // -------------------------AXI-FULL PORTS----------------------------//
    //AXI写地址通道
	output          [C_M_AXI_ID_WIDTH-1 : 0]            M_AXI_AWID      ,//AXI写地址通道ID信号。
	output  reg     [C_M_AXI_ADDR_WIDTH-1 : 0]          M_AXI_AWADDR    ,//AXI写地址通道地址信号。
	output          [C_M_AXI_WR_LEN_WIDTH-1 : 0]        M_AXI_AWLEN     ,//AXI写地址通道突发长度信号。
	output          [2 : 0]                             M_AXI_AWSIZE    ,//AXI写地址通道突发大小信号，该信号指示突发中每次传输的数据大小。
	output          [1 : 0]                             M_AXI_AWBURST   ,//AXI写地址通道突发类型信号。
	output                                              M_AXI_AWLOCK    ,//AXI写地址通道锁信号，只是为了兼容AXI3总线。
	output          [3 : 0]                             M_AXI_AWCACHE   ,//AXI写地址通道内存类型信号。
	output          [2 : 0]                             M_AXI_AWPROT    ,//AXI写地址通道保护类型信号。
	output          [3 : 0]                             M_AXI_AWQOS     ,//AXI写地址通道服务质量信号。
	output          [C_M_AXI_AWUSER_WIDTH-1 : 0]        M_AXI_AWUSER    ,//AXI写地址通道用户自定义信号。
	output  reg                                         M_AXI_AWVALID   ,//AXI写地址通道有效指示信号。
	input                                               M_AXI_AWREADY   ,//AXI写地址通道地址应答信号。
    //AXI写数据通道。
	output  wire    [C_M_AXI_DATA_WIDTH-1 : 0]          M_AXI_WDATA     ,//AXI写数据通道写数据信号。
	output          [C_M_AXI_DATA_WIDTH/8-1 : 0]        M_AXI_WSTRB     ,//AXI写数据通道写数据掩码信号。
	output  reg                                         M_AXI_WLAST     ,//AXI写数据通道突发传输最后一个信号。
	output          [C_M_AXI_WUSER_WIDTH-1 : 0]         M_AXI_WUSER     ,//AXI写数据通道用户自定义信号。
	output  reg                                         M_AXI_WVALID    ,//AXI写数据通道有效指示信号。
	input                                               M_AXI_WREADY    ,//AXI写数据通道数据应答信号。
    //AXI写应答通道。
	input           [C_M_AXI_ID_WIDTH-1 : 0]            M_AXI_BID       ,//AXI写响应通道响应ID信号。
	input           [1 : 0]                             M_AXI_BRESP     ,//AXI写响应通道写回复信号。
	input           [C_M_AXI_BUSER_WIDTH-1 : 0]         M_AXI_BUSER     ,//AXI写响应通道用户自定义信号。
	input                                               M_AXI_BVALID    ,//AXI写响应通道有效指示信号。
	output  reg                                         M_AXI_BREADY    ,//AXI写响应通道主机应答信号。
    //AXI读地址通道。
	output          [C_M_AXI_ID_WIDTH-1 : 0]            M_AXI_ARID      ,//AXI读地址通道ID信号。
	output  reg     [C_M_AXI_ADDR_WIDTH-1 : 0]          M_AXI_ARADDR    ,//AXI读地址通道读地址信号。
	output          [7 : 0]                             M_AXI_ARLEN     ,//AXI读地址通道数据突发长度信号。
	output          [2 : 0]                             M_AXI_ARSIZE    ,//AXI读地址通道突发大小信号，该信号指示突发中每次传输的数据大小。
	output          [1 : 0]                             M_AXI_ARBURST   ,//AXI读地址通道突发类型信号。
	output                                              M_AXI_ARLOCK    ,//AXI读地址通道锁信号，只是为了兼容AXI3总线。
	output          [3 : 0]                             M_AXI_ARCACHE   ,//AXI读地址通道内存类型信号。
	output          [2 : 0]                             M_AXI_ARPROT    ,//AXI读地址通道保护类型信号。
	output          [3 : 0]                             M_AXI_ARQOS     ,//AXI读地址通道服务质量信号。
	output          [C_M_AXI_ARUSER_WIDTH-1 : 0]        M_AXI_ARUSER    ,//AXI读地址通道用户自定义信号
	output  reg                                         M_AXI_ARVALID   ,//AXI读地址通道有效指示信号。。
	input                                               M_AXI_ARREADY   ,//AXI读地址通道地址应答信号。。
    //AXI读数据通道。
	input           [C_M_AXI_ID_WIDTH-1 : 0]            M_AXI_RID       ,//AXI读数据通道ID信号。
	input           [C_M_AXI_DATA_WIDTH-1 : 0]          M_AXI_RDATA     ,//AXI读数据通道读数据信号。
	input           [1 : 0]                             M_AXI_RRESP     ,//AXI读数据通道读回复信号。
	input                                               M_AXI_RLAST     ,//AXI读数据通道突发传输最后一个信号。
	input           [C_M_AXI_RUSER_WIDTH-1 : 0]         M_AXI_RUSER     ,//AXI读数据通道用户自定义信号。
	input                                               M_AXI_RVALID    ,//AXI读数据通道有效指示信号。
	output  reg                                         M_AXI_RREADY     //AXI读数据通道主机应答信号。
);

//------------------------------- AXI CTRL----------------------------------//
    //Four-stage state machine;
    localparam 	    IDLE        =       3'b001         ;//状态机的空闲状态编码；localparam 的值必须在编译时确定
    localparam 	    WRITE       =       3'b010         ;//状态机的写数据状态编码；
    localparam 	    READ        =       3'b100         ;//状态机的读数据状态编码；
    localparam      SIZE        =       clogb2(C_M_AXI_DATA_WIDTH/8-1  );//计算突发数据位宽的字节数。
   
    //parameter       WR_CNT_W    =       clogb2(wr_len_in - 1);//通过突发长度计算计数器位宽.
    //parameter       RD_CNT_W    =       clogb2(rd_len_in - 1);//通过突发长度计算计数器位宽.

    //自动计算位宽函数。
    function integer clogb2(input integer depth);begin
        if(depth == 0)
            clogb2 = 0;
        else if(depth != 0)
            for(clogb2=0 ; depth>0 ; clogb2=clogb2+1)
                depth=depth >> 1;
        end
    endfunction

    reg             [2 : 0]	           state      ;//状态机
    reg             [31: 0]            wr_cnt     ;//写数据个数计数
    reg             [31: 0]            rd_cnt     ;//读数据个数计数

    // 锁存突发长度，防止传输过程中外部信号变化导致异常
    reg [C_M_AXI_WR_LEN_WIDTH-1 : 0]   wr_len_latched;
    reg [C_M_AXI_RD_LEN_WIDTH-1 : 0]   rd_len_latched;
  
  
    wire            [1:0]              state_flag ; // 10,表示写开始， 01表示读开始
    
    assign state_flag = {wr_start,rd_start};

    //在 start 脉冲时锁存突发长度，保证传输期间长度值稳定
    always@(posedge M_AXI_ACLK) begin
        if(wr_start)
            wr_len_latched <= wr_len_in;
        if(rd_start)
            rd_len_latched <= rd_len_in;
    end

    always@(posedge M_AXI_ACLK)
        if(M_AXI_ARESETN == 1'b0) begin
            state <= IDLE ;
            wr_len_latched <= 0;
            rd_len_latched <= 0;
        end
        else	case(state) 
            IDLE :  //跳转到写数据状态；
                if(state_flag == 2'b10) 
                    state <= WRITE;
                
                else   if(state_flag == 2'b01) 
                    state <= READ;
                
                else 
                    state <= IDLE;
                        
            WRITE : 
                if(M_AXI_BVALID & M_AXI_BREADY)//写数据完成，跳转到IDLE状态；
                    state <= IDLE;
                
                else 
                    state <= WRITE;
                    
            READ : 
                if(M_AXI_RLAST && M_AXI_RVALID)//读突发完成，跳转到空闲状态。
                    state <= IDLE;
                
                else 
                    state <= READ;
                    
            default:  
                state <= IDLE;
            endcase
            
//------------------------------- AXI WRITE----------------------------------//
    // -----------USER PORTS------------
    assign data_rd_en = ((M_AXI_WVALID & M_AXI_WREADY) & (wr_fifo_empty == 1'b0))? 1'b1 : 1'b0;

    //------------AXI FORTS ------------
    assign M_AXI_AWID    = 0;//读写ID数值保持一致即可。
    assign M_AXI_AWLEN   = wr_len_latched - 1;//突发长度（锁存值）；
    assign M_AXI_AWSIZE  = SIZE;//突发数据的位宽字节数；
    assign M_AXI_AWBURST = 2'b01;//突发类型为递增类型，即地址逐渐累加。
    assign M_AXI_AWLOCK  = 1'b0;//AXI4不支持锁事务，只为了兼容AXI3而存在的信号；
    assign M_AXI_AWCACHE = 4'b0010;//不使用缓存。
    assign M_AXI_AWPROT  = 3'd0;//写地址端口为0；
    assign M_AXI_AWQOS   = 4'd0;//信号指令为0，不使用。
    assign M_AXI_AWUSER  = 0;//用户自定义数据为0；
    assign M_AXI_WUSER   = 0;//用户自定义数据为0；
    
    //生成写突发的基地址信号.
    always@(posedge M_AXI_ACLK)begin
        if(M_AXI_ARESETN==1'b0)begin
            M_AXI_AWADDR <= C_M_TARGET_SLAVE_BASE_ADDR;
        end
        else if(wr_start)begin//写操作开始时锁存地址
            M_AXI_AWADDR <= C_M_TARGET_SLAVE_BASE_ADDR + wr_addr_in;
        end
        else if(M_AXI_BREADY & M_AXI_BVALID)begin//每次写完后,跳过已经被写数据段的地址.
            M_AXI_AWADDR <= M_AXI_AWADDR + (wr_len_latched * C_M_AXI_DATA_WIDTH/8);
        end
    end

    //生成写地址有效指示信号，与应答信号握手。
    always@(posedge M_AXI_ACLK)begin
        if(M_AXI_ARESETN==1'b0)begin//初始值为0;
            M_AXI_AWVALID <= 1'b0;
        end
        else if(M_AXI_AWREADY & M_AXI_AWVALID)begin//当应答信号有效时拉低。
            M_AXI_AWVALID <= 1'b0;
        end
        else if(wr_start == 1'b1) begin//当状态机从空闲状态跳转到写数据状态时拉高；
            M_AXI_AWVALID <= 1'b1;
        end   
    end

    //生成写数据计数器,用于计数写入数据个数.
    always@(posedge M_AXI_ACLK)begin
        if(M_AXI_ARESETN==1'b0)begin//初始值为0;
            wr_cnt <= 32'd0 ;// {{WR_CNT_W}{1'b0}};
        end
        else if(state != WRITE)begin//状态机不处于写数据状态时清零.
            wr_cnt <= 32'd0 ; //{{WR_CNT_W}{1'b0}};
        end
        else if(M_AXI_WVALID & M_AXI_WREADY)begin//当写入一个数据时加1.
            wr_cnt <= wr_cnt + 1;
        end
    end

    assign M_AXI_WUSER = 0;//用户自定义信号输出0；
    assign M_AXI_WSTRB = {{C_M_AXI_DATA_WIDTH/8}{1'b1}};//将掩码信号所有位拉高,不使用掩码功能. 
    
    assign M_AXI_WDATA = (data_rd_en)? wr_data_in : {C_M_AXI_DATA_WIDTH{1'b0}} ;
    
    //生成写地址有效指示信号.
    always@(posedge M_AXI_ACLK)begin
        if(M_AXI_ARESETN==1'b0)begin//初始值为0;
            M_AXI_WVALID <= 1'b0;
        end
        else if((wr_cnt == wr_len_latched-1) && (M_AXI_WVALID & M_AXI_WREADY))begin//写完最后一个数据时拉低;
            M_AXI_WVALID <= 1'b0;
        end
        else if(wr_fifo_empty == 1'b1)begin//FIFO空时暂停写传输，防止写入垃圾数据
            M_AXI_WVALID <= 1'b0;
        end
        else if((wr_fifo_empty == 1'b0) & (state == WRITE))begin//当状态机从空闲状态跳转到写数据状态且wr-fifo非空时，拉高；
            M_AXI_WVALID <= 1'b1;
        end
    end

    //生成写突发结束信号,初始值为低电平.
    always@(posedge M_AXI_ACLK)begin
        if(M_AXI_ARESETN==1'b0)begin//初始值为0;
            M_AXI_WLAST <= 1'b0;
        end
        // 单拍突发 (len=1)：进入 WRITE 状态且 FIFO 非空时立即拉高 WLAST
        else if(state == WRITE && wr_cnt == 0 && wr_len_latched == 1 && wr_fifo_empty == 1'b0)begin
            M_AXI_WLAST <= 1'b1;
        end
        else if((M_AXI_WVALID & M_AXI_WREADY))begin
            if(wr_cnt == wr_len_latched-1)//当写入最后一次数据后拉低;
                M_AXI_WLAST <= 1'b0;
            else if(wr_cnt == wr_len_latched-2)//当要写入最后一次数据时拉高.
                M_AXI_WLAST <= 1'b1;
        end
        else begin
            M_AXI_WLAST <= 1'b0;
        end
    end
    
    //生成AXI写响应通道主机应答信号。
    always@(posedge M_AXI_ACLK)begin
        if(M_AXI_ARESETN==1'b0)begin//初始值为0;
            M_AXI_BREADY <= 1'b0;
        end
        else if(M_AXI_BVALID & M_AXI_BREADY)begin//当从机输出有效的应答信号后拉低.
            M_AXI_BREADY <= 1'b0;
        end
        else if(M_AXI_WLAST & M_AXI_WVALID & M_AXI_WREADY)begin//当突发写传输完成时拉高;
            M_AXI_BREADY <= 1'b1;
        end
    end


//------------------------------- AXI READ----------------------------------//
    assign M_AXI_ARID     = 0;//读写ID数值保持一致即可。
    assign M_AXI_ARLEN    = rd_len_latched - 1;//突发长度（锁存值）；
    assign M_AXI_ARSIZE   = SIZE;//突发数据的位宽字节数；
    assign M_AXI_ARBURST  = 2'b01;//突发类型为递增类型，即地址逐渐累加。
    assign M_AXI_ARLOCK   = 1'b0;//AXI4不支持锁事务，只为了兼容AXI3而存在的信号；
    assign M_AXI_ARCACHE  = 4'b0010;//不使用缓存。
    assign M_AXI_ARPROT   = 3'd0;//写地址端口为0；
    assign M_AXI_ARQOS    = 4'd0;//信号指令为0，不使用。
    assign M_AXI_ARUSER   = 0;//用户自定义数据为0；

    //生成读突发的基地址信号.
    always@(posedge M_AXI_ACLK)begin
        if(M_AXI_ARESETN==1'b0)begin
            M_AXI_ARADDR <= C_M_TARGET_SLAVE_BASE_ADDR;
        end
        else if(rd_start)begin//读操作开始时锁存地址
            M_AXI_ARADDR <= C_M_TARGET_SLAVE_BASE_ADDR + rd_addr_in;
        end
        else if(M_AXI_RLAST && M_AXI_RVALID)begin//每次读完后,跳过已经被读数据段的地址.
            M_AXI_ARADDR <= M_AXI_ARADDR + (rd_len_latched * C_M_AXI_DATA_WIDTH/8);
        end
    end

    //生成读地址有效指示信号，与应答信号握手。
    always@(posedge M_AXI_ACLK)begin
        if(M_AXI_ARESETN==1'b0)begin//初始值为0;
            M_AXI_ARVALID <= 1'b0;
        end
        else if(M_AXI_ARREADY & M_AXI_ARVALID)begin//当应答信号有效时拉低。
            M_AXI_ARVALID <= 1'b0;
        end
        else if(rd_start == 1'b1)begin//读操作开始时拉高（脉冲触发，与 AWVALID 一致）；
            M_AXI_ARVALID <= 1'b1;
        end
    end

    reg  rd_data_flag ; // 读数据状态
    always@(posedge M_AXI_ACLK)begin
        if(M_AXI_ARESETN==1'b0)begin//初始值为0;
            rd_data_flag <= 1'b0;
        end
        else if(M_AXI_RLAST && M_AXI_RVALID) begin//读数据最后一拍握手成功时清零
            rd_data_flag <= 1'b0;
        end
        else if(M_AXI_ARREADY & M_AXI_ARVALID)
            rd_data_flag <= 1'b1;
        else begin
            rd_data_flag <= rd_data_flag;
        end
    end
            
    //生成读数据响应信号,初始为低电平.
    always@(posedge M_AXI_ACLK)begin
        if(M_AXI_ARESETN==1'b0)begin//初始值为0;
            M_AXI_RREADY <= 1'b0;
        end
        else if(rd_fifo_full == 1'b0) begin
            if(M_AXI_RLAST)begin//接收完一次突发数据时拉低.
                M_AXI_RREADY <= 1'b0;
            end
            else if(rd_data_flag)begin//写入读地址后拉高,准备接收数据.
                M_AXI_RREADY <= 1'b1;
            end
            else begin
                M_AXI_RREADY <= M_AXI_RREADY;
            end
        end
        else begin
            M_AXI_RREADY <= 1'b0;
        end
    end

    //读数据计数器,初始值为0,当读取一个数据时加1.
    always@(posedge M_AXI_ACLK)begin
        if(M_AXI_ARESETN==1'b0)begin//初始值为0;
            rd_cnt <= 32'd0 ; //{{RD_CNT_W}{1'b0}};
        end
        else if(state != READ)begin//状态机不处于读数据状态时清零.
            rd_cnt <= 32'd0 ; //{{RD_CNT_W}{1'b0}};
        end
        else if(M_AXI_RVALID & M_AXI_RREADY)begin//当读出一个数据时加1.
            rd_cnt <= rd_cnt + 1;
        end
    end

    
    assign data_out     = M_AXI_RDATA ;
    assign data_out_vld = M_AXI_RVALID & M_AXI_RREADY ;
    
      
endmodule