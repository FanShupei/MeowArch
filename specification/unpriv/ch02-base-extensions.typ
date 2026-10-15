#import "../inst-encoding.typ": inst-encoding-grid
#import "../util.typ": note

= Base Extensions

This chapter describes the Meow base instruction set architectures.

The base extensions define the following parameters:
- `XLEN` : the width of general-purpose registers, in bits.
  - `XLEN = 32`: Meow32 architecture.
  - `XLEN = 64`: Meow64 architecture.
- `ILEN` : the width of the longest supported instruction, in bits.
  - `ILEN = 32`: The Meow architecture supports only 32-bit instructions.
- `IALIGN` : the smallest instruction-alignment requirement, in bits.
  - `IALIGN = 32`: Instructions must start at addresses that are multiples of 4 bytes.

#note[
  This version defines only the Meow32 variant.
]

== Architectural State

The Meow architecture has 32 `XLEN`-bit general-purpose registers (GPRs) `x0`-`x31`.
Register `x0` is hardwired to zero. The remaining GPRs are equivalent general-purpose registers.
"Hardwired to zero" means that reads from `x0` return zero and writes to `x0` are ignored.

The `XLEN`-bit program counter `pc` holds the address of the current instruction. This address is always aligned to an `IALIGN`-bit boundary.

Unless otherwise specified, successful execution of an instruction advances `pc` to the address immediately following that instruction.

== Memory Organization

Memory is byte-addressable, with an `XLEN`-bit address space of $2^"XLEN"$ bytes.
The address space is circular: all address calculations are performed modulo $2^"XLEN"$, including instruction sequencing, effective addresses, control-transfer targets, and return addresses.
Multibyte accesses that cross the address-space boundary wrap around to address zero.
Not all addresses need to be mapped to memory or devices.

Multibyte data values and instructions use *little-endian* byte order: the least-significant byte is stored at the starting address.

#note[
  There are no plans to define a big-endian variant of the Meow architecture.
]

== Instruction Encodings

#figure(
  {
    let cell = grid.cell
    let reg(body) = cell(colspan: 5, body)
    let opcode = cell(colspan: 7)[opcode]

    // @typstyle off
    inst-encoding-grid(
      opcode, cell(colspan: 3)[funct3], cell(colspan: 7)[funct7], reg[rs2], reg[rs1], reg[rs3 / rd], [R-type],

      opcode, cell(colspan: 3)[funct3], cell(colspan: 12)[imm12], reg[rs1], reg[rs3 / rd], [I-type],

      opcode, cell(colspan: 20)[imm[14:12] | imm[31:15]], reg[rd], [U-type],

      opcode, cell(colspan: 3)[funct3], cell(colspan: 7)[imm14[13:7]], reg[rs2], reg[rs1], cell(colspan: 5)[imm14[6:2]], [B-type],

      opcode, cell(colspan: 3)[funct3], cell(colspan: 22)[imm24[23:2]], [J-type],
    )
  },
  caption: [Base Instruction Encodings],
)

== Load/Store Instructions

Load and store instructions use I-type encoding.
The opcodes are `LD` and `ST`, respectively.
The immediate field encodes a signed 12-bit offset in bytes, ranging from $-2048$ to $2047$.

The _effective address_ is computed by adding the offset to the value in the base register `rs1`. #footnote[The offset is first sign-extended to `XLEN` bits. The addition is performed modulo $2^"XLEN"$.]

Load instructions read a value of the specified width from the effective address and write it to the destination register `rd`.
Values narrower than `XLEN` bits are sign-extended or zero-extended to `XLEN` bits accordingly.
See @tbl:load-instructions.

Store instructions write the least-significant 8, 16, 32, or 64 bits of `rs3`, according to the access size, to memory at the effective address.
See @tbl:store-instructions.

Loads to `x0` still perform the memory access but discard the result.

