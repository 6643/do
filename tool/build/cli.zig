const std = @import("std");

pub const Args = struct {
    input_path: []const u8,
    output_path: []const u8,
    compiled_test: bool = false,
    component_core: bool = false,
};

pub const RunArgs = struct {
    input_path: []const u8,
};

pub const FmtArgs = struct {
    input_path: []const u8,
    check: bool = false,
};

pub const LspArgs = struct {
    stdio: bool = true,
};

pub const CheckArgs = struct {
    input_path: []const u8,
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
        if (std.mem.startsWith(u8, args[i], "-")) return error.UnexpectedCliArg;
        if (input_path != null) return error.UnexpectedCliArg;
        input_path = args[i];
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
    var has_output_path = false;
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
            has_output_path = true;
            continue;
        }
        if (std.mem.startsWith(u8, args[i], "-")) return error.UnexpectedCliArg;
        if (input_path != null) return error.UnexpectedCliArg;
        input_path = args[i];
    }
    if (has_output_path and !compiled_test) return error.OutputRequiresCompiledTest;
    const path = input_path orelse return error.MissingTestInputPath;
    return .{
        .input_path = path,
        .output_path = output_path,
        .compiled_test = compiled_test,
    };
}

pub fn parseRun(args: []const []const u8) !RunArgs {
    var input_path: ?[]const u8 = null;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.startsWith(u8, args[i], "-")) return error.UnexpectedCliArg;
        if (input_path != null) return error.UnexpectedCliArg;
        input_path = args[i];
    }
    return .{
        .input_path = input_path orelse return error.MissingInputPath,
    };
}

pub fn parseFmt(args: []const []const u8) !FmtArgs {
    var input_path: ?[]const u8 = null;
    var check = false;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--check")) {
            if (check) return error.UnexpectedCliArg;
            check = true;
            continue;
        }
        if (std.mem.startsWith(u8, args[i], "-")) return error.UnexpectedCliArg;
        if (input_path != null) return error.UnexpectedCliArg;
        input_path = args[i];
    }
    return .{
        .input_path = input_path orelse return error.MissingInputPath,
        .check = check,
    };
}

pub fn parseLsp(args: []const []const u8) !LspArgs {
    var saw_stdio = false;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--stdio")) {
            if (saw_stdio) return error.UnexpectedCliArg;
            saw_stdio = true;
            continue;
        }
        return error.UnexpectedCliArg;
    }
    return .{ .stdio = true };
}

pub fn parseCheck(args: []const []const u8) !CheckArgs {
    var input_path: ?[]const u8 = null;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.startsWith(u8, args[i], "-")) return error.UnexpectedCliArg;
        if (input_path != null) return error.UnexpectedCliArg;
        input_path = args[i];
    }
    return .{
        .input_path = input_path orelse return error.MissingInputPath,
    };
}

test "parseRun accepts exactly one input path" {
    const args = [_][]const u8{ "run", "app.do" };
    const parsed = try parseRun(&args);
    try std.testing.expectEqualStrings("app.do", parsed.input_path);
}

test "parseRun rejects extra args and flags" {
    const extra = [_][]const u8{ "run", "app.do", "extra.do" };
    try std.testing.expectError(error.UnexpectedCliArg, parseRun(&extra));

    const flag = [_][]const u8{ "run", "--bad" };
    try std.testing.expectError(error.UnexpectedCliArg, parseRun(&flag));
}

test "parseRun rejects missing input path" {
    const args = [_][]const u8{"run"};
    try std.testing.expectError(error.MissingInputPath, parseRun(&args));
}

test "parseFmt accepts stdout mode input path" {
    const args = [_][]const u8{ "fmt", "app.do" };
    const parsed = try parseFmt(&args);
    try std.testing.expectEqualStrings("app.do", parsed.input_path);
    try std.testing.expect(!parsed.check);
}

test "parseFmt accepts check mode" {
    const args = [_][]const u8{ "fmt", "--check", "app.do" };
    const parsed = try parseFmt(&args);
    try std.testing.expectEqualStrings("app.do", parsed.input_path);
    try std.testing.expect(parsed.check);
}

test "parseFmt rejects missing input, extra input, and unknown flags" {
    const missing = [_][]const u8{"fmt"};
    try std.testing.expectError(error.MissingInputPath, parseFmt(&missing));

    const extra = [_][]const u8{ "fmt", "app.do", "next.do" };
    try std.testing.expectError(error.UnexpectedCliArg, parseFmt(&extra));

    const flag = [_][]const u8{ "fmt", "--write", "app.do" };
    try std.testing.expectError(error.UnexpectedCliArg, parseFmt(&flag));
}

test "parseLsp accepts stdio mode without extra args" {
    const args = [_][]const u8{"lsp"};
    const parsed = try parseLsp(&args);
    try std.testing.expect(parsed.stdio);
}

test "parseLsp accepts explicit stdio flag" {
    const args = [_][]const u8{ "lsp", "--stdio" };
    const parsed = try parseLsp(&args);
    try std.testing.expect(parsed.stdio);
}

test "parseLsp rejects extra args and unknown flags" {
    const extra = [_][]const u8{ "lsp", "app.do" };
    try std.testing.expectError(error.UnexpectedCliArg, parseLsp(&extra));

    const bad_flag = [_][]const u8{ "lsp", "--tcp" };
    try std.testing.expectError(error.UnexpectedCliArg, parseLsp(&bad_flag));
}

test "parseCheck accepts exactly one input path" {
    const args = [_][]const u8{ "check", "app.do" };
    const parsed = try parseCheck(&args);
    try std.testing.expectEqualStrings("app.do", parsed.input_path);
}

test "parseCheck rejects missing input, extra input, and flags" {
    const missing = [_][]const u8{"check"};
    try std.testing.expectError(error.MissingInputPath, parseCheck(&missing));

    const extra = [_][]const u8{ "check", "app.do", "next.do" };
    try std.testing.expectError(error.UnexpectedCliArg, parseCheck(&extra));

    const flag = [_][]const u8{ "check", "--watch", "app.do" };
    try std.testing.expectError(error.UnexpectedCliArg, parseCheck(&flag));
}
