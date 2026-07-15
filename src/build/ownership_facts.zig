const std = @import("std");
const ownership = @import("ownership.zig");

pub const SourceOrigin = enum {
    unknown,
    fresh_local,
    param_or_import,
    helper_shared,
    collection_value,
    recv_value,
    loop_source,
    union_payload,
    compiler_temp,
};

pub const MoveCandidateKind = enum {
    direct,
    call_arg,
    union_binding_call_arg,
    field_get,
    field_set,
    return_value,
    dead_alias,
};

pub const MoveRejectReason = enum {
    disabled,
    not_direct_source,
    not_managed_type,
    future_use_after_expr,
    future_use_after_arg,
    future_use_after_stmt,
    future_use_after_body,
    defer_visible,
    loop_context,
    source_not_unique,
    same_statement_multi_candidate,
    unsupported_candidate,
};

pub const TokenRange = struct {
    start: usize = 0,
    end: usize = 0,

    pub fn is_empty(self: TokenRange) bool {
        return self.start == self.end;
    }
};

pub const MoveSource = struct {
    source_name: []const u8,
    actual_name: []const u8,
    origin: SourceOrigin = .unknown,
};

pub const MoveUseWindows = struct {
    fresh_source_gap: ?TokenRange = null,
    after_expr: ?TokenRange = null,
    after_arg: ?TokenRange = null,
    after_stmt: ?TokenRange = null,
    body_rest: ?TokenRange = null,
};

pub const MoveContext = struct {
    body: TokenRange = .{},
    statement: TokenRange = .{},
    arg: ?TokenRange = null,
    args: ?TokenRange = null,
    cleanup: ownership.PathCleanupFacts = .{},
    defer_visible: bool = false,
    inside_loop: bool = false,
    allow_last_use_move: bool = true,
    allow_field_read_move: bool = false,

    pub fn cleanup_visible(self: MoveContext) bool {
        return self.cleanup.cleanup_visible;
    }
};

pub const MoveCandidate = struct {
    kind: MoveCandidateKind,
    source: MoveSource,
    expr_range: TokenRange,
    context: MoveContext,
    future_use: MoveUseWindows = .{},

    pub fn dedupe_key(self: MoveCandidate) []const u8 {
        return self.source.actual_name;
    }
};

pub const MoveActions = struct {
    zero_source: bool = false,
    zero_field: bool = false,
    release_skip_name: ?[]const u8 = null,
};

pub const MoveDecision = struct {
    accepted: bool,
    zero_source: bool = false,
    zero_field: bool = false,
    release_skip_name: ?[]const u8 = null,
    reject_reason: ?MoveRejectReason = null,

    pub fn accept(candidate: *const MoveCandidate, actions: MoveActions) MoveDecision {
        _ = candidate;
        return .{
            .accepted = true,
            .zero_source = actions.zero_source,
            .zero_field = actions.zero_field,
            .release_skip_name = actions.release_skip_name,
        };
    }

    pub fn reject(candidate: *const MoveCandidate, reason: MoveRejectReason) MoveDecision {
        _ = candidate;
        return .{
            .accepted = false,
            .reject_reason = reason,
        };
    }

    pub fn is_copy_required(self: MoveDecision) bool {
        return !self.accepted;
    }
};

pub fn decide_call_arg_move(candidate: MoveCandidate) MoveDecision {
    if (candidate.kind != .call_arg) return MoveDecision.reject(&candidate, .unsupported_candidate);
    if (!candidate.context.allow_last_use_move) return MoveDecision.reject(&candidate, .disabled);
    if (candidate.context.defer_visible) return MoveDecision.reject(&candidate, .defer_visible);
    if (has_use_window(candidate.future_use.after_arg)) return MoveDecision.reject(&candidate, .future_use_after_arg);
    if (has_use_window(candidate.future_use.after_stmt)) return MoveDecision.reject(&candidate, .future_use_after_stmt);
    if (has_use_window(candidate.future_use.body_rest)) return MoveDecision.reject(&candidate, .future_use_after_body);
    return MoveDecision.accept(&candidate, .{
        .zero_source = true,
        .release_skip_name = candidate.source.actual_name,
    });
}

