const std = @import("std");
const lexer = @import("lexer.zig");

const Value = union(enum) {
    unsupported,
    unknown,
    nil,
    bool: bool,
    int: i128,
    text: []const u8,
    object: []const FieldValue,
};

const Binding = struct {
    name: []const u8,
    value: Value,
};

const FieldValue = struct {
    name: []const u8,
    value: Value,
};

const FuncDecl = struct {
    name: []const u8,
    params_start: usize,
    params_end: usize,
    param_min: usize,
    param_max: ?usize,
    body_start: usize,
    body_end: usize,
    arrow: bool,
};

const TestStatus = enum {
    pass,
    fail,
    skip,
};

pub const TestDecl = struct {
    name_lexeme: []const u8,
    body_start: usize,
    body_end: usize,
    line: usize,
    col: usize,
};

pub fn run(io: std.Io, allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
    const test_decls = try collectTopLevelTests(allocator, tokens);
    defer allocator.free(test_decls);

    if (test_decls.len == 0) return error.NoTestDecl;

    const funcs = try collectTopLevelFuncs(allocator, tokens);
    defer allocator.free(funcs);

    try runAndPrintTestReport(io, allocator, tokens, funcs, test_decls);
}

pub fn collectTopLevelTests(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]TestDecl {
    var out = std.ArrayList(TestDecl).empty;
    defer out.deinit(allocator);

    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) {
        if (tokEqToken(tokens[i], "{")) {
            depth_brace += 1;
            i += 1;
            continue;
        }
        if (tokEqToken(tokens[i], "}")) {
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
        if (!tokEqToken(tokens[i + 2], "{")) return error.InvalidTestDecl;

        const close_brace = try findMatchingToken(tokens, i + 2, "{", "}");
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

fn collectTopLevelFuncs(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]FuncDecl {
    var out = std.ArrayList(FuncDecl).empty;
    defer out.deinit(allocator);

    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) {
        if (tokEqToken(tokens[i], "{")) {
            depth_brace += 1;
            i += 1;
            continue;
        }
        if (tokEqToken(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            i += 1;
            continue;
        }
        if (depth_brace != 0 or !isFuncDeclStart(tokens, i)) {
            i += 1;
            continue;
        }

        const close_params = try findMatchingToken(tokens, i + 1, "(", ")");
        const body_start = findFuncBodyStart(tokens, close_params + 1) orelse {
            i += 1;
            continue;
        };
        if (tokEqToken(tokens[body_start], "{")) {
            const body_end = try findMatchingToken(tokens, body_start, "{", "}");
            try out.append(allocator, .{
                .name = publicFuncName(tokens[i].lexeme),
                .params_start = i + 2,
                .params_end = close_params,
                .param_min = countFixedParams(tokens, i + 2, close_params),
                .param_max = if (hasVariadicParam(tokens, i + 2, close_params)) null else countFixedParams(tokens, i + 2, close_params),
                .body_start = body_start + 1,
                .body_end = body_end,
                .arrow = false,
            });
            i = body_end + 1;
            continue;
        }

        const body_end = findLineEnd(tokens, body_start, tokens.len);
        try out.append(allocator, .{
            .name = publicFuncName(tokens[i].lexeme),
            .params_start = i + 2,
            .params_end = close_params,
            .param_min = countFixedParams(tokens, i + 2, close_params),
            .param_max = if (hasVariadicParam(tokens, i + 2, close_params)) null else countFixedParams(tokens, i + 2, close_params),
            .body_start = body_start,
            .body_end = body_end,
            .arrow = true,
        });
        i = body_end;
    }

    return out.toOwnedSlice(allocator);
}

fn runAndPrintTestReport(
    io: std.Io,
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    test_decls: []const TestDecl,
) !void {
    var out_buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(io, &out_buffer);

    var passed: usize = 0;
    var failed: usize = 0;
    var skipped: usize = 0;
    for (test_decls) |decl| {
        const status = try evalTest(allocator, tokens, funcs, decl);
        switch (status) {
            .pass => {
                passed += 1;
                try out.interface.print("test {s} ... ok\n", .{decl.name_lexeme});
            },
            .fail => {
                failed += 1;
                try out.interface.print("test {s} ... failed\n", .{decl.name_lexeme});
            },
            .skip => {
                skipped += 1;
                try out.interface.print("test {s} ... skipped\n", .{decl.name_lexeme});
            },
        }
    }

    if (failed == 0) {
        try out.interface.print("ok: {d} passed; 0 failed; {d} skipped\n", .{ passed, skipped });
        try out.interface.flush();
        return;
    }

    try out.interface.print("failed: {d} passed; {d} failed; {d} skipped\n", .{ passed, failed, skipped });
    try out.interface.flush();
    return error.TestFailed;
}

fn evalTest(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    decl: TestDecl,
) !TestStatus {
    if (hasUnsupportedControlFlow(tokens, decl.body_start, decl.body_end)) return .skip;

    var bindings = std.ArrayList(Binding).empty;
    defer {
        freeBindings(allocator, bindings.items);
        bindings.deinit(allocator);
    }

    var saw_known_false = false;
    var saw_unknown = false;
    var saw_unsupported = false;
    var i = decl.body_start;
    while (i < decl.body_end) {
        if (tokEqToken(tokens[i], "if")) {
            const parsed = try evalIfReturn(allocator, tokens, funcs, &bindings, i, decl.body_end);
            if (parsed.returned) return if (saw_unsupported) .skip else .pass;
            if (parsed.unsupported) {
                saw_unsupported = true;
            } else if (parsed.unknown) {
                saw_unknown = true;
            } else {
                saw_known_false = true;
            }
            i = parsed.next_idx;
            continue;
        }
        if (tokEqToken(tokens[i], "return")) return if (saw_unsupported) .skip else .pass;
        if (try evalBindingLine(allocator, tokens, funcs, &bindings, i, decl.body_end)) |line| {
            if (line.unsupported) saw_unsupported = true;
            i = line.next_idx;
            continue;
        }
        i = findLineEnd(tokens, i, decl.body_end);
    }

    if (saw_unknown or saw_known_false) return .fail;
    if (saw_unsupported) return .skip;
    return .pass;
}

fn hasUnsupportedControlFlow(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i < end_idx) {
        if (tokEqToken(tokens[i], "else")) return true;
        if (tokEqToken(tokens[i], "defer")) return true;
        if (tokEqToken(tokens[i], "loop")) {
            const static_loop = staticNoopBreakLoop(tokens, i, end_idx) orelse return true;
            i = static_loop.next_idx;
            continue;
        }
        if (!tokEqToken(tokens[i], "if")) {
            i += 1;
            continue;
        }
        const line_end = findLineEnd(tokens, i, end_idx);
        if (findTopLevelToken(tokens, i + 1, line_end, "{") != null) return true;
        i += 1;
    }
    return false;
}

const StaticLoop = struct {
    next_idx: usize,
};

fn staticNoopBreakLoop(tokens: []const lexer.Token, loop_idx: usize, end_idx: usize) ?StaticLoop {
    const open_idx = loop_idx + 1;
    if (open_idx >= end_idx or !tokEqToken(tokens[open_idx], "{")) return null;
    const close_idx = findMatchingInRange(tokens, open_idx, "{", "}", end_idx) catch return null;
    const break_idx = open_idx + 1;
    if (break_idx >= close_idx or !tokEqToken(tokens[break_idx], "break")) return null;
    if (break_idx + 1 != close_idx) return null;
    return .{ .next_idx = close_idx + 1 };
}

const IfEval = struct {
    next_idx: usize,
    returned: bool,
    unsupported: bool,
    unknown: bool,
};

fn evalIfReturn(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    bindings: *std.ArrayList(Binding),
    if_idx: usize,
    limit_idx: usize,
) !IfEval {
    const line_end = findLineEnd(tokens, if_idx, limit_idx);
    const return_idx = findTopLevelToken(tokens, if_idx + 1, line_end, "return") orelse
        return .{ .next_idx = line_end, .returned = false, .unsupported = true, .unknown = false };
    const cond = try evalExpr(allocator, tokens, funcs, bindings.items, if_idx + 1, return_idx);
    defer freeValue(allocator, cond);
    if (cond == .unsupported) {
        if (isSingleUnboundIdent(tokens, bindings.items, if_idx + 1, return_idx)) return error.NoMatchingCall;
        return .{ .next_idx = line_end, .returned = false, .unsupported = true, .unknown = false };
    }
    if (cond == .unknown) {
        if (isSingleUnboundIdent(tokens, bindings.items, if_idx + 1, return_idx)) return error.NoMatchingCall;
        return .{ .next_idx = line_end, .returned = false, .unsupported = false, .unknown = true };
    }
    if (cond != .bool) return error.NonBoolIfCondition;
    return .{
        .next_idx = line_end,
        .returned = cond.bool,
        .unsupported = false,
        .unknown = false,
    };
}

const LineEval = struct {
    next_idx: usize,
    unsupported: bool,
};

fn evalBindingLine(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    bindings: *std.ArrayList(Binding),
    start_idx: usize,
    limit_idx: usize,
) !?LineEval {
    const line_end = findStmtEnd(tokens, start_idx, limit_idx);
    const eq_idx = findTopLevelToken(tokens, start_idx, line_end, "=") orelse return null;
    if (try evalMultiBindingLine(allocator, tokens, funcs, bindings, start_idx, eq_idx, line_end)) |line| {
        return line;
    }
    if (eq_idx == start_idx) return null;
    const name_idx = start_idx;
    if (tokens[name_idx].kind != .ident) return null;
    if (!isBindingName(tokens[name_idx].lexeme)) return null;

    const value = try evalExpr(allocator, tokens, funcs, bindings.items, eq_idx + 1, line_end);
    errdefer freeValue(allocator, value);
    const unsupported = value == .unsupported;
    try setBinding(allocator, bindings, tokens[name_idx].lexeme, value);
    return .{ .next_idx = line_end, .unsupported = unsupported };
}

fn evalMultiBindingLine(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    bindings: *std.ArrayList(Binding),
    start_idx: usize,
    eq_idx: usize,
    line_end: usize,
) !?LineEval {
    if (findTopLevelToken(tokens, start_idx, eq_idx, ",") == null) return null;
    const call = parseSimpleCall(tokens, eq_idx + 1, line_end) orelse return null;
    const lhs_count = try countMultiBindingLhs(tokens, start_idx, eq_idx);
    if (findFunc(funcs, call.name, countArgs(tokens, call.args_start, call.args_end)) == null) {
        try bindUnsupportedValues(allocator, tokens, bindings, start_idx, eq_idx);
        return .{ .next_idx = line_end, .unsupported = true };
    }
    const values = try evalUserFuncMulti(allocator, tokens, funcs, call.name, call.args_start, call.args_end, bindings.items, lhs_count);
    defer {
        freeValues(allocator, values);
        allocator.free(values);
    }
    if (lhs_count != values.len) return error.NoMatchingCall;
    const unsupported = hasUnsupportedValue(values);

    var value_idx: usize = 0;
    var lhs_start = start_idx;
    while (lhs_start < eq_idx) {
        const lhs_end = findArgEnd(tokens, lhs_start, eq_idx);
        const value = try cloneValue(allocator, values[value_idx]);
        errdefer freeValue(allocator, value);
        try setBinding(allocator, bindings, tokens[lhs_start].lexeme, value);
        value_idx += 1;
        lhs_start = lhs_end;
        if (lhs_start < eq_idx and tokEqToken(tokens[lhs_start], ",")) lhs_start += 1;
    }
    return .{ .next_idx = line_end, .unsupported = unsupported };
}

fn countMultiBindingLhs(tokens: []const lexer.Token, start_idx: usize, eq_idx: usize) !usize {
    var count: usize = 0;
    var lhs_start = start_idx;
    while (lhs_start < eq_idx) {
        const lhs_end = findArgEnd(tokens, lhs_start, eq_idx);
        if (lhs_end != lhs_start + 1 or tokens[lhs_start].kind != .ident or !isBindingName(tokens[lhs_start].lexeme)) {
            return error.NoMatchingCall;
        }
        count += 1;
        lhs_start = lhs_end;
        if (lhs_start < eq_idx and tokEqToken(tokens[lhs_start], ",")) lhs_start += 1;
    }
    if (count <= 1) return error.NoMatchingCall;
    return count;
}

fn bindUnsupportedValues(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    bindings: *std.ArrayList(Binding),
    start_idx: usize,
    eq_idx: usize,
) !void {
    var lhs_start = start_idx;
    while (lhs_start < eq_idx) {
        const lhs_end = findArgEnd(tokens, lhs_start, eq_idx);
        try setBinding(allocator, bindings, tokens[lhs_start].lexeme, .unsupported);
        lhs_start = lhs_end;
        if (lhs_start < eq_idx and tokEqToken(tokens[lhs_start], ",")) lhs_start += 1;
    }
}

fn evalExpr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    bindings: []const Binding,
    start_idx: usize,
    end_idx: usize,
) anyerror!Value {
    const trimmed = trimParens(tokens, start_idx, end_idx);
    if (trimmed.start >= trimmed.end) return .unknown;
    if (trimmed.end == trimmed.start + 1) return evalAtom(allocator, tokens[trimmed.start], bindings);

    if (isStructLiteralStart(tokens, trimmed.start, trimmed.end)) {
        return evalStructLiteral(allocator, tokens, funcs, bindings, trimmed.start, trimmed.end);
    }

    if (tokens[trimmed.start].kind == .ident and trimmed.start + 1 < trimmed.end and tokEqToken(tokens[trimmed.start + 1], "(")) {
        const close_paren = findMatchingInRange(tokens, trimmed.start + 1, "(", ")", trimmed.end) catch return .unknown;
        if (close_paren + 1 != trimmed.end) return .unknown;
        return evalCall(allocator, tokens, funcs, bindings, trimmed.start, trimmed.start + 2, close_paren);
    }
    if (tokEqToken(tokens[trimmed.start], "@") and trimmed.start + 2 < trimmed.end and tokens[trimmed.start + 1].kind == .ident and tokEqToken(tokens[trimmed.start + 2], "(")) {
        const close_paren = findMatchingInRange(tokens, trimmed.start + 2, "(", ")", trimmed.end) catch return .unknown;
        if (close_paren + 1 != trimmed.end) return .unknown;
        return evalCall(allocator, tokens, funcs, bindings, trimmed.start + 1, trimmed.start + 3, close_paren);
    }

    return .unknown;
}

