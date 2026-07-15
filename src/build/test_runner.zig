const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const model = @import("test_values.zig");
const test_report = @import("test_report.zig");
const test_eval = @import("test_eval.zig");

const Value = model.Value;
const Binding = model.Binding;
const FieldValue = model.FieldValue;
const FuncDecl = model.FuncDecl;
const TestStatus = model.TestStatus;
pub const TestDecl = model.TestDecl;
const eval_test = test_eval.eval_test;
const find_func = test_eval.find_func;
const find_line_end = test_eval.find_line_end;
const find_matching_in_range = test_eval.find_matching_in_range;
const find_matching_token = test_eval.find_matching_token;
const find_func_body_start = test_eval.find_func_body_start;
const count_fixed_params = test_eval.count_fixed_params;
const has_variadic_param = test_eval.has_variadic_param;
const is_func_decl_start = test_eval.is_func_decl_start;
const is_binding_name = test_eval.is_binding_name;
const public_func_name = test_eval.public_func_name;
const string_token_body = test_eval.string_token_body;
const tok_eq_token = test_eval.tok_eq_token;

pub fn run(io: std.Io, allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
    return run_with_modules(io, allocator, null, tokens, null);
}

pub fn run_with_modules(
    io: std.Io,
    allocator: std.mem.Allocator,
    input_path: ?[]const u8,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) !void {
    const test_decls = try collect_top_level_tests(allocator, tokens);
    defer allocator.free(test_decls);

    if (test_decls.len == 0) return error.NoTestDecl;

    const funcs = try collect_runnable_funcs(allocator, input_path, tokens, module_graph);
    defer allocator.free(funcs);

    try test_report.run_and_print(io, allocator, tokens, funcs, test_decls, test_eval.eval_test);
}

pub fn collect_top_level_tests(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]TestDecl {
    var out = std.ArrayList(TestDecl).empty;
    defer out.deinit(allocator);

    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) {
        if (tok_eq_token(tokens[i], "{")) {
            depth_brace += 1;
            i += 1;
            continue;
        }
        if (tok_eq_token(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            i += 1;
            continue;
        }
        if (depth_brace != 0) {
            i += 1;
            continue;
        }

        if (tokens[i].kind != .ident or !std.mem.eql(u8, tokens[i].lexeme, "test")) {
            i += 1;
            continue;
        }
        if (i + 2 >= tokens.len) return error.InvalidTestDecl;
        if (tokens[i + 1].kind != .string) return error.InvalidTestDecl;
        if (!tok_eq_token(tokens[i + 2], "{")) return error.InvalidTestDecl;

        const close_brace = try find_matching_token(tokens, i + 2, "{", "}");
        try out.append(allocator, .{
            .name_lexeme = tokens[i + 1].lexeme,
            .body_start = i + 3,
            .body_end = close_brace,
            .line = tokens[i].line,
            .col = tokens[i].col,
        });
        i = close_brace + 1;
    }

    return out.toOwnedSlice(allocator);
}

fn collect_top_level_funcs(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]FuncDecl {
    var out = std.ArrayList(FuncDecl).empty;
    defer out.deinit(allocator);

    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) {
        if (tok_eq_token(tokens[i], "{")) {
            depth_brace += 1;
            i += 1;
            continue;
        }
        if (tok_eq_token(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            i += 1;
            continue;
        }
        if (depth_brace != 0 or !is_func_decl_start(tokens, i)) {
            i += 1;
            continue;
        }

        const close_params = try find_matching_token(tokens, i + 1, "(", ")");
        const body_start = find_func_body_start(tokens, close_params + 1) orelse {
            i += 1;
            continue;
        };
        if (tok_eq_token(tokens[body_start], "{")) {
            const body_end = try find_matching_token(tokens, body_start, "{", "}");
            try out.append(allocator, .{
                .name = public_func_name(tokens[i].lexeme),
                .params_start = i + 2,
                .params_end = close_params,
                .param_min = count_fixed_params(tokens, i + 2, close_params),
                .param_max = if (has_variadic_param(tokens, i + 2, close_params)) null else count_fixed_params(tokens, i + 2, close_params),
                .body_start = body_start + 1,
                .body_end = body_end,
                .arrow = false,
                .tokens = tokens,
            });
            i = body_end + 1;
            continue;
        }

        const body_end = find_line_end(tokens, body_start, tokens.len);
        try out.append(allocator, .{
            .name = public_func_name(tokens[i].lexeme),
            .params_start = i + 2,
            .params_end = close_params,
            .param_min = count_fixed_params(tokens, i + 2, close_params),
            .param_max = if (has_variadic_param(tokens, i + 2, close_params)) null else count_fixed_params(tokens, i + 2, close_params),
            .body_start = body_start,
            .body_end = body_end,
            .arrow = true,
            .tokens = tokens,
        });
        i = body_end;
    }

    return out.toOwnedSlice(allocator);
}

