const std = @import("std");
const Vm = @import("ceevm");
fn sizeof(comptime t: type) usize {
    return @sizeOf(t);
}
fn bitsof(comptime t: type) usize {
    return @bitSizeOf(t);
}
fn typeof(a: anytype) type {
    return @TypeOf(a);
}
fn println(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt ++ "\n", args);
}
const Reg = Vm.Reg;
pub fn main(init: std.process.Init) !void {
    var mach = try Vm.init(init.gpa);
    defer mach.deinit();

    const collatz_id: Vm.FnId = @intCast(mach.blocks.items.len);
    const collatz = try mach.makeBlock([_]Vm.Inst{
        .{ .tmp = 32 + 32 }, //   0:0
        .{ .arg = 0 }, //                            :1
        .{ .tmp = 32 }, //                 1:2
        .{ .tmp = 32 }, //                 2:3
        .{ .dcons = try mach.makeCons(0, [_]Reg{ 1, 2 }) }, //:4
        .{ .tmp = 32 }, //                 3:5
        .{ .tmp = 32 }, //                 4:6
        .{ .tmp = 32 }, //                 5:7
        .{ .rom = try mach.makeRom(3, @as(u32, 1)) }, //:8
        .{ .rom = try mach.makeRom(4, @as(u32, 2)) }, //:9
        .{ .rom = try mach.makeRom(5, @as(u32, 3)) }, //:10
        .{ .tmp = 32 }, //                 6:11
        .{ .cmp = .{ .l = 2, .r = 3, .d = 6 } }, //  :12
        .{ .jmp3 = .{ .r = 6, .@">" = 14, .@"<" = 14, .@"=" = 25 } }, //:13
        .{ .mod = .{ .l = 2, .r = 4, .d = 6 } }, //  :14
        .{ .cmp = .{ .l = 6, .r = 3, .d = 6 } }, //  :15
        .{ .jmp3 = .{ .r = 6, .@">" = 17, .@"<" = 17, .@"=" = 19 } }, //:16
        .{ .shr = .{ .l = 2, .r = 3, .d = 2 } }, //  :17
        .{ .jmp3 = .unconditional(21) }, //          :18
        .{ .mul = .{ .l = 2, .r = 5, .d = 2 } }, //  :19
        .{ .add = .{ .l = 2, .r = 3, .d = 2 } }, //  :20
        .{ .add = .{ .l = 1, .r = 3, .d = 1 } }, //  :21
        .{ .cons = try mach.makeCons(0, [_]Reg{ 1, 2 }) }, //:22
        .{ .call = .{ .id = collatz_id, .arg = 0, .d = 0 } }, //:23
        .{ .ret = 0 }, //                              :24
        .{ .cons = try mach.makeCons(0, [_]Reg{ 1, 2 }) }, //:25
        .{ .ret = 0 }, //                              :26
    });
    const print_result = try mach.makeExtension(struct {
        fn f(arg: Vm.CSlice, _: Vm.CSlice) callconv(.c) void {
            const bytes = arg.ptr[0..arg.len];
            var result: [2]u32 = undefined;
            @memcpy(std.mem.asBytes(&result), bytes);
            println("Collatz(27): {d} steps, final value {d}", .{ result[0], result[1] });
        }
    }.f);
    try mach.run(.{ .tmp = bitsof([2]u32) });
    try mach.run(.{ .rom = try mach.makeRom(0, [2]u32{ 0, 27 }) });
    try mach.run(.{ .tmp = bitsof([2]u32) });
    try mach.run(.{ .call = .{ .id = collatz, .arg = 0, .d = 1 } });
    try mach.run(.{ .calx = .{ .id = print_result, .arg = 1 } });
}
