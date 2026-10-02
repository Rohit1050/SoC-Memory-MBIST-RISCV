# ECC Monitor IP — What It Does and Why

## The Problem It Solves

The VeeR EL2 core's DCCM (Data Closely Coupled Memory) has built-in **SECDED ECC**
(Single-Error Correction, Double-Error Detection). Every time the CPU reads a word
from DCCM, the hardware automatically:

- **Corrects** 1-bit errors silently, in-line, before the data reaches the CPU.
- **Detects** (but cannot correct) 2-bit errors, signalling a bus fault.

The problem: **for single-bit corrections, the core records only a running count**
(`mdccmect.count`) — it does not record *which address* was corrected. So if the
count ticks upward, you know *something* in DCCM has a weak cell, but you have no
idea where.

The ECC Monitor bridges that gap by correlating the error count with the MBIST
Controller's active scan window.

---

## How SECDED ECC Works

A standard SECDED code appends **check bits** (parity bits computed from the data
bits) to every word before it is stored. On a read, the hardware recomputes the
check bits and compares them to the stored ones.

```
Write path
──────────
 32-bit data  ──►  ECC encoder  ──►  38-bit codeword stored in DCCM
                                      (32 data + 6 check bits for 32-bit word)

Read path
─────────
 38-bit codeword  ──►  ECC decoder  ──►  syndrome bits
                                              │
                   ┌──────────────────────────┼──────────────────────┐
                   │ syndrome = 0             │ syndrome ≠ 0,        │
                   │ (no error)               │ single-bit pattern   │
                   │                          │ (correctable)        │
                   ▼                          ▼                      │
              data passes              flip the bad bit              │
              through clean            deliver correct data          │
                                       increment mdccmect.count      │
                                                                     │
                                       syndrome ≠ 0, double-bit ────►│
                                       pattern (uncorrectable)       │
                                       signal SLVERR on AXI bus ◄───┘
```

The hardware never exposes the raw corrected-or-not data to firmware — the
correction happens before the load instruction completes. That is why you cannot
distinguish a transient cosmic-ray soft error from a permanently degraded cell just
by reading the data.

---

## What the ECC Monitor Adds

```
                VeeR EL2 Core
               ┌─────────────────────┐
               │  DCCM               │
               │  (SECDED ECC)       │
               │                     │
               │  mdccmect CSR       │──── count field (27-bit) ────┐
               │  ┌───────────────┐  │                               │
               │  │ count [26:0]  │  │                               │  firmware reads
               │  │ thresh [4:0]  │  │                               │  CSR, writes here
               │  └───────────────┘  │                               ▼
               └─────────────────────┘                    ┌──────────────────────┐
                                                           │   ECC Monitor IP     │
                        MBIST Controller                   │                      │
               ┌─────────────────────┐                    │  shadow_count  [R/W] │◄─ firmware
               │  mbist_active       │──────────────────► │  shadow_thresh [R/W] │◄─ firmware
               │  mbist_fault_addr   │──────────────────► │                      │
               └─────────────────────┘                    │  On event write:     │
                                                           │  if enable AND        │
                       Firmware ISR                        │  mbist_active:        │
               ┌─────────────────────┐                    │    latch fault_addr  │
               │ mdccmect fires IRQ  │                    │    set correlated    │
               │ read count, compare │                    │                      │
               │ write event reg ────┼──────────────────► │  suspect_addr  [RO]  │─► localised
               └─────────────────────┘                    │  status        [RO]  │   candidate
                                                           └──────────────────────┘
```

The monitor is **passive** — it has no path to DCCM itself and drives nothing back
to the MBIST Controller or Watchdog Timer. All it does is record correlation state
when firmware tells it an ECC event occurred.

---

## Register Map

