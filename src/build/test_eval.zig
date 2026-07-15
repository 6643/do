const std = @import("std");
const lexer = @import("lexer.zig");
const model = @import("test_values.zig");

const Value = model.Value;
const Binding = model.Binding;
const FieldValue = model.FieldValue;
const FuncDecl = model.FuncDecl;
const TestStatus = model.TestStatus;
const TestDecl = model.TestDecl;
const value_eq = model.value_eq;
const lookup_binding = model.lookup_binding;
const set_binding = model.set_binding;
const free_bindings = model.free_bindings;
const free_values = model.free_values;
const free_value = model.free_value;
const clone_value = model.clone_value;
const clone_fields = model.clone_fields;
const get_object_field = model.get_object_field;
const set_object_field = model.set_object_field;

pub fn eval_test(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    decl: TestDecl,
) !TestStatus {
    var bindings = std.ArrayList(Binding).empty;
    defer {
        free_bindings(allocator, bindings.items);
        bindings.deinit(allocator);
    }
    const flow = try eval_test_statements(allocator, tokens, funcs, &bindings, decl.body_start, decl.body_end);
    if (flow.returned) return if (flow.unsupported) .skip else .pass;
    if (flow.unknown or flow.known_false) return .fail;
    if (flow.unsupported) return .skip;
    return .pass;
}

fn has_unsupported_control_flow(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i < end_idx) {
        if (tok_eq_token(tokens[i], "else")) return true;
        if (tok_eq_token(tokens[i], "defer")) return true;
        if (tok_eq_token(tokens[i], "loop")) {
            const static_loop = static_noop_break_loop(tokens, i, end_idx) orelse return true;
            i = static_loop.next_idx;
            continue;
        }
        if (!tok_eq_token(tokens[i], "if")) {
            i += 1;
            continue;
        }
        const line_end = find_line_end(tokens, i, end_idx);
        if (find_top_level_token(tokens, i + 1, line_end, "{") != null) return true;
        i += 1;
    }
    return false;
}

const StaticLoop = struct {
    next_idx: usize,
};

fn static_noop_break_loop(tokens: []const lexer.Token, loop_idx: usize, end_idx: usize) ?StaticLoop {
    const open_idx = loop_idx + 1;
    if (open_idx >= end_idx or !tok_eq_token(tokens[open_idx], "{")) return null;
    const close_idx = find_matching_in_range(tokens, open_idx, "{", "}", end_idx) catch return null;
    const break_idx = open_idx + 1;
    if (break_idx >= close_idx or !tok_eq_token(tokens[break_idx], "break")) return null;
    if (break_idx + 1 != close_idx) return null;
    return .{ .next_idx = close_idx + 1 };
}

const IfEval = struct {
    next_idx: usize,
    returned: bool,
    unsupported: bool,
    unknown: bool,
};

const TestFlow = struct {
    next_idx: usize,
    returned: bool,
    unsupported: bool,
    unknown: bool,
    known_false: bool,
};

fn eval_test_statements(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    bindings: *std.ArrayList(Binding),
    start_idx: usize,
    end_idx: usize,
) anyerror!TestFlow {
    var flow = TestFlow{
        .next_idx = end_idx,
        .returned = false,
        .unsupported = false,
        .unknown = false,
        .known_false = false,
    };
    var i = start_idx;
    while (i < end_idx) {
        if (tok_eq_token(tokens[i], "defer")) {
            flow.unsupported = true;
            flow.next_idx = end_idx;
            return flow;
        }
        if (tok_eq_token(tokens[i], "loop")) {
            const static_loop = static_noop_break_loop(tokens, i, end_idx) orelse {
                flow.unsupported = true;
                flow.next_idx = end_idx;
                return flow;
            };
            i = static_loop.next_idx;
            continue;
        }
        if (tok_eq_token(tokens[i], "if")) {
            if (try eval_test_if_else_block(allocator, tokens, funcs, bindings, i, end_idx)) |block| {
                if (block.returned) return block;
                if (block.unsupported) flow.unsupported = true;
                if (block.unknown) flow.unknown = true;
                if (block.known_false) flow.known_false = true;
                i = block.next_idx;
                continue;
            }
            const parsed = try eval_if_return(allocator, tokens, funcs, bindings, i, end_idx);
            if (parsed.returned) {
                flow.returned = true;
                flow.unsupported = flow.unsupported or parsed.unsupported;
                flow.next_idx = parsed.next_idx;
                return flow;
            }
            if (parsed.unsupported) flow.unsupported = true else if (parsed.unknown) flow.unknown = true else flow.known_false = true;
            i = parsed.next_idx;
            continue;
        }
        if (tok_eq_token(tokens[i], "return")) {
            flow.returned = true;
            flow.next_idx = find_line_end(tokens, i, end_idx);
            return flow;
        }
        if (try eval_binding_line(allocator, tokens, funcs, bindings, i, end_idx)) |line| {
            if (line.unsupported) flow.unsupported = true;
            i = line.next_idx;
            continue;
        }
        i = find_line_end(tokens, i, end_idx);
    }
    return flow;
}

fn eval_test_if_else_block(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    bindings: *std.ArrayList(Binding),
    if_idx: usize,
    limit_idx: usize,
) anyerror!?TestFlow {
    const line_end = find_line_end(tokens, if_idx, limit_idx);
    const open_then = find_top_level_open_brace(tokens, if_idx + 1, line_end) orelse return null;
    const then_close = try find_matching_token(tokens, open_then, "{", "}");
    if (then_close + 2 >= limit_idx or !tok_eq_token(tokens[then_close + 1], "else") or !tok_eq_token(tokens[then_close + 2], "{")) {
        return null;
    }
    const open_else = then_close + 2;
    const else_close = try find_matching_token(tokens, open_else, "{", "}");

    const cond = try eval_expr(allocator, tokens, funcs, bindings.items, if_idx + 1, open_then);
    defer free_value(allocator, cond);
    if (cond == .unsupported) {
        if (is_single_unbound_ident(tokens, bindings.items, if_idx + 1, open_then)) return error.NoMatchingCall;
        return .{ .next_idx = else_close + 1, .returned = false, .unsupported = true, .unknown = false, .known_false = false };
    }
    if (cond == .unknown) {
        if (is_single_unbound_ident(tokens, bindings.items, if_idx + 1, open_then)) return error.NoMatchingCall;
        return .{ .next_idx = else_close + 1, .returned = false, .unsupported = false, .unknown = true, .known_false = false };
    }
    if (cond != .bool) return error.NonBoolIfCondition;

    const branch_start = if (cond.bool) open_then + 1 else open_else + 1;
    const branch_end = if (cond.bool) then_close else else_close;
    var branch = try eval_test_statements(allocator, tokens, funcs, bindings, branch_start, branch_end);
    branch.next_idx = else_close + 1;
    return branch;
}

