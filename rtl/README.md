# SoC-Memory-MBIST-RISCV — RTL Directory

**Project Root:** `SoC-Memory-MBIST-RISCV/`
**RTL Directory:** `rtl/`
**Target Processor:** CHIPS Alliance VeeR EL2 (RV32IMC)
**Interconnect Fabric:** AXI4 Crossbar — 4 Masters × 11 Slaves (`axi_interconnect_wrap_4_11`)
**Bus Standard:** AMBA AXI4 (64-bit DMA) / AXI4-Lite (32-bit peripherals)

---

## 1. RTL Architecture Overview

```
          ┌──────────────────────────────────────────┐
          │          VeeR EL2  (RV32IMC)             │
          │  IFU ──AXI4──►┐                          │
          │  LSU ──AXI4──►│◄── DMA Slave (AXI4-64)  │
          │  Debug─AXI4──►│                          │
          └───────────────┼──────────────────────────┘
                          │ (3 AXI4 masters in)
                          ▼
               ┌──────────────────────┐
               │  AXI4 Crossbar       │
               │  axi_interconnect    │
               │  (4M × 11S)          │
               │  + axi4_to_axil_bridge│
               └─────────┬────────────┘
      ┌──────┬───────┬───┴────┬────────┬──────────┐
      ▼      ▼       ▼        ▼        ▼           ▼
    UART  Sys     GPIO    MBIST    ECC          WDT
   (m01) Timer  (m03)   Ctrl     Monitor      (m06)
         (m02)          (m04)    (m05)
                          │
                          │ AXI4-64 master
                          ▼
                    DMA Slave Port → DCCM
```

The crossbar operates at **32-bit AXI4-Lite** on all peripheral slave ports. An `axi4_to_axil_bridge` sits between the crossbar and each peripheral. The MBIST Controller also acts as a **64-bit AXI4 master** directly into the VeeR EL2 DMA Slave Port — this path bypasses the crossbar entirely.

---

## 2. Directory Structure

```
rtl/
├── top/
│   └── soc_core_integration.sv        Top-level SoC integration (76 KB)
│
├── interconnect/
│   └── rtl/
│       ├── axi_interconnect.v          AXI4 crossbar core (4M × N slaves)
│       ├── axi_interconnect_wrap_4_11.v  Configured wrapper: 4M × 11S
│       ├── axi4_to_axil_bridge.v       AXI4 full ↔ AXI4-Lite protocol bridge
│       ├── arbiter.v                   Round-robin arbiter
│       └── priority_encoder.v          Priority encoder utility
│
├── mbist_controller/
│   ├── axil_mbist_ctrl_top.v           MBIST CSR slave + sequencer
│   ├── mbist_algo_engine.v             Checkerboard + March C- engines
│   ├── mbist_dma_master.v              AXI4-64 master → DCCM DMA port
│   └── axil_mbist_defines.vh           Register map + parameters
│
├── ecc_monitor/
│   ├── axil_ecc_monitor_top.v          ECC shadow counter + window correlator
│   ├── tb_axil_ecc_monitor_top.v       ⚠ Misplaced unit TB (belongs in tb/)
│   └── axil_ecc_monitor_defines.vh     Register map + parameters
│
├── watchdog_timer/
│   ├── axil_wdt_top.v                  AXI4-Lite register interface
│   ├── wdt_core.v                      Countdown + reset-force logic
│   └── axil_wdt_defines.vh             Register map + parameters
│
├── system_timer/
│   ├── axil_systimer_top.v             mtime/mtimecmp AXI4-Lite slave
│   └── axil_systimer_defines.vh        Register map + parameters
│
├── UART/
│   ├── axil_uart_top.v                 16550-style UART AXI4-Lite top
│   ├── uart_transmitter.v              TX shift register + baud gen
│   ├── uart_receiver.v                 RX shift register + oversampling
│   ├── uart_controller.v               Control FSM
│   ├── uart_parity_bit_compute.v       Even/odd parity logic
│   ├── axi_internal_fifo.v             16-entry TX and RX FIFOs
│   └── axil_uart_defines.vh            Register map + parameters
│
├── gpio/
│   ├── axil_gpio_top.v                 8-bit GPIO AXI4-Lite slave
│   └── axil_gpio_defines.vh            Register map + parameters
│
├── source/                             ← VeeR EL2 generated config outputs
│
└── Core/
    └── Cores-VeeR-EL2/                 ← Upstream CHIPS Alliance core (read-only)
```

