# SoC-Memory-MBIST-RISCV — Testbenches

**Project Root:** `SoC-Memory-MBIST-RISCV/`
**Testbench Directory:** `tb/`
**Simulator:** Synopsys VCS (`vcs -full64 -sverilog`) / ModelSim (`vlog`) / Verilator
**Simulation Launch:** `run/run_ip.sh <ip_name>` or manually via `.f` filelists in `run/`

---

## 1. Testbench Architecture Overview

```
  tb/
   │
   ├── common/
   │    └── axil_bfm_master.v   ← Shared AXI4-Lite BFM (included by all unit TBs)
   │
   ├── top/                     ← Full-SoC integration testbench
   │    ├── tb_soc_top.v        ← Top-level TB: instantiates soc_core_integration + models
   │    ├── dccm_behavioral_model.v    ← DCCM simulation model with SECDED ECC
   │    ├── iccm_behavioral_model.v    ← ICCM simulation model
   │    └── uart_monitor.v             ← UART TX sniffer (decodes serial to ASCII)
   │
   └── <ip>/                    ← One self-contained unit TB per custom IP
        ├── tb_axil_mbist_ctrl_top.v
        ├── tb_axil_ecc_monitor_top.v
        ├── tb_axil_wdt_top.v
        ├── tb_axil_systimer_top.v
        ├── tb_axil_uart_top.v
        └── tb_axil_gpio_top.v
```

All unit testbenches share a common structure:
- Include `axil_bfm_master.v` via `+incdir` for AXI4-Lite read/write tasks.
- Instantiate the DUT directly.
- Self-check with `$display` pass/fail messages and `$finish`/non-zero exit on failure.
- Compiled with `+define+SIM` and the IP-specific standalone define (e.g., `+define+MBIST_CTRL_STANDALONE`).

---

## 2. Common BFM — `tb/common/axil_bfm_master.v`

A reusable AXI4-Lite master BFM included by every unit testbench. Provides:

| Task / Function     | Description                                          |
|---------------------|------------------------------------------------------|
| `axil_write(addr, data)` | Drive AW + W channels, receive B response      |
| `axil_read(addr, rdata)` | Drive AR channel, capture R channel response   |

Bus parameters match all IPs: `DATA_WIDTH=32`, `ADDR_WIDTH=32`, `ID_WIDTH=4`.

---

## 3. Unit Testbenches

### `tb/mbist_controller/tb_axil_mbist_ctrl_top.v`
Tests the MBIST Controller IP in isolation with a behavioral DCCM model driven over the DMA AXI4-64 master port.

| Test Group | Coverage |
|---|---|
| CSR readback | `MBIST_ALGO_SEL`, `MBIST_ADDR_START`, `MBIST_ADDR_END` write/read |
| Busy/done handshake | `mbist_busy` asserts on start, `mbist_done` sets on completion |
| W1C | `mbist_done` cleared by writing `1` |
| Checkerboard scan | Small window (128 B) and full DCCM (8 KB) — PASS expected |
| March C- scan | Small window and full DCCM — PASS expected |
| Fault injection | DMA read returns corrupt data → `mbist_pass_fail=1`, `mbist_fault_addr` captures address |
| SLVERR | DMA `RRESP=2'b10` → fault recorded |

Run command:
```bash
./run/run_ip.sh mbist
```

---

### `tb/ecc_monitor/tb_axil_ecc_monitor_top.v`
Tests the ECC Monitor IP. The MBIST Controller is also instantiated to exercise the `mbist_busy` / scan-window correlation path.

| Test Group | Coverage |
|---|---|
| Shadow register R/W | `ECC_SHADOW_COUNT`, `ECC_SHADOW_THRESH` |
| Disabled suppression | Events ignored when `ECC_ENABLE=0` |
| Correctable-seen flag | `ECC_STATUS[0]` sets on `ECC_EVENT` write with monitor enabled |
| Correlation (idle) | `ECC_STATUS[1]` stays clear when no MBIST scan is active |
| Correlation (active scan) | `ECC_STATUS[1]` sets when `ECC_EVENT` arrives during MBIST scan; `ECC_SUSPECT_ADDR` captures window address |
| W1C | `ECC_EVENT` reads back `0` after write |

Run command:
```bash
./run/run_ip.sh ecc
```

---

### `tb/watchdog_timer/tb_axil_wdt_top.v`
Tests the Watchdog Timer IP.

