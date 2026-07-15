//! Semantic function-signature checks.
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema_error = @import("sema_error.zig");
const type_util = @import("type_name.zig");
const sema_tokens = @import("sema_tokens.zig");
const sema_shapes = @import("sema_shapes.zig");
const sema_function_support = @import("sema_function_support.zig");
const SigTypeParamPair = sema_shapes.SigTypeParamPair;
const find_inline_func_type_in_is_arg = sema_function_support.find_inline_func_type_in_is_arg;
const find_top_level_nil_in_is_arg = sema_function_support.find_top_level_nil_in_is_arg;
const free_resolved_func_type_shape = sema_function_support.free_resolved_func_type_shape;
const resolve_func_param_type_shape = sema_function_support.resolve_func_param_type_shape;
const type_constraint_is_concrete_function_type = sema_function_support.type_constraint_is_concrete_function_type;

const collect_func_shapes = sema_function_support.collect_func_shapes;
const contains_name = sema_tokens.contains_name;
const find_constraint_block_start_before = sema_tokens.find_constraint_block_start_before;
const find_inline_func_type_in_params = sema_tokens.find_inline_func_type_in_params;
const find_line_end_idx = sema_tokens.find_line_end_idx;
const find_matching = sema_tokens.find_matching;
const find_top_level_assign_eq_on_line = sema_tokens.find_top_level_assign_eq_on_line;
const free_func_shapes = sema_function_support.free_func_shapes;
const is_arrow_at = sema_tokens.is_arrow_at;
const is_error_enum_decl_start = sema_tokens.is_error_enum_decl_start;
const is_func_decl_start = sema_tokens.is_func_decl_start;
const is_func_type_param = sema_tokens.is_func_type_param;
const is_func_type_range = sema_tokens.is_func_type_range;
const is_keyword = sema_tokens.is_keyword;
const is_lower_ident_name = sema_tokens.is_lower_ident_name;
const is_modern_import_assign = sema_tokens.is_modern_import_assign;
const is_payload_enum_decl_start = sema_tokens.is_payload_enum_decl_start;
const is_reserved_func_name = sema_tokens.is_reserved_func_name;
const is_return_arrow_at = sema_tokens.is_return_arrow_at;
const is_spread_token = sema_tokens.is_spread_token;
const is_start_decl_start = sema_tokens.is_start_decl_start;
const is_struct_field_decl_default = sema_tokens.is_struct_field_decl_default;
const is_top_level_comma_any = sema_tokens.is_top_level_comma_any;
const is_top_level_decl_head = sema_tokens.is_top_level_decl_head;
const is_type_decl_start = sema_tokens.is_type_decl_start;
const is_valid_declared_type_name = sema_tokens.is_valid_declared_type_name;
const is_valid_func_decl_name = sema_tokens.is_valid_func_decl_name;
const is_value_enum_decl_start = sema_tokens.is_value_enum_decl_start;
const is_visible_binding_or_callable_name = sema_function_support.is_visible_binding_or_callable_name;
const is_wit_only_source_type_name = sema_tokens.is_wit_only_source_type_name;
const mark_error_at = sema_tokens.mark_error_at;
const parse_import_decl_end = sema_function_support.parse_import_decl_end;
const skip_top_level_import_brace = sema_function_support.skip_top_level_import_brace;
const public_type_name = sema_tokens.public_type_name;
const tok_eq = sema_tokens.tok_eq;
const validate_is_type_expr = sema_tokens.validate_is_type_expr;
const FuncParamShape = sema_shapes.FuncParamShape;
const FuncShape = sema_shapes.FuncShape;
const FuncTypeShape = sema_shapes.FuncTypeShape;

pub fn check_private_l_value_assign(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) {
        const line_start = i;
        const line_end = find_line_end_idx(tokens, line_start);
        defer i = line_end;

        const t = tokens[line_start];
        if (t.kind != .ident) continue;
        if (t.lexeme.len < 2 or t.lexeme[0] != '.') continue;
        const eq_idx = find_top_level_assign_eq_on_line(tokens, line_start, line_end) orelse continue;
        if (is_modern_import_assign(tokens, line_start)) continue;
        if (is_top_level_decl_head(tokens, line_start) and is_type_decl_start(tokens, line_start)) continue;
        if (is_private_top_value_decl_start(tokens, line_start, eq_idx)) continue;
        if (is_struct_field_decl_default(tokens, line_start, eq_idx)) continue;
        return mark_error_at(tokens, line_start, error.PrivateIdentCannotBeLValue);
    }
}



