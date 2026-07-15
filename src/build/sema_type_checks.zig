//! Semantic analysis — type checks.
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema_error = @import("sema_error.zig");
const type_util = @import("type_name.zig");
const sema_tokens = @import("sema_tokens.zig");
const sema_shapes = @import("sema_shapes.zig");
const sema_function_support = @import("sema_function_support.zig");

const call_arg_info = sema_tokens.call_arg_info;
const count_type_args = sema_tokens.count_type_args;
const enum_decl_assign_idx = sema_tokens.enum_decl_assign_idx;
const enum_decl_has_branch = sema_tokens.enum_decl_has_branch;
const find_constraint_block_start_before = sema_tokens.find_constraint_block_start_before;
const find_enclosing_call_open = sema_tokens.find_enclosing_call_open;
const find_line_end_idx = sema_tokens.find_line_end_idx;
const find_matching = sema_tokens.find_matching;
const find_struct_field_type_end = sema_tokens.find_struct_field_type_end;
const find_top_level_assign_eq_on_line = sema_tokens.find_top_level_assign_eq_on_line;
const has_concrete_type_name = sema_function_support.has_concrete_type_name;
const has_return_arrow_before_on_line = sema_tokens.has_return_arrow_before_on_line;
const has_type_constraint_name = sema_tokens.has_type_constraint_name;
const is_arrow_at = sema_tokens.is_arrow_at;
const is_base_type_name = sema_tokens.is_base_type_name;
const is_error_enum_decl_start = sema_tokens.is_error_enum_decl_start;
const is_error_type_name = sema_tokens.is_error_type_name;
const is_func_decl_start = sema_tokens.is_func_decl_start;
const is_func_type_range = sema_tokens.is_func_type_range;
const is_imported_upper_alias = sema_function_support.is_imported_upper_alias;
const is_keyword = sema_tokens.is_keyword;
const is_local_payload_enum_case = sema_function_support.is_local_payload_enum_case;
const is_lower_ident_name = sema_tokens.is_lower_ident_name;
const is_modern_import_assign = sema_tokens.is_modern_import_assign;
const is_non_assign_equal = sema_tokens.is_non_assign_equal;
const is_payload_enum_decl_start = sema_tokens.is_payload_enum_decl_start;
const is_readonly_ident_name = sema_tokens.is_readonly_ident_name;
const is_reserved_func_name = sema_tokens.is_reserved_func_name;
const is_return_arrow_at = sema_tokens.is_return_arrow_at;
const is_spread_token = sema_tokens.is_spread_token;
const is_struct_decl_start = sema_tokens.is_struct_decl_start;
const is_struct_field_name = sema_tokens.is_struct_field_name;
const is_top_level_decl_head = sema_tokens.is_top_level_decl_head;
const is_type_decl_start = sema_tokens.is_type_decl_start;
const is_valid_declared_type_name = sema_tokens.is_valid_declared_type_name;
const is_valid_enum_branch_name = sema_tokens.is_valid_enum_branch_name;
const is_value_enum_decl_start = sema_tokens.is_value_enum_decl_start;
const is_wit_only_source_type_name = sema_tokens.is_wit_only_source_type_name;
const line_start_idx = sema_tokens.line_start_idx;
const local_struct_type_param_count = sema_function_support.local_struct_type_param_count;
const mark_error_at = sema_tokens.mark_error_at;
const parse_import_decl_end = sema_function_support.parse_import_decl_end;
const skip_top_level_import_brace = sema_function_support.skip_top_level_import_brace;
const public_type_name = sema_tokens.public_type_name;
const tok_eq = sema_tokens.tok_eq;
const validate_is_type_expr = sema_tokens.validate_is_type_expr;

pub fn check_type_decl_naming(tokens: []const lexer.Token) !void {
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
        if (!is_type_decl_start(tokens, i)) continue;
        if ((is_error_type_name(t.lexeme) or is_private_error_type_name(t.lexeme)) and is_struct_decl_start(tokens, i)) {
            return mark_error_at(tokens, i, error.InvalidTypeDeclName);
        }
        if (is_valid_declared_type_name(t.lexeme)) continue;
        return mark_error_at(tokens, i, error.InvalidTypeDeclName);
    }
}
pub fn check_type_decl_name_conflicts(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
    var seen = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer seen.deinit(allocator);

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
        if (!is_type_decl_start(tokens, i)) continue;
        if (!is_valid_declared_type_name(tokens[i].lexeme)) continue;

        const name = public_type_name(tokens[i].lexeme);
        for (seen.items) |prev| {
            if (std.mem.eql(u8, prev, name)) {
                return mark_error_at(tokens, i, error.DuplicateTypeDeclName);
            }
        }
        try seen.append(allocator, name);
    }
}


pub fn check_error_decl_branches(tokens: []const lexer.Token) !void {
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
        if (is_private_error_type_name(tokens[i].lexeme) and i + 1 < tokens.len and
            (tok_eq(tokens[i + 1], "=") or tok_eq(tokens[i + 1], "error")))
        {
            return mark_error_at(tokens, i, error.InvalidErrorBranchName);
        }
        if (is_error_type_name(tokens[i].lexeme)) {
            if (!is_error_enum_decl_start(tokens, i)) {
                if (is_type_decl_start(tokens, i)) return mark_error_at(tokens, i, error.InvalidErrorBranchName);
                continue;
            }

            try validate_error_enum_branches(tokens, i, i + 3);
            i = find_line_end_idx(tokens, i) - 1;
            continue;
        }
        if (is_value_enum_decl_start(tokens, i)) {
            try validate_value_enum_branches(tokens, i, i + 3);
            i = find_line_end_idx(tokens, i) - 1;
            continue;
        }
        if (is_payload_enum_decl_start(tokens, i)) {
            try validate_payload_enum_branches(tokens, i, i + 2);
            i = find_line_end_idx(tokens, i) - 1;
            continue;
        }
    }
}


fn validate_error_enum_branches(tokens: []const lexer.Token, enum_idx: usize, start_idx: usize) !void {
    const line_end = find_line_end_idx(tokens, enum_idx);
    var expect_branch = true;
    var j = start_idx;
    while (j < line_end) : (j += 1) {
        if (!expect_branch) {
            if (!tok_eq(tokens[j], "|")) return mark_error_at(tokens, j, error.InvalidErrorBranchName);
            expect_branch = true;
            continue;
        }
        if (!is_valid_error_branch_name(tokens[j])) return mark_error_at(tokens, j, error.InvalidErrorBranchName);
        if (has_visible_enum_branch_name_conflict(tokens, j, public_type_name(tokens[j].lexeme))) {
            return mark_error_at(tokens, j, error.InvalidErrorBranchName);
        }
        expect_branch = false;
    }
    if (expect_branch) return mark_error_at(tokens, line_end - 1, error.InvalidErrorBranchName);
}


