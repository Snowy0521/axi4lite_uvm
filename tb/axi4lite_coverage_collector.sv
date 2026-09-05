// ============================================================================
// axi4lite_coverage_collector.sv
//
// Coverage collector for AXI4-Lite interface transactions. 
// Collects coverage on the address, data, and response fields of both read and write transactions. 
// ============================================================================


class axi4lite_coverage_collector extends uvm_subscriber #(axi4lite_txn);
    `uvm_component_utils(axi4lite_coverage_collector)

    axi4lite_txn tr;

`ifndef VERILATOR
    covergroup cg_axi4lite; 
        option.per_instance = 1; // Each instance of the coverage collector will have its own coverage group

        cp_op: coverpoint tr.op {
            bins write = {AXI_WRITE};
            bins read = {AXI_READ};
        }

        cp_addr: coverpoint tr.addr {
            bins in_range = {[0 : (axi4lite_pkg::NUM_REGS-1)*4]}; // valid address range for the DUT
            bins out_of_range = default; // any address outside the valid range
        }

        cp_wdata: coverpoint tr.wdata {
            bins low = {['0 : (2**(axi4lite_pkg::DATA_WIDTH-2)) - 1]};
            bins mid = {[(2**(axi4lite_pkg::DATA_WIDTH-2)) : (2**(axi4lite_pkg::DATA_WIDTH-1)) - 1]};
            bins high = {[(2**(axi4lite_pkg::DATA_WIDTH-1)) : (2**axi4lite_pkg::DATA_WIDTH) - 1]};
        }

        cp_wstrb: coverpoint tr.wstrb {
            bins all_zero = {4'b0000};
            bins all_one = {4'b1111};
            bins byte0 = {4'b0001};
            bins byte1 = {4'b0010};
            bins byte2 = {4'b0100};
            bins byte3 = {4'b1000};
            bins others = default;
        }

        cp_resp: coverpoint tr.resp {
            bins ok = {2'b00};
            bins slverr = {2'b10};
        }

        // cross coverage between all coverpoints 
        cx_all: cross cp_op, cp_addr, cp_wdata, cp_wstrb, cp_resp;
    endgroup
`endif

    function new(string name, uvm_component parent);
        super.new(name, parent);
        `ifndef VERILATOR cg_axi4lite = new(); `endif
    endfunction

    function void write(axi4lite_txn tr);
        this.tr = tr;
        `ifndef VERILATOR cg_axi4lite.sample(); `endif
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("COVERAGE",
            $sformatf("Coverage for %s: %0.2f%%", get_full_name(), cg_axi4lite.get_coverage()),
            UVM_LOW)
    endfunction
endclass




