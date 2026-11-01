const std = @import("std");
const Core = @import("../core.zig").Core;
const posix = std.posix;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const page_size_min = std.heap.page_size_min;

const EM_MEOW: u16 = 242;

const ADDRESS_SPACE_SIZE: usize = 0x1_0000_0000;
const PAGE_TABLE_SIZE: usize = 0x10_0000 * @sizeOf(PTE);

// Upper bound of the guest user address space.
const TASK_SIZE: usize = 0x1000_0000; // 256 MiB

const STACK_SIZE: usize = 0x004_0000; // 256 KiB

pub const SyscallResult = union(enum) {
    // The handler generally writes the return value to a0.
    // The caller is responsible for advancing pc.
    success,

    exited: u8,
};

pub const Memory = struct {
    allocator: Allocator,

    // pt is the flattened page table (4 MiB, managed by mmap)
    pt: [*]PTE,

    // 4 GiB, managed by mmap
    data: [*]align(page_size_min) u8,

    pub fn init(allocator: Allocator) !Memory {
        const prot_none: posix.PROT = .{};
        const prot_rw: posix.PROT = .{
            .READ = true,
            .WRITE = true,
        };
        const flags: posix.MAP = .{
            .TYPE = .PRIVATE,
            .ANONYMOUS = true,
        };

        const page_table = try std.posix.mmap(null, PAGE_TABLE_SIZE, prot_rw, flags, -1, 0);
        errdefer std.posix.munmap(page_table);

        const data = try std.posix.mmap(null, ADDRESS_SPACE_SIZE, prot_none, flags, -1, 0);
        errdefer std.posix.munmap(data);

        if (posix.system.mprotect(data.ptr, TASK_SIZE, prot_rw) != 0) {
            return error.MemoryProtectionFailed;
        }

        return .{
            .allocator = allocator,
            .pt = @ptrCast(page_table.ptr),
            .data = data.ptr,
        };
    }

    pub fn deinit(self: *Memory) void {
        const pte_bytes: [*]align(page_size_min) const u8 = @ptrCast(@alignCast(self.pt));
        std.posix.munmap(pte_bytes[0..PAGE_TABLE_SIZE]);
        std.posix.munmap(self.data[0..ADDRESS_SPACE_SIZE]);
        self.* = undefined;
    }

    fn checkAccess(self: *const Memory, addr: u32, comptime op: PTE.Op) bool {
        return self.pt[addr >> 12].checkAccess(op);
    }

    fn checkRange(self: *const Memory, addr: u32, len: u32, comptime op: PTE.Op) bool {
        if (len == 0) return true;
        const end = @as(u64, addr) + len;
        if (end > TASK_SIZE) {
            return false;
        }

        const first: usize = addr >> 12;
        const last: usize = @intCast((end - 1) >> 12);
        for (first..last + 1) |idx| {
            if (!self.pt[idx].checkAccess(op)) {
                return false;
            }
        }
        return true;
    }

    /// Fetch a 4-byte instruction from an aligned address.
    pub fn fetch(self: *Memory, addr: u32) error{EmuAccessFault}!u32 {
        assert(addr % 4 == 0);
        if (!self.checkAccess(addr, .execute)) {
            return error.EmuAccessFault;
        }
        const bytes = self.data[addr..][0..4];
        return std.mem.readInt(u32, bytes, .little);
    }

    pub fn loadAligned(self: *Memory, comptime T: type, addr: u32) error{EmuAccessFault}!T {
        assert(addr % @sizeOf(T) == 0);
        if (!self.checkAccess(addr, .read)) {
            return error.EmuAccessFault;
        }
        const bytes = self.data[addr..][0..@sizeOf(T)];
        return switch (T) {
            u8 => bytes[0],
            u16 => std.mem.readInt(u16, bytes, .little),
            u32 => std.mem.readInt(u32, bytes, .little),
            else => @compileError("unsupported Memory load width: " ++ @typeName(T)),
        };
    }

    pub fn storeAligned(self: *Memory, comptime T: type, addr: u32, value: T) error{EmuAccessFault}!void {
        assert(addr % @sizeOf(T) == 0);
        if (!self.checkAccess(addr, .write)) {
            return error.EmuAccessFault;
        }
        const bytes = self.data[addr..][0..@sizeOf(T)];
        switch (T) {
            u8 => bytes[0] = value,
            u16 => std.mem.writeInt(u16, bytes, value, .little),
            u32 => std.mem.writeInt(u32, bytes, value, .little),
            else => @compileError("unsupported Memory store width: " ++ @typeName(T)),
        }
    }

    // Round [start, end) outward to pages.
    // `pte` must be valid, and all existing entries in the range must be invalid.
    fn mapPages(self: *Memory, start: u32, end: u32, pte: PTE) !void {
        assert(pte.isValid());

        const start_idx = start >> 12;
        const end_idx = ((end - 1) >> 12) + 1;

        for (start_idx..end_idx) |idx| {
            if (self.pt[idx].isValid()) {
                return error.OverlappingPages;
            }
        }
        for (start_idx..end_idx) |idx| {
            self.pt[idx] = pte;
        }
    }

    /// Returns the ELF entry point.
    pub fn loadElf(self: *Memory, data: []const u8) !u32 {
        var reader = std.Io.Reader.fixed(data);
        const header = try std.elf.Header.read(&reader);
        if (header.is_64) return error.NotElf32;
        if (header.endian != .little) return error.NotLittleEndian;
        if (header.type != .EXEC) return error.NotExecutable;
        if (@backingInt(header.machine) != EM_MEOW) return error.WrongMachine;
        if (header.entry & 3 != 0) return error.MisalignedEntry;
        if (header.phnum == 0) return error.NoLoadableSegments;

        // The std.elf buffer iterator uses the standard header size as its stride
        // and slices at each offset, so validate the complete table first.
        if (header.phentsize != @sizeOf(std.elf.Elf32.Phdr))
            return error.InvalidProgramHeaderSize;
        const table_end = header.phoff + @as(u64, header.phnum) * header.phentsize;
        if (table_end > data.len) return error.ElfTruncated;

        var saw_load = false;
        var headers = header.iterateProgramHeadersBuffer(data);
        while (try headers.next()) |phdr| {
            switch (phdr.type) {
                .DYNAMIC, .INTERP => return error.DynamicLinkingUnsupported,
                .LOAD => {
                    if (phdr.filesz > phdr.memsz) return error.FileSizeExceedsMemSize;
                    if (phdr.memsz == 0) continue;
                    if (phdr.offset + phdr.filesz > data.len) return error.ElfTruncated;

                    const file_data = data[@intCast(phdr.offset)..][0..@intCast(phdr.filesz)];
                    // std.elf widens ELF32 fields to u64; these casts are lossless.
                    const addr: u32 = @intCast(phdr.vaddr);
                    const len: u32 = @intCast(phdr.memsz);
                    const end = @as(u64, addr) + len;
                    if (end > TASK_SIZE) {
                        return error.InvalidSegmentRange;
                    }
                    if (end > TASK_SIZE - STACK_SIZE - 4096) {
                        return error.SegmentOverlapsStack;
                    }
                    const p_flags_rwx: u3 = @truncate(@backingInt(phdr.flags));
                    const rwx: PTE.RWX = switch (p_flags_rwx) {
                        4 => .read,
                        6 => .read_write,
                        5 => .read_execute,
                        else => return error.UnsupportedSegmentPermissions,
                    };
                    try self.mapPages(addr, @intCast(end), .withPerm(rwx));
                    @memcpy(self.data[addr..][0..file_data.len], file_data);
                    saw_load = true;
                },
                else => {},
            }
        }

        if (!saw_load) return error.NoLoadableSegments;
        return @intCast(header.entry);
    }

    /// Initialize argc, argv, envp, and AT_NULL; return a 16-byte-aligned sp.
    pub fn initializeStack(self: *Memory, stack_init: StackInit) !u32 {
        const size = stack_init.computeSize();
        if (size > STACK_SIZE) return error.ArgumentsTooLarge;
        const sp = TASK_SIZE - size;

        const stack_bottom = TASK_SIZE - STACK_SIZE;
        try self.mapPages(stack_bottom, TASK_SIZE, .stack);
        try self.mapPages(stack_bottom - 4096, stack_bottom, .stack_guard);

        @memset(self.data[stack_bottom..sp], 0);
        stack_init.fill(@intCast(sp), self.data[sp..TASK_SIZE]);
        return @intCast(sp);
    }

    pub fn handleSyscall(self: *Memory, core: *Core) SyscallResult {
        _ = self;
        switch (core.xreg(.x7)) {
            // exit, exit_group
            93, 94 => {
                const a0: u32 = core.xreg(.x8);
                return .{ .exited = @truncate(a0) };
            },
            else => {
                core.write_reg(.x8, @bitCast(@as(i32, -38))); // -ENOSYS
                return .success;
            },
        }
    }
};

