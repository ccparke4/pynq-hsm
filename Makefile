# PYNQ HSM Project Makefile

# Board settings
BOARD_IP ?= 192.168.2.99
BOARD_USER := xilinx

# Paths
VIVADO_PROJECT := hw/hsm_system_top
BIT_FILE := $(VIVADO_PROJECT)/hsm_system_top.runs/impl_1/hsm_system_design_wrapper.bit
HWH_FILE := $(VIVADO_PROJECT)/hsm_system_top.gen/sources_1/bd/hsm_system_design/hw_handoff/hsm_system_design.hwh
DEPLOY_DIR := deploy

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
	@mkdir -p $(DEPLOY_DIR)
	@echo "Copying bitstream..."
	@cp $(BIT_FILE) $(DEPLOY_DIR)/hsm_overlay.bit
	@echo "Copying hardware handoff..."
	@cp $(HWH_FILE) $(DEPLOY_DIR)/hsm_overlay.hwh
	@echo "Done. Files in $(DEPLOY_DIR)/"
	@ls -la $(DEPLOY_DIR)/

# Upload to board
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
	rm -rf $(DEPLOY_DIR)