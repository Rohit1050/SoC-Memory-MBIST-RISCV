/* -----------------------------------------------------------------------------
 * Project        : RISC-V SoC / MBIST  —  AXI4 to AXI4-Lite Protocol Bridge
 * File           : axi4_to_axil_bridge.v
 * Module         : axi4_to_axil_bridge
 * Description    : Downconverts 64-bit full AXI4 transactions from the crossbar
 *                  master ports (m01-m06) to 32-bit AXI4-Lite peripheral slave
 *                  ports (UART, Timers, GPIO, MBIST CSR, ECC Monitor, WDT).
 *
 * Parameters     :
 *   AXI4_DATA_WIDTH = 64
 *   AXIL_DATA_WIDTH = 32
 *   ADDR_WIDTH      = 32
 *   ID_WIDTH        = 4
 *
 * Functionality  :
 *   - Drops burst control signals not present in AXI4-Lite (awlen, awsize,
 *     awburst, awlock, awcache, awqos, wlast, arlen, arsize, arburst, etc.).
 *   - Extracts 32-bit slice and 4-bit strobes from 64-bit write data based on addr[2].
 *   - Replicates 32-bit read data across both 32-bit halves of the 64-bit read bus
 *     ({m_axil_rdata, m_axil_rdata}) and asserts rlast=1.
 *   - Propagates transaction IDs unchanged between AXI4 and AXI4-Lite.
 * -----------------------------------------------------------------------------*/
`timescale 1ns/1ps

`default_nettype none

