/**
* @file test_aes.cpp
* @brief AES256 Hardware verification test on PYNQZ2
* @details Runs NIST KAT vectors against the AES Core via AXI-Lite interface
*          Uses same vectors as in simulation verif.
*
* 1. write key
* 2. write AES_CTRL
* 3. poll AES_status until done
* 4. write PTEXT_W
* 5. write AES_CTRL to trigger encryption
* 6. poll AES_status until done
* 7. read CTEXT_R and compare to expected
* 8. AES_CTRL to clear
*/

#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>

// HW Config =======================================
constexpr uint32_t AES_BASE_ADDR = 0x40001000;
constexpr uint32_t AES_SIZE = 0x1000;           // 4KB

// AES Reg map =======================================
namespace AES {
    // offsets (byte addrs) - from aes_axi_wrapper.sv
    constexpr uint32_t CTRL       = 0x00; // control reg
    constexpr uint32_t STATUS     = 0x04; // status reg
    constexpr uint32_t KEY_W0     = 0x10; // key word [255:224]
    constexpr uint32_t KEY_W1     = 0x14; // key word [223:192]
    constexpr uint32_t KEY_W2     = 0x18; // key word [191:160]
    constexpr uint32_t KEY_W3     = 0x1C; // key word [159:128]
    constexpr uint32_t KEY_W4     = 0x20; // key word [127:96]
    constexpr uint32_t KEY_W5     = 0x24; // key word [95:64]
    constexpr uint32_t KEY_W6     = 0x28; // key word [63:32]
    constexpr uint32_t KEY_W7     = 0x2C; // key word [31:0]
    constexpr uint32_t PTEXT_W0   = 0x30; // plaintext word [127:96]
    constexpr uint32_t PTEXT_W1   = 0x34; // plaintext word [95:64]
    constexpr uint32_t PTEXT_W2   = 0x38; // plaintext word [63:32]
    constexpr uint32_t PTEXT_W3   = 0x3C; // plaintext word [31:0]
    constexpr uint32_t CTEXT_W0   = 0x40; // ciphertext word [127:96]
    constexpr uint32_t CTEXT_W1   = 0x44; // ciphertext word [95:64]
    constexpr uint32_t CTEXT_W2   = 0x48; // ciphertext word [63:32]
    constexpr uint32_t CTEXT_W3   = 0x4C; // ciphertext word [31:0]

    // control bits
    constexpr uint32_t CTRL_KEY_LOAD = 0x1;
    constexpr uint32_t CTRL_ENCRYPT  = 0x2;
    constexpr uint32_t CTRL_CLEAR    = 0x4;

    // status bits
    constexpr uint32_t STATUS_READY = 0x1; 
    constexpr uint32_t STATUS_BUSY  = 0x2;
    constexpr uint32_t STATUS_DONE = 0x4;
}

// MMIO helper =======================================
class MMIO {
public:
    volatile uint32_t* base_ptr = nullptr;
    int fd = -1;
    uint32_t map_size;

    bool open(uint32_t base, uint32_t size) {
        map_size = size;
        fd = ::open("/dev/mem", O_RDWR | O_SYNC);
        if (fd < 0) { perror("open /dev/mem"); return false; }
        base_ptr = (volatile uint32_t*)mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, base);
        if (base_ptr == MAP_FAILED) { perror("mmap"); ::close(fd); return false; }
        return true;
    }

    void close() {
        if (base_ptr && base_ptr != MAP_FAILED) munmap((void*)base_ptr, map_size);
        if (fd >= 0) ::close(fd);
    }

    void write(uint32_t offset, uint32_t value) { base_ptr[offset / 4] = value; }
    uint32_t read(uint32_t offset) { return base_ptr[offset / 4]; }
};

// AES driver functions =======================================

bool poll_status(MMIO& aes, uint32_t mask, int timeout_us = 1000000) {
    for (int i = 0; i < timeout_us; i++) {
        uint32_t status = aes.read(AES::STATUS);
        if ((status & mask) == mask) return true;
        usleep(1);
    }
    return false;
}

bool aes_load_key(MMIO& aes, const uint32_t key[8]) {
    // write 8 key words
    aes.write(AES::KEY_W0, key[0]);
    aes.write(AES::KEY_W1, key[1]);
    aes.write(AES::KEY_W2, key[2]);
    aes.write(AES::KEY_W3, key[3]);
    aes.write(AES::KEY_W4, key[4]);
    aes.write(AES::KEY_W5, key[5]);
    aes.write(AES::KEY_W6, key[6]);
    aes.write(AES::KEY_W7, key[7]);

    // strobe key load
    aes.write(AES::CTRL, 0);
    aes.write(AES::CTRL, AES::CTRL_KEY_LOAD);
    aes.write(AES::CTRL, 0);

    // wait for ready
    if (!poll_status(aes, AES::STATUS_READY)) {
        printf("    [TIMEOUT] Key expansion did not complete\n");
        return false;
    }
    return true;
}

bool aes_encrypt(MMIO& aes, const uint32_t pt[4], uint32_t ct_out[4]) {
    // write 4 plaintext words
    aes.write(AES::PTEXT_W0, pt[0]);
    aes.write(AES::PTEXT_W1, pt[1]);
    aes.write(AES::PTEXT_W2, pt[2]);
    aes.write(AES::PTEXT_W3, pt[3]);

    // strobe encrypt
    aes.write(AES::CTRL, 0);
    aes.write(AES::CTRL, AES::CTRL_ENCRYPT);
    aes.write(AES::CTRL, 0);

    // wait for done
    if (!poll_status(aes, AES::STATUS_DONE)) {
        printf("    [TIMEOUT] Encryption did not complete\n");
        return false;
    }

    // read ciphertext    ct_out[0] = aes.read(AES::CTEXT_W0);
    ct_out[0] = aes.read(AES::CTEXT_W0);
    ct_out[1] = aes.read(AES::CTEXT_W1);
    ct_out[2] = aes.read(AES::CTEXT_W2);
    ct_out[3] = aes.read(AES::CTEXT_W3);

    // clear done latch
    aes.write(AES::CTRL, AES::CTRL_CLEAR);
    aes.write(AES::CTRL, 0);

    return true;
}

