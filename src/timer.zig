const pmap = @import("pmap.zig");
const uart = @import("uart.zig");
const log = uart.log;

const  TIMER_MEM_BASE_ADDR:u32 = 0x3f000000;
const clock_freq =0xF4240; // 1mhz = 1000000  the clock frequency 
var holder_of_time_to_interrupt :u32 = 0;
const armTimer = struct {
    load: u32,
    value: u32,
    control: u32,
    clear: u32,
    RAWIRQ: u32,
    maskedIRQ: u32,
    reload: u32,
};

const irqController = struct {
    IRQ_basic_pending: u32,
    IRQ_pending_1: u32,
    IRQ_pending_2: u32,
    FIQ_control: u32,
    Enable_IRQs_1: u32,
    Enable_IRQs_2: u32,
    Enable_Basic_IRQs: u32,
    Disable_IRQs_1: u32,
    Disable_IRQs_2: u32,
    Disable_Basic_IRQs: u32,
};

const systemTimer = struct {
    controlStatus: u32,
    clockLow: u32,
    clockHigh: u32,
    cmp0: u32,
    cmp1: u32,
    cmp2: u32,
    cmp3: u32,

};
const controller : *irqController =@intToPtr(*irqController,0x3f000000 + 0xB200);
const timer : *armTimer = @intToPtr(*armTimer, 0x3f000000 + 0xb400);
const sysTimer:* systemTimer = @intToPtr(*systemTimer,0x3f000000 + 0x3000);

inline fn enable_irq() void {
     asm  volatile("MSR DAIFClr, #2");
}
inline fn disable_irq() void {
    asm volatile ("MSR  DAIFSet, #2");
}

pub fn setTimer(ms :u32)void{
    if (ms >= 1000){
        holder_of_time_to_interrupt =  (ms/1000) * clock_freq;
    }
    else{
        holder_of_time_to_interrupt =   clock_freq;
    }

}

pub fn handlerInterrupt()void{
    var irq :u32 = controller.IRQ_pending_1;
     log("1: {x}\n",.{irq});
    if(irq == 2){ // case of irq_1
        var clo:u32 = sysTimer.clockLow;
        clo = 0x100000; //1sec
        sysTimer.cmp0 = clo;
        sysTimer.controlStatus = 2;
    }
}

//ms : interrupt every X ms
//clockNumber : there is 4 clock to use in system timer from 0 to 3
pub fn init(ms:u32,comptime clockNumber:u32)void {
    setTimer(3000);
    controller.Enable_IRQs_1 =   1 << clockNumber;
    var clo:u32 = sysTimer.clockLow;
    const list  = @ptrCast([*] u32, &sysTimer.cmp0);
    list[clockNumber] =clo + holder_of_time_to_interrupt;
    enable_irq();
}