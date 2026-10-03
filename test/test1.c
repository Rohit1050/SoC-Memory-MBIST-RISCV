#include <stdint.h>

#define REG32(addr) (*(volatile uint32_t *)(addr))

#define MBIST_ADDR_START  REG32(0x40003008)
#define MBIST_ADDR_END    REG32(0x4000300C)
#define MBIST_ALGO_SEL    REG32(0x40003004)
#define MBIST_START       REG32(0x40003000)
#define MBIST_DONE        REG32(0x40003014)
#define MBIST_PASS_FAIL   REG32(0x40003018)

void main(void) {
    MBIST_ADDR_START = 0x00080000;
    MBIST_ADDR_END   = 0x00083FF8;   // real 16 KB DCCM end, not the stale default
    MBIST_ALGO_SEL    = 0x1;          // March C-
    MBIST_START        = 0x1;

    while (!(MBIST_DONE & 0x1)) { }
    // ... check MBIST_PASS_FAIL, report via UART, etc.
    while (1) { }
}
