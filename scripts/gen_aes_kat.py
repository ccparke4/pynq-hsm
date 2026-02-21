#!/usr/bin/env python3

"""
python implementation of AES-256 for golden vector gen.

Generates:
   vectors/aes_kat.hex     N test Vectors:
                            line 0: key[255:128] (upper bits)
                            line 1: key[127:0]   (lower bits)
                            line 2: plaintext [127:0]
                            line 3: ciphertext[127:0]                 

    vectors/aes_key_exp.hex  key schedule check --> W[8].. W[11] for vector 0

    Ref: FIPS 197 (AES), Appdix A.3 (AES-256 key expansion),
         Appendix C.3 (AES encryption example)
"""

import os
import struct

# GF (2^8) aritmetic
def gf_mul(a, b):
    result = 0
    for _ in range(8):
        if b & 1:
            result ^= a
        hi = a & 0x80
        a = (a << 1) & 0xFF
        if hi:
            a ^= 0x1B
        b >>= 1
    return result

def gf_inv(a):
    if a == 0:
        return 0
    for b in range(1, 256):
        if gf_mul(a, b) == 1:
            return b

def affine(b):
    """AES affine transformation — FIPS 197 Section 5.1.1."""
    result = 0
    for i in range(8):
        bit = (
            ((b >> i) & 1) ^
            ((b >> ((i + 4) % 8)) & 1) ^
            ((b >> ((i + 5) % 8)) & 1) ^
            ((b >> ((i + 6) % 8)) & 1) ^
            ((b >> ((i + 7) % 8)) & 1) ^
            ((0x63 >> i) & 1)
        )
        result |= bit << i
    return result

# buld sBox from math
SBOX = [affine(gf_inv(i)) for i in range(256)]

# AES-256 Round ops ===================================
def sub_bytes(state):
    return [SBOX[b] for b in state]

def shift_rows(state):
    """ State is 16'B in col-major order:
    [ s0 s4 s8  s12 ]
    [ s1 s5 s9  s13 ]
    [ s2 s6 s10 s14 ]
    [ s3 s7 s11 s15 ]
    """
    out = [0] * 16
    for r in range(4):
        for c in range(4):
            out[r + 4 * c] = state[r + 4 * ((c + r) % 4)]
    
    return out

def mix_columns(state):
    """ mixcols: GF(2^8) multiplication """
    def xtime(a):
        return ((a << 1) ^ 0x1B) & 0xFF if a & 0x80 else (a << 1) & 0xFF
    
    out = list(state)
    for c in range(4):
        i = 4 * c
        a0, a1, a2, a3 = state[i], state[i+1], state[i+2], state[i+3]
        tmp = a0 ^ a1 ^ a2 ^ a3
        out[i]   = a0 ^ tmp ^ xtime(a0 ^ a1)
        out[i+1] = a1 ^ tmp ^ xtime(a1 ^ a2)
        out[i+2] = a2 ^ tmp ^ xtime(a2 ^ a3)
        out[i+3] = a3 ^ tmp ^ xtime(a3 ^ a0)
    return out

def add_round_key(state, round_key):
    """ XOR state with round key """
    return [s ^ k for s, k in zip(state, round_key)]

# AES-256 key expansion - FIPS 197 S5.2 ===========================
RCON = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40]

