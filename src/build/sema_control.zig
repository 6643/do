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

    fn containsLoopBinding(self: *const Scope, name: []const u8) bool {
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
        if (scope.containsLoopBinding(name)) return true;
    }
    return false;
}


const ArgRange = struct {
    start: usize,
    end: usize,
};

const FieldMetaBinding = struct {
    name: []const u8,
    struct_name: []const u8,
    body_depth: usize,
};

pub fn check_defer_stmts(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
) !void {
    const funcs = try collect_func_shapes(allocator, tokens);
    defer free_func_shapes(allocator, funcs);

    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tok_eq(tokens[i], "defer")) continue;
        const body_idx = i + 1;
        if (body_idx >= tokens.len) return mark_error_at(tokens, i, error.NoMatchingCall);
        if (tok_eq(tokens[body_idx], "{")) {
            const close_block = find_matching(tokens, body_idx, "{", "}") catch return mark_error_at(tokens, body_idx, error.NoMatchingCall);
            try check_defer_block_no_control_flow(tokens, body_idx + 1, close_block);
            i = close_block;
            continue;
        }
        try check_defer_call_stmt(allocator, funcs, tokens, body_idx);
    }
}


fn check_defer_block_no_control_flow(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) !void {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "return") or tok_eq(tokens[i], "break") or tok_eq(tokens[i], "continue")) {
            return mark_error_at(tokens, i, error.NoMatchingCall);
        }
    }
}


fn check_defer_call_stmt(
    allocator: std.mem.Allocator,
    funcs: []const FuncShape,
    tokens: []const lexer.Token,
    call_idx: usize,
) !void {
    if (tok_eq(tokens[call_idx], "@")) return mark_error_at(tokens, call_idx, error.NoMatchingCall);
    if (tokens[call_idx].kind != .ident) return mark_error_at(tokens, call_idx, error.NoMatchingCall);
    if (call_idx + 1 >= tokens.len or !tok_eq(tokens[call_idx + 1], "(")) return mark_error_at(tokens, call_idx, error.NoMatchingCall);

    const line_end = find_line_end_idx(tokens, call_idx);
    const close_paren = find_matching(tokens, call_idx + 1, "(", ")") catch return mark_error_at(tokens, call_idx, error.NoMatchingCall);
    if (close_paren + 1 != line_end) return mark_error_at(tokens, call_idx, error.NoMatchingCall);

    const args = try parse_call_arg_shapes(allocator, tokens, call_idx + 2, close_paren);
    defer free_call_arg_shapes(allocator, args);

    const name = tokens[call_idx].lexeme;
    var saw_func_candidate = false;
    for (funcs) |func| {
        if (!std.mem.eql(u8, func.name, name)) continue;
        if (!call_arity_compatible_with_func(func, args.len)) continue;
        saw_func_candidate = true;
        if (func_return_is_nil(func.return_type)) return;
    }
    if (saw_func_candidate) return mark_error_at(tokens, call_idx, error.NoMatchingCall);

    if (host_import_return_is_nil(tokens, name)) |is_nil| {
        if (is_nil) return;
        return mark_error_at(tokens, call_idx, error.NoMatchingCall);
    }
}


fn func_return_is_nil(return_type: ?[]const u8) bool {
    const ty = return_type orelse return true;
    return std.mem.eql(u8, ty, "nil");
}


fn host_import_return_is_nil(tokens: []const lexer.Token, name: []const u8) ?bool {
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
        if (!std.mem.eql(u8, public_func_name(tokens[i].lexeme), name)) continue;
        if (!is_host_import_decl_start(tokens, i)) continue;

        const eq_idx = top_level_line_assign_idx(tokens, i) orelse return null;
        const at_idx = eq_idx + 1;
        const import_end = parse_import_decl_end(tokens, i) orelse return null;
        const comma_idx = find_top_level_comma(tokens, at_idx + 4, import_end - 1) orelse return null;
        const sig_start = comma_idx + 1;
        if (sig_start >= import_end or !tok_eq(tokens[sig_start], "(")) return null;
        const close_params = find_matching(tokens, sig_start, "(", ")") catch return null;
        if (!is_return_arrow_at(tokens, close_params + 1)) return null;

        const return_start = close_params + 3;
        const return_end = import_end - 1;
        return return_start + 1 == return_end and tok_eq(tokens[return_start], "nil");
    }
    return null;
}


fn is_valid_local_binding_name(name: []const u8) bool {
    return (is_lower_ident_name(name) or is_readonly_ident_name(name)) and !is_reserved_func_name(name);
}


fn is_valid_loop_binding_name(name: []const u8) bool {
    return std.mem.eql(u8, name, "_") or (is_lower_ident_name(name) and !is_reserved_func_name(name));
}


fn is_base_float_type_name(name: []const u8) bool {
    return std.mem.eql(u8, name, "f32") or std.mem.eql(u8, name, "f64");
}


pub fn check_loop_header(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            if (parse_import_decl_end(tokens, i)) |next_idx| {
                i = next_idx - 1;
                continue;
            }
        }

        if (!tok_eq(tokens[i], "loop")) continue;
        const open_brace = find_loop_block_open(tokens, i) orelse return mark_error_at(tokens, i, error.InvalidLoopHeader);
        if (open_brace <= i) return mark_error_at(tokens, i, error.InvalidLoopHeader);

        const header_start = i + 1;
        if (open_brace == header_start) {
            i = open_brace;
            continue; // loop { ... }
        }

        const bind = find_loop_bind_assign(tokens, header_start, open_brace) orelse
            return mark_error_at(tokens, header_start, error.InvalidLoopHeader);

        try validate_loop_bind_lhs(tokens, header_start, bind);
        if (bind + 1 >= open_brace) return mark_error_at(tokens, bind, error.InvalidLoopHeader);
        try check_loop_source(tokens, header_start, bind, open_brace);
        i = open_brace;
    }
}


const LoopLabelDecl = struct {
    loop_line: usize,
    name: []const u8,
};

const PendingLoopLabel = struct {
    open_idx: usize,
    name: []const u8,
};

const ActiveLoopLabel = struct {
    name: []const u8,
    body_depth: usize,
};

const ActiveLoop = struct {
    body_depth: usize,
};



