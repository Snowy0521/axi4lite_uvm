# ============================================================================
# Makefile -- run targets for verilator simulator
# Adjust UVM_HOME / tool invocation flags to match your local install.
# TEST defaults to the smoke test; override on the command line, e.g.:
#   make uvm TEST=axi4lite_random_test
#
# `uvm-sweep` builds TEST once and runs seeds 1..N (default 20)
# against it, reporting which (if any) failed by parsing each run's UVM
# report summary (UVM_ERROR/UVM_FATAL counts) -- much cheaper than N full
# rebuilds:
#   make uvm-sweep TEST=axi4lite_random_test N=50
#
# `formal` runs the ../formal/ assume/assert/cover environment (flow #2 in
# formal_tb.sv's header comment) -- bounded, randomly-driven simulation, not
# exhaustive formal proof. SEED controls axi4lite_formal_driver.sv's
# randomization for reproducibility, e.g.:
#   make formal SEED=123
# `formal-sweep` builds once and runs seeds 1..N (default 20) against it,
# reporting which (if any) failed -- much cheaper than N full rebuilds:
#   make formal-sweep N=50
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
VERILATOR_FLAGS ?= --binary --timing --trace --coverage -Wno-fatal -j $(shell nproc) \
                   --timescale 1ns/1ps \
                   -Wno-TIMESCALEMOD \
                   -Wno-WIDTHEXPAND \
                   -Wno-WIDTHTRUNC

UVM_VERBOSITY   ?= UVM_LOW
UVM_BIN         := obj_dir/sim_$(TEST)

uvm-build:
	$(VERILATOR) $(VERILATOR_FLAGS) -sv --top-module tb_top \
	     +incdir+$(UVM_HOME) +define+UVM_NO_DPI \
	     +incdir+$(TB_DIR) +incdir+$(RTL_DIR) \
	     $(UVM_HOME)/uvm_pkg.sv \
	     $(RTL_FILES) $(TB_FILES) \
	     -o sim_$(TEST)

uvm: uvm-build
	./$(UVM_BIN) +UVM_TESTNAME=$(TEST) +ntb_random_seed=$(SEED) +UVM_VERBOSITY=$(UVM_VERBOSITY)

uvm-sweep: uvm-build
	@fail=0; \
	for s in $$(seq 1 $(N)); do \
	  out=$$(./$(UVM_BIN) +UVM_TESTNAME=$(TEST) +ntb_random_seed=$$s +UVM_VERBOSITY=$(UVM_VERBOSITY) 2>&1); \
	  errs=$$(echo "$$out" | sed -n 's/^UVM_ERROR :[ \t]*\([0-9][0-9]*\).*/\1/p' | tail -1); \
	  fatals=$$(echo "$$out" | sed -n 's/^UVM_FATAL :[ \t]*\([0-9][0-9]*\).*/\1/p' | tail -1); \
	  if [ -z "$$errs" ] || [ -z "$$fatals" ]; then \
	    echo "seed $$s: FAILED (no UVM report summary found -- crashed or hung?)"; \
	    fail=1; \
	  elif [ "$$errs" -gt 0 ] || [ "$$fatals" -gt 0 ]; then \
	    echo "seed $$s: FAILED (UVM_ERROR=$$errs UVM_FATAL=$$fatals)"; \
	    fail=1; \
	  else \
	    echo "seed $$s: OK"; \
	  fi; \
	done; \
	if [ "$$fail" -eq 0 ]; then \
	  echo "ALL $(N) SEEDS PASSED (TEST=$(TEST))"; \
	else \
	  echo "SOME SEEDS FAILED (TEST=$(TEST))"; \
	  exit 1; \
	fi




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

# ============================================================================
# Formal assume/assert/cover environment -- bounded, randomly-driven
# simulation of formal/axi4lite_assumptions.sv / axi4lite_assertions.sv /
# axi4lite_covers.sv / axi4lite_formal_driver.sv, wired up by
# formal/formal_tb.sv. Own obj_dir (obj_dir_formal) since it's compiled with
# different flags (--assert, no --coverage) than the `verilator` target
# above, and shouldn't share build artifacts with it.
# ============================================================================
FORMAL_DIR   := ../formal
FORMAL_FILES := $(FORMAL_DIR)/axi4lite_assumptions.sv \
                $(FORMAL_DIR)/axi4lite_assertions.sv \
                $(FORMAL_DIR)/axi4lite_covers.sv \
                $(FORMAL_DIR)/axi4lite_formal_driver.sv \
                $(FORMAL_DIR)/formal_tb.sv

FORMAL_BIN := obj_dir_formal/sim_formal

formal-build:
	$(VERILATOR) --binary --timing --assert --trace -Wno-fatal -j $(shell nproc) \
	     --timescale 1ns/1ps \
	     -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
	     -sv --top-module formal_tb \
	     --Mdir obj_dir_formal \
	     +incdir+$(RTL_DIR) \
	     $(RTL_FILES) $(FORMAL_FILES) \
	     -o sim_formal

formal: formal-build
	./$(FORMAL_BIN) +verilator+seed+$(SEED)

N ?= 20
formal-sweep: formal-build
	@fail=0; \
	for s in $$(seq 1 $(N)); do \
	  out=$$(./$(FORMAL_BIN) +verilator+seed+$$s 2>&1); \
	  if echo "$$out" | grep -q '%Error'; then \
	    echo "seed $$s: FAILED"; \
	    echo "$$out" | grep '%Error' | sed 's/^/    /'; \
	    fail=1; \
	  else \
	    echo "seed $$s: OK"; \
	  fi; \
	done; \
	if [ "$$fail" -eq 0 ]; then \
	  echo "ALL $(N) SEEDS PASSED"; \
	else \
	  echo "SOME SEEDS FAILED"; \
	  exit 1; \
	fi

.PHONY: uvm uvm-build uvm-sweep verilator_simple formal formal-build formal-sweep clean

clean:
	rm -rf obj_dir obj_dir_simple obj_dir_formal *.vcd
