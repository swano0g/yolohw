`ifndef __SIM_MULTI_DEBUG_PARAMS_VH__
`define __SIM_MULTI_DEBUG_PARAMS_VH__



localparam  RTE_IFM  = 2'b00,
            RTE_BUF  = 2'b01,
            RTE_DRAM = 2'b10;   // not support


// `define MULTI_TC_0 1
// `define MULTI_TC_1 1
`define MULTI_TC_2 1


`ifdef MULTI_TC_2
    `define TEST_MULTI_MEMORY_16    "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/dram/multilayer_test2_memory_16b.hex"
    `define TEST_MULTI_EXPECT       "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/expect/multilayer_test2_output_32b.hex"


    `define DRAM_IFM_OFFSET         0
    `define DRAM_FILTER_OFFSET      2048
    `define DRAM_BIAS_OFFSET        7808
    `define DRAM_SCALE_OFFSET       8000
    `define DRAM_OFM_OFFSET         32768
    `define EXPECT_LINE             1024


    /*
    mode    size    input       output     cin  cout
    conv	3x3/1	16x16x8     16x16x16     8	16  -> route
    */
    `define TEST_L0_LAST_LAYER      0
    `define TEST_L0_OFM_SAVE        0
    `define TEST_L0_ROUTE_CHN_OFFSET 0
    `define TEST_L0_ROUTE_OFFSET    32768
    `define TEST_L0_ROUTE_LOC       RTE_IFM 
    `define TEST_L0_ROUTE_LOAD_SWAP 0      // route_load_swap
    `define TEST_L0_ROUTE_LOAD      0      // route_load
    `define TEST_L0_ROUTE_SAVE      1      // route_save
    `define TEST_L0_UPSAMPLE        0
    `define TEST_L0_MAXPOOL         0
    `define TEST_L0_MAXPOOL_STRIDE  0
    `define TEST_L0_CHANNEL_OUT     4
    `define TEST_L0_CHANNEL         2
    `define TEST_L0_ROW             16
    `define TEST_L0_COL             16

    /*
    mode    size    input       output     cin  cout
    conv	3x3/1	16x16x16    16x16x8     16	8
    max 	2x2/2	16x16x8      8x8x8      8	8
    */
    `define TEST_L1_LAST_LAYER      0
    `define TEST_L1_OFM_SAVE        0
    `define TEST_L1_ROUTE_CHN_OFFSET 0
    `define TEST_L1_ROUTE_OFFSET    0 
    `define TEST_L1_ROUTE_LOC       0 
    `define TEST_L1_ROUTE_LOAD_SWAP 0      // route_load_swap
    `define TEST_L1_ROUTE_LOAD      0      // route_load
    `define TEST_L1_ROUTE_SAVE      0      // route_save
    `define TEST_L1_UPSAMPLE        0
    `define TEST_L1_MAXPOOL         1
    `define TEST_L1_MAXPOOL_STRIDE  2
    `define TEST_L1_CHANNEL_OUT     2
    `define TEST_L1_CHANNEL         4
    `define TEST_L1_ROW             16
    `define TEST_L1_COL             16


    /*
    mode    size    input       output     cin  cout
    upsample        8x8x8      16x16x8(24)   8  24
    */
    `define TEST_L2_LAST_LAYER      0
    `define TEST_L2_OFM_SAVE        0
    `define TEST_L2_ROUTE_CHN_OFFSET 0
    `define TEST_L2_ROUTE_OFFSET    0 
    `define TEST_L2_ROUTE_LOC       0 
    `define TEST_L2_ROUTE_LOAD_SWAP 0      // route_load_swap
    `define TEST_L2_ROUTE_LOAD      0      // route_load
    `define TEST_L2_ROUTE_SAVE      0      // route_save
    `define TEST_L2_UPSAMPLE        1
    `define TEST_L2_MAXPOOL         0
    `define TEST_L2_MAXPOOL_STRIDE  0
    `define TEST_L2_CHANNEL_OUT     6
    `define TEST_L2_CHANNEL         2
    `define TEST_L2_ROW             8
    `define TEST_L2_COL             8

    /*
    mode    size    input       output     cin  cout
    route {L2,L0}               16x16x24
    */
    `define TEST_L3_LAST_LAYER      0
    `define TEST_L3_OFM_SAVE        0
    `define TEST_L3_ROUTE_CHN_OFFSET 2
    `define TEST_L3_ROUTE_OFFSET    32768
    `define TEST_L3_ROUTE_LOC       RTE_IFM
    `define TEST_L3_ROUTE_LOAD_SWAP 0      // route_load_swap
    `define TEST_L3_ROUTE_LOAD      1      // route_load
    `define TEST_L3_ROUTE_SAVE      0      // route_save
    `define TEST_L3_UPSAMPLE        0
    `define TEST_L3_MAXPOOL         0
    `define TEST_L3_MAXPOOL_STRIDE  0
    `define TEST_L3_CHANNEL_OUT     6
    `define TEST_L3_CHANNEL         4
    `define TEST_L3_ROW             16
    `define TEST_L3_COL             16

    /*
    mode    size    input       output     cin  cout
    conv	3x3/1	16x16x24    16x16x16    24	16
    */
    `define TEST_L4_LAST_LAYER      0
    `define TEST_L4_OFM_SAVE        0
    `define TEST_L4_ROUTE_CHN_OFFSET 0
    `define TEST_L4_ROUTE_OFFSET    0 
    `define TEST_L4_ROUTE_LOC       0 
    `define TEST_L4_ROUTE_LOAD_SWAP 0      // route_load_swap
    `define TEST_L4_ROUTE_LOAD      0      // route_load
    `define TEST_L4_ROUTE_SAVE      0      // route_save
    `define TEST_L4_UPSAMPLE        0
    `define TEST_L4_MAXPOOL         0
    `define TEST_L4_MAXPOOL_STRIDE  0
    `define TEST_L4_CHANNEL_OUT     4
    `define TEST_L4_CHANNEL         6
    `define TEST_L4_ROW             16
    `define TEST_L4_COL             16

    /*
    mode    size    input       output     cin  cout
    save		    16x16x16   
    */
    `define TEST_L5_LAST_LAYER      1
    `define TEST_L5_OFM_SAVE        1
    `define TEST_L5_ROUTE_CHN_OFFSET 0
    `define TEST_L5_ROUTE_OFFSET    0 
    `define TEST_L5_ROUTE_LOC       0 
    `define TEST_L5_ROUTE_LOAD_SWAP 0      // route_load_swap
    `define TEST_L5_ROUTE_LOAD      0      // route_load
    `define TEST_L5_ROUTE_SAVE      0      // route_save
    `define TEST_L5_UPSAMPLE        0
    `define TEST_L5_MAXPOOL         0
    `define TEST_L5_MAXPOOL_STRIDE  0
    `define TEST_L5_CHANNEL_OUT     4      // dont care
    `define TEST_L5_CHANNEL         4
    `define TEST_L5_ROW             16
    `define TEST_L5_COL             16
