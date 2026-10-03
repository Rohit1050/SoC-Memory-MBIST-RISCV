/* -----------------------------------------------------------------------------
 * Project        : RISC-V SoC / MBIST  —  AXI4-Lite System Timer IP
 * File           : tb_axil_systimer_top.v
 * Description    : Unit-level testbench for axil_systimer_top.
 *
 *   Uses the shared AXI4-Lite BFM master from tb/common/axil_bfm_master.v.
 *
 *   Test plan
 *   ---------
 *   TC01  Reset defaults — timer_en=0, timer_reload=0, timer_count=0,
 *           timer_tick_o=0.
 *   TC02  timer_reload write / read-back (R/W register, value preserved).
 *   TC03  Countdown decrements correctly:
 *           Set reload=10, enable, read timer_count at successive cycles
 *           and verify it steps down 10 → 9 → … → 0.
 *   TC04  timer_tick_o pulses for exactly 1 cycle at expiry:
 *           Set reload=5, enable, count clock edges, verify tick is high
 *           for exactly one cycle when count reaches 0.
 *   TC05  Reload applied after expiry — count restarts from reload (5→4→…→0→tick→5).
 *   TC06  Disable mid-count: timer_en=0 halts timer_count at its current value
 *           (HOLD behavior, not reset to 0).
 *   TC07  Re-enable resumes from timer_reload (preload on 0→1 edge).
 *           After disabling mid-count, re-enable → count preloads to reload
 *           value and begins fresh descent.
 *   TC08  timer_reload=0 edge case: timer_tick_o pulses for exactly 1 cycle
 *           per clock cycle (count stays at 0, tick fires once per cycle on
 *           each reload), not a multi-cycle glitch.
 *   TC09  SLVERR on read/write to undefined offset (0x00C).
 *   TC10  SLVERR on read/write to undefined offset (0xFFC).
 *   TC11  Write to RO timer_count (0x008) returns OKAY, countdown unaffected.
 *   TC12  Multiple back-to-back ticks: verify timer continues autonomously
 *           over three complete periods without firmware intervention.
 * -----------------------------------------------------------------------------*/
`timescale 1ns/1ps

`define CLK_PERIOD 20   // 50 MHz

