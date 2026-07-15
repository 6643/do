//! Sema func shared helpers (multi-domain).
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema_error = @import("sema_error.zig");
const type_util = @import("type_name.zig");
const sema_tokens = @import("sema_tokens.zig");
const sema_shapes = @import("sema_shapes.zig");
const CallArgInfo = sema_shapes.CallArgInfo;
const CallArgShape = sema_shapes.CallArgShape;
const FuncParamShape = sema_shapes.FuncParamShape;
const FuncShape = sema_shapes.FuncShape;
const LocalImportPrefix = sema_shapes.LocalImportPrefix;
const StructFieldInfo = sema_shapes.StructFieldInfo;
const StructInfo = sema_shapes.StructInfo;
const CallShape = sema_shapes.CallShape;
const ResolvedFuncTypeShape = sema_shapes.ResolvedFuncTypeShape;

const compact_type_name = sema_tokens.compact_type_name;
const enum_decl_has_branch = sema_tokens.enum_decl_has_branch;
const find_line_end_idx = sema_tokens.find_line_end_idx;
const find_matching = sema_tokens.find_matching;
const find_return_type_end = sema_tokens.find_return_type_end;
const find_struct_field_type_end = sema_tokens.find_struct_field_type_end;
const find_top_level_assign_eq_on_line = sema_tokens.find_top_level_assign_eq_on_line;
const is_arrow_at = sema_tokens.is_arrow_at;
const is_func_decl_start = sema_tokens.is_func_decl_start;
const is_keyword = sema_tokens.is_keyword;
const is_lower_ident_name = sema_tokens.is_lower_ident_name;
const is_modern_import_assign = sema_tokens.is_modern_import_assign;
const is_payload_enum_decl_start = sema_tokens.is_payload_enum_decl_start;
const is_readonly_ident_name = sema_tokens.is_readonly_ident_name;
const is_return_arrow_at = sema_tokens.is_return_arrow_at;
const is_spread_token = sema_tokens.is_spread_token;
const is_struct_decl_start = sema_tokens.is_struct_decl_start;
const is_struct_field_name = sema_tokens.is_struct_field_name;
const is_top_level_comma_any = sema_tokens.is_top_level_comma_any;
const is_top_level_decl_head = sema_tokens.is_top_level_decl_head;
const is_top_level_value_decl_start = sema_tokens.is_top_level_value_decl_start;
const is_type_decl_start = sema_tokens.is_type_decl_start;
const is_valid_declared_type_name = sema_tokens.is_valid_declared_type_name;
const normalize_struct_field_name = sema_tokens.normalize_struct_field_name;
const public_func_name = sema_tokens.public_func_name;
const public_type_name = sema_tokens.public_type_name;
const simple_type_name = sema_tokens.simple_type_name;
const tok_eq = sema_tokens.tok_eq;
const top_level_line_assign_idx = sema_tokens.top_level_line_assign_idx;
const call_arg_info = sema_tokens.call_arg_info;
const call_arity_compatible_with_func = sema_tokens.call_arity_compatible_with_func;
const call_name_idx_before_open = sema_tokens.call_name_idx_before_open;
const compact_token_range_equals = sema_tokens.compact_token_range_equals;
const contains_name = sema_tokens.contains_name;
const count_type_args = sema_tokens.count_type_args;
const enum_decl_assign_idx = sema_tokens.enum_decl_assign_idx;
const find_constraint_block_start_before = sema_tokens.find_constraint_block_start_before;
const find_enclosing_call_open = sema_tokens.find_enclosing_call_open;
const find_inline_func_type_in_params = sema_tokens.find_inline_func_type_in_params;
const find_matching_in_range = sema_tokens.find_matching_in_range;
const find_nearest_value_type_name = sema_tokens.find_nearest_value_type_name;
const find_plain_eq_on_line = sema_tokens.find_plain_eq_on_line;
const find_struct_info = sema_tokens.find_struct_info;
const find_top_level_comma = sema_tokens.find_top_level_comma;
const first_non_gap = sema_tokens.first_non_gap;
const func_param_type_start = sema_tokens.func_param_type_start;
const has_known_func_candidate = sema_tokens.has_known_func_candidate;
const has_local_struct_decl = sema_tokens.has_local_struct_decl;
const has_return_arrow_before_on_line = sema_tokens.has_return_arrow_before_on_line;
const has_top_level_comma = sema_tokens.has_top_level_comma;
const has_type_constraint_name = sema_tokens.has_type_constraint_name;
const is_all_digits = sema_tokens.is_all_digits;
const is_base_int_type_name = sema_tokens.is_base_int_type_name;
const is_base_type_name = sema_tokens.is_base_type_name;
const is_builtin_special_or_core_name = sema_tokens.is_builtin_special_or_core_name;
const is_decl_only_name = sema_tokens.is_decl_only_name;
const is_declared_type_name = sema_tokens.is_declared_type_name;
const is_dot_lower_ident = sema_tokens.is_dot_lower_ident;
const is_error_enum_decl_start = sema_tokens.is_error_enum_decl_start;
const is_error_type_name = sema_tokens.is_error_type_name;
const is_func_type_param = sema_tokens.is_func_type_param;
const is_func_type_range = sema_tokens.is_func_type_range;
const is_generic_type_start = sema_tokens.is_generic_type_start;
const is_host_import_decl_start = sema_tokens.is_host_import_decl_start;
const is_host_import_line = sema_tokens.is_host_import_line;
const is_inside_struct_decl = sema_tokens.is_inside_struct_decl;
const is_non_assign_equal = sema_tokens.is_non_assign_equal;
const is_numeric_core_func_name = sema_tokens.is_numeric_core_func_name;
const is_reserved_core_access_name = sema_tokens.is_reserved_core_access_name;
const is_reserved_field_name_body = sema_tokens.is_reserved_field_name_body;
const is_reserved_func_name = sema_tokens.is_reserved_func_name;
const is_reserved_source_name = sema_tokens.is_reserved_source_name;
const is_snake_lower_name = sema_tokens.is_snake_lower_name;
const is_start_decl_start = sema_tokens.is_start_decl_start;
const is_struct_decl_body_open = sema_tokens.is_struct_decl_body_open;
const is_struct_field_decl_default = sema_tokens.is_struct_field_decl_default;
const is_top_level_decl_start = sema_tokens.is_top_level_decl_start;
const is_top_level_token = sema_tokens.is_top_level_token;
const is_type_name = sema_tokens.is_type_name;
const is_valid_dep_file_stem = sema_tokens.is_valid_dep_file_stem;
const is_valid_enum_branch_name = sema_tokens.is_valid_enum_branch_name;
const is_valid_flat_file_stem = sema_tokens.is_valid_flat_file_stem;
const is_valid_func_decl_name = sema_tokens.is_valid_func_decl_name;
const is_valid_path_seg = sema_tokens.is_valid_path_seg;
const is_value_enum_decl_start = sema_tokens.is_value_enum_decl_start;
const is_value_literal_token = sema_tokens.is_value_literal_token;
const is_value_type_name = sema_tokens.is_value_type_name;
const is_wit_only_source_type_name = sema_tokens.is_wit_only_source_type_name;
const line_start_idx = sema_tokens.line_start_idx;
const mark_error_at = sema_tokens.mark_error_at;
const string_token_body = sema_tokens.string_token_body;
const token_name_appears_in_range = sema_tokens.token_name_appears_in_range;
const type_constraint_is_function_type = sema_tokens.type_constraint_is_function_type;
const validate_import_file_name = sema_tokens.validate_import_file_name;
const validate_import_file_name_text = sema_tokens.validate_import_file_name_text;
const validate_is_type_arg_list = sema_tokens.validate_is_type_arg_list;
const validate_is_type_atom = sema_tokens.validate_is_type_atom;
const validate_is_type_expr = sema_tokens.validate_is_type_expr;
const validate_is_type_expr_until_comma = sema_tokens.validate_is_type_expr_until_comma;



