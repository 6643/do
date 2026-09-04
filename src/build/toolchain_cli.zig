const std = @import("std");
const toolchain = @import("toolchain.zig");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) return usage(init.io, 2);

    const lock_path = init.environ_map.get("DO_TOOLCHAIN_LOCK") orelse "toolchain/toolchain.lock.json";
    if (std.mem.eql(u8, args[1], "probe")) {
        if (args.len != 2) return usage(init.io, 2);
        return probe(init, lock_path);
    }

    var lock = toolchain.load_lock(init.gpa, init.io, lock_path) catch |err| {
        try print_error(init.io, "load lock", err);
        std.process.exit(1);
    };
    defer lock.deinit();

    const parsed = parse_operation(args[1..]) catch |err| {
        try print_error(init.io, "operation arguments", err);
        std.process.exit(2);
    };
    var result = toolchain.run_operation(init.gpa, init.io, &lock.value, parsed.operation, parsed.args) catch |err| {
        try print_error(init.io, "toolchain operation", err);
        std.process.exit(1);
    };
    defer result.deinit(init.gpa);
    if (result.stdout.len != 0) try write_all(init.io, std.Io.File.stdout(), result.stdout);
    if (result.stderr.len != 0) try write_all(init.io, std.Io.File.stderr(), result.stderr);
    if (result.exit_code != 0) std.process.exit(result.exit_code);
}

const ParsedOperation = struct {
    operation: toolchain.Operation,
    args: toolchain.OperationArgs,
};

fn parse_operation(args: []const []const u8) !ParsedOperation {
    if (args.len == 0) return error.InvalidOperationArgs;
    const name = args[0];
    if (std.mem.eql(u8, name, "parse-core")) {
        if (args.len != 4 or !std.mem.eql(u8, args[2], "-o")) return error.InvalidOperationArgs;
        return .{ .operation = .parse_core, .args = .{ .parse_core = .{ .input = args[1], .output = args[3] } } };
    }
    if (std.mem.eql(u8, name, "strip-core")) {
        if (args.len != 4 or !std.mem.eql(u8, args[2], "-o")) return error.InvalidOperationArgs;
        return .{ .operation = .strip_core, .args = .{ .strip_core = .{ .input = args[1], .output = args[3] } } };
    }
    if (std.mem.eql(u8, name, "validate-core")) {
        if (args.len != 2) return error.InvalidOperationArgs;
        return .{ .operation = .validate_core, .args = .{ .validate_core = .{ .wasm = args[1] } } };
    }
    if (std.mem.eql(u8, name, "compile-core-gc")) {
        if (args.len != 4 or !std.mem.eql(u8, args[2], "-o")) return error.InvalidOperationArgs;
        return .{ .operation = .compile_core_gc, .args = .{ .compile_core_gc = .{ .input = args[1], .output = args[3] } } };
    }
    if (std.mem.eql(u8, name, "invoke-core-gc")) {
        if (args.len != 4 or !std.mem.eql(u8, args[2], "--export")) return error.InvalidOperationArgs;
        return .{ .operation = .invoke_core_gc, .args = .{ .invoke_core_gc = .{ .module = args[1], .export_name = args[3] } } };
    }
    if (std.mem.eql(u8, name, "run-core-gc")) {
        if (args.len != 2) return error.InvalidOperationArgs;
        return .{ .operation = .run_core_gc, .args = .{ .run_core_gc = .{ .module = args[1] } } };
    }
    if (std.mem.eql(u8, name, "embed-component")) {
        if (args.len != 6 and args.len != 8) return error.InvalidOperationArgs;
        if (args.len == 6 and !std.mem.eql(u8, args[4], "-o")) return error.InvalidOperationArgs;
        if (args.len == 8 and (!std.mem.eql(u8, args[4], "--features") or !std.mem.eql(u8, args[6], "-o"))) {
            return error.InvalidOperationArgs;
        }
        const features = if (args.len == 8)
            try toolchain.parse_feature_profile(args[5])
        else
            toolchain.FeatureProfile.component_async;
        return .{ .operation = .embed_component, .args = .{ .embed_component = .{
            .wit = args[1],
            .core_wasm = args[2],
            .world = args[3],
            .features = features,
            .output = if (args.len == 8) args[7] else args[5],
        } } };
    }
    if (std.mem.eql(u8, name, "embed-component-template")) {
        if (args.len != 3 and args.len != 5) return error.InvalidOperationArgs;
        if (args.len == 5 and !std.mem.eql(u8, args[3], "--features")) return error.InvalidOperationArgs;
        const features = if (args.len == 5)
            try toolchain.parse_feature_profile(args[4])
        else
            toolchain.FeatureProfile.component_async;
        return .{ .operation = .embed_component_template, .args = .{ .embed_component_template = .{
            .wit = args[1],
            .world = args[2],
            .features = features,
        } } };
    }
    if (std.mem.eql(u8, name, "new-component")) {
        if (args.len != 4 or !std.mem.eql(u8, args[2], "-o")) return error.InvalidOperationArgs;
        return .{ .operation = .new_component, .args = .{ .new_component = .{ .embedded = args[1], .output = args[3] } } };
    }
    if (std.mem.eql(u8, name, "validate-component")) {
        if (args.len != 2 and args.len != 4) return error.InvalidOperationArgs;
        if (args.len == 4 and !std.mem.eql(u8, args[2], "--features")) return error.InvalidOperationArgs;
        const features = if (args.len == 4)
            try toolchain.parse_feature_profile(args[3])
        else
            toolchain.FeatureProfile.component_async;
        return .{ .operation = .validate_component, .args = .{ .validate_component = .{
            .component = args[1],
            .features = features,
        } } };
    }
    if (std.mem.eql(u8, name, "component-wit")) {
        if (args.len == 2) return .{ .operation = .component_wit, .args = .{ .component_wit = .{ .component = args[1] } } };
        if (args.len == 4 and std.mem.eql(u8, args[2], "--world")) {
            return .{ .operation = .component_wit, .args = .{ .component_wit = .{ .component = args[1], .world = args[3] } } };
        }
        return error.InvalidOperationArgs;
    }
    if (std.mem.eql(u8, name, "component-targets")) {
        if (args.len != 5 or !std.mem.eql(u8, args[3], "--world")) return error.InvalidOperationArgs;
        return .{ .operation = .component_targets, .args = .{ .component_targets = .{
            .wit = args[1],
            .component = args[2],
            .world = args[4],
        } } };
    }
    if (std.mem.eql(u8, name, "print-component")) {
        if (args.len != 2) return error.InvalidOperationArgs;
        return .{ .operation = .print_component, .args = .{ .print_component = .{ .component = args[1] } } };
    }
    if (std.mem.eql(u8, name, "run-wasmtime")) {
        if (args.len < 2) return error.InvalidOperationArgs;
        var guest_args: []const []const u8 = &.{};
        if (args.len > 2) {
            if (!std.mem.eql(u8, args[2], "--")) return error.InvalidOperationArgs;
            guest_args = args[3..];
        }
        return .{ .operation = .run_wasmtime, .args = .{ .run_wasmtime = .{ .component = args[1], .arguments = guest_args } } };
    }
    return error.InvalidOperationArgs;
}

