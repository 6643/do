//! Semantic analysis — struct checks.
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema_error = @import("sema_error.zig");
const type_util = @import("type_name.zig");
const sema_tokens = @import("sema_tokens.zig");
const sema_shapes = @import("sema_shapes.zig");
const sema_function_support = @import("sema_function_support.zig");

const call_arg_info = sema_tokens.call_arg_info;
const collect_struct_infos = sema_function_support.collect_struct_infos;
const count_type_args = sema_tokens.count_type_args;
const find_line_end_idx = sema_tokens.find_line_end_idx;
const find_matching = sema_tokens.find_matching;
const find_nearest_value_type_name = sema_tokens.find_nearest_value_type_name;
const find_struct_info = sema_tokens.find_struct_info;
const find_top_level_assign_eq_on_line = sema_tokens.find_top_level_assign_eq_on_line;
const find_top_level_comma = sema_tokens.find_top_level_comma;
const first_non_gap = sema_tokens.first_non_gap;
const free_struct_infos = sema_function_support.free_struct_infos;
const has_local_struct_decl = sema_tokens.has_local_struct_decl;
const has_return_arrow_before_on_line = sema_tokens.has_return_arrow_before_on_line;
const is_dot_lower_ident = sema_tokens.is_dot_lower_ident;
const is_func_decl_start = sema_tokens.is_func_decl_start;
const is_inside_struct_decl = sema_tokens.is_inside_struct_decl;
const is_modern_import_assign = sema_tokens.is_modern_import_assign;
const is_non_assign_equal = sema_tokens.is_non_assign_equal;
const is_reserved_field_name_body = sema_tokens.is_reserved_field_name_body;
const is_return_arrow_at = sema_tokens.is_return_arrow_at;
const is_snake_lower_name = sema_tokens.is_snake_lower_name;
const is_spread_token = sema_tokens.is_spread_token;
const is_start_decl_start = sema_tokens.is_start_decl_start;
const is_struct_decl_body_open = sema_tokens.is_struct_decl_body_open;
const is_struct_decl_start = sema_tokens.is_struct_decl_start;
const is_struct_field_name = sema_tokens.is_struct_field_name;
const is_top_level_comma_any = sema_tokens.is_top_level_comma_any;
const is_top_level_decl_head = sema_tokens.is_top_level_decl_head;
const is_top_level_token = sema_tokens.is_top_level_token;
const is_type_decl_start = sema_tokens.is_type_decl_start;
const is_valid_declared_type_name = sema_tokens.is_valid_declared_type_name;
const line_start_idx = sema_tokens.line_start_idx;
const local_struct_type_param_count = sema_function_support.local_struct_type_param_count;
const mark_error_at = sema_tokens.mark_error_at;
const normalize_struct_field_name = sema_tokens.normalize_struct_field_name;
const parse_import_decl_end = sema_function_support.parse_import_decl_end;
const skip_top_level_import_brace = sema_function_support.skip_top_level_import_brace;
const public_type_name = sema_tokens.public_type_name;
const tok_eq = sema_tokens.tok_eq;
const StructFieldInfo = sema_shapes.StructFieldInfo;
const StructInfo = sema_shapes.StructInfo;

pub fn check_path_access(tokens: []const lexer.Token) !void {
    for (tokens, 0..) |t, i| {
        if (t.kind != .ident) continue;
        if (t.lexeme.len == 0) continue;
        if (t.lexeme[0] == '.') continue;
        if (is_import_path_token(tokens, i)) continue;
        if (std.mem.indexOfScalar(u8, t.lexeme, '.') == null) continue;
        return mark_error_at(tokens, i, error.InvalidPathAccess);
    }
}


pub fn check_field_segment_positions(tokens: []const lexer.Token) !void {
    for (tokens, 0..) |t, i| {
        if (t.kind != .ident) continue;
        if (t.lexeme.len == 0 or t.lexeme[0] != '.') continue;
        if (t.lexeme.len == 1) continue; // `.{...}` inferred aggregate prefix.
        if (is_import_path_token(tokens, i)) continue;
        if (is_top_level_decl_head(tokens, i) and is_modern_import_assign(tokens, i)) continue;
        if (is_top_level_decl_head(tokens, i) and is_type_decl_start(tokens, i)) continue;
        if (!std.ascii.isLower(t.lexeme[1])) continue;
        if (!is_dot_lower_ident(t.lexeme)) return mark_error_at(tokens, i, error.InvalidPathAccess);
        if (is_allowed_field_segment_position(tokens, i)) continue;
        return mark_error_at(tokens, i, error.InvalidPathAccess);
    }
}


