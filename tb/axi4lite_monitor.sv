// ============================================================================
// axi4lite_monitor.sv
//
// Passively observes the bus and reconstructs completed write/read
// transactions, broadcasting each one on an analysis port for the
// scoreboard and coverage collector to consume.
//
// Write and read channels are monitored concurrently since AXI4-Lite allows
// independent, overlapping read/write traffic.
// ============================================================================

class axi4lite_monitor extends uvm_monitor;
  `uvm_component_utils(axi4lite_monitor)
  
  virtual axi4lite_if #(
    .ADDR_WIDTH(axi4lite_pkg::ADDR_WIDTH),
    .DATA_WIDTH(axi4lite_pkg::DATA_WIDTH)
  ).monitor vif;

  uvm_analysis_port #(axi4lite_txn) ap;  

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this); // TLM port, can not be registered in config_db, just new it
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axi4lite_if#(
   	 .ADDR_WIDTH(axi4lite_pkg::ADDR_WIDTH),
    	 .DATA_WIDTH(axi4lite_pkg::DATA_WIDTH)
       ).monitor)::get(this, "", "vif", vif))
       	`uvm_fatal("NOVIF", "virtual interface (monitor modport) not found in config_db")
  endfunction

  task run_phase(uvm_phase phase);
    fork
      monitor_write();
      monitor_read();
    join
  endtask

  // ------------------------------------------------------------------
  // Reconstruct a write transaction: wait for AW and W handshakes
  // (independently, since they can complete in either order), then wait
  // for the B response, then publish the completed transaction.
  // monitor is passive, so we don't need to put any timeouts watchdogs here.
  // ------------------------------------------------------------------
  task monitor_write();
    forever begin
      axi4lite_txn tr = axi4lite_txn::type_id::create("tr");
      tr.op = AXI_WRITE;

      fork
        begin : do_aw 
          do @(posedge vif.clk); while (!(vif.awvalid && vif.awready));
          tr.addr = vif.awaddr;
        end
        begin : do_w
          do @(posedge vif.clk); while (!(vif.wvalid && vif.wready));
          tr.wdata = vif.wdata;
          tr.wstrb = vif.wstrb;
        end
      join

      do @(posedge vif.clk); while (!(vif.bvalid && vif.bready));
      tr.resp = vif.bresp;

      `uvm_info("MON", $sformatf("observed %s", tr.convert2string()), UVM_LOW)
      ap.write(tr);
    end
  endtask

  // ------------------------------------------------------------------
  // Reconstruct a read transaction: wait for the AR handshake, then wait
  // for RVALID, then publish.
  // ------------------------------------------------------------------
  task monitor_read();
    forever begin
      axi4lite_txn tr = axi4lite_txn::type_id::create("tr");
      tr.op = AXI_READ;

      do @(posedge vif.clk); while (!(vif.arvalid && vif.arready));
      tr.addr = vif.araddr;

      do @(posedge vif.clk); while (!(vif.rvalid && vif.rready));
      tr.rdata = vif.rdata;
      tr.resp  = vif.rresp;

      `uvm_info("MON", $sformatf("observed %s", tr.convert2string()), UVM_LOW)
      ap.write(tr);
    end
  endtask

endclass
