//! Semantic function-call checks.
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema_error = @import("sema_error.zig");
const type_util = @import("type_name.zig");
const sema_tokens = @import("sema_tokens.zig");
const sema_shapes = @import("sema_shapes.zig");
const sema_function_support = @import("sema_function_support.zig");
const CallShape = sema_shapes.CallShape;
const KnownBool = sema_shapes.KnownBool;
const DirectCallSite = sema_shapes.DirectCallSite;
const ReturnArityResolve = sema_shapes.ReturnArityResolve;
const call_open_paren_idx = sema_function_support.call_open_paren_idx;
const collect_call_shapes_from_program = sema_function_support.collect_call_shapes_from_program;
const find_enclosing_func_param_type_name = sema_function_support.find_enclosing_func_param_type_name;
const find_inline_func_type_in_is_arg = sema_function_support.find_inline_func_type_in_is_arg;
const find_top_level_nil_in_is_arg = sema_function_support.find_top_level_nil_in_is_arg;
const is_scalar_as_target_type_name = sema_function_support.is_scalar_as_target_type_name;

const call_arity_compatible_with_func = sema_tokens.call_arity_compatible_with_func;
const collect_func_shapes = sema_function_support.collect_func_shapes;
const find_constraint_block_start_before = sema_tokens.find_constraint_block_start_before;
const find_line_end_idx = sema_tokens.find_line_end_idx;
const find_matching = sema_tokens.find_matching;
const find_nearest_value_type_name = sema_tokens.find_nearest_value_type_name;
const find_return_type_end = sema_tokens.find_return_type_end;
const find_top_level_assign_eq_on_line = sema_tokens.find_top_level_assign_eq_on_line;
const find_top_level_comma = sema_tokens.find_top_level_comma;
const first_non_gap = sema_tokens.first_non_gap;
const free_call_arg_shapes = sema_function_support.free_call_arg_shapes;
const free_func_shapes = sema_function_support.free_func_shapes;
const func_param_type_start = sema_tokens.func_param_type_start;
const has_known_func_candidate = sema_tokens.has_known_func_candidate;
const is_arrow_at = sema_tokens.is_arrow_at;
const is_func_decl_start = sema_tokens.is_func_decl_start;
const is_func_type_param = sema_tokens.is_func_type_param;
const is_host_import_decl_start = sema_tokens.is_host_import_decl_start;
const is_keyword = sema_tokens.is_keyword;
const is_local_payload_enum_case = sema_function_support.is_local_payload_enum_case;
const is_return_arrow_at = sema_tokens.is_return_arrow_at;
const is_start_decl_start = sema_tokens.is_start_decl_start;
const is_top_level_comma_any = sema_tokens.is_top_level_comma_any;
const is_top_level_decl_head = sema_tokens.is_top_level_decl_head;
const is_valid_declared_type_name = sema_tokens.is_valid_declared_type_name;
const is_value_literal_token = sema_tokens.is_value_literal_token;
const mark_error_at = sema_tokens.mark_error_at;
const parse_call_arg_shapes = sema_function_support.parse_call_arg_shapes;
const public_func_name = sema_tokens.public_func_name;
const public_type_name = sema_tokens.public_type_name;
const tok_eq = sema_tokens.tok_eq;
const token_name_appears_in_range = sema_tokens.token_name_appears_in_range;
const type_constraint_is_function_type = sema_tokens.type_constraint_is_function_type;
const validate_is_type_atom = sema_tokens.validate_is_type_atom;
const validate_is_type_expr = sema_tokens.validate_is_type_expr;
const CallArgShape = sema_shapes.CallArgShape;
const FuncParamShape = sema_shapes.FuncParamShape;
const FuncShape = sema_shapes.FuncShape;
const FuncTypeShape = sema_shapes.FuncTypeShape;
const LambdaArgShape = sema_shapes.LambdaArgShape;

