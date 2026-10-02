// -----------------------------------------------------------------------------
// Project        : RISC-V SoC / MBIST  —  AXI4-Lite Watchdog Timer IP
// File           : axil_wdt_defines.vh
// Description    : Register offsets, word indices, bus widths, and response
//                  defines for axil_wdt_top and wdt_core.
//
// Memory-map     : Watchdog Timer base = 0x4000_5000, window = 4 KB
//                  (crossbar m06, AXI4-Lite via bridge)
// -----------------------------------------------------------------------------
`ifndef AXIL_WDT_DEFINES_VH
`define AXIL_WDT_DEFINES_VH

// -------------------------------------------------------------------------
// AXI4-Lite Bus Width Parameters
// -------------------------------------------------------------------------
`define _AXIL_WDT_DATA_WIDTH_   32   // AXI data bus width (32-bit, Lite side)
`define _AXIL_WDT_ADDR_WIDTH_   32   // AXI address bus width (matches crossbar)
`define _AXIL_WDT_ID_WIDTH_      4   // AXI ID width (matches crossbar ID_WIDTH=4)
`define _AXIL_WDT_RESP_WIDTH_    2   // AXI response field (OKAY/SLVERR)

// AXI4-Lite response encodings
`define AXIL_WDT_RESP_OKAY      2'b00
`define AXIL_WDT_RESP_SLVERR    2'b10

// -------------------------------------------------------------------------
// Watchdog Timer Register Offsets & Word Indices
//   Base address : 0x4000_5000
//   Window       : 4 KB (0x4000_5000 – 0x4000_5FFF)
// -------------------------------------------------------------------------
`define WDT_BASE_ADDR           32'h4000_5000
`define WDT_BASE_PREFIX         20'h40005

// Byte offsets
`define WDT_OFFSET_ENABLE       32'h000
`define WDT_OFFSET_LOAD         32'h004
`define WDT_OFFSET_KICK         32'h008
`define WDT_OFFSET_COUNT        32'h00C
`define WDT_OFFSET_STATUS       32'h010
`define WDT_OFFSET_PRETIMEOUT   32'h014

// Register word indices: addr[11:2]
`define WDT_REG_ENABLE          4'h0  // 0x000 : wdg_enable     (R/W, 1-bit)
`define WDT_REG_LOAD            4'h1  // 0x04   : wdg_load       (R/W, 32-bit)
`define WDT_REG_KICK            4'h2  // 0x08   : wdg_kick       (W,   32-bit)
`define WDT_REG_COUNT           4'h3  // 0x0C   : wdg_count      (RO,  32-bit)
`define WDT_REG_STATUS          4'h4  // 0x10   : wdg_status     (R/W1C, 1-bit)
`define WDT_REG_PRETIMEOUT      4'h5  // 0x14   : wdg_pretimeout (R/W, 32-bit)

// Bit positions
`define WDT_STATUS_TIMEOUT_BIT  0     // wdg_status[0] = timeout_occurred

`endif // AXIL_WDT_DEFINES_VH
