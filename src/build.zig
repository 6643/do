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

    const toolchain_module = b.createModule(.{
        .root_source_file = b.path("build/toolchain_cli.zig"),
        .target = target,
        .optimize = optimize,
    });
    const toolchain_exe = b.addExecutable(.{
        .name = "do-toolchain",
        .root_module = toolchain_module,
    });
    b.installArtifact(toolchain_exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run do toolchain");
    run_step.dependOn(&run_cmd.step);

    const process_test_module = b.createModule(.{
        .root_source_file = b.path("build/test/process.zig"),
        .target = target,
        .optimize = optimize,
    });
    const process_tests = b.addTest(.{
        .name = "process-tests",
        .root_module = process_test_module,
    });
    const run_process_tests = b.addRunArtifact(process_tests);

    const structural_test_module = b.createModule(.{
        .root_source_file = b.path("build/test/structural_checks_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const structural_tests = b.addTest(.{
        .name = "structural-check-tests",
        .root_module = structural_test_module,
    });
    const run_structural_tests = b.addRunArtifact(structural_tests);

    const toolchain_test_module = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const toolchain_tests = b.addTest(.{
        .name = "toolchain-tests",
        .root_module = toolchain_test_module,
        .filters = &.{"toolchain"},
    });
    const run_toolchain_tests = b.addRunArtifact(toolchain_tests);

    const harness_module = b.createModule(.{
        .root_source_file = b.path("build/test/test_harness.zig"),
        .target = target,
        .optimize = optimize,
    });
    const harness_exe = b.addExecutable(.{
        .name = "do-integration-harness",
        .root_module = harness_module,
    });
    const run_harness = b.addRunArtifact(harness_exe);
    run_harness.setEnvironmentVariable("DO_HARNESS_REPO_ROOT", b.pathFromRoot(".."));
    run_harness.setEnvironmentVariable("DO_HARNESS_DO_BIN", b.getInstallPath(.bin, "do"));
    run_harness.setEnvironmentVariable("DO_HARNESS_TOOLCHAIN_BIN", b.getInstallPath(.bin, "do-toolchain"));
    run_harness.setEnvironmentVariable("DO_TOOLCHAIN_LOCK", b.pathFromRoot("../toolchain/toolchain.lock.json"));
    run_harness.setCwd(b.path(".."));
    run_harness.step.dependOn(b.getInstallStep());

    const test_step = b.step("test", "Run compiler and integration regression tests");
    test_step.dependOn(&run_process_tests.step);
    test_step.dependOn(&run_structural_tests.step);
    test_step.dependOn(&run_toolchain_tests.step);
    test_step.dependOn(&run_harness.step);
}
