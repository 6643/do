const std = @import("std");
const model = @import("model.zig");

pub fn render(allocator: std.mem.Allocator, binding: model.BindingModel) ![]u8 {
    var out = std.ArrayList(u8).empty;
    var packages = std.ArrayList(model.PackageDecl).empty;
    defer packages.deinit(allocator);
    if (binding.packages.len == 0) {
        try packages.append(allocator, binding.package);
    } else {
        try packages.appendSlice(allocator, binding.packages);
    }
    std.mem.sort(model.PackageDecl, packages.items, {}, less_than_package);

    try out.appendSlice(allocator, "schema=1\n");
    for (packages.items) |package| {
        try out.appendSlice(allocator, "package=");
        try append_package(allocator, &out, package);
        try out.append(allocator, '\n');
    }
    try out.appendSlice(allocator, "sha256=");
    const digits = "0123456789abcdef";
    for (binding.content_hash) |byte| {
        try out.append(allocator, digits[byte >> 4]);
        try out.append(allocator, digits[byte & 0x0f]);
    }
    return out.toOwnedSlice(allocator);
}

fn less_than_package(_: void, lhs: model.PackageDecl, rhs: model.PackageDecl) bool {
    const lhs_namespace = std.mem.order(u8, lhs.namespace, rhs.namespace);
    if (lhs_namespace != .eq) return lhs_namespace == .lt;
    const lhs_name = std.mem.order(u8, lhs.name, rhs.name);
    if (lhs_name != .eq) return lhs_name == .lt;
    if (lhs.version.major != rhs.version.major) return lhs.version.major < rhs.version.major;
    if (lhs.version.minor != rhs.version.minor) return lhs.version.minor < rhs.version.minor;
    if (lhs.version.patch != rhs.version.patch) return lhs.version.patch < rhs.version.patch;
    return std.mem.order(u8, lhs.version.prerelease, rhs.version.prerelease) == .lt;
}

fn append_package(allocator: std.mem.Allocator, out: *std.ArrayList(u8), package: model.PackageDecl) !void {
    try out.appendSlice(allocator, package.namespace);
    try out.append(allocator, ':');
    try out.appendSlice(allocator, package.name);
    try append_fmt(allocator, out, "@{d}.{d}.{d}", .{
        package.version.major,
        package.version.minor,
        package.version.patch,
    });
    if (package.version.prerelease.len != 0) {
        try out.append(allocator, '-');
        try out.appendSlice(allocator, package.version.prerelease);
    }
}

fn append_fmt(allocator: std.mem.Allocator, out: *std.ArrayList(u8), comptime format: []const u8, args: anytype) !void {
    const text = try std.fmt.allocPrint(allocator, format, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}
