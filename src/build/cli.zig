const std = @import("std");

pub const Args = struct {
    input_path: []const u8,
    output_path: []const u8,
    compiled_test: bool = false,
    component_core: bool = false,
    p3_wait_for_component: bool = false,
    p3_resource_probe_component: bool = false,
    p3_wasi_filesystem_preopen_component: bool = false,
    p3_wasi_sockets_create_bind_drop_component: bool = false,
    p3_resource_async_component: bool = false,
    p3_async_component: bool = false,
    gc_core: bool = false,
    p3_wit_output_path: ?[]const u8 = null,
    p3_wit_package_output_path: ?[]const u8 = null,
    host_export: bool = false,
    host_manifest_path: ?[]const u8 = null,
};

pub const RunArgs = struct {
    input_path: []const u8,
};

pub const FmtArgs = struct {
    input_path: []const u8,
    check: bool = false,
    write: bool = false,
};

pub const LspArgs = struct {
    stdio: bool = true,
};

pub const CheckArgs = struct {
    input_paths: []const []const u8,
};

pub fn parse_build(args: []const []const u8) !Args {
    var input_path: ?[]const u8 = null;
    var output_path: []const u8 = "out.wat";
    var component_core = false;
    var p3_wait_for_component = false;
    var p3_resource_probe_component = false;
    var p3_wasi_filesystem_preopen_component = false;
    var p3_wasi_sockets_create_bind_drop_component = false;
    var p3_resource_async_component = false;
    var p3_async_component = false;
    var gc_core = false;
    var p3_wit_output_path: ?[]const u8 = null;
    var p3_wit_package_output_path: ?[]const u8 = null;
    var host_export = false;
    var host_manifest_path: ?[]const u8 = null;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--component-core")) {
            component_core = true;
            continue;
        }
        if (std.mem.eql(u8, args[i], "--p3-wait-for-component")) {
            p3_wait_for_component = true;
            continue;
        }
        if (std.mem.eql(u8, args[i], "--p3-resource-probe-component")) {
            p3_resource_probe_component = true;
            continue;
        }
        if (std.mem.eql(u8, args[i], "--p3-wasi-filesystem-preopen-component")) {
            p3_wasi_filesystem_preopen_component = true;
            continue;
        }
        if (std.mem.eql(u8, args[i], "--p3-wasi-sockets-create-bind-drop-component")) {
            p3_wasi_sockets_create_bind_drop_component = true;
            continue;
        }
        if (std.mem.eql(u8, args[i], "--p3-resource-async-component")) {
            p3_resource_async_component = true;
            continue;
        }
        if (std.mem.eql(u8, args[i], "--p3-async-component")) {
            p3_async_component = true;
            continue;
        }
        if (std.mem.eql(u8, args[i], "--gc-core")) {
            gc_core = true;
            continue;
        }
        if (std.mem.eql(u8, args[i], "--p3-wit-output")) {
            if (i + 1 >= args.len) return error.MissingP3WitOutputPath;
            i += 1;
            p3_wit_output_path = args[i];
            continue;
        }
        if (std.mem.eql(u8, args[i], "--p3-wit-package-output")) {
            if (i + 1 >= args.len) return error.MissingP3WitPackageOutputPath;
            i += 1;
            p3_wit_package_output_path = args[i];
            continue;
        }
        if (std.mem.eql(u8, args[i], "--host-export")) {
            host_export = true;
            continue;
        }
        if (std.mem.eql(u8, args[i], "--host-manifest")) {
            if (i + 1 >= args.len) return error.MissingHostManifestPath;
            i += 1;
            host_manifest_path = args[i];
            continue;
        }
        if (std.mem.eql(u8, args[i], "-o")) {
            if (i + 1 >= args.len) return error.MissingOutputPath;
            i += 1;
            output_path = args[i];
            continue;
        }
        if (std.mem.startsWith(u8, args[i], "-")) return error.UnexpectedCliArg;
        if (input_path != null) return error.UnexpectedCliArg;
        input_path = args[i];
    }
    const path = input_path orelse return error.MissingInputPath;
    if (host_manifest_path != null and !host_export) return error.HostManifestRequiresHostExport;
    if ((p3_wait_for_component or p3_resource_probe_component or p3_wasi_filesystem_preopen_component or p3_wasi_sockets_create_bind_drop_component or p3_resource_async_component or p3_async_component or gc_core) and (component_core or host_export)) return error.UnexpectedCliArg;
    const special_target_count: u8 = @as(u8, @intFromBool(p3_wait_for_component)) + @as(u8, @intFromBool(p3_resource_probe_component)) + @as(u8, @intFromBool(p3_wasi_filesystem_preopen_component)) + @as(u8, @intFromBool(p3_wasi_sockets_create_bind_drop_component)) + @as(u8, @intFromBool(p3_resource_async_component)) + @as(u8, @intFromBool(p3_async_component)) + @as(u8, @intFromBool(gc_core));
    if (special_target_count > 1) return error.UnexpectedCliArg;
    if (p3_wit_output_path != null and !p3_wait_for_component and !p3_resource_probe_component and !p3_wasi_filesystem_preopen_component and !p3_wasi_sockets_create_bind_drop_component and !p3_resource_async_component and !p3_async_component) return error.P3WitOutputRequiresP3Target;
    if (p3_wit_package_output_path != null and !p3_wait_for_component and !p3_resource_probe_component and !p3_wasi_filesystem_preopen_component and !p3_resource_async_component and !p3_async_component) return error.P3WitPackageOutputRequiresP3Target;
    if (p3_wit_package_output_path != null and !p3_async_component) return error.P3WitPackageOutputRequiresUnifiedTarget;
    if (p3_wit_output_path != null and p3_wit_package_output_path != null) return error.UnexpectedCliArg;
    if (p3_wit_output_path) |wit_path| {
        if (std.mem.eql(u8, wit_path, output_path)) return error.UnexpectedCliArg;
    }
    return .{
        .input_path = path,
        .output_path = output_path,
        .component_core = component_core,
        .p3_wait_for_component = p3_wait_for_component,
        .p3_resource_probe_component = p3_resource_probe_component,
        .p3_wasi_filesystem_preopen_component = p3_wasi_filesystem_preopen_component,
        .p3_wasi_sockets_create_bind_drop_component = p3_wasi_sockets_create_bind_drop_component,
        .p3_resource_async_component = p3_resource_async_component,
        .p3_async_component = p3_async_component,
        .gc_core = gc_core,
        .p3_wit_output_path = p3_wit_output_path,
        .p3_wit_package_output_path = p3_wit_package_output_path,
        .host_export = host_export,
        .host_manifest_path = host_manifest_path,
    };
}