pub const StackInit = struct {
    argv: []const [:0]const u8,
    env: []const [:0]const u8,

    pub fn computeSize(init: StackInit) u32 {
        // argc, argv, NULL, env, NULL, {AT_NULL, 0}
        var size: usize = (init.argv.len + init.env.len + 5) * 4;

        for (init.argv) |arg| {
            size += arg.len + 1;
        }
        for (init.env) |arg| {
            size += arg.len + 1;
        }

        return @intCast((size + 15) / 16 * 16);
    }

    pub fn fill(init: StackInit, guest_base: u32, buffer: []u8) void {
        // write argc
        std.mem.writeInt(u32, buffer[0..4], @intCast(init.argv.len), .little);

        var table_offset: u32 = 4;
        var string_offset: u32 = @intCast((init.argv.len + init.env.len + 5) * 4);

        // write argv
        for (init.argv) |arg| {
            std.mem.writeInt(u32, buffer[table_offset..][0..4], guest_base + string_offset, .little);

            @memcpy(buffer[string_offset..][0..arg.len], arg);
            buffer[string_offset + arg.len] = 0;

            table_offset += 4;
            string_offset += @intCast(arg.len + 1);
        }

        // write NULL
        @memset(buffer[table_offset..][0..4], 0);
        table_offset += 4;

        // write envp
        for (init.env) |arg| {
            std.mem.writeInt(u32, buffer[table_offset..][0..4], guest_base + string_offset, .little);

            @memcpy(buffer[string_offset..][0..arg.len], arg);
            buffer[string_offset + arg.len] = 0;

            table_offset += 4;
            string_offset += @intCast(arg.len + 1);
        }

        // write NULL
        @memset(buffer[table_offset..][0..4], 0);
        table_offset += 4;

        // write {AT_NULL, 0}
        @memset(buffer[table_offset..][0..8], 0);
    }
};

