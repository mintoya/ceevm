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
slots: std.ArrayList(Slot) = .empty,
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

pub fn init(alloc: std.mem.Allocator) !Mach {
    return .{ .alloc = alloc };
}

pub fn registerExtension(this: *Mach, function: Extension) !u32 {
    const id = std.math.cast(u32, this.extensions.items.len) orelse return error.TooManyExtensions;
    try this.extensions.append(this.alloc, function);
    return id;
}

pub fn deinit(this: *Mach) void {
    this.extensions.deinit(this.alloc);
    this.rom.deinit(this.alloc);
    this.instructions.deinit(this.alloc);
    this.blocks.deinit(this.alloc);
    this.slots.deinit(this.alloc);
    this.stack.deinit(this.alloc);
    this.kstack.deinit(this.alloc);
}

fn extendStack(this: *Mach, bytes: usize) !usize {
    const base = this.stack.items.len;
    _ = try std.math.add(usize, base, bytes);
    const previous = @intFromPtr(this.stack.items.ptr);
    try this.stack.appendNTimes(this.alloc, 0, bytes);
    if (@intFromPtr(this.stack.items.ptr) != previous) {
        for (this.kstack.items) |*frame| {
            if (frame.callargs.len == 0) continue;
            const offset = @intFromPtr(frame.callargs.ptr) - previous;
            frame.callargs = this.descriptors(offset, frame.callargs.len);
        }
    }
    return base;
}

fn descriptors(this: *Mach, offset: usize, count: usize) []align(1) Slot {
    return std.mem.bytesAsSlice(Slot, this.stack.items[offset..][0 .. count * @sizeOf(Slot)]);
}

pub fn pushStack(this: *Mach, sizes: []const usize) !void {
    var size: usize = 0;
    for (sizes) |len| {
        if (len == 0) return error.EmptyRegister;
        size = try std.math.add(usize, size, len);
    }
    const bytes = try std.math.mul(usize, sizes.len, @sizeOf(Slot));
    const base = try this.extendStack(try std.math.add(usize, size, bytes));
    errdefer this.stack.shrinkRetainingCapacity(base);
    const locations = this.descriptors(base + size, sizes.len);
    var offset = base;
    for (sizes, locations) |len, *descriptor| {
        descriptor.* = .{ .offset = offset, .len = len };
        offset += len;
    }
    try this.kstack.append(this.alloc, .{ .base = base, .callargs = locations });
}

pub fn popStack(this: *Mach) !void {
    const frame = this.kstack.getLastOrNull() orelse return error.NoCallerFrame;
    if (frame.block != null) return error.ActiveCall;
    _ = this.kstack.pop();
    this.stack.shrinkRetainingCapacity(frame.base);
}

pub fn pushBlock(this: *Mach, insts: []const Inst) !u32 {
    const id = std.math.cast(u32, this.blocks.items.len) orelse return error.TooManyBlocks;
    const register_start = this.slots.items.len;
    errdefer this.slots.shrinkRetainingCapacity(register_start);
    var size: usize = 0;
    for (insts) |inst| {
        if (inst != .tmp) continue;
        const len = inst.tmp[0];
        if (len == 0) return error.EmptyRegister;
        try this.slots.append(this.alloc, .{ .offset = size, .len = len });
        size = try std.math.add(usize, size, len);
    }
    const offset = this.instructions.items.len;
    errdefer this.instructions.shrinkRetainingCapacity(offset);
    try this.instructions.appendSlice(this.alloc, insts);
    try this.blocks.append(this.alloc, .{
        .offset = offset,
        .len = insts.len,
        .registers = register_start,
        .register_count = this.slots.items.len - register_start,
        .size = size,
    });
    return id;
}

