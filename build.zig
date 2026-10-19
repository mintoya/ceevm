const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const bitints = b.addTranslateC(.{
        .root_source_file = b.path("bitint.h"),
        .target = target,
        .optimize = optimize,
    }).createModule();
    bitints.addCSourceFile(.{ .file = b.path("bitint.c"), .flags = &.{"-std=c99"} });
    const mod = b.addModule("ceevm", .{
        .root_source_file = b.path("src/vm.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "bitint", .module = bitints }},
    });

    const exe = b.addExecutable(.{
        .name = "ceevm",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ceevm", .module = mod },
                .{ .name = "bitint", .module = bitints },
            },
        }),
    });
    b.installArtifact(exe);

    const exe_check = b.addExecutable(.{
        .name = "ceevm",
        .root_module = exe.root_module,
    });
    const check_step = b.step("check", "Check compilation for ZLS");
    check_step.dependOn(&exe_check.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.addPassthruArgs();
    const run_step = b.step("run", "Run the recursion example");
    run_step.dependOn(&run_cmd.step);

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run VM tests");
    test_step.dependOn(&run_tests.step);
}
