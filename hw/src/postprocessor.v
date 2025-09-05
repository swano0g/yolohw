`timescale 1ns / 1ps
`include "controller_params.vh"

module postprocessor #(
    parameter W_SIZE        = `W_SIZE,
    parameter W_CHANNEL     = `W_CHANNEL,
    parameter Tout          = `Tout,
    parameter W_Tout        = `W_Tout,

    parameter OUT_DW        = `W_DATA,     // 8; final output bitwidth

    // common
    parameter AFFINE_DW     = `BIAS_DW,
    parameter AFFINE_AW     = `BIAS_BUFFER_AW,
    parameter AFFINE_DEPTH  = `BIAS_BUFFER_DEPTH,

    parameter OFM_DW        = `FM_BUFFER_DW,
    parameter OFM_AW        = `FM_BUFFER_AW,
    parameter OFM_DEPTH     = `FM_BUFFER_DEPTH,

    parameter PSUM_DW       = `PSUM_DW,
    parameter PSUM_AW       = `PSUM_BUFFER_AW,
    parameter PSUM_DEPTH    = `PSUM_BUFFER_DEPTH,

    parameter PE_ACCO_FLAT_BW = `PE_ACCO_FLAT_BW,

    parameter AXI_WIDTH_DA  = `AXI_WIDTH_DA
)(
    input  wire                  clk,
    input  wire                  rstn,

    // postprocessor <-> top
    input  wire [W_SIZE-1:0]        q_width,
    input  wire [W_SIZE-1:0]        q_height,
    input  wire [W_CHANNEL-1:0]     q_channel,
    input  wire [W_CHANNEL-1:0]     q_channel_out,

    input  wire                     q_load_bias,
    input  wire                     q_load_scale,

    // postprocessor <-> ctrl
    input  wire                     c_ctrl_csync_run,
    input  wire                     c_ctrl_psync_run,
    input  wire                     c_ctrl_psync_phase,

    input  wire [W_CHANNEL-1:0]     c_ctrl_chn_out,


    output wire                     o_pp_load_done,

    // postprocessor <-> AXI
    // load bias, scales
    input  wire [AXI_WIDTH_DA-1:0]  read_data,
    input  wire                     read_data_vld,


    // postprocessor <-> pe_engine
    input  wire [PE_ACCO_FLAT_BW-1:0]   pe_data_i,
    input  wire                         pe_vld_i, 
    input  wire [W_SIZE-1:0]            pe_row_i,
    input  wire [W_SIZE-1:0]            pe_col_i,
    input  wire [W_CHANNEL-1:0]         pe_chn_i,
    input  wire [W_CHANNEL-1:0]         pe_chn_out_i,
    input  wire                         pe_is_first_chn_i,
    input  wire                         pe_is_last_chn_i, 

    // postprocessor <-> buffer_manager, maxpool, upsample 
    output reg                          o_pp_data_vld,
    output reg  [OFM_DW-1:0]            o_pp_data,
    output reg  [OFM_AW-1:0]            o_pp_addr,

    output wire [W_SIZE-1:0]            o_pp_row,
    output wire [W_SIZE-1:0]            o_pp_col,
    output wire [W_CHANNEL-1:0]         o_pp_chn_out
);

//============================================================================
// I. signals & pipe
//============================================================================
localparam STG = 3;

reg csync_d;
reg pre_psync_d;
reg post_psync_d;

wire csync_start = c_ctrl_csync_run & ~csync_d;
wire pre_psync_start = c_ctrl_psync_run & ~pre_psync_d;
wire post_psync_start = c_ctrl_psync_run & ~post_psync_d;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        csync_d <= 0; 
        pre_psync_d <= 0;
        post_psync_d <= 0;
    end
    else begin 
        csync_d <= c_ctrl_csync_run;
        pre_psync_d  <= (c_ctrl_psync_phase == 0) & c_ctrl_psync_run;
        post_psync_d <= (c_ctrl_psync_phase == 1) & c_ctrl_psync_run;
    end
end


wire                 bias_buf_read_en;
wire [AFFINE_AW-1:0] bias_buf_read_addr;
wire [AFFINE_DW-1:0] bias_buf_read_data;

