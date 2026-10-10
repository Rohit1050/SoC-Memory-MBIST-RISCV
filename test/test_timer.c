#include "test_common.h"

int main(void) {
    test_header("TEST SUITE: System Timer");

    uart_print("[SUBTEST 1] Verifying reload register...\n");
    TMR_RELOAD = 100000;
    uint32_t rl = TMR_RELOAD;
    report_test("TMR_RELOAD write/readback (100000)", rl == 100000);

    uart_print("\n[SUBTEST 2] Verifying countdown...\n");
    TMR_EN = 1;
    uint32_t en = TMR_EN;
    delay(5);
    uint32_t c1 = TMR_COUNT;
    delay(50);
    uint32_t c2 = TMR_COUNT;
    TMR_EN = 0;
    uart_print("  Count c1: "); uart_print_hex(c1);
    uart_print(", c2: ");       uart_print_hex(c2);
    uart_print("\n");
    report_test("TMR_EN write/readback (1)", (en & 1) == 1);
    report_test("TMR_COUNT decrementing while enabled", c2 < c1);

    uart_print("\n[SUBTEST 3] Verifying countdown halts when disabled...\n");
    uint32_t h1 = TMR_COUNT;
    delay(50);
    uint32_t h2 = TMR_COUNT;
    report_test("TMR_COUNT holds while TMR_EN = 0", h1 == h2);

    test_summary();
    return 0;
}
