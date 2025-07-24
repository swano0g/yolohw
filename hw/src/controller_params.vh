`ifndef CONTROLLER_PARAMS_VH
`define CONTROLLER_PARAMS_VH


`define K                   3               // kernel size

`define W_DATA              8               // feature map bitwidth
`define W_KERNEL            8               // kernel bitwidth
`define W_PSUM              32              // partial sum bitwidth


`define Tin                 4               // INPUT CHANNEL TILING 
`define Tout                4               // OUTPUT CHANNEL TILING       

`define IFM_DW              `W_DATA * `Tin          // 32
`define FILTER_DW           `W_KERNEL * `K * `K     // 72

// ADDER TREE
`define ADDER_TREE_DELAY    3

// MAC
`define MAC_DELAY           7
`define MAC_W_IN            128
`define MAC_W_OUT           20

// BUFFER MANAGER
`define BM_DATA_DELAY       2               // delay between req to BM <-> data receive

// BUFFER
`define IFM_BUFFER_CNT      4               // # IFM BUFFER 
`define IFM_BUFFER          2               // log2(IFM_BUFFER_CNT)
`define IFM_BUFFER_WIDTH    `IFM_DW
`define IFM_BUFFER_DEPTH    1536

`define FILTER_BUFFER_CNT   `Tout
`define FILTER_BUFFER       2               // log2(FILTER_BUFFER_CNT)
`define FILTER_BUFFER_WIDTH `FILTER_DW
`define FILTER_BUFFER_DEPTH 512

`define PSUM_BUFFER_WI



// CONTROLLER   
`define W_SIZE          10              // MAX WIDTH 256    row, col
`define W_CHANNEL       10              // MAX CHANNEL 512  chn
`define W_FRAME_SIZE    (2 * `W_SIZE + `W_CHANNEL)
`define W_DELAY         14              // MAX DELAY 2048


// PE
`define PE_DELAY        `MAC_DELAY + `ADDER_TREE_DELAY


`endif
