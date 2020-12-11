const std = @import("std");
const builtin = @import("builtin");
const uart = @import("uart.zig");
const log = uart.log;
const arch = @import("arch.zig");
const exception = @import("exception.zig");
const sd = @import("sd.zig");
const pmap = @import("pmap.zig");
const proc = @import("proc.zig");
pub const assert = std.debug.assert;

pub const GlobalError = sd.Error || pmap.Error || proc.Error;

pub fn panic(message: []const u8, trace: ?*builtin.StackTrace) noreturn {
    // debug.panic(trace, "KERNEL PANIC: {}", .{message});
    log("KERNEL PANIC: {}\n", .{message});
    while (true) {
        asm volatile ("wfe");
    }
    // const kernel_panic = @intCast(usize, @enumToInt(exception.Exception.KERNEL_PANIC));
    // exception.exception_handler(kernel_panic, null);
    unreachable;
}

pub fn get_bits(val: usize, comptime off: usize, comptime len: usize) usize {
    return (val >> off) & ((1 << len) - 1);
}
