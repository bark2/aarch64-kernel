usingnamespace @import("common.zig");
const uart = @import("uart.zig");
const log = uart.log;
const proc = @import("proc.zig");
const pmap = @import("pmap.zig");
const ExceptionFrame = @import("exception.zig").ExceptionFrame;

pub const Syscall = enum {
    KILL,
    PUTS,
    YIELD,
    PROC_ALLOC,
    PROC_SET_STATE,
    PROC_PID,
    PAGE_ALLOC,
    PAGE_MAP,
};

fn kill(pid: usize) !void {
    try proc.destory(pid);
    if (proc.cur_proc == null)
        proc.schedule();
}

fn puts(s: usize, len: usize) void {
    var tte: *pmap.TtEntry = undefined;
    if (pmap.page_lookup(proc.cur_proc.?.tt, s, &tte)) |pp| {
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

fn proc_alloc() !usize {
    var p = try proc.alloc();
    assert(p.state == proc.ProcState.NOT_RUNNABLE);
    p.ef = proc.cur_proc.?.ef;
    p.ef.xs[0] = 0;
    return p.pid;
}

fn proc_set_state(pid: usize, state: proc.ProcState) !void {
    var p = if (proc.find(pid)) |p| p else return error.NotFound;
    p.state = state;
}

fn proc_pid() usize {
    return proc.cur_proc.?.pid;
}

fn page_alloc(dstpid: usize, dstva: usize, page_desc: usize) !void {
    const final_dstpid = if (dstpid == 0) proc.cur_proc.?.pid else dstpid;
    const dst = if (proc.find(final_dstpid)) |dst| dst else return error.NotFound;

    const pp = try pmap.page_alloc(true);
    const ap = @truncate(u2, get_bits(page_desc, pmap.tte_ap_off, pmap.tte_ap_len));
    log("dstva: {x}\n", .{dstva});
    try pmap.page_insert(dst.tt, pp, dstva, ap);

    var ppsrc = pmap.page_lookup(proc.cur_proc.?.tt, dstva, null).?;
    @memcpy(@ptrCast([*]u8, pmap.page2kva(pp)), @ptrCast([*]u8, pmap.page2kva(ppsrc)), pmap.page_size);
}

fn page_map(srcpid: usize, srcva: usize, dstpid: usize, dstva: usize, page_desc: usize) !void {
    const final_srcpid = if (srcpid == 0) proc.cur_proc.?.pid else srcpid;
    const final_dstpid = if (dstpid == 0) proc.cur_proc.?.pid else dstpid;
    const src = if (proc.find(final_srcpid)) |src| src else return error.NotFound;
    const dst = if (proc.find(final_dstpid)) |dst| dst else return error.NotFound;

    var src_tte: *pmap.TtEntry = undefined;
    const srcpp = if (pmap.page_lookup(src.tt, srcva, &src_tte)) |pp| pp else return error.BadValue;

    const ap = @truncate(u2, get_bits(page_desc, pmap.tte_ap_off, pmap.tte_ap_len));
    log("srcva: {x}, dstva: {x}\n", .{ srcva, dstva });
    try pmap.page_insert(dst.tt, srcpp, dstva, ap);
}

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
        Syscall.PROC_ALLOC => try proc_alloc(),
        Syscall.PROC_SET_STATE => proc_set_state_blk: {
            try proc_set_state(
                args[0],
                @intToEnum(proc.ProcState, @truncate(@typeInfo(proc.ProcState).Enum.tag_type, args[1])),
            );
            break :proc_set_state_blk 0;
        },
        Syscall.PROC_PID => proc_pid(),
        Syscall.PAGE_ALLOC => page_alloc_blk: {
            try page_alloc(args[0], args[1], args[2]);
            break :page_alloc_blk 0;
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