fn collect_runnable_funcs(
    allocator: std.mem.Allocator,
    input_path: ?[]const u8,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) ![]FuncDecl {
    var out = std.ArrayList(FuncDecl).empty;
    defer out.deinit(allocator);

    const local_funcs = try collect_top_level_funcs(allocator, tokens);
    defer allocator.free(local_funcs);
    try out.appendSlice(allocator, local_funcs);

    if (input_path) |path| {
        if (module_graph) |graph| {
            try collect_direct_imported_funcs(allocator, path, tokens, graph, &out);
        }
    }

    return out.toOwnedSlice(allocator);
}

const ImportPrefix = enum {
    local,
    dep,
    std,
};

const StaticImportRef = struct {
    alias: []const u8,
    target: []const u8,
    file_path: []const u8,
    prefix: ImportPrefix,
};

fn collect_direct_imported_funcs(
    allocator: std.mem.Allocator,
    input_path: []const u8,
    entry_tokens: []const lexer.Token,
    graph: *const imports.ModuleGraph,
    out: *std.ArrayList(FuncDecl),
) !void {
    var i: usize = 0;
    while (i < entry_tokens.len) : (i += 1) {
        const import_ref = parse_static_import(entry_tokens, i) orelse continue;
        defer i = find_line_end(entry_tokens, i, entry_tokens.len) - 1;

        const resolved_path = try resolve_static_import_path(allocator, input_path, graph.dep_root, import_ref);
        defer allocator.free(resolved_path);
        const child_tokens = find_module_tokens_by_path(graph.modules, resolved_path) orelse continue;

        if (!std.mem.eql(u8, import_ref.alias, import_ref.target) and !has_func_named(out.items, import_ref.target)) {
            _ = try append_top_level_func_by_name_as(allocator, child_tokens, import_ref.target, import_ref.target, out);
        }
        if (has_func_named(out.items, import_ref.alias)) continue;
        _ = try append_top_level_func_by_name_as(allocator, child_tokens, import_ref.target, import_ref.alias, out);
    }
}

fn parse_static_import(tokens: []const lexer.Token, idx: usize) ?StaticImportRef {
    if (idx + 7 >= tokens.len) return null;
    if (tokens[idx].kind != .ident or !is_binding_name(tokens[idx].lexeme)) return null;
    if (!tok_eq_token(tokens[idx + 1], "=")) return null;
    if (!tok_eq_token(tokens[idx + 2], "@")) return null;
    if (tokens[idx + 3].kind != .ident or !std.mem.eql(u8, tokens[idx + 3].lexeme, "lib")) return null;
    if (!tok_eq_token(tokens[idx + 4], "(")) return null;
    const close_idx = find_matching_in_range(tokens, idx + 4, "(", ")", tokens.len) catch return null;
    if (close_idx != idx + 8) return null;
    if (tokens[idx + 5].kind != .string) return null;
    if (!tok_eq_token(tokens[idx + 6], ",")) return null;
    if (tokens[idx + 7].kind != .ident) return null;
    const raw_path = string_token_body(tokens[idx + 5].lexeme) orelse return null;

    var prefix: ImportPrefix = .std;
    var file_path = raw_path;
    if (std.mem.startsWith(u8, raw_path, "./")) {
        prefix = .local;
        file_path = raw_path[2..];
    } else if (std.mem.startsWith(u8, raw_path, "~/")) {
        prefix = .dep;
        file_path = raw_path[2..];
    }

    return .{
        .alias = tokens[idx].lexeme,
        .target = tokens[idx + 7].lexeme,
        .file_path = file_path,
        .prefix = prefix,
    };
}

fn resolve_static_import_path(
    allocator: std.mem.Allocator,
    input_path: []const u8,
    dep_root: []const u8,
    import_ref: StaticImportRef,
) ![]u8 {
    return switch (import_ref.prefix) {
        .local => blk: {
            const base = std.fs.path.dirname(input_path) orelse ".";
            break :blk std.fs.path.join(allocator, &.{ base, import_ref.file_path });
        },
        .dep => std.fs.path.join(allocator, &.{ dep_root, import_ref.file_path }),
        .std => std.fs.path.join(allocator, &.{ "lib", import_ref.file_path }),
    };
}

