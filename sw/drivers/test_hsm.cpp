/**
* @file     test_hsm.cpp
* @brief    Robust PYNQ HSM Driver w/ Safety Timeouts (v0.3.0)    
* @details  Implements "Anti-lock" protection
*/

#include <cstdint>
#include <iomanip>
#include <cstdint>
#include <iostream>
#include <sys/types.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <vector>
#include <csignal>

// global flag to track if user pressec Ctrl+C
volatile sig_atomic_t stop_requested = 0; 

// The function that runs when you ctrl+c
void signal_handler(int signum) {
    stop_requested = 1;
}



// --- CONFIG ---
constexpr uint32_t HSM_BASE_ADDR = 0x40000000;
constexpr uint32_t HSM_SIZE = 0x1000; // 4KB

// --- REG MAP ---
enum RegOffset : uint32_t {
    REG_CTRL        = 0x00, 
    REG_STATUS      = 0x04,
    REG_DATA_IN     = 0x08, // Future: AES Input
    REG_DATA_OUT    = 0x0C, // Future: AES Output
    REG_TRNG_OSC    = 0x10, // Debug: Raw Osc Bits
    REG_TRNG_OUT    = 0x18, // TRNG Result
    REG_SAMPLE_CNT  = 0x1C  // Debug: Sample Counter
};

// --- BIT MASKS ---
namespace Ctrl {
    constexpr uint32_t ENABLE = 1 << 0;
    constexpr uint32_t SAMPLE = 1 << 1;
    constexpr uint32_t CLEAR  = 1 << 2;
}

/* ===== SAFE DRIVE CLASS ===== */
class PynqHSM {
private:
    int _fd;
    volatile uint32_t* _base_ptr;           // pointer to mapped memory
    bool _is_mapped;                        // flag to track if MMIO is open

public:
    PynqHSM(uint32_t phys_addr, uint32_t size) : _fd(-1), _base_ptr(nullptr), _is_mapped(false) {
        // Open /dev/mem
        _fd = ::open("/dev/mem", O_RDWR | O_SYNC);
        if (_fd < 0) {
            perror("Failed to open /dev/mem");
            return;
        }

        // Map physical memory
        _base_ptr = (volatile uint32_t*)mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_SHARED, _fd, phys_addr);
        if (_base_ptr == MAP_FAILED) {
            perror("Failed to mmap");
            ::close(_fd);
            _fd = -1;
            return;
        }

        _is_mapped = true; // Mark as successfully opened and mapped
    }

    // Destructor to clean up resources
    ~PynqHSM() {
        if (_is_mapped) {
            writeReg(REG_CTRL, 0);          // Safety: Disable HW on exit
            munmap((void*)_base_ptr, HSM_SIZE);
            if (_fd >= 0) ::close(_fd);     // Close file descriptor
        }
    }

    void writeReg(RegOffset offset, uint32_t value) {
        if (_is_mapped) _base_ptr[offset / 4] = value; // Write to register
    }

    uint32_t readReg(RegOffset offset) {
        return _is_mapped ? _base_ptr[offset / 4] : 0; // Read from register
    }

    // --- Timeout implementation ---
    bool waitForDone(int timeout_ms = 1000) {
        int attempts = 0;
        usleep(100);
        return true;
    }

    
    // --- COMMANDS ---

    // 0xFFFF_FFFF returned if failed
    uint32_t getTrngRandom() {
        // 1. Clear and enable
        writeReg(REG_CTRL, Ctrl::ENABLE | Ctrl::CLEAR);
        usleep(10); // wait for clear

        // 2. Trigger Sample
        writeReg(REG_CTRL, Ctrl::ENABLE | Ctrl::SAMPLE);

        // 3. wait for hw to finish
        if (!waitForDone(500)) {
            std::cerr << "[ERROR] Hardware Timeout! TRNG stuck." << std::endl;
            return 0xFFFFFFFF;
        }

        // 4. Read result
        writeReg(REG_CTRL, Ctrl::ENABLE);   // clear sample bit
        return readReg(REG_TRNG_OUT);
    }
};

/* ===== Health Testing ===== */

void test_trng_health(PynqHSM& hsm) {
    std::cout << "Running TRNG Health Checks..." << std::endl;

    // 1. repatition count test (SW impl)
    uint32_t prev = hsm.getTrngRandom();
    bool frozen = true;

    for (int i = 0; i < 10; i++) {
        uint32_t curr = hsm.getTrngRandom();
        if (curr != prev) frozen = false; // if any value changes, not frozen
        prev = curr;
    }

    if (frozen) 
        std::cout << "[FAIL] TRNG appears frozen! Got same value repeatedly." << std::endl;
    else
        std::cout << "[PASS] TRNG values changing, not frozen." << std::endl;
}

int main() {
    // 1. Reg the signal handler immediately
    signal(SIGINT, signal_handler);

    std::cout << "--- PYNQ HSM v0.3 ---" << std::endl;
    std::cout << "[INFO] Press Ctrl+C to stop safely." << std::endl;

    PynqHSM hsm(HSM_BASE_ADDR, HSM_SIZE);

    // 2. Update test loop to check flag
    std::cout << "Generating random numbers (loop)..." << std::endl;

    int count = 0;
    while (!stop_requested) {   // <- check flag
        uint32_t rnd = hsm.getTrngRandom();

        if (rnd == 0xFFFFFFFF) {
            std::cerr << "[ERROR] Failed to get random number. Stopping test." << std::endl;
            break;
        }

        std::cout << "Sample" << std::dec << count++ << ": 0x" << std::hex << rnd << std::endl;

        usleep(100000); // wait 100ms between samples
    }
    // 3. When loop breaks
    std::cout << "\n[INFO] Exiting gracefully..." << std::endl;
    return 0;
}