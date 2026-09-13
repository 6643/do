const std = @import("std");
const state_ir = @import("codegen_component_producer_state_ir.zig");

pub const FragmentKind = enum { prefix, payload, lifecycle, metadata, suffix };

pub const SourceSpan = struct {
    start: u32,
    end: u32,
};

pub const Fragment = struct {
    name: []const u8,
    kind: FragmentKind,
    span: SourceSpan,
    required_markers: []const []const u8,
    order: u16,
};

pub const FragmentError = error{
    EmptyTable,
    EmptyName,
    InvalidSpan,
    SpanOutsideTemplate,
    FragmentGap,
    FragmentOverlap,
    OrderDrift,
    InvalidKindOrder,
    WholeTemplateFragment,
    MissingMarker,
    LifecycleMismatch,
    OutOfMemory,
};

pub fn validate_fragment_table(template: []const u8, fragment_table: []const Fragment) FragmentError!void {
    if (fragment_table.len == 0) return error.EmptyTable;
    if (fragment_table.len > @as(usize, std.math.maxInt(u16)) + 1) return error.OrderDrift;

    for (fragment_table) |fragment| {
        if (fragment.name.len == 0) return error.EmptyName;
        if (@as(u64, fragment.span.start) > template.len or @as(u64, fragment.span.end) > template.len) {
            return error.SpanOutsideTemplate;
        }
        if (fragment.span.start >= fragment.span.end) return error.InvalidSpan;
        if (fragment.span.start == 0 and @as(usize, fragment.span.end) == template.len) {
            return error.WholeTemplateFragment;
        }

        const source = template[@as(usize, fragment.span.start)..@as(usize, fragment.span.end)];
        for (fragment.required_markers) |marker| {
            if (marker.len == 0 or std.mem.indexOf(u8, source, marker) == null) {
                return error.MissingMarker;
            }
        }
    }

    var cursor: u32 = 0;
    var previous_kind: ?FragmentKind = null;
    for (0..fragment_table.len) |index| {
        const fragment = fragment_for_order(fragment_table, @intCast(index)) orelse return error.OrderDrift;
        if (fragment.span.start != cursor) {
            if (fragment.span.start > cursor) return error.FragmentGap;
            return error.FragmentOverlap;
        }
        if (index == 0 and fragment.kind != .prefix) return error.InvalidKindOrder;
        if (index + 1 == fragment_table.len and fragment.kind != .suffix) return error.InvalidKindOrder;
        if (previous_kind) |kind| {
            if (kind_rank(fragment.kind) < kind_rank(kind)) return error.InvalidKindOrder;
        }
        previous_kind = fragment.kind;
        cursor = fragment.span.end;
    }
    if (@as(usize, cursor) < template.len) return error.FragmentGap;
    if (@as(usize, cursor) > template.len) return error.FragmentOverlap;
}

pub fn assemble(allocator: std.mem.Allocator, template: []const u8, fragment_table: []const Fragment) FragmentError![]u8 {
    try validate_fragment_table(template, fragment_table);
    return assemble_validated(allocator, template, fragment_table);
}

pub fn assemble_with_lifecycle(
    allocator: std.mem.Allocator,
    template: []const u8,
    fragment_table: []const Fragment,
    lifecycle: state_ir.LifecycleStateIR,
) FragmentError![]u8 {
    try validate_fragment_table(template, fragment_table);
    try validate_lifecycle_assembly(template, fragment_table, lifecycle);
    return assemble_validated(allocator, template, fragment_table);
}

fn assemble_validated(allocator: std.mem.Allocator, template: []const u8, fragment_table: []const Fragment) FragmentError![]u8 {
    const output = allocator.alloc(u8, template.len) catch |err| return err;
    errdefer allocator.free(output);

    var cursor: usize = 0;
    for (0..fragment_table.len) |index| {
        const fragment = fragment_for_order(fragment_table, @intCast(index)) orelse return error.OrderDrift;
        const start: usize = @intCast(fragment.span.start);
        const end: usize = @intCast(fragment.span.end);
        std.mem.copyForwards(u8, output[cursor..], template[start..end]);
        cursor += end - start;
    }
    return output;
}

fn validate_lifecycle_assembly(
    template: []const u8,
    fragment_table: []const Fragment,
    lifecycle: state_ir.LifecycleStateIR,
) FragmentError!void {
    if (lifecycle.asset_count == 0 or lifecycle.group_count == 0 or
        lifecycle.transfer_count != lifecycle.group_count or
        lifecycle.barrier_count != lifecycle.group_count or lifecycle.cleanup_count == 0 or
        lifecycle.lifecycle_anchors.len == 0)
    {
        return error.LifecycleMismatch;
    }

    var lifecycle_fragment_count: usize = 0;
    for (fragment_table) |fragment| {
        if (fragment.kind == .lifecycle) lifecycle_fragment_count += 1;
    }
    if (lifecycle_fragment_count != 1) return error.LifecycleMismatch;

    for (lifecycle.lifecycle_anchors) |anchor| {
        for (anchor.required_text) |required| {
            if (required.len == 0 or std.mem.indexOf(u8, template, required) == null) return error.LifecycleMismatch;
        }
        var cursor: usize = 0;
        for (anchor.ordered_anchors) |ordered| {
            const found = std.mem.indexOfPos(u8, template, cursor, ordered) orelse return error.LifecycleMismatch;
            cursor = found + ordered.len;
        }
    }
}

fn fragment_for_order(fragment_table: []const Fragment, order: u16) ?Fragment {
    for (fragment_table) |fragment| {
        if (fragment.order == order) return fragment;
    }
    return null;
}

fn kind_rank(kind: FragmentKind) u8 {
    return switch (kind) {
        .prefix => 0,
        .payload => 1,
        .lifecycle => 2,
        .metadata => 3,
        .suffix => 4,
    };
}
