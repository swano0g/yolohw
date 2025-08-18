`timescale 1ns / 1ps
`include "controller_params.vh"

module adder_tree_4 #(
    parameter W_IN  = 20,  // input bit-width
    parameter W_OUT = `W_PSUM  // output bit-width
)(
    input                          clk,
    input                          rstn,
    input                          vld_i,
    input      signed [W_IN-1:0]   in0,
    input      signed [W_IN-1:0]   in1,
    input      signed [W_IN-1:0]   in2,
    input      signed [W_IN-1:0]   in3,
    output     signed [W_OUT-1:0]  acc_o,
    output                         vld_o
);

// pipeline registers for partial sums
reg signed [W_IN:0]    sum1_0, sum1_1;   // width = W_IN+1
reg signed [W_IN+1:0]  sum2;             // width = W_IN+2

// valid signal pipeline
reg vld_d1, vld_d2;

// Level 1: add pairs in0+in1, in2+in3
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        sum1_0 <= 'd0;
        sum1_1 <= 'd0;
        vld_d1  <= 1'b0;
    end else begin
        sum1_0 <= $signed(in0) + $signed(in1);  // first pair sum
        sum1_1 <= $signed(in2) + $signed(in3);  // second pair sum
        vld_d1 <= vld_i;      // latch valid
    end
end

// Level 2: add the two partial sums, register output
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        sum2  <= 'd0;
        vld_d2 <= 1'b0;
    end else begin
        sum2  <= $signed(sum1_0) + $signed(sum1_1);
        vld_d2 <= vld_d1;          // propagate valid
    end
end

assign vld_o = vld_d2;
assign acc_o = $signed(sum2);

endmodule
