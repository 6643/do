//! Provenance-checked adapter for bounded GC Component marshal requests.
//!
//! A request may select a descriptor id, but it cannot supply an independent
//! source, package, signature, or canonical import. This module reads the
//! checked-in manifest and repository-relative WIT files, then validates every
//! claim against the parser-backed binding before returning a marshal request.
const std = @import("std");
const descriptor_manifest = @import("../wit/descriptor_manifest.zig");
const wit_model = @import("../wit/model.zig");
const wit_resolve = @import("../wit/resolve.zig");
const wit_registry = @import("../wit/marshal_registry.zig");
const marshal = @import("codegen_component_marshal_plan.zig");
const wit_layout = @import("wit_abi_layout.zig");
const marshal_registry = @import("codegen_component_marshal_registry.zig");
const marshal_route = @import("codegen_component_marshal_route.zig");
const lexer = @import("lexer.zig");
const host_boundary = @import("codegen_gc_wit_host_boundary.zig");

pub const LoadedRequest = struct {
    manifest: descriptor_manifest.Parsed,
    manifest_source: []u8,
    source: []u8,
    request: marshal_route.Request,
    /// The already validated plan used to build `request`; retaining it avoids
    /// reparsing or rebuilding provenance facts at the ordinary-call boundary.
    plan: marshal.SyncValuePlan,
    /// Source-level host admission facts derived from the same resolved WIT
    /// binding as `plan`; all names are owned by this request.
    host_boundary: ?host_boundary.OwnedHostBoundarySpec,
    owned_measured: ?marshal.MeasuredNode = null,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *LoadedRequest) void {
        if (self.host_boundary) |*boundary| boundary.deinit();
        marshal.deinit_sync_value_plan(self.allocator, self.plan);
        if (self.owned_measured) |measured| deinit_marshal_measured_node(self.allocator, measured);
        self.manifest.deinit(self.allocator);
        self.allocator.free(self.manifest_source);
        self.allocator.free(self.source);
        self.* = undefined;
    }
};

pub fn load_request(
    io: std.Io,
    allocator: std.mem.Allocator,
    repository_root: []const u8,
    manifest_path: []const u8,
    descriptor_id: []const u8,
    measured: marshal.MeasuredNode,
    canonical_u64_arg: ?u64,
) !LoadedRequest {
    return load_request_internal(
        io,
        allocator,
        repository_root,
        manifest_path,
        descriptor_id,
        measured,
        false,
        canonical_u64_arg,
    );
}

pub fn load_request_from_manifest(
    io: std.Io,
    allocator: std.mem.Allocator,
    repository_root: []const u8,
    manifest_path: []const u8,
    descriptor_id: []const u8,
    canonical_u64_arg: ?u64,
) !LoadedRequest {
    return load_request_internal(
        io,
        allocator,
        repository_root,
        manifest_path,
        descriptor_id,
        null,
        true,
        canonical_u64_arg,
    );
}

/// Validate the Do declaration against the resolved WIT member. The boundary
/// spec is derived from WIT records and exists only for the duration of this
/// call; descriptor ids remain lookup keys, not shape tables.
pub fn validate_host_boundary_from_manifest(
    io: std.Io,
    allocator: std.mem.Allocator,
    repository_root: []const u8,
    manifest_path: []const u8,
    descriptor_id: []const u8,
    tokens: []const lexer.Token,
) !void {
    var loaded = try load_request_from_manifest(
        io,
        allocator,
        repository_root,
        manifest_path,
        descriptor_id,
        null,
    );
    defer loaded.deinit();
    try validate_loaded_host_boundary(&loaded, tokens);
}

pub fn validate_loaded_host_boundary(
    loaded: *const LoadedRequest,
    tokens: []const lexer.Token,
) !void {
    const boundary = loaded.host_boundary orelse return error.UnsupportedGcWitHostDescriptor;
    try host_boundary.validate_with_spec(tokens, boundary.as_spec());
}

