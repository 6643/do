//! Bounded lowering capabilities emitted for generated WIT bindings.
const std = @import("std");
const model = @import("model.zig");

pub const Capability = struct {
    capability: []const u8,
    member: []const u8,
    source_signature: []const u8,
    wit_package: []const u8,
    wit_world: []const u8,
    wit_interface: []const u8,
    wit_member: []const u8,
    async_import_module: []const u8,
    async_import_name: []const u8,
    completion: []const u8,
    wit_sha256: [32]u8,
};

pub const capability_name = "component-async-unit-v1";
pub const pinned_package = "do:generic-async-runtime-probe@0.1.0";
pub const pinned_world = "probe";
pub const pinned_interface = "host";
pub const pinned_member = "work";
pub const pinned_source_signature = "() -> Future<nil>";
pub const pinned_async_import_module = "do:generic-async-runtime-probe/host@0.1.0";
pub const pinned_async_import_name = "[async-lower]work";
pub const pinned_completion = "task-return";

pub fn detect(allocator: std.mem.Allocator, binding: model.BindingModel) ![]Capability {
    if (!same_package(binding.package, .{ .namespace = "do", .name = "generic-async-runtime-probe", .version = .{ .major = 0, .minor = 1, .patch = 0 }, .span = undefined })) return &.{};
    if (!std.mem.eql(u8, binding.world.name, pinned_world)) return &.{};
    if (binding.interfaces.len != 1) return &.{};
    const interface = binding.interfaces[0];
    if (!std.mem.eql(u8, interface.name, pinned_interface)) return &.{};
    if (interface.package) |package| {
        if (!same_package(package, binding.package)) return &.{};
    }
    if (interface.functions.len != 1) return &.{};
    const function = interface.functions[0];
    if (!std.mem.eql(u8, function.name, pinned_member) or
        !function.is_async or function.params.len != 0 or function.result != null or
        function.effects.has_future or function.effects.has_stream or function.effects.has_resource) return &.{};

    var capability = Capability{
        .capability = "",
        .member = "",
        .source_signature = "",
        .wit_package = "",
        .wit_world = "",
        .wit_interface = "",
        .wit_member = "",
        .async_import_module = "",
        .async_import_name = "",
        .completion = "",
        .wit_sha256 = binding.content_hash,
    };
    errdefer free_capability(allocator, &capability);
    capability.capability = try allocator.dupe(u8, capability_name);
    capability.member = try allocator.dupe(u8, "host.work");
    capability.source_signature = try allocator.dupe(u8, pinned_source_signature);
    capability.wit_package = try allocator.dupe(u8, pinned_package);
    capability.wit_world = try allocator.dupe(u8, pinned_world);
    capability.wit_interface = try allocator.dupe(u8, pinned_interface);
    capability.wit_member = try allocator.dupe(u8, pinned_member);
    capability.async_import_module = try allocator.dupe(u8, pinned_async_import_module);
    capability.async_import_name = try allocator.dupe(u8, pinned_async_import_name);
    capability.completion = try allocator.dupe(u8, pinned_completion);
    capability.wit_sha256 = binding.content_hash;

    var capabilities = try allocator.alloc(Capability, 1);
    capabilities[0] = capability;
    return capabilities;
}

pub fn deinit(allocator: std.mem.Allocator, capabilities: []Capability) void {
    for (capabilities) |*capability| free_capability(allocator, capability);
    if (capabilities.len != 0) allocator.free(capabilities);
}

fn free_capability(allocator: std.mem.Allocator, capability: *Capability) void {
    if (capability.capability.len != 0) allocator.free(capability.capability);
    if (capability.member.len != 0) allocator.free(capability.member);
    if (capability.source_signature.len != 0) allocator.free(capability.source_signature);
    if (capability.wit_package.len != 0) allocator.free(capability.wit_package);
    if (capability.wit_world.len != 0) allocator.free(capability.wit_world);
    if (capability.wit_interface.len != 0) allocator.free(capability.wit_interface);
    if (capability.wit_member.len != 0) allocator.free(capability.wit_member);
    if (capability.async_import_module.len != 0) allocator.free(capability.async_import_module);
    if (capability.async_import_name.len != 0) allocator.free(capability.async_import_name);
    if (capability.completion.len != 0) allocator.free(capability.completion);
}

fn same_package(lhs: model.PackageDecl, rhs: model.PackageDecl) bool {
    return std.mem.eql(u8, lhs.namespace, rhs.namespace) and
        std.mem.eql(u8, lhs.name, rhs.name) and
        lhs.version.major == rhs.version.major and
        lhs.version.minor == rhs.version.minor and
        lhs.version.patch == rhs.version.patch and
        std.mem.eql(u8, lhs.version.prerelease, rhs.version.prerelease);
}