fn is_allowed_field_segment_position(tokens: []const lexer.Token, idx: usize) bool {
    if (is_private_func_decl_name(tokens, idx)) return true;
    if (is_struct_field_decl_name(tokens, idx)) return true;
    return is_get_set_path_field_segment(tokens, idx);
}


fn is_private_func_decl_name(tokens: []const lexer.Token, idx: usize) bool {
    if (!is_top_level_token(tokens, idx)) return false;
    if (!is_top_level_decl_head(tokens, idx)) return false;
    return is_func_decl_start(tokens, idx);
}


fn is_struct_field_decl_name(tokens: []const lexer.Token, idx: usize) bool {
    if (line_start_idx(tokens, idx) != idx) return false;
    if (!is_struct_field_decl_syntax_name(tokens[idx].lexeme)) return false;
    return is_inside_struct_decl(tokens, idx);
}


fn is_struct_field_decl_syntax_name(name: []const u8) bool {
    if (name.len == 0) return false;
    const body = if (name[0] == '.') name[1..] else name;
    return is_snake_lower_name(body);
}


fn is_get_set_path_field_segment(tokens: []const lexer.Token, idx: usize) bool {
    const info = call_arg_info(tokens, idx) orelse return false;
    if (std.mem.eql(u8, info.name, "get")) return info.arg_index >= 1;
    if (std.mem.eql(u8, info.name, "set")) return info.arg_index >= 1 and info.arg_index + 1 < info.arg_count;
    return false;
}


fn is_import_path_token(tokens: []const lexer.Token, idx: usize) bool {
    var i = idx;
    while (i > 0 and tokens[i - 1].line == tokens[idx].line) : (i -= 1) {}
    while (i < idx) : (i += 1) {
        if (tok_eq(tokens[i], "@")) return true;
    }
    return false;
}


fn find_top_level_assign_eq(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    return find_top_level_assign_eq_on_line(tokens, start_idx, end_idx);
}


pub fn check_path_index_segments(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tok_eq(tokens[i], "get") and !tok_eq(tokens[i], "set")) continue;
        if (i + 1 >= tokens.len or !tok_eq(tokens[i + 1], "(")) continue;
        const close_paren = find_matching(tokens, i + 1, "(", ")") catch continue;
        try check_path_arg_index_segments(tokens, i + 2, close_paren);
        i = close_paren;
    }
}


pub fn check_direct_path_source(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tok_eq(tokens[i], "get") and !tok_eq(tokens[i], "set")) continue;
        if (i + 1 >= tokens.len or !tok_eq(tokens[i + 1], "(")) continue;
        const close_paren = find_matching(tokens, i + 1, "(", ")") catch continue;
        const first_arg = first_non_gap(tokens, i + 2, close_paren) orelse continue;
        if (first_arg >= close_paren or tokens[first_arg].kind != .ident) continue;
        const source_type = find_nearest_value_type_name(tokens, i, tokens[first_arg].lexeme) orelse continue;
        if ((std.mem.eql(u8, source_type, "List") or std.mem.eql(u8, source_type, "HashMap")) and
            !has_local_struct_decl(tokens, source_type))
        {
            return mark_error_at(tokens, first_arg, error.InvalidPathAccess);
        }
        i = close_paren;
    }
}


fn check_path_arg_index_segments(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) !void {
    const path_start = find_path_arg_start(tokens, start_idx, end_idx) orelse return;
    if (path_start + 1 >= end_idx or !tok_eq(tokens[path_start], ".") or !tok_eq(tokens[path_start + 1], "{")) return;
    const path_close = find_matching(tokens, path_start + 1, "{", "}") catch return mark_error_at(tokens, path_start, error.InvalidPathIndex);
    if (is_legacy_path_list(tokens, path_start + 2, path_close)) {
        return mark_error_at(tokens, path_start, error.InvalidPathIndex);
    }
}


fn find_path_arg_start(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var comma_count: usize = 0;
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
        if (!tok_eq(tokens[i], ",")) continue;

        comma_count += 1;
        if (comma_count == 1) return i + 1;
    }
    return null;
}


fn is_legacy_path_list(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (is_top_level_path_field_init(tokens, i, start_idx, end_idx)) return false;
    }
    return true;
}