const Range = struct {
    start: usize,
    end: usize,
};

const SimpleCall = struct {
    name: []const u8,
    args_start: usize,
    args_end: usize,
};

fn trimParens(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) Range {
    var start = start_idx;
    var end = end_idx;
    while (start + 1 < end and tokEqToken(tokens[start], "(")) {
        const close = findMatchingInRange(tokens, start, "(", ")", end) catch break;
        if (close + 1 != end) break;
        start += 1;
        end -= 1;
    }
    return .{ .start = start, .end = end };
}

fn parseSimpleCall(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?SimpleCall {
    const trimmed = trimParens(tokens, start_idx, end_idx);
    if (trimmed.start + 2 > trimmed.end) return null;
    if (tokens[trimmed.start].kind != .ident) return null;
    if (!tokEqToken(tokens[trimmed.start + 1], "(")) return null;
    const close_paren = findMatchingInRange(tokens, trimmed.start + 1, "(", ")", trimmed.end) catch return null;
    if (close_paren + 1 != trimmed.end) return null;
    return .{
        .name = tokens[trimmed.start].lexeme,
        .args_start = trimmed.start + 2,
        .args_end = close_paren,
    };
}

fn evalAtom(allocator: std.mem.Allocator, tok: lexer.Token, bindings: []const Binding) anyerror!Value {
    if (tok.kind == .number) return .{ .int = parseInt(tok.lexeme) orelse return .unknown };
    if (tok.kind == .string) return .{ .text = try decodeStringLiteral(allocator, tok.lexeme) };
    if (tokEqToken(tok, "true")) return .{ .bool = true };
    if (tokEqToken(tok, "false")) return .{ .bool = false };
    if (tokEqToken(tok, "nil")) return .nil;
    if (tok.kind == .ident) {
        if (lookupBinding(bindings, tok.lexeme)) |value| return cloneValue(allocator, value);
        return .unsupported;
    }
    return .unknown;
}

fn evalCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    bindings: []const Binding,
    name_idx: usize,
    args_start: usize,
    args_end: usize,
) anyerror!Value {
    const name = tokens[name_idx].lexeme;
    if (std.mem.eql(u8, name, "get")) {
        return evalGetCall(allocator, tokens, funcs, bindings, args_start, args_end);
    }
    if (std.mem.eql(u8, name, "set")) {
        return evalSetCall(allocator, tokens, funcs, bindings, args_start, args_end);
    }

    var args = std.ArrayList(Value).empty;
    defer {
        freeValues(allocator, args.items);
        args.deinit(allocator);
    }
    try evalArgs(allocator, tokens, funcs, bindings, args_start, args_end, &args);

    if (std.mem.eql(u8, name, "eq")) {
        if (hasUnsupportedValue(args.items)) return .unsupported;
        if (args.items.len != 2 or args.items[0] == .unknown or args.items[1] == .unknown) return .unknown;
        return .{ .bool = valueEq(args.items[0], args.items[1]) };
    }
    if (std.mem.eql(u8, name, "ne")) {
        if (hasUnsupportedValue(args.items)) return .unsupported;
        if (args.items.len != 2 or args.items[0] == .unknown or args.items[1] == .unknown) return .unknown;
        return .{ .bool = !valueEq(args.items[0], args.items[1]) };
    }
    if (std.mem.eql(u8, name, "and")) return evalAndOrCore("and", args.items);
    if (std.mem.eql(u8, name, "or")) return evalAndOrCore("or", args.items);
    if (std.mem.eql(u8, name, "not")) {
        if (hasUnsupportedValue(args.items)) return .unsupported;
        if (args.items.len != 1 or args.items[0] != .bool) return .unknown;
        return .{ .bool = !args.items[0].bool };
    }
    if (findFunc(funcs, name, args.items.len) != null) {
        return evalUserFunc(allocator, tokens, funcs, name, args.items);
    }
    if (std.mem.eql(u8, name, "abs")) return evalAbsCore(args.items);
    if (isConvertCoreName(name)) return evalConvertCore(args.items);
    if (isNumericCoreName(name)) return evalNumericCore(name, args.items);
    if (isBitwiseCoreName(name)) return evalBitwiseCore(name, args.items);
    if (isCountBitsCoreName(name)) return evalCountBitsCore(name, args.items);
    return .unsupported;
}