| Offset | Register | Access | Description |
|--------|----------|--------|-------------|
| `0x00` | `ecc_mon_enable` | R/W | Master enable. Write 1 before using the monitor. |
| `0x04` | `ecc_mon_shadow_count` | R/W | Firmware copy of `mdccmect.count`. Firmware updates this after each read of the CSR. |
| `0x08` | `ecc_mon_shadow_thresh` | R/W | Firmware copy of `mdccmect.thresh`. Stored for reference. |
| `0x0C` | `ecc_mon_event` | W1C | Firmware writes `1` here to signal that a correctable-error ISR just fired. The hardware never sets this bit; firmware is the only writer. Always reads back `0`. |
| `0x10` | `ecc_mon_suspect_addr` | RO | The MBIST window address that was active at the moment of the last correlated event. Hardware-written only. |
| `0x14` | `ecc_mon_status` | RO | Bit 0: a correctable event has been seen since reset. Bit 1: at least one event was correlated with an active MBIST scan. |

---

## Event-Driven Behaviour (Step by Step)

### Setup (firmware, once at boot)

```
1.  Write ecc_mon_shadow_count  ← current value of mdccmect.count
2.  Write ecc_mon_shadow_thresh ← current value of mdccmect.thresh
3.  Write ecc_mon_enable = 1
```

### Steady state

The MBIST Controller runs autonomously, asserting `mbist_active` while a scan
window is in progress and presenting the window's base address on `mbist_fault_addr`.

### When a correctable-error interrupt fires (firmware ISR)

```
4.  Read mdccmect.count  → new_count
5.  delta = new_count − shadow_count
6.  Write ecc_mon_shadow_count ← new_count       // keep shadow in sync
7.  Write ecc_mon_event = 1                       // trigger correlation
```

### What the hardware does on step 7

```
if (ecc_mon_enable == 1) {
    correctable_seen = 1                          // status bit 0

    if (mbist_active == 1) {
        ecc_mon_suspect_addr = mbist_fault_addr   // latch the window address
        mbist_correlated     = 1                  // status bit 1
    }
}
ecc_mon_event auto-clears to 0                    // W1C: always reads 0
```

### Firmware reads result

```
8.  Read ecc_mon_status
    → bit 1 set?  → "ECC event happened during MBIST scan of window X"
    → bit 1 clear? → "ECC event happened outside any MBIST window — likely transient"

9.  If correlated: read ecc_mon_suspect_addr
    → address of the MBIST window active at the time of the event
    → narrow down the search to that ~word-granular window
```

---

## What Gets Detected and What Doesn't

| Fault type | Detected by | Granularity |
|------------|-------------|-------------|
| **2-bit (uncorrectable)** | MBIST reads SLVERR directly from DMA port | Exact word address |
| **Address-decode fault** | MBIST reads wrong data back → mismatch | Exact word address |
| **1-bit (correctable)** | `mdccmect.count` increment + ECC Monitor correlation | MBIST window granularity (not exact word) |
| **Transient soft error** | Same path as 1-bit, but `mbist_active = 0` at event time | Cannot localise — flagged as unmatched |

> **Why only window granularity for single-bit faults?**
> The DCCM ECC correction happens inside the core's load path, *before* the data
> reaches the MBIST Controller's comparator. The MBIST Controller never sees the
> raw uncorrected bits — so it cannot directly observe the bad cell. The ECC Monitor
> can only say "the error count went up while MBIST was scanning this window," not
> "this specific word is bad." That window is typically a few hundred words wide,
> which still narrows a 128 KB DCCM search considerably.

---

## Integration Checklist

- [ ] `mbist_active_i` ← wire to `axil_mbist_ctrl_top.mbist_active_o`
- [ ] `mbist_fault_addr_tap_i` ← wire to `axil_mbist_ctrl_top.mbist_fault_addr_o`
- [ ] Crossbar port `m05` → AXI4-to-Lite bridge → `axil_ecc_monitor_top`
- [ ] Firmware: enable monitor at boot, hook ISR to write `ecc_mon_event`

---

*Document revision: 1.0 — 2026-10-02*