#figure(
  // @typstyle off
  table(
    columns: (auto, auto, auto, auto, 1fr),
    align: (x, y) => if y == 0 { auto } else {
      (left, auto, auto, auto, left).at(x)
    },
    table.header([Name], [funct3], [x32], [x64], [Description]),
    [`ld.u8`],   [000], [x], [x], [load a byte and zero-extend it],
    [`ld.i8`],   [100], [x], [x], [load a byte and sign-extend it],
    [`ld.u16`],  [001], [x], [x], [load a halfword and zero-extend it],
    [`ld.i16`],  [101], [x], [x], [load a halfword and sign-extend it],
    [`ld.u32`],  [010], [x], [x], [load a word and zero-extend it],
    [`ld.i32`],  [110], [ ], [x], [load a word and sign-extend it],
    [`ld.u64`],  [011], [ ], [x], [load a doubleword],
  ),
  caption: [Load Instructions (I-type, opcode=`LD`)],
) <tbl:load-instructions>

#figure(
  // @typstyle off
  table(
    columns: (auto, auto, auto, auto, 1fr),
    align: (x, y) => if y == 0 { auto } else {
      (left, auto, auto, auto, left).at(x)
    },
    table.header([Name], [funct3], [x32], [x64], [Description]),
    [`st.u8`],  [000], [x], [x], [store a byte],
    [`st.u16`], [001], [x], [x], [store a halfword],
    [`st.u32`], [010], [x], [x], [store a word],
    [`st.u64`], [011], [ ], [x], [store a doubleword],
  ),
  caption: [Store Instructions (I-type, opcode=`ST`)],
) <tbl:store-instructions>

When the effective address is a multiple of the access size in bytes, the memory access is called _aligned_; otherwise it is called _unaligned_.

The environment may support all, some, or no unaligned accesses.
The precise rules are defined in platform specifications.

== Control Transfer Instructions

Meow defines three kinds of control transfer instructions: branch instructions, direct jump (and link) instructions, and indirect jump (and link) instructions.

=== Branch Instructions

Branch instructions use B-type encoding with opcode `BRANCH`.
The encoded immediate supplies bits `[13:2]` of a signed 14-bit offset in bytes, where bits `[1:0]` are always zero.
The offset ranges from $-8192$ to $+8188$ bytes and is a multiple of 4 bytes.
The _target address_ is computed by adding this offset to the address of the branch instruction (the current `pc`).
#footnote[The offset is sign-extended to `XLEN` bits. The addition is performed modulo $2^"XLEN"$.]

Branch instructions evaluate the specified condition using the values in registers `rs1` and `rs2`.
If the condition holds, the branch is _taken_ and `pc` is set to the target address.
Otherwise, the branch is _not taken_ and execution falls through (`pc` advances by 4 bytes to the next instruction).

#figure(
  // @typstyle off
  table(
    columns: (auto, auto, 1fr),
    align: (x, y) => if y == 0 { auto } else {
      (left, auto, left).at(x)
    },
    table.header([Name], [funct3], [Description]),
    [`beq`], [`000`], [branch if `rs1 == rs2`],
    [`bne`], [`001`], [branch if `rs1 != rs2`],
    [`bltu`], [`100`], [branch if `UInt(rs1) < UInt(rs2)`],
    [`bgeu`], [`101`], [branch if `UInt(rs1) >= UInt(rs2)`],
    [`blt`], [`110`], [branch if `SInt(rs1) < SInt(rs2)`],
    [`bge`], [`111`], [branch if `SInt(rs1) >= SInt(rs2)`],
  ),
  caption: [Branch Instructions (B-type, opcode=`BRANCH`)],
) <tbl:branch-instructions>


#note[
  The target address is guaranteed to be aligned,
  because both the current `pc` and the offset are multiples of 4 bytes.
]

=== Direct Jump (and Link) Instructions

The `j` and `jal` instructions use J-type encoding with opcode `JAL`.
The encoded immediate supplies bits `[23:2]` of a signed 24-bit offset in bytes; bits `[1:0]` are zero.
The target address is computed by sign-extending the offset to `XLEN` bits and adding it to the address of the jump instruction (the current `pc`).

The `j` instruction sets `pc` to the target address without modifying any GPRs.
The `jal` instruction writes the address of the following instruction `(pc + 4)` to `x1`, then sets `pc` to the target address.

#note[
  The `j` instruction is designed for unconditional jumps and tail calls.
  The `jal` instruction is designed for function calls.

  The destination register `x1` for `jal` is implicit and not encoded directly.
]

