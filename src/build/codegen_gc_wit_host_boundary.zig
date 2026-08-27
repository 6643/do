//! Source-level admission for private manifest-backed GC/WIT host boundaries.
const std = @import("std");
const lexer = @import("lexer.zig");
const codegen_tokens = @import("codegen_tokens.zig");

const find_matching_in_range = codegen_tokens.find_matching_in_range;
const is_line_start = codegen_tokens.is_line_start;
const string_token_body = codegen_tokens.string_token_body;
const tok_eq = codegen_tokens.tok_eq;

pub const managed_record_lower_multi_descriptor =
    "demo:marshal-record-managed-lower-multi/api.write@1.0.0/lower";
pub const record_byte_list_lower_descriptor =
    "demo:marshal-record-byte-list-lower/api.write@1.0.0/lower";
pub const record_u32_list_lower_descriptor =
    "demo:marshal-record-u32-list-lower/api.write@1.0.0/lower";
pub const record_two_u32_lists_lower_descriptor =
    "demo:marshal-record-two-u32-lists-lower/api.write@1.0.0/lower";
pub const record_u32_list_lift_descriptor =
    "demo:marshal-record-u32-list-lift/api.read@1.0.0/lift";
pub const record_byte_list_lift_descriptor =
    "demo:marshal-record-byte-list-lift/api.read@1.0.0/lift";
pub const managed_record_lower_descriptor =
    "demo:marshal-record-managed-lower/api.write@1.0.0/lower";
pub const managed_record_lift_descriptor =
    "demo:marshal-record-managed-lift/api.read@1.0.0/lift";
pub const managed_record_lift_multi_descriptor =
    "demo:marshal-record-managed-lift-multi/api.read@1.0.0/lift";
pub const mixed_record_lower_descriptor =
    "demo:marshal-record-mixed-lower/api.write@1.0.0/lower";
pub const mixed_scalar_list_lower_descriptor =
    "demo:marshal-record-mixed-scalar-list-lower/api.write@1.0.0/lower";
pub const mixed_text_u32_list_lower_descriptor =
    "demo:marshal-record-mixed-text-u32-list-lower/api.write@1.0.0/lower";
pub const mixed_text_two_u32_lists_lower_descriptor =
    "demo:marshal-record-mixed-text-two-u32-lists-lower/api.write@1.0.0/lower";
pub const mixed_text_byte_u32_lists_lower_descriptor =
    "demo:marshal-record-mixed-text-byte-u32-lists-lower/api.write@1.0.0/lower";
pub const mixed_text_u32_list_lift_descriptor =
    "demo:marshal-record-mixed-text-u32-list-lift/api.read@1.0.0/lift";
pub const mixed_text_byte_list_lift_descriptor =
    "demo:marshal-record-mixed-text-byte-list-lift/api.read@1.0.0/lift";
pub const mixed_text_two_u32_lists_lift_descriptor =
    "demo:marshal-record-mixed-text-two-u32-lists-lift/api.read@1.0.0/lift";
pub const nested_record_lift_deeper_descriptor =
    "demo:marshal-record-nested-lift-deeper/api.read@1.0.0/lift";
pub const nested_record_lower_deeper_descriptor =
    "demo:marshal-record-nested-lower-deeper/api.write@1.0.0/lower";

const AdmissionEntry = struct {
    locator: []const u8,
    member: []const u8,
    descriptor_id: []const u8,
    explicit_probe: bool = false,
};

const ADMITTED_DESCRIPTORS = [_]AdmissionEntry{
    .{ .locator = "demo:marshal-record-byte-list-lower/api@1.0.0", .member = "write", .descriptor_id = record_byte_list_lower_descriptor, .explicit_probe = true },
    .{ .locator = "demo:marshal-record-u32-list-lower/api@1.0.0", .member = "write", .descriptor_id = record_u32_list_lower_descriptor, .explicit_probe = true },
    .{ .locator = "demo:marshal-record-two-u32-lists-lower/api@1.0.0", .member = "write", .descriptor_id = record_two_u32_lists_lower_descriptor, .explicit_probe = true },
    .{ .locator = "demo:marshal-record-u32-list-lift/api@1.0.0", .member = "read", .descriptor_id = record_u32_list_lift_descriptor, .explicit_probe = true },
    .{ .locator = "demo:marshal-record-byte-list-lift/api@1.0.0", .member = "read", .descriptor_id = record_byte_list_lift_descriptor, .explicit_probe = true },
    .{ .locator = "demo:marshal-record-managed-lower/api@1.0.0", .member = "write", .descriptor_id = managed_record_lower_descriptor, .explicit_probe = true },
    .{ .locator = "demo:marshal-record-managed-lift/api@1.0.0", .member = "read", .descriptor_id = managed_record_lift_descriptor, .explicit_probe = true },
    .{ .locator = "demo:marshal-record-managed-lower-multi/api@1.0.0", .member = "write", .descriptor_id = managed_record_lower_multi_descriptor, .explicit_probe = true },
    .{ .locator = "demo:marshal-record-managed-lift-multi/api@1.0.0", .member = "read", .descriptor_id = managed_record_lift_multi_descriptor, .explicit_probe = true },
    .{ .locator = "demo:marshal-record-mixed-lower/api@1.0.0", .member = "write", .descriptor_id = mixed_record_lower_descriptor },
    .{ .locator = "demo:marshal-record-mixed-scalar-list-lower/api@1.0.0", .member = "write", .descriptor_id = mixed_scalar_list_lower_descriptor, .explicit_probe = true },
    .{ .locator = "demo:marshal-record-mixed-text-u32-list-lower/api@1.0.0", .member = "write", .descriptor_id = mixed_text_u32_list_lower_descriptor },
    .{ .locator = "demo:marshal-record-mixed-text-two-u32-lists-lower/api@1.0.0", .member = "write", .descriptor_id = mixed_text_two_u32_lists_lower_descriptor },
    .{ .locator = "demo:marshal-record-mixed-text-byte-u32-lists-lower/api@1.0.0", .member = "write", .descriptor_id = mixed_text_byte_u32_lists_lower_descriptor },
    .{ .locator = "demo:marshal-record-mixed-text-u32-list-lift/api@1.0.0", .member = "read", .descriptor_id = mixed_text_u32_list_lift_descriptor, .explicit_probe = true },
    .{ .locator = "demo:marshal-record-mixed-text-byte-list-lift/api@1.0.0", .member = "read", .descriptor_id = mixed_text_byte_list_lift_descriptor, .explicit_probe = true },
    .{ .locator = "demo:marshal-record-mixed-text-two-u32-lists-lift/api@1.0.0", .member = "read", .descriptor_id = mixed_text_two_u32_lists_lift_descriptor, .explicit_probe = true },
    .{ .locator = "demo:marshal-record-nested-lower-deeper/api@1.0.0", .member = "write", .descriptor_id = nested_record_lower_deeper_descriptor, .explicit_probe = true },
    .{ .locator = "demo:marshal-record-nested-lift-deeper/api@1.0.0", .member = "read", .descriptor_id = nested_record_lift_deeper_descriptor, .explicit_probe = true },
};