pub fn is_scalar_as_target_type_name(name: []const u8) bool {
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



pub fn find_inline_func_type_in_is_arg(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (!tok_eq(tokens[i], "(")) continue;
        const close_paren = find_matching(tokens, i, "(", ")") catch return null;
        if (close_paren + 2 < end_idx and is_return_arrow_at(tokens, close_paren + 1)) return i;
        if (find_inline_func_type_in_is_arg(tokens, i + 1, close_paren)) |func_type_idx| return func_type_idx;
        i = close_paren;
    }
    return null;
}



pub fn find_top_level_nil_in_is_arg(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var depth_angle: usize = 0;
    var depth_bracket: usize = 0;
    var depth_paren: usize = 0;
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
        if (tok_eq(tokens[i], "[")) {
            depth_bracket += 1;
            continue;
        }
        if (tok_eq(tokens[i], "]")) {
            if (depth_bracket > 0) depth_bracket -= 1;
            continue;
        }
        if (depth_angle == 0 and depth_bracket == 0 and depth_paren == 0 and tok_eq(tokens[i], "nil")) return i;
    }
    return null;
}



pub fn collect_call_shapes_from_program(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    out: *std.ArrayList(CallShape),
) !void {
    for (program.expr_nodes) |node| {
        switch (node.kind) {
            .call => {},
            else => continue,
        }

        const call_start = node.start_tok;
        const open_paren = call_open_paren_idx(tokens, call_start, node.end_tok) orelse continue;

        const args_start = open_paren + 1;
        const args_end = node.end_tok - 1;
        const args = try parse_call_arg_shapes(allocator, tokens, args_start, args_end);
        try out.append(allocator, .{
            .name = tokens[call_start].lexeme,
            .start_idx = node.start_tok,
            .has_explicit_type_args = open_paren != call_start + 1,
            .arg_shapes = args,
        });
    }
}



