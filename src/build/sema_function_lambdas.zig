//! Semantic function-lambda checks.
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema_error = @import("sema_error.zig");
const type_util = @import("type_name.zig");
const sema_tokens = @import("sema_tokens.zig");
const sema_shapes = @import("sema_shapes.zig");
const sema_function_support = @import("sema_function_support.zig");
const CallShape = sema_shapes.CallShape;
const collect_call_shapes_from_program = sema_function_support.collect_call_shapes_from_program;
const find_enclosing_func_param_type_name = sema_function_support.find_enclosing_func_param_type_name;
const free_resolved_func_type_shape = sema_function_support.free_resolved_func_type_shape;
const is_scalar_as_target_type_name = sema_function_support.is_scalar_as_target_type_name;
const resolve_func_param_type_shape = sema_function_support.resolve_func_param_type_shape;
const type_constraint_is_concrete_function_type = sema_function_support.type_constraint_is_concrete_function_type;

const call_arg_info = sema_tokens.call_arg_info;
const call_arity_compatible_with_func = sema_tokens.call_arity_compatible_with_func;
const collect_func_shapes = sema_function_support.collect_func_shapes;
const contains_name = sema_tokens.contains_name;
const find_line_end_idx = sema_tokens.find_line_end_idx;
const find_matching = sema_tokens.find_matching;
const find_top_level_assign_eq_on_line = sema_tokens.find_top_level_assign_eq_on_line;
const free_call_arg_shapes = sema_function_support.free_call_arg_shapes;
const free_func_shapes = sema_function_support.free_func_shapes;
const has_known_func_candidate = sema_tokens.has_known_func_candidate;
const is_keyword = sema_tokens.is_keyword;
const is_lower_ident_name = sema_tokens.is_lower_ident_name;
const is_non_assign_equal = sema_tokens.is_non_assign_equal;
const is_reserved_func_name = sema_tokens.is_reserved_func_name;
const is_top_level_decl_head = sema_tokens.is_top_level_decl_head;
const is_top_level_token = sema_tokens.is_top_level_token;
const is_visible_binding_or_callable_name = sema_function_support.is_visible_binding_or_callable_name;
const lambda_body_start = sema_function_support.lambda_body_start;
const line_start_idx = sema_tokens.line_start_idx;
const mark_error_at = sema_tokens.mark_error_at;
const tok_eq = sema_tokens.tok_eq;
const FuncParamShape = sema_shapes.FuncParamShape;
const FuncShape = sema_shapes.FuncShape;
const FuncTypeShape = sema_shapes.FuncTypeShape;

pub fn check_lambda_usage(allocator: std.mem.Allocator, program: parser.Program, tokens: []const lexer.Token) !void {
    for (program.expr_nodes) |node| {
        if (node.kind != .lambda) continue;
        try check_one_lambda_usage(allocator, tokens, node);
    }
}
pub fn check_one_lambda_usage(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    node: parser.ExprNode,
) !void {
    if (!is_lambda_call_arg_site(tokens, node.start_tok)) {
        return mark_error_at(tokens, node.start_tok, error.InvalidLambdaExpr);
    }

    const open_paren = lambda_param_open(tokens, node.start_tok) orelse
        return mark_error_at(tokens, node.start_tok, error.InvalidLambdaExpr);
    const close_paren = find_matching(tokens, open_paren, "(", ")") catch
        return mark_error_at(tokens, node.start_tok, error.InvalidLambdaExpr);
    const body_start = lambda_body_start(tokens, close_paren + 1, node.end_tok) orelse {
        return mark_error_at(tokens, close_paren, error.InvalidLambdaExpr);
    };

    const params = try collect_lambda_param_names(allocator, tokens, open_paren + 1, close_paren);
    defer allocator.free(params);

    if (body_start > node.end_tok) return mark_error_at(tokens, close_paren, error.InvalidLambdaExpr);

    if (try find_lambda_capture(allocator, tokens, body_start, node.end_tok, params)) |bad_idx| {
        return mark_error_at(tokens, bad_idx, error.InvalidLambdaExpr);
    }
}
pub fn check_lambda_overload_calls(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
) !void {
    const funcs = try collect_func_shapes(allocator, tokens);
    defer free_func_shapes(allocator, funcs);

    if (funcs.len == 0) return;

    var calls = std.ArrayList(CallShape).empty;
    defer {
        for (calls.items) |call| free_call_arg_shapes(allocator, call.arg_shapes);
        calls.deinit(allocator);
    }

    try collect_call_shapes_from_program(allocator, program, tokens, &calls);
    for (calls.items) |call| {
        if (is_set_update_lambda_call(call)) continue;
        if (!call_has_target_function_value(tokens, funcs, call)) continue;
        if (!has_known_func_candidate(funcs, call.name)) continue;
        if (try count_compatible_function_value_candidates(allocator, tokens, funcs, call) != 1) {
            return mark_error_at(tokens, call.start_idx, error.NoMatchingCall);
        }
    }

    try check_bare_overloaded_func_assign(tokens, funcs);
}