#figure(
  // @typstyle off
  table(
    columns: (auto, auto, 1fr),
    align: (x, y) => if y == 0 { auto } else { (left, auto, left).at(x) },
    table.header([Name], [funct3], [Description]),
    [`j`],   [`000`], [jump without writing a return address],
    [`jal`], [`001`], [jump and write `pc + 4` to `x1`],
  ),
  caption: [Direct Jump Instructions (J-type, opcode=`JAL`)],
) <tbl:direct-jump-instructions>

#note[
  Like branch targets, direct jump targets are guaranteed to be aligned.
]

=== Indirect Jump (and Link) Instructions

The `jalr` and `ret` instructions use I-type encoding with opcode `JAL`.
The immediate for `jalr` is an offset in bytes, ranging from $-2048$ to $2047$.
Both perform an unconditional jump to a register-based target address.

The `jalr` instruction computes the target address by adding its signed 12-bit immediate to the value in `rs1`, then writes the address of the following instruction (`pc + 4`) to `rd` and sets `pc` to the target address.
#footnote[
  The target address is computed using the value in `rs1` before the write to `rd`.
  The order matters when `rd` and `rs1` are the same.
]

The `ret` instruction sets `pc` to the value in `rs1` without modifying any GPRs.
Its immediate field and `rd` field must both be zero.

#figure(
  // @typstyle off
  table(
    columns: (auto, auto, 1fr),
    align: (x, y) => if y == 0 { auto } else { (left, auto, left).at(x) },
    table.header([Name], [funct3], [Description]),
    [`jalr`], [`100`], [jump to `rs1 + offset` and write `pc + 4` to `rd`],
    [`ret`],  [`111`], [jump to `rs1` without writing a return address],
  ),
  caption: [Indirect Jump Instructions (I-type, opcode=`JAL`)],
) <tbl:indirect-jump-instructions>

If the target address of `jalr` or `ret` is not aligned according to `IALIGN`, the instruction raises a target-misaligned exception.
The exception is attributed to the jump instruction; the jump is not performed and no return address is written.

#note[
  The `jalr` instruction is designed for indirect function calls.
  The `auipc`-`jalr` pair can implement long-range jumps or function calls.

  `ret x1` is equivalent to `jalr x0, x1, 0` in architectural behavior.
  Function returns should use `ret x1` so implementations can recognize them as returns.
]

== Arithmetic Instructions

Arithmetic instructions never generate exceptions.

Arithmetic instructions that write to `x0` are hint instructions.

=== Upper-Immediate Instructions

The `lui` and `auipc` instructions use U-type encoding with opcodes `LUI` and `AUIPC`, respectively.
The immediate supplies bits `[31:12]` of a 32-bit value, with bits `[11:0]` set to zero.
As shown in the encoding diagram, instruction bits `[24:22]` supply immediate bits `[14:12]`, and instruction bits `[21:5]` supply immediate bits `[31:15]`.

The `lui` instruction writes this value to `rd`.
The `auipc` instruction adds this value to the address of the current instruction and writes the low `XLEN` bits of the sum to `rd`.

#note[
  `lui` can be combined with `addi` to construct a 32-bit constant.
  `auipc` can be combined with an instruction using a signed 12-bit offset to form a PC-relative address.
  The upper immediate must account for the sign extension of the lower immediate.
]

=== Register-Immediate Instructions

The following instructions use I-type encoding with opcode `OPI`.
The signed 12-bit immediate is sign-extended to `XLEN` bits before the operation.

#figure(
  // @typstyle off
  table(
    columns: (auto, auto, 1fr),
    align: (x, y) => if y == 0 { auto } else {
      (left, auto, left).at(x)
    },
    table.header([Name], [funct3], [Result written to `rd`]),
    [`addi`],  [`000`], [wrapping sum of `rs1` and the immediate],
    [`andi`],  [`001`], [bitwise AND of `rs1` and the immediate],
    [`ori`],   [`010`], [bitwise OR of `rs1` and the immediate],
    [`xori`],  [`011`], [bitwise XOR of `rs1` and the immediate],
    [`sltiu`], [`100`], [1 if `rs1` is less than the immediate when both operands are interpreted as unsigned integers; otherwise 0],
    [`slti`],  [`101`], [1 if `rs1` is less than the immediate when both operands are interpreted as signed integers; otherwise 0],
  ),
  caption: [Register-Immediate Arithmetic Instructions (I-type, opcode=`OPI`)],
) <tbl:immediate-arithmetic>

