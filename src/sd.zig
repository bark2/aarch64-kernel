// usingnamespace @import("gpio.zig");
// usingnamespace @import("delays.zig");
// const log = @import("uart.zig").log;

// const EMMC_ARG2: *volatile u32 = @ptrCast(*u32, MMIO_BASE + 0x00300000);
// const EMMC_BLKSIZECNT: *volatile u32 = @ptrCast(*u32, MMIO_BASE + 0x00300004);
// const EMMC_ARG1: *volatile u32 = @ptrCast(*u32, MMIO_BASE + 0x00300008);
// const EMMC_CMDTM: *volatile u32 = @ptrCast(*u32, MMIO_BASE + 0x0030000C);
// const EMMC_RESP0: *volatile u32 = @ptrCast(*u32, MMIO_BASE + 0x00300010);
// const EMMC_RESP1: *volatile u32 = @ptrCast(*u32, MMIO_BASE + 0x00300014);
// const EMMC_RESP2: *volatile u32 = @ptrCast(*u32, MMIO_BASE + 0x00300018);
// const EMMC_RESP3: *volatile u32 = @ptrCast(*u32, MMIO_BASE + 0x0030001C);
// const EMMC_DATA: *volatile u32 = @ptrCast(*u32, MMIO_BASE + 0x00300020);
// const EMMC_STATUS: *volatile u32 = @ptrCast(*u32, MMIO_BASE + 0x00300024);
// const EMMC_CONTROL0: *volatile u32 = @ptrCast(*u32, MMIO_BASE + 0x00300028);
// const EMMC_CONTROL1: *volatile u32 = @ptrCast(*u32, MMIO_BASE + 0x0030002C);
// const EMMC_INTERRUPT: *volatile u32 = @ptrCast(*u32, MMIO_BASE + 0x00300030);
// const EMMC_INT_MASK: *volatile u32 = @ptrCast(*u32, MMIO_BASE + 0x00300034);
// const EMMC_INT_EN: *volatile u32 = @ptrCast(*u32, MMIO_BASE + 0x00300038);
// const EMMC_CONTROL2: *volatile u32 = @ptrCast(*u32, MMIO_BASE + 0x0030003C);
// const EMMC_SLOTISR_VER: *volatile u32 = @ptrCast(*u32, MMIO_BASE + 0x003000FC);

// // command flags
// const CMD_NEED_APP: u32 = 0x80000000;
// const CMD_RSPNS_48: u32 = 0x00020000;
// const CMD_ERRORS_MASK: u32 = 0xfff9c004;
// const CMD_RCA_MASK: u32 = 0xffff0000;

// // COMMANDs
// const CMD_GO_IDLE: u32 = 0x00000000;
// const CMD_ALL_SEND_CID: u32 = 0x02010000;
// const CMD_SEND_REL_ADDR: u32 = 0x03020000;
// const CMD_CARD_SELECT: u32 = 0x07030000;
// const CMD_SEND_IF_COND: u32 = 0x08020000;
// const CMD_STOP_TRANS: u32 = 0x0C030000;
// const CMD_READ_SINGLE: u32 = 0x11220010;
// const CMD_READ_MULTI: u32 = 0x12220032;
// const CMD_SET_BLOCKCNT: u32 = 0x17020000;
// const CMD_APP_CMD: u32 = 0x37000000;
// const CMD_SET_BUS_WIDTH: u32 = (0x06020000 | CMD_NEED_APP);
// const CMD_SEND_OP_COND: u32 = (0x29020000 | CMD_NEED_APP);
// const CMD_SEND_SCR: u32 = (0x33220010 | CMD_NEED_APP);

// // STATUS register settings
// const SR_READ_AVAILABLE: u32 = 0x00000800;
// const SR_DAT_INHIBIT: u32 = 0x00000002;
// const SR_CMD_INHIBIT: u32 = 0x00000001;
// const SR_APP_CMD: u32 = 0x00000020;

