const std = @import("std");

pub const Args = struct {
    input_path: []const u8,
    output_path: []const u8,
};

pub fn parseBuild(args: []const []const u8) !Args {
    if (args.len < 2) return error.MissingInputPath;
    return .{
        .input_path = args[1],
        .output_path = try parseOutputPath(args),
    };
}

pub fn parseTest(args: []const []const u8) !Args {
    if (args.len < 2) return error.MissingTestInputPath;
    return .{
        .input_path = args[1],
        .output_path = "",
    };
}

fn parseOutputPath(args: []const []const u8) ![]const u8 {
    var out: []const u8 = "out.wat";
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (!std.mem.eql(u8, args[i], "-o")) continue;
        if (i + 1 >= args.len) return error.MissingOutputPath;
        out = args[i + 1];
        i += 1;
    }
    return out;
}
