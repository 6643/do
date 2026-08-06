const std = @import("std");
const lexer = @import("lexer.zig");
const model = @import("model.zig");
const parser = @import("parser.zig");

pub const ResolveError = error{
    AmbiguousPackage,
    AmbiguousDirectoryInput,
    DuplicateInterface,
    DuplicatePackage,
    DuplicateResource,
    DuplicateWorld,
    InterfaceNotFound,
    IncludeCycle,
    NoWitSource,
    UnresolvedUse,
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
    attach_package(@constCast(ast.interfaces), ast.package);
    attach_package_to_worlds(@constCast(ast.worlds), ast.package);
    const packages = try ast.arena.allocator().dupe(model.PackageDecl, &.{ast.package});
    const selected = try select_binding(
        ast.arena.allocator(),
        ast.package,
        packages,
        ast.worlds,
        ast.interfaces,
        source,
        requested_world,
    );

    return .{
        .arena = ast.arena,
        .source = source,
        .owns_source = false,
        .owned_sources = &[_][]const u8{},
        .package = ast.package,
        .packages = packages,
        .world = selected.world,
        .interfaces = selected.interfaces,
        .content_hash = selected.content_hash,
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
    binding.owned_sources = try binding.arena.allocator().dupe([]const u8, &.{source});
    return binding;
}

fn resolve_directory(
    io: std.Io,
    allocator: std.mem.Allocator,
    input_path: []const u8,
    requested_world: ?[]const u8,
) !model.BindingModel {
    var files = std.ArrayList(WitFile).empty;
    defer {
        for (files.items) |file| {
            allocator.free(file.relative);
            allocator.free(file.full_path);
        }
        files.deinit(allocator);
    }
    try collect_wit_files(io, allocator, input_path, "", &files);
    if (files.items.len == 0) return error.NoWitSource;
    std.mem.sort(WitFile, files.items, {}, less_than_file);

    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    var sources = std.ArrayList([]const u8).empty;
    var sources_transferred = false;
    defer {
        if (!sources_transferred) {
            for (sources.items) |source| allocator.free(source);
        }
        sources.deinit(allocator);
    }
    var root_package: ?model.PackageDecl = null;
    var packages = std.ArrayList(model.PackageDecl).empty;
    var interfaces = std.ArrayList(model.InterfaceDecl).empty;
    var worlds = std.ArrayList(model.WorldDecl).empty;

    for (files.items) |file| {
        const source = try std.Io.Dir.cwd().readFileAlloc(io, file.full_path, allocator, .limited(16 * 1024 * 1024));
        try sources.append(allocator, source);
        const document = try parser.parse_in_arena(arena.allocator(), source);
        if (file.is_root and root_package == null) root_package = document.package;
        if (file.is_root) {
            if (root_package) |expected| {
                if (!same_package(expected, document.package)) return error.DuplicatePackage;
            }
        }
        if (find_package(packages.items, document.package)) |existing| {
            if (!same_package(existing, document.package)) return error.DuplicatePackage;
        } else if (find_package_name(packages.items, document.package)) |existing| {
            if (!same_package(existing, document.package)) return error.DuplicatePackage;
        } else {
            try packages.append(arena.allocator(), document.package);
        }
        for (document.interfaces) |interface| {
            for (interfaces.items) |existing| {
                if (std.mem.eql(u8, existing.name, interface.name) and
                    same_package(existing.package orelse document.package, document.package)) return error.DuplicateInterface;
            }
            var owned_interface = interface;
            owned_interface.package = document.package;
            try interfaces.append(arena.allocator(), owned_interface);
        }
        for (document.worlds) |world| {
            for (worlds.items) |existing| {
                if (std.mem.eql(u8, existing.name, world.name) and
                    same_package(existing.package orelse document.package, document.package)) return error.DuplicateWorld;
            }
            var owned_world = world;
            owned_world.package = document.package;
            try worlds.append(arena.allocator(), owned_world);
        }
    }

    const package_decl = root_package orelse packages.items[0];
    const primary_source = sources.items[0];
    var selected = try select_binding(
        arena.allocator(),
        package_decl,
        packages.items,
        worlds.items,
        interfaces.items,
        primary_source,
        requested_world,
    );
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    for (files.items, sources.items) |file, source| {
        hasher.update(file.relative);
        hasher.update(&[_]u8{0});
        hasher.update(source);
        hasher.update(&[_]u8{0});
    }
    hasher.final(&selected.content_hash);
    const owned_sources = try arena.allocator().dupe([]const u8, sources.items);
    const binding = model.BindingModel{
        .arena = arena,
        .source = primary_source,
        .owns_source = true,
        .owned_sources = owned_sources,
        .package = package_decl,
        .packages = try arena.allocator().dupe(model.PackageDecl, packages.items),
        .world = selected.world,
        .interfaces = selected.interfaces,
        .content_hash = selected.content_hash,
    };
    for (sources.items) |source| {
        // The binding owns these buffers after returning; only the list backing
        // storage is temporary and is already copied into the arena above.
        _ = source;
    }
    sources_transferred = true;
    sources.clearRetainingCapacity();
    return binding;
}

const SelectedBinding = struct {
    world: model.WorldDecl,
    interfaces: []const model.InterfaceDecl,
    content_hash: [std.crypto.hash.sha2.Sha256.digest_length]u8,
};

const WitFile = struct {
    relative: []u8,
    full_path: []u8,
    is_root: bool,
};

fn select_binding(
    allocator: std.mem.Allocator,
    package: model.PackageDecl,
    packages: []const model.PackageDecl,
    worlds: []const model.WorldDecl,
    all_interfaces: []const model.InterfaceDecl,
    source: []const u8,
    requested_world: ?[]const u8,
) (ResolveError || std.mem.Allocator.Error)!SelectedBinding {
    try validate_references(allocator, packages, all_interfaces);
    const world = select_world(worlds, package, requested_world) orelse {
        if (requested_world == null and worlds.len > 1) return error.WorldRequired;
        return error.WorldNotFound;
    };

    var interfaces = std.ArrayList(model.InterfaceDecl).empty;
    for (world.imports) |import_decl| {
        const target = if (import_decl.target.len == 0) import_decl.name else import_decl.target;
        const interface_index = (try resolve_interface_index(target, package, packages, all_interfaces)) orelse return error.InterfaceNotFound;
        var resolved = all_interfaces[interface_index];
        validate_resources(resolved.resources) catch return error.DuplicateResource;
        annotate_interface(&resolved);
        try interfaces.append(allocator, resolved);
    }

    var content_hash: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(source, &content_hash, .{});
    return .{
        .world = world,
        .interfaces = try interfaces.toOwnedSlice(allocator),
        .content_hash = content_hash,
    };
}

fn less_than_file(_: void, lhs: WitFile, rhs: WitFile) bool {
    return std.mem.order(u8, lhs.relative, rhs.relative) == .lt;
}

fn same_package(lhs: model.PackageDecl, rhs: model.PackageDecl) bool {
    return std.mem.eql(u8, lhs.namespace, rhs.namespace) and
        std.mem.eql(u8, lhs.name, rhs.name) and
        lhs.version.major == rhs.version.major and
        lhs.version.minor == rhs.version.minor and
        lhs.version.patch == rhs.version.patch and
        std.mem.eql(u8, lhs.version.prerelease, rhs.version.prerelease);
}

fn find_package(packages: []const model.PackageDecl, expected: model.PackageDecl) ?model.PackageDecl {
    for (packages) |candidate| {
        if (same_package(candidate, expected)) return candidate;
    }
    return null;
}

fn find_package_name(packages: []const model.PackageDecl, expected: model.PackageDecl) ?model.PackageDecl {
    for (packages) |candidate| {
        if (std.mem.eql(u8, candidate.namespace, expected.namespace) and
            std.mem.eql(u8, candidate.name, expected.name)) return candidate;
    }
    return null;
}

fn attach_package(interfaces: []model.InterfaceDecl, package: model.PackageDecl) void {
    for (interfaces) |*interface| interface.package = package;
}

fn attach_package_to_worlds(worlds: []model.WorldDecl, package: model.PackageDecl) void {
    for (worlds) |*world| world.package = package;
}

fn collect_wit_files(
    io: std.Io,
    allocator: std.mem.Allocator,
    directory: []const u8,
    relative_prefix: []const u8,
    files: *std.ArrayList(WitFile),
) !void {
    var dir = try std.Io.Dir.cwd().openDir(io, directory, .{ .iterate = true, .access_sub_paths = true });
    defer dir.close(io);
    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        const relative = try std.fs.path.join(allocator, &.{ relative_prefix, entry.name });
        errdefer allocator.free(relative);
        const full_path = try std.fs.path.join(allocator, &.{ directory, entry.name });
        errdefer allocator.free(full_path);
        switch (entry.kind) {
            .file => {
                if (!std.mem.endsWith(u8, entry.name, ".wit")) {
                    allocator.free(relative);
                    allocator.free(full_path);
                    continue;
                }
                try files.append(allocator, .{
                    .relative = relative,
                    .full_path = full_path,
                    .is_root = relative_prefix.len == 0,
                });
            },
            .directory => {
                try collect_wit_files(io, allocator, full_path, relative, files);
                allocator.free(relative);
                allocator.free(full_path);
            },
            else => {
                allocator.free(relative);
                allocator.free(full_path);
            },
        }
    }
}