pub fn check_single_value_positions(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
) !void {
    for (program.value_exprs) |site| {
        if (site.expected_arity <= 1) continue;

        const resolved = root_expr_return_arity(program, site.root_expr_idx);
        const allowed = switch (resolved) {
            .unknown => true,
            .ambiguous => false,
            .arity => |arity| arity == site.expected_arity,
        };
        if (allowed) continue;

        const start_tok = root_expr_start_tok(program, site.root_expr_idx);
        const err = switch (site.context) {
            .assign => error.InvalidAssignExpr,
            .rhs => error.MultiReturnInSingleValuePosition,
            .return_value => error.InvalidReturnStmt,
            .single => error.MultiReturnInSingleValuePosition,
        };
        return mark_error_at(tokens, start_tok, err);
    }

    for (program.condition_exprs) |site| {
        const call_site = find_direct_call_at_root(program, site.root_expr_idx);
        if (call_site == null) continue;

        const resolved = resolve_call_return_arity(
            program.func_sigs,
            call_site.?.call.func_name,
            call_site.?.call.arg_count,
        );
        switch (resolved) {
            .unknown => continue, // 可能是外部导入函数, 此阶段不阻断
            .arity => |arity| {
                if (arity <= 1) continue;
                switch (site.context) {
                    .if_cond => return mark_error_at(tokens, call_site.?.start_tok_idx, error.MultiReturnInIfCondition),
                    .loop_cond => return mark_error_at(tokens, call_site.?.start_tok_idx, error.MultiReturnInLoopCondition),
                }
            },
            .ambiguous => return mark_error_at(tokens, call_site.?.start_tok_idx, error.AmbiguousConditionCallReturnArity),
        }
    }

    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (!is_call_head(tokens, i) and !is_builtin_intrinsic_call_head(tokens, i)) continue;
        if (is_top_level_decl_head(tokens, i) and (is_func_decl_start(tokens, i) or is_start_decl_start(tokens, i))) continue;
        if (is_func_constraint_head(tokens, i)) continue;

        const open_paren = call_open_paren_idx(tokens, i, tokens.len) orelse continue;
        const close_paren = find_matching(tokens, open_paren, "(", ")") catch
            return mark_error_at(tokens, i + 1, error.InvalidCallArgList);
        const args = try parse_call_arg_shapes(allocator, tokens, open_paren + 1, close_paren);
        defer free_call_arg_shapes(allocator, args);

        const resolved = resolve_call_return_arity(program.func_sigs, tokens[i].lexeme, args.len);
        const arity = switch (resolved) {
            .unknown => continue,
            .ambiguous => return mark_error_at(tokens, i, error.AmbiguousConditionCallReturnArity),
            .arity => |value| value,
        };
        if (arity <= 1) continue;
        if (value_expr_allows_arity_at(program, i, arity)) continue;

        return mark_error_at(tokens, i, error.MultiReturnInSingleValuePosition);
    }
}
pub fn check_known_condition_bool_sites(allocator: std.mem.Allocator, program: parser.Program, tokens: []const lexer.Token) !void {
    const funcs = try collect_func_shapes(allocator, tokens);
    defer free_func_shapes(allocator, funcs);

    for (program.condition_exprs) |site| {
        const err = switch (site.context) {
            .if_cond => error.NonBoolIfCondition,
            .loop_cond => error.NonBoolLoopCondition,
        };

        switch (try classify_known_bool(allocator, program, funcs, tokens, site.root_expr_idx)) {
            .yes, .unknown => continue,
            .no_matching_call => {
                const start_tok = root_expr_start_tok(program, site.root_expr_idx);
                return mark_error_at(tokens, start_tok, error.NoMatchingCall);
            },
            .no => {
                const start_tok = root_expr_start_tok(program, site.root_expr_idx);
                return mark_error_at(tokens, start_tok, err);
            },
        }
    }
}
pub fn check_line_string_root_positions(program: parser.Program, tokens: []const lexer.Token) !void {
    for (program.expr_nodes) |node| {
        if (node.kind != .literal) continue;
        if (!is_line_string_token(tokens[node.start_tok])) continue;
        if (is_line_string_root_expr(program, node.start_tok)) continue;
        return mark_error_at(tokens, node.start_tok, error.UnsupportedExpr);
    }
}



pub fn is_line_string_root_expr(program: parser.Program, start_tok: usize) bool {
    for (program.value_exprs) |site| {
        if (site.context != .rhs) continue;
        if (site.root_expr_idx >= program.expr_nodes.len) continue;
        if (program.expr_nodes[site.root_expr_idx].start_tok == start_tok) return true;
    }
    return false;
}



pub fn is_line_string_token(tok: lexer.Token) bool {
    return tok.kind == .string and tok.lexeme.len >= 2 and tok.lexeme[0] == '\\' and tok.lexeme[1] == '\\';
}



pub fn check_is_type_args(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (!tok_eq(tokens[i], "is")) continue;
        if (!tok_eq(tokens[i + 1], "(")) continue;
        const close_paren = find_matching(tokens, i + 1, "(", ")") catch
            return mark_error_at(tokens, i + 1, error.InvalidNarrowing);
        const comma = find_top_level_comma(tokens, i + 2, close_paren) orelse
            return mark_error_at(tokens, i, error.InvalidNarrowing);
        const type_arg = first_non_gap(tokens, comma + 1, close_paren) orelse
            return mark_error_at(tokens, comma, error.InvalidNarrowing);
        if (is_value_literal_token(tokens[type_arg])) {
            return mark_error_at(tokens, type_arg, error.InvalidNarrowing);
        }
        if (find_inline_func_type_in_is_arg(tokens, type_arg, close_paren)) |func_type_idx| {
            return mark_error_at(tokens, func_type_idx, error.InvalidNarrowing);
        }
        if (find_top_level_comma(tokens, type_arg, close_paren)) |extra_comma| {
            return mark_error_at(tokens, extra_comma, error.InvalidNarrowing);
        }
        if (find_top_level_nil_in_is_arg(tokens, type_arg, close_paren)) |nil_idx| {
            return mark_error_at(tokens, nil_idx, error.InvalidNarrowing);
        }
        // Payload-enum case name as second arg: @is(m, Text)
        if (type_arg + 1 == close_paren and tokens[type_arg].kind == .ident and
            is_valid_declared_type_name(tokens[type_arg].lexeme) and
            is_local_payload_enum_case(tokens, public_type_name(tokens[type_arg].lexeme)))
        {
            continue;
        }
        if (validate_is_target_type_expr(tokens, type_arg, close_paren) != close_paren) {
            return mark_error_at(tokens, type_arg, error.InvalidNarrowing);
        }
    }
}



pub fn check_as_type_args(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (!tok_eq(tokens[i], "as")) continue;
        if (!tok_eq(tokens[i + 1], "(")) continue;
        const close_paren = find_matching(tokens, i + 1, "(", ")") catch
            return mark_error_at(tokens, i + 1, error.InvalidCallArgList);
        const comma = find_top_level_comma(tokens, i + 2, close_paren) orelse
            return mark_error_at(tokens, i, error.InvalidCallArgList);

        if (as_type_first_arg(tokens, i + 2, comma) != null) {
            if (find_top_level_comma(tokens, comma + 1, close_paren)) |extra_comma| {
                return mark_error_at(tokens, extra_comma, error.InvalidCallArgList);
            }
            if (comma + 1 >= close_paren) return mark_error_at(tokens, comma, error.InvalidCallArgList);
            continue;
        }
        return mark_error_at(tokens, i, error.InvalidCallArgList);
    }
}