fn evalArgs(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    bindings: []const Binding,
    start_idx: usize,
    end_idx: usize,
    out: *std.ArrayList(Value),
) anyerror!void {
    var i = start_idx;
    while (i < end_idx) {
        const arg_end = findArgEnd(tokens, i, end_idx);
        {
            const value = try evalExpr(allocator, tokens, funcs, bindings, i, arg_end);
            errdefer freeValue(allocator, value);
            try out.append(allocator, value);
        }
        i = arg_end;
        if (i < end_idx and tokEqToken(tokens[i], ",")) i += 1;
    }
}

fn evalUserFunc(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    name: []const u8,
    args: []const Value,
) anyerror!Value {
    const func = findFunc(funcs, name, args.len) orelse return .unsupported;
    var bindings = std.ArrayList(Binding).empty;
    defer {
        freeBindings(allocator, bindings.items);
        bindings.deinit(allocator);
    }

    var arg_idx: usize = 0;
    var i = func.params_start;
    while (i < func.params_end and arg_idx < args.len) {
        const seg_end = findArgEnd(tokens, i, func.params_end);
        if (tokens[i].kind == .ident and isBindingName(tokens[i].lexeme)) {
            const value = try cloneValue(allocator, args[arg_idx]);
            errdefer freeValue(allocator, value);
            try setBinding(allocator, &bindings, tokens[i].lexeme, value);
        }
        arg_idx += 1;
        i = seg_end;
        if (i < func.params_end and tokEqToken(tokens[i], ",")) i += 1;
    }

    if (func.arrow) {
        return evalExpr(allocator, tokens, funcs, bindings.items, func.body_start, func.body_end);
    }

    if (hasUnsupportedControlFlow(tokens, func.body_start, func.body_end)) return .unsupported;

    i = func.body_start;
    while (i < func.body_end) {
        if (tokEqToken(tokens[i], "if")) {
            const parsed = try evalFuncIfReturn(allocator, tokens, funcs, &bindings, i, func.body_end);
            if (parsed.returned) return parsed.value;
            if (parsed.unsupported) return .unsupported;
            if (parsed.unknown) return .unknown;
            i = parsed.next_idx;
            continue;
        }
        if (tokEqToken(tokens[i], "return")) {
            const line_end = findLineEnd(tokens, i, func.body_end);
            return evalExpr(allocator, tokens, funcs, bindings.items, i + 1, line_end);
        }
        if (try evalBindingLine(allocator, tokens, funcs, &bindings, i, func.body_end)) |line| {
            if (line.unsupported) return .unsupported;
            i = line.next_idx;
            continue;
        }
        i = findLineEnd(tokens, i, func.body_end);
    }
    return .unsupported;
}

