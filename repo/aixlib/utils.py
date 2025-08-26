import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, List


KERNEL_SIZE = 3  # 3x3


@dataclass(frozen=True)
class TCParams:
    testcase_no: int
    width: int
    height: int
    cin: int
    cout: int
    ifm_hex: Path
    filter_hex: Path
    bias_hex: Path
    scale_hex: Path

    out_feamap_dir: Path
    out_param_packed_dir: Path
    out_expect_dir: Path
    out_ifm_hex: Path
    out_weight_hex: Path
    out_affine_hex: Path
    out_conv_result_hex: Path
    out_affine_result_hex: Path
    out_maxpool_stride1_result_hex: Path
    out_maxpool_stride2_result_hex: Path
    out_upsample_result_hex: Path
    out_golden_hex: Path
    out_memory_hex: Path
    
    
    
def _require_pos_int(cfg: dict[str, Any], key: str) -> int:
    v = cfg.get(key, None)
    if not isinstance(v, int) or v <= 0:
        raise ValueError(f"'{key}' must be a positive integer")
    return v


def _require_str_path(cfg: dict[str, Any], key: str) -> Path:
    s = cfg.get(key, None)
    if not isinstance(s, str) or not s:
        raise ValueError(f"'{key}' must be a non-empty string (path)")
    p = Path(s).expanduser()
    if not p.is_absolute():
        p = (Path.cwd() / p).resolve()
    return p
 

def _abs_path(p: Path) -> Path:
    p = p.expanduser()
    if not p.is_absolute():
        p = (Path.cwd() / p).resolve()
    return p



def load_params(args_path: Path) -> TCParams:
    args_path = _abs_path(args_path)
    if not args_path.is_file():
        raise FileNotFoundError(f"args file not found: {args_path}")

    with args_path.open("r", encoding="utf-8") as f:
        cfg = json.load(f)

    tc_no = _require_pos_int(cfg, "testcase_no")
    w     = _require_pos_int(cfg, "width")
    h     = _require_pos_int(cfg, "height")
    cin   = _require_pos_int(cfg, "cin")
    cout  = _require_pos_int(cfg, "cout")

    ifm      = _require_str_path(cfg, "ifm_hex")
    filter_p = _require_str_path(cfg, "filter_hex")
    bias_p    = _require_str_path(cfg, "bias_hex")
    scale_p   = _require_str_path(cfg, "scale_hex")

    if not ifm.is_file():
        raise FileNotFoundError(f"IFM hex not found: {ifm}")
    if not filter_p.is_file():
        raise FileNotFoundError(f"FILTER hex not found: {filter_p}")
    if not bias_p.is_file():
        raise FileNotFoundError(f"BIAS hex not found: {bias_p}")
    if not scale_p.is_file():
        raise FileNotFoundError(f"SCALE hex not found: {scale_p}")

    out_feamap_dir       = _abs_path(Path("hw") / "inout_data" / "feamap")
    out_param_packed_dir = _abs_path(Path("hw") / "inout_data" / "param_packed")
    out_expect_dir       = _abs_path(Path("hw") / "inout_data" / "expect")
    out_dram_dir         = _abs_path(Path("hw") / "inout_data" / "dram")

    out_feamap_dir.mkdir(parents=True, exist_ok=True)
    out_param_packed_dir.mkdir(parents=True, exist_ok=True)
    out_expect_dir.mkdir(parents=True, exist_ok=True)
    out_dram_dir.mkdir(parents=True, exist_ok=True)

    out_ifm_hex    = out_feamap_dir       / f"test{tc_no}_input_32b.hex"
    out_weight_hex = out_param_packed_dir / f"test{tc_no}_param_packed_weight.hex"
    out_affine_hex = out_param_packed_dir / f"test{tc_no}_affine_param.hex"
    out_memory_hex = out_dram_dir         / f"test{tc_no}_memory_16b.hex"
    
    out_conv_result_hex = out_expect_dir     / f"test{tc_no}_conv_result_32b.hex"
    out_affine_result_hex = out_expect_dir   / f"test{tc_no}_affine_result_32b.hex"
    out_maxpool_stride1_result_hex = out_expect_dir  / f"test{tc_no}_maxpool_stride1_result_32b.hex"
    out_maxpool_stride2_result_hex = out_expect_dir  / f"test{tc_no}_maxpool_stride2_result_32b.hex"
    out_upsample_result_hex = out_expect_dir / f"test{tc_no}_upsample_result_32b.hex"
    
    out_golden_hex = out_expect_dir        / f"test{tc_no}_output_32b.hex"

    return TCParams(
        testcase_no=tc_no,
        width=w, height=h, cin=cin, cout=cout,
        ifm_hex=ifm, filter_hex=filter_p,
        bias_hex=bias_p, scale_hex=scale_p,
        out_feamap_dir=out_feamap_dir,
        out_param_packed_dir=out_param_packed_dir,
        out_expect_dir=out_expect_dir,
        out_ifm_hex=out_ifm_hex,
        out_weight_hex=out_weight_hex,
        out_affine_hex=out_affine_hex,
        out_conv_result_hex=out_conv_result_hex,
        out_affine_result_hex=out_affine_result_hex,
        out_maxpool_stride1_result_hex=out_maxpool_stride1_result_hex,
        out_maxpool_stride2_result_hex=out_maxpool_stride2_result_hex,
        out_upsample_result_hex=out_upsample_result_hex,
        out_golden_hex=out_golden_hex,
        out_memory_hex=out_memory_hex,
    )
    




def read_lsb_1byte(in_list: list[str]) -> list[str]:
    out: list[str] = []
            
    for raw in in_list:
        s = raw.strip()
        if not s:
            continue
        v = int(s, 16)
        out.append(f"{(v & 0xFF):02x}")
            
    return out

