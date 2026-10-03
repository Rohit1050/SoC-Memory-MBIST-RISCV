/* -----------------------------------------------------------------------------
 * Project        : RISC-V SoC / MBIST  —  AXI4-Lite GPIO IP
 * File           : tb_axil_gpio_top.v
 * Description    : Unit-level testbench for axil_gpio_top.
 *
 *   Uses the shared AXI4-Lite BFM master from tb/common/axil_bfm_master.v.
 *
 *   Test plan
 *   ---------
 *   TC01  Reset defaults — gpio_dir=0, gpio_out_reg=0, gpio_in_reg=0,
 *           gpio_out_o all-zero, read-back all defined offsets return OKAY.
 *   TC02  Direction register R/W — write 0xAA, read back 0xAA.
 *   TC03  Output register R/W — write 0x55, read back 0x55.
 *   TC04  Output masking by direction:
 *           Set gpio_dir=0x0F, gpio_out_reg=0xFF.
 *           gpio_out_o must equal 0x0F (upper nibble masked to 0).
 *   TC05  Output enable per-bit — gpio_dir=0x01, gpio_out_reg=0x03 → gpio_out_o=0x01.
 *   TC06  gpio_in_i → gpio_in_reg synchronization:
 *           Drive gpio_in_i=0xA5, wait ≥3 clocks for sync chain to settle,
 *           read 0x008 and verify gpio_in_reg = 0xA5.
 *   TC07  Synchronized input is independent of gpio_dir:
 *           Set gpio_dir=0x00 (all inputs), drive gpio_in_i=0x5A,
 *           wait for sync, read 0x008 → expect 0x5A.
 *   TC08  Write to RO gpio_in_reg (0x008) returns OKAY, does not corrupt sync value:
 *           Set gpio_in_i=0x3C, wait for sync, write 0x008 = 0xFF, read back → 0x3C.
 *   TC09  SLVERR on write to undefined offset (0x00C).
 *   TC10  SLVERR on read from undefined offset (0x00C).
 *   TC11  SLVERR on read from offset 0xFFC (top of 4 KB window).
 *   TC12  All-zero gpio_in_i after non-zero: verify synchronizer propagates the
 *           change (no stuck-at behavior in sync chain).
 * -----------------------------------------------------------------------------*/
`timescale 1ns/1ps

`define CLK_PERIOD 20   // 50 MHz

