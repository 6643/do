const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");
const sema_tokens = @import("sema_tokens.zig");

pub fn emit_component_wat(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) anyerror![]u8 {
    _ = program;
    _ = module_graph;
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    var plan = RecordStreamSourcePlan.analyze(tokens, registry) catch return error.UnsupportedP3RecordStreamComponent;
    defer plan.deinit(allocator);
    return emit_record_stream_wat(allocator, plan);
}

pub fn emit_component_wit(allocator: std.mem.Allocator, tokens: []const lexer.Token) anyerror![]u8 {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    var plan = RecordStreamSourcePlan.analyze(tokens, registry) catch return error.UnsupportedP3RecordStreamComponent;
    defer plan.deinit(allocator);
    return emit_record_stream_wit(allocator, plan);
}

fn emit_record_stream_wat(allocator: std.mem.Allocator, plan: RecordStreamSourcePlan) ![]u8 {
    const shape = switch (p3_async_manifest.lowering_shape(plan.descriptor) orelse return error.UnsupportedP3RecordStreamComponent) {
        .record_stream_reader => |value| value,
        else => return error.UnsupportedP3RecordStreamComponent,
    };
    const stream = shape.stream;
    const future = shape.future;
    const layout = shape.record_layout orelse return error.UnsupportedP3RecordStreamComponent;
    const record_area_offset: u32 = 64;
    const owned_area_offset = record_area_offset + align_u32(layout.byte_size, 4);
    const completion_area_offset = owned_area_offset + try record_owned_size(layout);
    const frame_size = align_u32(completion_area_offset + 8, 16);
    const record_active_offset: u32 = 16;
    const decode_body = try build_record_decode_body(allocator, layout, record_area_offset, owned_area_offset, record_active_offset);
    defer allocator.free(decode_body);
    const field_markers = try build_record_field_markers(allocator, layout);
    defer allocator.free(field_markers);
    const resource_drop_imports = try build_resource_drop_imports(allocator, layout, plan.descriptor.canonical.async_import_module);
    defer allocator.free(resource_drop_imports);
    const resource_release_body = try build_record_resource_release_body(allocator, layout, owned_area_offset, record_active_offset);
    defer allocator.free(resource_release_body);

    const export_name = try sanitized_name(allocator, plan.export_name);
    defer allocator.free(export_name);
    const export_locator = try component_export_locator(allocator, plan.descriptor.wit.package, "probe");
    defer allocator.free(export_locator);
    const task_return_name = try std.fmt.allocPrint(allocator, "[task-return]{s}", .{export_name});
    defer allocator.free(task_return_name);
    const async_lift_name = try std.fmt.allocPrint(allocator, "[async-lift]{s}#{s}", .{ export_locator, export_name });
    defer allocator.free(async_lift_name);
    const callback_name = try std.fmt.allocPrint(allocator, "[callback][async-lift]{s}#{s}", .{ export_locator, export_name });
    defer allocator.free(callback_name);
    const task_return_module = try std.fmt.allocPrint(allocator, "[export]{s}", .{export_locator});
    defer allocator.free(task_return_module);
    const record_area_text = try decimal_text(allocator, record_area_offset);
    defer allocator.free(record_area_text);
    const owned_area_text = try decimal_text(allocator, owned_area_offset);
    defer allocator.free(owned_area_text);
    const completion_area_text = try decimal_text(allocator, completion_area_offset);
    defer allocator.free(completion_area_text);
    const frame_size_text = try decimal_text(allocator, frame_size);
    defer allocator.free(frame_size_text);
    const method_type = try wat_func_type(allocator, "record-stream-acquire", shape.method.core_params, shape.method.core_results);
    defer allocator.free(method_type);
    const wat_stream_read_type = try wat_func_type(allocator, "stream-read", stream.read.core_params, stream.read.core_results);
    defer allocator.free(wat_stream_read_type);
    const wat_future_read_type = try wat_func_type(allocator, "future-read", future.read.?.core_params, future.read.?.core_results);
    defer allocator.free(wat_future_read_type);

    var wat = try allocator.dupe(u8, generic_record_stream_core_wat);
    errdefer allocator.free(wat);
    const replacements = [_][2][]const u8{
        .{ "[method-type]", method_type },
        .{ "[stream-read-type]", wat_stream_read_type },
        .{ "[future-read-type]", wat_future_read_type },
        .{ "[source-module]", plan.descriptor.canonical.async_import_module },
        .{ "[source-acquire-name]", shape.method.import_name },
        .{ "[stream-read-name]", stream.read.import_name },
        .{ "[stream-drop-name]", stream.drop_readable.import_name },
        .{ "[future-read-name]", future.read.?.import_name },
        .{ "[future-drop-name]", future.drop_readable.import_name },
        .{ "[task-return-name]", task_return_name },
        .{ "[task-return-module]", task_return_module },
        .{ "[async-lift-name]", async_lift_name },
        .{ "[callback-name]", callback_name },
        .{ "[record-area-offset]", record_area_text },
        .{ "[owned-area-offset]", owned_area_text },
        .{ "[completion-area-offset]", completion_area_text },
        .{ "[frame-size]", frame_size_text },
        .{ "[record-decode-body]", decode_body },
        .{ "[record-field-markers]", field_markers },
        .{ "[resource-drop-imports]", resource_drop_imports },
        .{ "[record-resource-release-body]", resource_release_body },
    };
    for (replacements) |replacement| {
        wat = try replace_and_free(allocator, wat, replacement[0], replacement[1]);
    }
    return wat;
}

fn emit_record_stream_wit(allocator: std.mem.Allocator, plan: RecordStreamSourcePlan) ![]u8 {
    const shape = switch (p3_async_manifest.lowering_shape(plan.descriptor) orelse return error.UnsupportedP3RecordStreamComponent) {
        .record_stream_reader => |value| value,
        else => return error.UnsupportedP3RecordStreamComponent,
    };
    const layout = shape.record_layout orelse return error.UnsupportedP3RecordStreamComponent;
    const export_name = try sanitized_name(allocator, plan.export_name);
    defer allocator.free(export_name);
    const record_name = try wit_name(allocator, layout.name);
    defer allocator.free(record_name);
    const interface_name = try wit_name(allocator, plan.descriptor.wit.interface);
    defer allocator.free(interface_name);
    const world_name = try wit_name(allocator, plan.descriptor.wit.world);
    defer allocator.free(world_name);
    var wit = std.ArrayList(u8).empty;
    errdefer wit.deinit(allocator);
    if (has_owned_resource_field(layout)) {
        const resource_declarations = try build_wit_resource_declarations(allocator, layout);
        defer allocator.free(resource_declarations);
        const nested_declarations = try build_nested_wit_record_declarations(allocator, layout);
        defer allocator.free(nested_declarations);
        try append_fmt(allocator, &wit, "package {s};\n\ninterface types {{\n  enum error-code {{ io, no-entry }}\n}}\n\ninterface {s} {{\n  use types.{{error-code}};\n{s}{s}  record {s} {{\n", .{ plan.descriptor.wit.package, interface_name, resource_declarations, nested_declarations, record_name });
        try append_wit_record_fields(allocator, &wit, layout);
        try append_fmt(allocator, &wit, "  }}\n  {s}: func() -> tuple<stream<{s}>, future<result<_, error-code>>>;\n}}\n\ninterface probe {{\n  use types.{{error-code}};\n  {s}: async func() -> result<_, error-code>;\n}}\n\nworld {s} {{\n  import types;\n  import {s};\n  export probe;\n}}\n", .{ wit_name_borrowed(plan.descriptor.wit.operation), record_name, export_name, world_name, interface_name });
        return wit.toOwnedSlice(allocator);
    }
    try append_fmt(allocator, &wit, "package {s};\n\ninterface types {{\n  record {s} {{\n", .{ plan.descriptor.wit.package, record_name });
    for (layout.source_fields) |field| {
        const field_name = try wit_name(allocator, field.name);
        defer allocator.free(field_name);
        try append_fmt(allocator, &wit, "    {s}: {s},\n", .{ field_name, wit_source_type(field.source_type) });
    }
    try append_fmt(allocator, &wit, "  }}\n  enum error-code {{ io, no-entry }}\n}}\n\ninterface {s} {{\n  use types.{{error-code, {s}}};\n  {s}: func() -> tuple<stream<{s}>, future<result<_, error-code>>>;\n}}\n\ninterface probe {{\n  use types.{{error-code}};\n  {s}: async func() -> result<_, error-code>;\n}}\n\nworld {s} {{\n  import types;\n  import {s};\n  export probe;\n}}\n", .{ interface_name, record_name, wit_name_borrowed(plan.descriptor.wit.operation), record_name, export_name, world_name, interface_name });
    return wit.toOwnedSlice(allocator);
}

fn append_fmt(allocator: std.mem.Allocator, out: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
    const rendered = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(rendered);
    try out.appendSlice(allocator, rendered);
}

fn wat_func_type(allocator: std.mem.Allocator, name: []const u8, params: []const []const u8, results: []const []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try append_fmt(allocator, &out, "(type ${s} (func", .{name});
    for (params) |param| try append_fmt(allocator, &out, " (param {s})", .{param});
    if (results.len != 0) {
        try out.appendSlice(allocator, " (result");
        for (results) |result| try append_fmt(allocator, &out, " {s}", .{result});
        try out.appendSlice(allocator, ")");
    }
    try out.appendSlice(allocator, "))");
    return out.toOwnedSlice(allocator);
}

fn decimal_text(allocator: std.mem.Allocator, value: u32) ![]u8 {
    return std.fmt.allocPrint(allocator, "{d}", .{value});
}

fn align_u32(value: u32, alignment: u32) u32 {
    return (value + alignment - 1) / alignment * alignment;
}

fn record_owned_size(layout: p3_async_manifest.RecordLayout) !u32 {
    var size: u32 = 0;
    for (layout.source_fields) |field| {
        size += try owned_field_size(layout, field);
    }
    return size;
}

fn owned_field_size(layout: p3_async_manifest.RecordLayout, field: p3_async_manifest.RecordSourceField) !u32 {
    if (field.nested_fields.len != 0) {
        if (field.nested_fields.len != 1) return error.UnsupportedP3RecordStreamComponent;
        return nested_owned_size(layout, field.nested_fields[0]);
    }
    if (field.ownership == .own) return 4;
    if (std.mem.eql(u8, field.source_type, "string")) return 8;
    if (field.storage.len != 1) return error.UnsupportedP3RecordStreamComponent;
    const core_type = field_core_type(layout, field.storage[0]) orelse return error.UnsupportedP3RecordStreamComponent;
    return if (std.mem.eql(u8, core_type, "i64") or std.mem.eql(u8, core_type, "f64")) 8 else 4;
}

fn nested_owned_size(layout: p3_async_manifest.RecordLayout, field: p3_async_manifest.RecordNestedField) !u32 {
    if (field.nested_fields.len != 0) {
        if (field.nested_fields.len != 1) return error.UnsupportedP3RecordStreamComponent;
        return nested_owned_size(layout, field.nested_fields[0]);
    }
    if (field.ownership != .own or field.storage.len != 1 or field.resource == null) return error.UnsupportedP3RecordStreamComponent;
    return 4;
}

