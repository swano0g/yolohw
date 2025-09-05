from pathlib import Path

from aixlib.io_hex import *
from aixlib.utils import *
from aixlib.verify import *
from aixlib.packers import *
from aixlib.ops_conv import *
from aixlib.memory import *



L00_width   = 256
L00_height  = 256
L00_cin     = 4     # 3->4 padding
L00_cout    = 16


L01_width   = 128
L01_height  = 128
L01_cin     = 16
L01_cout    = 32


L02_width   = 64
L02_height  = 64
L02_cin     = 32
L02_cout    = 64


L03_width   = 32
L03_height  = 32
L03_cin     = 64 
L03_cout    = 128


L04_width   = 16
L04_height  = 16
L04_cin     = 128
L04_cout    = 256


L05_width   = 8
L05_height  = 8
L05_cin     = 256
L05_cout    = 512


L06_width   = 8
L06_height  = 8
L06_cin     = 512
L06_cout    = 256


L07_width   = 8
L07_height  = 8
L07_cin     = 256 
L07_cout    = 512


L08_width   = 8
L08_height  = 8
L08_cin     = 512 
L08_cout    = 196   # 195 -> 196 padding    


L11_width   = 8
L11_height  = 8
L11_cin     = 256 
L11_cout    = 128


L14_width   = 16
L14_height  = 16
L14_cin     = 384 
L14_cout    = 196   # 195 -> 196 padding


