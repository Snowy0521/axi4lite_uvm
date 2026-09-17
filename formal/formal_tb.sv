// ============================================================================
// formal_tb.sv
//
// Top-level formal environment for axi4lite_slave. Instantiates the DUT
// once, and wires it to axi4lite_assumptions.sv (constrains the environment
// to legal AXI4-Lite master behavior), axi4lite_assertions.sv (checks the
// DUT's own obligations, including the whitebox write-strobe checks against
// the DUT's internal `regfile`), and axi4lite_covers.sv (reachability
// coverage for the two spec rules that have no assert/assume of their own).
//
// Written to work two ways:
//   1. True formal tool (JasperGold, VC Formal, Questa Formal, ...): the
//      tool drives clk/reset itself via its own `clock`/`reset` commands
//      and treats every input as a free variable constrained. In that
//      flow, comment out the `always #5 clk = ~clk;` generator and the
//      `initial` reset block below -- the tool supplies both.
//   2. Bounded/simulation-based assertion checking (e.g. Verilator with
//      SVA support, or any simulator run as a smoke check before a real
//      formal tool is available): leave the generator and reset block
//      active, and this becomes a self-contained, randomly-driven
//      testbench that still exercises every assume/assert pair.
// ============================================================================

`timescale 1ns/1ps

module formal_tb;

  localparam int ADDR_WIDTH = 8;
  localparam int DATA_WIDTH = 32;   // change to 64 to formally verify the 64-bit configuration
  localparam int NUM_REGS   = 16;

  // ------------------------------------------------------------------
  // DUT signals
  // ------------------------------------------------------------------
  logic                    clk;
  logic                    rst_n;

  logic [ADDR_WIDTH-1:0]   awaddr;
  logic                    awvalid;
  logic                    awready;

  logic [DATA_WIDTH-1:0]   wdata;
  logic [DATA_WIDTH/8-1:0] wstrb;
  logic                    wvalid;
  logic                    wready;

  logic [1:0]              bresp;
  logic                    bvalid;
  logic                    bready;

  logic [ADDR_WIDTH-1:0]   araddr;
  logic                    arvalid;
  logic                    arready;

  logic [DATA_WIDTH-1:0]   rdata;
  logic [1:0]              rresp;
  logic                    rvalid;
  logic                    rready;

  // ------------------------------------------------------------------
  // Clock / reset -- see the header comment: comment this block out
  // when handing the design to a true formal tool, which drives these
  // itself.
  // ------------------------------------------------------------------
  initial clk = 0;
  always #5 clk = ~clk;   // 10ns period -> 100MHz

  initial begin
    rst_n = 0;
    repeat (3) @(posedge clk);
    rst_n = 1;
  end

  // ------------------------------------------------------------------
  // Simulation-only run length. A true formal tool never reaches an
  // `initial` block like this one during property solving; it only
  // matters for flow #2.
  // ------------------------------------------------------------------
  initial begin
    #100000;   // ~10,000 clock cycles at the 10ns period above
    $display("[formal_tb] Reached simulation time limit, stopping.");
    $finish;
  end

  // ------------------------------------------------------------------
  // DUT instantiation
  // ------------------------------------------------------------------
  axi4lite_slave #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .NUM_REGS   (NUM_REGS)
  ) dut (.*);

  // ------------------------------------------------------------------
  // Legal-master stimulus (flow #2 only) -- see
  // axi4lite_formal_driver.sv's header for why this is needed at all.
  // ------------------------------------------------------------------
  axi4lite_formal_driver #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .NUM_REGS   (NUM_REGS)
  ) u_driver (.*);

  // ------------------------------------------------------------------
  // Environment constraints 
  // ------------------------------------------------------------------
  axi4lite_assumptions #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH)
  ) u_assumptions (
    .clk     (clk),
    .rst_n   (rst_n),
    .awaddr  (awaddr),
    .awvalid (awvalid),
    .awready (awready),
    .wdata   (wdata),
    .wstrb   (wstrb),
    .wvalid  (wvalid),
    .wready  (wready),
    .bready  (bready),
    .araddr  (araddr),
    .arvalid (arvalid),
    .arready (arready),
    .rready  (rready)
  );

  // ------------------------------------------------------------------
  // DUT obligations (whitebox: regfile wired directly to dut.regfile)
  // ------------------------------------------------------------------
  axi4lite_assertions #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .NUM_REGS   (NUM_REGS)
  ) u_assertions (
    .clk     (clk),
    .rst_n   (rst_n),
    .awaddr  (awaddr),
    .awvalid (awvalid),
    .awready (awready),
    .wdata   (wdata),
    .wstrb   (wstrb),
    .wvalid  (wvalid),
    .wready  (wready),
    .bresp   (bresp),
    .bvalid  (bvalid),
    .bready  (bready),
    .araddr  (araddr),
    .arvalid (arvalid),
    .arready (arready),
    .rdata   (rdata),
    .rresp   (rresp),
    .rvalid  (rvalid),
    .rready  (rready),
    .regfile (dut.regfile)
  );

  // ------------------------------------------------------------------
  // Reachability coverage for spec rules, which have no
  // assert/assume of their own, confirming the proof actually reaches these
  // scenarios rather than vacuously passing.
  // ------------------------------------------------------------------
  axi4lite_covers #(
    .DATA_WIDTH (DATA_WIDTH)
  ) u_covers (
    .clk     (clk),
    .rst_n   (rst_n),
    .awvalid (awvalid),
    .awready (awready),
    .wstrb   (wstrb),
    .wvalid  (wvalid),
    .wready  (wready),
    .bresp   (bresp),
    .bvalid  (bvalid),
    .bready  (bready),
    .arvalid (arvalid),
    .arready (arready),
    .rresp   (rresp),
    .rvalid  (rvalid),
    .rready  (rready)
  );

endmodule