pub fn as_type_first_arg(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    const type_arg = first_non_gap(tokens, start_idx, end_idx) orelse return null;
    if (validate_scalar_as_target_type(tokens, type_arg, end_idx) != end_idx) return null;
    return type_arg;
}



pub fn validate_scalar_as_target_type(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (start_idx + 1 != end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (!is_scalar_as_target_type_name(tokens[start_idx].lexeme)) return null;
    return end_idx;
}



pub fn validate_is_target_type_expr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    return validate_is_type_atom(tokens, start_idx, end_idx);
}



pub fn check_generic_call_inference(
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
        if (call.has_explicit_type_args) continue;

        var has_plain_candidate = false;
        var has_direct_generic_candidate = false;
        var has_inferred_generic_candidate = false;

        for (funcs) |func| {
            if (!std.mem.eql(u8, func.name, call.name)) continue;
            if (func.param_shapes.len != call.arg_shapes.len) continue;

            if (!func_has_type_constraints(tokens, func.start_idx)) {
                has_plain_candidate = true;
                continue;
            }
            if (!func_has_direct_type_param_param(tokens, func)) {
                has_direct_generic_candidate = has_direct_generic_candidate or
                    func_has_uninferred_return_type_param(tokens, func);
                continue;
            }

            has_direct_generic_candidate = true;
            if (generic_call_infers_direct_type_params(tokens, funcs, func, call)) {
                has_inferred_generic_candidate = true;
            }
        }

        if (!has_direct_generic_candidate) continue;
        if (has_inferred_generic_candidate) continue;
        if (has_plain_candidate) continue;
        return mark_error_at(tokens, call.start_idx, error.NoMatchingCall);
    }
}



pub fn check_spread_call_targets(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
) !void {
    const funcs = try collect_func_shapes(allocator, tokens);
    defer free_func_shapes(allocator, funcs);

    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (!is_call_head(tokens, i) and !is_builtin_intrinsic_call_head(tokens, i)) continue;
        if (is_top_level_decl_head(tokens, i) and (is_func_decl_start(tokens, i) or is_start_decl_start(tokens, i))) continue;
        if (is_func_constraint_head(tokens, i)) continue;

        const open_paren = call_open_paren_idx(tokens, i, tokens.len) orelse continue;
        const close_paren = find_matching(tokens, open_paren, "(", ")") catch
            return mark_error_at(tokens, i + 1, error.InvalidCallArgList);
        const args = try parse_call_arg_shapes(allocator, tokens, open_paren + 1, close_paren);
        defer free_call_arg_shapes(allocator, args);

        const spread_idx = call_arg_spread_index(args) orelse continue;
        const spread_token_idx = call_arg_spread_token_idx(args) orelse i;
        const call_name = tokens[i].lexeme;
        if (is_host_import_func_name(tokens, call_name)) {
            return mark_error_at(tokens, spread_token_idx, error.InvalidCallArgList);
        }
        if (builtin_spread_call_allowed(call_name, spread_idx)) |allowed| {
            if (!allowed) return mark_error_at(tokens, spread_token_idx, error.InvalidCallArgList);
            continue;
        }
        if (!has_known_func_candidate(funcs, call_name)) continue;

        for (funcs) |func| {
            if (!std.mem.eql(u8, func.name, call_name)) continue;
            if (call_spread_compatible_with_func(func, args.len, spread_idx)) break;
        } else {
            return mark_error_at(tokens, spread_token_idx, error.InvalidCallArgList);
        }
    }
}



pub fn call_arg_spread_index(args: []const CallArgShape) ?usize {
    for (args, 0..) |arg, arg_idx| {
        if (arg == .spread) return arg_idx;
    }
    return null;
}



pub fn call_arg_spread_token_idx(args: []const CallArgShape) ?usize {
    for (args) |arg| {
        if (arg == .spread) return arg.spread;
    }
    return null;
}



pub fn call_spread_compatible_with_func(func: FuncShape, arg_count: usize, spread_idx: usize) bool {
    if (!call_arity_compatible_with_func(func, arg_count)) return false;
    if (func.param_max != null) return false;
    return spread_idx >= func.param_min;
}



pub fn builtin_spread_call_allowed(name: []const u8, spread_idx: usize) ?bool {
    if (is_numeric_core_name(name)) return spread_idx >= 2;
    if (std.mem.eql(u8, name, "put")) return spread_idx == 1;
    if (is_builtin_call_name(name)) return false;
    return null;
}



pub fn is_host_import_func_name(tokens: []const lexer.Token, name: []const u8) bool {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!is_top_level_decl_head(tokens, i)) continue;
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, public_func_name(tokens[i].lexeme), name)) continue;
        if (is_host_import_decl_start(tokens, i)) return true;
    }
    return false;
}



pub fn is_numeric_core_name(name: []const u8) bool {
    const names = [_][]const u8{ "add", "sub", "mul", "div", "rem", "min", "max" };
    for (names) |it| {
        if (std.mem.eql(u8, it, name)) return true;
    }
    return false;
}