fn build_record_field_markers(allocator: std.mem.Allocator, layout: p3_async_manifest.RecordLayout) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    for (layout.source_fields) |field| {
        if (field.nested_fields.len != 0) {
            for (field.nested_fields) |nested| {
                try append_nested_field_markers(allocator, &out, layout, nested);
            }
            continue;
        }
        if (field.ownership == .own) {
            try append_fmt(allocator, &out, "    ;; [record-resource-field-{s}]\n", .{field.resource.?});
        }
        if (field.storage.len == 1) {
            const offset = storage_offset(layout, field.storage[0]) orelse return error.UnsupportedP3RecordStreamComponent;
            try append_fmt(allocator, &out, "    ;; [record-field-{s}-offset] {d}\n", .{ field.name, offset });
        } else if (field.storage.len == 2) {
            const ptr_offset = storage_offset(layout, field.storage[0]) orelse return error.UnsupportedP3RecordStreamComponent;
            const len_offset = storage_offset(layout, field.storage[1]) orelse return error.UnsupportedP3RecordStreamComponent;
            try append_fmt(allocator, &out, "    ;; [record-field-{s}-ptr-offset] {d}\n    ;; [record-field-{s}-len-offset] {d}\n", .{ field.name, ptr_offset, field.name, len_offset });
        }
    }
    return out.toOwnedSlice(allocator);
}

fn append_nested_field_markers(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    layout: p3_async_manifest.RecordLayout,
    field: p3_async_manifest.RecordNestedField,
) !void {
    if (field.nested_fields.len != 0) {
        if (field.nested_fields.len != 1) return error.UnsupportedP3RecordStreamComponent;
        return append_nested_field_markers(allocator, out, layout, field.nested_fields[0]);
    }
    if (field.ownership != .own or field.storage.len != 1 or field.resource == null) return error.UnsupportedP3RecordStreamComponent;
    const offset = storage_offset(layout, field.storage[0]) orelse return error.UnsupportedP3RecordStreamComponent;
    try append_fmt(allocator, out, "    ;; [record-resource-field-{s}]\n    ;; [record-field-{s}-offset] {d}\n", .{ field.resource.?, field.name, offset });
}

fn build_record_decode_body(allocator: std.mem.Allocator, layout: p3_async_manifest.RecordLayout, record_area_offset: u32, owned_area_offset: u32, record_active_offset: u32) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var owned_cursor: u32 = 0;
    for (layout.source_fields) |field| {
        if (field.nested_fields.len != 0) {
            for (field.nested_fields) |nested| {
                try append_nested_decode_body(allocator, &out, layout, nested, record_area_offset, owned_area_offset, record_active_offset, &owned_cursor);
            }
            continue;
        }
        if (field.ownership == .own) {
            if (field.storage.len != 1) return error.UnsupportedP3RecordStreamComponent;
            const offset = storage_offset(layout, field.storage[0]) orelse return error.UnsupportedP3RecordStreamComponent;
            try append_fmt(allocator, &out, "    ;; owned resource field {s}\n    local.get $frame\n    i32.const {d}\n    i32.add\n    local.get $frame\n    i32.const {d}\n    i32.add\n    i32.const {d}\n    i32.add\n    i32.load\n    i32.store\n    local.get $frame\n    i32.const {d}\n    i32.add\n    i32.const 1\n    i32.store\n", .{ field.name, owned_area_offset + owned_cursor, record_area_offset, offset, record_active_offset });
            owned_cursor += try owned_field_size(layout, field);
        } else if (std.mem.eql(u8, field.source_type, "string")) {
            if (field.storage.len != 2) return error.UnsupportedP3RecordStreamComponent;
            const ptr_offset = storage_offset(layout, field.storage[0]) orelse return error.UnsupportedP3RecordStreamComponent;
            const len_offset = storage_offset(layout, field.storage[1]) orelse return error.UnsupportedP3RecordStreamComponent;
            try append_fmt(allocator, &out, "    ;; source field {s}: UTF-8 pointer/length copied into owned storage\n    local.get $frame\n    i32.const {d}\n    i32.add\n    local.get $frame\n    i32.const {d}\n    i32.add\n    i32.const {d}\n    i32.add\n    i32.load\n    local.get $frame\n    i32.const {d}\n    i32.add\n    i32.const {d}\n    i32.add\n    i32.load\n    call $copy-text\n    i32.store\n", .{ field.name, owned_area_offset + owned_cursor, record_area_offset, ptr_offset, record_area_offset, len_offset });
            owned_cursor += try owned_field_size(layout, field);
        } else {
            if (field.storage.len != 1) return error.UnsupportedP3RecordStreamComponent;
            const storage_name = field.storage[0];
            const offset = storage_offset(layout, storage_name) orelse return error.UnsupportedP3RecordStreamComponent;
            const core_type = field_core_type(layout, storage_name) orelse return error.UnsupportedP3RecordStreamComponent;
            const load = core_load(core_type) orelse return error.UnsupportedP3RecordStreamComponent;
            const store = core_store(core_type) orelse return error.UnsupportedP3RecordStreamComponent;
            try append_fmt(allocator, &out, "    ;; source field {s}\n    local.get $frame\n    i32.const {d}\n    i32.add\n    local.get $frame\n    i32.const {d}\n    i32.add\n    i32.const {d}\n    i32.add\n    {s}\n    {s}\n", .{ field.name, owned_area_offset + owned_cursor, record_area_offset, offset, load, store });
            owned_cursor += try owned_field_size(layout, field);
        }
    }
    return out.toOwnedSlice(allocator);
}

fn append_nested_decode_body(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    layout: p3_async_manifest.RecordLayout,
    field: p3_async_manifest.RecordNestedField,
    record_area_offset: u32,
    owned_area_offset: u32,
    record_active_offset: u32,
    owned_cursor: *u32,
) !void {
    if (field.nested_fields.len != 0) {
        if (field.nested_fields.len != 1) return error.UnsupportedP3RecordStreamComponent;
        return append_nested_decode_body(allocator, out, layout, field.nested_fields[0], record_area_offset, owned_area_offset, record_active_offset, owned_cursor);
    }
    if (field.ownership != .own or field.storage.len != 1 or field.resource == null) return error.UnsupportedP3RecordStreamComponent;
    const offset = storage_offset(layout, field.storage[0]) orelse return error.UnsupportedP3RecordStreamComponent;
    try append_fmt(allocator, out, "    ;; nested owned resource field {s}\n    ;; [record-resource-field-{s}]\n    local.get $frame\n    i32.const {d}\n    i32.add\n    local.get $frame\n    i32.const {d}\n    i32.add\n    i32.const {d}\n    i32.add\n    i32.load\n    i32.store\n    local.get $frame\n    i32.const {d}\n    i32.add\n    i32.const 1\n    i32.store\n", .{ field.name, field.resource.?, owned_area_offset + owned_cursor.*, record_area_offset, offset, record_active_offset });
    owned_cursor.* += 4;
}

fn has_owned_resource_field(layout: p3_async_manifest.RecordLayout) bool {
    for (layout.source_fields) |field| {
        if (field.ownership == .own) return true;
        if (has_nested_owned_resource(field.nested_fields)) return true;
    }
    return false;
}

fn has_nested_owned_resource(fields: []const p3_async_manifest.RecordNestedField) bool {
    for (fields) |field| {
        if (field.ownership == .own or has_nested_owned_resource(field.nested_fields)) return true;
    }
    return false;
}

fn build_wit_resource_declarations(allocator: std.mem.Allocator, layout: p3_async_manifest.RecordLayout) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var seen = std.ArrayList([]const u8).empty;
    defer seen.deinit(allocator);
    for (layout.source_fields) |field| {
        if (field.ownership == .own) {
            try append_wit_resource_declaration(allocator, &out, &seen, field.resource orelse return error.UnsupportedP3RecordStreamComponent);
        } else {
            try append_nested_wit_resources(allocator, &out, &seen, field.nested_fields);
        }
    }
    try out.appendSlice(allocator, "\n");
    return out.toOwnedSlice(allocator);
}

fn append_wit_resource_declaration(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    seen: *std.ArrayList([]const u8),
    resource: []const u8,
) !void {
    for (seen.items) |previous| {
        if (std.mem.eql(u8, previous, resource)) return;
    }
    try seen.append(allocator, resource);
    const resource_name = try wit_name(allocator, resource);
    defer allocator.free(resource_name);
    try append_fmt(allocator, out, "  resource {s} {{}}\n", .{resource_name});
}

fn append_nested_wit_resources(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    seen: *std.ArrayList([]const u8),
    fields: []const p3_async_manifest.RecordNestedField,
) !void {
    for (fields) |field| {
        if (field.nested_fields.len != 0) {
            if (field.nested_fields.len != 1) return error.UnsupportedP3RecordStreamComponent;
            try append_nested_wit_resources(allocator, out, seen, field.nested_fields);
        } else if (field.ownership == .own) {
            try append_wit_resource_declaration(allocator, out, seen, field.resource orelse return error.UnsupportedP3RecordStreamComponent);
        } else {
            return error.UnsupportedP3RecordStreamComponent;
        }
    }
}

fn nested_resource_name(field: p3_async_manifest.RecordSourceField) ?[]const u8 {
    if (field.nested_fields.len != 1) return null;
    return nested_resource_name_from_fields(field.nested_fields);
}

fn nested_resource_name_from_fields(fields: []const p3_async_manifest.RecordNestedField) ?[]const u8 {
    if (fields.len != 1) return null;
    const field = fields[0];
    if (field.nested_fields.len != 0) return nested_resource_name_from_fields(field.nested_fields);
    return if (field.ownership == .own) field.resource else null;
}

fn build_nested_wit_record_declarations(allocator: std.mem.Allocator, layout: p3_async_manifest.RecordLayout) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    for (layout.source_fields) |field| {
        if (field.nested_fields.len == 0) continue;
        try append_nested_wit_record_declaration(allocator, &out, field.source_type, field.nested_fields);
    }
    return out.toOwnedSlice(allocator);
}

fn append_nested_wit_record_declaration(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    record_source_type: []const u8,
    fields: []const p3_async_manifest.RecordNestedField,
) !void {
    for (fields) |field| {
        if (field.nested_fields.len != 0) {
            if (field.nested_fields.len != 1) return error.UnsupportedP3RecordStreamComponent;
            try append_nested_wit_record_declaration(allocator, out, field.source_type, field.nested_fields);
        }
    }
    const record_name = try wit_name(allocator, record_source_type);
    defer allocator.free(record_name);
    try append_fmt(allocator, out, "  record {s} {{\n", .{record_name});
    for (fields) |field| {
        const field_name = try wit_name(allocator, field.name);
        defer allocator.free(field_name);
        if (field.nested_fields.len != 0) {
            if (field.nested_fields.len != 1) return error.UnsupportedP3RecordStreamComponent;
            const nested_name = try wit_name(allocator, field.source_type);
            defer allocator.free(nested_name);
            try append_fmt(allocator, out, "    {s}: {s},\n", .{ field_name, nested_name });
        } else if (field.ownership == .own) {
            const resource_name = try wit_name(allocator, field.resource orelse return error.UnsupportedP3RecordStreamComponent);
            defer allocator.free(resource_name);
            try append_fmt(allocator, out, "    {s}: own<{s}>,\n", .{ field_name, resource_name });
        } else {
            return error.UnsupportedP3RecordStreamComponent;
        }
    }
    try out.appendSlice(allocator, "  }\n");
}

