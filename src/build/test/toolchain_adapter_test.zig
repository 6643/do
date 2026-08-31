const std = @import("std");
const toolchain = @import("../toolchain.zig");

test "toolchain adapter rejects identity drift before running a command" {
    const spec = toolchain.ToolSpec{
        .name = "wasm-tools",
        .path = "/bin/wasm-tools",
        .version = "wasm-tools 1.258.0 (5c6d31c78 2026-08-24)",
        .sha256 = "282e0014d38daf233cb10fb92815813b339e2b7f8b4734f6698f0176c7d99424",
        .capabilities = &.{ "parse-core", "embed-component" },
    };

    try std.testing.expectError(
        error.VersionMismatch,
        toolchain.validate_identity(spec, "wasm-tools 1.257.0", spec.sha256),
    );
    try std.testing.expectError(
        error.HashMismatch,
        toolchain.validate_identity(spec, spec.version, "deadbeef"),
    );
    try toolchain.validate_identity(spec, spec.version, spec.sha256);
    try std.testing.expectError(
        error.CapabilityMissing,
        toolchain.require_capability(spec, "run-wasmtime"),
    );
}

test "toolchain adapter builds only typed operation arguments" {
    const argv = try toolchain.build_argv(std.testing.allocator, .parse_core, .{
        .parse_core = .{ .input = "input.wat", .output = "output.wasm" },
    });
    defer toolchain.free_argv(std.testing.allocator, argv);

    try std.testing.expectEqualStrings("parse", argv[0]);
    try std.testing.expectEqualStrings("input.wat", argv[1]);
    try std.testing.expectEqualStrings("-o", argv[2]);
    try std.testing.expectEqualStrings("output.wasm", argv[3]);
}

test "toolchain adapter builds current core stripping arguments" {
    const argv = try toolchain.build_argv(std.testing.allocator, .strip_core, .{
        .strip_core = .{ .input = "input.wasm", .output = "output.wasm" },
    });
    defer toolchain.free_argv(std.testing.allocator, argv);

    const expected = [_][]const u8{ "strip", "-a", "input.wasm", "-o", "output.wasm" };
    try std.testing.expectEqual(expected.len, argv.len);
    for (expected, 0..) |value, index| {
        try std.testing.expectEqualStrings(value, argv[index]);
    }
}

test "toolchain adapter builds current core validation arguments" {
    const argv = try toolchain.build_argv(std.testing.allocator, .validate_core, .{
        .validate_core = .{ .wasm = "module.wasm" },
    });
    defer toolchain.free_argv(std.testing.allocator, argv);

    try std.testing.expectEqualStrings("validate", argv[0]);
    try std.testing.expectEqualStrings("--features", argv[1]);
    try std.testing.expectEqualStrings("gc,cm-async,cm-more-async-builtins", argv[2]);
    try std.testing.expectEqualStrings("module.wasm", argv[3]);
}

test "toolchain adapter builds current GC core compile arguments" {
    const argv = try toolchain.build_argv(std.testing.allocator, .compile_core_gc, .{
        .compile_core_gc = .{ .input = "module.wat", .output = "module.compiled" },
    });
    defer toolchain.free_argv(std.testing.allocator, argv);

    const expected = [_][]const u8{ "compile", "-W", "gc=y", "-o", "module.compiled", "module.wat" };
    try std.testing.expectEqual(expected.len, argv.len);
    for (expected, 0..) |value, index| try std.testing.expectEqualStrings(value, argv[index]);
}

test "toolchain adapter builds current GC core invoke arguments" {
    const argv = try toolchain.build_argv(std.testing.allocator, .invoke_core_gc, .{
        .invoke_core_gc = .{ .module = "module.wat", .export_name = "probe" },
    });
    defer toolchain.free_argv(std.testing.allocator, argv);

    const expected = [_][]const u8{ "-W", "gc=y", "--invoke", "probe", "module.wat" };
    try std.testing.expectEqual(expected.len, argv.len);
    for (expected, 0..) |value, index| try std.testing.expectEqualStrings(value, argv[index]);
}

