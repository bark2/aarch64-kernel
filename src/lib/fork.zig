const proc = @import("../proc.zig");
const pmap = @import("../pmap.zig");
const syscall = @import("syscall.zig");
usingnamespace @import("print.zig");

var vtt = @intToPtr(*volatile pmap.Tt, (1 << 30) - (1 << 12));

fn get_bits(val: usize, comptime off: usize, comptime len: usize) usize {
    return (val >> off) & ((1 << len) - 1);
}

pub fn fork() !usize {
    // create a new process
    // duplicate the current running process virtual memory, TODO: COW
    // allocate a new page for its stack
    // set its pc value
    var child = try syscall.syscall0(@enumToInt(syscall.syscall.Syscall.LIGHT_FORK));

    for (vtt) |tte, i| {
        if (get_bits(tte, pmap.tte_valid_off, pmap.tte_valid_len) == pmap.tte_valid_valid) {
            try print("vtt[{}]: {b}\n", .{ i, tte });
        }
    }

    return 0;
}