fn is_top_level_path_field_init(tokens: []const lexer.Token, eq_idx: usize, start_idx: usize, end_idx: usize) bool {
    if (!tok_eq(tokens[eq_idx], "=")) return false;

    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < eq_idx and i < end_idx) : (i += 1) {
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


pub fn check_struct_field_names(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
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
        if (!is_type_decl_start(tokens, i)) continue;
        if (i + 1 >= tokens.len or !tok_eq(tokens[i + 1], "{")) continue;

        const open_idx = i + 1;
        const close_idx = find_matching(tokens, open_idx, "{", "}") catch continue;
        try check_one_struct_field_names(allocator, tokens, open_idx + 1, close_idx);
        i = close_idx;
    }
}


pub fn check_struct_ctor_fields(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
    const structs = try collect_struct_infos(allocator, tokens);
    defer free_struct_infos(allocator, structs);
    if (structs.len == 0) return;

    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], ".")) {
            if (i + 1 >= tokens.len or !tok_eq(tokens[i + 1], "{")) continue;
            const struct_info = inferred_struct_ctor_info(structs, tokens, i) orelse continue;
            const close_idx = find_matching(tokens, i + 1, "{", "}") catch
                return mark_error_at(tokens, i + 1, error.InvalidStructLiteral);
            try check_one_struct_ctor_fields(allocator, tokens, i, i + 2, close_idx, struct_info);
            i = close_idx;
            continue;
        }

        if (tokens[i].kind == .ident) {
            if (i + 1 >= tokens.len or !tok_eq(tokens[i + 1], "{")) continue;
            if (is_top_level_decl_head(tokens, i) and is_type_decl_start(tokens, i)) continue;
            if (is_function_return_type_before_body(tokens, i)) continue;
            if (!is_struct_ctor_expr_context(tokens, i)) continue;
            const struct_info = find_struct_info(structs, public_type_name(tokens[i].lexeme)) orelse continue;
            const close_idx = find_matching(tokens, i + 1, "{", "}") catch
                return mark_error_at(tokens, i + 1, error.InvalidStructLiteral);
            try check_one_struct_ctor_fields(allocator, tokens, i, i + 2, close_idx, struct_info);
            i = close_idx;
            continue;
        }
    }
}


fn is_function_return_type_before_body(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (!tok_eq(tokens[idx + 1], "{")) return false;
    return has_return_arrow_before_on_line(tokens, idx);
}


fn is_struct_ctor_expr_context(tokens: []const lexer.Token, idx: usize) bool {
    if (idx == 0) return true;
    if (tokens[idx - 1].line != tokens[idx].line) return true;

    const prev = tokens[idx - 1];
    if (tok_eq(prev, "=")) return true;
    if (tok_eq(prev, "return")) return true;
    if (tok_eq(prev, "(") or tok_eq(prev, ",") or tok_eq(prev, "[")) return true;
    if (tok_eq(prev, "{")) return !is_struct_decl_body_open(tokens, idx - 1);
    if (is_spread_token(prev)) return true;
    if (idx >= 2 and is_return_arrow_at(tokens, idx - 2)) return false;
    if (prev.kind == .ident or tok_eq(prev, "]") or tok_eq(prev, ">") or tok_eq(prev, "|")) return false;
    return true;
}


fn inferred_struct_ctor_info(structs: []const StructInfo, tokens: []const lexer.Token, dot_idx: usize) ?StructInfo {
    const line_start = line_start_idx(tokens, dot_idx);
    if (dot_idx == 0) return null;
    const eq_idx = dot_idx - 1;
    if (tokens[eq_idx].line != tokens[dot_idx].line or !tok_eq(tokens[eq_idx], "=")) return null;
    if (is_non_assign_equal(tokens, eq_idx)) return null;
    if (line_start + 1 >= eq_idx) return null;
    if (tokens[line_start].kind != .ident) return null;

    const type_idx = line_start + 1;
    if (tokens[type_idx].kind != .ident) return null;
    return find_struct_info(structs, public_type_name(tokens[type_idx].lexeme));
}


