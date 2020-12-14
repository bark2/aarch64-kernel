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

pub fn fork() !usize {
    // create a new process
    // duplicate the current running process virtual memory, TODO: COW
    // allocate a new page for its stack then set its state to RUNNABLE
    const child = try syscall.syscall0(@enumToInt(syscall.syscall.Syscall.PROC_ALLOC));
    if (child == 0)
        return 0;

    for (get_l2tt()) |l2tte, il3| {
        const ap = get_bits(l2tte, pmap.tte_ap_off, pmap.tte_ap_len);
        if (get_bits(l2tte, pmap.tte_valid_off, pmap.tte_valid_len) == pmap.tte_valid_valid and
            get_bits(l2tte, pmap.tte_ap_off, pmap.tte_ap_len) == pmap.tte_ap_el1_rw_el0_rw)
        {
            for (get_l3tt(il3)) |pte, ip| {
                if (get_bits(pte, pmap.tte_valid_off, pmap.tte_valid_len) == pmap.tte_valid_valid and
                    get_bits(pte, pmap.tte_ap_off, pmap.tte_ap_len) == pmap.tte_ap_el1_rw_el0_rw)
                {
                    const va = pmap.gen_laddr(0, il3, ip);
                    _ = try syscall.syscall5(
                        @enumToInt(syscall.syscall.Syscall.PAGE_MAP),
                        0,
                        va,
                        child,
                        va,
                        pmap.tte_ap_el1_rw_el0_rw << pmap.tte_ap_off,
                    );
                }
            }
        }
    }

    _ = try syscall.syscall3(
        @enumToInt(syscall.syscall.Syscall.PAGE_ALLOC),
        child,
        (1 << 30) - pmap.page_size,
        pmap.tte_ap_el1_rw_el0_rw << pmap.tte_ap_off,
    );
    _ = try syscall.syscall2(
        @enumToInt(syscall.syscall.Syscall.PROC_SET_STATE),
        child,
        @enumToInt(proc.ProcState.RUNNABLE),
    );

    return 0;
}
