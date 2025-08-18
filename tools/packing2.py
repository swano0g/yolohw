import sys
from pathlib import Path
from typing import Optional, Tuple

# 32bit param_weight -> 32bit packed (4 cout 묶음, LSB 1byte만 사용)
input_path  = "hw\\inout_data\\param\\CONV04_param_weight.hex"
output_path = "hw\\inout_data\\param_packed\\CONV04_param_packed_weight_4in1.hex"


Cin = 16
Cout = 32


def read_lsb_bytes(in_path: Path) -> list[str]:
    bytes_lsb: list[str] = []
    with in_path.open("r", encoding="utf-8") as f:
        for line_no, raw in enumerate(f, 1):
            s = raw.strip()
            if not s:
                continue
            val = int(s, 16)
            lsb = val & 0xFF
            bytes_lsb.append(f"{lsb:02x}")
    return bytes_lsb


def pack_group_of_4_cout_to_32(in_path: str | Path, out_path: str | Path, Cin: int, Cout: int):
    in_path = Path(in_path)
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    bytes_lsb = read_lsb_bytes(in_path)

    with out_path.open("w", encoding="utf-8") as fw:
        # cout을 4개씩 그룹
        for cg in range(0, Cout, 4):
            # 각 cin, k에 대해 하나의 32비트 워드 생성
            for cin in range(Cin):
                for k in range(9):
                    # 각 cout의 동일 (cin, k) 위치 바이트를 수집
                    idxs = [(((cout * Cin) + cin) * 9) + k for cout in (cg, cg+1, cg+2, cg+3)]
                    b = [bytes_lsb[i] for i in idxs]

                    # little endian
                    packed32 = f"{b[3]}{b[2]}{b[1]}{b[0]}"
                    fw.write(packed32.lower() + "\n")


if __name__ == "__main__":
    pack_group_of_4_cout_to_32(input_path, output_path, Cin, Cout)
    print(f"success: '{output_path}'")
