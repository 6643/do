//! Compiler-side admission checks for generated `wit/*.do` modules.
//!
//! This intentionally mirrors only the manifest facts needed while loading a
//! generated module. The WIT parser and full manifest validator remain under
//! `src/wit`; keeping this boundary local lets the build modules stay directly
//! testable with `zig test build/*.zig`.
const std = @import("std");
const lexer = @import("lexer.zig");

pub const Error = error{
    GeneratedWitManifestMissing,
    GeneratedWitManifestInvalid,
    GeneratedWitManifestMismatch,
};

pub const GeneratedScalarPayload = struct {
    core_type: []const u8,
    offset: u32,
    byte_size: u32,
    alignment: u32,
    encoding: []const u8,
};

pub const GeneratedAsyncLowering = struct {
    locator: []const u8,
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
    payload: ?GeneratedScalarPayload,
};

pub const ValidatedManifest = struct {
    lowerings: []const GeneratedAsyncLowering,

    pub fn deinit(self: *ValidatedManifest, allocator: std.mem.Allocator) void {
        for (self.lowerings) |lowering| free_lowering(allocator, lowering);
        allocator.free(self.lowerings);
        self.* = undefined;
    }
};

const ModuleHash = struct {
    path: []const u8,
    hash: [32]u8,
};

const Member = struct {
    package: []const u8,
    name: []const u8,
    effect: []const u8,
    is_async: bool,
    has_future: bool,
    has_stream: bool,
    has_resource: bool,
    signature: []const u8,
};

const RawLowering = struct {
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
    payload: ?GeneratedScalarPayload,
};

const Parsed = struct {
    tree: std.json.Parsed(std.json.Value),
    package: []const u8,
    world: []const u8,
    sha256: [32]u8,
    modules: []const []const u8,
    hashes: []const ModuleHash,
    members: []const Member,
    lowerings: []const RawLowering,

    fn deinit(self: *Parsed, allocator: std.mem.Allocator) void {
        allocator.free(self.modules);
        allocator.free(self.hashes);
        allocator.free(self.members);
        allocator.free(self.lowerings);
        self.tree.deinit();
        self.* = undefined;
    }
};

const HostDecl = struct {
    locator: []const u8,
    member: []const u8,
    signature: []u8,
    has_future: bool,
    has_stream: bool,
    has_resource: bool,
};

pub fn validate(
    io: std.Io,
    allocator: std.mem.Allocator,
    module_path: []const u8,
    tokens: []const lexer.Token,
) (Error || std.mem.Allocator.Error)!void {
    var validated = try load_and_validate(io, allocator, module_path, tokens);
    defer validated.deinit(allocator);
}

pub fn load_and_validate(
    io: std.Io,
    allocator: std.mem.Allocator,
    module_path: []const u8,
    tokens: []const lexer.Token,
) (Error || std.mem.Allocator.Error)!ValidatedManifest {
    const module_dir = std.fs.path.dirname(module_path) orelse return error.GeneratedWitManifestMissing;
    const manifest_path = std.fs.path.join(allocator, &.{ module_dir, "manifest.json" }) catch
        return error.GeneratedWitManifestMissing;
    defer allocator.free(manifest_path);

    const manifest_source = std.Io.Dir.cwd().readFileAlloc(io, manifest_path, allocator, .limited(16 * 1024 * 1024)) catch
        return error.GeneratedWitManifestMissing;
    defer allocator.free(manifest_source);

    var parsed = parse(allocator, manifest_source) catch |err| switch (err) {
        error.GeneratedWitManifestMismatch => return error.GeneratedWitManifestMismatch,
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.GeneratedWitManifestInvalid,
    };
    defer parsed.deinit(allocator);

    const module_name = std.fs.path.basename(module_path);
    if (!contains_module(parsed.modules, module_name)) return error.GeneratedWitManifestMismatch;
    try validate_module_hashes(io, allocator, &parsed, manifest_path);

    var hosts = std.ArrayList(HostDecl).empty;
    defer {
        for (hosts.items) |host| allocator.free(host.signature);
        hosts.deinit(allocator);
    }
    collect_host_decls(allocator, tokens, &hosts) catch return error.GeneratedWitManifestMismatch;
    try validate_host_members(allocator, module_name, &parsed, hosts.items);

    try validate_lowerings(allocator, module_name, &parsed, hosts.items);
    return try clone_lowerings_for_module(allocator, module_name, parsed.lowerings);
}

