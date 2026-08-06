//! Validation for the manifest emitted beside generated WIT bindings.
const std = @import("std");
const model = @import("model.zig");
const signature = @import("signature.zig");

pub const ManifestError = error{
    InvalidManifest,
    ManifestSchemaUnsupported,
    ManifestMissingField,
    ManifestLocatorInvalid,
    ManifestModuleInvalid,
    ManifestDuplicateModule,
    ManifestHashInvalid,
    ManifestMemberInvalid,
    ManifestDuplicateMember,
    ManifestEffectMismatch,
    ManifestSignatureMismatch,
    ManifestLoweringMismatch,
    ManifestBindingMismatch,
    ManifestGeneratedModuleMismatch,
};

pub const Member = struct {
    package: []const u8,
    name: []const u8,
    effect: []const u8,
    is_async: bool,
    has_future: bool,
    has_stream: bool,
    has_resource: bool,
    signature: []const u8,
};

pub const ModuleHash = struct {
    path: []const u8,
    sha256: []const u8,
};

pub const AsyncLowering = struct {
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
    wit_sha256: []const u8,
    payload: ?ScalarPayload,
};

pub const ScalarPayload = struct {
    core_type: []const u8,
    offset: u32,
    byte_size: u32,
    alignment: u32,
    encoding: []const u8,
};

pub const Document = struct {
    schema: u32,
    package: []const u8,
    world: []const u8,
    modules: []const []const u8,
    module_hashes: []const ModuleHash,
    sha256: []const u8,
    members: []const Member,
    async_lowerings: []const AsyncLowering,
};

pub const Parsed = struct {
    tree: std.json.Parsed(std.json.Value),
    document: Document,

    pub fn deinit(self: *Parsed, allocator: std.mem.Allocator) void {
        allocator.free(self.document.modules);
        allocator.free(self.document.module_hashes);
        allocator.free(self.document.members);
        allocator.free(self.document.async_lowerings);
        self.tree.deinit();
        self.* = undefined;
    }
};

