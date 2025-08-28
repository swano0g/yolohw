`include "controller_params.vh"

//----------------------------------------------------------------+
// Project: Deep Learning Hardware Design Contest
// Module: yolo_engine
// Description:
//		Load parameters and input feature map from DRAM via AXI4
//
//
//----------------------------------------------------------------+
module yolo_engine #(
    parameter AXI_WIDTH_AD = 32,
    parameter AXI_WIDTH_ID = 4,
    parameter AXI_WIDTH_DA = 32,
    parameter AXI_WIDTH_DS = AXI_WIDTH_DA/8,
    parameter OUT_BITS_TRANS = 18,
    parameter WBUF_AW = 9,
    parameter WBUF_DW = 8*3*3*16,
    parameter WBUF_DS = WBUF_DW/8,
    parameter MEM_BASE_ADDR = 'h8000_0000,
    parameter MEM_DATA_BASE_ADDR = 4096,


    parameter W_SIZE                = `W_SIZE,
    parameter W_CHANNEL             = `W_CHANNEL,
    parameter W_FRAME_SIZE          = `W_FRAME_SIZE,
    parameter W_DELAY               = `W_DELAY,
    parameter K                     = `K,
    parameter Tin                   = `Tin,
    parameter Tout                  = `Tout,

    parameter IFM_DW                = `IFM_DW,
    parameter IFM_AW                = `FM_BUFFER_AW,

    parameter OFM_DW                = `FM_BUFFER_DW,
    parameter OFM_AW                = `FM_BUFFER_AW,    

    parameter FILTER_DW             = `FILTER_DW,
    parameter FILTER_AW             = `FILTER_BUFFER_AW,

    parameter PSUM_DW               = `W_PSUM,
    parameter W_PSUM                = `W_PSUM,
    parameter PE_IFM_FLAT_BW        = `PE_IFM_FLAT_BW,
    parameter PE_FILTER_FLAT_BW     = `PE_FILTER_FLAT_BW,
    parameter PE_ACCO_FLAT_BW       = `PE_ACCO_FLAT_BW,

    parameter TEST_COL              = 16,
    parameter TEST_ROW              = 16, 
    parameter TEST_T_CHNIN          = 4,
    parameter TEST_T_CHNOUT         = 8,  
    parameter TEST_FRAME_SIZE       = TEST_ROW * TEST_COL * TEST_T_CHNIN,

    parameter DRAM_FILTER_OFFSET    = 4096,
    parameter DRAM_BIAS_OFFSET      = DRAM_FILTER_OFFSET + 4608,
    parameter DRAM_SCALE_OFFSET     = DRAM_BIAS_OFFSET + 128 
)(
    input                           clk, 
    input                           rstn,

    input [31:0]                    i_ctrl_reg0,    // network_start, // {debug_big(1), debug_buf_select(16), debug_buf_addr(9)}
    input [31:0]                    i_ctrl_reg1,    // Read address base -> ifm, filter, bias, scale
    input [31:0]                    i_ctrl_reg2,    // Write address base -> ofm
    input [31:0]                    i_ctrl_reg3,    // Write address base

    output                          M_ARVALID,
    input                           M_ARREADY,
    output  [AXI_WIDTH_AD-1:0]      M_ARADDR,
    output  [AXI_WIDTH_ID-1:0]      M_ARID,
    output  [7:0]                   M_ARLEN,
    output  [2:0]                   M_ARSIZE,
    output  [1:0]                   M_ARBURST,
    output  [1:0]                   M_ARLOCK,
    output  [3:0]                   M_ARCACHE,
    output  [2:0]                   M_ARPROT,
    output  [3:0]                   M_ARQOS,
    output  [3:0]                   M_ARREGION,
    output  [3:0]                   M_ARUSER,
    input                           M_RVALID,
    output                          M_RREADY,
    input  [AXI_WIDTH_DA-1:0]       M_RDATA,
    input                           M_RLAST,
    input  [AXI_WIDTH_ID-1:0]       M_RID,
    input  [3:0]                    M_RUSER,
    input  [1:0]                    M_RRESP,

    output                          M_AWVALID,
    input                           M_AWREADY,
    output  [AXI_WIDTH_AD-1:0]      M_AWADDR,
    output  [AXI_WIDTH_ID-1:0]      M_AWID,
    output  [7:0]                   M_AWLEN,
    output  [2:0]                   M_AWSIZE,
    output  [1:0]                   M_AWBURST,
    output  [1:0]                   M_AWLOCK,
    output  [3:0]                   M_AWCACHE,
    output  [2:0]                   M_AWPROT,
    output  [3:0]                   M_AWQOS,
    output  [3:0]                   M_AWREGION,
    output  [3:0]                   M_AWUSER,
    
    output                          M_WVALID, 
    input                           M_WREADY, 
    output  [AXI_WIDTH_DA-1:0]      M_WDATA, 
    output  [AXI_WIDTH_DS-1:0]      M_WSTRB, 
    output                          M_WLAST, 
    output  [AXI_WIDTH_ID-1:0]      M_WID, 
    output  [3:0]                   M_WUSER,
    
    input                           M_BVALID,
    output                          M_BREADY,
    input  [1:0]                    M_BRESP,
    input  [AXI_WIDTH_ID-1:0]       M_BID,
    input                           M_BUSER,
    
    output                          network_done,
    output                          network_done_led  
);

localparam BIT_TRANS = 18;

//================================================================
// 1) Parse control signals
//================================================================
reg         debug_on;


//CSR
reg ap_start;
reg ap_ready;
reg ap_done;
reg interrupt;


// address
reg [AXI_WIDTH_AD-1:0] dram_base_addr_rd;
reg [AXI_WIDTH_AD-1:0] dram_base_addr_wr;
reg [AXI_WIDTH_AD-1:0] reserved_register;

reg [AXI_WIDTH_AD-1:0] dram_base_addr_ifm;
reg [AXI_WIDTH_AD-1:0] dram_base_addr_filter;
reg [AXI_WIDTH_AD-1:0] dram_base_addr_bias;
reg [AXI_WIDTH_AD-1:0] dram_base_addr_scale;

reg [AXI_WIDTH_AD-1:0] dram_base_addr_ofm;      // write address



always @ (*) begin
    ap_ready    = 1;
end
assign network_done     = interrupt;
assign network_done_led = interrupt;


always @ (posedge clk or negedge rstn) begin
    if(~rstn) begin
        ap_start <= 0;
        ap_done  <= 0;
    end
    else begin 
        if(!ap_start && i_ctrl_reg0[0])
            ap_start <= 1; //begin
        else if (ap_done)
            ap_start <= 0;    
    end 
end

always @(posedge clk or negedge rstn) begin
    if(~rstn) begin
        interrupt <= 0;
    end
    else begin        
        if(i_ctrl_reg0[0])
            interrupt <= 0;         
        else if (ap_done)
            interrupt <= 1;   //interrupt flag -> network done             
    end
end

// Parse the control registers
always @ (posedge clk or negedge rstn) begin
    if(~rstn) begin
        debug_on          <= 0;
        dram_base_addr_rd <= 0;
        dram_base_addr_wr <= 0;
        reserved_register <= 0; // unused 

        dram_base_addr_ifm    <= 0;
        dram_base_addr_filter <= 0;
        dram_base_addr_bias   <= 0;
        dram_base_addr_scale  <= 0;
        dram_base_addr_ofm    <= 0;
    end
    else begin 
        if (!ap_start && i_ctrl_reg0[0]) begin 
            dram_base_addr_rd <= i_ctrl_reg1; // Base Address for READ  (Input image, Model parameters)
            dram_base_addr_wr <= i_ctrl_reg2; // Base Address for WRITE (Intermediate feature maps, Outputs)
            reserved_register <= i_ctrl_reg3; // reserved (weight)
            
            dram_base_addr_ifm    <= i_ctrl_reg1;
            dram_base_addr_filter <= i_ctrl_reg1 + DRAM_FILTER_OFFSET;
            dram_base_addr_bias   <= i_ctrl_reg1 + DRAM_BIAS_OFFSET;
            dram_base_addr_scale  <= i_ctrl_reg1 + DRAM_SCALE_OFFSET;
            dram_base_addr_ofm    <= i_ctrl_reg2;

            
            dma_ifm_rd_base_addr    <= i_ctrl_reg1;
            dma_filter_rd_base_addr <= i_ctrl_reg1 + DRAM_FILTER_OFFSET;
            dma_bias_rd_base_addr   <= i_ctrl_reg1 + DRAM_BIAS_OFFSET;
            dma_scale_rd_base_addr  <= i_ctrl_reg1 + DRAM_SCALE_OFFSET;


            debug_on        <= i_ctrl_reg0[1];

        end 
        else if (ap_done) begin 
            dram_base_addr_rd <= 0;
            dram_base_addr_wr <= 0;
            reserved_register <= 0; 
            
            dram_base_addr_ifm    <= 0;
            dram_base_addr_filter <= 0;
            dram_base_addr_bias   <= 0;
            dram_base_addr_scale  <= 0;
            dram_base_addr_ofm    <= 0;

            debug_on   <= 0;
        end 
    end 
end
//================================================================
// 2) tools
//================================================================
function [15:0] ceil_div64;
    input [31:0] nbytes;
    begin
        ceil_div64 = (nbytes + 32'd63) >> 6; // (n+63)/64
    end
endfunction


function [15:0] blk16;
    input [31:0] words;
    begin blk16 = (words + 16 - 1)/16; end
endfunction


function [0:0] fit_1bit;
    input [31:0] x;
    begin
        fit_1bit = x[0];
    end
endfunction

function [1:0] fit_2bit;
    input [31:0] x;
    begin
        fit_2bit = x[1:0];
    end
endfunction

function [W_SIZE-1:0] fit_wsize;
    input [63:0] x;
    begin
        fit_wsize = x[W_SIZE-1:0];     // 자동 truncate/zero-extend
    end
endfunction

function [W_CHANNEL-1:0] fit_wch;
    input [63:0] x; 
    begin fit_wch = x[W_CHANNEL-1:0]; end
endfunction

function [IFM_AW-1:0] fit_aw;
    input [63:0] x; 
    begin fit_wch = x[IFM_AW-1:0]; end
endfunction

// function [W_FRAME_SIZE-1:0] fit_wframe;
//     input [63:0] x; 
//     begin fit_wframe = x[W_FRAME_SIZE-1:0]; end
// endfunction

// function [W_SIZE+W_CHANNEL-1:0] fit_row_stride;
//     input [63:0] x;
//     begin fit_row_stride = x[W_SIZE+W_CHANNEL-1:0]; end
// endfunction


// {q_last_layer, q_ofm_save, q_route_offset, q_route_loc, q_route_load, q_route_save, q_upsample, q_maxpool, q_maxpool_stride, q_channel_out, q_channel, q_height, q_width}

// 40 + 19
localparam W_ENTRY = 1                  // q_last_layer
                   + 1                  // q_ofm_save
                   + IFM_AW             // q_route_offset
                   + 2                  // q_route_loc
                   + 1                  // q_route_load
                   + 1                  // q_route_save
                   + 1                  // q_upsample
                   + 1                  // q_maxpool
                   + 2                  // q_maxpool_stride 
                   + W_CHANNEL          // q_channel_out    8
                   + W_CHANNEL          // q_channel        8
                   + W_SIZE             // q_height         9
                   + W_SIZE;            // q_width          9


// 미완 수정필요
function [W_ENTRY-1:0] layer_entry;
    input [4:0] q_layer;
    begin
        case (q_layer)
        5'd0: layer_entry = {
                1'b0,                   // upsample
                1'b1,                   // maxpool
                2'd2,                   // maxpool_stride
                fit_row_stride(256),    // row_stride
                fit_wframe(65536),      // frame_size
                fit_wch(4),             // channel_out
                fit_wch(1),             // channel (in)
                fit_wsize(256),         // height
                fit_wsize(256)          // width
                };
        5'd1: layer_entry = {
                1'b0,                   // upsample
                1'b1,                   // maxpool
                2'd2,                   // maxpool_stride
                fit_row_stride(512),    // row_stride
                fit_wframe(65536),      // frame_size
                fit_wch(8),             // channel_out
                fit_wch(4),             // channel (in)
                fit_wsize(128),         // height
                fit_wsize(128)          // width
                };
        5'd2: layer_entry = {
                1'b0,                   // upsample
                1'b1,                   // maxpool
                2'd2,                   // maxpool_stride
                fit_row_stride(512),    // row_stride
                fit_wframe(32768),      // frame_size
                fit_wch(16),            // channel_out
                fit_wch(8),             // channel (in)
                fit_wsize(64),          // height
                fit_wsize(64)           // width
                };
        5'd3: layer_entry = {
                1'b0,                   // upsample
                1'b1,                   // maxpool
                2'd2,                   // maxpool_stride
                fit_row_stride(512),    // row_stride
                fit_wframe(16384),      // frame_size
                fit_wch(32),            // channel_out
                fit_wch(16),            // channel (in)
                fit_wsize(32),          // height
                fit_wsize(32)           // width
                };
        5'd4: layer_entry = {
                1'b0,                   // upsample
                1'b1,                   // maxpool
                2'd2,                   // maxpool_stride
                fit_row_stride(512),    // row_stride
                fit_wframe(8192),       // frame_size
                fit_wch(64),            // channel_out
                fit_wch(32),            // channel (in)
                fit_wsize(16),          // height
                fit_wsize(16)           // width
                };
        5'd5: layer_entry = {
                1'b0,                   // upsample
                1'b1,                   // maxpool
                2'd1,                   // maxpool_stride
                fit_row_stride(512),    // row_stride
                fit_wframe(4096),       // frame_size
                fit_wch(128),           // channel_out
                fit_wch(64),            // channel (in)
                fit_wsize(8),           // height
                fit_wsize(8)            // width
                };
        5'd6: layer_entry = {
                1'b0,                   // upsample
                1'b0,                   // maxpool
                2'd0,                   // maxpool_stride
                fit_row_stride(1024),   // row_stride
                fit_wframe(8192),       // frame_size
                fit_wch(64),            // channel_out
                fit_wch(128),           // channel (in)
                fit_wsize(8),           // height
                fit_wsize(8)            // width
                };
        5'd7: layer_entry = {
                1'b0,                   // upsample
                1'b0,                   // maxpool
                2'd0,                   // maxpool_stride
                fit_row_stride(512),    // row_stride
                fit_wframe(4096),       // frame_size
                fit_wch(128),           // channel_out
                fit_wch(64),            // channel (in)
                fit_wsize(8),           // height
                fit_wsize(8)            // width
                };
        5'd8: layer_entry = {
                1'b0,                   // upsample
                1'b0,                   // maxpool
                2'd0,                   // maxpool_stride
                fit_row_stride(1024),   // row_stride
                fit_wframe(8192),       // frame_size
                fit_wch(49),            // channel_out
                fit_wch(128),           // channel (in)
                fit_wsize(8),           // height
                fit_wsize(8)            // width
                };
        default: layer_entry = {W_ENTRY{1'b0}};
        endcase
    end
endfunction


// debug
`include "sim_multi_cfg.vh"
function [W_ENTRY-1:0] dbg_layer_entry;
    input [4:0] q_layer;
    begin
        case (q_layer)
                // debug multi layer
        5'd0: dbg_layer_entry = {
                fit_1bit(`TEST_L0_LAST_LAYER),      // last_layer
                fit_1bit(`TEST_L0_OFM_SAVE),        // ofm_save
                fit_aw(`TEST_L0_ROUTE_OFFSET),      // route_offset
                fit_2bit(`TEST_L0_ROUTE_LOC),       // route_loc
                fit_1bit(`TEST_L0_ROUTE),           // route
                fit_1bit(`TEST_L0_UPSAMPLE),        // upsample
                fit_1bit(`TEST_L0_MAXPOOL),         // maxpool
                fit_2bit(`TEST_L0_MAXPOOL_STRIDE),  // maxpool_stride
                fit_wch(`TEST_L0_CHANNEL_OUT),      // channel_out
                fit_wch(`TEST_L0_CHANNEL),          // channel (in)
                fit_wsize(`TEST_L0_ROW),            // height
                fit_wsize(`TEST_L0_COL)             // width
                };
        5'd1: dbg_layer_entry = {
                fit_1bit(`TEST_L1_LAST_LAYER),      // last_layer
                fit_1bit(`TEST_L1_OFM_SAVE),        // ofm_save
                fit_aw(`TEST_L1_ROUTE_OFFSET),      // route_offset
                fit_2bit(`TEST_L1_ROUTE_LOC),       // route_loc
                fit_1bit(`TEST_L1_ROUTE),           // route
                fit_1bit(`TEST_L1_UPSAMPLE),        // upsample
                fit_1bit(`TEST_L1_MAXPOOL),         // maxpool
                fit_2bit(`TEST_L1_MAXPOOL_STRIDE),  // maxpool_stride
                fit_wch(`TEST_L1_CHANNEL_OUT),      // channel_out
                fit_wch(`TEST_L1_CHANNEL),          // channel (in)
                fit_wsize(`TEST_L1_ROW),            // height
                fit_wsize(`TEST_L1_COL)             // width
                };
        5'd2: dbg_layer_entry = {
                fit_1bit(`TEST_L2_LAST_LAYER),      // last_layer
                fit_1bit(`TEST_L2_OFM_SAVE),        // ofm_save
                fit_aw(`TEST_L2_ROUTE_OFFSET),      // route_offset
                fit_2bit(`TEST_L2_ROUTE_LOC),       // route_loc
                fit_1bit(`TEST_L2_ROUTE),           // route
                fit_1bit(`TEST_L2_UPSAMPLE),        // upsample
                fit_1bit(`TEST_L2_MAXPOOL),         // maxpool
                fit_2bit(`TEST_L2_MAXPOOL_STRIDE),  // maxpool_stride
                fit_wch(`TEST_L2_CHANNEL_OUT),      // channel_out
                fit_wch(`TEST_L2_CHANNEL),          // channel (in)
                fit_wsize(`TEST_L2_ROW),            // height
                fit_wsize(`TEST_L2_COL)             // width
                };
        5'd3: dbg_layer_entry = {
                fit_1bit(`TEST_L3_LAST_LAYER),      // last_layer
                fit_1bit(`TEST_L3_OFM_SAVE),        // ofm_save
                fit_aw(`TEST_L3_ROUTE_OFFSET),      // route_offset
                fit_2bit(`TEST_L3_ROUTE_LOC),       // route_loc
                fit_1bit(`TEST_L3_ROUTE),           // route
                fit_1bit(`TEST_L3_UPSAMPLE),        // upsample
                fit_1bit(`TEST_L3_MAXPOOL),         // maxpool
                fit_2bit(`TEST_L3_MAXPOOL_STRIDE),  // maxpool_stride
                fit_wch(`TEST_L3_CHANNEL_OUT),      // channel_out
                fit_wch(`TEST_L3_CHANNEL),          // channel (in)
                fit_wsize(`TEST_L3_ROW),            // height
                fit_wsize(`TEST_L3_COL)             // width
                };
        5'd4: dbg_layer_entry = {
                fit_1bit(`TEST_L4_LAST_LAYER),      // last_layer
                fit_1bit(`TEST_L4_OFM_SAVE),        // ofm_save
                fit_aw(`TEST_L4_ROUTE_OFFSET),      // route_offset
                fit_2bit(`TEST_L4_ROUTE_LOC),       // route_loc
                fit_1bit(`TEST_L4_ROUTE),           // route
                fit_1bit(`TEST_L4_UPSAMPLE),        // upsample
                fit_1bit(`TEST_L4_MAXPOOL),         // maxpool
                fit_2bit(`TEST_L4_MAXPOOL_STRIDE),  // maxpool_stride
                fit_wch(`TEST_L4_CHANNEL_OUT),      // channel_out
                fit_wch(`TEST_L4_CHANNEL),          // channel (in)
                fit_wsize(`TEST_L4_ROW),            // height
                fit_wsize(`TEST_L4_COL)             // width
                };
        default: dbg_layer_entry = {W_ENTRY{1'b0}};
        endcase
    end
endfunction





//================================================================
// 3) TOP state machine
//================================================================
reg  [4:0]                  q_layer;        // layer index

// layer informations -> hard coding
reg  [W_SIZE-1:0]           q_width;
reg  [W_SIZE-1:0]           q_height;
reg  [W_CHANNEL-1:0]        q_channel;
reg  [W_CHANNEL-1:0]        q_channel_out;
reg  [W_FRAME_SIZE-1:0]     q_frame_size;
reg  [W_SIZE+W_CHANNEL-1:0] q_row_stride;
reg                         q_maxpool;
reg  [1:0]                  q_maxpool_stride;
reg                         q_upsample;

reg                         q_last_layer;

reg                         q_c_ctrl_start;  // cnn_ctrl start signal (q_start)
reg                         q_load_ifm;
reg                         q_load_filter;
reg                         q_load_bias;
reg                         q_load_scale;

reg                         q_route_save;
reg                         q_route_load;
reg  [1:0]                  q_route_loc;    // 0-> ifm(feed back), 1-> additional buf, 2-> dram
reg  [IFM_AW-1:0]           q_route_offset; // address offset

reg                         q_ofm_save;

reg                         q_fm_buf_switch;


// 관찰용 완료 신호(하위에서 만들어 줘야 함)
//  - IFM 초기 적재 완료: buffer_manager(or DMA 프론트엔드)에서 발생
//  - 한 레이어 연산 완료: cnn_ctrl에서 제공 (기존 layer_done 사용)
//  - OFM 저장 완료: writer(또는 postprocessor→writer)에서 발생
wire dma_ifm_load_done;     // 
wire dma_ofm_write_done;
wire layer_done;            // cnn_ctrl


reg [2:0] q_state;

localparam 
    S_IDLE          = 3'd0, 
    S_LOAD_IFM      = 3'd1, // initial once
    S_SAVE_OFM      = 3'd2, // layer 14, 20
    S_LOAD_CFG1     = 3'd3,
    S_LOAD_CFG2     = 3'd4,
    S_WAIT_CNN_CTRL = 3'd5;  // each layer



always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        q_state          <= S_IDLE;
        q_layer          <= 0;
        q_c_ctrl_start   <= 0;

        q_layer          <= 0;
        q_width          <= 0;
        q_height         <= 0;
        q_channel        <= 0;
        q_channel_out    <= 0;
        q_frame_size     <= 0;
        q_row_stride     <= 0;
        q_maxpool        <= 0;
        q_maxpool_stride <= 0;
        q_upsample       <= 0;

        q_route_save     <= 0;
        q_route_load     <= 0;
        q_route_loc      <= 0;
        q_route_offset   <= 0;

        q_last_layer     <= 0;

        q_load_ifm       <= 0;
        q_load_filter    <= 0;
        q_load_bias      <= 0;
        q_load_scale     <= 0;

        q_ofm_save       <= 0;

        q_fm_buf_switch  <= 0;

        // layer info reset...

    end
    else begin
        q_c_ctrl_start <= 1'b0; // pulse
        q_fm_buf_switch <= 0; // pulse

        case (q_state)
            S_IDLE: begin
                if (ap_start) begin
                    q_layer <= 0;
                    q_state <= S_LOAD_CFG1;

                end
            end

            // IFM 초기 적재 대기.
            S_LOAD_IFM: begin
                if (dma_ifm_load_done) begin
                    // 첫 레이어 실행 트리거는 다음 상태에서 cfg 로드 후 발생
                    q_state        <= S_WAIT_CNN_CTRL;
                    q_c_ctrl_start <= 1'b1;
                end
            end            
            
            // FETCH
            S_LOAD_CFG1: begin

                // ADD
                // q_frame_size, q_row_stride: internal caculation
                if (debug_on) begin 
                    {q_last_layer, q_ofm_save, q_route_offset, q_route_loc, q_route_load, q_route_save, q_upsample, q_maxpool, q_maxpool_stride, q_channel_out, q_channel, q_height, q_width} = dbg_layer_entry(q_layer);
                end else begin 
                    {q_last_layer, q_ofm_save, q_route_offset, q_route_loc, q_route_load, q_route_save, q_upsample, q_maxpool, q_maxpool_stride, q_channel_out, q_channel, q_height, q_width} = layer_entry(q_layer);
                end
                
                q_frame_size <= q_width * q_height * q_channel;
                q_row_stride <= q_width * q_channel;

                q_state <= S_LOAD_CFG2;
            end
            
            // DECODE
            S_LOAD_CFG2: begin
                if (q_layer == 0) begin 
                    q_state <= S_LOAD_IFM;
                end else if (q_ofm_save) begin 
                    q_state <= S_SAVE_OFM;
                end else begin 
                    q_c_ctrl_start <= 1'b1;
                    q_state <= S_WAIT_CNN_CTRL;
                end
            end


            S_SAVE_OFM: begin 
                if (dma_ofm_write_done) begin 
                    if (q_last_layer) begin 
                        q_state <= S_IDLE;
                        ap_done <= 1;
                        ap_start <= 0;
                    end else begin 
                        q_layer <= q_layer + 1;
                        // q_fm_buf_switch <= 1;
                        q_state <= S_LOAD_CFG1;     
                    end
                end
            end


            S_WAIT_CNN_CTRL: begin 
                if (layer_done) begin 
                    if (q_last_layer) begin 
                        q_state <= S_IDLE;
                        ap_done <= 1;
                        ap_start <= 0;
                    end else begin 
                        q_layer <= q_layer + 1;
                        q_fm_buf_switch <= 1;
                        q_state <= S_LOAD_CFG1;
                    end
                end
            end

            default: q_state <= S_IDLE;
        endcase
    end
end


//================================================================
// 4) DMA signals
//================================================================
// 우리가 사용할 선들
wire                 dma_rd_go;                 // read stream start (1cycle)
wire [31:0]          dma_rd_base_addr;
wire [BIT_TRANS-1:0] dma_rd_num_trans;
wire [15:0]          dma_rd_max_req_blk_idx;
wire                 dma_ctrl_read_done;        // read stream done (1cycle)


wire                 dma_wr_go;
wire [31:0]          dma_wr_base_addr;
wire [BIT_TRANS-1:0] dma_wr_num_trans;
wire [15:0]          dma_wr_max_req_blk_idx;
wire                 dma_ctrl_write_done;

// 연결선
// Signals for dma read  
wire                    ctrl_read;
wire                    read_done;
wire [AXI_WIDTH_AD-1:0] read_addr;
wire [AXI_WIDTH_DA-1:0] axi_read_data;
wire                    axi_read_data_vld;
wire [BIT_TRANS   -1:0] read_data_cnt;


// Signals for dma write

wire                    ctrl_write;
wire                    write_done;
wire                    indata_req_wr;
wire [BIT_TRANS   -1:0] write_data_cnt;
wire [AXI_WIDTH_AD-1:0] write_addr;
wire [AXI_WIDTH_DA-1:0] write_data;



wire [BIT_TRANS   -1:0] num_trans        = 16;           // BURST_LENGTH = 16
//================================================================
// 5) DMA 
//================================================================
//----------------------------------------------------------------
// 5-1) DMA LOAD signal
//----------------------------------------------------------------
// stage wire
// 각 스테이지에서 로드를 "한번"만 진행
// load affine stage의 경우 bias 로드하고 그 다음에 scale을 로드해야함

// 각 스테이지에 대하여 base_addr을 두어 로드가 완료된 경우 offset을 더해 최신값 유지.

wire in_load_ifm_stage    = (q_state == S_LOAD_IFM);
wire in_load_filter_stage = (ctrl_csync_run == 1);
wire in_load_affine_stage = (ctrl_psync_run == 1) && (ctrl_psync_phase == 0);    // bias, scale

reg in_load_ifm_d, in_load_filter_d, in_load_affine_d;

wire in_load_ifm_enter    =  in_load_ifm_stage    & ~in_load_ifm_d;
wire in_load_ifm_leave    = ~in_load_ifm_stage    &  in_load_ifm_d;
wire in_load_filter_enter =  in_load_filter_stage & ~in_load_filter_d;
wire in_load_filter_leave = ~in_load_filter_stage &  in_load_filter_d;
wire in_load_affine_enter =  in_load_affine_stage & ~in_load_affine_d;
wire in_load_affine_leave = ~in_load_affine_stage &  in_load_affine_d;


always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        in_load_ifm_d    <= 1'b0;
        in_load_filter_d <= 1'b0;
        in_load_affine_d <= 1'b0;
    end else begin
        in_load_ifm_d    <= in_load_ifm_stage;
        in_load_filter_d <= in_load_filter_stage;
        in_load_affine_d <= in_load_affine_stage;
    end
end

//----------------------------------------------------------------
// 5-2) DMA LOAD FSM 
//----------------------------------------------------------------
localparam 
    DMA_LOAD_IDLE  = 2'd0,
    DMA_LOAD_SETUP = 2'd1,
    DMA_LOAD_KICK  = 2'd2,
    DMA_LOAD_WAIT  = 2'd3;

reg [1:0] dma_load_state;

// 어떤 대상(IFM/FILTER/BIAS/SCALE)을 로드 중인지
localparam 
    SEL_NONE   = 3'd0,
    SEL_IFM    = 3'd1,
    SEL_FILTER = 3'd2,
    SEL_BIAS   = 3'd3,
    SEL_SCALE  = 3'd4;

reg [2:0] dma_load_cur_sel;


reg  in_load_affine_phase;  // 0 -> bias, 1 -> scale


// *** 앞선 state machine(top fsm, cnn_ctrl)의 경우 로드가 완료됐다고 바로 state가 변하지 않음.
// 즉 dma load fsm에서 DMA_LOAD_WAIT가 끝나고 DMA_LOAD_IDLE로 전이했을 떄 여전히 in_load_*_stage가
// 활성화되어있을 수 있음. 이때 kicked 레지스터로 해당 load가 발행되었는지를 추적해야함.
// kicked 레지스터는 state가 변경된 경우 적절히 다시 0이 될 필요가 있음. 
reg  dma_load_kicked;


// a. dma_rd_go
reg dma_load_rd_go_pulse;

// b. dma_rd_base_addr
reg [31:0]          dma_ifm_rd_base_addr;
reg [31:0]          dma_filter_rd_base_addr;
reg [31:0]          dma_bias_rd_base_addr;
reg [31:0]          dma_scale_rd_base_addr;


// c. dma_rd_num_trans
// reg [BIT_TRANS-1:0] dma_ifm_rd_num_trans;          // = 16 고정
// num_trans (=고정값 16) 사용


// d. dma_rd_max_req_blk_idx
// total bytes / 64B
reg [15:0]          dma_rd_max_req_blk_idx_r; 



// e. dma_ctrl_read_done
reg                         dma_ifm_load_done_reg;
reg                         dma_filter_load_done_reg;
reg                         dma_bias_load_done_reg;
reg                         dma_scale_load_done_reg;

// // top fsm에 올려줄 신호
assign dma_ifm_load_done = dma_ifm_load_done_reg;


// 
assign dma_rd_go               = dma_load_rd_go_pulse;

assign dma_rd_base_addr        = (dma_load_cur_sel == SEL_IFM)    ? dma_ifm_rd_base_addr
                               : (dma_load_cur_sel == SEL_FILTER) ? dma_filter_rd_base_addr 
                               : (dma_load_cur_sel == SEL_BIAS)   ? dma_bias_rd_base_addr
                               : (dma_load_cur_sel == SEL_SCALE)  ? dma_scale_rd_base_addr
                               : 0;

assign dma_rd_num_trans        = num_trans;


assign dma_rd_max_req_blk_idx = dma_rd_max_req_blk_idx_r;


// 전체 바이트 
// item   : formula                         = formula optimize      => # blocks optimized
//-------------------------------------------------------------------------------------------
// ifm    : q_frame_size * 4                = q_frame_size << 2     => q_frame_size >> 4        
// filter : (q_channel << 2) * Tout * 9     = (q_channel << 4) * 9  => (q_channel >> 2) * 9     // input 채널 / 16 * 9
// bias   : (q_channel_out << 2) * 4        = (q_channel_out << 4)  => (q_channel_out >> 2)     // output 채널 / 16
// scale  : (q_channel_out << 2) * 4        = (q_channel_out << 4)  => (q_channel_out >> 2)   

// 블록단위로 안떨어지는 경우..
// 그냥 zero padding

// reg  [31:0] dma_load_bytes_total;  

// 블록 수 = 전체 바이트 / 64 (>> 6)

// 읽어야할 데이터가 64B의 배수가 아닐 때 -> 우선 계산 진행.
reg rd_inflight;

always @(posedge clk or negedge rstn) begin
    if (!rstn) rd_inflight <= 1'b0;
    else if (dma_rd_go)            rd_inflight <= 1'b1;   // kick 순간 busy 진입
    else if (dma_ctrl_read_done)   rd_inflight <= 1'b0;   // 컨트롤러 done에서만 내려감
end

wire dma_rd_plane_busy = rd_inflight;



// -----------------------------------------------------------------------------
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        dma_load_state           <= DMA_LOAD_IDLE;
        dma_load_cur_sel         <= SEL_NONE;
        in_load_affine_phase     <= 0;

        dma_load_kicked          <= 1'b0;
        dma_load_rd_go_pulse     <= 1'b0;


        dma_ifm_load_done_reg    <= 0;
        dma_filter_load_done_reg <= 0;
        dma_bias_load_done_reg   <= 0;
        dma_scale_load_done_reg  <= 0;        

    end else begin
        // defaults (pulse)
        dma_load_rd_go_pulse     <= 1'b0;
        dma_ifm_load_done_reg    <= 0;
        dma_filter_load_done_reg <= 0;
        dma_bias_load_done_reg   <= 0;
        dma_scale_load_done_reg  <= 0;  

        // dma drain
        // if ((in_load_ifm_leave && (dma_load_cur_sel==SEL_IFM)) ||
        //     (in_load_filter_leave && (dma_load_cur_sel==SEL_FILTER)) ||
        //     (in_load_affine_leave && ((dma_load_cur_sel==SEL_BIAS)||(dma_load_cur_sel==SEL_SCALE)))) begin
        //     dma_load_state       <= DMA_LOAD_IDLE;
        //     dma_load_cur_sel     <= SEL_NONE;
        //     dma_load_kicked      <= 1'b0;
        //     in_load_affine_phase <= 0;
        // end

        case (dma_load_state)
            // ------------------------------------------------
            DMA_LOAD_IDLE: begin
                // dma_load_cur_sel <= SEL_NONE;

                // 발행 한적 없을 때
                if (!dma_load_kicked && in_load_ifm_enter && !dma_rd_plane_busy) begin
                    dma_load_cur_sel <= SEL_IFM;
                    dma_load_state   <= DMA_LOAD_SETUP;
                end
                else if (!dma_load_kicked && in_load_filter_enter && !dma_rd_plane_busy) begin
                    dma_load_cur_sel <= SEL_FILTER;
                    dma_load_state   <= DMA_LOAD_SETUP;
                end
                else if (!dma_load_kicked && in_load_affine_enter && !dma_rd_plane_busy) begin
                    dma_load_cur_sel <= SEL_BIAS;
                    dma_load_state   <= DMA_LOAD_SETUP;
                end
            end
            // ------------------------------------------------
            // Program base address / block count for the input image
            DMA_LOAD_SETUP: begin

                case (dma_load_cur_sel)
                    SEL_IFM: begin
                        q_load_ifm <= 1;
                        dma_rd_max_req_blk_idx_r <= ceil_div64(q_frame_size << 2);
                    end
                    SEL_FILTER: begin
                        q_load_filter <= 1;
                        dma_rd_max_req_blk_idx_r <= ceil_div64((q_channel << 4) * 9);
                    end
                    SEL_BIAS: begin
                        q_load_bias <= 1;
                        dma_rd_max_req_blk_idx_r <= ceil_div64(q_channel_out << 4);
                    end
                    SEL_SCALE: begin
                        q_load_scale <= 1;
                        dma_rd_max_req_blk_idx_r <= ceil_div64(q_channel_out << 4);
                    end
                    default: begin
                        dma_rd_max_req_blk_idx_r <= 16'd0;
                    end
                endcase

                dma_load_state <= DMA_LOAD_KICK;
            end
            // ------------------------------------------------
            // Fire a single‑cycle start to DMA controller
            DMA_LOAD_KICK: begin
                if (!dma_load_kicked) begin
                    dma_load_rd_go_pulse <= 1'b1; // one-cycle kick
                    dma_load_kicked  <= 1'b1;
                end
                dma_load_state <= DMA_LOAD_WAIT;
            end
            // ------------------------------------------------
            // Wait until DMA finishes issuing and receiving all data
            DMA_LOAD_WAIT: begin
                if (dma_ctrl_read_done) begin
                    case (dma_load_cur_sel)
                        SEL_IFM: begin
                            dma_load_state        <= DMA_LOAD_IDLE;
                            dma_load_kicked       <= 1'b0;
                            q_load_ifm            <= 1'b0;
                            dma_ifm_load_done_reg <= 1'b1;
                        end
                        SEL_FILTER: begin 
                            dma_load_state           <= DMA_LOAD_IDLE;
                            dma_load_kicked          <= 1'b0;
                            q_load_filter            <= 1'b0;
                            dma_filter_load_done_reg <= 1'b1;

                            dma_filter_rd_base_addr  <= dma_filter_rd_base_addr + (q_channel << 4) * 9;
                        end
                        SEL_BIAS: begin 
                            dma_load_state         <= DMA_LOAD_SETUP;
                            dma_load_cur_sel       <= SEL_SCALE;
                            dma_load_kicked        <= 1'b0;
                            q_load_bias            <= 1'b0;
                            dma_bias_load_done_reg <= 1'b1;

                            dma_bias_rd_base_addr  <= dma_bias_rd_base_addr + (q_channel_out << 4);
                        end
                        SEL_SCALE: begin
                            dma_load_state          <= DMA_LOAD_IDLE;
                            q_load_scale            <= 1'b0;
                            dma_load_kicked         <= 1'b0;
                            dma_scale_load_done_reg <= 1'b1;

                            in_load_affine_phase    <= 1'b0;
                            dma_scale_rd_base_addr  <= dma_scale_rd_base_addr + (q_channel_out << 4);
                        end
                    endcase
                end
            end

            default: dma_load_state <= DMA_LOAD_IDLE;
        endcase
    end
end
//----------------------------------------------------------------
// beat counter
localparam BYTES_PER_BEAT     = 4;
localparam LOG_BYTES_PER_BEAT = $clog2(BYTES_PER_BEAT);


reg [15:0] payload_beats_need;
reg [15:0] payload_beats_seen;
wire       payload_done_early = (payload_beats_seen >= payload_beats_need);


wire [31:0] need_bytes_ifm    = (q_frame_size << 2);
wire [31:0] need_bytes_filter = ((q_channel << 4) * 9);
wire [31:0] need_bytes_bias   = (q_channel_out << 4);
wire [31:0] need_bytes_scale  = (q_channel_out << 4);

wire [31:0] need_bytes_cur = (dma_load_cur_sel==SEL_IFM)    ? need_bytes_ifm 
                           : (dma_load_cur_sel==SEL_FILTER) ? need_bytes_filter
                           : (dma_load_cur_sel==SEL_BIAS)   ? need_bytes_bias  
                           : (dma_load_cur_sel==SEL_SCALE)  ? need_bytes_scale : 32'd0;

wire [15:0] need_beats_cur = need_bytes_cur >> LOG_BYTES_PER_BEAT;


always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        payload_beats_need <= 0;
        payload_beats_seen <= 0;
    end else begin
        if (dma_load_state == DMA_LOAD_SETUP) begin
            payload_beats_need <= need_beats_cur;
            payload_beats_seen <= 0;
        end
        else if (dma_load_state == DMA_LOAD_WAIT && axi_read_data_vld) begin
            payload_beats_seen <= payload_beats_seen + 1'b1;
        end

        if (dma_ctrl_read_done) begin
            payload_beats_need <= 0;
            payload_beats_seen <= 0;
        end
    end
end


// q_load_* signal early OFF
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        q_load_ifm    <= 1'b0;
        q_load_filter <= 1'b0;
        q_load_bias   <= 1'b0;
        q_load_scale  <= 1'b0;
    end else begin
        if (dma_load_state == DMA_LOAD_SETUP) begin
            case (dma_load_cur_sel)
                SEL_IFM:    q_load_ifm    <= 1'b1;
                SEL_FILTER: q_load_filter <= 1'b1;
                SEL_BIAS:   q_load_bias   <= 1'b1;
                SEL_SCALE:  q_load_scale  <= 1'b1;
            endcase
        end

        if (dma_load_state == DMA_LOAD_WAIT && payload_done_early) begin
            case(dma_load_cur_sel)
                SEL_IFM:    q_load_ifm    <= 1'b0;
                SEL_FILTER: q_load_filter <= 1'b0;
                SEL_BIAS:   q_load_bias   <= 1'b0;
                SEL_SCALE:  q_load_scale  <= 1'b0;
            endcase
        end
    end
end
//----------------------------------------------------------------
// 5-3) DMA write
//----------------------------------------------------------------
// User interface

// input  dma_wr_go                 write stream start
// input  dma_wr_base_addr          write stream base address
// input  dma_wr_num_trans          data per block, fixed to 16
// input  dma_wr_max_req_blk_idx    # blocks to write
// output write_data_cnt            # data written within a block
// output dma_ctrl_write_done       write stream done

// input  write_data                data to write
// output indata_req_wr             data request signal

// tap_ifm_vld
// tap_ifm_read_vld
// tap_ifm_read_addr
// tap_ifm_read_data

wire in_save_ofm_stage    = (q_state == S_SAVE_OFM);


reg in_save_ofm_d;

wire in_save_ofm_enter    =  in_save_ofm_stage & ~in_save_ofm_d;
wire in_save_ofm_leave    = ~in_save_ofm_stage &  in_save_ofm_d;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        in_save_ofm_d    <= 1'b0;
    end else begin
        in_save_ofm_d    <= in_save_ofm_stage;
    end
end



localparam 
    DMA_SAVE_IDLE  = 2'd0,
    DMA_SAVE_SETUP = 2'd1,
    DMA_SAVE_KICK  = 2'd2,
    DMA_SAVE_WAIT  = 2'd3;

reg [1:0] dma_save_state;


// total bytes / 64B
reg [15:0]                      dma_wr_max_req_blk_idx_r;   // request
reg [15:0]                      dma_wr_blk_idx;             // blk counter


reg                             dma_save_wr_go_pulse;

// // top fsm에 올려줄 신호
assign dma_ofm_write_done       = dma_ctrl_write_done;


// 
assign dma_wr_go                = dma_save_wr_go_pulse;
assign dma_wr_base_addr         = dram_base_addr_ofm;
assign dma_wr_max_req_blk_idx   = dma_wr_max_req_blk_idx_r;
assign dma_wr_num_trans         = num_trans;


// 전체 바이트 
// item   : formula                         = formula optimize      => # blocks optimized
//-------------------------------------------------------------------------------------------
// ofm    : eff_w * eff_h * q_channel       = q_frame_size << 2     => q_frame_size >> 4        


assign tap_ifm_vld          = in_save_ofm_stage;
assign tap_ifm_read_vld     = indata_req_wr;
assign tap_ifm_read_addr    = (dma_wr_blk_idx << 4) + write_data_cnt;
assign write_data           = tap_ifm_read_data;


// -----------------------------------------------------------------------------


always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        dma_save_state <= DMA_SAVE_IDLE;

        dma_wr_max_req_blk_idx_r <= 0;
        dma_wr_blk_idx           <= 0;
        dma_save_wr_go_pulse     <= 0;
    end else begin
        dma_save_wr_go_pulse <= 0;
        case (dma_save_state)
            DMA_SAVE_IDLE: begin
                if (in_save_ofm_enter) begin 
                    dma_save_state <= DMA_SAVE_SETUP;
                end
            end

            DMA_SAVE_SETUP: begin
                dma_wr_max_req_blk_idx_r <= ceil_div64(q_frame_size<<2);
                dma_save_state <= DMA_SAVE_KICK;
            end

            DMA_SAVE_KICK: begin
                dma_save_wr_go_pulse <= 1;
                dma_save_state <= DMA_SAVE_WAIT;
            end

            DMA_SAVE_WAIT: begin
                if (write_done) begin 
                    dma_wr_blk_idx <= dma_wr_blk_idx + 1;
                end
                if (dma_ctrl_write_done) begin 
                    dma_save_state <= DMA_SAVE_IDLE;
                    
                    dma_wr_max_req_blk_idx_r <= 0;
                    dma_wr_blk_idx           <= 0;
                end
            end
        endcase
    end
end




//================================================================
// 6) dma instance
//================================================================
//----------------------------------------------------------------
axi_dma_ctrl #(.BIT_TRANS(BIT_TRANS))
u_dma_ctrl(
    .clk                  (clk                    ),
    .rstn                 (rstn                   ),

    // ----------- READ PLANE -----------
    .i_rd_start           (dma_rd_go              ),
    .i_rd_base_addr       (dma_rd_base_addr       ), 
    .i_rd_num_trans       (dma_rd_num_trans       ), // transaction needed (사실상 16 고정)
    .i_rd_max_req_blk_idx (dma_rd_max_req_blk_idx ), // 읽을 블록 개수
    .o_ctrl_read_done     (dma_ctrl_read_done     ),

    // DMA Read
    .i_read_done          (read_done              ),
    .o_ctrl_read          (ctrl_read              ), //when to read
    .o_read_addr          (read_addr              ), //where

    // ----------- WRITE PLANE ----------
    .i_wr_start           (dma_wr_go              ),
    .i_wr_base_addr       (dma_wr_base_addr       ), // dram write address
    .i_wr_num_trans       (dma_wr_num_trans       ), // ADD
    .i_wr_max_req_blk_idx (dma_wr_max_req_blk_idx ), // ADD
    
    .o_write_data_cnt     (write_data_cnt         ), // block 내에서 쓴 데이터 개수

    .o_ctrl_write_done    (dma_ctrl_write_done    ),

    // DMA Write
    .i_write_done         (write_done             ),
    .i_indata_req_wr      (indata_req_wr          ), // data req
    .o_ctrl_write         (ctrl_write             ), // when to write
    .o_write_addr         (write_addr             )
);


// DMA read module
axi_dma_rd #(
    .BITS_TRANS(BIT_TRANS),
    .OUT_BITS_TRANS(OUT_BITS_TRANS),    
    .AXI_WIDTH_USER(1),             // Master ID
    .AXI_WIDTH_ID(4),               // ID width in bits
    .AXI_WIDTH_AD(AXI_WIDTH_AD),    // address width
    .AXI_WIDTH_DA(AXI_WIDTH_DA),    // data width
    .AXI_WIDTH_DS(AXI_WIDTH_DS)     // data strobe width
    )
u_dma_read(
    //AXI Master Interface
    //Read address channel
    .M_ARVALID	(M_ARVALID	        ),  // address/control valid handshake
    .M_ARREADY	(M_ARREADY	        ),  // Read addr ready
    .M_ARADDR	(M_ARADDR	        ),  // Address Read
    .M_ARID		(M_ARID		        ),  // Read addr ID
    .M_ARLEN	(M_ARLEN	        ),  // Transfer length
    .M_ARSIZE	(M_ARSIZE	        ),  // Transfer width
    .M_ARBURST	(M_ARBURST	        ),  // Burst type
    .M_ARLOCK	(M_ARLOCK	        ),  // Atomic access information
    .M_ARCACHE	(M_ARCACHE	        ),  // Cachable/bufferable infor
    .M_ARPROT	(M_ARPROT	        ),  // Protection info
    .M_ARQOS	(M_ARQOS	        ),  // Quality of Service
    .M_ARREGION	(M_ARREGION	        ),  // Region signaling
    .M_ARUSER	(M_ARUSER	        ),  // User defined signal
 
    //Read data channel
    .M_RVALID	(M_RVALID	        ),  // Read data valid 
    .M_RREADY	(M_RREADY	        ),  // Read data ready (to Slave)
    .M_RDATA	(M_RDATA	        ),  // Read data bus
    .M_RLAST	(M_RLAST	        ),  // Last beat of a burst transfer
    .M_RID		(M_RID		        ),  // Read ID
    .M_RUSER	(M_RUSER	        ),  // User defined signal
    .M_RRESP	(M_RRESP	        ),  // Read response
     
    //Functional Ports
    .start_dma	(ctrl_read          ),
    .num_trans	(num_trans          ), // Number of 128-bit words transferred
    .start_addr	(read_addr          ), // iteration_num * 4 * 16 + read_address_d	
    //to bram
    .data_o		(axi_read_data      ),
    .data_vld_o	(axi_read_data_vld  ),
    .data_cnt_o	(read_data_cnt      ),
    .done_o		(read_done          ),

    //Global signals
    .clk        (clk                ),
    .rstn       (rstn               )
);

// DMA write module
axi_dma_wr #(
    .BITS_TRANS(BIT_TRANS),
    .OUT_BITS_TRANS(BIT_TRANS),    
    .AXI_WIDTH_USER(1),           // Master ID
    .AXI_WIDTH_ID(4),             // ID width in bits
    .AXI_WIDTH_AD(AXI_WIDTH_AD),  // address width
    .AXI_WIDTH_DA(AXI_WIDTH_DA),  // data width
    .AXI_WIDTH_DS(AXI_WIDTH_DS)   // data strobe width
    )
