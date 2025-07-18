`timescale 1ns / 1ps

module mul( //inputs for dsp
input clk, 
input [7:0] w, 
input [7:0] x, 
output[15:0] y
);
`include "define.v"

//dsp block instance
	wire [17:0] dsp_A, dsp_B;
	wire [47:0] dsp_P;

	assign dsp_A = w[7]? {10'b11_1111_1111, w} : {10'b00_0000_0000, w};	//sign extension considering msb
	assign dsp_B = x[7]? {10'b11_1111_1111, x} : {10'b00_0000_0000, x};
	assign y = dsp_P[15:0];

	//input into dsp block instance
	dsp_macro_0 u_dsp(.CLK(clk), .A(dsp_A), .B(dsp_B), .C(48'b0), .P(dsp_P));
endmodule
