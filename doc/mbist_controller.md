# MBIST Controller IP — What It Does and Why

## The Problem It Solves

Embedded memories (such as SRAMs) represent the highest transistor density and most defect-prone structures on modern SoCs. Once a chip is packaged and deployed in the field, traditional logic scan chains cannot test closely-coupled memories like the VeeR EL2 core's DCCM (Data Closely-Coupled Memory).

Furthermore, while the VeeR EL2 DCCM has built-in SECDED ECC, the core's hardware silently corrects single-bit errors without recording the failing address. If a memory cell is degrading (developing into a permanent hard fault), firmware has no visibility into where the fault is located.

The **Memory Built-In Self-Test (MBIST) Controller** solves these problems by providing:
1. **Autonomous, CPU-Independent Testing**: Injects and reads back deterministic structural test patterns into DCCM via the core's 64-bit DMA Slave Port without consuming CPU load/store pipeline slots.
2. **Comprehensive Fault Coverage**: Implements **Checkerboard** (stuck-at-0 and stuck-at-1 faults) and **March C-** (stuck-at, transition, address-decode, and cell-coupling faults).
3. **Hardware Correlation with ECC Monitor**: Continuously broadcasts `mbist_active` and `mbist_fault_addr_tap` so the ECC Monitor can localize single-bit correctable errors to the active test window.
4. **Direct Detection of Hard & Multi-Bit Faults**: Captures double-bit uncorrectable faults (`RRESP = 2'b10 SLVERR`) and data mismatches, recording the exact failing address and fault count.

---

## Dual-Personality Architecture

The MBIST Controller incorporates two distinct AMBA interfaces:

1. **32-bit AXI4-Lite Slave Interface (CSR Port)**:
   - Base Address: `0x4000_3000` (4 KB window, crossbar port `m04`).
   - Allows firmware or the System Timer to configure test bounds, select algorithms, trigger runs, and inspect fault diagnostic registers.
2. **64-bit Full AXI4 Master Interface (DMA Port)**:
   - Connects to the VeeR EL2 **DMA Slave Port** (crossbar slave `s03`).
   - Generates full 64-bit aligned write bursts (`WSTRB = 8'hFF`) to overwrite data and ECC bits cleanly without triggering read-modify-write cycles.
   - Reads back 64-bit words, compares them against expected patterns, and checks the bus response (`RRESP`).

```
                    ┌─────────────────────────┐
                    │     VeeR EL2 Core       │
                    │                         │
                    │   DMA Slave Port (64b)  │◄────────────┐
                    └───────────┬─────────────┘             │
                                │                           │
                       AXI4 Interconnect                    │
                                │                           │
                 m04 (0x4000_3000)                          │
                                │ (AXI4-Lite)               │ 64-bit AXI4
                                ▼                           │ Master DMA
                    ┌────────────────────────┐              │
                    │  axil_mbist_ctrl_top   │──────────────┘
                    │                        │
                    │  CSR Slave Interface   │
                    │  mbist_algo_engine     │
                    │  mbist_dma_master      │
                    └─────┬────────────┬─────┘
                          │            │
             mbist_active │            │ mbist_irq_done
      mbist_fault_addr_tap│            │ (to PIC)
                          ▼            ▼
                    ┌──────────┐ ┌──────────┐
                    │   ECC    │ │   PIC    │
                    │ Monitor  │ │ Interrupt│
                    └──────────┘ └──────────┘
```

---

## Test Algorithms

### 1. Checkerboard (`mbist_algo_sel = 2'b00`)
- Alternates `64'h5555_5555_5555_5555` and `64'hAAAA_AAAA_AAAA_AAAA` based on address bit 3.
- Executes 4 phases:
  - **Phase 1**: Ascending write pattern 1.
  - **Phase 2**: Ascending read and verify pattern 1.
  - **Phase 3**: Ascending write inverted pattern 2.
  - **Phase 4**: Ascending read and verify inverted pattern 2.
- Detects stuck-at-0 and stuck-at-1 faults rapidly.

### 2. March C- (`mbist_algo_sel = 2'b01`)
- Standard 6-element march sequence with $10N$ operations ($N = \text{number of 64-bit doublewords}$):
  - **M0**: $\Uparrow \{w0\}$ — Ascending write `0x0000_0000_0000_0000` to all addresses.
  - **M1**: $\Uparrow \{r0, w1\}$ — Ascending read `0x0`, verify; then write `0xFFFF_FFFF_FFFF_FFFF`.
  - **M2**: $\Uparrow \{r1, w0\}$ — Ascending read `0x1`, verify; then write `0x0000_0000_0000_0000`.
  - **M3**: $\Downarrow \{r0, w1\}$ — Descending read `0x0`, verify; then write `0xFFFF_FFFF_FFFF_FFFF`.
  - **M4**: $\Downarrow \{r1, w0\}$ — Descending read `0x1`, verify; then write `0x0000_0000_0000_0000`.
  - **M5**: $\Uparrow \{r0\}$ — Ascending read `0x0`, verify.
- Provides production-grade coverage for stuck-at, transition, address-decoder, and coupling faults.

---

## Register Map

Base address: **`0x4000_3000`**, Window: **4 KB** (`0x4000_3000` – `0x4000_3FFF`).

