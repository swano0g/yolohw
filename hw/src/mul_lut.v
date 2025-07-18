`timescale 1ns / 1ps

module mul_lut( //inputs for dsp
input clk, 
input [7:0] w, 
input [7:0] x, 
output[15:0] y
);
`include "define.v"
	reg [15:0] dsp_P[0:4];
	always@(posedge clk) begin 
		// Multiplication with LUT
		dsp_P[0] <= $signed(w) * $signed(x); //signed
		// Sync with dedicated DSP (delay for 4 cycles)
		dsp_P[1] <= dsp_P[0];
		dsp_P[2] <= dsp_P[1];
		dsp_P[3] <= dsp_P[2];
		dsp_P[4] <= dsp_P[3];
	end 
	assign y = dsp_P[4];
endmodule

