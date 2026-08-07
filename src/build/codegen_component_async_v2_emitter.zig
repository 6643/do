const std = @import("std");
const manifest = @import("p3_async_manifest.zig");
const abi_layout = @import("wit_abi_layout.zig");
const abi_types = @import("wit_abi_types.zig");

const invalid_template = error.InvalidGenericAbiV2Template;

pub fn emit_variant_resource_stream(
    allocator: std.mem.Allocator,
    descriptor: manifest.Descriptor,
    shape: manifest.VariantResourceStreamShape,
    layout: abi_layout.LayoutPlan,
) ![]u8 {
    if (layout.byte_size != shape.event.byte_size or
        layout.alignment != shape.event.alignment)
    {
        return error.InvalidGenericAbiV2Layout;
    }

    var wat = try allocator.dupe(u8, @embedFile("variant_resource_stream_v2_template.wat"));
    errdefer allocator.free(wat);

    const probe_module = try probe_module_name(allocator, descriptor.wit.package);
    defer allocator.free(probe_module);

    wat = try replace_required(allocator, wat, "__SOURCE_MODULE__", descriptor.canonical.async_import_module);
    wat = try replace_required(allocator, wat, "__PROBE_MODULE__", probe_module);
    wat = try replace_required(allocator, wat, "__ACQUIRE__", descriptor.canonical.async_import_name);
    wat = try replace_required(allocator, wat, "__STREAM_READ__", shape.stream_read.import_name);
    wat = try replace_required(allocator, wat, "__STREAM_DROP__", shape.stream_drop_readable.import_name);
    wat = try replace_required(allocator, wat, "__FUTURE_READ__", shape.future_read.import_name);
    wat = try replace_required(allocator, wat, "__FUTURE_DROP__", shape.future_drop_readable.import_name);
    wat = try replace_required(allocator, wat, "__RESOURCE_DROP__", shape.ticket_drop_import);
    wat = try replace_required(allocator, wat, "__TASK_RETURN__", "[task-return]run");

    wat = try replace_number(allocator, wat, "__EVENT_RESULT_POINTER__", 64);
    wat = try replace_number(allocator, wat, "__EVENT_TAG_OFFSET__", shape.event.tag_offset);
    wat = try replace_number(allocator, wat, "__EVENT_PAYLOAD_OFFSET__", shape.event.payload_offset);
    wat = try replace_number(allocator, wat, "__EVENT_SIZE__", layout.byte_size);
    wat = try replace_number(allocator, wat, "__EVENT_ALIGNMENT__", layout.alignment);
    return wat;
}

fn probe_module_name(allocator: std.mem.Allocator, package: []const u8) ![]u8 {
    const at = std.mem.lastIndexOfScalar(u8, package, '@') orelse return invalid_template;
    if (at == 0 or at + 1 >= package.len) return invalid_template;
    return try std.fmt.allocPrint(allocator, "{s}/probe{s}", .{ package[0..at], package[at..] });
}

fn replace_number(
    allocator: std.mem.Allocator,
    input: []u8,
    needle: []const u8,
    value: u32,
) ![]u8 {
    var buffer: [32]u8 = undefined;
    const replacement = try std.fmt.bufPrint(&buffer, "{}", .{value});
    return replace_required(allocator, input, needle, replacement);
}

fn replace_required(
    allocator: std.mem.Allocator,
    input: []u8,
    needle: []const u8,
    replacement: []const u8,
) ![]u8 {
    if (needle.len == 0) return invalid_template;
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var remainder = input;
    var found = false;
    while (std.mem.indexOf(u8, remainder, needle)) |index| {
        found = true;
        try out.appendSlice(allocator, remainder[0..index]);
        try out.appendSlice(allocator, replacement);
        remainder = remainder[index + needle.len ..];
    }
    if (!found) return invalid_template;
    try out.appendSlice(allocator, remainder);
    const result = try out.toOwnedSlice(allocator);
    allocator.free(input);
    return result;
}

test "independent v2 emitter renders descriptor imports and measured layout" {
    var descriptor = try manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer descriptor.deinit(std.testing.allocator);
    const item = descriptor.find("do:variant-resource-stream-canonical@0.1.0", "read-via-stream") orelse unreachable;
    const shape = switch (manifest.lowering_shape(item).?) {
        .variant_resource_stream_reader => |value| value,
        else => unreachable,
    };
    const measured_event = shape.event;
    const result = try std.fmt.allocPrint(std.testing.allocator, "tag={} payload={} size={} align={}", .{
        measured_event.tag_offset,
        measured_event.payload_offset,
        measured_event.byte_size,
        measured_event.alignment,
    });
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "tag=0") != null);
    var ticket = try abi_types.AbiType.resource(std.testing.allocator, "ticket", .own);
    defer ticket.deinit();
    var error_code = abi_types.AbiType.scalar(std.testing.allocator, .i32);
    defer error_code.deinit();
    var event = try abi_types.AbiType.variant(std.testing.allocator, &.{
        .{ .tag = 0, .name = "ticket", .payload = &ticket },
        .{ .tag = 1, .name = "idle", .payload = null },
        .{ .tag = 2, .name = "failed", .payload = &error_code },
    });
    defer event.deinit();
    var plan = try abi_layout.LayoutPlan.variant(std.testing.allocator, &event, .{
        .tag_offset = measured_event.tag_offset,
        .payload_offset = measured_event.payload_offset,
        .byte_size = measured_event.byte_size,
        .alignment = measured_event.alignment,
        .cases = &.{
            .{ .name = "ticket", .tag = 0, .payload_required = true, .payload = .{ .offset = 4, .byte_size = 4, .alignment = 4, .core_type = .i32 } },
            .{ .name = "idle", .tag = 1, .payload_required = false, .payload = null },
            .{ .name = "failed", .tag = 2, .payload_required = true, .payload = .{ .offset = 4, .byte_size = 4, .alignment = 4, .core_type = .i32 } },
        },
    });
    defer plan.deinit();
    const wat = try emit_variant_resource_stream(std.testing.allocator, item, shape, plan);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "generic ABI v2 independent descriptor emitter template") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__SOURCE_MODULE__") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lower][stream-read-0]read-via-stream") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 0") != null);
}