// // INTERRUPT register settings
// const INT_DATA_TIMEOUT: u32 = 0x00100000;
// const INT_CMD_TIMEOUT: u32 = 0x00010000;
// const INT_READ_RDY: u32 = 0x00000020;
// const INT_CMD_DONE: u32 = 0x00000001;

// const INT_ERROR_MASK: u32 = 0x017E8000;

// // CONTROL register settings;
// const C0_SPI_MODE_EN: u32 = 0x00100000;
// const C0_HCTL_HS_EN: u32 = 0x00000004;
// const C0_HCTL_DWITDH: u32 = 0x00000002;

// const C1_SRST_DATA: u32 = 0x04000000;
// const C1_SRST_CMD: u32 = 0x02000000;
// const C1_SRST_HC: u32 = 0x01000000;
// const C1_TOUNIT_DIS: u32 = 0x000f0000;
// const C1_TOUNIT_MAX: u32 = 0x000e0000;
// const C1_CLK_GENSEL: u32 = 0x00000020;
// const C1_CLK_EN: u32 = 0x00000004;
// const C1_CLK_STABLE: u32 = 0x00000002;
// const C1_CLK_INTLEN: u32 = 0x00000001;

// // SLOTISR_VER values;
// const HOST_SPEC_NUM: u32 = 0x00ff0000;
// const HOST_SPEC_NUM_SHIFT: u32 = 16;
// const HOST_SPEC_V3: u32 = 2;
// const HOST_SPEC_V2: u32 = 1;
// const HOST_SPEC_V1: u32 = 0;

// // SCR flags
// const SCR_SD_BUS_WIDTH_4: u32 = 0x00000400;
// const SCR_SUPP_SET_BLKCNT: u32 = 0x02000000;
// // added by my driver
// const SCR_SUPP_CCS: u32 = 0x00000001;

// const ACMD41_VOLTAGE: u32 = 0x00ff8000;
// const ACMD41_CMD_COMPLETE: u32 = 0x80000000;
// const ACMD41_CMD_CCS: u32 = 0x40000000;
// const ACMD41_ARG_HC: u32 = 0x51ff8000;

// var sd_scr: [2]u64 = undefined;
// var sd_ocr: u64 = undefined;
// var sd_rca: u64 = undefined;
// var sd_err: u64 = undefined;
// var sd_hv: u64 = undefined;

// const SD_OK: i32 = 0;
// const SD_TIMEOUT: i32 = -1;
// const SD_ERROR: i32 = -2;

// fn sd_clk(f: u32) i32 {
//     // unsigned int d,c=41666666/f,x,s=32,h=0;
//     var d: u32 = undefined;
//     var c: u32 = 41666666 / f;
//     var x: u32 = undefined;
//     var s: u32 = 32;
//     var h: u32 = 0;
//     // int cnt = 100000;
//     var cnt: i32 = 100000;
//     while ((EMMC_STATUS.* & (SR_CMD_INHIBIT | SR_DAT_INHIBIT)) != 0 and cnt != 0) {
//         cnt -= 1;
//         wait_msec(1);
//     }
//     if (cnt <= 0) {
//         log("ERROR: timeout waiting for inhibit flag\n", .{});
//         return SD_ERROR;
//     }