fn check_one_struct_ctor_fields(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    ctor_idx: usize,
    start_idx: usize,
    end_idx: usize,
    struct_info: StructInfo,
) !void {
    var seen = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer seen.deinit(allocator);

    var field_start = start_idx;
    while (field_start < end_idx) {
        if (tok_eq(tokens[field_start], ",")) {
            field_start += 1;
            continue;
        }
        const assign_idx = find_top_level_assign_eq(tokens, field_start, end_idx) orelse
            return mark_error_at(tokens, field_start, error.InvalidStructLiteral);
        if (assign_idx == field_start or tokens[field_start].kind != .ident) {
            return mark_error_at(tokens, field_start, error.InvalidStructLiteral);
        }
        if (assign_idx != field_start + 1) {
            return mark_error_at(tokens, field_start, error.InvalidStructLiteral);
        }
        const field_end = find_struct_ctor_field_end(tokens, assign_idx + 1, end_idx);
        if (field_end == assign_idx + 1) return mark_error_at(tokens, assign_idx, error.InvalidStructLiteral);
        const field_name = normalize_struct_field_name(tokens[field_start].lexeme);
        if (find_struct_field_info(struct_info.fields, field_name) == null) {
            return mark_error_at(tokens, field_start, error.InvalidStructLiteral);
        }
        if (has_seen_field(seen.items, field_name)) {
            return mark_error_at(tokens, field_start, error.InvalidStructLiteral);
        }
        try seen.append(allocator, field_name);
        field_start = field_end;
        if (field_start < end_idx and tok_eq(tokens[field_start], ",")) field_start += 1;
    }

    for (struct_info.fields) |field| {
        if (field.has_default) continue;
        if (has_seen_field(seen.items, field.name)) continue;
        return mark_error_at(tokens, ctor_idx, error.InvalidStructLiteral);
    }
}


fn find_struct_field_info(fields: []const StructFieldInfo, name: []const u8) ?StructFieldInfo {
    for (fields) |field| {
        if (std.mem.eql(u8, field.name, name)) return field;
    }
    return null;
}


fn has_seen_field(seen: []const []const u8, name: []const u8) bool {
    for (seen) |field_name| {
        if (std.mem.eql(u8, field_name, name)) return true;
    }
    return false;
}


fn find_struct_ctor_field_end(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
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
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tok_eq(tokens[i], ",")) return i;
    }
    return end_idx;
}


fn check_one_struct_field_names(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) !void {
    var seen = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer seen.deinit(allocator);

    var i = start_idx;
    while (i < end_idx) {
        if (tokens[i].kind != .ident or !is_struct_field_name(tokens[i].lexeme)) {
            if (tokens[i].kind == .ident and is_reserved_field_name(tokens[i].lexeme)) {
                return mark_error_at(tokens, i, error.InvalidTypeRef);
            }
            i = find_line_end_idx(tokens, i);
            continue;
        }
        const field_name = normalize_struct_field_name(tokens[i].lexeme);
        for (seen.items) |prev| {
            if (std.mem.eql(u8, prev, field_name)) {
                return mark_error_at(tokens, i, error.DuplicateStructFieldName);
            }
        }
        try seen.append(allocator, field_name);
        i = find_line_end_idx(tokens, i);
    }
}


fn is_reserved_field_name(name: []const u8) bool {
    const public_name = normalize_struct_field_name(name);
    return is_reserved_field_name_body(public_name);
}


pub fn check_generic_struct_ctor_type_args(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (!is_valid_declared_type_name(tokens[i].lexeme)) continue;
        if (!tok_eq(tokens[i + 1], "{")) continue;
        if (is_top_level_decl_head(tokens, i) and is_struct_decl_start(tokens, i)) continue;
        if (!is_generic_struct_type_name(tokens, public_type_name(tokens[i].lexeme))) continue;
        return mark_error_at(tokens, i, error.InvalidTypeRef);
    }
}


