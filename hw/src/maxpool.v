`timescale 1ns / 1ps
`include "controller_params.vh"

module maxpool #(
    parameter W_SIZE        = `W_SIZE,
    parameter W_CHANNEL     = `W_CHANNEL,
    parameter Tout          = `Tout,
    parameter W_Tout        = `W_Tout,

    parameter OUT_DW        = `W_DATA,     // 8; final output bitwidth

    parameter OFM_DW        = `FM_BUFFER_DW,
    parameter OFM_AW        = `FM_BUFFER_AW,

    parameter MP_BUF_DW     = `MAXPOOL_BUFFER_DW,
    parameter MP_BUF_DEPTH  = `MAXPOOL_BUFFER_DEPTH,
    parameter MP_BUF_AW     = `MAXPOOL_BUFFER_AW
)(
    input  wire                     clk,
    input  wire                     rstn,

    // maxpool <-> top
    input  wire [W_SIZE-1:0]        q_width,
    input  wire [W_SIZE-1:0]        q_height,
    input  wire [W_CHANNEL-1:0]     q_channel_out,  // tiled output channel

    // maxpool <-> postprocessor
    input  wire                     pp_data_vld,
    input  wire [OFM_DW-1:0]        pp_data,

    input  wire [W_SIZE-1:0]        pp_row,         // 2의 거듭제곱 보장
    input  wire [W_SIZE-1:0]        pp_col,         // 2의 거듭제곱 보장
    input  wire [W_CHANNEL-1:0]     pp_chn_out,

    // maxpool <-> buffer manager
    output reg                      o_mp_data_vld,
    output reg  [OFM_DW-1:0]        o_mp_data,
    output reg  [OFM_AW-1:0]        o_mp_addr
);

//============================================================================
// I. signals & pipe
//============================================================================
// localparam STRIDE = 2;
// localparam STG    = STRIDE;


// reg [OUT_DW-1:0] data0_pipe [0:STG-1];  // output chn 0
// reg [OUT_DW-1:0] data1_pipe [0:STG-1];  // output chn 1
// reg [OUT_DW-1:0] data2_pipe [0:STG-1];  // output chn 2
// reg [OUT_DW-1:0] data3_pipe [0:STG-1];  // output chn 3
// reg              vld_pipe   [0:STG-1];


// integer i;

// always @(posedge clk or negedge rstn) begin 
//     if (!rstn) begin 
//         for (i = 0; i < STG; i = i + 1) begin 
//             data0_pipe[i] <= 0;
//             data1_pipe[i] <= 0;
//             data2_pipe[i] <= 0;
//             data3_pipe[i] <= 0;
//             vld_pipe[i]   <= 0;
//         end
//     end else begin 
//             data0_pipe[0] <= (pp_data_vld) ? pp_data[0*OUT_DW+:OUT_DW] : 0;
//             data1_pipe[0] <= (pp_data_vld) ? pp_data[1*OUT_DW+:OUT_DW] : 0;
//             data2_pipe[0] <= (pp_data_vld) ? pp_data[2*OUT_DW+:OUT_DW] : 0;
//             data3_pipe[0] <= (pp_data_vld) ? pp_data[3*OUT_DW+:OUT_DW] : 0;
//             vld_pipe[0]   <= pp_data_vld;

//         for (i = 1; i < STG; i = i + 1) begin 
//             data0_pipe[i] <= data0_pipe[i-1];
//             data1_pipe[i] <= data1_pipe[i-1];
//             data2_pipe[i] <= data2_pipe[i-1];
//             data3_pipe[i] <= data3_pipe[i-1];
//             vld_pipe[i]   <= vld_pipe[i-1];
//         end
//     end
// end

wire is_even_col = (pp_data_vld) && ~pp_col[0];
wire is_odd_col  = (pp_data_vld) && pp_col[0];
wire is_even_row = (pp_data_vld) && ~pp_row[0];
wire is_odd_row  = (pp_data_vld) && pp_row[0];


wire              s_vld   = pp_data_vld;

wire [OUT_DW-1:0] s_data0 = pp_data[0*OUT_DW+:OUT_DW];
wire [OUT_DW-1:0] s_data1 = pp_data[1*OUT_DW+:OUT_DW];
wire [OUT_DW-1:0] s_data2 = pp_data[2*OUT_DW+:OUT_DW];
wire [OUT_DW-1:0] s_data3 = pp_data[3*OUT_DW+:OUT_DW];


//============================================================================
// II. maxpool buffer
//============================================================================
// wire                    mp_buf_ena;
wire [MP_BUF_AW-1:0]    mp_buf_addra;
wire                    mp_buf_wea;
wire [MP_BUF_DW-1:0]    mp_buf_dia;

wire                    mp_buf_read_en;
wire [MP_BUF_AW-1:0]    mp_buf_read_addr; 
wire [MP_BUF_DW-1:0]    mp_buf_read_data;
//----------------------------------------------------------------------------
// dpram_128x32
dpram_wrapper #(
    .DEPTH  (MP_BUF_DEPTH       ),
    .AW     (MP_BUF_AW          ),
    .DW     (MP_BUF_DW          ))
