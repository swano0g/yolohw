import sys
import json
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any, List

from do_conv import run_conv

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

    out_feamap_dir: Path
    out_param_packed_dir: Path
    out_expect_dir: Path
    out_ifm_hex: Path
    out_weight_hex: Path
    out_golden_hex: Path


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

    if not ifm.is_file():
        raise FileNotFoundError(f"IFM hex not found: {ifm}")
    if not filter_p.is_file():
        raise FileNotFoundError(f"FILTER hex not found: {filter_p}")

    out_feamap_dir       = _abs_path(Path("hw") / "inout_data" / "feamap")
    out_param_packed_dir = _abs_path(Path("hw") / "inout_data" / "param_packed")
    out_expect_dir       = _abs_path(Path("hw") / "inout_data" / "expect")

    out_feamap_dir.mkdir(parents=True, exist_ok=True)
    out_param_packed_dir.mkdir(parents=True, exist_ok=True)
    out_expect_dir.mkdir(parents=True, exist_ok=True)

    out_ifm_hex    = out_feamap_dir       / f"test{tc_no}_input_32b.hex"
    out_weight_hex = out_param_packed_dir / f"test{tc_no}_param_packed_weight.hex"
    out_golden_hex = out_expect_dir       / f"test{tc_no}_output_32b.hex"

    return TCParams(
        testcase_no=tc_no,
        width=w, height=h, cin=cin, cout=cout,
        ifm_hex=ifm, filter_hex=filter_p,
        out_feamap_dir=out_feamap_dir,
        out_param_packed_dir=out_param_packed_dir,
        out_expect_dir=out_expect_dir,
        out_ifm_hex=out_ifm_hex,
        out_weight_hex=out_weight_hex,
        out_golden_hex=out_golden_hex,
    )


# ------------------------------
# I/O 유틸
# ------------------------------
def _read_hex_lines(path: Path) -> List[str]:
    lines: List[str] = []
    with path.open("r", encoding="utf-8") as f:
        for raw in f:
            s = raw.strip()
            if not s:
                continue
            # 검증: 1~8 hex (32b 가정) - 필요시 완화 가능
            int(s, 16)  # ValueError 유발 용도
            lines.append(s.lower())
    return lines


