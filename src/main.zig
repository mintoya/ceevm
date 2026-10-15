const std = @import("std");
const vm = @import("ceevm");
fn println(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt ++ "\n", args);
}
// Float representation and arithmetic belong to this extension, not the VM.
const FloatMath = struct {
    const Op = enum(u8) { add, sub, mul, div };

    // Arguments: operation byte, output f64, left f64, right f64.
    fn call(args: []const []u8) !void {
        if (args.len != 4 or args[0].len != 1) return error.InvalidFloatArguments;
        for (args[1..]) |arg| {
            if (arg.len != @sizeOf(f64)) return error.InvalidFloatArguments;
        }
        if (args[0][0] > @backingInt(Op.div)) return error.InvalidFloatOperation;
        const op: Op = @fromBackingInt(@intCast(args[0][0]));
        const left = number(args[2]);
        const right = number(args[3]);
        const result = switch (op) {
            .add => left + right,
            .sub => left - right,
            .mul => left * right,
            .div => left / right,
        };
        std.mem.writeInt(u64, args[1][0..8], @bitCast(result), .little);
    }

    fn number(bytes: []const u8) f64 {
        return @bitCast(std.mem.readInt(u64, bytes[0..8], .little));
    }
};

fn floatExample(mach: *vm.Mach) !void {
    const float_math = try mach.registerExtension(FloatMath.call);
    const block = try mach.pushBlock(&.{
        .{ .tmp = .{8} }, // accumulator
        .{ .tmp = .{8} }, // right operand
        .{ .tmp = .{1} }, // operation
        .{ .read = try mach.readFromRom(0, @as(u64, @bitCast(@as(f64, 1.5)))) },
        .{ .read = try mach.readFromRom(1, @as(u64, @bitCast(@as(f64, 2.25)))) },
        .{ .read = try mach.readFromRom(2, @backingInt(FloatMath.Op.add)) },
        .{ .callEx = try mach.makeCallEx(float_math, &.{ 2, 0, 0, 1 }) },
        .{ .read = try mach.readFromRom(1, @as(u64, @bitCast(@as(f64, 4.0)))) },
        .{ .read = try mach.readFromRom(2, @backingInt(FloatMath.Op.mul)) },
        .{ .callEx = try mach.makeCallEx(float_math, &.{ 2, 0, 0, 1 }) },
        .{ .read = try mach.readFromRom(1, @as(u64, @bitCast(@as(f64, 5.0)))) },
        .{ .read = try mach.readFromRom(2, @backingInt(FloatMath.Op.sub)) },
        .{ .callEx = try mach.makeCallEx(float_math, &.{ 2, 0, 0, 1 }) },
        .{ .read = try mach.readFromRom(1, @as(u64, @bitCast(@as(f64, 2.0)))) },
        .{ .read = try mach.readFromRom(2, @backingInt(FloatMath.Op.div)) },
        .{ .callEx = try mach.makeCallEx(float_math, &.{ 2, 0, 0, 1 }) },
        .{ .ret = 0 },
    });
    try mach.pushStack(&.{8});
    defer mach.popStack() catch unreachable;
    try mach.run(.{ .call = .{ .id = block, .d = 0 } });
    const result = FloatMath.number(try mach.register(0, 0));
    println("float extension: ((1.5 + 2.25) * 4 - 5) / 2 = {d}", .{result});
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
    try mach.popStack();

    try floatExample(&mach);
}
