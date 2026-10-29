#include "test_common.h"

static void mbist_report(void) {
    uart_print("  mbist_pass_fail:   "); uart_print_hex(MBIST_PASS_FAIL);   uart_print("\n");
    uart_print("  mbist_fault_addr:  "); uart_print_hex(MBIST_FAULT_ADDR);  uart_print("\n");
    uart_print("  mbist_fault_count: "); uart_print_dec(MBIST_FAULT_COUNT); uart_print("\n");
}

int main(void) {
    test_header("TEST SUITE: MBIST Controller");

    uart_print("[SUBTEST 1] Verifying configuration registers...\n");
    MBIST_ADDR_START = MB_START;
    report_test("mbist_addr_start write/readback", MBIST_ADDR_START == MB_START);
    MBIST_ADDR_END = MB_SM_END;
    report_test("mbist_addr_end write/readback", MBIST_ADDR_END == MB_SM_END);
    MBIST_ALGO_SEL = ALGO_CB;
    report_test("mbist_algo_sel write/readback (Checkerboard)", (MBIST_ALGO_SEL & 3) == ALGO_CB);
    MBIST_ALGO_SEL = ALGO_MC;
    report_test("mbist_algo_sel write/readback (March C-)", (MBIST_ALGO_SEL & 3) == ALGO_MC);

    uart_print("\n[SUBTEST 2] Verifying busy/done handshake (Checkerboard, small range)...\n");
    MBIST_DONE = 1;
    MBIST_ALGO_SEL = ALGO_CB;
    MBIST_START = 1;
    uint32_t busy = MBIST_BUSY;
    uint32_t dn = MBIST_DONE;
    int fin = mbist_wait();
    report_test("mbist_busy asserted after mbist_start", (busy & 1) || (dn & 1));
    report_test("mbist_done asserts within timeout", fin);
    report_test("mbist_busy clear once mbist_done set", (MBIST_BUSY & 1) == 0);
    mbist_report();
    report_test("Checkerboard small-range scan passes", MBIST_PASS_FAIL == 0);

    uart_print("\n[SUBTEST 3] Verifying mbist_done write-1-to-clear...\n");
    MBIST_DONE = 1;
    report_test("mbist_done cleared by writing 1", (MBIST_DONE & 1) == 0);

    uart_print("\n[SUBTEST 4] Verifying March C- (small range)...\n");
    fin = mbist_run(ALGO_MC, MB_START, MB_SM_END);
    report_test("March C- mbist_done asserts within timeout", fin);
    mbist_report();
    report_test("March C- small-range scan passes", MBIST_PASS_FAIL == 0);
    report_test("mbist_fault_count is 0", MBIST_FAULT_COUNT == 0);

    uart_print("\n[SUBTEST 5] Verifying March C- over lower 8 KB of DCCM...\n");
    uart_print("  Range: "); uart_print_hex(MB_START);
    uart_print(" to ");     uart_print_hex(MB_END);
    uart_print("\n");
    fin = mbist_run(ALGO_MC, MB_START, MB_END);
    report_test("Large-range mbist_done asserts within timeout", fin);
    mbist_report();
    report_test("Large-range scan passes", MBIST_PASS_FAIL == 0);

    MBIST_DONE = 1;

    test_summary();
    return 0;
}