def _count_required_ifm_lines(width: int, height: int, cin: int) -> int:
    return width * height * (cin // 4)

def _count_required_filter_lines(cin: int, cout: int) -> int:
    return cout * cin * (KERNEL_SIZE * KERNEL_SIZE)


# ------------------------------
# 검증 루틴
# ------------------------------
def verify_inputs(params: TCParams) -> None:
    if (params.cin % 4 != 0) or (params.cout %4 != 0):
        raise ValueError(f"Cin/Cout must be multiple of 4")
    
    ifm_lines = _read_hex_lines(params.ifm_hex)
    filt_lines = _read_hex_lines(params.filter_hex)

    need_ifm = _count_required_ifm_lines(params.width, params.height, params.cin)
    need_flt = _count_required_filter_lines(params.cin, params.cout)

    if len(ifm_lines) < need_ifm:
        raise ValueError(f"IFM data not enough: have={len(ifm_lines)} need={need_ifm}")
    if len(filt_lines) < need_flt:
        raise ValueError(f"FILTER data not enough: have={len(filt_lines)} need={need_flt}")



# ------------------------------
# 2종 패킹
# ------------------------------
def read_lsb_bytes(in_path: Path, n_words: int) -> list[str]:
    out: list[str] = []
    with in_path.open("r", encoding="utf-8") as f:
        for raw in f:
            if len(out) >= n_words:
                break
            s = raw.strip()
            if not s:
                continue
            v = int(s, 16)
            out.append(f"{(v & 0xFF):02x}")
    return out



def pack_weight_for_golden(params: TCParams, out72_path: Path) -> None:
    lines = _count_required_filter_lines(params.cin, params.cout)
    src_lines = read_lsb_bytes(params.filter_hex, lines)

    out72_path.parent.mkdir(parents=True, exist_ok=True)
    with out72_path.open("w", encoding="utf-8") as fw:
        for i in range(0, len(src_lines), 9):
            group = src_lines[i:i+9]
            packed = "".join(reversed(group))
            fw.write(packed.lower() + "\n")



def pack_weight_for_hw(params: TCParams, out32_path: Path) -> None:
    lines = _count_required_filter_lines(params.cin, params.cout)
    src_lines = read_lsb_bytes(params.filter_hex, lines)

    out32_path.parent.mkdir(parents=True, exist_ok=True)
    with out32_path.open("w", encoding="utf-8") as fw:
        # cout을 4개씩 그룹
        for cg in range(0, params.cout, 4):
            # 각 cin, k에 대해 하나의 32비트 워드 생성
            for ci in range(params.cin):
                for k in range(9):
                    # 각 cout의 동일 (cin, k) 위치 바이트를 수집
                    idxs = [(((co * params.cin) + ci) * 9) + k for co in (cg, cg+1, cg+2, cg+3)]
                    b = [src_lines[i] for i in idxs]

                    # little endian
                    packed32 = f"{b[0]}{b[1]}{b[2]}{b[3]}"
                    fw.write(packed32.lower() + "\n")


# ------------------------------
# IFM 복사
# ------------------------------
def copy_ifm_verbatim(params: TCParams) -> None:
    lines = _count_required_ifm_lines(params.width, params.height, params.cin)
    src = params.ifm_hex
    dst = params.out_ifm_hex
    
    dst.parent.mkdir(parents=True, exist_ok=True)
    
    with src.open("r", encoding="utf-8") as fr, dst.open("w", encoding="utf-8") as fw:
        for i, raw in enumerate(fr):
            if i >= lines:
                break
            fw.write(raw)


def main(argv: list[str]) -> None:
    default_args = Path("tools") / "testcase_args.json"
    args_file = Path(argv[1]) if len(argv) > 1 else default_args
    args_file = args_file.expanduser()
    if not args_file.is_absolute():
        args_file = (Path.cwd() / args_file).resolve()

    params = load_params(args_file)

    print("[OK] params loaded")
    print(f" tc_no={params.testcase_no} width={params.width} height={params.height} cin={params.cin} cout={params.cout}")
    print(f" ifm_hex={params.ifm_hex}")
    print(f" filter_hex={params.filter_hex}")
    print(f" out_ifm_hex={params.out_ifm_hex}")
    print(f" out_weight_hex={params.out_weight_hex}")
    print(f" out_golden_hex={params.out_golden_hex}")
    
    
    # 1) 입력 검증 (라인 수 등)
    verify_inputs(params)
    print("[OK] input sizes verified")

    # 2) IFM 복사
    copy_ifm_verbatim(params)
    print(f"[OK] IFM copied -> {params.out_ifm_hex}")

    # 3) 가중치 2종 패킹
    tmp_dir = _abs_path(Path("tools") / "tmp")
    tmp_dir.mkdir(parents=True, exist_ok=True)
    packed72_path = tmp_dir / f"test{params.testcase_no}_param_packed_for_golden_72b.hex"
    
    pack_weight_for_golden(params, packed72_path)
    print(f"[OK] weight packed for golden (72b) -> {packed72_path}")

    pack_weight_for_hw(params, params.out_weight_hex)
    print(f"[OK] weight packed for HW (32b) -> {params.out_weight_hex}")

    run_conv(
        ifm_path=params.out_ifm_hex,
        filt_path=packed72_path,
        ofm_path=params.out_golden_hex,
        H=params.height, W=params.width, 
        C=params.cin, M=params.cout
    )
    print(f"[OK] golden generated -> {params.out_golden_hex}")


if __name__ == "__main__":
    # try:
    #     main(sys.argv)
    # except Exception as e:
    #     print(f"[ERROR] {e}", file=sys.stderr)
    #     sys.exit(1)
    main(sys.argv)
