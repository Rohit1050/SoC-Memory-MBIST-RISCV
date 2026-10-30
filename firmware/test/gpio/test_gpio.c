/* =============================================================================
 * Test File   : firmware/test/test_gpio.c
 * IP Tested   : AXI4-Lite GPIO (axil_gpio_top)
 * Base Address: 0x4000_2000
 * Toolchain   : riscv32-unknown-elf-gcc -march=rv32imc -mabi=ilp32
 *
 * Register Map (from axil_gpio_top.v):
 *   0x000  GPIO_DIR  (R/W, 8-bit) : 1 = output, 0 = input (per bit)
 *   0x004  GPIO_OUT  (R/W, 8-bit) : output drive value
 *   0x008  GPIO_IN   (RO,  8-bit) : 2-flop synchronized capture of gpio_in_i
 *
 * Hardware behaviour:
 *   gpio_out_o[i] = gpio_dir[i] & gpio_out_reg[i]
 *   gpio_out_o is always driven — no tri-state.
 *   Writes to GPIO_IN are silently ignored (no corruption, OKAY response).
 *   Writes to any other offset in the 4 KB window return SLVERR.
 *
 * Test Coverage:
 *   1. Reset state         — DIR=0 (all inputs), OUT=0 after reset
 *   2. GPIO_DIR patterns   — walking-ones, walking-zeros, nibble split
 *   3. GPIO_OUT patterns   — checkerboard, complement, all-ones, all-zeros
 *   4. GPIO_DIR / OUT independence — OUT register retains value across DIR changes
 *   5. GPIO_IN read-only   — write has no effect; value does not change
 *   6. Output gating       — gpio_out_o = DIR & OUT (read OUT after DIR=0 forced)
 *   7. SLVERR safety       — unmapped offset read returns 0, CPU survives
 *
 * Note on GPIO_IN:
 *   In bare-metal simulation, gpio_in_i is driven by the testbench.
 *   The firmware cannot control it.  We only verify the write-protection
 *   property (write ignored) here.  Value-correctness tests live in
 *   tb/gpio/tb_axil_gpio_top.v where the input can be forced.
 * =============================================================================*/

#include "test_common.h"

