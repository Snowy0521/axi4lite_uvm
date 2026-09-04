# ============================================================================
# Makefile -- run targets for common commercial simulators.
# Adjust UVM_HOME / tool invocation flags to match your local install.
# TEST defaults to the smoke test; override on the command line, e.g.:
#   make questa TEST=axi4lite_random_test
# ============================================================================

TEST      ?= axi4lite_smoke_test
SEED      ?= 1
RTL_DIR   := ../rtl
TB_DIR    := ../tb

RTL_FILES := $(RTL_DIR)/axi4lite_slave.sv
TB_FILES  := $(TB_DIR)/axi4lite_if.sv \
             $(TB_DIR)/axi4lite_pkg.sv \
             $(TB_DIR)/tb_top.sv

# --------------------------------------------------------------------------
# Questa/ModelSim
# --------------------------------------------------------------------------
questa:
	vlib work
	vlog -sv +incdir+$(UVM_HOME)/src $(UVM_HOME)/src/uvm_pkg.sv \
	     $(RTL_FILES) $(TB_FILES)
	vsim -c -sv_seed $(SEED) +UVM_TESTNAME=$(TEST) tb_top -do "run -all; quit"

# --------------------------------------------------------------------------
# Synopsys VCS
# --------------------------------------------------------------------------
vcs:
	vcs -sverilog -ntb_opts uvm -full64 \
	    $(RTL_FILES) $(TB_FILES) -o simv
	./simv +UVM_TESTNAME=$(TEST) +ntb_random_seed=$(SEED)

# --------------------------------------------------------------------------
# Cadence Xcelium
# --------------------------------------------------------------------------
xrun:
	xrun -uvm -sv \
	     $(RTL_FILES) $(TB_FILES) \
	     +UVM_TESTNAME=$(TEST) -svseed $(SEED)

clean:
	rm -rf work transcript *.vcd simv* csrc *.log *.history DVEfiles xcelium.d