fn validate_value_enum_branches(tokens: []const lexer.Token, enum_idx: usize, start_idx: usize) !void {
    const line_end = find_line_end_idx(tokens, enum_idx);
    var expect_branch = true;
    var j = start_idx;
    while (j < line_end) {
        if (!expect_branch) {
            if (!tok_eq(tokens[j], "|")) return mark_error_at(tokens, j, error.InvalidErrorBranchName);
            expect_branch = true;
            j += 1;
            continue;
        }
        if (!is_valid_enum_branch_name(tokens[j])) return mark_error_at(tokens, j, error.InvalidErrorBranchName);
        if (has_prior_enum_branch_name(tokens, start_idx, j, public_type_name(tokens[j].lexeme))) {
            return mark_error_at(tokens, j, error.InvalidErrorBranchName);
        }
        if (has_visible_enum_branch_name_conflict(tokens, j, public_type_name(tokens[j].lexeme))) {
            return mark_error_at(tokens, j, error.InvalidErrorBranchName);
        }
        if (j + 4 > line_end or !tok_eq(tokens[j + 1], "(") or !tok_eq(tokens[j + 3], ")")) {
            return mark_error_at(tokens, j, error.InvalidErrorBranchName);
        }
        if (tokens[j + 2].kind != .number) return mark_error_at(tokens, j + 2, error.InvalidErrorBranchName);
        const value = parse_enum_carrier_value(tokens[j + 2].lexeme) orelse return mark_error_at(tokens, j + 2, error.InvalidErrorBranchName);
        if (!enum_carrier_value_in_range(tokens[enum_idx + 1].lexeme, value)) {
            return mark_error_at(tokens, j + 2, error.InvalidErrorBranchName);
        }
        if (has_prior_enum_carrier_value(tokens, start_idx, j, value)) {
            return mark_error_at(tokens, j + 2, error.InvalidErrorBranchName);
        }
        j += 4;
        expect_branch = false;
    }
    if (expect_branch) return mark_error_at(tokens, line_end - 1, error.InvalidErrorBranchName);
}


fn validate_payload_enum_branches(tokens: []const lexer.Token, enum_idx: usize, start_idx: usize) !void {
    const line_end = find_line_end_idx(tokens, enum_idx);
    var expect_branch = true;
    var j = start_idx;
    while (j < line_end) {
        if (!expect_branch) {
            if (!tok_eq(tokens[j], "|")) return mark_error_at(tokens, j, error.InvalidErrorBranchName);
            expect_branch = true;
            j += 1;
            continue;
        }
        if (!is_valid_enum_branch_name(tokens[j])) return mark_error_at(tokens, j, error.InvalidErrorBranchName);
        if (has_prior_enum_branch_name(tokens, start_idx, j, public_type_name(tokens[j].lexeme))) {
            return mark_error_at(tokens, j, error.InvalidErrorBranchName);
        }
        if (has_visible_enum_branch_name_conflict(tokens, j, public_type_name(tokens[j].lexeme))) {
            return mark_error_at(tokens, j, error.InvalidErrorBranchName);
        }
        j += 1;
        if (j < line_end and tok_eq(tokens[j], "(")) {
            const close = find_matching(tokens, j, "(", ")") catch
                return mark_error_at(tokens, j, error.InvalidErrorBranchName);
            if (close <= j + 1) return mark_error_at(tokens, j, error.InvalidErrorBranchName);
            // No value-enum style numeric carriers in payload enums.
            if (close == j + 2 and tokens[j + 1].kind == .number) {
                return mark_error_at(tokens, j + 1, error.InvalidErrorBranchName);
            }
            if (tokens[j + 1].kind == .number or tokens[j + 1].kind == .string) {
                return mark_error_at(tokens, j + 1, error.InvalidErrorBranchName);
            }
            if (validate_is_type_expr(tokens, j + 1, close) != close) {
                return mark_error_at(tokens, j + 1, error.InvalidErrorBranchName);
            }
            j = close + 1;
        }
        expect_branch = false;
    }
    if (expect_branch) return mark_error_at(tokens, line_end - 1, error.InvalidErrorBranchName);
}


fn has_prior_enum_branch_name(tokens: []const lexer.Token, start_idx: usize, before_idx: usize, name: []const u8) bool {
    var j = start_idx;
    while (j < before_idx) : (j += 1) {
        if (tokens[j].kind != .ident) continue;
        if (!std.mem.eql(u8, public_type_name(tokens[j].lexeme), name)) continue;
        return true;
    }
    return false;
}


fn has_visible_enum_branch_name_conflict(tokens: []const lexer.Token, branch_idx: usize, name: []const u8) bool {
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

        if (is_modern_import_assign(tokens, i)) {
            if (is_valid_declared_type_name(tokens[i].lexeme) and std.mem.eql(u8, public_type_name(tokens[i].lexeme), name)) {
                return true;
            }
            i = (parse_import_decl_end(tokens, i) orelse find_line_end_idx(tokens, i)) - 1;
            continue;
        }

        if (is_type_decl_start(tokens, i) and is_valid_declared_type_name(tokens[i].lexeme)) {
            if (std.mem.eql(u8, public_type_name(tokens[i].lexeme), name)) return true;
        }

        if (!is_error_enum_decl_start(tokens, i) and !is_value_enum_decl_start(tokens, i) and !is_payload_enum_decl_start(tokens, i)) continue;
        if (enum_decl_has_prior_branch(tokens, i, branch_idx, name)) return true;
        i = find_line_end_idx(tokens, i) - 1;
    }
    return false;
}


fn enum_decl_has_prior_branch(tokens: []const lexer.Token, decl_start_idx: usize, branch_idx: usize, name: []const u8) bool {
    const eq_idx = enum_decl_assign_idx(tokens, decl_start_idx) orelse return false;
    const line_end = find_line_end_idx(tokens, decl_start_idx);

    var i = eq_idx + 1;
    var expect_branch = true;
    while (i < line_end) : (i += 1) {
        if (!expect_branch) {
            if (tok_eq(tokens[i], "|")) expect_branch = true;
            continue;
        }
        if (tokens[i].kind != .ident) continue;
        if (i >= branch_idx) return false;
        if (std.mem.eql(u8, public_type_name(tokens[i].lexeme), name)) return true;
        expect_branch = false;
    }
    return false;
}


