const std = @import("std");
const arith = @import("arith.zig");
const Inst = @import("util.zig").Inst;
const Core = @import("core.zig").Core;
const Memory = @import("user/memory.zig").Memory;
const Signedness = std.builtin.Signedness;
const assert = std.debug.assert;

pub const NextPc = struct {
    next_pc: u32,

    pub fn init(next_pc: u32) NextPc {
        return .{
            .next_pc = next_pc,
        };
    }

    fn jump(npc: *NextPc, target: u32) void {
        npc.* = .{
            .next_pc = target,
        };
    }
};

pub const StepOutcome = union(enum) {
    ok,
    invalid_instruction,
    breakpoint,
    system_call,
    hypervisor_call,
    misaligned_target,
    access_fault: MemoryFault,
    misaligned_access: MemoryFault,

    pub const MemoryFault = struct { addr: u32 };
};

fn exec_load(core: *Core, memory: *Memory, inst: Inst, comptime T: type, comptime signedness: Signedness) StepOutcome {
    const rd = inst.rd();
    const rs1 = inst.rs1();
    const imm12 = inst.simm12_i();

    const src1 = core.xreg(rs1);
    const imm_sext: u32 = @bitCast(@as(i32, imm12));
    const addr = src1 +% imm_sext;

    if (addr % @sizeOf(T) != 0) {
        return .{ .misaligned_access = .{ .addr = addr } };
    }

    const value = blk: {
        const load_value = memory.loadAligned(T, addr) catch {
            return .{ .access_fault = .{ .addr = addr } };
        };
        break :blk arith.extend_to_u32(T, signedness, load_value);
    };

    core.write_reg(rd, value);
    return .ok;
}

fn exec_store(core: *Core, memory: *Memory, inst: Inst, comptime T: type) StepOutcome {
    const rs1 = inst.rs1();
    const rs3 = inst.rd();
    const imm12 = inst.simm12_i();

    const src1 = core.xreg(rs1);
    const src3 = core.xreg(rs3);
    const imm_sext: u32 = @bitCast(@as(i32, imm12));
    const addr = src1 +% imm_sext;
    const value: T = @truncate(src3);

    if (addr % @sizeOf(T) != 0) {
        return .{ .misaligned_access = .{ .addr = addr } };
    }

    memory.storeAligned(T, addr, value) catch {
        return .{ .access_fault = .{ .addr = addr } };
    };

    return .ok;
}

fn exec_branch(core: *Core, inst: Inst, npc: *NextPc, op: arith.BranchOp) StepOutcome {
    const rs1 = inst.rs1();
    const rs2 = inst.rs2();
    const bimm = inst.simm14_b();

    const src1 = core.xreg(rs1);
    const src2 = core.xreg(rs2);

    const taken = op.compare_u32(src1, src2);

    if (taken) {
        const offset: u32 = @bitCast(@as(i32, bimm));
        const target = core.pc() +% offset;
        assert(target % 4 == 0);
        npc.jump(target);
    }

    return .ok;
}

fn exec_j(core: *Core, inst: Inst, npc: *NextPc) StepOutcome {
    const offset: u32 = @bitCast(@as(i32, inst.simm24_j()));
    const target = core.pc() +% offset;

    npc.jump(target);
    return .ok;
}

fn exec_jal(core: *Core, inst: Inst, npc: *NextPc) StepOutcome {
    const offset: u32 = @bitCast(@as(i32, inst.simm24_j()));
    const target = core.pc() +% offset;

    core.write_reg(.x1, core.pc() +% 4);
    npc.jump(target);
    return .ok;
}

fn exec_jalr(core: *Core, inst: Inst, npc: *NextPc) StepOutcome {
    const rd = inst.rd();
    const rs1 = inst.rs1();
    const imm12 = inst.simm12_i();

    const src1 = core.xreg(rs1);
    const imm_sext: u32 = @bitCast(@as(i32, imm12));
    const target = src1 +% imm_sext;

    if (target % 4 != 0) {
        return .misaligned_target;
    }

    core.write_reg(rd, core.pc() +% 4);
    npc.jump(target);
    return .ok;
}

fn exec_ret(core: *Core, inst: Inst, npc: *NextPc) StepOutcome {
    const rs1 = inst.rs1();

    const target = core.xreg(rs1);
    if (target % 4 != 0) {
        return .misaligned_target;
    }

    npc.jump(target);
    return .ok;
}

fn exec_lui(core: *Core, inst: Inst) StepOutcome {
    const rd = inst.rd();
    const imm32 = inst.simm32_u();

    const value: u32 = @bitCast(imm32);
    core.write_reg(rd, value);
    return .ok;
}

fn exec_auipc(core: *Core, inst: Inst) StepOutcome {
    const rd = inst.rd();
    const imm32 = inst.simm32_u();

    const value = core.pc() +% @as(u32, @bitCast(imm32));
    core.write_reg(rd, value);
    return .ok;
}

fn exec_opimm(core: *Core, inst: Inst, op: arith.AluOp) StepOutcome {
    const rd = inst.rd();
    const rs1 = inst.rs1();
    const imm12 = inst.simm12_i();

    const src1 = core.xreg(rs1);
    const src2: u32 = @bitCast(@as(i32, imm12));

    const value = op.compute_u32(src1, src2);
    core.write_reg(rd, value);
    return .ok;
}

