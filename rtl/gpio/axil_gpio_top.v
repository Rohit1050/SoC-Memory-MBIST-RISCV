/* -----------------------------------------------------------------------------
 * Project        : RISC-V SoC / MBIST  —  AXI4-Lite GPIO IP
 * File           : axil_gpio_top.v
 * Module         : axil_gpio_top
 * Description    : AXI4-Lite Slave GPIO top module.
 *
 *                  Provides three 8-bit registers:
 *                    gpio_dir     (R/W) — per-bit direction (1=output, 0=input)
 *                    gpio_out_reg (R/W) — output drive value
 *                    gpio_in_reg  (RO)  — 2-flop synchronized capture of gpio_in_i
 *
 *                  gpio_out_o[i] = gpio_dir[i] & gpio_out_reg[i].
 *                  gpio_out_o is always driven (no tri-state / 1'bz).
 *
 *                  Writes to the RO gpio_in_reg offset (0x008) are silently
 *                  accepted and return OKAY — the synchronized value is not
 *                  corrupted.
 *
 *                  Reads/writes to any other offset in the 4 KB window return
 *                  SLVERR.
 *
 * Memory-map     : GPIO base = 0x4000_2000, window = 4 KB
 *                  Reached from axi_interconnect_wrap_4x7 master port m03
 *                  through the shared AXI4-to-AXI4-Lite bridge.
 *
 * Interface      : AXI4-Lite (DATA_WIDTH=32, ADDR_WIDTH=32, ID_WIDTH=4).
 *                  No burst signals.  Single synchronous active-low reset
 *                  (axi_aresetn_i) — no dual-reset requirement for GPIO.
 *
 * Register map   (offsets from IP base, 4-byte aligned):
 *   0x000  gpio_dir     (R/W, 8-bit) : 1=output, 0=input, per bit
 *   0x004  gpio_out_reg (R/W, 8-bit) : output drive value
 *   0x008  gpio_in_reg  (RO,  8-bit) : synchronized external input capture
 *   others                           : SLVERR
 *
 * Revision History
 *  Rev | Date       | Description
 *  1.0 | 2026-10-03 | Initial release.
 * -----------------------------------------------------------------------------*/
`timescale 1ns/1ps

`default_nettype none

