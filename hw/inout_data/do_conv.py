import numpy as np
from pathlib import Path

# ifm_path  = Path("hw\\inout_data\\feamap\\CONV04_input_32b.hex")
# filt_path = Path("hw\\inout_data\\param_packed\\CONV04_param_packed_weight.hex")
# ofm_path  = Path("hw\\inout_data\\expect\\CONV04_output_32b.hex")

ifm_path  = Path("hw\\inout_data\\feamap\\test_small_input_32b.hex")
filt_path = Path("hw\\inout_data\\param_packed\\test_small_param_packed_weight.hex")
ofm_path  = Path("hw\\inout_data\\expect\\test_small_output_32b.hex")

ofm_path.parent.mkdir(parents=True, exist_ok=True)

H   = 16     # input height
W   = 16     # input width
C   = 16   # input channel
M   = 32     # output channel
K   = 3      # kernel
pad = 1      # padding
GROUPS_PER_PIXEL = C // 4


def read_hex32_file(path: Path) -> list[int]:
    vals = []
    with path.open("r", encoding="utf-8") as f:
        for ln_no, raw in enumerate(f, 1):
            s = raw.strip()
            if not s:
                continue
            v = int(s, 16) & 0xFFFFFFFF
            vals.append(v)
    return vals

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
    ifm,
    pad_width=((pad, pad), (pad, pad), (0, 0)),
    mode="constant",
    constant_values=0
)

# print(ifm.shape, ifm.dtype)              # (64, 64, 32) uint8
# print("ifm[0,0,0:8] =", ifm[0, 0, 0:8])  # (0,0)


f_lines = []
with filt_path.open("r", encoding="utf-8") as f:
    for ln, raw in enumerate(f, 1):
        s = raw.strip()
        if not s:
            continue
        val = int(s, 16)
        f_lines.append(val)


weights = np.zeros((M, C, K, K), dtype=np.int8)
pos = 0
for m in range(M):
    for c_idx in range(C):
        word72 = f_lines[pos]; pos += 1
        b = word72.to_bytes(K*K, "little", signed=False) 
        w = np.frombuffer(b, dtype=np.int8).reshape(K, K)
        weights[m, c_idx] = w


# print(weights.shape, weights.dtype)              # (64, 64, 32) uint8
# print(weights)

# -------------------------------
# CONV cal
H_out, W_out = H, W
output = np.zeros((M, H_out, W_out), dtype=np.int32)

for m in range(M):
    for y in range(H_out):
        for x in range(W_out):
            acc = 0
            for c_idx in range(C):
                patch = ifm_padded[y:y+K, x:x+K, c_idx].astype(np.int32)  # (3,3)
                acc += int(np.sum(patch * weights[m, c_idx].astype(np.int32)))
            output[m, y, x] = acc

print("result shape =", output.shape)  # (M,H,W)


with ofm_path.open("w", encoding="utf-8") as fw:
    # for m in range(M):
    #     for y in range(H_out):
    #         for x in range(W_out):
    #             v = output[m, y, x] & 0xFFFFFFFF
    #             fw.write(f"{v:08x}\n")

    for y in range(H_out):
        for x in range(W_out):
            for m in range(M):
                v = output[m, y, x] & 0xFFFFFFFF
                fw.write(f"{v:08x}\n")