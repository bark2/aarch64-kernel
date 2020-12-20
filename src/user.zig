usingnamespace @import("lib/syscall.zig");
usingnamespace @import("lib/fork.zig");
usingnamespace @import("lib/print.zig");
const page_size = (1 << 12);
const rtt_addr = (1 << 32) - page_size;

export fn main() usize {
    const pid = kernel_space_fork() catch unreachable;
    // const self_pid = syscall0(@enumToInt(syscall.Syscall.PROC_PID)) catch unreachable;
    print("fork got {}\n", .{pid});
    _ = syscall1(@enumToInt(syscall.Syscall.KILL), 0) catch unreachable;

    return 0;
}
