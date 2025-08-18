`timescale 1ns / 1ps
`include "controller_params.vh"

module postprocessor #(
    parameter W_SIZE        = `W_SIZE,
    parameter W_CHANNEL     = `W_CHANNEL,
    parameter PSUM_DW   = `W_PSUM,   // psum bitwidth
    parameter BIAS_DW   = `BIAS_DW,   // bias bitwidth
    parameter SCALES_DW = `SCALES_DW,
    parameter W_OUT    = `W_DATA,     // final output bitwidth

    parameter OFM_BUF_DW = ,
    parameter OFM_BUF_AW = ,

    parameter PE_ACCO_FLAT_BW = `PE_ACCO_FLAT_BW
)(
    input  wire                  clk,
    input  wire                  rstn,

    
    // postprocessor <-> top
    input  wire [4:0]               q_layer,

    // postprocessor <-> AXI
    // load bias, scales


    // postprocessor <-> pe_engine
    input  wire [PE_ACCO_FLAT_BW-1:0]   pe_data_i,
    input  wire                         pe_vld_i, 
    input  wire [W_SIZE-1:0]            pe_row_i,
    input  wire [W_SIZE-1:0]            pe_col_i,
    input  wire [W_CHANNEL-1:0]         pe_chn_i,
    input  wire [W_CHANNEL-1:0]         pe_chn_out_i,

    // postprocessor <-> buffer_manager
    output wire
    
);



endmodule