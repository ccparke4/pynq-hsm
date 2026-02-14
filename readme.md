# PYNQ HSM
Hardware Security Module on PYNQ-Z2 

## Status
- [x] v0.1.0 - AXI-Lite register interface working
- [x] v0.2.0 - TRNG w/ Ring oscillator entropy source 
- [ ] Encryption Core
- [ ] Key storage

## Architecture/Block Design
![Block Diagram](docs/hsm_bd_init.png)

## Register Map

| Offset | Name     | Access | Description                      |
|--------|----------|--------|----------------------------------|
| 0x00   | CTRL     | R/W    | [0]=enable, [1]=sample, [2]=clear|
| 0x04   | STATUS   | R      | [0]=osc running, [7:4]=raw osc   |
| 0x08   | DATA_IN  | R/W    | Reserved                         |
| 0x0C   | DATA_OUT | R/W    | Reserved                         |
| 0x10   | RAW_OSC  | R      | Raw oscillator outputs [3:0]     |
| 0x14   | COUNTER  | R      | Free-running debug counter       |
| 0x18   | RAND_OUT | R      | 32-bit random value              |
| 0x1C   | SAMP_CNT | R      | Number of samples taken          |

## TRNG Design
Uses 4 ring oscillators with different prime stage counts (13,17, 19, 23 inverters)

## Quick Start

### Manual Steps

#### 1. Build Bitstream (Windows VM - Vivado)
1. Open `hw/hsm_system_top/hsm_system_top.xpr`
2. Run Synthesis → Implementation → Generate Bitstream
3. Copy files to `deploy/`:
```powershell
   mkdir deploy
   copy hw\hsm_system_top\hsm_system_top.runs\impl_1\hsm_system_design_wrapper.bit deploy\hsm_overlay.bit
   copy hw\hsm_system_top\hsm_system_top.gen\sources_1\bd\hsm_system_design\hw_handoff\hsm_system_design.hwh deploy\hsm_overlay.hwh
```

#### 2. Program FPGA (Windows VM - Vivado)
1. Open Hardware Manager
2. Open Target → Auto Connect
3. Right-click `xc7z020` → Program Device
4. Select `deploy/hsm_overlay.bit`
5. Click Program

#### 3. Setup Board Network (Serial Console)
```bash
# Connect via PuTTY to COM7 at 115200 baud
# Login: xilinx / xilinx
sudo ip addr add 192.168.2.99/24 dev eth0
```

#### 4. Setup Mac Network
```bash
sudo ifconfig en26 192.168.2.1 netmask 255.255.255.0 up
ping 192.168.2.99
```

#### 5. Upload and Test (Mac)
```bash
scp sw/drivers/test_trng.cpp xilinx@192.168.2.99:~/
ssh xilinx@192.168.2.99
g++ -o test_trng test_trng.cpp
sudo ./test_trng
```

### Makefile Automation

#### Windows
```bash
make package    # Copy bitstream to deploy/
make program    # Program FPGA via JTAG (requires Vivado in PATH)
make serial     # Open PuTTY serial console
```

#### Mac
```bash
make ping       # Check board connectivity
make upload     # Upload C++ drivers
make test-trng  # Compile and run TRNG test
make ssh        # SSH to board
```

## Example Output
```
TRNG Test Starting...

[TEST 1] Counter Register
    Counter: 881091339 -> 881209352
 (diff: 118013)
    [PASS]: Counter incrementing

[TEST 2] Ring Oscillators
    Status: 0x21
    Oscillators Running: Yes
    Raw Osc Bits [7:4]: 0x2

    Sampling Raw Oscillator Bits:
        Sample 1: 0xB
        Sample 2: 0xA
        Sample 3: 0xC
        Sample 4: 0x7
        Sample 5: 0x2

 [TEST 3] Random Number Generation
    Collecting 32 random bits...
    Sample Count: 32
    Random Value: 0xC31703EB

 [TEST 4] Collecting Multiple Random Values
    Random[1]: 0xB24BDF18
    Random[2]: 0x914F9FBE
    Random[3]: 0x86805472
    Random[4]: 0xC90CAD2F
    Random[5]: 0x8F20B951

TRNG Test Completed.
```

## Build Requirements

- PYNQ-Z2 board with default PYNQ image
- USB-JTAG Connection for bitstream loading
- USB-Ethernet adapter for network
- PuTTy or some serial interface 