fn has_prior_enum_carrier_value(tokens: []const lexer.Token, start_idx: usize, before_idx: usize, value: i128) bool {
    var j = start_idx;
    while (j + 3 < before_idx) {
        if (tokens[j].kind == .ident and tok_eq(tokens[j + 1], "(") and tokens[j + 2].kind == .number and tok_eq(tokens[j + 3], ")")) {
            if (parse_enum_carrier_value(tokens[j + 2].lexeme)) |prev| {
                if (prev == value) return true;
            }
            j += 4;
            continue;
        }
        j += 1;
    }
    return false;
}


fn parse_enum_carrier_value(raw: []const u8) ?i128 {
    return std.fmt.parseInt(i128, raw, 10) catch null;
}


fn enum_carrier_value_in_range(carrier: []const u8, value: i128) bool {
    if (std.mem.eql(u8, carrier, "i8")) return value >= -128 and value <= 127;
    if (std.mem.eql(u8, carrier, "i16")) return value >= -32768 and value <= 32767;
    if (std.mem.eql(u8, carrier, "i32")) return value >= -2147483648 and value <= 2147483647;
    if (std.mem.eql(u8, carrier, "isize")) return value >= -2147483648 and value <= 2147483647;
    if (std.mem.eql(u8, carrier, "i64")) {
        return value >= -9223372036854775808 and value <= 9223372036854775807;
    }
    if (std.mem.eql(u8, carrier, "u8")) return value >= 0 and value <= 255;
    if (std.mem.eql(u8, carrier, "u16")) return value >= 0 and value <= 65535;
    if (std.mem.eql(u8, carrier, "u32")) return value >= 0 and value <= 4294967295;
    if (std.mem.eql(u8, carrier, "usize")) return value >= 0 and value <= 4294967295;
    if (std.mem.eql(u8, carrier, "u64")) return value >= 0 and value <= 18446744073709551615;
    return false;
}


fn is_valid_error_branch_name(tok: lexer.Token) bool {
    if (tok.kind != .ident) return false;
    if (!is_valid_declared_type_name(tok.lexeme)) return false;
    if (std.mem.eql(u8, tok.lexeme, "Error")) return false;
    if (is_error_type_name(tok.lexeme)) return false;
    return true;
}


fn is_private_error_type_name(name: []const u8) bool {
    if (name.len < 2 or name[0] != '.') return false;
    return is_error_type_name(name[1..]);
}


pub fn check_synth_error_type_positions(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, tokens[i].lexeme, "Error")) continue;

        const line_start = line_start_idx(tokens, i);
        if (line_start == i and is_modern_import_assign(tokens, i)) {
            i = find_line_end_idx(tokens, i) - 1;
            continue;
        }
        return mark_error_at(tokens, i, error.InvalidSynthErrorType);
    }
}


pub fn check_upper_value_exprs(program: parser.Program, tokens: []const lexer.Token) !void {
    for (program.expr_nodes) |node| {
        if (node.kind != .ident) continue;
        const tok = tokens[node.start_tok];
        if (!is_valid_declared_type_name(tok.lexeme)) continue;
        if (is_type_constructor_expr(tokens, node.start_tok)) continue;
        if (is_payload_enum_case_ctor_expr(tokens, node.start_tok)) continue;
        if (is_local_error_branch_value(tokens, tok.lexeme)) continue;
        if (is_imported_upper_alias(tokens, tok.lexeme)) continue;
        return mark_error_at(tokens, node.start_tok, error.InvalidTypeRef);
    }
}


fn is_type_constructor_expr(tokens: []const lexer.Token, start_idx: usize) bool {
    var idx = start_idx + 1;
    if (idx < tokens.len and tok_eq(tokens[idx], "<")) {
        const close_angle = find_matching(tokens, idx, "<", ">") catch return false;
        idx = close_angle + 1;
    }
    return idx < tokens.len and tok_eq(tokens[idx], "{");
}

/// `Text(buf)` / unit case `Quit` used as payload-enum constructor.

/// `Text(buf)` / unit case `Quit` used as payload-enum constructor.
fn is_payload_enum_case_ctor_expr(tokens: []const lexer.Token, start_idx: usize) bool {
    if (start_idx >= tokens.len or tokens[start_idx].kind != .ident) return false;
    const name = public_type_name(tokens[start_idx].lexeme);
    if (!is_local_payload_enum_case(tokens, name)) return false;
    // Unit case: bare Ident. Payload case: Ident(expr).
    if (start_idx + 1 < tokens.len and tok_eq(tokens[start_idx + 1], "(")) return true;
    return true;
}


fn is_local_error_branch_value(tokens: []const lexer.Token, name: []const u8) bool {
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
        if (!is_error_enum_decl_start(tokens, i) and !is_value_enum_decl_start(tokens, i) and !is_payload_enum_decl_start(tokens, i)) continue;
        if (enum_decl_has_branch(tokens, i, name)) return true;
    }
    return false;
}


pub fn check_top_value_decl_names(tokens: []const lexer.Token) !void {
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
        if (is_top_level_decl_head(tokens, i) and is_type_decl_start(tokens, i)) continue;
        if (i + 1 < tokens.len and tok_eq(tokens[i + 1], "(")) continue;

        const line_end = find_line_end_idx(tokens, i);
        const eq_idx = find_top_level_assign_eq_on_line(tokens, i + 1, line_end) orelse continue;
        if (eq_idx <= i + 1) return mark_error_at(tokens, i, error.InvalidBindingName);
        if (is_valid_top_value_decl_name(t.lexeme)) continue;
        return mark_error_at(tokens, i, error.InvalidBindingName);
    }
}


fn is_valid_top_value_decl_name(name: []const u8) bool {
    if (is_readonly_ident_name(name)) return true;
    if (is_lower_ident_name(name) and !is_reserved_func_name(name)) return true;
    return name.len > 1 and name[0] == '.' and is_lower_ident_name(name[1..]) and !is_reserved_func_name(name[1..]);
}


