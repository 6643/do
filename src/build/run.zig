const std = @import("std");
const cli = @import("cli.zig");
const codegen = @import("codegen_runtime_api.zig");
const codegen_gc_wit_marshal = @import("codegen_gc_wit_marshal.zig");
const codegen_gc_wit_host_boundary = @import("codegen_gc_wit_host_boundary.zig");
const codegen_component_descriptor_manifest = @import("codegen_component_descriptor_manifest.zig");
const codegen_host_imports = @import("codegen_host_imports.zig");
const codegen_model = @import("codegen_model.zig");
const diag = @import("diag.zig");
const entry = @import("entry.zig");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const p3_http_wit_manifest = @import("p3_http_wit_manifest.zig");
const sema = @import("sema.zig");
const test_runner = @import("test_runner.zig");

const GcSyncHostWitRoute = codegen_model.GcSyncHostWitRoute;
const HostImport = codegen_model.HostImport;

const GC_DESCRIPTOR_MANIFEST = "doc/wit/gc_descriptor_manifest.json";

const GcHostRouteLease = struct {
    loaded: codegen_component_descriptor_manifest.LoadedRequest,
    host_import: HostImport,
    allocator: std.mem.Allocator,

    fn route(self: *const GcHostRouteLease) GcSyncHostWitRoute {
        return .{ .plan = &self.loaded.plan, .host_import = self.host_import };
    }

    fn deinit(self: *GcHostRouteLease) void {
        const owned_imports = [_]HostImport{self.host_import};
        codegen_host_imports.free_host_imports(self.allocator, owned_imports[0..]);
        self.loaded.deinit();
        self.* = undefined;
    }
};

pub const LoadedProgram = struct {
    source: []const u8,
    tokens: []const lexer.Token,
    program: parser.Program,
    module_graph: imports.ModuleGraph,

    pub fn deinit(self: *LoadedProgram, allocator: std.mem.Allocator) void {
        self.module_graph.deinit();
        self.program.deinit(allocator);
        allocator.free(self.tokens);
        allocator.free(self.source);
    }
};

pub const LoadOptions = struct {
    defer_async_map_validation: bool = false,
};

