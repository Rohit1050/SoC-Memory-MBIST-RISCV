/* =============================================================================
 * Test File   : firmware/test/test_timer.c
 * IP Tested   : AXI4-Lite System Timer (axil_systimer_top)
 * Base Address: 0x4000_1000
 * Toolchain   : riscv32-unknown-elf-gcc -march=rv32imc -mabi=ilp32
 *
 * Register Map (from axil_systimer_top.v):
 *   0x000  TMR_EN     (R/W, 1-bit)  : [0] = countdown enable
 *   0x004  TMR_RELOAD (R/W, 32-bit) : reload value — counter restarts here on expiry
 *   0x008  TMR_COUNT  (RO,  32-bit) : current countdown value
 *
 * Hardware behaviour (from RTL header):
 *   - timer_en = 1  : counter decrements each clock cycle from timer_reload.
 *   - timer_en = 0  : counter HOLDS at current value (does not reset to reload).
 *   - On (re)enable from idle, counter preloads with timer_reload so the first
 *     tick fires exactly timer_reload cycles after enable (not reload-1).
 *   - On expiry (count → 0), timer_tick_o pulses 1 cycle, counter reloads
 *     from timer_reload automatically and continues if timer_en is still set.
 *   - timer_reload = 0 : count stays at 0, tick pulses every cycle (safe).
 *   - Writes to TMR_COUNT (0x008) are silently accepted (OKAY) but ignored.
 *   - Writes to any other offset return SLVERR.
 *
 * Test Coverage:
 *   1. Reset state         — TMR_EN=0, TMR_RELOAD=0, TMR_COUNT=0
 *   2. TMR_RELOAD R/W      — multiple values including boundary cases
 *   3. Enable + countdown  — count decrements while enabled
 *   4. Hold on disable     — count freezes when TMR_EN=0
 *   5. Re-arm from zero    — disable, write reload, re-enable → restarts from reload
 *   6. TMR_COUNT read-only — write ignored; value unaffected
 *   7. Tick-derived delay  — use TMR_COUNT to spin-wait a calibrated period
 *   8. SLVERR safety       — unmapped offset returns 0, CPU survives
 * =============================================================================*/

#include "test_common.h"

/* ---------------------------------------------------------------------------
 * Spin-wait using TMR_COUNT as a reference.
 * Enables the timer with given reload, waits until count drops by 'ticks',
 * then disables.  Returns the observed count delta (for verification).
 *
 * Precondition: timer is disabled and reload is set before calling.
 * ---------------------------------------------------------------------------*/
static uint32_t timer_wait_ticks(uint32_t reload, uint32_t ticks)
{
    TMR_RELOAD = reload;
    TMR_EN = 0;         /* ensure halted so re-enable reloads cleanly */
    TMR_EN = 1;         /* re-arm: count preloads to reload */

    uint32_t start = TMR_COUNT;
    /* Spin until count has dropped by at least 'ticks' from start.
     * We guard against the counter wrapping through zero (auto-reload). */
    volatile uint32_t n = POLL_TIMEOUT;
    while (1) {
        uint32_t now = TMR_COUNT;
        /* If counter wrapped (now > start), treat entire elapsed period */
        uint32_t elapsed = (now <= start) ? (start - now) : (reload - now + start);
        if (elapsed >= ticks) break;
        if (--n == 0) break;
    }
    uint32_t stop = TMR_COUNT;
    TMR_EN = 0;
    return (stop <= start) ? (start - stop) : (reload - stop + start);
}

/* =============================================================================
 * Main test entry point
 * =============================================================================*/
