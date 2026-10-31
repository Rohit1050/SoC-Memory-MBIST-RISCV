class wdt_timeout_env extends uvm_env;
wdt_timeout_agent agent; wdt_timeout_scoreboard sb;
`uvm_component_utils(wdt_timeout_env)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); agent=wdt_timeout_agent::type_id::create("agent",this); sb=wdt_timeout_scoreboard::type_id::create("sb",this); endfunction
endclass
