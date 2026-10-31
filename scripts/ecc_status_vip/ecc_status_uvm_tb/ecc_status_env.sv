class ecc_status_env extends uvm_env;
ecc_status_agent agent; ecc_status_scoreboard sb;
`uvm_component_utils(ecc_status_env)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); agent=ecc_status_agent::type_id::create("agent",this); sb=ecc_status_scoreboard::type_id::create("sb",this); endfunction
endclass
