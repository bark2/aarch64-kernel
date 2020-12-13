const pmap = @import("pmap.zig");
const uart = @import("uart.zig");
const log = uart.log;

const  TIMER_MEM_BASE_ADDR:u32 = 0x3f000000;
const clock_freq =0xF4240; // 1mhz = 1000000  the clock frequency 
var holder_of_time_to_interrupt :[4]u32 = undefined;

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
    cmp :[4] u32,
   // cmp0: u32,
   // cmp1: u32,
   // cmp2: u32,
   // cmp3: u32,

};
const controller : *irqController =@intToPtr(*irqController,0x3f000000 + 0xB200);
const sysTimer:* systemTimer = @intToPtr(*systemTimer,0x3f000000 + 0x3000);

inline fn enable_irq() void {
     asm  volatile("MSR DAIFClr, #2");
}
inline fn disable_irq() void {
    asm volatile ("MSR  DAIFSet, #2");
}

//ms : interrupt every X ms
//clockNumber : there is 4 clock to use in system timer from 0 to 3
pub fn setTimer(ms :u32,clockNumber:u32)void{
    if (ms >= 1000){
        holder_of_time_to_interrupt[clockNumber] =  (ms/1000) * clock_freq;
    }
    else{
        holder_of_time_to_interrupt[clockNumber] =   clock_freq / (ms +1);
    }
    sysTimer.cmp[clockNumber] =sysTimer.clockLow + holder_of_time_to_interrupt[clockNumber];
}

pub fn handlerInterruptPending1()void{
    var clockCompare :u32 = controller.IRQ_pending_1;
    log("ieq,timer handler: {x}\n",.{clockCompare});
    if(clockCompare == 8){ // clocktimer3  
        sysTimer.cmp[3] = sysTimer.clockLow +  holder_of_time_to_interrupt[3];
        }
    else if (clockCompare < 8){ 
        sysTimer.cmp[clockCompare >> 1] =sysTimer.clockLow + holder_of_time_to_interrupt[clockCompare >> 1];
    }
    // clear the bit
    sysTimer.controlStatus = controller.IRQ_pending_1;
}

pub fn init()void {
    controller.Enable_IRQs_1 =   0xf; // all 4 timers enable
    enable_irq();
}