pub fn parse_test(args: []const []const u8) !Args {
    var input_path: ?[]const u8 = null;
    var output_path: []const u8 = "out.wat";
    var compiled_test = false;
    var has_output_path = false;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--compiled")) {
            compiled_test = true;
            continue;
        }
        if (std.mem.eql(u8, args[i], "-o")) {
            if (i + 1 >= args.len) return error.MissingOutputPath;
            i += 1;
            output_path = args[i];
            has_output_path = true;
            continue;
        }
        if (std.mem.startsWith(u8, args[i], "-")) return error.UnexpectedCliArg;
        if (input_path != null) return error.UnexpectedCliArg;
        input_path = args[i];
    }
    if (has_output_path and !compiled_test) return error.OutputRequiresCompiledTest;
    const path = input_path orelse return error.MissingTestInputPath;
    return .{
        .input_path = path,
        .output_path = output_path,
        .compiled_test = compiled_test,
    };
}

pub fn parse_run(args: []const []const u8) !RunArgs {
    var input_path: ?[]const u8 = null;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.startsWith(u8, args[i], "-")) return error.UnexpectedCliArg;
        if (input_path != null) return error.UnexpectedCliArg;
        input_path = args[i];
    }
    return .{
        .input_path = input_path orelse return error.MissingInputPath,
    };
}

