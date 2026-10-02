// -----------------------------------------------------------------------------
// Project        : RISC-V SoC / MBIST  —  MBIST Controller IP
// File           : axil_mbist_defines.vh
// Description    : Register offsets, word indices, bus widths, algorithm codes,
//                  and response defines for axil_mbist_ctrl_top.
//
// Memory-map     : MBIST Controller CSR base = 0x4000_3000, window = 4 KB
//                  (crossbar m04, AXI4-Lite via bridge)
// -----------------------------------------------------------------------------
`ifndef AXIL_MBIST_DEFINES_VH
`define AXIL_MBIST_DEFINES_VH

// -------------------------------------------------------------------------
// AXI4-Lite CSR Bus Width Parameters (Slave Port)
// -------------------------------------------------------------------------
`define _AXIL_MBIST_DATA_WIDTH_     32   // 32-bit register data
`define _AXIL_MBIST_ADDR_WIDTH_     32   // 32-bit address bus
`define _AXIL_MBIST_ID_WIDTH_        4   // 4-bit AXI transaction ID
`define _AXIL_MBIST_RESP_WIDTH_      2   // 2-bit response

// -------------------------------------------------------------------------
// AXI4 DMA Master Bus Width Parameters (Master Port to DCCM)
// -------------------------------------------------------------------------
`define _AXI4_MBIST_DMA_DATA_WIDTH_ 64   // 64-bit DMA data width
`define _AXI4_MBIST_DMA_ADDR_WIDTH_ 32   // 32-bit address
`define _AXI4_MBIST_DMA_ID_WIDTH_    4   // 4-bit master ID
`define _AXI4_MBIST_DMA_STRB_WIDTH_  8   // 8 byte strobes (64-bit / 8)

// -------------------------------------------------------------------------
// AXI Response Codes
// -------------------------------------------------------------------------
`define AXI_RESP_OKAY               2'b00
`define AXI_RESP_EXOKAY             2'b01
`define AXI_RESP_SLVERR             2'b10
`define AXI_RESP_DECERR             2'b11

// -------------------------------------------------------------------------
// MBIST Controller Base Address & 4 KB Window Prefix
// -------------------------------------------------------------------------
`define MBIST_BASE_ADDR             32'h4000_3000
`define MBIST_BASE_PREFIX           20'h40003

// Byte Offsets
`define MBIST_OFFSET_START          32'h000
`define MBIST_OFFSET_ALGO           32'h004
`define MBIST_OFFSET_ADDR_START     32'h008
`define MBIST_OFFSET_ADDR_END       32'h00C
`define MBIST_OFFSET_BUSY           32'h010
`define MBIST_OFFSET_DONE           32'h014
`define MBIST_OFFSET_PASS_FAIL      32'h018
`define MBIST_OFFSET_FAULT_ADDR     32'h01C
`define MBIST_OFFSET_FAULT_COUNT    32'h020

// Word Indices (addr[11:2])
`define MBIST_REG_START             4'h0  // 0x000 : mbist_start       (W, pulse)
`define MBIST_REG_ALGO              4'h1  // 0x004 : mbist_algo_sel    (R/W, 2-bit)
`define MBIST_REG_ADDR_START        4'h2  // 0x008 : mbist_addr_start  (R/W, 32-bit)
`define MBIST_REG_ADDR_END          4'h3  // 0x00C : mbist_addr_end    (R/W, 32-bit)
`define MBIST_REG_BUSY              4'h4  // 0x010 : mbist_busy        (RO, 1-bit)
`define MBIST_REG_DONE              4'h5  // 0x014 : mbist_done        (RO/W1C, 1-bit)
`define MBIST_REG_PASS_FAIL         4'h6  // 0x018 : mbist_pass_fail   (RO, 1-bit)
`define MBIST_REG_FAULT_ADDR        4'h7  // 0x01C : mbist_fault_addr  (RO, 32-bit)
`define MBIST_REG_FAULT_COUNT       4'h8  // 0x020 : mbist_fault_count (RO, 16-bit)

// -------------------------------------------------------------------------
// Test Algorithm Selection Encodings
// -------------------------------------------------------------------------
`define MBIST_ALGO_CHECKERBOARD     2'b00
`define MBIST_ALGO_MARCH_C          2'b01

`endif // AXIL_MBIST_DEFINES_VH
