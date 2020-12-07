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

pub const ProcState = enum {
    RUNNING,
    RUNNABLE,
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

        // TODO: use page_insert or map_region
        // allocate translation table
        var pp1 = try pmap.page_alloc(true);
        errdefer pmap.page_free(pp1);
        pp1.ref_count += 1;
        var tt = @ptrCast(*volatile pmap.Tt, pmap.page2kva(pp1));

        // allocate stack
        var pp2 = try pmap.page_alloc(true);
        errdefer pmap.page_free(pp2);
        pp2.ref_count += 1;
        var sp = @ptrToInt(pmap.page2kva(pp2));
        sp += pmap.page_size;
        // sp -= @sizeOf(exception.ExceptionFrame);
        // const tf = @intToPtr(*exception.ExceptionFrame, sp);
        // sp -= @sizeof(Context);

        self.* = Proc{
            .next = null,
            .pid = pid,
            .tt = @ptrCast(*pmap.Tt, tt),
            .ef = exception.ExceptionFrame{
                .xs = [_]u64{0} ** 29,
                .fp = 0,
                .lr = 0,
                .sp = pmap.phys_addr(sp),
                .elr = 0,
                .spsr = spsr,
            },
            .state = ProcState.RUNNABLE,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.tt) |tte1, itte1| {
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

        pmap.page_decref(pmap.pa2page(pmap.phys_addr(@ptrToInt(self.tt))));
        pmap.page_decref(pmap.pa2page(self.ef.sp));
    }

    pub fn load_elf(self: *Self, code: *align(8) u8) !void {
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

            log("pha: {x}\n", .{ph});
            try pmap.region_alloc(self.tt, ph.va, ph.memsz, 1);
            // arch.set_ttbr0_el1(@ptrToInt(self.tt));
            log("ph.va: {}\n", .{ph.va});
            pmap.user_memzero(self.tt, ph.va, ph.memsz);
            var blk_start = ph.offset % sd.block_size;
            var off: usize = 0;
            while (off < ph.filesz) {
                const lba = (ph.offset + off) / sd.block_size;
                const bytes = try sd.readblock(@truncate(u32, lba), &buf, 1);
                assert(bytes == sd.block_size); // TODO
                const len = std.math.min(ph.filesz - off, sd.block_size - blk_start);
                log("ph.va: {}\n", .{ph.va});
                pmap.user_memcpy(self.tt, ph.va + off, len, @ptrToInt(&buf[blk_start]));
                blk_start = (blk_start + len) % sd.block_size;
                off += len;
            }
        }

        log("entry: {x}\n", .{hdr.entry});
        self.ef.elr = hdr.entry;
    }

    pub fn run(self: *Self) noreturn {
        if (cur_proc) |p| {
            if (p.state == ProcState.RUNNING) {
                p.state = ProcState.RUNNABLE;
            }
        }

        cur_proc = self;
        self.state = ProcState.RUNNING;
        arch.set_ttbr0_el1(pmap.phys_addr(@ptrToInt(self.tt)));
        exception.pop_ef(0, &self.ef);
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
};

pub var pid_count: usize = undefined;
pub var cur_proc: ?*Proc = undefined;
// pub var procs: std.ArrayList(Proc) = undefined;
// pub var procs: std.SinglyLinkedList(Proc) = undefined;
var all_procs: []Proc = undefined;
pub var procs: ?*Proc = undefined;

var fixed: std.heap.FixedBufferAllocator = undefined;
var allocator: *Allocator = undefined;

pub fn init() Error!void {
    var page = try pmap.page_alloc(true); // Should not be freed thus ref_count is not inc
    var buffer = std.mem.span(@ptrCast(*[pmap.page_size]u8, pmap.page2kva(page)));
    fixed = std.heap.FixedBufferAllocator.init(buffer);
    allocator = &fixed.allocator;

    cur_proc = try create();
}

pub fn create() Error!*Proc {
    var p = try allocator.create(Proc);
    errdefer allocator.destroy(p);
    try p.init(pid_count);

    @setRuntimeSafety(false);
    if (p.ef.elr % @alignOf(elf.Elf) != 0) panic("wrong alignment for elf", null);
    try p.load_elf(@intToPtr(*align(@alignOf(elf.Elf)) u8, p.ef.elr));

    p.next = procs;
    procs = p;

    pid_count += 1;
    return p;
}

pub fn destory(pid: usize) void {
    // FIXME
    // find pid
    var ip = procs;
    while (ip != null and ip.?.pid != pid) : (ip = ip.?.next) {}

    if (ip) |p| {
        p.deinit();
        if (cur_proc == p) {
            cur_proc = null;
            schedule();
        }
    }
}

pub fn schedule() noreturn {
    var idle = if (cur_proc == null) procs else cur_proc.?;
    while ((cur_proc != null and idle != cur_proc) or (cur_proc == null and idle != null)) {
        if (idle.?.state == ProcState.RUNNABLE)
            idle.?.run();

        idle = idle.?.next;
        if (cur_proc != null and idle == null)
            idle = procs;
    }

    if (cur_proc) |p| {
        if (p.state == ProcState.RUNNING) p.run();
    }

    while (true) {
        asm volatile ("wfe");
    }
}