pub fn parse(allocator: std.mem.Allocator, source: []const u8) (ManifestError || std.mem.Allocator.Error)!Parsed {
    var tree = std.json.parseFromSlice(std.json.Value, allocator, source, .{}) catch return error.InvalidManifest;
    errdefer tree.deinit();

    const root = object_value(tree.value) orelse return error.InvalidManifest;
    const schema = unsigned_value(root.get("schema")) orelse return error.ManifestMissingField;
    if (schema != 1 and schema != 2) return error.ManifestSchemaUnsupported;
    const package = string_value(root.get("package")) orelse return error.ManifestMissingField;
    const world = string_value(root.get("world")) orelse return error.ManifestMissingField;
    const sha256 = string_value(root.get("sha256")) orelse return error.ManifestMissingField;
    if (!valid_package_locator(package) or !valid_identifier(world)) return error.ManifestLocatorInvalid;
    if (!valid_hash(sha256)) return error.ManifestHashInvalid;

    const module_values = array_value(root.get("modules")) orelse return error.ManifestMissingField;
    var modules = std.ArrayList([]const u8).empty;
    errdefer modules.deinit(allocator);
    for (module_values.items) |value| {
        const module = string_value(value) orelse return error.ManifestModuleInvalid;
        if (!valid_module_path(module)) return error.ManifestModuleInvalid;
        for (modules.items) |existing| {
            if (std.mem.eql(u8, existing, module)) return error.ManifestDuplicateModule;
        }
        try modules.append(allocator, module);
    }
    if (modules.items.len == 0) return error.ManifestModuleInvalid;

    var module_hashes = std.ArrayList(ModuleHash).empty;
    errdefer module_hashes.deinit(allocator);
    if (root.get("module_hashes")) |module_hash_value| {
        const module_hash_values = array_value(module_hash_value) orelse return error.ManifestModuleInvalid;
        for (module_hash_values.items) |value| {
            const object = object_value(value) orelse return error.ManifestModuleInvalid;
            const path = string_value(object.get("path")) orelse return error.ManifestModuleInvalid;
            const hash = string_value(object.get("sha256")) orelse return error.ManifestModuleInvalid;
            if (!valid_module_path(path) or !valid_hash(hash)) return error.ManifestModuleInvalid;
            if (!has_module_path(modules.items, path)) return error.ManifestModuleInvalid;
            for (module_hashes.items) |existing| {
                if (std.mem.eql(u8, existing.path, path)) return error.ManifestDuplicateModule;
            }
            try module_hashes.append(allocator, .{ .path = path, .sha256 = hash });
        }
    }

    const member_values = array_value(root.get("members")) orelse return error.ManifestMissingField;
    var members = std.ArrayList(Member).empty;
    errdefer members.deinit(allocator);
    for (member_values.items) |value| {
        const member = try parse_member(value);
        for (members.items) |existing| {
            if (std.mem.eql(u8, existing.package, member.package) and
                std.mem.eql(u8, existing.name, member.name)) return error.ManifestDuplicateMember;
        }
        try members.append(allocator, member);
    }

    var async_lowerings = std.ArrayList(AsyncLowering).empty;
    errdefer async_lowerings.deinit(allocator);
    if (schema == 2) {
        const lowering_values = array_value(root.get("async_lowerings")) orelse return error.ManifestMissingField;
        for (lowering_values.items) |value| {
            const lowering = try parse_async_lowering(value);
            if (!std.mem.eql(u8, lowering.wit_package, package) or
                !std.mem.eql(u8, lowering.wit_world, world) or
                !std.mem.eql(u8, lowering.wit_sha256, sha256)) return error.ManifestLoweringMismatch;
            if (find_manifest_member(members.items, lowering.wit_package, lowering.member)) |member| {
                if (std.mem.eql(u8, lowering.capability, "component-async-unit-v1")) {
                    if (!member.is_async or !std.mem.eql(u8, member.effect, "async")) return error.ManifestEffectMismatch;
                } else if (std.mem.eql(u8, lowering.capability, "component-async-scalar-u32-v1") or
                    std.mem.eql(u8, lowering.capability, "component-async-scalar-i64-v1")) {
                    if (member.is_async or !member.has_future or member.has_stream or member.has_resource) return error.ManifestEffectMismatch;
                } else return error.ManifestLoweringMismatch;
                if (!std.mem.eql(u8, member.signature, lowering.source_signature)) return error.ManifestSignatureMismatch;
            } else return error.ManifestLoweringMismatch;
            for (async_lowerings.items) |existing| {
                if (std.mem.eql(u8, existing.member, lowering.member) or
                    std.mem.eql(u8, existing.wit_member, lowering.wit_member)) return error.ManifestLoweringMismatch;
            }
            try async_lowerings.append(allocator, lowering);
        }
    } else if (root.get("async_lowerings") != null) {
        return error.ManifestSchemaUnsupported;
    }

    return .{
        .tree = tree,
        .document = .{
            .schema = @intCast(schema),
            .package = package,
            .world = world,
            .modules = try modules.toOwnedSlice(allocator),
            .module_hashes = try module_hashes.toOwnedSlice(allocator),
            .sha256 = sha256,
            .members = try members.toOwnedSlice(allocator),
            .async_lowerings = try async_lowerings.toOwnedSlice(allocator),
        },
    };
}

/// Validate the generated source files named by a manifest. This is separate
/// from WIT/model validation so `do wit check --manifest` can reject a module
/// whose host signature was edited after generation.
pub fn validate_generated_modules(
    io: std.Io,
    allocator: std.mem.Allocator,
    parsed: *const Parsed,
    manifest_path: []const u8,
) (ManifestError || std.mem.Allocator.Error)!void {
    const document = parsed.document;
    if (document.module_hashes.len != document.modules.len) return error.ManifestGeneratedModuleMismatch;
    const base = std.fs.path.dirname(manifest_path) orelse ".";
    const cwd = std.Io.Dir.cwd();
    for (document.modules) |module| {
        const expected = find_module_hash(document.module_hashes, module) orelse
            return error.ManifestGeneratedModuleMismatch;
        const path = std.fs.path.join(allocator, &.{ base, module }) catch
            return error.ManifestGeneratedModuleMismatch;
        defer allocator.free(path);
        const source = cwd.readFileAlloc(io, path, allocator, .limited(16 * 1024 * 1024)) catch
            return error.ManifestGeneratedModuleMismatch;
        defer allocator.free(source);
        if (!source_hash_matches(expected.sha256, source)) return error.ManifestGeneratedModuleMismatch;
    }
}