pub fn descriptor_id_for_host(locator: []const u8, member: []const u8) ?[]const u8 {
    for (ADMITTED_DESCRIPTORS) |entry| {
        if (std.mem.eql(u8, entry.locator, locator) and std.mem.eql(u8, entry.member, member)) {
            return entry.descriptor_id;
        }
    }
    return null;
}

pub fn is_admitted_host_locator(locator: []const u8) bool {
    for (ADMITTED_DESCRIPTORS) |entry| {
        if (std.mem.eql(u8, entry.locator, locator)) return true;
    }
    return false;
}

pub fn is_admitted_descriptor(descriptor_id: []const u8) bool {
    for (ADMITTED_DESCRIPTORS) |entry| {
        if (entry.explicit_probe and std.mem.eql(u8, entry.descriptor_id, descriptor_id)) return true;
    }
    return false;
}

/// A field is either a scalar/text Do type (`nested_fields == null`) or a
/// named nested record whose fields are checked recursively. The optional
/// slice keeps the existing flat descriptor literals source-compatible.
pub const HostBoundaryField = struct {
    name: []const u8,
    ty: []const u8,
    nested_fields: ?[]const HostBoundaryField = null,
};

pub const HostBoundaryShape = enum { lower_record, lift_record };

pub const HostBoundarySpec = struct {
    locator: []const u8,
    member: []const u8,
    record_name: []const u8,
    fields: []const HostBoundaryField,
    shape: HostBoundaryShape,
};

/// Owned form used by a manifest-loaded request. WIT model names may belong to
/// a temporary resolver binding, so a request must not retain those borrowed
/// slices after the binding is deinitialized.
pub const OwnedHostBoundarySpec = struct {
    allocator: std.mem.Allocator,
    locator: []u8,
    member: []u8,
    record_name: []u8,
    fields: []HostBoundaryField,
    shape: HostBoundaryShape,

    pub fn from_spec(allocator: std.mem.Allocator, spec: HostBoundarySpec) !OwnedHostBoundarySpec {
        const locator = try allocator.dupe(u8, spec.locator);
        errdefer allocator.free(locator);
        const member = try allocator.dupe(u8, spec.member);
        errdefer allocator.free(member);
        const record_name = try allocator.dupe(u8, spec.record_name);
        errdefer allocator.free(record_name);
        const fields = try duplicate_fields(allocator, spec.fields);
        return .{
            .allocator = allocator,
            .locator = locator,
            .member = member,
            .record_name = record_name,
            .fields = fields,
            .shape = spec.shape,
        };
    }

    pub fn as_spec(self: *const OwnedHostBoundarySpec) HostBoundarySpec {
        return .{
            .locator = self.locator,
            .member = self.member,
            .record_name = self.record_name,
            .fields = self.fields,
            .shape = self.shape,
        };
    }

    pub fn deinit(self: *OwnedHostBoundarySpec) void {
        free_owned_fields(self.allocator, self.fields);
        self.allocator.free(self.locator);
        self.allocator.free(self.member);
        self.allocator.free(self.record_name);
        self.* = undefined;
    }
};

fn duplicate_fields(allocator: std.mem.Allocator, source: []const HostBoundaryField) std.mem.Allocator.Error![]HostBoundaryField {
    if (source.len == 0) return &.{};
    const fields = try allocator.alloc(HostBoundaryField, source.len);
    var initialized: usize = 0;
    errdefer {
        free_owned_fields(allocator, fields[0..initialized]);
        allocator.free(fields);
    }
    for (source, 0..) |field, index| {
        fields[index] = try duplicate_field(allocator, field);
        initialized += 1;
    }
    return fields;
}

fn duplicate_field(allocator: std.mem.Allocator, field: HostBoundaryField) std.mem.Allocator.Error!HostBoundaryField {
    const name = try allocator.dupe(u8, field.name);
    errdefer allocator.free(name);
    const ty = try allocator.dupe(u8, field.ty);
    errdefer allocator.free(ty);
    const nested_fields = if (field.nested_fields) |nested| try duplicate_fields(allocator, nested) else null;
    errdefer if (nested_fields) |nested| free_owned_fields(allocator, nested);
    return .{
        .name = name,
        .ty = ty,
        .nested_fields = nested_fields,
    };
}

fn free_owned_fields(allocator: std.mem.Allocator, fields: []const HostBoundaryField) void {
    for (fields) |field| {
        if (field.nested_fields) |nested| free_owned_fields(allocator, nested);
        allocator.free(field.name);
        allocator.free(field.ty);
    }
    if (fields.len != 0) allocator.free(@constCast(fields));
}

const ExpectedField = HostBoundaryField;
const HostShape = HostBoundaryShape;
const DescriptorSpec = HostBoundarySpec;

const MANAGED_RECORD_LOWER_FIELDS = [_]HostBoundaryField{
    .{ .name = "code", .ty = "u32" },
    .{ .name = "label", .ty = "text" },
};

const RECORD_BYTE_LIST_LOWER_FIELDS = [_]HostBoundaryField{
    .{ .name = "code", .ty = "u32" },
    .{ .name = "payload", .ty = "[u8]" },
};