pub fn pushRomBytes(this: *Mach, bytes: []const u8) !usize {
    const offset = this.rom.items.len;
    try this.rom.appendSlice(this.alloc, bytes);
    return offset;
}
pub fn pushRom(this: *Mach, value: anytype) !usize {
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

fn pushArgs(this: *Mach, args: []const Reg) !struct { offset: usize, count: u32 } {
    const count = std.math.cast(u32, args.len) orelse return error.TooManyArguments;
    const bytes = try std.math.mul(usize, args.len, @sizeOf(Reg));
    const offset = this.rom.items.len;
    try this.rom.appendNTimes(this.alloc, 0, bytes);
    for (args, 0..) |arg, i| {
        std.mem.writeInt(Reg, this.rom.items[offset + i * @sizeOf(Reg) ..][0..@sizeOf(Reg)], arg, .little);
    }
    return .{ .offset = offset, .count = count };
}

pub fn makeCall(this: *Mach, id: u32, dest: Reg, args: []const Reg) !@FieldType(Inst, "call") {
    const stored = try this.pushArgs(args);
    return .{ .id = id, .d = dest, .args = stored.offset, .argcount = stored.count };
}

pub fn makeCallEx(this: *Mach, id: u32, args: []const Reg) !@FieldType(Inst, "callEx") {
    const stored = try this.pushArgs(args);
    return .{ .id = id, .args = stored.offset, .argcount = stored.count };
}

fn resolve(this: *Mach, frame: Frame, reg: Reg) !Slot {
    if (frame.block) |id| {
        const block = this.blocks.items[id];
        if (reg >= block.register_count) return error.InvalidRegister;
        const slot = this.slots.items[block.registers + reg];
        return .{ .offset = frame.base + slot.offset, .len = slot.len };
    }
    if (reg >= frame.callargs.len) return error.InvalidRegister;
    return frame.callargs[reg];
}

pub fn register(this: *Mach, fi: usize, reg: Reg) ![]u8 {
    if (fi >= this.kstack.items.len) return error.InvalidFrame;
    return this.location(try this.resolve(this.kstack.items[fi], reg));
}

fn location(this: *Mach, slot: Slot) []u8 {
    return this.stack.items[slot.offset..][0..slot.len];
}

fn enter(this: *Mach, call: @FieldType(Inst, "call")) !void {
    if (call.id >= this.blocks.items.len) return error.InvalidBlock;
    const argbytes = try std.math.mul(usize, call.argcount, @sizeOf(Reg));
    const argend = try std.math.add(usize, call.args, argbytes);
    if (argend > this.rom.items.len) return error.InvalidRom;
    const count = try std.math.add(usize, call.argcount, 1);
    const bytes = try std.math.mul(usize, count, @sizeOf(Slot));
    const block = this.blocks.items[call.id];
    const base = try this.extendStack(try std.math.add(usize, block.size, bytes));
    errdefer this.stack.shrinkRetainingCapacity(base);
    const parent = this.kstack.getLast();
    const locations = this.descriptors(base + block.size, count);
    locations[0] = try this.resolve(parent, call.d);
    for (0..call.argcount) |i| {
        const encoded = this.rom.items[call.args + i * @sizeOf(Reg) ..][0..@sizeOf(Reg)];
        locations[i + 1] = try this.resolve(parent, std.mem.readInt(Reg, encoded, .little));
    }
    try this.kstack.append(this.alloc, .{ .block = call.id, .base = base, .callargs = locations });
}

pub fn run(this: *Mach, entry: Inst) !void {
    if (entry != .call and entry != .callEx) return error.InvalidEntry;
    const parent = this.kstack.getLastOrNull() orelse return error.NoCallerFrame;
    if (parent.block != null) return error.ActiveCall;
    const depth = this.kstack.items.len;
    const stackend = this.stack.items.len;
    defer {
        this.kstack.shrinkRetainingCapacity(depth);
        this.stack.shrinkRetainingCapacity(stackend);
    }
    if (entry == .callEx) {
        try this.dispatchExtension(depth - 1, entry.callEx);
        return;
    }
    try this.enter(entry.call);
    while (this.kstack.items.len > depth) {
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
                Math.copy(try this.register(fi, r.d), this.rom.items[r.o..end]);
            },
            .arg => |a| {
                const index = @as(usize, a.i) + 1;
                if (index >= frame.callargs.len) return error.InvalidArgument;
                Math.copy(try this.register(fi, a.d), this.location(frame.callargs[index]));
            },
            .call => |c| try this.enter(c),
            .callEx => |b| try this.dispatchExtension(fi, b),
            .ret => |r| {
                Math.copy(this.location(frame.callargs[0]), try this.register(fi, r));
                const base = frame.base;
                _ = this.kstack.pop();
                this.stack.shrinkRetainingCapacity(base);
            },
            .jmp3 => |j| {
                const comparison = if (j.r) |r| (try this.register(fi, r))[0] else 0;
                const target = switch (comparison) {
                    0xff => j.less,
                    0 => j.equal,
                    1 => j.more,
                    else => return error.InvalidComparison,
                };
                if (target >= block.len) return error.InvalidJump;
                frame.counter = target;
            },
            .lea => |a| {
                const source = try this.resolve(frame.*, a.l);
                const dest = try this.register(fi, a.d);
                var bytes: [@sizeOf(usize)]u8 = undefined;
                std.mem.writeInt(usize, &bytes, source.offset, .little);
                for (bytes[@min(dest.len, bytes.len)..]) |byte| {
                    if (byte != 0) return error.AddressTooLarge;
                }
                Math.copy(dest, &bytes);
            },
            .cpy, .mov => |a| {
                const source = try this.register(fi, a.l);
                Math.copy(try this.register(fi, a.d), source);
                if (inst == .mov and a.l != a.d) @memset(source, 0);
            },
            inline .not, .nnot, .bnot => |a, tag| {
                const source = try this.register(fi, a.l);
                const dest = try this.register(fi, a.d);
                @field(Math, @tagName(tag))(dest, source);
            },
            inline .add, .sub, .mul, .div, .mod, .cmp, .band, .bor, .bxor, .shl, .shr => |a, tag| {
                try this.binary(fi, a, tag);
            },
        }
    }
}

