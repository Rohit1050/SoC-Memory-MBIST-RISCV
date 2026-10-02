# Watchdog Timer IP — What It Does and Why

## The Problem It Solves

During autonomous memory self-test (MBIST) or normal application execution, firmware loops or hardware transactions may enter an unrecoverable deadlock:

- An AXI transaction on the VeeR EL2 DMA Slave Port might stall or wait indefinitely for an unasserted handshake (`READY` or `VALID`).
- An algorithmic MBIST scan or ISR polling loop might hang.
- Software corruption (e.g., jump to invalid address or corrupted stack) might prevent the processor from making forward progress.

Because the SoC is intended to run autonomously in the field without external test equipment or manual reset buttons, it requires a **hardware supervisor** that continuously monitors firmware liveness and autonomously enforces a system recovery if the processor stops making progress.

The **Watchdog Timer (WDT)** provides this safety net.

---

## How Watchdog Supervision & Reset Recovery Works

The Watchdog Timer uses a **countdown timer** clocked from the system clock (`axi_aclk_i`). Firmware is required to periodically "pet" (or "kick") the watchdog by writing to the `wdg_kick` register before the countdown reaches zero.

```
Normal Operation (Firmware Alive):
───────────────────────────────────
  Load value (e.g. 50,000) ──► Countdown decrements: 50,000 → 49,999 → ...
                                       │
  Firmware writes wdg_kick ────────────┴──► Reload countdown back to 50,000!
  (wdg_timeout_o remains 0; system continues normal execution)

Failure / Hang Condition:
─────────────────────────
  Firmware hangs in loop   ──► Countdown continues decrementing unchecked:
                                 ... → 100 → ... → 1 → 0 (EXPIRY!)
                                       │
                                       ├─► Assert wdg_timeout_o pulse/level
                                       ├─► Latch wdg_status.timeout_occurred = 1
                                       │
                                       ▼
                         External Reset Generation Logic
                                       │
                                       ▼
                         Re-asserts rst_l to Core & Peripherals
                                       │
                                       ▼
                         Core Reboots from Boot Vector
```

---

## Architecture and System Connections

```
                     ┌───────────────────────────────┐
                     │        VeeR EL2 Core          │
                     │                               │
                     │   LSU Master (0x4000_5000)    │
                     └───────┬───────────────▲───────┘
                             │               │
                    AXI4-Lite Write/Read     │ rst_l
                             │               │ (System Reset)
                             ▼               │
    ┌───────────────────────────────────┐    │
    │        axil_wdt_top (IP)          │    │
    │                                   │    │
    │  wdg_enable       [R/W, 1-bit]    │    │
    │  wdg_load         [R/W, 32-bit]   │    │
    │  wdg_kick         [W,   32-bit]   │    │
    │  wdg_count        [RO,  32-bit]   │    │
    │  wdg_pretimeout   [R/W, 32-bit]   │    │
    │                                   │    │
    │  timeout_occurred [R/W1C, 1-bit]  │    │
    │  (Cold POR reset domain)          │    │
    └──────┬──────────────────────┬─────┘    │
           │                      │          │
     wdg_timeout_o        wdg_irq_pretimeout │
           │                      │          │
           ▼                      ▼          │
  ┌─────────────────┐    ┌─────────────────┐ │
  │ External Reset  │    │ VeeR EL2 PIC    │ │
  │ Generation Logic├────┼─────────────────┼─┘
  └─────────────────┘    │ (extintsrc_req) │
                         └─────────────────┘
```

---

## Dual-Reset Domain Architecture (Post-Mortem Analysis)

A critical requirement in high-reliability embedded systems is knowing **why** the system rebooted:
- Was it a power-up (cold reset)?
- Or did the watchdog timer expire because of a firmware hang (warm recovery)?

To enable post-mortem firmware inspection after a reboot:

1. **`por_rstn_i` (Power-On Reset / Cold Reset):**
   - Asserted only during board power-up or cold system reset.
   - Clears `timeout_occurred` to `0`.
2. **`axi_aresetn_i` (System Reset / Warm Reset):**
   - Driven by external reset logic when `wdg_timeout_o` fires or when external `rst_l` is asserted.
   - Resets AXI handshake FSMs and operational registers (`wdg_enable`, `wdg_load`, `wdg_count`, `wdg_pretimeout`).
   - **Does NOT clear `timeout_occurred`!**
3. **Post-Reboot Inspection:**
   - After reboot, the startup code reads `wdg_status[0]`.
   - If `1`, firmware logs that a watchdog recovery took place (e.g., prints a warning to UART) and writes `1` to `wdg_status[0]` to clear it (**W1C**).

---

## Register Map

Base address: **`0x4000_5000`**, Window: **4 KB** (`0x4000_5000` – `0x4000_5FFF`).

