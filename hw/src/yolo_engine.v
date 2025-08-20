`include "controller_params.vh"
//----------------------------------------------------------------+
// Project: Deep Learning Hardware Design Contest
// Module: yolo_engine
// Description:
//		Load parameters and input feature map from DRAM via AXI4
//
// 2023.04.05 by NXT (truongnx@capp.snu.ac.kr)
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
    
    parameter W_SIZE        = `W_SIZE,
    parameter W_CHANNEL     = `W_CHANNEL,
    parameter W_FRAME_SIZE  = `W_FRAME_SIZE,
    parameter W_DELAY       = `W_DELAY
)
(
    input                          clk, 
    input                          rstn,

    input [31:0] i_ctrl_reg0,    // network_start, // {debug_big(1), debug_buf_select(16), debug_buf_addr(9)}
    input [31:0] i_ctrl_reg1,    // Read address base -> ifm, filter, bias, scale
    input [31:0] i_ctrl_reg2,    // Write address base -> ofm
    input [31:0] i_ctrl_reg3,    // Write address base

    output                         M_ARVALID,
    input                          M_ARREADY,
    output  [AXI_WIDTH_AD-1:0]     M_ARADDR,
    output  [AXI_WIDTH_ID-1:0]     M_ARID,
    output  [7:0]                  M_ARLEN,
    output  [2:0]                  M_ARSIZE,
    output  [1:0]                  M_ARBURST,
    output  [1:0]                  M_ARLOCK,
    output  [3:0]                  M_ARCACHE,
    output  [2:0]                  M_ARPROT,
    output  [3:0]                  M_ARQOS,
    output  [3:0]                  M_ARREGION,
    output  [3:0]                  M_ARUSER,
    input                          M_RVALID,
    output                         M_RREADY,
    input  [AXI_WIDTH_DA-1:0]      M_RDATA,
    input                          M_RLAST,
    input  [AXI_WIDTH_ID-1:0]      M_RID,
    input  [3:0]                   M_RUSER,
    input  [1:0]                   M_RRESP,

    output                         M_AWVALID,
    input                          M_AWREADY,
    output  [AXI_WIDTH_AD-1:0]     M_AWADDR,
    output  [AXI_WIDTH_ID-1:0]     M_AWID,
    output  [7:0]                  M_AWLEN,
    output  [2:0]                  M_AWSIZE,
    output  [1:0]                  M_AWBURST,
    output  [1:0]                  M_AWLOCK,
    output  [3:0]                  M_AWCACHE,
    output  [2:0]                  M_AWPROT,
    output  [3:0]                  M_AWQOS,
    output  [3:0]                  M_AWREGION,
    output  [3:0]                  M_AWUSER,
    
    output                         M_WVALID, 
    input                          M_WREADY, 
    output  [AXI_WIDTH_DA-1:0]     M_WDATA, 
    output  [AXI_WIDTH_DS-1:0]     M_WSTRB, 
    output                         M_WLAST, 
    output  [AXI_WIDTH_ID-1:0]     M_WID, 
    output  [3:0]                  M_WUSER,
    
    input                          M_BVALID,
    output                         M_BREADY,
    input  [1:0]                   M_BRESP,
    input  [AXI_WIDTH_ID-1:0]      M_BID,
    input                          M_BUSER,
    
    output network_done,
    output network_done_led   
);
`include "define.v"

// parameter BUFF_DEPTH    = 256;
// parameter BUFF_ADDR_W   = $clog2(BUFF_DEPTH);
// localparam BIT_TRANS = BUFF_ADDR_W;

parameter DRAM_FILTER_OFFSET = 256 * 256;
parameter DRAM_BIAS_OFFSET   = DRAM_FILTER_OFFSET + 512 // (# of filters, not real)
parameter DRAM_SCALE_OFFSET  = DRAM_BIAS_OFFSET + 512   // (# of bias, not real)


//CSR
reg ap_start;
reg ap_ready;
reg ap_done;
reg interrupt;

//pe engine
reg pe_start;

// address
reg [31:0] dram_base_addr_rd;
reg [31:0] dram_base_addr_wr;
reg [31:0] reserved_register;

reg [31:0] dram_base_addr_ifm;
reg [31:0] dram_base_addr_filter;
reg [31:0] dram_base_addr_bias;
reg [31:0] dram_base_addr_scale;
reg [31:0] dram_base_addr_ofm;


