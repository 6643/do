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

    const source = std.Io.Dir.cwd().readFileAlloc(io, parsed.input_path, allocator, .limited(16 * 1024 * 1024)) catch |err| {
        try diag.printIoError(io, parsed.input_path, err);
        std.process.exit(1);
    };
    defer allocator.free(source);

    const formatted = formatter.formatSource(allocator, source) catch |err| {
        try diag.printIoError(io, parsed.input_path, err);
        std.process.exit(1);
    };
    defer allocator.free(formatted);

    if (parsed.check) {
        if (std.mem.eql(u8, source, formatted)) return;
        try diag.printCliError(io, error.FormatMismatch);
        std.process.exit(1);
    }

    var out_buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(io, &out_buffer);
    try out.interface.writeAll(formatted);
    try out.interface.flush();
}