fn eval_if_return(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    bindings: *std.ArrayList(Binding),
    if_idx: usize,
    limit_idx: usize,
) !IfEval {
    const line_end = find_line_end(tokens, if_idx, limit_idx);
    const return_idx = find_top_level_token(tokens, if_idx + 1, line_end, "return") orelse
        return .{ .next_idx = line_end, .returned = false, .unsupported = true, .unknown = false };
    const cond = try eval_expr(allocator, tokens, funcs, bindings.items, if_idx + 1, return_idx);
    defer free_value(allocator, cond);
    if (cond == .unsupported) {
        if (is_single_unbound_ident(tokens, bindings.items, if_idx + 1, return_idx)) return error.NoMatchingCall;
        return .{ .next_idx = line_end, .returned = false, .unsupported = true, .unknown = false };
    }
    if (cond == .unknown) {
        if (is_single_unbound_ident(tokens, bindings.items, if_idx + 1, return_idx)) return error.NoMatchingCall;
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

fn eval_binding_line(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    bindings: *std.ArrayList(Binding),
    start_idx: usize,
    limit_idx: usize,
) !?LineEval {
    const line_end = find_stmt_end(tokens, start_idx, limit_idx);
    const eq_idx = find_top_level_token(tokens, start_idx, line_end, "=") orelse return null;
    if (try eval_multi_binding_line(allocator, tokens, funcs, bindings, start_idx, eq_idx, line_end)) |line| {
        return line;
    }
    if (eq_idx == start_idx) return null;
    const name_idx = start_idx;
    if (tokens[name_idx].kind != .ident) return null;
    if (!is_binding_name(tokens[name_idx].lexeme)) return null;

    const value = try eval_expr(allocator, tokens, funcs, bindings.items, eq_idx + 1, line_end);
    errdefer free_value(allocator, value);
    const unsupported = value == .unsupported;
    try set_binding(allocator, bindings, tokens[name_idx].lexeme, value);
    return .{ .next_idx = line_end, .unsupported = unsupported };
}

fn eval_multi_binding_line(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    bindings: *std.ArrayList(Binding),
    start_idx: usize,
    eq_idx: usize,
    line_end: usize,
) !?LineEval {
    if (find_top_level_token(tokens, start_idx, eq_idx, ",") == null) return null;
    const call = parse_simple_call(tokens, eq_idx + 1, line_end) orelse return null;
    const lhs_count = try count_multi_binding_lhs(tokens, start_idx, eq_idx);
    if (call.has_type_args) {
        try bind_unsupported_values(allocator, tokens, bindings, start_idx, eq_idx);
        return .{ .next_idx = line_end, .unsupported = true };
    }
    if (find_func(funcs, call.name, count_args(tokens, call.args_start, call.args_end)) == null) {
        try bind_unsupported_values(allocator, tokens, bindings, start_idx, eq_idx);
        return .{ .next_idx = line_end, .unsupported = true };
    }
    const values = try eval_user_func_multi(allocator, tokens, funcs, call.name, call.args_start, call.args_end, bindings.items, lhs_count);
    defer {
        free_values(allocator, values);
        allocator.free(values);
    }
    if (lhs_count != values.len) return error.NoMatchingCall;
    const unsupported = has_unsupported_value(values);

    var value_idx: usize = 0;
    var lhs_start = start_idx;
    while (lhs_start < eq_idx) {
        const lhs_end = find_arg_end(tokens, lhs_start, eq_idx);
        const value = try clone_value(allocator, values[value_idx]);
        errdefer free_value(allocator, value);
        try set_binding(allocator, bindings, tokens[lhs_start].lexeme, value);
        value_idx += 1;
        lhs_start = lhs_end;
        if (lhs_start < eq_idx and tok_eq_token(tokens[lhs_start], ",")) lhs_start += 1;
    }
    return .{ .next_idx = line_end, .unsupported = unsupported };
}

fn count_multi_binding_lhs(tokens: []const lexer.Token, start_idx: usize, eq_idx: usize) !usize {
    var count: usize = 0;
    var lhs_start = start_idx;
    while (lhs_start < eq_idx) {
        const lhs_end = find_arg_end(tokens, lhs_start, eq_idx);
        if (lhs_end != lhs_start + 1 or tokens[lhs_start].kind != .ident or !is_binding_name(tokens[lhs_start].lexeme)) {
            return error.NoMatchingCall;
        }
        count += 1;
        lhs_start = lhs_end;
        if (lhs_start < eq_idx and tok_eq_token(tokens[lhs_start], ",")) lhs_start += 1;
    }
    if (count <= 1) return error.NoMatchingCall;
    return count;
}

fn bind_unsupported_values(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    bindings: *std.ArrayList(Binding),
    start_idx: usize,
    eq_idx: usize,
) !void {
    var lhs_start = start_idx;
    while (lhs_start < eq_idx) {
        const lhs_end = find_arg_end(tokens, lhs_start, eq_idx);
        try set_binding(allocator, bindings, tokens[lhs_start].lexeme, .unsupported);
        lhs_start = lhs_end;
        if (lhs_start < eq_idx and tok_eq_token(tokens[lhs_start], ",")) lhs_start += 1;
    }
}

fn eval_expr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    bindings: []const Binding,
    start_idx: usize,
    end_idx: usize,
) anyerror!Value {
    const trimmed = trim_parens(tokens, start_idx, end_idx);
    if (trimmed.start >= trimmed.end) return .unknown;
    if (trimmed.end == trimmed.start + 1) return eval_atom(allocator, tokens, tokens[trimmed.start], bindings);

    if (is_struct_literal_start(tokens, trimmed.start, trimmed.end)) {
        return eval_struct_literal(allocator, tokens, funcs, bindings, trimmed.start, trimmed.end);
    }

    if (parse_simple_call(tokens, trimmed.start, trimmed.end)) |call| {
        if (call.has_type_args) return .unsupported;
        return eval_call(allocator, tokens, funcs, bindings, trimmed.start, call.args_start, call.args_end);
    }
    if (tok_eq_token(tokens[trimmed.start], "@") and trimmed.start + 2 < trimmed.end and tokens[trimmed.start + 1].kind == .ident and tok_eq_token(tokens[trimmed.start + 2], "(")) {
        const close_paren = find_matching_in_range(tokens, trimmed.start + 2, "(", ")", trimmed.end) catch return .unknown;
        if (close_paren + 1 != trimmed.end) return .unknown;
        return eval_call(allocator, tokens, funcs, bindings, trimmed.start + 1, trimmed.start + 3, close_paren);
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
    has_type_args: bool = false,
};

fn trim_parens(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) Range {
    var start = start_idx;
    var end = end_idx;
    while (start + 1 < end and tok_eq_token(tokens[start], "(")) {
        const close = find_matching_in_range(tokens, start, "(", ")", end) catch break;
        if (close + 1 != end) break;
        start += 1;
        end -= 1;
    }
    return .{ .start = start, .end = end };
}

fn parse_simple_call(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?SimpleCall {
    const trimmed = trim_parens(tokens, start_idx, end_idx);
    if (trimmed.start + 2 > trimmed.end) return null;
    if (tokens[trimmed.start].kind != .ident) return null;
    var open_paren = trimmed.start + 1;
    var has_type_args = false;
    if (tok_eq_token(tokens[open_paren], "<")) {
        const close_angle = find_matching_in_range(tokens, open_paren, "<", ">", trimmed.end) catch return null;
        open_paren = close_angle + 1;
        has_type_args = true;
    }
    if (open_paren >= trimmed.end or !tok_eq_token(tokens[open_paren], "(")) return null;
    const close_paren = find_matching_in_range(tokens, open_paren, "(", ")", trimmed.end) catch return null;
    if (close_paren + 1 != trimmed.end) return null;
    return .{
        .name = tokens[trimmed.start].lexeme,
        .args_start = open_paren + 1,
        .args_end = close_paren,
        .has_type_args = has_type_args,
    };
}

fn eval_atom(allocator: std.mem.Allocator, tokens: []const lexer.Token, tok: lexer.Token, bindings: []const Binding) anyerror!Value {
    if (tok.kind == .number) return .{ .int = parse_int(tok.lexeme) orelse return .unknown };
    if (tok.kind == .string) return .{ .text = try decode_string_literal(allocator, tok.lexeme) };
    if (tok_eq_token(tok, "true")) return .{ .bool = true };
    if (tok_eq_token(tok, "false")) return .{ .bool = false };
    if (tok_eq_token(tok, "nil")) return .nil;
    if (tok.kind == .ident) {
        if (lookup_binding(bindings, tok.lexeme)) |value| return clone_value(allocator, value);
        if (find_error_type_for_branch(tokens, tok.lexeme)) |type_name| {
            return .{ .error_branch = .{ .name = tok.lexeme, .type_name = type_name } };
        }
        return .unsupported;
    }
    return .unknown;
}

fn eval_call(
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
        return eval_get_call(allocator, tokens, funcs, bindings, args_start, args_end);
    }
    if (std.mem.eql(u8, name, "set")) {
        return eval_set_call(allocator, tokens, funcs, bindings, args_start, args_end);
    }
    if (std.mem.eql(u8, name, "as")) {
        return eval_as_call(allocator, tokens, funcs, bindings, args_start, args_end);
    }
    if (std.mem.eql(u8, name, "is")) {
        return eval_is_call(allocator, tokens, funcs, bindings, args_start, args_end);
    }

    var args = std.ArrayList(Value).empty;
    defer {
        free_values(allocator, args.items);
        args.deinit(allocator);
    }
    try eval_args(allocator, tokens, funcs, bindings, args_start, args_end, &args);

    if (std.mem.eql(u8, name, "eq")) {
        if (has_unsupported_value(args.items)) return .unsupported;
        if (args.items.len != 2 or args.items[0] == .unknown or args.items[1] == .unknown) return .unknown;
        return .{ .bool = value_eq(args.items[0], args.items[1]) };
    }
    if (std.mem.eql(u8, name, "ne")) {
        if (has_unsupported_value(args.items)) return .unsupported;
        if (args.items.len != 2 or args.items[0] == .unknown or args.items[1] == .unknown) return .unknown;
        return .{ .bool = !value_eq(args.items[0], args.items[1]) };
    }
    if (std.mem.eql(u8, name, "lt") or
        std.mem.eql(u8, name, "le") or
        std.mem.eql(u8, name, "gt") or
        std.mem.eql(u8, name, "ge"))
    {
        return eval_comparison_core(name, args.items);
    }
    if (std.mem.eql(u8, name, "and")) return eval_and_or_core("and", args.items);
    if (std.mem.eql(u8, name, "or")) return eval_and_or_core("or", args.items);
    if (std.mem.eql(u8, name, "not")) {
        if (has_unsupported_value(args.items)) return .unsupported;
        if (args.items.len != 1 or args.items[0] != .bool) return .unknown;
        return .{ .bool = !args.items[0].bool };
    }
    if (find_func(funcs, name, args.items.len) != null) {
        return eval_user_func(allocator, tokens, funcs, name, args.items);
    }
    if (std.mem.eql(u8, name, "abs")) return eval_abs_core(args.items);
    if (is_numeric_core_name(name)) return eval_numeric_core(name, args.items);
    if (is_bitwise_core_name(name)) return eval_bitwise_core(name, args.items);
    if (is_count_bits_core_name(name)) return eval_count_bits_core(name, args.items);
    return .unsupported;
}

fn eval_is_call(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    bindings: []const Binding,
    start_idx: usize,
    end_idx: usize,
) anyerror!Value {
    const target_end = find_arg_end(tokens, start_idx, end_idx);
    if (target_end == start_idx or target_end >= end_idx or !tok_eq_token(tokens[target_end], ",")) return .unknown;
    const value = try eval_expr(allocator, tokens, funcs, bindings, start_idx, target_end);
    defer free_value(allocator, value);
    if (value == .unsupported or value == .unknown) return value;

    const type_start = target_end + 1;
    const type_end = find_arg_end(tokens, type_start, end_idx);
    if (type_end != end_idx or type_end != type_start + 1 or tokens[type_start].kind != .ident) return .unknown;
    const type_name = tokens[type_start].lexeme;
    return .{ .bool = value_matches_type(value, type_name) };
}

fn value_matches_type(value: Value, type_name: []const u8) bool {
    return switch (value) {
        .nil => std.mem.eql(u8, type_name, "nil"),
        .bool => std.mem.eql(u8, type_name, "bool"),
        .int => is_scalar_type_name(type_name),
        .text => std.mem.eql(u8, type_name, "text"),
        .error_branch => |branch| std.mem.eql(u8, branch.type_name, type_name),
        else => false,
    };
}

fn eval_args(
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
        const arg_end = find_arg_end(tokens, i, end_idx);
        {
            const value = try eval_expr(allocator, tokens, funcs, bindings, i, arg_end);
            errdefer free_value(allocator, value);
            try out.append(allocator, value);
        }
        i = arg_end;
        if (i < end_idx and tok_eq_token(tokens[i], ",")) i += 1;
    }
}

fn eval_user_func(
    allocator: std.mem.Allocator,
    caller_tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    name: []const u8,
    args: []const Value,
) anyerror!Value {
    const func = find_func(funcs, name, args.len) orelse return .unsupported;
    const func_tokens = func.tokens;
    const imported_func = !module_tokens_equal(func_tokens, caller_tokens);
    var bindings = std.ArrayList(Binding).empty;
    defer {
        free_bindings(allocator, bindings.items);
        bindings.deinit(allocator);
    }

    var arg_idx: usize = 0;
    var i = func.params_start;
    while (i < func.params_end and arg_idx < args.len) {
        const seg_end = find_arg_end(func_tokens, i, func.params_end);
        if (func_tokens[i].kind == .ident and is_binding_name(func_tokens[i].lexeme)) {
            const value = try clone_value(allocator, args[arg_idx]);
            errdefer free_value(allocator, value);
            try set_binding(allocator, &bindings, func_tokens[i].lexeme, value);
        }
        arg_idx += 1;
        i = seg_end;
        if (i < func.params_end and tok_eq_token(func_tokens[i], ",")) i += 1;
    }

    if (func.arrow) {
        return eval_expr(allocator, func_tokens, funcs, bindings.items, func.body_start, func.body_end) catch |err| {
            if (imported_func and err == error.NoMatchingCall) return .unsupported;
            return err;
        };
    }
    return eval_returning_block(allocator, func_tokens, funcs, &bindings, func.body_start, func.body_end, imported_func);
}

fn eval_user_func_multi(
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
        free_values(allocator, args.items);
        args.deinit(allocator);
    }
    try eval_args(allocator, tokens, funcs, outer_bindings, args_start, args_end, &args);

    const func = find_func(funcs, name, args.items.len) orelse return error.NoMatchingCall;
    const func_tokens = func.tokens;
    const imported_func = !module_tokens_equal(func_tokens, tokens);
    var bindings = std.ArrayList(Binding).empty;
    defer {
        free_bindings(allocator, bindings.items);
        bindings.deinit(allocator);
    }

    var arg_idx: usize = 0;
    var i = func.params_start;
    while (i < func.params_end and arg_idx < args.items.len) {
        const seg_end = find_arg_end(func_tokens, i, func.params_end);
        if (func_tokens[i].kind == .ident and is_binding_name(func_tokens[i].lexeme)) {
            const value = try clone_value(allocator, args.items[arg_idx]);
            errdefer free_value(allocator, value);
            try set_binding(allocator, &bindings, func_tokens[i].lexeme, value);
        }
        arg_idx += 1;
        i = seg_end;
        if (i < func.params_end and tok_eq_token(func_tokens[i], ",")) i += 1;
    }

    const range = if (func.arrow) Range{ .start = func.body_start, .end = func.body_end } else blk: {
        if (has_unsupported_control_flow(func_tokens, func.body_start, func.body_end)) {
            if (imported_func) return alloc_unsupported_values(allocator, expected_count);
            return error.NoMatchingCall;
        }
        if (func.body_start >= func.body_end or !tok_eq_token(func_tokens[func.body_start], "return")) {
            if (imported_func) return alloc_unsupported_values(allocator, expected_count);
            return error.NoMatchingCall;
        }
        const line_end = find_line_end(func_tokens, func.body_start, func.body_end);
        if (line_end != func.body_end) {
            if (imported_func) return alloc_unsupported_values(allocator, expected_count);
            return error.NoMatchingCall;
        }
        break :blk Range{ .start = func.body_start + 1, .end = line_end };
    };

    if (parse_simple_call(func_tokens, range.start, range.end)) |nested| {
        if (nested.has_type_args) return alloc_unsupported_values(allocator, expected_count);
        if (find_func(funcs, nested.name, count_args(func_tokens, nested.args_start, nested.args_end)) == null) {
            return alloc_unsupported_values(allocator, expected_count);
        }
        return eval_user_func_multi(allocator, func_tokens, funcs, nested.name, nested.args_start, nested.args_end, bindings.items, expected_count) catch |err| {
            if (imported_func and err == error.NoMatchingCall) return alloc_unsupported_values(allocator, expected_count);
            return err;
        };
    }

    var out = std.ArrayList(Value).empty;
    errdefer {
        free_values(allocator, out.items);
        out.deinit(allocator);
    }
    var expr_start = range.start;
    while (expr_start < range.end) {
        const expr_end = find_arg_end(func_tokens, expr_start, range.end);
        const value = eval_expr(allocator, func_tokens, funcs, bindings.items, expr_start, expr_end) catch |err| {
            if (imported_func and err == error.NoMatchingCall) return alloc_unsupported_values(allocator, expected_count);
            return err;
        };
        errdefer free_value(allocator, value);
        try out.append(allocator, value);
        expr_start = expr_end;
        if (expr_start < range.end and tok_eq_token(func_tokens[expr_start], ",")) expr_start += 1;
    }
    if (out.items.len <= 1) {
        if (imported_func) return alloc_unsupported_values(allocator, expected_count);
        return error.NoMatchingCall;
    }
    return out.toOwnedSlice(allocator);
}