test "toolchain adapter preserves an explicit empty component feature profile" {
    const argv = try toolchain.build_argv(std.testing.allocator, .embed_component, .{
        .embed_component = .{
            .wit = "interface.wit",
            .core_wasm = "module.wasm",
            .world = "probe",
            .output = "embedded.wasm",
            .features = .none,
        },
    });
    defer toolchain.free_argv(std.testing.allocator, argv);

    try std.testing.expectEqual(@as(usize, 8), argv.len);
    try std.testing.expectEqualStrings("component", argv[0]);
    try std.testing.expectEqualStrings("embed", argv[1]);
    try std.testing.expectEqualStrings("interface.wit", argv[2]);
    try std.testing.expectEqualStrings("module.wasm", argv[3]);
    try std.testing.expectEqualStrings("--world", argv[4]);
    try std.testing.expectEqualStrings("probe", argv[5]);
    try std.testing.expectEqualStrings("-o", argv[6]);
    try std.testing.expectEqualStrings("embedded.wasm", argv[7]);
}

test "toolchain adapter builds the current async metadata probe arguments" {
    const argv = try toolchain.build_argv(std.testing.allocator, .embed_component_template, .{
        .embed_component_template = .{
            .wit = "interface.wit",
            .world = "probe",
            .features = .component_async,
        },
    });
    defer toolchain.free_argv(std.testing.allocator, argv);

    const expected = [_][]const u8{
        "component", "embed", "interface.wit", "--world", "probe",
        "--dummy-names", "legacy", "--async-callback", "--features",
        "cm-async,cm-more-async-builtins", "-t",
    };
    try std.testing.expectEqual(expected.len, argv.len);
    for (expected, 0..) |value, index| {
        try std.testing.expectEqualStrings(value, argv[index]);
    }
}

test "toolchain adapter keeps component async as the default feature profile" {
    const argv = try toolchain.build_argv(std.testing.allocator, .validate_component, .{
        .validate_component = .{ .component = "component.wasm" },
    });
    defer toolchain.free_argv(std.testing.allocator, argv);

    try std.testing.expectEqual(@as(usize, 4), argv.len);
    try std.testing.expectEqualStrings("validate", argv[0]);
    try std.testing.expectEqualStrings("--features", argv[1]);
    try std.testing.expectEqualStrings("cm-async,cm-more-async-builtins", argv[2]);
    try std.testing.expectEqualStrings("component.wasm", argv[3]);
}

test "toolchain adapter maps the core GC async profile to current feature flags" {
    const argv = try toolchain.build_argv(std.testing.allocator, .validate_component, .{
        .validate_component = .{
            .component = "component.wasm",
            .features = .core_gc_async,
        },
    });
    defer toolchain.free_argv(std.testing.allocator, argv);

    try std.testing.expectEqual(@as(usize, 4), argv.len);
    try std.testing.expectEqualStrings("validate", argv[0]);
    try std.testing.expectEqualStrings("--features", argv[1]);
    try std.testing.expectEqualStrings("gc,cm-async,cm-more-async-builtins", argv[2]);
    try std.testing.expectEqualStrings("component.wasm", argv[3]);
}

test "toolchain adapter feature profiles reject arbitrary feature strings" {
    try std.testing.expectEqual(toolchain.FeatureProfile.none, try toolchain.parse_feature_profile("none"));
    try std.testing.expectEqual(toolchain.FeatureProfile.component_async, try toolchain.parse_feature_profile("component-async"));
    try std.testing.expectEqual(toolchain.FeatureProfile.core_gc_async, try toolchain.parse_feature_profile("core-gc-async"));
    try std.testing.expectError(error.InvalidFeatureProfile, toolchain.parse_feature_profile("gc,custom"));
}

test "toolchain lock records current CLI identities and verified Rust crate upgrade" {
    var lock = try toolchain.load_lock(
        std.testing.allocator,
        std.testing.io,
        "../toolchain/toolchain.lock.json",
    );
    defer lock.deinit();

    try std.testing.expectEqual(@as(u32, 1), lock.value.schema);
    try std.testing.expectEqualStrings("wasm-tools 1.258.0 (5c6d31c78 2026-08-24)", lock.value.wasm_tools.version);
    try std.testing.expectEqualStrings("wasmtime 48.0.1 (7bac2c277 2026-08-24)", lock.value.wasmtime.version);
    try std.testing.expectEqualStrings("verified", lock.value.rust_wasmtime.status);
    try toolchain.verify_tool(std.testing.allocator, std.testing.io, lock.value.wasm_tools);
    try toolchain.verify_tool(std.testing.allocator, std.testing.io, lock.value.wasmtime);
}

test "toolchain command runner captures output and preserves nonzero status" {
    const argv = [_][]const u8{ "-c", "printf out; printf err >&2; exit 7" };
    var result = try toolchain.run_command(std.testing.allocator, std.testing.io, "/bin/sh", &argv);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 7), result.exit_code);
    try std.testing.expectEqualStrings("out", result.stdout);
    try std.testing.expectEqualStrings("err", result.stderr);
}
