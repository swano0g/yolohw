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


    input  wire                         q_as_start,
    output wire                         o_as_done,

    input  wire                         q_as_mode,          // 0 -> upsample, 1 -> route

    input  wire [IFM_AW-1:0]            q_route_offset,
    input  wire [W_CHANNEL-1:0]         q_route_chn_offset,

    // RD/WR addr 
    output wire                         o_as_rd_vld,
    output wire [IFM_AW-1:0]            o_as_rd_addr,

    // one cycle delay
    output wire                         o_as_wr_vld,
    output wire [OFM_AW-1:0]            o_as_wr_addr
);

//============================================================================
// I. INTERNAL SIGNALS
//============================================================================
localparam  S_UP  = 1'b0,
            S_RTE = 1'b1;

wire m_up  = (q_as_mode == S_UP);
wire m_rte = (q_as_mode == S_RTE);

// sequencer control signal
wire                    c_sequencer_start;  // one cycle pulse;; assign needed
reg                     c_sequencer_vld;
reg                     c_sequencer_done;   // one cycle done pulse
reg                     c_sequencer_done_d; // delayed one cycle done pulse for write

reg                     c_sequencer_running;


wire [W_SIZE-1:0]       c_width   = m_up ? q_width << 1  : q_width;
wire [W_SIZE-1:0]       c_height  = m_up ? q_height << 1 : q_height;
wire [W_CHANNEL-1:0]    c_channel = m_up ? q_channel     : q_channel;


reg  [W_SIZE-1:0]       c_row_counter;
reg  [W_SIZE-1:0]       c_col_counter;
reg  [W_CHANNEL-1:0]    c_chn_counter;

