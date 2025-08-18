`timescale 1ns / 1ps
`include "controller_params.vh"

module cnn_ctrl_tb;
    parameter W_SIZE        = `W_SIZE;                   // Max width 256
    parameter W_CHANNEL     = `W_CHANNEL;
    parameter W_FRAME_SIZE  = `W_FRAME_SIZE;
    parameter W_DELAY       = `W_DELAY;
    
    parameter WIDTH         = 32;
    parameter HEIGHT        = 32;
    parameter CHANNEL       = 16;
    parameter CHANNEL_O     = 32;
    parameter FRAME_SIZE    = WIDTH * HEIGHT * CHANNEL;
    
    reg                      clk, rstn;
    // buffer synchronization signals
    reg                      fb_load_done;
    reg                      pb_sync_done;

    
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

    wire                     layer_done;

    wire                     fb_load_req;
    
    wire                     is_first_row;
    wire                     is_last_row;
    wire                     is_first_col;
    wire                     is_last_col;
    wire                     is_first_chn;
    wire                     is_last_chn;

    //-------------------------------------------------
    // Controller (FSM)
    //-------------------------------------------------
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

        .fb_load_done      (fb_load_done      ),    // not used
        .pb_sync_done      (pb_sync_done      ),

        // Outputs
        .o_fb_load_req     (fb_load_req       ),
        .o_ctrl_csync_run  (ctrl_csync_run    ),
        .o_ctrl_psync_run  (ctrl_psync_run    ),
        .o_ctrl_data_run   (ctrl_data_run     ),

        .o_layer_done      (layer_done        ),

        .o_is_first_row    (is_first_row      ),
        .o_is_last_row     (is_last_row       ),
        .o_is_first_col    (is_first_col      ),
        .o_is_last_col     (is_last_col       ),
        .o_is_first_chn    (is_first_chn      ),
        .o_is_last_chn     (is_last_chn       ),
        .o_row             (row               ),
        .o_col             (col               ),
        .o_chn             (chn               ), 
        .o_chn_out         (chn_out           )
    );

    // Clock
    parameter CLK_PERIOD = 10;  // 100MHz
    initial begin
        clk = 1'b1;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
   

    // TB: FILTER buffer load emulation (128-cycle delay -> 1-cycle done pulse) ----------------------------
    localparam integer FB_DELAY = CHANNEL * 4;

    reg        f_loading;
    reg [6:0]  f_load_cnt;      // 0..127 (7 bits)

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            f_loading     <= 1'b0;
            f_load_cnt    <= 7'd0;
            fb_load_done  <= 1'b0;
        end else begin
            fb_load_done  <= 1'b0;  // 기본값(펄스용)

            if (fb_load_req && !f_loading) begin
                f_loading  <= 1'b1;
                f_load_cnt <= 7'd0;
            end
            // 로딩 진행 중
            else if (f_loading) begin
                if (f_load_cnt == FB_DELAY-1) begin    // 127
                    f_loading    <= 1'b0;
                    fb_load_done <= 1'b1;              // 1사이클 펄스
                end else begin
                    f_load_cnt   <= f_load_cnt + 7'd1;
                end
            end
        end
    end
    //------------------------------------------------------------------------------------------------------


    localparam integer PS_DELAY = WIDTH / 2;

    reg        ps_loading;
    reg [5:0]  ps_cnt;          // 0..63
    reg        psync_run_d;
    reg        data_run_d;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            ps_loading    <= 1'b0;
            ps_cnt        <= 6'd0;
            psync_run_d   <= 1'b0;
            data_run_d    <= 1'b0;
            pb_sync_done  <= 1'b0;
        end else begin
            // 이전 사이클 기록
            psync_run_d  <= ctrl_psync_run;
            data_run_d   <= ctrl_data_run;

            pb_sync_done <= 1'b0;  // 기본값 (펄스용)

            // 트리거: DATA_RUN -> PSYNC 전이
            if (!ps_loading && (ctrl_psync_run && !psync_run_d) && data_run_d) begin
                ps_loading <= 1'b1;
                ps_cnt     <= 6'd0;
            end
            // 카운트 진행
            else if (ps_loading) begin
                if (ps_cnt == PS_DELAY-1) begin
                    ps_loading   <= 1'b0;
                    pb_sync_done <= 1'b1;  // 1사이클 펄스
                end else begin
                    ps_cnt <= ps_cnt + 6'd1;
                end
            end
        end
    end




    //------------------------------------------------------------------------------------------------------
    // Test cases
    //------------------------------------------------------------------------------------------------------
    initial begin
        rstn           = 1'b0;
        q_width        = WIDTH;
        q_height       = HEIGHT;   
        q_channel      = CHANNEL;           // (tiled)채널 수 4로 설정 (실제 타일 수는 16)
        q_channel_out  = CHANNEL_O;
        q_frame_size   = FRAME_SIZE;
        q_start        = 1'b0; 
        pb_sync_done   = 1'b0;
        
        // FILTER
        // FILTER WIDTH=3, INPUT CHANNEL=16, TILED OUTPUT CHANNEL=4
        // # of data fetched from DRAM -> BRAM: 64(=INPUT CHANNEL*TILED OUTPUT CHANNEL) (128 cycle)
        
        #(4*CLK_PERIOD) rstn = 1'b1;
        
        #(100*CLK_PERIOD)
            @(posedge clk) q_start = 1'b1;
        #(4*CLK_PERIOD)
            @(posedge clk) q_start = 1'b0;
    end
    
    initial begin
        wait (layer_done == 1);
        repeat (1000) @(posedge clk);
        $finish;
    end

endmodule