fn dispatchExtension(this: *Mach, fi: usize, args: @FieldType(Inst, "callEx")) !void {
    if (args.id >= this.extensions.items.len) return error.InvalidExtension;
    try this.invokeExtension(fi, args, this.extensions.items[args.id]);
}

fn invokeExtension(this: *Mach, fi: usize, args: @FieldType(Inst, "callEx"), callback: Extension) !void {
    const encoded_len = try std.math.mul(usize, args.argcount, @sizeOf(Reg));
    const encoded_end = try std.math.add(usize, args.args, encoded_len);
    if (encoded_end > this.rom.items.len) return error.InvalidRom;
    // Reserve all slice headers before borrowing register data. The stack has
    // slice alignment, and padding keeps the headers aligned within it.
    const end = this.stack.items.len;
    const alignment: usize = @alignOf([]u8);
    const aligned = (try std.math.add(usize, end, alignment - 1)) & ~(alignment - 1);
    const bytes = try std.math.mul(usize, args.argcount, @sizeOf([]u8));
    _ = try this.extendStack(try std.math.add(usize, aligned - end, bytes));
    defer this.stack.shrinkRetainingCapacity(end);
    const headers: []align(@alignOf([]u8)) u8 = @alignCast(this.stack.items[aligned..][0..bytes]);
    const registers = std.mem.bytesAsSlice([]u8, headers);
    for (registers, 0..) |*value, i| {
        const encoded = this.rom.items[args.args + i * @sizeOf(Reg) ..][0..@sizeOf(Reg)];
        value.* = try this.register(fi, std.mem.readInt(Reg, encoded, .little));
    }
    try callback(registers);
}

fn binary(this: *Mach, fi: usize, a: Inst.Lrd, comptime op: std.meta.Tag(Inst)) !void {
    const left_len = (try this.register(fi, a.l)).len;
    const right_len = (try this.register(fi, a.r)).len;
    const dest_len = (try this.register(fi, a.d)).len;
    const remainder_len = if (op == .div or op == .mod)
        try std.math.add(usize, @max(left_len, right_len), 1)
    else
        0;
    const scratch = try this.extendStack(try std.math.add(usize, dest_len, remainder_len));
    defer this.stack.shrinkRetainingCapacity(scratch);
    const left = try this.register(fi, a.l);
    const right = try this.register(fi, a.r);
    const result = this.stack.items[scratch..][0..dest_len];
    if (op == .div or op == .mod) {
        try @field(Math, @tagName(op))(result, left, right, this.stack.items[scratch + dest_len ..]);
    } else {
        @field(Math, @tagName(op))(result, left, right);
    }
    Math.copy(try this.register(fi, a.d), result);
}