pub fn is_set_update_lambda_call(call: CallShape) bool {
    if (!std.mem.eql(u8, call.name, "set")) return false;
    if (call.arg_shapes.len < 3) return false;
    return call.arg_shapes[call.arg_shapes.len - 1] == .lambda;
}



pub fn count_compatible_function_value_candidates(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncShape,
    call: CallShape,
) !usize {
    var count: usize = 0;
    for (funcs) |func| {
        if (!std.mem.eql(u8, func.name, call.name)) continue;
        if (!call_arity_compatible_with_func(func, call.arg_shapes.len)) continue;
        if (!(try function_value_args_match_func(allocator, tokens, funcs, func, call))) continue;
        count += 1;
    }
    return count;
}



pub fn function_value_args_match_func(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncShape,
    func: FuncShape,
    call: CallShape,
) !bool {
    for (call.arg_shapes, 0..) |arg, arg_index| {
        switch (arg) {
            .other => continue,
            .spread => continue,
            .lambda => |lambda| {
                if (lambda.arg_index >= func.param_shapes.len) return false;
                const target = try resolve_func_param_type_shape(allocator, tokens, func, func.param_shapes[lambda.arg_index]);
                defer free_resolved_func_type_shape(allocator, target);
                const func_type = if (target) |resolved| resolved.shape else return false;
                if (func_type.param_count != lambda.param_count) return false;
                if (!explicit_lambda_types_match(func_type.param_types, lambda.param_types)) return false;
            },
            .ident => |name| {
                if (arg_index >= func.param_shapes.len) return false;
                const target = try resolve_func_param_type_shape(allocator, tokens, func, func.param_shapes[arg_index]);
                defer free_resolved_func_type_shape(allocator, target);
                const target_func = if (target) |resolved| resolved.shape else continue;
                if (count_funcs_matching_target(funcs, name, target_func) != 1) return false;
            },
        }
    }
    return true;
}



pub fn count_funcs_matching_target(
    funcs: []const FuncShape,
    name: []const u8,
    target_func: FuncTypeShape,
) usize {
    var count: usize = 0;
    for (funcs) |func| {
        if (!std.mem.eql(u8, func.name, name)) continue;
        if (!function_matches_target(func, target_func)) continue;
        count += 1;
    }
    return count;
}



pub fn function_matches_target(func: FuncShape, target: FuncTypeShape) bool {
    if (func.param_shapes.len != target.param_count) return false;
    for (target.param_types, 0..) |target_type, idx| {
        const expected = target_type orelse continue;
        const actual = switch (func.param_shapes[idx]) {
            .value => |value_type| value_type orelse return false,
            .variadic => |value_type| value_type orelse return false,
            else => return false,
        };
        if (!std.mem.eql(u8, actual, expected)) return false;
    }
    if (target.return_type) |expected_ret| {
        const actual_ret = func.return_type orelse return false;
        if (!std.mem.eql(u8, actual_ret, expected_ret)) return false;
    }
    return true;
}



pub fn call_has_target_function_value(tokens: []const lexer.Token, funcs: []const FuncShape, call: CallShape) bool {
    for (call.arg_shapes, 0..) |arg, arg_index| {
        if (arg == .lambda and call_has_func_param_candidate_at_index(tokens, funcs, call, arg_index)) return true;
        if (arg != .ident) continue;
        const ident = arg.ident;
        if (!has_known_func_candidate(funcs, ident)) continue;
        if (call_has_func_param_candidate_at_index(tokens, funcs, call, arg_index)) return true;
    }
    return false;
}



pub fn call_has_func_param_candidate_at_index(tokens: []const lexer.Token, funcs: []const FuncShape, call: CallShape, arg_index: usize) bool {
    for (funcs) |func| {
        if (!std.mem.eql(u8, func.name, call.name)) continue;
        if (!call_arity_compatible_with_func(func, call.arg_shapes.len)) continue;
        if (arg_index >= func.param_shapes.len) continue;
        if (func_param_shape_is_function_like(tokens, func, func.param_shapes[arg_index])) return true;
    }
    return false;
}



pub fn func_param_shape_is_function_like(tokens: []const lexer.Token, func: FuncShape, param: FuncParamShape) bool {
    return switch (param) {
        .func => true,
        .value => |type_name| if (type_name) |name|
            type_constraint_is_concrete_function_type(tokens, func.start_idx, name)
        else
            false,
        .variadic => |type_name| if (type_name) |name|
            type_constraint_is_concrete_function_type(tokens, func.start_idx, name)
        else
            false,
        else => false,
    };
}