/// Position-ctor arity for `Tuple<T0,...>{v0,...}` must equal type-arg count.
/// Nested ctors are scanned by not skipping the body after the outer ctor.
/// Named field inits are usually rejected earlier as InvalidStructLiteral by the parser;
/// this path remains as a defensive fallback (InvalidTypedLiteral).
pub fn check_tuple_ctor_arity(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, public_type_name(tokens[i].lexeme), "Tuple")) continue;
        if (!tok_eq(tokens[i + 1], "<")) continue;

        const close_angle = find_matching(tokens, i + 1, "<", ">") catch continue;
        if (close_angle + 1 >= tokens.len or !tok_eq(tokens[close_angle + 1], "{")) {
            i = close_angle;
            continue;
        }
        // `f() -> Tuple<...>{ ... }` is a function body brace, not a position ctor.
        // Lexer emits `->` as two symbol tokens (`-`, `>`).
        if (i >= 2 and tok_eq(tokens[i - 2], "-") and tok_eq(tokens[i - 1], ">")) {
            i = close_angle;
            continue;
        }
        if (is_top_level_decl_head(tokens, i) and is_type_decl_start(tokens, i)) {
            i = close_angle;
            continue;
        }

        const open_brace = close_angle + 1;
        const close_brace = find_matching(tokens, open_brace, "{", "}") catch
            return mark_error_at(tokens, open_brace, error.InvalidTypedLiteral);
        const expected = count_type_args(tokens, i + 2, close_angle);
        if (expected < 2) {
            // arity floor already reported by check_generic_type_arg_arity when reachable.
            // Still walk the body so nested Tuple ctors are checked.
            i = open_brace;
            continue;
        }
        if (tuple_ctor_body_has_named_field(tokens, open_brace + 1, close_brace)) {
            return mark_error_at(tokens, open_brace, error.InvalidTypedLiteral);
        }
        const actual = count_tuple_ctor_positional_args(tokens, open_brace + 1, close_brace);
        if (actual != expected) return mark_error_at(tokens, i, error.InvalidTypedLiteral);
        try check_tuple_ctor_elem_literal_types(tokens, i + 2, close_angle, open_brace + 1, close_brace);
        // Do not jump to close_brace: nested `Tuple<...>{...}` lives inside the body.
        i = open_brace;
    }
}


fn tuple_ctor_body_has_named_field(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
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
        return true;
    }
    return false;
}


fn count_tuple_ctor_positional_args(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    if (start_idx >= end_idx) return 0;

    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var count: usize = 1;
    var saw_token = false;

    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "(")) {
            depth_paren += 1;
            saw_token = true;
            continue;
        }
        if (tok_eq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            saw_token = true;
            continue;
        }
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            saw_token = true;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            saw_token = true;
            continue;
        }
        if (tok_eq(tokens[i], "<")) {
            depth_angle += 1;
            saw_token = true;
            continue;
        }
        if (tok_eq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            saw_token = true;
            continue;
        }
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tok_eq(tokens[i], ",")) {
            // Trailing comma is not an extra positional arg.
            if (!tuple_ctor_has_top_level_token_after(tokens, i + 1, end_idx)) continue;
            count += 1;
            continue;
        }
        saw_token = true;
    }
    if (!saw_token) return 0;
    return count;
}


fn tuple_ctor_has_top_level_token_after(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "(")) {
            depth_paren += 1;
            return true;
        }
        if (tok_eq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            return true;
        }
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            return true;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            return true;
        }
        if (tok_eq(tokens[i], "<")) {
            depth_angle += 1;
            return true;
        }
        if (tok_eq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            return true;
        }
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tok_eq(tokens[i], ",")) {
            continue;
        }
        return true;
    }
    return false;
}

/// One positional segment of a typed tuple ctor: literal vs matching type arg.
fn check_tuple_ctor_segment_literal(
    tokens: []const lexer.Token,
    type_args_start: usize,
    type_args_end: usize,
    seg_start: usize,
    seg_end: usize,
    arg_idx: usize,
) !void {
    if (seg_start >= seg_end) return;
    const type_range = nth_type_arg_range(tokens, type_args_start, type_args_end, arg_idx) orelse return;
    if (tuple_positional_arg_compatible_with_type(tokens, seg_start, seg_end, type_range.start, type_range.end)) return;
    return mark_error_at(tokens, seg_start, error.InvalidTypedLiteral);
}

