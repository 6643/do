//! Shared semantic token/name/scan predicates.
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema_error = @import("sema_error.zig");
const type_util = @import("type_name.zig");
const sema_shapes = @import("sema_shapes.zig");

const CallArgInfo = sema_shapes.CallArgInfo;
const FuncShape = sema_shapes.FuncShape;
const LocalImportPrefix = sema_shapes.LocalImportPrefix;
const StructInfo = sema_shapes.StructInfo;

pub fn is_top_level_decl_start(tokens: []const lexer.Token, idx: usize) bool {
    if (idx >= tokens.len or tokens[idx].kind != .ident) return false;
    if (is_modern_import_assign(tokens, idx)) return true;
    if (is_start_decl_start(tokens, idx) or is_func_decl_start(tokens, idx)) return true;
    if (is_type_decl_start(tokens, idx)) return true;
    if (top_level_line_assign_idx(tokens, idx) != null) return true;
    return tok_eq(tokens[idx], "test");
}



pub fn find_plain_eq_on_line(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (!tok_eq(tokens[i], "=")) continue;
        if (is_non_assign_equal(tokens, i)) continue;
        return i;
    }
    return null;
}



pub fn call_arg_info(tokens: []const lexer.Token, idx: usize) ?CallArgInfo {
    const open_idx = find_enclosing_call_open(tokens, idx) orelse return null;
    const name_idx = call_name_idx_before_open(tokens, open_idx) orelse return null;

    const close_idx = find_matching(tokens, open_idx, "(", ")") catch return null;
    if (idx <= open_idx or idx >= close_idx) return null;

    var current_arg: usize = 0;
    var arg_count: usize = 0;
    var saw_arg_token = false;
    var target_arg: ?usize = null;
    var target_top_level = false;
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;

    var i = open_idx + 1;
    while (i < close_idx) : (i += 1) {
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tok_eq(tokens[i], ",")) {
            if (saw_arg_token) arg_count += 1;
            saw_arg_token = false;
            current_arg += 1;
            continue;
        }

        saw_arg_token = true;
        if (i == idx) {
            target_arg = current_arg;
            target_top_level = depth_paren == 0 and depth_brace == 0 and depth_angle == 0;
        }

        if (tok_eq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tok_eq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
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
    if (saw_arg_token) arg_count += 1;

    const arg_index = target_arg orelse return null;
    if (!target_top_level) return null;
    return .{
        .name = tokens[name_idx].lexeme,
        .arg_index = arg_index,
        .arg_count = arg_count,
    };
}



pub fn call_name_idx_before_open(tokens: []const lexer.Token, open_idx: usize) ?usize {
    if (open_idx == 0) return null;
    const name_idx = open_idx - 1;
    if (tokens[name_idx].kind != .ident) return null;
    return name_idx;
}



pub fn find_enclosing_call_open(tokens: []const lexer.Token, idx: usize) ?usize {
    var depth: usize = 0;
    var i = idx;
    while (i > 0) {
        i -= 1;
        if (tok_eq(tokens[i], ")")) {
            depth += 1;
            continue;
        }
        if (!tok_eq(tokens[i], "(")) continue;
        if (depth == 0) return i;
        depth -= 1;
    }
    return null;
}



pub fn is_top_level_token(tokens: []const lexer.Token, idx: usize) bool {
    var depth: usize = 0;
    var i: usize = 0;
    while (i < idx) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            depth += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth > 0) depth -= 1;
            continue;
        }
    }
    return depth == 0;
}



pub fn validate_is_type_expr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var i = validate_is_type_atom(tokens, start_idx, end_idx) orelse return null;
    while (i < end_idx) {
        if (!tok_eq(tokens[i], "|")) return null;
        i = validate_is_type_atom(tokens, i + 1, end_idx) orelse return null;
    }
    return i;
}



pub fn validate_is_type_atom(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (start_idx >= end_idx) return null;
    if (tok_eq(tokens[start_idx], "(")) return null;
    if (tok_eq(tokens[start_idx], "[")) {
        const close_bracket = find_matching(tokens, start_idx, "[", "]") catch return null;
        if (validate_is_type_expr(tokens, start_idx + 1, close_bracket) != close_bracket) return null;
        return close_bracket + 1;
    }
    if (tokens[start_idx].kind != .ident) return null;
    if (tok_eq(tokens[start_idx], "nil")) return start_idx + 1;
    if (is_value_literal_token(tokens[start_idx])) return null;
    if (!is_base_type_name(tokens[start_idx].lexeme) and !is_valid_declared_type_name(tokens[start_idx].lexeme)) return null;

    var next_idx = start_idx + 1;
    if (next_idx < end_idx and tok_eq(tokens[next_idx], "<")) {
        const close_angle = find_matching(tokens, next_idx, "<", ">") catch return null;
        if (validate_is_type_arg_list(tokens, next_idx + 1, close_angle) == null) return null;
        next_idx = close_angle + 1;
    }
    if (next_idx < end_idx and tok_eq(tokens[next_idx], "(")) return null;
    return next_idx;
}



pub fn validate_is_type_arg_list(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (start_idx >= end_idx) return null;
    var i = start_idx;
    while (i < end_idx) {
        const next_idx = validate_is_type_expr_until_comma(tokens, i, end_idx) orelse return null;
        if (next_idx >= end_idx) return next_idx;
        if (!tok_eq(tokens[next_idx], ",")) return null;
        i = next_idx + 1;
        if (i >= end_idx) return null;
    }
    return i;
}



