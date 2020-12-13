const std = @import("std");
const proc = @import("../proc.zig");
const pmap = @import("../pmap.zig");
const syscall = @import("syscall.zig");
usingnamespace @import("print.zig");

fn get_bits(val: usize, comptime off: usize, comptime len: usize) usize {
    return (val >> off) & ((1 << len) - 1);
}

fn pde(i: usize) *volatile pmap.TtEntry {
    const vtta: usize = 0b1_1111_1111 << pmap.l2_off;
    const l2tta: usize = vtta + (0b1_1111_1111 << pmap.l3_off);
    const vtt = @intToPtr(*volatile pmap.Tt, vtta);
    const l2tt = @intToPtr(*volatile pmap.Tt, l2tta);
    return &l2tt[i];
}

fn pte(i: usize, j: usize) *volatile pmap.TtEntry {
    const vtta: usize = 0b1_1111_1111 << pmap.l2_off;
    const l3tta: usize = vtta + (i << pmap.l3_off);
    const l3tt = @intToPtr(*volatile pmap.Tt, l3tta);
    return &l3tt[j];
}

pub fn fork() !usize {
    // create a new process
    // duplicate the current running process virtual memory, TODO: COW
    // allocate a new page for its stack
    // set its pc value
    // var child = try syscall.syscall0(@enumToInt(syscall.syscall.Syscall.LIGHT_FORK));
    const vtta: usize = 0b1_1111_1111 << pmap.l2_off;
    const l2tta: usize = vtta + (0b1_1111_1111 << pmap.l3_off);
    const vtt = @intToPtr(*volatile pmap.Tt, vtta);
    const l2tt = @intToPtr(*volatile pmap.Tt, l2tta);

    var il2: usize = 0;
    while (il2 < 511) {
        const l2tte = pde(il2).*;
        if (get_bits(l2tte, pmap.tte_valid_off, pmap.tte_valid_len) == pmap.tte_valid_valid and
            get_bits(l2tte, pmap.tte_ap_off, pmap.tte_ap_len) == pmap.tte_ap_el1_rw_el0_rw)
        {
            try print("l2vtt[{}]: {x}\n", .{ il2, pmap.tte_paddr(l2tte) });
            var il3: usize = 0;
            while (il3 < 512) {
                try print("l3tt[{}]: \n", .{il3});
                const l3tte = pte(il2, il3).*;
                if (get_bits(l3tte, pmap.tte_valid_off, pmap.tte_valid_len) == pmap.tte_valid_valid) {
                    // try print("l2vtt[{}]: {b}\n", .{ il2, pmap.tte_paddr(l2tte) });
                }
            }
        }
    }

    // while (il2 < 512) : (il2 += 1) {
    // var il3: usize = 0;
    // while (il3 < pmap.l3_off) : (il3 += 8) {
    // const tte = @intToPtr(*allowzero volatile pmap.TtEntry, vtt + (il2 << pmap.l3_off) + il3);
    // if (get_bits(tte.*, pmap.tte_valid_off, pmap.tte_valid_len) == pmap.tte_valid_valid) {
    // try print("vtt[{}][{}]: {b}\n", .{ il2, il3, tte });
    // }
    // }
    // }

    return 0;
}
