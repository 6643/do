const std = @import("std");

pub const Args = struct {
    input_path: []const u8,
    output_path: []const u8,
    compiled_test: bool = false,
    component_core: bool = false,
};

pub fn parseBuild(args: []const []const u8) !Args {
    var input_path: ?[]const u8 = null;
    var output_path: []const u8 = "out.wat";
    var component_core = false;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--component-core")) {
            component_core = true;
            continue;
        }
        if (std.mem.eql(u8, args[i], "-o")) {
            if (i + 1 >= args.len) return error.MissingOutputPath;
            i += 1;
            output_path = args[i];
            continue;
        }
        if (input_path == null) input_path = args[i];
    }
    const path = input_path orelse return error.MissingInputPath;
    return .{
        .input_path = path,
        .output_path = output_path,
        .component_core = component_core,
    };
}

pub fn parseTest(args: []const []const u8) !Args {
    var input_path: ?[]const u8 = null;
    var output_path: []const u8 = "out.wat";
    var compiled_test = false;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--compiled")) {
            compiled_test = true;
            continue;
        }
        if (std.mem.eql(u8, args[i], "-o")) {
            if (i + 1 >= args.len) return error.MissingOutputPath;
            i += 1;
            output_path = args[i];
            continue;
        }
        if (input_path == null) input_path = args[i];
    }
    const path = input_path orelse return error.MissingTestInputPath;
    return .{
        .input_path = path,
        .output_path = output_path,
        .compiled_test = compiled_test,
    };
}
