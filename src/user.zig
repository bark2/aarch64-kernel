const syscall = @import("syscall.zig");

pub fn main() align(8) !void {
    _ = syscall1(@enumToInt(syscall.Syscall.KILL), 0);
}

fn syscall0(number: usize) usize {
    return asm volatile (
        \\ mov x8, #0
        \\ svc #0
        : [ret] "={x0}" (-> usize)
        : [number] "{x0}" (number)
    );
}

fn syscall1(number: usize, arg1: usize) usize {
    return asm volatile (
        \\ mov x8, #0
        \\ svc #0
        : [ret] "={x0}" (-> usize)
        : [number] "{x0}" (number),
          [arg1] "{x1}" (arg1)
    );
}
