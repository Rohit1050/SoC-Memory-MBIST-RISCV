class wdt_timeout_test extends uvm_test;
wdt_timeout_env env;
`uvm_component_utils(wdt_timeout_test)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); env=wdt_timeout_env::type_id::create("env",this); endfunction
endclass