test "nested calls keep ROM immutable and caller descriptors valid across growth" {
    var mach = try init(std.testing.allocator);
    defer mach.deinit();
    try mach.pushStack(&.{ 3, 17 });
    const host_end = mach.stack.items.len;
    const leaf = try mach.pushBlock(&.{
        .{ .tmp = .{17} },
        .{ .arg = .{ .i = 0, .d = 0 } },
        .{ .ret = 0 },
    });
    var child = leaf;
    for (0..128) |_| {
        child = try mach.pushBlock(&.{
            .{ .tmp = .{17} },
            .{ .tmp = .{1} },
            .{ .arg = .{ .i = 0, .d = 0 } },
            .{ .read = try mach.readFromRom(1, @as(u8, 1)) },
            .{ .call = try mach.makeCall(child, 0, &.{0}) },
            .{ .add = .{ .l = 0, .r = 1, .d = 0 } },
            .{ .ret = 0 },
        });
    }
    Math.copy(try mach.register(0, 0), &.{ 255, 0, 0 });
    const call = try mach.makeCall(child, 1, &.{0});
    const rom_before = try std.testing.allocator.dupe(u8, mach.rom.items);
    defer std.testing.allocator.free(rom_before);
    for (0..2) |_| {
        try mach.run(.{ .call = call });
        try std.testing.expectEqualSlices(u8, &.{ 127, 1, 0 }, (try mach.register(0, 1))[0..3]);
        try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0 }, try mach.register(0, 0));
        try std.testing.expectEqualSlices(u8, rom_before, mach.rom.items);
        try std.testing.expectEqual(host_end, mach.stack.items.len);
        try std.testing.expectEqual(@as(usize, 1), mach.kstack.items.len);
    }
    try mach.popStack();
    try std.testing.expectEqual(@as(usize, 0), mach.stack.items.len);
    try std.testing.expectEqual(@as(usize, 0), mach.kstack.items.len);
}

test "all binary operations support aliased three byte registers" {
    var mach = try init(std.testing.allocator);
    defer mach.deinit();
    try mach.pushStack(&.{3});
    const Case = struct { instruction: Inst, expected: u24 };
    const operands: Inst.Lrd = .{ .l = 0, .r = 1, .d = 0 };
    for ([_]Case{
        .{ .instruction = .{ .add = operands }, .expected = 0x123456 + 4 },
        .{ .instruction = .{ .sub = operands }, .expected = 0x123456 - 4 },
        .{ .instruction = .{ .mul = operands }, .expected = 0x123456 * 4 },
        .{ .instruction = .{ .div = operands }, .expected = 0x123456 / 4 },
        .{ .instruction = .{ .mod = operands }, .expected = 0x123456 % 4 },
        .{ .instruction = .{ .cmp = operands }, .expected = 1 },
        .{ .instruction = .{ .band = operands }, .expected = 0x123456 & 4 },
        .{ .instruction = .{ .bor = operands }, .expected = 0x123456 | 4 },
        .{ .instruction = .{ .bxor = operands }, .expected = 0x123456 ^ 4 },
        .{ .instruction = .{ .shl = operands }, .expected = 0x234560 },
        .{ .instruction = .{ .shr = operands }, .expected = 0x012345 },
    }) |case| {
        const block = try mach.pushBlock(&.{
            .{ .tmp = .{3} },
            .{ .tmp = .{1} },
            .{ .read = try mach.readFromRom(0, @as(u24, 0x123456)) },
            .{ .read = try mach.readFromRom(1, @as(u8, 4)) },
            case.instruction,
            .{ .ret = 0 },
        });
        const end = try mach.extendStack(128);
        mach.stack.shrinkRetainingCapacity(end);
        try mach.kstack.ensureUnusedCapacity(mach.alloc, 1);
        {
            var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
            mach.alloc = failing.allocator();
            defer mach.alloc = std.testing.allocator;
            try mach.run(.{ .call = .{ .id = block, .d = 0 } });
            try std.testing.expect(!failing.has_induced_failure);
        }
        try std.testing.expectEqual(case.expected, std.mem.readInt(u24, (try mach.register(0, 0))[0..3], .little));
    }
}