wire                 scale_buf_read_en;
wire [AFFINE_AW-1:0] scale_buf_read_addr;
wire [AFFINE_DW-1:0] scale_buf_read_data;



reg [PE_ACCO_FLAT_BW-1:0]   data_pipe    [0:STG-1];
reg                         vld_pipe     [0:STG-1];
reg [W_SIZE-1:0]            row_pipe     [0:STG-1];
reg [W_SIZE-1:0]            col_pipe     [0:STG-1];
reg [W_CHANNEL-1:0]         chn_pipe     [0:STG-1];
reg [W_CHANNEL-1:0]         chn_out_pipe [0:STG-1];
reg [1:0]                   pad_pipe     [0:STG-1];

integer i;

always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin 
        for (i = 0; i < STG; i = i + 1) begin 
            data_pipe[i]    <= 0;
            vld_pipe[i]     <= 0;
            row_pipe[i]     <= 0;
            col_pipe[i]     <= 0;
            chn_pipe[i]     <= 0;
            chn_out_pipe[i] <= 0;
            pad_pipe[i]     <= 0; 
        end
    end else begin 
        data_pipe[0] <= pe_data_i;
        vld_pipe[0] <= pe_vld_i;
        row_pipe[0] <= pe_row_i;
        col_pipe[0] <= pe_col_i;
        chn_pipe[0] <= pe_chn_i;
        chn_out_pipe[0] <= pe_chn_out_i;
        pad_pipe[0] <= {pe_is_last_chn_i, pe_is_first_chn_i};

        for (i = 1; i < STG; i = i + 1) begin 
            data_pipe[i] <= data_pipe[i-1];
            vld_pipe[i] <= vld_pipe[i-1];
            row_pipe[i] <= row_pipe[i-1];
            col_pipe[i] <= col_pipe[i-1];
            chn_pipe[i] <= chn_pipe[i-1];
            chn_out_pipe[i] <= chn_out_pipe[i-1];
            pad_pipe[i] <= pad_pipe[i-1];            
        end
    end
end


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


