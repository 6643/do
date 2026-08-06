const std = @import("std");

pub const Action = enum {
    check,
    bind,
    help,
};

pub const Args = struct {
    action: Action,
    input_path: ?[]const u8 = null,
    world: ?[]const u8 = null,
    output_path: ?[]const u8 = null,
    manifest_path: ?[]const u8 = null,
};

pub const CliError = error{
    MissingInput,
    MissingOutput,
    MissingManifest,
    MissingSubcommand,
    MissingWorld,
    UnexpectedArgument,
    UnknownSubcommand,
};

pub fn parse(args: []const []const u8) CliError!Args {
    if (args.len == 0 or std.mem.eql(u8, args[0], "--help") or std.mem.eql(u8, args[0], "help")) {
        return .{ .action = .help };
    }
    const action = if (std.mem.eql(u8, args[0], "check")) Action.check else if (std.mem.eql(u8, args[0], "bind")) Action.bind else return error.UnknownSubcommand;
    var input_path: ?[]const u8 = null;
    var world: ?[]const u8 = null;
    var output_path: ?[]const u8 = null;
    var manifest_path: ?[]const u8 = null;

    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--world")) {
            if (index + 1 >= args.len) return error.MissingWorld;
            index += 1;
            if (world != null) return error.UnexpectedArgument;
            world = args[index];
            continue;
        }
        if (std.mem.eql(u8, arg, "--out")) {
            if (action != .bind) return error.UnexpectedArgument;
            if (index + 1 >= args.len) return error.MissingOutput;
            index += 1;
            if (output_path != null) return error.UnexpectedArgument;
            output_path = args[index];
            continue;
        }
        if (std.mem.eql(u8, arg, "--manifest")) {
            if (action != .check) return error.UnexpectedArgument;
            if (index + 1 >= args.len) return error.MissingManifest;
            index += 1;
            if (manifest_path != null) return error.UnexpectedArgument;
            manifest_path = args[index];
            continue;
        }
        if (std.mem.startsWith(u8, arg, "-")) return error.UnexpectedArgument;
        if (input_path != null) return error.UnexpectedArgument;
        input_path = arg;
    }

    if (input_path == null) return error.MissingInput;
    if (action == .bind) {
        if (world == null) return error.MissingWorld;
        if (output_path == null) return error.MissingOutput;
    } else if (output_path != null) {
        return error.UnexpectedArgument;
    }
    return .{ .action = action, .input_path = input_path, .world = world, .output_path = output_path, .manifest_path = manifest_path };
}
