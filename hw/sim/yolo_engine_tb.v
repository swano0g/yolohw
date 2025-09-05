`timescale 1ns / 1ns

module yolo_engine_tb;


// select test case
// `define TESTCASE_0 1
// `define TESTCASE_1 1
`define TESTCASE_2 1

// `include "define.v"
// `include "sim_cfg.vh"
`include "sim_multi_cfg.vh"
`include "yolo_layer_cfg.vh"


localparam MEM_ADDRW = 22;
localparam MEM_DW = 16;
localparam A = 32;
localparam D = 32;
localparam I = 4;
localparam L = 8;
localparam M = D/8;

// localparam DRAM_IFM_OFFSET    = `DRAM_IFM_OFFSET;
// localparam DRAM_FILTER_OFFSET = `DRAM_FILTER_OFFSET;
// localparam DRAM_BIAS_OFFSET   = `DRAM_BIAS_OFFSET;
// localparam DRAM_SCALE_OFFSET  = `DRAM_SCALE_OFFSET;
// localparam DRAM_OFM_OFFSET    = `DRAM_OFM_OFFSET;

localparam DRAM_IFM_OFFSET    = `YOLO_DRAM_IFM_OFFSET;
localparam DRAM_FILTER_OFFSET = `YOLO_DRAM_FILTER_OFFSET;
localparam DRAM_BIAS_OFFSET   = `YOLO_DRAM_BIAS_OFFSET;
localparam DRAM_SCALE_OFFSET  = `YOLO_DRAM_SCALE_OFFSET;
localparam DRAM_OFM_OFFSET    = `YOLO_DRAM_OFM_OFFSET;

// Clock
parameter CLK_PERIOD = 10;   //100MHz
reg clk;
reg rstn;

initial begin
   clk = 1'b1;
   forever #(CLK_PERIOD/2) clk = ~clk;
end

//AXI Master IF0 for input/out access
wire  [I-1:0]     M_AWID;       // Address ID
wire  [A-1:0]     M_AWADDR;     // Address Write
wire  [L-1:0]     M_AWLEN;      // Transfer length
wire  [2:0]       M_AWSIZE;     // Transfer width
wire  [1:0]       M_AWBURST;    // Burst type
wire  [1:0]       M_AWLOCK;     // Atomic access information
wire  [3:0]       M_AWCACHE;    // Cachable/bufferable infor
wire  [2:0]       M_AWPROT;     // Protection info
wire              M_AWVALID;    // address/control valid handshake
wire              M_AWREADY;
wire  [I-1:0]     M_WID;        // Write ID
wire  [D-1:0]     M_WDATA;      // Write Data bus
wire  [M-1:0]     M_WSTRB;      // Write Data byte lane strobes
wire              M_WLAST;      // Last beat of a burst transfer
wire              M_WVALID;     // Write data valid
wire              M_WREADY;     // Write data ready
wire [I-1:0]      M_BID;        // buffered response ID
wire [1:0]        M_BRESP;      // Buffered write response
wire              M_BVALID;     // Response info valid
wire              M_BREADY;     // Response info ready (to slave)
wire  [I-1:0]     M_ARID;       // Read addr ID
wire  [A-1:0]     M_ARADDR;     // Address Read 
wire  [L-1:0]     M_ARLEN;      // Transfer length
wire  [2:0]       M_ARSIZE;     // Transfer width
wire  [1:0]       M_ARBURST;    // Burst type
wire  [1:0]       M_ARLOCK;     // Atomic access information
wire  [3:0]       M_ARCACHE;    // Cachable/bufferable infor
wire  [2:0]       M_ARPROT;     // Protection info
wire              M_ARVALID;    // address/control valid handshake
wire              M_ARREADY;
wire  [I-1:0]     M_RID;        // Read ID
wire  [D-1:0]     M_RDATA;      // Read data bus
wire  [1:0]       M_RRESP;      // Read response
wire              M_RLAST;      // Last beat of a burst transfer
wire              M_RVALID;     // Read data valid 
wire              M_RREADY;     // Read data ready (to Slave)

// Memory ports for input (activation)
wire [MEM_ADDRW-1:0]   mem_addr;
wire                   mem_we;
wire [MEM_DW-1:0]      mem_di;
wire [MEM_DW-1:0]      mem_do;

//--------------------------------------------------------------------
// AXI Slave External Memory: Input
//--------------------------------------------------------------------
axi_sram_if #(  //New
   .MEM_ADDRW(MEM_ADDRW), .MEM_DW(MEM_DW),
   .A(A), .I(I), .L(L), .D(D), .M(M))
u_axi_ext_mem_if_input(
   .ACLK(clk), .ARESETn(rstn),
    
   //AXI Slave IF
   .AWID	(M_AWID		),      // Address ID
   .AWADDR	(M_AWADDR	),      // Address Write
   .AWLEN	(M_AWLEN	),      // Transfer length
   .AWSIZE	(M_AWSIZE	),      // Transfer width
   .AWBURST	(M_AWBURST	),      // Burst type
   .AWLOCK	(M_AWLOCK	),      // Atomic access information
   .AWCACHE	(M_AWCACHE	),      // Cachable/bufferable infor
   .AWPROT	(M_AWPROT	),      // Protection info
   .AWVALID	(M_AWVALID	),      // address/control valid handshake
   .AWREADY	(M_AWREADY	),
   //Write data channel
   .WID		(M_WID		),      // Write ID
   .WDATA	(M_WDATA	),      // Write Data bus
   .WSTRB	(M_WSTRB	),      // Write Data byte lane strobes
   .WLAST	(M_WLAST	),      // Last beat of a burst transfer
   .WVALID	(M_WVALID	),      // Write data valid
   .WREADY	(M_WREADY	),      // Write data ready
    //Write response channel
   .BID		(M_BID		),      // buffered response ID
   .BRESP	(M_BRESP    ),      // Buffered write response
   .BVALID	(M_BVALID	),      // Response info valid
   .BREADY	(M_BREADY	),      // Response info ready (from Master)
    // Read address
   .ARID    (M_ARID		),   // Read addr ID
   .ARADDR  (M_ARADDR	),   // Address Read 
   .ARLEN   (M_ARLEN	),   // Transfer length
   .ARSIZE  (M_ARSIZE	),   // Transfer width
   .ARBURST (M_ARBURST	),   // Burst type
   .ARLOCK  (M_ARLOCK	),   // Atomic access information
   .ARCACHE (M_ARCACHE	),   // Cachable/bufferable infor
   .ARPROT  (M_ARPROT	),   // Protection info
   .ARVALID (M_ARVALID	),   // address/control valid handshake
   .ARREADY (M_ARREADY	),
    // Read data 
   .RID     (M_RID		),   // Read ID
   .RDATA   (M_RDATA	),   // Read data bus
   .RRESP   (M_RRESP	),   // Read response
   .RLAST   (M_RLAST	),   // Last beat of a burst transfer
   .RVALID  (M_RVALID	),   // Read data valid 
   .RREADY  (M_RREADY	),   // Read data ready (to Slave)

   //Interface to SRAM 
   .mem_addr(mem_addr	),
   .mem_we  (mem_we		),
   .mem_di  (mem_di		),
   .mem_do  (mem_do		)
);


// Input
// IMEM for SIM
// Inputs
//instruction memory
sram #(
   .FILE_NAME(`YOLO_MEMORY_16),
    // .FILE_NAME(`TEST_MULTI_MEMORY_16),  // debug
   .SIZE(2**MEM_ADDRW),
   .WL_ADDR(MEM_ADDRW),
   .WL_DATA(MEM_DW  ))
