`timescale 1ns / 1ps
`include "controller_params.vh"


module ifm_buf_manager #(
    parameter W_SIZE        = `W_SIZE,
    
    parameter IFM_BUF_CNT   = `IFM_BUFFER_CNT,      // 4
    parameter W_IFM_BUF     = `IFM_BUFFER           // 2
)(
    input  wire               clk,
    input  wire               rstn,

    // Controller <-> Buffer Manager
    input  wire                 m_req_load,         // new row load request
    input  wire [W_SIZE-1:0]    m_req_row,          // req row idx
    output reg                  o_req_done,         // req done signal

    // TODO
    // Buffer <-> Buffer Manager
    input  wire [IFM_BUF_CNT-1:0]   m_buf_done,     // signal from each buffer
    output reg  [IFM_BUF_CNT-1:0]   o_buf_sel,      // buffer select to load row
    output reg  [W_SIZE-1:0]        o_buf_row,      // DRAM address to load data from 

    // TODO
    // conv_pe <-> Buffer Manager
    input  wire               req_use
);

localparam  EMPTY   = 2'd0, 
            LOADING = 2'd1, 
            READY   = 2'd2, 
            IN_USE  = 2'd3;

reg [1:0] state [0:N_BUF-1];

reg [W_SIZE-1:0]        row_in_buf [0:IFM_BUF_CNT-1];   // track 
reg [IFM_BUFFER-1:0]     tail_ptr, head_ptr;            // circular buffer pointer

integer j;

// State register
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        for (j = 0; j < IFM_BUF_CNT; j = j + 1)
            state[j] <= EMPTY;
    end

end