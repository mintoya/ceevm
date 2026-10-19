pub const Mach = @This();
const CBitInt = @import("bitint");
pub const BitInt = struct {
    pub const BitBuf = CBitInt.BitBuf;
    pub fn add(bits: u32, l: [*]const BitBuf, r: [*]BitBuf) void {
        CBitInt.eval_bitint_add(@intCast(bits), l, r);
    }
    pub fn sub(bits: u32, l: [*]const BitBuf, r: [*]BitBuf) void {
        CBitInt.eval_bitint_sub(@intCast(bits), l, r);
    }
    pub fn mul(bits: u32, l: [*]const BitBuf, r: [*]BitBuf) void {
        CBitInt.eval_bitint_mul(@intCast(bits), l, r);
    }
    pub fn div(bits: u32, l: [*]BitBuf, r: [*]BitBuf) void {
        CBitInt.eval_bitint_div(@intCast(bits), l, r, true, true);
    }
    pub fn mod(bits: u32, l: [*]BitBuf, r: [*]BitBuf) void {
        CBitInt.eval_bitint_div(@intCast(bits), l, r, true, false);
    }
    // cmp: Lrd, //    <=>
    // not: Ld, //     !
    // nnot: Ld, //    !!
    // bnot: Ld, //    ~
    // band: Lrd, //   &
    // bor: Lrd, //    |
    // bxor: Lrd, //   ^
    // shl: Lrd, //    <<
    // shr: Lrd, //    >>
};
test "div and mod" {
    var a = [_]BitInt.BitBuf{.{ .as64 = 67 }};
    var b = [_]BitInt.BitBuf{.{ .as64 = 60 }};
    BitInt.div(8, &a, &b);
    try std.testing.expectEqual(@as(u64, 1), b[0].as64);

    a[0] = .{ .as64 = 67 };
    b[0] = .{ .as64 = 60 };
    BitInt.mod(8, &a, &b);
    try std.testing.expectEqual(@as(u64, 7), b[0].as64);
}
const std = @import("std");
const List = std.ArrayList;
const Mu = std.math.big.int.Mutable;

pub const Reg = u32;
pub const Ptr = usize;
pub const Extension = *const fn (arg: []u8) void;

alloc: std.mem.Allocator,
rom: List(u8),
stack: List(u8) = .empty,
extensions: List(Extension),

pub const Inst = union(enum) {
    pub const Lrd = struct { l: Reg, r: Reg, d: Reg };
    pub const Ld = struct { l: Reg, d: Reg };
    pub const Cmp = enum(u8) {
        less = 0xff,
        more = 0x01,
        eqal = 0x00,
    };
    const Call = struct { id: u32, arg: Reg = 0 };
    const Construct = struct {
        d: Reg,
        args: usize, //[]Reg,
    };

    tmp: usize,

    rom: struct { s: usize, o: usize, d: Reg }, // read offset and size from rom

    cons: Construct,
    dcons: Construct,
    arg: Reg,
    ret: Reg,
    call: Call,
    calx: Call,

    cpy: Ld,

    loa: Ld, //     & . // load offset address

    add: Lrd, //    +
    sub: Lrd, //    -
    mul: Lrd, //    *
    div: Lrd, //    /
    mod: Lrd, //    %
    cmp: Lrd, //    <=>
    not: Ld, //     !
    nnot: Ld, //    !!
    bnot: Ld, //    ~
    band: Lrd, //   &
    bor: Lrd, //    |
    bxor: Lrd, //   ^
    shl: Lrd, //    <<
    shr: Lrd, //    >>

    jmp3: struct {
        r: ?Reg, // assumes register is result of a cmp, only checks for more and equal
        more: u32,
        less: u32,
        equal: u32,
    },
};
pub fn init(alloc: std.mem.Allocator) !Mach {
    return .{
        .alloc = alloc,
        .extensions = try .initCapacity(alloc, 8),
        .rom = try .initCapacity(alloc, 8),
    };
}
pub fn deinit(self: *Mach) void {
    self.extensions.deinit(self.alloc);
    self.rom.deinit(self.alloc);
}

pub fn makeRom(self: *Mach, into: Reg, value: anytype) !@FieldType(Inst, "rom") {
    const result: @FieldType(Inst, "rom") = .{
        .d = into,
        .o = self.rom.items.len,
        .s = @sizeOf(@TypeOf(value)),
    };
    try self.rom.appendSlice(self.alloc, std.mem.asBytes(&value));
    return result;
}
fn ct_assert(comptime cnd: bool, comptime msg: []const u8) void {
    if (!cnd) @compileError(msg);
}
pub fn makeCons(self: *Mach, into: Reg, value: anytype) !@FieldType(Inst, "cons") {
    const vt = @TypeOf(value);
    ct_assert(@typeInfo(vt) == .array, "expected array");
    ct_assert(@typeInfo(vt).array.child == Reg, "expected array of registers");
    const result: @FieldType(Inst, "cons") = .{
        .d = into,
        .args = self.rom.items.len,
    };
    try self.rom.appendSlice(self.alloc, std.mem.asBytes(&@as(u64, @typeInfo(vt).array.len)));
    try self.rom.appendSlice(self.alloc, std.mem.asBytes(&value));
    return result;
}