pub fn run(init: std.process.Init, args: []const []const u8) !void {
    const allocator = init.gpa;
    const io = init.io;

    const parsed_cli = cli.parse_build(args) catch |err| {
        try diag.print_cli_error(io, err);
        std.process.exit(1);
    };

    var loaded = try load_program_with_options(init, parsed_cli.input_path, .{
        .defer_async_map_validation = parsed_cli.p3_async_map_component,
    });
    defer loaded.deinit(allocator);

    var gc_host_route_lease = load_default_gc_host_route(io, allocator, ".", loaded.tokens) catch |err| {
        try diag.print_compile_error(io, parsed_cli.input_path, loaded.source, loaded.tokens, err, null);
        std.process.exit(1);
    };
    defer if (gc_host_route_lease) |*lease| lease.deinit();
    var gc_host_route_storage: ?GcSyncHostWitRoute = if (gc_host_route_lease) |*lease| lease.route() else null;

    if (parsed_cli.p3_wit_package_output_path != null) {
        const supports_http_wit_package = codegen.requires_p3_http_wit_package(allocator, loaded.tokens) catch |err| {
            try diag.print_compile_error(io, parsed_cli.input_path, loaded.source, loaded.tokens, err, null);
            std.process.exit(1);
        };
        if (!supports_http_wit_package) {
            try diag.print_compile_error(io, parsed_cli.input_path, loaded.source, loaded.tokens, error.P3WitPackageOutputRequiresHttpService, null);
            std.process.exit(1);
        }
    }

    var host_manifest = std.ArrayList(u8).empty;
    defer host_manifest.deinit(allocator);
    const wat = if (parsed_cli.gc_wit_marshal_descriptor) |descriptor_id| blk: {
        break :blk emit_gc_wit_marshal_target(io, allocator, ".", descriptor_id, loaded.tokens) catch |err| {
            try diag.print_compile_error(io, parsed_cli.input_path, loaded.source, loaded.tokens, err, null);
            std.process.exit(1);
        };
    } else try compile_program_wat(io, allocator, parsed_cli.input_path, parsed_cli.component_core, parsed_cli.p3_wait_for_component, parsed_cli.p3_async_map_component, parsed_cli.p3_resource_probe_component, parsed_cli.p3_wasi_filesystem_preopen_component, parsed_cli.p3_wasi_filesystem_stat_component, parsed_cli.p3_wasi_sockets_create_bind_drop_component, parsed_cli.p3_resource_async_component, parsed_cli.p3_async_component, parsed_cli.p3_async_call_component, parsed_cli.p3_async_host_arg_component, parsed_cli.p3_owned_future_component, parsed_cli.p3_async_component_v2, parsed_cli.p3_async_v2_scalar_i64_component, parsed_cli.gc_core, parsed_cli.host_export, if (parsed_cli.host_manifest_path != null) &host_manifest else null, &loaded, if (gc_host_route_storage) |*route| route else null);
    defer allocator.free(wat);

    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = parsed_cli.output_path, .data = wat }) catch |err| {
        try diag.print_io_error(io, parsed_cli.output_path, err);
        std.process.exit(1);
    };
    if (parsed_cli.host_manifest_path) |path| {
        std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = host_manifest.items }) catch |err| {
            try diag.print_io_error(io, path, err);
            std.process.exit(1);
        };
    }
    if (parsed_cli.p3_wit_output_path) |path| {
        const wit = (if (parsed_cli.p3_resource_probe_component)
            codegen.emit_p3_resource_probe_wit(allocator, loaded.tokens)
        else if (parsed_cli.p3_async_map_component)
            codegen.emit_p3_async_map_component_wit(allocator)
        else if (parsed_cli.p3_wasi_filesystem_preopen_component)
            codegen.emit_p3_wasi_filesystem_preopen_wit(allocator, loaded.tokens)
        else if (parsed_cli.p3_wasi_filesystem_stat_component)
            codegen.emit_p3_async_component_wit(allocator, loaded.tokens, &loaded.module_graph)
        else if (parsed_cli.p3_wasi_sockets_create_bind_drop_component)
            codegen.emit_p3_wasi_sockets_create_bind_drop_wit(allocator, loaded.tokens)
        else if (parsed_cli.p3_resource_async_component)
            codegen.emit_p3_resource_async_wit(allocator, loaded.tokens)
        else if (parsed_cli.p3_async_call_component)
            codegen.emit_p3_async_call_component_wit(allocator)
        else if (parsed_cli.p3_async_host_arg_component)
            codegen.emit_p3_async_host_arg_component_wit(allocator)
        else if (parsed_cli.p3_owned_future_component)
            codegen.emit_p3_owned_future_component_wit(allocator)
        else if (parsed_cli.p3_async_component)
            codegen.emit_p3_async_component_wit(allocator, loaded.tokens, &loaded.module_graph)
        else if (parsed_cli.p3_async_component_v2)
            codegen.emit_p3_async_component_wit(allocator, loaded.tokens, &loaded.module_graph)
        else if (parsed_cli.p3_async_v2_scalar_i64_component)
            codegen.emit_p3_async_component_wit(allocator, loaded.tokens, &loaded.module_graph)
        else
            codegen.emit_p3_wait_for_wit(allocator, loaded.tokens)) catch |err| {
            try diag.print_compile_error(io, parsed_cli.input_path, loaded.source, loaded.tokens, err, null);
            std.process.exit(1);
        };
        defer allocator.free(wit);
        std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = wit }) catch |err| {
            try diag.print_io_error(io, path, err);
            std.process.exit(1);
        };
    }
    if (parsed_cli.p3_wit_package_output_path) |path| {
        var package_dir = std.Io.Dir.cwd().createDirPathOpen(io, path, .{}) catch |err| {
            try diag.print_io_error(io, path, err);
            std.process.exit(1);
        };
        defer package_dir.close(io);
        p3_http_wit_manifest.write_package(package_dir, io) catch |err| {
            try diag.print_io_error(io, path, err);
            std.process.exit(1);
        };
    }
    try print_compile_ok(io, parsed_cli, loaded.program);
}

