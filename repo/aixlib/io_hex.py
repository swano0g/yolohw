from pathlib import Path
from typing import Any, List



def read_32b_hex_lines(path: Path) -> List[str]:
    lines: List[str] = []
    with path.open("r", encoding="utf-8") as f:
        for raw in f:
            s = raw.strip()
            if not s:
                continue
            int(s, 16)  # ValueError 유발 용도
            lines.append(s.lower())
    return lines



def write_hex_lines(out_path: Path, hex: list[str]) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    
    with out_path.open("w", encoding="utf-8") as fw:
        for s in hex:
            fw.write(s + "\n")