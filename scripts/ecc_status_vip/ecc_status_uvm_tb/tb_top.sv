module tb_top;
import uvm_pkg::*; import ecc_status_pkg::*;
ecc_status_if vif();
initial run_test("ecc_status_test");
endmodule