// Signals for dma read  
wire ctrl_read;
wire read_done;
wire [AXI_WIDTH_AD-1:0] read_addr;
wire [AXI_WIDTH_DA-1:0] read_data;
wire                    read_data_vld;
wire [BIT_TRANS   -1:0] read_data_cnt;
wire ctrl_read_done;

// Signals for dma write
wire ctrl_write_done;
wire ctrl_write;
wire write_done;
wire indata_req_wr;
wire [BIT_TRANS   -1:0] write_data_cnt;
wire [AXI_WIDTH_AD-1:0] write_addr;
wire [AXI_WIDTH_DA-1:0] write_data;

// FIX ME
wire[BIT_TRANS   -1:0] num_trans        = 16;           // BURST_LENGTH = 16

//wire[            15:0] max_req_blk_idx  = (256*256)/16; // The number of blocks

//================================================================
// 1) Control signals
//================================================================
always @ (*) begin
    ap_done     = ctrl_write_done;
    ap_ready    = 1;
end
assign network_done     = interrupt;
assign network_done_led = interrupt;


always @ (posedge clk, negedge rstn) begin
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

always @(posedge clk, negedge rstn) begin
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
always @ (posedge clk, negedge rstn) begin
    if(~rstn) begin
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
        end 
    end 
end
//================================================================
// 2) tools
//================================================================

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

// wire burst_first=read_data_vld&&(blk_read==0)&&(read_data_cnt==0);




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

reg                         q_c_ctrl_start; // cnn_ctrl start signal
reg                         q_load_ifm;
reg                         q_load_filter;
reg                         q_load_bias;
reg                         q_load_scale;



// pulse
assign q_load_ifm = phase_ifm & read_data_vld;
assign q_load_filter = (~phase_ifm) & read_data_vld;

localparam integer IFM_BYTES=256*256*3;
localparam integer BYTES_PER_BURST=16*(AXI_WIDTH_DA/8); 
localparam integer IFM_BLOCKS =IFM_BYTES/BYTES_PER_BURST;

// wire [15:0] blk_read;


// reg [AXI_WIDTH_AD:0] rd_base_addr_reg;
reg [15:0] rd_blocks_reg;


reg rd_go, wr_go;
reg [1:0] q_state;

localparam 
    S_IDLE          = 0, 
    S_LOAD_IFM      = 1, // initial once
    S_SAVE_OFM      = 2, // layer 14, 20
    S_LOAD_CFG      = 3,
    S_WAIT_CNN_CTRL = 4  // each layer




// reg [9:0] idx_group;
// reg phase_ifm;          //1: ifm phase, 0: weight phase
// reg start_d1;


