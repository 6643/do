const std = @import("std");

pub const EnvVar = struct {
    name: []const u8,
    value: []const u8,
};

pub const RunOptions = struct {
    argv: []const []const u8,
    environ: ?*const std.process.Environ.Map = null,
    env: []const EnvVar = &.{},
    cwd: ?[]const u8 = null,
    timeout_ms: ?u64 = null,
    stdout_limit: usize = 16 * 1024 * 1024,
    stderr_limit: usize = 16 * 1024 * 1024,
};

pub const CommandResult = struct {
    command: []u8,
    term: std.process.Child.Term,
    stdout: []u8,
    stderr: []u8,

    pub fn exit_code(self: CommandResult) ?u8 {
        return switch (self.term) {
            .exited => |code| code,
            .signal, .stopped, .unknown => null,
        };
    }

    pub fn succeeded(self: CommandResult) bool {
        return self.exit_code() == 0;
    }

    pub fn deinit(self: *CommandResult, allocator: std.mem.Allocator) void {
        allocator.free(self.command);
        allocator.free(self.stdout);
        allocator.free(self.stderr);
        self.* = undefined;
    }
};

pub const TempDir = struct {
    parent_dir: std.Io.Dir,
    dir: std.Io.Dir,
    sub_path: [16]u8,
    path: []u8,
    allocator: std.mem.Allocator,
    io: std.Io,
    cleaned: bool = false,

    pub fn cleanup(self: *TempDir) void {
        if (self.cleaned) return;
        self.dir.close(self.io);
        self.parent_dir.deleteTree(self.io, &self.sub_path) catch {};
        self.parent_dir.close(self.io);
        self.allocator.free(self.path);
        self.cleaned = true;
        self.* = undefined;
    }
};

pub fn run_checked(
    allocator: std.mem.Allocator,
    io: std.Io,
    options: RunOptions,
) !CommandResult {
    if (options.argv.len == 0) return error.InvalidArguments;
    for (options.env) |entry| {
        if (!std.process.Environ.Map.validateKeyForPut(entry.name)) {
            return error.InvalidEnvironmentKey;
        }
    }

    var environ_map: ?std.process.Environ.Map = null;
    if (options.environ) |base| {
        environ_map = try base.clone(allocator);
    } else if (options.env.len != 0) {
        environ_map = std.process.Environ.Map.init(allocator);
    }
    defer if (environ_map) |*map| map.deinit();

    if (environ_map) |*map| {
        for (options.env) |entry| try map.put(entry.name, entry.value);
    }

    const command = try std.mem.join(allocator, " ", options.argv);
    errdefer allocator.free(command);

    const run_result = try std.process.run(allocator, io, .{
        .argv = options.argv,
        .environ_map = if (environ_map) |*map| map else null,
        .cwd = if (options.cwd) |cwd| .{ .path = cwd } else .inherit,
        .timeout = if (options.timeout_ms) |timeout_ms|
            .{ .duration = .{
                .raw = std.Io.Duration.fromMilliseconds(@intCast(timeout_ms)),
                .clock = .awake,
            } }
        else
            .none,
        .stdout_limit = .limited(options.stdout_limit),
        .stderr_limit = .limited(options.stderr_limit),
    });

    return .{
        .command = command,
        .term = run_result.term,
        .stdout = run_result.stdout,
        .stderr = run_result.stderr,
    };
}

pub fn make_temp_dir(allocator: std.mem.Allocator, io: std.Io) !TempDir {
    var parent_dir = try std.Io.Dir.cwd().createDirPathOpen(io, ".zig-cache/tmp", .{});
    errdefer parent_dir.close(io);

    var sub_path: [16]u8 = undefined;
    var random_bytes: [12]u8 = undefined;
    var dir: ?std.Io.Dir = null;
    for (0..16) |_| {
        io.random(&random_bytes);
        _ = std.base64.url_safe.Encoder.encode(&sub_path, &random_bytes);
        const status = try parent_dir.createDirPathStatus(io, &sub_path, .default_dir);
        if (status == .existed) continue;
        dir = try parent_dir.openDir(io, &sub_path, .{});
        break;
    }
    const opened_dir = dir orelse return error.TempDirCollision;
    errdefer opened_dir.close(io);

    const cwd = try std.process.currentPathAlloc(io, allocator);
    defer allocator.free(cwd);
    const path = try std.fs.path.join(allocator, &.{ cwd, ".zig-cache", "tmp", sub_path[0..] });
    return .{
        .parent_dir = parent_dir,
        .dir = opened_dir,
        .sub_path = sub_path,
        .path = path,
        .allocator = allocator,
        .io = io,
    };
}

pub fn defer_cleanup(temp: *TempDir) CleanupGuard {
    return .{ .temp = temp };
}

pub const CleanupGuard = struct {
    temp: *TempDir,

    pub fn deinit(self: *CleanupGuard) void {
        self.temp.cleanup();
    }
};

pub fn assert_stdout_contains(result: CommandResult, needle: []const u8) !void {
    if (std.mem.indexOf(u8, result.stdout, needle) == null) return error.StdoutMissing;
}

