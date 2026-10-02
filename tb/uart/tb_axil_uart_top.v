/* -----------------------------------------------------------------------------
 * Project        : RISC-V SoC / MBIST  —  AXI4-Lite UART IP
 * File           : tb_axil_uart_top.v
 * Description    : Unit-level testbench for axil_uart_top.
 *
 *   Uses the shared AXI4-Lite BFM from tb/common/axil_bfm_master.v.
 *
 *   Test plan
 *   ---------
 *   TC01  LCR write / read-back at offset 0x00C
 *   TC02  BAUD_DIVISOR write / read-back at 0x008 (direct, DLAB irrelevant
 *         for this address)
 *   TC03  DLAB=1 gate: write via THR address while DLAB=1 → data suppressed
 *   TC04  DLAB=1 gate: read RBR via 0x000 while DLAB=1 → returns divisor
 *   TC05  IER write / read-back at 0x004; verify interrupt line tracks it
 *   TC06  TX write → byte appears on uart_tx_o (loopback through uart_rx_i)
 *   TC07  RX byte → RBR read returns correct data; LSR[0] clears after read
 *   TC08  TX FIFO full: write 16+1 bytes → 17th is silently dropped, no hang
 *   TC09  RX interrupt: IER[0]=1, RX byte arrives → read_interrupt_o asserts
 *         until RBR is read
 *   TC10  SLVERR: read/write to undefined offsets 0x010, 0x018, 0xFFC
 *
 *   Simulation parameters
 *     CLK_PERIOD  — system clock period (both axi_aclk and fixed_clk driven
 *                   from the same source; see clock-domain note in RTL header)
 *     BAUD_DIV    — baud divisor used during test (shortened for simulation)
 *
 * Revision History
 *  Rev | Description
 *  1.0 | Initial testbench.
 * -----------------------------------------------------------------------------*/
