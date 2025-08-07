`timescale 1ns / 1ps
`include "controller_params.vh"


module buf_manager #(
    parameter W_SIZE        = `W_SIZE,
    parameter W_CHANNEL     = `W_CHANNEL,


    parameter IFM_DW        = `IFM_DW,  // 32
    parameter FILTER_DW     = `FILTER_DW,   // 72


    parameter FILTER_DEPTH = `FILTER_BUFFER_DEPTH,
    parameter FILTER_AW    = `FILTER_BUFFER_AW,

    parameter IFM_DEPTH   = `IFM_TOTAL_BUFFER_DEPTH,
    parameter IFM_AW      = `IFM_TOTAL_BUFFER_AW,

    parameter ROW_DEPTH   = `IFM_ROW_BUFFER_DEPTH,
    parameter ROW_AW      = `IFM_ROW_BUFFER_AW
)(
    input  wire               clk,
    input  wire               rstn,

    // Buffer Manager <-> TOP
    input  wire [W_SIZE-1:0]        q_width,
    input  wire [W_SIZE-1:0]        q_height,
    input  wire [W_CHANNEL-1:0]     q_channel,   // TILED input channel
    input  wire [W_SIZE+W_CHANNEL-1:0] q_row_stride, // q_width * q_channel

    input  wire [4:0]               q_layer,            // 몇번째 레이어인지 -> filter load할때 사용

    input  wire                     q_load_ifm,         // ifm 로드 시작 시그널
    output wire                     o_load_ifm_done,    // ifm 로드 완료 시그널

    input  wire [W_CHANNEL-1:0]     q_outchn,           // output channel 인덱스
    input  wire                     q_load_filter,       // filter 로드 시작 시그널
    output wire                     o_load_filter_done,    // ifm 로드 완료 시그널

    // Buffer Manager <-> AXI
    // AXI signals to load ifm, filter
    //

    // Buffer Manager <-> Controller 
    input  wire                         c_ctrl_data_run,
    input  wire [W_SIZE-1:0]            c_row,
    input  wire [W_SIZE-1:0]            c_col,
    input  wire [W_CHANNEL-1:0]         c_chn,

    input  wire                         c_is_first_row,
    input  wire                         c_is_last_row,
    input  wire                         c_is_first_col,
    input  wire                         c_is_last_col,
    input  wire                         c_is_first_chn,
    input  wire                         c_is_last_chn,


    // not use
    input  wire                 m_req_load,         // new row load request
    input  wire [W_SIZE-1:0]    m_req_row,          // req row idx
    output reg                  o_req_done,         // req done signal


    // Buffer Manager <-> pe_engine (IFM)
    output wire [IFM_DW-1:0]        ib_data0_out,
    output wire [IFM_DW-1:0]        ib_data1_out,
    output wire [IFM_DW-1:0]        ib_data2_out,

    // Buffer Manager <-> pe_engine (FILTER)
    input  wire                     fb_req,
    input  wire [FILTER_AW-1:0]     fb_addr,

    output wire [FILTER_DW-1:0]     fb_data0_out,
    output wire [FILTER_DW-1:0]     fb_data1_out,
    output wire [FILTER_DW-1:0]     fb_data2_out,
    output wire [FILTER_DW-1:0]     fb_data3_out,
);

//============================================================================
// 1) ifm buffer & AXI
//============================================================================
wire [IFM_AW-1:0]    ifm_buf_read_addr;
wire [IFM_DW-1:0]    ifm_buf_read_data;


// dpram_65536x32, 전체 ifm을 저장할 퍼버
dpram_wrapper #(
    .DEPTH  (IFM_DEPTH        ),
    .AW     (IFM_AW           ),
    .DW     (IFM_DW           ))