| Test Group | Coverage |
|---|---|
| Enable/disable | `WDG_ENABLE` starts/stops countdown |
| Load + countdown | `WDG_LOAD` sets value; `WDG_COUNT` decrements each clock |
| Kick (service) | Writing `WDG_KICK` reloads counter; no timeout |
| Timeout | Counter reaches zero → `WDG_STATUS[0]` sets, `wdt_reset_n` asserts |
| Pre-timeout | `WDG_PRETIMEOUT` threshold triggers interrupt before reset |
| Status W1C | `WDG_STATUS` cleared by writing `1` |

Run command:
```bash
./run/run_ip.sh watchdog
```

---

### `tb/system_timer/tb_axil_systimer_top.v`
Tests the System Timer IP.

| Test Group | Coverage |
|---|---|
| Enable/disable | `TMR_EN` starts/stops counter |
| Reload value | `TMR_RELOAD` sets the rollover value |
| Countdown read | `TMR_COUNT` decrements and wraps |
| Interrupt | `timer_irq` asserts on expiry |

Run command:
```bash
./run/run_ip.sh timer
```

---

### `tb/uart/tb_axil_uart_top.v`
Tests the UART IP with a loopback path (TX wired to RX externally in the TB).

| Test Group | Coverage |
|---|---|
| Baud divisor | `UART_BDIV` write; sampling rate changes |
| LCR config | 8N1, parity modes, stop bits |
| TX with THRE poll | Write `UART_THR`, wait for `LSR[5]` (THRE) |
| TX complete | `LSR[6]` (TEMT) asserts when shift register drains |
| RX loopback | Transmitted byte received in `UART_RBR`; `LSR[0]` (DR) sets |
| TX FIFO depth | 16-entry FIFO fill + drain |

Run command:
```bash
./run/run_ip.sh uart
```

---

### `tb/gpio/tb_axil_gpio_top.v`
Tests the GPIO IP.

| Test Group | Coverage |
|---|---|
| Direction control | `GPIO_DIR` sets pin direction |
| Output drive | `GPIO_OUT` value appears on `gpio_out` pins |
| Input read | External `gpio_in` value readable via `GPIO_IN` (synchronized) |
| Default state | Resets to all-inputs, output register = 0 |

Run command:
```bash
./run/run_ip.sh gpio
```

---

## 4. Full-SoC Testbench — `tb/top/`

### `tb_soc_top.v` (58 KB)
The full-system integration testbench. Instantiates `soc_core_integration` (the VeeR EL2 SoC top) alongside behavioral memory models.

| Component | Role |
|---|---|
| `soc_core_integration` (DUT) | Complete SoC with VeeR EL2 core + all custom IPs |
| `dccm_behavioral_model.v` | DCCM SRAM with SECDED ECC; responds to MBIST DMA AXI4 reads/writes |
| `iccm_behavioral_model.v` | ICCM SRAM; loaded with firmware `.vhx` via `$readmemh` |
| `uart_monitor.v` | Snoops UART TX pin; decodes serial bitstream and prints to console |

Firmware is loaded via `$readmemh` into `iccm_behavioral_model`. The VeeR EL2 core fetches instructions from ICCM at reset vector `0x0004_0000`, executes the firmware test, and all MMIO register reads/writes flow through the AXI4 crossbar to the custom IPs.

UART output from the firmware `uart_print` calls is decoded by `uart_monitor.v` and displayed in the simulation transcript — this is the primary pass/fail mechanism for the full-SoC tests.

---

## 5. Simulation Output Format

All testbenches print structured output. A passing run looks like:

```
====================================================
  TEST SUITE: MBIST Controller
  Processor Core: VeeR EL2 (RV32IMC Bare-Metal)
  Bus Architecture: AXI4 crossbar + AXI4-Lite peripherals
====================================================

[SUBTEST 1] Verifying configuration registers...
  [PASS] mbist_addr_start write/readback
  [PASS] mbist_addr_end write/readback
  ...

====================================================
  TEST SUMMARY REPORT
====================================================
  Total Passed: 14
  Total Failed: 0

>>> ALL TESTS PASSED SUCCESSFULLY! <<<
```

A non-zero exit code or `FAILED` in the transcript indicates a failing test.

---

## 6. Related

| Item | Location |
|---|---|
| Simulation run scripts | `run/README.md` |
| Firmware test sources | `firmware/README.md` |
| RTL IP register maps | `rtl/README.md` |
| `.f` file lists | `run/mbist_ctrl.f`, `run/ecc_monitor.f`, `run/watchdog_timer.f` |