/// Lightweight literal-vs-type-arg checks for position ctors.
/// Covers obvious mismatches (bool vs integer, etc.); complex exprs stay for later phases.
fn check_tuple_ctor_elem_literal_types(
    tokens: []const lexer.Token,
    type_args_start: usize,
    type_args_end: usize,
    body_start: usize,
    body_end: usize,
) !void {
    var arg_idx: usize = 0;
    var seg_start = body_start;
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = body_start;
    while (i <= body_end) : (i += 1) {
        const at_end = i == body_end;
        const at_top_comma = !at_end and depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tok_eq(tokens[i], ",");
        if (!at_end and !at_top_comma) {
            // Flat depth bookkeeping stays inline (not a complete named boundary).
            if (tok_eq(tokens[i], "(")) {
                depth_paren += 1;
            } else if (tok_eq(tokens[i], ")")) {
                if (depth_paren > 0) depth_paren -= 1;
            } else if (tok_eq(tokens[i], "{")) {
                depth_brace += 1;
            } else if (tok_eq(tokens[i], "}")) {
                if (depth_brace > 0) depth_brace -= 1;
            } else if (tok_eq(tokens[i], "<")) {
                depth_angle += 1;
            } else if (tok_eq(tokens[i], ">")) {
                if (depth_angle > 0) depth_angle -= 1;
            }
            continue;
        }

        try check_tuple_ctor_segment_literal(tokens, type_args_start, type_args_end, seg_start, i, arg_idx);
        if (seg_start < i) arg_idx += 1;
        seg_start = i + 1;
    }
}


const TypeArgRange = struct { start: usize, end: usize };


fn nth_type_arg_range(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, want: usize) ?TypeArgRange {
    if (start_idx >= end_idx) return null;
    var depth_paren: usize = 0;
    var depth_bracket: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var idx: usize = 0;
    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        const at_end = i == end_idx;
        const at_top_comma = !at_end and depth_paren == 0 and depth_bracket == 0 and depth_brace == 0 and depth_angle == 0 and tok_eq(tokens[i], ",");
        if (!at_end and !at_top_comma) {
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
                if (depth_angle > 0) depth_angle -= 1;
                continue;
            }
            continue;
        }
        if (idx == want and seg_start < i) return .{ .start = seg_start, .end = i };
        idx += 1;
        seg_start = i + 1;
    }
    return null;
}


fn tuple_positional_arg_compatible_with_type(
    tokens: []const lexer.Token,
    arg_start: usize,
    arg_end: usize,
    type_start: usize,
    type_end: usize,
) bool {
    if (arg_start >= arg_end or type_start >= type_end) return true;

    // Nested position ctor: `Tuple<...>{...}` against a Tuple type arg.
    if (tokens[arg_start].kind == .ident and
        std.mem.eql(u8, public_type_name(tokens[arg_start].lexeme), "Tuple") and
        arg_start + 1 < arg_end and tok_eq(tokens[arg_start + 1], "<"))
    {
        if (tokens[type_start].kind != .ident) return true;
        if (!std.mem.eql(u8, public_type_name(tokens[type_start].lexeme), "Tuple")) return false;
        return true;
    }

    // Single-token literal against a simple type name.
    if (arg_end != arg_start + 1) return true;
    if (type_end != type_start + 1 or tokens[type_start].kind != .ident) return true;

    const ty = public_type_name(tokens[type_start].lexeme);
    const lit = tokens[arg_start];

    if (std.mem.eql(u8, lit.lexeme, "true") or std.mem.eql(u8, lit.lexeme, "false")) {
        return std.mem.eql(u8, ty, "bool");
    }
    if (lit.kind == .number) {
        return is_integer_type_name(ty) or is_float_type_name(ty);
    }
    if (lit.kind == .string) {
        return std.mem.eql(u8, ty, "text");
    }
    return true;
}


fn is_integer_type_name(ty: []const u8) bool {
    const names = [_][]const u8{ "u8", "u16", "u32", "u64", "usize", "i8", "i16", "i32", "i64", "isize" };
    for (names) |name| {
        if (std.mem.eql(u8, ty, name)) return true;
    }
    return false;
}


fn is_float_type_name(ty: []const u8) bool {
    return std.mem.eql(u8, ty, "f32") or std.mem.eql(u8, ty, "f64");
}

/// `@get(tuple, N)` requires compile-time integer N in `0..arity-1` when the source is Tuple.