def pad_filter_cin_to_mult4(filter_src: list[str], Cin: int, Cout: int, K: int = 3) -> list[str]:
    """
    Cin 채널 수가 4의 배수가 되도록 zero-padding
    """
    
    padded_Cin = ((Cin + 3) // 4) * 4
    out: list[str] = []
    idx = 0
    for m in range(Cout):
        for c in range(Cin):
            # 원래 weight 채널 (K*K개)
            for _ in range(K * K):
                out.append(filter_src[idx])
                idx += 1
        # 패딩 채널 (Cin → padded_Cin)
        for _ in range((padded_Cin - Cin) * K * K):
            out.append("00000000")
    return out


def pad_filter_cout_to_mult4(filter_src: list[str], Cin: int, Cout: int, K: int = 3) -> list[str]:
    """
    Cout 채널 수를 4의 배수로 맞추도록 zero-padding 출력 채널 추가.
    - filter_src: flatten된 hex string 리스트 (길이 = Cin * Cout * K * K)
    - Cin: 입력 채널 수
    - Cout: 원래 출력 채널 수
    - K: 커널 크기 (기본 3)
    반환: 패딩된 filter 리스트
    """
    padded_Cout = ((Cout + 3) // 4) * 4  # 4의 배수로 올림
    out: list[str] = []
    idx = 0
    for m in range(Cout):
        for c in range(Cin):
            for _ in range(K * K):
                out.append(filter_src[idx])
                idx += 1
    # 패딩된 dummy Cout 채널 추가
    for _ in range((padded_Cout - Cout) * Cin * K * K):
        out.append("00000000")
    return out



def make_image():
    root_dir = Path(__file__).resolve().parent.parent
    feamap_dir = root_dir / "repo" / "data" / "feamap"
    param_dir  = root_dir / "repo" / "data" / "param"
    
    
    
    feamap_path = feamap_dir.resolve()
    param_path  = param_dir.resolve()
    
    memory_path = (root_dir / "hw" / "inout_data" / "yolo" / "dram").resolve()
    expect_path = (root_dir / "hw" / "inout_data" / "yolo" / "expect").resolve()
    
    
    memory_file  = memory_path / "yolo_engine_image.hex"
    expect_file  = expect_path / "yolo_engine_expect.hex"
    
    
    L00_ifm_file  = feamap_path / "CONV00_input_32b.hex"
    
    L00_filt_file = param_path / "CONV00_param_weight.hex"
    L01_filt_file = param_path / "CONV02_param_weight.hex"
    L02_filt_file = param_path / "CONV04_param_weight.hex"
    L03_filt_file = param_path / "CONV06_param_weight.hex"
    L04_filt_file = param_path / "CONV08_param_weight.hex"
    L05_filt_file = param_path / "CONV10_param_weight.hex"
    L06_filt_file = param_path / "CONV12_param_weight.hex"
    L07_filt_file = param_path / "CONV13_param_weight.hex"
    L08_filt_file = param_path / "CONV14_param_weight.hex"
    L11_filt_file = param_path / "CONV17_param_weight.hex"
    L14_filt_file = param_path / "CONV20_param_weight.hex"
    
    
    L00_bias_file = param_path / "CONV00_param_biases.hex"
    L01_bias_file = param_path / "CONV02_param_biases.hex"
    L02_bias_file = param_path / "CONV04_param_biases.hex"
    L03_bias_file = param_path / "CONV06_param_biases.hex"
    L04_bias_file = param_path / "CONV08_param_biases.hex"
    L05_bias_file = param_path / "CONV10_param_biases.hex"
    L06_bias_file = param_path / "CONV12_param_biases.hex"
    L07_bias_file = param_path / "CONV13_param_biases.hex"
    L08_bias_file = param_path / "CONV14_param_biases.hex"
    L11_bias_file = param_path / "CONV17_param_biases.hex"
    L14_bias_file = param_path / "CONV20_param_biases.hex"
    
    
    L00_scal_file = param_path / "CONV00_param_scales.hex"
    L01_scal_file = param_path / "CONV02_param_scales.hex"
    L02_scal_file = param_path / "CONV04_param_scales.hex"
    L03_scal_file = param_path / "CONV06_param_scales.hex"
    L04_scal_file = param_path / "CONV08_param_scales.hex"
    L05_scal_file = param_path / "CONV10_param_scales.hex"
    L06_scal_file = param_path / "CONV12_param_scales.hex"
    L07_scal_file = param_path / "CONV13_param_scales.hex"
    L08_scal_file = param_path / "CONV14_param_scales.hex"
    L11_scal_file = param_path / "CONV17_param_scales.hex"
    L14_scal_file = param_path / "CONV20_param_scales.hex"
    
    
    L00_ifm_src  = read_32b_hex_lines(L00_ifm_file)
    
    L00_filt_src = read_32b_hex_lines(L00_filt_file)    # cin=3->4 padding
    L01_filt_src = read_32b_hex_lines(L01_filt_file)
    L02_filt_src = read_32b_hex_lines(L02_filt_file)
    L03_filt_src = read_32b_hex_lines(L03_filt_file)
    L04_filt_src = read_32b_hex_lines(L04_filt_file)
    L05_filt_src = read_32b_hex_lines(L05_filt_file)
    L06_filt_src = read_32b_hex_lines(L06_filt_file)    # 1x1 -> 3x3
    L07_filt_src = read_32b_hex_lines(L07_filt_file)
    L08_filt_src = read_32b_hex_lines(L08_filt_file)    # 1x1 -> 3x3    # cout=195 -> 196 padding
    L11_filt_src = read_32b_hex_lines(L11_filt_file)    # 1x1 -> 3x3
    L14_filt_src = read_32b_hex_lines(L14_filt_file)    # 1x1 -> 3x3    # cout=195 -> 196 padding
    
    
    L00_bias_src = read_32b_hex_lines(L00_bias_file) 
    L01_bias_src = read_32b_hex_lines(L01_bias_file)
    L02_bias_src = read_32b_hex_lines(L02_bias_file)
    L03_bias_src = read_32b_hex_lines(L03_bias_file)
    L04_bias_src = read_32b_hex_lines(L04_bias_file)
    L05_bias_src = read_32b_hex_lines(L05_bias_file)
    L06_bias_src = read_32b_hex_lines(L06_bias_file)
    L07_bias_src = read_32b_hex_lines(L07_bias_file)
    L08_bias_src = read_32b_hex_lines(L08_bias_file)    # cout=195 -> 196 padding
    L11_bias_src = read_32b_hex_lines(L11_bias_file)
    L14_bias_src = read_32b_hex_lines(L14_bias_file)    # cout=195 -> 196 padding
    
    
    L00_scal_src = read_32b_hex_lines(L00_scal_file) 
    L01_scal_src = read_32b_hex_lines(L01_scal_file)
    L02_scal_src = read_32b_hex_lines(L02_scal_file)
    L03_scal_src = read_32b_hex_lines(L03_scal_file)
    L04_scal_src = read_32b_hex_lines(L04_scal_file)
    L05_scal_src = read_32b_hex_lines(L05_scal_file)
    L06_scal_src = read_32b_hex_lines(L06_scal_file)
    L07_scal_src = read_32b_hex_lines(L07_scal_file)
    L08_scal_src = read_32b_hex_lines(L08_scal_file)    # cout=195 -> 196 padding
    L11_scal_src = read_32b_hex_lines(L11_scal_file)
    L14_scal_src = read_32b_hex_lines(L14_scal_file)    # cout=195 -> 196 padding
    # ===================================================================
    # preprocess
    # ===================================================================
    L00_filt_src = pad_filter_cin_to_mult4(L00_filt_src, 3, L00_cout)
    
    L06_filt_src = pad_1x1_to_3x3(L06_filt_src, L06_cin, L06_cout)
    L11_filt_src = pad_1x1_to_3x3(L11_filt_src, L11_cin, L11_cout)
    
    L08_filt_tmp = pad_filter_cout_to_mult4(L08_filt_src, L08_cin, 195, 1)
    L14_filt_tmp = pad_filter_cout_to_mult4(L14_filt_src, L14_cin, 195, 1)
    
    L08_filt_src = pad_1x1_to_3x3(L08_filt_tmp, L08_cin, L08_cout)
    L14_filt_src = pad_1x1_to_3x3(L14_filt_tmp, L14_cin, L14_cout)
    
    L08_bias_src.append("00000000")
    L14_bias_src.append("00000000")
    
    L08_scal_src.append("00000000")
    L14_scal_src.append("00000000")
    # ===================================================================
    L00_filt_72b = pack_filter_72b(L00_filt_src)
    L01_filt_72b = pack_filter_72b(L01_filt_src)
    L02_filt_72b = pack_filter_72b(L02_filt_src)
    L03_filt_72b = pack_filter_72b(L03_filt_src)
    L04_filt_72b = pack_filter_72b(L04_filt_src)
    L05_filt_72b = pack_filter_72b(L05_filt_src)
    L06_filt_72b = pack_filter_72b(L06_filt_src)
    L07_filt_72b = pack_filter_72b(L07_filt_src)
    L08_filt_72b = pack_filter_72b(L08_filt_src)
    L11_filt_72b = pack_filter_72b(L11_filt_src)
    L14_filt_72b = pack_filter_72b(L14_filt_src)
    
    
    L00_filt_32b = pack_filter_32b(L00_cin, L00_cout, L00_filt_src)
    L01_filt_32b = pack_filter_32b(L01_cin, L01_cout, L01_filt_src)
    L02_filt_32b = pack_filter_32b(L02_cin, L02_cout, L02_filt_src)
    L03_filt_32b = pack_filter_32b(L03_cin, L03_cout, L03_filt_src)
    L04_filt_32b = pack_filter_32b(L04_cin, L04_cout, L04_filt_src)
    L05_filt_32b = pack_filter_32b(L05_cin, L05_cout, L05_filt_src)
    L06_filt_32b = pack_filter_32b(L06_cin, L06_cout, L06_filt_src)
    L07_filt_32b = pack_filter_32b(L07_cin, L07_cout, L07_filt_src)
    L08_filt_32b = pack_filter_32b(L08_cin, L08_cout, L08_filt_src)
    L11_filt_32b = pack_filter_32b(L11_cin, L11_cout, L11_filt_src)
    L14_filt_32b = pack_filter_32b(L14_cin, L14_cout, L14_filt_src)
    
    # ===================================================================
    mem_ifm = L00_ifm_src
    mem_filt = L00_filt_32b + L01_filt_32b + L02_filt_32b + L03_filt_32b + L04_filt_32b + L05_filt_32b + L06_filt_32b + L07_filt_32b + L08_filt_32b + L11_filt_32b + L14_filt_32b 
    mem_bias = L00_bias_src + L01_bias_src + L02_bias_src + L03_bias_src + L04_bias_src + L05_bias_src + L06_bias_src + L07_bias_src + L08_bias_src + L11_bias_src + L14_bias_src
    mem_scal = L00_scal_src + L01_scal_src + L02_scal_src + L03_scal_src + L04_scal_src + L05_scal_src + L06_scal_src + L07_scal_src + L08_scal_src + L11_scal_src + L14_scal_src
    
    info_memory = memory_builder_monolayer(mem_ifm, mem_filt, mem_bias, mem_scal)
    
    write_hex_lines(memory_file, info_memory["memory"])
    
    print("DRAM memory image built")
    print("offset")
    print(f" ifm    : {info_memory['ifm_offset'] * 4}")
    print(f" filter : {info_memory['filter_offset'] * 4}")
    print(f" bias   : {info_memory['bias_offset'] * 4}")
    print(f" scale  : {info_memory['scale_offset'] * 4}")
    print(f" total  : {info_memory['total_lines'] * 4} bytes")
    print(f" total  : {info_memory['total_lines']} lines")
    # ===================================================================
    # ===================================================================
    # EXPECT
    # ===================================================================
    params = load_params(Path("repo") / "testcase_args.json") 
    # Layer 0
    print("[Layer 0]")
    params.width = L00_width
    params.height = L00_height
    params.cin = L00_cin
    params.cout = L00_cout
    print(f" width={params.width} height={params.height} cin={params.cin} cout={params.cout}")
    
    L00_affine_data = pack_affine(params.cout, L00_bias_src, L00_scal_src)
    
    L00_conv_result             = run_conv(L00_ifm_src, L00_filt_72b, params.height, params.width, params.cin, params.cout)
    L00_affine_result           = run_affine_from_conv(L00_conv_result, L00_affine_data, params.height, params.width, params.cout)
    L00_maxpool_stride2_result  = maxpool_from_affine_words(L00_affine_result, params.height, params.width, params.cout, stride=2)
    # L00 output: L00_maxpool_stride2_result
    # ===================================================================
    # Layer 1
    print("[Layer 1]")
    params.width  = L01_width
    params.height = L01_height
    params.cin    = L01_cin
    params.cout   = L01_cout
    print(f" width={params.width} height={params.height} cin={params.cin} cout={params.cout}")

    L01_affine_data            = pack_affine(params.cout, L01_bias_src, L01_scal_src)
    L01_conv_result            = run_conv(L00_maxpool_stride2_result, L01_filt_72b, params.height, params.width, params.cin, params.cout)
    L01_affine_result          = run_affine_from_conv(L01_conv_result, L01_affine_data, params.height, params.width, params.cout)
    L01_maxpool_stride2_result = maxpool_from_affine_words(L01_affine_result, params.height, params.width, params.cout, stride=2)
    # L01 output: L01_maxpool_stride2_result
    # ===================================================================

    # Layer 2
    print("[Layer 2]")
    params.width  = L02_width
    params.height = L02_height
    params.cin    = L02_cin
    params.cout   = L02_cout
    print(f" width={params.width} height={params.height} cin={params.cin} cout={params.cout}")

    L02_affine_data            = pack_affine(params.cout, L02_bias_src, L02_scal_src)
    L02_conv_result            = run_conv(L01_maxpool_stride2_result, L02_filt_72b, params.height, params.width, params.cin, params.cout)
    L02_affine_result          = run_affine_from_conv(L02_conv_result, L02_affine_data, params.height, params.width, params.cout)
    L02_maxpool_stride2_result = maxpool_from_affine_words(L02_affine_result, params.height, params.width, params.cout, stride=2)
    # L02 output: L02_maxpool_stride2_result
    # ===================================================================

    # Layer 3
    print("[Layer 3]")
    params.width  = L03_width
    params.height = L03_height
    params.cin    = L03_cin
    params.cout   = L03_cout
    print(f" width={params.width} height={params.height} cin={params.cin} cout={params.cout}")

    L03_affine_data            = pack_affine(params.cout, L03_bias_src, L03_scal_src)
    L03_conv_result            = run_conv(L02_maxpool_stride2_result, L03_filt_72b, params.height, params.width, params.cin, params.cout)
    L03_affine_result          = run_affine_from_conv(L03_conv_result, L03_affine_data, params.height, params.width, params.cout)
    L03_maxpool_stride2_result = maxpool_from_affine_words(L03_affine_result, params.height, params.width, params.cout, stride=2)
    # L03 output: L03_maxpool_stride2_result
    # ===================================================================

    # Layer 4
    print("[Layer 4]")
    params.width  = L04_width
    params.height = L04_height
    params.cin    = L04_cin
    params.cout   = L04_cout
    print(f" width={params.width} height={params.height} cin={params.cin} cout={params.cout}")

    L04_affine_data            = pack_affine(params.cout, L04_bias_src, L04_scal_src)
    L04_conv_result            = run_conv(L03_maxpool_stride2_result, L04_filt_72b, params.height, params.width, params.cin, params.cout)
    L04_affine_result          = run_affine_from_conv(L04_conv_result, L04_affine_data, params.height, params.width, params.cout)
    L04_maxpool_stride2_result = maxpool_from_affine_words(L04_affine_result, params.height, params.width, params.cout, stride=2)
    # L04 output: L04_maxpool_stride2_result
    # ===================================================================

    # Layer 5
    print("[Layer 5]")
    params.width  = L05_width
    params.height = L05_height
    params.cin    = L05_cin
    params.cout   = L05_cout
    print(f" width={params.width} height={params.height} cin={params.cin} cout={params.cout}")

    L05_affine_data            = pack_affine(params.cout, L05_bias_src, L05_scal_src)
    L05_conv_result            = run_conv(L04_maxpool_stride2_result, L05_filt_72b, params.height, params.width, params.cin, params.cout)
    L05_affine_result          = run_affine_from_conv(L05_conv_result, L05_affine_data, params.height, params.width, params.cout)
    L05_maxpool_stride1_result = maxpool_from_affine_words(L05_affine_result, params.height, params.width, params.cout, stride=1)
    # L05 output: L05_maxpool_stride1_result
    # ===================================================================

    # Layer 6
    print("[Layer 6]")
    params.width  = L06_width
    params.height = L06_height
    params.cin    = L06_cin
    params.cout   = L06_cout
    print(f" width={params.width} height={params.height} cin={params.cin} cout={params.cout}")

    L06_affine_data            = pack_affine(params.cout, L06_bias_src, L06_scal_src)
    L06_conv_result            = run_conv(L05_maxpool_stride1_result, L06_filt_72b, params.height, params.width, params.cin, params.cout)
    L06_affine_result          = run_affine_from_conv(L06_conv_result, L06_affine_data, params.height, params.width, params.cout)
    # L06 output: L06_affine_result
    # ===================================================================

    # Layer 7
    print("[Layer 7]")
    params.width  = L07_width
    params.height = L07_height
    params.cin    = L07_cin
    params.cout   = L07_cout
    print(f" width={params.width} height={params.height} cin={params.cin} cout={params.cout}")

    L07_affine_data            = pack_affine(params.cout, L07_bias_src, L07_scal_src)
    L07_conv_result            = run_conv(L06_affine_result, L07_filt_72b, params.height, params.width, params.cin, params.cout)
    L07_affine_result          = run_affine_from_conv(L07_conv_result, L07_affine_data, params.height, params.width, params.cout)
    # L07 output: L07_affine_result
    # ===================================================================

    # Layer 8
    print("[Layer 8]")
    params.width  = L08_width
    params.height = L08_height
    params.cin    = L08_cin
    params.cout   = L08_cout
    print(f" width={params.width} height={params.height} cin={params.cin} cout={params.cout}")

    L08_affine_data            = pack_affine(params.cout, L08_bias_src, L08_scal_src)
    L08_conv_result            = run_conv(L07_affine_result, L08_filt_72b, params.height, params.width, params.cin, params.cout)
    L08_affine_result          = run_affine_from_conv(L08_conv_result, L08_affine_data, params.height, params.width, params.cout)
    # L08 output: L08_affine_result
    # ===================================================================

    # Layer 9
    print("[Layer 9]")
    print("DRAM save layer")
    # ===================================================================

    # Layer 10
    print("[Layer 10]")
    print("ROUTE layer")

    # L10 output: L06_affine_result
    # ===================================================================

    # Layer 11
    print("[Layer 11]")
    params.width  = L11_width
    params.height = L11_height
    params.cin    = L11_cin
    params.cout   = L11_cout
    print(f" width={params.width} height={params.height} cin={params.cin} cout={params.cout}")

    L11_affine_data            = pack_affine(params.cout, L11_bias_src, L11_scal_src)
    L11_conv_result            = run_conv(L06_affine_result, L11_filt_72b, params.height, params.width, params.cin, params.cout)
    L11_affine_result          = run_affine_from_conv(L11_conv_result, L11_affine_data, params.height, params.width, params.cout)
    # L11 output: L11_affine_result
    # ===================================================================

    # Layer 12
    print("[Layer 12]")
    print("UPSAMPLE")
    params.width  = L11_width
    params.height = L11_height
    params.cin    = L11_cout   # cout
    params.cout   = L11_cout
    
    L12_upsample_result = upsample_words(L11_affine_result, params.height, params.width, params.cin)
    # L12 output: L12_upsample_result
    # ===================================================================

    # Layer 13
    print("[Layer 13]")
    print("CONCAT")
    
    L13_concat_result = concat_words(L12_upsample_result, L04_affine_result, 16, 16, 128, 256)
    # L13 output: L13_concat_result
    # ===================================================================

    # Layer 14
    print("[Layer 14]")
    params.width  = L14_width
    params.height = L14_height
    params.cin    = L14_cin
    params.cout   = L14_cout
    print(f" width={params.width} height={params.height} cin={params.cin} cout={params.cout}")

    L14_affine_data            = pack_affine(params.cout, L14_bias_src, L14_scal_src)
    L14_conv_result            = run_conv(L13_concat_result, L14_filt_72b, params.height, params.width, params.cin, params.cout)
    L14_affine_result          = run_affine_from_conv(L14_conv_result, L14_affine_data, params.height, params.width, params.cout)
    # L14 output: L14_affine_result
    # ===================================================================
    
    yolo_expect = L08_affine_result + L14_affine_result
    print("EXPECT info")
    print(f" total  : {len(yolo_expect) * 4} bytes")
    print(f" total  : {len(yolo_expect)} lines")
    write_hex_lines(expect_file, yolo_expect)
    
    
if __name__ == "__main__":
    make_image()