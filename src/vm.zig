pub const Mach = @This();
fn ct_assert(comptime cnd: bool, comptime msg: []const u8) void {
    if (!cnd) @compileError(msg);
}
const CBitInt = @import("bitint");
pub const BitInt = struct {
    pub const BitBuf = CBitInt.BitBuf;
    const Math = enum { add, sub, mul, div, mod, shr, shl };

    fn nativeMath(comptime op: Math, bits: u32, l: [*]const BitBuf, r: [*]BitBuf) bool {
        if (bits > @bitSizeOf(@FieldType(BitBuf, "as64"))) return false;

        const left: u64 = @truncate(l[0].as64);
        const right: u64 = @truncate(r[0].as64);
        r[0].as64 = switch (op) {
            .add => left +% right,
            .sub => left -% right,

            .shr => left >> @intCast(right),
            .shl => left << @intCast(right),

            .mul => left *% right,
            .div => left / right,
            .mod => left % right,
        };
        return true;
    }

    pub fn add(bits: u32, l: [*]const BitBuf, r: [*]BitBuf) void {
        if (nativeMath(.add, bits, l, r)) return;
        CBitInt.eval_bitint_add(@intCast(bits), @constCast(l), r);
    }
    pub fn sub(bits: u32, l: [*]const BitBuf, r: [*]BitBuf) void {
        if (nativeMath(.sub, bits, l, r)) return;
        CBitInt.eval_bitint_sub(@intCast(bits), @constCast(l), r);
    }
    pub fn mul(bits: u32, l: [*]const BitBuf, r: [*]BitBuf) void {
        if (nativeMath(.mul, bits, l, r)) return;
        CBitInt.eval_bitint_mul(@intCast(bits), @constCast(l), r);
    }
    pub fn div(bits: u32, l: [*]const BitBuf, r: [*]BitBuf) void {
        if (nativeMath(.div, bits, l, r)) return;
        CBitInt.eval_bitint_div(@intCast(bits), @constCast(l), r, true, true);
    }
    pub fn mod(bits: u32, l: [*]const BitBuf, r: [*]BitBuf) void {
        if (nativeMath(.mod, bits, l, r)) return;
        CBitInt.eval_bitint_div(@intCast(bits), @constCast(l), r, true, false);
    }
    pub fn cmp(bits: u32, l: [*]const BitBuf, r: [*]BitBuf) i32 {
        inline for (.{ c_uint, c_ulong }) |T| {
            if (bits == @bitSizeOf(T)) {
                const left: T = @truncate(l[0].as64);
                const right: T = @truncate(r[0].as64);
                return if (left == right) 0 else if (left < right) 1 else 2;
            }
        }
        return @intCast(CBitInt.eval_bitint_cmp(@intCast(bits), @constCast(l), r, true));
    }
    pub const BitBufBits = @sizeOf(BitBuf) * 8;
    pub fn nnot(bits: u32, l: [*]const BitBuf) bool {
        for (0..(bits / BitBufBits)) |i|
            if (l[i].as64 != 0) return true;
        const remainder = bits % BitBufBits;
        if (remainder != 0) {
            const mask = (@as(u64, 1) << @intCast(remainder)) - 1;
            if (mask & l[bits / BitBufBits].as64 != 0) return true;
        }
        return false;
    }
    pub fn not(bits: u32, l: [*]const BitBuf) bool {
        return !nnot(bits, l);
    }
    pub fn bnot(bits: u32, l: [*]BitBuf) void {
        CBitInt.eval_bitint_bitnot(@intCast(bits), l);
    }
    pub fn shl(bits: u32, l: [*]const BitBuf, r: [*]BitBuf, ammount: i32) void {
        if (nativeMath(.shl, bits, l, r)) return;
        CBitInt.eval_bitint_shl(@intCast(bits), @constCast(l), r, ammount);
    }
    pub fn sshr(bits: u32, l: [*]const BitBuf, r: [*]BitBuf, ammount: i32) void {
        CBitInt.eval_bitint_shr(@intCast(bits), @constCast(l), r, ammount, true);
    }
    pub fn shr(bits: u32, l: [*]const BitBuf, r: [*]BitBuf, ammount: i32) void {
        if (nativeMath(.shr, bits, l, r)) return;
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
    var a = [_]BitInt.BitBuf{.{ .as64 = 0b100000000 }};
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
pub const CSlice = CBitInt.u8slice;
pub const Extension = *const fn (arg: CSlice, ret: CSlice) callconv(.c) void;
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
rootItems: SgList(Slot) = .empty,
addressStack: List(Frame) = .empty,

const Frame = struct {
    block: ?FnId = null,
    base: usize = 0,
    pc: usize = 0,
    argument: Slot = .{ .offset = 0, .bits = 0 },
    destination: ?Slot = null,
};

pub const FnId = u32;
pub const Inst = union(enum) {
    pub const Lrd = struct { l: Reg, r: Reg, d: Reg };
    pub const Ld = struct { l: Reg, d: Reg };
    pub const Cmp = enum(u8) {
        @"<" = 0xff,
        @">" = 0x01,
        @"=" = 0x00,
        pub fn asu8(self: @This()) u8 {
            return @backingInt(self);
        }
    };
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
        @"<": u32 = std.math.maxInt(u32),
        @"=": u32 = std.math.maxInt(u32),
        const Self = @This();
        pub fn unconditional(loc: u32) Self {
            return .{ .@">" = loc };
        }
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
    self.rootItems.deinit(self.alloc);
    self.extensions.deinit(self.alloc);
    self.rom.deinit(self.alloc);
    self.stack.deinit(self.alloc);
}

pub fn makeExtension(self: *Mach, extension: Extension) !FnId {
    const id: FnId = @intCast(self.extensions.items.len);
    try self.extensions.append(self.alloc, extension);
    return id;
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
            const len = length / 8 + @intFromBool(length % 8 != 0);
            const end = try std.math.add(usize, offset, len);
            try items.append(self.alloc, .{ .offset = offset, .bits = length });
            offset = end;
        },
        else => {},
    };
    const owned_items = try items.toOwnedSlice(self.alloc);
    errdefer self.alloc.free(owned_items);
    const owned_instructions = try self.alloc.dupe(Inst, &ists);
    errdefer self.alloc.free(owned_instructions);
    try self.blocks.append(self.alloc, .{
        .instructions = owned_instructions,
        .items = owned_items,
    });
    return id;
}

