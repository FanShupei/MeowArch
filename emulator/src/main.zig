const std = @import("std");
const Memory = @import("user/memory.zig").Memory;
const Core = @import("core.zig").Core;
const exec = @import("exec.zig");

const assert = std.debug.assert;
const panic = std.debug.panic;
const cwd = std.Io.Dir.cwd;
const stdout = std.Io.File.stdout;

const CliOptions = struct {
    argv: [][:0]const u8,
    argv0: ?[:0]const u8,
    env: [][:0]const u8,

    trace: bool,
    max_steps: ?u64,

    pub const usage =
        \\Usage: meow-user [options] <program> [arguments...]
        \\
        \\Run a static Meow32 ELF executable.
        \\
        \\Options:
        \\  --argv0 NAME     Override the guest's argv[0].
        \\  -E, --env TEXT   Append a guest environment string (repeatable).
        \\  --trace          Print executed PCs and instruction words to stderr.
        \\  --max-steps N    Stop after N retired instructions.
        \\  -h, --help       Show this help.
        \\  --               End emulator options.
        \\
        \\Options must precede the program path. Everything after it is passed
        \\unchanged to the guest. The guest environment is empty by default.
        \\
        \\Examples:
        \\  meow-user program.elf hello
        \\  meow-user -E LANG=C --env USER=guest program.elf
        \\  meow-user --trace --max-steps 1000 program.elf
        \\
    ;

    fn printCliError(comptime fmt: []const u8, args: anytype) error{CliError} {
        std.debug.print("meow-user: " ++ fmt ++ "\n", args);
        return error.CliError;
    }

    fn parse(arena: std.mem.Allocator, args: std.process.Args) error{ CliError, PrintHelp }!CliOptions {
        var arg_iter = args.iterate();
        defer arg_iter.deinit();
        _ = arg_iter.next();

        var opt_argv: std.ArrayList([:0]const u8) = .empty;
        var opt_env: std.ArrayList([:0]const u8) = .empty;
        var opt_trace = false;
        var opt_max_steps: ?u64 = null;
        var opt_argv0: ?[:0]const u8 = null;

        var positional = false;
        while (arg_iter.next()) |arg| {
            if (positional) {
                opt_argv.append(arena, arg) catch panic("cannot allocate guest arguments", .{});
                continue;
            }
            if (!std.mem.startsWith(u8, arg, "-")) {
                opt_argv.append(arena, arg) catch panic("cannot allocate guest arguments", .{});
                positional = true;
                continue;
            }

            if (std.mem.eql(u8, arg, "--")) {
                positional = true;
            } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                return error.PrintHelp;
            } else if (std.mem.eql(u8, arg, "--trace")) {
                opt_trace = true;
            } else if (std.mem.eql(u8, arg, "--argv0")) {
                opt_argv0 = arg_iter.next() orelse {
                    return printCliError("--argv0 requires a value", .{});
                };
            } else if (std.mem.eql(u8, arg, "-E") or std.mem.eql(u8, arg, "--env")) {
                const value = arg_iter.next() orelse {
                    return printCliError("{s} requires a value", .{arg});
                };
                opt_env.append(arena, value) catch panic("cannot allocate guest environment", .{});
            } else if (std.mem.eql(u8, arg, "--max-steps")) {
                const value = arg_iter.next() orelse {
                    return printCliError("--max-steps requires a value", .{});
                };
                opt_max_steps = std.fmt.parseInt(u64, value, 0) catch {
                    return printCliError("invalid step limit: {s}", .{value});
                };
            } else {
                return printCliError("unknown option: {s}", .{arg});
            }
        }

        if (opt_argv.items.len == 0) {
            return printCliError("missing program", .{});
        }

        return .{
            .argv = opt_argv.items,
            .env = opt_env.items,
            .argv0 = opt_argv0,
            .trace = opt_trace,
            .max_steps = opt_max_steps,
        };
    }
};

pub fn main(init: std.process.Init) u8 {
    const arena = init.arena.allocator();

    const options: CliOptions = CliOptions.parse(arena, init.minimal.args) catch |e| switch (e) {
        error.PrintHelp => {
            stdout().writeStreamingAll(init.io, CliOptions.usage) catch |err| {
                std.debug.print("meow-user: cannot write help: {t}\n", .{err});
                return 1;
            };
            return 0;
        },
        error.CliError => {
            // The parse function already prints diagnostics to stderr
            return 1;
        },
    };

    const elf_path = options.argv[0];
    if (options.argv0) |argv0| {
        options.argv[0] = argv0;
    }

    switch (run(
        init.gpa,
        init.io,
        elf_path,
        options.argv,
        options.env,
        options.trace,
        options.max_steps,
    )) {
        .host_error => {
            return 1;
        },
        .exited => |code| {
            return code;
        },
        .signal => |s| {
            std.debug.print("meow-user: uncaught signal ({t})\n", .{s});
            terminateWithSignal(s);
        },
    }
}

