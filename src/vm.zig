const std = @import("std");
pub const Reg = u32;
pub const Mach = @This();

const Slot = struct { offset: usize, len: usize };
const Block = struct { offset: usize, len: usize, slots: []Slot, size: usize };
const Frame = struct {
    block: ?u32 = null,
    counter: usize = 0,
    base: usize,
    slots: []const Slot,
    callargs: u32 = 0, // Byte offset of resolved u32 pairs in stack.
    argcount: u32 = 0,
};

alloc: std.mem.Allocator,
rom: std.ArrayList(u8) = .empty,
instructions: std.ArrayList(Inst) = .empty,
blocks: std.ArrayList(Block) = .empty,
stack: std.ArrayList(u8) = .empty,
kstack: std.ArrayList(Frame) = .empty,

pub const Inst = union(enum) {
    pub const Lrd = struct { l: Reg, r: Reg, d: Reg };
    pub const Ld = struct { l: Reg, d: Reg };
    pub const CmpV = enum(u8) {
        less = 0xff,
        more = 0x01,
        eqal = 0x00,
    };

    tmp: struct { u32 },
    read: struct { s: u32, o: u32, d: Reg },

    arg: struct { i: u32, d: Reg },
    call: struct { id: u32, d: Reg, args: []const Reg = &.{} },
    ret: Reg,

    cpy: Ld,
    mov: Ld,

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

pub fn init(alloc: std.mem.Allocator) !Mach {
    return .{ .alloc = alloc };
}

pub fn deinit(this: *Mach) void {
    for (this.instructions.items) |inst| switch (inst) {
        .call => |c| this.alloc.free(c.args),
        else => {},
    };
    for (this.blocks.items) |b| this.alloc.free(b.slots);
    for (this.kstack.items) |f| {
        if (f.block == null) this.alloc.free(f.slots);
    }
    this.blocks.deinit(this.alloc);
    this.rom.deinit(this.alloc);
    this.instructions.deinit(this.alloc);
    this.kstack.deinit(this.alloc);
    this.stack.deinit(this.alloc);
}

fn layout(allocator: std.mem.Allocator, sizes: []const u32) !struct { slots: []Slot, size: usize } {
    const slots = try allocator.alloc(Slot, sizes.len);
    errdefer allocator.free(slots);
    var size: usize = 0;
    for (sizes, slots) |len, *slot| {
        if (len == 0) return error.EmptyRegister;
        slot.* = .{ .offset = size, .len = len };
        size = try std.math.add(usize, size, len);
    }
    return .{ .slots = slots, .size = size };
}

/// Create a caller frame on the VM stack, with register sizes in bytes.
/// Calls return to these registers; run never returns a host value.
pub fn pushStack(this: *Mach, sizes: []const u32) !void {
    const registers = try layout(this.alloc, sizes);
    errdefer this.alloc.free(registers.slots);
    const base = this.stack.items.len;
    try this.stack.appendNTimes(this.alloc, 0, registers.size);
    errdefer this.stack.shrinkRetainingCapacity(base);
    try this.kstack.append(this.alloc, .{ .base = base, .slots = registers.slots });
}

pub fn popStack(this: *Mach) !void {
    if (this.kstack.items.len == 0) return error.NoCallerFrame;
    const frame = this.kstack.items[this.kstack.items.len - 1];
    if (frame.block != null) return error.ActiveCall;
    _ = this.kstack.pop();
    this.stack.shrinkRetainingCapacity(frame.base);
    this.alloc.free(frame.slots);
}

pub fn pushBlock(this: *Mach, instructions: []const Inst) !u32 {
    const id = std.math.cast(u32, this.blocks.items.len) orelse return error.TooManyBlocks;
    var sizes: std.ArrayList(u32) = .empty;
    defer sizes.deinit(this.alloc);
    for (instructions) |inst| switch (inst) {
        .tmp => |t| try sizes.append(this.alloc, t[0]),
        else => {},
    };
    const registers = try layout(this.alloc, sizes.items);
    errdefer this.alloc.free(registers.slots);
    const offset = this.instructions.items.len;
    errdefer {
        for (this.instructions.items[offset..]) |inst| switch (inst) {
            .call => |c| this.alloc.free(c.args),
            else => {},
        };
        this.instructions.shrinkRetainingCapacity(offset);
    }
    for (instructions) |inst| {
        var owned = inst;
        if (inst == .call) owned.call.args = try this.alloc.dupe(Reg, inst.call.args);
        errdefer if (owned == .call) this.alloc.free(owned.call.args);
        try this.instructions.append(this.alloc, owned);
    }
    try this.blocks.append(this.alloc, .{ .offset = offset, .len = instructions.len, .slots = registers.slots, .size = registers.size });
    return id;
}

pub fn pushRomBytes(this: *Mach, bytes: []const u8) !u32 {
    const offset = std.math.cast(u32, this.rom.items.len) orelse return error.RomTooLarge;
    _ = std.math.cast(u32, try std.math.add(usize, this.rom.items.len, bytes.len)) orelse return error.RomTooLarge;
    try this.rom.appendSlice(this.alloc, bytes);
    return offset;
}

pub fn pushRom(this: *Mach, value: anytype) !u32 {
    const T = @TypeOf(value);
    const info = @typeInfo(T);
    if (info != .int or info.int.signedness != .unsigned) @compileError("ROM integers must be unsigned; use pushRomBytes for raw bytes");
    var bytes: [(@bitSizeOf(T) + 7) / 8]u8 = undefined;
    var remaining = value;
    for (&bytes) |*byte| {
        byte.* = @intCast(remaining & @as(T, @truncate(@as(u8, 255))));
        remaining = if (@bitSizeOf(T) > 8) remaining >> 8 else 0;
    }
    return this.pushRomBytes(&bytes);
}

pub fn readFromRom(this: *Mach, dest: Reg, value: anytype) !@FieldType(Inst, "read") {
    return .{ .s = (@bitSizeOf(@TypeOf(value)) + 7) / 8, .o = try this.pushRom(value), .d = dest };
}

fn register(this: *Mach, frame_index: usize, reg: Reg) ![]u8 {
    const frame = this.kstack.items[frame_index];
    if (reg >= frame.slots.len) return error.InvalidRegister;
    const slot = frame.slots[reg];
    return this.stack.items[frame.base + slot.offset ..][0..slot.len];
}

fn resolve(frame: Frame, reg: Reg) ![2]u32 {
    if (reg >= frame.slots.len) return error.InvalidRegister;
    const slot = frame.slots[reg];
    const offset = std.math.cast(u32, try std.math.add(usize, frame.base, slot.offset)) orelse return error.StackTooLarge;
    const len = std.math.cast(u32, slot.len) orelse return error.StackTooLarge;
    _ = std.math.add(u32, offset, len) catch return error.StackTooLarge;
    return .{ offset, len };
}

fn enter(this: *Mach, call: @FieldType(Inst, "call")) !void {
    if (call.id >= this.blocks.items.len) return error.InvalidBlock;
    const parent = this.kstack.items[this.kstack.items.len - 1];
    const argcount = std.math.cast(u32, call.args.len) orelse return error.TooManyArguments;
    const pairs = try std.math.add(usize, call.args.len, 1);
    const bytes = try std.math.mul(usize, pairs, 2 * @sizeOf(u32));
    const block = this.blocks.items[call.id];
    const base = this.stack.items.len;
    const callargs = std.math.cast(u32, try std.math.add(usize, base, block.size)) orelse return error.StackTooLarge;
    _ = std.math.cast(u32, try std.math.add(usize, callargs, bytes)) orelse return error.StackTooLarge;
    try this.stack.appendNTimes(this.alloc, 0, try std.math.add(usize, block.size, bytes));
    errdefer this.stack.shrinkRetainingCapacity(base);
    this.writeCallPair(callargs, 0, try resolve(parent, call.d));
    for (call.args, 0..) |arg, i| this.writeCallPair(callargs, i + 1, try resolve(parent, arg));
    try this.kstack.append(this.alloc, .{ .block = call.id, .base = base, .slots = block.slots, .callargs = callargs, .argcount = argcount });
}

fn writeCallPair(this: *Mach, offset: u32, index: usize, pair: [2]u32) void {
    const bytes = this.stack.items[@as(usize, offset) + index * 8 ..][0..8];
    std.mem.writeInt(u32, bytes[0..4], pair[0], .little);
    std.mem.writeInt(u32, bytes[4..8], pair[1], .little);
}

fn callPair(this: *Mach, frame: Frame, index: usize) [2]u32 {
    const bytes = this.stack.items[@as(usize, frame.callargs) + index * 8 ..][0..8];
    return .{ std.mem.readInt(u32, bytes[0..4], .little), std.mem.readInt(u32, bytes[4..8], .little) };
}

fn callRegister(this: *Mach, frame: Frame, index: usize) []u8 {
    const pair = this.callPair(frame, index);
    return this.stack.items[pair[0]..][0..pair[1]];
}

pub fn run(this: *Mach, entry: Inst) !void {
    if (entry != .call) return error.InvalidEntry;
    if (this.kstack.items.len == 0) return error.NoCallerFrame;
    const caller_depth = this.kstack.items.len;
    if (this.kstack.items[caller_depth - 1].block != null) return error.ActiveCall;
    const stackend = this.stack.items.len;
    defer {
        this.kstack.shrinkRetainingCapacity(caller_depth);
        this.stack.shrinkRetainingCapacity(stackend);
    }
    try this.enter(entry.call);
    while (this.kstack.items.len > caller_depth) {
        const fi = this.kstack.items.len - 1;
        const frame = &this.kstack.items[fi];
        const block = this.blocks.items[frame.block.?];
        if (frame.counter >= block.len) return error.MissingReturn;
        const inst = this.instructions.items[block.offset + frame.counter];
        frame.counter += 1;
        switch (inst) {
            .tmp => {},
            .read => |r| {
                const end = try std.math.add(usize, r.o, r.s);
                if (end > this.rom.items.len) return error.InvalidRom;
                copy(try this.register(fi, r.d), this.rom.items[r.o..end]);
            },
            .arg => |a| {
                if (a.i >= frame.argcount) return error.InvalidArgument;
                copy(try this.register(fi, a.d), this.callRegister(frame.*, @as(usize, a.i) + 1));
            },
            .call => |c| try this.enter(c),
            .ret => |r| {
                copy(this.callRegister(frame.*, 0), try this.register(fi, r));
                const base = frame.base;
                _ = this.kstack.pop();
                this.stack.shrinkRetainingCapacity(base);
            },
            .jmp3 => |j| {
                const c: u8 = if (j.r) |r| (try this.register(fi, r))[0] else 0;
                const target = switch (c) {
                    0xff => j.less,
                    0 => j.equal,
                    1 => j.more,
                    else => return error.InvalidComparison,
                };
                if (target >= block.len) return error.InvalidJump;
                frame.counter = target;
            },
            .cpy, .mov, .not, .nnot, .bnot => |a| {
                const source = try this.alloc.dupe(u8, try this.register(fi, a.l));
                defer this.alloc.free(source);
                const dest = try this.register(fi, a.d);
                switch (inst) {
                    .cpy, .mov => copy(dest, source),
                    .not, .nnot => {
                        @memset(dest, 0);
                        dest[0] = @intFromBool(if (inst == .not) isZero(source) else !isZero(source));
                    },
                    .bnot => for (dest, 0..) |*byte, i| {
                        byte.* = ~at(source, i);
                    },
                    else => unreachable,
                }
                if (inst == .mov and a.l != a.d) @memset(try this.register(fi, a.l), 0);
            },
            .add, .sub, .mul, .div, .mod, .cmp, .band, .bor, .bxor, .shl, .shr => |a| {
                const left = try this.alloc.dupe(u8, try this.register(fi, a.l));
                defer this.alloc.free(left);
                const right = try this.alloc.dupe(u8, try this.register(fi, a.r));
                defer this.alloc.free(right);
                try this.binary(inst, try this.register(fi, a.d), left, right);
            },
        }
    }
}

fn at(bytes: []const u8, i: usize) u8 {
    return if (i < bytes.len) bytes[i] else 0;
}
fn isZero(bytes: []const u8) bool {
    for (bytes) |b| {
        if (b != 0) return false;
    }
    return true;
}
fn copy(dest: []u8, source: []const u8) void {
    const len = @min(dest.len, source.len);
    @memmove(dest[0..len], source[0..len]);
    @memset(dest[len..], 0);
}
fn compare(left: []const u8, right: []const u8) std.math.Order {
    var i = @max(left.len, right.len);
    while (i > 0) {
        i -= 1;
        if (at(left, i) < at(right, i)) return .lt;
        if (at(left, i) > at(right, i)) return .gt;
    }
    return .eq;
}
fn subtract(dest: []u8, left: []const u8, right: []const u8) void {
    var borrow: u16 = 0;
    for (dest, 0..) |*byte, i| {
        const l: u16 = at(left, i);
        const r: u16 = @as(u16, at(right, i)) + borrow;
        byte.* = @truncate(l + 256 - r);
        borrow = @intFromBool(l < r);
    }
}
fn binary(this: *Mach, inst: Inst, dest: []u8, left: []const u8, right: []const u8) !void {
    @memset(dest, 0);
    switch (inst) {
        .add => {
            var carry: u16 = 0;
            for (dest, 0..) |*byte, i| {
                const sum = @as(u16, at(left, i)) + at(right, i) + carry;
                byte.* = @truncate(sum);
                carry = sum >> 8;
            }
        },
        .sub => subtract(dest, left, right),
        .mul => {
            for (left[0..@min(left.len, dest.len)], 0..) |l, i| {
                var carry: u16 = 0;
                var j: usize = 0;
                while (i + j < dest.len) : (j += 1) {
                    const product = @as(u16, l) * at(right, j) + dest[i + j] + carry;
                    dest[i + j] = @truncate(product);
                    carry = product >> 8;
                }
            }
        },
        .div, .mod => {
            if (isZero(right)) return error.DivisionByZero;
            const remainder = try this.alloc.alloc(u8, try std.math.add(usize, @max(left.len, right.len), 1));
            defer this.alloc.free(remainder);
            @memset(remainder, 0);
            var bit = try std.math.mul(usize, left.len, 8);
            while (bit > 0) {
                bit -= 1;
                var carry: u16 = (left[bit / 8] >> @as(u3, @intCast(bit % 8))) & 1;
                for (remainder) |*byte| {
                    const v = (@as(u16, byte.*) << 1) | carry;
                    byte.* = @truncate(v);
                    carry = v >> 8;
                }
                if (compare(remainder, right) != .lt) {
                    subtract(remainder, remainder, right);
                    if (inst == .div and bit / 8 < dest.len) dest[bit / 8] |= @as(u8, 1) << @as(u3, @intCast(bit % 8));
                }
            }
            if (inst == .mod) copy(dest, remainder);
        },
        .cmp => dest[0] = switch (compare(left, right)) {
            .lt => 0xff,
            .eq => 0,
            .gt => 1,
        },
        .band, .bor, .bxor => for (dest, 0..) |*byte, i| {
            byte.* = switch (inst) {
                .band => at(left, i) & at(right, i),
                .bor => at(left, i) | at(right, i),
                .bxor => at(left, i) ^ at(right, i),
                else => unreachable,
            };
        },
        .shl, .shr => {
            const limit = try std.math.mul(usize, if (inst == .shl) dest.len else left.len, 8);
            var shift: usize = 0;
            var i = right.len;
            while (i > 0) {
                i -= 1;
                shift = std.math.mul(usize, shift, 256) catch return;
                shift = std.math.add(usize, shift, right[i]) catch return;
                if (shift >= limit) return;
            }
            for (dest, 0..) |*byte, d| {
                var b: usize = 0;
                while (b < 8) : (b += 1) {
                    const target = try std.math.add(usize, try std.math.mul(usize, d, 8), b);
                    const source = if (inst == .shl) (if (target >= shift) target - shift else continue) else (std.math.add(usize, target, shift) catch continue);
                    if (source / 8 < left.len) byte.* |= ((left[source / 8] >> @as(u3, @intCast(source % 8))) & 1) << @as(u3, @intCast(b));
                }
            }
        },
        else => unreachable,
    }
}

test "call frame stores resolved u32 return and argument locations" {
    var mach = try init(std.testing.allocator);
    defer mach.deinit();
    try mach.pushStack(&.{4});
    try mach.pushStack(&.{ 1, 2, 4 });
    const block = try mach.pushBlock(&.{ .{ .tmp = .{4} }, .{ .ret = 0 } });
    try mach.enter(.{ .id = block, .d = 1, .args = &.{ 2, 0 } });
    const frame = mach.kstack.items[2];
    try std.testing.expectEqual(@as(u32, 15), frame.callargs);
    try std.testing.expectEqual(@as(u32, 2), frame.argcount);
    try std.testing.expectEqual([2]u32{ 5, 2 }, mach.callPair(frame, 0));
    try std.testing.expectEqual([2]u32{ 7, 4 }, mach.callPair(frame, 1));
    try std.testing.expectEqual([2]u32{ 4, 1 }, mach.callPair(frame, 2));
    // Stack growth does not invalidate the stored offsets.
    try mach.stack.appendNTimes(mach.alloc, 0, 1024);
    copy(try mach.register(1, 2), &.{ 1, 2, 3, 4 });
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, mach.callRegister(mach.kstack.items[2], 1));
}