fn validate_references(
    allocator: std.mem.Allocator,
    packages: []const model.PackageDecl,
    interfaces: []const model.InterfaceDecl,
) (ResolveError || std.mem.Allocator.Error)!void {
    for (interfaces) |interface| {
        const package = interface.package orelse return error.UnresolvedUse;
        for (interface.uses) |use_decl| {
            if ((try resolve_interface_index(use_decl.target, package, packages, interfaces)) == null) return error.UnresolvedUse;
        }
        for (interface.includes) |include_decl| {
            if ((try resolve_interface_index(include_decl.target, package, packages, interfaces)) == null) return error.UnresolvedUse;
        }
    }

    var path = std.ArrayList(usize).empty;
    defer path.deinit(allocator);
    for (interfaces, 0..) |_, index| {
        try visit_include(index, packages, interfaces, allocator, &path);
    }
}

fn visit_include(
    index: usize,
    packages: []const model.PackageDecl,
    interfaces: []const model.InterfaceDecl,
    allocator: std.mem.Allocator,
    path: *std.ArrayList(usize),
) (ResolveError || std.mem.Allocator.Error)!void {
    for (path.items) |ancestor| {
        if (ancestor == index) return error.IncludeCycle;
    }
    const interface = interfaces[index];
    try path.append(allocator, index);
    defer _ = path.pop();
    const package = interface.package orelse return error.UnresolvedUse;
    for (interface.includes) |include_decl| {
        const target = (try resolve_interface_index(include_decl.target, package, packages, interfaces)) orelse return error.UnresolvedUse;
        try visit_include(target, packages, interfaces, allocator, path);
    }
}

