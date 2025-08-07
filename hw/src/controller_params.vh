`ifndef CONTROLLER_PARAMS_VH
`define CONTROLLER_PARAMS_VH


`define K                   3               // kernel size

`define W_DATA              8               // feature map bitwidth
`define W_KERNEL            8               // kernel bitwidth
`define W_PSUM              32              // partial sum bitwidth


`define Tin                 4               // INPUT CHANNEL TILING 
`define Tout                4               // OUTPUT CHANNEL TILING
`define W_Tin               2       


`define IFM_DW              `W_DATA * `Tin                  // 32
`define FILTER_DW           `W_KERNEL * `K * `K             // 72


// ADDER TREE 4
`define ADDER_TREE_DELAY    2

// MAC
`define MAC_DELAY           9               // 5(mul) + 4(adder tree)
`define MAC_W_IN            128
`define MAC_W_OUT           20


// CONTROLLER   
`define W_SIZE          10              // MAX WIDTH 256    row, col
`define W_CHANNEL       10              // MAX CHANNEL 512  chn
`define W_FRAME_SIZE    (2 * `W_SIZE + `W_CHANNEL)
`define W_DELAY         14              // MAX DELAY 2048


// PE
`define PE_IFM_FLAT_BW          `IFM_DW * `K            
`define PE_FILTER_FLAT_BW       `FILTER_DW * `Tout   
`define PE_ACCO_FLAT_BW         `W_PSUM * `Tout
`define PE_DELAY                `MAC_DELAY + `ADDER_TREE_DELAY  // 11



// BUFFER
`define BUFFER_ADDRESS_BW   14
//

`define FILTER_BUFFER_CNT       `Tout
`define FILTER_BUFFER_DW        `FILTER_DW // 72
`define FILTER_BUFFER_DEPTH     512
`define FILTER_BUFFER_AW        $clog2(`FILTER_BUFFER_DEPTH)


`define IFM_TOTAL_BUFFER_DW     `IFM_DW // 32
`define IFM_TOTAL_BUFFER_DEPTH  65536  // 256KB / 4B
`define IFM_TOTAL_BUFFER_AW     $clog2(`IFM_TOTAL_BUFFER_DEPTH)  // 256KB / 4B


`define IFM_ROW_BUFFER_CNT      `K
`define IFM_ROW_BUFFER_DW       `IFM_DW // 32
`define IFM_ROW_BUFFER_DEPTH    1536    // 6KB  / 4
`define IFM_ROW_BUFFER_AW       $clog2(`IFM_ROW_BUFFER_DEPTH)

// add psum


`endif
