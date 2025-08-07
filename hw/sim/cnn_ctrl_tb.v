`timescale 1ns / 1ps
`include "controller_params.vh"

module cnn_ctrl_tb;
    parameter W_SIZE        = `W_SIZE;                   // Max width 256
    parameter W_CHANNEL     = `W_CHANNEL;
    parameter W_FRAME_SIZE  = `W_FRAME_SIZE;
    parameter W_DELAY       = `W_DELAY;
    
    parameter WIDTH         = 256;
    parameter HEIGHT        = 256;
    parameter CHANNEL       = 4;
    parameter FRAME_SIZE    = WIDTH * HEIGHT * CHANNEL;
    
    reg                      clk, rstn;
    // buffer synchronization signals
    reg                      q_ifm_buf_done;
    reg                      q_filter_buf_done;

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
    wire                     is_first_chn;
    wire                     is_last_chn;

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
        .o_is_first_row    (is_first_row      ),
        .o_is_last_row     (is_last_row       ),
        .o_is_first_col    (is_first_col      ),
        .o_is_last_col     (is_last_col       ),
        .o_is_first_chn    (is_first_chn      ),
        .o_is_last_chn     (is_last_chn       ),
        .o_row             (row               ),
        .o_col             (col               ),
        .o_chn             (chn               ),  // 추가
        .o_data_count      (data_count        ),
        .o_end_frame       (end_frame         ),

        .o_ifm_buf_req_load(ifm_buf_req_load  ),
        .o_ifm_buf_req_row (ifm_buf_req_row   ),
        .q_pe_done         (q_pe_done         )
    );

    // Clock
    parameter CLK_PERIOD = 10;  // 100MHz
    initial begin
        clk = 1'b1;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
   
    // IFM buffer 
    reg       loading;
    reg [11:0] load_cnt;  // 2048 < 2^12


    always @(posedge clk or negedge rstn) begin 
        q_pe_done <= 0;
        if (row != 0 && ctrl_hsync_cnt == 5) begin 
            q_pe_done <= 1;
        end
    end

    // Reset 및 동작
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            loading        <= 1'b0;
            load_cnt       <= 12'd0;
            q_ifm_buf_done <= 1'b0;
        end

        if (ifm_buf_req_load && !loading) begin
            // 새 로드 요청 감지 → 카운터 시작
            loading        <= 1'b1;
            load_cnt       <= 12'd0;
            q_ifm_buf_done <= 1'b0;
        end
        else if (loading) begin
            // 로딩중
            load_cnt <= load_cnt + 1;

            if (load_cnt == 12'd2047) begin
                // 2048클럭 지연 후 1클럭 펄스 생성
                q_ifm_buf_done <= 1'b1;
                loading        <= 1'b0;
            end else begin
                q_ifm_buf_done <= 1'b0;
            end
        end
        else begin
            // idle 상태
            q_ifm_buf_done <= 1'b0;
        end
    end
    //




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
        q_ifm_buf_done      = 1'b0;
        
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
    end
    
    initial begin
        wait (end_frame == 1);
        repeat (1000) @(posedge clk);
        $finish;
    end

endmodule
