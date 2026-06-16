const std = @import("std");
const cli = @import("cli.zig");
const codegen = @import("codegen.zig");
const diag = @import("diag.zig");
const entry = @import("entry.zig");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
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

    const parsed_cli = cli.parseBuild(args) catch |err| {
        try diag.printCliError(io, err);
        std.process.exit(1);
    };

    var loaded = try loadProgram(init, parsed_cli.input_path);
    defer loaded.deinit(allocator);

    const wat = try compileProgramWat(io, allocator, parsed_cli.input_path, parsed_cli.component_core, &loaded);
    defer allocator.free(wat);

    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = parsed_cli.output_path, .data = wat }) catch |err| {
        try diag.printIoError(io, parsed_cli.output_path, err);
        std.process.exit(1);
    };

    try printCompileOk(io, parsed_cli, loaded.program);
}

pub fn runTest(init: std.process.Init, args: []const []const u8) !void {
    const allocator = init.gpa;
    const io = init.io;

    const parsed_cli = cli.parseTest(args) catch |err| {
        try diag.printCliError(io, err);
        std.process.exit(1);
    };

    const source = std.Io.Dir.cwd().readFileAlloc(io, parsed_cli.input_path, allocator, .limited(16 * 1024 * 1024)) catch |err| {
        try diag.printIoError(io, parsed_cli.input_path, err);
        std.process.exit(1);
    };
    defer allocator.free(source);

    const tokens = lexer.tokenize(allocator, source) catch |err| {
        try diag.printCompileError(io, parsed_cli.input_path, source, null, err, null);
        std.process.exit(1);
    };
    defer allocator.free(tokens);

    var program = parser.parseProgram(allocator, tokens, source.len) catch |err| {
        try diag.printCompileError(io, parsed_cli.input_path, source, tokens, err, parserErrorLoc());
        std.process.exit(1);
    };
    defer program.deinit(allocator);

    sema.checkProgram(allocator, program, tokens) catch |err| {
        try diag.printCompileError(io, parsed_cli.input_path, source, tokens, err, semaErrorLoc());
        std.process.exit(1);
    };

    const dep_root = try resolveDepRoot(allocator, init.environ_map);
    defer dep_root.deinit(allocator);

    var module_graph = imports.checkAndLoad(io, allocator, parsed_cli.input_path, tokens, dep_root.path) catch |err| {
        try diag.printCompileError(io, parsed_cli.input_path, source, tokens, err, importsErrorLoc());
        std.process.exit(1);
    };
    defer module_graph.deinit();

    if (parsed_cli.compiled_test) {
        try compileTests(io, allocator, parsed_cli, source, tokens, program, &module_graph);
    } else {
        try runTests(io, allocator, parsed_cli, source, tokens);
    }
}

fn runTests(
    io: std.Io,
    allocator: std.mem.Allocator,
    parsed_cli: cli.Args,
    source: []const u8,
    tokens: []const lexer.Token,
) !void {
    test_runner.run(io, allocator, tokens) catch |err| {
        try diag.printCompileError(io, parsed_cli.input_path, source, tokens, err, null);
        std.process.exit(1);
    };
}

fn compileTests(
    io: std.Io,
    allocator: std.mem.Allocator,
    parsed_cli: cli.Args,
    source: []const u8,
    tokens: []const lexer.Token,
    program: parser.Program,
    module_graph: *const imports.ModuleGraph,
) !void {
    const test_decls = test_runner.collectTopLevelTests(allocator, tokens) catch |err| {
        try diag.printCompileError(io, parsed_cli.input_path, source, tokens, err, null);
        std.process.exit(1);
    };
    defer allocator.free(test_decls);
    if (test_decls.len == 0) {
        try diag.printCompileError(io, parsed_cli.input_path, source, tokens, error.NoTestDecl, null);
        std.process.exit(1);
    }

    const wat = codegen.emitTestWat(allocator, program, tokens, module_graph) catch |err| {
        try diag.printCompileError(io, parsed_cli.input_path, source, tokens, err, null);
        std.process.exit(1);
    };
    defer allocator.free(wat);

    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = parsed_cli.output_path, .data = wat }) catch |err| {
        try diag.printIoError(io, parsed_cli.output_path, err);
        std.process.exit(1);
    };

    try printCompiledTestOk(io, parsed_cli, test_decls.len);
}