pub fn resolve_func_param_type_shape(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    func: FuncShape,
    param: FuncParamShape,
) !?ResolvedFuncTypeShape {
    return switch (param) {
        .func => |func_type| .{ .shape = func_type, .owned = false },
        .value => |type_name| if (type_name) |name|
            try parse_concrete_func_type_constraint_shape(allocator, tokens, func.start_idx, name)
        else
            null,
        .variadic => |type_name| if (type_name) |name|
            try parse_concrete_func_type_constraint_shape(allocator, tokens, func.start_idx, name)
        else
            null,
        .other => null,
    };
}



pub fn free_resolved_func_type_shape(allocator: std.mem.Allocator, resolved: ?ResolvedFuncTypeShape) void {
    const item = resolved orelse return;
    if (!item.owned) return;
    free_func_type_param_names(allocator, item.shape.param_types);
}



pub fn parse_concrete_func_type_constraint_shape(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    func_start_idx: usize,
    constraint_name: []const u8,
) !?ResolvedFuncTypeShape {
    const block_start = find_constraint_block_start_before(tokens, func_start_idx) orelse return null;

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

        const eq_idx = find_top_level_assign_eq_on_line(tokens, i + 2, line_end) orelse return null;
        if (!is_func_type_range(tokens, eq_idx + 1, line_end)) return null;
        if (func_type_constraint_uses_prior_type_param(tokens, block_start, i, eq_idx + 1, line_end)) return null;

        const close_params = find_matching(tokens, eq_idx + 1, "(", ")") catch return null;
        const param_types = try parse_type_name_list(allocator, tokens, eq_idx + 2, close_params);
        return .{
            .shape = .{
                .param_count = param_types.len,
                .param_types = param_types,
                .return_type = simple_type_name(tokens, close_params + 3, line_end),
            },
            .owned = true,
        };
    }
    return null;
}