fn parse(allocator: std.mem.Allocator, source: []const u8) !Parsed {
    var tree = std.json.parseFromSlice(std.json.Value, allocator, source, .{}) catch
        return error.InvalidManifest;
    errdefer tree.deinit();
    const root = object_value(tree.value) orelse return error.InvalidManifest;
    const schema = unsigned_value(root.get("schema")) orelse return error.InvalidManifest;
    if (schema != 1 and schema != 2) return error.InvalidManifest;
    const package = string_value(root.get("package")) orelse return error.InvalidManifest;
    const world = string_value(root.get("world")) orelse return error.InvalidManifest;
    const manifest_hash = string_value(root.get("sha256")) orelse return error.InvalidManifest;
    const manifest_sha256 = parse_hash(manifest_hash) orelse return error.InvalidManifest;

    const module_values = array_value(root.get("modules")) orelse return error.InvalidManifest;
    var modules = std.ArrayList([]const u8).empty;
    errdefer modules.deinit(allocator);
    for (module_values.items) |value| {
        const module = string_value(value) orelse return error.InvalidManifest;
        if (!valid_module_name(module)) return error.InvalidManifest;
        for (modules.items) |existing| {
            if (std.mem.eql(u8, existing, module)) return error.InvalidManifest;
        }
        try modules.append(allocator, module);
    }
    if (modules.items.len == 0) return error.InvalidManifest;

    const hash_values = array_value(root.get("module_hashes")) orelse return error.InvalidManifest;
    var hashes = std.ArrayList(ModuleHash).empty;
    errdefer hashes.deinit(allocator);
    for (hash_values.items) |value| {
        const object = object_value(value) orelse return error.InvalidManifest;
        const path = string_value(object.get("path")) orelse return error.InvalidManifest;
        const hash_text = string_value(object.get("sha256")) orelse return error.InvalidManifest;
        const hash = parse_hash(hash_text) orelse return error.InvalidManifest;
        if (!valid_module_name(path) or !contains_module(modules.items, path)) return error.InvalidManifest;
        for (hashes.items) |existing| {
            if (std.mem.eql(u8, existing.path, path)) return error.InvalidManifest;
        }
        try hashes.append(allocator, .{ .path = path, .hash = hash });
    }
    if (hashes.items.len != modules.items.len) return error.InvalidManifest;

    const member_values = array_value(root.get("members")) orelse return error.InvalidManifest;
    var members = std.ArrayList(Member).empty;
    errdefer members.deinit(allocator);
    for (member_values.items) |value| {
        const object = object_value(value) orelse return error.InvalidManifest;
        const member_package = string_value(object.get("package")) orelse return error.InvalidManifest;
        const name = string_value(object.get("member")) orelse return error.InvalidManifest;
        const effect = string_value(object.get("effect")) orelse return error.InvalidManifest;
        const is_async = bool_value(object.get("async")) orelse return error.InvalidManifest;
        const has_future = bool_value(object.get("future")) orelse return error.InvalidManifest;
        const has_stream = bool_value(object.get("stream")) orelse return error.InvalidManifest;
        const has_resource = bool_value(object.get("resource")) orelse return error.InvalidManifest;
        const signature = string_value(object.get("signature")) orelse return error.InvalidManifest;
        if (member_package.len == 0 or name.len == 0 or signature.len == 0) return error.InvalidManifest;
        if (!std.mem.eql(u8, effect, "async") and !std.mem.eql(u8, effect, "sync")) return error.InvalidManifest;
        if (is_async != std.mem.eql(u8, effect, "async")) return error.InvalidManifest;
        for (members.items) |existing| {
            if (std.mem.eql(u8, existing.package, member_package) and std.mem.eql(u8, existing.name, name)) {
                return error.InvalidManifest;
            }
        }
        try members.append(allocator, .{
            .package = member_package,
            .name = name,
            .effect = effect,
            .is_async = is_async,
            .has_future = has_future,
            .has_stream = has_stream,
            .has_resource = has_resource,
            .signature = signature,
        });
    }

    var lowerings = std.ArrayList(RawLowering).empty;
    errdefer lowerings.deinit(allocator);
    if (schema == 2) {
        const lowering_values = array_value(root.get("async_lowerings")) orelse return error.InvalidManifest;
        for (lowering_values.items) |value| {
            const object = object_value(value) orelse return error.InvalidManifest;
            const capability = string_value(object.get("capability")) orelse return error.InvalidManifest;
            const member = string_value(object.get("member")) orelse return error.InvalidManifest;
            const source_signature = string_value(object.get("source_signature")) orelse return error.InvalidManifest;
            const wit_package = string_value(object.get("wit_package")) orelse return error.InvalidManifest;
            const wit_world = string_value(object.get("wit_world")) orelse return error.InvalidManifest;
            const wit_interface = string_value(object.get("wit_interface")) orelse return error.InvalidManifest;
            const wit_member = string_value(object.get("wit_member")) orelse return error.InvalidManifest;
            const async_import_module = string_value(object.get("async_import_module")) orelse return error.InvalidManifest;
            const async_import_name = string_value(object.get("async_import_name")) orelse return error.InvalidManifest;
            const completion = string_value(object.get("completion")) orelse return error.InvalidManifest;
            const wit_sha256 = string_value(object.get("wit_sha256")) orelse return error.InvalidManifest;
            const hash = parse_hash(wit_sha256) orelse return error.InvalidManifest;
            const payload = try parse_payload(object.get("payload"));
            for (lowerings.items) |existing| {
                if (std.mem.eql(u8, existing.member, member) or
                    std.mem.eql(u8, existing.wit_member, wit_member)) return error.GeneratedWitManifestMismatch;
            }
            try lowerings.append(allocator, .{
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
                .wit_sha256 = hash,
                .payload = payload,
            });
        }
    } else if (root.get("async_lowerings") != null) {
        return error.GeneratedWitManifestMismatch;
    }

    return .{
        .tree = tree,
        .package = package,
        .world = world,
        .sha256 = manifest_sha256,
        .modules = try modules.toOwnedSlice(allocator),
        .hashes = try hashes.toOwnedSlice(allocator),
        .members = try members.toOwnedSlice(allocator),
        .lowerings = try lowerings.toOwnedSlice(allocator),
    };
}

