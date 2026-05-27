const std = @import("std");
const cli = @import("cli.zig");
const codegen = @import("codegen.zig");
const diag = @import("diag.zig");
const entry = @import("entry.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema = @import("sema.zig");
const test_runner = @import("test_runner.zig");

pub fn run(init: std.process.Init, args: []const []const u8) !void {
    const allocator = init.gpa;
    const io = init.io;

    const parsed_cli = cli.parseBuild(args) catch |err| {
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

    try compileProgram(io, allocator, parsed_cli, source, tokens, program);
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

    try runTests(io, allocator, parsed_cli, source, tokens);
}

fn compileProgram(
    io: std.Io,
    allocator: std.mem.Allocator,
    parsed_cli: cli.Args,
    source: []const u8,
    tokens: []const lexer.Token,
    program: parser.Program,
) !void {
    entry.validateStart(program) catch |err| {
        try diag.printCompileError(io, parsed_cli.input_path, source, tokens, err, null);
        std.process.exit(1);
    };

    const wat = codegen.emitWat(allocator, program) catch |err| {
        try diag.printCompileError(io, parsed_cli.input_path, source, tokens, err, null);
        std.process.exit(1);
    };
    defer allocator.free(wat);

    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = parsed_cli.output_path, .data = wat }) catch |err| {
        try diag.printIoError(io, parsed_cli.output_path, err);
        std.process.exit(1);
    };

    try printCompileOk(io, parsed_cli, program);
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

fn printCompileOk(io: std.Io, parsed_cli: cli.Args, program: parser.Program) !void {
    var out_buffer: [1024]u8 = undefined;
    var out = std.Io.File.stdout().writer(io, &out_buffer);
    try out.interface.print(
        "ok: {s} -> {s} (tokens={d}, items={d})\n",
        .{ parsed_cli.input_path, parsed_cli.output_path, program.token_count, program.top_level_count },
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