pub fn type_constraint_is_concrete_function_type(
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
        if (!is_func_type_range(tokens, eq_idx + 1, line_end)) return false;
        return !func_type_constraint_uses_prior_type_param(tokens, block_start, i, eq_idx + 1, line_end);
    }
    return false;
}



pub fn func_type_constraint_uses_prior_type_param(
    tokens: []const lexer.Token,
    block_start: usize,
    constraint_idx: usize,
    type_start: usize,
    type_end: usize,
) bool {
    var i = type_start;
    while (i < type_end) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (has_type_constraint_name(tokens, block_start, constraint_idx, tokens[i].lexeme)) return true;
    }
    return false;
}



pub fn call_open_paren_idx(tokens: []const lexer.Token, name_idx: usize, limit_idx: usize) ?usize {
    if (name_idx + 1 >= limit_idx) return null;
    if (tok_eq(tokens[name_idx + 1], "(")) return name_idx + 1;
    if (!tok_eq(tokens[name_idx + 1], "<")) return null;

    const close_angle = find_matching_in_range(tokens, name_idx + 1, "<", ">", limit_idx) catch return null;
    if (close_angle + 1 >= limit_idx or !tok_eq(tokens[close_angle + 1], "(")) return null;
    return close_angle + 1;
}



pub fn find_enclosing_func_param_type_name(tokens: []const lexer.Token, before_idx: usize, name: []const u8) ?[]const u8 {
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
        if (find_func_param_type_name_before_body(tokens, i, name)) |type_name| return type_name;
    }
    return null;
}



pub fn find_func_param_type_name_before_body(
    tokens: []const lexer.Token,
    body_open_idx: usize,
    name: []const u8,
) ?[]const u8 {
    const line_start = line_start_idx(tokens, body_open_idx);
    if (line_start >= body_open_idx) return null;
    if (!is_func_decl_start(tokens, line_start)) return null;

    const close_paren = find_matching(tokens, line_start + 1, "(", ")") catch return null;
    if (close_paren >= body_open_idx) return null;
    return find_param_type_name(tokens, line_start + 2, close_paren, name);
}



pub fn find_param_type_name(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    name: []const u8,
) ?[]const u8 {
    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !is_top_level_comma_any(tokens, i, start_idx, end_idx)) continue;
        if (seg_start + 1 < i and tokens[seg_start].kind == .ident and std.mem.eql(u8, tokens[seg_start].lexeme, name)) {
            if (tokens[seg_start + 1].kind == .ident) return tokens[seg_start + 1].lexeme;
        }
        seg_start = i + 1;
    }
    return null;
}

// Shared shape parsing/collection helpers.
pub fn collect_func_shapes(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]FuncShape {
    var out = std.ArrayList(FuncShape).empty;
    errdefer {
        for (out.items) |shape| free_func_param_shapes(allocator, shape.param_shapes);
        out.deinit(allocator);
    }

    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) {
        if (tok_eq(tokens[i], "{")) {
            if (skip_top_level_import_brace(tokens, i, depth_brace)) |skip_i| {
                i = skip_i + 1;
                continue;
            }
            depth_brace += 1;
            i += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            i += 1;
            continue;
        }
        if (depth_brace != 0 or !is_top_level_decl_head(tokens, i) or !is_func_decl_start(tokens, i)) {
            i += 1;
            continue;
        }

        const close_paren = find_matching(tokens, i + 1, "(", ")") catch {
            i += 1;
            continue;
        };
        const params = try parse_func_param_shapes(allocator, tokens, i + 2, close_paren);
        const arity = parse_func_param_arity(tokens, i + 2, close_paren);
        try out.append(allocator, .{
            .name = public_func_name(tokens[i].lexeme),
            .start_idx = i,
            .param_shapes = params,
            .param_min = arity.param_min,
            .param_max = arity.param_max,
            .return_type = parse_top_level_func_return_type(tokens, close_paren + 1),
        });
        i = close_paren + 1;
    }

    const owned = try out.toOwnedSlice(allocator);
    return owned;
}