pub fn validate_is_type_expr_until_comma(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var i = validate_is_type_atom(tokens, start_idx, end_idx) orelse return null;
    while (i < end_idx and !tok_eq(tokens[i], ",")) {
        if (!tok_eq(tokens[i], "|")) return null;
        i = validate_is_type_atom(tokens, i + 1, end_idx) orelse return null;
    }
    return i;
}



pub fn find_return_type_end(tokens: []const lexer.Token, start_idx: usize) usize {
    var i = start_idx;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) return i;
        if (is_arrow_at(tokens, i)) return i;
        if (tokens[i].line != tokens[start_idx].line) return i;
    }
    return i;
}



pub fn has_known_func_candidate(funcs: []const FuncShape, name: []const u8) bool {
    for (funcs) |func| {
        if (std.mem.eql(u8, func.name, name)) return true;
    }
    return false;
}



pub fn func_param_type_start(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (start_idx + 1 >= end_idx) return null;
    if (is_spread_token(tokens[start_idx + 1])) {
        if (start_idx + 2 >= end_idx) return null;
        return start_idx + 2;
    }
    return start_idx + 1;
}



pub fn is_func_type_param(tokens: []const lexer.Token, func_start_idx: usize, name: []const u8) bool {
    const block_start = find_constraint_block_start_before(tokens, func_start_idx) orelse return false;

    var i = block_start;
    while (i < func_start_idx) {
        if (!tok_eq(tokens[i], "#")) {
            i += 1;
            continue;
        }
        const line_end = find_line_end_idx(tokens, i);
        const is_func_constraint = i + 2 < line_end and tok_eq(tokens[i + 2], "(");
        if (!is_func_constraint and i + 1 < line_end and std.mem.eql(u8, tokens[i + 1].lexeme, name)) {
            return true;
        }
        i = line_end;
    }
    return false;
}



pub fn type_constraint_is_function_type(
    tokens: []const lexer.Token,
    func_start_idx: usize,
    constraint_name: []const u8,
) bool {
    const block_start = find_constraint_block_start_before(tokens, func_start_idx) orelse return false;

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
        if (eq_idx + 1 >= line_end or !tok_eq(tokens[eq_idx + 1], "(")) return false;
        const close_params = find_matching(tokens, eq_idx + 1, "(", ")") catch return false;
        return is_return_arrow_at(tokens, close_params + 1);
    }
    return false;
}



pub fn find_constraint_block_start_before(tokens: []const lexer.Token, decl_start_idx: usize) ?usize {
    if (decl_start_idx == 0 or decl_start_idx >= tokens.len) return null;

    var scan_idx = decl_start_idx;
    var expected_line = tokens[decl_start_idx].line;
    var block_start: ?usize = null;

    while (scan_idx > 0) {
        const prev_idx = scan_idx - 1;
        const prev_line = tokens[prev_idx].line;
        if (prev_line + 1 != expected_line) break;

        const line_start = line_start_idx(tokens, prev_idx);
        if (!tok_eq(tokens[line_start], "#")) break;

        block_start = line_start;
        scan_idx = line_start;
        expected_line = prev_line;
    }

    return block_start;
}



pub fn line_start_idx(tokens: []const lexer.Token, idx: usize) usize {
    var out = idx;
    while (out > 0 and tokens[out - 1].line == tokens[idx].line) : (out -= 1) {}
    return out;
}



pub fn compact_type_name(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize) !?[]const u8 {
    if (start_idx + 1 == end_idx and tokens[start_idx].kind == .ident) {
        return try allocator.dupe(u8, tokens[start_idx].lexeme);
    }
    if (validate_is_type_expr(tokens, start_idx, end_idx) != end_idx) return null;

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        try out.appendSlice(allocator, tokens[i].lexeme);
    }
    const owned = try out.toOwnedSlice(allocator);
    return owned;
}



