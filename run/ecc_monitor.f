// =============================================================================
// Runfile : run/ecc_monitor.f
// IP      : ECC Monitor (axil_ecc_monitor_top)
// Tool    : VCS       -> vcs -full64 -sverilog -file run/ecc_monitor.f
//           ModelSim  -> vlog -f run/ecc_monitor.f
//           Verilator -> verilator -f run/ecc_monitor.f --binary --top-module tb_axil_ecc_monitor_top
// =============================================================================

// ---- Compiler flags ----------------------------------------------------------
+define+SIM
+define+ECC_MON_STANDALONE

// ---- Include search paths ----------------------------------------------------
+incdir+${PRJ_DIR}/rtl/ecc_monitor
+incdir+${PRJ_DIR}/tb/common

// ---- RTL sources -------------------------------------------------------------
${PRJ_DIR}/rtl/ecc_monitor/axil_ecc_monitor_top.v

// ---- Testbench ---------------------------------------------------------------
// NOTE: tb_axil_ecc_monitor_top.v `includes axil_bfm_master.v via +incdir.
${PRJ_DIR}/tb/ecc_monitor/tb_axil_ecc_monitor_top.v
