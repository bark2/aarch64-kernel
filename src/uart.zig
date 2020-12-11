const std = @import("std");
// usingnamespace @import("gpio.zig");
const print = @import("print.zig");
const AtomicOrder = @import("builtin").AtomicOrder;
const pmap = @import("pmap.zig");

pub const MMIO_BASE = 0x3f000000;
const GPIO_BASE = MMIO_BASE + 0x200000;

const GPFSEL1 = GPIO_BASE + 0x4;
const GPPUD = GPIO_BASE + 0x94;
const GPPUDCLK0 = GPIO_BASE + 0x98;

// const aux_enb = @ptrToInt(MMIO_BASE + 0x215004);
// const aux_mu_base = @ptrToInt(MMIO_BASE + 0x215000);
const aux_enable = MMIO_BASE + 0x215004;
const aux_mu_base = MMIO_BASE + 0x215000;
const aux_mu_io = aux_mu_base + 0x40;
const aux_mu_ier = aux_mu_base + 0x44;
const aux_mu_iir = aux_mu_base + 0x48;
const aux_mu_lcr = aux_mu_base + 0x4c;
const aux_mu_mcr = aux_mu_base + 0x50;
const aux_mu_lsr = aux_mu_base + 0x54;
const aux_mu_msr = aux_mu_base + 0x58;
const aux_mu_scratch = aux_mu_base + 0x5c;
const aux_mu_cntl = aux_mu_base + 0x60;
const aux_mu_stat = aux_mu_base + 0x64;
const aux_mu_baud = aux_mu_base + 0x68;

fn mmio_read(addr: u64) u32 {
    @fence(AtomicOrder.SeqCst);
    return @intToPtr(*volatile u32, pmap.kern_addr(addr)).*;
}

fn mmio_write(addr: u64, val: u32) void {
    @fence(AtomicOrder.SeqCst);
    @intToPtr(*volatile u32, pmap.kern_addr(addr)).* = val;
}

// Loop count times in a way that the compiler won't optimize away.
fn delay(count: usize) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        asm volatile ("mov w0, w0");
    }
}

pub fn init() void {
    // enable uart1 registers
    mmio_write(aux_enable, mmio_read(aux_enable) | (1 << 0));

    mmio_write(aux_mu_cntl, 0); // disable rx and tx
    mmio_write(aux_mu_lcr, 3); // work in 8-bit mode, DLAB 0

    mmio_write(aux_mu_mcr, 0);
    mmio_write(aux_mu_ier, 0);

    mmio_write(aux_mu_iir, 0); // disable interrupts
    mmio_write(aux_mu_iir, 0xc6); // disable interrupts
    mmio_write(aux_mu_baud, 270); // 115200 baud

    var reg = mmio_read(GPFSEL1);
    reg &= ~@intCast(u32, ((7 << 12) | (7 << 15))); // gpio14, gpio15
    reg |= (2 << 12) | (2 << 15); // alt5
    mmio_write(GPFSEL1, reg);
    mmio_write(GPPUD, 0); // enable pins 14 and 15
    delay(150);
    mmio_write(GPPUDCLK0, (1 << 14) | (1 << 15));
    delay(150);
    mmio_write(GPPUDCLK0, 0); // flush gpio setup

    mmio_write(aux_mu_cntl, (1 << 1) | (1 << 0)); // enable rx and tx
}

pub fn write_byte(c: u8) void {
    while ((mmio_read(aux_mu_lsr) & (1 << 5)) == 0) {}
    // while ((aux_mu_lsr.* & (1 << 5)) == 0) {}
    mmio_write(aux_mu_io, c);
}

pub fn read_byte() u8 {
    while ((mmio_read(aux_mu_lsr) & (1 << 0)) == 0) {}
    return @truncate(u8, mmio_read(aux_mu_io));
}

pub fn write(s: []const u8) void {
    for (s) |c| {
        if (c == '\n') {
            write_byte('\r');
            write_byte('\n');
        } else {
            write_byte(c);
        }
    }
}

const NoError = error{};

const WriterType = std.io.Writer(void, NoError, struct {
    fn write_bytes(_: void, bytes: []const u8) NoError!usize {
        write(bytes);
        return bytes.len;
    }
}.write_bytes);

var serial_writer: WriterType = undefined;

pub fn log(comptime format: []const u8, args: anytype) void {
    // https://developer.arm.com/documentation/den0024/a/AArch64-Floating-point-and-NEON?lang=en
    serial_writer.print(format, args) catch return;
}

pub fn log_bytes(bytes: []const u8) void {
    try serial_writer.writeAll(bytes);
}
