import numpy as np
import math


def run_conv(ifm_data: list[str], filt_72b: list[str],
             H: int, W: int, C: int, M: int, K: int = 3, pad: int = 1) -> list[str]:
    
    GROUPS_PER_PIXEL = C // 4
    ifm = np.zeros((H, W, C), dtype=np.int8)
    
    idx = 0
    for y in range(H):
        for x in range(W):
            for g in range(GROUPS_PER_PIXEL):
                word = ifm_data[idx]; idx += 1
                word_int32 = int(word, 16) & 0xFFFFFFFF
                b = word_int32.to_bytes(4, "little", signed=False)
                ch_base = 4 * g
                ifm[y, x, ch_base:ch_base+4] = np.frombuffer(b, dtype=np.int8)
                
                
    ifm_padded = np.pad(
        ifm, pad_width=((pad, pad), (pad, pad), (0, 0)),
        mode="constant", constant_values=0
    )
    
    
    weights = np.zeros((M, C, K, K), dtype=np.int8)
    pos = 0
    for m in range(M):
        for c_idx in range(C):
            word72 = filt_72b[pos]; pos += 1
            word72_int = int(word72, 16)
            b = word72_int.to_bytes(K*K, "little", signed=False)
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
    
    out: list[str] = []
    
    for y in range(H_out):
        for x in range(W_out):
            for m in range(M):
                v = output[m, y, x] & 0xFFFFFFFF
                out.append(f"{v:08x}")

    return out


def run_affine_from_conv(conv_result: list[str], affine: list[str],
                            H: int, W: int, M: int) -> list[str]:
    
    aff_words = affine
    
    bias_words  = aff_words[:M]
    scale_words = aff_words[M:M*2]

    bias = []
    
    for v in bias_words:
        v_int = int(v, 16)
        if v_int >= 0x8000_0000:
            v_int -= 0x1_0000_0000  # twos-complement to signed
        bias.append(v_int)
    bias = np.array(bias, dtype=np.int32)
    
    
    scale_shift_list = []
    for v in scale_words[:M]:
        v_int = int(v, 16)
        if v_int <= 0:
            shift = 0
        else:
            shift = int(math.log2(v_int)) + 1
        scale_shift_list.append(shift)
    scale_shift = np.array(scale_shift_list, dtype=np.int32)  # (M,)


    # expect 텐서 복원: (M,H,W)로 보관
    ofm_list = []
    for v in conv_result:
        v_int = int(v, 16)
        if v_int >= 0x8000_0000:
            v_int -= 0x1_0000_0000  # twos-complement to signed
        ofm_list.append(v_int)

    ofm_int32 = np.asarray(ofm_list).reshape(H, W, M)
    ofm_int32 = ofm_int32.transpose(2, 0, 1) 
    
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
    
    out: list[str] = []
    for y in range(H):
        for x in range(W):
            m = 0
            while m < M:
                # 부족하면 0 패딩
                v0 = int(ofm_u8[m+0, y, x]) if (m+0) < M else 0
                v1 = int(ofm_u8[m+1, y, x]) if (m+1) < M else 0
                v2 = int(ofm_u8[m+2, y, x]) if (m+2) < M else 0
                v3 = int(ofm_u8[m+3, y, x]) if (m+3) < M else 0
                word = (v0 & 0xFF) | ((v1 & 0xFF) << 8) | ((v2 & 0xFF) << 16) | ((v3 & 0xFF) << 24)
                word_str = f"{word:08x}"
                out.append(word_str.lower())
                m += 4

    return out



def maxpool_from_affine_words(
    words: list[str],
    H: int,
    W: int,
    M: int,
) -> list[str]:
    
    kernel = 2
    stride = 2
    N = M * W * H
    
    arr = []
    for v in words:
        v0 = v[6:8]
        v1 = v[4:6]
        v2 = v[2:4]
        v3 = v[0:2]
        
        v0_int = int(v0, 16)
        v1_int = int(v1, 16)
        v2_int = int(v2, 16)
        v3_int = int(v3, 16)
        arr.append(v0_int)
        arr.append(v1_int)
        arr.append(v2_int)
        arr.append(v3_int)
        
    ofm = np.asarray(arr).reshape(H, W, M)
    ofm = ofm.transpose(2, 0, 1) 
    
    
    # 2) maxpool (VALID, padding 없음)
    outH = 1 + (H - kernel) // stride
    outW = 1 + (W - kernel) // stride
    mp_out = np.zeros((M, outH, outW), dtype=np.uint8)
    
    for m in range(M):
        for oy in range(outH):
            ys = oy * stride
            for ox in range(outW):
                xs = ox * stride
                window = ofm[m, ys:ys+kernel, xs:xs+kernel]
                mp_out[m, oy, ox] = window.max()
                
                
    out_words: list[str] = []
    
    acc = 0
    cnt = 0
    

        
    for y in range(outH):
        for x in range(outW):
            for m in range(M):
                byte = int(mp_out[m, y, x]) & 0xFF
                acc |= (byte << (8 * (cnt % 4)))   # LSB-first
                cnt += 1
                if cnt % 4 == 0:
                    out_words.append(f"{acc:08x}")
                    acc = 0

    return out_words