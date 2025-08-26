`timescale 1ns / 1ps
`include "controller_params.vh"

`define FPGA 1

module dpram_wrapper  #(
    parameter integer DW      = 32,       // data bit-width per word
    parameter integer AW      = 16,       // address bit-width → 2^16 = 65 536 words
    parameter integer DEPTH   = (1<<AW),  // depth = 2^AW
    parameter integer N_DELAY = 1         // read latency
)(	
	clk,		// clock 
	ena,		// enable for write address
	addra,		// input address for write
	wea,		// input write enable
	enb,		// enable for read address
	addrb,		// input address for read
	dia,		// input write data
	dob			// output read-out data
);

//------------------------------------------------------------------------+
// Declare Input & Output signals
//------------------------------------------------------------------------+
// clock and reset
input							clk;
// input SRAM signals
input [AW-1			:	0]		addra;	// input address 
input							wea;	// input write enable
input							ena;	// input enable
input [DW-1			:	0]		dia;	// input write data
input [AW-1			:	0]		addrb;	// input address 
input							enb;	// input chip-select 
// output SRAM signal
output [DW-1		:	0]		dob;	// output read-out data
//------------------------------------------------------------------------+
// Declare internal signals
//------------------------------------------------------------------------+
reg	[DW-1			:	0]		rdata;

`ifdef FPGA
	//------------------------------------------------------------------------+
	// implement generate block ram
	//------------------------------------------------------------------------+
	generate
        // total ifm buffer (256KB)
        if((DEPTH == 65536) && (DW == 32)) begin: gen_dpram_65536x32
            dpram_65536x32 u_dpram_65536x32 (
				// write ports
				.clka    (clk),
				.ena     (ena),
				.wea     (wea),
				.addra   (addra),
				.dina    (dia),
				// read ports 
				.clkb    (clk),
				.enb     (enb),
				.addrb   (addrb),
				.doutb   (dob)
			);
		end
        // ifm row buffer (6KB)
        else if((DEPTH == 1536) && (DW == 32)) begin: gen_dpram_1536x32
			dpram_1536x32 u_dpram_1536x32 (
				// write ports
				.clka    (clk),
				.ena     (ena),
				.wea     (wea),
				.addra   (addra),
				.dina    (dia),
				// read ports 
				.clkb    (clk),
				.enb     (enb),
				.addrb   (addrb),
				.doutb   (dob)
			);
	    end
		// filter buffer (4.5KB)
        else if((DEPTH == 512) && (DW == 72)) begin: gen_dpram_512x72
			dpram_512x72 u_dpram_512x72 (
				// write ports
				.clka    (clk),
				.ena     (ena),
				.wea     (wea),
				.addra   (addra),
				.dina    (dia),
				// read ports 
				.clkb    (clk),
				.enb     (enb),
				.addrb   (addrb),
				.doutb   (dob)
			);
	    end
		// affine buffer
		else if((DEPTH == 512) && (DW == 32)) begin: gen_dpram_512x32
			dpram_512x32 u_dpram_512x32 (
				// write ports
				.clka    (clk),
				.ena     (ena),
				.wea     (wea),
				.addra   (addra),
				.dina    (dia),
				// read ports 
				.clkb    (clk),
				.enb     (enb),
				.addrb   (addrb),
				.doutb   (dob)
			);
	    end
		// psum row buffer
		else if((DEPTH == 256) && (DW == 32)) begin: gen_dpram_256x32
			dpram_256x32 u_dpram_256x32 (
				// write ports
				.clka    (clk),
				.ena     (ena),
				.wea     (wea),
				.addra   (addra),
				.dina    (dia),
				// read ports 
				.clkb    (clk),
				.enb     (enb),
				.addrb   (addrb),
				.doutb   (dob)
			);
	    end
		// maxpool buffer
		else if((DEPTH == 128) && (DW == 32)) begin: gen_dpram_128x32
			dpram_128x32 u_dpram_128x32 (
				// write ports
				.clka    (clk),
				.ena     (ena),
				.wea     (wea),
				.addra   (addra),
				.dina    (dia),
				// read ports 
				.clkb    (clk),
				.enb     (enb),
				.addrb   (addrb),
				.doutb   (dob)
			);
	    end
	endgenerate
`else
	//------------------------------------------------------------------------+
	// Memory modeling
	//------------------------------------------------------------------------+
	reg [DW-1			:	0]		ram[0:DEPTH-1];	// Memory cell
	// Write
	always @(posedge clk) begin
		if(ena) begin
			if(wea)			ram[addra] <= dia;
		end
	end	
	// Read
	generate 
	   if(N_DELAY == 1) begin: delay_1
		  reg [DW-1:0] rdata   ; //Primary Data Output
		  //Read port
		  always @(posedge clk)
		  begin: read
			 if(enb)
				rdata <= ram[addrb];
		  end
		  assign dob = rdata;
	   end
	   else begin: delay_n
		  reg [N_DELAY*DW-1:0] rdata_r;
		  always @(posedge clk)
		  begin: read
			 if(enb)
				rdata_r[0+:DW] <= ram[addrb];
		  end

		  always @(posedge clk) begin: delay
			 integer i;
			 for(i = 0; i < N_DELAY-1; i = i+1)
				if(enb)
				   rdata_r[(i+1)*DW+:DW] <= rdata_r[i*DW+:DW];
		  end
		  assign dob = rdata_r[(N_DELAY-1)*DW+:DW];
	   end
	endgenerate
`endif

endmodule


