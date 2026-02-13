# PYNQ HSM
Hardware Security Module on PYNQ-Z2 

## Status
[x] v0.1.0 0 AXI-Lite register interface working
[ ] Encryption Core
[ ] Key Storage

## Architecture/Block Design
![Block Diagram](docs/hsm_bd_init.png)

## Quick Start
```bash
scp sw/drivers/test_hsm.cpp xilinx@192.168.2.99:~/
ssh xilinx@xxx.xxx.xxx.xxx
...
g++ -o test_hsm test_hsm.cpp
sudo ./test_hsm
...
=== HSM TEST ===
Mapped HSM HW @ 0x40000000
Writing 0xDEADBEEF to Data input (reg2)...
Read baack: 0xDEADBEEF
[PASS] AXI-Lite W/R success!
Writing 0x1 (Start) to control (Reg 0)...
Control Reg is no: 0x00000000
```