pub fn validate_binding(
    allocator: std.mem.Allocator,
    parsed: *const Parsed,
    binding: model.BindingModel,
) (ManifestError || std.mem.Allocator.Error)!void {
    const document = parsed.document;
    if (!package_locator_matches(document.package, binding.package) or
        !std.mem.eql(u8, document.world, binding.world.name) or
        !hash_matches(document.sha256, binding.content_hash)) return error.ManifestBindingMismatch;

    if (document.modules.len != binding.interfaces.len) return error.ManifestBindingMismatch;
    for (binding.interfaces) |interface| {
        const package = interface.package orelse binding.package;
        if (!has_module(document.modules, package, binding.world, interface.name)) {
            return error.ManifestBindingMismatch;
        }
    }

    var expected_members: usize = 0;
    for (binding.interfaces) |interface| expected_members += interface.functions.len;
    if (document.members.len != expected_members) return error.ManifestBindingMismatch;

    for (binding.interfaces) |interface| {
        const package = interface.package orelse binding.package;
        for (interface.functions) |function| {
            const member = find_member(document.members, package, interface.name, function.name) orelse
                return error.ManifestBindingMismatch;
            if (member.is_async != function.is_async or
                member.has_future != function.effects.has_future or
                member.has_stream != function.effects.has_stream or
                member.has_resource != function.effects.has_resource) return error.ManifestBindingMismatch;
            const expected_signature = signature.render(allocator, interface.name, function) catch
                return error.ManifestBindingMismatch;
            defer allocator.free(expected_signature);
            if (!std.mem.eql(u8, member.signature, expected_signature)) return error.ManifestSignatureMismatch;
        }
    }

    for (document.async_lowerings) |lowering| {
        if (!hash_matches(lowering.wit_sha256, binding.content_hash)) return error.ManifestLoweringMismatch;
        if (!std.mem.eql(u8, lowering.wit_package, document.package) or
            !std.mem.eql(u8, lowering.wit_world, document.world)) return error.ManifestLoweringMismatch;
        const interface = find_interface(binding.interfaces, lowering.wit_interface) orelse
            return error.ManifestLoweringMismatch;
        const function = find_function(interface, lowering.wit_member) orelse
            return error.ManifestLoweringMismatch;
        if (std.mem.eql(u8, lowering.capability, "component-async-unit-v1")) {
            if (!function.is_async or function.params.len != 0 or function.result != null or
                function.effects.has_future or function.effects.has_stream or function.effects.has_resource) return error.ManifestEffectMismatch;
        } else if (std.mem.eql(u8, lowering.capability, "component-async-scalar-u32-v1") or
            std.mem.eql(u8, lowering.capability, "component-async-scalar-i64-v1")) {
            if (function.is_async or function.params.len != 0 or function.result == null or
                function.result.?.kind != .future or function.result.?.args.len != 1 or
                (function.result.?.args[0].kind != .u32 and function.result.?.args[0].kind != .s64) or
                !function.effects.has_future or
                function.effects.has_stream or function.effects.has_resource) return error.ManifestEffectMismatch;
        } else return error.ManifestLoweringMismatch;
        const expected_signature = signature.render(allocator, interface.name, function) catch
            return error.ManifestSignatureMismatch;
        defer allocator.free(expected_signature);
        if (!std.mem.eql(u8, lowering.source_signature, expected_signature)) return error.ManifestSignatureMismatch;
    }
}

