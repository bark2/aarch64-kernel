const std = @import("std");
const mem = std.mem;
const pmap = @import("pmap.zig");
const arch = @import("arch.zig");
const user = @import("user.zig");
const exception = @import("exception.zig");
const uart = @import("uart.zig");
const elf = @import("elf.zig");
const log = uart.log;
usingnamespace @import("common.zig");
const Allocator = std.mem.Allocator;
const sd = @import("sd.zig");
const initrd = @import("initrd.zig");

pub const Error = error{ OutOfMemory, NotFound, NotAnElf };

pub const ProcState = enum {
    RUNNING,
    RUNNABLE,
    NOT_RUNNABLE,
};

const Context = struct {
    xs: [10]usize,
    fp: usize,
    sp: usize,
    pc: usize,
};

const Proc = struct {
    const Self = @This();
    next: ?*Proc,
    pid: usize,
    tt: *align(pmap.page_size) volatile pmap.Tt,
    ef: exception.ExceptionFrame,
    state: ProcState,

    fn init(self: *Self, pid: usize) Error!void {
        var spsr = arch.spsr_el1();
        spsr &= ~@intCast(usize, 0x1); // return to EL0
        spsr &= ~@intCast(usize, 0x1 << 4); // return to Aarch64

        // allocate translation table
        var pp1 = try pmap.page_alloc(true);
        errdefer pmap.page_free(pp1);
        pp1.ref_count += 1;
        var tt = @ptrCast(*volatile pmap.Tt, pmap.page2kva(pp1));

        self.* = Proc{
            .next = null,
            .pid = pid,
            .tt = @ptrCast(*pmap.Tt, tt),
            .ef = exception.ExceptionFrame{
                .xs = [_]u64{0} ** 29,
                .fp = 0,
                .lr = 0,
                .sp = 0,
                .elr = 0,
                .spsr = spsr,
            },
            .state = ProcState.RUNNABLE,
        };
    }

    pub fn deinit(self: *Self) void {
        const Ttp = *align(pmap.page_size) volatile pmap.Tt;
        const tt2 = @intToPtr(Ttp, pmap.kern_addr(pmap.tte_paddr(self.tt[0])));
        for (tt2) |tte2, itte2| {
            if ((tte2 & (1 << pmap.tte_valid_off)) != 1)
                continue;

            const pa2 = pmap.tte_paddr(tte2);
            // log("tte2: {x}, {x}\n", .{ tte2, ((tte2 >> 12) & ((1 << 36) - 1)) << 12 });
            const tt3 = @intToPtr(Ttp, pmap.kern_addr(pa2));
            for (tt3) |tte3, itte3| {
                if ((tte3 & (1 << pmap.tte_valid_off)) == 1) {
                    const pa3 = pmap.tte_paddr(tte3);
                    const va = @intToPtr(*allowzero u8, pmap.gen_laddr(0, itte2, itte3));
                    log("[{}][{}]: va: {}, pa: {x}\n", .{ itte2, itte3, va, pa3 });
                    const p3 = pmap.pa2page(pa3);
                    if (p3.ref_count > 0)
                        pmap.page_decref(p3);
                    tt3[itte3] = 0;
                    // pmap.page_remove(self.tt, va);
                }
            }

            // log("page_decref(2): {x}\n", .{pa2});
            pmap.page_remove(self.tt, @ptrCast(*allowzero u8, tt2));
        }

        pmap.page_remove(self.tt, @ptrCast(*allowzero u8, tt2));
        pmap.page_decref(pmap.pa2page(pmap.phys_addr(@ptrToInt(self.tt))));
    }

    pub fn load_elf(self: *Self) !void {
        @setRuntimeSafety(false);
        // read first block of user code from disk
        const blocks_per_page = pmap.page_size / sd.block_size;
        var elf_buf: [pmap.page_size]u8 align(@alignOf(elf.Elf)) = undefined;
        _ = try sd.readblock(0, &elf_buf, blocks_per_page);

        // user code is valid elf
        const hdr = @ptrCast(*elf.Elf, @alignCast(@alignOf(elf.Elf), &elf_buf));
        if (hdr.magic != elf.ELF_MAGIC)
            return Error.NotAnElf;
        assert(hdr.ehsize < sd.block_size); // TODO

        var buf: [pmap.page_size]u8 align(@alignOf(elf.Elf)) = undefined;
        var pheaders = @intToPtr([*]elf.Proghdr, @ptrToInt(hdr) + hdr.phoff)[0..hdr.phnum];
        for (pheaders) |*ph| {
            if (ph.type != elf.ELF_PROG_LOAD) continue;

            // log("ph: {x}\n", .{ph});
            try pmap.region_alloc(self.tt, ph.va, ph.memsz, pmap.tte_ap_el1_rw_el0_rw);
            pmap.user_memzero(self.tt, ph.va, ph.memsz);
            var blk_start = ph.offset % sd.block_size;
            var off: usize = 0;
            while (off < ph.filesz) {
                const lba = (ph.offset + off) / sd.block_size;
                const bytes = try sd.readblock(@truncate(u32, lba), &buf, 1);
                assert(bytes == sd.block_size); // TODO
                const len = std.math.min(ph.filesz - off, sd.block_size - blk_start);
                pmap.user_memcpy(self.tt, ph.va + off, len, @ptrToInt(&buf[blk_start]));
                blk_start = (blk_start + len) % sd.block_size;
                off += len;
            }
        }

        // log("entry: {x}\n", .{hdr.entry});
        self.ef.elr = hdr.entry;
    }

    fn init_virtual_memory(self: *Self) !void {
        const vtta = (1 << 30) - pmap.page_size;
        const all_read_base_entry = (1 << pmap.tte_valid_off) |
            (1 << pmap.tte_walk_off) |
            (1 << pmap.tte_af_off) |
            (@intCast(u64, pmap.tte_ap_el1_r_el0_r) << pmap.tte_ap_off);

        const l2_tt_pa = pmap.tte_paddr(self.tt[0]);
        const l2_tt = @intToPtr(*volatile pmap.Tt, pmap.kern_addr(l2_tt_pa));
        l2_tt[pmap.tt_entries - 1] = l2_tt_pa | all_read_base_entry;
        log("l2_tt_pa: {x}\n", .{l2_tt_pa});

        // initialize user stack
        const sp_top = (1 << 30) - pmap.page_size;
        try pmap.region_alloc(self.tt, sp_top - pmap.page_size, pmap.page_size, pmap.tte_ap_el1_rw_el0_rw);
        self.ef.sp = sp_top;

        for (l2_tt) |tte, i| {
            if (i == pmap.tt_entries - 1)
                continue;
            if (get_bits(tte, pmap.tte_valid_off, pmap.tte_valid_len) == pmap.tte_valid_valid) {
                const l3_tt = @intToPtr(*volatile pmap.Tt, pmap.kern_addr(pmap.tte_paddr(tte)));
                for (l3_tt) |tte3, j| {
                    if (get_bits(tte3, pmap.tte_valid_off, pmap.tte_valid_len) == pmap.tte_valid_valid)
                        log("{}[{}]: {b}, 0x{x}\n", .{ i, j, tte3, pmap.tte_paddr(tte3) });
                }
            }
        }

        // const tte = @intToPtr(*volatile pmap.Tt, pmap.kern_addr(pmap.tte_paddr(l2_tt[510])))[346];
        // if (get_bits(tte, pmap.tte_valid_off, pmap.tte_valid_len) == pmap.tte_valid_valid)
        // log("{b}, 0x{x}\n", .{ tte, pmap.tte_paddr(tte) });
        var tte: *pmap.TtEntry = undefined;
        var pp = pmap.page_lookup(self.tt, @intToPtr(*allowzero u8, 0x3fe00000), &tte);
        log("tte: {x} {}\n", .{ pmap.tte_paddr(tte.*), (tte.* >> pmap.tte_ap_off) & 3 });
    }
};

