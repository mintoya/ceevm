const std = @import("std");
const vm = @import("ceevm");
fn println(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt ++ "\n", args);
}
pub fn main(init: std.process.Init) !void {
    var mach = try vm.init(init.gpa);
    defer mach.deinit();

    const recurse = try mach.pushBlock(&.{
        .{ .tmp = .{@sizeOf(u32)} },
        .{ .tmp = .{1} },
        .{ .tmp = .{1} },
        .{ .arg = .{ .i = 0, .d = 0 } },
        .{ .nnot = .{ .l = 0, .d = 2 } },
        .{ .jmp3 = .{ .r = 2, .more = 6, .less = 9, .equal = 9 } },
        .{ .read = try mach.readFromRom(1, @as(u8, 1)) },
        .{ .sub = .{ .l = 0, .r = 1, .d = 0 } },
        .{ .call = try mach.makeCall(0, 0, &.{0}) },
        .{ .ret = 0 },
    });
    const entry = try mach.pushBlock(&.{
        .{ .tmp = .{@sizeOf(u32)} },
        .{ .read = try mach.readFromRom(0, @as(u32, 5_000_000)) },
        .{ .call = try mach.makeCall(recurse, 0, &.{0}) },
        .{ .ret = 0 },
    });
    try mach.pushStack(&.{@sizeOf(u32)});
    try mach.run(.{ .call = .{ .id = entry, .d = 0 } });
    println("{x}", .{try mach.register(0, 0)});
}