pub fn check_bare_overloaded_func_assign(tokens: []const lexer.Token, funcs: []const FuncShape) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tok_eq(tokens[i], "=") or is_non_assign_equal(tokens, i)) continue;

        const line_start = line_start_idx(tokens, i);
        const line_end = find_line_end_idx(tokens, i);
        const rhs_start = i + 1;
        if (rhs_start + 1 != line_end) continue;
        if (tokens[rhs_start].kind != .ident) continue;
        if (count_funcs_by_name(funcs, tokens[rhs_start].lexeme) < 2) continue;

        if (line_start + 1 != i) continue;
        if (tokens[line_start].kind != .ident) continue;
        return mark_error_at(tokens, rhs_start, error.NoMatchingCall);
    }
}



pub fn count_funcs_by_name(funcs: []const FuncShape, name: []const u8) usize {
    var count: usize = 0;
    for (funcs) |func| {
        if (std.mem.eql(u8, func.name, name)) count += 1;
    }
    return count;
}



pub fn explicit_lambda_types_match(target_types: []const ?[]const u8, lambda_types: []const ?[]const u8) bool {
    if (target_types.len != lambda_types.len) return false;
    for (lambda_types, 0..) |lambda_type, idx| {
        const expected = lambda_type orelse continue;
        const actual = target_types[idx] orelse return false;
        if (!std.mem.eql(u8, actual, expected)) return false;
    }
    return true;
}



pub fn lambda_param_open(tokens: []const lexer.Token, start_idx: usize) ?usize {
    if (start_idx >= tokens.len) return null;
    if (tok_eq(tokens[start_idx], "(")) return start_idx;
    return null;
}



pub fn is_lambda_call_arg_site(tokens: []const lexer.Token, start_idx: usize) bool {
    if (is_disallowed_set_path_lambda(tokens, start_idx)) return false;
    if (start_idx == 0) return false;
    const prev = tokens[start_idx - 1];
    if (tok_eq(prev, ",")) return true;
    if (!tok_eq(prev, "(")) return false;
    if (start_idx < 2) return false;
    const before_prev = tokens[start_idx - 2];
    return before_prev.kind == .ident or tok_eq(before_prev, ")") or tok_eq(before_prev, "]");
}



pub fn is_disallowed_set_path_lambda(tokens: []const lexer.Token, start_idx: usize) bool {
    const info = call_arg_info(tokens, start_idx) orelse return false;
    if (!std.mem.eql(u8, info.name, "set")) return false;
    return info.arg_index + 1 < info.arg_count;
}



fn skip_lambda_param_type_tail(tokens: []const lexer.Token, start_i: usize, end_idx: usize) !usize {
    var i = start_i;
    var depth_paren: usize = 0;
    var depth_angle: usize = 0;
    var depth_brace: usize = 0;
    while (i < end_idx) {
        if (depth_paren == 0 and depth_angle == 0 and depth_brace == 0 and tok_eq(tokens[i], ",")) break;
        if (tok_eq(tokens[i], "(")) {
            depth_paren += 1;
        } else if (tok_eq(tokens[i], ")")) {
            if (depth_paren == 0) return mark_error_at(tokens, i, error.InvalidLambdaExpr);
            depth_paren -= 1;
        } else if (tok_eq(tokens[i], "<")) {
            depth_angle += 1;
        } else if (tok_eq(tokens[i], ">")) {
            if (depth_angle == 0) return mark_error_at(tokens, i, error.InvalidLambdaExpr);
            depth_angle -= 1;
        } else if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
        } else if (tok_eq(tokens[i], "}")) {
            if (depth_brace == 0) return mark_error_at(tokens, i, error.InvalidLambdaExpr);
            depth_brace -= 1;
        }
        i += 1;
    }
    if (depth_paren != 0 or depth_angle != 0 or depth_brace != 0) {
        return mark_error_at(tokens, end_idx - 1, error.InvalidLambdaExpr);
    }
    return i;
}

