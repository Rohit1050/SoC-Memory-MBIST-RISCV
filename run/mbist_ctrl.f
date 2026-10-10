// =============================================================================
// Runfile : run/mbist_ctrl.f
// IP      : MBIST Controller (axil_mbist_ctrl_top)
// Tool    : VCS       -> vcs -full64 -sverilog -file run/mbist_ctrl.f
//           ModelSim  -> vlog -f run/mbist_ctrl.f
//           Verilator -> verilator -f run/mbist_ctrl.f --binary --top-module tb_axil_mbist_ctrl_top
// =============================================================================

// ---- Compiler flags ----------------------------------------------------------
+define+SIM
+define+MBIST_CTRL_STANDALONE

// ---- Include search paths ----------------------------------------------------
+incdir+${PRJ_DIR}/rtl/mbist_controller
+incdir+${PRJ_DIR}/tb/common

// ---- RTL sources (bottom-up order) -------------------------------------------
${PRJ_DIR}/rtl/mbist_controller/mbist_algo_engine.v
${PRJ_DIR}/rtl/mbist_controller/mbist_dma_master.v
${PRJ_DIR}/rtl/mbist_controller/axil_mbist_ctrl_top.v

// ---- Testbench ---------------------------------------------------------------
// NOTE: tb_axil_mbist_ctrl_top.v `includes axil_bfm_master.v via +incdir.
${PRJ_DIR}/tb/mbist_controller/tb_axil_mbist_ctrl_top.v