always @(posedge clk or negedge rstn) begin
    if(!rstn) begin
        phase_ifm        <= 1'b1;
        q_layer          <= 0;
        start_d1         <= 0;
        idx_group        <= 0;
        // rd_base_addr_reg <= 32'd0;
        rd_blocks_reg    <= 0;
        rd_go            <= 0;
        q_state          <= S_IDLE;
    end
    else begin
        rd_go<=1'd0;
        pe_start<=0;

        case (q_state)
            S_IDLE: begin
                if (ap_start) begin
                    // phase_ifm   <= 1;
                    q_layer     <= 0;
                    idx_group   <= 0;
                    rd_blocks_reg <= IFM_BLOCKS[15:0];

                    q_state <= S_LOAD_CFG;
                end else begin 
                    q_state <= S_IDLE;
                end
            end
            
            S_LOAD_IFM: begin
                // ifm 불러오는 단계
                // 다 불러온것이 확인되면 q_c_ctrl_start = 1로 바꾸고 (1cycle) WAIT_CNN_CTRL로 전이
                // q_c_ctrl_start가 굳이 한사이클일 필요는 없음. 대신 계산이 끝나기 전에 다시 0으로 바꿔줄 필요가 있음.

                // if(ctrl_read_done) begin
                //     phase_ifm<=1'b0;
                //     q_layer <=4'd0;
                //     idx_group<=0;
                //     rd_base_addr_reg<=i_ctrl_reg3 + 4*(w_off_words(4'd0)+w_grp_words(4'd0)*0);
                //     rd_blocks_reg<=blk16(w_grp_words(4'd0));
                //     rd_go<=1'b1;
                //     q_state<=S_WAIT_WG;
                    
            end            
            
            S_LOAD_CFG: begin
                // 우선 layer 정보 불러오기 
                // layer 0면 LOAD_IFM으로 전이
                // 그 외 layer면 q_c_ctrl_start = 1로 바꾸고 (1cycle) WAIT_CNN_CTRL로 전이
            end

            S_WAIT_CNN_CTRL: begin 
                // c_layer_done 시그널 대기
                // layer_done -> q_layer 올리고 S_LOAD_CFG로 전이
            end
            



            // S_WAIT_WG: begin
            //     if(ctrl_read_done&&o_load_filter_done) begin
            //         pe_start<=1'b1;
            //         s<=S_WAIT_PE;
            //     end
            // end
            
            // S_WAIT_PE: begin
            //     if (pe_done) begin
            //         if (idx_group+1<w_grp_total(q_layer)) begin
            //             idx_group<=idx_group+1;
            //             rd_base_addr_reg<=i_ctrl_reg3+4*(w_off_words(q_layer)+w_grp_words(q_layer)*(idx_group+1'b1));
            //             rd_blocks_reg<=blk16(w_grp_words(q_layer));

            //         end else if (q_layer+1<N_LAYER) begin
            //             q_layer<=q_layer+1;
            //             idx_group<=0;
            //             rd_base_addr_reg<=i_ctrl_reg3+4*(w_off_words(q_layer+1'b1));
            //             rd_blocks_reg    <= blk16( w_grp_words(q_layer + 1'b1) );
            //         end else begin
            //             //
            //         end
            //     end
                
            // end
               
        endcase
        
    /*
        start_d1<=i_ctrl_reg0[0];

        if(start_d1) begin
            //first layer begin
            phase_ifm<=1;
            q_layer<=4'd0;
            idx_group<=0;
            rd_base_addr_reg<=i_ctrl_reg1;
            rd_blocks_reg<=IFM_BLOCKS[15:0];

        end
        else if(ctrl_read_done) begin
            if(phase_ifm) begin
            //ifm ended->weight phase
            //start form layer0, group0
                phase_ifm<=1'b0;
                q_layer <=4'd0;
                idx_group<=0;
                rd_base_addr_reg<=i_ctrl_reg3 + 4*(w_off_words(4'd0)+w_grp_words(4'd0)*0);
                rd_blocks_reg<=blk16(w_grp_words(4'd0));
            end
            else begin//wait until the pe engine is done
                //?���? weight group?�� ???�� 진행
                if(idx_group+1<w_grp_total(q_layer)) begin
                    //?�� ?��?��?�� ?��?�� 그룹 
                    idx_group<=idx_group+1;
                    rd_base_addr_reg<=i_ctrl_reg3+4*(w_off_words(q_layer)+w_grp_words(q_layer)*(idx_group+1'b1));
                    rd_blocks_reg<=blk16(w_grp_words(q_layer));

                end else if(q_layer+1<N_LAYER) begin
                    //?��?�� ?��?��?�� �? 그룹
                    q_layer<=q_layer+1;
                    idx_group<=0;
                    rd_base_addr_reg<=i_ctrl_reg3+4*(w_off_words(q_layer+1'b1));
                    rd_blocks_reg    <= blk16( w_grp_words(q_layer + 1'b1) );
                end else begin
                    //모든 ?��?��?�� ?���? ?��, ?��?�� ?��?��
                end
            end
        end
    */
    end
end


//================================================================
// 4) DMA request logic
//================================================================
// axi_dma_ctrl 에 넣어줄 데이터 만들기!

// 1. ifm 로드
// q_state == S_LOAD_IFM 일 때 ifm 로드

// 2. filter 로드
// cnn_ctrl 이 생성하는 csync state에서 filter 로드 시작.
// q_layer, tout 바탕으로 base address 계산
// layer info 바탕으로 읽어야할 데이터 개수 계산
// 그걸 바탕으로 block, trans 계산

// 3. bias, scale 로드
// cnn_ctrl 이 생성하는 psync state && psync phase == 0 에서 bias와 scale 로드 시작.


// 4. ofm write
// 나중에 생각하기



