class ecc_status_monitor extends uvm_monitor;
virtual ecc_status_if vif;
uvm_analysis_port #(ecc_status_item) ap;
`uvm_component_utils(ecc_status_monitor)
function new(string n,uvm_component p); super.new(n,p); ap=new("ap",this); endfunction
endclass
