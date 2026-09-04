const std = @import("std");
const wit_model = @import("../wit/model.zig");
const wit_registry = @import("../wit/marshal_registry.zig");
const wit_resolve = @import("../wit/resolve.zig");
const marshal = @import("codegen_component_marshal_plan.zig");
const wit_types = @import("wit_abi_types.zig");

pub const ResolveError = error{
    UnsupportedWitMarshalShape,
    UnsupportedWitMemberArity,
    MissingWitMarshalResult,
    UnresolvedWitType,
    WitTypeCycle,
};

const descriptor_revision = "wit-resolver-v1";

pub fn build_sync_value_plan_from_wit_source(
    allocator: std.mem.Allocator,
    source: []const u8,
    world_name: []const u8,
    interface_name: []const u8,
    member_name: []const u8,
    direction: marshal.Direction,
    measured: marshal.MeasuredNode,
) !marshal.SyncValuePlan {
    var binding = try wit_resolve.resolve_source(allocator, source, world_name);
    defer binding.deinit();
    return build_sync_value_plan_from_binding(allocator, &binding, interface_name, member_name, direction, measured);
}

fn build_sync_value_plan_from_binding(
    allocator: std.mem.Allocator,
    binding: *const wit_model.BindingModel,
    interface_name: []const u8,
    member_name: []const u8,
    direction: marshal.Direction,
    measured: marshal.MeasuredNode,
) !marshal.SyncValuePlan {
    const member = try wit_registry.find_value_member(binding, interface_name, member_name);
    var source = try resolve_member_abi_type(allocator, &member, direction);
    defer source.deinit();

    const package = try format_package(allocator, binding.package);
    defer allocator.free(package);
    const canonical_member = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ interface_name, member_name });
    defer allocator.free(canonical_member);
    var hash_buffer: ["sha256:".len + 64]u8 = undefined;
    const schema_hash = format_schema_hash(&hash_buffer, binding.content_hash);

    return marshal.build_sync_value_plan_with_layout(allocator, .{
        .package = package,
        .world = member.world_name,
        .member = canonical_member,
        .revision = descriptor_revision,
        .schema_hash = schema_hash,
    }, &source, direction, measured);
}

pub fn resolve_member_abi_type(
    allocator: std.mem.Allocator,
    member: *const wit_registry.ResolvedValueMember,
    direction: marshal.Direction,
) (ResolveError || wit_types.AbiTypeError || std.mem.Allocator.Error)!wit_types.AbiType {
    var active = std.StringHashMap(void).init(allocator);
    defer active.deinit();
    return switch (direction) {
        .lower => {
            if (member.function.params.len != 1) return error.UnsupportedWitMemberArity;
            return convert_type(allocator, member.interface, member.function.params[0].type_ref, &active);
        },
        .lift => {
            const result = member.function.result orelse return error.MissingWitMarshalResult;
            return convert_type(allocator, member.interface, result, &active);
        },
    };
}

fn convert_type(
    allocator: std.mem.Allocator,
    interface: *const wit_model.InterfaceDecl,
    type_ref: *const wit_model.TypeRef,
    active: *std.StringHashMap(void),
) (ResolveError || wit_types.AbiTypeError || std.mem.Allocator.Error)!wit_types.AbiType {
    return switch (type_ref.kind) {
        .bool => wit_types.AbiType.scalar(allocator, .bool),
        .s8 => wit_types.AbiType.scalar(allocator, .i8),
        .u8 => wit_types.AbiType.scalar(allocator, .u8),
        .s16 => wit_types.AbiType.scalar(allocator, .i16),
        .u16 => wit_types.AbiType.scalar(allocator, .u16),
        .s32 => wit_types.AbiType.scalar(allocator, .i32),
        .u32 => wit_types.AbiType.scalar(allocator, .u32),
        .s64 => wit_types.AbiType.scalar(allocator, .i64),
        .u64 => wit_types.AbiType.scalar(allocator, .u64),
        .f32 => wit_types.AbiType.scalar(allocator, .f32),
        .f64 => wit_types.AbiType.scalar(allocator, .f64),
        .string => wit_types.AbiType.text(allocator),
        .list => convert_list(allocator, interface, type_ref, active),
        .map => convert_map(allocator, interface, type_ref, active),
        .named => convert_named(allocator, interface, type_ref, active),
        .unit, .option, .result, .future, .stream, .tuple, .own, .borrow => error.UnsupportedWitMarshalShape,
        .char => error.UnsupportedWitMarshalShape,
    };
}

fn format_package(allocator: std.mem.Allocator, package: wit_model.PackageDecl) ![]u8 {
    const prerelease_separator: []const u8 = if (package.version.prerelease.len == 0) "" else "-";
    return std.fmt.allocPrint(allocator, "{s}:{s}@{d}.{d}.{d}{s}{s}", .{
        package.namespace,
        package.name,
        package.version.major,
        package.version.minor,
        package.version.patch,
        prerelease_separator,
        package.version.prerelease,
    });
}

