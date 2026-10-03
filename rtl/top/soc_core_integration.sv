/* =============================================================================
 * Project        : RISC-V SoC / MBIST  —  Core Integration Layer
 * File           : soc_core_integration.sv
 * Module         : soc_core_integration
 * Language       : SystemVerilog (required: el2_veer_wrapper uses SV interfaces)
 *
 * Description    : Wires the VeeR EL2 core (el2_veer_wrapper) to the
 *                  axi_interconnect_wrap_4x7 crossbar and the MBIST Controller's
 *                  64-bit AXI4 DMA master (axil_mbist_ctrl_top / mbist_dma_master).
 *
 * What this file DOES:
 *   STEP 1 — Instantiate el2_veer_wrapper (the authoritative core RTL)
 *   STEP 2 — Wire core AXI4 masters (IFU/LSU/sb_axi) to crossbar slave ports
 *             s00/s01/s02
 *   STEP 3 — Wire MBIST Controller DMA master to crossbar slave port s03
 *   STEP 4 — Wire crossbar master port m00 back to the core's DMA Slave Port
 *   STEP 5 — Tie off unused core pins per PRM defaults
 *   STEP 6 — Clock enables and reset
 *   STEP 7 — Scope boundary: m01-m06 (GPIO, Timer, UART, MBIST CSR, ECC Mon,
 *             WDT) are wired in a separate top-level integration step; those
 *             ports are left as outputs/inputs of THIS module.
 *
 * What this file does NOT do:
 *   - Does not wire the AXI4-to-AXI4-Lite bridge or any peripheral behind m01-m06
 *   - Does not modify the core RTL, crossbar, or any peripheral IP
 *
 * Core file      : rtl/Cores-VeeR-EL2/Cores-VeeR-EL2/design/el2_veer_wrapper.sv
 * Crossbar file  : rtl/interconnect/rtl/axi_interconnect_wrap_4_11.v  (renamed wrapper)
 *
 * ─── Port-width audit (critical) ──────────────────────────────────────────────
 * All four *_BUS_TAG parameters in the default veer.config are 4 bits:
 *   LSU_BUS_TAG = 4, IFU_BUS_TAG = 4, SB_BUS_TAG = 4, DMA_BUS_TAG = 4
 * The crossbar has ID_WIDTH = 4.
 * The MBIST DMA master has ID_WIDTH = 4.
 * ✓ NO ID-WIDTH MISMATCH — no padding or truncation required anywhere.
 *
 * PIC_TOTAL_INT = 31 in the default config, so extintsrc_req[31:1] is the
 * full vector. This integration assigns:
 *   extintsrc_req[1] = mbist_irq_done_o   (MBIST scan completion)
 *   extintsrc_req[2] = wdg_irq_pretimeout_o (Watchdog early-warning)
 *   extintsrc_req[31:3] = 32-bit ties: see INTERRUPT RESERVATION TABLE below
 *
 * ─── INTERRUPT RESERVATION TABLE ─────────────────────────────────────────────
 *   Bit 1  : MBIST Controller — mbist_irq_done_o          (ACTIVE)
 *   Bit 2  : Watchdog Timer   — wdg_irq_pretimeout_o      (ACTIVE)
 *   Bit 3  : [reserved] UART RX-data-ready                (future)
 *   Bit 4  : [reserved] ECC Monitor correctable event     (future)
 *   Bit 5  : [reserved] GPIO edge detect                  (future)
 *   Bits 6-31: [reserved] — tied 0 until assigned
 *
 * ─── KNOWN GAPS ───────────────────────────────────────────────────────────────
 * (a) nmi_int is tied LOW.  Per the design spec, double-bit uncorrectable
 *     DCCM ECC errors (dccm_ecc_double_error) should eventually be routed to
 *     nmi_int so the core takes a precise non-maskable trap.  That path has not
 *     been built yet.  The signal is available as an output of this module so
 *     the connection can be made in the next integration pass without modifying
 *     this file — simply OR dccm_ecc_double_error into nmi_int_i at the SoC top.
 *
 * (b) rst_vec is set to 31'h0002_0000 (i.e. address 0x0004_0000), the base of
 *     the 16 KB ICCM window (0x0004_0000–0x0004_3FFF).  This is valid: the
 *     first instruction fetch after reset will target 0x0004_0000 which lies
 *     within the 16 KB ICCM.
 *     Note: the PRM passes rst_vec as bits [31:1]; 0x0004_0000 >> 1 = 31'h0002_0000.
 *
 * ─── Revision History ─────────────────────────────────────────────────────────
 *   Rev | Date       | Description
 *   1.0 | 2026-10-03 | Initial release — core-to-crossbar wiring.
 * =============================================================================*/

`timescale 1ns/1ps

// Pull in VeeR EL2 common defines (required by el2_veer_wrapper)
`include "common_defines.vh"

