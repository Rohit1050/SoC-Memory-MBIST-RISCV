/* -----------------------------------------------------------------------------
 * Project        : RISC-V SoC / MBIST  —  AXI4-Lite ECC Monitor IP
 * File           : tb_axil_ecc_monitor_top.v
 * Description    : Unit-level testbench for axil_ecc_monitor_top.
 *
 *   Uses the shared AXI4-Lite BFM master from tb/common/axil_bfm_master.v.
 *
 *   Test plan
 *   ---------
 *   TC01  Reset defaults — all readable registers return 0 after reset
 *   TC02  ecc_mon_enable write / read-back
 *   TC03  ecc_mon_shadow_count write / read-back (27-bit field)
 *   TC04  ecc_mon_shadow_thresh write / read-back (5-bit field)
 *   TC05  ecc_mon_event always reads 0 (W1C — no stored state)
 *   TC06  Disable gating: event write with enable=0 → no state change
 *   TC07  Correlation with mbist_active=1: correctable_seen sets,
 *           suspect_addr latches mbist_fault_addr_tap, mbist_correlated sets
 *   TC08  No correlation with mbist_active=0: correctable_seen sets,
 *           suspect_addr unchanged, mbist_correlated unchanged
 *   TC09  W1C clear — ecc_mon_event always reads 0 before and after event
 *   TC10  Already-latched state preserved after ecc_mon_enable cleared
 *   TC11  SLVERR on write to RO register ecc_mon_suspect_addr (0x10)
 *   TC12  SLVERR on write to RO register ecc_mon_status (0x14)
 *   TC13  SLVERR on read/write to undefined offset 0x18
 *   TC14  SLVERR on read/write to top of 4 KB window (0xFFC)
 *   TC15  Sequential events: two back-to-back event writes with different
 *           mbist_fault_addr_tap values; second overwrites first
 *
 * Revision History
 *  Rev | Description
 *  1.0 | Initial testbench for axil_ecc_monitor_top.
 * -----------------------------------------------------------------------------*/
`timescale 1ns/1ps

`define CLK_PERIOD 20   // 50 MHz — same as UART TB for consistency

