# SoC-Memory-MBIST-RISCV — Firmware & Software Tests

**Project Root:** `SoC-Memory-MBIST-RISCV/`
**Firmware Directory:** `firmware/`
**Target Processor:** CHIPS Alliance VeeR EL2 (RV32IMC, bare-metal)
**Toolchain:** `riscv32-unknown-elf-gcc` or `riscv64-unknown-elf-gcc` (multi-lib, `-march=rv32imc -mabi=ilp32`)

---

## 1. Firmware Architecture Overview

```
          crt0.s  +  test/<test_name>.c
                       │
                       ▼
    riscv32-unknown-elf-gcc  (-march=rv32imc -mabi=ilp32)
                       │
                       ▼
             <test_name>.elf   (linked via link.ld)
                       │
          ┌────────────┼────────────┐
          ▼            ▼            ▼
       .bin          .hex          .vhx  (Verilog HEX for $readmemh)
                                    │
                                    ▼  ($readmemh backdoor load)
                          tb/top/tb_soc_top.v
                                    │
                                    ▼
                          ICCM  (0x0004_0000, 16 KB)
                                    │
                                    ▼
                          VeeR EL2  (RV32IMC)
                                    │  (LSU → AXI4 crossbar)
                                    ▼
                          AXI4 Crossbar + AXI4-Lite Bridge
                                    │
       ┌──────┬───────┬─────────────┼──────────┬──────────┐
       ▼      ▼       ▼             ▼          ▼          ▼
     UART  SysTmr   GPIO        MBIST Ctrl  ECC Mon    WDT
  0x4000  0x4000  0x4000        0x4000      0x4000   0x4000
  _0000   _1000   _2000         _3000       _4000    _5000
```

Firmware is **bare-metal** — no OS, no libc, no dynamic allocation. Every peripheral is accessed via memory-mapped `volatile` pointer macros defined in `test/test_common.h`. UART is used as the sole output channel for test results.

---

## 2. Memory Regions (from `link.ld`)

| Region | Base Address  | Size  | Contents                                    |
|--------|---------------|-------|---------------------------------------------|
| ICCM   | `0x0004_0000` | 16 KB | `.text`, `.rodata` — executable code        |
| DCCM   | `0x0008_2000` | 8 KB  | `.data`, `.bss`, stack (top = `0x0008_4000`)|

The linker script places code in ICCM and data in DCCM. `crt0.s` copies the `.data` section from its load address in ICCM to its runtime address in DCCM before calling `main`.

---

## 3. Startup Sequence (`crt0.s`)

```
_start:
  1. Set stack pointer → _stack_top  (top of DCCM = 0x0008_4000)
  2. Copy .data from ICCM (LMA) → DCCM (VMA)
  3. Zero-fill .bss
  4. call main
  5. wfi / infinite loop  (halt on return)
```

---

## 4. Peripheral Register Macros (`test/test_common.h`)

All peripheral registers are accessed through macros. The full set is listed below.

### UART — `0x4000_0000`

| Macro        | Offset | Access | Description                     |
|--------------|--------|--------|---------------------------------|
| `UART_THR`   | `+0x00`| W      | TX Holding Register             |
| `UART_RBR`   | `+0x00`| R      | RX Buffer Register              |
| `UART_IER`   | `+0x04`| R/W    | Interrupt Enable Register       |
| `UART_BDIV`  | `+0x08`| W      | Baud Divisor (default: 434 → 115 200 bps @ 50 MHz) |
| `UART_LCR`   | `+0x0C`| R/W    | Line Control (`0x03` = 8N1)     |
| `UART_LSR`   | `+0x14`| R      | Line Status (`[5]` = THRE, `[6]` = TEMT) |

### System Timer — `0x4000_1000`

| Macro        | Offset | Access | Description                     |
|--------------|--------|--------|---------------------------------|
| `TMR_EN`     | `+0x00`| R/W    | Enable (`[0]`)                  |
| `TMR_RELOAD` | `+0x04`| R/W    | Reload value                    |
| `TMR_COUNT`  | `+0x08`| RO     | Current counter value           |

### GPIO — `0x4000_2000`