#note[
  This sign-extension rule applies to all register-immediate instructions in @tbl:immediate-arithmetic, including logical instructions and `sltiu`.

  For `sltiu`, the immediate is first sign-extended then interpreted as an unsigned value.
]

=== Register-Register Instructions

The following instructions use R-type encoding with opcode `OP` and `funct3 = 000`.
They operate on the values in `rs1` and `rs2`.

#figure(
  // @typstyle off
  table(
    columns: (auto, auto, 1fr),
    align: (x, y) => if y == 0 { auto } else { (left, auto, left).at(x) },
    table.header([Name], [funct7], [Result written to `rd`]),
    [`add`],  [`0000000`], [wrapping sum of `rs1` and `rs2`],
    [`sub`],  [`0000001`], [wrapping difference of `rs1` and `rs2`],
    [`and`],  [`0000010`], [bitwise AND of `rs1` and `rs2`],
    [`or`],   [`0000100`], [bitwise OR of `rs1` and `rs2`],
    [`xor`],  [`0000110`], [bitwise XOR of `rs1` and `rs2`],
    [`sltu`], [`0001000`], [1 if `rs1` is less than `rs2` when both operands are interpreted as unsigned integers; otherwise 0],
    [`slt`],  [`0001010`], [1 if `rs1` is less than `rs2` when both operands are interpreted as signed integers; otherwise 0],
  ),
  caption: [Register-Register Arithmetic Instructions (R-type, opcode=`OP`, funct3=`000`)],
) <tbl:register-arithmetic>

Like `sltiu` and `slti`, `sltu` and `slt` write an `XLEN`-bit value of 0 or 1.

=== Shift Instructions

Immediate shifts use I-type encoding with opcode `OPI` and `funct3 = 111`.
Bits `[14:10]` encode an unsigned 5-bit shift amount, `shamt5`, ranging from 0 to 31.
Bits `[21:15]` select the operation as shown in @tbl:shift-instructions; the shift amount is not sign-extended.

Register shifts use R-type encoding with opcode `OP` and `funct3 = 111`.
The shift amount is the low 5 bits of the value in `rs2`; the other bits of `rs2` are ignored.
Both forms shift the value in `rs1` and write the result to `rd`.

#figure(
  // @typstyle off
  table(
    columns: (auto, auto, auto, 1fr),
    align: (x, y) => if y == 0 { auto } else { (left, left, auto, left).at(x) },
    table.header([Immediate], [Register], [funct7], [Operation]),
    [`slli`], [`sll`], [`0000000`], [logical left shift; fill vacated low bits with zeros],
    [`srli`], [`srl`], [`0000100`], [logical right shift; fill vacated high bits with zeros],
    [`srai`], [`sra`], [`0000110`], [arithmetic right shift; fill vacated high bits with the original sign bit],
  ),
  caption: [Shift Instructions (I-type: opcode=`OPI`; R-type: opcode=`OP`; funct3=`111`)],
) <tbl:shift-instructions>

Bits shifted out of the `XLEN`-bit result are discarded.
A shift amount of zero leaves the value unchanged.

=== Multiplication Instructions

Multiplication instructions use R-type encoding with opcode `OP` and `funct3 = 001`.
They form a `(2*XLEN)`-bit product from the `XLEN`-bit values in `rs1` and `rs2`, then write the selected half to `rd`.

#figure(
  // @typstyle off
  table(
    columns: (auto, auto, 1fr),
    align: (x, y) => if y == 0 { auto } else { (left, auto, left).at(x) },
    table.header([Name], [funct7], [Result written to `rd`]),
    [`mul`],    [`0000000`], [low `XLEN` bits of the product],
    [`mulhu`],  [`0000010`], [high `XLEN` bits of the unsigned-by-unsigned product],
    [`mulhsu`], [`0000100`], [high `XLEN` bits of the signed `rs1` by unsigned `rs2` product],
    [`mulh`],   [`0000110`], [high `XLEN` bits of the signed-by-signed product],
  ),
  caption: [Multiplication Instructions (R-type, opcode=`OP`, funct3=`001`)],
) <tbl:multiplication-instructions>

