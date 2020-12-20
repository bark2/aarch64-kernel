const builtin = @import("builtin");
// const debug = @import("debug.zig");
usingnamespace @import("common.zig");
const std = @import("std");
const arch = @import("arch.zig");
const uart = @import("uart.zig");
const proc = @import("proc.zig");
const syscall = @import("syscall.zig");
const pmap = @import("pmap.zig");
const timer = @import("timer.zig");
const log = uart.log;
// const ESR_ELx_EC_SHIFT = 26;
// const ESR_ELx_EC_SVC64 = 0x15;
// const ESR_ELx_EC_DABT_LOW = 0x24;

pub const ExceptionFrame = packed struct {
    xs: [29]u64,
    fp: u64, // x29
    lr: u64, // x30
    sp: u64,
    elr: u64,
    spsr: u64,
};

pub const Exception = enum {
    SYNC_INVALID_EL1T = 0,
    IRQ_INVALID_EL1T = 1,
    FIQ_INVALID_EL1T = 2,
    ERROR_INVALID_EL1T = 3,
    SYNC_INVALID_EL1H = 4,
    IRQ_EL1H = 5,
    FIQ_INVALID_EL1H = 6,
    ERROR_INVALID_EL1H = 7,
    SYNC_EL0_64 = 8,
    IRQ_EL0_64 = 9,
    FIQ_INVALID_EL0_64 = 10,
    ERROR_INVALID_EL0_64 = 11,
    SYNC_INVALID_EL0_32 = 12,
    IRQ_INVALID_EL0_32 = 13,
    FIQ_INVALID_EL0_32 = 14,
    ERROR_INVALID_EL0_32 = 15,
};

const exception_names = init: {
    var array: [@typeInfo(Exception).Enum.fields.len][]const u8 = undefined;
    for (@typeInfo(Exception).Enum.fields) |e, i| {
        array[i] = e.name;
    }
    break :init array;
};

// If a user gets exception, switch to kernel stack then push user state and handle,
// the user state is on the kernel's stack.
// A kernel thread which yields will use a function call, which as defined by the abi
// will save the current caller saved registers on the stack,
// and the new process state will be loaded.
// Can a system with more users than cores can function correcly?
// In xv6 for example, every user have a coresponding kernel thread.
// Exception results in a exception frame being created on the kernel stack(and because
// each user process has a kernel thread is is OK).

pub export fn handler(exception_: usize, ef: *ExceptionFrame) noreturn {
    const exception = @intToEnum(Exception, @truncate(u4, exception_));
    var stack_or_proc_ef = ef;
    // log("proc: {}, {}\n", .{ @ptrCast(*u8, proc.cur_proc.data.?), proc.cur_proc.?.* });
    if (exception == Exception.SYNC_EL0_64) {
        proc.cur_proc.?.ef = stack_or_proc_ef.*;
        stack_or_proc_ef = &proc.cur_proc.?.ef;
    }

    dispatch(exception, stack_or_proc_ef);

    switch (exception) {
        Exception.SYNC_INVALID_EL1H, Exception.IRQ_EL1H, Exception.FIQ_INVALID_EL1H, Exception.ERROR_INVALID_EL1H => {
            pop_ef(1, stack_or_proc_ef);
        },
        Exception.SYNC_EL0_64, Exception.IRQ_EL0_64, Exception.FIQ_INVALID_EL0_64, Exception.ERROR_INVALID_EL0_64 => {
            if (proc.cur_proc) |cur_proc| {
                if (cur_proc.state == proc.ProcState.RUNNING)
                    proc.run(cur_proc);
            }
            proc.schedule();
        },
        else => unreachable,
    }
}

fn log_ef(exception: Exception, ef: ExceptionFrame) void {
    log("\n{}\n", .{exception_names[@enumToInt(exception)]});
    const currentEL = asm volatile ("mrs x0, CurrentEL"
        : [ret] "=r" (-> usize)
    );
    log("EL{}\n", .{currentEL >> 2 & 0x3});
    const esr_el1 = asm ("mrs %[esr_el1], esr_el1"
        : [esr_el1] "=r" (-> usize)
    );
    const esr_el1_ec = (esr_el1 >> 26) & ((1 << 6) - 1);
    const esr_el1_iss = (esr_el1) & ((1 << 25) - 1);
    log("esr_el1 {x}, ec: {b}b, iss: {b}b (https://developer.arm.com/docs/ddi0595/b/aarch64-system-registers/esr_el1 )\n", .{ esr_el1, esr_el1_ec, esr_el1_iss });
    const elr_el1 = asm ("mrs %[elr_el1], elr_el1"
        : [elr_el1] "=r" (-> usize)
    );
    log("elr_el1 {x}\n", .{elr_el1});
    const spsr_el1 = asm ("mrs %[spsr_el1], spsr_el1"
        : [spsr_el1] "=r" (-> usize)
    );
    log("spsr_el1 {x}\n", .{spsr_el1});
    const far = arch.far_el1();
    log("far_el1 {x}, l1:{}, l2:{}, l3:{}\n", .{ far, pmap.l1x(far), pmap.l2x(far), pmap.l3x(far) });
}