fn exec_shiftimm(core: *Core, inst: Inst, op: arith.ShiftOp) StepOutcome {
    const rd = inst.rd();
    const rs1 = inst.rs1();
    const shamt = inst.shamt5();

    const src1 = core.xreg(rs1);
    const value = op.compute_u32(src1, shamt);

    core.write_reg(rd, value);
    return .ok;
}

fn exec_op(core: *Core, inst: Inst, op: arith.AluOp) StepOutcome {
    const rd = inst.rd();
    const rs1 = inst.rs1();
    const rs2 = inst.rs2();

    const src1 = core.xreg(rs1);
    const src2 = core.xreg(rs2);

    const value = op.compute_u32(src1, src2);
    core.write_reg(rd, value);
    return .ok;
}

fn exec_shift(core: *Core, inst: Inst, op: arith.ShiftOp) StepOutcome {
    const rd = inst.rd();
    const rs1 = inst.rs1();
    const rs2 = inst.rs2();

    const src1 = core.xreg(rs1);
    const src2 = core.xreg(rs2);

    const shamt5: u5 = @truncate(src2);
    const value = op.compute_u32(src1, shamt5);
    core.write_reg(rd, value);
    return .ok;
}

pub fn execute(core: *Core, memory: *Memory, inst: Inst, npc: *NextPc) StepOutcome {
    const opcode = inst.opcode();
    const funct3 = inst.funct3();
    const funct7 = inst.funct7();

    return switch (opcode) {
        .ld => switch (funct3) {
            0b000 => exec_load(core, memory, inst, u8, .unsigned),
            0b001 => exec_load(core, memory, inst, u16, .unsigned),
            0b010 => exec_load(core, memory, inst, u32, .unsigned),
            0b100 => exec_load(core, memory, inst, u8, .signed),
            0b101 => exec_load(core, memory, inst, u16, .signed),
            else => .invalid_instruction,
        },
        .auipc => exec_auipc(core, inst),
        .st => switch (funct3) {
            0b000 => exec_store(core, memory, inst, u8),
            0b001 => exec_store(core, memory, inst, u16),
            0b010 => exec_store(core, memory, inst, u32),
            else => .invalid_instruction,
        },
        .opi => switch (funct3) {
            0b000 => exec_opimm(core, inst, .add),
            0b001 => exec_opimm(core, inst, .@"and"),
            0b010 => exec_opimm(core, inst, .@"or"),
            0b011 => exec_opimm(core, inst, .xor),
            0b100 => exec_opimm(core, inst, .slt_u),
            0b101 => exec_opimm(core, inst, .slt_s),
            0b110 => .invalid_instruction,
            0b111 => switch (funct7) {
                0b0000000 => exec_shiftimm(core, inst, .sll),
                0b0000100 => exec_shiftimm(core, inst, .srl),
                0b0000110 => exec_shiftimm(core, inst, .sra),
                else => .invalid_instruction,
            },
        },
        .lui => exec_lui(core, inst),
        .branch => switch (funct3) {
            0b000 => exec_branch(core, inst, npc, .eq),
            0b001 => exec_branch(core, inst, npc, .neq),
            0b100 => exec_branch(core, inst, npc, .lt_u),
            0b101 => exec_branch(core, inst, npc, .ge_u),
            0b110 => exec_branch(core, inst, npc, .lt_s),
            0b111 => exec_branch(core, inst, npc, .ge_s),
            else => .invalid_instruction,
        },
        .jal => switch (funct3) {
            0b000 => exec_j(core, inst, npc),
            0b001 => exec_jal(core, inst, npc),
            0b100 => exec_jalr(core, inst, npc),
            0b111 => if (inst.rd() != .x0 or inst.uimm12_i() != 0) .invalid_instruction else exec_ret(core, inst, npc),
            else => .invalid_instruction,
        },
        .op => switch (funct3) {
            0b000 => switch (funct7) {
                0b0000000 => exec_op(core, inst, .add),
                0b0000001 => exec_op(core, inst, .sub),
                0b0000010 => exec_op(core, inst, .@"and"),
                0b0000100 => exec_op(core, inst, .@"or"),
                0b0000110 => exec_op(core, inst, .xor),
                0b0001000 => exec_op(core, inst, .slt_u),
                0b0001010 => exec_op(core, inst, .slt_s),
                else => .invalid_instruction,
            },
            0b001 => switch (funct7) {
                0b0000000 => exec_op(core, inst, .mul),
                0b0000010 => exec_op(core, inst, .mulh_uu),
                0b0000100 => exec_op(core, inst, .mulh_su),
                0b0000110 => exec_op(core, inst, .mulh_ss),
                0b0001000 => exec_op(core, inst, .div_u),
                0b0001010 => exec_op(core, inst, .rem_u),
                0b0001100 => exec_op(core, inst, .div_s),
                0b0001110 => exec_op(core, inst, .rem_s),
                else => .invalid_instruction,
            },
            0b111 => switch (funct7) {
                0b0000000 => exec_shift(core, inst, .sll),
                0b0000100 => exec_shift(core, inst, .srl),
                0b0000110 => exec_shift(core, inst, .sra),
                else => .invalid_instruction,
            },
            else => .invalid_instruction,
        },
        .system => if (funct3 != 0 or inst.rd() != .x0 or inst.rs1() != .x0) .invalid_instruction else switch (inst.uimm12_i()) {
            1 => .breakpoint,
            2 => .system_call,
            3 => .hypervisor_call,
            else => .invalid_instruction,
        },
        else => .invalid_instruction,
    };
}