u_ext_mem_input (
   .clk   (clk	    ),
   .rst   (rstn		),
   .addr  (mem_addr	),
   .wdata (mem_di	),
   .rdata (mem_do	),
   .ena   (1'b0		)     // Read only
   );

//--------------------------------------------------------------------
// CNN Accelerator
//--------------------------------------------------------------------
reg [31:0] i_0;
reg [31:0] i_1;
reg [31:0] i_2;
	
yolo_engine #(
    .AXI_WIDTH_AD(A),
    .AXI_WIDTH_ID(4),
    .AXI_WIDTH_DA(D),
    .AXI_WIDTH_DS(M),
    .MEM_BASE_ADDR(2048),
    .MEM_DATA_BASE_ADDR(2048),
    .DRAM_FILTER_OFFSET(DRAM_FILTER_OFFSET),
    .DRAM_BIAS_OFFSET(DRAM_BIAS_OFFSET),
    .DRAM_SCALE_OFFSET(DRAM_SCALE_OFFSET)
)
u_yolo_engine
(
    .clk(clk),
    .rstn(rstn),
       
    .i_ctrl_reg0(i_0     ), // network_start // {debug_big(1), debug_buf_select(16), debug_buf_addr(9)}
    .i_ctrl_reg1(i_1     ), // Read_address (INPUT)
    .i_ctrl_reg2(i_2     ), // Write_address
    .i_ctrl_reg3(32'd0   ), // Reserved

    // READ ADDRESS
    .M_ARVALID	(M_ARVALID),
    .M_ARREADY	(M_ARREADY),
    .M_ARADDR	(M_ARADDR ),
    .M_ARID		(M_ARID	  ),
    .M_ARLEN	(M_ARLEN  ),
    .M_ARSIZE	(M_ARSIZE ),
    .M_ARBURST	(M_ARBURST),
    .M_ARLOCK	(M_ARLOCK ),
    .M_ARCACHE	(M_ARCACHE),
    .M_ARPROT	(M_ARPROT ),
    .M_ARQOS	(	      ),
    .M_ARREGION (		  ),
    .M_ARUSER	(		  ),
    // READ DATA
    .M_RVALID	(M_RVALID ),
    .M_RREADY	(M_RREADY ),
    .M_RDATA	(M_RDATA  ),
    .M_RLAST	(M_RLAST  ),
    .M_RID		(M_RID	  ),
    .M_RUSER	(		  ),
    .M_RRESP	(M_RRESP  ),
    

    // WRITE
    .M_AWVALID	(M_AWVALID),
    .M_AWREADY	(M_AWREADY),
    .M_AWADDR	(M_AWADDR ),    // write address
    .M_AWID		(M_AWID	  ),
    .M_AWLEN	(M_AWLEN  ),
    .M_AWSIZE	(M_AWSIZE ),
    .M_AWBURST	(M_AWBURST),
    .M_AWLOCK	(M_AWLOCK ),
    .M_AWCACHE	(M_AWCACHE),
    .M_AWPROT	(M_AWPROT ),
    .M_AWQOS	(		  ),
    .M_AWREGION (		  ),
    .M_AWUSER	(		  ),
    
    .M_WVALID	(M_WVALID ),    // write data valid
    .M_WREADY	(M_WREADY ),    
    .M_WDATA	(M_WDATA  ),    // write data
    .M_WSTRB	(M_WSTRB  ),
    .M_WLAST	(M_WLAST  ),
    .M_WID		(M_WID	  ),
    .M_WUSER	(		  ),
    
    .M_BVALID	(M_BVALID ),
    .M_BREADY	(M_BREADY ),
    .M_BRESP	(M_BRESP  ),
    .M_BID		(M_BID	  ),
    .M_BUSER	(		  ),
    
    .network_done(network_done),
    .network_done_led(network_done_led)
);

//--------------------------------------------------------------------
// Stimulus
//--------------------------------------------------------------------
initial begin
   rstn = 1'b0;         // Reset, low active   
   i_0 = 0;
   i_1 = 0;
   i_2 = 0;

   
   #(4*CLK_PERIOD) rstn = 1'b1; 
   #(100*CLK_PERIOD) 
        @(posedge clk)
            // i_0 = 32'd3; // ... _0011  debug_on
            i_0 = 32'd1;    // ..._0001 debug off
            i_1 = DRAM_IFM_OFFSET;  // read addr
            i_2 = DRAM_OFM_OFFSET;  // write addr

   #(100*CLK_PERIOD) 
         @(posedge clk)
            i_0 = 32'd0;
end




//--------------------------------------------------------------------
// Compare output
//--------------------------------------------------------------------
`include "controller_params.vh"

// `define MONOLAYER 1
`define MULTILAYER 1


reg  [`OFM_DW-1:0]           result   [0:65536-1];
reg  [`OFM_DW-1:0]           expect   [0:65536-1];

initial begin
    `ifdef MONOLAYER
        $readmemh(`TEST_EXP_MAXPOOL_STRIDE2_PATH, expect);
    `else
        // $readmemh(`TEST_MULTI_EXPECT, expect);  // debug
        $readmemh(`YOLO_EXPECT, expect);
    `endif
end


// ------- capture signals -------
integer cap_addr;

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin 
        cap_addr <= 0;
    end
    if (M_WVALID) begin
        result[cap_addr] <= M_WDATA;
        cap_addr <= cap_addr + 1;
    end
end
// -------------------------------


task automatic tb_check_multilayer_result;
    integer i;
    integer exp_words;
    integer errors, checks;
    integer max_print, printed;
    reg [`OFM_DW-1:0] got, exp;
    
    begin
        errors    = 0;
        checks    = 0;
        max_print = 50;
        printed   = 0;
        $display("============================================================");
        $display("MULTILAYER CHECK START");

        exp_words = `YOLO_EXPECT_LINE;
        // exp_words = `EXPECT_LINE; // debug


        for (i = 0; i < exp_words; i = i + 1) begin
            got = result[i]; 
            exp = expect[i];
            if (got !== exp) begin
                errors = errors + 1;
                if (printed < max_print) begin
                    $display("[%0t] MIS idx=%0d : got=%h  exp=%h",
                            $time, i, got, exp);
                    printed = printed + 1;
                end
            end
            checks = checks + 1;
        end

        // --------- summary ---------
        $display("------------------------------------------------------------");
        $display("MULTILAYER CHECK SUMMARY @%0t", $time);
        $display("  total=%0d  match=%0d  errors=%0d",
                checks, checks - errors, errors);
        if (errors == 0) begin
            $display("RESULT: PASS");
        end else begin
            $display("RESULT: FAIL");
        end
        $display("============================================================");
        // -----------------------------------------------
    end
endtask



reg checked_done;
initial checked_done = 1'b0;

always @(posedge clk) begin
    if (network_done && !checked_done) begin
        @(posedge clk);
        @(posedge clk);
        tb_check_multilayer_result();
        @(posedge clk);
        checked_done <= 1'b1;
    end
end

initial begin
    @(posedge checked_done);     
    repeat (100) @(posedge clk);
    $finish;
end


endmodule