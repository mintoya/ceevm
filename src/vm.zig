const std = @import("std");
const Math = @import("math.zig");
pub const Reg = u32;
pub const Mach = @This();

pub const Extension = *const fn (args: []const []u8) anyerror!void;
const Slot = extern struct { offset: usize, len: usize };
const Block = struct {
    offset: usize,
    len: usize,
    registers: usize,
    register_count: usize,
    size: usize,
};
const Frame = struct {
    block: ?u32 = null,
    counter: usize = 0,
    base: usize,
    callargs: []align(1) const Slot,
};

alloc: std.mem.Allocator,
extensions: std.ArrayList(Extension) = .empty,
rom: std.ArrayList(u8) = .empty,
instructions: std.ArrayList(Inst) = .empty,
blocks: std.ArrayList(Block) = .empty,
stack: std.array_list.Aligned(u8, .of([]u8)) = .empty,
kstack: std.ArrayList(Frame) = .empty,

pub const Inst = union(enum) {
    pub const Lrd = struct { l: Reg, r: Reg, d: Reg };
    pub const Ld = struct { l: Reg, d: Reg };
    pub const CmpV = enum(u8) {
        less = 0xff,
        more = 0x01,
        eqal = 0x00,
    };

    tmp: struct { usize },
    read: struct { s: usize, o: usize, d: Reg },

    arg: struct { i: u32, d: Reg },
    call: struct { id: u32, d: Reg, args: usize = 0, argcount: u32 = 0 },
    callEx: struct { id: u32, args: usize = 0, argcount: u32 = 0 },
    ret: Reg,

    cpy: Ld,
    mov: Ld,

    lea: Ld,
    add: Lrd,
    sub: Lrd,
    mul: Lrd,
    div: Lrd,
    mod: Lrd,
    cmp: Lrd,

    not: Ld,
    nnot: Ld,

    bnot: Ld,
    band: Lrd,
    bor: Lrd,
    bxor: Lrd,
    shl: Lrd,
    shr: Lrd,

    jmp3: struct {
        r: ?Reg,
        more: u32,
        less: u32,
        equal: u32,
    },
};
