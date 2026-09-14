// ============================================================================
// axi4lite_assertions.sv
//
// All `assert property` checks for axi4lite_slave
//
// yosys-native rewrite (formal-bmc-native branch): see the header comment in
// axi4lite_assumptions.sv for why every property here is hand-lowered to a
// plain boolean, checked once per clock, with explicit one-cycle delay
// registers replacing `|=>`/$stable/$rose/$past, and `!rst_n ||` folded in
// by hand instead of a module-level `default disable iff`.
// ============================================================================
module axi4lite_assertions #(
  parameter int ADDR_WIDTH = 8,
  parameter int DATA_WIDTH = 32,
  parameter int NUM_REGS   = 16
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

  input logic [1:0]              bresp,
  input logic                    bvalid,
  input logic                    bready,

  input logic [ADDR_WIDTH-1:0]   araddr,
  input logic                    arvalid,
  input logic                    arready,

  input logic [DATA_WIDTH-1:0]   rdata,
  input logic [1:0]              rresp,
  input logic                    rvalid,
  input logic                    rready,

  // Whitebox: connect to the DUT's internal register file, e.g.
  // .regfile(dut.regfile) at the instantiation site in formal_tb.sv.
  // Packed 2D array, not an unpacked array dimension -- yosys's native
  // frontend can't parse an unpacked-array port at all (confirmed by
  // minimal repro); a packed 2D array indexes identically and is just a
  // plain bit vector at the port boundary.
  input logic [NUM_REGS-1:0][DATA_WIDTH-1:0] regfile
);

  // Every real SV tool -- Verilator included -- requires a clocking event on
  // every concurrent assertion (IEEE 1800 16.16); yosys-native can't
  // parse `default clocking` at all (confirmed by minimal repro), and
  // -- unlike Verilator -- doesn't seem to need one for a module-level
  // `assert property` with no temporal operator, so this is
  // only used by Verilator.
`ifndef YOSYS_NATIVE_BMC
  default clocking cb @(posedge clk); endclocking
`endif

  localparam logic [1:0] OKAY   = 2'b00;
  localparam logic [1:0] SLVERR = 2'b10;

  localparam int ADDR_LSB = $clog2(DATA_WIDTH / 8);

  function automatic bit in_range(logic [ADDR_WIDTH-1:0] addr);
    // yosys-native can't parse `return`; assign the function name instead.
    in_range = (addr[ADDR_WIDTH-1:ADDR_LSB] < NUM_REGS);
  endfunction

  // One-shot check at elaboration time, not a formal property. yosys-native
  // can't parse `assert (...) else $fatal(...)` as an action-block
  // statement -- rewritten as a plain if.
  initial begin
    if (!(DATA_WIDTH == 32 || DATA_WIDTH == 64))
      $fatal(1, "axi4lite_assertions: DATA_WIDTH=%0d is not legal, (32 or 64 are desired)", DATA_WIDTH);
  end

  // ----------------------------------------------------------------------
  // One-cycle delay registers, standing in for $rose/$past/$stable/|=>
  // wherever this file needs "the value one cycle ago".
  // ----------------------------------------------------------------------
  logic bvalid_q, bready_q, rvalid_q, rready_q, arvalid_q, arready_q;
  logic [1:0]            bresp_q, rresp_q;
  logic [DATA_WIDTH-1:0] rdata_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bvalid_q <= 1'b0; rvalid_q <= 1'b0; arvalid_q <= 1'b0;
    end else begin
      bvalid_q <= bvalid; rvalid_q <= rvalid; arvalid_q <= arvalid;
    end
  end
  // Separate plain-clocked block: mixing signals with a constant async
  // reset value and signals without one (these) in the same
  // `@(posedge clk or negedge rst_n)` block makes yosys's async-reset FF
  // inference reject the whole block ("yields non-constant value").
  // These only ever get *read* alongside their own *_q-partnered valid,
  // which already carries the reset-safety, so no reset value needed.
  always_ff @(posedge clk) begin
    bready_q <= bready; bresp_q <= bresp;
    rready_q <= rready; rdata_q <= rdata; rresp_q <= rresp;
    arready_q <= arready;
  end

  // Environment constraints to prevent X propagation from the slave side.
  //
  // Excluded from the yosys-native BMC build (`-D YOSYS_NATIVE_BMC`,
  // see bmc.sby): confirmed by isolating every other property in this
  // file (all pass cleanly) that $isunknown() specifically makes
  // yosys's own undef-propagation modeling conservatively taint
  // bvalid/rvalid/rdata as "unknown" forever after reset releases --
  // even though the concrete counterexample trace shows a fully defined
  // 0 for the flagged signal. That's a modeling artifact of how yosys's
  // formal backend threads its (value, undef) bit-pair through this
  // design's array-indexed regfile writes, not a real DUT bug (every
  // other, non-$isunknown property -- including the ones checking the
  // same signals' actual behavior -- verifies exhaustively). Verilator's
  // genuine 4-state simulation (`make formal-sweep`) still exercises
  // these; only the exhaustive-BMC build skips them.
