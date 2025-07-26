`timescale 1ns/1ps
`include "controller_params"


module pe_engine #(
    parameter W_SIZE        = `W_SIZE,
    parameter W_CHANNEL     = `W_CHANNEL,
    parameter W_FRAME_SIZE  = `W_FRAME_SIZE,
    parameter W_DELAY       = `W_DELAY,

    
    parameter K             = `K,
    parameter Tin           = `Tin,
    parameter Tout          = `Tout,
    parameter IFM_DW        = `IFM_DW,
    parameter FILTER_DW     = `FILTER_DW,
    parameter W_PSUM        = `W_PSUM,
    parameter BM_DELAY      = `BM_DATA_DELAY,
    parameter PE_DELAY      = `PE_DELAY,
    parameter ADDR_WIDTH    = 12
)(

    input  wire                     clk,
    input  wire                     rstn,
  
    // controller -> PE engine
    input  wire                         c_ctrl_data_run,
    input  wire [W_SIZE-1:0]            c_row,
    input  wire [W_SIZE-1:0]            c_col,
    input  wire [W_CHANNEL-1:0]         c_chn,
    input  wire [W_FRAME_SIZE-1:0]      c_data_count,
    input  wire                         c_end_frame,

    input wire                          c_is_first_row,
    input wire                          c_is_last_row,
    input wire                          c_is_first_col,
    input wire                          c_is_last_col,


    // bm interface
    output reg                      o_req_ifm,
    output reg                      o_req_filter,
    output reg                      o_req_psum,

    input  wire [IFM_DW-1:0]        bm_ifm_data [0:K-1],
    input  wire [FILTER_DW-1:0]     bm_filter_data [0:Tin-1],
    input  wire [W_PSUM-1:0]        bm_psum_data,

    // PE result -> psum
    output reg                      psum_we,
    output reg [ADDR_WIDTH-1:0]     psum_addr,
    output reg [W_PSUM-1:0]         psum_wdata
);


// 1. 좌표 파이프라인
reg [ADDR_WIDTH-1:0] row_d   [0:PE_LATENCY-1];
reg [ADDR_WIDTH-1:0] col_d   [0:PE_LATENCY-1];
reg [W_CHANNEL-1:0]  chn_d   [0:PE_LATENCY-1];
integer i;
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        for (i=0; i<PE_LATENCY; i=i+1) begin
        row_d[i] <= 0; col_d[i] <= 0; chn_d[i] <= 0;
        end
    end else begin
        row_d[0] <= row_i;    col_d[0] <= col_i;    chn_d[0] <= chn_i;
        for (i=1; i<PE_LATENCY; i=i+1) begin
        row_d[i] <= row_d[i-1];
        col_d[i] <= col_d[i-1];
        chn_d[i] <= chn_d[i-1];
        end
    end
end

// 2. BM 요청 타이밍 생성
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        req_ifm    <= 0;
        req_filter <= 0;
        req_psum   <= 0;
    end else begin
        // run_i가 들어온 그 사이클에 요청
        req_ifm    <= run_i;
        req_filter <= run_i;
        req_psum   <= run_i;
    end
end

// 3. conv_pe 인스턴스
wire [W_PSUM-1:0] o_acc [0:Tout-1];
wire              o_vld [0:Tout-1];


conv_pe #(
    .K(K), .Tin(Tin), .Tout(Tout),
    .IFM_DW(IFM_DW), .FILTER_DW(FILTER_DW),
    .W_PSUM(W_PSUM)
    // … 나머지 파라미터
    ) U_PE (
    .clk            (clk),
    .rstn           (rstn),
    .c_ctrl_data_run(run_i),
    // bm 데이터
    .bm_ifm_data    (bm_ifm_data),
    .reuse_filter   (1'b0),
    .bm_filter_data (bm_filter_data),
    .bm_psum_data   ({Tout{bm_psum_data}}), // 필요에 맞게 포맷
    // 결과
    .o_acc          (o_acc),
    .o_vld          (o_vld)
);

// 4. PSUM 쓰기
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        psum_we    <= 0;
        psum_addr  <= 0;
        psum_wdata <= 0;
    end else begin
        if (o_vld[0]) begin
        psum_we   <= 1;
        // 예: row, col, chn 조합으로 어드레스 계산
        psum_addr <= { row_d[PE_LATENCY-1], col_d[PE_LATENCY-1] /*, chn_d…*/ };
        psum_wdata<= o_acc[chn_d[PE_LATENCY-1]];
        end else begin
        psum_we <= 0;
        end
    end
end

endmodule
