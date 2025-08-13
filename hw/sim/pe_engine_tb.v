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
    localparam TEST_T_CHNOUT    = 1;
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
    wire                     fb_load_done;
    wire                     pb_sync_done;
    
    //
    reg  [W_SIZE-1:0]        q_width;
    reg  [W_SIZE-1:0]        q_height;
    reg  [W_CHANNEL-1:0]     q_channel;
    reg  [W_CHANNEL-1:0]     q_channel_out;
    reg  [W_FRAME_SIZE-1:0]  q_frame_size;
    reg                      q_start;

    wire                     ctrl_csync_run;
    wire                     ctrl_psync_run;
    wire                     ctrl_data_run;
    wire [W_SIZE-1:0]        row;
    wire [W_SIZE-1:0]        col;
    wire [W_CHANNEL-1:0]     chn;
    wire [W_CHANNEL-1:0]     chn_out;
    // wire [W_FRAME_SIZE-1:0]  data_count;
    // wire                     end_frame;

    wire                     fb_load_req;
    
    wire                     is_first_row;
    wire                     is_last_row;
    wire                     is_first_col;
    wire                     is_last_col; 
    wire                     is_first_chn;
    wire                     is_last_chn; 

    wire                     layer_done;
    wire                     pe_csync_done;

    cnn_ctrl u_cnn_ctrl (
        .clk               (clk               ),
        .rstn              (rstn              ),
        // Inputs
        .q_width           (q_width           ),
        .q_height          (q_height          ),
        .q_channel         (q_channel         ),
        .q_channel_out     (q_channel_out     ),
        .q_frame_size      (q_frame_size      ),
        .q_start           (q_start           ),
        // .fb_load_done      (fb_load_done      ),
        .pb_sync_done      (pb_sync_done      ),
        .pe_csync_done     (pe_csync_done     ),
        // Outputs
        .o_ctrl_csync_run  (ctrl_csync_run    ),
        .o_ctrl_psync_run  (ctrl_psync_run    ),
        .o_ctrl_data_run   (ctrl_data_run     ),
        .o_is_first_row    (is_first_row      ),
        .o_is_last_row     (is_last_row       ),
        .o_is_first_col    (is_first_col      ),
        .o_is_last_col     (is_last_col       ),
        .o_is_first_chn    (is_first_chn      ),
        .o_is_last_chn     (is_last_chn       ),
        .o_row             (row               ),
        .o_col             (col               ),
        .o_chn             (chn               ),
        .o_chn_out         (chn_out           ),
        .o_fb_load_req     (fb_load_req       ),
        .o_layer_done      (layer_done        )
    );

  //----------------------------------------------------------------------  
  // 5) pe_engine 인스턴스
  //---------------------------------------------------------------------- 
    wire                     fb_req_possible;

    pe_engine u_pe_engine (
        .clk(clk), 
        .rstn(rstn),
        .c_ctrl_data_run(ctrl_data_run),
        .c_ctrl_csync_run(ctrl_csync_run),
        .c_row(row),
        .c_col(col),
        .c_chn(chn),
        // .c_data_count(data_count),
        .c_is_first_row(is_first_row),
        .c_is_last_row (is_last_row),
        .c_is_first_col(is_first_col),
        .c_is_last_col (is_last_col),

        .q_channel(q_channel),

        .pe_csync_done(pe_csync_done),
        
        .ib_data0_in(ifm_data_0), 
        .ib_data1_in(ifm_data_1), 
        .ib_data2_in(ifm_data_2),
        
        .fb_req_possible(fb_req_possible),
        .o_fb_req(fb_req),
        .o_fb_addr(fb_addr),

        .fb_data0_in(filter_data_0),
        .fb_data1_in(filter_data_1),
        .fb_data2_in(filter_data_2),
        .fb_data3_in(filter_data_3),

        .o_pb_req(pb_req),
        .o_pb_addr(pb_addr),

        .pb_data_in(psum_data)
    );

    //----------------------------------------------------------------------  
    // 6) IFM buffer mimic (assume already loaded)
    //----------------------------------------------------------------------  

    reg [BUF_AW-1:0] ifm_base_addr;

    initial begin 
        ifm_base_addr = 0;

        ifm_data_0       = {IFM_DW{1'b0}};
        ifm_data_1       = {IFM_DW{1'b0}};
        ifm_data_2       = {IFM_DW{1'b0}};
    end
    
    always @(posedge clk or negedge rstn) begin 
        if (ctrl_data_run) begin 
            ifm_base_addr = col * TEST_T_CHNIN + chn;
            if (row == 0) begin 
                ifm_data_0 <= 0;
                ifm_data_1 <= ifmbuf0[ifm_base_addr];
                ifm_data_2 <= ifmbuf1[ifm_base_addr];
            end
            else if (row == 1) begin
                ifm_data_0 <= ifmbuf0[ifm_base_addr];
                ifm_data_1 <= ifmbuf1[ifm_base_addr];
                ifm_data_2 <= ifmbuf2[ifm_base_addr];
            end
            else if (row == 2) begin 
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
    
    assign fb_req_possible = filter_loaded;

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
        if (ctrl_csync_run && !filter_loaded) begin 
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
        q_channel_out  = TEST_T_CHNOUT;
        q_frame_size   = TEST_FRAME_SIZE;
        q_start        = 0; 

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
    // 0x000022A2 0xFFFFF31F 0xFFFFF46F 0xFFFFF885 0xFFFFF8FE 0xFFFFF87F 0xFFFFFA5C 0xFFFFF879 0xFFFFFB47 0xFFFFFDA6 0xFFFFFCEB 0xFFFFFE7A 0xFFFFFD5F 0xFFFFFD3E 0xFFFFFE65 0xFFFFC9CC
    // 0x000026FE 0xFFFFFECF 0x0000006B 0x000001E8 0x000000DE 0x000001F1 0x00000259 0x0000043B 0x00000381 0x00000214 0x0000014B 0x000002A9 0x00000315 0x00000172 0x000002AC 0xFFFFC145
    // 0x00002012 0x0000014E 0x0000020B 0x00000312 0x00000187 0x0000022D 0x00000176 0x00000368 0x00000336 0x000001D2 0x00000222 0x00000119 0x000000BD 0x000000FA 0x0000029E 0xFFFFCE42

    // [Channel 1]
    // 0xFFFFF8A2 0x00001680 0x0000141E 0x00001122 0x00001096 0x00001077 0x00000EB8 0x00000F8C 0x00000CF6 0x00000BF0 0x00000BFB 0x00000B7D 0x00000C11 0x00000C6F 0x00000BD1 0x00001DEF
    // 0xFFFFF0F0 0x000012F0 0x00001105 0x00000FB1 0x00000F64 0x00000EFB 0x00000E23 0x00000CB0 0x00000CD9 0x00000C51 0x00000CBF 0x00000BF0 0x00000B68 0x00000C64 0x00000BCE 0x00002178
    // 0xFFFFF109 0x000003A7 0x00000318 0x00000270 0x0000031C 0x000002FB 0x00000309 0x000001B7 0x000001F7 0x0000027F 0x00000218 0x0000026C 0x00000244 0x00000239 0x00000236 0x00001739

    // [Channel 2]
    // 0xFFFFF08C 0xFFFFEA4E 0xFFFFEC53 0xFFFFED78 0xFFFFEE2C 0xFFFFEF33 0xFFFFEFFA 0xFFFFF154 0xFFFFF19B 0xFFFFF0D0 0xFFFFF0A8 0xFFFFF12A 0xFFFFF166 0xFFFFF0FF 0xFFFFF114 0xFFFFE763
    // 0xFFFFE5F3 0xFFFFD8FB 0xFFFFDB60 0xFFFFDD97 0xFFFFDE7B 0xFFFFDFB9 0xFFFFE045 0xFFFFE174 0xFFFFE14F 0xFFFFE138 0xFFFFE171 0xFFFFE0A4 0xFFFFE039 0xFFFFE021 0xFFFFE0D3 0xFFFFD752
    // 0xFFFFE73F 0xFFFFDF2B 0xFFFFDFBF 0xFFFFDFDC 0xFFFFDFDE 0xFFFFE04A 0xFFFFDFD9 0xFFFFE002 0xFFFFDE77 0xFFFFDDF6 0xFFFFDDB2 0xFFFFDD6E 0xFFFFDD9F 0xFFFFDDFB 0xFFFFDDDF 0xFFFFE082

    // [Channel 3]
    // 0xFFFFD182 0xFFFFC5D7 0xFFFFC951 0xFFFFCC20 0xFFFFCE74 0xFFFFD03D 0xFFFFD1C4 0xFFFFD2FA 0xFFFFD3A7 0xFFFFD470 0xFFFFD46F 0xFFFFD442 0xFFFFD423 0xFFFFD3E9 0xFFFFD3D2 0xFFFFE378
    // 0xFFFFF41E 0xFFFFF4BD 0xFFFFF2FF 0xFFFFF1AB 0xFFFFF08F 0xFFFFEF65 0xFFFFEE9F 0xFFFFEB99 0xFFFFEA07 0xFFFFE8C0 0xFFFFE898 0xFFFFE8D4 0xFFFFE8A4 0xFFFFE899 0xFFFFE879 0xFFFFEE35
    // 0xFFFFFC76 0xFFFFFCD8 0xFFFFFC14 0xFFFFFB3B 0xFFFFFA76 0xFFFFFA1D 0xFFFFF9DA 0xFFFFFA07 0xFFFFFA1E 0xFFFFFA5C 0xFFFFF9D8 0xFFFFF9FC 0xFFFFFA93 0xFFFFFB07 0xFFFFFB70 0xFFFFF83B

endmodule

