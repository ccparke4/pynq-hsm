#!/usr/bin/env python3

"""
gen_kinj_golden.py

Computes expected ciphertexts for mock TRNG keys used in tb_key_inect.sv.
Same aes implementation as gen_aes_kay.py

Gens:
    vectors/kinj_golden.hex   (256 lines, one byte per line)
        line 0: ct for mock key A encrypting all-zero plaintext
        line 1: ct for mock key B encrypting all-zero plaintext

Mock keys to match tb_key_inject.sv 
    key a = DEADBEEF_CAFEBABE_12345678_9ABCDEF0_FEDCBA98_76543210_AAAA5555_0F0FF0F0
    key b = 11111111_22222222_33333333_44444444_55555555_66666666_77777777_88888888
"""

import os 
import sys

# import AES from gen_aes_key.py
script_dir = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, script_dir)
from gen_aes_kat import aes256_encrypt

# mock keys - match tb_key_inject.sv
MOCK_KEY_A = [
    0xDEADBEEF, 0xCAFEBABE, 0x12345678, 0x9ABCDEF0,
    0xFEDCBA98, 0x76543210, 0xAAAA5555, 0x0F0FF0F0
]

MOCK_KEY_B = [
    0x11111111, 0x22222222, 0x33333333, 0x44444444,
    0x55555555, 0x66666666, 0x77777777, 0x88888888
]

def word_to_bytes(words):
    result = b""
    for w in words:
        result += w.to_bytes(4, byteorder="big")
    return result

def main():
    key_a = word_to_bytes(MOCK_KEY_A)
    key_b = word_to_bytes(MOCK_KEY_B)
    plaintext = bytes(16)  # all-zero plaintext

    ct_a = aes256_encrypt(plaintext, key_a)
    ct_b = aes256_encrypt(plaintext, key_b)

    print(f"  Key A: {key_a.hex()}")
    print(f"  PT:    {plaintext.hex()}")
    print(f"  CT A:  {ct_a.hex()}")
    print()
    print(f"  Key B: {key_b.hex()}")
    print(f"  PT:    {plaintext.hex()}")
    print(f"  CT B:  {ct_b.hex()}")

    # ensure they differ
    assert ct_a != ct_b, "Expected different ciphertexts for different keys"
    print()
    print ("Success: Generated distinct ciphertexts for mock keys A and B.")

    # write hex fil
    repo_root = (os.path.dirname(script_dir)
                 if os.path.basename(repo_root) == "scripts" else script_dir)
    vec_dir = os.path.join(repo_root, "vectors")
    os.makedirs(vec_dir, exist_ok=True)

    out_path = os.path.join(vec_dir, "kinj_golden.hex")
    with open(out_path, "w") as f:
        f.write(f"{ct_a.hex()}\n")
        f.write(f"{ct_b.hex()}\n")

    print(f"  Written: {out_path}  (2 entries)")

if __name__ == "__main__":
    main()
    