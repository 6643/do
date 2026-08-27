//! Structural validation for the bounded GC host/WIT descriptor manifest.
//!
//! This module owns only JSON shape and identity guards. It does not read
//! source files or import compiler/codegen modules; provenance verification is
//! implemented by the build-side adapter.
const std = @import("std");

pub const ManifestError = error{
    InvalidManifest,
    ManifestSchemaUnsupported,
    ManifestMissingField,
    ManifestToolchainInvalid,
    DuplicateDescriptorId,
    DescriptorIdInvalid,
    DescriptorPathInvalid,
    DescriptorHashInvalid,
    DescriptorPackageInvalid,
    DescriptorWorldInvalid,
    DescriptorMemberInvalid,
    DescriptorDirectionInvalid,
    DescriptorSignatureInvalid,
    DescriptorCanonicalImportInvalid,
    DescriptorMeasurementInvalid,
    DescriptorNotFound,
};

pub const Direction = enum { lift, lower };

pub const CanonicalImport = struct {
    module: []const u8,
    name: []const u8,
};

pub const MeasurementKind = enum {
    scalar,
    text,
    list,
    byte_list,
    record,
};

pub const MeasuredField = struct {
    name: []const u8,
    offset: u32,
    byte_size: u32,
    alignment: u32,
};

/// Manifest-owned, recursively decoded layout facts. Slices point into the
/// parsed JSON tree except for arrays allocated by this module.
pub const MeasuredNode = struct {
    kind: MeasurementKind,
    byte_size: u32,
    alignment: u32,
    offset: ?u32 = null,
    core_type: ?[]const u8 = null,
    pointer_offset: ?u32 = null,
    length_offset: ?u32 = null,
    element_byte_size: ?u32 = null,
    element_stride: ?u32 = null,
    element_alignment: ?u32 = null,
    ticket_offset: ?u32 = null,
    capacity: ?u32 = null,
    allocation: ?[]const u8 = null,
    free: ?[]const u8 = null,
    accepted_lengths: []const u32 = &.{},
    fields: []const MeasuredField = &.{},
    children: []const MeasuredNode = &.{},
};

pub const Descriptor = struct {
    id: []const u8,
    source: []const u8,
    world_source: []const u8,
    package: []const u8,
    world: []const u8,
    interface: []const u8,
    member: []const u8,
    direction: Direction,
    params: []const []const u8,
    result: []const u8,
    /// Optional Do-side nominal record name. When present, the build-side
    /// host-boundary validator must require the declaration to use this
    /// exact identifier; older descriptors remain shape-only compatible.
    do_record_name: ?[]const u8 = null,
    source_sha256: []const u8,
    canonical_import: CanonicalImport,
    measured_layout: ?MeasuredNode = null,
};

pub const Document = struct {
    schema: u32,
    toolchain: []const u8,
    descriptors: []const Descriptor,
};

pub const Parsed = struct {
    tree: std.json.Parsed(std.json.Value),
    document: Document,
    allocator: std.mem.Allocator,

    pub fn find_descriptor(self: *const Parsed, id: []const u8) ManifestError!Descriptor {
        for (self.document.descriptors) |descriptor| {
            if (std.mem.eql(u8, descriptor.id, id)) return descriptor;
        }
        return error.DescriptorNotFound;
    }

    pub fn deinit(self: *Parsed, allocator: std.mem.Allocator) void {
        for (self.document.descriptors) |descriptor| {
            allocator.free(descriptor.params);
            if (descriptor.measured_layout) |layout| deinit_measured_node(allocator, layout);
        }
        allocator.free(self.document.descriptors);
        self.tree.deinit();
        self.* = undefined;
    }
};