pub fn decide_field_get_move(candidate: MoveCandidate) MoveDecision {
    if (candidate.kind != .field_get) return MoveDecision.reject(&candidate, .unsupported_candidate);
    if (!candidate.context.allow_last_use_move or !candidate.context.allow_field_read_move) return MoveDecision.reject(&candidate, .disabled);
    if (candidate.context.defer_visible) return MoveDecision.reject(&candidate, .defer_visible);
    if (candidate.source.origin != .fresh_local) return MoveDecision.reject(&candidate, .source_not_unique);
    if (has_use_window(candidate.future_use.fresh_source_gap)) return MoveDecision.reject(&candidate, .source_not_unique);
    if (has_use_window(candidate.future_use.after_expr)) return MoveDecision.reject(&candidate, .future_use_after_expr);
    if (has_use_window(candidate.future_use.after_stmt)) return MoveDecision.reject(&candidate, .future_use_after_stmt);
    if (has_use_window(candidate.future_use.body_rest)) return MoveDecision.reject(&candidate, .future_use_after_body);
    return MoveDecision.accept(&candidate, .{
        .zero_field = true,
    });
}

fn has_use_window(range: ?TokenRange) bool {
    const value = range orelse return false;
    return !value.is_empty();
}

test "move candidate records source, context, cleanup facts and conservative decision" {
    const candidate = MoveCandidate{
        .kind = .call_arg,
        .source = .{
            .source_name = "data",
            .actual_name = "data",
            .origin = .fresh_local,
        },
        .expr_range = .{ .start = 10, .end = 11 },
        .context = .{
            .body = .{ .start = 0, .end = 40 },
            .statement = .{ .start = 8, .end = 20 },
            .arg = .{ .start = 10, .end = 11 },
            .cleanup = .{
                .cleanup_visible = true,
                .release_skip_names = &.{"data"},
            },
            .defer_visible = false,
            .inside_loop = true,
        },
        .future_use = .{
            .after_arg = .{ .start = 11, .end = 20 },
            .after_stmt = .{ .start = 20, .end = 40 },
        },
    };

    const decision = MoveDecision.reject(&candidate, .loop_context);

    try std.testing.expectEqual(MoveCandidateKind.call_arg, candidate.kind);
    try std.testing.expectEqual(SourceOrigin.fresh_local, candidate.source.origin);
    try std.testing.expectEqualStrings("data", candidate.dedupe_key());
    try std.testing.expect(candidate.context.cleanup_visible());
    try std.testing.expect(decision.is_copy_required());
    try std.testing.expectEqual(MoveRejectReason.loop_context, decision.reject_reason.?);
}

test "accepted move decision carries zero and release-skip actions" {
    const candidate = MoveCandidate{
        .kind = .field_get,
        .source = .{
            .source_name = "user",
            .actual_name = "user",
            .origin = .fresh_local,
        },
        .expr_range = .{ .start = 6, .end = 9 },
        .context = .{
            .body = .{ .start = 0, .end = 12 },
            .statement = .{ .start = 4, .end = 12 },
        },
    };

    const decision = MoveDecision.accept(&candidate, .{
        .zero_source = true,
        .release_skip_name = candidate.source.actual_name,
    });

    try std.testing.expect(!decision.is_copy_required());
    try std.testing.expectEqualStrings("user", decision.release_skip_name.?);
    try std.testing.expect(decision.zero_source);
    try std.testing.expectEqual(@as(?MoveRejectReason, null), decision.reject_reason);
}

