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

const Context = packed struct {
    xs: [10]usize,
    fp: usize,
    sp: usize,
    pc: usize,
};

const Proc = struct {
    const Self = @This();
    ef: exception.ExceptionFrame,
    next: ?*Proc,
    pid: usize,
    tt: *align(pmap.page_size) volatile pmap.Tt,
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
            .state = ProcState.NOT_RUNNABLE,
        };
    }

    pub fn deinit(self: *Self) void {
        const Ttp = *align(pmap.page_size) volatile pmap.Tt;
        const tt2 = @intToPtr(Ttp, pmap.kern_addr(pmap.tte_paddr(self.tt[0])));
        for (tt2) |tte2, itte2| {
            if ((tte2 & (1 << pmap.tte_valid_off)) != 1)
                continue;

            const pa3 = pmap.tte_paddr(tte2);
            // log("tte2: {x}, {x}\n", .{ tte2, ((tte2 >> 12) & ((1 << 36) - 1)) << 12 });
            const tt3 = @intToPtr(Ttp, pmap.kern_addr(pa3));
            for (tt3) |tte3, itte3| {
                if (tte3 & pmap.tte_valid_mask == pmap.tte_valid_valid) {
                    // log("trying to remove: [{}][{}]: {x}, pa: {x}\n", .{ itte2, itte3, pmap.gen_laddr(0, itte2, itte3), pmap.page2pa(pmap.page_lookup(self.tt, pmap.gen_laddr(0, itte2, itte3), null).?) });
                    pmap.page_remove(self.tt, pmap.gen_laddr(0, itte2, itte3));
                }
            }

            pmap.page_decref(pmap.pa2page(pa3));
        }

        pmap.page_decref(pmap.pa2page(pmap.tte_paddr(self.tt[0])));
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
        const Ttp = *align(pmap.page_size) volatile pmap.Tt;

        self.tt[pmap.tt_entries - 1] = pmap.phys_addr(@ptrToInt(self.tt)) | pmap.tte_read_only;

        // initialize user stack
        const sp_top = (1 << 30);
        try pmap.region_alloc(self.tt, sp_top - pmap.page_size, pmap.page_size, pmap.tte_ap_el1_rw_el0_rw);
        self.ef.sp = sp_top;

        // for (@intToPtr(Ttp, pmap.kern_addr(pmap.tte_paddr(self.tt[0])))) |tte, i| {
        //     if (get_bits(tte, pmap.tte_valid_off, pmap.tte_valid_len) == pmap.tte_valid_valid) {
        //         log("[{}]: 0x{x}\n", .{ i, pmap.tte_paddr(tte) });
        //         const l3_tt = @intToPtr(*volatile pmap.Tt, pmap.kern_addr(pmap.tte_paddr(tte)));
        //         for (l3_tt) |tte3, j| {
        //             if (get_bits(tte3, pmap.tte_valid_off, pmap.tte_valid_len) == pmap.tte_valid_valid)
        //                 log("{}[{}]: {b}, 0x{x}\n", .{ i, j, tte3, pmap.tte_paddr(tte3) });
        //         }
        //     }
        // }
    }
};

pub var pid_count: usize = undefined;
pub export var cur_proc: ?*Proc = undefined;
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
    p.state = ProcState.RUNNABLE;
    return p;
}

pub fn find(pid: usize) ?*Proc {
    var ip = procs;
    while (ip != null and ip.?.pid != pid) : (ip = ip.?.next) {}
    return ip;
}

pub fn destory(p: *Proc) void {
    var ip = procs;
    if (ip.?.pid != p.pid) {
        while (ip.?.next != null and ip.?.next.?.pid != p.pid) : (ip = ip.?.next) {}
        ip.?.next = ip.?.next.?.next;
    } else {
        procs = procs.?.next;
    }

    if (cur_proc == p)
        cur_proc = null;

    p.deinit();
    allocator.destroy(p);
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

pub fn page_owners(pp: *pmap.PageInfo) void {
    if (procs == null) return;

    var p = procs;
}

pub fn schedule() noreturn {
    var idle = if (cur_proc == null) procs else if (cur_proc.?.next == null) procs else cur_proc.?.next;
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
