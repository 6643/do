//! Union layout types and pure layout helpers (no emit / no LocalSet).
const std = @import("std");

pub const UnionBranch = struct {
    /// Flat union: arm type name. Payload enum: case name (Text / Quit).
    ty: []const u8,
    tag: usize,
    payload_start: usize,
    payload_len: usize,
    /// When set (payload-enum cases with payload), actual payload type for emit/narrow (e.g. [u8]).
    payload_type: ?[]const u8 = null,
};

pub const UnionLayout = struct {
    source_ty: []const u8,
    branches: []const UnionBranch,
    payload_tys: []const []const u8,
};

pub fn union_layouts_equal(a: UnionLayout, b: UnionLayout) bool {
    if (a.branches.len != b.branches.len) return false;
    if (a.payload_tys.len != b.payload_tys.len) return false;
    for (a.payload_tys, 0..) |ty, idx| {
        if (!std.mem.eql(u8, ty, b.payload_tys[idx])) return false;
    }
    for (a.branches, 0..) |branch, idx| {
        const other = b.branches[idx];
        if (!std.mem.eql(u8, branch.ty, other.ty)) return false;
        if (branch.tag != other.tag) return false;
        if (branch.payload_start != other.payload_start) return false;
        if (branch.payload_len != other.payload_len) return false;
    }
    return true;
}

pub fn free_union_layout(allocator: std.mem.Allocator, layout: UnionLayout) void {
    allocator.free(layout.branches);
    allocator.free(layout.payload_tys);
}

pub fn clone_union_layout(allocator: std.mem.Allocator, layout: UnionLayout) !UnionLayout {
    const branches = try allocator.dupe(UnionBranch, layout.branches);
    errdefer allocator.free(branches);
    const payload_tys = try allocator.dupe([]const u8, layout.payload_tys);
    return .{
        .source_ty = layout.source_ty,
        .branches = branches,
        .payload_tys = payload_tys,
    };
}

pub fn union_branch_is_status_i32(layout: UnionLayout, branch: UnionBranch) bool {
    return std.mem.eql(u8, branch.ty, "i32") and branch.payload_len == 1 and
        branch.payload_start < layout.payload_tys.len and
        std.mem.eql(u8, layout.payload_tys[branch.payload_start], "i32");
}