// Test Vectors ================================================
struct AESTestVector {
    const char* name;
    uint32_t key[8];
    uint32_t pt[4];
    uint32_t ct[4];
};

// words are big endian
const AESTestVector VECTORS[] = {
    // vector 0 from NIST FIPS 197 C.3
    {
        .name = "NIST FIPS 197 C.3",
        .key = {0x00010203, 0x04050607, 0x08090a0b, 0x0c0d0e0f, 0x10111213, 0x14151617, 0x18191a1b, 0x1c1d1e1f},
        .pt = {0x00112233, 0x44556677, 0x8899aabb, 0xccddeeff},
        .ct = {0x8ea2b7ca, 0x516745bf, 0xeafc4990, 0x4b496089}
    },
    // vector 1 all zeros
    {
        .name = "All Zeros",
        .key = {0,0,0,0,0,0,0,0},
        .pt = {0,0,0,0},
        .ct = {0xdc95c078, 0xa2408989, 0xad48a214, 0x92842087} // TODO: fill in correct expected ciphertext
    },
    // vector 2 all 1s
    {
        .name = "All 0xFF",
        .key = {0xFFFFFFFF,0xFFFFFFFF,0xFFFFFFFF,0xFFFFFFFF,0xFFFFFFFF,0xFFFFFFFF,0xFFFFFFFF,0xFFFFFFFF},
        .pt = {0xFFFFFFFF,0xFFFFFFFF,0xFFFFFFFF,0xFFFFFFFF},
        .ct = {0xd5f93d6d, 0x3311cb30, 0x9f23621b, 0x02fbd5e2} // TODO: fill in correct expected ciphertext
    }
};

const int NUM_VECTORS = sizeof(VECTORS) / sizeof(VECTORS[0]);

// helpers ================================================
void print_128(const char* label, const uint32_t w[4]) {
    printf("    %s: %08x_%08x_%08x_%08x\n", label, w[0], w[1], w[2], w[3]);
}

bool compare_128(const uint32_t a[4], const uint32_t b[4]) {
    return (a[0] == b[0]) && (a[1] == b[1]) && (a[2] == b[2]) && (a[3] == b[3]);
}

// Main Test ================================================
int main() {
    printf("================================================\n");
    printf("  AES-256 Hardware Verification\n");
    printf("  Target: PYNQ-Z2 @ 0x%08X\n", AES_BASE_ADDR);
    printf("  Vectors: %d (same as sim tb_aes_core.sv)\n", NUM_VECTORS);
    printf("================================================\n");

    MMIO aes;
    if (!aes.open(AES_BASE_ADDR, AES_SIZE)) {
        printf("[FATAL] Cannot map AES peripheral. Check:\n");
        printf("  1. Running as root (sudo)\n");
        printf("  2. Bitstream is programmed\n");
        printf("  3. AES_BASE_ADDR matches Vivado Address Editor\n");
        return EXIT_FAILURE;
    }
    // santiy read status before anything -------
    uint32_t status = aes.read(AES::STATUS);
    printf("[INFO] Initial AES Status: 0x%08X\n", status);
    printf("       (ready=%d, busy=%d, error=%d)\n", 
                    (status & AES::STATUS_READY) != 0, 
                    (status & AES::STATUS_BUSY) != 0, 
                    (status & AES::STATUS_DONE) != 0);

    // run KAT vectors ----------------------------
    int pass_count = 0; int fail_count = 0;
    for (int i = 0; i < NUM_VECTORS; i++) {
        const AESTestVector& vec = VECTORS[i];
        uint32_t ct_got[4] = {0};

        printf("\n  --- Vector %d: %s ---\n", i, vec.name);
        print_128("Key hi", vec.key);
        print_128("Key lo", vec.key + 4);
        print_128("Plaintext", vec.pt);

        // 1. load key
        if (!aes_load_key(aes, vec.key)) {
            printf("    [FAIL] Key load failed\n");
            fail_count++;
            continue;
        }

        // 2. encrypt
        if (!aes_encrypt(aes, vec.pt, ct_got)) {
            printf("    [FAIL] Encryption failed\n");
            fail_count++;
            continue;
        }

        // 3. compare
        print_128("Ciphertext got", ct_got);
        print_128("Ciphertext exp", vec.ct);

        if (compare_128(ct_got, vec.ct)) {
            printf("    [PASS] Ciphertext matches expected\n");
            pass_count++;
        } else {
            printf("    [FAIL] Ciphertext does NOT match expected\n");
            fail_count++;
        }
    }
    // summary --------------------------------------
    printf("\n================================================\n");
    printf("  Test Summary: %d/%d passed, %d failed\n", pass_count, NUM_VECTORS, fail_count);
    printf("================================================\n");

    if (fail_count == 0) {
        printf("[OVERALL PASS] AES core is functioning correctly!\n");
        printf(" AES-256 hardware verification successful. All test vectors passed.\n");
    } else {
        printf("[OVERALL FAIL] Some tests failed. Check above for details.\n");
    }

    aes.close();
    return (fail_count == 0) ? EXIT_SUCCESS : EXIT_FAILURE;
}
