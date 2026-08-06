const std = @import("std");
const cli = @import("cli.zig");
const codegen = @import("codegen_api.zig");
const diag = @import("diag.zig");
const entry = @import("entry.zig");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const p3_http_wit_manifest = @import("p3_http_wit_manifest.zig");
const sema = @import("sema.zig");
const test_runner = @import("test_runner.zig");

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

pub fn run(init: std.process.Init, args: []const []const u8) !void {
    const allocator = init.gpa;
    const io = init.io;

    const parsed_cli = cli.parse_build(args) catch |err| {
        try diag.print_cli_error(io, err);
        std.process.exit(1);
    };

    var loaded = try load_program(init, parsed_cli.input_path);
    defer loaded.deinit(allocator);

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
    const wat = try compile_program_wat(io, allocator, parsed_cli.input_path, parsed_cli.component_core, parsed_cli.p3_wait_for_component, parsed_cli.p3_resource_probe_component, parsed_cli.p3_wasi_filesystem_preopen_component, parsed_cli.p3_wasi_sockets_create_bind_drop_component, parsed_cli.p3_resource_async_component, parsed_cli.p3_async_component, parsed_cli.gc_core, parsed_cli.host_export, if (parsed_cli.host_manifest_path != null) &host_manifest else null, &loaded);
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
        else if (parsed_cli.p3_wasi_filesystem_preopen_component)
            codegen.emit_p3_wasi_filesystem_preopen_wit(allocator, loaded.tokens)
        else if (parsed_cli.p3_wasi_sockets_create_bind_drop_component)
            codegen.emit_p3_wasi_sockets_create_bind_drop_wit(allocator, loaded.tokens)
        else if (parsed_cli.p3_resource_async_component)
            codegen.emit_p3_resource_async_wit(allocator, loaded.tokens)
        else if (parsed_cli.p3_async_component)
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

    sema.check_program(allocator, program, tokens) catch |err| {
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
    p3_resource_probe_component: bool,
    p3_wasi_filesystem_preopen_component: bool,
    p3_wasi_sockets_create_bind_drop_component: bool,
    p3_resource_async_component: bool,
    p3_async_component: bool,
    gc_core: bool,
    host_export: bool,
    host_manifest_out: ?*std.ArrayList(u8),
    loaded: *const LoadedProgram,
) ![]u8 {
    return compile_program_wat_parts(
        io,
        allocator,
        input_path,
        component_core,
        p3_wait_for_component,
        p3_resource_probe_component,
        p3_wasi_filesystem_preopen_component,
        p3_wasi_sockets_create_bind_drop_component,
        p3_resource_async_component,
        p3_async_component,
        gc_core,
        host_export,
        host_manifest_out,
        loaded.source,
        loaded.tokens,
        loaded.program,
        &loaded.module_graph,
    );
}

fn compile_program_wat_parts(
    io: std.Io,
    allocator: std.mem.Allocator,
    input_path: []const u8,
    component_core: bool,
    p3_wait_for_component: bool,
    p3_resource_probe_component: bool,
    p3_wasi_filesystem_preopen_component: bool,
    p3_wasi_sockets_create_bind_drop_component: bool,
    p3_resource_async_component: bool,
    p3_async_component: bool,
    gc_core: bool,
    host_export: bool,
    host_manifest_out: ?*std.ArrayList(u8),
    source: []const u8,
    tokens: []const lexer.Token,
    program: parser.Program,
    module_graph: *const imports.ModuleGraph,
) ![]u8 {
    if (requires_start_entry(host_export, p3_async_component, p3_wasi_sockets_create_bind_drop_component) and
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
        .p3_resource_probe_component = p3_resource_probe_component,
        .p3_wasi_filesystem_preopen_component = p3_wasi_filesystem_preopen_component,
        .p3_wasi_sockets_create_bind_drop_component = p3_wasi_sockets_create_bind_drop_component,
        .p3_resource_async_component = p3_resource_async_component,
        .p3_async_component = p3_async_component,
        .gc_core = gc_core,
        .host_export = host_export,
        .host_manifest_out = host_manifest_out,
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
    try std.testing.expect(!requires_start_entry(false, true));
    try std.testing.expect(requires_start_entry(false, false));
    try std.testing.expect(!requires_start_entry(true, false));
}