module tb_axil_gpio_top;

  // --------------------------------------------------------------------------
  // BFM parameters (must match axil_bfm_master.v defaults)
  // --------------------------------------------------------------------------
  parameter ADDR_WIDTH   = 32;
  parameter DATA_WIDTH   = 32;
  parameter ID_WIDTH     = 4;
  parameter RESP_TIMEOUT = 256;

  // Byte offsets (relative addressing — DUT also accepts these directly)
  localparam OFFSET_DIR     = 32'h000;
  localparam OFFSET_OUT     = 32'h004;
  localparam OFFSET_IN      = 32'h008;
  localparam OFFSET_UNDEF_C = 32'h00C;
  localparam OFFSET_UNDEF_FFC = 32'hFFC;

  localparam RESP_OKAY   = 2'b00;
  localparam RESP_SLVERR = 2'b10;

  // --------------------------------------------------------------------------
  // Clock and reset
  // --------------------------------------------------------------------------
  reg axi_aclk;
  reg axi_aresetn;

  initial axi_aclk = 1'b0;
  always #(`CLK_PERIOD/2) axi_aclk = ~axi_aclk;

  // --------------------------------------------------------------------------
  // AXI4-Lite master signals (driven by BFM tasks)
  // --------------------------------------------------------------------------
  reg  [ID_WIDTH-1:0]     axil_awid;
  reg  [ADDR_WIDTH-1:0]   axil_awaddr;
  reg  [2:0]              axil_awprot;
  reg                     axil_awvalid;
  wire                    axil_awready;

  reg  [DATA_WIDTH-1:0]   axil_wdata;
  reg  [DATA_WIDTH/8-1:0] axil_wstrb;
  reg                     axil_wvalid;
  wire                    axil_wready;

  wire [ID_WIDTH-1:0]     axil_bid;
  wire [1:0]              axil_bresp;
  wire                    axil_bvalid;
  reg                     axil_bready;

  reg  [ID_WIDTH-1:0]     axil_arid;
  reg  [ADDR_WIDTH-1:0]   axil_araddr;
  reg  [2:0]              axil_arprot;
  reg                     axil_arvalid;
  wire                    axil_arready;

  wire [ID_WIDTH-1:0]     axil_rid;
  wire [DATA_WIDTH-1:0]   axil_rdata;
  wire [1:0]              axil_rresp;
  wire                    axil_rvalid;
  reg                     axil_rready;

  // --------------------------------------------------------------------------
  // GPIO I/O
  // --------------------------------------------------------------------------
  wire [7:0] gpio_out;
  reg  [7:0] gpio_in;

  // --------------------------------------------------------------------------
  // DUT instantiation
  // --------------------------------------------------------------------------
  axil_gpio_top #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDR_WIDTH),
    .ID_WIDTH   (ID_WIDTH)
  ) dut (
    .axi_aclk_i     (axi_aclk),
    .axi_aresetn_i  (axi_aresetn),

    .axi_awid_i     (axil_awid),
    .axi_awaddr_i   (axil_awaddr),
    .axi_awprot_i   (axil_awprot),
    .axi_awvalid_i  (axil_awvalid),
    .axi_awready_o  (axil_awready),

    .axi_wdata_i    (axil_wdata),
    .axi_wstrb_i    (axil_wstrb),
    .axi_wvalid_i   (axil_wvalid),
    .axi_wready_o   (axil_wready),

    .axi_bid_o      (axil_bid),
    .axi_bresp_o    (axil_bresp),
    .axi_bvalid_o   (axil_bvalid),
    .axi_bready_i   (axil_bready),

    .axi_arid_i     (axil_arid),
    .axi_araddr_i   (axil_araddr),
    .axi_arprot_i   (axil_arprot),
    .axi_arvalid_i  (axil_arvalid),
    .axi_arready_o  (axil_arready),

    .axi_rid_o      (axil_rid),
    .axi_rdata_o    (axil_rdata),
    .axi_rresp_o    (axil_rresp),
    .axi_rvalid_o   (axil_rvalid),
    .axi_rready_i   (axil_rready),

    .gpio_out_o     (gpio_out),
    .gpio_in_i      (gpio_in)
  );

  // --------------------------------------------------------------------------
  // BFM include (tasks: axil_write, axil_read)
  // --------------------------------------------------------------------------
  `include "../../tb/common/axil_bfm_master.v"

  // --------------------------------------------------------------------------
  // Test bookkeeping
  // --------------------------------------------------------------------------
  integer pass_count;
  integer fail_count;

  task report_pass;
    input [63:0] tc;
    begin
      $display("[PASS] TC%02d", tc);
      pass_count = pass_count + 1;
    end
  endtask

  task report_fail;
    input [63:0] tc;
    input [DATA_WIDTH-1:0] got;
    input [DATA_WIDTH-1:0] exp;
    begin
      $display("[FAIL] TC%02d  got=0x%08h  exp=0x%08h", tc, got, exp);
      fail_count = fail_count + 1;
    end
  endtask

  // --------------------------------------------------------------------------
  // Local BFM result variables
  // --------------------------------------------------------------------------
  reg [DATA_WIDTH-1:0] rd_data;
  reg [1:0]            rd_resp;
  reg [1:0]            wr_resp;

  // --------------------------------------------------------------------------
  // Initialise master signals to idle
  // --------------------------------------------------------------------------
  task init_bus;
    begin
      axil_awid    = {ID_WIDTH{1'b0}};
      axil_awaddr  = {ADDR_WIDTH{1'b0}};
      axil_awprot  = 3'b000;
      axil_awvalid = 1'b0;
      axil_wdata   = {DATA_WIDTH{1'b0}};
      axil_wstrb   = {(DATA_WIDTH/8){1'b0}};
      axil_wvalid  = 1'b0;
      axil_bready  = 1'b0;
      axil_arid    = {ID_WIDTH{1'b0}};
      axil_araddr  = {ADDR_WIDTH{1'b0}};
      axil_arprot  = 3'b000;
      axil_arvalid = 1'b0;
      axil_rready  = 1'b0;
    end
  endtask

  // --------------------------------------------------------------------------
  // Main stimulus
  // --------------------------------------------------------------------------
  initial begin
    pass_count  = 0;
    fail_count  = 0;
    gpio_in     = 8'h00;
    axi_aresetn = 1'b0;
    init_bus;

    // De-assert reset after a few clocks
    repeat(4) @(posedge axi_aclk);
    @(negedge axi_aclk);
    axi_aresetn = 1'b1;
    @(posedge axi_aclk);

    // ====================================================================
    // TC01: Reset defaults
    // ====================================================================
    axil_read(OFFSET_DIR, 4'h0, rd_data, rd_resp);
    if (rd_data === 32'h0 && rd_resp === RESP_OKAY) report_pass(1);
    else report_fail(1, rd_data, 32'h0);

    axil_read(OFFSET_OUT, 4'h0, rd_data, rd_resp);
    if (rd_data === 32'h0 && rd_resp === RESP_OKAY) report_pass(1);
    else report_fail(1, rd_data, 32'h0);

    axil_read(OFFSET_IN, 4'h0, rd_data, rd_resp);
    if (rd_data === 32'h0 && rd_resp === RESP_OKAY) report_pass(1);
    else report_fail(1, rd_data, 32'h0);

    if (gpio_out === 8'h00) report_pass(1);
    else report_fail(1, {24'h0, gpio_out}, 32'h0);

    // ====================================================================
    // TC02: gpio_dir write / read-back
    // ====================================================================
    axil_write(OFFSET_DIR, 32'h000000AA, 4'hF, 4'h1, wr_resp);
    if (wr_resp !== RESP_OKAY) report_fail(2, {30'h0, wr_resp}, {30'h0, RESP_OKAY});

    axil_read(OFFSET_DIR, 4'h1, rd_data, rd_resp);
    if (rd_data[7:0] === 8'hAA && rd_resp === RESP_OKAY) report_pass(2);
    else report_fail(2, rd_data, 32'h000000AA);

    // ====================================================================
    // TC03: gpio_out_reg write / read-back
    // ====================================================================
    axil_write(OFFSET_OUT, 32'h00000055, 4'hF, 4'h1, wr_resp);
    axil_read(OFFSET_OUT, 4'h1, rd_data, rd_resp);
    if (rd_data[7:0] === 8'h55 && rd_resp === RESP_OKAY) report_pass(3);
    else report_fail(3, rd_data, 32'h00000055);

    // ====================================================================
    // TC04: Output masking by direction  (dir=0x0F, out=0xFF → gpio_out=0x0F)
    // ====================================================================
    axil_write(OFFSET_DIR, 32'h0000000F, 4'hF, 4'h1, wr_resp);
    axil_write(OFFSET_OUT, 32'h000000FF, 4'hF, 4'h1, wr_resp);
    @(posedge axi_aclk); // one extra cycle for combinational settle
    if (gpio_out === 8'h0F) report_pass(4);
    else report_fail(4, {24'h0, gpio_out}, 32'h0000000F);

    // ====================================================================
    // TC05: Per-bit output enable  (dir=0x01, out=0x03 → gpio_out=0x01)
    // ====================================================================
    axil_write(OFFSET_DIR, 32'h00000001, 4'hF, 4'h1, wr_resp);
    axil_write(OFFSET_OUT, 32'h00000003, 4'hF, 4'h1, wr_resp);
    @(posedge axi_aclk);
    if (gpio_out === 8'h01) report_pass(5);
    else report_fail(5, {24'h0, gpio_out}, 32'h00000001);

    // ====================================================================
    // TC06: gpio_in_i → gpio_in_reg (2-flop synchronizer)
    // ====================================================================
    gpio_in = 8'hA5;
    repeat(4) @(posedge axi_aclk); // allow at least 2 clk for sync chain + margin
    axil_read(OFFSET_IN, 4'h0, rd_data, rd_resp);
    if (rd_data[7:0] === 8'hA5 && rd_resp === RESP_OKAY) report_pass(6);
    else report_fail(6, rd_data, 32'h000000A5);

    // ====================================================================
    // TC07: Synchronized input independent of gpio_dir
    // ====================================================================
    axil_write(OFFSET_DIR, 32'h00000000, 4'hF, 4'h1, wr_resp); // all inputs
    gpio_in = 8'h5A;
    repeat(4) @(posedge axi_aclk);
    axil_read(OFFSET_IN, 4'h0, rd_data, rd_resp);
    if (rd_data[7:0] === 8'h5A && rd_resp === RESP_OKAY) report_pass(7);
    else report_fail(7, rd_data, 32'h0000005A);

    // ====================================================================
    // TC08: Write to RO offset 0x008 returns OKAY, does not corrupt sync value
    // ====================================================================
    gpio_in = 8'h3C;
    repeat(4) @(posedge axi_aclk);
    axil_write(OFFSET_IN, 32'h000000FF, 4'hF, 4'h1, wr_resp);
    if (wr_resp !== RESP_OKAY) begin
      $display("[FAIL] TC08 write to RO got SLVERR, expected OKAY");
      fail_count = fail_count + 1;
    end
    // Read back — must still reflect synchronized gpio_in, not the written value
    axil_read(OFFSET_IN, 4'h0, rd_data, rd_resp);
    if (rd_data[7:0] === 8'h3C && rd_resp === RESP_OKAY) report_pass(8);
    else report_fail(8, rd_data, 32'h0000003C);

    // ====================================================================
    // TC09: SLVERR on write to undefined offset 0x00C
    // ====================================================================
    axil_write(OFFSET_UNDEF_C, 32'hDEADBEEF, 4'hF, 4'h1, wr_resp);
    if (wr_resp === RESP_SLVERR) report_pass(9);
    else report_fail(9, {30'h0, wr_resp}, {30'h0, RESP_SLVERR});

    // ====================================================================
    // TC10: SLVERR on read from undefined offset 0x00C
    // ====================================================================
    axil_read(OFFSET_UNDEF_C, 4'h0, rd_data, rd_resp);
    if (rd_resp === RESP_SLVERR) report_pass(10);
    else report_fail(10, {30'h0, rd_resp}, {30'h0, RESP_SLVERR});

    // ====================================================================
    // TC11: SLVERR on read from offset 0xFFC (top of 4 KB window)
    // ====================================================================
    axil_read(OFFSET_UNDEF_FFC, 4'h0, rd_data, rd_resp);
    if (rd_resp === RESP_SLVERR) report_pass(11);
    else report_fail(11, {30'h0, rd_resp}, {30'h0, RESP_SLVERR});

    // ====================================================================
    // TC12: Sync chain propagates 0 after non-zero (no stuck-at)
    // ====================================================================
    gpio_in = 8'hFF;
    repeat(4) @(posedge axi_aclk);
    axil_read(OFFSET_IN, 4'h0, rd_data, rd_resp);
    if (rd_data[7:0] !== 8'hFF) begin
      $display("[FAIL] TC12 pre-condition: expected 0xFF got 0x%02h", rd_data[7:0]);
      fail_count = fail_count + 1;
    end

    gpio_in = 8'h00;
    repeat(4) @(posedge axi_aclk);
    axil_read(OFFSET_IN, 4'h0, rd_data, rd_resp);
    if (rd_data[7:0] === 8'h00 && rd_resp === RESP_OKAY) report_pass(12);
    else report_fail(12, rd_data, 32'h00000000);

    // ====================================================================
    // Summary
    // ====================================================================
    $display("--------------------------------------------");
    $display("GPIO TB: %0d passed, %0d failed", pass_count, fail_count);
    $display("--------------------------------------------");
    if (fail_count == 0)
      $display("ALL TESTS PASSED");
    else
      $display("SOME TESTS FAILED");
    $finish;
  end

  // --------------------------------------------------------------------------
  // Timeout watchdog
  // --------------------------------------------------------------------------
  initial begin
    #500000;
    $display("[ERROR] Simulation timeout");
    $finish;
  end

endmodule