fn validate_module_hashes(
    io: std.Io,
    allocator: std.mem.Allocator,
    parsed: *const Parsed,
    manifest_path: []const u8,
) Error!void {
    const base = std.fs.path.dirname(manifest_path) orelse return error.GeneratedWitManifestMismatch;
    for (parsed.hashes) |expected| {
        const path = std.fs.path.join(allocator, &.{ base, expected.path }) catch
            return error.GeneratedWitManifestMismatch;
        defer allocator.free(path);
        const source = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(16 * 1024 * 1024)) catch
            return error.GeneratedWitManifestMismatch;
        defer allocator.free(source);
        var actual: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(source, &actual, .{});
        if (!std.mem.eql(u8, &actual, &expected.hash)) return error.GeneratedWitManifestMismatch;
    }
}

fn validate_lowerings(
    allocator: std.mem.Allocator,
    module_name: []const u8,
    parsed: *const Parsed,
    hosts: []const HostDecl,
) Error!void {
    if (parsed.lowerings.len == 0) return;
    const interface = interface_name(module_name) orelse return error.GeneratedWitManifestMismatch;
    for (parsed.lowerings) |lowering| {
        const is_unit = std.mem.eql(u8, lowering.capability, "component-async-unit-v1");
        const is_scalar = std.mem.eql(u8, lowering.capability, "component-async-scalar-u32-v1");
        if (!is_unit and !is_scalar) return error.GeneratedWitManifestMismatch;
        if (is_unit) {
            if (!std.mem.eql(u8, lowering.member, "host.work") or
                !std.mem.eql(u8, lowering.source_signature, "() -> Future<nil>") or
                !std.mem.eql(u8, lowering.wit_package, "do:generic-async-runtime-probe@0.1.0") or
                !std.mem.eql(u8, lowering.wit_world, "probe") or
                !std.mem.eql(u8, lowering.wit_interface, "host") or
                !std.mem.eql(u8, lowering.wit_member, "work") or
                !std.mem.eql(u8, lowering.async_import_module, "do:generic-async-runtime-probe/host@0.1.0") or
                !std.mem.eql(u8, lowering.async_import_name, "[async-lower]work") or
                !std.mem.eql(u8, lowering.completion, "task-return") or
                lowering.payload != null) return error.GeneratedWitManifestMismatch;
        } else {
            const payload = lowering.payload orelse return error.GeneratedWitManifestMismatch;
            if (!std.mem.eql(u8, lowering.member, "host.completion") or
                !std.mem.eql(u8, lowering.source_signature, "() -> Future<u32>") or
                !std.mem.eql(u8, lowering.wit_package, "do:generic-async-scalar-probe@0.1.0") or
                !std.mem.eql(u8, lowering.wit_world, "probe") or
                !std.mem.eql(u8, lowering.wit_interface, "host") or
                !std.mem.eql(u8, lowering.wit_member, "completion") or
                !std.mem.eql(u8, lowering.async_import_module, "do:generic-async-scalar-probe/host@0.1.0") or
                !std.mem.eql(u8, lowering.async_import_name, "[async-lower][future-read-0]completion") or
                !std.mem.eql(u8, lowering.completion, "completion") or
                !std.mem.eql(u8, payload.core_type, "i32") or payload.offset != 12 or
                payload.byte_size != 4 or payload.alignment != 4 or
                !std.mem.eql(u8, payload.encoding, "core-u32")) return error.GeneratedWitManifestMismatch;
        }
        if (!std.mem.eql(u8, lowering.wit_package, parsed.package) or
            !std.mem.eql(u8, lowering.wit_world, parsed.world) or
            !std.mem.eql(u8, lowering.wit_interface, interface) or
            !member_name_matches(lowering.member, interface, lowering.wit_member) or
            !std.mem.eql(u8, lowering.wit_sha256[0..], parsed.sha256[0..])) return error.GeneratedWitManifestMismatch;

        const member = find_manifest_member(parsed.members, lowering.wit_package, interface, lowering.wit_member) orelse
            return error.GeneratedWitManifestMismatch;
        if (is_unit) {
            if (!member.is_async or member.has_future or member.has_stream or member.has_resource) {
                return error.GeneratedWitManifestMismatch;
            }
        } else if (member.is_async or !member.has_future or member.has_stream or member.has_resource) {
            return error.GeneratedWitManifestMismatch;
        }
        const expected_signature = normalized_text(allocator, member.signature) catch
            return error.GeneratedWitManifestMismatch;
        defer allocator.free(expected_signature);
        const source_signature = normalized_text(allocator, lowering.source_signature) catch
            return error.GeneratedWitManifestMismatch;
        defer allocator.free(source_signature);
        if (!std.mem.eql(u8, expected_signature, source_signature)) return error.GeneratedWitManifestMismatch;

        var host_count: usize = 0;
        for (hosts) |host| {
            if (std.mem.eql(u8, host.locator, lowering.async_import_module) and
                std.mem.eql(u8, host.member, lowering.wit_member)) host_count += 1;
        }
        if (host_count != 1) return error.GeneratedWitManifestMismatch;
    }
}

