//! Semantic validation for compiler-provided Result syntax.
const std = @import("std");
const lexer = @import("lexer.zig");
const sema_tokens = @import("sema_tokens.zig");

const find_line_end_idx = sema_tokens.find_line_end_idx;
const find_matching = sema_tokens.find_matching;
const find_top_level_comma = sema_tokens.find_top_level_comma;
const find_top_level_assign_eq_on_line = sema_tokens.find_top_level_assign_eq_on_line;
const mark_error_at = sema_tokens.mark_error_at;
const tok_eq = sema_tokens.tok_eq;

pub fn check_result_constructor_context(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (!is_result_constructor_name(tokens[i].lexeme)) continue;
        if (!tok_eq(tokens[i + 1], "(")) continue;

        const line_start = find_line_start(tokens, i);
        const line_end = find_line_end_idx(tokens, i);
        const assign_idx = find_top_level_assign_eq_on_line(tokens, line_start, line_end) orelse continue;
        if (assign_idx >= i) continue;
        if (result_binding_shape(tokens, line_start, assign_idx)) |binding| {
            if (constructor_payload_is_valid(tokens, i, binding)) continue;
            return mark_error_at(tokens, i, error.InvalidResultConstructor);
        }
        return mark_error_at(tokens, i, error.InvalidResultConstructor);
    }
}

fn is_result_constructor_name(name: []const u8) bool {
    return std.mem.eql(u8, name, "Ok") or std.mem.eql(u8, name, "Err");
}

fn find_line_start(tokens: []const lexer.Token, idx: usize) usize {
    var start = idx;
    while (start > 0 and tokens[start - 1].line == tokens[idx].line) : (start -= 1) {}
    return start;
}

const ResultBindingShape = struct {
    ok_is_unit: bool,
};

fn result_binding_shape(tokens: []const lexer.Token, start_idx: usize, assign_idx: usize) ?ResultBindingShape {
    var i = start_idx;
    while (i + 1 < assign_idx) : (i += 1) {
        if (!std.mem.eql(u8, tokens[i].lexeme, "Result")) continue;
        if (!tok_eq(tokens[i + 1], "<")) continue;
        const close_angle = find_matching(tokens, i + 1, "<", ">") catch return null;
        if (close_angle >= assign_idx or i + 3 >= close_angle) return null;
        return .{ .ok_is_unit = tok_eq(tokens[i + 2], "nil") and tok_eq(tokens[i + 3], ",") };
    }
    return null;
}

fn constructor_payload_is_valid(tokens: []const lexer.Token, constructor_idx: usize, binding: ResultBindingShape) bool {
    const close_paren = find_matching(tokens, constructor_idx + 1, "(", ")") catch return false;
    const payload_count: usize = if (close_paren == constructor_idx + 2)
        0
    else if (find_top_level_comma(tokens, constructor_idx + 2, close_paren) == null)
        1
    else
        2;
    if (std.mem.eql(u8, tokens[constructor_idx].lexeme, "Err")) return payload_count == 1;
    return if (binding.ok_is_unit) payload_count == 0 else payload_count == 1;
}