u_dma_write(
    .M_AWID		 (M_AWID	),  // Address ID
    .M_AWADDR	 (M_AWADDR	),  // Address Write
    .M_AWLEN	 (M_AWLEN	),  // Transfer length
    .M_AWSIZE	 (M_AWSIZE	),  // Transfer width
    .M_AWBURST	 (M_AWBURST	),  // Burst type
    .M_AWLOCK	 (M_AWLOCK	),  // Atomic access information
    .M_AWCACHE	 (M_AWCACHE	),  // Cachable/bufferable infor
    .M_AWPROT	 (M_AWPROT	),  // Protection info
    .M_AWREGION	 (M_AWREGION),
    .M_AWQOS	 (M_AWQOS	),
    .M_AWVALID	 (M_AWVALID	),  // address/control valid handshake
    .M_AWREADY	 (M_AWREADY	),
    .M_AWUSER    (          ),
    //Write data channel
    .M_WID		 (M_WID		),  // Write ID
    .M_WDATA	 (M_WDATA	),  // Write Data bus
    .M_WSTRB	 (M_WSTRB	),  // Write Data byte lane strobes
    .M_WLAST	 (M_WLAST	),  // Last beat of a burst transfer
    .M_WVALID	 (M_WVALID	),  // Write data valid
    .M_WREADY	 (M_WREADY	),  // Write data ready
    .M_WUSER     (          ),
    .M_BUSER     (          ),    
    //Write response chaDnel
    .M_BID		 (M_BID		),  // buffered response ID
    .M_BRESP	 (M_BRESP	),  // Buffered write response
    .M_BVALID	 (M_BVALID	),  // Response info valid
    .M_BREADY	 (M_BREADY	),  // Response info ready (to slave)
    //Read address channDl
    //User interface
    .start_dma	 (ctrl_write    ),
    .num_trans	 (num_trans     ), //Number of words transferred
    .start_addr	 (write_addr    ),
    .indata	     (write_data    ),
    .indata_req_o(indata_req_wr ),
    .done_o		 (write_done    ), //Blk transfer done
    .fail_check  (              ),
    //User signals
    .clk         (clk            ),
    .rstn        (rstn           )
);

