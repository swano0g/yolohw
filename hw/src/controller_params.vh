`ifndef CONTROLLER_PARAMS_VH
`define CONTROLLER_PARAMS_VH

`define Tin                 4               // INPUT CHANNEL TILING 
`define Tout                4               // OUTPUT CHANNEL TILING                                        

// BUFFER
`define IFM_BUFFER_CNT      4               // # IFM BUFFER 
`define IFM_BUFFER          2               // log2(IFM_BUFFER_CNT)
`define IFM_BUFFER_WIDTH    32
`define IFM_BUFFER_DEPTH    1536

`define FILTER_BUFFER_CNT   `Tout
`define FILTER_BUFFER       2               // log2
`define FILTER_BUFFER_WIDTH 72
`define FILTER_BUFFER_DEPTH 512



// CONTROLLER
`define N_PESYNC        2               // PE preload delay      
`define W_SIZE          10              // MAX WIDTH 256    row, col
`define W_CHANNEL       10              // MAX CHANNEL 512  chn
`define W_FRAME_SIZE    (2 * `W_SIZE + `W_CHANNEL)
`define W_DELAY         14              // MAX DELAY 2048




`endif
