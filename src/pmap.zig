const std = @import("std");
// const std = @import("gpio.zig");
usingnamespace @import("common.zig");
const pow = std.math.pow;
const arch = @import("arch.zig");
const uart = @import("uart.zig");
const log = uart.log;

pub const Error = error{OutOfMemory};

// https://armv8-ref.codingbelief.com/en/chapter_d4/d43_3_memory_attribute_fields_in_the_vmsav8-64_translation_table_formats_descriptors.html

// const TtEntry = packed struct {
//     valid: u1 = 0, // [0]
//     walk: u1 = 0, // [1]
//     indx: u3 = 0, //  [2:4]
//     ns: u1 = 0, // security bit (EL3 or Secure EL1), [5]
//     ap: u2 = 0, // access permission, [6:7]
//     sh: u2 = 0, // shareable attribute, [8:9]
//     af: u1 = 0, // access flag, [10]
//     ng: u1 = 0, // not global, [11]
//     addr: u36 = 0, // [12:47]
//     res1: u2 = 0, // [48:49]
//     gp: u1 = 0, // [50]
//     dbm: u1 = 0, // [51]
//     continuous: u1 = 0, // [52]
//     pxn: u1 = 0, // [53]
//     uxn: u1 = 0, // [54]
//     software_use: u4 = 0, // [55:58]
//     ignored: u5 = 0, // [59:63]
// };

pub const TtEntry = u64;
pub const tte_valid_off = 0;
pub const tte_valid_len = 1;
pub const tte_valid_valid = 1;
pub const tte_walk_off = 1;
pub const tte_indx_off = 2;
pub const tte_ns_off = 5;
pub const tte_ap_off = 6;
pub const tte_ap_len = 2;
const tte_sh_off = 8;
pub const tte_af_off = 10;
const tte_ng_off = 11;
pub const tte_addr_off = 12;
pub const tte_ap_el1_rw_el0_none = 0;
pub const tte_ap_el1_rw_el0_rw = 1;
pub const tte_ap_el1_r_el0_none = 2;
pub const tte_ap_el1_r_el0_r = 3;
pub const tte_cow = 1 << 58;

pub fn tte_paddr(tte: TtEntry) usize {
    return ((tte >> tte_addr_off) & ((1 << 36) - 1)) << l3_off;
}

const TcrEl1 = packed struct {
    t0sz: u6 = 0, // number of the most significat bits that are not used
    reserved1: u1 = 0,
    epd0: u1 = 0,
    irgn0: u2 = 0,
    orgn0: u2 = 0,
    sh0: u2 = 0,
    tg0: u2 = 0, // translation granule size
    t1sz: u6 = 0, // number of the most significat bits that are not used
    a1: u1 = 0,
    epd1: u1 = 0,
    irgn1: u2 = 0,
    orgn1: u2 = 0,
    sh1: u2 = 0,
    tg1: u2 = 0, // translation granule size
    ips: u3 = 0,
    reserved3: u1 = 0,
    as: u1 = 0,
    tbi0: u1 = 0,
    tbi1: u1 = 0,
    reserved4: u25 = 0,

    pub const tg0_4k = 0;
    pub const tg1_4k = 2;
    pub const txsz_32b = 64 - 32;
    pub const txsz_39b = 64 - 39;
    pub const txsz_48b = 64 - 48;
};

const PhysAddr = usize;

const page_bits = 12;
pub const page_size = 1 << page_bits;
pub const kern_base = 0xffffffff << 32;
const page_count: usize = 4 * 1024; // 16MB Physical Memory | 4K Pages

pub const PageInfo = struct {
    next: ?*PageInfo,
    ref_count: u32,
};
pub const Page = [*]align(page_size) u8;

pub const tt_entries = page_size / @sizeOf(TtEntry);
pub const Tt = [tt_entries]TtEntry;

extern fn set_ttbr1_and_tcr(_: *align(page_size) volatile Tt, _: usize, kern_base: usize) void;

// These variables are set in pmap.init()
pub var kern_tt: *align(page_size) volatile Tt = undefined; // Kernel's initial page directory
var pages: *[page_count]PageInfo = undefined; // Physical page state array
var page_free_list: ?*PageInfo = null; // Free list of physical pages