//--------------------------------------------------------------------
// 
//--------------------------------------------------------------------
// 연결선

// BM read tap
wire                        tap_ifm_vld;
wire                        tap_ifm_read_vld;
wire [IFM_AW-1:0]           tap_ifm_read_addr;
wire [IFM_DW-1:0]           tap_ifm_read_data;

// BM route aux port
wire                        rte_ifm_vld;
wire                        rte_ifm_write_vld;
wire [IFM_AW-1:0]           rte_ifm_write_addr;
wire [IFM_DW-1:0]           rte_ifm_write_data;


// rte ports (when route load)  FIXME
wire                        rte_buf_load_vld;
wire [RTE_AW-1:0]           rte_buf_load_addr;
wire [FM_DW-1:0]            rte_buf_load_data;
wire                        rte_buf_load_done; 

// BM <-> PE (IFM/FILTER)
wire [IFM_DW-1:0]           ifm_data_0, ifm_data_1, ifm_data_2;
wire                        fb_req;
wire                        fb_req_possible;
wire [FILTER_AW-1:0]        fb_addr;
wire [FILTER_DW-1:0]        filter_data_0, filter_data_1, filter_data_2, filter_data_3;

    
// ctrl
wire                        bm_ofm_sync_done;  // ofm save done

//

wire                        ctrl_csync_run;
wire                        ctrl_psync_run;
wire                        ctrl_data_run;
wire                        ctrl_psync_phase;
wire [W_SIZE-1:0]           row;
wire [W_SIZE-1:0]           col;
wire [W_CHANNEL-1:0]        chn;
wire [W_CHANNEL-1:0]        chn_out;

