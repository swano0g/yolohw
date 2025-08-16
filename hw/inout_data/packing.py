import sys
from pathlib import Path

# 32bit param_weight -> 72bit packing
input_path  = "hw\\inout_data\\param\\CONV04_param_weight.hex"
output_path = "hw\\inout_data\\param_packed\\CONV04_param_packed_weight.hex"


def pack_32_to_72(in_path: str | Path, out_path: str | Path) -> None:
    in_path = Path(in_path)
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    # 입력 파일 읽기
    bytes_lsb: list[str] = []
    with in_path.open("r", encoding="utf-8") as f:
        for line_no, raw in enumerate(f, 1):
            s = raw.strip()
            if not s:
                continue

            
            val = int(s, 16)
            lsb = val & 0xFF
            bytes_lsb.append(f"{lsb:02x}")
    
    # kernel check
    if len(bytes_lsb) % 9 != 0:
        raise ValueError(f"file length error: {len(bytes_lsb)}")


    with out_path.open("w", encoding="utf-8") as fw:
        for i in range(0, len(bytes_lsb), 9):
            group = bytes_lsb[i:i+9]
            packed = "".join(reversed(group))
            fw.write(packed.lower() + "\n")

if __name__ == "__main__":
    pack_32_to_72(input_path, output_path)
    print(f"success: '{output_path}'")