fn append_wit_record_fields(allocator: std.mem.Allocator, out: *std.ArrayList(u8), layout: p3_async_manifest.RecordLayout) !void {
    for (layout.source_fields) |field| {
        const field_name = try wit_name(allocator, field.name);
        defer allocator.free(field_name);
        if (field.nested_fields.len != 0) {
            const nested_name = try wit_name(allocator, field.source_type);
            defer allocator.free(nested_name);
            try append_fmt(allocator, out, "    {s}: {s},\n", .{ field_name, nested_name });
        } else if (field.ownership == .own) {
            const resource_name = try wit_name(allocator, field.resource.?);
            defer allocator.free(resource_name);
            try append_fmt(allocator, out, "    {s}: own<{s}>,\n", .{ field_name, resource_name });
        } else {
            try append_fmt(allocator, out, "    {s}: {s},\n", .{ field_name, wit_source_type(field.source_type) });
        }
    }
}

fn build_resource_drop_imports(allocator: std.mem.Allocator, layout: p3_async_manifest.RecordLayout, module: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var seen = std.ArrayList(ResourceDropKey).empty;
    defer seen.deinit(allocator);
    for (layout.source_fields) |field| {
        if (field.ownership == .own) {
            try append_resource_drop_import(allocator, &out, &seen, module, field.resource orelse return error.UnsupportedP3RecordStreamComponent, field.drop_import orelse return error.UnsupportedP3RecordStreamComponent);
        } else {
            try append_nested_resource_drop_imports(allocator, &out, &seen, module, field.nested_fields);
        }
    }
    return out.toOwnedSlice(allocator);
}

const ResourceDropKey = struct {
    resource: []const u8,
    drop_import: []const u8,
};

fn append_resource_drop_import(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    seen: *std.ArrayList(ResourceDropKey),
    module: []const u8,
    resource: []const u8,
    drop_import: []const u8,
) !void {
    for (seen.items) |previous| {
        if (std.mem.eql(u8, previous.resource, resource) and std.mem.eql(u8, previous.drop_import, drop_import)) return;
    }
    try seen.append(allocator, .{ .resource = resource, .drop_import = drop_import });
    const resource_name = try sanitized_name(allocator, resource);
    defer allocator.free(resource_name);
    try append_fmt(allocator, out, "    (import \"{s}\" \"{s}\" (func $resource-drop-{s} (type $resource-drop)))\n", .{ module, drop_import, resource_name });
}

fn append_nested_resource_drop_imports(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    seen: *std.ArrayList(ResourceDropKey),
    module: []const u8,
    fields: []const p3_async_manifest.RecordNestedField,
) !void {
    for (fields) |field| {
        if (field.nested_fields.len != 0) {
            if (field.nested_fields.len != 1) return error.UnsupportedP3RecordStreamComponent;
            try append_nested_resource_drop_imports(allocator, out, seen, module, field.nested_fields);
        } else if (field.ownership == .own) {
            try append_resource_drop_import(allocator, out, seen, module, field.resource orelse return error.UnsupportedP3RecordStreamComponent, field.drop_import orelse return error.UnsupportedP3RecordStreamComponent);
        } else {
            return error.UnsupportedP3RecordStreamComponent;
        }
    }
}

fn build_record_resource_release_body(allocator: std.mem.Allocator, layout: p3_async_manifest.RecordLayout, owned_area_offset: u32, record_active_offset: u32) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    if (!has_owned_resource_field(layout)) return out.toOwnedSlice(allocator);

    try append_fmt(allocator, &out, "    local.get $frame\n    i32.const {d}\n    i32.add\n    i32.load\n    i32.eqz\n    if\n    else\n", .{record_active_offset});
    var owned_cursor: u32 = 0;
    for (layout.source_fields) |field| {
        if (field.nested_fields.len != 0) {
            for (field.nested_fields) |nested| {
                try append_nested_resource_release(allocator, &out, nested, owned_area_offset, &owned_cursor);
            }
            continue;
        }
        if (field.ownership == .own) {
            try append_resource_release(allocator, &out, field.resource orelse return error.UnsupportedP3RecordStreamComponent, owned_area_offset + owned_cursor);
            owned_cursor += try owned_field_size(layout, field);
        } else if (std.mem.eql(u8, field.source_type, "string")) {
            owned_cursor += try owned_field_size(layout, field);
        } else {
            owned_cursor += try owned_field_size(layout, field);
        }
    }
    try append_fmt(allocator, &out, "      local.get $frame\n      i32.const {d}\n      i32.add\n      i32.const 0\n      i32.store\n    end\n", .{record_active_offset});
    return out.toOwnedSlice(allocator);
}

fn append_nested_resource_release(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    field: p3_async_manifest.RecordNestedField,
    owned_area_offset: u32,
    owned_cursor: *u32,
) !void {
    if (field.nested_fields.len != 0) {
        if (field.nested_fields.len != 1) return error.UnsupportedP3RecordStreamComponent;
        return append_nested_resource_release(allocator, out, field.nested_fields[0], owned_area_offset, owned_cursor);
    }
    if (field.ownership != .own or field.storage.len != 1 or field.resource == null) return error.UnsupportedP3RecordStreamComponent;
    try append_resource_release(allocator, out, field.resource.?, owned_area_offset + owned_cursor.*);
    owned_cursor.* += 4;
}

fn append_resource_release(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    resource: []const u8,
    offset: u32,
) !void {
    const resource_name = try sanitized_name(allocator, resource);
    defer allocator.free(resource_name);
    try append_fmt(allocator, out, "      ;; [record-resource-release-{s}]\n      local.get $frame\n      i32.const {d}\n      i32.add\n      i32.load\n      i32.eqz\n      if\n      else\n        local.get $frame\n        i32.const {d}\n        i32.add\n        i32.load\n        local.tee $record-handle\n        call $resource-drop-{s}\n        local.get $frame\n        i32.const {d}\n        i32.add\n        i32.const 0\n        i32.store\n      end\n", .{ resource_name, offset, offset, resource_name, offset });
}

fn storage_offset(layout: p3_async_manifest.RecordLayout, name: []const u8) ?u32 {
    return layout.field_offset(name);
}

fn field_core_type(layout: p3_async_manifest.RecordLayout, name: []const u8) ?[]const u8 {
    for (layout.fields) |field| if (std.mem.eql(u8, field.name, name)) return field.core_type;
    return null;
}

fn core_load(core_type: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, core_type, "i64")) return "i64.load";
    if (std.mem.eql(u8, core_type, "f64")) return "f64.load";
    if (std.mem.eql(u8, core_type, "f32")) return "f32.load";
    if (std.mem.eql(u8, core_type, "i32")) return "i32.load";
    return null;
}

fn core_store(core_type: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, core_type, "i64")) return "i64.store";
    if (std.mem.eql(u8, core_type, "f64")) return "f64.store";
    if (std.mem.eql(u8, core_type, "f32")) return "f32.store";
    if (std.mem.eql(u8, core_type, "i32")) return "i32.store";
    return null;
}

fn wit_source_type(source_type: []const u8) []const u8 {
    if (std.mem.eql(u8, source_type, "string")) return "string";
    if (std.mem.eql(u8, source_type, "bool")) return "bool";
    if (std.mem.eql(u8, source_type, "u8")) return "u8";
    if (std.mem.eql(u8, source_type, "u16")) return "u16";
    if (std.mem.eql(u8, source_type, "u32")) return "u32";
    if (std.mem.eql(u8, source_type, "u64")) return "u64";
    if (std.mem.eql(u8, source_type, "i8")) return "s8";
    if (std.mem.eql(u8, source_type, "i16")) return "s16";
    if (std.mem.eql(u8, source_type, "i32")) return "s32";
    if (std.mem.eql(u8, source_type, "i64")) return "s64";
    if (std.mem.eql(u8, source_type, "f32")) return "float32";
    if (std.mem.eql(u8, source_type, "f64")) return "float64";
    return source_type;
}

fn sanitized_name(allocator: std.mem.Allocator, source_name: []const u8) ![]u8 {
    const result = try allocator.dupe(u8, source_name);
    for (result) |*char| {
        if (char.* == '_') char.* = '-';
    }
    return result;
}

fn wit_name(allocator: std.mem.Allocator, source_name: []const u8) ![]u8 {
    return sanitized_name(allocator, source_name);
}

fn wit_name_borrowed(source_name: []const u8) []const u8 {
    return source_name;
}

fn component_export_locator(allocator: std.mem.Allocator, package: []const u8, interface_name: []const u8) ![]u8 {
    const version_start = std.mem.indexOfScalar(u8, package, '@') orelse return error.UnsupportedP3RecordStreamComponent;
    return std.fmt.allocPrint(allocator, "{s}/{s}@{s}", .{ package[0..version_start], interface_name, package[version_start + 1 ..] });
}

fn replace_and_free(allocator: std.mem.Allocator, input: []u8, needle: []const u8, replacement: []const u8) ![]u8 {
    const replaced = try replace_all(allocator, input, needle, replacement);
    allocator.free(input);
    return replaced;
}

fn replace_all(allocator: std.mem.Allocator, input: []const u8, needle: []const u8, replacement: []const u8) ![]u8 {
    if (needle.len == 0) return allocator.dupe(u8, input);
    var count: usize = 0;
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, input, cursor, needle)) |index| {
        count += 1;
        cursor = index + needle.len;
    }
    if (count == 0) return allocator.dupe(u8, input);
    const removed = count * needle.len;
    const added = count * replacement.len;
    const size = if (added >= removed) input.len + added - removed else input.len - (removed - added);
    var output = try allocator.alloc(u8, size);
    var input_cursor: usize = 0;
    var output_cursor: usize = 0;
    while (std.mem.indexOfPos(u8, input, input_cursor, needle)) |index| {
        const prefix = input[input_cursor..index];
        @memcpy(output[output_cursor .. output_cursor + prefix.len], prefix);
        output_cursor += prefix.len;
        @memcpy(output[output_cursor .. output_cursor + replacement.len], replacement);
        output_cursor += replacement.len;
        input_cursor = index + needle.len;
    }
    const suffix = input[input_cursor..];
    @memcpy(output[output_cursor .. output_cursor + suffix.len], suffix);
    return output;
}

