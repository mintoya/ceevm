const std = @import("std");
pub fn SgList(T: type) type {
    return struct {
        const Self = @This();

        pub const empty: Self = .{};

        len: usize = 0,
        arrays: [30]?[*]T = @splat(null),

        fn idx1(i: usize) usize {
            return std.math.log2_int(usize, i + 8) - 3;
        }

        fn sectionLen(section: usize) usize {
            return @as(usize, 1) << @intCast(section + 3);
        }

        fn idx2(i: usize) usize {
            return i - (sectionLen(idx1(i)) - 8);
        }

        pub fn get(self: *Self, index: usize) *T {
            std.debug.assert(index < self.len);
            return &self.arrays[idx1(index)].?[idx2(index)];
        }

        pub fn getConst(self: *const Self, index: usize) *const T {
            std.debug.assert(index < self.len);
            return &self.arrays[idx1(index)].?[idx2(index)];
        }

        pub fn push(self: *Self, allocator: std.mem.Allocator, value: T) std.mem.Allocator.Error!void {
            if (self.len > std.math.maxInt(usize) - 8) return error.OutOfMemory;
            const section = idx1(self.len);
            if (section >= self.arrays.len or section + 3 >= @bitSizeOf(usize))
                return error.OutOfMemory;
            if (self.arrays[section] == null) {
                const items = try allocator.alloc(T, sectionLen(section));
                self.arrays[section] = items.ptr;
            }
            self.arrays[section].?[idx2(self.len)] = value;
            self.len += 1;
        }
        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            for (&self.arrays, 0..) |*array, section| {
                const ptr = array.* orelse break;
                allocator.free(ptr[0..sectionLen(section)]);
                array.* = null;
            }
            self.len = 0;
        }
    };
}

test "segment boundaries, stable pointers, and retained segments" {
    var list = SgList(usize).empty;
    defer list.deinit(std.testing.allocator);

    try list.push(std.testing.allocator, 0);
    const first = list.get(0);
    for (1..128) |i| try list.push(std.testing.allocator, i);
    try std.testing.expect(first == list.get(0));
    const read_only: *const SgList(usize) = &list;
    for (0..128) |i| try std.testing.expectEqual(i, read_only.getConst(i).*);
    for ([_]usize{ 0, 8, 24, 56, 120 }, 0..) |start, section| {
        try std.testing.expect(list.get(start) == &list.arrays[section].?[0]);
    }
    first.* = 42;
    try std.testing.expectEqual(@as(usize, 42), list.get(0).*);

    const second_segment = list.arrays[1].?;
    list.len = 8;
    try list.push(std.testing.allocator, 99);
    try std.testing.expect(second_segment == list.arrays[1].?);
    try std.testing.expectEqual(@as(usize, 99), list.get(8).*);

    list.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), list.len);
    for (list.arrays) |array| try std.testing.expect(array == null);
    try list.push(std.testing.allocator, 7);
    try std.testing.expectEqual(@as(usize, 7), list.get(0).*);
}

test "failed growth preserves existing elements" {
    var buffer: [8]u64 = undefined;
    var allocator = std.heap.FixedBufferAllocator.init(std.mem.sliceAsBytes(&buffer));
    var list = SgList(u64).empty;
    defer list.deinit(allocator.allocator());

    for (0..8) |i| try list.push(allocator.allocator(), i);
    const first = list.get(0);
    try std.testing.expectError(error.OutOfMemory, list.push(allocator.allocator(), 8));
    try std.testing.expectEqual(@as(usize, 8), list.len);
    try std.testing.expect(list.arrays[1] == null);
    try std.testing.expect(first == list.get(0));
    for (0..8) |i| try std.testing.expectEqual(@as(u64, i), list.get(i).*);
}
