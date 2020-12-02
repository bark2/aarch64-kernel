const uart = @import("uart.zig");
const proc = @import("proc.zig");

pub const Syscall = enum {
    KILL, PUTS
};

fn kill(pid: usize) usize {
    proc.destory(pid);
    return 0;
}

fn puts(s: [*]u8, len: usize) void {
    uart.log_bytes(s[0..len]);
}

pub fn syscall(isyscall: usize, args: [8]usize) usize {
    return switch (@intToEnum(Syscall, @truncate(@typeInfo(Syscall).Enum.tag_type, isyscall))) {
        Syscall.KILL => kill(args[0]),
        Syscall.PUTS => puts_blk: {
            puts(@intToPtr([*]u8, args[0]), args[1]);
            break :puts_blk 0;
        },
    };
}
