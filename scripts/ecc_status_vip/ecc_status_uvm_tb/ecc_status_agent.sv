class ecc_status_agent extends uvm_agent;
ecc_status_driver drv; ecc_status_monitor mon; ecc_status_sequencer seqr;
`uvm_component_utils(ecc_status_agent)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); drv=ecc_status_driver::type_id::create("drv",this); mon=ecc_status_monitor::type_id::create("mon",this); seqr=ecc_status_sequencer::type_id::create("seqr",this); endfunction
function void connect_phase(uvm_phase phase); drv.seq_item_port.connect(seqr.seq_item_export); endfunction
endclass
