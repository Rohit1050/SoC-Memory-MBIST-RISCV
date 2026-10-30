# SoC-Memory-MBIST-RISCV — Simulation Run Scripts

**Project Root:** `SoC-Memory-MBIST-RISCV/`
**Run Directory:** `run/`
**Simulator:** Synopsys VCS (primary) — also compatible with ModelSim and Verilator via `.f` filelists

---

## 1. Quick Start

```bash
# From the project root:
export PRJ_DIR=$(pwd)

# Simulate a single IP:
./run/run_ip.sh mbist
./run/run_ip.sh ecc
./run/run_ip.sh watchdog
./run/run_ip.sh timer
./run/run_ip.sh uart
./run/run_ip.sh gpio

# Simulate all IPs in sequence:
./run/run_ip.sh all

# Options (combinable):
./run/run_ip.sh mbist -clean    # delete build dir first
./run/run_ip.sh mbist -gui      # open VCS DVE waveform viewer
./run/run_ip.sh mbist -fsdb     # enable FSDB dumping (Verdi/Novas)
```

---

## 2. Directory Contents

| File                | Purpose                                              |
|---------------------|------------------------------------------------------|
| `run_ip.sh`         | Main simulation launcher for all IP unit tests       |
| `mbist_ctrl.f`      | File list for MBIST Controller simulation            |
| `ecc_monitor.f`     | File list for ECC Monitor simulation                 |
| `watchdog_timer.f`  | File list for Watchdog Timer simulation              |

> **Note:** `uart.f`, `gpio.f`, and `system_timer.f` are referenced by `run_ip.sh` but not yet committed. Create them following the same pattern as the existing `.f` files.

---

## 3. `run_ip.sh` — Detailed Reference

### Environment Setup

`run_ip.sh` auto-configures the VCS environment if `vcs` is not already on `PATH`:

```
VCS_HOME   = /home/student/snps_tools_target/vcs/U-2023.03
VERDI_HOME = /home/student/snps_tools_target/verdi/U-2023.03-SP1
LICENSE    = 27021@14.139.1.126  (SNPSLMD_LICENSE_FILE)
```

Override by exporting `VCS_HOME` before calling the script, or by loading your site's VCS module first.

### IP Name Aliases

| Argument                          | Filelist used         |
|-----------------------------------|-----------------------|
| `uart`                            | `uart.f`              |
| `gpio`                            | `gpio.f`              |
| `timer`, `system_timer`, `systimer` | `system_timer.f`    |
| `watchdog`, `wdt`, `watchdog_timer` | `watchdog_timer.f`  |
| `ecc`, `ecc_mon`, `ecc_monitor`   | `ecc_monitor.f`       |
| `mbist`, `mbist_ctrl`, `mbist_controller` | `mbist_ctrl.f` |
| `all`                             | All six IPs in order  |

### Build Outputs

Each simulation is compiled into `build/<ip_name>_sim/`:

```
build/
└── mbist_sim/
    ├── simv           ← VCS simulation binary
    ├── csrc/          ← VCS intermediate build files
    ├── compile.log    ← Compilation transcript
    └── sim.log        ← Simulation transcript (pass/fail output here)
```

### VCS Compile Flags

```
vcs -full64 -sverilog -notice -timescale=1ns/1ps \
    -file <ip>.f \
    -o build/<ip>_sim/simv \
    -Mdir=build/<ip>_sim/csrc \
    -l build/<ip>_sim/compile.log
```

### Exit Codes

| Code | Meaning                           |
|------|-----------------------------------|
| `0`  | Simulation completed (check log for PASS/FAIL) |
| `1`  | Unknown IP name or missing filelist |
| `≠0` | Simulation binary returned non-zero (test failure) |

---

## 4. Filelist Format (`.f` files)

Each `.f` file follows this structure:

```
// ---- Compiler flags ----------------------------------------------------------
+define+SIM
+define+<IP>_STANDALONE

// ---- Include search paths ----------------------------------------------------
+incdir+${PRJ_DIR}/rtl/<ip_dir>
+incdir+${PRJ_DIR}/tb/common

// ---- RTL sources (bottom-up dependency order) --------------------------------
${PRJ_DIR}/rtl/<ip_dir>/<submodule>.v
${PRJ_DIR}/rtl/<ip_dir>/<top>.v

// ---- Testbench ---------------------------------------------------------------
${PRJ_DIR}/tb/<ip_dir>/tb_<top>.v
```

`${PRJ_DIR}` is exported by `run_ip.sh` to the project root before invoking VCS.

### Existing Filelists

**`run/mbist_ctrl.f`**
```
+define+SIM  +define+MBIST_CTRL_STANDALONE
+incdir+${PRJ_DIR}/rtl/mbist_controller
+incdir+${PRJ_DIR}/tb/common
${PRJ_DIR}/rtl/mbist_controller/mbist_algo_engine.v
${PRJ_DIR}/rtl/mbist_controller/mbist_dma_master.v
${PRJ_DIR}/rtl/mbist_controller/axil_mbist_ctrl_top.v
${PRJ_DIR}/tb/mbist_controller/tb_axil_mbist_ctrl_top.v
```

**`run/ecc_monitor.f`**
```
+define+SIM  +define+ECC_MON_STANDALONE
+incdir+${PRJ_DIR}/rtl/ecc_monitor
+incdir+${PRJ_DIR}/tb/common
${PRJ_DIR}/rtl/ecc_monitor/axil_ecc_monitor_top.v
${PRJ_DIR}/tb/ecc_monitor/tb_axil_ecc_monitor_top.v
```

**`run/watchdog_timer.f`**
```
+define+SIM  +define+WDT_STANDALONE
+incdir+${PRJ_DIR}/rtl/watchdog_timer
+incdir+${PRJ_DIR}/tb/common
${PRJ_DIR}/rtl/watchdog_timer/wdt_core.v
${PRJ_DIR}/rtl/watchdog_timer/axil_wdt_top.v
${PRJ_DIR}/tb/watchdog_timer/tb_axil_wdt_top.v
```

---

## 5. Alternative Simulators

The `.f` filelists work with other simulators using the same `${PRJ_DIR}` variable:

**ModelSim / Questa:**
```bash
export PRJ_DIR=$(pwd)
vlog -f run/mbist_ctrl.f
vsim -c tb_axil_mbist_ctrl_top -do "run -all; quit"
```

**Verilator:**
```bash
export PRJ_DIR=$(pwd)
verilator -f run/mbist_ctrl.f \
  --binary --top-module tb_axil_mbist_ctrl_top \
  -o build/mbist_verilator/Vtb
./build/mbist_verilator/Vtb
```

---

## 6. Adding a New IP Filelist

To create a filelist for a new IP (e.g., `new_ip`):

1. Create `run/new_ip.f` following the template in Section 4.
2. Add a case entry in `run_ip.sh`'s `resolve_ip()` function:
   ```bash
   new_ip)
       echo "new_ip.f"
       ;;
   ```
3. Add `"new_ip"` to the `ALL_IPS` array in `run_ip.sh` if it should be included in `run_ip.sh all`.

---

## 7. Related

| Item | Location |
|---|---|
| Testbench sources | `tb/README.md` |
| Firmware tests | `firmware/README.md` |
| RTL IP sources | `rtl/README.md` |
| Full SoC top TB | `tb/top/tb_soc_top.v` |
