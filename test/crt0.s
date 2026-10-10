.section .text.init
.globl _start
.type _start, @function

_start:
    /* Set stack pointer to top of DCCM stack area */
    la sp, _stack_top

    /* Zero out .bss section */
    la t0, _bss_start
    la t1, _bss_end
1:  bgeu t0, t1, 2f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 1b

2:  /* Jump to main */
    call main

    /* Loop forever upon exit */
3:  wfi
    j 3b

.size _start, . - _start