fn readStack(self: *const Mach, offset: usize, bytes: []u8) void {
    for (bytes, 0..) |*byte, i| byte.* = self.stack.getConst(offset + i).*;
}

fn writeStack(self: *Mach, offset: usize, bytes: []const u8) void {
    for (bytes, 0..) |byte, i| self.stack.get(offset + i).* = byte;
}

const Slot = struct {
    offset: usize,
    bits: usize,
    fn len(s: Slot) usize {
        return (s.bits + 7) / 8;
    }
};
fn slot(self: *Mach, id: ?FnId, frame: usize, reg: Reg) Slot {
    if (id) |block| {
        const items = self.blocks.items[block].items;
        return .{ .offset = frame + items[reg].offset, .bits = items[reg].bits };
    }
    return self.rootItems.get(reg).*;
}
fn load(self: *Mach, s: Slot, bytes: []u8) void {
    @memset(bytes, 0);
    self.readStack(s.offset, bytes[0..@min(s.len(), bytes.len)]);
    if (s.bits % 8 != 0 and s.len() <= bytes.len)
        bytes[s.len() - 1] &= (@as(u8, 1) << @intCast(s.bits % 8)) - 1;
}
fn save(self: *Mach, s: Slot, bytes: []const u8) void {
    for (0..s.len()) |i| self.stack.get(s.offset + i).* = if (i < bytes.len) bytes[i] else 0;
    if (s.bits % 8 != 0) self.stack.get(s.offset + s.len() - 1).* &= (@as(u8, 1) << @intCast(s.bits % 8)) - 1;
}