const RECORD_U32_LIST_LOWER_FIELDS = [_]HostBoundaryField{
    .{ .name = "code", .ty = "u32" },
    .{ .name = "payload", .ty = "[u32]" },
};

const RECORD_TWO_U32_LISTS_LOWER_FIELDS = [_]HostBoundaryField{
    .{ .name = "code", .ty = "u32" },
    .{ .name = "first", .ty = "[u32]" },
    .{ .name = "second", .ty = "[u32]" },
};

const RECORD_U32_LIST_LIFT_FIELDS = [_]HostBoundaryField{
    .{ .name = "code", .ty = "u32" },
    .{ .name = "payload", .ty = "[u32]" },
};

const RECORD_BYTE_LIST_LIFT_FIELDS = [_]HostBoundaryField{
    .{ .name = "code", .ty = "u32" },
    .{ .name = "payload", .ty = "[u8]" },
};

const MANAGED_RECORD_LOWER_MULTI_FIELDS = [_]ExpectedField{
    .{ .name = "code", .ty = "u32" },
    .{ .name = "label", .ty = "text" },
    .{ .name = "note", .ty = "text" },
};

const MIXED_RECORD_LOWER_FIELDS = [_]ExpectedField{
    .{ .name = "code", .ty = "u32" },
    .{ .name = "count", .ty = "u64" },
    .{ .name = "status", .ty = "i64" },
};

const MIXED_SCALAR_LIST_LOWER_FIELDS = [_]ExpectedField{
    .{ .name = "code", .ty = "u32" },
    .{ .name = "label", .ty = "text" },
    .{ .name = "payload", .ty = "[u8]" },
};

const MIXED_TEXT_U32_LIST_LOWER_FIELDS = [_]ExpectedField{
    .{ .name = "code", .ty = "u32" },
    .{ .name = "label", .ty = "text" },
    .{ .name = "payload", .ty = "[u32]" },
};

const MIXED_TEXT_TWO_U32_LISTS_LOWER_FIELDS = [_]ExpectedField{
    .{ .name = "code", .ty = "u32" },
    .{ .name = "label", .ty = "text" },
    .{ .name = "first", .ty = "[u32]" },
    .{ .name = "second", .ty = "[u32]" },
};

const MIXED_TEXT_BYTE_U32_LISTS_LOWER_FIELDS = [_]ExpectedField{
    .{ .name = "code", .ty = "u32" },
    .{ .name = "label", .ty = "text" },
    .{ .name = "bytes", .ty = "[u8]" },
    .{ .name = "values", .ty = "[u32]" },
};

const MIXED_TEXT_U32_LIST_LIFT_FIELDS = [_]ExpectedField{
    .{ .name = "code", .ty = "u32" },
    .{ .name = "label", .ty = "text" },
    .{ .name = "payload", .ty = "[u32]" },
};

const MIXED_TEXT_BYTE_LIST_LIFT_FIELDS = [_]ExpectedField{
    .{ .name = "code", .ty = "u32" },
    .{ .name = "label", .ty = "text" },
    .{ .name = "payload", .ty = "[u8]" },
};

const MIXED_TEXT_TWO_U32_LISTS_LIFT_FIELDS = [_]ExpectedField{
    .{ .name = "code", .ty = "u32" },
    .{ .name = "label", .ty = "text" },
    .{ .name = "first", .ty = "[u32]" },
    .{ .name = "second", .ty = "[u32]" },
};

// Compatibility descriptors retained only for standalone boundary tests and
// probe adapters. The real compiler route derives its spec from manifest/WIT.
const MANAGED_RECORD_LOWER_SPEC = DescriptorSpec{
    .locator = "demo:marshal-record-managed-lower/api@1.0.0",
    .member = "write",
    .record_name = "Writing",
    .fields = MANAGED_RECORD_LOWER_FIELDS[0..],
    .shape = .lower_record,
};

const RECORD_BYTE_LIST_LOWER_SPEC = DescriptorSpec{
    .locator = "demo:marshal-record-byte-list-lower/api@1.0.0",
    .member = "write",
    .record_name = "Writing",
    .fields = RECORD_BYTE_LIST_LOWER_FIELDS[0..],
    .shape = .lower_record,
};

const RECORD_U32_LIST_LOWER_SPEC = DescriptorSpec{
    .locator = "demo:marshal-record-u32-list-lower/api@1.0.0",
    .member = "write",
    .record_name = "Writing",
    .fields = RECORD_U32_LIST_LOWER_FIELDS[0..],
    .shape = .lower_record,
};

const RECORD_TWO_U32_LISTS_LOWER_SPEC = DescriptorSpec{
    .locator = "demo:marshal-record-two-u32-lists-lower/api@1.0.0",
    .member = "write",
    .record_name = "Writing",
    .fields = RECORD_TWO_U32_LISTS_LOWER_FIELDS[0..],
    .shape = .lower_record,
};

const RECORD_U32_LIST_LIFT_SPEC = DescriptorSpec{
    .locator = "demo:marshal-record-u32-list-lift/api@1.0.0",
    .member = "read",
    .record_name = "Reading",
    .fields = RECORD_U32_LIST_LIFT_FIELDS[0..],
    .shape = .lift_record,
};

const RECORD_BYTE_LIST_LIFT_SPEC = DescriptorSpec{
    .locator = "demo:marshal-record-byte-list-lift/api@1.0.0",
    .member = "read",
    .record_name = "Reading",
    .fields = RECORD_BYTE_LIST_LIFT_FIELDS[0..],
    .shape = .lift_record,
};

const MANAGED_RECORD_LOWER_MULTI_SPEC = DescriptorSpec{
    .locator = "demo:marshal-record-managed-lower-multi/api@1.0.0",
    .member = "write",
    .record_name = "Writing",
    .fields = MANAGED_RECORD_LOWER_MULTI_FIELDS[0..],
    .shape = .lower_record,
};

const MIXED_RECORD_LOWER_SPEC = DescriptorSpec{
    .locator = "demo:marshal-record-mixed-lower/api@1.0.0",
    .member = "write",
    .record_name = "Writing",
    .fields = MIXED_RECORD_LOWER_FIELDS[0..],
    .shape = .lower_record,
};