pub fn is_builtin_call_name(name: []const u8) bool {
    const names = [_][]const u8{
        "is",
        "as",
        "and",
        "or",
        "not",
        "eq",
        "ne",
        "lt",
        "le",
        "gt",
        "ge",
        "add",
        "sub",
        "mul",
        "div",
        "rem",
        "get",
        "set",
        "field_name",
        "field_index",
        "field_has_default",
        "field_get",
        "field_set",
        "len",
        "put",
        "load_u8",
        "load_i8",
        "load_u16_le",
        "load_i16_le",
        "load_u32_le",
        "load_i32_le",
        "load_u64_le",
        "load_i64_le",
        "xor",
        "shl",
        "shr",
        "rotl",
        "rotr",
        "clz",
        "ctz",
        "popcnt",
        "abs",
        "neg",
        "sqrt",
        "ceil",
        "floor",
        "trunc",
        "nearest",
        "min",
        "max",
        "copysign",
    };
    for (names) |it| {
        if (std.mem.eql(u8, it, name)) return true;
    }
    return false;
}



pub fn func_has_type_constraints(tokens: []const lexer.Token, func_start_idx: usize) bool {
    return find_constraint_block_start_before(tokens, func_start_idx) != null;
}



pub fn func_has_direct_type_param_param(tokens: []const lexer.Token, func: FuncShape) bool {
    for (func.param_shapes) |param| {
        const type_name = switch (param) {
            .value => |value_type| value_type orelse continue,
            .variadic => |value_type| value_type orelse continue,
            else => continue,
        };
        if (type_constraint_is_function_type(tokens, func.start_idx, type_name)) continue;
        if (is_func_type_param(tokens, func.start_idx, type_name)) return true;
    }
    return func_param_type_ranges_contain_data_type_param(tokens, func);
}



pub fn generic_call_infers_direct_type_params(
    tokens: []const lexer.Token,
    funcs: []const FuncShape,
    func: FuncShape,
    call: CallShape,
) bool {
    if (func_has_uninferred_return_type_param(tokens, func)) return false;
    if (!generic_call_has_required_lambda_return_types(tokens, func, call)) return false;

    for (func.param_shapes, 0..) |param, param_idx| {
        const type_name = switch (param) {
            .value => |value_type| value_type orelse continue,
            .variadic => |value_type| value_type orelse continue,
            else => continue,
        };
        if (type_constraint_is_function_type(tokens, func.start_idx, type_name)) continue;
        if (!is_func_type_param(tokens, func.start_idx, type_name)) continue;
        if (has_prior_direct_type_param(func, param_idx, type_name)) continue;
        if (!call_has_known_arg_for_direct_type_param(tokens, funcs, func, call, type_name)) return false;
    }
    return true;
}



pub fn func_has_uninferred_return_type_param(tokens: []const lexer.Token, func: FuncShape) bool {
    const close_params = find_matching(tokens, func.start_idx + 1, "(", ")") catch return false;
    var return_start = close_params + 1;
    if (return_start >= tokens.len) return false;
    if (is_return_arrow_at(tokens, return_start)) return_start += 2;
    if (return_start >= tokens.len) return false;
    if (tok_eq(tokens[return_start], "{") or is_arrow_at(tokens, return_start)) return false;

    const return_end = find_return_type_end(tokens, return_start);
    var i = return_start;
    while (i < return_end) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        const name = tokens[i].lexeme;
        if (!is_func_type_param(tokens, func.start_idx, name)) continue;
        if (type_constraint_is_function_type(tokens, func.start_idx, name)) continue;
        if (!func_param_side_can_bind_type_param(tokens, func, name)) return true;
    }
    return false;
}



pub fn func_param_side_can_bind_type_param(tokens: []const lexer.Token, func: FuncShape, type_name: []const u8) bool {
    if (func_param_type_ranges_contain_type_param(tokens, func, type_name)) return true;

    for (func.param_shapes, 0..) |param, param_idx| {
        const param_type = switch (param) {
            .value => |value_type| value_type orelse continue,
            .variadic => |value_type| value_type orelse continue,
            .func => |func_type| {
                if (func_type_shape_contains_type_param(func_type, type_name)) return true;
                continue;
            },
            .other => continue,
        };
        if (type_constraint_is_function_type(tokens, func.start_idx, param_type)) {
            if (type_constraint_func_shape_contains_type_param(tokens, func.start_idx, param_type, type_name)) return true;
            continue;
        }
        if (!std.mem.eql(u8, param_type, type_name)) continue;
        if (has_prior_direct_type_param(func, param_idx, type_name)) continue;
        return true;
    }
    return false;
}



pub fn func_param_type_ranges_contain_data_type_param(tokens: []const lexer.Token, func: FuncShape) bool {
    const close_params = find_matching(tokens, func.start_idx + 1, "(", ")") catch return false;
    var seg_start = func.start_idx + 2;
    var i = seg_start;
    while (i <= close_params) : (i += 1) {
        if (i < close_params and !is_top_level_comma_any(tokens, i, func.start_idx + 2, close_params)) continue;
        if (func_param_type_range_contains_data_type_param(tokens, func, seg_start, i)) return true;
        seg_start = i + 1;
    }
    return false;
}



pub fn func_param_type_ranges_contain_type_param(tokens: []const lexer.Token, func: FuncShape, type_name: []const u8) bool {
    const close_params = find_matching(tokens, func.start_idx + 1, "(", ")") catch return false;
    var seg_start = func.start_idx + 2;
    var i = seg_start;
    while (i <= close_params) : (i += 1) {
        if (i < close_params and !is_top_level_comma_any(tokens, i, func.start_idx + 2, close_params)) continue;
        if (func_param_type_range_contains_type_param(tokens, seg_start, i, type_name)) return true;
        seg_start = i + 1;
    }
    return false;
}



