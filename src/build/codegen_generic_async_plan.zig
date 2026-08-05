const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const imports = @import("imports.zig");
const sema_tokens = @import("sema_tokens.zig");

const find_matching = sema_tokens.find_matching;
const find_line_end_idx = sema_tokens.find_line_end_idx;
const tok_eq = sema_tokens.tok_eq;

pub const GenericAsyncPlan = struct {
    root_name: []const u8,
    work_name: []const u8,
    await_future_name: []const u8,
    cancel_future_name: []const u8,
    await_token_index: usize,
    cancel_token_index: usize,

    pub fn deinit(self: *GenericAsyncPlan, allocator: std.mem.Allocator) void {
        allocator.free(self.root_name);
        allocator.free(self.work_name);
        allocator.free(self.await_future_name);
        allocator.free(self.cancel_future_name);
        self.* = undefined;
    }
};

test "generic async admission accepts the exact single-future slice" {
    const source = @embedFile("test/check/417_generic_async_single_future.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    var plan = try analyze(std.testing.allocator, program, tokens, null);
    defer plan.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("run", plan.root_name);
    try std.testing.expectEqualStrings("work", plan.work_name);
    try std.testing.expectEqualStrings("ready", plan.await_future_name);
    try std.testing.expectEqualStrings("pending", plan.cancel_future_name);
    try std.testing.expect(plan.await_token_index < plan.cancel_token_index);
}

test "generic async admission rejects payload futures" {
    try expect_unsupported(
        \\work() -> i32 { return 1 }
        \\run() -> nil {
        \\    pending Future<i32> = @async(work())
        \\    @await(pending)
        \\    other Future<nil> = @async(work())
        \\    @cancel(other)
        \\}
        \\start() {}
    );
}

test "generic async admission rejects stream operations" {
    try expect_unsupported(
        \\work() -> nil { return }
        \\run() -> nil {
        \\    stream Stream<u8> = @async(work())
        \\    @await(stream)
        \\    pending Future<nil> = @async(work())
        \\    @cancel(pending)
        \\}
        \\start() {}
    );
}

test "generic async admission rejects multiple awaits" {
    try expect_unsupported(
        \\work() -> nil { return }
        \\run() -> nil {
        \\    first Future<nil> = @async(work())
        \\    @await(first)
        \\    second Future<nil> = @async(work())
        \\    @await(second)
        \\    pending Future<nil> = @async(work())
        \\    @cancel(pending)
        \\}
        \\start() {}
    );
}

test "generic async admission rejects async function declarations" {
    try expect_unsupported(
        \\work() -> nil { return }
        \\async run() -> nil {
        \\    ready Future<nil> = @async(work())
        \\    @await(ready)
        \\    pending Future<nil> = @async(work())
        \\    @cancel(pending)
        \\}
        \\start() {}
    );
}

fn expect_unsupported(source: []const u8) !void {
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    try std.testing.expectError(error.UnsupportedGenericAsyncShape, analyze(std.testing.allocator, program, tokens, null));
}

pub fn analyze(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) !GenericAsyncPlan {
    for (program.func_sigs) |sig| {
        if (sig.is_async) return error.UnsupportedGenericAsyncShape;
    }
    if (module_graph) |graph| {
        for (graph.modules) |module| {
            if (module.tokens.len == tokens.len and module.tokens.ptr == tokens.ptr) continue;
            if (contains_async_operation(module.tokens)) return error.UnsupportedGenericAsyncShape;
        }
    }

    const root = find_function(tokens, "run") orelse return error.UnsupportedGenericAsyncShape;
    const work = find_function(tokens, "work") orelse return error.UnsupportedGenericAsyncShape;
    if (root.is_async or work.is_async) return error.UnsupportedGenericAsyncShape;
    if (!signature_is_unit(program, "run") or !signature_is_unit(program, "work")) {
        return error.UnsupportedGenericAsyncShape;
    }

    const body = tokens[root.body_start..root.body_end];
    var cursor: usize = 0;
    const first = parse_future_binding(body, cursor) orelse return error.UnsupportedGenericAsyncShape;
    if (!std.mem.eql(u8, first.work_name, work.name)) return error.UnsupportedGenericAsyncShape;
    cursor = first.next_idx;

    const await_call = parse_intrinsic_call(body, cursor, "await") orelse return error.UnsupportedGenericAsyncShape;
    if (!std.mem.eql(u8, await_call.operand, first.future_name)) return error.UnsupportedGenericAsyncShape;
    cursor = await_call.next_idx;

    const second = parse_future_binding(body, cursor) orelse return error.UnsupportedGenericAsyncShape;
    if (!std.mem.eql(u8, second.work_name, work.name) or
        std.mem.eql(u8, second.future_name, first.future_name)) return error.UnsupportedGenericAsyncShape;
    cursor = second.next_idx;

    const cancel_call = parse_intrinsic_call(body, cursor, "cancel") orelse return error.UnsupportedGenericAsyncShape;
    if (!std.mem.eql(u8, cancel_call.operand, second.future_name) or cancel_call.next_idx != body.len) {
        return error.UnsupportedGenericAsyncShape;
    }

    if (count_intrinsic(tokens, "async") != 2 or count_intrinsic(tokens, "await") != 1 or count_intrinsic(tokens, "cancel") != 1) {
        return error.UnsupportedGenericAsyncShape;
    }

    const root_name = try allocator.dupe(u8, root.name);
    errdefer allocator.free(root_name);
    const work_name = try allocator.dupe(u8, work.name);
    errdefer allocator.free(work_name);
    const await_future_name = try allocator.dupe(u8, first.future_name);
    errdefer allocator.free(await_future_name);
    const cancel_future_name = try allocator.dupe(u8, second.future_name);
    errdefer allocator.free(cancel_future_name);

    return .{
        .root_name = root_name,
        .work_name = work_name,
        .await_future_name = await_future_name,
        .cancel_future_name = cancel_future_name,
        .await_token_index = root.body_start + await_call.token_index,
        .cancel_token_index = root.body_start + cancel_call.token_index,
    };
}

const FunctionRange = struct {
    name: []const u8,
    is_async: bool,
    body_start: usize,
    body_end: usize,
};

const FutureBinding = struct {
    future_name: []const u8,
    work_name: []const u8,
    next_idx: usize,
};

const IntrinsicCall = struct {
    token_index: usize,
    operand: []const u8,
    next_idx: usize,
};

fn signature_is_unit(program: parser.Program, name: []const u8) bool {
    var found = false;
    for (program.func_sigs) |sig| {
        if (!std.mem.eql(u8, sig.name, name)) continue;
        if (found or sig.is_async or sig.param_min != 0 or
            (sig.param_max orelse std.math.maxInt(usize)) != 0 or sig.return_arity != 0) return false;
        found = true;
    }
    return found;
}

fn find_function(tokens: []const lexer.Token, name: []const u8) ?FunctionRange {
    var depth: usize = 0;
    var idx: usize = 0;
    while (idx < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], "{")) {
            depth += 1;
            continue;
        }
        if (tok_eq(tokens[idx], "}")) {
            if (depth > 0) depth -= 1;
            continue;
        }
        if (depth != 0 or tokens[idx].kind != .ident or !std.mem.eql(u8, tokens[idx].lexeme, name) or
            idx + 1 >= tokens.len or !tok_eq(tokens[idx + 1], "(")) continue;

        const close_params = find_matching(tokens, idx + 1, "(", ")") catch return null;
        var body_open = close_params + 1;
        while (body_open < tokens.len and !tok_eq(tokens[body_open], "{")) : (body_open += 1) {
            if (tokens[body_open].line != tokens[close_params].line) return null;
        }
        if (body_open >= tokens.len) return null;
        const body_end = find_matching(tokens, body_open, "{", "}") catch return null;
        return .{
            .name = tokens[idx].lexeme,
            .is_async = idx > 0 and tokens[idx - 1].line == tokens[idx].line and tok_eq(tokens[idx - 1], "async"),
            .body_start = body_open + 1,
            .body_end = body_end,
        };
    }
    return null;
}