wire                        fb_load_req;

wire                        is_first_row;
wire                        is_last_row;
wire                        is_first_col;
wire                        is_last_col; 
wire                        is_first_chn;
wire                        is_last_chn; 

// wire                        layer_done;
wire                        bm_csync_done;
wire                        pe_csync_done;

// pe -> postprocessor 연결선 
wire [PE_ACCO_FLAT_BW-1:0]  pe_data;
wire                        pe_vld;
wire [W_SIZE-1:0]           pe_row;
wire [W_SIZE-1:0]           pe_col;
wire [W_CHANNEL-1:0]        pe_chn;
wire [W_CHANNEL-1:0]        pe_chn_out;
wire                        pe_is_last_chn; 

// postprocessor
wire                        pp_load_done;
// pp -> buffer manager
wire                        pp_data_vld;
wire [OFM_DW-1:0]           pp_data;
wire [OFM_AW-1:0]           pp_addr;

wire [W_SIZE-1:0]           pp_row;
wire [W_SIZE-1:0]           pp_col;
wire [W_CHANNEL-1:0]        pp_chn_out;

// maxpool
wire                        mp_data_vld;
wire  [OFM_DW-1:0]          mp_data;
wire  [OFM_AW-1:0]          mp_addr;

// ofm mux
wire                        mux_ofm_data_vld = q_maxpool ? mp_data_vld : pp_data_vld;
wire  [OFM_DW-1:0]          mux_ofm_data     = q_maxpool ? mp_data     : pp_data;
wire  [OFM_AW-1:0]          mux_ofm_addr     = q_maxpool ? mp_addr     : pp_addr;