fn find_interface(interfaces: []const model.InterfaceDecl, name: []const u8) ?model.InterfaceDecl {
    for (interfaces) |interface| {
        if (std.mem.eql(u8, interface.name, name)) return interface;
    }
    return null;
}

fn find_function(interface: model.InterfaceDecl, name: []const u8) ?model.FunctionDecl {
    for (interface.functions) |function| {
        if (std.mem.eql(u8, function.name, name)) return function;
    }
    return null;
}

fn has_module(
    modules: []const []const u8,
    package: model.PackageDecl,
    world: model.WorldDecl,
    interface_name: []const u8,
) bool {
    for (modules) |module| {
        if (module_matches(module, package, world.name, interface_name)) return true;
    }
    return false;
}

fn has_module_path(modules: []const []const u8, path: []const u8) bool {
    for (modules) |module| {
        if (std.mem.eql(u8, module, path)) return true;
    }
    return false;
}

fn find_module_hash(module_hashes: []const ModuleHash, path: []const u8) ?ModuleHash {
    for (module_hashes) |module_hash| {
        if (std.mem.eql(u8, module_hash.path, path)) return module_hash;
    }
    return null;
}

fn module_matches(
    module: []const u8,
    package: model.PackageDecl,
    world_name: []const u8,
    interface_name: []const u8,
) bool {
    var index: usize = 0;
    if (!consume_flat_name(module, &index, package.namespace)) return false;
    if (!consume_literal(module, &index, "_")) return false;
    if (!consume_flat_name(module, &index, package.name)) return false;
    if (!consume_literal(module, &index, "__")) return false;
    if (!consume_flat_name(module, &index, interface_name)) return false;
    if (!consume_literal(module, &index, "__")) return false;
    if (!consume_flat_name(module, &index, world_name)) return false;
    if (!consume_literal(module, &index, ".do")) return false;
    return index == module.len;
}

fn consume_literal(text: []const u8, index: *usize, literal: []const u8) bool {
    if (text.len -| index.* < literal.len) return false;
    if (!std.mem.eql(u8, text[index.* .. index.* + literal.len], literal)) return false;
    index.* += literal.len;
    return true;
}

fn consume_flat_name(text: []const u8, index: *usize, name: []const u8) bool {
    for (name) |ch| {
        if (index.* >= text.len) return false;
        const expected = if (std.ascii.isAlphanumeric(ch) or ch == '_') ch else '_';
        if (text[index.*] != expected) return false;
        index.* += 1;
    }
    return true;
}

fn find_member(
    members: []const Member,
    package: model.PackageDecl,
    interface_name: []const u8,
    function_name: []const u8,
) ?Member {
    for (members) |member| {
        if (package_locator_matches(member.package, package) and
            member_name_matches(member.name, interface_name, function_name)) return member;
    }
    return null;
}

fn member_name_matches(name: []const u8, interface_name: []const u8, function_name: []const u8) bool {
    if (name.len <= interface_name.len + 1 or
        !std.mem.startsWith(u8, name, interface_name) or
        name[interface_name.len] != '.') return false;
    return std.mem.eql(u8, name[interface_name.len + 1 ..], function_name);
}

fn package_locator_matches(locator: []const u8, package: model.PackageDecl) bool {
    const colon = std.mem.indexOfScalar(u8, locator, ':') orelse return false;
    const at = std.mem.indexOfScalarPos(u8, locator, colon + 1, '@') orelse return false;
    if (!std.mem.eql(u8, locator[0..colon], package.namespace)) return false;
    if (!std.mem.eql(u8, locator[colon + 1 .. at], package.name)) return false;
    const version = locator[at + 1 ..];
    const prerelease_start = std.mem.indexOfScalar(u8, version, '-') orelse version.len;
    const numeric = version[0..prerelease_start];
    var parts = std.mem.splitScalar(u8, numeric, '.');
    const major = std.fmt.parseInt(u32, parts.next() orelse return false, 10) catch return false;
    const minor = std.fmt.parseInt(u32, parts.next() orelse return false, 10) catch return false;
    const patch = std.fmt.parseInt(u32, parts.next() orelse return false, 10) catch return false;
    if (parts.next() != null or major != package.version.major or minor != package.version.minor or patch != package.version.patch) return false;
    const prerelease = if (prerelease_start < version.len) version[prerelease_start + 1 ..] else "";
    return std.mem.eql(u8, prerelease, package.version.prerelease);
}