pub fn parse_fmt(args: []const []const u8) !FmtArgs {
    var input_path: ?[]const u8 = null;
    var check = false;
    var write = false;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--check")) {
            if (check or write) return error.UnexpectedCliArg;
            check = true;
            continue;
        }
        if (std.mem.eql(u8, args[i], "--write")) {
            if (write or check) return error.UnexpectedCliArg;
            write = true;
            continue;
        }
        if (std.mem.startsWith(u8, args[i], "-")) return error.UnexpectedCliArg;
        if (input_path != null) return error.UnexpectedCliArg;
        input_path = args[i];
    }
    return .{
        .input_path = input_path orelse return error.MissingInputPath,
        .check = check,
        .write = write,
    };
}

pub fn parse_lsp(args: []const []const u8) !LspArgs {
    var saw_stdio = false;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--stdio")) {
            if (saw_stdio) return error.UnexpectedCliArg;
            saw_stdio = true;
            continue;
        }
        return error.UnexpectedCliArg;
    }
    return .{ .stdio = true };
}

pub fn parse_check(args: []const []const u8) !CheckArgs {
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.startsWith(u8, args[i], "-")) return error.UnexpectedCliArg;
    }
    if (args.len < 2) return error.MissingInputPath;
    return .{
        .input_paths = args[1..],
    };
}

test "parse_run accepts exactly one input path" {
    const args = [_][]const u8{ "run", "app.do" };
    const parsed = try parse_run(&args);
    try std.testing.expectEqualStrings("app.do", parsed.input_path);
}

test "parse_build accepts host export and manifest" {
    const args = [_][]const u8{ "build", "app.do", "--host-export", "--host-manifest", "app.host.json" };
    const parsed = try parse_build(&args);
    try std.testing.expect(parsed.host_export);
    try std.testing.expectEqualStrings("app.host.json", parsed.host_manifest_path.?);
}

test "parse_build accepts the pinned P3 wait-for component target" {
    const args = [_][]const u8{ "build", "app.do", "--p3-wait-for-component" };
    const parsed = try parse_build(&args);
    try std.testing.expect(parsed.p3_wait_for_component);
}

test "parse_build accepts the pinned resource probe component target" {
    const args = [_][]const u8{ "build", "app.do", "--p3-resource-probe-component", "--p3-wit-output", "app.wit" };
    const parsed = try parse_build(&args);
    try std.testing.expect(parsed.p3_resource_probe_component);
    try std.testing.expectEqualStrings("app.wit", parsed.p3_wit_output_path.?);
}

test "parse_build accepts the pinned filesystem preopen component target" {
    const args = [_][]const u8{ "build", "app.do", "--p3-wasi-filesystem-preopen-component", "--p3-wit-output", "app.wit" };
    const parsed = try parse_build(&args);
    try std.testing.expect(parsed.p3_wasi_filesystem_preopen_component);
    try std.testing.expectEqualStrings("app.wit", parsed.p3_wit_output_path.?);
}

test "parse_build accepts the pinned socket create bind drop component target" {
    const args = [_][]const u8{ "build", "app.do", "--p3-wasi-sockets-create-bind-drop-component", "--p3-wit-output", "app.wit" };
    const parsed = try parse_build(&args);
    try std.testing.expect(parsed.p3_wasi_sockets_create_bind_drop_component);
    try std.testing.expectEqualStrings("app.wit", parsed.p3_wit_output_path.?);
}

test "parse_build accepts the private async resource component target" {
    const args = [_][]const u8{ "build", "app.do", "--p3-resource-async-component", "--p3-wit-output", "app.wit" };
    const parsed = try parse_build(&args);
    try std.testing.expect(parsed.p3_resource_async_component);
    try std.testing.expectEqualStrings("app.wit", parsed.p3_wit_output_path.?);
}

