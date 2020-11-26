const std = @import("std");
const mem = std.mem;
const pmap = @import("pmap.zig");
const arch = @import("arch.zig");
const user = @import("user.zig");
const exception = @import("exception.zig");
const uart = @import("uart.zig");
const log = uart.log;
usingnamespace @import("common.zig");
const Allocator = std.mem.Allocator;

pub const ProcState = enum {
    RUNNING,
    RUNNABLE,
};

const Proc = struct {
    const Self = @This();
    pid: usize,
    tt: *pmap.Tt,
    ef: exception.ExceptionFrame,
    state: ProcState,

    pub fn load_elf(self: *Self, elf: *u8) void {}

    pub fn run(self: *Self) noreturn {
        if (cur_proc) |p| {
            if (p.state == ProcState.RUNNING) {
                p.state = ProcState.RUNNABLE;
            }
        }

        cur_proc = self;
        self.state = ProcState.RUNNING;
        exception.pop_ef(0, &self.ef);
    }
};

pub var pid_count: usize = undefined;
pub var cur_proc: ?*Proc = undefined;
pub var procs: std.ArrayList(Proc) = undefined;

var fixed: std.heap.FixedBufferAllocator = undefined;
var allocator: *Allocator = undefined;

pub fn init() Error!void {
    var page = try pmap.page_alloc(true); // Should not be freed thus ref_count is not inc
    var buffer = std.mem.span(@ptrCast(*[pmap.page_size]u8, pmap.page2kva(page)));
    fixed = std.heap.FixedBufferAllocator.init(buffer);
    allocator = &fixed.allocator;

    pid_count = 0;
    cur_proc = null;
    procs = std.ArrayList(Proc).init(allocator);
}

pub fn free(pid: usize) void {
    var opt_proc_idx: ?usize = null;
    for (procs.items) |p, i| {
        log("proc({}): {}\n", .{ i, p });
        if (p.pid == pid) {
            opt_proc_idx = i;
            break;
        }
    }

    var proc: Proc = undefined;
    if (opt_proc_idx) |proc_idx| {
        proc = procs.swapRemove(proc_idx);
    } else {
        log("free: not found {}\n", .{pid});
        return;
    }

    log("freeing {}\n", .{pid});
    for (proc.tt) |tte1, itte1| {
        // TODO: for 32bit of va only the first 4 entries could be in use
        if (itte1 == 4)
            break;
        if ((tte1 & pmap.tte_valid_off) != 1)
            continue;

        const pa1 = pmap.tte_addr(@intToPtr(*volatile u64, tte1));
        const tt2 = @intToPtr(*volatile pmap.Tt, pmap.kern_addr(pa1));
        for (tt2) |tte2, itte2| {
            if ((tte2 & pmap.tte_valid_off) != 1)
                continue;

            const pa2 = pmap.tte_addr(@intToPtr(*volatile u64, tte2));
            const tt3 = @intToPtr(*align(pmap.page_size) volatile pmap.Tt, pmap.kern_addr(pa2));
            for (tt3) |tte3, itte3| {
                if ((tte3 & pmap.tte_valid_off) == 1) {
                    const va = pmap.gtaddr(@truncate(u2, itte1), @truncate(u9, itte2), @truncate(u9, itte3));
                    // FIXME: after we allocate code region
                    // pmap.page_remove(tt3, @intToPtr(*align(pmap.page_size) u8, va));
                }
            }

            pmap.page_decref(pmap.pa2page(pmap.phys_addr(@ptrToInt(tt3))));
        }

        pmap.page_decref(pmap.pa2page(pmap.phys_addr(@ptrToInt(tt2))));
    }

    pmap.page_decref(pmap.pa2page(pmap.phys_addr(@ptrToInt(proc.tt))));
}

pub fn alloc() Error!*Proc {
    var proc = try procs.addOne();
    errdefer _ = procs.pop();

    var pp1 = try pmap.page_alloc(true);
    errdefer pmap.page_free(pp1);
    pp1.ref_count += 1;
    var tt = @ptrCast(*volatile pmap.Tt, pmap.page2kva(pp1));
    try pmap.map_region(tt, 0, (4 * 1024 - 1) * pmap.page_size, 0, 1); // hard coded for now
    arch.set_ttbr0_el1(pmap.phys_addr(@ptrToInt(tt)));

    var pp2 = try pmap.page_alloc(true);
    errdefer pmap.page_free(pp2);
    pp2.ref_count += 1;
    var stack = pmap.page2kva(pp2);

    var spsr = arch.spsr_el1();
    spsr &= ~@intCast(usize, 0x1); // return to EL0
    spsr &= ~@intCast(usize, 0x1 << 4); // return to Aarch64

    // FIXME: after setting ttbr0 cannot write to low memory(phys memory)
    // log("user.main: {}\n", .{user.main});

    proc.* = Proc{
        .pid = pid_count,
        .tt = @ptrCast(*pmap.Tt, tt),
        .ef = exception.ExceptionFrame{
            .xs = [_]u64{0} ** 29,
            .fp = 0,
            .lr = 0,
            .sp = pmap.phys_addr(@ptrToInt(stack) + pmap.page_size),
            .elr = pmap.phys_addr(@ptrToInt(user.main)),
            .spsr = spsr,
        },
        .state = ProcState.RUNNABLE,
    };
    log("proc: {}\n", .{proc.*});
    log("list[0]: {}\n", .{procs.items[0]});

    pid_count += 1;
    return proc;
}

pub fn create(elf: *u8) Error!*Proc {
    var proc = try alloc();
    // proc.load_elf(elf);
    return proc;
}

pub fn schedule() noreturn {
    while (true) {
        asm volatile ("wfe");
    }
}