fn build_host_boundary_fields(
    allocator: std.mem.Allocator,
    records: []const wit_model.RecordDecl,
    record: *const wit_model.RecordDecl,
) ![]host_boundary.HostBoundaryField {
    const fields = try allocator.alloc(host_boundary.HostBoundaryField, record.fields.len);
    var initialized: usize = 0;
    errdefer {
        for (fields[0..initialized]) |field| {
            if (field.nested_fields) |nested_fields| free_host_boundary_fields(allocator, nested_fields);
        }
        allocator.free(fields);
    }
    for (record.fields, 0..) |field, index| {
        if (do_boundary_type(field.type_ref)) |ty| {
            fields[index] = .{ .name = field.name, .ty = ty };
            initialized += 1;
            continue;
        }
        if (field.type_ref.kind != .named) return error.UnsupportedWitShape;
        const nested_record = find_record(records, field.type_ref.name) orelse return error.UnsupportedWitShape;
        fields[index] = .{
            .name = field.name,
            .ty = "",
            .nested_fields = try build_host_boundary_fields(allocator, records, nested_record),
        };
        initialized += 1;
    }
    return fields;
}

fn free_host_boundary_fields(allocator: std.mem.Allocator, fields: []const host_boundary.HostBoundaryField) void {
    for (fields) |field| {
        if (field.nested_fields) |nested_fields| free_host_boundary_fields(allocator, nested_fields);
    }
    allocator.free(@constCast(fields));
}

fn load_request_internal(
    io: std.Io,
    allocator: std.mem.Allocator,
    repository_root: []const u8,
    manifest_path: []const u8,
    descriptor_id: []const u8,
    measured_override: ?marshal.MeasuredNode,
    require_manifest_measurement: bool,
    canonical_u64_arg: ?u64,
) !LoadedRequest {
    if (!valid_relative_path(manifest_path)) return error.ManifestPathInvalid;

    const manifest_source = try read_relative(io, allocator, repository_root, manifest_path);
    errdefer allocator.free(manifest_source);
    var parsed = descriptor_manifest.parse(allocator, manifest_source) catch |err| return err;
    errdefer parsed.deinit(allocator);
    const descriptor = try parsed.find_descriptor(descriptor_id);

    var owned_measured: ?marshal.MeasuredNode = null;
    errdefer if (owned_measured) |measured| deinit_marshal_measured_node(allocator, measured);
    const measured = if (measured_override) |measured| measured else blk: {
        if (!require_manifest_measurement) return error.DescriptorMeasurementMissing;
        const layout = descriptor.measured_layout orelse return error.DescriptorMeasurementMissing;
        const converted = try convert_manifest_measurement(allocator, layout);
        owned_measured = converted;
        break :blk converted;
    };

    const source_part = try read_relative(io, allocator, repository_root, descriptor.source);
    defer allocator.free(source_part);
    const world_part = try read_relative(io, allocator, repository_root, descriptor.world_source);
    defer allocator.free(world_part);

    const source = try concatenate_sources(allocator, source_part, world_part);
    errdefer allocator.free(source);

    try verify_source_hash(source, descriptor.source_sha256);

    var binding = try wit_resolve.resolve_source(allocator, source, descriptor.world);
    defer binding.deinit();
    try validate_binding_claims(allocator, &binding, descriptor);

    const member = wit_registry.find_value_member(&binding, descriptor.interface, descriptor.member) catch |err| switch (err) {
        error.InterfaceNotFound => return error.InterfaceMismatch,
        error.MemberNotFound => return error.MemberMismatch,
        error.UnsupportedMarshalMember => return error.UnsupportedWitShape,
    };
    const root_type = switch (descriptor.direction) {
        .lower => if (member.function.params.len == 1) member.function.params[0].type_ref else return error.SignatureMismatch,
        .lift => member.function.result orelse return error.SignatureMismatch,
    };

    var owned_host_boundary: ?host_boundary.OwnedHostBoundarySpec = null;
    if (root_type.kind == .named) {
        const record = find_record(member.interface.records, root_type.name) orelse return error.UnsupportedWitShape;
        const fields = try build_host_boundary_fields(allocator, member.interface.records, record);
        defer free_host_boundary_fields(allocator, fields);
        owned_host_boundary = try host_boundary.OwnedHostBoundarySpec.from_spec(allocator, .{
            .locator = descriptor.canonical_import.module,
            .member = descriptor.member,
            .record_name = descriptor.do_record_name orelse "",
            .fields = fields,
            .shape = switch (descriptor.direction) {
                .lower => .lower_record,
                .lift => .lift_record,
            },
        });
    }
    errdefer if (owned_host_boundary) |*boundary| boundary.deinit();

    const direction: marshal.Direction = switch (descriptor.direction) {
        .lift => .lift,
        .lower => .lower,
    };
    const plan = marshal_registry.build_sync_value_plan_from_wit_source(
        allocator,
        source,
        descriptor.world,
        descriptor.interface,
        descriptor.member,
        direction,
        measured,
    ) catch |err| return map_plan_error(err);
    errdefer marshal.deinit_sync_value_plan(allocator, plan);

    const owned_source = source;
    errdefer allocator.free(owned_source);
    return .{
        .manifest = parsed,
        .manifest_source = manifest_source,
        .source = owned_source,
        .request = .{
            .source = owned_source,
            .world_name = descriptor.world,
            .interface_name = descriptor.interface,
            .member_name = descriptor.member,
            .direction = direction,
            .measured = measured,
            .canonical_u64_arg = canonical_u64_arg,
        },
        .plan = plan,
        .host_boundary = owned_host_boundary,
        .owned_measured = owned_measured,
        .allocator = allocator,
    };
}

