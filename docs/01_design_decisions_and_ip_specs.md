# Design Decisions and IP Specifications
## RISC-V SoC — MBIST / ECC Monitor Platform

---

## 1. Overview

This document records the architectural decisions made during RTL specification and
the IP-level register maps, parameter choices, and interface conventions that are
frozen for this project.  It is the authoritative source of truth for integration;
if it conflicts with any other document (including older PDF revisions), this file
takes precedence.

---

## 2. Global Memory Map

| Base Address    | Size  | Block                             | Interface        |
|-----------------|-------|-----------------------------------|------------------|
| `0x0004_0000`   | 128 KB | ICCM                             | DMA Slave Port  |
| `0x0008_0000`   | 128 KB | DCCM (SECDED ECC)                | DMA Slave Port  |
| `0x4000_0000`   | 4 KB  | **UART**                          | AXI4-Lite       |
| `0x4000_1000`   | 4 KB  | System Timer                      | AXI4-Lite       |
| `0x4000_2000`   | 4 KB  | GPIO                              | AXI4-Lite       |
| `0x4000_3000`   | 4 KB  | MBIST Controller (CSR slave)      | AXI4-Lite       |
| `0x4000_4000`   | 4 KB  | ECC Monitor                       | AXI4-Lite       |
| `0x4000_5000`   | 4 KB  | Watchdog Timer                    | AXI4-Lite       |

All peripherals at `0x4000_xxxx` are reached through the `axi_interconnect_wrap_4x7`
crossbar's master ports `m01`–`m06`, each via a shared AXI4-to-AXI4-Lite bridge.
The crossbar itself operates at `DATA_WIDTH=64`, `ADDR_WIDTH=32`, `ID_WIDTH=4`.
The bridge performs 64→32 data-width conversion; peripherals are 32-bit.

---

## 3. Peripheral IP Specifications

### 3.1 AXI4 Crossbar Parameters (frozen)

| Parameter    | Value | Notes                                     |
|--------------|-------|-------------------------------------------|
| `DATA_WIDTH` | 64    | Master-side (core IFU/LSU/Debug/MBIST)    |
| `ADDR_WIDTH` | 32    | All address channels                      |
| `ID_WIDTH`   | 4     | Applied to all slave and master ports     |
| `M_REGIONS`  | 1     | Single address region per master port     |

### 3.2 AXI4-Lite Peripheral Interface Convention (all IPs at `0x4000_xxxx`)

All AXI4-Lite peripherals in this project share the same port conventions,
derived from the crossbar's Lite-side port after the bridge:

| Parameter    | Value | Notes                                        |
|--------------|-------|----------------------------------------------|
| `DATA_WIDTH` | 32    | Bridge handles 64→32 conversion              |
| `ADDR_WIDTH` | 32    | Full address bus retained through bridge     |
| `ID_WIDTH`   | 4     | Bridge propagates ID unchanged               |

Port naming prefix: `axi_aw*`, `axi_w*`, `axi_b*`, `axi_ar*`, `axi_r*` with
`_i` / `_o` suffixes on inputs and outputs respectively.

---

### 3.3 UART — `axil_uart_top`

**File:** `rtl/UART/axil_uart_top.v`  
**Defines:** `rtl/UART/axil_uart_defines.vh`  
**Base address:** `0x4000_0000`  
**Window:** 4 KB (`0x4000_0000` – `0x4000_0FFF`)  
**Interface:** AXI4-Lite (`DATA_WIDTH=32`, `ADDR_WIDTH=32`, `ID_WIDTH=4`)

#### 3.3.1 Parameters

| Parameter              | Define                     | Value | Frozen? |
|------------------------|----------------------------|-------|---------|
| AXI data width         | `_AXI_UART_DATA_WIDTH_`    | 32    | ✓       |
| AXI address width      | `_AXI_UART_ADDR_WIDTH_`    | 32    | ✓       |
| AXI ID width           | `_AXI_UART_ID_WIDTH_`      | 4     | ✓       |
| Baud-rate div width    | `_AXI_UART_DIV_WIDTH_`     | 16    | ✓       |
| RX / TX FIFO depth     | `_AXI_UART_FIFO_DEPTH_`    | 16    | —       |
| Default baud divisor   | `_UART_BAUDRATE_DIV_INIT_` | 434   | — (115 200 bps @ 50 MHz) |
| UART data width        | `_DATA_WIDTH_UART_`        | 8     | ✓       |

Note: AXI4 burst parameters (`LEN_WIDTH`, `SIZE_WIDTH`, `BURST_WIDTH`,
`LOCK_WIDTH`, `CACHE_WIDTH`, `PROT_WIDTH`, `QOS_WIDTH`, `REGION_WIDTH`)
are **absent** from `axil_uart_defines.vh`.  AXI4-Lite has no burst channels.

#### 3.3.2 Register Map

All offsets are relative to the base address `0x4000_0000`.  All registers
are 32-bit wide; only the defined bits carry meaning.

