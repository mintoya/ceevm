const std = @import("std");
pub const Reg = u32;

Rom: std.ArrayList(u8),
Stack: std.ArrayList(u8),
BlockMem: std.ArrayList(Inst),
Blocks: std.ArrayList(struct {
    offset: u32,
    len: u32,
    offsets: []struct {
        offset: u32,
        len: u32,
    },
}),

pub const Inst = union(enum) {
    // l: left , r: right , d:dest
    pub const Lrd = struct { l: Reg, r: Reg, d: Reg };
    pub const Rd = struct { r: Reg, d: Reg };
    lit: struct { s: u32, o: u32 }, // create literal of size s from offset inside of Rom
    ptr: Rd, // get pointer to r and place it in d
    cpy: Rd, // copy r into d, both pointers
    mov: Rd, // copy r into d

    add: Lrd,
    sub: Lrd,
    mul: Lrd,
    div: Lrd,

    tru: Rd, // equivalent of !!

    band: Lrd,
    bor: Lrd,
    bxor: Lrd,

    jmp: ?u32,
};
pub fn init(alloc: std.mem.Allocator) !@This() {
    var r: @This() = undefined;
    r.Blocks = try .initCapacity(alloc, 8);
    r.BlockMem = try .initCapacity(alloc, 8);
    r.Rom = try .initCapacity(alloc, 8);
    r.Stack = try .initCapacity(alloc, 8);
    return r;
}
pub fn deinit(this: *@This(), alloc: std.mem.Allocator) void {
    for (this.Blocks.items) |b|
        if (b.offsets.len > 0) alloc.free(b.offsets);
    this.Blocks.deinit(alloc);
    this.BlockMem.deinit(alloc);
    this.Rom.deinit(alloc);
    this.Stack.deinit(alloc);
}
pub fn pushRom(this: *@This(), alloc: std.mem.Allocator, data: anytype) !void {
    var mem: [@sizeOf(@TypeOf(data))]u8 = undefined;
    @memcpy(&mem, @as(@TypeOf(&mem), @ptrCast(@constCast(&data))));
    try this.Rom.appendSlice(alloc, &mem);
}
pub fn pushBlock(this: *@This(), alloc: std.mem.Allocator, insts: []const Inst) !u32 {
    const Ref = @typeInfo(@TypeOf(@as(@This(), undefined).Blocks.items)).pointer.child;
    const Slot = @typeInfo(@TypeOf(@as(Ref, undefined).offsets)).pointer.child;

    var regs: std.ArrayList(Slot) = try .initCapacity(alloc, 8);
    defer regs.deinit(alloc);
    var cur: u32 = 0;
    for (insts) |inst| switch (inst) {
        .lit => |l| {
            try regs.append(alloc, .{ .offset = cur, .len = l.s });
            cur += l.s;
        },
        else => {},
    };

    try this.BlockMem.appendSlice(alloc, insts);
    try this.Blocks.append(alloc, .{
        .offset = @intCast(this.BlockMem.items.len - insts.len),
        .len = @intCast(insts.len),
        .offsets = try regs.toOwnedSlice(alloc),
    });
    return @intCast(this.Blocks.items.len - 1);
}
pub fn execBlock(this: *@This(), alloc: std.mem.Allocator, i: u32) !void {
    const l = this.Blocks.items[i].offsets[this.Blocks.items[i].offsets.len - 1];
    try this.Stack.appendNTimes(alloc, 0, l.len + l.offset);
}