fn evalUserFuncMulti(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    name: []const u8,
    args_start: usize,
    args_end: usize,
    outer_bindings: []const Binding,
    expected_count: usize,
) ![]Value {
    var args = std.ArrayList(Value).empty;
    defer {
        freeValues(allocator, args.items);
        args.deinit(allocator);
    }
    try evalArgs(allocator, tokens, funcs, outer_bindings, args_start, args_end, &args);

    const func = findFunc(funcs, name, args.items.len) orelse return error.NoMatchingCall;
    var bindings = std.ArrayList(Binding).empty;
    defer {
        freeBindings(allocator, bindings.items);
        bindings.deinit(allocator);
    }

    var arg_idx: usize = 0;
    var i = func.params_start;
    while (i < func.params_end and arg_idx < args.items.len) {
        const seg_end = findArgEnd(tokens, i, func.params_end);
        if (tokens[i].kind == .ident and isBindingName(tokens[i].lexeme)) {
            const value = try cloneValue(allocator, args.items[arg_idx]);
            errdefer freeValue(allocator, value);
            try setBinding(allocator, &bindings, tokens[i].lexeme, value);
        }
        arg_idx += 1;
        i = seg_end;
        if (i < func.params_end and tokEqToken(tokens[i], ",")) i += 1;
    }

    const range = if (func.arrow) Range{ .start = func.body_start, .end = func.body_end } else blk: {
        if (hasUnsupportedControlFlow(tokens, func.body_start, func.body_end)) return error.NoMatchingCall;
        if (func.body_start >= func.body_end or !tokEqToken(tokens[func.body_start], "return")) return error.NoMatchingCall;
        const line_end = findLineEnd(tokens, func.body_start, func.body_end);
        if (line_end != func.body_end) return error.NoMatchingCall;
        break :blk Range{ .start = func.body_start + 1, .end = line_end };
    };

    if (parseSimpleCall(tokens, range.start, range.end)) |nested| {
        if (findFunc(funcs, nested.name, countArgs(tokens, nested.args_start, nested.args_end)) == null) {
            return allocUnsupportedValues(allocator, expected_count);
        }
        return evalUserFuncMulti(allocator, tokens, funcs, nested.name, nested.args_start, nested.args_end, bindings.items, expected_count);
    }

    var out = std.ArrayList(Value).empty;
    errdefer {
        freeValues(allocator, out.items);
        out.deinit(allocator);
    }
    var expr_start = range.start;
    while (expr_start < range.end) {
        const expr_end = findArgEnd(tokens, expr_start, range.end);
        const value = try evalExpr(allocator, tokens, funcs, bindings.items, expr_start, expr_end);
        errdefer freeValue(allocator, value);
        try out.append(allocator, value);
        expr_start = expr_end;
        if (expr_start < range.end and tokEqToken(tokens[expr_start], ",")) expr_start += 1;
    }
    if (out.items.len <= 1) return error.NoMatchingCall;
    return out.toOwnedSlice(allocator);
}

fn allocUnsupportedValues(allocator: std.mem.Allocator, count: usize) ![]Value {
    if (count <= 1) return error.NoMatchingCall;
    const out = try allocator.alloc(Value, count);
    @memset(out, .unsupported);
    return out;
}

const FuncIfEval = struct {
    next_idx: usize,
    returned: bool,
    unsupported: bool,
    unknown: bool,
    value: Value,
};

fn evalFuncIfReturn(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    bindings: *std.ArrayList(Binding),
    if_idx: usize,
    limit_idx: usize,
) !FuncIfEval {
    const line_end = findLineEnd(tokens, if_idx, limit_idx);
    const return_idx = findTopLevelToken(tokens, if_idx + 1, line_end, "return") orelse
        return .{ .next_idx = line_end, .returned = false, .unsupported = true, .unknown = false, .value = .unsupported };
    const cond = try evalExpr(allocator, tokens, funcs, bindings.items, if_idx + 1, return_idx);
    defer freeValue(allocator, cond);
    if (cond == .unsupported) {
        if (isSingleUnboundIdent(tokens, bindings.items, if_idx + 1, return_idx)) return error.NoMatchingCall;
        return .{ .next_idx = line_end, .returned = false, .unsupported = true, .unknown = false, .value = .unsupported };
    }
    if (cond == .unknown) {
        if (isSingleUnboundIdent(tokens, bindings.items, if_idx + 1, return_idx)) return error.NoMatchingCall;
        return .{ .next_idx = line_end, .returned = false, .unsupported = false, .unknown = true, .value = .unknown };
    }
    if (cond != .bool) return error.NonBoolIfCondition;
    if (!cond.bool) {
        return .{ .next_idx = line_end, .returned = false, .unsupported = false, .unknown = false, .value = .unknown };
    }
    const value = if (return_idx + 1 < line_end)
        try evalExpr(allocator, tokens, funcs, bindings.items, return_idx + 1, line_end)
    else
        Value.nil;
    return .{ .next_idx = line_end, .returned = true, .unsupported = false, .unknown = false, .value = value };
}

fn evalAnd(args: []const Value) Value {
    if (args.len == 0) return .{ .bool = true };
    var saw_unknown = false;
    var saw_unsupported = false;
    for (args) |arg| {
        if (arg == .unsupported) {
            saw_unsupported = true;
            continue;
        }
        if (arg == .unknown) {
            saw_unknown = true;
            continue;
        }
        if (arg != .bool) return .unknown;
        if (!arg.bool) return .{ .bool = false };
    }
    if (saw_unsupported) return .unsupported;
    if (saw_unknown) return .unknown;
    return .{ .bool = true };
}

fn evalAndOrCore(name: []const u8, args: []const Value) Value {
    if (allIntValues(args)) return evalBitwiseCore(name, args);
    if (std.mem.eql(u8, name, "and")) return evalAnd(args);
    return evalOr(args);
}

fn allIntValues(args: []const Value) bool {
    if (args.len == 0) return false;
    for (args) |arg| {
        if (arg != .int) return false;
    }
    return true;
}

