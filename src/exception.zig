const builtin = @import("builtin");
// const debug = @import("debug.zig");
usingnamespace @import("common.zig");
const std = @import("std");
const arch = @import("arch.zig");
const uart = @import("uart.zig");
const proc = @import("proc.zig");
const syscall = @import("syscall.zig");
const log = uart.log;

const ESR_ELx_EC_SHIFT = 26;
const ESR_ELx_EC_SVC64 = 0x15;

pub const ExceptionFrame = packed struct {
    xs: [29]u64,
    fp: u64, // x29
    lr: u64, // x30
    sp: u64,
    elr: u64,
    spsr: u64,
};

pub const Exception = enum {
    SYNC_INVALID_EL1T = 0,
    IRQ_INVALID_EL1T = 1,
    FIQ_INVALID_EL1T = 2,
    ERROR_INVALID_EL1T = 3,
    SYNC_INVALID_EL1H = 4,
    IRQ_EL1H = 5,
    FIQ_INVALID_EL1H = 6,
    ERROR_INVALID_EL1H = 7,
    SYNC_EL0_64 = 8,
    IRQ_EL0_64 = 9,
    FIQ_INVALID_EL0_64 = 10,
    ERROR_INVALID_EL0_64 = 11,
    SYNC_INVALID_EL0_32 = 12,
    IRQ_INVALID_EL0_32 = 13,
    FIQ_INVALID_EL0_32 = 14,
    ERROR_INVALID_EL0_32 = 15,
};

const exception_names = init: {
    var array: [@typeInfo(Exception).Enum.fields.len][]const u8 = undefined;
    for (@typeInfo(Exception).Enum.fields) |e, i| {
        array[i] = e.name;
    }
    break :init array;
};

pub export fn handler(exception: usize, ef: *ExceptionFrame) callconv(.Fastcall) noreturn {
    var stack_or_proc_ef = ef;
    if (exception == @enumToInt(Exception.SYNC_EL0_64)) {
        proc.cur_proc.?.ef = stack_or_proc_ef.*;
        stack_or_proc_ef = &proc.cur_proc.?.ef;
    }

    dispatch(@intToEnum(Exception, @truncate(u4, exception)), stack_or_proc_ef);
    if (proc.cur_proc) |cur_proc| {
        if (cur_proc.state == proc.ProcState.RUNNING)
            cur_proc.run();
    }
    proc.schedule();
}

fn dispatch(exception: Exception, ef: *ExceptionFrame) void {
    log("\n{}\n", .{exception_names[@enumToInt(exception)]});
    const currentEL = asm volatile ("mrs x0, CurrentEL"
        : [ret] "={x0}" (-> usize)
    );
    log("EL{}\n", .{currentEL >> 2 & 0x3});
    const esr_el1 = asm ("mrs %[esr_el1], esr_el1"
        : [esr_el1] "=r" (-> usize)
    );
    const esr_el1_ec = (esr_el1 >> 26) & ((1 << 6) - 1);
    const esr_el1_iss = (esr_el1) & ((1 << 25) - 1);
    log("esr_el1 {x}, ec: {b}b, iss: {b}b (https://developer.arm.com/docs/ddi0595/b/aarch64-system-registers/esr_el1 )\n", .{ esr_el1, esr_el1_ec, esr_el1_iss });
    const elr_el1 = asm ("mrs %[elr_el1], elr_el1"
        : [elr_el1] "=r" (-> usize)
    );
    log("elr_el1 {x}\n", .{elr_el1});
    const spsr_el1 = asm ("mrs %[spsr_el1], spsr_el1"
        : [spsr_el1] "=r" (-> usize)
    );
    log("spsr_el1 {x}\n", .{spsr_el1});
    const far_el1 = asm ("mrs %[far_el1], far_el1"
        : [far_el1] "=r" (-> usize)
    );
    log("far_el1 {x}\n", .{far_el1});

    switch (exception) {
        // {exception type}_{taken from exception level}
        Exception.IRQ_EL1H => {
            // pop_ef(1);
        },
        Exception.IRQ_EL0_64 => {
            // pop_ef(0);
        },
        Exception.SYNC_EL0_64 => {
            if ((arch.esr_el1() >> ESR_ELx_EC_SHIFT) == ESR_ELx_EC_SVC64) { // caused by an svc inst
                // x8 for syscall number, x0-x7 for arguments, x0 for return value
                log("{}", .{ef.xs[8]});
                for (ef.xs[0..8]) |x, i|
                    log(", arg{}: {}", .{ i, x });
                log("\n", .{});

                ef.xs[0] = syscall.syscall(ef.xs[8], ef.xs[0..8].*);
                return;
            }
        },
        else => {},
    }

    log("Execution is now stopped in exception handler\n", .{});
    while (true) {
        asm volatile ("wfe");
    }
}

