`timescale 1ns / 1ps
`include "controller_params.vh"

module postprocessor #(
    parameter W_SIZE      = `W_SIZE,
    parameter W_CHANNEL   = `W_CHANNEL,
    parameter Tout        = `Tout,

    parameter PSUM_DW     = `W_PSUM,   // psum bitwidth
    parameter W_OUT       = `W_DATA,     // 8; final output bitwidth

    // parameter BIAS_DW     = `BIAS_DW,
    // parameter BIAS_AW     = `BIAS_BUFFER_AW,
    // parameter BIAS_DEPTH  = `BIAS_BUFFER_DEPTH,
    // parameter SCALE_DW    = `SCALE_DW,
    // parameter SCALE_AW    = `SCALE_BUFFER_AW,
    // parameter SCALE_DEPTH = `SCALE_BUFFER_DEPTH,

    // common
    parameter AFFINE_DW     = `BIAS_DW,
    parameter AFFINE_AW     = `BIAS_BUFFER_AW,
    parameter AFFINE_DEPTH  = `BIAS_BUFFER_DEPTH,

    parameter OFM_DW      = `FM_BUFFER_DW,
    parameter OFM_AW      = `FM_BUFFER_AW,
    parameter OFM_DEPTH   = `FM_BUFFER_DEPTH,

    parameter PE_ACCO_FLAT_BW = `PE_ACCO_FLAT_BW,

    parameter AXI_WIDTH_DA = `AXI_WIDTH_DA
)(
    input  wire                  clk,
    input  wire                  rstn,

    // postprocessor <-> top
    input  wire [4:0]               q_layer,
    
    input  wire [W_SIZE-1:0]        q_width,
    input  wire [W_SIZE-1:0]        q_height,
    input  wire [W_CHANNEL-1:0]     q_channel,      // tiled
    input  wire [W_CHANNEL-1:0]     q_channel_out,  // tiled

    input  wire                     q_load_bias,
    input  wire                     q_load_scale,

    // postprocessor <-> ctrl
    input  wire                     c_ctrl_csync_run,
    input  wire                     c_ctrl_psync_run,
    input  wire                     c_ctrl_psync_phase,


    output wire                     o_pp_load_done,
    output wire                     o_pb_sync_done,  // o_pp_sync_done?   ////=> post psync done signal

    // postprocessor <-> AXI
    // load bias, scales
    input  wire [AXI_WIDTH_DA-1:0]  read_data,      // data from axi
    input  wire                     read_data_vld,  // whether valid


    // postprocessor <-> pe_engine
    input  wire [PE_ACCO_FLAT_BW-1:0]   pe_data_i,
    input  wire                         pe_vld_i, 
    input  wire [W_SIZE-1:0]            pe_row_i,
    input  wire [W_SIZE-1:0]            pe_col_i,
    input  wire [W_CHANNEL-1:0]         pe_chn_i,
    input  wire [W_CHANNEL-1:0]         pe_chn_out_i,
    input  wire                         pe_is_last_chn, 

    // postprocessor <-> buffer_manager
    output wire                         o_pp_data_vld,
    output wire [OFM_DW-1:0]            o_pp_data,
    output wire [OFM_AW-1:0]            o_pp_addr
);

//============================================================================
// I. signals & pipe
//============================================================================
reg pre_psync_d;
reg post_psync_d;

wire pre_psync_start = c_ctrl_psync_run & ~pre_psync_d;
wire post_psync_start = c_ctrl_psync_run & ~post_psync_d;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin 
        pre_psync_d <= 0;
        post_psync_d <= 0;
    end
    else begin 
        pre_psync_d  <= (c_ctrl_psync_phase == 0) & c_ctrl_psync_run;
        post_psync_d <= (c_ctrl_psync_phase == 1) & c_ctrl_psync_run;
    end
end


wire bias_buf_read_en;
wire [AFFINE_AW-1:0] bias_buf_read_addr;
wire [AFFINE_DW-1:0]bias_buf_read_data;

wire scale_buf_read_en;
wire [AFFINE_AW-1:0] scale_buf_read_addr;
wire [AFFINE_DW-1:0] scale_buf_read_data;

//============================================================================
// II. BIAS, SCALE buffer
//============================================================================
// AXI APPEND
reg q_load_bias_d;
reg q_load_scale_d;
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        q_load_bias_d  <= 1'b0;
        q_load_scale_d <= 1'b0;
    end else begin 
        q_load_bias_d  <= q_load_bias;
        q_load_scale_d <= q_load_scale;
    end
end
wire load_bias_start  = q_load_bias  & ~q_load_bias_d;
wire load_scale_start = q_load_scale & ~q_load_scale_d;
//----------------------------------------------------------------------------
reg                     axi_load_busy;
reg                     axi_ptr;        // 0: bias, 1:scale
reg [AFFINE_AW-1:0]     axi_wr_addr;
reg [AXI_WIDTH_DA-1:0]  axi_wr_data;
reg                     axi_wr_vld;

wire [AFFINE_AW-1:0]    load_words = (q_channel_out << 2);

reg                     affine_load_done;

assign o_pp_load_done = affine_load_done;

always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin 
        affine_load_done <= 0;
    end else begin 
        if (axi_ptr == 1 && axi_wr_vld && (axi_wr_addr == load_words - 1)) begin 
            affine_load_done <= 1;
        end else begin 
            affine_load_done <= 0;  // pulse
        end
    end
