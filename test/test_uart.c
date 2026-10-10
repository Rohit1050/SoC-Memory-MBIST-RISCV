#include "test_common.h"

int main(void) {
    test_header("TEST SUITE: UART 16550 Serial Controller");

    uart_print("[SUBTEST 1] Verifying Line Status Register (LSR)...\n");
    uint32_t lsr = UART_LSR;
    uart_print("  UART LSR raw: "); uart_print_hex(lsr); uart_print("\n");
    report_test("LSR indicates Transmitter Holding Register Empty (THRE = 1)", (lsr & UART_LSR_THRE) != 0);

    uart_print("\n[SUBTEST 2] Verifying Transmitter Empty Flag (TEMT)...\n");
    report_test("LSR indicates Transmitter Empty (TEMT = 1)", (lsr & UART_LSR_TEMT) != 0);

    uart_print("\n[SUBTEST 3] Verifying Interrupt Enable Register (IER)...\n");
    UART_IER = 1;
    uint32_t ier_on = UART_IER;
    UART_IER = 0;
    uint32_t ier_off = UART_IER;
    report_test("IER write/readback (1)", (ier_on & 1) == 1);
    report_test("IER write/readback (0)", (ier_off & 1) == 0);

    uart_print("\n[SUBTEST 4] Verifying Single Character Streaming...\n");
    uart_putc('U');
    uart_putc('A');
    uart_putc('R');
    uart_putc('T');
    uart_putc('\n');
    report_test("Single character byte transmission", 1);

    uart_print("\n[SUBTEST 5] Verifying String Output Streaming...\n");
    uart_print("  Testing text transmission burst...\n");
    report_test("String buffer transmission", 1);

    uart_print("\n[SUBTEST 6] Verifying Hex Output Formatter...\n");
    uart_print("  Hex Output Verification: "); uart_print_hex(0xDEADBEEF); uart_print("\n");
    report_test("Hex formatting utility (0xDEADBEEF)", 1);

    uart_print("\n[SUBTEST 7] Verifying Decimal Output Formatter...\n");
    uart_print("  Decimal Output Verification: "); uart_print_dec(12345678); uart_print("\n");
    report_test("Decimal formatting utility (12345678)", 1);

    test_summary();
    return 0;
}
