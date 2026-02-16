# PYNQ HSM
Hardware Security Module on PYNQ-Z2 

## Status
- [x] **v0.1.0** - AXI-Lite register interface working
- [x] **v0.2.0** - TRNG w/ Ring oscillator entropy source 
- [x] **v0.3.0** - Validated TRNG (Von Neumann Debiaser + Handshake logic) 
- [ ] **v0.4.0** - AES-256 Encryption Core 
- [ ] **v0.5.0** -  Secure Key Storage

## Architecture/Block Design
### HDL Block Diagram
![Block Diagram](docs/hsm_bd_init.png)

### Overview
The HSM is implemented in HDL and communicates with the Processing system via AXI4-Lite.
`[ARM Core(Linux)] <---> [AXI] <---> [HSM Core]`

### TRNG Design (Entropy Source)
The TRNG derives randomness from thermal noise and clock jitter using free-running Ring Oscillators (ROs).
1.  **Entropy Source:** 4 parallel Ring Oscillators with prime number stage lengths (13, 17, 19, 23 inverters) to prevent frequency locking.
2.  **Digitizer & Decimator:** The RO outputs are XORed together. The sampler waits **8 clock cycles** between samples (12.5 MHz effective rate) to allow clock jitter to accumulate, preventing correlation between adjacent bits.
3.  **Whitening (Von Neumann Debiaser):** - Eliminates bias (e.g., if the circuit naturally favors '1's).
    - Logic: Reads pairs of bits. `01` -> Output `1`. `10` -> Output `0`. `00` & `11` -> Discard.
4.  **Accumulator:** Collects 32 valid bits into a holding register.
5.  **Interface:** Uses a "Valid/Done" handshake signal to ensure the software never reads partial or stale data.

## Verification & Benchmarks (v0.3.0)

Randomness was verified using the **ENT** industry-standard statistical analysis tool.

**Test Command:**
```bash
sudo ./test_hsm --binary | dd of=rng_data.bin bs=1024 count=1000 iflag=fullblock
ent rng_data.bin

#### 3. Setup Board Network (Serial Console)
# Connect via PuTTY to COM7 at 115200 baud
# Login
sudo ip addr add 192.168.2.99/24 dev eth0
```
### Results
| Metric | W/O Decimator | **w/ Decimator** | Industry Std | Verdict |
|--------|--------------|----------------------|--------------|---------|
| **Entropy** | 7.81 bits/byte | **7.935 bits/byte** | > 7.9 | ✅ **PASS** |
| **Compression** | 2% reduction | **0% (Uncompressible)** | 0% | ✅ **PASS** |
| **Chi-Square** | 280,000+ (High Bias) | **83,908 (Low Bias)** | < 100k | ✅ **PASS** |
| **Mean** | 127.55 | **127.39** | 127.5 | ✅ **PASS** |

### Quick Start

1. **Build & Deploy**

**Windows (Vivado):** <br>
- Run/Generate bitstream in vivado
- Program in vivado

**Mac/Linux (Software)** <br>
- Connect via Ethernet
- Run `make upload` to send driver to board

2. **Run Driver**
SSH into board and compile driver
```bash
ssh xilinx@...
g++ -o test_hsm test_hsm.cpp
```

3. **Usage Modes**
**Health Check (Text):** <br>
Verifies hw responsiveness and prints samples in hex
```bash
sudo ./test_hsm
```

**Binary Capture (Analysis):**
Streams raw binary data to stdout (pipe to file).
```bash
sudo ./test_hsm --binary > random_data.bin
```

## Build Requirements
* PYNQ-Z2 Board w/ image
* Vivado 2025.2
* `g++` on board to compile drivers
* `ent` (rec'd) for statistical analysis