pub fn simple_type_name(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    if (start_idx + 1 != end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    return tokens[start_idx].lexeme;
}



pub fn is_top_level_comma_any(tokens: []const lexer.Token, idx: usize, start_idx: usize, end_idx: usize) bool {
    if (!tok_eq(tokens[idx], ",")) return false;

    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
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
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
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

    return depth_paren == 0 and depth_brace == 0 and depth_angle == 0;
}



pub fn is_func_decl_start(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (tokens[idx].kind != .ident) return false;
    if (!is_valid_func_decl_name(tokens[idx].lexeme)) return false;
    if (is_reserved_func_name(tokens[idx].lexeme)) return false;
    return tok_eq(tokens[idx + 1], "(");
}



pub fn is_start_decl_start(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (tokens[idx].kind != .ident) return false;
    return tok_eq(tokens[idx], "start") and tok_eq(tokens[idx + 1], "(");
}



pub fn public_func_name(name: []const u8) []const u8 {
    if (name.len != 0 and name[0] == '.') return name[1..];
    return name;
}



pub fn contains_name(names: []const []const u8, needle: []const u8) bool {
    for (names) |name| {
        if (std.mem.eql(u8, name, needle)) return true;
    }
    return false;
}



pub fn is_top_level_value_decl_start(tokens: []const lexer.Token, idx: usize) bool {
    if (!is_top_level_decl_head(tokens, idx)) return false;
    if (tokens[idx].kind != .ident) return false;
    const name = tokens[idx].lexeme;
    if (!is_lower_ident_name(name) and !is_readonly_ident_name(name) and !is_dot_lower_ident(name)) return false;
    if (idx + 1 >= tokens.len) return false;
    if (tok_eq(tokens[idx + 1], "(") or tok_eq(tokens[idx + 1], "{")) return false;
    const line_end = find_line_end_idx(tokens, idx);
    const eq_idx = find_top_level_assign_eq_on_line(tokens, idx + 1, line_end) orelse return false;
    return eq_idx > idx + 1;
}



pub fn is_arrow_at(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 1 < tokens.len and tok_eq(tokens[idx], "=") and tok_eq(tokens[idx + 1], ">");
}



pub fn is_return_arrow_at(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 1 < tokens.len and tok_eq(tokens[idx], "-") and tok_eq(tokens[idx + 1], ">");
}



pub fn find_nearest_value_type_name(tokens: []const lexer.Token, before_idx: usize, name: []const u8) ?[]const u8 {
    var skip_depth: usize = 0;
    var i = before_idx;
    while (i > 0) {
        i -= 1;

        if (tok_eq(tokens[i], "}")) {
            skip_depth += 1;
            continue;
        }
        if (tok_eq(tokens[i], "{")) {
            if (skip_depth > 0) skip_depth -= 1;
            continue;
        }
        if (skip_depth != 0) continue;
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, tokens[i].lexeme, name)) continue;

        const line_end = find_line_end_idx(tokens, i);
        const eq_idx = find_top_level_assign_eq_on_line(tokens, i + 1, line_end) orelse continue;
        if (eq_idx > i + 1 and tokens[i + 1].kind == .ident and is_value_type_name(tokens[i + 1].lexeme)) return tokens[i + 1].lexeme;
        if (eq_idx > i + 1 and tokens[i + 1].kind == .ident and is_generic_type_start(tokens, i + 1, eq_idx)) return tokens[i + 1].lexeme;
        if (tokens[eq_idx + 1].kind == .ident and eq_idx + 2 < line_end and tok_eq(tokens[eq_idx + 2], "{")) return tokens[eq_idx + 1].lexeme;
    }
    return null;
}



pub fn is_generic_type_start(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 1 >= end_idx or !tok_eq(tokens[start_idx + 1], "<")) return false;
    _ = find_matching(tokens, start_idx + 1, "<", ">") catch return false;
    return true;
}



pub fn is_declared_type_name(name: []const u8) bool {
    return name.len != 0 and std.ascii.isUpper(name[0]);
}



pub fn is_value_type_name(name: []const u8) bool {
    return is_declared_type_name(name) or is_base_type_name(name);
}



pub fn public_type_name(name: []const u8) []const u8 {
    if (name.len != 0 and name[0] == '.') return name[1..];
    return name;
}



pub fn find_line_end_idx(tokens: []const lexer.Token, start_idx: usize) usize {
    if (start_idx >= tokens.len) return start_idx;
    const line = tokens[start_idx].line;
    var i = start_idx;
    while (i < tokens.len and tokens[i].line == line) : (i += 1) {}
    return i;
}



pub fn find_top_level_assign_eq_on_line(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
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
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
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
        if (depth_paren != 0 or depth_brace != 0 or depth_angle != 0) continue;
        if (!tok_eq(tokens[i], "=")) continue;
        if (is_non_assign_equal(tokens, i)) continue;
        return i;
    }
    return null;
}



pub fn has_local_struct_decl(tokens: []const lexer.Token, name: []const u8) bool {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
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
        if (!std.mem.eql(u8, public_type_name(tokens[i].lexeme), name)) continue;
        if (i + 1 < tokens.len and tok_eq(tokens[i + 1], "{")) return true;
    }
    return false;
}



pub fn call_arity_compatible_with_func(func: FuncShape, arg_count: usize) bool {
    if (arg_count < func.param_min) return false;
    if (func.param_max) |max_count| return arg_count <= max_count;
    return true;
}



pub fn find_matching(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8) !usize {
    return find_matching_in_range(tokens, open_idx, open, close, tokens.len);
}



pub fn find_matching_in_range(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8, limit: usize) !usize {
    if (open_idx >= tokens.len or !tok_eq(tokens[open_idx], open)) return error.InvalidGroupStart;

    var depth: usize = 0;
    var i = open_idx;
    while (i < limit) : (i += 1) {
        if (tok_eq(tokens[i], open)) {
            depth += 1;
            continue;
        }
        if (!tok_eq(tokens[i], close)) continue;

        if (depth == 0) return error.InvalidGroupDepth;
        depth -= 1;
        if (depth == 0) return i;
    }
    return error.UnterminatedGroup;
}



pub fn is_struct_decl_start(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 1 < tokens.len and tok_eq(tokens[idx + 1], "{");
}



pub fn is_error_enum_decl_start(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 2 < tokens.len and
        is_error_type_name(tokens[idx].lexeme) and
        tok_eq(tokens[idx + 1], "error") and
        tok_eq(tokens[idx + 2], "=");
}



pub fn is_value_enum_decl_start(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 2 < tokens.len and
        is_valid_declared_type_name(tokens[idx].lexeme) and
        !is_error_type_name(tokens[idx].lexeme) and
        is_base_int_type_name(tokens[idx + 1].lexeme) and
        tok_eq(tokens[idx + 2], "=");
}

