# PYNQ HSM Project Makefile
# Windows: Vivado build + JTAG program
# Mac: Upload drivers + compile/test via SSH

BOARD_IP ?= 192.168.2.99
BOARD_USER := xilinx

VIVADO := C:/AMDDesignTools/2025.2/Vivado/bin/vivado.bat
VIVADO_PROJECT := hw/hsm_system_top
BIT_FILE := $(VIVADO_PROJECT)/hsm_system_top.runs/impl_1/hsm_system_design_wrapper.bit
HWH_FILE := $(VIVADO_PROJECT)/hsm_system_top.gen/sources_1/bd/hsm_system_design/hw_handoff/hsm_system_design.hwh
DEPLOY_DIR := deploy

ifeq ($(OS),Windows_NT)
    DETECTED_OS := Windows
    MKDIR = if not exist $(DEPLOY_DIR) mkdir $(DEPLOY_DIR)
    CP = copy /Y
    RM = if exist $(DEPLOY_DIR) rmdir /s /q $(DEPLOY_DIR)
    FIXPATH = $(subst /,\,$1)
    SEP := \\
else
    DETECTED_OS := Mac
    MKDIR = mkdir -p $(DEPLOY_DIR)
    CP = cp
    RM = rm -rf $(DEPLOY_DIR)
    SEP := /
endif

.PHONY: help clean

help:
	@echo "PYNQ HSM Makefile - Detected OS: $(DETECTED_OS)"
	@echo ""
ifeq ($(DETECTED_OS),Windows)
	@echo "=== Windows (Vivado/JTAG) ==="
	@echo "  make package   - Copy .bit/.hwh to deploy/"
	@echo "  make program   - Program FPGA via JTAG"
	@echo "  make serial    - Open PuTTY serial console"
	@echo "  make clean     - Remove deploy/"
else
	@echo "=== Mac (SSH) ==="
	@echo "  make ping      - Check board connectivity"
	@echo "  make ssh       - SSH to board"
	@echo "  make upload    - Upload C++ drivers to board"
	@echo "  make test      - Compile + run test_hsm (TRNG)"
	@echo "  make test-trng - Compile + run test_trng"
	@echo "  make test-aes  - Compile + run test_aes (AES-256 KAT)"
	@echo "  make test-all  - Run TRNG + AES tests (full HW regression)"
	@echo "  make clean     - Remove deploy/"
endif

clean:
	@$(RM)
	@echo "Cleaned."

# ============ WINDOWS ONLY ============
ifeq ($(DETECTED_OS),Windows)

package:
	@$(MKDIR)
	@echo Copying bitstream...
	@$(CP) $(call FIXPATH,$(BIT_FILE)) $(call FIXPATH,$(DEPLOY_DIR)$(SEP)hsm_overlay.bit)
	@echo Copying hardware handoff...
	@$(CP) $(call FIXPATH,$(HWH_FILE)) $(call FIXPATH,$(DEPLOY_DIR)$(SEP)hsm_overlay.hwh)
	@echo Done.

program: package
	@echo Programming FPGA via JTAG...
	$(VIVADO) -mode batch -source scripts/program.tcl

serial:
	putty -serial COM7 -sercfg 115200,8,n,1,N

endif

# ============ MAC ONLY ============
ifeq ($(DETECTED_OS),Mac)

BIND_IP 	:= 192.168.2.1
ETH_IFACE := $(shell ifconfig | \
               awk '/^en[0-9]+:/{iface=$$1; gsub(":","",iface)} \
                    /1000baseT.*full-duplex/{print iface; exit}' \
               2>/dev/null || echo "en26")
SSH_CMD		:= ssh -o BindAddress=$(BIND_IP) -o ConnectTimeout=5
SCP_CMD		:= scp -o BindAddress=$(BIND_IP) -o ConnectTimeout=5

.PHONY: setup-network ping ssh upload test test-trng test-aes test-all

setup-network:
	@if [ -z "$(ETH_IFACE)" ]; then \
		echo "ERROR: Could not detect ethernet interface. Set ETH_IFACE manually."; \
		exit 1; \
	fi
	@echo "Detected ethernet interface: $(ETH_IFACE)"
	@sudo ifconfig $(ETH_IFACE) $(BIND_IP) netmask 255.255.255.0
	@ping -c 2 -W 1 $(BOARD_IP) > /dev/null 2>&1 \
		&& echo "Board $(BOARD_IP) is reachable" \
		|| (echo "ERROR: Board not responding. Check cable/boot." && exit 1)

ping: setup-network
	@echo "Board is UP"

ssh: setup-network
	$(SSH_CMD) $(BOARD_USER)@$(BOARD_IP)

upload: setup-network
	@echo "Uploading drivers to $(BOARD_USER)@$(BOARD_IP)..."
	$(SCP_CMD) sw/drivers/*.cpp $(BOARD_USER)@$(BOARD_IP):~/
	@echo "Done."

test: upload
	$(SSH_CMD) -t $(BOARD_USER)@$(BOARD_IP) 'g++ -o test_hsm test_hsm.cpp && sudo ./test_hsm'

test-trng: upload
	$(SSH_CMD) -t $(BOARD_USER)@$(BOARD_IP) 'g++ -o test_trng test_trng.cpp && sudo ./test_trng'

test-aes: upload
	$(SSH_CMD) -t $(BOARD_USER)@$(BOARD_IP) 'g++ -o test_aes test_aes.cpp && sudo ./test_aes'

test-all: upload
	@echo "================================================"
	@echo "  Full HW Regression: TRNG + AES-256"
	@echo "================================================"
	$(SSH_CMD) -t $(BOARD_USER)@$(BOARD_IP) \
		'g++ -o test_trng test_trng.cpp && sudo ./test_trng && \
		 echo "" && \
		 g++ -o test_aes test_aes.cpp && sudo ./test_aes'

capture: upload
	@echo "Capturing 1MB RNG data..."
	$(SSH_CMD) $(BOARD_USER)@$(BOARD_IP) \
		'sudo ./test_hsm --binary | dd of=rng_data.bin bs=1024 count=1000 iflag=fullblock'
	$(SCP_CMD) $(BOARD_USER)@$(BOARD_IP):~/rng_data.bin .
	@echo "Running ENT analysis..."
	ent rng_data.bin

endif