pub fn run(self: *Mach, instruction: Inst) !void {
    const root_len = self.stack.len;
    errdefer {
        self.stack.len = root_len;
        self.addressStack.items.len = 0;
    }
    var current: Frame = .{};
    var inst = instruction;
    while (true) {
        const id = current.block;
        const frame = current.base;
        switch (inst) {
            .tmp => |bits| {
                if (id == null) {
                    const len = (bits + 7) / 8;
                    const offset = self.stack.len;
                    try self.stack.appendNTimes(self.alloc, 0, len);
                    try self.rootItems.append(self.alloc, .{ .offset = offset, .bits = bits });
                }
            },
            .rom => |v| {
                self.save(self.slot(id, frame, v.d), self.rom.items[v.o..][0..v.s]);
            },
            .ret => |reg| {
                const source = self.slot(id, frame, reg);
                if (current.destination) |dest| {
                    const bytes = try self.alloc.alloc(u8, source.len());
                    defer self.alloc.free(bytes);
                    self.load(source, bytes);
                    self.save(dest, bytes);
                }
                if (id == null) return;
                self.stack.len = current.base;
                current = self.addressStack.pop().?;
            },
            .arg, .cpy => {
                const source: Slot = switch (inst) {
                    .arg => current.argument,
                    .cpy => |v| self.slot(id, frame, v.l),
                    else => unreachable,
                };
                const dest = switch (inst) {
                    .arg => |r| self.slot(id, frame, r),
                    .cpy => |v| self.slot(id, frame, v.d),
                    else => unreachable,
                };
                const bytes = try self.alloc.alloc(u8, source.len());
                defer self.alloc.free(bytes);
                self.load(source, bytes);
                self.save(dest, bytes);
            },
            .cons, .dcons => |v| {
                const count = std.mem.readInt(u64, self.rom.items[v.args..][0..8], @import("builtin").target.cpu.arch.endian());
                const start = v.args + 8;
                const aggregate = self.slot(id, frame, v.d);
                var offset: usize = 0;
                for (0..@intCast(count)) |i| {
                    const r = std.mem.readInt(Reg, self.rom.items[start + i * 4 ..][0..4], @import("builtin").target.cpu.arch.endian());
                    const part = self.slot(id, frame, r);
                    const bytes = try self.alloc.alloc(u8, part.len());
                    defer self.alloc.free(bytes);
                    if (inst == .cons) {
                        self.load(part, bytes);
                        self.writeStack(aggregate.offset + offset, bytes);
                    } else {
                        self.readStack(aggregate.offset + offset, bytes);
                        self.save(part, bytes);
                    }
                    offset += part.len();
                }
            },
            .call => |v| {
                const empty_root = id == null and self.rootItems.len == 0;
                const arg: Slot = if (empty_root and v.arg == 0) .{ .offset = 0, .bits = 0 } else self.slot(id, frame, v.arg);
                const dest: ?Slot = if (empty_root and v.d == 0) null else self.slot(id, frame, v.d);
                const base = self.stack.len;
                const items = self.blocks.items[v.id].items;
                const len = if (items.len == 0) 0 else items[items.len - 1].offset + (items[items.len - 1].bits + 7) / 8;
                for (0..len) |_| try self.stack.push(self.alloc, 0);
                try self.addressStack.append(self.alloc, current);
                current = .{ .block = v.id, .base = base, .argument = arg, .destination = dest };
            },
            .calx => |v| {
                const arg = self.slot(id, frame, v.arg);
                const dest = self.slot(id, frame, v.d);
                const argument = try self.alloc.alloc(u8, arg.len());
                defer self.alloc.free(argument);
                const result = try self.alloc.alloc(u8, dest.len());
                defer self.alloc.free(result);
                self.load(arg, argument);
                self.load(dest, result);
                self.extensions.items[v.id](
                    .{ .len = argument.len, .ptr = argument.ptr },
                    .{ .len = result.len, .ptr = result.ptr },
                );
                self.save(dest, result);
            },
            .loa => |v| {
                const source = self.slot(id, frame, v.l);
                const pointer: Ptr = .{ .heap = false, .addr = @intCast(source.offset) };
                const dest = self.slot(id, frame, v.d);
                self.save(dest, std.mem.asBytes(&pointer));
            },
            .jmp3 => |v| {
                const target = if (v.r) |r| blk: {
                    const s = self.slot(id, frame, r);
                    break :blk switch (self.stack.get(s.offset).*) {
                        Inst.Cmp.@"=".asu8() => v.@"=",
                        Inst.Cmp.@">".asu8() => v.@">",
                        else => v.@"<",
                    };
                } else v.@">";
                if (target != std.math.maxInt(u32)) {
                    current.pc = target;
                }
            },
            else => try self.arithmetic(id, frame, inst),
        }
        const block = current.block orelse return;
        const code = self.blocks.items[block].instructions;
        inst = code[current.pc];
        current.pc += 1;
    }
}