fn isSingleUnboundIdent(
    tokens: []const lexer.Token,
    bindings: []const Binding,
    start_idx: usize,
    end_idx: usize,
) bool {
    const trimmed = trimParens(tokens, start_idx, end_idx);
    if (trimmed.end != trimmed.start + 1) return false;
    const tok = tokens[trimmed.start];
    if (tok.kind != .ident) return false;
    if (tokEqToken(tok, "true") or tokEqToken(tok, "false") or tokEqToken(tok, "nil")) return false;
    return lookupBinding(bindings, tok.lexeme) == null;
}

fn evalOr(args: []const Value) Value {
    if (args.len == 0) return .{ .bool = false };
    var saw_unknown = false;
    var saw_unsupported = false;
    for (args) |arg| {
        if (arg == .unsupported) {
            saw_unsupported = true;
            continue;
        }
        if (arg == .unknown) {
            saw_unknown = true;
            continue;
        }
        if (arg != .bool) return .unknown;
        if (arg.bool) return .{ .bool = true };
    }
    if (saw_unsupported) return .unsupported;
    if (saw_unknown) return .unknown;
    return .{ .bool = false };
}

fn hasUnsupportedValue(values: []const Value) bool {
    for (values) |value| {
        if (value == .unsupported) return true;
    }
    return false;
}

fn evalNumericCore(name: []const u8, args: []const Value) Value {
    if (hasUnsupportedValue(args)) return .unsupported;
    if (args.len < 2) return .unknown;
    if (args[0] != .int) return .unknown;
    var out = args[0].int;
    for (args[1..]) |arg| {
        if (arg != .int) return .unknown;
        if (std.mem.eql(u8, name, "add")) out += arg.int else if (std.mem.eql(u8, name, "sub")) out -= arg.int else if (std.mem.eql(u8, name, "mul")) out *= arg.int else if (std.mem.eql(u8, name, "min")) {
            if (arg.int < out) out = arg.int;
        } else if (std.mem.eql(u8, name, "max")) {
            if (arg.int > out) out = arg.int;
        } else if (std.mem.eql(u8, name, "div")) {
            if (arg.int == 0) return .unknown;
            out = @divTrunc(out, arg.int);
        } else if (std.mem.eql(u8, name, "rem")) {
            if (arg.int == 0) return .unknown;
            out = @rem(out, arg.int);
        } else return .unknown;
    }
    return .{ .int = out };
}

fn evalAbsCore(args: []const Value) Value {
    if (hasUnsupportedValue(args)) return .unsupported;
    if (args.len != 1 or args[0] != .int) return .unknown;
    if (args[0].int == std.math.minInt(i128)) return .unknown;
    if (args[0].int < 0) return .{ .int = -args[0].int };
    return args[0];
}

fn evalConvertCore(args: []const Value) Value {
    if (hasUnsupportedValue(args)) return .unsupported;
    if (args.len != 1 or args[0] != .int) return .unknown;
    return args[0];
}

fn evalBitwiseCore(name: []const u8, args: []const Value) Value {
    if (hasUnsupportedValue(args)) return .unsupported;
    if (args.len != 2 or args[0] != .int or args[1] != .int) return .unknown;
    if (args[0].int < 0 or args[1].int < 0) return .unknown;
    const a = std.math.cast(u64, args[0].int) orelse return .unknown;
    const rhs = std.math.cast(u64, args[1].int) orelse return .unknown;
    const b = std.math.cast(u6, args[1].int & 63) orelse return .unknown;
    const out: u64 = if (std.mem.eql(u8, name, "and"))
        a & rhs
    else if (std.mem.eql(u8, name, "or"))
        a | rhs
    else if (std.mem.eql(u8, name, "xor"))
        a ^ rhs
    else if (std.mem.eql(u8, name, "shl"))
        a << b
    else if (std.mem.eql(u8, name, "shr"))
        a >> b
    else if (std.mem.eql(u8, name, "rotl"))
        std.math.rotl(u64, a, b)
    else if (std.mem.eql(u8, name, "rotr"))
        std.math.rotr(u64, a, b)
    else
        return .unknown;
    return .{ .int = @as(i128, @intCast(out)) };
}

fn evalCountBitsCore(name: []const u8, args: []const Value) Value {
    if (hasUnsupportedValue(args)) return .unsupported;
    if (args.len != 1 or args[0] != .int or args[0].int < 0) return .unknown;
    const value = std.math.cast(u64, args[0].int) orelse return .unknown;
    if (value > std.math.maxInt(u32)) return .unknown;
    const out = evalCountBitsU32(name, @as(u32, @intCast(value))) orelse return .unknown;
    return .{ .int = out };
}

fn evalCountBitsU32(name: []const u8, value: u32) ?u7 {
    if (std.mem.eql(u8, name, "clz")) return @as(u7, @intCast(@clz(value)));
    if (std.mem.eql(u8, name, "ctz")) return @as(u7, @intCast(@ctz(value)));
    if (std.mem.eql(u8, name, "popcnt")) return @as(u7, @intCast(@popCount(value)));
    return null;
}

fn valueEq(a: Value, b: Value) bool {
    if (a == .unknown or b == .unknown) return false;
    if (a == .nil and b == .nil) return true;
    if (a == .bool and b == .bool) return a.bool == b.bool;
    if (a == .int and b == .int) return a.int == b.int;
    if (a == .text and b == .text) return std.mem.eql(u8, a.text, b.text);
    if (a == .object and b == .object) return objectEq(a.object, b.object);
    return false;
}

fn objectEq(a: []const FieldValue, b: []const FieldValue) bool {
    if (a.len != b.len) return false;
    for (a, 0..) |field, idx| {
        if (!std.mem.eql(u8, field.name, b[idx].name)) return false;
        if (!valueEq(field.value, b[idx].value)) return false;
    }
    return true;
}

fn lookupBinding(bindings: []const Binding, name: []const u8) ?Value {
    var i = bindings.len;
    while (i > 0) {
        i -= 1;
        if (std.mem.eql(u8, bindings[i].name, name)) return bindings[i].value;
    }
    return null;
}

fn setBinding(allocator: std.mem.Allocator, bindings: *std.ArrayList(Binding), name: []const u8, value: Value) !void {
    var i = bindings.items.len;
    while (i > 0) {
        i -= 1;
        if (!std.mem.eql(u8, bindings.items[i].name, name)) continue;
        freeValue(allocator, bindings.items[i].value);
        bindings.items[i].value = value;
        return;
    }
    try bindings.append(allocator, .{ .name = name, .value = value });
}

fn freeBindings(allocator: std.mem.Allocator, bindings: []Binding) void {
    for (bindings) |binding| freeValue(allocator, binding.value);
}

fn freeValues(allocator: std.mem.Allocator, values: []const Value) void {
    for (values) |value| freeValue(allocator, value);
}

fn freeValue(allocator: std.mem.Allocator, value: Value) void {
    switch (value) {
        .text => |text| allocator.free(text),
        .object => |fields| {
            for (fields) |field| freeValue(allocator, field.value);
            allocator.free(fields);
        },
        else => {},
    }
}

