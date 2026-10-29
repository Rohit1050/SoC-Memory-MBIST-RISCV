#include "test_common.h"

int main(void) {
    test_header("TEST SUITE: Watchdog Timer");

    uart_print("[SUBTEST 1] Verifying configuration registers...\n");
    WDG_LOAD = 100000;
    report_test("WDG_LOAD write/readback (100000)", WDG_LOAD == 100000);
    WDG_PRETIMEOUT = 20000;
    report_test("WDG_PRETIMEOUT write/readback (20000)", WDG_PRETIMEOUT == 20000);
    WDG_PRETIMEOUT = 0;

    uart_print("\n[SUBTEST 2] Verifying post-mortem status flag...\n");
    uint32_t boot_st = WDG_STATUS;
    uart_print("  Boot-time WDG_STATUS: "); uart_print_hex(boot_st); uart_print("\n");
    WDG_STATUS = 1;
    report_test("timeout_occurred cleared by writing 1", (WDG_STATUS & 1) == 0);

    uart_print("\n[SUBTEST 3] Verifying countdown and kick...\n");
    WDG_LOAD = 100000;
    WDG_ENABLE = 1;
    WDG_KICK = 1;
    uint32_t en = WDG_ENABLE;
    uint32_t c1 = WDG_COUNT;
    delay(50);
    uint32_t c2 = WDG_COUNT;
    WDG_KICK = 1;
    uint32_t c3 = WDG_COUNT;
    WDG_ENABLE = 0;
    uart_print("  Count c1: "); uart_print_dec(c1);
    uart_print(", c2: ");       uart_print_dec(c2);
    uart_print(", after kick: "); uart_print_dec(c3);
    uart_print("\n");
    report_test("WDG_ENABLE write/readback (1)", (en & 1) == 1);
    report_test("WDG_COUNT decrementing while enabled", c2 < c1);
    report_test("WDG_KICK reloads WDG_COUNT", c3 > c2);
    report_test("No timeout during test", (WDG_STATUS & 1) == 0);

    uart_print("\n[SUBTEST 4] Verifying countdown halts when disabled...\n");
    uint32_t h1 = WDG_COUNT;
    delay(50);
    uint32_t h2 = WDG_COUNT;
    report_test("WDG_COUNT holds while WDG_ENABLE = 0", h1 == h2);

    test_summary();
    return 0;
}