pub fn parse(allocator: std.mem.Allocator, source: []const u8) (ManifestError || std.mem.Allocator.Error)!Parsed {
    var tree = std.json.parseFromSlice(std.json.Value, allocator, source, .{}) catch return error.InvalidManifest;
    errdefer tree.deinit();

    const root = object_value(tree.value) orelse return error.InvalidManifest;
    const schema = unsigned_value(root.get("schema")) orelse return error.ManifestMissingField;
    if (schema != 1) return error.ManifestSchemaUnsupported;
    const toolchain = string_value(root.get("toolchain")) orelse return error.ManifestMissingField;
    if (toolchain.len == 0 or !std.mem.startsWith(u8, toolchain, "wasm-tools ")) {
        return error.ManifestToolchainInvalid;
    }
    const values = array_value(root.get("descriptors")) orelse return error.ManifestMissingField;
    var descriptors = try allocator.alloc(Descriptor, values.items.len);
    var initialized: usize = 0;
    errdefer {
        for (descriptors[0..initialized]) |descriptor| {
            allocator.free(descriptor.params);
            if (descriptor.measured_layout) |layout| deinit_measured_node(allocator, layout);
        }
        allocator.free(descriptors);
    }
    for (values.items, 0..) |value, index| {
        const object = object_value(value) orelse return error.InvalidManifest;
        const id = string_value(object.get("id")) orelse return error.ManifestMissingField;
        for (descriptors[0..initialized]) |existing| {
            if (std.mem.eql(u8, existing.id, id)) return error.DuplicateDescriptorId;
        }
        const descriptor = try parse_descriptor(allocator, value);
        descriptors[index] = descriptor;
        initialized += 1;
    }

    return .{
        .tree = tree,
        .document = .{
            .schema = @intCast(schema),
            .toolchain = toolchain,
            .descriptors = descriptors,
        },
        .allocator = allocator,
    };
}

fn parse_descriptor(allocator: std.mem.Allocator, value: std.json.Value) (ManifestError || std.mem.Allocator.Error)!Descriptor {
    const object = object_value(value) orelse return error.InvalidManifest;
    const id = string_value(object.get("id")) orelse return error.ManifestMissingField;
    const source = string_value(object.get("source")) orelse return error.ManifestMissingField;
    const world_source = string_value(object.get("world_source")) orelse return error.ManifestMissingField;
    const package = string_value(object.get("package")) orelse return error.ManifestMissingField;
    const world = string_value(object.get("world")) orelse return error.ManifestMissingField;
    const interface = string_value(object.get("interface")) orelse return error.ManifestMissingField;
    const member = string_value(object.get("member")) orelse return error.ManifestMissingField;
    const direction_text = string_value(object.get("direction")) orelse return error.ManifestMissingField;
    const result = string_value(object.get("result")) orelse return error.ManifestMissingField;
    const source_sha256 = string_value(object.get("source_sha256")) orelse return error.ManifestMissingField;
    if (!valid_text(id)) return error.DescriptorIdInvalid;
    if (!valid_relative_path(source) or !valid_relative_path(world_source)) return error.DescriptorPathInvalid;
    if (!valid_package(package)) return error.DescriptorPackageInvalid;
    if (!valid_identifier(world) or !valid_identifier(interface)) return error.DescriptorWorldInvalid;
    if (!valid_identifier(member) and !valid_member(member)) return error.DescriptorMemberInvalid;
    const direction = if (std.mem.eql(u8, direction_text, "lift")) Direction.lift else if (std.mem.eql(u8, direction_text, "lower")) Direction.lower else return error.DescriptorDirectionInvalid;
    if (!valid_text(result) or !valid_sha256(source_sha256)) return error.DescriptorHashInvalid;
    const do_record_name = if (object.get("do_record_name")) |raw| blk: {
        const name = string_value(raw) orelse return error.DescriptorSignatureInvalid;
        if (!valid_identifier(name)) return error.DescriptorSignatureInvalid;
        break :blk name;
    } else null;

    const param_values = array_value(object.get("params")) orelse return error.ManifestMissingField;
    var params = try allocator.alloc([]const u8, param_values.items.len);
    errdefer allocator.free(params);
    for (param_values.items, 0..) |param_value, index| {
        const param = string_value(param_value) orelse return error.DescriptorSignatureInvalid;
        if (!valid_text(param)) return error.DescriptorSignatureInvalid;
        params[index] = param;
    }

    const import_value = object.get("canonical_import") orelse return error.ManifestMissingField;
    const import_object = object_value(import_value) orelse return error.ManifestMissingField;
    const import_module = string_value(import_object.get("module")) orelse return error.DescriptorCanonicalImportInvalid;
    const import_name = string_value(import_object.get("name")) orelse return error.DescriptorCanonicalImportInvalid;
    if (!valid_text(import_module) or !valid_member(import_name)) return error.DescriptorCanonicalImportInvalid;

    var measured_layout: ?MeasuredNode = null;
    errdefer if (measured_layout) |layout| deinit_measured_node(allocator, layout);
    if (object.get("measured_layout")) |raw_layout| {
        measured_layout = try parse_measured_node(allocator, raw_layout);
    }

    return .{
        .id = id,
        .source = source,
        .world_source = world_source,
        .package = package,
        .world = world,
        .interface = interface,
        .member = member,
        .direction = direction,
        .params = params,
        .result = result,
        .do_record_name = do_record_name,
        .source_sha256 = source_sha256,
        .canonical_import = .{ .module = import_module, .name = import_name },
        .measured_layout = measured_layout,
    };
}

