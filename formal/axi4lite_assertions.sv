// ============================================================================
// axi4lite_assertions.sv
//
// All assert property checks for axi4lite_slave
// ============================================================================

module axi4lite_assertions #(
  parameter int ADDR_WIDTH = 8,
  parameter int DATA_WIDTH = 32,
  //parameter int DATA_WIDTH = 64,
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
  
  localparam int ADDR_LSB = $clog2(DATA_WIDTH / 8);

  default clocking cb @(posedge clk); endclocking 
  default disable iff (!rst_n);

  function automatic bit in_range(logic [ADDR_WIDTH-1:0] addr);
	  return (addr[ADDR_WIDTH-1:ADDR_LSB] < NUM_REGS);
  endfunction

  // ===============================================================
  // Rule_01: VALID signals must be LOW during reset.
  //
  // Slave-driven channels (B, R) only
  // Master-driven channels (AW, W, AR) in axi4lite_assumptions.sv
  // ===============================================================

  a_bvalid_low_in_reset: assert property (@(posedge clk) !rst_n |-> !bvalid)
  	else $error("BVALID not held low during reset");

  a_rvalid_low_in_reset: assert property (@(posedge clk) !rst_n |-> !rvalid)
  	else $error("RVALID not held low during reset")

  // ===============================================================
  // Rule_02: Once VALID is asserted, it must remain asserted, 
  // and the accompanying payload (address/data/control) must remain stable, 
  // until the rising clock edge after READY is seen HIGH. (next cycle)
  //
  // Slave-driven channels (B, R) only
  // Master-driven channels (AW, W, AR) in axi4lite_assumptions.sv
  // ===============================================================

  a_bvalid_stable: assert property (bvalid && !bready |=> bvalid && $stable(bresp))
  	else $error("BVALID/BRESP deasserted or changed before BREADY");

  a_rvalid_stable: assert property (rvalid && !rready |=> rvalid && $stable(rdata) && $stable(rresp))
  	else $error("RVALID/RDATA/RRESP deasserted or changed before BREADY");

  // ===============================================================
  // Rule_03: AW and W handshakes must be completed before asserting BVALID 
  // ===============================================================
  property p_bvalid_after_aw_and_w;
	  $rose(bvalid) |-> 
		  // AW handshake happened in cycle N-1 or earlier
		  $past((awvalid && awready) [->1], 1) && 
	          // W handshake happened in cycle N-1 or earlier
		  $past((awvalid && awready) [->1], 1);
  endproperty

  a_bvalid_before_aw_and_w: assert property (p_bvalid_after_aw_and_w)
  	else $error ("BVALID asserted before or at same cycle AW and W handshakes completed");












