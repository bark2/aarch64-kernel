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
    PROC_FORK,
    PROC_SET_STATE,
    PROC_PID,
    PAGE_ALLOC,
    PAGE_MAP,
};

fn kill(pid: usize) !void {
    const final_pid = if (pid == 0) proc.cur_proc.?.pid else pid;
    const p = if (proc.find(final_pid)) |p| p else return error.NotFound;
    proc.destory(p);
    if (proc.cur_proc == null)
        proc.schedule();
}

fn puts(s: usize, len: usize) void {
    var tte: *pmap.TtEntry = undefined;
    if (pmap.page_lookup(proc.cur_proc.?.tt, s, &tte)) |pp| {
        if (tte.* & pmap.tte_valid_mask != pmap.tte_valid_valid)
            proc.destory(proc.cur_proc.?);
        const ap = tte.* & pmap.tte_ap_mask;
        if ((ap != pmap.tte_ap_el1_r_el0_r) and (ap != pmap.tte_ap_el1_rw_el0_rw))
            proc.destory(proc.cur_proc.?);

        const kva_base = pmap.page2kva(pp);
        const off = s & ((1 << pmap.l3_off) - 1);
        const kva = kva_base + off;
        uart.log_bytes(kva[0..len]);
        return;
    }

    proc.destory(proc.cur_proc.?);
}

fn yield() void {
    proc.cur_proc.?.state = proc.ProcState.RUNNABLE;
}

fn proc_fork() !usize {
    var p = try proc.alloc();
    assert(p.state == proc.ProcState.NOT_RUNNABLE);
    p.ef = proc.cur_proc.?.ef;
    p.ef.xs[0] = 0;

    const l2tt = @intToPtr(*pmap.Tt, pmap.kern_addr(pmap.tte_paddr(proc.cur_proc.?.tt[0])));
    for (l2tt) |l2pte, il2| {
        if (l2pte & pmap.tte_valid_mask == pmap.tte_valid_valid) {
            const l3tt = @intToPtr(*pmap.Tt, pmap.kern_addr(pmap.tte_paddr(l2pte)));
            for (l3tt) |pte, il3| {
                if (pte & pmap.tte_valid_mask == pmap.tte_valid_valid) {
                    const va = pmap.gen_laddr(0, il2, il3);
                    const flags = pte - pmap.tte_paddr(pte);
                    const srcpp = pmap.pa2page(pmap.tte_paddr(pte));
                    if (pte & pmap.tte_ap_mask == pmap.tte_ap_el1_r_el0_r) {
                        try pmap.page_insert(p.tt, srcpp, va, pmap.tte_ap_el1_r_el0_r);
                    } else if (pte & pmap.tte_ap_mask == pmap.tte_ap_el1_rw_el0_rw) {
                        const cow_pte = (flags - (flags & pmap.tte_ap_mask)) | pmap.tte_cow_read_only;
                        try pmap.page_insert(p.tt, srcpp, va, cow_pte);
                        try pmap.page_insert(proc.cur_proc.?.tt, srcpp, va, cow_pte);
                    } else unreachable;
                }
            }
        }
    }

    return p.pid;
}

fn proc_set_state(pid: usize, state: proc.ProcState) !void {
    const final_pid = if (pid == 0) proc.cur_proc.?.pid else pid;
    const p = if (proc.find(final_pid)) |p| p else return error.NotFound;
    p.state = state;
}

fn proc_pid() usize {
    return proc.cur_proc.?.pid;
}

fn page_alloc(dstpid: usize, dstva: usize, flags: usize) !void {
    const final_dstpid = if (dstpid == 0) proc.cur_proc.?.pid else dstpid;
    const dst = if (proc.find(final_dstpid)) |dst| dst else return error.NotFound;

    const pp = try pmap.page_alloc(true);
    try pmap.page_insert(dst.tt, pp, dstva, flags - pmap.tte_paddr(flags));
}

fn page_map(srcpid: usize, srcva: usize, dstpid: usize, dstva: usize, flags: usize) !void {
    const final_srcpid = if (srcpid == 0) proc.cur_proc.?.pid else srcpid;
    const final_dstpid = if (dstpid == 0) proc.cur_proc.?.pid else dstpid;
    const src = if (proc.find(final_srcpid)) |src| src else return error.NotFound;
    const dst = if (proc.find(final_dstpid)) |dst| dst else return error.NotFound;

    var src_tte: *pmap.TtEntry = undefined;
    const srcpp = if (pmap.page_lookup(src.tt, srcva, &src_tte)) |pp| pp else return error.BadValue;

    const final_flags = flags - pmap.tte_paddr(flags);
    // log("srcva: {x}, dstva: {x} cow: {b}, ap: {b}\n", .{ srcva, dstva, final_pte & pmap.tte_cow, get_bits(final_pte, pmap.tte_ap_off, pmap.tte_ap_len) });
    try pmap.page_insert(dst.tt, srcpp, dstva, flags);
}

fn page_unmap(dstpid: usize, dstva: usize) !void {
    const final_dstpid = if (dstpid == 0) proc.cur_proc.?.pid else dstpid;
    const dst = if (proc.find(final_dstpid)) |dst| dst else return error.NotFound;
    pmap.page_remove(dst.tt, dstva);
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
        Syscall.PROC_FORK => try proc_fork(),
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