/// `Message = Quit | Text([u8]) | Binary([u8])` — tagged payload enum (L1).
/// Disambiguated from value/error enums and from `Name = @wasi_*` bindings.

/// `Message = Quit | Text([u8]) | Binary([u8])` — tagged payload enum (L1).
/// Disambiguated from value/error enums and from `Name = @wasi_*` bindings.

/// `Message = Quit | Text([u8]) | Binary([u8])` — tagged payload enum (L1).
/// Disambiguated from value/error enums and from `Name = @wasi_*` bindings.
pub fn is_payload_enum_decl_start(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 2 >= tokens.len) return false;
    if (tokens[idx].kind != .ident) return false;
    if (!is_valid_declared_type_name(tokens[idx].lexeme)) return false;
    if (is_error_type_name(tokens[idx].lexeme)) return false;
    if (is_error_enum_decl_start(tokens, idx) or is_value_enum_decl_start(tokens, idx)) return false;
    if (!tok_eq(tokens[idx + 1], "=")) return false;
    // WASI / lib binding: Name = @...
    if (tok_eq(tokens[idx + 2], "@")) return false;

    const line_end = find_line_end_idx(tokens, idx);
    var j = idx + 2;
    var saw_case = false;
    var expect_case = true;
    while (j < line_end) {
        if (!expect_case) {
            if (!tok_eq(tokens[j], "|")) return false;
            expect_case = true;
            j += 1;
            continue;
        }
        if (tokens[j].kind != .ident) return false;
        if (!is_valid_enum_branch_name(tokens[j])) return false;
        j += 1;
        if (j < line_end and tok_eq(tokens[j], "(")) {
            const close = find_matching(tokens, j, "(", ")") catch return false;
            if (close <= j + 1) return false;
            // Value-enum style numeric carrier: Case(0) — not payload enum.
            if (close == j + 2 and tokens[j + 1].kind == .number) return false;
            // Payload type must be a type expr, not a bare value literal.
            if (tokens[j + 1].kind == .number or tokens[j + 1].kind == .string) return false;
            if (tok_eq(tokens[j + 1], "true") or tok_eq(tokens[j + 1], "false") or tok_eq(tokens[j + 1], "nil")) return false;
            // Type atom from j+1 .. close must fully consume.
            if (validate_is_type_expr(tokens, j + 1, close) != close) return false;
            j = close + 1;
        }
        saw_case = true;
        expect_case = false;
    }
    if (!saw_case or expect_case) return false;
    return true;
}



pub fn is_valid_enum_branch_name(tok: lexer.Token) bool {
    if (tok.kind != .ident) return false;
    const name = public_type_name(tok.lexeme);
    if (!is_valid_declared_type_name(name)) return false;
    if (std.mem.eql(u8, name, "Error")) return false;
    if (is_error_type_name(name)) return false;
    return true;
}



pub fn is_error_type_name(name: []const u8) bool {
    if (name.len == 0 or name[0] == '.') return false;
    if (!is_valid_declared_type_name(name)) return false;
    if (std.mem.eql(u8, name, "Error")) return false;
    return std.mem.endsWith(u8, name, "Error");
}



pub fn enum_decl_has_branch(tokens: []const lexer.Token, decl_start_idx: usize, name: []const u8) bool {
    const eq_idx = enum_decl_assign_idx(tokens, decl_start_idx) orelse return false;
    const line_end = find_line_end_idx(tokens, decl_start_idx);

    var i = eq_idx + 1;
    while (i < line_end) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (std.mem.eql(u8, public_type_name(tokens[i].lexeme), name)) return true;
    }
    return false;
}



pub fn enum_decl_assign_idx(tokens: []const lexer.Token, decl_start_idx: usize) ?usize {
    if (is_error_enum_decl_start(tokens, decl_start_idx) or is_value_enum_decl_start(tokens, decl_start_idx)) {
        return decl_start_idx + 2;
    }
    if (is_payload_enum_decl_start(tokens, decl_start_idx)) {
        return decl_start_idx + 1; // Name = …
    }
    return null;
}



pub fn find_struct_info(structs: []const StructInfo, name: []const u8) ?StructInfo {
    for (structs) |info| {
        if (std.mem.eql(u8, info.name, name)) return info;
    }
    return null;
}



pub fn normalize_struct_field_name(name: []const u8) []const u8 {
    if (name.len > 0 and name[0] == '.') return name[1..];
    return name;
}



pub fn is_reserved_field_name_body(name: []const u8) bool {
    return is_keyword(name) or is_decl_only_name(name) or is_reserved_core_access_name(name) or is_reserved_source_name(name);
}



pub fn is_reserved_core_access_name(name: []const u8) bool {
    return std.mem.eql(u8, name, "get") or std.mem.eql(u8, name, "set");
}



pub fn is_top_level_decl_head(tokens: []const lexer.Token, idx: usize) bool {
    if (idx == 0) return true;
    if (tokens[idx - 1].line == tokens[idx].line) return false;

    const prev = tokens[idx - 1];
    if (tok_eq(prev, "=")) return false;
    if (tok_eq(prev, "|")) return false;
    if (tok_eq(prev, ",")) return false;
    if (tok_eq(prev, ":")) return false;
    return true;
}