| Offset  | Word idx | Register     | Access | Reset  | Description                                            |
|---------|----------|--------------|--------|--------|--------------------------------------------------------|
| `0x000` | `5'h00`  | RBR          | R      | —      | Receive Buffer Register.  Reads oldest RX FIFO byte.  Valid when LSR[0]=1.  If DLAB=1, reads BAUD_DIVISOR[15:0] instead. |
| `0x000` | `5'h00`  | THR          | W      | —      | Transmit Holding Register.  Writes byte to TX FIFO.  Ignored if TX FIFO full or DLAB=1. |
| `0x004` | `5'h01`  | IER          | R/W    | 0x0    | Interrupt Enable Register.  IER[0]: RX data-ready interrupt enable. |
| `0x008` | `5'h02`  | BAUD_DIVISOR | R/W    | 434    | Baud-rate Divisor (16-bit).  New value takes effect immediately on write.  No DLAB guard on this register's own address. |
| `0x00C` | `5'h03`  | LCR          | R/W    | 0x0    | Line Control Register.  See bit map below.             |
| `0x010` | `5'h04`  | *(reserved)* | —      | —      | No register.  Reads return 0x0 with SLVERR.            |
| `0x014` | `5'h05`  | LSR          | R      | —      | Line Status Register (read-only, combinatorial).  See bit map below. |
| `0x018`+| —        | *(undefined)*| —      | —      | All other offsets within the 4 KB window return SLVERR. |

**All offsets resolve to addresses in the range `0x4000_0000`–`0x4000_0FFF` and
are 4-byte aligned. ✓**

#### 3.3.3 LCR Bit Map (offset `0x00C`)

| Bit | Name          | Reset | Description                                |
|-----|---------------|-------|--------------------------------------------|
| 0   | `STOP_BITS`   | 0     | 0 = 1 stop bit; 1 = 2 stop bits           |
| 1   | `PARITY_EN`   | 0     | 0 = no parity; 1 = parity enabled         |
| 2   | `PARITY_MODE` | 0     | 0 = odd parity; 1 = even parity           |
| 6:3 | *(reserved)*  | 0     | Reads as 0; writes ignored                |
| 7   | `DLAB`        | 0     | Divisor Latch Access Bit.  When DLAB=1:  `0x000` R → BAUD_DIVISOR read; `0x000` W → ignored; `0x004` R/W → reserved (reads 0). |
| 31:8| *(reserved)*  | 0     | —                                          |

#### 3.3.4 LSR Bit Map (offset `0x014`)

| Bit | Name          | Description                                         |
|-----|---------------|-----------------------------------------------------|
| 0   | `DR`          | Data Ready: 1 when RX FIFO is non-empty AND IER[0]=1 |
| 4:1 | *(reserved)*  | Always 0                                            |
| 5   | `THRE`        | TX Holding Register Empty: 1 when TX FIFO has space  |
| 6   | `TEMT`        | TX Empty: 1 when TX FIFO and TX shift register empty |
| 31:7| *(reserved)*  | Always 0                                            |

#### 3.3.5 Clock Domain Notes

The module has two clock inputs:

- **`fixed_clk_i`** — UART baud-clock domain.  All sequential logic, including the
  AXI4-Lite channel handshake registers, is clocked on this domain.  Must be
  ≥ 16× the desired baud rate.

- **`axi_aclk_i`** — AXI bus clock.  Present for port compatibility with the bridge
  interface.  Currently **unused internally** — the bridge-facing AXI channel
  signals are sampled directly on `fixed_clk_i`.

  **⚠ CDC hazard:** If `fixed_clk_i ≠ axi_aclk_i` the AXI input signals cross
  clock domains without synchronizers inside this module.  A future CDC pass must
  add two-flop synchronizers before deploying to an asynchronous multi-clock
  system.  The current design is correct only when the two clocks are the same
  or phase-locked.

#### 3.3.6 FIFO Behaviour

- **TX FIFO** (depth 16): firmware writes to THR; `uart_controller` drains it.
  Writes to THR when the TX FIFO is full are silently dropped.
- **RX FIFO** (depth 16): `uart_controller` pushes received bytes; reads of RBR
  pop the oldest byte.  The `DR` bit in LSR reflects non-empty status gated by
  `IER[0]`.  If the FIFO overflows, the oldest unread byte is overwritten (no
  overflow interrupt in this revision).

#### 3.3.7 Decision: 16550-style map vs. 4-register placeholder

The `axi4_uart_top.v` baseline carried a 16550-compatible register map
(RBR/THR, IER, BAUD_DIVISOR, LCR, LSR).  An earlier design-document draft
contained a simpler 4-register placeholder.  **Decision: the 16550-style map
is adopted as the project's frozen UART register map** because:

1. It is already implemented by the UART datapath sub-modules
   (`uart_controller`, `uart_transmitter`, `uart_receiver`).
2. It provides interrupt enable, configurable parity/stop-bits, and baud-rate
   control — all required by the firmware self-test loop.
3. The DLAB mechanism allows baud-rate divisor access without consuming an
   additional register offset.

The simpler placeholder is superseded by this table.

---

## 4. Verification Notes

See `tb/uart/tb_axil_uart_top.v` for the UART unit-level testbench.
The shared AXI4-Lite BFM master is in `tb/common/axil_bfm_master.v`.

Coverage targets:
- Each register's read/write at its correct offset
- DLAB-gated access (baud divisor read/write, RBR suppression)
- TX FIFO full edge case (write to full FIFO → data dropped, no hang)
- RX data arrival → interrupt assertion → interrupt clear on RBR read
- SLVERR response on undefined offsets within the 4 KB window

---

*Document revision: 1.0 — 2026-10-02*
