class uart_monitor extends uvm_monitor;
virtual uart_if vif;
uvm_analysis_port #(uart_item) ap;
`uvm_component_utils(uart_monitor)
function new(string n,uvm_component p); super.new(n,p); ap=new("ap",this); endfunction
endclass
