ENTRY(_start)
 
SECTIONS
{
    /* Link the kernel at this address */
    . = 0xffffffff << 32;

    /* AT(...) gives the load address of this section, which tells
       the boot loader where to load the kernel in physical memory */
    .text : AT(0x0) {
        __text_start = .;
        KEEP(*(.text.exception_vector_table))
        KEEP(*(.text.exception))
        KEEP(*(.text.kern_main))
        *(.text.kern_main)
        __text_end = .;
    }
 
    .rodata : {
        *(.rodata)
        __debug_info_start = .;
        KEEP(*(.debug_info))
        __debug_info_end = .;
        __debug_abbrev_start = .;
        KEEP(*(.debug_abbrev))
        __debug_abbrev_end = .;
        __debug_str_start = .;
        KEEP(*(.debug_str))
        __debug_str_end = .;
        __debug_line_start = .;
        KEEP(*(.debug_line))
        __debug_line_end = .;
        __debug_ranges_start = .;
        KEEP(*(.debug_ranges))
        __debug_ranges_end = .;
    }
 
    .data : {
        *(.data)
    }
 
    .bss : {
        __bss_start = .;
        *(COMMON)
        *(.bss)
        __bss_end = .;
    }

    __end = .;
}