/// Pass 1: collect `#label` immediately followed by `loop` (label decls only).
fn collect_loop_label_decls(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    out: *std.ArrayList(LoopLabelDecl),
) !void {
    var brace_depth: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) {
        const line_start = i;
        const line_no = tokens[i].line;
        const line_end = find_line_end_idx(tokens, i);

        if (brace_depth > 0 and tok_eq(tokens[line_start], "#")) {
            if (line_start + 1 >= line_end or tokens[line_start + 1].kind != .ident) {
                return mark_error_at(tokens, line_start, error.InvalidLoopHeader);
            }
            if (!is_valid_loop_label_name(tokens[line_start + 1].lexeme)) {
                return mark_error_at(tokens, line_start + 1, error.InvalidLoopHeader);
            }
            const next_line_start = line_end;
            if (next_line_start >= tokens.len or tokens[next_line_start].line != line_no + 1) {
                return mark_error_at(tokens, line_start, error.InvalidLoopHeader);
            }
            if (!tok_eq(tokens[next_line_start], "loop")) {
                return mark_error_at(tokens, next_line_start, error.InvalidLoopHeader);
            }
            try out.append(allocator, .{
                .loop_line = tokens[next_line_start].line,
                .name = tokens[line_start + 1].lexeme,
            });
        }

        var j = line_start;
        while (j < line_end) : (j += 1) {
            if (tok_eq(tokens[j], "{")) {
                brace_depth += 1;
                continue;
            }
            if (tok_eq(tokens[j], "}") and brace_depth > 0) brace_depth -= 1;
        }
        i = line_end;
    }
}

/// Register a `loop` keyword: queue its body open-brace (and optional label).
fn register_pending_loop(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    loop_idx: usize,
    label_decls: []const LoopLabelDecl,
    pending_loop_opens: *std.ArrayList(usize),
    pending_loops: *std.ArrayList(PendingLoopLabel),
) !void {
    const open_idx = find_loop_block_open(tokens, loop_idx) orelse {
        return mark_error_at(tokens, loop_idx, error.InvalidLoopHeader);
    };
    try pending_loop_opens.append(allocator, open_idx);
    const label_name = label_decl_for_line(label_decls, tokens[loop_idx].line) orelse return;
    try pending_loops.append(allocator, .{ .open_idx = open_idx, .name = label_name });
}

/// When `{` is reached: activate any pending loop/label whose body opens here.
fn activate_pending_loop_body(
    allocator: std.mem.Allocator,
    open_idx: usize,
    brace_depth: usize,
    pending_loop_opens: *std.ArrayList(usize),
    pending_loops: *std.ArrayList(PendingLoopLabel),
    active_loops: *std.ArrayList(ActiveLoop),
    active_labels: *std.ArrayList(ActiveLoopLabel),
) !void {
    if (pending_loop_opens.items.len > 0 and
        pending_loop_opens.items[pending_loop_opens.items.len - 1] == open_idx)
    {
        _ = pending_loop_opens.pop();
        try active_loops.append(allocator, .{ .body_depth = brace_depth });
    }
    if (pending_loops.items.len == 0) return;
    if (pending_loops.items[pending_loops.items.len - 1].open_idx != open_idx) return;
    const pending = pending_loops.pop().?;
    try active_labels.append(allocator, .{
        .name = pending.name,
        .body_depth = brace_depth,
    });
}

/// After `}`: drop active loops/labels whose body depth is no longer live.
fn pop_active_loops_past_depth(
    brace_depth: usize,
    active_loops: *std.ArrayList(ActiveLoop),
    active_labels: *std.ArrayList(ActiveLoopLabel),
) void {
    while (active_loops.items.len > 0 and
        active_loops.items[active_loops.items.len - 1].body_depth > brace_depth)
    {
        _ = active_loops.pop();
    }
    while (active_labels.items.len > 0 and
        active_labels.items[active_labels.items.len - 1].body_depth > brace_depth)
    {
        _ = active_labels.pop();
    }
}

/// Pass 2: walk tokens, track active loop/label stack, validate break/continue.
fn check_loop_label_stack(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    label_decls: []const LoopLabelDecl,
) !void {
    var pending_loops = try std.ArrayList(PendingLoopLabel).initCapacity(allocator, 0);
    defer pending_loops.deinit(allocator);
    var pending_loop_opens = try std.ArrayList(usize).initCapacity(allocator, 0);
    defer pending_loop_opens.deinit(allocator);
    var active_loops = try std.ArrayList(ActiveLoop).initCapacity(allocator, 0);
    defer active_loops.deinit(allocator);
    var active_labels = try std.ArrayList(ActiveLoopLabel).initCapacity(allocator, 0);
    defer active_labels.deinit(allocator);

    var brace_depth: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) {
        const line_start = i;
        const line_end = find_line_end_idx(tokens, i);
        var j = line_start;
        while (j < line_end) : (j += 1) {
            if (tok_eq(tokens[j], "loop")) {
                try register_pending_loop(allocator, tokens, j, label_decls, &pending_loop_opens, &pending_loops);
            } else if (tok_eq(tokens[j], "break") or tok_eq(tokens[j], "continue")) {
                try validate_break_or_continue(tokens, j, line_end, active_loops.items.len, active_labels.items);
            } else if (tok_eq(tokens[j], "{")) {
                brace_depth += 1;
                try activate_pending_loop_body(
                    allocator,
                    j,
                    brace_depth,
                    &pending_loop_opens,
                    &pending_loops,
                    &active_loops,
                    &active_labels,
                );
            } else if (tok_eq(tokens[j], "}")) {
                if (brace_depth > 0) brace_depth -= 1;
                pop_active_loops_past_depth(brace_depth, &active_loops, &active_labels);
            }
        }
        i = line_end;
    }
}

pub fn check_loop_labels(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
    var label_decls = try std.ArrayList(LoopLabelDecl).initCapacity(allocator, 0);
    defer label_decls.deinit(allocator);
    try collect_loop_label_decls(allocator, tokens, &label_decls);
    try check_loop_label_stack(allocator, tokens, label_decls.items);
}


fn label_decl_for_line(decls: []const LoopLabelDecl, line: usize) ?[]const u8 {
    for (decls) |decl| {
        if (decl.loop_line == line) return decl.name;
    }
    return null;
}


