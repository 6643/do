//! Ownership release plan emit (ARC scope exits).
const std = @import("std");
const lexer = @import("lexer.zig");
const ownership = @import("ownership.zig");
const codegen_tokens = @import("codegen_tokens.zig");
const codegen_names = @import("codegen_names.zig");
const constants = @import("codegen_constants.zig");
const model = @import("codegen_model.zig");
const context = @import("codegen_context.zig");
const codegen_storage_layout = @import("codegen_storage_layout.zig");
const codegen_collect_util = @import("codegen_collect_util.zig");
const codegen_collect_functions = @import("codegen_collect_functions.zig");
const codegen_collect_structs = @import("codegen_collect_structs.zig");

const tok_eq = codegen_tokens.tok_eq;
const find_matching = codegen_tokens.find_matching;
const find_matching_in_range = codegen_tokens.find_matching_in_range;
const find_line_end = codegen_tokens.find_line_end;
const is_line_start = codegen_tokens.is_line_start;
const find_top_level_token = codegen_tokens.find_top_level_token;
const find_top_level_block_open = codegen_tokens.find_top_level_block_open;
const find_stmt_end = codegen_tokens.find_stmt_end;
const append_fmt = codegen_names.append_fmt;
const STORAGE_OVERWRITE_TMP_LOCAL = constants.STORAGE_OVERWRITE_TMP_LOCAL;
const Range = codegen_tokens.Range;

const LocalSet = context.LocalSet;
const CodegenContext = context.CodegenContext;
const CodegenError = model.CodegenError;
const LoopControl = context.LoopControl;
const find_struct_layout = codegen_collect_util.find_struct_layout;
const is_managed_local_type = codegen_storage_layout.is_managed_local_type;
const is_managed_payload_type = codegen_storage_layout.is_managed_payload_type;

pub fn emit_replace_managed_local_from_tmp(
    allocator: std.mem.Allocator,
    name: []const u8,
    out: *std.ArrayList(u8),
) !void {
    try append_fmt(allocator, out, "    ;; arc-overwrite-release {s}\n", .{name});
    try append_fmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try append_fmt(allocator, out, "    local.get ${s}\n", .{name});
    try out.appendSlice(allocator, "    i32.ne\n");
    try out.appendSlice(allocator, "    if\n");
    try append_fmt(allocator, out, "      local.get ${s}\n", .{name});
    try out.appendSlice(allocator, "      call $__arc_dec\n");
    try out.appendSlice(allocator, "    end\n");
    try append_fmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try append_fmt(allocator, out, "    local.set ${s}\n", .{name});
}

pub fn emit_release_managed_locals(allocator: std.mem.Allocator, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) !void {
    try emit_release_managed_locals_except(allocator, locals, ctx, null, out);
}

pub fn emit_release_managed_locals_except(allocator: std.mem.Allocator, locals: *const LocalSet, ctx: CodegenContext, skip_name: ?[]const u8, out: *std.ArrayList(u8)) !void {
    if (skip_name) |name| {
        const skip_names = [_][]const u8{name};
        return emit_release_managed_locals_except_many(allocator, locals, ctx, &skip_names, out);
    }
    return emit_release_managed_locals_except_many(allocator, locals, ctx, &.{}, out);
}

pub fn emit_release_managed_locals_except_many(allocator: std.mem.Allocator, locals: *const LocalSet, ctx: CodegenContext, skip_names: []const []const u8, out: *std.ArrayList(u8)) !void {
    const release_plan = try build_return_ownership_plan(allocator, locals, ctx, skip_names);
    defer release_plan.deinit(allocator);
    try emit_ownership_release_plan(allocator, release_plan, out);
}

pub fn emit_fallthrough_release_managed_locals(allocator: std.mem.Allocator, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) !void {
    const release_plan = try build_fallthrough_ownership_plan(allocator, locals, ctx);
    defer release_plan.deinit(allocator);
    if (release_plan.release_steps.len == 0) return;
    try out.appendSlice(allocator, "    ;; arc-fallthrough-release\n");
    try emit_ownership_release_plan(allocator, release_plan, out);
}

pub fn emit_block_release_managed_locals(allocator: std.mem.Allocator, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) !void {
    const release_plan = try build_block_ownership_plan(allocator, locals, ctx);
    defer release_plan.deinit(allocator);
    if (release_plan.release_steps.len == 0) return;
    try out.appendSlice(allocator, "    ;; arc-block-release\n");
    try emit_ownership_release_plan(allocator, release_plan, out);
}

