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
	@echo "  make test      - Compile + run test_hsm"
	@echo "  make test-trng - Compile + run test_trng"
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

ping:
	@ping -c 1 -W 1 $(BOARD_IP) > /dev/null 2>&1 && echo "Board is UP" || echo "Board is DOWN"

ssh:
	ssh $(BOARD_USER)@$(BOARD_IP)

upload:
	@echo "Uploading drivers to $(BOARD_USER)@$(BOARD_IP)..."
	scp sw/drivers/*.cpp $(BOARD_USER)@$(BOARD_IP):~/
	@echo "Done."

test:
	ssh -t $(BOARD_USER)@$(BOARD_IP) 'g++ -o test_hsm test_hsm.cpp && sudo ./test_hsm'

test-trng:
	ssh -t $(BOARD_USER)@$(BOARD_IP) 'g++ -o test_trng test_trng.cpp && sudo ./test_trng'

endif