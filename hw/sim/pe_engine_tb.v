`timescale 1ns/1ps
`include "controller_params.vh"

module pe_engine_tb;
    //----------------------------------------------------------------------  
    // 1) 파라미터: controller_params.vh에서 import
    //----------------------------------------------------------------------  
    parameter W_SIZE        = `W_SIZE;
    parameter W_CHANNEL     = `W_CHANNEL;
    parameter W_FRAME_SIZE  = `W_FRAME_SIZE;
    parameter W_DELAY       = `W_DELAY;
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


    // local parameters for test
    localparam TEST_ROW         = 3;    // fix
    localparam TEST_COL         = 16;
    localparam TEST_CHNIN       = 8;    
    localparam TEST_T_CHNIN     = 2;
    localparam TEST_CHNOUT      = 4;    // fix
    localparam TEST_FRAME_SIZE  = TEST_ROW * TEST_COL * TEST_T_CHNIN;

    localparam TEST_IB_DEPTH    = TEST_COL * TEST_T_CHNIN; // 32
    localparam TEST_FB_DEPTH    = TEST_CHNIN; // 8
    

    localparam TEST_IB_LOAD_DELAY = TEST_IB_DEPTH * 2;
    localparam TEST_FB_LOAD_DELAY = TEST_FB_DEPTH * TEST_CHNOUT * 2;
    //

    //----------------------------------------------------------------------  
    // 2) 신호 선언
    //----------------------------------------------------------------------  
    reg  [IFM_DW-1:0]    ifmbuf0 [0:TEST_IB_DEPTH-1], ifmbuf1 [0:TEST_IB_DEPTH-1], ifmbuf2 [0:TEST_IB_DEPTH-1];
    reg  [FILTER_DW-1:0] filterbuf0 [0:TEST_FB_DEPTH-1], filterbuf1 [0:TEST_FB_DEPTH-1], filterbuf2 [0:TEST_FB_DEPTH-1], filterbuf3 [0:TEST_FB_DEPTH-1];

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

    // debug
    wire [192*32-1:0] psum_flat; // 16*3*4 32bit

    wire [31:0] psum_unflat [192-1:0];

    wire [PE_ACCO_FLAT_BW-1:0] dbg_acco;

    genvar gi;
    generate
        for (gi = 0; gi < 192; gi = gi + 1) begin : UNFLAT_PSUM
            assign psum_unflat[gi] = psum_flat[gi*32 +: 32];
        end
    endgenerate


    //----------------------------------------------------------------------  
    // 3) clock & reset
    //----------------------------------------------------------------------  
    reg                  clk, rstn;
    initial begin
        clk = 0; forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //----------------------------------------------------------------------  
    // 4) cnn_ctrl 인스턴스
    //---------------------------------------------------------------------- 
    wire                     ifm_buf_done;
    wire                     filter_buf_done;

    // pe
    wire                     pe_done;
    
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
        .q_ifm_buf_done    (ifm_buf_done      ),
        .q_filter_buf_done (filter_buf_done   ),
        .q_width           (q_width           ),
        .q_height          (q_height          ),
        .q_channel         (q_channel         ),
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
        .q_pe_done         (pe_done           )
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

        .q_channel(q_channel),
        
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

        .dbg_psum_flat(psum_flat),
        .dbg_acco_flat(dbg_acco)
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

    reg [BUF_AW-1:0] ifm_base_addr;

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

        ifm_base_addr = 0;

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

        if (ifm_loading_cnt == TEST_IB_LOAD_DELAY-1) begin
            if (ifm_loading_buf_num == 0) begin 
                ifm0_loaded <= 1;
            end
            else if (ifm_loading_buf_num == 1) begin 
                ifm1_loaded <= 1;
            end
            else if (ifm_loading_buf_num == 2) begin 
                ifm2_loaded <= 1;
            end

            ifm_loading <= 0;
            ifm_loading_cnt <= 0;
        end

        ifm0_loaded_d <= ifm0_loaded;
        ifm1_loaded_d <= ifm1_loaded;
        ifm2_loaded_d <= ifm2_loaded;


        if (ctrl_data_run) begin 
            ifm_base_addr = col * TEST_T_CHNIN + chn;
            if (row == 0 && ifm0_loaded && ifm1_loaded) begin 
                ifm_data_0 <= 0;
                ifm_data_1 <= ifmbuf0[ifm_base_addr];
                ifm_data_2 <= ifmbuf1[ifm_base_addr];
            end
            else if (row == 1 && ifm0_loaded && ifm1_loaded && ifm2_loaded) begin
                ifm_data_0 <= ifmbuf0[ifm_base_addr];
                ifm_data_1 <= ifmbuf1[ifm_base_addr];
                ifm_data_2 <= ifmbuf2[ifm_base_addr];
            end
            else if (row == 2 && ifm1_loaded && ifm2_loaded) begin 
                ifm_data_0 <= ifmbuf1[ifm_base_addr];
                ifm_data_1 <= ifmbuf2[ifm_base_addr];
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

        if (filter_loading_cnt == TEST_FB_LOAD_DELAY-1) begin 
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
        q_width        = TEST_COL;
        q_height       = TEST_ROW;   
        q_channel      = TEST_T_CHNIN;           // (tiled)채널 수 1. 즉 실제 input channel = 4
        q_frame_size   = TEST_FRAME_SIZE;
        q_start        = 0; 
