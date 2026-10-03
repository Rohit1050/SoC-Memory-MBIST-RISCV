#include <stdint.h>

#define REG32(addr) (*(volatile uint32_t *)(addr))

#define MBIST_START       REG32(0x40003000)
#define MBIST_ALGO_SEL    REG32(0x40003004)
#define MBIST_ADDR_START  REG32(0x40003008)
#define MBIST_ADDR_END    REG32(0x4000300C)
#define MBIST_STATUS      REG32(0x40003010)
#define MBIST_DONE        REG32(0x40003014)
#define MBIST_PASS_FAIL   REG32(0x40003018)

#define MBIST_START_ADDR  0x00080000
#define MBIST_END_ADDR    0x00083FF8

#define MBIST_TIMEOUT     10000000

#define UART_BASE         0x40002000
#define UART_TXDATA       REG32(UART_BASE + 0x00)
#define UART_STATUS       REG32(UART_BASE + 0x04)

#define UART_TX_READY     0x01

void uart_putc(char c)
{
    while ((UART_STATUS & UART_TX_READY) == 0)
        ;

    UART_TXDATA = (uint32_t)c;
}

void uart_print(const char *str)
{
    while (*str)
        uart_putc(*str++);
}

void uart_print_hex(uint32_t value)
{
    const char hex[] = "0123456789ABCDEF";
    int i;

    uart_print("0x");

    for (i = 7; i >= 0; i--)
        uart_putc(hex[(value >> (i * 4)) & 0xF]);
}

int main(void)
{
    uint32_t timeout = 0;
    uint32_t result;

    uart_print("\nMBIST TEST START\n");

    MBIST_ADDR_START = MBIST_START_ADDR;
    MBIST_ADDR_END   = MBIST_END_ADDR;

    uart_print("Address Start: ");
    uart_print_hex(MBIST_ADDR_START);
    uart_print("\n");

    uart_print("Address End: ");
    uart_print_hex(MBIST_ADDR_END);
    uart_print("\n");

    MBIST_ALGO_SEL = 0x1;

    uart_print("Algorithm: ");
    uart_print_hex(MBIST_ALGO_SEL);
    uart_print("\n");

    MBIST_START = 0x1;

    uart_print("MBIST Started\n");

    while ((MBIST_DONE & 0x1) == 0)
    {
        timeout++;

        if (timeout >= MBIST_TIMEOUT)
        {
            uart_print("MBIST TIMEOUT\n");
            return 1;
        }
    }

    uart_print("MBIST DONE\n");

    result = MBIST_PASS_FAIL;

    uart_print("PASS_FAIL: ");
    uart_print_hex(result);
    uart_print("\n");

    if (result & 0x1)
        uart_print("MBIST PASS\n");
    else
        uart_print("MBIST FAIL\n");

    uart_print("MBIST STATUS: ");
    uart_print_hex(MBIST_STATUS);
    uart_print("\n");

    return 0;
}