pub fn func_param_type_range_contains_data_type_param(
    tokens: []const lexer.Token,
    func: FuncShape,
    start_idx: usize,
    end_idx: usize,
) bool {
    const type_start = func_param_type_start(tokens, start_idx, end_idx) orelse return false;
    var i = type_start;
    while (i < end_idx) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        const name = tokens[i].lexeme;
        if (!is_func_type_param(tokens, func.start_idx, name)) continue;
        if (type_constraint_is_function_type(tokens, func.start_idx, name)) continue;
        return true;
    }
    return false;
}



pub fn func_param_type_range_contains_type_param(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    type_name: []const u8,
) bool {
    const type_start = func_param_type_start(tokens, start_idx, end_idx) orelse return false;
    return token_name_appears_in_range(tokens, type_start, end_idx, type_name);
}



pub fn func_type_shape_contains_type_param(shape: FuncTypeShape, type_name: []const u8) bool {
    for (shape.param_types) |param_type| {
        const name = param_type orelse continue;
        if (std.mem.eql(u8, name, type_name)) return true;
    }
    if (shape.return_type) |ret| {
        if (std.mem.eql(u8, ret, type_name)) return true;
    }
    return false;
}



pub fn type_constraint_func_shape_contains_type_param(
    tokens: []const lexer.Token,
    func_start_idx: usize,
    constraint_name: []const u8,
    type_name: []const u8,
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
        if (token_name_appears_in_range(tokens, eq_idx + 1, line_end, type_name)) return true;
        return false;
    }
    return false;
}



pub fn generic_call_has_required_lambda_return_types(
    tokens: []const lexer.Token,
    func: FuncShape,
    call: CallShape,
) bool {
    for (func.param_shapes, 0..) |param, param_idx| {
        const param_type = switch (param) {
            .value => |value_type| value_type orelse continue,
            .variadic => |value_type| value_type orelse continue,
            else => continue,
        };
        if (!type_constraint_func_return_has_type_param(tokens, func.start_idx, param_type)) continue;
        if (param_idx >= call.arg_shapes.len) return false;

        switch (call.arg_shapes[param_idx]) {
            .lambda => |lambda| if (lambda.return_type == null) return false,
            else => {},
        }
    }
    return true;
}



pub fn has_prior_direct_type_param(func: FuncShape, before_param_idx: usize, type_name: []const u8) bool {
    var i: usize = 0;
    while (i < before_param_idx) : (i += 1) {
        const prior = switch (func.param_shapes[i]) {
            .value => |value_type| value_type orelse continue,
            .variadic => |value_type| value_type orelse continue,
            else => continue,
        };
        if (std.mem.eql(u8, prior, type_name)) return true;
    }
    return false;
}



pub fn call_has_known_arg_for_direct_type_param(
    tokens: []const lexer.Token,
    funcs: []const FuncShape,
    func: FuncShape,
    call: CallShape,
    type_name: []const u8,
) bool {
    for (func.param_shapes, 0..) |param, param_idx| {
        const param_type = switch (param) {
            .value => |value_type| value_type orelse continue,
            .variadic => |value_type| value_type orelse continue,
            else => continue,
        };
        if (!std.mem.eql(u8, param_type, type_name)) continue;
        if (param_idx >= call.arg_shapes.len) return false;

        const arg_name = switch (call.arg_shapes[param_idx]) {
            .ident => |ident| ident,
            else => continue,
        };
        if (has_known_value_type_before(tokens, call.start_idx, arg_name)) return true;
    }
    if (call_has_known_callback_arg_for_type_param(tokens, funcs, func, call, type_name)) return true;
    return false;
}



pub fn call_has_known_callback_arg_for_type_param(
    tokens: []const lexer.Token,
    funcs: []const FuncShape,
    func: FuncShape,
    call: CallShape,
    type_name: []const u8,
) bool {
    for (func.param_shapes, 0..) |param, param_idx| {
        const constraint_name = switch (param) {
            .value => |value_type| value_type orelse continue,
            .variadic => |value_type| value_type orelse continue,
            .func => continue,
            .other => continue,
        };
        if (!type_constraint_is_function_type(tokens, func.start_idx, constraint_name)) continue;
        if (param_idx >= call.arg_shapes.len) return false;
        switch (call.arg_shapes[param_idx]) {
            .lambda => |lambda| {
                if (lambda_binds_type_param_through_constraint(tokens, func.start_idx, constraint_name, type_name, lambda)) return true;
            },
            .ident => |name| {
                if (function_ref_binds_type_param_through_constraint(tokens, funcs, func.start_idx, constraint_name, type_name, name)) return true;
            },
            else => {},
        }
    }
    return false;
}



pub fn function_ref_binds_type_param_through_constraint(
    tokens: []const lexer.Token,
    funcs: []const FuncShape,
    func_start_idx: usize,
    constraint_name: []const u8,
    type_name: []const u8,
    func_ref_name: []const u8,
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

        for (funcs) |candidate| {
            if (!std.mem.eql(u8, candidate.name, func_ref_name)) continue;
            if (func_candidate_binds_type_param_in_constraint(
                tokens,
                candidate,
                eq_idx,
                close_params,
                line_end,
                type_name,
            )) return true;
        }
        return false;
    }
    return false;
}



