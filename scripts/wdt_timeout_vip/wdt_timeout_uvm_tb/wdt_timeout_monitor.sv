class wdt_timeout_monitor extends uvm_monitor;
virtual wdt_timeout_if vif;
uvm_analysis_port #(wdt_timeout_item) ap;
`uvm_component_utils(wdt_timeout_monitor)
function new(string n,uvm_component p); super.new(n,p); ap=new("ap",this); endfunction
endclass
