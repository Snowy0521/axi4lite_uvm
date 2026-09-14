// ============================================================================
// axi4lite_assumptions.sv
//
// All `assume property` constraints on the master side of axi4lite_slave's
// formal environment.
//
// yosys-native rewrite (formal-bmc-native branch): yosys's built-in Verilog
// frontend (no Verific license available) cannot parse `##`, `|->`, `|=>`,
// `default clocking` or `default disable iff` at all -- confirmed by direct
// minimal repro. Every property below is therefore hand-lowered to a plain
// boolean expression evaluated once per clock (no concurrent-SVA temporal
// operators), with one-cycle delay registers standing in for `|=>`/$stable,
// and `disable iff (!rst_n)` folded in explicitly as `!rst_n || (...)`
// instead of relying on a module-level default. See axi4lite_assertions.sv
// for the same treatment (and NBA/reset reasoning) on the slave side.
// ============================================================================
module axi4lite_assumptions #(
  parameter int ADDR_WIDTH = 8,
  parameter int DATA_WIDTH = 32
)(
  input logic clk, rst_n,

  input logic [ADDR_WIDTH-1:0] awaddr,
  input logic                  awvalid,
  input logic                  awready,

  input logic [DATA_WIDTH-1:0]   wdata,
  input logic [DATA_WIDTH/8-1:0] wstrb,
  input logic                    wvalid,
  input logic                    wready,

  input logic bready,

  input logic [ADDR_WIDTH-1:0] araddr,
  input logic                  arvalid,
  input logic                  arready,

  input logic rready
);

  // Every real SV tool -- Verilator included -- requires a clocking event on
  // every concurrent assertion (IEEE 1800 16.16); yosys-native can't
  // parse `default clocking` at all (confirmed by minimal repro), and
  // -- unlike Verilator -- doesn't seem to need one for a module-level
  // `assert property`/`assume property`/`cover property` with no
  // temporal operator, so this only applies to Verilator.
`ifndef YOSYS_NATIVE_BMC
  default clocking cb @(posedge clk); endclocking
`endif

  // Seed BMC in reset: plain sync-reset flops below have no meaningful
  // value before the first clock edge, so without this the solver is free
  // to pick an arbitrary (never-reset) initial state and "fail" a property
  // at step 0 for reasons that have nothing to do with the DUT. $initstate
  // is true only at the very first BMC step.
  //
  // Excluded from the Verilator build (`` `ifndef YOSYS_NATIVE_BMC ``):
  // $initstate is a formal-only construct Verilator doesn't implement,
  // and formal_tb.sv's own `initial rst_n = 0; repeat(3) @(posedge clk);
  // rst_n = 1;` block already does the equivalent job for that flow.
`ifdef YOSYS_NATIVE_BMC
  m_reset_at_start: assume property (!$initstate || !rst_n);
`endif

  // One-cycle-delayed copies of every master-driven signal, standing in for
  // the `|=>`/$stable() pair used in the original *_stable properties.
  logic                    awvalid_q, awready_q;
  logic                    wvalid_q,  wready_q;
  logic                    arvalid_q, arready_q;
  logic [ADDR_WIDTH-1:0]   awaddr_q, araddr_q;
  logic [DATA_WIDTH-1:0]   wdata_q;
  logic [DATA_WIDTH/8-1:0] wstrb_q;
  always_ff @(posedge clk) begin
    awvalid_q <= awvalid; awready_q <= awready; awaddr_q <= awaddr;
    wvalid_q  <= wvalid;  wready_q  <= wready;  wdata_q  <= wdata; wstrb_q <= wstrb;
    arvalid_q <= arvalid; arready_q <= arready; araddr_q <= araddr;
  end

  // Environment constraints to prevent X propagation from the master side.
  m_no_x_awvalid: assume property (!rst_n || !$isunknown(awvalid));
  m_no_x_awaddr:  assume property (!rst_n || !awvalid || !$isunknown(awaddr));
  m_no_x_wvalid:  assume property (!rst_n || !$isunknown(wvalid));
  m_no_x_wdata:   assume property (!rst_n || !wvalid || !$isunknown(wdata));
  m_no_x_wstrb:   assume property (!rst_n || !wvalid || !$isunknown(wstrb));
  m_no_x_bready:  assume property (!rst_n || !$isunknown(bready));
  m_no_x_arvalid: assume property (!rst_n || !$isunknown(arvalid));
  m_no_x_araddr:  assume property (!rst_n || !arvalid || !$isunknown(araddr));
  m_no_x_rready:  assume property (!rst_n || !$isunknown(rready));

  // VALID must be held low during reset. `disable iff (1'b0)` in the
  // original meant "never disabled, check even during reset" -- an
  // explicit override of the module default -- so unlike the checks
  // above, these get NO `!rst_n ||` guard.
  m_awvalid_low_in_reset: assume property (rst_n || !awvalid);
  m_wvalid_low_in_reset:  assume property (rst_n || !wvalid);
  m_arvalid_low_in_reset: assume property (rst_n || !arvalid);

  // Once VALID is asserted and not yet accepted, it (and its payload) must
  // remain stable until accepted. `awvalid_q && !awready_q` is "the
  // antecedent was true last cycle"; the consequent is checked now.
  m_awvalid_stable: assume property (
    !rst_n || !(awvalid_q && !awready_q) || (awvalid && awaddr == awaddr_q)
  );
  m_wvalid_stable: assume property (
    !rst_n || !(wvalid_q && !wready_q) || (wvalid && wdata == wdata_q && wstrb == wstrb_q)
  );
  m_arvalid_stable: assume property (
    !rst_n || !(arvalid_q && !arready_q) || (arvalid && araddr == araddr_q)
  );

endmodule