fn validate_break_or_continue(
    tokens: []const lexer.Token,
    j: usize,
    line_end: usize,
    active_loop_count: usize,
    active_labels: []const ActiveLoopLabel,
) !void {
    if (active_loop_count == 0) return mark_error_at(tokens, j, error.InvalidLoopHeader);
    if (j + 1 >= line_end or !tok_eq(tokens[j + 1], "#")) return;
    if (j + 2 >= line_end or tokens[j + 2].kind != .ident) {
        return mark_error_at(tokens, j + 1, error.InvalidLoopHeader);
    }
    if (!is_valid_loop_label_name(tokens[j + 2].lexeme)) {
        return mark_error_at(tokens, j + 2, error.InvalidLoopHeader);
    }
    if (!label_is_active(active_labels, tokens[j + 2].lexeme)) {
        return mark_error_at(tokens, j + 1, error.InvalidLoopHeader);
    }
}

fn label_is_active(labels: []const ActiveLoopLabel, name: []const u8) bool {
    var idx = labels.len;
    while (idx > 0) {
        idx -= 1;
        if (std.mem.eql(u8, labels[idx].name, name)) return true;
    }
    return false;
}


fn is_valid_loop_label_name(name: []const u8) bool {
    return is_snake_lower_name(name) and !is_keyword(name);
}


fn check_loop_source(tokens: []const lexer.Token, header_start: usize, bind_idx: usize, open_brace: usize) !void {
    if (header_start + 1 == bind_idx) {
        if (!is_recv_loop_source(tokens, bind_idx + 1, open_brace) and !is_fields_loop_source(tokens, bind_idx + 1, open_brace)) {
            return mark_error_at(tokens, bind_idx + 1, error.InvalidLoopHeader);
        }
        return;
    }
    if (bind_idx + 1 >= open_brace) return mark_error_at(tokens, bind_idx, error.InvalidLoopHeader);
    if (tokens[bind_idx + 1].kind != .ident) return;

    const source_name = tokens[bind_idx + 1].lexeme;
    const source_type = find_nearest_value_type_name(tokens, bind_idx, source_name) orelse return;
    if (is_unsupported_direct_loop_source(source_type)) {
        return mark_error_at(tokens, bind_idx + 1, error.InvalidLoopSource);
    }
}


fn is_recv_loop_source(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 3 >= end_idx) return false;
    if (!tok_eq(tokens[start_idx], "recv")) return false;
    if (!tok_eq(tokens[start_idx + 1], "(")) return false;
    const close_idx = find_matching(tokens, start_idx + 1, "(", ")") catch return false;
    return close_idx + 1 == end_idx;
}


fn is_fields_loop_source(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 4 != end_idx) return false;
    if (tokens[start_idx].kind != .ident or !std.mem.eql(u8, tokens[start_idx].lexeme, "fields")) return false;
    if (!tok_eq(tokens[start_idx + 1], "(")) return false;
    if (tokens[start_idx + 2].kind != .ident) return false;
    if (!is_valid_declared_type_name(tokens[start_idx + 2].lexeme)) return false;
    return tok_eq(tokens[start_idx + 3], ")");
}


pub fn check_field_reflection(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
    const funcs = try collect_func_shapes(allocator, tokens);
    defer free_func_shapes(allocator, funcs);

    const structs = try collect_struct_infos(allocator, tokens);
    defer free_struct_infos(allocator, structs);

    var field_bindings = try std.ArrayList(FieldMetaBinding).initCapacity(allocator, 0);
    defer field_bindings.deinit(allocator);

    var pending_field_loop_opens = try std.ArrayList(FieldMetaBinding).initCapacity(allocator, 0);
    defer pending_field_loop_opens.deinit(allocator);

    var brace_depth: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "loop")) {
            if (try field_reflection_loop_binding(tokens, i)) |binding| {
                try pending_field_loop_opens.append(allocator, binding);
            }
        }

        if (tokens[i].kind == .ident and is_field_reflect_func_name(tokens[i].lexeme)) {
            try check_field_reflect_call(tokens, i, field_bindings.items);
            if (std.mem.eql(u8, tokens[i].lexeme, "field_get")) {
                try check_field_get_static_use(allocator, tokens, i, field_bindings.items, structs, funcs);
            } else if (std.mem.eql(u8, tokens[i].lexeme, "field_set")) {
                try check_field_set_static_use(allocator, tokens, i, field_bindings.items, structs, funcs);
            }
        }

        if (tokens[i].kind == .ident and is_active_field_meta_binding(field_bindings.items, tokens[i].lexeme) and
            !is_allowed_field_meta_use(tokens, i))
        {
            return mark_error_at(tokens, i, error.InvalidFieldReflection);
        }

        if (tok_eq(tokens[i], "{")) {
            brace_depth += 1;
            while (pending_field_loop_opens.items.len > 0) {
                const last = pending_field_loop_opens.items[pending_field_loop_opens.items.len - 1];
                if (last.body_depth != brace_depth) break;
                const binding = pending_field_loop_opens.pop().?;
                try field_bindings.append(allocator, binding);
            }
            continue;
        }

        if (tok_eq(tokens[i], "}")) {
            if (brace_depth > 0) brace_depth -= 1;
            while (field_bindings.items.len > 0 and field_bindings.items[field_bindings.items.len - 1].body_depth > brace_depth) {
                _ = field_bindings.pop();
            }
            continue;
        }
    }
}


fn is_active_field_meta_binding(field_bindings: []const FieldMetaBinding, name: []const u8) bool {
    return find_active_field_meta_binding(field_bindings, name) != null;
}


fn find_active_field_meta_binding(field_bindings: []const FieldMetaBinding, name: []const u8) ?FieldMetaBinding {
    for (field_bindings) |binding| {
        if (std.mem.eql(u8, binding.name, name)) return binding;
    }
    return null;
}


fn is_field_reflect_func_name(name: []const u8) bool {
    return std.mem.eql(u8, name, "field_name") or
        std.mem.eql(u8, name, "field_index") or
        std.mem.eql(u8, name, "field_has_default") or
        std.mem.eql(u8, name, "field_get") or
        std.mem.eql(u8, name, "field_set");
}