fn clone_lowerings_for_module(
    allocator: std.mem.Allocator,
    module_name: []const u8,
    lowerings: []const RawLowering,
) (Error || std.mem.Allocator.Error)!ValidatedManifest {
    const interface = if (lowerings.len == 0) null else interface_name(module_name) orelse return error.GeneratedWitManifestMismatch;
    var out = std.ArrayList(GeneratedAsyncLowering).empty;
    errdefer {
        for (out.items) |lowering| free_lowering(allocator, lowering);
        out.deinit(allocator);
    }
    for (lowerings) |lowering| {
        if (interface == null or !std.mem.eql(u8, lowering.wit_interface, interface.?)) continue;
        var owned = GeneratedAsyncLowering{
            .locator = "",
            .member = "",
            .source_signature = "",
            .wit_package = "",
            .wit_world = "",
            .wit_interface = "",
            .wit_member = "",
            .async_import_module = "",
            .async_import_name = "",
            .completion = "",
            .wit_sha256 = lowering.wit_sha256,
            .payload = null,
        };
        errdefer free_lowering(allocator, owned);
        owned.locator = try allocator.dupe(u8, lowering.async_import_module);
        owned.member = try allocator.dupe(u8, lowering.wit_member);
        owned.source_signature = try allocator.dupe(u8, lowering.source_signature);
        owned.wit_package = try allocator.dupe(u8, lowering.wit_package);
        owned.wit_world = try allocator.dupe(u8, lowering.wit_world);
        owned.wit_interface = try allocator.dupe(u8, lowering.wit_interface);
        owned.wit_member = try allocator.dupe(u8, lowering.wit_member);
        owned.async_import_module = try allocator.dupe(u8, lowering.async_import_module);
        owned.async_import_name = try allocator.dupe(u8, lowering.async_import_name);
        owned.completion = try allocator.dupe(u8, lowering.completion);
        if (lowering.payload) |payload| {
            owned.payload = try clone_payload(allocator, payload);
        }
        try out.append(allocator, owned);
        owned = .{
            .locator = "",
            .member = "",
            .source_signature = "",
            .wit_package = "",
            .wit_world = "",
            .wit_interface = "",
            .wit_member = "",
            .async_import_module = "",
            .async_import_name = "",
            .completion = "",
            .wit_sha256 = lowering.wit_sha256,
            .payload = null,
        };
    }
    return .{ .lowerings = try out.toOwnedSlice(allocator) };
}