//---------------------------------------------------------------------- 
cnn_ctrl u_cnn_ctrl (
    .clk               (clk                 ),
    .rstn              (rstn                ),
    // Inputs
    .q_width           (q_width             ),
    .q_height          (q_height            ),
    .q_channel         (q_channel           ),
    .q_channel_out     (q_channel_out       ),
    .q_frame_size      (q_frame_size        ),
    .q_start           (q_c_ctrl_start      ),
    
    .bm_csync_done     (bm_csync_done       ),
    .pe_csync_done     (pe_csync_done       ),

    .pp_load_done      (pp_load_done        ),
    .ofm_sync_done     (bm_ofm_sync_done    ),
    
    // Outputs
    .o_ctrl_csync_run  (ctrl_csync_run      ),
    .o_ctrl_psync_run  (ctrl_psync_run      ),
    .o_ctrl_data_run   (ctrl_data_run       ),
    .o_ctrl_psync_phase(ctrl_psync_phase    ),
    .o_is_first_row    (is_first_row        ),
    .o_is_last_row     (is_last_row         ),
    .o_is_first_col    (is_first_col        ),
    .o_is_last_col     (is_last_col         ),
    .o_is_first_chn    (is_first_chn        ),
    .o_is_last_chn     (is_last_chn         ),
    .o_row             (row                 ),
    .o_col             (col                 ),
    .o_chn             (chn                 ),
    .o_chn_out         (chn_out             ),
    .o_fb_load_req     (fb_load_req         ),
    .o_layer_done      (layer_done          )
);
//---------------------------------------------------------------------- 
buffer_manager u_buffer_manager (
    .clk                (clk                ),
    .rstn               (rstn               ),

    // Buffer Manager <-> TOP
    .q_width            (q_width            ),
    .q_height           (q_height           ),
    .q_channel          (q_channel          ),
    .q_channel_out      (q_channel_out      ),
    .q_row_stride       (q_row_stride       ),

    .q_maxpool          (q_maxpool          ),
    .q_maxpool_stride   (q_maxpool_stride   ),
    .q_upsample         (q_upsample         ),

    .q_load_ifm         (q_load_ifm         ),
    .q_load_filter      (q_load_filter      ),

    .q_fm_buf_switch    (q_fm_buf_switch    ),

    // Buffer Manager ifm tap read
    .tap_ifm_vld        (tap_ifm_vld        ),   // *if activated, the function as another ifm buffer is interrupted.
    .tap_ifm_read_vld   (tap_ifm_read_vld   ),
    .tap_ifm_read_addr  (tap_ifm_read_addr  ),
    .tap_ifm_read_data  (tap_ifm_read_data  ),

    // aux port for route load (route buffer -> ifm buffer)
    // two functionality
    // 1. when route save -> pp result directly saved in buf destination
    // 2. when route load -> route buf data (FIXME: need to implement)
    .rte_ifm_vld        (rte_ifm_vld        ),   // must be separated from the area being calculated
    .rte_ifm_write_vld  (rte_ifm_write_vld  ),
    .rte_ifm_write_addr (rte_ifm_write_addr ),
    .rte_ifm_write_data (rte_ifm_write_data ),

    // Buffer Manager <-> AXI (IFM/FILTER)
    .read_data          (axi_read_data      ),
    .read_data_vld      (axi_read_data_vld  ),

    // Buffer Manager <-> Controller 
    .c_ctrl_data_run    (ctrl_data_run      ),
    .c_ctrl_csync_run   (ctrl_csync_run     ),
    .c_row              (row                ),
    .c_col              (col                ),
    .c_chn              (chn                ),

    .c_is_first_row     (is_first_row       ),
    .c_is_last_row      (is_last_row        ),
    .c_is_first_col     (is_first_col       ),
    .c_is_last_col      (is_last_col        ),
    .c_is_first_chn     (is_first_chn       ),
    .c_is_last_chn      (is_last_chn        ),

    .o_bm_csync_done    (bm_csync_done      ),
    .o_bm_ofm_sync_done (bm_ofm_sync_done   ),

    // Buffer Manager <-> pe_engine (IFM)
    .ib_data0_out       (ifm_data_0         ),
    .ib_data1_out       (ifm_data_1         ),
    .ib_data2_out       (ifm_data_2         ),

    // Buffer Manager <-> pe_engine (FILTER)
    .fb_req_possible    (fb_req_possible    ),
    .fb_req             (fb_req             ),
    .fb_addr            (fb_addr            ),

    .fb_data0_out       (filter_data_0      ),
    .fb_data1_out       (filter_data_1      ),
    .fb_data2_out       (filter_data_2      ),
    .fb_data3_out       (filter_data_3      ),

    // Buffer Manager <-> post processor or max pooling module
    .ofm_data_vld       (mux_ofm_data_vld   ),
    .ofm_data           (mux_ofm_data       ),
    .ofm_addr           (mux_ofm_addr       )
);
//---------------------------------------------------------------------- 
pe_engine u_pe_engine (
    .clk                (clk                ), 
    .rstn               (rstn               ),
    .c_ctrl_data_run    (ctrl_data_run      ),
    .c_ctrl_csync_run   (ctrl_csync_run     ),
    .c_row              (row                ),
    .c_col              (col                ),
    .c_chn              (chn                ),
    .c_chn_out          (chn_out            ),
    .c_is_first_row     (is_first_row       ),
    .c_is_last_row      (is_last_row        ),
    .c_is_first_col     (is_first_col       ),
    .c_is_last_col      (is_last_col        ),
    .c_is_first_chn     (is_first_chn       ),
    .c_is_last_chn      (is_last_chn        ),

    .q_channel          (q_channel          ),

    .o_pe_csync_done    (pe_csync_done      ),
    
    .ib_data0_in        (ifm_data_0         ), 
    .ib_data1_in        (ifm_data_1         ), 
    .ib_data2_in        (ifm_data_2         ),
    
    .fb_req_possible    (fb_req_possible    ),
    .o_fb_req           (fb_req             ),
    .o_fb_addr          (fb_addr            ),

    .fb_data0_in        (filter_data_0      ),
    .fb_data1_in        (filter_data_1      ),
    .fb_data2_in        (filter_data_2      ),
    .fb_data3_in        (filter_data_3      ),

    // pe_engine -> postprocessor
    .o_pe_data          (pe_data            ),
    .o_pe_vld           (pe_vld             ), 
    .o_pe_row           (pe_row             ),
    .o_pe_col           (pe_col             ),
    .o_pe_chn           (pe_chn             ),
    .o_pe_chn_out       (pe_chn_out         ),
    .o_pe_is_first_chn  (pe_is_first_chn    ),
    .o_pe_is_last_chn   (pe_is_last_chn     ) 
);
//---------------------------------------------------------------------- 
postprocessor u_postprocessor (
    .clk                (clk                ),
    .rstn               (rstn               ),

    // postprocessor <-> top
    .q_width            (q_width            ),
    .q_height           (q_height           ),
    .q_channel          (q_channel          ),
    .q_channel_out      (q_channel_out      ),


    .q_load_bias        (q_load_bias        ),
    .q_load_scale       (q_load_scale       ),

    // postprocessor <-> ctrl
    .c_ctrl_csync_run   (ctrl_csync_run     ),
    .c_ctrl_psync_run   (ctrl_psync_run     ),
    .c_ctrl_psync_phase (ctrl_psync_phase   ),

    .c_ctrl_chn_out     (chn_out            ),

    .o_pp_load_done     (pp_load_done       ),

    // postprocessor <-> AXI
    .read_data          (axi_read_data      ),
    .read_data_vld      (axi_read_data_vld  ),

    // postprocessor <-> pe_engine
    .pe_data_i          (pe_data            ),
    .pe_vld_i           (pe_vld             ), 
    .pe_row_i           (pe_row             ),
    .pe_col_i           (pe_col             ),
    .pe_chn_i           (pe_chn             ),
    .pe_chn_out_i       (pe_chn_out         ),
    .pe_is_first_chn_i  (pe_is_first_chn    ),
    .pe_is_last_chn_i   (pe_is_last_chn     ),

    // postprocessor <-> buffer_manager
    .o_pp_data_vld      (pp_data_vld        ),
    .o_pp_data          (pp_data            ),
    .o_pp_addr          (pp_addr            ),

    .o_pp_row           (pp_row             ),
    .o_pp_col           (pp_col             ),
    .o_pp_chn_out       (pp_chn_out         )
);
//----------------------------------------------------------------------  
maxpool u_maxpool (
    .clk                (clk                ),
    .rstn               (rstn               ),

    // maxpool <-> top
    .q_channel_out      (q_channel_out      ),

    .q_maxpool_stride   (q_maxpool_stride   ),

    // maxpool <-> postprocessor
    .pp_data_vld        (pp_data_vld        ),
    .pp_data            (pp_data            ),
    .pp_row             (pp_row             ), 
    .pp_col             (pp_col             ), 
    .pp_chn_out         (pp_chn_out         ),

    // maxpool <-> buffer manager
    .o_mp_data_vld      (mp_data_vld        ),
    .o_mp_data          (mp_data            ),
    .o_mp_addr          (mp_addr            )
);


route_buffer u_route_buffer (
    .clk                (clk                ),
    .rstn               (rstn               ),

    // top
    .q_route_save       (q_route_save       ),
    .q_route_load       (q_route_load       ),
    .q_route_loc        (q_route_loc        ),
    .q_route_offset     (q_route_offset     ),

    // postprocessor
    .pp_data_vld        (pp_data_vld        ),
    .pp_data            (pp_data            ),
    .pp_addr            (pp_addr            ),

    // buffer manager
    .rte_ifm_vld        (rte_ifm_vld        ),
    .rte_ifm_write_vld  (rte_ifm_write_vld  ),
    .rte_ifm_write_addr (rte_ifm_write_addr ),
    .rte_ifm_write_data (rte_ifm_write_data ),

    // route load
    .rte_buf_load_vld   (rte_buf_load_vld   ),  // input
    .rte_buf_load_addr  (rte_buf_load_addr  ),  // output
    .rte_buf_load_data  (rte_buf_load_data  ),  // output
    .rte_buf_load_done  (rte_buf_load_done  )   // output
);

endmodule
