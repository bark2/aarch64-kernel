const std = @import("std");
const uart = @import("uart.zig");

pub fn print(comptime format: []const u8, args: anytype) void {
    const State = enum {
        start,
        open_brace,
        close_brace,
    };

    comptime var start_index: usize = 0;
    comptime var state = State.start;
    comptime var next_arg: usize = 0;

    inline for (format) |c, i| {
        switch (state) {
            State.start => switch (c) {
                '{' => {
                    if (start_index < i) uart.write(format[start_index..i]);
                    state = State.open_brace;
                },
                '}' => {
                    if (start_index < i) uart.write(format[start_index..i]);
                    state = State.close_brace;
                },
                else => {},
            },
            State.open_brace => switch (c) {
                '{' => {
                    state = State.start;
                    start_index = i;
                },
                '}' => {
                    printValue(args[next_arg]);
                    next_arg += 1;
                    state = State.start;
                    start_index = i + 1;
                },
                else => @compileError("Unknown format character: " ++ c),
            },
            State.close_brace => switch (c) {
                '}' => {
                    state = State.start;
                    start_index = i;
                },
                else => @compileError("Single '}' encountered in format string"),
            },
        }
    }
    comptime {
        if (args.len != next_arg) {
            @compileError("Unused arguments");
        }
        if (state != State.start) {
            @compileError("Incomplete format string: " ++ format);
        }
    }
    if (start_index < format.len) {
        uart.write(format[start_index..format.len]);
    }
}

fn printValue(value: anytype) void {
    switch (@typeInfo(@TypeOf(value))) {
        .ComptimeInt, .Int, .ComptimeFloat, .Float => {
            // return writer.writeIntNative(@TypeOf(value), value);
            return write_uint(value, 16);
        },
        else => {
            @compileError("Unable to print type '" ++ @typeName(@TypeOf(value)) ++ "'");
        },
    }
}

pub fn write_uint(num: usize, comptime base: usize) void {
    if (num == 0) {
        uart.write_byte('0');
        return;
    }

    var rest = num;
    while (rest > 0) : (rest /= base) {
        uart.write_byte(switch (base) {
            10 => rest % 10 + '0',
            16 => if (rest % 16 < 10) @intCast(u8, rest % 16) + '0' else @intCast(u8, rest % 16) + 'A',
            else => @compileError("Wrong base value used."),
        });
    }
}