fn emit_gc_wit_marshal_target(
    io: std.Io,
    allocator: std.mem.Allocator,
    repository_root: []const u8,
    descriptor_id: []const u8,
    entry_tokens: []const lexer.Token,
) ![]u8 {
    return codegen_gc_wit_marshal.emit_module(io, allocator, repository_root, descriptor_id, entry_tokens);
}

fn admitted_gc_host_descriptor(locator: []const u8, member: []const u8) ?[]const u8 {
    return codegen_gc_wit_host_boundary.descriptor_id_for_host(locator, member);
}

fn load_default_gc_host_route(
    io: std.Io,
    allocator: std.mem.Allocator,
    repository_root: []const u8,
    tokens: []const lexer.Token,
) !?GcHostRouteLease {
    var host_imports = std.ArrayList(HostImport).empty;
    defer {
        codegen_host_imports.free_host_imports(allocator, host_imports.items);
        host_imports.deinit(allocator);
    }
    try codegen_host_imports.collect_host_imports(allocator, tokens, &host_imports);

    var selected_index: ?usize = null;
    var descriptor_id: ?[]const u8 = null;
    for (host_imports.items, 0..) |host_import, index| {
        const candidate = admitted_gc_host_descriptor(host_import.locator, host_import.field) orelse {
            if (codegen_gc_wit_host_boundary.is_admitted_host_locator(host_import.locator)) {
                return error.GcWitHostMemberMismatch;
            }
            continue;
        };
        if (selected_index != null) return error.DuplicateGcWitHostDeclaration;
        selected_index = index;
        descriptor_id = candidate;
    }
    const index = selected_index orelse return null;
    const selected_descriptor = descriptor_id orelse return error.UnsupportedGcWitHostDescriptor;

    var loaded = try codegen_component_descriptor_manifest.load_request_from_manifest(
        io,
        allocator,
        repository_root,
        GC_DESCRIPTOR_MANIFEST,
        selected_descriptor,
        null,
    );
    errdefer loaded.deinit();
    try codegen_component_descriptor_manifest.validate_loaded_host_boundary(&loaded, tokens);

    const selected = host_imports.items[index];
    host_imports.items[index].params = &.{};
    host_imports.items[index].owned_alias = false;
    return .{ .loaded = loaded, .host_import = selected, .allocator = allocator };
}

pub fn run_test(init: std.process.Init, args: []const []const u8) !void {
    const allocator = init.gpa;
    const io = init.io;

    const parsed_cli = cli.parse_test(args) catch |err| {
        try diag.print_cli_error(io, err);
        std.process.exit(1);
    };

    var loaded = try load_program(init, parsed_cli.input_path);
    defer loaded.deinit(allocator);

    if (parsed_cli.compiled_test) {
        try compile_tests(io, allocator, parsed_cli, loaded.source, loaded.tokens, loaded.program, &loaded.module_graph);
    } else {
        try run_tests(io, allocator, parsed_cli, loaded.source, loaded.tokens, &loaded.module_graph);
    }
}

fn run_tests(
    io: std.Io,
    allocator: std.mem.Allocator,
    parsed_cli: cli.Args,
    source: []const u8,
    tokens: []const lexer.Token,
    module_graph: *const imports.ModuleGraph,
) !void {
    test_runner.run_with_modules(io, allocator, parsed_cli.input_path, tokens, module_graph) catch |err| {
        try diag.print_compile_error(io, parsed_cli.input_path, source, tokens, err, null);
        std.process.exit(1);
    };
}

