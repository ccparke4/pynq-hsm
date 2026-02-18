/**
* @file     test_hsm.cpp
* @brief    Robust PYNQ HSM Driver w/ Safety Timeouts (v0.3.0)    
* @details  Implements "Anti-lock" protection and Binary Mode
*/

#include <cstdint>
#include <iomanip>
#include <iostream>
#include <sys/types.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <vector>
#include <csignal>

// Global flag to track if user pressed Ctrl+C
volatile sig_atomic_t stop_requested = 0; 

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
    REG_DATA_IN     = 0x08, 
    REG_DATA_OUT    = 0x0C, 
    REG_TRNG_OSC    = 0x10, 
    REG_TRNG_OUT    = 0x18, // TRNG Result
    REG_SAMPLE_CNT  = 0x1C  // Sample Counter
};

// --- BIT MASKS ---
namespace Ctrl {
    constexpr uint32_t ENABLE = 1 << 0;
    constexpr uint32_t SAMPLE = 1 << 1;
    constexpr uint32_t CLEAR  = 1 << 2;
}

namespace Status {
    constexpr uint32_t OSC_RUNNING  = 1 << 0;
    constexpr uint32_t HEALTH_FAIL  = 1 << 8;   // combined health failure
    constexpr uint32_t RCT_FAIL     = 1 << 9;   // repetition count test
    constexpr uint32_t APT_FAIL     = 1 << 10; 
}

/* ===== SAFE DRIVER CLASS ===== */
class PynqHSM {
private:
    int _fd;
    volatile uint32_t* _base_ptr;
    bool _is_mapped;

public:
    PynqHSM(uint32_t phys_addr, uint32_t size) : _fd(-1), _base_ptr(nullptr), _is_mapped(false) {
        _fd = ::open("/dev/mem", O_RDWR | O_SYNC);
        if (_fd < 0) {
            perror("Failed to open /dev/mem");
            return;
        }
        _base_ptr = (volatile uint32_t*)mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_SHARED, _fd, phys_addr);
        if (_base_ptr == MAP_FAILED) {
            perror("Failed to mmap");
            ::close(_fd);
            _fd = -1;
            return;
        }
        _is_mapped = true;
    }

    ~PynqHSM() {
        if (_is_mapped) {
            writeReg(REG_CTRL, 0);
            munmap((void*)_base_ptr, HSM_SIZE);
            if (_fd >= 0) ::close(_fd);
        }
    }

    void writeReg(RegOffset offset, uint32_t value) {
        if (_is_mapped) _base_ptr[offset / 4] = value;
    }

    uint32_t readReg(RegOffset offset) {
        return _is_mapped ? _base_ptr[offset / 4] : 0;
    }

    // --- Health status check ---
    bool checkHealth(bool verbose = false) {
        uint32_t status = readReg(REG_STATUS);
        if (verbose) {
            bool osc_ok = status & Status::OSC_RUNNING;
            bool rct_ok = !(status & Status::RCT_FAIL);
            bool apt_ok = !(status & Status::APT_FAIL);
            std::cout << "  OSC Running : " << (osc_ok  ? "[OK]" : "[FAIL]") << std::endl;
            std::cout << "  RCT Test    : " << (rct_ok  ? "[OK]" : "[FAIL] - Oscillator may be locked") << std::endl;
            std::cout << "  APT Test    : " << (apt_ok  ? "[OK]" : "[FAIL] - Bit distribution skewed") << std::endl;
        }
        return !(status & Status::HEALTH_FAIL);
    }

    // --- Timeout implementation ---
    bool waitForSampleDone(uint32_t old_count) {
        volatile int timeout = 1000000; 
        while (timeout-- > 0) {
            uint32_t new_count = readReg(REG_SAMPLE_CNT);
            if (new_count > old_count) {
                return true; 
            }
        }
        return false;
    }
    
    // --- COMMANDS ---
    uint32_t getTrngRandom() {
        // 1. Read current count
        uint32_t current_cnt = readReg(REG_SAMPLE_CNT);

        // 2. PREPARE TRIGGER: Pull Sample Bit LOW (keep Enable High)
        //    This resets the pin to 0 so we can create a rising edge.
        writeReg(REG_CTRL, Ctrl::ENABLE); 

        // 3. TRIGGER: Pull Sample Bit HIGH
        //    This creates the 0->1 transition the hardware is waiting for!
        writeReg(REG_CTRL, Ctrl::ENABLE | Ctrl::SAMPLE);

        // 4. Wait until count increases (Hardware Handshake)
        //    (I also increased the timeout here just to be safe)
        if (!waitForSampleDone(current_cnt)) {
            return 0xFFFFFFFF;
        }

        // 5. Read result
        return readReg(REG_TRNG_OUT);
    }
}; 

