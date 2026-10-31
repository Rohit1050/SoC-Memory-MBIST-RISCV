class uart_item extends uvm_sequence_item;

  rand bit fixed_clk_i;
  bit uart_tx_o;
  rand bit uart_rx_i;

  `uvm_object_utils(uart_item)

  function new(string name="uart_item"); super.new(name); endfunction
endclass
