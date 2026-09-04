//! Current-only external toolchain adapter.
//!
//! The adapter owns tool identity checks and exposes only the operations used
//! by repository gates. Compiler semantic code must not inspect tool versions.
const std = @import("std");

pub const AdapterError = error{
    InvalidToolSpec,
    VersionMismatch,
    HashMismatch,
    CapabilityMissing,
    InvalidOperationArgs,
    InvalidFeatureProfile,
    CommandFailed,
};

pub const FeatureProfile = enum {
    none,
    component_async,
    component_map,
    core_gc_async,
};

pub fn parse_feature_profile(name: []const u8) AdapterError!FeatureProfile {
    if (std.mem.eql(u8, name, "none")) return .none;
    if (std.mem.eql(u8, name, "component-async")) return .component_async;
    if (std.mem.eql(u8, name, "component-map")) return .component_map;
    if (std.mem.eql(u8, name, "core-gc-async")) return .core_gc_async;
    return error.InvalidFeatureProfile;
}

fn feature_list(profile: FeatureProfile) ?[]const u8 {
    return switch (profile) {
        .none => null,
        .component_async => "cm-async,cm-more-async-builtins",
        .component_map => "cm-map",
        .core_gc_async => "gc,cm-async,cm-more-async-builtins",
    };
}

pub const ToolSpec = struct {
    name: []const u8,
    path: []const u8,
    version: []const u8,
    sha256: []const u8,
    capabilities: []const []const u8,
};

pub const RustWasmtimeLock = struct {
    version: []const u8,
    target_version: []const u8,
    status: []const u8,
};

pub const ToolchainLock = struct {
    schema: u32,
    wasm_tools: ToolSpec,
    wasmtime: ToolSpec,
    zig: ToolSpec,
    rustc: ToolSpec,
    cargo: ToolSpec,
    rust_wasmtime: RustWasmtimeLock,
};

pub const ParsedLock = struct {
    value: ToolchainLock,
    parsed: std.json.Parsed(ToolchainLock),
    source: []u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ParsedLock) void {
        self.parsed.deinit();
        self.allocator.free(self.source);
        self.* = undefined;
    }
};

pub fn load_lock(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
) !ParsedLock {
    const source = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024 * 1024));
    var parsed = std.json.parseFromSlice(ToolchainLock, allocator, source, .{}) catch {
        allocator.free(source);
        return error.InvalidToolSpec;
    };
    if (parsed.value.schema != 1) {
        parsed.deinit();
        allocator.free(source);
        return error.InvalidToolSpec;
    }
    return .{ .value = parsed.value, .parsed = parsed, .source = source, .allocator = allocator };
}

pub const Operation = enum {
    parse_core,
    strip_core,
    validate_core,
    compile_core_gc,
    invoke_core_gc,
    run_core_gc,
    embed_component,
    embed_component_template,
    new_component,
    validate_component,
    component_wit,
    component_targets,
    print_component,
    run_wasmtime,
    probe,
};

pub const ParseCoreArgs = struct {
    input: []const u8,
    output: []const u8,
};

pub const StripCoreArgs = struct {
    input: []const u8,
    output: []const u8,
};

pub const ValidateCoreArgs = struct {
    wasm: []const u8,
};

pub const CompileCoreGcArgs = struct {
    input: []const u8,
    output: []const u8,
};

pub const InvokeCoreGcArgs = struct {
    module: []const u8,
    export_name: []const u8,
};

pub const RunCoreGcArgs = struct {
    module: []const u8,
};

pub const EmbedComponentArgs = struct {
    wit: []const u8,
    core_wasm: []const u8,
    world: []const u8,
    output: []const u8,
    features: FeatureProfile = .component_async,
};

pub const EmbedComponentTemplateArgs = struct {
    wit: []const u8,
    world: []const u8,
    features: FeatureProfile = .component_async,
};

pub const NewComponentArgs = struct {
    embedded: []const u8,
    output: []const u8,
};

pub const ValidateComponentArgs = struct {
    component: []const u8,
    features: FeatureProfile = .component_async,
};

pub const PrintComponentArgs = struct {
    component: []const u8,
};

pub const ComponentWitArgs = struct {
    component: []const u8,
    world: ?[]const u8 = null,
};

pub const ComponentTargetsArgs = struct {
    wit: []const u8,
    component: []const u8,
    world: []const u8,
};

pub const RunWasmtimeArgs = struct {
    component: []const u8,
    arguments: []const []const u8 = &.{},
};

