const std = @import("std");
const generated_scalar_plan = @import("codegen_generated_async_scalar_plan.zig");
const abi_layout = @import("wit_abi_layout.zig");

const invalid_template = error.InvalidGenericAbiV2ScalarTemplate;

pub fn emit_scalar_i64(
    allocator: std.mem.Allocator,
    plan: generated_scalar_plan.GeneratedAsyncScalarPlan,
    layout: abi_layout.LayoutPlan,
) ![]u8 {
    const measured = layout.scalar_measurement orelse return error.InvalidGenericAbiV2ScalarLayout;
    if (measured.offset != plan.payload.offset or
        measured.byte_size != plan.payload.byte_size or
        measured.alignment != plan.payload.alignment or
        measured.core_type != .i64 or
        !std.mem.eql(u8, plan.payload.core_type, "i64") or
        !std.mem.eql(u8, plan.payload.encoding, "core-s64"))
    {
        return error.InvalidGenericAbiV2ScalarLayout;
    }

    var wat = try allocator.dupe(u8, @embedFile("generated_async_scalar_i64_v2_template.wat"));
    errdefer allocator.free(wat);
    var offset_buf: [32]u8 = undefined;
    var size_buf: [32]u8 = undefined;
    var alignment_buf: [32]u8 = undefined;
    const offset = try std.fmt.bufPrint(&offset_buf, "{}", .{measured.offset});
    const size = try std.fmt.bufPrint(&size_buf, "{}", .{measured.byte_size});
    const alignment = try std.fmt.bufPrint(&alignment_buf, "{}", .{measured.alignment});

    wat = try replace_required(allocator, wat, "__V2_ASYNC_IMPORT_MODULE__", plan.async_import_module);
    wat = try replace_required(allocator, wat, "__V2_ASYNC_IMPORT_NAME__", plan.async_import_name);
    wat = try replace_required(allocator, wat, "__V2_ASYNC_COMPLETION__", plan.completion);
    wat = try replace_required(allocator, wat, "__V2_PAYLOAD_OFFSET__", offset);
    wat = try replace_required(allocator, wat, "__V2_PAYLOAD_BYTE_SIZE__", size);
    wat = try replace_required(allocator, wat, "__V2_PAYLOAD_ALIGNMENT__", alignment);
    wat = try replace_required(allocator, wat, "__V2_PAYLOAD_ENCODING__", "core-s64");
    wat = try replace_required(allocator, wat, "__PAYLOAD_LOAD__", "i64.load");
    wat = try replace_required(allocator, wat, "__PAYLOAD_STORE__", "i64.store");
    wat = try replace_required(allocator, wat, "__PAYLOAD_ZERO__", "i64.const 0");
    return wat;
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
    while (std.mem.indexOf(u8, remainder, needle)) |idx| {
        found = true;
        try out.appendSlice(allocator, remainder[0..idx]);
        try out.appendSlice(allocator, replacement);
        remainder = remainder[idx + needle.len ..];
    }
    if (!found) return invalid_template;
    try out.appendSlice(allocator, remainder);
    const owned = try out.toOwnedSlice(allocator);
    allocator.free(input);
    return owned;
}
