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
    DescriptorNotFound,
};

pub const Direction = enum { lift, lower };

pub const CanonicalImport = struct {
    module: []const u8,
    name: []const u8,
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
    source_sha256: []const u8,
    canonical_import: CanonicalImport,
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
        for (descriptors[0..initialized]) |descriptor| allocator.free(descriptor.params);
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
        .source_sha256 = source_sha256,
        .canonical_import = .{ .module = import_module, .name = import_name },
    };
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
