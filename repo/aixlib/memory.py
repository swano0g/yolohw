from dataclasses import dataclass
from typing import Any, List, Tuple
from .utils import TCParams



def _pad_to_mult16(lines: List[str]) -> Tuple[List[str], int]:
    """16의 배수가 될 때까지 '00000000'으로 패딩. 반환: (패딩후라인, 추가패딩수)"""
    pad_needed = (-len(lines)) % 16
    if pad_needed:
        lines = lines + ["00000000"] * pad_needed
    return lines, pad_needed


def _split32_to_16_lines(lines32: List[str]) -> List[str]:
    """
    32b 문자열 리스트를 16b 문자열 리스트로 분할.
    hi_lo=True : [상위16, 하위16]
    hi_lo=False: [하위16, 상위16]
    모든 결과는 4자리 소문자 hex로 zero-padding.
    """
    out16: List[str] = []
    for s in lines32:
        v = int(s, 16) & 0xFFFFFFFF
        hi = (v >> 16) & 0xFFFF
        lo = v & 0xFFFF
        
        out16.append(f"{lo:04x}")
        out16.append(f"{hi:04x}")
        
    return out16



def memory_builder_monolayer(params: TCParams, ifm_src: list[str], filt_src: list[str], affine_src: list[str]) -> dict:
    """
    단일 레이어 연산을 위한 memory builder\n
    섹션 순서: IFM -> FILTER -> BIAS -> SCALE\n
    반환:\n
      {
        "memory": all16_lines,          # 16b 라인(하위16→상위16 순) 리스트
        "ifm_offset": start_ifm,        # 32b 기준 오프셋
        "filter_offset": start_flt,     # 32b 기준 오프셋
        "bias_offset": start_bias,      # 32b 기준 오프셋
        "scale_offset": start_scale,    # 32b 기준 오프셋
        "total_lines": len(all32_lines),
        "total_lines_16b": len(all16_lines),
      }
    """
    
    M = params.cout
    
    ifm_lines   = list(ifm_src)
    filt_lines  = list(filt_src)
    bias_lines  = list(affine_src[:M])
    scale_lines = list(affine_src[M:M*2])

    # --- 16줄 정렬 패딩 및 오프셋 계산(32b 기준) ---
    start_ifm = 0
    ifm_lines, _ = _pad_to_mult16(ifm_lines)

    start_flt = len(ifm_lines)
    filt_lines, _ = _pad_to_mult16(filt_lines)

    start_bias = start_flt + len(filt_lines)
    bias_lines, _ = _pad_to_mult16(bias_lines)

    start_scale = start_bias + len(bias_lines)
    scale_lines, _ = _pad_to_mult16(scale_lines)

    # --- 최종 32b/16b 라인 구성 ---
    all32_lines = ifm_lines + filt_lines + bias_lines + scale_lines
    all16_lines = _split32_to_16_lines(all32_lines) 
    

    return {
        "memory": all16_lines,
        "ifm_offset": start_ifm,
        "filter_offset": start_flt,
        "bias_offset": start_bias,
        "scale_offset": start_scale,
        "total_lines": len(all32_lines),
        "total_lines_16b": len(all16_lines),
    }