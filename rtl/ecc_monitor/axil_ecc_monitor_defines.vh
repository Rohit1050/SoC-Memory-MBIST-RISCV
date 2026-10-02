// -----------------------------------------------------------------------------
// Project        : RISC-V SoC / MBIST  —  AXI4-Lite ECC Monitor IP
// File           : axil_ecc_monitor_defines.vh
// Description    : Register offsets, word indices, bus widths, and response
//                  defines for axil_ecc_monitor_top.
//
// Memory-map     : ECC Monitor base = 0x4000_4000, window = 4 KB
//                  (crossbar m05, AXI4-Lite via bridge)
// -----------------------------------------------------------------------------
`ifndef AXIL_ECC_MONITOR_DEFINES_VH
`define AXIL_ECC_MONITOR_DEFINES_VH

// -------------------------------------------------------------------------
// AXI4-Lite Bus Width Parameters
// -------------------------------------------------------------------------
`define _AXIL_ECC_DATA_WIDTH_   32   // AXI data bus width (32-bit, Lite side)
`define _AXIL_ECC_ADDR_WIDTH_   32   // AXI address bus width (matches crossbar)
`define _AXIL_ECC_ID_WIDTH_      4   // AXI ID width (matches crossbar ID_WIDTH=4)
`define _AXIL_ECC_RESP_WIDTH_    2   // AXI response field (OKAY/SLVERR)

// AXI4-Lite response encodings
`define AXIL_ECC_RESP_OKAY      2'b00
`define AXIL_ECC_RESP_SLVERR    2'b10

// -------------------------------------------------------------------------
// ECC Monitor Register Offsets & Word Indices
//   Base address : 0x4000_4000
//   Window       : 4 KB (0x4000_4000 – 0x4000_4FFF)
// -------------------------------------------------------------------------
`define ECC_BASE_ADDR           32'h4000_4000
`define ECC_BASE_PREFIX         20'h40004

// Byte offsets
`define ECC_OFFSET_ENABLE       32'h000
`define ECC_OFFSET_SHADOW_COUNT 32'h004
`define ECC_OFFSET_SHADOW_THRESH 32'h008
`define ECC_OFFSET_EVENT        32'h00C
`define ECC_OFFSET_SUSPECT_ADDR 32'h010
`define ECC_OFFSET_STATUS       32'h014

// Register word indices: addr[11:2]
`define ECC_REG_ENABLE          4'h0  // 0x00 : ecc_mon_enable        (R/W, 1-bit)
`define ECC_REG_SHADOW_COUNT    4'h1  // 0x04 : ecc_mon_shadow_count   (R/W, 27-bit)
`define ECC_REG_SHADOW_THRESH   4'h2  // 0x08 : ecc_mon_shadow_thresh  (R/W, 5-bit)
`define ECC_REG_EVENT           4'h3  // 0x0C : ecc_mon_event          (W1C, 1-bit)
`define ECC_REG_SUSPECT_ADDR    4'h4  // 0x10 : ecc_mon_suspect_addr   (RO,  32-bit)
`define ECC_REG_STATUS          4'h5  // 0x14 : ecc_mon_status         (RO,  2-bit)

// Status bit positions
`define ECC_STATUS_CORR_SEEN    0     // Bit 0: correctable_seen
`define ECC_STATUS_MBIST_CORR   1     // Bit 1: mbist_correlated

`endif // AXIL_ECC_MONITOR_DEFINES_VH