/// `@get(tuple, N)` requires compile-time integer N in `0..arity-1` when the source is Tuple.
pub fn check_tuple_get_index(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tok_eq(tokens[i], "get")) continue;
        if (i + 1 >= tokens.len or !tok_eq(tokens[i + 1], "(")) continue;
        if (i == 0 or !tok_eq(tokens[i - 1], "@") or tokens[i - 1].line != tokens[i].line) continue;

        const close_paren = find_matching(tokens, i + 1, "(", ")") catch continue;
        const first_end = find_top_level_comma(tokens, i + 2, close_paren) orelse {
            i = close_paren;
            continue;
        };
        if (first_end <= i + 2) {
            i = close_paren;
            continue;
        }
        // Only simple two-arg `@get(source, index)` form.
        if (find_top_level_comma(tokens, first_end + 1, close_paren) != null) {
            i = close_paren;
            continue;
        }

        const source_start = i + 2;
        const source_end = first_end;
        if (source_end != source_start + 1 or tokens[source_start].kind != .ident) {
            i = close_paren;
            continue;
        }

        const arity = find_nearest_tuple_arity(tokens, i, tokens[source_start].lexeme) orelse {
            i = close_paren;
            continue;
        };

        const index_start = first_end + 1;
        const index_end = close_paren;
        if (index_end != index_start + 1 or tokens[index_start].kind != .number) {
            return mark_error_at(tokens, index_start, error.InvalidPathIndex);
        }
        const index = std.fmt.parseInt(usize, tokens[index_start].lexeme, 10) catch
            return mark_error_at(tokens, index_start, error.InvalidPathIndex);
        if (index >= arity) return mark_error_at(tokens, index_start, error.InvalidPathIndex);
        i = close_paren;
    }
}

/// Returns arity when the nearest binding type of `name` before `before_idx` is `Tuple<...>`.

/// Returns arity when the nearest binding type of `name` before `before_idx` is `Tuple<...>`.
fn find_nearest_tuple_arity(tokens: []const lexer.Token, before_idx: usize, name: []const u8) ?usize {
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
        if (eq_idx <= i + 1) continue;
        if (tokens[i + 1].kind != .ident) continue;
        if (!std.mem.eql(u8, public_type_name(tokens[i + 1].lexeme), "Tuple")) continue;
        if (i + 2 >= eq_idx or !tok_eq(tokens[i + 2], "<")) continue;
        const close_angle = find_matching(tokens, i + 2, "<", ">") catch continue;
        if (close_angle > eq_idx) continue;
        return count_type_args(tokens, i + 3, close_angle);
    }

    // Function param: `name Tuple<...>`
    return find_enclosing_func_param_tuple_arity(tokens, before_idx, name);
}


fn find_enclosing_func_param_tuple_arity(tokens: []const lexer.Token, before_idx: usize, name: []const u8) ?usize {
    var skip_depth: usize = 0;
    var i = before_idx;
    while (i > 0) {
        i -= 1;

        if (tok_eq(tokens[i], "}")) {
            skip_depth += 1;
            continue;
        }
        if (!tok_eq(tokens[i], "{")) continue;
        if (skip_depth > 0) {
            skip_depth -= 1;
            continue;
        }
        if (find_func_param_tuple_arity_before_body(tokens, i, name)) |arity| return arity;
    }
    return null;
}


fn find_func_param_tuple_arity_before_body(tokens: []const lexer.Token, body_open_idx: usize, name: []const u8) ?usize {
    const line_start = line_start_idx(tokens, body_open_idx);
    if (line_start >= body_open_idx) return null;
    if (!is_func_decl_start(tokens, line_start) and !is_start_decl_start(tokens, line_start)) return null;

    const close_paren = find_matching(tokens, line_start + 1, "(", ")") catch return null;
    if (close_paren >= body_open_idx) return null;

    var seg_start = line_start + 2;
    var j = seg_start;
    while (j <= close_paren) : (j += 1) {
        if (j < close_paren and !is_top_level_comma_any(tokens, j, line_start + 2, close_paren)) continue;
        if (seg_start + 1 < j and tokens[seg_start].kind == .ident and std.mem.eql(u8, tokens[seg_start].lexeme, name)) {
            if (tokens[seg_start + 1].kind == .ident and
                std.mem.eql(u8, public_type_name(tokens[seg_start + 1].lexeme), "Tuple") and
                seg_start + 2 < j and tok_eq(tokens[seg_start + 2], "<"))
            {
                const close_angle = find_matching(tokens, seg_start + 2, "<", ">") catch return null;
                if (close_angle < j) return count_type_args(tokens, seg_start + 3, close_angle);
            }
        }
        seg_start = j + 1;
    }
    return null;
}


fn is_generic_struct_type_name(tokens: []const lexer.Token, name: []const u8) bool {
    return generic_struct_type_param_count(tokens, name) != null;
}


fn generic_struct_type_param_count(tokens: []const lexer.Token, name: []const u8) ?usize {
    const count = local_struct_type_param_count(tokens, name) orelse return null;
    return if (count == 0) null else count;
}

