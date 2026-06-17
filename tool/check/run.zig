const std = @import("std");
const cli = @import("../build/cli.zig");
const diag = @import("../build/diag.zig");
const env = @import("../env.zig");
const diagnostics = @import("../lsp/diagnostics.zig");

pub fn run(init: std.process.Init, args: []const []const u8) !void {
    const allocator = init.gpa;
    const io = init.io;

    const parsed = cli.parseCheck(args) catch |err| {
        try diag.printCliError(io, err);
        std.process.exit(1);
    };

    const source = std.Io.Dir.cwd().readFileAlloc(io, parsed.input_path, allocator, .limited(16 * 1024 * 1024)) catch |err| {
        try diag.printIoError(io, parsed.input_path, err);
        std.process.exit(1);
    };
    defer allocator.free(source);

    const dep_root = try env.resolveDepRoot(allocator, init.environ_map);
    defer dep_root.deinit(allocator);

    const collected = try diagnostics.collectDiagnostics(io, allocator, parsed.input_path, source, dep_root.path);
    defer allocator.free(collected);
    if (collected.len == 0) return;

    try diag.printDiagnostic(io, collected[0]);
    std.process.exit(1);
}

test "check uses shared diagnostics collector for valid source" {
    const source =
        \\test "ok" {
        \\    return
        \\}
        \\
    ;
    const collected = try diagnostics.collectDiagnostics(
        std.testing.io,
        std.testing.allocator,
        "mem://valid.do",
        source,
        "tool/build/test/lib",
    );
    defer std.testing.allocator.free(collected);

    try std.testing.expectEqual(@as(usize, 0), collected.len);
}