pub fn is_private_top_value_decl_start(tokens: []const lexer.Token, idx: usize, eq_idx: usize) bool {
    if (!is_top_level_decl_head(tokens, idx)) return false;
    if (eq_idx <= idx + 1) return false;
    if (tokens[idx].kind != .ident) return false;
    const name = tokens[idx].lexeme;
    return name.len > 1 and name[0] == '.' and is_lower_ident_name(name[1..]) and !is_reserved_func_name(name[1..]);
}



pub fn check_func_decl_naming(tokens: []const lexer.Token) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            if (skip_top_level_import_brace(tokens, i, depth_brace)) |skip_i| {
                i = skip_i;
                continue;
            }
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;

        const t = tokens[i];
        if (t.kind != .ident) continue;
        if (!is_top_level_decl_head(tokens, i)) continue;
        if (i + 1 >= tokens.len or !tok_eq(tokens[i + 1], "(")) continue;
        if (!is_valid_func_decl_name(t.lexeme)) {
            return mark_error_at(tokens, i, error.InvalidFuncDeclName);
        }
        if (std.mem.eql(u8, t.lexeme, "start")) continue;
        if (!is_reserved_func_name(t.lexeme)) continue;
        return mark_error_at(tokens, i, error.InvalidFuncDeclName);
    }
}



pub fn check_func_param_names(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            if (skip_top_level_import_brace(tokens, i, depth_brace)) |skip_i| {
                i = skip_i;
                continue;
            }
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;

        const t = tokens[i];
        if (t.kind != .ident) continue;
        if (!is_top_level_decl_head(tokens, i)) continue;
        if (is_keyword(t.lexeme)) continue;
        if (is_modern_import_assign(tokens, i)) continue;
        if (i + 1 >= tokens.len or !tok_eq(tokens[i + 1], "(")) continue;

        const close_paren = find_matching(tokens, i + 1, "(", ")") catch return mark_error_at(tokens, i + 1, error.InvalidParamName);
        try validate_func_param_names(allocator, tokens, i + 2, close_paren);
        i = close_paren;
    }
}



pub fn validate_func_param_names(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize) !void {
    var expect_name = true;
    var saw_variadic = false;
    var expect_variadic_type = false;
    var seen = std.ArrayListUnmanaged([]const u8).empty;
    var depth_angle: usize = 0;
    var depth_paren: usize = 0;
    defer seen.deinit(allocator);

    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (!expect_name) {
            if (tok_eq(tokens[i], "<")) {
                depth_angle += 1;
                continue;
            }
            if (tok_eq(tokens[i], ">")) {
                if (depth_angle > 0) depth_angle -= 1;
                continue;
            }
            if (tok_eq(tokens[i], "(")) {
                depth_paren += 1;
                continue;
            }
            if (tok_eq(tokens[i], ")")) {
                if (depth_paren > 0) depth_paren -= 1;
                continue;
            }
            if (depth_angle == 0 and depth_paren == 0 and tok_eq(tokens[i], ",")) {
                expect_name = true;
                expect_variadic_type = false;
            }
            continue;
        }

        if (expect_variadic_type) {
            if (tokens[i].kind != .ident) return mark_error_at(tokens, i, error.InvalidParamName);
            if (!is_valid_func_param_type_name(tokens[i].lexeme)) return mark_error_at(tokens, i, error.InvalidParamName);
            expect_name = false;
            expect_variadic_type = false;
            continue;
        }

        if (tokens[i].kind != .ident) return mark_error_at(tokens, i, error.InvalidParamName);
        if (is_spread_token(tokens[i])) {
            if (saw_variadic) return mark_error_at(tokens, i, error.InvalidParamName);
            saw_variadic = true;
            expect_name = false;
            expect_variadic_type = true;
            continue;
        }
        const name = tokens[i].lexeme;
        if (!is_valid_func_param_name(name)) return mark_error_at(tokens, i, error.InvalidParamName);
        if (contains_name(seen.items, name)) return mark_error_at(tokens, i, error.InvalidParamName);
        if (is_visible_binding_or_callable_name(tokens, name, start_idx)) return mark_error_at(tokens, i, error.InvalidParamName);
        try seen.append(allocator, name);
        expect_name = false;
    }
}