// Initialize nextfree if this is the first time.
// '__end' is a magic symbol automatically generated by the linker,
// which points to the end of the kernel's bss segment:
// the first virtual address that the linker did *not* assign
// to any kernel code or global variables.
extern var __end: u8;
var nextfree: PhysAddr = undefined;

pub fn init() Error!void {
    // initialize pages and pages_free_list
    nextfree = round_up(phys_addr(@ptrToInt(&__end)), page_size);
    pages = @ptrCast(@TypeOf(pages), boot_alloc(page_count * @sizeOf(PageInfo)));
    @memset(@ptrCast([*]volatile u8, pages), 0, @sizeOf(@TypeOf(pages.*)));

    // create initial page directory.
    kern_tt = @ptrCast(@TypeOf(kern_tt), boot_alloc(@sizeOf(@TypeOf(kern_tt))));
    @memset(@ptrCast([*]volatile u8, kern_tt), 0, @sizeOf(@TypeOf(kern_tt)));
    // kern_pgdir[PDX(UVPT)] = PADDR(kern_pgdir) | PTE_U | PTE_P;

    pages_init();

    try boot_map_region(kern_tt, kern_base, (page_count - 1) * page_size, 0, 0);
    // try boot_map_region(kern_tt, 0, (page_count - 1) * page_size, 0, 0);
    try boot_map_region(kern_tt, uart.MMIO_BASE, 0x1000000, uart.MMIO_BASE, 0);

    set_ttbr1_and_tcr(kern_tt, @bitCast(usize, TcrEl1{
        .t0sz = TcrEl1.txsz_39b,
        .t1sz = TcrEl1.txsz_32b,
        .tg0 = TcrEl1.tg0_4k,
        .tg1 = TcrEl1.tg1_4k,
    }), kern_base);
}

// If n>0, allocates enough pages of contiguous physical memory to hold 'n'
// bytes.  Doesn't initialize the memory.  Returns a kernel virtual address.
//
// If n==0, returns the address of the next free page without allocating
// anything.
//
// If we're out of memory, boot_alloc should panic.
// This function may ONLY be used during initialization,
// before the page_free_list list has been set up.
fn boot_alloc(n: u64) Page {
    if (nextfree + n >= page_count * page_size)
        std.builtin.panic("boot_alloc: out of memory\n", null);

    const next_free_page = @intToPtr(Page, kern_addr(nextfree));
    nextfree = round_up(nextfree + n, page_size);
    // log("(boot_alloc) next_free_page: {x}, nextfree: {x}\n", .{ next_free_page, nextfree });
    return next_free_page;
}

// initialize page_free_list and pages reference count
fn pages_init() void {
    var pa = @intCast(isize, (page_count - 1) * page_size);
    while (pa >= 0) : (pa -= page_size) {
        const i = @intCast(usize, pa) >> page_bits;
        if (pa <= phys_addr(@ptrToInt(boot_alloc(0)))) {
            pages[i].next = null;
            continue;
        }

        // if (i % (16 * 16) == 0)
        // log("{}\n", .{page2kva(&pages[i])});
        pages[i].ref_count = 0;
        pages[i].next = page_free_list;
        page_free_list = &pages[i];
    }
}

// --------------------------------------------------------------
// Tracking of physical pages.
// The 'pages' array has one 'struct PageInfo' entry per physical page.
// Pages are reference counted, and free pages are kept on a linked list.
// --------------------------------------------------------------

// Allocates a physical page.  If (alloc_flags & ALLOC_ZERO), fills the entire
// returned physical page with '\0' bytes.  Does NOT increment the reference
// count of the page - the caller must do these if necessary (either explicitly
// or via page_insert).
//
// Returns NULL if out of free memory.
pub fn page_alloc(alloc_zero: bool) Error!*PageInfo {
    if (page_free_list) |*page_free_list_| {
        var next_free_page = page_free_list_.*;
        page_free_list = page_free_list_.*.next;
        next_free_page.next = null;
        // log("page_alloc: {}\n", .{page2kva(next_free_page)});
        if (alloc_zero)
            @memset(@ptrCast([*]u8, page2kva(next_free_page)), 0, page_size);
        return next_free_page;
    }

    // log("page_alloc: out of memory\n", .{});
    return Error.OutOfMemory;
}