fn convert_manifest_measurement(
    allocator: std.mem.Allocator,
    node: descriptor_manifest.MeasuredNode,
) !marshal.MeasuredNode {
    var children: []marshal.MeasuredNode = &.{};
    var initialized_children: usize = 0;
    if (node.children.len != 0) {
        children = try allocator.alloc(marshal.MeasuredNode, node.children.len);
    }
    errdefer {
        for (children[0..initialized_children]) |child| deinit_marshal_measured_node(allocator, child);
        if (children.len != 0) allocator.free(children);
    }
    for (node.children, 0..) |child, index| {
        children[index] = try convert_manifest_measurement(allocator, child);
        initialized_children += 1;
    }

    switch (node.kind) {
        .scalar => {
            return .{
                .layout = .{ .scalar = .{
                    .offset = node.offset orelse return error.DescriptorMeasurementInvalid,
                    .byte_size = node.byte_size,
                    .alignment = node.alignment,
                    .core_type = try convert_core_type(node.core_type orelse return error.DescriptorMeasurementInvalid),
                } },
                .children = children,
            };
        },
        .text => {
            return .{
                .layout = .{ .text = .{
                    .pointer_offset = node.pointer_offset orelse return error.DescriptorMeasurementInvalid,
                    .length_offset = node.length_offset orelse return error.DescriptorMeasurementInvalid,
                    .byte_size = node.byte_size,
                    .alignment = node.alignment,
                    .allocation = try convert_allocation_action(node.allocation orelse return error.DescriptorMeasurementInvalid),
                    .free = try convert_free_action(node.free orelse return error.DescriptorMeasurementInvalid),
                } },
                .children = children,
            };
        },
        .list => {
            // The manifest schema stores list container facts only. C17's
            // admitted list shape is list<u32>, whose canonical scalar
            // element is i32; materialize that child for the marshal binder.
            if (children.len != 0 or
                node.element_byte_size.? != 4 or
                node.element_stride.? != 4 or
                node.element_alignment.? != 4)
            {
                return error.DescriptorMeasurementInvalid;
            }
            children = try allocator.alloc(marshal.MeasuredNode, 1);
            children[0] = .{ .layout = .{ .scalar = .{
                .offset = 0,
                .byte_size = 4,
                .alignment = 4,
                .core_type = .i32,
            } } };
            initialized_children = 1;
            return .{
                .layout = .{ .list = .{
                    .pointer_offset = node.pointer_offset orelse return error.DescriptorMeasurementInvalid,
                    .length_offset = node.length_offset orelse return error.DescriptorMeasurementInvalid,
                    .element_byte_size = node.element_byte_size orelse return error.DescriptorMeasurementInvalid,
                    .element_stride = node.element_stride orelse return error.DescriptorMeasurementInvalid,
                    .element_alignment = node.element_alignment orelse return error.DescriptorMeasurementInvalid,
                    .ticket_offset = node.ticket_offset orelse return error.DescriptorMeasurementInvalid,
                    .capacity = node.capacity orelse return error.DescriptorMeasurementInvalid,
                    .accepted_lengths = node.accepted_lengths,
                    .allocation = try convert_allocation_action(node.allocation orelse return error.DescriptorMeasurementInvalid),
                    .free = try convert_free_action(node.free orelse return error.DescriptorMeasurementInvalid),
                } },
                .children = children,
            };
        },
        .byte_list => {
            return .{
                .layout = .{ .byte_list = .{
                    .pointer_offset = node.pointer_offset orelse return error.DescriptorMeasurementInvalid,
                    .length_offset = node.length_offset orelse return error.DescriptorMeasurementInvalid,
                    .element_byte_size = node.element_byte_size orelse return error.DescriptorMeasurementInvalid,
                    .element_stride = node.element_stride orelse return error.DescriptorMeasurementInvalid,
                    .element_alignment = node.element_alignment orelse return error.DescriptorMeasurementInvalid,
                    .capacity = node.capacity orelse return error.DescriptorMeasurementInvalid,
                    .accepted_lengths = node.accepted_lengths,
                    .allocation = try convert_allocation_action(node.allocation orelse return error.DescriptorMeasurementInvalid),
                    .free = try convert_free_action(node.free orelse return error.DescriptorMeasurementInvalid),
                } },
                .children = children,
            };
        },
        .record => {
            var fields: []wit_layout.FieldMeasurement = &.{};
            if (node.fields.len != 0) fields = try allocator.alloc(wit_layout.FieldMeasurement, node.fields.len);
            errdefer if (fields.len != 0) allocator.free(fields);
            for (node.fields, 0..) |field, index| {
                fields[index] = .{
                    .name = field.name,
                    .offset = field.offset,
                    .byte_size = field.byte_size,
                    .alignment = field.alignment,
                    .indirect = null,
                };
            }
            return .{
                .layout = .{ .record = .{
                    .byte_size = node.byte_size,
                    .alignment = node.alignment,
                    .fields = fields,
                    .indirect = null,
                } },
                .children = children,
            };
        },
    }
}