export var REGISTERS_SIZE: u12 = 272;
// push registers on to the kernel stack
pub inline fn push_ef(comptime el: usize, ef: *ExceptionFrame) noreturn {
    // asm volatile ()
    asm volatile (
        \\  sub	sp, sp, #272
        \\  stp	x0, x1, [sp, #16 * 0]
        \\  stp	x2, x3, [sp, #16 * 1]
        \\  stp	x4, x5, [sp, #16 * 2]
        \\  stp	x6, x7, [sp, #16 * 3]
        \\  stp	x8, x9, [sp, #16 * 4]
        \\  stp	x10, x11, [sp, #16 * 5]
        \\  stp	x12, x13, [sp, #16 * 6]
        \\  stp	x14, x15, [sp, #16 * 7]
        \\  stp	x16, x17, [sp, #16 * 8]
        \\  stp	x18, x19, [sp, #16 * 9]
        \\  stp	x20, x21, [sp, #16 * 10]
        \\  stp	x22, x23, [sp, #16 * 11]
        \\  stp	x24, x25, [sp, #16 * 12]
        \\  stp	x26, x27, [sp, #16 * 13]
        \\  stp x28, x29, [sp, #16 * 14]
        :
        : [ef] "{sp}" (ef)
    );
    if (el == 0) {
        asm volatile ("mrs x21, sp_el0");
    } else {
        asm volatile ("add x21, sp, #272"
            :
            : [ef] "{sp}" (ef)
        );
    }
    asm volatile (
        \\  mrs	x22, elr_el1
        \\  mrs	x23, spsr_el1
        \\  stp	x30, x21, [sp, #16 * 15] 
        \\  stp	x22, x23, [sp, #16 * 16]
        :
        : [ef] "{sp}" (ef)
    );
}

pub inline fn pop_ef(comptime el: usize, ef: *ExceptionFrame) noreturn {
    asm volatile (
        \\  ldp	x22, x23, [sp, #16 * 16]
        \\  ldp	x30, x21, [sp, #16 * 15]
        :
        : [ef] "{sp}" (ef)
    );
    if (el == 0)
        asm volatile ("msr sp_el0, x21");
    asm volatile (
        \\  msr	elr_el1, x22			
        \\  msr	spsr_el1, x23
        \\  ldp	x0, x1, [sp, #16 * 0]
        \\  ldp	x2, x3, [sp, #16 * 1]
        \\  ldp	x4, x5, [sp, #16 * 2]
        \\  ldp	x6, x7, [sp, #16 * 3]
        \\  ldp	x8, x9, [sp, #16 * 4]
        \\  ldp	x10, x11, [sp, #16 * 5]
        \\  ldp	x12, x13, [sp, #16 * 6]
        \\  ldp	x14, x15, [sp, #16 * 7]
        \\  ldp	x16, x17, [sp, #16 * 8]
        \\  ldp	x18, x19, [sp, #16 * 9]
        \\  ldp	x20, x21, [sp, #16 * 10]
        \\  ldp	x22, x23, [sp, #16 * 11]
        \\  ldp	x24, x25, [sp, #16 * 12]
        \\  ldp	x26, x27, [sp, #16 * 13]
        \\  ldp	x28, x29, [sp, #16 * 14]
        \\  // add	sp, sp, #272		
        \\  eret
        :
        : [ef] "{sp}" (ef)
    );
    unreachable;
}
