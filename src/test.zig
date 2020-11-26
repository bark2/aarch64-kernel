const std = @import("std");
const expect = std.testing.expect;

const TtEntry1 = packed struct {
    valid: u1 = 0, // [0:0]
    walk: u1 = 0, // [1:1]
    indx: u2 = 0, //  [2:3]
    ns: u1 = 0, // security bit (EL3 or Secure EL1), [4:4]
    ap: u2 = 0, // access permission, [5:6]
    sh: u2 = 0, // shareable attribute, [7:8]
    af: u1 = 0, // access flag, [9:9]
    ng: u1 = 0, // not global, [10:10]
    reserved1: u1 = 0, // [11:11]
    addr: u36 = 0, // [12:47]
    reserve2: u5 = 0, // [48:52]
    pxn: u1 = 0, // [53:53]
    uxn: u1 = 0, // [54:54]
    software_use: u4 = 0, // [55:58]
    ignored: u5 = 0, // [59:63]
};

const TtEntry2 = packed struct {
    valid: u1 = 0, // [0]
    walk: u1 = 0, // [1]
    indx: u3 = 0, //  [2:4]
    ns: u1 = 0, // security bit (EL3 or Secure EL1), [5]
    ap: u2 = 0, // access permission, [6:7]
    sh: u2 = 0, // shareable attribute, [8:9]
    af: u1 = 0, // access flag, [10]
    ng: u1 = 0, // not global, [11]
    addr: u36 = 0, // [12:47]
    res1: u2 = 0, // [48:49]
    gp: u1 = 0, // [50]
    dbm: u1 = 0, // [51]
    continuous: u1 = 0, // [52]
    pxn: u1 = 0, // [53]
    uxn: u1 = 0, // [54]
    software_use: u4 = 0, // [55:58]
    ignored: u5 = 0, // [59:63]
};

test "sizeOf" {
    std.debug.warn("\n@bitSizeOf 1: {}\n", .{@bitSizeOf(TtEntry1)});
    std.debug.warn("@bitSizeOf 2: {}\n", .{@bitSizeOf(TtEntry2)});
    std.debug.warn("@sizeOf 1: {}\n", .{@sizeOf(TtEntry1)});
    std.debug.warn("@sizeOf 2: {}\n", .{@sizeOf(TtEntry2)});
    expect(@bitSizeOf(TtEntry1) == @bitSizeOf(TtEntry2));
    expect(@sizeOf(TtEntry1) == @sizeOf(TtEntry2));
}
