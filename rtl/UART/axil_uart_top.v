/* -----------------------------------------------------------------------------
 * Project        : RISC-V SoC / MBIST  —  AXI4-Lite UART IP
 * File           : axil_uart_top.v
 * Module         : axil_uart_top
 * Description    : AXI4-Lite Slave UART  —  dual-FSM (write / read) with
 *                  FIFO-backed TX and RX paths and 16550-compatible register map.
 *
 * Memory-map     : UART base = 0x4000_0000, window = 4 KB
 *                  Reached from axi_interconnect_wrap_4x7 master port m01
 *                  through the AXI4-to-AXI4-Lite bridge.
 *
 * Interface      : AXI4-Lite (no burst channels).
 *                    ADDR_WIDTH = 32   (matches crossbar ADDR_WIDTH)
 *                    DATA_WIDTH = 32   (Lite-side; bridge handles 64→32 conversion)
 *                    ID_WIDTH   = 4    (matches crossbar ID_WIDTH=4)
 *
 * Register map   :
 *   Offset  Name          Access  Description
 *   0x000   RBR           R       Receive  Buffer Register  (DLAB=0)
 *   0x000   THR           W       Transmit Holding Register (DLAB=0)
 *   0x004   IER           R/W     Interrupt Enable Register (DLAB=0)
 *   0x008   BAUD_DIVISOR  R/W     Baud-rate Divisor        (DLAB=1 to write)
 *   0x00C   LCR           R/W     Line Control Register
 *   0x014   LSR           R       Line Status Register
 *   others  —             —       SLVERR
 *
 * ⚠  Clock domain note
 *   The module exposes two clock inputs:
 *     fixed_clk_i : UART baud-clock domain (must be ≥16× baud rate).
 *                   All sequential logic in this module is registered on this
 *                   clock, including the AXI4-Lite channel registers.
 *     axi_aclk_i  : AXI bus clock.  Currently unused internally — present to
 *                   match the bridge's expected port list and to allow a future
 *                   integrator to insert two-flop synchronizers between the AXI
 *                   channel inputs and the fixed_clk_i domain.
 *
 *   CONSEQUENCE: If fixed_clk_i ≠ axi_aclk_i the AXI handshake signals
 *   (AWVALID, WVALID, ARVALID, RREADY, BREADY) cross clock domains without
 *   synchronizers inside this module.  The current design is safe only when
 *   the two clocks are the same or are phase-locked.  A future CDC pass should
 *   add two-flop synchronizers on all AXI input signals before moving to an
 *   asynchronous multi-clock system.
 *
 * Derived from   : axi4_uart_top.v (full AXI4, rev 4.0)
 *   Changes       : AXI4 burst channels removed (AWLEN/SIZE/BURST/LOCK/CACHE/
 *                   PROT/QOS, WLAST, ARLEN/SIZE/BURST/LOCK/CACHE/PROT/QOS,
 *                   RLAST).  Module name updated.  Defines file updated.
 *                   Register map and FSM architecture preserved unchanged.
 *
 * Revision History
 *  Rev | Author      | Description
 *  1.0 | aruiz       | First IP (Avalon bus)
 *  2.0 | vkostalamp  | AXI-Bus porting
 *  2.1 | aruiz       | Asynchronous reset
 *  3.0 | aruiz       | Two clock domains
 *  4.0 | HC_CBP_095  | Full AXI4 burst version (axi4_uart_top.v)
 *  5.0 | HC_CBP_095  | AXI4-Lite conversion (this file)
 * -----------------------------------------------------------------------------*/
`timescale 1ns/1ps

`default_nettype none