const generic_record_stream_core_wat =
    \\(module
    \\  [method-type]
    \\  [stream-read-type]
    \\  [future-read-type]
    \\  (type $resource-drop (func (param i32)))
    \\  (type $waitable-new (func (result i32)))
    \\  (type $waitable-join (func (param i32 i32)))
    \\  (type $waitable-drop (func (param i32)))
    \\  (type $context-get (func (result i32)))
    \\  (type $context-set (func (param i32)))
    \\  (type $async-run (func (result i32)))
    \\  (type $async-callback (func (param i32 i32 i32) (result i32)))
    \\  (type $task-return (func (param i32 i32)))
    \\  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
    \\  (type $initialize (func))
    \\  ;; [record-stream-plan] descriptor-driven source acquisition
    \\  (import "[source-module]" "[source-acquire-name]" (func $record-stream-acquire (type $record-stream-acquire)))
    \\  (import "[source-module]" "[stream-read-name]" (func $stream-read (type $stream-read)))
    \\  (import "[source-module]" "[stream-drop-name]" (func $stream-drop-readable (type $resource-drop)))
    \\  (import "[source-module]" "[future-read-name]" (func $future-read (type $future-read)))
    \\  (import "[source-module]" "[future-drop-name]" (func $future-drop-readable (type $resource-drop)))
    \\  [resource-drop-imports]
    \\  (import "$root" "[waitable-set-new]" (func $waitable-set-new (type $waitable-new)))
    \\  (import "$root" "[waitable-join]" (func $waitable-join (type $waitable-join)))
    \\  (import "$root" "[waitable-set-drop]" (func $waitable-set-drop (type $waitable-drop)))
    \\  (import "$root" "[context-get-0]" (func $context-get-0 (type $context-get)))
    \\  (import "$root" "[context-set-0]" (func $context-set-0 (type $context-set)))
    \\  (import "[task-return-module]" "[task-return-name]" (func $task-return (type $task-return)))
    \\  (memory (export "memory") 2)
    \\  ;; [record-loop-state] frame+12: 0=reading, 1=completion, 2=terminal
    \\  ;; [record-read-index] frame+12
    \\  ;; [record-field-markers]
    \\  (global $frame-next (mut i32) (i32.const 1024))
    \\  (global $heap-next (mut i32) (i32.const 65536))
    \\  (func $frame-alloc (result i32)
    \\    global.get $frame-next
    \\    global.get $frame-next
    \\    i32.const [frame-size]
    \\    i32.add
    \\    global.set $frame-next
    \\  )
    \\  (func $frame-free (param $frame i32))
    \\  (func $wait-on-stream (param $frame i32) (result i32)
    \\    local.get $frame
    \\    i32.const 4
    \\    i32.add
    \\    i32.load
    \\    local.get $frame
    \\    i32.load
    \\    call $waitable-join
    \\    local.get $frame
    \\    i32.load
    \\    i32.const 4
    \\    i32.shl
    \\    i32.const 2
    \\    i32.or
    \\  )
    \\  (func $wait-on-completion (param $frame i32) (result i32)
    \\    local.get $frame
    \\    i32.const 8
    \\    i32.add
    \\    i32.load
    \\    local.get $frame
    \\    i32.load
    \\    call $waitable-join
    \\    local.get $frame
    \\    i32.load
    \\    i32.const 4
    \\    i32.shl
    \\    i32.const 2
    \\    i32.or
    \\  )
    \\  (func $cleanup (param $frame i32) (result i32) (local $handle i32)
    \\    local.get $frame
    \\    i32.const 8
    \\    i32.add
    \\    i32.load
    \\    local.tee $handle
    \\    i32.eqz
    \\    if
    \\    else
    \\      local.get $handle
    \\      call $future-drop-readable
    \\      local.get $frame
    \\      i32.const 8
    \\      i32.add
    \\      i32.const 0
    \\      i32.store
    \\    end
    \\    local.get $frame
    \\    i32.const 4
    \\    i32.add
    \\    i32.load
    \\    local.tee $handle
    \\    i32.eqz
    \\    if
    \\    else
    \\      local.get $handle
    \\      call $stream-drop-readable
    \\      local.get $frame
    \\      i32.const 4
    \\      i32.add
    \\      i32.const 0
    \\      i32.store
    \\    end
    \\    local.get $frame
    \\    call $release-record
    \\    local.get $frame
    \\    i32.load
    \\    call $waitable-set-drop
    \\    local.get $frame
    \\    i32.const 12
    \\    i32.add
    \\    i32.const 2
    \\    i32.store
    \\    i32.const 0
    \\    call $context-set-0
    \\    local.get $frame
    \\    i32.const [completion-area-offset]
    \\    i32.add
    \\    i32.load
    \\    local.get $frame
    \\    i32.const [completion-area-offset]
    \\    i32.add
    \\    i32.const 4
    \\    i32.add
    \\    i32.load
    \\    call $task-return
    \\    local.get $frame
    \\    call $frame-free
    \\    i32.const 0
    \\  )
    \\  (func $copy-text (param $ptr i32) (param $len i32) (result i32) (local $dst i32)
    \\    global.get $heap-next
    \\    local.set $dst
    \\    local.get $dst
    \\    local.get $len
    \\    i32.add
    \\    global.set $heap-next
    \\    local.get $dst
    \\    local.get $ptr
    \\    local.get $len
    \\    memory.copy
    \\    local.get $dst
    \\  )
    \\  (func $release-record (param $frame i32) (local $record-handle i32)
    \\    [record-resource-release-body]
    \\  )
    \\  (func $consume-record (param $frame i32)
    \\    ;; [record-decode] copies all validated source fields into frame-owned storage
    \\    [record-decode-body]
    \\  )
    \\  (func $accept-completion (param $frame i32) (param $code i32) (result i32)
    \\    local.get $frame
    \\    call $cleanup
    \\  )
    \\  (func $start-completion (param $frame i32) (result i32) (local $code i32)
    \\    local.get $frame
    \\    i32.const 12
    \\    i32.add
    \\    i32.const 1
    \\    i32.store
    \\    local.get $frame
    \\    i32.const 8
    \\    i32.add
    \\    i32.load
    \\    local.get $frame
    \\    i32.const [completion-area-offset]
    \\    i32.add
    \\    call $future-read
    \\    local.tee $code
    \\    i32.const -1
    \\    i32.eq
    \\    if (result i32)
    \\      local.get $frame
    \\      call $wait-on-completion
    \\    else
    \\      local.get $frame
    \\      local.get $code
    \\      call $accept-completion
    \\    end
    \\  )
    \\  (func $accept-stream (param $frame i32) (param $code i32) (result i32)
    \\    local.get $code
    \\    i32.const 1
    \\    i32.eq
    \\    if (result i32)
    \\      local.get $frame
    \\      call $start-completion
    \\    else
    \\      local.get $code
    \\      i32.const 17
    \\      i32.eq
    \\      if (result i32)
    \\        local.get $frame
    \\        call $start-completion
    \\      else
    \\        local.get $code
    \\        i32.const 16
    \\        i32.eq
    \\        if (result i32)
    \\          local.get $frame
    \\          call $consume-record
    \\          local.get $frame
    \\          call $release-record
    \\          local.get $frame
    \\          i32.const 12
    \\          i32.add
    \\          local.get $frame
    \\          i32.const 12
    \\          i32.add
    \\          i32.load
    \\          i32.const 1
    \\          i32.add
    \\          i32.store
    \\          local.get $frame
    \\          call $start-stream
    \\        else
    \\          local.get $frame
    \\          i32.const [completion-area-offset]
    \\          i32.add
    \\          i32.const 1
    \\          i32.store
    \\          local.get $frame
    \\          i32.const [completion-area-offset]
    \\          i32.add
    \\          i32.const 4
    \\          i32.add
    \\          local.get $code
    \\          i32.store
    \\          local.get $frame
    \\          call $cleanup
    \\        end
    \\      end
    \\    end
    \\  )
    \\  (func $start-stream (param $frame i32) (result i32) (local $code i32)
    \\    local.get $frame
    \\    i32.const 4
    \\    i32.add
    \\    i32.load
    \\    local.get $frame
    \\    i32.const [record-area-offset]
    \\    i32.add
    \\    i32.const 1
    \\    call $stream-read
    \\    local.tee $code
    \\    i32.const -1
    \\    i32.eq
    \\    if (result i32)
    \\      local.get $frame
    \\      call $wait-on-stream
    \\    else
    \\      local.get $frame
    \\      local.get $code
    \\      call $accept-stream
    \\    end
    \\  )
    \\  (func $accept-acquisition (param $frame i32) (param $payload i32) (result i32)
    \\    local.get $frame
    \\    i32.const 4
    \\    i32.add
    \\    local.get $payload
    \\    i32.load
    \\    i32.store
    \\    local.get $frame
    \\    i32.const 8
    \\    i32.add
    \\    local.get $payload
    \\    i32.const 4
    \\    i32.add
    \\    i32.load
    \\    i32.store
    \\    local.get $frame
    \\    call $start-stream
    \\  )
    \\  (func (export "[async-lift-name]") (type $async-run) (result i32) (local $frame i32)
    \\    call $frame-alloc
    \\    local.tee $frame
    \\    call $context-set-0
    \\    local.get $frame
    \\    call $waitable-set-new
    \\    i32.store
    \\    local.get $frame
    \\    i32.const 4
    \\    i32.add
    \\    call $record-stream-acquire
    \\    local.get $frame
    \\    i32.const 12
    \\    i32.add
    \\    i32.const 0
    \\    i32.store
    \\    local.get $frame
    \\    i32.const [completion-area-offset]
    \\    i32.add
    \\    i32.const 0
    \\    i32.store
    \\    local.get $frame
    \\    i32.const [completion-area-offset]
    \\    i32.add
    \\    i32.const 4
    \\    i32.add
    \\    i32.const 0
    \\    i32.store
    \\    local.get $frame
    \\    call $start-stream
    \\  )
    \\  (func (export "[callback-name]") (type $async-callback) (param $event i32) (param $index i32) (param $payload i32) (result i32) (local $frame i32)
    \\    call $context-get-0
    \\    local.set $frame
    \\    local.get $event
    \\    i32.const 1
    \\    i32.eq
    \\    if (result i32)
    \\      local.get $frame
    \\      local.get $payload
    \\      call $accept-acquisition
    \\    else
    \\      local.get $event
    \\      i32.const 2
    \\      i32.eq
    \\      if (result i32)
    \\        local.get $frame
    \\        local.get $payload
    \\        call $accept-stream
    \\      else
    \\        local.get $event
    \\        i32.const 4
    \\        i32.eq
    \\        if (result i32)
    \\          local.get $frame
    \\          local.get $payload
    \\          call $accept-completion
    \\        else
    \\          unreachable
    \\        end
    \\      end
    \\    end
    \\  )
    \\  (func (export "cabi_realloc") (type $cabi-realloc) (param $old i32) (param $old-size i32) (param $align i32) (param $size i32) (result i32)
    \\    (local $ptr i32)
    \\    local.get $old
    \\    i32.eqz
    \\    if (result i32)
    \\      global.get $heap-next
    \\      local.set $ptr
    \\      local.get $ptr
    \\      local.get $size
    \\      i32.add
    \\      global.set $heap-next
    \\      local.get $ptr
    \\    else
    \\      local.get $old
    \\    end
    \\  )
    \\  (func (export "_initialize") (type $initialize))
    \\)