pub fn check_inline_func_param_types(tokens: []const lexer.Token) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            if (skip_top_level_import_brace(tokens, i, depth_brace)) |skip_i| {
                i = skip_i;
                continue;
            }
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!is_top_level_decl_head(tokens, i)) continue;
        if (!is_func_decl_start(tokens, i)) continue;

        const close_paren = find_matching(tokens, i + 1, "(", ")") catch
            return mark_error_at(tokens, i, error.InvalidFuncDeclName);
        if (find_inline_func_type_in_params(tokens, i + 2, close_paren)) |type_start| {
            return mark_error_at(tokens, type_start, error.InvalidFuncDeclName);
        }
        i = close_paren;
    }
}



pub fn check_func_param_type_restrictions(tokens: []const lexer.Token) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            if (skip_top_level_import_brace(tokens, i, depth_brace)) |skip_i| {
                i = skip_i;
                continue;
            }
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!is_top_level_decl_head(tokens, i)) continue;
        if (!is_func_decl_start(tokens, i)) continue;

        const close_paren = find_matching(tokens, i + 1, "(", ")") catch
            return mark_error_at(tokens, i + 1, error.InvalidParamName);
        try check_param_type_range(tokens, i, i + 2, close_paren);
        i = close_paren;
    }
}



pub fn check_synth_error_func_param_types(tokens: []const lexer.Token) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            if (skip_top_level_import_brace(tokens, i, depth_brace)) |skip_i| {
                i = skip_i;
                continue;
            }
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!is_top_level_decl_head(tokens, i)) continue;
        if (!is_func_decl_start(tokens, i)) continue;

        const close_paren = find_matching(tokens, i + 1, "(", ")") catch
            return mark_error_at(tokens, i + 1, error.InvalidParamName);
        if (find_synth_error_param_type(tokens, i + 2, close_paren)) |bad_idx| {
            return mark_error_at(tokens, bad_idx, error.InvalidSynthErrorType);
        }
        i = close_paren;
    }
}



pub fn find_synth_error_param_type(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !is_top_level_comma_any(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            const type_start = if (seg_start + 1 < i and is_spread_token(tokens[seg_start + 1])) seg_start + 2 else seg_start + 1;
            if (find_top_level_type_name(tokens, type_start, i, "Error")) |bad_idx| return bad_idx;
        }
        seg_start = i + 1;
    }
    return null;
}



pub fn find_top_level_type_name(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    name: []const u8,
) ?usize {
    var depth_paren: usize = 0;
    var depth_bracket: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tok_eq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "[")) {
            depth_bracket += 1;
            continue;
        }
        if (tok_eq(tokens[i], "]")) {
            if (depth_bracket > 0) depth_bracket -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tok_eq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (depth_paren != 0 or depth_bracket != 0 or depth_angle != 0) continue;
        if (tokens[i].kind == .ident and std.mem.eql(u8, tokens[i].lexeme, name)) return i;
    }
    return null;
}



pub fn check_param_type_range(tokens: []const lexer.Token, func_start_idx: usize, start_idx: usize, end_idx: usize) !void {
    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !is_top_level_comma_any(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) try check_one_param_type(tokens, func_start_idx, seg_start, i);
        seg_start = i + 1;
    }
}