fn alloc_unsupported_values(allocator: std.mem.Allocator, count: usize) ![]Value {
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

fn eval_returning_block(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    bindings: *std.ArrayList(Binding),
    start_idx: usize,
    end_idx: usize,
    imported_func: bool,
) anyerror!Value {
    var i = start_idx;
    while (i < end_idx) {
        if (tok_eq_token(tokens[i], "defer") or tok_eq_token(tokens[i], "loop") or tok_eq_token(tokens[i], "else")) return .unsupported;
        if (tok_eq_token(tokens[i], "if")) {
            if (try eval_func_if_else_block_return(allocator, tokens, funcs, bindings, i, end_idx, imported_func)) |block| {
                if (block.returned) return block.value;
                if (block.unsupported) return .unsupported;
                if (block.unknown) return .unknown;
                i = block.next_idx;
                continue;
            }
            const parsed = eval_func_if_return(allocator, tokens, funcs, bindings, i, end_idx) catch |err| {
                if (imported_func and err == error.NoMatchingCall) return .unsupported;
                return err;
            };
            if (parsed.returned) return parsed.value;
            if (parsed.unsupported) return .unsupported;
            if (parsed.unknown) return .unknown;
            i = parsed.next_idx;
            continue;
        }
        if (tok_eq_token(tokens[i], "return")) {
            const line_end = find_line_end(tokens, i, end_idx);
            return eval_expr(allocator, tokens, funcs, bindings.items, i + 1, line_end) catch |err| {
                if (imported_func and err == error.NoMatchingCall) return .unsupported;
                return err;
            };
        }
        if (eval_binding_line(allocator, tokens, funcs, bindings, i, end_idx) catch |err| {
            if (imported_func and err == error.NoMatchingCall) return .unsupported;
            return err;
        }) |line| {
            if (line.unsupported) return .unsupported;
            i = line.next_idx;
            continue;
        }
        return .unsupported;
    }
    return .unsupported;
}

fn eval_func_if_else_block_return(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    bindings: *std.ArrayList(Binding),
    if_idx: usize,
    limit_idx: usize,
    imported_func: bool,
) !?FuncIfEval {
    const line_end = find_line_end(tokens, if_idx, limit_idx);
    const open_then = find_top_level_open_brace(tokens, if_idx + 1, line_end) orelse return null;
    const then_close = try find_matching_token(tokens, open_then, "{", "}");
    if (then_close + 2 >= limit_idx or !tok_eq_token(tokens[then_close + 1], "else") or !tok_eq_token(tokens[then_close + 2], "{")) {
        return null;
    }
    const open_else = then_close + 2;
    const else_close = try find_matching_token(tokens, open_else, "{", "}");

    const cond = try eval_expr(allocator, tokens, funcs, bindings.items, if_idx + 1, open_then);
    defer free_value(allocator, cond);
    if (cond == .unsupported) {
        if (is_single_unbound_ident(tokens, bindings.items, if_idx + 1, open_then)) return error.NoMatchingCall;
        return .{ .next_idx = else_close + 1, .returned = false, .unsupported = true, .unknown = false, .value = .unsupported };
    }
    if (cond == .unknown) {
        if (is_single_unbound_ident(tokens, bindings.items, if_idx + 1, open_then)) return error.NoMatchingCall;
        return .{ .next_idx = else_close + 1, .returned = false, .unsupported = false, .unknown = true, .value = .unknown };
    }
    if (cond != .bool) return error.NonBoolIfCondition;

    const branch_start = if (cond.bool) open_then + 1 else open_else + 1;
    const branch_end = if (cond.bool) then_close else else_close;
    const value = try eval_returning_block(allocator, tokens, funcs, bindings, branch_start, branch_end, imported_func);
    return .{ .next_idx = else_close + 1, .returned = true, .unsupported = false, .unknown = false, .value = value };
}

fn find_top_level_open_brace(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var depth_paren: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq_token(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tok_eq_token(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tok_eq_token(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tok_eq_token(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (depth_paren == 0 and depth_angle == 0 and tok_eq_token(tokens[i], "{")) return i;
    }
    return null;
}

fn find_error_type_for_branch(tokens: []const lexer.Token, branch_name: []const u8) ?[]const u8 {
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
        if (depth_brace != 0) continue;
        if (i + 3 >= tokens.len) continue;
        if (tokens[i].kind != .ident or tokens[i + 1].kind != .ident) continue;
        if (!std.mem.eql(u8, tokens[i + 1].lexeme, "error") or !tok_eq_token(tokens[i + 2], "=")) continue;

        const line_end = find_line_end(tokens, i, tokens.len);
        var branch_start = i + 3;
        while (branch_start < line_end) {
            const branch_end = find_arg_end(tokens, branch_start, line_end);
            if (branch_end == branch_start + 1 and tokens[branch_start].kind == .ident and std.mem.eql(u8, tokens[branch_start].lexeme, branch_name)) {
                return tokens[i].lexeme;
            }
            branch_start = branch_end;
            if (branch_start < line_end and tok_eq_token(tokens[branch_start], "|")) branch_start += 1;
        }
        i = line_end;
    }
    return null;
}

fn eval_func_if_return(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    bindings: *std.ArrayList(Binding),
    if_idx: usize,
    limit_idx: usize,
) !FuncIfEval {
    const line_end = find_line_end(tokens, if_idx, limit_idx);
    const return_idx = find_top_level_token(tokens, if_idx + 1, line_end, "return") orelse
        return .{ .next_idx = line_end, .returned = false, .unsupported = true, .unknown = false, .value = .unsupported };
    const cond = try eval_expr(allocator, tokens, funcs, bindings.items, if_idx + 1, return_idx);
    defer free_value(allocator, cond);
    if (cond == .unsupported) {
        if (is_single_unbound_ident(tokens, bindings.items, if_idx + 1, return_idx)) return error.NoMatchingCall;
        return .{ .next_idx = line_end, .returned = false, .unsupported = true, .unknown = false, .value = .unsupported };
    }
    if (cond == .unknown) {
        if (is_single_unbound_ident(tokens, bindings.items, if_idx + 1, return_idx)) return error.NoMatchingCall;
        return .{ .next_idx = line_end, .returned = false, .unsupported = false, .unknown = true, .value = .unknown };
    }
    if (cond != .bool) return error.NonBoolIfCondition;
    if (!cond.bool) {
        return .{ .next_idx = line_end, .returned = false, .unsupported = false, .unknown = false, .value = .unknown };
    }
    const value = if (return_idx + 1 < line_end)
        try eval_expr(allocator, tokens, funcs, bindings.items, return_idx + 1, line_end)
    else
        Value.nil;
    return .{ .next_idx = line_end, .returned = true, .unsupported = false, .unknown = false, .value = value };
}

fn eval_and(args: []const Value) Value {
    if (args.len == 0) return .{ .bool = true };
    var saw_false = false;
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
        if (!arg.bool) saw_false = true;
    }
    if (saw_unsupported) return .unsupported;
    if (saw_unknown) return .unknown;
    if (saw_false) return .{ .bool = false };
    return .{ .bool = true };
}

fn eval_and_or_core(name: []const u8, args: []const Value) Value {
    if (all_int_values(args)) return eval_bitwise_core(name, args);
    if (std.mem.eql(u8, name, "and")) return eval_and(args);
    return eval_or(args);
}

fn all_int_values(args: []const Value) bool {
    if (args.len == 0) return false;
    for (args) |arg| {
        if (arg != .int) return false;
    }
    return true;
}

fn is_single_unbound_ident(
    tokens: []const lexer.Token,
    bindings: []const Binding,
    start_idx: usize,
    end_idx: usize,
) bool {
    const trimmed = trim_parens(tokens, start_idx, end_idx);
    if (trimmed.end != trimmed.start + 1) return false;
    const tok = tokens[trimmed.start];
    if (tok.kind != .ident) return false;
    if (tok_eq_token(tok, "true") or tok_eq_token(tok, "false") or tok_eq_token(tok, "nil")) return false;
    return lookup_binding(bindings, tok.lexeme) == null;
}

fn eval_or(args: []const Value) Value {
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

fn has_unsupported_value(values: []const Value) bool {
    for (values) |value| {
        if (value == .unsupported) return true;
    }
    return false;
}

fn eval_numeric_core(name: []const u8, args: []const Value) Value {
    if (has_unsupported_value(args)) return .unsupported;
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

fn eval_comparison_core(name: []const u8, args: []const Value) Value {
    if (has_unsupported_value(args)) return .unsupported;
    if (args.len != 2 or args[0] != .int or args[1] != .int) return .unknown;
    if (std.mem.eql(u8, name, "lt")) return .{ .bool = args[0].int < args[1].int };
    if (std.mem.eql(u8, name, "le")) return .{ .bool = args[0].int <= args[1].int };
    if (std.mem.eql(u8, name, "gt")) return .{ .bool = args[0].int > args[1].int };
    if (std.mem.eql(u8, name, "ge")) return .{ .bool = args[0].int >= args[1].int };
    return .unknown;
}

fn eval_abs_core(args: []const Value) Value {
    if (has_unsupported_value(args)) return .unsupported;
    if (args.len != 1 or args[0] != .int) return .unknown;
    if (args[0].int == std.math.minInt(i128)) return .unknown;
    if (args[0].int < 0) return .{ .int = -args[0].int };
    return args[0];
}

fn eval_as_call(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    bindings: []const Binding,
    start_idx: usize,
    end_idx: usize,
) anyerror!Value {
    const target_end = find_arg_end(tokens, start_idx, end_idx);
    if (target_end == start_idx or target_end >= end_idx or !tok_eq_token(tokens[target_end], ",")) return .unknown;
    if (!is_scalar_as_target(tokens, start_idx, target_end)) return .unsupported;

    const value_start = target_end + 1;
    const value_end = find_arg_end(tokens, value_start, end_idx);
    if (value_end != end_idx) return .unknown;
    const value = try eval_expr(allocator, tokens, funcs, bindings, value_start, value_end);
    if (value == .unsupported or value == .unknown) return value;
    if (value != .int) {
        free_value(allocator, value);
        return .unknown;
    }
    return value;
}

fn is_scalar_as_target(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 1 != end_idx) return false;
    if (tokens[start_idx].kind != .ident) return false;
    return is_scalar_type_name(tokens[start_idx].lexeme);
}

fn is_scalar_type_name(name: []const u8) bool {
    const names = [_][]const u8{
        "u8",
        "u16",
        "u32",
        "u64",
        "usize",
        "isize",
        "i8",
        "i16",
        "i32",
        "i64",
        "f32",
        "f64",
    };
    for (names) |it| {
        if (std.mem.eql(u8, it, name)) return true;
    }
    return false;
}

fn eval_bitwise_core(name: []const u8, args: []const Value) Value {
    if (has_unsupported_value(args)) return .unsupported;
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

fn eval_count_bits_core(name: []const u8, args: []const Value) Value {
    if (has_unsupported_value(args)) return .unsupported;
    if (args.len != 1 or args[0] != .int or args[0].int < 0) return .unknown;
    const value = std.math.cast(u64, args[0].int) orelse return .unknown;
    if (value > std.math.maxInt(u32)) return .unknown;
    const out = eval_count_bits_u32(name, @as(u32, @intCast(value))) orelse return .unknown;
    return .{ .int = out };
}

fn eval_count_bits_u32(name: []const u8, value: u32) ?u7 {
    if (std.mem.eql(u8, name, "clz")) return @as(u7, @intCast(@clz(value)));
    if (std.mem.eql(u8, name, "ctz")) return @as(u7, @intCast(@ctz(value)));
    if (std.mem.eql(u8, name, "popcnt")) return @as(u7, @intCast(@popCount(value)));
    return null;
}

fn is_struct_literal_start(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 1 >= end_idx) return false;
    if (tokens[start_idx].kind != .ident) return false;
    if (!std.ascii.isUpper(tokens[start_idx].lexeme[0])) return false;
    return tok_eq_token(tokens[start_idx + 1], "{");
}

fn eval_struct_literal(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    bindings: []const Binding,
    start_idx: usize,
    end_idx: usize,
) anyerror!Value {
    const open_idx = start_idx + 1;
    const close_idx = find_matching_in_range(tokens, open_idx, "{", "}", end_idx) catch return .unknown;
    if (close_idx + 1 != end_idx) return .unknown;

    var fields = std.ArrayList(FieldValue).empty;
    errdefer {
        for (fields.items) |field| free_value(allocator, field.value);
        fields.deinit(allocator);
    }

    var i = open_idx + 1;
    while (i < close_idx) {
        const field_end = find_arg_end(tokens, i, close_idx);
        const eq_idx = find_top_level_token(tokens, i, field_end, "=") orelse return .unknown;
        if (tokens[i].kind != .ident) return .unknown;
        {
            const value = try eval_expr(allocator, tokens, funcs, bindings, eq_idx + 1, field_end);
            errdefer free_value(allocator, value);
            try fields.append(allocator, .{ .name = tokens[i].lexeme, .value = value });
        }
        i = field_end;
        if (i < close_idx and tok_eq_token(tokens[i], ",")) i += 1;
    }

    return .{ .object = try fields.toOwnedSlice(allocator) };
}

fn eval_get_call(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    bindings: []const Binding,
    args_start: usize,
    args_end: usize,
) anyerror!Value {
    const first_end = find_arg_end(tokens, args_start, args_end);
    const target = try eval_expr(allocator, tokens, funcs, bindings, args_start, first_end);
    defer free_value(allocator, target);
    if (target == .unsupported) return .unsupported;
    if (target != .object) return .unknown;

    var current = target;
    var i = first_end;
    if (i < args_end and tok_eq_token(tokens[i], ",")) i += 1;
    while (i < args_end) {
        const arg_end = find_arg_end(tokens, i, args_end);
        if (i + 1 != arg_end or !is_field_seg(tokens[i])) return .unknown;
        current = get_object_field(current, tokens[i].lexeme[1..]) orelse return .unknown;
        i = arg_end;
        if (i < args_end and tok_eq_token(tokens[i], ",")) i += 1;
    }
    return clone_value(allocator, current);
}

fn eval_set_call(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    bindings: []const Binding,
    args_start: usize,
    args_end: usize,
) anyerror!Value {
    const first_end = find_arg_end(tokens, args_start, args_end);
    const target = try eval_expr(allocator, tokens, funcs, bindings, args_start, first_end);
    defer free_value(allocator, target);
    if (target == .unsupported) return .unsupported;
    if (target != .object) return .unknown;

    const value_start = find_final_arg_start(tokens, first_end, args_end) orelse return .unknown;
    const path_start = next_arg_start(tokens, first_end, args_end) orelse return .unknown;
    if (path_start >= value_start) return .unknown;
    if (!single_field_path(tokens, path_start, value_start)) return .unknown;
    const field_name = tokens[path_start].lexeme[1..];
    const old_value = get_object_field(target, field_name) orelse return .unknown;
    const new_value = if (is_lambda_expr(tokens, value_start, args_end))
        try eval_set_lambda_value(allocator, tokens, funcs, old_value, value_start, args_end)
    else
        try eval_expr(allocator, tokens, funcs, bindings, value_start, args_end);
    errdefer free_value(allocator, new_value);
    if (new_value == .unsupported) return .unsupported;

    return set_object_field(allocator, target.object, field_name, new_value);
}

fn eval_set_lambda_value(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncDecl,
    old_value: Value,
    start_idx: usize,
    end_idx: usize,
) anyerror!Value {
    const close_params = find_matching_in_range(tokens, start_idx, "(", ")", end_idx) catch return .unknown;
    const body_start = lambda_body_start(tokens, close_params + 1, end_idx) orelse return .unknown;
    if (tokens[start_idx + 1].kind != .ident) return .unknown;

    var lambda_bindings = std.ArrayList(Binding).empty;
    defer {
        free_bindings(allocator, lambda_bindings.items);
        lambda_bindings.deinit(allocator);
    }
    const value = try clone_value(allocator, old_value);
    errdefer free_value(allocator, value);
    try set_binding(allocator, &lambda_bindings, tokens[start_idx + 1].lexeme, value);
    return eval_expr(allocator, tokens, funcs, lambda_bindings.items, body_start, end_idx);
}

fn is_field_seg(tok: lexer.Token) bool {
    return tok.kind == .ident and tok.lexeme.len > 1 and tok.lexeme[0] == '.' and std.ascii.isLower(tok.lexeme[1]);
}

fn single_field_path(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    const path_end = find_arg_end(tokens, start_idx, end_idx);
    return path_end == end_idx - 1 and is_field_seg(tokens[start_idx]) and tok_eq_token(tokens[path_end], ",");
}

fn find_final_arg_start(tokens: []const lexer.Token, first_end: usize, args_end: usize) ?usize {
    var current = next_arg_start(tokens, first_end, args_end) orelse return null;
    var last = current;
    while (current < args_end) {
        const arg_end = find_arg_end(tokens, current, args_end);
        last = current;
        current = next_arg_start(tokens, arg_end, args_end) orelse break;
    }
    return last;
}

fn next_arg_start(tokens: []const lexer.Token, arg_end: usize, args_end: usize) ?usize {
    if (arg_end >= args_end) return null;
    if (!tok_eq_token(tokens[arg_end], ",")) return null;
    const next = arg_end + 1;
    if (next >= args_end) return null;
    return next;
}

fn is_lambda_expr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx >= end_idx or !tok_eq_token(tokens[start_idx], "(")) return false;
    const close_params = find_matching_in_range(tokens, start_idx, "(", ")", end_idx) catch return false;
    return lambda_body_start(tokens, close_params + 1, end_idx) != null;
}

fn lambda_body_start(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (is_arrow_at(tokens, start_idx)) return start_idx + 2;
    if (!is_return_arrow_at(tokens, start_idx)) return null;
    var i = start_idx + 2;
    while (i < end_idx) : (i += 1) {
        if (is_arrow_at(tokens, i)) return i + 2;
    }
    return null;
}

fn is_arrow_at(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 1 < tokens.len and tok_eq_token(tokens[idx], "=") and tok_eq_token(tokens[idx + 1], ">");
}

fn is_return_arrow_at(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 1 < tokens.len and tok_eq_token(tokens[idx], "-") and tok_eq_token(tokens[idx + 1], ">");
}

pub fn find_func(funcs: []const FuncDecl, name: []const u8, arg_count: usize) ?FuncDecl {
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

pub fn count_fixed_params(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    var count: usize = 0;
    var i = start_idx;
    while (i < end_idx) {
        const seg_end = find_arg_end(tokens, i, end_idx);
        if (seg_end > i and is_variadic_param(tokens, i, seg_end)) return count;
        if (seg_end > i) count += 1;
        i = seg_end;
        if (i < end_idx and tok_eq_token(tokens[i], ",")) i += 1;
    }
    return count;
}

fn count_args(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    if (start_idx >= end_idx) return 0;
    var count: usize = 0;
    var i = start_idx;
    while (i < end_idx) {
        const seg_end = find_arg_end(tokens, i, end_idx);
        if (seg_end > i) count += 1;
        i = seg_end;
        if (i < end_idx and tok_eq_token(tokens[i], ",")) i += 1;
    }
    return count;
}

pub fn has_variadic_param(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i < end_idx) {
        const seg_end = find_arg_end(tokens, i, end_idx);
        if (seg_end > i and is_variadic_param(tokens, i, seg_end)) return true;
        i = seg_end;
        if (i < end_idx and tok_eq_token(tokens[i], ",")) i += 1;
    }
    return false;
}

fn is_variadic_param(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    return start_idx + 2 < end_idx and is_spread_token(tokens[start_idx + 1]);
}

fn is_spread_token(tok: lexer.Token) bool {
    return tok.kind == .symbol and tok_eq_token(tok, "...");
}

pub fn find_func_body_start(tokens: []const lexer.Token, start_idx: usize) ?usize {
    var i = start_idx;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq_token(tokens[i], "{")) return i;
        if (i + 1 < tokens.len and tok_eq_token(tokens[i], "=") and tok_eq_token(tokens[i + 1], ">")) return i + 2;
    }
    return null;
}

