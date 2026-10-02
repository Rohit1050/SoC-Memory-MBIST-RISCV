/* -----------------------------------------------------------------------------
 * Project        : RISC-V SoC / MBIST  —  AXI4-Lite ECC Monitor IP
 * File           : axil_ecc_monitor_top.v
 * Module         : axil_ecc_monitor_top
 * Description    : AXI4-Lite Slave ECC Monitor — firmware-fed shadow of the
 *                  VeeR EL2 DCCM mdccmect correctable-error counter, correlated
 *                  against the active MBIST scan window to localise suspect
 *                  addresses.
 *
 * Memory-map     : ECC Monitor base = 0x4000_4000, window = 4 KB
 *                  Reached from axi_interconnect_wrap_4x7 master port m05
 *                  through the shared AXI4-to-AXI4-Lite bridge.
 *
 * Interface      : AXI4-Lite (no burst channels — no AWLEN/ARLEN/SIZE/BURST/
 *                  LOCK/CACHE/QOS/WLAST/RLAST).
 *                    DATA_WIDTH = 32   (Lite-side; bridge handles 64→32)
 *                    ADDR_WIDTH = 32   (matches crossbar ADDR_WIDTH = 32)
 *                    ID_WIDTH   = 4    (bridge propagates ID unchanged)
 *
 * Register map   (byte offsets from this IP's own base — the crossbar /
 *                 bridge adds the global 0x4000_4000 externally):
 *
 *   Offset  Register              Width  Access   Reset  Description
 *   0x00    ecc_mon_enable         1     R/W      0      Enables monitor logic
 *   0x04    ecc_mon_shadow_count  27     R/W      0      FW mirror of mdccmect.count
 *   0x08    ecc_mon_shadow_thresh  5     R/W      0      FW mirror of mdccmect.thresh
 *   0x0C    ecc_mon_event          1     R/W1C    0      FW writes 1 to signal correctable ISR fired
 *   0x10    ecc_mon_suspect_addr  32     RO       0      MBIST window active at last correlated event
 *   0x14    ecc_mon_status         2     RO       0      Bit0=correctable_seen, Bit1=mbist_correlated
 *   others  —                      —     —        —      SLVERR (gap to end of 4 KB window)
 *
 * Non-bus I/O    : Two inputs sourced by the MBIST Controller (not yet built):
 *                    mbist_active_i          — 1-bit:  MBIST scan in progress
 *                    mbist_fault_addr_tap_i  — 32-bit: current MBIST window addr
 *                  These are plain module inputs with no internal driver.
 *                  They MUST be wired to the MBIST Controller outputs once that
 *                  IP is built.  Until then this module is functionally complete
 *                  but not integrated.
 *
 * Crossbar port  : m05 on axi_interconnect_wrap_4x7
 *                    DATA_WIDTH = 64 (crossbar side; 64→32 via shared bridge)
 *                    ADDR_WIDTH = 32   ID_WIDTH = 4
 *                    M05_BASE_ADDR = 32'h4000_4000, M05_ADDR_WIDTH = 12 (4 KB)
 *
 * Behaviour      : Event-driven (not a general state machine).
 *   On an AXI4-Lite write of bit[0]=1 to ecc_mon_event (0x0C),
 *   evaluated at the WR_DATA decode step:
 *     if (ecc_mon_enable == 1):
 *         correctable_seen  <- 1
 *         if (mbist_active_i == 1):
 *             ecc_mon_suspect_addr <- mbist_fault_addr_tap_i
 *             mbist_correlated     <- 1
 *   ecc_mon_event is W1C: it always reads back as 0 (no stored state).
 *   If ecc_mon_enable == 0, the write is accepted (OKAY, no hang) but
 *   produces no state change.
 *
 * Confirmed absent : No output to MBIST Controller, no output to Watchdog
 *                    Timer, no path to DCCM, no AXI4 burst/ID-tracking signals.
 *
 * Coding style   : Synchronous active-low reset (posedge clk, negedge rstn),
 *                  _i/_o port suffixes, _d next-state variables, dual
 *                  combinational-then-sequential always blocks per channel.
 *                  Matches axil_uart_top.v conventions throughout.
 *
 * Revision History
 *  Rev | Author      | Description
 *  1.0 | HC_CBP_095  | Initial AXI4-Lite ECC Monitor (this file)
 * -----------------------------------------------------------------------------*/