`else
`ifdef MULTI_TC_1
    `define TEST_MULTI_MEMORY_16    "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/dram/multilayer_test1_memory_16b.hex"
    `define TEST_MULTI_EXPECT       "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/expect/multilayer_test1_output_32b.hex"


    `define DRAM_IFM_OFFSET         0
    `define DRAM_FILTER_OFFSET      512
    `define DRAM_BIAS_OFFSET        5120
    `define DRAM_SCALE_OFFSET       5312
    `define DRAM_OFM_OFFSET         32768
    `define EXPECT_LINE             384


    /*
    mode    size    input       output     cin  cout
    conv	3x3/1	8x8x8       8x8x16       8	16  -> route      
    max 	2x2/1	8x8x16      8x8x16      16	16
    */
    `define TEST_L0_LAST_LAYER      0
    `define TEST_L0_OFM_SAVE        0
    `define TEST_L0_ROUTE_CHN_OFFSET 0
    `define TEST_L0_ROUTE_OFFSET    0 
    `define TEST_L0_ROUTE_LOC       RTE_BUF 
    `define TEST_L0_ROUTE_LOAD_SWAP 0      // route_load_swap
    `define TEST_L0_ROUTE_LOAD      0      // route_load
    `define TEST_L0_ROUTE_SAVE      1      // route_save
    `define TEST_L0_UPSAMPLE        0
    `define TEST_L0_MAXPOOL         1
    `define TEST_L0_MAXPOOL_STRIDE  1
    `define TEST_L0_CHANNEL_OUT     4
    `define TEST_L0_CHANNEL         2
    `define TEST_L0_ROW             8
    `define TEST_L0_COL             8


    /*
    mode    size    input       output     cin  cout
    conv	3x3/1	8x8x16      8x8x16      16	16
    */
    `define TEST_L1_LAST_LAYER      0
    `define TEST_L1_OFM_SAVE        0
    `define TEST_L1_ROUTE_CHN_OFFSET 0
    `define TEST_L1_ROUTE_OFFSET    0 
    `define TEST_L1_ROUTE_LOC       0 
    `define TEST_L1_ROUTE_LOAD_SWAP 0      // route_load_swap
    `define TEST_L1_ROUTE_LOAD      0      // route_load
    `define TEST_L1_ROUTE_SAVE      0      // route_save
    `define TEST_L1_UPSAMPLE        0
    `define TEST_L1_MAXPOOL         0
    `define TEST_L1_MAXPOOL_STRIDE  0
    `define TEST_L1_CHANNEL_OUT     4
    `define TEST_L1_CHANNEL         4
    `define TEST_L1_ROW             8
    `define TEST_L1_COL             8


    /*
    mode    size    input       output     cin  cout
    save            8x8x16
    */
    `define TEST_L2_LAST_LAYER      0
    `define TEST_L2_OFM_SAVE        1
    `define TEST_L2_ROUTE_CHN_OFFSET 0
    `define TEST_L2_ROUTE_OFFSET    0 
    `define TEST_L2_ROUTE_LOC       0 
    `define TEST_L2_ROUTE_LOAD_SWAP 0      // route_load_swap
    `define TEST_L2_ROUTE_LOAD      0      // route_load
    `define TEST_L2_ROUTE_SAVE      0      // route_save
    `define TEST_L2_UPSAMPLE        0
    `define TEST_L2_MAXPOOL         0
    `define TEST_L2_MAXPOOL_STRIDE  0
    `define TEST_L2_CHANNEL_OUT     4      // 상관없음 (dram save)
    `define TEST_L2_CHANNEL         4
    `define TEST_L2_ROW             8
    `define TEST_L2_COL             8

    /*
    mode    size    input       output     cin  cout
    route L0        8x8x16      8x8x16
    */
    `define TEST_L3_LAST_LAYER      0
    `define TEST_L3_OFM_SAVE        0
    `define TEST_L3_ROUTE_CHN_OFFSET 0
    `define TEST_L3_ROUTE_OFFSET    0 
    `define TEST_L3_ROUTE_LOC       RTE_BUF 
    `define TEST_L3_ROUTE_LOAD_SWAP 0      // route_load_swap
    `define TEST_L3_ROUTE_LOAD      1      // route_load
    `define TEST_L3_ROUTE_SAVE      0      // route_save
    `define TEST_L3_UPSAMPLE        0
    `define TEST_L3_MAXPOOL         0
    `define TEST_L3_MAXPOOL_STRIDE  0
    `define TEST_L3_CHANNEL_OUT     4
    `define TEST_L3_CHANNEL         4
    `define TEST_L3_ROW             8
    `define TEST_L3_COL             8

    /*
    mode    size    input       output     cin  cout
    conv	3x3/1	8x8x16      8x8x8       16	8
    */
    `define TEST_L4_LAST_LAYER      0
    `define TEST_L4_OFM_SAVE        0
    `define TEST_L4_ROUTE_CHN_OFFSET 0
    `define TEST_L4_ROUTE_OFFSET    0 
    `define TEST_L4_ROUTE_LOC       0 
    `define TEST_L4_ROUTE_LOAD_SWAP 0      // route_load_swap
    `define TEST_L4_ROUTE_LOAD      0      // route_load
    `define TEST_L4_ROUTE_SAVE      0      // route_save
    `define TEST_L4_UPSAMPLE        0
    `define TEST_L4_MAXPOOL         0
    `define TEST_L4_MAXPOOL_STRIDE  0
    `define TEST_L4_CHANNEL_OUT     2
    `define TEST_L4_CHANNEL         4
    `define TEST_L4_ROW             8
    `define TEST_L4_COL             8

    /*
    mode    size    input       output     cin  cout
    save		    8x8x8   
    */
    `define TEST_L5_LAST_LAYER      1
    `define TEST_L5_OFM_SAVE        1
    `define TEST_L5_ROUTE_CHN_OFFSET 0
    `define TEST_L5_ROUTE_OFFSET    0 
    `define TEST_L5_ROUTE_LOC       0 
    `define TEST_L5_ROUTE_LOAD_SWAP 0      // route_load_swap
    `define TEST_L5_ROUTE_LOAD      0      // route_load
    `define TEST_L5_ROUTE_SAVE      0      // route_save
    `define TEST_L5_UPSAMPLE        0
    `define TEST_L5_MAXPOOL         0
    `define TEST_L5_MAXPOOL_STRIDE  0
    `define TEST_L5_CHANNEL_OUT     2
    `define TEST_L5_CHANNEL         2
    `define TEST_L5_ROW             8
    `define TEST_L5_COL             8
