#!/usr/bin/env python3
"""
gen_sbox_golden.py

Computes AES S-box from GF(2^8) math and writes a hex file
consumed by tb_aes_sbox.sv via $readmemh.

Usage (from repo root or scripts/):
    python scripts/gen_sbox_golden.py

Output:
    vectors/sbox_golden.hex   (256 lines, one byte per line)
    Matches VEC_DIR := $(PROJECT_ROOT)/vectors in sim.mk
"""

import os

# ============================================================
# GF(2^8) arithmetic — irreducible polynomial 0x11B
# ============================================================

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

def compute_sbox():
    return [affine(gf_inv(i)) for i in range(256)]

# ============================================================
# Sanity check against known FIPS 197 Figure 7 values
# ============================================================

SPOT_CHECKS = {
    0x00: 0x63,
    0x01: 0x7c,
    0x53: 0xed,
    0xac: 0x91,
    0xff: 0x16,
}

def verify(sbox):
    ok = True
    for inp, expected in SPOT_CHECKS.items():
        if sbox[inp] != expected:
            print(f"  ERROR: SBOX[0x{inp:02x}] = 0x{sbox[inp]:02x}, expected 0x{expected:02x}")
            ok = False
    return ok

# ============================================================
# Write hex file for $readmemh — one byte per line, no prefix
# ============================================================

def write_hex(sbox, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        for val in sbox:
            f.write(f"{val:02x}\n")
    print(f"  Written: {path}  ({len(sbox)} entries)")

if __name__ == "__main__":
    print("================================")
    print(" Generating sbox_golden.hex")
    print("================================")

    sbox = compute_sbox()

    print("Verifying against FIPS 197 spot-checks...")
    if not verify(sbox):
        raise SystemExit("Spot-check failed — GF computation has a bug.")
    print("  All spot-checks OK.")

    # Output to vectors/ relative to repo root.
    # Script may be run from repo root OR from scripts/ — handle both.
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root  = os.path.dirname(script_dir) if os.path.basename(script_dir) == "scripts" else script_dir
    out_path   = os.path.join(repo_root, "vectors", "sbox_golden.hex")

    write_hex(sbox, out_path)
    print("================================")