/* -----------------------------------------------------------------------------
 * Project        : RISC-V SoC / MBIST  —  MBIST Controller IP
 * File           : mbist_dma_master.v
 * Module         : mbist_dma_master
 * Description    : 64-bit Full AXI4 Master transaction engine. Drives the
 *                  VeeR EL2 DMA Slave Port to read and write test patterns
 *                  to DCCM.
 *
 * Parameters     :
 *   DATA_WIDTH = 64
 *   ADDR_WIDTH = 32
 *   ID_WIDTH   = 4
 *   STRB_WIDTH = 8
 * -----------------------------------------------------------------------------*/
`timescale 1ns/1ps

`default_nettype none

`include "axil_mbist_defines.vh"

module mbist_dma_master #
(
  parameter DATA_WIDTH = `_AXI4_MBIST_DMA_DATA_WIDTH_, // 64
  parameter ADDR_WIDTH = `_AXI4_MBIST_DMA_ADDR_WIDTH_, // 32
  parameter ID_WIDTH   = `_AXI4_MBIST_DMA_ID_WIDTH_,   //  4
  parameter STRB_WIDTH = `_AXI4_MBIST_DMA_STRB_WIDTH_  //  8
)
(
  // -------------------------------------------------------------------------
  // Clock & reset
  // -------------------------------------------------------------------------
  input  wire                                clk_i,
  input  wire                                rst_n_i,

  // -------------------------------------------------------------------------
  // Command interface (from mbist_algo_engine)
  // -------------------------------------------------------------------------
  input  wire                                cmd_valid_i,
  input  wire                                cmd_write_i,     // 1 = write, 0 = read
  input  wire [ADDR_WIDTH-1:0]               cmd_addr_i,
  input  wire [DATA_WIDTH-1:0]               cmd_wdata_i,
  output wire                                cmd_ready_o,

  // Response interface (to mbist_algo_engine)
  output reg                                 rsp_valid_o,
  output reg  [DATA_WIDTH-1:0]               rsp_rdata_o,
  output reg                                 rsp_slverr_o,    // 1 if SLVERR detected

  // -------------------------------------------------------------------------
  // AXI4 64-bit Master Interface (to Core DMA Slave Port / Crossbar)
  // -------------------------------------------------------------------------
  // Write Address Channel (AW)
  output reg  [ID_WIDTH-1:0]                 m_axi_awid,
  output reg  [ADDR_WIDTH-1:0]               m_axi_awaddr,
  output wire [7:0]                          m_axi_awlen,
  output wire [2:0]                          m_axi_awsize,
  output wire [1:0]                          m_axi_awburst,
  output wire                                m_axi_awlock,
  output wire [3:0]                          m_axi_awcache,
  output wire [2:0]                          m_axi_awprot,
  output wire [3:0]                          m_axi_awqos,
  output reg                                 m_axi_awvalid,
  input  wire                                m_axi_awready,

  // Write Data Channel (W)
  output reg  [DATA_WIDTH-1:0]               m_axi_wdata,
  output wire [STRB_WIDTH-1:0]               m_axi_wstrb,
  output wire                                m_axi_wlast,
  output reg                                 m_axi_wvalid,
  input  wire                                m_axi_wready,

  // Write Response Channel (B)
  input  wire [ID_WIDTH-1:0]                 m_axi_bid,
  input  wire [1:0]                          m_axi_bresp,
  input  wire                                m_axi_bvalid,
  output reg                                 m_axi_bready,

  // Read Address Channel (AR)
  output reg  [ID_WIDTH-1:0]                 m_axi_arid,
  output reg  [ADDR_WIDTH-1:0]               m_axi_araddr,
  output wire [7:0]                          m_axi_arlen,
  output wire [2:0]                          m_axi_arsize,
  output wire [1:0]                          m_axi_arburst,
  output wire                                m_axi_arlock,
  output wire [3:0]                          m_axi_arcache,
  output wire [2:0]                          m_axi_arprot,
  output wire [3:0]                          m_axi_arqos,
  output reg                                 m_axi_arvalid,
  input  wire                                m_axi_arready,

  // Read Data Channel (R)
  input  wire [ID_WIDTH-1:0]                 m_axi_rid,
  input  wire [DATA_WIDTH-1:0]               m_axi_rdata,
  input  wire [1:0]                          m_axi_rresp,
  input  wire                                m_axi_rlast,
  input  wire                                m_axi_rvalid,
  output reg                                 m_axi_rready
);

  // Constant AXI4 transfer attributes
  assign m_axi_awlen   = 8'd0;       // single beat
  assign m_axi_awsize  = 3'b011;     // 64-bit (8 bytes)
  assign m_axi_awburst = 2'b01;      // INCR
  assign m_axi_awlock  = 1'b0;
  assign m_axi_awcache = 4'b0011;    // Bufferable / Normal
  assign m_axi_awprot  = 3'b000;
  assign m_axi_awqos   = 4'b0000;

  assign m_axi_wstrb   = 8'hFF;      // full 64-bit write (prevents RMW for ECC)
  assign m_axi_wlast   = 1'b1;       // always 1 for 1 beat

  assign m_axi_arlen   = 8'd0;       // single beat
  assign m_axi_arsize  = 3'b011;     // 64-bit (8 bytes)
  assign m_axi_arburst = 2'b01;      // INCR
  assign m_axi_arlock  = 1'b0;
  assign m_axi_arcache = 4'b0011;
  assign m_axi_arprot  = 3'b000;
  assign m_axi_arqos   = 4'b0000;

  // Master FSM States
  localparam [2:0]
    ST_IDLE      = 3'b000,
    ST_AW_W      = 3'b001,
    ST_B_RESP    = 3'b010,
    ST_AR        = 3'b011,
    ST_R_DATA    = 3'b100,
    ST_DONE      = 3'b101;

  reg [2:0] state, state_d;
  reg       aw_done, aw_done_d;
  reg       w_done,  w_done_d;

  assign cmd_ready_o = (state == ST_IDLE);

  // ---- Combinational Next-State Logic ----
  always @(*) begin
    state_d      = state;
    aw_done_d    = aw_done;
    w_done_d     = w_done;
    rsp_valid_o  = 1'b0;
    rsp_rdata_o  = m_axi_rdata;
    rsp_slverr_o = 1'b0;

    case (state)

      ST_IDLE: begin
        aw_done_d = 1'b0;
        w_done_d  = 1'b0;
        if (cmd_valid_i) begin
          if (cmd_write_i) begin
            state_d = ST_AW_W;
          end else begin
            state_d = ST_AR;
          end
        end
      end

      ST_AW_W: begin
        // Track completion of AW and W independently
        if (m_axi_awvalid && m_axi_awready) begin
          aw_done_d = 1'b1;
        end
        if (m_axi_wvalid && m_axi_wready) begin
          w_done_d = 1'b1;
        end

        // When both address and data have transferred, wait for response
        if ((aw_done_d || (m_axi_awvalid && m_axi_awready)) &&
            (w_done_d  || (m_axi_wvalid  && m_axi_wready))) begin
          state_d = ST_B_RESP;
        end
      end

      ST_B_RESP: begin
        if (m_axi_bvalid && m_axi_bready) begin
          rsp_valid_o  = 1'b1;
          rsp_slverr_o = (m_axi_bresp == `AXI_RESP_SLVERR);
          state_d      = ST_IDLE;
        end
      end

      ST_AR: begin
        if (m_axi_arvalid && m_axi_arready) begin
          state_d = ST_R_DATA;
        end
      end

      ST_R_DATA: begin
        if (m_axi_rvalid && m_axi_rready) begin
          rsp_valid_o  = 1'b1;
          rsp_rdata_o  = m_axi_rdata;
          rsp_slverr_o = (m_axi_rresp == `AXI_RESP_SLVERR);
          state_d      = ST_IDLE;
        end
      end

      default: begin
        state_d = ST_IDLE;
      end

    endcase
  end

  // ---- Sequential Logic ----
  always @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      state         <= ST_IDLE;
      aw_done       <= 1'b0;
      w_done        <= 1'b0;
      m_axi_awid    <= {ID_WIDTH{1'b0}};
      m_axi_awaddr  <= {ADDR_WIDTH{1'b0}};
      m_axi_awvalid <= 1'b0;
      m_axi_wdata   <= {DATA_WIDTH{1'b0}};
      m_axi_wvalid  <= 1'b0;
      m_axi_bready  <= 1'b0;
      m_axi_arid    <= {ID_WIDTH{1'b0}};
      m_axi_araddr  <= {ADDR_WIDTH{1'b0}};
      m_axi_arvalid <= 1'b0;
      m_axi_rready  <= 1'b0;
    end else begin
      state   <= state_d;
      aw_done <= aw_done_d;
      w_done  <= w_done_d;

      case (state)

        ST_IDLE: begin
          if (cmd_valid_i) begin
            if (cmd_write_i) begin
              m_axi_awid    <= 4'h3; // MBIST master ID
              m_axi_awaddr  <= cmd_addr_i;
              m_axi_awvalid <= 1'b1;
              m_axi_wdata   <= cmd_wdata_i;
              m_axi_wvalid  <= 1'b1;
              m_axi_bready  <= 1'b1;
            end else begin
              m_axi_arid    <= 4'h3;
              m_axi_araddr  <= cmd_addr_i;
              m_axi_arvalid <= 1'b1;
              m_axi_rready  <= 1'b1;
            end
          end
        end

        ST_AW_W: begin
          if (m_axi_awvalid && m_axi_awready) begin
            m_axi_awvalid <= 1'b0;
          end
          if (m_axi_wvalid && m_axi_wready) begin
            m_axi_wvalid <= 1'b0;
          end
        end

        ST_B_RESP: begin
          // m_axi_bready remains asserted
          if (m_axi_bvalid && m_axi_bready) begin
            m_axi_bready <= 1'b0;
          end
        end

        ST_AR: begin
          if (m_axi_arvalid && m_axi_arready) begin
            m_axi_arvalid <= 1'b0;
          end
        end

        ST_R_DATA: begin
          // m_axi_rready remains asserted
          if (m_axi_rvalid && m_axi_rready) begin
            m_axi_rready <= 1'b0;
          end
        end

        default: begin
          m_axi_awvalid <= 1'b0;
          m_axi_wvalid  <= 1'b0;
          m_axi_bready  <= 1'b0;
          m_axi_arvalid <= 1'b0;
          m_axi_rready  <= 1'b0;
        end

      endcase
    end
  end

endmodule

`default_nettype wire
