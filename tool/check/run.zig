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

    const dep_root = try env.resolveDepRoot(allocator, init.environ_map);
    defer dep_root.deinit(allocator);

    var err_buffer: [4096]u8 = undefined;
    var err_writer = std.Io.File.stderr().writer(io, &err_buffer);
    const failed = try checkPaths(io, allocator, std.Io.Dir.cwd(), parsed.input_paths, dep_root.path, &err_writer.interface, true);
    try err_writer.interface.flush();
    if (failed) std.process.exit(1);
}

fn checkPaths(
    io: std.Io,
    allocator: std.mem.Allocator,
    dir: std.Io.Dir,
    input_paths: []const []const u8,
    dep_root: []const u8,
    diagnostics_writer: anytype,
    emit_diagnostics: bool,
) !bool {
    var failed = false;
    for (input_paths) |input_path| {
        const source = dir.readFileAlloc(io, input_path, allocator, .limited(16 * 1024 * 1024)) catch |err| {
            if (emit_diagnostics) try diag.writeIoErrorTo(diagnostics_writer, input_path, err);
            failed = true;
            continue;
        };
        defer allocator.free(source);

        const collected = try diagnostics.collectDiagnostics(io, allocator, input_path, source, dep_root);
        defer allocator.free(collected);
        if (collected.len == 0) continue;

        if (emit_diagnostics) try diag.writeDiagnosticTo(diagnostics_writer, collected[0]);
        failed = true;
    }
    return failed;
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

test "checkPaths checks all inputs and reports failure status" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "bad.do",
        .data = "test \"bad",
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "ok.do",
        .data =
            \\test "ok" {
            \\    return
            \\}
            \\
        ,
    });

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    const paths = [_][]const u8{ "bad.do", "ok.do" };
    const failed = try checkPaths(std.testing.io, std.testing.allocator, tmp.dir, &paths, "tool/build/test/lib", &out.writer, false);
    try std.testing.expect(failed);
}
