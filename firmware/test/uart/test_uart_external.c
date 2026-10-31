/* =============================================================================
 * Test File   : firmware/test/uart/test_uart_external.c
 * Scope       : External to SoC — UART serial pin (uart_tx_o)
 * Testmap IDs : UART_LCR_PARITY, UART_TX_THRE_POLL, UART_TEMT_DRAIN
 *
 * These tests exercise the UART TX serial output pin (uart_tx_o) which
 * crosses the SoC boundary. Verification is done by the UART VIP monitor
 * in the testbench sniffing the serial bitstream on uart_tx_o.
 *
 * The firmware side:
 *   - Configures LCR for the required parity mode
 *   - Writes data and polls LSR correctly
 *   - Waits for TEMT before declaring drain complete
 *
 * The VIP monitor side:
 *   - Decodes the serial bitstream at the configured baud rate
 *   - Checks parity bit correctness on each frame
 *   - Verifies every byte appears on uart_tx_o without loss
 *   - Monitors TEMT assertion timing after last serial bit
 * =============================================================================*/

#include "test_common.h"

/* Baud divisor for simulation — set low for fast simulation */
#define BAUD_DIV_SIM   4

/* -----------------------------------------------------------------------
 * wait_thre() — poll LSR[5] (THRE) until TX holding register is empty
 * Returns 1 if THRE seen within timeout, 0 if timed out
 * -----------------------------------------------------------------------*/
static int wait_thre(void) {
    uint32_t n = POLL_TIMEOUT;
    while (!((UART_LSR & UART_LSR_THRE)) && --n);
    return n != 0;
}

/* -----------------------------------------------------------------------
 * wait_temt() — poll LSR[6] (TEMT) until both TX FIFO and shift register
 * are fully drained (last serial bit has left the pin)
 * Returns 1 if TEMT seen within timeout, 0 if timed out
 * -----------------------------------------------------------------------*/
static int wait_temt(void) {
    uint32_t n = POLL_TIMEOUT;
    while (!((UART_LSR & UART_LSR_TEMT)) && --n);
    return n != 0;
}

/* -----------------------------------------------------------------------
 * uart_send_byte() — wait for THRE then write one byte to THR
 * -----------------------------------------------------------------------*/
static int uart_send_byte(uint8_t data) {
    if (!wait_thre()) return 0;
    UART_THR = (uint32_t)data;
    return 1;
}

/* =============================================================================
 * Main
 * =============================================================================*/
