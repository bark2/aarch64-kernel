# ZIG := ~/src/kernel/zig
ZIG := zig

all: clean kernel user tar kernel.img

kernel:
	$(ZIG) build

user:
	$(ZIG) build user

tar:
	tar -cf ramdisk zig-cache/kernel zig-cache/user

rd.o: ramdisk
	aarch64-none-elf-ld -r -b binary -o rd.o ramdisk

kernel.img: rd.o
	$(ZIG) build elf
	aarch64-none-elf-objcopy -O binary zig-cache/kernel.elf kernel.img

clean:
	rm kernel.elf rd.o zig-cache/*.o zig-cache/kernel* zig-cache/user* >/dev/null 2>/dev/null || true

run: all
	qemu-system-aarch64 -M raspi3 -kernel kernel.img -serial null -serial stdio -display none

debug: all
	qemu-system-aarch64 -M raspi3 -kernel kernel.img -serial null -serial stdio -display none -S -s
