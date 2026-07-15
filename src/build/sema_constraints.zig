//! Semantic analysis — ctrl checks.
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema_error = @import("sema_error.zig");
const type_util = @import("type_name.zig");
const sema_tokens = @import("sema_tokens.zig");
const sema_shapes = @import("sema_shapes.zig");
const sema_function_support = @import("sema_function_support.zig");

const call_arg_info = sema_tokens.call_arg_info;
const call_arity_compatible_with_func = sema_tokens.call_arity_compatible_with_func;
const collect_func_shapes = sema_function_support.collect_func_shapes;
const collect_struct_infos = sema_function_support.collect_struct_infos;
const compact_token_range_equals = sema_tokens.compact_token_range_equals;
const find_inline_func_type_in_params = sema_tokens.find_inline_func_type_in_params;
const find_line_end_idx = sema_tokens.find_line_end_idx;
const find_matching = sema_tokens.find_matching;
const find_matching_in_range = sema_tokens.find_matching_in_range;
const find_nearest_value_type_name = sema_tokens.find_nearest_value_type_name;
const find_return_type_end = sema_tokens.find_return_type_end;
const find_struct_field_type_end = sema_tokens.find_struct_field_type_end;
const find_struct_info = sema_tokens.find_struct_info;
const find_top_level_assign_eq_on_line = sema_tokens.find_top_level_assign_eq_on_line;
const find_top_level_comma = sema_tokens.find_top_level_comma;
const free_call_arg_shapes = sema_function_support.free_call_arg_shapes;
const free_func_shapes = sema_function_support.free_func_shapes;
const free_struct_infos = sema_function_support.free_struct_infos;
const func_param_type_start = sema_tokens.func_param_type_start;
const has_concrete_type_name = sema_function_support.has_concrete_type_name;
const has_known_func_candidate = sema_tokens.has_known_func_candidate;
const has_local_struct_decl = sema_tokens.has_local_struct_decl;
const has_type_constraint_name = sema_tokens.has_type_constraint_name;
const is_arrow_at = sema_tokens.is_arrow_at;
const is_base_int_type_name = sema_tokens.is_base_int_type_name;
const is_builtin_special_or_core_name = sema_tokens.is_builtin_special_or_core_name;
const is_decl_only_name = sema_tokens.is_decl_only_name;
const is_func_decl_start = sema_tokens.is_func_decl_start;
const is_func_type_param = sema_tokens.is_func_type_param;
const is_func_type_range = sema_tokens.is_func_type_range;
const is_host_import_decl_start = sema_tokens.is_host_import_decl_start;
const is_imported_upper_alias = sema_function_support.is_imported_upper_alias;
const is_keyword = sema_tokens.is_keyword;
const is_lower_ident_name = sema_tokens.is_lower_ident_name;
const is_modern_import_assign = sema_tokens.is_modern_import_assign;
const is_non_assign_equal = sema_tokens.is_non_assign_equal;
const is_readonly_ident_name = sema_tokens.is_readonly_ident_name;
const is_reserved_func_name = sema_tokens.is_reserved_func_name;
const is_reserved_source_name = sema_tokens.is_reserved_source_name;
const is_return_arrow_at = sema_tokens.is_return_arrow_at;
const is_snake_lower_name = sema_tokens.is_snake_lower_name;
const is_struct_decl_start = sema_tokens.is_struct_decl_start;
const is_struct_field_decl_default = sema_tokens.is_struct_field_decl_default;
const is_struct_field_name = sema_tokens.is_struct_field_name;
const is_top_level_comma_any = sema_tokens.is_top_level_comma_any;
const is_top_level_decl_head = sema_tokens.is_top_level_decl_head;
const is_type_decl_start = sema_tokens.is_type_decl_start;
const is_valid_declared_type_name = sema_tokens.is_valid_declared_type_name;
const is_visible_binding_or_callable_name = sema_function_support.is_visible_binding_or_callable_name;
const line_start_idx = sema_tokens.line_start_idx;
const mark_error_at = sema_tokens.mark_error_at;
const parse_call_arg_shapes = sema_function_support.parse_call_arg_shapes;
const parse_import_decl_end = sema_function_support.parse_import_decl_end;
const skip_top_level_import_brace = sema_function_support.skip_top_level_import_brace;
const public_func_name = sema_tokens.public_func_name;
const public_type_name = sema_tokens.public_type_name;
const string_token_body = sema_tokens.string_token_body;
const tok_eq = sema_tokens.tok_eq;
const token_name_appears_in_range = sema_tokens.token_name_appears_in_range;
const top_level_line_assign_idx = sema_tokens.top_level_line_assign_idx;
const type_constraint_is_function_type = sema_tokens.type_constraint_is_function_type;
const CallArgInfo = sema_shapes.CallArgInfo;
const FuncParamShape = sema_shapes.FuncParamShape;
const FuncShape = sema_shapes.FuncShape;
const StructInfo = sema_shapes.StructInfo;