pub fn collect_lambda_param_names(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ![]const []const u8 {
    var out = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    errdefer out.deinit(allocator);

    var i = start_idx;
    while (i < end_idx) {
        if (!is_lambda_param_name_token(tokens[i])) return mark_error_at(tokens, i, error.InvalidLambdaExpr);
        const name = tokens[i].lexeme;
        if (contains_name(out.items, name)) return mark_error_at(tokens, i, error.InvalidLambdaExpr);
        if (is_visible_binding_or_callable_name(tokens, name, start_idx)) return mark_error_at(tokens, i, error.InvalidLambdaExpr);
        if (is_visible_local_binding_before(tokens, name, start_idx)) return mark_error_at(tokens, i, error.InvalidLambdaExpr);
        try out.append(allocator, name);
        i += 1;
        if (i >= end_idx) break;

        if (tok_eq(tokens[i], ",")) {
            i += 1;
            if (i >= end_idx) return mark_error_at(tokens, end_idx - 1, error.InvalidLambdaExpr);
            continue;
        }

        i = try skip_lambda_param_type_tail(tokens, i, end_idx);
        if (i < end_idx and tok_eq(tokens[i], ",")) {
            i += 1;
            if (i >= end_idx) return mark_error_at(tokens, end_idx - 1, error.InvalidLambdaExpr);
        }
    }

    return out.toOwnedSlice(allocator);
}



pub fn is_lambda_param_name_token(tok: lexer.Token) bool {
    if (tok.kind != .ident) return false;
    if (tok.lexeme.len == 0) return false;
    if (tok.lexeme[0] == '_') return false;
    return std.ascii.isLower(tok.lexeme[0]) and !is_reserved_func_name(tok.lexeme);
}



pub fn find_lambda_capture(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    params: []const []const u8,
) !?usize {
    var locals = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer locals.deinit(allocator);

    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        const tok = tokens[i];
        if (tok.kind != .ident) continue;
        if (tok.lexeme.len == 0) continue;
        if (tok.lexeme[0] == '.') continue;
        if (tok.lexeme[0] == '_') continue;
        if (std.ascii.isUpper(tok.lexeme[0])) continue;
        if (is_keyword(tok.lexeme)) continue;
        if (is_as_scalar_type_token(tokens, i)) continue;
        if (contains_name(params, tok.lexeme)) continue;
        if (contains_name(locals.items, tok.lexeme)) continue;
        if (is_lambda_local_bind_name(tokens, i, start_idx)) {
            try locals.append(allocator, tok.lexeme);
            continue;
        }
        if (i + 1 < end_idx and (tok_eq(tokens[i + 1], "(") or tok_eq(tokens[i + 1], "{") or tok_eq(tokens[i + 1], "<"))) continue;
        return i;
    }
    return null;
}



pub fn is_lambda_local_bind_name(tokens: []const lexer.Token, idx: usize, body_start: usize) bool {
    if (!is_lower_ident_name(tokens[idx].lexeme)) return false;
    if (is_reserved_func_name(tokens[idx].lexeme)) return false;

    const line_start = lambda_line_start(tokens, idx, body_start);
    const line_end = find_line_end_idx(tokens, idx);
    const eq_idx = find_top_level_assign_eq_on_line(tokens, line_start, line_end) orelse return false;
    return idx < eq_idx;
}



pub fn is_as_scalar_type_token(tokens: []const lexer.Token, idx: usize) bool {
    if (!is_scalar_as_target_type_name(tokens[idx].lexeme)) return false;
    const info = call_arg_info(tokens, idx) orelse return false;
    return std.mem.eql(u8, info.name, "as") and (info.arg_index == 0 or info.arg_index == 1);
}



pub fn lambda_line_start(tokens: []const lexer.Token, idx: usize, body_start: usize) usize {
    var line_start = idx;
    while (line_start > body_start and tokens[line_start - 1].line == tokens[idx].line) {
        line_start -= 1;
    }
    if (line_start < idx and tok_eq(tokens[line_start], "{")) return line_start + 1;
    return line_start;
}



pub fn is_visible_local_binding_before(tokens: []const lexer.Token, name: []const u8, before_idx: usize) bool {
    if (find_enclosing_func_param_type_name(tokens, before_idx, name) != null) return true;

    var scopes = [_]bool{false} ** 128;
    var depth: usize = 0;
    var i: usize = 0;
    while (i < before_idx and i < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            if (depth + 1 < scopes.len) depth += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth > 0) {
                scopes[depth] = false;
                depth -= 1;
            }
            continue;
        }
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, tokens[i].lexeme, name)) continue;
        if (!is_local_binding_introducer(tokens, i)) continue;
        scopes[depth] = true;
    }
    var d = depth + 1;
    while (d > 0) {
        d -= 1;
        if (scopes[d]) return true;
    }
    return false;
}



pub fn is_local_binding_introducer(tokens: []const lexer.Token, idx: usize) bool {
    if (idx >= tokens.len) return false;
    if (!is_lower_ident_name(tokens[idx].lexeme)) return false;
    if (is_reserved_func_name(tokens[idx].lexeme)) return false;
    const line_start = line_start_idx(tokens, idx);
    if (line_start >= tokens.len) return false;
    if (is_top_level_token(tokens, line_start) and is_top_level_decl_head(tokens, line_start)) return false;
    if (tok_eq(tokens[line_start], "loop")) return false;
    const line_end = find_line_end_idx(tokens, idx);
    const eq_idx = find_top_level_assign_eq_on_line(tokens, line_start, line_end) orelse return false;
    if (idx >= eq_idx) return false;
    if (idx == line_start and eq_idx > idx + 1) return true;
    return false;
}