fn convert_core_type(value: []const u8) !wit_layout.CoreWord {
    if (std.mem.eql(u8, value, "i32")) return .i32;
    if (std.mem.eql(u8, value, "i64")) return .i64;
    if (std.mem.eql(u8, value, "f32")) return .f32;
    if (std.mem.eql(u8, value, "f64")) return .f64;
    return error.DescriptorMeasurementInvalid;
}

fn convert_allocation_action(value: []const u8) !wit_layout.AllocationAction {
    if (std.mem.eql(u8, value, "none")) return .none;
    if (std.mem.eql(u8, value, "cabi_realloc")) return .cabi_realloc;
    return error.DescriptorMeasurementInvalid;
}

fn convert_free_action(value: []const u8) !wit_layout.FreeAction {
    if (std.mem.eql(u8, value, "none")) return .none;
    if (std.mem.eql(u8, value, "cabi_realloc")) return .cabi_realloc;
    return error.DescriptorMeasurementInvalid;
}

fn deinit_marshal_measured_node(allocator: std.mem.Allocator, node: marshal.MeasuredNode) void {
    for (node.children) |child| deinit_marshal_measured_node(allocator, child);
    if (node.children.len != 0) allocator.free(node.children);
    switch (node.layout) {
        .record => |record| if (record.fields.len != 0) allocator.free(record.fields),
        else => {},
    }
}

fn validate_binding_claims(
    allocator: std.mem.Allocator,
    binding: *const wit_model.BindingModel,
    descriptor: descriptor_manifest.Descriptor,
) !void {
    const package = try format_package(allocator, binding.package);
    defer allocator.free(package);
    if (!std.mem.eql(u8, package, descriptor.package)) return error.PackageMismatch;
    if (!std.mem.eql(u8, binding.world.name, descriptor.world)) return error.WorldMismatch;

    const member = wit_registry.find_value_member(binding, descriptor.interface, descriptor.member) catch |err| switch (err) {
        error.InterfaceNotFound => return error.InterfaceMismatch,
        error.MemberNotFound => return error.MemberMismatch,
        error.UnsupportedMarshalMember => return error.UnsupportedWitShape,
    };
    if (!std.mem.eql(u8, member.interface_name, descriptor.interface)) return error.InterfaceMismatch;
    if (!std.mem.eql(u8, member.member_name, descriptor.member)) return error.MemberMismatch;
    if (member.function.params.len != descriptor.params.len) return error.SignatureMismatch;
    for (member.function.params, descriptor.params) |param, expected| {
        if (!type_matches(allocator, param.type_ref, expected)) return error.SignatureMismatch;
    }
    if (member.function.result) |result| {
        if (!type_matches(allocator, result, descriptor.result)) return error.SignatureMismatch;
    } else if (!std.mem.eql(u8, descriptor.result, "_")) {
        return error.SignatureMismatch;
    }

    const canonical_module = try format_canonical_module(allocator, binding.package, descriptor.interface);
    defer allocator.free(canonical_module);
    if (!std.mem.eql(u8, canonical_module, descriptor.canonical_import.module) or
        !std.mem.eql(u8, descriptor.member, descriptor.canonical_import.name))
    {
        return error.CanonicalImportMismatch;
    }
}

