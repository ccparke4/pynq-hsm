# PYNQ HSM Project Makefile
# Mac: SSH deploy/test | Windows: Vivado/JTAG

# Board settings
BOARD_IP ?= 192.168.2.99
BOARD_USER := xilinx

# Paths
VIVADO_PROJECT := hw/hsm_system_top
BIT_FILE := $(VIVADO_PROJECT)/hsm_system_top.runs/impl_1/hsm_system_design_wrapper.bit
HWH_FILE := $(VIVADO_PROJECT)/hsm_system_top.gen/sources_1/bd/hsm_system_design/hw_handoff/hsm_system_design.hwh
DEPLOY_DIR := deploy

# OS Detection
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
    FIXPATH = $1
    SEP := /
endif

.PHONY: help package clean ping ssh deploy test test-trng upload program

help:
	@echo "PYNQ HSM Makefile - Detected OS: $(DETECTED_OS)"
	@echo ""
	@echo "=== Both Platforms ==="
	@echo "  make package    - Copy .bit/.hwh to deploy/"
	@echo "  make clean      - Remove deploy/"
	@echo ""
ifeq ($(DETECTED_OS),Windows)
	@echo "=== Windows (Vivado/JTAG) ==="
	@echo "  make program    - Program FPGA via Vivado JTAG"
	@echo "  make serial     - Open PuTTY serial console"
else
	@echo "=== Mac (SSH) ==="
	@echo "  make ping       - Check board connectivity"
	@echo "  make ssh        - SSH to board"
	@echo "  make upload     - Upload files to board"
	@echo "  make deploy     - Package + upload + load bitstream"
	@echo "  make test       - Run test_hsm"
	@echo "  make test-trng  - Run test_trng"
endif

# ============ BOTH PLATFORMS ============

package:
	@$(MKDIR)
	@echo "Copying bitstream..."
	@$(CP) $(call FIXPATH,$(BIT_FILE)) $(call FIXPATH,$(DEPLOY_DIR)$(SEP)hsm_overlay.bit)
	@echo "Copying hardware handoff..."
	@$(CP) $(call FIXPATH,$(HWH_FILE)) $(call FIXPATH,$(DEPLOY_DIR)$(SEP)hsm_overlay.hwh)
	@echo "Done. Files in $(DEPLOY_DIR)/"

clean:
	@$(RM)
	@echo "Cleaned."

# ============ WINDOWS ONLY ============
ifeq ($(DETECTED_OS),Windows)

# Program via JTAG using Vivado
program:
	@echo "Programming FPGA via JTAG..."
	vivado -mode batch -source scripts/program.tcl

# Open serial console
serial:
	@echo "Opening serial console..."
	putty -serial COM7 -sercfg 115200,8,n,1,N

endif

# ============ MAC ONLY ============
ifeq ($(DETECTED_OS),Mac)

ping:
	@ping -c 1 -W 1 $(BOARD_IP) > /dev/null 2>&1 && echo "Board is UP" || echo "Board is DOWN"

ssh:
	ssh $(BOARD_USER)@$(BOARD_IP)

upload:
	@test -f $(DEPLOY_DIR)/hsm_overlay.bit || (echo "Error: deploy/hsm_overlay.bit not found. Run 'make package' on Windows first." && exit 1)
	@echo "Uploading to $(BOARD_USER)@$(BOARD_IP)..."
	scp $(DEPLOY_DIR)/hsm_overlay.bit $(BOARD_USER)@$(BOARD_IP):~/
	scp $(DEPLOY_DIR)/hsm_overlay.hwh $(BOARD_USER)@$(BOARD_IP):~/
	scp sw/drivers/*.cpp $(BOARD_USER)@$(BOARD_IP):~/
	@echo "Upload complete."

deploy: upload
	@echo "Loading bitstream..."
	ssh -t $(BOARD_USER)@$(BOARD_IP) 'sudo fpgautil -b /home/xilinx/hsm_overlay.bit'
	@echo "Ready."

test:
	ssh -t $(BOARD_USER)@$(BOARD_IP) 'g++ -o test_hsm test_hsm.cpp && sudo ./test_hsm'

test-trng:
	ssh -t $(BOARD_USER)@$(BOARD_IP) 'g++ -o test_trng test_trng.cpp && sudo ./test_trng'

endif