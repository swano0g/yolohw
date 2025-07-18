`timescale 1ns / 1ps
`include "controller_params.vh"

module cnn_ctrl_tb;
    parameter W_SIZE        = `W_SIZE;                   // Max width 256
    parameter W_CHANNEL     = `W_CHANNEL;
    parameter W_FRAME_SIZE  = `W_FRAME_SIZE;
    parameter W_DELAY       = `W_DELAY;
    
    parameter IFM_BUF_CNT   = `IFM_BUFFER_CNT;       // 4
    parameter W_IFM_BUF     = `W_IFM_BUFFER;         // 2
    
    parameter WIDTH         = 256;
    parameter HEIGHT        = 256;
    parameter CHANNEL       = 4;
    parameter FRAME_SIZE    = WIDTH * HEIGHT * CHANNEL;
    
    reg                      clk, rstn;
    // buffer synchronization signals
    reg  [IFM_BUF_CNT-1:0]   q_ifm_buf_done;
    reg                      q_filter_buf_done;
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

    //-------------------------------------------------
    // Controller (FSM)
    //-------------------------------------------------
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
        .o_row             (row               ),
        .o_col             (col               ),
        .o_chn             (chn               ),  // 추가
        .o_data_count      (data_count        ),
        .o_end_frame       (end_frame         )
    );

    // Clock
    parameter CLK_PERIOD = 10;  // 100MHz
    initial begin
        clk = 1'b1;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    integer row_cnt;

    //------------------------------------------------------------------------------------------------------
    // Test cases
    //------------------------------------------------------------------------------------------------------
    initial begin
        rstn           = 1'b0;
        q_width        = WIDTH;
        q_height       = HEIGHT;   
        q_channel      = CHANNEL;           // (tiled)채널 수 4로 설정 (실제 타일 수는 16)
        q_frame_size   = FRAME_SIZE;
        q_start        = 1'b0; 
        q_filter_buf_done   = 1'b0;
        q_ifm_buf_done      = 4'b0;
        
        // FILTER
        // FILTER WIDTH=3, INPUT CHANNEL=16, TILED OUTPUT CHANNEL=4
        // # of data fetched from DRAM -> BRAM: 64(=INPUT CHANNEL*TILED OUTPUT CHANNEL) (128 cycle)
        
        // IFM
        // WIDTH=256, HEIGHT=256, INPUT CHANNEL=16, TILED INPUT CHANNEL=4
        // # of data fetched from DRAM -> BRAM: 1024(=WIDTH*TILED INPUT CHANNEL) (2048 cycle)
       

        #(4*CLK_PERIOD) rstn = 1'b1;
        
        #(100*CLK_PERIOD)
            @(posedge clk) q_start = 1'b1;
        #(4*CLK_PERIOD)
            @(posedge clk) q_start = 1'b0;
        
        // --------------------------------------- 
        // loading filter buffer...
        repeat(128) @(posedge clk);
        @(posedge clk) q_filter_buf_done = 1;
        @(posedge clk) q_filter_buf_done = 0;
        // ---------------------------------------
        
        
        
        // ---------------------------------------
        // loading ifm buffer...
        
        for (row_cnt = 0; row_cnt < HEIGHT; row_cnt = row_cnt + 1) begin
            repeat (2048) @(posedge clk);
            
            @(posedge clk) q_ifm_buf_done[row_cnt%IFM_BUF_CNT] = 1'b1;
            @(posedge clk) q_ifm_buf_done[row_cnt%IFM_BUF_CNT] = 1'b0;
        end
        // --------------------------------------- 
    end
    
    initial begin
        wait (end_frame == 1);
        repeat (1000) @(posedge clk);
        $finish;
    end

endmodule
