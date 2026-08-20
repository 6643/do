//! Private manifest-backed entry point for bounded GC Component marshalling.
//!
//! The descriptor id is the only host/WIT identity supplied by callers. The
//! loader owns source, package, signature, canonical-import, and hash checks;
//! this wrapper only connects that verified request to the measured emitter.
const std = @import("std");
const marshal = @import("codegen_component_marshal_plan.zig");
const descriptor_loader = @import("codegen_component_descriptor_manifest.zig");
const marshal_route = @import("codegen_component_marshal_route.zig");

pub fn emit_sync_marshal_module_from_manifest(
    io: std.Io,
    allocator: std.mem.Allocator,
    repository_root: []const u8,
    manifest_path: []const u8,
    descriptor_id: []const u8,
    measured: marshal.MeasuredNode,
    canonical_u64_arg: ?u64,
) ![]u8 {
    return emit_sync_marshal_module_from_manifest_with_options(
        io,
        allocator,
        repository_root,
        manifest_path,
        descriptor_id,
        measured,
        canonical_u64_arg,
        false,
    );
}

pub fn emit_sync_marshal_module_from_manifest_with_options(
    io: std.Io,
    allocator: std.mem.Allocator,
    repository_root: []const u8,
    manifest_path: []const u8,
    descriptor_id: []const u8,
    measured: marshal.MeasuredNode,
    canonical_u64_arg: ?u64,
    emit_realloc_counters: bool,
) ![]u8 {
    var loaded = try descriptor_loader.load_request(
        io,
        allocator,
        repository_root,
        manifest_path,
        descriptor_id,
        measured,
        canonical_u64_arg,
    );
    defer loaded.deinit();
    loaded.request.emit_realloc_counters = emit_realloc_counters;
    return marshal_route.emit_sync_marshal_module_from_wit_source(allocator, loaded.request);
}