fn free_lowering(allocator: std.mem.Allocator, lowering: GeneratedAsyncLowering) void {
    if (lowering.locator.len != 0) allocator.free(lowering.locator);
    if (lowering.member.len != 0) allocator.free(lowering.member);
    if (lowering.source_signature.len != 0) allocator.free(lowering.source_signature);
    if (lowering.wit_package.len != 0) allocator.free(lowering.wit_package);
    if (lowering.wit_world.len != 0) allocator.free(lowering.wit_world);
    if (lowering.wit_interface.len != 0) allocator.free(lowering.wit_interface);
    if (lowering.wit_member.len != 0) allocator.free(lowering.wit_member);
    if (lowering.async_import_module.len != 0) allocator.free(lowering.async_import_module);
    if (lowering.async_import_name.len != 0) allocator.free(lowering.async_import_name);
    if (lowering.completion.len != 0) allocator.free(lowering.completion);
    if (lowering.payload) |payload| {
        free_payload(allocator, payload);
    }
}

fn clone_payload(allocator: std.mem.Allocator, payload: GeneratedScalarPayload) !GeneratedScalarPayload {
    var owned = GeneratedScalarPayload{
        .core_type = "",
        .offset = payload.offset,
        .byte_size = payload.byte_size,
        .alignment = payload.alignment,
        .encoding = "",
    };
    errdefer free_payload(allocator, owned);
    owned.core_type = try allocator.dupe(u8, payload.core_type);
    owned.encoding = try allocator.dupe(u8, payload.encoding);
    return owned;
}

fn free_payload(allocator: std.mem.Allocator, payload: GeneratedScalarPayload) void {
    if (payload.core_type.len != 0) allocator.free(payload.core_type);
    if (payload.encoding.len != 0) allocator.free(payload.encoding);
}

fn find_manifest_member(
    members: []const Member,
    package: []const u8,
    interface: []const u8,
    function: []const u8,
) ?Member {
    for (members) |member| {
        if (!std.mem.eql(u8, member.package, package)) continue;
        if (member_name_matches(member.name, interface, function)) return member;
    }
    return null;
}

fn member_name_matches(name: []const u8, interface: []const u8, function: []const u8) bool {
    return name.len == interface.len + 1 + function.len and
        std.mem.startsWith(u8, name, interface) and
        name[interface.len] == '.' and
        std.mem.eql(u8, name[interface.len + 1 ..], function);
}

