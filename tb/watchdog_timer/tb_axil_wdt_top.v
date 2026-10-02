/* -----------------------------------------------------------------------------
 * Project        : RISC-V SoC / MBIST  —  AXI4-Lite Watchdog Timer IP
 * File           : tb_axil_wdt_top.v
 * Description    : Unit-level testbench for axil_wdt_top.
 *
 *   Uses the shared AXI4-Lite BFM master from tb/common/axil_bfm_master.v.
 *
 *   Test plan
 *   ---------
 *   TC01  Reset defaults — verify readable registers return 0/expected
 *   TC02  wdg_load write / read-back
 *   TC03  wdg_enable write / read-back and count decrementing verification
 *   TC04  wdg_kick resets countdown back to wdg_load
 *   TC05  Continuous kicking prevents timeout
 *   TC06  Countdown expiry: wdg_timeout_o asserts, timeout_occurred sets
 *   TC07  Post-mortem status latch: warm reset (axi_aresetn_i) preserves
 *           timeout_occurred=1 flag across reboot
 *   TC08  W1C clear: write 1 to wdg_status[0] clears timeout_occurred
 *   TC09  Early-warning interrupt: wdg_irq_pretimeout_o asserts on threshold
 *   TC10  SLVERR on write to read-only register wdg_count (0x00C)
 *   TC11  SLVERR on read/write to undefined offsets (0x018, 0xFFC)
 *   TC12  Cold reset (por_rstn_i) clears timeout_occurred
 * -----------------------------------------------------------------------------*/
`timescale 1ns/1ps

`define CLK_PERIOD 20   // 50 MHz clock

