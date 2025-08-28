`timescale 1ns / 1ps
`include "controller_params.vh"


module route_buffer #(
    parameter IFM_DW        = `IFM_DW,          // 32
    parameter OFM_DW        = `OFM_DW,          // 32

    // feature map
    parameter FM_AW       = `FM_BUFFER_AW,
    parameter FM_DW       = `FM_BUFFER_DW,
    parameter IFM_AW      = `FM_BUFFER_AW,
    parameter OFM_AW      = `FM_BUFFER_AW,

    parameter RTE_DEPTH   = `ROUTE_BUFFER_DEPTH,
    parameter RTE_AW      = `ROUTE_BUFFER_AW
)(
    input  wire                         clk,
    input  wire                         rstn,

    // top
    input  wire [W_FRAME_SIZE-1:0]      q_frame_size, // route load data cnt

    input  wire                         q_route_save,
    input  wire                         q_route_load,
    input  wire [1:0]                   q_route_loc,
    input  wire [IFM_AW-1:0]            q_route_offset,

    // postprocessor
    input  wire                         pp_data_vld,
    input  wire [OFM_DW-1:0]            pp_data,
    input  wire [OFM_AW-1:0]            pp_addr,

    // buffer manager
    output wire                         rte_ifm_vld,
    output wire                         rte_ifm_write_vld,
    output wire [IFM_AW-1:0]            rte_ifm_write_addr,
    output wire [IFM_DW-1:0]            rte_ifm_write_data,

    // load data from route buf (rte buf -> ifm buf(aux port))
    input  wire                         rte_buf_load_vld,
    output wire [IFM_AW-1:0]            rte_buf_load_addr,
    output wire [FM_DW-1:0]             rte_buf_load_data,
    output wire                         rte_buf_load_done
);


localparam  RTE_IFM  = 2'b00,
            RTE_BUF  = 2'b01,
            RTE_DRAM = 2'b10;   // not support


wire rte_ifm_save = q_route_save && (q_route_loc == RTE_IFM);
wire rte_buf_save = q_route_save && (q_route_loc == RTE_BUF);

// wire rte_ifm_load = q_route_save && (q_route_loc == RTE_IFM);
wire rte_buf_load = q_route_load && (q_route_loc == RTE_BUF);

assign rte_ifm_vld          = rte_ifm_save;
assign rte_ifm_write_vld    = rte_ifm_save ? pp_data_vld              : 0;
assign rte_ifm_write_addr   = rte_ifm_save ? q_route_offset + pp_addr : 0;
assign rte_ifm_write_data   = rte_ifm_save ? pp_data                  : 0;



wire [RTE_AW-1:0]   rte_buf_write_addr = rte_buf_save ? pp_addr     : {RTE_AW{1'b0}}; 
wire                rte_buf_wea        = rte_buf_save ? pp_data_vld : 1'b0;
wire [FM_DW-1:0]    rte_buf_write_data = rte_buf_save ? pp_data     : {FM_DW{1'b0}};


// rte buf load logic
// rte buf -> ifm buf (aux port)

reg  [RTE_AW-1:0]   read_data_cnt;
reg                 read_data_vld;
reg                 read_data_done;

always @(posedge clk or negedge rstn) begin 
    if (!rstn) begin 
        read_data_cnt     <= 0;
        read_data_vld     <= 0;
        read_data_done <= 0;
    end else begin 
        read_data_vld <= rte_buf_load_vld && rte_buf_load;

        if (rte_buf_load_vld && read_data_done == 0) begin 
            if (read_data_cnt == q_frame_size - 1) begin 
                read_data_done <= 1;
            end else begin 
                read_data_cnt <= read_data_cnt + 1;
            end
        end

        if (q_route_load == 0) begin 
            read_data_done <= 0;
            read_data_cnt  <= 0;
        end
    end
end

wire                rte_buf_read_en    = rte_buf_load ? rte_buf_load_vld : 1'b0;
wire [RTE_AW-1:0]   rte_buf_read_addr  = rte_buf_load ? read_data_cnt    : {RTE_AW{1'b0}};
wire [FM_DW-1:0]    rte_buf_read_data;

assign              rte_buf_load_data = read_data_vld ? rte_buf_read_data : 0;
assign              rte_buf_load_done = read_data_done;
assign              rte_buf_load_addr = read_data_cnt + q_route_offset;


// dpram_512x32 (L12)

dpram_wrapper #(
    .DEPTH  (RTE_DEPTH         ),
    .AW     (RTE_AW            ),
    .DW     (FM_DW             ))
u_rte_buf0(    
    .clk	(clk		       ),
    // write port
    .ena	(1'b1              ),
    .addra  (rte_buf_write_addr),
    .wea    (rte_buf_wea       ),
    .dia    (rte_buf_write_data),
    // read port
    .enb    (rte_buf_read_en   ),
    .addrb	(rte_buf_read_addr ),
    .dob	(rte_buf_read_data )
);

endmodule