fn parse_measured_node(allocator: std.mem.Allocator, value: std.json.Value) (ManifestError || std.mem.Allocator.Error)!MeasuredNode {
    const object = object_value(value) orelse return error.DescriptorMeasurementInvalid;
    const kind_text = string_value(object.get("kind")) orelse return error.DescriptorMeasurementInvalid;
    const kind = parse_measurement_kind(kind_text) orelse return error.DescriptorMeasurementInvalid;
    const byte_size = bounded_u32(object.get("byte_size")) orelse return error.DescriptorMeasurementInvalid;
    const alignment = bounded_u32(object.get("alignment")) orelse return error.DescriptorMeasurementInvalid;
    if (byte_size == 0 or !valid_alignment(alignment) or byte_size % alignment != 0) {
        return error.DescriptorMeasurementInvalid;
    }

    var node: MeasuredNode = .{
        .kind = kind,
        .byte_size = byte_size,
        .alignment = alignment,
        .offset = optional_u32(object.get("offset")),
    };
    errdefer deinit_measured_node(allocator, node);

    switch (kind) {
        .scalar => {
            if (node.offset == null) return error.DescriptorMeasurementInvalid;
            const core_type = string_value(object.get("core_type")) orelse return error.DescriptorMeasurementInvalid;
            if (!valid_core_type(core_type)) return error.DescriptorMeasurementInvalid;
            node.core_type = core_type;
            const expected_size: u32 = if (std.mem.eql(u8, core_type, "i64") or std.mem.eql(u8, core_type, "f64")) 8 else 4;
            const expected_alignment: u32 = expected_size;
            if (byte_size != expected_size or alignment != expected_alignment) {
                return error.DescriptorMeasurementInvalid;
            }
        },
        .text => {
            node.pointer_offset = bounded_u32(object.get("pointer_offset"));
            node.length_offset = bounded_u32(object.get("length_offset"));
            node.allocation = string_value(object.get("allocation"));
            node.free = string_value(object.get("free"));
            if (node.pointer_offset == null or node.length_offset == null or
                node.allocation == null or node.free == null or
                !std.mem.eql(u8, node.allocation.?, "cabi_realloc") or
                !std.mem.eql(u8, node.free.?, "cabi_realloc") or
                byte_size != 8 or alignment != 4)
            {
                return error.DescriptorMeasurementInvalid;
            }
            if (node.pointer_offset.? == node.length_offset.? or
                !valid_region(node.pointer_offset.?, 4, byte_size) or
                !valid_region(node.length_offset.?, 4, byte_size) or
                !is_aligned(node.pointer_offset.?, 4) or
                !is_aligned(node.length_offset.?, 4))
            {
                return error.DescriptorMeasurementInvalid;
            }
        },
        .list, .byte_list => {
            node.pointer_offset = bounded_u32(object.get("pointer_offset"));
            node.length_offset = bounded_u32(object.get("length_offset"));
            node.element_byte_size = bounded_u32(object.get("element_byte_size"));
            node.element_stride = bounded_u32(object.get("element_stride"));
            node.element_alignment = bounded_u32(object.get("element_alignment"));
            node.ticket_offset = bounded_u32(object.get("ticket_offset"));
            node.capacity = bounded_u32(object.get("capacity"));
            node.allocation = string_value(object.get("allocation"));
            node.free = string_value(object.get("free"));
            if (node.pointer_offset == null or node.length_offset == null or
                node.element_byte_size == null or node.element_stride == null or
                node.element_alignment == null or node.capacity == null or
                node.allocation == null or node.free == null or
                !std.mem.eql(u8, node.allocation.?, "cabi_realloc") or
                !std.mem.eql(u8, node.free.?, "cabi_realloc") or
                node.pointer_offset.? == node.length_offset.? or
                !valid_region(node.pointer_offset.?, 4, byte_size) or
                !valid_region(node.length_offset.?, 4, byte_size) or
                !valid_alignment(node.element_alignment.?) or
                node.element_byte_size.? == 0 or
                node.element_stride.? < node.element_byte_size.? or
                node.element_stride.? % node.element_alignment.? != 0)
            {
                return error.DescriptorMeasurementInvalid;
            }
            if (kind == .byte_list and
                (node.element_byte_size.? != 1 or node.element_stride.? != 1 or node.element_alignment.? != 1))
            {
                return error.DescriptorMeasurementInvalid;
            }
            if (kind == .list and node.ticket_offset == null) {
                return error.DescriptorMeasurementInvalid;
            }
            if (object.get("accepted_lengths")) |raw_lengths| {
                const length_values = array_value(raw_lengths) orelse return error.DescriptorMeasurementInvalid;
                var accepted = try allocator.alloc(u32, length_values.items.len);
                errdefer allocator.free(accepted);
                for (length_values.items, 0..) |raw_length, index| {
                    accepted[index] = bounded_u32(raw_length) orelse return error.DescriptorMeasurementInvalid;
                }
                node.accepted_lengths = accepted;
            }
        },
        .record => {
            const field_values = array_value(object.get("fields")) orelse return error.DescriptorMeasurementInvalid;
            const child_values = array_value(object.get("children")) orelse return error.DescriptorMeasurementInvalid;
            if (field_values.items.len == 0 or field_values.items.len != child_values.items.len) {
                return error.DescriptorMeasurementInvalid;
            }
            node.fields = try parse_measured_fields(allocator, field_values, byte_size);
            node.children = try parse_measured_children(allocator, child_values);
            for (node.fields, node.children) |field, child| {
                if (child.offset) |offset| {
                    if (offset != field.offset) return error.DescriptorMeasurementInvalid;
                }
            }
        },
    }

    if (kind != .record) {
        if (object.get("children")) |raw_children| {
            const children = array_value(raw_children) orelse return error.DescriptorMeasurementInvalid;
            if (children.items.len != 0) return error.DescriptorMeasurementInvalid;
        }
        if (object.get("fields")) |raw_fields| {
            const fields = array_value(raw_fields) orelse return error.DescriptorMeasurementInvalid;
            if (fields.items.len != 0) return error.DescriptorMeasurementInvalid;
        }
    }
    return node;
}

