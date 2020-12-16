const std = @import("std");
const proc = @import("../proc.zig");
const pmap = @import("../pmap.zig");
const syscall = @import("syscall.zig");
usingnamespace @import("print.zig");

fn get_bits(val: usize, comptime off: usize, comptime len: usize) usize {
    return (val >> off) & ((1 << len) - 1);
}

fn get_l2tt() *volatile pmap.Tt {
    const il1: usize = (pmap.tt_entries - 1) << pmap.l1_off;
    const il2: usize = (pmap.tt_entries - 1) << pmap.l2_off;
    const il3: usize = (0) << pmap.l3_off;
    return @intToPtr(*volatile pmap.Tt, il1 | il2 | il3);
}

fn get_l3tt(i: usize) *volatile pmap.Tt {
    const il1: usize = (pmap.tt_entries - 1) << pmap.l1_off;
    const il2: usize = (0) << pmap.l2_off;
    const il3: usize = (i) << pmap.l3_off;
    return @intToPtr(*volatile pmap.Tt, il1 | il2 | il3);
}

fn duppage(dstpid: usize, va: usize, flags: usize) !void {
    const cow_pte = (1 << pmap.tte_valid_off) |
        (1 << pmap.tte_walk_off) |
        (1 << pmap.tte_af_off) |
        (@intCast(u64, pmap.tte_ap_el1_r_el0_r)) |
        @intCast(u64, pmap.tte_cow);

    if (flags & pmap.tte_ap_mask == pmap.tte_ap_el1_r_el0_r) {
        _ = try syscall.syscall5(
            @enumToInt(syscall.syscall.Syscall.PAGE_MAP),
            0,
            va,
            dstpid,
            va,
            flags,
        );
    } else {
        const read_flags = (flags - (flags & pmap.tte_ap_mask)) | pmap.tte_ap_el1_r_el0_r;
        _ = try syscall.syscall5(
            @enumToInt(syscall.syscall.Syscall.PAGE_MAP),
            0,
            va,
            dstpid,
            va,
            read_flags | cow_pte,
        );
        _ = try syscall.syscall5(
            @enumToInt(syscall.syscall.Syscall.PAGE_MAP),
            0,
            va,
            dstpid,
            va,
            read_flags | cow_pte,
        );
    }
}

pub fn fork() !usize {
    // create a new process
    // duplicate the current running process virtual memory, TODO: COW
    // allocate a new page for its stack then set its state to RUNNABLE
    const child = syscall.syscall0(@enumToInt(syscall.syscall.Syscall.PROC_FORK));
    if (child == 0) {
        return 0;
    } else {
        for (get_l2tt()) |l2tte, il3| {
            const ap = get_bits(l2tte, pmap.tte_ap_off, pmap.tte_ap_len);
            if (get_bits(l2tte, pmap.tte_valid_off, pmap.tte_valid_len) == pmap.tte_valid_valid) {
                for (get_l3tt(il3)) |pte, ip| {
                    if (get_bits(pte, pmap.tte_valid_off, pmap.tte_valid_len) == pmap.tte_valid_valid) {
                        const va = pmap.gen_laddr(0, il3, ip);
                        const flags = pte - pmap.tte_paddr(pte);
                        _ = try duppage(child, va, flags);
                    }
                }
            }
        }
        _ = try syscall.syscall2(
            @enumToInt(syscall.syscall.Syscall.PROC_SET_STATE),
            child,
            @enumToInt(proc.ProcState.RUNNABLE),
        );

        return child;
    }
}

pub fn kernel_space_fork() !usize {
    const child = try syscall.syscall0(@enumToInt(syscall.syscall.Syscall.PROC_FORK));
    if (child != 0) {
        _ = try syscall.syscall2(
            @enumToInt(syscall.syscall.Syscall.PROC_SET_STATE),
            child,
            @enumToInt(proc.ProcState.RUNNABLE),
        );
        _ = try syscall.syscall0(@enumToInt(syscall.syscall.Syscall.YIELD));
    }
    return child;
}
