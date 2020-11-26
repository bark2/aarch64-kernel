const std = @import("std");
const uart = @import("uart.zig");
const elf = @import("elf.zig");
const log = uart.log;

// POSIX ustar header format
const Tar = struct {
    name: [100]u8, //   0
    mode: [8]u8, // 100
    uid: [8]u8, // 108
    gid: [8]u8, // 116
    size: [12]u8, // 124
    mtime: [12]u8, // 136
    chksum: [8]u8, // 148
    typeflag: u8, // 156
    linkname: [100]u8, // 157
    magic: [6]u8, // 257
    version: [2]u8, // 263
    uname: [32]u8, // 265
    gname: [32]u8, // 297
    devmajor: [8]u8, // 329
    devminor: [8]u8, // 337
    prefix: [167]u8, // 345
};

// Helper function to convert ASCII octal number into binary
// s string
// n number of digits
fn oct2bin(s: []const u8, n_: u32) u32 {
    var n = n_;
    var i: u32 = 0;
    var r: u32 = 0;
    while (n > 0) : (n -= 1) {
        r <<= 3;
        r += s[i] - '0';
        i += 1;
    }
    return r;
}

// List the contents of an archive
pub fn list(archive: [*]u8) void {
    const types = [_][]const u8{ "regular", "link  ", "symlnk", "chrdev", "blkdev", "dircty", "fifo  ", "???   " };

    log("Type     Offset Size  Access rights\tFilename\n", .{});

    // iterate on archive's contents
    var ptr = archive;
    var filesize: usize = undefined;
    while (std.mem.eql(u8, @ptrCast(*[5]u8, ptr + 257), "ustar")) : (ptr += (((filesize + 511) / 512) + 1) * 512) {
        const header = @ptrCast(*Tar, ptr);
        filesize = oct2bin(&header.size, 11);
        // print out meta information
        log("{}  {} {x} {s} {s}.{s}\t{s}", .{
            types[header.typeflag - '0'],
            @intCast(u32, @ptrToInt(ptr + @sizeOf(Tar))),
            filesize,
            @ptrCast([*:0]u8, &header.mode),
            @ptrCast([*:0]u8, &header.uname),
            @ptrCast([*:0]u8, &header.gname),
            @ptrCast([*:0]u8, &header.name),
        });
        if (header.typeflag == '2')
            log(" -> {s}", .{header.linkname});
        log("\n", .{});
    }
}

pub fn lookup(archive: [*]u8, filename: []const u8, out: **elf.Elf) usize {
    var ptr = archive;
    var filesize: usize = undefined;
    while (std.mem.eql(u8, @ptrCast(*[5]u8, ptr + 257), "ustar")) : (ptr += (((filesize + 511) / 512) + 1) * 512) {
        const header = @ptrCast(*Tar, ptr);
        filesize = oct2bin(&header.size, 11);
        if (std.mem.eql(u8, filename, std.mem.spanZ(@ptrCast([*:0]u8, &header.name)))) {
            std.debug.assert(@mod(@ptrToInt(ptr + 512), 4) == 0);
            out.* = @intToPtr(*elf.Elf, @ptrToInt(ptr + 512));
            return filesize;
        }
    }
    return 0;
}
