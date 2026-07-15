const std = @import("std");
const build_diag = @import("diag.zig");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema = @import("sema.zig");

pub const Diagnostic = build_diag.CompileDiagnostic;

/// Front-end analyze path for check/LSP: lexer → parser → sema → imports.
/// Returns zero diagnostics on success, or a single fail-fast diagnostic.
pub fn collect_diagnostics(
    io: std.Io,
    allocator: std.mem.Allocator,
    path: []const u8,
    source: []const u8,
    dep_root: []const u8,
) ![]Diagnostic {
    const tokens = lexer.tokenize(allocator, source) catch |err| {
        return one(allocator, build_diag.build_compile_diagnostic(path, source, null, err, null));
    };
    defer allocator.free(tokens);

    var program = parser.parse_program(allocator, tokens, source.len) catch |err| {
        return one(allocator, build_diag.build_compile_diagnostic(path, source, tokens, err, parser_error_loc()));
    };
    defer program.deinit(allocator);

    sema.check_program(allocator, program, tokens) catch |err| {
        return one(allocator, build_diag.build_compile_diagnostic(path, source, tokens, err, sema_error_loc()));
    };

    var module_graph = imports.check_and_load(io, allocator, path, tokens, dep_root) catch |err| {
        return one(allocator, build_diag.build_compile_diagnostic(path, source, tokens, err, imports_error_loc()));
    };
    module_graph.deinit();

    return allocator.alloc(Diagnostic, 0);
}

fn one(allocator: std.mem.Allocator, diagnostic: Diagnostic) ![]Diagnostic {
    const diagnostics = try allocator.alloc(Diagnostic, 1);
    diagnostics[0] = diagnostic;
    return diagnostics;
}

fn parser_error_loc() ?build_diag.SourceLoc {
    const site = parser.take_last_error_site() orelse return null;
    return .{ .line = site.line, .col = site.col };
}

fn sema_error_loc() ?build_diag.SourceLoc {
    const site = sema.take_last_error_site() orelse return null;
    return .{ .line = site.line, .col = site.col };
}

fn imports_error_loc() ?build_diag.SourceLoc {
    const site = imports.take_last_error_site() orelse return null;
    return .{ .line = site.line, .col = site.col };
}

test "collect_diagnostics returns empty list for valid test source" {
    const source =
        \\test "ok" {
        \\    return
        \\}
        \\
    ;
    const diagnostics = try collect_diagnostics(
        std.testing.io,
        std.testing.allocator,
        "mem://valid.do",
        source,
        "src/build/test/lib",
    );
    defer std.testing.allocator.free(diagnostics);
    try std.testing.expectEqual(@as(usize, 0), diagnostics.len);
}

test "collect_diagnostics reports lexer error without printing or exiting" {
    const diagnostics = try collect_diagnostics(
        std.testing.io,
        std.testing.allocator,
        "mem://bad.do",
        "\"abc",
        "src/build/test/lib",
    );
    defer std.testing.allocator.free(diagnostics);
    try std.testing.expectEqual(@as(usize, 1), diagnostics.len);
    try std.testing.expectEqualStrings("UnterminatedString", diagnostics[0].code);
    try std.testing.expectEqual(@as(usize, 1), diagnostics[0].loc.line);
    try std.testing.expectEqual(@as(usize, 1), diagnostics[0].loc.col);
}
