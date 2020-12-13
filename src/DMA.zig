const uart = @import("uart.zig");
const log = uart.log;

const BaseDMA :u32 =  0x3F007000;
// 0 Transfer Information TI
// 1 Source Address SOURCE_AD
// 2 Destination Address DEST_AD
// 3 Transfer Length TXFR_LEN
// 4 2D Mode Stride STRIDE
// 5 Next Control Block
// Address NEXTCONBK
// 6-7 Reserved – set to zero. N/A
const ControlBlock = struct
{
    cs              :u32,
    cb              :u32,
    tInfo           :u32,
    sAddr           :u32,
    dAddr           :u32,
    tLen            :u32,
    modeStride2D    :u32,
    nextCB          :u32,  
    dbg             :u32,
    reserved        :[0x37]u32,
};
const DmaController = struct{
    status :u32,
    en :u32,

};
const dmaCh : *[15]ControlBlock =@intToPtr(*[15]ControlBlock,BaseDMA);
const dmaController :*DmaController = @intToPtr(*DmaController,BaseDMA + 0xfe0);


pub fn init()void {
    dmaController.en = 1;
    log("1 {x} \n",.{dmaController.en});
    log("2 {x} \n",.{dmaController.status});

}