fn parse_future_binding(tokens: []const lexer.Token, start_idx: usize) ?FutureBinding {
    const line_end = find_line_end_idx(tokens, start_idx);
    if (start_idx + 8 >= line_end or tokens[start_idx].kind != .ident or
        !tok_eq(tokens[start_idx + 1], "Future") or !tok_eq(tokens[start_idx + 2], "<") or
        !tok_eq(tokens[start_idx + 3], "nil") or !tok_eq(tokens[start_idx + 4], ">") or
        !tok_eq(tokens[start_idx + 5], "=") or !tok_eq(tokens[start_idx + 6], "@") or
        !tok_eq(tokens[start_idx + 7], "async") or !tok_eq(tokens[start_idx + 8], "(")) return null;

    const outer_close = find_matching(tokens, start_idx + 8, "(", ")") catch return null;
    if (outer_close + 1 != line_end or tokens[start_idx + 9].kind != .ident or
        !tok_eq(tokens[start_idx + 10], "(") or !tok_eq(tokens[start_idx + 11], ")") or
        !tok_eq(tokens[outer_close], ")")) return null;
    return .{
        .future_name = tokens[start_idx].lexeme,
        .work_name = tokens[start_idx + 9].lexeme,
        .next_idx = line_end,
    };
}

fn parse_intrinsic_call(tokens: []const lexer.Token, start_idx: usize, name: []const u8) ?IntrinsicCall {
    const line_end = find_line_end_idx(tokens, start_idx);
    if (start_idx + 5 != line_end or !tok_eq(tokens[start_idx], "@") or
        !std.mem.eql(u8, tokens[start_idx + 1].lexeme, name) or !tok_eq(tokens[start_idx + 2], "(") or
        tokens[start_idx + 3].kind != .ident or !tok_eq(tokens[start_idx + 4], ")")) return null;
    return .{ .token_index = start_idx, .operand = tokens[start_idx + 3].lexeme, .next_idx = line_end };
}

fn contains_async_operation(tokens: []const lexer.Token) bool {
    return count_intrinsic(tokens, "async") != 0 or count_intrinsic(tokens, "await") != 0 or count_intrinsic(tokens, "cancel") != 0;
}

fn count_intrinsic(tokens: []const lexer.Token, name: []const u8) usize {
    var count: usize = 0;
    for (tokens, 0..) |token, idx| {
        if (!tok_eq(token, "@") or idx + 1 >= tokens.len or !std.mem.eql(u8, tokens[idx + 1].lexeme, name)) continue;
        count += 1;
    }
    return count;
}
