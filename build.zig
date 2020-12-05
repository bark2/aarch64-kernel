const std = @import("std");
const warn = std.debug.warn;
const Builder = std.build.Builder;
const builtin = @import("builtin");

// llvm-objdump zig-cache/kernel.aarch64.bin --section=.text -dl -h | less
pub fn build(b: *Builder) !void {
    const mode = b.standardReleaseOptions();
    const arch = std.zig.CrossTarget{
        .cpu_arch = .aarch64,
        .os_tag = .freestanding,
        .cpu_model = .{ .explicit = &std.Target.aarch64.cpu.cortex_a53 },
    };

    // const sd = b.addObject("sd", "extern/sd.c");
    // sd.addObjectFile("extern/delays.c");
    // sd.setOutputDir("zig-cache");
    // sd.setBuildMode(mode);
    // sd.setTarget(arch);
    // b.default_step.dependOn(&sd.step);

    const kernel = b.addExecutable("kernel", "src/main.zig");
    kernel.addAssemblyFile("src/set_ttbr0_el1_and_t0sz.s");
    kernel.addAssemblyFile("src/exception.s");
    kernel.addObjectFile("zig-cache/delays.o");
    kernel.addObjectFile("zig-cache/sd.o");
    kernel.setOutputDir("zig-cache");
    kernel.setBuildMode(mode);
    kernel.setTarget(arch);
    // const linker_script = if (want_gdb) "src/kernel.debug.ld" else "src/kernel.ld";
    const linker_script = "src/kernel.debug.ld";
    kernel.setLinkerScriptPath(linker_script);
    b.default_step.dependOn(&kernel.step);

    const user = b.step("user", "");
    const user_run = b.addExecutable("user", "src/user.zig");
    user_run.setOutputDir("zig-cache");
    user_run.setBuildMode(mode);
    user_run.setTarget(arch);
    user_run.setLinkerScriptPath("src/user.debug.ld");
    user.dependOn(&user_run.step);
    // b.default_step.dependOn(&user_run.step);

    const elf = b.step("elf", "link and compile the bootloader with kernel ramdisk");
    const run_elf = b.addExecutable("kernel.elf", "src/boot.zig");
    run_elf.addObjectFile("rd.o");
    run_elf.setOutputDir("zig-cache");
    run_elf.setBuildMode(mode);
    run_elf.setTarget(arch);
    run_elf.setLinkerScriptPath("src/boot.ld");
    elf.dependOn(&run_elf.step);
}