u_ifm_buf(    
    .clk	(clk		      ),
    // write port
    .ena	(/* AXI         */),
	.addra	(/* AXI         */),
	.wea	(/* AXI         */),
	.dia	(/* AXI         */),
    // read port
    .enb    (1'd1             ),  // Always Read       
    .addrb	(ifm_buf_read_addr),
    .dob	(ifm_buf_read_data)
);
//============================================================================




//============================================================================
// 2) filter buffer & AXI
//============================================================================

// dpram_512x72, filter 저장할 퍼버 & 4개
dpram_wrapper #(
    .DEPTH  (FILTER_DEPTH   ),
    .AW     (FILTER_AW      ),
    .DW     (FILTER_DW      ))
u_filter_buf0(    
    .clk	(clk		    ),
    .ena	(/* AXI       */),
	.addra	(/* AXI       */),
	.wea	(/* AXI       */),
	.dia	(/* AXI       */),
    .enb    (fb_req         ), 
    .addrb	(fb_addr        ),
    .dob	(fb_data0_out   )
);

dpram_wrapper #(
    .DEPTH  (FILTER_DEPTH   ),
    .AW     (FILTER_AW      ),
    .DW     (FILTER_DW      ))
u_filter_buf1(    
    .clk	(clk		    ),
    .ena	(/* AXI       */),
	.addra	(/* AXI       */),
	.wea	(/* AXI       */),
	.dia	(/* AXI       */),
    .enb    (fb_req         ), 
    .addrb	(fb_addr        ),
    .dob	(fb_data1_out   )
);

dpram_wrapper #(
    .DEPTH  (FILTER_DEPTH   ),
    .AW     (FILTER_AW      ),
    .DW     (FILTER_DW      ))
u_filter_buf2(    
    .clk	(clk		    ),
    .ena	(/* AXI       */),
	.addra	(/* AXI       */),
	.wea	(/* AXI       */),
	.dia	(/* AXI       */),
    .enb    (fb_req         ), 
    .addrb	(fb_addr        ),
    .dob	(fb_data2_out   )
);

dpram_wrapper #(
    .DEPTH  (FILTER_DEPTH   ),
    .AW     (FILTER_AW      ),
    .DW     (FILTER_DW      ))
u_filter_buf3(    
    .clk	(clk		    ),
    .ena	(/* AXI       */),
	.addra	(/* AXI       */),
	.wea	(/* AXI       */),
	.dia	(/* AXI       */),
    .enb    (fb_req         ), 
    .addrb	(fb_addr        ),
    .dob	(fb_data3_out   )
);
//============================================================================




//============================================================================
// 3) row buffer pointer
//============================================================================
localparam ABV = 2'd0, // row - 1
           CUR = 2'd1, // row
           BEL = 2'd2; // row + 1

reg  [1:0] ptr_row0, ptr_row1, ptr_row2;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        ptr_row0 <= CUR;
        ptr_row1 <= BEL;
        ptr_row2 <= ABV;
    end
    else if (c_is_last_chn && c_is_last_col) begin
        {ptr_row0, ptr_row1, ptr_row2} <= {ptr_row1, ptr_row2, ptr_row0};
    end
end
//============================================================================




//============================================================================
// 4) row buffer instantiate
//============================================================================
wire [IFM_DW-1:0] row0_dout, row1_dout, row2_dout; // row buf에서 읽어올 데이터
wire row0_wea, row1_wea, row2_wea;


wire [ROW_AW-1:0] row_buf_read_addr;

// dpram_1536x32 
dpram_wrapper #(
    .DEPTH  (ROW_DEPTH        ),
    .AW     (ROW_AW           ),
    .DW     (IFM_DW           ))
u_row_buf0(    
    .clk	(clk		      ),
    .ena	(1'b1             ),
	.addra	(row_buf_read_addr),
	.wea	(row0_wea         ),
	.dia	(ifm_buf_read_data),
    .enb    (c_ctrl_data_run  ),     
    .addrb	(row_buf_read_addr),
    .dob	(row0_dout        )
);

// dpram_1536x32 
dpram_wrapper #(
    .DEPTH  (ROW_DEPTH        ),
    .AW     (ROW_AW           ),
    .DW     (IFM_DW           ))
