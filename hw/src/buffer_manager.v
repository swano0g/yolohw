`timescale 1ns / 1ps
`include "controller_params.vh"


module buffer_manager #(
    parameter W_SIZE        = `W_SIZE,
    parameter W_CHANNEL     = `W_CHANNEL,

    parameter BM_DELAY      = `BM_IB_DELAY - 1, // 2; output port reg -> only 2cycle delay inside BM
    parameter IFM_DW        = `IFM_DW,      // 32
    parameter OFM_DW        = `OFM_DW,      // 32
    parameter FILTER_DW     = `FILTER_DW,   // 72

    parameter FILTER_DEPTH = `FILTER_BUFFER_DEPTH,
    parameter FILTER_AW    = `FILTER_BUFFER_AW,

    // feature map
    parameter FM_DEPTH    = `FM_BUFFER_DEPTH,
    parameter FM_AW       = `FM_BUFFER_AW,
    parameter FM_DW       = `FM_BUFFER_DW,


    parameter IFM_DEPTH   = `FM_BUFFER_DEPTH,
    parameter IFM_AW      = `FM_BUFFER_AW,

    parameter OFM_DEPTH   = `FM_BUFFER_DEPTH,
    parameter OFM_AW      = `FM_BUFFER_AW,


    parameter ROW_DEPTH   = `IFM_ROW_BUFFER_DEPTH,
    parameter ROW_AW      = `IFM_ROW_BUFFER_AW,

    //AXI
    parameter AXI_WIDTH_DA = `AXI_WIDTH_DA
)(
    input  wire               clk,
    input  wire               rstn,

    // Buffer Manager <-> TOP
    input  wire [W_SIZE-1:0]        q_width,
    input  wire [W_SIZE-1:0]        q_height,
    input  wire [W_CHANNEL-1:0]     q_channel,   // TILED input channel
    input  wire [W_SIZE+W_CHANNEL-1:0] q_row_stride, // q_width * q_channel

    input  wire [4:0]               q_layer,            // 紐뉖쾲吏? ?젅?씠?뼱?씤吏? -> filter load?븷?븣 ?궗?슜

    input  wire                     q_load_ifm,         // ifm load start
    // output wire                     o_load_ifm_done,    // ifm load done

    input  wire [W_CHANNEL-1:0]     q_outchn,               // output channel ?씤?뜳?뒪
    input  wire                     q_load_filter,          // filter 濡쒕뱶 ?떆?옉 ?떆洹몃꼸
    output wire                     o_load_filter_done,     // filter 濡쒕뱶 ?셿猷? ?떆洹몃꼸

    input  wire                     q_fm_buf_switch,            // ofm <-> ifm switch


    // Buffer Manager <-> AXI
    input  wire [AXI_WIDTH_DA-1:0]  read_data,      // data from axi
    input  wire                     read_data_vld,  // whether valid
    input  wire                     first,          //


    // AXI mimic for filter_buf0
    input  wire                    dbg_axi_fb0_ena,
    input  wire [FILTER_AW-1:0]    dbg_axi_fb0_addra,
    input  wire                    dbg_axi_fb0_wea,
    input  wire [FILTER_DW-1:0]    dbg_axi_fb0_dia,
    // AXI mimic for filter_buf1
    input  wire                    dbg_axi_fb1_ena,
    input  wire [FILTER_AW-1:0]    dbg_axi_fb1_addra,
    input  wire                    dbg_axi_fb1_wea,
    input  wire [FILTER_DW-1:0]    dbg_axi_fb1_dia,
    // AXI mimic for filter_buf2
    input  wire                    dbg_axi_fb2_ena,
    input  wire [FILTER_AW-1:0]    dbg_axi_fb2_addra,
    input  wire                    dbg_axi_fb2_wea,
    input  wire [FILTER_DW-1:0]    dbg_axi_fb2_dia,
    // AXI mimic for filter_buf3
    input  wire                    dbg_axi_fb3_ena,
    input  wire [FILTER_AW-1:0]    dbg_axi_fb3_addra,
    input  wire                    dbg_axi_fb3_wea,
    input  wire [FILTER_DW-1:0]    dbg_axi_fb3_dia,


    //

    // Buffer Manager <-> Controller 
    input  wire                         c_ctrl_data_run,
    input  wire                         c_ctrl_csync_run,
    input  wire [W_SIZE-1:0]            c_row,
    input  wire [W_SIZE-1:0]            c_col,
    input  wire [W_CHANNEL-1:0]         c_chn,

    input  wire                         c_is_first_row,
    input  wire                         c_is_last_row,
    input  wire                         c_is_first_col,
    input  wire                         c_is_last_col,
    input  wire                         c_is_first_chn,
    input  wire                         c_is_last_chn,

    output wire                         o_bm_csync_done,


    // Buffer Manager <-> pe_engine (IFM)
    output reg [IFM_DW-1:0]        ib_data0_out,
    output reg [IFM_DW-1:0]        ib_data1_out,
    output reg [IFM_DW-1:0]        ib_data2_out,

    // Buffer Manager <-> pe_engine (FILTER)
    output wire                     fb_req_possible,

    input  wire                     fb_req,
    input  wire [FILTER_AW-1:0]     fb_addr,

    output wire [FILTER_DW-1:0]     fb_data0_out,
    output wire [FILTER_DW-1:0]     fb_data1_out,
    output wire [FILTER_DW-1:0]     fb_data2_out,
    output wire [FILTER_DW-1:0]     fb_data3_out
);