;

pub const max_effects: usize = 8;

pub const Phase = enum {
    idle,
    read_pending,
    item_ready,
    completion_pending,
    terminal,
    closed,
};

pub const Event = enum {
    start,
    read_pending,
    read_ok,
    read_eof,
    read_error,
    completion_pending,
    completion_ok,
    completion_error,
    cancel,
};

pub const Effect = enum {
    issue_read,
    wait_read,
    decode_record,
    await_completion,
    cancel_read,
    cancel_completion,
    drop_stream,
    drop_completion,
    release_record,
    release_frame,
    return_ok,
    return_err,
};

pub const Transition = struct {
    phase: Phase,
    effects: [max_effects]Effect = undefined,
    effect_count: u8 = 0,
};

const cleanup_stream: u8 = 1 << 0;
const cleanup_completion: u8 = 1 << 1;
const cleanup_record: u8 = 1 << 2;
const cleanup_frame: u8 = 1 << 3;
const cleanup_all = cleanup_stream | cleanup_completion | cleanup_record | cleanup_frame;

pub const Consumer = struct {
    phase: Phase = .idle,
    read_active: bool = false,
    completion_active: bool = false,
    cleanup_mask: u8 = 0,

    pub fn init() Consumer {
        return .{};
    }

    pub fn dispatch(self: *Consumer, event: Event) Transition {
        const before = self.phase;
        var transition = Transition{ .phase = before };

        switch (event) {
            .start => {
                if (self.phase != .idle) return transition;
                self.phase = .read_pending;
                self.read_active = true;
                append(&transition, .issue_read);
            },
            .read_pending => {
                if (self.phase != .read_pending or !self.read_active) return transition;
                append(&transition, .wait_read);
            },
            .read_ok => {
                if (self.phase != .read_pending or !self.read_active) return transition;
                self.read_active = false;
                self.phase = .item_ready;
                append(&transition, .decode_record);
                self.phase = .read_pending;
                self.read_active = true;
                append(&transition, .issue_read);
            },
            .read_eof => {
                if (self.phase != .read_pending or !self.read_active) return transition;
                self.read_active = false;
                self.phase = .completion_pending;
                self.completion_active = true;
                append(&transition, .await_completion);
            },
            .read_error => {
                if (self.phase != .read_pending or !self.read_active) return transition;
                self.read_active = false;
                terminal(self, &transition, false, true);
            },
            .completion_pending => {
                if (self.phase != .completion_pending or !self.completion_active) return transition;
                append(&transition, .await_completion);
            },
            .completion_ok => {
                if (self.phase != .completion_pending or !self.completion_active) return transition;
                self.completion_active = false;
                terminal(self, &transition, false, false);
            },
            .completion_error => {
                if (self.phase != .completion_pending or !self.completion_active) return transition;
                self.completion_active = false;
                terminal(self, &transition, false, true);
            },
            .cancel => {
                if (self.phase == .read_pending and self.read_active) {
                    self.read_active = false;
                    terminal(self, &transition, true, true);
                } else if (self.phase == .completion_pending and self.completion_active) {
                    terminal(self, &transition, false, true);
                    self.completion_active = false;
                }
            },
        }

        transition.phase = self.phase;
        return transition;
    }
};

pub const RecordStreamSourcePlan = struct {
    descriptor: p3_async_manifest.Descriptor,
    export_name: []const u8,
    record_type: []const u8,
    reader_name: []const u8,
    completion_name: []const u8,
    loop_read_count: usize,
    has_completion_await: bool,

    pub fn analyze(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) !RecordStreamSourcePlan {
        const host = find_record_stream_host(tokens, registry) orelse return error.UnsupportedP3RecordStreamComponent;
        const function = find_async_function(tokens) orelse return error.UnsupportedP3RecordStreamComponent;
        const loop_open = find_loop_open(tokens, function.body_start, function.body_end) orelse return error.UnsupportedP3RecordStreamComponent;
        const loop_end = sema_tokens.find_matching(tokens, loop_open, "{", "}") catch return error.UnsupportedP3RecordStreamComponent;
        if (loop_end >= function.body_end) return error.UnsupportedP3RecordStreamComponent;

        const reader = find_stream_binding(tokens, function.body_start, loop_open, host.record_type) orelse
            return error.UnsupportedP3RecordStreamComponent;
        const completion = find_completion_binding(tokens, function.body_start, loop_open) orelse
            return error.UnsupportedP3RecordStreamComponent;
        if (count_next_calls(tokens, loop_open + 1, loop_end) != 1 or
            !has_next_binding(tokens, loop_open + 1, loop_end, reader.name, host.record_type) or
            !has_await_call(tokens, loop_open + 1, loop_end) or
            !has_ok_guard(tokens, loop_open + 1, loop_end) or
            !has_else_break(tokens, loop_open + 1, loop_end)) return error.UnsupportedP3RecordStreamComponent;

        if (!has_await_call_for(tokens, loop_end + 1, function.body_end, completion.name) or
            !has_is_target(tokens, loop_end + 1, function.body_end, "completed", "Err") or
            !has_return_ok(tokens, loop_end + 1, function.body_end)) return error.UnsupportedP3RecordStreamComponent;

        return .{
            .descriptor = host.descriptor,
            .export_name = function.name,
            .record_type = host.record_type,
            .reader_name = reader.name,
            .completion_name = completion.name,
            .loop_read_count = 1,
            .has_completion_await = true,
        };
    }

    pub fn deinit(self: *RecordStreamSourcePlan, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.* = undefined;
    }
};

const HostBinding = struct {
    name: []const u8,
    descriptor: p3_async_manifest.Descriptor,
    record_type: []const u8,
};

const AsyncFunction = struct {
    name: []const u8,
    body_start: usize,
    body_end: usize,
};

const Binding = struct {
    name: []const u8,
};

fn find_record_stream_host(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) ?HostBinding {
    var idx: usize = 0;
    while (idx + 12 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !sema_tokens.tok_eq(tokens[idx + 1], "=") or
            !sema_tokens.tok_eq(tokens[idx + 2], "@") or
            !sema_tokens.tok_eq(tokens[idx + 3], "host_func") or
            !sema_tokens.tok_eq(tokens[idx + 4], "(") or tokens[idx + 5].kind != .string or
            !sema_tokens.tok_eq(tokens[idx + 6], ",") or tokens[idx + 7].kind != .string) continue;
        const locator = sema_tokens.string_token_body(tokens[idx + 5].lexeme) orelse continue;
        const member = sema_tokens.string_token_body(tokens[idx + 7].lexeme) orelse continue;
        const descriptor = registry.find(locator, member) orelse continue;
        const shape = switch (p3_async_manifest.lowering_shape(descriptor) orelse continue) {
            .record_stream_reader => |value| value,
            else => continue,
        };
        if (shape.element.len == 0) continue;
        const record_type_start = idx + 17;
        if (record_type_start >= tokens.len or tokens[record_type_start].kind != .ident) continue;
        if (!source_type_matches_element(tokens[record_type_start].lexeme, shape.element)) continue;
        return .{ .name = tokens[idx].lexeme, .descriptor = descriptor, .record_type = tokens[record_type_start].lexeme };
    }
    return null;
}

fn find_async_function(tokens: []const lexer.Token) ?AsyncFunction {
    var idx: usize = 0;
    while (idx + 3 < tokens.len) : (idx += 1) {
        const name_idx: usize = if (sema_tokens.tok_eq(tokens[idx], "async")) blk: {
            if (tokens[idx + 1].kind != .ident or !sema_tokens.tok_eq(tokens[idx + 2], "(")) continue;
            break :blk idx + 1;
        } else blk: {
            if (tokens[idx].kind != .ident or !sema_tokens.tok_eq(tokens[idx + 1], "(")) continue;
            break :blk idx;
        };
        const params_idx = name_idx + 1;
        const params_end = sema_tokens.find_matching(tokens, params_idx, "(", ")") catch return null;
        if (params_end + 2 >= tokens.len or !sema_tokens.tok_eq(tokens[params_end + 1], "-") or
            !sema_tokens.tok_eq(tokens[params_end + 2], ">")) continue;
        var body_open = params_end + 1;
        while (body_open < tokens.len and !sema_tokens.tok_eq(tokens[body_open], "{")) : (body_open += 1) {}
        if (body_open >= tokens.len) return null;
        const body_end = sema_tokens.find_matching(tokens, body_open, "{", "}") catch return null;
        return .{ .name = tokens[name_idx].lexeme, .body_start = body_open + 1, .body_end = body_end };
    }
    return null;
}

fn find_loop_open(tokens: []const lexer.Token, start: usize, end: usize) ?usize {
    var idx = start;
    while (idx < end) : (idx += 1) {
        if (sema_tokens.tok_eq(tokens[idx], "loop") and idx + 1 < end and sema_tokens.tok_eq(tokens[idx + 1], "{")) return idx + 1;
    }
    return null;
}

fn find_stream_binding(tokens: []const lexer.Token, start: usize, end: usize, record_type: []const u8) ?Binding {
    var idx = start;
    while (idx + 9 < end) : (idx += 1) {
        if (tokens[idx].kind != .ident or !sema_tokens.tok_eq(tokens[idx + 1], "Stream") or
            !sema_tokens.tok_eq(tokens[idx + 2], "<") or tokens[idx + 3].kind != .ident or
            !std.mem.eql(u8, tokens[idx + 3].lexeme, record_type) or !sema_tokens.tok_eq(tokens[idx + 4], ">") or
            !sema_tokens.tok_eq(tokens[idx + 5], "=") or !sema_tokens.tok_eq(tokens[idx + 6], "@") or
            !sema_tokens.tok_eq(tokens[idx + 7], "get") or !sema_tokens.tok_eq(tokens[idx + 8], "(") or
            !sema_tokens.tok_eq(tokens[idx + 10], ",") or !sema_tokens.tok_eq(tokens[idx + 11], "0")) continue;
        return .{ .name = tokens[idx].lexeme };
    }
    return null;
}

fn find_completion_binding(tokens: []const lexer.Token, start: usize, end: usize) ?Binding {
    var idx = start;
    while (idx + 12 < end) : (idx += 1) {
        if (tokens[idx].kind != .ident or !sema_tokens.tok_eq(tokens[idx + 1], "Future") or
            !sema_tokens.tok_eq(tokens[idx + 2], "<") or !sema_tokens.tok_eq(tokens[idx + 3], "Result") or
            !sema_tokens.tok_eq(tokens[idx + 4], "<") or !sema_tokens.tok_eq(tokens[idx + 5], "nil") or
            !sema_tokens.tok_eq(tokens[idx + 6], ",") or tokens[idx + 7].kind != .ident or
            !sema_tokens.tok_eq(tokens[idx + 8], ">") or !sema_tokens.tok_eq(tokens[idx + 9], ">") or
            !sema_tokens.tok_eq(tokens[idx + 10], "=") or !sema_tokens.tok_eq(tokens[idx + 11], "@") or
            !sema_tokens.tok_eq(tokens[idx + 12], "get")) continue;
        if (idx + 16 >= end or !sema_tokens.tok_eq(tokens[idx + 13], "(") or
            !sema_tokens.tok_eq(tokens[idx + 15], ",") or !sema_tokens.tok_eq(tokens[idx + 16], "1")) continue;
        return .{ .name = tokens[idx].lexeme };
    }
    return null;
}

