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

    const collatz = try mach.makeBlock([_]Vm.Inst{
        .{ .tmp = bitsof(u32) + bitsof(u32) }, //   0:0
        .{ .arg = 0 }, //                            :1
        .{ .tmp = bitsof(u32) }, //                 1:2
        .{ .tmp = bitsof(u32) }, //                 2:3
        .{ .dcons = try mach.makeCons(0, [_]Reg{ 1, 2 }) }, //:4
        .{ .tmp = bitsof(u32) }, //                 3:5
        .{ .tmp = bitsof(u32) }, //                 4:6
        .{ .tmp = bitsof(u32) }, //                 5:7
        .{ .rom = try mach.makeRom(3, @as(u32, 1)) }, //:8
        .{ .rom = try mach.makeRom(4, @as(u32, 2)) }, //:9
        .{ .rom = try mach.makeRom(5, @as(u32, 3)) }, //:10
        .{ .tmp = bitsof(u32) }, //                 6:11
        .{ .cmp = .{ .l = 2, .r = 3, .d = 6 } }, //  :12
        .{ .jmp3 = .{ .r = 6, .@">" = 14, .@"<" = 14, .@"=" = 23 } }, //:13
        .{ .mod = .{ .l = 2, .r = 4, .d = 6 } }, //  :14
        .{ .cmp = .{ .l = 6, .r = 3, .d = 6 } }, //  :15
        .{ .jmp3 = .{ .r = 6, .@">" = 17, .@"<" = 17, .@"=" = 19 } }, //                                      :16
        .{ .shr = .{ .l = 2, .r = 3, .d = 2 } }, //  :17
        .{ .jmp3 = .{ .@">" = 21 } }, //              :18
        .{ .mul = .{ .l = 2, .r = 5, .d = 2 } }, //  :19
        .{ .add = .{ .l = 2, .r = 3, .d = 2 } }, //  :20
        .{ .add = .{ .l = 1, .r = 3, .d = 1 } }, //  :21
        .{ .jmp3 = .{ .@">" = 12 } }, //              :22
        .{ .cons = try mach.makeCons(0, [_]Reg{ 1, 2 }) }, //:23
        .{ .ret = 0 }, //                            :24
    });
    _ = collatz;
}
