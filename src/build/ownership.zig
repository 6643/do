const std = @import("std");

pub const ExitKind = enum {
    fallthrough,
    return_stmt,
    guard_return,
    block_exit,
    break_stmt,
    continue_stmt,
};

pub const ManagedLocalKind = enum {
    storage,
    managed_struct,
};

pub const ReleaseReason = enum {
    fallthrough_cleanup,
    return_cleanup,
    guard_return_cleanup,
    block_exit,
    loop_control,
};

pub const PathCleanupFacts = struct {
    cleanup_visible: bool = false,
    release_skip_names: []const []const u8 = &.{},
};

pub const ManagedLocal = struct {
    name: []const u8,
    kind: ManagedLocalKind,
};

pub const LoopFrame = struct {
    locals: []const ManagedLocal,
    path_facts: PathCleanupFacts = .{},
};

pub const ReleaseStep = struct {
    local_name: []const u8,
    kind: ManagedLocalKind,
    reason: ReleaseReason,
    clear_after_release: bool,
};

pub const ExitPlan = struct {
    kind: ExitKind,
    release_steps: []const ReleaseStep,

    pub fn deinit(self: ExitPlan, allocator: std.mem.Allocator) void {
        if (self.release_steps.len == 0) return;
        allocator.free(self.release_steps);
    }
};

pub fn buildReturnExitPlan(
    allocator: std.mem.Allocator,
    locals: []const ManagedLocal,
    skip_names: []const []const u8,
) !ExitPlan {
    return buildReturnExitPlanWithFacts(allocator, locals, .{
        .cleanup_visible = true,
        .release_skip_names = skip_names,
    });
}

pub fn buildGuardReturnExitPlan(
    allocator: std.mem.Allocator,
    locals: []const ManagedLocal,
    skip_names: []const []const u8,
) !ExitPlan {
    return buildGuardReturnExitPlanWithFacts(allocator, locals, .{
        .cleanup_visible = true,
        .release_skip_names = skip_names,
    });
}

pub fn buildFallthroughExitPlan(
    allocator: std.mem.Allocator,
    locals: []const ManagedLocal,
) !ExitPlan {
    return buildFallthroughExitPlanWithFacts(allocator, locals, .{});
}

pub fn buildBlockExitPlan(
    allocator: std.mem.Allocator,
    locals: []const ManagedLocal,
) !ExitPlan {
    return buildBlockExitPlanWithFacts(allocator, locals, .{});
}

pub fn buildReturnExitPlanWithFacts(
    allocator: std.mem.Allocator,
    locals: []const ManagedLocal,
    facts: PathCleanupFacts,
) !ExitPlan {
    return buildLocalExitPlan(allocator, .return_stmt, .return_cleanup, locals, facts, false);
}

pub fn buildGuardReturnExitPlanWithFacts(
    allocator: std.mem.Allocator,
    locals: []const ManagedLocal,
    facts: PathCleanupFacts,
) !ExitPlan {
    return buildLocalExitPlan(allocator, .guard_return, .guard_return_cleanup, locals, facts, false);
}

pub fn buildFallthroughExitPlanWithFacts(
    allocator: std.mem.Allocator,
    locals: []const ManagedLocal,
    facts: PathCleanupFacts,
) !ExitPlan {
    return buildLocalExitPlan(allocator, .fallthrough, .fallthrough_cleanup, locals, facts, false);
}

pub fn buildBlockExitPlanWithFacts(
    allocator: std.mem.Allocator,
    locals: []const ManagedLocal,
    facts: PathCleanupFacts,
) !ExitPlan {
    return buildLocalExitPlan(allocator, .block_exit, .block_exit, locals, facts, true);
}

pub fn buildLoopControlExitPlan(
    allocator: std.mem.Allocator,
    kind: ExitKind,
    frames: []const LoopFrame,
) !ExitPlan {
    var steps = std.ArrayList(ReleaseStep).empty;
    errdefer steps.deinit(allocator);

    for (frames) |frame| {
        try appendReverseLocals(&steps, allocator, frame.locals, releaseSkipNamesForFacts(frame.path_facts), .loop_control, true);
    }

    return ownedPlan(allocator, kind, &steps);
}

