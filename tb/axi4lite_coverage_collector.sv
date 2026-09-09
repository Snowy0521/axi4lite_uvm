// ============================================================================
// axi4lite_coverage_collector.sv
//
// Coverage collector for AXI4-Lite interface transactions. 
// Collects coverage on the address, data, and response fields of both read and write transactions. 
// ============================================================================


class axi4lite_coverage_collector extends uvm_subscriber #(axi4lite_txn);
    `uvm_component_utils(axi4lite_coverage_collector)


    covergroup cg_axi4lite with function sample(
	   axi4lite_op_e				op,
	   logic [axi4lite_pkg::ADDR_WIDTH-1:0] 	addr,
	   logic [axi4lite_pkg::DATA_WIDTH-1:0]		wdata,
	   logic [axi4lite_pkg::STRB_WIDTH-1:0]		wstrb,
	   logic [1:0]					resp); 

        option.per_instance = 1; // Each instance of the coverage collector will have its own coverage group

        cp_op: coverpoint op {
            bins write = {AXI_WRITE};
            bins read = {AXI_READ};
        }

        cp_addr: coverpoint addr {
            bins in_range = {[0 : (axi4lite_pkg::NUM_REGS-1)*axi4lite_pkg::STRB_WIDTH]}; // valid address range for the DUT
            bins out_of_range = default; // any address outside the valid range
        }

        cp_wdata: coverpoint wdata iff (op == AXI_WRITE) {
            bins low = {['0 : (2**(axi4lite_pkg::DATA_WIDTH-2)) - 1]};
            bins mid = {[(2**(axi4lite_pkg::DATA_WIDTH-2)) : (2**(axi4lite_pkg::DATA_WIDTH-1)) - 1]};
            bins high = {[(2**(axi4lite_pkg::DATA_WIDTH-1)) : (2**axi4lite_pkg::DATA_WIDTH) - 1]};
        }

        cp_wstrb: coverpoint wstrb iff (op == AXI_WRITE) {
            bins all_zero = {'0};
            bins all_one =  {'1};
            bins others = default;
        }

        cp_resp: coverpoint resp {
            bins ok = {2'b00};
            bins slverr = {2'b10};
        }

        // cross coverage between coverpoints 
        cx_op_addr: 	cross cp_op, cp_addr;

	// not supported by verilator 
        //cx_addr_resp:   cross cp_addr, cp_resp {
	//	illegal_bins invalid_out_of_range_ok = binsof(cp_addr.out_of_range) && binsof(cp_resp.ok);
	//	illegal_bins invalid_in_range_err = binsof(cp_addr.in_range) && binsof(cp_resp.slverr);
	//}
	
        // alternative
        cp_addr_resp_comb: coverpoint {(addr > (axi4lite_pkg::NUM_REGS-1)*axi4lite_pkg::STRB_WIDTH), resp} {
    	   bins in_range_ok       = {3'b0_00}; 
     	   bins out_of_range_err  = {3'b1_10}; 
    	}
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_axi4lite = new(); 
    endfunction

    function void write(axi4lite_txn tr);
        cg_axi4lite.sample(tr.op, tr.addr, tr.wdata, tr.wstrb, tr.resp); 
    endfunction

    function void report_phase(uvm_phase phase);
    	super.report_phase(phase);
    	`uvm_info("COVERAGE",
        	$sformatf("Overall coverage for %s: %0.2f%%", get_full_name(), cg_axi4lite.get_inst_coverage()),
        	UVM_LOW)
    endfunction    
endclass




