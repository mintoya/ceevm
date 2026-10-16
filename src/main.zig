const std = @import("std");
const vm = @import("ceevm");
fn println(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt ++ "\n", args);
}

pub fn main(init: std.process.Init) !void {
    var mach = try vm.init(init.gpa);
    defer mach.deinit();

    _ = try mach.pushBlock(&.{
        .{ .tmp = .{@sizeOf(u32)} },
        .{ .read = try mach.readFromRom(0, @as(u32, 2)) },
        .{ .ret = 0 },
    });
}
