pub const XRegIdx = enum(u5) {
    x0 = 0,
    x1 = 1,
    x2 = 2,
    x3 = 3,
    x4 = 4,
    x5 = 5,
    x6 = 6,
    x7 = 7,
    x8 = 8,
    x9 = 9,
    x10 = 10,
    x11 = 11,
    x12 = 12,
    x13 = 13,
    x14 = 14,
    x15 = 15,
    x16 = 16,
    x17 = 17,
    x18 = 18,
    x19 = 19,
    x20 = 20,
    x21 = 21,
    x22 = 22,
    x23 = 23,
    x24 = 24,
    x25 = 25,
    x26 = 26,
    x27 = 27,
    x28 = 28,
    x29 = 29,
    x30 = 30,
    x31 = 31,

    pub const zero: XRegIdx = .x0;
    pub const ra: XRegIdx = .x1;
    pub const sp: XRegIdx = .x2;
};

pub const Inst = struct {
    bits: u32,

    // verilog: inst[31:25]
    pub fn opcode(inst: Inst) Opcode {
        return @fromBackingInt(@truncate(inst.bits >> 25));
    }

    // verilog: inst[24:22]
    pub fn funct3(inst: Inst) u3 {
        return @truncate(inst.bits >> 22);
    }

    // verilog: inst[21:15]
    pub fn funct7(inst: Inst) u7 {
        return @truncate(inst.bits >> 15);
    }

    // verilog: inst[4:0]
    fn _rd(inst: Inst) u5 {
        return @truncate(inst.bits);
    }

    // verilog: inst[9:5]
    pub fn rs1_uimm5(inst: Inst) u5 {
        return @truncate(inst.bits >> 5);
    }

    // verilog: inst[14:10]
    pub fn rs2_uimm5(inst: Inst) u5 {
        return @truncate(inst.bits >> 10);
    }

    // verilog: inst[4:0]
    pub fn rd(inst: Inst) XRegIdx {
        return @fromBackingInt(inst._rd());
    }

    // verilog: inst[9:5]
    pub fn rs1(inst: Inst) XRegIdx {
        return @fromBackingInt(inst.rs1_uimm5());
    }

    // verilog: inst[14:10]
    pub fn rs2(inst: Inst) XRegIdx {
        return @fromBackingInt(inst.rs2_uimm5());
    }

    // verilog: inst[14:10]
    pub fn shamt5(inst: Inst) u5 {
        return @truncate(inst.bits >> 10);
    }

    // verilog: inst[21:10]
    pub fn simm12_i(inst: Inst) i12 {
        const imm: u12 = @truncate(inst.bits >> 10);
        return @bitCast(imm);
    }

    // verilog: inst[21:10]
    pub fn uimm12_i(inst: Inst) u12 {
        return @truncate(inst.bits >> 10);
    }

    // verilog: {inst[21:5], inst[24:22], 12'h0}
    pub fn simm32_u(inst: Inst) i32 {
        const slice_24_22 = (inst.bits >> 22) & 0x07;
        const slice_21_5 = (inst.bits >> 5) & 0x1ffff;
        return @bitCast((slice_21_5 << 15) | (slice_24_22 << 12));
    }

    // verilog: {inst[21:15], inst[4:0], 2'b00}
    pub fn simm14_b(inst: Inst) i14 {
        const slice_21_15 = (inst.bits >> 15) & 0x7f;
        const slice_4_0 = inst.bits & 0x1f;
        const imm14: u14 = @truncate((slice_21_15 << 7) | (slice_4_0 << 2));
        return @bitCast(imm14);
    }

    // verilog: {inst[21:0], 2'b00}
    pub fn simm24_j(inst: Inst) i24 {
        const imm24: u24 = @truncate(inst.bits << 2);
        return @bitCast(imm24);
    }
};

pub const Opcode = enum(u7) {
    opi = 0b1100000,
    opi32 = 0b1100001,
    op = 0b1100010,
    op32 = 0b1100011,
    lui = 0b1100100,
    auipc = 0b1100101,

    cfg = 0b1101000,
    fp = 0b1101001,
    vector = 0b1101010,

    ld = 0b1110000,
    ld_fp = 0b1110001,
    ld_x = 0b1110010,
    mem = 0b1110011,
    st = 0b1110100,
    st_fp = 0b1110101,
    st_x = 0b1110110,
    amo = 0b1110111,

    branch = 0b1111000,
    jal = 0b1111001,
    system = 0b1111011,

    _,
};
