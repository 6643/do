const std = @import("std");
const build_diag = @import("../build/diag.zig");
const imports = @import("../build/imports.zig");
const lexer = @import("../build/lexer.zig");
const parser = @import("../build/parser.zig");
const sema = @import("../build/sema.zig");

pub const Diagnostic = build_diag.CompileDiagnostic;

pub fn collectDiagnostics(
    io: std.Io,
    allocator: std.mem.Allocator,
    path: []const u8,
    source: []const u8,
    dep_root: []const u8,
) ![]Diagnostic {
    const tokens = lexer.tokenize(allocator, source) catch |err| {
        return one(allocator, build_diag.buildCompileDiagnostic(path, source, null, err, null));
    };
    defer allocator.free(tokens);

    var program = parser.parseProgram(allocator, tokens, source.len) catch |err| {
        return one(allocator, build_diag.buildCompileDiagnostic(path, source, tokens, err, parserErrorLoc()));
    };
    defer program.deinit(allocator);

    sema.checkProgram(allocator, program, tokens) catch |err| {
        return one(allocator, build_diag.buildCompileDiagnostic(path, source, tokens, err, semaErrorLoc()));
    };

    var module_graph = imports.checkAndLoad(io, allocator, path, tokens, dep_root) catch |err| {
        return one(allocator, build_diag.buildCompileDiagnostic(path, source, tokens, err, importsErrorLoc()));
    };
    module_graph.deinit();

    return allocator.alloc(Diagnostic, 0);
}

fn one(allocator: std.mem.Allocator, diagnostic: Diagnostic) ![]Diagnostic {
    const diagnostics = try allocator.alloc(Diagnostic, 1);
    diagnostics[0] = diagnostic;
    return diagnostics;
}

fn parserErrorLoc() ?build_diag.SourceLoc {
    const site = parser.takeLastErrorSite() orelse return null;
    return .{ .line = site.line, .col = site.col };
}

fn semaErrorLoc() ?build_diag.SourceLoc {
    const site = sema.takeLastErrorSite() orelse return null;
    return .{ .line = site.line, .col = site.col };
}

fn importsErrorLoc() ?build_diag.SourceLoc {
    const site = imports.takeLastErrorSite() orelse return null;
    return .{ .line = site.line, .col = site.col };
}

test "collectDiagnostics returns empty list for valid test source" {
    const source =
        \\test "ok" {
        \\    return
        \\}
        \\
    ;
    const diagnostics = try collectDiagnostics(
        std.testing.io,
        std.testing.allocator,
        "mem://valid.do",
        source,
        "tool/build/test/lib",
    );
    defer std.testing.allocator.free(diagnostics);
    try std.testing.expectEqual(@as(usize, 0), diagnostics.len);
}

test "collectDiagnostics reports lexer error without printing or exiting" {
    const diagnostics = try collectDiagnostics(
        std.testing.io,
        std.testing.allocator,
        "mem://bad.do",
        "\"abc",
        "tool/build/test/lib",
    );
    defer std.testing.allocator.free(diagnostics);
    try std.testing.expectEqual(@as(usize, 1), diagnostics.len);
    try std.testing.expectEqualStrings("UnterminatedString", diagnostics[0].code);
    try std.testing.expectEqual(@as(usize, 1), diagnostics[0].loc.line);
    try std.testing.expectEqual(@as(usize, 1), diagnostics[0].loc.col);
}
