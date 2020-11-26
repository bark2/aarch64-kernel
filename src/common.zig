const builtin = @import("builtin");
const uart = @import("uart.zig");
const log = uart.log;
const arch = @import("arch.zig");
const exception = @import("exception.zig");

pub const Error = error{OutOfMemory};

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