test "parse_build accepts the unified P3 async component target" {
    const args = [_][]const u8{ "build", "app.do", "--p3-async-component", "--p3-wit-output", "app.wit" };
    const parsed = try parse_build(&args);
    try std.testing.expect(parsed.p3_async_component);
    try std.testing.expectEqualStrings("app.wit", parsed.p3_wit_output_path.?);
}

test "parse_build accepts the explicit Core Wasm GC target" {
    const args = [_][]const u8{ "build", "app.do", "--gc-core" };
    const parsed = try parse_build(&args);
    try std.testing.expect(parsed.gc_core);
}

test "parse_build rejects filesystem preopen target with another P3 target" {
    const args = [_][]const u8{ "build", "app.do", "--p3-wasi-filesystem-preopen-component", "--p3-resource-probe-component" };
    try std.testing.expectError(error.UnexpectedCliArg, parse_build(&args));
}

test "parse_build rejects incompatible resource probe component targets" {
    const wait_for = [_][]const u8{ "build", "app.do", "--p3-resource-probe-component", "--p3-wait-for-component" };
    try std.testing.expectError(error.UnexpectedCliArg, parse_build(&wait_for));

    const component_core = [_][]const u8{ "build", "app.do", "--p3-resource-probe-component", "--component-core" };
    try std.testing.expectError(error.UnexpectedCliArg, parse_build(&component_core));

    const host_export = [_][]const u8{ "build", "app.do", "--p3-resource-probe-component", "--host-export" };
    try std.testing.expectError(error.UnexpectedCliArg, parse_build(&host_export));

    const unified = [_][]const u8{ "build", "app.do", "--p3-resource-async-component", "--p3-async-component" };
    try std.testing.expectError(error.UnexpectedCliArg, parse_build(&unified));
}

test "parse_build accepts a P3 WIT sidecar only for the P3 target" {
    const args = [_][]const u8{ "build", "app.do", "--p3-wait-for-component", "--p3-wit-output", "app.wit" };
    const parsed = try parse_build(&args);
    try std.testing.expectEqualStrings("app.wit", parsed.p3_wit_output_path.?);

    const missing_target = [_][]const u8{ "build", "app.do", "--p3-wit-output", "app.wit" };
    try std.testing.expectError(error.P3WitOutputRequiresP3Target, parse_build(&missing_target));

    const same_path = [_][]const u8{ "build", "app.do", "--p3-wait-for-component", "--p3-wit-output", "out.wat" };
    try std.testing.expectError(error.UnexpectedCliArg, parse_build(&same_path));
}

test "parse_build accepts a P3 WIT package output directory" {
    const args = [_][]const u8{ "build", "app.do", "--p3-async-component", "--p3-wit-package-output", "app.wit-package" };
    const parsed = try parse_build(&args);
    try std.testing.expectEqualStrings("app.wit-package", parsed.p3_wit_package_output_path.?);
}

test "parse_build restricts a P3 WIT package output directory to the unified target" {
    const args = [_][]const u8{ "build", "app.do", "--p3-wait-for-component", "--p3-wit-package-output", "app.wit-package" };
    try std.testing.expectError(error.P3WitPackageOutputRequiresUnifiedTarget, parse_build(&args));
}

test "parse_build rejects a manifest without host export" {
    const args = [_][]const u8{ "build", "app.do", "--host-manifest", "app.host.json" };
    try std.testing.expectError(error.HostManifestRequiresHostExport, parse_build(&args));
}

test "parse_run rejects extra args and flags" {
    const extra = [_][]const u8{ "run", "app.do", "extra.do" };
    try std.testing.expectError(error.UnexpectedCliArg, parse_run(&extra));

    const flag = [_][]const u8{ "run", "--bad" };
    try std.testing.expectError(error.UnexpectedCliArg, parse_run(&flag));
}

