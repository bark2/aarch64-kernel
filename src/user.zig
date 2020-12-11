usingnamespace @import("lib/syscall.zig");
usingnamespace @import("lib/fork.zig");
usingnamespace @import("lib/print.zig");
const page_size = (1 << 12);
const rtt_addr = (1 << 32) - page_size;

export fn main() usize {
    const s = "hello from user\n";
    // if (fork() == 0) {
    print("{}\n", .{s}) catch unreachable;

    _ = fork() catch unreachable;

    print("bye\n", .{}) catch unreachable;

    _ = syscall1(@enumToInt(syscall.Syscall.KILL), 0) catch unreachable;
    // }

    return 0;
}
