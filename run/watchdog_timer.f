// =============================================================================
// Runfile : run/watchdog_timer.f
// IP      : Watchdog Timer (axil_wdt_top)
// Tool    : VCS       -> vcs -full64 -sverilog -file run/watchdog_timer.f
//           ModelSim  -> vlog -f run/watchdog_timer.f
//           Verilator -> verilator -f run/watchdog_timer.f --binary --top-module tb_axil_wdt_top
// =============================================================================

// ---- Compiler flags ----------------------------------------------------------
+define+SIM
+define+WDT_STANDALONE

// ---- Include search paths ----------------------------------------------------
+incdir+${PRJ_DIR}/rtl/watchdog_timer
+incdir+${PRJ_DIR}/tb/common

// ---- RTL sources (bottom-up order) -------------------------------------------
${PRJ_DIR}/rtl/watchdog_timer/wdt_core.v
${PRJ_DIR}/rtl/watchdog_timer/axil_wdt_top.v

// ---- Testbench ---------------------------------------------------------------
// NOTE: tb_axil_wdt_top.v `includes axil_bfm_master.v via +incdir.
${PRJ_DIR}/tb/watchdog_timer/tb_axil_wdt_top.v