pub const OperationArgs = union(Operation) {
    parse_core: ParseCoreArgs,
    strip_core: StripCoreArgs,
    validate_core: ValidateCoreArgs,
    compile_core_gc: CompileCoreGcArgs,
    invoke_core_gc: InvokeCoreGcArgs,
    run_core_gc: RunCoreGcArgs,
    embed_component: EmbedComponentArgs,
    embed_component_template: EmbedComponentTemplateArgs,
    new_component: NewComponentArgs,
    validate_component: ValidateComponentArgs,
    component_wit: ComponentWitArgs,
    component_targets: ComponentTargetsArgs,
    print_component: PrintComponentArgs,
    run_wasmtime: RunWasmtimeArgs,
    probe: void,
};

pub const CommandResult = struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: u8,

    pub fn deinit(self: *CommandResult, allocator: std.mem.Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
        self.* = undefined;
    }
};

pub fn validate_identity(spec: ToolSpec, actual_version: []const u8, actual_sha256: []const u8) AdapterError!void {
    if (spec.name.len == 0 or spec.path.len == 0 or spec.version.len == 0 or spec.sha256.len != 64) {
        return error.InvalidToolSpec;
    }
    if (!std.mem.eql(u8, spec.version, actual_version)) return error.VersionMismatch;
    if (!std.mem.eql(u8, spec.sha256, actual_sha256)) return error.HashMismatch;
}

pub fn require_capability(spec: ToolSpec, capability: []const u8) AdapterError!void {
    for (spec.capabilities) |candidate| {
        if (std.mem.eql(u8, candidate, capability)) return;
    }
    return error.CapabilityMissing;
}

pub fn operation_capability(operation: Operation) ?[]const u8 {
    return switch (operation) {
        .parse_core => "parse-core",
        .strip_core => "strip-core",
        .validate_core => "validate-core",
        .compile_core_gc => "compile-core-gc",
        .invoke_core_gc => "invoke-core-gc",
        .run_core_gc => "run-core-gc",
        .embed_component => "embed-component",
        .embed_component_template => "embed-component-template",
        .new_component => "new-component",
        .validate_component => "validate-component",
        .component_wit => "component-wit",
        .component_targets => "component-targets",
        .print_component => "print-component",
        .run_wasmtime => "run-wasmtime",
        .probe => null,
    };
}