// ============================================================================
// Testbench top
// ============================================================================
module tb_axil_ecc_monitor_top;

  // --------------------------------------------------------------------------
  // BFM parameters (must match axil_bfm_master.v defaults)
  // --------------------------------------------------------------------------
  parameter ADDR_WIDTH   = 32;
  parameter DATA_WIDTH   = 32;
  parameter ID_WIDTH     = 4;
  parameter RESP_TIMEOUT = 256;

  // --------------------------------------------------------------------------
  // Register byte offsets (relative to IP base — as seen by axi_awaddr_i /
  // axi_araddr_i; the crossbar/bridge strips the global 0x4000_4000 prefix)
  // --------------------------------------------------------------------------
  localparam OFFSET_ENABLE       = 32'h000;  // ecc_mon_enable       R/W   1-bit
  localparam OFFSET_SHADOW_COUNT = 32'h004;  // ecc_mon_shadow_count R/W  27-bit
  localparam OFFSET_SHADOW_THRESH= 32'h008;  // ecc_mon_shadow_thresh R/W  5-bit
  localparam OFFSET_EVENT        = 32'h00C;  // ecc_mon_event        W1C   1-bit
  localparam OFFSET_SUSPECT_ADDR = 32'h010;  // ecc_mon_suspect_addr RO   32-bit
  localparam OFFSET_STATUS       = 32'h014;  // ecc_mon_status       RO    2-bit
  localparam OFFSET_UNDEF_18     = 32'h018;  // first undefined offset
  localparam OFFSET_UNDEF_FFC    = 32'hFFC;  // last offset in 4 KB window

  // AXI4-Lite response codes
  localparam RESP_OKAY   = 2'b00;
  localparam RESP_SLVERR = 2'b10;

  // Status register bit positions
  localparam STATUS_CORR_SEEN  = 0;  // correctable_seen
  localparam STATUS_MBIST_CORR = 1;  // mbist_correlated

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
  // Non-bus MBIST sideband signals (driven directly from test vectors)
  //   These represent what the MBIST Controller will eventually drive.
  //   No tie-off — left as freely assignable regs in the testbench.
  // --------------------------------------------------------------------------
  reg         mbist_active;
  reg  [31:0] mbist_fault_addr_tap;

  // --------------------------------------------------------------------------
  // DUT instantiation
  // --------------------------------------------------------------------------
  axil_ecc_monitor_top dut (
    .axi_aclk_i              (axi_aclk),
    .axi_aresetn_i           (axi_aresetn),

    // Write Address
    .axi_awid_i              (axil_awid),
    .axi_awaddr_i            (axil_awaddr),
    .axi_awprot_i            (3'b000),
    .axi_awvalid_i           (axil_awvalid),
    .axi_awready_o           (axil_awready),

    // Write Data
    .axi_wdata_i             (axil_wdata),
    .axi_wstrb_i             (axil_wstrb),
    .axi_wvalid_i            (axil_wvalid),
    .axi_wready_o            (axil_wready),

    // Write Response
    .axi_bid_o               (axil_bid),
    .axi_bresp_o             (axil_bresp),
    .axi_bvalid_o            (axil_bvalid),
    .axi_bready_i            (axil_bready),

    // Read Address
    .axi_arid_i              (axil_arid),
    .axi_araddr_i            (axil_araddr),
    .axi_arprot_i            (3'b000),
    .axi_arvalid_i           (axil_arvalid),
    .axi_arready_o           (axil_arready),

    // Read Data
    .axi_rid_o               (axil_rid),
    .axi_rdata_o             (axil_rdata),
    .axi_rresp_o             (axil_rresp),
    .axi_rvalid_o            (axil_rvalid),
    .axi_rready_i            (axil_rready),

    // MBIST sideband (driven from test vectors below)
    .mbist_active_i          (mbist_active),
    .mbist_fault_addr_tap_i  (mbist_fault_addr_tap)
  );

  // --------------------------------------------------------------------------
  // Shared AXI4-Lite BFM (tasks: axil_write, axil_read)
  // --------------------------------------------------------------------------
  `include "../../tb/common/axil_bfm_master.v"

  // --------------------------------------------------------------------------
  // Utility: check helpers
  // --------------------------------------------------------------------------
  integer pass_count;
  integer fail_count;

  task check;
    input [255:0]          tc_name;
    input [DATA_WIDTH-1:0] expected;
    input [DATA_WIDTH-1:0] actual;
    begin
      if (expected === actual) begin
        $display("[PASS] %0s  expected=0x%08h  actual=0x%08h",
                 tc_name, expected, actual);
        pass_count = pass_count + 1;
      end else begin
        $display("[FAIL] %0s  expected=0x%08h  actual=0x%08h",
                 tc_name, expected, actual);
        fail_count = fail_count + 1;
      end
    end
  endtask

  task check_resp;
    input [255:0] tc_name;
    input [1:0]   expected;
    input [1:0]   actual;
    begin
      if (expected === actual) begin
        $display("[PASS] %0s  RESP expected=%0b  actual=%0b",
                 tc_name, expected, actual);
        pass_count = pass_count + 1;
      end else begin
        $display("[FAIL] %0s  RESP expected=%0b  actual=%0b",
                 tc_name, expected, actual);
        fail_count = fail_count + 1;
      end
    end
  endtask

  // --------------------------------------------------------------------------
  // Utility: reset DUT to a known clean state
  //   (useful between test cases that need a pristine register state)
  // --------------------------------------------------------------------------
  task do_reset;
    begin
      axi_aresetn = 1'b0;
      repeat (4) @(posedge axi_aclk);
      @(negedge axi_aclk);
      axi_aresetn = 1'b1;
      repeat (4) @(posedge axi_aclk);
    end
  endtask

  // --------------------------------------------------------------------------
  // Stimulus variables
  // --------------------------------------------------------------------------
  reg [DATA_WIDTH-1:0] rd_data;
  reg [1:0]            rd_resp;
  reg [1:0]            wr_resp;

  // ==========================================================================
  // Main stimulus
  // ==========================================================================
  initial begin

    // -- Initialise BFM / sideband signals -----------------------------------
    axil_awid           = {ID_WIDTH{1'b0}};
    axil_awaddr         = {ADDR_WIDTH{1'b0}};
    axil_awvalid        = 1'b0;
    axil_wdata          = {DATA_WIDTH{1'b0}};
    axil_wstrb          = {(DATA_WIDTH/8){1'b1}};
    axil_wvalid         = 1'b0;
    axil_bready         = 1'b0;
    axil_arid           = {ID_WIDTH{1'b0}};
    axil_araddr         = {ADDR_WIDTH{1'b0}};
    axil_arvalid        = 1'b0;
    axil_rready         = 1'b0;

    mbist_active        = 1'b0;
    mbist_fault_addr_tap= 32'h0000_0000;

    pass_count = 0;
    fail_count = 0;

    // -- Initial reset -------------------------------------------------------
    do_reset;

    // ========================================================================
    // TC01 — Reset defaults: all readable registers return 0
    // ========================================================================
    $display("\n--- TC01: Reset defaults ---");
    axil_read(OFFSET_ENABLE,        4'h0, rd_data, rd_resp);
    check_resp("TC01 ENABLE rresp",        RESP_OKAY, rd_resp);
    check("TC01 ENABLE = 0",               32'h0, rd_data);

    axil_read(OFFSET_SHADOW_COUNT,  4'h0, rd_data, rd_resp);
    check_resp("TC01 SHADOW_COUNT rresp",  RESP_OKAY, rd_resp);
    check("TC01 SHADOW_COUNT = 0",         32'h0, rd_data);

    axil_read(OFFSET_SHADOW_THRESH, 4'h0, rd_data, rd_resp);
    check_resp("TC01 SHADOW_THRESH rresp", RESP_OKAY, rd_resp);
    check("TC01 SHADOW_THRESH = 0",        32'h0, rd_data);

    axil_read(OFFSET_EVENT,         4'h0, rd_data, rd_resp);
    check_resp("TC01 EVENT rresp",         RESP_OKAY, rd_resp);
    check("TC01 EVENT reads 0",            32'h0, rd_data);

    axil_read(OFFSET_SUSPECT_ADDR,  4'h0, rd_data, rd_resp);
    check_resp("TC01 SUSPECT_ADDR rresp",  RESP_OKAY, rd_resp);
    check("TC01 SUSPECT_ADDR = 0",         32'h0, rd_data);

    axil_read(OFFSET_STATUS,        4'h0, rd_data, rd_resp);
    check_resp("TC01 STATUS rresp",        RESP_OKAY, rd_resp);
    check("TC01 STATUS = 0",               32'h0, rd_data);

    // ========================================================================
    // TC02 — ecc_mon_enable write / read-back
    // ========================================================================
    $display("\n--- TC02: ecc_mon_enable write/read-back ---");
    axil_write(OFFSET_ENABLE, 32'h0000_0001, 4'hF, 4'h1, wr_resp);
    check_resp("TC02 WR bresp",        RESP_OKAY, wr_resp);
    axil_read(OFFSET_ENABLE,  4'h1, rd_data, rd_resp);
    check_resp("TC02 RD rresp",        RESP_OKAY, rd_resp);
    check("TC02 ENABLE = 1",           32'h0000_0001, rd_data & 32'h0000_0001);

    // Write 0 — clears enable
    axil_write(OFFSET_ENABLE, 32'h0000_0000, 4'hF, 4'h1, wr_resp);
    axil_read(OFFSET_ENABLE,  4'h1, rd_data, rd_resp);
    check("TC02 ENABLE cleared = 0",   32'h0000_0000, rd_data & 32'h0000_0001);

    // ========================================================================
    // TC03 — ecc_mon_shadow_count write / read-back (27-bit field)
    // ========================================================================
    $display("\n--- TC03: ecc_mon_shadow_count write/read-back ---");
    // Write a value that uses all 27 bits
    axil_write(OFFSET_SHADOW_COUNT, 32'h07FF_FFFF, 4'hF, 4'h2, wr_resp);
    check_resp("TC03 WR bresp",        RESP_OKAY, wr_resp);
    axil_read(OFFSET_SHADOW_COUNT, 4'h2, rd_data, rd_resp);
    check_resp("TC03 RD rresp",        RESP_OKAY, rd_resp);
    check("TC03 SHADOW_COUNT max",     32'h07FF_FFFF, rd_data & 32'h07FF_FFFF);

    // Write a smaller value to confirm it replaces cleanly
    axil_write(OFFSET_SHADOW_COUNT, 32'h0000_1234, 4'hF, 4'h2, wr_resp);
    axil_read(OFFSET_SHADOW_COUNT, 4'h2, rd_data, rd_resp);
    check("TC03 SHADOW_COUNT 0x1234",  32'h0000_1234, rd_data & 32'h07FF_FFFF);

    // ========================================================================
    // TC04 — ecc_mon_shadow_thresh write / read-back (5-bit field)
    // ========================================================================
    $display("\n--- TC04: ecc_mon_shadow_thresh write/read-back ---");
    axil_write(OFFSET_SHADOW_THRESH, 32'h0000_001F, 4'hF, 4'h3, wr_resp);
    check_resp("TC04 WR bresp",        RESP_OKAY, wr_resp);
    axil_read(OFFSET_SHADOW_THRESH, 4'h3, rd_data, rd_resp);
    check_resp("TC04 RD rresp",        RESP_OKAY, rd_resp);
    check("TC04 SHADOW_THRESH max",    32'h0000_001F, rd_data & 32'h0000_001F);

    axil_write(OFFSET_SHADOW_THRESH, 32'h0000_000A, 4'hF, 4'h3, wr_resp);
    axil_read(OFFSET_SHADOW_THRESH, 4'h3, rd_data, rd_resp);
    check("TC04 SHADOW_THRESH 0xA",    32'h0000_000A, rd_data & 32'h0000_001F);

    // ========================================================================
    // TC05 — ecc_mon_event always reads 0 (W1C, no stored state)
    // ========================================================================
    $display("\n--- TC05: ecc_mon_event always reads 0 ---");
    // Read before any write
    axil_read(OFFSET_EVENT, 4'h4, rd_data, rd_resp);
    check_resp("TC05 RD before rresp",  RESP_OKAY, rd_resp);
    check("TC05 EVENT before write",    32'h0, rd_data);

    // Enable must be set for the event to have any side-effect, but the
    // register should still read 0 afterward.
    axil_write(OFFSET_ENABLE, 32'h1, 4'hF, 4'h0, wr_resp);
    mbist_active = 1'b0;
    axil_write(OFFSET_EVENT, 32'h0000_0001, 4'hF, 4'h4, wr_resp);
    check_resp("TC05 WR EVENT bresp",   RESP_OKAY, wr_resp);
    axil_read(OFFSET_EVENT, 4'h4, rd_data, rd_resp);
    check_resp("TC05 RD after rresp",   RESP_OKAY, rd_resp);
    check("TC05 EVENT after write = 0", 32'h0, rd_data);
    // Clean up for next TC
    do_reset;

    // ========================================================================
    // TC06 — Disable gating: event write with enable=0 → no state change
    // ========================================================================
    $display("\n--- TC06: Disable gating on ecc_mon_event ---");
    // Reset ensures enable=0, correctable_seen=0, mbist_correlated=0
    mbist_active         = 1'b1;
    mbist_fault_addr_tap = 32'hDEAD_BEEF;

    // Write event with enable still 0 — must be OKAY but no state change
    axil_write(OFFSET_EVENT, 32'h0000_0001, 4'hF, 4'h5, wr_resp);
    check_resp("TC06 EVENT WR bresp",         RESP_OKAY, wr_resp);

    // Status must remain all-zero
    axil_read(OFFSET_STATUS, 4'h5, rd_data, rd_resp);
    check("TC06 STATUS unchanged (=0)",       32'h0000_0000, rd_data & 32'h3);

    // suspect_addr must remain 0
    axil_read(OFFSET_SUSPECT_ADDR, 4'h5, rd_data, rd_resp);
    check("TC06 SUSPECT_ADDR unchanged (=0)", 32'h0000_0000, rd_data);

    mbist_active = 1'b0;

    // ========================================================================
    // TC07 — Correlation capture when mbist_active=1 at time of event write
    //   Expected: correctable_seen=1, mbist_correlated=1,
    //             suspect_addr = mbist_fault_addr_tap
    // ========================================================================
    $display("\n--- TC07: Correlation with mbist_active=1 ---");
    do_reset;

    // Enable monitor
    axil_write(OFFSET_ENABLE, 32'h0000_0001, 4'hF, 4'h0, wr_resp);

    // Drive MBIST sideband
    mbist_active         = 1'b1;
    mbist_fault_addr_tap = 32'hCAFE_1234;
    @(posedge axi_aclk); // one cycle settle

    // Write event — should trigger full correlation
    axil_write(OFFSET_EVENT, 32'h0000_0001, 4'hF, 4'h6, wr_resp);
    check_resp("TC07 EVENT WR bresp",    RESP_OKAY, wr_resp);

    // Check status: both bits set
    axil_read(OFFSET_STATUS, 4'h6, rd_data, rd_resp);
    check_resp("TC07 STATUS rresp",      RESP_OKAY, rd_resp);
    check("TC07 correctable_seen",       32'h1, rd_data[STATUS_CORR_SEEN]);
    check("TC07 mbist_correlated",       32'h1, rd_data[STATUS_MBIST_CORR]);

    // Check suspect addr latched correctly
    axil_read(OFFSET_SUSPECT_ADDR, 4'h6, rd_data, rd_resp);
    check_resp("TC07 SUSPECT_ADDR rresp",RESP_OKAY, rd_resp);
    check("TC07 suspect_addr latched",   32'hCAFE_1234, rd_data);

    // ========================================================================
    // TC08 — No correlation capture when mbist_active=0 at event write
    //   Expected: correctable_seen=1, mbist_correlated=0,
    //             suspect_addr still = TC07 value (unchanged)
    // ========================================================================
    $display("\n--- TC08: No correlation when mbist_active=0 ---");
    // Reset to clear TC07 state, then re-enable
    do_reset;
    axil_write(OFFSET_ENABLE, 32'h0000_0001, 4'hF, 4'h0, wr_resp);

    mbist_active         = 1'b0;    // MBIST not running
    mbist_fault_addr_tap = 32'hBAAD_CAFE;

    axil_write(OFFSET_EVENT, 32'h0000_0001, 4'hF, 4'h7, wr_resp);
    check_resp("TC08 EVENT WR bresp",    RESP_OKAY, wr_resp);

    axil_read(OFFSET_STATUS, 4'h7, rd_data, rd_resp);
    check("TC08 correctable_seen=1",     32'h1, rd_data[STATUS_CORR_SEEN]);
    check("TC08 mbist_correlated=0",     32'h0, rd_data[STATUS_MBIST_CORR]);

    // suspect_addr must remain reset value (0) since no correlation occurred
    axil_read(OFFSET_SUSPECT_ADDR, 4'h7, rd_data, rd_resp);
    check("TC08 suspect_addr unchanged", 32'h0000_0000, rd_data);

    // ========================================================================
    // TC09 — W1C clearing: ecc_mon_event reads 0 before and after write
    //   (redundant with TC05 but important to confirm after state changes)
    // ========================================================================
    $display("\n--- TC09: W1C — ecc_mon_event reads 0 before and after ---");
    // State from TC08 still active (correctable_seen=1, mbist_correlated=0)
    axil_read(OFFSET_EVENT, 4'h8, rd_data, rd_resp);
    check("TC09 EVENT reads 0 before",  32'h0, rd_data);

    // Write 1 (trigger) — event fires, flag updates
    axil_write(OFFSET_EVENT, 32'h0000_0001, 4'hF, 4'h8, wr_resp);
    check_resp("TC09 EVENT WR bresp",   RESP_OKAY, wr_resp);

    // Read back — must still be 0
    axil_read(OFFSET_EVENT, 4'h8, rd_data, rd_resp);
    check("TC09 EVENT reads 0 after",   32'h0, rd_data);

    // ========================================================================
    // TC10 — Disabling ecc_mon_enable mid-operation does not corrupt already-
    //         latched state (correctable_seen and suspect_addr from TC07/08)
    // ========================================================================
    $display("\n--- TC10: Already-latched state preserved after enable cleared ---");
    // Snapshot current status (from TC08/09 chain: correctable_seen=1, mbist_correlated=0)
    axil_read(OFFSET_STATUS,       4'h9, rd_data, rd_resp);
    $display("[INFO] TC10 status before disable: 0x%02h", rd_data[1:0]);

    // Disable the monitor
    axil_write(OFFSET_ENABLE, 32'h0000_0000, 4'hF, 4'h9, wr_resp);
    check_resp("TC10 disable WR bresp",      RESP_OKAY, wr_resp);

    // Try to fire another event — must not change state
    mbist_active         = 1'b1;
    mbist_fault_addr_tap = 32'hFFFF_AAAA;
    axil_write(OFFSET_EVENT, 32'h0000_0001, 4'hF, 4'h9, wr_resp);

    // Status must be unchanged from snapshot (correctable_seen=1, mbist_corr=0)
    axil_read(OFFSET_STATUS, 4'h9, rd_data, rd_resp);
    check("TC10 correctable_seen preserved", 32'h1, rd_data[STATUS_CORR_SEEN]);
    check("TC10 mbist_correlated preserved", 32'h0, rd_data[STATUS_MBIST_CORR]);

    // suspect_addr must still be reset value (0) from TC08
    axil_read(OFFSET_SUSPECT_ADDR, 4'h9, rd_data, rd_resp);
    check("TC10 suspect_addr preserved",     32'h0000_0000, rd_data);

    mbist_active = 1'b0;

    // ========================================================================
    // TC11 — SLVERR on write to RO register ecc_mon_suspect_addr (0x10)
    // ========================================================================
    $display("\n--- TC11: SLVERR write to RO suspect_addr ---");
    axil_write(OFFSET_SUSPECT_ADDR, 32'hDEAD_DEAD, 4'hF, 4'hA, wr_resp);
    check_resp("TC11 WR 0x10 bresp", RESP_SLVERR, wr_resp);
    // Confirm the register was not modified
    axil_read(OFFSET_SUSPECT_ADDR,  4'hA, rd_data, rd_resp);
    check("TC11 suspect_addr not written", 32'h0000_0000, rd_data);

    // ========================================================================
    // TC12 — SLVERR on write to RO register ecc_mon_status (0x14)
    // ========================================================================
    $display("\n--- TC12: SLVERR write to RO status ---");
    axil_write(OFFSET_STATUS, 32'h0000_0003, 4'hF, 4'hA, wr_resp);
    check_resp("TC12 WR 0x14 bresp", RESP_SLVERR, wr_resp);

    // ========================================================================
    // TC13 — SLVERR on read/write to undefined offset 0x18
    // ========================================================================
    $display("\n--- TC13: SLVERR on undefined offset 0x18 ---");
    axil_read(OFFSET_UNDEF_18,  4'hB, rd_data, rd_resp);
    check_resp("TC13 RD 0x18 rresp", RESP_SLVERR, rd_resp);
    check("TC13 RD 0x18 data = 0",   32'h0, rd_data);

    axil_write(OFFSET_UNDEF_18, 32'hCAFE_BABE, 4'hF, 4'hB, wr_resp);
    check_resp("TC13 WR 0x18 bresp", RESP_SLVERR, wr_resp);

    // ========================================================================
    // TC14 — SLVERR on read/write at top of 4 KB window (0xFFC)
    // ========================================================================
    $display("\n--- TC14: SLVERR at top of 4 KB window (0xFFC) ---");
    axil_read(OFFSET_UNDEF_FFC,  4'hC, rd_data, rd_resp);
    check_resp("TC14 RD 0xFFC rresp", RESP_SLVERR, rd_resp);
    check("TC14 RD 0xFFC data = 0",   32'h0, rd_data);

    axil_write(OFFSET_UNDEF_FFC, 32'hFFFF_FFFF, 4'hF, 4'hC, wr_resp);
    check_resp("TC14 WR 0xFFC bresp", RESP_SLVERR, wr_resp);

    // ========================================================================
    // TC15 — Sequential events: two back-to-back event writes with different
    //         mbist_fault_addr_tap values; second must overwrite first
    // ========================================================================
    $display("\n--- TC15: Sequential events — second overwrites first ---");
    do_reset;
    axil_write(OFFSET_ENABLE, 32'h0000_0001, 4'hF, 4'h0, wr_resp);

    // First event: mbist_active=1, addr_tap = 0xAAAA_0001
    mbist_active         = 1'b1;
    mbist_fault_addr_tap = 32'hAAAA_0001;
    @(posedge axi_aclk);
    axil_write(OFFSET_EVENT, 32'h0000_0001, 4'hF, 4'hD, wr_resp);
    check_resp("TC15 first EVENT bresp",      RESP_OKAY, wr_resp);
    axil_read(OFFSET_SUSPECT_ADDR, 4'hD, rd_data, rd_resp);
    check("TC15 first suspect_addr",          32'hAAAA_0001, rd_data);

    // Second event: different addr_tap
    mbist_fault_addr_tap = 32'h5555_0002;
    @(posedge axi_aclk);
    axil_write(OFFSET_EVENT, 32'h0000_0001, 4'hF, 4'hE, wr_resp);
    check_resp("TC15 second EVENT bresp",     RESP_OKAY, wr_resp);
    axil_read(OFFSET_SUSPECT_ADDR, 4'hE, rd_data, rd_resp);
    check("TC15 second suspect_addr",         32'h5555_0002, rd_data);

    // Both correctable_seen and mbist_correlated must still be set
    axil_read(OFFSET_STATUS, 4'hE, rd_data, rd_resp);
    check("TC15 correctable_seen",            32'h1, rd_data[STATUS_CORR_SEEN]);
    check("TC15 mbist_correlated",            32'h1, rd_data[STATUS_MBIST_CORR]);

    mbist_active = 1'b0;

    // ========================================================================
    // Summary
    // ========================================================================
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
  // Simulation timeout watchdog (prevent infinite hang on protocol error)
  // --------------------------------------------------------------------------
  initial begin
    #(500_000);
    $display("[ERROR] Simulation global timeout — hung transaction?");
    $finish;
  end

  // --------------------------------------------------------------------------
  // Waveform dump
  // --------------------------------------------------------------------------
  initial begin
    $dumpfile("tb_axil_ecc_monitor_top.vcd");
    $dumpvars(0, tb_axil_ecc_monitor_top);
  end

endmodule
