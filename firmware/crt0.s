.section .text.init
.globl _start
.type _start, @function

_start:
    /* Set stack pointer to top of DCCM stack area */
    la sp, _stack_top

    /* Copy .data section from ICCM (LMA) to DCCM (VMA) */
    la t0, _data_start
    la t1, _data_end
    la t2, _data_load
1:  bgeu t0, t1, 2f
    lw t3, 0(t2)
    sw t3, 0(t0)
    addi t0, t0, 4
    addi t2, t2, 4
    j 1b

2:  /* Zero out .bss section */
    la t0, _bss_start
    la t1, _bss_end
3:  bgeu t0, t1, 4f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 3b

4:  /* Jump to main */
    call main

    /* Loop forever upon exit */
5:  wfi
    j 5b

.size _start, . - _start
