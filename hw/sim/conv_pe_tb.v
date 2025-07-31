`timescale 1ns/1ps
`include "controller_params.vh"

module conv_pe_tb;
    //--------------------------------------------------------------------------
    // Parameters
    //--------------------------------------------------------------------------
    parameter K                = `K;               // kernel size (3)
    parameter W_DATA           = `W_DATA;
    parameter W_KERNEL         = `W_KERNEL;
    parameter W_OUT            = `W_PSUM;
    parameter Tin              = `Tin;
    parameter Tout             = `Tout;
    parameter W_SIZE           = `W_SIZE;
    parameter W_CHANNEL        = `W_CHANNEL;
    parameter W_FRAME_SIZE     = `W_FRAME_SIZE;
    parameter W_DELAY          = `W_DELAY;
    parameter MAC_W_IN         = `MAC_W_IN;
    parameter MAC_W_OUT        = `MAC_W_OUT;
    parameter MAC_DELAY        = `MAC_DELAY;
    parameter ADDER_TREE_DELAY = `ADDER_TREE_DELAY;
    parameter IFM_DW           = `IFM_DW;
    parameter FILTER_DW        = `FILTER_DW;
    parameter PE_DELAY         = `PE_DELAY;
    parameter PE_IFM_FLAT_BW        = `PE_IFM_FLAT_BW;
    parameter PE_FILTER_FLAT_BW     = `PE_FILTER_FLAT_BW;
    parameter PE_ACCO_FLAT_BW       = `PE_ACCO_FLAT_BW;

    // Clock period (100 MHz)
    localparam CLK_PERIOD = 10;

    //--------------------------------------------------------------------------
    // Testbench signals
    //--------------------------------------------------------------------------
    reg                           clk;
    reg                           rstn;
    reg                           c_ctrl_data_run;
    reg                           c_top_cal_start;
    reg                           c_is_first_row, c_is_last_row;
    reg                           c_is_first_col, c_is_last_col;
    reg                           load_filter;
    reg        [1:0]              load_idx;
    reg [PE_IFM_FLAT_BW-1:0]      bm_ifm_data_flat;
    reg [PE_FILTER_FLAT_BW-1:0]   bm_filter_data_flat;
    reg                           change_filter;
    wire [PE_ACCO_FLAT_BW-1:0]    o_acc_flat;
    wire                          o_vld;

    //--------------------------------------------------------------------------
    // DUT instantiation
    //--------------------------------------------------------------------------
    conv_pe u_conv_pe (
        .clk                   (clk),
        .rstn                  (rstn),
        .t_data_run            (c_ctrl_data_run),
        .t_cal_start           (c_top_cal_start),
        .c_is_first_row        (c_is_first_row_pipe[2]),
        .c_is_last_row         (c_is_last_row_pipe[2]),
        .c_is_first_col        (c_is_first_col_pipe[2]),
        .c_is_last_col         (c_is_last_col_pipe[2]),
        .bm_ifm_data_flat      (bm_ifm_data_flat),
        .change_filter         (change_filter),
        .load_filter           (load_filter),
        .load_idx              (load_idx),
        .bm_filter_data_flat   (bm_filter_data_flat),
        .o_acc                 (o_acc_flat),
        .o_vld                 (o_vld)
    );




    wire [W_OUT-1:0]       o_acc [0:Tout-1];
    reg [IFM_DW-1:0]      bm_ifm_data [0:K-1];
    reg [FILTER_DW-1:0]   bm_filter_data [0:Tout-1];

    // pipe
    reg [2:0]  c_is_first_row_pipe;
    reg [2:0]  c_is_last_row_pipe;
    reg [2:0]  c_is_first_col_pipe;
    reg [2:0]  c_is_last_col_pipe;

    reg q_start;
    reg [9:0]           cal_count;

    // IFM buffers (16 columns × 3 rows)
    reg [IFM_DW-1:0] ifmbuf0 [0:15];
    reg [IFM_DW-1:0] ifmbuf1 [0:15];
    reg [IFM_DW-1:0] ifmbuf2 [0:15];

    // Filter buffers (4 words × 4 cycles)
    reg [FILTER_DW-1:0] filterbuf0 [0:3];
    reg [FILTER_DW-1:0] filterbuf1 [0:3];
    reg [FILTER_DW-1:0] filterbuf2 [0:3];
    reg [FILTER_DW-1:0] filterbuf3 [0:3];

    integer idx;
    always @(*) begin
        // pack K entries of IFM into flat bus: MSB=ifmbuf2 down to LSB=ifmbuf0
        bm_ifm_data_flat = { K{ {IFM_DW{1'b0}} } }; // default
        for (idx = 0; idx < K; idx = idx + 1) begin
            bm_ifm_data_flat[(idx+1)*IFM_DW-1 -: IFM_DW] = bm_ifm_data[idx];
        end
    end

    always @(*) begin
        if (load_filter) begin
            bm_filter_data_flat = { filterbuf3[load_idx], filterbuf2[load_idx],
                                    filterbuf1[load_idx], filterbuf0[load_idx] };
        end else begin
            bm_filter_data_flat = {PE_FILTER_FLAT_BW{1'b0}};
        end
    end

    assign {o_acc[0],o_acc[1],o_acc[2],o_acc[3]} = o_acc_flat; 

    always @(posedge clk or negedge rstn) begin 
        if (!rstn) begin 
            c_is_first_row_pipe = 3'b0;
            c_is_last_row_pipe = 3'b0;
            c_is_first_col_pipe = 3'b0;
            c_is_last_col_pipe = 3'b0;
        end
        else begin 
            c_is_first_row_pipe[1]  <= c_is_first_row_pipe[0];
            c_is_last_row_pipe[1]   <= c_is_last_row_pipe[0];
            c_is_first_col_pipe[1]  <= c_is_first_col_pipe[0];
            c_is_last_col_pipe[1]   <= c_is_last_col_pipe[0];
                        
            c_is_first_row_pipe[2]  <= c_is_first_row_pipe[1];
            c_is_last_row_pipe[2]   <= c_is_last_row_pipe[1];
            c_is_first_col_pipe[2]  <= c_is_first_col_pipe[1];
            c_is_last_col_pipe[2]   <= c_is_last_col_pipe[1];
        end
    end



  integer i, row, col;

  //--------------------------------------------------------------------------
  // Initialize IFM buffers
  //--------------------------------------------------------------------------
  initial begin
    // row 0
    ifmbuf0[0]  = 32'h00707064; ifmbuf0[1]  = 32'h006F6F63;
    ifmbuf0[2]  = 32'h0066685D; ifmbuf0[3]  = 32'h005E5F56;
    ifmbuf0[4]  = 32'h005D5D56; ifmbuf0[5]  = 32'h00595B54;
    ifmbuf0[6]  = 32'h0055574F; ifmbuf0[7]  = 32'h0054554F;
    ifmbuf0[8]  = 32'h0053544E; ifmbuf0[9]  = 32'h004F524B;
    ifmbuf0[10] = 32'h004C504B; ifmbuf0[11] = 32'h00494D48;
    ifmbuf0[12] = 32'h00494A46; ifmbuf0[13] = 32'h00484A45;
    ifmbuf0[14] = 32'h00474944; ifmbuf0[15] = 32'h00424643;
    // row 1
    ifmbuf1[0]  = 32'h00474644; ifmbuf1[1]  = 32'h00424340;
    ifmbuf1[2]  = 32'h0042423F; ifmbuf1[3]  = 32'h0042413F;
    ifmbuf1[4]  = 32'h003F3F3D; ifmbuf1[5]  = 32'h003E3F3D;
    ifmbuf1[6]  = 32'h003E3E3C; ifmbuf1[7]  = 32'h003E3E3C;
    ifmbuf1[8]  = 32'h003D3D3B; ifmbuf1[9]  = 32'h003C3D3B;
    ifmbuf1[10] = 32'h003B3B39; ifmbuf1[11] = 32'h003B3B39;
    ifmbuf1[12] = 32'h003B3B3B; ifmbuf1[13] = 32'h003A3A3A;
    ifmbuf1[14] = 32'h003C3C3A; ifmbuf1[15] = 32'h003A3B39;
    // row 2
    ifmbuf2[0]  = 32'h003C3C3A; ifmbuf2[1]  = 32'h003C3C3C;
    ifmbuf2[2]  = 32'h003C3C3C; ifmbuf2[3]  = 32'h003D3D3D;
    ifmbuf2[4]  = 32'h003C3C3C; ifmbuf2[5]  = 32'h003C3D3B;
    ifmbuf2[6]  = 32'h003D3D3D; ifmbuf2[7]  = 32'h003D3D3D;
    ifmbuf2[8]  = 32'h003F3F3F; ifmbuf2[9]  = 32'h003D3F3F;
    ifmbuf2[10] = 32'h003D3F3F; ifmbuf2[11] = 32'h003D3F3F;
    ifmbuf2[12] = 32'h00404040; ifmbuf2[13] = 32'h003D3E3E;
    ifmbuf2[14] = 32'h003E3F3F; ifmbuf2[15] = 32'h00404040;
  end

  //--------------------------------------------------------------------------
  // Initialize Filter buffers
  //--------------------------------------------------------------------------
  initial begin
    filterbuf0[0] = 72'h13f5fa3defd617feeb; filterbuf0[1] = 72'h11f4fb30f2e00bfcfd;
    filterbuf0[2] = 72'h10f00031efe106fffb; filterbuf0[3] = 72'h0cf1ef0505ee0602ef;

    filterbuf1[0] = 72'hedf0f5d4fef2e3e9ea; filterbuf1[1] = 72'h11131afa3e2c0b2427;
    filterbuf1[2] = 72'h03060ef8011505ea09; filterbuf1[3] = 72'h08091110060e140314;

    filterbuf2[0] = 72'h00dbe6f7d8e507d7ef; filterbuf2[1] = 72'h18110c0b1718fc09ff;
    filterbuf2[2] = 72'h14fdf8fcf800f4fcfc; filterbuf2[3] = 72'h15f3effcf1f6fdf6ed;

    filterbuf3[0] = 72'hf6fe04f7f8f708000a; filterbuf3[1] = 72'hfff3fcfcfdf7170706;
    filterbuf3[2] = 72'hf2f8f700f7f70b0804; filterbuf3[3] = 72'h19f616f9e009faebf8;
  end

  //--------------------------------------------------------------------------
  // Clock generation
  //--------------------------------------------------------------------------
  initial begin
    clk = 1'b1;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  //--------------------------------------------------------------------------
  // Row/Col counters + c_is_* flags + IFM feeding
  //--------------------------------------------------------------------------
  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        row               <= 2;
        col               <= 0;
        c_ctrl_data_run   <= 1'b0;
        c_is_first_row    <= 1'b1;
        c_is_last_row     <= 1'b0;
        c_is_first_col    <= 1'b1;
        c_is_last_col     <= 1'b0;
    end else if (q_start) begin
        c_ctrl_data_run <= 1'b1;
        // update edge flags
        c_is_first_row_pipe[0] <= (row == 0);
        c_is_last_row_pipe[0]  <= (row == K-1);
        c_is_first_col_pipe[0] <= (col == 0);
        c_is_last_col_pipe[0]  <= (col == 15);

        // sliding window: supply 3 rows of data
        if (row == 0) begin
            bm_ifm_data[0] <= {IFM_DW{1'b0}};      // pad top
            bm_ifm_data[1] <= ifmbuf0[col];
            bm_ifm_data[2] <= ifmbuf1[col];
        end else if (row == 1) begin
            bm_ifm_data[0] <= ifmbuf0[col];
            bm_ifm_data[1] <= ifmbuf1[col];
            bm_ifm_data[2] <= ifmbuf2[col];
        end else begin
            // wrap example
            bm_ifm_data[0] <= ifmbuf1[col];
            bm_ifm_data[1] <= ifmbuf2[col];
            bm_ifm_data[2] <= {IFM_DW{1'b0}};
        end

        // advance col/row
        if (col == 3) begin 
            c_top_cal_start = 1'b1;
        end
        if (col == 0 && row == 3) begin 
            c_ctrl_data_run <= 1'b0;  // 끝나면 stop
            q_start <= 1'b0;
        end
        
        if (col == 15) begin
            col <= 0;

            row <= row + 1;
        end else begin
            col <= col + 1;
        end
    end
  end

    always @(posedge clk or negedge rstn) begin
        if(c_top_cal_start) begin 
            cal_count <= cal_count + 1;
        end
        if (cal_count == 16) begin 
            c_top_cal_start = 1'b0;
        end
    end

  //--------------------------------------------------------------------------
  // Filter load sequence (4 cycles)
  //--------------------------------------------------------------------------
  initial begin
    // initial values
    rstn          = 1'b0;
    load_filter   = 1'b0;
    change_filter = 1'b0;
    load_idx      = 2'b00;
    c_ctrl_data_run = 1'b0;
    q_start = 1'b0;
    c_top_cal_start = 1'b0;
    cal_count = 0;

    // reset 해제
    # (4*CLK_PERIOD) rstn = 1'b1;
    # (CLK_PERIOD);

    // 4사이클 동안 filter_p 로드
    for (i = 0; i < 4; i = i + 1) begin
      load_filter                  = 1'b1;
      load_idx                     = i[1:0];
      # (CLK_PERIOD);
    end
    load_filter    = 1'b0;
    @(posedge clk);
    change_filter = 1'b1;
    @(posedge clk);
    change_filter = 1'b0;
    // c_ctrl_data_run = 1'b1;
    q_start = 1'b1;
  end

endmodule