fn count_next_calls(tokens: []const lexer.Token, start: usize, end: usize) usize {
    var count: usize = 0;
    var idx = start;
    while (idx + 1 < end) : (idx += 1) {
        if (sema_tokens.tok_eq(tokens[idx], "@") and sema_tokens.tok_eq(tokens[idx + 1], "next")) count += 1;
    }
    return count;
}

fn has_next_binding(tokens: []const lexer.Token, start: usize, end: usize, reader_name: []const u8, record_type: []const u8) bool {
    var idx = start;
    while (idx + 9 < end) : (idx += 1) {
        if (tokens[idx].kind == .ident and sema_tokens.tok_eq(tokens[idx + 1], "Future") and
            sema_tokens.tok_eq(tokens[idx + 2], "<") and sema_tokens.tok_eq(tokens[idx + 3], "Result") and
            sema_tokens.tok_eq(tokens[idx + 4], "<") and tokens[idx + 5].kind == .ident and
            std.mem.eql(u8, tokens[idx + 5].lexeme, record_type) and
            sema_tokens.tok_eq(tokens[idx + 6], ",") and sema_tokens.tok_eq(tokens[idx + 7], "nil") and
            sema_tokens.tok_eq(tokens[idx + 8], ">") and sema_tokens.tok_eq(tokens[idx + 9], ">") and
            idx + 13 < end and sema_tokens.tok_eq(tokens[idx + 10], "=") and sema_tokens.tok_eq(tokens[idx + 11], "@") and
            sema_tokens.tok_eq(tokens[idx + 12], "next") and sema_tokens.tok_eq(tokens[idx + 13], "(") and
            idx + 15 < end and tokens[idx + 14].kind == .ident and std.mem.eql(u8, tokens[idx + 14].lexeme, reader_name) and
            sema_tokens.tok_eq(tokens[idx + 15], ")")) return true;
    }
    return false;
}

fn has_await_call(tokens: []const lexer.Token, start: usize, end: usize) bool {
    var idx = start;
    while (idx + 1 < end) : (idx += 1) {
        if (sema_tokens.tok_eq(tokens[idx], "await") and sema_tokens.tok_eq(tokens[idx + 1], "(")) return true;
        if (idx + 2 < end and sema_tokens.tok_eq(tokens[idx], "@") and
            sema_tokens.tok_eq(tokens[idx + 1], "await") and sema_tokens.tok_eq(tokens[idx + 2], "(")) return true;
    }
    return false;
}

fn has_ok_guard(tokens: []const lexer.Token, start: usize, end: usize) bool {
    return has_is_target(tokens, start, end, "item", "Ok");
}

fn has_is_target(tokens: []const lexer.Token, start: usize, end: usize, value: []const u8, target: []const u8) bool {
    var idx = start;
    while (idx + 5 < end) : (idx += 1) {
        if (sema_tokens.tok_eq(tokens[idx], "@") and sema_tokens.tok_eq(tokens[idx + 1], "is") and
            sema_tokens.tok_eq(tokens[idx + 2], "(") and tokens[idx + 3].kind == .ident and
            std.mem.eql(u8, tokens[idx + 3].lexeme, value) and sema_tokens.tok_eq(tokens[idx + 4], ",") and
            tokens[idx + 5].kind == .ident and std.mem.eql(u8, tokens[idx + 5].lexeme, target)) return true;
    }
    return false;
}

fn has_else_break(tokens: []const lexer.Token, start: usize, end: usize) bool {
    var idx = start;
    while (idx + 2 < end) : (idx += 1) {
        if (sema_tokens.tok_eq(tokens[idx], "else") and sema_tokens.tok_eq(tokens[idx + 1], "{") and
            sema_tokens.tok_eq(tokens[idx + 2], "break")) return true;
    }
    return false;
}

fn has_await_call_for(tokens: []const lexer.Token, start: usize, end: usize, name: []const u8) bool {
    var idx = start;
    while (idx + 3 < end) : (idx += 1) {
        if (sema_tokens.tok_eq(tokens[idx], "await") and sema_tokens.tok_eq(tokens[idx + 1], "(") and
            tokens[idx + 2].kind == .ident and std.mem.eql(u8, tokens[idx + 2].lexeme, name) and
            sema_tokens.tok_eq(tokens[idx + 3], ")")) return true;
        if (idx + 4 < end and sema_tokens.tok_eq(tokens[idx], "@") and sema_tokens.tok_eq(tokens[idx + 1], "await") and
            sema_tokens.tok_eq(tokens[idx + 2], "(") and tokens[idx + 3].kind == .ident and
            std.mem.eql(u8, tokens[idx + 3].lexeme, name) and sema_tokens.tok_eq(tokens[idx + 4], ")")) return true;
    }
    return false;
}

fn has_return_ok(tokens: []const lexer.Token, start: usize, end: usize) bool {
    var idx = start;
    while (idx + 2 < end) : (idx += 1) {
        if (sema_tokens.tok_eq(tokens[idx], "return") and sema_tokens.tok_eq(tokens[idx + 1], "Ok") and
            sema_tokens.tok_eq(tokens[idx + 2], "(")) return true;
    }
    return false;
}

fn source_type_matches_element(source_type: []const u8, element: []const u8) bool {
    var source_index: usize = 0;
    var element_index: usize = 0;
    for (source_type) |char| {
        if (char >= 'A' and char <= 'Z' and source_index != 0) {
            if (element_index >= element.len or element[element_index] != '-') return false;
            element_index += 1;
        }
        if (element_index >= element.len) return false;
        const expected = if (char >= 'A' and char <= 'Z') char + ('a' - 'A') else char;
        if (element[element_index] != expected) return false;
        source_index += 1;
        element_index += 1;
    }
    return element_index == element.len;
}

fn append(transition: *Transition, effect: Effect) void {
    if (transition.effect_count >= max_effects) return;
    transition.effects[transition.effect_count] = effect;
    transition.effect_count += 1;
}

fn terminal(self: *Consumer, transition: *Transition, cancel_read: bool, is_error: bool) void {
    if (self.phase == .closed) return;
    self.phase = .terminal;
    if (cancel_read) append(transition, .cancel_read);
    if (self.completion_active) append(transition, .cancel_completion);
    if (self.cleanup_mask & cleanup_stream == 0) {
        self.cleanup_mask |= cleanup_stream;
        append(transition, .drop_stream);
    }
    if (self.cleanup_mask & cleanup_completion == 0) {
        self.cleanup_mask |= cleanup_completion;
        append(transition, .drop_completion);
    }
    if (self.cleanup_mask & cleanup_record == 0) {
        self.cleanup_mask |= cleanup_record;
        append(transition, .release_record);
    }
    if (self.cleanup_mask & cleanup_frame == 0) {
        self.cleanup_mask |= cleanup_frame;
        append(transition, .release_frame);
    }
    self.cleanup_mask |= cleanup_all;
    append(transition, if (is_error) .return_err else .return_ok);
    self.phase = .closed;
}

fn expect_effects(transition: Transition, expected: []const Effect) !void {
    try std.testing.expectEqual(expected.len, @as(usize, transition.effect_count));
    for (expected, 0..) |effect, index| {
        try std.testing.expectEqual(effect, transition.effects[index]);
    }
}

test "record stream consumer transitions from read to eof completion" {
    var consumer = Consumer.init();
    try expect_effects(consumer.dispatch(.start), &.{.issue_read});
    try expect_effects(consumer.dispatch(.read_pending), &.{.wait_read});
    try expect_effects(consumer.dispatch(.read_ok), &.{ .decode_record, .issue_read });
    try expect_effects(consumer.dispatch(.read_eof), &.{.await_completion});
    try expect_effects(consumer.dispatch(.completion_ok), &.{
        .drop_stream,
        .drop_completion,
        .release_record,
        .release_frame,
        .return_ok,
    });
    try std.testing.expectEqual(Phase.closed, consumer.phase);
}

test "record stream consumer rejects a second in-flight read" {
    var consumer = Consumer.init();
    _ = consumer.dispatch(.start);
    _ = consumer.dispatch(.read_pending);
    const transition = consumer.dispatch(.start);
    try std.testing.expectEqual(@as(u8, 0), transition.effect_count);
    try std.testing.expectEqual(Phase.read_pending, transition.phase);
}

test "record stream consumer cancellation cancels active read before cleanup" {
    var consumer = Consumer.init();
    _ = consumer.dispatch(.start);
    _ = consumer.dispatch(.read_pending);
    const transition = consumer.dispatch(.cancel);
    try expect_effects(transition, &.{
        .cancel_read,
        .drop_stream,
        .drop_completion,
        .release_record,
        .release_frame,
        .return_err,
    });
    try std.testing.expectEqual(Phase.closed, consumer.phase);
}

test "record stream consumer emits terminal cleanup once" {
    var consumer = Consumer.init();
    _ = consumer.dispatch(.start);
    _ = consumer.dispatch(.read_eof);
    const first = consumer.dispatch(.completion_error);
    try expect_effects(first, &.{
        .drop_stream,
        .drop_completion,
        .release_record,
        .release_frame,
        .return_err,
    });
    const second = consumer.dispatch(.completion_error);
    try std.testing.expectEqual(@as(u8, 0), second.effect_count);
    try std.testing.expectEqual(Phase.closed, second.phase);
}

test "record stream consumer cancels completion after eof" {
    var consumer = Consumer.init();
    _ = consumer.dispatch(.start);
    _ = consumer.dispatch(.read_eof);
    const transition = consumer.dispatch(.cancel);
    try expect_effects(transition, &.{
        .cancel_completion,
        .drop_stream,
        .drop_completion,
        .release_record,
        .release_frame,
        .return_err,
    });
    try std.testing.expectEqual(Phase.closed, consumer.phase);
}

test "record stream consumer read failure is terminal and invalid events are inert" {
    var consumer = Consumer.init();
    const idle_read = consumer.dispatch(.read_ok);
    try std.testing.expectEqual(@as(u8, 0), idle_read.effect_count);
    try std.testing.expectEqual(Phase.idle, idle_read.phase);

    _ = consumer.dispatch(.start);
    const failure = consumer.dispatch(.read_error);
    try expect_effects(failure, &.{
        .drop_stream,
        .drop_completion,
        .release_record,
        .release_frame,
        .return_err,
    });
    try std.testing.expectEqual(Phase.closed, consumer.phase);
}