fn parse_measured_fields(
    allocator: std.mem.Allocator,
    values: std.json.Array,
    container_size: u32,
) (ManifestError || std.mem.Allocator.Error)![]const MeasuredField {
    var fields = try allocator.alloc(MeasuredField, values.items.len);
    var initialized: usize = 0;
    errdefer allocator.free(fields);
    for (values.items, 0..) |value, index| {
        const object = object_value(value) orelse return error.DescriptorMeasurementInvalid;
        const name = string_value(object.get("name")) orelse return error.DescriptorMeasurementInvalid;
        const offset = bounded_u32(object.get("offset")) orelse return error.DescriptorMeasurementInvalid;
        const byte_size = bounded_u32(object.get("byte_size")) orelse return error.DescriptorMeasurementInvalid;
        const alignment = bounded_u32(object.get("alignment")) orelse return error.DescriptorMeasurementInvalid;
        if (!valid_text(name) or byte_size == 0 or !valid_alignment(alignment) or
            !is_aligned(offset, alignment) or !valid_region(offset, byte_size, container_size))
        {
            return error.DescriptorMeasurementInvalid;
        }
        if (index != 0) {
            const previous = fields[index - 1];
            if (offset <= previous.offset or !valid_region(previous.offset, previous.byte_size, offset)) {
                return error.DescriptorMeasurementInvalid;
            }
        }
        for (fields[0..initialized]) |existing| {
            if (std.mem.eql(u8, existing.name, name)) return error.DescriptorMeasurementInvalid;
        }
        fields[index] = .{ .name = name, .offset = offset, .byte_size = byte_size, .alignment = alignment };
        initialized += 1;
    }
    return fields;
}

fn parse_measured_children(
    allocator: std.mem.Allocator,
    values: std.json.Array,
) (ManifestError || std.mem.Allocator.Error)![]const MeasuredNode {
    var children = try allocator.alloc(MeasuredNode, values.items.len);
    var initialized: usize = 0;
    errdefer {
        for (children[0..initialized]) |child| deinit_measured_node(allocator, child);
        allocator.free(children);
    }
    for (values.items, 0..) |value, index| {
        children[index] = try parse_measured_node(allocator, value);
        initialized += 1;
    }
    return children;
}

fn deinit_measured_node(allocator: std.mem.Allocator, node: MeasuredNode) void {
    for (node.children) |child| deinit_measured_node(allocator, child);
    if (node.children.len != 0) allocator.free(node.children);
    if (node.fields.len != 0) allocator.free(node.fields);
    if (node.accepted_lengths.len != 0) allocator.free(node.accepted_lengths);
}