pub fn is_host_import_decl_start(tokens: []const lexer.Token, idx: usize) bool {
    const eq_idx = top_level_line_assign_idx(tokens, idx) orelse return false;
    const at_idx = eq_idx + 1;
    if (at_idx >= tokens.len or !tok_eq(tokens[at_idx], "@")) return false;
    return is_host_import_line(tokens, at_idx);
}



pub fn is_modern_import_assign(tokens: []const lexer.Token, idx: usize) bool {
    const eq_idx = top_level_line_assign_idx(tokens, idx) orelse return false;
    const at_idx = eq_idx + 1;
    if (at_idx + 1 >= tokens.len or !tok_eq(tokens[at_idx], "@")) return false;
    if (tokens[at_idx + 1].kind != .ident) return false;
    return std.mem.eql(u8, tokens[at_idx + 1].lexeme, "lib") or
        std.mem.eql(u8, tokens[at_idx + 1].lexeme, "host");
}



pub fn top_level_line_assign_idx(tokens: []const lexer.Token, line_start: usize) ?usize {
    const line_end = find_line_end_idx(tokens, line_start);
    return find_top_level_assign_eq_on_line(tokens, line_start + 1, line_end);
}



pub fn is_host_import_line(tokens: []const lexer.Token, at_idx: usize) bool {
    if (at_idx + 2 >= tokens.len) return false;
    if (!tok_eq(tokens[at_idx], "@")) return false;
    if (tokens[at_idx + 1].kind != .ident) return false;
    if (!tok_eq(tokens[at_idx + 2], "(")) return false;
    return std.mem.eql(u8, tokens[at_idx + 1].lexeme, "host");
}



pub fn validate_import_file_name_text(tokens: []const lexer.Token, site_idx: usize, s: []const u8, prefix: LocalImportPrefix) !void {
    if (!std.mem.endsWith(u8, s, ".do")) return mark_error_at(tokens, site_idx, error.InvalidImportDecl);
    const stem = s[0 .. s.len - 3];
    const ok = switch (prefix) {
        .local, .std => is_valid_flat_file_stem(stem),
        .dep => is_valid_dep_file_stem(stem),
    };
    if (!ok) return mark_error_at(tokens, site_idx, error.InvalidImportDecl);
}



pub fn validate_import_file_name(tokens: []const lexer.Token, idx: usize, prefix: LocalImportPrefix) !void {
    try validate_import_file_name_text(tokens, idx, tokens[idx].lexeme, prefix);
}



pub fn is_valid_flat_file_stem(stem: []const u8) bool {
    var count: usize = 0;
    var start: usize = 0;
    while (start <= stem.len) {
        const dot_idx = std.mem.indexOfScalarPos(u8, stem, start, '.') orelse stem.len;
        if (!is_valid_path_seg(stem[start..dot_idx])) return false;
        count += 1;
        if (dot_idx == stem.len) break;
        start = dot_idx + 1;
    }
    return count != 0;
}



pub fn is_valid_dep_file_stem(stem: []const u8) bool {
    var count: usize = 0;
    var start: usize = 0;
    while (start <= stem.len) {
        const dot_idx = std.mem.indexOfScalarPos(u8, stem, start, '.') orelse stem.len;
        const seg = stem[start..dot_idx];
        if (!is_all_digits(seg) and !is_valid_path_seg(seg)) return false;
        count += 1;
        if (dot_idx == stem.len) break;
        start = dot_idx + 1;
    }
    return count >= 2;
}



pub fn is_all_digits(seg: []const u8) bool {
    if (seg.len == 0) return false;
    for (seg) |ch| {
        if (ch < '0' or ch > '9') return false;
    }
    return true;
}



pub fn is_valid_path_seg(seg: []const u8) bool {
    if (seg.len == 0) return false;
    if (seg[0] < 'a' or seg[0] > 'z') return false;
    if (seg[seg.len - 1] == '_') return false;

    var prev_underscore = false;
    for (seg[1..]) |ch| {
        if ((ch >= 'a' and ch <= 'z') or (ch >= '0' and ch <= '9')) {
            prev_underscore = false;
            continue;
        }
        if (ch >= '0' and ch <= '9') {
            prev_underscore = false;
            continue;
        }
        if (ch == '_') {
            if (prev_underscore) return false;
            prev_underscore = true;
            continue;
        }
        return false;
    }
    return true;
}



pub fn compact_token_range_equals(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, expected: []const u8) bool {
    var pos: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        const lexeme = tokens[i].lexeme;
        if (pos + lexeme.len > expected.len) return false;
        if (!std.mem.eql(u8, expected[pos .. pos + lexeme.len], lexeme)) return false;
        pos += lexeme.len;
    }
    return pos == expected.len;
}



pub fn string_token_body(s: []const u8) ?[]const u8 {
    if (s.len < 2) return null;
    if (s[0] != '"' or s[s.len - 1] != '"') return null;
    return s[1 .. s.len - 1];
}



pub fn has_top_level_comma(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var depth_paren: usize = 0;
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
        if (tok_eq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tok_eq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (depth_paren == 0 and depth_angle == 0 and tok_eq(tokens[i], ",")) return true;
    }
    return false;
}



pub fn find_top_level_comma(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var depth_paren: usize = 0;
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
        if (tok_eq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tok_eq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (depth_paren == 0 and depth_angle == 0 and tok_eq(tokens[i], ",")) return i;
    }
    return null;
}



pub fn first_non_gap(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        _ = tokens;
        return i;
    }
    return null;
}



