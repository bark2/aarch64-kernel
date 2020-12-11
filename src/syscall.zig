const uart = @import("uart.zig");
const log = uart.log;
const proc = @import("proc.zig");
const pmap = @import("pmap.zig");
const ExceptionFrame = @import("exception.zig").ExceptionFrame;

pub const Syscall = enum {
    KILL,
    PUTS,
    YIELD,
    LIGHT_FORK,
    PROC_SET_STATE,
    SET_PROC_EXCEPTION_FRAME,
    PAGE_MAP,
};

fn kill(pid: usize) !void {
    try proc.destory(pid);
}

fn puts(s: usize, len: usize) void {
    var tte: *pmap.TtEntry = undefined;
    // log("s: {}\n", .{s});
    if (pmap.page_lookup(proc.cur_proc.?.tt, @intToPtr(*allowzero u8, s), &tte)) |pp| {
        const is_valid = get_bits(tte.*, pmap.tte_valid_off, pmap.tte_valid_len);
        if (is_valid != pmap.tte_valid_valid)
            proc.destory(proc.cur_proc.?.pid) catch unreachable;
        const ap = get_bits(tte.*, pmap.tte_ap_off, pmap.tte_ap_len);
        if ((ap != pmap.tte_ap_el1_r_el0_r) and (ap != pmap.tte_ap_el1_rw_el0_rw))
            proc.destory(proc.cur_proc.?.pid) catch unreachable;

        const kva_base = pmap.page2kva(pp);
        const off = get_bits(s, 0, pmap.l3_off);
        const kva = kva_base + off;
        uart.log_bytes(kva[0..len]);
        return;
    }

    proc.destory(proc.cur_proc.?.pid) catch unreachable;
}

fn yield() void {
    proc.cur_proc.?.state = proc.ProcState.RUNNABLE;
}

fn light_fork() !usize {
    var p = try proc.alloc();
    p.state = proc.ProcState.NOT_RUNNABLE;
    p.ef = proc.cur_proc.?.ef;
    p.ef.xs[0] = 0;
    return p.pid;
}

fn proc_set_state(pid: usize, state: proc.ProcState) !void {
    var p = if (proc.find(pid)) |p| p else return error.NotFound;
    p.state = state;
}

fn set_proc_exception_frame(pid: usize, opt_ef: ?*ExceptionFrame) !void {
    if (opt_ef) |ef| {
        if (proc.find(pid)) |p| {
            p.ef = ef.*;
            return;
        }
        return error.NotFound;
    }
    return error.Null;
}

fn page_map(srcpid: usize, srcva: usize, dstpid: usize, dstva: usize, ap: usize) !void {}

fn syscall_(isyscall: usize, args: [8]usize) !usize {
    return switch (@intToEnum(Syscall, @truncate(@typeInfo(Syscall).Enum.tag_type, isyscall))) {
        Syscall.KILL => kill_blk: {
            try kill(args[0]);
            break :kill_blk 0;
        },
        Syscall.PUTS => puts_blk: {
            puts(args[0], args[1]);
            break :puts_blk 0;
        },
        Syscall.YIELD => yield_blk: {
            yield();
            break :yield_blk 0;
        },
        Syscall.LIGHT_FORK => try light_fork(),
        Syscall.PROC_SET_STATE => proc_set_state_blk: {
            try proc_set_state(args[0], @intToEnum(proc.ProcState, @truncate(@typeInfo(proc.ProcState).Enum.tag_type, args[1])));
            break :proc_set_state_blk 0;
        },
        Syscall.SET_PROC_EXCEPTION_FRAME => set_proc_exception_frame_blk: {
            try set_proc_exception_frame(args[0], @intToPtr(?*ExceptionFrame, args[1]));
            break :set_proc_exception_frame_blk 0;
        },
        Syscall.PAGE_MAP => page_map_blk: {
            try page_map(args[0], args[1], args[2], args[3], args[4]);
            break :page_map_blk 0;
        },
    };
}

pub fn syscall(isyscall: usize, args: [8]usize) usize {
    return syscall_(isyscall, args) catch |err| return @bitCast(usize, -@intCast(isize, @truncate(u16, @errorToInt(err))));
}

fn get_bits(val: usize, comptime off: usize, comptime len: usize) usize {
    return (val >> off) & ((1 << len) - 1);
}
