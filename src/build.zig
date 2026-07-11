const std = @import("std");

pub fn build(b: *std.Build) void {
    b.resolveInstallPrefix(b.pathFromRoot(".."), .{
        .exe_dir = "bin",
    });

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const root_module = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "do",
        .root_module = root_module,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run do toolchain");
    run_step.dependOn(&run_cmd.step);
}
