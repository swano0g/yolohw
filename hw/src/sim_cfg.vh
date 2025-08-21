`ifndef __SIM_DEBUG_PARAMS_VH__
`define __SIM_DEBUG_PARAMS_VH__

// bm_tb test case

// select test case
// `define TESTCASE_0 1
`define TESTCASE_1 1
// `define TESTCASE_2 1


`ifdef TESTCASE_3
    `define TEST_ROW         3
    `define TEST_COL         16
    `define TEST_CHNIN       16    
    `define TEST_CHNOUT      32
    `define TEST_IFM_PATH  "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/feamap/test3_input_32b.hex"
    `define TEST_FILT_PATH "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/param_packed/test3_param_packed_weight.hex"
    `define TEST_EXP_PATH  "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/expect/test3_output_32b.hex"
`else
    `ifdef TESTCASE_2
        `define TEST_ROW         8
        `define TEST_COL         8
        `define TEST_CHNIN       32    
        `define TEST_CHNOUT      64
        `define TEST_IFM_PATH  "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/feamap/test2_input_32b.hex"
        `define TEST_FILT_PATH "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/param_packed/test2_param_packed_weight.hex"
        `define TEST_EXP_PATH  "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/expect/test2_output_32b.hex"
    `else
        `ifdef TESTCASE_1
            // testcase 1
            // 110 us
            `define TEST_ROW         16
            `define TEST_COL         16
            `define TEST_CHNIN       16    
            `define TEST_CHNOUT      32
            `define TEST_IFM_PATH  "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/feamap/test1_input_32b.hex"
            `define TEST_FILT_PATH "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/param_packed/test1_param_packed_weight.hex"
            `define TEST_AFFINE_PATH "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/param_packed/test1_affine_param.hex"
            `define TEST_EXP_PATH  "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/expect/test1_output_32b.hex"
        `else
            // testcase 0
            // 5 us
            `define TEST_ROW         3
            `define TEST_COL         16
            `define TEST_CHNIN       8    
            `define TEST_CHNOUT      4

            `define TEST_IFM_PATH  "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/feamap/test_small_input_32b.hex"
            `define TEST_FILT_PATH "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/param_packed/test_small_param_packed_weight.hex"
            `define TEST_EXP_PATH  "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/expect/test_small_output_32b.hex"
        `endif
    `endif
`endif
// -----------




// common
`define TEST_T_CHNIN     `TEST_CHNIN / `Tin
`define TEST_T_CHNOUT    `TEST_CHNOUT / `Tout
`define TEST_FRAME_SIZE  `TEST_ROW * `TEST_COL * `TEST_T_CHNIN


`endif