pub fn is_value_literal_token(t: lexer.Token) bool {
    if (t.kind == .number or t.kind == .string) return true;
    if (tok_eq(t, "true") or tok_eq(t, "false") or tok_eq(t, "nil")) return true;
    return false;
}



pub fn is_type_decl_start(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (tok_eq(tokens[idx + 1], "(")) return false; // func decl
    if (is_error_enum_decl_start(tokens, idx) or is_value_enum_decl_start(tokens, idx) or is_payload_enum_decl_start(tokens, idx)) return true;
    // Declarative WASI type binding: Name = @wasi_resource|wasi_record("…", { … })
    if (tok_eq(tokens[idx + 1], "=") and idx + 5 < tokens.len and
        tok_eq(tokens[idx + 2], "@") and tokens[idx + 3].kind == .ident and
        (std.mem.eql(u8, tokens[idx + 3].lexeme, "wasi_resource") or
            std.mem.eql(u8, tokens[idx + 3].lexeme, "wasi_record")) and
        tok_eq(tokens[idx + 4], "("))
    {
        return is_valid_declared_type_name(tokens[idx].lexeme);
    }

    var next_idx = idx + 1;
    if (tok_eq(tokens[next_idx], "<")) {
        const close_angle = find_matching(tokens, next_idx, "<", ">") catch return false;
        next_idx = close_angle + 1;
        if (next_idx >= tokens.len) return false;
    }

    return tok_eq(tokens[next_idx], "{");
}



pub fn is_valid_declared_type_name(name: []const u8) bool {
    if (name.len == 0) return false;
    if (name[0] == '.') return is_valid_declared_type_name(name[1..]);
    if (std.mem.eql(u8, name, "Error")) return false;
    if (!std.ascii.isUpper(name[0])) return false;

    var i: usize = 1;
    while (i < name.len) : (i += 1) {
        if (std.ascii.isAlphabetic(name[i])) continue;
        if (std.ascii.isDigit(name[i])) continue;
        return false;
    }
    return true;
}



pub fn is_lower_ident_name(name: []const u8) bool {
    return is_snake_lower_name(name);
}



pub fn is_readonly_ident_name(name: []const u8) bool {
    if (name.len < 2) return false;
    if (name[0] != '_') return false;
    return is_snake_lower_name(name[1..]);
}



pub fn is_snake_lower_name(name: []const u8) bool {
    if (name.len == 0) return false;
    if (!std.ascii.isLower(name[0])) return false;

    var prev_underscore = false;
    for (name[1..]) |ch| {
        if (std.ascii.isLower(ch) or std.ascii.isDigit(ch)) {
            prev_underscore = false;
            continue;
        }
        if (ch == '_' and !prev_underscore) {
            prev_underscore = true;
            continue;
        }
        return false;
    }

    return !prev_underscore;
}



pub fn is_spread_token(tok: lexer.Token) bool {
    return tok.kind == .symbol and tok_eq(tok, "...");
}



pub fn has_return_arrow_before_on_line(tokens: []const lexer.Token, idx: usize) bool {
    var i = line_start_idx(tokens, idx);
    while (i + 1 < idx) : (i += 1) {
        if (is_return_arrow_at(tokens, i)) return true;
    }
    return false;
}



pub fn count_type_args(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    if (start_idx >= end_idx) return 0;

    var depth_paren: usize = 0;
    var depth_bracket: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var count: usize = 1;

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
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tok_eq(tokens[i], ">")) {
            if (i > start_idx and tok_eq(tokens[i - 1], "-")) continue;
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (tok_eq(tokens[i], ",") and depth_paren == 0 and depth_bracket == 0 and depth_brace == 0 and depth_angle == 0) {
            count += 1;
        }
    }
    return count;
}



pub fn is_func_type_range(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx >= end_idx or !tok_eq(tokens[start_idx], "(")) return false;
    const close_idx = find_matching(tokens, start_idx, "(", ")") catch return false;
    return close_idx + 2 < end_idx and is_return_arrow_at(tokens, close_idx + 1);
}



pub fn is_base_type_name(name: []const u8) bool {
    const base_types = [_][]const u8{
        "i8",    "i16",   "i32", "i64",
        "u8",    "u16",   "u32", "u64",
        "isize", "usize", "f32", "f64",
        "bool",  "text",
    };
    for (base_types) |it| {
        if (std.mem.eql(u8, it, name)) return true;
    }
    return false;
}



pub fn is_wit_only_source_type_name(name: []const u8) bool {
    return std.mem.eql(u8, name, "char") or std.mem.eql(u8, name, "tuple");
}



pub fn is_base_int_type_name(name: []const u8) bool {
    const base_int_types = [_][]const u8{
        "i8",    "i16",   "i32", "i64",
        "u8",    "u16",   "u32", "u64",
        "isize", "usize",
    };
    for (base_int_types) |it| {
        if (std.mem.eql(u8, it, name)) return true;
    }
    return false;
}



pub fn has_type_constraint_name(
    tokens: []const lexer.Token,
    block_start: usize,
    before_idx: usize,
    name: []const u8,
) bool {
    var i = block_start;
    while (i < before_idx) {
        if (!tok_eq(tokens[i], "#")) {
            i += 1;
            continue;
        }
        const line_end = find_line_end_idx(tokens, i);
        const is_func_constraint = (i + 2 < line_end and tok_eq(tokens[i + 2], "("));
        if (!is_func_constraint and i + 1 < line_end and std.mem.eql(u8, tokens[i + 1].lexeme, name)) {
            return true;
        }
        i = line_end;
    }
    return false;
}



