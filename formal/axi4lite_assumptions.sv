// ============================================================================
// axi4lite_assumptions.sv
//
// All `assume property` constraints for axi4lite_slave's formal
// environment -- everything a compliant AXI4-Lite *master* is obligated to
// do. Paired with axi4lite_assertions.sv (the DUT's obligations) and
// axi4lite_covers.sv (reachability coverage for rules that have no
// assert/assume of their own); formal_tb.sv wires all three to the DUT.
//
// Organized to mirror axi4lite_slave_spec.md §4:
//   §4.1 General rules      -- master-driven channels (AW, W, AR)
//   §4.2 AW/W/B group       -- master-side obligations only (B is slave-driven)
//   §4.3 AR/R group         -- master-side obligations only (R is slave-driven)
// ============================================================================
module axi4lite_assumptions #(
  parameter int ADDR_WIDTH = 8,
  parameter int DATA_WIDTH = 32
)(
  input logic                    clk,
  input logic                    rst_n,

  input logic [ADDR_WIDTH-1:0]   awaddr,
  input logic                    awvalid,
  input logic                    awready,

  input logic [DATA_WIDTH-1:0]   wdata,
  input logic [DATA_WIDTH/8-1:0] wstrb,
  input logic                    wvalid,
  input logic                    wready,

  input logic                    bvalid,
  input logic                    bready,

  input logic [ADDR_WIDTH-1:0]   araddr,
  input logic                    arvalid,
  input logic                    arready,

  input logic                    rvalid,
  input logic                    rready
);

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // ****************************************************************************
  // ***** 4.1 General rules (master-driven channels: AW, W, AR) *****
  // ****************************************************************************

  // ===============================================================
  // Rule_01: VALID signals must be LOW during reset.
  // Checked without `disable iff`, since that would mask exactly the
  // cycle under test.
  // ===============================================================
  m_awvalid_low_in_reset: assume property (@(posedge clk) !rst_n |-> !awvalid);
  m_wvalid_low_in_reset:  assume property (@(posedge clk) !rst_n |-> !wvalid);
  m_arvalid_low_in_reset: assume property (@(posedge clk) !rst_n |-> !arvalid);

  // ===============================================================
  // Rule_02: once VALID is asserted, it must remain asserted, and the
  // accompanying payload (address/data/control) must remain stable,
  // until the rising clock edge after READY is seen HIGH.
  //
  // NOT an encoding of "transmitter must not wait for READY" (that
  // rule isn't expressible as a waveform property at all -- see the
  // note further down). This only restricts behavior *after* VALID is
  // already high; the absence of any constraint tying VALID to READY
  // *before* it rises is what encodes the "don't wait" rule.
  // ===============================================================
  m_awvalid_stable: assume property (
    awvalid && !awready |=> awvalid && $stable(awaddr)
  );

  m_wvalid_stable: assume property (
    wvalid && !wready |=> wvalid && $stable(wdata) && $stable(wstrb)
  );

  m_arvalid_stable: assume property (
    arvalid && !arready |=> arvalid && $stable(araddr)
  );

  // ===============================================================
  // Environment sanity: no X/Z driven onto the DUT's inputs. Not a
  // spec rule of its own -- without this, a formal tool can "prove"
  // almost anything by driving X and letting it propagate, or
  // generate meaningless X-based counterexamples.
  // ===============================================================
  m_no_x_awvalid: assume property (!$isunknown(awvalid));
  m_no_x_wvalid:  assume property (!$isunknown(wvalid));
  m_no_x_arvalid: assume property (!$isunknown(arvalid));
  m_no_x_awaddr:  assume property (awvalid |-> !$isunknown(awaddr));
  m_no_x_wdata:   assume property (wvalid  |-> !$isunknown(wdata));
  m_no_x_wstrb:   assume property (wvalid  |-> !$isunknown(wstrb));
  m_no_x_araddr:  assume property (arvalid |-> !$isunknown(araddr));
  m_no_x_bready:  assume property (!$isunknown(bready));
  m_no_x_rready:  assume property (!$isunknown(rready));

  // ===============================================================
  // Rules with no assert/assume of their own:
  //
  //   "Transfer occurs only on a clock edge where VALID and READY are
  //    both HIGH" -- a definition, not a constraint; nothing to write.
  //
  //   "The transmitter must not wait for READY before asserting
  //    VALID" -- not expressible from waveforms alone: valid=0 is
  //    indistinguishable, from outside, between "illegally waiting on
  //    ready" and "legitimately has nothing to send yet". Encoded by
  //    *omission* -- no assumption anywhere in this file ties VALID to
  //    READY before VALID rises.
  //
  //   "The receiver may assert READY either before or after VALID" --
  //    a permission granted to the receiver (AWREADY/WREADY/ARREADY),
  //    not an obligation on the master; nothing to constrain.
  //
  // Rule 1 and rule 3 both get `cover` points instead -- see
  // axi4lite_covers.sv, which confirms a formal proof actually reaches
  // the scenarios they describe rather than vacuously passing because
  // some other assumption accidentally makes them unreachable.
  // ===============================================================


  // ****************************************************************************
  // ***** 4.2 AW / W / B group -- master side *****
  // ****************************************************************************

  // ===============================================================
  // Descriptive, non-checkable rules (no property -- the rule-1/3
  // reasoning above also covers the two bullets below: "the master
  // asserts AWVALID/WVALID only when it drives valid information" is
  // exactly as unassertable as "the slave asserts RVALID only when it
  // drives valid data" (see axi4lite_assertions.sv Rule_07's
  // discussion) -- there is no oracle for "valid information" separate
  // from the response/read-data correctness checks that already exist
  // in axi4lite_assertions.sv.
  //
  //   - The master asserts AWVALID only when it drives valid address
  //     and control information.
  //   - The master asserts WVALID only when it drives valid write
  //     data.
  //   - AWVALID/WVALID may arrive in either order or simultaneously --
  //     a permission, not an obligation; covered in axi4lite_covers.sv
  //     instead of asserted.
  //   - The master may assert BREADY before or after BVALID -- same
  //     rule-3 permission as above, applied to the B channel; covered
  //     in axi4lite_covers.sv.
  // ===============================================================

  // Optional: address-alignment constraint (IHI0022E §B1.1.1: every
  // transaction is full-data-bus-width, burst length 1, so a real
  // master's address is inherently word-aligned). axi4lite_slave
  // itself does not check this (spec §6b), so proofs run WITHOUT this
  // assumption also exercise the DUT's behavior on unaligned addresses.
  // Left commented out by default for that reason; uncomment to
  // restrict the environment to only legal-master traffic.
  //
  // localparam int ADDR_LSB = $clog2(DATA_WIDTH / 8);
  // m_awaddr_aligned: assume property (awvalid |-> awaddr[ADDR_LSB-1:0] == '0);


  // ****************************************************************************
  // ***** 4.3 AR / R group -- master side *****
  // ****************************************************************************

  // ===============================================================
  // Descriptive, non-checkable rule (no property -- same reasoning as
  // the AW/W group above):
  //   - The master asserts ARVALID only when it drives valid address
  //     and control information.
  //   - The master may assert RREADY before or after RVALID -- rule-3
  //     permission; covered in axi4lite_covers.sv.
  // ===============================================================

  // Optional address-alignment constraint, AR side (see the AW-side
  // note above for why this stays commented out by default):
  //
  // m_araddr_aligned: assume property (arvalid |-> araddr[ADDR_LSB-1:0] == '0);

endmodule
