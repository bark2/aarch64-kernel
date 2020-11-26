const proc = @import("proc.zig");

pub const Syscall = enum {
    KILL
};

fn kill(pid: usize) usize {
    proc.free(pid);
    return 0;
}

pub fn syscall(isyscall: usize, args: [8]usize) usize {
    return switch (isyscall) {
        0 => kill(args[0]),
        else => unreachable,
    };
}
