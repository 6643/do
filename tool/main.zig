const std = @import("std");
const build_cmd = @import("build/run.zig");
const fmt_cmd = @import("fmt/run.zig");
const run_cmd = @import("run/run.zig");

const Command = enum {
    build,
    test_cmd,
    run,
    fmt,
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
        .run => try run_cmd.run(init, args[1..]),
        .fmt => try fmt_cmd.run(init, args[1..]),
    }
}

fn parseCommand(name: []const u8) !Command {
    if (std.mem.eql(u8, name, "build")) return .build;
    if (std.mem.eql(u8, name, "test")) return .test_cmd;
    if (std.mem.eql(u8, name, "run")) return .run;
    if (std.mem.eql(u8, name, "fmt")) return .fmt;
    return error.UnknownCommand;
}

fn printUsage(io: std.Io) !void {
    var out_buffer: [384]u8 = undefined;
    var out = std.Io.File.stdout().writer(io, &out_buffer);
    try out.interface.print(
        \\do toolchain
        \\usage:
        \\  do build <input.do> [--component-core] [-o out.wat]
        \\  do test <input.do>
        \\  do test <input.do> --compiled [-o out.wat]
        \\  do run <input.do>
        \\  do fmt <input.do>
        \\  do fmt --check <input.do>
        \\
    , .{});
    try out.interface.flush();
}

fn printCommandError(io: std.Io, err: anyerror) !void {
    var err_buffer: [512]u8 = undefined;
    var out = std.Io.File.stderr().writer(io, &err_buffer);
    try out.interface.print("error[{s}]: 命令语法: `do build ...`、`do test ...`、`do run ...` 或 `do fmt ...`\n", .{@errorName(err)});
    try out.interface.flush();
}

test {
    _ = @import("run/run.zig");
    _ = @import("fmt/run.zig");
}
