const builtin = @import("builtin");
// const debug = @import("debug.zig");
usingnamespace @import("common.zig");
const std = @import("std");
const AtomicOrder = @import("builtin").AtomicOrder;
const arch = @import("arch.zig");
const pmap = @import("pmap.zig");
const proc = @import("proc.zig");
const uart = @import("uart.zig");
const log = uart.log;

// linker filled globals
extern var __bss_start: u8;
extern var __bss_end: u8;

comptime {
    asm (
        \\.section .text.boot
        \\.globl _start
        \\_start:
        \\    mrs     x4, mpidr_el1
        \\    and     x4, x4, #3
        \\    cbnz    x4, halt
        \\// ------------------------------------
        \\    ldr     x0, =exception_vector_table
        \\    msr vbar_el1,x0
        \\    msr vbar_el2,x0
        \\    //msr vbar_el3,x0
        \\// Configure SCR_EL3
        \\    MOV   x0, #0              // Indicates that EL0 and EL1 are in Secure state.
        \\    //ORR   x0, x0, #(1 << 1)   // IRQ interrupts are taken to EL3
        \\    //ORR   x0, x0, #(1 << 2)   // FIQ interrupts are taken to EL3
        \\    //ORR   x0, x0, #(1 << 3)   // External Abort and SError are taken to EL3
        \\    ORR   x0, x0, #(1 << 7)   // SMD=1 SMD instructions are enabled
        \\    ORR   x0, x0, #(1 << 10)  // RW=1  Next EL down uses AArch64
        \\    ORR   x0, x0, #(1 << 11)  // ST=1  Secure EL1 can access timers
        \\    //MSR   SCR_EL3, x0
        \\// ------------------------------------
        \\ // Configure HCR_EL2
        \\    MOV   x0, #0
        \\    //ORR   w0, wzr, #(1 << 3)       // FMO=1
        \\    //ORR   x0, x0, #(1 << 4)        // IMO=1
        \\    ORR   x0, x0, #(1 << 31)       // RW=1     NS.EL1 is AArch64
        \\                                   // TGE=0    Entry to NS.EL1 is possible
        \\                                   // VM=0     Stage 2 MMU disabled
        \\    MSR   HCR_EL2, x0
        \\// ------------------------------------
        \\// Set up VMPIDR_EL2/VPIDR_EL1
        \\    MRS   x0, MIDR_EL1
        \\    MSR   VPIDR_EL2, x0
        \\    MRS   x0, MPIDR_EL1
        \\    MSR   VMPIDR_EL2, x0
        \\// ---------------------------
        \\// Set VMID
        \\// Although we are not using stage 2 translation, NS.EL1 still cares
        \\// about the VMID
        \\    MSR   VTTBR_EL2, xzr
        \\// ------------------------------------
        \\// Set SCTLRs for EL1/2 to safe values
        \\    MSR   SCTLR_EL2, xzr
        \\    MSR   SCTLR_EL1, xzr
        \\// ------------------------------------
        \\ // Enabling NEON and Floating Point
        \\ // Disable trapping of accessing in EL3 and EL2.
        \\ //MSR CPTR_EL3, XZR
        \\ MSR CPTR_EL2, XZR
        \\ // Disable access trapping in EL1 and EL0.
        \\ MOV X1, #(0x3 << 20) // FPEN disables trapping to EL1.
        \\ MSR CPTR_EL2, X1
        \\ MSR CPACR_EL1, X1
        \\ ISB
        \\// ------------------------------------
        \\// Address register to return from EL2 exception
        \\    ADR   x0, el1_entry
        \\    MSR   ELR_EL2, x0
        \\// ------------------------------------
        \\// Enter EL1
        \\    msr DAIFClr, #0xf              // dont take exceptions
        \\    MOV   x0, #0x0
        \\    ORR   x0, x0, #(1 << 2)        // exception in EL3 returns to EL1t
        \\    MSR   spsr_el2, x0
        \\    eret
        \\// ------------------------------------
        \\el1_entry:
        \\ MSR SPSel, #1                  // Handler will switch to SP_ELn
        \\// ------------------------------------
        \\ // enable MMU
        \\ ldr x0, =boot_tt_l1
        \\ // mov x1, #0x80200020
        \\ mov x1, #0x80
        \\ lsl x1, x1, #8
        \\ orr x1, x1, #0x20
        \\ lsl x1, x1, #16
        \\ orr x1, x1, #0x20
        \\ mov x2, #(0xffffffff << 32) // kern_base
        \\ bl set_ttbr0_el1_and_t0sz // Return address saved in x30
        \\// ------------------------------------
        \\ // Set boot stack
        \\ ldr x0, =boot_stack
        \\ add x0, x0, 0x8000
        \\ mov sp, x0
        \\// ------------------------------------
        \\ // Jump to kernel main
        \\ ldr     x0, =kern_main
        \\ br      x0
        \\// ------------------------------------
        \\halt:
        \\ wfe
        \\ b       halt
    );
}

inline fn init() Error!void {
    uart.init();
    try pmap.init();
    try proc.init();
}

export fn kern_main() callconv(.Naked) void {
    @memset(@as(*volatile [1]u8, &__bss_start), 0, @ptrToInt(&__bss_end) - @ptrToInt(&__bss_start));
    log("hello world!\n", .{});
    init() catch {
        panic("Error in critical code\n", null);
    };

    // while (true) uart.write_byte(uart.read_byte());
    var p = proc.create(@intToPtr(*u8, 1)) catch panic("Out of Memory allocating proc\n", null);
    log("proc: {}\n", .{p.*});

    p.run();
}