`include "axil_uart_defines.vh"

/*
Title: axil_uart_top
AXI4-Lite slave UART.  Two decoupled FSMs handle the write and read channels
independently.  The actual UART datapath (uart_controller, RX-FIFO, TX-FIFO)
is unchanged from the AXI4 version.
*/
module axil_uart_top (
  // -------------------------------------------------------------------------
  // Clocks & reset
  //   See clock domain note in the file header above.
  // -------------------------------------------------------------------------
  input  wire        fixed_clk_i,   // UART clock domain (≥16× baud); all FFs here
  input  wire        axi_aclk_i,    // AXI bus clock (present for port compatibility)
  input  wire        axi_aresetn_i, // Active-low synchronous reset (sampled on fixed_clk_i)

  // -------------------------------------------------------------------------
  // AXI4-Lite Write Address channel (AW)
  // -------------------------------------------------------------------------
  input  wire [`_AXI_UART_ID_WIDTH_-1:0]     axi_awid_i,
  input  wire [`_AXI_UART_ADDR_WIDTH_-1:0]   axi_awaddr_i,
  input  wire                                axi_awvalid_i,
  output wire                                axi_awready_o,

  // -------------------------------------------------------------------------
  // AXI4-Lite Write Data channel (W)
  // -------------------------------------------------------------------------
  input  wire [`_AXI_UART_DATA_WIDTH_-1:0]   axi_wdata_i,
  input  wire [`_AXI_UART_DATA_WIDTH_/8-1:0] axi_wstrb_i,
  input  wire                                axi_wvalid_i,
  output wire                                axi_wready_o,

  // -------------------------------------------------------------------------
  // AXI4-Lite Write Response channel (B)
  // -------------------------------------------------------------------------
  output wire [`_AXI_UART_ID_WIDTH_-1:0]     axi_bid_o,
  output wire [`_AXI_UART_RESP_WIDTH_-1:0]   axi_bresp_o,
  output wire                                axi_bvalid_o,
  input  wire                                axi_bready_i,

  // -------------------------------------------------------------------------
  // AXI4-Lite Read Address channel (AR)
  // -------------------------------------------------------------------------
  input  wire [`_AXI_UART_ID_WIDTH_-1:0]     axi_arid_i,
  input  wire [`_AXI_UART_ADDR_WIDTH_-1:0]   axi_araddr_i,
  input  wire                                axi_arvalid_i,
  output wire                                axi_arready_o,

  // -------------------------------------------------------------------------
  // AXI4-Lite Read Data channel (R)
  // -------------------------------------------------------------------------
  output wire [`_AXI_UART_ID_WIDTH_-1:0]     axi_rid_o,
  output wire [`_AXI_UART_DATA_WIDTH_-1:0]   axi_rdata_o,
  output wire [`_AXI_UART_RESP_WIDTH_-1:0]   axi_rresp_o,
  output wire                                axi_rvalid_o,
  input  wire                                axi_rready_i,

  // -------------------------------------------------------------------------
  // UART interface
  // -------------------------------------------------------------------------
  output reg                                 read_interrupt_o,
  input  wire                                uart_rx_i,
  output wire                                uart_tx_o
);

  // =========================================================================
  // Local parameters
  // =========================================================================
  localparam BYTE             = 8;
  localparam AXI_DATA_WIDTH   = `_AXI_UART_DATA_WIDTH_;
  localparam AXI_ADDR_WIDTH   = `_AXI_UART_ADDR_WIDTH_;
  localparam AXI_DIV_WIDTH    = `_AXI_UART_DIV_WIDTH_;
  localparam AXI_ID_WIDTH     = `_AXI_UART_ID_WIDTH_;
  localparam AXI_RESP_WIDTH   = `_AXI_UART_RESP_WIDTH_;
  localparam AXI_FIFO_DEPTH   = `_AXI_UART_FIFO_DEPTH_;
  localparam AXI_FIFO_ADDR    = $clog2(AXI_FIFO_DEPTH);
  localparam AXI_BYTE_NUM     = AXI_DATA_WIDTH / BYTE;
  localparam AXI_LSB_WIDTH    = $clog2(AXI_BYTE_NUM); // byte-lane LSBs to strip

  // UART register map (word indices — compare addr[AXI_ADDR_WIDTH-1 : AXI_LSB_WIDTH])
  localparam UART_RBR          = `_UART_RBR_;
  localparam UART_THR          = `_UART_THR_;
  localparam UART_IER          = `_UART_IER_;
  localparam UART_BAUD_DIVISOR = `_UART_BAUD_DIVISOR_;
  localparam UART_LCR          = `_UART_LCR_;
  localparam UART_LSR          = `_UART_LSR_;

  // LCR / LSR bit positions
  localparam UART_CONFIG_STOP_BITS   = `_UART_CONFIG_STOP_BITS_;
  localparam UART_CONFIG_PARITY_EN   = `_UART_CONFIG_PARITY_EN_;
  localparam UART_CONFIG_PARITY_MODE = `_UART_CONFIG_PARITY_MODE_;
  localparam UART_CONFIG_DLAB        = `_UART_CONFIG_DLAB_;
  localparam UART_LSR_DATA_READY     = `_UART_LSR_DATA_READY_;
  localparam UART_LSR_TEMT           = `_UART_LSR_TEMT_;
  localparam UART_LSR_THRE           = `_UART_LSR_THRE_;

  // UART datapath
  localparam DATA_WIDTH_UART        = `_DATA_WIDTH_UART_;
  localparam UART_BAUDRATE_DIV_INIT = `_UART_BAUDRATE_DIV_INIT_;

  // =========================================================================
  // Internal UART configuration registers
  // =========================================================================
  reg  [AXI_DATA_WIDTH-1:0]  uart_config_reg_int,   uart_config_reg_int_d;
  reg  [AXI_DIV_WIDTH-1:0]   uart_baudrate_div_int, uart_baudrate_div_int_d;
  reg  [AXI_DIV_WIDTH-1:0]   baudrate_divisor_int,  baudrate_divisor_int_d;
  reg                        uart_irq_en_int,        uart_irq_en_int_d;

  wire uart_en_int            = 1'b1;
  wire uart_parity_en_int     = uart_config_reg_int[UART_CONFIG_PARITY_EN];
  wire uart_parity_mode_int   = uart_config_reg_int[UART_CONFIG_PARITY_MODE];
  wire uart_stop_bits_sel_int = uart_config_reg_int[UART_CONFIG_STOP_BITS];
  wire uart_dlab_int          = uart_config_reg_int[UART_CONFIG_DLAB];

  // =========================================================================
  // FIFO wires
  // =========================================================================
  wire [AXI_FIFO_ADDR:0]     rx_status_int;
  wire [AXI_FIFO_ADDR+3:0]   tx_status_int;

  wire                       push_controller_rx_fifo;
  wire                       pull_controller_tx_fifo;
  wire                       load_tx_fifo_controller;
  wire                       tx_fifo_full_int;
  wire                       available_write_space_int;

  wire [DATA_WIDTH_UART-1:0] data_rx_controller_fifo;
  wire [DATA_WIDTH_UART-1:0] rx_fifo_data_out_int;
  wire [DATA_WIDTH_UART-1:0] data_tx_fifo_controller;

  reg                        rx_fifo_reset_int, rx_fifo_reset_int_d;
  reg                        rx_fifo_pull_int,  rx_fifo_pull_int_d;

  reg                        tx_fifo_reset_int,   tx_fifo_reset_int_d;
  reg                        tx_fifo_push_int,    tx_fifo_push_int_d;
  reg  [DATA_WIDTH_UART-1:0] tx_fifo_data_in_int, tx_fifo_data_in_int_d;

  // LSR register — assembled combinatorially from FIFO status
  wire [AXI_DATA_WIDTH-1:0]  uart_lsr_reg_int;

  genvar I;
  generate
    for (I = 0; I < AXI_DATA_WIDTH; I = I + 1) begin : uart_lsr_assignment_gen
      case (I)
        UART_LSR_THRE:       assign uart_lsr_reg_int[I] = available_write_space_int;
        UART_LSR_TEMT:       assign uart_lsr_reg_int[I] = available_write_space_int;
        UART_LSR_DATA_READY: assign uart_lsr_reg_int[I] = ~rx_status_int[AXI_FIFO_ADDR] & uart_irq_en_int;
        default:             assign uart_lsr_reg_int[I] = 1'b0;
      endcase
    end
  endgenerate

  // =========================================================================
  // AXI4-Lite register declarations
  // =========================================================================

  // ---- Write Address channel ----
  reg                        axi_awready,   axi_awready_d;
  reg  [AXI_ID_WIDTH-1:0]    aw_id_lat,     aw_id_lat_d;   // latched AW ID
  reg  [AXI_ADDR_WIDTH-1:0]  aw_addr_lat,   aw_addr_lat_d; // latched AW addr

  // ---- Write Data channel ----
  reg                        axi_wready,    axi_wready_d;

  // ---- Write Response channel ----
  reg  [AXI_ID_WIDTH-1:0]    axi_bid,       axi_bid_d;
  reg  [AXI_RESP_WIDTH-1:0]  axi_bresp,     axi_bresp_d;
  reg                        axi_bvalid,    axi_bvalid_d;

  // ---- Read Address channel ----
  reg                        axi_arready,   axi_arready_d;
  reg  [AXI_ID_WIDTH-1:0]    ar_id_lat,     ar_id_lat_d;
  reg  [AXI_ADDR_WIDTH-1:0]  ar_addr_lat,   ar_addr_lat_d;

  // ---- Read Data channel ----
  reg  [AXI_ID_WIDTH-1:0]    axi_rid,       axi_rid_d;
  reg  [AXI_DATA_WIDTH-1:0]  axi_rdata,     axi_rdata_d;
  reg  [AXI_RESP_WIDTH-1:0]  axi_rresp,     axi_rresp_d;
  reg                        axi_rvalid,    axi_rvalid_d;

  // =========================================================================
  // AXI4-Lite output assignments
  // =========================================================================
  assign axi_awready_o = axi_awready;
  assign axi_wready_o  = axi_wready;
  assign axi_bid_o     = axi_bid;
  assign axi_bresp_o   = axi_bresp;
  assign axi_bvalid_o  = axi_bvalid;
  assign axi_arready_o = axi_arready;
  assign axi_rid_o     = axi_rid;
  assign axi_rdata_o   = axi_rdata;
  assign axi_rresp_o   = axi_rresp;
  assign axi_rvalid_o  = axi_rvalid;

  // =========================================================================
  // WRITE FSM
  //
  // AXI4-Lite write transaction:
  //   1. WR_IDLE : slave asserts AWREADY + WREADY when AWVALID arrives
  //                (address and data channels may arrive simultaneously or
  //                 address first; AXI4-Lite does not guarantee ordering)
  //   2. WR_DATA : wait until both AWVALID+WVALID have been seen, then
  //                decode the address, update the target register, and
  //                move to WR_RESP
  //   3. WR_RESP : hold BVALID until BREADY; return to WR_IDLE
  //
  // Note: AXI4-Lite has no burst channels — WLAST / RLAST do not exist.
  // =========================================================================
  localparam WR_IDLE = 2'b00;
  localparam WR_DATA = 2'b01;
  localparam WR_RESP = 2'b10;
  reg [1:0] wr_state, wr_state_d;

  // Handshake latches: track whether AW and W have each been accepted
  reg aw_done, aw_done_d;  // AW address has been latched
  reg w_done,  w_done_d;   // W data has been latched

  // Latch for the write data (needed when W arrives before the decode beat)
  reg  [AXI_DATA_WIDTH-1:0]   aw_wdata_lat,  aw_wdata_lat_d;
  reg  [AXI_DATA_WIDTH/8-1:0] aw_wstrb_lat,  aw_wstrb_lat_d;

  // ---- WRITE FSM : combinational ----
  always @(*) begin
    // Default: hold all state
    wr_state_d              = wr_state;
    axi_awready_d           = 1'b0;
    axi_wready_d            = axi_wready;
    axi_bid_d               = axi_bid;
    axi_bresp_d             = axi_bresp;
    axi_bvalid_d            = axi_bvalid;
    aw_id_lat_d             = aw_id_lat;
    aw_addr_lat_d           = aw_addr_lat;
    aw_done_d               = aw_done;
    w_done_d                = w_done;
    aw_wdata_lat_d          = aw_wdata_lat;
    aw_wstrb_lat_d          = aw_wstrb_lat;
    tx_fifo_push_int_d      = 1'b0;
    tx_fifo_data_in_int_d   = tx_fifo_data_in_int;
    tx_fifo_reset_int_d     = tx_fifo_reset_int;
    uart_baudrate_div_int_d = uart_baudrate_div_int;
    baudrate_divisor_int_d  = baudrate_divisor_int;
    uart_config_reg_int_d   = uart_config_reg_int;
    uart_irq_en_int_d       = uart_irq_en_int;

    case (wr_state)
      // ------------------------------------------------------------------
      WR_IDLE: begin
        axi_bvalid_d = 1'b0;
        aw_done_d    = 1'b0;
        w_done_d     = 1'b0;

        // Accept AW handshake
        if (axi_awvalid_i) begin
          axi_awready_d = 1'b1;
          aw_id_lat_d   = axi_awid_i;
          aw_addr_lat_d = axi_awaddr_i;
          aw_done_d     = 1'b1;
        end

        // Accept W handshake simultaneously (AXI4-Lite allows both channels valid
        // at once; we must accept both regardless of ordering)
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

      // ------------------------------------------------------------------
      WR_DATA: begin
        // Both address and data are in the latches; decode and write.
        axi_awready_d = 1'b0;
        axi_wready_d  = 1'b0;

        case (aw_addr_lat[AXI_ADDR_WIDTH-1 : AXI_LSB_WIDTH])

          UART_THR: begin
            if (!uart_dlab_int && !tx_fifo_full_int) begin
              tx_fifo_push_int_d    = 1'b1;
              tx_fifo_data_in_int_d = aw_wdata_lat[DATA_WIDTH_UART-1:0];
            end
            axi_bresp_d = `AXIL_RESP_OKAY;
          end

          UART_IER: begin
            if (!uart_dlab_int)
              uart_irq_en_int_d = aw_wdata_lat[0];
            axi_bresp_d = `AXIL_RESP_OKAY;
          end

          UART_BAUD_DIVISOR: begin
            if (uart_dlab_int)
              baudrate_divisor_int_d = aw_wdata_lat[AXI_DIV_WIDTH-1:0];
            axi_bresp_d = `AXIL_RESP_OKAY;
          end

          UART_LCR: begin
            uart_config_reg_int_d = aw_wdata_lat;
            axi_bresp_d           = `AXIL_RESP_OKAY;
          end

          default: begin
            // Undefined offset: respond with SLVERR (no state change)
            axi_bresp_d = `AXIL_RESP_SLVERR;
          end
        endcase

        // Commit baud-rate divisor on any write (harmless if DLAB was clear)
        uart_baudrate_div_int_d = baudrate_divisor_int_d;
        tx_fifo_reset_int_d     = 1'b0;

        axi_bid_d    = aw_id_lat;
        axi_bvalid_d = 1'b1;
        wr_state_d   = WR_RESP;
      end

      // ------------------------------------------------------------------
      WR_RESP: begin
        if (axi_bready_i) begin
          axi_bvalid_d = 1'b0;
          axi_bid_d    = {AXI_ID_WIDTH{1'b0}};
          wr_state_d   = WR_IDLE;
        end
      end

      default: begin
        wr_state_d              = WR_IDLE;
        axi_awready_d           = 1'b0;
        axi_wready_d            = 1'b0;
        axi_bvalid_d            = 1'b0;
        tx_fifo_reset_int_d     = 1'b1;
        uart_baudrate_div_int_d = UART_BAUDRATE_DIV_INIT[AXI_DIV_WIDTH-1:0];
        baudrate_divisor_int_d  = UART_BAUDRATE_DIV_INIT[AXI_DIV_WIDTH-1:0];
        uart_config_reg_int_d   = {AXI_DATA_WIDTH{1'b0}};
        uart_irq_en_int_d       = 1'b0;
        aw_done_d               = 1'b0;
        w_done_d                = 1'b0;
      end
    endcase
  end

  // ---- WRITE FSM : sequential (fixed_clk_i domain) ----
  always @(posedge fixed_clk_i, negedge axi_aresetn_i) begin
    if (!axi_aresetn_i) begin
      wr_state              <= WR_IDLE;
      axi_awready           <= 1'b0;
      axi_wready            <= 1'b0;
      axi_bid               <= {AXI_ID_WIDTH{1'b0}};
      axi_bresp             <= 2'b0;
      axi_bvalid            <= 1'b0;
      aw_id_lat             <= {AXI_ID_WIDTH{1'b0}};
      aw_addr_lat           <= {AXI_ADDR_WIDTH{1'b0}};
      aw_done               <= 1'b0;
      w_done                <= 1'b0;
      aw_wdata_lat          <= {AXI_DATA_WIDTH{1'b0}};
      aw_wstrb_lat          <= {(AXI_DATA_WIDTH/8){1'b0}};
      tx_fifo_reset_int     <= 1'b1;
      tx_fifo_push_int      <= 1'b0;
      tx_fifo_data_in_int   <= {DATA_WIDTH_UART{1'b0}};
      uart_baudrate_div_int <= UART_BAUDRATE_DIV_INIT[AXI_DIV_WIDTH-1:0];
      baudrate_divisor_int  <= UART_BAUDRATE_DIV_INIT[AXI_DIV_WIDTH-1:0];
      uart_config_reg_int   <= {AXI_DATA_WIDTH{1'b0}};
      uart_irq_en_int       <= 1'b0;
    end else begin
      wr_state              <= wr_state_d;
      axi_awready           <= axi_awready_d;
      axi_wready            <= axi_wready_d;
      axi_bid               <= axi_bid_d;
      axi_bresp             <= axi_bresp_d;
      axi_bvalid            <= axi_bvalid_d;
      aw_id_lat             <= aw_id_lat_d;
      aw_addr_lat           <= aw_addr_lat_d;
      aw_done               <= aw_done_d;
      w_done                <= w_done_d;
      aw_wdata_lat          <= aw_wdata_lat_d;
      aw_wstrb_lat          <= aw_wstrb_lat_d;
      tx_fifo_reset_int     <= tx_fifo_reset_int_d;
      tx_fifo_push_int      <= tx_fifo_push_int_d;
      tx_fifo_data_in_int   <= tx_fifo_data_in_int_d;
      uart_baudrate_div_int <= uart_baudrate_div_int_d;
      baudrate_divisor_int  <= baudrate_divisor_int_d;
      uart_config_reg_int   <= uart_config_reg_int_d;
      uart_irq_en_int       <= uart_irq_en_int_d;
    end
  end

  // =========================================================================
  // READ FSM
  //
  // AXI4-Lite read transaction:
  //   1. RD_IDLE : slave asserts ARREADY when ARVALID arrives; latches address
  //   2. RD_DATA : decode address, present RDATA + RVALID; wait for RREADY
  //   3. Return to RD_IDLE
  //
  // Note: AXI4-Lite has no RLAST — the single-beat transaction completes when
  // RVALID & RREADY are both asserted.
  // =========================================================================
  localparam RD_IDLE = 2'b00;
  localparam RD_DATA = 2'b01;
  reg [1:0] rd_state, rd_state_d;

  // ---- READ FSM : combinational ----
  always @(*) begin
    rd_state_d          = rd_state;
    axi_arready_d       = 1'b0;
    axi_rid_d           = axi_rid;
    axi_rdata_d         = axi_rdata;
    axi_rresp_d         = axi_rresp;
    axi_rvalid_d        = axi_rvalid;
    ar_id_lat_d         = ar_id_lat;
    ar_addr_lat_d       = ar_addr_lat;
    rx_fifo_pull_int_d  = 1'b0;
    rx_fifo_reset_int_d = rx_fifo_reset_int;

    case (rd_state)
      // ------------------------------------------------------------------
      RD_IDLE: begin
        axi_rvalid_d = 1'b0;
        if (axi_arvalid_i) begin
          axi_arready_d = 1'b1;
          ar_id_lat_d   = axi_arid_i;
          ar_addr_lat_d = axi_araddr_i;
          rd_state_d    = RD_DATA;
        end
      end

      // ------------------------------------------------------------------
      RD_DATA: begin
        axi_arready_d = 1'b0;

        // Present data as long as master has not yet accepted (or is accepting now)
        if (!axi_rvalid || axi_rready_i) begin
          case (ar_addr_lat[AXI_ADDR_WIDTH-1 : AXI_LSB_WIDTH])

            UART_RBR: begin
              if (!uart_dlab_int) begin
                axi_rdata_d        = {{(AXI_DATA_WIDTH-DATA_WIDTH_UART){1'b0}},
                                       rx_fifo_data_out_int};
                rx_fifo_pull_int_d = 1'b1;
              end else begin
                // DLAB=1: RBR address maps to BAUD_DIVISOR read
                axi_rdata_d = {{(AXI_DATA_WIDTH-AXI_DIV_WIDTH){1'b0}},
                                uart_baudrate_div_int};
              end
              axi_rresp_d = `AXIL_RESP_OKAY;
            end

            UART_IER: begin
              axi_rdata_d = {{(AXI_DATA_WIDTH-1){1'b0}}, uart_irq_en_int};
              axi_rresp_d = `AXIL_RESP_OKAY;
            end

            UART_BAUD_DIVISOR: begin
              axi_rdata_d = {{(AXI_DATA_WIDTH-AXI_DIV_WIDTH){1'b0}},
                              uart_baudrate_div_int};
              axi_rresp_d = `AXIL_RESP_OKAY;
            end

            UART_LCR: begin
              axi_rdata_d = uart_config_reg_int;
              axi_rresp_d = `AXIL_RESP_OKAY;
            end

            UART_LSR: begin
              axi_rdata_d = uart_lsr_reg_int;
              axi_rresp_d = `AXIL_RESP_OKAY;
            end

            default: begin
              axi_rdata_d = {AXI_DATA_WIDTH{1'b0}};
              axi_rresp_d = `AXIL_RESP_SLVERR; // undefined register in window
            end
          endcase

          axi_rid_d    = ar_id_lat;
          axi_rvalid_d = 1'b1;

          // Single-beat AXI4-Lite: return to IDLE after presenting data
          if (axi_rready_i) begin
            rx_fifo_reset_int_d = 1'b0;
            rd_state_d          = RD_IDLE;
          end
        end
      end

      default: begin
        rd_state_d          = RD_IDLE;
        axi_arready_d       = 1'b0;
        axi_rvalid_d        = 1'b0;
        rx_fifo_reset_int_d = 1'b1;
        rx_fifo_pull_int_d  = 1'b0;
      end
    endcase
  end

  // ---- READ FSM : sequential (fixed_clk_i domain) ----
  always @(posedge fixed_clk_i, negedge axi_aresetn_i) begin
    if (!axi_aresetn_i) begin
      rd_state          <= RD_IDLE;
      axi_arready       <= 1'b0;
      axi_rid           <= {AXI_ID_WIDTH{1'b0}};
      axi_rdata         <= {AXI_DATA_WIDTH{1'b0}};
      axi_rresp         <= 2'b0;
      axi_rvalid        <= 1'b0;
      ar_id_lat         <= {AXI_ID_WIDTH{1'b0}};
      ar_addr_lat       <= {AXI_ADDR_WIDTH{1'b0}};
      rx_fifo_reset_int <= 1'b1;
      rx_fifo_pull_int  <= 1'b0;
    end else begin
      rd_state          <= rd_state_d;
      axi_arready       <= axi_arready_d;
      axi_rid           <= axi_rid_d;
      axi_rdata         <= axi_rdata_d;
      axi_rresp         <= axi_rresp_d;
      axi_rvalid        <= axi_rvalid_d;
      ar_id_lat         <= ar_id_lat_d;
      ar_addr_lat       <= ar_addr_lat_d;
      rx_fifo_reset_int <= rx_fifo_reset_int_d;
      rx_fifo_pull_int  <= rx_fifo_pull_int_d;
    end
  end

  // =========================================================================
  // Read-interrupt generation
  //   Asserted whenever the RX FIFO is non-empty AND IER[0] is set.
  // =========================================================================
  always @(posedge fixed_clk_i, negedge axi_aresetn_i) begin
    if (!axi_aresetn_i)
      read_interrupt_o <= 1'b0;
    else
      read_interrupt_o <= ~rx_status_int[AXI_FIFO_ADDR] & uart_irq_en_int;
  end

  // =========================================================================
  // UART controller instantiation
  // =========================================================================
  uart_controller
    #(
      .DATA_UART (DATA_WIDTH_UART),
      .DATA_SIZE (AXI_DATA_WIDTH),
      .DIV_SIZE  (AXI_DIV_WIDTH)
    )
    uart_controller_inst (
      .clk_i                  (fixed_clk_i),
      .rstn_i                 (axi_aresetn_i),

      .uart_en_i              (uart_en_int),
      .uart_stop_bits_i       (uart_stop_bits_sel_int),
      .uart_parity_bit_i      (uart_parity_en_int),
      .uart_parity_bit_mode_i (uart_parity_mode_int),
      .uart_baudrate_div_i    (uart_baudrate_div_int),

      .uart_rx_i              (uart_rx_i),
      .rx_data_o              (data_rx_controller_fifo),
      .rx_push_o              (push_controller_rx_fifo),

      .uart_tx_o              (uart_tx_o),
      .tx_load_i              (load_tx_fifo_controller),
      .tx_data_i              (data_tx_fifo_controller),
      .tx_pull_o              (pull_controller_tx_fifo)
    );

  // =========================================================================
  // RX FIFO  (UART → AXI master)
  // =========================================================================
  axi_internal_fifo
    #(
      .FIFO_SIZE    (AXI_FIFO_DEPTH),
      .DATA_SIZE    (DATA_WIDTH_UART),
      .INDEX_LENGTH (AXI_FIFO_ADDR),
      .PORT_EN      (3'b000)  // [load | full | available_space] — only space used
    )
    axi_internal_fifo_rx_inst (
      .clk_i   (fixed_clk_i),
      .arstn_i (axi_aresetn_i),
      .rst_i   (rx_fifo_reset_int),

      .push_i  (push_controller_rx_fifo),
      .pull_i  (rx_fifo_pull_int),

      .data_i  (data_rx_controller_fifo),
      .data_o  (rx_fifo_data_out_int),

      .status_o (rx_status_int)
    );

  // =========================================================================
  // TX FIFO  (AXI master → UART)
  // =========================================================================
  axi_internal_fifo
    #(
      .FIFO_SIZE    (AXI_FIFO_DEPTH),
      .DATA_SIZE    (DATA_WIDTH_UART),
      .INDEX_LENGTH (AXI_FIFO_ADDR),
      .PORT_EN      (3'b111)  // [load | full | available_space] — all needed
    )
    axi_internal_fifo_tx_inst (
      .clk_i   (fixed_clk_i),
      .arstn_i (axi_aresetn_i),
      .rst_i   (tx_fifo_reset_int),

      .push_i  (tx_fifo_push_int),
      .pull_i  (pull_controller_tx_fifo),

      .data_i  (tx_fifo_data_in_int),
      .data_o  (data_tx_fifo_controller),

      .status_o (tx_status_int)
    );

  // TX FIFO status decode
  assign load_tx_fifo_controller   = tx_status_int[AXI_FIFO_ADDR+3];
  assign tx_fifo_full_int          = tx_status_int[AXI_FIFO_ADDR+2];
  assign available_write_space_int = tx_status_int[AXI_FIFO_ADDR+1];

endmodule

`default_nettype wire