int main(void)
{
    test_header("TEST SUITE: GPIO");

    /* ------------------------------------------------------------------
     * SUBTEST 1: Reset state
     *   After system reset, GPIO_DIR and GPIO_OUT should both be 0x00
     *   (all pins configured as inputs, output register cleared).
     * ------------------------------------------------------------------*/
    uart_print("[SUBTEST 1] Reset state...\n");

    uint32_t dir_boot = GPIO_DIR & 0xFF;
    uint32_t out_boot = GPIO_OUT & 0xFF;
    uart_print("  GPIO_DIR at boot: "); uart_print_hex(dir_boot); uart_print("\n");
    uart_print("  GPIO_OUT at boot: "); uart_print_hex(out_boot); uart_print("\n");

    report_test("GPIO_DIR = 0x00 at reset (all inputs)", dir_boot == 0x00);
    report_test("GPIO_OUT = 0x00 at reset", out_boot == 0x00);

    /* ------------------------------------------------------------------
     * SUBTEST 2: GPIO_DIR walking-ones and nibble patterns
     *   Verify all 8 direction bits can be set individually.
     * ------------------------------------------------------------------*/
    uart_print("\n[SUBTEST 2] GPIO_DIR write/readback patterns...\n");

    /* Walking-ones */
    int dir_ok = 1;
    for (int i = 0; i < 8; i++) {
        uint8_t val = (uint8_t)(1u << i);
        GPIO_DIR = val;
        if ((GPIO_DIR & 0xFF) != val) { dir_ok = 0; break; }
    }
    report_test("GPIO_DIR walking-ones (bits 0–7)", dir_ok);

    /* Walking-zeros */
    int dirz_ok = 1;
    for (int i = 0; i < 8; i++) {
        uint8_t val = (uint8_t)(0xFF & ~(1u << i));
        GPIO_DIR = val;
        if ((GPIO_DIR & 0xFF) != val) { dirz_ok = 0; break; }
    }
    report_test("GPIO_DIR walking-zeros (bits 0–7)", dirz_ok);

    /* Split nibble */
    GPIO_DIR = 0xF0;
    report_test("GPIO_DIR 0xF0 (upper nibble outputs)", (GPIO_DIR & 0xFF) == 0xF0);
    GPIO_DIR = 0x0F;
    report_test("GPIO_DIR 0x0F (lower nibble outputs)", (GPIO_DIR & 0xFF) == 0x0F);

    /* All outputs */
    GPIO_DIR = 0xFF;
    report_test("GPIO_DIR 0xFF (all outputs)", (GPIO_DIR & 0xFF) == 0xFF);

    /* All inputs */
    GPIO_DIR = 0x00;
    report_test("GPIO_DIR 0x00 (all inputs)", (GPIO_DIR & 0xFF) == 0x00);

    /* ------------------------------------------------------------------
     * SUBTEST 3: GPIO_OUT write/readback patterns
     *   The output register stores its value regardless of DIR.
     *   (gpio_out_o is gated by DIR, but the register itself is not.)
     * ------------------------------------------------------------------*/
    uart_print("\n[SUBTEST 3] GPIO_OUT write/readback patterns...\n");

    GPIO_OUT = 0xA5;   /* 1010_0101 checkerboard */
    report_test("GPIO_OUT 0xA5 write/readback", (GPIO_OUT & 0xFF) == 0xA5);

    GPIO_OUT = 0x5A;   /* 0101_1010 complement */
    report_test("GPIO_OUT 0x5A write/readback", (GPIO_OUT & 0xFF) == 0x5A);

    GPIO_OUT = 0xFF;   /* all-ones */
    report_test("GPIO_OUT 0xFF write/readback", (GPIO_OUT & 0xFF) == 0xFF);

    GPIO_OUT = 0x00;   /* all-zeros */
    report_test("GPIO_OUT 0x00 write/readback", (GPIO_OUT & 0xFF) == 0x00);

    /* Walking-ones */
    int out_ok = 1;
    for (int i = 0; i < 8; i++) {
        uint8_t val = (uint8_t)(1u << i);
        GPIO_OUT = val;
        if ((GPIO_OUT & 0xFF) != val) { out_ok = 0; break; }
    }
    report_test("GPIO_OUT walking-ones (bits 0–7)", out_ok);

    /* ------------------------------------------------------------------
     * SUBTEST 4: DIR / OUT independence
     *   Write a value to GPIO_OUT, then flip GPIO_DIR multiple times.
     *   The GPIO_OUT register must retain its value across DIR changes.
     * ------------------------------------------------------------------*/
    uart_print("\n[SUBTEST 4] GPIO_DIR does not corrupt GPIO_OUT...\n");

    GPIO_OUT = 0xC3;   /* reference value */
    GPIO_DIR = 0xFF;   report_test("GPIO_OUT 0xC3 stable with DIR=0xFF", (GPIO_OUT & 0xFF) == 0xC3);
    GPIO_DIR = 0x00;   report_test("GPIO_OUT 0xC3 stable with DIR=0x00", (GPIO_OUT & 0xFF) == 0xC3);
    GPIO_DIR = 0xAA;   report_test("GPIO_OUT 0xC3 stable with DIR=0xAA", (GPIO_OUT & 0xFF) == 0xC3);
    GPIO_OUT = 0x00;

    /* ------------------------------------------------------------------
     * SUBTEST 5: GPIO_IN is read-only
     *   The synchronized input register must not be writable from SW.
     *   Capture the current value, write the bitwise complement,
     *   read back — the value must be unchanged.
     *   (The AXI4-Lite slave silently accepts the write and returns OKAY
     *   per the RTL spec but the register itself is not updated.)
     * ------------------------------------------------------------------*/
    uart_print("\n[SUBTEST 5] GPIO_IN is read-only (write ignored)...\n");

    uint32_t in_before = GPIO_IN & 0xFF;
    GPIO_IN = (~in_before) & 0xFF;   /* attempt to flip all bits */
    uint32_t in_after  = GPIO_IN & 0xFF;
    uart_print("  GPIO_IN before: "); uart_print_hex(in_before);
    uart_print("  after write: ");    uart_print_hex(in_after);
    uart_print("\n");
    report_test("GPIO_IN unchanged after write (read-only)", in_before == in_after);

    /* Write 0x00 and 0xFF — both should have no effect */
    GPIO_IN = 0x00;
    report_test("GPIO_IN unchanged after write 0x00", (GPIO_IN & 0xFF) == in_before);
    GPIO_IN = 0xFF;
    report_test("GPIO_IN unchanged after write 0xFF", (GPIO_IN & 0xFF) == in_before);

    /* ------------------------------------------------------------------
     * SUBTEST 6: Output gating (DIR & OUT)
     *   Hardware: gpio_out_o[i] = gpio_dir[i] & gpio_out_reg[i]
     *   We cannot read gpio_out_o directly in firmware, but we can verify
     *   the SW-visible registers are consistent for the TB to check.
     *   Set a known DIR + OUT and print them so the waveform confirms gating.
     * ------------------------------------------------------------------*/
    uart_print("\n[SUBTEST 6] Output gating sanity (DIR & OUT visible registers)...\n");

    GPIO_DIR = 0x0F;   /* lower nibble = outputs */
    GPIO_OUT = 0xFF;   /* all bits set */
    uint32_t dir6 = GPIO_DIR & 0xFF;
    uint32_t out6 = GPIO_OUT & 0xFF;
    uart_print("  DIR="); uart_print_hex(dir6);
    uart_print("  OUT="); uart_print_hex(out6);
    uart_print("  Expected gpio_out_o = 0x0F (DIR & OUT)\n");
    report_test("DIR=0x0F, OUT=0xFF — registers consistent for gating", dir6 == 0x0F && out6 == 0xFF);

    GPIO_DIR = 0xF0;
    GPIO_OUT = 0x0F;
    dir6 = GPIO_DIR & 0xFF;
    out6 = GPIO_OUT & 0xFF;
    uart_print("  DIR="); uart_print_hex(dir6);
    uart_print("  OUT="); uart_print_hex(out6);
    uart_print("  Expected gpio_out_o = 0x00 (no overlap)\n");
    report_test("DIR=0xF0, OUT=0x0F — registers consistent (output = 0)", dir6 == 0xF0 && out6 == 0x0F);

    /* ------------------------------------------------------------------
     * SUBTEST 7: SLVERR safety (unmapped offset)
     *   Offset 0x00C is unmapped (next valid address after 0x008).
     *   The AXI4-Lite bridge returns SLVERR; the read should return 0
     *   and the CPU must continue executing.
     * ------------------------------------------------------------------*/
    uart_print("\n[SUBTEST 7] Unmapped register access (SLVERR safety)...\n");

    volatile uint32_t *unmapped = (volatile uint32_t *)(GPIO_BASE + 0x00C);
    uint32_t slverr_val = *unmapped;
    uart_print("  Read from GPIO+0x00C: "); uart_print_hex(slverr_val); uart_print("\n");

    report_test("CPU survived SLVERR on unmapped GPIO offset", 1);
    report_test("Unmapped GPIO register returns 0 (safe default)", slverr_val == 0);

    /* Confirm GPIO registers still functional after the SLVERR */
    GPIO_DIR = 0x55;
    report_test("GPIO_DIR still writable after SLVERR access", (GPIO_DIR & 0xFF) == 0x55);

    /* ------------------------------------------------------------------
     * Teardown — leave GPIO in a safe state (all inputs, output = 0)
     * ------------------------------------------------------------------*/
    GPIO_DIR = 0x00;
    GPIO_OUT = 0x00;

    test_summary();
    return 0;
}