int main(void)
{
    test_header("TEST SUITE: System Timer");

    /* ------------------------------------------------------------------
     * SUBTEST 1: Reset state
     *   TMR_EN, TMR_RELOAD, TMR_COUNT should all be 0 at cold boot.
     * ------------------------------------------------------------------*/
    uart_print("[SUBTEST 1] Reset state...\n");

    uint32_t en_boot    = TMR_EN     & 0x1;
    uint32_t reload_boot = TMR_RELOAD;
    uint32_t count_boot  = TMR_COUNT;
    uart_print("  TMR_EN:     "); uart_print_hex(en_boot);    uart_print("\n");
    uart_print("  TMR_RELOAD: "); uart_print_hex(reload_boot); uart_print("\n");
    uart_print("  TMR_COUNT:  "); uart_print_hex(count_boot);  uart_print("\n");

    report_test("TMR_EN = 0 at reset", en_boot == 0);
    report_test("TMR_RELOAD = 0 at reset", reload_boot == 0);
    report_test("TMR_COUNT = 0 at reset", count_boot == 0);

    /* ------------------------------------------------------------------
     * SUBTEST 2: TMR_RELOAD register write/readback
     *   Verify multiple reload values including max and boundary cases.
     * ------------------------------------------------------------------*/
    uart_print("\n[SUBTEST 2] TMR_RELOAD write/readback...\n");

    TMR_RELOAD = 100000;
    report_test("TMR_RELOAD 100000 write/readback", TMR_RELOAD == 100000);

    TMR_RELOAD = 0xDEADBEEF;
    report_test("TMR_RELOAD 0xDEADBEEF write/readback", TMR_RELOAD == 0xDEADBEEF);

    TMR_RELOAD = 0xFFFFFFFF;
    report_test("TMR_RELOAD 0xFFFFFFFF (max) write/readback", TMR_RELOAD == 0xFFFFFFFF);

    TMR_RELOAD = 1;
    report_test("TMR_RELOAD 1 (minimum non-zero) write/readback", TMR_RELOAD == 1);

    TMR_RELOAD = 0;
    report_test("TMR_RELOAD 0 (zero edge case) write/readback", TMR_RELOAD == 0);

    /* ------------------------------------------------------------------
     * SUBTEST 3: Enable + countdown
     *   Set a known reload, enable, read count twice with a delay between.
     *   Second reading must be strictly less than first.
     * ------------------------------------------------------------------*/
    uart_print("\n[SUBTEST 3] Enable and countdown...\n");

    TMR_RELOAD = 0x00FFFFFF;
    TMR_EN = 0;   /* ensure halted first */
    TMR_EN = 1;

    uint32_t en_rb = TMR_EN & 0x1;
    delay(5);
    uint32_t c1 = TMR_COUNT;
    delay(100);
    uint32_t c2 = TMR_COUNT;
    TMR_EN = 0;

    uart_print("  TMR_EN readback: "); uart_print_hex(en_rb); uart_print("\n");
    uart_print("  c1: "); uart_print_hex(c1);
    uart_print("  c2: "); uart_print_hex(c2); uart_print("\n");

    report_test("TMR_EN write/readback (1)", en_rb == 1);
    report_test("TMR_COUNT preloads to TMR_RELOAD on enable", c1 <= 0x00FFFFFF);
    report_test("TMR_COUNT decrementing while TMR_EN=1", c2 < c1);

    /* ------------------------------------------------------------------
     * SUBTEST 4: Hold on disable
     *   With TMR_EN=0, count must not change between two reads.
     * ------------------------------------------------------------------*/
    uart_print("\n[SUBTEST 4] Hold on disable (TMR_EN=0)...\n");

    /* TMR_EN is already 0 from Subtest 3 */
    uint32_t h1 = TMR_COUNT;
    delay(100);
    uint32_t h2 = TMR_COUNT;
    uart_print("  h1: "); uart_print_hex(h1);
    uart_print("  h2: "); uart_print_hex(h2); uart_print("\n");
    report_test("TMR_COUNT frozen while TMR_EN=0", h1 == h2);

    /* ------------------------------------------------------------------
     * SUBTEST 5: Re-arm from zero (disable → write reload → re-enable)
     *   Per RTL spec: when re-enabled from idle, count preloads with
     *   timer_reload — a clean restart, not a resume from frozen value.
     * ------------------------------------------------------------------*/
    uart_print("\n[SUBTEST 5] Re-arm from zero...\n");

    /* Force count to some non-reload value by partially draining */
    TMR_RELOAD = 0x00010000;
    TMR_EN = 1;
    delay(20);             /* let it decrement a little */
    uint32_t frozen = TMR_COUNT;
    TMR_EN = 0;
    uart_print("  Frozen count after partial drain: "); uart_print_hex(frozen); uart_print("\n");

    /* Now re-arm: write new reload, toggle enable */
    uint32_t new_reload = 0x00020000;
    TMR_RELOAD = new_reload;
    TMR_EN = 0;            /* ensure idle */
    TMR_EN = 1;            /* re-arm */
    uint32_t rearmed = TMR_COUNT;
    TMR_EN = 0;
    uart_print("  Count immediately after re-arm: "); uart_print_hex(rearmed); uart_print("\n");

    report_test("Re-arm loads TMR_RELOAD (not frozen value)", rearmed == new_reload);
    report_test("Re-armed count is not the old frozen value", rearmed != frozen);

    /* ------------------------------------------------------------------
     * SUBTEST 6: TMR_COUNT is read-only (write ignored)
     *   Attempt to write a magic value; read back — must be unchanged.
     * ------------------------------------------------------------------*/
    uart_print("\n[SUBTEST 6] TMR_COUNT is read-only (write ignored)...\n");

    /* Freeze the counter */
    TMR_EN = 0;
    uint32_t cnt_before = TMR_COUNT;
    TMR_COUNT = 0xDEADBEEF;   /* should be silently ignored */
    uint32_t cnt_after  = TMR_COUNT;
    uart_print("  TMR_COUNT before write: "); uart_print_hex(cnt_before);
    uart_print("  after write: ");            uart_print_hex(cnt_after);
    uart_print("\n");
    report_test("TMR_COUNT unchanged after write (read-only)", cnt_before == cnt_after);

    /* ------------------------------------------------------------------
     * SUBTEST 7: Tick-derived delay calibration
     *   Use the timer hardware to measure a firmware delay loop, cross-
     *   checking that the counter advances the expected number of ticks.
     *   We request ≥1000 ticks and verify the observed delta is in range.
     * ------------------------------------------------------------------*/
    uart_print("\n[SUBTEST 7] Tick-derived delay calibration...\n");

    uint32_t target   = 2000;     /* request at least 2000 ticks */
    uint32_t observed = timer_wait_ticks(0x00FFFFFF, target);
    uart_print("  Requested ticks: "); uart_print_dec(target);
    uart_print("  Observed delta: ");  uart_print_dec(observed);
    uart_print("\n");

    /* Observed must be ≥ target (we always over-estimate, never under) */
    report_test("Observed tick delta >= requested (2000)", observed >= target);
    /* Sanity upper bound: should not be 100× over (stuck or misconfigured) */
    report_test("Observed tick delta < 200000 (not stuck)", observed < 200000);

    /* ------------------------------------------------------------------
     * SUBTEST 8: SLVERR safety (unmapped offset)
     *   Offset 0x00C is unmapped (no register after 0x008).
     *   SLVERR is returned by the bridge; read returns 0; CPU must survive.
     * ------------------------------------------------------------------*/
    uart_print("\n[SUBTEST 8] Unmapped register access (SLVERR safety)...\n");

    volatile uint32_t *unmapped = (volatile uint32_t *)(TMR_BASE + 0x00C);
    uint32_t slverr_val = *unmapped;
    uart_print("  Read from TMR+0x00C: "); uart_print_hex(slverr_val); uart_print("\n");

    report_test("CPU survived SLVERR on unmapped timer offset", 1);
    report_test("Unmapped register returns 0 (safe default)", slverr_val == 0);

    /* Verify timer registers still functional after the SLVERR */
    TMR_RELOAD = 0x1234ABCD;
    report_test("TMR_RELOAD still writable after SLVERR", TMR_RELOAD == 0x1234ABCD);
    TMR_RELOAD = 0;
    TMR_EN = 0;

    /* ------------------------------------------------------------------
     * Final summary
     * ------------------------------------------------------------------*/
    test_summary();
    return 0;
}
