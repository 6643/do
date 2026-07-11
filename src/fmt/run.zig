const std = @import("std");
const cli = @import("../build/cli.zig");
const diag = @import("../build/diag.zig");
const formatter = @import("format.zig");

pub fn run(init: std.process.Init, args: []const []const u8) !void {
    const allocator = init.gpa;
    const io = init.io;

    const parsed = cli.parseFmt(args) catch |err| {
        try diag.printCliError(io, err);
        std.process.exit(1);
    };

    var out_buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(io, &out_buffer);
    formatPath(io, allocator, std.Io.Dir.cwd(), parsed.input_path, .{ .check = parsed.check, .write = parsed.write }, &out.interface) catch |err| {
        switch (err) {
            error.FormatMismatch => try diag.printCliError(io, err),
            else => try diag.printIoError(io, parsed.input_path, err),
        }
        std.process.exit(1);
    };
    try out.interface.flush();
}

const FormatMode = struct {
    check: bool = false,
    write: bool = false,
};

fn formatPath(
    io: std.Io,
    allocator: std.mem.Allocator,
    dir: std.Io.Dir,
    input_path: []const u8,
    mode: FormatMode,
    writer: anytype,
) !void {
    const source = try dir.readFileAlloc(io, input_path, allocator, .limited(16 * 1024 * 1024));
    defer allocator.free(source);

    const formatted = try formatter.formatSource(allocator, source);
    defer allocator.free(formatted);

    if (mode.check) {
        if (std.mem.eql(u8, source, formatted)) return;
        return error.FormatMismatch;
    }

    if (mode.write) {
        try dir.writeFile(io, .{ .sub_path = input_path, .data = formatted });
        return;
    }

    try writer.writeAll(formatted);
}

test "formatPath write mode rewrites file and emits no stdout" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "app.do",
        .data = "User {\nid i32\n}",
    });

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try formatPath(
        std.testing.io,
        std.testing.allocator,
        tmp.dir,
        "app.do",
        .{ .write = true },
        &out.writer,
    );

    const rewritten = try tmp.dir.readFileAlloc(std.testing.io, "app.do", std.testing.allocator, .limited(1024));
    defer std.testing.allocator.free(rewritten);

    try std.testing.expectEqualStrings("User {\n    id i32\n}\n", rewritten);
    try std.testing.expectEqual(@as(usize, 0), out.writer.buffered().len);
}
