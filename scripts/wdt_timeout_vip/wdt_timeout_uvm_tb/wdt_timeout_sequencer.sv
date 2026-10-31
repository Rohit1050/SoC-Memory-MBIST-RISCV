class wdt_timeout_sequencer extends uvm_sequencer #(wdt_timeout_item);
`uvm_component_utils(wdt_timeout_sequencer)
function new(string n,uvm_component p);super.new(n,p);endfunction
endclass
