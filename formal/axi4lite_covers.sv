// ============================================================================
// axi4lite_covers.sv
//
// All `cover property` points for axi4lite_slave's formal environment --
// extracted from axi4lite_assertions.sv and axi4lite_assumptions.sv into
// one place. These confirm a formal proof actually *reaches* the scenarios
// the spec rules describe (handshake completions, both READY/VALID
// orderings, both response codes, every write-strobe pattern, etc.)
// rather than vacuously passing a proof where some assumption accidentally
// makes them unreachable.
//
// This module is deliberately self-contained: it does not read any
// internal signal from axi4lite_assertions.sv (e.g. its aw_seen_q/
// wstrb_latched_ref), even though a couple of these cover points need the
// same kind of latched/tracked state. Where that's needed (the write-strobe
// coverage below), this file re-derives its own local copy of just enough
// tracking logic to express the cover point, so this module can be
// instantiated independently of axi4lite_assertions.sv if desired.
//
// Organized to mirror axi4lite_slave_spec.md §4, and to mirror where each
// cover point's signals originate:
//   §4.1 General rules      -- one subsection per channel side
//   §4.2 AW/W/B group       -- slave-side cover points, then master-side
//   §4.3 AR/R group         -- slave-side cover points, then master-side
// ============================================================================
module axi4lite_covers #(
  parameter int ADDR_WIDTH = 8,
  parameter int DATA_WIDTH = 32
)(
  input logic                    clk,
  input logic                    rst_n,

  input logic                    awvalid,
  input logic                    awready,

  input logic [DATA_WIDTH/8-1:0] wstrb,
  input logic                    wvalid,
  input logic                    wready,

  input logic [1:0]              bresp,
  input logic                    bvalid,
  input logic                    bready,

  input logic                    arvalid,
  input logic                    arready,

  input logic [1:0]              rresp,
  input logic                    rvalid,
  input logic                    rready
);

  localparam logic [1:0] OKAY   = 2'b00;
  localparam logic [1:0] SLVERR = 2'b10;

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // ****************************************************************************
  // ***** 4.1 General rules -- rule 1 (handshake reachability) and *****
  // ***** rule 3 (both READY-before/after-VALID orderings), per channel *****
  // ****************************************************************************

  // ---- B (slave-driven) ------------------------------------------------
  cp_b_handshake_occurs:  cover property (bvalid && bready);
  cp_b_ready_preasserted: cover property ($rose(bvalid) && bready);
  cp_b_ready_after_valid: cover property (bvalid && !bready ##1 (bvalid throughout bready[->1]));

  // ---- R (slave-driven) --------------------------------------------------
  cp_r_handshake_occurs:  cover property (rvalid && rready);
  cp_r_ready_preasserted: cover property ($rose(rvalid) && rready);
  cp_r_ready_after_valid: cover property (rvalid && !rready ##1 (rvalid throughout rready[->1]));

  // ---- AW (master-driven) -------------------------------------------------
  cp_aw_handshake_occurs:  cover property (awvalid && awready);
  cp_aw_ready_preasserted: cover property ($rose(awvalid) && awready);
  cp_aw_ready_after_valid: cover property (awvalid && !awready ##1 (awvalid throughout awready[->1]));

  // ---- W (master-driven) ---------------------------------------------------
  cp_w_handshake_occurs:  cover property (wvalid && wready);
  cp_w_ready_preasserted: cover property ($rose(wvalid) && wready);
  cp_w_ready_after_valid: cover property (wvalid && !wready ##1 (wvalid throughout wready[->1]));

  // ---- AR (master-driven) --------------------------------------------------
  cp_ar_handshake_occurs:  cover property (arvalid && arready);
  cp_ar_ready_preasserted: cover property ($rose(arvalid) && arready);
  cp_ar_ready_after_valid: cover property (arvalid && !arready ##1 (arvalid throughout arready[->1]));


  // ****************************************************************************
  // ***** 4.2 AW / W / B group *****
  // ****************************************************************************

  // ---- Slave side ----------------------------------------------------------
  cp_write_okay:   cover property ($rose(bvalid) && bresp == OKAY);
  cp_write_slverr: cover property ($rose(bvalid) && bresp == SLVERR);

  // AW/W completion ordering, as observed from the DUT's own AWREADY/WREADY
  // (this is what actually determines when each half's data gets latched).
  cp_aw_before_w: cover property (
    (awvalid && awready && !(wvalid && wready)) ##1 (wvalid && wready)[->1]
  );
  cp_w_before_aw: cover property (
    (wvalid && wready && !(awvalid && awready)) ##1 (awvalid && awready)[->1]
  );
  cp_aw_w_same_cycle: cover property (awvalid && awready && wvalid && wready);

  // Write-strobe pattern coverage: needs the strobe value latched at the
  // W handshake, held until the write commits (mirrors
  // axi4lite_assertions.sv's own wstrb_latched_ref, re-derived locally so
  // this module has no dependency on that one).
  logic [DATA_WIDTH/8-1:0] wstrb_latched_ref;
  always_ff @(posedge clk) begin
    if (wvalid && wready) wstrb_latched_ref <= wstrb;
  end

  cp_wstrb_all_zero: cover property ($rose(bvalid) && wstrb_latched_ref == '0);
  cp_wstrb_partial:  cover property (
    $rose(bvalid) && wstrb_latched_ref != '0 && wstrb_latched_ref != '1
  );
  cp_wstrb_full: cover property ($rose(bvalid) && wstrb_latched_ref == '1);

  // ---- Master side -----------------------------------------------------------
  // AWVALID/WVALID arrival-order coverage, as observed from the master's
  // own VALID signals directly (independent of whether/when the slave
  // accepted each one) -- complements cp_aw_before_w/cp_w_before_aw above,
  // which are keyed to the slave's READY instead.
  cp_aw_before_w_master: cover property (
    (awvalid && !wvalid) ##1 wvalid[->1]
  );
  cp_w_before_aw_master: cover property (
    (wvalid && !awvalid) ##1 awvalid[->1]
  );


  // ****************************************************************************
  // ***** 4.3 AR / R group *****
  // ****************************************************************************

  // ---- Slave side ------------------------------------------------------------
  cp_read_okay:   cover property ($rose(rvalid) && rresp == OKAY);
  cp_read_slverr: cover property ($rose(rvalid) && rresp == SLVERR);

  // ---- Master side ------------------------------------------------------------
  // (No AR-side arrival-order coverage: AR is a single-signal address
  // channel, there's no second signal on this channel to order against.)

endmodule