fn compile_tests(
    io: std.Io,
    allocator: std.mem.Allocator,
    parsed_cli: cli.Args,
    source: []const u8,
    tokens: []const lexer.Token,
    program: parser.Program,
    module_graph: *const imports.ModuleGraph,
) !void {
    const test_decls = test_runner.collect_top_level_tests(allocator, tokens) catch |err| {
        try diag.print_compile_error(io, parsed_cli.input_path, source, tokens, err, null);
        std.process.exit(1);
    };
    defer allocator.free(test_decls);
    if (test_decls.len == 0) {
        try diag.print_compile_error(io, parsed_cli.input_path, source, tokens, error.NoTestDecl, null);
        std.process.exit(1);
    }

    const wat = codegen.emit_test_wat(allocator, program, tokens, module_graph) catch |err| {
        try diag.print_compile_error(io, parsed_cli.input_path, source, tokens, err, null);
        std.process.exit(1);
    };
    defer allocator.free(wat);

    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = parsed_cli.output_path, .data = wat }) catch |err| {
        try diag.print_io_error(io, parsed_cli.output_path, err);
        std.process.exit(1);
    };

    try print_compiled_test_ok(io, parsed_cli, test_decls.len);
}

pub fn load_program(init: std.process.Init, input_path: []const u8) !LoadedProgram {
    return load_program_with_options(init, input_path, .{});
}

pub fn load_program_with_options(
    init: std.process.Init,
    input_path: []const u8,
    options: LoadOptions,
) !LoadedProgram {
    const allocator = init.gpa;
    const io = init.io;

    const source = std.Io.Dir.cwd().readFileAlloc(io, input_path, allocator, .limited(16 * 1024 * 1024)) catch |err| {
        try diag.print_io_error(io, input_path, err);
        std.process.exit(1);
    };
    errdefer allocator.free(source);

    const tokens = lexer.tokenize(allocator, source) catch |err| {
        try diag.print_compile_error(io, input_path, source, null, err, null);
        std.process.exit(1);
    };
    errdefer allocator.free(tokens);

    var program = parser.parse_program(allocator, tokens, source.len) catch |err| {
        try diag.print_compile_error(io, input_path, source, tokens, err, parser_error_loc());
        std.process.exit(1);
    };
    errdefer program.deinit(allocator);

    sema.check_program_with_options(allocator, program, tokens, .{
        .defer_async_map_validation = options.defer_async_map_validation,
    }) catch |err| {
        try diag.print_compile_error(io, input_path, source, tokens, err, sema_error_loc());
        std.process.exit(1);
    };

    const dep_root = try resolve_dep_root(allocator, init.environ_map);
    defer dep_root.deinit(allocator);

    var module_graph = imports.check_and_load(io, allocator, input_path, tokens, dep_root.path) catch |err| {
        try diag.print_compile_error(io, input_path, source, tokens, err, imports_error_loc());
        std.process.exit(1);
    };
    errdefer module_graph.deinit();

    return .{
        .source = source,
        .tokens = tokens,
        .program = program,
        .module_graph = module_graph,
    };
}

pub fn compile_program_wat(
    io: std.Io,
    allocator: std.mem.Allocator,
    input_path: []const u8,
    component_core: bool,
    p3_wait_for_component: bool,
    p3_async_map_component: bool,
    p3_resource_probe_component: bool,
    p3_wasi_filesystem_preopen_component: bool,
    p3_wasi_filesystem_stat_component: bool,
    p3_wasi_sockets_create_bind_drop_component: bool,
    p3_resource_async_component: bool,
    p3_async_component: bool,
    p3_async_call_component: bool,
    p3_async_host_arg_component: bool,
    p3_owned_future_component: bool,
    p3_async_component_v2: bool,
    p3_async_v2_scalar_i64_component: bool,
    gc_core: bool,
    host_export: bool,
    host_manifest_out: ?*std.ArrayList(u8),
    loaded: *const LoadedProgram,
    gc_host_route: ?*const GcSyncHostWitRoute,
) ![]u8 {
    return compile_program_wat_parts(
        io,
        allocator,
        input_path,
        component_core,
        p3_wait_for_component,
        p3_async_map_component,
        p3_resource_probe_component,
        p3_wasi_filesystem_preopen_component,
        p3_wasi_filesystem_stat_component,
        p3_wasi_sockets_create_bind_drop_component,
        p3_resource_async_component,
        p3_async_component,
        p3_async_call_component,
        p3_async_host_arg_component,
        p3_owned_future_component,
        p3_async_component_v2,
        p3_async_v2_scalar_i64_component,
        gc_core,
        host_export,
        host_manifest_out,
        loaded.source,
        loaded.tokens,
        loaded.program,
        &loaded.module_graph,
        gc_host_route,
    );
}

