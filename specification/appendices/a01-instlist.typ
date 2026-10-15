#import "../theme.typ": font-mono
#import "inst-table.typ": empty, imm, inst-row, inst-table, lit, reg, title

#let rs1 = reg[rs1]
#let rs2 = reg[rs2]
#let rs3 = reg[rs3]
#let rd = reg[*rd*]
#let rs3-rd = reg[rs3 / *rd*]

#let imm-u = imm(20, "imm[14:12] | imm[31:15]")
#let imm-j = imm(22, "imm24[23:2]")
#let imm-i = imm(12, "imm12")
#let imm-b-1 = imm(7, "imm14[13:7]")
#let imm-b-2 = imm(5, "imm14[6:2]")
#let shamt5 = imm(5, "shamt5")

#let major(body5) = lit("11" + body5.slice(0, 2) + " " + body5.slice(2))

#let op-opi = major("00000")
#let op-opi32 = major("00001")
#let op-op = major("00010")
#let op-op32 = major("00011")
#let op-lui = major("00100")
#let op-auipc = major("00101")

#let op-cfg = major("01000")
#let op-fp = major("01001")
#let op-vector = major("01010")

#let op-ld = major("10000")
#let op-ldfp = major("10001")
#let op-ldx = major("10010")
#let op-mem = major("10011")
#let op-st = major("10100")
#let op-stfp = major("10101")
#let op-stx = major("10110")
#let op-amo = major("10111")

#let op-branch = major("11000")
#let op-jal = major("11001")
#let op-system = major("11011")

= Instruction Listing

#figure(
  {
    set text(font: font-mono, size: 8pt)
    let cell2(body) = table.cell(rowspan: 2, body)
    // @typstyle off
    table(
      columns: (1.2fr,) + (1fr,) * 8,
      rows: 6,
      align: center + horizon,
      stroke: 0.5pt + gray,
      inset: 4pt,

      table.header(
        [inst[27:25]],
        cell2[000], cell2[001], cell2[010], cell2[011],
        cell2[100], cell2[101], cell2[110], cell2[111],
        [inst[29:28]],
      ),

      [00], [OPI],        [/*OPI-32*/], [OP],         [/*OP-32*/],
            [LUI],        [AUIPC],      [],           [],
      [01], [/*CFG*/],    [/*FP*/],     [/*VECTOR*/], [],
            [],           [],           [],           [],
      [10], [LD],         [/*LD-FP*/],  [/*LD-X*/],   [/*MEM*/],
            [ST],         [/*ST-FP*/],  [/*ST-X*/],   [/*AMO*/],
      [11], [BRANCH],     [JAL],        [],           [SYSTEM],
            [],           [],           [],           [(RSVD)],
    )
  },
  caption: [Meow Opcode Map (inst[31:30] = 11)],
)

#pagebreak(weak: true)
// @typstyle off
#inst-table(
  title("Control Transfer Instructions"),
  inst-row("j",    op-jal, lit("000"), imm-j),
  inst-row("jal",  op-jal, lit("001"), imm-j),
  inst-row("jalr", op-jal, lit("100"), imm-i, rs1, rd),
  inst-row("ret",  op-jal, lit("111"), lit("0000 0000 0000"), rs1, lit("00000")),
  empty,
  inst-row("beq",  op-branch, lit("000"), imm-b-1, rs2, rs1, imm-b-2),
  inst-row("bne",  op-branch, lit("001"), imm-b-1, rs2, rs1, imm-b-2),
  inst-row("bltu", op-branch, lit("100"), imm-b-1, rs2, rs1, imm-b-2),
  inst-row("bgeu", op-branch, lit("101"), imm-b-1, rs2, rs1, imm-b-2),
  inst-row("blt",  op-branch, lit("110"), imm-b-1, rs2, rs1, imm-b-2),
  inst-row("bge",  op-branch, lit("111"), imm-b-1, rs2, rs1, imm-b-2),

  title("Integer Load/Store Instructions"),
  inst-row("ld.u8",  op-ld, lit("000"), imm-i, rs1, rd),
  inst-row("ld.u16", op-ld, lit("001"), imm-i, rs1, rd),
  inst-row("ld.u32", op-ld, lit("010"), imm-i, rs1, rd),
  // inst-row("ld.u64", op-ld, lit("011"), imm-i, rs1, rd),
  inst-row("ld.i8",  op-ld, lit("100"), imm-i, rs1, rd),
  inst-row("ld.i16", op-ld, lit("101"), imm-i, rs1, rd),
  // inst-row("ld.i32", op-ld, lit("110"), imm-i, rs1, rd),
  empty,
  inst-row("st.u8",  op-st, lit("000"), imm-i, rs1, rs3),
  inst-row("st.u16", op-st, lit("001"), imm-i, rs1, rs3),
  inst-row("st.u32", op-st, lit("010"), imm-i, rs1, rs3),
  // inst-row("st.u64", op-st, lit("011"), imm-i, rs1, rs3),

  title("System Instructions"),
  inst-row("unimp", op-system, lit("000"), lit("0000 0000 0000"), lit("00000"), lit("00000")),
  inst-row("break", op-system, lit("000"), lit("0000 0000 0001"), lit("00000"), lit("00000")),
  inst-row("ecall.s", op-system, lit("000"), lit("0000 0000 0010"), lit("00000"), lit("00000")),
  inst-row("ecall.h", op-system, lit("000"), lit("0000 0000 0011"), lit("00000"), lit("00000")),
  inst-row("csrr", op-system, lit("100"), imm(12, "csr"), lit("00000"), rd),
  inst-row("csrrw", op-system, lit("101"), imm(12, "csr"), rs1, rd),
)

