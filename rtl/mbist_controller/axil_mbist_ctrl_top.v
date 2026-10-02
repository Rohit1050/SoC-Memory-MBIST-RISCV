/* -----------------------------------------------------------------------------
 * Project        : RISC-V SoC / MBIST  —  AXI4-Lite MBIST Controller IP
 * File           : axil_mbist_ctrl_top.v
 * Module         : axil_mbist_ctrl_top
 * Description    : Top-level MBIST Controller IP combining:
 *                  1. AXI4-Lite Slave CSR Interface (32-bit registers)
 *                  2. Algorithmic Test Sequencer (mbist_algo_engine: Checkerboard & March C-)
 *                  3. 64-bit Full AXI4 Master DMA Port (mbist_dma_master to DCCM)
 *                  4. Sideband outputs to ECC Monitor, Watchdog, and PIC.
 *
 * Memory-map     : MBIST Controller CSR base = 0x4000_3000, window = 4 KB
 *                  Reached from axi_interconnect_wrap_4x7 master port m04
 *                  through the shared AXI4-to-AXI4-Lite bridge.
 *
 * Sub-modules    :
 *   - mbist_algo_engine.v   : Test algorithm sequencer
 *   - mbist_dma_master.v    : 64-bit AXI4 master DMA engine
 *   - axil_mbist_defines.vh : Shared defines
 * -----------------------------------------------------------------------------*/
`timescale 1ns/1ps

`default_nettype none

