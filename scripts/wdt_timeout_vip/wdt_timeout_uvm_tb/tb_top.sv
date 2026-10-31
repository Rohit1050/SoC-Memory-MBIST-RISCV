module tb_top;
import uvm_pkg::*; import wdt_timeout_pkg::*;
wdt_timeout_if vif();
initial run_test("wdt_timeout_test");
endmodule
