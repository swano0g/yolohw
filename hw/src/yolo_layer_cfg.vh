`ifndef __YOLO_PARAMS_VH__
`define __YOLO_PARAMS_VH__



// localparam  RTE_IFM  = 2'b00,
//             RTE_BUF  = 2'b01,
//             RTE_DRAM = 2'b10;   // not support



`define YOLO_MEMORY_16          "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/yolo/dram/yolo_engine_image.hex"
`define YOLO_EXPECT             "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/yolo/expect/yolo_engine_expect.hex"


`define YOLO_DRAM_IFM_OFFSET    0
`define YOLO_DRAM_FILTER_OFFSET 262144
`define YOLO_DRAM_BIAS_OFFSET   6068800
`define YOLO_DRAM_SCALE_OFFSET  6078016
`define YOLO_DRAM_OFM_OFFSET    8388608
`define YOLO_EXPECT_LINE        15680



`define L00_LAST_LAYER          0
`define L00_OFM_SAVE            0
`define L00_ROUTE_CHN_OFFSET    0
`define L00_ROUTE_OFFSET        0
`define L00_ROUTE_LOC           0
`define L00_ROUTE_LOAD_SWAP     0  
`define L00_ROUTE_LOAD          0 
`define L00_ROUTE_SAVE          0 
`define L00_UPSAMPLE            0
`define L00_MAXPOOL             1
`define L00_MAXPOOL_STRIDE      2
`define L00_CHANNEL_OUT         4
`define L00_CHANNEL             1
`define L00_ROW                 256
`define L00_COL                 256


`define L01_LAST_LAYER          0
`define L01_OFM_SAVE            0
`define L01_ROUTE_CHN_OFFSET    0
`define L01_ROUTE_OFFSET        0 
`define L01_ROUTE_LOC           0 
`define L01_ROUTE_LOAD_SWAP     0  
`define L01_ROUTE_LOAD          0 
`define L01_ROUTE_SAVE          0 
`define L01_UPSAMPLE            0
`define L01_MAXPOOL             1
`define L01_MAXPOOL_STRIDE      2
`define L01_CHANNEL_OUT         8
`define L01_CHANNEL             4
`define L01_ROW                 128
`define L01_COL                 128


`define L02_LAST_LAYER          0
`define L02_OFM_SAVE            0
`define L02_ROUTE_CHN_OFFSET    0
`define L02_ROUTE_OFFSET        0 
`define L02_ROUTE_LOC           0 
`define L02_ROUTE_LOAD_SWAP     0  
`define L02_ROUTE_LOAD          0 
`define L02_ROUTE_SAVE          0 
`define L02_UPSAMPLE            0
`define L02_MAXPOOL             1
`define L02_MAXPOOL_STRIDE      2
`define L02_CHANNEL_OUT         16
`define L02_CHANNEL             8
`define L02_ROW                 64
`define L02_COL                 64


`define L03_LAST_LAYER          0
`define L03_OFM_SAVE            0
`define L03_ROUTE_CHN_OFFSET    0
`define L03_ROUTE_OFFSET        0
`define L03_ROUTE_LOC           0
`define L03_ROUTE_LOAD_SWAP     0  
`define L03_ROUTE_LOAD          0
`define L03_ROUTE_SAVE          0
`define L03_UPSAMPLE            0
`define L03_MAXPOOL             1
`define L03_MAXPOOL_STRIDE      2
`define L03_CHANNEL_OUT         32
`define L03_CHANNEL             16
`define L03_ROW                 32
`define L03_COL                 32


`define L04_LAST_LAYER          0
`define L04_OFM_SAVE            0
`define L04_ROUTE_CHN_OFFSET    0
`define L04_ROUTE_OFFSET        32768 
`define L04_ROUTE_LOC           RTE_IFM
`define L04_ROUTE_LOAD_SWAP     0  
`define L04_ROUTE_LOAD          0 
`define L04_ROUTE_SAVE          1 
`define L04_UPSAMPLE            0
`define L04_MAXPOOL             1
`define L04_MAXPOOL_STRIDE      2
`define L04_CHANNEL_OUT         64
`define L04_CHANNEL             32
`define L04_ROW                 16
`define L04_COL                 16


`define L05_LAST_LAYER          0
`define L05_OFM_SAVE            0
`define L05_ROUTE_CHN_OFFSET    0
`define L05_ROUTE_OFFSET        0 
`define L05_ROUTE_LOC           0 
`define L05_ROUTE_LOAD_SWAP     0  
`define L05_ROUTE_LOAD          0 
`define L05_ROUTE_SAVE          0 
`define L05_UPSAMPLE            0
`define L05_MAXPOOL             1
`define L05_MAXPOOL_STRIDE      1
`define L05_CHANNEL_OUT         128
`define L05_CHANNEL             64
`define L05_ROW                 8
`define L05_COL                 8


`define L06_LAST_LAYER          0
`define L06_OFM_SAVE            0
`define L06_ROUTE_CHN_OFFSET    0
`define L06_ROUTE_OFFSET        0 
`define L06_ROUTE_LOC           RTE_BUF 
`define L06_ROUTE_LOAD_SWAP     0  
`define L06_ROUTE_LOAD          0 
`define L06_ROUTE_SAVE          1 
`define L06_UPSAMPLE            0
`define L06_MAXPOOL             0
`define L06_MAXPOOL_STRIDE      0
`define L06_CHANNEL_OUT         64
`define L06_CHANNEL             128
`define L06_ROW                 8
`define L06_COL                 8


`define L07_LAST_LAYER          0
`define L07_OFM_SAVE            0
`define L07_ROUTE_CHN_OFFSET    0
`define L07_ROUTE_OFFSET        0 
`define L07_ROUTE_LOC           0 
`define L07_ROUTE_LOAD_SWAP     0  
`define L07_ROUTE_LOAD          0 
`define L07_ROUTE_SAVE          0 
`define L07_UPSAMPLE            0
`define L07_MAXPOOL             0
`define L07_MAXPOOL_STRIDE      0
`define L07_CHANNEL_OUT         128
`define L07_CHANNEL             64
`define L07_ROW                 8
`define L07_COL                 8