test "division and remainder reconstruct a seventeen byte value" {
    var mach = try init(std.testing.allocator);
    defer mach.deinit();
    try mach.pushStack(&.{17});
    const value: u136 = (@as(u136, 1) << 128) + 5;
    const encoded = try mach.pushRom(value);
    const block = try mach.pushBlock(&.{
        .{ .tmp = .{17} },
        .{ .tmp = .{3} },
        .{ .tmp = .{17} },
        .{ .read = .{ .d = 0, .o = encoded, .s = 17 } },
        .{ .read = try mach.readFromRom(1, @as(u24, 3)) },
        .{ .mod = .{ .l = 0, .r = 1, .d = 2 } },
        .{ .div = .{ .l = 0, .r = 1, .d = 0 } },
        .{ .mul = .{ .l = 0, .r = 1, .d = 0 } },
        .{ .add = .{ .l = 0, .r = 2, .d = 0 } },
        .{ .ret = 0 },
    });
    try mach.run(.{ .call = .{ .id = block, .d = 0 } });
    try std.testing.expectEqualSlices(u8, mach.rom.items[encoded..][0..17], try mach.register(0, 0));
}

test "lea and unary operations do not allocate with reserved runtime storage" {
    var mach = try init(std.testing.allocator);
    defer mach.deinit();
    try mach.pushStack(&.{@sizeOf(usize)});
    const block = try mach.pushBlock(&.{
        .{ .tmp = .{@sizeOf(usize)} },
        .{ .lea = .{ .l = 0, .d = 0 } },
        .{ .nnot = .{ .l = 0, .d = 0 } },
        .{ .not = .{ .l = 0, .d = 0 } },
        .{ .bnot = .{ .l = 0, .d = 0 } },
        .{ .ret = 0 },
    });
    const end = try mach.extendStack(128);
    mach.stack.shrinkRetainingCapacity(end);
    try mach.kstack.ensureUnusedCapacity(mach.alloc, 1);
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    mach.alloc = failing.allocator();
    defer mach.alloc = std.testing.allocator;
    try mach.run(.{ .call = .{ .id = block, .d = 0 } });
    for (try mach.register(0, 0)) |byte| try std.testing.expectEqual(@as(u8, 255), byte);
    try std.testing.expect(!failing.has_induced_failure);
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var mach = try init(allocator);
    defer mach.deinit();
    try mach.pushStack(&.{3});
    const block = try mach.pushBlock(&.{
        .{ .tmp = .{3} },
        .{ .tmp = .{1} },
        .{ .read = try mach.readFromRom(0, @as(u24, 27)) },
        .{ .read = try mach.readFromRom(1, @as(u8, 3)) },
        .{ .div = .{ .l = 0, .r = 1, .d = 0 } },
        .{ .ret = 0 },
    });
    try mach.run(.{ .call = try mach.makeCall(block, 0, &.{0}) });
    try std.testing.expectEqualSlices(u8, &.{ 9, 0, 0 }, try mach.register(0, 0));
}

test "allocation failures leave no owned buffers or partial frames" {
    for (0..128) |fail_index| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = fail_index, .resize_fail_index = 0 });
        allocationScenario(failing.allocator()) catch |err| {
            if (err != error.OutOfMemory) return err;
        };
        try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        if (!failing.has_induced_failure) return;
    }
    return error.IncompleteAllocationCoverage;
}

test "invalid arguments and division by zero unwind without changing ROM" {
    var mach = try init(std.testing.allocator);
    defer mach.deinit();
    try mach.pushStack(&.{1});
    const invalid = try mach.pushBlock(&.{ .{ .tmp = .{1} }, .{ .arg = .{ .i = 0, .d = 0 } }, .{ .ret = 0 } });
    const zero = try mach.pushBlock(&.{
        .{ .tmp = .{1} },
        .{ .div = .{ .l = 0, .r = 0, .d = 0 } },
        .{ .ret = 0 },
    });
    const stackend = mach.stack.items.len;
    const romend = mach.rom.items.len;
    try std.testing.expectError(error.InvalidArgument, mach.run(.{ .call = .{ .id = invalid, .d = 0 } }));
    try std.testing.expectError(error.DivisionByZero, mach.run(.{ .call = .{ .id = zero, .d = 0 } }));
    try std.testing.expectEqual(stackend, mach.stack.items.len);
    try std.testing.expectEqual(romend, mach.rom.items.len);
    try std.testing.expectEqual(@as(usize, 1), mach.kstack.items.len);
}