const find_loop_block_open = sema_tokens.find_loop_block_open;
const find_loop_bind_assign = sema_tokens.find_loop_bind_assign;
const is_valid_local_binding_name = sema_tokens.is_valid_local_binding_name;

pub fn check_constraint_layout(tokens: []const lexer.Token) !void {
    var depth_brace: usize = 0;
    var in_constraint_block = false;
    var saw_type_constraint = false;
    var saw_func_type_constraint = false;
    var saw_func_constraint = false;
    var last_constraint_line: usize = 0;
    var constraint_block_start: ?usize = null;

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
            if (in_constraint_block) {
                try validate_constraint_block_follower(tokens, i, last_constraint_line, saw_func_type_constraint, saw_func_constraint, constraint_block_start.?);
                in_constraint_block = false;
                saw_type_constraint = false;
                saw_func_type_constraint = false;
                saw_func_constraint = false;
                constraint_block_start = null;
            }
            continue;
        }

        const line = tokens[i].line;
        const line_end = find_line_end_idx(tokens, i);
        if (i + 1 >= line_end or tokens[i + 1].kind != .ident) {
            return mark_error_at(tokens, i, error.InvalidConstraintDecl);
        }

        var depth_paren: usize = 0;
        var depth_angle: usize = 0;
        var j = i + 1;
        while (j < line_end) : (j += 1) {
            if (tok_eq(tokens[j], "(")) {
                depth_paren += 1;
                continue;
            }
            if (tok_eq(tokens[j], ")")) {
                if (depth_paren > 0) depth_paren -= 1;
                continue;
            }
            if (tok_eq(tokens[j], "<")) {
                depth_angle += 1;
                continue;
            }
            if (tok_eq(tokens[j], ">")) {
                if (depth_angle > 0) depth_angle -= 1;
                continue;
            }
            if (depth_paren != 0 or depth_angle != 0) continue;
            if (tok_eq(tokens[j], "#")) return mark_error_at(tokens, j, error.InvalidConstraintDecl);
            if (tokens[j].kind == .ident and j > i + 1 and j + 1 < line_end and tok_eq(tokens[j + 1], "(")) {
                return mark_error_at(tokens, j, error.InvalidConstraintDecl);
            }
        }

        const eq_idx = find_top_level_assign_eq_on_line(tokens, i + 2, line_end);
        const is_func_type_constraint = eq_idx != null;
        const is_func_constraint = (!is_func_type_constraint and i + 2 < line_end and tok_eq(tokens[i + 2], "("));
        const is_type_constraint = !is_func_type_constraint and !is_func_constraint;

        if (!is_func_constraint and !is_valid_declared_type_name(tokens[i + 1].lexeme)) {
            return mark_error_at(tokens, i + 1, error.InvalidConstraintDecl);
        }
        if (is_type_constraint and line_end != i + 2) {
            return mark_error_at(tokens, i, error.InvalidConstraintDecl);
        }
        if (is_func_type_constraint) {
            const assign_idx = eq_idx.?;
            if (assign_idx != i + 2) return mark_error_at(tokens, i, error.InvalidConstraintDecl);
            if (!is_func_type_range(tokens, assign_idx + 1, line_end)) {
                return mark_error_at(tokens, assign_idx + 1, error.InvalidConstraintDecl);
            }
        }
        if (is_func_constraint and !is_allowed_constraint_func_name(tokens[i + 1].lexeme)) {
            return mark_error_at(tokens, i + 1, error.InvalidConstraintDecl);
        }
        if (is_type_constraint and (saw_func_type_constraint or saw_func_constraint)) {
            return mark_error_at(tokens, i, error.InvalidConstraintDecl);
        }
        if (is_func_type_constraint and saw_func_constraint) {
            return mark_error_at(tokens, i, error.InvalidConstraintDecl);
        }
        if (is_func_constraint and !saw_type_constraint) {
            return mark_error_at(tokens, i, error.InvalidConstraintDecl);
        }
        const block_start = constraint_block_start orelse i;
        if (constraint_block_start == null) constraint_block_start = i;
        if (!is_func_constraint and has_concrete_type_name(tokens, public_type_name(tokens[i + 1].lexeme))) {
            return mark_error_at(tokens, i + 1, error.InvalidConstraintDecl);
        }
        if (!is_func_constraint and has_duplicate_type_constraint_name(tokens, block_start, i, tokens[i + 1].lexeme)) {
            return mark_error_at(tokens, i + 1, error.InvalidConstraintDecl);
        }
        if (is_func_type_constraint) {
            if (find_implicit_type_param_in_type_constraint(tokens, block_start, i, line_end)) |name_idx| {
                return mark_error_at(tokens, name_idx, error.InvalidConstraintDecl);
            }
        }
        if (is_type_constraint) {
            if (find_implicit_type_param_in_type_constraint(tokens, block_start, i, line_end)) |name_idx| {
                return mark_error_at(tokens, name_idx, error.InvalidConstraintDecl);
            }
        }
        if (is_func_constraint and has_duplicate_func_constraint_signature(tokens, block_start, i, line_end)) {
            return mark_error_at(tokens, i + 1, error.InvalidConstraintDecl);
        }
        if (is_func_constraint) {
            if (find_implicit_type_param_in_func_constraint(tokens, block_start, i, line_end)) |name_idx| {
                return mark_error_at(tokens, name_idx, error.InvalidConstraintDecl);
            }
        }
        if (is_type_constraint) saw_type_constraint = true;
        if (is_func_type_constraint) saw_func_type_constraint = true;
        if (is_func_constraint) saw_func_constraint = true;

        in_constraint_block = true;
        last_constraint_line = line;
        i = line_end - 1;
    }
}