pub fn check_one_param_type(tokens: []const lexer.Token, func_start_idx: usize, start_idx: usize, end_idx: usize) !void {
    if (start_idx + 1 >= end_idx) return mark_error_at(tokens, start_idx, error.InvalidParamName);
    const type_start = if (is_spread_token(tokens[start_idx + 1])) start_idx + 2 else start_idx + 1;
    const is_variadic = type_start != start_idx + 1;
    if (type_start >= end_idx) return mark_error_at(tokens, start_idx + 1, error.InvalidParamName);
    if (find_inline_func_type_in_is_arg(tokens, type_start, end_idx)) |func_type_idx| {
        return mark_error_at(tokens, func_type_idx, error.InvalidTypeRef);
    }
    if (validate_is_type_expr(tokens, type_start, end_idx) != end_idx) {
        return mark_error_at(tokens, type_start, error.InvalidTypeRef);
    }
    if (is_variadic) {
        if (find_top_level_pipe(tokens, type_start, end_idx)) |pipe_idx| {
            return mark_error_at(tokens, pipe_idx, error.InvalidTypeRef);
        }
    }
    if (find_top_level_pipe(tokens, type_start, end_idx)) |_| {
        if (find_top_level_nil_in_is_arg(tokens, type_start, end_idx)) |nil_idx| {
            if (nil_idx + 1 != end_idx) return mark_error_at(tokens, nil_idx, error.InvalidTypeRef);
        }
        if (find_func_type_constraint_branch_in_param(tokens, func_start_idx, type_start, end_idx)) |bad_idx| {
            return mark_error_at(tokens, bad_idx, error.InvalidTypeRef);
        }
    }
    if (tok_eq(tokens[type_start], "nil")) {
        return mark_error_at(tokens, type_start, error.InvalidTypeRef);
    }
    if (tokens[type_start].kind == .ident and is_wit_only_source_type_name(tokens[type_start].lexeme)) {
        return mark_error_at(tokens, type_start, error.InvalidTypeRef);
    }
    if (direct_param_type_name(tokens, type_start, end_idx)) |name| {
        if (is_local_union_alias(tokens, name)) return mark_error_at(tokens, type_start, error.InvalidTypeRef);
    }
}



pub fn direct_param_type_name(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    if (start_idx + 1 != end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (!is_valid_declared_type_name(tokens[start_idx].lexeme)) return null;
    return public_type_name(tokens[start_idx].lexeme);
}



pub fn find_top_level_pipe(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var depth_paren: usize = 0;
    var depth_bracket: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tok_eq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "[")) {
            depth_bracket += 1;
            continue;
        }
        if (tok_eq(tokens[i], "]")) {
            if (depth_bracket > 0) depth_bracket -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tok_eq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (depth_paren == 0 and depth_bracket == 0 and depth_angle == 0 and tok_eq(tokens[i], "|")) return i;
    }
    return null;
}



pub fn find_func_type_constraint_branch_in_param(
    tokens: []const lexer.Token,
    func_start_idx: usize,
    start_idx: usize,
    end_idx: usize,
) ?usize {
    const block_start = find_constraint_block_start_before(tokens, func_start_idx) orelse return null;
    var branch_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !is_top_level_type_pipe(tokens, i, start_idx, end_idx)) continue;
        if (direct_param_type_name(tokens, branch_start, i)) |name| {
            if (type_constraint_is_function_type_in_block(tokens, block_start, func_start_idx, name)) return branch_start;
        }
        branch_start = i + 1;
    }
    return null;
}



pub fn is_top_level_type_pipe(tokens: []const lexer.Token, idx: usize, start_idx: usize, end_idx: usize) bool {
    if (!tok_eq(tokens[idx], "|")) return false;

    var depth_paren: usize = 0;
    var depth_bracket: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < idx and i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tok_eq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "[")) {
            depth_bracket += 1;
            continue;
        }
        if (tok_eq(tokens[i], "]")) {
            if (depth_bracket > 0) depth_bracket -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tok_eq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
    }
    return depth_paren == 0 and depth_bracket == 0 and depth_angle == 0;
}



pub fn type_constraint_is_function_type_in_block(
    tokens: []const lexer.Token,
    block_start: usize,
    func_start_idx: usize,
    constraint_name: []const u8,
) bool {
    var i = block_start;
    while (i < func_start_idx) {
        if (!tok_eq(tokens[i], "#")) {
            i += 1;
            continue;
        }
        const line_end = find_line_end_idx(tokens, i);
        const is_func_constraint = i + 2 < line_end and tok_eq(tokens[i + 2], "(");
        if (is_func_constraint or i + 1 >= line_end or !std.mem.eql(u8, tokens[i + 1].lexeme, constraint_name)) {
            i = line_end;
            continue;
        }

        const eq_idx = find_top_level_assign_eq_on_line(tokens, i + 2, line_end) orelse return false;
        return is_func_type_range(tokens, eq_idx + 1, line_end);
    }
    return false;
}



