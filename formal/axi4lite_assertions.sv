// ============================================================================
// axi4lite_assertions.sv
//
// All `assert property` checks for axi4lite_slave -- everything the DUT
// itself is obligated to do. Paired with axi4lite_assumptions.sv (the
// *environment*'s obligations) and axi4lite_covers.sv (reachability
// coverage for rules that have no assert/assume of their own); formal_tb.sv
// wires all three to the DUT.
//
// Organized to mirror axi4lite_slave_spec.md §4:
//   §4.1 General rules      -- slave-driven channels (B, R)
//   §4.2 AW/W/B group       -- slave-side obligations
//   §4.3 AR/R group         -- slave-side obligations
//
// This is a whitebox checker for the write-strobe section: `regfile` binds
// directly to the DUT's internal register-file array (wired explicitly in
// formal_tb.sv, e.g. `.regfile(dut.regfile)`), which lets §4.2 check actual
// per-byte write behavior, not just the response code.
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
  input logic [DATA_WIDTH-1:0]   regfile [NUM_REGS]
);

  localparam logic [1:0] OKAY   = 2'b00;
  localparam logic [1:0] EXOKAY = 2'b01;
  localparam logic [1:0] SLVERR = 2'b10;
  localparam logic [1:0] DECERR = 2'b11;

  // IHI0022E §B1.1.2: AXI4-Lite data bus width must be 32 or 64 bits. The
  // ADDR_LSB derivation below (and every word_idx computation in the DUT)
  // is only meaningful for these two values.
  localparam int ADDR_LSB = $clog2(DATA_WIDTH / 8);

  initial
    assert (DATA_WIDTH == 32 || DATA_WIDTH == 64)
      else $fatal(1, "axi4lite_assertions: DATA_WIDTH=%0d is not legal AXI4-Lite (IHI0022E %sB1.1.2)", DATA_WIDTH, "\u00a7");

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  function automatic bit in_range(logic [ADDR_WIDTH-1:0] addr);
    return (addr[ADDR_WIDTH-1:ADDR_LSB] < NUM_REGS);
  endfunction

  // ****************************************************************************
  // ***** 4.1 General rules (slave-driven channels: B, R) *****
  // Master-driven channels (AW, W, AR) are the environment's obligation;
  // see axi4lite_assumptions.sv.
  // ****************************************************************************

  // ===============================================================
  // Rule_01: VALID signals must be LOW during reset.
  // Checked without `disable iff`, since that would mask exactly the
  // cycle under test.
  // ===============================================================
  a_bvalid_low_in_reset: assert property (@(posedge clk) !rst_n |-> !bvalid)
    else $error("BVALID not held low during reset");

  a_rvalid_low_in_reset: assert property (@(posedge clk) !rst_n |-> !rvalid)
    else $error("RVALID not held low during reset");

  // ===============================================================
  // Rule_02: once VALID is asserted, it must remain asserted, and the
  // accompanying payload (address/data/control) must remain stable,
  // until the rising clock edge after READY is seen HIGH.
  // ===============================================================
  a_bvalid_stable: assert property (bvalid && !bready |=> bvalid && $stable(bresp))
    else $error("BVALID/BRESP deasserted or changed before BREADY");

  a_rvalid_stable: assert property (rvalid && !rready |=> rvalid && $stable(rdata) && $stable(rresp))
    else $error("RVALID/RDATA/RRESP deasserted or changed before RREADY");

  a_no_x_bvalid: assert property (!$isunknown(bvalid));
  a_no_x_rvalid: assert property (!$isunknown(rvalid));

  // ===============================================================
  // Rules with no assert of their own -- see the matching note in
  // axi4lite_assumptions.sv (rule 1 is a definition, rule 3 is a
  // permission granted to the receiver -- here, the master's
  // BREADY/RREADY). Covered instead of asserted -- see
  // axi4lite_covers.sv.
  // ===============================================================


  // ****************************************************************************
  // ***** 4.2 AW / W / B group -- slave side *****
  // ****************************************************************************

  logic aw_seen_q, w_seen_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_seen_q <= 1'b0;
      w_seen_q  <= 1'b0;
    end else if (bvalid && bready) begin
      aw_seen_q <= 1'b0;
      w_seen_q  <= 1'b0;
    end else begin
      if (awvalid && awready) aw_seen_q <= 1'b1;
      if (wvalid  && wready)  w_seen_q  <= 1'b1;
    end
  end

  // ===============================================================
  // Rule_03: the slave must wait for AWVALID, AWREADY, WVALID, and
  // WREADY to all have been asserted (AW and W handshakes both
  // complete) before asserting BVALID.
  // ===============================================================
  a_bvalid_requires_aw_and_w: assert property ($rose(bvalid) |-> aw_seen_q && w_seen_q)
    else $error("BVALID asserted before AW and W handshakes both completed");

  // ===============================================================
  // Rule_04: the slave must not wait for BREADY before asserting
  // BVALID. Bounded-liveness proxy: this is not a literal encoding of
  // the master-side "don't wait for ready" rule (not expressible from
  // waveforms alone) -- it's the DUT-side analogue, scoped to this
  // channel's own completion condition. Tighten [0:1] if you know the
  // DUT's exact expected latency.
  // ===============================================================
  a_bvalid_not_wait_bready: assert property ((aw_seen_q && w_seen_q && !bvalid) |-> ##[0:1] bvalid)
    else $error("BVALID delayed past expected latency after AW+W complete -- possible BREADY dependency");

  // ===============================================================
  // Whenever the slave asserts BVALID, BRESP must be a legal AXI4-Lite
  // write response (OKAY or SLVERR -- EXOKAY is never legal on
  // AXI4-Lite per IHI0022E §B1.1.1, and DECERR is interconnect-only).
  // ===============================================================
  a_bresp_legal_value: assert property (bvalid |-> (bresp == OKAY || bresp == SLVERR))
    else $error("BRESP is neither OKAY nor SLVERR while BVALID is asserted");

  // Response-code correctness against the DUT's own address range.
  logic [ADDR_WIDTH-1:0] awaddr_latched_ref;
  always_ff @(posedge clk) begin
    if (awvalid && awready) awaddr_latched_ref <= awaddr;
  end

  a_write_okay_in_range: assert property (
    $rose(bvalid) && in_range(awaddr_latched_ref) |-> bresp == OKAY
  ) else $error("In-range write did not return OKAY");

  a_write_slverr_out_of_range: assert property (
    $rose(bvalid) && !in_range(awaddr_latched_ref) |-> bresp == SLVERR
  ) else $error("Out-of-range write did not return SLVERR");

  // Write-strobe byte-lane correctness (IHI0022E §B1.1.3: this slave
  // chose "full use of the write strobes"). Whitebox check against the
  // connected `regfile` array.
  logic [DATA_WIDTH-1:0]   wdata_latched_ref;
  logic [DATA_WIDTH/8-1:0] wstrb_latched_ref;
  logic [DATA_WIDTH-1:0]   regfile_before_write [NUM_REGS];
  always_ff @(posedge clk) begin
    if (wvalid && wready) begin
      wdata_latched_ref <= wdata;
      wstrb_latched_ref <= wstrb;
    end
    if (awvalid && awready) regfile_before_write <= regfile;
  end

  genvar gb;
  generate
    for (gb = 0; gb < DATA_WIDTH/8; gb++) begin : g_strobe_byte_check
      a_write_enabled_byte_updated: assert property (
        $rose(bvalid) && in_range(awaddr_latched_ref) && wstrb_latched_ref[gb]
        |-> regfile[awaddr_latched_ref[ADDR_WIDTH-1:ADDR_LSB]][gb*8+:8] == wdata_latched_ref[gb*8+:8]
      ) else $error("Byte lane %0d enabled by WSTRB was not written with WDATA", gb);

      a_write_disabled_byte_preserved: assert property (
        $rose(bvalid) && in_range(awaddr_latched_ref) && !wstrb_latched_ref[gb]
        |-> regfile[awaddr_latched_ref[ADDR_WIDTH-1:ADDR_LSB]][gb*8+:8]
              == regfile_before_write[awaddr_latched_ref[ADDR_WIDTH-1:ADDR_LSB]][gb*8+:8]
      ) else $error("Byte lane %0d masked by WSTRB was modified anyway", gb);
    end
  endgenerate

  // Outstanding-transaction restriction (IHI0022E §B1.1.4 explicitly
  // permits this -- pins down this DUT's specific choice, not a
  // compliance violation).
  a_bvalid_clears_next_cycle: assert property (bvalid && bready |=> !bvalid)
    else $error("BVALID did not deassert the cycle after being accepted");

  a_no_x_awready: assert property (!$isunknown(awready));
  a_no_x_wready:  assert property (!$isunknown(wready));
  a_no_x_bresp:   assert property (bvalid |-> !$isunknown(bresp));


  // ****************************************************************************
  // ***** 4.3 AR / R group -- slave side *****
  // ****************************************************************************

  // ===============================================================
  // Rule_05: the slave must wait for both ARVALID and ARREADY to be
  // asserted before asserting RVALID.
  // ===============================================================
  a_rvalid_requires_ar: assert property ($rose(rvalid) |-> $past(arvalid && arready))
    else $error("RVALID asserted without a preceding ARVALID&ARREADY handshake");

  // ===============================================================
  // Rule_06: the slave must not wait for RREADY before asserting
  // RVALID. Unlike the write side's bounded-liveness proxy, this one
  // is a direct, tight implication -- AR completing forces RVALID the
  // very next cycle regardless of RREADY, so it's strictly stronger
  // than a bounded-latency check and needs no separate "not wait for
  // rready" property alongside it.
  // ===============================================================
  a_ar_leads_to_rvalid: assert property ((arvalid && arready) |=> rvalid)
    else $error("ARVALID&ARREADY handshake did not produce RVALID next cycle -- possible RREADY dependency");

  // ===============================================================
  // Rule_07: the slave asserts RVALID only when it drives valid RDATA.
  // "Valid" here reduces to two checkable things: not X/Z, and
  // content-correct (the latter is a_read_okay_in_range /
  // a_read_slverr_out_of_range below, plus stability is already
  // covered by Rule_02's a_rvalid_stable above).
  // ===============================================================
  a_no_x_rdata: assert property (rvalid |-> !$isunknown(rdata))
    else $error("RVALID asserted with X/Z in RDATA");

  a_read_okay_in_range: assert property (
    (arvalid && arready && in_range(araddr)) |=> rresp == OKAY
  ) else $error("In-range read did not return OKAY");

  a_read_slverr_out_of_range: assert property (
    (arvalid && arready && !in_range(araddr)) |=> (rresp == SLVERR && rdata == '0)
  ) else $error("Out-of-range read did not return SLVERR with rdata==0");

  // Legal response-code check, read side (parallel to a_bresp_legal_value).
  a_rresp_legal_value: assert property (rvalid |-> (rresp == OKAY || rresp == SLVERR))
    else $error("RRESP is neither OKAY nor SLVERR while RVALID is asserted");

  // Outstanding-transaction restriction (IHI0022E §B1.1.4 -- permitted,
  // not a violation).
  a_no_new_ar_while_rvalid: assert property (rvalid && !rready |-> !arready)
    else $error("ARREADY asserted while a prior RVALID is still outstanding");

  a_no_x_arready: assert property (!$isunknown(arready));
  a_no_x_rresp:   assert property (rvalid |-> !$isunknown(rresp));

endmodule