module soc_core_integration
import el2_pkg::*;
#(
  // ─── Crossbar parameters (frozen, match axi_interconnect_wrap_4x7) ──────────
  parameter XBAR_DATA_WIDTH = 64,
  parameter XBAR_ADDR_WIDTH = 32,
  parameter XBAR_ID_WIDTH   =  4,
  parameter XBAR_STRB_WIDTH = (XBAR_DATA_WIDTH/8),  // 8

  // ─── PIC interrupt vector width ────────────────────────────────────────────
  parameter PIC_TOTAL_INT   = 31   // matches veer.config default
)
(
  // ===========================================================================
  // Clocks and resets (top-level, passed through unchanged)
  // ===========================================================================
  input  logic                          clk_i,         // Single system clock (core + bus)
  input  logic                          rst_l_i,       // Active-low synchronous system reset
  input  logic                          por_rst_l_i,   // Active-low power-on reset (for WDT)
  input  logic                          dbg_rst_l_i,   // Active-low debug reset (exposed for
                                                        // external JTAG controller; wire to
                                                        // rst_l_i for simple bring-up)

  // ===========================================================================
  // JTAG (external pins — never tie off)
  // ===========================================================================
  input  logic                          jtag_tck,
  input  logic                          jtag_tms,
  input  logic                          jtag_tdi,
  input  logic                          jtag_trst_n,
  output logic                          jtag_tdo,
  output logic                          jtag_tdoEn,

  // ===========================================================================
  // Interrupt inputs from peripherals (only two are live today)
  // ===========================================================================
  input  logic                          mbist_irq_done_i,      // from axil_mbist_ctrl_top
  input  logic                          wdg_irq_pretimeout_i,  // from axil_wdt_top

  // ===========================================================================
  // ECC diagnostic outputs (passed out for monitoring / future nmi_int wiring)
  // ===========================================================================
  output logic                          dccm_ecc_single_error_o,
  output logic                          dccm_ecc_double_error_o,  // ← tie to nmi_int in
                                                                    //   next integration pass
  output logic                          iccm_ecc_single_error_o,
  output logic                          iccm_ecc_double_error_o,
  output logic                          dccm_write_readback_error_o,

  // ===========================================================================
  // STEP 7: Crossbar master ports m01-m06 exposed as module I/O for the
  //         next integration pass (peripherals behind AXI4-to-AXI4-Lite bridge)
  //         Naming convention: m<nn>_axi_* matches the crossbar port names.
  // ===========================================================================
  // m01 — UART (0x4000_0000)
  output logic [XBAR_ID_WIDTH-1:0]      m01_axi_awid,
  output logic [XBAR_ADDR_WIDTH-1:0]    m01_axi_awaddr,
  output logic [7:0]                    m01_axi_awlen,
  output logic [2:0]                    m01_axi_awsize,
  output logic [1:0]                    m01_axi_awburst,
  output logic                          m01_axi_awlock,
  output logic [3:0]                    m01_axi_awcache,
  output logic [2:0]                    m01_axi_awprot,
  output logic [3:0]                    m01_axi_awqos,
  output logic [3:0]                    m01_axi_awregion,
  output logic                          m01_axi_awvalid,
  input  logic                          m01_axi_awready,
  output logic [XBAR_DATA_WIDTH-1:0]    m01_axi_wdata,
  output logic [XBAR_STRB_WIDTH-1:0]    m01_axi_wstrb,
  output logic                          m01_axi_wlast,
  output logic                          m01_axi_wvalid,
  input  logic                          m01_axi_wready,
  input  logic [XBAR_ID_WIDTH-1:0]      m01_axi_bid,
  input  logic [1:0]                    m01_axi_bresp,
  input  logic                          m01_axi_bvalid,
  output logic                          m01_axi_bready,
  output logic [XBAR_ID_WIDTH-1:0]      m01_axi_arid,
  output logic [XBAR_ADDR_WIDTH-1:0]    m01_axi_araddr,
  output logic [7:0]                    m01_axi_arlen,
  output logic [2:0]                    m01_axi_arsize,
  output logic [1:0]                    m01_axi_arburst,
  output logic                          m01_axi_arlock,
  output logic [3:0]                    m01_axi_arcache,
  output logic [2:0]                    m01_axi_arprot,
  output logic [3:0]                    m01_axi_arqos,
  output logic [3:0]                    m01_axi_arregion,
  output logic                          m01_axi_arvalid,
  input  logic                          m01_axi_arready,
  input  logic [XBAR_ID_WIDTH-1:0]      m01_axi_rid,
  input  logic [XBAR_DATA_WIDTH-1:0]    m01_axi_rdata,
  input  logic [1:0]                    m01_axi_rresp,
  input  logic                          m01_axi_rlast,
  input  logic                          m01_axi_rvalid,
  output logic                          m01_axi_rready,

  // m02 — System Timer (0x4000_1000)
  output logic [XBAR_ID_WIDTH-1:0]      m02_axi_awid,
  output logic [XBAR_ADDR_WIDTH-1:0]    m02_axi_awaddr,
  output logic [7:0]                    m02_axi_awlen,
  output logic [2:0]                    m02_axi_awsize,
  output logic [1:0]                    m02_axi_awburst,
  output logic                          m02_axi_awlock,
  output logic [3:0]                    m02_axi_awcache,
  output logic [2:0]                    m02_axi_awprot,
  output logic [3:0]                    m02_axi_awqos,
  output logic [3:0]                    m02_axi_awregion,
  output logic                          m02_axi_awvalid,
  input  logic                          m02_axi_awready,
  output logic [XBAR_DATA_WIDTH-1:0]    m02_axi_wdata,
  output logic [XBAR_STRB_WIDTH-1:0]    m02_axi_wstrb,
  output logic                          m02_axi_wlast,
  output logic                          m02_axi_wvalid,
  input  logic                          m02_axi_wready,
  input  logic [XBAR_ID_WIDTH-1:0]      m02_axi_bid,
  input  logic [1:0]                    m02_axi_bresp,
  input  logic                          m02_axi_bvalid,
  output logic                          m02_axi_bready,
  output logic [XBAR_ID_WIDTH-1:0]      m02_axi_arid,
  output logic [XBAR_ADDR_WIDTH-1:0]    m02_axi_araddr,
  output logic [7:0]                    m02_axi_arlen,
  output logic [2:0]                    m02_axi_arsize,
  output logic [1:0]                    m02_axi_arburst,
  output logic                          m02_axi_arlock,
  output logic [3:0]                    m02_axi_arcache,
  output logic [2:0]                    m02_axi_arprot,
  output logic [3:0]                    m02_axi_arqos,
  output logic [3:0]                    m02_axi_arregion,
  output logic                          m02_axi_arvalid,
  input  logic                          m02_axi_arready,
  input  logic [XBAR_ID_WIDTH-1:0]      m02_axi_rid,
  input  logic [XBAR_DATA_WIDTH-1:0]    m02_axi_rdata,
  input  logic [1:0]                    m02_axi_rresp,
  input  logic                          m02_axi_rlast,
  input  logic                          m02_axi_rvalid,
  output logic                          m02_axi_rready,

  // m03 — GPIO (0x4000_2000)
  output logic [XBAR_ID_WIDTH-1:0]      m03_axi_awid,
  output logic [XBAR_ADDR_WIDTH-1:0]    m03_axi_awaddr,
  output logic [7:0]                    m03_axi_awlen,
  output logic [2:0]                    m03_axi_awsize,
  output logic [1:0]                    m03_axi_awburst,
  output logic                          m03_axi_awlock,
  output logic [3:0]                    m03_axi_awcache,
  output logic [2:0]                    m03_axi_awprot,
  output logic [3:0]                    m03_axi_awqos,
  output logic [3:0]                    m03_axi_awregion,
  output logic                          m03_axi_awvalid,
  input  logic                          m03_axi_awready,
  output logic [XBAR_DATA_WIDTH-1:0]    m03_axi_wdata,
  output logic [XBAR_STRB_WIDTH-1:0]    m03_axi_wstrb,
  output logic                          m03_axi_wlast,
  output logic                          m03_axi_wvalid,
  input  logic                          m03_axi_wready,
  input  logic [XBAR_ID_WIDTH-1:0]      m03_axi_bid,
  input  logic [1:0]                    m03_axi_bresp,
  input  logic                          m03_axi_bvalid,
  output logic                          m03_axi_bready,
  output logic [XBAR_ID_WIDTH-1:0]      m03_axi_arid,
  output logic [XBAR_ADDR_WIDTH-1:0]    m03_axi_araddr,
  output logic [7:0]                    m03_axi_arlen,
  output logic [2:0]                    m03_axi_arsize,
  output logic [1:0]                    m03_axi_arburst,
  output logic                          m03_axi_arlock,
  output logic [3:0]                    m03_axi_arcache,
  output logic [2:0]                    m03_axi_arprot,
  output logic [3:0]                    m03_axi_arqos,
  output logic [3:0]                    m03_axi_arregion,
  output logic                          m03_axi_arvalid,
  input  logic                          m03_axi_arready,
  input  logic [XBAR_ID_WIDTH-1:0]      m03_axi_rid,
  input  logic [XBAR_DATA_WIDTH-1:0]    m03_axi_rdata,
  input  logic [1:0]                    m03_axi_rresp,
  input  logic                          m03_axi_rlast,
  input  logic                          m03_axi_rvalid,
  output logic                          m03_axi_rready,

  // m04 — MBIST Controller CSR (0x4000_3000)
  output logic [XBAR_ID_WIDTH-1:0]      m04_axi_awid,
  output logic [XBAR_ADDR_WIDTH-1:0]    m04_axi_awaddr,
  output logic [7:0]                    m04_axi_awlen,
  output logic [2:0]                    m04_axi_awsize,
  output logic [1:0]                    m04_axi_awburst,
  output logic                          m04_axi_awlock,
  output logic [3:0]                    m04_axi_awcache,
  output logic [2:0]                    m04_axi_awprot,
  output logic [3:0]                    m04_axi_awqos,
  output logic [3:0]                    m04_axi_awregion,
  output logic                          m04_axi_awvalid,
  input  logic                          m04_axi_awready,
  output logic [XBAR_DATA_WIDTH-1:0]    m04_axi_wdata,
  output logic [XBAR_STRB_WIDTH-1:0]    m04_axi_wstrb,
  output logic                          m04_axi_wlast,
  output logic                          m04_axi_wvalid,
  input  logic                          m04_axi_wready,
  input  logic [XBAR_ID_WIDTH-1:0]      m04_axi_bid,
  input  logic [1:0]                    m04_axi_bresp,
  input  logic                          m04_axi_bvalid,
  output logic                          m04_axi_bready,
  output logic [XBAR_ID_WIDTH-1:0]      m04_axi_arid,
  output logic [XBAR_ADDR_WIDTH-1:0]    m04_axi_araddr,
  output logic [7:0]                    m04_axi_arlen,
  output logic [2:0]                    m04_axi_arsize,
  output logic [1:0]                    m04_axi_arburst,
  output logic                          m04_axi_arlock,
  output logic [3:0]                    m04_axi_arcache,
  output logic [2:0]                    m04_axi_arprot,
  output logic [3:0]                    m04_axi_arqos,
  output logic [3:0]                    m04_axi_arregion,
  output logic                          m04_axi_arvalid,
  input  logic                          m04_axi_arready,
  input  logic [XBAR_ID_WIDTH-1:0]      m04_axi_rid,
  input  logic [XBAR_DATA_WIDTH-1:0]    m04_axi_rdata,
  input  logic [1:0]                    m04_axi_rresp,
  input  logic                          m04_axi_rlast,
  input  logic                          m04_axi_rvalid,
  output logic                          m04_axi_rready,

  // m05 — ECC Monitor (0x4000_4000)
  output logic [XBAR_ID_WIDTH-1:0]      m05_axi_awid,
  output logic [XBAR_ADDR_WIDTH-1:0]    m05_axi_awaddr,
  output logic [7:0]                    m05_axi_awlen,
  output logic [2:0]                    m05_axi_awsize,
  output logic [1:0]                    m05_axi_awburst,
  output logic                          m05_axi_awlock,
  output logic [3:0]                    m05_axi_awcache,
  output logic [2:0]                    m05_axi_awprot,
  output logic [3:0]                    m05_axi_awqos,
  output logic [3:0]                    m05_axi_awregion,
  output logic                          m05_axi_awvalid,
  input  logic                          m05_axi_awready,
  output logic [XBAR_DATA_WIDTH-1:0]    m05_axi_wdata,
  output logic [XBAR_STRB_WIDTH-1:0]    m05_axi_wstrb,
  output logic                          m05_axi_wlast,
  output logic                          m05_axi_wvalid,
  input  logic                          m05_axi_wready,
  input  logic [XBAR_ID_WIDTH-1:0]      m05_axi_bid,
  input  logic [1:0]                    m05_axi_bresp,
  input  logic                          m05_axi_bvalid,
  output logic                          m05_axi_bready,
  output logic [XBAR_ID_WIDTH-1:0]      m05_axi_arid,
  output logic [XBAR_ADDR_WIDTH-1:0]    m05_axi_araddr,
  output logic [7:0]                    m05_axi_arlen,
  output logic [2:0]                    m05_axi_arsize,
  output logic [1:0]                    m05_axi_arburst,
  output logic                          m05_axi_arlock,
  output logic [3:0]                    m05_axi_arcache,
  output logic [2:0]                    m05_axi_arprot,
  output logic [3:0]                    m05_axi_arqos,
  output logic [3:0]                    m05_axi_arregion,
  output logic                          m05_axi_arvalid,
  input  logic                          m05_axi_arready,
  input  logic [XBAR_ID_WIDTH-1:0]      m05_axi_rid,
  input  logic [XBAR_DATA_WIDTH-1:0]    m05_axi_rdata,
  input  logic [1:0]                    m05_axi_rresp,
  input  logic                          m05_axi_rlast,
  input  logic                          m05_axi_rvalid,
  output logic                          m05_axi_rready,

  // m06 — Watchdog Timer (0x4000_5000)
  output logic [XBAR_ID_WIDTH-1:0]      m06_axi_awid,
  output logic [XBAR_ADDR_WIDTH-1:0]    m06_axi_awaddr,
  output logic [7:0]                    m06_axi_awlen,
  output logic [2:0]                    m06_axi_awsize,
  output logic [1:0]                    m06_axi_awburst,
  output logic                          m06_axi_awlock,
  output logic [3:0]                    m06_axi_awcache,
  output logic [2:0]                    m06_axi_awprot,
  output logic [3:0]                    m06_axi_awqos,
  output logic [3:0]                    m06_axi_awregion,
  output logic                          m06_axi_awvalid,
  input  logic                          m06_axi_awready,
  output logic [XBAR_DATA_WIDTH-1:0]    m06_axi_wdata,
  output logic [XBAR_STRB_WIDTH-1:0]    m06_axi_wstrb,
  output logic                          m06_axi_wlast,
  output logic                          m06_axi_wvalid,
  input  logic                          m06_axi_wready,
  input  logic [XBAR_ID_WIDTH-1:0]      m06_axi_bid,
  input  logic [1:0]                    m06_axi_bresp,
  input  logic                          m06_axi_bvalid,
  output logic                          m06_axi_bready,
  output logic [XBAR_ID_WIDTH-1:0]      m06_axi_arid,
  output logic [XBAR_ADDR_WIDTH-1:0]    m06_axi_araddr,
  output logic [7:0]                    m06_axi_arlen,
  output logic [2:0]                    m06_axi_arsize,
  output logic [1:0]                    m06_axi_arburst,
  output logic                          m06_axi_arlock,
  output logic [3:0]                    m06_axi_arcache,
  output logic [2:0]                    m06_axi_arprot,
  output logic [3:0]                    m06_axi_arqos,
  output logic [3:0]                    m06_axi_arregion,
  output logic                          m06_axi_arvalid,
  input  logic                          m06_axi_arready,
  input  logic [XBAR_ID_WIDTH-1:0]      m06_axi_rid,
  input  logic [XBAR_DATA_WIDTH-1:0]    m06_axi_rdata,
  input  logic [1:0]                    m06_axi_rresp,
  input  logic                          m06_axi_rlast,
  input  logic                          m06_axi_rvalid,
  output logic                          m06_axi_rready,

  // ===========================================================================
  // MBIST Controller sideband outputs (consumed by ECC Monitor, WDT, PIC)
  // ===========================================================================
  output logic                          mbist_active_o,
  output logic [31:0]                   mbist_fault_addr_tap_o,

  // ===========================================================================
  // System Timer tick input (auto-trigger path to MBIST Controller)
  // ===========================================================================
  input  logic                          timer_tick_i,

  // ===========================================================================
  // DMI uncore interface (passed through for external debug controller)
  // ===========================================================================
  input  logic                          dmi_core_enable_i,
  input  logic                          dmi_uncore_enable_i,
  output logic                          dmi_uncore_en_o,
  output logic                          dmi_uncore_wr_en_o,
  output logic [6:0]                    dmi_uncore_addr_o,
  output logic [31:0]                   dmi_uncore_wdata_o,
  input  logic [31:0]                   dmi_uncore_rdata_i,
  output logic                          dmi_active_o
);

  // ===========================================================================
  // ─── Internal wires: IFU AXI4 master (core → crossbar s00) ─────────────────
  // ===========================================================================
  // IFU — 64-bit AXI4 master; ID width = pt.IFU_BUS_TAG = 4
  logic                          ifu_axi_awvalid;
  logic                          ifu_axi_awready;
  logic [3:0]                    ifu_axi_awid;
  logic [31:0]                   ifu_axi_awaddr;
  logic [3:0]                    ifu_axi_awregion;
  logic [7:0]                    ifu_axi_awlen;
  logic [2:0]                    ifu_axi_awsize;
  logic [1:0]                    ifu_axi_awburst;
  logic                          ifu_axi_awlock;
  logic [3:0]                    ifu_axi_awcache;
  logic [2:0]                    ifu_axi_awprot;
  logic [3:0]                    ifu_axi_awqos;
  logic                          ifu_axi_wvalid;
  logic                          ifu_axi_wready;
  logic [63:0]                   ifu_axi_wdata;
  logic [7:0]                    ifu_axi_wstrb;
  logic                          ifu_axi_wlast;
  logic                          ifu_axi_bvalid;
  logic                          ifu_axi_bready;
  logic [1:0]                    ifu_axi_bresp;
  logic [3:0]                    ifu_axi_bid;
  logic                          ifu_axi_arvalid;
  logic                          ifu_axi_arready;
  logic [3:0]                    ifu_axi_arid;
  logic [31:0]                   ifu_axi_araddr;
  logic [3:0]                    ifu_axi_arregion;
  logic [7:0]                    ifu_axi_arlen;
  logic [2:0]                    ifu_axi_arsize;
  logic [1:0]                    ifu_axi_arburst;
  logic                          ifu_axi_arlock;
  logic [3:0]                    ifu_axi_arcache;
  logic [2:0]                    ifu_axi_arprot;
  logic [3:0]                    ifu_axi_arqos;
  logic                          ifu_axi_rvalid;
  logic                          ifu_axi_rready;
  logic [3:0]                    ifu_axi_rid;
  logic [63:0]                   ifu_axi_rdata;
  logic [1:0]                    ifu_axi_rresp;
  logic                          ifu_axi_rlast;

  // ===========================================================================
  // ─── Internal wires: LSU AXI4 master (core → crossbar s01) ─────────────────
  // ===========================================================================
  // LSU — 64-bit AXI4 master; ID width = pt.LSU_BUS_TAG = 4
  logic                          lsu_axi_awvalid;
  logic                          lsu_axi_awready;
  logic [3:0]                    lsu_axi_awid;
  logic [31:0]                   lsu_axi_awaddr;
  logic [3:0]                    lsu_axi_awregion;
  logic [7:0]                    lsu_axi_awlen;
  logic [2:0]                    lsu_axi_awsize;
  logic [1:0]                    lsu_axi_awburst;
  logic                          lsu_axi_awlock;
  logic [3:0]                    lsu_axi_awcache;
  logic [2:0]                    lsu_axi_awprot;
  logic [3:0]                    lsu_axi_awqos;
  logic                          lsu_axi_wvalid;
  logic                          lsu_axi_wready;
  logic [63:0]                   lsu_axi_wdata;
  logic [7:0]                    lsu_axi_wstrb;
  logic                          lsu_axi_wlast;
  logic                          lsu_axi_bvalid;
  logic                          lsu_axi_bready;
  logic [1:0]                    lsu_axi_bresp;
  logic [3:0]                    lsu_axi_bid;
  logic                          lsu_axi_arvalid;
  logic                          lsu_axi_arready;
  logic [3:0]                    lsu_axi_arid;
  logic [31:0]                   lsu_axi_araddr;
  logic [3:0]                    lsu_axi_arregion;
  logic [7:0]                    lsu_axi_arlen;
  logic [2:0]                    lsu_axi_arsize;
  logic [1:0]                    lsu_axi_arburst;
  logic                          lsu_axi_arlock;
  logic [3:0]                    lsu_axi_arcache;
  logic [2:0]                    lsu_axi_arprot;
  logic [3:0]                    lsu_axi_arqos;
  logic                          lsu_axi_rvalid;
  logic                          lsu_axi_rready;
  logic [3:0]                    lsu_axi_rid;
  logic [63:0]                   lsu_axi_rdata;
  logic [1:0]                    lsu_axi_rresp;
  logic                          lsu_axi_rlast;

  // ===========================================================================
  // ─── Internal wires: Debug System Bus (sb_axi) AXI4 master → crossbar s02 ──
  // ===========================================================================
  // SB — 64-bit AXI4 master; ID width = pt.SB_BUS_TAG = 4
  logic                          sb_axi_awvalid;
  logic                          sb_axi_awready;
  logic [3:0]                    sb_axi_awid;
  logic [31:0]                   sb_axi_awaddr;
  logic [3:0]                    sb_axi_awregion;
  logic [7:0]                    sb_axi_awlen;
  logic [2:0]                    sb_axi_awsize;
  logic [1:0]                    sb_axi_awburst;
  logic                          sb_axi_awlock;
  logic [3:0]                    sb_axi_awcache;
  logic [2:0]                    sb_axi_awprot;
  logic [3:0]                    sb_axi_awqos;
  logic                          sb_axi_wvalid;
  logic                          sb_axi_wready;
  logic [63:0]                   sb_axi_wdata;
  logic [7:0]                    sb_axi_wstrb;
  logic                          sb_axi_wlast;
  logic                          sb_axi_bvalid;
  logic                          sb_axi_bready;
  logic [1:0]                    sb_axi_bresp;
  logic [3:0]                    sb_axi_bid;
  logic                          sb_axi_arvalid;
  logic                          sb_axi_arready;
  logic [3:0]                    sb_axi_arid;
  logic [31:0]                   sb_axi_araddr;
  logic [3:0]                    sb_axi_arregion;
  logic [7:0]                    sb_axi_arlen;
  logic [2:0]                    sb_axi_arsize;
  logic [1:0]                    sb_axi_arburst;
  logic                          sb_axi_arlock;
  logic [3:0]                    sb_axi_arcache;
  logic [2:0]                    sb_axi_arprot;
  logic [3:0]                    sb_axi_arqos;
  logic                          sb_axi_rvalid;
  logic                          sb_axi_rready;
  logic [3:0]                    sb_axi_rid;
  logic [63:0]                   sb_axi_rdata;
  logic [1:0]                    sb_axi_rresp;
  logic                          sb_axi_rlast;

  // ===========================================================================
  // ─── Internal wires: DMA Slave Port (core ← crossbar m00 ← s03/MBIST) ──────
  // ===========================================================================
  // DMA — 64-bit AXI4 slave on the core; ID width = pt.DMA_BUS_TAG = 4
  logic                          dma_axi_awvalid;
  logic                          dma_axi_awready;
  logic [3:0]                    dma_axi_awid;
  logic [31:0]                   dma_axi_awaddr;
  logic [2:0]                    dma_axi_awsize;
  logic [2:0]                    dma_axi_awprot;
  logic [7:0]                    dma_axi_awlen;
  logic [1:0]                    dma_axi_awburst;
  logic                          dma_axi_wvalid;
  logic                          dma_axi_wready;
  logic [63:0]                   dma_axi_wdata;
  logic [7:0]                    dma_axi_wstrb;
  logic                          dma_axi_wlast;
  logic                          dma_axi_bvalid;
  logic                          dma_axi_bready;
  logic [1:0]                    dma_axi_bresp;
  logic [3:0]                    dma_axi_bid;
  logic                          dma_axi_arvalid;
  logic                          dma_axi_arready;
  logic [3:0]                    dma_axi_arid;
  logic [31:0]                   dma_axi_araddr;
  logic [2:0]                    dma_axi_arsize;
  logic [2:0]                    dma_axi_arprot;
  logic [7:0]                    dma_axi_arlen;
  logic [1:0]                    dma_axi_arburst;
  logic                          dma_axi_rvalid;
  logic                          dma_axi_rready;
  logic [3:0]                    dma_axi_rid;
  logic [63:0]                   dma_axi_rdata;
  logic [1:0]                    dma_axi_rresp;
  logic                          dma_axi_rlast;

  // ===========================================================================
  // ─── Internal wires: MBIST Controller DMA master (→ crossbar s03) ───────────
  // ===========================================================================
  // mbist_dma_master AXI4 master; ID_WIDTH = 4; DATA_WIDTH = 64; ADDR_WIDTH = 32
  logic                          mbist_m_axi_awvalid;
  logic                          mbist_m_axi_awready;
  logic [3:0]                    mbist_m_axi_awid;
  logic [31:0]                   mbist_m_axi_awaddr;
  logic [7:0]                    mbist_m_axi_awlen;
  logic [2:0]                    mbist_m_axi_awsize;
  logic [1:0]                    mbist_m_axi_awburst;
  logic                          mbist_m_axi_awlock;
  logic [3:0]                    mbist_m_axi_awcache;
  logic [2:0]                    mbist_m_axi_awprot;
  logic [3:0]                    mbist_m_axi_awqos;
  logic                          mbist_m_axi_wvalid;
  logic                          mbist_m_axi_wready;
  logic [63:0]                   mbist_m_axi_wdata;
  logic [7:0]                    mbist_m_axi_wstrb;
  logic                          mbist_m_axi_wlast;
  logic                          mbist_m_axi_bvalid;
  logic                          mbist_m_axi_bready;
  logic [1:0]                    mbist_m_axi_bresp;
  logic [3:0]                    mbist_m_axi_bid;
  logic                          mbist_m_axi_arvalid;
  logic                          mbist_m_axi_arready;
  logic [3:0]                    mbist_m_axi_arid;
  logic [31:0]                   mbist_m_axi_araddr;
  logic [7:0]                    mbist_m_axi_arlen;
  logic [2:0]                    mbist_m_axi_arsize;
  logic [1:0]                    mbist_m_axi_arburst;
  logic                          mbist_m_axi_arlock;
  logic [3:0]                    mbist_m_axi_arcache;
  logic [2:0]                    mbist_m_axi_arprot;
  logic [3:0]                    mbist_m_axi_arqos;
  logic                          mbist_m_axi_rvalid;
  logic                          mbist_m_axi_rready;
  logic [3:0]                    mbist_m_axi_rid;
  logic [63:0]                   mbist_m_axi_rdata;
  logic [1:0]                    mbist_m_axi_rresp;
  logic                          mbist_m_axi_rlast;

  // ===========================================================================
  // ─── el2_mem_if SystemVerilog interface instances ────────────────────────────
  // The VeeR EL2 wrapper uses a packed SV interface to export ICCM/DCCM/ICache
  // SRAM control signals to the integration level where actual SRAM macros live.
  // el2_mem_export carries DCCM + ICCM + ICache bank signals.
  // el2_icache_export carries ICache tag/data specifically.
  // In this integration pass we instantiate the interface objects and forward
  // them. The actual SRAM macro instantiations belong in a future memory
  // subsystem file — the interfaces are exposed here as module-level objects.
  // ===========================================================================
  el2_mem_if  #(`include "el2_param.vh") el2_mem_export  ();
  el2_mem_if  #(`include "el2_param.vh") el2_icache_export();

  // ===========================================================================
  // ─── Interrupt vector assembly ───────────────────────────────────────────────
  // PIC_TOTAL_INT = 31 → extintsrc_req[31:1]
  // ===========================================================================
  logic [PIC_TOTAL_INT:1] extintsrc_req;

  always_comb begin
    extintsrc_req                    = '0;  // default: all inactive
    extintsrc_req[1]                 = mbist_irq_done_i;       // MBIST done
    extintsrc_req[2]                 = wdg_irq_pretimeout_i;   // WDT early-warning
    // Bits 3-5 reserved for future peripheral interrupts (see RESERVATION TABLE)
    // Bits 6-31: reserved, tied 0
  end

  // ===========================================================================
  // STEP 1 + 2 + 4 + 5 + 6
  // ─── el2_veer_wrapper instantiation ─────────────────────────────────────────
  // File : rtl/Cores-VeeR-EL2/Cores-VeeR-EL2/design/el2_veer_wrapper.sv
  // ===========================================================================
  el2_veer_wrapper
  `ifndef RV_SYNTHESIS
    #(`include "el2_param.vh")
  `endif
  u_veer_core (
    // ─── STEP 6: Clock, resets, clock enables ──────────────────────────────
    .clk             (clk_i),
    .rst_l           (rst_l_i),
    .dbg_rst_l       (dbg_rst_l_i),

    // STEP 6: Boot vector — ICCM base 0x0004_0000, passed as [31:1]
    // rst_vec[31:1] = 31'h0002_0000  →  full address = 0x0004_0000
    // Verification: 0x0004_0000 lies in [0x0004_0000, 0x0004_3FFF] — VALID
    .rst_vec         (31'h0002_0000),

    // STEP 5: nmi_int tied LOW — known gap, see header comment (a)
    .nmi_int         (1'b0),

    // nmi_vec and jtag_id are supposed to be tied to constants (PRM pragma)
    .nmi_vec         (31'h0),       // NMI handler not yet assigned
    .jtag_id         (31'h0),       // JTAG ID constant (change for production)

    // STEP 6: clock enables — all 1'b1 for 1:1 core:bus clock ratio
    // Change these to gated enables for power tuning in a later pass.
    .ifu_bus_clk_en  (1'b1),
    .lsu_bus_clk_en  (1'b1),
    .dbg_bus_clk_en  (1'b1),
    .dma_bus_clk_en  (1'b1),

    // ─── STEP 5: tie-offs for unused control pins ──────────────────────────
    // scan_mode: foundry scan test pin — tie low for functional operation
    .scan_mode       (1'b0),
    // mbist_mode: core's own foundry-level structural MBIST pin — DISTINCT
    //   from the custom MBIST Controller IP.  Must remain tied LOW during
    //   normal operation.  The custom MBIST IP uses the DMA Slave Port, not
    //   this pin.
    .mbist_mode      (1'b0),

    // soft_int: software interrupt (RISC-V mip.MSIP) — not used in this design
    .soft_int        (1'b0),
    // timer_int: machine timer interrupt (RISC-V mip.MTIP) — not used here;
    //   the custom System Timer peripheral raises extintsrc_req, not this pin
    .timer_int       (1'b0),

    // core_id[31:4]: upper bits of core ID — tie to 0 for single-core design
    .core_id         (28'h0),

    // MPC debug halt/run interface: no PMU/MPC in this design
    .mpc_debug_halt_req (1'b0),
    .mpc_debug_run_req  (1'b0),
    .mpc_reset_run_req  (1'b0),  // run after reset (1=run, 0=halt on reset)

    // CPU halt/run request from PMU: no PMU in this design
    .i_cpu_halt_req  (1'b0),
    .i_cpu_run_req   (1'b0),

    // DMI uncore interface (passed through to top level)
    .dmi_core_enable   (dmi_core_enable_i),
    .dmi_uncore_enable (dmi_uncore_enable_i),
    .dmi_uncore_en     (dmi_uncore_en_o),
    .dmi_uncore_wr_en  (dmi_uncore_wr_en_o),
    .dmi_uncore_addr   (dmi_uncore_addr_o),
    .dmi_uncore_wdata  (dmi_uncore_wdata_o),
    .dmi_uncore_rdata  (dmi_uncore_rdata_i),
    .dmi_active        (dmi_active_o),

    // ─── STEP 5: JTAG — exposed as top-level I/O (never tie off) ──────────
    .jtag_tck        (jtag_tck),
    .jtag_tms        (jtag_tms),
    .jtag_tdi        (jtag_tdi),
    .jtag_trst_n     (jtag_trst_n),
    .jtag_tdo        (jtag_tdo),
    .jtag_tdoEn      (jtag_tdoEn),

    // ─── Interrupt vector ──────────────────────────────────────────────────
    .extintsrc_req   (extintsrc_req),

    // ─── ECC diagnostic outputs ────────────────────────────────────────────
    .dccm_ecc_single_error        (dccm_ecc_single_error_o),
    .dccm_ecc_double_error        (dccm_ecc_double_error_o),
    .dccm_write_readback_error    (dccm_write_readback_error_o),
    .iccm_ecc_single_error        (iccm_ecc_single_error_o),
    .iccm_ecc_double_error        (iccm_ecc_double_error_o),

    // ─── STEP 2: IFU AXI4 master → crossbar s00 ──────────────────────────
    .ifu_axi_awvalid (ifu_axi_awvalid),
    .ifu_axi_awready (ifu_axi_awready),
    .ifu_axi_awid    (ifu_axi_awid),
    .ifu_axi_awaddr  (ifu_axi_awaddr),
    .ifu_axi_awregion(ifu_axi_awregion),
    .ifu_axi_awlen   (ifu_axi_awlen),
    .ifu_axi_awsize  (ifu_axi_awsize),
    .ifu_axi_awburst (ifu_axi_awburst),
    .ifu_axi_awlock  (ifu_axi_awlock),
    .ifu_axi_awcache (ifu_axi_awcache),
    .ifu_axi_awprot  (ifu_axi_awprot),
    .ifu_axi_awqos   (ifu_axi_awqos),
    .ifu_axi_wvalid  (ifu_axi_wvalid),
    .ifu_axi_wready  (ifu_axi_wready),
    .ifu_axi_wdata   (ifu_axi_wdata),
    .ifu_axi_wstrb   (ifu_axi_wstrb),
    .ifu_axi_wlast   (ifu_axi_wlast),
    .ifu_axi_bvalid  (ifu_axi_bvalid),
    .ifu_axi_bready  (ifu_axi_bready),
    .ifu_axi_bresp   (ifu_axi_bresp),
    .ifu_axi_bid     (ifu_axi_bid),
    .ifu_axi_arvalid (ifu_axi_arvalid),
    .ifu_axi_arready (ifu_axi_arready),
    .ifu_axi_arid    (ifu_axi_arid),
    .ifu_axi_araddr  (ifu_axi_araddr),
    .ifu_axi_arregion(ifu_axi_arregion),
    .ifu_axi_arlen   (ifu_axi_arlen),
    .ifu_axi_arsize  (ifu_axi_arsize),
    .ifu_axi_arburst (ifu_axi_arburst),
    .ifu_axi_arlock  (ifu_axi_arlock),
    .ifu_axi_arcache (ifu_axi_arcache),
    .ifu_axi_arprot  (ifu_axi_arprot),
    .ifu_axi_arqos   (ifu_axi_arqos),
    .ifu_axi_rvalid  (ifu_axi_rvalid),
    .ifu_axi_rready  (ifu_axi_rready),
    .ifu_axi_rid     (ifu_axi_rid),
    .ifu_axi_rdata   (ifu_axi_rdata),
    .ifu_axi_rresp   (ifu_axi_rresp),
    .ifu_axi_rlast   (ifu_axi_rlast),

    // ─── STEP 2: LSU AXI4 master → crossbar s01 ──────────────────────────
    .lsu_axi_awvalid (lsu_axi_awvalid),
    .lsu_axi_awready (lsu_axi_awready),
    .lsu_axi_awid    (lsu_axi_awid),
    .lsu_axi_awaddr  (lsu_axi_awaddr),
    .lsu_axi_awregion(lsu_axi_awregion),
    .lsu_axi_awlen   (lsu_axi_awlen),
    .lsu_axi_awsize  (lsu_axi_awsize),
    .lsu_axi_awburst (lsu_axi_awburst),
    .lsu_axi_awlock  (lsu_axi_awlock),
    .lsu_axi_awcache (lsu_axi_awcache),
    .lsu_axi_awprot  (lsu_axi_awprot),
    .lsu_axi_awqos   (lsu_axi_awqos),
    .lsu_axi_wvalid  (lsu_axi_wvalid),
    .lsu_axi_wready  (lsu_axi_wready),
    .lsu_axi_wdata   (lsu_axi_wdata),
    .lsu_axi_wstrb   (lsu_axi_wstrb),
    .lsu_axi_wlast   (lsu_axi_wlast),
    .lsu_axi_bvalid  (lsu_axi_bvalid),
    .lsu_axi_bready  (lsu_axi_bready),
    .lsu_axi_bresp   (lsu_axi_bresp),
    .lsu_axi_bid     (lsu_axi_bid),
    .lsu_axi_arvalid (lsu_axi_arvalid),
    .lsu_axi_arready (lsu_axi_arready),
    .lsu_axi_arid    (lsu_axi_arid),
    .lsu_axi_araddr  (lsu_axi_araddr),
    .lsu_axi_arregion(lsu_axi_arregion),
    .lsu_axi_arlen   (lsu_axi_arlen),
    .lsu_axi_arsize  (lsu_axi_arsize),
    .lsu_axi_arburst (lsu_axi_arburst),
    .lsu_axi_arlock  (lsu_axi_arlock),
    .lsu_axi_arcache (lsu_axi_arcache),
    .lsu_axi_arprot  (lsu_axi_arprot),
    .lsu_axi_arqos   (lsu_axi_arqos),
    .lsu_axi_rvalid  (lsu_axi_rvalid),
    .lsu_axi_rready  (lsu_axi_rready),
    .lsu_axi_rid     (lsu_axi_rid),
    .lsu_axi_rdata   (lsu_axi_rdata),
    .lsu_axi_rresp   (lsu_axi_rresp),
    .lsu_axi_rlast   (lsu_axi_rlast),

    // ─── STEP 2: Debug SB AXI4 master → crossbar s02 ────────────────────
    .sb_axi_awvalid  (sb_axi_awvalid),
    .sb_axi_awready  (sb_axi_awready),
    .sb_axi_awid     (sb_axi_awid),
    .sb_axi_awaddr   (sb_axi_awaddr),
    .sb_axi_awregion (sb_axi_awregion),
    .sb_axi_awlen    (sb_axi_awlen),
    .sb_axi_awsize   (sb_axi_awsize),
    .sb_axi_awburst  (sb_axi_awburst),
    .sb_axi_awlock   (sb_axi_awlock),
    .sb_axi_awcache  (sb_axi_awcache),
    .sb_axi_awprot   (sb_axi_awprot),
    .sb_axi_awqos    (sb_axi_awqos),
    .sb_axi_wvalid   (sb_axi_wvalid),
    .sb_axi_wready   (sb_axi_wready),
    .sb_axi_wdata    (sb_axi_wdata),
    .sb_axi_wstrb    (sb_axi_wstrb),
    .sb_axi_wlast    (sb_axi_wlast),
    .sb_axi_bvalid   (sb_axi_bvalid),
    .sb_axi_bready   (sb_axi_bready),
    .sb_axi_bresp    (sb_axi_bresp),
    .sb_axi_bid      (sb_axi_bid),
    .sb_axi_arvalid  (sb_axi_arvalid),
    .sb_axi_arready  (sb_axi_arready),
    .sb_axi_arid     (sb_axi_arid),
    .sb_axi_araddr   (sb_axi_araddr),
    .sb_axi_arregion (sb_axi_arregion),
    .sb_axi_arlen    (sb_axi_arlen),
    .sb_axi_arsize   (sb_axi_arsize),
    .sb_axi_arburst  (sb_axi_arburst),
    .sb_axi_arlock   (sb_axi_arlock),
    .sb_axi_arcache  (sb_axi_arcache),
    .sb_axi_arprot   (sb_axi_arprot),
    .sb_axi_arqos    (sb_axi_arqos),
    .sb_axi_rvalid   (sb_axi_rvalid),
    .sb_axi_rready   (sb_axi_rready),
    .sb_axi_rid      (sb_axi_rid),
    .sb_axi_rdata    (sb_axi_rdata),
    .sb_axi_rresp    (sb_axi_rresp),
    .sb_axi_rlast    (sb_axi_rlast),

    // ─── STEP 4: DMA Slave Port ← crossbar m00 ────────────────────────────
    .dma_axi_awvalid (dma_axi_awvalid),
    .dma_axi_awready (dma_axi_awready),
    .dma_axi_awid    (dma_axi_awid),
    .dma_axi_awaddr  (dma_axi_awaddr),
    .dma_axi_awsize  (dma_axi_awsize),
    .dma_axi_awprot  (dma_axi_awprot),
    .dma_axi_awlen   (dma_axi_awlen),
    .dma_axi_awburst (dma_axi_awburst),
    .dma_axi_wvalid  (dma_axi_wvalid),
    .dma_axi_wready  (dma_axi_wready),
    .dma_axi_wdata   (dma_axi_wdata),
    .dma_axi_wstrb   (dma_axi_wstrb),
    .dma_axi_wlast   (dma_axi_wlast),
    .dma_axi_bvalid  (dma_axi_bvalid),
    .dma_axi_bready  (dma_axi_bready),
    .dma_axi_bresp   (dma_axi_bresp),
    .dma_axi_bid     (dma_axi_bid),
    .dma_axi_arvalid (dma_axi_arvalid),
    .dma_axi_arready (dma_axi_arready),
    .dma_axi_arid    (dma_axi_arid),
    .dma_axi_araddr  (dma_axi_araddr),
    .dma_axi_arsize  (dma_axi_arsize),
    .dma_axi_arprot  (dma_axi_arprot),
    .dma_axi_arlen   (dma_axi_arlen),
    .dma_axi_arburst (dma_axi_arburst),
    .dma_axi_rvalid  (dma_axi_rvalid),
    .dma_axi_rready  (dma_axi_rready),
    .dma_axi_rid     (dma_axi_rid),
    .dma_axi_rdata   (dma_axi_rdata),
    .dma_axi_rresp   (dma_axi_rresp),
    .dma_axi_rlast   (dma_axi_rlast),

    // ─── Memory export interfaces (SRAM macros instantiated elsewhere) ────
    .el2_mem_export   (el2_mem_export),
    .el2_icache_export(el2_icache_export),

    // ─── Trace and performance counter outputs (unused in this pass) ─────
    .trace_rv_i_insn_ip     (),
    .trace_rv_i_address_ip  (),
    .trace_rv_i_valid_ip    (),
    .trace_rv_i_exception_ip(),
    .trace_rv_i_ecause_ip   (),
    .trace_rv_i_interrupt_ip(),
    .trace_rv_i_tval_ip     (),
    .dec_tlu_perfcnt0       (),
    .dec_tlu_perfcnt1       (),
    .dec_tlu_perfcnt2       (),
    .dec_tlu_perfcnt3       (),

    // ─── MPC status outputs (no PMU) ─────────────────────────────────────
    .mpc_debug_halt_ack (),
    .mpc_debug_run_ack  (),
    .debug_brkpt_status (),
    .o_cpu_halt_ack     (),
    .o_cpu_halt_status  (),
    .o_cpu_run_ack      (),
    .o_debug_mode_status()
  );

  // ===========================================================================
  // STEP 3
  // ─── MBIST Controller instantiation ─────────────────────────────────────────
  // axil_mbist_ctrl_top instantiates mbist_dma_master internally.
  // The DMA master's AXI4 output wires (m_dma_axi_*) become crossbar s03_axi_*.
  // The CSR AXI4-Lite slave port wires come from crossbar m04_axi_* (after bridge);
  // that bridge connection is part of the next integration pass.
  // ===========================================================================
  axil_mbist_ctrl_top u_mbist_ctrl (
    .axi_aclk_i    (clk_i),
    .axi_aresetn_i (rst_l_i),

    // ─── CSR AXI4-Lite slave (from crossbar m04 via bridge) ──────────────
    // These are connected here but the bridge itself is wired in the next pass.
    // Temporarily the CSR slave receives its signals from m04_axi_* module ports
    // which will be driven by the AXI4-to-AXI4-Lite bridge in the next step.
    // For now the wire stubs are present; the tool will warn about undriven
    // inputs which will be resolved when the bridge is wired.
    //
    // NOTE: the bridge Lite-side has ID signals; the MBIST top was designed
    // to accept them.  The connection matches exactly — no width change needed.
    .axi_awid_i    (m04_axi_awid   [3:0]),  // bridge drives these
    .axi_awaddr_i  (m04_axi_awaddr ),
    .axi_awprot_i  (3'b000         ),        // prot tied: bridge doesn't use it
    .axi_awvalid_i (m04_axi_awvalid),
    .axi_awready_o (m04_axi_awready),        // NOTE: this drives the crossbar port
    .axi_wdata_i   (m04_axi_wdata  [31:0]),  // bridge down-converts 64→32
    .axi_wstrb_i   (m04_axi_wstrb  [3:0]),
    .axi_wvalid_i  (m04_axi_wvalid ),
    .axi_wready_o  (m04_axi_wready ),
    .axi_bid_o     (m04_axi_bid    ),
    .axi_bresp_o   (m04_axi_bresp  ),
    .axi_bvalid_o  (m04_axi_bvalid ),
    .axi_bready_i  (m04_axi_bready ),
    .axi_arid_i    (m04_axi_arid   [3:0]),
    .axi_araddr_i  (m04_axi_araddr ),
    .axi_arprot_i  (3'b000         ),
    .axi_arvalid_i (m04_axi_arvalid),
    .axi_arready_o (m04_axi_arready),
    .axi_rid_o     (m04_axi_rid    ),
    .axi_rdata_o   (m04_axi_rdata  [31:0]),
    .axi_rresp_o   (m04_axi_rresp  ),
    .axi_rvalid_o  (m04_axi_rvalid ),
    .axi_rready_i  (m04_axi_rready ),

    // ─── System Timer auto-trigger ────────────────────────────────────────
    .timer_tick_i  (timer_tick_i),

    // ─── Sideband outputs ────────────────────────────────────────────────
    .mbist_active_o         (mbist_active_o),
    .mbist_fault_addr_tap_o (mbist_fault_addr_tap_o),
    .mbist_irq_done_o       (mbist_irq_done_i),   // loops back to extintsrc_req[1]

    // ─── STEP 3: DMA AXI4 master → crossbar slave s03 ────────────────────
    .m_dma_axi_awid     (mbist_m_axi_awid),
    .m_dma_axi_awaddr   (mbist_m_axi_awaddr),
    .m_dma_axi_awlen    (mbist_m_axi_awlen),
    .m_dma_axi_awsize   (mbist_m_axi_awsize),
    .m_dma_axi_awburst  (mbist_m_axi_awburst),
    .m_dma_axi_awlock   (mbist_m_axi_awlock),
    .m_dma_axi_awcache  (mbist_m_axi_awcache),
    .m_dma_axi_awprot   (mbist_m_axi_awprot),
    .m_dma_axi_awqos    (mbist_m_axi_awqos),
    .m_dma_axi_awvalid  (mbist_m_axi_awvalid),
    .m_dma_axi_awready  (mbist_m_axi_awready),
    .m_dma_axi_wdata    (mbist_m_axi_wdata),
    .m_dma_axi_wstrb    (mbist_m_axi_wstrb),
    .m_dma_axi_wlast    (mbist_m_axi_wlast),
    .m_dma_axi_wvalid   (mbist_m_axi_wvalid),
    .m_dma_axi_wready   (mbist_m_axi_wready),
    .m_dma_axi_bid      (mbist_m_axi_bid),
    .m_dma_axi_bresp    (mbist_m_axi_bresp),
    .m_dma_axi_bvalid   (mbist_m_axi_bvalid),
    .m_dma_axi_bready   (mbist_m_axi_bready),
    .m_dma_axi_arid     (mbist_m_axi_arid),
    .m_dma_axi_araddr   (mbist_m_axi_araddr),
    .m_dma_axi_arlen    (mbist_m_axi_arlen),
    .m_dma_axi_arsize   (mbist_m_axi_arsize),
    .m_dma_axi_arburst  (mbist_m_axi_arburst),
    .m_dma_axi_arlock   (mbist_m_axi_arlock),
    .m_dma_axi_arcache  (mbist_m_axi_arcache),
    .m_dma_axi_arprot   (mbist_m_axi_arprot),
    .m_dma_axi_arqos    (mbist_m_axi_arqos),
    .m_dma_axi_arvalid  (mbist_m_axi_arvalid),
    .m_dma_axi_arready  (mbist_m_axi_arready),
    .m_dma_axi_rid      (mbist_m_axi_rid),
    .m_dma_axi_rdata    (mbist_m_axi_rdata),
    .m_dma_axi_rresp    (mbist_m_axi_rresp),
    .m_dma_axi_rlast    (mbist_m_axi_rlast),
    .m_dma_axi_rvalid   (mbist_m_axi_rvalid),
    .m_dma_axi_rready   (mbist_m_axi_rready)
  );

  // ===========================================================================
  // STEP 2 + 3 + 4
  // ─── axi_interconnect_wrap_4x7 (crossbar) instantiation ─────────────────────
  //
  //  Slave-side (masters into the crossbar):
  //    s00 ← IFU AXI4 master    (core)
  //    s01 ← LSU AXI4 master    (core)
  //    s02 ← SB/Debug AXI4      (core)
  //    s03 ← MBIST DMA master
  //
  //  Master-side (targets the crossbar drives out):
  //    m00 → DMA Slave Port     (core — ICCM/DCCM)
  //    m01 → UART               (exposed as module port for next pass)
  //    m02 → System Timer       (exposed as module port for next pass)
  //    m03 → GPIO               (exposed as module port for next pass)
  //    m04 → MBIST Controller CSR (wired to axil_mbist_ctrl_top above)
  //    m05 → ECC Monitor        (exposed as module port for next pass)
  //    m06 → Watchdog Timer     (exposed as module port for next pass)
  //
  //  USER/AWUSER/WUSER/BUSER/ARUSER/RUSER sideband signals are disabled
  //  (AWUSER_ENABLE=0 etc.) — tie to 1-bit zeros to satisfy port list.
  // ===========================================================================
  axi_interconnect_wrap_4x7 #(
    .DATA_WIDTH      (XBAR_DATA_WIDTH),    // 64
    .ADDR_WIDTH      (XBAR_ADDR_WIDTH),    // 32
    .ID_WIDTH        (XBAR_ID_WIDTH),      //  4
    .AWUSER_ENABLE   (0),
    .WUSER_ENABLE    (0),
    .BUSER_ENABLE    (0),
    .ARUSER_ENABLE   (0),
    .RUSER_ENABLE    (0),
    .FORWARD_ID      (0),
    .M_REGIONS       (1)
  ) u_crossbar (
    .clk  (clk_i),
    .rst  (~rst_l_i),   // crossbar uses active-high reset

    // ─── s00 : IFU ────────────────────────────────────────────────────────
    .s00_axi_awid    (ifu_axi_awid),
    .s00_axi_awaddr  (ifu_axi_awaddr),
    .s00_axi_awlen   (ifu_axi_awlen),
    .s00_axi_awsize  (ifu_axi_awsize),
    .s00_axi_awburst (ifu_axi_awburst),
    .s00_axi_awlock  (ifu_axi_awlock),
    .s00_axi_awcache (ifu_axi_awcache),
    .s00_axi_awprot  (ifu_axi_awprot),
    .s00_axi_awqos   (ifu_axi_awqos),
    .s00_axi_awuser  (1'b0),
    .s00_axi_awvalid (ifu_axi_awvalid),
    .s00_axi_awready (ifu_axi_awready),
    .s00_axi_wdata   (ifu_axi_wdata),
    .s00_axi_wstrb   (ifu_axi_wstrb),
    .s00_axi_wlast   (ifu_axi_wlast),
    .s00_axi_wuser   (1'b0),
    .s00_axi_wvalid  (ifu_axi_wvalid),
    .s00_axi_wready  (ifu_axi_wready),
    .s00_axi_bid     (ifu_axi_bid),
    .s00_axi_bresp   (ifu_axi_bresp),
    .s00_axi_buser   (),
    .s00_axi_bvalid  (ifu_axi_bvalid),
    .s00_axi_bready  (ifu_axi_bready),
    .s00_axi_arid    (ifu_axi_arid),
    .s00_axi_araddr  (ifu_axi_araddr),
    .s00_axi_arlen   (ifu_axi_arlen),
    .s00_axi_arsize  (ifu_axi_arsize),
    .s00_axi_arburst (ifu_axi_arburst),
    .s00_axi_arlock  (ifu_axi_arlock),
    .s00_axi_arcache (ifu_axi_arcache),
    .s00_axi_arprot  (ifu_axi_arprot),
    .s00_axi_arqos   (ifu_axi_arqos),
    .s00_axi_aruser  (1'b0),
    .s00_axi_arvalid (ifu_axi_arvalid),
    .s00_axi_arready (ifu_axi_arready),
    .s00_axi_rid     (ifu_axi_rid),
    .s00_axi_rdata   (ifu_axi_rdata),
    .s00_axi_rresp   (ifu_axi_rresp),
    .s00_axi_rlast   (ifu_axi_rlast),
    .s00_axi_ruser   (),
    .s00_axi_rvalid  (ifu_axi_rvalid),
    .s00_axi_rready  (ifu_axi_rready),

    // ─── s01 : LSU ────────────────────────────────────────────────────────
    .s01_axi_awid    (lsu_axi_awid),
    .s01_axi_awaddr  (lsu_axi_awaddr),
    .s01_axi_awlen   (lsu_axi_awlen),
    .s01_axi_awsize  (lsu_axi_awsize),
    .s01_axi_awburst (lsu_axi_awburst),
    .s01_axi_awlock  (lsu_axi_awlock),
    .s01_axi_awcache (lsu_axi_awcache),
    .s01_axi_awprot  (lsu_axi_awprot),
    .s01_axi_awqos   (lsu_axi_awqos),
    .s01_axi_awuser  (1'b0),
    .s01_axi_awvalid (lsu_axi_awvalid),
    .s01_axi_awready (lsu_axi_awready),
    .s01_axi_wdata   (lsu_axi_wdata),
    .s01_axi_wstrb   (lsu_axi_wstrb),
    .s01_axi_wlast   (lsu_axi_wlast),
    .s01_axi_wuser   (1'b0),
    .s01_axi_wvalid  (lsu_axi_wvalid),
    .s01_axi_wready  (lsu_axi_wready),
    .s01_axi_bid     (lsu_axi_bid),
    .s01_axi_bresp   (lsu_axi_bresp),
    .s01_axi_buser   (),
    .s01_axi_bvalid  (lsu_axi_bvalid),
    .s01_axi_bready  (lsu_axi_bready),
    .s01_axi_arid    (lsu_axi_arid),
    .s01_axi_araddr  (lsu_axi_araddr),
    .s01_axi_arlen   (lsu_axi_arlen),
    .s01_axi_arsize  (lsu_axi_arsize),
    .s01_axi_arburst (lsu_axi_arburst),
    .s01_axi_arlock  (lsu_axi_arlock),
    .s01_axi_arcache (lsu_axi_arcache),
    .s01_axi_arprot  (lsu_axi_arprot),
    .s01_axi_arqos   (lsu_axi_arqos),
    .s01_axi_aruser  (1'b0),
    .s01_axi_arvalid (lsu_axi_arvalid),
    .s01_axi_arready (lsu_axi_arready),
    .s01_axi_rid     (lsu_axi_rid),
    .s01_axi_rdata   (lsu_axi_rdata),
    .s01_axi_rresp   (lsu_axi_rresp),
    .s01_axi_rlast   (lsu_axi_rlast),
    .s01_axi_ruser   (),
    .s01_axi_rvalid  (lsu_axi_rvalid),
    .s01_axi_rready  (lsu_axi_rready),

    // ─── s02 : Debug SB (sb_axi) ─────────────────────────────────────────
    .s02_axi_awid    (sb_axi_awid),
    .s02_axi_awaddr  (sb_axi_awaddr),
    .s02_axi_awlen   (sb_axi_awlen),
    .s02_axi_awsize  (sb_axi_awsize),
    .s02_axi_awburst (sb_axi_awburst),
    .s02_axi_awlock  (sb_axi_awlock),
    .s02_axi_awcache (sb_axi_awcache),
    .s02_axi_awprot  (sb_axi_awprot),
    .s02_axi_awqos   (sb_axi_awqos),
    .s02_axi_awuser  (1'b0),
    .s02_axi_awvalid (sb_axi_awvalid),
    .s02_axi_awready (sb_axi_awready),
    .s02_axi_wdata   (sb_axi_wdata),
    .s02_axi_wstrb   (sb_axi_wstrb),
    .s02_axi_wlast   (sb_axi_wlast),
    .s02_axi_wuser   (1'b0),
    .s02_axi_wvalid  (sb_axi_wvalid),
    .s02_axi_wready  (sb_axi_wready),
    .s02_axi_bid     (sb_axi_bid),
    .s02_axi_bresp   (sb_axi_bresp),
    .s02_axi_buser   (),
    .s02_axi_bvalid  (sb_axi_bvalid),
    .s02_axi_bready  (sb_axi_bready),
    .s02_axi_arid    (sb_axi_arid),
    .s02_axi_araddr  (sb_axi_araddr),
    .s02_axi_arlen   (sb_axi_arlen),
    .s02_axi_arsize  (sb_axi_arsize),
    .s02_axi_arburst (sb_axi_arburst),
    .s02_axi_arlock  (sb_axi_arlock),
    .s02_axi_arcache (sb_axi_arcache),
    .s02_axi_arprot  (sb_axi_arprot),
    .s02_axi_arqos   (sb_axi_arqos),
    .s02_axi_aruser  (1'b0),
    .s02_axi_arvalid (sb_axi_arvalid),
    .s02_axi_arready (sb_axi_arready),
    .s02_axi_rid     (sb_axi_rid),
    .s02_axi_rdata   (sb_axi_rdata),
    .s02_axi_rresp   (sb_axi_rresp),
    .s02_axi_rlast   (sb_axi_rlast),
    .s02_axi_ruser   (),
    .s02_axi_rvalid  (sb_axi_rvalid),
    .s02_axi_rready  (sb_axi_rready),

    // ─── s03 : MBIST DMA master ────────────────────────────────────────────
    .s03_axi_awid    (mbist_m_axi_awid),
    .s03_axi_awaddr  (mbist_m_axi_awaddr),
    .s03_axi_awlen   (mbist_m_axi_awlen),
    .s03_axi_awsize  (mbist_m_axi_awsize),
    .s03_axi_awburst (mbist_m_axi_awburst),
    .s03_axi_awlock  (mbist_m_axi_awlock),
    .s03_axi_awcache (mbist_m_axi_awcache),
    .s03_axi_awprot  (mbist_m_axi_awprot),
    .s03_axi_awqos   (mbist_m_axi_awqos),
    .s03_axi_awuser  (1'b0),
    .s03_axi_awvalid (mbist_m_axi_awvalid),
    .s03_axi_awready (mbist_m_axi_awready),
    .s03_axi_wdata   (mbist_m_axi_wdata),
    .s03_axi_wstrb   (mbist_m_axi_wstrb),
    .s03_axi_wlast   (mbist_m_axi_wlast),
    .s03_axi_wuser   (1'b0),
    .s03_axi_wvalid  (mbist_m_axi_wvalid),
    .s03_axi_wready  (mbist_m_axi_wready),
    .s03_axi_bid     (mbist_m_axi_bid),
    .s03_axi_bresp   (mbist_m_axi_bresp),
    .s03_axi_buser   (),
    .s03_axi_bvalid  (mbist_m_axi_bvalid),
    .s03_axi_bready  (mbist_m_axi_bready),
    .s03_axi_arid    (mbist_m_axi_arid),
    .s03_axi_araddr  (mbist_m_axi_araddr),
    .s03_axi_arlen   (mbist_m_axi_arlen),
    .s03_axi_arsize  (mbist_m_axi_arsize),
    .s03_axi_arburst (mbist_m_axi_arburst),
    .s03_axi_arlock  (mbist_m_axi_arlock),
    .s03_axi_arcache (mbist_m_axi_arcache),
    .s03_axi_arprot  (mbist_m_axi_arprot),
    .s03_axi_arqos   (mbist_m_axi_arqos),
    .s03_axi_aruser  (1'b0),
    .s03_axi_arvalid (mbist_m_axi_arvalid),
    .s03_axi_arready (mbist_m_axi_arready),
    .s03_axi_rid     (mbist_m_axi_rid),
    .s03_axi_rdata   (mbist_m_axi_rdata),
    .s03_axi_rresp   (mbist_m_axi_rresp),
    .s03_axi_rlast   (mbist_m_axi_rlast),
    .s03_axi_ruser   (),
    .s03_axi_rvalid  (mbist_m_axi_rvalid),
    .s03_axi_rready  (mbist_m_axi_rready),

    // ─── m00 : DMA Slave Port (targets ICCM/DCCM inside the core) ─────────
    // Crossbar drives 64-bit bus; core DMA port is 64-bit.
    // awcache/awqos/awregion/awuser are present in m00 but not in DMA slave port —
    // those are consumed by the crossbar internally and not forwarded to the core.
    .m00_axi_awid    (dma_axi_awid),
    .m00_axi_awaddr  (dma_axi_awaddr),
    .m00_axi_awlen   (dma_axi_awlen),
    .m00_axi_awsize  (dma_axi_awsize),
    .m00_axi_awburst (dma_axi_awburst),
    .m00_axi_awlock  (),        // not a DMA slave port input
    .m00_axi_awcache (),        // not a DMA slave port input
    .m00_axi_awprot  (dma_axi_awprot),
    .m00_axi_awqos   (),        // not a DMA slave port input
    .m00_axi_awregion(),        // not a DMA slave port input
    .m00_axi_awuser  (),        // sideband disabled
    .m00_axi_awvalid (dma_axi_awvalid),
    .m00_axi_awready (dma_axi_awready),
    .m00_axi_wdata   (dma_axi_wdata),
    .m00_axi_wstrb   (dma_axi_wstrb),
    .m00_axi_wlast   (dma_axi_wlast),
    .m00_axi_wuser   (),
    .m00_axi_wvalid  (dma_axi_wvalid),
    .m00_axi_wready  (dma_axi_wready),
    .m00_axi_bid     (dma_axi_bid),
    .m00_axi_bresp   (dma_axi_bresp),
    .m00_axi_buser   (1'b0),
    .m00_axi_bvalid  (dma_axi_bvalid),
    .m00_axi_bready  (dma_axi_bready),
    .m00_axi_arid    (dma_axi_arid),
    .m00_axi_araddr  (dma_axi_araddr),
    .m00_axi_arlen   (dma_axi_arlen),
    .m00_axi_arsize  (dma_axi_arsize),
    .m00_axi_arburst (dma_axi_arburst),
    .m00_axi_arlock  (),
    .m00_axi_arcache (),
    .m00_axi_arprot  (dma_axi_arprot),
    .m00_axi_arqos   (),
    .m00_axi_arregion(),
    .m00_axi_aruser  (),
    .m00_axi_arvalid (dma_axi_arvalid),
    .m00_axi_arready (dma_axi_arready),
    .m00_axi_rid     (dma_axi_rid),
    .m00_axi_rdata   (dma_axi_rdata),
    .m00_axi_rresp   (dma_axi_rresp),
    .m00_axi_rlast   (dma_axi_rlast),
    .m00_axi_ruser   (1'b0),
    .m00_axi_rvalid  (dma_axi_rvalid),
    .m00_axi_rready  (dma_axi_rready),

    // ─── m01-m06 : Peripherals (passed out as module ports for next pass) ──
    .m01_axi_awid    (m01_axi_awid),    .m01_axi_awaddr  (m01_axi_awaddr),
    .m01_axi_awlen   (m01_axi_awlen),   .m01_axi_awsize  (m01_axi_awsize),
    .m01_axi_awburst (m01_axi_awburst), .m01_axi_awlock  (m01_axi_awlock),
    .m01_axi_awcache (m01_axi_awcache), .m01_axi_awprot  (m01_axi_awprot),
    .m01_axi_awqos   (m01_axi_awqos),   .m01_axi_awregion(m01_axi_awregion),
    .m01_axi_awuser  (),
    .m01_axi_awvalid (m01_axi_awvalid), .m01_axi_awready (m01_axi_awready),
    .m01_axi_wdata   (m01_axi_wdata),   .m01_axi_wstrb   (m01_axi_wstrb),
    .m01_axi_wlast   (m01_axi_wlast),   .m01_axi_wuser   (),
    .m01_axi_wvalid  (m01_axi_wvalid),  .m01_axi_wready  (m01_axi_wready),
    .m01_axi_bid     (m01_axi_bid),     .m01_axi_bresp   (m01_axi_bresp),
    .m01_axi_buser   (1'b0),
    .m01_axi_bvalid  (m01_axi_bvalid),  .m01_axi_bready  (m01_axi_bready),
    .m01_axi_arid    (m01_axi_arid),    .m01_axi_araddr  (m01_axi_araddr),
    .m01_axi_arlen   (m01_axi_arlen),   .m01_axi_arsize  (m01_axi_arsize),
    .m01_axi_arburst (m01_axi_arburst), .m01_axi_arlock  (m01_axi_arlock),
    .m01_axi_arcache (m01_axi_arcache), .m01_axi_arprot  (m01_axi_arprot),
    .m01_axi_arqos   (m01_axi_arqos),   .m01_axi_arregion(m01_axi_arregion),
    .m01_axi_aruser  (),
    .m01_axi_arvalid (m01_axi_arvalid), .m01_axi_arready (m01_axi_arready),
    .m01_axi_rid     (m01_axi_rid),     .m01_axi_rdata   (m01_axi_rdata),
    .m01_axi_rresp   (m01_axi_rresp),   .m01_axi_rlast   (m01_axi_rlast),
    .m01_axi_ruser   (1'b0),
    .m01_axi_rvalid  (m01_axi_rvalid),  .m01_axi_rready  (m01_axi_rready),

    .m02_axi_awid    (m02_axi_awid),    .m02_axi_awaddr  (m02_axi_awaddr),
    .m02_axi_awlen   (m02_axi_awlen),   .m02_axi_awsize  (m02_axi_awsize),
    .m02_axi_awburst (m02_axi_awburst), .m02_axi_awlock  (m02_axi_awlock),
    .m02_axi_awcache (m02_axi_awcache), .m02_axi_awprot  (m02_axi_awprot),
    .m02_axi_awqos   (m02_axi_awqos),   .m02_axi_awregion(m02_axi_awregion),
    .m02_axi_awuser  (),
    .m02_axi_awvalid (m02_axi_awvalid), .m02_axi_awready (m02_axi_awready),
    .m02_axi_wdata   (m02_axi_wdata),   .m02_axi_wstrb   (m02_axi_wstrb),
    .m02_axi_wlast   (m02_axi_wlast),   .m02_axi_wuser   (),
    .m02_axi_wvalid  (m02_axi_wvalid),  .m02_axi_wready  (m02_axi_wready),
    .m02_axi_bid     (m02_axi_bid),     .m02_axi_bresp   (m02_axi_bresp),
    .m02_axi_buser   (1'b0),
    .m02_axi_bvalid  (m02_axi_bvalid),  .m02_axi_bready  (m02_axi_bready),
    .m02_axi_arid    (m02_axi_arid),    .m02_axi_araddr  (m02_axi_araddr),
    .m02_axi_arlen   (m02_axi_arlen),   .m02_axi_arsize  (m02_axi_arsize),
    .m02_axi_arburst (m02_axi_arburst), .m02_axi_arlock  (m02_axi_arlock),
    .m02_axi_arcache (m02_axi_arcache), .m02_axi_arprot  (m02_axi_arprot),
    .m02_axi_arqos   (m02_axi_arqos),   .m02_axi_arregion(m02_axi_arregion),
    .m02_axi_aruser  (),
    .m02_axi_arvalid (m02_axi_arvalid), .m02_axi_arready (m02_axi_arready),
    .m02_axi_rid     (m02_axi_rid),     .m02_axi_rdata   (m02_axi_rdata),
    .m02_axi_rresp   (m02_axi_rresp),   .m02_axi_rlast   (m02_axi_rlast),
    .m02_axi_ruser   (1'b0),
    .m02_axi_rvalid  (m02_axi_rvalid),  .m02_axi_rready  (m02_axi_rready),

    .m03_axi_awid    (m03_axi_awid),    .m03_axi_awaddr  (m03_axi_awaddr),
    .m03_axi_awlen   (m03_axi_awlen),   .m03_axi_awsize  (m03_axi_awsize),
    .m03_axi_awburst (m03_axi_awburst), .m03_axi_awlock  (m03_axi_awlock),
    .m03_axi_awcache (m03_axi_awcache), .m03_axi_awprot  (m03_axi_awprot),
    .m03_axi_awqos   (m03_axi_awqos),   .m03_axi_awregion(m03_axi_awregion),
    .m03_axi_awuser  (),
    .m03_axi_awvalid (m03_axi_awvalid), .m03_axi_awready (m03_axi_awready),
    .m03_axi_wdata   (m03_axi_wdata),   .m03_axi_wstrb   (m03_axi_wstrb),
    .m03_axi_wlast   (m03_axi_wlast),   .m03_axi_wuser   (),
    .m03_axi_wvalid  (m03_axi_wvalid),  .m03_axi_wready  (m03_axi_wready),
    .m03_axi_bid     (m03_axi_bid),     .m03_axi_bresp   (m03_axi_bresp),
    .m03_axi_buser   (1'b0),
    .m03_axi_bvalid  (m03_axi_bvalid),  .m03_axi_bready  (m03_axi_bready),
    .m03_axi_arid    (m03_axi_arid),    .m03_axi_araddr  (m03_axi_araddr),
    .m03_axi_arlen   (m03_axi_arlen),   .m03_axi_arsize  (m03_axi_arsize),
    .m03_axi_arburst (m03_axi_arburst), .m03_axi_arlock  (m03_axi_arlock),
    .m03_axi_arcache (m03_axi_arcache), .m03_axi_arprot  (m03_axi_arprot),
    .m03_axi_arqos   (m03_axi_arqos),   .m03_axi_arregion(m03_axi_arregion),
    .m03_axi_aruser  (),
    .m03_axi_arvalid (m03_axi_arvalid), .m03_axi_arready (m03_axi_arready),
    .m03_axi_rid     (m03_axi_rid),     .m03_axi_rdata   (m03_axi_rdata),
    .m03_axi_rresp   (m03_axi_rresp),   .m03_axi_rlast   (m03_axi_rlast),
    .m03_axi_ruser   (1'b0),
    .m03_axi_rvalid  (m03_axi_rvalid),  .m03_axi_rready  (m03_axi_rready),

    // m04 signals are driven to/from axil_mbist_ctrl_top (wired above)
    .m04_axi_awid    (m04_axi_awid),    .m04_axi_awaddr  (m04_axi_awaddr),
    .m04_axi_awlen   (m04_axi_awlen),   .m04_axi_awsize  (m04_axi_awsize),
    .m04_axi_awburst (m04_axi_awburst), .m04_axi_awlock  (m04_axi_awlock),
    .m04_axi_awcache (m04_axi_awcache), .m04_axi_awprot  (m04_axi_awprot),
    .m04_axi_awqos   (m04_axi_awqos),   .m04_axi_awregion(m04_axi_awregion),
    .m04_axi_awuser  (),
    .m04_axi_awvalid (m04_axi_awvalid), .m04_axi_awready (m04_axi_awready),
    .m04_axi_wdata   (m04_axi_wdata),   .m04_axi_wstrb   (m04_axi_wstrb),
    .m04_axi_wlast   (m04_axi_wlast),   .m04_axi_wuser   (),
    .m04_axi_wvalid  (m04_axi_wvalid),  .m04_axi_wready  (m04_axi_wready),
    .m04_axi_bid     (m04_axi_bid),     .m04_axi_bresp   (m04_axi_bresp),
    .m04_axi_buser   (1'b0),
    .m04_axi_bvalid  (m04_axi_bvalid),  .m04_axi_bready  (m04_axi_bready),
    .m04_axi_arid    (m04_axi_arid),    .m04_axi_araddr  (m04_axi_araddr),
    .m04_axi_arlen   (m04_axi_arlen),   .m04_axi_arsize  (m04_axi_arsize),
    .m04_axi_arburst (m04_axi_arburst), .m04_axi_arlock  (m04_axi_arlock),
    .m04_axi_arcache (m04_axi_arcache), .m04_axi_arprot  (m04_axi_arprot),
    .m04_axi_arqos   (m04_axi_arqos),   .m04_axi_arregion(m04_axi_arregion),
    .m04_axi_aruser  (),
    .m04_axi_arvalid (m04_axi_arvalid), .m04_axi_arready (m04_axi_arready),
    .m04_axi_rid     (m04_axi_rid),     .m04_axi_rdata   (m04_axi_rdata),
    .m04_axi_rresp   (m04_axi_rresp),   .m04_axi_rlast   (m04_axi_rlast),
    .m04_axi_ruser   (1'b0),
    .m04_axi_rvalid  (m04_axi_rvalid),  .m04_axi_rready  (m04_axi_rready),

    .m05_axi_awid    (m05_axi_awid),    .m05_axi_awaddr  (m05_axi_awaddr),
    .m05_axi_awlen   (m05_axi_awlen),   .m05_axi_awsize  (m05_axi_awsize),
    .m05_axi_awburst (m05_axi_awburst), .m05_axi_awlock  (m05_axi_awlock),
    .m05_axi_awcache (m05_axi_awcache), .m05_axi_awprot  (m05_axi_awprot),
    .m05_axi_awqos   (m05_axi_awqos),   .m05_axi_awregion(m05_axi_awregion),
    .m05_axi_awuser  (),
    .m05_axi_awvalid (m05_axi_awvalid), .m05_axi_awready (m05_axi_awready),
    .m05_axi_wdata   (m05_axi_wdata),   .m05_axi_wstrb   (m05_axi_wstrb),
    .m05_axi_wlast   (m05_axi_wlast),   .m05_axi_wuser   (),
    .m05_axi_wvalid  (m05_axi_wvalid),  .m05_axi_wready  (m05_axi_wready),
    .m05_axi_bid     (m05_axi_bid),     .m05_axi_bresp   (m05_axi_bresp),
    .m05_axi_buser   (1'b0),
    .m05_axi_bvalid  (m05_axi_bvalid),  .m05_axi_bready  (m05_axi_bready),
    .m05_axi_arid    (m05_axi_arid),    .m05_axi_araddr  (m05_axi_araddr),
    .m05_axi_arlen   (m05_axi_arlen),   .m05_axi_arsize  (m05_axi_arsize),
    .m05_axi_arburst (m05_axi_arburst), .m05_axi_arlock  (m05_axi_arlock),
    .m05_axi_arcache (m05_axi_arcache), .m05_axi_arprot  (m05_axi_arprot),
    .m05_axi_arqos   (m05_axi_arqos),   .m05_axi_arregion(m05_axi_arregion),
    .m05_axi_aruser  (),
    .m05_axi_arvalid (m05_axi_arvalid), .m05_axi_arready (m05_axi_arready),
    .m05_axi_rid     (m05_axi_rid),     .m05_axi_rdata   (m05_axi_rdata),
    .m05_axi_rresp   (m05_axi_rresp),   .m05_axi_rlast   (m05_axi_rlast),
    .m05_axi_ruser   (1'b0),
    .m05_axi_rvalid  (m05_axi_rvalid),  .m05_axi_rready  (m05_axi_rready),

    .m06_axi_awid    (m06_axi_awid),    .m06_axi_awaddr  (m06_axi_awaddr),
    .m06_axi_awlen   (m06_axi_awlen),   .m06_axi_awsize  (m06_axi_awsize),
    .m06_axi_awburst (m06_axi_awburst), .m06_axi_awlock  (m06_axi_awlock),
    .m06_axi_awcache (m06_axi_awcache), .m06_axi_awprot  (m06_axi_awprot),
    .m06_axi_awqos   (m06_axi_awqos),   .m06_axi_awregion(m06_axi_awregion),
    .m06_axi_awuser  (),
    .m06_axi_awvalid (m06_axi_awvalid), .m06_axi_awready (m06_axi_awready),
    .m06_axi_wdata   (m06_axi_wdata),   .m06_axi_wstrb   (m06_axi_wstrb),
    .m06_axi_wlast   (m06_axi_wlast),   .m06_axi_wuser   (),
    .m06_axi_wvalid  (m06_axi_wvalid),  .m06_axi_wready  (m06_axi_wready),
    .m06_axi_bid     (m06_axi_bid),     .m06_axi_bresp   (m06_axi_bresp),
    .m06_axi_buser   (1'b0),
    .m06_axi_bvalid  (m06_axi_bvalid),  .m06_axi_bready  (m06_axi_bready),
    .m06_axi_arid    (m06_axi_arid),    .m06_axi_araddr  (m06_axi_araddr),
    .m06_axi_arlen   (m06_axi_arlen),   .m06_axi_arsize  (m06_axi_arsize),
    .m06_axi_arburst (m06_axi_arburst), .m06_axi_arlock  (m06_axi_arlock),
    .m06_axi_arcache (m06_axi_arcache), .m06_axi_arprot  (m06_axi_arprot),
    .m06_axi_arqos   (m06_axi_arqos),   .m06_axi_arregion(m06_axi_arregion),
    .m06_axi_aruser  (),
    .m06_axi_arvalid (m06_axi_arvalid), .m06_axi_arready (m06_axi_arready),
    .m06_axi_rid     (m06_axi_rid),     .m06_axi_rdata   (m06_axi_rdata),
    .m06_axi_rresp   (m06_axi_rresp),   .m06_axi_rlast   (m06_axi_rlast),
    .m06_axi_ruser   (1'b0),
    .m06_axi_rvalid  (m06_axi_rvalid),  .m06_axi_rready  (m06_axi_rready)
  );

endmodule