| Macro      | Offset | Access | Description                       |
|------------|--------|--------|-----------------------------------|
| `GPIO_DIR` | `+0x00`| R/W    | Direction (`1` = output)          |
| `GPIO_OUT` | `+0x04`| R/W    | Output register                   |
| `GPIO_IN`  | `+0x08`| RO     | Input register (synchronized)     |

### MBIST Controller — `0x4000_3000`

| Macro              | Offset | Access | Description                              |
|--------------------|--------|--------|------------------------------------------|
| `MBIST_START`      | `+0x00`| W      | Write `1` to launch scan (self-clearing) |
| `MBIST_ALGO_SEL`   | `+0x04`| R/W    | `0` = Checkerboard, `1` = March C-       |
| `MBIST_ADDR_START` | `+0x08`| R/W    | DCCM scan window start address           |
| `MBIST_ADDR_END`   | `+0x0C`| R/W    | DCCM scan window end address             |
| `MBIST_BUSY`       | `+0x10`| RO     | `1` while scan is running                |
| `MBIST_DONE`       | `+0x14`| RO/W1C | `1` when scan complete; write `1` to clear|
| `MBIST_PASS_FAIL`  | `+0x18`| RO     | `0` = PASS, `1` = FAIL                  |
| `MBIST_FAULT_ADDR` | `+0x1C`| RO     | Address of first detected fault          |
| `MBIST_FAULT_COUNT`| `+0x20`| RO     | Count of detected faults (16-bit)        |

### ECC Monitor — `0x4000_4000`

| Macro              | Offset | Access | Description                                         |
|--------------------|--------|--------|-----------------------------------------------------|
| `ECC_ENABLE`       | `+0x00`| R/W    | Monitor enable (`[0]`)                              |
| `ECC_SHADOW_COUNT` | `+0x04`| R/W    | Shadow copy of `mdccmect` (written by firmware)     |
| `ECC_SHADOW_THRESH`| `+0x08`| R/W    | Threshold delta to declare an ECC event (5-bit)     |
| `ECC_EVENT`        | `+0x0C`| W1C    | Write `1` to signal a correctable-error event       |
| `ECC_SUSPECT_ADDR` | `+0x10`| RO     | Latched MBIST scan address at time of event         |
| `ECC_STATUS`       | `+0x14`| RO     | `[0]` = correctable_seen, `[1]` = mbist_correlated  |

### Watchdog Timer — `0x4000_5000`

| Macro           | Offset | Access | Description                                |
|-----------------|--------|--------|--------------------------------------------|
| `WDG_ENABLE`    | `+0x00`| R/W    | Enable (`[0]`)                             |
| `WDG_LOAD`      | `+0x04`| R/W    | Countdown reload value                     |
| `WDG_KICK`      | `+0x08`| W      | Write any value to restart countdown       |
| `WDG_COUNT`     | `+0x0C`| RO     | Current countdown value                    |
| `WDG_STATUS`    | `+0x10`| R/W1C  | `[0]` = timeout_occurred                  |
| `WDG_PRETIMEOUT`| `+0x14`| R/W    | Pre-timeout interrupt threshold            |

---

## 5. Firmware Test Suite (`firmware/test/`)

Each test is a self-contained `main()` that runs a series of subtests and reports results over UART using `report_test()` / `test_summary()` from `test_common.h`.

| File              | Tests Covered                                                        |
|-------------------|----------------------------------------------------------------------|
| `test_mbist.c`    | CSR readback, busy/done handshake, W1C, Checkerboard + March C- scans (small + full 8 KB DCCM) |
| `test_ecc.c`      | Shadow register R/W, event suppression when disabled, correctable_seen flag, mbist_correlated flag with concurrent scan, suspect address capture |
| `test_watchdog.c` | Enable/disable, load + countdown read, kick (reload), timeout status flag, pre-timeout threshold |
| `test_uart.c`     | Baud divisor, LCR config, TX (LSR THRE polling), loopback RX, parity modes |
| `test_gpio.c`     | Direction register, output drive, input read, bit-level control      |
| `test_timer.c`    | Enable, reload, countdown, wrap-around / re-arm                      |

### Common Test Utilities (`test_common.h`)