def key_expansion_256(key_bytes):
    """ expand 32'B key into 60 x 32'b words, returns list of 60 ints, each 32'b word """
    # W[0..7] from key directly
    W = []
    for i in range(8):
        W.append(int.from_bytes(key_bytes[4*i:4*(i+1)], 'big'))

    for i in range(8, 60):
        temp = W[i - 1]
        if i % 8 == 0:
            # rotword
            temp = ((temp << 8) | (temp >> 24)) & 0xFFFFFFFF
            # subword
            temp = ((SBOX[(temp >> 24) & 0xFF] << 24) |
                    (SBOX[(temp >> 16) & 0xFF] << 16) |
                    (SBOX[(temp >> 8) & 0xFF]  << 8) |
                    SBOX[  temp       & 0xFF])
            # XOR Rcon
            temp ^= (RCON[(i // 8) - 1] << 24)
        elif i % 8 == 4:
            # subword only
            temp = ((SBOX[(temp >> 24) & 0xFF] << 24) |
                    (SBOX[(temp >> 16) & 0xFF] << 16) |
                    (SBOX[(temp >> 8) & 0xFF]  << 8) |
                    SBOX[  temp       & 0xFF])
        W.append(W[i - 8] ^ temp)

    return W

def get_round_key(W, rnd):
    """ Extract 16'B round key for round rnd from W[] """
    rk = []
    for w_idx in range(4 * rnd, 4 * rnd + 4):
        w = W[w_idx]
        rk.extend([(w >> 24) & 0xFF, (w >> 16) & 0xFF, (w >> 8) & 0xFF, w & 0xFF])

    return rk

# AES encrpyt 14 rounds =============================================

def aes256_encrypt(key_bytes, pt_bytes):
    """ Encrypt 16'B plaintext with 32'B key, returns 16'B ciphertext """
    W = key_expansion_256(key_bytes)

    # state is col-major: state[row + 4*col]
    state = list(pt_bytes)

    # Initial AddRoundKey
    state = add_round_key(state, get_round_key(W, 0))

    # Rounds 1..13
    for rnd in range(1, 14):
        state = sub_bytes(state)
        state = shift_rows(state)
        state = mix_columns(state)
        state = add_round_key(state, get_round_key(W, rnd))

    # round 14: subbytes, shiftrows, addroundkey (no mixcols)
    state = sub_bytes(state)
    state = shift_rows(state)
    state = add_round_key(state, get_round_key(W, 14))

    return bytes(state), W

# Test Vctors =============================================

VECTORS = [
    #vector 0: NIST FIPS 197 Appendix C.3 - canonical AES-256 test
    {
        "name": "FIPS 197 C.3",
        "key": bytes.fromhex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"),
        "pt":  bytes.fromhex("00112233445566778899aabbccddeeff"),
        "ct":  bytes.fromhex("8ea2b7ca516745bfeafc49904b496089")
    },
    # vector 1: all-zeros key & plain text
    {
        "name": "All zeros",
        "key": bytes(32),
        "pt":  bytes(16),
        "ct":  bytes.fromhex("dc95c078a2408989ad48a21492842087")
    }, 
    # vector 2: all-ones key & plain plaintext
    {
        "name": "All 0xFF",
        "key": bytes([0xFF] * 32),
        "pt":  bytes([0xFF] * 16),
        "ct":  bytes.fromhex("d5f93d6d3311cb309f23621b02fbd5e2"),
    }
]

# Validation and output =============================================

def bytes_to_hex128(b):
    return b.hex()

def word32_to_hex(w):
    return f"{w:08x}"

def validate_and_generate():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = (os.path.dirname(script_dir)
                if os.path.basename(script_dir) == "scripts" else script_dir)
    vec_dir = os.path.join(repo_root, "vectors")
    os.makedirs(vec_dir, exist_ok=True)

    print("===============================")
    print(" AES-256 Golden Vector Generation")
    print(" Ref: FIPS 197, pure python implemntation")
    print("===============================")

    #validate against known test vectors
    all_ok = True
    all_W = []

    for idx, v in enumerate(VECTORS):
        ct_got, W = aes256_encrypt(v["key"], v["pt"])
        all_W.append(W)

        match = (ct_got == v["ct"])
        status = "PASS" if match else "FAIL"
        print(f"Vector {idx}: {v['name']}: {status}")

        if not match:
            print(f"  Expected: {bytes_to_hex128(v['ct'])}")
            print(f"  Got     : {bytes_to_hex128(ct_got)}")
            all_ok = False

    if not all_ok:
        raise SystemExit("Validation failed — AES implementation has a bug.")

    print(f"   All {len(VECTORS)} test vectors passed.")
    print("")

    # write KAT vectors: 4 lines per vector
    # line 0: key[255:128] (upper bits)
    # line 1: key[127:0]   (lower bits)
    # line 2: plaintext [127:0]
    # line 3: ciphertext[127:0]
    kat_path = os.path.join(vec_dir, "aes_kat.hex")
    with open(kat_path, "w") as f:
        for v in VECTORS:
            f.write(bytes_to_hex128(v["key"][:16]) + "\n")
            f.write(bytes_to_hex128(v["key"][16:]) + "\n")
            f.write(bytes_to_hex128(v["pt"]) + "\n")
            f.write(bytes_to_hex128(v["ct"]) + "\n")
    print(f"  Written: {kat_path}  ({len(VECTORS)} vectors)")

    # write key expansion check vector: W[8]..W[11] for vector 0
    # these are the first 4 computed words loadded directly
    W0 = all_W[0]
    kexp_path = os.path.join(vec_dir, "aes_key_exp.hex")
    with open(kexp_path, "w") as f:
        for wi in range(8, 12):
            f.write(word32_to_hex(W0[wi]) + "\n")

    print(f"  Written: {kexp_path}  (W[8]..W[11] for vector 0)")

    # print key schedule values for ref
    print("")
    print("  Key schedule spot-check (vector 0):")
    for wi in range(8, 12):
        print(f"    W[{wi}] = 0x{word32_to_hex(W0[wi])}")

    print("")
    print("==============================================")

if __name__ == "__main__":
    validate_and_generate()


