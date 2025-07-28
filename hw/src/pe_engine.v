`timescale 1ns/1ps
`include "controller_params.vh"


module pe_engine #(
    parameter W_SIZE        = `W_SIZE,
    parameter W_CHANNEL     = `W_CHANNEL,
    parameter W_FRAME_SIZE  = `W_FRAME_SIZE,
    parameter W_DELAY       = `W_DELAY,

    
    parameter K             = `K,
    parameter Tin           = `Tin,
    parameter Tout          = `Tout,
    parameter W_Tin         = `W_Tin,
    
    parameter IFM_DW        = `IFM_DW,
    parameter FILTER_DW     = `FILTER_DW,
    parameter W_PSUM        = `W_PSUM,
    parameter PE_DELAY      = `PE_DELAY,

    parameter NB_IFM        = `IFM_BUFFER_CNT,
    parameter BUF_AW        = `BUFFER_ADDRESS_BW,

    parameter NB_FILTER     = `FILTER_BUFFER_CNT,
    
    parameter PE_CAL_DELAY          = `PE_DELAY,
    parameter PE_IFM_FLAT_BW        = `PE_IFM_FLAT_BW,
    parameter PE_FILTER_FLAT_BW     = `PE_FILTER_FLAT_BW,
    parameter PE_ACCO_FLAT_BW       = `PE_ACCO_FLAT_BW,
    parameter PE_OUT_BW             = `W_PSUM

)(

    input  wire                     clk,
    input  wire                     rstn,
  
    // controller -> PE engine
    input  wire                         c_ctrl_data_run,
    input  wire                         c_ctrl_hsync_run,
    input  wire [W_SIZE-1:0]            c_row,
    input  wire [W_SIZE-1:0]            c_col,
    input  wire [W_CHANNEL-1:0]         c_chn,
    input  wire [W_FRAME_SIZE-1:0]      c_data_count,
    input  wire                         c_end_frame,

    input wire                          c_is_first_row,
    input wire                          c_is_last_row,
    input wire                          c_is_first_col,
    input wire                          c_is_last_col,


    // IFM buffer
    input  wire [IFM_DW-1:0]        ib_data0_in,
    input  wire [IFM_DW-1:0]        ib_data1_in,
    input  wire [IFM_DW-1:0]        ib_data2_in,

    // FILTER buffer
    output wire                     o_fb_req,
    output wire [BUF_AW-1:0]        o_fb_addr,

    input  wire [FILTER_DW-1:0]     fb_data0_in,
    input  wire [FILTER_DW-1:0]     fb_data1_in,
    input  wire [FILTER_DW-1:0]     fb_data2_in,
    input  wire [FILTER_DW-1:0]     fb_data3_in,


    // PSUM buffer
    output wire                     o_pb_req,
    output wire [BUF_AW-1:0]        o_pb_addr,

    input  wire [W_PSUM-1:0]        pb_data_in,


    // DEBUG
    // output wire []
);

// practically after 3 cycle from row,col,chn signal, calculation could start.
localparam  BUF_DELAY           = 1;  // buf -> pe
localparam  PE_DATA_DELAY       = 1;  // pe save data
localparam  PE_WINDOW_DELAY     = 1;  // to start calculation one more data should be loaded at pe.

localparam  PE_PRE_CAL_DELAY    = BUF_DELAY + PE_DATA_DELAY + PE_WINDOW_DELAY; // 3

localparam  STG                 = PE_PRE_CAL_DELAY + PE_CAL_DELAY; // 12




// 1. pipe
reg [W_SIZE-1:0]    row_pipe [0:STG-1];
reg [W_SIZE-1:0]    col_pipe [0:STG-1];
reg [W_CHANNEL-1:0] chn_pipe [0:STG-1];

// for calculation
reg                 data_vld_pipe [0:PE_PRE_CAL_DELAY-1];   // when data goes into pe
reg [3:0]           location_pipe [0:PE_PRE_CAL_DELAY-1];   // when start calculation

// for filter load
reg [W_Tin-1:0]     filter_offset_pipe   [0:BUF_DELAY-1];
reg                 filter_data_vld_pipe [0:BUF_DELAY-1];