int main(void) {
    test_header("TEST SUITE: UART External Signal Tests (uart_tx_o pin)");

    /* ------------------------------------------------------------------
     * Common setup: configure baud divisor for simulation speed
     * ------------------------------------------------------------------*/
    UART_LCR  = 0x80;               /* DLAB=1 to access baud divisor */
    UART_BDIV = BAUD_DIV_SIM;
    UART_LCR  = 0x03;               /* DLAB=0, 8N1 default */
    UART_IER  = 0x00;               /* disable all interrupts */

    /* ------------------------------------------------------------------
     * TESTMAP: UART_LCR_PARITY
     * Verify parity bits are encoded correctly on uart_tx_o serial output.
     * The VIP monitor checks each frame for correct parity bit value.
     *
     * 8O1 — LCR = 0x0B (8 data bits, odd parity, 1 stop bit)
     * 8E1 — LCR = 0x1B (8 data bits, even parity, 1 stop bit)
     * ------------------------------------------------------------------*/
    uart_print("[TEST] UART_LCR_PARITY — parity encoding on uart_tx_o\n");

    /* --- 8O1 (odd parity) --- */
    UART_LCR = 0x80;                /* DLAB=1 */
    UART_BDIV = BAUD_DIV_SIM;
    UART_LCR = 0x0B;                /* 8O1: WLS=11(8-bit), PEN=1, EPS=0(odd), DLAB=0 */
    report_test("LCR 0x0B write/readback (8O1)", (UART_LCR & 0xFF) == 0x0B);

    /* Send test pattern — VIP checks odd parity on each frame */
    uart_send_byte(0x55);           /* 0101_0101 — 4 ones, odd parity bit = 1 */
    uart_send_byte(0xAA);           /* 1010_1010 — 4 ones, odd parity bit = 1 */
    uart_send_byte(0x01);           /* 0000_0001 — 1 one,  odd parity bit = 0 */
    int temt_8o1 = wait_temt();
    report_test("UART_LCR_PARITY: 8O1 TX drained (TEMT seen)", temt_8o1);

    /* --- 8E1 (even parity) --- */
    UART_LCR = 0x80;
    UART_BDIV = BAUD_DIV_SIM;
    UART_LCR = 0x1B;                /* 8E1: WLS=11(8-bit), PEN=1, EPS=1(even), DLAB=0 */
    report_test("LCR 0x1B write/readback (8E1)", (UART_LCR & 0xFF) == 0x1B);

    uart_send_byte(0x55);           /* 4 ones, even parity bit = 0 */
    uart_send_byte(0xAA);           /* 4 ones, even parity bit = 0 */
    uart_send_byte(0x01);           /* 1 one,  even parity bit = 1 */
    int temt_8e1 = wait_temt();
    report_test("UART_LCR_PARITY: 8E1 TX drained (TEMT seen)", temt_8e1);

    /* Restore 8N1 for remaining tests */
    UART_LCR = 0x80;
    UART_BDIV = BAUD_DIV_SIM;
    UART_LCR = 0x03;                /* 8N1 */

    /* ------------------------------------------------------------------
     * TESTMAP: UART_TX_THRE_POLL
     * Firmware writes THR only when LSR[5]=1 (THRE).
     * Sends A–Z (26 bytes) with explicit THRE poll before each byte.
     * VIP monitor verifies every byte appears on uart_tx_o in order.
     * ------------------------------------------------------------------*/
    uart_print("\n[TEST] UART_TX_THRE_POLL — send A-Z with THRE polling\n");

    int thre_ok = 1;
    for (char c = 'A'; c <= 'Z'; c++) {
        if (!uart_send_byte((uint8_t)c)) {
            thre_ok = 0;
            break;
        }
    }
    report_test("UART_TX_THRE_POLL: THRE seen before every byte (A-Z)", thre_ok);

    /* Wait for all 26 bytes to drain off the serial pin */
    int temt_az = wait_temt();
    report_test("UART_TX_THRE_POLL: TEMT asserted after A-Z drain", temt_az);

    /* ------------------------------------------------------------------
     * TESTMAP: UART_TEMT_DRAIN
     * LSR[6] TEMT must assert only after both TX FIFO and TX shift
     * register are completely drained — i.e. last bit has left uart_tx_o.
     *
     * Method: burst-write 3 lines (fits within 16-entry TX FIFO),
     * then call wait_temt() and verify it asserts before timeout.
     * VIP monitors TEMT assertion relative to the last serial bit edge.
     * ------------------------------------------------------------------*/
    uart_print("\n[TEST] UART_TEMT_DRAIN — TEMT after TX FIFO + shift register drain\n");

    /* Burst: write all bytes without re-checking THRE (FIFO absorbs them) */
    const char *line1 = "MBIST_SCAN_PASS\r\n";
    const char *line2 = "ECC_OK\r\n";
    const char *line3 = "WDT_ALIVE\r\n";

    /* Fill TX FIFO — each line is short enough to fit without stalling */
    for (const char *p = line1; *p; p++) UART_THR = (uint32_t)*p;
    for (const char *p = line2; *p; p++) UART_THR = (uint32_t)*p;
    for (const char *p = line3; *p; p++) UART_THR = (uint32_t)*p;

    /* Now poll TEMT — must not assert until the last bit leaves the pin */
    int temt_burst = wait_temt();
    report_test("UART_TEMT_DRAIN: TEMT asserted after 3-line burst drain", temt_burst);

    /* Verify LSR[6] is actually set now */
    uint32_t lsr_final = UART_LSR;
    report_test("UART_TEMT_DRAIN: LSR[6] TEMT = 1 after drain",
                (lsr_final & UART_LSR_TEMT) != 0);
    report_test("UART_TEMT_DRAIN: LSR[5] THRE = 1 after drain",
                (lsr_final & UART_LSR_THRE) != 0);

    /* ------------------------------------------------------------------
     * Final summary
     * ------------------------------------------------------------------*/
    test_summary();
    return 0;
}