fn arithmetic(self: *Mach, id: ?FnId, frame: usize, inst: Inst) !void {
    const operands: Inst.Lrd = switch (inst) {
        .add, .sub, .mul, .div, .mod, .cmp, .band, .bor, .bxor, .shl, .shr => |v| v,
        .not, .nnot, .bnot => |v| .{ .l = v.l, .r = v.l, .d = v.d },
        else => unreachable,
    };
    const left = self.slot(id, frame, operands.l);
    const right = self.slot(id, frame, operands.r);
    const dest = self.slot(id, frame, operands.d);
    const width = @max(left.bits, right.bits);
    const bits: u32 = @intCast(width);
    const l = try self.alloc.alloc(BitInt.BitBuf, (width + 63) / 64);
    defer self.alloc.free(l);
    const r = try self.alloc.alloc(BitInt.BitBuf, l.len);
    defer self.alloc.free(r);
    self.load(left, std.mem.sliceAsBytes(l));
    self.load(right, std.mem.sliceAsBytes(r));
    switch (inst) {
        .add => BitInt.add(bits, l.ptr, r.ptr),
        .sub => BitInt.sub(bits, l.ptr, r.ptr),
        .mul => BitInt.mul(bits, l.ptr, r.ptr),
        .div, .mod => {
            if (BitInt.not(bits, r.ptr)) return error.DivisionByZero;
            if (inst == .div) BitInt.div(bits, l.ptr, r.ptr) else BitInt.mod(bits, l.ptr, r.ptr);
        },
        .cmp => {
            const result: u8 = switch (BitInt.cmp(bits, l.ptr, r.ptr)) {
                0 => 0,
                2 => 1,
                else => 0xff,
            };
            return self.save(dest, &.{result});
        },
        .not, .nnot => return self.save(dest, &.{@intFromBool(if (inst == .not) BitInt.not(bits, l.ptr) else BitInt.nnot(bits, l.ptr))}),
        .bnot => BitInt.bnot(bits, r.ptr),
        .band => BitInt.band(bits, l.ptr, r.ptr),
        .bor => BitInt.bor(bits, l.ptr, r.ptr),
        .bxor => BitInt.bxor(bits, l.ptr, r.ptr),
        .shl, .shr => {
            var amount: u64 = r[0].as64;
            for (r[1..]) |word| if (word.as64 != 0) {
                amount = width;
                break;
            };
            if (amount >= width) @memset(std.mem.sliceAsBytes(r), 0) else {
                if (inst == .shl) BitInt.shl(bits, l.ptr, r.ptr, @intCast(amount)) else BitInt.shr(bits, l.ptr, r.ptr, @intCast(amount));
            }
        },
        else => unreachable,
    }
    self.save(dest, std.mem.sliceAsBytes(r));
}

