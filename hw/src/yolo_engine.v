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

)
(
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
reg [AXI_WIDTH_AD-1:0] dram_base_addr_ofm;

reg  debug_on;

always @ (*) begin
    // ap_done     = ctrl_write_done;
    ap_ready    = 1;
end
assign network_done     = interrupt;
assign network_done_led = interrupt;


always @ (posedge clk or negedge rstn) begin
    if(~rstn) begin
        ap_start <= 0;
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
        if(!ap_start && i_ctrl_reg0[0]) begin 
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


            debug_on <= i_ctrl_reg0[1];

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

            debug_on <= 0;
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


function [31:0] w_off_words; input [3:0] idx; begin
  case(idx)
    0: w_off_words =          0;      // L0  : 432
    1: w_off_words =        432;      // L2  : 4608
    2: w_off_words =       5040;      // L4  : 18432
    3: w_off_words =      23472;      // L6  : 73728
    4: w_off_words =      97200;      // L8  : 294912
    5: w_off_words =     392112;      // L10 : 1179648
    6: w_off_words =    1571760;      // L12 : 131072
    7: w_off_words =    1702832;      // L13 : 1179648
    8: w_off_words =    2882480;      // L14 : 99840
    9: w_off_words =    2982320;      // L17 : 32768
   10: w_off_words =    3015088;      // L20 : 74880
    default: w_off_words = 0;
  endcase
end endfunction


function [31:0] w_grp_words; input [3:0] idx; begin
  case(idx)
     0: w_grp_words =   108;   // L0 : Cin=3,   3x3
     1: w_grp_words =   576;   // L2 : Cin=16,  3x3
     2: w_grp_words =  1152;   // L4 : Cin=32,  3x3
     3: w_grp_words =  2304;   // L6 : Cin=64,  3x3
     4: w_grp_words =  4608;   // L8 : Cin=128, 3x3
     5: w_grp_words =  9216;   // L10: Cin=256, 3x3
     6: w_grp_words =  2048;   // L12: Cin=512, 1x1
     7: w_grp_words =  9216;   // L13: Cin=256, 3x3
     8: w_grp_words =  2048;   // L14: Cin=512, 1x1
     9: w_grp_words =  1024;   // L17: Cin=256, 1x1
    10: w_grp_words =  1536;   // L20: Cin=384, 1x1
    default: w_grp_words = 0;
  endcase
end endfunction
function [15:0] w_grp_total; input [3:0] idx; begin
  case(idx)
     0: w_grp_total =  4;   // 16/4
     1: w_grp_total =  8;   // 32/4
     2: w_grp_total = 16;   // 64/4
     3: w_grp_total = 32;   // 128/4
     4: w_grp_total = 64;   // 256/4
     5: w_grp_total =128;   // 512/4
     6: w_grp_total = 64;   // 256/4
     7: w_grp_total =128;   // 512/4
     8: w_grp_total = 49;   // ceil(195/4)
     9: w_grp_total = 32;   // 128/4
    10: w_grp_total = 49;   // ceil(195/4)
    default: w_grp_total = 0;
  endcase
end endfunction


//================================================================
// 3) TOP state machine
//================================================================
reg [4:0]                   q_layer;        // layer index

// layer informations -> hard coding
reg  [W_SIZE-1:0]           q_width;
reg  [W_SIZE-1:0]           q_height;
reg  [W_CHANNEL-1:0]        q_channel;
reg  [W_CHANNEL-1:0]        q_channel_out;
reg  [W_FRAME_SIZE-1:0]     q_frame_size;
reg  [W_SIZE+W_CHANNEL-1:0] q_row_stride;
reg                         q_maxpool;
reg                         q_upsample;

reg                         q_c_ctrl_start;  // cnn_ctrl start signal (q_start)
reg                         q_load_ifm;
reg                         q_load_filter;
reg                         q_load_bias;
reg                         q_load_scale;


// 관찰용 완료 신호(하위에서 만들어 줘야 함)
//  - IFM 초기 적재 완료: buffer_manager(or DMA 프론트엔드)에서 발생
//  - 한 레이어 연산 완료: cnn_ctrl에서 제공 (기존 layer_done 사용)
//  - OFM 저장 완료: writer(또는 postprocessor→writer)에서 발생
wire dma_ifm_load_done;    // TODO: buffer_manager에 포트 추가하여 연결
wire ofm_write_done;   // TODO: OFM writer 모듈 done 신호 연결
wire layer_done;       // 이미 cnn_ctrl에서 나옴


reg [2:0] q_state;

localparam 
    S_IDLE          = 3'd0, 
    S_LOAD_IFM      = 3'd1, // initial once
    S_SAVE_OFM      = 3'd2, // layer 14, 20
    S_LOAD_CFG      = 3'd3,
    S_WAIT_CNN_CTRL = 3'd4;  // each layer



always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        q_state          <= S_IDLE;
        q_layer          <= 0;
        q_c_ctrl_start   <= 0;

        q_layer         <= 0;
        q_width         <= 0;
        q_height        <= 0;
        q_channel       <= 0;
        q_channel_out   <= 0;
        q_frame_size    <= 0;
        q_row_stride    <= 0;
        q_maxpool       <= 0;
        q_upsample      <= 0;

        q_load_ifm <= 0;
        q_load_filter <= 0;
        q_load_bias <= 0;
        q_load_scale <= 0;

        // layer info reset...

    end
    else begin
        q_c_ctrl_start <= 1'b0; // pulse

        case (q_state)
            S_IDLE: begin
                if (ap_start) begin
                    q_layer     <= 0;
                    q_state <= S_LOAD_CFG;
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
            
            S_LOAD_CFG: begin
                if (debug_on) begin 
                    // 우선은 여기로만 들어옴.
                    q_layer         <= 20;
                    q_width         <= TEST_COL;       // 16
                    q_height        <= TEST_ROW;       // 16
                    q_channel       <= TEST_T_CHNIN;   // 16 (4)
                    q_channel_out   <= TEST_T_CHNOUT;  // 32 (8) 
                    q_frame_size    <= TEST_FRAME_SIZE;
                    q_row_stride    <= TEST_COL * TEST_T_CHNIN;
                    q_maxpool       <= 1;
                    // 만약 레이어가 늘어나면 분기하는 로직이 필요함.
                    q_state <= S_LOAD_IFM;
                end else begin 
                    // layer 정보 불러오기 
                    // a. q_* reg 에 값 할당
                    // b. dram base addr fix
                    // layer 0면 LOAD_IFM으로 전이
                    // 그 외 layer면 q_c_ctrl_start = 1로 바꾸고 (1cycle) WAIT_CNN_CTRL로 전이
                    // special layer 처리

                    // 아직 구현할 필요 없음 
                end
            end

            S_SAVE_OFM: begin 
                // pass
                // 아직 구현할 필요 없음 
            end


            S_WAIT_CNN_CTRL: begin 
                if (layer_done) begin 
                    // bebug end
                    if (q_layer == 20) begin 
                        q_state <= S_IDLE;
                        ap_done <= 1;
                    end
                    else begin 
                        // layer_done -> q_layer 올리고 S_LOAD_CFG로 전이
                        // 아직 구현할 필요 없음
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
// write는 아직 미완



// 연결선
// Signals for dma read  
wire                    ctrl_read;
wire                    read_done;
wire [AXI_WIDTH_AD-1:0] read_addr;
wire [AXI_WIDTH_DA-1:0] axi_read_data;
wire                    axi_read_data_vld;
wire [BIT_TRANS   -1:0] read_data_cnt;

// Signals for dma write
wire ctrl_write_done;
wire ctrl_write;
wire write_done;
wire indata_req_wr;
wire [BIT_TRANS   -1:0] write_data_cnt;
wire [AXI_WIDTH_AD-1:0] write_addr;
wire [AXI_WIDTH_DA-1:0] write_data;


wire[BIT_TRANS   -1:0] num_trans        = 16;           // BURST_LENGTH = 16

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
// assign dma_rd_max_req_blk_idx  = (dma_load_cur_sel == SEL_IFM)    ? dma_ifm_rd_max_req_blk_idx
//                                : (dma_load_cur_sel == SEL_FILTER) ? dma_filter_rd_max_req_blk_idx
//                                : (dma_load_cur_sel == SEL_BIAS)   ? dma_bias_rd_max_req_blk_idx
//                                : (dma_load_cur_sel == SEL_SCALE)  ? dma_scale_rd_max_req_blk_idx
//                                : 0;


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

        // 상위가 stage를 떠났으면 FSM 정리
        if ((in_load_ifm_leave && (dma_load_cur_sel==SEL_IFM)) ||
            (in_load_filter_leave && (dma_load_cur_sel==SEL_FILTER)) ||
            (in_load_affine_leave && ((dma_load_cur_sel==SEL_BIAS)||(dma_load_cur_sel==SEL_SCALE)))) begin
            dma_load_state       <= DMA_LOAD_IDLE;
            dma_load_cur_sel     <= SEL_NONE;
            dma_load_kicked      <= 1'b0;
            in_load_affine_phase <= 0;
        end

        case (dma_load_state)
            // ------------------------------------------------
            DMA_LOAD_IDLE: begin
                // dma_load_cur_sel <= SEL_NONE;

                // 발행 한적 없을 때
                if (!dma_load_kicked && in_load_ifm_stage) begin
                    dma_load_cur_sel <= SEL_IFM;
                    dma_load_state   <= DMA_LOAD_SETUP;
                end
                else if (!dma_load_kicked && in_load_filter_stage) begin
                    dma_load_cur_sel <= SEL_FILTER;
                    dma_load_state   <= DMA_LOAD_SETUP;
                end
                else if (!dma_load_kicked && in_load_affine_stage) begin
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
                // Option A: strictly wait for both controls
                if (dma_ctrl_read_done) begin
                    case (dma_load_cur_sel)
                        SEL_IFM: begin
                            dma_load_state        <= DMA_LOAD_IDLE;
                            q_load_ifm            <= 1'b0;
                            dma_ifm_load_done_reg <= 1'b1;
                        end
                        SEL_FILTER: begin 
                            dma_load_state           <= DMA_LOAD_IDLE;
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
                            dma_scale_load_done_reg <= 1'b1;

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
// 5-1) DMA write
//----------------------------------------------------------------
// ...



//================================================================
// 5) dma instance
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
    .i_wr_base_addr       (dma_wr_base_addr       ), //dram write address
    .i_indata_req_wr      (indata_req_wr          ),
    .o_ctrl_write_done    (ctrl_write_done        ),

    // DMA Write
    .i_write_done         (write_done             ),
    .o_ctrl_write         (ctrl_write             ), //when to write
    .o_write_addr         (write_addr             ),
    .o_write_data_cnt     (write_data_cnt         )
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
    .M_ARVALID	(M_ARVALID	  ),  // address/control valid handshake
    .M_ARREADY	(M_ARREADY	  ),  // Read addr ready
    .M_ARADDR	(M_ARADDR	  ),  // Address Read
    .M_ARID		(M_ARID		  ),  // Read addr ID
    .M_ARLEN	(M_ARLEN	  ),  // Transfer length
    .M_ARSIZE	(M_ARSIZE	  ),  // Transfer width
    .M_ARBURST	(M_ARBURST	  ),  // Burst type
    .M_ARLOCK	(M_ARLOCK	  ),  // Atomic access information
    .M_ARCACHE	(M_ARCACHE	  ),  // Cachable/bufferable infor
    .M_ARPROT	(M_ARPROT	  ),  // Protection info
    .M_ARQOS	(M_ARQOS	  ),  // Quality of Service
    .M_ARREGION	(M_ARREGION	  ),  // Region signaling
    .M_ARUSER	(M_ARUSER	  ),  // User defined signal
 
    //Read data channel
    .M_RVALID	(M_RVALID	  ),  // Read data valid 
    .M_RREADY	(M_RREADY	  ),  // Read data ready (to Slave)
    .M_RDATA	(M_RDATA	  ),  // Read data bus
    .M_RLAST	(M_RLAST	  ),  // Last beat of a burst transfer
    .M_RID		(M_RID		  ),  // Read ID
    .M_RUSER	(M_RUSER	  ),  // User defined signal
    .M_RRESP	(M_RRESP	  ),  // Read response
     
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
    .M_AWID		(M_AWID		),  // Address ID
    .M_AWADDR	(M_AWADDR	),  // Address Write
    .M_AWLEN	(M_AWLEN	),  // Transfer length
    .M_AWSIZE	(M_AWSIZE	),  // Transfer width
    .M_AWBURST	(M_AWBURST	),  // Burst type
    .M_AWLOCK	(M_AWLOCK	),  // Atomic access information
    .M_AWCACHE	(M_AWCACHE	),  // Cachable/bufferable infor
    .M_AWPROT	(M_AWPROT	),  // Protection info
    .M_AWREGION	(M_AWREGION	),
    .M_AWQOS	(M_AWQOS	),
    .M_AWVALID	(M_AWVALID	),  // address/control valid handshake
    .M_AWREADY	(M_AWREADY	),
    .M_AWUSER   (           ),
    //Write data channel
    .M_WID		(M_WID		),  // Write ID
    .M_WDATA	(M_WDATA	),  // Write Data bus
    .M_WSTRB	(M_WSTRB	),  // Write Data byte lane strobes
    .M_WLAST	(M_WLAST	),  // Last beat of a burst transfer
    .M_WVALID	(M_WVALID	),  // Write data valid
    .M_WREADY	(M_WREADY	),  // Write data ready
    .M_WUSER    (           ),
    .M_BUSER    (           ),    
    //Write response chaDnel
    .M_BID		(M_BID		),  // buffered response ID
    .M_BRESP	(M_BRESP	),  // Buffered write response
    .M_BVALID	(M_BVALID	),  // Response info valid
    .M_BREADY	(M_BREADY	),  // Response info ready (to slave)
    //Read address channDl
    //User interface
    .start_dma	(ctrl_write     ),
    .num_trans	(num_trans      ), //Number of words transferred
    .start_addr	(write_addr     ),
    .indata		(write_data     ),
    .indata_req_o(indata_req_wr ),
    .done_o		(write_done     ), //Blk transfer done
    .fail_check (               ),
    //User signals
    .clk        (clk            ),
    .rstn       (rstn           )
);

//--------------------------------------------------------------------
// 
//--------------------------------------------------------------------
// 연결선

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

wire                        layer_done;
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
    .q_upsample         (q_upsample         ),

    .q_load_ifm         (q_load_ifm         ),
    .q_load_filter      (q_load_filter      ),

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
    .q_width            (q_width            ),
    .q_height           (q_height           ),
    .q_channel_out      (q_channel_out      ),

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


endmodule
