#include "test_common.h"

int main(void) {
    test_header("TEST SUITE: GPIO");

    uart_print("[SUBTEST 1] Verifying direction register...\n");
    GPIO_DIR = 0xFF;
    report_test("GPIO_DIR write/readback (0xFF)", (GPIO_DIR & 0xFF) == 0xFF);
    GPIO_DIR = 0x0F;
    report_test("GPIO_DIR write/readback (0x0F)", (GPIO_DIR & 0xFF) == 0x0F);

    uart_print("\n[SUBTEST 2] Verifying output register...\n");
    GPIO_OUT = 0xA5;
    report_test("GPIO_OUT write/readback (0xA5)", (GPIO_OUT & 0xFF) == 0xA5);
    GPIO_OUT = 0x5A;
    report_test("GPIO_OUT write/readback (0x5A)", (GPIO_OUT & 0xFF) == 0x5A);

    uart_print("\n[SUBTEST 3] Verifying input register is read-only...\n");
    uint32_t before = GPIO_IN & 0xFF;
    GPIO_IN = (~before) & 0xFF;
    uint32_t after = GPIO_IN & 0xFF;
    uart_print("  GPIO_IN before: "); uart_print_hex(before);
    uart_print(", after: ");          uart_print_hex(after);
    uart_print("\n");
    report_test("Write to GPIO_IN has no effect", before == after);

    GPIO_DIR = 0;
    GPIO_OUT = 0;

    test_summary();
    return 0;
}
