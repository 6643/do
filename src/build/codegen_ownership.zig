//! Ownership release plan emit (ARC scope exits).
const std = @import("std");
const ownership = @import("ownership.zig");
const codegen_names = @import("codegen_names.zig");
const constants = @import("codegen_constants.zig");
const model = @import("codegen_model.zig");
const context = @import("codegen_context.zig");
const codegen_storage_layout = @import("codegen_storage_layout.zig");
const codegen_collect_util = @import("codegen_collect_util.zig");
const codegen_collect_functions = @import("codegen_collect_functions.zig");
const codegen_collect_structs = @import("codegen_collect_structs.zig");

const append_fmt = codegen_names.append_fmt;
const STORAGE_OVERWRITE_TMP_LOCAL = constants.STORAGE_OVERWRITE_TMP_LOCAL;

const LocalSet = context.LocalSet;
const CodegenContext = context.CodegenContext;
const CodegenError = model.CodegenError;
const find_struct_layout = codegen_collect_util.find_struct_layout;
const is_managed_local_type = codegen_storage_layout.is_managed_local_type;
const is_managed_payload_type = codegen_storage_layout.is_managed_payload_type;

pub fn emit_replace_managed_local_from_tmp(
    allocator: std.mem.Allocator,
    name: []const u8,
    out: *std.ArrayList(u8),
) !void {
    try append_fmt(allocator, out, "    ;; arc-overwrite-release {[name]s}\n", .{ .name = name });
    try append_fmt(allocator, out, "    local.get ${[STORAGE_OVERWRITE_TMP_LOCAL]s}\n", .{ .STORAGE_OVERWRITE_TMP_LOCAL = STORAGE_OVERWRITE_TMP_LOCAL });
    try append_fmt(allocator, out, "    local.get ${[name]s}\n", .{ .name = name });
    try out.appendSlice(allocator, "    i32.ne\n");
    try out.appendSlice(allocator, "    if\n");
    try append_fmt(allocator, out, "      local.get ${[name]s}\n", .{ .name = name });
    try out.appendSlice(allocator, "      call $__arc_dec\n");
    try out.appendSlice(allocator, "    end\n");
    try append_fmt(allocator, out, "    local.get ${[STORAGE_OVERWRITE_TMP_LOCAL]s}\n", .{ .STORAGE_OVERWRITE_TMP_LOCAL = STORAGE_OVERWRITE_TMP_LOCAL });
    try append_fmt(allocator, out, "    local.set ${[name]s}\n", .{ .name = name });
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
        try append_fmt(allocator, out, "    ;; arc-release-local {[local_name]s}\n", .{ .local_name = step.local_name });
        try append_fmt(allocator, out, "    local.get ${[local_name]s}\n", .{ .local_name = step.local_name });
        try out.appendSlice(allocator, "    call $__arc_dec\n");
        if (!step.clear_after_release) continue;
        try out.appendSlice(allocator, "    i32.const 0\n");
        try append_fmt(allocator, out, "    local.set ${[local_name]s}\n", .{ .local_name = step.local_name });
    }
}
