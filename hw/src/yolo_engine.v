`include "./controller_params.vh"
//----------------------------------------------------------------+
// Project: Deep Learning Hardware Design Contest
// Module: yolo_engine
// Description:
//		Load parameters and input feature map from DRAM via AXI4
//      존나많이고쳐야할듯
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
    
    parameter W_SIZE=`W_SIZE,
    parameter W_CHANNEL=`W_CHANNEL,
    parameter W_FRAME_SIZE=`W_FRAME_SIZE,
    parameter W_DELAY=`W_DELAY
)
(
    input                          clk, 
    input                          rstn

    , input [31:0] i_ctrl_reg0    // network_start, // {debug_big(1), debug_buf_select(16), debug_buf_addr(9)}
    , input [31:0] i_ctrl_reg1    // Read address base ->ifm
    , input [31:0] i_ctrl_reg2    // Write address base ->ofm
	, input [31:0] i_ctrl_reg3    // Write address base ->weight base address

    , output                         M_ARVALID
    , input                          M_ARREADY
    , output  [AXI_WIDTH_AD-1:0]     M_ARADDR
    , output  [AXI_WIDTH_ID-1:0]     M_ARID
    , output  [7:0]                  M_ARLEN
    , output  [2:0]                  M_ARSIZE
    , output  [1:0]                  M_ARBURST
    , output  [1:0]                  M_ARLOCK
    , output  [3:0]                  M_ARCACHE
    , output  [2:0]                  M_ARPROT
    , output  [3:0]                  M_ARQOS
    , output  [3:0]                  M_ARREGION
    , output  [3:0]                  M_ARUSER
    , input                          M_RVALID
    , output                         M_RREADY
    , input  [AXI_WIDTH_DA-1:0]      M_RDATA
    , input                          M_RLAST
    , input  [AXI_WIDTH_ID-1:0]      M_RID
    , input  [3:0]                   M_RUSER
    , input  [1:0]                   M_RRESP
       
    , output                         M_AWVALID
    , input                          M_AWREADY
    , output  [AXI_WIDTH_AD-1:0]     M_AWADDR
    , output  [AXI_WIDTH_ID-1:0]     M_AWID
    , output  [7:0]                  M_AWLEN
    , output  [2:0]                  M_AWSIZE
    , output  [1:0]                  M_AWBURST
    , output  [1:0]                  M_AWLOCK
    , output  [3:0]                  M_AWCACHE
    , output  [2:0]                  M_AWPROT
    , output  [3:0]                  M_AWQOS
    , output  [3:0]                  M_AWREGION
    , output  [3:0]                  M_AWUSER
    
    , output                         M_WVALID
    , input                          M_WREADY
    , output  [AXI_WIDTH_DA-1:0]     M_WDATA
    , output  [AXI_WIDTH_DS-1:0]     M_WSTRB
    , output                         M_WLAST
    , output  [AXI_WIDTH_ID-1:0]     M_WID
    , output  [3:0]                  M_WUSER
    
    , input                          M_BVALID
    , output                         M_BREADY
    , input  [1:0]                   M_BRESP
    , input  [AXI_WIDTH_ID-1:0]      M_BID
    , input                          M_BUSER
    
    , output network_done
    , output network_done_led   
);
`include "define.v"

parameter BUFF_DEPTH    = 256;
parameter BUFF_ADDR_W   = $clog2(BUFF_DEPTH);
localparam BIT_TRANS = BUFF_ADDR_W;

//CSR
reg ap_start;
reg ap_ready;
reg ap_done;
reg interrupt;

//pe engine
reg pe_start;

