`timescale 1ns / 1ps
`include "controller_params.vh"

module postprocessor #(
    parameter W_SIZE        = `W_SIZE,
    parameter W_CHANNEL     = `W_CHANNEL,
    parameter Tout          = `Tout,

    parameter PSUM_DW   = `W_PSUM,   // psum bitwidth
    parameter BIAS_DW   = `BIAS_DW,   // bias bitwidth
    parameter SCALES_DW = `SCALES_DW,
    parameter W_OUT    = `W_DATA,     // 8; final output bitwidth

    parameter OFM_DW = `FM_BUFFER_DW,
    parameter OFM_AW = `FM_BUFFER_AW,
    parameter OFM_DEPTH = `FM_BUFFER_DEPTH,

    parameter PE_ACCO_FLAT_BW = `PE_ACCO_FLAT_BW
)(
    input  wire                  clk,
    input  wire                  rstn,

    
    // postprocessor <-> top
    input  wire [4:0]               q_layer,
    
    input  wire [W_SIZE-1:0]        q_width,
    input  wire [W_SIZE-1:0]        q_height,
    input  wire [W_CHANNEL-1:0]     q_channel,      // tiled
    input  wire [W_CHANNEL-1:0]     q_channel_out,  // tiled


    // postprocessor <-> AXI
    // load bias, scales


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


// for debugging
localparam PSUM_DEPTH  = 65536; //
localparam PSUM_AW     = $clog2(PSUM_DEPTH); //

reg [PSUM_DW-1:0] psumbuf [PSUM_DEPTH-1:0]; // dbg 

wire [PSUM_DW-1:0] acc_arr [0:Tout-1];

genvar g;
generate
    for (g = 0; g < Tout; g = g + 1) begin : UNPACK_ACC
        assign acc_arr[g] = pe_data_i[(g+1)*PSUM_DW-1 -: PSUM_DW];
    end
endgenerate

reg [PSUM_AW-1:0] base_addr;

integer i;
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


endmodule