//        filter_buf_done   = 0;
//        ifm_buf_done      = 0;


        #(4*CLK_PERIOD) rstn = 1'b1;
        #(CLK_PERIOD);

        #(100*CLK_PERIOD)
            @(posedge clk) q_start = 1'b1;
        #(4*CLK_PERIOD)
            @(posedge clk) q_start = 1'b0;
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
        ifmbuf0[16] = 32'h003f3e3e; ifmbuf0[17] = 32'h003f4040;
        ifmbuf0[18] = 32'h00404040; ifmbuf0[19] = 32'h003f3f3f;
        ifmbuf0[20] = 32'h003f3f3f; ifmbuf0[21] = 32'h003f3f3f;
        ifmbuf0[22] = 32'h003f3f3f; ifmbuf0[23] = 32'h00403f3f;
        ifmbuf0[24] = 32'h00404040; ifmbuf0[25] = 32'h003d3f3f;
        ifmbuf0[26] = 32'h003d403f; ifmbuf0[27] = 32'h003f3f3f;
        ifmbuf0[28] = 32'h00403f3f; ifmbuf0[29] = 32'h003f3f3f;
        ifmbuf0[30] = 32'h00404040; ifmbuf0[31] = 32'h00404040;
        // row 1
        ifmbuf1[0]  = 32'h00474644; ifmbuf1[1]  = 32'h00424340;
        ifmbuf1[2]  = 32'h0042423F; ifmbuf1[3]  = 32'h0042413F;
        ifmbuf1[4]  = 32'h003F3F3D; ifmbuf1[5]  = 32'h003E3F3D;
        ifmbuf1[6]  = 32'h003E3E3C; ifmbuf1[7]  = 32'h003E3E3C;
        ifmbuf1[8]  = 32'h003D3D3B; ifmbuf1[9]  = 32'h003C3D3B;
        ifmbuf1[10] = 32'h003B3B39; ifmbuf1[11] = 32'h003B3B39;
        ifmbuf1[12] = 32'h003B3B3B; ifmbuf1[13] = 32'h003A3A3A;
        ifmbuf1[14] = 32'h003C3C3A; ifmbuf1[15] = 32'h003A3B39;
        ifmbuf1[16] = 32'h003e4040; ifmbuf1[17] = 32'h00414141;
        ifmbuf1[18] = 32'h003f4040; ifmbuf1[19] = 32'h003e3f3f;
        ifmbuf1[20] = 32'h003e4040; ifmbuf1[21] = 32'h003d403f;
        ifmbuf1[22] = 32'h003d3f3f; ifmbuf1[23] = 32'h003f3f3f;
        ifmbuf1[24] = 32'h00423f40; ifmbuf1[25] = 32'h00404040;
        ifmbuf1[26] = 32'h00424141; ifmbuf1[27] = 32'h00414141;
        ifmbuf1[28] = 32'h003f4141; ifmbuf1[29] = 32'h00404242;
        ifmbuf1[30] = 32'h00404242; ifmbuf1[31] = 32'h00414242;
        // row 2
        ifmbuf2[0]  = 32'h003C3C3A; ifmbuf2[1]  = 32'h003C3C3C;
        ifmbuf2[2]  = 32'h003C3C3C; ifmbuf2[3]  = 32'h003D3D3D;
        ifmbuf2[4]  = 32'h003C3C3C; ifmbuf2[5]  = 32'h003C3D3B;
        ifmbuf2[6]  = 32'h003D3D3D; ifmbuf2[7]  = 32'h003D3D3D;
        ifmbuf2[8]  = 32'h003F3F3F; ifmbuf2[9]  = 32'h003D3F3F;
        ifmbuf2[10] = 32'h003D3F3F; ifmbuf2[11] = 32'h003D3F3F;
        ifmbuf2[12] = 32'h00404040; ifmbuf2[13] = 32'h003D3E3E;
        ifmbuf2[14] = 32'h003E3F3F; ifmbuf2[15] = 32'h00404040;
        ifmbuf2[16] = 32'h00404242; ifmbuf2[17] = 32'h00404242;
        ifmbuf2[18] = 32'h00404242; ifmbuf2[19] = 32'h00404243;
        ifmbuf2[20] = 32'h00414242; ifmbuf2[21] = 32'h00434244;
        ifmbuf2[22] = 32'h00434144; ifmbuf2[23] = 32'h00424244;
        ifmbuf2[24] = 32'h003f4242; ifmbuf2[25] = 32'h00404241;
        ifmbuf2[26] = 32'h003e4141; ifmbuf2[27] = 32'h00404244;
        ifmbuf2[28] = 32'h003c4042; ifmbuf2[29] = 32'h003e4140;
        ifmbuf2[30] = 32'h00414141; ifmbuf2[31] = 32'h00424242;
    end

    //--------------------------------------------------------------------------
    // Initialize Filter buffers
    //--------------------------------------------------------------------------
    initial begin
        filterbuf0[0] = 72'h13f5fa3defd617feeb; filterbuf0[1] = 72'h11f4fb30f2e00bfcfd;
        filterbuf0[2] = 72'h10f00031efe106fffb; filterbuf0[3] = 72'h0cf1ef0505ee0602ef;
        filterbuf0[4] = 72'hffff04fff80004fe01; filterbuf0[5] = 72'h00fc0000fa00060005;
        filterbuf0[6] = 72'h00fe03ffff01ff0100; filterbuf0[7] = 72'h0506ff0601ff0200fd;

        filterbuf1[0] = 72'hedf0f5d4fef2e3e9ea; filterbuf1[1] = 72'h11131afa3e2c0b2427;
        filterbuf1[2] = 72'h03060ef8011505ea09; filterbuf1[3] = 72'h08091110060e140314;
        filterbuf1[4] = 72'hfffffffdfbfd0200ff; filterbuf1[5] = 72'h00fe02fcf9fffefb00;
        filterbuf1[6] = 72'hff0202faf4fc00ff04; filterbuf1[7] = 72'h00f9fe00f2fc01fb01;

        filterbuf2[0] = 72'h00dbe6f7d8e507d7ef; filterbuf2[1] = 72'h18110c0b1718fc09ff;
        filterbuf2[2] = 72'h14fdf8fcf800f4fcfc; filterbuf2[3] = 72'h15f3effcf1f6fdf6ed;
        filterbuf2[4] = 72'h00fe03fafafc02ff03; filterbuf2[5] = 72'h00000000ffff000101;
        filterbuf2[6] = 72'h040204fdf1fb06fafd; filterbuf2[7] = 72'hfff5f9fff5fcfe0003;

        filterbuf3[0] = 72'hf6fe04f7f8f708000a; filterbuf3[1] = 72'hfff3fcfcfdf7170706;
        filterbuf3[2] = 72'hf2f8f700f7f70b0804; filterbuf3[3] = 72'h19f616f9e009faebf8;
        filterbuf3[4] = 72'hfe03fcff00ff030703; filterbuf3[5] = 72'hfd0001fafa01fc0003;
        filterbuf3[6] = 72'hfdf900f6ecfe00f804; filterbuf3[7] = 72'h030104020101000000;
    end
    //--------------------------------------------------------------------------
    // Answers
    //--------------------------------------------------------------------------
    // [Channel 0]
    // 0x00003021 0xFFFFFD68 0xFFFFFA7C 0xFFFFFDFA 0x0000001A 0xFFFFFE48 0xFFFFFFAF 0x000000E3 0xFFFFFFAE 0xFFFFFF7A 0xFFFFFF67 0xFFFFFFC6 0x00000095 0x0000012A 0xFFFFFF70 0xFFFFCB17
    // 0x00002BD1 0x0000004E 0x00000122 0x00000090 0x0000018D 0x000001C6 0x00000225 0x00000297 0x000001C7 0x00000147 0x000001A1 0x000002FD 0x000001C8 0x000002FB 0x00000255 0xFFFFC6B4
    // 0x00002230 0x000001F4 0x000002AF 0x000001A7 0x0000016D 0x000002A2 0x00000284 0x0000033D 0x0000027C 0x000001A0 0x000001F0 0x00000353 0x00000168 0x000001CF 0x00000344 0xFFFFD20E

    // [Channel 1]
    // 0x000006C7 0x000026F9 0x00002645 0x0000226D 0x0000206D 0x0000204C 0x00001ECD 0x00001DBC 0x00001DB6 0x00001D0B 0x00001C9E 0x00001B68 0x00001A2C 0x00001A08 0x00001A3B 0x00002866
    // 0xFFFFFD66 0x00001E6B 0x00001DE5 0x00001D21 0x00001B8B 0x00001B5C 0x00001AF0 0x00001A8F 0x00001A45 0x00001AC1 0x00001A08 0x00001931 0x00001903 0x000018A1 0x000018EC 0x00002964
    // 0xFFFFFB45 0x00000F12 0x00000E5A 0x00000EB1 0x00000EC9 0x00000E61 0x00000E82 0x00000E03 0x00000E91 0x00000F10 0x00000ED9 0x00000E2A 0x00000EC4 0x00000E69 0x00000DF3 0x0000202D

    // [Channel 2]
    // 0xFFFFFBEB 0xFFFFF685 0xFFFFF783 0xFFFFF785 0xFFFFF761 0xFFFFF7A3 0xFFFFF83F 0xFFFFF824 0xFFFFF825 0xFFFFF85D 0xFFFFF8A1 0xFFFFF8D1 0xFFFFF87C 0xFFFFF8D7 0xFFFFF8F9 0xFFFFEF7A
    // 0xFFFFEC32 0xFFFFDE87 0xFFFFDFED 0xFFFFE131 0xFFFFE22C 0xFFFFE30B 0xFFFFE3F6 0xFFFFE47B 0xFFFFE48F 0xFFFFE52F 0xFFFFE5C3 0xFFFFE683 0xFFFFE62A 0xFFFFE6AD 0xFFFFE7AB 0xFFFFDFBF
    // 0xFFFFEE0E 0xFFFFE7F4 0xFFFFE83B 0xFFFFE84B 0xFFFFE8CE 0xFFFFE92B 0xFFFFE92A 0xFFFFE90B 0xFFFFE911 0xFFFFE93B 0xFFFFE983 0xFFFFE9AF 0xFFFFE945 0xFFFFE95C 0xFFFFE978 0xFFFFEC07

    // [Channel 3]
    // 0xFFFFE5BC 0xFFFFD899 0xFFFFD9E6 0xFFFFDB9C 0xFFFFDCE5 0xFFFFDDA5 0xFFFFDE65 0xFFFFDF0F 0xFFFFDF86 0xFFFFE020 0xFFFFE0E8 0xFFFFE164 0xFFFFE1EC 0xFFFFE238 0xFFFFE279 0xFFFFEBEB
    // 0x0000046D 0x00000254 0x000000D2 0xFFFFFFC1 0xFFFFFEF6 0xFFFFFE39 0xFFFFFD94 0xFFFFFCE6 0xFFFFFC57 0xFFFFFC02 0xFFFFFB5E 0xFFFFFAAA 0xFFFFFA5C 0xFFFFFA00 0xFFFFF94C 0xFFFFF6C1
    // 0x00000751 0x0000060B 0x00000580 0x00000503 0x000004CA 0x00000485 0x00000461 0x000003F2 0x000003B0 0x00000327 0x0000031F 0x000002FE 0x000002C8 0x00000308 0x000002FB 0xFFFFFC6D

endmodule