pub var pid_count: usize = undefined;
pub var cur_proc: ?*Proc = undefined;
var all_procs: []Proc = undefined;
pub var procs: ?*Proc = undefined;

var fixed: std.heap.FixedBufferAllocator = undefined;
var allocator: *Allocator = undefined;

pub fn init() !void {
    var page = try pmap.page_alloc(true); // Should not be freed thus ref_count is not inc
    var buffer = std.mem.span(@ptrCast(*[pmap.page_size]u8, pmap.page2kva(page)));
    fixed = std.heap.FixedBufferAllocator.init(buffer);
    allocator = &fixed.allocator;

    cur_proc = try create();
}

pub fn alloc() !*Proc {
    var p = try allocator.create(Proc);
    errdefer allocator.destroy(p);
    try p.init(pid_count);

    p.next = procs;
    procs = p;

    pid_count += 1;
    return p;
}

pub fn create() !*Proc {
    var p = try alloc();
    assert(p.ef.elr % @alignOf(elf.Elf) == 0);
    try p.load_elf();
    try p.init_virtual_memory();
    return p;
}

pub fn find(pid: usize) ?*Proc {
    var ip = procs;
    while (ip != null and ip.?.pid != pid) : (ip = ip.?.next) {}
    return ip;
}

pub fn destory(pid: usize) !void {
    if (find(pid)) |p| {
        p.deinit();
        if (cur_proc == p)
            cur_proc = null;
    } else {
        return Error.NotFound;
    }
}

