class gpio_item extends uvm_sequence_item;

  bit [7:0] gpio_out_o;
  rand bit [7:0] gpio_in_i;

  `uvm_object_utils(gpio_item)

  function new(string name="gpio_item"); super.new(name); endfunction
endclass