fn dispatch(exception: Exception, ef: *ExceptionFrame) void {
    switch (exception) {
        // {exception type}_{taken from exception level}
        Exception.IRQ_EL1H => {
            timer.handlerInterruptPending1();
        },
        Exception.IRQ_EL0_64 => {
            // pop_ef(0);
        },
        Exception.SYNC_EL0_64 => {
            const esr = arch.esr_el1();
            if ((esr >> arch.ESR_ELx_EC_SHIFT) == arch.ESR_ELx_EC_SVC64) { // SVC instruction
                // log("\npid: {}, {}\n", .{
                //     proc.cur_proc.?.pid,
                //     @intToEnum(syscall.Syscall, @truncate(u3, proc.cur_proc.?.ef.xs[8])),
                // });

                ef.xs[0] = @intCast(usize, syscall.syscall(ef.xs[8], ef.xs[0..8].*));
            } else if ((esr >> arch.ESR_ELx_EC_SHIFT) == arch.ESR_ELx_EC_DABT_LOW) { // Data Abort from a lower Exception level
                if (user_memory_fault_handler() == false) proc.destory(proc.cur_proc.?);
            } else {
                log_ef(exception, ef.*);
                log("Unexpected el0 excpetion, killing process {}\n", .{proc.cur_proc.?.pid});
                proc.destory(proc.cur_proc.?);
            }
        },
        else => {
            log_ef(exception, ef.*);
            log("Execution is now stopped in exception handler\n", .{});
            while (true) {
                asm volatile ("wfe");
            }
        },
    }
}

const MemoryFaultType = enum {
    ADDRESS_SIZE_FAULT,
    TRANSLATION_FAULT,
    ACCESS_FLAG_FAULT,
    PERMISSION_FAULT,
};

fn user_memory_fault_handler() bool {
    // log("user_memory_fault_handler() pid: {}, far: 0x{x}\n", .{ proc.cur_proc.?.pid, arch.far_el1() });
    const data_fault_status_code = arch.esr_el1() & ((1 << 6) - 1);
    const data_fault_status_code_type = data_fault_status_code >> 4;
    if (data_fault_status_code_type != 0)
        panic("", null);

    const memory_fault_type = @intToEnum(MemoryFaultType, @truncate(u2, data_fault_status_code >> 2));
    const memory_fault_level = @truncate(u2, data_fault_status_code);
    const tt = proc.cur_proc.?.tt;
    switch (memory_fault_type) {
        MemoryFaultType.PERMISSION_FAULT => blk: {
            var pte: *pmap.TtEntry = undefined;
            var srcpp = pmap.page_lookup(tt, arch.far_el1(), &pte).?;
            if (pte.* & pmap.tte_cow_mask != pmap.tte_cow)
                break :blk;

            var dstpp = srcpp;
            if (srcpp.ref_count > 1) {
                dstpp = pmap.page_alloc(false) catch return false;
                errdefer pmap.page_decref(dstpp);

                const srcva = pmap.page2kva(srcpp);
                const dstva = pmap.page2kva(dstpp);
                std.mem.copy(u8, dstva[0..pmap.page_size], srcva[0..pmap.page_size]);
            }

            pmap.page_insert(tt, dstpp, pmap.round_down(arch.far_el1(), pmap.page_size), pmap.tte_ap_el1_rw_el0_rw) catch return false;

            return true;
        },
        else => {
            log("unsupported user memory fault: {}, destroying procces: {}\n", .{ memory_fault_type, proc.cur_proc.?.pid });
            return false;
        },
    }

    return false;
}

