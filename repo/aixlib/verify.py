from .utils import KERNEL_SIZE, TCParams
from .io_hex import read_32b_hex_lines


def _count_required_ifm_lines(width: int, height: int, cin: int) -> int:
    return width * height * (cin // 4)

def _count_required_filter_lines(cin: int, cout: int) -> int:
    return cout * cin * (KERNEL_SIZE * KERNEL_SIZE)

def _count_required_affine_lines(cout: int) -> int:
    return cout


def verify_inputs(params: TCParams, ifm_lines: list[str], filt_lines: list[str], bias_lines: list[str], scale_lines: list[str]) -> tuple:
    if (params.cin % 4 != 0) or (params.cout %4 != 0):
        raise ValueError(f"Cin/Cout must be multiple of 4")
    
    need_ifm = _count_required_ifm_lines(params.width, params.height, params.cin)
    need_flt = _count_required_filter_lines(params.cin, params.cout)
    need_aff = _count_required_affine_lines(params.cout)

    if len(ifm_lines) < need_ifm:
        raise ValueError(f"IFM data not enough: have={len(ifm_lines)} need={need_ifm}")
    if len(filt_lines) < need_flt:
        raise ValueError(f"FILTER data not enough: have={len(filt_lines)} need={need_flt}")
    if len(bias_lines) < need_aff:
        raise ValueError(f"BIAS data not enough: have={len(bias_lines)} need={need_aff}")
    if len(scale_lines) < need_aff:
        raise ValueError(f"SCALE data not enough: have={len(scale_lines)} need={need_aff}")
    
    
    
    
    out_ifm  = ifm_lines[:need_ifm]
    out_filt = filt_lines[:need_flt]
    out_bias = bias_lines[:need_aff]
    out_scale = scale_lines[:need_aff]
    
    
    return (out_ifm, out_filt, out_bias, out_scale)