fn probe(init: std.process.Init, lock_path: []const u8) !void {
    var lock = toolchain.load_lock(init.gpa, init.io, lock_path) catch |err| {
        try print_error(init.io, "load lock", err);
        std.process.exit(1);
    };
    defer lock.deinit();
    toolchain.verify_tool(init.gpa, init.io, lock.value.wasm_tools) catch |err| {
        try print_error(init.io, "verify wasm-tools", err);
        std.process.exit(1);
    };
    toolchain.verify_tool(init.gpa, init.io, lock.value.wasmtime) catch |err| {
        try print_error(init.io, "verify wasmtime", err);
        std.process.exit(1);
    };

    var buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buffer);
    try out.interface.print(
        "{{\"schema\":{d},\"wasm_tools\":{{\"path\":\"{s}\",\"version\":\"{s}\",\"sha256\":\"{s}\"}},\"wasmtime\":{{\"path\":\"{s}\",\"version\":\"{s}\",\"sha256\":\"{s}\"}},\"rust_wasmtime\":{{\"version\":\"{s}\",\"target_version\":\"{s}\",\"status\":\"{s}\"}}}}\n",
        .{
            lock.value.schema,
            lock.value.wasm_tools.path,
            lock.value.wasm_tools.version,
            lock.value.wasm_tools.sha256,
            lock.value.wasmtime.path,
            lock.value.wasmtime.version,
            lock.value.wasmtime.sha256,
            lock.value.rust_wasmtime.version,
            lock.value.rust_wasmtime.target_version,
            lock.value.rust_wasmtime.status,
        },
    );
    try out.interface.flush();
}

fn usage(io: std.Io, code: u8) !void {
    var buffer: [1024]u8 = undefined;
    var out = std.Io.File.stderr().writer(io, &buffer);
    try out.interface.writeAll("usage: do-toolchain probe | parse-core <input> -o <output> | strip-core <input> -o <output> | validate-core <wasm> | compile-core-gc <input> -o <output> | invoke-core-gc <module> --export <name> | run-core-gc <module> | embed-component <wit> <core> <world> [--features <none|component-async|component-map|core-gc-async>] -o <output> | embed-component-template <wit> <world> [--features <none|component-async|component-map|core-gc-async>] | new-component <embedded> -o <output> | validate-component <component> [--features <none|component-async|component-map|core-gc-async>] | component-wit <component> [--world <world>] | component-targets <wit> <component> --world <world> | print-component <component> | run-wasmtime <component> [-- <args...>]\n");
    try out.interface.flush();
    std.process.exit(code);
}