fn format_schema_hash(buffer: *["sha256:".len + 64]u8, digest: [32]u8) []const u8 {
    const digits = "0123456789abcdef";
    @memcpy(buffer[0.."sha256:".len], "sha256:");
    for (digest, 0..) |byte, index| {
        buffer["sha256:".len + index * 2] = digits[byte >> 4];
        buffer["sha256:".len + index * 2 + 1] = digits[byte & 0x0f];
    }
    return buffer[0..];
}

fn convert_list(
    allocator: std.mem.Allocator,
    interface: *const wit_model.InterfaceDecl,
    type_ref: *const wit_model.TypeRef,
    active: *std.StringHashMap(void),
) (ResolveError || wit_types.AbiTypeError || std.mem.Allocator.Error)!wit_types.AbiType {
    if (type_ref.args.len != 1) return error.UnsupportedWitMarshalShape;
    var child = try convert_type(allocator, interface, type_ref.args[0], active);
    defer child.deinit();
    return wit_types.AbiType.list(allocator, &child);
}

fn convert_map(
    allocator: std.mem.Allocator,
    interface: *const wit_model.InterfaceDecl,
    type_ref: *const wit_model.TypeRef,
    active: *std.StringHashMap(void),
) (ResolveError || wit_types.AbiTypeError || std.mem.Allocator.Error)!wit_types.AbiType {
    if (type_ref.args.len != 2 or !wit_model.map_key_allowed(type_ref.args[0])) {
        return error.UnsupportedWitMarshalShape;
    }

    var key = try convert_type(allocator, interface, type_ref.args[0], active);
    defer key.deinit();
    var value = try convert_type(allocator, interface, type_ref.args[1], active);
    defer value.deinit();
    return wit_types.AbiType.map(allocator, &key, &value);
}

fn convert_named(
    allocator: std.mem.Allocator,
    interface: *const wit_model.InterfaceDecl,
    type_ref: *const wit_model.TypeRef,
    active: *std.StringHashMap(void),
) (ResolveError || wit_types.AbiTypeError || std.mem.Allocator.Error)!wit_types.AbiType {
    if (find_resource(interface.resources, type_ref.name) != null or
        find_variant(interface.variants, type_ref.name) != null or
        find_enum(interface.enums, type_ref.name) != null or
        find_flags(interface.flags, type_ref.name) != null)
    {
        return error.UnsupportedWitMarshalShape;
    }
    if (active.contains(type_ref.name)) return error.WitTypeCycle;
    try active.put(type_ref.name, {});
    defer _ = active.remove(type_ref.name);

    if (find_alias(interface.aliases, type_ref.name)) |alias| {
        return convert_type(allocator, interface, alias.type_ref, active);
    }
    if (find_record(interface.records, type_ref.name)) |record| {
        return convert_record(allocator, interface, record, active);
    }
    return error.UnresolvedWitType;
}

fn convert_record(
    allocator: std.mem.Allocator,
    interface: *const wit_model.InterfaceDecl,
    record: *const wit_model.RecordDecl,
    active: *std.StringHashMap(void),
) (ResolveError || wit_types.AbiTypeError || std.mem.Allocator.Error)!wit_types.AbiType {
    const values = try allocator.alloc(wit_types.AbiType, record.fields.len);
    var initialized: usize = 0;
    errdefer {
        for (values[0..initialized]) |*value| value.deinit();
        allocator.free(values);
    }
    const specs = try allocator.alloc(wit_types.FieldSpec, record.fields.len);
    defer allocator.free(specs);

    for (record.fields, 0..) |field, index| {
        values[index] = try convert_type(allocator, interface, field.type_ref, active);
        initialized += 1;
        specs[index] = .{ .name = field.name, .value = &values[index] };
    }

    const result = try wit_types.AbiType.record(allocator, specs);
    for (values[0..initialized]) |*value| value.deinit();
    allocator.free(values);
    return result;
}

fn find_alias(aliases: []const wit_model.TypeAlias, name: []const u8) ?*const wit_model.TypeAlias {
    for (aliases) |*alias| {
        if (std.mem.eql(u8, alias.name, name)) return alias;
    }
    return null;
}

fn find_record(records: []const wit_model.RecordDecl, name: []const u8) ?*const wit_model.RecordDecl {
    for (records) |*record| {
        if (std.mem.eql(u8, record.name, name)) return record;
    }
    return null;
}

fn find_variant(variants: []const wit_model.VariantDecl, name: []const u8) ?*const wit_model.VariantDecl {
    for (variants) |*variant| {
        if (std.mem.eql(u8, variant.name, name)) return variant;
    }
    return null;
}

fn find_enum(enums: []const wit_model.EnumDecl, name: []const u8) ?*const wit_model.EnumDecl {
    for (enums) |*enum_decl| {
        if (std.mem.eql(u8, enum_decl.name, name)) return enum_decl;
    }
    return null;
}

fn find_flags(flags: []const wit_model.FlagsDecl, name: []const u8) ?*const wit_model.FlagsDecl {
    for (flags) |*flags_decl| {
        if (std.mem.eql(u8, flags_decl.name, name)) return flags_decl;
    }
    return null;
}

fn find_resource(resources: []const wit_model.ResourceDecl, name: []const u8) ?*const wit_model.ResourceDecl {
    for (resources) |*resource| {
        if (std.mem.eql(u8, resource.name, name)) return resource;
    }
    return null;
}
