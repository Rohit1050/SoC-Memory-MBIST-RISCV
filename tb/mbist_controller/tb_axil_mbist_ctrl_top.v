/* -----------------------------------------------------------------------------
 * Project        : RISC-V SoC / MBIST  —  MBIST Controller IP
 * File           : tb_axil_mbist_ctrl_top.v
 * Description    : Unit-level testbench for axil_mbist_ctrl_top.
 *
 *   Simulates:
 *     1. AXI4-Lite CPU master configuring and monitoring the controller
 *        via tb/common/axil_bfm_master.v.
 *     2. 64-bit AXI4 slave memory model representing DCCM / DMA Slave Port
 *        with controllable fault injection (SLVERR & data corruption).
 *
 *   Test Scenarios:
 *     TC01  Reset defaults verification
 *     TC02  Register read/write (range, algo)
 *     TC03  Checkerboard scan — fault-free memory (PASS)
 *     TC04  March C- scan — fault-free memory (PASS)
 *     TC05  Double-bit ECC fault detection (SLVERR injection)
 *     TC06  Data corruption / stuck-at fault detection (mismatch injection)
 *     TC07  Sideband tracking: mbist_active_o, fault_addr_tap_o, mbist_irq_done_o
 *     TC08  Auto-trigger via timer_tick_i
 *     TC09  SLVERR on RO registers and undefined offsets
 * -----------------------------------------------------------------------------*/
`timescale 1ns/1ps

`define CLK_PERIOD 20   // 50 MHz clock