test "execution: arithmetic, aliasing, nested calls and frame cleanup" {
    var mach = try init(std.testing.allocator);
    defer mach.deinit();
    const child = try mach.makeBlock([_]Inst{
        .{ .tmp = 32 },                               .{ .arg = 0 },                           .{ .tmp = 32 },
        .{ .rom = try mach.makeRom(1, @as(u32, 3)) }, .{ .sub = .{ .l = 0, .r = 1, .d = 0 } }, .{ .mul = .{ .l = 0, .r = 1, .d = 0 } },
        .{ .ret = 0 },
    });
    const parent = try mach.makeBlock([_]Inst{
        .{ .tmp = 32 },                .{ .arg = 0 },
        .{ .call = .{ .id = child } }, .{ .ret = 0 },
    });
    try expectProgram(&mach, parent, std.mem.asBytes(&@as(u32, 10)), std.mem.asBytes(&@as(u32, 21)));
    try std.testing.expectEqual(@as(usize, 0), mach.stack.len);
    try std.testing.expectEqual(@as(usize, 0), mach.addressStack.items.len);
}

test "execution: partial bytes, comparisons and conditional fallthrough" {
    var mach = try init(std.testing.allocator);
    defer mach.deinit();
    const block = try mach.makeBlock([_]Inst{
        .{ .tmp = 9 },                                  .{ .tmp = 9 },                                .{ .tmp = 8 },
        .{ .rom = try mach.makeRom(0, @as(u16, 511)) }, .{ .rom = try mach.makeRom(1, @as(u16, 1)) }, .{ .add = .{ .l = 0, .r = 1, .d = 0 } },
        .{ .cmp = .{ .l = 0, .r = 1, .d = 2 } },        .{ .jmp3 = .{ .r = 2, .@">" = 100 } },        .{ .jmp3 = .unconditional(10) },
        .{ .ret = 1 },                                  .{ .ret = 0 },
    });
    try expectProgram(&mach, block, &.{}, std.mem.asBytes(&@as(u16, 0)));
}

test "execution errors unwind stack frames" {
    var mach = try init(std.testing.allocator);
    defer mach.deinit();
    const block = try mach.makeBlock([_]Inst{
        .{ .tmp = 64 },                               .{ .tmp = 64 },
        .{ .rom = try mach.makeRom(0, @as(u64, 1)) }, .{ .div = .{ .l = 0, .r = 1, .d = 0 } },
        .{ .ret = 0 },
    });
    try std.testing.expectError(error.DivisionByZero, mach.run(.{ .call = .{ .id = block } }));
    try std.testing.expectEqual(@as(usize, 0), mach.stack.len);
    try std.testing.expectEqual(@as(usize, 0), mach.addressStack.items.len);
}

test "truth checks respect bit width and word boundaries" {
    const words = [_]BitInt.BitBuf{ .{ .as64 = 0 }, .{ .as64 = 1 } };
    try std.testing.expect(!BitInt.nnot(64, &words));
    try std.testing.expect(BitInt.nnot(65, &words));
    const outside = [_]BitInt.BitBuf{.{ .as64 = 512 }};
    try std.testing.expect(!BitInt.nnot(9, &outside));
}