pub fn check_type_refs(tokens: []const lexer.Token) !void {
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
        if (t.lexeme.len < 2 or t.lexeme[0] != '.') continue;
        if (!std.ascii.isUpper(t.lexeme[1])) continue;
        if (is_top_level_decl_head(tokens, i) and is_type_decl_start(tokens, i)) continue;
        if (is_value_enum_branch_decl_token(tokens, i)) continue;
        return mark_error_at(tokens, i, error.InvalidTypeRef);
    }
}


pub fn check_forbidden_source_type_names(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (!is_forbidden_source_type_name(tokens[i].lexeme)) continue;
        if (!is_source_type_name_context(tokens, i)) continue;
        return mark_error_at(tokens, i, error.InvalidTypeRef);
    }
}


fn is_forbidden_source_type_name(name: []const u8) bool {
    return is_wit_only_source_type_name(name);
}


fn is_source_type_name_context(tokens: []const lexer.Token, idx: usize) bool {
    if (is_inside_host_import_call(tokens, idx)) return false;
    if (is_second_is_arg(tokens, idx)) return true;

    if (idx > 0 and tokens[idx - 1].line == tokens[idx].line) {
        const prev = tokens[idx - 1];
        if (tok_eq(prev, "=")) return is_type_decl_or_constraint_line(tokens, idx);
        if (tok_eq(prev, "[") or tok_eq(prev, "<") or tok_eq(prev, "|") or tok_eq(prev, ",")) return true;
        if (idx >= 2 and is_return_arrow_at(tokens, idx - 2)) return true;
        if (prev.kind == .ident and !is_keyword(prev.lexeme)) return true;
        if (is_spread_token(prev)) return true;
    }

    if (idx + 1 < tokens.len and tokens[idx + 1].line == tokens[idx].line) {
        const next = tokens[idx + 1];
        if (tok_eq(next, "]") or tok_eq(next, ">") or tok_eq(next, "|") or tok_eq(next, ",") or tok_eq(next, "{")) return true;
    }

    return false;
}


fn is_inside_host_import_call(tokens: []const lexer.Token, idx: usize) bool {
    const open_idx = find_enclosing_call_open(tokens, idx) orelse return false;
    if (open_idx < 2) return false;
    if (!tok_eq(tokens[open_idx - 2], "@")) return false;
    if (tokens[open_idx - 1].kind != .ident) return false;
    const name = tokens[open_idx - 1].lexeme;
    return std.mem.eql(u8, name, "host");
}


fn is_value_enum_branch_decl_token(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 2 >= tokens.len) return false;
    if (!tok_eq(tokens[idx + 1], "(")) return false;

    var line_start = idx;
    while (line_start > 0 and tokens[line_start - 1].line == tokens[idx].line) {
        line_start -= 1;
    }
    if (!is_value_enum_decl_start(tokens, line_start)) return false;

    const branch_start = line_start + 3;
    if (idx == branch_start) return true;
    return idx > branch_start and tok_eq(tokens[idx - 1], "|");
}


pub fn check_bare_nil_types(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tok_eq(tokens[i], "nil")) continue;
        if (is_nil_union_branch(tokens, i)) {
            if (has_duplicate_nil_in_union_segment(tokens, i)) {
                return mark_error_at(tokens, i, error.InvalidTypeRef);
            }
            continue;
        }
        if (is_nil_return_spec(tokens, i)) continue;
        if (is_parenthesized_nil_type(tokens, i)) return mark_error_at(tokens, i, error.InvalidTypeRef);
        if (is_untyped_nil_assignment(tokens, i)) return mark_error_at(tokens, i, error.InvalidTypeRef);
        if (!is_bare_nil_type_context(tokens, i)) continue;
        return mark_error_at(tokens, i, error.InvalidTypeRef);
    }
}


fn is_parenthesized_nil_type(tokens: []const lexer.Token, idx: usize) bool {
    if (idx == 0 or idx + 1 >= tokens.len) return false;
    if (tokens[idx - 1].line != tokens[idx].line or tokens[idx + 1].line != tokens[idx].line) return false;
    if (!tok_eq(tokens[idx - 1], "(") or !tok_eq(tokens[idx + 1], ")")) return false;
    const close_idx = find_matching_open(tokens, idx + 1, "(", ")") orelse return false;
    return close_idx == idx - 1;
}


fn is_untyped_nil_assignment(tokens: []const lexer.Token, idx: usize) bool {
    if (idx == 0 or tokens[idx - 1].line != tokens[idx].line) return false;
    const eq_idx = idx - 1;
    if (!tok_eq(tokens[eq_idx], "=") or is_non_assign_equal(tokens, eq_idx)) return false;

    const line_start = line_start_idx(tokens, idx);
    const line_end = find_line_end_idx(tokens, idx);
    const assign_eq = find_top_level_assign_eq_on_line(tokens, line_start, line_end) orelse return false;
    if (assign_eq != eq_idx) return false;
    if (idx + 1 != line_end) return false;
    return !assignment_lhs_has_type_annotation(tokens, line_start, eq_idx);
}


fn assignment_lhs_has_type_annotation(tokens: []const lexer.Token, start_idx: usize, eq_idx: usize) bool {
    var i = start_idx + 1;
    while (i < eq_idx) : (i += 1) {
        if (is_type_atom_start(tokens[i])) return true;
        if (is_spread_token(tokens[i])) return true;
    }
    return false;
}


pub fn check_parenthesized_type_args(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tok_eq(tokens[i], "(")) continue;
        if (!is_type_arg_start_after_separator(tokens, i)) continue;
        return mark_error_at(tokens, i, error.InvalidTypeRef);
    }
}


pub fn check_parenthesized_types(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tok_eq(tokens[i], "(")) continue;
        if (is_fields_loop_source_type_paren(tokens, i)) continue;
        if (is_func_type_start(tokens, i)) continue;
        if (is_payload_enum_case_payload_paren(tokens, i)) continue;
        const close_idx = find_matching(tokens, i, "(", ")") catch continue;
        if (!is_parenthesized_type_context(tokens, i, close_idx)) continue;
        if (!is_type_expr_range_allow_parens(tokens, i + 1, close_idx)) continue;
        return mark_error_at(tokens, i, error.InvalidTypeRef);
    }
}

/// `Text([u8])` payload paren on a payload-enum case arm.