fn find_module_tokens_by_path(modules: []const imports.ModuleRecord, path: []const u8) ?[]const lexer.Token {
    for (modules) |module| {
        if (std.mem.eql(u8, module.path, path)) return module.tokens;
    }
    return null;
}

fn has_func_named(funcs: []const FuncDecl, name: []const u8) bool {
    for (funcs) |func| {
        if (std.mem.eql(u8, func.name, name)) return true;
    }
    return false;
}

fn append_top_level_func_by_name_as(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    target_name: []const u8,
    emit_name: []const u8,
    out: *std.ArrayList(FuncDecl),
) !bool {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq_token(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq_token(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0 or !is_func_decl_start(tokens, i)) continue;

        const close_params = try find_matching_token(tokens, i + 1, "(", ")");
        const body_start = find_func_body_start(tokens, close_params + 1) orelse {
            i += 1;
            continue;
        };
        const body_end = if (tok_eq_token(tokens[body_start], "{"))
            try find_matching_token(tokens, body_start, "{", "}")
        else
            find_line_end(tokens, body_start, tokens.len);
        if (!std.mem.eql(u8, public_func_name(tokens[i].lexeme), target_name)) {
            i = body_end;
            continue;
        }

        try out.append(allocator, .{
            .name = emit_name,
            .params_start = i + 2,
            .params_end = close_params,
            .param_min = count_fixed_params(tokens, i + 2, close_params),
            .param_max = if (has_variadic_param(tokens, i + 2, close_params)) null else count_fixed_params(tokens, i + 2, close_params),
            .body_start = if (tok_eq_token(tokens[body_start], "{")) body_start + 1 else body_start,
            .body_end = body_end,
            .arrow = !tok_eq_token(tokens[body_start], "{"),
            .tokens = tokens,
        });
        return true;
    }
    return false;
}

test "private function declaration is callable by public name" {
    const allocator = std.testing.allocator;
    const source =
        \\.double(x i32) i32 => mul(x, 2)
    ;
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);

    const funcs = try collect_top_level_funcs(allocator, tokens);
    defer allocator.free(funcs);

    try std.testing.expectEqual(@as(usize, 1), funcs.len);
    try std.testing.expectEqualStrings("double", funcs[0].name);
    try std.testing.expect(find_func(funcs, "double", 1) != null);
}

test "variadic function matches zero trailing args" {
    const allocator = std.testing.allocator;
    const source =
        \\count(rest ...i32) -> i32 => 0
    ;
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);

    const funcs = try collect_top_level_funcs(allocator, tokens);
    defer allocator.free(funcs);

    try std.testing.expect(find_func(funcs, "count", 0) != null);
}

test "fixed arity function wins over variadic function" {
    const allocator = std.testing.allocator;
    const source =
        \\pick(rest ...i32) -> i32 => 2
        \\pick(x i32) -> i32 => 1
    ;
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);

    const funcs = try collect_top_level_funcs(allocator, tokens);
    defer allocator.free(funcs);

    const func = find_func(funcs, "pick", 1) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("1", tokens[func.body_start].lexeme);
}

test "longer fixed prefix variadic wins over shorter prefix variadic" {
    const allocator = std.testing.allocator;
    const source =
        \\pick(rest ...i32) -> i32 => 1
        \\pick(x i32, rest ...i32) -> i32 => 2
    ;
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);

    const funcs = try collect_top_level_funcs(allocator, tokens);
    defer allocator.free(funcs);

    const func = find_func(funcs, "pick", 2) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("2", tokens[func.body_start].lexeme);
}

test "recursive guard return static runner passes" {
    const allocator = std.testing.allocator;
    const source =
        \\sum_positive(n i32) -> i32 {
        \\    if @lt(n, 0) return 0
        \\    if @eq(n, 0) return 0
        \\    next i32 = @sub(n, 1)
        \\    return @add(n, sum_positive(next))
        \\}
        \\
        \\test "recursive guard return" {
        \\    out i32 = sum_positive(4)
        \\    if @eq(out, 10) return
        \\}
    ;
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);

    const tests = try collect_top_level_tests(allocator, tokens);
    defer allocator.free(tests);
    const funcs = try collect_top_level_funcs(allocator, tokens);
    defer allocator.free(funcs);

    try std.testing.expectEqual(@as(usize, 1), tests.len);
    try std.testing.expectEqual(TestStatus.pass, try eval_test(allocator, tokens, funcs, tests[0]));
}