fn reference_base(raw: []const u8) ?[]const u8 {
    var target = std.mem.trim(u8, raw, " \t\r\n");
    if (target.len == 0) return null;
    if (target[0] == '"') return null;
    var end = target.len;
    for ([_]u8{ '.', '{' }) |delimiter| {
        if (std.mem.indexOfScalar(u8, target, delimiter)) |index| end = @min(end, index);
    }
    target = std.mem.trim(u8, target[0..end], " \t\r\n");
    return if (target.len == 0) null else target;
}

fn resolve_interface_index(
    raw: []const u8,
    current_package: model.PackageDecl,
    packages: []const model.PackageDecl,
    interfaces: []const model.InterfaceDecl,
) (ResolveError || std.mem.Allocator.Error)!?usize {
    const target = reference_base(raw) orelse return null;
    const package = if (parse_qualified_package(target)) |qualified| blk: {
        const requested = qualified.version orelse null;
        var match: ?model.PackageDecl = null;
        for (packages) |candidate| {
            if (!std.mem.eql(u8, candidate.namespace, qualified.namespace) or
                !std.mem.eql(u8, candidate.name, qualified.package)) continue;
            if (requested) |version| {
                if (!same_version(candidate.version, version)) continue;
            }
            if (match != null) return error.AmbiguousPackage;
            match = candidate;
        }
        break :blk match orelse return null;
    } else current_package;
    const interface_name = if (parse_qualified_package(target)) |qualified| qualified.interface else target;
    return find_interface_index(interfaces, package, interface_name);
}

