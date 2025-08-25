`timescale 1ns/1ps
`include "controller_params.vh"

// select test case
// `define TESTCASE_0 1
// `define TESTCASE_1 1
`define TESTCASE_2 1


`include "sim_cfg.vh"
module top_tb;
    //----------------------------------------------------------------------  
    // 1) Parameter
    //----------------------------------------------------------------------  
    parameter W_SIZE        = `W_SIZE;
    parameter W_CHANNEL     = `W_CHANNEL;
    parameter W_FRAME_SIZE  = `W_FRAME_SIZE;
    parameter W_DELAY       = `W_DELAY;
    parameter K                = `K;
    parameter Tin              = `Tin;
    parameter Tout             = `Tout;

    parameter IFM_DW           = `IFM_DW;
    parameter IFM_AW           = `FM_BUFFER_AW;

    parameter OFM_DW            = `FM_BUFFER_DW;
    parameter OFM_AW            = `FM_BUFFER_AW;


    parameter FILTER_DW        = `FILTER_DW;
    parameter FILTER_AW        = `FILTER_BUFFER_AW;

    parameter PSUM_DW          = `W_PSUM;
    parameter W_PSUM           = `W_PSUM;
    parameter PE_IFM_FLAT_BW    = `PE_IFM_FLAT_BW;
    parameter PE_FILTER_FLAT_BW = `PE_FILTER_FLAT_BW;
    parameter PE_ACCO_FLAT_BW   = `PE_ACCO_FLAT_BW;

    parameter AXI_WIDTH_DA      = `AXI_WIDTH_DA;

    localparam CLK_PERIOD   = 10; // 100 MHz


    parameter TEST_ROW         = `TEST_ROW;
    parameter TEST_COL         = `TEST_COL;
    parameter TEST_CHNIN       = `TEST_CHNIN;    
    parameter TEST_CHNOUT      = `TEST_CHNOUT;

    parameter TEST_T_CHNIN     = `TEST_T_CHNIN;
    parameter TEST_T_CHNOUT    = `TEST_T_CHNOUT;
    parameter TEST_FRAME_SIZE  = `TEST_FRAME_SIZE;
    

    //----------------------------------------------------------------------  
    // 2) Signals
    //----------------------------------------------------------------------  
    reg  [W_SIZE+W_CHANNEL-1:0] q_row_stride;
    reg  [4:0]                  q_layer;
    reg                         q_load_ifm;
    reg                         q_load_filter;
    reg                         q_load_bias;
    reg                         q_load_scale;
    wire                        load_filter_done;

    // DRAM
    // 256KB ifm
    reg  [AXI_WIDTH_DA-1:0]     ifm_dram    [0:65536-1];
    reg  [AXI_WIDTH_DA-1:0]     filter_dram [0:65536-1];
    reg  [AXI_WIDTH_DA-1:0]     affine_dram [0:65536-1];
    reg  [PSUM_DW-1:0]          expect_conv [0:65536-1];
    reg  [OFM_DW-1:0]           expect_aff  [0:65536-1];
    reg  [OFM_DW-1:0]           expect_mp   [0:65536-1];


    // IFM, FILTER AXI
    reg [AXI_WIDTH_DA-1:0]      axi_read_data;      // data from axi
    reg                         axi_read_data_vld;  // whether valid
    reg                         axi_first;          //


    // BM <-> PE (IFM/FILTER) 연결선
    wire [IFM_DW-1:0]           ifm_data_0, ifm_data_1, ifm_data_2;
    wire                        fb_req;
    wire                        fb_req_possible;
    wire [FILTER_AW-1:0]        fb_addr;
    wire [FILTER_DW-1:0]        filter_data_0, filter_data_1, filter_data_2, filter_data_3;

    // ctrl
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
    wire                     ctrl_psync_phase;
    wire [W_SIZE-1:0]        row;
    wire [W_SIZE-1:0]        col;
    wire [W_CHANNEL-1:0]     chn;
    wire [W_CHANNEL-1:0]     chn_out;

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

    // pe -> postprocessor 연결선 
    wire [PE_ACCO_FLAT_BW-1:0]  pe_data;
    wire                        pe_vld;
    wire [W_SIZE-1:0]           pe_row;
    wire [W_SIZE-1:0]           pe_col;
    wire [W_CHANNEL-1:0]        pe_chn;
    wire [W_CHANNEL-1:0]        pe_chn_out;
    wire                        pe_is_first_chn;
    wire                        pe_is_last_chn; 

    // pp
    wire                        pp_load_done;
    // pp -> buffer manager
    wire                        pp_data_vld;
    wire [OFM_DW-1:0]           pp_data;
    wire [OFM_AW-1:0]           pp_addr;

    wire [W_SIZE-1:0]           pp_row;
    wire [W_SIZE-1:0]           pp_col;
    wire [W_CHANNEL-1:0]        pp_chn_out;

    // maxpool
    wire                        mp_data_vld;
    wire  [OFM_DW-1:0]          mp_data;
    wire  [OFM_AW-1:0]          mp_addr;


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
        
        .bm_csync_done     (bm_csync_done     ),
        .pe_csync_done     (pe_csync_done     ),

        .pp_load_done      (pp_load_done      ),
        .pb_sync_done      (pb_sync_done      ),
        
        // Outputs
        .o_ctrl_csync_run  (ctrl_csync_run    ),
        .o_ctrl_psync_run  (ctrl_psync_run    ),
        .o_ctrl_data_run   (ctrl_data_run     ),
        .o_ctrl_psync_phase(ctrl_psync_phase  ),
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
        .clk                (clk              ),
        .rstn               (rstn             ),

        // Buffer Manager <-> TOP
        .q_width            (q_width          ),
        .q_height           (q_height         ),
        .q_channel          (q_channel        ),
        .q_row_stride       (q_row_stride     ),

        .q_load_ifm         (q_load_ifm       ),
        .q_load_filter      (q_load_filter    ),
        .o_load_filter_done (load_filter_done ),

        // Buffer Manager <-> AXI (IFM/FILTER) : TB가 구동
        .read_data          (axi_read_data    ),
        .read_data_vld      (axi_read_data_vld),

        // Buffer Manager <-> Controller 
        .c_ctrl_data_run    (ctrl_data_run    ),
        .c_ctrl_csync_run   (ctrl_csync_run   ),
        .c_row              (row              ),
        .c_col              (col              ),
        .c_chn              (chn              ),

        .c_is_first_row     (is_first_row     ),
        .c_is_last_row      (is_last_row      ),
        .c_is_first_col     (is_first_col     ),
        .c_is_last_col      (is_last_col      ),
        .c_is_first_chn     (is_first_chn     ),
        .c_is_last_chn      (is_last_chn      ),

        .o_bm_csync_done    (bm_csync_done    ),

        // Buffer Manager <-> pe_engine (IFM)
        .ib_data0_out       (ifm_data_0       ),
        .ib_data1_out       (ifm_data_1       ),
        .ib_data2_out       (ifm_data_2       ),

        // Buffer Manager <-> pe_engine (FILTER)
        .fb_req_possible    (fb_req_possible  ),
        .fb_req             (fb_req           ),
        .fb_addr            (fb_addr          ),

        .fb_data0_out       (filter_data_0    ),
        .fb_data1_out       (filter_data_1    ),
        .fb_data2_out       (filter_data_2    ),
        .fb_data3_out       (filter_data_3    ),

        // Buffer Manager <-> post processor or max pooling module
        // .pp_data_vld        (pp_data_vld      ),
        // .pp_data            (pp_data          ),
        // .pp_addr            (pp_addr          )
        .pp_data_vld        (mp_data_vld      ),
        .pp_data            (mp_data          ),
        .pp_addr            (mp_addr          )
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
        .c_chn_out(chn_out),
        .c_is_first_row(is_first_row),
        .c_is_last_row (is_last_row),
        .c_is_first_col(is_first_col),
        .c_is_last_col (is_last_col),
        .c_is_first_chn(is_first_chn),
        .c_is_last_chn (is_last_chn),

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

        // pe_engine -> postprocessor
        .o_pe_data(pe_data),
        .o_pe_vld(pe_vld), 
        .o_pe_row(pe_row),
        .o_pe_col(pe_col),
        .o_pe_chn(pe_chn),
        .o_pe_chn_out(pe_chn_out),
        .o_pe_is_first_chn(pe_is_first_chn),
        .o_pe_is_last_chn(pe_is_last_chn) 
    );
    //----------------------------------------------------------------------  
    // 7) postprocessor instance
    //----------------------------------------------------------------------  
    postprocessor u_postprocessor (
        .clk(clk),
        .rstn(rstn),

        // postprocessor <-> top
        .q_width(q_width),
        .q_height(q_height),
        .q_channel(q_channel),    
        .q_channel_out(q_channel_out),


        .q_load_bias(q_load_bias),
        .q_load_scale(q_load_scale),

        // postprocessor <-> ctrl
        .c_ctrl_csync_run(ctrl_csync_run),
        .c_ctrl_psync_run(ctrl_psync_run),
        .c_ctrl_psync_phase(ctrl_psync_phase),

        .c_ctrl_chn_out(chn_out),


        .o_pp_load_done(pp_load_done),
        .o_pb_sync_done(pb_sync_done),

        // postprocessor <-> AXI
        .read_data(axi_read_data),
        .read_data_vld(axi_read_data_vld),
    
        // postprocessor <-> pe_engine
        .pe_data_i(pe_data),
        .pe_vld_i(pe_vld), 
        .pe_row_i(pe_row),
        .pe_col_i(pe_col),
        .pe_chn_i(pe_chn),
        .pe_chn_out_i(pe_chn_out),
        .pe_is_first_chn_i(pe_is_first_chn),
        .pe_is_last_chn_i(pe_is_last_chn), 

        // postprocessor <-> buffer_manager
        .o_pp_data_vld(pp_data_vld),
        .o_pp_data(pp_data),
        .o_pp_addr(pp_addr),

        .o_pp_row(pp_row),
        .o_pp_col(pp_col),
        .o_pp_chn_out(pp_chn_out)
    );
    //----------------------------------------------------------------------  
    // 8) maxpool instance
    //----------------------------------------------------------------------  
    maxpool u_maxpool (
        .clk(clk),
        .rstn(rstn),

        // maxpool <-> top
        .q_width(q_width),
        .q_height(q_height),
        .q_channel_out(q_channel_out),

        // maxpool <-> postprocessor
        .pp_data_vld(pp_data_vld),
        .pp_data(pp_data),
        .pp_row(pp_row), 
        .pp_col(pp_col), 
        .pp_chn_out(pp_chn_out),

        // maxpool <-> buffer manager
        .o_mp_data_vld(mp_data_vld),
        .o_mp_data(mp_data),
        .o_mp_addr(mp_addr)
    );


    //----------------------------------------------------------------------  
    // 9) AXI mimic
    //----------------------------------------------------------------------  
    function integer rand0_to_N;
        input integer N;
        integer r;
        begin
            r = $random;
            if (r < 0) r = -r;
            rand0_to_N = (N >= 0) ? (r % (N + 1)) : 0;
        end
    endfunction

    initial begin 
        axi_read_data     = 0;
        axi_read_data_vld = 0;
        axi_first         = 0;
    end

    localparam AXI_MAX_GAP   = 7;
    localparam AXI_MAX_BURST = 15;

    task automatic tb_axi_ifm_from_dram (
        input integer      n_words      // 쓸 워드 수 (q_width*q_height*q_channel)
        );
        integer i, j, dly, burst_len, remaining;
        begin
            axi_read_data_vld <= 1'b0;
            axi_read_data     <= 0;
            @(posedge clk);

            remaining = n_words;
            i = 0;
            while (remaining > 0) begin
                burst_len = rand0_to_N(AXI_MAX_BURST) + 1;
                if (burst_len > remaining) burst_len = remaining;

                // burst 전 latency
                dly = rand0_to_N(AXI_MAX_GAP);
                repeat (dly) @(posedge clk);

                for (j = 0; j < burst_len; j = j + 1) begin
                    axi_read_data     <= ifm_dram[i];
                    axi_read_data_vld <= 1'b1;
                    @(posedge clk);

                    axi_read_data_vld <= 1'b0;

                    i = i + 1;
                    remaining = remaining - 1;
                end
            end

            // drain
            axi_read_data_vld <= 1'b0;
            axi_read_data     <= 0;
            @(posedge clk);
        end
    endtask


    task automatic tb_load_filters_in_csync (
        input integer tout_idx
        );
        integer n_words, i, j, remaining, burst_len;
        integer dly; 
        integer base_addr;
        
        begin
            n_words = (q_channel << 2) * 9;
            base_addr = tout_idx * n_words;
            axi_read_data_vld <= 1'b0;
            axi_read_data     <= 0;
            
            @(posedge clk); wait (ctrl_csync_run == 1'b1);


            @(negedge clk);
            q_load_filter <= 1'b1;
            @(posedge clk); 

            remaining = n_words;
            i = 0;
            while (remaining > 0) begin
                burst_len = rand0_to_N(AXI_MAX_BURST) + 1;
                if (burst_len > remaining) burst_len = remaining;

                // burst 전 latency
                dly = rand0_to_N(AXI_MAX_GAP);
                repeat (dly) @(posedge clk);

                for (j = 0; j < burst_len; j = j + 1) begin
                    axi_read_data     <= filter_dram[base_addr + i];
                    axi_read_data_vld <= 1'b1;
                    @(posedge clk);

                    axi_read_data_vld <= 1'b0;

                    i = i + 1;
                    remaining = remaining - 1;
                end
            end

            // drain
            axi_read_data_vld <= 1'b0;
            axi_read_data     <= 0;

            @(posedge clk);
            @(negedge clk);
            q_load_filter <= 1'b0;
            @(posedge clk); 


            // wait csync deassert 
            if (ctrl_csync_run === 1'b1) @(negedge ctrl_csync_run);
        end
    endtask


    task automatic tb_load_affine_in_prepsync (
        );
        integer n_words_bias, n_words_scale, i, j, remaining, burst_len;
        integer dly; 
        integer base_addr_bias, base_addr_scale;
        
        begin
            n_words_bias = (q_channel_out << 2);
            n_words_scale = (q_channel_out << 2);

            base_addr_bias = 0;
            base_addr_scale = (q_channel_out << 2);


            axi_read_data_vld <= 1'b0;
            axi_read_data     <= 0;
            
            @(posedge clk); wait (ctrl_psync_run == 1'b1);

            // load bias
            
            @(negedge clk);
            q_load_bias <= 1'b1;
            @(posedge clk);  

            remaining = n_words_bias;
            i = 0;
            while (remaining > 0) begin
                burst_len = rand0_to_N(AXI_MAX_BURST) + 1;
                if (burst_len > remaining) burst_len = remaining;

                // burst 전 latency
                dly = rand0_to_N(AXI_MAX_GAP);
                repeat (dly) @(posedge clk);

                for (j = 0; j < burst_len; j = j + 1) begin
                    axi_read_data     <= affine_dram[base_addr_bias + i];
                    axi_read_data_vld <= 1'b1;
                    @(posedge clk);

                    axi_read_data_vld <= 1'b0;

                    i = i + 1;
                    remaining = remaining - 1;
                end
            end

            // drain
            axi_read_data_vld <= 1'b0;
            axi_read_data     <= 0;

            @(negedge clk);
            q_load_bias <= 1'b0;
            @(posedge clk);  
            // load bias end



            // load scale
            @(negedge clk);
            q_load_scale <= 1'b1;
            @(posedge clk);  

            remaining = n_words_scale;
            i = 0;
            while (remaining > 0) begin
                burst_len = rand0_to_N(AXI_MAX_BURST) + 1;
                if (burst_len > remaining) burst_len = remaining;

                // burst 전 latency
                dly = rand0_to_N(AXI_MAX_GAP);
                repeat (dly) @(posedge clk);

                for (j = 0; j < burst_len; j = j + 1) begin
                    axi_read_data     <= affine_dram[base_addr_scale + i];
                    axi_read_data_vld <= 1'b1;
                    @(posedge clk);

                    axi_read_data_vld <= 1'b0;

                    i = i + 1;
                    remaining = remaining - 1;
                end
            end

            // drain
            axi_read_data_vld <= 1'b0;
            axi_read_data     <= 0;

            @(negedge clk);
            q_load_scale <= 1'b0;
            @(posedge clk);  
            // load scale end


            // wait csync deassert 
            if (ctrl_psync_run === 1'b1) @(negedge ctrl_psync_run);
        end
    endtask

    //----------------------------------------------------------------------  
    // 9) stimulus
    //---------------------------------------------------------------------- 
    integer t;
    initial begin
        rstn           = 1'b0;
        q_width        = TEST_COL;
        q_height       = TEST_ROW;   
        q_channel      = TEST_T_CHNIN;
        q_channel_out  = TEST_T_CHNOUT;
        q_row_stride   = q_width * q_channel;
        q_frame_size   = TEST_FRAME_SIZE;
        q_layer        = 0;
        q_start        = 0; 

        q_load_ifm     = 0;
        q_load_filter  = 0;
        q_load_bias    = 0;
        q_load_scale   = 0;

        t = 0;

        #(4*CLK_PERIOD) rstn = 1'b1;
        #(CLK_PERIOD);

        // AXI load ifm
        q_load_ifm = 1;
        
        tb_axi_ifm_from_dram(q_width*q_height*q_channel);
        
        #(CLK_PERIOD);
        q_load_ifm = 0;
        //


        #(100*CLK_PERIOD)
            @(posedge clk) q_start = 1'b1;
        #(4*CLK_PERIOD)
            @(posedge clk) q_start = 1'b0;

        @(posedge clk);
        tb_load_affine_in_prepsync();
        @(posedge clk);

        // load filter
        for (t = 0; t < TEST_T_CHNOUT; t = t + 1) begin
            tb_load_filters_in_csync(t);
        end
    end
    //--------------------------------------------------------------------------
    // 10) Initialize dram & compare output
    //--------------------------------------------------------------------------
    initial begin 
        $readmemh(`TEST_IFM_PATH, ifm_dram);
        $readmemh(`TEST_FILT_PATH, filter_dram);
        $readmemh(`TEST_AFFINE_PATH, affine_dram);
        $readmemh(`TEST_EXP_CONV_PATH, expect_conv);
        $readmemh(`TEST_EXP_AFFINE_PATH, expect_aff);
        $readmemh(`TEST_EXP_MAXPOOL_PATH, expect_mp);
    end

    // ------- capture signals -------
    reg [OFM_DW-1:0]  cap_pp_mem [0:65536-1];
    reg [OFM_DW-1:0]  cap_mp_mem [0:65536-1];

    wire                cap_pp_vld  = pp_data_vld;
    wire [OFM_DW-1:0]   cap_pp_data = pp_data;
    wire [OFM_AW-1:0]   cap_pp_addr = pp_addr;

    wire                cap_mp_vld  = mp_data_vld;
    wire [OFM_DW-1:0]   cap_mp_data = mp_data;
    wire [OFM_AW-1:0]   cap_mp_addr = mp_addr;

    always @(posedge clk) begin
        if (cap_pp_vld) begin
            cap_pp_mem[cap_pp_addr] <= cap_pp_data;
        end

        if (cap_mp_vld) begin 
            cap_mp_mem[cap_mp_addr] <= cap_mp_data;
        end
    end
    // -------------------------------

    task automatic tb_check_conv_result;
        integer i;
        integer exp_words;
        integer errors, checks;
        integer max_print, printed;
        reg [OFM_DW-1:0] got, exp;
        
        begin
            errors    = 0;
            checks    = 0;
            max_print = 200;
            printed   = 0;
            exp_words = TEST_ROW * TEST_COL * TEST_CHNOUT;
            $display("============================================================");
            $display("CONV CHECK START");

            for (i = 0; i < exp_words; i = i + 1) begin
                got = u_postprocessor.psumbuf[i]; 
                exp = expect_conv[i]; 
                if (got !== exp) begin
                    errors = errors + 1;
                    if (printed < max_print) begin
                        $display("[%0t] MIS idx=%0d : got=%h  exp=%h",
                                $time, i, got, exp);
                        printed = printed + 1;
                    end
                end
                checks = checks + 1;
            end

            // --------- summary ---------
            $display("------------------------------------------------------------");
            $display("CONV CHECK SUMMARY @%0t", $time);
            $display("  total=%0d  match=%0d  errors=%0d",
                    checks, checks - errors, errors);
            $display("------------------------------------------------------------");
            if (errors == 0) begin
                $display("RESULT: PASS");
            end else begin
                $display("RESULT: FAIL");
            end
            $display("============================================================");
            // -----------------------------------------------

        end
    endtask


    task automatic tb_check_affine_result;
        integer i;
        integer exp_words;
        integer errors, checks;
        integer max_print, printed;
        reg [W_PSUM-1:0] got, exp;
        
        begin
            errors    = 0;
            checks    = 0;
            max_print = 200;
            printed   = 0;
            exp_words = TEST_ROW * TEST_COL * TEST_T_CHNOUT;
            $display("============================================================");
            $display("AFFINE CHECK START");

            for (i = 0; i < exp_words; i = i + 1) begin
                got = cap_pp_mem[i]; 
                exp = expect_aff[i]; 
                if (got !== exp) begin
                    errors = errors + 1;
                    if (printed < max_print) begin
                        $display("[%0t] MIS idx=%0d : got=%h  exp=%h",
                                $time, i, got, exp);
                        printed = printed + 1;
                    end
                end
                checks = checks + 1;
            end

            // --------- summary ---------
            $display("------------------------------------------------------------");
            $display("AFFINE CHECK SUMMARY @%0t", $time);
            $display("  total=%0d  match=%0d  errors=%0d",
                    checks, checks - errors, errors);
            $display("------------------------------------------------------------");
            if (errors == 0) begin
                $display("RESULT: PASS");
            end else begin
                $display("RESULT: FAIL");
            end
            $display("============================================================");
            // -----------------------------------------------

        end
    endtask


    task automatic tb_check_maxpool_result;
        integer i;
        integer exp_words;
        integer errors, checks;
        integer max_print, printed;
        reg [OFM_DW-1:0] got, exp;
        
        begin
            errors    = 0;
            checks    = 0;
            max_print = 50;
            printed   = 0;
            exp_words = TEST_ROW * TEST_COL * TEST_T_CHNOUT;
            $display("============================================================");
            $display("MAXPOOL CHECK START");

            for (i = 0; i < exp_words; i = i + 1) begin
                got = cap_mp_mem[i]; 
                exp = expect_mp[i]; 
                if (got !== exp) begin
                    errors = errors + 1;
                    if (printed < max_print) begin
                        $display("[%0t] MIS idx=%0d : got=%h  exp=%h",
                                $time, i, got, exp);
                        printed = printed + 1;
                    end
                end
                checks = checks + 1;
            end

            // --------- summary ---------
            $display("------------------------------------------------------------");
            $display("MAXPOOL CHECK SUMMARY @%0t", $time);
            $display("  total=%0d  match=%0d  errors=%0d",
                    checks, checks - errors, errors);
            $display("------------------------------------------------------------");
            if (errors == 0) begin
                $display("RESULT: PASS");
            end else begin
                $display("RESULT: FAIL");
            end
            $display("============================================================");
            // -----------------------------------------------

        end
    endtask



    reg checked_done;
    initial checked_done = 1'b0;

    always @(posedge clk) begin
        if (layer_done && !checked_done) begin
            @(posedge clk);
            @(posedge clk);
            tb_check_conv_result();
            tb_check_affine_result();
            tb_check_maxpool_result();
            @(posedge clk);
            checked_done <= 1'b1;
        end
    end

    initial begin
        @(posedge checked_done);     
        repeat (100) @(posedge clk);
        $finish;
    end

endmodule