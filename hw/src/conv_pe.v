`timescale 1ns / 1ps
`include "controller_params.vh"


module conv_pe #(


    parameter K             = `K,               // kernel size

    parameter W_DATA        = `W_DATA,               // feature map bitwidth
    parameter W_KERNEL      = `W_KERNEL,               // kernel bitwidth
    parameter W_PSUM        = `W_PSUM,              // partial sum bitwidth

    parameter Tin           = `Tin,
    parameter Tout          = `Tout,

    parameter W_SIZE        = `W_SIZE,
    parameter W_CHANNEL     = `W_CHANNEL,
    parameter W_FRAME_SIZE  = `W_FRAME_SIZE,
    parameter W_DELAY       = `W_DELAY,

    parameter IFM_DW        = `IFM_DW,                  // 32
    parameter FILTER_DW     = `FILTER_DW,               // 72
    
    parameter IFM_BUF_CNT   = `IFM_BUFFER_CNT,      // 4
    parameter W_IFM_BUF     = `IFM_BUFFER,           // 2
    
    parameter BM_DATA_DELAY = `BM_DATA_DELAY,
    parameter MAC_DELAY     = `MAC_DELAY
)(
    input  wire                         clk,
    input  wire                         rstn,
    
    input  wire                      c_ctrl_data_run,

    // no use?
    input  wire                         c_ctrl_pesync_run,
    input  wire                         c_ctrl_pesync_cnt,
    //

    input  wire [W_SIZE-1:0]         c_row,
    input  wire [W_SIZE-1:0]         c_col,
    input  wire [W_CHANNEL-1:0]      c_chn,

    input  wire                     c_is_first_row,
    input  wire                     c_is_last_row,
    input  wire                     c_is_first_col,
    input  wire                     c_is_last_col,

    /**
    * Signals connected to `buffer manager` and buffers.
    * Once valid signal asserted, `buffer manager` outputs data 
    * after `BM_DATA_DELAY` cycles.
    */

    // IFM BUFFER
    output wire [K-1:0]                  o_ifm_req_vld,
    output wire [W_SIZE-1:0]             o_ifm_req_row [0:K-1], 
    output wire [W_SIZE-1:0]             o_ifm_req_col [0:K-1],
    output wire [W_SIZE-1:0]             o_ifm_req_chn [0:K-1],

    input  wire [IFM_DW-1:0]             bm_ifm_data [0:K-1],

    // FILTER BUFFER 
    output wire                          o_filter_req_vld,
    output wire [W_CHANNEL-1:0]          o_filter_req_inchn,

    input  wire [FILTER_DW-1:0]          bm_filter_data [0:Tout-1],


    output wire                          o_pe_done
);


localparam STG = BM_DATA_DELAY + MAC_DELAY;


reg [K-1:0]             ifm_req_vld;
reg [W_SIZE-1:0]        ifm_req_row [0:K-1]; 
reg [W_SIZE-1:0]        ifm_req_col [0:K-1];
reg [W_SIZE-1:0]        ifm_req_chn [0:K-1];

reg                     filter_req_vld;
reg [W_CHANNEL-1:0]     filter_req_inchn;



reg [IFM_DW-1:0]        in_img [0:K*K-1];
reg [FILTER_DW-1:0]     filter [0:Tout-1];

// pipes
reg [W_SIZE-1:0]        row_pipe [0:STG-1];
reg [W_SIZE-1:0]        col_pipe [0:STG-1];
reg [W_CHANNEL-1:0]     chn_pipe [0:STG-1];

reg [BM_DATA_DELAY-1:0] is_first_row_pipe;
reg [BM_DATA_DELAY-1:0] is_last_row_pipe;
reg [BM_DATA_DELAY-1:0] is_first_col_pipe;
reg [BM_DATA_DELAY-1:0] is_last_col_pipe;

reg [STG-1:0]           output_vld_pipe;

reg [BM_DATA_DELAY-1:0] reuse_filter_pipe;

wire reuse_filter = (chn_pipe[0] == c_chn);


integer i, j;


