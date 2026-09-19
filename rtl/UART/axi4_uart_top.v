/* -----------------------------------------------------------------------------
 * Project        : AXI4 UART IP Core
 * File           : axi4_uart_top.v
 * Description    : Full AXI4 Slave UART Module (with burst support)
 *                  Replaces axi_uart_top.v (AXI4-Lite version).
 * ------------------------------------------------------------------------------
 * AXI4 additions over the AXI4-Lite version:
 *   Write channel : AWLEN, AWSIZE, AWBURST, AWLOCK, AWCACHE, AWPROT, AWQOS
 *                   WLAST
 *   Read  channel : ARLEN, ARSIZE, ARBURST, ARLOCK, ARCACHE, ARPROT, ARQOS
 *                   RLAST
 *   Burst support : INCR burst on both read and write channels.
 *                   Single-register slave: all burst beats map to the same
 *                   register address (simplest correct behaviour for a UART
 *                   peripheral whose registers are single-beat in nature).
 *                   WLAST / RLAST are tracked so the slave correctly completes
 *                   the handshake for multi-beat bursts from the master.
 * ------------------------------------------------------------------------------
 * Revision History
 *  Revision   | Author      | Description
 *  1.0        | aruiz       | First IP version with Avalon-Bus interface
 *  2.0        | vkostalamp  | AXI-Bus porting and documentation
 *  2.1        | aruiz       | Code refactoring with asynchronous reset
 *  3.0        | aruiz       | Two clock domains integration
 *  4.0        | HC_CBP_095  | Full AXI4 upgrade (burst channels)
 * -----------------------------------------------------------------------------*/
`timescale 1ns/1ps

`default_nettype none

