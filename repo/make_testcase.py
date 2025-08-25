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
    
    write_hex_lines(params.out_ifm_hex, ifm_data)
    write_hex_lines(params.out_weight_hex, filt_32b_data)
    write_hex_lines(params.out_affine_hex, affine_data)
    
    write_hex_lines(params.out_conv_result_hex, conv_result)
    write_hex_lines(params.out_affine_result_hex, affine_result)
    
    
    # memory builder
    info_mono = memory_builder_monolayer(params, ifm_data, filt_32b_data, affine_data)
    
    print("[OK] DRAM memory image built")
    print("offset")
    print(f" ifm    : {info_mono['ifm_offset'] * 4}")
    print(f" filter : {info_mono['filter_offset'] * 4}")
    print(f" bias   : {info_mono['bias_offset'] * 4}")
    print(f" scale  : {info_mono['scale_offset'] * 4}")
    print(f" total  : {info_mono['total_lines'] * 4} bytes")
    print(f" total  : {info_mono['total_lines']} lines")
    
    maxpool_result = maxpool_from_affine_words(affine_result, params.height, params.width, params.cout)
    write_hex_lines(params.out_maxpool_result_hex, maxpool_result)
    
    
if __name__ == "__main__":
    main()
