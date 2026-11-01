const std = @import("std");

const XRegIdx = @import("util.zig").XRegIdx;

pub const Core = struct {
    state_pc: u32,
    state_xregs: [32]u32 = @splat(0),

    pub fn pc(self: *const Core) u32 {
        return self.state_pc;
    }

    pub fn set_pc(self: *Core, value: u32) void {
        std.debug.assert(value % 4 == 0);
        self.state_pc = value;
    }

    pub fn xreg(self: *const Core, reg: XRegIdx) u32 {
        return self.state_xregs[@backingInt(reg)];
    }

    pub fn write_reg(self: *Core, reg: XRegIdx, value: u32) void {
        if (reg != .x0) {
            self.state_xregs[@backingInt(reg)] = value;
        }
    }
};