fn parse_measurement_kind(value: []const u8) ?MeasurementKind {
    if (std.mem.eql(u8, value, "scalar")) return .scalar;
    if (std.mem.eql(u8, value, "text")) return .text;
    if (std.mem.eql(u8, value, "list")) return .list;
    if (std.mem.eql(u8, value, "byte_list")) return .byte_list;
    if (std.mem.eql(u8, value, "record")) return .record;
    return null;
}

fn valid_core_type(value: []const u8) bool {
    return std.mem.eql(u8, value, "i32") or std.mem.eql(u8, value, "i64") or
        std.mem.eql(u8, value, "f32") or std.mem.eql(u8, value, "f64");
}

fn valid_alignment(value: u32) bool {
    return value != 0 and (value & (value - 1)) == 0;
}

fn is_aligned(value: u32, alignment: u32) bool {
    return alignment != 0 and value % alignment == 0;
}

fn valid_region(offset: u32, byte_size: u32, container_size: u32) bool {
    return @as(u64, offset) + @as(u64, byte_size) <= @as(u64, container_size);
}

fn valid_relative_path(path: []const u8) bool {
    if (path.len == 0 or path[0] == '/' or std.mem.indexOfScalar(u8, path, '\\') != null) return false;
    var segments = std.mem.splitScalar(u8, path, '/');
    while (segments.next()) |segment| {
        if (segment.len == 0 or std.mem.eql(u8, segment, ".") or std.mem.eql(u8, segment, "..")) return false;
    }
    return true;
}

fn valid_package(package: []const u8) bool {
    const colon = std.mem.indexOfScalar(u8, package, ':') orelse return false;
    const at = std.mem.indexOfScalarPos(u8, package, colon + 1, '@') orelse return false;
    if (!valid_identifier(package[0..colon]) or !valid_identifier(package[colon + 1 .. at])) return false;
    return valid_version(package[at + 1 ..]);
}

fn valid_version(version: []const u8) bool {
    const dash = std.mem.indexOfScalar(u8, version, '-');
    const numeric = if (dash) |index| version[0..index] else version;
    var parts = std.mem.splitScalar(u8, numeric, '.');
    var count: usize = 0;
    while (parts.next()) |part| {
        if (part.len == 0) return false;
        for (part) |ch| if (!std.ascii.isDigit(ch)) return false;
        count += 1;
    }
    if (count != 3) return false;
    if (dash) |index| {
        if (index + 1 >= version.len) return false;
        for (version[index + 1 ..]) |ch| if (!(std.ascii.isAlphanumeric(ch) or ch == '.' or ch == '-')) return false;
    }
    return true;
}

fn valid_identifier(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value, 0..) |ch, index| {
        if (index == 0) {
            if (!(std.ascii.isAlphabetic(ch) or ch == '_')) return false;
        } else if (!(std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '-')) return false;
    }
    return true;
}

fn valid_member(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |ch| if (!(std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '-')) return false;
    return true;
}

fn valid_text(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |ch| if (ch < 0x20 or ch == '"' or ch == '\\') return false;
    return true;
}

fn valid_sha256(value: []const u8) bool {
    if (value.len != "sha256:".len + 64 or !std.mem.startsWith(u8, value, "sha256:")) return false;
    for (value["sha256:".len..]) |ch| if (!(std.ascii.isDigit(ch) or (ch >= 'a' and ch <= 'f'))) return false;
    return true;
}

fn object_value(value: std.json.Value) ?std.json.ObjectMap {
    return switch (value) { .object => |object| object, else => null };
}

fn array_value(value: ?std.json.Value) ?std.json.Array {
    const actual = value orelse return null;
    return switch (actual) { .array => |array| array, else => null };
}

fn string_value(value: ?std.json.Value) ?[]const u8 {
    const actual = value orelse return null;
    return switch (actual) { .string => |text| text, else => null };
}

fn unsigned_value(value: ?std.json.Value) ?u64 {
    const actual = value orelse return null;
    return switch (actual) { .integer => |number| if (number >= 0) @intCast(number) else null, else => null };
}

fn bounded_u32(value: ?std.json.Value) ?u32 {
    const number = unsigned_value(value) orelse return null;
    if (number > std.math.maxInt(u32)) return null;
    return @intCast(number);
}

fn optional_u32(value: ?std.json.Value) ?u32 {
    if (value == null) return null;
    return bounded_u32(value);
}
