/**
* @file     test_trng.cpp
* @brief    TRNG Hardware test for PYNQ-Z2
* 
* Tests:
* T1 - Enabling osc
* T2 - Reading raw osc outputs
* T3 - sample trig
* T4 - Collecting rand data
*/

#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>

/* HW config */
constexpr uint32_t HSM_BASE_ADDR = 0x40000000;
constexpr uint32_t HSM_SIZE = 0x10000;

/* TRNG register offsets */
namespace REG {
    constexpr uint32_t CTRL     = 0x00; // [0]=enable, [1]=sample, [2]=clear
    constexpr uint32_t STATUS   = 0x04; // [0]=running, [7:4]=raw_osc
    constexpr uint32_t DATA_IN  = 0x08; 
    constexpr uint32_t DATA_OUT = 0x0C;
    constexpr uint32_t RAW_OSC  = 0x10; // [3:0] raw osc bits
    constexpr uint32_t COUNTER  = 0x14; // free running counter
    constexpr uint32_t RAND_OUT = 0x18; // accumulated random output
    constexpr uint32_t SAMP_CNT = 0x1C; // number of samples taken
}

/* control bits*/
namespace CTRL {
    constexpr uint32_t ENABLE = 1 << 0;
    constexpr uint32_t SAMPLE = 1 << 1;
    constexpr uint32_t CLEAR  = 1 << 2;
}

class MMIO {
public:
    volatile uint32_t* ptr = nullptr;   // pointer to mapped memory
    int fd = -1;                        // file descriptor for /dev/mem

    bool open(uint32_t base, uint32_t size) {
        fd = ::open("/dev/mem", O_RDWR | O_SYNC);
        if (fd < 0) return false;
        ptr = (volatile uint32_t*)mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, base); // map physical memory
        return ptr != MAP_FAILED; // check if mapping succeeded
    }

    void close() {
        if  (ptr) munmap((void*)ptr, HSM_SIZE);         // unmap memory
        if (fd >= 0) ::close(fd);                       // close file descriptor
    }

    void write(uint32_t offset, uint32_t value) {
        ptr[offset / 4] = value; // write value to register (offset in bytes, divide by 4 for uint32_t)
    }

    uint32_t read(uint32_t offset) {
        return ptr[offset / 4]; // read value from register
    }
};

int main() {
    printf("TRNG Test Starting...\n");

    MMIO hsm;  // create MMIO instance
    if (!hsm.open(HSM_BASE_ADDR, HSM_SIZE)) { // open MMIO
        perror("Failed to open MMIO");
        return EXIT_FAILURE;
    }

    // Test 1: Read Counter (verify AXI is working)
    printf("\n[TEST 1] Counter Register\n");
    uint32_t counter1 = hsm.read(REG::COUNTER);
    usleep(1000); // wait 1ms
    uint32_t counter2 = hsm.read(REG::COUNTER);
    printf("    Counter: %u -> %u\n (diff: %u)\n", counter1, counter2, counter2 - counter1);
    if (counter2 > counter1) 
        printf("    [PASS]: Counter incrementing\n");
    else 
        printf("    [FAIL]: Counter not incrementing\n");

    // Test 2: Enable Oscillator & Read Raw Oscillator Output
    printf("\n[TEST 2] Ring Oscillators\n");
    hsm.write(REG::CTRL, CTRL::CLEAR);          // clear state
    hsm.write(REG::CTRL, CTRL::ENABLE);         // enable oscillator

    usleep(100);                                // wait for oscillator to stabilize

    uint32_t status = hsm.read(REG::STATUS);
    printf("    Status: 0x%02X\n", status);
    printf("    Oscillators Running: %s\n", (status & 0x1) ? "Yes" : "No");
    printf("    Raw Osc Bits [7:4]: 0x%X\n", (status >> 4) & 0xF);

    // sample raw oscillator bits multiple times to see if they are changing
    printf("\n    Sampling Raw Oscillator Bits:\n");
    for (int i = 0; i < 5; i++) {
        uint32_t raw = hsm.read(REG::RAW_OSC) & 0xF;    // read raw osc bits
        printf("        Sample %d: 0x%X\n", i+1, raw);
        usleep(10);                                     // wait between samples
    }

    // Test 3: Trigger Sample and Check Random Output
    printf("\n [TEST 3] Random Number Generation\n");
    hsm.write(REG::CTRL, CTRL::ENABLE | CTRL::CLEAR); // clear and enable
    usleep(10);
    hsm.write(REG::CTRL, CTRL::ENABLE);               // re-enable w/o clear

    printf("    Collecting 32 random bits...\n");
    for (int i = 0; i < 32; i++) {
        // trigger sample
        hsm.write(REG::CTRL, CTRL::ENABLE | CTRL::SAMPLE);  
        usleep(10);     
        hsm.write(REG::CTRL, CTRL::ENABLE);               // clear sample bit
        usleep(10);
    }

    uint32_t random_value = hsm.read(REG::RAND_OUT);
    uint32_t sample_count = hsm.read(REG::SAMP_CNT);

    printf("    Sample Count: %u\n", sample_count);
    printf("    Random Value: 0x%08X\n", random_value);

    // Test 4: Collect multiple random values to see if they change
    printf("\n [TEST 4] Collecting Multiple Random Values\n");
    for (int n = 0; n < 5; n++) {
        // clear and generate 32 new bits
        hsm.write(REG::CTRL, CTRL::ENABLE | CTRL::CLEAR);
        usleep(10);
        hsm.write(REG::CTRL, CTRL::ENABLE);

        for (int i = 0; i < 32; i++) {
            hsm.write(REG::CTRL, CTRL::ENABLE | CTRL::SAMPLE);  
            usleep(5);     
            hsm.write(REG::CTRL, CTRL::ENABLE);               
            usleep(5);
        }
        printf("    Random[%d]: 0x%08X\n", i+1, hsm.read(REG::RAND_OUT));
    }

    // disable oscillator
    hsm.write(REG::CTRL, 0); // disable all

    // test done
    printf("\nTRNG Test Completed.\n");

    hsm.close(); // close MMIO
    return 0;
}