const std = @import("std");
const model = @import("model.zig");

pub const RegistryError = error{
    InterfaceNotFound,
    MemberNotFound,
    UnsupportedMarshalMember,
};

pub const ResolvedValueMember = struct {
    package_namespace: []const u8,
    package_name: []const u8,
    world_name: []const u8,
    interface_name: []const u8,
    member_name: []const u8,
    interface: *const model.InterfaceDecl,
    function: *const model.FunctionDecl,
    content_hash: [32]u8,
};

pub const MapPairListShape = struct {
    key: *const model.TypeRef,
    value: *const model.TypeRef,
    representation: []const u8 = "pair-list",
};

/// Describe the canonical ABI representation without claiming that the
/// current GC marshal emitter can lower the map payload yet.
pub fn map_pair_list_shape(type_ref: *const model.TypeRef) ?MapPairListShape {
    if (type_ref.kind != .map or type_ref.args.len != 2 or !model.map_key_allowed(type_ref.args[0])) return null;
    return .{ .key = type_ref.args[0], .value = type_ref.args[1] };
}

pub fn find_value_member(
    binding: *const model.BindingModel,
    interface_name: []const u8,
    member_name: []const u8,
) RegistryError!ResolvedValueMember {
    const interface = find_interface(binding.interfaces, interface_name) orelse return error.InterfaceNotFound;
    const function = find_function(interface.functions, member_name) orelse return error.MemberNotFound;

    if (function.is_async or function.effects.has_future or function.effects.has_stream or function.effects.has_resource) {
        return error.UnsupportedMarshalMember;
    }
    for (function.params) |param| {
        if (contains_unsupported_shape(param.type_ref, interface, 0)) {
            return error.UnsupportedMarshalMember;
        }
    }
    if (function.result) |result| {
        if (contains_unsupported_shape(result, interface, 0)) {
            return error.UnsupportedMarshalMember;
        }
    }

    return .{
        .package_namespace = binding.package.namespace,
        .package_name = binding.package.name,
        .world_name = binding.world.name,
        .interface_name = interface.name,
        .member_name = function.name,
        .interface = interface,
        .function = function,
        .content_hash = binding.content_hash,
    };
}

fn find_interface(interfaces: []const model.InterfaceDecl, name: []const u8) ?*const model.InterfaceDecl {
    for (interfaces) |*interface| {
        if (std.mem.eql(u8, interface.name, name)) return interface;
    }
    return null;
}

fn find_function(functions: []const model.FunctionDecl, name: []const u8) ?*const model.FunctionDecl {
    for (functions) |*function| {
        if (std.mem.eql(u8, function.name, name)) return function;
    }
    return null;
}

fn contains_unsupported_shape(
    type_ref: *const model.TypeRef,
    interface: *const model.InterfaceDecl,
    depth: usize,
) bool {
    if (depth > 128) return true;
    if (model.type_is_resource(type_ref, interface.resources)) return true;
    switch (type_ref.kind) {
        .own, .borrow, .future, .stream, .tuple => return true,
        else => {},
    }
    for (type_ref.args) |arg| {
        if (contains_unsupported_shape(arg, interface, depth + 1)) return true;
    }
    if (type_ref.kind != .named) return false;
    for (interface.aliases) |alias| {
        if (std.mem.eql(u8, alias.name, type_ref.name)) {
            return contains_unsupported_shape(alias.type_ref, interface, depth + 1);
        }
    }
    for (interface.records) |record| {
        if (std.mem.eql(u8, record.name, type_ref.name)) {
            for (record.fields) |field| {
                if (contains_unsupported_shape(field.type_ref, interface, depth + 1)) return true;
            }
            return false;
        }
    }
    for (interface.variants) |variant| {
        if (std.mem.eql(u8, variant.name, type_ref.name)) {
            for (variant.cases) |case| {
                if (case.payload) |payload| {
                    if (contains_unsupported_shape(payload, interface, depth + 1)) return true;
                }
            }
            return false;
        }
    }
    return false;
}
