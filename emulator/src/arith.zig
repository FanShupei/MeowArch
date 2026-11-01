const std = @import("std");

fn as_i32(x: u32) i32 {
    return @bitCast(x);
}

fn sext32(x: u32) u64 {
    return @bitCast(@as(i64, @as(i32, @bitCast(x))));
}

pub fn extend_to_u32(comptime T: type, comptime signedness: std.builtin.Signedness, x: T) u32 {
    switch (signedness) {
        .unsigned => return x,
        .signed => {
            const y: i32 = switch (T) {
                u8 => @as(i8, @bitCast(x)),
                u16 => @as(i16, @bitCast(x)),
                u32 => @as(i32, @bitCast(x)),
                else => @compileError("unknown type T=" ++ @typeName(T)),
            };
            return @bitCast(y);
        },
    }
}

pub const BranchOp = enum {
    eq,
    neq,
    lt_u,
    ge_u,
    lt_s,
    ge_s,

    pub fn compare_u32(op: BranchOp, src1: u32, src2: u32) bool {
        return switch (op) {
            .eq => src1 == src2,
            .neq => src1 != src2,
            .lt_u => src1 < src2,
            .ge_u => src1 >= src2,
            .lt_s => as_i32(src1) < as_i32(src2),
            .ge_s => as_i32(src1) >= as_i32(src2),
        };
    }
};

pub const AluOp = enum {
    add,
    sub,
    @"and",
    @"or",
    xor,
    slt_u,
    slt_s,
    mul,
    mulh_uu,
    mulh_su,
    mulh_ss,
    div_u,
    rem_u,
    div_s,
    rem_s,

    pub fn compute_u32(op: AluOp, src1: u32, src2: u32) u32 {
        return switch (op) {
            .add => src1 +% src2,
            .sub => src1 -% src2,
            .@"and" => src1 & src2,
            .@"or" => src1 | src2,
            .xor => src1 ^ src2,
            .slt_u => if (src1 < src2) @as(u32, 1) else @as(u32, 0),
            .slt_s => if (as_i32(src1) < as_i32(src2)) @as(u32, 1) else @as(u32, 0),
            .mul => src1 *% src2,
            .mulh_uu => @truncate((@as(u64, src1) *% @as(u64, src2)) >> 32),
            .mulh_su => @truncate((sext32(src1) *% @as(u64, src2)) >> 32),
            .mulh_ss => @truncate((sext32(src1) *% sext32(src2)) >> 32),
            .div_u => if (src2 == 0) @as(u32, 0xFFFF_FFFF) else src1 / src2,
            .rem_u => if (src2 == 0) src1 else src1 % src2,
            .div_s => blk: {
                if (src2 == 0) break :blk @as(u32, 0xFFFF_FFFF);
                if (src1 == 0x8000_0000 and ~src2 == 0) break :blk src1;
                const s1 = @as(i32, @bitCast(src1));
                const s2 = @as(i32, @bitCast(src2));
                break :blk @as(u32, @bitCast(@divTrunc(s1, s2)));
            },
            .rem_s => blk: {
                if (src2 == 0) break :blk src1;
                if (src1 == 0x8000_0000 and ~src2 == 0) break :blk 0;
                const s1 = @as(i32, @bitCast(src1));
                const s2 = @as(i32, @bitCast(src2));
                break :blk @as(u32, @bitCast(@rem(s1, s2)));
            },
        };
    }
};

pub const ShiftOp = enum {
    sll,
    srl,
    sra,

    pub fn compute_u32(op: ShiftOp, src1: u32, shamt: u5) u32 {
        return switch (op) {
            .sll => src1 << shamt,
            .srl => src1 >> shamt,
            .sra => @as(u32, @bitCast(as_i32(src1) >> shamt)),
        };
    }
};
