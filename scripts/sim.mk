# sim.mk — HDL Simulation Automation
#
# Include from scripts/Makefile:
#     include sim.mk
#
# Standalone from scripts/:
#     make -f sim.mk sim-sbox
#
# Adding a new testbench:
#   1. Define DUT_<n> with its RTL source files
#   2. Define TB_<n>  pointing to the testbench file
#   3. Add a sim-<n> target using $(call run_sim,...)
#   4. Add sim-<n> to the 'sim' dependency list

# Config =======================================================
VIVADO_BIN  ?= C:/AMDDesignTools/2025.2/Vivado/bin
PYTHON      ?= python
PROJECT_ROOT ?= C:/Users/trey/pynq_hsm

XVLOG       := $(VIVADO_BIN)/xvlog
XELAB       := $(VIVADO_BIN)/xelab
XSIM        := $(VIVADO_BIN)/xsim
SCRIPTS_DIR := $(PROJECT_ROOT)/scripts

# Directories ==================================================
SRC_DIR     := $(PROJECT_ROOT)/hw/src
SIM_DIR     := $(PROJECT_ROOT)/hw/sim
VEC_DIR     := $(PROJECT_ROOT)/vectors
LOG_DIR     := $(PROJECT_ROOT)/logs

# DUT file lists ===============================================
DUT_SBOX    := $(SRC_DIR)/aes_sbox.sv

# FIX: no trailing space after backslash
DUT_CORE    := $(SRC_DIR)/aes_sbox.sv \
               $(SRC_DIR)/aes_core.sv

# Uncomment when tb_aes_axi.sv is written:
# DUT_AXI   := $(SRC_DIR)/aes_sbox.sv \
#              $(SRC_DIR)/aes_core.sv \
#              $(SRC_DIR)/aes_axi_wrapper.sv \
#              $(SRC_DIR)/aes_bridge.v

# Testbench files ==============================================
TB_SBOX     := $(SIM_DIR)/tb_aes_sbox.sv
TB_CORE     := $(SIM_DIR)/tb_aes_core.sv
# TB_AXI    := $(SIM_DIR)/tb_aes_axi.sv

# Generated vector files =======================================
GOLDEN_SBOX := $(VEC_DIR)/sbox_golden.hex
GOLDEN_KAT  := $(VEC_DIR)/aes_kat.hex
GOLDEN_KEXP := $(VEC_DIR)/aes_key_exp.hex

# Phony targets ================================================
.PHONY: sim sim-sbox sim-core vectors check-sim clean-sim sim-help

sim: sim-sbox sim-core
	@echo ""
	@echo "================================="
	@echo " All simulation stages passed"
	@echo "================================="

vectors: $(GOLDEN_SBOX) $(GOLDEN_KAT)

$(GOLDEN_SBOX):
	@echo "================================="
	@echo " Generating golden vector files"
	@echo "================================="
	@$(PYTHON) -c "import os; os.makedirs('$(VEC_DIR)', exist_ok=True)"
	$(PYTHON) $(SCRIPTS_DIR)/gen_sbox_golden.py
	@echo ""
	@echo "   Done -> $(GOLDEN_SBOX)"
	@echo "================================="

$(GOLDEN_KAT):
	@echo "================================="
	@echo " Generating AES KAT vector files"
	@echo "================================="
	@$(PYTHON) -c "import os; os.makedirs('$(VEC_DIR)', exist_ok=True)"
	$(PYTHON) $(SCRIPTS_DIR)/gen_aes_kat.py
	@echo ""
	@echo "   Done -> $(GOLDEN_KAT), $(GOLDEN_KEXP)"
	@echo "================================="

# Simulation recipe ============================================
# $(call run_sim,TOP_MODULE,DUT_FILES,TB_FILE)
# No spaces after commas in call — spaces become part of arg
define run_sim
	@echo ""
	@echo "================================="
	@echo " Simulation: $(1)"
	@echo "================================="
	@$(PYTHON) -c "import os; os.makedirs('$(LOG_DIR)', exist_ok=True)"
	cd $(PROJECT_ROOT) && $(XVLOG) --sv $(2) $(3) --log $(LOG_DIR)/$(1)_compile.log
	cd $(PROJECT_ROOT) && $(XELAB) $(1) --snapshot $(1)_snap --debug typical --log $(LOG_DIR)/$(1)_elab.log
	cd $(PROJECT_ROOT) && $(XSIM) $(1)_snap --runall --log $(LOG_DIR)/$(1)_sim.log
	@echo ""
	@echo "   Log: $(LOG_DIR)/$(1)_sim.log"
	@echo "================================="