test "VM owned function lists provide floating point extensions" {
    const Callbacks = struct {
        fn addFloat(args: []const []u8) !void {
            if (args.len != 3) return error.InvalidArguments;
            for (args) |value| if (value.len != 4) return error.InvalidArguments;
            const left: f32 = @bitCast(std.mem.readInt(u32, args[1][0..4], .little));
            const right: f32 = @bitCast(std.mem.readInt(u32, args[2][0..4], .little));
            std.mem.writeInt(u32, args[0][0..4], @bitCast(left + right), .little);
        }
    };
    for (0..2) |_| {
        var mach = try init(std.testing.allocator);
        defer mach.deinit();
        const id = try mach.registerExtension(Callbacks.addFloat);
        try mach.pushStack(&.{4});
        const block = try mach.pushBlock(&.{
            .{ .tmp = .{4} },
            .{ .tmp = .{4} },
            .{ .read = try mach.readFromRom(0, @as(u32, @bitCast(@as(f32, 1.5)))) },
            .{ .read = try mach.readFromRom(1, @as(u32, @bitCast(@as(f32, 2.25)))) },
            .{ .callEx = try mach.makeCallEx(id, &.{ 0, 0, 1 }) },
            .{ .ret = 0 },
        });
        const end = try mach.extendStack(256);
        mach.stack.shrinkRetainingCapacity(end);
        try mach.kstack.ensureUnusedCapacity(mach.alloc, 1);
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
        mach.alloc = failing.allocator();
        defer mach.alloc = std.testing.allocator;
        try mach.run(.{ .call = .{ .id = block, .d = 0 } });
        const actual: f32 = @bitCast(std.mem.readInt(u32, (try mach.register(0, 0))[0..4], .little));
        try std.testing.expectEqual(@as(f32, 3.75), actual);
        try std.testing.expect(!failing.has_induced_failure);
    }
}

test "builtin errors unwind and argument validation prevents invocation" {
    const Callbacks = struct {
        fn fail(_: []const []u8) !void {
            return error.ExtensionFailure;
        }
        fn noArguments(args: []const []u8) !void {
            try std.testing.expectEqual(@as(usize, 0), args.len);
        }
    };
    var mach = try init(std.testing.allocator);
    defer mach.deinit();
    const fail_id = try mach.registerExtension(Callbacks.fail);
    const empty_id = try mach.registerExtension(Callbacks.noArguments);
    try mach.pushStack(&.{1});
    const block = try mach.pushBlock(&.{
        .{ .tmp = .{1} },
        .{ .callEx = try mach.makeCallEx(fail_id, &.{0}) },
        .{ .ret = 0 },
    });
    const end = mach.stack.items.len;
    const rom_len = mach.rom.items.len;
    try std.testing.expectError(error.ExtensionFailure, mach.run(.{ .call = .{ .id = block, .d = 0 } }));
    try std.testing.expectEqual(end, mach.stack.items.len);
    try std.testing.expectEqual(@as(usize, 1), mach.kstack.items.len);
    try std.testing.expectEqual(rom_len, mach.rom.items.len);
    try std.testing.expectError(error.InvalidExtension, mach.run(.{ .callEx = .{ .id = 999 } }));
    try std.testing.expectError(error.InvalidRegister, mach.run(.{ .callEx = try mach.makeCallEx(fail_id, &.{99}) }));
    try std.testing.expectError(error.InvalidRom, mach.run(.{ .callEx = .{ .id = fail_id, .args = mach.rom.items.len, .argcount = 1 } }));
    try mach.run(.{ .callEx = try mach.makeCallEx(empty_id, &.{}) });
    var other = try init(std.testing.allocator);
    defer other.deinit();
    try other.pushStack(&.{1});
    try std.testing.expectError(error.InvalidExtension, other.run(.{ .callEx = .{ .id = empty_id } }));
}