pub fn free_func_shapes(allocator: std.mem.Allocator, funcs: []FuncShape) void {
    for (funcs) |shape| free_func_param_shapes(allocator, shape.param_shapes);
    allocator.free(funcs);
}


pub fn free_func_param_shapes(allocator: std.mem.Allocator, shapes: []FuncParamShape) void {
    for (shapes) |shape| {
        switch (shape) {
            .other => {},
            .value => |type_name| if (type_name) |name| allocator.free(name),
            .variadic => |type_name| if (type_name) |name| allocator.free(name),
            .func => |func_type| free_func_type_param_names(allocator, func_type.param_types),
        }
    }
    allocator.free(shapes);
}


pub fn free_func_type_param_names(allocator: std.mem.Allocator, param_types: []?[]const u8) void {
    for (param_types) |param_type| {
        if (param_type) |name| allocator.free(name);
    }
    allocator.free(param_types);
}


pub fn free_call_arg_shapes(allocator: std.mem.Allocator, shapes: []CallArgShape) void {
    for (shapes) |shape| {
        switch (shape) {
            .other => {},
            .lambda => |lambda| allocator.free(lambda.param_types),
            .ident => {},
            .spread => {},
        }
    }
    allocator.free(shapes);
}


pub fn parse_func_param_shapes(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ![]FuncParamShape {
    var out = std.ArrayList(FuncParamShape).empty;
    errdefer out.deinit(allocator);

    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !is_top_level_comma_any(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            try out.append(allocator, try parse_func_param_shape(allocator, tokens, seg_start, i));
        }
        seg_start = i + 1;
    }

    return out.toOwnedSlice(allocator);
}


pub fn parse_func_param_shape(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) !FuncParamShape {
    if (start_idx + 1 >= end_idx) return .other;
    const type_start = if (is_spread_token(tokens[start_idx + 1])) start_idx + 2 else start_idx + 1;
    if (type_start >= end_idx) return .other;
    if (!tok_eq(tokens[type_start], "(")) {
        const type_name = try compact_type_name(allocator, tokens, type_start, end_idx);
        if (type_start != start_idx + 1) return .{ .variadic = type_name };
        return .{ .value = type_name };
    }
    const close_param_types = find_matching(tokens, type_start, "(", ")") catch return .other;
    if (close_param_types >= end_idx) return .other;
    if (!is_return_arrow_at(tokens, close_param_types + 1)) return .other;

    const param_types = try parse_type_name_list(allocator, tokens, type_start + 1, close_param_types);
    return .{ .func = .{
        .param_count = param_types.len,
        .param_types = param_types,
        .return_type = simple_type_name(tokens, close_param_types + 3, end_idx),
    } };
}


pub fn parse_func_param_arity(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) struct { param_min: usize, param_max: ?usize } {
    var min_count: usize = 0;
    var has_variadic = false;
    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !is_top_level_comma_any(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            if (seg_start + 1 < i and is_spread_token(tokens[seg_start + 1])) {
                has_variadic = true;
            } else {
                min_count += 1;
            }
        }
        seg_start = i + 1;
    }
    return .{
        .param_min = min_count,
        .param_max = if (has_variadic) null else min_count,
    };
}


pub fn parse_top_level_func_return_type(tokens: []const lexer.Token, start_idx: usize) ?[]const u8 {
    if (start_idx >= tokens.len) return null;
    if (tok_eq(tokens[start_idx], "{") or is_arrow_at(tokens, start_idx)) return null;

    if (is_return_arrow_at(tokens, start_idx)) {
        return simple_type_name(tokens, start_idx + 2, find_return_type_end(tokens, start_idx + 2));
    }

    return simple_type_name(tokens, start_idx, find_return_type_end(tokens, start_idx));
}


