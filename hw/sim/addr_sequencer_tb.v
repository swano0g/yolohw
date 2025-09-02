`timescale 1ns / 1ps

module addr_sequencer_tb;

parameter W_SIZE       = `W_SIZE;
parameter W_CHANNEL    = `W_CHANNEL;
parameter W_FRAME_SIZE = `W_FRAME_SIZE;
parameter Tin          = `Tin;
parameter Tout         = `Tout;

parameter IFM_AW       = `FM_BUFFER_AW;

parameter OFM_AW       = `FM_BUFFER_AW; 
localparam CLK_PERIOD       = 10; // 100 MHz


reg                  clk, rstn;
initial begin
    clk = 0; forever #(CLK_PERIOD/2) clk = ~clk;
end

reg  [W_SIZE-1:0]           q_width;
reg  [W_SIZE-1:0]           q_height;
reg  [W_CHANNEL-1:0]        q_channel;
reg  [W_CHANNEL-1:0]        q_channel_out;
reg  [W_SIZE+W_CHANNEL-1:0] q_row_stride;

reg                         q_addr_seq_start;
wire                        addr_seq_done;
reg                         q_as_mode;

reg  [IFM_AW-1:0]           q_route_offset;
reg  [W_CHANNEL-1:0]        q_route_chn_offset;

wire                        as_rd_vld;
wire [IFM_AW-1:0]           as_rd_addr;

wire                        as_wr_vld;
wire [OFM_AW-1:0]           as_wr_addr;



initial begin
    rstn = 1'b0; 

    q_width = 4;
    q_height = 4;
    q_channel = 2;
    q_channel_out = 4;
    q_row_stride = 8;

    q_addr_seq_start = 0;
    // 0: upsample, 1: route
    q_as_mode = 1;
    
    q_route_offset = 0;
    q_route_chn_offset = 2;

   
    #(4*CLK_PERIOD) rstn = 1'b1; 

    #(100*CLK_PERIOD);

    @(negedge clk);
    q_addr_seq_start = 1;
    @(negedge clk);
    q_addr_seq_start = 0;

    @(posedge addr_seq_done);
    #(10*CLK_PERIOD);
    $finish;
end


//-------------------------------------------
// DUT: addr_sequencer
//-------------------------------------------
addr_sequencer u_addr_sequencer(
.clk(clk), 
.rstn(rstn),

// Addr Sequencer <-> TOP
.q_width(q_width),
.q_height(q_height),
.q_channel(q_channel),   
.q_channel_out(q_channel_out),
.q_row_stride(q_row_stride),   // q_width * q_channel


.q_addr_seq_start(q_addr_seq_start),
.addr_seq_done(addr_seq_done),

.q_as_mode(q_as_mode),          // 0 -> upsample, 1 -> route

.q_route_offset(q_route_offset),
.q_route_chn_offset(q_route_chn_offset),

// RD/WR addr 
.as_rd_vld(as_rd_vld),
.as_rd_addr(as_rd_addr),

// one cycle delay
.as_wr_vld(as_wr_vld),
.as_wr_addr(as_wr_addr)
);

endmodule