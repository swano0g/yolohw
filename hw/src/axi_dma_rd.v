//----------------------------------------------------------------+
//----------------------------------------------------------------+
// Project: Deep Learning Hardware Design Contest
// Module: axi_dma_rd
// Description:
//		Load parameters and input feature map from DRAM via AXI4
//
// 2021.09.01 by NXT (truongnx@capp.snu.ac.kr)
//----------------------------------------------------------------+
//dram 에서 데이터 읽어옴
module axi_dma_rd(
    //AXI Master Interface
    //Read address channel
    M_ARVALID,    // address/control valid handshake
    M_ARREADY,    // Read addr ready
    M_ARADDR,     // Address Read 
    M_ARID,       // Read addr ID
    M_ARLEN,      // Transfer length
    M_ARSIZE,     // Transfer width
    M_ARBURST,    // Burst type
    M_ARLOCK,     // Atomic access information
    M_ARCACHE,    // Cachable/bufferable infor
    M_ARPROT,     // Protection info
    M_ARQOS,      // Quality of Service
    M_ARREGION,   // Region signaling
    M_ARUSER,     // User defined signal
 
    //Read data channel
    M_RVALID,     // Read data valid 
    M_RREADY,     // Read data ready (to Slave)
    M_RDATA,      // Read data bus
    M_RLAST,      // Last beat of a burst transfer
    M_RID,        // Read ID
    M_RUSER,      // User defined signal
    M_RRESP,      // Read response
     
    //Functional Ports
    start_dma,//전송 시작 트리거 
    num_trans, //Number of 32-bit words transferred(burst)
    start_addr,//데이터 읽을 위치 시작점-> burst 만틈 읽기
    data_o,//읽은 데이터 
    data_vld_o,//유효할 때 high
    data_cnt_o,//데이터 개수
    done_o,//완료 시 high

    //Global signals
    clk, rstn
);
	// Parameters
	parameter BITS_TRANS = 18;
	parameter OUT_BITS_TRANS = 13;

	parameter AXI_WIDTH_USER = 1;               // Master ID
	parameter AXI_WIDTH_ID   = 4;               // ID width in bits
	parameter AXI_WIDTH_AD   = 32;              // address width
	parameter AXI_WIDTH_DA   = 32;              // data width
	parameter AXI_WIDTH_DS   = (AXI_WIDTH_DA/8);// data strobe width
	
    localparam  FIXED_BURST_SIZE = 256; //Change if you want, 256 is possible, but it can be dangerous
    //일단 256 기준으로 해서 요청 -> 여러 번 데이터 나누어 읽음
    localparam  LOG_BURST_SIZE = $clog2(FIXED_BURST_SIZE);

//------------------------------------------------------------------------------
// Port declarations
//------------------------------------------------------------------------------
    //AXI Master Interface
    //Read address channel
    output                      M_ARVALID;  // address/control valid handshake
    input                       M_ARREADY;
    output  [AXI_WIDTH_AD-1:0]  M_ARADDR;   // Address Read 
    output  [AXI_WIDTH_ID-1:0]  M_ARID;     // Read addr ID
    output  [7:0]               M_ARLEN;    // Transfer length
    output  [2:0]               M_ARSIZE;   // Transfer width
    output  [1:0]               M_ARBURST;  // Burst type
    output  [1:0]               M_ARLOCK;   // Atomic access information
    output  [3:0]               M_ARCACHE;  // Cachable/bufferable infor
    output  [2:0]               M_ARPROT;   // Protection info
    output  [3:0]               M_ARQOS;    // Quality of Service
    output  [3:0]               M_ARREGION; // Region signaling
    output  [3:0]               M_ARUSER;   // User defined signal
   
    //Read data channel
    input                       M_RVALID;   // Read data valid -> data 받아옴
    output                      M_RREADY;   // Read data ready (to Slave)
    input   [AXI_WIDTH_DA-1:0]  M_RDATA;    // Read data bus
    input                       M_RLAST;    // Last beat of a burst transfer
    input   [AXI_WIDTH_ID-1:0]  M_RID;      // Read ID
    input  [3:0]                M_RUSER;    // User defiend signal
    input   [1:0]               M_RRESP;    // Read response

    //Functional Ports
    input                           start_dma;
    input [BITS_TRANS-1:0]          num_trans;     //Number of 32-bit words transferred
    input [AXI_WIDTH_AD-1:0]        start_addr;
    output reg [AXI_WIDTH_DA-1:0]   data_o;
    output reg                      data_vld_o;
    output reg [BITS_TRANS-1:0]     data_cnt_o;
    output reg                      done_o;

    //Global signals
    input               clk;
    input               rstn;