| Offset | Word Index | Register Name | Access | Reset | Description |
|---|---|---|---|---|---|
| `0x000` | `4'h0` | `mbist_start` | W | — | Write `1` to trigger self-test. Auto-clearing pulse. |
| `0x004` | `4'h1` | `mbist_algo_sel` | R/W | `2'b01` | Algorithm select: `2'b00` = Checkerboard, `2'b01` = March C-. |
| `0x008` | `4'h2` | `mbist_addr_start` | R/W | `0x0008_0000` | Start address of DCCM region to test (64-bit aligned). |
| `0x00C` | `4'h3` | `mbist_addr_end` | R/W | `0x0009_FFF8` | End address of DCCM region to test (inclusive, 64-bit aligned). |
| `0x010` | `4'h4` | `mbist_busy` | RO | `0x0` | Set while self-test scan is running. |
| `0x014` | `4'h5` | `mbist_done` | RO / W1C | `0x0` | Set when scan completes. Cleared on new start or writing `1`. |
| `0x018` | `4'h6` | `mbist_pass_fail` | RO | `0x0` | `0` = PASS, `1` = Directly-detected fault present. |
| `0x01C` | `4'h7` | `mbist_fault_addr` | RO | `0x0` | Address of the first directly-detected fault. |
| `0x020` | `4'h8` | `mbist_fault_count`| RO | `0x0` | 16-bit count of directly-detected faults. |
| `0x024`–`0xFFC` | — | *(undefined)* | — | — | Accesses return `SLVERR`. |

---

## Direct vs. Indirect Fault Detection

| Fault Type | How It Is Detected | Granularity | Recorded In |
|---|---|---|---|
| **Double-Bit Uncorrectable ECC Error** | DMA read returns `RRESP = 2'b10 (SLVERR)` | Exact 64-bit word | `mbist_fault_addr`, `mbist_pass_fail=1` |
| **Address-Decode / Multi-Bit Fault** | DMA read data does not match expected pattern | Exact 64-bit word | `mbist_fault_addr`, `mbist_pass_fail=1` |
| **Single-Bit Correctable Error** | In-line core ECC corrects data before read returns; CPU `mdccmect` increments; ECC Monitor correlates with `mbist_fault_addr_tap` | MBIST test window | `ecc_mon_suspect_addr`, `mbist_correlated=1` |

---

## Operational Flow

### 1. Software Configuration & Launch
```c
// Configure test bounds: DCCM 128 KB (0x0008_0000 to 0x0009_FFF8)
*(volatile uint32_t *)(0x40003008) = 0x00080000;
*(volatile uint32_t *)(0x4000300C) = 0x0009FFF8;

// Select March C- algorithm
*(volatile uint32_t *)(0x40003004) = 0x1;

// Trigger self-test
*(volatile uint32_t *)(0x40003000) = 0x1;
```

### 2. Autonomous Scan Execution
- `mbist_busy` asserts; `mbist_active_o` signals the ECC Monitor and Watchdog Timer.
- `mbist_dma_master` sweeps through DCCM using 64-bit AXI4 read and write transactions.
- During every operation, `mbist_fault_addr_tap_o` exposes the current address.

### 3. Completion and Reporting
- Scan finishes: `mbist_busy` de-asserts, `mbist_done` asserts, and `mbist_irq_done_o` pulses to trigger the PIC interrupt.
- Firmware ISR reads `mbist_pass_fail`, `mbist_fault_addr`, and `mbist_fault_count`.
- Firmware formats results and reports status over UART and GPIO LEDs.

---

## Integration Checklist

- [x] **Top Module:** [`rtl/mbist_controller/axil_mbist_ctrl_top.v`](file:///home/rohit/SoC-Memory-MBIST-RISCV/rtl/mbist_controller/axil_mbist_ctrl_top.v)
- [x] **Algorithm Sequencer:** [`rtl/mbist_controller/mbist_algo_engine.v`](file:///home/rohit/SoC-Memory-MBIST-RISCV/rtl/mbist_controller/mbist_algo_engine.v)
- [x] **64-bit AXI4 Master:** [`rtl/mbist_controller/mbist_dma_master.v`](file:///home/rohit/SoC-Memory-MBIST-RISCV/rtl/mbist_controller/mbist_dma_master.v)
- [x] **Defines Header:** [`rtl/mbist_controller/axil_mbist_defines.vh`](file:///home/rohit/SoC-Memory-MBIST-RISCV/rtl/mbist_controller/axil_mbist_defines.vh)
- [x] **Unit Testbench:** [`tb/mbist_controller/tb_axil_mbist_ctrl_top.v`](file:///home/rohit/SoC-Memory-MBIST-RISCV/tb/mbist_controller/tb_axil_mbist_ctrl_top.v) (9 test cases)
- [x] **Crossbar Slave Port:** Mapped to `m04` (`0x4000_3000`) on `axi_interconnect_wrap_4x7`
- [x] **Crossbar Master Port:** Sourced from `s03` driving core DMA Slave Port
- [ ] **ECC Monitor Connection:** Wire `mbist_active_o` $\rightarrow$ `axil_ecc_monitor_top.mbist_active_i`, `mbist_fault_addr_tap_o` $\rightarrow$ `axil_ecc_monitor_top.mbist_fault_addr_tap_i`
- [ ] **PIC Interrupt:** Wire `mbist_irq_done_o` $\rightarrow$ PIC `extintsrc_req`

---

*Document revision: 1.0 — 2026-10-02*
