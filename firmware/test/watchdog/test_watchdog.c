/* =============================================================================
 * Test File   : firmware/test/test_watchdog.c
 * IP Tested   : AXI4-Lite Watchdog Timer (axil_wdt_top + wdt_core)
 * Base Address: 0x4000_5000
 * Toolchain   : riscv32-unknown-elf-gcc -march=rv32imc -mabi=ilp32
 *
 * Register Map (from axil_wdt_defines.vh + wdt_core.v):
 *   0x000  WDG_ENABLE     (R/W,   1-bit)  : [0] countdown enable
 *   0x004  WDG_LOAD       (R/W,  32-bit)  : reload value
 *   0x008  WDG_KICK       (W,    32-bit)  : any write reloads counter
 *   0x00C  WDG_COUNT      (RO,   32-bit)  : current countdown value
 *   0x010  WDG_STATUS     (R/W1C, 1-bit)  : [0] timeout_occurred (sticky, POR domain)
 *   0x014  WDG_PRETIMEOUT (R/W,  32-bit)  : pre-timeout threshold (early IRQ)
 *
 * Hardware behaviour (from wdt_core.v):
 *   - WDG_ENABLE=1  : counter decrements each clock cycle.
 *   - WDG_ENABLE=0  : counter holds at current value (does NOT reset to load).
 *   - WDG_KICK write: instantly reloads WDG_COUNT ← WDG_LOAD.
 *   - On expiry (count → 0): timeout_o asserts, wdt_reset_n forces a system reset.
 *   - pretimeout_irq_o asserts when WDG_COUNT ≤ WDG_PRETIMEOUT.
 *   - WDG_STATUS[0] (timeout_occurred) is a STICKY flag in the POR clock domain
 *     — survives warm resets so firmware can inspect it on reboot.
 *   - WDG_STATUS is cleared by writing 1 (W1C).
 *
 * Test Coverage:
 *   1. Reset state         — WDG_ENABLE=0, no timeout at boot
 *   2. WDG_LOAD R/W        — multiple values including boundary cases
 *   3. Enable + countdown  — count decrements while enabled
 *   4. WDG_KICK reloads    — kick restores WDG_COUNT to WDG_LOAD
 *   5. Hold on disable     — count freezes when WDG_ENABLE=0
 *   6. WDG_STATUS W1C      — timeout flag cleared by writing 1
 *   7. Pre-timeout threshold — WDG_PRETIMEOUT R/W, threshold ordering
 *   8. No timeout during test — WDG_STATUS[0] remains clear throughout
 *   9. SLVERR safety       — unmapped offset returns 0, CPU survives
 *
 * IMPORTANT: This test must NOT let the counter reach zero — that would
 * trigger a system reset and terminate the test.  All subtests that enable
 * the WDT either kick it promptly or disable it well before expiry.
 * WDG_LOAD is set to a large value (0x00FFFFFF) to give ample margin.
 * =============================================================================*/

#include "test_common.h"

/* Large reload gives ample headroom — a 50 MHz clock takes ~335 ms to expire */
#define WDT_SAFE_LOAD  0x00FFFFFFu

/* =============================================================================
 * Main test entry point
 * =============================================================================*/
