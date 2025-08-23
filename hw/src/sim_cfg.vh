`ifndef __SIM_DEBUG_PARAMS_VH__
`define __SIM_DEBUG_PARAMS_VH__

// bm_tb test case


`ifdef TESTCASE_2
    `define TEST_ROW         8
    `define TEST_COL         8
    `define TEST_CHNIN       32    
    `define TEST_CHNOUT      64
    `define TEST_IFM_PATH  "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/feamap/test2_input_32b.hex"
    `define TEST_FILT_PATH "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/param_packed/test2_param_packed_weight.hex"
    `define TEST_AFFINE_PATH "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/param_packed/test2_affine_param.hex"
    `define TEST_EXP_PATH  "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/expect/test2_output_32b.hex"
    `define TEST_MEMORY    "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/dram/test2_memory.hex"
    `define TEST_MEMORY_16 "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/dram/test2_memory_16b.hex"
    `define TEST_MEMORY_FILT_OFFSET     2048
    `define TEST_MEMORY_BIAS_OFFSET     20480
    `define TEST_MEMORY_SCALE_OFFSET    20736
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
        `define TEST_MEMORY    "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/dram/test1_memory.hex"
        `define TEST_MEMORY_16 "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/dram/test1_memory_16b.hex"
        `define TEST_MEMORY_FILT_OFFSET     4096
        `define TEST_MEMORY_BIAS_OFFSET     8704
        `define TEST_MEMORY_SCALE_OFFSET    8832

    `else
        // testcase 0
        // 5 us
        `define TEST_ROW         16
        `define TEST_COL         16
        `define TEST_CHNIN       16    
        `define TEST_CHNOUT      32
        `define TEST_IFM_PATH  "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/feamap/test1_input_32b.hex"
        `define TEST_FILT_PATH "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/param_packed/test1_param_packed_weight.hex"
        `define TEST_AFFINE_PATH "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/param_packed/test1_affine_param.hex"
        `define TEST_EXP_PATH  "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/expect/test1_output_32b.hex"
        `define TEST_MEMORY    "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/dram/test1_memory.hex"
        `define TEST_MEMORY_16 "C:/Users/rain0/hw_prj/AIX_source/hw/inout_data/dram/test1_memory_16b.hex"
        `define TEST_MEMORY_FILT_OFFSET     4096
        `define TEST_MEMORY_BIAS_OFFSET     8704
        `define TEST_MEMORY_SCALE_OFFSET    8832
    `endif
`endif
// -----------




// common
`define TEST_T_CHNIN     `TEST_CHNIN / `Tin
`define TEST_T_CHNOUT    `TEST_CHNOUT / `Tout
`define TEST_FRAME_SIZE  `TEST_ROW * `TEST_COL * `TEST_T_CHNIN


`endif