fn buildLocalExitPlan(
    allocator: std.mem.Allocator,
    kind: ExitKind,
    reason: ReleaseReason,
    locals: []const ManagedLocal,
    facts: PathCleanupFacts,
    clear_after_release: bool,
) !ExitPlan {
    var steps = std.ArrayList(ReleaseStep).empty;
    errdefer steps.deinit(allocator);

    try appendReverseLocals(&steps, allocator, locals, releaseSkipNamesForFacts(facts), reason, clear_after_release);
    return ownedPlan(allocator, kind, &steps);
}

fn releaseSkipNamesForFacts(facts: PathCleanupFacts) []const []const u8 {
    if (!facts.cleanup_visible) return &.{};
    return facts.release_skip_names;
}

fn appendReverseLocals(
    steps: *std.ArrayList(ReleaseStep),
    allocator: std.mem.Allocator,
    locals: []const ManagedLocal,
    skip_names: []const []const u8,
    reason: ReleaseReason,
    clear_after_release: bool,
) !void {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (hasName(skip_names, local.name)) continue;
        try steps.append(allocator, .{
            .local_name = local.name,
            .kind = local.kind,
            .reason = reason,
            .clear_after_release = clear_after_release,
        });
    }
}

fn ownedPlan(
    allocator: std.mem.Allocator,
    kind: ExitKind,
    steps: *std.ArrayList(ReleaseStep),
) !ExitPlan {
    if (steps.items.len == 0) {
        steps.deinit(allocator);
        return .{
            .kind = kind,
            .release_steps = &.{},
        };
    }
    const owned_steps = try steps.toOwnedSlice(allocator);
    return .{
        .kind = kind,
        .release_steps = owned_steps,
    };
}

fn hasName(names: []const []const u8, name: []const u8) bool {
    for (names) |candidate| {
        if (std.mem.eql(u8, candidate, name)) return true;
    }
    return false;
}

test "return exit plan facts can skip selected releases" {
    const allocator = std.testing.allocator;
    const locals = [_]ManagedLocal{
        .{ .name = "keep_first", .kind = .storage },
        .{ .name = "moved_value", .kind = .managed_struct },
        .{ .name = "keep_last", .kind = .storage },
    };
    const facts = PathCleanupFacts{
        .cleanup_visible = true,
        .release_skip_names = &.{"moved_value"},
    };

    const plan = try buildReturnExitPlanWithFacts(allocator, &locals, facts);
    defer plan.deinit(allocator);

    try std.testing.expectEqual(ExitKind.return_stmt, plan.kind);
    try std.testing.expectEqual(@as(usize, 2), plan.release_steps.len);
    try std.testing.expectEqualStrings("keep_last", plan.release_steps[0].local_name);
    try std.testing.expectEqualStrings("keep_first", plan.release_steps[1].local_name);
}

test "loop control exit plan honors per-frame release skips" {
    const allocator = std.testing.allocator;
    const inner_locals = [_]ManagedLocal{
        .{ .name = "inner_keep", .kind = .storage },
        .{ .name = "inner_skip", .kind = .managed_struct },
    };
    const outer_locals = [_]ManagedLocal{
        .{ .name = "outer_keep", .kind = .storage },
    };
    const frames = [_]LoopFrame{
        .{
            .locals = &inner_locals,
            .path_facts = .{
                .cleanup_visible = true,
                .release_skip_names = &.{"inner_skip"},
            },
        },
        .{
            .locals = &outer_locals,
        },
    };

    const plan = try buildLoopControlExitPlan(allocator, .break_stmt, &frames);
    defer plan.deinit(allocator);

    try std.testing.expectEqual(ExitKind.break_stmt, plan.kind);
    try std.testing.expectEqual(@as(usize, 2), plan.release_steps.len);
    try std.testing.expectEqualStrings("inner_keep", plan.release_steps[0].local_name);
    try std.testing.expectEqualStrings("outer_keep", plan.release_steps[1].local_name);
}