pub fn assert_stderr_contains(result: CommandResult, needle: []const u8) !void {
    if (std.mem.indexOf(u8, result.stderr, needle) == null) return error.StderrMissing;
}

pub fn assert_exit_code(result: CommandResult, expected: u8) !void {
    if (result.exit_code() != expected) return error.UnexpectedExitCode;
}

pub fn failure_report(allocator: std.mem.Allocator, result: CommandResult) ![]u8 {
    const redacted_stderr = try redact_stderr(allocator, result.stderr);
    defer allocator.free(redacted_stderr);
    return std.fmt.allocPrint(allocator, "command={s} term={s} exit={d} stderr={s}", .{
        result.command,
        @tagName(result.term),
        result.exit_code() orelse 255,
        redacted_stderr,
    });
}

fn redact_stderr(allocator: std.mem.Allocator, stderr: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var line_start: usize = 0;
    while (line_start <= stderr.len) {
        const line_end = std.mem.indexOfScalarPos(u8, stderr, line_start, '\n') orelse stderr.len;
        const line = stderr[line_start..line_end];
        const sensitive = std.mem.indexOfAny(u8, line, "\x00") != null or
            contains_sensitive_marker(line);
        try out.appendSlice(allocator, if (sensitive) "[redacted]" else line);
        if (line_end == stderr.len) break;
        try out.append(allocator, '\n');
        line_start = line_end + 1;
    }
    return out.toOwnedSlice(allocator);
}

fn contains_sensitive_marker(line: []const u8) bool {
    const markers = [_][]const u8{
        "TOKEN=", "SECRET=", "PASSWORD=", "API_KEY=", "AUTHORIZATION:",
    };
    for (markers) |marker| {
        if (std.mem.indexOf(u8, line, marker) != null) return true;
    }
    return false;
}

test "process helper captures successful stdout and stderr" {
    const argv = [_][]const u8{ "/bin/sh", "-c", "printf out; printf err >&2" };
    var result = try run_checked(std.testing.allocator, std.testing.io, .{ .argv = &argv });
    defer result.deinit(std.testing.allocator);

    try assert_exit_code(result, 0);
    try assert_stdout_contains(result, "out");
    try assert_stderr_contains(result, "err");
}

test "process helper preserves a nonzero exit status" {
    const argv = [_][]const u8{ "/bin/sh", "-c", "printf failed >&2; exit 7" };
    var result = try run_checked(std.testing.allocator, std.testing.io, .{ .argv = &argv });
    defer result.deinit(std.testing.allocator);

    try assert_exit_code(result, 7);
    try assert_stderr_contains(result, "failed");
}

test "process helper injects environment variables" {
    const argv = [_][]const u8{ "/bin/sh", "-c", "printf '%s' \"$DO_HARNESS_TEST\"" };
    const env = [_]EnvVar{.{ .name = "DO_HARNESS_TEST", .value = "injected" }};
    var result = try run_checked(std.testing.allocator, std.testing.io, .{ .argv = &argv, .env = &env });
    defer result.deinit(std.testing.allocator);

    try assert_exit_code(result, 0);
    try std.testing.expectEqualStrings("injected", result.stdout);
}

test "process helper overrides an inherited environment variable" {
    var base = std.process.Environ.Map.init(std.testing.allocator);
    defer base.deinit();
    try base.put("DO_HARNESS_TEST", "base");
    const argv = [_][]const u8{ "/bin/sh", "-c", "printf '%s' \"$DO_HARNESS_TEST\"" };
    const env = [_]EnvVar{.{ .name = "DO_HARNESS_TEST", .value = "override" }};
    var result = try run_checked(std.testing.allocator, std.testing.io, .{
        .argv = &argv,
        .environ = &base,
        .env = &env,
    });
    defer result.deinit(std.testing.allocator);

    try assert_exit_code(result, 0);
    try std.testing.expectEqualStrings("override", result.stdout);
}

test "process helper terminates a timed out child" {
    const argv = [_][]const u8{ "/bin/sh", "-c", "sleep 1" };
    try std.testing.expectError(
        error.Timeout,
        run_checked(std.testing.allocator, std.testing.io, .{ .argv = &argv, .timeout_ms = 100 }),
    );
}

test "process helper cleans its temporary directory" {
    var temp = try make_temp_dir(std.testing.allocator, std.testing.io);
    const path = temp.path;
    var guard = defer_cleanup(&temp);
    defer guard.deinit();

    const marker = try std.fs.path.join(std.testing.allocator, &.{ path, "marker" });
    defer std.testing.allocator.free(marker);
    const argv = [_][]const u8{ "/bin/sh", "-c", "touch marker" };
    var result = try run_checked(std.testing.allocator, std.testing.io, .{ .argv = &argv, .cwd = path });
    defer result.deinit(std.testing.allocator);

    try assert_exit_code(result, 0);
    const stat = try std.Io.Dir.cwd().statFile(std.testing.io, marker, .{});
    _ = stat;
}