wire                    c_is_last_row = (c_row_counter == c_height  - 1'b1);
wire                    c_is_last_col = (c_col_counter == c_width   - 1'b1);
wire                    c_is_last_chn = (c_chn_counter == c_channel - 1'b1);


// Nested counters: chn fastest, then col, then row
always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin 
        c_sequencer_running <= 0;
        c_sequencer_vld     <= 0;
        c_sequencer_done    <= 0;
        c_row_counter <= 0;
        c_col_counter <= 0;
        c_chn_counter <= 0;
    end else begin 
        c_sequencer_done <= 0;
        if (c_sequencer_running) begin
            c_sequencer_vld <= 1;
            if (!c_is_last_chn) begin
                c_chn_counter <= c_chn_counter + 1;
            end else begin
                c_chn_counter <= 0;
                if (!c_is_last_col) begin
                    c_col_counter <= c_col_counter + 1;
                end else begin
                    c_col_counter <= 0;
                    if (!c_is_last_row) begin
                        c_row_counter <= c_row_counter + 1;
                    end else begin
                        c_sequencer_running <= 0;
                        c_sequencer_vld     <= 0;
                        c_sequencer_done    <= 1;
                    end
                end
            end
        end 
        else begin
            if (c_sequencer_start) begin
                c_sequencer_running <= 1;
                c_sequencer_vld     <= 1;
                c_sequencer_done    <= 0;
                c_row_counter <= 0;
                c_col_counter <= 0;
                c_chn_counter <= 0;
            end
        end
    end
end

always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin 
        c_sequencer_done_d <= 0;
    end else begin 
        c_sequencer_done_d <= c_sequencer_done;
    end
end

//============================================================================
// II. UPSAMPLE
//============================================================================
reg                     up_start;
reg                     up_running;

always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin 
        up_start   <= 0;
        up_running <= 0;
    end else begin 
        up_start <= 0;
        if (m_up && q_as_start) begin 
            up_start   <= 1;
            up_running <= 1;
        end

        if (c_sequencer_done && up_running) begin 
            up_running <= 0;
        end
    end
end
//----------------------------------------------------------------------------
// read address
//----------------------------------------------------------------------------
reg  [IFM_AW-1:0]       up_rd_addr;
reg  [IFM_AW-1:0]       up_rd_row_base_addr;
reg                     up_rd_row_2;
reg                     up_rd_col_2;

wire                    up_rd_vld = up_running && c_sequencer_vld;


always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin 
        up_rd_addr          <= 0;
        up_rd_row_base_addr <= 0;
        up_rd_row_2         <= 0;
        up_rd_col_2         <= 0;
    end else begin 
        if (up_rd_vld) begin 
            if (!c_is_last_chn) begin
                up_rd_addr <= up_rd_addr + 1;
            end else begin 
                if (up_rd_col_2 == 0) begin 
                    up_rd_col_2 <= 1;
                    up_rd_addr <= up_rd_addr - c_channel + 1;
                end else begin 
                    up_rd_col_2 <= 0;
                    
                    if (!c_is_last_col) begin 
                        up_rd_addr <= up_rd_addr + 1;
                    end else begin 
                        if (up_rd_row_2 == 0) begin 
                            up_rd_row_2 <= 1;
                            up_rd_addr <= up_rd_row_base_addr;
                        end else begin 
                            up_rd_row_2 <= 0;
                            if (!c_is_last_row) begin 
                                up_rd_addr <= up_rd_addr + 1;
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
// write address
//----------------------------------------------------------------------------
reg  [OFM_AW-1:0]       up_wr_addr;
wire [W_CHANNEL-1:0]    up_wr_offset = q_channel_out - c_channel + 1;

wire                    up_wr_vld = up_running && c_sequencer_vld;

always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin 
        up_wr_addr <= 0;
    end else begin 
        if (up_wr_vld) begin 
            if (c_is_last_chn) begin 
                up_wr_addr <= up_wr_addr + up_wr_offset;
            end else begin 
                up_wr_addr <= up_wr_addr + 1;
            end
        end else begin 
            up_wr_addr <= 0;
        end
    end
end

// one cycle delay
reg                     up_wr_vld_d;
reg  [OFM_AW-1:0]       up_wr_addr_d;

always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin 
        up_wr_vld_d  <= 0;
        up_wr_addr_d <= 0;
    end else begin 
        up_wr_vld_d  <= up_wr_vld;
        up_wr_addr_d <= up_wr_addr;
    end
end


//============================================================================
// III. ROUTE
//============================================================================
reg                     rte_start;
reg                     rte_running;

always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin 
        rte_start   <= 0;
        rte_running <= 0;
    end else begin 
        rte_start <= 0;
        if (m_rte && q_as_start) begin 
            rte_start   <= 1;
            rte_running <= 1;
        end

        if (c_sequencer_done && rte_running) begin 
            rte_running <= 0;
        end
    end
end
//----------------------------------------------------------------------------
// read address
//----------------------------------------------------------------------------
reg  [IFM_AW-1:0]       rte_rd_addr;

wire                    rte_rd_vld = rte_running && c_sequencer_vld;

always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin 
        rte_rd_addr <= 0;
    end else begin 
        if (rte_rd_vld) begin 
            rte_rd_addr <= rte_rd_addr + 1;
        end else begin 
            rte_rd_addr <= q_route_offset;
        end
    end
end

//----------------------------------------------------------------------------
// write address
//----------------------------------------------------------------------------
reg  [OFM_AW-1:0]       rte_wr_addr;
wire [W_CHANNEL-1:0]    rte_wr_offset = q_channel_out - c_channel + 1;

wire                    rte_wr_vld = rte_running && c_sequencer_vld;

always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin 
        rte_wr_addr <= 0;
    end else begin 
        if (rte_wr_vld) begin 
            if (c_is_last_chn) begin 
                rte_wr_addr <= rte_wr_addr + rte_wr_offset;
            end else begin 
                rte_wr_addr <= rte_wr_addr + 1;
            end
        end else begin 
            rte_wr_addr <= q_route_chn_offset;
        end
    end
end

// one cycle delay
reg                     rte_wr_vld_d;
reg  [OFM_AW-1:0]       rte_wr_addr_d;

always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin 
        rte_wr_vld_d  <= 0;
        rte_wr_addr_d <= 0;
    end else begin 
        rte_wr_vld_d  <= rte_wr_vld;
        rte_wr_addr_d <= rte_wr_addr;
    end
end



//============================================================================
// IV. OUTPUT
//============================================================================
assign c_sequencer_start = m_up ? up_start : rte_start;

assign o_as_done    = c_sequencer_done_d;

assign o_as_rd_vld  = up_rd_vld  ? up_rd_vld
                    : rte_rd_vld ? rte_rd_vld
                    : 0;

assign o_as_rd_addr = up_rd_vld   ? up_rd_addr
                    : rte_rd_vld  ? rte_rd_addr
                    : 0;



assign o_as_wr_vld  = up_wr_vld_d  ? up_wr_vld_d
                    : rte_wr_vld_d ? rte_wr_vld_d
                    : 0;

assign o_as_wr_addr = up_wr_vld_d  ? up_wr_addr_d
                    : rte_wr_vld_d ? rte_wr_addr_d
                    : 0;

endmodule