fn has_duplicate_type_constraint_name(
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


fn has_duplicate_func_constraint_signature(
    tokens: []const lexer.Token,
    block_start: usize,
    current_idx: usize,
    current_line_end: usize,
) bool {
    var i = block_start;
    while (i < current_idx) {
        if (!tok_eq(tokens[i], "#")) {
            i += 1;
            continue;
        }
        const line_end = find_line_end_idx(tokens, i);
        const is_func_constraint = (i + 2 < line_end and tok_eq(tokens[i + 2], "("));
        if (is_func_constraint and
            std.mem.eql(u8, tokens[i + 1].lexeme, tokens[current_idx + 1].lexeme) and
            func_constraint_params_equal(tokens, i, line_end, current_idx, current_line_end))
        {
            return true;
        }
        i = line_end;
    }
    return false;
}


fn func_constraint_params_equal(
    tokens: []const lexer.Token,
    a_idx: usize,
    a_line_end: usize,
    b_idx: usize,
    b_line_end: usize,
) bool {
    const a_open = a_idx + 2;
    const b_open = b_idx + 2;
    if (a_open >= a_line_end or b_open >= b_line_end) return false;
    const a_close = find_matching(tokens, a_open, "(", ")") catch return false;
    const b_close = find_matching(tokens, b_open, "(", ")") catch return false;
    if (a_close > a_line_end or b_close > b_line_end) return false;
    return token_ranges_equal(tokens, a_open + 1, a_close, b_open + 1, b_close);
}


fn find_implicit_type_param_in_type_constraint(
    tokens: []const lexer.Token,
    block_start: usize,
    constraint_idx: usize,
    line_end: usize,
) ?usize {
    const eq_idx = find_top_level_assign_eq_on_line(tokens, constraint_idx + 2, line_end) orelse return null;
    var i = eq_idx + 1;
    while (i < line_end) : (i += 1) {
        if (!is_valid_declared_type_name(tokens[i].lexeme)) continue;
        const name = public_type_name(tokens[i].lexeme);
        if (has_type_constraint_name(tokens, block_start, constraint_idx, name)) continue;
        if (has_concrete_type_name(tokens, name)) continue;
        return i;
    }
    return null;
}


fn find_implicit_type_param_in_func_constraint(
    tokens: []const lexer.Token,
    block_start: usize,
    constraint_idx: usize,
    line_end: usize,
) ?usize {
    var i = constraint_idx + 2;
    while (i < line_end) : (i += 1) {
        if (!is_valid_declared_type_name(tokens[i].lexeme)) continue;
        const name = public_type_name(tokens[i].lexeme);
        if (has_type_constraint_name(tokens, block_start, constraint_idx, name)) continue;
        if (has_concrete_type_name(tokens, name)) continue;
        return i;
    }
    return null;
}


fn token_ranges_equal(
    tokens: []const lexer.Token,
    a_start: usize,
    a_end: usize,
    b_start: usize,
    b_end: usize,
) bool {
    if (a_end - a_start != b_end - b_start) return false;
    var offset: usize = 0;
    while (offset < a_end - a_start) : (offset += 1) {
        if (!std.mem.eql(u8, tokens[a_start + offset].lexeme, tokens[b_start + offset].lexeme)) return false;
    }
    return true;
}


fn find_unused_type_constraint_in_func_params(
    tokens: []const lexer.Token,
    block_start: usize,
    before_idx: usize,
    param_start: usize,
    param_end: usize,
) ?usize {
    var i = block_start;
    while (i < before_idx) {
        if (!tok_eq(tokens[i], "#")) {
            i += 1;
            continue;
        }
        const line_end = find_line_end_idx(tokens, i);
        const is_func_constraint = (i + 2 < line_end and tok_eq(tokens[i + 2], "("));
        if (!is_func_constraint and i + 1 < line_end) {
            const name = tokens[i + 1].lexeme;
            if (!token_name_appears_in_range(tokens, param_start, param_end, name) and
                !type_constraint_feeds_func_param(tokens, block_start, before_idx, param_start, param_end, name) and
                !func_return_type_contains_name(tokens, before_idx, param_end, name))
            {
                return i + 1;
            }
        }
        i = line_end;
    }
    return null;
}


fn type_constraint_feeds_func_param(
    tokens: []const lexer.Token,
    block_start: usize,
    before_idx: usize,
    param_start: usize,
    param_end: usize,
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
        if (is_func_constraint or i + 1 >= line_end) {
            i = line_end;
            continue;
        }

        const carrier = tokens[i + 1].lexeme;
        if (token_name_appears_in_range(tokens, param_start, param_end, carrier) and
            token_name_appears_in_range(tokens, i + 2, line_end, name))
        {
            return true;
        }
        i = line_end;
    }
    return false;
}


