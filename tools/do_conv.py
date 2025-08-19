import numpy as np
from pathlib import Path


def run_conv(ifm_path: Path, filt_path: Path, ofm_path: Path,
             H: int, W: int, C: int, M: int, K: int = 3, pad: int = 1):
    
    ofm_path.parent.mkdir(parents=True, exist_ok=True)
    GROUPS_PER_PIXEL = C // 4

    def read_hex32_file(path: Path) -> list[int]:
        vals = []
        with path.open("r", encoding="utf-8") as f:
            for raw in f:
                s = raw.strip()
                if not s:
                    continue
                vals.append(int(s, 16) & 0xFFFFFFFF)
        return vals

    # -------------------------------
    # IFM 로드
    ifm_words = read_hex32_file(ifm_path)
    ifm = np.zeros((H, W, C), dtype=np.int8)
    idx = 0
    for y in range(H):
        for x in range(W):
            for g in range(GROUPS_PER_PIXEL):
                word = ifm_words[idx]; idx += 1
                b = word.to_bytes(4, "little", signed=False)
                ch_base = 4 * g
                ifm[y, x, ch_base:ch_base+4] = np.frombuffer(b, dtype=np.int8)

    ifm_padded = np.pad(
        ifm, pad_width=((pad, pad), (pad, pad), (0, 0)),
        mode="constant", constant_values=0
    )

    # -------------------------------
    # 가중치 로드
    f_lines = []
    with filt_path.open("r", encoding="utf-8") as f:
        for raw in f:
            s = raw.strip()
            if not s:
                continue
            f_lines.append(int(s, 16))

    weights = np.zeros((M, C, K, K), dtype=np.int8)
    pos = 0
    for m in range(M):
        for c_idx in range(C):
            word72 = f_lines[pos]; pos += 1
            b = word72.to_bytes(K*K, "little", signed=False)
            w = np.frombuffer(b, dtype=np.int8).reshape(K, K)
            weights[m, c_idx] = w

    # -------------------------------
    # Convolution
    H_out, W_out = H, W
    output = np.zeros((M, H_out, W_out), dtype=np.int32)
    for m in range(M):
        for y in range(H_out):
            for x in range(W_out):
                acc = 0
                for c_idx in range(C):
                    patch = ifm_padded[y:y+K, x:x+K, c_idx].astype(np.int32)
                    acc += int(np.sum(patch * weights[m, c_idx].astype(np.int32)))
                output[m, y, x] = acc

    print("result shape =", output.shape)

    # -------------------------------
    # 결과 저장
    with ofm_path.open("w", encoding="utf-8") as fw:
        for y in range(H_out):
            for x in range(W_out):
                for m in range(M):
                    v = output[m, y, x] & 0xFFFFFFFF
                    fw.write(f"{v:08x}\n")

    return output