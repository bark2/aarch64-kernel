usingnamespace @import("common.zig");

extern fn sd_readblock(lba: c_uint, buffer: [*c]u8, num: c_uint) c_int;
extern fn sd_init() c_int;
pub const SD_OK = 0;
pub const SD_TIMEOUT = -1;
pub const SD_ERROR = -2;

pub const Error = error{ Timeout, Unknown };

pub fn readblock(lba: u32, buffer: [*c]u8, num: u32) !u32 {
    const bytes = sd_readblock(lba, buffer, num);
    if (bytes == 0)
        return if (sd_err == SD_TIMEOUT) Error.Timeout else Error.Unknown;

    return @intCast(u32, bytes);
}
pub fn init() Error!void {
    switch (sd_init()) {
        SD_OK => {},
        SD_ERROR => {
            return Error.Unknown;
        },
        SD_TIMEOUT => {
            return Error.Timeout;
        },
        else => unreachable,
    }
}
pub extern var sd_err: u32;
pub const block_size = 512;