fn is_allowed_field_meta_use(tokens: []const lexer.Token, field_idx: usize) bool {
    var i = field_idx;
    while (i > 0) {
        i -= 1;
        if (!tok_eq(tokens[i], "@")) continue;
        if (i + 2 >= tokens.len) continue;
        if (tokens[i + 1].kind != .ident or !is_field_reflect_func_name(tokens[i + 1].lexeme)) continue;
        if (!tok_eq(tokens[i + 2], "(")) continue;

        const close_paren = find_matching(tokens, i + 2, "(", ")") catch return false;
        if (close_paren < field_idx) continue;
        const field_arg = field_reflect_field_arg_range(tokens, i + 1, close_paren) orelse return false;
        return field_arg.start == field_idx and field_arg.end == field_idx + 1;
    }
    return false;
}


fn field_reflection_loop_binding(tokens: []const lexer.Token, loop_idx: usize) !?FieldMetaBinding {
    const open_brace = find_loop_block_open(tokens, loop_idx) orelse return null;
    const bind_idx = find_loop_bind_assign(tokens, loop_idx + 1, open_brace) orelse return null;
    if (loop_idx + 2 != bind_idx) return null;
    if (tokens[loop_idx + 1].kind != .ident) return null;
    if (!is_fields_loop_source(tokens, bind_idx + 1, open_brace)) return null;

    const type_idx = bind_idx + 3;
    if (!field_reflection_source_type_allowed(tokens, loop_idx, type_idx)) {
        return mark_error_at(tokens, type_idx, error.InvalidFieldReflection);
    }

    return .{
        .name = tokens[loop_idx + 1].lexeme,
        .struct_name = public_type_name(tokens[type_idx].lexeme),
        .body_depth = brace_depth_before(tokens, open_brace) + 1,
    };
}


fn field_reflection_source_type_allowed(tokens: []const lexer.Token, loop_idx: usize, type_idx: usize) bool {
    const type_name = public_type_name(tokens[type_idx].lexeme);
    if (has_local_struct_decl(tokens, type_name)) return true;
    if (is_func_type_param_at(tokens, loop_idx, type_name)) return true;
    if (is_imported_upper_alias(tokens, type_name)) return true;
    return false;
}


fn is_func_type_param_at(tokens: []const lexer.Token, idx: usize, name: []const u8) bool {
    const func_start = find_enclosing_func_start(tokens, idx) orelse return false;
    return is_func_type_param(tokens, func_start, name);
}


fn find_enclosing_func_start(tokens: []const lexer.Token, idx: usize) ?usize {
    var skip_depth: usize = 0;
    var i = idx;
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

        const line_start = line_start_idx(tokens, i);
        if (line_start < i and is_func_decl_start(tokens, line_start)) return line_start;
    }
    return null;
}


fn check_field_reflect_call(tokens: []const lexer.Token, name_idx: usize, field_bindings: []const FieldMetaBinding) !void {
    if (name_idx == 0 or !tok_eq(tokens[name_idx - 1], "@")) return;
    if (name_idx + 1 >= tokens.len or !tok_eq(tokens[name_idx + 1], "(")) {
        return mark_error_at(tokens, name_idx, error.InvalidFieldReflection);
    }

    const close_paren = find_matching(tokens, name_idx + 1, "(", ")") catch
        return mark_error_at(tokens, name_idx + 1, error.InvalidFieldReflection);
    const field_arg = field_reflect_field_arg_range(tokens, name_idx, close_paren) orelse
        return mark_error_at(tokens, name_idx, error.InvalidFieldReflection);
    if (!is_field_meta_arg(tokens, field_arg, field_bindings)) {
        return mark_error_at(tokens, field_arg.start, error.InvalidFieldReflection);
    }
    if (std.mem.eql(u8, tokens[name_idx].lexeme, "field_set") and !is_field_set_self_assignment(tokens, name_idx, close_paren)) {
        return mark_error_at(tokens, name_idx, error.InvalidFieldReflection);
    }
}


fn field_reflect_field_arg_range(tokens: []const lexer.Token, name_idx: usize, close_paren: usize) ?ArgRange {
    if (std.mem.eql(u8, tokens[name_idx].lexeme, "field_name") or
        std.mem.eql(u8, tokens[name_idx].lexeme, "field_index") or
        std.mem.eql(u8, tokens[name_idx].lexeme, "field_has_default"))
    {
        return single_arg_range(tokens, name_idx + 2, close_paren);
    }

    if (std.mem.eql(u8, tokens[name_idx].lexeme, "field_get") or
        std.mem.eql(u8, tokens[name_idx].lexeme, "field_set"))
    {
        return nth_arg_range(tokens, name_idx + 2, close_paren, 1);
    }

    return null;
}


fn is_field_meta_arg(tokens: []const lexer.Token, arg: ArgRange, field_bindings: []const FieldMetaBinding) bool {
    if (arg.start + 1 != arg.end) return false;
    if (tokens[arg.start].kind != .ident) return false;
    for (field_bindings) |binding| {
        if (std.mem.eql(u8, binding.name, tokens[arg.start].lexeme)) return true;
    }
    return false;
}


fn is_field_set_self_assignment(tokens: []const lexer.Token, name_idx: usize, close_paren: usize) bool {
    const line_start = line_start_idx(tokens, name_idx);
    const line_end = find_line_end_idx(tokens, name_idx);
    if (close_paren + 1 != line_end) return false;
    const eq_idx = find_top_level_assign_eq_on_line(tokens, line_start, line_end) orelse return false;
    if (eq_idx + 1 != name_idx - 1) return false;
    if (line_start + 1 != eq_idx or tokens[line_start].kind != .ident) return false;

    const target_arg = nth_arg_range(tokens, name_idx + 2, close_paren, 0) orelse return false;
    if (target_arg.start + 1 != target_arg.end) return false;
    if (tokens[target_arg.start].kind != .ident) return false;
    return std.mem.eql(u8, tokens[line_start].lexeme, tokens[target_arg.start].lexeme);
}


const FieldGetCandidate = struct {
    name: []const u8,
    ty: []const u8,
    index: usize,
    has_default: bool,
};

const FieldGetBindingUse = struct {
    type_start: usize,
    type_end: usize,
};

const FieldStaticValue = union(enum) {
    bool: bool,
    int: usize,
    text: []const u8,
};

const FieldStaticIfParts = struct {
    cond_start: usize,
    cond_end: usize,
    then_start: usize,
    then_end: usize,
    else_if_start: ?usize = null,
    else_start: ?usize = null,
    else_end: usize = 0,
};

const FieldExprRange = struct {
    start: usize,
    end: usize,
};

