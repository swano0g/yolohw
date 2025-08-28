`ifndef __SIM_MULTI_DEBUG_PARAMS_VH__
`define __SIM_MULTI_DEBUG_PARAMS_VH__



`define TEST_MULTI_MEMORY_16    "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/dram/multilayer_test_memory_16b.hex"
`define TEST_MULTI_EXPECT       "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/expect/multilayer_test_output_32b.hex"


`define DRAM_IFM_OFFSET         0
`define DRAM_FILTER_OFFSET      4096
`define DRAM_BIAS_OFFSET        27136
`define DRAM_SCALE_OFFSET       27520
`define DRAM_OFM_OFFSET         32768


/*
mode    size    input       output     cin  cout
conv	3x3/1	16x16x16    16x16x32    16	32
max 	2x2/2	16x16x32    8x8x32      32	32
*/
`define TEST_L0_LAST_LAYER      0
`define TEST_L0_OFM_SAVE        0
`define TEST_L0_ROUTE_OFFSET    0 
`define TEST_L0_ROUTE_LOC       0 
`define TEST_L0_ROUTE           0 
`define TEST_L0_UPSAMPLE        0
`define TEST_L0_MAXPOOL         1
`define TEST_L0_MAXPOOL_STRIDE  2
`define TEST_L0_CHANNEL_OUT     8
`define TEST_L0_CHANNEL         4
`define TEST_L0_ROW             16
`define TEST_L0_COL             16


/*
mode    size    input       output     cin  cout
conv	3x3/1	8x8x32      8x8x64      32	64
max     2x2/1	8x8x64      8x8x64      64	64
*/
`define TEST_L1_LAST_LAYER      0
`define TEST_L1_OFM_SAVE        0
`define TEST_L1_ROUTE_OFFSET    0 
`define TEST_L1_ROUTE_LOC       0 
`define TEST_L1_ROUTE           0 
`define TEST_L1_UPSAMPLE        0
`define TEST_L1_MAXPOOL         1
`define TEST_L1_MAXPOOL_STRIDE  1
`define TEST_L1_CHANNEL_OUT     16
`define TEST_L1_CHANNEL         8
`define TEST_L1_ROW             8
`define TEST_L1_COL             8


/*
mode    size    input       output     cin  cout
save            8x8x64
*/
`define TEST_L2_LAST_LAYER      1
`define TEST_L2_OFM_SAVE        1
`define TEST_L2_ROUTE_OFFSET    0 
`define TEST_L2_ROUTE_LOC       0 
`define TEST_L2_ROUTE           0 
`define TEST_L2_UPSAMPLE        0
`define TEST_L2_MAXPOOL         0
`define TEST_L2_MAXPOOL_STRIDE  0
`define TEST_L2_CHANNEL_OUT     16      // 상관없음 (last layer)
`define TEST_L2_CHANNEL         16
`define TEST_L2_ROW             8
`define TEST_L2_COL             8



// not use
`define TEST_L3_LAST_LAYER      1
`define TEST_L3_OFM_SAVE        1
`define TEST_L3_ROUTE_OFFSET    0 
`define TEST_L3_ROUTE_LOC       0 
`define TEST_L3_ROUTE           0 
`define TEST_L3_UPSAMPLE        0
`define TEST_L3_MAXPOOL         1
`define TEST_L3_MAXPOOL_STRIDE  2
`define TEST_L3_CHANNEL_OUT     4
`define TEST_L3_CHANNEL         4
`define TEST_L3_ROW             16
`define TEST_L3_COL             16


`define TEST_L4_LAST_LAYER      1
`define TEST_L4_OFM_SAVE        1
`define TEST_L4_ROUTE_OFFSET    0 
`define TEST_L4_ROUTE_LOC       0 
`define TEST_L4_ROUTE           0 
`define TEST_L4_UPSAMPLE        0
`define TEST_L4_MAXPOOL         1
`define TEST_L4_MAXPOOL_STRIDE  2
`define TEST_L4_CHANNEL_OUT     4
`define TEST_L4_CHANNEL         4
`define TEST_L4_ROW             16
`define TEST_L4_COL             16




`endif