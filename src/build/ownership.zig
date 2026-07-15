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

pub fn build_return_exit_plan(
    allocator: std.mem.Allocator,
    locals: []const ManagedLocal,
    skip_names: []const []const u8,
) !ExitPlan {
    return build_return_exit_plan_with_facts(allocator, locals, .{
        .cleanup_visible = true,
        .release_skip_names = skip_names,
    });
}

pub fn build_guard_return_exit_plan(
    allocator: std.mem.Allocator,
    locals: []const ManagedLocal,
    skip_names: []const []const u8,
) !ExitPlan {
    return build_guard_return_exit_plan_with_facts(allocator, locals, .{
        .cleanup_visible = true,
        .release_skip_names = skip_names,
    });
}

pub fn build_fallthrough_exit_plan(
    allocator: std.mem.Allocator,
    locals: []const ManagedLocal,
) !ExitPlan {
    return build_fallthrough_exit_plan_with_facts(allocator, locals, .{});
}

pub fn build_block_exit_plan(
    allocator: std.mem.Allocator,
    locals: []const ManagedLocal,
) !ExitPlan {
    return build_block_exit_plan_with_facts(allocator, locals, .{});
}

pub fn build_return_exit_plan_with_facts(
    allocator: std.mem.Allocator,
    locals: []const ManagedLocal,
    facts: PathCleanupFacts,
) !ExitPlan {
    return build_local_exit_plan(allocator, .return_stmt, .return_cleanup, locals, facts, false);
}

pub fn build_guard_return_exit_plan_with_facts(
    allocator: std.mem.Allocator,
    locals: []const ManagedLocal,
    facts: PathCleanupFacts,
) !ExitPlan {
    return build_local_exit_plan(allocator, .guard_return, .guard_return_cleanup, locals, facts, false);
}

pub fn build_fallthrough_exit_plan_with_facts(
    allocator: std.mem.Allocator,
    locals: []const ManagedLocal,
    facts: PathCleanupFacts,
) !ExitPlan {
    return build_local_exit_plan(allocator, .fallthrough, .fallthrough_cleanup, locals, facts, false);
}

pub fn build_block_exit_plan_with_facts(
    allocator: std.mem.Allocator,
    locals: []const ManagedLocal,
    facts: PathCleanupFacts,
) !ExitPlan {
    return build_local_exit_plan(allocator, .block_exit, .block_exit, locals, facts, true);
}

pub fn build_loop_control_exit_plan(
    allocator: std.mem.Allocator,
    kind: ExitKind,
    frames: []const LoopFrame,
) !ExitPlan {
    var steps = std.ArrayList(ReleaseStep).empty;
    errdefer steps.deinit(allocator);

    for (frames) |frame| {
        try append_reverse_locals(&steps, allocator, frame.locals, release_skip_names_for_facts(frame.path_facts), .loop_control, true);
    }

    return owned_plan(allocator, kind, &steps);
}

fn build_local_exit_plan(
    allocator: std.mem.Allocator,
    kind: ExitKind,
    reason: ReleaseReason,
    locals: []const ManagedLocal,
    facts: PathCleanupFacts,
    clear_after_release: bool,
) !ExitPlan {
    var steps = std.ArrayList(ReleaseStep).empty;
    errdefer steps.deinit(allocator);

    try append_reverse_locals(&steps, allocator, locals, release_skip_names_for_facts(facts), reason, clear_after_release);
    return owned_plan(allocator, kind, &steps);
}

fn release_skip_names_for_facts(facts: PathCleanupFacts) []const []const u8 {
    if (!facts.cleanup_visible) return &.{};
    return facts.release_skip_names;
}

fn append_reverse_locals(
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
        if (has_name(skip_names, local.name)) continue;
        try steps.append(allocator, .{
            .local_name = local.name,
            .kind = local.kind,
            .reason = reason,
            .clear_after_release = clear_after_release,
        });
    }
}

fn owned_plan(
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

fn has_name(names: []const []const u8, name: []const u8) bool {
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

    const plan = try build_return_exit_plan_with_facts(allocator, &locals, facts);
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

    const plan = try build_loop_control_exit_plan(allocator, .break_stmt, &frames);
    defer plan.deinit(allocator);

    try std.testing.expectEqual(ExitKind.break_stmt, plan.kind);
    try std.testing.expectEqual(@as(usize, 2), plan.release_steps.len);
    try std.testing.expectEqualStrings("inner_keep", plan.release_steps[0].local_name);
    try std.testing.expectEqualStrings("outer_keep", plan.release_steps[1].local_name);
}