const MIXED_SCALAR_LIST_LOWER_SPEC = DescriptorSpec{
    .locator = "demo:marshal-record-mixed-scalar-list-lower/api@1.0.0",
    .member = "write",
    .record_name = "Writing",
    .fields = MIXED_SCALAR_LIST_LOWER_FIELDS[0..],
    .shape = .lower_record,
};

const MIXED_TEXT_U32_LIST_LOWER_SPEC = DescriptorSpec{
    .locator = "demo:marshal-record-mixed-text-u32-list-lower/api@1.0.0",
    .member = "write",
    .record_name = "Writing",
    .fields = MIXED_TEXT_U32_LIST_LOWER_FIELDS[0..],
    .shape = .lower_record,
};

const MIXED_TEXT_TWO_U32_LISTS_LOWER_SPEC = DescriptorSpec{
    .locator = "demo:marshal-record-mixed-text-two-u32-lists-lower/api@1.0.0",
    .member = "write",
    .record_name = "Writing",
    .fields = MIXED_TEXT_TWO_U32_LISTS_LOWER_FIELDS[0..],
    .shape = .lower_record,
};

const MIXED_TEXT_BYTE_U32_LISTS_LOWER_SPEC = DescriptorSpec{
    .locator = "demo:marshal-record-mixed-text-byte-u32-lists-lower/api@1.0.0",
    .member = "write",
    .record_name = "Writing",
    .fields = MIXED_TEXT_BYTE_U32_LISTS_LOWER_FIELDS[0..],
    .shape = .lower_record,
};

const MIXED_TEXT_U32_LIST_LIFT_SPEC = DescriptorSpec{
    .locator = "demo:marshal-record-mixed-text-u32-list-lift/api@1.0.0",
    .member = "read",
    .record_name = "Reading",
    .fields = MIXED_TEXT_U32_LIST_LIFT_FIELDS[0..],
    .shape = .lift_record,
};

const MIXED_TEXT_BYTE_LIST_LIFT_SPEC = DescriptorSpec{
    .locator = "demo:marshal-record-mixed-text-byte-list-lift/api@1.0.0",
    .member = "read",
    .record_name = "Reading",
    .fields = MIXED_TEXT_BYTE_LIST_LIFT_FIELDS[0..],
    .shape = .lift_record,
};

const MIXED_TEXT_TWO_U32_LISTS_LIFT_SPEC = DescriptorSpec{
    .locator = "demo:marshal-record-mixed-text-two-u32-lists-lift/api@1.0.0",
    .member = "read",
    .record_name = "Reading",
    .fields = MIXED_TEXT_TWO_U32_LISTS_LIFT_FIELDS[0..],
    .shape = .lift_record,
};

const MANAGED_RECORD_LIFT_SPEC = DescriptorSpec{
    .locator = "demo:marshal-record-managed-lift/api@1.0.0",
    .member = "read",
    .record_name = "Reading",
    .fields = MANAGED_RECORD_LOWER_FIELDS[0..],
    .shape = .lift_record,
};

const MANAGED_RECORD_LIFT_MULTI_SPEC = DescriptorSpec{
    .locator = "demo:marshal-record-managed-lift-multi/api@1.0.0",
    .member = "read",
    .record_name = "Reading",
    .fields = MANAGED_RECORD_LOWER_MULTI_FIELDS[0..],
    .shape = .lift_record,
};

fn descriptor_spec(descriptor_id: []const u8) ?DescriptorSpec {
    if (std.mem.eql(u8, descriptor_id, record_byte_list_lower_descriptor)) return RECORD_BYTE_LIST_LOWER_SPEC;
    if (std.mem.eql(u8, descriptor_id, record_u32_list_lower_descriptor)) return RECORD_U32_LIST_LOWER_SPEC;
    if (std.mem.eql(u8, descriptor_id, record_two_u32_lists_lower_descriptor)) return RECORD_TWO_U32_LISTS_LOWER_SPEC;
    if (std.mem.eql(u8, descriptor_id, record_u32_list_lift_descriptor)) return RECORD_U32_LIST_LIFT_SPEC;
    if (std.mem.eql(u8, descriptor_id, record_byte_list_lift_descriptor)) return RECORD_BYTE_LIST_LIFT_SPEC;
    if (std.mem.eql(u8, descriptor_id, managed_record_lower_descriptor)) return MANAGED_RECORD_LOWER_SPEC;
    if (std.mem.eql(u8, descriptor_id, managed_record_lower_multi_descriptor)) return MANAGED_RECORD_LOWER_MULTI_SPEC;
    if (std.mem.eql(u8, descriptor_id, mixed_record_lower_descriptor)) return MIXED_RECORD_LOWER_SPEC;
    if (std.mem.eql(u8, descriptor_id, mixed_scalar_list_lower_descriptor)) return MIXED_SCALAR_LIST_LOWER_SPEC;
    if (std.mem.eql(u8, descriptor_id, mixed_text_u32_list_lower_descriptor)) return MIXED_TEXT_U32_LIST_LOWER_SPEC;
    if (std.mem.eql(u8, descriptor_id, mixed_text_two_u32_lists_lower_descriptor)) return MIXED_TEXT_TWO_U32_LISTS_LOWER_SPEC;
    if (std.mem.eql(u8, descriptor_id, mixed_text_byte_u32_lists_lower_descriptor)) return MIXED_TEXT_BYTE_U32_LISTS_LOWER_SPEC;
    if (std.mem.eql(u8, descriptor_id, mixed_text_u32_list_lift_descriptor)) return MIXED_TEXT_U32_LIST_LIFT_SPEC;
    if (std.mem.eql(u8, descriptor_id, mixed_text_byte_list_lift_descriptor)) return MIXED_TEXT_BYTE_LIST_LIFT_SPEC;
    if (std.mem.eql(u8, descriptor_id, mixed_text_two_u32_lists_lift_descriptor)) return MIXED_TEXT_TWO_U32_LISTS_LIFT_SPEC;
    if (std.mem.eql(u8, descriptor_id, managed_record_lift_descriptor)) return MANAGED_RECORD_LIFT_SPEC;
    if (std.mem.eql(u8, descriptor_id, managed_record_lift_multi_descriptor)) return MANAGED_RECORD_LIFT_MULTI_SPEC;
    return null;
}

