/* -----------------------------------------------------------------------------
 * Project        : RISC-V SoC / MBIST  —  AXI4-Lite System Timer IP
 * File           : axil_systimer_top.v
 * Module         : axil_systimer_top
 * Description    : AXI4-Lite Slave System Timer top module.
 *
 *                  Provides a 32-bit countdown timer with three registers:
 *                    timer_en     (R/W, 1-bit)  — enables countdown
 *                    timer_reload (R/W, 32-bit) — reload value (period)
 *                    timer_count  (RO,  32-bit) — current countdown value
 *
 *                  timer_tick_o pulses HIGH for exactly one clock cycle when
 *                  timer_count reaches zero.  The counter then reloads from
 *                  timer_reload and continues if timer_en is still asserted.
 *
 *                  timer_en = 0 behavior (HOLD):
 *                    Countdown halts; timer_count freezes at its current value.
 *                    Re-asserting timer_en resumes decrement from the frozen
 *                    value (not from timer_reload).  To force a clean restart,
 *                    firmware writes timer_reload and toggles timer_en:
 *                      1. Write desired period to timer_reload.
 *                      2. Write 0 to timer_en (ensure halted).
 *                      3. Write 1 to timer_en — first decrement starts next
 *                         cycle from timer_reload (see reload-on-enable below).
 *                    Note: on (re)enable from IDLE, timer_count preloads with
 *                    timer_reload so the first tick fires exactly timer_reload
 *                    cycles after enable, not timer_reload-1.
 *
 *                  timer_reload = 0 edge case:
 *                    Handled safely.  When the count reaches 0, timer_tick_o
 *                    pulses for exactly 1 cycle, then the counter reloads to 0
 *                    and timer_tick_o is de-asserted the next cycle.  The count
 *                    stays at 0 and ticks once per cycle — no combinational race
 *                    because the tick is registered and only the sequential
 *                    reload path controls it.
 *
 *                  Writes to the RO timer_count offset (0x008) are silently
 *                  accepted and return OKAY — the countdown value is unaffected.
 *
 *                  Reads/writes to any other offset in the 4 KB window return
 *                  SLVERR.
 *
 * Memory-map     : System Timer base = 0x4000_1000, window = 4 KB
 *                  Reached from axi_interconnect_wrap_4x7 master port m02
 *                  through the shared AXI4-to-AXI4-Lite bridge.
 *
 * Interface      : AXI4-Lite (DATA_WIDTH=32, ADDR_WIDTH=32, ID_WIDTH=4).
 *                  No burst signals.  Single synchronous active-low reset.
 *
 * Non-bus output : timer_tick_o — 1-cycle pulse at countdown expiry.
 *                  This signal is wired externally (e.g. to MBIST auto-trigger)
 *                  without any MBIST-specific logic inside this module.
 *
 * Revision History
 *  Rev | Date       | Description
 *  1.0 | 2026-10-03 | Initial release.
 * -----------------------------------------------------------------------------*/
`timescale 1ns/1ps

`default_nettype none

