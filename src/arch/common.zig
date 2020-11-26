pub inline fn invalidate_tlb() void {
    asm volatile (
        \\    TLBI     VMALLE1
        \\    DSB      SY
        \\    ISB
    );
}
