// =============================================================================
// Project  : RISC-V SoC / MBIST — Full-SoC Testbench
// File     : tb/top/iccm_behavioral_model.v
// Module   : iccm_behavioral_model
//
// Description
//   Behavioral 16 KB ICCM (Instruction Closely-Coupled Memory) for simulation.
//   Sits between the el2_veer_wrapper's el2_mem_if ICCM bank interface and the
//   testbench top.
//
//   The VeeR EL2 core handles all ECC encode/decode internally.  This model is
//   pure split-bank storage of raw data + ECC bits exactly as the core presents
//   them on the interface.  No ECC logic lives here.
//
// ICCM parameters (frozen, from design decisions doc):
//   ICCM_BASE   = 0x0004_0000
//   ICCM_SIZE   = 16 KB  (0x4000 bytes)
//   NUM_BANKS   = 4      (default VeeR EL2 config)
//   BANK_WORDS  = 16384/4/4 = 1024 32-bit words per bank
//   ECC_WIDTH   = 7      (Hamming SECDED over 32-bit data)
//
// Firmware loading:
//   At time-0 (initial block) the module calls $readmemh on the file whose
//   path is passed in through the FIRMWARE_FILE parameter.  The hex file
//   must contain 32-bit words (one per line, no byte address prefix needed
//   since $readmemh loads sequentially from address 0).
//
// Revision History
//   Rev | Date       | Description
//   1.0 | 2026-10-03 | Initial release.
// =============================================================================
`timescale 1ns/1ps

module iccm_behavioral_model #(
  parameter ICCM_NUM_BANKS   = 4,
  parameter ICCM_BANK_WORDS  = 1024,    // 32-bit words per bank
  parameter ICCM_DATA_WIDTH  = 32,
  parameter ICCM_ECC_WIDTH   = 7,
  parameter ICCM_ADDR_BITS   = 15,      // log2(16384) = 14, bits [14:1]
  parameter BANK_INDEX_LO    = 3,       // addr bit where bank word index starts
  parameter FIRMWARE_FILE    = ""       // overridden at testbench instantiation
)(
  input  wire                                                    clk,

  // ── Bank interface from el2_mem_if (veer_sram_src modport) ──────────────
  input  wire [ICCM_NUM_BANKS-1:0]                              iccm_clken,
  input  wire [ICCM_NUM_BANKS-1:0]                              iccm_wren_bank,
  input  wire [ICCM_NUM_BANKS-1:0][ICCM_ADDR_BITS-1:BANK_INDEX_LO] iccm_addr_bank,
  input  wire [ICCM_NUM_BANKS-1:0][ICCM_DATA_WIDTH-1:0]        iccm_bank_wr_data,
  input  wire [ICCM_NUM_BANKS-1:0][ICCM_ECC_WIDTH-1:0]         iccm_bank_wr_ecc,

  output reg  [ICCM_NUM_BANKS-1:0][ICCM_DATA_WIDTH-1:0]        iccm_bank_dout,
  output reg  [ICCM_NUM_BANKS-1:0][ICCM_ECC_WIDTH-1:0]         iccm_bank_ecc
);

  // ── Storage arrays ─────────────────────────────────────────────────────────
  reg [ICCM_DATA_WIDTH-1:0] data_mem [0:ICCM_NUM_BANKS-1][0:ICCM_BANK_WORDS-1];
  reg [ICCM_ECC_WIDTH-1:0]  ecc_mem  [0:ICCM_NUM_BANKS-1][0:ICCM_BANK_WORDS-1];

  integer b, w;

  // ── Firmware loading ───────────────────────────────────────────────────────
  // $readmemh loads a flat word array.  We map it into bank 0 then bank 1 etc.
  // A 16 KB ICCM with 4 banks × 1024 words = 4096 total 32-bit words.
  reg [ICCM_DATA_WIDTH-1:0] flat_image [0:ICCM_NUM_BANKS*ICCM_BANK_WORDS-1];

  // ── VeeR EL2 7-bit SECDED ECC parity computation ─────────────────────────
  function [6:0] riscv_ecc32(input [31:0] data);
    reg [6:0] synd;
    begin
      synd[0] = ^(data & 32'h56aa_ad5b);
      synd[1] = ^(data & 32'h9b33_366d);
      synd[2] = ^(data & 32'he3c3_c78e);
      synd[3] = ^(data & 32'h03fc_07f0);
      synd[4] = ^(data & 32'h03ff_f800);
      synd[5] = ^(data & 32'hfc00_0000);
      synd[6] = ^{data, synd[5:0]};
      riscv_ecc32 = synd;
    end
  endfunction

  initial begin : load_firmware
    integer bank_i, word_i, flat_idx;

    // Zero-initialize all banks with valid zero ECC
    for (bank_i = 0; bank_i < ICCM_NUM_BANKS; bank_i = bank_i + 1) begin
      for (word_i = 0; word_i < ICCM_BANK_WORDS; word_i = word_i + 1) begin
        data_mem[bank_i][word_i] = {ICCM_DATA_WIDTH{1'b0}};
        ecc_mem [bank_i][word_i] = riscv_ecc32({ICCM_DATA_WIDTH{1'b0}});
      end
    end

    if (FIRMWARE_FILE != "") begin
      $readmemh(FIRMWARE_FILE, flat_image);
      // Interleave into banks: word 0 → bank 0, word 1 → bank 1, ...
      // word 4 → bank 0 word 1, etc. (VeeR EL2 default bank mapping)
      for (flat_idx = 0; flat_idx < ICCM_NUM_BANKS*ICCM_BANK_WORDS; flat_idx = flat_idx + 1) begin
        bank_i = flat_idx % ICCM_NUM_BANKS;
        word_i = flat_idx / ICCM_NUM_BANKS;
        data_mem[bank_i][word_i] = flat_image[flat_idx];
        ecc_mem [bank_i][word_i] = riscv_ecc32(flat_image[flat_idx]);
      end
      $display("[ICCM] Loaded firmware from %s with ECC generated", FIRMWARE_FILE);
    end else begin
      $display("[ICCM] WARNING: no firmware file specified, ICCM initialized to zero");
    end
  end

  // ── Bank read / write ──────────────────────────────────────────────────────
  genvar gi;
  generate
    for (gi = 0; gi < ICCM_NUM_BANKS; gi = gi + 1) begin : bank_logic

      // Write port (synchronous, clock-gated)
      always @(posedge clk) begin
        if (iccm_clken[gi] && iccm_wren_bank[gi]) begin
          data_mem[gi][iccm_addr_bank[gi][ICCM_ADDR_BITS-1:BANK_INDEX_LO]] <= iccm_bank_wr_data[gi];
          ecc_mem [gi][iccm_addr_bank[gi][ICCM_ADDR_BITS-1:BANK_INDEX_LO]] <= iccm_bank_wr_ecc[gi];
        end
      end

      // Read port (synchronous, clock-gated, registered output)
      always @(posedge clk) begin
        if (iccm_clken[gi] && !iccm_wren_bank[gi]) begin
          iccm_bank_dout[gi] <= data_mem[gi][iccm_addr_bank[gi][ICCM_ADDR_BITS-1:BANK_INDEX_LO]];
          iccm_bank_ecc[gi]  <= ecc_mem [gi][iccm_addr_bank[gi][ICCM_ADDR_BITS-1:BANK_INDEX_LO]];
        end
      end

    end
  endgenerate

endmodule
