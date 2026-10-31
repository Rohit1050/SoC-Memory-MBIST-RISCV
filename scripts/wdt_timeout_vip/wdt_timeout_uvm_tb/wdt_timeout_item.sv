class wdt_timeout_item extends uvm_sequence_item;

  bit wdg_timeout_o;
  bit wdg_irq_pretimeout_o;

  `uvm_object_utils(wdt_timeout_item)

  function new(string name="wdt_timeout_item"); super.new(name); endfunction
endclass