fn find_arg_end(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq_token(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tok_eq_token(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tok_eq_token(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq_token(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (tok_eq_token(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tok_eq_token(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tok_eq_token(tokens[i], ",")) return i;
    }
    return end_idx;
}

fn find_top_level_token(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, lexeme: []const u8) ?usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq_token(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tok_eq_token(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tok_eq_token(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq_token(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (tok_eq_token(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tok_eq_token(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tok_eq_token(tokens[i], lexeme)) return i;
    }
    return null;
}

pub fn find_line_end(tokens: []const lexer.Token, start_idx: usize, limit_idx: usize) usize {
    if (start_idx >= limit_idx) return start_idx;
    const line = tokens[start_idx].line;
    var i = start_idx;
    while (i < limit_idx and tokens[i].line == line) : (i += 1) {}
    return i;
}

fn find_stmt_end(tokens: []const lexer.Token, start_idx: usize, limit_idx: usize) usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < limit_idx) : (i += 1) {
        if (tok_eq_token(tokens[i], "(")) {
            depth_paren += 1;
        } else if (tok_eq_token(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
        } else if (tok_eq_token(tokens[i], "{")) {
            depth_brace += 1;
        } else if (tok_eq_token(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
        } else if (tok_eq_token(tokens[i], "<")) {
            depth_angle += 1;
        } else if (tok_eq_token(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
        }

        if (depth_paren != 0 or depth_brace != 0 or depth_angle != 0) continue;
        if (i + 1 >= limit_idx or tokens[i + 1].line != tokens[i].line) return i + 1;
    }
    return limit_idx;
}

pub fn find_matching_token(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8) !usize {
    return find_matching_in_range(tokens, open_idx, open, close, tokens.len);
}

pub fn find_matching_in_range(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8, limit: usize) !usize {
    if (open_idx >= limit or !tok_eq_token(tokens[open_idx], open)) return error.InvalidGroupStart;

    var depth: usize = 0;
    var i = open_idx;
    while (i < limit) : (i += 1) {
        if (tok_eq_token(tokens[i], open)) {
            depth += 1;
            continue;
        }
        if (!tok_eq_token(tokens[i], close)) continue;
        if (depth == 0) return error.InvalidGroupDepth;
        depth -= 1;
        if (depth == 0) return i;
    }
    return error.UnterminatedGroup;
}

fn module_tokens_equal(a: []const lexer.Token, b: []const lexer.Token) bool {
    return a.ptr == b.ptr and a.len == b.len;
}

fn parse_int(raw: []const u8) ?i128 {
    if (raw.len == 0) return null;
    return std.fmt.parseInt(i128, raw, 10) catch null;
}

pub fn string_token_body(s: []const u8) ?[]const u8 {
    if (s.len >= 2 and s[0] == '"' and s[s.len - 1] == '"') return s[1 .. s.len - 1];
    return null;
}

fn decode_string_literal(allocator: std.mem.Allocator, raw: []const u8) ![]const u8 {
    if (raw.len >= 2 and raw[0] == '"' and raw[raw.len - 1] == '"') {
        return decode_quoted_string(allocator, raw[1 .. raw.len - 1]);
    }
    if (raw.len >= 2 and raw[0] == '\\' and raw[1] == '\\') {
        return decode_line_string(allocator, raw);
    }
    return allocator.dupe(u8, raw);
}

fn decode_quoted_string(allocator: std.mem.Allocator, body: []const u8) ![]const u8 {
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
                const hi = hex_value(body[i + 1]) orelse return error.InvalidStringEscape;
                const lo = hex_value(body[i + 2]) orelse return error.InvalidStringEscape;
                try out.append(allocator, (hi << 4) | lo);
                i += 2;
            },
            else => return error.InvalidStringEscape,
        }
        i += 1;
    }

    return out.toOwnedSlice(allocator);
}

fn decode_line_string(allocator: std.mem.Allocator, raw: []const u8) ![]const u8 {
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

fn hex_value(ch: u8) ?u8 {
    if (ch >= '0' and ch <= '9') return ch - '0';
    if (ch >= 'a' and ch <= 'f') return ch - 'a' + 10;
    if (ch >= 'A' and ch <= 'F') return ch - 'A' + 10;
    return null;
}

fn is_numeric_core_name(name: []const u8) bool {
    return std.mem.eql(u8, name, "add") or
        std.mem.eql(u8, name, "sub") or
        std.mem.eql(u8, name, "mul") or
        std.mem.eql(u8, name, "div") or
        std.mem.eql(u8, name, "rem") or
        std.mem.eql(u8, name, "min") or
        std.mem.eql(u8, name, "max");
}

fn is_bitwise_core_name(name: []const u8) bool {
    return std.mem.eql(u8, name, "and") or
        std.mem.eql(u8, name, "or") or
        std.mem.eql(u8, name, "xor") or
        std.mem.eql(u8, name, "shl") or
        std.mem.eql(u8, name, "shr") or
        std.mem.eql(u8, name, "rotl") or
        std.mem.eql(u8, name, "rotr");
}

fn is_count_bits_core_name(name: []const u8) bool {
    return std.mem.eql(u8, name, "clz") or
        std.mem.eql(u8, name, "ctz") or
        std.mem.eql(u8, name, "popcnt");
}

pub fn is_func_decl_start(tokens: []const lexer.Token, i: usize) bool {
    if (i + 1 >= tokens.len) return false;
    if (tokens[i].kind != .ident) return false;
    if (tok_eq_token(tokens[i], "test")) return false;
    if (!is_func_decl_name(tokens[i].lexeme)) return false;
    return tok_eq_token(tokens[i + 1], "(");
}

pub fn public_func_name(name: []const u8) []const u8 {
    if (name.len != 0 and name[0] == '.') return name[1..];
    return name;
}

fn is_func_decl_name(name: []const u8) bool {
    if (name.len == 0) return false;
    if (is_lower_ident_name(name)) return true;
    if (name[0] == '.') return is_lower_ident_name(name[1..]);
    return false;
}

pub fn is_binding_name(name: []const u8) bool {
    if (name.len == 0) return false;
    return std.ascii.isLower(name[0]) or name[0] == '_';
}

fn is_lower_ident_name(name: []const u8) bool {
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

pub fn tok_eq_token(tok: lexer.Token, lexeme: []const u8) bool {
    return std.mem.eql(u8, tok.lexeme, lexeme);
}