// Return a page to the free list.
// (This function should only be called when pp->pp_ref reaches 0.)
pub fn page_free(p: *PageInfo) void {
    log("free: {x}\n", .{page2pa(p)});
    p.*.next = page_free_list;
    page_free_list = p;
}

// Decrement the reference count on a page,
// freeing it if there are no more refs.
pub fn page_decref(p: *PageInfo) void {
    assert(p.ref_count > 0);
    p.ref_count -= 1;
    if (p.ref_count == 0) {
        page_free(p);
    } else {
        log("not freed: {x}\n", .{page2pa(p)});
    }
}

// Given 'pgdir', a pointer to a page directory, pgdir_walk returns
// a pointer to the page table entry (PTE) for linear address 'va'.
// This requires walking the two-level page table structure.
//
// The relevant page table page might not exist yet.
// If this is true, and create == false, then pgdir_walk returns NULL.
// Otherwise, pgdir_walk allocates a new page table page with page_alloc.
//    - If the allocation fails, pgdir_walk returns NULL.
//    - Otherwise, the new page's reference count is incremented,
//	the page is cleared,
//	and pgdir_walk returns a pointer into the new page table page.
//
// Hint 1: you can turn a Page * into the physical address of the
// page it refers to with page2pa() from kern/pmap.h.
//
// Hint 2: the x86 MMU checks permission bits in both the page directory
// and the page table, so it's safe to leave permissions in the page
// directory more permissive than strictly necessary.
//
// Hint 3: look at inc/mmu.h for useful macros that mainipulate page
// table and page directory entries.
pub fn walk(tt: *align(page_size) volatile Tt, va: usize, create: bool) Error!?*TtEntry {
    // log("va: {}\n", .{va});
    var l1_tte = &tt[l1x(va)];
    // log("walk: {x} {x} {x}\n", .{ va, l1x(@ptrToInt(va)), l2x(@ptrToInt(va)) });
    if ((l1_tte.* >> tte_valid_off) & 0x1 == 0) {
        if (!create)
            return null;

        // allocate a new translation table
        var pp = try page_alloc(true);
        // log("alloc l1: {}\n", .{page2pa(pp)});
        pp.ref_count += 1;
        l1_tte.* = page2pa(pp);
        l1_tte.* |= (1 << tte_valid_off);
        l1_tte.* |= (1 << tte_walk_off);
        l1_tte.* |= (1 << tte_af_off);
        l1_tte.* |= (tte_ap_el1_rw_el0_rw << tte_ap_off);
        // l1_tte.* = TtEntry{
        // .valid = 1,
        // .walk = 1,
        // .addr = @truncate(u36, @ptrToInt(page2pa(pp)) >> page_bits),
        // };
    }
    // log("l1x: {}, l1_tte: {x}\n", .{ l1x(@ptrToInt(va)), l1_tte.* });

    var l2_tt = @intToPtr(*Tt, kern_addr(tte_paddr(l1_tte.*)));
    var l2_tte = &l2_tt[l2x(va)];
    if ((l2_tte.* >> tte_valid_off) & 0x1 == 0) {
        if (!create)
            return null;

        // allocate a new translation table
        var pp = try page_alloc(true);
        // log("alloc l2: {}\n", .{page2pa(pp)});
        pp.ref_count += 1;
        l2_tte.* = page2pa(pp);
        l2_tte.* |= (1 << tte_valid_off);
        l2_tte.* |= (1 << tte_walk_off);
        l2_tte.* |= (1 << tte_af_off);
        l2_tte.* |= (tte_ap_el1_rw_el0_rw << tte_ap_off);
        // l2_tte.* = 0;
        // @ptrCast(*u64, l2_tte).* |= 1 << tte_valid_off;
        // @ptrCast(*u64, l2_tte).* |= 1 << tte_walk_off;
        // @ptrCast(*u64, l2_tte).* |= page2pa(pp);
        // l2_tte.* = TtEntry{
        // .valid = 1,
        // .walk = 1,
        // .addr = @truncate(u36, @ptrToInt(page2pa(pp)) >> page_bits),
        // };
    }
    // log("l2x: {}, l2_tte: {x}\n", .{ l2x(@ptrToInt(va)), l2_tte.* });

    var l3_tt = @intToPtr(*Tt, kern_addr(tte_paddr(l2_tte.*)));
    return &l3_tt[l3x(va)];
}

