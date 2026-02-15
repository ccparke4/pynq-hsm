#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <stdint.h>

// --- HW ADDRESSES ---
#define HSM_BASE_ADDR       0x40000000
#define HSM_SIZE            0x1000          // 4KB

// --- REG OFFSETS ---
#define REG_CTRL        0 // 0x00
#define REG_STATUS      1 // 0x04
#define REG_DATA_IN     2 // 0x08
#define REG_DATA_OUT    3 // 0x0C

int main() {
    int dh = open("/dev/mem", O_RDWR | O_SYNC);
    if(dh == -1) {
        perror("Error opening /dev/mem");
        return -1;
    }

    // map physical address 0x4000_0000 into our programs history
    uint32_t* hsm_ptr = (uint32_t*)mmap(NULL, HSM_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, dh, HSM_BASE_ADDR);

    if (hsm_ptr == MAP_FAILED) {
        perror("Mmap failed");
        close(dh);
        return -1;
    }

    printf("=== HSM TEST ===\n");
    printf("Mapped HSM HW @ 0x%08X\n", HSM_BASE_ADDR);

    // 1. write to data in reg
    uint32_t test_val = 0xDEADBEEF;
    printf("Writing 0x%08X to Data input (reg2)...\n", test_val);
    hsm_ptr[REG_DATA_IN] = test_val;

    // 2. Read it back
    uint32_t read_back = hsm_ptr[REG_DATA_IN];
    printf("Read baack: 0x%08X\n", read_back);

    if (read_back == test_val) 
        printf("[PASS] AXI-Lite W/R success!\n");
    else
        printf("[FAIL] Data Mismatch... Expected 0x%08X, got 0x%08X\n", test_val, read_back);

    // 3. test control
    printf("Writing 0x1 (Start) to control (Reg 0)...\n");
    hsm_ptr[REG_CTRL] = 0x1;
    printf("Control Reg is no: 0x%08X\n", hsm_ptr[REG_CTRL]);

    // clean up
    munmap(hsm_ptr, HSM_SIZE);
    close(dh);
    return 0;
}