const std = @import("std");
const ceevm = @import("ceevm");

fn println(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt ++ "\n", args);
}
const vm = @import("vm.zig");
pub fn main(init: std.process.Init) !void {
    var mach = try vm.init(init.gpa);
    defer mach.deinit(init.gpa);

    //main:
    //  %1 = lit 0 4
    //  %2 = lit 4 4
    //  add %1 %2 %1
    //  ret %1
    try mach.pushRom(init.gpa, @as(u32, 5));
    try mach.pushRom(init.gpa, @as(u32, 3));

    const b = try mach.pushBlock(init.gpa, &[_]vm.Inst{
        .{ .lit = .{ .s = 4, .o = 0 } },
        .{ .lit = .{ .s = 4, .o = 4 } },
        .{ .add = .{ .l = 0, .r = 1, .d = 0 } },
    });

    try mach.execBlock(init.gpa, b);
    println("{x}", .{mach.Stack.items});
}
