`timescale 1ns / 1ps
`include "controller_params.vh"


module buf_manager #(
    parameter W_SIZE        = `W_SIZE,
    parameter W_CHANNEL     = `W_CHANNEL,

    parameter IFM_DW        = `IFM_DW,
    parameter FILTER_DW     = `FILTER_DW,

    parameter BUF_AW        = `BUFFER_ADDRESS_BW,
    
    parameter IFM_BUF_CNT   = `IFM_BUFFER_CNT,      // 4
    parameter W_IFM_BUF     = `IFM_BUFFER,           // 2

    parameter IFM_DEPTH   = 65536,  // 256KB / 4B
    parameter IFM_AW      = $clog(IFM_DEPTH),  // 256KB / 4B

    parameter ROW_DEPTH   = 1536    // 6KB  / 4
)(
    input  wire               clk,
    input  wire               rstn,

    // Buffer Manager <-> TOP
    input  wire [W_SIZE-1:0]        q_width,
    input  wire [W_SIZE-1:0]        q_height,
    input  wire [W_CHANNEL-1:0]     q_channel,   // TILED input channel

    input  wire [4:0]               q_layer,            // 몇번째 레이어인지

    input  wire                     q_load_ifm,         // ifm 로드 시작 시그널
    output wire                     o_load_ifm_done,    // ifm 로드 완료 시그널

    input  wire [W_CHANNEL-1:0]     q_outchn,           // output channel 인덱스
    input  wire                     q_load_filter,       // filter 로드 시작 시그널
    output wire                     o_load_filter_done,    // ifm 로드 완료 시그널

    // Buffer Manager <-> AXI
    // AXI signals to load ifm, filter




    // Buffer Manager <-> Controller 
    input  wire                         c_ctrl_data_run,
    input  wire [W_SIZE-1:0]            c_row,
    input  wire [W_SIZE-1:0]            c_col,
    input  wire [W_CHANNEL-1:0]         c_chn,


    input  wire                 m_req_load,         // new row load request
    input  wire [W_SIZE-1:0]    m_req_row,          // req row idx
    output reg                  o_req_done,         // req done signal

    // Buffer Manager <-> pe_engine (IFM)
    output wire [IFM_DW-1:0]        ib_data0_out,
    output wire [IFM_DW-1:0]        ib_data1_out,
    output wire [IFM_DW-1:0]        ib_data2_out,

    // Buffer Manager <-> pe_engine (FILTER)
    input  wire                     fb_req,
    input  wire [BUF_AW-1:0]        fb_addr,

    output wire [FILTER_DW-1:0]     fb_data0_out,
    output wire [FILTER_DW-1:0]     fb_data1_out,
    output wire [FILTER_DW-1:0]     fb_data2_out,
    output wire [FILTER_DW-1:0]     fb_data3_out,
);

//============================================================================
// 1) ifm buffer 데이터 저장 (AXI와 연결)
//============================================================================
reg [IFM_AW-1:0]    ifm_buf_read_addr;
reg [IFM_DW-1:0]    ifm_buf_read_data;


// dpram_65536x32, 전체 ifm을 저장할 퍼버
dpram_wrapper #(
    .DEPTH  (IFM_DEPTH      ),
    .AW     (IFM_AW         ),
    .DW     (IFM_DW         ))
u_ifm_buf(    
    .clk	(clk		    ),
    // write port
    .ena	( ),
	.addra	( ),
	.wea	( ),
	.dia	( ),
    // read port
    .enb    (1'd1             ),  // Always Read       
    .addrb	(ifm_buf_read_addr),
    .dob	(ifm_buf_read_data)
);
//============================================================================




//============================================================================
// 2) filter buffer 데이터 저장 (AXI와 연결)
//============================================================================
// dpram_512x72, filter 저장할 퍼버
dpram_wrapper #(
    .DEPTH  (BUFF_DEPTH     ),
    .AW     (BUFF_ADDR_W    ),
    .DW     (AXI_WIDTH_DA   ))
u_filter_buf(    
    .clk	(clk		    ),
    .ena	(1'd1		    ),
	.addra	(read_data_cnt  ),
	.wea	(read_data_vld  ),
	.dia	(read_data      ),
    .enb    (1'd1           ),  // Always Read       
    .addrb	(write_data_cnt ),
    .dob	(write_data     )
);
//============================================================================




//============================================================================
// 3) row buffer & 포인터 회전
//============================================================================
// 포인터: row buffer 인덱스 (0,1,2)
reg  [1:0] ptr_above, ptr_cur, ptr_below;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        ptr_above <= 2'd0;  // row -1
        ptr_cur   <= 2'd1;  // row
        ptr_below <= 2'd2;  // row + 1 (데이터 저장)
    end
    else if (/* 한 행 연산 완료..*/) begin
        {ptr_above, ptr_cur, ptr_below} <= {ptr_cur, ptr_below, ptr_above};
    end
end

// dpram_1536x32 
dpram_wrapper #(
    .DEPTH  (BUFF_DEPTH     ),
    .AW     (BUFF_ADDR_W    ),
    .DW     (AXI_WIDTH_DA   ))
u_row_buf0(    
    .clk	(clk		    ),
    .ena	(1'd1		    ),
	.addra	(read_data_cnt  ),
	.wea	(read_data_vld  ),
	.dia	(read_data      ),
    .enb    (1'd1           ),  // Always Read       
    .addrb	(write_data_cnt ),
    .dob	(write_data     )
);

// dpram_1536x32 
dpram_wrapper #(
    .DEPTH  (BUFF_DEPTH     ),
    .AW     (BUFF_ADDR_W    ),
    .DW     (AXI_WIDTH_DA   ))
u_row_buf1(    
    .clk	(clk		    ),
    .ena	(1'd1		    ),
	.addra	(read_data_cnt  ),
	.wea	(read_data_vld  ),
	.dia	(read_data      ),
    .enb    (1'd1           ),  // Always Read       
    .addrb	(write_data_cnt ),
    .dob	(write_data     )
);

// dpram_1536x32 
dpram_wrapper #(
    .DEPTH  (BUFF_DEPTH     ),
    .AW     (BUFF_ADDR_W    ),
    .DW     (AXI_WIDTH_DA   ))
u_row_buf2(    
    .clk	(clk		    ),
    .ena	(1'd1		    ),
	.addra	(read_data_cnt  ),
	.wea	(read_data_vld  ),
	.dia	(read_data      ),
    .enb    (1'd1           ),  // Always Read       
    .addrb	(write_data_cnt ),
    .dob	(write_data     )
);
//============================================================================



endmodule