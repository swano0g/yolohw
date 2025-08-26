`ifndef CONTROLLER_PARAMS_VH
`define CONTROLLER_PARAMS_VH


`define K                   3               // kernel size

`define W_DATA              8               // feature map bitwidth
`define W_KERNEL            8               // kernel bitwidth
`define W_PSUM              32              // partial sum bitwidth


`define Tin                 4               // INPUT CHANNEL TILING 
`define Tout                4               // OUTPUT CHANNEL TILING
`define W_Tin               $clog2(`Tin)       
`define W_Tout              $clog2(`Tout)


`define IFM_DW              `W_DATA * `Tin                  // 32
`define OFM_DW              `W_DATA * `Tout                 // 32
`define FILTER_DW           `W_KERNEL * `K * `K             // 72



// ADDER TREE 4
`define ADDER_TREE_DELAY    2

// MAC
`define MAC_DELAY           9               // 5(mul) + 4(adder tree)
`define MAC_W_IN            128
`define MAC_W_OUT           20


// CONTROLLER   
`define W_SIZE              9               // MAX WIDTH 256                    row, col
`define W_CHANNEL           8               // MAX CHANNEL 512 => tiled: 128    chn
`define W_FRAME_SIZE        (`W_SIZE + `W_SIZE + `W_CHANNEL)
`define W_DELAY             14              // MAX DELAY 2048


// PE
`define PE_IFM_FLAT_BW          `IFM_DW * `K            
`define PE_FILTER_FLAT_BW       `FILTER_DW * `Tout   
`define PE_ACCO_FLAT_BW         `W_PSUM * `Tout
`define PE_DELAY                `MAC_DELAY + `ADDER_TREE_DELAY  // 11


// AXI
`define AXI_WIDTH_DA            32



// BUFFER
`define BM_IB_DELAY             3   // index -> data -> reg
`define BM_FB_DELAY             1

// FEATURE MAP BUFFER
`define FM_BUFFER_CNT           2   // IFM, OFM
`define FM_BUFFER_DW            `IFM_DW // 32
`define FM_BUFFER_DEPTH         65536                    // 256KB / 4B
`define FM_BUFFER_AW            $clog2(`FM_BUFFER_DEPTH) // 16

`define FILTER_BUFFER_CNT       `Tout
`define FILTER_BUFFER_DW        `FILTER_DW // 72
`define FILTER_BUFFER_DEPTH     512
`define FILTER_BUFFER_AW        $clog2(`FILTER_BUFFER_DEPTH)

// `define IFM_TOTAL_BUFFER_DW     `IFM_DW // 32
// `define IFM_TOTAL_BUFFER_DEPTH  65536  // 256KB / 4B
// `define IFM_TOTAL_BUFFER_AW     $clog2(`IFM_TOTAL_BUFFER_DEPTH)  // 256KB / 4B


`define IFM_ROW_BUFFER_CNT      `K
`define IFM_ROW_BUFFER_DW       `IFM_DW // 32
`define IFM_ROW_BUFFER_DEPTH    1536    // 6KB  / 4
`define IFM_ROW_BUFFER_AW       $clog2(`IFM_ROW_BUFFER_DEPTH)





// postprocessor
`define PSUM_DW                 `W_PSUM 
`define PSUM_BUFFER_DEPTH       256
`define PSUM_BUFFER_AW          $clog2(`PSUM_BUFFER_DEPTH)

`define BIAS_DW                 32
`define BIAS_BUFFER_DEPTH       512
`define BIAS_BUFFER_AW          $clog2(`BIAS_BUFFER_DEPTH)

`define SCALE_DW                32
`define SCALE_BUFFER_DEPTH      512
`define SCALE_BUFFER_AW         $clog2(`SCALE_BUFFER_DEPTH)

// maxpool
`define MAXPOOL_BUFFER_DW       32
`define MAXPOOL_BUFFER_DEPTH    128
`define MAXPOOL_BUFFER_AW       $clog2(`MAXPOOL_BUFFER_DEPTH)



`endif
