# ============================================================================
# Makefile -- run targets for verilator simulator
# Adjust UVM_HOME / tool invocation flags to match your local install.
# TEST defaults to the smoke test; override on the command line, e.g.:
#   make verilator TEST=axi4lite_random_test
# ============================================================================

TEST      ?= axi4lite_smoke_test
SEED      ?= 42
RTL_DIR   := ../rtl
TB_DIR    := ../tb

UVM_HOME  ?= $(HOME)/uvm-kit/1800.2-2020.3.1/src

RTL_FILES := $(RTL_DIR)/axi4lite_slave.sv
TB_FILES  := $(TB_DIR)/axi4lite_if.sv \
             $(TB_DIR)/axi4lite_pkg.sv \
             $(TB_DIR)/tb_top.sv


VERILATOR       ?= verilator
VERILATOR_FLAGS ?= --binary --timing --trace -Wno-fatal -j $(shell nproc) \
                   --timescale 1ns/1ps \
                   -Wno-TIMESCALEMOD \
                   -Wno-WIDTHEXPAND \
                   -Wno-WIDTHTRUNC

UVM_VERBOSITY   ?= UVM_LOW
verilator:
	$(VERILATOR) $(VERILATOR_FLAGS) -sv --top-module tb_top \
	     +incdir+$(UVM_HOME) +define+UVM_NO_DPI \
	     +incdir+$(TB_DIR) +incdir+$(RTL_DIR) \
	     $(UVM_HOME)/uvm_pkg.sv \
	     $(RTL_FILES) $(TB_FILES) \
	     -o sim_$(TEST)
	./obj_dir/sim_$(TEST) +UVM_TESTNAME=$(TEST) +ntb_random_seed=$(SEED) +UVM_VERBOSITY=$(UVM_VERBOSITY)




# ============================================================================
# Plain (non-UVM) simple test — tb_simple.sv drives axi4lite_slave directly,
# no UVM agent/package involved. Use this to sanity-check the DUT in
# isolation before/instead of debugging through the full UVM environment.
# ============================================================================
SIMPLE_FILES := $(RTL_FILES) $(TB_DIR)/tb_simple.sv


verilator_simple:
	$(VERILATOR) --binary --timing --trace -Wno-fatal -j $(shell nproc) \
	     -sv --top-module tb_simple \
	     --Mdir obj_dir_simple \
	     +incdir+$(TB_DIR) +incdir+$(RTL_DIR) \
	     $(SIMPLE_FILES) \
	     -o sim_simple
	./obj_dir_simple/sim_simple

clean:
	rm -rf obj_dir obj_dir_simple *.vcd
