`timescale 1ns / 1ps
`include "controller_params.vh"


module conv_pe #(


    parameter K             = `K,               // kernel size

    parameter W_DATA        = `W_DATA,               // feature map bitwidth
    parameter W_KERNEL      = `W_KERNEL,               // kernel bitwidth
    parameter W_OUT         = `W_PSUM,              // partial sum bitwidth

    parameter Tin           = `Tin,
    parameter Tout          = `Tout,
    parameter W_Tin         = `W_Tin,

    parameter W_SIZE        = `W_SIZE,
    parameter W_CHANNEL     = `W_CHANNEL,
    parameter W_FRAME_SIZE  = `W_FRAME_SIZE,
    parameter W_DELAY       = `W_DELAY,

    parameter MAC_W_IN      = `MAC_W_IN,        // 128
    parameter MAC_W_OUT     = `MAC_W_OUT,       // 20
    parameter MAC_DELAY     = `MAC_DELAY,

    parameter ADDER_TREE_DELAY = `ADDER_TREE_DELAY,     // 2

    parameter IFM_DW        = `IFM_DW,                  // 32
    parameter FILTER_DW     = `FILTER_DW,               // 72

    parameter PE_DELAY              = `PE_DELAY,
    parameter PE_IFM_FLAT_BW        = `PE_IFM_FLAT_BW,
    parameter PE_FILTER_FLAT_BW     = `PE_FILTER_FLAT_BW,
    parameter PE_ACCO_FLAT_BW       = `PE_ACCO_FLAT_BW
)(
    input  wire                     clk,
    input  wire                     rstn,
    
    input  wire                     c_ctrl_data_run,
    input  wire                     c_top_cal_start,

    input  wire                     c_is_first_row,
    input  wire                     c_is_last_row,
    input  wire                     c_is_first_col,
    input  wire                     c_is_last_col,

    // IFM BUFFER
    input  wire [PE_IFM_FLAT_BW-1:0]    bm_ifm_data_flat,

    // FILTER BUFFER 
    input  wire                         change_filter,
    input  wire                         load_filter,
    input  wire [W_Tin-1:0]             load_idx,
    input  wire [PE_FILTER_FLAT_BW-1:0] bm_filter_data_flat,


    output wire [PE_ACCO_FLAT_BW-1:0]   o_acc,
    output wire                         o_vld 
);


wire [IFM_DW-1:0] bm_ifm_data [0:K-1];
wire [FILTER_DW-1:0] bm_filter_data [0:Tout-1];



// sliding window
reg [IFM_DW-1:0]        in_img [0:K*K-1];
reg [FILTER_DW-1:0]     filter [0:Tin*Tout-1];

reg [FILTER_DW-1:0]     filter_p [0:Tin*Tout-1];

integer i, j;


// ------------------------------------------------------------------------------------------
// flatten
// ------------------------------------------------------------------------------------------
genvar gi;
generate
  for (gi = 0; gi < K; gi = gi + 1) begin
    assign bm_ifm_data[gi] = bm_ifm_data_flat[(gi+1)*IFM_DW-1 -: IFM_DW];
  end
endgenerate

generate
for (gi = 0; gi < Tout; gi = gi + 1) begin
    assign bm_filter_data[gi] = bm_filter_data_flat[(gi+1)*FILTER_DW-1 -: FILTER_DW];
end
endgenerate
// ------------------------------------------------------------------------------------------





// ------------------------------------------------------------------------------------------
// IFM shift, FILTER
// ------------------------------------------------------------------------------------------
always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin
        // in_img reset
        for (i = 0; i < K; i = i + 1) begin
            for (j = 0; j < K; j = j + 1) begin
                in_img[i*K+j] <= {IFM_DW{1'b0}};
            end
        end
    end
    
    if (c_ctrl_data_run || c_top_cal_start) begin
        for (i = 0; i < K; i = i + 1) begin 
            for (j = 0; j < K - 1; j = j + 1) begin 
                in_img[i*K+j] <= in_img[i*K+j+1];
            end
        end
    end

    if (c_ctrl_data_run) begin 
        for (i = 0; i < K; i = i + 1) begin 
            in_img[i*K+K-1] <= bm_ifm_data[i];
        end
    end
end


// FILTER
always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin
        // filter reset
        for (i = 0; i < Tin * Tout; i = i + 1) begin
            filter[i] <= {FILTER_DW{1'b0}};
            filter_p[i] <= {FILTER_DW{1'b0}};
        end
    end
    else begin 
        // filter change
        if (change_filter) begin 
            for (i = 0; i < Tin * Tout; i = i + 1) begin 
                filter[i] <= filter_p[i];
            end
        end

        // load filter
        if (load_filter) begin 
            for (i = 0; i < Tout; i = i + 1) begin 
                filter_p[Tin*i+load_idx] <= bm_filter_data[i];
            end
        end
    end
end
// ------------------------------------------------------------------------------------------




// 16 macs
reg  [MAC_W_IN-1:0]     din  [0:Tin-1]; 
reg  [MAC_W_IN-1:0]     win  [0:Tin*Tout-1];
wire [MAC_W_OUT-1:0]    mac_acc_o[0:Tout*Tin-1];
wire                    mac_vld_o[0:Tout*Tin-1];

wire [PE_ACCO_FLAT_BW-1:0]     acc_o;
wire                vld_o[0:Tout-1];

// input data parsing
always@(posedge clk or negedge rstn) begin

    for (i = 0; i < Tin; i = i + 1) begin 
        din[i] = 128'd0;
    end
    for (i = 0; i < Tin*Tout; i = i + 1) begin 
        win[i] = 128'd0;
    end

    if(c_top_cal_start) begin
		// Tiled IFM data
        for (i = 0; i < Tin; i = i + 1) begin 
            din[i][ 7: 0] = (c_is_first_row || c_is_first_col) ? 8'd0 : in_img[0 * K + 0][i*8+:8];
            din[i][15: 8] = (c_is_first_row                  ) ? 8'd0 : in_img[0 * K + 1][i*8+:8];
            din[i][23:16] = (c_is_first_row || c_is_last_col ) ? 8'd0 : in_img[0 * K + 2][i*8+:8];
            
            din[i][31:24] = (                  c_is_first_col) ? 8'd0 : in_img[1 * K + 0][i*8+:8];
            din[i][39:32] =                                             in_img[1 * K + 1][i*8+:8];
            din[i][47:40] = (                  c_is_last_col ) ? 8'd0 : in_img[1 * K + 2][i*8+:8];
            
            din[i][55:48] = (c_is_last_row  || c_is_first_col) ? 8'd0 : in_img[2 * K + 0][i*8+:8];
            din[i][63:56] = (c_is_last_row                   ) ? 8'd0 : in_img[2 * K + 1][i*8+:8];
            din[i][71:64] = (c_is_last_row  || c_is_last_col ) ? 8'd0 : in_img[2 * K + 2][i*8+:8];
        end
        
		// Tiled Filters
        for (i = 0; i < Tin * Tout; i = i + 1) begin
            win[i][71:0] = filter[i];
        end
    end    
end 


//-------------------------------------------
// DUT: MAC, ADDER TREE
//-------------------------------------------
//use 16 macs to do the convolution -> 15 dsps each * 16 = 240!

generate
    genvar w, d;
    for (w = 0; w < Tout; w = w + 1) begin : ROW_GEN
        for (d = 0; d < Tin; d = d + 1) begin : COL_GEN
            mac u_mac_inst(
            ./*input 		 */clk	(clk	        ), 
            ./*input 		 */rstn	(rstn	        ), 
            ./*input 		 */vld_i(c_top_cal_start), 
            ./*input [127:0] */win	(win[Tin*w+d]   ), 
            ./*input [127:0] */din	(din[d]	        ),
            ./*output[ 19:0] */acc_o(mac_acc_o[Tin*w+d]), 
            ./*output        */vld_o(mac_vld_o[Tin*w+d])
            );
        end
    end
endgenerate



generate 
    genvar a;
    for (a = 0; a < Tout; a = a + 1) begin : ADDERTREE_GEN
        adder_tree_4 u_adder_tree_4(
            ./*input 		*/clk(clk             ), 
            ./*input 		*/rstn(rstn           ),
            ./*input 		*/vld_i(mac_vld_o[Tin*a] ),
            ./*input [19:0] */in0(mac_acc_o[Tin*a+0]), 
            ./*input [19:0] */in1(mac_acc_o[Tin*a+1]), 
            ./*input [19:0] */in2(mac_acc_o[Tin*a+2]), 
            ./*input [19:0] */in3(mac_acc_o[Tin*a+3]),
            ./*output[31:0] */acc_o(acc_o[a*W_OUT+:W_OUT]),
            ./*output       */vld_o(vld_o[a]       ) 
        );
    end
endgenerate


assign o_acc = acc_o;
assign o_vld = vld_o[0];


endmodule