pub fn check_func_return_arrow_syntax(tokens: []const lexer.Token) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            if (skip_top_level_import_brace(tokens, i, depth_brace)) |skip_i| {
                i = skip_i;
                continue;
            }
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!is_top_level_decl_head(tokens, i)) continue;
        if (!is_func_decl_start(tokens, i) and !is_start_decl_start(tokens, i)) continue;

        const close_paren = find_matching(tokens, i + 1, "(", ")") catch continue;
        const next_idx = close_paren + 1;
        if (next_idx >= tokens.len) continue;
        if (tok_eq(tokens[next_idx], "{") or is_arrow_at(tokens, next_idx) or is_return_arrow_at(tokens, next_idx)) continue;
        return mark_error_at(tokens, i, error.InvalidFuncDeclName);
    }
}



pub fn check_start_decl_syntax(tokens: []const lexer.Token) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!is_top_level_decl_head(tokens, i)) continue;
        if (!is_start_decl_start(tokens, i)) continue;

        const close_paren = find_matching(tokens, i + 1, "(", ")") catch
            return mark_error_at(tokens, i, error.InvalidStartEntrySig);
        if (close_paren != i + 2) return mark_error_at(tokens, i, error.InvalidStartEntrySig);
        if (close_paren + 1 >= tokens.len or !tok_eq(tokens[close_paren + 1], "{")) {
            return mark_error_at(tokens, i, error.InvalidStartEntrySig);
        }
    }
}



pub fn check_func_signature_conflicts(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
    const funcs = try collect_func_shapes(allocator, tokens);
    defer free_func_shapes(allocator, funcs);

    for (funcs, 0..) |func, idx| {
        for (funcs[idx + 1 ..]) |next| {
            if (!std.mem.eql(u8, func.name, next.name)) continue;
            if (!(try func_param_shapes_equal(allocator, tokens, func, next))) continue;
            return mark_error_at(tokens, next.start_idx, error.DuplicateFuncSignature);
        }
    }

    for (funcs, 0..) |func, idx| {
        for (funcs[idx + 1 ..]) |next| {
            if (!std.mem.eql(u8, func.name, next.name)) continue;
            if (func.param_shapes.len != next.param_shapes.len) continue;
            const func_is_generic = func_has_generic_signature_param(tokens, func);
            const next_is_generic = func_has_generic_signature_param(tokens, next);
            if (!func_is_generic and !next_is_generic) continue;
            if (func_is_generic != next_is_generic) continue;
            return mark_error_at(tokens, next.start_idx, error.DuplicateFuncSignature);
        }
    }
}



pub fn func_param_shapes_equal(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    a: FuncShape,
    b: FuncShape,
) !bool {
    if (a.param_shapes.len != b.param_shapes.len) return false;
    var type_param_pairs = std.ArrayList(SigTypeParamPair).empty;
    defer type_param_pairs.deinit(allocator);

    for (a.param_shapes, 0..) |item, idx| {
        if (!(try func_param_shape_equal(allocator, tokens, a, item, b, b.param_shapes[idx], &type_param_pairs))) return false;
    }
    return true;
}



pub fn func_param_shape_equal(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    a_func: FuncShape,
    a: FuncParamShape,
    b_func: FuncShape,
    b: FuncParamShape,
    type_param_pairs: *std.ArrayList(SigTypeParamPair),
) !bool {
    const a_resolved = try resolve_func_param_type_shape(allocator, tokens, a_func, a);
    defer free_resolved_func_type_shape(allocator, a_resolved);
    const b_resolved = try resolve_func_param_type_shape(allocator, tokens, b_func, b);
    defer free_resolved_func_type_shape(allocator, b_resolved);

    if (a_resolved != null or b_resolved != null) {
        const a_func_type = if (a_resolved) |resolved| resolved.shape else return false;
        const b_func_type = if (b_resolved) |resolved| resolved.shape else return false;
        return func_type_shape_equal(a_func_type, b_func_type);
    }

    return try func_param_shape_equal_lexical(allocator, tokens, a_func, a, b_func, b, type_param_pairs);
}