| Offset | Register Name | Width | Access | Reset | Description |
|---|---|---|---|---|---|
| `0x000` | `wdg_enable` | 1 | R/W | `0x0` | Master enable. Bit 0: `1` = countdown active, `0` = countdown halted. |
| `0x004` | `wdg_load` | 32 | R/W | `0x0` | Reload value (timeout period in clock cycles). Loaded into `wdg_count` on kick or when enabled. |
| `0x008` | `wdg_kick` | 32 | W | — | Pet watchdog. Writing any value reloads `wdg_count` with `wdg_load`. Reads return `0x0`. |
| `0x00C` | `wdg_count` | 32 | RO | `0x0` | Current countdown value (diagnostic read). Writes return `SLVERR`. |
| `0x010` | `wdg_status` | 1 | R/W1C | `0x0` | Bit 0: `timeout_occurred`. Latched across warm resets. Writing `1` clears the bit. |
| `0x014` | `wdg_pretimeout` | 32 | R/W | `0x0` | Early-warning interrupt threshold. Asserts `wdg_irq_pretimeout_o` when `wdg_count <= wdg_pretimeout`. |
| `0x018`–`0xFFC` | *(undefined)* | — | — | — | Unmapped offsets in the 4 KB window return `SLVERR`. |

---

## Operational Behaviour (Step by Step)

### 1. Boot and Initialisation (Firmware)
```c
// Configure timeout for 1,000,000 clock cycles (~20 ms @ 50 MHz)
*(volatile uint32_t *)(0x40005004) = 1000000;

// Configure early-warning threshold at 200,000 cycles (~4 ms before timeout)
*(volatile uint32_t *)(0x40005014) = 200000;

// Inspect post-mortem status
uint32_t status = *(volatile uint32_t *)(0x40005010);
if (status & 0x1) {
    uart_puts("WARN: System recovered from Watchdog Timeout!\n");
    // Clear the sticky flag (W1C)
    *(volatile uint32_t *)(0x40005010) = 0x1;
}

// Enable Watchdog countdown
*(volatile uint32_t *)(0x40005000) = 1;
```

### 2. Normal Steady State (Petting the Dog)
Within the main application loop, MBIST test scheduler, or periodic timer ISR:
```c
// Reset countdown back to wdg_load
*(volatile uint32_t *)(0x40005008) = 0xA5A5A5A5;
```

### 3. Early-Warning Pre-Timeout Interrupt
- If firmware execution is delayed and `wdg_count` drops below `wdg_pretimeout`, `wdg_irq_pretimeout_o` asserts.
- The VeeR EL2 Programmable Interrupt Controller (PIC) routes this interrupt to the core.
- The ISR can attempt diagnostic state capture (stack trace, registers) or execute an emergency kick before hardware reset occurs.

### 4. Hardware Timeout and Recovery
- If no kick occurs and `wdg_count` reaches `0`:
  1. `wdg_timeout_o` asserts.
  2. `timeout_occurred` status bit is set to `1`.
  3. External reset logic detects `wdg_timeout_o` and pulses system reset `rst_l`.
  4. Core complex reboots cleanly.

---

## Integration Checklist

- [x] **RTL Top Wrapper:** [`rtl/watchdog_timer/axil_wdt_top.v`](file:///home/rohit/SoC-Memory-MBIST-RISCV/rtl/watchdog_timer/axil_wdt_top.v)
- [x] **Timer Core Engine:** [`rtl/watchdog_timer/wdt_core.v`](file:///home/rohit/SoC-Memory-MBIST-RISCV/rtl/watchdog_timer/wdt_core.v)
- [x] **Register Defines Header:** [`rtl/watchdog_timer/axil_wdt_defines.vh`](file:///home/rohit/SoC-Memory-MBIST-RISCV/rtl/watchdog_timer/axil_wdt_defines.vh)
- [x] **Unit Testbench:** [`tb/watchdog_timer/tb_axil_wdt_top.v`](file:///home/rohit/SoC-Memory-MBIST-RISCV/tb/watchdog_timer/tb_axil_wdt_top.v) (12 test cases)
- [x] **AXI4 Crossbar Interconnect:** Crossbar master port `m06` (`M06_BASE_ADDR = 32'h4000_5000`, `M06_ADDR_WIDTH = 12`)
- [x] **Protocol Bridge:** [`rtl/InterConnect/rtl/axi4_to_axil_bridge.v`](file:///home/rohit/SoC-Memory-MBIST-RISCV/rtl/InterConnect/rtl/axi4_to_axil_bridge.v) (64-bit to 32-bit conversion)
- [ ] **PIC Interrupt Line:** Connect `wdg_irq_pretimeout_o` to PIC `extintsrc_req` pin
- [ ] **Reset Logic:** Connect `wdg_timeout_o` to SoC external reset generator to drive `rst_l`

---

*Document revision: 1.0 — 2026-10-02*