`include "axil_mbist_defines.vh"

module axil_mbist_ctrl_top #
(
  parameter AXIL_DATA_WIDTH = `_AXIL_MBIST_DATA_WIDTH_,     // 32
  parameter AXIL_ADDR_WIDTH = `_AXIL_MBIST_ADDR_WIDTH_,     // 32
  parameter AXIL_ID_WIDTH   = `_AXIL_MBIST_ID_WIDTH_,       //  4
  parameter AXIL_RESP_WIDTH = `_AXIL_MBIST_RESP_WIDTH_,     //  2

  parameter DMA_DATA_WIDTH  = `_AXI4_MBIST_DMA_DATA_WIDTH_, // 64
  parameter DMA_ADDR_WIDTH  = `_AXI4_MBIST_DMA_ADDR_WIDTH_, // 32
  parameter DMA_ID_WIDTH    = `_AXI4_MBIST_DMA_ID_WIDTH_,   //  4
  parameter DMA_STRB_WIDTH  = `_AXI4_MBIST_DMA_STRB_WIDTH_  //  8
)
(
  // -------------------------------------------------------------------------
  // Clocks and resets
  // -------------------------------------------------------------------------
  input  wire                                    axi_aclk_i,     // System / bus clock
  input  wire                                    axi_aresetn_i,  // Active-low synchronous reset

  // -------------------------------------------------------------------------
  // AXI4-Lite Slave CSR Interface (CPU LSU Master -> m04 -> Bridge -> Here)
  // -------------------------------------------------------------------------
  // Write Address Channel (AW)
  input  wire [AXIL_ID_WIDTH-1:0]                axi_awid_i,
  input  wire [AXIL_ADDR_WIDTH-1:0]              axi_awaddr_i,
  input  wire [2:0]                              axi_awprot_i,
  input  wire                                    axi_awvalid_i,
  output wire                                    axi_awready_o,

  // Write Data Channel (W)
  input  wire [AXIL_DATA_WIDTH-1:0]              axi_wdata_i,
  input  wire [AXIL_DATA_WIDTH/8-1:0]            axi_wstrb_i,
  input  wire                                    axi_wvalid_i,
  output wire                                    axi_wready_o,

  // Write Response Channel (B)
  output wire [AXIL_ID_WIDTH-1:0]                axi_bid_o,
  output wire [AXIL_RESP_WIDTH-1:0]              axi_bresp_o,
  output wire                                    axi_bvalid_o,
  input  wire                                    axi_bready_i,

  // Read Address Channel (AR)
  input  wire [AXIL_ID_WIDTH-1:0]                axi_arid_i,
  input  wire [AXIL_ADDR_WIDTH-1:0]              axi_araddr_i,
  input  wire [2:0]                              axi_arprot_i,
  input  wire                                    axi_arvalid_i,
  output wire                                    axi_arready_o,

  // Read Data Channel (R)
  output wire [AXIL_ID_WIDTH-1:0]                axi_rid_o,
  output wire [AXIL_DATA_WIDTH-1:0]              axi_rdata_o,
  output wire [AXIL_RESP_WIDTH-1:0]              axi_rresp_o,
  output wire                                    axi_rvalid_o,
  input  wire                                    axi_rready_i,

  // -------------------------------------------------------------------------
  // 64-bit Full AXI4 Master DMA Port (Here -> s03 / DMA Slave Port -> DCCM)
  // -------------------------------------------------------------------------
  // Write Address Channel (AW)
  output wire [DMA_ID_WIDTH-1:0]                 m_dma_axi_awid,
  output wire [DMA_ADDR_WIDTH-1:0]               m_dma_axi_awaddr,
  output wire [7:0]                              m_dma_axi_awlen,
  output wire [2:0]                              m_dma_axi_awsize,
  output wire [1:0]                              m_dma_axi_awburst,
  output wire                                    m_dma_axi_awlock,
  output wire [3:0]                              m_dma_axi_awcache,
  output wire [2:0]                              m_dma_axi_awprot,
  output wire [3:0]                              m_dma_axi_awqos,
  output wire                                    m_dma_axi_awvalid,
  input  wire                                    m_dma_axi_awready,

  // Write Data Channel (W)
  output wire [DMA_DATA_WIDTH-1:0]               m_dma_axi_wdata,
  output wire [DMA_STRB_WIDTH-1:0]               m_dma_axi_wstrb,
  output wire                                    m_dma_axi_wlast,
  output wire                                    m_dma_axi_wvalid,
  input  wire                                    m_dma_axi_wready,

  // Write Response Channel (B)
  input  wire [DMA_ID_WIDTH-1:0]                 m_dma_axi_bid,
  input  wire [1:0]                              m_dma_axi_bresp,
  input  wire                                    m_dma_axi_bvalid,
  output wire                                    m_dma_axi_bready,

  // Read Address Channel (AR)
  output wire [DMA_ID_WIDTH-1:0]                 m_dma_axi_arid,
  output wire [DMA_ADDR_WIDTH-1:0]               m_dma_axi_araddr,
  output wire [7:0]                              m_dma_axi_arlen,
  output wire [2:0]                              m_dma_axi_arsize,
  output wire [1:0]                              m_dma_axi_arburst,
  output wire                                    m_dma_axi_arlock,
  output wire [3:0]                              m_dma_axi_arcache,
  output wire [2:0]                              m_dma_axi_arprot,
  output wire [3:0]                              m_dma_axi_arqos,
  output wire                                    m_dma_axi_arvalid,
  input  wire                                    m_dma_axi_arready,

  // Read Data Channel (R)
  input  wire [DMA_ID_WIDTH-1:0]                 m_dma_axi_rid,
  input  wire [DMA_DATA_WIDTH-1:0]               m_dma_axi_rdata,
  input  wire [1:0]                              m_dma_axi_rresp,
  input  wire                                    m_dma_axi_rlast,
  input  wire                                    m_dma_axi_rvalid,
  output wire                                    m_dma_axi_rready,

  // -------------------------------------------------------------------------
  // Dedicated Sideband & Interrupt Interfaces
  // -------------------------------------------------------------------------
  input  wire                                    timer_tick_i,          // Auto-trigger from System Timer
  output wire                                    mbist_active_o,        // Output to ECC Mon & WDT
  output wire [DMA_ADDR_WIDTH-1:0]               mbist_fault_addr_tap_o,// Active window tap to ECC Mon
  output wire                                    mbist_irq_done_o       // Completion IRQ to PIC
);

  localparam AXI_LSB_WIDTH = 2; // byte offset to 32-bit word

  // =========================================================================
  // Architectural Configuration Registers
  // =========================================================================
  reg [1:0]                mbist_algo_sel,    mbist_algo_sel_d;
  reg [AXIL_ADDR_WIDTH-1:0] mbist_addr_start,  mbist_addr_start_d;
  reg [AXIL_ADDR_WIDTH-1:0] mbist_addr_end,    mbist_addr_end_d;
  reg                      mbist_done_lat,    mbist_done_lat_d;

  reg                      start_pulse;
  reg                      done_w1c_pulse;

  // Inter-module signals
  wire                     engine_busy;
  wire                     engine_done;
  wire                     engine_pass_fail;
  wire [DMA_ADDR_WIDTH-1:0] engine_fault_addr;
  wire [15:0]              engine_fault_count;
  wire [DMA_ADDR_WIDTH-1:0] engine_curr_addr;

  wire                     cmd_valid;
  wire                     cmd_write;
  wire [DMA_ADDR_WIDTH-1:0] cmd_addr;
  wire [DMA_DATA_WIDTH-1:0] cmd_wdata;
  wire                     cmd_ready;

  wire                     rsp_valid;
  wire [DMA_DATA_WIDTH-1:0] rsp_rdata;
  wire                     rsp_slverr;

  // Combine CSR write trigger and hardware timer trigger
  wire test_start = start_pulse | (timer_tick_i & !engine_busy);

  // =========================================================================
  // WRITE FSM
  // =========================================================================
  localparam WR_IDLE = 2'b00;
  localparam WR_DATA = 2'b01;
  localparam WR_RESP = 2'b10;

  reg [1:0]                wr_state,      wr_state_d;
  reg                      axi_awready,   axi_awready_d;
  reg [AXIL_ID_WIDTH-1:0]  aw_id_lat,     aw_id_lat_d;
  reg [AXIL_ADDR_WIDTH-1:0] aw_addr_lat,  aw_addr_lat_d;
  reg                      aw_done,       aw_done_d;

  reg                      axi_wready,    axi_wready_d;
  reg [AXIL_DATA_WIDTH-1:0] aw_wdata_lat, aw_wdata_lat_d;
  reg [3:0]                aw_wstrb_lat,  aw_wstrb_lat_d;
  reg                      w_done,        w_done_d;

  reg [AXIL_ID_WIDTH-1:0]  axi_bid,       axi_bid_d;
  reg [1:0]                axi_bresp,     axi_bresp_d;
  reg                      axi_bvalid,    axi_bvalid_d;

  wire aw_addr_in_window = (aw_addr_lat[AXIL_ADDR_WIDTH-1:12] == `MBIST_BASE_PREFIX) ||
                           (aw_addr_lat[AXIL_ADDR_WIDTH-1:12] == 20'h00000);

  always @(*) begin
    wr_state_d         = wr_state;
    axi_awready_d      = 1'b0;
    axi_wready_d       = axi_wready;
    axi_bid_d          = axi_bid;
    axi_bresp_d        = axi_bresp;
    axi_bvalid_d       = axi_bvalid;
    aw_id_lat_d        = aw_id_lat;
    aw_addr_lat_d      = aw_addr_lat;
    aw_wdata_lat_d     = aw_wdata_lat;
    aw_wstrb_lat_d     = aw_wstrb_lat;
    aw_done_d          = aw_done;
    w_done_d           = w_done;

    mbist_algo_sel_d   = mbist_algo_sel;
    mbist_addr_start_d = mbist_addr_start;
    mbist_addr_end_d   = mbist_addr_end;
    start_pulse        = 1'b0;
    done_w1c_pulse     = 1'b0;

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

            // 0x00 : mbist_start (W)
            `MBIST_REG_START: begin
              if (aw_wdata_lat[0]) begin
                start_pulse = 1'b1;
              end
              axi_bresp_d = `AXI_RESP_OKAY;
            end

            // 0x04 : mbist_algo_sel (R/W)
            `MBIST_REG_ALGO: begin
              mbist_algo_sel_d = aw_wdata_lat[1:0];
              axi_bresp_d      = `AXI_RESP_OKAY;
            end

            // 0x08 : mbist_addr_start (R/W)
            `MBIST_REG_ADDR_START: begin
              mbist_addr_start_d = aw_wdata_lat;
              axi_bresp_d        = `AXI_RESP_OKAY;
            end

            // 0x0C : mbist_addr_end (R/W)
            `MBIST_REG_ADDR_END: begin
              mbist_addr_end_d = aw_wdata_lat;
              axi_bresp_d      = `AXI_RESP_OKAY;
            end

            // 0x10 : mbist_busy (RO)
            `MBIST_REG_BUSY: begin
              axi_bresp_d = `AXI_RESP_SLVERR;
            end

            // 0x14 : mbist_done (RO / W1C)
            `MBIST_REG_DONE: begin
              if (aw_wdata_lat[0]) begin
                done_w1c_pulse = 1'b1;
              end
              axi_bresp_d = `AXI_RESP_OKAY;
            end

            // 0x18 : mbist_pass_fail (RO)
            `MBIST_REG_PASS_FAIL: begin
              axi_bresp_d = `AXI_RESP_SLVERR;
            end

            // 0x1C : mbist_fault_addr (RO)
            `MBIST_REG_FAULT_ADDR: begin
              axi_bresp_d = `AXI_RESP_SLVERR;
            end

            // 0x20 : mbist_fault_count (RO)
            `MBIST_REG_FAULT_COUNT: begin
              axi_bresp_d = `AXI_RESP_SLVERR;
            end

            default: begin
              axi_bresp_d = `AXI_RESP_SLVERR;
            end

          endcase
        end else begin
          axi_bresp_d = `AXI_RESP_SLVERR;
        end

        axi_bid_d    = aw_id_lat;
        axi_bvalid_d = 1'b1;
        wr_state_d   = WR_RESP;
      end

      WR_RESP: begin
        if (axi_bready_i) begin
          axi_bvalid_d = 1'b0;
          axi_bid_d    = {AXIL_ID_WIDTH{1'b0}};
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

  // Sequential Block for Write FSM and registers
  always @(posedge axi_aclk_i or negedge axi_aresetn_i) begin
    if (!axi_aresetn_i) begin
      wr_state         <= WR_IDLE;
      axi_awready      <= 1'b0;
      axi_wready       <= 1'b0;
      axi_bid          <= {AXIL_ID_WIDTH{1'b0}};
      axi_bresp        <= 2'b00;
      axi_bvalid       <= 1'b0;
      aw_id_lat        <= {AXIL_ID_WIDTH{1'b0}};
      aw_addr_lat      <= {AXIL_ADDR_WIDTH{1'b0}};
      aw_wdata_lat     <= {AXIL_DATA_WIDTH{1'b0}};
      aw_wstrb_lat     <= 4'h0;
      aw_done          <= 1'b0;
      w_done           <= 1'b0;
      mbist_algo_sel   <= `MBIST_ALGO_MARCH_C; // default to March C-
      mbist_addr_start <= 32'h0008_0000;       // default DCCM base
      mbist_addr_end   <= 32'h0009_FFF8;       // default 128 KB DCCM end
      mbist_done_lat   <= 1'b0;
    end else begin
      wr_state         <= wr_state_d;
      axi_awready      <= axi_awready_d;
      axi_wready       <= axi_wready_d;
      axi_bid          <= axi_bid_d;
      axi_bresp        <= axi_bresp_d;
      axi_bvalid       <= axi_bvalid_d;
      aw_id_lat        <= aw_id_lat_d;
      aw_addr_lat      <= aw_addr_lat_d;
      aw_wdata_lat     <= aw_wdata_lat_d;
      aw_wstrb_lat     <= aw_wstrb_lat_d;
      aw_done          <= aw_done_d;
      w_done           <= w_done_d;
      mbist_algo_sel   <= mbist_algo_sel_d;
      mbist_addr_start <= mbist_addr_start_d;
      mbist_addr_end   <= mbist_addr_end_d;

      // Handle mbist_done latching
      if (engine_done) begin
        mbist_done_lat <= 1'b1;
      end else if (test_start || done_w1c_pulse) begin
        mbist_done_lat <= 1'b0;
      end
    end
  end

  // Write outputs
  assign axi_awready_o = axi_awready;
  assign axi_wready_o  = axi_wready;
  assign axi_bid_o     = axi_bid;
  assign axi_bresp_o   = axi_bresp;
  assign axi_bvalid_o  = axi_bvalid;

  // =========================================================================
  // READ FSM
  // =========================================================================
  localparam RD_IDLE = 1'b0;
  localparam RD_DATA = 1'b1;

  reg                      rd_state,      rd_state_d;
  reg                      axi_arready,   axi_arready_d;
  reg [AXIL_ID_WIDTH-1:0]  ar_id_lat,     ar_id_lat_d;
  reg [AXIL_ADDR_WIDTH-1:0] ar_addr_lat,  ar_addr_lat_d;
  reg [AXIL_ID_WIDTH-1:0]  axi_rid,       axi_rid_d;
  reg [AXIL_DATA_WIDTH-1:0] axi_rdata,    axi_rdata_d;
  reg [1:0]                axi_rresp,     axi_rresp_d;
  reg                      axi_rvalid,    axi_rvalid_d;

  wire ar_addr_in_window = (ar_addr_lat[AXIL_ADDR_WIDTH-1:12] == `MBIST_BASE_PREFIX) ||
                           (ar_addr_lat[AXIL_ADDR_WIDTH-1:12] == 20'h00000);

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

              // 0x00 : mbist_start (reads 0)
              `MBIST_REG_START: begin
                axi_rdata_d = {AXIL_DATA_WIDTH{1'b0}};
                axi_rresp_d = `AXI_RESP_OKAY;
              end

              // 0x04 : mbist_algo_sel
              `MBIST_REG_ALGO: begin
                axi_rdata_d = {{(AXIL_DATA_WIDTH-2){1'b0}}, mbist_algo_sel};
                axi_rresp_d = `AXI_RESP_OKAY;
              end

              // 0x08 : mbist_addr_start
              `MBIST_REG_ADDR_START: begin
                axi_rdata_d = mbist_addr_start;
                axi_rresp_d = `AXI_RESP_OKAY;
              end

              // 0x0C : mbist_addr_end
              `MBIST_REG_ADDR_END: begin
                axi_rdata_d = mbist_addr_end;
                axi_rresp_d = `AXI_RESP_OKAY;
              end

              // 0x10 : mbist_busy
              `MBIST_REG_BUSY: begin
                axi_rdata_d = {{(AXIL_DATA_WIDTH-1){1'b0}}, engine_busy};
                axi_rresp_d = `AXI_RESP_OKAY;
              end

              // 0x14 : mbist_done
              `MBIST_REG_DONE: begin
                axi_rdata_d = {{(AXIL_DATA_WIDTH-1){1'b0}}, mbist_done_lat};
                axi_rresp_d = `AXI_RESP_OKAY;
              end

              // 0x18 : mbist_pass_fail
              `MBIST_REG_PASS_FAIL: begin
                axi_rdata_d = {{(AXIL_DATA_WIDTH-1){1'b0}}, engine_pass_fail};
                axi_rresp_d = `AXI_RESP_OKAY;
              end

              // 0x1C : mbist_fault_addr
              `MBIST_REG_FAULT_ADDR: begin
                axi_rdata_d = engine_fault_addr;
                axi_rresp_d = `AXI_RESP_OKAY;
              end

              // 0x20 : mbist_fault_count
              `MBIST_REG_FAULT_COUNT: begin
                axi_rdata_d = {{(AXIL_DATA_WIDTH-16){1'b0}}, engine_fault_count};
                axi_rresp_d = `AXI_RESP_OKAY;
              end

              default: begin
                axi_rdata_d = {AXIL_DATA_WIDTH{1'b0}};
                axi_rresp_d = `AXI_RESP_SLVERR;
              end

            endcase
          end else begin
            axi_rdata_d = {AXIL_DATA_WIDTH{1'b0}};
            axi_rresp_d = `AXI_RESP_SLVERR;
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

  // Sequential Block for Read FSM
  always @(posedge axi_aclk_i or negedge axi_aresetn_i) begin
    if (!axi_aresetn_i) begin
      rd_state    <= RD_IDLE;
      axi_arready <= 1'b0;
      ar_id_lat   <= {AXIL_ID_WIDTH{1'b0}};
      ar_addr_lat <= {AXIL_ADDR_WIDTH{1'b0}};
      axi_rid     <= {AXIL_ID_WIDTH{1'b0}};
      axi_rdata   <= {AXIL_DATA_WIDTH{1'b0}};
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

  // Read outputs
  assign axi_arready_o = axi_arready;
  assign axi_rid_o     = axi_rid;
  assign axi_rdata_o   = axi_rdata;
  assign axi_rresp_o   = axi_rresp;
  assign axi_rvalid_o  = axi_rvalid;

  // =========================================================================
  // Algorithm Engine Instantiation
  // =========================================================================
  mbist_algo_engine #(
    .DATA_WIDTH     (DMA_DATA_WIDTH),
    .ADDR_WIDTH     (DMA_ADDR_WIDTH)
  ) u_algo_engine (
    .clk_i          (axi_aclk_i),
    .rst_n_i        (axi_aresetn_i),

    .start_i        (test_start),
    .algo_sel_i     (mbist_algo_sel),
    .addr_start_i   (mbist_addr_start),
    .addr_end_i     (mbist_addr_end),

    .busy_o         (engine_busy),
    .done_o         (engine_done),
    .pass_fail_o    (engine_pass_fail),
    .fault_addr_o   (engine_fault_addr),
    .fault_count_o  (engine_fault_count),
    .active_o       (mbist_active_o),
    .current_addr_o (engine_curr_addr),

    .cmd_valid_o    (cmd_valid),
    .cmd_write_o    (cmd_write),
    .cmd_addr_o     (cmd_addr),
    .cmd_wdata_o    (cmd_wdata),
    .cmd_ready_i    (cmd_ready),

    .rsp_valid_i    (rsp_valid),
    .rsp_rdata_i    (rsp_rdata),
    .rsp_slverr_i   (rsp_slverr)
  );

  assign mbist_fault_addr_tap_o = engine_curr_addr;
  assign mbist_irq_done_o       = engine_done;

  // =========================================================================
  // 64-bit Full AXI4 DMA Master Engine Instantiation
  // =========================================================================
  mbist_dma_master #(
    .DATA_WIDTH     (DMA_DATA_WIDTH),
    .ADDR_WIDTH     (DMA_ADDR_WIDTH),
    .ID_WIDTH       (DMA_ID_WIDTH),
    .STRB_WIDTH     (DMA_STRB_WIDTH)
  ) u_dma_master (
    .clk_i          (axi_aclk_i),
    .rst_n_i        (axi_aresetn_i),

    .cmd_valid_i    (cmd_valid),
    .cmd_write_i    (cmd_write),
    .cmd_addr_i     (cmd_addr),
    .cmd_wdata_i    (cmd_wdata),
    .cmd_ready_o    (cmd_ready),

    .rsp_valid_o    (rsp_valid),
    .rsp_rdata_o    (rsp_rdata),
    .rsp_slverr_o   (rsp_slverr),

    // AW Channel
    .m_axi_awid     (m_dma_axi_awid),
    .m_axi_awaddr   (m_dma_axi_awaddr),
    .m_axi_awlen    (m_dma_axi_awlen),
    .m_axi_awsize   (m_dma_axi_awsize),
    .m_axi_awburst  (m_dma_axi_awburst),
    .m_axi_awlock   (m_dma_axi_awlock),
    .m_axi_awcache  (m_dma_axi_awcache),
    .m_axi_awprot   (m_dma_axi_awprot),
    .m_axi_awqos    (m_dma_axi_awqos),
    .m_axi_awvalid  (m_dma_axi_awvalid),
    .m_axi_awready  (m_dma_axi_awready),

    // W Channel
    .m_axi_wdata    (m_dma_axi_wdata),
    .m_axi_wstrb    (m_dma_axi_wstrb),
    .m_axi_wlast    (m_dma_axi_wlast),
    .m_axi_wvalid   (m_dma_axi_wvalid),
    .m_axi_wready   (m_dma_axi_wready),

    // B Channel
    .m_axi_bid      (m_dma_axi_bid),
    .m_axi_bresp    (m_dma_axi_bresp),
    .m_axi_bvalid   (m_dma_axi_bvalid),
    .m_axi_bready   (m_dma_axi_bready),

    // AR Channel
    .m_axi_arid     (m_dma_axi_arid),
    .m_axi_araddr   (m_dma_axi_araddr),
    .m_axi_arlen    (m_dma_axi_arlen),
    .m_axi_arsize   (m_dma_axi_arsize),
    .m_axi_arburst  (m_dma_axi_arburst),
    .m_axi_arlock   (m_dma_axi_arlock),
    .m_axi_arcache  (m_dma_axi_arcache),
    .m_axi_arprot   (m_dma_axi_arprot),
    .m_axi_arqos    (m_dma_axi_arqos),
    .m_axi_arvalid  (m_dma_axi_arvalid),
    .m_axi_arready  (m_dma_axi_arready),

    // R Channel
    .m_axi_rid      (m_dma_axi_rid),
    .m_axi_rdata    (m_dma_axi_rdata),
    .m_axi_rresp    (m_dma_axi_rresp),
    .m_axi_rlast    (m_dma_axi_rlast),
    .m_axi_rvalid   (m_dma_axi_rvalid),
    .m_axi_rready   (m_dma_axi_rready)
  );

endmodule

`default_nettype wire
