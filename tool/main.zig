const std = @import("std");
const build_cmd = @import("build/run.zig");

const Command = enum {
    build,
    test_cmd,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len < 2) {
        try printUsage(io);
        return;
    }

    const command = parseCommand(args[1]) catch |err| {
        try printCommandError(io, err);
        std.process.exit(1);
    };

    switch (command) {
        .build => try build_cmd.run(init, args[1..]),
        .test_cmd => try build_cmd.runTest(init, args[1..]),
    }
}

fn parseCommand(name: []const u8) !Command {
    if (std.mem.eql(u8, name, "build")) return .build;
    if (std.mem.eql(u8, name, "test")) return .test_cmd;
    return error.UnknownCommand;
}

fn printUsage(io: std.Io) !void {
    var out_buffer: [384]u8 = undefined;
    var out = std.Io.File.stdout().writer(io, &out_buffer);
    try out.interface.print(
        \\do toolchain
        \\usage:
        \\  do build <input.do> [-o out.wat]
        \\  do test <input.do>
        \\
    , .{});
    try out.interface.flush();
}

fn printCommandError(io: std.Io, err: anyerror) !void {
    var err_buffer: [512]u8 = undefined;
    var out = std.Io.File.stderr().writer(io, &err_buffer);
    try out.interface.print("error[{s}]: 命令语法: `do build ...` 或 `do test ...`\n", .{ @errorName(err) });
    try out.interface.flush();
}