/// Build the argv after argv[0]. Every accepted operation has a fixed shape;
/// callers cannot pass arbitrary flags through this API.
pub fn build_argv(
    allocator: std.mem.Allocator,
    operation: Operation,
    args: OperationArgs,
) (AdapterError || std.mem.Allocator.Error)![][]u8 {
    if (@as(Operation, args) != operation) return error.InvalidOperationArgs;
    var out = std.ArrayList([]u8).empty;
    errdefer free_argv(allocator, out.items);

    switch (args) {
        .parse_core => |value| {
            try append_arg(allocator, &out, "parse");
            try append_arg(allocator, &out, value.input);
            try append_arg(allocator, &out, "-o");
            try append_arg(allocator, &out, value.output);
        },
        .strip_core => |value| {
            try append_arg(allocator, &out, "strip");
            try append_arg(allocator, &out, "-a");
            try append_arg(allocator, &out, value.input);
            try append_arg(allocator, &out, "-o");
            try append_arg(allocator, &out, value.output);
        },
        .validate_core => |value| {
            try append_arg(allocator, &out, "validate");
            try append_arg(allocator, &out, "--features");
            try append_arg(allocator, &out, "gc,cm-async,cm-more-async-builtins");
            try append_arg(allocator, &out, value.wasm);
        },
        .compile_core_gc => |value| {
            try append_arg(allocator, &out, "compile");
            try append_arg(allocator, &out, "-W");
            try append_arg(allocator, &out, "gc=y");
            try append_arg(allocator, &out, "-o");
            try append_arg(allocator, &out, value.output);
            try append_arg(allocator, &out, value.input);
        },
        .invoke_core_gc => |value| {
            try append_arg(allocator, &out, "-W");
            try append_arg(allocator, &out, "gc=y");
            try append_arg(allocator, &out, "--invoke");
            try append_arg(allocator, &out, value.export_name);
            try append_arg(allocator, &out, value.module);
        },
        .run_core_gc => |value| {
            try append_arg(allocator, &out, "run");
            try append_arg(allocator, &out, "-W");
            try append_arg(allocator, &out, "gc=y");
            try append_arg(allocator, &out, value.module);
        },
        .embed_component => |value| {
            try append_arg(allocator, &out, "component");
            try append_arg(allocator, &out, "embed");
            try append_arg(allocator, &out, value.wit);
            try append_arg(allocator, &out, value.core_wasm);
            try append_arg(allocator, &out, "--world");
            try append_arg(allocator, &out, value.world);
            try append_feature_args(allocator, &out, value.features);
            try append_arg(allocator, &out, "-o");
            try append_arg(allocator, &out, value.output);
        },
        .embed_component_template => |value| {
            try append_arg(allocator, &out, "component");
            try append_arg(allocator, &out, "embed");
            try append_arg(allocator, &out, value.wit);
            try append_arg(allocator, &out, "--world");
            try append_arg(allocator, &out, value.world);
            try append_arg(allocator, &out, "--dummy-names");
            try append_arg(allocator, &out, "legacy");
            try append_arg(allocator, &out, "--async-callback");
            try append_feature_args(allocator, &out, value.features);
            try append_arg(allocator, &out, "-t");
        },
        .new_component => |value| {
            try append_arg(allocator, &out, "component");
            try append_arg(allocator, &out, "new");
            try append_arg(allocator, &out, "--skip-validation");
            try append_arg(allocator, &out, value.embedded);
            try append_arg(allocator, &out, "-o");
            try append_arg(allocator, &out, value.output);
        },
        .validate_component => |value| {
            try append_arg(allocator, &out, "validate");
            try append_feature_args(allocator, &out, value.features);
            try append_arg(allocator, &out, value.component);
        },
        .component_wit => |value| {
            try append_arg(allocator, &out, "component");
            try append_arg(allocator, &out, "wit");
            try append_arg(allocator, &out, value.component);
            if (value.world) |world| {
                try append_arg(allocator, &out, "--world");
                try append_arg(allocator, &out, world);
            }
        },
        .component_targets => |value| {
            try append_arg(allocator, &out, "component");
            try append_arg(allocator, &out, "targets");
            try append_arg(allocator, &out, value.wit);
            try append_arg(allocator, &out, value.component);
            try append_arg(allocator, &out, "--world");
            try append_arg(allocator, &out, value.world);
        },
        .print_component => |value| {
            try append_arg(allocator, &out, "print");
            try append_arg(allocator, &out, value.component);
        },
        .run_wasmtime => |value| {
            try append_arg(allocator, &out, "run");
            try append_arg(allocator, &out, value.component);
            for (value.arguments) |argument| try append_arg(allocator, &out, argument);
        },
        .probe => {},
    }
    return out.toOwnedSlice(allocator);
}

pub fn free_argv(allocator: std.mem.Allocator, argv: []const []u8) void {
    for (argv) |arg| allocator.free(arg);
    if (argv.len != 0) allocator.free(argv);
}

fn append_arg(allocator: std.mem.Allocator, out: *std.ArrayList([]u8), value: []const u8) !void {
    try out.append(allocator, try allocator.dupe(u8, value));
}

fn append_feature_args(
    allocator: std.mem.Allocator,
    out: *std.ArrayList([]u8),
    profile: FeatureProfile,
) !void {
    if (feature_list(profile)) |features| {
        try append_arg(allocator, out, "--features");
        try append_arg(allocator, out, features);
    }
}

pub fn run_command(
    allocator: std.mem.Allocator,
    io: std.Io,
    executable: []const u8,
    argv: []const []const u8,
) !CommandResult {
    var full_argv = try allocator.alloc([]const u8, argv.len + 1);
    defer allocator.free(full_argv);
    full_argv[0] = executable;
    @memcpy(full_argv[1..], argv);

    const result = try std.process.run(allocator, io, .{
        .argv = full_argv,
        .stdout_limit = .limited(16 * 1024 * 1024),
        .stderr_limit = .limited(16 * 1024 * 1024),
    });
    return .{
        .stdout = result.stdout,
        .stderr = result.stderr,
        .exit_code = switch (result.term) {
            .exited => |code| code,
            .signal, .stopped, .unknown => 1,
        },
    };
}

pub fn executable_sha256(io: std.Io, path: []const u8) ![64]u8 {
    const source = try std.Io.Dir.cwd().readFileAlloc(io, path, std.heap.page_allocator, .limited(256 * 1024 * 1024));
    defer std.heap.page_allocator.free(source);
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(source, &digest, .{});
    var encoded: [64]u8 = undefined;
    const digits = "0123456789abcdef";
    for (digest, 0..) |byte, index| {
        encoded[index * 2] = digits[byte >> 4];
        encoded[index * 2 + 1] = digits[byte & 0x0f];
    }
    return encoded;
}