//------------------------------------------------------------------------------
// Internal Signals 
//------------------------------------------------------------------------------
    assign M_ARID = 3'd0;           // Read addr ID
    assign M_ARLOCK = 2'd0;         // Atomic access information
    assign M_ARCACHE = 4'd0;        // Cachable/bufferable infor
    assign M_ARPROT = 3'd0;         // Protection info
    assign M_ARQOS = 4'b1111;       // Highest priority
    assign M_ARREGION = 4'd0;       // Region signaling
    assign M_ARUSER = 4'd0;         // User defiend signal
        
    reg     [AXI_WIDTH_AD-1:0]  ext_araddr ;
	reg     [AXI_WIDTH_AD-1:0]  ext_arlen  ;
	reg     [2:0]               ext_arsize ;
	reg     [1:0]               ext_arburst;
	reg                         ext_arvalid;
	wire                        ext_arready;
	wire    [AXI_WIDTH_DA-1:0]  ext_rdata  ;
	wire    [1:0]               ext_rresp  ;
	wire                        ext_rlast  ;
	wire                        ext_rvalid ;
	wire                        ext_rready ;

    assign  M_ARVALID = ext_arvalid;
    assign  M_ARADDR  = ext_araddr;
    assign  M_ARLEN   = ext_arlen;
    assign  M_ARSIZE  = ext_arsize;
    assign  M_ARBURST = ext_arburst;
    assign  ext_arready = M_ARREADY;

    assign  ext_rdata   = M_RDATA;
    assign  ext_rresp   = M_RRESP;
    assign  ext_rlast   = M_RLAST;
    assign  ext_rvalid  = M_RVALID;
    assign  M_RREADY  = ext_rready;

    reg ext_rlast_r;  
    reg [1:0] ext_rresp_r;
    reg last_trans;   
    reg [7:0] q_burst_size_rd;
    reg [8:0] q_burst_size_rd_1;
    reg [AXI_WIDTH_AD-1:0] q_ext_addr_rd;
    reg [2:0] st_rdaxi, next_st_rdaxi;  
    reg [BITS_TRANS-1:0] num_trans_d;
    reg [BITS_TRANS-1:0] data_cnt;
    reg [BITS_TRANS-1:0] d_burst_cnt_rd, q_burst_cnt_rd;
    reg start_dma_d;
   
    always @(posedge clk or negedge rstn)
        if(!rstn)   ext_rlast_r <= 'h0;
        else        ext_rlast_r <= ext_rlast & ext_rvalid & ext_rready;
   
    always @(posedge clk or negedge rstn)
        if(!rstn)   ext_rresp_r <= 'h0;
        else        ext_rresp_r <= ext_rresp;

