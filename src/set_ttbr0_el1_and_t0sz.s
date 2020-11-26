.type set_ttbr0_el1_and_t0sz, @function
.global set_ttbr0_el1_and_t0sz

// TODO: rename file and function

// Arguments:
//	ttbr0_el1, tcr_el1, kern_base
//
set_ttbr0_el1_and_t0sz:
	// jump to physical address
	ldr x3, =phys
	sub x3, x3, x2
	br x3
phys:	// disable MMU
	mrs x3, sctlr_el1
	bic x3, x3, #(1 << 0)
        msr sctlr_el1, x3
        isb
	// set mair
	mov x3, #0x44
        msr mair_el1, x3
	// set tcr_el1
        msr tcr_el1, x1
	// set new translation table
	sub x0, x0, x2
        msr ttbr1_el1, x0
        msr ttbr0_el1, x0
        isb
	// flush tlb
        tlbi     vmalle1
        dsb      sy
        isb
	// renable MMU
        mrs x0, sctlr_el1
        orr x0, x0, #(1 << 0)
        msr sctlr_el1, x0
        isb

	// return to virtual high address
	ldr x0, =high
	br x0
high:	ret
