//! Pure reachability and loop-control helpers shared by codegen domains.
const std = @import("std");
const lexer = @import("lexer.zig");
const codegen_tokens = @import("codegen_tokens.zig");
const context = @import("codegen_context.zig");

const tok_eq = codegen_tokens.tok_eq;
const find_matching_in_range = codegen_tokens.find_matching_in_range;
const find_stmt_end = codegen_tokens.find_stmt_end;
const find_top_level_block_open = codegen_tokens.find_top_level_block_open;
const LoopControl = context.LoopControl;

pub fn body_ends_with_plain_return(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    var last_start: ?usize = null;
    while (i < end_idx) {
        const stmt_end = find_stmt_end(tokens, i, end_idx);
        if (i < stmt_end) last_start = i;
        i = stmt_end;
    }
    const idx = last_start orelse return false;
    return tok_eq(tokens[idx], "return");
}

pub fn body_can_reach_end(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i < end_idx) {
        const stmt_end = find_stmt_end(tokens, i, end_idx);
        if (!stmt_can_reach_end(tokens, i, stmt_end)) return false;
        i = stmt_end;
    }
    return true;
}

pub fn stmt_can_reach_end(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx >= end_idx) return true;
    if (tok_eq(tokens[start_idx], "return")) return false;
    if (tok_eq(tokens[start_idx], "break") or tok_eq(tokens[start_idx], "continue")) return false;
    if (tok_eq(tokens[start_idx], "if")) return if_stmt_can_reach_end(tokens, start_idx, end_idx);
    if (tok_eq(tokens[start_idx], "loop")) return loop_stmt_can_reach_end(tokens, start_idx, end_idx);
    return true;
}

pub fn if_stmt_can_reach_end(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    const open_brace = find_top_level_block_open(tokens, start_idx + 1, end_idx) orelse return true;
    const close_brace = find_matching_in_range(tokens, open_brace, "{", "}", end_idx) catch return true;

    var else_if_start: ?usize = null;
    var else_open: ?usize = null;
    var else_close: ?usize = null;
    if (close_brace + 1 < end_idx and tok_eq(tokens[close_brace + 1], "else")) {
        if (close_brace + 2 >= end_idx) return true;
        if (tok_eq(tokens[close_brace + 2], "if")) {
            else_if_start = close_brace + 2;
        } else if (tok_eq(tokens[close_brace + 2], "{")) {
            const close_else = find_matching_in_range(tokens, close_brace + 2, "{", "}", end_idx) catch return true;
            if (close_else + 1 != end_idx) return true;
            else_open = close_brace + 2;
            else_close = close_else;
        } else {
            return true;
        }
    } else if (close_brace + 1 != end_idx) {
        return true;
    }

    const then_can_reach_end = body_can_reach_end(tokens, open_brace + 1, close_brace);
    const else_can_reach_end = if (else_if_start) |nested_if|
        if_stmt_can_reach_end(tokens, nested_if, end_idx)
    else if (else_open) |open_else|
        body_can_reach_end(tokens, open_else + 1, else_close orelse return true)
    else
        true;
    return then_can_reach_end or else_can_reach_end;
}

pub fn loop_stmt_can_reach_end(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    const open_brace = find_top_level_block_open(tokens, start_idx + 1, end_idx) orelse return true;
    const close_brace = find_matching_in_range(tokens, open_brace, "{", "}", end_idx) catch return true;
    if (close_brace + 1 != end_idx) return true;
    return loop_body_can_break_current_loop(tokens, open_brace + 1, close_brace, label_for_loop_start(tokens, start_idx));
}

pub fn loop_body_can_break_current_loop(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, loop_label: ?[]const u8) bool {
    if (loop_label) |label| {
        if (token_range_contains_labeled_break(tokens, start_idx, end_idx, label)) return true;
    }

    var i = start_idx;
    while (i < end_idx) {
        const stmt_end = find_stmt_end(tokens, i, end_idx);
        if (stmt_breaks_current_loop(tokens, i, stmt_end, loop_label)) return true;
        i = stmt_end;
    }
    return false;
}

pub fn stmt_breaks_current_loop(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, loop_label: ?[]const u8) bool {
    if (start_idx >= end_idx) return false;
    if (tok_eq(tokens[start_idx], "break")) return break_targets_current_loop(tokens, start_idx, end_idx, loop_label);
    if (!tok_eq(tokens[start_idx], "if")) return false;
    const control_idx = find_top_level_guard_loop_control(tokens, start_idx + 1, end_idx) orelse return false;
    if (!tok_eq(tokens[control_idx], "break")) return false;
    return break_targets_current_loop(tokens, control_idx, end_idx, loop_label);
}

pub fn break_targets_current_loop(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, loop_label: ?[]const u8) bool {
    if (end_idx == start_idx + 1) return true;
    if (end_idx != start_idx + 3 or !tok_eq(tokens[start_idx + 1], "#")) return false;
    const label = loop_label orelse return false;
    return tokens[start_idx + 2].kind == .ident and std.mem.eql(u8, tokens[start_idx + 2].lexeme, label);
}

pub fn token_range_contains_labeled_break(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, label: []const u8) bool {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "loop")) {
            const nested_label = label_for_loop_start(tokens, i) orelse continue;
            if (!std.mem.eql(u8, nested_label, label)) continue;
            const open_brace = find_top_level_block_open(tokens, i + 1, end_idx) orelse continue;
            const close_brace = find_matching_in_range(tokens, open_brace, "{", "}", end_idx) catch continue;
            i = close_brace;
            continue;
        }

        if (i + 2 >= end_idx) continue;
        if (!tok_eq(tokens[i], "break")) continue;
        if (!tok_eq(tokens[i + 1], "#")) continue;
        if (tokens[i + 2].kind != .ident) continue;
        if (std.mem.eql(u8, tokens[i + 2].lexeme, label)) return true;
    }
    return false;
}

pub fn same_loop_control(a: *const LoopControl, b: *const LoopControl) bool {
    return std.mem.eql(u8, a.break_label, b.break_label);
}

pub fn find_top_level_guard_loop_control(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
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
        if (tok_eq(tokens[i], "break") or tok_eq(tokens[i], "continue")) return i;
    }
    return null;
}

pub fn label_for_loop_start(tokens: []const lexer.Token, loop_idx: usize) ?[]const u8 {
    if (loop_idx < 2) return null;
    const label_idx = previous_line_start(tokens, loop_idx) orelse return null;
    if (!tok_eq(tokens[label_idx], "#")) return null;
    if (label_idx + 2 != loop_idx) return null;
    if (tokens[label_idx + 1].kind != .ident) return null;
    return tokens[label_idx + 1].lexeme;
}

pub fn previous_line_start(tokens: []const lexer.Token, idx: usize) ?usize {
    if (idx == 0 or idx > tokens.len) return null;
    const prev_line = tokens[idx - 1].line;
    var start = idx - 1;
    while (start > 0 and tokens[start - 1].line == prev_line) {
        start -= 1;
    }
    return start;
}
