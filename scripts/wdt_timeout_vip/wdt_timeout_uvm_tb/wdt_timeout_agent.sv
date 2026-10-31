class wdt_timeout_agent extends uvm_agent;
wdt_timeout_driver drv; wdt_timeout_monitor mon; wdt_timeout_sequencer seqr;
`uvm_component_utils(wdt_timeout_agent)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); drv=wdt_timeout_driver::type_id::create("drv",this); mon=wdt_timeout_monitor::type_id::create("mon",this); seqr=wdt_timeout_sequencer::type_id::create("seqr",this); endfunction
function void connect_phase(uvm_phase phase); drv.seq_item_port.connect(seqr.seq_item_export); endfunction
endclass
