import sys
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, List, Tuple

KERNEL_SIZE = 3  # 3x3

# =========================================
# Dataclasses & Arg loading
# =========================================
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

    # derived output candidates (존재하면 우선 사용)
    out_feamap_dir: Path
    out_param_packed_dir: Path
    out_dram_dir: Path
    out_ifm_hex: Path
    out_weight_hex: Path
    out_memory_hex: Path


def _abs_path(p: Path) -> Path:
    p = p.expanduser()
    if not p.is_absolute():
        p = (Path.cwd() / p).resolve()
    return p


def _require_pos_int(cfg: dict[str, Any], key: str) -> int:
    v = cfg.get(key, None)
    if not isinstance(v, int) or v <= 0:
        raise ValueError(f"'{key}' must be a positive integer")
    return v


def _require_str_path(cfg: dict[str, Any], key: str) -> Path:
    s = cfg.get(key, None)
    if not isinstance(s, str) or not s:
        raise ValueError(f"'{key}' must be a non-empty string (path)")
    return _abs_path(Path(s))


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

    ifm_path    = _require_str_path(cfg, "ifm_hex")
    filter_path = _require_str_path(cfg, "filter_hex")
    bias_path   = _require_str_path(cfg, "bias_hex")
    scale_path  = _require_str_path(cfg, "scale_hex")

    # 후보 출력/중간 산출물 경로들
    out_feamap_dir       = _abs_path(Path("hw") / "inout_data" / "feamap")
    out_param_packed_dir = _abs_path(Path("hw") / "inout_data" / "param_packed")
    out_dram_dir         = _abs_path(Path("hw") / "inout_data" / "dram")

    out_ifm_hex    = out_feamap_dir       / f"test{tc_no}_input_32b.hex"
    out_weight_hex = out_param_packed_dir / f"test{tc_no}_param_packed_weight.hex"
    out_memory_hex = out_dram_dir         / f"test{tc_no}_memory.hex"

    return TCParams(
        testcase_no=tc_no,
        width=w, height=h, cin=cin, cout=cout,
        ifm_hex=ifm_path,
        filter_hex=filter_path,
        bias_hex=bias_path,
        scale_hex=scale_path,
        out_feamap_dir=out_feamap_dir,
        out_param_packed_dir=out_param_packed_dir,
        out_dram_dir=out_dram_dir,
        out_ifm_hex=out_ifm_hex,
        out_weight_hex=out_weight_hex,
        out_memory_hex=out_memory_hex,
    )

# =========================================
# Helpers
# =========================================
def _read_hex_lines(path: Path) -> List[str]:
    """파일에서 공백/빈줄 제외, 소문자 hex 문자열 리스트 반환."""
    lines: List[str] = []
    with path.open("r", encoding="utf-8") as f:
        for raw in f:
            s = raw.strip()
            if not s:
                continue
            # 32b 고정 폭은 강제하지 않고, 정수로 파싱 가능 여부만 확인
            int(s, 16)
            lines.append(s.lower())
    return lines