pub fn lambda_binds_type_param_through_constraint(
    tokens: []const lexer.Token,
    func_start_idx: usize,
    constraint_name: []const u8,
    type_name: []const u8,
    lambda: LambdaArgShape,
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

        if (lambda_binds_type_param_in_constraint_params(
            tokens,
            lambda,
            eq_idx,
            close_params,
            line_end,
            type_name,
        )) return true;
        return false;
    }
    return false;
}

fn param_shape_has_concrete_type(shape: FuncParamShape) bool {
    return switch (shape) {
        .value => |value_type| value_type != null,
        .variadic => |value_type| value_type != null,
        else => false,
    };
}

fn func_candidate_binds_type_param_in_constraint(
    tokens: []const lexer.Token,
    candidate: FuncShape,
    eq_idx: usize,
    close_params: usize,
    line_end: usize,
    type_name: []const u8,
) bool {
    var seg_start = eq_idx + 2;
    var seg_idx: usize = 0;
    var seg = seg_start;
    while (seg <= close_params) : (seg += 1) {
        if (seg < close_params and !is_top_level_comma_any(tokens, seg, eq_idx + 2, close_params)) continue;
        if (seg_start >= seg) {
            seg_start = seg + 1;
            continue;
        }
        if (seg_idx < candidate.param_shapes.len and
            token_name_appears_in_range(tokens, seg_start, seg, type_name) and
            param_shape_has_concrete_type(candidate.param_shapes[seg_idx]))
        {
            return true;
        }
        seg_idx += 1;
        seg_start = seg + 1;
    }
    if (!is_return_arrow_at(tokens, close_params + 1)) return false;
    if (candidate.return_type == null) return false;
    return token_name_appears_in_range(tokens, close_params + 3, line_end, type_name);
}

fn lambda_binds_type_param_in_constraint_params(
    tokens: []const lexer.Token,
    lambda: LambdaArgShape,
    eq_idx: usize,
    close_params: usize,
    line_end: usize,
    type_name: []const u8,
) bool {
    var seg_start = eq_idx + 2;
    var seg_idx: usize = 0;
    var seg = seg_start;
    while (seg <= close_params) : (seg += 1) {
        if (seg < close_params and !is_top_level_comma_any(tokens, seg, eq_idx + 2, close_params)) continue;
        if (seg_start >= seg) {
            seg_start = seg + 1;
            continue;
        }
        if (seg_idx < lambda.param_types.len and
            lambda.param_types[seg_idx] != null and
            token_name_appears_in_range(tokens, seg_start, seg, type_name))
        {
            return true;
        }
        seg_idx += 1;
        seg_start = seg + 1;
    }
    if (!is_return_arrow_at(tokens, close_params + 1)) return false;
    if (lambda.return_type == null) return false;
    return token_name_appears_in_range(tokens, close_params + 3, line_end, type_name);
}



pub fn has_known_value_type_before(tokens: []const lexer.Token, before_idx: usize, name: []const u8) bool {
    if (find_nearest_value_type_name(tokens, before_idx, name) != null) return true;
    if (has_nearest_value_type_expr(tokens, before_idx, name)) return true;
    return find_enclosing_func_param_type_name(tokens, before_idx, name) != null;
}



pub fn has_nearest_value_type_expr(tokens: []const lexer.Token, before_idx: usize, name: []const u8) bool {
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
        return validate_is_type_expr(tokens, i + 1, eq_idx) == eq_idx;
    }
    return false;
}



pub fn type_constraint_func_return_has_type_param(
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
        if (!is_return_arrow_at(tokens, close_params + 1)) return false;

        var ret_idx = close_params + 3;
        while (ret_idx < line_end) : (ret_idx += 1) {
            if (tokens[ret_idx].kind != .ident) continue;
            if (is_func_type_param(tokens, func_start_idx, tokens[ret_idx].lexeme)) return true;
        }
        return false;
    }
    return false;
}



pub fn is_call_head(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (tokens[idx].kind != .ident) return false;
    if (idx > 0 and tok_eq(tokens[idx - 1], "@") and tokens[idx - 1].line == tokens[idx].line) return false;
    if (is_keyword(tokens[idx].lexeme)) return false;
    return call_open_paren_idx(tokens, idx, tokens.len) != null;
}



pub fn is_builtin_intrinsic_call_head(tokens: []const lexer.Token, idx: usize) bool {
    if (idx == 0 or idx + 1 >= tokens.len) return false;
    if (tokens[idx].kind != .ident) return false;
    if (!tok_eq(tokens[idx - 1], "@") or tokens[idx - 1].line != tokens[idx].line) return false;
    if (!is_builtin_call_name(tokens[idx].lexeme)) return false;
    return tok_eq(tokens[idx + 1], "(");
}



pub fn is_func_constraint_head(tokens: []const lexer.Token, idx: usize) bool {
    if (idx == 0 or !tok_eq(tokens[idx - 1], "#")) return false;
    return tokens[idx - 1].line == tokens[idx].line;
}



pub fn root_expr_start_tok(program: parser.Program, root_idx: usize) usize {
    if (root_idx >= program.expr_nodes.len) return 0;
    const node = program.expr_nodes[root_idx];
    return switch (node.kind) {
        .paren => root_expr_start_tok(program, node.data.child),
        else => node.start_tok,
    };
}



