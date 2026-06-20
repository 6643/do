const std = @import("std");
const build_cmd = @import("build/run.zig");
const check_cmd = @import("check/run.zig");
const fmt_cmd = @import("fmt/run.zig");
const lsp_cmd = @import("lsp/run.zig");
const run_cmd = @import("run/run.zig");

const Command = enum {
    build,
    test_cmd,
    check,
    run,
    fmt,
    lsp,
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
        .check => try check_cmd.run(init, args[1..]),
        .run => try run_cmd.run(init, args[1..]),
        .fmt => try fmt_cmd.run(init, args[1..]),
        .lsp => try lsp_cmd.run(init, args[1..]),
    }
}

fn parseCommand(name: []const u8) !Command {
    if (std.mem.eql(u8, name, "build")) return .build;
    if (std.mem.eql(u8, name, "test")) return .test_cmd;
    if (std.mem.eql(u8, name, "check")) return .check;
    if (std.mem.eql(u8, name, "run")) return .run;
    if (std.mem.eql(u8, name, "fmt")) return .fmt;
    if (std.mem.eql(u8, name, "lsp")) return .lsp;
    return error.UnknownCommand;
}

fn printUsage(io: std.Io) !void {
    var out_buffer: [512]u8 = undefined;
    var out = std.Io.File.stdout().writer(io, &out_buffer);
    try out.interface.print(
        \\do toolchain
        \\usage:
        \\  do build <input.do> [--component-core] [-o out.wat]
        \\  do test <input.do>
        \\  do test <input.do> --compiled [-o out.wat]
        \\  do check <input.do>...
        \\  do run <input.do>
        \\  do fmt <input.do>
        \\  do fmt --check <input.do>
        \\  do fmt --write <input.do>
        \\  do lsp [--stdio]
        \\
    , .{});
    try out.interface.flush();
}

fn printCommandError(io: std.Io, err: anyerror) !void {
    var err_buffer: [512]u8 = undefined;
    var out = std.Io.File.stderr().writer(io, &err_buffer);
    try out.interface.print("error[{s}]: 命令语法: `do build ...`、`do test ...`、`do check ...`、`do run ...`、`do fmt ...` 或 `do lsp ...`\n", .{@errorName(err)});
    try out.interface.flush();
}

test {
    _ = @import("run/run.zig");
    _ = @import("fmt/run.zig");
    _ = @import("lsp/run.zig");
    _ = @import("check/run.zig");
    _ = @import("lsp/diagnostics.zig");
    _ = @import("lsp/protocol.zig");
    _ = @import("lsp/semantic_tokens.zig");
}