const FieldStaticCallHead = struct {
    name_idx: usize,
    args_start: usize,
    args_end: usize,
    is_intrinsic: bool,
};

fn check_field_get_static_use(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    name_idx: usize,
    field_bindings: []const FieldMetaBinding,
    structs: []const StructInfo,
    funcs: []const FuncShape,
) !void {
    if (name_idx == 0 or !tok_eq(tokens[name_idx - 1], "@")) return;
    if (name_idx + 1 >= tokens.len or !tok_eq(tokens[name_idx + 1], "(")) return;

    const close_paren = find_matching(tokens, name_idx + 1, "(", ")") catch return;
    const field_arg = field_reflect_field_arg_range(tokens, name_idx, close_paren) orelse return;
    if (field_arg.start + 1 != field_arg.end or tokens[field_arg.start].kind != .ident) return;

    const binding = find_active_field_meta_binding(field_bindings, tokens[field_arg.start].lexeme) orelse return;
    const struct_info = find_struct_info(structs, binding.struct_name) orelse return;

    var candidates = try collect_field_get_candidates_at_use(allocator, tokens, name_idx, binding, struct_info);
    defer candidates.deinit(allocator);
    if (candidates.items.len == 0) return;

    if (field_get_direct_binding_use(tokens, name_idx, close_paren)) |binding_use| {
        if (!field_get_candidates_match_binding(tokens, candidates.items, binding_use)) {
            return mark_error_at(tokens, name_idx, error.InvalidFieldReflection);
        }
    }

    if (call_arg_info(tokens, name_idx)) |call| {
        if (has_known_func_candidate(funcs, call.name) and !field_get_candidates_match_call(tokens, funcs, call, candidates.items)) {
            return mark_error_at(tokens, name_idx, error.InvalidFieldReflection);
        }
    }
}


fn check_field_set_static_use(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    name_idx: usize,
    field_bindings: []const FieldMetaBinding,
    structs: []const StructInfo,
    funcs: []const FuncShape,
) !void {
    if (name_idx == 0 or !tok_eq(tokens[name_idx - 1], "@")) return;
    if (name_idx + 1 >= tokens.len or !tok_eq(tokens[name_idx + 1], "(")) return;

    const close_paren = find_matching(tokens, name_idx + 1, "(", ")") catch return;
    const field_arg = field_reflect_field_arg_range(tokens, name_idx, close_paren) orelse return;
    if (field_arg.start + 1 != field_arg.end or tokens[field_arg.start].kind != .ident) return;

    const binding = find_active_field_meta_binding(field_bindings, tokens[field_arg.start].lexeme) orelse return;
    const struct_info = find_struct_info(structs, binding.struct_name) orelse return;

    const value_arg = field_set_value_arg_range(tokens, name_idx, close_paren) orelse
        return mark_error_at(tokens, name_idx, error.InvalidFieldReflection);

    var candidates = try collect_field_get_candidates_at_use(allocator, tokens, name_idx, binding, struct_info);
    defer candidates.deinit(allocator);
    if (candidates.items.len == 0) return;

    if (!field_set_candidates_accept_value(tokens, funcs, value_arg, candidates.items)) {
        return mark_error_at(tokens, name_idx, error.InvalidFieldReflection);
    }
}


fn field_set_value_arg_range(tokens: []const lexer.Token, name_idx: usize, close_paren: usize) ?ArgRange {
    const args_start = name_idx + 2;
    const first_end = find_arg_end_any(tokens, args_start, close_paren);
    if (first_end >= close_paren or !tok_eq(tokens[first_end], ",")) return null;
    const field_start = first_end + 1;
    const field_end = find_arg_end_any(tokens, field_start, close_paren);
    if (field_end >= close_paren or !tok_eq(tokens[field_end], ",")) return null;
    const value_start = field_end + 1;
    const value_end = find_arg_end_any(tokens, value_start, close_paren);
    if (value_start >= value_end or value_end != close_paren) return null;
    return .{ .start = value_start, .end = value_end };
}


fn field_set_candidates_accept_value(
    tokens: []const lexer.Token,
    funcs: []const FuncShape,
    value_arg: ArgRange,
    candidates: []const FieldGetCandidate,
) bool {
    for (candidates) |candidate| {
        if (!(field_set_value_compatible_with_type(tokens, funcs, value_arg.start, value_arg.end, candidate.ty) orelse true)) {
            return false;
        }
    }
    return true;
}


fn field_set_value_compatible_with_type(
    tokens: []const lexer.Token,
    funcs: []const FuncShape,
    start_idx: usize,
    end_idx: usize,
    expected_ty: []const u8,
) ?bool {
    const range = field_trim_parens(tokens, start_idx, end_idx);
    if (range.start >= range.end) return null;

    if (range.end == range.start + 1) {
        const tok = tokens[range.start];
        if (tok.kind == .string) {
            return field_set_expected_accepts_known_type(expected_ty, "text") or field_set_expected_accepts_known_type(expected_ty, "[u8]");
        }
        if (tok.kind == .number) {
            return field_set_number_literal_accepts_type(tok.lexeme, expected_ty);
        }
        if (tok_eq(tok, "true") or tok_eq(tok, "false")) {
            return field_set_expected_accepts_known_type(expected_ty, "bool");
        }
        if (tok_eq(tok, "nil")) {
            return field_set_expected_accepts_known_type(expected_ty, "nil");
        }
        if (tok.kind == .ident) {
            const actual_ty = find_nearest_value_type_name(tokens, range.start, tok.lexeme) orelse return null;
            return field_set_expected_accepts_known_type(expected_ty, actual_ty);
        }
        return null;
    }

    const call_head = field_static_call_head(tokens, range) orelse return null;
    if (call_head.is_intrinsic) return null;
    const actual_ty = field_set_call_return_type(tokens, funcs, call_head) orelse return null;
    return field_set_expected_accepts_known_type(expected_ty, actual_ty);
}


fn field_set_call_return_type(tokens: []const lexer.Token, funcs: []const FuncShape, call: FieldStaticCallHead) ?[]const u8 {
    const arg_count = count_field_static_call_args(tokens, call.args_start, call.args_end) orelse return null;
    var found: ?[]const u8 = null;
    for (funcs) |func| {
        if (!std.mem.eql(u8, func.name, tokens[call.name_idx].lexeme)) continue;
        if (!call_arity_compatible_with_func(func, arg_count)) continue;
        const return_ty = func.return_type orelse return null;
        if (found) |prev| {
            if (!std.mem.eql(u8, prev, return_ty)) return null;
        } else {
            found = return_ty;
        }
    }
    return found;
}


