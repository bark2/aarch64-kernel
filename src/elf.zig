pub const Elf = extern struct {
    magic: u32,
    elf: [12]u8,
    type: u16,
    machine: u16,
    version: u32,
    entry: u64,
    phoff: u64,
    shoff: u64,
    flags: u32,
    ehsize: u16,
    phentsize: u16,
    phnum: u16,
    shentsize: u16,
    shnum: u16,
    shstrndx: u16,
};
pub const Proghdr = extern struct {
    type: u32,
    flags: u32,
    offset: u64,
    va: u64,
    pa: u64,
    filesz: u64,
    memsz: u64,
    do_align: u64,
};
pub const Secthdr = extern struct {
    name: u32,
    type: u32,
    flags: u64,
    addr: u64,
    offset: u64,
    size: u64,
    addralign: u64,
    entsize: u64,
};

pub const ELF_MAGIC: u32 = 0x464C457F;
// Values for Proghdr::type
pub const ELF_PROG_LOAD = 1;
// Flag bits for Proghdr::flags
pub const ELF_PROG_FLAG_EXEC = 1;
pub const ELF_PROG_FLAG_WRITE = 2;
pub const ELF_PROG_FLAG_READ = 4;
// Values for Secthdr::type
pub const ELF_SHT_NULL = 0;
pub const ELF_SHT_PROGBITS = 1;
pub const ELF_SHT_SYMTAB = 2;
pub const ELF_SHT_STRTAB = 3;
// Values for Secthdr::name
pub const ELF_SHN_UNDEF = 0;
