# tools/aix.py
from pathlib import Path

from aixlib.io_hex import *
from aixlib.utils import *
from aixlib.verify import *
from aixlib.packers import *
from aixlib.ops_conv import *
from aixlib.memory import *


def main():
    default_args = Path("repo") / "testcase_args.json"
    params = load_params(default_args)
    
    print("[OK] params loaded")
    print(f" tc_no={params.testcase_no} width={params.width} height={params.height} cin={params.cin} cout={params.cout}")
    print(f" ifm_hex={params.ifm_hex}")
    print(f" filter_hex={params.filter_hex}")
    print(f" bias_hex={params.bias_hex}")
    print(f" scale_hex={params.scale_hex}")
    
    
    print(f" out_ifm_hex={params.out_ifm_hex}")
    print(f" out_weight_hex={params.out_weight_hex}")
    print(f" out_affine_hex={params.out_affine_hex}")
    
    
    ifm_src   = read_32b_hex_lines(params.ifm_hex)
    filt_src  = read_32b_hex_lines(params.filter_hex)
    bias_src  = read_32b_hex_lines(params.bias_hex)
    scale_src = read_32b_hex_lines(params.scale_hex)
    
    
    ifm_data, filt_data, bias_data, scale_data = verify_inputs(params, ifm_src, filt_src, bias_src, scale_src)
    print("[OK] input sizes verified")
    
    filt_72b_data = pack_filter_72b(params, filt_data)
    filt_32b_data = pack_filter_32b(params, filt_data)
    affine_data   = pack_affine(params, bias_data, scale_data)
    
    conv_result   = run_conv(ifm_data, filt_72b_data, params.height, params.width, params.cin, params.cout)
    affine_result = run_affine_from_conv(conv_result, affine_data, params.height, params.width, params.cout)
    maxpool_stride2_result = maxpool_from_affine_words(affine_result, params.height, params.width, params.cout, stride=2)
    maxpool_stride1_result = maxpool_from_affine_words(affine_result, params.height, params.width, params.cout, stride=1)
    
    write_hex_lines(params.out_ifm_hex, ifm_data)
    write_hex_lines(params.out_weight_hex, filt_32b_data)
    write_hex_lines(params.out_affine_hex, affine_data)
    
    write_hex_lines(params.out_conv_result_hex, conv_result)
    write_hex_lines(params.out_affine_result_hex, affine_result)
    write_hex_lines(params.out_maxpool_stride1_result_hex, maxpool_stride1_result)
    write_hex_lines(params.out_maxpool_stride2_result_hex, maxpool_stride2_result)
    
    
    
    # memory builder
    info_mono = memory_builder_monolayer(params, ifm_data, filt_32b_data, bias_data, scale_data)
    write_hex_lines(params.out_memory_hex, info_mono["memory"])
    
    print("[OK] DRAM memory image built")
    print("offset")
    print(f" ifm    : {info_mono['ifm_offset'] * 4}")
    print(f" filter : {info_mono['filter_offset'] * 4}")
    print(f" bias   : {info_mono['bias_offset'] * 4}")
    print(f" scale  : {info_mono['scale_offset'] * 4}")
    print(f" total  : {info_mono['total_lines'] * 4} bytes")
    print(f" total  : {info_mono['total_lines']} lines")
    