// Map [va, va+size) of virtual address space to physical [pa, pa+size)
// in the page table rooted at pgdir.  Size is a multiple of PGSIZE, and
// va and pa are both page-aligned.
// Use permission bits perm|PTE_P for the entries.
//
// This function is only intended to set up the ``static'' mappings
// above UTOP. As such, it should *not* change the pp_ref field on the
// mapped pages.
fn boot_map_region(tt: *align(page_size) volatile Tt, va: usize, size: usize, pa: PhysAddr, _: u2) Error!void {
    @setRuntimeSafety(false);
    assert(va == round_up(va, page_size));
    assert(pa == round_up(pa, page_size));
    assert(size % page_size == 0);

    var off: usize = 0;
    while (off < size) : (off += (1 << l3_off)) {
        // log("off: {}\n", .{off});
        if (try walk(tt, va + off, true)) |tte| {
            tte.* = pa + off;
            tte.* |= 1 << tte_valid_off;
            tte.* |= 1 << tte_walk_off;
            tte.* |= 1 << tte_af_off;
        }
        // log("{x}\n", .{tte.*});
    }
}

fn set_direct_tt_l2andl3(l2_tt: *[tt_entries]TtEntry, l3_tts: *[tt_entries]Tt, tcr_el1: *TcrEl1) void {
    log("set_direct_tt:\n", .{});
    tcr_el1.* = TcrEl1{
        .t0sz = tcr_el1_txsz,
    };

    @memset(@ptrCast([*]volatile u8, l2_tt), 0, @sizeOf(@TypeOf(l2_tt)));
    @memset(@ptrCast([*]volatile u8, l3_tts), 0, @sizeOf(@TypeOf(l3_tts)));

    var l2i: usize = 0;
    while (l2i < tt_entries) : (l2i += 1) {
        var l3i: usize = 0;
        while (l3i < tt_entries) : (l3i += 1) {
            l3_tts[l2i][l3i] = TtEntry{
                .valid = 1,
                .walk = 1,
                .af = 1,
                .addr = @truncate(u36, l3i + l2i * tt_entries),
            };
        }

        l2_tt[l2i] = TtEntry{
            .valid = 1,
            .walk = 1,
            .addr = @truncate(u36, @ptrToInt(&l3_tts[l2i]) >> page_bits),
        };
    }
    log("set_direct_tt: done\n", .{});
}

fn set_direct_tt_l1andl2(l1_tt: *[tt_entries]TtEntry, l2_tts: *[tt_entries]Tt, tcr_el1: *TcrEl1) void {
    log("set_direct_tt:\n", .{});
    tcr_el1.* = TcrEl1{
        .t0sz = 32,
    };

    @memset(@ptrCast([*]volatile u8, l1_tt), 0, @sizeOf(@TypeOf(l1_tt)));
    @memset(@ptrCast([*]volatile u8, l2_tts), 0, @sizeOf(@TypeOf(l2_tts)));

    var l1i: usize = 0;
    while (l1i <= @ptrToInt(&__end) >> 30) : (l1i += 1) {
        var l2i: usize = 0;
        while (l2i < tt_entries) : (l2i += 1) {
            l2_tts[l1i][l2i] = TtEntry{
                .valid = 1,
                .af = 1,
                .addr = @truncate(u36, (l2i + l1i * tt_entries) * (1 << 9)),
            };
        }

        l1_tt[l1i] = TtEntry{
            .valid = 1,
            .walk = 1,
            .addr = @truncate(u36, @ptrToInt(&l2_tts[l1i]) >> page_bits),
        };
    }
    log("set_direct_tt: done\n", .{});
}

pub export var boot_tt_l1: Tt align(page_size) = init: {
    var tt: Tt = undefined;
    for (tt) |*en|
        en.* = 0;

    tt[0] |= 1 << tte_valid_off;
    tt[0] |= 1 << tte_af_off;
    break :init tt;
};

