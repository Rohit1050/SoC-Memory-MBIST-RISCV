// =============================================================================
// Project  : RISC-V SoC / MBIST — Full-SoC Testbench
// File     : tb/top/dccm_behavioral_model.v
// Module   : dccm_behavioral_model
//
// Description
//   Behavioral 16 KB DCCM (Data Closely-Coupled Memory) with testbench-side
//   fault-injection hooks for simulation.
//
// ── ECC Architecture Decision ─────────────────────────────────────────────────
//   The VeeR EL2 core performs ALL SECDED ECC encode and decode internally.
//   The el2_mem_if interface exposes raw storage banks:
//     dccm_wr_data_bank [31:0]  — data word to write (pre-encoded by the core)
//     dccm_wr_ecc_bank  [ 6:0]  — ECC check bits written alongside the data
//     dccm_bank_dout    [31:0]  — raw data word read back from storage
//     dccm_bank_ecc     [ 6:0]  — raw ECC bits read back from storage
//
//   This model is PURE STORAGE.  It does NOT perform ECC encode/decode.
//   Fault injection works by flipping stored bits in data_mem or ecc_mem.
//   When the core subsequently reads the corrupted word, its own internal
//   SECDED hardware detects the bit flip:
//     - 1-bit error  → corrected in-line, mdccmect counter incremented
//     - 2-bit error  → uncorrectable, RRESP = SLVERR on the AXI channel
//   No ECC logic is duplicated here.
//
// DCCM parameters (frozen):
//   DCCM_BASE  = 0x0008_0000
//   DCCM_SIZE  = 16 KB  (0x4000 bytes)
//   NUM_BANKS  = 4
//   BANK_WORDS = 1024  (32-bit words per bank)
//   ECC_WIDTH  = 7
//
// Fault-injection API (called from tb_soc_top tasks):
//   inject_single_bit_fault(addr, bit_pos)
//     → flips bit_pos of the data word at byte address addr
//     → on next core read, core ECC corrects it and increments mdccmect
//   inject_double_bit_fault(addr, bit_pos_1, bit_pos_2)
//     → flips two bits of the data word at byte address addr
//     → on next core read, core ECC detects uncorrectable error, SLVERR
//   inject_ecc_bit_fault(addr, ecc_bit_pos)
//     → flips one ECC check bit (causes single-bit ECC error on next read)
//   clear_fault(addr)
//     → restores the stored word to its last-written value
//
// Revision History
//   Rev | Date       | Description
//   1.0 | 2026-10-03 | Initial release.
// =============================================================================
`timescale 1ns/1ps

module dccm_behavioral_model #(
  parameter DCCM_NUM_BANKS   = 4,
  parameter DCCM_BANK_WORDS  = 1024,    // 32-bit words per bank (16 KB / 4 banks / 4 bytes)
  parameter DCCM_DATA_WIDTH  = 32,
  parameter DCCM_ECC_WIDTH   = 7,
  parameter DCCM_ADDR_BITS   = 15,      // address bits used by the core (15-bit = 32 KB space)
  parameter BANK_BITS        = 2,       // log2(NUM_BANKS)
  parameter BANK_ADDR_SHIFT  = 4        // addr[BANK_ADDR_SHIFT-1:2] = bank select; [14:BANK_ADDR_SHIFT] = word index
)(
  input  wire                                                      clk,

  // ── Bank interface from el2_mem_if ─────────────────────────────────────────
  input  wire [DCCM_NUM_BANKS-1:0]                                dccm_clken,
  input  wire [DCCM_NUM_BANKS-1:0]                                dccm_wren_bank,
  input  wire [DCCM_NUM_BANKS-1:0][DCCM_ADDR_BITS-1:(BANK_BITS+2)] dccm_addr_bank,
  input  wire [DCCM_NUM_BANKS-1:0][DCCM_DATA_WIDTH-1:0]          dccm_wr_data_bank,
  input  wire [DCCM_NUM_BANKS-1:0][DCCM_ECC_WIDTH-1:0]           dccm_wr_ecc_bank,

  output reg  [DCCM_NUM_BANKS-1:0][DCCM_DATA_WIDTH-1:0]          dccm_bank_dout,
  output reg  [DCCM_NUM_BANKS-1:0][DCCM_ECC_WIDTH-1:0]           dccm_bank_ecc
);

  // ── Storage arrays ─────────────────────────────────────────────────────────
  // data_mem and ecc_mem hold the raw bits as stored.
  // fault_data_mask and fault_ecc_mask hold XOR masks applied on read-out
  // so that a single assignment in the inject task takes effect immediately
  // without modifying what is persistently "in the cell".
  //
  // This approach means inject_fault() takes effect on the NEXT read cycle
  // (the mask is applied in the read path), matching real memory behaviour.

  reg [DCCM_DATA_WIDTH-1:0] data_mem      [0:DCCM_NUM_BANKS-1][0:DCCM_BANK_WORDS-1];
  reg [DCCM_ECC_WIDTH-1:0]  ecc_mem       [0:DCCM_NUM_BANKS-1][0:DCCM_BANK_WORDS-1];
  reg [DCCM_DATA_WIDTH-1:0] fault_data_mask [0:DCCM_NUM_BANKS-1][0:DCCM_BANK_WORDS-1];
  reg [DCCM_ECC_WIDTH-1:0]  fault_ecc_mask  [0:DCCM_NUM_BANKS-1][0:DCCM_BANK_WORDS-1];

  integer b, w;

  initial begin : zero_init
    for (b = 0; b < DCCM_NUM_BANKS; b = b + 1) begin
      for (w = 0; w < DCCM_BANK_WORDS; w = w + 1) begin
        data_mem[b][w]       = {DCCM_DATA_WIDTH{1'b0}};
        ecc_mem [b][w]       = {DCCM_ECC_WIDTH{1'b0}};
        fault_data_mask[b][w] = {DCCM_DATA_WIDTH{1'b0}};
        fault_ecc_mask [b][w] = {DCCM_ECC_WIDTH{1'b0}};
      end
    end
  end

  // ── Bank read / write ──────────────────────────────────────────────────────
  genvar gi;
  generate
    for (gi = 0; gi < DCCM_NUM_BANKS; gi = gi + 1) begin : bank_logic

      // Write port — clears any fault mask on write so a fresh write heals the cell
      always @(posedge clk) begin
        if (dccm_clken[gi] && dccm_wren_bank[gi]) begin
          data_mem[gi][dccm_addr_bank[gi][DCCM_ADDR_BITS-1:(BANK_BITS+2)]] <= dccm_wr_data_bank[gi];
          ecc_mem [gi][dccm_addr_bank[gi][DCCM_ADDR_BITS-1:(BANK_BITS+2)]] <= dccm_wr_ecc_bank[gi];
          // Writing to a cell clears any injected fault mask (cell is "repaired")
          fault_data_mask[gi][dccm_addr_bank[gi][DCCM_ADDR_BITS-1:(BANK_BITS+2)]] <= {DCCM_DATA_WIDTH{1'b0}};
          fault_ecc_mask [gi][dccm_addr_bank[gi][DCCM_ADDR_BITS-1:(BANK_BITS+2)]] <= {DCCM_ECC_WIDTH{1'b0}};
        end
      end

      // Read port — applies XOR fault mask so the core sees corrupted bits
      always @(posedge clk) begin
        if (dccm_clken[gi] && !dccm_wren_bank[gi]) begin
          dccm_bank_dout[gi] <= data_mem[gi][dccm_addr_bank[gi][DCCM_ADDR_BITS-1:(BANK_BITS+2)]]
                                ^ fault_data_mask[gi][dccm_addr_bank[gi][DCCM_ADDR_BITS-1:(BANK_BITS+2)]];
          dccm_bank_ecc[gi]  <= ecc_mem [gi][dccm_addr_bank[gi][DCCM_ADDR_BITS-1:(BANK_BITS+2)]]
                                ^ fault_ecc_mask [gi][dccm_addr_bank[gi][DCCM_ADDR_BITS-1:(BANK_BITS+2)]];
        end
      end

    end
  endgenerate

  // ==========================================================================
  // ── Fault-injection tasks ───────────────────────────────────────────────────
  //
  // Address convention: byte address within DCCM space.
  //   bank    = addr[BANK_ADDR_SHIFT-1:2]  (using BANK_ADDR_SHIFT=4: bits[3:2])
  //   word_idx = addr[14:BANK_ADDR_SHIFT]   (bits[14:4])
  //
  // The tasks operate on the fault_*_mask arrays; no permanent data corruption
  // occurs — a subsequent write from the core will automatically clear the mask.
  //
  // These tasks are $display-instrumented so every injection appears in the log.
  // ==========================================================================

  // ── Helper: decode byte address to bank/word index ─────────────────────────
  // (inline calculation to avoid SystemVerilog function syntax in plain Verilog)

  // inject_single_bit_fault
  //   Flips one data bit.  The core's SECDED corrects this on the next read
  //   and increments its mdccmect correctable-error counter.
  task inject_single_bit_fault;
    input [31:0] byte_addr;   // byte address within DCCM (0-relative)
    input [5:0]  bit_pos;     // which data bit to flip (0-31)
    integer bk, wd;
    begin
      bk = (byte_addr >> 2) % DCCM_NUM_BANKS;
      wd = (byte_addr >> 2) / DCCM_NUM_BANKS;
      if (wd >= DCCM_BANK_WORDS) begin
        $display("[DCCM FAULT] ERROR: addr 0x%08h is outside DCCM range", byte_addr);
      end else begin
        fault_data_mask[bk][wd] = fault_data_mask[bk][wd] | (1 << bit_pos);
        $display("[DCCM FAULT] SINGLE-BIT injected at byte_addr=0x%08h (bank=%0d word=%0d) bit=%0d  mask=0x%08h",
                 byte_addr, bk, wd, bit_pos, fault_data_mask[bk][wd]);
      end
    end
  endtask

  // inject_double_bit_fault
  //   Flips two data bits.  The core's SECDED detects an uncorrectable error
  //   and returns SLVERR on the AXI read response.
  task inject_double_bit_fault;
    input [31:0] byte_addr;
    input [5:0]  bit_pos_1;
    input [5:0]  bit_pos_2;
    integer bk, wd;
    begin
      bk = (byte_addr >> 2) % DCCM_NUM_BANKS;
      wd = (byte_addr >> 2) / DCCM_NUM_BANKS;
      if (wd >= DCCM_BANK_WORDS) begin
        $display("[DCCM FAULT] ERROR: addr 0x%08h is outside DCCM range", byte_addr);
      end else if (bit_pos_1 == bit_pos_2) begin
        $display("[DCCM FAULT] ERROR: double-bit fault requires two different bit positions");
      end else begin
        fault_data_mask[bk][wd] = fault_data_mask[bk][wd]
                                  | (1 << bit_pos_1)
                                  | (1 << bit_pos_2);
        $display("[DCCM FAULT] DOUBLE-BIT injected at byte_addr=0x%08h (bank=%0d word=%0d) bits=%0d,%0d  mask=0x%08h",
                 byte_addr, bk, wd, bit_pos_1, bit_pos_2, fault_data_mask[bk][wd]);
      end
    end
  endtask

  // inject_ecc_bit_fault
  //   Flips one ECC check-bit.  This creates a single-bit error in the ECC
  //   syndrome, equivalent to a single-bit data error from the core's perspective.
  task inject_ecc_bit_fault;
    input [31:0] byte_addr;
    input [2:0]  ecc_bit_pos;  // which ECC bit to flip (0-6)
    integer bk, wd;
    begin
      bk = (byte_addr >> 2) % DCCM_NUM_BANKS;
      wd = (byte_addr >> 2) / DCCM_NUM_BANKS;
      if (wd >= DCCM_BANK_WORDS) begin
        $display("[DCCM FAULT] ERROR: addr 0x%08h is outside DCCM range", byte_addr);
      end else begin
        fault_ecc_mask[bk][wd] = fault_ecc_mask[bk][wd] | (1 << ecc_bit_pos);
        $display("[DCCM FAULT] ECC-BIT injected at byte_addr=0x%08h (bank=%0d word=%0d) ecc_bit=%0d  mask=0x%02h",
                 byte_addr, bk, wd, ecc_bit_pos, fault_ecc_mask[bk][wd]);
      end
    end
  endtask

  // clear_fault
  //   Removes all injected fault masks at the given address.
  //   Does NOT restore any already-corrupted storage; only clears the XOR mask.
  task clear_fault;
    input [31:0] byte_addr;
    integer bk, wd;
    begin
      bk = (byte_addr >> 2) % DCCM_NUM_BANKS;
      wd = (byte_addr >> 2) / DCCM_NUM_BANKS;
      fault_data_mask[bk][wd] = {DCCM_DATA_WIDTH{1'b0}};
      fault_ecc_mask [bk][wd] = {DCCM_ECC_WIDTH{1'b0}};
      $display("[DCCM FAULT] Cleared fault mask at byte_addr=0x%08h (bank=%0d word=%0d)",
               byte_addr, bk, wd);
    end
  endtask

  // clear_all_faults
  //   Removes all injected fault masks across the entire DCCM.
  task clear_all_faults;
    integer bi, wi;
    begin
      for (bi = 0; bi < DCCM_NUM_BANKS; bi = bi + 1)
        for (wi = 0; wi < DCCM_BANK_WORDS; wi = wi + 1) begin
          fault_data_mask[bi][wi] = {DCCM_DATA_WIDTH{1'b0}};
          fault_ecc_mask [bi][wi] = {DCCM_ECC_WIDTH{1'b0}};
        end
      $display("[DCCM FAULT] All fault masks cleared");
    end
  endtask

endmodule