`include "axi4_uart_defines.vh"

/*
Title: axi4_uart_top
Full AXI4 slave UART top-level.  Two decoupled FSMs handle the read and write
channels independently.  Burst transactions (INCR) are accepted; every beat of
a write burst is decoded against the address latched from AWADDR.  Every beat
of a read burst returns data from the same register address.
The actual UART datapath (uart_controller, rx-FIFO, tx-FIFO) is unchanged from
the AXI4-Lite version.
*/
module axi4_uart_top (
  // -----------------------------------------------------------------------
  // Clocks & reset
  // -----------------------------------------------------------------------
  input  wire        fixed_clk_i,   // UART clock domain (≥16× baud)
  input  wire        axi_aclk_i,    // AXI bus clock
  input  wire        axi_aresetn_i, // AXI active-low synchronous reset

  // -----------------------------------------------------------------------
  // AXI4 Write Address channel (AW)
  // -----------------------------------------------------------------------
  input  wire [`_AXI_UART_ID_WIDTH_-1:0]     axi_awid_i,
  input  wire [`_AXI_UART_ADDR_WIDTH_-1:0]   axi_awaddr_i,
  input  wire [`_AXI_UART_LEN_WIDTH_-1:0]    axi_awlen_i,    // burst length (beats-1)
  input  wire [`_AXI_UART_SIZE_WIDTH_-1:0]   axi_awsize_i,   // bytes per beat
  input  wire [`_AXI_UART_BURST_WIDTH_-1:0]  axi_awburst_i,  // FIXED/INCR/WRAP
  input  wire [`_AXI_UART_LOCK_WIDTH_-1:0]   axi_awlock_i,   // exclusive lock
  input  wire [`_AXI_UART_CACHE_WIDTH_-1:0]  axi_awcache_i,  // memory attributes
  input  wire [`_AXI_UART_PROT_WIDTH_-1:0]   axi_awprot_i,   // protection type
  input  wire [`_AXI_UART_QOS_WIDTH_-1:0]    axi_awqos_i,    // QoS
  input  wire                                axi_awvalid_i,
  output wire                                axi_awready_o,

  // -----------------------------------------------------------------------
  // AXI4 Write Data channel (W)
  // -----------------------------------------------------------------------
  input  wire [`_AXI_UART_DATA_WIDTH_-1:0]   axi_wdata_i,
  input  wire [`_AXI_UART_DATA_WIDTH_/8-1:0] axi_wstrb_i,
  input  wire                                axi_wlast_i,   // last beat of burst
  input  wire                                axi_wvalid_i,
  output wire                                axi_wready_o,

  // -----------------------------------------------------------------------
  // AXI4 Write Response channel (B)
  // -----------------------------------------------------------------------
  output wire [`_AXI_UART_ID_WIDTH_-1:0]     axi_bid_o,
  output wire [`_AXI_UART_RESP_WIDTH_-1:0]   axi_bresp_o,
  output wire                                axi_bvalid_o,
  input  wire                                axi_bready_i,

  // -----------------------------------------------------------------------
  // AXI4 Read Address channel (AR)
  // -----------------------------------------------------------------------
  input  wire [`_AXI_UART_ID_WIDTH_-1:0]     axi_arid_i,
  input  wire [`_AXI_UART_ADDR_WIDTH_-1:0]   axi_araddr_i,
  input  wire [`_AXI_UART_LEN_WIDTH_-1:0]    axi_arlen_i,    // burst length (beats-1)
  input  wire [`_AXI_UART_SIZE_WIDTH_-1:0]   axi_arsize_i,   // bytes per beat
  input  wire [`_AXI_UART_BURST_WIDTH_-1:0]  axi_arburst_i,  // FIXED/INCR/WRAP
  input  wire [`_AXI_UART_LOCK_WIDTH_-1:0]   axi_arlock_i,   // exclusive lock
  input  wire [`_AXI_UART_CACHE_WIDTH_-1:0]  axi_arcache_i,  // memory attributes
  input  wire [`_AXI_UART_PROT_WIDTH_-1:0]   axi_arprot_i,   // protection type
  input  wire [`_AXI_UART_QOS_WIDTH_-1:0]    axi_arqos_i,    // QoS
  input  wire                                axi_arvalid_i,
  output wire                                axi_arready_o,

  // -----------------------------------------------------------------------
  // AXI4 Read Data channel (R)
  // -----------------------------------------------------------------------
  output wire [`_AXI_UART_ID_WIDTH_-1:0]     axi_rid_o,
  output wire [`_AXI_UART_DATA_WIDTH_-1:0]   axi_rdata_o,
  output wire [`_AXI_UART_RESP_WIDTH_-1:0]   axi_rresp_o,
  output wire                                axi_rlast_o,    // last beat of read burst
  output wire                                axi_rvalid_o,
  input  wire                                axi_rready_i,

  // -----------------------------------------------------------------------
  // UART interface
  // -----------------------------------------------------------------------
  output reg                                 read_interrupt_o,
  input  wire                                uart_rx_i,
  output wire                                uart_tx_o
);

  // =========================================================================
  // Local parameters derived from defines
  // =========================================================================
  localparam BYTE             = 8;
  localparam AXI_DATA_WIDTH   = `_AXI_UART_DATA_WIDTH_;
  localparam AXI_ADDR_WIDTH   = `_AXI_UART_ADDR_WIDTH_;
  localparam AXI_DIV_WIDTH    = `_AXI_UART_DIV_WIDTH_;
  localparam AXI_ID_WIDTH     = `_AXI_UART_ID_WIDTH_;
  localparam AXI_RESP_WIDTH   = `_AXI_UART_RESP_WIDTH_;
  localparam AXI_LEN_WIDTH    = `_AXI_UART_LEN_WIDTH_;
  localparam AXI_FIFO_DEPTH   = `_AXI_UART_FIFO_DEPTH_;
  localparam AXI_FIFO_ADDR    = $clog2(AXI_FIFO_DEPTH);
  localparam AXI_BYTE_NUM     = AXI_DATA_WIDTH / BYTE;
  localparam AXI_LSB_WIDTH    = $clog2(AXI_BYTE_NUM); // byte-lane LSBs to strip

  // UART register map (word indices — compare addr[AXI_ADDR_WIDTH-1 : AXI_LSB_WIDTH])
  localparam UART_RBR                = `_UART_RBR_;
  localparam UART_THR                = `_UART_THR_;
  localparam UART_IER                = `_UART_IER_;
  localparam UART_BAUD_DIVISOR       = `_UART_BAUD_DIVISOR_;
  localparam UART_LCR                = `_UART_LCR_;
  localparam UART_LSR                = `_UART_LSR_;

  // LCR / LSR bit positions
  localparam UART_CONFIG_STOP_BITS   = `_UART_CONFIG_STOP_BITS_;
  localparam UART_CONFIG_PARITY_EN   = `_UART_CONFIG_PARITY_EN_;
  localparam UART_CONFIG_PARITY_MODE = `_UART_CONFIG_PARITY_MODE_;
  localparam UART_CONFIG_DLAB        = `_UART_CONFIG_DLAB_;
  localparam UART_LSR_DATA_READY     = `_UART_LSR_DATA_READY_;
  localparam UART_LSR_TEMT           = `_UART_LSR_TEMT_;
  localparam UART_LSR_THRE           = `_UART_LSR_THRE_;

  // UART datapath
  localparam DATA_WIDTH_UART         = `_DATA_WIDTH_UART_;
  localparam UART_BAUDRATE_DIV_INIT  = `_UART_BAUDRATE_DIV_INIT_;

  // =========================================================================
  // Internal UART configuration registers
  // =========================================================================
  reg  [AXI_DATA_WIDTH-1:0]  uart_config_reg_int,  uart_config_reg_int_d;
  reg  [AXI_DIV_WIDTH-1:0]   uart_baudrate_div_int, uart_baudrate_div_int_d;
  reg  [AXI_DIV_WIDTH-1:0]   baudrate_divisor_int,  baudrate_divisor_int_d;
  reg                        uart_irq_en_int,       uart_irq_en_int_d;

  wire uart_en_int            = 1'b1; // UART always enabled
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

  reg                        tx_fifo_reset_int,    tx_fifo_reset_int_d;
  reg                        tx_fifo_push_int,     tx_fifo_push_int_d;
  reg  [DATA_WIDTH_UART-1:0] tx_fifo_data_in_int,  tx_fifo_data_in_int_d;

  // LSR register (combinatorially assembled)
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
  // AXI4 Register declarations
  // =========================================================================

  // ---- Write Address channel ----
  reg                        axi_awready,    axi_awready_d;
  reg  [AXI_ID_WIDTH-1:0]    aw_id_lat,      aw_id_lat_d;    // latched AW ID
  reg  [AXI_ADDR_WIDTH-1:0]  aw_addr_lat,    aw_addr_lat_d;  // latched AW addr
  reg  [AXI_LEN_WIDTH-1:0]   aw_len_lat,     aw_len_lat_d;   // latched burst len
  reg  [AXI_LEN_WIDTH-1:0]   aw_beat_cnt,    aw_beat_cnt_d;  // write beat counter

  // ---- Write Data channel ----
  reg                        axi_wready,     axi_wready_d;

  // ---- Write Response channel ----
  reg  [AXI_ID_WIDTH-1:0]    axi_bid,        axi_bid_d;
  reg  [AXI_RESP_WIDTH-1:0]  axi_bresp,      axi_bresp_d;
  reg                        axi_bvalid,     axi_bvalid_d;

  // ---- Read Address channel ----
  reg                        axi_arready,    axi_arready_d;
  reg  [AXI_ID_WIDTH-1:0]    ar_id_lat,      ar_id_lat_d;
  reg  [AXI_ADDR_WIDTH-1:0]  ar_addr_lat,    ar_addr_lat_d;
  reg  [AXI_LEN_WIDTH-1:0]   ar_len_lat,     ar_len_lat_d;   // latched burst len
  reg  [AXI_LEN_WIDTH-1:0]   ar_beat_cnt,    ar_beat_cnt_d;  // read beat counter

  // ---- Read Data channel ----
  reg  [AXI_ID_WIDTH-1:0]    axi_rid,        axi_rid_d;
  reg  [AXI_DATA_WIDTH-1:0]  axi_rdata,      axi_rdata_d;
  reg  [AXI_RESP_WIDTH-1:0]  axi_rresp,      axi_rresp_d;
  reg                        axi_rlast,      axi_rlast_d;
  reg                        axi_rvalid,     axi_rvalid_d;

  // =========================================================================
  // AXI4 output assignments
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
  assign axi_rlast_o   = axi_rlast;
  assign axi_rvalid_o  = axi_rvalid;

  // =========================================================================
  // WRITE FSM — accepts full AXI4 burst writes
  // =========================================================================
  //
  // State encoding
  //   WR_IDLE  : waiting for AW handshake
  //   WR_DATA  : accepting W-channel beats
  //   WR_RESP  : sending B-channel response (wait for bready)
  //
  localparam WR_IDLE = 2'b00;
  localparam WR_DATA = 2'b01;
  localparam WR_RESP = 2'b10;
  reg [1:0] wr_state, wr_state_d;

  // ---- WRITE FSM : combinational ----
  always @(*) begin
    // default: hold
    wr_state_d              = wr_state;
    axi_awready_d           = 1'b0;
    axi_wready_d            = axi_wready;
    axi_bid_d               = axi_bid;
    axi_bresp_d             = axi_bresp;
    axi_bvalid_d            = axi_bvalid;
    aw_id_lat_d             = aw_id_lat;
    aw_addr_lat_d           = aw_addr_lat;
    aw_len_lat_d            = aw_len_lat;
    aw_beat_cnt_d           = aw_beat_cnt;
    tx_fifo_push_int_d      = 1'b0;
    tx_fifo_data_in_int_d   = tx_fifo_data_in_int;
    tx_fifo_reset_int_d     = tx_fifo_reset_int;
    uart_baudrate_div_int_d = uart_baudrate_div_int;
    baudrate_divisor_int_d  = baudrate_divisor_int;
    uart_config_reg_int_d   = uart_config_reg_int;
    uart_irq_en_int_d       = uart_irq_en_int;

    case (wr_state)
      // -------------------------------------------------------------------
      WR_IDLE: begin
        axi_bvalid_d  = 1'b0;
        axi_wready_d  = 1'b0;
        if (axi_awvalid_i) begin
          // Accept address — latch burst info
          axi_awready_d   = 1'b1;
          aw_id_lat_d     = axi_awid_i;
          aw_addr_lat_d   = axi_awaddr_i;
          aw_len_lat_d    = axi_awlen_i;
          aw_beat_cnt_d   = {AXI_LEN_WIDTH{1'b0}};
          axi_wready_d    = 1'b1;   // immediately ready for data
          wr_state_d      = WR_DATA;
        end
      end

      // -------------------------------------------------------------------
      WR_DATA: begin
        axi_awready_d = 1'b0;  // address already accepted

        if (axi_wvalid_i && axi_wready) begin
          // --- decode address and update register ---
          case (aw_addr_lat[AXI_ADDR_WIDTH-1 : AXI_LSB_WIDTH])

            UART_THR: begin
              if (!uart_dlab_int && !tx_fifo_full_int) begin
                tx_fifo_push_int_d    = 1'b1;
                tx_fifo_data_in_int_d = axi_wdata_i[DATA_WIDTH_UART-1:0];
              end
            end

            UART_IER: begin
              if (!uart_dlab_int)
                uart_irq_en_int_d = axi_wdata_i[0];
            end

            UART_BAUD_DIVISOR: begin
              if (uart_dlab_int)
                baudrate_divisor_int_d = axi_wdata_i[AXI_DIV_WIDTH-1:0];
            end

            UART_LCR: begin
              uart_config_reg_int_d = axi_wdata_i;
            end

            default: ; // ignore writes to undefined registers (no hang)
          endcase

          // --- burst beat accounting ---
          if (axi_wlast_i || (aw_beat_cnt == aw_len_lat)) begin
            // Last beat received — send response
            axi_wready_d      = 1'b0;
            axi_bid_d         = aw_id_lat;
            axi_bresp_d       = `AXI4_RESP_OKAY;
            axi_bvalid_d      = 1'b1;
            uart_baudrate_div_int_d = baudrate_divisor_int_d; // commit divisor
            tx_fifo_reset_int_d = 1'b0;
            wr_state_d        = WR_RESP;
          end else begin
            aw_beat_cnt_d = aw_beat_cnt + 1'b1;
          end
        end
      end

      // -------------------------------------------------------------------
      WR_RESP: begin
        // Hold BVALID until master acknowledges
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
      end
    endcase
  end

  // ---- WRITE FSM : sequential (fixed_clk domain for UART coherence) ----
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
      aw_len_lat            <= {AXI_LEN_WIDTH{1'b0}};
      aw_beat_cnt           <= {AXI_LEN_WIDTH{1'b0}};
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
      aw_len_lat            <= aw_len_lat_d;
      aw_beat_cnt           <= aw_beat_cnt_d;
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
  // READ FSM — accepts full AXI4 burst reads
  // =========================================================================
  //
  // State encoding
  //   RD_IDLE  : waiting for AR handshake
  //   RD_DATA  : sending R-channel beats
  //
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
    axi_rlast_d         = 1'b0;
    axi_rvalid_d        = axi_rvalid;
    ar_id_lat_d         = ar_id_lat;
    ar_addr_lat_d       = ar_addr_lat;
    ar_len_lat_d        = ar_len_lat;
    ar_beat_cnt_d       = ar_beat_cnt;
    rx_fifo_pull_int_d  = 1'b0;
    rx_fifo_reset_int_d = rx_fifo_reset_int;

    case (rd_state)
      // -------------------------------------------------------------------
      RD_IDLE: begin
        axi_rvalid_d = 1'b0;
        if (axi_arvalid_i) begin
          // Accept address — latch burst info
          axi_arready_d  = 1'b1;
          ar_id_lat_d    = axi_arid_i;
          ar_addr_lat_d  = axi_araddr_i;
          ar_len_lat_d   = axi_arlen_i;
          ar_beat_cnt_d  = {AXI_LEN_WIDTH{1'b0}};
          rd_state_d     = RD_DATA;
        end
      end

      // -------------------------------------------------------------------
      RD_DATA: begin
        axi_arready_d = 1'b0;

        if (!axi_rvalid || axi_rready_i) begin
          // --- decode read address ---
          case (ar_addr_lat[AXI_ADDR_WIDTH-1 : AXI_LSB_WIDTH])
            UART_RBR: begin
              if (!uart_dlab_int) begin
                axi_rdata_d        = {{(AXI_DATA_WIDTH-DATA_WIDTH_UART){1'b0}}, rx_fifo_data_out_int};
                rx_fifo_pull_int_d = 1'b1;
              end else begin
                axi_rdata_d = {AXI_DATA_WIDTH{1'b0}};
              end
              axi_rresp_d  = `AXI4_RESP_OKAY;
            end

            UART_IER: begin
              axi_rdata_d  = {{(AXI_DATA_WIDTH-1){1'b0}}, uart_irq_en_int};
              axi_rresp_d  = `AXI4_RESP_OKAY;
            end

            UART_BAUD_DIVISOR: begin
              axi_rdata_d  = {{(AXI_DATA_WIDTH-AXI_DIV_WIDTH){1'b0}}, uart_baudrate_div_int};
              axi_rresp_d  = `AXI4_RESP_OKAY;
            end

            UART_LCR: begin
              axi_rdata_d  = uart_config_reg_int;
              axi_rresp_d  = `AXI4_RESP_OKAY;
            end

            UART_LSR: begin
              axi_rdata_d  = uart_lsr_reg_int;
              axi_rresp_d  = `AXI4_RESP_OKAY;
            end

            default: begin
              axi_rdata_d  = {AXI_DATA_WIDTH{1'b0}};
              axi_rresp_d  = `AXI4_RESP_SLVERR; // undefined register
            end
          endcase

          axi_rid_d    = ar_id_lat;
          axi_rvalid_d = 1'b1;

          // --- burst beat accounting ---
          if (ar_beat_cnt == ar_len_lat) begin
            axi_rlast_d   = 1'b1;           // mark last beat
            rx_fifo_reset_int_d = 1'b0;
            rd_state_d    = RD_IDLE;
          end else begin
            ar_beat_cnt_d = ar_beat_cnt + 1'b1;
          end
        end
      end

      default: begin
        rd_state_d          = RD_IDLE;
        axi_arready_d       = 1'b0;
        axi_rvalid_d        = 1'b0;
        axi_rlast_d         = 1'b0;
        rx_fifo_reset_int_d = 1'b1;
        rx_fifo_pull_int_d  = 1'b0;
      end
    endcase
  end

  // ---- READ FSM : sequential (fixed_clk domain) ----
  always @(posedge fixed_clk_i, negedge axi_aresetn_i) begin
    if (!axi_aresetn_i) begin
      rd_state          <= RD_IDLE;
      axi_arready       <= 1'b0;
      axi_rid           <= {AXI_ID_WIDTH{1'b0}};
      axi_rdata         <= {AXI_DATA_WIDTH{1'b0}};
      axi_rresp         <= 2'b0;
      axi_rlast         <= 1'b0;
      axi_rvalid        <= 1'b0;
      ar_id_lat         <= {AXI_ID_WIDTH{1'b0}};
      ar_addr_lat       <= {AXI_ADDR_WIDTH{1'b0}};
      ar_len_lat        <= {AXI_LEN_WIDTH{1'b0}};
      ar_beat_cnt       <= {AXI_LEN_WIDTH{1'b0}};
      rx_fifo_reset_int <= 1'b1;
      rx_fifo_pull_int  <= 1'b0;
    end else begin
      rd_state          <= rd_state_d;
      axi_arready       <= axi_arready_d;
      axi_rid           <= axi_rid_d;
      axi_rdata         <= axi_rdata_d;
      axi_rresp         <= axi_rresp_d;
      axi_rlast         <= axi_rlast_d;
      axi_rvalid        <= axi_rvalid_d;
      ar_id_lat         <= ar_id_lat_d;
      ar_addr_lat       <= ar_addr_lat_d;
      ar_len_lat        <= ar_len_lat_d;
      ar_beat_cnt       <= ar_beat_cnt_d;
      rx_fifo_reset_int <= rx_fifo_reset_int_d;
      rx_fifo_pull_int  <= rx_fifo_pull_int_d;
    end
  end

  // =========================================================================
  // Read interrupt generation
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
      .PORT_EN      (3'b000)  // [load | full | available_space] — only space needed
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
