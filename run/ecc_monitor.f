

// Tool    : VCS       -> vcs -file ecc_monitor.f -sverilog
//           ModelSim  -> vlog -f ecc_monitor.f
//           Verilator -> verilator -f ecc_monitor.f --binary --top-module tb_axil_ecc_monitor_top
// =============================================================================

// ---- Compiler flags ----------------------------------------------------------
+define+SIM
+define+ECC_MON_STANDALONE

// ---- Include search paths ----------------------------------------------------
// RTL package / defines header
+incdir+${PRJ_DIR}/rtl/ecc_monitor
// Common TB BFM
+incdir+${PRJ_DIR}/tb/common

// ---- RTL sources (bottom-up order) -------------------------------------------
// ECC Monitor is a single-file IP (no sub-modules)
${PRJ_DIR}/rtl/ecc_monitor/axil_ecc_monitor_top.v

// ---- Testbench ---------------------------------------------------------------
// NOTE: tb_axil_ecc_monitor_top.v `include's axil_bfm_master.v with a repo-root
// relative path. List it here so Verilator sees it as a standalone compile unit; 
// ModelSim/VCS `include will find it via +incdir above.
${PRJ_DIR}/tb/common/axil_bfm_master.v

${PRJ_DIR}/tb/ecc_monitor/tb_axil_ecc_monitor_top.v