---

## 3. Memory Map — All Peripherals

| Crossbar Port | Base Address    | Size  | Peripheral          |
|---------------|-----------------|-------|---------------------|
| —             | `0x0004_0000`   | 16 KB | ICCM (instruction)  |
| —             | `0x0008_2000`   | 8 KB  | DCCM (data, SECDED) |
| m01           | `0x4000_0000`   | 4 KB  | UART                |
| m02           | `0x4000_1000`   | 4 KB  | System Timer        |
| m03           | `0x4000_2000`   | 4 KB  | GPIO                |
| m04           | `0x4000_3000`   | 4 KB  | MBIST Controller    |
| m05           | `0x4000_4000`   | 4 KB  | ECC Monitor         |
| m06           | `0x4000_5000`   | 4 KB  | Watchdog Timer      |

---

## 4. Key Design Decisions

**AXI4 over AHB-Lite** — Decoupled Write Address / Write Data channels eliminate the back-to-back write idle-cycle penalty in the VeeR EL2 PRM errata. Both CPU stores and MBIST pattern sweeps benefit.

**AXI4-Lite peripheral bus** — All custom IPs are native 32-bit AXI4-Lite slaves. The `axi4_to_axil_bridge` handles the protocol downgrade from the full-AXI4 crossbar transparently.

**MBIST dual-role** — The MBIST Controller is simultaneously a 32-bit AXI4-Lite CSR slave (firmware-visible registers) and a 64-bit AXI4 master (DMA into DCCM). These two ports are independent.

**No ECC hardware duplication** — The ECC Monitor is a passive firmware-fed observer of the `mdccmect` CSR. It adds zero gates to the MBIST or WDT paths and can be removed without impact.

**Single-bit fault inference** — DCCM reads pass through inline SECDED correction before reaching the MBIST read-back path, so single-bit faults never produce a data mismatch. They are inferred from an abnormal rise in `mdccmect` while an MBIST scan window is active. Double-bit and address-decode faults produce `RRESP = SLVERR` and are directly detected.

---

## 5. IP Quick Reference

| IP                 | RTL Files | CSR Regs | AXI Role            | Reset Behaviour         |
|--------------------|-----------|----------|---------------------|-------------------------|
| MBIST Controller   | 3 `.v`    | 9        | Slave + DMA Master  | All regs cleared        |
| ECC Monitor        | 1 `.v`    | 6        | Slave only          | Counter/status cleared  |
| Watchdog Timer     | 2 `.v`    | 6        | Slave only          | Disabled, full reload   |
| System Timer       | 1 `.v`    | 3        | Slave only          | Disabled, counter = 0   |
| UART               | 6 `.v`    | 6        | Slave only          | FIFOs flushed, LCR=0    |
| GPIO               | 1 `.v`    | 3        | Slave only          | DIR=input, OUT=0        |
| Interconnect       | 5 `.v`    | —        | Crossbar (4M×11S)   | All channels idle       |
| Top Integration    | 1 `.sv`   | —        | Wrapper             | Core + periph reset     |

---

## 6. RTL Coding Conventions

- All custom IPs are written in **Verilog-2005** (`.v`). The top-level integration uses **SystemVerilog** (`.sv`).
- Register maps are defined in `*_defines.vh` include files. Never hard-code offsets in RTL.
- AXI4-Lite bus widths: `DATA=32`, `ADDR=32`, `ID=4`, `RESP=2`.
- DMA master bus widths: `DATA=64`, `ADDR=32`, `ID=4`, `STRB=8`.
- All registers are synchronous reset, active-low `aresetn`.
- Write-1-to-Clear (W1C) bits use the mask pattern `reg <= reg & ~(wdata & wmask)`.

---

## 7. Related Documentation

| Document | Location |
|---|---|
| Complete architecture + register maps | `doc/HC_Project_Complete_Documentation_v3.pdf` |
| Design decisions & IP specifications | `doc/01_design_decisions_and_ip_specs.md` |
| MBIST Controller detailed spec | `doc/mbist_controller.md` |
| ECC Monitor detailed spec | `doc/ecc_monitor.md` |
| Watchdog Timer detailed spec | `doc/watchdog_timer.md` |
| SoC memory map (visual) | `doc/memory_map_soc - Sheet1.pdf` |
| VeeR EL2 upstream core | `rtl/Core/Cores-VeeR-EL2/README.md` |
