const std = @import("std");

fn at(bytes: []const u8, i: usize) u8 {
    return if (i < bytes.len) bytes[i] else 0;
}
fn isZero(bytes: []const u8) bool {
    for (bytes) |byte| if (byte != 0) return false;
    return true;
}
pub fn copy(dest: []u8, source: []const u8) void {
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
pub fn add(dest: []u8, left: []const u8, right: []const u8) void {
    var carry: u16 = 0;
    for (dest, 0..) |*byte, i| {
        const sum = @as(u16, at(left, i)) + at(right, i) + carry;
        byte.* = @truncate(sum);
        carry = sum >> 8;
    }
}
pub fn sub(dest: []u8, left: []const u8, right: []const u8) void {
    var borrow: u16 = 0;
    for (dest, 0..) |*byte, i| {
        const l: u16 = at(left, i);
        const r = @as(u16, at(right, i)) + borrow;
        byte.* = @truncate(l + 256 - r);
        borrow = @intFromBool(l < r);
    }
}
pub fn mul(dest: []u8, left: []const u8, right: []const u8) void {
    @memset(dest, 0);
    for (left[0..@min(left.len, dest.len)], 0..) |l, i| {
        var carry: u16 = 0;
        for (0..dest.len - i) |j| {
            const product = @as(u16, l) * at(right, j) + dest[i + j] + carry;
            dest[i + j] = @truncate(product);
            carry = product >> 8;
        }
    }
}
fn divide(dest: []u8, left: []const u8, right: []const u8, remainder: []u8, comptime modulo: bool) !void {
    if (isZero(right)) return error.DivisionByZero;
    @memset(dest, 0);
    @memset(remainder, 0);
    var byte_index = left.len;
    while (byte_index > 0) {
        byte_index -= 1;
        var bit: usize = 8;
        while (bit > 0) {
            bit -= 1;
            var carry: u16 = (left[byte_index] >> @as(u3, @intCast(bit))) & 1;
            for (remainder) |*byte| {
                const value = (@as(u16, byte.*) << 1) | carry;
                byte.* = @truncate(value);
                carry = value >> 8;
            }
            if (compare(remainder, right) != .lt) {
                sub(remainder, remainder, right);
                if (!modulo and byte_index < dest.len)
                    dest[byte_index] |= @as(u8, 1) << @as(u3, @intCast(bit));
            }
        }
    }
    if (modulo) copy(dest, remainder);
}
pub fn div(dest: []u8, left: []const u8, right: []const u8, remainder: []u8) !void {
    try divide(dest, left, right, remainder, false);
}
pub fn mod(dest: []u8, left: []const u8, right: []const u8, remainder: []u8) !void {
    try divide(dest, left, right, remainder, true);
}
pub fn cmp(dest: []u8, left: []const u8, right: []const u8) void {
    @memset(dest, 0);
    dest[0] = switch (compare(left, right)) {
        .lt => 0xff,
        .eq => 0,
        .gt => 1,
    };
}
pub fn not(dest: []u8, source: []const u8) void {
    const value = isZero(source);
    @memset(dest, 0);
    dest[0] = @intFromBool(value);
}
pub fn nnot(dest: []u8, source: []const u8) void {
    const value = !isZero(source);
    @memset(dest, 0);
    dest[0] = @intFromBool(value);
}
pub fn bnot(dest: []u8, source: []const u8) void {
    for (dest, 0..) |*byte, i| byte.* = ~at(source, i);
}
pub fn band(dest: []u8, left: []const u8, right: []const u8) void {
    for (dest, 0..) |*byte, i| byte.* = at(left, i) & at(right, i);
}
pub fn bor(dest: []u8, left: []const u8, right: []const u8) void {
    for (dest, 0..) |*byte, i| byte.* = at(left, i) | at(right, i);
}
pub fn bxor(dest: []u8, left: []const u8, right: []const u8) void {
    for (dest, 0..) |*byte, i| byte.* = at(left, i) ^ at(right, i);
}
fn shift(dest: []u8, left: []const u8, right: []const u8, comptime towards_left: bool) void {
    @memset(dest, 0);
    var count: usize = 0;
    var i = right.len;
    while (i > 0) {
        i -= 1;
        count = std.math.mul(usize, count, 256) catch return;
        count = std.math.add(usize, count, right[i]) catch return;
    }
    const bytes = count / 8;
    const bits: u3 = @intCast(count % 8);
    for (dest, 0..) |*byte, d| {
        if (towards_left) {
            if (d < bytes) continue;
            const source = d - bytes;
            var value = @as(u16, at(left, source)) << bits;
            if (bits != 0 and source != 0)
                value |= @as(u16, at(left, source - 1)) >> @as(u4, @intCast(8 - @as(u8, bits)));
            byte.* = @truncate(value);
        } else {
            const source = std.math.add(usize, d, bytes) catch continue;
            var value = @as(u16, at(left, source)) >> bits;
            if (bits != 0 and source < left.len)
                value |= @as(u16, at(left, source + 1)) << @as(u4, @intCast(8 - @as(u8, bits)));
            byte.* = @truncate(value);
        }
    }
}
pub fn shl(dest: []u8, left: []const u8, right: []const u8) void {
    shift(dest, left, right, true);
}
pub fn shr(dest: []u8, left: []const u8, right: []const u8) void {
    shift(dest, left, right, false);
}
