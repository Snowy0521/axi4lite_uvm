// ============================================================================
// axi4lite_covers.sv
//
// All `cover property` points for axi4lite_slave's formal environment.
//
// yosys-native rewrite (formal-bmc-native branch): see the header comment
// in axi4lite_assumptions.sv for why every property here is hand-lowered
// to a plain boolean checked once per clock -- no `##`, `|->`, `throughout`
// or `[->1]`. A BMC `cover` only needs ONE cycle, somewhere in the unrolled
// trace, where its boolean is true, so every "eventually X happens" shape
// below becomes a small sticky flag that turns on when the precondition is
// seen and turns back off once X actually happens -- the cover then just
// asks "is the flag set AND X true this cycle", which is exactly the cycle
// the original `##1 ... [->1]` sequence would have completed on.
// ============================================================================
module axi4lite_covers #(
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

  // Every real SV tool -- Verilator included -- requires a clocking event on
  // every concurrent assertion (IEEE 1800 16.16); yosys-native can't
  // parse `default clocking` at all (confirmed by minimal repro), and
  // -- unlike Verilator -- doesn't seem to need one for a module-level
  // `cover property` with no temporal operator, so this is
  // only used by Verilator.
`ifndef YOSYS_NATIVE_BMC
  default clocking cb @(posedge clk); endclocking
`endif

  localparam logic [1:0] OKAY   = 2'b00;
  localparam logic [1:0] SLVERR = 2'b10;

  // One-cycle delay registers, standing in for $rose() everywhere below.
  logic awvalid_q, awready_q, wvalid_q, wready_q, bvalid_q, bready_q;
  logic arvalid_q, arready_q, rvalid_q, rready_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      awvalid_q <= 1'b0; wvalid_q <= 1'b0; bvalid_q <= 1'b0;
      arvalid_q <= 1'b0; rvalid_q <= 1'b0;
    end else begin
      awvalid_q <= awvalid; wvalid_q <= wvalid; bvalid_q <= bvalid;
      arvalid_q <= arvalid; rvalid_q <= rvalid;
    end
  end
  // Separate plain-clocked block: mixing signals with a constant async
  // reset value and signals without one (these) in the same
  // `@(posedge clk or negedge rst_n)` block makes yosys's async-reset FF
  // inference reject the whole block ("yields non-constant value").
  always_ff @(posedge clk) begin
    awready_q <= awready; wready_q <= wready; bready_q <= bready;
    arready_q <= arready; rready_q <= rready;
  end

  // ****************************************************************************
  // **************************** 4.1 General rules *****************************
  // ****************************************************************************

  // 3. Transfer occurs only on a clock edge where VALID and READY
  // are both HIGH on that channel.
  cp_aw_handshake_occurs:   cover property (awvalid && awready);
  cp_w_handshake_occurs:    cover property (wvalid && wready);
  cp_b_handshake_occurs:    cover property (bvalid && bready);
  cp_ar_handshake_occurs:   cover property (arvalid && arready);
  cp_r_handshake_occurs:    cover property (rvalid && rready);

  // 5. The receiver may assert READY either before or after VALID.
  cp_aw_ready_preasserted: cover property (awvalid && !awvalid_q && awready);
  // "Ready came after a wait": last cycle VALID was up and READY wasn't,
  // and the handshake completes now. (The master-side stability
  // assumption already forces VALID to have stayed up throughout any
  // longer wait, so witnessing one wait cycle demonstrates the general
  // shape -- a BMC cover doesn't need to separately witness every wait
  // length.)
  cp_aw_ready_after_valid: cover property (awvalid && awready && awvalid_q && !awready_q);

  cp_w_ready_preasserted: cover property (wvalid && !wvalid_q && wready);
  cp_w_ready_after_valid: cover property (wvalid && wready && wvalid_q && !wready_q);

  cp_b_ready_preasserted: cover property (bvalid && !bvalid_q && bready);
  cp_b_ready_after_valid: cover property (bvalid && bready && bvalid_q && !bready_q);

  cp_ar_ready_preasserted: cover property (arvalid && !arvalid_q && arready);
  cp_ar_ready_after_valid: cover property (arvalid && arready && arvalid_q && !arready_q);

  cp_r_ready_preasserted: cover property (rvalid && !rvalid_q && rready);
  cp_r_ready_after_valid: cover property (rvalid && rready && rvalid_q && !rready_q);


  // ****************************************************************************
  // *********** 4.2 Specific rules for AW / W / B ******************************
  // ****************************************************************************

  cp_write_okay:   cover property (bvalid && !bvalid_q && bresp == OKAY);
  cp_write_slverr: cover property (bvalid && !bvalid_q && bresp == SLVERR);

  // AWVALID/WVALID may arrive in either order or simultaneously.
  // Sticky "the other half is still owed" flags replace the
  // `##1 (...)[->1]` sequences: set when one handshake completes alone,
  // cleared once the other one follows.
  logic w_owed_after_aw_only, aw_owed_after_w_only;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      w_owed_after_aw_only  <= 1'b0;
      aw_owed_after_w_only  <= 1'b0;
    end else begin
      if (wvalid && wready) w_owed_after_aw_only <= 1'b0;
      else if (awvalid && awready && !(wvalid && wready)) w_owed_after_aw_only <= 1'b1;

      if (awvalid && awready) aw_owed_after_w_only <= 1'b0;
      else if (wvalid && wready && !(awvalid && awready)) aw_owed_after_w_only <= 1'b1;
    end
  end

  cp_aw_before_w: cover property (w_owed_after_aw_only && wvalid && wready);
  cp_w_before_aw: cover property (aw_owed_after_w_only && awvalid && awready);
  cp_aw_w_same_cycle: cover property (awvalid && awready && wvalid && wready);

  // Write-strobe pattern coverage
  logic [DATA_WIDTH/8-1:0] wstrb_latched_ref;
  always_ff @(posedge clk) begin
    if (wvalid && wready) wstrb_latched_ref <= wstrb;
  end

  cp_wstrb_all_zero: cover property (bvalid && !bvalid_q && wstrb_latched_ref == '0);
  cp_wstrb_partial:  cover property (
    bvalid && !bvalid_q && wstrb_latched_ref != '0 && wstrb_latched_ref != '1
  );
  cp_wstrb_full: cover property (bvalid && !bvalid_q && wstrb_latched_ref == '1);

  // Master-side ordering (no READY involved): AWVALID/WVALID raised alone,
  // then the other one eventually follows -- same sticky-flag technique.
  logic wvalid_owed_after_aw_only, awvalid_owed_after_w_only;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wvalid_owed_after_aw_only  <= 1'b0;
      awvalid_owed_after_w_only  <= 1'b0;
    end else begin
      if (wvalid) wvalid_owed_after_aw_only <= 1'b0;
      else if (awvalid && !wvalid) wvalid_owed_after_aw_only <= 1'b1;

      if (awvalid) awvalid_owed_after_w_only <= 1'b0;
      else if (wvalid && !awvalid) awvalid_owed_after_w_only <= 1'b1;
    end
  end

  cp_aw_before_w_master: cover property (wvalid_owed_after_aw_only && wvalid);
  cp_w_before_aw_master: cover property (awvalid_owed_after_w_only && awvalid);


  // ****************************************************************************
  // ***** 4.3 Specific rules for AR / R ****************************************
  // ****************************************************************************

  cp_read_okay:   cover property (rvalid && !rvalid_q && rresp == OKAY);
  cp_read_slverr: cover property (rvalid && !rvalid_q && rresp == SLVERR);

endmodule