fn hash_matches(text: []const u8, hash: [32]u8) bool {
    if (text.len != 64) return false;
    const digits = "0123456789abcdef";
    for (hash, 0..) |byte, index| {
        const high = text[index * 2];
        const low = text[index * 2 + 1];
        if (std.ascii.toLower(high) != digits[byte >> 4] or std.ascii.toLower(low) != digits[byte & 0x0f]) return false;
    }
    return true;
}

fn source_hash_matches(text: []const u8, source: []const u8) bool {
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(source, &digest, .{});
    return hash_matches(text, digest);
}

fn parse_member(value: std.json.Value) ManifestError!Member {
    const object = object_value(value) orelse return error.ManifestMemberInvalid;
    const package = string_value(object.get("package")) orelse return error.ManifestMemberInvalid;
    const name = string_value(object.get("member")) orelse return error.ManifestMemberInvalid;
    const effect = string_value(object.get("effect")) orelse return error.ManifestMemberInvalid;
    const is_async = bool_value(object.get("async")) orelse return error.ManifestMemberInvalid;
    const has_future = bool_value(object.get("future")) orelse return error.ManifestMemberInvalid;
    const has_stream = bool_value(object.get("stream")) orelse return error.ManifestMemberInvalid;
    const has_resource = bool_value(object.get("resource")) orelse return error.ManifestMemberInvalid;
    const signature_text = string_value(object.get("signature")) orelse return error.ManifestMemberInvalid;
    if (!valid_package_locator(package) or !valid_member_name(name)) return error.ManifestMemberInvalid;
    if (!std.mem.eql(u8, effect, "sync") and !std.mem.eql(u8, effect, "async")) return error.ManifestMemberInvalid;
    if (is_async != std.mem.eql(u8, effect, "async")) return error.ManifestEffectMismatch;
    if (!valid_signature(signature_text)) return error.ManifestMemberInvalid;
    return .{
        .package = package,
        .name = name,
        .effect = effect,
        .is_async = is_async,
        .has_future = has_future,
        .has_stream = has_stream,
        .has_resource = has_resource,
        .signature = signature_text,
    };
}

