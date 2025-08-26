`timescale 1ns/1ps
`include "controller_params.vh"


module pe_engine #(
    parameter W_SIZE        = `W_SIZE,
    parameter W_CHANNEL     = `W_CHANNEL,
    
    parameter K             = `K,
    parameter Tin           = `Tin,
    parameter Tout          = `Tout,
    parameter W_Tin         = `W_Tin,
    
    parameter BM_DELAY      = `BM_IB_DELAY,
    parameter IFM_DW        = `IFM_DW,
    parameter FILTER_DW     = `FILTER_DW,
    parameter W_PSUM        = `W_PSUM,
    parameter PE_DELAY      = `PE_DELAY,

    parameter FILTER_BUF_AW = `FILTER_BUFFER_AW,

    parameter NB_FILTER     = `FILTER_BUFFER_CNT,
    
    parameter PE_CAL_DELAY          = `PE_DELAY,
    parameter PE_IFM_FLAT_BW        = `PE_IFM_FLAT_BW,
    parameter PE_FILTER_FLAT_BW     = `PE_FILTER_FLAT_BW,
    parameter PE_ACCO_FLAT_BW       = `PE_ACCO_FLAT_BW
)(

    input  wire                     clk,
    input  wire                     rstn,
  
    // controller -> PE engine
    input  wire                         c_ctrl_data_run,
    input  wire                         c_ctrl_csync_run,
    input  wire [W_SIZE-1:0]            c_row,
    input  wire [W_SIZE-1:0]            c_col,
    input  wire [W_CHANNEL-1:0]         c_chn,
    input  wire [W_CHANNEL-1:0]         c_chn_out,

    input  wire                         c_is_first_row,
    input  wire                         c_is_last_row,
    input  wire                         c_is_first_col,
    input  wire                         c_is_last_col,
    input  wire                         c_is_first_chn,
    input  wire                         c_is_last_chn,

    input  wire [W_CHANNEL-1:0]         q_channel,      // tiled input channel

    output wire                         o_pe_csync_done,


    // IFM buffer
    input  wire [IFM_DW-1:0]        ib_data0_in,
    input  wire [IFM_DW-1:0]        ib_data1_in,
    input  wire [IFM_DW-1:0]        ib_data2_in,

    // FILTER buffer
    input  wire                     fb_req_possible,

    output wire                     o_fb_req,
    output wire [FILTER_BUF_AW-1:0] o_fb_addr,

    input  wire [FILTER_DW-1:0]     fb_data0_in,
    input  wire [FILTER_DW-1:0]     fb_data1_in,
    input  wire [FILTER_DW-1:0]     fb_data2_in,
    input  wire [FILTER_DW-1:0]     fb_data3_in,


    // pe_engine -> postprocessor
    output wire [PE_ACCO_FLAT_BW-1:0]   o_pe_data,
    output wire                         o_pe_vld, 
    output wire [W_SIZE-1:0]            o_pe_row,
    output wire [W_SIZE-1:0]            o_pe_col,
    output wire [W_CHANNEL-1:0]         o_pe_chn,
    output wire [W_CHANNEL-1:0]         o_pe_chn_out,
    output wire                         o_pe_is_first_chn,
    output wire                         o_pe_is_last_chn 

);

localparam  IB_DELAY            = BM_DELAY;  // 2 calculate index -> buf -> pe
localparam  FB_DELAY            = 1;
localparam  PE_DATA_DELAY       = 1;  // pe save data
localparam  PE_WINDOW_DELAY     = 1;  // load window

localparam  PE_PRE_CAL_DELAY    = IB_DELAY + PE_DATA_DELAY + PE_WINDOW_DELAY; // 4

localparam  STG                 = PE_PRE_CAL_DELAY + PE_CAL_DELAY; // 15


wire t_change_filter;

// 0. internal signal
reg  csync_d;

wire csync_start = c_ctrl_csync_run & ~csync_d;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin 
        csync_d <= 0;
    end
    else begin 
        csync_d <= c_ctrl_csync_run;
    end
end



// 1. pipe
reg [W_SIZE-1:0]    row_pipe [0:STG-1];
reg [W_SIZE-1:0]    col_pipe [0:STG-1];
reg [W_CHANNEL-1:0] chn_pipe [0:STG-1];
reg [W_CHANNEL-1:0] chn_out_pipe [0:STG-1];

// chn loacation info
reg [1:0]           chn_location_pipe [0:STG-1];

// for calculation
reg                 data_vld_pipe [0:STG-1];   // when data goes into pe
reg [3:0]           location_pipe [0:PE_PRE_CAL_DELAY-1];   // when start calculation

// for filter load
reg [W_Tin-1:0]     filter_offset_pipe   [0:FB_DELAY-1];
reg                 filter_data_vld_pipe [0:FB_DELAY-1];


integer i;
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        for (i = 0; i < PE_PRE_CAL_DELAY; i = i + 1) begin 
            location_pipe[i] <= 0;
        end

        for (i = 0; i < STG; i = i + 1) begin
            data_vld_pipe[i] <= 0;

            row_pipe[i] <= 0;
            col_pipe[i] <= 0;
            chn_pipe[i] <= 0;
            chn_out_pipe[i] <= 0;

            chn_location_pipe[i] <= 0;
        end
    end else begin
        row_pipe[0] <= c_row;
        col_pipe[0] <= c_col;
        chn_pipe[0] <= c_chn;
        chn_out_pipe[0] <= c_chn_out;

        data_vld_pipe[0] <= c_ctrl_data_run;
        location_pipe[0] <= {c_is_last_col, c_is_first_col, c_is_last_row, c_is_first_row};
        chn_location_pipe[0] <= {c_is_last_chn, c_is_first_chn};

        for (i = 1; i < PE_PRE_CAL_DELAY; i = i + 1) begin 
            location_pipe[i] <= location_pipe[i-1];
        end

        for (i = 1; i < STG; i = i + 1) begin
            data_vld_pipe[i] <= data_vld_pipe[i-1];

            row_pipe[i] <= row_pipe[i-1];
            col_pipe[i] <= col_pipe[i-1];
            chn_pipe[i] <= chn_pipe[i-1];
            chn_out_pipe[i] <= chn_out_pipe[i-1];

            chn_location_pipe[i] <= chn_location_pipe[i-1];
        end
    end
end



// 2. ifm
wire [PE_IFM_FLAT_BW-1:0] ib_data_flat = {ib_data2_in, ib_data1_in, ib_data0_in};


// 3. filter
wire [PE_FILTER_FLAT_BW-1:0] fb_data_flat = {fb_data3_in, fb_data2_in, fb_data1_in, fb_data0_in};

reg             filter_loaded;
reg [W_Tin-1:0] filter_offset;

reg [W_CHANNEL-1:0] filter_idx;

reg fb_req;
reg [FILTER_BUF_AW-1:0] fb_addr;

always @(posedge clk or negedge rstn) begin 
    if (!rstn || csync_start) begin 
        //reset
        for (i = 0; i < FB_DELAY; i = i + 1) begin 
            filter_offset_pipe[i] <= 0;
            filter_data_vld_pipe[i] <= 0;
        end

        filter_loaded <= 0;
        filter_offset <= 0;
        filter_idx <= 0;
        fb_req <= 0;
    end
    else begin 
        for (i = 1; i < FB_DELAY; i = i + 1) begin 
            filter_offset_pipe[i] <= filter_offset_pipe[i-1];
            filter_data_vld_pipe[i] <= filter_data_vld_pipe[i-1];
        end

        // possible to load filter
        if (!filter_loaded && !fb_req && fb_req_possible) begin 
            fb_req <= 1;
            filter_data_vld_pipe[0] <= 0;
            
            filter_offset_pipe[0] <= filter_offset;
        end
        else if (fb_req) begin 
            // end
            if (filter_offset == Tin - 1) begin 
                fb_req <= 0;
                filter_loaded <= 1;
                filter_offset <= 0;
                filter_data_vld_pipe[0] <= 1;
                filter_offset_pipe[0] <= filter_offset;

                if (filter_idx == q_channel - 1) begin 
                    filter_idx <= 0;
                end
                else begin 
                    filter_idx <= filter_idx + 1;
                end
            end
            else begin 
                filter_offset <= filter_offset + 1;
                filter_data_vld_pipe[0] <= 1;
                filter_offset_pipe[0] <= filter_offset;
            end
        end
        else begin 
            filter_data_vld_pipe[0] <= 0;
            filter_offset_pipe[0] <= 0;
        end

        // change filter
        if (t_change_filter) begin 
            filter_loaded <= 0;
        end
    end
end

// filter address calculation; combinational
always @(*) begin 
    if (!rstn) begin 
        fb_addr = 0;
    end
    else begin 
        fb_addr = filter_idx * Tin + filter_offset;
    end
end

assign o_fb_req  = fb_req;
assign o_fb_addr = fb_addr;


assign t_change_filter = data_vld_pipe[PE_PRE_CAL_DELAY-2] && location_pipe[PE_PRE_CAL_DELAY-2][2];


// csync done signal
assign o_pe_csync_done = filter_loaded & c_ctrl_csync_run;


// 4. outputs to postprocessor
wire [PE_ACCO_FLAT_BW-1:0] acc_flat;
wire                       vld;

assign o_pe_data         = acc_flat;
assign o_pe_vld          = vld;
assign o_pe_row          = row_pipe[STG-1];
assign o_pe_col          = col_pipe[STG-1];
assign o_pe_chn          = chn_pipe[STG-1];
assign o_pe_chn_out      = chn_out_pipe[STG-1];
assign o_pe_is_first_chn = chn_location_pipe[STG-1][0];
assign o_pe_is_last_chn  = chn_location_pipe[STG-1][1];


// 5. DUT: conv_pe
conv_pe u_conv_pe(
    ./*input    */clk                (clk                                 ),
    ./*input    */rstn               (rstn                                ),
    ./*input    */t_data_run         (data_vld_pipe[IB_DELAY-1]           ),
    ./*input    */t_cal_start        (data_vld_pipe[PE_PRE_CAL_DELAY-1]   ),

    ./*input    */c_is_first_row     (location_pipe[PE_PRE_CAL_DELAY-1][0]),
    ./*input    */c_is_last_row      (location_pipe[PE_PRE_CAL_DELAY-1][1]),
    ./*input    */c_is_first_col     (location_pipe[PE_PRE_CAL_DELAY-1][2]),
    ./*input    */c_is_last_col      (location_pipe[PE_PRE_CAL_DELAY-1][3]),

    // IFM BUFFER
    ./*input    */bm_ifm_data_flat   (ib_data_flat                        ),

    // FILTER BUFFER 
    ./*input    */change_filter      (t_change_filter                     ),
    ./*input    */load_filter        (filter_data_vld_pipe[FB_DELAY-1]    ),
    ./*input    */load_idx           (filter_offset_pipe[FB_DELAY-1]      ),
    ./*input    */bm_filter_data_flat(fb_data_flat                        ),

    ./*output   */o_acc              (acc_flat                            ),
    ./*output   */o_vld              (vld                                 )
);


endmodule