test "execution: unsigned arithmetic and bit operations" {
    const cases = [_]struct { Inst, u32 }{
        .{ .{ .add = .{ .l = 0, .r = 1, .d = 0 } }, 70 },
        .{ .{ .sub = .{ .l = 0, .r = 1, .d = 0 } }, 64 },
        .{ .{ .mul = .{ .l = 0, .r = 1, .d = 0 } }, 201 },
        .{ .{ .div = .{ .l = 0, .r = 1, .d = 0 } }, 22 },
        .{ .{ .mod = .{ .l = 0, .r = 1, .d = 0 } }, 1 },
        .{ .{ .band = .{ .l = 0, .r = 1, .d = 0 } }, 3 },
        .{ .{ .bor = .{ .l = 0, .r = 1, .d = 0 } }, 67 },
        .{ .{ .bxor = .{ .l = 0, .r = 1, .d = 0 } }, 64 },
        .{ .{ .shl = .{ .l = 0, .r = 1, .d = 0 } }, 536 },
        .{ .{ .shr = .{ .l = 0, .r = 1, .d = 0 } }, 8 },
        .{ .{ .bnot = .{ .l = 0, .d = 0 } }, 0xffffffbc },
        .{ .{ .not = .{ .l = 0, .d = 0 } }, 0 },
        .{ .{ .nnot = .{ .l = 0, .d = 0 } }, 1 },
    };
    inline for (cases) |case| {
        var mach = try init(std.testing.allocator);
        defer mach.deinit();
        const block = try mach.makeBlock([_]Inst{
            .{ .tmp = 32 },                                .{ .tmp = 32 },
            .{ .rom = try mach.makeRom(0, @as(u32, 67)) }, .{ .rom = try mach.makeRom(1, @as(u32, 3)) },
            case[0],                                       .{ .ret = 0 },
        });
        try expectProgram(&mach, block, &.{}, std.mem.asBytes(&@as(u32, case[1])));
    }
}

test "execution: extension and aggregate round trip" {
    var mach = try init(std.testing.allocator);
    defer mach.deinit();
    const Host = struct {
        fn increment(arg: CSlice, ret: CSlice) callconv(.c) void {
            ret.ptr[0] = arg.ptr[0] + 1;
        }
    };
    const increment = try mach.makeExtension(Host.increment);
    const block = try mach.makeBlock([_]Inst{
        .{ .tmp = 16 },                                    .{ .tmp = 8 },                                      .{ .tmp = 8 },
        .{ .arg = 0 },                                     .{ .dcons = try mach.makeCons(0, [_]Reg{ 1, 2 }) }, .{ .calx = .{ .id = increment, .arg = 1, .d = 1 } },
        .{ .cons = try mach.makeCons(0, [_]Reg{ 2, 1 }) }, .{ .ret = 0 },
    });
    try expectProgram(&mach, block, &.{ 7, 9 }, &.{ 9, 8 });
    try std.testing.expectEqual(@as(usize, 0), mach.stack.len);
}

// Observe program output through an extension, as a host would.
fn expectProgram(mach: *Mach, block: FnId, argument: []const u8, expected: []const u8) !void {
    const Capture = struct {
        var bytes: [256]u8 = undefined;
        var captured_len: usize = 0;
        var called: bool = false;
        fn output(arg: CSlice, _: CSlice) callconv(.c) void {
            const value = arg.ptr[0..arg.len];
            @memcpy(bytes[0..value.len], value);
            captured_len = value.len;
            called = true;
        }
    };
    Capture.called = false;
    const extension = try mach.makeExtension(Capture.output);
    const offset = mach.rom.items.len;
    try mach.rom.appendSlice(mach.alloc, argument);
    const entry = try mach.makeBlock([_]Inst{
        .{ .tmp = @max(1, argument.len, expected.len) * 8 },
        .{ .rom = .{ .d = 0, .o = offset, .s = argument.len } },
        .{ .call = .{ .id = block } },
        .{ .calx = .{ .id = extension } },
        .{ .ret = 0 },
    });
    try mach.run(.{ .call = .{ .id = entry } });
    try std.testing.expect(Capture.called);
    try std.testing.expectEqualSlices(u8, expected, Capture.bytes[0..expected.len]);
    try std.testing.expectEqual(@as(usize, 0), mach.stack.len);
}