// push registers on to the kernel stack
//   el: indicates which exception level an exception is taken from
pub inline fn push_ef(comptime el: usize, ef: *ExceptionFrame) noreturn {
    asm volatile (
        \\  sub	sp, sp, #272
        \\  stp	x0, x1, [sp, #16 * 0]
        \\  stp	x2, x3, [sp, #16 * 1]
        \\  stp	x4, x5, [sp, #16 * 2]
        \\  stp	x6, x7, [sp, #16 * 3]
        \\  stp	x8, x9, [sp, #16 * 4]
        \\  stp	x10, x11, [sp, #16 * 5]
        \\  stp	x12, x13, [sp, #16 * 6]
        \\  stp	x14, x15, [sp, #16 * 7]
        \\  stp	x16, x17, [sp, #16 * 8]
        \\  stp	x18, x19, [sp, #16 * 9]
        \\  stp	x20, x21, [sp, #16 * 10]
        \\  stp	x22, x23, [sp, #16 * 11]
        \\  stp	x24, x25, [sp, #16 * 12]
        \\  stp	x26, x27, [sp, #16 * 13]
        \\  stp x28, x29, [sp, #16 * 14]
        :
        : [ef] "{sp}" (ef)
    );
    if (el == 0) {
        asm volatile ("mrs x21, sp_el0");
    } else {
        asm volatile ("add x21, sp, #272"
            :
            : [ef] "{sp}" (ef)
        );
    }
    asm volatile (
        \\  mrs	x22, elr_el1
        \\  mrs	x23, spsr_el1
        \\  stp	x30, x21, [sp, #16 * 15] 
        \\  stp	x22, x23, [sp, #16 * 16]
        :
        : [ef] "{sp}" (ef)
    );
}

// el: indicates which exception level an exception is taken from
pub inline fn pop_ef(comptime el: usize, ef: *ExceptionFrame) noreturn {
    if (el == 0) {
        asm volatile (
            \\  ldp	x22, x23, [sp, #16 * 16]
            \\  ldp	x30, x21, [sp, #16 * 15]
            \\  msr     sp_el0, x21
            \\  msr	elr_el1, x22			
            \\  msr	spsr_el1, x23
            \\  ldp	x0, x1, [sp, #16 * 0]
            \\  ldp	x2, x3, [sp, #16 * 1]
            \\  ldp	x4, x5, [sp, #16 * 2]
            \\  ldp	x6, x7, [sp, #16 * 3]
            \\  ldp	x8, x9, [sp, #16 * 4]
            \\  ldp	x10, x11, [sp, #16 * 5]
            \\  ldp	x12, x13, [sp, #16 * 6]
            \\  ldp	x14, x15, [sp, #16 * 7]
            \\  ldp	x16, x17, [sp, #16 * 8]
            \\  ldp	x18, x19, [sp, #16 * 9]
            \\  ldp	x20, x21, [sp, #16 * 10]
            \\  ldp	x22, x23, [sp, #16 * 11]
            \\  ldp	x24, x25, [sp, #16 * 12]
            \\  ldp	x26, x27, [sp, #16 * 13]
            \\  ldp	x28, x29, [sp, #16 * 14]
            \\  ldr     x0, =boot_stack
            \\  add     x0, x0, #8*(1 << 12)
            \\  str     x1, [x0, #-8]!     // store x1 on the new stack
            \\  ldr     x1, [sp]           // reread x0 into x1
            \\  str     x1, [x0, #-8]!     // store x0 on the new stack
            \\  mov     sp, x0             // load the new stack
            \\  ldp     x0, x1, [sp], #16  // load the saved registers
            \\  eret
            :
            : [ef] "{sp}" (ef)
            : "memory"
        );
    } else {
        asm volatile (
            \\  ldp	x22, x23, [sp, #16 * 16]
            \\  ldp	x30, x21, [sp, #16 * 15]
            \\  msr     sp_el0, x21
            \\  msr	elr_el1, x22			
            \\  msr	spsr_el1, x23
            \\  ldp	x0, x1, [sp, #16 * 0]
            \\  ldp	x2, x3, [sp, #16 * 1]
            \\  ldp	x4, x5, [sp, #16 * 2]
            \\  ldp	x6, x7, [sp, #16 * 3]
            \\  ldp	x8, x9, [sp, #16 * 4]
            \\  ldp	x10, x11, [sp, #16 * 5]
            \\  ldp	x12, x13, [sp, #16 * 6]
            \\  ldp	x14, x15, [sp, #16 * 7]
            \\  ldp	x16, x17, [sp, #16 * 8]
            \\  ldp	x18, x19, [sp, #16 * 9]
            \\  ldp	x20, x21, [sp, #16 * 10]
            \\  ldp	x22, x23, [sp, #16 * 11]
            \\  ldp	x24, x25, [sp, #16 * 12]
            \\  ldp	x26, x27, [sp, #16 * 13]
            \\  ldp	x28, x29, [sp, #16 * 14]
            \\  add	sp, sp, #272
            \\  eret
            :
            : [ef] "{sp}" (ef)
            : "memory"
        );
    }
    unreachable;
}

test "pop_ef" {
    std.debug.warn("\n", .{});
    std.debug.warn("{}\n", .{@sizeOf(ExceptionFrame)});
}
