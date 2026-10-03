// -----------------------------------------------------------------------------
// Project        : RISC-V SoC / MBIST  —  AXI4-Lite System Timer IP
// File           : axil_systimer_defines.vh
// Description    : Register offsets, word indices, bus widths, and response
//                  defines for axil_systimer_top.
//
// Memory-map     : System Timer base = 0x4000_1000, window = 4 KB
//                  (crossbar m02, AXI4-Lite via bridge)
//
// Revision History
//  Rev | Date       | Description
//  1.0 | 2026-10-03 | Initial version.
// -----------------------------------------------------------------------------
`ifndef AXIL_SYSTIMER_DEFINES_VH
`define AXIL_SYSTIMER_DEFINES_VH

// -------------------------------------------------------------------------
// AXI4-Lite Bus Width Parameters
// -------------------------------------------------------------------------
`define _AXIL_STMR_DATA_WIDTH_  32   // AXI data bus width (32-bit, Lite side)
`define _AXIL_STMR_ADDR_WIDTH_  32   // AXI address bus width (matches crossbar)
`define _AXIL_STMR_ID_WIDTH_     4   // AXI ID width (matches crossbar ID_WIDTH=4)
`define _AXIL_STMR_RESP_WIDTH_   2   // AXI response field width

// AXI4-Lite response encodings
`define AXIL_STMR_RESP_OKAY     2'b00
`define AXIL_STMR_RESP_SLVERR   2'b10

// -------------------------------------------------------------------------
// System Timer Register Offsets & Word Indices
//   Base address : 0x4000_1000
//   Window       : 4 KB (0x4000_1000 – 0x4000_1FFF)
// -------------------------------------------------------------------------
`define STMR_BASE_ADDR          32'h4000_1000
`define STMR_BASE_PREFIX        20'h40001

// Byte offsets
`define STMR_OFFSET_EN          32'h000
`define STMR_OFFSET_RELOAD      32'h004
`define STMR_OFFSET_COUNT       32'h008

// Register word indices: addr[11:2]
`define STMR_REG_EN             2'h0  // 0x000 : timer_en     (R/W, 1-bit)
`define STMR_REG_RELOAD         2'h1  // 0x004 : timer_reload (R/W, 32-bit)
`define STMR_REG_COUNT          2'h2  // 0x008 : timer_count  (RO,  32-bit)

`endif // AXIL_SYSTIMER_DEFINES_VH