#note[
  The low `XLEN` bits of the product are independent of operand signedness, so `mul` handles all three cases.
]

=== Division and Remainder Instructions

Division and remainder instructions use R-type encoding with opcode `OP` and `funct3 = 001`.
The value in `rs1` is the dividend, and the value in `rs2` is the divisor.

#figure(
  // @typstyle off
  table(
    columns: (auto, auto, 1fr),
    align: (x, y) => if y == 0 { auto } else { (left, auto, left).at(x) },
    table.header([Name], [funct7], [Result written to `rd`]),
    [`divu`], [`0001000`], [unsigned quotient],
    [`remu`], [`0001010`], [unsigned remainder],
    [`div`],  [`0001100`], [signed quotient, rounded toward zero],
    [`rem`],  [`0001110`], [signed remainder, with the sign of the dividend unless zero],
  ),
  caption: [Division and Remainder Instructions (R-type, opcode=`OP`, funct3=`001`)],
) <tbl:division-instructions>

Division by zero and signed overflow do not raise exceptions.
The results for these cases are specified in @tbl:division-value.

#figure(
  // @typstyle off
  table(
    columns: (auto, 1fr, 1fr, 1fr, 1fr),
    align: (x, y) => if y == 0 { auto } else {
      (left, auto, auto, auto, auto).at(x)
    },
    table.header([Name], [`rs1`], [`rs2`], [Quotient], [Remainder]),
    [`divu`/`remu`], [`x`], [`0`], [`0xFFFFFFFF`], [`x`],
    [`div`/`rem`], [`x`], [`0`], [`0xFFFFFFFF`], [`x`],
    [`div`/`rem`], [`0x80000000`], [`0xFFFFFFFF`], [`0x80000000`], [`0`],
  ),
  caption: [Division and Remainder Results for Exceptional Cases (Meow32)],
) <tbl:division-value>

== Breakpoint and Environment-Call Instructions

The following instructions use I-type encoding with opcode `SYSTEM`.
They use `funct3 = 000`, with both `rs1` and `rd` set to zero.

The `unimp` instruction is the canonical unimplemented instruction.
The `break` instruction is the software breakpoint instruction.
The `ecall.s` and `ecall.h` instructions are designed for supervisor and hypervisor calls, respectively.
Their precise semantics are defined by platform specifications.

#figure(
  // @typstyle off
  table(
    columns: (auto, auto, auto, 1fr),
    align: (x, y) => if y == 0 { auto } else { (left, auto, left, left).at(x) },
    table.header([Name], [inst[21:10]], [Extension], [Semantics]),
    [`unimp`],   [`000000000000`], [Base],                [illegal instruction],
    [`break`],   [`000000000001`], [Software breakpoint], [platform-defined],
    [`ecall.s`], [`000000000010`], [Environment call],    [platform-defined],
    [`ecall.h`], [`000000000011`], [Environment call],    [platform-defined],
  ),
  caption: [System Instructions (opcode=`SYSTEM`, funct3=`000`)],
) <tbl:system-exceptions>

== CSR Instructions

CSR instructions use I-type encoding with opcode `SYSTEM`.
The immediate field encodes an unsigned 12-bit control and status register (CSR) address.
CSR values are `XLEN` bits wide; individual CSR definitions specify permissions and side effects.

#figure(
  // @typstyle off
  table(
    columns: (auto, auto, 1fr),
    align: (x, y) => if y == 0 { auto } else { (left, auto, left).at(x) },
    table.header([Name], [funct3], [Operation]),
    [`csrr`],  [`100`], [read a CSR into `rd`; `rs1` must be zero],
    [`csrrw`], [`101`], [atomically exchange the CSR value with the value in `rs1`, returning the old CSR value in `rd`],
  ),
  caption: [CSR-Access Instructions (I-type, opcode=`SYSTEM`)],
) <tbl:csr-instructions>

== Hint Instructions

Hint instructions may provide implementation-specific guidance but have no architectural effect beyond normal instruction sequencing.
Implementations may ignore the guidance and execute them as no-ops.

=== Canonical NOP Instruction

The `nop` hint is encoded as `addi x0, x0, 0`.

It provides no additional guidance and can be used for padding or alignment.