`timescale 1ns/1ps

`default_nettype none

// ============================================================================
// Local defines include
// ============================================================================
`include "axil_ecc_monitor_defines.vh"


// ============================================================================
// Module declaration
// ============================================================================
/*
Title: axil_ecc_monitor_top
AXI4-Lite slave ECC Monitor for VeeR EL2 DCCM correctable-error correlation.
Two independent FSMs handle the write and read channels; the event-driven
correlation update is performed inline within the write FSM's WR_DATA state.
*/
module axil_ecc_monitor_top (

  // -------------------------------------------------------------------------
  // Clock & reset
  // -------------------------------------------------------------------------
  input  wire                                    axi_aclk_i,     // AXI / system clock
  input  wire                                    axi_aresetn_i,  // Active-low synchronous reset

  // -------------------------------------------------------------------------
  // AXI4-Lite Write Address channel (AW)
  // -------------------------------------------------------------------------
  input  wire [`_AXIL_ECC_ID_WIDTH_-1:0]         axi_awid_i,
  input  wire [`_AXIL_ECC_ADDR_WIDTH_-1:0]       axi_awaddr_i,
  input  wire [2:0]                              axi_awprot_i,   // accepted, not decoded
  input  wire                                    axi_awvalid_i,
  output wire                                    axi_awready_o,

  // -------------------------------------------------------------------------
  // AXI4-Lite Write Data channel (W)
  // -------------------------------------------------------------------------
  input  wire [`_AXIL_ECC_DATA_WIDTH_-1:0]       axi_wdata_i,
  input  wire [`_AXIL_ECC_DATA_WIDTH_/8-1:0]     axi_wstrb_i,
  input  wire                                    axi_wvalid_i,
  output wire                                    axi_wready_o,

  // -------------------------------------------------------------------------
  // AXI4-Lite Write Response channel (B)
  // -------------------------------------------------------------------------
  output wire [`_AXIL_ECC_ID_WIDTH_-1:0]         axi_bid_o,
  output wire [`_AXIL_ECC_RESP_WIDTH_-1:0]       axi_bresp_o,
  output wire                                    axi_bvalid_o,
  input  wire                                    axi_bready_i,

  // -------------------------------------------------------------------------
  // AXI4-Lite Read Address channel (AR)
  // -------------------------------------------------------------------------
  input  wire [`_AXIL_ECC_ID_WIDTH_-1:0]         axi_arid_i,
  input  wire [`_AXIL_ECC_ADDR_WIDTH_-1:0]       axi_araddr_i,
  input  wire [2:0]                              axi_arprot_i,   // accepted, not decoded
  input  wire                                    axi_arvalid_i,
  output wire                                    axi_arready_o,

  // -------------------------------------------------------------------------
  // AXI4-Lite Read Data channel (R)
  // -------------------------------------------------------------------------
  output wire [`_AXIL_ECC_ID_WIDTH_-1:0]         axi_rid_o,
  output wire [`_AXIL_ECC_DATA_WIDTH_-1:0]       axi_rdata_o,
  output wire [`_AXIL_ECC_RESP_WIDTH_-1:0]       axi_rresp_o,
  output wire                                    axi_rvalid_o,
  input  wire                                    axi_rready_i,

  // -------------------------------------------------------------------------
  // Non-bus inputs from MBIST Controller (not yet built).
  //   *** INTEGRATION NOTE ***
  //   Wire mbist_active_i to mbist_ctrl.mbist_active_o and
  //   mbist_fault_addr_tap_i to mbist_ctrl.mbist_fault_addr_o once the MBIST
  //   Controller IP is built.  These are left as undriven module inputs here;
  //   drive them from test vectors in tb_axil_ecc_monitor_top.v.
  // -------------------------------------------------------------------------
  input  wire                                    mbist_active_i,          // 1: MBIST scan running
  input  wire [31:0]                             mbist_fault_addr_tap_i   // current MBIST window addr
);

  // =========================================================================
  // Local parameters (sizing)
  // =========================================================================
  localparam AXI_DATA_WIDTH = `_AXIL_ECC_DATA_WIDTH_;  // 32
  localparam AXI_ADDR_WIDTH = `_AXIL_ECC_ADDR_WIDTH_;  // 32
  localparam AXI_ID_WIDTH   = `_AXIL_ECC_ID_WIDTH_;    //  4
  localparam AXI_RESP_WIDTH = `_AXIL_ECC_RESP_WIDTH_;  //  2

  // AXI_LSB_WIDTH = log2(DATA_WIDTH/8) = log2(4) = 2
  // Used to strip byte-lane LSBs when comparing to word-index defines above.
  localparam AXI_LSB_WIDTH  = 2;

  // =========================================================================
  // ECC Monitor architectural registers
  // =========================================================================
  // 0x00  ecc_mon_enable        (1-bit,  R/W)
  reg                 ecc_mon_enable,          ecc_mon_enable_d;
  // 0x04  ecc_mon_shadow_count  (27-bit, R/W)
  reg  [26:0]         ecc_mon_shadow_count,    ecc_mon_shadow_count_d;
  // 0x08  ecc_mon_shadow_thresh (5-bit,  R/W)
  reg  [4:0]          ecc_mon_shadow_thresh,   ecc_mon_shadow_thresh_d;
  // 0x10  ecc_mon_suspect_addr  (32-bit, RO — set by correlation logic only)
  reg  [31:0]         ecc_mon_suspect_addr,    ecc_mon_suspect_addr_d;
  // 0x14  ecc_mon_status bit 0  (RO)
  reg                 correctable_seen,        correctable_seen_d;
  // 0x14  ecc_mon_status bit 1  (RO)
  reg                 mbist_correlated,        mbist_correlated_d;
  // 0x0C  ecc_mon_event — W1C, always reads 0; no stored bit needed.

  // =========================================================================
  // WRITE FSM
  //   WR_IDLE  — accept AW and W channels independently, advance when both seen
  //   WR_DATA  — decode address, update register(s), prepare B response
  //   WR_RESP  — hold BVALID until BREADY, return to WR_IDLE
  // =========================================================================
  localparam WR_IDLE = 2'b00;
  localparam WR_DATA = 2'b01;
  localparam WR_RESP = 2'b10;

  reg  [1:0]                          wr_state,      wr_state_d;

  reg                                 axi_awready,   axi_awready_d;
  reg  [`_AXIL_ECC_ID_WIDTH_-1:0]     aw_id_lat,     aw_id_lat_d;
  reg  [`_AXIL_ECC_ADDR_WIDTH_-1:0]   aw_addr_lat,   aw_addr_lat_d;
  reg                                 aw_done,       aw_done_d;

  reg                                 axi_wready,    axi_wready_d;
  reg  [`_AXIL_ECC_DATA_WIDTH_-1:0]   aw_wdata_lat,  aw_wdata_lat_d;
  reg  [3:0]                          aw_wstrb_lat,  aw_wstrb_lat_d;
  reg                                 w_done,        w_done_d;

  reg  [`_AXIL_ECC_ID_WIDTH_-1:0]     axi_bid,       axi_bid_d;
  reg  [1:0]                          axi_bresp,     axi_bresp_d;
  reg                                 axi_bvalid,    axi_bvalid_d;

  // Window check: either relative (prefix 0x00000) or absolute (prefix 0x40004)
  wire aw_addr_in_window = (aw_addr_lat[AXI_ADDR_WIDTH-1:12] == `ECC_BASE_PREFIX) ||
                           (aw_addr_lat[AXI_ADDR_WIDTH-1:12] == 20'h00000);

  // ---- WRITE FSM : combinational next-state logic ----
  always @(*) begin
    // --- defaults: hold everything ---
    wr_state_d              = wr_state;
    axi_awready_d           = 1'b0;
    axi_wready_d            = axi_wready;
    axi_bid_d               = axi_bid;
    axi_bresp_d             = axi_bresp;
    axi_bvalid_d            = axi_bvalid;
    aw_id_lat_d             = aw_id_lat;
    aw_addr_lat_d           = aw_addr_lat;
    aw_wdata_lat_d          = aw_wdata_lat;
    aw_wstrb_lat_d          = aw_wstrb_lat;
    aw_done_d               = aw_done;
    w_done_d                = w_done;

    // Architecture registers: hold
    ecc_mon_enable_d        = ecc_mon_enable;
    ecc_mon_shadow_count_d  = ecc_mon_shadow_count;
    ecc_mon_shadow_thresh_d = ecc_mon_shadow_thresh;
    correctable_seen_d      = correctable_seen;
    mbist_correlated_d      = mbist_correlated;
    ecc_mon_suspect_addr_d  = ecc_mon_suspect_addr;

    case (wr_state)

      // --------------------------------------------------------------------
      WR_IDLE: begin
        axi_bvalid_d = 1'b0;
        aw_done_d    = 1'b0;
        w_done_d     = 1'b0;

        // Accept Write Address channel
        if (axi_awvalid_i) begin
          axi_awready_d = 1'b1;
          aw_id_lat_d   = axi_awid_i;
          aw_addr_lat_d = axi_awaddr_i;
          aw_done_d     = 1'b1;
        end

        // Accept Write Data channel independently
        // (AXI4-Lite allows W to arrive before or simultaneously with AW)
        if (axi_wvalid_i) begin
          axi_wready_d   = 1'b1;
          aw_wdata_lat_d = axi_wdata_i;
          aw_wstrb_lat_d = axi_wstrb_i;
          w_done_d       = 1'b1;
        end

        // Advance when both channels have been accepted
        if ((axi_awvalid_i || aw_done) && (axi_wvalid_i || w_done))
          wr_state_d = WR_DATA;
      end

      // --------------------------------------------------------------------
      WR_DATA: begin
        axi_awready_d = 1'b0;
        axi_wready_d  = 1'b0;

        if (aw_addr_in_window) begin
          case (aw_addr_lat[11 : AXI_LSB_WIDTH])

            // ----------------------------------------------------------------
            // 0x00 : ecc_mon_enable  (1-bit R/W)
            // ----------------------------------------------------------------
            `ECC_REG_ENABLE: begin
              ecc_mon_enable_d = aw_wdata_lat[0];
              axi_bresp_d      = `AXIL_ECC_RESP_OKAY;
            end

            // ----------------------------------------------------------------
            // 0x04 : ecc_mon_shadow_count  (27-bit R/W)
            // ----------------------------------------------------------------
            `ECC_REG_SHADOW_COUNT: begin
              ecc_mon_shadow_count_d = aw_wdata_lat[26:0];
              axi_bresp_d            = `AXIL_ECC_RESP_OKAY;
            end

            // ----------------------------------------------------------------
            // 0x08 : ecc_mon_shadow_thresh  (5-bit R/W)
            // ----------------------------------------------------------------
            `ECC_REG_SHADOW_THRESH: begin
              ecc_mon_shadow_thresh_d = aw_wdata_lat[4:0];
              axi_bresp_d             = `AXIL_ECC_RESP_OKAY;
            end

            // ----------------------------------------------------------------
            // 0x0C : ecc_mon_event  (W1C)
            //   Writing bit[0]=1 with enable=1 triggers correlation.
            //   The register has no stored state and always reads 0.
            //   Bus completes with OKAY regardless of enable or data value.
            // ----------------------------------------------------------------
            `ECC_REG_EVENT: begin
              if (aw_wdata_lat[0] && ecc_mon_enable) begin
                correctable_seen_d = 1'b1;
                if (mbist_active_i) begin
                  ecc_mon_suspect_addr_d = mbist_fault_addr_tap_i;
                  mbist_correlated_d     = 1'b1;
                end
              end
              // If ecc_mon_enable=0: write accepted, OKAY, no state change.
              axi_bresp_d = `AXIL_ECC_RESP_OKAY;
            end

            // ----------------------------------------------------------------
            // 0x10 : ecc_mon_suspect_addr  (RO — firmware may not write)
            // ----------------------------------------------------------------
            `ECC_REG_SUSPECT_ADDR: begin
              axi_bresp_d = `AXIL_ECC_RESP_SLVERR;
            end

            // ----------------------------------------------------------------
            // 0x14 : ecc_mon_status  (RO — firmware may not write)
            // ----------------------------------------------------------------
            `ECC_REG_STATUS: begin
              axi_bresp_d = `AXIL_ECC_RESP_SLVERR;
            end

            // ----------------------------------------------------------------
            // All other byte offsets in the 4 KB window → SLVERR
            // (covers 0x18 … 0xFFC, the entire gap past the last register)
            // ----------------------------------------------------------------
            default: begin
              axi_bresp_d = `AXIL_ECC_RESP_SLVERR;
            end

          endcase
        end else begin
          axi_bresp_d = `AXIL_ECC_RESP_SLVERR;
        end

        axi_bid_d    = aw_id_lat;
        axi_bvalid_d = 1'b1;
        wr_state_d   = WR_RESP;
      end

      // --------------------------------------------------------------------
      WR_RESP: begin
        if (axi_bready_i) begin
          axi_bvalid_d = 1'b0;
          axi_bid_d    = {AXI_ID_WIDTH{1'b0}};
          wr_state_d   = WR_IDLE;
        end
      end

      // --------------------------------------------------------------------
      default: begin
        wr_state_d    = WR_IDLE;
        axi_awready_d = 1'b0;
        axi_wready_d  = 1'b0;
        axi_bvalid_d  = 1'b0;
        aw_done_d     = 1'b0;
        w_done_d      = 1'b0;
      end

    endcase
  end

  // ---- WRITE FSM : sequential (axi_aclk_i domain, active-low reset) ----
  always @(posedge axi_aclk_i, negedge axi_aresetn_i) begin
    if (!axi_aresetn_i) begin
      wr_state              <= WR_IDLE;
      axi_awready           <= 1'b0;
      axi_wready            <= 1'b0;
      axi_bid               <= {AXI_ID_WIDTH{1'b0}};
      axi_bresp             <= 2'b00;
      axi_bvalid            <= 1'b0;
      aw_id_lat             <= {AXI_ID_WIDTH{1'b0}};
      aw_addr_lat           <= {AXI_ADDR_WIDTH{1'b0}};
      aw_wdata_lat          <= {AXI_DATA_WIDTH{1'b0}};
      aw_wstrb_lat          <= 4'h0;
      aw_done               <= 1'b0;
      w_done                <= 1'b0;
      // Architecture registers
      ecc_mon_enable        <= 1'b0;
      ecc_mon_shadow_count  <= 27'h0;
      ecc_mon_shadow_thresh <= 5'h0;
      correctable_seen      <= 1'b0;
      mbist_correlated      <= 1'b0;
      ecc_mon_suspect_addr  <= 32'h0000_0000;
    end else begin
      wr_state              <= wr_state_d;
      axi_awready           <= axi_awready_d;
      axi_wready            <= axi_wready_d;
      axi_bid               <= axi_bid_d;
      axi_bresp             <= axi_bresp_d;
      axi_bvalid            <= axi_bvalid_d;
      aw_id_lat             <= aw_id_lat_d;
      aw_addr_lat           <= aw_addr_lat_d;
      aw_wdata_lat          <= aw_wdata_lat_d;
      aw_wstrb_lat          <= aw_wstrb_lat_d;
      aw_done               <= aw_done_d;
      w_done                <= w_done_d;
      // Architecture registers
      ecc_mon_enable        <= ecc_mon_enable_d;
      ecc_mon_shadow_count  <= ecc_mon_shadow_count_d;
      ecc_mon_shadow_thresh <= ecc_mon_shadow_thresh_d;
      correctable_seen      <= correctable_seen_d;
      mbist_correlated      <= mbist_correlated_d;
      ecc_mon_suspect_addr  <= ecc_mon_suspect_addr_d;
    end
  end

  // ---- Write channel outputs ----
  assign axi_awready_o = axi_awready;
  assign axi_wready_o  = axi_wready;
  assign axi_bid_o     = axi_bid;
  assign axi_bresp_o   = axi_bresp;
  assign axi_bvalid_o  = axi_bvalid;

  // =========================================================================
  // READ FSM
  //   RD_IDLE — accept AR, latch address + ID, advance to RD_DATA
  //   RD_DATA — decode, present RDATA + RVALID, return to RD_IDLE after RREADY
  // =========================================================================
  localparam RD_IDLE = 1'b0;
  localparam RD_DATA = 1'b1;

  reg                                 rd_state,      rd_state_d;
  reg                                 axi_arready,   axi_arready_d;
  reg  [`_AXIL_ECC_ID_WIDTH_-1:0]     ar_id_lat,     ar_id_lat_d;
  reg  [`_AXIL_ECC_ADDR_WIDTH_-1:0]   ar_addr_lat,   ar_addr_lat_d;
  reg  [`_AXIL_ECC_ID_WIDTH_-1:0]     axi_rid,       axi_rid_d;
  reg  [`_AXIL_ECC_DATA_WIDTH_-1:0]   axi_rdata,     axi_rdata_d;
  reg  [1:0]                          axi_rresp,     axi_rresp_d;
  reg                                 axi_rvalid,    axi_rvalid_d;

  wire ar_addr_in_window = (ar_addr_lat[AXI_ADDR_WIDTH-1:12] == `ECC_BASE_PREFIX) ||
                           (ar_addr_lat[AXI_ADDR_WIDTH-1:12] == 20'h00000);

  // ---- READ FSM : combinational ----
  always @(*) begin
    // --- defaults: hold ---
    rd_state_d    = rd_state;
    axi_arready_d = 1'b0;
    ar_id_lat_d   = ar_id_lat;
    ar_addr_lat_d = ar_addr_lat;
    axi_rid_d     = axi_rid;
    axi_rdata_d   = axi_rdata;
    axi_rresp_d   = axi_rresp;
    axi_rvalid_d  = axi_rvalid;

    case (rd_state)

      // --------------------------------------------------------------------
      RD_IDLE: begin
        axi_rvalid_d = 1'b0;
        if (axi_arvalid_i) begin
          axi_arready_d = 1'b1;
          ar_id_lat_d   = axi_arid_i;
          ar_addr_lat_d = axi_araddr_i;
          rd_state_d    = RD_DATA;
        end
      end

      // --------------------------------------------------------------------
      RD_DATA: begin
        axi_arready_d = 1'b0;

        // Present data whenever RVALID is not yet asserted or master is
        // accepting this beat (avoids re-muxing if master stalls RREADY).
        if (!axi_rvalid || axi_rready_i) begin
          if (ar_addr_in_window) begin
            case (ar_addr_lat[11 : AXI_LSB_WIDTH])

              // 0x00 : ecc_mon_enable
              `ECC_REG_ENABLE: begin
                axi_rdata_d = {{(AXI_DATA_WIDTH-1){1'b0}}, ecc_mon_enable};
                axi_rresp_d = `AXIL_ECC_RESP_OKAY;
              end

              // 0x04 : ecc_mon_shadow_count
              `ECC_REG_SHADOW_COUNT: begin
                axi_rdata_d = {{(AXI_DATA_WIDTH-27){1'b0}}, ecc_mon_shadow_count};
                axi_rresp_d = `AXIL_ECC_RESP_OKAY;
              end

              // 0x08 : ecc_mon_shadow_thresh
              `ECC_REG_SHADOW_THRESH: begin
                axi_rdata_d = {{(AXI_DATA_WIDTH-5){1'b0}}, ecc_mon_shadow_thresh};
                axi_rresp_d = `AXIL_ECC_RESP_OKAY;
              end

              // 0x0C : ecc_mon_event — W1C, always reads 0
              `ECC_REG_EVENT: begin
                axi_rdata_d = {AXI_DATA_WIDTH{1'b0}};
                axi_rresp_d = `AXIL_ECC_RESP_OKAY;
              end

              // 0x10 : ecc_mon_suspect_addr (RO)
              `ECC_REG_SUSPECT_ADDR: begin
                axi_rdata_d = ecc_mon_suspect_addr;
                axi_rresp_d = `AXIL_ECC_RESP_OKAY;
              end

              // 0x14 : ecc_mon_status (RO)
              //   Bit 0 = correctable_seen
              //   Bit 1 = mbist_correlated
              `ECC_REG_STATUS: begin
                axi_rdata_d = {{(AXI_DATA_WIDTH-2){1'b0}},
                                mbist_correlated,
                                correctable_seen};
                axi_rresp_d = `AXIL_ECC_RESP_OKAY;
              end

              // All other offsets in the 4 KB window → SLVERR, data = 0
              default: begin
                axi_rdata_d = {AXI_DATA_WIDTH{1'b0}};
                axi_rresp_d = `AXIL_ECC_RESP_SLVERR;
              end

            endcase
          end else begin
            axi_rdata_d = {AXI_DATA_WIDTH{1'b0}};
            axi_rresp_d = `AXIL_ECC_RESP_SLVERR;
          end

          axi_rid_d    = ar_id_lat;
          axi_rvalid_d = 1'b1;

          if (axi_rready_i)
            rd_state_d = RD_IDLE;
        end
      end

      // --------------------------------------------------------------------
      default: begin
        rd_state_d    = RD_IDLE;
        axi_arready_d = 1'b0;
        axi_rvalid_d  = 1'b0;
      end

    endcase
  end

  // ---- READ FSM : sequential ----
  always @(posedge axi_aclk_i, negedge axi_aresetn_i) begin
    if (!axi_aresetn_i) begin
      rd_state    <= RD_IDLE;
      axi_arready <= 1'b0;
      ar_id_lat   <= {AXI_ID_WIDTH{1'b0}};
      ar_addr_lat <= {AXI_ADDR_WIDTH{1'b0}};
      axi_rid     <= {AXI_ID_WIDTH{1'b0}};
      axi_rdata   <= {AXI_DATA_WIDTH{1'b0}};
      axi_rresp   <= 2'b00;
      axi_rvalid  <= 1'b0;
    end else begin
      rd_state    <= rd_state_d;
      axi_arready <= axi_arready_d;
      ar_id_lat   <= ar_id_lat_d;
      ar_addr_lat <= ar_addr_lat_d;
      axi_rid     <= axi_rid_d;
      axi_rdata   <= axi_rdata_d;
      axi_rresp   <= axi_rresp_d;
      axi_rvalid  <= axi_rvalid_d;
    end
  end

  // ---- Read channel outputs ----
  assign axi_arready_o = axi_arready;
  assign axi_rid_o     = axi_rid;
  assign axi_rdata_o   = axi_rdata;
  assign axi_rresp_o   = axi_rresp;
  assign axi_rvalid_o  = axi_rvalid;

  // =========================================================================
  // Confirmed absent:
  //   - No output signal driving MBIST Controller, Watchdog Timer, or DCCM
  //   - No AXI4 burst signals (AWLEN/ARLEN/SIZE/BURST/LOCK/CACHE/QOS/
  //     WLAST/RLAST) — pure AXI4-Lite
  //   - No AWID/ARID tracking beyond single-transaction ID latches
  // =========================================================================

endmodule

`default_nettype wire