//================================================================
// 5) 
//================================================================
//----------------------------------------------------------------
//read, write
axi_dma_ctrl #(.BIT_TRANS(BIT_TRANS))
u_dma_ctrl(
    .clk              (clk              ),
    .rstn             (rstn             ),

    .i_rd_start       (rd_go            ), //start reading
    .i_wr_start       (wr_go            ),
    .i_base_address_rd(rd_base_addr_reg ), /*dram_base_addr_rd*/ //dram read address
    .i_base_address_wr(dram_base_addr_wr), //dram write address
    .i_num_trans      (num_trans        ), //transaction needed
    .i_max_req_blk_idx(rd_blocks_reg    ), /*max_req_blk_idx*/
    // DMA Read
    .i_read_done      (read_done        ),
    .o_ctrl_read      (ctrl_read        ), //when to read
    .o_read_addr      (read_addr        ), //where
    // .o_blk_read(blk_read)
    // DMA Write
    .i_indata_req_wr  (indata_req_wr    ),
    .i_write_done     (write_done       ),
    .o_ctrl_write     (ctrl_write       ), //when to write
    .o_write_addr     (write_addr       ),
    .o_write_data_cnt (write_data_cnt   ),
    .o_ctrl_write_done(ctrl_write_done  ),
    .o_ctrl_read_done (ctrl_read_done   )
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
    .M_ARADDR	(M_ARADDR	  ),  // Address Read ?��?�� ?��?�� ?��?��?���? 밖으�? 보낸?��
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
    .start_dma	(ctrl_read    ),
    .num_trans	(num_trans    ), //Number of 128-bit words transferred
    .start_addr	(read_addr    ), //iteration_num * 4 * 16 + read_address_d	
    //to bram
    .data_o		(read_data    ),
    .data_vld_o	(read_data_vld),
    .data_cnt_o	(read_data_cnt),
    .done_o		(read_done    ),

    //Global signals
    .clk        (clk          ),
    .rstn       (rstn         )
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

// top
reg  [W_SIZE+W_CHANNEL-1:0] q_row_stride;
reg  [4:0]                  q_layer;
reg                         q_load_ifm;
reg                         q_load_filter;
wire                        load_filter_done;




// 연결선
// BM <-> PE (IFM/FILTER)
wire [IFM_DW-1:0]           ifm_data_0, ifm_data_1, ifm_data_2;
wire                        fb_req;
wire                        fb_req_possible;
wire [FILTER_AW-1:0]        fb_addr;
wire [FILTER_DW-1:0]        filter_data_0, filter_data_1, filter_data_2, filter_data_3;

// ctrl
wire                     pb_sync_done;

//
reg  [W_SIZE-1:0]        q_width;
reg  [W_SIZE-1:0]        q_height;
reg  [W_CHANNEL-1:0]     q_channel;
reg  [W_CHANNEL-1:0]     q_channel_out;
reg  [W_FRAME_SIZE-1:0]  q_frame_size;
reg                      q_start;

wire                     ctrl_csync_run;
wire                     ctrl_psync_run;
wire                     ctrl_data_run;
wire                     ctrl_psync_phase;
wire [W_SIZE-1:0]        row;
wire [W_SIZE-1:0]        col;
wire [W_CHANNEL-1:0]     chn;
wire [W_CHANNEL-1:0]     chn_out;

wire                     fb_load_req;

wire                     is_first_row;
wire                     is_last_row;
wire                     is_first_col;
wire                     is_last_col; 
wire                     is_first_chn;
wire                     is_last_chn; 

wire                     layer_done;
wire                     bm_csync_done;
wire                     pe_csync_done;

// pe -> postprocessor 연결선 
wire [PE_ACCO_FLAT_BW-1:0]   pe_data;
wire                         pe_vld;
wire [W_SIZE-1:0]            pe_row;
wire [W_SIZE-1:0]            pe_col;
wire [W_CHANNEL-1:0]         pe_chn;
wire [W_CHANNEL-1:0]         pe_chn_out;
wire                         pe_is_last_chn; 


//---------------------------------------------------------------------- 
cnn_ctrl u_cnn_ctrl (
    .clk               (clk               ),
    .rstn              (rstn              ),
    // Inputs
    .q_width           (q_width           ),
    .q_height          (q_height          ),
    .q_channel         (q_channel         ),
    .q_channel_out     (q_channel_out     ),
    .q_frame_size      (q_frame_size      ),
    .q_start           (q_start           ),
    .pb_sync_done      (pb_sync_done      ),
    .bm_csync_done     (bm_csync_done     ),
    .pe_csync_done     (pe_csync_done     ),
    // Outputs
    .o_ctrl_csync_run  (ctrl_csync_run    ),
    .o_ctrl_psync_run  (ctrl_psync_run    ),
    .o_ctrl_data_run   (ctrl_data_run     ),
    .o_ctrl_psync_phase(ctrl_psync_phase  ),
    .o_is_first_row    (is_first_row      ),
    .o_is_last_row     (is_last_row       ),
    .o_is_first_col    (is_first_col      ),
    .o_is_last_col     (is_last_col       ),
    .o_is_first_chn    (is_first_chn      ),
    .o_is_last_chn     (is_last_chn       ),
    .o_row             (row               ),
    .o_col             (col               ),
    .o_chn             (chn               ),
    .o_chn_out         (chn_out           ),
    .o_fb_load_req     (fb_load_req       ),
    .o_layer_done      (layer_done        )
);
//--------------------------------------------------------------------
buffer_manager u_buffer_manager (
    .clk                (clk              ),
    .rstn               (rstn             ),

    // Buffer Manager <-> TOP
    .q_width            (q_width          ),
    .q_height           (q_height         ),
    .q_channel          (q_channel        ),
    .q_row_stride       (q_row_stride     ),

    .q_layer            (q_layer          ),

    .q_load_ifm         (q_load_ifm       ),
    .q_load_filter      (q_load_filter    ),
    .o_load_filter_done (load_filter_done ),

    // Buffer Manager <-> AXI (IFM/FILTER) : TB가 구동
    .read_data          (read_data        ),
    .read_data_vld      (read_data_vld    ),
    // .first              (axi_first        ),

    // Buffer Manager <-> Controller 
    .c_ctrl_data_run    (ctrl_data_run    ),
    .c_ctrl_csync_run   (ctrl_csync_run   ),
    .c_row              (row              ),
    .c_col              (col              ),
    .c_chn              (chn              ),

    .c_is_first_row     (is_first_row     ),
    .c_is_last_row      (is_last_row      ),
    .c_is_first_col     (is_first_col     ),
    .c_is_last_col      (is_last_col      ),
    .c_is_first_chn     (is_first_chn     ),
    .c_is_last_chn      (is_last_chn      ),

    .o_bm_csync_done    (bm_csync_done    ),

    // Buffer Manager <-> pe_engine (IFM)
    .ib_data0_out       (ifm_data_0       ),
    .ib_data1_out       (ifm_data_1       ),
    .ib_data2_out       (ifm_data_2       ),

    // Buffer Manager <-> pe_engine (FILTER)
    .fb_req_possible    (fb_req_possible  ),
    .fb_req             (fb_req           ), // from PE
    .fb_addr            (fb_addr          ), // from PE

    .fb_data0_out       (filter_data_0    ),
    .fb_data1_out       (filter_data_1    ),
    .fb_data2_out       (filter_data_2    ),
    .fb_data3_out       (filter_data_3    )
);
//---------------------------------------------------------------------- 
pe_engine u_pe_engine (
    .clk(clk), 
    .rstn(rstn),
    .c_ctrl_data_run(ctrl_data_run),
    .c_ctrl_csync_run(ctrl_csync_run),
    .c_row(row),
    .c_col(col),
    .c_chn(chn),
    .c_chn_out(chn_out),
    .c_is_first_row(is_first_row),
    .c_is_last_row (is_last_row),
    .c_is_first_col(is_first_col),
    .c_is_last_col (is_last_col),
    .c_is_first_chn(is_first_chn),
    .c_is_last_chn (is_last_chn),

    .q_channel(q_channel),

    .o_pe_csync_done(pe_csync_done),
    
    .ib_data0_in(ifm_data_0), 
    .ib_data1_in(ifm_data_1), 
    .ib_data2_in(ifm_data_2),
    
    .fb_req_possible(fb_req_possible),
    .o_fb_req(fb_req),
    .o_fb_addr(fb_addr),

    .fb_data0_in(filter_data_0),
    .fb_data1_in(filter_data_1),
    .fb_data2_in(filter_data_2),
    .fb_data3_in(filter_data_3),

    // pe_engine -> postprocessor
    .o_pe_data(pe_data),
    .o_pe_vld(pe_vld), 
    .o_pe_row(pe_row),
    .o_pe_col(pe_col),
    .o_pe_chn(pe_chn),
    .o_pe_chn_out(pe_chn_out),
    .o_pe_is_last_chn(pe_is_last_chn) 
);
//----------------------------------------------------------------------  
postprocessor u_postprocessor (
    .clk(clk),
    .rstn(rstn),

    // postprocessor <-> top
    .q_layer(q_layer),
    
    .q_width(q_width),
    .q_height(q_height),
    .q_channel(q_channel),    
    .q_channel_out(q_channel_out),

    // postprocessor <-> pe_engine
    .pe_data_i(pe_data),
    .pe_vld_i(pe_vld), 
    .pe_row_i(pe_row),
    .pe_col_i(pe_col),
    .pe_chn_i(pe_chn),
    .pe_chn_out_i(pe_chn_out),
    .pe_is_last_chn(pe_is_last_chn), 

    // postprocessor <-> buffer_manager
    .o_pp_data_vld(),
    .o_pp_data(),
    .o_pp_addr()
);


endmodule