reg [31:0] dram_base_addr_rd;
reg [31:0] dram_base_addr_wr;
reg [31:0] reserved_register;

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
//?��번에 16word ?���?
//wire[            15:0] max_req_blk_idx  = (256*256)/16; // The number of blocks
//�? ?��겨야 ?�� block ?��
//----------------------------------------------------------------
// Control signals
//----------------------------------------------------------------
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
    end
    else begin 
        if(!ap_start && i_ctrl_reg0[0]) begin 
            //?���? ?��?�� ?��주는거�??
            dram_base_addr_rd <= i_ctrl_reg1; // Base Address for READ  (Input image, Model parameters)
            dram_base_addr_wr <= i_ctrl_reg2; // Base Address for WRITE (Intermediate feature maps, Outputs)
            reserved_register <= i_ctrl_reg3; // reserved (weight)
        end 
        else if (ap_done) begin 
            dram_base_addr_rd <= 0;
            dram_base_addr_wr <= 0;
            reserved_register <= 0; 
        end 
    end 
end
//----------------------------------------------------------------
// DUTs
//----------------------------------------------------------------
// DMA Controller

reg [3:0] idx_layer;//idx of conv layer
reg[9:0] idx_group;
reg phase_ifm;//1: ifm phase, 0: weight phase
reg start_d1;

// DMA�? ?��?��?�� 값들�? ?��겨줄 ?���??��?��
reg [31:0] rd_base_addr_reg;
reg [15:0] rd_blocks_reg;

// --- ?��?��: 16-word 블록 개수(ceil) ---
function [15:0] blk16;
  input [31:0] words;
  begin blk16 = (words + 16 - 1)/16; end
endfunction

// --- conv ?��?�� ?�� weight ?��?�� word-offset(?��?��) ---
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

// --- conv ?��?�� ?�� 4 filters(=OC 4�?) ?�� weight word ?�� ---
//   (3x3 conv: 3*3*Cin*4, 1x1 conv: 1*1*Cin*4) : 미리 ?��?��코딩
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
// --- conv ?��?�� ?�� (?��?��?��/4)?�� 그룹 개수(마�?�? 반쪽?�� ?��?��?��?�� ceil) ---
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

wire burst_first=read_data_vld&&(blk_read==0)&&(read_data_cnt==0);

//?��?�� pulse
wire q_load_ifm, q_load_filter;
assign q_load_ifm=phase_ifm&read_data_vld;
assign q_load_filter=(~phase_ifm)&read_data_vld;

localparam integer IFM_BYTES=256*256*3;
localparam integer BYTES_PER_BURST=16*(AXI_WIDTH_DA/8); 
localparam integer IFM_BLOCKS =IFM_BYTES/BYTES_PER_BURST;