fn find_record(records: []const wit_model.RecordDecl, name: []const u8) ?*const wit_model.RecordDecl {
    for (records) |*record| {
        if (std.mem.eql(u8, record.name, name)) return record;
    }
    return null;
}

fn do_boundary_type(type_ref: *const wit_model.TypeRef) ?[]const u8 {
    return switch (type_ref.kind) {
        .bool => "bool",
        .s8 => "i8",
        .u8 => "u8",
        .s16 => "i16",
        .u16 => "u16",
        .s32 => "i32",
        .u32 => "u32",
        .s64 => "i64",
        .u64 => "u64",
        .f32 => "f32",
        .f64 => "f64",
        .char => "u32",
        .string => "text",
        .list => if (type_ref.args.len == 1 and type_ref.args[0].kind == .u8)
            "[u8]"
        else if (type_ref.args.len == 1 and type_ref.args[0].kind == .u32)
            "[u32]"
        else
            null,
        else => null,
    };
}

fn type_matches(allocator: std.mem.Allocator, type_ref: *const wit_model.TypeRef, expected: []const u8) bool {
    const actual = render_wit_type(allocator, type_ref) catch return false;
    defer allocator.free(actual);
    return std.mem.eql(u8, actual, expected);
}

fn render_wit_type(allocator: std.mem.Allocator, type_ref: *const wit_model.TypeRef) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try append_wit_type(&out, allocator, type_ref);
    return out.toOwnedSlice(allocator);
}

fn append_wit_type(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    type_ref: *const wit_model.TypeRef,
) !void {
    switch (type_ref.kind) {
        .bool => try out.appendSlice(allocator, "bool"),
        .s8 => try out.appendSlice(allocator, "s8"),
        .u8 => try out.appendSlice(allocator, "u8"),
        .s16 => try out.appendSlice(allocator, "s16"),
        .u16 => try out.appendSlice(allocator, "u16"),
        .s32 => try out.appendSlice(allocator, "s32"),
        .u32 => try out.appendSlice(allocator, "u32"),
        .s64 => try out.appendSlice(allocator, "s64"),
        .u64 => try out.appendSlice(allocator, "u64"),
        .f32 => try out.appendSlice(allocator, "f32"),
        .f64 => try out.appendSlice(allocator, "f64"),
        .char => try out.appendSlice(allocator, "char"),
        .string => try out.appendSlice(allocator, "string"),
        .unit => try out.appendSlice(allocator, "_"),
        .named => try out.appendSlice(allocator, type_ref.name),
        .list, .option, .result, .future, .stream, .tuple, .own, .borrow => {
            const name = switch (type_ref.kind) {
                .list => "list",
                .option => "option",
                .result => "result",
                .future => "future",
                .stream => "stream",
                .tuple => "tuple",
                .own => "own",
                .borrow => "borrow",
                else => unreachable,
            };
            if (type_ref.args.len == 0) return error.InvalidSignature;
            try out.appendSlice(allocator, name);
            try out.append(allocator, '<');
            for (type_ref.args, 0..) |arg, index| {
                if (index != 0) try out.appendSlice(allocator, ", ");
                try append_wit_type(out, allocator, arg);
            }
            try out.append(allocator, '>');
        },
    }
}

fn format_package(allocator: std.mem.Allocator, package: wit_model.PackageDecl) ![]u8 {
    const separator: []const u8 = if (package.version.prerelease.len == 0) "" else "-";
    return std.fmt.allocPrint(allocator, "{s}:{s}@{d}.{d}.{d}{s}{s}", .{
        package.namespace,
        package.name,
        package.version.major,
        package.version.minor,
        package.version.patch,
        separator,
        package.version.prerelease,
    });
}

fn format_canonical_module(
    allocator: std.mem.Allocator,
    package: wit_model.PackageDecl,
    interface_name: []const u8,
) ![]u8 {
    const package_text = try format_package(allocator, package);
    defer allocator.free(package_text);
    const at = std.mem.indexOfScalar(u8, package_text, '@') orelse return error.CanonicalImportMismatch;
    return std.fmt.allocPrint(allocator, "{s}/{s}{s}", .{ package_text[0..at], interface_name, package_text[at..] });
}

fn map_plan_error(err: anyerror) anyerror {
    return switch (err) {
        error.UnsupportedMarshalMember,
        error.UnsupportedWitMarshalShape,
        error.UnsupportedMarshalShape,
        error.ResourceBoundaryUnsupported,
        error.UnsupportedMeasuredShape,
        => error.UnsupportedWitShape,
        else => err,
    };
}