fn compile_program_wat_parts(
    io: std.Io,
    allocator: std.mem.Allocator,
    input_path: []const u8,
    component_core: bool,
    p3_wait_for_component: bool,
    p3_async_map_component: bool,
    p3_resource_probe_component: bool,
    p3_wasi_filesystem_preopen_component: bool,
    p3_wasi_filesystem_stat_component: bool,
    p3_wasi_sockets_create_bind_drop_component: bool,
    p3_resource_async_component: bool,
    p3_async_component: bool,
    p3_async_call_component: bool,
    p3_async_host_arg_component: bool,
    p3_owned_future_component: bool,
    p3_async_component_v2: bool,
    p3_async_v2_scalar_i64_component: bool,
    gc_core: bool,
    host_export: bool,
    host_manifest_out: ?*std.ArrayList(u8),
    source: []const u8,
    tokens: []const lexer.Token,
    program: parser.Program,
    module_graph: *const imports.ModuleGraph,
    gc_host_route: ?*const GcSyncHostWitRoute,
) ![]u8 {
    if (requires_start_entry(host_export, p3_async_component or p3_async_map_component or p3_wasi_filesystem_stat_component or p3_async_call_component or p3_async_host_arg_component or p3_owned_future_component or p3_async_component_v2 or p3_async_v2_scalar_i64_component, p3_wasi_sockets_create_bind_drop_component) and
        !codegen.program_requires_async_lowering(program, tokens, module_graph))
    {
        entry.validate_start(program) catch |err| {
            try diag.print_compile_error(io, input_path, source, tokens, err, null);
            std.process.exit(1);
        };
    }

    return codegen.emit_wat_with_options(allocator, program, tokens, module_graph, .{
        .component_core = component_core,
        .p3_wait_for_component = p3_wait_for_component,
        .p3_async_map_component = p3_async_map_component,
        .p3_resource_probe_component = p3_resource_probe_component,
        .p3_wasi_filesystem_preopen_component = p3_wasi_filesystem_preopen_component,
        .p3_wasi_filesystem_stat_component = p3_wasi_filesystem_stat_component,
        .p3_wasi_sockets_create_bind_drop_component = p3_wasi_sockets_create_bind_drop_component,
        .p3_resource_async_component = p3_resource_async_component,
        .p3_async_component = p3_async_component,
        .p3_async_call_component = p3_async_call_component,
        .p3_async_host_arg_component = p3_async_host_arg_component,
        .p3_owned_future_component = p3_owned_future_component,
        .p3_async_component_v2 = p3_async_component_v2,
        .p3_async_v2_scalar_i64_component = p3_async_v2_scalar_i64_component,
        .gc_core = gc_core,
        .host_export = host_export,
        .host_manifest_out = host_manifest_out,
        .gc_sync_host_wit_route = gc_host_route,
    }) catch |err| {
        try diag.print_compile_error(io, input_path, source, tokens, err, null);
        std.process.exit(1);
    };
}

fn requires_start_entry(host_export: bool, p3_async_component: bool, p3_wasi_sockets_create_bind_drop_component: bool) bool {
    return !host_export and !p3_async_component and !p3_wasi_sockets_create_bind_drop_component;
}

const DepRoot = struct {
    path: []const u8,
    owned: bool,

    fn deinit(self: DepRoot, allocator: std.mem.Allocator) void {
        if (self.owned) allocator.free(self.path);
    }
};