pub fn run(p: *Proc) noreturn {
    if (cur_proc) |cp| {
        if (cp.state == ProcState.RUNNING) {
            cp.state = ProcState.RUNNABLE;
        }
    }

    cur_proc = p;
    cur_proc.?.state = ProcState.RUNNING;
    arch.set_ttbr0_el1(pmap.phys_addr(@ptrToInt(p.tt)));
    exception.pop_ef(0, &cur_proc.?.ef);
}

fn switch_context(prev: *Context, next: *Context) noreturn {
    asm volatile (
        \\  mov    x10, #THREAD_CPU_CONTEXT
        \\  add    x8, x0, x10
        \\  mov    x9, sp
        \\  stp    x19, x20, [x8], #16        // store callee-saved registers
        \\  stp    x21, x22, [x8], #16
        \\  stp    x23, x24, [x8], #16
        \\  stp    x25, x26, [x8], #16
        \\  stp    x27, x28, [x8], #16
        \\  stp    x29, x9, [x8], #16
        \\  str    x30, [x8]
        \\  add    x8, x1, x10
        \\  ldp    x19, x20, [x8], #16        // restore callee-saved registers
        \\  ldp    x21, x22, [x8], #16
        \\  ldp    x23, x24, [x8], #16
        \\  ldp    x25, x26, [x8], #16
        \\  ldp    x27, x28, [x8], #16
        \\  ldp    x29, x9, [x8], #16
        \\  ldr    x30, [x8]
        \\  mov    sp, x9
        \\  ret
        :
        : [prev] "x0" (prev),
          [next] "x1" (next)
    );
}

pub fn schedule() noreturn {
    var idle = if (cur_proc == null) procs else cur_proc.?;
    while ((cur_proc != null and idle != cur_proc) or (cur_proc == null and idle != null)) {
        if (idle.?.state == ProcState.RUNNABLE)
            run(idle.?);

        idle = idle.?.next;
        if (cur_proc != null and idle == null)
            idle = procs;
    }

    if (cur_proc) |p| {
        if (p.state == ProcState.RUNNING) run(p);
    }

    while (true) {
        asm volatile ("wfe");
    }
}