export var boot_stack: [8 * page_size]u8 align(page_size) = undefined;
pub fn boot_stack_top() usize {
    return @ptrToInt(&boot_stack) + boot_stack.len;
}

// Map the physical page 'pp' at virtual address 'va'.
// The permissions (the low 12 bits) of the page table entry
// should be set to 'perm|PTE_P'.
//
// Requirements
//   - If there is already a page mapped at 'va', it should be page_remove()d.
//   - If necessary, on demand, a page table should be allocated and inserted
//     into 'pgdir'.
//   - pp->pp_ref should be incremented if the insertion succeeds.
//   - The TLB must be invalidated if a page was formerly present at 'va'.
//
// Corner-case hint: Make sure to consider what happens when the same
// pp is re-inserted at the same virtual address in the same pgdir.
// However, try not to distinguish this case in your code, as this
// frequently leads to subtle bugs; there's an elegant way to handle
// everything in one code path.
//
// RETURNS:
//   0 on success
//   -E_NO_MEM, if page table couldn't be allocated
//
// Hint: The TA solution is implemented using pgdir_walk, page_remove,
// and page2pa.
pub fn page_insert(tt: *align(page_size) volatile Tt, pp: *PageInfo, va: usize, ap: u2) Error!void {
    var tte = (try walk(tt, va, true)).?;
    if (tte_paddr(tte.*) != page2pa(pp)) {
        pp.*.ref_count += 1;
        if ((tte.* >> tte_valid_off) & 0x1 == 1)
            page_remove(tt, tte_paddr(tte.*));
    }

    // log("page_insert: va: {}, pa: {x}\n",.{va, page2pa(pp)});
    tte.* = page2pa(pp);
    @ptrCast(*u64, tte).* |= 1 << tte_valid_off;
    @ptrCast(*u64, tte).* |= 1 << tte_walk_off;
    @ptrCast(*u64, tte).* |= 1 << tte_af_off;
    @ptrCast(*u64, tte).* |= @intCast(u64, ap) << tte_ap_off;
}

// Return the page mapped at virtual address 'va'.
// If pte_store is not zero, then we store in it the address
// of the pte for this page.  This is used by page_remove and
// can be used to verify page permissions for syscall arguments,
// but should not be used by most callers.
//
// Return NULL if there is no page mapped at va.
pub fn page_lookup(tt: *align(page_size) volatile Tt, va: usize, opt_tte_store: ?**TtEntry) ?*PageInfo {
    var opt_tte = walk(tt, va, false) catch unreachable;
    if (opt_tte) |tte| {
        if (opt_tte_store) |tte_store| tte_store.* = tte;
        if (get_bits(tte.*, tte_valid_off, tte_valid_len) == tte_valid_valid)
            return pa2page(tte_paddr(tte.*));
    }
    return null;
}

// Unmaps the physical page at virtual address 'va'.
// If there is no physical page at that address, silently does nothing.
//
// Details:
//   - The ref count on the physical page should decrement.
//   - The physical page should be freed if the refcount reaches 0.
//   - The pg table entry corresponding to 'va' should be set to 0.
//     (if such a PTE exists)
//   - The TLB must be invalidated if you remove an entry from
//     the page table.
//
// Hint: The TA solution is implemented using page_lookup,
// 	tlb_invalidate, and page_decref.
pub fn page_remove(tt: *align(page_size) volatile Tt, va: usize) void {
    var tte: *TtEntry = undefined;
    if (page_lookup(tt, va, &tte)) |pp| {
        tte.* = 0;
        page_decref(pp);
        tlb_invalidate(tt, va);
    }
}

pub fn region_alloc(tt: *align(page_size) volatile Tt, src_va: usize, len: usize, ap: u2) Error!void {
    var va = src_va;
    while (round_down(va, page_size) < round_up(src_va + len, page_size)) : (va += (1 << l3_off)) {
        if (page_lookup(tt, va, null) != null)
            continue;
        const pp = try page_alloc(false);
        errdefer page_free(pp);
        _ = try page_insert(tt, pp, va, ap);
    }
}