fn func_return_type_contains_name(
    tokens: []const lexer.Token,
    func_start_idx: usize,
    close_params_idx: usize,
    name: []const u8,
) bool {
    _ = func_start_idx;
    var return_start = close_params_idx + 1;
    if (return_start >= tokens.len) return false;
    if (is_return_arrow_at(tokens, return_start)) return_start += 2;
    if (return_start >= tokens.len) return false;
    if (tok_eq(tokens[return_start], "{") or is_arrow_at(tokens, return_start)) return false;

    const return_end = find_return_type_end(tokens, return_start);
    return token_name_appears_in_range(tokens, return_start, return_end, name);
}


fn find_unused_type_constraint_in_struct_fields(
    tokens: []const lexer.Token,
    block_start: usize,
    before_idx: usize,
    field_start: usize,
    field_end: usize,
) ?usize {
    var i = block_start;
    while (i < before_idx) {
        if (!tok_eq(tokens[i], "#")) {
            i += 1;
            continue;
        }
        const line_end = find_line_end_idx(tokens, i);
        const is_func_constraint = (i + 2 < line_end and tok_eq(tokens[i + 2], "("));
        if (!is_func_constraint and i + 1 < line_end) {
            const name = tokens[i + 1].lexeme;
            if (!struct_field_type_contains_name(tokens, field_start, field_end, name)) return i + 1;
        }
        i = line_end;
    }
    return null;
}


