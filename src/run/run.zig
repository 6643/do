const std = @import("std");
const cli = @import("../build/cli.zig");
const build_run = @import("../build/run.zig");
const diag = @import("../build/diag.zig");

pub fn run(init: std.process.Init, args: []const []const u8) !void {
    const allocator = init.gpa;
    const io = init.io;

    const parsed_cli = cli.parseRun(args) catch |err| {
        try diag.printCliError(io, err);
        std.process.exit(1);
    };

    const wasm_tools = findExecutable(allocator, io, init.environ_map, "wasm-tools") catch |err| {
        try printToolLookupError(io, "wasm-tools", err);
        std.process.exit(1);
    };
    defer allocator.free(wasm_tools);

    const node = findExecutable(allocator, io, init.environ_map, "node") catch |err| {
        try printToolLookupError(io, "node", err);
        std.process.exit(1);
    };
    defer allocator.free(node);

    var loaded = try build_run.loadProgram(init, parsed_cli.input_path);
    defer loaded.deinit(allocator);

    const wat = try build_run.compileProgramWat(io, allocator, parsed_cli.input_path, false, &loaded);
    defer allocator.free(wat);

    const tmp_root = init.environ_map.get("TMPDIR") orelse "/tmp";
    const tmp_suffix = std.hash.Wyhash.hash(0, parsed_cli.input_path);
    const pid = std.os.linux.getpid();
    const tmp_dir_name = try std.fmt.allocPrint(allocator, "do-run-{d}-{x}", .{ pid, tmp_suffix });
    defer allocator.free(tmp_dir_name);

    const tmp_dir_path = try std.fs.path.join(allocator, &.{ tmp_root, tmp_dir_name });
    defer allocator.free(tmp_dir_path);

    try std.Io.Dir.cwd().createDirPath(io, tmp_dir_path);
    defer std.Io.Dir.cwd().deleteTree(io, tmp_dir_path) catch {};

    const wat_path = try std.fs.path.join(allocator, &.{ tmp_dir_path, "out.wat" });
    defer allocator.free(wat_path);

    const wasm_path = try std.fs.path.join(allocator, &.{ tmp_dir_path, "out.wasm" });
    defer allocator.free(wasm_path);

    const runner_path = try std.Io.Dir.cwd().realPathFileAlloc(io, "src/run/run_wasm_program.mjs", allocator);
    defer allocator.free(runner_path);

    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = wat_path, .data = wat }) catch |err| {
        try diag.printIoError(io, wat_path, err);
        std.process.exit(1);
    };

    const parse_argv = [_][]const u8{ wasm_tools, "parse", wat_path, "-o", wasm_path };
    const parse_term = try spawnForwarding(io, &parse_argv);
    const parse_exit = exitCode(parse_term);
    if (parse_exit != 0) std.process.exit(parse_exit);

    const run_argv = [_][]const u8{ node, runner_path, wasm_path };
    const run_term = try spawnForwarding(io, &run_argv);
    std.process.exit(exitCode(run_term));
}

fn spawnForwarding(io: std.Io, argv: []const []const u8) !std.process.Child.Term {
    var child = try std.process.spawn(io, .{
        .argv = argv,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    return child.wait(io);
}

fn exitCode(term: std.process.Child.Term) u8 {
    return switch (term) {
        .exited => |code| code,
        .signal, .stopped, .unknown => 1,
    };
}

fn printToolLookupError(io: std.Io, name: []const u8, err: anyerror) !void {
    if (err != error.FileNotFound) {
        try diag.printIoError(io, name, err);
        return;
    }

    var err_buffer: [256]u8 = undefined;
    const msg = try formatMissingToolDiagnostic(&err_buffer, name);

    var out_buffer: [256]u8 = undefined;
    var out = std.Io.File.stderr().writer(io, &out_buffer);
    try out.interface.writeAll(msg);
    try out.interface.flush();
}

fn formatMissingToolDiagnostic(buffer: []u8, name: []const u8) ![]const u8 {
    return std.fmt.bufPrint(buffer, "error[MissingExternalTool]: {s} not found\n", .{name});
}

fn findExecutable(
    allocator: std.mem.Allocator,
    io: std.Io,
    environ_map: *std.process.Environ.Map,
    name: []const u8,
) ![]u8 {
    if (std.fs.path.isAbsolute(name)) {
        return allocator.dupe(u8, name);
    }

    const path_env = environ_map.get("PATH") orelse return error.FileNotFound;
    var it = std.mem.tokenizeScalar(u8, path_env, std.fs.path.delimiter);
    while (it.next()) |dir_path| {
        const candidate = try std.fs.path.join(allocator, &.{ dir_path, name });
        defer allocator.free(candidate);

        std.Io.Dir.cwd().access(io, candidate, .{ .execute = true }) catch |err| switch (err) {
            error.FileNotFound,
            error.AccessDenied,
            => continue,
            else => return err,
        };

        return allocator.dupe(u8, candidate);
    }

    return error.FileNotFound;
}

test "findExecutable preserves PATH launcher path instead of resolving symlink target" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const bin_dir = try tmp.dir.createDirPathOpen(io, "bin", .{});
    defer bin_dir.close(io);

    const target_path = "/bin/sh";
    try bin_dir.symLink(io, target_path, "node", .{});

    var env = std.process.Environ.Map.init(allocator);
    defer env.deinit();

    const bin_path = try tmp.dir.realPathFileAlloc(io, "bin", allocator);
    defer allocator.free(bin_path);
    try env.put("PATH", bin_path);

    const resolved = try findExecutable(allocator, io, &env, "node");
    defer allocator.free(resolved);

    const expected = try std.fs.path.join(allocator, &.{ bin_path, "node" });
    defer allocator.free(expected);

    try std.testing.expectEqualStrings(expected, resolved);
}

test "formatMissingToolDiagnostic prints explicit missing tool error" {
    var buffer: [128]u8 = undefined;
    const msg = try formatMissingToolDiagnostic(&buffer, "wasm-tools");

    try std.testing.expectEqualStrings("error[MissingExternalTool]: wasm-tools not found\n", msg);
}