//     EMMC_CONTROL1.* &= ~C1_CLK_EN;
//     wait_msec(10);
//     x = c - 1;
//     if (x == 0) {
//         s = 0;
//     } else {
//         if ((x & 0xffff0000) == 0) {
//             x <<= 16;
//             s -= 16;
//         }
//         if ((x & 0xff000000) == 0) {
//             x <<= 8;
//             s -= 8;
//         }
//         if ((x & 0xf0000000) == 0) {
//             x <<= 4;
//             s -= 4;
//         }
//         if ((x & 0xc0000000) == 0) {
//             x <<= 2;
//             s -= 2;
//         }
//         if ((x & 0x80000000) == 0) {
//             x <<= 1;
//             s -= 1;
//         }
//         if (s > 0) s -= 1;
//         if (s > 7) s = 7;
//     }
//     if (sd_hv > HOST_SPEC_V2) {
//         d = c;
//     } else {
//         d = (1 << @truncate(u5, s));
//     }
//     if (d <= 2) {
//         d = 2;
//         s = 0;
//     }
//     log("sd_clk divisor {x}, shift {x}\n", .{ d, s });
//     if (sd_hv > HOST_SPEC_V2) h = (d & 0x300) >> 2;
//     d = (((d & 0x0ff) << 8) | h);
//     EMMC_CONTROL1.* = (EMMC_CONTROL1.* & 0xffff003f) | d;
//     wait_msec(10);
//     EMMC_CONTROL1.* |= C1_CLK_EN;
//     wait_msec(10);
//     cnt = 10000;
//     while ((EMMC_CONTROL1.* & C1_CLK_STABLE) == 0 and cnt) {
//         cnt -= 1;
//         wait_msec(10);
//     }
//     if (cnt <= 0) {
//         uart_puts("ERROR: failed to get stable clock\n");
//         return SD_ERROR;
//     }
//     return SD_OK;
// }

// fn sd_cmd(code: u32, arg: u32) i32 {
//     var r: i32 = 0;
//     sd_err = SD_OK;
//     if (code & CMD_NEED_APP != 0) {
//         r = sd_cmd(CMD_APP_CMD | (if (sd_rca != 0) CMD_RSPNS_48 else 0), @truncate(u32, sd_rca));
//         if (sd_rca != 0 and !r) {
//             log("ERROR: failed to send SD APP command\n", .{});
//             sd_err = SD_ERROR;
//             return 0;
//         }
//         code &= ~CMD_NEED_APP;
//     }
//     if (sd_status(SR_CMD_INHIBIT)) {
//         uart_puts("ERROR: EMMC busy\n");
//         sd_err = SD_TIMEOUT;
//         return 0;
//     }
//     uart_puts("EMMC: Sending command ");
//     uart_hex(code);
//     uart_puts(" arg ");
//     uart_hex(arg);
//     uart_puts("\n");
//     EMMC_INTERRUPT.* = EMMC_INTERRUPT.*;
//     EMMC_ARG1.* = arg;
//     EMMC_CMDTM.* = code;
//     if (code == CMD_SEND_OP_COND) {
//         wait_msec(1000);
//     } else if (code == CMD_SEND_IF_COND or code == CMD_APP_CMD) {
//         wait_msec(100);
//     }
//     r = sd_int(INT_CMD_DONE);
//     if (r != 0) {
//         uart_puts("ERROR: failed to send EMMC command\n");
//         sd_err = r;
//         return 0;
//     }
//     r = *EMMC_RESP0;
//     if (code == CMD_GO_IDLE or code == CMD_APP_CMD) {
//         return 0;
//     } else if (code == (CMD_APP_CMD | CMD_RSPNS_48)) {
//         return r & SR_APP_CMD;
//     } else if (code == CMD_SEND_OP_COND) {
//         return r;
//     } else if (code == CMD_SEND_IF_COND) {
//         return if (r == arg) SD_OK else SD_ERROR;
//     } else if (code == CMD_ALL_SEND_CID) {
//         r |= *EMMC_RESP3;
//         r |= *EMMC_RESP2;
//         r |= *EMMC_RESP1;
//         return r;
//     } else if (code == CMD_SEND_REL_ADDR) {
//         sd_err = (((r & 0x1fff)) | ((r & 0x2000) << 6) | ((r & 0x4000) << 8) | ((r & 0x8000) << 8)) & CMD_ERRORS_MASK;
//         return r & CMD_RCA_MASK;
//     }
//     return r & CMD_ERRORS_MASK;
//     // make gcc happy
//     return 0;
// }

// fn sd_status(code: u32) i32 {
//     return 0;
// }

// fn sd_int(code: u32) i32 {
//     return 0;
// }

