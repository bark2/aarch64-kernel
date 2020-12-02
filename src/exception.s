.equ SYNC_INVALID_EL1T, 0
.equ IRQ_INVALID_EL1T, 1
.equ FIQ_INVALID_EL1T, 2
.equ ERROR_INVALID_EL1T, 3
.equ SYNC_INVALID_EL1H, 4
.equ IRQ_EL1H, 5
.equ FIQ_INVALID_EL1H, 6
.equ ERROR_INVALID_EL1H, 7
.equ SYNC_EL0_64, 8
.equ IRQ_EL0_64, 9
.equ FIQ_INVALID_EL0_64, 10
.equ ERROR_INVALID_EL0_64, 11
.equ SYNC_INVALID_EL0_32, 12
.equ IRQ_INVALID_EL0_32, 13
.equ FIQ_INVALID_EL0_32, 14
.equ ERROR_INVALID_EL0_32, 15
	

//  el: indicates which exception level an exception is taken from
.macro	push_ef, el
	sub	sp, sp, #272
	stp	x0, x1, [sp, #16 * 0]
	stp	x2, x3, [sp, #16 * 1]
	stp	x4, x5, [sp, #16 * 2]
	stp	x6, x7, [sp, #16 * 3]
	stp	x8, x9, [sp, #16 * 4]
	stp	x10, x11, [sp, #16 * 5]
	stp	x12, x13, [sp, #16 * 6]
	stp	x14, x15, [sp, #16 * 7]
	stp	x16, x17, [sp, #16 * 8]
	stp	x18, x19, [sp, #16 * 9]
	stp	x20, x21, [sp, #16 * 10]
	stp	x22, x23, [sp, #16 * 11]
	stp	x24, x25, [sp, #16 * 12]
	stp	x26, x27, [sp, #16 * 13]
	stp	x28, x29, [sp, #16 * 14]
.if	\el == 0
	mrs	x21, sp_el0
.else
	add	x21, sp, #272
.endif
	mrs	x22, elr_el1
	mrs	x23, spsr_el1
	stp	x30, x21, [sp, #16 * 15] 
	stp	x22, x23, [sp, #16 * 16]
	.endm
	

	.macro	pop_ef, el
	ldp	x22, x23, [sp, #16 * 16]
	ldp	x30, x21, [sp, #16 * 15] 

	.if	\el == 0
	msr	sp_el0, x21
	.endif /* \el == 0 */

	msr	elr_el1, x22			
	msr	spsr_el1, x23

	ldp	x0, x1, [sp, #16 * 0]
	ldp	x2, x3, [sp, #16 * 1]
	ldp	x4, x5, [sp, #16 * 2]
	ldp	x6, x7, [sp, #16 * 3]
	ldp	x8, x9, [sp, #16 * 4]
	ldp	x10, x11, [sp, #16 * 5]
	ldp	x12, x13, [sp, #16 * 6]
	ldp	x14, x15, [sp, #16 * 7]
	ldp	x16, x17, [sp, #16 * 8]
	ldp	x18, x19, [sp, #16 * 9]
	ldp	x20, x21, [sp, #16 * 10]
	ldp	x22, x23, [sp, #16 * 11]
	ldp	x24, x25, [sp, #16 * 12]
	ldp	x26, x27, [sp, #16 * 13]
	ldp	x28, x29, [sp, #16 * 14]
	add	sp, sp, #272		
	eret
	.endm
	

	.macro	ventry	label
	.align	7
	b	\label
	.endm
	

/*
 * Exception vectors.
 */
.section .text.exception_vector_table
.align	11
.globl exception_vector_table 
exception_vector_table:
	ventry	sync_invalid_el1t			// Synchronous EL1t
	ventry	irq_invalid_el1t			// IRQ EL1t
	ventry	fiq_invalid_el1t			// FIQ EL1t
	ventry	error_invalid_el1t			// Error EL1t

	ventry	sync_invalid_el1h			// Synchronous EL1h
	ventry	irq_el1					// IRQ EL1h
	ventry	fiq_invalid_el1h			// FIQ EL1h
	ventry	error_invalid_el1h			// Error EL1h

	ventry	sync_el0				// Synchronous 64-bit EL0
	ventry	irq_el0					// IRQ 64-bit EL0
	ventry	fiq_invalid_el0_64			// FIQ 64-bit EL0
	ventry	error_invalid_el0_64			// Error 64-bit EL0

	ventry	sync_invalid_el0_32			// Synchronous 32-bit EL0
	ventry	irq_invalid_el0_32			// IRQ 32-bit EL0
	ventry	fiq_invalid_el0_32			// FIQ 32-bit EL0
	ventry	error_invalid_el0_32			// Error 32-bit EL0

	
.macro handle_entry el, type
	push_ef \el
	mov	x0, \type
	mov     x1, sp
	bl	handler
	.endm	

sync_invalid_el1t:
	handle_entry 1,  SYNC_INVALID_EL1T

irq_invalid_el1t:
	handle_entry  1, IRQ_INVALID_EL1T

fiq_invalid_el1t:
	handle_entry  1, FIQ_INVALID_EL1T

error_invalid_el1t:
	handle_entry  1, ERROR_INVALID_EL1T

sync_invalid_el1h:
	handle_entry 1, SYNC_INVALID_EL1H

fiq_invalid_el1h:
	handle_entry  1, FIQ_INVALID_EL1H

error_invalid_el1h:
	handle_entry  1, ERROR_INVALID_EL1H

fiq_invalid_el0_64:
	handle_entry  0, FIQ_INVALID_EL0_64

error_invalid_el0_64:
	handle_entry  0, ERROR_INVALID_EL0_64

sync_invalid_el0_32:
	handle_entry  0, SYNC_INVALID_EL0_32

irq_invalid_el0_32:
	handle_entry  0, IRQ_INVALID_EL0_32

fiq_invalid_el0_32:
	handle_entry  0, FIQ_INVALID_EL0_32

error_invalid_el0_32:
	handle_entry  0, ERROR_INVALID_EL0_32

irq_el1:
	handle_entry  0, IRQ_EL1H

irq_el0:
	handle_entry  0, IRQ_EL0_64

sync_el0:
	handle_entry  0, SYNC_EL0_64