fn count_field_static_call_args(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (start_idx == end_idx) return 0;
    var count: usize = 0;
    var arg_start = start_idx;
    while (arg_start < end_idx) {
        const arg_end = find_arg_end_any(tokens, arg_start, end_idx);
        if (arg_end == arg_start) return null;
        count += 1;
        arg_start = arg_end;
        if (arg_start < end_idx) {
            if (!tok_eq(tokens[arg_start], ",")) return null;
            arg_start += 1;
        }
    }
    return count;
}


fn field_set_expected_accepts_known_type(expected_ty: []const u8, actual_ty: []const u8) bool {
    if (std.mem.eql(u8, expected_ty, actual_ty)) return true;
    var it = std.mem.splitScalar(u8, expected_ty, '|');
    while (it.next()) |branch| {
        if (std.mem.eql(u8, branch, actual_ty)) return true;
    }
    return false;
}


fn field_set_number_literal_accepts_type(lexeme: []const u8, expected_ty: []const u8) bool {
    const is_float = std.mem.indexOfScalar(u8, lexeme, '.') != null;
    if (field_set_numeric_branch_accepts_literal(expected_ty, is_float)) return true;
    var it = std.mem.splitScalar(u8, expected_ty, '|');
    while (it.next()) |branch| {
        if (field_set_numeric_branch_accepts_literal(branch, is_float)) return true;
    }
    return false;
}


fn field_set_numeric_branch_accepts_literal(branch_ty: []const u8, is_float_literal: bool) bool {
    if (is_float_literal) return is_base_float_type_name(branch_ty);
    return is_base_int_type_name(branch_ty) or is_base_float_type_name(branch_ty);
}


fn collect_field_get_candidates_at_use(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    use_idx: usize,
    binding: FieldMetaBinding,
    struct_info: StructInfo,
) !std.ArrayList(FieldGetCandidate) {
    var candidates = std.ArrayList(FieldGetCandidate).empty;
    errdefer candidates.deinit(allocator);

    for (struct_info.fields, 0..) |field, idx| {
        const ty = field.ty orelse continue;
        try candidates.append(allocator, .{
            .name = field.name,
            .ty = ty,
            .index = idx,
            .has_default = field.has_default,
        });
    }

    try filter_field_get_candidates_by_static_guards(allocator, tokens, use_idx, binding, &candidates);
    return candidates;
}


fn filter_field_get_candidates_by_static_guards(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    use_idx: usize,
    binding: FieldMetaBinding,
    candidates: *std.ArrayList(FieldGetCandidate),
) !void {
    var i: usize = 0;
    while (i < use_idx and i < tokens.len) : (i += 1) {
        if (!tok_eq(tokens[i], "if")) continue;
        const stmt_end = find_field_static_stmt_end(tokens, i, tokens.len);
        const parts = field_static_if_parts(tokens, i, stmt_end) orelse continue;

        if (use_idx >= parts.then_start and use_idx < parts.then_end) {
            try filter_field_get_candidates_by_condition(allocator, tokens, parts.cond_start, parts.cond_end, true, binding, candidates);
            continue;
        }
        if (parts.else_if_start) |else_if_start| {
            if (use_idx >= else_if_start and use_idx < stmt_end) {
                try filter_field_get_candidates_by_condition(allocator, tokens, parts.cond_start, parts.cond_end, false, binding, candidates);
            }
            continue;
        }
        if (parts.else_start) |else_start| {
            if (use_idx >= else_start and use_idx < parts.else_end) {
                try filter_field_get_candidates_by_condition(allocator, tokens, parts.cond_start, parts.cond_end, false, binding, candidates);
            }
        }
    }
}


fn filter_field_get_candidates_by_condition(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    cond_start: usize,
    cond_end: usize,
    expected: bool,
    binding: FieldMetaBinding,
    candidates: *std.ArrayList(FieldGetCandidate),
) !void {
    var idx: usize = 0;
    while (idx < candidates.items.len) {
        const value = field_static_bool_for_candidate(tokens, cond_start, cond_end, binding, candidates.items[idx]) orelse return;
        if (value == expected) {
            idx += 1;
            continue;
        }
        _ = candidates.orderedRemove(idx);
    }
    _ = allocator;
}


fn field_get_candidates_match_binding(
    tokens: []const lexer.Token,
    candidates: []const FieldGetCandidate,
    binding_use: FieldGetBindingUse,
) bool {
    if (candidates.len <= 1) {
        if (binding_use.type_start == binding_use.type_end) return true;
        return compact_token_range_equals(tokens, binding_use.type_start, binding_use.type_end, candidates[0].ty);
    }

    if (binding_use.type_start == binding_use.type_end) return field_get_candidate_types_homogeneous(candidates);
    for (candidates) |candidate| {
        if (!compact_token_range_equals(tokens, binding_use.type_start, binding_use.type_end, candidate.ty)) return false;
    }
    return true;
}


fn field_get_candidate_types_homogeneous(candidates: []const FieldGetCandidate) bool {
    if (candidates.len <= 1) return true;
    const first = candidates[0].ty;
    for (candidates[1..]) |candidate| {
        if (!std.mem.eql(u8, first, candidate.ty)) return false;
    }
    return true;
}


fn field_get_direct_binding_use(
    tokens: []const lexer.Token,
    name_idx: usize,
    close_paren: usize,
) ?FieldGetBindingUse {
    if (name_idx == 0 or !tok_eq(tokens[name_idx - 1], "@")) return null;
    const line_start = line_start_idx(tokens, name_idx);
    const line_end = find_line_end_idx(tokens, name_idx);
    if (close_paren + 1 != line_end) return null;

    const eq_idx = find_top_level_assign_eq_on_line(tokens, line_start, line_end) orelse return null;
    if (eq_idx + 1 != name_idx - 1) return null;
    if (line_start >= eq_idx or tokens[line_start].kind != .ident) return null;
    if (find_top_level_comma(tokens, line_start, eq_idx) != null) return null;

    if (eq_idx == line_start + 1) {
        return .{ .type_start = eq_idx, .type_end = eq_idx };
    }
    return .{ .type_start = line_start + 1, .type_end = eq_idx };
}