module axi4_to_axil_bridge #
(
  parameter AXI4_DATA_WIDTH = 64,
  parameter AXIL_DATA_WIDTH = 32,
  parameter ADDR_WIDTH      = 32,
  parameter ID_WIDTH        = 4
)
(
  input  wire                                     clk,
  input  wire                                     rst_n,

  // -------------------------------------------------------------------------
  // AXI4 64-bit Slave Interface (from crossbar master port)
  // -------------------------------------------------------------------------
  // Write Address Channel (AW)
  input  wire [ID_WIDTH-1:0]                      s_axi_awid,
  input  wire [ADDR_WIDTH-1:0]                    s_axi_awaddr,
  input  wire [7:0]                               s_axi_awlen,
  input  wire [2:0]                               s_axi_awsize,
  input  wire [1:0]                               s_axi_awburst,
  input  wire                                     s_axi_awlock,
  input  wire [3:0]                               s_axi_awcache,
  input  wire [2:0]                               s_axi_awprot,
  input  wire [3:0]                               s_axi_awqos,
  input  wire [3:0]                               s_axi_awregion,
  input  wire                                     s_axi_awvalid,
  output wire                                     s_axi_awready,

  // Write Data Channel (W)
  input  wire [AXI4_DATA_WIDTH-1:0]               s_axi_wdata,
  input  wire [AXI4_DATA_WIDTH/8-1:0]             s_axi_wstrb,
  input  wire                                     s_axi_wlast,
  input  wire                                     s_axi_wvalid,
  output wire                                     s_axi_wready,

  // Write Response Channel (B)
  output wire [ID_WIDTH-1:0]                      s_axi_bid,
  output wire [1:0]                               s_axi_bresp,
  output wire                                     s_axi_bvalid,
  input  wire                                     s_axi_bready,

  // Read Address Channel (AR)
  input  wire [ID_WIDTH-1:0]                      s_axi_arid,
  input  wire [ADDR_WIDTH-1:0]                    s_axi_araddr,
  input  wire [7:0]                               s_axi_arlen,
  input  wire [2:0]                               s_axi_arsize,
  input  wire [1:0]                               s_axi_arburst,
  input  wire                                     s_axi_arlock,
  input  wire [3:0]                               s_axi_arcache,
  input  wire [2:0]                               s_axi_arprot,
  input  wire [3:0]                               s_axi_arqos,
  input  wire [3:0]                               s_axi_arregion,
  input  wire                                     s_axi_arvalid,
  output wire                                     s_axi_arready,

  // Read Data Channel (R)
  output wire [ID_WIDTH-1:0]                      s_axi_rid,
  output wire [AXI4_DATA_WIDTH-1:0]               s_axi_rdata,
  output wire [1:0]                               s_axi_rresp,
  output wire                                     s_axi_rlast,
  output wire                                     s_axi_rvalid,
  input  wire                                     s_axi_rready,

  // -------------------------------------------------------------------------
  // AXI4-Lite 32-bit Master Interface (to peripheral slave)
  // -------------------------------------------------------------------------
  // Write Address Channel (AW)
  output wire [ID_WIDTH-1:0]                      m_axil_awid,
  output wire [ADDR_WIDTH-1:0]                    m_axil_awaddr,
  output wire [2:0]                               m_axil_awprot,
  output wire                                     m_axil_awvalid,
  input  wire                                     m_axil_awready,

  // Write Data Channel (W)
  output wire [AXIL_DATA_WIDTH-1:0]               m_axil_wdata,
  output wire [AXIL_DATA_WIDTH/8-1:0]             m_axil_wstrb,
  output wire                                     m_axil_wvalid,
  input  wire                                     m_axil_wready,

  // Write Response Channel (B)
  input  wire [ID_WIDTH-1:0]                      m_axil_bid,
  input  wire [1:0]                               m_axil_bresp,
  input  wire                                     m_axil_bvalid,
  output wire                                     m_axil_bready,

  // Read Address Channel (AR)
  output wire [ID_WIDTH-1:0]                      m_axil_arid,
  output wire [ADDR_WIDTH-1:0]                    m_axil_araddr,
  output wire [2:0]                               m_axil_arprot,
  output wire                                     m_axil_arvalid,
  input  wire                                     m_axil_arready,

  // Read Data Channel (R)
  input  wire [ID_WIDTH-1:0]                      m_axil_rid,
  input  wire [AXIL_DATA_WIDTH-1:0]               m_axil_rdata,
  input  wire [1:0]                               m_axil_rresp,
  input  wire                                     m_axil_rvalid,
  output wire                                     m_axil_rready
);

  // Latch word selection bit for write channel in case AW handshakes before W
  reg aw_upper_lat;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_upper_lat <= 1'b0;
    end else if (s_axi_awvalid && s_axi_awready) begin
      aw_upper_lat <= s_axi_awaddr[2];
    end
  end

  wire aw_sel_upper = (s_axi_awvalid && s_axi_awready) ? s_axi_awaddr[2] : aw_upper_lat;

  // -------------------------------------------------------------------------
  // Write Address Channel Mapping
  // -------------------------------------------------------------------------
  assign m_axil_awid    = s_axi_awid;
  assign m_axil_awaddr  = s_axi_awaddr;
  assign m_axil_awprot  = s_axi_awprot;
  assign m_axil_awvalid = s_axi_awvalid;
  assign s_axi_awready  = m_axil_awready;

  // -------------------------------------------------------------------------
  // Write Data Channel Mapping (64 -> 32 downconversion)
  // -------------------------------------------------------------------------
  assign m_axil_wdata   = aw_sel_upper ? s_axi_wdata[63:32] : s_axi_wdata[31:0];
  assign m_axil_wstrb   = aw_sel_upper ? s_axi_wstrb[7:4]   : s_axi_wstrb[3:0];
  assign m_axil_wvalid  = s_axi_wvalid;
  assign s_axi_wready   = m_axil_wready;

  // -------------------------------------------------------------------------
  // Write Response Channel Mapping
  // -------------------------------------------------------------------------
  assign s_axi_bid      = m_axil_bid;
  assign s_axi_bresp    = m_axil_bresp;
  assign s_axi_bvalid   = m_axil_bvalid;
  assign m_axil_bready  = s_axi_bready;

  // -------------------------------------------------------------------------
  // Read Address Channel Mapping
  // -------------------------------------------------------------------------
  assign m_axil_arid    = s_axi_arid;
  assign m_axil_araddr  = s_axi_araddr;
  assign m_axil_arprot  = s_axi_arprot;
  assign m_axil_arvalid = s_axi_arvalid;
  assign s_axi_arready  = m_axil_arready;

  // -------------------------------------------------------------------------
  // Read Data Channel Mapping (32 -> 64 replication)
  // -------------------------------------------------------------------------
  assign s_axi_rid      = m_axil_rid;
  assign s_axi_rdata    = {m_axil_rdata, m_axil_rdata}; // duplicate word to both lanes
  assign s_axi_rresp    = m_axil_rresp;
  assign s_axi_rlast    = 1'b1;                          // single beat
  assign s_axi_rvalid   = m_axil_rvalid;
  assign m_axil_rready  = s_axi_rready;

endmodule

`default_nettype wire