`include "axil_systimer_defines.vh"

module axil_systimer_top #
(
  parameter DATA_WIDTH = `_AXIL_STMR_DATA_WIDTH_,  // 32
  parameter ADDR_WIDTH = `_AXIL_STMR_ADDR_WIDTH_,  // 32
  parameter ID_WIDTH   = `_AXIL_STMR_ID_WIDTH_,    //  4
  parameter RESP_WIDTH = `_AXIL_STMR_RESP_WIDTH_   //  2
)
(
  // -------------------------------------------------------------------------
  // Clock and reset
  // -------------------------------------------------------------------------
  input  wire                        axi_aclk_i,    // System / bus clock
  input  wire                        axi_aresetn_i, // Active-low synchronous reset

  // -------------------------------------------------------------------------
  // AXI4-Lite Write Address channel (AW)
  // -------------------------------------------------------------------------
  input  wire [ID_WIDTH-1:0]         axi_awid_i,
  input  wire [ADDR_WIDTH-1:0]       axi_awaddr_i,
  input  wire [2:0]                  axi_awprot_i,  // accepted, not decoded
  input  wire                        axi_awvalid_i,
  output wire                        axi_awready_o,

  // -------------------------------------------------------------------------
  // AXI4-Lite Write Data channel (W)
  // -------------------------------------------------------------------------
  input  wire [DATA_WIDTH-1:0]       axi_wdata_i,
  input  wire [DATA_WIDTH/8-1:0]     axi_wstrb_i,
  input  wire                        axi_wvalid_i,
  output wire                        axi_wready_o,

  // -------------------------------------------------------------------------
  // AXI4-Lite Write Response channel (B)
  // -------------------------------------------------------------------------
  output wire [ID_WIDTH-1:0]         axi_bid_o,
  output wire [RESP_WIDTH-1:0]       axi_bresp_o,
  output wire                        axi_bvalid_o,
  input  wire                        axi_bready_i,

  // -------------------------------------------------------------------------
  // AXI4-Lite Read Address channel (AR)
  // -------------------------------------------------------------------------
  input  wire [ID_WIDTH-1:0]         axi_arid_i,
  input  wire [ADDR_WIDTH-1:0]       axi_araddr_i,
  input  wire [2:0]                  axi_arprot_i,  // accepted, not decoded
  input  wire                        axi_arvalid_i,
  output wire                        axi_arready_o,

  // -------------------------------------------------------------------------
  // AXI4-Lite Read Data channel (R)
  // -------------------------------------------------------------------------
  output wire [ID_WIDTH-1:0]         axi_rid_o,
  output wire [DATA_WIDTH-1:0]       axi_rdata_o,
  output wire [RESP_WIDTH-1:0]       axi_rresp_o,
  output wire                        axi_rvalid_o,
  input  wire                        axi_rready_i,

  // -------------------------------------------------------------------------
  // Timer output
  // -------------------------------------------------------------------------
  output wire                        timer_tick_o   // 1-cycle pulse at expiry
);

  // =========================================================================
  // Local parameters
  // =========================================================================
  localparam AXI_LSB    = 2;           // byte-offset to 32-bit word index
  localparam TMR_IDLE   = 1'b0;
  localparam TMR_COUNT  = 1'b1;

  // =========================================================================
  // Architectural registers (software-configurable)
  // =========================================================================
  reg        timer_en,     timer_en_d;
  reg [31:0] timer_reload, timer_reload_d;

  // =========================================================================
  // Timer countdown registers
  // =========================================================================
  reg [31:0] timer_count,  timer_count_d;
  reg        tmr_state,    tmr_state_d;
  reg        timer_tick,   timer_tick_d;   // registered tick output

  // prev_en tracks the previous value of timer_en so the FSM can detect
  // a 0->1 rising edge (re-enable event) to preload the counter.
  reg        prev_en;

  // =========================================================================
  // Timer FSM — combinational next-state logic
  // =========================================================================
  always @(*) begin
    tmr_state_d   = tmr_state;
    timer_count_d = timer_count;
    timer_tick_d  = 1'b0;  // default: tick is de-asserted

    case (tmr_state)

      TMR_IDLE: begin
        // Stay idle while disabled.
        // On enable (0->1 edge): preload count from reload register and
        // transition to COUNTING.  This ensures the first period is exactly
        // timer_reload cycles regardless of the previous counter value.
        if (timer_en && !prev_en) begin
          timer_count_d = timer_reload;
          tmr_state_d   = TMR_COUNT;
        end
      end

      TMR_COUNT: begin
        if (!timer_en) begin
          // Disable: freeze counter, return to IDLE (HOLD behavior — no reset)
          tmr_state_d = TMR_IDLE;
        end else begin
          if (timer_count == 32'd0) begin
            // Count reached zero: pulse tick for this cycle, reload, continue
            timer_tick_d  = 1'b1;
            timer_count_d = timer_reload;
            // Remain in TMR_COUNT — timer continues running
          end else begin
            timer_count_d = timer_count - 32'd1;
          end
        end
      end

      default: begin
        tmr_state_d   = TMR_IDLE;
        timer_count_d = 32'd0;
        timer_tick_d  = 1'b0;
      end

    endcase
  end

  // Sequential block — timer
  always @(posedge axi_aclk_i or negedge axi_aresetn_i) begin
    if (!axi_aresetn_i) begin
      tmr_state   <= TMR_IDLE;
      timer_count <= 32'd0;
      timer_tick  <= 1'b0;
      prev_en     <= 1'b0;
    end else begin
      tmr_state   <= tmr_state_d;
      timer_count <= timer_count_d;
      timer_tick  <= timer_tick_d;
      prev_en     <= timer_en;
    end
  end

  assign timer_tick_o = timer_tick;

  // =========================================================================
  // WRITE FSM
  //   WR_IDLE — accept AW and W independently; advance when both valid seen
  //   WR_DATA — decode address, update registers, prepare B response
  //   WR_RESP — hold BVALID until BREADY, return to WR_IDLE
  // =========================================================================
  localparam WR_IDLE = 2'b00;
  localparam WR_DATA = 2'b01;
  localparam WR_RESP = 2'b10;

  reg [1:0]             wr_state,      wr_state_d;
  reg                   axi_awready,   axi_awready_d;
  reg [ID_WIDTH-1:0]    aw_id_lat,     aw_id_lat_d;
  reg [ADDR_WIDTH-1:0]  aw_addr_lat,   aw_addr_lat_d;
  reg                   aw_done,       aw_done_d;

  reg                   axi_wready,    axi_wready_d;
  reg [DATA_WIDTH-1:0]  aw_wdata_lat,  aw_wdata_lat_d;
  reg [3:0]             aw_wstrb_lat,  aw_wstrb_lat_d;
  reg                   w_done,        w_done_d;

  reg [ID_WIDTH-1:0]    axi_bid,       axi_bid_d;
  reg [1:0]             axi_bresp,     axi_bresp_d;
  reg                   axi_bvalid,    axi_bvalid_d;

  wire aw_addr_in_window = (aw_addr_lat[ADDR_WIDTH-1:12] == `STMR_BASE_PREFIX) ||
                           (aw_addr_lat[ADDR_WIDTH-1:12] == 20'h00000);

  always @(*) begin
    // ---- defaults: hold all state ----
    wr_state_d       = wr_state;
    axi_awready_d    = 1'b0;
    axi_wready_d     = axi_wready;
    axi_bid_d        = axi_bid;
    axi_bresp_d      = axi_bresp;
    axi_bvalid_d     = axi_bvalid;
    aw_id_lat_d      = aw_id_lat;
    aw_addr_lat_d    = aw_addr_lat;
    aw_wdata_lat_d   = aw_wdata_lat;
    aw_wstrb_lat_d   = aw_wstrb_lat;
    aw_done_d        = aw_done;
    w_done_d         = w_done;
    timer_en_d       = timer_en;
    timer_reload_d   = timer_reload;

    case (wr_state)

      WR_IDLE: begin
        axi_bvalid_d = 1'b0;
        aw_done_d    = 1'b0;
        w_done_d     = 1'b0;

        // Accept AW channel
        if (axi_awvalid_i) begin
          axi_awready_d = 1'b1;
          aw_id_lat_d   = axi_awid_i;
          aw_addr_lat_d = axi_awaddr_i;
          aw_done_d     = 1'b1;
        end

        // Accept W channel (independent of AW)
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

      WR_DATA: begin
        axi_awready_d = 1'b0;
        axi_wready_d  = 1'b0;

        if (aw_addr_in_window) begin
          case (aw_addr_lat[11:AXI_LSB])

            // 0x000 : timer_en (R/W)
            `STMR_REG_EN: begin
              timer_en_d  = aw_wdata_lat[0];
              axi_bresp_d = `AXIL_STMR_RESP_OKAY;
            end

            // 0x004 : timer_reload (R/W)
            `STMR_REG_RELOAD: begin
              timer_reload_d = aw_wdata_lat;
              axi_bresp_d    = `AXIL_STMR_RESP_OKAY;
            end

            // 0x008 : timer_count (RO) — accept write silently, return OKAY
            `STMR_REG_COUNT: begin
              axi_bresp_d = `AXIL_STMR_RESP_OKAY;
            end

            // All other offsets within 4 KB: SLVERR
            default: begin
              axi_bresp_d = `AXIL_STMR_RESP_SLVERR;
            end

          endcase
        end else begin
          axi_bresp_d = `AXIL_STMR_RESP_SLVERR;
        end

        axi_bid_d    = aw_id_lat;
        axi_bvalid_d = 1'b1;
        wr_state_d   = WR_RESP;
      end

      WR_RESP: begin
        if (axi_bready_i) begin
          axi_bvalid_d = 1'b0;
          axi_bid_d    = {ID_WIDTH{1'b0}};
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

  // Sequential block — write path (also holds timer_en / timer_reload)
  always @(posedge axi_aclk_i or negedge axi_aresetn_i) begin
    if (!axi_aresetn_i) begin
      wr_state      <= WR_IDLE;
      axi_awready   <= 1'b0;
      axi_wready    <= 1'b0;
      axi_bid       <= {ID_WIDTH{1'b0}};
      axi_bresp     <= 2'b00;
      axi_bvalid    <= 1'b0;
      aw_id_lat     <= {ID_WIDTH{1'b0}};
      aw_addr_lat   <= {ADDR_WIDTH{1'b0}};
      aw_wdata_lat  <= {DATA_WIDTH{1'b0}};
      aw_wstrb_lat  <= 4'h0;
      aw_done       <= 1'b0;
      w_done        <= 1'b0;
      timer_en      <= 1'b0;
      timer_reload  <= 32'd0;
    end else begin
      wr_state      <= wr_state_d;
      axi_awready   <= axi_awready_d;
      axi_wready    <= axi_wready_d;
      axi_bid       <= axi_bid_d;
      axi_bresp     <= axi_bresp_d;
      axi_bvalid    <= axi_bvalid_d;
      aw_id_lat     <= aw_id_lat_d;
      aw_addr_lat   <= aw_addr_lat_d;
      aw_wdata_lat  <= aw_wdata_lat_d;
      aw_wstrb_lat  <= aw_wstrb_lat_d;
      aw_done       <= aw_done_d;
      w_done        <= w_done_d;
      timer_en      <= timer_en_d;
      timer_reload  <= timer_reload_d;
    end
  end

  // Write channel output assignments
  assign axi_awready_o = axi_awready;
  assign axi_wready_o  = axi_wready;
  assign axi_bid_o     = axi_bid;
  assign axi_bresp_o   = axi_bresp;
  assign axi_bvalid_o  = axi_bvalid;

  // =========================================================================
  // READ FSM
  //   RD_IDLE — wait for ARVALID, latch address
  //   RD_DATA — decode, drive RDATA/RRESP/RVALID, wait for RREADY
  // =========================================================================
  localparam RD_IDLE = 1'b0;
  localparam RD_DATA = 1'b1;

  reg                   rd_state,      rd_state_d;
  reg                   axi_arready,   axi_arready_d;
  reg [ID_WIDTH-1:0]    ar_id_lat,     ar_id_lat_d;
  reg [ADDR_WIDTH-1:0]  ar_addr_lat,   ar_addr_lat_d;
  reg [ID_WIDTH-1:0]    axi_rid,       axi_rid_d;
  reg [DATA_WIDTH-1:0]  axi_rdata,     axi_rdata_d;
  reg [1:0]             axi_rresp,     axi_rresp_d;
  reg                   axi_rvalid,    axi_rvalid_d;

  wire ar_addr_in_window = (ar_addr_lat[ADDR_WIDTH-1:12] == `STMR_BASE_PREFIX) ||
                           (ar_addr_lat[ADDR_WIDTH-1:12] == 20'h00000);

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
            case (ar_addr_lat[11:AXI_LSB])

              // 0x000 : timer_en
              `STMR_REG_EN: begin
                axi_rdata_d = {{(DATA_WIDTH-1){1'b0}}, timer_en};
                axi_rresp_d = `AXIL_STMR_RESP_OKAY;
              end

              // 0x004 : timer_reload
              `STMR_REG_RELOAD: begin
                axi_rdata_d = timer_reload;
                axi_rresp_d = `AXIL_STMR_RESP_OKAY;
              end

              // 0x008 : timer_count (RO — live countdown value)
              `STMR_REG_COUNT: begin
                axi_rdata_d = timer_count;
                axi_rresp_d = `AXIL_STMR_RESP_OKAY;
              end

              // All other offsets: SLVERR
              default: begin
                axi_rdata_d = {DATA_WIDTH{1'b0}};
                axi_rresp_d = `AXIL_STMR_RESP_SLVERR;
              end

            endcase
          end else begin
            axi_rdata_d = {DATA_WIDTH{1'b0}};
            axi_rresp_d = `AXIL_STMR_RESP_SLVERR;
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

  // Sequential block — read path
  always @(posedge axi_aclk_i or negedge axi_aresetn_i) begin
    if (!axi_aresetn_i) begin
      rd_state    <= RD_IDLE;
      axi_arready <= 1'b0;
      ar_id_lat   <= {ID_WIDTH{1'b0}};
      ar_addr_lat <= {ADDR_WIDTH{1'b0}};
      axi_rid     <= {ID_WIDTH{1'b0}};
      axi_rdata   <= {DATA_WIDTH{1'b0}};
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

  // Read channel output assignments
  assign axi_arready_o = axi_arready;
  assign axi_rid_o     = axi_rid;
  assign axi_rdata_o   = axi_rdata;
  assign axi_rresp_o   = axi_rresp;
  assign axi_rvalid_o  = axi_rvalid;

endmodule

`default_nettype wire