fn field_get_candidates_match_call(
    tokens: []const lexer.Token,
    funcs: []const FuncShape,
    call: CallArgInfo,
    candidates: []const FieldGetCandidate,
) bool {
    for (candidates) |candidate| {
        if (!field_get_call_accepts_type(tokens, funcs, call, candidate.ty)) return false;
    }
    return true;
}


fn field_get_call_accepts_type(
    tokens: []const lexer.Token,
    funcs: []const FuncShape,
    call: CallArgInfo,
    actual_ty: []const u8,
) bool {
    for (funcs) |func| {
        if (!std.mem.eql(u8, func.name, call.name)) continue;
        if (!call_arity_compatible_with_func(func, call.arg_count)) continue;
        const param = field_get_param_shape_for_arg(func, call.arg_index) orelse continue;
        if (field_get_param_accepts_type(tokens, func, param, actual_ty)) return true;
    }
    return false;
}


fn field_get_param_shape_for_arg(func: FuncShape, arg_index: usize) ?FuncParamShape {
    if (arg_index < func.param_shapes.len) return func.param_shapes[arg_index];
    if (func.param_shapes.len == 0) return null;
    const last = func.param_shapes[func.param_shapes.len - 1];
    return switch (last) {
        .variadic => last,
        else => null,
    };
}


fn field_get_param_accepts_type(
    tokens: []const lexer.Token,
    func: FuncShape,
    param: FuncParamShape,
    actual_ty: []const u8,
) bool {
    const expected = switch (param) {
        .value => |ty| ty orelse return true,
        .variadic => |ty| ty orelse return true,
        .other => return true,
        .func => return false,
    };
    if (std.mem.eql(u8, expected, actual_ty)) return true;
    if (is_func_type_param(tokens, func.start_idx, expected) and !type_constraint_is_function_type(tokens, func.start_idx, expected)) return true;
    return field_get_param_contains_data_type_param(tokens, func, expected);
}


fn field_get_param_contains_data_type_param(tokens: []const lexer.Token, func: FuncShape, expected: []const u8) bool {
    const close_params = find_matching(tokens, func.start_idx + 1, "(", ")") catch return false;
    var seg_start = func.start_idx + 2;
    var i = seg_start;
    while (i <= close_params) : (i += 1) {
        if (i < close_params and !is_top_level_comma_any(tokens, i, func.start_idx + 2, close_params)) continue;
        const type_start = func_param_type_start(tokens, seg_start, i) orelse {
            seg_start = i + 1;
            continue;
        };
        if (!compact_token_range_equals(tokens, type_start, i, expected)) {
            seg_start = i + 1;
            continue;
        }
        var j = type_start;
        while (j < i) : (j += 1) {
            if (tokens[j].kind != .ident) continue;
            if (is_func_type_param(tokens, func.start_idx, tokens[j].lexeme) and !type_constraint_is_function_type(tokens, func.start_idx, tokens[j].lexeme)) return true;
        }
        return false;
    }
    return false;
}


fn find_field_static_stmt_end(tokens: []const lexer.Token, start_idx: usize, limit_idx: usize) usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < limit_idx) : (i += 1) {
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

        if (depth_paren != 0 or depth_brace != 0 or depth_angle != 0) continue;
        if (i + 1 >= limit_idx or tokens[i + 1].line != tokens[i].line) return i + 1;
    }
    return limit_idx;
}


fn field_static_if_parts(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ?FieldStaticIfParts {
    if (start_idx + 4 > end_idx) return null;
    if (!tok_eq(tokens[start_idx], "if")) return null;
    const open_brace = find_field_static_block_open(tokens, start_idx + 1, end_idx) orelse return null;
    const close_brace = find_matching_in_range(tokens, open_brace, "{", "}", end_idx) catch return null;
    var parts = FieldStaticIfParts{
        .cond_start = start_idx + 1,
        .cond_end = open_brace,
        .then_start = open_brace + 1,
        .then_end = close_brace,
    };
    if (close_brace + 1 == end_idx) return parts;
    if (close_brace + 1 >= end_idx or !tok_eq(tokens[close_brace + 1], "else")) return null;
    if (close_brace + 2 >= end_idx) return null;
    if (tok_eq(tokens[close_brace + 2], "if")) {
        parts.else_if_start = close_brace + 2;
        return parts;
    }
    if (!tok_eq(tokens[close_brace + 2], "{")) return null;
    const close_else = find_matching_in_range(tokens, close_brace + 2, "{", "}", end_idx) catch return null;
    if (close_else + 1 != end_idx) return null;
    parts.else_start = close_brace + 3;
    parts.else_end = close_else;
    return parts;
}


fn find_field_static_block_open(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
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
        if (depth_paren == 0 and depth_angle == 0 and tok_eq(tokens[i], "{")) return i;
    }
    return null;
}


fn field_static_bool_for_candidate(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    binding: FieldMetaBinding,
    candidate: FieldGetCandidate,
) ?bool {
    if (field_static_value_for_candidate(tokens, start_idx, end_idx, binding, candidate)) |value| {
        return switch (value) {
            .bool => |b| b,
            else => null,
        };
    }

    const range = field_trim_parens(tokens, start_idx, end_idx);
    const call_head = field_static_call_head(tokens, range) orelse return null;
    const call_name = tokens[call_head.name_idx].lexeme;
    if (!call_head.is_intrinsic) return null;

    if (std.mem.eql(u8, call_name, "not")) {
        const arg_end = find_arg_end_any(tokens, call_head.args_start, call_head.args_end);
        if (arg_end != call_head.args_end) return null;
        return !(field_static_bool_for_candidate(tokens, call_head.args_start, arg_end, binding, candidate) orelse return null);
    }
    if (std.mem.eql(u8, call_name, "and") or std.mem.eql(u8, call_name, "or")) {
        var arg_start = call_head.args_start;
        var saw_arg = false;
        while (arg_start < call_head.args_end) {
            const arg_end = find_arg_end_any(tokens, arg_start, call_head.args_end);
            const value = field_static_bool_for_candidate(tokens, arg_start, arg_end, binding, candidate) orelse return null;
            saw_arg = true;
            if (std.mem.eql(u8, call_name, "and") and !value) return false;
            if (std.mem.eql(u8, call_name, "or") and value) return true;
            arg_start = arg_end;
            if (arg_start < call_head.args_end and tok_eq(tokens[arg_start], ",")) arg_start += 1;
        }
        if (!saw_arg) return null;
        return std.mem.eql(u8, call_name, "and");
    }
    if (std.mem.eql(u8, call_name, "eq") or std.mem.eql(u8, call_name, "ne")) {
        const first_end = find_arg_end_any(tokens, call_head.args_start, call_head.args_end);
        if (first_end >= call_head.args_end or !tok_eq(tokens[first_end], ",")) return null;
        const second_start = first_end + 1;
        const second_end = find_arg_end_any(tokens, second_start, call_head.args_end);
        if (second_end != call_head.args_end) return null;
        const left = field_static_value_for_candidate(tokens, call_head.args_start, first_end, binding, candidate) orelse return null;
        const right = field_static_value_for_candidate(tokens, second_start, second_end, binding, candidate) orelse return null;
        const is_equal = field_static_values_equal(left, right);
        return if (std.mem.eql(u8, call_name, "eq")) is_equal else !is_equal;
    }
    return null;
}