test "root frame persists across instruction dispatch and failed calls" {
    var mach = try init(std.testing.allocator);
    defer mach.deinit();
    try mach.run(.{ .tmp = 32 });
    try mach.run(.{ .rom = try mach.makeRom(0, @as(u32, 10)) });
    try mach.run(.{ .tmp = 32 });
    try mach.run(.{ .rom = try mach.makeRom(1, @as(u32, 3)) });
    try mach.run(.{ .add = .{ .l = 0, .r = 1, .d = 0 } });
    const fail = try mach.makeBlock([_]Inst{
        .{ .tmp = 32 },
        .{ .div = .{ .l = 0, .r = 0, .d = 0 } },
        .{ .ret = 0 },
    });
    try std.testing.expectError(error.DivisionByZero, mach.run(.{ .call = .{ .id = fail } }));
    const Check = struct {
        var called: bool = false;
        fn output(arg: CSlice, _: CSlice) callconv(.c) void {
            const bytes = arg.ptr[0..arg.len];
            std.debug.assert(arg.len == 4);
            std.debug.assert(std.mem.readInt(u32, bytes[0..4], @import("builtin").target.cpu.arch.endian()) == 13);
            called = true;
        }
    };
    Check.called = false;
    const output = try mach.makeExtension(Check.output);
    try mach.run(.{ .calx = .{ .id = output } });
    try std.testing.expect(Check.called);
    try std.testing.expectEqual(@as(usize, 8), mach.stack.len);
    try std.testing.expectEqual(@as(usize, 0), mach.addressStack.items.len);
}

test "deep calls use VM frames and resume caller instructions" {
    var mach = try init(std.testing.allocator);
    defer mach.deinit();
    const recursive = try mach.makeBlock([_]Inst{
        .{ .tmp = 32 }, // 0
        .{ .tmp = 32 }, // 1
        .{ .tmp = 8 }, // 2
        .{ .arg = 0 }, // 3
        .{ .cmp = .{ .l = 0, .r = 1, .d = 2 } }, // 4
        .{ .jmp3 = .{ .r = 2, .@">" = 6, .@"=" = 10, .@"<" = 10 } }, // 5
        .{ .rom = try mach.makeRom(1, @as(u32, 1)) }, // 6
        .{ .sub = .{ .l = 0, .r = 1, .d = 0 } }, // 7
        .{ .call = .{ .id = 0 } }, // 8
        .{ .add = .{ .l = 0, .r = 1, .d = 0 } }, // 9
        .{ .ret = 0 }, // 10
    });
    try expectProgram(&mach, recursive, std.mem.asBytes(&@as(u32, 10000)), std.mem.asBytes(&@as(u32, 10000)));
}

test "math fallback retains multiple words" {
    var l = [_]BitInt.BitBuf{ .{ .as64 = std.math.maxInt(u64) }, .{ .as64 = 1 } };
    var r = [_]BitInt.BitBuf{ .{ .as64 = 1 }, .{ .as64 = 0 } };
    BitInt.add(128, &l, &r);
    try std.testing.expectEqual(@as(u64, 0), r[0].as64);
    try std.testing.expectEqual(@as(u64, 2), r[1].as64);
}

test "extensions receive distinct argument and return sizes" {
    var mach = try init(std.testing.allocator);
    defer mach.deinit();
    const Host = struct {
        fn widen(arg: CSlice, ret: CSlice) callconv(.c) void {
            std.debug.assert(arg.len == 1);
            std.debug.assert(ret.len == 4);
            const result: u32 = @as(u32, arg.ptr[0]) * 2;
            @memcpy(ret.ptr[0..ret.len], std.mem.asBytes(&result));
        }
    };
    const extension = try mach.makeExtension(Host.widen);
    const block = try mach.makeBlock([_]Inst{
        .{ .tmp = 8 },
        .{ .tmp = 32 },
        .{ .tmp = 40 },
        .{ .rom = try mach.makeRom(0, @as(u8, 21)) },
        .{ .calx = .{ .id = extension, .arg = 0, .d = 1 } },
        .{ .cons = try mach.makeCons(2, [_]Reg{ 0, 1 }) },
        .{ .ret = 2 },
    });
    var expected: [5]u8 = undefined;
    expected[0] = 21;
    @memcpy(expected[1..], std.mem.asBytes(&@as(u32, 42)));
    try expectProgram(&mach, block, &.{}, &expected);
}