pub fn find_inline_func_type_in_params(
    tokens: []const lexer.Token,
    param_start: usize,
    param_end: usize,
) ?usize {
    var seg_start = param_start;
    var i = param_start;
    while (i <= param_end) : (i += 1) {
        if (i < param_end and !is_top_level_comma_any(tokens, i, param_start, param_end)) continue;
        if (seg_start + 1 < i) {
            const type_start = seg_start + 1;
            if (is_func_type_range(tokens, type_start, i)) return type_start;
            if (type_start + 1 < i and is_spread_token(tokens[type_start]) and is_func_type_range(tokens, type_start + 1, i)) {
                return type_start + 1;
            }
        }
        seg_start = i + 1;
    }
    return null;
}



pub fn find_struct_field_type_end(tokens: []const lexer.Token, start_idx: usize, line_end: usize) usize {
    var i = start_idx;
    while (i < line_end) : (i += 1) {
        if (tok_eq(tokens[i], "=")) return i;
    }
    return line_end;
}



pub fn token_name_appears_in_range(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    name: []const u8,
) bool {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokens[i].kind == .ident and std.mem.eql(u8, tokens[i].lexeme, name)) return true;
    }
    return false;
}



pub fn is_struct_field_decl_default(tokens: []const lexer.Token, line_start: usize, eq_idx: usize) bool {
    if (line_start >= eq_idx) return false;
    if (tokens[line_start].kind != .ident) return false;
    if (tokens[line_start].lexeme.len == 0) return false;
    if (!is_struct_field_name(tokens[line_start].lexeme)) return false;
    if (line_start + 2 > eq_idx) return false;
    return is_inside_struct_decl(tokens, line_start);
}



pub fn is_struct_field_name(name: []const u8) bool {
    if (name.len == 0) return false;
    const body = if (name[0] == '.') name[1..] else name;
    return is_snake_lower_name(body) and !is_reserved_field_name_body(body);
}



pub fn is_dot_lower_ident(name: []const u8) bool {
    return name.len > 1 and name[0] == '.' and is_snake_lower_name(name[1..]);
}



pub fn is_inside_struct_decl(tokens: []const lexer.Token, idx: usize) bool {
    var depth: usize = 0;
    var i = idx;
    while (i > 0) {
        i -= 1;
        if (tok_eq(tokens[i], "}")) {
            depth += 1;
            continue;
        }
        if (!tok_eq(tokens[i], "{")) continue;
        if (depth > 0) {
            depth -= 1;
            continue;
        }
        return is_struct_decl_body_open(tokens, i);
    }
    return false;
}



pub fn is_struct_decl_body_open(tokens: []const lexer.Token, open_idx: usize) bool {
    var i = open_idx;
    while (i > 0 and tokens[i - 1].line == tokens[open_idx].line) {
        i -= 1;
    }
    if (i >= open_idx) return false;
    if (tokens[i].kind != .ident) return false;
    if (is_keyword(tokens[i].lexeme)) return false;
    if (tokens[i].lexeme.len == 0 or !std.ascii.isUpper(tokens[i].lexeme[0])) return false;
    if (i + 1 < open_idx and tokens[i + 1].kind == .string) return false;
    if (i + 1 < open_idx and tok_eq(tokens[i + 1], "(")) return false;
    return is_type_decl_start(tokens, i);
}



pub fn is_non_assign_equal(tokens: []const lexer.Token, idx: usize) bool {
    if (idx > 0 and tok_eq(tokens[idx - 1], "=")) return true; // ==
    if (idx + 1 < tokens.len and tok_eq(tokens[idx + 1], "=")) return true; // ==
    if (idx + 1 < tokens.len and tok_eq(tokens[idx + 1], ">")) return true; // =>
    return false;
}



pub fn tok_eq(t: lexer.Token, s: []const u8) bool {
    return std.mem.eql(u8, t.lexeme, s);
}



pub fn is_keyword(name: []const u8) bool {
    const keywords = [_][]const u8{
        "if",
        "else",
        "loop",
        "break",
        "continue",
        "return",
        "defer",
        "do",
        "test",
        "true",
        "false",
        "nil",
    };
    for (keywords) |kw| {
        if (std.mem.eql(u8, name, kw)) return true;
    }
    return false;
}



pub fn is_reserved_func_name(name: []const u8) bool {
    const public_name = if (name.len != 0 and name[0] == '.') name[1..] else name;
    if (std.mem.eql(u8, public_name, "start")) return true;
    if (is_keyword(public_name)) return true;
    if (is_reserved_source_name(public_name)) return true;
    return is_builtin_special_or_core_name(public_name);
}



pub fn is_reserved_source_name(name: []const u8) bool {
    return is_base_type_name(name) or is_wit_only_source_type_name(name);
}



pub fn is_decl_only_name(name: []const u8) bool {
    const public_name = if (name.len != 0 and name[0] == '.') name[1..] else name;
    return std.mem.eql(u8, public_name, "start") or std.mem.eql(u8, public_name, "test");
}



pub fn is_numeric_core_func_name(name: []const u8) bool {
    const names = [_][]const u8{ "add", "sub", "mul", "div", "rem" };
    for (names) |it| {
        if (std.mem.eql(u8, it, name)) return true;
    }
    return false;
}