fn collect_host_decls(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    out: *std.ArrayList(HostDecl),
) !void {
    var resources = std.ArrayList([]const u8).empty;
    defer resources.deinit(allocator);
    collect_resource_names(allocator, tokens, &resources) catch return error.InvalidManifest;

    var depth: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (eq(tokens[i], "{")) {
            depth += 1;
            continue;
        }
        if (eq(tokens[i], "}")) {
            if (depth > 0) depth -= 1;
            continue;
        }
        if (depth != 0 or !line_start(tokens, i)) continue;
        if (i + 9 >= tokens.len or tokens[i].kind != .ident or !eq(tokens[i + 1], "=") or
            !eq(tokens[i + 2], "@") or !eq(tokens[i + 3], "host") or !eq(tokens[i + 4], "(") or
            tokens[i + 5].kind != .string or !eq(tokens[i + 6], ",") or tokens[i + 7].kind != .string or
            !eq(tokens[i + 8], ",") or !eq(tokens[i + 9], "(")) continue;

        const outer_close = find_matching(tokens, i + 4, "(", ")") orelse return error.InvalidManifest;
        const params_close = find_matching(tokens, i + 9, "(", ")") orelse return error.InvalidManifest;
        if (params_close + 2 >= outer_close or !eq(tokens[params_close + 1], "-") or !eq(tokens[params_close + 2], ">")) {
            return error.InvalidManifest;
        }
        const signature = try normalized_token_range(allocator, tokens, i + 9, outer_close);
        errdefer allocator.free(signature);
        var has_resource = false;
        var token_idx = i + 9;
        while (token_idx < outer_close) : (token_idx += 1) {
            if (tokens[token_idx].kind != .ident) continue;
            for (resources.items) |resource| {
                if (std.mem.eql(u8, tokens[token_idx].lexeme, resource)) {
                    has_resource = true;
                    break;
                }
            }
            if (has_resource) break;
        }
        try out.append(allocator, .{
            .locator = string_body(tokens[i + 5].lexeme) orelse return error.InvalidManifest,
            .member = string_body(tokens[i + 7].lexeme) orelse return error.InvalidManifest,
            .signature = signature,
            .has_future = params_close + 3 < outer_close and eq(tokens[params_close + 3], "Future"),
            .has_stream = params_close + 3 < outer_close and eq(tokens[params_close + 3], "Stream"),
            .has_resource = has_resource,
        });
    }
}

fn collect_resource_names(allocator: std.mem.Allocator, tokens: []const lexer.Token, out: *std.ArrayList([]const u8)) !void {
    var i: usize = 0;
    while (i + 4 < tokens.len) : (i += 1) {
        if (!line_start(tokens, i) or tokens[i].kind != .ident or !eq(tokens[i + 1], "=") or
            !eq(tokens[i + 2], "@") or !eq(tokens[i + 3], "wasi_resource") or !eq(tokens[i + 4], "(")) continue;
        try out.append(allocator, tokens[i].lexeme);
    }
}

fn validate_host_members(
    allocator: std.mem.Allocator,
    module_name: []const u8,
    parsed: *const Parsed,
    hosts: []const HostDecl,
) Error!void {
    const interface = interface_name(module_name) orelse return error.GeneratedWitManifestMismatch;
    var expected_count: usize = 0;
    for (parsed.members) |member| {
        if (!std.mem.startsWith(u8, member.name, interface) or
            member.name.len <= interface.len + 1 or member.name[interface.len] != '.') continue;
        for (hosts) |host| {
            if (member_matches_locator(member.package, host.locator)) {
                expected_count += 1;
                break;
            }
        }
    }
    if (expected_count != hosts.len) return error.GeneratedWitManifestMismatch;

    for (hosts) |host| {
        const member = find_member(parsed.members, host.locator, interface, host.member) orelse
            return error.GeneratedWitManifestMismatch;
        const expected = normalized_text(allocator, member.signature) catch
            return error.GeneratedWitManifestMismatch;
        defer allocator.free(expected);
        if (!std.mem.eql(u8, host.signature, expected)) return error.GeneratedWitManifestMismatch;
        // An async WIT function is emitted as Future<T>, but its `future` flag
        // is false; a normal WIT future has the same source shape with `async`
        // false and `future` true. This preserves both distinctions.
        const expected_future = host.has_future and !member.is_async;
        if (member.has_future != expected_future or member.has_stream != host.has_stream or
            member.has_resource != host.has_resource) return error.GeneratedWitManifestMismatch;
    }
}

fn find_member(members: []const Member, locator: []const u8, interface: []const u8, name: []const u8) ?Member {
    for (members) |member| {
        if (!member_matches_locator(member.package, locator)) continue;
        if (member.name.len <= interface.len + 1 or
            !std.mem.startsWith(u8, member.name, interface) or member.name[interface.len] != '.' or
            !std.mem.eql(u8, member.name[interface.len + 1 ..], name)) continue;
        return member;
    }
    return null;
}