pub fn parse_call_arg_shapes(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ![]CallArgShape {
    var out = std.ArrayList(CallArgShape).empty;
    errdefer out.deinit(allocator);

    var seg_start = start_idx;
    var arg_index: usize = 0;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !is_top_level_comma_any(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            try out.append(allocator, try parse_call_arg_shape(allocator, tokens, seg_start, i, arg_index));
            arg_index += 1;
        }
        seg_start = i + 1;
    }

    return out.toOwnedSlice(allocator);
}


pub fn parse_call_arg_shape(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    arg_index: usize,
) !CallArgShape {
    if (start_idx < end_idx and is_spread_token(tokens[start_idx])) return .{ .spread = start_idx };

    const close_params = lambda_param_close(tokens, start_idx, end_idx);
    if (close_params) |close_idx| {
        if (lambda_body_start(tokens, close_idx + 1, end_idx) != null) {
            const param_types = try parse_lambda_param_type_list(allocator, tokens, start_idx + 1, close_idx);
            return .{ .lambda = .{
                .arg_index = arg_index,
                .param_count = param_types.len,
                .param_types = param_types,
                .return_type = lambda_return_type_name(tokens, close_idx, end_idx),
            } };
        }
    }

    if (start_idx + 1 == end_idx and tokens[start_idx].kind == .ident) {
        return .{ .ident = tokens[start_idx].lexeme };
    }

    return .other;
}


pub fn lambda_param_close(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (start_idx >= end_idx or !tok_eq(tokens[start_idx], "(")) return null;
    const close_idx = find_matching(tokens, start_idx, "(", ")") catch return null;
    if (close_idx >= end_idx) return null;
    return close_idx;
}


pub fn lambda_return_type_name(tokens: []const lexer.Token, close_params_idx: usize, end_idx: usize) ?[]const u8 {
    const return_arrow_idx = close_params_idx + 1;
    if (!is_return_arrow_at(tokens, return_arrow_idx)) return null;

    const body_start = lambda_body_start(tokens, return_arrow_idx, end_idx) orelse return null;
    const return_end = if (body_start >= 2 and is_arrow_at(tokens, body_start - 2))
        body_start - 2
    else
        body_start;
    return simple_type_name(tokens, return_arrow_idx + 2, return_end);
}


pub fn count_lambda_params(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    if (start_idx >= end_idx) return 0;
    var count: usize = 0;
    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !is_top_level_comma_any(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) count += 1;
        seg_start = i + 1;
    }
    return count;
}


pub fn parse_type_name_list(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ![]?[]const u8 {
    var out = std.ArrayList(?[]const u8).empty;
    errdefer {
        for (out.items) |param_type| {
            if (param_type) |name| allocator.free(name);
        }
        out.deinit(allocator);
    }

    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !is_top_level_comma_any(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            try out.append(allocator, try compact_type_name(allocator, tokens, seg_start, i));
        }
        seg_start = i + 1;
    }

    return out.toOwnedSlice(allocator);
}


pub fn parse_lambda_param_type_list(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ![]?[]const u8 {
    var out = std.ArrayList(?[]const u8).empty;
    errdefer out.deinit(allocator);

    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !is_top_level_comma_any(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            try out.append(allocator, lambda_param_type_name(tokens, seg_start, i));
        }
        seg_start = i + 1;
    }

    return out.toOwnedSlice(allocator);
}


pub fn lambda_param_type_name(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    if (start_idx + 1 >= end_idx) return null;
    return simple_type_name(tokens, start_idx + 1, end_idx);
}


pub fn lambda_body_start(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (is_arrow_at(tokens, start_idx)) return start_idx + 2;
    if (start_idx < end_idx and tok_eq(tokens[start_idx], "{")) return start_idx;
    if (start_idx >= end_idx or !is_return_arrow_at(tokens, start_idx)) return null;

    var i = start_idx + 2;
    var depth_angle: usize = 0;
    var depth_paren: usize = 0;
    while (i < end_idx) : (i += 1) {
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
        if (depth_angle == 0 and depth_paren == 0 and is_arrow_at(tokens, i)) return i + 2;
        if (depth_angle == 0 and depth_paren == 0 and tok_eq(tokens[i], "{")) return i;
    }
    return null;
}