fn print_error(io: std.Io, context: []const u8, err: anyerror) !void {
    var buffer: [512]u8 = undefined;
    var out = std.Io.File.stderr().writer(io, &buffer);
    try out.interface.print("error[ToolchainAdapter]: {s}: {s}\n", .{ context, @errorName(err) });
    try out.interface.flush();
}

fn write_all(io: std.Io, file: std.Io.File, data: []const u8) !void {
    var buffer: [4096]u8 = undefined;
    var writer = file.writer(io, &buffer);
    try writer.interface.writeAll(data);
    try writer.interface.flush();
}

test "toolchain CLI parses an explicit component feature profile" {
    const parsed = try parse_operation(&.{
        "embed-component",
        "interface.wit",
        "module.wasm",
        "probe",
        "--features",
        "none",
        "-o",
        "embedded.wasm",
    });

    try std.testing.expectEqual(toolchain.Operation.embed_component, parsed.operation);
    try std.testing.expectEqual(toolchain.FeatureProfile.none, parsed.args.embed_component.features);
}

test "toolchain CLI parses core stripping arguments" {
    const parsed = try parse_operation(&.{
        "strip-core",
        "input.wasm",
        "-o",
        "output.wasm",
    });

    try std.testing.expectEqual(toolchain.Operation.strip_core, parsed.operation);
    try std.testing.expectEqualStrings("input.wasm", parsed.args.strip_core.input);
    try std.testing.expectEqualStrings("output.wasm", parsed.args.strip_core.output);
}

test "toolchain CLI parses GC core compile arguments" {
    const parsed = try parse_operation(&.{
        "compile-core-gc",
        "input.wat",
        "-o",
        "output.compiled",
    });

    try std.testing.expectEqual(toolchain.Operation.compile_core_gc, parsed.operation);
    try std.testing.expectEqualStrings("input.wat", parsed.args.compile_core_gc.input);
    try std.testing.expectEqualStrings("output.compiled", parsed.args.compile_core_gc.output);
}

test "toolchain CLI parses GC core invoke arguments" {
    const parsed = try parse_operation(&.{
        "invoke-core-gc",
        "module.wat",
        "--export",
        "probe",
    });

    try std.testing.expectEqual(toolchain.Operation.invoke_core_gc, parsed.operation);
    try std.testing.expectEqualStrings("module.wat", parsed.args.invoke_core_gc.module);
    try std.testing.expectEqualStrings("probe", parsed.args.invoke_core_gc.export_name);
}

test "toolchain CLI parses GC core run arguments" {
    const parsed = try parse_operation(&.{
        "run-core-gc",
        "module.wasm",
    });

    try std.testing.expectEqual(toolchain.Operation.run_core_gc, parsed.operation);
    try std.testing.expectEqualStrings("module.wasm", parsed.args.run_core_gc.module);
}

test "toolchain CLI parses async metadata template arguments" {
    const parsed = try parse_operation(&.{
        "embed-component-template",
        "interface.wit",
        "probe",
        "--features",
        "none",
    });

    try std.testing.expectEqual(toolchain.Operation.embed_component_template, parsed.operation);
    try std.testing.expectEqualStrings("interface.wit", parsed.args.embed_component_template.wit);
    try std.testing.expectEqualStrings("probe", parsed.args.embed_component_template.world);
    try std.testing.expectEqual(toolchain.FeatureProfile.none, parsed.args.embed_component_template.features);
}

test "toolchain CLI parses validate component feature profile" {
    const parsed = try parse_operation(&.{
        "validate-component",
        "component.wasm",
        "--features",
        "none",
    });

    try std.testing.expectEqual(toolchain.Operation.validate_component, parsed.operation);
    try std.testing.expectEqual(toolchain.FeatureProfile.none, parsed.args.validate_component.features);
}

test "toolchain CLI parses the core GC async component profile" {
    const parsed = try parse_operation(&.{
        "embed-component",
        "interface.wit",
        "module.wasm",
        "probe",
        "--features",
        "core-gc-async",
        "-o",
        "embedded.wasm",
    });

    try std.testing.expectEqual(toolchain.Operation.embed_component, parsed.operation);
    try std.testing.expectEqual(toolchain.FeatureProfile.core_gc_async, parsed.args.embed_component.features);
}

test "toolchain CLI rejects an invalid component feature profile" {
    try std.testing.expectError(
        error.InvalidFeatureProfile,
        parse_operation(&.{
            "validate-component",
            "component.wasm",
            "--features",
            "gc,custom",
        }),
    );
}

test "toolchain CLI parses component target arguments" {
    const parsed = try parse_operation(&.{
        "component-targets",
        "interface.wit",
        "component.wasm",
        "--world",
        "probe",
    });

    try std.testing.expectEqual(toolchain.Operation.component_targets, parsed.operation);
    try std.testing.expectEqualStrings("interface.wit", parsed.args.component_targets.wit);
    try std.testing.expectEqualStrings("component.wasm", parsed.args.component_targets.component);
    try std.testing.expectEqualStrings("probe", parsed.args.component_targets.world);
}
