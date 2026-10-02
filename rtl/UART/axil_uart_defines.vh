// -----------------------------------------------------------------------------
// Project        : RISC-V SoC / MBIST  —  AXI4-Lite UART IP
// File           : axil_uart_defines.vh
// Description    : AXI4-Lite bus parameters and UART register-map / config
//                  defines for axil_uart_top.
//
//                  Derived from axi4_uart_defines.vh (full-AXI4 version) by:
//                    • Removing all AXI4 burst-specific width parameters
//                      (LEN, SIZE, BURST, LOCK, CACHE, PROT, QOS, REGION).
//                    • Retaining the 16550-style register map unchanged —
//                      all offsets already fall inside the 4 KB window
//                      allocated to UART (0x4000_0000 – 0x4000_0FFF) and
//                      are 4-byte aligned.
//                    • Confirming DATA_WIDTH=32, ADDR_WIDTH=32, ID_WIDTH=4
//                      match the crossbar (axi_interconnect_wrap_4x7)
//                      parameters after the AXI4-to-AXI4-Lite bridge.
//
// Memory-map     : UART base = 0x4000_0000, window = 4 KB
//                  (crossbar m01, AXI4-Lite via bridge)
//
// Revision History
//  Rev | Description
//  1.0 | Derived from axi4_uart_defines.vh rev 4.0; burst params removed.
// -----------------------------------------------------------------------------

`ifndef AXIL_UART_DEFINES_VH
`define AXIL_UART_DEFINES_VH

// -------------------------------------------------------------------------
// AXI4-Lite Bus Width Parameters
// -------------------------------------------------------------------------
`define _AXI_UART_DATA_WIDTH_   32   // AXI data bus width (32-bit, Lite side)
`define _AXI_UART_ADDR_WIDTH_   32   // AXI address bus width (matches crossbar)
`define _AXI_UART_ID_WIDTH_      4   // AXI ID width (matches crossbar ID_WIDTH=4)
`define _AXI_UART_RESP_WIDTH_    2   // AXI response field (OKAY/EXOKAY/SLVERR/DECERR)
`define _AXI_UART_DIV_WIDTH_    16   // Baud-rate divisor register width

// NOTE: AXI4 burst-specific parameters (LEN, SIZE, BURST, LOCK, CACHE, PROT,
// QOS, REGION) are intentionally absent.  AXI4-Lite has no burst channels.

// AXI4-Lite response encodings
`define AXIL_RESP_OKAY     2'b00
`define AXIL_RESP_EXOKAY   2'b01   // not used on Lite, included for completeness
`define AXIL_RESP_SLVERR   2'b10
`define AXIL_RESP_DECERR   2'b11

// -------------------------------------------------------------------------
// Internal FIFO depth
// -------------------------------------------------------------------------
`define _AXI_UART_FIFO_DEPTH_   16   // 16-entry deep TX / RX FIFOs

// -------------------------------------------------------------------------
// Deadlock watchdog limit (cycles before forcing idle on stuck transaction)
// -------------------------------------------------------------------------
`define _AXI_UART_DEADLOCK_     256

// =========================================================================
// UART Register Map
//   Base address : 0x4000_0000  (added by system; offsets below are from base)
//   Window       : 4 KB (0x000 – 0xFFF)
//   Encoding     : 5-bit word index; byte address = (index << 2)
//
//  Word index | Byte offset | Name              | Access | Description
//  5'h00      | 0x000       | RBR               | R      | Receive  Buffer Register
//  5'h00      | 0x000       | THR               | W      | Transmit Holding Register
//  5'h01      | 0x004       | IER               | R/W    | Interrupt Enable Register
//  5'h02      | 0x008       | BAUD_DIVISOR      | R/W    | Baud-rate Divisor (DLAB=1)
//  5'h03      | 0x00C       | LCR               | R/W    | Line Control Register
//  5'h04      |  —          | (reserved)        |  —     | No register; SLVERR on access
//  5'h05      | 0x014       | LSR               | R      | Line Status Register
//  5'h06+     |  —          | (undefined)       |  —     | SLVERR on access
// =========================================================================
`define _UART_RBR_          5'h00   // byte offset 0x000
`define _UART_THR_          5'h00   // byte offset 0x000  (direction selects R vs W)
`define _UART_IER_          5'h01   // byte offset 0x004
`define _UART_BAUD_DIVISOR_ 5'h02   // byte offset 0x008
`define _UART_LCR_          5'h03   // byte offset 0x00C
`define _UART_LSR_          5'h05   // byte offset 0x014

// -------------------------------------------------------------------------
// LCR bit positions  (within the 32-bit line-control register)
// -------------------------------------------------------------------------
`define _UART_CONFIG_STOP_BITS_   0   // LCR[0]: 0=1 stop bit, 1=2 stop bits
`define _UART_CONFIG_PARITY_EN_   1   // LCR[1]: 0=no parity,  1=parity enabled
`define _UART_CONFIG_PARITY_MODE_ 2   // LCR[2]: 0=odd parity, 1=even parity
`define _UART_CONFIG_DLAB_        7   // LCR[7]: Divisor Latch Access Bit
                                      //   DLAB=1: RBR/THR addr → BAUD_DIVISOR
                                      //           IER  addr    → reserved (reads 0)

// -------------------------------------------------------------------------
// LSR bit positions  (within the 32-bit line-status register)
// -------------------------------------------------------------------------
`define _UART_LSR_DATA_READY_ 0   // LSR[0]: RX data available in RX FIFO
`define _UART_LSR_THRE_       5   // LSR[5]: TX Holding Register Empty
`define _UART_LSR_TEMT_       6   // LSR[6]: TX completely empty (shift + holding)

// -------------------------------------------------------------------------
// UART data-path width and default baud-rate divisor
// -------------------------------------------------------------------------
`define _DATA_WIDTH_UART_         8    // 8-bit UART data
`define _UART_BAUDRATE_DIV_INIT_  434  // Default: 115 200 bps @ 50 MHz
                                       //   50_000_000 / 115_200 ≈ 434

`endif // AXIL_UART_DEFINES_VH
