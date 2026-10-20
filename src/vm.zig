pub const Mach = @This();
fn ct_assert(comptime cnd: bool, comptime msg: []const u8) void {
    if (!cnd) @compileError(msg);
}
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
        CBitInt.eval_bitint_bitnot(@intCast(bits), l);
    }
    pub fn shl(bits: u32, l: [*]const BitBuf, r: [*]BitBuf, ammount: i32) void {
        CBitInt.eval_bitint_shl(@intCast(bits), @constCast(l), r, ammount);
    }
    pub fn sshr(bits: u32, l: [*]const BitBuf, r: [*]BitBuf, ammount: i32) void {
        CBitInt.eval_bitint_shr(@intCast(bits), @constCast(l), r, ammount, true);
    }
    pub fn shr(bits: u32, l: [*]const BitBuf, r: [*]BitBuf, ammount: i32) void {
        CBitInt.eval_bitint_shr(@intCast(bits), @constCast(l), r, ammount, false);
    }
    pub fn band(bits: u32, l: [*]const BitBuf, r: [*]BitBuf) void {
        CBitInt.eval_bitint_bitand(@intCast(bits), @constCast(l), r);
    }
    pub fn bor(bits: u32, l: [*]const BitBuf, r: [*]BitBuf) void {
        CBitInt.eval_bitint_bitor(@intCast(bits), @constCast(l), r);
    }
    pub fn bxor(bits: u32, l: [*]const BitBuf, r: [*]BitBuf) void {
        CBitInt.eval_bitint_bitxor(@intCast(bits), @constCast(l), r);
    }
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
test "shl shr" {
    var a = [_]BitInt.BitBuf{.{ .as64 = 0b1 }};
    var b = [_]BitInt.BitBuf{.{ .as64 = 0b1 }};
    BitInt.shl(9, &a, &b, 1);
    try std.testing.expectEqual(0b10, b[0].as64);
    BitInt.shr(9, &b, &a, 1);
    try std.testing.expectEqual(0b1, a[0].as64);
}
const std = @import("std");
const List = std.ArrayList;

pub const Reg = u32;
pub const Ptr = packed struct {
    heap: bool,
    addr: @Int(.unsigned, @bitSizeOf(*anyopaque) - 1),
};
test "ptrsize" {
    ct_assert(
        @sizeOf(Ptr) == @sizeOf(*anyopaque),
        "must be pointer sized",
    );
}
pub const Extension = *const fn (arg: []u8) void;
const SgList = @import("sglist.zig").SgList;
alloc: std.mem.Allocator,

rom: List(u8) = .empty,
//ram: List(u8) = .empty,
extensions: List(Extension) = .empty,
stack: SgList(u8) = .empty,
blocks: List(struct {
    items: []const struct {
        offset: usize,
        bits: usize,
    },
    instructions: []const Inst,
}) = .empty,
addressStack: List(struct {
    frame: usize,
    ret: usize,
    arg: usize,
}) = .empty,

pub const FnId = u32;
pub const Inst = union(enum) {
    pub const Lrd = struct { l: Reg, r: Reg, d: Reg };
    pub const Ld = struct { l: Reg, d: Reg };
    pub const Cmp = enum(u8) { @"<" = 0xff, @">" = 0x01, @"=" = 0x00 };
    const Call = struct { id: FnId, d: Reg = 0, arg: Reg = 0 };
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
        r: ?Reg = null, // assumes register is result of a cmp, only checks for more and equal
        @">": u32,
        @"<": u32 = 0,
        @"=": u32 = 0,
    },
};
pub fn init(alloc: std.mem.Allocator) !Mach {
    return .{ .alloc = alloc };
}
pub fn deinit(self: *Mach) void {
    for (self.blocks.items) |block| {
        self.alloc.free(block.items);
        self.alloc.free(block.instructions);
    }
    self.blocks.deinit(self.alloc);
    self.addressStack.deinit(self.alloc);
    self.extensions.deinit(self.alloc);
    self.rom.deinit(self.alloc);
    self.stack.deinit(self.alloc);
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
fn lineup(a: usize, u: usize) usize {
    return (a + u - 1) / u * u;
}
pub fn makeBlock(self: *Mach, instructions: anytype) !FnId {
    const ists = @as([@typeInfo(@TypeOf(instructions)).array.len]Inst, instructions);
    const id = std.math.cast(FnId, self.blocks.items.len) orelse return error.TooManyBlocks;
    const Block = @TypeOf(self.blocks.items[0]);
    const Item = @typeInfo(@FieldType(Block, "items")).pointer.child;
    var items: List(Item) = .empty;
    defer items.deinit(self.alloc);
    var offset: usize = 0;
    for (ists) |inst| switch (inst) {
        .tmp => |length| {
            std.debug.assert(length > 0);
            const len = lineup(8, length) / 8;
            const end = try std.math.add(usize, offset, len);
            try items.append(self.alloc, .{ .offset = offset, .bits = length });
            offset = end;
        },
        else => {},
    };
    const owned_items = try items.toOwnedSlice(self.alloc);
    errdefer self.alloc.free(owned_items);
    const owned_instructions = try self.alloc.dupe(Inst, &instructions);
    errdefer self.alloc.free(owned_instructions);
    try self.blocks.append(self.alloc, .{
        .instructions = owned_instructions,
        .items = owned_items,
    });
    return id;
}
