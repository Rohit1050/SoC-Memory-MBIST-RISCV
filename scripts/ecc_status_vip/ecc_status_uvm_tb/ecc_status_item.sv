class ecc_status_item extends uvm_sequence_item;

  bit dccm_ecc_single_error_o;
  bit dccm_ecc_double_error_o;
  bit iccm_ecc_single_error_o;
  bit iccm_ecc_double_error_o;

  `uvm_object_utils(ecc_status_item)

  function new(string name="ecc_status_item"); super.new(name); endfunction
endclass
