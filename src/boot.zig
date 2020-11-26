const std = @import("std");
const elf = @import("elf.zig");
const uart = @import("uart.zig");
const initrd = @import("initrd.zig");
const log = uart.log;

// linker filled globals
extern var __bss_start: u8;
extern var __bss_end: u8;
extern var _binary_ramdisk_start: u8;

// extern fn sd_init() c_int;
// extern fn sd_readblock(lba: u64, buffer: [*]u8, num: u64) c_int;
// extern fn initrd_list(buf: *u8) void;

comptime {
    // .text.boot to keep this in the first portion of the binary
    asm (
        \\.section .text.boot
        \\.globl _start
        \\_start:
        \\    mrs     x4, mpidr_el1
        \\    and     x4, x4, #3
        \\    cbnz    x4, halt
        \\ // ------------------------------------
        \\ // Enabling NEON and Floating Point
        \\ // Disable trapping of accessing in EL3 and EL2.
        \\ MSR CPTR_EL2, XZR
        \\ //MSR CPTR_EL3, XZR
        \\ // Disable access trapping in EL1 and EL0.
        \\ MOV X1, #(0x3 << 20)
        \\ MSR CPACR_EL1, X1
        \\ // FPEN disables trapping to EL1.
        \\ ISB
        \\ mov sp,#0x80000
        \\ ldr     x5, =boot_main
        \\ br      x5
        \\// ------------------------------------
        \\halt:
        \\ wfe
        \\ b       halt
    );
}

fn hlt() noreturn {
    while (true) {
        asm volatile ("wfe");
    }
}

// export fn boot_main() linksection(".text.main") void {
export fn boot_main() linksection(".text.boot_main") void {
    @memset(@as(*volatile [1]u8, &__bss_start), 0, @ptrToInt(&__bss_end) - @ptrToInt(&__bss_start));
    // uart.init();

    // const currentEL = asm volatile ("mrs x0, CurrentEL"
    // : [ret] "={x0}" (-> usize)
    // );
    // log("CurrentEL {} exception level {}\n", .{ currentEL, currentEL >> 2 & 0x3 });

    var archive = @ptrCast([*]u8, &_binary_ramdisk_start);
    // initrd.list(archive);

    var hdr: *elf.Elf = undefined;
    _ = initrd.lookup(archive, "zig-cache/kernel", &hdr);
    // log("{x}\n", .{hdr.magic});
    if (hdr.magic != elf.ELF_MAGIC)
        hlt();
    // log("{x}\n", .{hdr});

    var entry: usize = undefined;
    var pheaders = @intToPtr([*]elf.Proghdr, @ptrToInt(hdr) + hdr.phoff)[0..hdr.phnum];
    for (pheaders) |*ph, item| {
        if (ph.type == 0x6474e551) continue; // skip GNU_STACK program header

        // pa is the load address of this segment
        // offset is the offset of the segment in the file image
        // log("{x}\n", .{ph});
        // @memcpy(@intToPtr([*]u8, ph.pa), @ptrCast([*]u8, hdr) + ph.offset, ph.memsz);
        memmove(ph.pa, @ptrToInt(hdr) + ph.offset, ph.memsz);
    }

    @intToPtr(fn () noreturn, hdr.entry - @import("pmap.zig").kern_base)();
}

fn memmove(dest: usize, src: usize, n: usize) void {
    @setRuntimeSafety(false);
    if (dest < src) {
        var index: usize = 0;
        while (index != n) : (index += 1) {
            @intToPtr([*]u8, dest)[index] = @intToPtr([*]u8, src)[index];
        }
    } else {
        var index = n;
        while (index != 0) {
            index -= 1;
            @intToPtr([*]u8, dest)[index] = @intToPtr([*]u8, src)[index];
        }
    }
}