/// `Text([u8])` payload paren on a payload-enum case arm.
fn is_payload_enum_case_payload_paren(tokens: []const lexer.Token, open_idx: usize) bool {
    if (open_idx == 0) return false;
    if (tokens[open_idx - 1].kind != .ident) return false;
    if (tokens[open_idx - 1].line != tokens[open_idx].line) return false;
    if (!is_valid_enum_branch_name(tokens[open_idx - 1])) return false;

    const line_start = line_start_idx(tokens, open_idx);
    if (!is_payload_enum_decl_start(tokens, line_start)) return false;

    // Case must be at case position after `=` / `|`.
    const case_idx = open_idx - 1;
    if (case_idx == line_start + 2) return true; // first case after Name =
    if (case_idx > line_start + 2 and tok_eq(tokens[case_idx - 1], "|")) return true;
    return false;
}


fn is_fields_loop_source_type_paren(tokens: []const lexer.Token, open_idx: usize) bool {
    if (open_idx == 0 or tokens[open_idx - 1].line != tokens[open_idx].line) return false;
    if (tokens[open_idx - 1].kind != .ident or !std.mem.eql(u8, tokens[open_idx - 1].lexeme, "fields")) return false;
    const close_idx = find_matching(tokens, open_idx, "(", ")") catch return false;
    if (open_idx + 2 != close_idx) return false;
    if (tokens[open_idx + 1].kind != .ident or !is_valid_declared_type_name(tokens[open_idx + 1].lexeme)) return false;
    if (close_idx + 1 >= tokens.len or tokens[close_idx + 1].line != tokens[open_idx].line or !tok_eq(tokens[close_idx + 1], "{")) return false;

    const line_start = line_start_idx(tokens, open_idx);
    const line_end = find_line_end_idx(tokens, open_idx);
    if (!tok_eq(tokens[line_start], "loop")) return false;
    const bind_idx = find_top_level_assign_eq_on_line(tokens, line_start + 1, line_end) orelse return false;
    if (bind_idx + 1 != open_idx - 1) return false;
    if (line_start + 2 != bind_idx) return false;
    return tokens[line_start + 1].kind == .ident and !is_keyword(tokens[line_start + 1].lexeme);
}


fn is_parenthesized_type_context(tokens: []const lexer.Token, open_idx: usize, close_idx: usize) bool {
    const prev_idx = previous_token_same_line(tokens, open_idx) orelse return false;
    const prev = tokens[prev_idx];

    if (tok_eq(prev, "[") or tok_eq(prev, "<") or tok_eq(prev, "|")) return true;
    if (tok_eq(prev, "=")) return is_type_decl_or_constraint_line(tokens, open_idx);
    if (tok_eq(prev, ">") and prev_idx > 0 and tok_eq(tokens[prev_idx - 1], "-")) return true;
    if (tok_eq(prev, ",") and has_return_arrow_before_on_line(tokens, open_idx)) return true;
    if (tok_eq(prev, ",") and is_inside_func_type_param_list(tokens, open_idx)) return true;
    if (tok_eq(prev, ",") and is_second_is_arg(tokens, open_idx)) return true;
    if (tok_eq(prev, "(") and is_inside_func_type_param_list(tokens, open_idx)) return true;
    if (is_spread_token(prev)) return true;
    if (prev.kind == .ident and can_parenthesized_type_follow_name(tokens, close_idx)) return true;
    return false;
}


fn previous_token_same_line(tokens: []const lexer.Token, idx: usize) ?usize {
    if (idx == 0) return null;
    const prev_idx = idx - 1;
    if (tokens[prev_idx].line != tokens[idx].line) return null;
    return prev_idx;
}


fn can_parenthesized_type_follow_name(tokens: []const lexer.Token, close_idx: usize) bool {
    const next_idx = close_idx + 1;
    if (next_idx >= tokens.len) return true;
    if (tokens[next_idx].line != tokens[close_idx].line) return true;
    const next = tokens[next_idx];
    if (tok_eq(next, "=") or tok_eq(next, "|") or tok_eq(next, ",") or tok_eq(next, ")") or tok_eq(next, "{")) return true;
    return false;
}


fn is_inside_func_type_param_list(tokens: []const lexer.Token, idx: usize) bool {
    var i = idx;
    while (i > 0 and tokens[i - 1].line == tokens[idx].line) {
        i -= 1;
        if (!tok_eq(tokens[i], "(")) continue;
        const close_idx = find_matching(tokens, i, "(", ")") catch continue;
        if (close_idx <= idx) continue;
        if (close_idx + 2 >= tokens.len) continue;
        if (is_return_arrow_at(tokens, close_idx + 1)) return true;
    }
    return false;
}


fn is_second_is_arg(tokens: []const lexer.Token, idx: usize) bool {
    const info = call_arg_info(tokens, idx) orelse return false;
    return std.mem.eql(u8, info.name, "is") and info.arg_index == 1;
}


fn is_type_expr_range_allow_parens(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx >= end_idx) return false;
    var idx = parse_type_atom_allow_parens(tokens, start_idx, end_idx) orelse return false;
    while (idx < end_idx) {
        if (!tok_eq(tokens[idx], "|")) return false;
        idx = parse_type_atom_allow_parens(tokens, idx + 1, end_idx) orelse return false;
    }
    return idx == end_idx;
}


fn parse_type_atom_allow_parens(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (start_idx >= end_idx) return null;

    if (tok_eq(tokens[start_idx], "(")) {
        if (is_func_type_start(tokens, start_idx)) return null;
        const close_idx = find_matching(tokens, start_idx, "(", ")") catch return null;
        if (close_idx >= end_idx) return null;
        if (!is_type_expr_range_allow_parens(tokens, start_idx + 1, close_idx)) return null;
        return close_idx + 1;
    }

    if (tok_eq(tokens[start_idx], "[")) {
        const close_idx = find_matching(tokens, start_idx, "[", "]") catch return null;
        if (close_idx >= end_idx) return null;
        if (!is_type_expr_range_allow_parens(tokens, start_idx + 1, close_idx)) return null;
        return close_idx + 1;
    }

    if (tokens[start_idx].kind != .ident) return null;
    if (!is_type_atom_name(tokens[start_idx].lexeme)) return null;

    var idx = start_idx + 1;
    if (idx < end_idx and tok_eq(tokens[idx], "<")) {
        const close_angle = find_matching(tokens, idx, "<", ">") catch return null;
        if (close_angle >= end_idx) return null;
        if (!is_type_arg_list_range(tokens, idx + 1, close_angle)) return null;
        idx = close_angle + 1;
    }
    return idx;
}


