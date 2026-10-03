// =============================================================================
// Project  : RISC-V SoC / MBIST — Full-SoC Testbench
// File     : tb/top/uart_monitor.v
// Module   : uart_monitor
//
// Description
//   Passive UART TX monitor for simulation.  Watches the uart_tx_o pin of
//   axil_uart_top and decodes transmitted bytes, printing them to the
//   simulation log.  No bus access or AXI connection required — this is a
//   purely combinational/clocked listener.
//
//   Decoding matches the UART configured by firmware:
//     Baud divisor : 434  (115 200 bps @ 50 MHz)
//     Format       : 8N1  (8 data bits, no parity, 1 stop bit)
//
//   The monitor accumulates decoded characters into a line buffer and flushes
//   it on newline.  It also exports a "byte received" event so testbench tasks
//   can block-wait for specific output strings without polling.
//
//   Special recognition:
//     "PASS" anywhere on a line → sets pass_seen = 1
//     "FAIL" anywhere on a line → sets fail_seen = 1
//
// Revision History
//   Rev | Date       | Description
//   1.0 | 2026-10-03 | Initial release.
// =============================================================================
`timescale 1ns/1ps

module uart_monitor #(
  parameter CLK_FREQ_HZ  = 50_000_000,
  parameter BAUD_RATE    = 115_200,
  parameter DATA_BITS    = 8
)(
  input  wire        clk,
  input  wire        rst_n,
  input  wire        uart_tx,       // Connect to axil_uart_top.uart_tx_o

  output reg         byte_valid,    // Pulses 1 cycle when a byte is decoded
  output reg  [7:0]  byte_data,     // The decoded byte
  output reg         pass_seen,     // Set when "PASS" is detected in output
  output reg         fail_seen      // Set when "FAIL" is detected in output
);

  // ── Baud timing ────────────────────────────────────────────────────────────
  // clocks per bit at 50 MHz / 115200 ≈ 434
  localparam integer CLKS_PER_BIT  = CLK_FREQ_HZ / BAUD_RATE;
  localparam integer HALF_BIT      = CLKS_PER_BIT / 2;

  // ── State machine ──────────────────────────────────────────────────────────
  localparam ST_IDLE      = 2'b00;
  localparam ST_START     = 2'b01;
  localparam ST_DATA      = 2'b10;
  localparam ST_STOP      = 2'b11;

  reg [1:0]  state;
  reg [15:0] baud_cnt;
  reg [3:0]  bit_idx;
  reg [7:0]  shift_reg;

  // ── Start-bit edge detection ────────────────────────────────────────────────
  reg uart_tx_r1, uart_tx_r2;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      uart_tx_r1 <= 1'b1;
      uart_tx_r2 <= 1'b1;
    end else begin
      uart_tx_r1 <= uart_tx;
      uart_tx_r2 <= uart_tx_r1;
    end
  end

  wire start_edge = uart_tx_r2 & ~uart_tx_r1;  // high-to-low = start bit

  // ── Main decode FSM ────────────────────────────────────────────────────────
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state     <= ST_IDLE;
      baud_cnt  <= 0;
      bit_idx   <= 0;
      shift_reg <= 8'h00;
      byte_valid<= 1'b0;
      byte_data <= 8'h00;
    end else begin
      byte_valid <= 1'b0;  // default: de-assert

      case (state)

        ST_IDLE: begin
          if (start_edge) begin
            // Align to middle of start bit
            baud_cnt <= HALF_BIT[15:0];
            state    <= ST_START;
          end
        end

        ST_START: begin
          if (baud_cnt == 0) begin
            // Sample middle of start bit — verify it's still low
            if (!uart_tx_r1) begin
              baud_cnt <= CLKS_PER_BIT[15:0] - 1;
              bit_idx  <= 0;
              state    <= ST_DATA;
            end else begin
              // False trigger, back to idle
              state <= ST_IDLE;
            end
          end else begin
            baud_cnt <= baud_cnt - 1;
          end
        end

        ST_DATA: begin
          if (baud_cnt == 0) begin
            shift_reg <= {uart_tx_r1, shift_reg[7:1]};  // LSB first
            if (bit_idx == DATA_BITS - 1) begin
              baud_cnt <= CLKS_PER_BIT[15:0] - 1;
              state    <= ST_STOP;
            end else begin
              bit_idx  <= bit_idx + 1;
              baud_cnt <= CLKS_PER_BIT[15:0] - 1;
            end
          end else begin
            baud_cnt <= baud_cnt - 1;
          end
        end

        ST_STOP: begin
          if (baud_cnt == 0) begin
            if (uart_tx_r1) begin  // stop bit must be high
              byte_valid <= 1'b1;
              byte_data  <= shift_reg;
            end
            state <= ST_IDLE;
          end else begin
            baud_cnt <= baud_cnt - 1;
          end
        end

      endcase
    end
  end

  // ── Line buffer and log printing ──────────────────────────────────────────
  // Buffer up to 128 chars; flush on newline or buffer full.
  reg [7:0]  line_buf [0:127];
  reg [6:0]  line_idx;
  integer    pass_search_idx;
  integer    fail_search_idx;

  // Simple substring match helpers
  function automatic check_pass;
    input [6:0] len;
    integer i;
    reg match;
    begin
      match = 0;
      for (i = 0; i <= len - 4; i = i + 1) begin
        if (line_buf[i]   == "P" &&
            line_buf[i+1] == "A" &&
            line_buf[i+2] == "S" &&
            line_buf[i+3] == "S")
          match = 1;
      end
      check_pass = match;
    end
  endfunction

  function automatic check_fail;
    input [6:0] len;
    integer i;
    reg match;
    begin
      match = 0;
      for (i = 0; i <= len - 4; i = i + 1) begin
        if (line_buf[i]   == "F" &&
            line_buf[i+1] == "A" &&
            line_buf[i+2] == "I" &&
            line_buf[i+3] == "L")
          match = 1;
      end
      check_fail = match;
    end
  endfunction

  initial begin
    line_idx  = 0;
    pass_seen = 0;
    fail_seen = 0;
  end

  always @(posedge clk) begin
    if (byte_valid) begin
      if (byte_data == 8'h0A || line_idx == 127) begin
        // Newline or buffer full — flush line to log
        // Print accumulated string (Verilog doesn't have printf with %s on
        // reg arrays directly; we print char by char)
        $write("[UART] ");
        begin : flush_block
          integer fi;
          for (fi = 0; fi < line_idx; fi = fi + 1) begin
            if (line_buf[fi] >= 8'h20 && line_buf[fi] <= 8'h7E)
              $write("%s", line_buf[fi]);  // printable ASCII
            else
              $write(".");
          end
        end
        $write("\n");

        // Check for PASS/FAIL tokens
        if (line_idx >= 4) begin
          if (check_pass(line_idx)) begin
            pass_seen <= 1'b1;
            $display("[UART MONITOR] *** PASS token detected in UART output ***");
          end
          if (check_fail(line_idx)) begin
            fail_seen <= 1'b1;
            $display("[UART MONITOR] *** FAIL token detected in UART output ***");
          end
        end

        line_idx <= 0;
      end else if (byte_data != 8'h0D) begin
        // Accumulate printable character (skip CR)
        line_buf[line_idx] <= byte_data;
        line_idx <= line_idx + 1;
      end
    end
  end

endmodule