pub fn classify_known_bool(
    allocator: std.mem.Allocator,
    program: parser.Program,
    funcs: []const FuncShape,
    tokens: []const lexer.Token,
    root_idx: usize,
) !KnownBool {
    if (root_idx >= program.expr_nodes.len) return .unknown;
    const node = program.expr_nodes[root_idx];

    return switch (node.kind) {
        .paren => try classify_known_bool(allocator, program, funcs, tokens, node.data.child),
        .literal => classify_literal_bool(tokens, node.start_tok),
        .ident => classify_typed_ident_bool(tokens, node.start_tok),
        .call => try classify_call_bool(allocator, funcs, tokens, node),
        .lambda,
        .inferred_agg_lit,
        .struct_lit,
        => .no,
    };
}



pub fn classify_literal_bool(tokens: []const lexer.Token, tok_idx: usize) KnownBool {
    if (tok_idx >= tokens.len) return .unknown;
    if (tok_eq(tokens[tok_idx], "true") or tok_eq(tokens[tok_idx], "false")) return .yes;
    return .no;
}



pub fn classify_typed_ident_bool(tokens: []const lexer.Token, ident_tok_idx: usize) KnownBool {
    if (ident_tok_idx >= tokens.len) return .unknown;
    const name = tokens[ident_tok_idx].lexeme;
    const typed = find_nearest_typed_binding(tokens, ident_tok_idx, name) orelse return .unknown;
    return if (typed) .yes else .no;
}



pub fn find_nearest_typed_binding(tokens: []const lexer.Token, ident_tok_idx: usize, name: []const u8) ?bool {
    var skip_depth: usize = 0;
    var i = ident_tok_idx;
    while (i > 0) {
        i -= 1;

        if (tok_eq(tokens[i], "}")) {
            skip_depth += 1;
            continue;
        }
        if (tok_eq(tokens[i], "{")) {
            if (skip_depth > 0) {
                skip_depth -= 1;
            }
            continue;
        }
        if (skip_depth != 0) continue;
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, tokens[i].lexeme, name)) continue;

        if (typed_binding_bool(tokens, i)) |is_bool| return is_bool;
    }
    return null;
}



pub fn typed_binding_bool(tokens: []const lexer.Token, name_idx: usize) ?bool {
    if (name_idx + 2 >= tokens.len) return null;
    const line_end = find_line_end_idx(tokens, name_idx);
    if (line_end <= name_idx + 1) return null;

    const eq_idx = find_top_level_assign_eq_on_line(tokens, name_idx + 1, line_end) orelse return null;
    if (eq_idx == name_idx + 1) return infer_bool_from_assignment_rhs(tokens, name_idx, eq_idx + 1, line_end);
    return is_bool_type_spec(tokens, name_idx + 1, eq_idx);
}



pub fn infer_bool_from_assignment_rhs(tokens: []const lexer.Token, name_idx: usize, rhs_start: usize, line_end: usize) ?bool {
    if (rhs_start + 5 > line_end) return null;
    if (!tok_eq(tokens[rhs_start], "get")) return null;
    if (!tok_eq(tokens[rhs_start + 1], "(")) return null;
    if (tokens[rhs_start + 2].kind != .ident) return null;
    if (!tok_eq(tokens[rhs_start + 3], ",")) return null;
    if (tokens[rhs_start + 4].kind != .ident) return null;
    if (tokens[rhs_start + 4].lexeme.len < 2 or tokens[rhs_start + 4].lexeme[0] != '.') return null;
    if (rhs_start + 6 != line_end or !tok_eq(tokens[rhs_start + 5], ")")) return null;

    const source_name = tokens[rhs_start + 2].lexeme;
    const source_type = find_nearest_value_type_name(tokens, name_idx, source_name) orelse return null;
    return find_struct_field_bool_type(tokens, source_type, tokens[rhs_start + 4].lexeme[1..]);
}



pub fn find_struct_field_bool_type(tokens: []const lexer.Token, type_name: []const u8, field_name: []const u8) ?bool {
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
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, public_type_name(tokens[i].lexeme), type_name)) continue;
        if (i + 1 >= tokens.len or !tok_eq(tokens[i + 1], "{")) continue;

        const close_idx = find_matching(tokens, i + 1, "{", "}") catch return null;
        return find_field_bool_type(tokens, i + 2, close_idx, field_name);
    }
    return null;
}



pub fn find_field_bool_type(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, field_name: []const u8) ?bool {
    var i = start_idx;
    while (i < end_idx) {
        if (tokens[i].kind != .ident) {
            i += 1;
            continue;
        }
        const name = if (tokens[i].lexeme.len != 0 and tokens[i].lexeme[0] == '.') tokens[i].lexeme[1..] else tokens[i].lexeme;
        const type_start = i + 1;
        const line_end = @min(find_line_end_idx(tokens, i), end_idx);
        const type_end = find_top_level_assign_eq_on_line(tokens, type_start, line_end) orelse line_end;
        if (std.mem.eql(u8, name, field_name)) return is_bool_type_spec(tokens, type_start, type_end);
        i = line_end;
    }
    return null;
}



pub fn is_bool_type_spec(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    return end_idx == start_idx + 1 and tok_eq(tokens[start_idx], "bool");
}