fn member_matches_locator(package: []const u8, locator: []const u8) bool {
    const slash = std.mem.indexOfScalar(u8, locator, '/') orelse return false;
    const version_at = std.mem.lastIndexOfScalar(u8, locator, '@') orelse return false;
    if (version_at <= slash + 1 or version_at + 1 >= locator.len) return false;
    const package_prefix = locator[0..slash];
    const version = locator[version_at + 1 ..];
    return package.len == package_prefix.len + 1 + version.len and
        std.mem.startsWith(u8, package, package_prefix) and
        package[package_prefix.len] == '@' and
        std.mem.eql(u8, package[package_prefix.len + 1 ..], version);
}

fn interface_name(module_name: []const u8) ?[]const u8 {
    if (!std.mem.endsWith(u8, module_name, ".do")) return null;
    const stem = module_name[0 .. module_name.len - 3];
    const first = std.mem.indexOf(u8, stem, "__") orelse return null;
    const second = std.mem.indexOfPos(u8, stem, first + 2, "__") orelse return null;
    if (second <= first + 2) return null;
    return stem[first + 2 .. second];
}

fn find_matching(tokens: []const lexer.Token, start: usize, open: []const u8, close: []const u8) ?usize {
    var depth: usize = 0;
    var i = start;
    while (i < tokens.len) : (i += 1) {
        if (eq(tokens[i], open)) {
            depth += 1;
        } else if (eq(tokens[i], close)) {
            if (depth == 0) return null;
            depth -= 1;
            if (depth == 0) return i;
        }
    }
    return null;
}

fn normalized_token_range(allocator: std.mem.Allocator, tokens: []const lexer.Token, start: usize, end: usize) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    for (tokens[start..end]) |token| try out.appendSlice(allocator, token.lexeme);
    return out.toOwnedSlice(allocator);
}

fn normalized_text(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.ensureTotalCapacity(allocator, text.len);
    for (text) |ch| if (!std.ascii.isWhitespace(ch)) out.appendAssumeCapacity(ch);
    return out.toOwnedSlice(allocator);
}

fn line_start(tokens: []const lexer.Token, idx: usize) bool {
    return idx == 0 or tokens[idx - 1].line != tokens[idx].line;
}

fn eq(token: lexer.Token, text: []const u8) bool {
    return std.mem.eql(u8, token.lexeme, text);
}

fn string_body(text: []const u8) ?[]const u8 {
    if (text.len < 2 or text[0] != '"' or text[text.len - 1] != '"') return null;
    return text[1 .. text.len - 1];
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

fn parse_payload(value: ?std.json.Value) !?GeneratedScalarPayload {
    const actual = value orelse return null;
    return switch (actual) {
        .null => null,
        .object => |object| .{
            .core_type = string_value(object.get("core_type")) orelse return error.InvalidManifest,
            .offset = bounded_u32(object.get("offset")) orelse return error.InvalidManifest,
            .byte_size = bounded_u32(object.get("byte_size")) orelse return error.InvalidManifest,
            .alignment = bounded_u32(object.get("alignment")) orelse return error.InvalidManifest,
            .encoding = string_value(object.get("encoding")) orelse return error.InvalidManifest,
        },
        else => return error.InvalidManifest,
    };
}

fn contains_module(modules: []const []const u8, name: []const u8) bool {
    for (modules) |module| if (std.mem.eql(u8, module, name)) return true;
    return false;
}

fn valid_module_name(name: []const u8) bool {
    return name.len > 3 and std.mem.endsWith(u8, name, ".do") and
        std.mem.indexOfScalar(u8, name, '/') == null and
        std.mem.indexOfScalar(u8, name, '\\') == null and
        std.mem.indexOf(u8, name, "..") == null;
}

fn valid_hash_text(text: []const u8) bool {
    return parse_hash(text) != null;
}

fn parse_hash(text: []const u8) ?[32]u8 {
    if (text.len != 64) return null;
    var result: [32]u8 = undefined;
    for (0..32) |index| {
        const high = hex_value(text[index * 2]) orelse return null;
        const low = hex_value(text[index * 2 + 1]) orelse return null;
        result[index] = (high << 4) | low;
    }
    return result;
}

fn hex_value(ch: u8) ?u8 {
    if (ch >= '0' and ch <= '9') return ch - '0';
    if (ch >= 'a' and ch <= 'f') return ch - 'a' + 10;
    if (ch >= 'A' and ch <= 'F') return ch - 'A' + 10;
    return null;
}