fn struct_field_type_contains_name(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    name: []const u8,
) bool {
    var i = start_idx;
    while (i < end_idx) {
        const line_end = find_line_end_idx(tokens, i);
        if (tokens[i].kind != .ident or !is_struct_field_name(tokens[i].lexeme) or i + 1 >= line_end) {
            i = line_end;
            continue;
        }

        const type_end = find_struct_field_type_end(tokens, i + 1, line_end);
        if (token_name_appears_in_range(tokens, i + 1, type_end, name)) return true;
        i = line_end;
    }
    return false;
}



const Scope = struct {
    names: std.ArrayListUnmanaged([]const u8) = .empty,
    loop_bindings: std.ArrayListUnmanaged([]const u8) = .empty,

    fn deinit(self: *Scope, allocator: std.mem.Allocator) void {
        self.names.deinit(allocator);
        self.loop_bindings.deinit(allocator);
    }

    fn contains(self: *const Scope, name: []const u8) bool {
        for (self.names.items) |it| {
            if (std.mem.eql(u8, it, name)) return true;
        }
        return false;
    }

    fn contains_loop_binding(self: *const Scope, name: []const u8) bool {
        for (self.loop_bindings.items) |it| {
            if (std.mem.eql(u8, it, name)) return true;
        }
        return false;
    }
};

fn scopes_contain(scopes: []const Scope, name: []const u8) bool {
    for (scopes) |scope| {
        if (scope.contains(name)) return true;
    }
    return false;
}

fn scopes_contain_loop_binding(scopes: []const Scope, name: []const u8) bool {
    for (scopes) |scope| {
        if (scope.contains_loop_binding(name)) return true;
    }
    return false;
}

