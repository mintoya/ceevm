pub const Mach = @This();
const CBitInt = @import("bitint");
pub const BitInt = struct {
    pub const BitBuf = CBitInt.BitBuf;
    pub fn add(bits: u32, l: [*]const BitBuf, r: [*]BitBuf) void {
        CBitInt.eval_bitint_add(@intCast(bits), @constCast(l), r);
    }
    pub fn sub(bits: u32, l: [*]const BitBuf, r: [*]BitBuf) void {
        CBitInt.eval_bitint_sub(@intCast(bits), @constCast(l), r);
    }
    pub fn mul(bits: u32, l: [*]const BitBuf, r: [*]BitBuf) void {
        CBitInt.eval_bitint_mul(@intCast(bits), @constCast(l), r);
    }
    pub fn div(bits: u32, l: [*]const BitBuf, r: [*]BitBuf) void {
        CBitInt.eval_bitint_div(@intCast(bits), @constCast(l), r, true, true);
    }
    pub fn mod(bits: u32, l: [*]const BitBuf, r: [*]BitBuf) void {
        CBitInt.eval_bitint_div(@intCast(bits), @constCast(l), r, true, false);
    }
    pub fn cmp(bits: u32, l: [*]const BitBuf, r: [*]BitBuf) i32 {
        return @intCast(CBitInt.eval_bitint_cmp(bits, l, r, true));
    }
    pub const BitBufBits = @sizeOf(BitBuf) * 8;
    pub fn nnot(bits: u32, l: [*]const BitBuf) bool {
        for (l, 0..(bits / BitBufBits)) |v, _|
            if (v.as64 != 0) return true;
        const mask = (@as(u64, 1) << @intCast(bits % BitBufBits + 1)) - 1;
        if (mask != 0) if (mask & l[bits / BitBufBits].as64 != 0) return true;
        return false;
    }
    pub fn not(bits: u32, l: [*]const BitBuf) bool {
        return !nnot(bits, l);
    }
    pub fn bnot(bits: u32, l: [*]BitBuf) void {
        for (0..(bits / BitBufBits)) |i|
            l[i].as64 = ~l[i].as64;
        if (bits % BitBufBits != 0)
            l[bits / BitBufBits].as64 = ~l[bits / BitBufBits].as64;
    }
    // shl: Lrd, //    <<
    // shr: Lrd, //    >>
    // band: Lrd, //   &
    // bor: Lrd, //    |
    // bxor: Lrd, //   ^
};
test "div and mod" {
    var a = [_]BitInt.BitBuf{.{ .as64 = 67 }};
    var b = [_]BitInt.BitBuf{.{ .as64 = 60 }};
    BitInt.div(9, &a, &b);
    try std.testing.expectEqual(@as(u64, 1), b[0].as64);

    a[0] = .{ .as64 = 67 };
    b[0] = .{ .as64 = 60 };
    BitInt.mod(8, &a, &b);
    try std.testing.expectEqual(@as(u64, 7), b[0].as64);
}
test "not and nnot" {
    var a = [_]BitInt.BitBuf{.{ .as64 = 0b1000000000 }};
    try std.testing.expectEqual(BitInt.not(9, &a), false);
    try std.testing.expectEqual(BitInt.nnot(9, &a), true);
    a[0] = .{ .as64 = 0b1 };
    try std.testing.expectEqual(BitInt.not(1, &a), false);
    try std.testing.expectEqual(BitInt.nnot(1, &a), true);
}
test "bnot" {
    var a = [_]BitInt.BitBuf{.{ .as64 = 0b1000000000 }};
    BitInt.bnot(9, &a);
    try std.testing.expectEqual(0b0111111111, a[0].as64 & (@as(u64, 1 << 9) - 1));
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
