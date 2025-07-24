`timescale 1ns / 1ps
`include "controller_params.vh"


module conv_pe #(


    parameter K             = `K,               // kernel size

    parameter W_DATA        = `W_DATA,               // feature map bitwidth
    parameter W_KERNEL      = `W_KERNEL,               // kernel bitwidth
    parameter W_PSUM        = `W_PSUM,              // partial sum bitwidth

    parameter Tin           = `Tin,
    parameter Tout          = `Tout,

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

    parameter PE_DELAY      = `PE_DELAY
)(
    input  wire                     clk,
    input  wire                     rstn,
    
    input  wire                     c_ctrl_data_run,

    input  wire                     c_is_first_row,
    input  wire                     c_is_last_row,
    input  wire                     c_is_first_col,
    input  wire                     c_is_last_col,

    // IFM BUFFER
    input  wire [IFM_DW-1:0]            bm_ifm_data [0:K-1],

    // FILTER BUFFER 
    input  wire                         reuse_filter,
    input  wire [FILTER_DW-1:0]         bm_filter_data [0:Tout-1],

    // PARTIALSUM BUFFER
    input  wire [W_PSUM-1:0]            bm_psum_data [0:Tout-1],


    output wire [W_PSUM-1:0]            o_acc [0:Tout-1],
    output wire                         o_vld [0:Tout-1]
);

// sliding window
reg [IFM_DW-1:0]        in_img [0:K*K-1];
reg [FILTER_DW-1:0]     filter [0:Tout-1];



integer i, j;


// IFM shift, FILTER
always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin
        // in_img reset
        for (i = 0; i < K; i = i + 1) begin
            for (j = 0; j < K; j = j + 1) begin
                in_img[i*K+j] <= {IFM_DW{1'b0}};
            end
        end

        // filter reset
        for (i = 0; i < Tout; i = i + 1) begin
            filter[i] <= {FILTER_DW{1'b0}};
        end
    end

    else if (c_ctrl_data_run) begin 
        for (i=0; i<K; i=i+1) begin 
            in_img[i*K+K-1] <= bm_ifm_data[i];
        end

        for (i = 0; i < K; i = i + 1) begin 
            for (j = 0; j < K - 1; j = j + 1) begin 
                in_img[i*K+j] <= in_img[i*K+j+1];
            end
        end

        if (!reuse_filter) begin 
            for (i = 0; i < Tout; i = i + 1) begin 
                filter[i] <= bm_filter_data[i];
            end
        end
    end
end



// 16 macs
reg [MAC_W_IN-1:0]  din  [0:Tin-1]; 
reg [MAC_W_IN-1:0]  win  [0:Tout-1];
wire[MAC_W_OUT-1:0] mac_acc_o[0:Tout*Tin-1];
wire                mac_vld_o[0:Tout*Tin-1];


// input data parsing
always@(*) begin

    for (i = 0; i < Tin; i = i + 1) begin 
        din[i] = 128'd0;
    end
    for (i = 0; i < Tout; i = i + 1) begin 
        win[i] = 128'd0;
    end

    if(c_ctrl_data_run) begin
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
		for(j = 0; j < Tout; j = j + 1) begin 	// Four sets <=> Four output channels
            win[j] = filter[j];	
		end 
    end    
end 


//-------------------------------------------
// DUT: MACs
//-------------------------------------------
//use 16 macs to do the convolution -> 15 dsps each * 16 = 240!

generate
    genvar w, d;
    for (w = 0; w < Tout; w = w + 1) begin : ROW_GEN
        for (d = 0; d < Tin; d = d + 1) begin : COL_GEN
            mac u_mac_inst(
            ./*input 		 */clk	(clk	        ), 
            ./*input 		 */rstn	(rstn	        ), 
            ./*input 		 */vld_i(c_ctrl_data_run), 
            ./*input [127:0] */win	(win[w]         ), 
            ./*input [127:0] */din	(din[d]	        ),
            ./*output[ 19:0] */acc_o(mac_acc_o[Tin*w+d]), 
            ./*output        */vld_o(mac_vld_o[Tin*w+d])
            );
        end
    end
endgenerate


wire[W_PSUM-1:0]    acc_o[0:Tout-1];
wire                vld_o[0:Tout-1];

// adder_tree_4
generate 
    genvar a;
    for (a = 0; a < Tout; a = a + 1) begin : ADDERTREE_GEN
        adder_tree_4 u_adder_tree_4(
            ./*input 		*/clk(clk             ), 
            ./*input 		*/rstn(rstn           ),
            ./*input 		*/vld_i(vld_i_d4      ),
            ./*input [19:0] */in_0(mac_acc_o[Tin*a+0]), 
            ./*input [19:0] */in_1(mac_acc_o[Tin*a+1]), 
            ./*input [19:0] */in_2(mac_acc_o[Tin*a+2]), 
            ./*input [19:0] */in_3(mac_acc_o[Tin*a+3]), 
            ./*input [31:0] */psum(bm_psum_data[a]),
            ./*output[31:0] */acc_o(acc_o[a]      ),
            ./*output       */vld_o(vld_o[a]      ) 
        );
    end
endgenerate


assign o_acc = acc_o;
assign o_vld = vld_o;


endmodule
