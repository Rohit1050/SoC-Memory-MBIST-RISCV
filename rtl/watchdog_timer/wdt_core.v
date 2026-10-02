/* -----------------------------------------------------------------------------
 * Project        : RISC-V SoC / MBIST  —  Watchdog Timer IP
 * File           : wdt_core.v
 * Module         : wdt_core
 * Description    : Bus-agnostic Watchdog Timer countdown engine and post-mortem
 *                  status latch.
 *
 *                  Provides:
 *                    - 32-bit countdown decrementer
 *                    - Instant reload upon kick pulse
 *                    - Pre-timeout threshold comparator (early-warning IRQ to PIC)
 *                    - Expiry timeout trigger to reset generator
 *                    - Sticky timeout_occurred status flag clocked in the cold
 *                      reset (POR) domain, surviving warm system resets.
 * -----------------------------------------------------------------------------*/
`timescale 1ns/1ps

`default_nettype none

module wdt_core #
(
  parameter DEFAULT_LOAD       = 32'd0,
  parameter DEFAULT_PRETIMEOUT = 32'd0
)
(
  // -------------------------------------------------------------------------
  // Clocks and resets
  // -------------------------------------------------------------------------
  input  wire         clk_i,               // System clock
  input  wire         rst_n_i,             // Active-low warm system reset
  input  wire         por_rstn_i,          // Active-low cold power-on reset

  // -------------------------------------------------------------------------
  // Control and configuration inputs (from bus wrapper / CSRs)
  // -------------------------------------------------------------------------
  input  wire         enable_i,            // Countdown enable (wdg_enable[0])
  input  wire [31:0]  load_val_i,          // Reload value (wdg_load[31:0])
  input  wire         kick_i,              // Reload trigger pulse (wdg_kick write)
  input  wire [31:0]  pretimeout_val_i,    // Pre-timeout threshold (wdg_pretimeout)
  input  wire         w1c_status_clear_i,  // W1C pulse to clear timeout_occurred

  // -------------------------------------------------------------------------
  // Status and timer outputs
  // -------------------------------------------------------------------------
  output reg  [31:0]  count_o,             // Current countdown value (wdg_count)
  output reg          timeout_o,           // Asserted on countdown expiry
  output reg          pretimeout_irq_o,    // Early-warning interrupt to PIC
  output reg          timeout_occurred_o   // Sticky flag preserved across warm reset
);

  // -------------------------------------------------------------------------
  // Internal next-state signals
  // -------------------------------------------------------------------------
  reg [31:0] count_d;
  reg        timeout_d;
  reg        pretimeout_irq_d;
  reg        timeout_occurred_d;

  // -------------------------------------------------------------------------
  // Countdown Timer & Timeout Combinational Logic
  // -------------------------------------------------------------------------
  always @(*) begin
    count_d          = count_o;
    timeout_d        = 1'b0;
    pretimeout_irq_d = 1'b0;

    if (!enable_i) begin
      // When disabled, reset countdown to reload value
      count_d          = load_val_i;
      timeout_d        = 1'b0;
      pretimeout_irq_d = 1'b0;
    end else if (kick_i) begin
      // Kick: reload counter immediately
      count_d          = load_val_i;
      timeout_d        = 1'b0;
      pretimeout_irq_d = 1'b0;
    end else if (count_o > 32'd0) begin
      // Active decrement
      count_d = count_o - 1'b1;

      // Check for countdown expiry (decrementing to 0)
      if (count_o == 32'd1) begin
        timeout_d = 1'b1;
      end

      // Check pre-timeout threshold
      if ((pretimeout_val_i != 32'd0) && (count_d <= pretimeout_val_i) && (count_d > 32'd0)) begin
        pretimeout_irq_d = 1'b1;
      end
    end else begin
      // Count is zero: hold at zero and keep timeout asserted until reset/kick
      count_d   = 32'd0;
      timeout_d = 1'b1;
    end
  end

  // -------------------------------------------------------------------------
  // Operational Counter Sequential Block (Warm Reset Domain)
  // -------------------------------------------------------------------------
  always @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      count_o          <= DEFAULT_LOAD;
      timeout_o        <= 1'b0;
      pretimeout_irq_o <= 1'b0;
    end else begin
      count_o          <= count_d;
      timeout_o        <= timeout_d;
      pretimeout_irq_o <= pretimeout_irq_d;
    end
  end

  // -------------------------------------------------------------------------
  // Sticky Post-Mortem Status Latch (Cold POR Reset Domain)
  // -------------------------------------------------------------------------
  always @(*) begin
    timeout_occurred_d = timeout_occurred_o;

    // Check for W1C clear from firmware
    if (w1c_status_clear_i) begin
      timeout_occurred_d = 1'b0;
    end

    // Set on timeout event
    if (enable_i && (count_o == 32'd1)) begin
      timeout_occurred_d = 1'b1;
    end
  end

  always @(posedge clk_i or negedge por_rstn_i) begin
    if (!por_rstn_i) begin
      timeout_occurred_o <= 1'b0;
    end else begin
      timeout_occurred_o <= timeout_occurred_d;
    end
  end

endmodule

`default_nettype wire
