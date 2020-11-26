ENTRY(_start)
 
SECTIONS
{
    . = 0x80000;

    /* AT(...) gives the load address of this section, which tells
       the boot loader where to load the kernel in physical memory */
    .text : AT(0x80000) {
        __text_start = .;
        /* KEEP(*(.text.exception)) */
        KEEP(*(.text.boot))
        *(.text.boot)
        /* KEEP(*(.text.boot_main)) */
        /* *(.text.boot_main) */
        /* KEEP(*(.text.exception)) */
        /* . = ALIGN(256); */
        /* KEEP(*(.text.kernel_main)) */
        /* *(.text.kernel_main) */
        __text_end = .;
    }
 
.rodata : ALIGN(4K) {
        __rodata_start = .;
        *(.rodata)
        __rodata_end = .;
    }
 
    .data : ALIGN(4K) {
        __data_start = .;
        *(.data)
        __data_end = .;
    }
 
    .bss : ALIGN(4K) {
        __bss_start = .;
	*(COMMON)
        *(.bss)
	__debug_info_start = .;
        __debug_info_end = .;
        __debug_abbrev_start = .;
        __debug_abbrev_end = .;
        __debug_str_start = .;
        __debug_str_end = .;
        __debug_line_start = .;
        __debug_line_end = .;
        __debug_ranges_start = .;
        __debug_ranges_end = .;
        __bss_end = .;
    }

    __end = .;
}