// IFM shift, FILTER
always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin
        // in_img reset
        for (i = 0; i < K; i = i + 1) begin
            for (j = 0; j < K; j = j + 1) begin
                in_img[i*K+j] <= {IFM_DW{1'b0}};
            end
        end

        // filter reset
        for (i = 0; i < Tout; i = i + 1) begin
            filter[i] <= {FILTER_DW{1'b0}};
        end
    end
    else if (ctrl_data_run) begin 
        for (i=0; i<K; i=i+1) begin 
            in_img[i*K+K-1] <= bm_ifm_data[i];
        end

        for (i = 0; i < K; i = i + 1) begin 
            for (j = 0; j < K - 1; j = j + 1) begin 
                in_img[i*K+j] <= in_img[i*K+j+1];
            end
        end

        if (!reuse_filter_pipe[BM_DATA_DELAY-1]) begin 
            for (i = 0; i < Tout; i = i + 1) begin 
                filter[i] <= bm_filter_data[i];
            end
        end
    end
end


// pipeline
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        // pipe reset
        for (i = 0; i < STG; i = i + 1) begin
            row_pipe[i] <= {W_SIZE{1'b0}};
            col_pipe[i] <= {W_SIZE{1'b0}};
            chn_pipe[i] <= {W_CHANNEL{1'b0}};
        end

        for (i = 0; i < BM_DATA_DELAY; i = i + 1) begin
            is_first_row_pipe[i] <= 1'b0;
            is_last_row_pipe[i]  <= 1'b0;
            is_first_col_pipe[i] <= 1'b0;
            is_last_col_pipe[i]  <= 1'b0;
        end
        
        for (i = 0; i < BM_DATA_DELAY; i = i + 1) begin 
            reuse_filter_pipe[i] <= 1'b0;
        end

        for (i = 0; i < STG; i = i + 1) begin 
            output_vld_pipe[i] <= 1'b0;
        end

        o_ifm_req_vld    <= 1'b0;
        o_filter_req_vld <= 1'b0;
        o_pe_done        <= 1'b0;
    end

    else begin
        row_pipe[0] <= c_row;
        col_pipe[0] <= c_col;
        chn_pipe[0] <= c_chn;

        is_first_row_pipe[0] <= c_is_first_row;
        is_last_row_pipe[0]  <= c_is_last_row;
        is_first_col_pipe[0] <= c_is_first_col;
        is_last_col_pipe[0]  <= c_is_last_col;

        reuse_filter_pipe[0] <= reuse_filter;

        output_vld_pipe[0] <= c_ctrl_data_run;


        // pipe
        for (i = 0; i < STG-1; i = i + 1) begin 
            row_pipe[i+1] <= row_pipe[i];
            col_pipe[i+1] <= col_pipe[i];
            chn_pipe[i+1] <= chn_pipe[i];
        end

        for (i=0; i<BM_DATA_DELAY-1; i=i+1) begin 
            is_first_row_pipe[i+1]  <= is_first_row_pipe[i];
            is_last_row_pipe[i+1]   <= is_last_row_pipe[i];
            is_first_col_pipe[i+1]  <= is_first_col_pipe[i];
            is_last_col_pipe[i+1]   <= is_last_col_pipe[i];
        end

        for (i=0; i<STG-1; i=i+1) begin 
            output_vld_pipe[i+1] <= output_vld_pipe[i];
        end

        for (i = 0; i < BM_DATA_DELAY - 1 ; i = i + 1) begin 
            reuse_filter_pipe[i+1] <= reuse_filter_pipe[i];
        end
    end
end


// IFM request
always @(posedge clk or negedge rstn) begin 
    for (i = 0; i < K; i = i + 1) begin 
        ifm_req_vld[i] <= 1'b0;
    end

    if (c_ctrl_data_run) begin 
        for (i = 0; i < K; i = i + 1) begin 
            ifm_req_col[i] <= c_col;
            ifm_req_chn[i] <= c_chn;
        end
        // hard coded
        ifm_req_row[0] <= c_is_first_row ? {W_SIZE{1'b0}} : c_row - 1;
        ifm_req_row[1] <= c_row;
        ifm_req_row[2] <= c_is_last_row ? {W_SIZE{1'b0}} : c_row + 1;

        ifm_req_vld[0] <= c_is_first_row ? 1'b0 : 1'b1;
        ifm_req_vld[1] <= 1'b1;
        ifm_req_vld[2] <= c_is_last_row ? 1'b0 : 1'b1;
    end
end

// FILTER request
always @(posedge clk or negedge rstn) begin 
    filter_req_vld <= 1'b0;
    
    if (c_ctrl_data_run && !reuse_filter) begin
        filter_req_inchn <= c_chn;
        filter_req_vld <= 1'b1;
    end
end


// 16 macs









assign o_ifm_req_vld = ifm_req_vld;
assign o_ifm_req_row = ifm_req_row;
assign o_ifm_req_col = ifm_req_col;
assign o_ifm_req_chn = ifm_req_chn;

assign o_filter_req_vld = filter_req_vld;
assign o_filter_req_inchn = filter_req_inchn;

// o_pe_done: every calculation done
// assign o_pe_done = 


endmodule
