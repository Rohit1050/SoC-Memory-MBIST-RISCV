/* -----------------------------------------------------------------------------
 * File           : axil_bfm_master.v
 * Description    : Shared AXI4-Lite Bus Functional Model (BFM) — master side.
 *
 *   Provides Verilog tasks for single-beat AXI4-Lite write and read
 *   transactions.  Intended for inclusion in unit-level testbenches.
 *
 *   Parameters
 *     ADDR_WIDTH   — address bus width (default 32)
 *     DATA_WIDTH   — data bus width   (default 32)
 *     ID_WIDTH     — ID field width   (default 4)
 *     RESP_TIMEOUT — max cycles to wait for a response before error (default 256)
 *
 *   Usage
 *     `include "axil_bfm_master.v"`   (in the testbench module)
 *     Then call:
 *       axil_write(addr, data, strb, id, bresp)
 *       axil_read (addr, id, rdata, rresp)
 *
 *   All tasks are blocking.  The calling testbench must drive the clock and
 *   set posedge-aligned inputs before invoking a task.
 *
 * Revision History
 *  Rev | Description
 *  1.0 | Initial version for axil_uart_top testbench.
 * -----------------------------------------------------------------------------*/

// ============================================================================
// axil_write — single AXI4-Lite write transaction
//
//   Drives AW + W simultaneously (spec allows both channels valid at once),
//   then waits for B response.
//
//   Inputs  : addr, data, strb, id
//   Outputs : bresp (returned via output argument)
// ============================================================================
task axil_write;
  input  [ADDR_WIDTH-1:0]   addr;
  input  [DATA_WIDTH-1:0]   data;
  input  [DATA_WIDTH/8-1:0] strb;
  input  [ID_WIDTH-1:0]     id;
  output [1:0]              bresp;

  integer timeout_cnt;
  begin
    // ---- Phase 1: present AW and W channels --------------------------------
    @(negedge axi_aclk);
    axil_awaddr  = addr;
    axil_awid    = id;
    axil_awvalid = 1'b1;
    axil_wdata   = data;
    axil_wstrb   = strb;
    axil_wvalid  = 1'b1;
    axil_bready  = 1'b1;

    // Wait for AWREADY
    timeout_cnt = 0;
    @(posedge axi_aclk);
    while (!axil_awready) begin
      @(posedge axi_aclk);
      timeout_cnt = timeout_cnt + 1;
      if (timeout_cnt >= RESP_TIMEOUT) begin
        $display("[BFM] ERROR: AWREADY timeout at addr=0x%08h", addr);
        $finish;
      end
    end

    // Wait for WREADY (may have already come with AWREADY)
    timeout_cnt = 0;
    while (!axil_wready) begin
      @(posedge axi_aclk);
      timeout_cnt = timeout_cnt + 1;
      if (timeout_cnt >= RESP_TIMEOUT) begin
        $display("[BFM] ERROR: WREADY timeout at addr=0x%08h", addr);
        $finish;
      end
    end

    // De-assert after handshake
    @(negedge axi_aclk);
    axil_awvalid = 1'b0;
    axil_wvalid  = 1'b0;

    // ---- Phase 2: wait for B response --------------------------------------
    timeout_cnt = 0;
    @(posedge axi_aclk);
    while (!axil_bvalid) begin
      @(posedge axi_aclk);
      timeout_cnt = timeout_cnt + 1;
      if (timeout_cnt >= RESP_TIMEOUT) begin
        $display("[BFM] ERROR: BVALID timeout at addr=0x%08h", addr);
        $finish;
      end
    end
    bresp = axil_bresp;

    @(negedge axi_aclk);
    axil_bready = 1'b0;
  end
endtask

// ============================================================================
// axil_read — single AXI4-Lite read transaction
//
//   Drives AR channel, then waits for R response.
//
//   Inputs  : addr, id
//   Outputs : rdata, rresp (returned via output arguments)
// ============================================================================
task axil_read;
  input  [ADDR_WIDTH-1:0] addr;
  input  [ID_WIDTH-1:0]   id;
  output [DATA_WIDTH-1:0] rdata;
  output [1:0]            rresp;

  integer timeout_cnt;
  begin
    // ---- Phase 1: present AR channel ---------------------------------------
    @(negedge axi_aclk);
    axil_araddr  = addr;
    axil_arid    = id;
    axil_arvalid = 1'b1;
    axil_rready  = 1'b1;

    timeout_cnt = 0;
    @(posedge axi_aclk);
    while (!axil_arready) begin
      @(posedge axi_aclk);
      timeout_cnt = timeout_cnt + 1;
      if (timeout_cnt >= RESP_TIMEOUT) begin
        $display("[BFM] ERROR: ARREADY timeout at addr=0x%08h", addr);
        $finish;
      end
    end

    @(negedge axi_aclk);
    axil_arvalid = 1'b0;

    // ---- Phase 2: wait for R data ------------------------------------------
    timeout_cnt = 0;
    @(posedge axi_aclk);
    while (!axil_rvalid) begin
      @(posedge axi_aclk);
      timeout_cnt = timeout_cnt + 1;
      if (timeout_cnt >= RESP_TIMEOUT) begin
        $display("[BFM] ERROR: RVALID timeout at addr=0x%08h", addr);
        $finish;
      end
    end
    rdata = axil_rdata;
    rresp = axil_rresp;

    @(negedge axi_aclk);
    axil_rready = 1'b0;
  end
endtask