wire [AFFINE_AW:0]   words_w = {q_channel_out, 2'b00};
wire [AFFINE_AW:0]   last_w  = (words_w != 0) ? (words_w - {{AFFINE_AW{1'b0}},1'b1}) : { (AFFINE_AW+1){1'b0} };
wire [AFFINE_AW-1:0] affine_last_addr = last_w[AFFINE_AW-1:0];

// wire [AFFINE_AW-1:0]    affine_last_addr = (q_channel_out << 2) - 1'b1;
// wire [AFFINE_AW:0]      load_words = (q_channel_out << 2);

reg                     affine_load_done;

assign o_pp_load_done = affine_load_done;

always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin 
        affine_load_done <= 0;
    end else begin 
        if (axi_ptr == 1 && axi_wr_vld && (axi_wr_addr == affine_last_addr)) begin 
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

            if (axi_wr_vld && (axi_wr_addr == affine_last_addr)) begin
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
u_bias_buf (    
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
wire [PSUM_AW-1:0]  psum_buf0_addra; 
wire                psum_buf0_wea;  
wire [PSUM_DW-1:0]  psum_buf0_dia; 
wire                psum_buf0_read_en; 
wire [PSUM_AW-1:0]  psum_buf0_read_addr;
wire [PSUM_DW-1:0]  psum_buf0_read_data;


wire [PSUM_AW-1:0]  psum_buf1_addra; 
wire                psum_buf1_wea;  
wire [PSUM_DW-1:0]  psum_buf1_dia; 
wire                psum_buf1_read_en; 
wire [PSUM_AW-1:0]  psum_buf1_read_addr;
wire [PSUM_DW-1:0]  psum_buf1_read_data;


wire [PSUM_AW-1:0]  psum_buf2_addra; 
wire                psum_buf2_wea;  
wire [PSUM_DW-1:0]  psum_buf2_dia; 
wire                psum_buf2_read_en; 
wire [PSUM_AW-1:0]  psum_buf2_read_addr;
wire [PSUM_DW-1:0]  psum_buf2_read_data;

 
wire [PSUM_AW-1:0]  psum_buf3_addra; 
wire                psum_buf3_wea;  
wire [PSUM_DW-1:0]  psum_buf3_dia; 
wire                psum_buf3_read_en; 
wire [PSUM_AW-1:0]  psum_buf3_read_addr;
wire [PSUM_DW-1:0]  psum_buf3_read_data;


//----------------------------------------------------------------------------
// "read first" option

// dpram 256x32 * 4
dpram_wrapper #(
    .DEPTH  (PSUM_DEPTH         ),
    .AW     (PSUM_AW            ),
    .DW     (PSUM_DW            ))
u_psum_buf0 (    
    .clk	(clk		        ),
    // write port
    .ena	(1'b1               ),
    .addra  (psum_buf0_addra    ),
    .wea    (psum_buf0_wea      ),
    .dia    (psum_buf0_dia      ),
    // read port
    .enb    (psum_buf0_read_en  ),
    .addrb	(psum_buf0_read_addr),
    .dob	(psum_buf0_read_data)
);

dpram_wrapper #(
    .DEPTH  (PSUM_DEPTH         ),
    .AW     (PSUM_AW            ),
    .DW     (PSUM_DW            ))
u_psum_buf1 (    
    .clk	(clk		        ),
    // write port
    .ena	(1'b1               ),
    .addra  (psum_buf1_addra    ),
    .wea    (psum_buf1_wea      ),
    .dia    (psum_buf1_dia      ),
    // read port
    .enb    (psum_buf1_read_en  ),
    .addrb	(psum_buf1_read_addr),
    .dob	(psum_buf1_read_data)
);

dpram_wrapper #(
    .DEPTH  (PSUM_DEPTH         ),
    .AW     (PSUM_AW            ),
    .DW     (PSUM_DW            ))
u_psum_buf2 (    
    .clk	(clk		        ),
    // write port
    .ena	(1'b1               ),
    .addra  (psum_buf2_addra    ),
    .wea    (psum_buf2_wea      ),
    .dia    (psum_buf2_dia      ),
    // read port
    .enb    (psum_buf2_read_en  ),
    .addrb	(psum_buf2_read_addr),
    .dob	(psum_buf2_read_data)
);

dpram_wrapper #(
    .DEPTH  (PSUM_DEPTH         ),
    .AW     (PSUM_AW            ),
    .DW     (PSUM_DW            ))
u_psum_buf3 (    
    .clk	(clk		        ),
    // write port
    .ena	(1'b1               ),
    .addra  (psum_buf3_addra    ),
    .wea    (psum_buf3_wea      ),
    .dia    (psum_buf3_dia      ),
    // read port
    .enb    (psum_buf3_read_en  ),
    .addrb	(psum_buf3_read_addr),
    .dob	(psum_buf3_read_data)
);

//============================================================================
// IV. bias & scale csync
//============================================================================
reg [AFFINE_DW-1:0] bias0, bias1, bias2, bias3;
reg [7:0] scale0, scale1, scale2, scale3; 


function integer scale2shift;
    input [AFFINE_DW-1:0] sc;
    begin
        case (sc)
        8'h80: scale2shift = 8;
        8'h40: scale2shift = 7;
        8'h20: scale2shift = 6;
        8'h10: scale2shift = 5;
        8'h08: scale2shift = 4;
        8'h04: scale2shift = 3;
        8'h02: scale2shift = 2;
        8'h01: scale2shift = 1;
        default: scale2shift = 0;
        endcase
    end
endfunction


reg                 affine_loading;
reg                 affine_vld;
reg [W_Tout-1:0]    affine_offset;
reg [AFFINE_AW-1:0] affine_address;


wire vld_clear = !vld_pipe[STG-1] && c_ctrl_csync_run;

reg  vld_clear_d;

always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin 
        vld_clear_d <= 0;
    end else begin 
        vld_clear_d <= vld_clear;
    end
end

wire affine_load_start = vld_clear && !vld_clear_d;


always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin 
        affine_loading <= 0;
        affine_vld <= 0;
        affine_offset <= 0;
        affine_address <= 0;

        bias0 <= {AFFINE_DW{1'b0}};
        bias1 <= {AFFINE_DW{1'b0}};
        bias2 <= {AFFINE_DW{1'b0}};
        bias3 <= {AFFINE_DW{1'b0}};
        scale0 <= 8'd0; scale1 <= 8'd0; scale2 <= 8'd0; scale3 <= 8'd0;
    end
    else begin 
        if (affine_load_start) begin 
            affine_loading <= 1;
            affine_offset <= 0;
            affine_address <= (c_ctrl_chn_out << 2);
        end

        affine_vld <= affine_loading;

        if (affine_loading) begin
            if (affine_offset == Tout - 2) begin 
                affine_loading <= 0;
            end
            affine_address <= affine_address + 1;
        end

        if (affine_vld) begin 
            affine_offset <= affine_offset + 1;
            case (affine_offset)
                0: begin
                    bias0  <= bias_buf_read_data;
                    scale0 <= scale2shift(scale_buf_read_data[7:0]);
                end
                1: begin
                    bias1  <= bias_buf_read_data;
                    scale1 <= scale2shift(scale_buf_read_data[7:0]);
                end
                2: begin
                    bias2  <= bias_buf_read_data;
                    scale2 <= scale2shift(scale_buf_read_data[7:0]);
                end
                3: begin
                    bias3  <= bias_buf_read_data;
                    scale3 <= scale2shift(scale_buf_read_data[7:0]);
                end
                default: ;
            endcase
        end
    end
end


assign bias_buf_read_en    = affine_loading;
assign bias_buf_read_addr  = affine_address;
assign scale_buf_read_en   = affine_loading;
assign scale_buf_read_addr = affine_address;

//============================================================================
// V. accumulating
//============================================================================
// STG 0 
// data vld and not first chn
assign psum_buf0_read_en = vld_pipe[0] && !pad_pipe[0][0];
assign psum_buf1_read_en = vld_pipe[0] && !pad_pipe[0][0];
assign psum_buf2_read_en = vld_pipe[0] && !pad_pipe[0][0];
assign psum_buf3_read_en = vld_pipe[0] && !pad_pipe[0][0];

assign psum_buf0_read_addr = col_pipe[0];
assign psum_buf1_read_addr = col_pipe[0];
assign psum_buf2_read_addr = col_pipe[0];
assign psum_buf3_read_addr = col_pipe[0];

//----------------------------------------------------------------------------
// STG 1
reg [PSUM_DW-1:0] psum0, psum1, psum2, psum3;

always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin 
        psum0 <= 0;
        psum1 <= 0;
        psum2 <= 0;
        psum3 <= 0;
    end else begin 
        // is first chn
        if (vld_pipe[1]) begin 
            if (pad_pipe[1][0]) begin 
                psum0 <= $signed(data_pipe[1][0*PSUM_DW+:PSUM_DW]) + $signed(bias0);
                psum1 <= $signed(data_pipe[1][1*PSUM_DW+:PSUM_DW]) + $signed(bias1);
                psum2 <= $signed(data_pipe[1][2*PSUM_DW+:PSUM_DW]) + $signed(bias2);
                psum3 <= $signed(data_pipe[1][3*PSUM_DW+:PSUM_DW]) + $signed(bias3);
            end else begin 
                psum0 <= $signed(data_pipe[1][0*PSUM_DW+:PSUM_DW]) + $signed(psum_buf0_read_data);
                psum1 <= $signed(data_pipe[1][1*PSUM_DW+:PSUM_DW]) + $signed(psum_buf1_read_data);
                psum2 <= $signed(data_pipe[1][2*PSUM_DW+:PSUM_DW]) + $signed(psum_buf2_read_data);
                psum3 <= $signed(data_pipe[1][3*PSUM_DW+:PSUM_DW]) + $signed(psum_buf3_read_data);
            end
        end
    end
end
//----------------------------------------------------------------------------
// STG 2
// data is vld & not last channel
assign psum_buf0_wea = vld_pipe[2] && !pad_pipe[2][1];
assign psum_buf1_wea = vld_pipe[2] && !pad_pipe[2][1];
assign psum_buf2_wea = vld_pipe[2] && !pad_pipe[2][1];
assign psum_buf3_wea = vld_pipe[2] && !pad_pipe[2][1];

assign psum_buf0_addra = col_pipe[2];
assign psum_buf1_addra = col_pipe[2];
assign psum_buf2_addra = col_pipe[2];
assign psum_buf3_addra = col_pipe[2];

assign psum_buf0_dia = psum0;
assign psum_buf1_dia = psum1;
assign psum_buf2_dia = psum2;
assign psum_buf3_dia = psum3;


// OFM output (last)
wire [PSUM_DW-1:0] psum_act0 = (vld_pipe[2] && pad_pipe[2][1]) ? ((psum0[PSUM_DW-1]==1) ? 0 : psum0) : 0;
wire [PSUM_DW-1:0] psum_act1 = (vld_pipe[2] && pad_pipe[2][1]) ? ((psum1[PSUM_DW-1]==1) ? 0 : psum1) : 0;
wire [PSUM_DW-1:0] psum_act2 = (vld_pipe[2] && pad_pipe[2][1]) ? ((psum2[PSUM_DW-1]==1) ? 0 : psum2) : 0;
wire [PSUM_DW-1:0] psum_act3 = (vld_pipe[2] && pad_pipe[2][1]) ? ((psum3[PSUM_DW-1]==1) ? 0 : psum3) : 0;

wire [PSUM_DW-1:0] shr0 = psum_act0 >> scale0; 
wire [PSUM_DW-1:0] shr1 = psum_act1 >> scale1;
wire [PSUM_DW-1:0] shr2 = psum_act2 >> scale2;
wire [PSUM_DW-1:0] shr3 = psum_act3 >> scale3;

wire [OUT_DW-1:0] scaled0 = (|shr0[PSUM_DW-1:OUT_DW]) ? {OUT_DW{1'b1}} : shr0[OUT_DW-1:0];
wire [OUT_DW-1:0] scaled1 = (|shr1[PSUM_DW-1:OUT_DW]) ? {OUT_DW{1'b1}} : shr1[OUT_DW-1:0];
wire [OUT_DW-1:0] scaled2 = (|shr2[PSUM_DW-1:OUT_DW]) ? {OUT_DW{1'b1}} : shr2[OUT_DW-1:0];
wire [OUT_DW-1:0] scaled3 = (|shr3[PSUM_DW-1:OUT_DW]) ? {OUT_DW{1'b1}} : shr3[OUT_DW-1:0];


always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin 
        o_pp_data <= 0;
        o_pp_data_vld <= 0;
    end else begin
        if (pad_pipe[2][1]) begin 
            // scale
            o_pp_data <= {scaled3, scaled2, scaled1, scaled0};
            o_pp_data_vld <= 1'b1;
        end else begin 
            o_pp_data <= 0;
            o_pp_data_vld <= 0;
        end
    end
end
//----------------------------------------------------------------------------
// address calculation pipe
reg [OFM_AW-1:0] ofm_addr_pipe [0:STG-1];


always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin 
        o_pp_addr <= 0;
        for (i = 0; i < STG; i = i + 1) begin 
            ofm_addr_pipe[i] <= 0;
        end
    end else begin
        ofm_addr_pipe[0] <= {{(OFM_AW-W_SIZE){1'b0}}, pe_row_i};
        ofm_addr_pipe[1] <= ($unsigned(ofm_addr_pipe[0]) * $unsigned(q_width) + {{(OFM_AW-W_SIZE){1'b0}}, col_pipe[0]});
        ofm_addr_pipe[2] <= (pad_pipe[1][1]) ? ($unsigned(ofm_addr_pipe[1]) * $unsigned(q_channel_out) + {{(OFM_AW-W_CHANNEL){1'b0}}, chn_out_pipe[1]}) : {OFM_AW{1'b0}};
        o_pp_addr        <= ofm_addr_pipe[2];
    end
end

//----------------------------------------------------------------------------
reg [W_SIZE-1:0]    o_pp_row_r, o_pp_col_r;
reg [W_CHANNEL-1:0] o_pp_chn_out_r;


always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin 
        o_pp_row_r <= 0;
        o_pp_col_r <= 0;
        o_pp_chn_out_r <= 0;
    end else begin 
        o_pp_row_r <= row_pipe[STG-1];
        o_pp_col_r <= col_pipe[STG-1];
        o_pp_chn_out_r <= chn_out_pipe[STG-1];
    end
end

assign o_pp_row     = o_pp_data_vld ? o_pp_row_r : 0;
assign o_pp_col     = o_pp_data_vld ? o_pp_col_r : 0;
assign o_pp_chn_out = o_pp_data_vld ? o_pp_chn_out_r : 0;


endmodule