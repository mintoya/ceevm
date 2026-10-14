# ceevm

A byte-backed VM Zig 0.17.0 written for th3 ceeshel language


```zig
var mach = try vm.init(allocator);
defer mach.deinit();
const block = try mach.pushBlock(&.{ .{ .tmp = .{1} }, .{ .ret = 0 } });
try mach.pushStack(&.{1});
try mach.run(.{ .call = .{ .id = block, .d = 0 } });
```