pub fn validate(tokens: []const lexer.Token, descriptor_id: []const u8) !void {
    const spec = descriptor_spec(descriptor_id) orelse return error.UnsupportedGcWitHostDescriptor;
    return validate_with_spec(tokens, spec);
}

pub fn validate_with_spec(tokens: []const lexer.Token, spec: HostBoundarySpec) !void {
    const fixed_record = if (spec.record_name.len == 0) null else find_record(tokens, spec.record_name);
    if (spec.record_name.len != 0 and fixed_record == null) return error.GcWitHostRecordMismatch;
    var host_count: usize = 0;
    var target_seen = false;
    var unrelated_seen = false;
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0 or !tok_eq(tokens[i], "@")) continue;
        if (i + 2 >= tokens.len or tokens[i + 1].kind != .ident) continue;
        const marker = tokens[i + 1].lexeme;
        if (!std.mem.eql(u8, marker, "host_func") and !std.mem.eql(u8, marker, "host_async_func")) continue;

        host_count += 1;
        const host = parse_host(tokens, i) catch return error.GcWitHostSignatureMismatch;
        const is_target_member = std.mem.eql(u8, host.member, spec.member);
        const is_target_locator = std.mem.eql(u8, host.locator, spec.locator);
        if (is_target_member and !is_target_locator) {
            return error.GcWitHostLocatorMismatch;
        }
        if (!is_target_member and is_target_locator) {
            return error.GcWitHostMemberMismatch;
        }
        if (!is_target_member and !is_target_locator) {
            unrelated_seen = true;
            if (target_seen or host_count > 1) return error.GcWitHostExtraDeclaration;
            continue;
        }
        if (target_seen) return error.DuplicateGcWitHostDeclaration;
        target_seen = true;
        if (host.async_marker) return error.AsyncGcWitHostDeclaration;
        if (!std.mem.eql(u8, host.locator, spec.locator)) {
            return error.GcWitHostLocatorMismatch;
        }
        if (!std.mem.eql(u8, host.member, spec.member)) return error.GcWitHostMemberMismatch;
        const record = fixed_record orelse
            (find_record_for_host(tokens, host, spec.shape) orelse return error.GcWitHostRecordMismatch);
        try validate_target_signature(tokens, host, record, spec);
        i = host.close_idx;
    }

    if (!target_seen) {
        if (unrelated_seen) return error.GcWitHostExtraDeclaration;
        if (host_count == 0) return error.MissingGcWitHostDeclaration;
        return error.GcWitHostSignatureMismatch;
    }
    if (host_count != 1) return error.GcWitHostExtraDeclaration;
}

fn find_record_for_host(tokens: []const lexer.Token, host: HostDecl, shape: HostShape) ?RecordRange {
    const record_name = switch (shape) {
        .lower_record => if (host.params_close == host.params_open + 2 and tokens[host.params_open + 1].kind == .ident)
            tokens[host.params_open + 1].lexeme
        else
            return null,
        .lift_record => if (host.result_idx < tokens.len and tokens[host.result_idx].kind == .ident)
            tokens[host.result_idx].lexeme
        else
            return null,
    };
    return find_record(tokens, record_name);
}

const RecordRange = struct { open_idx: usize, close_idx: usize };

const HostDecl = struct {
    locator: []const u8,
    member: []const u8,
    async_marker: bool,
    params_open: usize,
    params_close: usize,
    result_idx: usize,
    close_idx: usize,
};

fn find_record(tokens: []const lexer.Token, record_name: []const u8) ?RecordRange {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0 or !is_line_start(tokens, i) or tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, tokens[i].lexeme, record_name) or !tok_eq(tokens[i + 1], "{")) continue;
        const close_idx = find_matching_in_range(tokens, i + 1, "{", "}", tokens.len) catch return null;
        return .{ .open_idx = i + 1, .close_idx = close_idx };
    }
    return null;
}

fn parse_host(tokens: []const lexer.Token, at_idx: usize) !HostDecl {
    if (at_idx + 7 >= tokens.len or !tok_eq(tokens[at_idx + 2], "(")) return error.InvalidGcWitHostBoundary;
    const outer_close = try find_matching_in_range(tokens, at_idx + 2, "(", ")", tokens.len);
    if (tokens[at_idx + 3].kind != .string or !tok_eq(tokens[at_idx + 4], ",") or
        tokens[at_idx + 5].kind != .string or !tok_eq(tokens[at_idx + 6], ",")) return error.InvalidGcWitHostBoundary;
    const sig_open = at_idx + 7;
    if (!tok_eq(tokens[sig_open], "(")) return error.InvalidGcWitHostBoundary;
    const params_close = try find_matching_in_range(tokens, sig_open, "(", ")", outer_close);
    if (params_close + 4 != outer_close or !tok_eq(tokens[params_close + 1], "-") or
        !tok_eq(tokens[params_close + 2], ">")) return error.InvalidGcWitHostBoundary;
    return .{
        .locator = string_token_body(tokens[at_idx + 3].lexeme) orelse return error.InvalidGcWitHostBoundary,
        .member = string_token_body(tokens[at_idx + 5].lexeme) orelse return error.InvalidGcWitHostBoundary,
        .async_marker = std.mem.eql(u8, tokens[at_idx + 1].lexeme, "host_async_func"),
        .params_open = sig_open,
        .params_close = params_close,
        .result_idx = params_close + 3,
        .close_idx = outer_close,
    };
}

