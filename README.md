# AXI4-Lite UVM Verification Environment

---

## Introduction 

A UVM verification environment for a simplified AXI4-Lite slave. AXI4-Lite is a simple memory-mapped register interface. It has 5 independent channels: 

| Channel | Direction          | Purpose              |
| ------- | ------------------ | -------------------- |
| **AW**  | Master $\to$ Slave | Write address        |
| **W**   | Master $\to$ Slave | Write data           |
| **B**   | Slave $\to$ Master | Write response       |
| **AR**  | Master $\to$ Slave | Read address         |
| **R**   | Slave $\to$ Master | Read data + response |

Every channel uses `VALID/READY` handshake. A transfer happens only when `VALID/READY` are both 1 on a clock edge. Both signals make master and slave don't need to be ready at same time. AXI4-Lite uses a fixed 32- or 64-bit data width and every read and write operation consists of exactly one data transfer per address phase.

---
### Write transaction 

       MASTER                   SLAVE

                 AW
       AWADDR  --------------->
       AWVALID --------------->
               <--------------- AWREADY

                 W
       WDATA   --------------->
       WSTRB   --------------->
       WVALID  --------------->
               <--------------- WREADY

                 B
               <--------------- BRESP
               <--------------- BVALID
       BREADY  --------------->

#### Instance : `write 0x12345678` $\to$ `address 0x1000`

**Step 1 : Write address (AW)**

Master sends   `AWADDR = 0x1000`, `AWVALID = 1`
Slave responds `AWREADY = 1` 

**Step 2 : Write data (W)**

Master sends   `WDATA = 0x12345678`, `WSTRB = 4'b1111`, `AWVALID = 1`
  - `WSTRB[0]` $\to$ `WDATA[7:0]`
  - `WSTRB[1]` $\to$ `WDATA[15:8]`
  - `WSTRB[2]` $\to$ `WDATA[23:16]`
  - `WSTRB[3]` $\to$ `WDATA[31:24]`
  
Slave responds `WREADY = 1` 

**Step 3 : Write response (B)**

Slave sends     `BVALID = 1`, `BRESP = 2'b00` 
  - `2'b00 = OKAY`, Transaction succeeded
  - `2'b01 = EXOKAY`, exclusive okay, don't support in AXI4-lite 
  - `2'b10 = SLAVERR`, slave error (e.g., accessing an invalid register address)
  - `2'b11 = DECERR`, decode error (e.g., no slave exists at the targeted address)
  
Master responds `BREADY = 1` 

---

### Read transaction

        MASTER                  SLAVE

                  AR
       ARADDR  --------------->
       ARVALID --------------->
               <--------------- ARREADY

                  R 
               <--------------- RDATA
               <--------------- RRESP
               <--------------- RVALID
        RREADY --------------->

#### Instance : `read 0x12345678` $\leftarrow$ `address 0x1000`

**Step 1 : Read address (AR)**

Master sends   `ARADDR = 0x1000`, `ARVALID = 1`
Slave responds `ARREADY = 1` 

**Step 2 : Read data (W)**

Slave sends   `RDATA = 0x12345678`, `RRESP = 2'b00`, `RVALID = 1`
Master responds `RREADY = 1` 

---

## Directory structure

```
axi4lite_uvm/
├── rtl/
│   └── axi4lite_slave.sv       -- DUT: simple AXI4-Lite slave, NUM_REGS x 32-bit reg file
├── tb/
│   ├── axi4lite_if.sv          -- interface with driver/monitor clocking blocks + modports
│   ├── axi4lite_txn.sv         -- transaction (uvm_sequence_item)
│   ├── axi4lite_sequencer.sv   -- uvm_sequencer typedef
│   ├── axi4lite_sequences.sv   -- directed write/read seqs + randomized traffic seq
│   ├── axi4lite_driver.sv      -- drives transactions onto the bus (AW/W concurrent, timeout-protected)
│   ├── axi4lite_monitor.sv     -- passively reconstructs transactions, broadcasts via analysis port
│   ├── axi4lite_agent.sv       -- driver + sequencer + monitor container (active/passive capable)
│   ├── axi4lite_scoreboard.sv  -- shadow-register-model checker
│   ├── axi4lite_env.sv         -- top-level environment (agent + scoreboard)
│   ├── axi4lite_test.sv        -- base_test, smoke_test, random_test
│   ├── axi4lite_pkg.sv         -- package bundling all `include`d class files
│   └── tb_top.sv               -- clock/reset gen, DUT+interface instantiation, run_test()
├── sim/
│   └── Makefile                -- run targets for Questa / VCS / Xcelium
└── README.md
```

