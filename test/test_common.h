#ifndef TEST_COMMON_H
#define TEST_COMMON_H

#include <stdint.h>

#define UART_BASE  0x40000000
#define TMR_BASE   0x40001000
#define GPIO_BASE  0x40002000
#define MBIST_BASE 0x40003000
#define ECC_BASE   0x40004000
#define WDG_BASE   0x40005000

#define UART_RBR  *(volatile uint32_t*)(UART_BASE + 0x00)
#define UART_THR  *(volatile uint32_t*)(UART_BASE + 0x00)
#define UART_IER  *(volatile uint32_t*)(UART_BASE + 0x04)
#define UART_BDIV *(volatile uint32_t*)(UART_BASE + 0x08)
#define UART_LCR  *(volatile uint32_t*)(UART_BASE + 0x0C)
#define UART_LSR  *(volatile uint32_t*)(UART_BASE + 0x14)
#define UART_LSR_THRE 0x20
#define UART_LSR_TEMT 0x40

#define TMR_EN     *(volatile uint32_t*)(TMR_BASE + 0x00)
#define TMR_RELOAD *(volatile uint32_t*)(TMR_BASE + 0x04)
#define TMR_COUNT  *(volatile uint32_t*)(TMR_BASE + 0x08)

#define GPIO_DIR *(volatile uint32_t*)(GPIO_BASE + 0x00)
#define GPIO_OUT *(volatile uint32_t*)(GPIO_BASE + 0x04)
#define GPIO_IN  *(volatile uint32_t*)(GPIO_BASE + 0x08)

#define MBIST_START       *(volatile uint32_t*)(MBIST_BASE + 0x00)
#define MBIST_ALGO_SEL    *(volatile uint32_t*)(MBIST_BASE + 0x04)
#define MBIST_ADDR_START  *(volatile uint32_t*)(MBIST_BASE + 0x08)
#define MBIST_ADDR_END    *(volatile uint32_t*)(MBIST_BASE + 0x0C)
#define MBIST_BUSY        *(volatile uint32_t*)(MBIST_BASE + 0x10)
#define MBIST_DONE        *(volatile uint32_t*)(MBIST_BASE + 0x14)
#define MBIST_PASS_FAIL   *(volatile uint32_t*)(MBIST_BASE + 0x18)
#define MBIST_FAULT_ADDR  *(volatile uint32_t*)(MBIST_BASE + 0x1C)
#define MBIST_FAULT_COUNT *(volatile uint32_t*)(MBIST_BASE + 0x20)

#define ECC_ENABLE        *(volatile uint32_t*)(ECC_BASE + 0x00)
#define ECC_SHADOW_COUNT  *(volatile uint32_t*)(ECC_BASE + 0x04)
#define ECC_SHADOW_THRESH *(volatile uint32_t*)(ECC_BASE + 0x08)
#define ECC_EVENT         *(volatile uint32_t*)(ECC_BASE + 0x0C)
#define ECC_SUSPECT_ADDR  *(volatile uint32_t*)(ECC_BASE + 0x10)
#define ECC_STATUS        *(volatile uint32_t*)(ECC_BASE + 0x14)

#define WDG_ENABLE     *(volatile uint32_t*)(WDG_BASE + 0x00)
#define WDG_LOAD       *(volatile uint32_t*)(WDG_BASE + 0x04)
#define WDG_KICK       *(volatile uint32_t*)(WDG_BASE + 0x08)
#define WDG_COUNT      *(volatile uint32_t*)(WDG_BASE + 0x0C)
#define WDG_STATUS     *(volatile uint32_t*)(WDG_BASE + 0x10)
#define WDG_PRETIMEOUT *(volatile uint32_t*)(WDG_BASE + 0x14)

#define ALGO_CB 0x0
#define ALGO_MC 0x1

#define DCCM_BASE 0x00080000
#define DCCM_END  0x00083FFF
#define MB_START  0x00080000
#define MB_END    0x00081FF8
#define MB_SM_END 0x00080078

#define POLL_TIMEOUT 1000000

static uint32_t g_pass_count = 0;
static uint32_t g_fail_count = 0;

static __attribute__((noinline)) void uart_putc(char c) {
    uint32_t timeout = 100000;
    while ((UART_LSR & UART_LSR_THRE) == 0) {
        if (--timeout == 0) break;
    }
    UART_THR = (uint32_t)c;
}

static __attribute__((noinline)) void uart_print(const char* str) {
    while (*str) {
        if (*str == '\n') {
            uart_putc('\r');
        }
        uart_putc(*str++);
    }
}

static __attribute__((noinline)) void uart_print_hex(uint32_t val) {
    const char hex_chars[] = "0123456789ABCDEF";
    uart_print("0x");
    for (int i = 7; i >= 0; i--) {
        uart_putc(hex_chars[(val >> (i * 4)) & 0xF]);
    }
}

static __attribute__((noinline)) void uart_print_dec(uint32_t val) {
    if (val == 0) {
        uart_putc('0');
        return;
    }
    char buf[12];
    int idx = 0;
    while (val > 0) {
        buf[idx++] = (char)('0' + (val % 10));
        val /= 10;
    }
    for (int i = idx - 1; i >= 0; i--) {
        uart_putc(buf[i]);
    }
}

static __attribute__((noinline)) void delay(uint32_t count) {
    for (volatile uint32_t i = 0; i < count; i++) {
        __asm__ volatile("nop");
    }
}

static __attribute__((noinline)) void report_test(const char* test_name, int pass) {
    if (pass) {
        uart_print("  [PASS] ");
        g_pass_count++;
    } else {
        uart_print("  [FAIL] ");
        g_fail_count++;
    }
    uart_print(test_name);
    uart_print("\n");
}

static __attribute__((noinline)) void test_header(const char* title) {
    uart_print("\n");
    uart_print("====================================================\n");
    uart_print("  ");
    uart_print(title);
    uart_print("\n");
    uart_print("  Processor Core: VeeR EL2 (RV32IMC Bare-Metal)\n");
    uart_print("  Bus Architecture: AXI4 crossbar + AXI4-Lite peripherals\n");
    uart_print("====================================================\n\n");
}

static __attribute__((noinline)) void test_summary(void) {
    uart_print("\n====================================================\n");
    uart_print("  TEST SUMMARY REPORT\n");
    uart_print("====================================================\n");
    uart_print("  Total Passed: "); uart_print_dec(g_pass_count); uart_print("\n");
    uart_print("  Total Failed: "); uart_print_dec(g_fail_count); uart_print("\n");

    if (g_fail_count == 0) {
        uart_print("\n>>> ALL TESTS PASSED SUCCESSFULLY! <<<\n\n");
    } else {
        uart_print("\n*** SOME TESTS FAILED! ***\n\n");
    }
}

static inline int mbist_wait(void) {
    uint32_t n = POLL_TIMEOUT;
    while (!(MBIST_DONE & 1) && --n);
    return n != 0;
}

static inline int mbist_run(uint32_t algo, uint32_t s, uint32_t e) {
    MBIST_DONE = 1;
    MBIST_ADDR_START = s;
    MBIST_ADDR_END = e;
    MBIST_ALGO_SEL = algo;
    MBIST_START = 1;
    return mbist_wait();
}

#endif
