#!/usr/bin/env bash
# =============================================================================
# Project  : RISC-V VeeR EL2 MBIST SoC
# Script   : run/run_ip.sh
# Purpose  : Compile and simulate a particular IP block using Synopsys VCS
# Usage    : ./run/run_ip.sh <ip_name> [options]
#            e.g.: ./run/run_ip.sh uart
#                  ./run/run_ip.sh gpio
#                  ./run/run_ip.sh timer
#                  ./run/run_ip.sh watchdog
#                  ./run/run_ip.sh ecc
#                  ./run/run_ip.sh mbist
#                  ./run/run_ip.sh all
# Options  :
#            -clean   : Clean build directory before compile
#            -gui     : Launch VCS with GUI / DVE
#            -fsdb    : Enable Novas / FSDB dumping support
# =============================================================================

set -e

# --- 1. Locate Project Root ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PRJ_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# --- 2. Setup Synopsys VCS Environment (if not already loaded) ---
if ! command -v vcs &> /dev/null; then
    export SNPSLMD_LICENSE_FILE="27021@14.139.1.126"
    export VCS_HOME="/home/student/snps_tools_target/vcs/U-2023.03"
    export VERDI_HOME="/home/student/snps_tools_target/verdi/U-2023.03-SP1"
    export PATH="${VCS_HOME}/bin:${VERDI_HOME}/bin:${PATH}"
fi

# Ensure VCS is now available
if ! command -v vcs &> /dev/null; then
    echo "[ERROR] VCS command not found. Please verify VCS_HOME and PATH."
    exit 1
fi

# --- 3. Parse Arguments ---
IP_ARG=""
CLEAN=0
GUI_FLAG=""
FSDB_FLAGS=""

for arg in "$@"; do
    case "$arg" in
        -clean)
            CLEAN=1
            ;;
        -gui)
            GUI_FLAG="-gui"
            ;;
        -fsdb)
            FSDB_FLAGS="-kdb -debug_access+all"
            ;;
        -h|--help)
            echo "Usage: $0 <ip_name> [options]"
            echo "Supported IPs: uart, gpio, timer, watchdog, ecc, mbist, all"
            echo "Options:"
            echo "  -clean  : Delete simulation build directory before running"
            echo "  -gui    : Open VCS interactive GUI"
            echo "  -fsdb   : Enable FSDB dumping support"
            exit 0
            ;;
        *)
            if [ -z "$IP_ARG" ]; then
                IP_ARG="$arg"
            fi
            ;;
    esac
done

if [ -z "$IP_ARG" ]; then
    echo "[ERROR] No IP specified."
    echo "Usage: $0 <uart|gpio|timer|watchdog|ecc|mbist|all> [-clean] [-gui]"
    exit 1
fi

# --- 4. Resolve IP Name to Filelist (.f) ---
resolve_ip() {
    local target="$1"
    case "$target" in
        uart)
            echo "uart.f"
            ;;
        gpio)
            echo "gpio.f"
            ;;
        timer|system_timer|systimer)
            echo "system_timer.f"
            ;;
        watchdog|wdt|watchdog_timer)
            echo "watchdog_timer.f"
            ;;
        ecc|ecc_mon|ecc_monitor)
            echo "ecc_monitor.f"
            ;;
        mbist|mbist_ctrl|mbist_controller)
            echo "mbist_ctrl.f"
            ;;
        *)
            echo ""
            ;;
    esac
}

# --- 5. Execution Function for a Single IP ---
run_single_ip() {
    local ip_key="$1"
    local f_file
    f_file="$(resolve_ip "$ip_key")"

    if [ -z "$f_file" ]; then
        echo "[ERROR] Unknown IP: '$ip_key'"
        echo "Valid options: uart, gpio, timer, watchdog, ecc, mbist"
        return 1
    fi

    local runfile="${PRJ_DIR}/run/${f_file}"
    if [ ! -f "$runfile" ]; then
        echo "[ERROR] Filelist not found: $runfile"
        return 1
    fi

    local build_dir="${PRJ_DIR}/build/${ip_key}_sim"
    if [ "$CLEAN" -eq 1 ]; then
        echo "[INFO] Cleaning ${build_dir}..."
        rm -rf "${build_dir}"
    fi
    mkdir -p "${build_dir}"

    echo "=================================================================="
    echo " [VCS RUN] Testing IP: ${ip_key}"
    echo " Filelist : ${runfile}"
    echo " Build Dir: ${build_dir}"
    echo "=================================================================="

    local vcs_opts="-full64 -sverilog -notice -timescale=1ns/1ps"
    vcs_opts="${vcs_opts} ${GUI_FLAG} ${FSDB_FLAGS}"

    echo "[1/2] Compiling with VCS..."
    vcs ${vcs_opts} \
        -file "${runfile}" \
        -o "${build_dir}/simv" \
        -Mdir="${build_dir}/csrc" \
        -l "${build_dir}/compile.log"

    echo "[2/2] Running simulation..."
    set +e
    (cd "${build_dir}" && ./simv -no_save -l "${build_dir}/sim.log")
    local sim_status=$?
    set -e

    echo "------------------------------------------------------------------"
    if [ $sim_status -eq 0 ]; then
        echo " [RESULT] Simulation completed for ${ip_key}. Check: ${build_dir}/sim.log"
    else
        echo " [RESULT] Simulation FAILED with exit code ${sim_status} for ${ip_key}."
    fi
    echo "=================================================================="
    echo ""
    return $sim_status
}

# --- 6. Main Execution ---
if [ "$IP_ARG" = "all" ]; then
    ALL_IPS=("uart" "gpio" "timer" "watchdog" "ecc" "mbist")
    FAILED_IPS=()
    PASSED_IPS=()

    for ip in "${ALL_IPS[@]}"; do
        if run_single_ip "$ip"; then
            PASSED_IPS+=("$ip")
        else
            FAILED_IPS+=("$ip")
        fi
    done

    echo "=================== SUMMARY OF ALL IPS ==================="
    echo " PASSED: ${PASSED_IPS[*]}"
    if [ ${#FAILED_IPS[@]} -gt 0 ]; then
        echo " FAILED: ${FAILED_IPS[*]}"
        exit 1
    else
        echo " ALL IP SIMULATIONS COMPLETED SUCCESSFULLY!"
        exit 0
    fi
else
    run_single_ip "$IP_ARG"
fi
