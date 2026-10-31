class ecc_status_test extends uvm_test;
ecc_status_env env;
`uvm_component_utils(ecc_status_test)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); env=ecc_status_env::type_id::create("env",this); endfunction
endclass