fn cloneValue(allocator: std.mem.Allocator, value: Value) std.mem.Allocator.Error!Value {
    return switch (value) {
        .text => |text| .{ .text = try allocator.dupe(u8, text) },
        .object => |fields| .{ .object = try cloneFields(allocator, fields) },
        else => value,
    };
}

fn cloneFields(allocator: std.mem.Allocator, fields: []const FieldValue) std.mem.Allocator.Error![]FieldValue {
    const out = try allocator.alloc(FieldValue, fields.len);
    errdefer allocator.free(out);
    var idx: usize = 0;
    errdefer {
        for (out[0..idx]) |field| freeValue(allocator, field.value);
    }
    for (fields, 0..) |field, i| {
        out[i] = .{ .name = field.name, .value = try cloneValue(allocator, field.value) };
        idx += 1;
    }
    return out;
}

fn isStructLiteralStart(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 1 >= end_idx) return false;
    if (tokens[start_idx].kind != .ident) return false;
    if (!std.ascii.isUpper(tokens[start_idx].lexeme[0])) return false;
    return tokEqToken(tokens[start_idx + 1], "{");
}

fn evalStructLiteral(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    bindings: []const Binding,
    start_idx: usize,
    end_idx: usize,
) anyerror!Value {
    const open_idx = start_idx + 1;
    const close_idx = findMatchingInRange(tokens, open_idx, "{", "}", end_idx) catch return .unknown;
    if (close_idx + 1 != end_idx) return .unknown;

    var fields = std.ArrayList(FieldValue).empty;
    errdefer {
        for (fields.items) |field| freeValue(allocator, field.value);
        fields.deinit(allocator);
    }

    var i = open_idx + 1;
    while (i < close_idx) {
        const field_end = findArgEnd(tokens, i, close_idx);
        const eq_idx = findTopLevelToken(tokens, i, field_end, "=") orelse return .unknown;
        if (tokens[i].kind != .ident) return .unknown;
        {
            const value = try evalExpr(allocator, tokens, funcs, bindings, eq_idx + 1, field_end);
            errdefer freeValue(allocator, value);
            try fields.append(allocator, .{ .name = tokens[i].lexeme, .value = value });
        }
        i = field_end;
        if (i < close_idx and tokEqToken(tokens[i], ",")) i += 1;
    }

    return .{ .object = try fields.toOwnedSlice(allocator) };
}

fn evalGetCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    bindings: []const Binding,
    args_start: usize,
    args_end: usize,
) anyerror!Value {
    const first_end = findArgEnd(tokens, args_start, args_end);
    const target = try evalExpr(allocator, tokens, funcs, bindings, args_start, first_end);
    defer freeValue(allocator, target);
    if (target == .unsupported) return .unsupported;
    if (target != .object) return .unknown;

    var current = target;
    var i = first_end;
    if (i < args_end and tokEqToken(tokens[i], ",")) i += 1;
    while (i < args_end) {
        const arg_end = findArgEnd(tokens, i, args_end);
        if (i + 1 != arg_end or !isFieldSeg(tokens[i])) return .unknown;
        current = getObjectField(current, tokens[i].lexeme[1..]) orelse return .unknown;
        i = arg_end;
        if (i < args_end and tokEqToken(tokens[i], ",")) i += 1;
    }
    return cloneValue(allocator, current);
}

fn evalSetCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    bindings: []const Binding,
    args_start: usize,
    args_end: usize,
) anyerror!Value {
    const first_end = findArgEnd(tokens, args_start, args_end);
    const target = try evalExpr(allocator, tokens, funcs, bindings, args_start, first_end);
    defer freeValue(allocator, target);
    if (target == .unsupported) return .unsupported;
    if (target != .object) return .unknown;

    const value_start = findFinalArgStart(tokens, first_end, args_end) orelse return .unknown;
    const path_start = nextArgStart(tokens, first_end, args_end) orelse return .unknown;
    if (path_start >= value_start) return .unknown;
    if (!singleFieldPath(tokens, path_start, value_start)) return .unknown;
    const field_name = tokens[path_start].lexeme[1..];
    const old_value = getObjectField(target, field_name) orelse return .unknown;
    const new_value = if (isLambdaExpr(tokens, value_start, args_end))
        try evalSetLambdaValue(allocator, tokens, funcs, old_value, value_start, args_end)
    else
        try evalExpr(allocator, tokens, funcs, bindings, value_start, args_end);
    errdefer freeValue(allocator, new_value);
    if (new_value == .unsupported) return .unsupported;

    return setObjectField(allocator, target.object, field_name, new_value);
}

fn getObjectField(value: Value, name: []const u8) ?Value {
    if (value != .object) return null;
    for (value.object) |field| {
        if (std.mem.eql(u8, field.name, name)) return field.value;
    }
    return null;
}

fn setObjectField(allocator: std.mem.Allocator, fields: []const FieldValue, name: []const u8, new_value: Value) !Value {
    const out = try allocator.alloc(FieldValue, fields.len);
    errdefer allocator.free(out);
    var idx: usize = 0;
    errdefer {
        for (out[0..idx]) |field| freeValue(allocator, field.value);
    }
    for (fields, 0..) |field, i| {
        out[i].name = field.name;
        out[i].value = if (std.mem.eql(u8, field.name, name))
            new_value
        else
            try cloneValue(allocator, field.value);
        idx += 1;
    }
    return .{ .object = out };
}

fn evalSetLambdaValue(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    old_value: Value,
    start_idx: usize,
    end_idx: usize,
) anyerror!Value {
    const close_params = findMatchingInRange(tokens, start_idx, "(", ")", end_idx) catch return .unknown;
    const body_start = lambdaBodyStart(tokens, close_params + 1, end_idx) orelse return .unknown;
    if (tokens[start_idx + 1].kind != .ident) return .unknown;

    var lambda_bindings = std.ArrayList(Binding).empty;
    defer {
        freeBindings(allocator, lambda_bindings.items);
        lambda_bindings.deinit(allocator);
    }
    const value = try cloneValue(allocator, old_value);
    errdefer freeValue(allocator, value);
    try setBinding(allocator, &lambda_bindings, tokens[start_idx + 1].lexeme, value);
    return evalExpr(allocator, tokens, funcs, lambda_bindings.items, body_start, end_idx);
}

fn isFieldSeg(tok: lexer.Token) bool {
    return tok.kind == .ident and tok.lexeme.len > 1 and tok.lexeme[0] == '.' and std.ascii.isLower(tok.lexeme[1]);
}

fn singleFieldPath(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    const path_end = findArgEnd(tokens, start_idx, end_idx);
    return path_end == end_idx - 1 and isFieldSeg(tokens[start_idx]) and tokEqToken(tokens[path_end], ",");
}

fn findFinalArgStart(tokens: []const lexer.Token, first_end: usize, args_end: usize) ?usize {
    var current = nextArgStart(tokens, first_end, args_end) orelse return null;
    var last = current;
    while (current < args_end) {
        const arg_end = findArgEnd(tokens, current, args_end);
        last = current;
        current = nextArgStart(tokens, arg_end, args_end) orelse break;
    }
    return last;
}

