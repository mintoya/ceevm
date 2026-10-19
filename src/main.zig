const std = @import("std");
const Vm = @import("ceevm");
fn println(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt ++ "\n", args);
}
pub fn main(init: std.process.Init) !void {
    var mach = try Vm.init(init.gpa);
    defer mach.deinit();
    const insts = [_]Vm.Inst{
        .{ .tmp = @sizeOf(u32) },
        .{ .rom = try mach.makeRom(0, @as(u32, 67)) },

        .{ .tmp = @sizeOf(u32) },
        .{ .arg = 1 },

        .{ .add = .{ .d = 0, .l = 0, .r = 1 } },
        .{ .ret = 0 },
    };
    _ = try mach.makeCons(0, [_]Vm.Reg{});
    println("{x}", .{mach.rom.items});
    println("{any}", .{insts});
}