pub fn is_builtin_special_or_core_name(name: []const u8) bool {
    const names = [_][]const u8{
        "is",          "as",                "and",         "or",          "not",
        "recv",        "fields",            "get",         "set",         "field_name",
        "field_index", "field_has_default", "field_get",   "field_set",   "eq",
        "ne",          "lt",                "le",          "gt",          "ge",
        "add",         "sub",               "mul",         "div",         "rem",
        "len",         "put",               "load_u8",     "load_i8",     "load_u16_le",
        "load_i16_le", "load_u32_le",       "load_i32_le", "load_u64_le", "load_i64_le",
        "xor",         "shl",               "shr",         "rotl",        "rotr",
        "clz",         "ctz",               "popcnt",      "abs",         "neg",
        "sqrt",        "ceil",              "floor",       "trunc",       "nearest",
        "min",         "max",               "copysign",
    };
    for (names) |it| {
        if (std.mem.eql(u8, it, name)) return true;
    }
    return false;
}



pub fn is_valid_func_decl_name(name: []const u8) bool {
    if (name.len == 0) return false;
    if (is_snake_lower_name(name)) return true;
    if (name[0] == '.') return is_snake_lower_name(name[1..]);
    return false;
}



pub fn is_type_name(name: []const u8) bool {
    if (name.len == 0) return false;
    return std.ascii.isUpper(name[0]);
}



pub fn mark_error_at(tokens: []const lexer.Token, idx: usize, err: anyerror) anyerror {
    return sema_error.mark_error_at(tokens, idx, err);
}

pub fn is_valid_local_binding_name(name: []const u8) bool {
    return (is_lower_ident_name(name) or is_readonly_ident_name(name)) and !is_reserved_func_name(name);
}


pub fn is_valid_loop_binding_name(name: []const u8) bool {
    return std.mem.eql(u8, name, "_") or (is_lower_ident_name(name) and !is_reserved_func_name(name));
}


pub fn is_base_float_type_name(name: []const u8) bool {
    return std.mem.eql(u8, name, "f32") or std.mem.eql(u8, name, "f64");
}


pub fn find_loop_block_open(tokens: []const lexer.Token, loop_idx: usize) ?usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = loop_idx + 1;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tok_eq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
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
        if (tok_eq(tokens[i], "{")) {
            if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0) return i;
            depth_brace += 1;
            continue;
        }
        if (!tok_eq(tokens[i], "}")) continue;
        if (depth_brace > 0) depth_brace -= 1;
    }
    return null;
}


pub fn find_loop_bind_assign(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var found: ?usize = null;
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tok_eq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
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
        if (tok_eq(tokens[i], "{")) {
            if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0) break;
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }

        if (depth_paren != 0 or depth_brace != 0 or depth_angle != 0) continue;
        if (tok_eq(tokens[i], ":") and tok_eq(tokens[i + 1], "=")) return null;
        if (!tok_eq(tokens[i], "=")) continue;
        if (found != null) return null;
        found = i;
    }
    return found;
}


pub fn validate_loop_bind_lhs(tokens: []const lexer.Token, start_idx: usize, bind_idx: usize) !void {
    if (start_idx >= bind_idx) return mark_error_at(tokens, bind_idx, error.InvalidLoopHeader);
    if (tokens[start_idx].kind != .ident) return mark_error_at(tokens, start_idx, error.InvalidLoopHeader);
    if (is_keyword(tokens[start_idx].lexeme)) return mark_error_at(tokens, start_idx, error.InvalidLoopHeader);
    if (!is_valid_loop_binding_name(tokens[start_idx].lexeme)) return mark_error_at(tokens, start_idx, error.InvalidLoopHeader);

    if (start_idx + 1 == bind_idx) return;
    if (start_idx + 3 != bind_idx) return mark_error_at(tokens, start_idx + 1, error.InvalidLoopHeader);
    if (!tok_eq(tokens[start_idx + 1], ",")) return mark_error_at(tokens, start_idx + 1, error.InvalidLoopHeader);
    if (tokens[start_idx + 2].kind != .ident) return mark_error_at(tokens, start_idx + 2, error.InvalidLoopHeader);
    if (is_keyword(tokens[start_idx + 2].lexeme)) return mark_error_at(tokens, start_idx + 2, error.InvalidLoopHeader);
    if (!is_valid_loop_binding_name(tokens[start_idx + 2].lexeme)) return mark_error_at(tokens, start_idx + 2, error.InvalidLoopHeader);
}

pub fn is_recv_loop_source(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 3 >= end_idx) return false;
    if (!tok_eq(tokens[start_idx], "recv")) return false;
    if (!tok_eq(tokens[start_idx + 1], "(")) return false;
    const close_idx = find_matching(tokens, start_idx + 1, "(", ")") catch return false;
    return close_idx + 1 == end_idx;
}

pub fn is_fields_loop_source(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 4 != end_idx) return false;
    if (tokens[start_idx].kind != .ident or !std.mem.eql(u8, tokens[start_idx].lexeme, "fields")) return false;
    if (!tok_eq(tokens[start_idx + 1], "(")) return false;
    if (tokens[start_idx + 2].kind != .ident) return false;
    if (!is_valid_declared_type_name(tokens[start_idx + 2].lexeme)) return false;
    return tok_eq(tokens[start_idx + 3], ")");
}