fn is_type_atom_name(name: []const u8) bool {
    if (is_base_type_name(name) or std.mem.eql(u8, name, "nil")) return true;
    return is_valid_declared_type_name(name);
}


fn is_type_arg_list_range(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx >= end_idx) return false;
    var idx = parse_type_atom_allow_parens(tokens, start_idx, end_idx) orelse return false;
    while (idx < end_idx) {
        if (!tok_eq(tokens[idx], "|") and !tok_eq(tokens[idx], ",")) return false;
        idx = parse_type_atom_allow_parens(tokens, idx + 1, end_idx) orelse return false;
    }
    return idx == end_idx;
}


pub fn check_generic_type_arg_arity(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (!is_valid_declared_type_name(tokens[i].lexeme)) continue;
        if (!tok_eq(tokens[i + 1], "<")) continue;

        const close_angle = find_matching(tokens, i + 1, "<", ">") catch continue;
        const type_name = public_type_name(tokens[i].lexeme);
        if (std.mem.eql(u8, type_name, "Tuple")) {
            const actual_count = count_type_args(tokens, i + 2, close_angle);
            if (actual_count < 2) return mark_error_at(tokens, i, error.InvalidTypeRef);
            i = close_angle;
            continue;
        }
        const expected_count = local_struct_type_param_count(tokens, type_name) orelse {
            if (is_local_non_struct_type_name(tokens, type_name)) return mark_error_at(tokens, i, error.InvalidTypeRef);
            i = close_angle;
            continue;
        };
        const actual_count = count_type_args(tokens, i + 2, close_angle);
        if (actual_count != expected_count) return mark_error_at(tokens, i, error.InvalidTypeRef);
        i = close_angle;
    }
}

/// Position-ctor arity for `Tuple<T0,...>{v0,...}` must equal type-arg count.
/// Nested ctors are scanned by not skipping the body after the outer ctor.
/// Named field inits are usually rejected earlier as InvalidStructLiteral by the parser;
/// this path remains as a defensive fallback (InvalidTypedLiteral).

fn is_local_non_struct_type_name(tokens: []const lexer.Token, name: []const u8) bool {
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
        if (is_modern_import_assign(tokens, i)) continue;
        if (!is_type_decl_start(tokens, i)) continue;
        return !is_struct_decl_start(tokens, i);
    }
    return false;
}


pub fn check_unbound_type_param_refs(tokens: []const lexer.Token) !void {
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

        if (is_func_decl_start(tokens, i)) {
            const close_paren = find_matching(tokens, i + 1, "(", ")") catch continue;
            try check_unbound_type_names_in_range(tokens, i, i + 2, close_paren);
            try check_unbound_type_names_in_range(tokens, i, close_paren + 1, find_func_decl_signature_end(tokens, close_paren + 1));
            i = close_paren;
            continue;
        }

        if (is_struct_decl_start(tokens, i)) {
            const close_brace = find_matching(tokens, i + 1, "{", "}") catch continue;
            try check_unbound_struct_field_type_names(tokens, i, i + 2, close_brace);
            i = close_brace;
        }
    }
}


fn check_unbound_struct_field_type_names(
    tokens: []const lexer.Token,
    decl_start_idx: usize,
    field_start: usize,
    field_end: usize,
) !void {
    var i = field_start;
    while (i < field_end) {
        const line_start = i;
        const line_end = @min(find_line_end_idx(tokens, i), field_end);
        if (line_start + 1 < line_end and tokens[line_start].kind == .ident and is_struct_field_name(tokens[line_start].lexeme)) {
            const type_end = find_struct_field_type_end(tokens, line_start + 1, line_end);
            try check_unbound_type_names_in_range(tokens, decl_start_idx, line_start + 1, type_end);
        }
        i = line_end;
    }
}


fn check_unbound_type_names_in_range(
    tokens: []const lexer.Token,
    decl_start_idx: usize,
    start_idx: usize,
    end_idx: usize,
) !void {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (is_wit_only_source_type_name(tokens[i].lexeme)) {
            return mark_error_at(tokens, i, error.InvalidTypeRef);
        }
        if (!is_valid_declared_type_name(tokens[i].lexeme)) continue;
        const name = public_type_name(tokens[i].lexeme);
        if (has_concrete_type_name(tokens, name)) continue;
        if (decl_has_type_constraint_name(tokens, decl_start_idx, name)) continue;
        if (!has_prior_type_constraint_name(tokens, decl_start_idx, name)) continue;
        return mark_error_at(tokens, i, error.InvalidTypeRef);
    }
}


fn decl_has_type_constraint_name(tokens: []const lexer.Token, decl_start_idx: usize, name: []const u8) bool {
    const block_start = find_constraint_block_start_before(tokens, decl_start_idx) orelse return false;
    return has_type_constraint_name(tokens, block_start, decl_start_idx, name);
}


fn has_prior_type_constraint_name(tokens: []const lexer.Token, before_idx: usize, name: []const u8) bool {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < before_idx and i < tokens.len) : (i += 1) {
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
        if (!tok_eq(tokens[i], "#")) continue;

        const line_end = find_line_end_idx(tokens, i);
        const is_func_constraint = i + 2 < line_end and tok_eq(tokens[i + 2], "(");
        if (!is_func_constraint and i + 1 < line_end and std.mem.eql(u8, tokens[i + 1].lexeme, name)) return true;
        i = line_end - 1;
    }
    return false;
}


fn find_func_decl_signature_end(tokens: []const lexer.Token, start_idx: usize) usize {
    var i = start_idx;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) return i;
        if (is_arrow_at(tokens, i)) return i;
    }
    return i;
}


fn is_type_arg_start_after_separator(tokens: []const lexer.Token, idx: usize) bool {
    if (idx == 0) return false;
    const prev = tokens[idx - 1];
    if (!tok_eq(prev, "<") and !tok_eq(prev, ",")) return false;
    return has_open_type_arg_angle_before(tokens, idx);
}