`include "axil_gpio_defines.vh"

module axil_gpio_top #
(
  parameter DATA_WIDTH = `_AXIL_GPIO_DATA_WIDTH_,   // 32
  parameter ADDR_WIDTH = `_AXIL_GPIO_ADDR_WIDTH_,   // 32
  parameter ID_WIDTH   = `_AXIL_GPIO_ID_WIDTH_,     //  4
  parameter RESP_WIDTH = `_AXIL_GPIO_RESP_WIDTH_    //  2
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
  // GPIO physical I/O
  // -------------------------------------------------------------------------
  output wire [`GPIO_WIDTH-1:0]      gpio_out_o,    // Driven output (never tri-state)
  input  wire [`GPIO_WIDTH-1:0]      gpio_in_i      // External input (async)
);

  // =========================================================================
  // Local parameters
  // =========================================================================
  localparam AXI_LSB = 2; // addr[1:0] always 0 on 4-byte-aligned accesses

  // =========================================================================
  // Architectural registers
  // =========================================================================
  reg [`GPIO_WIDTH-1:0] gpio_dir,     gpio_dir_d;
  reg [`GPIO_WIDTH-1:0] gpio_out_reg, gpio_out_reg_d;

  // 2-flop input synchronizer
  reg [`GPIO_WIDTH-1:0] gpio_in_sync0;  // stage 1
  reg [`GPIO_WIDTH-1:0] gpio_in_sync1;  // stage 2 (metastability-resolved)

  // =========================================================================
  // 2-Flop Synchronizer for gpio_in_i
  // =========================================================================
  always @(posedge axi_aclk_i or negedge axi_aresetn_i) begin
    if (!axi_aresetn_i) begin
      gpio_in_sync0 <= {`GPIO_WIDTH{1'b0}};
      gpio_in_sync1 <= {`GPIO_WIDTH{1'b0}};
    end else begin
      gpio_in_sync0 <= gpio_in_i;
      gpio_in_sync1 <= gpio_in_sync0;
    end
  end

  // gpio_in_reg is the stable, synchronized view of the external input pins.
  // It is a wire alias for gpio_in_sync1 — no separate storage register needed.
  wire [`GPIO_WIDTH-1:0] gpio_in_reg_w = gpio_in_sync1;

  // =========================================================================
  // Output drive: masking by direction register
  //   gpio_out_o[i] = gpio_dir[i] ? gpio_out_reg[i] : 1'b0
  //   (output is held low, not tri-stated, when configured as input)
  // =========================================================================
  assign gpio_out_o = gpio_dir & gpio_out_reg;

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

  // Window check: absolute (0x40002_xxx) or relative (0x00000_xxx)
  wire aw_addr_in_window = (aw_addr_lat[ADDR_WIDTH-1:12] == `GPIO_BASE_PREFIX) ||
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
    gpio_dir_d       = gpio_dir;
    gpio_out_reg_d   = gpio_out_reg;

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

        // Accept W channel (can arrive same cycle or independently)
        if (axi_wvalid_i) begin
          axi_wready_d   = 1'b1;
          aw_wdata_lat_d = axi_wdata_i;
          aw_wstrb_lat_d = axi_wstrb_i;
          w_done_d       = 1'b1;
        end

        // Advance only when both channels have been accepted
        if ((axi_awvalid_i || aw_done) && (axi_wvalid_i || w_done))
          wr_state_d = WR_DATA;
      end

      WR_DATA: begin
        axi_awready_d = 1'b0;
        axi_wready_d  = 1'b0;

        if (aw_addr_in_window) begin
          case (aw_addr_lat[11:AXI_LSB])

            // 0x000 : gpio_dir (R/W)
            `GPIO_REG_DIR: begin
              gpio_dir_d  = aw_wdata_lat[`GPIO_WIDTH-1:0];
              axi_bresp_d = `AXIL_GPIO_RESP_OKAY;
            end

            // 0x004 : gpio_out_reg (R/W)
            `GPIO_REG_OUT: begin
              gpio_out_reg_d = aw_wdata_lat[`GPIO_WIDTH-1:0];
              axi_bresp_d    = `AXIL_GPIO_RESP_OKAY;
            end

            // 0x008 : gpio_in_reg (RO) — accept write silently, return OKAY,
            //         do not update any register (synchronized value unaffected)
            `GPIO_REG_IN: begin
              axi_bresp_d = `AXIL_GPIO_RESP_OKAY;
            end

            // All other offsets within the 4 KB window: SLVERR
            default: begin
              axi_bresp_d = `AXIL_GPIO_RESP_SLVERR;
            end

          endcase
        end else begin
          // Address outside the 4 KB window (should not reach here via crossbar,
          // but handled defensively)
          axi_bresp_d = `AXIL_GPIO_RESP_SLVERR;
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

  // Sequential block — write path
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
      gpio_dir      <= {`GPIO_WIDTH{1'b0}};   // all pins input on reset
      gpio_out_reg  <= {`GPIO_WIDTH{1'b0}};
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
      gpio_dir      <= gpio_dir_d;
      gpio_out_reg  <= gpio_out_reg_d;
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

  wire ar_addr_in_window = (ar_addr_lat[ADDR_WIDTH-1:12] == `GPIO_BASE_PREFIX) ||
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

              // 0x000 : gpio_dir
              `GPIO_REG_DIR: begin
                axi_rdata_d = {{(DATA_WIDTH-`GPIO_WIDTH){1'b0}}, gpio_dir};
                axi_rresp_d = `AXIL_GPIO_RESP_OKAY;
              end

              // 0x004 : gpio_out_reg
              `GPIO_REG_OUT: begin
                axi_rdata_d = {{(DATA_WIDTH-`GPIO_WIDTH){1'b0}}, gpio_out_reg};
                axi_rresp_d = `AXIL_GPIO_RESP_OKAY;
              end

              // 0x008 : gpio_in_reg (synchronized input capture)
              `GPIO_REG_IN: begin
                axi_rdata_d = {{(DATA_WIDTH-`GPIO_WIDTH){1'b0}}, gpio_in_reg_w};
                axi_rresp_d = `AXIL_GPIO_RESP_OKAY;
              end

              // All other offsets: SLVERR
              default: begin
                axi_rdata_d = {DATA_WIDTH{1'b0}};
                axi_rresp_d = `AXIL_GPIO_RESP_SLVERR;
              end

            endcase
          end else begin
            axi_rdata_d = {DATA_WIDTH{1'b0}};
            axi_rresp_d = `AXIL_GPIO_RESP_SLVERR;
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
