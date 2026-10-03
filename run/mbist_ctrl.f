// =============================================================================
// Runfile : tb/mbist_controller/mbist_ctrl.f
// IP      : MBIST Controller (axil_mbist_ctrl_top)
// Tool    : ModelSim  -> vlog -f mbist_ctrl.f
//           Verilator -> verilator -f mbist_ctrl.f --binary --top-module tb_axil_mbist_ctrl_top
// =============================================================================

// ---- Compiler flags ----------------------------------------------------------
+define+SIM                        // generic simulation guard
+define+MBIST_CTRL_STANDALONE      // disable any top-level tie-offs for full SoC

// ---- Include search paths ----------------------------------------------------
// RTL package / defines header
+incdir+../../rtl/mbist_controller
// Common TB BFM (axil_bfm_master.v is `include'd directly inside the TB)
+incdir+../../tb/common

// ---- RTL sources (bottom-up order) -------------------------------------------
// 1. Sub-modules instantiated by the top
../../rtl/mbist_controller/mbist_algo_engine.v
../../rtl/mbist_controller/mbist_dma_master.v

// 2. IP top-level
../../rtl/mbist_controller/axil_mbist_ctrl_top.v

// ---- Testbench ---------------------------------------------------------------
// Common BFM (compiled as a standalone file for Verilator; `include handles it
// for event-driven sims — list here so it appears in the compile unit regardless)
../../tb/common/axil_bfm_master.v

// TB top
tb_axil_mbist_ctrl_top.v
