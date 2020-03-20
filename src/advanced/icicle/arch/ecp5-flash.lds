ENTRY(start)

MEMORY {
    bram (rwx) : ORIGIN = 0x00000000, LENGTH = 32K
    flash (rx) : ORIGIN = 0x01100000, LENGTH = 3M
}

SECTIONS {
    .text : {
        start.o(.text);
        *(.text);
        *(.text.*);
    } > flash

    .data : ALIGN(4) {
        *(.data);
        *(.data.*);

        . = ALIGN(4);
    } > bram AT> flash

    .rodata : {
        *(.rodata);
        *(.rodata.*);
    } > flash

    .bss : ALIGN(4) {
        *(.bss);
        *(.bss.*);

        . = ALIGN(4);
    } > bram

    bss_start = ADDR(.bss);
    bss_end = bss_start + SIZEOF(.bss);

    data_flash_start = LOADADDR(.data);
    data_start = ADDR(.data);
    data_end = data_start + SIZEOF(.data);

    stack_top = ORIGIN(bram) + LENGTH(bram);
}
