const std = @import("std");
const p3_async_manifest = @import("p3_async_manifest.zig");
const future_owned_plan = @import("codegen_component_future_owned_plan.zig");
const component_abi = @import("codegen_component_abi_plan.zig");
const component_resources = @import("codegen_component_resource_plan.zig");

const future_owned_wat = @embedFile("future_owned_component_template.wat");

pub fn emit_component_wat(
    allocator: std.mem.Allocator,
    plan: future_owned_plan.FutureOwnedPlan,
) ![]u8 {
    try component_abi.validate_abi_plan(plan.abi_plan);
    if (plan.resource_plan.terminal_state != .pending) return error.TerminalAlreadyDecided;
    const shape = switch (p3_async_manifest.lowering_shape(plan.descriptor) orelse return error.UnsupportedP3OwnedFutureComponent) {
        .future_owned_resource => |value| value,
        else => return error.UnsupportedP3OwnedFutureComponent,
    };
    if (shape.payload_offset != plan.payload_offset or
        shape.resource_offset != plan.resource_offset or
        shape.presence_offset != plan.presence_offset or
        !std.mem.eql(u8, shape.drop_import, plan.drop_import)) return error.UnsupportedP3OwnedFutureComponent;
    const markers = try std.fmt.allocPrint(
        allocator,
        "(module\n  ;; [gc-root-plan] suspendable-fields={d}\n  ;; [abi-plan] arguments={d} results={d}\n  ;; [resource-terminal] {s}\n",
        .{ plan.root_plan.fields.len, plan.abi_plan.arguments.len, plan.abi_plan.results.len, terminal_action_name(plan.resource_plan.terminal_action) },
    );
    defer allocator.free(markers);
    const wat = try allocator.dupe(u8, future_owned_wat);
    errdefer allocator.free(wat);
    return replace_all(allocator, wat, "(module\n", markers);
}

fn terminal_action_name(action: component_resources.TerminalAction) []const u8 {
    return switch (action) {
        .no_resource => "no_resource",
        .drop_owned => "drop_owned",
        .retain_for_host => "retain_for_host",
    };
}

fn replace_all(allocator: std.mem.Allocator, input: []u8, needle: []const u8, replacement: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    const index = std.mem.indexOf(u8, input, needle) orelse return error.InvalidTemplate;
    try out.appendSlice(allocator, input[0..index]);
    try out.appendSlice(allocator, replacement);
    try out.appendSlice(allocator, input[index + needle.len ..]);
    allocator.free(input);
    return out.toOwnedSlice(allocator);
}

pub fn emit_component_wit(allocator: std.mem.Allocator) ![]u8 {
    return allocator.dupe(
        u8,
        "package do:future-owned-canonical@0.1.0;\n\n" ++
            "interface source {\n  resource ticket {}\n  read: func() -> future<own<ticket>>;\n}\n\n" ++
            "interface probe {\n  run: async func(mode: u32);\n}\n\n" ++
            "world future-owned-canonical {\n  import source;\n  export probe;\n}\n",
    );
}