pub fn func_param_shape_equal_lexical(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    a_func: FuncShape,
    a: FuncParamShape,
    b_func: FuncShape,
    b: FuncParamShape,
    type_param_pairs: *std.ArrayList(SigTypeParamPair),
) !bool {
    return switch (a) {
        .other => switch (b) {
            .other => true,
            else => false,
        },
        .value => |a_type| switch (b) {
            .value => |b_type| try func_param_value_types_equal(allocator, tokens, a_func, a_type, b_func, b_type, type_param_pairs),
            else => false,
        },
        .variadic => |a_type| switch (b) {
            .variadic => |b_type| try func_param_value_types_equal(allocator, tokens, a_func, a_type, b_func, b_type, type_param_pairs),
            else => false,
        },
        .func => |a_func_type| switch (b) {
            .func => |b_func_type| func_type_shape_equal(a_func_type, b_func_type),
            else => false,
        },
    };
}



pub fn func_param_value_types_equal(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    a_func: FuncShape,
    a_type: ?[]const u8,
    b_func: FuncShape,
    b_type: ?[]const u8,
    type_param_pairs: *std.ArrayList(SigTypeParamPair),
) !bool {
    const a_name = a_type orelse return b_type == null;
    const b_name = b_type orelse return false;

    const a_is_param = is_func_type_param(tokens, a_func.start_idx, a_name);
    const b_is_param = is_func_type_param(tokens, b_func.start_idx, b_name);
    if (!a_is_param and !b_is_param) return std.mem.eql(u8, a_name, b_name);
    if (a_is_param != b_is_param) return false;

    for (type_param_pairs.items) |pair| {
        if (std.mem.eql(u8, pair.a, a_name)) return std.mem.eql(u8, pair.b, b_name);
        if (std.mem.eql(u8, pair.b, b_name)) return false;
    }
    try type_param_pairs.append(allocator, .{ .a = a_name, .b = b_name });
    return true;
}



pub fn func_type_shape_equal(a: FuncTypeShape, b: FuncTypeShape) bool {
    if (a.param_count != b.param_count) return false;
    if (a.param_types.len != b.param_types.len) return false;
    for (a.param_types, 0..) |a_type, idx| {
        if (!optional_type_name_equal(a_type, b.param_types[idx])) return false;
    }
    return optional_type_name_equal(a.return_type, b.return_type);
}



pub fn optional_type_name_equal(a: ?[]const u8, b: ?[]const u8) bool {
    if (a) |a_name| {
        const b_name = b orelse return false;
        return std.mem.eql(u8, a_name, b_name);
    }
    return b == null;
}



pub fn func_has_generic_signature_param(tokens: []const lexer.Token, func: FuncShape) bool {
    for (func.param_shapes) |param| {
        const type_name = switch (param) {
            .value => |value_type| value_type orelse continue,
            .variadic => |value_type| value_type orelse continue,
            else => continue,
        };
        if (!is_func_type_param(tokens, func.start_idx, type_name)) continue;
        if (type_constraint_is_concrete_function_type(tokens, func.start_idx, type_name)) continue;
        return true;
    }
    return false;
}



pub fn is_local_union_alias(tokens: []const lexer.Token, name: []const u8) bool {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            if (skip_top_level_import_brace(tokens, i, depth_brace)) |skip_i| {
                i = skip_i;
                continue;
            }
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!is_top_level_decl_head(tokens, i)) continue;
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, public_type_name(tokens[i].lexeme), name)) continue;
        if (is_modern_import_assign(tokens, i)) return false;
        if (is_error_enum_decl_start(tokens, i) or is_value_enum_decl_start(tokens, i) or is_payload_enum_decl_start(tokens, i)) return false;
        const line_end = find_line_end_idx(tokens, i);
        const eq_idx = find_top_level_assign_eq_on_line(tokens, i + 1, line_end) orelse return false;
        return find_token_on_line(tokens, eq_idx + 1, line_end, "|") != null;
    }
    return false;
}



pub fn find_token_on_line(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, s: []const u8) ?usize {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], s)) return i;
    }
    return null;
}



pub fn is_valid_func_param_name(name: []const u8) bool {
    return is_lower_ident_name(name) and !is_reserved_func_name(name);
}



pub fn is_valid_func_param_type_name(name: []const u8) bool {
    return name.len != 0 and (std.ascii.isUpper(name[0]) or name[0] == '[' or name[0] == '(' or name[0] == '.');
}