test "generic record stream source plan accepts a dynamic Ok loop" {
    const source =
        \\probe_read = @host_func("do:record-stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<ProbeEntry>, Future<Result<nil, ProbeError>>>)
        \\
        \\async run() -> Result<nil, ProbeError> {
        \\    handles Tuple<Stream<ProbeEntry>, Future<Result<nil, ProbeError>>> = probe_read()
        \\    reader Stream<ProbeEntry> = @get(handles, 0)
        \\    completion Future<Result<nil, ProbeError>> = @get(handles, 1)
        \\    loop {
        \\        pending Future<Result<ProbeEntry, nil>> = @next(reader)
        \\        item Result<ProbeEntry, nil> = await(pending)
        \\        if @is(item, Ok) {
        \\            entry ProbeEntry = item
        \\            _ = entry
        \\        } else {
        \\            break
        \\        }
        \\    }
        \\    completed Result<nil, ProbeError> = await(completion)
        \\    if @is(completed, Err) return completed
        \\    return Ok()
        \\}
        \\
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    var plan = try RecordStreamSourcePlan.analyze(tokens, registry);
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("ProbeEntry", plan.record_type);
    try std.testing.expectEqual(@as(usize, 1), plan.loop_read_count);
    try std.testing.expect(plan.has_completion_await);
}

test "generic record stream source plan rejects concurrent next" {
    const source =
        \\probe_read = @host_func("do:record-stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<ProbeEntry>, Future<Result<nil, ProbeError>>>)
        \\
        \\async run() -> Result<nil, ProbeError> {
        \\    handles Tuple<Stream<ProbeEntry>, Future<Result<nil, ProbeError>>> = probe_read()
        \\    reader Stream<ProbeEntry> = @get(handles, 0)
        \\    completion Future<Result<nil, ProbeError>> = @get(handles, 1)
        \\    loop {
        \\        first Future<Result<ProbeEntry, nil>> = @next(reader)
        \\        second Future<Result<ProbeEntry, nil>> = @next(reader)
        \\        item Result<ProbeEntry, nil> = await(first)
        \\        if @is(item, Err) break
        \\    }
        \\    completed Result<nil, ProbeError> = await(completion)
        \\    _ = completed
        \\    return Ok()
        \\}
        \\
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    try std.testing.expectError(error.UnsupportedP3RecordStreamComponent, RecordStreamSourcePlan.analyze(tokens, registry));
}

test "generic record stream emitter is descriptor-driven" {
    const source =
        \\probe_read = @host_func("do:record-stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<ProbeEntry>, Future<Result<nil, ProbeError>>>)
        \\async run() -> Result<nil, ProbeError> {
        \\    handles Tuple<Stream<ProbeEntry>, Future<Result<nil, ProbeError>>> = probe_read()
        \\    reader Stream<ProbeEntry> = @get(handles, 0)
        \\    completion Future<Result<nil, ProbeError>> = @get(handles, 1)
        \\    loop {
        \\        pending Future<Result<ProbeEntry, nil>> = @next(reader)
        \\        item Result<ProbeEntry, nil> = await(pending)
        \\        if @is(item, Ok) {
        \\            entry ProbeEntry = item
        \\            _ = entry
        \\        } else {
        \\            break
        \\        }
        \\    }
        \\    completed Result<nil, ProbeError> = await(completion)
        \\    if @is(completed, Err) return completed
        \\    return Ok()
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[record-stream-plan]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[record-loop-state]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[record-read-index]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[record-field-id-offset]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[record-field-label-ptr-offset]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[record-field-label-len-offset]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $cleanup") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "directory-entry") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "descriptor.read-directory") == null);
}

test "generic record stream emitter derives WIT from the descriptor" {
    const source =
        \\probe_read = @host_func("do:record-stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<ProbeEntry>, Future<Result<nil, ProbeError>>>)
        \\async run() -> Result<nil, ProbeError> {
        \\    handles Tuple<Stream<ProbeEntry>, Future<Result<nil, ProbeError>>> = probe_read()
        \\    reader Stream<ProbeEntry> = @get(handles, 0)
        \\    completion Future<Result<nil, ProbeError>> = @get(handles, 1)
        \\    loop {
        \\        pending Future<Result<ProbeEntry, nil>> = @next(reader)
        \\        item Result<ProbeEntry, nil> = await(pending)
        \\        if @is(item, Ok) {
        \\            entry ProbeEntry = item
        \\            _ = entry
        \\        } else {
        \\            break
        \\        }
        \\    }
        \\    completed Result<nil, ProbeError> = await(completion)
        \\    if @is(completed, Err) return completed
        \\    return Ok()
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "package do:record-stream-probe@0.1.0;") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "record probe-entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "id: u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "label: string") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "read-via-stream: func() -> tuple<stream<probe-entry>, future<result<_, error-code>>>;") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "run: async func() -> result<_, error-code>;") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "world record-stream-probe") != null);
}

test "generic record stream emitter emits owned resource cleanup" {
    const source =
        \\probe_read = @host_func("do:record-resource-stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<ResourceEntry>, Future<Result<nil, ProbeError>>>)
        \\Ticket = @wasi_resource("do:record-resource-stream-probe/ledger/ticket", { .id i64 })
        \\ResourceEntry {
        \\    .id u32
        \\    .ticket Ticket
        \\}
        \\ProbeError error = Io | NoEntry
        \\async run() -> Result<nil, ProbeError> {
        \\    handles Tuple<Stream<ResourceEntry>, Future<Result<nil, ProbeError>>> = probe_read()
        \\    reader Stream<ResourceEntry> = @get(handles, 0)
        \\    completion Future<Result<nil, ProbeError>> = @get(handles, 1)
        \\    loop {
        \\        pending Future<Result<ResourceEntry, nil>> = @next(reader)
        \\        item Result<ResourceEntry, nil> = await(pending)
        \\        if @is(item, Ok) {
        \\            entry ResourceEntry = item
        \\            _ = entry
        \\        } else {
        \\            break
        \\        }
        \\    }
        \\    completed Result<nil, ProbeError> = await(completion)
        \\    if @is(completed, Err) return completed
        \\    return Ok()
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[record-resource-field-ticket]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[resource-drop]ticket") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $release-record") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 76") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 84") == null);

    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "resource ticket {}") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "ticket: own<ticket>") != null);
}

test "generic record stream emitter emits multiple owned resource cleanup" {
    const source =
        \\probe_read = @host_func("do:record-resource-stream-multi@0.1.0", "read-via-stream", () -> Tuple<Stream<ResourceEntry>, Future<Result<nil, ProbeError>>>)
        \\Ticket = @wasi_resource("do:record-resource-stream-multi/ledger/ticket", { .id i64 })
        \\ResourceEntry {
        \\    .id u32
        \\    .left Ticket
        \\    .right Ticket
        \\}
        \\ProbeError error = Io | NoEntry
        \\async run() -> Result<nil, ProbeError> {
        \\    handles Tuple<Stream<ResourceEntry>, Future<Result<nil, ProbeError>>> = probe_read()
        \\    reader Stream<ResourceEntry> = @get(handles, 0)
        \\    completion Future<Result<nil, ProbeError>> = @get(handles, 1)
        \\    loop {
        \\        pending Future<Result<ResourceEntry, nil>> = @next(reader)
        \\        item Result<ResourceEntry, nil> = await(pending)
        \\        if @is(item, Ok) {
        \\            entry ResourceEntry = item
        \\            _ = entry
        \\        } else {
        \\            break
        \\        }
        \\    }
        \\    completed Result<nil, ProbeError> = await(completion)
        \\    if @is(completed, Err) return completed
        \\    return Ok()
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[record-resource-field-ticket]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[record-resource-release-ticket]") != null);
    try std.testing.expectEqual(@as(usize, 2), count_substring(wat, "[record-resource-field-ticket]"));
    try std.testing.expectEqual(@as(usize, 2), count_substring(wat, "[record-resource-release-ticket]"));
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 76") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 80") != null);
    try std.testing.expectEqual(@as(usize, 1), count_substring(wat, "(import \"do:record-resource-stream-multi/source@0.1.0\" \"[resource-drop]ticket\""));

    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expectEqual(@as(usize, 1), count_substring(wit, "resource ticket {}"));
    try std.testing.expect(std.mem.indexOf(u8, wit, "left: own<ticket>") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "right: own<ticket>") != null);
}

test "generic record stream emitter emits one nested owned resource field" {
    const source =
        \\probe_read = @host_func("do:record-resource-stream-nested@0.1.0", "read-via-stream", () -> Tuple<Stream<ResourceEntry>, Future<Result<nil, ProbeError>>>)
        \\Ticket = @wasi_resource("do:record-resource-stream-nested/source/ticket", { .id i64 })
        \\InnerEntry {
        \\    .ticket Ticket
        \\}
        \\ResourceEntry {
        \\    .inner InnerEntry
        \\}
        \\ProbeError error = Io | NoEntry
        \\async run() -> Result<nil, ProbeError> {
        \\    handles Tuple<Stream<ResourceEntry>, Future<Result<nil, ProbeError>>> = probe_read()
        \\    reader Stream<ResourceEntry> = @get(handles, 0)
        \\    completion Future<Result<nil, ProbeError>> = @get(handles, 1)
        \\    loop {
        \\        pending Future<Result<ResourceEntry, nil>> = @next(reader)
        \\        item Result<ResourceEntry, nil> = await(pending)
        \\        if @is(item, Ok) {
        \\            entry ResourceEntry = item
        \\            _ = entry
        \\        } else {
        \\            break
        \\        }
        \\    }
        \\    completed Result<nil, ProbeError> = await(completion)
        \\    if @is(completed, Err) return completed
        \\    return Ok()
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[record-resource-field-ticket]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[record-resource-release-ticket]") != null);
    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "record inner-entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "ticket: own<ticket>") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "inner: inner-entry") != null);
}

test "generic record stream emitter emits two nested owned resource levels" {
    const source =
        \\probe_read = @host_func("do:record-resource-stream-nested-two-level@0.1.0", "read-via-stream", () -> Tuple<Stream<ResourceEntry>, Future<Result<nil, ProbeError>>>)
        \\Ticket = @wasi_resource("do:record-resource-stream-nested-two-level/source/ticket", { .id i64 })
        \\DeepEntry {
        \\    .ticket Ticket
        \\}
        \\InnerEntry {
        \\    .deep DeepEntry
        \\}
        \\ResourceEntry {
        \\    .inner InnerEntry
        \\}
        \\ProbeError error = Io | NoEntry
        \\async run() -> Result<nil, ProbeError> {
        \\    handles Tuple<Stream<ResourceEntry>, Future<Result<nil, ProbeError>>> = probe_read()
        \\    reader Stream<ResourceEntry> = @get(handles, 0)
        \\    completion Future<Result<nil, ProbeError>> = @get(handles, 1)
        \\    loop {
        \\        pending Future<Result<ResourceEntry, nil>> = @next(reader)
        \\        item Result<ResourceEntry, nil> = await(pending)
        \\        if @is(item, Ok) {
        \\            entry ResourceEntry = item
        \\            _ = entry
        \\        } else {
        \\            break
        \\        }
        \\    }
        \\    completed Result<nil, ProbeError> = await(completion)
        \\    if @is(completed, Err) return completed
        \\    return Ok()
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expectEqual(@as(usize, 2), count_substring(wat, "[record-resource-field-ticket]"));
    try std.testing.expectEqual(@as(usize, 1), count_substring(wat, "[record-resource-release-ticket]"));
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 80") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 84") == null);
    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "record deep-entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "record inner-entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "deep: deep-entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "ticket: own<ticket>") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "inner: inner-entry") != null);
}

