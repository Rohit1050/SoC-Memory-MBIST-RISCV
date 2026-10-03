// =============================================================================
// Runfile : tb/watchdog_timer/watchdog_timer.f
// IP      : Watchdog Timer (axil_wdt_top)
// Tool    : ModelSim  -> vlog -f watchdog_timer.f
//           Verilator -> verilator -f watchdog_timer.f --binary --top-module tb_axil_wdt_top
// =============================================================================

// ---- Compiler flags ----------------------------------------------------------
+define+SIM
+define+WDT_STANDALONE

// ---- Include search paths ----------------------------------------------------
// RTL package / defines header
+incdir+../../rtl/watchdog_timer
// Common TB BFM
+incdir+../../tb/common

// ---- RTL sources (bottom-up order) -------------------------------------------
// 1. Functional core (no AXI-Lite wrapper)
../../rtl/watchdog_timer/wdt_core.v

// 2. AXI-Lite wrapper / IP top-level
../../rtl/watchdog_timer/axil_wdt_top.v

// ---- Testbench ---------------------------------------------------------------
../../tb/common/axil_bfm_master.v

tb_axil_wdt_top.v
