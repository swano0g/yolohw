`timescale 1ns / 1ps
`include "controller_params.vh"


module cnn_ctrl #(
    parameter W_SIZE        = `W_SIZE,
    parameter W_CHANNEL     = `W_CHANNEL,
    parameter W_FRAME_SIZE  = `W_FRAME_SIZE,
    parameter W_DELAY       = `W_DELAY,
    
    parameter IFM_BUF_CNT   = `IFM_BUFFER_CNT,      // 4
    parameter W_IFM_BUF     = `IFM_BUFFER           // 2
)(
    input  wire                     clk,
    input  wire                     rstn,
    // INPUTS
    // buffer manager
    input  wire                     q_ifm_buf_done,     // connect with o_req_done
    input  wire                     q_filter_buf_done,
    
    // PE
    input  wire                     q_pe_done,          

    //
    input  wire [W_SIZE-1:0]        q_width,
    input  wire [W_SIZE-1:0]        q_height,
    input  wire [W_CHANNEL-1:0]     q_channel,          // !!!TILED input CHANNEL!!!
    input  wire [W_FRAME_SIZE-1:0]  q_frame_size,
    input  wire                     q_start,
    
    // OUTPUTS
    output wire                     o_ctrl_vsync_run,
    output wire [W_DELAY-1:0]       o_ctrl_vsync_cnt,
    output wire                     o_ctrl_hsync_run,
    output wire [W_DELAY-1:0]       o_ctrl_hsync_cnt,
    output wire                     o_ctrl_data_run,

    // buffer connect with Buffer Manager
    output wire                     o_ifm_buf_req_load,
    output wire [W_SIZE-1:0]        o_ifm_buf_req_row,
    //
    
    output wire                     o_is_first_row,
    output wire                     o_is_last_row,
    output wire                     o_is_first_col,
    output wire                     o_is_last_col,
    output wire                     o_is_first_chn,
    output wire                     o_is_last_chn,
    
    output wire [W_SIZE-1:0]        o_row,
    output wire [W_SIZE-1:0]        o_col,
    output wire [W_CHANNEL-1:0]     o_chn,
    output wire [W_FRAME_SIZE-1:0]  o_data_count,
    output wire                     o_end_frame
);

// FSM states
localparam ST_IDLE   = 2'd0,
           ST_VSYNC  = 2'd1,
           ST_HSYNC  = 2'd2,
           ST_DATA   = 2'd3;


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


// buffer control
reg                     ifm_buf_req_load;       // request load
reg [W_SIZE-1:0]        ifm_buf_req_row;        // request row

reg [W_SIZE-1:0]        ifm_loaded_row_plus;   // track which row need to be fetched (0 is not loaded)
reg                     ifm_loading;


wire                    ready_to_calculate = (row + 2 <= ifm_loaded_row_plus);


wire                    end_frame = (data_count == q_frame_size - 1);

wire                    is_first_row = (row == 0) ? 1'b1: 1'b0;
wire                    is_last_row  = (row == q_height-1) ? 1'b1: 1'b0;
wire                    is_first_col = (col == 0) ? 1'b1: 1'b0;
wire                    is_last_col  = (col == q_width-1) ? 1'b1 : 1'b0;
wire                    is_first_chn = (chn == 0) ? 1'b1: 1'b0;
wire                    is_last_chn  = (chn == q_channel-1) ? 1'b1 : 1'b0;


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
            if (ready_to_calculate || is_last_row) begin 
                nstate = ST_DATA;
            end 
            else begin 
                nstate = ST_HSYNC;
            end
        ST_DATA:  
            nstate = 
                end_frame                           ? ST_IDLE   : 
                (is_last_chn && is_last_col)        ? ST_HSYNC  : 
                                                      ST_DATA   ;
        default:  
            nstate = ST_IDLE;
    endcase
end


// Output enables
always @(*) begin
    ctrl_vsync_run  = 1'b0;
    ctrl_hsync_run  = 1'b0;
    ctrl_data_run   = 1'b0;
    case (cstate)
        ST_VSYNC:   ctrl_vsync_run = 1'b1;
        ST_HSYNC:   ctrl_hsync_run = 1'b1;
        ST_DATA:    ctrl_data_run  = 1'b1;
    endcase
end

// VSYNC / HSYNC counters
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        ctrl_vsync_cnt <= 0;
        ctrl_hsync_cnt <= 0;
    end else begin
        // VSYNC
        if (ctrl_vsync_run)     ctrl_vsync_cnt <= ctrl_vsync_cnt + 1;
        else                    ctrl_vsync_cnt <= 0;
        // HSYNC
        if (ctrl_hsync_run)     ctrl_hsync_cnt <= ctrl_hsync_cnt + 1;
        else                    ctrl_hsync_cnt <= 0;
    end
end


// Nested counters: col fastest, then chn, then row
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        row <= 0;
        chn <= 0;
        col <= 0;
    end else if (ctrl_data_run) begin
        if (col != q_width - 1) begin
            col <= col + 1;
        end else begin
            col <= 0;
            if (chn != q_channel - 1) begin
                chn <= chn + 1;
            end else begin
                chn <= 0;
                if (row != q_height - 1)
                    row <= row + 1;
                else
                    row <= 0;
            end
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


// IFM buffer load control

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        ifm_loaded_row_plus  <= 0;
        ifm_loading     <= 0;
    end

    ifm_buf_req_load <= 0;
    ifm_buf_req_row  <= 0;

    if (cstate != ST_IDLE && cstate != ST_VSYNC) begin 
        if (q_ifm_buf_done && ifm_loading) begin
            ifm_loaded_row_plus <= ifm_loaded_row_plus + 1;
            ifm_loading <= 1'b0;
        end
        else if (!ifm_loading && ifm_loaded_row_plus != q_height) begin
            ifm_buf_req_load <= 1'b1;
            ifm_buf_req_row  <= ifm_loaded_row_plus;
            ifm_loading      <= 1'b1; 
        end
    end
end


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

assign o_is_first_row   = is_first_row;
assign o_is_last_row    = is_last_row;
assign o_is_first_col   = is_first_col;
assign o_is_last_col    = is_last_col;
assign o_is_first_chn   = is_first_chn;
assign o_is_last_chn    = is_last_chn;

assign o_ifm_buf_req_row    = ifm_buf_req_row;
assign o_ifm_buf_req_load   = ifm_buf_req_load;

endmodule