fn nextArgStart(tokens: []const lexer.Token, arg_end: usize, args_end: usize) ?usize {
    if (arg_end >= args_end) return null;
    if (!tokEqToken(tokens[arg_end], ",")) return null;
    const next = arg_end + 1;
    if (next >= args_end) return null;
    return next;
}

fn isLambdaExpr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx >= end_idx or !tokEqToken(tokens[start_idx], "(")) return false;
    const close_params = findMatchingInRange(tokens, start_idx, "(", ")", end_idx) catch return false;
    return lambdaBodyStart(tokens, close_params + 1, end_idx) != null;
}

fn lambdaBodyStart(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (isArrowAt(tokens, start_idx)) return start_idx + 2;
    if (!isReturnArrowAt(tokens, start_idx)) return null;
    var i = start_idx + 2;
    while (i < end_idx) : (i += 1) {
        if (isArrowAt(tokens, i)) return i + 2;
    }
    return null;
}

fn isArrowAt(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 1 < tokens.len and tokEqToken(tokens[idx], "=") and tokEqToken(tokens[idx + 1], ">");
}

fn isReturnArrowAt(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 1 < tokens.len and tokEqToken(tokens[idx], "-") and tokEqToken(tokens[idx + 1], ">");
}

fn findFunc(funcs: []const FuncDecl, name: []const u8, arg_count: usize) ?FuncDecl {
    for (funcs) |func| {
        if (!std.mem.eql(u8, func.name, name)) continue;
        if (func.param_max == null) continue;
        if (func.param_min != arg_count) continue;
        return func;
    }
    var best_func: ?FuncDecl = null;
    for (funcs) |func| {
        if (!std.mem.eql(u8, func.name, name)) continue;
        if (arg_count < func.param_min) continue;
        if (func.param_max) |max_count| {
            if (arg_count > max_count) continue;
        }
        if (best_func == null or func.param_min > best_func.?.param_min) {
            best_func = func;
        }
    }
    return best_func;
}

fn countFixedParams(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    var count: usize = 0;
    var i = start_idx;
    while (i < end_idx) {
        const seg_end = findArgEnd(tokens, i, end_idx);
        if (seg_end > i and isVariadicParam(tokens, i, seg_end)) return count;
        if (seg_end > i) count += 1;
        i = seg_end;
        if (i < end_idx and tokEqToken(tokens[i], ",")) i += 1;
    }
    return count;
}

fn countArgs(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    if (start_idx >= end_idx) return 0;
    var count: usize = 0;
    var i = start_idx;
    while (i < end_idx) {
        const seg_end = findArgEnd(tokens, i, end_idx);
        if (seg_end > i) count += 1;
        i = seg_end;
        if (i < end_idx and tokEqToken(tokens[i], ",")) i += 1;
    }
    return count;
}

fn hasVariadicParam(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i < end_idx) {
        const seg_end = findArgEnd(tokens, i, end_idx);
        if (seg_end > i and isVariadicParam(tokens, i, seg_end)) return true;
        i = seg_end;
        if (i < end_idx and tokEqToken(tokens[i], ",")) i += 1;
    }
    return false;
}

fn isVariadicParam(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    return start_idx + 2 < end_idx and isSpreadToken(tokens[start_idx + 1]);
}

fn isSpreadToken(tok: lexer.Token) bool {
    return tok.kind == .symbol and tokEqToken(tok, "...");
}

fn findFuncBodyStart(tokens: []const lexer.Token, start_idx: usize) ?usize {
    var i = start_idx;
    while (i < tokens.len) : (i += 1) {
        if (tokEqToken(tokens[i], "{")) return i;
        if (i + 1 < tokens.len and tokEqToken(tokens[i], "=") and tokEqToken(tokens[i + 1], ">")) return i + 2;
    }
    return null;
}