pub fn verify_tool(allocator: std.mem.Allocator, io: std.Io, spec: ToolSpec) !void {
    const version_argv = [_][]const u8{"--version"};
    var version_result = try run_command(allocator, io, spec.path, &version_argv);
    defer version_result.deinit(allocator);
    if (version_result.exit_code != 0) return error.CommandFailed;
    const actual_version = std.mem.trim(u8, version_result.stdout, " \t\r\n");
    const actual_hash = try executable_sha256(io, spec.path);
    try validate_identity(spec, actual_version, &actual_hash);
}

pub fn run_operation(
    allocator: std.mem.Allocator,
    io: std.Io,
    lock: *const ToolchainLock,
    operation: Operation,
    args: OperationArgs,
) !CommandResult {
    const spec = switch (operation) {
        .parse_core, .strip_core, .validate_core, .embed_component, .embed_component_template, .new_component, .validate_component, .component_wit, .component_targets, .print_component => lock.wasm_tools,
        .compile_core_gc, .invoke_core_gc, .run_core_gc, .run_wasmtime => lock.wasmtime,
        .probe => return error.InvalidOperationArgs,
    };
    try verify_tool(allocator, io, spec);
    if (operation_capability(operation)) |capability| try require_capability(spec, capability);
    const operation_argv = try build_argv(allocator, operation, args);
    defer free_argv(allocator, operation_argv);
    return run_command(allocator, io, spec.path, operation_argv);
}

test "toolchain operation capability mapping is stable" {
    try std.testing.expectEqualStrings("parse-core", operation_capability(.parse_core).?);
    try std.testing.expectEqualStrings("strip-core", operation_capability(.strip_core).?);
    try std.testing.expectEqualStrings("validate-core", operation_capability(.validate_core).?);
    try std.testing.expectEqualStrings("component-targets", operation_capability(.component_targets).?);
    try std.testing.expectEqualStrings("run-wasmtime", operation_capability(.run_wasmtime).?);
    try std.testing.expect(operation_capability(.probe) == null);
}

test "component targets operation builds a fixed wasm-tools argv" {
    const argv = try build_argv(std.testing.allocator, .component_targets, .{ .component_targets = .{
        .wit = "interface.wit",
        .component = "component.wasm",
        .world = "probe",
    } });
    defer free_argv(std.testing.allocator, argv);

    const expected = [_][]const u8{
        "component",
        "targets",
        "interface.wit",
        "component.wasm",
        "--world",
        "probe",
    };
    try std.testing.expectEqual(expected.len, argv.len);
    for (expected, 0..) |value, index| try std.testing.expectEqualStrings(value, argv[index]);
}

test "GC core compile operation builds a fixed Wasmtime argv" {
    const argv = try build_argv(std.testing.allocator, .compile_core_gc, .{
        .compile_core_gc = .{ .input = "module.wat", .output = "module.compiled" },
    });
    defer free_argv(std.testing.allocator, argv);

    const expected = [_][]const u8{ "compile", "-W", "gc=y", "-o", "module.compiled", "module.wat" };
    try std.testing.expectEqual(expected.len, argv.len);
    for (expected, 0..) |value, index| try std.testing.expectEqualStrings(value, argv[index]);
}

test "GC core invoke operation builds a fixed Wasmtime argv" {
    const argv = try build_argv(std.testing.allocator, .invoke_core_gc, .{
        .invoke_core_gc = .{ .module = "module.wat", .export_name = "probe" },
    });
    defer free_argv(std.testing.allocator, argv);

    const expected = [_][]const u8{ "-W", "gc=y", "--invoke", "probe", "module.wat" };
    try std.testing.expectEqual(expected.len, argv.len);
    for (expected, 0..) |value, index| try std.testing.expectEqualStrings(value, argv[index]);
}

test "GC core run operation builds a fixed Wasmtime argv" {
    const argv = try build_argv(std.testing.allocator, .run_core_gc, .{
        .run_core_gc = .{ .module = "module.wasm" },
    });
    defer free_argv(std.testing.allocator, argv);

    const expected = [_][]const u8{ "run", "-W", "gc=y", "module.wasm" };
    try std.testing.expectEqual(expected.len, argv.len);
    for (expected, 0..) |value, index| try std.testing.expectEqualStrings(value, argv[index]);
}