pub fn classify_call_bool(
    allocator: std.mem.Allocator,
    funcs: []const FuncShape,
    tokens: []const lexer.Token,
    node: parser.ExprNode,
) !KnownBool {
    const call = node.data.call;
    if (is_builtin_bool_call(call.func_name)) return .yes;

    const call_start = node.start_tok;
    const open_paren = call_open_paren_idx(tokens, call_start, node.end_tok) orelse return .unknown;

    const args_start = open_paren + 1;
    const args_end = node.end_tok - 1;
    const args = try parse_call_arg_shapes(allocator, tokens, args_start, args_end);
    defer free_call_arg_shapes(allocator, args);

    var matched_fixed_count: usize = 0;
    var fixed_return_type: ?[]const u8 = null;
    var best_variadic_min: ?usize = null;
    var best_variadic_count: usize = 0;
    var variadic_return_type: ?[]const u8 = null;

    for (funcs) |func| {
        if (!std.mem.eql(u8, func.name, call.func_name)) continue;
        if (!call_arity_compatible_with_func(func, args.len)) continue;
        if (!condition_call_args_match_func(tokens, func, args, call_start)) continue;
        if (func.param_max != null) {
            matched_fixed_count += 1;
            fixed_return_type = func.return_type;
            continue;
        }
        if (best_variadic_min == null or func.param_min > best_variadic_min.?) {
            best_variadic_min = func.param_min;
            best_variadic_count = 1;
            variadic_return_type = func.return_type;
            continue;
        }
        if (func.param_min == best_variadic_min.?) best_variadic_count += 1;
    }

    if (matched_fixed_count > 1) return .no_matching_call;
    if (matched_fixed_count == 1) {
        const return_type = fixed_return_type orelse return .no;
        return if (std.mem.eql(u8, return_type, "bool")) .yes else .no;
    }
    if (best_variadic_min == null) return .unknown;
    if (best_variadic_count > 1) return .no_matching_call;
    const return_type = variadic_return_type orelse return .no;
    return if (std.mem.eql(u8, return_type, "bool")) .yes else .no;
}



pub fn condition_call_args_match_func(
    tokens: []const lexer.Token,
    func: FuncShape,
    args: []const CallArgShape,
    call_start: usize,
) bool {
    for (args, 0..) |arg, arg_index| {
        if (arg_index >= func.param_shapes.len) return false;
        switch (func.param_shapes[arg_index]) {
            .other => continue,
            .func => continue,
            .value => |param_type| {
                const expected = param_type orelse continue;
                const actual = condition_call_arg_value_type(tokens, arg, call_start) orelse continue;
                if (!std.mem.eql(u8, actual, expected)) return false;
            },
            .variadic => |param_type| {
                const expected = param_type orelse continue;
                const actual = condition_call_arg_value_type(tokens, arg, call_start) orelse continue;
                if (!std.mem.eql(u8, actual, expected)) return false;
            },
        }
    }
    return true;
}



pub fn condition_call_arg_value_type(tokens: []const lexer.Token, arg: CallArgShape, call_start: usize) ?[]const u8 {
    return switch (arg) {
        .ident => |name| find_nearest_value_type_name(tokens, call_start, name),
        else => null,
    };
}



pub fn is_builtin_bool_call(name: []const u8) bool {
    const builtin = [_][]const u8{
        "is",
        "eq",
        "ne",
        "lt",
        "le",
        "gt",
        "ge",
        "and",
        "or",
        "not",
    };
    for (builtin) |it| {
        if (std.mem.eql(u8, it, name)) return true;
    }
    return false;
}



pub fn find_direct_call_at_root(program: parser.Program, root_idx: usize) ?DirectCallSite {
    if (root_idx >= program.expr_nodes.len) return null;
    const node = program.expr_nodes[root_idx];

    return switch (node.kind) {
        .call => .{
            .call = node.data.call,
            .start_tok_idx = node.start_tok,
        },
        else => null,
    };
}



pub fn root_expr_return_arity(program: parser.Program, root_idx: usize) ReturnArityResolve {
    if (root_idx >= program.expr_nodes.len) return .{ .arity = 1 };
    const node = program.expr_nodes[root_idx];

    return switch (node.kind) {
        .call => resolve_call_return_arity(
            program.func_sigs,
            node.data.call.func_name,
            node.data.call.arg_count,
        ),
        else => .{ .arity = 1 },
    };
}



pub fn resolve_call_return_arity(
    func_sigs: []const parser.FuncSig,
    func_name: []const u8,
    arg_count: usize,
) ReturnArityResolve {
    var matched_arity: ?usize = null;

    for (func_sigs) |sig| {
        if (!std.mem.eql(u8, sig.name, func_name)) continue;
        if (!is_arg_count_compatible(sig, arg_count)) continue;

        if (matched_arity) |arity| {
            if (arity != sig.return_arity) return .ambiguous;
            continue;
        }
        matched_arity = sig.return_arity;
    }

    if (matched_arity) |arity| return .{ .arity = arity };
    return .unknown;
}



pub fn value_expr_allows_arity_at(program: parser.Program, start_tok: usize, arity: usize) bool {
    for (program.value_exprs) |site| {
        if (site.expected_arity != arity) continue;
        if (site.context != .assign and site.context != .return_value) continue;
        if (!root_expr_matches_call_start(program, site.root_expr_idx, start_tok)) continue;
        return true;
    }
    return false;
}



pub fn root_expr_matches_call_start(program: parser.Program, root_idx: usize, start_tok: usize) bool {
    if (root_idx >= program.expr_nodes.len) return false;
    const node = program.expr_nodes[root_idx];
    return switch (node.kind) {
        .call => node.start_tok == start_tok,
        else => false,
    };
}



pub fn is_arg_count_compatible(sig: parser.FuncSig, arg_count: usize) bool {
    if (arg_count < sig.param_min) return false;
    if (sig.param_max) |max_count| {
        return arg_count <= max_count;
    }
    return true;
}
