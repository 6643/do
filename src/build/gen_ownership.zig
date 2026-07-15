//! Ownership release plan emit (ARC scope exits).
const std = @import("std");
const lexer = @import("lexer.zig");
const ownership = @import("ownership.zig");
const codegen_tokens = @import("codegen_tokens.zig");
const codegen_names = @import("codegen_names.zig");
const model = @import("codegen_model.zig");
const context = @import("codegen_context.zig");
const codegen_emit_wasi = @import("codegen_emit_wasi.zig");
const gen_collect_util = @import("gen_collect_util.zig");
const codegen_collect_functions = @import("codegen_collect_functions.zig");
const codegen_collect_structs = @import("codegen_collect_structs.zig");

const tokEq = codegen_tokens.tok_eq;
const findMatching = codegen_tokens.find_matching;
const findMatchingInRange = codegen_tokens.find_matching_in_range;
const findLineEnd = codegen_tokens.find_line_end;
const isLineStart = codegen_tokens.is_line_start;
const findTopLevelToken = codegen_tokens.find_top_level_token;
const findTopLevelBlockOpen = codegen_tokens.find_top_level_block_open;
const findStmtEnd = codegen_tokens.find_stmt_end;
const appendFmt = codegen_names.append_fmt;
const Range = codegen_tokens.Range;

const LocalSet = context.LocalSet;
const CodegenContext = context.CodegenContext;
const CodegenError = model.CodegenError;
const LoopControl = context.LoopControl;
const findStructLayout = gen_collect_util.findStructLayout;
const is_managed_local_type = codegen_emit_wasi.is_managed_local_type;
const is_managed_payload_type = codegen_emit_wasi.is_managed_payload_type;

pub fn emitReleaseManagedLocals(allocator: std.mem.Allocator, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) !void {
    try emitReleaseManagedLocalsExcept(allocator, locals, ctx, null, out);
}

pub fn emitReleaseManagedLocalsExcept(allocator: std.mem.Allocator, locals: *const LocalSet, ctx: CodegenContext, skip_name: ?[]const u8, out: *std.ArrayList(u8)) !void {
    if (skip_name) |name| {
        const skip_names = [_][]const u8{name};
        return emitReleaseManagedLocalsExceptMany(allocator, locals, ctx, &skip_names, out);
    }
    return emitReleaseManagedLocalsExceptMany(allocator, locals, ctx, &.{}, out);
}

pub fn emitReleaseManagedLocalsExceptMany(allocator: std.mem.Allocator, locals: *const LocalSet, ctx: CodegenContext, skip_names: []const []const u8, out: *std.ArrayList(u8)) !void {
    const release_plan = try buildReturnOwnershipPlan(allocator, locals, ctx, skip_names);
    defer release_plan.deinit(allocator);
    try emitOwnershipReleasePlan(allocator, release_plan, out);
}

pub fn emitFallthroughReleaseManagedLocals(allocator: std.mem.Allocator, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) !void {
    const release_plan = try buildFallthroughOwnershipPlan(allocator, locals, ctx);
    defer release_plan.deinit(allocator);
    if (release_plan.release_steps.len == 0) return;
    try out.appendSlice(allocator, "    ;; arc-fallthrough-release\n");
    try emitOwnershipReleasePlan(allocator, release_plan, out);
}

pub fn emitBlockReleaseManagedLocals(allocator: std.mem.Allocator, locals: *const LocalSet, ctx: CodegenContext, out: *std.ArrayList(u8)) !void {
    const release_plan = try buildBlockOwnershipPlan(allocator, locals, ctx);
    defer release_plan.deinit(allocator);
    if (release_plan.release_steps.len == 0) return;
    try out.appendSlice(allocator, "    ;; arc-block-release\n");
    try emitOwnershipReleasePlan(allocator, release_plan, out);
}