`timescale 1ns/1ps

`define CLK_PERIOD    20   // 50 MHz
`define BAUD_DIV      16   // shortened: baud period = 16 × 20 ns = 320 ns
`define UART_BITS     10   // 1 start + 8 data + 1 stop (no parity)
`define BAUD_PERIOD   (`BAUD_DIV * `CLK_PERIOD)

// ============================================================================
// Testbench top
// ============================================================================
module tb_axil_uart_top;

  // --------------------------------------------------------------------------
  // Parameters (mirrored from axil_uart_defines.vh for readability)
  // --------------------------------------------------------------------------
  parameter ADDR_WIDTH   = 32;
  parameter DATA_WIDTH   = 32;
  parameter ID_WIDTH     = 4;
  parameter RESP_TIMEOUT = 256;

  // Offsets (byte, from base — as seen by the DUT's axi_awaddr_i / axi_araddr_i)
  localparam OFFSET_RBR_THR    = 32'h000;
  localparam OFFSET_IER        = 32'h004;
  localparam OFFSET_BAUD_DIV   = 32'h008;
  localparam OFFSET_LCR        = 32'h00C;
  localparam OFFSET_LSR        = 32'h014;
  localparam OFFSET_RESERVED   = 32'h010;
  localparam OFFSET_UNDEF_1    = 32'h018;
  localparam OFFSET_UNDEF_END  = 32'hFFC;

  // Response codes
  localparam RESP_OKAY   = 2'b00;
  localparam RESP_SLVERR = 2'b10;

  // --------------------------------------------------------------------------
  // Clock and reset
  // --------------------------------------------------------------------------
  reg axi_aclk;
  reg axi_aresetn;

  initial axi_aclk = 0;
  always #(`CLK_PERIOD/2) axi_aclk = ~axi_aclk;

  // --------------------------------------------------------------------------
  // AXI4-Lite master signals (driven by BFM tasks)
  // --------------------------------------------------------------------------
  // Write Address channel
  reg  [ID_WIDTH-1:0]     axil_awid;
  reg  [ADDR_WIDTH-1:0]   axil_awaddr;
  reg                     axil_awvalid;
  wire                    axil_awready;

  // Write Data channel
  reg  [DATA_WIDTH-1:0]   axil_wdata;
  reg  [DATA_WIDTH/8-1:0] axil_wstrb;
  reg                     axil_wvalid;
  wire                    axil_wready;

  // Write Response channel
  wire [ID_WIDTH-1:0]     axil_bid;
  wire [1:0]              axil_bresp;
  wire                    axil_bvalid;
  reg                     axil_bready;

  // Read Address channel
  reg  [ID_WIDTH-1:0]     axil_arid;
  reg  [ADDR_WIDTH-1:0]   axil_araddr;
  reg                     axil_arvalid;
  wire                    axil_arready;

  // Read Data channel
  wire [ID_WIDTH-1:0]     axil_rid;
  wire [DATA_WIDTH-1:0]   axil_rdata;
  wire [1:0]              axil_rresp;
  wire                    axil_rvalid;
  reg                     axil_rready;

  // --------------------------------------------------------------------------
  // UART loopback: connect uart_tx_o → uart_rx_i
  // --------------------------------------------------------------------------
  wire uart_tx;
  wire read_irq;

  // --------------------------------------------------------------------------
  // DUT instantiation
  // --------------------------------------------------------------------------
  axil_uart_top dut (
    .fixed_clk_i      (axi_aclk),
    .axi_aclk_i       (axi_aclk),
    .axi_aresetn_i    (axi_aresetn),

    .axi_awid_i       (axil_awid),
    .axi_awaddr_i     (axil_awaddr),
    .axi_awvalid_i    (axil_awvalid),
    .axi_awready_o    (axil_awready),

    .axi_wdata_i      (axil_wdata),
    .axi_wstrb_i      (axil_wstrb),
    .axi_wvalid_i     (axil_wvalid),
    .axi_wready_o     (axil_wready),

    .axi_bid_o        (axil_bid),
    .axi_bresp_o      (axil_bresp),
    .axi_bvalid_o     (axil_bvalid),
    .axi_bready_i     (axil_bready),

    .axi_arid_i       (axil_arid),
    .axi_araddr_i     (axil_araddr),
    .axi_arvalid_i    (axil_arvalid),
    .axi_arready_o    (axil_arready),

    .axi_rid_o        (axil_rid),
    .axi_rdata_o      (axil_rdata),
    .axi_rresp_o      (axil_rresp),
    .axi_rvalid_o     (axil_rvalid),
    .axi_rready_i     (axil_rready),

    .read_interrupt_o (read_irq),
    .uart_rx_i        (uart_tx),   // loopback
    .uart_tx_o        (uart_tx)
  );

  // --------------------------------------------------------------------------
  // BFM task includes
  // --------------------------------------------------------------------------
  `include "../../tb/common/axil_bfm_master.v"

  // --------------------------------------------------------------------------
  // Helper: check helper — compares expected vs actual, prints PASS/FAIL
  // --------------------------------------------------------------------------
  integer pass_count;
  integer fail_count;

  task check;
    input [255:0]         name;
    input [DATA_WIDTH-1:0] expected;
    input [DATA_WIDTH-1:0] actual;
    begin
      if (expected === actual) begin
        $display("[PASS] %0s  expected=0x%08h  actual=0x%08h", name, expected, actual);
        pass_count = pass_count + 1;
      end else begin
        $display("[FAIL] %0s  expected=0x%08h  actual=0x%08h", name, expected, actual);
        fail_count = fail_count + 1;
      end
    end
  endtask

  task check_resp;
    input [255:0] name;
    input [1:0]   expected;
    input [1:0]   actual;
    begin
      if (expected === actual) begin
        $display("[PASS] %0s  RESP expected=%0b  actual=%0b", name, expected, actual);
        pass_count = pass_count + 1;
      end else begin
        $display("[FAIL] %0s  RESP expected=%0b  actual=%0b", name, expected, actual);
        fail_count = fail_count + 1;
      end
    end
  endtask

  // --------------------------------------------------------------------------
  // Stimulus
  // --------------------------------------------------------------------------
  reg [DATA_WIDTH-1:0] rd_data;
  reg [1:0]            rd_resp;
  reg [1:0]            wr_resp;
  integer              i;
  reg [7:0]            rx_byte;

  initial begin
    // Initialise BFM signals
    axil_awid    = {ID_WIDTH{1'b0}};
    axil_awaddr  = {ADDR_WIDTH{1'b0}};
    axil_awvalid = 1'b0;
    axil_wdata   = {DATA_WIDTH{1'b0}};
    axil_wstrb   = {(DATA_WIDTH/8){1'b1}};
    axil_wvalid  = 1'b0;
    axil_bready  = 1'b0;
    axil_arid    = {ID_WIDTH{1'b0}};
    axil_araddr  = {ADDR_WIDTH{1'b0}};
    axil_arvalid = 1'b0;
    axil_rready  = 1'b0;

    pass_count = 0;
    fail_count = 0;

    // Reset sequence
    axi_aresetn = 1'b0;
    repeat (4) @(posedge axi_aclk);
    @(negedge axi_aclk);
    axi_aresetn = 1'b1;
    repeat (4) @(posedge axi_aclk);

    // ======================================================================
    // TC01  LCR write / read-back
    // ======================================================================
    $display("\n--- TC01: LCR write/read-back ---");
    // Write LCR: DLAB=0, even parity, 2 stop bits → 0x00000006
    axil_write(OFFSET_LCR, 32'h00000006, 4'hF, 4'h1, wr_resp);
    check_resp("TC01 WR bresp", RESP_OKAY, wr_resp);
    axil_read(OFFSET_LCR, 4'h1, rd_data, rd_resp);
    check_resp("TC01 RD rresp", RESP_OKAY, rd_resp);
    check("TC01 LCR value", 32'h00000006, rd_data);

    // ======================================================================
    // TC02  BAUD_DIVISOR write / read-back
    // ======================================================================
    $display("\n--- TC02: BAUD_DIVISOR write/read-back ---");
    axil_write(OFFSET_BAUD_DIV, 32'h000000D2 /*210*/, 4'hF, 4'h1, wr_resp);
    check_resp("TC02 WR bresp", RESP_OKAY, wr_resp);
    axil_read(OFFSET_BAUD_DIV, 4'h1, rd_data, rd_resp);
    check_resp("TC02 RD rresp", RESP_OKAY, rd_resp);
    check("TC02 BAUD_DIV value", 32'h000000D2, rd_data);

    // Restore to simulation divisor
    axil_write(OFFSET_BAUD_DIV, `BAUD_DIV, 4'hF, 4'h1, wr_resp);

    // ======================================================================
    // TC03  DLAB=1: write to THR address → data suppressed, OKAY response
    // ======================================================================
    $display("\n--- TC03: DLAB=1 suppresses THR write ---");
    // Set DLAB=1 in LCR
    axil_write(OFFSET_LCR, 32'h00000080, 4'hF, 4'h1, wr_resp);
    // Write to 0x000 while DLAB=1 → should be silently dropped
    axil_write(OFFSET_RBR_THR, 32'h000000AA, 4'hF, 4'h2, wr_resp);
    check_resp("TC03 THR suppress WR bresp", RESP_OKAY, wr_resp);
    // Read LSR[5] (THRE) — TX FIFO must still be empty (no byte was pushed)
    axil_read(OFFSET_LSR, 4'h2, rd_data, rd_resp);
    check("TC03 LSR THRE still set (FIFO empty)", 32'h00000060, rd_data & 32'h00000060);
    // Clear DLAB
    axil_write(OFFSET_LCR, 32'h00000000, 4'hF, 4'h1, wr_resp);

    // ======================================================================
    // TC04  DLAB=1: read at RBR address returns BAUD_DIVISOR
    // ======================================================================
    $display("\n--- TC04: DLAB=1 RBR read returns BAUD_DIVISOR ---");
    axil_write(OFFSET_BAUD_DIV, 32'h00000010 /*16*/, 4'hF, 4'h1, wr_resp);
    axil_write(OFFSET_LCR, 32'h00000080, 4'hF, 4'h1, wr_resp); // DLAB=1
    axil_read(OFFSET_RBR_THR, 4'h1, rd_data, rd_resp);
    check_resp("TC04 RD rresp", RESP_OKAY, rd_resp);
    check("TC04 DLAB RBR returns div", 32'h00000010, rd_data & 32'h0000FFFF);
    axil_write(OFFSET_LCR, 32'h00000000, 4'hF, 4'h1, wr_resp); // DLAB=0

    // ======================================================================
    // TC05  IER write / read-back; verify interrupt line
    // ======================================================================
    $display("\n--- TC05: IER write/read and interrupt enable ---");
    axil_write(OFFSET_IER, 32'h00000001, 4'hF, 4'h1, wr_resp);
    check_resp("TC05 WR bresp", RESP_OKAY, wr_resp);
    axil_read(OFFSET_IER, 4'h1, rd_data, rd_resp);
    check_resp("TC05 RD rresp", RESP_OKAY, rd_resp);
    check("TC05 IER value", 32'h00000001, rd_data & 32'h00000001);

    // ======================================================================
    // TC06  TX write → loopback → RX byte in FIFO
    //   (loopback: tx→rx at UART bit level; wait for transmission to complete)
    // ======================================================================
    $display("\n--- TC06: TX write / loopback RX ---");
    // Ensure DLAB=0, IER[0]=1
    axil_write(OFFSET_LCR, 32'h00000000, 4'hF, 4'h1, wr_resp);
    axil_write(OFFSET_IER, 32'h00000001, 4'hF, 4'h1, wr_resp);
    // Write byte 0x55 to THR
    axil_write(OFFSET_RBR_THR, 32'h00000055, 4'hF, 4'h3, wr_resp);
    check_resp("TC06 THR WR bresp", RESP_OKAY, wr_resp);
    // Wait enough time for the byte to transmit and be received via loopback
    // Transmission: 10 bit-periods (start + 8 data + stop)
    repeat (`UART_BITS * `BAUD_DIV * 2) @(posedge axi_aclk);
    // Read RBR
    axil_read(OFFSET_RBR_THR, 4'h3, rd_data, rd_resp);
    check_resp("TC06 RBR RD rresp", RESP_OKAY, rd_resp);
    check("TC06 loopback byte", 32'h00000055, rd_data & 32'h000000FF);

    // ======================================================================
    // TC07  RX arrival → read_interrupt_o asserts; clears after RBR read
    // ======================================================================
    $display("\n--- TC07: RX interrupt assert/clear ---");
    // IER[0] already set from TC05; TX another byte and wait for RX
    axil_write(OFFSET_RBR_THR, 32'h000000A5, 4'hF, 4'h4, wr_resp);
    repeat (`UART_BITS * `BAUD_DIV * 2) @(posedge axi_aclk);
    // Interrupt should be asserted (RX FIFO non-empty, IER[0]=1)
    @(posedge axi_aclk);
    check("TC07 IRQ asserted",  1'b1, read_irq);
    // Read RBR → pops the byte → interrupt should clear
    axil_read(OFFSET_RBR_THR, 4'h4, rd_data, rd_resp);
    check("TC07 RBR byte", 32'h000000A5, rd_data & 32'h000000FF);
    repeat (2) @(posedge axi_aclk);
    check("TC07 IRQ cleared", 1'b0, read_irq);

    // ======================================================================
    // TC08  TX FIFO full: write 17 bytes → 17th dropped, no hang
    // ======================================================================
    $display("\n--- TC08: TX FIFO full edge case ---");
    // Disable IER to avoid interrupt noise
    axil_write(OFFSET_IER, 32'h00000000, 4'hF, 4'h1, wr_resp);
    for (i = 0; i < 17; i = i + 1) begin
      axil_write(OFFSET_RBR_THR, i[DATA_WIDTH-1:0], 4'hF, 4'h5, wr_resp);
      check_resp("TC08 THR WR bresp", RESP_OKAY, wr_resp);
    end
    // LSR[5] (THRE) should now be 0 (FIFO full)
    axil_read(OFFSET_LSR, 4'h5, rd_data, rd_resp);
    check("TC08 THRE=0 when full", 1'b0, rd_data[5]);
    $display("[INFO] TC08: 17 writes accepted without hang (17th dropped).");
    // Drain the FIFO: wait for all bytes to transmit
    repeat (17 * `UART_BITS * `BAUD_DIV * 3) @(posedge axi_aclk);

    // ======================================================================
    // TC09  RX interrupt: redundant check with explicit IER sequence
    // ======================================================================
    $display("\n--- TC09: RX interrupt full sequence ---");
    // Ensure RX FIFO is empty after TC07/TC08 drain
    axil_write(OFFSET_IER, 32'h00000001, 4'hF, 4'h1, wr_resp);
    axil_write(OFFSET_RBR_THR, 32'h0000003C, 4'hF, 4'h6, wr_resp);
    repeat (`UART_BITS * `BAUD_DIV * 2) @(posedge axi_aclk);
    @(posedge axi_aclk);
    check("TC09 IRQ asserted", 1'b1, read_irq);
    // Disable IER → interrupt should drop even though FIFO still has data
    axil_write(OFFSET_IER, 32'h00000000, 4'hF, 4'h1, wr_resp);
    @(posedge axi_aclk);
    check("TC09 IRQ masked", 1'b0, read_irq);
    // Re-enable and clear
    axil_write(OFFSET_IER, 32'h00000001, 4'hF, 4'h1, wr_resp);
    axil_read(OFFSET_RBR_THR, 4'h6, rd_data, rd_resp);
    check("TC09 RBR byte", 32'h0000003C, rd_data & 32'h000000FF);
    repeat (2) @(posedge axi_aclk);
    check("TC09 IRQ cleared", 1'b0, read_irq);

    // ======================================================================
    // TC10  SLVERR on undefined offsets
    // ======================================================================
    $display("\n--- TC10: SLVERR on undefined offsets ---");

    // Read 0x010 (reserved gap between LCR and LSR)
    axil_read(OFFSET_RESERVED, 4'h7, rd_data, rd_resp);
    check_resp("TC10 RD 0x010 rresp", RESP_SLVERR, rd_resp);

    // Write 0x010
    axil_write(OFFSET_RESERVED, 32'hDEADBEEF, 4'hF, 4'h7, wr_resp);
    check_resp("TC10 WR 0x010 bresp", RESP_SLVERR, wr_resp);

    // Read 0x018
    axil_read(OFFSET_UNDEF_1, 4'h7, rd_data, rd_resp);
    check_resp("TC10 RD 0x018 rresp", RESP_SLVERR, rd_resp);

    // Write 0x018
    axil_write(OFFSET_UNDEF_1, 32'hCAFEBABE, 4'hF, 4'h7, wr_resp);
    check_resp("TC10 WR 0x018 bresp", RESP_SLVERR, wr_resp);

    // Read top of 4 KB window (0xFFC)
    axil_read(OFFSET_UNDEF_END, 4'h7, rd_data, rd_resp);
    check_resp("TC10 RD 0xFFC rresp", RESP_SLVERR, rd_resp);

    // Write top of 4 KB window (0xFFC)
    axil_write(OFFSET_UNDEF_END, 32'hFFFFFFFF, 4'hF, 4'h7, wr_resp);
    check_resp("TC10 WR 0xFFC bresp", RESP_SLVERR, wr_resp);

    // ======================================================================
    // Summary
    // ======================================================================
    repeat (10) @(posedge axi_aclk);
    $display("\n========================================");
    $display("Test summary: PASS=%0d  FAIL=%0d", pass_count, fail_count);
    $display("========================================\n");
    if (fail_count == 0)
      $display("ALL TESTS PASSED");
    else
      $display("FAILURES DETECTED — see [FAIL] lines above");
    $finish;
  end

  // --------------------------------------------------------------------------
  // Simulation timeout watchdog
  // --------------------------------------------------------------------------
  initial begin
    #(1_000_000);
    $display("[ERROR] Simulation global timeout — hung transaction?");
    $finish;
  end

  // --------------------------------------------------------------------------
  // Optional waveform dump
  // --------------------------------------------------------------------------
  initial begin
    $dumpfile("tb_axil_uart_top.vcd");
    $dumpvars(0, tb_axil_uart_top);
  end

endmodule