fn validate_target_signature(tokens: []const lexer.Token, host: HostDecl, record: RecordRange, spec: DescriptorSpec) !void {
    const param_count = if (host.params_close == host.params_open + 1)
        0
    else
        1 + count_top_level_commas(tokens, host.params_open + 1, host.params_close);
    switch (spec.shape) {
        .lower_record => {
            if (host.result_idx >= tokens.len or tokens[host.result_idx].kind != .ident or
                !tok_eq(tokens[host.result_idx], "nil")) return error.GcWitHostSignatureMismatch;
            if (param_count != 1) return error.GcWitHostSignatureMismatch;
            if (spec.record_name.len != 0 and
                (tokens[host.params_open + 1].kind != .ident or
                 !tok_eq(tokens[host.params_open + 1], spec.record_name)))
            {
                return error.GcWitHostRecordMismatch;
            }
        },
        .lift_record => {
            if (param_count != 0) return error.GcWitHostSignatureMismatch;
            if (host.result_idx >= tokens.len or tokens[host.result_idx].kind != .ident or
                (spec.record_name.len != 0 and !tok_eq(tokens[host.result_idx], spec.record_name)))
                return error.GcWitHostRecordMismatch;
        },
    }
    if (!record_matches(tokens, record, spec.fields)) return error.GcWitHostRecordMismatch;
}

fn count_top_level_commas(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    var count: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "<")) depth_angle += 1;
        if (tok_eq(tokens[i], ">") and depth_angle > 0) depth_angle -= 1;
        if (depth_angle == 0 and tok_eq(tokens[i], ",")) count += 1;
    }
    return count;
}

fn record_matches(tokens: []const lexer.Token, record: RecordRange, expected_fields: []const ExpectedField) bool {
    var field_idx: usize = 0;
    var i = record.open_idx + 1;
    while (i < record.close_idx) {
        if (is_line_start(tokens, i) and tok_eq(tokens[i], "}")) break;
        if (tokens[i].kind != .ident or field_idx >= expected_fields.len) return false;
        const expected = expected_fields[field_idx];
        if (!std.mem.eql(u8, tokens[i].lexeme, expected.name)) return false;
        if (expected.nested_fields) |nested_fields| {
            if (i + 1 >= record.close_idx or tokens[i + 1].kind != .ident) return false;
            const nested_record = find_record(tokens, tokens[i + 1].lexeme) orelse return false;
            if (!record_matches(tokens, nested_record, nested_fields)) return false;
            const line = tokens[i].line;
            i += 2;
            while (i < record.close_idx and tokens[i].line == line) : (i += 1) {}
            field_idx += 1;
            continue;
        }
        const type_end = match_do_field_type(tokens, i + 1, record.close_idx, expected.ty) orelse return false;
        const line = tokens[i].line;
        i = type_end;
        while (i < record.close_idx and tokens[i].line == line) : (i += 1) {}
        field_idx += 1;
    }
    return field_idx == expected_fields.len and i == record.close_idx;
}

/// Match only the Do field spellings admitted by a manifest-backed boundary.
/// Primitive fields occupy one identifier token; bounded list descriptors
/// additionally admit exactly `[u8]` or `[u32]`.
fn match_do_field_type(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    expected: []const u8,
) ?usize {
    if (std.mem.eql(u8, expected, "[u8]") or std.mem.eql(u8, expected, "[u32]")) {
        const element = if (std.mem.eql(u8, expected, "[u8]")) "u8" else "u32";
        if (start_idx + 2 >= end_idx or
            !tok_eq(tokens[start_idx], "[") or
            tokens[start_idx + 1].kind != .ident or
            !tok_eq(tokens[start_idx + 1], element) or
            !tok_eq(tokens[start_idx + 2], "]")) return null;
        return start_idx + 3;
    }
    if (start_idx >= end_idx or tokens[start_idx].kind != .ident) return null;
    if (!tok_eq(tokens[start_idx], expected)) return null;
    return start_idx + 1;
}

fn expect_error(source: []const u8, expected: anyerror) !void {
    try expect_error_for_descriptor(source, managed_record_lower_multi_descriptor, expected);
}

fn expect_error_for_descriptor(source: []const u8, descriptor_id: []const u8, expected: anyerror) !void {
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectError(expected, validate(tokens, descriptor_id));
}

const positive_source = @embedFile("test/compile_ok/564_gc_wit_managed_record_host_boundary.do");