pub fn check_assignment_constraints(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
    var scopes: std.ArrayListUnmanaged(Scope) = .empty;
    defer {
        for (scopes.items) |*scope| scope.deinit(allocator);
        scopes.deinit(allocator);
    }

    try scopes.append(allocator, .{});

    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            var scope: Scope = .{};
            errdefer scope.deinit(allocator);
            if (loop_header_for_body_open(tokens, i)) |loop_idx| {
                try append_loop_body_bindings(allocator, &scope, tokens, loop_idx, i, scopes.items);
            }
            try scopes.append(allocator, scope);
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (scopes.items.len <= 1) return mark_error_at(tokens, i, error.UnbalancedScope);
            var popped = scopes.pop().?;
            popped.deinit(allocator);
            continue;
        }
        if (!tok_eq(tokens[i], "=")) continue;
        if (is_non_assign_equal(tokens, i)) continue;

        var line_start = i;
        while (line_start > 0 and tokens[line_start - 1].line == tokens[i].line) {
            line_start -= 1;
        }
        const line_end = find_line_end_idx(tokens, i);
        const stmt_eq_idx = find_top_level_assign_eq_on_line(tokens, line_start, line_end) orelse continue;
        if (stmt_eq_idx != i) continue;
        const is_top_level = scopes.items.len == 1;

        if (tok_eq(tokens[line_start], "#")) {
            continue;
        }
        if (is_top_level and is_modern_import_assign(tokens, line_start)) {
            continue;
        }

        if (line_start < i and tokens[line_start].kind == .ident and tokens[line_start].lexeme.len > 0 and tokens[line_start].lexeme[0] == '.') {
            if (is_top_level and is_top_level_decl_head(tokens, line_start) and is_type_decl_start(tokens, line_start)) {
                continue;
            }
            if (!is_struct_field_decl_default(tokens, line_start, i)) {
                return mark_error_at(tokens, line_start, error.PrivateIdentCannotBeLValue);
            }
        }
        if (is_top_level and line_start + 1 <= i and is_top_level_decl_head(tokens, line_start) and is_type_decl_start(tokens, line_start)) {
            continue;
        }
        if (is_struct_field_decl_default(tokens, line_start, i)) {
            continue;
        }
        if (tok_eq(tokens[line_start], "loop")) {
            continue;
        }

        try validate_assignment_lhs_names(tokens, line_start, stmt_eq_idx);
        try register_single_lhs_binding(allocator, tokens, line_start, stmt_eq_idx, &scopes);

        var k = line_start;
        while (k < i) : (k += 1) {
            const t = tokens[k];
            if (t.kind != .ident) continue;
            if (t.lexeme.len == 0) continue;

            if (t.lexeme[0] == '.') return mark_error_at(tokens, k, error.PrivateIdentCannotBeLValue);
            if (scopes_contain_loop_binding(scopes.items, t.lexeme)) return mark_error_at(tokens, k, error.InvalidAssignExpr);
            if (k == line_start and t.lexeme[0] != '_') continue;
            if (std.mem.eql(u8, t.lexeme, "_")) continue;

            if (t.lexeme[0] == '_') {
                if (scopes_contain(scopes.items, t.lexeme)) return mark_error_at(tokens, k, error.DuplicateImmutableBinding);
                var current = &scopes.items[scopes.items.len - 1];
                try current.names.append(allocator, t.lexeme);
            }
        }
    }
}


fn register_single_lhs_binding(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    line_start: usize,
    stmt_eq_idx: usize,
    scopes: *std.ArrayList(Scope),
) !void {
    if (find_top_level_comma(tokens, line_start, stmt_eq_idx) != null) return;
    const lhs_name = tokens[line_start].lexeme;
    if (lhs_name.len == 0 or lhs_name[0] == '.' or lhs_name[0] == '_') return;
    if (is_single_local_value_decl(tokens, line_start, stmt_eq_idx)) {
        if (scopes_contain(scopes.items, lhs_name)) return mark_error_at(tokens, line_start, error.DuplicateLocalBinding);
        var current = &scopes.items[scopes.items.len - 1];
        try current.names.append(allocator, lhs_name);
        return;
    }
    if (scopes_contain(scopes.items, lhs_name)) return;
    var current = &scopes.items[scopes.items.len - 1];
    try current.names.append(allocator, lhs_name);
}

fn validate_constraint_following_decl(
    tokens: []const lexer.Token,
    i: usize,
    constraint_block_start: usize,
) !void {
    if (is_func_decl_start(tokens, i)) {
        const close_paren = find_matching(tokens, i + 1, "(", ")") catch
            return mark_error_at(tokens, i, error.InvalidConstraintDecl);
        if (find_inline_func_type_in_params(tokens, i + 2, close_paren)) |name_idx| {
            return mark_error_at(tokens, name_idx, error.InvalidConstraintDecl);
        }
        if (find_unused_type_constraint_in_func_params(tokens, constraint_block_start, i, i + 2, close_paren)) |name_idx| {
            return mark_error_at(tokens, name_idx, error.InvalidConstraintDecl);
        }
        return;
    }
    if (!is_struct_decl_start(tokens, i)) return;
    const close_brace = find_matching(tokens, i + 1, "{", "}") catch
        return mark_error_at(tokens, i, error.InvalidConstraintDecl);
    if (find_unused_type_constraint_in_struct_fields(tokens, constraint_block_start, i, i + 2, close_brace)) |name_idx| {
        return mark_error_at(tokens, name_idx, error.InvalidConstraintDecl);
    }
}

