// ============================================================================
// formal_tb_bmc.sv
//
// Top-level formal environment for REAL, exhaustive SymbiYosys/yosys-native
// BMC -- the "flow #1: true formal tool" case that formal_tb.sv's header
// comment describes but formal_tb.sv itself doesn't implement (it always
// carries its own clock generator, reset initial block, and constrained-
// random driver for flow #2, bounded simulation).
//
// Unlike formal_tb.sv:
//   - clk/rst_n and every master-driven signal are plain top-level ports,
//     left as free variables for the solver -- no clock generator, no
//     reset `initial` block, no axi4lite_formal_driver instance. Legality
//     is entirely the job of axi4lite_assumptions.sv's `assume property`
//     statements (plus the `$initstate`-gated reset assumption in there).
//   - Otherwise wires up the same DUT + axi4lite_assumptions +
//     axi4lite_assertions (whitebox regfile included) + axi4lite_covers
//     as formal_tb.sv.
//
// Driven by bmc.sby.
// ============================================================================
module formal_tb_bmc (
  input logic clk,
  input logic rst_n,

  input logic [7:0]  awaddr,
  input logic        awvalid,
  input logic [31:0] wdata,
  input logic [3:0]  wstrb,
  input logic        wvalid,
  input logic        bready,
  input logic [7:0]  araddr,
  input logic        arvalid,
  input logic        rready
);

  localparam int ADDR_WIDTH = 8;
  localparam int DATA_WIDTH = 32;
  localparam int NUM_REGS   = 16;

  logic        awready;
  logic        wready;
  logic [1:0]  bresp;
  logic        bvalid;
  logic        arready;
  logic [31:0] rdata;
  logic [1:0]  rresp;
  logic        rvalid;
  logic [NUM_REGS-1:0][DATA_WIDTH-1:0] regfile_dbg;

  axi4lite_slave #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .NUM_REGS   (NUM_REGS)
  ) dut (.*);

  axi4lite_assumptions #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH)
  ) u_assumptions (.*);

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
    .regfile (regfile_dbg)
  );

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