fn resolvedCallScenario(allocator: std.mem.Allocator) !void {
    var mach = try init(allocator);
    defer mach.deinit();
    try mach.pushStack(&.{4});
    try mach.pushStack(&.{ 1, 2, 4 });
    copy(try mach.register(1, 0), &.{3});
    copy(try mach.register(1, 2), &.{ 255, 1, 2, 3 });
    const child = try mach.pushBlock(&.{
        .{ .tmp = .{4} },                        .{ .tmp = .{1} },
        .{ .arg = .{ .i = 0, .d = 0 } },         .{ .arg = .{ .i = 1, .d = 1 } },
        .{ .add = .{ .l = 0, .r = 1, .d = 0 } }, .{ .ret = 0 },
    });
    const parent = try mach.pushBlock(&.{
        .{ .tmp = .{4} },                                          .{ .tmp = .{1} },
        .{ .arg = .{ .i = 0, .d = 0 } },                           .{ .arg = .{ .i = 1, .d = 1 } },
        .{ .call = .{ .id = child, .d = 0, .args = &.{ 0, 1 } } }, .{ .ret = 0 },
    });
    try mach.run(.{ .call = .{ .id = parent, .d = 1, .args = &.{ 2, 0 } } });
    try std.testing.expectEqualSlices(u8, &.{ 2, 2 }, try mach.register(1, 1));
    try std.testing.expectEqual(@as(usize, 2), mach.kstack.items.len);
    try std.testing.expectEqual(@as(usize, 11), mach.stack.items.len);
    const bad = try mach.pushBlock(&.{
        .{ .tmp = .{1} }, .{ .arg = .{ .i = 1, .d = 0 } }, .{ .ret = 0 },
    });
    if (mach.run(.{ .call = .{ .id = bad, .d = 1, .args = &.{0} } })) {
        return error.TestExpectedError;
    } else |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.InvalidArgument, err);
    }
    try std.testing.expectEqual(@as(usize, 2), mach.kstack.items.len);
    try std.testing.expectEqual(@as(usize, 11), mach.stack.items.len);
}

test "resolved locations handle nested calls and allocation failure cleanup" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, resolvedCallScenario, .{});
}

test "enter and return require no heap allocation when stack capacity is available" {
    var mach = try init(std.testing.allocator);
    defer mach.deinit();
    try mach.pushStack(&.{1});
    const block = try mach.pushBlock(&.{ .{ .tmp = .{5} }, .{ .ret = 0 } });
    try mach.stack.ensureUnusedCapacity(mach.alloc, 64);
    try mach.kstack.ensureUnusedCapacity(mach.alloc, 1);
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    mach.alloc = failing.allocator();
    defer mach.alloc = std.testing.allocator;
    try mach.run(.{ .call = .{ .id = block, .d = 0, .args = &.{0} } });
    try std.testing.expect(!failing.has_induced_failure);
    try std.testing.expectEqual(@as(usize, 1), mach.kstack.items.len);
    try std.testing.expectEqualSlices(u8, &.{0}, mach.stack.items);
}