def multilayer():
    print("[multilayer testcase builder]")
    print(
"""[layer info]
layer   mode   size    input       output       cin  cout
20      conv	3x3/1	16x16x16    16x16x32    16	32
        max 	2x2/2	16x16x32    8x8x32      32	32
21      conv	3x3/1	8x8x32      8x8x64      32	64
        max     2x2/1	8x8x64      8x8x64      64	64""")
    
    default_args = Path("repo") / "testcase_args.json"
    params = load_params(default_args)
    
    print("[OK] params loaded")
    
    print("layer 20 building...")
    params.width = 16
    params.height = 16
    params.cin = 16
    params.cout = 32
    print(f" width={params.width} height={params.height} cin={params.cin} cout={params.cout}")
    
    ifm_src   = read_32b_hex_lines(params.ifm_hex)
    filt_src  = read_32b_hex_lines(params.filter_hex)
    bias_src  = read_32b_hex_lines(params.bias_hex)
    scale_src = read_32b_hex_lines(params.scale_hex)
    
    
    ifm_data_0, filt_data_0, bias_data_0, scale_data_0 = verify_inputs(params, ifm_src, filt_src, bias_src, scale_src)
    print("[OK] input sizes verified")
    
    filt_72b_data_0 = pack_filter_72b(params, filt_data_0)
    filt_32b_data_0 = pack_filter_32b(params, filt_data_0)
    affine_data_0   = pack_affine(params, bias_data_0, scale_data_0)
    
    conv_result_0   = run_conv(ifm_data_0, filt_72b_data_0, params.height, params.width, params.cin, params.cout)
    affine_result_0 = run_affine_from_conv(conv_result_0, affine_data_0, params.height, params.width, params.cout)
    maxpool_stride2_result_0 = maxpool_from_affine_words(affine_result_0, params.height, params.width, params.cout, stride=2)
    
    print("layer 21 building...")    
    # cutoff portion of used data 
    filt_src_1  = filt_src[params.cout * params.cin * KERNEL_SIZE:]
    bias_src_1  = bias_src[params.cout:]
    scale_src_1 = scale_src[params.cout:]
    
    params.width = 8
    params.height = 8
    params.cin = 32
    params.cout = 64
    print(f" width={params.width} height={params.height} cin={params.cin} cout={params.cout}")
    
    
    
    ifm_data_1, filt_data_1, bias_data_1, scale_data_1 = verify_inputs(params, maxpool_stride2_result_0, filt_src_1, bias_src_1, scale_src_1)
    print("[OK] input sizes verified")
    
    filt_72b_data_1 = pack_filter_72b(params, filt_data_1)
    filt_32b_data_1 = pack_filter_32b(params, filt_data_1)
    affine_data_1   = pack_affine(params, bias_data_1, scale_data_1)
    
    conv_result_1   = run_conv(ifm_data_1, filt_72b_data_1, params.height, params.width, params.cin, params.cout)
    affine_result_1 = run_affine_from_conv(conv_result_1, affine_data_1, params.height, params.width, params.cout)
    maxpool_stride1_result_1 = maxpool_from_affine_words(affine_result_1, params.height, params.width, params.cout, stride=1)
    

    out_multi_result = params.out_expect_dir / f"multilayer_test_output_32b.hex"
    write_hex_lines(out_multi_result, maxpool_stride1_result_1)
    
    
    # write_hex_lines(params.out_ifm_hex, ifm_data)
    # write_hex_lines(params.out_weight_hex, filt_32b_data)
    # write_hex_lines(params.out_affine_hex, affine_data)
    
    # write_hex_lines(params.out_conv_result_hex, conv_result)
    # write_hex_lines(params.out_affine_result_hex, affine_result)
    # write_hex_lines(params.out_maxpool_stride1_result_hex, maxpool_stride1_result)
    # write_hex_lines(params.out_maxpool_stride2_result_hex, maxpool_stride2_result)
    
    
    
    # memory builder
    mem_ifm = ifm_data_0
    mem_filt = filt_32b_data_0 + filt_32b_data_1
    mem_bias = bias_data_0 + bias_data_1
    mem_scale = scale_data_0 + scale_data_1
    
    
    info_multi = memory_builder_monolayer(params, mem_ifm, mem_filt, mem_bias, mem_scale)
    out_multi_mem = params.out_dram_dir / f"multilayer_test_memory_16b.hex"
    write_hex_lines(out_multi_mem, info_multi["memory"])
    
    print("[OK] DRAM memory image built")
    print("offset")
    print(f" ifm    : {info_multi['ifm_offset'] * 4}")
    print(f" filter : {info_multi['filter_offset'] * 4}")
    print(f" bias   : {info_multi['bias_offset'] * 4}")
    print(f" scale  : {info_multi['scale_offset'] * 4}")
    print(f" total  : {info_multi['total_lines'] * 4} bytes")
    print(f" total  : {info_multi['total_lines']} lines")
    
    
    
    
    
if __name__ == "__main__":
    # main()
    multilayer()