fn has_open_type_arg_angle_before(tokens: []const lexer.Token, idx: usize) bool {
    var depth_angle: usize = 0;
    var i = line_start_idx(tokens, idx);
    while (i < idx) : (i += 1) {
        if (tok_eq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (!tok_eq(tokens[i], ">")) continue;
        if (i > 0 and tok_eq(tokens[i - 1], "-")) continue;
        if (depth_angle > 0) depth_angle -= 1;
    }
    return depth_angle > 0;
}


fn is_nil_union_branch(tokens: []const lexer.Token, idx: usize) bool {
    if (idx > 0 and tokens[idx - 1].line == tokens[idx].line and tok_eq(tokens[idx - 1], "|")) return true;
    if (idx + 1 < tokens.len and tokens[idx + 1].line == tokens[idx].line and tok_eq(tokens[idx + 1], "|")) return true;
    return false;
}


fn has_duplicate_nil_in_union_segment(tokens: []const lexer.Token, idx: usize) bool {
    const start = nil_union_segment_start(tokens, idx);
    const end = nil_union_segment_end(tokens, idx);
    var nil_count: usize = 0;
    var saw_pipe = false;

    var i = start;
    while (i < end) : (i += 1) {
        if (tok_eq(tokens[i], "|")) {
            saw_pipe = true;
            continue;
        }
        if (tok_eq(tokens[i], "nil")) nil_count += 1;
    }

    return saw_pipe and nil_count > 1;
}


fn nil_union_segment_start(tokens: []const lexer.Token, idx: usize) usize {
    var start = idx;
    while (start > 0 and tokens[start - 1].line == tokens[idx].line) {
        if (is_nil_union_boundary_before(tokens, start)) break;
        start -= 1;
    }
    return start;
}


fn nil_union_segment_end(tokens: []const lexer.Token, idx: usize) usize {
    var end = idx + 1;
    while (end < tokens.len and tokens[end].line == tokens[idx].line) : (end += 1) {
        if (is_nil_union_boundary_token(tokens[end])) break;
        if (tok_eq(tokens[end], "{")) break;
    }
    return end;
}


fn is_nil_union_boundary_before(tokens: []const lexer.Token, idx: usize) bool {
    const prev = tokens[idx - 1];
    if (is_nil_union_boundary_token(prev)) return true;
    return idx >= 2 and tok_eq(tokens[idx - 2], "-") and tok_eq(tokens[idx - 1], ">");
}


fn is_nil_union_boundary_token(tok: lexer.Token) bool {
    return tok_eq(tok, ",") or tok_eq(tok, "(") or tok_eq(tok, ")") or tok_eq(tok, "=");
}


pub fn check_duplicate_union_branches(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) {
        if (!tok_eq(tokens[i], "|")) {
            i += 1;
            continue;
        }

        const start = union_segment_start(tokens, i);
        const end = union_segment_end(tokens, i);
        try check_duplicate_union_branch_segment(tokens, start, end);
        i = end;
    }
}


fn union_segment_start(tokens: []const lexer.Token, idx: usize) usize {
    var depth_paren: usize = 0;
    var depth_angle: usize = 0;
    var depth_bracket: usize = 0;
    var start = idx;

    while (start > 0 and tokens[start - 1].line == tokens[idx].line) {
        if (depth_paren == 0 and depth_angle == 0 and depth_bracket == 0 and is_union_segment_boundary_before(tokens, start)) break;

        const prev_idx = start - 1;
        if (tok_eq(tokens[prev_idx], ")")) {
            depth_paren += 1;
        } else if (tok_eq(tokens[prev_idx], "(")) {
            if (depth_paren == 0) break;
            depth_paren -= 1;
        } else if (tok_eq(tokens[prev_idx], ">")) {
            depth_angle += 1;
        } else if (tok_eq(tokens[prev_idx], "<")) {
            if (depth_angle == 0) break;
            depth_angle -= 1;
        } else if (tok_eq(tokens[prev_idx], "]")) {
            depth_bracket += 1;
        } else if (tok_eq(tokens[prev_idx], "[")) {
            if (depth_bracket == 0) break;
            depth_bracket -= 1;
        }

        start = prev_idx;
    }

    return start;
}


