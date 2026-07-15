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
const validate_loop_bind_lhs = sema_tokens.validate_loop_bind_lhs;
const is_recv_loop_source = sema_tokens.is_recv_loop_source;
const is_fields_loop_source = sema_tokens.is_fields_loop_source;

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


fn is_unsupported_direct_loop_source(type_name: []const u8) bool {
    return std.mem.eql(u8, type_name, "List") or std.mem.eql(u8, type_name, "HashMap");
}
