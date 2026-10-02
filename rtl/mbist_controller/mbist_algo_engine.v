/* -----------------------------------------------------------------------------
 * Project        : RISC-V SoC / MBIST  —  MBIST Controller IP
 * File           : mbist_algo_engine.v
 * Module         : mbist_algo_engine
 * Description    : Algorithmic test sequencer for Memory Built-In Self-Test.
 *                  Executes Checkerboard and March C- test algorithms across
 *                  the programmed DCCM address range via the DMA master engine.
 *
 * Supported Algorithms:
 *   - Checkerboard (2'b00): Alternating 0x55/0xAA patterns, 4 phases
 *   - March C-     (2'b01): 6-element march sequence (10N operations):
 *       M0: ⇑ {w0}
 *       M1: ⇑ {r0, w1}
 *       M2: ⇑ {r1, w0}
 *       M3: ⇓ {r0, w1}
 *       M4: ⇓ {r1, w0}
 *       M5: ⇑ {r0}
 * -----------------------------------------------------------------------------*/
`timescale 1ns/1ps

`default_nettype none

`include "axil_mbist_defines.vh"

module mbist_algo_engine #
(
  parameter DATA_WIDTH = `_AXI4_MBIST_DMA_DATA_WIDTH_, // 64
  parameter ADDR_WIDTH = `_AXI4_MBIST_DMA_ADDR_WIDTH_  // 32
)
(
  // -------------------------------------------------------------------------
  // Clock & reset
  // -------------------------------------------------------------------------
  input  wire                                clk_i,
  input  wire                                rst_n_i,

  // -------------------------------------------------------------------------
  // Control and configuration inputs (from CSRs)
  // -------------------------------------------------------------------------
  input  wire                                start_i,         // start pulse
  input  wire [1:0]                          algo_sel_i,      // 00=Checkerboard, 01=March C-
  input  wire [ADDR_WIDTH-1:0]               addr_start_i,    // DCCM start address
  input  wire [ADDR_WIDTH-1:0]               addr_end_i,      // DCCM end address (inclusive)

  // -------------------------------------------------------------------------
  // Status outputs (to CSRs & external pins)
  // -------------------------------------------------------------------------
  output reg                                 busy_o,
  output reg                                 done_o,
  output reg                                 pass_fail_o,     // 0 = pass, 1 = fail
  output reg  [ADDR_WIDTH-1:0]               fault_addr_o,    // address of first fault
  output reg  [15:0]                         fault_count_o,   // total faults count
  output wire                                active_o,        // high while test running
  output reg  [ADDR_WIDTH-1:0]               current_addr_o,  // tap for ECC Monitor

  // -------------------------------------------------------------------------
  // DMA Master command & response interface
  // -------------------------------------------------------------------------
  output reg                                 cmd_valid_o,
  output reg                                 cmd_write_o,     // 1=write, 0=read
  output reg  [ADDR_WIDTH-1:0]               cmd_addr_o,
  output reg  [DATA_WIDTH-1:0]               cmd_wdata_o,
  input  wire                                cmd_ready_i,

  input  wire                                rsp_valid_i,
  input  wire [DATA_WIDTH-1:0]               rsp_rdata_i,
  input  wire                                rsp_slverr_i
);

  assign active_o = busy_o;

  // Patterns
  localparam [64:0] PAT_ZEROS = 64'h0000_0000_0000_0000;
  localparam [64:0] PAT_ONES  = 64'hFFFF_FFFF_FFFF_FFFF;
  localparam [64:0] PAT_55    = 64'h5555_5555_5555_5555;
  localparam [64:0] PAT_AA    = 64'hAAAA_AAAA_AAAA_AAAA;

  // Engine Top-Level FSM States
  localparam [3:0]
    ST_IDLE            = 4'h0,
    ST_INIT            = 4'h1,
    // Checkerboard States
    ST_CHK_W1          = 4'h2,
    ST_CHK_R1          = 4'h3,
    ST_CHK_W2          = 4'h4,
    ST_CHK_R2          = 4'h5,
    // March C- States
    ST_MARCH_M0_W      = 4'h6,  // ⇑ {w0}
    ST_MARCH_M1_R      = 4'h7,  // ⇑ {r0, w1} - read step
    ST_MARCH_M1_W      = 4'h8,  // ⇑ {r0, w1} - write step
    ST_MARCH_M2_R      = 4'h9,  // ⇑ {r1, w0} - read step
    ST_MARCH_M2_W      = 4'hA,  // ⇑ {r1, w0} - write step
    ST_MARCH_M3_R      = 4'hB,  // ⇓ {r0, w1} - read step
    ST_MARCH_M3_W      = 4'hC,  // ⇓ {r0, w1} - write step
    ST_MARCH_M4_R      = 4'hD,  // ⇓ {r1, w0} - read step
    ST_MARCH_M4_W      = 4'hE,  // ⇓ {r1, w0} - write step
    ST_MARCH_M5_R      = 4'hF;  // ⇑ {r0}

  reg [3:0] state;

  // Latched bounds (aligned to 8 bytes)
  reg [ADDR_WIDTH-1:0] start_addr_reg;
  reg [ADDR_WIDTH-1:0] end_addr_reg;
  reg [ADDR_WIDTH-1:0] curr_addr;
  reg [1:0]            algo_reg;

  // Expected read data for verification
  reg [DATA_WIDTH-1:0] exp_rdata;

  // Checkerboard pattern helpers
  wire [DATA_WIDTH-1:0] chk_pat1 = (curr_addr[3] == 1'b0) ? PAT_55 : PAT_AA;
  wire [DATA_WIDTH-1:0] chk_pat2 = (curr_addr[3] == 1'b0) ? PAT_AA : PAT_55;

  // Fault logging helper
  task record_fault;
    input [ADDR_WIDTH-1:0] addr;
    begin
      pass_fail_o <= 1'b1;
      if (fault_count_o == 16'd0) begin
        fault_addr_o <= addr;
      end
      if (fault_count_o < 16'hFFFF) begin
        fault_count_o <= fault_count_o + 1'b1;
      end
    end
  endtask

  // ---- Engine Sequential Logic ----
  always @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      state          <= ST_IDLE;
      busy_o         <= 1'b0;
      done_o         <= 1'b0;
      pass_fail_o    <= 1'b0;
      fault_addr_o   <= {ADDR_WIDTH{1'b0}};
      fault_count_o  <= 16'd0;
      current_addr_o <= {ADDR_WIDTH{1'b0}};
      cmd_valid_o    <= 1'b0;
      cmd_write_o    <= 1'b0;
      cmd_addr_o     <= {ADDR_WIDTH{1'b0}};
      cmd_wdata_o    <= {DATA_WIDTH{1'b0}};
      curr_addr      <= {ADDR_WIDTH{1'b0}};
      start_addr_reg <= {ADDR_WIDTH{1'b0}};
      end_addr_reg   <= {ADDR_WIDTH{1'b0}};
      algo_reg       <= 2'b00;
      exp_rdata      <= {DATA_WIDTH{1'b0}};
    end else begin
      done_o <= 1'b0; // default 1-cycle pulse for done

      case (state)

        // --------------------------------------------------------------------
        ST_IDLE: begin
          cmd_valid_o <= 1'b0;
          if (start_i && !busy_o) begin
            busy_o         <= 1'b1;
            pass_fail_o    <= 1'b0;
            fault_addr_o   <= {ADDR_WIDTH{1'b0}};
            fault_count_o  <= 16'd0;
            algo_reg       <= algo_sel_i;
            start_addr_reg <= {addr_start_i[ADDR_WIDTH-1:3], 3'b000};
            end_addr_reg   <= {addr_end_i[ADDR_WIDTH-1:3],   3'b000};
            curr_addr      <= {addr_start_i[ADDR_WIDTH-1:3], 3'b000};
            state          <= ST_INIT;
          end
        end

        // --------------------------------------------------------------------
        ST_INIT: begin
          current_addr_o <= curr_addr;
          // Guard: if end address is less than start address, finish immediately
          if (end_addr_reg < start_addr_reg) begin
            busy_o <= 1'b0;
            done_o <= 1'b1;
            state  <= ST_IDLE;
          end else if (algo_reg == `MBIST_ALGO_CHECKERBOARD) begin
            state <= ST_CHK_W1;
          end else begin
            state <= ST_MARCH_M0_W;
          end
        end

        // ====================================================================
        // CHECKERBOARD ALGORITHM
        // ====================================================================

        // Phase 1: Write Checkerboard 1 (0x55 / 0xAA)
        ST_CHK_W1: begin
          current_addr_o <= curr_addr;
          if (!cmd_valid_o) begin
            cmd_valid_o <= 1'b1;
            cmd_write_o <= 1'b1;
            cmd_addr_o  <= curr_addr;
            cmd_wdata_o <= chk_pat1;
          end else if (cmd_ready_i) begin
            cmd_valid_o <= 1'b0;
          end

          if (rsp_valid_i) begin
            if (rsp_slverr_i) record_fault(curr_addr);
            if (curr_addr >= end_addr_reg) begin
              curr_addr <= start_addr_reg;
              state     <= ST_CHK_R1;
            end else begin
              curr_addr <= curr_addr + 8;
            end
          end
        end

        // Phase 2: Read & Verify Checkerboard 1
        ST_CHK_R1: begin
          current_addr_o <= curr_addr;
          exp_rdata      <= chk_pat1;
          if (!cmd_valid_o) begin
            cmd_valid_o <= 1'b1;
            cmd_write_o <= 1'b0;
            cmd_addr_o  <= curr_addr;
          end else if (cmd_ready_i) begin
            cmd_valid_o <= 1'b0;
          end

          if (rsp_valid_i) begin
            if (rsp_slverr_i || (rsp_rdata_i !== exp_rdata)) begin
              record_fault(curr_addr);
            end
            if (curr_addr >= end_addr_reg) begin
              curr_addr <= start_addr_reg;
              state     <= ST_CHK_W2;
            end else begin
              curr_addr <= curr_addr + 8;
            end
          end
        end

        // Phase 3: Write Checkerboard 2 (Inverted: 0xAA / 0x55)
        ST_CHK_W2: begin
          current_addr_o <= curr_addr;
          if (!cmd_valid_o) begin
            cmd_valid_o <= 1'b1;
            cmd_write_o <= 1'b1;
            cmd_addr_o  <= curr_addr;
            cmd_wdata_o <= chk_pat2;
          end else if (cmd_ready_i) begin
            cmd_valid_o <= 1'b0;
          end

          if (rsp_valid_i) begin
            if (rsp_slverr_i) record_fault(curr_addr);
            if (curr_addr >= end_addr_reg) begin
              curr_addr <= start_addr_reg;
              state     <= ST_CHK_R2;
            end else begin
              curr_addr <= curr_addr + 8;
            end
          end
        end

        // Phase 4: Read & Verify Checkerboard 2
        ST_CHK_R2: begin
          current_addr_o <= curr_addr;
          exp_rdata      <= chk_pat2;
          if (!cmd_valid_o) begin
            cmd_valid_o <= 1'b1;
            cmd_write_o <= 1'b0;
            cmd_addr_o  <= curr_addr;
          end else if (cmd_ready_i) begin
            cmd_valid_o <= 1'b0;
          end

          if (rsp_valid_i) begin
            if (rsp_slverr_i || (rsp_rdata_i !== exp_rdata)) begin
              record_fault(curr_addr);
            end
            if (curr_addr >= end_addr_reg) begin
              busy_o <= 1'b0;
              done_o <= 1'b1;
              state  <= ST_IDLE;
            end else begin
              curr_addr <= curr_addr + 8;
            end
          end
        end

        // ====================================================================
        // MARCH C- ALGORITHM
        // ====================================================================

        // M0: ⇑ {w0} — Ascending write 0 to all cells
        ST_MARCH_M0_W: begin
          current_addr_o <= curr_addr;
          if (!cmd_valid_o) begin
            cmd_valid_o <= 1'b1;
            cmd_write_o <= 1'b1;
            cmd_addr_o  <= curr_addr;
            cmd_wdata_o <= PAT_ZEROS;
          end else if (cmd_ready_i) begin
            cmd_valid_o <= 1'b0;
          end

          if (rsp_valid_i) begin
            if (rsp_slverr_i) record_fault(curr_addr);
            if (curr_addr >= end_addr_reg) begin
              curr_addr <= start_addr_reg;
              state     <= ST_MARCH_M1_R;
            end else begin
              curr_addr <= curr_addr + 8;
            end
          end
        end

        // M1: ⇑ {r0, w1} - Read 0 step
        ST_MARCH_M1_R: begin
          current_addr_o <= curr_addr;
          exp_rdata      <= PAT_ZEROS;
          if (!cmd_valid_o) begin
            cmd_valid_o <= 1'b1;
            cmd_write_o <= 1'b0;
            cmd_addr_o  <= curr_addr;
          end else if (cmd_ready_i) begin
            cmd_valid_o <= 1'b0;
          end

          if (rsp_valid_i) begin
            if (rsp_slverr_i || (rsp_rdata_i !== exp_rdata)) begin
              record_fault(curr_addr);
            end
            state <= ST_MARCH_M1_W;
          end
        end

        // M1: ⇑ {r0, w1} - Write 1 step
        ST_MARCH_M1_W: begin
          if (!cmd_valid_o) begin
            cmd_valid_o <= 1'b1;
            cmd_write_o <= 1'b1;
            cmd_addr_o  <= curr_addr;
            cmd_wdata_o <= PAT_ONES;
          end else if (cmd_ready_i) begin
            cmd_valid_o <= 1'b0;
          end

          if (rsp_valid_i) begin
            if (rsp_slverr_i) record_fault(curr_addr);
            if (curr_addr >= end_addr_reg) begin
              curr_addr <= start_addr_reg;
              state     <= ST_MARCH_M2_R;
            end else begin
              curr_addr <= curr_addr + 8;
              state     <= ST_MARCH_M1_R;
            end
          end
        end

        // M2: ⇑ {r1, w0} - Read 1 step
        ST_MARCH_M2_R: begin
          current_addr_o <= curr_addr;
          exp_rdata      <= PAT_ONES;
          if (!cmd_valid_o) begin
            cmd_valid_o <= 1'b1;
            cmd_write_o <= 1'b0;
            cmd_addr_o  <= curr_addr;
          end else if (cmd_ready_i) begin
            cmd_valid_o <= 1'b0;
          end

          if (rsp_valid_i) begin
            if (rsp_slverr_i || (rsp_rdata_i !== exp_rdata)) begin
              record_fault(curr_addr);
            end
            state <= ST_MARCH_M2_W;
          end
        end

        // M2: ⇑ {r1, w0} - Write 0 step
        ST_MARCH_M2_W: begin
          if (!cmd_valid_o) begin
            cmd_valid_o <= 1'b1;
            cmd_write_o <= 1'b1;
            cmd_addr_o  <= curr_addr;
            cmd_wdata_o <= PAT_ZEROS;
          end else if (cmd_ready_i) begin
            cmd_valid_o <= 1'b0;
          end

          if (rsp_valid_i) begin
            if (rsp_slverr_i) record_fault(curr_addr);
            if (curr_addr >= end_addr_reg) begin
              curr_addr <= end_addr_reg; // prepare for descending pass
              state     <= ST_MARCH_M3_R;
            end else begin
              curr_addr <= curr_addr + 8;
              state     <= ST_MARCH_M2_R;
            end
          end
        end

        // M3: ⇓ {r0, w1} - Descending read 0 step
        ST_MARCH_M3_R: begin
          current_addr_o <= curr_addr;
          exp_rdata      <= PAT_ZEROS;
          if (!cmd_valid_o) begin
            cmd_valid_o <= 1'b1;
            cmd_write_o <= 1'b0;
            cmd_addr_o  <= curr_addr;
          end else if (cmd_ready_i) begin
            cmd_valid_o <= 1'b0;
          end

          if (rsp_valid_i) begin
            if (rsp_slverr_i || (rsp_rdata_i !== exp_rdata)) begin
              record_fault(curr_addr);
            end
            state <= ST_MARCH_M3_W;
          end
        end

        // M3: ⇓ {r0, w1} - Descending write 1 step
        ST_MARCH_M3_W: begin
          if (!cmd_valid_o) begin
            cmd_valid_o <= 1'b1;
            cmd_write_o <= 1'b1;
            cmd_addr_o  <= curr_addr;
            cmd_wdata_o <= PAT_ONES;
          end else if (cmd_ready_i) begin
            cmd_valid_o <= 1'b0;
          end

          if (rsp_valid_i) begin
            if (rsp_slverr_i) record_fault(curr_addr);
            if (curr_addr <= start_addr_reg) begin
              curr_addr <= end_addr_reg; // descending next element
              state     <= ST_MARCH_M4_R;
            end else begin
              curr_addr <= curr_addr - 8;
              state     <= ST_MARCH_M3_R;
            end
          end
        end

        // M4: ⇓ {r1, w0} - Descending read 1 step
        ST_MARCH_M4_R: begin
          current_addr_o <= curr_addr;
          exp_rdata      <= PAT_ONES;
          if (!cmd_valid_o) begin
            cmd_valid_o <= 1'b1;
            cmd_write_o <= 1'b0;
            cmd_addr_o  <= curr_addr;
          end else if (cmd_ready_i) begin
            cmd_valid_o <= 1'b0;
          end

          if (rsp_valid_i) begin
            if (rsp_slverr_i || (rsp_rdata_i !== exp_rdata)) begin
              record_fault(curr_addr);
            end
            state <= ST_MARCH_M4_W;
          end
        end

        // M4: ⇓ {r1, w0} - Descending write 0 step
        ST_MARCH_M4_W: begin
          if (!cmd_valid_o) begin
            cmd_valid_o <= 1'b1;
            cmd_write_o <= 1'b1;
            cmd_addr_o  <= curr_addr;
            cmd_wdata_o <= PAT_ZEROS;
          end else if (cmd_ready_i) begin
            cmd_valid_o <= 1'b0;
          end

          if (rsp_valid_i) begin
            if (rsp_slverr_i) record_fault(curr_addr);
            if (curr_addr <= start_addr_reg) begin
              curr_addr <= start_addr_reg; // final ascending read pass
              state     <= ST_MARCH_M5_R;
            end else begin
              curr_addr <= curr_addr - 8;
              state     <= ST_MARCH_M4_R;
            end
          end
        end

        // M5: ⇑ {r0} - Final ascending read 0 step
        ST_MARCH_M5_R: begin
          current_addr_o <= curr_addr;
          exp_rdata      <= PAT_ZEROS;
          if (!cmd_valid_o) begin
            cmd_valid_o <= 1'b1;
            cmd_write_o <= 1'b0;
            cmd_addr_o  <= curr_addr;
          end else if (cmd_ready_i) begin
            cmd_valid_o <= 1'b0;
          end

          if (rsp_valid_i) begin
            if (rsp_slverr_i || (rsp_rdata_i !== exp_rdata)) begin
              record_fault(curr_addr);
            end
            if (curr_addr >= end_addr_reg) begin
              busy_o <= 1'b0;
              done_o <= 1'b1;
              state  <= ST_IDLE;
            end else begin
              curr_addr <= curr_addr + 8;
            end
          end
        end

        default: begin
          state <= ST_IDLE;
        end

      endcase
    end
  end

endmodule

`default_nettype wire