fn concatenate_sources(allocator: std.mem.Allocator, source: []const u8, world: []const u8) ![]u8 {
    var out = try allocator.alloc(u8, source.len + 1 + world.len + 1);
    var offset: usize = 0;
    @memcpy(out[offset .. offset + source.len], source);
    offset += source.len;
    out[offset] = '\n';
    offset += 1;
    @memcpy(out[offset .. offset + world.len], world);
    offset += world.len;
    out[offset] = '\n';
    return out;
}

fn verify_source_hash(source: []const u8, expected: []const u8) !void {
    if (expected.len != "sha256:".len + 64 or !std.mem.startsWith(u8, expected, "sha256:")) {
        return error.SourceHashMismatch;
    }
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(source, &digest, .{});
    const digits = "0123456789abcdef";
    for (digest, 0..) |byte, index| {
        if (expected[7 + index * 2] != digits[byte >> 4] or
            expected[7 + index * 2 + 1] != digits[byte & 0x0f]) return error.SourceHashMismatch;
    }
}

fn read_relative(
    io: std.Io,
    allocator: std.mem.Allocator,
    repository_root: []const u8,
    relative_path: []const u8,
) ![]u8 {
    if (!valid_relative_path(relative_path)) return error.SourcePathInvalid;
    const path = try std.fs.path.join(allocator, &.{ repository_root, relative_path });
    defer allocator.free(path);
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(16 * 1024 * 1024));
}

fn valid_relative_path(path: []const u8) bool {
    if (path.len == 0 or path[0] == '/' or std.mem.indexOfScalar(u8, path, '\\') != null) return false;
    var segments = std.mem.splitScalar(u8, path, '/');
    while (segments.next()) |segment| {
        if (segment.len == 0 or std.mem.eql(u8, segment, ".") or std.mem.eql(u8, segment, "..")) return false;
    }
    return true;
}

test "loaded request owns host boundary facts" {
    const descriptor_id = "demo:marshal-record-mixed-text-byte-list-lift/api.read@1.0.0/lift";
    var loaded = try load_request_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        "doc/wit/gc_descriptor_manifest.json",
        descriptor_id,
        null,
    );
    defer loaded.deinit();

    const source = @embedFile("test/compile_ok/648_gc_wit_mixed_text_byte_list_lift_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try validate_loaded_host_boundary(&loaded, tokens);
}

test "loaded request admits the two u32 list lower host boundary" {
    var loaded = try load_request_from_manifest(
        std.testing.io,
        std.testing.allocator,
        "..",
        "doc/wit/gc_descriptor_manifest.json",
        "demo:marshal-record-two-u32-lists-lower/api.write@1.0.0/lower",
        null,
    );
    defer loaded.deinit();

    const root = loaded.plan.root.measured orelse unreachable;
    try std.testing.expectEqual(@as(u32, 20), root.byte_size);
    try std.testing.expectEqual(@as(u32, 4), root.alignment);
    try std.testing.expectEqual(@as(usize, 3), loaded.plan.root.children.len);
    try std.testing.expectEqual(@as(u32, 0), loaded.plan.root.children[0].measured.?.offset);
    try std.testing.expectEqual(@as(u32, 4), loaded.plan.root.children[1].measured.?.offset);
    try std.testing.expectEqual(@as(u32, 12), loaded.plan.root.children[2].measured.?.offset);
    try std.testing.expectEqual(@as(u32, 3), loaded.plan.root.children[1].measured.?.capacity.?);
    try std.testing.expectEqual(@as(u32, 2), loaded.plan.root.children[2].measured.?.capacity.?);
    try std.testing.expectEqual(@as(u32, 4), loaded.plan.root.children[1].measured.?.element_stride.?);
    try std.testing.expectEqual(@as(u32, 4), loaded.plan.root.children[2].measured.?.element_stride.?);

    const source = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "../examples/gc-p3-runtime/ordinary-host-record-two-u32-lists-lower-call.do",
        std.testing.allocator,
        .limited(1024 * 1024),
    );
    defer std.testing.allocator.free(source);
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try validate_loaded_host_boundary(&loaded, tokens);
}

test "source hash verification rejects the two-list descriptor on drift" {
    try std.testing.expectError(
        error.SourceHashMismatch,
        verify_source_hash(
            "package demo:drift@1.0.0;",
            "sha256:0000000000000000000000000000000000000000000000000000000000000000",
        ),
    );
}