pub fn hasManagedLocals(locals: *const LocalSet, ctx: CodegenContext) bool {
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

pub fn managedLocalKindForType(ty: []const u8, ctx: CodegenContext) ?ownership.ManagedLocalKind {
    if (is_managed_payload_type(ty)) return .storage;
    if (findStructLayout(ctx.struct_layouts, ty) != null) return .managed_struct;
    return null;
}

pub fn collectManagedOwnershipLocals(allocator: std.mem.Allocator, locals: *const LocalSet, ctx: CodegenContext) ![]const ownership.ManagedLocal {
    var managed = std.ArrayList(ownership.ManagedLocal).empty;
    errdefer managed.deinit(allocator);

    for (locals.locals.items) |local| {
        if (!local.release_on_scope_exit) continue;
        const kind = managedLocalKindForType(local.ty, ctx) orelse continue;
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

pub fn buildReturnOwnershipPlan(allocator: std.mem.Allocator, locals: *const LocalSet, ctx: CodegenContext, skip_names: []const []const u8) !ownership.ExitPlan {
    const managed = try collectManagedOwnershipLocals(allocator, locals, ctx);
    defer if (managed.len != 0) allocator.free(managed);
    return ownership.buildReturnExitPlanWithFacts(allocator, managed, .{
        .cleanup_visible = true,
        .release_skip_names = skip_names,
    });
}

pub fn buildGuardReturnOwnershipPlan(allocator: std.mem.Allocator, locals: *const LocalSet, ctx: CodegenContext, skip_names: []const []const u8) !ownership.ExitPlan {
    const managed = try collectManagedOwnershipLocals(allocator, locals, ctx);
    defer if (managed.len != 0) allocator.free(managed);
    return ownership.buildGuardReturnExitPlanWithFacts(allocator, managed, .{
        .cleanup_visible = true,
        .release_skip_names = skip_names,
    });
}

pub fn buildFallthroughOwnershipPlan(allocator: std.mem.Allocator, locals: *const LocalSet, ctx: CodegenContext) !ownership.ExitPlan {
    const managed = try collectManagedOwnershipLocals(allocator, locals, ctx);
    defer if (managed.len != 0) allocator.free(managed);
    return ownership.buildFallthroughExitPlanWithFacts(allocator, managed, .{});
}

pub fn buildBlockOwnershipPlan(allocator: std.mem.Allocator, locals: *const LocalSet, ctx: CodegenContext) !ownership.ExitPlan {
    const managed = try collectManagedOwnershipLocals(allocator, locals, ctx);
    defer if (managed.len != 0) allocator.free(managed);
    return ownership.buildBlockExitPlanWithFacts(allocator, managed, .{});
}

pub fn emitOwnershipReleasePlan(allocator: std.mem.Allocator, release_plan: ownership.ExitPlan, out: *std.ArrayList(u8)) !void {
    for (release_plan.release_steps) |step| {
        try appendFmt(allocator, out, "    ;; arc-release-local {s}\n", .{step.local_name});
        try appendFmt(allocator, out, "    local.get ${s}\n", .{step.local_name});
        try out.appendSlice(allocator, "    call $__arc_dec\n");
        if (!step.clear_after_release) continue;
        try out.appendSlice(allocator, "    i32.const 0\n");
        try appendFmt(allocator, out, "    local.set ${s}\n", .{step.local_name});
    }
}

pub fn bodyEndsWithPlainReturn(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    var last_start: ?usize = null;
    while (i < end_idx) {
        const stmt_end = findStmtEnd(tokens, i, end_idx);
        if (i < stmt_end) last_start = i;
        i = stmt_end;
    }
    const idx = last_start orelse return false;
    return tokEq(tokens[idx], "return");
}

pub fn bodyCanReachEnd(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i < end_idx) {
        const stmt_end = findStmtEnd(tokens, i, end_idx);
        if (!stmtCanReachEnd(tokens, i, stmt_end)) return false;
        i = stmt_end;
    }
    return true;
}

pub fn stmtCanReachEnd(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx >= end_idx) return true;
    if (tokEq(tokens[start_idx], "return")) return false;
    if (tokEq(tokens[start_idx], "break") or tokEq(tokens[start_idx], "continue")) return false;
    if (tokEq(tokens[start_idx], "if")) return ifStmtCanReachEnd(tokens, start_idx, end_idx);
    if (tokEq(tokens[start_idx], "loop")) return loopStmtCanReachEnd(tokens, start_idx, end_idx);
    return true;
}

pub fn ifStmtCanReachEnd(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    const open_brace = findTopLevelBlockOpen(tokens, start_idx + 1, end_idx) orelse return true;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return true;

    var else_if_start: ?usize = null;
    var else_open: ?usize = null;
    var else_close: ?usize = null;
    if (close_brace + 1 < end_idx and tokEq(tokens[close_brace + 1], "else")) {
        if (close_brace + 2 >= end_idx) return true;
        if (tokEq(tokens[close_brace + 2], "if")) {
            else_if_start = close_brace + 2;
        } else if (tokEq(tokens[close_brace + 2], "{")) {
            const close_else = findMatchingInRange(tokens, close_brace + 2, "{", "}", end_idx) catch return true;
            if (close_else + 1 != end_idx) return true;
            else_open = close_brace + 2;
            else_close = close_else;
        } else {
            return true;
        }
    } else if (close_brace + 1 != end_idx) {
        return true;
    }

    const then_can_reach_end = bodyCanReachEnd(tokens, open_brace + 1, close_brace);
    const else_can_reach_end = if (else_if_start) |nested_if|
        ifStmtCanReachEnd(tokens, nested_if, end_idx)
    else if (else_open) |open_else|
        bodyCanReachEnd(tokens, open_else + 1, else_close orelse return true)
    else
        true;
    return then_can_reach_end or else_can_reach_end;
}

pub fn loopStmtCanReachEnd(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    const open_brace = findTopLevelBlockOpen(tokens, start_idx + 1, end_idx) orelse return true;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return true;
    if (close_brace + 1 != end_idx) return true;
    return loopBodyCanBreakCurrentLoop(tokens, open_brace + 1, close_brace, labelForLoopStart(tokens, start_idx));
}

pub fn loopBodyCanBreakCurrentLoop(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, loop_label: ?[]const u8) bool {
    if (loop_label) |label| {
        if (tokenRangeContainsLabeledBreak(tokens, start_idx, end_idx, label)) return true;
    }

    var i = start_idx;
    while (i < end_idx) {
        const stmt_end = findStmtEnd(tokens, i, end_idx);
        if (stmtBreaksCurrentLoop(tokens, i, stmt_end, loop_label)) return true;
        i = stmt_end;
    }
    return false;
}

pub fn stmtBreaksCurrentLoop(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, loop_label: ?[]const u8) bool {
    if (start_idx >= end_idx) return false;
    if (tokEq(tokens[start_idx], "break")) return breakTargetsCurrentLoop(tokens, start_idx, end_idx, loop_label);
    if (!tokEq(tokens[start_idx], "if")) return false;
    const control_idx = findTopLevelGuardLoopControl(tokens, start_idx + 1, end_idx) orelse return false;
    if (!tokEq(tokens[control_idx], "break")) return false;
    return breakTargetsCurrentLoop(tokens, control_idx, end_idx, loop_label);
}

pub fn breakTargetsCurrentLoop(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, loop_label: ?[]const u8) bool {
    if (end_idx == start_idx + 1) return true;
    if (end_idx != start_idx + 3 or !tokEq(tokens[start_idx + 1], "#")) return false;
    const label = loop_label orelse return false;
    return tokens[start_idx + 2].kind == .ident and std.mem.eql(u8, tokens[start_idx + 2].lexeme, label);
}

pub fn tokenRangeContainsLabeledBreak(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, label: []const u8) bool {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEq(tokens[i], "loop")) {
            const nested_label = labelForLoopStart(tokens, i) orelse continue;
            if (!std.mem.eql(u8, nested_label, label)) continue;
            const open_brace = findTopLevelBlockOpen(tokens, i + 1, end_idx) orelse continue;
            const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch continue;
            i = close_brace;
            continue;
        }

        if (i + 2 >= end_idx) continue;
        if (!tokEq(tokens[i], "break")) continue;
        if (!tokEq(tokens[i + 1], "#")) continue;
        if (tokens[i + 2].kind != .ident) continue;
        if (std.mem.eql(u8, tokens[i + 2].lexeme, label)) return true;
    }
    return false;
}

pub fn sameLoopControl(a: *const LoopControl, b: *const LoopControl) bool {
    return std.mem.eql(u8, a.break_label, b.break_label);
}

pub fn findTopLevelGuardLoopControl(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tokEq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (tokEq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tokEq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (depth_paren != 0 or depth_brace != 0 or depth_angle != 0) continue;
        if (tokEq(tokens[i], "break") or tokEq(tokens[i], "continue")) return i;
    }
    return null;
}

pub fn labelForLoopStart(tokens: []const lexer.Token, loop_idx: usize) ?[]const u8 {
    if (loop_idx < 2) return null;
    const label_idx = previousLineStart(tokens, loop_idx) orelse return null;
    if (!tokEq(tokens[label_idx], "#")) return null;
    if (label_idx + 2 != loop_idx) return null;
    if (tokens[label_idx + 1].kind != .ident) return null;
    return tokens[label_idx + 1].lexeme;
}

pub fn previousLineStart(tokens: []const lexer.Token, idx: usize) ?usize {
    if (idx == 0 or idx > tokens.len) return null;
    const prev_line = tokens[idx - 1].line;
    var start = idx - 1;
    while (start > 0 and tokens[start - 1].line == prev_line) {
        start -= 1;
    }
    return start;
}