module tb_axil_wdt_top;

  // --------------------------------------------------------------------------
  // Parameters (must match axil_bfm_master.v defaults)
  // --------------------------------------------------------------------------
  parameter ADDR_WIDTH   = 32;
  parameter DATA_WIDTH   = 32;
  parameter ID_WIDTH     = 4;
  parameter RESP_TIMEOUT = 256;

  // Offsets (byte, relative to IP base 0x4000_5000)
  localparam OFFSET_ENABLE      = 32'h000;
  localparam OFFSET_LOAD        = 32'h004;
  localparam OFFSET_KICK        = 32'h008;
  localparam OFFSET_COUNT       = 32'h00C;
  localparam OFFSET_STATUS      = 32'h010;
  localparam OFFSET_PRETIMEOUT  = 32'h014;
  localparam OFFSET_UNDEF_18    = 32'h018;
  localparam OFFSET_UNDEF_FFC   = 32'hFFC;

  // Response codes
  localparam RESP_OKAY   = 2'b00;
  localparam RESP_SLVERR = 2'b10;

  // --------------------------------------------------------------------------
  // Clocks and resets
  // --------------------------------------------------------------------------
  reg axi_aclk;
  reg axi_aresetn;
  reg por_rstn;

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

  // Dedicated non-bus outputs
  wire                    wdg_timeout;
  wire                    wdg_irq_pretimeout;
  wire                    timeout_occurred;

  // --------------------------------------------------------------------------
  // DUT Instantiation
  // --------------------------------------------------------------------------
  axil_wdt_top #(
    .DEFAULT_LOAD       (32'd0),
    .DEFAULT_PRETIMEOUT (32'd0)
  ) dut (
    .axi_aclk_i           (axi_aclk),
    .axi_aresetn_i        (axi_aresetn),
    .por_rstn_i           (por_rstn),

    .axi_awid_i           (axil_awid),
    .axi_awaddr_i         (axil_awaddr),
    .axi_awprot_i         (axil_awprot),
    .axi_awvalid_i        (axil_awvalid),
    .axi_awready_o        (axil_awready),

    .axi_wdata_i          (axil_wdata),
    .axi_wstrb_i          (axil_wstrb),
    .axi_wvalid_i         (axil_wvalid),
    .axi_wready_o         (axil_wready),

    .axi_bid_o            (axil_bid),
    .axi_bresp_o          (axil_bresp),
    .axi_bvalid_o         (axil_bvalid),
    .axi_bready_i         (axil_bready),

    .axi_arid_i           (axil_arid),
    .axi_araddr_i         (axil_araddr),
    .axi_arprot_i         (axil_arprot),
    .axi_arvalid_i        (axil_arvalid),
    .axi_arready_o        (axil_arready),

    .axi_rid_o            (axil_rid),
    .axi_rdata_o          (axil_rdata),
    .axi_rresp_o          (axil_rresp),
    .axi_rvalid_o         (axil_rvalid),
    .axi_rready_i         (axil_rready),

    .wdg_timeout_o        (wdg_timeout),
    .wdg_irq_pretimeout_o (wdg_irq_pretimeout),
    .timeout_occurred_o   (timeout_occurred)
  );

  // --------------------------------------------------------------------------
  // Include shared AXI4-Lite BFM tasks
  // --------------------------------------------------------------------------
  `include "axil_bfm_master.v"

  // --------------------------------------------------------------------------
  // Test variables
  // --------------------------------------------------------------------------
  reg [DATA_WIDTH-1:0] rd_data;
  reg [1:0]            resp;
  integer              test_errors;
  integer              tc_num;

  // --------------------------------------------------------------------------
  // Helper tasks
  // --------------------------------------------------------------------------
  task do_cold_reset;
    begin
      por_rstn    <= 1'b0;
      axi_aresetn <= 1'b0;
      repeat (5) @(posedge axi_aclk);
      @(negedge axi_aclk);
      por_rstn    <= 1'b1;
      axi_aresetn <= 1'b1;
      repeat (2) @(posedge axi_aclk);
    end
  endtask

  task do_warm_reset;
    begin
      // por_rstn remains 1'b1
      axi_aresetn <= 1'b0;
      repeat (5) @(posedge axi_aclk);
      @(negedge axi_aclk);
      axi_aresetn <= 1'b1;
      repeat (2) @(posedge axi_aclk);
    end
  endtask

  task check_val;
    input [31:0] actual;
    input [31:0] expected;
    input [8*40:1] name;
    begin
      if (actual !== expected) begin
        $display("[FAIL] TC%02d: %0s mismatch! Expected: 0x%08h, Got: 0x%08h", tc_num, name, expected, actual);
        test_errors = test_errors + 1;
      end else begin
        $display("[PASS] TC%02d: %0s matched (0x%08h)", tc_num, name, actual);
      end
    end
  endtask

  task check_resp;
    input [1:0] actual;
    input [1:0] expected;
    input [8*20:1] op_name;
    begin
      if (actual !== expected) begin
        $display("[FAIL] TC%02d: %0s response mismatch! Expected: %b, Got: %b", tc_num, op_name, expected, actual);
        test_errors = test_errors + 1;
      end
    end
  endtask

  // --------------------------------------------------------------------------
  // Main Test Sequence
  // --------------------------------------------------------------------------
  initial begin
    test_errors  = 0;
    axil_awprot  = 3'b000;
    axil_arprot  = 3'b000;
    axil_awvalid = 1'b0;
    axil_wvalid  = 1'b0;
    axil_bready  = 1'b0;
    axil_arvalid = 1'b0;
    axil_rready  = 1'b0;

    $display("================================================================");
    $display("Starting AXI4-Lite Watchdog Timer (axil_wdt_top) Unit Tests");
    $display("================================================================");

    // Initial cold reset
    do_cold_reset();

    // ------------------------------------------------------------------------
    // TC01: Reset defaults
    // ------------------------------------------------------------------------
    tc_num = 1;
    $display("\n--- TC01: Verify Reset Defaults ---");
    axil_read(OFFSET_ENABLE, 4'h0, rd_data, resp);
    check_resp(resp, RESP_OKAY, "read enable");
    check_val(rd_data, 32'h0, "wdg_enable");

    axil_read(OFFSET_LOAD, 4'h0, rd_data, resp);
    check_resp(resp, RESP_OKAY, "read load");
    check_val(rd_data, 32'h0, "wdg_load");

    axil_read(OFFSET_COUNT, 4'h0, rd_data, resp);
    check_resp(resp, RESP_OKAY, "read count");
    check_val(rd_data, 32'h0, "wdg_count");

    axil_read(OFFSET_STATUS, 4'h0, rd_data, resp);
    check_resp(resp, RESP_OKAY, "read status");
    check_val(rd_data, 32'h0, "wdg_status");

    // ------------------------------------------------------------------------
    // TC02: Write & read wdg_load
    // ------------------------------------------------------------------------
    tc_num = 2;
    $display("\n--- TC02: Write / Read wdg_load ---");
    axil_write(OFFSET_LOAD, 32'h0000_0100, 4'hF, 4'h1, resp);
    check_resp(resp, RESP_OKAY, "write load");

    axil_read(OFFSET_LOAD, 4'h1, rd_data, resp);
    check_resp(resp, RESP_OKAY, "read load");
    check_val(rd_data, 32'h0000_0100, "wdg_load");

    // When disabled, wdg_count reflects wdg_load
    axil_read(OFFSET_COUNT, 4'h1, rd_data, resp);
    check_val(rd_data, 32'h0000_0100, "wdg_count");

    // ------------------------------------------------------------------------
    // TC03: Enable watchdog & verify countdown
    // ------------------------------------------------------------------------
    tc_num = 3;
    $display("\n--- TC03: Enable Watchdog & Verify Countdown ---");
    axil_write(OFFSET_LOAD, 32'd50, 4'hF, 4'h2, resp);
    axil_write(OFFSET_ENABLE, 32'd1, 4'hF, 4'h2, resp);

    repeat (10) @(posedge axi_aclk);

    axil_read(OFFSET_COUNT, 4'h2, rd_data, resp);
    if (rd_data < 32'd50 && rd_data > 32'd0) begin
      $display("[PASS] TC03: wdg_count is decrementing (current: %0d < 50)", rd_data);
    end else begin
      $display("[FAIL] TC03: wdg_count not decrementing properly! Current: %0d", rd_data);
      test_errors = test_errors + 1;
    end

    // ------------------------------------------------------------------------
    // TC04: Pet watchdog (wdg_kick)
    // ------------------------------------------------------------------------
    tc_num = 4;
    $display("\n--- TC04: Pet Watchdog via wdg_kick ---");
    axil_write(OFFSET_KICK, 32'h1234_5678, 4'hF, 4'h3, resp);
    check_resp(resp, RESP_OKAY, "write kick");

    axil_read(OFFSET_COUNT, 4'h3, rd_data, resp);
    if (rd_data >= 32'd45) begin
      $display("[PASS] TC04: wdg_count reloaded after kick (value: %0d)", rd_data);
    end else begin
      $display("[FAIL] TC04: wdg_count was not reloaded! Got: %0d", rd_data);
      test_errors = test_errors + 1;
    end

    // ------------------------------------------------------------------------
    // TC05: Continuous kicking prevents timeout
    // ------------------------------------------------------------------------
    tc_num = 5;
    $display("\n--- TC05: Continuous Kicking Prevents Timeout ---");
    repeat (5) begin
      repeat (15) @(posedge axi_aclk);
      axil_write(OFFSET_KICK, 32'h1, 4'hF, 4'h4, resp);
    end
    if (wdg_timeout == 1'b0) begin
      $display("[PASS] TC05: wdg_timeout remained 0 during periodic kicks");
    end else begin
      $display("[FAIL] TC05: wdg_timeout prematurely asserted!");
      test_errors = test_errors + 1;
    end

    // ------------------------------------------------------------------------
    // TC06: Countdown expiry triggers timeout
    // ------------------------------------------------------------------------
    tc_num = 6;
    $display("\n--- TC06: Countdown Expiry & Timeout Assertion ---");
    // Set smaller load for fast expiry
    axil_write(OFFSET_LOAD, 32'd15, 4'hF, 4'h5, resp);
    axil_write(OFFSET_KICK, 32'd1, 4'hF, 4'h5, resp);

    // Wait for countdown to reach 0
    repeat (20) @(posedge axi_aclk);

    if (wdg_timeout == 1'b1) begin
      $display("[PASS] TC06: wdg_timeout asserted after countdown expiry");
    end else begin
      $display("[FAIL] TC06: wdg_timeout failed to assert on expiry!");
      test_errors = test_errors + 1;
    end

    axil_read(OFFSET_STATUS, 4'h5, rd_data, resp);
    check_val(rd_data[0], 1'b1, "timeout_occurred in status");

    // ------------------------------------------------------------------------
    // TC07: Warm reset preservation of timeout_occurred
    // ------------------------------------------------------------------------
    tc_num = 7;
    $display("\n--- TC07: Post-Mortem Latch (Warm Reset Survival) ---");
    $display("Applying warm system reset (axi_aresetn asserted, por_rstn maintained high)...");
    do_warm_reset();

    // Verify registers reset to defaults
    axil_read(OFFSET_ENABLE, 4'h6, rd_data, resp);
    check_val(rd_data, 32'h0, "wdg_enable after warm reset");

    // BUT wdg_status must preserve timeout_occurred=1!
    axil_read(OFFSET_STATUS, 4'h6, rd_data, resp);
    check_resp(resp, RESP_OKAY, "read status post warm reset");
    check_val(rd_data[0], 1'b1, "timeout_occurred preserved post-mortem");

    // ------------------------------------------------------------------------
    // TC08: W1C clear of timeout_occurred
    // ------------------------------------------------------------------------
    tc_num = 8;
    $display("\n--- TC08: Write-1-to-Clear (W1C) Status Clear ---");
    axil_write(OFFSET_STATUS, 32'h0000_0001, 4'hF, 4'h7, resp);
    check_resp(resp, RESP_OKAY, "write status W1C");

    axil_read(OFFSET_STATUS, 4'h7, rd_data, resp);
    check_val(rd_data[0], 1'b0, "timeout_occurred cleared");

    // ------------------------------------------------------------------------
    // TC09: Pre-timeout early-warning interrupt
    // ------------------------------------------------------------------------
    tc_num = 9;
    $display("\n--- TC09: Early-Warning Pre-Timeout Interrupt ---");
    axil_write(OFFSET_LOAD, 32'd30, 4'hF, 4'h8, resp);
    axil_write(OFFSET_PRETIMEOUT, 32'd15, 4'hF, 4'h8, resp);
    axil_write(OFFSET_ENABLE, 32'd1, 4'hF, 4'h8, resp);

    // Count is ~30 > 15, pretimeout should be 0
    @(posedge axi_aclk);
    if (wdg_irq_pretimeout !== 1'b0) begin
      $display("[FAIL] TC09: wdg_irq_pretimeout asserted too early!");
      test_errors = test_errors + 1;
    end

    // Wait until count drops into pretimeout window (<= 15)
    repeat (18) @(posedge axi_aclk);
    if (wdg_irq_pretimeout == 1'b1) begin
      $display("[PASS] TC09: wdg_irq_pretimeout asserted in pretimeout window");
    end else begin
      $display("[FAIL] TC09: wdg_irq_pretimeout failed to assert! Count: %0d", dut.wdg_count);
      test_errors = test_errors + 1;
    end

    // Kick and verify pre-timeout clears
    axil_write(OFFSET_KICK, 32'd1, 4'hF, 4'h8, resp);
    @(posedge axi_aclk);
    if (wdg_irq_pretimeout == 1'b0) begin
      $display("[PASS] TC09: wdg_irq_pretimeout cleared upon kick");
    end else begin
      $display("[FAIL] TC09: wdg_irq_pretimeout did not clear upon kick!");
      test_errors = test_errors + 1;
    end

    // Disable WDT before next test
    axil_write(OFFSET_ENABLE, 32'd0, 4'hF, 4'h8, resp);

    // ------------------------------------------------------------------------
    // TC10: SLVERR on write to read-only register
    // ------------------------------------------------------------------------
    tc_num = 10;
    $display("\n--- TC10: SLVERR on Write to Read-Only Register wdg_count ---");
    axil_write(OFFSET_COUNT, 32'hDEAD_BEEF, 4'hF, 4'h9, resp);
    check_resp(resp, RESP_SLVERR, "write to RO wdg_count");

    // ------------------------------------------------------------------------
    // TC11: SLVERR on undefined offsets
    // ------------------------------------------------------------------------
    tc_num = 11;
    $display("\n--- TC11: SLVERR on Undefined Offsets ---");
    axil_read(OFFSET_UNDEF_18, 4'hA, rd_data, resp);
    check_resp(resp, RESP_SLVERR, "read undefined offset 0x018");

    axil_write(OFFSET_UNDEF_18, 32'h0, 4'hF, 4'hA, resp);
    check_resp(resp, RESP_SLVERR, "write undefined offset 0x018");

    axil_read(OFFSET_UNDEF_FFC, 4'hA, rd_data, resp);
    check_resp(resp, RESP_SLVERR, "read top of window 0xFFC");

    // ------------------------------------------------------------------------
    // TC12: Cold reset clears timeout_occurred
    // ------------------------------------------------------------------------
    tc_num = 12;
    $display("\n--- TC12: Cold Reset (POR) Clears timeout_occurred ---");
    // Trigger timeout again
    axil_write(OFFSET_LOAD, 32'd5, 4'hF, 4'hB, resp);
    axil_write(OFFSET_ENABLE, 32'd1, 4'hF, 4'hB, resp);
    repeat (10) @(posedge axi_aclk);

    axil_read(OFFSET_STATUS, 4'hB, rd_data, resp);
    check_val(rd_data[0], 1'b1, "timeout_occurred prior to cold reset");

    // Now apply full cold reset
    do_cold_reset();
    axil_read(OFFSET_STATUS, 4'hB, rd_data, resp);
    check_val(rd_data[0], 1'b0, "timeout_occurred cleared by cold reset");

    // ------------------------------------------------------------------------
    // Test Summary
    // ------------------------------------------------------------------------
    $display("\n================================================================");
    if (test_errors == 0) begin
      $display("ALL 12 TEST CASES PASSED SUCCESSFULLY!");
    end else begin
      $display("TEST FAILED WITH %0d ERROR(S)!", test_errors);
    end
    $display("================================================================\n");

    $finish;
  end

  // Simulation timeout watchdog
  initial begin
    #100000;
    $display("[TB ERROR] Simulation timeout reached!");
    $finish;
  end

endmodule
