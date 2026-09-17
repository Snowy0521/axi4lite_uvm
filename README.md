# AXI4-Lite UVM + Formal Verification Environment

---

## Introduction

A verification environment for a simplified AXI4-Lite slave, combining a constrained-random UVM testbench with a SystemVerilog Assertions (SVA) formal environment. AXI4-Lite is AMBA's lightweight memory-mapped register interface defined in [`spec/IHI0022E_amba_axi_and_ace_protocol_spec.pdf`](spec/IHI0022E_amba_axi_and_ace_protocol_spec.pdf). The DUT's concrete behavior is documented in [`spec/axi4lite_slave_spec.md`](spec/axi4lite_slave_spec.md).


---

## Directory structure

```
axi4lite_uvm/
├── rtl/
│   └── axi4lite_slave.sv           -- DUT: simple AXI4-Lite slave, NUM_REGS x 32-bit reg file
├── tb/
│   ├── axi4lite_if.sv              -- interface with driver/monitor clocking blocks + modports
│   ├── axi4lite_txn.sv             -- transaction (uvm_sequence_item)
│   ├── axi4lite_sequencer.sv       -- uvm_sequencer typedef
│   ├── axi4lite_sequences.sv       -- directed write/read seqs + randomized traffic seq
│   ├── axi4lite_driver.sv          -- drives transactions onto the bus (AW/W concurrent, timeout-protected)
│   ├── axi4lite_monitor.sv         -- passively reconstructs transactions, broadcasts via analysis port
│   ├── axi4lite_agent.sv           -- driver + sequencer + monitor container (active/passive capable)
│   ├── axi4lite_scoreboard.sv      -- shadow-register-model checker
│   ├── axi4lite_coverage_collector.sv -- functional coverage (op x address-region, wstrb, resp)
│   ├── axi4lite_env.sv             -- top-level environment (agent + scoreboard + coverage)
│   ├── axi4lite_tests.sv           -- base_test, smoke_test, random_test
│   ├── axi4lite_pkg.sv             -- package bundling all `include`d class files
│   ├── tb_top.sv                   -- clock/reset gen, DUT+interface instantiation, run_test()
│   └── tb_simple.sv                -- plain (non-UVM) direct-drive sanity check
├── formal/
│   ├── axi4lite_assumptions.sv     -- `assume property`: constrains the environment to legal masters
│   ├── axi4lite_assertions.sv      -- `assert property`: the DUT's own obligations (incl. whitebox WSTRB checks)
│   ├── axi4lite_covers.sv          -- `cover property`: reachability for spec rules with no assert/assume
│   ├── axi4lite_formal_driver.sv   -- legal-master constrained-random driver for simulation-based checking
│   └── formal_tb.sv                -- top-level formal environment, wires the above + the DUT together
├── spec/
│   ├── axi4lite_slave_spec.md      -- this DUT's concrete behavior, traced back to IHI0022E rules
│   └── IHI0022E_amba_axi_and_ace_protocol_spec.pdf -- the normative AMBA AXI4-Lite spec
├── sim/
│   └── Makefile                    -- Verilator run targets for both tb/ (UVM) and formal/
└── README.md
```

## How to run

Requires Verilator (`$UVM_HOME` pointed at a UVM class library for the `uvm`/`uvm-sweep` targets; the
`formal`/`formal-sweep` targets need no UVM). All targets live in [`sim/Makefile`](sim/Makefile):

```bash
cd sim
make uvm TEST=axi4lite_smoke_test              # directed write/read-back smoke test
make uvm TEST=axi4lite_random_test SEED=42     # constrained-random regression, reproducible via seed
make uvm-sweep TEST=axi4lite_random_test N=50  # build once, run seeds 1..N, report which (if any) failed

make formal SEED=7                             # assume/assert/cover env, bounded randomly-driven sim
make formal-sweep N=50                         # same idea: build once, sweep seeds, report failures

make verilator_simple                          # plain (non-UVM) direct-drive sanity check via tb_simple.sv
make clean
```



## Next steps / extension points

1. **UVM RAL**
2. **Outstanding-transaction handling**
3. **Error injection via factory override**
4. **Implemente AWPROT/ARPROT**
5. **Cover-point closure reporting for `formal/`**
6. **Real formal proof for `formal/`**
7. **Wire both sweeps into CI**