u_maxpool_buf (    
    .clk	(clk		        ),
    // write port
    .ena	(1'b1               ),
    .addra  (mp_buf_addra       ),
    .wea    (mp_buf_wea         ),
    .dia    (mp_buf_dia         ),
    // read port
    .enb    (mp_buf_read_en     ),
    .addrb	(mp_buf_read_addr   ),
    .dob	(mp_buf_read_data   )
);


//============================================================================
// III. column side max pool
//============================================================================
// row 가 짝수면 maxpool_buf에 다시 저장
// row 가 홀수면 row side max pool
// col 이 짝수면 대기
// col 이 홀수면 col-side maxpool 진행

reg [OUT_DW-1:0] last_d0, last_d1, last_d2, last_d3;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        last_d0 <= 0;
        last_d1 <= 0;
        last_d2 <= 0;
        last_d3 <= 0;
    end else if (pp_data_vld && is_even_col) begin
        last_d0 <= s_data0;
        last_d1 <= s_data1; 
        last_d2 <= s_data2; 
        last_d3 <= s_data3;
    end
end


wire [OUT_DW-1:0] colmax0 = (s_data0 > last_d0) ? s_data0 : last_d0;
wire [OUT_DW-1:0] colmax1 = (s_data1 > last_d1) ? s_data1 : last_d1;
wire [OUT_DW-1:0] colmax2 = (s_data2 > last_d2) ? s_data2 : last_d2;
wire [OUT_DW-1:0] colmax3 = (s_data3 > last_d3) ? s_data3 : last_d3;


wire [MP_BUF_DW-1:0] colmax_pack = {colmax3, colmax2, colmax1, colmax0};


// maxpool buf write
// row 짝수, col 홀수
assign mp_buf_wea   = is_even_row && is_odd_col;
assign mp_buf_addra = (pp_col >> 1);
assign mp_buf_dia   = colmax_pack;


//============================================================================
// IV. row side max pool
//============================================================================
// row 가 짝수면 아무것도 안함
// row 가 홀수면 row-side maxpool 진행 & output 지정

// col 가 짝수면 maxpool buf address 지정, 데이터 꺼내오기
// col 홀수면 꺼내온 데이터와 비교 (row-side maxpool)


// maxpool buf read

assign mp_buf_read_en   = is_odd_row && is_even_col;
assign mp_buf_read_addr = (pp_col >> 1);

wire [OUT_DW-1:0]  buf_data0 = mp_buf_read_data[0*OUT_DW+:OUT_DW];
wire [OUT_DW-1:0]  buf_data1 = mp_buf_read_data[0*OUT_DW+:OUT_DW];
wire [OUT_DW-1:0]  buf_data2 = mp_buf_read_data[0*OUT_DW+:OUT_DW];
wire [OUT_DW-1:0]  buf_data3 = mp_buf_read_data[0*OUT_DW+:OUT_DW];


wire [OUT_DW-1:0] rowmax0 = (colmax0 > buf_data0) ? colmax0 : buf_data0;
wire [OUT_DW-1:0] rowmax1 = (colmax1 > buf_data1) ? colmax1 : buf_data1;
wire [OUT_DW-1:0] rowmax2 = (colmax2 > buf_data2) ? colmax2 : buf_data2;
wire [OUT_DW-1:0] rowmax3 = (colmax3 > buf_data3) ? colmax3 : buf_data3;

wire [OFM_DW-1:0] rowmax_pack = {rowmax3, rowmax2, rowmax1, rowmax0};



always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        o_mp_data_vld  <= 0;
        o_mp_data <= 0;
    end else begin
        if (is_odd_col && is_odd_row) begin 
            o_mp_data_vld  <= 1;
            o_mp_data <= rowmax_pack;
        end else begin 
            o_mp_data_vld  <= 0;
            o_mp_data <= 0;
        end
    end
end


// output address logic
// (row 홀수, col 홀수) 일때 output reg에 할당

// chn_out이 바뀌면 base address 지정.
// 매 데이터 address offset: q_channel_out

reg  [OFM_AW-1:0]    base_addr;
reg  [W_CHANNEL-1:0] chn_out_cur;
wire [W_CHANNEL-1:0] addr_offset = q_channel_out;


always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin 
        o_mp_addr <= 0;
        base_addr <= 0;
        chn_out_cur <= 0;
    end else begin
        // chn_out  
        if (pp_data_vld && (chn_out_cur != pp_chn_out)) begin 
            chn_out_cur <= pp_chn_out;
            base_addr   <= pp_chn_out;
        end

        if (is_odd_col && is_odd_row) begin 
            base_addr <= base_addr + addr_offset;
            o_mp_addr <= base_addr;
        end else begin 
            o_mp_addr <= 0;
        end
    end
end


endmodule