`else
`ifdef MULTI_TC_0
    `define TEST_MULTI_MEMORY_16    "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/dram/multilayer_test_memory_16b.hex"
    `define TEST_MULTI_EXPECT       "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/expect/multilayer_test_output_32b.hex"


    `define DRAM_IFM_OFFSET         0
    `define DRAM_FILTER_OFFSET      4096
    `define DRAM_BIAS_OFFSET        27136
    `define DRAM_SCALE_OFFSET       27520
    `define DRAM_OFM_OFFSET         32768
    `define EXPECT_LINE             1024


    /*
    mode    size    input       output     cin  cout
    conv	3x3/1	16x16x16    16x16x32    16	32
    max 	2x2/2	16x16x32    8x8x32      32	32
    */
    `define TEST_L0_LAST_LAYER      0
    `define TEST_L0_OFM_SAVE        0
    `define TEST_L0_ROUTE_CHN_OFFSET 0
    `define TEST_L0_ROUTE_OFFSET    0 
    `define TEST_L0_ROUTE_LOC       0 
    `define TEST_L0_ROUTE_LOAD_SWAP 0      // route_load_swap
    `define TEST_L0_ROUTE_LOAD      0      // route_load
    `define TEST_L0_ROUTE_SAVE      0      // route_save
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
    `define TEST_L1_ROUTE_CHN_OFFSET 0
    `define TEST_L1_ROUTE_OFFSET    0 
    `define TEST_L1_ROUTE_LOC       0 
    `define TEST_L1_ROUTE_LOAD_SWAP 0      // route_load_swap
    `define TEST_L1_ROUTE_LOAD      0      // route_load
    `define TEST_L1_ROUTE_SAVE      0      // route_save
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
    `define TEST_L2_ROUTE_CHN_OFFSET 0
    `define TEST_L2_ROUTE_OFFSET    0 
    `define TEST_L2_ROUTE_LOC       0 
    `define TEST_L2_ROUTE_LOAD_SWAP 0      // route_load_swap
    `define TEST_L2_ROUTE_LOAD      0      // route_load
    `define TEST_L2_ROUTE_SAVE      0      // route_save
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
    `define TEST_L3_ROUTE_CHN_OFFSET 0
    `define TEST_L3_ROUTE_OFFSET    0 
    `define TEST_L3_ROUTE_LOC       0 
    `define TEST_L3_ROUTE_LOAD_SWAP 0      // route_load_swap
    `define TEST_L3_ROUTE_LOAD      0      // route_load
    `define TEST_L3_ROUTE_SAVE      0      // route_save
    `define TEST_L3_UPSAMPLE        0
    `define TEST_L3_MAXPOOL         1
    `define TEST_L3_MAXPOOL_STRIDE  2
    `define TEST_L3_CHANNEL_OUT     4
    `define TEST_L3_CHANNEL         4
    `define TEST_L3_ROW             16
    `define TEST_L3_COL             16


    `define TEST_L4_LAST_LAYER      1
    `define TEST_L4_OFM_SAVE        1
    `define TEST_L4_ROUTE_CHN_OFFSET 0
    `define TEST_L4_ROUTE_OFFSET    0 
    `define TEST_L4_ROUTE_LOC       0 
    `define TEST_L4_ROUTE_LOAD_SWAP 0      // route_load_swap
    `define TEST_L4_ROUTE_LOAD      0      // route_load
    `define TEST_L4_ROUTE_SAVE      0      // route_save
    `define TEST_L4_UPSAMPLE        0
    `define TEST_L4_MAXPOOL         1
    `define TEST_L4_MAXPOOL_STRIDE  2
    `define TEST_L4_CHANNEL_OUT     4
    `define TEST_L4_CHANNEL         4
    `define TEST_L4_ROW             16
    `define TEST_L4_COL             16


    `define TEST_L5_LAST_LAYER      1
    `define TEST_L5_OFM_SAVE        1
    `define TEST_L5_ROUTE_CHN_OFFSET 0
    `define TEST_L5_ROUTE_OFFSET    0 
    `define TEST_L5_ROUTE_LOC       0 
    `define TEST_L5_ROUTE_LOAD_SWAP 0      // route_load_swap
    `define TEST_L5_ROUTE_LOAD      0      // route_load
    `define TEST_L5_ROUTE_SAVE      0      // route_save
    `define TEST_L5_UPSAMPLE        0
    `define TEST_L5_MAXPOOL         0
    `define TEST_L5_MAXPOOL_STRIDE  0
    `define TEST_L5_CHANNEL_OUT     2
    `define TEST_L5_CHANNEL         2
    `define TEST_L5_ROW             8
    `define TEST_L5_COL             8
`else
    `define TEST_MULTI_MEMORY_16    "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/dram/multilayer_test_memory_16b.hex"
    `define TEST_MULTI_EXPECT       "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/expect/multilayer_test_output_32b.hex"


    `define DRAM_IFM_OFFSET         0
    `define DRAM_FILTER_OFFSET      4096
    `define DRAM_BIAS_OFFSET        27136
    `define DRAM_SCALE_OFFSET       27520
    `define DRAM_OFM_OFFSET         32768
    `define EXPECT_LINE             1024


    /*
    mode    size    input       output     cin  cout
    conv	3x3/1	16x16x16    16x16x32    16	32
    max 	2x2/2	16x16x32    8x8x32      32	32
    */
    `define TEST_L0_LAST_LAYER      0
    `define TEST_L0_OFM_SAVE        0
    `define TEST_L0_ROUTE_CHN_OFFSET 0
    `define TEST_L0_ROUTE_OFFSET    0 
    `define TEST_L0_ROUTE_LOC       0 
    `define TEST_L0_ROUTE_LOAD_SWAP 0      // route_load_swap
    `define TEST_L0_ROUTE_LOAD      0      // route_load
    `define TEST_L0_ROUTE_SAVE      0      // route_save
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
    `define TEST_L1_ROUTE_CHN_OFFSET 0
    `define TEST_L1_ROUTE_OFFSET    0 
    `define TEST_L1_ROUTE_LOC       0 
    `define TEST_L1_ROUTE_LOAD_SWAP 0      // route_load_swap
    `define TEST_L1_ROUTE_LOAD      0      // route_load
    `define TEST_L1_ROUTE_SAVE      0      // route_save
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
    `define TEST_L2_ROUTE_CHN_OFFSET 0
    `define TEST_L2_ROUTE_OFFSET    0 
    `define TEST_L2_ROUTE_LOC       0 
    `define TEST_L2_ROUTE_LOAD_SWAP 0      // route_load_swap
    `define TEST_L2_ROUTE_LOAD      0      // route_load
    `define TEST_L2_ROUTE_SAVE      0      // route_save
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
    `define TEST_L3_ROUTE_CHN_OFFSET 0
    `define TEST_L3_ROUTE_OFFSET    0 
    `define TEST_L3_ROUTE_LOC       0 
    `define TEST_L3_ROUTE_LOAD_SWAP 0      // route_load_swap
    `define TEST_L3_ROUTE_LOAD      0      // route_load
    `define TEST_L3_ROUTE_SAVE      0      // route_save
    `define TEST_L3_UPSAMPLE        0
    `define TEST_L3_MAXPOOL         1
    `define TEST_L3_MAXPOOL_STRIDE  2
    `define TEST_L3_CHANNEL_OUT     4
    `define TEST_L3_CHANNEL         4
    `define TEST_L3_ROW             16
    `define TEST_L3_COL             16


    `define TEST_L4_LAST_LAYER      1
    `define TEST_L4_OFM_SAVE        1
    `define TEST_L4_ROUTE_CHN_OFFSET 0
    `define TEST_L4_ROUTE_OFFSET    0 
    `define TEST_L4_ROUTE_LOC       0 
    `define TEST_L4_ROUTE_LOAD_SWAP 0      // route_load_swap
    `define TEST_L4_ROUTE_LOAD      0      // route_load
    `define TEST_L4_ROUTE_SAVE      0      // route_save
    `define TEST_L4_UPSAMPLE        0
    `define TEST_L4_MAXPOOL         1
    `define TEST_L4_MAXPOOL_STRIDE  2
    `define TEST_L4_CHANNEL_OUT     4
    `define TEST_L4_CHANNEL         4
    `define TEST_L4_ROW             16
    `define TEST_L4_COL             16


    `define TEST_L5_LAST_LAYER      1
    `define TEST_L5_OFM_SAVE        1
    `define TEST_L5_ROUTE_CHN_OFFSET 0
    `define TEST_L5_ROUTE_OFFSET    0 
    `define TEST_L5_ROUTE_LOC       0 
    `define TEST_L5_ROUTE_LOAD_SWAP 0      // route_load_swap
    `define TEST_L5_ROUTE_LOAD      0      // route_load
    `define TEST_L5_ROUTE_SAVE      0      // route_save
    `define TEST_L5_UPSAMPLE        0
    `define TEST_L5_MAXPOOL         0
    `define TEST_L5_MAXPOOL_STRIDE  0
    `define TEST_L5_CHANNEL_OUT     2
    `define TEST_L5_CHANNEL         2
    `define TEST_L5_ROW             8
    `define TEST_L5_COL             8
`endif
`endif
`endif


`endif