//============================================================================
//  . internal signals
//============================================================================
reg  csync_d;
reg  data_d;

wire csync_start = c_ctrl_csync_run & ~csync_d;
wire data_start  = c_ctrl_data_run  & ~data_d;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin 
        csync_d <= 0;
        data_d  <= 0;
    end
    else begin 
        csync_d <= c_ctrl_csync_run;
        data_d  <= c_ctrl_data_run;
    end
end

// control signal pipe
localparam 
    CTRL_DATA_RUN = 0,
    IS_FIRST_ROW  = 1,
    IS_LAST_ROW   = 2,
    IS_FIRST_COL  = 3,
    IS_LAST_COL   = 4,
    IS_FIRST_CHN  = 5,
    IS_LAST_CHN   = 6;

reg [6:0] control_pipe [0:BM_DELAY-1];

integer i;
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin 
        for (i = 0; i < BM_DELAY; i = i + 1) begin 
            control_pipe[i] <= 0;
        end
    end
    else begin 
        control_pipe[0] <= {c_is_last_chn, c_is_first_chn, c_is_last_col, c_is_first_col, c_is_last_row, c_is_first_row, c_ctrl_data_run};
        
        for (i = 1; i < BM_DELAY; i = i + 1) begin 
            control_pipe[i] <= control_pipe[i-1];
        end
    end
end

wire c_ctrl_data_run_d = control_pipe[BM_DELAY-1][CTRL_DATA_RUN];
wire c_is_first_row_d  = control_pipe[BM_DELAY-1][IS_FIRST_ROW];
wire c_is_last_row_d   = control_pipe[BM_DELAY-1][IS_LAST_ROW];
wire c_is_first_col_d  = control_pipe[BM_DELAY-1][IS_FIRST_COL];
wire c_is_last_col_d   = control_pipe[BM_DELAY-1][IS_LAST_COL];
wire c_is_first_chn_d  = control_pipe[BM_DELAY-1][IS_FIRST_CHN];
wire c_is_last_chn_d   = control_pipe[BM_DELAY-1][IS_LAST_CHN];
//============================================================================


//============================================================================
// I. FEATURE MAP BUFFER & AXI
//============================================================================
// ifm buf & ofm buf ping-pong
localparam  IFM = 1'b0,
            OFM = 1'b1;

reg  fm_buf0_ptr, fm_buf1_ptr;

