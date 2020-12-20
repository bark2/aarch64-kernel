pub fn ttbr0_el1() u64 {
    return asm ("mrs %[res], ttbr0_el1"
        : [res] "=r" (-> u64)
    );
}

pub fn set_ttbr0_el1(val: u64) void {
    asm volatile ("msr ttbr0_el1, %[val]"
        :
        : [val] "r" (val)
    );
}

pub fn ttbr1_el1() u64 {
    return asm ("mrs %[res], ttbr1_el1"
        : [res] "=r" (-> u64)
    );
}

pub fn set_ttbr1_el1(val: u64) void {
    asm volatile ("msr ttbr1_el1, %[val]"
        :
        : [val] "r" (val)
    );
}

pub fn tcr_el1() u64 {
    return asm ("mrs %[res], tcr_el1"
        : [res] "=r" (-> u64)
    );
}

pub fn set_tcr_el1(val: u64) void {
    asm volatile ("msr tcr_el1, %[val]"
        :
        : [val] "r" (val)
    );
}

pub fn hcr_el2() u64 {
    return asm ("mrs %[res], hcr_el2"
        : [res] "=r" (-> u64)
    );
}

pub fn set_hcr_el2(val: u64) void {
    asm volatile ("msr hcr_el2, %[val]"
        :
        : [val] "r" (val)
    );
}

pub fn sctlr_el1() u64 {
    return asm ("mrs %[res], sctlr_el1"
        : [res] "=r" (-> u64)
    );
}

pub fn set_sctlr_el1(val: u64) void {
    asm volatile ("msr sctlr_el1, %[val]"
        :
        : [val] "r" (val)
    );
}

pub fn sctlr_el3() u64 {
    return asm ("mrs %[res], sctlr_el3"
        : [res] "=r" (-> u64)
    );
}

pub fn set_sctlr_el3(val: u64) void {
    asm volatile ("msr sctlr_el3, %[val]"
        :
        : [val] "r" (val)
    );
}

pub inline fn isb() void {
    asm volatile ("isb");
}

pub inline fn curr_el() usize {
    return (asm volatile ("mrs %[res], CurrentEL"
        : [res] "=r" (-> usize)
    ) & (0x3 << 2)) >> 2;
}

pub inline fn vbar_el1() u64 {
    return asm ("mrs %[res], vbar_el1"
        : [res] "=r" (-> u64)
    );
}

pub inline fn set_vbar_el1(val: u64) void {
    asm volatile ("msr vbar_el1, %[val]"
        :
        : [val] "r" (val)
    );
}

pub inline fn set_mair_el1(val: u64) void {
    asm volatile ("msr mair_el1, %[val]"
        :
        : [val] "r" (val)
    );
}

pub inline fn esr_el1() u64 {
    return asm ("mrs %[esr], esr_el1"
        : [esr] "=r" (-> u64)
    );
}

pub inline fn set_esr_el1(val: usize) void {
    return asm ("msr esr_el1, %[val]"
        :
        : [val] "r" (val)
    );
}

pub inline fn set_spsr_el1(val: usize) void {
    asm volatile ("msr spsr_el1, %[val]"
        :
        : [val] "r" (val)
    );
}

pub inline fn spsr_el1() u64 {
    return asm ("mrs %[res], spsr_el1"
        : [res] "=r" (-> u64)
    );
}

pub inline fn set_elr_el1(val: usize) void {
    asm volatile ("msr elr_el1, %[val]"
        :
        : [val] "r" (val)
    );
}

pub inline fn elr_el1() u64 {
    return asm ("mrs %[res], elr_el1"
        : [res] "=r" (-> u64)
    );
}

pub inline fn x0() u64 {
    return asm (""
        : [res] "=r" (-> u64)
    );
}

pub inline fn x8() u64 {
    return asm (""
        : [res] "=r" (-> u64)
    );
}

pub inline fn ID_AA64MMFR2_EL1() u64 {
    return asm ("mrs %[res], ID_AA64MMFR2_EL1"
        : [res] "=r" (-> u64)
    );
}

pub inline fn ID_AA64MMFR1_EL1() u64 {
    return asm ("mrs %[res], ID_AA64MMFR2_EL1"
        : [res] "=r" (-> u64)
    );
}

pub inline fn far_el1() u64 {
    return asm ("mrs %[res], far_el1"
        : [res] "=r" (-> u64)
    );
}