fn field_static_value_for_candidate(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    binding: FieldMetaBinding,
    candidate: FieldGetCandidate,
) ?FieldStaticValue {
    const range = field_trim_parens(tokens, start_idx, end_idx);
    if (range.start >= range.end) return null;

    if (range.end == range.start + 1) {
        const tok = tokens[range.start];
        if (tok.kind == .number) return .{ .int = std.fmt.parseUnsigned(usize, tok.lexeme, 10) catch return null };
        if (tok.kind == .string) return .{ .text = string_token_body(tok.lexeme) orelse return null };
        if (tok_eq(tok, "true")) return .{ .bool = true };
        if (tok_eq(tok, "false")) return .{ .bool = false };
        return null;
    }

    const call_head = field_static_call_head(tokens, range) orelse return null;
    if (!call_head.is_intrinsic) return null;
    const call_name = tokens[call_head.name_idx].lexeme;
    if (std.mem.eql(u8, call_name, "field_name")) {
        if (!field_static_single_meta_arg_matches(tokens, call_head.args_start, call_head.args_end, binding.name)) return null;
        return .{ .text = candidate.name };
    }
    if (std.mem.eql(u8, call_name, "field_index")) {
        if (!field_static_single_meta_arg_matches(tokens, call_head.args_start, call_head.args_end, binding.name)) return null;
        return .{ .int = candidate.index };
    }
    if (std.mem.eql(u8, call_name, "field_has_default")) {
        if (!field_static_single_meta_arg_matches(tokens, call_head.args_start, call_head.args_end, binding.name)) return null;
        return .{ .bool = candidate.has_default };
    }
    return null;
}


fn field_static_single_meta_arg_matches(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    binding_name: []const u8,
) bool {
    const arg = single_arg_range(tokens, start_idx, end_idx) orelse return false;
    if (arg.start + 1 != arg.end or tokens[arg.start].kind != .ident) return false;
    return std.mem.eql(u8, tokens[arg.start].lexeme, binding_name);
}


fn field_static_values_equal(left: FieldStaticValue, right: FieldStaticValue) bool {
    return switch (left) {
        .bool => |l| switch (right) {
            .bool => |r| l == r,
            else => false,
        },
        .int => |l| switch (right) {
            .int => |r| l == r,
            else => false,
        },
        .text => |l| switch (right) {
            .text => |r| std.mem.eql(u8, l, r),
            else => false,
        },
    };
}


fn field_trim_parens(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) FieldExprRange {
    var start = start_idx;
    var end = end_idx;
    while (start + 1 < end and tok_eq(tokens[start], "(")) {
        const close = find_matching_in_range(tokens, start, "(", ")", end) catch break;
        if (close + 1 != end) break;
        start += 1;
        end -= 1;
    }
    return .{ .start = start, .end = end };
}


fn field_static_call_head(tokens: []const lexer.Token, range: FieldExprRange) ?FieldStaticCallHead {
    if (range.start >= range.end) return null;
    var name_idx = range.start;
    var is_intrinsic = false;
    if (tok_eq(tokens[name_idx], "@")) {
        is_intrinsic = true;
        name_idx += 1;
    }
    if (name_idx >= range.end or tokens[name_idx].kind != .ident) return null;
    if (name_idx + 1 >= range.end or !tok_eq(tokens[name_idx + 1], "(")) return null;
    const close_paren = find_matching_in_range(tokens, name_idx + 1, "(", ")", range.end) catch return null;
    if (close_paren + 1 != range.end) return null;
    return .{
        .name_idx = name_idx,
        .args_start = name_idx + 2,
        .args_end = close_paren,
        .is_intrinsic = is_intrinsic,
    };
}


fn find_arg_end_any(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
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


fn single_arg_range(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?ArgRange {
    var count: usize = 0;
    var out: ?ArgRange = null;
    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !is_top_level_comma_any(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            count += 1;
            out = .{ .start = seg_start, .end = i };
        }
        seg_start = i + 1;
    }
    if (count != 1) return null;
    return out;
}


fn nth_arg_range(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, arg_index: usize) ?ArgRange {
    var current: usize = 0;
    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !is_top_level_comma_any(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            if (current == arg_index) return .{ .start = seg_start, .end = i };
            current += 1;
        }
        seg_start = i + 1;
    }
    return null;
}


fn brace_depth_before(tokens: []const lexer.Token, before_idx: usize) usize {
    var depth: usize = 0;
    var i: usize = 0;
    while (i < before_idx) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            depth += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth > 0) depth -= 1;
        }
    }
    return depth;
}


fn is_unsupported_direct_loop_source(type_name: []const u8) bool {
    return std.mem.eql(u8, type_name, "List") or std.mem.eql(u8, type_name, "HashMap");
}


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


fn find_loop_block_open(tokens: []const lexer.Token, loop_idx: usize) ?usize {
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


fn find_loop_bind_assign(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
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


fn validate_loop_bind_lhs(tokens: []const lexer.Token, start_idx: usize, bind_idx: usize) !void {
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
    if (scope.containsLoopBinding(name) or scopes_contain(outer_scopes, name) or scopes_contain_loop_binding(outer_scopes, name)) {
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