fn findArgEnd(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEqToken(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tokEqToken(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tokEqToken(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEqToken(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (tokEqToken(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tokEqToken(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tokEqToken(tokens[i], ",")) return i;
    }
    return end_idx;
}

fn findTopLevelToken(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, lexeme: []const u8) ?usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEqToken(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tokEqToken(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tokEqToken(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEqToken(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (tokEqToken(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tokEqToken(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tokEqToken(tokens[i], lexeme)) return i;
    }
    return null;
}

fn findLineEnd(tokens: []const lexer.Token, start_idx: usize, limit_idx: usize) usize {
    if (start_idx >= limit_idx) return start_idx;
    const line = tokens[start_idx].line;
    var i = start_idx;
    while (i < limit_idx and tokens[i].line == line) : (i += 1) {}
    return i;
}

fn findStmtEnd(tokens: []const lexer.Token, start_idx: usize, limit_idx: usize) usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < limit_idx) : (i += 1) {
        if (tokEqToken(tokens[i], "(")) {
            depth_paren += 1;
        } else if (tokEqToken(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
        } else if (tokEqToken(tokens[i], "{")) {
            depth_brace += 1;
        } else if (tokEqToken(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
        } else if (tokEqToken(tokens[i], "<")) {
            depth_angle += 1;
        } else if (tokEqToken(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
        }

        if (depth_paren != 0 or depth_brace != 0 or depth_angle != 0) continue;
        if (i + 1 >= limit_idx or tokens[i + 1].line != tokens[i].line) return i + 1;
    }
    return limit_idx;
}

fn findMatchingToken(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8) !usize {
    return findMatchingInRange(tokens, open_idx, open, close, tokens.len);
}

fn findMatchingInRange(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8, limit: usize) !usize {
    if (open_idx >= limit or !tokEqToken(tokens[open_idx], open)) return error.InvalidGroupStart;

    var depth: usize = 0;
    var i = open_idx;
    while (i < limit) : (i += 1) {
        if (tokEqToken(tokens[i], open)) {
            depth += 1;
            continue;
        }
        if (!tokEqToken(tokens[i], close)) continue;
        if (depth == 0) return error.InvalidGroupDepth;
        depth -= 1;
        if (depth == 0) return i;
    }
    return error.UnterminatedGroup;
}

fn parseInt(raw: []const u8) ?i128 {
    if (raw.len == 0) return null;
    return std.fmt.parseInt(i128, raw, 10) catch null;
}

fn decodeStringLiteral(allocator: std.mem.Allocator, raw: []const u8) ![]const u8 {
    if (raw.len >= 2 and raw[0] == '"' and raw[raw.len - 1] == '"') {
        return decodeQuotedString(allocator, raw[1 .. raw.len - 1]);
    }
    if (raw.len >= 2 and raw[0] == '\\' and raw[1] == '\\') {
        return decodeLineString(allocator, raw);
    }
    return allocator.dupe(u8, raw);
}

fn decodeQuotedString(allocator: std.mem.Allocator, body: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    var i: usize = 0;
    while (i < body.len) {
        if (body[i] != '\\') {
            try out.append(allocator, body[i]);
            i += 1;
            continue;
        }

        i += 1;
        if (i >= body.len) return error.InvalidStringEscape;
        const esc = body[i];
        switch (esc) {
            '"' => try out.append(allocator, '"'),
            '\\' => try out.append(allocator, '\\'),
            'n' => try out.append(allocator, '\n'),
            'r' => try out.append(allocator, '\r'),
            't' => try out.append(allocator, '\t'),
            'x' => {
                if (i + 2 >= body.len) return error.InvalidStringEscape;
                const hi = hexValue(body[i + 1]) orelse return error.InvalidStringEscape;
                const lo = hexValue(body[i + 2]) orelse return error.InvalidStringEscape;
                try out.append(allocator, (hi << 4) | lo);
                i += 2;
            },
            else => return error.InvalidStringEscape,
        }
        i += 1;
    }

    return out.toOwnedSlice(allocator);
}

fn decodeLineString(allocator: std.mem.Allocator, raw: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    var line_start: usize = 0;
    var first = true;
    while (line_start <= raw.len) {
        var line_end = line_start;
        while (line_end < raw.len and raw[line_end] != '\n' and raw[line_end] != '\r') : (line_end += 1) {}

        var text_start = line_start;
        while (text_start < line_end and (raw[text_start] == ' ' or raw[text_start] == '\t')) : (text_start += 1) {}
        if (text_start + 1 >= line_end or raw[text_start] != '\\' or raw[text_start + 1] != '\\') {
            return error.InvalidStringEscape;
        }

        if (!first) try out.append(allocator, '\n');
        first = false;
        try out.appendSlice(allocator, raw[text_start + 2 .. line_end]);

        if (line_end >= raw.len) break;
        line_start = line_end + 1;
        if (raw[line_end] == '\r' and line_start < raw.len and raw[line_start] == '\n') {
            line_start += 1;
        }
    }

    return out.toOwnedSlice(allocator);
}

fn hexValue(ch: u8) ?u8 {
    if (ch >= '0' and ch <= '9') return ch - '0';
    if (ch >= 'a' and ch <= 'f') return ch - 'a' + 10;
    if (ch >= 'A' and ch <= 'F') return ch - 'A' + 10;
    return null;
}

fn isNumericCoreName(name: []const u8) bool {
    return std.mem.eql(u8, name, "add") or
        std.mem.eql(u8, name, "sub") or
        std.mem.eql(u8, name, "mul") or
        std.mem.eql(u8, name, "div") or
        std.mem.eql(u8, name, "rem") or
        std.mem.eql(u8, name, "min") or
        std.mem.eql(u8, name, "max");
}

fn isConvertCoreName(name: []const u8) bool {
    return std.mem.eql(u8, name, "to_u8") or
        std.mem.eql(u8, name, "to_u16") or
        std.mem.eql(u8, name, "to_u32") or
        std.mem.eql(u8, name, "to_u64") or
        std.mem.eql(u8, name, "to_usize") or
        std.mem.eql(u8, name, "to_isize") or
        std.mem.eql(u8, name, "to_i8") or
        std.mem.eql(u8, name, "to_i16") or
        std.mem.eql(u8, name, "to_i32") or
        std.mem.eql(u8, name, "to_i64") or
        std.mem.eql(u8, name, "to_f32") or
        std.mem.eql(u8, name, "to_f64");
}

fn isBitwiseCoreName(name: []const u8) bool {
    return std.mem.eql(u8, name, "and") or
        std.mem.eql(u8, name, "or") or
        std.mem.eql(u8, name, "xor") or
        std.mem.eql(u8, name, "shl") or
        std.mem.eql(u8, name, "shr") or
        std.mem.eql(u8, name, "rotl") or
        std.mem.eql(u8, name, "rotr");
}

fn isCountBitsCoreName(name: []const u8) bool {
    return std.mem.eql(u8, name, "clz") or
        std.mem.eql(u8, name, "ctz") or
        std.mem.eql(u8, name, "popcnt");
}

fn isFuncDeclStart(tokens: []const lexer.Token, i: usize) bool {
    if (i + 1 >= tokens.len) return false;
    if (tokens[i].kind != .ident) return false;
    if (tokEqToken(tokens[i], "test")) return false;
    if (!isFuncDeclName(tokens[i].lexeme)) return false;
    return tokEqToken(tokens[i + 1], "(");
}

fn publicFuncName(name: []const u8) []const u8 {
    if (name.len != 0 and name[0] == '.') return name[1..];
    return name;
}

fn isFuncDeclName(name: []const u8) bool {
    if (name.len == 0) return false;
    if (isLowerIdentName(name)) return true;
    if (name[0] == '.') return isLowerIdentName(name[1..]);
    return false;
}

fn isBindingName(name: []const u8) bool {
    if (name.len == 0) return false;
    return std.ascii.isLower(name[0]) or name[0] == '_';
}

fn isLowerIdentName(name: []const u8) bool {
    if (name.len == 0) return false;
    if (!std.ascii.isLower(name[0])) return false;

    var prev_underscore = false;
    for (name[1..]) |ch| {
        if (ch == '_') {
            if (prev_underscore) return false;
            prev_underscore = true;
            continue;
        }
        if (!std.ascii.isLower(ch) and !std.ascii.isDigit(ch)) return false;
        prev_underscore = false;
    }

    return !prev_underscore;
}

fn tokEqToken(tok: lexer.Token, lexeme: []const u8) bool {
    return std.mem.eql(u8, tok.lexeme, lexeme);
}

test "private function declaration is callable by public name" {
    const allocator = std.testing.allocator;
    const source =
        \\.double(x i32) i32 => mul(x, 2)
    ;
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);

    const funcs = try collectTopLevelFuncs(allocator, tokens);
    defer allocator.free(funcs);

    try std.testing.expectEqual(@as(usize, 1), funcs.len);
    try std.testing.expectEqualStrings("double", funcs[0].name);
    try std.testing.expect(findFunc(funcs, "double", 1) != null);
}

test "variadic function matches zero trailing args" {
    const allocator = std.testing.allocator;
    const source =
        \\count(rest ...i32) -> i32 => 0
    ;
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);

    const funcs = try collectTopLevelFuncs(allocator, tokens);
    defer allocator.free(funcs);

    try std.testing.expect(findFunc(funcs, "count", 0) != null);
}

test "fixed arity function wins over variadic function" {
    const allocator = std.testing.allocator;
    const source =
        \\pick(rest ...i32) -> i32 => 2
        \\pick(x i32) -> i32 => 1
    ;
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);

    const funcs = try collectTopLevelFuncs(allocator, tokens);
    defer allocator.free(funcs);

    const func = findFunc(funcs, "pick", 1) orelse return error.TestExpectedEqual;
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

    const funcs = try collectTopLevelFuncs(allocator, tokens);
    defer allocator.free(funcs);

    const func = findFunc(funcs, "pick", 2) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("2", tokens[func.body_start].lexeme);
}
