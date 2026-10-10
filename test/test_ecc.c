#include "test_common.h"

int main(void) {
    test_header("TEST SUITE: ECC Monitor");

    uart_print("[SUBTEST 1] Verifying shadow registers...\n");
    ECC_SHADOW_COUNT = 0x1234;
    report_test("ECC_SHADOW_COUNT write/readback (0x1234)", ECC_SHADOW_COUNT == 0x1234);
    ECC_SHADOW_THRESH = 0x5;
    report_test("ECC_SHADOW_THRESH write/readback (5)", (ECC_SHADOW_THRESH & 0x1F) == 0x5);
    ECC_SHADOW_COUNT = 0;
    ECC_SHADOW_THRESH = 0;

    uart_print("\n[SUBTEST 2] Verifying event ignored while disabled...\n");
    ECC_ENABLE = 0;
    ECC_EVENT = 1;
    report_test("ECC_STATUS stays clear with monitor disabled", ECC_STATUS == 0);

    uart_print("\n[SUBTEST 3] Verifying event while MBIST is idle...\n");
    ECC_ENABLE = 1;
    ECC_EVENT = 1;
    uint32_t st = ECC_STATUS;
    uart_print("  ECC_STATUS: "); uart_print_hex(st); uart_print("\n");
    report_test("correctable_seen set", (st & 1) == 1);
    report_test("mbist_correlated clear (no scan active)", (st & 2) == 0);
    report_test("ECC_SUSPECT_ADDR unchanged (0)", ECC_SUSPECT_ADDR == 0);

    uart_print("\n[SUBTEST 4] Verifying event during an active MBIST scan...\n");
    MBIST_DONE = 1;
    MBIST_ADDR_START = MB_START;
    MBIST_ADDR_END = MB_END;
    MBIST_ALGO_SEL = ALGO_MC;
    MBIST_START = 1;
    uint32_t n = POLL_TIMEOUT;
    while (!(MBIST_BUSY & 1) && --n);
    ECC_EVENT = 1;
    st = ECC_STATUS;
    uint32_t sa = ECC_SUSPECT_ADDR;
    int fin = mbist_wait();
    uart_print("  ECC_STATUS: "); uart_print_hex(st);
    uart_print(", suspect addr: "); uart_print_hex(sa);
    uart_print("\n");
    report_test("MBIST scan started and finished", n != 0 && fin);
    report_test("mbist_correlated set", (st & 2) == 2);
    report_test("ECC_SUSPECT_ADDR inside DCCM", sa >= DCCM_BASE && sa <= DCCM_END);

    uart_print("\n[SUBTEST 5] Verifying ECC_EVENT reads back zero...\n");
    report_test("ECC_EVENT is write-1-to-clear (reads 0)", ECC_EVENT == 0);

    MBIST_DONE = 1;
    ECC_ENABLE = 0;

    test_summary();
    return 0;
}
