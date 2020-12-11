const std = @import("std");
const builtin = @import("builtin");
usingnamespace @import("syscall.zig");

var writer: Writer = undefined;

pub fn print(comptime format: []const u8, args: anytype) !void {
    try writer.print(format, args);
}

const NoError = error{};

const Writer = std.io.Writer(void, anyerror, struct {
    fn write_bytes(_: void, bytes: []const u8) !usize {
        _ = try syscall2(@enumToInt(syscall.Syscall.PUTS), @ptrToInt(bytes.ptr), bytes.len);
        return bytes.len;
    }
}.write_bytes);
