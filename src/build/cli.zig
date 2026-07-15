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
    write: bool = false,
};

pub const LspArgs = struct {
    stdio: bool = true,
};

pub const CheckArgs = struct {
    input_paths: []const []const u8,
};

pub fn parse_build(args: []const []const u8) !Args {
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

pub fn parse_test(args: []const []const u8) !Args {
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

pub fn parse_run(args: []const []const u8) !RunArgs {
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

pub fn parse_fmt(args: []const []const u8) !FmtArgs {
    var input_path: ?[]const u8 = null;
    var check = false;
    var write = false;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--check")) {
            if (check or write) return error.UnexpectedCliArg;
            check = true;
            continue;
        }
        if (std.mem.eql(u8, args[i], "--write")) {
            if (write or check) return error.UnexpectedCliArg;
            write = true;
            continue;
        }
        if (std.mem.startsWith(u8, args[i], "-")) return error.UnexpectedCliArg;
        if (input_path != null) return error.UnexpectedCliArg;
        input_path = args[i];
    }
    return .{
        .input_path = input_path orelse return error.MissingInputPath,
        .check = check,
        .write = write,
    };
}

pub fn parse_lsp(args: []const []const u8) !LspArgs {
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

pub fn parse_check(args: []const []const u8) !CheckArgs {
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.startsWith(u8, args[i], "-")) return error.UnexpectedCliArg;
    }
    if (args.len < 2) return error.MissingInputPath;
    return .{
        .input_paths = args[1..],
    };
}

test "parse_run accepts exactly one input path" {
    const args = [_][]const u8{ "run", "app.do" };
    const parsed = try parse_run(&args);
    try std.testing.expectEqualStrings("app.do", parsed.input_path);
}

test "parse_run rejects extra args and flags" {
    const extra = [_][]const u8{ "run", "app.do", "extra.do" };
    try std.testing.expectError(error.UnexpectedCliArg, parse_run(&extra));

    const flag = [_][]const u8{ "run", "--bad" };
    try std.testing.expectError(error.UnexpectedCliArg, parse_run(&flag));
}

test "parse_run rejects missing input path" {
    const args = [_][]const u8{"run"};
    try std.testing.expectError(error.MissingInputPath, parse_run(&args));
}

test "parse_fmt accepts stdout mode input path" {
    const args = [_][]const u8{ "fmt", "app.do" };
    const parsed = try parse_fmt(&args);
    try std.testing.expectEqualStrings("app.do", parsed.input_path);
    try std.testing.expect(!parsed.check);
    try std.testing.expect(!parsed.write);
}

test "parse_fmt accepts check mode" {
    const args = [_][]const u8{ "fmt", "--check", "app.do" };
    const parsed = try parse_fmt(&args);
    try std.testing.expectEqualStrings("app.do", parsed.input_path);
    try std.testing.expect(parsed.check);
    try std.testing.expect(!parsed.write);
}

test "parse_fmt accepts write mode" {
    const args = [_][]const u8{ "fmt", "--write", "app.do" };
    const parsed = try parse_fmt(&args);
    try std.testing.expectEqualStrings("app.do", parsed.input_path);
    try std.testing.expect(parsed.write);
    try std.testing.expect(!parsed.check);
}

test "parse_fmt rejects mixing check and write modes" {
    const args = [_][]const u8{ "fmt", "--check", "--write", "app.do" };
    try std.testing.expectError(error.UnexpectedCliArg, parse_fmt(&args));
}

test "parse_fmt rejects missing input, extra input, and unknown flags" {
    const missing = [_][]const u8{"fmt"};
    try std.testing.expectError(error.MissingInputPath, parse_fmt(&missing));

    const extra = [_][]const u8{ "fmt", "app.do", "next.do" };
    try std.testing.expectError(error.UnexpectedCliArg, parse_fmt(&extra));

    const flag = [_][]const u8{ "fmt", "--bad", "app.do" };
    try std.testing.expectError(error.UnexpectedCliArg, parse_fmt(&flag));
}

test "parse_lsp accepts stdio mode without extra args" {
    const args = [_][]const u8{"lsp"};
    const parsed = try parse_lsp(&args);
    try std.testing.expect(parsed.stdio);
}

test "parse_lsp accepts explicit stdio flag" {
    const args = [_][]const u8{ "lsp", "--stdio" };
    const parsed = try parse_lsp(&args);
    try std.testing.expect(parsed.stdio);
}

test "parse_lsp rejects extra args and unknown flags" {
    const extra = [_][]const u8{ "lsp", "app.do" };
    try std.testing.expectError(error.UnexpectedCliArg, parse_lsp(&extra));

    const bad_flag = [_][]const u8{ "lsp", "--tcp" };
    try std.testing.expectError(error.UnexpectedCliArg, parse_lsp(&bad_flag));
}

test "parse_check accepts exactly one input path" {
    const args = [_][]const u8{ "check", "app.do" };
    const parsed = try parse_check(&args);
    try std.testing.expectEqual(@as(usize, 1), parsed.input_paths.len);
    try std.testing.expectEqualStrings("app.do", parsed.input_paths[0]);
}

test "parse_check accepts multiple input paths" {
    const args = [_][]const u8{ "check", "a.do", "b.do" };
    const parsed = try parse_check(&args);
    try std.testing.expectEqual(@as(usize, 2), parsed.input_paths.len);
    try std.testing.expectEqualStrings("a.do", parsed.input_paths[0]);
    try std.testing.expectEqualStrings("b.do", parsed.input_paths[1]);
}

test "parse_check rejects missing input and flags" {
    const missing = [_][]const u8{"check"};
    try std.testing.expectError(error.MissingInputPath, parse_check(&missing));

    const flag = [_][]const u8{ "check", "--watch", "app.do" };
    try std.testing.expectError(error.UnexpectedCliArg, parse_check(&flag));
}