// pub fn sd_init() i32 {
//     // long r,cnt,ccs=0;
//     var r: u32 = undefined;
//     var cnt: u32 = undefined;
//     var ccs: u32 = 0;

//     // GPIO_CD
//     r = GPFSEL4.*;
//     r &= ~@intCast(u32, (7 << (7 * 3)));
//     GPFSEL4.* = r;
//     GPPUD.* = 2;
//     wait_cycles(150);
//     GPPUDCLK1.* = (1 << 15);
//     wait_cycles(150);
//     GPPUD.* = 0;
//     GPPUDCLK1.* = 0;
//     r = GPHEN1.*;
//     r |= 1 << 15;
//     GPHEN1.* = r;

//     // GPIO_CLK, GPIO_CMD
//     r = GPFSEL4.*;
//     r |= (7 << (8 * 3)) | (7 << (9 * 3));
//     GPFSEL4.* = r;
//     GPPUD.* = 2;
//     wait_cycles(150);
//     GPPUDCLK1.* = (1 << 16) | (1 << 17);
//     wait_cycles(150);
//     GPPUD.* = 0;
//     GPPUDCLK1.* = 0;

//     // GPIO_DAT0, GPIO_DAT1, GPIO_DAT2, GPIO_DAT3
//     r = GPFSEL5.*;
//     r |= (7 << (0 * 3)) | (7 << (1 * 3)) | (7 << (2 * 3)) | (7 << (3 * 3));
//     GPFSEL5.* = r;
//     GPPUD.* = 2;
//     wait_cycles(150);
//     GPPUDCLK1.* = (1 << 18) | (1 << 19) | (1 << 20) | (1 << 21);
//     wait_cycles(150);
//     GPPUD.* = 0;
//     GPPUDCLK1.* = 0;

//     sd_hv = (EMMC_SLOTISR_VER.* & HOST_SPEC_NUM) >> HOST_SPEC_NUM_SHIFT;
//     log("EMMC: GPIO set up\n", .{});
//     // Reset the card.
//     EMMC_CONTROL0.* = 0;
//     EMMC_CONTROL1.* |= C1_SRST_HC;
//     // cnt=10000; do{wait_msec(10);} while( (*EMMC_CONTROL1 & C1_SRST_HC) && cnt-- );
//     cnt = 10000;
//     wait_msec(10);
//     while ((EMMC_CONTROL1.* & C1_SRST_HC) != 0 and cnt != 0) {
//         cnt -= 1;
//         wait_msec(10);
//     }
//     if (cnt <= 0) {
//         log("ERROR: failed to reset EMMC\n", .{});
//         return SD_ERROR;
//     }
//     log("EMMC: reset OK\n", .{});
//     EMMC_CONTROL1.* |= C1_CLK_INTLEN | C1_TOUNIT_MAX;
//     wait_msec(10);
//     // Set clock to setup frequency.
//     r = @bitCast(u32, sd_clk(400000));
//     if (r != 0) return @bitCast(i32, r);
//     EMMC_INT_EN.* = 0xffffffff;
//     EMMC_INT_MASK.* = 0xffffffff;
//     // sd_scr[0]=sd_scr[1]=sd_rca=sd_err=0;
//     sd_scr[0] = 0;
//     sd_scr[1] = 0;
//     sd_rca = 0;
//     sd_err = 0;

//     _ = sd_cmd(CMD_GO_IDLE, 0);
//     if (sd_err != 0) return SD_ERROR;

