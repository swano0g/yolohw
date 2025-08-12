`timescale 1ns / 1ps
`include "controller_params.vh"


module cnn_ctrl #(
    parameter W_SIZE        = `W_SIZE,
    parameter W_CHANNEL     = `W_CHANNEL,
    parameter W_FRAME_SIZE  = `W_FRAME_SIZE,
    parameter W_DELAY       = `W_DELAY
)(
    input  wire                     clk,
    input  wire                     rstn,
    
    // INPUTS


    //
    input  wire [W_SIZE-1:0]        q_width,
    input  wire [W_SIZE-1:0]        q_height,
    input  wire [W_CHANNEL-1:0]     q_channel,          // TILED input CHANNEL!!!
    input  wire [W_CHANNEL-1:0]     q_channel_out,      // TILED output channel
    input  wire [W_FRAME_SIZE-1:0]  q_frame_size,
    input  wire                     q_start,

    // buffer manager
    input  wire                     fb_load_done,
    input  wire                     pb_sync_done,
    
    output wire                     o_fb_load_req,

    // OUTPUTS
    output wire                     o_ctrl_csync_run,   // synchronize cout
    output wire                     o_ctrl_psync_run,   // synchronize psum
    output wire                     o_ctrl_data_run,    // calculate

    output wire                     o_layer_done,
    
    output wire                     o_is_first_row,
    output wire                     o_is_last_row,
    output wire                     o_is_first_col,
    output wire                     o_is_last_col,
    output wire                     o_is_first_chn,
    output wire                     o_is_last_chn,
    
    output wire [W_SIZE-1:0]        o_row,
    output wire [W_SIZE-1:0]        o_col,
    output wire [W_CHANNEL-1:0]     o_chn,
    output wire [W_CHANNEL-1:0]     o_chn_out
);

// FSM states
localparam ST_IDLE   = 2'd0,
           ST_CSYNC  = 2'd1,
           ST_PSYNC  = 2'd2,
           ST_DATA   = 2'd3;


reg [1:0]  cstate, nstate;
reg        ctrl_csync_run;
reg        ctrl_psync_run;
reg        ctrl_data_run;
reg        layer_done;

reg [W_SIZE-1:0]        row;
reg [W_SIZE-1:0]        col;
reg [W_CHANNEL-1:0]     chn; 
reg [W_CHANNEL-1:0]     chn_out; 
reg [W_FRAME_SIZE-1:0]  data_count;


reg filter_load_req;



// pad signals
wire                    end_frame = (data_count == q_frame_size - 1);

wire                    is_first_row     = (row == 0) ? 1'b1: 1'b0;
wire                    is_last_row      = (row == q_height-1) ? 1'b1: 1'b0;
wire                    is_first_col     = (col == 0) ? 1'b1: 1'b0;
wire                    is_last_col      = (col == q_width-1) ? 1'b1 : 1'b0;
wire                    is_first_chn     = (chn == 0) ? 1'b1: 1'b0;
wire                    is_last_chn      = (chn == q_channel-1) ? 1'b1 : 1'b0;

wire                    is_first_chn_out = (chn_out == 0) ? 1'b1: 1'b0;
wire                    is_last_chn_out  = (chn_out == q_channel_out-1) ? 1'b1 : 1'b0;


// State register
always @(posedge clk or negedge rstn) begin
    if (!rstn) cstate <= ST_IDLE;
    else       cstate <= nstate;
end

// Next-state logic
always @(*) begin
    case (cstate)
        ST_IDLE:  
            nstate = q_start ? ST_CSYNC : ST_IDLE;
        ST_CSYNC: 
            nstate = fb_load_done ? ST_DATA : ST_CSYNC;
        ST_PSYNC: 
            nstate = pb_sync_done ? ST_IDLE : ST_PSYNC;
        ST_DATA:  
            nstate = 
                end_frame && is_last_chn_out ? ST_PSYNC : 
                end_frame                    ? ST_CSYNC :
                                               ST_DATA  ;
        default:  
            nstate = ST_IDLE;
    endcase
end


// Output enables
always @(*) begin
    ctrl_csync_run  = 1'b0;
    ctrl_psync_run  = 1'b0;
    ctrl_data_run   = 1'b0;
    case (cstate)
        ST_CSYNC:   ctrl_csync_run = 1'b1;
        ST_PSYNC:   ctrl_psync_run = 1'b1;
        ST_DATA:    ctrl_data_run  = 1'b1;
    endcase
end

// Nested counters: col fastest, then chn, then row, then chn_out
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        chn_out <= 0;
        row <= 0;
        chn <= 0;
        col <= 0;
    end else if (ctrl_data_run) begin
        if (end_frame) begin
            chn_out <= is_last_chn_out ? 0 : chn_out + 1;
            row     <= 0;
            chn     <= 0;
            col     <= 0;
        end
        else begin
            if (col < q_width - 1) begin
                col <= col + 1;
            end else begin
                col <= 0;
                if (chn < q_channel - 1) begin
                    chn <= chn + 1;
                end else begin
                    chn <= 0;
                    if (row < q_width - 1)
                        row <= row + 1;
                    else
                        col <= 0;
                end
            end
        end
    end
end


// Data count
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


// Buffer
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        filter_load_req <= 0;
    end
    else begin
        if (cstate != ST_CSYNC && nstate == ST_CSYNC)
            filter_load_req <= 1;
        else
            filter_load_req <= 0;
    end
end


// End signal
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        layer_done <= 0;
    end
    else begin
        if (cstate == ST_PSYNC && nstate == ST_IDLE)
            layer_done <= 1;
    end
end


// Outputs
assign o_ctrl_csync_run = ctrl_csync_run;
assign o_ctrl_psync_run = ctrl_psync_run;
assign o_ctrl_data_run  = ctrl_data_run;
assign o_row            = row;
assign o_col            = col;
assign o_chn            = chn;
assign o_chn_out        = chn_out;
// assign o_data_count     = data_count;
// assign o_end_frame      = end_frame;
assign o_layer_done     = layer_done;

assign o_is_first_row   = is_first_row;
assign o_is_last_row    = is_last_row;
assign o_is_first_col   = is_first_col;
assign o_is_last_col    = is_last_col;
assign o_is_first_chn   = is_first_chn;
assign o_is_last_chn    = is_last_chn;

assign o_fb_load_req      = filter_load_req;

endmodule