fn parse_async_lowering(value: std.json.Value) ManifestError!AsyncLowering {
    const object = object_value(value) orelse return error.ManifestLoweringMismatch;
    const capability = string_value(object.get("capability")) orelse return error.ManifestLoweringMismatch;
    const member = string_value(object.get("member")) orelse return error.ManifestLoweringMismatch;
    const source_signature = string_value(object.get("source_signature")) orelse return error.ManifestLoweringMismatch;
    const wit_package = string_value(object.get("wit_package")) orelse return error.ManifestLoweringMismatch;
    const wit_world = string_value(object.get("wit_world")) orelse return error.ManifestLoweringMismatch;
    const wit_interface = string_value(object.get("wit_interface")) orelse return error.ManifestLoweringMismatch;
    const wit_member = string_value(object.get("wit_member")) orelse return error.ManifestLoweringMismatch;
    const async_import_module = string_value(object.get("async_import_module")) orelse return error.ManifestLoweringMismatch;
    const async_import_name = string_value(object.get("async_import_name")) orelse return error.ManifestLoweringMismatch;
    const completion = string_value(object.get("completion")) orelse return error.ManifestLoweringMismatch;
    const wit_sha256 = string_value(object.get("wit_sha256")) orelse return error.ManifestLoweringMismatch;
    const payload = try parse_payload(object.get("payload"));

    if (std.mem.eql(u8, capability, "component-async-unit-v1")) {
        if (!std.mem.eql(u8, member, "host.work") or
        !std.mem.eql(u8, source_signature, "() -> Future<nil>") or
        !std.mem.eql(u8, wit_package, "do:generic-async-runtime-probe@0.1.0") or
        !std.mem.eql(u8, wit_world, "probe") or
        !std.mem.eql(u8, wit_interface, "host") or
        !std.mem.eql(u8, wit_member, "work") or
        !std.mem.eql(u8, async_import_module, "do:generic-async-runtime-probe/host@0.1.0") or
        !std.mem.eql(u8, async_import_name, "[async-lower]work") or
        !std.mem.eql(u8, completion, "task-return") or
        !valid_hash(wit_sha256) or payload != null) return error.ManifestLoweringMismatch;
    } else if (std.mem.eql(u8, capability, "component-async-scalar-u32-v1")) {
        const scalar = payload orelse return error.ManifestLoweringMismatch;
        if (!std.mem.eql(u8, member, "host.completion") or
            !std.mem.eql(u8, source_signature, "() -> Future<u32>") or
            !std.mem.eql(u8, wit_package, "do:generic-async-scalar-probe@0.1.0") or
            !std.mem.eql(u8, wit_world, "probe") or
            !std.mem.eql(u8, wit_interface, "host") or
            !std.mem.eql(u8, wit_member, "completion") or
            !std.mem.eql(u8, async_import_module, "do:generic-async-scalar-probe/host@0.1.0") or
            !std.mem.eql(u8, async_import_name, "[async-lower][future-read-0]completion") or
            !std.mem.eql(u8, completion, "completion") or
            !std.mem.eql(u8, scalar.core_type, "i32") or scalar.offset != 12 or
            scalar.byte_size != 4 or scalar.alignment != 4 or
            !std.mem.eql(u8, scalar.encoding, "core-u32") or !valid_hash(wit_sha256)) return error.ManifestLoweringMismatch;
    } else if (std.mem.eql(u8, capability, "component-async-scalar-i64-v1")) {
        const scalar = payload orelse return error.ManifestLoweringMismatch;
        if (!std.mem.eql(u8, member, "host.completion") or
            !std.mem.eql(u8, source_signature, "() -> Future<i64>") or
            !std.mem.eql(u8, wit_package, "do:generic-async-scalar-i64-probe@0.1.0") or
            !std.mem.eql(u8, wit_world, "probe") or
            !std.mem.eql(u8, wit_interface, "host") or
            !std.mem.eql(u8, wit_member, "completion") or
            !std.mem.eql(u8, async_import_module, "do:generic-async-scalar-i64-probe/host@0.1.0") or
            !std.mem.eql(u8, async_import_name, "[async-lower][future-read-0]completion") or
            !std.mem.eql(u8, completion, "completion") or
            !std.mem.eql(u8, scalar.core_type, "i64") or scalar.offset != 16 or
            scalar.byte_size != 8 or scalar.alignment != 8 or
            !std.mem.eql(u8, scalar.encoding, "core-s64") or !valid_hash(wit_sha256)) return error.ManifestLoweringMismatch;
    } else return error.ManifestLoweringMismatch;
    return .{
        .capability = capability,
        .member = member,
        .source_signature = source_signature,
        .wit_package = wit_package,
        .wit_world = wit_world,
        .wit_interface = wit_interface,
        .wit_member = wit_member,
        .async_import_module = async_import_module,
        .async_import_name = async_import_name,
        .completion = completion,
        .wit_sha256 = wit_sha256,
        .payload = payload,
    };
}

fn parse_payload(value: ?std.json.Value) ManifestError!?ScalarPayload {
    const actual = value orelse return null;
    return switch (actual) {
        .null => null,
        .object => |object| .{
            .core_type = string_value(object.get("core_type")) orelse return error.ManifestLoweringMismatch,
            .offset = bounded_u32(object.get("offset")) orelse return error.ManifestLoweringMismatch,
            .byte_size = bounded_u32(object.get("byte_size")) orelse return error.ManifestLoweringMismatch,
            .alignment = bounded_u32(object.get("alignment")) orelse return error.ManifestLoweringMismatch,
            .encoding = string_value(object.get("encoding")) orelse return error.ManifestLoweringMismatch,
        },
        else => return error.ManifestLoweringMismatch,
    };
}