pub fn user_memcpy(tt: *align(page_size) volatile Tt, dst_va_: usize, len: usize, src_kva: usize) void {
    const src = @intToPtr([*]u8, src_kva);
    var dst_va = dst_va_;
    var page_start = dst_va % page_size;
    var osrc: usize = 0;
    while (osrc < len) {
        if (page_lookup(tt, dst_va, null)) |pp| {
            const kva = @intToPtr([*]u8, @ptrToInt(page2kva(pp)));
            const l = std.math.min(len - osrc, page_size - page_start);
            std.mem.copy(u8, kva[page_start .. page_start + l], src[osrc .. osrc + l]);
            page_start = (page_start + l) % page_size;
            osrc += l;
            dst_va += l;
        } else unreachable;
    }
}

pub fn user_memzero(tt: *align(page_size) volatile Tt, dst_va: usize, len: usize) void {
    var dst = dst_va;
    var page_start = dst_va % page_size;
    var off: usize = 0;
    while (off < len) {
        if (page_lookup(tt, dst, null)) |pp| {
            const kva = @ptrCast([*]u8, page2kva(pp));
            const l = std.math.min(len - off, page_size - page_start);
            for (kva[page_start .. page_start + l]) |*p| p.* = 0;
            // log("memzero: {}..{}\n", .{ &kva[page_start], &kva[page_start + l] });
            page_start = (page_start + l) % page_size;
            off += l;
            dst += l;
        } else
            unreachable;
    }
}

fn tlb_invalidate(tt: *align(page_size) volatile Tt, va: usize) void {
    asm volatile (
        \\  TLBI     VMALLE1
        \\  DSB      SY
        \\  ISB
    );
}

pub inline fn phys_addr(va: usize) PhysAddr {
    return va - kern_base;
}

pub inline fn kern_addr(pa: usize) usize {
    return pa + kern_base;
}

pub fn page2pa(pp: *PageInfo) usize {
    const page_idx = ((@ptrToInt(pp) - @ptrToInt(pages)) / @sizeOf(PageInfo));
    return page_idx << page_bits;
}

pub fn pa2page(pa: PhysAddr) *PageInfo {
    const ipage = (pa >> page_bits);
    if (ipage >= page_count) {
        panic("pa2page called with invalid pa", null);
    }
    // log("pa2page: pa: {}, pa >> page_bits: {}\n", .{ pa, pa >> page_bits });
    return &pages[ipage];
}

pub fn page2kva(pp: *PageInfo) Page {
    return @intToPtr(Page, page2pa(pp) + kern_base);
}

fn round_down(p: usize, n: usize) usize {
    return p - (p % n);
}

fn round_up(p: usize, n: usize) usize {
    return round_down(p + n - 1, n);
}

pub const l1_off = l2_off + 9;

pub fn l1x(va: usize) u2 {
    return @truncate(u2, va >> l1_off);
}

pub const l2_off = l3_off + 9;

pub fn l2x(va: usize) u9 {
    return @truncate(u9, va >> l2_off);
}

pub const l3_off = page_bits;

pub fn l3x(va: usize) u9 {
    return @truncate(u9, va >> l3_off);
}

// generate linear address
pub fn gen_laddr(itte1: usize, itte2: usize, itte3: usize) usize {
    const m9 = (1 << 9) - 1;
    return ((itte1 & m9) << l1_off) | ((itte2 & m9) << l2_off) | ((itte3 & m9) << l3_off);
}

test "boot_l1_tt" {
    std.debug.warn("\n{x}\n", .{&boot_tt_l1});
    std.debug.warn("{x}\n", .{l1x(uart.MMIO_BASE)});
    std.debug.warn("{}\n", .{@bitSizeOf(TtEntry)});
    std.debug.warn("{}\n", .{@sizeOf(TtEntry)});
    std.debug.warn("{}\n", .{@sizeOf(TcrEl1)});
    std.debug.warn("{x}\n", .{@bitCast(usize, TcrEl1{
        .t0sz = TcrEl1.txsz_32b,
        .t1sz = TcrEl1.txsz_32b,
        .tg0 = TcrEl1.tg0_4k,
        .tg1 = TcrEl1.tg1_4k,
    })});
    std.debug.warn("l1_off: {}, l2_off: {}, l3_of: {}\n", .{ l1_off, l2_off, l3_off });
}