int main(void)
{
    test_header("TEST SUITE: Watchdog Timer");

    /* Safety: ensure WDT starts disabled and is kicked immediately */
    WDG_ENABLE = 0;
    WDG_LOAD   = WDT_SAFE_LOAD;
    WDG_KICK   = 1;    /* pre-load counter to WDT_SAFE_LOAD */

    /* ------------------------------------------------------------------
     * SUBTEST 1: Reset state
     *   WDG_ENABLE must be 0 at cold boot (WDT not running).
     *   WDG_STATUS[0] may be set if a previous test caused a timeout,
     *   so we clear it and verify it goes to 0.
     * ------------------------------------------------------------------*/
    uart_print("[SUBTEST 1] Reset state and boot-time status...\n");

    uint32_t en_boot  = WDG_ENABLE & 0x1;
    uint32_t st_boot  = WDG_STATUS & 0x1;
    uart_print("  WDG_ENABLE at boot: "); uart_print_hex(en_boot); uart_print("\n");
    uart_print("  WDG_STATUS at boot: "); uart_print_hex(st_boot); uart_print("\n");

    report_test("WDG_ENABLE = 0 at reset (WDT not running)", en_boot == 0);

    /* Clear any residual timeout flag from a prior run */
    WDG_STATUS = 1;
    report_test("WDG_STATUS cleared by writing 1 (W1C)", (WDG_STATUS & 0x1) == 0);

    /* ------------------------------------------------------------------
     * SUBTEST 2: WDG_LOAD write/readback
     *   Verify reload register accepts all bit patterns.
     * ------------------------------------------------------------------*/
    uart_print("\n[SUBTEST 2] WDG_LOAD write/readback...\n");

    WDG_LOAD = 0x00001000;
    report_test("WDG_LOAD 0x00001000 write/readback", WDG_LOAD == 0x00001000);

    WDG_LOAD = 0xDEADBEEF;
    report_test("WDG_LOAD 0xDEADBEEF write/readback", WDG_LOAD == 0xDEADBEEF);

    WDG_LOAD = 0xFFFFFFFF;
    report_test("WDG_LOAD 0xFFFFFFFF (max) write/readback", WDG_LOAD == 0xFFFFFFFF);

    WDG_LOAD = 1;
    report_test("WDG_LOAD 1 (minimum non-zero) write/readback", WDG_LOAD == 1);

    /* Restore safe reload before enabling */
    WDG_LOAD = WDT_SAFE_LOAD;

    /* ------------------------------------------------------------------
     * SUBTEST 3: Enable + countdown
     *   Enable with WDT_SAFE_LOAD.  Read count twice with a short delay;
     *   second reading must be strictly less than first.
     *   Disable immediately after sampling.
     * ------------------------------------------------------------------*/
    uart_print("\n[SUBTEST 3] Enable and countdown...\n");

    WDG_LOAD   = WDT_SAFE_LOAD;
    WDG_ENABLE = 0;       /* ensure halted */
    WDG_KICK   = 1;       /* pre-load counter */
    WDG_ENABLE = 1;       /* start countdown */

    uint32_t en_rb = WDG_ENABLE & 0x1;
    delay(5);
    uint32_t c1 = WDG_COUNT;
    delay(100);
    uint32_t c2 = WDG_COUNT;
    WDG_ENABLE = 0;       /* halt — do not let it expire */

    uart_print("  WDG_ENABLE readback: "); uart_print_hex(en_rb); uart_print("\n");
    uart_print("  c1: "); uart_print_hex(c1);
    uart_print("  c2: "); uart_print_hex(c2); uart_print("\n");

    report_test("WDG_ENABLE write/readback (1)", en_rb == 1);
    report_test("WDG_COUNT decrementing while WDG_ENABLE=1", c2 < c1);
    /* Sanity: counter must not have reached zero (that would reset the system) */
    report_test("WDG_COUNT > 0 (no spurious timeout)", c2 > 0);

    /* ------------------------------------------------------------------
     * SUBTEST 4: WDG_KICK reloads WDG_COUNT
     *   Enable, let the counter drop, kick it, read again.
     *   The count after kick must be WDT_SAFE_LOAD (or very close —
     *   exactly WDT_SAFE_LOAD if we sample immediately).
     * ------------------------------------------------------------------*/
    uart_print("\n[SUBTEST 4] WDG_KICK reloads WDG_COUNT...\n");

    WDG_LOAD   = WDT_SAFE_LOAD;
    WDG_ENABLE = 0;
    WDG_KICK   = 1;       /* pre-load */
    WDG_ENABLE = 1;

    delay(200);           /* let count drop noticeably */
    uint32_t before_kick = WDG_COUNT;
    WDG_KICK = 1;         /* service the watchdog */
    uint32_t after_kick  = WDG_COUNT;
    WDG_ENABLE = 0;

    uart_print("  Count before kick: "); uart_print_hex(before_kick); uart_print("\n");
    uart_print("  Count after kick:  "); uart_print_hex(after_kick);  uart_print("\n");

    report_test("WDG_COUNT decremented before kick", before_kick < WDT_SAFE_LOAD);
    report_test("WDG_KICK reloads WDG_COUNT to WDG_LOAD", after_kick == WDT_SAFE_LOAD);
    report_test("After-kick count > before-kick count", after_kick > before_kick);

    /* ------------------------------------------------------------------
     * SUBTEST 5: Hold on disable
     *   With WDG_ENABLE=0, count must not change between two reads.
     *   (RTL spec: counter holds, does NOT reset to load value.)
     * ------------------------------------------------------------------*/
    uart_print("\n[SUBTEST 5] Hold on disable (WDG_ENABLE=0)...\n");

    /* WDG_ENABLE is already 0 from Subtest 4 */
    uint32_t h1 = WDG_COUNT;
    delay(100);
    uint32_t h2 = WDG_COUNT;
    uart_print("  h1: "); uart_print_hex(h1);
    uart_print("  h2: "); uart_print_hex(h2); uart_print("\n");
    report_test("WDG_COUNT frozen while WDG_ENABLE=0", h1 == h2);

    /* Verify count is NOT reset to WDG_LOAD (it holds at last value) */
    report_test("WDG_COUNT holds (not reset to WDG_LOAD) while disabled", h1 != WDT_SAFE_LOAD);

    /* ------------------------------------------------------------------
     * SUBTEST 6: WDG_STATUS W1C (sticky timeout flag)
     *   WDG_STATUS[0] is in the POR domain and sticky.  We cannot safely
     *   trigger a real timeout (it would reset the chip), but we can:
     *     a) Verify the flag starts clear after being cleared in Subtest 1.
     *     b) Verify W1C clears it (already shown in Subtest 1).
     *     c) Write 0 — must NOT clear the flag (W1C means only 1 clears).
     * ------------------------------------------------------------------*/
    uart_print("\n[SUBTEST 6] WDG_STATUS W1C semantics...\n");

    /* Status must still be 0 from the clear in Subtest 1 */
    report_test("WDG_STATUS[0] = 0 (no timeout has occurred)", (WDG_STATUS & 0x1) == 0);

    /* Writing 0 must not affect the register (W1C — only 1 clears) */
    WDG_STATUS = 0x00;   /* should have no effect */
    report_test("Writing 0 to WDG_STATUS has no effect", (WDG_STATUS & 0x1) == 0);

    /* ------------------------------------------------------------------
     * SUBTEST 7: WDG_PRETIMEOUT register R/W
     *   The pre-timeout threshold triggers an early-warning IRQ to the PIC
     *   when WDG_COUNT ≤ WDG_PRETIMEOUT.
     *   Verify:
     *     a) R/W of several threshold values.
     *     b) Threshold must be < WDG_LOAD to be meaningful.
     * ------------------------------------------------------------------*/
    uart_print("\n[SUBTEST 7] WDG_PRETIMEOUT register...\n");

    WDG_PRETIMEOUT = 0x00001000;
    report_test("WDG_PRETIMEOUT 0x1000 write/readback", WDG_PRETIMEOUT == 0x00001000);

    WDG_PRETIMEOUT = 0x00010000;
    report_test("WDG_PRETIMEOUT 0x10000 write/readback", WDG_PRETIMEOUT == 0x00010000);

    WDG_PRETIMEOUT = 0;
    report_test("WDG_PRETIMEOUT 0 (disabled) write/readback", WDG_PRETIMEOUT == 0);

    /* Threshold ordering sanity: pretimeout must be less than load for IRQ to fire */
    uint32_t thresh = WDT_SAFE_LOAD / 4;   /* 25 % of load */
    WDG_PRETIMEOUT = thresh;
    WDG_LOAD       = WDT_SAFE_LOAD;
    report_test("WDG_PRETIMEOUT < WDG_LOAD (correct threshold ordering)",
                WDG_PRETIMEOUT < WDG_LOAD);

    WDG_PRETIMEOUT = 0;  /* disable pre-timeout IRQ for remainder of test */

    /* ------------------------------------------------------------------
     * SUBTEST 8: No timeout during the entire test run
     *   At this point all enables have been cleared.  Confirm the status
     *   flag is still 0 — verifies no accidental expiry occurred above.
     * ------------------------------------------------------------------*/
    uart_print("\n[SUBTEST 8] Confirming no timeout occurred during test...\n");

    /* Final kick to ensure counter stays loaded before we check status */
    WDG_ENABLE = 0;
    WDG_KICK   = 1;
    uint32_t final_st = WDG_STATUS & 0x1;
    uart_print("  WDG_STATUS final: "); uart_print_hex(final_st); uart_print("\n");
    uart_print("  WDG_COUNT  final: "); uart_print_hex(WDG_COUNT); uart_print("\n");

    report_test("WDG_STATUS[0] = 0 throughout all tests (no timeout)", final_st == 0);
    report_test("WDG_COUNT = WDT_SAFE_LOAD after final kick", WDG_COUNT == WDT_SAFE_LOAD);

    /* ------------------------------------------------------------------
     * SUBTEST 9: SLVERR safety (unmapped offset)
     *   Offset 0x018 is unmapped (no register after 0x014).
     *   SLVERR is returned by the AXI bridge; read must return 0; CPU survives.
     * ------------------------------------------------------------------*/
    uart_print("\n[SUBTEST 9] Unmapped register access (SLVERR safety)...\n");

    volatile uint32_t *unmapped = (volatile uint32_t *)(WDG_BASE + 0x018);
    uint32_t slverr_val = *unmapped;
    uart_print("  Read from WDG+0x018: "); uart_print_hex(slverr_val); uart_print("\n");

    report_test("CPU survived SLVERR on unmapped WDT offset", 1);
    report_test("Unmapped WDT register returns 0 (safe default)", slverr_val == 0);

    /* Confirm WDT registers still functional after the SLVERR */
    WDG_LOAD = 0x12345678;
    report_test("WDG_LOAD still writable after SLVERR access", WDG_LOAD == 0x12345678);

    /* Leave WDT in safe state */
    WDG_ENABLE     = 0;
    WDG_LOAD       = WDT_SAFE_LOAD;
    WDG_PRETIMEOUT = 0;
    WDG_KICK       = 1;

    /* ------------------------------------------------------------------
     * Final summary
     * ------------------------------------------------------------------*/
    test_summary();
    return 0;
}