test "generic record stream emitter emits three nested owned resource levels" {
    const source =
        \\probe_read = @host_func("do:record-resource-stream-nested-three-level@0.1.0", "read-via-stream", () -> Tuple<Stream<ResourceEntry>, Future<Result<nil, ProbeError>>>)
        \\Ticket = @wasi_resource("do:record-resource-stream-nested-three-level/source/ticket", { .id i64 })
        \\DeeperEntry {
        \\    .ticket Ticket
        \\}
        \\DeepEntry {
        \\    .deeper DeeperEntry
        \\}
        \\InnerEntry {
        \\    .deep DeepEntry
        \\}
        \\ResourceEntry {
        \\    .inner InnerEntry
        \\}
        \\ProbeError error = Io | NoEntry
        \\async run() -> Result<nil, ProbeError> {
        \\    handles Tuple<Stream<ResourceEntry>, Future<Result<nil, ProbeError>>> = probe_read()
        \\    reader Stream<ResourceEntry> = @get(handles, 0)
        \\    completion Future<Result<nil, ProbeError>> = @get(handles, 1)
        \\    loop {
        \\        pending Future<Result<ResourceEntry, nil>> = @next(reader)
        \\        item Result<ResourceEntry, nil> = await(pending)
        \\        if @is(item, Ok) {
        \\            entry ResourceEntry = item
        \\            _ = entry
        \\        } else {
        \\            break
        \\        }
        \\    }
        \\    completed Result<nil, ProbeError> = await(completion)
        \\    if @is(completed, Err) return completed
        \\    return Ok()
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expectEqual(@as(usize, 2), count_substring(wat, "[record-resource-field-ticket]"));
    try std.testing.expectEqual(@as(usize, 1), count_substring(wat, "[record-resource-release-ticket]"));
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 80") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 84") == null);
    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "record deeper-entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "record deep-entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "record inner-entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "deeper: deeper-entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "deep: deep-entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "ticket: own<ticket>") != null);
}

test "generic record stream emitter emits four nested owned resource levels" {
    const source =
        \\probe_read = @host_func("do:record-resource-stream-nested-four-level@0.1.0", "read-via-stream", () -> Tuple<Stream<ResourceEntry>, Future<Result<nil, ProbeError>>>)
        \\Ticket = @wasi_resource("do:record-resource-stream-nested-four-level/source/ticket", { .id i64 })
        \\DeepestEntry {
        \\    .ticket Ticket
        \\}
        \\DeeperEntry {
        \\    .deepest DeepestEntry
        \\}
        \\DeepEntry {
        \\    .deeper DeeperEntry
        \\}
        \\InnerEntry {
        \\    .deep DeepEntry
        \\}
        \\ResourceEntry {
        \\    .inner InnerEntry
        \\}
        \\ProbeError error = Io | NoEntry
        \\async run() -> Result<nil, ProbeError> {
        \\    handles Tuple<Stream<ResourceEntry>, Future<Result<nil, ProbeError>>> = probe_read()
        \\    reader Stream<ResourceEntry> = @get(handles, 0)
        \\    completion Future<Result<nil, ProbeError>> = @get(handles, 1)
        \\    loop {
        \\        pending Future<Result<ResourceEntry, nil>> = @next(reader)
        \\        item Result<ResourceEntry, nil> = await(pending)
        \\        if @is(item, Ok) {
        \\            entry ResourceEntry = item
        \\            _ = entry
        \\        } else {
        \\            break
        \\        }
        \\    }
        \\    completed Result<nil, ProbeError> = await(completion)
        \\    if @is(completed, Err) return completed
        \\    return Ok()
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expectEqual(@as(usize, 2), count_substring(wat, "[record-resource-field-ticket]"));
    try std.testing.expectEqual(@as(usize, 1), count_substring(wat, "[record-resource-release-ticket]"));
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 80") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 84") == null);
    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "record deepest-entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "record deeper-entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "record deep-entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "record inner-entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "deepest: deepest-entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "ticket: own<ticket>") != null);
}

test "generic record stream emitter emits five nested owned resource levels" {
    const source =
        \\probe_read = @host_func("do:record-resource-stream-nested-five-level@0.1.0", "read-via-stream", () -> Tuple<Stream<ResourceEntry>, Future<Result<nil, ProbeError>>>)
        \\Ticket = @wasi_resource("do:record-resource-stream-nested-five-level/source/ticket", { .id i64 })
        \\UltraEntry {
        \\    .ticket Ticket
        \\}
        \\DeepestEntry {
        \\    .ultra UltraEntry
        \\}
        \\DeeperEntry {
        \\    .deepest DeepestEntry
        \\}
        \\DeepEntry {
        \\    .deeper DeeperEntry
        \\}
        \\InnerEntry {
        \\    .deep DeepEntry
        \\}
        \\ResourceEntry {
        \\    .inner InnerEntry
        \\}
        \\ProbeError error = Io | NoEntry
        \\async run() -> Result<nil, ProbeError> {
        \\    handles Tuple<Stream<ResourceEntry>, Future<Result<nil, ProbeError>>> = probe_read()
        \\    reader Stream<ResourceEntry> = @get(handles, 0)
        \\    completion Future<Result<nil, ProbeError>> = @get(handles, 1)
        \\    loop {
        \\        pending Future<Result<ResourceEntry, nil>> = @next(reader)
        \\        item Result<ResourceEntry, nil> = await(pending)
        \\        if @is(item, Ok) {
        \\            entry ResourceEntry = item
        \\            _ = entry
        \\        } else {
        \\            break
        \\        }
        \\    }
        \\    completed Result<nil, ProbeError> = await(completion)
        \\    if @is(completed, Err) return completed
        \\    return Ok()
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expectEqual(@as(usize, 2), count_substring(wat, "[record-resource-field-ticket]"));
    try std.testing.expectEqual(@as(usize, 1), count_substring(wat, "[record-resource-release-ticket]"));
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 80") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 84") == null);
    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "record ultra-entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "record deepest-entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "record deeper-entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "record deep-entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "record inner-entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "ultra: ultra-entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "ticket: own<ticket>") != null);
}

test "generic record stream emitter emits six nested owned resource levels" {
    const source =
        \\probe_read = @host_func("do:record-resource-stream-nested-six-level@0.1.0", "read-via-stream", () -> Tuple<Stream<ResourceEntry>, Future<Result<nil, ProbeError>>>)
        \\Ticket = @wasi_resource("do:record-resource-stream-nested-six-level/source/ticket", { .id i64 })
        \\HyperEntry {
        \\    .ticket Ticket
        \\}
        \\UltraEntry {
        \\    .hyper HyperEntry
        \\}
        \\DeepestEntry {
        \\    .ultra UltraEntry
        \\}
        \\DeeperEntry {
        \\    .deepest DeepestEntry
        \\}
        \\DeepEntry {
        \\    .deeper DeeperEntry
        \\}
        \\InnerEntry {
        \\    .deep DeepEntry
        \\}
        \\ResourceEntry {
        \\    .inner InnerEntry
        \\}
        \\ProbeError error = Io | NoEntry
        \\async run() -> Result<nil, ProbeError> {
        \\    handles Tuple<Stream<ResourceEntry>, Future<Result<nil, ProbeError>>> = probe_read()
        \\    reader Stream<ResourceEntry> = @get(handles, 0)
        \\    completion Future<Result<nil, ProbeError>> = @get(handles, 1)
        \\    loop {
        \\        pending Future<Result<ResourceEntry, nil>> = @next(reader)
        \\        item Result<ResourceEntry, nil> = await(pending)
        \\        if @is(item, Ok) {
        \\            entry ResourceEntry = item
        \\            _ = entry
        \\        } else {
        \\            break
        \\        }
        \\    }
        \\    completed Result<nil, ProbeError> = await(completion)
        \\    if @is(completed, Err) return completed
        \\    return Ok()
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expectEqual(@as(usize, 2), count_substring(wat, "[record-resource-field-ticket]"));
    try std.testing.expectEqual(@as(usize, 1), count_substring(wat, "[record-resource-release-ticket]"));
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 80") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 84") == null);
    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "record hyper-entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "record ultra-entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "hyper: hyper-entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "ticket: own<ticket>") != null);
}

test "generic record stream emitter emits multiple nested owned resource paths" {
    const source =
        \\probe_read = @host_func("do:record-resource-stream-multiple-nested@0.1.0", "read-via-stream", () -> Tuple<Stream<ResourceEntry>, Future<Result<nil, ProbeError>>>)
        \\Ticket = @wasi_resource("do:record-resource-stream-multiple-nested/source/ticket", { .id i64 })
        \\LeftEntry {
        \\    .ticket Ticket
        \\}
        \\RightEntry {
        \\    .ticket Ticket
        \\}
        \\ResourceEntry {
        \\    .left LeftEntry
        \\    .right RightEntry
        \\}
        \\ProbeError error = Io | NoEntry
        \\async run() -> Result<nil, ProbeError> {
        \\    handles Tuple<Stream<ResourceEntry>, Future<Result<nil, ProbeError>>> = probe_read()
        \\    reader Stream<ResourceEntry> = @get(handles, 0)
        \\    completion Future<Result<nil, ProbeError>> = @get(handles, 1)
        \\    loop {
        \\        pending Future<Result<ResourceEntry, nil>> = @next(reader)
        \\        item Result<ResourceEntry, nil> = await(pending)
        \\        if @is(item, Ok) {
        \\            entry ResourceEntry = item
        \\            _ = entry
        \\        } else {
        \\            break
        \\        }
        \\    }
        \\    completed Result<nil, ProbeError> = await(completion)
        \\    if @is(completed, Err) return completed
        \\    return Ok()
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expectEqual(@as(usize, 4), count_substring(wat, "[record-resource-field-ticket]"));
    try std.testing.expectEqual(@as(usize, 2), count_substring(wat, "[record-resource-release-ticket]"));
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 4") != null);
    try std.testing.expectEqual(@as(usize, 1), count_substring(wat, "[resource-drop]ticket"));
    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expectEqual(@as(usize, 1), count_substring(wit, "resource ticket {}"));
    try std.testing.expect(std.mem.indexOf(u8, wit, "record left-entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "record right-entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "left: left-entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "right: right-entry") != null);
}

fn count_substring(haystack: []const u8, needle: []const u8) usize {
    if (needle.len == 0) return 0;
    var count: usize = 0;
    var start: usize = 0;
    while (std.mem.indexOf(u8, haystack[start..], needle)) |relative| {
        count += 1;
        start += relative + needle.len;
        if (start >= haystack.len) break;
    }
    return count;
}
