# PYNQ HSM Project Makefile

# Board settings
BOARD_IP ?= 192.168.2.99
BOARD_USER := xilinx

# Paths
VIVADO_PROJECT := hw/hsm_system_top
# Note: Keep forward slashes here; we will fix them automatically later
BIT_FILE := $(VIVADO_PROJECT)/hsm_system_top.runs/impl_1/hsm_system_design_wrapper.bit
HWH_FILE := $(VIVADO_PROJECT)/hsm_system_top.gen/sources_1/bd/hsm_system_design/hw_handoff/hsm_system_design.hwh
DEPLOY_DIR := deploy

# --- OS Detection & Command Setup ---
ifeq ($(OS),Windows_NT)
    # Windows Settings
    MKDIR = if not exist $(DEPLOY_DIR) mkdir $(DEPLOY_DIR)
    CP = copy /Y
    RM = if exist $(DEPLOY_DIR) rmdir /s /q $(DEPLOY_DIR)
    # Magic to change / to \ for Windows commands
    FIXPATH = $(subst /,\,$1)
else
    # Linux / Bash Settings
    MKDIR = mkdir -p $(DEPLOY_DIR)
    CP = cp
    RM = rm -rf $(DEPLOY_DIR)
    FIXPATH = $1
endif

.PHONY: all deploy package upload ssh test clean help

help:
	@echo "Usage:"
	@echo "  make package  - Copy .bit/.hwh to deploy/"
	@echo "  make upload   - Upload to PYNQ board"
	@echo "  make deploy   - Package + upload + load"
	@echo "  make test     - Run test on board"
	@echo "  make ssh      - SSH to board"
	@echo "  make clean    - Remove deploy/"

# Copy bitstream and hardware handoff to deploy/
package:
	@$(MKDIR)
	@echo "Copying bitstream..."
	@$(CP) $(call FIXPATH,$(BIT_FILE)) $(call FIXPATH,$(DEPLOY_DIR)\hsm_overlay.bit)
	@echo "Copying hardware handoff..."
	@$(CP) $(call FIXPATH,$(HWH_FILE)) $(call FIXPATH,$(DEPLOY_DIR)\hsm_overlay.hwh)
	@echo "Done. Files in $(DEPLOY_DIR)/"

# Upload to board (scp works fine on Windows 10+)
upload: package
	@echo "Uploading to $(BOARD_USER)@$(BOARD_IP)..."
	scp $(DEPLOY_DIR)/hsm_overlay.bit $(BOARD_USER)@$(BOARD_IP):~/
	scp $(DEPLOY_DIR)/hsm_overlay.hwh $(BOARD_USER)@$(BOARD_IP):~/
	scp sw/drivers/test_hsm.cpp $(BOARD_USER)@$(BOARD_IP):~/
	@echo "Upload complete."

# Full deploy: package, upload, load bitstream, compile
deploy: upload
	@echo "Loading bitstream and compiling..."
	ssh $(BOARD_USER)@$(BOARD_IP) '\
		python3 -c "from pynq import Overlay; Overlay(\"/home/xilinx/hsm_overlay.bit\"); print(\"Bitstream loaded\")" && \
		g++ -o test_hsm test_hsm.cpp && \
		echo "Ready. Run: sudo ./test_hsm"'

# Run test
test:
	ssh $(BOARD_USER)@$(BOARD_IP) 'sudo ./test_hsm'

# SSH to board
ssh:
	ssh $(BOARD_USER)@$(BOARD_IP)

# Clean
clean:
	@$(RM)
	@echo "Cleaned deploy directory."