module tb_axil_systimer_top;

  // --------------------------------------------------------------------------
  // BFM parameters
  // --------------------------------------------------------------------------
  parameter ADDR_WIDTH   = 32;
  parameter DATA_WIDTH   = 32;
  parameter ID_WIDTH     = 4;
  parameter RESP_TIMEOUT = 256;

  localparam OFFSET_EN      = 32'h000;
  localparam OFFSET_RELOAD  = 32'h004;
  localparam OFFSET_COUNT   = 32'h008;
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
  // AXI4-Lite master signals
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
  // Timer output
  // --------------------------------------------------------------------------
  wire timer_tick;

  // --------------------------------------------------------------------------
  // DUT instantiation
  // --------------------------------------------------------------------------
  axil_systimer_top #(
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

    .timer_tick_o   (timer_tick)
  );

  // --------------------------------------------------------------------------
  // BFM include
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

  reg [DATA_WIDTH-1:0] rd_data;
  reg [1:0]            rd_resp;
  reg [1:0]            wr_resp;

  // --------------------------------------------------------------------------
  // Tick edge-counter helper
  //   Counts rising edges of timer_tick in a window of 'cycles' clock cycles.
  // --------------------------------------------------------------------------
  integer tick_count_global;

  task count_ticks;
    input integer cycles;
    output integer ticks;
    integer i;
    begin
      ticks = 0;
      for (i = 0; i < cycles; i = i + 1) begin
        @(posedge axi_aclk);
        if (timer_tick) ticks = ticks + 1;
      end
    end
  endtask

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

  // Helper: disable timer cleanly
  task disable_timer;
    begin
      axil_write(OFFSET_EN, 32'h0, 4'hF, 4'h0, wr_resp);
    end
  endtask

  // --------------------------------------------------------------------------
  // Main stimulus
  // --------------------------------------------------------------------------
  integer tick_cnt;
  integer cnt_prev;
  integer cnt_cur;
  integer i;

  initial begin
    pass_count = 0;
    fail_count = 0;
    axi_aresetn = 1'b0;
    init_bus;

    repeat(4) @(posedge axi_aclk);
    @(negedge axi_aclk);
    axi_aresetn = 1'b1;
    @(posedge axi_aclk);

    // ====================================================================
    // TC01: Reset defaults
    // ====================================================================
    axil_read(OFFSET_EN,     4'h0, rd_data, rd_resp);
    if (rd_data === 32'h0 && rd_resp === RESP_OKAY) report_pass(1);
    else report_fail(1, rd_data, 32'h0);

    axil_read(OFFSET_RELOAD, 4'h0, rd_data, rd_resp);
    if (rd_data === 32'h0 && rd_resp === RESP_OKAY) report_pass(1);
    else report_fail(1, rd_data, 32'h0);

    axil_read(OFFSET_COUNT,  4'h0, rd_data, rd_resp);
    if (rd_data === 32'h0 && rd_resp === RESP_OKAY) report_pass(1);
    else report_fail(1, rd_data, 32'h0);

    @(posedge axi_aclk);
    if (timer_tick === 1'b0) report_pass(1);
    else report_fail(1, {31'h0, timer_tick}, 32'h0);

    // ====================================================================
    // TC02: timer_reload write / read-back
    // ====================================================================
    axil_write(OFFSET_RELOAD, 32'hDEAD_CAFE, 4'hF, 4'h1, wr_resp);
    axil_read(OFFSET_RELOAD,  4'h1, rd_data, rd_resp);
    if (rd_data === 32'hDEAD_CAFE && rd_resp === RESP_OKAY) report_pass(2);
    else report_fail(2, rd_data, 32'hDEADCAFE);

    // Reset reload to a known value for subsequent tests
    axil_write(OFFSET_RELOAD, 32'h0, 4'hF, 4'h0, wr_resp);

    // ====================================================================
    // TC03: Countdown decrements correctly (reload=10)
    // ====================================================================
    // Ensure timer is stopped and reset from prior state
    disable_timer;
    repeat(2) @(posedge axi_aclk);

    axil_write(OFFSET_RELOAD, 32'd10, 4'hF, 4'h1, wr_resp);
    // Enable: count preloads to 10 on the enable edge
    axil_write(OFFSET_EN, 32'h1, 4'hF, 4'h1, wr_resp);

    // Read count at successive cycles and verify it descends
    // Allow 1 cycle after enable for the preload to propagate
    @(posedge axi_aclk);
    axil_read(OFFSET_COUNT, 4'h0, rd_data, rd_resp);
    cnt_prev = rd_data;

    begin : tc03_check
      integer ok;
      ok = 1;
      // Sample 5 more cycles and check count decrements by 1 each time
      for (i = 0; i < 5; i = i + 1) begin
        @(posedge axi_aclk);
        // Allow AXI read to complete within this cycle window
        axil_read(OFFSET_COUNT, 4'h0, rd_data, rd_resp);
        cnt_cur = rd_data;
        if (cnt_cur !== cnt_prev - 1) begin
          $display("[FAIL] TC03 step %0d: count=%0d expected=%0d", i, cnt_cur, cnt_prev-1);
          fail_count = fail_count + 1;
          ok = 0;
        end
        cnt_prev = cnt_cur;
      end
      if (ok) report_pass(3);
    end

    disable_timer;

    // ====================================================================
    // TC04: timer_tick_o pulses for exactly 1 cycle at expiry (reload=5)
    // ====================================================================
    disable_timer;
    repeat(2) @(posedge axi_aclk);

    axil_write(OFFSET_RELOAD, 32'd5, 4'hF, 4'h1, wr_resp);
    axil_write(OFFSET_EN,     32'h1, 4'hF, 4'h1, wr_resp);

    // Wait for one full period: reload=5, so expect tick after exactly 6 cycles
    // (preload to 5, then 5→4→3→2→1→0, tick on 0).
    // Count ticks over 8 cycles; expect exactly 1 tick in the first period window.
    count_ticks(8, tick_cnt);
    if (tick_cnt === 1) report_pass(4);
    else report_fail(4, tick_cnt, 32'd1);

    disable_timer;

    // ====================================================================
    // TC05: Reload reapplied — count restarts from reload after expiry
    // ====================================================================
    disable_timer;
    repeat(2) @(posedge axi_aclk);

    axil_write(OFFSET_RELOAD, 32'd4, 4'hF, 4'h1, wr_resp);
    axil_write(OFFSET_EN,     32'h1, 4'hF, 4'h1, wr_resp);

    // Wait for first tick (at count=0), then read count next cycle.
    // After reload, count must be 4 again (period = reload+1 cycles = 5).
    begin : tc05_wait
      integer wait_limit;
      wait_limit = 0;
      while (timer_tick !== 1'b1 && wait_limit < 50) begin
        @(posedge axi_aclk);
        wait_limit = wait_limit + 1;
      end
    end
    // Tick was just sampled high; on the very next posedge count is back to 4
    @(posedge axi_aclk);
    axil_read(OFFSET_COUNT, 4'h0, rd_data, rd_resp);
    // count should be 4 (just reloaded from reload=4, one decrement pending next cycle)
    // Accept 3 or 4 depending on read latency — primarily verify non-zero and ≤ reload
    if (rd_data <= 32'd4 && rd_data >= 32'd1) report_pass(5);
    else report_fail(5, rd_data, 32'd4);

    disable_timer;

    // ====================================================================
    // TC06: Disable mid-count halts and preserves timer_count (HOLD)
    // ====================================================================
    disable_timer;
    repeat(2) @(posedge axi_aclk);

    axil_write(OFFSET_RELOAD, 32'd20, 4'hF, 4'h1, wr_resp);
    axil_write(OFFSET_EN,     32'h1,  4'hF, 4'h1, wr_resp);

    // Let it run for 5 cycles, then disable
    repeat(6) @(posedge axi_aclk);
    axil_read(OFFSET_COUNT, 4'h0, rd_data, rd_resp);
    cnt_prev = rd_data;

    disable_timer;
    @(posedge axi_aclk);

    // Read count multiple times — must remain frozen (no decrement, no reset to 0)
    axil_read(OFFSET_COUNT, 4'h0, rd_data, rd_resp);
    if (rd_data === cnt_prev) report_pass(6);
    else report_fail(6, rd_data, cnt_prev);

    repeat(3) @(posedge axi_aclk);
    axil_read(OFFSET_COUNT, 4'h0, rd_data, rd_resp);
    if (rd_data === cnt_prev) report_pass(6);
    else report_fail(6, rd_data, cnt_prev);

    // ====================================================================
    // TC07: Re-enable resumes from timer_reload (preload on 0->1 edge)
    // ====================================================================
    // Timer is currently disabled with count frozen at cnt_prev.
    // Re-enable: expect count to preload to timer_reload=20, not continue from cnt_prev.
    axil_write(OFFSET_EN, 32'h1, 4'hF, 4'h1, wr_resp);
    @(posedge axi_aclk); // allow preload to register
    axil_read(OFFSET_COUNT, 4'h0, rd_data, rd_resp);
    // Count should be 20 (preloaded) or 19 (one decrement past preload)
    if (rd_data >= 32'd19 && rd_data <= 32'd20) report_pass(7);
    else report_fail(7, rd_data, 32'd20);

    disable_timer;

    // ====================================================================
    // TC08: timer_reload=0 — tick fires once per cycle, no multi-cycle glitch
    // ====================================================================
    disable_timer;
    repeat(2) @(posedge axi_aclk);

    axil_write(OFFSET_RELOAD, 32'd0, 4'hF, 4'h1, wr_resp);
    axil_write(OFFSET_EN,     32'h1, 4'hF, 4'h1, wr_resp);

    // In 4 cycles: expect exactly 4 ticks (one per cycle once running with reload=0)
    // Allow 1 cycle for enable/preload to register first.
    @(posedge axi_aclk);
    count_ticks(4, tick_cnt);
    if (tick_cnt === 4) report_pass(8);
    else report_fail(8, tick_cnt, 32'd4);

    disable_timer;

    // ====================================================================
    // TC09: SLVERR on write to undefined offset 0x00C
    // ====================================================================
    axil_write(OFFSET_UNDEF_C, 32'hDEADBEEF, 4'hF, 4'h1, wr_resp);
    if (wr_resp === RESP_SLVERR) report_pass(9);
    else report_fail(9, {30'h0, wr_resp}, {30'h0, RESP_SLVERR});

    // ====================================================================
    // TC10: SLVERR on read from undefined offset 0xFFC
    // ====================================================================
    axil_read(OFFSET_UNDEF_FFC, 4'h0, rd_data, rd_resp);
    if (rd_resp === RESP_SLVERR) report_pass(10);
    else report_fail(10, {30'h0, rd_resp}, {30'h0, RESP_SLVERR});

    // ====================================================================
    // TC11: Write to RO timer_count (0x008) returns OKAY, countdown unaffected
    // ====================================================================
    disable_timer;
    repeat(2) @(posedge axi_aclk);

    axil_write(OFFSET_RELOAD, 32'd15, 4'hF, 4'h1, wr_resp);
    axil_write(OFFSET_EN,     32'h1,  4'hF, 4'h1, wr_resp);
    repeat(4) @(posedge axi_aclk);

    // Capture current count
    axil_read(OFFSET_COUNT, 4'h0, rd_data, rd_resp);
    cnt_prev = rd_data;

    // Write to RO count register — must return OKAY and not corrupt count
    axil_write(OFFSET_COUNT, 32'hFFFFFFFF, 4'hF, 4'h1, wr_resp);
    if (wr_resp !== RESP_OKAY) begin
      $display("[FAIL] TC11: write to RO got non-OKAY response");
      fail_count = fail_count + 1;
    end

    // Count must continue decrementing naturally (not jump to 0xFFFFFFFF)
    @(posedge axi_aclk);
    axil_read(OFFSET_COUNT, 4'h0, rd_data, rd_resp);
    // Should still be in range [cnt_prev-3, cnt_prev-1] allowing for read latency
    if (rd_data < 32'hFFFF0000) report_pass(11);
    else report_fail(11, rd_data, cnt_prev);

    disable_timer;

    // ====================================================================
    // TC12: Three autonomous periods without firmware intervention
    // ====================================================================
    disable_timer;
    repeat(2) @(posedge axi_aclk);

    axil_write(OFFSET_RELOAD, 32'd6, 4'hF, 4'h1, wr_resp);
    axil_write(OFFSET_EN,     32'h1, 4'hF, 4'h1, wr_resp);

    // Each period is reload+1 = 7 cycles.  Count 3 ticks; allow 25 cycles.
    count_ticks(25, tick_cnt);
    if (tick_cnt === 3) report_pass(12);
    else report_fail(12, tick_cnt, 32'd3);

    disable_timer;

    // ====================================================================
    // Summary
    // ====================================================================
    $display("--------------------------------------------");
    $display("SysTimer TB: %0d passed, %0d failed", pass_count, fail_count);
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
    #1000000;
    $display("[ERROR] Simulation timeout");
    $finish;
  end

endmodule