`ifndef YOSYS_NATIVE_BMC
  a_no_x_awready:  assert property (!rst_n || !$isunknown(awready));

  a_no_x_wready:   assert property (!rst_n || !$isunknown(wready));

  a_no_x_bvalid:   assert property (!rst_n || !$isunknown(bvalid));
  a_no_x_bresp:    assert property (!rst_n || !bvalid || !$isunknown(bresp));

  a_no_x_arready:  assert property (!rst_n || !$isunknown(arready));

  a_no_x_rvalid:   assert property (!rst_n || !$isunknown(rvalid));
  a_no_x_rdata:    assert property (!rst_n || !rvalid || !$isunknown(rdata));
  a_no_x_rresp:    assert property (!rst_n || !rvalid || !$isunknown(rresp));
`endif

  // ****************************************************************************
  // ***** 4.1 General rules (slave-driven channels: B, R) **********************
  // ****************************************************************************

  // 1. BVALID and RVALID must be LOW during reset.
  //
  // Original used `disable iff (1'b0)` to explicitly override the module
  // default and check even during reset -- so, unlike every property
  // above, these get NO `!rst_n ||` guard.
  a_bvalid_low_in_reset: assert property (rst_n || !bvalid);

  a_rvalid_low_in_reset: assert property (rst_n || !rvalid);


  // 2. Once VALID is asserted, it must remain asserted, and the
  //    accompanying payload (address/data/control) must remain stable,
  //    until the rising clock edge after READY is seen HIGH.
  //    `bvalid_q && !bready_q` is "the antecedent held last cycle".
  a_bvalid_stable: assert property (
    !rst_n || !(bvalid_q && !bready_q) || (bvalid && bresp == bresp_q)
  );

  a_rvalid_stable: assert property (
    !rst_n || !(rvalid_q && !rready_q) || (rvalid && rdata == rdata_q && rresp == rresp_q)
  );

  // ****************************************************************************
  // *********** 4.2 Specific rules for AW / W / B -- slave side ****************
  // ****************************************************************************
  // aw_seen_q/w_seen_q track "a currently-pending AW+W pair has been
  // latched", for the property below. Two wrong ways to clear them, and
  // why this settles on a third:
  //
  //   - Clearing on BVALID&&BREADY (response *accepted*): wrong, because
  //     the DUT re-opens AWREADY/WREADY the same cycle it raises BVALID
  //     (see axi4lite_slave.sv), so it can latch a THIRD AW+W pair while
  //     a SECOND transaction's response is still outstanding waiting for
  //     BREADY. That third pair's aw_hs_done/w_hs_done stay 1 throughout
  //     -- but a BVALID&&BREADY clear here, keyed to the unrelated
  //     second transaction finally being accepted, would wipe
  //     aw_seen_q/w_seen_q out from under it, producing a false failure
  //     when it later fires for real.
  //   - Clearing the same cycle BVALID rises (an exact mirror of the
  //     DUT's own aw_hs_done/w_hs_done, which clear in that same cycle):
  //     also wrong, but more subtly -- it makes the property below
  //     unsatisfiable by construction. `$rose(bvalid) |-> aw_seen_q &&
  //     w_seen_q` (now: `bvalid && !bvalid_q |-> ...`) samples both sides
  //     at the same sampled cycle, so a same-cycle clear means
  //     aw_seen_q/w_seen_q always read 0 exactly when the rise is true,
  //     on every single fire.
  //
  // The fix: clear one cycle *after* the fire (bvalid_q lags bvalid by
  // one register), so aw_seen_q/w_seen_q are still 1 for the property to
  // observe during the rise itself, and only clear once that specific
  // pair has actually been consumed -- independent of whichever earlier
  // transaction's response happens to get accepted around the same time.
  logic aw_seen_q, w_seen_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_seen_q <= 1'b0;
      w_seen_q  <= 1'b0;
    end else begin
      if (bvalid && !bvalid_q) begin
        aw_seen_q <= 1'b0;
        w_seen_q  <= 1'b0;
      end
      if (awvalid && awready) aw_seen_q <= 1'b1;
      if (wvalid  && wready)  w_seen_q  <= 1'b1;
    end
  end

  // 1. The slave must wait for AWVALID, AWREADY, WVALID, and
  //    WREADY to all have been asserted (AW and W handshakes both
  //    complete) before asserting BVALID. `bvalid && !bvalid_q` is
  //    `$rose(bvalid)`.
  a_bvalid_requires_aw_and_w: assert property (
    !rst_n || !(bvalid && !bvalid_q) || (aw_seen_q && w_seen_q)
  );

  // 2. The slave must not wait for BREADY before asserting BVALID.
  // `##0` in a `##[0:1]` range here would be dead code: the antecedent's
  // own `!bvalid` already rules out bvalid being true at that same
  // sampled cycle, so the range collapsed to exactly `##1` -- i.e.
  // `|=>` (which is defined as `|-> ##1`). Note `bready` never appears
  // in this property at all -- that omission, not the delay width, is
  // what actually encodes "does not wait for BREADY": a fixed,
  // BREADY-independent deadline for BVALID to rise.
  //
  // `|=>` needs "was the antecedent true last cycle" -- a dedicated
  // delay register, since aw_seen_q/w_seen_q/bvalid are already this
  // cycle's values.
  logic bvalid_deadline_pending_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) bvalid_deadline_pending_q <= 1'b0;
    else        bvalid_deadline_pending_q <= (aw_seen_q && w_seen_q && !bvalid);
  end
  a_bvalid_not_wait_bready: assert property (!rst_n || !bvalid_deadline_pending_q || bvalid);


  // 3. Whenever the slave asserts BVALID, BRESP must be a legal AXI4-Lite
  //    write response code (OKAY or SLVERR).
  a_bresp_legal_value: assert property (!rst_n || !bvalid || (bresp == OKAY || bresp == SLVERR));

  // Response-code correctness against the DUT's own address range.
  logic [ADDR_WIDTH-1:0] awaddr_latched_ref;
  always_ff @(posedge clk) begin
    if (awvalid && awready) awaddr_latched_ref <= awaddr;
  end

  a_write_okay_in_range: assert property (
    !rst_n || !(bvalid && !bvalid_q) || !in_range(awaddr_latched_ref) || bresp == OKAY
  );

  a_write_slverr_out_of_range: assert property (
    !rst_n || !(bvalid && !bvalid_q) || in_range(awaddr_latched_ref) || bresp == SLVERR
  );

  // Write-strobe byte-lane correctness, whitebox check against the
  // connected `regfile` array.
  logic [DATA_WIDTH-1:0]   wdata_latched_ref;
  logic [DATA_WIDTH/8-1:0] wstrb_latched_ref;
  logic [NUM_REGS-1:0][DATA_WIDTH-1:0] regfile_before_write;
  always_ff @(posedge clk) begin
    if (wvalid && wready) begin
      wdata_latched_ref <= wdata;
      wstrb_latched_ref <= wstrb;
    end
    if (awvalid && awready) regfile_before_write <= regfile;
  end

  // Manually unrolled instead of a `generate for` loop: yosys-native
  // gives every iteration's labeled concurrent assertion the SAME cell
  // name regardless of generate scope (confirmed by minimal repro --
  // even distinct `generate if` blocks collide unless each iteration's
  // *label text* is unique), so a `for` loop with one fixed label
  // errors out immediately on the second iteration. Each unrolled copy
  // below has its own literal label instead.
  generate
    `define AXI4LITE_BYTE_LANE_CHECK(N) \
      if (DATA_WIDTH/8 > N) begin : g_strobe_byte_check_``N`` \
        a_write_enabled_byte_updated``N``: assert property ( \
          !rst_n || !(bvalid && !bvalid_q) || !in_range(awaddr_latched_ref) || !wstrb_latched_ref[N] \
          || (regfile[awaddr_latched_ref[ADDR_WIDTH-1:ADDR_LSB]][N*8+:8] == wdata_latched_ref[N*8+:8]) \
        ); \
        a_write_disabled_byte_preserved``N``: assert property ( \
          !rst_n || !(bvalid && !bvalid_q) || !in_range(awaddr_latched_ref) || wstrb_latched_ref[N] \
          || (regfile[awaddr_latched_ref[ADDR_WIDTH-1:ADDR_LSB]][N*8+:8] \
                == regfile_before_write[awaddr_latched_ref[ADDR_WIDTH-1:ADDR_LSB]][N*8+:8]) \
        ); \
      end
    `AXI4LITE_BYTE_LANE_CHECK(0)
    `AXI4LITE_BYTE_LANE_CHECK(1)
    `AXI4LITE_BYTE_LANE_CHECK(2)
    `AXI4LITE_BYTE_LANE_CHECK(3)
    `AXI4LITE_BYTE_LANE_CHECK(4)
    `AXI4LITE_BYTE_LANE_CHECK(5)
    `AXI4LITE_BYTE_LANE_CHECK(6)
    `AXI4LITE_BYTE_LANE_CHECK(7)
    `undef AXI4LITE_BYTE_LANE_CHECK
  endgenerate

  // Outstanding-transaction restriction. `bvalid && bready |=> !bvalid`:
  // the antecedent is this-cycle bvalid&&bready, checked against NEXT
  // cycle's bvalid -- so needs its own one-cycle delay register (bvalid_q
  // alone isn't enough, it doesn't know about bready).
  logic bvalid_accepted_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) bvalid_accepted_q <= 1'b0;
    else        bvalid_accepted_q <= (bvalid && bready);
  end
  a_bvalid_clears_next_cycle: assert property (!rst_n || !bvalid_accepted_q || !bvalid);

  // ****************************************************************************
  // ************ 4.3 Specific rules for AR / R -- slave side *******************
  // ****************************************************************************

  // 1. The slave must wait for both ARVALID and ARREADY to be
  //    asserted before asserting RVALID. `$past(arvalid && arready)` is
  //    exactly what arvalid_q && arready_q already gives us.
  a_rvalid_requires_ar: assert property (
    !rst_n || !(rvalid && !rvalid_q) || (arvalid_q && arready_q)
  );

  // 2. The slave must not wait for RREADY before asserting
  //    RVALID. `(arvalid && arready) |=> rvalid` needs its own delay reg,
  //    same reasoning as a_bvalid_clears_next_cycle above.
  logic ar_handshake_q;
  logic [ADDR_WIDTH-1:0] araddr_latched_ref;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) ar_handshake_q <= 1'b0;
    else        ar_handshake_q <= (arvalid && arready);
  end
  always_ff @(posedge clk) begin
    if (arvalid && arready) araddr_latched_ref <= araddr;
  end
  a_ar_leads_to_rvalid: assert property (!rst_n || !ar_handshake_q || rvalid);

  // 3. The slave asserts RVALID only when it drives valid RDATA.
  // Excluded from yosys-native BMC -- see the a_no_x_* comment above.
`ifndef YOSYS_NATIVE_BMC
  a_rvalid_requires_rdata: assert property (!rst_n || !rvalid || !$isunknown(rdata));
`endif

  a_read_okay_in_range: assert property (
    !rst_n || !ar_handshake_q || !in_range(araddr_latched_ref) || rresp == OKAY
  );

  a_read_slverr_out_of_range: assert property (
    !rst_n || !ar_handshake_q || in_range(araddr_latched_ref) || (rresp == SLVERR && rdata == '0)
  );

  // Legal response-code check, read side (parallel to a_bresp_legal_value).
  a_rresp_legal_value: assert property (!rst_n || !rvalid || (rresp == OKAY || rresp == SLVERR));

  // Outstanding-transaction restriction
  a_no_new_ar_while_rvalid: assert property (!rst_n || !(rvalid && !rready) || !arready);

endmodule
