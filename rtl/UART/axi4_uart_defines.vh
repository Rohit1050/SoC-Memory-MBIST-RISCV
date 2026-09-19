// -----------------------------------------------------------------------------
// Project        : AXI4 UART IP Core
// File           : axi4_uart_defines.vh
// Description    : AXI4 bus parameters and UART register map / config defines
// Note           : This replaces axi_uart_defines.vh + axi_uart.vh for the
//                  full AXI4 (burst-capable) version of the UART slave.
// ------------------------------------------------------------------------------
// Revision History
//  Revision  | Description
//  4.0       | Full AXI4 upgrade: burst channels, AxLEN/AxSIZE/AxBURST/
//            | WLAST/RLAST, separate ACLK from fixed_clk, QoS/cache/lock
// -----------------------------------------------------------------------------

`ifndef AXI4_UART_DEFINES_VH
`define AXI4_UART_DEFINES_VH

// -------------------------------------------------------------------------
// AXI4 Bus Width Parameters
// -------------------------------------------------------------------------
`define _AXI_UART_DATA_WIDTH_   32   // AXI data bus width  (32 or 64 bits)
`define _AXI_UART_ADDR_WIDTH_   32   // AXI address bus width
`define _AXI_UART_ID_WIDTH_      4   // AXI ID field width
`define _AXI_UART_RESP_WIDTH_    2   // AXI response field width (OKAY/EXOKAY/SLVERR/DECERR)
`define _AXI_UART_DIV_WIDTH_    16   // Baud-rate divisor register width

// -------------------------------------------------------------------------
// AXI4 Burst Parameters
// -------------------------------------------------------------------------
`define _AXI_UART_LEN_WIDTH_     8   // AxLEN  width  (AXI4: 0-255 beats)
`define _AXI_UART_SIZE_WIDTH_    3   // AxSIZE width  (encodes bytes per beat)
`define _AXI_UART_BURST_WIDTH_   2   // AxBURST width  (FIXED/INCR/WRAP)
`define _AXI_UART_LOCK_WIDTH_    1   // AxLOCK width  (AXI4: 1 bit)
`define _AXI_UART_CACHE_WIDTH_   4   // AxCACHE width
`define _AXI_UART_PROT_WIDTH_    3   // AxPROT width
`define _AXI_UART_QOS_WIDTH_     4   // AxQOS  width
`define _AXI_UART_REGION_WIDTH_  4   // AxREGION width (optional; tie to 0 if unused)

// AXI4 burst type encodings
`define AXI4_BURST_FIXED   2'b00
`define AXI4_BURST_INCR    2'b01
`define AXI4_BURST_WRAP    2'b10

// AXI4 response encodings
`define AXI4_RESP_OKAY     2'b00
`define AXI4_RESP_EXOKAY   2'b01
`define AXI4_RESP_SLVERR   2'b10
`define AXI4_RESP_DECERR   2'b11

// -------------------------------------------------------------------------
// Internal FIFO depth
// -------------------------------------------------------------------------
`define _AXI_UART_FIFO_DEPTH_   16   // 16-entry deep TX/RX FIFOs

// -------------------------------------------------------------------------
// Deadlock watchdog limit (cycles before forcing idle on stuck transaction)
// -------------------------------------------------------------------------
`define _AXI_UART_DEADLOCK_     256

// =========================================================================
// UART Register Map  (word-addressed; byte address = field << 2)
// =========================================================================
//  Offset  | Name              | Access | Description
//  0x00    | RBR / THR         | R / W  | Receive Buffer / Transmit Holding Reg
//  0x04    | IER               | R/W    | Interrupt Enable Register
//  0x08    | BAUD_DIVISOR      | R/W    | Baud-rate divisor (DLAB=1)
//  0x0C    | LCR               | R/W    | Line Control Register
//  0x14    | LSR               | R      | Line Status Register
// =========================================================================
`define _UART_RBR_          5'h00   // 0x00 >> 2  -> word index 0
`define _UART_THR_          5'h00   // same address, direction differs
`define _UART_IER_          5'h01   // 0x04 >> 2  -> word index 1
`define _UART_BAUD_DIVISOR_ 5'h02   // 0x08 >> 2  -> word index 2
`define _UART_LCR_          5'h03   // 0x0C >> 2  -> word index 3
`define _UART_LSR_          5'h05   // 0x14 >> 2  -> word index 5

// -------------------------------------------------------------------------
// LCR bit positions  (within the 32-bit config register)
// -------------------------------------------------------------------------
`define _UART_CONFIG_STOP_BITS_   0   // LCR[0]: 0=1 stop bit, 1=2 stop bits
`define _UART_CONFIG_PARITY_EN_   1   // LCR[1]: 0=no parity, 1=parity enabled
`define _UART_CONFIG_PARITY_MODE_ 2   // LCR[2]: 0=odd parity, 1=even parity
`define _UART_CONFIG_DLAB_        7   // LCR[7]: Divisor Latch Access Bit

// -------------------------------------------------------------------------
// LSR bit positions  (within the 32-bit status register)
// -------------------------------------------------------------------------
`define _UART_LSR_DATA_READY_ 0   // LSR[0]: RX data available
`define _UART_LSR_THRE_       5   // LSR[5]: TX Holding Register Empty
`define _UART_LSR_TEMT_       6   // LSR[6]: TX Empty (shift + holding empty)

// -------------------------------------------------------------------------
// UART data-path width and default baud-rate divisor
// -------------------------------------------------------------------------
`define _DATA_WIDTH_UART_         8    // 8-bit UART data
`define _UART_BAUDRATE_DIV_INIT_  434  // Default: 115 200 bps @ 50 MHz clock
                                       //  50_000_000 / 115_200 ≈ 434

`endif // AXI4_UART_DEFINES_VH
