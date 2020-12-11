pub const syscall = @import("../syscall.zig");
const SyscallError = @import("../sd.zig").Error || @import("../pmap.zig").Error || @import("../proc.zig").Error;

pub fn syscall0(number: usize) !usize {
    const res = asm volatile (
        \\ svc #0
        : [res] "={x0}" (-> isize)
        : [number] "{x8}" (number)
    );
    return if (res < 0) @intToError(@intCast(u16, -1 * res)) else return @intCast(usize, res);
}

pub fn syscall1(number: usize, arg1: usize) !usize {
    const res = asm volatile (
        \\ svc #0
        : [res] "={x0}" (-> isize)
        : [number] "{x8}" (number),
          [arg1] "{x0}" (arg1)
    );
    return if (res < 0) @intToError(@intCast(u16, -1 * res)) else return @intCast(usize, res);
}

pub fn syscall2(number: usize, arg1: usize, arg2: usize) !usize {
    const res = asm volatile (
        \\ svc #0
        : [res] "={x0}" (-> usize)
        : [number] "{x8}" (number),
          [arg1] "{x0}" (arg1),
          [arg2] "{x1}" (arg2)
    );
    return if (res < 0) @intToError(@intCast(u16, -1 * res)) else return @intCast(usize, res);
}