fn validate_constraint_block_follower(
    tokens: []const lexer.Token,
    i: usize,
    last_constraint_line: usize,
    saw_func_type_constraint: bool,
    saw_func_constraint: bool,
    constraint_block_start: usize,
) !void {
    if (tokens[i].line != last_constraint_line + 1) {
        return mark_error_at(tokens, i, error.InvalidConstraintDecl);
    }
    if ((saw_func_type_constraint or saw_func_constraint) and !is_func_decl_start(tokens, i)) {
        return mark_error_at(tokens, i, error.InvalidConstraintDecl);
    }
    if (!is_func_decl_start(tokens, i) and !is_struct_decl_start(tokens, i)) {
        return mark_error_at(tokens, i, error.InvalidConstraintDecl);
    }
    try validate_constraint_following_decl(tokens, i, constraint_block_start);
}

fn is_single_local_value_decl(tokens: []const lexer.Token, start_idx: usize, eq_idx: usize) bool {
    if (tokens[start_idx].kind != .ident) return false;
    return eq_idx > start_idx + 1;
}


fn loop_header_for_body_open(tokens: []const lexer.Token, open_idx: usize) ?usize {
    var i = open_idx;
    while (i > 0) {
        i -= 1;
        if (!tok_eq(tokens[i], "loop")) continue;
        const body_open = find_loop_block_open(tokens, i) orelse continue;
        if (body_open == open_idx) return i;
    }
    return null;
}


fn append_loop_body_bindings(
    allocator: std.mem.Allocator,
    scope: *Scope,
    tokens: []const lexer.Token,
    loop_idx: usize,
    open_idx: usize,
    outer_scopes: []const Scope,
) !void {
    const header_start = loop_idx + 1;
    if (header_start == open_idx) return;

    const bind_idx = find_loop_bind_assign(tokens, header_start, open_idx) orelse
        return mark_error_at(tokens, loop_idx, error.InvalidLoopHeader);
    try append_loop_binding_name(allocator, scope, tokens, header_start, outer_scopes);

    if (header_start + 3 == bind_idx) {
        try append_loop_binding_name(allocator, scope, tokens, header_start + 2, outer_scopes);
    }
}


fn append_loop_binding_name(
    allocator: std.mem.Allocator,
    scope: *Scope,
    tokens: []const lexer.Token,
    idx: usize,
    outer_scopes: []const Scope,
) !void {
    const name = tokens[idx].lexeme;
    if (std.mem.eql(u8, name, "_")) return;
    if (scope.contains_loop_binding(name) or scopes_contain(outer_scopes, name) or scopes_contain_loop_binding(outer_scopes, name)) {
        return mark_error_at(tokens, idx, error.InvalidLoopHeader);
    }
    if (is_visible_binding_or_callable_name(tokens, name, idx)) return mark_error_at(tokens, idx, error.InvalidLoopHeader);
    try scope.loop_bindings.append(allocator, name);
}
fn validate_assignment_lhs_names(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) !void {
    var expect_name = true;
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

        const at_top_level = depth_paren == 0 and depth_bracket == 0 and depth_angle == 0;
        if (!expect_name) {
            if (at_top_level and tok_eq(tokens[i], ",")) expect_name = true;
            continue;
        }

        const t = tokens[i];
        if (t.kind != .ident) continue;
        if (t.lexeme.len == 0) continue;
        if (t.lexeme[0] == '.') return mark_error_at(tokens, i, error.PrivateIdentCannotBeLValue);
        if (std.mem.eql(u8, t.lexeme, "_")) {
            expect_name = false;
            continue;
        }
        if (!is_valid_local_binding_name(t.lexeme)) return mark_error_at(tokens, i, error.InvalidBindingName);
        expect_name = false;
    }
}


fn is_allowed_constraint_func_name(name: []const u8) bool {
    if (!is_lower_ident_name(name)) return false;
    if (is_decl_only_name(name)) return false;
    if (is_builtin_special_or_core_name(name)) return false;
    if (is_reserved_source_name(name)) return false;
    return !is_keyword(name);
}
