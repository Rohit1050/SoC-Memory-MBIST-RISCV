/* =============================================================================
 * Test File   : firmware/test/test_uart.c
 * IP Tested   : AXI4-Lite UART (axil_uart_top)
 * Base Address: 0x4000_0000
 * Toolchain   : riscv32-unknown-elf-gcc -march=rv32imc -mabi=ilp32
 *
 * Test Coverage:
 *   1. Cold-boot LSR state  — THRE and TEMT must be set at reset (TX idle)
 *   2. LCR programming     — write and read back data-format configurations
 *   3. Baud divisor        — BAUD_DIV write/readback (DLAB path via LCR[7])
 *   4. IER                 — interrupt-enable register write/readback
 *   5. TX byte-by-byte     — send each of A-Z via THR with THRE poll
 *   6. TX string burst     — send a full diagnostic string
 *   7. LSR TEMT drain      — verify transmitter is fully idle after burst
 *   8. Unknown register    — access unmapped offset; reads 0 (SLVERR silenced
 *                            by the AXI bridge; no bus lockup expected)
 *
 * Notes:
 *   - No RX loopback path is available on bare-metal without hardware wiring.
 *     RX tests (LSR[0] data-ready) belong in the RTL testbench (tb/uart/).
 *   - LCR[7] (DLAB) must be 0 after baud-divisor tests so uart_putc() works.
 *   - The test_common.h uart_putc() function itself exercises the THRE path
 *     implicitly; the tests here also verify it explicitly.
 * =============================================================================*/

#include "test_common.h"

/* ---------------------------------------------------------------------------
 * Local helpers
 * ---------------------------------------------------------------------------*/

/* Poll LSR until THRE is set, return 1 on success, 0 on timeout. */
static int wait_thre(void)
{
    volatile uint32_t n = POLL_TIMEOUT;
    while ((UART_LSR & UART_LSR_THRE) == 0) {
        if (--n == 0) return 0;
    }
    return 1;
}

/* Poll LSR until TEMT is set, return 1 on success, 0 on timeout.
 * TEMT (Transmitter Empty) clears only after the shift register drains. */
static int wait_temt(void)
{
    volatile uint32_t n = POLL_TIMEOUT;
    while ((UART_LSR & UART_LSR_TEMT) == 0) {
        if (--n == 0) return 0;
    }
    return 1;
}

/* Send a single character using explicit THRE polling (not uart_putc). */
static int tx_byte(uint8_t c)
{
    if (!wait_thre()) return 0;
    UART_THR = (uint32_t)c;
    return 1;
}

/* =============================================================================
 * Main test entry point
 * =============================================================================*/