//     _ = sd_cmd(CMD_SEND_IF_COND, 0x000001AA);
//     if (sd_err != 0) return SD_ERROR;
//     // cnt=6; r=0; while(!(r&ACMD41_CMD_COMPLETE) && cnt--) {
//     cnt = 6;
//     r = 0;
//     while ((@intCast(u32, r) & ACMD41_CMD_COMPLETE) == 0 and cnt != 0) {
//         cnt -= 1;
//         wait_cycles(400);
//         r = @bitCast(i32, sd_cmd(CMD_SEND_OP_COND, ACMD41_ARG_HC));
//         log("EMMC: CMD_SEND_OP_COND returned ", .{});
//         if ((r & ACMD41_CMD_COMPLETE) != 0)
//             log("COMPLETE ", .{});
//         if ((r & ACMD41_VOLTAGE) != 0)
//             log("VOLTAGE ", .{});
//         if ((r & ACMD41_CMD_CCS) != 0)
//             log("CCS ", .{});
//         log("{x}\n", .{r});
//         if (sd_err != SD_TIMEOUT and sd_err != SD_OK) {
//             log("ERROR: EMMC ACMD41 returned error\n", .{});
//             return SD_ERROR;
//         }
//     }
//     if ((r & ACMD41_CMD_COMPLETE) == 0 or cnt == 0) return SD_TIMEOUT;
//     if ((r & ACMD41_VOLTAGE) == 0) return SD_ERROR;
//     if ((r & ACMD41_CMD_CCS) != 0) ccs = SCR_SUPP_CCS;

//     _ = sd_cmd(CMD_ALL_SEND_CID, 0);

//     sd_rca = @bitCast(u32, sd_cmd(CMD_SEND_REL_ADDR, 0));
//     log("EMMC: CMD_SEND_REL_ADDR returned {}{}\n", .{ sd_rca >> 32, sd_rca });
//     // uart_hex(sd_rca >> 32);
//     // uart_hex(sd_rca);
//     // log("\n", .{});
//     if (sd_err != 0) return @intCast(i32, sd_err);

//     r = @bitCast(u32, sd_clk(25000000));
//     if (r != 0) return @bitCast(u32, r);

//     _ = sd_cmd(CMD_CARD_SELECT, @truncate(u32, sd_rca));
//     if (sd_err != 0) return @bitCast(i32, @truncate(u32, sd_err));

//     if (sd_status(SR_DAT_INHIBIT) != 0) return SD_TIMEOUT;
//     EMMC_BLKSIZECNT.* = (1 << 16) | 8;
//     _ = sd_cmd(CMD_SEND_SCR, 0);
//     if (sd_err != 0) return @bitCast(i32, @truncate(u32, sd_err));
//     if (sd_int(INT_READ_RDY) != 0) return SD_TIMEOUT;

//     r = 0;
//     cnt = 100000;
//     while (r < 2 and cnt != 0) {
//         if ((EMMC_STATUS.* & SR_READ_AVAILABLE) != 0) {
//             sd_scr[r] = EMMC_DATA.*;
//             r += 1;
//         } else {
//             wait_msec(1);
//         }
//     }
//     if (r != 2) return SD_TIMEOUT;
//     if ((sd_scr[0] & SCR_SD_BUS_WIDTH_4) != 0) {
//         _ = sd_cmd(CMD_SET_BUS_WIDTH, @truncate(u32, sd_rca | 2));
//         if (sd_err != 0) return @bitCast(u32, sd_err);
//         EMMC_CONTROL0.* |= C0_HCTL_DWITDH;
//     }
//     // add software flag
//     log("EMMC: supports ", .{});
//     if (sd_scr[0] & SCR_SUPP_SET_BLKCNT)
//         log("SET_BLKCNT ", .{});
//     if (ccs)
//         log("CCS ", .{});
//     log("\n", .{});
//     sd_scr[0] &= ~SCR_SUPP_CCS;
//     sd_scr[0] |= ccs;
//     return SD_OK;
// }

// read a block(512 bytes) from sd card and return the number of bytes read
// returns 0 on error.
extern fn sd_readblock(lba: c_uint, buffer: [*c]u8, num: c_uint) c_int;
extern fn sd_init() c_int;
pub const SD_OK = 0;
pub const SD_TIMEOUT = -1;
pub const SD_ERROR = -2;

pub const readblock = sd_readblock;
pub const init = sd_init;
pub extern var sd_err: u32;
pub const block_size = 512;