fn resolve_dep_root(allocator: std.mem.Allocator, environ_map: *std.process.Environ.Map) !DepRoot {
    if (environ_map.get("DO_LIB_ROOT")) |path| {
        return .{ .path = path, .owned = false };
    }

    const home = environ_map.get("HOME") orelse ".";
    return .{
        .path = try std.fs.path.join(allocator, &.{ home, ".do", "lib" }),
        .owned = true,
    };
}

fn print_compile_ok(io: std.Io, parsed_cli: cli.Args, program: parser.Program) !void {
    var out_buffer: [1024]u8 = undefined;
    var out = std.Io.File.stdout().writer(io, &out_buffer);
    try out.interface.print(
        "ok: {s} -> {s} (tokens={d}, items={d})\n",
        .{ parsed_cli.input_path, parsed_cli.output_path, program.token_count, program.top_level_count },
    );
    try out.interface.flush();
}

fn print_compiled_test_ok(io: std.Io, parsed_cli: cli.Args, test_count: usize) !void {
    var out_buffer: [1024]u8 = undefined;
    var out = std.Io.File.stdout().writer(io, &out_buffer);
    try out.interface.print(
        "ok: {s} -> {s} (compiled_tests={d})\n",
        .{ parsed_cli.input_path, parsed_cli.output_path, test_count },
    );
    try out.interface.flush();
}

fn parser_error_loc() ?diag.SourceLoc {
    const site = parser.take_last_error_site() orelse return null;
    return .{ .line = site.line, .col = site.col };
}

fn sema_error_loc() ?diag.SourceLoc {
    const site = sema.take_last_error_site() orelse return null;
    return .{ .line = site.line, .col = site.col };
}

fn imports_error_loc() ?diag.SourceLoc {
    const site = imports.take_last_error_site() orelse return null;
    return .{ .line = site.line, .col = site.col };
}

test "normal program compile path still enforces start entry" {
    const allocator = std.testing.allocator;
    const source =
        \\fn helper() i32 {
        \\    return 1;
        \\}
        \\
    ;
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);

    var program = try parser.parse_program(allocator, tokens, source.len);
    defer program.deinit(allocator);

    try sema.check_program(allocator, program, tokens);
    try std.testing.expectError(error.MissingStartEntry, entry.validate_start(program));
}

test "p3 async component owns the WIT root instead of requiring start" {
    try std.testing.expect(!requires_start_entry(false, true, false));
    try std.testing.expect(requires_start_entry(false, false, false));
    try std.testing.expect(!requires_start_entry(true, false, false));
}

test "explicit GC WIT marshal dispatch uses the manifest adapter" {
    const source = @embedFile("test/compile_ok/565_gc_wit_managed_record_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    const wat = try emit_gc_wit_marshal_target(
        std.testing.io,
        std.testing.allocator,
        "..",
        codegen_gc_wit_marshal.managed_record_lower_descriptor,
        tokens,
    );
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "demo:marshal-record-managed-lower/api@1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(export \"run\" (func $run))") != null);
}

test "compiled GC fixture remains admitted after frontend and module loading" {
    const allocator = std.testing.allocator;
    const source = @embedFile("test/compiled_ok/49_compiled_test_storage_alias_set_keeps_old_value.do");
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);
    var program = try parser.parse_program(allocator, tokens, source.len);
    defer program.deinit(allocator);
    try sema.check_program(allocator, program, tokens);
    var graph = try imports.check_and_load(std.testing.io, allocator, "compiled-alias.do", tokens, "lib");
    defer graph.deinit();
    const wat = try codegen.emit_test_wat(allocator, program, tokens, &graph);
    defer allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; backend=gc") != null);
}