/* ===== Health Testing (Outside Class) ===== */
void test_trng_health(PynqHSM& hsm) {
    std::cout << "Running TRNG Health Checks..." << std::endl;
    uint32_t prev = hsm.getTrngRandom();
    bool frozen = true;

    for (int i = 0; i < 10; i++) {
        uint32_t curr = hsm.getTrngRandom();
        if (curr != prev) frozen = false;
        prev = curr;
    }

    if (frozen) 
        std::cout << "[FAIL] TRNG appears frozen! Got same value repeatedly." << std::endl;
    else
        std::cout << "[PASS] TRNG values changing, not frozen." << std::endl;
}

/* ===== MAIN ===== */
int main(int argc, char* argv[]) {
    // 1. Check mode
    bool binary_mode = false;
    bool health_mode = false;
    if (argc > 1) {
        std::string arg = argv[1];
        if (arg == "--binary") binary_mode = true;
        if (arg == "--health") health_mode = true;
    }

    signal(SIGINT, signal_handler);

    PynqHSM hsm(HSM_BASE_ADDR, HSM_SIZE);

    // --- Health Monitor Mode (Text Only) ---
    if (health_mode) {
            std::cout << "PYNQ HSM Health Monitor:" << std::endl;

            // enable oscillators 
            hsm.writeReg(REG_CTRL, Ctrl::ENABLE);

            // clear any latched startup fails
            hsm.writeReg(REG_CTRL, Ctrl::ENABLE | Ctrl::CLEAR);
            hsm.writeReg(REG_CTRL, Ctrl::ENABLE); // re-enable after clear

            sleep(1); // give it a moment to stabilize

            while (!stop_requested) {
                std::cout << "\033[2J\033[H"; // Clear screen and move cursor to top-left
                std::cout <<"--- TRNG Health Status ---" << std::endl;
                hsm.checkHealth(true);
                bool healthy = !(hsm.readReg(REG_STATUS) & Status::HEALTH_FAIL);
                std::cout << "--------------------------" << std::endl;
                std::cout << "  Sample Count: 0x" << std::hex << hsm.readReg(REG_SAMPLE_CNT) << std::endl;
                std::cout.flush();
                sleep(1);
            }
            return 0;
        }

    // --- Normal Mode (Text Output) ---
    if (!binary_mode) {
        std::cout << "PYNQ HSM Driver Test Starting..." << std::endl;
        std::cout << "Press Ctrl+C to stop." << std::endl;
        
        std::cout << "\n--- TRNG Health Status ---" << std::endl;
        bool healthy = hsm.checkHealth(true);
        if (!healthy) {
            std::cerr << "[WARN] Health monitor reports failure. Output may be compromised." << std::endl;
            std::cerr << "       Run with ctrl_clear to reset, then re-check." << std::endl;
        } else {
            std::cout << "  Overall     : [OK] TRNG healthy" << std::endl;
        }
        std::cout << "--------------------------\n" << std::endl;
        test_trng_health(hsm);
    }

    while (!stop_requested) {
        // check health every 1k samples in binary mode
        if (binary_mode) {
            static int health_check_count = 0;
            if (++health_check_count >= 1000) {
                health_check_count = 0;
                if (!hsm.checkHealth(false)) {
                    std::cerr << "[ERROR] Health monitor failure detected mid-stream. Aborting." << std::endl;
                    break;
                }
            }
        }

        uint32_t random_value = hsm.getTrngRandom();

        if (random_value == 0xFFFFFFFF) {
            if (!binary_mode) std::cerr << "[ERROR] Hardware Timeout." << std::endl;
            break;
        }

        if (binary_mode) {
            // write raw bytes for post-run analysis
            std::cout.write(reinterpret_cast<const char*>(&random_value), sizeof(random_value));
        } else {
            // text mode for debug
            std::cout << "0x" << std::hex << random_value << std::endl;
        }
    }
    if (!binary_mode) {
        std::cout << "PYNQ HSM Driver Test Ending..." << std::endl;
    }
    return 0;
}