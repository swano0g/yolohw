import numpy as np
import sys
import json
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any, List
import math

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
    out_golden_hex: Path
    out_golden_final_hex: Path


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

    out_feamap_dir.mkdir(parents=True, exist_ok=True)
    out_param_packed_dir.mkdir(parents=True, exist_ok=True)
    out_expect_dir.mkdir(parents=True, exist_ok=True)

    out_ifm_hex    = out_feamap_dir       / f"test{tc_no}_input_32b.hex"
    out_weight_hex = out_param_packed_dir / f"test{tc_no}_param_packed_weight.hex"
    out_golden_hex = out_expect_dir       / f"test{tc_no}_output_32b.hex"
    out_affine_hex = out_param_packed_dir / f"test{tc_no}_affine_param.hex"
    out_golden_final_hex = out_expect_dir / f"test{tc_no}_answer_32b.hex"

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
        out_golden_hex=out_golden_hex,
        out_golden_final_hex=out_golden_final_hex,
    )
    

def _read_hex32_lines(path: Path) -> list[int]:
    vals = []
    with path.open("r", encoding="utf-8") as f:
        for raw in f:
            s = raw.strip()
            if not s:
                continue
            # 32b 마스크 후 파이썬 int로
            vals.append(int(s, 16) & 0xFFFFFFFF)
    return vals

def _to_int32(v: int) -> int:
    """32b two's complement 부호해석 (넘파이 미사용)"""
    v &= 0xFFFFFFFF
    return v - 0x100000000 if (v & 0x80000000) else v

def _is_pow2_u8(x: int) -> bool:
    return x != 0 and (x & (x - 1)) == 0


def _midbyte_to_shift(mid: int) -> int:
    """
    규칙: mid( [15:8] ) -> (mid << 4) 가 2의 거듭제곱이라고 가정
         shift = log2(mid << 4) + 1
    예) mid=0x04 -> (0x40) -> 6 -> +1 => 7
    """
    mid &= 0xFF
    if mid == 0:
        return 0
    val = mid << 4
    # 부동소수 log2 대신 정수 비트 계산
    if _is_pow2_u8(mid):
        return (val.bit_length() - 1) + 1  # log2(val) + 1
    # 원-핫이 아니면 보수적으로 바이트 값을 직접 시프트량으로 사용(원하시면 에러 처리로 바꿔도 됨)
    return mid


def _pack4_u8_le(v0, v1, v2, v3) -> int:
    # 4개의 u8을 리틀엔디언 32b로 패킹
    return (v0 & 0xFF) | ((v1 & 0xFF) << 8) | ((v2 & 0xFF) << 16) | ((v3 & 0xFF) << 24)


def run_affine_from_expect(expect_path: Path, affine_path: Path,
                           out_path: Path, H: int, W: int, M: int):
    """
    expect_path : conv 누적 결과(INT32) hex (한 줄 32b, m -> x -> y 순으로 저장되어 있다고 가정)
    affine_path : 채널별 bias(INT32) hex, 줄 수 = M -> 채널별 scale(INT32) hex, 줄 수 = M => total 2M 줄
    out_path    : 최종 UINT8을 4개씩 32b로 묶어(m 빠름 → x → y) 저장
    """
    out_path.parent.mkdir(parents=True, exist_ok=True)


    # -------------------------------
    # 1) 입력 로드
    # expect: 저장 루프가 (y,x,m) 순으로 작성되었고 m가 가장 안쪽이므로
    #         읽을 때도 동일 순서로 복원
    exp_words = _read_hex32_lines(expect_path)
    if len(exp_words) != H * W * M:
        raise ValueError(f"expect 크기 불일치: got {len(exp_words)} lines, expected {H*W*M}")


    # 2) affine 로드 (bias M줄 + scale M줄)
    aff_words = _read_hex32_lines(affine_path)
    if len(aff_words) < 2 * M:
        raise ValueError(f"affine 크기 불일치: {len(aff_words)} lines, expected >= {2*M}")
    
    bias_words  = aff_words[:M]
    scale_words = aff_words[M:M*2]

    bias_list = [_to_int32(v) for v in bias_words]
    bias = np.array(bias_list, dtype=np.int32)        # (M,)
    
    
    scale_shift_list = []
    for v in scale_words[:M]:
        if v <= 0:
            shift = 0
        else:
            shift = int(math.log2(v)) + 1
        scale_shift_list.append(shift)
        
    scale_shift = np.array(scale_shift_list, dtype=np.int32)  # (M,)

    # expect 텐서 복원: (M,H,W)로 보관
    ofm_int32 = np.zeros((M, H, W), dtype=np.int32)
    idx = 0
    for y in range(H):
        for x in range(W):
            # m가 가장 빠르게 증가
            for m in range(M):
                ofm_int32[m, y, x] = _to_int32(exp_words[idx])
                idx += 1

    # -------------------------------
    # 2) Affine: bias add → ReLU → right-shift(scale) → clamp to [0,255]
    # 채널별로 처리 (브로드캐스팅)
    # acc(m,y,x) + bias(m)
    ofm_int32 = ofm_int32 + bias[:, None, None]

    # ReLU
    np.maximum(ofm_int32, 0, out=ofm_int32)

    # 채널별 시프트: (m,y,x) >> scale(m)
    # 음수가 아니므로 산술/논리 동일, 안전하게 np.right_shift 사용
    # right_shift는 피연산자 dtype에 따라 동작하므로 int32 유지
    # 브로드캐스트 위해 scale을 (M,1,1)로 reshape
    ofm_shifted = np.right_shift(ofm_int32, scale_shift.astype(np.int32)[:, None, None])

    # clamp to uint8
    ofm_u8 = np.clip(ofm_shifted, 0, 255).astype(np.uint8)  # (M,H,W)

    # -------------------------------
    # 3) 저장: m → x → y 순, 4채널씩 1워드(리틀엔디언)
    with out_path.open("w", encoding="utf-8") as fw:
        for y in range(H):
            for x in range(W):
                m = 0
                while m < M:
                    # 부족하면 0 패딩
                    v0 = int(ofm_u8[m+0, y, x]) if (m+0) < M else 0
                    v1 = int(ofm_u8[m+1, y, x]) if (m+1) < M else 0
                    v2 = int(ofm_u8[m+2, y, x]) if (m+2) < M else 0
                    v3 = int(ofm_u8[m+3, y, x]) if (m+3) < M else 0
                    word = _pack4_u8_le(v0, v1, v2, v3)
                    fw.write(f"{word:08x}\n")
                    m += 4

    return ofm_u8  # (M,H,W)



def main(argv: list[str]) -> None:
    default_args = Path("tools") / "testcase_args.json"
    args_file = Path(argv[1]) if len(argv) > 1 else default_args
    args_file = args_file.expanduser()
    if not args_file.is_absolute():
        args_file = (Path.cwd() / args_file).resolve()

    params = load_params(args_file)

    print("[OK] params loaded")
    print(f" tc_no={params.testcase_no} width={params.width} height={params.height} cin={params.cin} cout={params.cout}")
    print(f" out_answer_hex={params.out_golden_final_hex}")
    run_affine_from_expect(params.out_golden_hex, params.out_affine_hex, params.out_golden_final_hex, params.height, params.width, params.cout)
    

# -------------------------------
# 예시 사용
if __name__ == "__main__":
    main(sys.argv)
