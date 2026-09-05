// ============================================================================
// axi4lite_if.sv
//
// Bundles all AXI4-Lite signals into one interface, with clocking blocks for
// the driver (drives inputs from the master side, samples slave responses)
// and the monitor (purely samples everything, drives nothing).
//
// Using clocking blocks here avoids the classic testbench-vs-RTL sampling
// race: driver outputs are skewed after the clock edge, and driver
// inputs are sampled slightly before it.
// ============================================================================

interface axi4lite_if #(
  parameter int ADDR_WIDTH = 8,
  parameter int DATA_WIDTH = 32
)(
  input logic clk,
  input logic rst_n
);

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

  // ---------------------------------------------------------------------
  // Driver clocking block: drives master-side signals, samples slave
  // responses. Output skew keeps driven values from racing the DUT's own
  // posedge-triggered sampling.
  // ---------------------------------------------------------------------
  clocking drv_cb @(posedge clk);
    default input #1step output #2;
    output awaddr, awvalid, wdata, wstrb, wvalid, bready, araddr, arvalid, rready;
    input  rst_n;
    input  awready, wready, bresp, bvalid, arready, rdata, rresp, rvalid;
  endclocking

  // ---------------------------------------------------------------------
  // Monitor clocking block: read-only view of every signal.
  // ---------------------------------------------------------------------
  clocking mon_cb @(posedge clk);
    default input #1step;
    input rst_n;
    input awaddr, awvalid, awready;
    input wdata, wstrb, wvalid, wready;
    input bresp, bvalid, bready;
    input araddr, arvalid, arready;
    input rdata, rresp, rvalid, rready;
  endclocking

  modport driver  (clocking drv_cb);
  modport monitor (clocking mon_cb);

endinterface
