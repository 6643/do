const std = @import("std");
const lexer = @import("lexer.zig");
const model = @import("model.zig");
const parser = @import("parser.zig");

pub const ResolveError = error{
    AmbiguousDirectoryInput,
    DuplicateResource,
    InterfaceNotFound,
    NoWitSource,
    WorldNotFound,
    WorldRequired,
};

pub fn resolve_input(
    io: std.Io,
    allocator: std.mem.Allocator,
    input_path: []const u8,
    requested_world: ?[]const u8,
) !model.BindingModel {
    const stat = try std.Io.Dir.cwd().statFile(io, input_path, .{});
    if (stat.kind != .directory) return resolve_file(io, allocator, input_path, requested_world);
    return resolve_directory(io, allocator, input_path, requested_world);
}

pub fn resolve_source(
    allocator: std.mem.Allocator,
    source: []const u8,
    requested_world: ?[]const u8,
) (ResolveError || parser.ParseError || lexer.LexerError || std.mem.Allocator.Error)!model.BindingModel {
    var ast = try parser.parse(allocator, source);
    errdefer ast.deinit();

    const world = select_world(ast.worlds, requested_world) orelse {
        if (requested_world == null and ast.worlds.len > 1) return error.WorldRequired;
        return error.WorldNotFound;
    };

    var interfaces = std.ArrayList(model.InterfaceDecl).empty;
    for (world.imports) |import_decl| {
        var interface = find_interface(ast.interfaces, import_decl.name) orelse return error.InterfaceNotFound;
        validate_resources(interface.resources) catch return error.DuplicateResource;
        annotate_interface(&interface);
        try interfaces.append(ast.arena.allocator(), interface);
    }

    var content_hash: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(source, &content_hash, .{});

    return .{
        .arena = ast.arena,
        .source = source,
        .owns_source = false,
        .package = ast.package,
        .world = world,
        .interfaces = try interfaces.toOwnedSlice(ast.arena.allocator()),
        .content_hash = content_hash,
    };
}

pub fn resolve_file(
    io: std.Io,
    allocator: std.mem.Allocator,
    path: []const u8,
    requested_world: ?[]const u8,
) !model.BindingModel {
    const source = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(16 * 1024 * 1024));
    errdefer allocator.free(source);
    var binding = try resolve_source(allocator, source, requested_world);
    binding.source = source;
    binding.owns_source = true;
    return binding;
}

fn resolve_directory(
    io: std.Io,
    allocator: std.mem.Allocator,
    input_path: []const u8,
    requested_world: ?[]const u8,
) !model.BindingModel {
    var dir = try std.Io.Dir.cwd().openDir(io, input_path, .{ .iterate = true, .access_sub_paths = true });
    defer dir.close(io);

    var preferred: ?[]const u8 = null;
    var only_wit: ?[]const u8 = null;
    var wit_count: usize = 0;
    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".wit")) continue;
        wit_count += 1;
        if (std.mem.eql(u8, entry.name, "world.wit") or std.mem.eql(u8, entry.name, "worlds.wit")) {
            preferred = entry.name;
        }
        only_wit = entry.name;
    }

    if (preferred == null) {
        if (wit_count == 0) return error.NoWitSource;
        if (wit_count != 1) return error.AmbiguousDirectoryInput;
    }
    const selected = preferred orelse only_wit orelse return error.NoWitSource;
    const selected_path = try std.fs.path.join(allocator, &.{ input_path, selected });
    defer allocator.free(selected_path);
    return resolve_file(io, allocator, selected_path, requested_world);
}

fn select_world(worlds: []const model.WorldDecl, requested: ?[]const u8) ?model.WorldDecl {
    if (requested) |name| {
        for (worlds) |world| {
            if (std.mem.eql(u8, world.name, name)) return world;
        }
        return null;
    }
    if (worlds.len != 1) return null;
    return worlds[0];
}

fn find_interface(interfaces: []const model.InterfaceDecl, name: []const u8) ?model.InterfaceDecl {
    for (interfaces) |interface| {
        if (std.mem.eql(u8, interface.name, name)) return interface;
    }
    return null;
}

fn validate_resources(resources: []const model.ResourceDecl) ResolveError!void {
    var index: usize = 0;
    while (index < resources.len) : (index += 1) {
        var next = index + 1;
        while (next < resources.len) : (next += 1) {
            if (std.mem.eql(u8, resources[index].name, resources[next].name)) return error.DuplicateResource;
        }
    }
}

fn annotate_interface(interface: *model.InterfaceDecl) void {
    for (@constCast(interface.functions)) |*function| {
        var has_resource = false;
        for (@constCast(function.params)) |*param| {
            annotate_type(param.type_ref, interface.resources, &has_resource);
        }
        if (function.result) |result| annotate_type(result, interface.resources, &has_resource);
        function.effects.has_resource = has_resource;
    }
    for (@constCast(interface.aliases)) |*alias| {
        var ignored = false;
        annotate_type(alias.type_ref, interface.resources, &ignored);
    }
    for (@constCast(interface.records)) |*record| {
        for (@constCast(record.fields)) |*field| {
            var ignored = false;
            annotate_type(field.type_ref, interface.resources, &ignored);
        }
    }
}

fn annotate_type(type_ref: *model.TypeRef, resources: []const model.ResourceDecl, has_resource: *bool) void {
    if (model.type_is_resource(type_ref, resources)) {
        type_ref.ownership = .owned;
        has_resource.* = true;
    }
    if (type_ref.kind == .own) {
        type_ref.ownership = .owned;
        has_resource.* = true;
    } else if (type_ref.kind == .borrow) {
        type_ref.ownership = .borrowed;
        has_resource.* = true;
    }
    for (@constCast(type_ref.args)) |arg| annotate_type(arg, resources, has_resource);
}
