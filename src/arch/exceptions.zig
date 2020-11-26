const arch = @import("system_registes.zig");

pub inline fn set_exception_table(vector_table: *u8) void {
    arch.set_vbar_el1(vector_table);
}

pub inline fn enable_irq() void {
    asm volatile (
        \\ msr    daifclr, #(1 << 1)
        \\ ret
    );
}

pub inline fn disable_irq() void {
    asm volatile (
        \\ msr    daifset, #(1 << 1)
        \\ ret
    );
}

