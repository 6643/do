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

pub const ManagedLocal = struct {
    name: []const u8,
    kind: ManagedLocalKind,
};

pub const LoopFrame = struct {
    locals: []const ManagedLocal,
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
    return buildLocalExitPlan(allocator, .return_stmt, .return_cleanup, locals, skip_names, false);
}

pub fn buildGuardReturnExitPlan(
    allocator: std.mem.Allocator,
    locals: []const ManagedLocal,
    skip_names: []const []const u8,
) !ExitPlan {
    return buildLocalExitPlan(allocator, .guard_return, .guard_return_cleanup, locals, skip_names, false);
}

pub fn buildFallthroughExitPlan(
    allocator: std.mem.Allocator,
    locals: []const ManagedLocal,
) !ExitPlan {
    return buildLocalExitPlan(allocator, .fallthrough, .fallthrough_cleanup, locals, &.{}, false);
}

pub fn buildBlockExitPlan(
    allocator: std.mem.Allocator,
    locals: []const ManagedLocal,
) !ExitPlan {
    return buildLocalExitPlan(allocator, .block_exit, .block_exit, locals, &.{}, true);
}

pub fn buildLoopControlExitPlan(
    allocator: std.mem.Allocator,
    kind: ExitKind,
    frames: []const LoopFrame,
) !ExitPlan {
    var steps = std.ArrayList(ReleaseStep).empty;
    errdefer steps.deinit(allocator);

    for (frames) |frame| {
        try appendReverseLocals(&steps, allocator, frame.locals, &.{}, .loop_control, true);
    }

    return ownedPlan(allocator, kind, &steps);
}

fn buildLocalExitPlan(
    allocator: std.mem.Allocator,
    kind: ExitKind,
    reason: ReleaseReason,
    locals: []const ManagedLocal,
    skip_names: []const []const u8,
    clear_after_release: bool,
) !ExitPlan {
    var steps = std.ArrayList(ReleaseStep).empty;
    errdefer steps.deinit(allocator);

    try appendReverseLocals(&steps, allocator, locals, skip_names, reason, clear_after_release);
    return ownedPlan(allocator, kind, &steps);
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