test "GC WIT host boundary accepts the C15-B managed record declaration" {
    const source = @embedFile("test/compile_ok/565_gc_wit_managed_record_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try validate(tokens, "demo:marshal-record-managed-lower/api.write@1.0.0/lower");
}

test "generic host boundary validates a manifest-derived shape without descriptor id" {
    const fields = [_]ExpectedField{
        .{ .name = "code", .ty = "u32" },
        .{ .name = "label", .ty = "text" },
    };
    const spec = HostBoundarySpec{
        .locator = "demo:synthetic/api@1.0.0",
        .member = "write",
        .record_name = "LocalWriting",
        .fields = fields[0..],
        .shape = .lower_record,
    };
    const source =
                \\LocalWriting {
        \\    code u32
        \\    label text
        \\}
        \\write = @host_func("demo:synthetic/api@1.0.0", "write", (LocalWriting) -> nil)
        ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try validate_with_spec(tokens, spec);
}

test "C16-C managed record lift declaration is accepted" {
    const source = @embedFile("test/compile_ok/566_gc_wit_managed_record_lift_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try validate(tokens, "demo:marshal-record-managed-lift/api.read@1.0.0/lift");
}

test "C16-D managed multi-record lift declaration is accepted" {
    const source = @embedFile("test/compile_ok/581_gc_wit_managed_record_lift_multi_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try validate(tokens, "demo:marshal-record-managed-lift-multi/api.read@1.0.0/lift");
}

test "mixed scalar lower declaration is accepted" {
    const source = @embedFile("test/compile_ok/591_gc_wit_mixed_record_lower_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try validate(tokens, mixed_record_lower_descriptor);
}

test "mixed scalar-list lower declaration is accepted" {
    const source = @embedFile("test/compile_ok/622_gc_wit_mixed_scalar_list_lower_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try validate(tokens, mixed_scalar_list_lower_descriptor);
}

test "two u32-list lower declaration is accepted" {
    const source = @embedFile("test/compile_ok/657_gc_wit_two_u32_lists_lower_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try validate(tokens, "demo:marshal-record-two-u32-lists-lower/api.write@1.0.0/lower");
}

test "mixed text and two u32-list lower declaration is accepted" {
    const source = @embedFile("test/compile_ok/665_gc_wit_mixed_text_two_u32_lists_lower_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try validate(tokens, "demo:marshal-record-mixed-text-two-u32-lists-lower/api.write@1.0.0/lower");
}

test "mixed text and two u32-list lower declaration rejects locator drift" {
    try expect_error_for_descriptor(
        "Writing {\n    code u32\n    label text\n    first [u32]\n    second [u32]\n}\nwrite = @host_func(\"demo:other/api@1.0.0\", \"write\", (Writing) -> nil)",
        mixed_text_two_u32_lists_lower_descriptor,
        error.GcWitHostLocatorMismatch,
    );
}

test "mixed text byte/u32-list lower declaration rejects locator drift" {
    try expect_error_for_descriptor(
        "Writing {\n    code u32\n    label text\n    bytes [u8]\n    values [u32]\n}\nwrite = @host_func(\"demo:marshal-record-mixed-text-byte-u32-lists-other/api@1.0.0\", \"write\", (Writing) -> nil)",
        mixed_text_byte_u32_lists_lower_descriptor,
        error.GcWitHostLocatorMismatch,
    );
}

test "mixed text u32-list lower declaration is accepted" {
    const source =
        "Writing {\n    code u32\n    label text\n    payload [u32]\n}\n" ++
        "write = @host_func(\"demo:marshal-record-mixed-text-u32-list-lower/api@1.0.0\", \"write\", (Writing) -> nil)";
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try validate(tokens, mixed_text_u32_list_lower_descriptor);
}

test "mixed text u32-list lift declaration is accepted" {
    const source =
        "Reading {\n    code u32\n    label text\n    payload [u32]\n}\n" ++
        "read = @host_func(\"demo:marshal-record-mixed-text-u32-list-lift/api@1.0.0\", \"read\", () -> Reading)";
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try validate(tokens, "demo:marshal-record-mixed-text-u32-list-lift/api.read@1.0.0/lift");
}

test "mixed text byte-list lift declaration is accepted" {
    const source = @embedFile("test/compile_ok/648_gc_wit_mixed_text_byte_list_lift_host_boundary.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try validate(tokens, "demo:marshal-record-mixed-text-byte-list-lift/api.read@1.0.0/lift");
}

test "mixed text and two u32-list lift declaration is accepted" {
    const source =
        "Reading {\n    code u32\n    label text\n    first [u32]\n    second [u32]\n}\n" ++
        "read = @host_func(\"demo:marshal-record-mixed-text-two-u32-lists-lift/api@1.0.0\", \"read\", () -> Reading)";
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try validate(tokens, "demo:marshal-record-mixed-text-two-u32-lists-lift/api.read@1.0.0/lift");
}

test "mixed scalar-list lower declaration rejects async host" {
    try expect_error_for_descriptor(
        "Writing {\n    code u32\n    label text\n    payload [u8]\n}\nwrite = @host_async_func(\"demo:marshal-record-mixed-scalar-list-lower/api@1.0.0\", \"write\", (Writing) -> nil)",
        mixed_scalar_list_lower_descriptor,
        error.AsyncGcWitHostDeclaration,
    );
}

test "GC WIT host boundary rejects an async C15-B declaration" {
    try expect_error_for_descriptor(
        "Writing {\n    code u32\n    label text\n}\nwrite = @host_async_func(\"demo:marshal-record-managed-lower/api@1.0.0\", \"write\", (Writing) -> nil)",
        managed_record_lower_descriptor,
        error.AsyncGcWitHostDeclaration,
    );
}

test "GC WIT host boundary rejects a C15-B locator mismatch" {
    try expect_error_for_descriptor(
        "Writing {\n    code u32\n    label text\n}\nwrite = @host_func(\"demo:other/api@1.0.0\", \"write\", (Writing) -> nil)",
        managed_record_lower_descriptor,
        error.GcWitHostLocatorMismatch,
    );
}

test "GC WIT host boundary accepts the managed record declaration" {
    const tokens = try lexer.tokenize(std.testing.allocator, positive_source);
    defer std.testing.allocator.free(tokens);
    try validate(tokens, managed_record_lower_multi_descriptor);
}

test "GC WIT host boundary rejects an unknown descriptor" {
    const tokens = try lexer.tokenize(std.testing.allocator, positive_source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectError(
        error.UnsupportedGcWitHostDescriptor,
        validate(tokens, "demo:unknown/api.write@1.0.0/lower"),
    );
}

test "GC WIT host boundary rejects a missing host declaration" {
    try expect_error(
        "Writing {\n    code u32\n    label text\n    note text\n}\nstart() {}",
        error.MissingGcWitHostDeclaration,
    );
}

test "GC WIT host boundary rejects an async marker" {
    try expect_error(
        "Writing {\n    code u32\n    label text\n    note text\n}\nwrite = @host_async_func(\"demo:marshal-record-managed-lower-multi/api@1.0.0\", \"write\", (Writing) -> nil)",
        error.AsyncGcWitHostDeclaration,
    );
}

test "GC WIT host boundary rejects a locator mismatch" {
    try expect_error(
        "Writing {\n    code u32\n    label text\n    note text\n}\nwrite = @host_func(\"demo:other/api@1.0.0\", \"write\", (Writing) -> nil)",
        error.GcWitHostLocatorMismatch,
    );
}

test "GC WIT host boundary rejects a member mismatch" {
    try expect_error(
        "Writing {\n    code u32\n    label text\n    note text\n}\nwrite = @host_func(\"demo:marshal-record-managed-lower-multi/api@1.0.0\", \"other\", (Writing) -> nil)",
        error.GcWitHostMemberMismatch,
    );
}

test "GC WIT host boundary rejects a non-nil result" {
    try expect_error(
        "Writing {\n    code u32\n    label text\n    note text\n}\nwrite = @host_func(\"demo:marshal-record-managed-lower-multi/api@1.0.0\", \"write\", (Writing) -> u32)",
        error.GcWitHostSignatureMismatch,
    );
}

test "GC WIT host boundary rejects wrong parameter arity" {
    try expect_error(
        "Writing {\n    code u32\n    label text\n    note text\n}\nwrite = @host_func(\"demo:marshal-record-managed-lower-multi/api@1.0.0\", \"write\", (Writing, Writing) -> nil)",
        error.GcWitHostSignatureMismatch,
    );
}

test "GC WIT host boundary rejects a non-record parameter" {
    try expect_error(
        "Writing {\n    code u32\n    label text\n    note text\n}\nwrite = @host_func(\"demo:marshal-record-managed-lower-multi/api@1.0.0\", \"write\", (u32) -> nil)",
        error.GcWitHostRecordMismatch,
    );
}

test "GC WIT host boundary rejects reordered record fields" {
    try expect_error(
        "Writing {\n    label text\n    code u32\n    note text\n}\nwrite = @host_func(\"demo:marshal-record-managed-lower-multi/api@1.0.0\", \"write\", (Writing) -> nil)",
        error.GcWitHostRecordMismatch,
    );
}

test "GC WIT host boundary rejects a wrong record field type" {
    try expect_error(
        "Writing {\n    code u32\n    label [u8]\n    note text\n}\nwrite = @host_func(\"demo:marshal-record-managed-lower-multi/api@1.0.0\", \"write\", (Writing) -> nil)",
        error.GcWitHostRecordMismatch,
    );
}

test "GC WIT host boundary rejects duplicate target declarations" {
    try expect_error(
        "Writing {\n    code u32\n    label text\n    note text\n}\nwrite = @host_func(\"demo:marshal-record-managed-lower-multi/api@1.0.0\", \"write\", (Writing) -> nil)\nwrite_again = @host_func(\"demo:marshal-record-managed-lower-multi/api@1.0.0\", \"write\", (Writing) -> nil)",
        error.DuplicateGcWitHostDeclaration,
    );
}

test "GC WIT host boundary rejects an unrelated extra host declaration" {
    try expect_error(
        "Writing {\n    code u32\n    label text\n    note text\n}\nwrite = @host_func(\"demo:marshal-record-managed-lower-multi/api@1.0.0\", \"write\", (Writing) -> nil)\nlog = @host_func(\"env\", \"log\", (i32) -> nil)",
        error.GcWitHostExtraDeclaration,
    );
}

test "GC WIT host descriptor registry covers every default route" {
    const cases = [_]struct {
        locator: []const u8,
        member: []const u8,
        descriptor: []const u8,
    }{
        .{ .locator = "demo:marshal-record-byte-list-lower/api@1.0.0", .member = "write", .descriptor = record_byte_list_lower_descriptor },
        .{ .locator = "demo:marshal-record-u32-list-lower/api@1.0.0", .member = "write", .descriptor = record_u32_list_lower_descriptor },
        .{ .locator = "demo:marshal-record-u32-list-lift/api@1.0.0", .member = "read", .descriptor = record_u32_list_lift_descriptor },
        .{ .locator = "demo:marshal-record-byte-list-lift/api@1.0.0", .member = "read", .descriptor = record_byte_list_lift_descriptor },
        .{ .locator = "demo:marshal-record-managed-lower/api@1.0.0", .member = "write", .descriptor = managed_record_lower_descriptor },
        .{ .locator = "demo:marshal-record-managed-lift/api@1.0.0", .member = "read", .descriptor = managed_record_lift_descriptor },
        .{ .locator = "demo:marshal-record-managed-lower-multi/api@1.0.0", .member = "write", .descriptor = managed_record_lower_multi_descriptor },
        .{ .locator = "demo:marshal-record-managed-lift-multi/api@1.0.0", .member = "read", .descriptor = managed_record_lift_multi_descriptor },
        .{ .locator = "demo:marshal-record-mixed-lower/api@1.0.0", .member = "write", .descriptor = mixed_record_lower_descriptor },
        .{ .locator = "demo:marshal-record-mixed-scalar-list-lower/api@1.0.0", .member = "write", .descriptor = mixed_scalar_list_lower_descriptor },
        .{ .locator = "demo:marshal-record-mixed-text-u32-list-lower/api@1.0.0", .member = "write", .descriptor = mixed_text_u32_list_lower_descriptor },
        .{ .locator = "demo:marshal-record-mixed-text-two-u32-lists-lower/api@1.0.0", .member = "write", .descriptor = mixed_text_two_u32_lists_lower_descriptor },
        .{ .locator = "demo:marshal-record-mixed-text-u32-list-lift/api@1.0.0", .member = "read", .descriptor = mixed_text_u32_list_lift_descriptor },
        .{ .locator = "demo:marshal-record-mixed-text-byte-list-lift/api@1.0.0", .member = "read", .descriptor = mixed_text_byte_list_lift_descriptor },
        .{ .locator = "demo:marshal-record-nested-lower-deeper/api@1.0.0", .member = "write", .descriptor = nested_record_lower_deeper_descriptor },
        .{ .locator = "demo:marshal-record-nested-lift-deeper/api@1.0.0", .member = "read", .descriptor = nested_record_lift_deeper_descriptor },
    };
    for (cases) |case| {
        const descriptor = descriptor_id_for_host(case.locator, case.member) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqualStrings(case.descriptor, descriptor);
        const explicit_probe = !std.mem.eql(u8, descriptor, mixed_record_lower_descriptor) and
            !std.mem.eql(u8, descriptor, mixed_text_u32_list_lower_descriptor) and
            !std.mem.eql(u8, descriptor, mixed_text_two_u32_lists_lower_descriptor);
        try std.testing.expectEqual(explicit_probe, is_admitted_descriptor(descriptor));
    }
}

test "GC WIT host descriptor registry rejects unknown and member drift" {
    try std.testing.expect(descriptor_id_for_host("demo:unknown/api@1.0.0", "read") == null);
    try std.testing.expect(descriptor_id_for_host("demo:marshal-record-mixed-lower/api@1.0.0", "read") == null);
    try std.testing.expect(!is_admitted_descriptor("demo:marshal-record-mixed-lower/api.write@1.0.0/lift"));
}