pub fn loadProgram(init: std.process.Init, input_path: []const u8) !LoadedProgram {
    const allocator = init.gpa;
    const io = init.io;

    const source = std.Io.Dir.cwd().readFileAlloc(io, input_path, allocator, .limited(16 * 1024 * 1024)) catch |err| {
        try diag.printIoError(io, input_path, err);
        std.process.exit(1);
    };
    errdefer allocator.free(source);

    const tokens = lexer.tokenize(allocator, source) catch |err| {
        try diag.printCompileError(io, input_path, source, null, err, null);
        std.process.exit(1);
    };
    errdefer allocator.free(tokens);

    var program = parser.parseProgram(allocator, tokens, source.len) catch |err| {
        try diag.printCompileError(io, input_path, source, tokens, err, parserErrorLoc());
        std.process.exit(1);
    };
    errdefer program.deinit(allocator);

    sema.checkProgram(allocator, program, tokens) catch |err| {
        try diag.printCompileError(io, input_path, source, tokens, err, semaErrorLoc());
        std.process.exit(1);
    };

    const dep_root = try resolveDepRoot(allocator, init.environ_map);
    defer dep_root.deinit(allocator);

    var module_graph = imports.checkAndLoad(io, allocator, input_path, tokens, dep_root.path) catch |err| {
        try diag.printCompileError(io, input_path, source, tokens, err, importsErrorLoc());
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

pub fn compileProgramWat(
    io: std.Io,
    allocator: std.mem.Allocator,
    input_path: []const u8,
    component_core: bool,
    loaded: *const LoadedProgram,
) ![]u8 {
    return compileProgramWatParts(
        io,
        allocator,
        input_path,
        component_core,
        loaded.source,
        loaded.tokens,
        loaded.program,
        &loaded.module_graph,
    );
}

fn compileProgramWatParts(
    io: std.Io,
    allocator: std.mem.Allocator,
    input_path: []const u8,
    component_core: bool,
    source: []const u8,
    tokens: []const lexer.Token,
    program: parser.Program,
    module_graph: *const imports.ModuleGraph,
) ![]u8 {
    entry.validateStart(program) catch |err| {
        try diag.printCompileError(io, input_path, source, tokens, err, null);
        std.process.exit(1);
    };

    return codegen.emitWatWithOptions(allocator, program, tokens, module_graph, .{
        .component_core = component_core,
    }) catch |err| {
        try diag.printCompileError(io, input_path, source, tokens, err, null);
        std.process.exit(1);
    };
}

const DepRoot = struct {
    path: []const u8,
    owned: bool,

    fn deinit(self: DepRoot, allocator: std.mem.Allocator) void {
        if (self.owned) allocator.free(self.path);
    }
};

fn resolveDepRoot(allocator: std.mem.Allocator, environ_map: *std.process.Environ.Map) !DepRoot {
    if (environ_map.get("DO_LIB_ROOT")) |path| {
        return .{ .path = path, .owned = false };
    }

    const home = environ_map.get("HOME") orelse ".";
    return .{
        .path = try std.fs.path.join(allocator, &.{ home, ".do", "lib" }),
        .owned = true,
    };
}

fn printCompileOk(io: std.Io, parsed_cli: cli.Args, program: parser.Program) !void {
    var out_buffer: [1024]u8 = undefined;
    var out = std.Io.File.stdout().writer(io, &out_buffer);
    try out.interface.print(
        "ok: {s} -> {s} (tokens={d}, items={d})\n",
        .{ parsed_cli.input_path, parsed_cli.output_path, program.token_count, program.top_level_count },
    );
    try out.interface.flush();
}

fn printCompiledTestOk(io: std.Io, parsed_cli: cli.Args, test_count: usize) !void {
    var out_buffer: [1024]u8 = undefined;
    var out = std.Io.File.stdout().writer(io, &out_buffer);
    try out.interface.print(
        "ok: {s} -> {s} (compiled_tests={d})\n",
        .{ parsed_cli.input_path, parsed_cli.output_path, test_count },
    );
    try out.interface.flush();
}

fn parserErrorLoc() ?diag.SourceLoc {
    const site = parser.takeLastErrorSite() orelse return null;
    return .{ .line = site.line, .col = site.col };
}

fn semaErrorLoc() ?diag.SourceLoc {
    const site = sema.takeLastErrorSite() orelse return null;
    return .{ .line = site.line, .col = site.col };
}

fn importsErrorLoc() ?diag.SourceLoc {
    const site = imports.takeLastErrorSite() orelse return null;
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

    var program = try parser.parseProgram(allocator, tokens, source.len);
    defer program.deinit(allocator);

    try sema.checkProgram(allocator, program, tokens);
    try std.testing.expectError(error.MissingStartEntry, entry.validateStart(program));
}
