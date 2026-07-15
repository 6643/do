const std = @import("std");
const cli = @import("../build/cli.zig");
const diag = @import("../build/diag.zig");
const diagnostics = @import("../build/diagnostics.zig");
const env = @import("../env.zig");

pub fn run(init: std.process.Init, args: []const []const u8) !void {
    const allocator = init.gpa;
    const io = init.io;

    const parsed = cli.parse_check(args) catch |err| {
        try diag.print_cli_error(io, err);
        std.process.exit(1);
    };

    const dep_root = try env.resolve_dep_root(allocator, init.environ_map);
    defer dep_root.deinit(allocator);

    var err_buffer: [4096]u8 = undefined;
    var err_writer = std.Io.File.stderr().writer(io, &err_buffer);
    const failed = try check_paths(io, allocator, std.Io.Dir.cwd(), parsed.input_paths, dep_root.path, &err_writer.interface, true);
    try err_writer.interface.flush();
    if (failed) std.process.exit(1);
}

fn check_paths(
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
            if (emit_diagnostics) try diag.write_io_error_to(diagnostics_writer, input_path, err);
            failed = true;
            continue;
        };
        defer allocator.free(source);

        const collected = try diagnostics.collect_diagnostics(io, allocator, input_path, source, dep_root);
        defer allocator.free(collected);
        if (collected.len == 0) continue;

        if (emit_diagnostics) try diag.write_diagnostic_to(diagnostics_writer, collected[0]);
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
    const collected = try diagnostics.collect_diagnostics(
        std.testing.io,
        std.testing.allocator,
        "mem://valid.do",
        source,
        "src/build/test/lib",
    );
    defer std.testing.allocator.free(collected);

    try std.testing.expectEqual(@as(usize, 0), collected.len);
}

test "check_paths checks all inputs and reports failure status" {
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
    const failed = try check_paths(std.testing.io, std.testing.allocator, tmp.dir, &paths, "src/build/test/lib", &out.writer, false);
    try std.testing.expect(failed);
}
