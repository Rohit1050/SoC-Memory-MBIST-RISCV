/* -----------------------------------------------------------------------------
 * Project        : RISC-V SoC / MBIST  —  AXI4-Lite Watchdog Timer IP
 * File           : axil_wdt_top.v
 * Module         : axil_wdt_top
 * Description    : AXI4-Lite Slave Watchdog Timer top module.
 *                  Provides the AXI4-Lite slave register interface and
 *                  instantiates the wdt_core countdown engine.
 *
 * Memory-map     : Watchdog Timer base = 0x4000_5000, window = 4 KB
 *                  Reached from axi_interconnect_wrap_4x7 master port m06
 *                  through the shared AXI4-to-AXI4-Lite bridge.
 *
 * Sub-modules    :
 *   - wdt_core.v           : Countdown decrementer & timeout engine
 *   - axil_wdt_defines.vh  : Register offsets, word indices, bus defines
 *
 * Register map   (offsets from base 0x4000_5000 or relative):
 *   0x00  wdg_enable      (R/W,   1-bit) : Bit 0 enables countdown
 *   0x04  wdg_load        (R/W,  32-bit) : Reload / timeout period (cycles)
 *   0x08  wdg_kick        (W,    32-bit) : Pet watchdog (reloads count)
 *   0x0C  wdg_count       (RO,   32-bit) : Current countdown value
 *   0x10  wdg_status      (R/W1C, 1-bit) : Bit 0: timeout_occurred (latched across reset)
 *   0x14  wdg_pretimeout  (R/W,  32-bit) : Early-warning IRQ threshold
 *   others —             (SLVERR)
 * -----------------------------------------------------------------------------*/
`timescale 1ns/1ps

`default_nettype none

