class ecc_status_driver extends uvm_driver #(ecc_status_item);
virtual ecc_status_if vif;
`uvm_component_utils(ecc_status_driver)
function new(string n,uvm_component p);super.new(n,p);endfunction
task run_phase(uvm_phase phase); forever begin seq_item_port.get_next_item(req); @(posedge vif.clk); seq_item_port.item_done(); end endtask
endclass
