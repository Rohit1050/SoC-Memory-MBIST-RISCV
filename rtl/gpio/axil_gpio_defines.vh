// -----------------------------------------------------------------------------
// Project        : RISC-V SoC / MBIST  —  AXI4-Lite GPIO IP
// File           : axil_gpio_defines.vh
// Description    : Register offsets, word indices, bus widths, and response
//                  defines for axil_gpio_top.
//
// Memory-map     : GPIO base = 0x4000_2000, window = 4 KB
//                  (crossbar m03, AXI4-Lite via bridge)
//
// Revision History
//  Rev | Date       | Description
//  1.0 | 2026-10-03 | Initial version.
// -----------------------------------------------------------------------------
`ifndef AXIL_GPIO_DEFINES_VH
`define AXIL_GPIO_DEFINES_VH

// -------------------------------------------------------------------------
// AXI4-Lite Bus Width Parameters
// -------------------------------------------------------------------------
`define _AXIL_GPIO_DATA_WIDTH_  32   // AXI data bus width (32-bit, Lite side)
`define _AXIL_GPIO_ADDR_WIDTH_  32   // AXI address bus width (matches crossbar)
`define _AXIL_GPIO_ID_WIDTH_     4   // AXI ID width (matches crossbar ID_WIDTH=4)
`define _AXIL_GPIO_RESP_WIDTH_   2   // AXI response field width

// AXI4-Lite response encodings
`define AXIL_GPIO_RESP_OKAY     2'b00
`define AXIL_GPIO_RESP_SLVERR   2'b10

// -------------------------------------------------------------------------
// GPIO Register Offsets & Word Indices
//   Base address : 0x4000_2000
//   Window       : 4 KB (0x4000_2000 – 0x4000_2FFF)
// -------------------------------------------------------------------------
`define GPIO_BASE_ADDR          32'h4000_2000
`define GPIO_BASE_PREFIX        20'h40002

// Byte offsets
`define GPIO_OFFSET_DIR         32'h000
`define GPIO_OFFSET_OUT         32'h004
`define GPIO_OFFSET_IN          32'h008

// Register word indices: addr[11:2]
`define GPIO_REG_DIR            2'h0  // 0x000 : gpio_dir     (R/W, 8-bit)
`define GPIO_REG_OUT            2'h1  // 0x004 : gpio_out_reg (R/W, 8-bit)
`define GPIO_REG_IN             2'h2  // 0x008 : gpio_in_reg  (RO,  8-bit, synchronized)

// GPIO pin width
`define GPIO_WIDTH              8

`endif // AXIL_GPIO_DEFINES_VH
