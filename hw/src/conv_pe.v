`timescale 1ns / 1ps
`include "controller_params.vh"


module conv_pe #(


    parameter K             = `K,               // kernel size

    parameter W_DATA        = `W_DATA,               // feature map bitwidth
    parameter W_KERNEL      = `W_KERNEL,               // kernel bitwidth
    parameter W_PSUM        = `W_PSUM,              // partial sum bitwidth


    parameter W_SIZE        = `W_SIZE,
    parameter W_CHANNEL     = `W_CHANNEL,
    parameter W_FRAME_SIZE  = `W_FRAME_SIZE,
    parameter W_DELAY       = `W_DELAY,

    parameter IFM_DW        = `IFM_DW,                  // 32
    parameter FILTER_DW     = `FILTER_DW,               // 72
    
    parameter IFM_BUF_CNT   = `IFM_BUFFER_CNT,      // 4
    parameter W_IFM_BUF     = `IFM_BUFFER,           // 2

    parameter Tin           = `Tin,
    parameter Tout          = `Tout
)(
    input  wire                         clk,
    input  wire                         rstn,
    
    input  wire                      c_ctrl_data_run,
    input  wire                         c_ctrl_pesync_run,
    input  wire                         c_ctrl_pesync_cnt,
    input  wire [W_SIZE-1:0]         c_row,
    input  wire [W_SIZE-1:0]         c_col,
    input  wire [W_CHANNEL-1:0]      c_chn,

    /**
    * Signals connected to `buffer manager` and buffers.
    * Once valid signal asserted, `buffer manager` outputs data 
    * after `BM_DATA_DELAY` cycles.
    */

    // IFM BUFFER
    output reg                          o_ifm_req_vld;
    output reg [W_SIZE-1:0]             o_ifm_req_row [K-1:0]; 
    output reg [W_SIZE-1:0]             o_ifm_req_col [K-1:0];
    output reg [W_SIZE-1:0]             o_ifm_req_chn [K-1:0];

    input wire [IFM_DW-1:0]             c_ifm_data [K-1:0];

    // FILTER BUFFER 
    output reg                          o_filter_req_vld;
    output reg [W_CHANNEL-1:0]          o_filter_req_inchn  [Tout-1:0];

    input wire [FILTER_DW-1:0]          c_filter_ifm_data [Tout-1:0];



    output reg                          o_pe_done
);


reg [IFM_DW-1:0]        in_img [0:K-1][0:K-1];
reg [FILTER_DW-1:0]     filter [0:Tout-1];


always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        for (i = 0; i < K; i = i + 1)
            for (j = 0; j < K; j = j + 1)
                in_img[i][j] <= {IFM_DW{1'b0}};
        for (i = 0; i < Tout; i = i + 1)
            filter[i] <= {FILTER_DW{1'b0}};
        o_pe_done <= 1'b0;
    end
    else begin
        in_img[0][0] <= in_img[0][1];

    end
end



always @(posedge clk or negedge rstn) begin
    if (c_ctrl_pesync_run) begin 

    end
end

endmodule