fn union_segment_end(tokens: []const lexer.Token, idx: usize) usize {
    var depth_paren: usize = 0;
    var depth_angle: usize = 0;
    var depth_bracket: usize = 0;
    var end = idx + 1;

    while (end < tokens.len and tokens[end].line == tokens[idx].line) : (end += 1) {
        if (depth_paren == 0 and depth_angle == 0 and depth_bracket == 0 and is_union_segment_end_boundary(tokens[end])) break;

        if (tok_eq(tokens[end], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tok_eq(tokens[end], ")")) {
            if (depth_paren == 0) break;
            depth_paren -= 1;
            continue;
        }
        if (tok_eq(tokens[end], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tok_eq(tokens[end], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (tok_eq(tokens[end], "[")) {
            depth_bracket += 1;
            continue;
        }
        if (tok_eq(tokens[end], "]")) {
            if (depth_bracket == 0) break;
            depth_bracket -= 1;
            continue;
        }
    }

    return end;
}


fn is_union_segment_boundary_before(tokens: []const lexer.Token, idx: usize) bool {
    const prev = tokens[idx - 1];
    if (tok_eq(prev, ",") or tok_eq(prev, "=") or tok_eq(prev, "{")) return true;
    return idx >= 2 and tok_eq(tokens[idx - 2], "-") and tok_eq(tokens[idx - 1], ">");
}


fn is_union_segment_end_boundary(tok: lexer.Token) bool {
    return tok_eq(tok, ",") or tok_eq(tok, "=") or tok_eq(tok, "{") or tok_eq(tok, ")");
}


pub fn check_inline_func_type_union_branches(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tok_eq(tokens[i], "|")) continue;
        if (inline_func_type_branch_before_pipe(tokens, i)) |site| return mark_error_at(tokens, site, error.InvalidTypeRef);
        if (inline_func_type_branch_after_pipe(tokens, i)) |site| return mark_error_at(tokens, site, error.InvalidTypeRef);
    }
}


fn inline_func_type_branch_before_pipe(tokens: []const lexer.Token, pipe_idx: usize) ?usize {
    if (pipe_idx == 0) return null;
    const close_idx = pipe_idx - 1;
    if (!tok_eq(tokens[close_idx], ")")) return null;
    const open_idx = find_matching_open(tokens, close_idx, "(", ")") orelse return null;
    if (!is_parenthesized_func_type_branch(tokens, open_idx, pipe_idx)) return null;
    return open_idx;
}


fn inline_func_type_branch_after_pipe(tokens: []const lexer.Token, pipe_idx: usize) ?usize {
    const start_idx = pipe_idx + 1;
    if (start_idx >= tokens.len) return null;
    if (!tok_eq(tokens[start_idx], "(")) return null;
    if (is_func_type_start(tokens, start_idx)) return start_idx;
    if (!is_parenthesized_func_type_branch_start(tokens, start_idx)) return null;
    return start_idx;
}


fn is_parenthesized_func_type_branch_start(tokens: []const lexer.Token, start_idx: usize) bool {
    const close_idx = find_matching(tokens, start_idx, "(", ")") catch return false;
    return is_parenthesized_func_type_branch(tokens, start_idx, close_idx + 1);
}


fn is_parenthesized_func_type_branch(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var start = start_idx;
    var end = end_idx;
    while (start < end and tok_eq(tokens[start], "(")) {
        const close_idx = find_matching(tokens, start, "(", ")") catch return false;
        if (close_idx + 1 != end) return false;
        const inner_start = start + 1;
        const inner_end = close_idx;
        if (is_func_type_range(tokens, inner_start, inner_end)) return true;
        start = inner_start;
        end = inner_end;
    }
    return false;
}


fn is_func_type_start(tokens: []const lexer.Token, start_idx: usize) bool {
    const close_idx = find_matching(tokens, start_idx, "(", ")") catch return false;
    return close_idx + 2 < tokens.len and is_return_arrow_at(tokens, close_idx + 1);
}


fn find_matching_open(tokens: []const lexer.Token, close_idx: usize, open: []const u8, close: []const u8) ?usize {
    if (close_idx >= tokens.len or !tok_eq(tokens[close_idx], close)) return null;

    var depth: usize = 0;
    var i = close_idx + 1;
    while (i > 0) {
        i -= 1;
        if (tok_eq(tokens[i], close)) {
            depth += 1;
            continue;
        }
        if (!tok_eq(tokens[i], open)) continue;

        if (depth == 0) return null;
        depth -= 1;
        if (depth == 0) return i;
    }
    return null;
}


const TokenRange = struct {
    start: usize,
    end: usize,
};

fn check_duplicate_union_branch_segment(tokens: []const lexer.Token, start: usize, end: usize) !void {
    var branch_start = start;
    while (branch_start < end) {
        const branch_end = find_next_union_pipe(tokens, branch_start, end);
        const branch_range = normalized_union_branch_range(tokens, branch_start, branch_end);

        var prev_start = start;
        while (prev_start < branch_start) {
            const prev_end = find_next_union_pipe(tokens, prev_start, end);
            const prev_range = normalized_union_branch_range(tokens, prev_start, prev_end);
            if (union_branches_equal(tokens, prev_range, branch_range)) {
                return mark_error_at(tokens, branch_range.start, error.InvalidTypeRef);
            }
            prev_start = if (prev_end < end) prev_end + 1 else end;
        }

        branch_start = if (branch_end < end) branch_end + 1 else end;
    }
}


fn find_next_union_pipe(tokens: []const lexer.Token, start: usize, end: usize) usize {
    var depth_paren: usize = 0;
    var depth_angle: usize = 0;
    var depth_bracket: usize = 0;

    var i = start;
    while (i < end) : (i += 1) {
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
        if (depth_paren == 0 and depth_angle == 0 and depth_bracket == 0 and tok_eq(tokens[i], "|")) return i;
    }
    return end;
}


fn normalized_union_branch_range(tokens: []const lexer.Token, start: usize, end: usize) TokenRange {
    var out = TokenRange{
        .start = normalized_union_branch_start(tokens, start, end),
        .end = end,
    };

    while (out.start + 1 < out.end and tok_eq(tokens[out.start], "(")) {
        const close_idx = find_matching(tokens, out.start, "(", ")") catch break;
        if (close_idx + 1 != out.end) break;
        out.start += 1;
        out.end -= 1;
    }

    return out;
}


fn normalized_union_branch_start(tokens: []const lexer.Token, start: usize, end: usize) usize {
    if (start + 1 >= end) return start;
    if (tokens[start].kind != .ident) return start;
    if (!is_lower_ident_name(tokens[start].lexeme)) return start;
    if (!is_type_atom_start(tokens[start + 1])) return start;
    return start + 1;
}


fn is_type_atom_start(tok: lexer.Token) bool {
    if (tok_eq(tok, "[") or tok_eq(tok, "(")) return true;
    if (tok.kind != .ident or tok.lexeme.len == 0) return false;
    if (std.ascii.isUpper(tok.lexeme[0])) return true;
    return is_base_type_name(tok.lexeme) or tok_eq(tok, "nil");
}


fn union_branches_equal(
    tokens: []const lexer.Token,
    a: TokenRange,
    b: TokenRange,
) bool {
    if (a.end - a.start != b.end - b.start) return false;
    var offset: usize = 0;
    while (offset < a.end - a.start) : (offset += 1) {
        if (!std.mem.eql(u8, tokens[a.start + offset].lexeme, tokens[b.start + offset].lexeme)) return false;
    }
    return true;
}


fn is_nil_return_spec(tokens: []const lexer.Token, idx: usize) bool {
    return idx >= 2 and
        tokens[idx - 2].line == tokens[idx].line and
        tokens[idx - 1].line == tokens[idx].line and
        tok_eq(tokens[idx - 2], "-") and
        tok_eq(tokens[idx - 1], ">");
}


fn is_bare_nil_type_context(tokens: []const lexer.Token, idx: usize) bool {
    if (idx > 0 and tokens[idx - 1].line == tokens[idx].line) {
        const prev = tokens[idx - 1];
        if (tok_eq(prev, "=")) return is_type_decl_or_constraint_line(tokens, idx);
        if (tok_eq(prev, "[") or tok_eq(prev, "<")) return true;
        if (prev.kind == .ident and !is_keyword(prev.lexeme)) return true;
    }
    if (idx + 1 < tokens.len and tokens[idx + 1].line == tokens[idx].line) {
        const next = tokens[idx + 1];
        if (tok_eq(next, "]") or tok_eq(next, ">")) return true;
    }
    return false;
}


fn is_type_decl_or_constraint_line(tokens: []const lexer.Token, idx: usize) bool {
    const line_start = line_start_idx(tokens, idx);
    if (tok_eq(tokens[line_start], "#")) return true;
    if (tokens[line_start].kind != .ident) return false;
    if (!is_valid_declared_type_name(tokens[line_start].lexeme)) return false;
    if (!is_top_level_decl_head(tokens, line_start)) return false;
    return is_type_decl_start(tokens, line_start);
}