`define L08_LAST_LAYER          0
`define L08_OFM_SAVE            0
`define L08_ROUTE_CHN_OFFSET    0
`define L08_ROUTE_OFFSET        0 
`define L08_ROUTE_LOC           0 
`define L08_ROUTE_LOAD_SWAP     0  
`define L08_ROUTE_LOAD          0 
`define L08_ROUTE_SAVE          0 
`define L08_UPSAMPLE            0
`define L08_MAXPOOL             0
`define L08_MAXPOOL_STRIDE      0
`define L08_CHANNEL_OUT         49
`define L08_CHANNEL             128
`define L08_ROW                 8
`define L08_COL                 8


`define L09_LAST_LAYER          0
`define L09_OFM_SAVE            1
`define L09_ROUTE_CHN_OFFSET    0
`define L09_ROUTE_OFFSET        0 
`define L09_ROUTE_LOC           0 
`define L09_ROUTE_LOAD_SWAP     0  
`define L09_ROUTE_LOAD          0 
`define L09_ROUTE_SAVE          0 
`define L09_UPSAMPLE            0
`define L09_MAXPOOL             0
`define L09_MAXPOOL_STRIDE      0
`define L09_CHANNEL_OUT         49
`define L09_CHANNEL             49
`define L09_ROW                 8
`define L09_COL                 8


`define L10_LAST_LAYER          0
`define L10_OFM_SAVE            0
`define L10_ROUTE_CHN_OFFSET    0
`define L10_ROUTE_OFFSET        0 
`define L10_ROUTE_LOC           RTE_BUF 
`define L10_ROUTE_LOAD_SWAP     0  
`define L10_ROUTE_LOAD          1 
`define L10_ROUTE_SAVE          0 
`define L10_UPSAMPLE            0
`define L10_MAXPOOL             0
`define L10_MAXPOOL_STRIDE      0
`define L10_CHANNEL_OUT         64
`define L10_CHANNEL             64
`define L10_ROW                 8
`define L10_COL                 8


`define L11_LAST_LAYER          0
`define L11_OFM_SAVE            0
`define L11_ROUTE_CHN_OFFSET    0
`define L11_ROUTE_OFFSET        0 
`define L11_ROUTE_LOC           0 
`define L11_ROUTE_LOAD_SWAP     0  
`define L11_ROUTE_LOAD          0 
`define L11_ROUTE_SAVE          0 
`define L11_UPSAMPLE            0
`define L11_MAXPOOL             0
`define L11_MAXPOOL_STRIDE      0
`define L11_CHANNEL_OUT         32
`define L11_CHANNEL             64
`define L11_ROW                 8
`define L11_COL                 8


`define L12_LAST_LAYER          0
`define L12_OFM_SAVE            0
`define L12_ROUTE_CHN_OFFSET    0
`define L12_ROUTE_OFFSET        0 
`define L12_ROUTE_LOC           0 
`define L12_ROUTE_LOAD_SWAP     0  
`define L12_ROUTE_LOAD          0 
`define L12_ROUTE_SAVE          0 
`define L12_UPSAMPLE            1
`define L12_MAXPOOL             0
`define L12_MAXPOOL_STRIDE      0
`define L12_CHANNEL_OUT         96     // 384 / 4
`define L12_CHANNEL             32
`define L12_ROW                 8
`define L12_COL                 8


`define L13_LAST_LAYER          0
`define L13_OFM_SAVE            0
`define L13_ROUTE_CHN_OFFSET    32
`define L13_ROUTE_OFFSET        32768 
`define L13_ROUTE_LOC           RTE_IFM 
`define L13_ROUTE_LOAD_SWAP     0  
`define L13_ROUTE_LOAD          1 
`define L13_ROUTE_SAVE          0 
`define L13_UPSAMPLE            0
`define L13_MAXPOOL             0
`define L13_MAXPOOL_STRIDE      0
`define L13_CHANNEL_OUT         96
`define L13_CHANNEL             64
`define L13_ROW                 16
`define L13_COL                 16


`define L14_LAST_LAYER          0
`define L14_OFM_SAVE            0
`define L14_ROUTE_CHN_OFFSET    0
`define L14_ROUTE_OFFSET        0 
`define L14_ROUTE_LOC           0 
`define L14_ROUTE_LOAD_SWAP     0  
`define L14_ROUTE_LOAD          0 
`define L14_ROUTE_SAVE          0 
`define L14_UPSAMPLE            0
`define L14_MAXPOOL             0
`define L14_MAXPOOL_STRIDE      0
`define L14_CHANNEL_OUT         49
`define L14_CHANNEL             96
`define L14_ROW                 16
`define L14_COL                 16


`define L15_LAST_LAYER          1
`define L15_OFM_SAVE            1
`define L15_ROUTE_CHN_OFFSET    0
`define L15_ROUTE_OFFSET        0 
`define L15_ROUTE_LOC           0 
`define L15_ROUTE_LOAD_SWAP     0  
`define L15_ROUTE_LOAD          0 
`define L15_ROUTE_SAVE          0 
`define L15_UPSAMPLE            0
`define L15_MAXPOOL             0
`define L15_MAXPOOL_STRIDE      0
`define L15_CHANNEL_OUT         49
`define L15_CHANNEL             49
`define L15_ROW                 16
`define L15_COL                 16

`endif