pub fn is_visible_binding_or_callable_name(tokens: []const lexer.Token, name: []const u8, before_idx: usize) bool {
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
        if (i == before_idx) continue;
        if (tokens[i].kind != .ident) continue;
        if (is_keyword(tokens[i].lexeme)) continue;

        const public_name = public_func_name(tokens[i].lexeme);
        if (!std.mem.eql(u8, public_name, name)) continue;
        if (is_func_decl_start(tokens, i)) return true;
        if (is_modern_import_assign(tokens, i)) {
            const eq_idx = top_level_line_assign_idx(tokens, i) orelse continue;
            if (eq_idx + 2 >= tokens.len) continue;
            if (!tok_eq(tokens[eq_idx + 1], "@")) continue;
            if (tokens[eq_idx + 2].kind != .ident) continue;
            const import_kind = tokens[eq_idx + 2].lexeme;
            if (std.mem.eql(u8, import_kind, "host")) return true;
            if (std.mem.eql(u8, import_kind, "lib") and (is_lower_ident_name(public_name) or is_readonly_ident_name(tokens[i].lexeme))) return true;
            continue;
        }
        if (is_top_level_value_decl_start(tokens, i)) return true;
    }
    return false;
}


pub fn parse_import_decl_end(tokens: []const lexer.Token, start_idx: usize) ?usize {
    const eq_idx = top_level_line_assign_idx(tokens, start_idx) orelse return null;
    const at_idx = eq_idx + 1;
    if (at_idx + 2 >= tokens.len or !tok_eq(tokens[at_idx], "@")) return null;
    if (tokens[at_idx + 1].kind != .ident) return null;
    if (!tok_eq(tokens[at_idx + 2], "(")) return null;
    const close_paren = find_matching(tokens, at_idx + 2, "(", ")") catch return null;
    return close_paren + 1;
}


fn find_token_in_range(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, lexeme: []const u8) ?usize {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], lexeme)) return i;
    }
    return null;
}

/// When scanning top-level decls and hitting `{`, skip a whole import decl if present.
/// Returns the loop index to assign before `continue` (`next_idx - 1`), else null.
pub fn skip_top_level_import_brace(tokens: []const lexer.Token, i: usize, depth_brace: usize) ?usize {
    if (depth_brace != 0) return null;
    const next_idx = parse_import_decl_end(tokens, i) orelse return null;
    return next_idx - 1;
}


pub fn is_local_payload_enum_case(tokens: []const lexer.Token, name: []const u8) bool {
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
        if (is_modern_import_assign(tokens, i)) continue;
        if (!is_payload_enum_decl_start(tokens, i)) continue;
        if (enum_decl_has_branch(tokens, i, name)) return true;
    }
    return false;
}


pub fn is_imported_upper_alias(tokens: []const lexer.Token, name: []const u8) bool {
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
        if (!std.mem.eql(u8, tokens[i].lexeme, name)) continue;
        if (!is_valid_declared_type_name(tokens[i].lexeme)) continue;
        if (is_modern_import_assign(tokens, i)) return true;
    }
    return false;
}