always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin 
        fm_buf0_ptr <= IFM;
        fm_buf1_ptr <= OFM;
    end else begin 
        if (q_fm_buf_switch) begin 
            {fm_buf1_ptr, fm_buf0_ptr} <= {fm_buf0_ptr, fm_buf1_ptr};
        end
    end
end
//----------------------------------------------------------------------------

wire [FM_AW-1:0]     fm_buf0_write_addr;
wire                 fm_buf0_wea;
wire [FM_DW-1:0]     fm_buf0_write_data;
wire                 fm_buf0_read_en;
wire [FM_AW-1:0]     fm_buf0_read_addr;
wire [FM_DW-1:0]     fm_buf0_read_data;


wire [FM_AW-1:0]     fm_buf1_write_addr;
wire                 fm_buf1_wea;
wire [FM_DW-1:0]     fm_buf1_write_data;
wire                 fm_buf1_read_en;
wire [FM_AW-1:0]     fm_buf1_read_addr;
wire [FM_DW-1:0]     fm_buf1_read_data;

//----------------------------------------------------------------------------
wire [IFM_AW-1:0]    ifm_buf_read_addr;
wire [IFM_DW-1:0]    ifm_buf_read_data;
wire                 ifm_buf_read_en;

wire [OFM_AW-1:0]    ofm_buf_write_addr;
wire [OFM_DW-1:0]    ofm_buf_write_data;
wire                 ofm_buf_wea;
//----------------------------------------------------------------------------
// AXI APPEND
reg q_load_ifm_d;
always @(posedge clk or negedge rstn) begin
    if (!rstn) q_load_ifm_d <= 1'b0;
    else       q_load_ifm_d <= q_load_ifm;
end
wire load_start = q_load_ifm & ~q_load_ifm_d;

reg                 axi_ifm_ena;
reg                 axi_ifm_wr_en;
reg [IFM_AW-1:0]    axi_ifm_wr_addr;
reg [IFM_DW-1:0]    axi_ifm_wr_data;


always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        axi_ifm_ena     <= 0;
        axi_ifm_wr_en   <= 0;
        axi_ifm_wr_addr <= 0;
        axi_ifm_wr_data <= 0;
    end else begin
        axi_ifm_ena     <= q_load_ifm;
        axi_ifm_wr_en   <= q_load_ifm & read_data_vld;
        axi_ifm_wr_data <= read_data;

        if (load_start) begin
            axi_ifm_wr_addr <= 0;
        end else if (axi_ifm_wr_en) begin
            axi_ifm_wr_addr <= axi_ifm_wr_addr + 1'b1;
        end
    end
end
//----------------------------------------------------------------------------
assign fm_buf0_wea        = (axi_ifm_ena)      ? axi_ifm_wr_en     
                          : (fm_buf0_ptr==OFM) ? ofm_buf_wea        
                          : 1'b0;

