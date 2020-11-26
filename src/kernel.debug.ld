ENTRY(_start)
 
SECTIONS
{
    /* Link the kernel at this address */
    . = 0xffffffff << 32;

    /* AT(...) gives the load address of this section, which tells
       the boot loader where to load the kernel in physical memory */
    .text : AT(0) {
        __text_start = .;
        KEEP(*(.text.exception_vector_table))
        KEEP(*(.text.boot))
        KEEP(*(.text.kern_main))
        *(.text.kern_main)
        __text_end = .;
    }
 
    .rodata : {
        __rodata_start = .;
        *(.rodata)
        __rodata_end = .;
    }
 
    .data : {
        __data_start = .;
        *(.data)
        __data_end = .;
    }
 
    .bss : ALIGN(16) {
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

    /* /DISCARD/ : { *(.gnu*) *(.note*) *(.eh_frame*) }	 */

    __end = .;
}