fn terminateWithSignal(s: RunResult.Signal) noreturn {
    const sig: std.posix.SIG = switch (s) {
        .sigsegv => .SEGV,
        .sigbus => .BUS,
        .sigill => .ILL,
        .sigfpe => .FPE,
        .sigtrap => .TRAP,
    };
    // Preserve the guest's terminating signal instead of invoking Zig's
    // host crash handler or an inherited ignored disposition.
    const action: std.posix.Sigaction = .{
        .handler = .{ .handler = std.posix.SIG.DFL },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(sig, &action, null);
    var mask = std.posix.sigemptyset();
    std.posix.sigaddset(&mask, sig);
    std.posix.sigprocmask(std.posix.SIG.UNBLOCK, &mask, null);

    std.posix.raise(sig) catch {};

    std.debug.print("meow-user: cannot raise signal\n", .{});
    std.process.exit(1);
}

const MAX_FILE_SIZE: std.Io.Limit = .limited(16 * 1024 * 1024);

const RunResult = union(enum) {
    host_error,
    exited: u8,
    signal: Signal,

    const Signal = enum {
        sigsegv,
        sigbus,
        sigill,
        sigfpe,
        sigtrap,
    };
};

fn run(
    gpa: std.mem.Allocator,
    io: std.Io,
    elf_path: [:0]const u8,
    argv: []const [:0]const u8,
    env: []const [:0]const u8,
    opt_trace: bool,
    opt_max_steps: ?u64,
) RunResult {
    const data = cwd().readFileAlloc(io, elf_path, gpa, MAX_FILE_SIZE) catch |err| {
        std.debug.print("meow-user: cannot read {s}: {t}\n", .{ elf_path, err });
        return .host_error;
    };
    defer gpa.free(data);

    var memory = Memory.init(gpa) catch |err| {
        std.debug.print("meow-user: memory initialization failed: {t}\n", .{err});
        return .host_error;
    };
    defer memory.deinit();

    const elf_entry = memory.loadElf(data) catch |err| {
        std.debug.print("meow-user: cannot load elf {s}: {t}\n", .{ elf_path, err });
        return .host_error;
    };

    const initial_sp = memory.initializeStack(.{
        .argv = argv,
        .env = env,
    }) catch |err| {
        std.debug.print("meow-user: cannot initialize stack: {t}\n", .{err});
        return .host_error;
    };

    assert(elf_entry % 4 == 0);
    var core: Core = .{ .state_pc = elf_entry };
    core.write_reg(.sp, initial_sp);

    var retired: u64 = 0;
    while (true) {
        if (opt_max_steps) |limit| {
            if (retired >= limit) {
                std.debug.print("meow-user: step limit reached\n", .{});
                return .host_error;
            }
        }

        const pc = core.pc();
        const inst_bits = memory.fetch(pc) catch {
            std.debug.print("meow-user: fetch error, pc={x:0>8}\n", .{pc});
            return .{ .signal = .sigsegv };
        };

        if (opt_trace) {
            std.debug.print("meow-user: trace, pc={x:0>8}, inst={x:0>8}\n", .{ pc, inst_bits });
        }

        var npc: exec.NextPc = .init(pc +% 4);
        const outcome = exec.execute(&core, &memory, .{ .bits = inst_bits }, &npc);

        switch (outcome) {
            .ok => {
                core.set_pc(npc.next_pc);
                retired += 1;
            },
            .system_call => {
                switch (memory.handleSyscall(&core)) {
                    .success => {
                        core.set_pc(pc +% 4);
                    },
                    .exited => |code| {
                        return .{ .exited = code };
                    },
                }
            },

            .breakpoint => {
                std.debug.print("meow-user: breakpoint, pc={x:0>8}, inst={x:0>8}\n", .{ pc, inst_bits });
                return .{ .signal = .sigtrap };
            },
            .invalid_instruction, .hypervisor_call => {
                std.debug.print("meow-user: invalid instruction, pc={x:0>8}, inst={x:0>8}\n", .{ pc, inst_bits });
                return .{ .signal = .sigill };
            },
            .misaligned_target => {
                std.debug.print("meow-user: misaligned target, pc={x:0>8}, inst={x:0>8}\n", .{ pc, inst_bits });
                return .{ .signal = .sigbus };
            },
            .misaligned_access => |e| {
                std.debug.print("meow-user: misaligned access, pc={x:0>8}, inst={x:0>8}, addr={x:0>8}\n", .{ pc, inst_bits, e.addr });
                return .{ .signal = .sigbus };
            },
            .access_fault => |e| {
                std.debug.print("meow-user: access fault, pc={x:0>8}, inst={x:0>8}, addr={x:0>8}\n", .{ pc, inst_bits, e.addr });
                return .{ .signal = .sigsegv };
            },
        }
    }
}
