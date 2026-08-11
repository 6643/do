const std = @import("std");
const representation = @import("codegen_gc_representation.zig");
const roots = @import("codegen_gc_roots.zig");
const abi = @import("codegen_component_abi_plan.zig");
const resources = @import("codegen_component_resource_plan.zig");

test "GC root plan excludes inline values and rejects resources" {
    const locals = [_]roots.RootLocal{
        .{ .name = "count", .rep = .inline_value },
        .{ .name = "message", .rep = .gc_managed },
    };
    const plan = try roots.build_root_plan(std.testing.allocator, locals[0..], .synchronous);
    defer roots.deinit_root_plan(std.testing.allocator, plan);

    try std.testing.expectEqual(@as(usize, 1), plan.slots.len);
    try std.testing.expectEqualStrings("message", plan.slots[0].name);
    try std.testing.expectEqual(roots.RootPoint.local_bind, plan.slots[0].point);

    const resource_locals = [_]roots.RootLocal{
        .{ .name = "file", .rep = .resource_handle },
    };
    try std.testing.expectError(error.ResourceCannotBeGcRoot, roots.build_root_plan(std.testing.allocator, resource_locals[0..], .synchronous));
}

test "ABI plan rejects GC references at canonical boundary" {
    const illegal = abi.AbiPlan{
        .package = "pkg",
        .world = "world",
        .member = "call",
        .arguments = &.{.{ .source_type = "text", .canonical_type = "(ref null $do_text)", .direction = .lower, .contains_gc_reference = true }},
        .results = &.{},
    };
    try std.testing.expectError(error.GcReferenceCannotCrossCanonicalAbi, abi.validate_abi_plan(illegal));
}

test "resource plan requires exactly one terminal action" {
    const transfers = [_]resources.ResourceTransfer{
        .{ .type_name = "File", .direction = .own_in, .drop_authority = true },
    };
    const duplicate = resources.ResourceFacts{
        .transfers = transfers[0..],
        .terminal_actions = &.{ .drop_owned, .drop_owned },
    };
    try std.testing.expectError(error.DuplicateTerminalCleanup, resources.build_resource_plan(std.testing.allocator, duplicate));
}

test "resource plan preserves a single terminal action" {
    const facts = resources.ResourceFacts{
        .transfers = &.{},
        .terminal_actions = &.{.no_resource},
    };
    const plan = try resources.build_resource_plan(std.testing.allocator, facts);
    defer resources.deinit_resource_plan(std.testing.allocator, plan);
    try std.testing.expectEqual(resources.TerminalAction.no_resource, plan.terminal_action);
}

test "representation type remains shared by the three plans" {
    try std.testing.expectEqual(representation.ValueRep.gc_managed, try representation.classify_type("text", &.{}, &.{}));
}
