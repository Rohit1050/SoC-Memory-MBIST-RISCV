ENTRY(_start)

MEMORY {
    iccm (rx) : ORIGIN = 0x00040000, LENGTH = 16K
    dccm (rw) : ORIGIN = 0x00082000, LENGTH = 8K
}

SECTIONS {
    .text : {
        *(.text.init)
        *(.text)
        *(.text.*)
        *(.rodata)
        *(.rodata.*)
        *(.srodata)
        *(.srodata.*)
    } > iccm

    .data : {
        . = ALIGN(4);
        *(.data)
        *(.data.*)
        *(.sdata)
        *(.sdata.*)
    } > dccm AT > iccm

    .bss (NOLOAD) : {
        . = ALIGN(4);
        _bss_start = .;
        *(.sbss)
        *(.sbss.*)
        *(.bss)
        *(.bss.*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > dccm

    _stack_top = ORIGIN(dccm) + LENGTH(dccm);
}
