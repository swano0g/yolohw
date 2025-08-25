from .utils import TCParams, read_lsb_1byte


def pack_filter_72b(params: TCParams, filter_src: list[str]) -> list[str]:
    src_lines = read_lsb_1byte(filter_src)
    out: list[str] = []
    
    for i in range(0, len(src_lines), 9):
        group = src_lines[i:i+9]
        packed = "".join(reversed(group))
        out.append(packed)
        
    return out



def pack_filter_32b(params: TCParams, filter_src: list[str]) -> list[str]:
    src_lines = read_lsb_1byte(filter_src)
    out: list[str] = []
    
    for cg in range(0, params.cout, 4):
        # 각 cin, k에 대해 하나의 32비트 워드 생성
        for ci in range(params.cin):
            for k in range(9):
                # 각 cout의 동일 (cin, k) 위치 바이트를 수집
                idxs = [(((co * params.cin) + ci) * 9) + k for co in (cg, cg+1, cg+2, cg+3)]
                b = [src_lines[i] for i in idxs]

                # little endian
                packed32 = f"{b[3]}{b[2]}{b[1]}{b[0]}"
                out.append(packed32)
                
    return out


# ------------------------------
# AFFINE 패킹 (bias + scale)
# ------------------------------
def pack_affine(params: TCParams, bias_src: list[str], scale_src: list[str]) -> list[str]:
    out: list[str] = []
    for c in range(params.cout):
        out.append(bias_src[c])
    for c in range(params.cout):
        out.append(scale_src[c])
        
    return out