const QualifiedPackage = struct {
    namespace: []const u8,
    package: []const u8,
    interface: []const u8,
    version: ?model.Version,
};

fn parse_qualified_package(raw: []const u8) ?QualifiedPackage {
    const colon = std.mem.indexOfScalar(u8, raw, ':') orelse return null;
    const slash = std.mem.indexOfScalarPos(u8, raw, colon + 1, '/') orelse return null;
    if (colon == 0 or slash <= colon + 1 or slash + 1 >= raw.len) return null;
    const namespace = raw[0..colon];
    const package = raw[colon + 1 .. slash];
    var interface = raw[slash + 1 ..];
    var version: ?model.Version = null;
    if (std.mem.indexOfScalar(u8, interface, '@')) |at| {
        version = parse_version(interface[at + 1 ..]) orelse return null;
        interface = interface[0..at];
    }
    if (interface.len == 0) return null;
    return .{ .namespace = namespace, .package = package, .interface = interface, .version = version };
}

fn parse_version(raw: []const u8) ?model.Version {
    const prerelease_start = std.mem.indexOfScalar(u8, raw, '-') orelse raw.len;
    const numeric = raw[0..prerelease_start];
    const prerelease = if (prerelease_start < raw.len) raw[prerelease_start + 1 ..] else "";
    if (numeric.len == 0 or (prerelease_start < raw.len and prerelease.len == 0)) return null;
    var parts = std.mem.splitScalar(u8, numeric, '.');
    const major = std.fmt.parseInt(u32, parts.next() orelse return null, 10) catch return null;
    const minor = std.fmt.parseInt(u32, parts.next() orelse return null, 10) catch return null;
    const patch = std.fmt.parseInt(u32, parts.next() orelse return null, 10) catch return null;
    if (parts.next() != null) return null;
    return .{ .major = major, .minor = minor, .patch = patch, .prerelease = prerelease };
}

fn same_version(lhs: model.Version, rhs: model.Version) bool {
    return lhs.major == rhs.major and lhs.minor == rhs.minor and lhs.patch == rhs.patch and
        std.mem.eql(u8, lhs.prerelease, rhs.prerelease);
}

fn select_world(worlds: []const model.WorldDecl, package: model.PackageDecl, requested: ?[]const u8) ?model.WorldDecl {
    if (requested) |name| {
        for (worlds) |world| {
            if (std.mem.eql(u8, world.name, name) and same_package(world.package orelse package, package)) return world;
        }
        return null;
    }
    var selected: ?model.WorldDecl = null;
    for (worlds) |world| {
        if (!same_package(world.package orelse package, package)) continue;
        if (selected != null) return null;
        selected = world;
    }
    return selected;
}

fn find_interface_index(interfaces: []const model.InterfaceDecl, package: model.PackageDecl, name: []const u8) ?usize {
    for (interfaces, 0..) |interface, index| {
        if (std.mem.eql(u8, interface.name, name) and same_package(interface.package orelse package, package)) return index;
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