test "default GC host admission covers the verified multi-managed descriptors" {
    const lower = admitted_gc_host_descriptor(
        "demo:marshal-record-managed-lower-multi/api@1.0.0",
        "write",
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(
        codegen_gc_wit_host_boundary.managed_record_lower_multi_descriptor,
        lower,
    );

    const lift = admitted_gc_host_descriptor(
        "demo:marshal-record-managed-lift-multi/api@1.0.0",
        "read",
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(
        codegen_gc_wit_host_boundary.managed_record_lift_multi_descriptor,
        lift,
    );
    try std.testing.expect(
        admitted_gc_host_descriptor("demo:unadmitted/api@1.0.0", "write") == null,
    );
}

test "default GC host route rejects a known locator with a mismatched member" {
    const source = @embedFile("test/compile_err/590_gc_wit_nested_record_deeper_lower_host_boundary_mismatch.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectError(
        error.GcWitHostMemberMismatch,
        load_default_gc_host_route(std.testing.io, std.testing.allocator, "..", tokens),
    );
}

test "default GC host admission covers the C14 nested scalar descriptors" {
    const lower = admitted_gc_host_descriptor(
        "demo:marshal-record-nested-lower-deeper/api@1.0.0",
        "write",
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(
        codegen_gc_wit_host_boundary.nested_record_lower_deeper_descriptor,
        lower,
    );

    const lift = admitted_gc_host_descriptor(
        "demo:marshal-record-nested-lift-deeper/api@1.0.0",
        "read",
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(
        codegen_gc_wit_host_boundary.nested_record_lift_deeper_descriptor,
        lift,
    );
}

test "default GC host admission covers the mixed scalar lower descriptor" {
    const mixed = admitted_gc_host_descriptor(
        "demo:marshal-record-mixed-lower/api@1.0.0",
        "write",
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(
        codegen_gc_wit_host_boundary.mixed_record_lower_descriptor,
        mixed,
    );
}

test "default GC host admission covers the mixed scalar-list lower descriptor" {
    const descriptor = admitted_gc_host_descriptor(
        "demo:marshal-record-mixed-scalar-list-lower/api@1.0.0",
        "write",
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(
        codegen_gc_wit_host_boundary.mixed_scalar_list_lower_descriptor,
        descriptor,
    );
}

test "default GC host admission covers the mixed text u32-list lower descriptor" {
    const descriptor = admitted_gc_host_descriptor(
        "demo:marshal-record-mixed-text-u32-list-lower/api@1.0.0",
        "write",
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(
        codegen_gc_wit_host_boundary.mixed_text_u32_list_lower_descriptor,
        descriptor,
    );
}

test "default GC host admission covers the mixed text two-u32-list lower descriptor" {
    const descriptor = admitted_gc_host_descriptor(
        "demo:marshal-record-mixed-text-two-u32-lists-lower/api@1.0.0",
        "write",
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(
        codegen_gc_wit_host_boundary.mixed_text_two_u32_lists_lower_descriptor,
        descriptor,
    );
}

test "default GC host admission covers the mixed text byte-list lift descriptor" {
    const descriptor = admitted_gc_host_descriptor(
        "demo:marshal-record-mixed-text-byte-list-lift/api@1.0.0",
        "read",
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(
        codegen_gc_wit_host_boundary.mixed_text_byte_list_lift_descriptor,
        descriptor,
    );
}

test "default GC host admission covers the bounded byte-list lower descriptor" {
    const descriptor = admitted_gc_host_descriptor(
        "demo:marshal-record-byte-list-lower/api@1.0.0",
        "write",
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(
        "demo:marshal-record-byte-list-lower/api.write@1.0.0/lower",
        descriptor,
    );
}

test "default GC host admission covers the bounded u32-list lower descriptor" {
    const descriptor = admitted_gc_host_descriptor(
        "demo:marshal-record-u32-list-lower/api@1.0.0",
        "write",
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(
        codegen_gc_wit_host_boundary.record_u32_list_lower_descriptor,
        descriptor,
    );
}

test "default GC host admission covers the bounded u32-list lift descriptor" {
    const descriptor = admitted_gc_host_descriptor(
        "demo:marshal-record-u32-list-lift/api@1.0.0",
        "read",
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(
        codegen_gc_wit_host_boundary.record_u32_list_lift_descriptor,
        descriptor,
    );
}