test "call arg decision rejects disabled, defer and future-use windows" {
    const safe_candidate = MoveCandidate{
        .kind = .call_arg,
        .source = .{
            .source_name = "data",
            .actual_name = "data",
            .origin = .fresh_local,
        },
        .expr_range = .{ .start = 4, .end = 5 },
        .context = .{
            .body = .{ .start = 0, .end = 12 },
            .statement = .{ .start = 2, .end = 8 },
            .arg = .{ .start = 4, .end = 5 },
            .allow_last_use_move = true,
        },
    };
    const safe_decision = decide_call_arg_move(safe_candidate);
    try std.testing.expect(safe_decision.accepted);
    try std.testing.expect(safe_decision.zero_source);

    var disabled_candidate = safe_candidate;
    disabled_candidate.context.allow_last_use_move = false;
    const disabled_decision = decide_call_arg_move(disabled_candidate);
    try std.testing.expectEqual(MoveRejectReason.disabled, disabled_decision.reject_reason.?);

    var defer_candidate = safe_candidate;
    defer_candidate.context.defer_visible = true;
    const defer_decision = decide_call_arg_move(defer_candidate);
    try std.testing.expectEqual(MoveRejectReason.defer_visible, defer_decision.reject_reason.?);

    var after_arg_candidate = safe_candidate;
    after_arg_candidate.future_use.after_arg = .{ .start = 5, .end = 8 };
    const after_arg_decision = decide_call_arg_move(after_arg_candidate);
    try std.testing.expectEqual(MoveRejectReason.future_use_after_arg, after_arg_decision.reject_reason.?);

    var after_stmt_candidate = safe_candidate;
    after_stmt_candidate.future_use.after_stmt = .{ .start = 8, .end = 12 };
    const after_stmt_decision = decide_call_arg_move(after_stmt_candidate);
    try std.testing.expectEqual(MoveRejectReason.future_use_after_stmt, after_stmt_decision.reject_reason.?);
}

test "field-get decision requires fresh unique source and field-read permission" {
    const safe_candidate = MoveCandidate{
        .kind = .field_get,
        .source = .{
            .source_name = "user",
            .actual_name = "user",
            .origin = .fresh_local,
        },
        .expr_range = .{ .start = 10, .end = 13 },
        .context = .{
            .body = .{ .start = 0, .end = 30 },
            .statement = .{ .start = 8, .end = 20 },
            .allow_last_use_move = true,
            .allow_field_read_move = true,
        },
    };

    const safe_decision = decide_field_get_move(safe_candidate);
    try std.testing.expect(safe_decision.accepted);
    try std.testing.expect(safe_decision.zero_field);
    try std.testing.expect(!safe_decision.zero_source);

    var disabled_candidate = safe_candidate;
    disabled_candidate.context.allow_field_read_move = false;
    const disabled_decision = decide_field_get_move(disabled_candidate);
    try std.testing.expectEqual(MoveRejectReason.disabled, disabled_decision.reject_reason.?);

    var shared_candidate = safe_candidate;
    shared_candidate.source.origin = .helper_shared;
    const shared_decision = decide_field_get_move(shared_candidate);
    try std.testing.expectEqual(MoveRejectReason.source_not_unique, shared_decision.reject_reason.?);

    var alias_candidate = safe_candidate;
    alias_candidate.future_use.fresh_source_gap = .{ .start = 4, .end = 8 };
    const alias_decision = decide_field_get_move(alias_candidate);
    try std.testing.expectEqual(MoveRejectReason.source_not_unique, alias_decision.reject_reason.?);

    var after_expr_candidate = safe_candidate;
    after_expr_candidate.future_use.after_expr = .{ .start = 13, .end = 20 };
    const after_expr_decision = decide_field_get_move(after_expr_candidate);
    try std.testing.expectEqual(MoveRejectReason.future_use_after_expr, after_expr_decision.reject_reason.?);

    var body_rest_candidate = safe_candidate;
    body_rest_candidate.future_use.body_rest = .{ .start = 20, .end = 30 };
    const body_rest_decision = decide_field_get_move(body_rest_candidate);
    try std.testing.expectEqual(MoveRejectReason.future_use_after_body, body_rest_decision.reject_reason.?);
}