//------------------------------------------------------------------------------
// Main body of code
//------------------------------------------------------------------------------
   //FSM for Read from AXI

    localparam RD_IDLE = 0, RD_PRE = 1, RD_START = 2, RD_SEQ = 3, RD_WAIT = 4;

    always @(posedge clk or negedge rstn)
        if(!rstn)         st_rdaxi <= RD_IDLE;
        else              st_rdaxi <= next_st_rdaxi;//flow setting


    assign ext_rready = 1'b1;
    always @(posedge clk or negedge rstn)
        if(!rstn) start_dma_d <= 'b0;
        else start_dma_d <= start_dma;

    always @(posedge clk or negedge rstn)
        if(!rstn) num_trans_d <= 'h0;
        else if(start_dma) num_trans_d <= num_trans; //start_dma access only 1time?


    always @(posedge clk or negedge rstn)
        if(!rstn)   q_burst_cnt_rd <= 0;//현재까지 읽은 데이터 총 개수-> burst 마다 업데이트됨
        else        q_burst_cnt_rd <= d_burst_cnt_rd;

    always @(posedge clk or negedge rstn) begin//burst 개수 설정!
        if(!rstn) begin
            q_burst_size_rd <= 0;
            q_burst_size_rd_1 <= 0;
            last_trans <= 1'b0;
        end
        // else if(q_burst_cnt_rd + FIXED_BURST_SIZE >= num_trans_d) begin
        //     q_burst_size_rd <= num_trans_d - q_burst_cnt_rd - 1;
        //     q_burst_size_rd_1 <= num_trans_d - q_burst_cnt_rd;//The # of remaining transaction
        //     if(st_rdaxi == RD_SEQ) last_trans <= 1'b1;
        //     else last_trans <= 1'b0;
         
        // end
        else if(q_burst_cnt_rd + FIXED_BURST_SIZE > num_trans_d) begin
            //burst개수가 총량 초과?
            q_burst_size_rd <= num_trans_d[LOG_BURST_SIZE - 1 :0] - 1;
            q_burst_size_rd_1 <= num_trans_d[LOG_BURST_SIZE - 1 :0];    //The # of remaining transaction
            if(st_rdaxi == RD_SEQ) last_trans <= 1'b1;
            else last_trans <= 1'b0;
        end
        else if(q_burst_cnt_rd + FIXED_BURST_SIZE == num_trans_d) begin
            //정확히 256개 남음
            q_burst_size_rd <= FIXED_BURST_SIZE-1;
            q_burst_size_rd_1 <= FIXED_BURST_SIZE;    //The # of remaining transaction
            if(st_rdaxi == RD_SEQ) last_trans <= 1'b1;
            else last_trans <= 1'b0;
        end
        else begin
            //일반적 상황-> full burst
            q_burst_size_rd <= FIXED_BURST_SIZE-1;
            q_burst_size_rd_1 <= FIXED_BURST_SIZE;
        end
    end


    always @(posedge clk or negedge rstn) begin //dram 주소 계산
        if(!rstn)
            q_ext_addr_rd <= 0;
        else if(start_dma)
            q_ext_addr_rd <= start_addr;
        else if((st_rdaxi == RD_WAIT) && (next_st_rdaxi == RD_PRE))//burst 1개 끝 -> 다음 주소 계산
            q_ext_addr_rd <= q_ext_addr_rd + {FIXED_BURST_SIZE,{2'b00}};//4B 
    end


    always @(*) begin
        next_st_rdaxi = st_rdaxi;
        d_burst_cnt_rd = q_burst_cnt_rd;

        //AXI read addr channel
        ext_araddr = 0;
        ext_arlen = 0;
        ext_arsize = 0;
        ext_arburst = 0;
        ext_arvalid = 1'b0;

        case(st_rdaxi)
            default: next_st_rdaxi = RD_IDLE;
            RD_IDLE: begin
                if(start_dma_d)
                next_st_rdaxi = RD_PRE;
            end
            RD_PRE: begin //burst 설정 준비
                if(q_burst_cnt_rd == num_trans_d) begin //end of blk read
                d_burst_cnt_rd = 0;
                next_st_rdaxi = RD_IDLE;
                end
                else next_st_rdaxi = RD_START;
            end
            RD_START: begin   //start burst read-> read요청 보내기 
                if(ext_arready) begin//read address 전송 성공
                ext_arvalid = 1'b1;
                ext_araddr = q_ext_addr_rd;
                ext_arlen = q_burst_size_rd;
                ext_arsize = 3'b010;
                //ext_arsize = SIZE_8B;
                ext_arburst = 2'b01;// BURST_INCR

                next_st_rdaxi = RD_SEQ;
                end
            end
            RD_SEQ: begin  //data수신 대기 
                //if(ext_rlast && ext_rvalid && ext_rready) begin //last beat of a burst
                //   if(ext_rresp == RESP_OKAY)
                if(ext_rlast_r) begin //last beat of a burst
                    if(ext_rresp_r == 2'b00)
                        next_st_rdaxi = RD_WAIT;
                    else     //error, restart the burst transfer
                        next_st_rdaxi = RD_START;
                end
            end
            RD_WAIT: begin //wait data written to ofifo
                d_burst_cnt_rd = q_burst_cnt_rd + q_burst_size_rd_1;
                next_st_rdaxi = RD_PRE;
            end
        endcase

    end


    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            data_cnt_o <= 'h0;
            data_o <= 'h0;
            data_vld_o <= 'h0;
        end
        else begin
            data_cnt_o <= data_cnt;
            data_o <= ext_rdata;
            data_vld_o <= ext_rvalid;
        end
    end
  
    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            done_o <= 'h0;
        end
        else begin
            done_o <= last_trans && ext_rlast && (ext_rresp == 2'b00);
        end

    end// Timing check needed



    always @(posedge clk or negedge rstn) begin
        if(!rstn)               data_cnt <= 'h0;
        else begin
            if(st_rdaxi == RD_START) data_cnt <= q_burst_cnt_rd;
            else if(ext_rvalid) data_cnt <= data_cnt + 'h1;
            end
        end
endmodule