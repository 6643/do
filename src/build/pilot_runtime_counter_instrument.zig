const std = @import("std");
const counters = @import("codegen_component_producer_runtime_counters.zig");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3) {
        try write_stderr(init.io, "usage: pilot_runtime_counter_instrument <input.wat> <output.wat>\n");
        std.process.exit(2);
    }

    const input = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], init.gpa, .limited(16 * 1024 * 1024));
    defer init.gpa.free(input);
    const instrumented = counters.instrument(init.gpa, input) catch |err| {
        try write_stderr(init.io, "instrumentation failed: ");
        try write_stderr(init.io, @errorName(err));
        try write_stderr(init.io, "\n");
        std.process.exit(1);
    };
    defer init.gpa.free(instrumented);

    var file = try std.Io.Dir.cwd().createFile(init.io, args[2], .{});
    defer file.close(init.io);
    var buffer: [4096]u8 = undefined;
    var writer = file.writer(init.io, &buffer);
    try writer.interface.writeAll(instrumented);
    try writer.interface.flush();
}

fn write_stderr(io: std.Io, bytes: []const u8) !void {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.File.stderr().writer(io, &buffer);
    try writer.interface.writeAll(bytes);
    try writer.interface.flush();
}