test "recursive imported function static runner passes" {
    const allocator = std.testing.allocator;
    const entry_source =
        \\factorial = @lib("./fixture.recursive_math.do", factorial)
        \\
        \\test "imported recursive factorial" {
        \\    out i32 = factorial(5)
        \\    if @eq(out, 120) return
        \\}
    ;
    const child_source =
        \\factorial(n i32) -> i32 {
        \\    if @eq(n, 0) return 1
        \\    next i32 = @sub(n, 1)
        \\    return @mul(n, factorial(next))
        \\}
    ;
    const entry_tokens = try lexer.tokenize(allocator, entry_source);
    defer allocator.free(entry_tokens);
    const child_tokens = try lexer.tokenize(allocator, child_source);
    defer allocator.free(child_tokens);

    const tests = try collect_top_level_tests(allocator, entry_tokens);
    defer allocator.free(tests);
    var modules = [_]imports.ModuleRecord{
        .{
            .path = "src/build/test/ok/entry.do",
            .source = null,
            .owns_source = false,
            .tokens = entry_tokens,
            .owns_tokens = false,
        },
        .{
            .path = "src/build/test/ok/fixture.recursive_math.do",
            .source = null,
            .owns_source = false,
            .tokens = child_tokens,
            .owns_tokens = false,
        },
    };
    const graph = imports.ModuleGraph{
        .allocator = allocator,
        .dep_root = "lib",
        .modules = modules[0..],
    };
    const funcs = try collect_runnable_funcs(allocator, "src/build/test/ok/entry.do", entry_tokens, &graph);
    defer allocator.free(funcs);

    try std.testing.expectEqual(@as(usize, 1), tests.len);
    try std.testing.expectEqual(TestStatus.pass, try eval_test(allocator, entry_tokens, funcs, tests[0]));
}

test "recursive if else block static runner passes" {
    const allocator = std.testing.allocator;
    const source =
        \\sum_branch(n i32, acc i32, include bool) -> i32 {
        \\    if @eq(n, 0) return acc
        \\    next_n i32 = @sub(n, 1)
        \\    if include {
        \\        next_acc i32 = @add(acc, n)
        \\        return sum_branch(next_n, next_acc, include)
        \\    } else {
        \\        return sum_branch(next_n, acc, include)
        \\    }
        \\}
        \\
        \\test "recursive if else block" {
        \\    out i32 = sum_branch(5, 0, true)
        \\    if @eq(out, 15) return
        \\}
    ;
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);

    const tests = try collect_top_level_tests(allocator, tokens);
    defer allocator.free(tests);
    const funcs = try collect_top_level_funcs(allocator, tokens);
    defer allocator.free(funcs);

    try std.testing.expectEqual(@as(usize, 1), tests.len);
    try std.testing.expectEqual(TestStatus.pass, try eval_test(allocator, tokens, funcs, tests[0]));
}

test "recursive error union static runner passes" {
    const allocator = std.testing.allocator;
    const source =
        \\DepthError error = Negative
        \\
        \\sum_checked(n i32) -> i32 | DepthError {
        \\    if @lt(n, 0) return Negative
        \\    if @eq(n, 0) return 0
        \\    next i32 = @sub(n, 1)
        \\    partial = sum_checked(next)
        \\    if @is(partial, DepthError) return partial
        \\    return @add(n, partial)
        \\}
        \\
        \\test "recursive error union" {
        \\    total = sum_checked(4)
        \\    fail = sum_checked(-1)
        \\
        \\    ok bool = true
        \\    if @is(total, i32) {
        \\        ok = @and(ok, @eq(total, 10))
        \\    } else {
        \\        ok = false
        \\    }
        \\    ok = @and(ok, @eq(fail, Negative))
        \\    if ok return
        \\}
    ;
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);

    const tests = try collect_top_level_tests(allocator, tokens);
    defer allocator.free(tests);
    const funcs = try collect_top_level_funcs(allocator, tokens);
    defer allocator.free(funcs);

    try std.testing.expectEqual(@as(usize, 1), tests.len);
    try std.testing.expectEqual(TestStatus.pass, try eval_test(allocator, tokens, funcs, tests[0]));
}