#pagebreak(weak: true)
// @typstyle off
#inst-table(
  title("Integer Arithmetic Instructions"),
  inst-row("lui", op-lui, imm-u, rd),
  inst-row("auipc", op-auipc, imm-u, rd),
  empty,
  inst-row("addi",  op-opi, lit("000"), imm-i, rs1, rd),
  inst-row("andi",  op-opi, lit("001"), imm-i, rs1, rd),
  inst-row("ori",   op-opi, lit("010"), imm-i, rs1, rd),
  inst-row("xori",  op-opi, lit("011"), imm-i, rs1, rd),
  inst-row("sltiu", op-opi, lit("100"), imm-i, rs1, rd),
  inst-row("slti",  op-opi, lit("101"), imm-i, rs1, rd),
  inst-row("slli",  op-opi, lit("111"), lit("000000 0"), shamt5, rs1, rd),
  inst-row("srli",  op-opi, lit("111"), lit("000010 0"), shamt5, rs1, rd),
  inst-row("srai",  op-opi, lit("111"), lit("000011 0"), shamt5, rs1, rd),
  empty,
  inst-row("add",    op-op, lit("000"), lit("000000 0"), rs2, rs1, rd),
  inst-row("sub",    op-op, lit("000"), lit("000000 1"), rs2, rs1, rd),
  inst-row("and",    op-op, lit("000"), lit("000001 0"), rs2, rs1, rd),
  inst-row("or",     op-op, lit("000"), lit("000010 0"), rs2, rs1, rd),
  inst-row("xor",    op-op, lit("000"), lit("000011 0"), rs2, rs1, rd),
  inst-row("sltu",   op-op, lit("000"), lit("000100 0"), rs2, rs1, rd),
  inst-row("slt",    op-op, lit("000"), lit("000101 0"), rs2, rs1, rd),
  inst-row("mul",    op-op, lit("001"), lit("000000 0"), rs2, rs1, rd),
  inst-row("mulhu",  op-op, lit("001"), lit("000001 0"), rs2, rs1, rd),
  inst-row("mulhsu", op-op, lit("001"), lit("000010 0"), rs2, rs1, rd),
  inst-row("mulh",   op-op, lit("001"), lit("000011 0"), rs2, rs1, rd),
  inst-row("divu",   op-op, lit("001"), lit("000100 0"), rs2, rs1, rd),
  inst-row("remu",   op-op, lit("001"), lit("000101 0"), rs2, rs1, rd),
  inst-row("div",    op-op, lit("001"), lit("000110 0"), rs2, rs1, rd),
  inst-row("rem",    op-op, lit("001"), lit("000111 0"), rs2, rs1, rd),
  inst-row("sll",    op-op, lit("111"), lit("000000 0"), rs2, rs1, rd),
  inst-row("srl",    op-op, lit("111"), lit("000010 0"), rs2, rs1, rd),
  inst-row("sra",    op-op, lit("111"), lit("000011 0"), rs2, rs1, rd),
)