end


always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        axi_load_busy <= 0;
        axi_ptr       <= 0; // 0: bias, 1:scale
        axi_wr_addr   <= 0;
        axi_wr_data   <= 0;
        axi_wr_vld    <= 0;
    end else begin
        axi_wr_data <= read_data;
        axi_wr_vld  <= read_data_vld;

        if (!axi_load_busy && load_bias_start) begin
            axi_load_busy <= 1;
            axi_ptr <= 0;
            axi_wr_addr <= 0;
        end else if (!axi_load_busy && load_scale_start) begin 
            axi_load_busy <= 1;
            axi_ptr <= 1;
            axi_wr_addr <= 0;
        end

        if (axi_load_busy) begin 
            if (axi_wr_vld) begin 
                axi_wr_addr <= axi_wr_addr + 1'b1;
            end

            if (axi_wr_vld && (axi_wr_addr == load_words - 1)) begin
                axi_load_busy <= 1'b0;
            end
        end
    end
end
//----------------------------------------------------------------------------
wire                 bias_buf_ena    = axi_load_busy && (axi_ptr == 1'b0);
wire [AFFINE_AW-1:0] bias_buf_addra  = axi_wr_addr;
wire                 bias_buf_wea    = bias_buf_ena && axi_wr_vld;
wire [AFFINE_DW-1:0] bias_buf_dia    = axi_wr_data;

wire                 scale_buf_ena   = axi_load_busy && (axi_ptr == 1);
wire [AFFINE_AW-1:0] scale_buf_addra = axi_wr_addr;
wire                 scale_buf_wea   = scale_buf_ena && axi_wr_vld;
wire [AFFINE_DW-1:0] scale_buf_dia   = axi_wr_data;
//----------------------------------------------------------------------------
// dpram_512x32
dpram_wrapper #(
    .DEPTH  (AFFINE_DEPTH       ),
    .AW     (AFFINE_AW          ),
    .DW     (AFFINE_DW          ))
u_bias_buf(    
    .clk	(clk		        ),
    // write port
    .ena	(bias_buf_ena       ),
    .addra  (bias_buf_addra     ),
    .wea    (bias_buf_wea       ),
    .dia    (bias_buf_dia       ),
    // read port
    .enb    (bias_buf_read_en   ),
    .addrb	(bias_buf_read_addr ),
    .dob	(bias_buf_read_data )
);

// dpram_512x32
dpram_wrapper #(
    .DEPTH  (AFFINE_DEPTH       ),
    .AW     (AFFINE_AW          ),
    .DW     (AFFINE_DW          ))
u_scale_buf(    
    .clk	(clk		        ),
    // write port
    .ena	(scale_buf_ena      ),
    .addra  (scale_buf_addra    ),
    .wea    (scale_buf_wea      ),
    .dia    (scale_buf_dia      ),
    // read port
    .enb    (scale_buf_read_en  ),
    .addrb	(scale_buf_read_addr),
    .dob	(scale_buf_read_data)
);
//============================================================================
// III. PSUM ROW buffer
//============================================================================
// dpram 32x256 * 4


//============================================================================
// IV. accumulating & column side max pool logic
//============================================================================


//============================================================================
// V. row side max pooling
//============================================================================


//============================================================================
// VI. output to buffer_manager 
//============================================================================






//============================================================================
// debugging
//============================================================================
localparam PSUM_DEPTH  = 65536; //
localparam PSUM_AW     = $clog2(PSUM_DEPTH); //

reg  [PSUM_DW-1:0] psumbuf [PSUM_DEPTH-1:0]; // dbg 
wire [PSUM_DW-1:0] acc_arr [0:Tout-1];

reg [PSUM_AW-1:0] base_addr;
integer i;
genvar g;

generate
    for (g = 0; g < Tout; g = g + 1) begin : UNPACK_ACC
        assign acc_arr[g] = pe_data_i[(g+1)*PSUM_DW-1 -: PSUM_DW];
    end
endgenerate

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        base_addr <= {PSUM_AW{1'b0}};
        for (i = 0; i < PSUM_DEPTH; i = i + 1) begin 
            psumbuf[i] <= 0;
        end
    end
    else if (pe_vld_i) begin
        base_addr = (pe_row_i * q_width + pe_col_i) * (q_channel_out<<2) + pe_chn_out_i * Tout;

        psumbuf[base_addr + 0] <= $signed(psumbuf[base_addr + 0]) + $signed(acc_arr[0]);
        psumbuf[base_addr + 1] <= $signed(psumbuf[base_addr + 1]) + $signed(acc_arr[1]);
        psumbuf[base_addr + 2] <= $signed(psumbuf[base_addr + 2]) + $signed(acc_arr[2]);
        psumbuf[base_addr + 3] <= $signed(psumbuf[base_addr + 3]) + $signed(acc_arr[3]);
    end
end

reg pb_sync_done;
reg [10:0] pb_sync_counter;
assign o_pb_sync_done = pb_sync_done;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin 
        pb_sync_done <= 0;
        pb_sync_counter <= 0;
    end else begin 
        if (c_ctrl_psync_run && c_ctrl_psync_phase == 1'b1) begin 
            pb_sync_counter <= pb_sync_counter + 1;

            if (pb_sync_counter == 999) begin 
                pb_sync_done <= 1;
            end
        end
    end
end
// //
endmodule