`timescale 1ns / 1ps
`include "controller_params.vh"


module conv_pe #(
    parameter W_SIZE        = `W_SIZE,
    parameter W_CHANNEL     = `W_CHANNEL,
    parameter W_FRAME_SIZE  = `W_FRAME_SIZE,
    parameter W_DELAY       = `W_DELAY,
    
    parameter IFM_BUF_CNT   = `IFM_BUFFER_CNT,      // 4
    parameter W_IFM_BUF     = `IFM_BUFFER           // 2
)(
    input  wire                         clk,
    input  wire                         rstn,
    
    input  wire                      c_ctrl_data_run,
    input  wire [W_SIZE-1:0]         c_row,
    input  wire [W_SIZE-1:0]         c_col,
    input  wire [W_CHANNEL-1:0]      c_chn
);

endmodule
