const std = @import("std");
const lexer = @import("lexer.zig");
const module_graph = @import("module_graph.zig");
const import_resolution = @import("import_resolution.zig");

pub const ModuleRecord = module_graph.ModuleRecord;
pub const ModuleGraph = module_graph.ModuleGraph;
pub const ErrorSite = import_resolution.ErrorSite;

pub fn take_last_error_site() ?ErrorSite {
    return import_resolution.take_last_error_site();
}

pub fn check(
    io: std.Io,
    allocator: std.mem.Allocator,
    input_path: []const u8,
    tokens: []const lexer.Token,
    dep_root: []const u8,
) !void {
    return import_resolution.check(io, allocator, input_path, tokens, dep_root);
}

pub fn check_and_load(
    io: std.Io,
    allocator: std.mem.Allocator,
    input_path: []const u8,
    tokens: []const lexer.Token,
    dep_root: []const u8,
) !ModuleGraph {
    return import_resolution.check_and_load(io, allocator, input_path, tokens, dep_root);
}