pub fn collect_struct_infos(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]StructInfo {
    var out = std.ArrayList(StructInfo).empty;
    errdefer free_struct_infos(allocator, out.items);

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

        // Declarative: Name = @wasi_resource|wasi_record("…", { fields })
        if (i + 5 < tokens.len and tok_eq(tokens[i + 1], "=") and tok_eq(tokens[i + 2], "@") and
            tokens[i + 3].kind == .ident and
            (std.mem.eql(u8, tokens[i + 3].lexeme, "wasi_resource") or
                std.mem.eql(u8, tokens[i + 3].lexeme, "wasi_record")) and
            tok_eq(tokens[i + 4], "("))
        {
            const close_call = find_matching(tokens, i + 4, "(", ")") catch continue;
            const open_brace = find_token_in_range(tokens, i + 5, close_call, "{") orelse continue;
            const close_brace = find_matching(tokens, open_brace, "{", "}") catch continue;
            try out.append(allocator, .{
                .name = public_type_name(tokens[i].lexeme),
                .fields = try collect_struct_field_infos(allocator, tokens, open_brace + 1, close_brace),
            });
            i = close_call;
            continue;
        }

        // Classic: Name { fields }
        if (i + 1 >= tokens.len or !tok_eq(tokens[i + 1], "{")) continue;

        const close_idx = find_matching(tokens, i + 1, "{", "}") catch continue;
        try out.append(allocator, .{
            .name = public_type_name(tokens[i].lexeme),
            .fields = try collect_struct_field_infos(allocator, tokens, i + 2, close_idx),
        });
        i = close_idx;
    }

    return out.toOwnedSlice(allocator);
}


pub fn collect_struct_field_infos(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ![]StructFieldInfo {
    var out = std.ArrayList(StructFieldInfo).empty;
    errdefer {
        for (out.items) |field| {
            if (field.ty) |ty| allocator.free(ty);
        }
        out.deinit(allocator);
    }

    var i = start_idx;
    while (i < end_idx) {
        // Clamp to brace end so single-line `{ .id i64 }` does not pull `}` into the type span.
        const line_end = @min(find_line_end_idx(tokens, i), end_idx);
        if (tokens[i].kind == .ident and is_struct_field_name(tokens[i].lexeme)) {
            const type_end = find_struct_field_type_end(tokens, i + 1, line_end);
            {
                const ty = try compact_type_name(allocator, tokens, i + 1, type_end);
                errdefer if (ty) |owned| allocator.free(owned);
                try out.append(allocator, .{
                    .name = normalize_struct_field_name(tokens[i].lexeme),
                    .ty = ty,
                    .has_default = find_top_level_assign_eq_on_line(tokens, i, line_end) != null,
                });
            }
        }
        i = line_end;
    }

    return out.toOwnedSlice(allocator);
}


pub fn free_struct_infos(allocator: std.mem.Allocator, structs: []StructInfo) void {
    for (structs) |info| {
        for (info.fields) |field| {
            if (field.ty) |ty| allocator.free(ty);
        }
        allocator.free(info.fields);
    }
    allocator.free(structs);
}


pub fn local_struct_type_param_count(tokens: []const lexer.Token, name: []const u8) ?usize {
    var depth_brace: usize = 0;
    var in_constraint_block = false;
    var type_constraint_count: usize = 0;
    var last_constraint_line: usize = 0;

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

        if (!tok_eq(tokens[i], "#")) {
            const is_target_struct = tokens[i].kind == .ident and is_struct_decl_start(tokens, i) and
                std.mem.eql(u8, public_type_name(tokens[i].lexeme), name);
            if (is_target_struct and in_constraint_block and tokens[i].line == last_constraint_line + 1 and type_constraint_count > 0) {
                return type_constraint_count;
            }
            if (is_target_struct) return 0;
            if (in_constraint_block) {
                in_constraint_block = false;
                type_constraint_count = 0;
            }
            continue;
        }

        const line_end = find_line_end_idx(tokens, i);
        const is_func_constraint = (i + 2 < line_end and tok_eq(tokens[i + 2], "("));
        if (!is_func_constraint) type_constraint_count += 1;
        in_constraint_block = true;
        last_constraint_line = tokens[i].line;
        i = line_end - 1;
    }
    return null;
}


pub fn has_concrete_type_name(tokens: []const lexer.Token, name: []const u8) bool {
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
        if (is_modern_import_assign(tokens, i)) return true;
        if (is_type_decl_start(tokens, i)) return true;
    }
    return false;
}


