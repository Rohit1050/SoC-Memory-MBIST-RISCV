class uart_test extends uvm_test;
uart_env env;
`uvm_component_utils(uart_test)
function new(string n,uvm_component p);super.new(n,p);endfunction
function void build_phase(uvm_phase phase); env=uart_env::type_id::create("env",this); endfunction
endclass
