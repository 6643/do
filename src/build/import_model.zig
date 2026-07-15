const std = @import("std");
const lexer = @import("lexer.zig");

pub const ImportPrefix = enum {
    local,
    dep,
    std,
};

pub const ImportRef = struct {
    alias_idx: usize,
    target: []const u8,
    file_path: []const u8,
    prefix: ImportPrefix,
};

pub const ModuleRecord = struct {
    path: []const u8,
    source: ?[]const u8,
    owns_source: bool,
    tokens: []const lexer.Token,
    owns_tokens: bool,
};

pub const ModuleGraph = struct {
    allocator: std.mem.Allocator,
    dep_root: []const u8,
    modules: []ModuleRecord,

    pub fn deinit(self: *ModuleGraph) void {
        for (self.modules) |module| {
            if (module.owns_source) self.allocator.free(module.source.?);
            if (module.owns_tokens) self.allocator.free(module.tokens);
            self.allocator.free(module.path);
        }
        self.allocator.free(self.modules);
    }

    pub fn find_module(self: *const ModuleGraph, path: []const u8) ?usize {
        for (self.modules, 0..) |module, idx| {
            if (std.mem.eql(u8, module.path, path)) return idx;
        }
        return null;
    }
};
