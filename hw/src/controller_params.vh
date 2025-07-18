`ifndef CONTROLLER_PARAMS_VH
`define CONTROLLER_PARAMS_VH

`define Tin             4
`define Tout            4

`define IFM_BUFFER_CNT  4
`define W_IFM_BUFFER    2   // log2(IFM_BUFFER_CNT)

`define W_SIZE          10                    // Max width 256
`define W_CHANNEL       10
`define W_FRAME_SIZE    (2 * `W_SIZE + `W_CHANNEL)
`define W_DELAY         14


`endif