test "parse_run rejects missing input path" {
    const args = [_][]const u8{"run"};
    try std.testing.expectError(error.MissingInputPath, parse_run(&args));
}

test "parse_fmt accepts stdout mode input path" {
    const args = [_][]const u8{ "fmt", "app.do" };
    const parsed = try parse_fmt(&args);
    try std.testing.expectEqualStrings("app.do", parsed.input_path);
    try std.testing.expect(!parsed.check);
    try std.testing.expect(!parsed.write);
}

test "parse_fmt accepts check mode" {
    const args = [_][]const u8{ "fmt", "--check", "app.do" };
    const parsed = try parse_fmt(&args);
    try std.testing.expectEqualStrings("app.do", parsed.input_path);
    try std.testing.expect(parsed.check);
    try std.testing.expect(!parsed.write);
}

test "parse_fmt accepts write mode" {
    const args = [_][]const u8{ "fmt", "--write", "app.do" };
    const parsed = try parse_fmt(&args);
    try std.testing.expectEqualStrings("app.do", parsed.input_path);
    try std.testing.expect(parsed.write);
    try std.testing.expect(!parsed.check);
}

test "parse_fmt rejects mixing check and write modes" {
    const args = [_][]const u8{ "fmt", "--check", "--write", "app.do" };
    try std.testing.expectError(error.UnexpectedCliArg, parse_fmt(&args));
}

test "parse_fmt rejects missing input, extra input, and unknown flags" {
    const missing = [_][]const u8{"fmt"};
    try std.testing.expectError(error.MissingInputPath, parse_fmt(&missing));

    const extra = [_][]const u8{ "fmt", "app.do", "next.do" };
    try std.testing.expectError(error.UnexpectedCliArg, parse_fmt(&extra));

    const flag = [_][]const u8{ "fmt", "--bad", "app.do" };
    try std.testing.expectError(error.UnexpectedCliArg, parse_fmt(&flag));
}

test "parse_lsp accepts stdio mode without extra args" {
    const args = [_][]const u8{"lsp"};
    const parsed = try parse_lsp(&args);
    try std.testing.expect(parsed.stdio);
}

test "parse_lsp accepts explicit stdio flag" {
    const args = [_][]const u8{ "lsp", "--stdio" };
    const parsed = try parse_lsp(&args);
    try std.testing.expect(parsed.stdio);
}

test "parse_lsp rejects extra args and unknown flags" {
    const extra = [_][]const u8{ "lsp", "app.do" };
    try std.testing.expectError(error.UnexpectedCliArg, parse_lsp(&extra));

    const bad_flag = [_][]const u8{ "lsp", "--tcp" };
    try std.testing.expectError(error.UnexpectedCliArg, parse_lsp(&bad_flag));
}

test "parse_check accepts exactly one input path" {
    const args = [_][]const u8{ "check", "app.do" };
    const parsed = try parse_check(&args);
    try std.testing.expectEqual(@as(usize, 1), parsed.input_paths.len);
    try std.testing.expectEqualStrings("app.do", parsed.input_paths[0]);
}

test "parse_check accepts multiple input paths" {
    const args = [_][]const u8{ "check", "a.do", "b.do" };
    const parsed = try parse_check(&args);
    try std.testing.expectEqual(@as(usize, 2), parsed.input_paths.len);
    try std.testing.expectEqualStrings("a.do", parsed.input_paths[0]);
    try std.testing.expectEqualStrings("b.do", parsed.input_paths[1]);
}

test "parse_check rejects missing input and flags" {
    const missing = [_][]const u8{"check"};
    try std.testing.expectError(error.MissingInputPath, parse_check(&missing));

    const flag = [_][]const u8{ "check", "--watch", "app.do" };
    try std.testing.expectError(error.UnexpectedCliArg, parse_check(&flag));
}