`include "axil_wdt_defines.vh"

module axil_wdt_top #
(
  parameter DEFAULT_LOAD       = 32'd0,
  parameter DEFAULT_PRETIMEOUT = 32'd0
)
(
  // -------------------------------------------------------------------------
  // Clock & resets
  // -------------------------------------------------------------------------
  input  wire                                    axi_aclk_i,     // System / bus clock
  input  wire                                    axi_aresetn_i,  // Active-low synchronous system reset
  input  wire                                    por_rstn_i,     // Active-low power-on / cold reset

  // -------------------------------------------------------------------------
  // AXI4-Lite Write Address channel (AW)
  // -------------------------------------------------------------------------
  input  wire [`_AXIL_WDT_ID_WIDTH_-1:0]         axi_awid_i,
  input  wire [`_AXIL_WDT_ADDR_WIDTH_-1:0]       axi_awaddr_i,
  input  wire [2:0]                              axi_awprot_i,   // accepted, not decoded
  input  wire                                    axi_awvalid_i,
  output wire                                    axi_awready_o,

  // -------------------------------------------------------------------------
  // AXI4-Lite Write Data channel (W)
  // -------------------------------------------------------------------------
  input  wire [`_AXIL_WDT_DATA_WIDTH_-1:0]       axi_wdata_i,
  input  wire [`_AXIL_WDT_DATA_WIDTH_/8-1:0]     axi_wstrb_i,
  input  wire                                    axi_wvalid_i,
  output wire                                    axi_wready_o,

  // -------------------------------------------------------------------------
  // AXI4-Lite Write Response channel (B)
  // -------------------------------------------------------------------------
  output wire [`_AXIL_WDT_ID_WIDTH_-1:0]         axi_bid_o,
  output wire [`_AXIL_WDT_RESP_WIDTH_-1:0]       axi_bresp_o,
  output wire                                    axi_bvalid_o,
  input  wire                                    axi_bready_i,

  // -------------------------------------------------------------------------
  // AXI4-Lite Read Address channel (AR)
  // -------------------------------------------------------------------------
  input  wire [`_AXIL_WDT_ID_WIDTH_-1:0]         axi_arid_i,
  input  wire [`_AXIL_WDT_ADDR_WIDTH_-1:0]       axi_araddr_i,
  input  wire [2:0]                              axi_arprot_i,   // accepted, not decoded
  input  wire                                    axi_arvalid_i,
  output wire                                    axi_arready_o,

  // -------------------------------------------------------------------------
  // AXI4-Lite Read Data channel (R)
  // -------------------------------------------------------------------------
  output wire [`_AXIL_WDT_ID_WIDTH_-1:0]         axi_rid_o,
  output wire [`_AXIL_WDT_DATA_WIDTH_-1:0]       axi_rdata_o,
  output wire [`_AXIL_WDT_RESP_WIDTH_-1:0]       axi_rresp_o,
  output wire                                    axi_rvalid_o,
  input  wire                                    axi_rready_i,

  // -------------------------------------------------------------------------
  // Dedicated point-to-point / interrupt outputs
  // -------------------------------------------------------------------------
  output wire                                    wdg_timeout_o,        // Reset logic trigger
  output wire                                    wdg_irq_pretimeout_o, // Early-warning interrupt to PIC
  output wire                                    timeout_occurred_o    // Status flag tap
);

  // =========================================================================
  // Local parameters (sizing)
  // =========================================================================
  localparam AXI_DATA_WIDTH = `_AXIL_WDT_DATA_WIDTH_;  // 32
  localparam AXI_ADDR_WIDTH = `_AXIL_WDT_ADDR_WIDTH_;  // 32
  localparam AXI_ID_WIDTH   = `_AXIL_WDT_ID_WIDTH_;    //  4
  localparam AXI_RESP_WIDTH = `_AXIL_WDT_RESP_WIDTH_;  //  2
  localparam AXI_LSB_WIDTH  = 2;                       // byte-offset to word-offset

  // =========================================================================
  // Architectural registers (Software Configurable)
  // =========================================================================
  reg                 wdg_enable,      wdg_enable_d;
  reg  [31:0]         wdg_load,        wdg_load_d;
  reg  [31:0]         wdg_pretimeout,  wdg_pretimeout_d;

  // Pulses to wdt_core
  reg                 kick_pulse;
  reg                 w1c_clear_pulse;

  // Wires from wdt_core
  wire [31:0]         wdg_count_w;
  wire                timeout_occurred_w;

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
  reg  [`_AXIL_WDT_ID_WIDTH_-1:0]     aw_id_lat,     aw_id_lat_d;
  reg  [`_AXIL_WDT_ADDR_WIDTH_-1:0]   aw_addr_lat,   aw_addr_lat_d;
  reg                                 aw_done,       aw_done_d;

  reg                                 axi_wready,    axi_wready_d;
  reg  [`_AXIL_WDT_DATA_WIDTH_-1:0]   aw_wdata_lat,  aw_wdata_lat_d;
  reg  [3:0]                          aw_wstrb_lat,  aw_wstrb_lat_d;
  reg                                 w_done,        w_done_d;

  reg  [`_AXIL_WDT_ID_WIDTH_-1:0]     axi_bid,       axi_bid_d;
  reg  [1:0]                          axi_bresp,     axi_bresp_d;
  reg                                 axi_bvalid,    axi_bvalid_d;

  // Window check: either relative (prefix 0x00000) or absolute (prefix 0x40005)
  wire aw_addr_in_window = (aw_addr_lat[AXI_ADDR_WIDTH-1:12] == `WDT_BASE_PREFIX) ||
                           (aw_addr_lat[AXI_ADDR_WIDTH-1:12] == 20'h00000);

  // ---- WRITE FSM : combinational next-state logic ----
  always @(*) begin
    // --- defaults: hold ---
    wr_state_d           = wr_state;
    axi_awready_d        = 1'b0;
    axi_wready_d         = axi_wready;
    axi_bid_d            = axi_bid;
    axi_bresp_d          = axi_bresp;
    axi_bvalid_d         = axi_bvalid;
    aw_id_lat_d          = aw_id_lat;
    aw_addr_lat_d        = aw_addr_lat;
    aw_wdata_lat_d       = aw_wdata_lat;
    aw_wstrb_lat_d       = aw_wstrb_lat;
    aw_done_d            = aw_done;
    w_done_d             = w_done;

    // Registers: hold
    wdg_enable_d         = wdg_enable;
    wdg_load_d           = wdg_load;
    wdg_pretimeout_d     = wdg_pretimeout;
    kick_pulse           = 1'b0;
    w1c_clear_pulse      = 1'b0;

    case (wr_state)

      WR_IDLE: begin
        axi_bvalid_d = 1'b0;
        aw_done_d    = 1'b0;
        w_done_d     = 1'b0;

        if (axi_awvalid_i) begin
          axi_awready_d = 1'b1;
          aw_id_lat_d   = axi_awid_i;
          aw_addr_lat_d = axi_awaddr_i;
          aw_done_d     = 1'b1;
        end

        if (axi_wvalid_i) begin
          axi_wready_d   = 1'b1;
          aw_wdata_lat_d = axi_wdata_i;
          aw_wstrb_lat_d = axi_wstrb_i;
          w_done_d       = 1'b1;
        end

        if ((axi_awvalid_i || aw_done) && (axi_wvalid_i || w_done))
          wr_state_d = WR_DATA;
      end

      WR_DATA: begin
        axi_awready_d = 1'b0;
        axi_wready_d  = 1'b0;

        if (aw_addr_in_window) begin
          case (aw_addr_lat[11 : AXI_LSB_WIDTH])

            // 0x00 : wdg_enable
            `WDT_REG_ENABLE: begin
              wdg_enable_d = aw_wdata_lat[0];
              axi_bresp_d  = `AXIL_WDT_RESP_OKAY;
            end

            // 0x04 : wdg_load
            `WDT_REG_LOAD: begin
              wdg_load_d  = aw_wdata_lat;
              axi_bresp_d = `AXIL_WDT_RESP_OKAY;
            end

            // 0x08 : wdg_kick — pet watchdog
            `WDT_REG_KICK: begin
              kick_pulse  = 1'b1;
              axi_bresp_d = `AXIL_WDT_RESP_OKAY;
            end

            // 0x0C : wdg_count (RO)
            `WDT_REG_COUNT: begin
              axi_bresp_d = `AXIL_WDT_RESP_SLVERR;
            end

            // 0x10 : wdg_status (R/W1C)
            `WDT_REG_STATUS: begin
              if (aw_wdata_lat[`WDT_STATUS_TIMEOUT_BIT]) begin
                w1c_clear_pulse = 1'b1;
              end
              axi_bresp_d = `AXIL_WDT_RESP_OKAY;
            end

            // 0x14 : wdg_pretimeout
            `WDT_REG_PRETIMEOUT: begin
              wdg_pretimeout_d = aw_wdata_lat;
              axi_bresp_d      = `AXIL_WDT_RESP_OKAY;
            end

            default: begin
              axi_bresp_d = `AXIL_WDT_RESP_SLVERR;
            end

          endcase
        end else begin
          axi_bresp_d = `AXIL_WDT_RESP_SLVERR;
        end

        axi_bid_d    = aw_id_lat;
        axi_bvalid_d = 1'b1;
        wr_state_d   = WR_RESP;
      end

      WR_RESP: begin
        if (axi_bready_i) begin
          axi_bvalid_d = 1'b0;
          axi_bid_d    = {AXI_ID_WIDTH{1'b0}};
          wr_state_d   = WR_IDLE;
        end
      end

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

  // ---- WRITE FSM Sequential Block ----
  always @(posedge axi_aclk_i, negedge axi_aresetn_i) begin
    if (!axi_aresetn_i) begin
      wr_state            <= WR_IDLE;
      axi_awready         <= 1'b0;
      axi_wready          <= 1'b0;
      axi_bid             <= {AXI_ID_WIDTH{1'b0}};
      axi_bresp           <= 2'b00;
      axi_bvalid          <= 1'b0;
      aw_id_lat           <= {AXI_ID_WIDTH{1'b0}};
      aw_addr_lat         <= {AXI_ADDR_WIDTH{1'b0}};
      aw_wdata_lat        <= {AXI_DATA_WIDTH{1'b0}};
      aw_wstrb_lat        <= 4'h0;
      aw_done             <= 1'b0;
      w_done              <= 1'b0;
      wdg_enable          <= 1'b0;
      wdg_load            <= DEFAULT_LOAD;
      wdg_pretimeout      <= DEFAULT_PRETIMEOUT;
    end else begin
      wr_state            <= wr_state_d;
      axi_awready         <= axi_awready_d;
      axi_wready          <= axi_wready_d;
      axi_bid             <= axi_bid_d;
      axi_bresp           <= axi_bresp_d;
      axi_bvalid          <= axi_bvalid_d;
      aw_id_lat           <= aw_id_lat_d;
      aw_addr_lat         <= aw_addr_lat_d;
      aw_wdata_lat        <= aw_wdata_lat_d;
      aw_wstrb_lat        <= aw_wstrb_lat_d;
      aw_done             <= aw_done_d;
      w_done              <= w_done_d;
      wdg_enable          <= wdg_enable_d;
      wdg_load            <= wdg_load_d;
      wdg_pretimeout      <= wdg_pretimeout_d;
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
  reg  [`_AXIL_WDT_ID_WIDTH_-1:0]     ar_id_lat,     ar_id_lat_d;
  reg  [`_AXIL_WDT_ADDR_WIDTH_-1:0]   ar_addr_lat,   ar_addr_lat_d;
  reg  [`_AXIL_WDT_ID_WIDTH_-1:0]     axi_rid,       axi_rid_d;
  reg  [`_AXIL_WDT_DATA_WIDTH_-1:0]   axi_rdata,     axi_rdata_d;
  reg  [1:0]                          axi_rresp,     axi_rresp_d;
  reg                                 axi_rvalid,    axi_rvalid_d;

  wire ar_addr_in_window = (ar_addr_lat[AXI_ADDR_WIDTH-1:12] == `WDT_BASE_PREFIX) ||
                           (ar_addr_lat[AXI_ADDR_WIDTH-1:12] == 20'h00000);

  // ---- READ FSM : combinational ----
  always @(*) begin
    rd_state_d    = rd_state;
    axi_arready_d = 1'b0;
    ar_id_lat_d   = ar_id_lat;
    ar_addr_lat_d = ar_addr_lat;
    axi_rid_d     = axi_rid;
    axi_rdata_d   = axi_rdata;
    axi_rresp_d   = axi_rresp;
    axi_rvalid_d  = axi_rvalid;

    case (rd_state)

      RD_IDLE: begin
        axi_rvalid_d = 1'b0;
        if (axi_arvalid_i) begin
          axi_arready_d = 1'b1;
          ar_id_lat_d   = axi_arid_i;
          ar_addr_lat_d = axi_araddr_i;
          rd_state_d    = RD_DATA;
        end
      end

      RD_DATA: begin
        axi_arready_d = 1'b0;

        if (!axi_rvalid || axi_rready_i) begin
          if (ar_addr_in_window) begin
            case (ar_addr_lat[11 : AXI_LSB_WIDTH])

              // 0x00 : wdg_enable
              `WDT_REG_ENABLE: begin
                axi_rdata_d = {{(AXI_DATA_WIDTH-1){1'b0}}, wdg_enable};
                axi_rresp_d = `AXIL_WDT_RESP_OKAY;
              end

              // 0x04 : wdg_load
              `WDT_REG_LOAD: begin
                axi_rdata_d = wdg_load;
                axi_rresp_d = `AXIL_WDT_RESP_OKAY;
              end

              // 0x08 : wdg_kick — reads 0
              `WDT_REG_KICK: begin
                axi_rdata_d = {AXI_DATA_WIDTH{1'b0}};
                axi_rresp_d = `AXIL_WDT_RESP_OKAY;
              end

              // 0x0C : wdg_count (RO)
              `WDT_REG_COUNT: begin
                axi_rdata_d = wdg_count_w;
                axi_rresp_d = `AXIL_WDT_RESP_OKAY;
              end

              // 0x10 : wdg_status (RO) — bit 0: timeout_occurred
              `WDT_REG_STATUS: begin
                axi_rdata_d = {{(AXI_DATA_WIDTH-1){1'b0}}, timeout_occurred_w};
                axi_rresp_d = `AXIL_WDT_RESP_OKAY;
              end

              // 0x14 : wdg_pretimeout
              `WDT_REG_PRETIMEOUT: begin
                axi_rdata_d = wdg_pretimeout;
                axi_rresp_d = `AXIL_WDT_RESP_OKAY;
              end

              default: begin
                axi_rdata_d = {AXI_DATA_WIDTH{1'b0}};
                axi_rresp_d = `AXIL_WDT_RESP_SLVERR;
              end

            endcase
          end else begin
            axi_rdata_d = {AXI_DATA_WIDTH{1'b0}};
            axi_rresp_d = `AXIL_WDT_RESP_SLVERR;
          end

          axi_rid_d    = ar_id_lat;
          axi_rvalid_d = 1'b1;

          if (axi_rready_i)
            rd_state_d = RD_IDLE;
        end
      end

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
  // Watchdog Core Datapath Instantiation
  // =========================================================================
  wdt_core #(
    .DEFAULT_LOAD       (DEFAULT_LOAD),
    .DEFAULT_PRETIMEOUT (DEFAULT_PRETIMEOUT)
  ) u_wdt_core (
    .clk_i              (axi_aclk_i),
    .rst_n_i            (axi_aresetn_i),
    .por_rstn_i         (por_rstn_i),

    .enable_i           (wdg_enable),
    .load_val_i         (wdg_load),
    .kick_i             (kick_pulse),
    .pretimeout_val_i   (wdg_pretimeout),
    .w1c_status_clear_i (w1c_clear_pulse),

    .count_o            (wdg_count_w),
    .timeout_o          (wdg_timeout_o),
    .pretimeout_irq_o   (wdg_irq_pretimeout_o),
    .timeout_occurred_o (timeout_occurred_w)
  );

  assign timeout_occurred_o = timeout_occurred_w;

endmodule

`default_nettype wire
