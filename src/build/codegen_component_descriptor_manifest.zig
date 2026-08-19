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
const marshal_registry = @import("codegen_component_marshal_registry.zig");
const marshal_route = @import("codegen_component_marshal_route.zig");

pub const LoadedRequest = struct {
    manifest: descriptor_manifest.Parsed,
    manifest_source: []u8,
    source: []u8,
    request: marshal_route.Request,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *LoadedRequest) void {
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
    if (!valid_relative_path(manifest_path)) return error.ManifestPathInvalid;

    const manifest_source = try read_relative(io, allocator, repository_root, manifest_path);
    errdefer allocator.free(manifest_source);
    var parsed = descriptor_manifest.parse(allocator, manifest_source) catch |err| return err;
    errdefer parsed.deinit(allocator);
    const descriptor = try parsed.find_descriptor(descriptor_id);

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
    defer marshal.deinit_sync_value_plan(allocator, plan);

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
        .allocator = allocator,
    };
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
