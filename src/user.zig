const syscall = @import("syscall.zig");

export fn main() usize {
    const s = "hello from user\n";
    _ = syscall2(@enumToInt(syscall.Syscall.PUTS), @ptrToInt(s[0..s.len]), 5);
    _ = syscall1(@enumToInt(syscall.Syscall.KILL), 0);
    return 0;
}

fn syscall0(number: usize) usize {
    return asm volatile (
        \\ svc #0
        : [ret] "={x0}" (-> usize)
        : [number] "{x8}" (number)
    );
}

fn syscall1(number: usize, arg1: usize) usize {
    return asm volatile (
        \\ svc #0
        : [ret] "={x0}" (-> usize)
        : [number] "{x8}" (number),
          [arg1] "{x0}" (arg1)
    );
}

fn syscall2(number: usize, arg1: usize, arg2: usize) usize {
    return asm volatile (
        \\ svc #0
        : [ret] "={x0}" (-> usize)
        : [number] "{x8}" (number),
          [arg1] "{x0}" (arg1),
          [arg2] "{x1}" (arg2)
    );
}
