set confirm off

echo + target remote localhost:1234\n
target remote localhost:1234

echo + symbol-file zig-cache/kernel\n
set architecture aarch64
file zig-cache/kernel
b main.zig:kern_main
c
layout regs
layout prev