assign fm_buf0_write_addr = (axi_ifm_ena)      ? axi_ifm_wr_addr     
                          : (fm_buf0_ptr==OFM) ? ofm_buf_write_addr 
                          : {FM_AW{1'b0}};

assign fm_buf0_write_data = (axi_ifm_ena)      ? axi_ifm_wr_data
                          : (fm_buf0_ptr==OFM) ? ofm_buf_write_data 
                          : {FM_DW{1'b0}};

assign fm_buf0_read_en    = (fm_buf0_ptr==IFM) ? ifm_buf_read_en    : 1'b0;
assign fm_buf0_read_addr  = (fm_buf0_ptr==IFM) ? ifm_buf_read_addr  : {FM_AW{1'b0}};

assign fm_buf1_wea        = (fm_buf1_ptr==OFM) ? ofm_buf_wea        : 1'b0;
assign fm_buf1_write_addr = (fm_buf1_ptr==OFM) ? ofm_buf_write_addr : {FM_AW{1'b0}};
assign fm_buf1_write_data = (fm_buf1_ptr==OFM) ? ofm_buf_write_data : {FM_DW{1'b0}};
assign fm_buf1_read_en    = (fm_buf1_ptr==IFM) ? ifm_buf_read_en    : 1'b0;
assign fm_buf1_read_addr  = (fm_buf1_ptr==IFM) ? ifm_buf_read_addr  : {FM_AW{1'b0}};

assign ifm_buf_read_data  = (fm_buf0_ptr==IFM) ? fm_buf0_read_data :
                            (fm_buf1_ptr==IFM) ? fm_buf1_read_data :
                            {IFM_DW{1'b0}};
//----------------------------------------------------------------------------
// dpram_65536x32
dpram_wrapper #(
    .DEPTH  (FM_DEPTH          ),
    .AW     (FM_AW             ),
    .DW     (FM_DW             ))
u_fm_buf0(    
    .clk	(clk		       ),
    // write port
    .ena	(1'b1              ),
    .addra  (fm_buf0_write_addr),
    .wea    (fm_buf0_wea       ),
    .dia    (fm_buf0_write_data),
    // read port
    .enb    (fm_buf0_read_en   ),
    .addrb	(fm_buf0_read_addr ),
    .dob	(fm_buf0_read_data )
);
// spare buffer for ping pong
dpram_wrapper #(
    .DEPTH  (FM_DEPTH          ),
    .AW     (FM_AW             ),
    .DW     (FM_DW             ))
u_fm_buf1(    
    .clk	(clk		       ),
    // write port
    .ena	(1'b1              ),
    .addra  (fm_buf1_write_addr),
    .wea    (fm_buf1_wea       ),
    .dia    (fm_buf1_write_data),
    // read port
    .enb    (fm_buf1_read_en   ),
    .addrb	(fm_buf1_read_addr ),
    .dob	(fm_buf1_read_data )
);
//============================================================================




//============================================================================
// II. FILTER BUFFER & AXI
//============================================================================

// dpram_512x72
function [15:0] cin_total_for_layer;
  input [3:0] idx;
  begin
    case (idx)
      4'd0:  cin_total_for_layer = 16'd3;    // conv0 : Cin=3
      4'd1:  cin_total_for_layer = 16'd16;   // conv2 : Cin=16
      4'd2:  cin_total_for_layer = 16'd32;   // conv4 : Cin=32
      4'd3:  cin_total_for_layer = 16'd64;   // conv6 : Cin=64
      4'd4:  cin_total_for_layer = 16'd128;  // conv8 : Cin=128
      4'd5:  cin_total_for_layer = 16'd256;  // conv10: Cin=256
      4'd6:  cin_total_for_layer = 16'd512;  // conv12: Cin=512
      4'd7:  cin_total_for_layer = 16'd256;  // conv13: Cin=256
      4'd8:  cin_total_for_layer = 16'd512;  // conv14: Cin=512
      4'd9:  cin_total_for_layer = 16'd128;  // conv17: Cin=128 (?   기 ?)
      4'd10: cin_total_for_layer = 16'd384;  // conv20: Cin=384
      default: cin_total_for_layer = 16'd0;
    endcase
  end
endfunction

wire [15:0] CIN_TOTAL=cin_total_for_layer(q_layer);

wire f_start=q_load_filter&first;//?  ?   ?  그널
wire f_in_vld=q_load_filter&read_data_vld;//data valid signal
// 9개(3x3) 수집 카운터
reg [3:0] kpos;                // 0..8
wire      kcommit = f_in_vld && (kpos == 4'd0)&&(f_start!=1);

reg [71:0] acc0, acc1, acc2, acc3; 
reg[FILTER_AW-1:0] f_wr_addr;

reg filter_group_done;

//buffer?   ?  결된 ?   ??  ?  
reg f_we0, f_we1, f_we2, f_we3;
reg[71:0] f_d0, f_d1, f_d2, f_d3;

reg filter_group_done, filter_group_done_q;
assign o_load_filter_done=filter_group_done&~filter_group_done_q;

// AXI mimic
// wire                    dbg_axi_fb0_ena;
// wire [FILTER_AW-1:0]    dbg_axi_fb0_addra;
// wire                    dbg_axi_fb0_wea;
// wire [FILTER_DW-1:0]    dbg_axi_fb0_dia;
always @(posedge clk or negedge rstn) begin
  if(!rstn) begin
    kpos <= 4'd0;
    acc0 <= 72'd0; acc1 <= 72'd0; acc2 <= 72'd0; acc3 <= 72'd0;
    f_wr_addr <= {FILTER_AW{1'b0}};
    {f_we0,f_we1,f_we2,f_we3} <= 4'b0000;
    filter_group_done   <= 1'b0;
    filter_group_done_q <= 1'b0;
  end else begin
    // defaults
    {f_we0,f_we1,f_we2,f_we3} <= 4'b0000;
    filter_group_done_q <= filter_group_done;
    filter_group_done   <= 1'b0;

    if (f_start) begin //only at the initial burst
      kpos      <= 4'd0;
      f_wr_addr <= {FILTER_AW{1'b0}};
      acc0 <= 72'd0; acc1 <= 72'd0; acc2 <= 72'd0; acc3 <= 72'd0;
    end

    if (f_in_vld) begin
      // 32b 워드 = {F3,F2,F1,F0} 각 8b가 동일 (kpos,Cin)에 해당
      acc0[8*kpos +: 8] <= read_data[ 7: 0];   // F0
      acc1[8*kpos +: 8] <= read_data[15: 8];   // F1
      acc2[8*kpos +: 8] <= read_data[23:16];   // F2
      acc3[8*kpos +: 8] <= read_data[31:24];   // F3

      kpos <= (kpos == 4'd8) ? 4'd0 : (kpos + 4'd1);
    end

    if (kcommit) begin
      // 9바이트 모였으니 동일 Cin 주소로 4개 필터 라인(72b) 동시 커밋
      f_we0 <= 1'b1; f_d0 <= acc0;
      f_we1 <= 1'b1; f_d1 <= acc1;
      f_we2 <= 1'b1; f_d2 <= acc2;
      f_we3 <= 1'b1; f_d3 <= acc3;

      // 다음 Cin
      if (f_wr_addr == CIN_TOTAL[FILTER_AW-1:0] - 1) begin
        // 이번 그룹(F0..F3)의 모든 Cin 완료
        filter_group_done <= 1'b1;
        f_wr_addr <= {FILTER_AW{1'b0}};
      end else begin
        f_wr_addr <= f_wr_addr + 1'b1;
      end
    end
  end
end
dpram_wrapper #(
    .DEPTH  (FILTER_DEPTH   ),
    .AW     (FILTER_AW      ),
    .DW     (FILTER_DW      ))
u_filter_buf0(    
    .clk	(clk		    ),
    .ena    (1    ),
    .addra  (f_wr_addr[FILTER_AW-1:0]  ),
    .wea    (f_we0    ),
    .dia    (f_d0   ),
    .enb    (fb_req         ), 
    .addrb	(fb_addr        ),
    .dob	(fb_data0_out   )
);

// AXI mimic
// wire                    dbg_axi_fb1_ena;
// wire [FILTER_AW-1:0]    dbg_axi_fb1_addra;
// wire                    dbg_axi_fb1_wea;
// wire [FILTER_DW-1:0]    dbg_axi_fb1_dia;
dpram_wrapper #(
    .DEPTH  (FILTER_DEPTH   ),
    .AW     (FILTER_AW      ),
    .DW     (FILTER_DW      ))
u_filter_buf1(    
    .clk	(clk		    ),
    .ena    (1    ),
    .addra  (f_wr_addr[FILTER_AW-1:0]  ),
    .wea    (f_we1    ),
    .dia    (f_d1    ),
    .enb    (fb_req         ), 
    .addrb	(fb_addr        ),
    .dob	(fb_data1_out   )
);


// AXI mimic
// wire                    dbg_axi_fb2_ena;
// wire [FILTER_AW-1:0]    dbg_axi_fb2_addra;
// wire                    dbg_axi_fb2_wea;
// wire [FILTER_DW-1:0]    dbg_axi_fb2_dia;
dpram_wrapper #(
    .DEPTH  (FILTER_DEPTH   ),
    .AW     (FILTER_AW      ),
    .DW     (FILTER_DW      ))
u_filter_buf2(    
    .clk	(clk		    ),
    .ena    (1   ),
    .addra  (f_wr_addr[FILTER_AW-1:0]  ),
    .wea    (f_we2    ),
    .dia    (f_d2    ),
    .enb    (fb_req         ), 
    .addrb	(fb_addr        ),
    .dob	(fb_data2_out   )
);



// AXI mimic
// wire                    dbg_axi_fb3_ena;
// wire [FILTER_AW-1:0]    dbg_axi_fb3_addra;
// wire                    dbg_axi_fb3_wea;
// wire [FILTER_DW-1:0]    dbg_axi_fb3_dia;
dpram_wrapper #(
    .DEPTH  (FILTER_DEPTH   ),
    .AW     (FILTER_AW      ),
    .DW     (FILTER_DW      ))
u_filter_buf3(    
    .clk	(clk		    ),
    .ena    (1   ),
    .addra  (f_wr_addr[FILTER_AW-1:0]  ),
    .wea    (f_we3   ),
    .dia    (f_d3    ),
    .enb    (fb_req         ), 
    .addrb	(fb_addr        ),
    .dob	(fb_data3_out   )
);


// fb_req_possible
// catch last write address
wire [FILTER_AW-1:0] fb_last_addr = ( {{(FILTER_AW-W_CHANNEL){1'b0}}, q_channel} << 2 ) - 1'b1;
wire filter_last_write = dbg_axi_fb3_ena & dbg_axi_fb3_wea & (dbg_axi_fb3_addra == fb_last_addr);


reg fb_req_possible_r;
always @(posedge clk or negedge rstn) begin
    if (!rstn || csync_start) fb_req_possible_r <= 1'b0;
    else if (filter_last_write) fb_req_possible_r <= 1'b1;
end

assign fb_req_possible = fb_req_possible_r;
//============================================================================





//========================================================================================================================================================
// III. ROW BUFFER
//========================================================================================================================================================
//----------------------------------------------------------------------------
// III-1) row buf pointer
//----------------------------------------------------------------------------
localparam ABV = 2'd0, // row - 1
           CUR = 2'd1, // row
           BEL = 2'd2; // row + 1

reg  [1:0] ptr_row0, ptr_row1, ptr_row2;

wire row_ptr_switch = c_ctrl_data_run_d && c_is_last_chn_d && c_is_last_col_d;

always @(posedge clk or negedge rstn) begin
    if (!rstn || data_start) begin
        ptr_row0 <= CUR;
        ptr_row1 <= BEL;
        ptr_row2 <= ABV;
    end
    else if (row_ptr_switch) begin
        {ptr_row0, ptr_row1, ptr_row2} <= {ptr_row2, ptr_row0, ptr_row1};
    end
end
//----------------------------------------------------------------------------
// III-2) row buffer prefill state machine (csync) FIXME
//----------------------------------------------------------------------------
reg                 pf_run;     // prefill active
reg                 pf_done;    // prefill done
reg                 pf_vld;     // read-latency (activate after 1 cycle)
reg  [ROW_AW-1:0]   pf_cnt;     // 0 .. (row_stride - 1)


wire [ROW_AW-1:0] row_elems = q_row_stride[ROW_AW-1:0]; 
wire [ROW_AW-1:0] pf_row_addr = pf_cnt;                             // rowbuf write addr
wire [IFM_AW-1:0] pf_ifm_addr = {{(IFM_AW-ROW_AW){1'b0}}, pf_cnt};  // ifmbuf read  addr
reg  [ROW_AW-1:0] pf_row_addr_d;

always @(posedge clk or negedge rstn) begin
    if (!rstn || data_start) begin
        pf_run  <= 1'b0;
        pf_done <= 1'b0;
        pf_vld  <= 1'b0;
        pf_cnt  <= {ROW_AW{1'b0}};
        pf_row_addr_d <= {ROW_AW{1'b0}};
    end else begin
        pf_vld <= pf_run;
        pf_row_addr_d <= pf_row_addr;
        // prefill start 
        if (csync_start) begin
            pf_run  <= 1'b1;
            pf_done <= 1'b0;
            pf_cnt  <= {ROW_AW{1'b0}};
        end else if (pf_run) begin
            pf_cnt <= pf_cnt + 1'b1;
            if (pf_cnt == row_elems - 1) begin
                pf_run  <= 1'b0;
                pf_done <= 1'b1;
            end
        end else if (!c_ctrl_csync_run) begin
            pf_done <= 1'b0;
        end
    end
end
//----------------------------------------------------------------------------
// III-3) row buffer signal
//----------------------------------------------------------------------------
wire [ROW_AW-1:0] row_buf0_read_addr, row_buf1_read_addr, row_buf2_read_addr;
wire [ROW_AW-1:0] row_buf0_write_addr, row_buf1_write_addr, row_buf2_write_addr;

wire row0_wea, row1_wea, row2_wea;
wire [IFM_DW-1:0] row0_dout, row1_dout, row2_dout; 

// prefill only row buf 0
assign row0_wea = pf_vld || (c_ctrl_data_run_d && (ptr_row0 == BEL));
assign row1_wea = c_ctrl_data_run_d && (ptr_row1 == BEL);
assign row2_wea = c_ctrl_data_run_d && (ptr_row2 == BEL);
//----------------------------------------------------------------------------
// III-4) ifm buf -> row buf addressing logic
//----------------------------------------------------------------------------
// ifm_buf_read_addr & row_buf_read_addr (wire)
// [IFM_AW-1:0] ifm_buf_read_addr = c_row * (q_width * q_channel) + c_col * q_channel + c_chn (+ q_row_stride)
// [ROW_AW-1:0] row_buf_read_addr = c_col * q_channel + c_chn
//
// q_row_stride = q_width * q_channel

// addr_offset = c_col * q_channel + c_chn

reg  [IFM_AW-1:0] reg_ifm_addr;    // total IFM buffer read address
reg  [ROW_AW-1:0] reg_row_addr;    // row buffer read address (offset within row)
reg  [ROW_AW-1:0] reg_row_addr_d;  // row buffer write address (one cycle delayed from read address)
reg  [IFM_AW-1:0] row_base;        // base address of current row = row * q_row_stride


wire [ROW_AW-1:0] addr_offset = c_col * q_channel + c_chn;

always @(posedge clk or negedge rstn) begin
    if (!rstn || csync_start) begin
        row_base     <= {IFM_AW{1'b0}};
        reg_row_addr <= {ROW_AW{1'b0}};
        reg_ifm_addr <= {IFM_AW{1'b0}};
    end
    else if (c_ctrl_data_run) begin
        reg_row_addr <= addr_offset;
        reg_ifm_addr <= row_base + {{IFM_AW-ROW_AW{1'b0}}, addr_offset} + q_row_stride;

        if (c_is_last_col && c_is_last_chn && !c_is_last_row) begin
            row_base <= row_base + q_row_stride;
        end
    end
end

always @(posedge clk or negedge rstn) begin 
    if (!rstn || csync_start) begin 
        reg_row_addr_d <= {ROW_AW{1'b0}};
    end
    else begin 
        reg_row_addr_d <= reg_row_addr;
    end
end


assign ifm_buf_read_addr  = pf_run ? pf_ifm_addr : reg_ifm_addr;
assign ifm_buf_read_en    = pf_run | (control_pipe[BM_DELAY-2][CTRL_DATA_RUN] & ~control_pipe[BM_DELAY-2][IS_LAST_ROW]);

assign row_buf0_read_addr = reg_row_addr;
assign row_buf1_read_addr = reg_row_addr;
assign row_buf2_read_addr = reg_row_addr;

assign row_buf0_write_addr = pf_vld ? pf_row_addr_d : reg_row_addr_d;
assign row_buf1_write_addr = reg_row_addr_d;
assign row_buf2_write_addr = reg_row_addr_d;
//----------------------------------------------------------------------------
// III-5) connect btw row buf & output registers ... comb
//----------------------------------------------------------------------------
// ABV
wire [IFM_DW-1:0] abv_mux =
    c_is_first_row_d  ? {IFM_DW{1'b0}} :
    (ptr_row0==ABV) ? row0_dout :
    (ptr_row1==ABV) ? row1_dout :
    (ptr_row2==ABV) ? row2_dout : {IFM_DW{1'b0}};

wire [IFM_DW-1:0] cur_mux =
    (ptr_row0==CUR) ? row0_dout :
    (ptr_row1==CUR) ? row1_dout :
    (ptr_row2==CUR) ? row2_dout : {IFM_DW{1'b0}};

wire [IFM_DW-1:0] bel_mux =
    c_is_last_row_d ? {IFM_DW{1'b0}} : ifm_buf_read_data;


always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        ib_data0_out <= {IFM_DW{1'b0}};
        ib_data1_out <= {IFM_DW{1'b0}};
        ib_data2_out <= {IFM_DW{1'b0}};
    end else begin
        ib_data0_out <= c_ctrl_data_run_d ? abv_mux : {IFM_DW{1'b0}};
        ib_data1_out <= c_ctrl_data_run_d ? cur_mux : {IFM_DW{1'b0}};
        ib_data2_out <= c_ctrl_data_run_d ? bel_mux : {IFM_DW{1'b0}};
    end
end
//----------------------------------------------------------------------------
// III-6) row buffer instance
//----------------------------------------------------------------------------
// dpram_1536x32 
dpram_wrapper #(
    .DEPTH  (ROW_DEPTH                              ),
    .AW     (ROW_AW                                 ),
    .DW     (IFM_DW                                 ))
u_row_buf0(    
    .clk	(clk		                            ),
    .ena	(1'b1                                   ),
	.addra	(row_buf0_write_addr                    ),
	.wea	(row0_wea                               ),
	.dia	(ifm_buf_read_data                      ),
    .enb    (control_pipe[BM_DELAY-2][CTRL_DATA_RUN]),     
    .addrb	(row_buf0_read_addr                     ),
    .dob	(row0_dout                              )
);
dpram_wrapper #(
    .DEPTH  (ROW_DEPTH                              ),
    .AW     (ROW_AW                                 ),
    .DW     (IFM_DW                                 ))
u_row_buf1(    
    .clk	(clk		                            ),
    .ena	(1'b1                                   ),
	.addra	(row_buf1_write_addr                    ),
	.wea	(row1_wea                               ),
	.dia	(ifm_buf_read_data                      ),
    .enb    (control_pipe[BM_DELAY-2][CTRL_DATA_RUN]),
    .addrb	(row_buf1_read_addr                     ),
    .dob	(row1_dout                              )
);
dpram_wrapper #(
    .DEPTH  (ROW_DEPTH                              ),
    .AW     (ROW_AW                                 ),
    .DW     (IFM_DW                                 ))
u_row_buf2(    
    .clk	(clk		                            ),
    .ena	(1'b1                                   ),
	.addra	(row_buf2_write_addr                    ),
	.wea	(row2_wea                               ),
	.dia	(ifm_buf_read_data                      ),
    .enb    (control_pipe[BM_DELAY-2][CTRL_DATA_RUN]),     
    .addrb	(row_buf2_read_addr                     ),
    .dob	(row2_dout                              ) 
);
//----------------------------------------------------------------------------
//========================================================================================================================================================


assign o_bm_csync_done = c_ctrl_csync_run & fb_req_possible & pf_done;

endmodule