pub fn has_managed_locals(locals: *const LocalSet, ctx: CodegenContext) bool {
    for (locals.locals.items) |local| {
        if (!local.release_on_scope_exit) continue;
        if (is_managed_local_type(local.ty, ctx)) return true;
    }
    return false;
}

pub const OwnedLoopFrames = struct {
    frames: []const ownership.LoopFrame,

    pub fn deinit(self: OwnedLoopFrames, allocator: std.mem.Allocator) void {
        for (self.frames) |frame| {
            if (frame.locals.len != 0) allocator.free(frame.locals);
        }
        if (self.frames.len != 0) allocator.free(self.frames);
    }
};

pub fn managed_local_kind_for_type(ty: []const u8, ctx: CodegenContext) ?ownership.ManagedLocalKind {
    if (is_managed_payload_type(ty)) return .storage;
    if (find_struct_layout(ctx.struct_layouts, ty) != null) return .managed_struct;
    return null;
}

pub fn collect_managed_ownership_locals(allocator: std.mem.Allocator, locals: *const LocalSet, ctx: CodegenContext) ![]const ownership.ManagedLocal {
    var managed = std.ArrayList(ownership.ManagedLocal).empty;
    errdefer managed.deinit(allocator);

    for (locals.locals.items) |local| {
        if (!local.release_on_scope_exit) continue;
        const kind = managed_local_kind_for_type(local.ty, ctx) orelse continue;
        try managed.append(allocator, .{
            .name = local.name,
            .kind = kind,
        });
    }

    if (managed.items.len == 0) {
        managed.deinit(allocator);
        return &.{};
    }
    return try managed.toOwnedSlice(allocator);
}

pub fn build_return_ownership_plan(allocator: std.mem.Allocator, locals: *const LocalSet, ctx: CodegenContext, skip_names: []const []const u8) !ownership.ExitPlan {
    const managed = try collect_managed_ownership_locals(allocator, locals, ctx);
    defer if (managed.len != 0) allocator.free(managed);
    return ownership.build_return_exit_plan_with_facts(allocator, managed, .{
        .cleanup_visible = true,
        .release_skip_names = skip_names,
    });
}

pub fn build_guard_return_ownership_plan(allocator: std.mem.Allocator, locals: *const LocalSet, ctx: CodegenContext, skip_names: []const []const u8) !ownership.ExitPlan {
    const managed = try collect_managed_ownership_locals(allocator, locals, ctx);
    defer if (managed.len != 0) allocator.free(managed);
    return ownership.build_guard_return_exit_plan_with_facts(allocator, managed, .{
        .cleanup_visible = true,
        .release_skip_names = skip_names,
    });
}

pub fn build_fallthrough_ownership_plan(allocator: std.mem.Allocator, locals: *const LocalSet, ctx: CodegenContext) !ownership.ExitPlan {
    const managed = try collect_managed_ownership_locals(allocator, locals, ctx);
    defer if (managed.len != 0) allocator.free(managed);
    return ownership.build_fallthrough_exit_plan_with_facts(allocator, managed, .{});
}

pub fn build_block_ownership_plan(allocator: std.mem.Allocator, locals: *const LocalSet, ctx: CodegenContext) !ownership.ExitPlan {
    const managed = try collect_managed_ownership_locals(allocator, locals, ctx);
    defer if (managed.len != 0) allocator.free(managed);
    return ownership.build_block_exit_plan_with_facts(allocator, managed, .{});
}

pub fn emit_ownership_release_plan(allocator: std.mem.Allocator, release_plan: ownership.ExitPlan, out: *std.ArrayList(u8)) !void {
    for (release_plan.release_steps) |step| {
        try append_fmt(allocator, out, "    ;; arc-release-local {s}\n", .{step.local_name});
        try append_fmt(allocator, out, "    local.get ${s}\n", .{step.local_name});
        try out.appendSlice(allocator, "    call $__arc_dec\n");
        if (!step.clear_after_release) continue;
        try out.appendSlice(allocator, "    i32.const 0\n");
        try append_fmt(allocator, out, "    local.set ${s}\n", .{step.local_name});
    }
}

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