reg rd_go, wr_go;
reg [1:0] s;
localparam S_IDLE=0, S_WAIT_IFM=1, S_WAIT_WG=2, S_WAIT_PE=3;
//state machine ?��?�� -> dram<->bram interface
always @(posedge clk or negedge rstn) begin
    if(!rstn) begin
        phase_ifm<=1'b1;//start from ifm
        idx_layer<=0;
        start_d1<=0;
        idx_group<=0;
        rd_base_addr_reg<=32'd0;
        rd_blocks_reg<=0;
        rd_go<=0;
        s<=S_IDLE;
    end
    else begin
        rd_go<=1'd0;
        pe_start<=0;
        case(s)
            S_IDLE: begin
                if(i_ctrl_reg0[0]) begin
                    phase_ifm<=1;
                    idx_layer<=4'd0;
                    idx_group<=0;
                    rd_base_addr_reg<=i_ctrl_reg1;
                    rd_blocks_reg<=IFM_BLOCKS[15:0];
                    rd_go=1'b1;
                    s<=S_WAIT_IFM;
                end
            end
            
            S_WAIT_IFM: begin
                if(ctrl_read_done) begin
                    phase_ifm<=1'b0;
                    idx_layer <=4'd0;
                    idx_group<=0;
                    rd_base_addr_reg<=i_ctrl_reg3 + 4*(w_off_words(4'd0)+w_grp_words(4'd0)*0);
                    rd_blocks_reg<=blk16(w_grp_words(4'd0));
                    rd_go<=1'b1;
                    s<=S_WAIT_WG;
                    
                end            
            end
            
            S_WAIT_WG: begin
                if(ctrl_read_done&&o_load_filter_done) begin
                    pe_start<=1'b1;
                    s<=S_WAIT_PE;
                end
            end
            
            S_WAIT_PE: begin
                if(pe_done) begin
                    if(idx_group+1<w_grp_total(idx_layer)) begin
                    //?�� ?��?��?�� ?��?�� 그룹 
                    idx_group<=idx_group+1;
                    rd_base_addr_reg<=i_ctrl_reg3+4*(w_off_words(idx_layer)+w_grp_words(idx_layer)*(idx_group+1'b1));
                    rd_blocks_reg<=blk16(w_grp_words(idx_layer));

                end else if(idx_layer+1<N_LAYER) begin
                    //?��?�� ?��?��?�� �? 그룹
                    idx_layer<=idx_layer+1;
                    idx_group<=0;
                    rd_base_addr_reg<=i_ctrl_reg3+4*(w_off_words(idx_layer+1'b1));
                    rd_blocks_reg    <= blk16( w_grp_words(idx_layer + 1'b1) );
                end else begin
                    //모든 ?��?��?�� ?���? ?��, ?��?�� ?��?��
                end
                end
                
            end
               
        endcase
        
    /*
        start_d1<=i_ctrl_reg0[0];

        if(start_d1) begin
            //first layer begin
            phase_ifm<=1;
            idx_layer<=4'd0;
            idx_group<=0;
            rd_base_addr_reg<=i_ctrl_reg1;
            rd_blocks_reg<=IFM_BLOCKS[15:0];

        end
        else if(ctrl_read_done) begin
            if(phase_ifm) begin
            //ifm ended->weight phase
            //start form layer0, group0
                phase_ifm<=1'b0;
                idx_layer <=4'd0;
                idx_group<=0;
                rd_base_addr_reg<=i_ctrl_reg3 + 4*(w_off_words(4'd0)+w_grp_words(4'd0)*0);
                rd_blocks_reg<=blk16(w_grp_words(4'd0));
            end
            else begin//wait until the pe engine is done
                //?���? weight group?�� ???�� 진행
                if(idx_group+1<w_grp_total(idx_layer)) begin
                    //?�� ?��?��?�� ?��?�� 그룹 
                    idx_group<=idx_group+1;
                    rd_base_addr_reg<=i_ctrl_reg3+4*(w_off_words(idx_layer)+w_grp_words(idx_layer)*(idx_group+1'b1));
                    rd_blocks_reg<=blk16(w_grp_words(idx_layer));

                end else if(idx_layer+1<N_LAYER) begin
                    //?��?�� ?��?��?�� �? 그룹
                    idx_layer<=idx_layer+1;
                    idx_group<=0;
                    rd_base_addr_reg<=i_ctrl_reg3+4*(w_off_words(idx_layer+1'b1));
                    rd_blocks_reg    <= blk16( w_grp_words(idx_layer + 1'b1) );
                end else begin
                    //모든 ?��?��?�� ?���? ?��, ?��?�� ?��?��
                end
            end
        end
    */
    end
    
end

wire [15:0] blk_read;

//----------------------------------------------------------------
//read, write ???���? ?��?��
axi_dma_ctrl #(.BIT_TRANS(BIT_TRANS))
u_dma_ctrl(
    .clk              (clk              )
   ,.rstn             (rstn             )
   ,.i_rd_start          (rd_go   )//start reading
   ,.i_wr_start(wr_go)
   ,.i_base_address_rd(rd_base_addr_reg/*dram_base_addr_rd*/)//dram read address
   ,.i_base_address_wr(dram_base_addr_wr)//dram write address
   ,.i_num_trans      (num_trans        )//transaction needed
   ,.i_max_req_blk_idx(rd_blocks_reg/*max_req_blk_idx*/  )
   // DMA Read
   ,.i_read_done      (read_done        )
   ,.o_ctrl_read      (ctrl_read        )//when to read
   ,.o_read_addr      (read_addr        )//where 
   
   ,.o_blk_read(blk_read)
   // DMA Write
   ,.i_indata_req_wr  (indata_req_wr    )
   ,.i_write_done     (write_done       )
   ,.o_ctrl_write     (ctrl_write       )//when to write
   ,.o_write_addr     (write_addr       )
   ,.o_write_data_cnt (write_data_cnt   )
   ,.o_ctrl_write_done(ctrl_write_done  )
   ,.o_ctrl_read_done(ctrl_read_done)
);


// DMA read module->dram access ?��?��

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


wire o_load_filter_done;
wire q_height, q_channel;
buf_manager#(

)
u_buf_manager(
    .clk(clk),
    .rstn(rstn),
    .q_width(),
    .q_height(q_height),
    .q_channel(q_channel),
    .q_row_stride(),
    .q_layer(idx_layer),


    .q_outchn(),
 
    //data from the AXI
    .read_data(read_data),
    .read_data_vld(read_data_vld),//vld?
    .first(burst_first),
    .q_load_ifm(q_load_ifm),//input ifm enable

    .q_load_filter(q_load_filter),//?��?�� ?��?�� ?��?��
    .o_load_filter_done(o_load_filter_done)//
    
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
// DEBUGGING: Save the results in images
//--------------------------------------------------------------------
// synthesis_off

`ifdef CHECK_DMA_WRITE
	bmp_image_writer #(.OUTFILE(CONV_OUTPUT_IMG00),.WIDTH(IFM_WIDTH),.HEIGHT(IFM_HEIGHT))
	u_bmp_image_writer_00(
		./*input 			*/clk	(clk            ),
		./*input 			*/rstn	(rstn           ),
		./*input [WI-1:0]   */din	(i_WDATA[7:0]   ),
		./*input 			*/vld	(i_WVALID       ),
		./*output reg 		*/frame_done(           )
	);
	bmp_image_writer #(.OUTFILE(CONV_OUTPUT_IMG01),..WIDTH(IFM_WIDTH),.HEIGHT(IFM_HEIGHT))
	u_bmp_image_writer_01(
		./*input 			*/clk	(clk            ),
		./*input 			*/rstn	(rstn           ),
		./*input [WI-1:0]   */din	(i_WDATA[15:8]  ),
		./*input 			*/vld	(i_WVALID       ),
		./*output reg 		*/frame_done(           )
	);
	bmp_image_writer #(.OUTFILE(CONV_OUTPUT_IMG02),.WIDTH(IFM_WIDTH),.HEIGHT(IFM_HEIGHT))
	u_bmp_image_writer_02(
		./*input 			*/clk	(clk            ),
		./*input 			*/rstn	(rstn           ),
		./*input [WI-1:0]   */din	(i_WDATA[23:16] ),
		./*input 			*/vld	(i_WVALID       ),
		./*output reg 		*/frame_done(           )
	);
	bmp_image_writer #(.OUTFILE(CONV_OUTPUT_IMG03),.WIDTH(IFM_WIDTH),.HEIGHT(IFM_HEIGHT))
	u_bmp_image_writer_03(
		./*input 			*/clk	(clk            ),
		./*input 			*/rstn	(rstn           ),
		./*input [WI-1:0]   */din	(i_WDATA[31:24] ),
		./*input 			*/vld	(i_WVALID       ),
		./*output reg 		*/frame_done(           )
	);

`else   // Check DMA_READ 
	bmp_image_writer #(.OUTFILE(CONV_INPUT_IMG00),.WIDTH(IFM_WIDTH),.HEIGHT(IFM_HEIGHT))
	u_bmp_image_writer_00(
		./*input 			*/clk	(clk             ),
		./*input 			*/rstn	(rstn            ),
		./*input [WI-1:0]   */din	(read_data[7:0]  ),
		./*input 			*/vld	(read_data_vld   ),
		./*output reg 		*/frame_done(            )
	);
	bmp_image_writer #(.OUTFILE(CONV_INPUT_IMG01),.WIDTH(IFM_WIDTH),.HEIGHT(IFM_HEIGHT))
	u_bmp_image_writer_01(
		./*input 			*/clk	(clk             ),
		./*input 			*/rstn	(rstn            ),
		./*input [WI-1:0]   */din	(read_data[15:8] ),
		./*input 			*/vld	(read_data_vld   ),
		./*output reg 		*/frame_done(            )
	);
	bmp_image_writer #(.OUTFILE(CONV_INPUT_IMG02),.WIDTH(IFM_WIDTH),.HEIGHT(IFM_HEIGHT))
	u_bmp_image_writer_02(
		./*input 			*/clk	(clk             ),
		./*input 			*/rstn	(rstn            ),
		./*input [WI-1:0]   */din	(read_data[23:16]),
		./*input 			*/vld	(read_data_vld   ),
		./*output reg 		*/frame_done(            )
	);
	bmp_image_writer #(.OUTFILE(CONV_INPUT_IMG03),.WIDTH(IFM_WIDTH),.HEIGHT(IFM_HEIGHT))
	u_bmp_image_writer_03(
		./*input 			*/clk	(clk             ),
		./*input 			*/rstn	(rstn            ),
		./*input [WI-1:0]   */din	(read_data[31:24]),
		./*input 			*/vld	(read_data_vld   ),
		./*output reg 		*/frame_done(            )
	);
`endif   
// synthesis_on

 //----------------------------------------------------------------------  
    // 4) cnn_ctrl
    //---------------------------------------------------------------------- 
    wire                     ifm_buf_done;
    wire                     filter_buf_done;

    // pe
    wire                     pe_done;
    
    //
    reg  [W_SIZE-1:0]        q_width;
    reg  [W_SIZE-1:0]        q_height;
    reg  [W_CHANNEL-1:0]     q_channel;    // 채널 ?�� ?��?��
    reg  [W_FRAME_SIZE-1:0]  q_frame_size;
    reg                      q_start;

    wire                     ctrl_vsync_run;
    wire [W_DELAY-1:0]       ctrl_vsync_cnt;
    wire                     ctrl_hsync_run;
    wire [W_DELAY-1:0]       ctrl_hsync_cnt;
    wire                     ctrl_data_run;
    wire [W_SIZE-1:0]        row;
    wire [W_SIZE-1:0]        col;
    wire [W_CHANNEL-1:0]     chn;        // 채널 ?��?��?�� 출력
    wire [W_FRAME_SIZE-1:0]  data_count;
    wire                     end_frame;

    wire                     ifm_buf_req_load;
    wire [W_SIZE-1:0]        ifm_buf_req_row;
    
    wire                     is_first_row;
    wire                     is_last_row;
    wire                     is_first_col;
    wire                     is_last_col; 
    wire                     is_first_chn;
    wire                     is_last_chn; 

    cnn_ctrl u_cnn_ctrl (
        .clk               (clk               ),
        .rstn              (rstn              ),
        // Inputs
        .q_ifm_buf_done    (ifm_buf_done      ),
        .q_filter_buf_done (filter_buf_done   ),
        .q_width           (q_width           ),
        .q_height          (q_height          ),
        .q_channel         (q_channel         ),
        .q_frame_size      (q_frame_size      ),
        .q_start           (pe_start           ),
        // Outputs
        .o_ctrl_vsync_run  (ctrl_vsync_run    ),
        .o_ctrl_vsync_cnt  (ctrl_vsync_cnt    ),
        .o_ctrl_hsync_run  (ctrl_hsync_run    ),
        .o_ctrl_hsync_cnt  (ctrl_hsync_cnt    ),
        .o_ctrl_data_run   (ctrl_data_run     ),
        .o_is_first_row    (is_first_row      ),
        .o_is_last_row     (is_last_row       ),
        .o_is_first_col    (is_first_col      ),
        .o_is_last_col     (is_last_col       ),
        .o_is_first_chn    (is_first_chn      ),
        .o_is_last_chn     (is_last_chn       ),
        .o_row             (row               ),
        .o_col             (col               ),
        .o_chn             (chn               ),
        .o_data_count      (data_count        ),
        .o_end_frame       (end_frame         ),

        .o_ifm_buf_req_load(ifm_buf_req_load  ),
        .o_ifm_buf_req_row (ifm_buf_req_row   ),
        .q_pe_done         (pe_done           )
    );



endmodule