| Function            | Description                                          |
|---------------------|------------------------------------------------------|
| `uart_putc(c)`      | Blocking TX with THRE poll (timeout-safe)            |
| `uart_print(str)`   | Print null-terminated string; `\n` → `\r\n`          |
| `uart_print_hex(v)` | Print 32-bit value as `0xXXXXXXXX`                  |
| `uart_print_dec(v)` | Print 32-bit value as decimal                        |
| `report_test(n, p)` | Print `[PASS]`/`[FAIL]` + name; update global counts |
| `test_header(t)`    | Print decorated banner with title                    |
| `test_summary()`    | Print pass/fail totals and final verdict             |
| `mbist_wait()`      | Poll `MBIST_DONE` until set or timeout               |
| `mbist_run(a,s,e)`  | Configure + launch MBIST scan, wait for completion   |
| `delay(n)`          | Spin-loop delay via `nop`                            |

### MBIST Scan Constants

| Constant    | Value         | Meaning                            |
|-------------|---------------|------------------------------------|
| `DCCM_BASE` | `0x0008_0000` | DCCM start                        |
| `DCCM_END`  | `0x0008_3FFF` | DCCM end                          |
| `MB_START`  | `0x0008_0000` | Default scan window start         |
| `MB_END`    | `0x0008_1FF8` | Default scan window end (8 KB)    |
| `MB_SM_END` | `0x0008_0078` | Small scan window end (first 128 B)|
| `ALGO_CB`   | `0x0`         | Checkerboard algorithm select     |
| `ALGO_MC`   | `0x1`         | March C- algorithm select         |

---

## 6. Other Firmware Files

| File                | Purpose                                                              |
|---------------------|----------------------------------------------------------------------|
| `crt0.s`            | RISC-V startup: stack init, `.data` copy, `.bss` zero, jump to `main` |
| `link.ld`           | Linker script: ICCM (text) + DCCM (data/bss/stack)                  |
| `defines.h`         | VeeR EL2 auto-generated config macros (DCCM size, ECC params, etc.) |
| `el2_param.vh`      | VeeR EL2 RTL parameter header (used by core, not firmware directly)  |
| `el2_pdef.vh`       | VeeR EL2 RTL `define header                                          |
| `common_defines.vh` | Shared RTL/firmware defines                                          |
| `pd_defines.vh`     | PD (physical design) overrides                                       |
| `pic_map_auto.svh`  | Auto-generated PIC interrupt map                                     |
| `perl_configs.pl`   | VeeR EL2 configuration script (used by core generator)              |
| `whisper.json`      | Configuration for WD Whisper ISS (instruction-set simulator)        |

---

## 7. Build Instructions

No Makefile is committed yet — the project is at RTL architecture specification stage. When a Makefile is added, the expected targets are:

```bash
cd firmware/

# Compile a test (example: MBIST test)
riscv32-unknown-elf-gcc \
  -march=rv32imc -mabi=ilp32 \
  -nostartfiles -nostdlib \
  -T link.ld \
  crt0.s test/test_mbist.c \
  -o test_mbist.elf

# Generate Verilog HEX for $readmemh simulation loading
riscv32-unknown-elf-objcopy -O verilog test_mbist.elf test_mbist.vhx

# Generate flat binary
riscv32-unknown-elf-objcopy -O binary test_mbist.elf test_mbist.bin

# Generate disassembly for debug
riscv32-unknown-elf-objdump -d test_mbist.elf > test_mbist.dump

# Check memory footprint (must fit in 16 KB ICCM + 8 KB DCCM)
riscv32-unknown-elf-size test_mbist.elf
```

To run in simulation, set `PRJ_DIR` and use `run/run_ip.sh` or the top-level TB (`tb/top/tb_soc_top.v`).

---

## 8. Related Documentation

| Document | Location |
|---|---|
| Full architecture + register maps | `doc/HC_Project_Complete_Documentation_v3.pdf` |
| MBIST Controller register spec | `doc/mbist_controller.md` |
| ECC Monitor register spec | `doc/ecc_monitor.md` |
| Watchdog Timer register spec | `doc/watchdog_timer.md` |
| RTL IP overview | `rtl/README.md` |
| Simulation & run scripts | `run/README.md` |
| Testbenches | `tb/README.md` |