def _count_required_ifm_lines(width: int, height: int, cin: int) -> int:
    # IFM은 32b 라인에 cin이 4씩 묶여 들어온다고 가정 (기존 파이프라인과 동일)
    return width * height * (cin // 4)


def _count_required_filter_lines(cin: int, cout: int) -> int:
    # 3x3 conv 가정, HW용 32b로 패킹된 파일도 라인 수는 cout*cin*9 과 동일
    return cout * cin * (KERNEL_SIZE * KERNEL_SIZE)


def _count_required_affine_lines(cout: int) -> int:
    # bias/scale 각각 cout줄
    return cout


def _truncate(lines: List[str], need: int) -> List[str]:
    return lines[:need] if len(lines) >= need else lines


def _pad_to_mult16(lines: List[str]) -> Tuple[List[str], int]:
    """16의 배수가 될 때까지 '00000000'으로 패딩. 반환: (패딩후라인, 추가패딩수)"""
    pad_needed = (-len(lines)) % 16
    if pad_needed:
        lines = lines + ["00000000"] * pad_needed
    return lines, pad_needed


def _select_if_exists(primary: Path, fallback: Path) -> Path:
    return primary if primary.is_file() else fallback

# =========================================
# Build memory image
# =========================================
def build_memory(params: TCParams) -> dict:
    """
    최종 메모리 파일을 생성하고, 섹션 시작 인덱스를 반환.
    섹션 순서: IFM -> FILTER -> BIAS -> SCALE
    """
    # 입력 소스 선택(준비된 산출물 우선)
    ifm_src    = _select_if_exists(params.out_ifm_hex, params.ifm_hex)
    filt_src   = _select_if_exists(params.out_weight_hex, params.filter_hex)
    bias_src   = params.bias_hex
    scale_src  = params.scale_hex

    # 라인 로드
    if not ifm_src.is_file():
        raise FileNotFoundError(f"IFM not found: {ifm_src}")
    if not filt_src.is_file():
        raise FileNotFoundError(f"FILTER not found: {filt_src}")
    if not bias_src.is_file():
        raise FileNotFoundError(f"BIAS not found: {bias_src}")
    if not scale_src.is_file():
        raise FileNotFoundError(f"SCALE not found: {scale_src}")

    ifm_lines_all   = _read_hex_lines(ifm_src)
    filt_lines_all  = _read_hex_lines(filt_src)
    bias_lines_all  = _read_hex_lines(bias_src)
    scale_lines_all = _read_hex_lines(scale_src)

    # 필요 라인 수로 절단(초과 입력 방지)
    need_ifm  = _count_required_ifm_lines(params.width, params.height, params.cin)
    need_flt  = _count_required_filter_lines(params.cin, params.cout)
    need_aff  = _count_required_affine_lines(params.cout)

    ifm_lines   = _truncate(ifm_lines_all, need_ifm)
    filt_lines  = _truncate(filt_lines_all, need_flt)
    bias_lines  = _truncate(bias_lines_all, need_aff)
    scale_lines = _truncate(scale_lines_all, need_aff)

    # 섹션별 패딩 전 길이 -> 시작 인덱스 계산에 사용
    start_ifm = 0
    start_flt = start_ifm + len(ifm_lines)
    # IFM 패딩
    ifm_lines, _ = _pad_to_mult16(ifm_lines)

    start_flt = len(ifm_lines)  # 패딩 반영 후 시작 인덱스 재설정
    # FILTER 패딩 전 길이 참고 후 패딩
    filt_lines, _ = _pad_to_mult16(filt_lines)

    start_bias = start_flt + len(filt_lines)
    # BIAS 패딩
    bias_lines, _ = _pad_to_mult16(bias_lines)

    start_scale = start_bias + len(bias_lines)
    # SCALE 패딩
    scale_lines, _ = _pad_to_mult16(scale_lines)

    # 최종 메모리 이미지 작성
    params.out_dram_dir.mkdir(parents=True, exist_ok=True)
    with params.out_memory_hex.open("w", encoding="utf-8") as fw:
        for s in ifm_lines:
            fw.write(s + "\n")
        for s in filt_lines:
            fw.write(s + "\n")
        for s in bias_lines:
            fw.write(s + "\n")
        for s in scale_lines:
            fw.write(s + "\n")

    return {
        "memory_path": str(params.out_memory_hex),
        "ifm": start_ifm,
        "filter": start_flt,
        "bias": start_bias,
        "scale": start_scale,
        "total_lines": len(ifm_lines) + len(filt_lines) + len(bias_lines) + len(scale_lines),
    }

# =========================================
# Main
# =========================================
def main(argv: list[str]) -> None:
    default_args = Path("tools") / "testcase_args.json"
    args_file = Path(argv[1]) if len(argv) > 1 else default_args
    args_file = _abs_path(args_file)

    params = load_params(args_file)

    # 간단 무결성 체크(필요 시 강화 가능)
    if (params.cin % 4 != 0) or (params.cout % 4 != 0):
        raise ValueError("Cin/Cout must be multiples of 4")

    info = build_memory(params)

    # 섹션 시작 인덱스 및 요약 출력
    print("[OK] DRAM memory image built")
    print(f" path   : {info['memory_path']}")
    print("offset")
    print(f" ifm    : {info['ifm'] * 4}")
    print(f" filter : {info['filter'] * 4}")
    print(f" bias   : {info['bias'] * 4}")
    print(f" scale  : {info['scale'] * 4}")
    print(f" total  : {info['total_lines'] * 4} bytes")
    print(f" total  : {info['total_lines']} lines")


if __name__ == "__main__":
    main(sys.argv)