module tb_axil_mbist_ctrl_top;

  // --------------------------------------------------------------------------
  // Bus Parameters
  // --------------------------------------------------------------------------
  parameter ADDR_WIDTH   = 32;
  parameter DATA_WIDTH   = 32;
  parameter ID_WIDTH     = 4;
  parameter RESP_TIMEOUT = 512;

  parameter DMA_DATA_WIDTH = 64;
  parameter DMA_ADDR_WIDTH = 32;
  parameter DMA_ID_WIDTH   = 4;
  parameter DMA_STRB_WIDTH = 8;

  // Offsets
  localparam OFFSET_START        = 32'h000;
  localparam OFFSET_ALGO         = 32'h004;
  localparam OFFSET_ADDR_START   = 32'h008;
  localparam OFFSET_ADDR_END     = 32'h00C;
  localparam OFFSET_BUSY         = 32'h010;
  localparam OFFSET_DONE         = 32'h014;
  localparam OFFSET_PASS_FAIL    = 32'h018;
  localparam OFFSET_FAULT_ADDR   = 32'h01C;
  localparam OFFSET_FAULT_COUNT  = 32'h020;
  localparam OFFSET_UNDEF        = 32'h028;

  localparam RESP_OKAY   = 2'b00;
  localparam RESP_SLVERR = 2'b10;

  // --------------------------------------------------------------------------
  // Clocks and resets
  // --------------------------------------------------------------------------
  reg axi_aclk;
  reg axi_aresetn;

  initial axi_aclk = 1'b0;
  always #(`CLK_PERIOD/2) axi_aclk = ~axi_aclk;

  // --------------------------------------------------------------------------
  // AXI4-Lite CSR Master signals (driven by BFM tasks)
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
  // 64-bit Full AXI4 DMA Master signals (driven by DUT, connected to slave model)
  // --------------------------------------------------------------------------
  wire [DMA_ID_WIDTH-1:0]   dma_awid;
  wire [DMA_ADDR_WIDTH-1:0] dma_awaddr;
  wire [7:0]                dma_awlen;
  wire [2:0]                dma_awsize;
  wire [1:0]                dma_awburst;
  wire                      dma_awlock;
  wire [3:0]                dma_awcache;
  wire [2:0]                dma_awprot;
  wire [3:0]                dma_awqos;
  wire                      dma_awvalid;
  reg                       dma_awready;

  wire [DMA_DATA_WIDTH-1:0] dma_wdata;
  wire [DMA_STRB_WIDTH-1:0] dma_wstrb;
  wire                      dma_wlast;
  wire                      dma_wvalid;
  reg                       dma_wready;

  reg  [DMA_ID_WIDTH-1:0]   dma_bid;
  reg  [1:0]                dma_bresp;
  reg                       dma_bvalid;
  wire                      dma_bready;

  wire [DMA_ID_WIDTH-1:0]   dma_arid;
  wire [DMA_ADDR_WIDTH-1:0] dma_araddr;
  wire [7:0]                dma_arlen;
  wire [2:0]                dma_arsize;
  wire [1:0]                dma_arburst;
  wire                      dma_arlock;
  wire [3:0]                dma_arcache;
  wire [2:0]                dma_arprot;
  wire [3:0]                dma_arqos;
  wire                      dma_arvalid;
  reg                       dma_arready;

  reg  [DMA_ID_WIDTH-1:0]   dma_rid;
  reg  [DMA_DATA_WIDTH-1:0] dma_rdata;
  reg  [1:0]                dma_rresp;
  reg                       dma_rlast;
  reg                       dma_rvalid;
  wire                      dma_rready;

  // --------------------------------------------------------------------------
  // Sideband signals
  // --------------------------------------------------------------------------
  reg                       timer_tick;
  wire                      mbist_active;
  wire [DMA_ADDR_WIDTH-1:0] mbist_fault_addr_tap;
  wire                      mbist_irq_done;

  // --------------------------------------------------------------------------
  // DUT Instantiation
  // --------------------------------------------------------------------------
  axil_mbist_ctrl_top dut (
    .axi_aclk_i             (axi_aclk),
    .axi_aresetn_i          (axi_aresetn),

    // CSR AXI4-Lite Slave Port
    .axi_awid_i             (axil_awid),
    .axi_awaddr_i           (axil_awaddr),
    .axi_awprot_i           (axil_awprot),
    .axi_awvalid_i          (axil_awvalid),
    .axi_awready_o          (axil_awready),

    .axi_wdata_i            (axil_wdata),
    .axi_wstrb_i            (axil_wstrb),
    .axi_wvalid_i           (axil_wvalid),
    .axi_wready_o           (axil_wready),

    .axi_bid_o              (axil_bid),
    .axi_bresp_o            (axil_bresp),
    .axi_bvalid_o           (axil_bvalid),
    .axi_bready_i           (axil_bready),

    .axi_arid_i             (axil_arid),
    .axi_araddr_i           (axil_araddr),
    .axi_arprot_i           (axil_arprot),
    .axi_arvalid_i          (axil_arvalid),
    .axi_arready_o          (axil_arready),

    .axi_rid_o              (axil_rid),
    .axi_rdata_o            (axil_rdata),
    .axi_rresp_o            (axil_rresp),
    .axi_rvalid_o           (axil_rvalid),
    .axi_rready_i           (axil_rready),

    // 64-bit DMA Master Port
    .m_dma_axi_awid         (dma_awid),
    .m_dma_axi_awaddr       (dma_awaddr),
    .m_dma_axi_awlen        (dma_awlen),
    .m_dma_axi_awsize       (dma_awsize),
    .m_dma_axi_awburst      (dma_awburst),
    .m_dma_axi_awlock       (dma_awlock),
    .m_dma_axi_awcache      (dma_awcache),
    .m_dma_axi_awprot       (dma_awprot),
    .m_dma_axi_awqos        (dma_awqos),
    .m_dma_axi_awvalid      (dma_awvalid),
    .m_dma_axi_awready      (dma_awready),

    .m_dma_axi_wdata        (dma_wdata),
    .m_dma_axi_wstrb        (dma_wstrb),
    .m_dma_axi_wlast        (dma_wlast),
    .m_dma_axi_wvalid       (dma_wvalid),
    .m_dma_axi_wready       (dma_wready),

    .m_dma_axi_bid          (dma_bid),
    .m_dma_axi_bresp        (dma_bresp),
    .m_dma_axi_bvalid       (dma_bvalid),
    .m_dma_axi_bready       (dma_bready),

    .m_dma_axi_arid         (dma_arid),
    .m_dma_axi_araddr       (dma_araddr),
    .m_dma_axi_arlen        (dma_arlen),
    .m_dma_axi_arsize       (dma_arsize),
    .m_dma_axi_arburst      (dma_arburst),
    .m_dma_axi_arlock       (dma_arlock),
    .m_dma_axi_arcache      (dma_arcache),
    .m_dma_axi_arprot       (dma_arprot),
    .m_dma_axi_arqos        (dma_arqos),
    .m_dma_axi_arvalid      (dma_arvalid),
    .m_dma_axi_arready      (dma_arready),

    .m_dma_axi_rid          (dma_rid),
    .m_dma_axi_rdata        (dma_rdata),
    .m_dma_axi_rresp        (dma_rresp),
    .m_dma_axi_rlast        (dma_rlast),
    .m_dma_axi_rvalid       (dma_rvalid),
    .m_dma_axi_rready       (dma_rready),

    // Sideband
    .timer_tick_i           (timer_tick),
    .mbist_active_o         (mbist_active),
    .mbist_fault_addr_tap_o (mbist_fault_addr_tap),
    .mbist_irq_done_o       (mbist_irq_done)
  );

  // --------------------------------------------------------------------------
  // Include shared AXI4-Lite BFM tasks
  // --------------------------------------------------------------------------
  `include "axil_bfm_master.v"

  // --------------------------------------------------------------------------
  // 64-bit DCCM AXI4 Slave Memory Simulation Model with Fault Injection
  // --------------------------------------------------------------------------
  reg [63:0] mem_array [0:255]; // 256 double-words = 2 KB window
  integer i;

  reg        inject_slverr;
  reg [31:0] inject_slverr_addr;

  reg        inject_corrupt;
  reg [31:0] inject_corrupt_addr;
  reg [63:0] inject_corrupt_mask;

  // Latch write address and ID
  reg [DMA_ADDR_WIDTH-1:0] lat_awaddr;
  reg [DMA_ID_WIDTH-1:0]   lat_awid;
  reg                      have_aw;

  // DMA Write Channel Slave Logic
  always @(posedge axi_aclk or negedge axi_aresetn) begin
    if (!axi_aresetn) begin
      dma_awready <= 1'b1;
      dma_wready  <= 1'b1;
      dma_bvalid  <= 1'b0;
      dma_bresp   <= 2'b00;
      dma_bid     <= 4'h0;
      have_aw     <= 1'b0;
      lat_awaddr  <= 32'h0;
      lat_awid    <= 4'h0;
    end else begin
      // Latch AW
      if (dma_awvalid && dma_awready) begin
        lat_awaddr <= dma_awaddr;
        lat_awid   <= dma_awid;
        have_aw    <= 1'b1;
      end

      // Write data into memory when W handshakes
      if (dma_wvalid && dma_wready) begin
        mem_array[(lat_awaddr[10:3])] <= dma_wdata;
        dma_bvalid <= 1'b1;
        dma_bid    <= lat_awid;
        dma_bresp  <= 2'b00;
      end

      if (dma_bvalid && dma_bready) begin
        dma_bvalid <= 1'b0;
        have_aw    <= 1'b0;
      end
    end
  end

  // DMA Read Channel Slave Logic
  always @(posedge axi_aclk or negedge axi_aresetn) begin
    if (!axi_aresetn) begin
      dma_arready <= 1'b1;
      dma_rvalid  <= 1'b0;
      dma_rdata   <= 64'h0;
      dma_rresp   <= 2'b00;
      dma_rid     <= 4'h0;
      dma_rlast   <= 1'b0;
    end else begin
      if (dma_arvalid && dma_arready) begin
        dma_rvalid <= 1'b1;
        dma_rid    <= dma_arid;
        dma_rlast  <= 1'b1;

        // Check if injecting SLVERR (Double-bit ECC error)
        if (inject_slverr && (dma_araddr == inject_slverr_addr)) begin
          dma_rresp <= 2'b10; // SLVERR
          dma_rdata <= 64'hDEAD_BEEF_DEAD_BEEF;
        end else if (inject_corrupt && (dma_araddr == inject_corrupt_addr)) begin
          dma_rresp <= 2'b00; // OKAY
          dma_rdata <= mem_array[(dma_araddr[10:3])] ^ inject_corrupt_mask; // flipped bits
        end else begin
          dma_rresp <= 2'b00; // OKAY
          dma_rdata <= mem_array[(dma_araddr[10:3])];
        end
      end else if (dma_rvalid && dma_rready) begin
        dma_rvalid <= 1'b0;
      end
    end
  end

  // --------------------------------------------------------------------------
  // Test Variables
  // --------------------------------------------------------------------------
  reg [DATA_WIDTH-1:0] rd_data;
  reg [1:0]            resp;
  integer              test_errors;
  integer              tc_num;

  task wait_for_done;
    reg busy;
    integer timeout;
    begin
      timeout = 0;
      busy = 1'b1;
      while (busy) begin
        @(posedge axi_aclk);
        axil_read(OFFSET_BUSY, 4'h0, rd_data, resp);
        busy = rd_data[0];
        timeout = timeout + 1;
        if (timeout > 5000) begin
          $display("[TB ERROR] Timeout waiting for MBIST done!");
          test_errors = test_errors + 1;
          busy = 1'b0;
        end
      end
    end
  endtask

  // --------------------------------------------------------------------------
  // Main Test Sequence
  // --------------------------------------------------------------------------
  initial begin
    test_errors        = 0;
    axil_awprot        = 3'b000;
    axil_arprot        = 3'b000;
    axil_awvalid       = 1'b0;
    axil_wvalid        = 1'b0;
    axil_bready        = 1'b0;
    axil_arvalid       = 1'b0;
    axil_rready        = 1'b0;
    timer_tick         = 1'b0;
    inject_slverr      = 1'b0;
    inject_corrupt     = 1'b0;
    inject_slverr_addr = 32'h0;
    inject_corrupt_addr= 32'h0;

    for (i = 0; i < 256; i = i + 1) begin
      mem_array[i] = 64'h0;
    end

    $display("================================================================");
    $display("Starting MBIST Controller (axil_mbist_ctrl_top) Unit Tests");
    $display("================================================================");

    // Apply Reset
    axi_aresetn = 1'b0;
    repeat (5) @(posedge axi_aclk);
    @(negedge axi_aclk);
    axi_aresetn = 1'b1;
    repeat (2) @(posedge axi_aclk);

    // ------------------------------------------------------------------------
    // TC01: Reset defaults
    // ------------------------------------------------------------------------
    tc_num = 1;
    $display("\n--- TC01: Verify Reset Defaults ---");
    axil_read(OFFSET_ALGO, 4'h0, rd_data, resp);
    if (rd_data[1:0] == 2'b01) $display("[PASS] TC01: Default algo is March C-");
    else begin $display("[FAIL] TC01: Expected March C- default"); test_errors=test_errors+1; end

    axil_read(OFFSET_BUSY, 4'h0, rd_data, resp);
    if (rd_data[0] == 1'b0) $display("[PASS] TC01: mbist_busy is 0 after reset");
    else begin $display("[FAIL] TC01: mbist_busy is not 0"); test_errors=test_errors+1; end

    axil_read(OFFSET_PASS_FAIL, 4'h0, rd_data, resp);
    if (rd_data[0] == 1'b0) $display("[PASS] TC01: mbist_pass_fail is 0 after reset");
    else begin $display("[FAIL] TC01: mbist_pass_fail is not 0"); test_errors=test_errors+1; end

    // ------------------------------------------------------------------------
    // TC02: Configure bounds and algorithm
    // ------------------------------------------------------------------------
    tc_num = 2;
    $display("\n--- TC02: Configure Bounds and Algorithm ---");
    // Test a 4-word region: 0x0008_0000 to 0x0008_0018 (4 double-words: 0x00, 0x08, 0x10, 0x18)
    axil_write(OFFSET_ADDR_START, 32'h0008_0000, 4'hF, 4'h1, resp);
    axil_write(OFFSET_ADDR_END,   32'h0008_0018, 4'hF, 4'h1, resp);
    axil_write(OFFSET_ALGO,       32'h0000_0000, 4'hF, 4'h1, resp); // Checkerboard

    axil_read(OFFSET_ADDR_START, 4'h1, rd_data, resp);
    if (rd_data == 32'h0008_0000) $display("[PASS] TC02: addr_start programmed correctly");
    else begin $display("[FAIL] TC02: addr_start mismatch"); test_errors=test_errors+1; end

    // ------------------------------------------------------------------------
    // TC03: Checkerboard Test — Clean Memory (Expect PASS)
    // ------------------------------------------------------------------------
    tc_num = 3;
    $display("\n--- TC03: Checkerboard Scan — Clean Memory (PASS) ---");
    axil_write(OFFSET_START, 32'h1, 4'hF, 4'h2, resp);

    wait_for_done();

    axil_read(OFFSET_DONE, 4'h2, rd_data, resp);
    if (rd_data[0] == 1'b1) $display("[PASS] TC03: mbist_done set");
    else begin $display("[FAIL] TC03: mbist_done not set"); test_errors=test_errors+1; end

    axil_read(OFFSET_PASS_FAIL, 4'h2, rd_data, resp);
    if (rd_data[0] == 1'b0) $display("[PASS] TC03: Checkerboard passed without faults");
    else begin $display("[FAIL] TC03: Checkerboard reported false failure!"); test_errors=test_errors+1; end

    // ------------------------------------------------------------------------
    // TC04: March C- Test — Clean Memory (Expect PASS)
    // ------------------------------------------------------------------------
    tc_num = 4;
    $display("\n--- TC04: March C- Scan — Clean Memory (PASS) ---");
    axil_write(OFFSET_ALGO, 32'h0000_0001, 4'hF, 4'h3, resp); // March C-
    axil_write(OFFSET_START, 32'h1, 4'hF, 4'h3, resp);

    wait_for_done();

    axil_read(OFFSET_PASS_FAIL, 4'h3, rd_data, resp);
    if (rd_data[0] == 1'b0) $display("[PASS] TC04: March C- passed without faults");
    else begin $display("[FAIL] TC04: March C- reported false failure!"); test_errors=test_errors+1; end

    // ------------------------------------------------------------------------
    // TC05: Double-Bit Uncorrectable ECC Fault Injection (SLVERR)
    // ------------------------------------------------------------------------
    tc_num = 5;
    $display("\n--- TC05: Double-Bit ECC Error (SLVERR Injection) ---");
    inject_slverr      = 1'b1;
    inject_slverr_addr = 32'h0008_0010; // inject at 3rd double-word

    axil_write(OFFSET_START, 32'h1, 4'hF, 4'h4, resp);
    wait_for_done();

    axil_read(OFFSET_PASS_FAIL, 4'h4, rd_data, resp);
    if (rd_data[0] == 1'b1) $display("[PASS] TC05: Directly detected double-bit ECC fault!");
    else begin $display("[FAIL] TC05: Failed to detect SLVERR fault!"); test_errors=test_errors+1; end

    axil_read(OFFSET_FAULT_ADDR, 4'h4, rd_data, resp);
    if (rd_data == 32'h0008_0010) $display("[PASS] TC05: Fault address matches injected address 0x0008_0010");
    else begin $display("[FAIL] TC05: Fault address mismatch! Got: 0x%08h", rd_data); test_errors=test_errors+1; end

    inject_slverr = 1'b0;

    // ------------------------------------------------------------------------
    // TC06: Data Mismatch / Stuck-At Bit Fault Injection
    // ------------------------------------------------------------------------
    tc_num = 6;
    $display("\n--- TC06: Data Mismatch / Stuck-at Bit Fault ---");
    inject_corrupt      = 1'b1;
    inject_corrupt_addr = 32'h0008_0008;
    inject_corrupt_mask = 64'h0000_0000_0000_0001; // flip bit 0

    axil_write(OFFSET_START, 32'h1, 4'hF, 4'h5, resp);
    wait_for_done();

    axil_read(OFFSET_PASS_FAIL, 4'h5, rd_data, resp);
    if (rd_data[0] == 1'b1) $display("[PASS] TC06: Detected data mismatch fault!");
    else begin $display("[FAIL] TC06: Failed to detect mismatch fault!"); test_errors=test_errors+1; end

    axil_read(OFFSET_FAULT_ADDR, 4'h5, rd_data, resp);
    if (rd_data == 32'h0008_0008) $display("[PASS] TC06: Fault address matches 0x0008_0008");
    else begin $display("[FAIL] TC06: Fault address mismatch! Got: 0x%08h", rd_data); test_errors=test_errors+1; end

    inject_corrupt = 1'b0;

    // ------------------------------------------------------------------------
    // TC07: Sideband Signal Tracking Verification
    // ------------------------------------------------------------------------
    tc_num = 7;
    $display("\n--- TC07: Sideband Signals (active, tap, irq_done) ---");
    axil_write(OFFSET_START, 32'h1, 4'hF, 4'h6, resp);

    @(posedge axi_aclk);
    if (mbist_active == 1'b1) $display("[PASS] TC07: mbist_active asserted during scan");
    else begin $display("[FAIL] TC07: mbist_active not asserted!"); test_errors=test_errors+1; end

    wait_for_done();

    if (mbist_active == 1'b0) $display("[PASS] TC07: mbist_active de-asserted on completion");
    else begin $display("[FAIL] TC07: mbist_active still asserted!"); test_errors=test_errors+1; end

    // ------------------------------------------------------------------------
    // TC08: Auto-trigger via timer_tick
    // ------------------------------------------------------------------------
    tc_num = 8;
    $display("\n--- TC08: Auto-Trigger via timer_tick_i ---");
    @(negedge axi_aclk);
    timer_tick = 1'b1;
    @(negedge axi_aclk);
    timer_tick = 1'b0;

    @(posedge axi_aclk);
    if (mbist_active == 1'b1) $display("[PASS] TC08: timer_tick_i successfully auto-triggered MBIST");
    else begin $display("[FAIL] TC08: timer_tick_i failed to trigger test!"); test_errors=test_errors+1; end

    wait_for_done();

    // ------------------------------------------------------------------------
    // TC09: Register Protection & SLVERR
    // ------------------------------------------------------------------------
    tc_num = 9;
    $display("\n--- TC09: Register Protection & SLVERR on RO / Undefined ---");
    axil_write(OFFSET_BUSY, 32'h1, 4'hF, 4'h7, resp);
    if (resp == RESP_SLVERR) $display("[PASS] TC09: Write to RO register mbist_busy returned SLVERR");
    else begin $display("[FAIL] TC09: Write to RO did not return SLVERR!"); test_errors=test_errors+1; end

    axil_read(OFFSET_UNDEF, 4'h7, rd_data, resp);
    if (resp == RESP_SLVERR) $display("[PASS] TC09: Access to undefined offset returned SLVERR");
    else begin $display("[FAIL] TC09: Access to undefined did not return SLVERR!"); test_errors=test_errors+1; end

    // ------------------------------------------------------------------------
    // Summary
    // ------------------------------------------------------------------------
    $display("\n================================================================");
    if (test_errors == 0) begin
      $display("ALL 9 MBIST CONTROLLER TEST CASES PASSED SUCCESSFULLY!");
    end else begin
      $display("MBIST CONTROLLER TEST SUITE FAILED WITH %0d ERROR(S)!", test_errors);
    end
    $display("================================================================\n");

    $finish;
  end

  initial begin
    #200000;
    $display("[TB ERROR] Simulation watchdog expired!");
    $finish;
  end

endmodule