fn find_manifest_member(members: []const Member, package: []const u8, name: []const u8) ?Member {
    var result: ?Member = null;
    for (members) |member| {
        if (!std.mem.eql(u8, member.package, package) or !std.mem.eql(u8, member.name, name)) continue;
        if (result != null) return null;
        result = member;
    }
    return result;
}

fn valid_package_locator(locator: []const u8) bool {
    const colon = std.mem.indexOfScalar(u8, locator, ':') orelse return false;
    const at = std.mem.indexOfScalarPos(u8, locator, colon + 1, '@') orelse return false;
    if (colon == 0 or at <= colon + 1 or at + 1 >= locator.len) return false;
    if (std.mem.indexOfScalarPos(u8, locator, colon + 1, ':') != null) return false;
    const namespace = locator[0..colon];
    const package = locator[colon + 1 .. at];
    if (!valid_identifier(namespace) or !valid_identifier(package)) return false;
    return valid_version(locator[at + 1 ..]);
}

fn valid_version(version: []const u8) bool {
    const prerelease = std.mem.indexOfScalar(u8, version, '-');
    const numeric = if (prerelease) |index| version[0..index] else version;
    if (numeric.len == 0) return false;
    var parts = std.mem.splitScalar(u8, numeric, '.');
    var count: usize = 0;
    while (parts.next()) |part| {
        if (part.len == 0) return false;
        for (part) |ch| if (!std.ascii.isDigit(ch)) return false;
        count += 1;
    }
    if (count != 3) return false;
    if (prerelease) |index| {
        if (index + 1 >= version.len) return false;
        for (version[index + 1 ..]) |ch| {
            if (!(std.ascii.isAlphanumeric(ch) or ch == '.' or ch == '-')) return false;
        }
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

fn valid_module_path(path: []const u8) bool {
    return path.len > 3 and std.mem.endsWith(u8, path, ".do") and
        std.mem.indexOfScalar(u8, path, '/') == null and
        std.mem.indexOfScalar(u8, path, '\\') == null and
        std.mem.indexOf(u8, path, "..") == null;
}

fn valid_member_name(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |ch| {
        if (!(std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '-' or ch == '.')) return false;
    }
    return true;
}

fn valid_signature(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |ch| {
        if (ch < 0x20 or ch == '"' or ch == '\\') return false;
    }
    return true;
}

fn valid_hash(hash: []const u8) bool {
    if (hash.len != 64) return false;
    for (hash) |ch| {
        if (!(std.ascii.isDigit(ch) or (ch >= 'a' and ch <= 'f') or (ch >= 'A' and ch <= 'F'))) return false;
    }
    return true;
}

fn object_value(value: std.json.Value) ?std.json.ObjectMap {
    return switch (value) {
        .object => |object| object,
        else => null,
    };
}

fn array_value(value: ?std.json.Value) ?std.json.Array {
    const actual = value orelse return null;
    return switch (actual) {
        .array => |array| array,
        else => null,
    };
}

fn string_value(value: ?std.json.Value) ?[]const u8 {
    const actual = value orelse return null;
    return switch (actual) {
        .string => |text| text,
        else => null,
    };
}

fn bool_value(value: ?std.json.Value) ?bool {
    const actual = value orelse return null;
    return switch (actual) {
        .bool => |result| result,
        else => null,
    };
}

fn unsigned_value(value: ?std.json.Value) ?u64 {
    const actual = value orelse return null;
    return switch (actual) {
        .integer => |number| if (number >= 0) @intCast(number) else null,
        else => null,
    };
}

fn bounded_u32(value: ?std.json.Value) ?u32 {
    const number = unsigned_value(value) orelse return null;
    if (number > std.math.maxInt(u32)) return null;
    return @intCast(number);
}