u_row_buf1(    
    .clk	(clk		      ),
    .ena	(1'b1             ),
	.addra	(row_buf_read_addr),
	.wea	(row1_wea         ),
	.dia	(ifm_buf_read_data),
    .enb    (c_ctrl_data_run  ),
    .addrb	(row_buf_read_addr),
    .dob	(row1_dout        )
);

// dpram_1536x32 
dpram_wrapper #(
    .DEPTH  (ROW_DEPTH        ),
    .AW     (ROW_AW           ),
    .DW     (IFM_DW           ))
u_row_buf2(    
    .clk	(clk		      ),
    .ena	(1'b1             ),
	.addra	(row_buf_read_addr),
	.wea	(row2_wea         ),
	.dia	(ifm_buf_read_data),
    .enb    (c_ctrl_data_run  ),     
    .addrb	(row_buf_read_addr),
    .dob	(row2_dout        ) 
);
//============================================================================





//============================================================================
// 5) supply data to row buf 
//============================================================================
// a) row buf0 initialize


// b) supply row buf
always @(*) begin 
    row0_wea = c_ctrl_data_run && (ptr_row0 == BEL);
    row1_wea = c_ctrl_data_run && (ptr_row1 == BEL);
    row2_wea = c_ctrl_data_run && (ptr_row2 == BEL);
end

//============================================================================





//============================================================================
// 6) row buf addressing logic
//============================================================================
// ifm_buf_read_addr & row_buf_read_addr (wire)
// [IFM_AW-1:0] ifm_buf_read_addr = c_row * (q_width * q_channel) + c_col * q_channel + c_chn
// [ROW_AW-1:0] row_buf_read_addr = c_col * q_channel + c_chn
//
// q_row_stride = q_width * q_channel


reg  [IFM_AW-1:0] reg_ifm_addr;    // total IFM buffer read address
reg  [ROW_AW-1:0] reg_row_addr;    // row buffer read address (offset within row)
reg  [IFM_AW-1:0] row_base;        // base address of current row = row * q_row_stride

// next row offset within a row (combinational)
wire [ROW_AW-1:0] next_row_offset =
    c_is_last_col && c_is_last_chn && c_is_last_row ? {ROW_AW{1'b0}} :            // finished all
    c_is_last_col && !c_is_last_chn                 ? (c_chn + 1)    :            // end of col
                                                      (reg_row_addr + q_channel); // same channel, next col


wire [IFM_AW-1:0] next_ifm_addr = row_base + {{IFM_AW-ROW_AW{1'b0}}, next_row_offset};

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        row_base     <= {IFM_AW{1'b0}};
        reg_row_addr <= {ROW_AW{1'b0}};
        reg_ifm_addr <= {IFM_AW{1'b0}};
    end
    else if (c_ctrl_data_run) begin
        reg_row_addr <= next_row_offset;
        reg_ifm_addr <= next_ifm_addr;


        if (c_is_last_col && c_is_last_chn && !c_is_last_row) begin
            row_base <= row_base + q_row_stride;
        end
    end
end

assign ifm_buf_read_addr = reg_ifm_addr;
assign row_buf_read_addr = reg_row_addr;
//============================================================================




//============================================================================
// 7) connect btw row buf & output registers ... comb
//============================================================================
always @(*) begin
    case({ptr_row0, ptr_row1, ptr_row2})
        {ABV, 2'b??, 2'b??}: ib_data0_out = row0_dout;
        {2'b??, ABV, 2'b??}: ib_data0_out = row1_dout;
        {2'b??, 2'b??, ABV}: ib_data0_out = row2_dout;
        default:     ib_data0_out = {IFM_DW{1'b0}};
    endcase

    case({ptr_row0, ptr_row1, ptr_row2})
        {CUR, 2'b??, 2'b??}: ib_data1_out = row0_dout;
        {2'b??, CUR, 2'b??}: ib_data1_out = row1_dout;
        {2'b??, 2'b??, CUR}: ib_data1_out = row2_dout;
        default:     ib_data1_out = {IFM_DW{1'b0}};
    endcase
    
    ib_data2_out = c_is_last_row ? {IFM_DW{1'b0}} : ifm_buf_read_data;
end
//============================================================================



endmodule