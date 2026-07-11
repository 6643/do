const std = @import("std");

pub const DepRoot = struct {
    path: []const u8,
    owned: bool,

    pub fn deinit(self: DepRoot, allocator: std.mem.Allocator) void {
        if (self.owned) allocator.free(self.path);
    }
};

pub fn resolveDepRoot(allocator: std.mem.Allocator, environ_map: *std.process.Environ.Map) !DepRoot {
    if (environ_map.get("DO_LIB_ROOT")) |path| {
        return .{ .path = path, .owned = false };
    }

    const home = environ_map.get("HOME") orelse ".";
    return .{
        .path = try std.fs.path.join(allocator, &.{ home, ".do", "lib" }),
        .owned = true,
    };
}

test "resolveDepRoot prefers DO_LIB_ROOT" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("DO_LIB_ROOT", "deps/lib");

    const dep_root = try resolveDepRoot(std.testing.allocator, &env);
    defer dep_root.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("deps/lib", dep_root.path);
    try std.testing.expect(!dep_root.owned);
}