// PTE does not do translation. It only checks permissions.
const PTE = packed struct(u32) {
    rwx: RWX,
    tag: Tag,
    unused: u24 = 0,

    pub const RWX = packed struct(u3) {
        r: bool,
        w: bool,
        x: bool,

        pub const none: RWX = .{ .r = false, .w = false, .x = false };
        pub const read: RWX = .{ .r = true, .w = false, .x = false };
        pub const read_write: RWX = .{ .r = true, .w = true, .x = false };
        pub const read_execute: RWX = .{ .r = true, .w = false, .x = true };
    };

    pub const Tag = enum(u5) {
        invalid = 0,
        guard = 1,
        normal = 2,
        stack = 3,
        _,
    };

    pub const invalid: PTE = .{
        .rwx = .none,
        .tag = .invalid,
    };

    pub const stack: PTE = .{
        .rwx = .read_write,
        .tag = .stack,
    };

    pub const stack_guard: PTE = .{
        .rwx = .none,
        .tag = .guard,
    };

    pub fn withPerm(rwx: RWX) PTE {
        return .{
            .rwx = rwx,
            .tag = .normal,
        };
    }

    pub const Op = enum {
        read,
        write,
        execute,
    };

    fn isValid(e: PTE) bool {
        return e.tag != .invalid;
    }

    fn checkAccess(e: PTE, comptime op: Op) bool {
        switch (op) {
            .read => return e.rwx.r,
            .write => return e.rwx.w,
            .execute => return e.rwx.x,
        }
    }
};
