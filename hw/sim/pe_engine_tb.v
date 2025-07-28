`timescale 1ns/1ps
`include "controller_params.vh"

module pe_engine_tb;
    //----------------------------------------------------------------------  
    // 1) 파라미터: controller_params.vh에서 import
    //----------------------------------------------------------------------  
    parameter K                = `K;
    parameter Tin              = `Tin;
    parameter Tout             = `Tout;
    parameter IFM_DW           = `IFM_DW;
    parameter FILTER_DW        = `FILTER_DW;
    parameter W_PSUM           = `W_PSUM;
    parameter PE_IFM_FLAT_BW    = `PE_IFM_FLAT_BW;
    parameter PE_FILTER_FLAT_BW = `PE_FILTER_FLAT_BW;
    parameter PE_ACCO_FLAT_BW   = `PE_ACCO_FLAT_BW;
    parameter BUF_AW           = `BUFFER_ADDRESS_BW;

    parameter WIDTH         = 16;
    parameter HEIGHT        = 3;
    parameter CHANNEL       = 1;
    parameter FRAME_SIZE    = WIDTH * HEIGHT * CHANNEL;

    localparam CLK_PERIOD   = 10; // 100 MHz

    localparam  BUF_DELAY   = 1;  // buf -> pe

    //----------------------------------------------------------------------  
    // 2) 신호 선언
    //----------------------------------------------------------------------  
    reg  [IFM_DW-1:0]    ifmbuf0 [0:15], ifmbuf1 [0:15], ifmbuf2 [0:15];
    reg  [FILTER_DW-1:0] filterbuf0 [0:3], filterbuf1 [0:3], filterbuf2 [0:3], filterbuf3 [0:3];

    reg  [IFM_DW-1:0] ifm_data_0;
    reg  [IFM_DW-1:0] ifm_data_1;
    reg  [IFM_DW-1:0] ifm_data_2;


    wire                 fb_req;
    wire [BUF_AW-1:09]   fb_addr;

    reg  [FILTER_DW-1:0] filter_data_0;
    reg  [FILTER_DW-1:0] filter_data_1;
    reg  [FILTER_DW-1:0] filter_data_2;
    reg  [FILTER_DW-1:0] filter_data_3;


    wire pb_req;
    wire [BUF_AW-1:0] pb_addr;
    wire [W_PSUM-1:0] psum_data;

    //----------------------------------------------------------------------  
    // 3) clock & reset
    //----------------------------------------------------------------------  
    reg                  clk, rstn;
    initial begin
        clk = 0; forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //----------------------------------------------------------------------  
    // 4) cnn_ctrl 인스턴스: row/col/chn 패이프라인 등
    //---------------------------------------------------------------------- 
    wire                     ifm_buf_done;
    wire                     filter_buf_done;

    // pe
    reg                      q_pe_done;
    
    //
    reg  [W_SIZE-1:0]        q_width;
    reg  [W_SIZE-1:0]        q_height;
    reg  [W_CHANNEL-1:0]     q_channel;    // 채널 수 입력
    reg  [W_FRAME_SIZE-1:0]  q_frame_size;
    reg                      q_start;

    wire                     ctrl_vsync_run;
    wire [W_DELAY-1:0]       ctrl_vsync_cnt;
    wire                     ctrl_hsync_run;
    wire [W_DELAY-1:0]       ctrl_hsync_cnt;
    wire                     ctrl_data_run;
    wire [W_SIZE-1:0]        row;
    wire [W_SIZE-1:0]        col;
    wire [W_CHANNEL-1:0]     chn;        // 채널 인덱스 출력
    wire [W_FRAME_SIZE-1:0]  data_count;
    wire                     end_frame;

    wire                     ifm_buf_req_load;
    wire [W_SIZE-1:0]        ifm_buf_req_row;
    
    wire                     is_first_row;
    wire                     is_last_row;
    wire                     is_first_col;
    wire                     is_last_col; 

    cnn_ctrl u_cnn_ctrl (
        .clk               (clk               ),
        .rstn              (rstn              ),
        // Inputs
        .q_ifm_buf_done    (q_ifm_buf_done    ),
        .q_filter_buf_done (q_filter_buf_done ),
        .q_width           (q_width           ),
        .q_height          (q_height          ),
        .q_channel         (q_channel         ),  // 추가
        .q_frame_size      (q_frame_size      ),
        .q_start           (q_start           ),
        // Outputs
        .o_ctrl_vsync_run  (ctrl_vsync_run    ),
        .o_ctrl_vsync_cnt  (ctrl_vsync_cnt    ),
        .o_ctrl_hsync_run  (ctrl_hsync_run    ),
        .o_ctrl_hsync_cnt  (ctrl_hsync_cnt    ),
        .o_ctrl_data_run   (ctrl_data_run     ),
        .o_is_first_row    (is_first_row      ),
        .o_is_last_row     (is_last_row       ),
        .o_is_first_col    (is_first_col      ),
        .o_is_last_col     (is_last_col       ),
        .o_row             (row               ),
        .o_col             (col               ),
        .o_chn             (chn               ),
        .o_data_count      (data_count        ),
        .o_end_frame       (end_frame         ),

        .o_ifm_buf_req_load(ifm_buf_req_load  ),
        .o_ifm_buf_req_row (ifm_buf_req_row   ),
        .q_pe_done         (q_pe_done         )
    );

  //----------------------------------------------------------------------  
  // 5) pe_engine 인스턴스
  //---------------------------------------------------------------------- 

  pe_engine u_pe_engine (
        .clk(clk), 
        .rstn(rstn),
        .c_ctrl_data_run(ctrl_data_run),
        .c_ctrl_hsync_run(ctrl_hsync_run),
        .c_row(row),
        .c_col(col),
        .c_chn(chn),
        .c_data_count(data_count),
        .c_end_frame(end_frame),
        .c_is_first_row(is_first_row),
        .c_is_last_row (is_last_row),
        .c_is_first_col(is_first_col),
        .c_is_last_col (is_last_col),
        
        .ib_data0_in(ifm_data_0), 
        .ib_data1_in(ifm_data_1), 
        .ib_data2_in(ifm_data_2),
        
        .o_fb_req(fb_req),
        .o_fb_addr(fb_addr),

        .fb_data0_in(filter_data_0),
        .fb_data1_in(filter_data_1),
        .fb_data2_in(filter_data_2),
        .fb_data3_in(filter_data_3),

        .o_pb_req(pb_req),
        .o_pb_addr(pb_addr),

        .pb_data_in(psum_data),
    );

    //----------------------------------------------------------------------  
    // 6) IFM buffer mimic
    //----------------------------------------------------------------------  
    // load one ifm buffer: 16 cycle
    reg         ifm0_loaded;
    reg         ifm1_loaded;
    reg         ifm2_loaded;

    reg [7:0]   ifm_loading_cnt;
    reg         ifm_loading;
    reg [1:0]   ifm_loading_buf_num;

    reg         ifm0_loaded_d;
    reg         ifm1_loaded_d;
    reg         ifm2_loaded_d;

    assign ifm_buf_done = (ifm0_loaded && !ifm0_loaded_d) || (ifm1_loaded && !ifm1_loaded_d) || (ifm2_loaded && !ifm2_loaded_d); 
    
    initial begin 
        ifm0_loaded = 0;
        ifm1_loaded = 0;
        ifm2_loaded = 0;
        ifm0_loaded_d = 0;
        ifm1_loaded_d = 0;
        ifm2_loaded_d = 0;

        ifm_loading_cnt = 0;
        ifm_loading = 0;
        ifm_loading_buf_num = 0;

        ifm_data_0       = {IFM_DW{1'b0}};
        ifm_data_1       = {IFM_DW{1'b0}};
        ifm_data_2       = {IFM_DW{1'b0}};
    end
    
    always @(posedge clk or negedge rstn) begin 
        if (ifm_buf_req_load && !ifm_loading) begin 
            ifm_loading <= 1;
            ifm_loading_buf_num <= ifm_buf_req_row;
        end

        if (ifm_loading) begin 
            ifm_loading_cnt <= ifm_loading_cnt + 1;
        end

        if (ifm_loading_cnt == 8'd15) begin
            if (ifm_loading_buf_num == 0) begin 
                ifm0_loaded <= 1;
            end
            else if (ifm_loading_buf_num == 0) begin 
                ifm1_loaded <= 1;
            end
            else if (ifm_loading_buf_num == 0) begin 
                ifm2_loaded <= 1;
            end

            ifm_loading <= 0;
            ifm_loading_cnt <= 0;
        end

        ifm0_loaded_d <= ifm0_loaded;
        ifm1_loaded_d <= ifm1_loaded;
        ifm2_loaded_d <= ifm2_loaded;


        if (ctrl_data_run) begin 
            if (row == 0 && ifm0_loaded && ifm1_loaded) begin 
                ifm_data_0 <= 0;
                ifm_data_1 <= ifmbuf0[col];
                ifm_data_2 <= ifmbuf1[col];
            end
            else if (row == 1 && ifm0_loaded && ifm1_loaded && ifm2_loaded) begin
                ifm_data_0 <= ifmbuf0[col];
                ifm_data_1 <= ifmbuf1[col];
                ifm_data_2 <= ifmbuf2[col];
            end
            else if (row == 2 && ifm1_loaded && ifm2_loaded) begin 
                ifm_data_0 <= ifmbuf1[col];
                ifm_data_1 <= ifmbuf2[col];
                ifm_data_2 <= 0;
            end 
        end
    end
    //----------------------------------------------------------------------  
    // 7) FILTER buffer mimic
    //---------------------------------------------------------------------- 
    // filter buffer load: 32 cycle
    reg         filter_loaded;
    reg [7:0]   filter_loading_cnt;

    reg filter_loaded_d;

    assign filter_buf_done = filter_loaded && !filter_loaded_d;
    
    initial begin 
        filter_loaded = 0;
        filter_loaded_d = 0;
        filter_loading_cnt = 0;
        filter_data_0       = {FILTER_DW{1'b0}};
        filter_data_1       = {FILTER_DW{1'b0}};
        filter_data_2       = {FILTER_DW{1'b0}};
        filter_data_3       = {FILTER_DW{1'b0}};
    end

    always @(posedge clk or negedge rstn) begin 
        if (ctrl_vsync_run && !filter_loaded) begin 
            filter_loading_cnt <= filter_loading_cnt + 1;
        end

        if (filter_loading_cnt == 8'd31) begin 
            filter_loaded <= 1;
        end
        
        filter_loaded_d <= filter_loaded;
        
        if (fb_req && filter_loaded) begin 
            filter_data_0 <= filterbuf0[fb_addr];
            filter_data_1 <= filterbuf1[fb_addr];
            filter_data_2 <= filterbuf2[fb_addr];
            filter_data_3 <= filterbuf3[fb_addr];
        end
    end
    //----------------------------------------------------------------------  
    // 8) stimulus
    //----------------------------------------------------------------------  
    initial begin
        rstn           = 1'b0;
        q_width        = WIDTH;
        q_height       = HEIGHT;   
        q_channel      = CHANNEL;           // (tiled)채널 수 1. 즉 실제 input channel = 4
        q_frame_size   = FRAME_SIZE;
        q_start        = 1'b0; 
        q_filter_buf_done   = 1'b0;
        q_ifm_buf_done      = 4'b0;

        // 8.3) load_filter, load_idx 시퀀스
        # (10*CLK_PERIOD);
        for (i=0; i<4; i=i+1) begin
        load_filter = 1;
        load_idx    = i;
        # CLK_PERIOD;
        end
        load_filter = 0;
        # CLK_PERIOD;
        change_filter = 1;
        # CLK_PERIOD;
        change_filter = 0;

        // 8.4) start 전체 프레임 처리를 위해 run 신호 인에이블
        # CLK_PERIOD;
        q_start = 1;
        # (256*256*CLK_PERIOD);  // 충분히 긴 시간
        q_start = 0;

        // 8.5) 출력 모니터
        $display("acc_ch[0]=%h, acc_ch[1]=%h, acc_ch[2]=%h, acc_ch[3]=%h",
                acc_ch[0], acc_ch[1], acc_ch[2], acc_ch[3]);
        $finish;
    end



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


endmodule