integer i;
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin


        for (i = 0; i < BUF_DELAY; i = i + 1) begin 
            filter_offset_pipe[i] <= 0;
            filter_data_vld_pipe[i] <= 0;
        end

        for (i = 0; i < PE_PRE_CAL_DELAY; i = i + 1) begin 
            data_vld_pipe[i] <= 0;
            location_pipe[i] <= 0;
        end

        for (i = 0; i < STG; i = i + 1) begin
            row_pipe[i] <= 0;
            col_pipe[i] <= 0;
            chn_pipe[i] <= 0;
        end
    end else begin
        row_pipe[0] <= c_row;
        col_pipe[0] <= c_col;
        chn_pipe[0] <= c_chn;

        data_vld_pipe[0] <= c_ctrl_data_run;
        location_pipe[0] <= {c_is_last_col,  c_is_first_col, c_is_last_row, c_is_first_row};

        for (i = 1; i < PE_PRE_CAL_DELAY; i = i + 1) begin 
            data_vld_pipe[i] <= data_vld_pipe[i-1];
            location_pipe[i] <= location_pipe[i-1];
        end

        for (i = 1; i < STG; i = i + 1) begin
            row_pipe[i] <= row_pipe[i-1];
            col_pipe[i] <= col_pipe[i-1];
            chn_pipe[i] <= chn_pipe[i-1];
        end
    end
end



// 2. ifm
wire [PE_IFM_FLAT_BW-1:0] ib_data_flat  = {ib_data2_in, ib_data1_in, ib_data0_in};


// 3. filter
wire [PE_FILTER_FLAT_BW-1:0] fb_data_flat = {fb_data3_in, fb_data2_in, fb_data1_in, fb_data0_in};

reg             filter_loaded;
reg [W_Tin-1:0] filter_offset;

reg fb_req;
reg [BUF_AW-1:0] fb_addr;

always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin 
        //reset
        filter_loaded <= 0;
        filter_offset <= 0;
        fb_req <= 0;
    end
    else begin 
        if (!filter_loaded) begin 
            
            fb_addr <= c_chn * Tin + filter_offset;

            filter_offset_pipe[0]   <= filter_offset;
            filter_data_vld_pipe[0] <= 1;

            if (filter_offset == Tin - 1) begin 
                filter_loaded <= 1;
                fb_req <= 0;
                filter_data_vld_pipe[0] <= 1'b0;
            end else begin 
                fb_req  <= 1;
                filter_offset <= filter_offset + 1;
            end
        end
    end
end

assign o_fb_req  = fb_req;
assign o_fb_addr = fb_addr;


// 4. psum
// debugging

reg [31:0] psumbuf [192-1:0]; // 16*3*4=192     256*256*4(Tout)=262144

wire [PE_ACCO_FLAT_BW-1:0] acc_flat;
wire                   vld;


wire [PE_OUT_BW-1:0] acc_arr [0:Tout-1];
genvar g;
generate
    for (g = 0; g < Tout; g = g + 1) begin : UNPACK_ACC
        assign acc_arr[g] = acc_flat[(g+1)*PE_OUT_BW-1 -: PE_OUT_BW];
    end
endgenerate


localparam PSUM_IDX_W = 20;
reg [PSUM_IDX_W-1:0] idx0; // output channel 0


always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        idx0 <= {PSUM_IDX_W{1'b0}};
    end
    else if (vld) begin
        idx0 = (row_pipe[STG-1]*3 + col_pipe[STG-1]) * Tout;
        psumbuf[idx0] <= acc_arr[0];
        psumbuf[idx0 + 1] <= acc_arr[1];
        psumbuf[idx0 + 2] <= acc_arr[2];
        psumbuf[idx0 + 3] <= acc_arr[3];
    end
end



// 5. DUT: conv_pe


conv_pe u_conv_pe(
    ./*input    */clk           (clk                              ),
    ./*input    */rstn          (rstn                             ),
    ./*input    */t_data_run    (data_vld_pipe[BUF_DELAY-1]       ),
    ./*input    */t_cal_start   (data_vld_pipe[PE_PRE_CAL_DELAY-1]),

    ./*input    */c_is_first_row(location_pipe[PE_PRE_CAL_DELAY-1][0]),
    ./*input    */c_is_last_row (location_pipe[PE_PRE_CAL_DELAY-1][1]),
    ./*input    */c_is_first_col(location_pipe[PE_PRE_CAL_DELAY-1][2]),
    ./*input    */c_is_last_col (location_pipe[PE_PRE_CAL_DELAY-1][3]),

    // IFM BUFFER
    ./*input    */bm_ifm_data_flat(ib_data_flat     ),

    // FILTER BUFFER 
    ./*input    */change_filter      (location_pipe[PE_PRE_CAL_DELAY-2][2]),
    ./*input    */load_filter        (filter_data_vld_pipe[BUF_DELAY-1]   ),
    ./*input    */load_idx           (filter_offset_pipe[BUF_DELAY-1]     ),
    ./*input    */bm_filter_data_flat(fb_data_flat                        ),

    ./*output   */o_acc (acc_flat),
    ./*output   */o_vld (vld)
);


endmodule
