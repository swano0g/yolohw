`timescale 1ns/1ps
`include "controller_params.vh"

module bm_tb;
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
    parameter IFM_AW           = `IFM_TOTAL_BUFFER_AW;

    parameter FILTER_DW        = `FILTER_DW;
    parameter FILTER_AW        = `FILTER_BUFFER_AW;
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
    reg  [W_SIZE+W_CHANNEL-1:0] q_row_stride;
    reg  [4:0]                  q_layer;
    reg                         q_load_ifm;
    wire                        load_ifm_done;
    reg  [W_CHANNEL-1:0]        q_outchn;
    reg                         q_load_filter;
    wire                        load_filter_done;

    // DRAM
    // 256KB ifm
    reg  [IFM_DW-1:0]           ifm_dram    [0:65536-1];
    reg  [FILTER_DW-1:0]        filter_dram [0:65536-1];

    // IFM AXI mimic (TB에서 구동)
    reg                         dbg_axi_ib_ena;
    reg  [IFM_AW-1:0]           dbg_axi_ib_addra;
    reg                         dbg_axi_ib_wea;
    reg  [IFM_DW-1:0]           dbg_axi_ib_dia;

    // FILTER AXI mimic (TB에서 구동)
    reg                         dbg_axi_fb0_ena;
    reg  [FILTER_AW-1:0]        dbg_axi_fb0_addra;
    reg                         dbg_axi_fb0_wea;
    reg  [FILTER_DW-1:0]        dbg_axi_fb0_dia;

    reg                         dbg_axi_fb1_ena;
    reg  [FILTER_AW-1:0]        dbg_axi_fb1_addra;
    reg                         dbg_axi_fb1_wea;
    reg  [FILTER_DW-1:0]        dbg_axi_fb1_dia;

    reg                         dbg_axi_fb2_ena;
    reg  [FILTER_AW-1:0]        dbg_axi_fb2_addra;
    reg                         dbg_axi_fb2_wea;
    reg  [FILTER_DW-1:0]        dbg_axi_fb2_dia;

    reg                         dbg_axi_fb3_ena;
    reg  [FILTER_AW-1:0]        dbg_axi_fb3_addra;
    reg                         dbg_axi_fb3_wea;
    reg  [FILTER_DW-1:0]        dbg_axi_fb3_dia;


    // BM <-> PE (IFM/FILTER) 연결선
    wire [IFM_DW-1:0]           ifm_data_0, ifm_data_1, ifm_data_2;
    wire                        fb_req;
    wire                        fb_req_possible;
    wire [FILTER_AW-1:0]        fb_addr;
    wire [FILTER_DW-1:0]        filter_data_0, filter_data_1, filter_data_2, filter_data_3;


    //----------------------------------------------------------------------  
    // 3) clock & reset
    //----------------------------------------------------------------------  
    reg                  clk, rstn;
    initial begin
        clk = 0; forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //----------------------------------------------------------------------  
    // 4) cnn_ctrl instance
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
    wire                     bm_csync_done;
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
        .pb_sync_done      (pb_sync_done      ),
        .bm_csync_done     (bm_csync_done     ),
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
    // 5) buffer_manager instance
    //----------------------------------------------------------------------  

    buffer_manager u_buffer_manager (
        .clk                (clk),
        .rstn               (rstn),

        // Buffer Manager <-> TOP
        .q_width            (q_width),
        .q_height           (q_height),
        .q_channel          (q_channel),
        .q_row_stride       (q_row_stride),

        .q_layer            (q_layer),

        .q_load_ifm         (q_load_ifm),
        .o_load_ifm_done    (load_ifm_done),

        .q_outchn           (q_outchn),
        .q_load_filter      (q_load_filter),
        .o_load_filter_done (load_filter_done),

        // Buffer Manager <-> AXI (IFM/FILTER) : TB가 구동
        .dbg_axi_ib_ena     (dbg_axi_ib_ena),
        .dbg_axi_ib_addra   (dbg_axi_ib_addra),
        .dbg_axi_ib_wea     (dbg_axi_ib_wea),
        .dbg_axi_ib_dia     (dbg_axi_ib_dia),

        .dbg_axi_fb0_ena    (dbg_axi_fb0_ena),
        .dbg_axi_fb0_addra  (dbg_axi_fb0_addra),
        .dbg_axi_fb0_wea    (dbg_axi_fb0_wea),
        .dbg_axi_fb0_dia    (dbg_axi_fb0_dia),

        .dbg_axi_fb1_ena    (dbg_axi_fb1_ena),
        .dbg_axi_fb1_addra  (dbg_axi_fb1_addra),
        .dbg_axi_fb1_wea    (dbg_axi_fb1_wea),
        .dbg_axi_fb1_dia    (dbg_axi_fb1_dia),

        .dbg_axi_fb2_ena    (dbg_axi_fb2_ena),
        .dbg_axi_fb2_addra  (dbg_axi_fb2_addra),
        .dbg_axi_fb2_wea    (dbg_axi_fb2_wea),
        .dbg_axi_fb2_dia    (dbg_axi_fb2_dia),

        .dbg_axi_fb3_ena    (dbg_axi_fb3_ena),
        .dbg_axi_fb3_addra  (dbg_axi_fb3_addra),
        .dbg_axi_fb3_wea    (dbg_axi_fb3_wea),
        .dbg_axi_fb3_dia    (dbg_axi_fb3_dia),
        //


        // Buffer Manager <-> Controller 
        .c_ctrl_data_run    (ctrl_data_run),
        .c_ctrl_csync_run   (ctrl_csync_run),
        .c_row              (row),
        .c_col              (col),
        .c_chn              (chn),

        .c_is_first_row     (is_first_row),
        .c_is_last_row      (is_last_row),
        .c_is_first_col     (is_first_col),
        .c_is_last_col      (is_last_col),
        .c_is_first_chn     (is_first_chn),
        .c_is_last_chn      (is_last_chn),

        .o_bm_csync_done    (bm_csync_done),


        // Buffer Manager <-> pe_engine (IFM)
        .ib_data0_out       (ifm_data_0),
        .ib_data1_out       (ifm_data_1),
        .ib_data2_out       (ifm_data_2),

        // Buffer Manager <-> pe_engine (FILTER)
        .fb_req_possible    (fb_req_possible),
        .fb_req             (fb_req),     // from PE
        .fb_addr            (fb_addr),    // from PE

        .fb_data0_out       (filter_data_0),
        .fb_data1_out       (filter_data_1),
        .fb_data2_out       (filter_data_2),
        .fb_data3_out       (filter_data_3)
    );





    //----------------------------------------------------------------------  
    // 6) pe_engine instance
    //---------------------------------------------------------------------- 
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

        .o_pe_csync_done(pe_csync_done),
        
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
    // 7) dram -> bram mimic
    //----------------------------------------------------------------------  
    initial begin 
        // IFM
        dbg_axi_ib_ena   = 1'b0;
        dbg_axi_ib_wea   = 1'b0;
        dbg_axi_ib_addra = 0;
        dbg_axi_ib_dia   = 0;
        // FILTER
        dbg_axi_fb0_ena   = 1'b0; dbg_axi_fb0_wea   = 1'b0; dbg_axi_fb0_addra = 0; dbg_axi_fb0_dia = 0;
        dbg_axi_fb1_ena   = 1'b0; dbg_axi_fb1_wea   = 1'b0; dbg_axi_fb1_addra = 0; dbg_axi_fb1_dia = 0;
        dbg_axi_fb2_ena   = 1'b0; dbg_axi_fb2_wea   = 1'b0; dbg_axi_fb2_addra = 0; dbg_axi_fb2_dia = 0;
        dbg_axi_fb3_ena   = 1'b0; dbg_axi_fb3_wea   = 1'b0; dbg_axi_fb3_addra = 0; dbg_axi_fb3_dia = 0;
    end

    task automatic tb_axi_ifm_from_dram (
        input integer      n_words      // 쓸 워드 수 (q_width*q_height*q_channel)
        );
        integer i;
        begin
            // 1클럭당 1워드 쓰기
            dbg_axi_ib_ena <= 1'b1;
            dbg_axi_ib_wea <= 1'b1;
            for (i = 0; i < n_words; i = i + 1) begin
                @(posedge clk);
                dbg_axi_ib_addra <= i[IFM_AW-1:0];
                dbg_axi_ib_dia   <= ifm_dram[i];
            end
            @(posedge clk);
            dbg_axi_ib_ena <= 1'b0;
            dbg_axi_ib_wea <= 1'b0;
        end
    endtask

    task automatic tb_axi_fb0 (
        input integer n_words,
        input integer base_addr
        );

        integer i;
        begin
            dbg_axi_fb0_ena <= 1'b1; 
            dbg_axi_fb0_wea <= 1'b1;
            for (i = 0; i < n_words; i = i + 1) begin
                @(posedge clk);
                dbg_axi_fb0_addra <= i[FILTER_AW-1:0];
                dbg_axi_fb0_dia   <= filter_dram[base_addr+i];
            end
            @(posedge clk);
            dbg_axi_fb0_ena <= 1'b0; 
            dbg_axi_fb0_wea <= 1'b0;
        end
    endtask
    task automatic tb_axi_fb1 (
        input integer n_words,
        input integer base_addr
        );
        integer i;
        begin
            dbg_axi_fb1_ena <= 1'b1; 
            dbg_axi_fb1_wea <= 1'b1;
            for (i = 0; i < n_words; i = i + 1) begin
                @(posedge clk);
                dbg_axi_fb1_addra <= i[FILTER_AW-1:0];
                dbg_axi_fb1_dia   <= filter_dram[base_addr+i];
            end
            @(posedge clk);
            dbg_axi_fb1_ena <= 1'b0; 
            dbg_axi_fb1_wea <= 1'b0;
        end
    endtask
    task automatic tb_axi_fb2 (
        input integer n_words,
        input integer base_addr
        );
        integer i;
        begin
            dbg_axi_fb2_ena <= 1'b1; 
            dbg_axi_fb2_wea <= 1'b1;
            for (i = 0; i < n_words; i = i + 1) begin
                @(posedge clk);
                dbg_axi_fb2_addra <= i[FILTER_AW-1:0];
                dbg_axi_fb2_dia   <= filter_dram[base_addr+i];
            end
            @(posedge clk);
            dbg_axi_fb2_ena <= 1'b0; 
            dbg_axi_fb2_wea <= 1'b0;
        end
    endtask
    task automatic tb_axi_fb3(
        input integer n_words,
        input integer base_addr
        );
        integer i;
        begin
            dbg_axi_fb3_ena <= 1'b1; 
            dbg_axi_fb3_wea <= 1'b1;
            for (i = 0; i < n_words; i = i + 1) begin
                @(posedge clk);
                dbg_axi_fb3_addra <= i[FILTER_AW-1:0];
                dbg_axi_fb3_dia   <= filter_dram[base_addr+i];
            end
            @(posedge clk);
            dbg_axi_fb3_ena <= 1'b0; 
            dbg_axi_fb3_wea <= 1'b0;
        end
    endtask

    task automatic tb_load_filters_in_csync (
        input integer tout_idx
        );
        integer words, i;
        integer dly; 
        integer dram_base0, dram_base1, dram_base2, dram_base3;
        begin
            words = (q_channel << 2);
            dram_base0 = (4 * tout_idx + 0) * words;
            dram_base1 = (4 * tout_idx + 1) * words;
            dram_base2 = (4 * tout_idx + 2) * words;
            dram_base3 = (4 * tout_idx + 3) * words;


            @(posedge clk); wait (ctrl_csync_run == 1'b1);

            // mimic dram latency
            dly = $random & 8'h7; repeat(dly) @(posedge clk);
            tb_axi_fb0(words, dram_base0);
            dly = $random & 8'h7; repeat(dly) @(posedge clk);
            tb_axi_fb1(words, dram_base1);
            dly = $random & 8'h7; repeat(dly) @(posedge clk);
            tb_axi_fb2(words, dram_base2);
            dly = $random & 8'h7; repeat(dly) @(posedge clk);
            tb_axi_fb3(words, dram_base3);
        end
    endtask



    //----------------------------------------------------------------------  
    // 7) stimulus
    //----------------------------------------------------------------------  
    initial begin
        rstn           = 1'b0;
        q_width        = TEST_COL;
        q_height       = TEST_ROW;   
        q_channel      = TEST_T_CHNIN;           // (tiled)채널 수 1. 즉 실제 input channel = 4
        q_channel_out  = TEST_T_CHNOUT;
        q_row_stride   = q_width * q_channel;
        q_frame_size   = TEST_FRAME_SIZE;
        q_layer        = 0;
        q_start        = 0; 

        #(4*CLK_PERIOD) rstn = 1'b1;
        #(CLK_PERIOD);


        tb_axi_ifm_from_dram(q_width*q_height*q_channel);

        #(100*CLK_PERIOD)
            @(posedge clk) q_start = 1'b1;
        #(4*CLK_PERIOD)
            @(posedge clk) q_start = 1'b0;

        // FIXME
        tb_load_filters_in_csync(0);
    end


    //--------------------------------------------------------------------------
    // Initialize dram
    //--------------------------------------------------------------------------
    initial begin
        // row 0
        ifm_dram[0]  = 32'h00707064; ifm_dram[1]  = 32'h006F6F63;
        ifm_dram[2]  = 32'h0066685D; ifm_dram[3]  = 32'h005E5F56;
        ifm_dram[4]  = 32'h005D5D56; ifm_dram[5]  = 32'h00595B54;
        ifm_dram[6]  = 32'h0055574F; ifm_dram[7]  = 32'h0054554F;
        ifm_dram[8]  = 32'h0053544E; ifm_dram[9]  = 32'h004F524B;
        ifm_dram[10] = 32'h004C504B; ifm_dram[11] = 32'h00494D48;
        ifm_dram[12] = 32'h00494A46; ifm_dram[13] = 32'h00484A45;
        ifm_dram[14] = 32'h00474944; ifm_dram[15] = 32'h00424643;
        ifm_dram[16] = 32'h003f3e3e; ifm_dram[17] = 32'h003f4040;
        ifm_dram[18] = 32'h00404040; ifm_dram[19] = 32'h003f3f3f;
        ifm_dram[20] = 32'h003f3f3f; ifm_dram[21] = 32'h003f3f3f;
        ifm_dram[22] = 32'h003f3f3f; ifm_dram[23] = 32'h00403f3f;
        ifm_dram[24] = 32'h00404040; ifm_dram[25] = 32'h003d3f3f;
        ifm_dram[26] = 32'h003d403f; ifm_dram[27] = 32'h003f3f3f;
        ifm_dram[28] = 32'h00403f3f; ifm_dram[29] = 32'h003f3f3f;
        ifm_dram[30] = 32'h00404040; ifm_dram[31] = 32'h00404040;
        // row 1
        ifm_dram[32+0]  = 32'h00474644; ifm_dram[32+1]  = 32'h00424340;
        ifm_dram[32+2]  = 32'h0042423F; ifm_dram[32+3]  = 32'h0042413F;
        ifm_dram[32+4]  = 32'h003F3F3D; ifm_dram[32+5]  = 32'h003E3F3D;
        ifm_dram[32+6]  = 32'h003E3E3C; ifm_dram[32+7]  = 32'h003E3E3C;
        ifm_dram[32+8]  = 32'h003D3D3B; ifm_dram[32+9]  = 32'h003C3D3B;
        ifm_dram[32+10] = 32'h003B3B39; ifm_dram[32+11] = 32'h003B3B39;
        ifm_dram[32+12] = 32'h003B3B3B; ifm_dram[32+13] = 32'h003A3A3A;
        ifm_dram[32+14] = 32'h003C3C3A; ifm_dram[32+15] = 32'h003A3B39;
        ifm_dram[32+16] = 32'h003e4040; ifm_dram[32+17] = 32'h00414141;
        ifm_dram[32+18] = 32'h003f4040; ifm_dram[32+19] = 32'h003e3f3f;
        ifm_dram[32+20] = 32'h003e4040; ifm_dram[32+21] = 32'h003d403f;
        ifm_dram[32+22] = 32'h003d3f3f; ifm_dram[32+23] = 32'h003f3f3f;
        ifm_dram[32+24] = 32'h00423f40; ifm_dram[32+25] = 32'h00404040;
        ifm_dram[32+26] = 32'h00424141; ifm_dram[32+27] = 32'h00414141;
        ifm_dram[32+28] = 32'h003f4141; ifm_dram[32+29] = 32'h00404242;
        ifm_dram[32+30] = 32'h00404242; ifm_dram[32+31] = 32'h00414242;
        // row 2
        ifm_dram[64+0]  = 32'h003C3C3A; ifm_dram[64+1]  = 32'h003C3C3C;
        ifm_dram[64+2]  = 32'h003C3C3C; ifm_dram[64+3]  = 32'h003D3D3D;
        ifm_dram[64+4]  = 32'h003C3C3C; ifm_dram[64+5]  = 32'h003C3D3B;
        ifm_dram[64+6]  = 32'h003D3D3D; ifm_dram[64+7]  = 32'h003D3D3D;
        ifm_dram[64+8]  = 32'h003F3F3F; ifm_dram[64+9]  = 32'h003D3F3F;
        ifm_dram[64+10] = 32'h003D3F3F; ifm_dram[64+11] = 32'h003D3F3F;
        ifm_dram[64+12] = 32'h00404040; ifm_dram[64+13] = 32'h003D3E3E;
        ifm_dram[64+14] = 32'h003E3F3F; ifm_dram[64+15] = 32'h00404040;
        ifm_dram[64+16] = 32'h00404242; ifm_dram[64+17] = 32'h00404242;
        ifm_dram[64+18] = 32'h00404242; ifm_dram[64+19] = 32'h00404243;
        ifm_dram[64+20] = 32'h00414242; ifm_dram[64+21] = 32'h00434244;
        ifm_dram[64+22] = 32'h00434144; ifm_dram[64+23] = 32'h00424244;
        ifm_dram[64+24] = 32'h003f4242; ifm_dram[64+25] = 32'h00404241;
        ifm_dram[64+26] = 32'h003e4141; ifm_dram[64+27] = 32'h00404244;
        ifm_dram[64+28] = 32'h003c4042; ifm_dram[64+29] = 32'h003e4140;
        ifm_dram[64+30] = 32'h00414141; ifm_dram[64+31] = 32'h00424242;
    end

    initial begin
        // output chn 0
        filter_dram[0] = 72'h13f5fa3defd617feeb; filter_dram[1] = 72'h11f4fb30f2e00bfcfd;
        filter_dram[2] = 72'h10f00031efe106fffb; filter_dram[3] = 72'h0cf1ef0505ee0602ef;
        filter_dram[4] = 72'hffff04fff80004fe01; filter_dram[5] = 72'h00fc0000fa00060005;
        filter_dram[6] = 72'h00fe03ffff01ff0100; filter_dram[7] = 72'h0506ff0601ff0200fd;
        // output chn 1
        filter_dram[8+0] = 72'hedf0f5d4fef2e3e9ea; filter_dram[8+1] = 72'h11131afa3e2c0b2427;
        filter_dram[8+2] = 72'h03060ef8011505ea09; filter_dram[8+3] = 72'h08091110060e140314;
        filter_dram[8+4] = 72'hfffffffdfbfd0200ff; filter_dram[8+5] = 72'h00fe02fcf9fffefb00;
        filter_dram[8+6] = 72'hff0202faf4fc00ff04; filter_dram[8+7] = 72'h00f9fe00f2fc01fb01;
        // output chn 2
        filter_dram[16+0] = 72'h00dbe6f7d8e507d7ef; filter_dram[16+1] = 72'h18110c0b1718fc09ff;
        filter_dram[16+2] = 72'h14fdf8fcf800f4fcfc; filter_dram[16+3] = 72'h15f3effcf1f6fdf6ed;
        filter_dram[16+4] = 72'h00fe03fafafc02ff03; filter_dram[16+5] = 72'h00000000ffff000101;
        filter_dram[16+6] = 72'h040204fdf1fb06fafd; filter_dram[16+7] = 72'hfff5f9fff5fcfe0003;
        // output chn 3
        filter_dram[24+0] = 72'hf6fe04f7f8f708000a; filter_dram[24+1] = 72'hfff3fcfcfdf7170706;
        filter_dram[24+2] = 72'hf2f8f700f7f70b0804; filter_dram[24+3] = 72'h19f616f9e009faebf8;
        filter_dram[24+4] = 72'hfe03fcff00ff030703; filter_dram[24+5] = 72'hfd0001fafa01fc0003;
        filter_dram[24+6] = 72'hfdf900f6ecfe00f804; filter_dram[24+7] = 72'h030104020101000000;
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

