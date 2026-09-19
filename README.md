# RISC-V (VeeR EL2) Based SoC for Memory Built-In Self-Test and Fault Detection

A RISC-V SoC built around the [VeeR EL2](https://github.com/chipsalliance/Cores-VeeR-EL2) core that autonomously tests its own DCCM for structural memory faults and correlates the results with the core's native SECDED ECC activity — without external test equipment.

## Overview

Embedded memories are among the most defect-prone structures in a modern SoC, and once a device is deployed in the field, conventional logic scan chains can't verify them. The VeeR EL2 core's DCCM has native SECDED ECC with in-line correction of single-bit errors, but per the core's reference manual, **no address is recorded for individual correctable errors — only a running count**. This makes it impossible to tell a transient soft error apart from a developing hard fault at a specific cell.

This project solves both problems with three custom IPs sitting alongside the VeeR EL2 core:

- **MBIST Controller** — runs Checkerboard and March C- test algorithms against DCCM via the core's DMA Slave Port, independent of CPU load/store traffic.
- **ECC Monitor** — a firmware-fed shadow of the core's `mdccmect` correctable-error counter, correlated against the active MBIST scan window to localize suspect addresses.
- **Watchdog Timer** — supervises firmware liveness and forces a system reset if a self-test scan or firmware loop hangs.

Results are reported over **UART** and indicated via **GPIO** LEDs, with a **System Timer** driving periodic, autonomous self-test scheduling.

## Architecture

The SoC standardizes on **AMBA AXI4 / AXI4-Lite** throughout:

- The VeeR EL2 core exposes four 64-bit AXI4 interfaces: **IFU** (instruction fetch), **LSU** (load/store), **Debug** (JTAG), and the **DMA Slave Port**.
- The **MBIST Controller** operates as a 64-bit AXI4 master on the DMA Slave Port to inject/verify test patterns in DCCM directly, and as a 32-bit AXI4-Lite slave for its own control/status registers.
- All other peripherals (UART, System Timer, GPIO, Watchdog Timer, ECC Monitor) are native 32-bit AXI4-Lite slaves behind a unified **AXI4 Crossbar Interconnect**.

```
                    ┌─────────────────────┐
                    │   VeeR EL2 RISC-V   │
                    │   Core (RV32IMC)    │
                    │  IFU / LSU / Debug  │◄── AXI4 Masters
                    │   DMA Slave Port    │◄── AXI4 Slave
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │  AXI4 Interconnect  │
                    │  / Crossbar + Addr  │
                    │      Decoder        │
                    └──────────┬──────────┘
              ┌────────┬───────┼───────┬────────┬────────┐
          ┌───▼──┐ ┌───▼───┐ ┌─▼──┐ ┌──▼───┐ ┌──▼──┐ ┌───▼───┐
          │ UART │ │ Sys   │ │GPIO│ │MBIST │ │ ECC │ │ WDT   │
          │      │ │ Timer │ │    │ │Ctrl  │ │ Mon │ │       │
          └──────┘ └───────┘ └────┘ └───┬──┘ └─────┘ └───────┘
                                         │ (AXI4 master)
                                         ▼
                                  DMA Slave Port → DCCM
```

## Key Design Decisions

- **AXI4 over AHB-Lite**: decoupled Write Address / Write Data channels eliminate the back-to-back write idle-cycle penalty documented in the VeeR EL2 PRM errata, speeding up both CPU stores and MBIST pattern sweeps.
- **No duplication of core ECC hardware**: the ECC Monitor is a passive, firmware-fed observer — it can be removed entirely with zero impact on MBIST or Watchdog functionality.
- **Indirect single-bit fault detection**: because DCCM reads pass through the core's in-line ECC correction before reaching the MBIST Controller, single-bit faults never produce a data mismatch. They're inferred instead from an abnormal rise in the `mdccmect` count while a known MBIST scan window is active. Double-bit (uncorrectable) faults and address-decode faults *are* directly detected via `RRESP = 2'b10 (SLVERR)`.

## Memory Map

| Base Address | Size | Block |
|---|---|---|
| `0x0004_0000` | 128 KB (ex.) | ICCM |
| `0x0008_0000` | 128 KB (ex.) | DCCM (SECDED ECC) |
| `0x4000_0000` | 4 KB | UART |
| `0x4000_1000` | 4 KB | System Timer |
| `0x4000_2000` | 4 KB | GPIO |
| `0x4000_3000` | 4 KB | MBIST Controller |
| `0x4000_4000` | 4 KB | ECC Monitor |
| `0x4000_5000` | 4 KB | Watchdog Timer |

Full signal lists, register maps, and address-decode rules are in the [project documentation](./HC_Project_Complete_Documentation_v3.pdf).

## Repository Structure

```
.
├── rtl/                  # SystemVerilog RTL (core wrapper, interconnect, custom IPs)
│   ├── mbist_controller/
│   ├── ecc_monitor/
│   ├── watchdog_timer/
│   ├── system_timer/
│   ├── uart/
│   └── gpio/
├── fw/                   # C firmware (RV32IMC, boot/init, ISRs, result reporting)
├── tb/                   # Testbenches (unit + full-SoC)
├── docs/                 # Architecture, memory map, verification plan
└── README.md
```
*(Adjust to match your actual repo layout.)*

## Status

This project is currently at the **RTL architecture specification stage** — memory map, register definitions, signal lists, control/data flow, and the verification plan are complete. RTL implementation and simulation results are in progress; see [Limitations and Future Enhancements](./HC_Project_Complete_Documentation_v3.pdf) in the full documentation for known constraints (e.g., single-bit fault localization is window-granular, not word-exact; no ICCM MBIST coverage yet; no physical timing closure).

## Toolchain

| Purpose | Tool |
|---|---|
| RTL Simulation | ModelSim / Verilator |
| Synthesis | Yosys / Synopsys DC / Cadence Genus |
| RISC-V Toolchain | `riscv32-unknown-elf-gcc` (RV32IMC) |
| Core | [CHIPS Alliance VeeR EL2](https://github.com/chipsalliance/Cores-VeeR-EL2) |

## References

- CHIPS Alliance, *RISC-V VeeR EL2 Programmer's Reference Manual*, Rev. 1.4, Dec 2022.
- RISC-V International, *The RISC-V Instruction Set Manual, Volumes I & II*.
- ARM Limited, *AMBA AXI and ACE Protocol Specification (AXI3, AXI4, AXI4-Lite)*, ARM IHI 0022E.
- S. Hamdioui et al., "March Tests for All Static Simple RAM Faults: Theory and Practice," IOLTS 2002.
- A. J. van de Goor, *Testing Semiconductor Memories: Theory and Practice*, Wiley, 1991.