## How to run

```bash
cd sim
make questa TEST=axi4lite_smoke_test          # directed write/read-back smoke test
make questa TEST=axi4lite_random_test SEED=42  # constrained-random regression, reproducible via seed
```

Swap `questa` for `vcs` or `xrun` depending on what's available to you. Set
`$UVM_HOME` to your UVM library install path first if using Questa.

## Architecture notes (useful for interview discussion)

- **AW/W independence**: the driver drives the AW and W channels
  *concurrently* via `fork...join`, matching the AXI4-Lite spec's allowance
  for these to complete in either order. The monitor mirrors this with its
  own concurrent `fork...join` when reconstructing writes.
- **Timeout protection**: every handshake wait uses the
  `fork...join_any` + `disable fork` pattern (Q20) so a stuck `READY`/`VALID`
  produces a clean `` `uvm_error `` instead of an indefinite hang.
- **Clocking blocks**: the interface uses separate `drv_cb`/`mon_cb` clocking
  blocks with input/output skew, avoiding testbench-vs-RTL sampling races
  (see the CDC/clocking-block discussion in your notes) — the driver and
  monitor never touch raw interface signals directly, only through their
  respective clocking block.
- **Scoreboard as shadow register model**: rather than comparing two
  independently-generated streams, the scoreboard maintains its own
  internal copy of the DUT's register file, updated on every observed
  write and checked on every observed read — this is the natural
  predecessor to a full UVM RAL model with a `uvm_reg_predictor`.
- **Boundary-value stimulus**: `axi4lite_random_seq` deliberately biases
  90% of addresses in-range and 10% out-of-range via `dist`, so SLVERR
  handling gets meaningfully exercised rather than being a rare accident
  of uniform randomization (same principle as the Q27 Ethernet
  frame-length discussion, applied to address space).

## Next steps / extension points (in suggested order)

1. **Functional coverage** (Q41-46): add a `covergroup` sampling `op`,
   address region (in-range low/high halves, out-of-range), `wstrb`
   patterns, and a `cross` of `op` x address-region. This is the most
   natural next addition and directly extends what you already have.
2. **UVM RAL** (Q93-97): replace the shadow-register-model scoreboard with
   a proper `uvm_reg_block` + `uvm_reg` model, a `uvm_reg_adapter`
   translating `uvm_reg_bus_op` to/from `axi4lite_txn`, and a
   `uvm_reg_predictor` wired to the monitor's analysis port. This is the
   single highest-value addition for your target companies' interviews.
3. **Outstanding-transaction handling** (AMD-flavored extension): the
   current driver processes one transaction at a time; a stronger version
   pipelines multiple outstanding writes/reads and the scoreboard tracks
   them via address/ID matching rather than strict arrival order.
4. **Error injection via factory override** (Q59): write a
   `axi4lite_error_injecting_driver` that occasionally drives an
   unaligned address or drops `WSTRB` bits, and swap it in via
   `set_type_override` in a dedicated negative test -- demonstrates the
   factory mechanism concretely rather than just describing it.
5. **Assertions** (Q47-55): add an SVA checker module bound to the
   interface (or the DUT) enforcing protocol rules directly -- e.g. "AWVALID
   must not deassert before AWREADY," "RDATA/RRESP must be `$stable` while
   RVALID is high and RREADY is low" -- as a structural complement to the
   scoreboard's data checking.
6. **Regression scripting**: a small Python/Perl script that launches
   `axi4lite_random_test` across N seeds in parallel, greps each log for
   `UVM_ERROR`/`UVM_FATAL` counts, and prints a pass/fail summary table --
   directly addresses the regression-automation gap flagged from the
   Apple JD.