endef

# Simulation stages ============================================

# Stage 1 — S-box isolation
sim-sbox: $(GOLDEN_SBOX) $(DUT_SBOX) $(TB_SBOX)
	$(call run_sim,tb_aes_sbox,$(DUT_SBOX),$(TB_SBOX))

# Stage 2 — Full AES-256 core KAT
sim-core: $(GOLDEN_KAT) $(GOLDEN_KEXP) $(DUT_CORE) $(TB_CORE)
	$(call run_sim,tb_aes_core,$(DUT_CORE),$(TB_CORE))

# Stage 3 — AXI wrapper (uncomment when TB is written)
# sim-axi: $(GOLDEN_SBOX) $(DUT_AXI) $(TB_AXI)
# 	$(call run_sim,tb_aes_axi,$(DUT_AXI),$(TB_AXI))

# Utilities ====================================================
check-sim:
	@echo "Checking simulation prerequisites..."
	@echo "   xvlog: $(XVLOG)"
	@$(XVLOG) --version
	@echo "   Python: $(PYTHON)"
	@$(PYTHON) --version
	@echo "   SRC dir:"
	@$(PYTHON) -c "import os; print('   $(SRC_DIR): EXISTS' if os.path.isdir('$(SRC_DIR)') else '   $(SRC_DIR): NOT FOUND')"
	@echo "   Vectors:"
	@$(PYTHON) -c "import os; print('   sbox_golden.hex: EXISTS' if os.path.exists('$(GOLDEN_SBOX)') else '   sbox_golden.hex: NOT FOUND - run make vectors')"
	@$(PYTHON) -c "import os; print('   aes_kat.hex:     EXISTS' if os.path.exists('$(GOLDEN_KAT)') else '   aes_kat.hex:     NOT FOUND - run make vectors')"
	@$(PYTHON) -c "import os; print('   aes_key_exp.hex: EXISTS' if os.path.exists('$(GOLDEN_KEXP)') else '   aes_key_exp.hex: NOT FOUND - run make vectors')"

check-sim:
	@echo "Checking simulation prerequisites..."
	@echo "   xvlog: $(XVLOG)"
	@$(XVLOG) --version
	@echo "   Python: $(PYTHON)"
	@$(PYTHON) --version
	@echo "   SRC dir:"
	@$(PYTHON) -c "import os; print('   $(SRC_DIR): EXISTS' if os.path.isdir('$(SRC_DIR)') else '   $(SRC_DIR): NOT FOUND')"
	@echo "   Vectors:"
	@$(PYTHON) -c "import os; print('   sbox_golden.hex: EXISTS' if os.path.exists('$(GOLDEN_SBOX)') else '   sbox_golden.hex: NOT FOUND - run make vectors')"
	@$(PYTHON) -c "import os; print('   aes_kat.hex:     EXISTS' if os.path.exists('$(GOLDEN_KAT)') else '   aes_kat.hex:     NOT FOUND - run make vectors')"

sim-help:
	@echo ""
	@echo "HDL Simulation Targets"
	@echo "=============================="
	@echo ""
	@echo "Prerequisite:"
	@echo "  make vectors     - Generate golden reference files (run once)"
	@echo ""
	@echo "Simulation Stages:"
	@echo "  make sim-sbox    - Stage 1: S-box exhaustive verification"
	@echo "  make sim-core    - Stage 2: Full AES-256 core KAT"
	@echo "  make sim         - All stages in sequence"
	@echo ""
	@echo "Utilities:"
	@echo "  make check-sim   - Verify xvlog/xsim are accessible"
	@echo "  make clean-sim   - Remove logs/, xsim.dir/, *.pb, *.wdb"
	@echo ""
	@echo "Configuration:"
	@echo "  VIVADO_BIN=$(VIVADO_BIN)"
	@echo "  PROJECT_ROOT=$(PROJECT_ROOT)"
	@echo "  SRC_DIR=$(SRC_DIR)"
	@echo ""
	@echo "Examples:"
	@echo "  make vectors sim-sbox"
	@echo "  make sim"
	@echo ""