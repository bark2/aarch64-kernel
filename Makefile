# ZIG := ~/src/kernel/zig
ZIG := zig

all: extern kernel user tar kernel.img

extern: extern/*
	aarch64-none-elf-gcc -g -c ./extern/delays.c
	aarch64-none-elf-gcc -g -c ./extern/sd.c
	mv delays.o zig-cache/delays.o
	mv sd.o zig-cache/sd.o

kernel: extern
	$(ZIG) build

user:
	$(ZIG) build user
	dd if=zig-cache/user of=sd.img
	qemu-img resize -f raw sd.img 1M

tar:
	tar -cf ramdisk zig-cache/kernel

rd.o: ramdisk
	aarch64-none-elf-ld -r -b binary -o rd.o ramdisk

kernel.img: rd.o
	$(ZIG) build elf
	aarch64-none-elf-objcopy -O binary zig-cache/kernel.elf kernel.img

ifeq ($(OS),Windows_NT)
clean:
	rm kernel.elf rd.o zig-cache/*.o zig-cache/kernel* zig-cache/user* >/dev/null 2>/dev/null || true
	aarch64-none-elf-gcc -g -c ./extern/delays.c
	aarch64-none-elf-gcc -g -c ./extern/sd.c
	mv delays.o zig-cache/delays.o
	mv sd.o zig-cache/sd.o	
else
clean:
	rm kernel.elf rd.o zig-cache/*.o zig-cache/kernel* zig-cache/user* >/dev/null 2>/dev/null || true
endif

run: all
	qemu-system-aarch64 -M raspi3 -kernel kernel.img -serial null -serial stdio -display none -drive file=sd.img,if=sd,format=raw 

debug: all
	qemu-system-aarch64 -M raspi3 -kernel kernel.img -serial null -serial stdio -display none -drive file=sd.img,if=sd,format=raw -S -s
