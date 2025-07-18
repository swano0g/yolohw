`timescale 1ns / 1ps
`include "controller_params.vh"


module cnn_ctrl #(
    parameter W_SIZE        = `W_SIZE,
    parameter W_CHANNEL     = `W_CHANNEL,
    parameter W_FRAME_SIZE  = `W_FRAME_SIZE,
    parameter W_DELAY       = `W_DELAY,
    
    parameter IFM_BUF_CNT   = `IFM_BUFFER_CNT,      // 4
    parameter W_IFM_BUF     = `W_IFM_BUFFER         // 2
)(
    input  wire                     clk,
    input  wire                     rstn,
    // Inputs
    // buffer synchronization signals
    input  wire [IFM_BUF_CNT-1:0]   q_ifm_buf_done,
    
    input  wire                     q_filter_buf_done,
    //
    input  wire [W_SIZE-1:0]        q_width,
    input  wire [W_SIZE-1:0]        q_height,
    input  wire [W_CHANNEL-1:0]     q_channel,          // !!!TILED input CHANNEL!!!
    input  wire [W_FRAME_SIZE-1:0]  q_frame_size,
    input  wire                     q_start,
    // Outputs
    output wire                     o_ctrl_vsync_run,
    output wire [W_DELAY-1:0]       o_ctrl_vsync_cnt,
    output wire                     o_ctrl_hsync_run,
    output wire [W_DELAY-1:0]       o_ctrl_hsync_cnt,
    output wire                     o_ctrl_data_run,
    output wire [W_SIZE-1:0]        o_row,
    output wire [W_SIZE-1:0]        o_col,
    output wire [W_CHANNEL-1:0]     o_chn,
    output wire [W_FRAME_SIZE-1:0]  o_data_count,
    output wire                     o_end_frame
);

// FSM states
localparam ST_IDLE   = 2'b00,
           ST_VSYNC  = 2'b01,
           ST_HSYNC  = 2'b10,
           ST_DATA   = 2'b11;

reg [1:0]  cstate, nstate;
reg        ctrl_vsync_run;
reg [W_DELAY-1:0] ctrl_vsync_cnt;
reg        ctrl_hsync_run;
reg [W_DELAY-1:0] ctrl_hsync_cnt;
reg        ctrl_data_run;

reg [W_SIZE-1:0]        row;
reg [W_SIZE-1:0]        col;
reg [W_CHANNEL-1:0]     chn; 
reg [W_FRAME_SIZE-1:0]  data_count;
wire                    end_frame;

wire [W_IFM_BUF-1:0]    next_buf_id = (row + 1'b1);


// State register
always @(posedge clk or negedge rstn) begin
    if (!rstn) cstate <= ST_IDLE;
    else       cstate <= nstate;
end

// Next-state logic
always @(*) begin
    case (cstate)
        ST_IDLE:  
            nstate = q_start ? ST_VSYNC : ST_IDLE;
        ST_VSYNC: 
            nstate = q_filter_buf_done ? ST_HSYNC : ST_VSYNC;
        ST_HSYNC: 
            nstate = 
                (row == q_height-1) ? ST_DATA :
                q_ifm_buf_done[next_buf_id] ? ST_DATA : 
                ST_HSYNC;
        ST_DATA:  
            nstate = 
                end_frame ? ST_IDLE : 
                (chn == q_channel-1 && col == q_width-1) ? ST_HSYNC : 
                ST_DATA;
        default:  
            nstate = ST_IDLE;
    endcase
end


// Output enables
always @(*) begin
    ctrl_vsync_run = 1'b0;
    ctrl_hsync_run = 1'b0;
    ctrl_data_run  = 1'b0;
    case (cstate)
        ST_VSYNC: ctrl_vsync_run = 1'b1;
        ST_HSYNC: ctrl_hsync_run = 1'b1;
        ST_DATA:  ctrl_data_run  = 1'b1;
    endcase
end

// VSYNC / HSYNC counters
// may not use
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        ctrl_vsync_cnt <= 0;
        ctrl_hsync_cnt <= 0;
    end else begin
        // VSYNC
        if (ctrl_vsync_run) ctrl_vsync_cnt <= ctrl_vsync_cnt + 1;
        else                ctrl_vsync_cnt <= 0;
        // HSYNC
        if (ctrl_hsync_run) ctrl_hsync_cnt <= ctrl_hsync_cnt + 1;
        else                ctrl_hsync_cnt <= 0;
    end
end

// (tiled!! input) channel counter
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        chn <= 0;
    end else if (ctrl_data_run) begin
        if (chn == q_channel - 1)
            chn <= 0;
        else
            chn <= chn + 1;
    end
end

// row & col counter
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        row <= 0;
        col <= 0;
    // row & col update only when last channel 
    end else if (ctrl_data_run && chn == q_channel - 1) begin
        // last column
        if (col == q_width - 1) begin
            // end of frame
            if (end_frame) begin
                row <= 0;
                col <= 0;
            // next row
            end else begin
                row <= row + 1;
                col <= 0;
            end
        // not last column
        end else begin
            col <= col + 1;
        end
    end
end

// Data count (include channel, actually the number of tiles)
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        data_count <= 0;
    end else if (ctrl_data_run) begin
        if (!end_frame)
            data_count <= data_count + 1;
        else
            data_count <= 0;
    end
end

// End of frame signal
assign end_frame = (data_count == q_frame_size - 1);

// Outputs
assign o_ctrl_vsync_run = ctrl_vsync_run;
assign o_ctrl_vsync_cnt = ctrl_vsync_cnt;
assign o_ctrl_hsync_run = ctrl_hsync_run;
assign o_ctrl_hsync_cnt = ctrl_hsync_cnt;
assign o_ctrl_data_run  = ctrl_data_run;
assign o_row            = row;
assign o_col            = col;
assign o_chn            = chn;
assign o_data_count     = data_count;
assign o_end_frame      = end_frame;

endmodule
