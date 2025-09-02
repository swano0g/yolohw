`include "controller_params.vh"

module addr_sequencer #(
    parameter W_SIZE                = `W_SIZE,
    parameter W_CHANNEL             = `W_CHANNEL,
    parameter W_FRAME_SIZE          = `W_FRAME_SIZE,
    parameter Tin                   = `Tin,
    parameter Tout                  = `Tout,

    parameter IFM_AW                = `FM_BUFFER_AW,
    
    parameter OFM_AW                = `FM_BUFFER_AW
)(
    input                               clk, 
    input                               rstn,


    // Addr Sequencer <-> TOP
    input  wire [W_SIZE-1:0]            q_width,
    input  wire [W_SIZE-1:0]            q_height,
    input  wire [W_CHANNEL-1:0]         q_channel,   
    input  wire [W_CHANNEL-1:0]         q_channel_out,
    input  wire [W_SIZE+W_CHANNEL-1:0]  q_row_stride,   // q_width * q_channel


    input  wire                         q_addr_seq_start,
    output wire                         addr_seq_done,

    input  wire                         q_as_mode,          // 0 -> upsample, 1 -> route

    input  wire [IFM_AW-1:0]            q_route_offset,

    // RD/WR addr 
    output reg                          as_rd_vld,
    output reg  [IFM_AW-1:0]            as_rd_addr,

    // one cycle delay
    output reg                          as_wr_vld,
    output reg  [OFM_AW-1:0]            as_wr_addr
);

// row * (q_width * q_channel) + col * q_channel + chn_out (+ q_row_stride)

//============================================================================
// I. UPSAMPLE
//============================================================================
wire [W_SIZE-1:0]       up_width  = q_width << 1;
wire [W_SIZE-1:0]       up_height = q_height << 1;
wire [W_CHANNEL-1:0]    up_channel = q_channel;


reg                     up_running;
reg  [W_SIZE-1:0]       up_row_counter;
reg  [W_SIZE-1:0]       up_col_counter;
reg  [W_CHANNEL-1:0]    up_chn_counter;


wire                    up_is_last_row = (up_row_counter == up_height - 1);
wire                    up_is_last_col = (up_col_counter == up_width  - 1);
wire                    up_is_last_chn = (up_chn_counter == q_channel - 1);


// Nested counters: chn fastest, then col, then row
always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin 
        up_running     <= 0;
        up_row_counter <= 0;
        up_col_counter <= 0;
        up_chn_counter <= 0;
    end else begin 
        if (up_running) begin
            if (!up_is_last_chn) begin
                up_chn_counter <= up_chn_counter + 1;
            end else begin
                up_chn_counter <= 0;
                if (!up_is_last_col) begin
                    up_col_counter <= up_col_counter + 1;
                end else begin
                    up_col_counter <= 0;
                    if (!up_is_last_row) begin
                        up_row_counter <= up_row_counter + 1;
                    end else begin
                        up_running <= 0;
                    end
                end
            end
        end 
        else begin
            if (q_addr_seq_start) begin
                up_running     <= 1;
                up_row_counter <= 0;
                up_col_counter <= 0;
                up_chn_counter <= 0;
            end
        end
    end
end

//----------------------------------------------------------------------------
// READ ADDRESS
//----------------------------------------------------------------------------
reg  [IFM_AW-1:0]       up_rd_addr;
reg  [IFM_AW-1:0]       up_rd_row_base_addr;
reg                     up_rd_row_2;
reg                     up_rd_col_2;

always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin 
        up_rd_addr          <= 0;
        up_rd_row_base_addr <= 0;
        up_rd_row_2         <= 0;
        up_rd_col_2         <= 0;
    end else begin 
        if (up_running) begin 
            if (!up_is_last_chn) begin
                up_rd_addr <= up_rd_addr + 1;
            end else begin 
                if (up_rd_col_2 == 0) begin 
                    up_rd_col_2 <= 1;
                    up_rd_addr <= up_rd_addr;
                end else begin 
                    up_rd_col_2 <= 0;
                    
                    if (!up_is_last_col) begin 
                        up_rd_addr <= up_rd_addr + 1;
                    end else begin 
                        if (up_rd_row_2 == 0) begin 
                            up_rd_row_2 <= 1;
                            up_rd_addr <= up_rd_row_base_addr;
                        end else begin 
                            up_rd_row_2 <= 0;
                            if (!up_is_last_row) begin 
                                up_rd_addr <= up_rd_addr + 1;
                            end else begin 
                                up_rd_row_base_addr <= up_rd_row_base_addr + q_row_stride;
                            end
                        end
                    end
                end
            end
        end else begin 
            up_rd_addr          <= 0;
            up_rd_row_base_addr <= 0;
            up_rd_row_2         <= 0;
            up_rd_col_2         <= 0;
        end
    end
end


//----------------------------------------------------------------------------
// WRITE ADDRESS
//----------------------------------------------------------------------------
reg  [OFM_AW-1:0]       up_wr_addr;
wire [W_CHANNEL-1:0]    up_wr_offset = q_channel_out - q_channel;


always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin 
        up_wr_addr <= 0;
    end else begin 
        if (up_running) begin 
            if (up_is_last_chn) begin 
                up_wr_addr <= up_wr_addr + up_wr_offset;
            end else begin 
                up_wr_addr <= up_wr_addr + 1;
            end
        end
    end
end



//============================================================================
// II. ROUTE
//============================================================================

endmodule