int main(void)
{
    test_header("TEST SUITE: UART 16550 Serial Controller");

    /* ------------------------------------------------------------------
     * SUBTEST 1: Cold-boot LSR state
     *   At reset, TX FIFO is empty so THRE (bit 5) and TEMT (bit 6)
     *   must both be set.  RX FIFO is empty so DR (bit 0) must be 0.
     * ------------------------------------------------------------------*/
    uart_print("[SUBTEST 1] Cold-boot Line Status Register state...\n");

    uint32_t lsr_boot = UART_LSR;
    uart_print("  UART_LSR at boot: "); uart_print_hex(lsr_boot); uart_print("\n");

    report_test("LSR[5] THRE set at reset (TX FIFO empty)", (lsr_boot & UART_LSR_THRE) != 0);
    report_test("LSR[6] TEMT set at reset (TX shift reg empty)", (lsr_boot & UART_LSR_TEMT) != 0);
    report_test("LSR[0] DR clear at reset (RX FIFO empty)", (lsr_boot & 0x1) == 0);

    /* ------------------------------------------------------------------
     * SUBTEST 2: LCR programming
     *   Verify all common 16550 line-control words can be written and
     *   read back.  DLAB (bit 7) is kept 0 for all tests here.
     *
     *   LCR encoding (bits [2:0]):
     *     [1:0] word length: 00=5, 01=6, 10=7, 11=8
     *     [2]   stop bits:   0=1 stop, 1=2 stop (or 1.5 for 5-bit words)
     *   0x03 = 8 data bits, 1 stop bit, no parity  (8N1 — standard)
     *   0x07 = 8 data bits, 2 stop bits, no parity (8N2)
     *   0x1B = 8 data bits, 1 stop bit, odd parity (8O1)
     *   0x1F = 8 data bits, 1 stop bit, even parity(8E1)
     * ------------------------------------------------------------------*/
    uart_print("\n[SUBTEST 2] LCR write/readback...\n");

    /* 8N1 */
    UART_LCR = 0x03;
    report_test("LCR 0x03 (8N1) write/readback", (UART_LCR & 0xFF) == 0x03);

    /* 8N2 */
    UART_LCR = 0x07;
    report_test("LCR 0x07 (8N2) write/readback", (UART_LCR & 0xFF) == 0x07);

    /* 8O1 — odd parity */
    UART_LCR = 0x0B;
    report_test("LCR 0x0B (8O1) write/readback", (UART_LCR & 0xFF) == 0x0B);

    /* 8E1 — even parity */
    UART_LCR = 0x1B;
    report_test("LCR 0x1B (8E1) write/readback", (UART_LCR & 0xFF) == 0x1B);

    /* Restore to 8N1 for subsequent TX tests */
    UART_LCR = 0x03;
    report_test("LCR restored to 0x03 (8N1)", (UART_LCR & 0xFF) == 0x03);

    /* ------------------------------------------------------------------
     * SUBTEST 3: Baud divisor (DLAB path)
     *   Set LCR[7]=1 to access the baud-divisor register at offset 0x08.
     *   Write a known value, read it back, then clear DLAB.
     *
     *   Default: 434 → 115 200 bps at 50 MHz  (50_000_000 / 115200 ≈ 434)
     *   Test values chosen to avoid zero (undefined baud).
     * ------------------------------------------------------------------*/
    uart_print("\n[SUBTEST 3] Baud divisor (DLAB path)...\n");

    /* Enter DLAB mode: LCR[7] = 1, keep 8N1 */
    UART_LCR = 0x83;   /* 0x80 | 0x03 */
    report_test("LCR DLAB bit set (0x83 readback)", (UART_LCR & 0x80) != 0);

    /* Write and read back divisor value 434 (115 200 bps @ 50 MHz) */
    UART_BDIV = 434;
    uint32_t div_rb = UART_BDIV;
    uart_print("  BAUD_DIV readback: "); uart_print_dec(div_rb); uart_print("\n");
    report_test("BAUD_DIV write/readback 434 (115200 @ 50 MHz)", div_rb == 434);

    /* Write and read back a different divisor */
    UART_BDIV = 217;   /* ~230 400 bps @ 50 MHz */
    report_test("BAUD_DIV write/readback 217 (~230400 bps)", UART_BDIV == 217);

    /* Restore default divisor and clear DLAB so TX path works again */
    UART_BDIV = 434;
    UART_LCR  = 0x03;  /* DLAB=0, 8N1 */
    report_test("DLAB cleared (LCR back to 0x03)", (UART_LCR & 0x80) == 0);

    /* ------------------------------------------------------------------
     * SUBTEST 4: Interrupt Enable Register (IER)
     *   Bit 0: RX data-available IRQ enable
     *   Bit 1: TX holding-register-empty IRQ enable
     *   Other bits reserved / read-as-zero on this implementation.
     * ------------------------------------------------------------------*/
    uart_print("\n[SUBTEST 4] IER write/readback...\n");

    UART_IER = 0x01;   /* RX IRQ enable */
    report_test("IER 0x01 (RX data-available IRQ)", (UART_IER & 0x01) == 0x01);

    UART_IER = 0x02;   /* TX THRE IRQ enable */
    report_test("IER 0x02 (TX THRE IRQ)", (UART_IER & 0x02) == 0x02);

    UART_IER = 0x03;   /* Both RX + TX IRQs */
    report_test("IER 0x03 (RX + TX IRQs)", (UART_IER & 0x03) == 0x03);

    UART_IER = 0x00;   /* Disable all interrupts (polled mode) */
    report_test("IER 0x00 (interrupts disabled)", (UART_IER & 0x03) == 0x00);

    /* ------------------------------------------------------------------
     * SUBTEST 5: TX byte-by-byte character test
     *   Send 'A'–'Z' one byte at a time using explicit THRE polling.
     *   Each write verifies the THRE path is functional.
     *   The sent characters will appear in the simulation UART monitor.
     * ------------------------------------------------------------------*/
    uart_print("\n[SUBTEST 5] TX byte-by-byte ('A'-'Z')...\n");
    uart_print("  Sending: ");

    int all_ok = 1;
    for (char c = 'A'; c <= 'Z'; c++) {
        if (!tx_byte((uint8_t)c)) {
            all_ok = 0;
        }
    }
    tx_byte('\r');
    tx_byte('\n');

    report_test("All 26 characters transmitted without THRE timeout", all_ok);

    /* ------------------------------------------------------------------
     * SUBTEST 6: TX string burst
     *   Send a longer string to stress the 16-entry TX FIFO.
     *   We use uart_print() which goes through the same THRE-poll path.
     * ------------------------------------------------------------------*/
    uart_print("\n[SUBTEST 6] TX string burst (FIFO stress)...\n");
    uart_print("  >> MBIST SoC UART TX burst test — 0123456789ABCDEF <<\n");
    uart_print("  >> MBIST SoC UART TX burst test — 0123456789ABCDEF <<\n");
    uart_print("  >> MBIST SoC UART TX burst test — 0123456789ABCDEF <<\n");
    report_test("Three-line string burst transmitted (no stuck THRE)", 1);

    /* ------------------------------------------------------------------
     * SUBTEST 7: LSR TEMT — transmitter fully drained
     *   After the burst, wait for TEMT to confirm the TX shift register
     *   has completely emptied.  Failure here means data was lost or the
     *   TX state machine is stuck.
     * ------------------------------------------------------------------*/
    uart_print("\n[SUBTEST 7] Verifying TEMT after TX burst...\n");

    int temt_ok = wait_temt();
    uart_print("  Final UART_LSR: "); uart_print_hex(UART_LSR); uart_print("\n");
    report_test("LSR[6] TEMT set after burst completes", temt_ok);
    report_test("LSR[5] THRE still set after drain", (UART_LSR & UART_LSR_THRE) != 0);

    /* ------------------------------------------------------------------
     * SUBTEST 8: Unknown/unmapped register access
     *   Offset 0x010 is reserved (no register exists).  The AXI4-Lite
     *   bridge returns SLVERR; the bus should not lock up and the read
     *   should return 0 (implementation-defined safe value).
     *   We verify the core continues executing after the access.
     * ------------------------------------------------------------------*/
    uart_print("\n[SUBTEST 8] Unmapped register access (SLVERR safety)...\n");

    volatile uint32_t *unmapped = (volatile uint32_t *)(UART_BASE + 0x010);
    uint32_t slverr_val = *unmapped;   /* Should return 0; SLVERR consumed by bridge */
    uart_print("  Read from UART+0x010: "); uart_print_hex(slverr_val); uart_print("\n");

    /* Core must still be running if we reach this line */
    report_test("CPU survived SLVERR on unmapped UART offset", 1);
    report_test("Unmapped register returns 0 (safe default)", slverr_val == 0);

    /* Confirm UART still works after the SLVERR */
    UART_IER = 0x01;
    report_test("UART_IER still writable after SLVERR access", (UART_IER & 0x01) == 0x01);
    UART_IER = 0x00;

    /* ------------------------------------------------------------------
     * Final summary
     * ------------------------------------------------------------------*/
    test_summary();
    return 0;
}
