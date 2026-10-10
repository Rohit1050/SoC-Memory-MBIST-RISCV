/*
 Copyright 2019-2026 Western Digital Corporation or its affiliates.
 Copyright 2022-2026 Antmicro <www.antmicro.com>

 SPDX-License-Identifier: Apache-2.0
 Licensed under the Apache License, Version 2.0, see LICENSE for details.

 This is an automatically generated file by student on Sat Oct 10 15:39:36 IST 2026

 cmd:    veer -target=default -set build_axi4 

*/
OUTPUT_ARCH( "riscv" )
ENTRY(_start)

SECTIONS
{
  . = 0x80000000;
  .text.init .  : { *(.text.init) }
  
  .text . : { *(.text) }
  _end = .;
  . = 0xd0580000;
  .data.io .  : { *(.data.io) }
    . = 0xf0040000 ;
  .data  :  ALIGN(0x800) { *(.*data) *(.rodata*)}
  .bss :  {BSS_START = .; *(.*bss)}
  BSS_END = .;
  STACK = ALIGN(16) + 0x1000;
  
    . = 0xfffffff8; .data.ctl : { LONG(0xf0040000); LONG(STACK) }
}

