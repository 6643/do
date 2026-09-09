//! Production code-generation API.
//!
//! This module is deliberately GC-only.  The historical emitter and its ARC
//! helpers remain reachable only from the test-side equivalence oracle; the
//! installed compiler enters this module instead.

const std = @import("std");
const codegen_component_async = @import("codegen_component_async.zig");
const codegen_component_async_call = @import("codegen_component_async_call.zig");
const codegen_component_async_host_arg = @import("codegen_component_async_host_arg.zig");
const codegen_component_async_host_arg_plan = @import("codegen_component_async_host_arg_plan.zig");
const codegen_component_async_map = @import("codegen_component_async_map.zig");
const codegen_component_async_map_plan = @import("codegen_component_async_map_plan.zig");
const codegen_component_cabi_realloc = @import("codegen_component_cabi_realloc.zig");
const codegen_component_future_owned = @import("codegen_component_future_owned.zig");
const codegen_component_future_owned_plan = @import("codegen_component_future_owned_plan.zig");
const codegen_component_resource_async = @import("codegen_component_resource_async.zig");
const codegen_component_resource_probe = @import("codegen_component_resource_probe.zig");
const codegen_component_wasi_filesystem_preopen = @import("codegen_component_wasi_filesystem_preopen.zig");
const codegen_component_wasi_sockets = @import("codegen_component_wasi_sockets.zig");
const codegen_gc_core = @import("codegen_gc_core.zig");
const codegen_gc_diagnostic_compat = @import("codegen_gc_diagnostic_compat.zig");
const codegen_gc_sync = @import("codegen_gc_sync.zig");
const codegen_host_imports = @import("codegen_host_imports.zig");
const codegen_imports = @import("codegen_imports.zig");
const codegen_generic_async = @import("codegen_emit_generic_async.zig");
const codegen_task_bridge = @import("codegen_task_bridge.zig");
const codegen_model = @import("codegen_model.zig");
const codegen_wasi_registry = @import("codegen_wasi_registry.zig");
const codegen_p3_wait_for = @import("codegen_p3_wait_for.zig");
const generated_text = @import("codegen_text.zig");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const wat_component_metadata = @import("wat_component_metadata.zig");

pub const EmitOptions = codegen_model.EmitOptions;
pub const CodegenError = codegen_model.CodegenError;
pub const GcSyncHostWitRoute = codegen_model.GcSyncHostWitRoute;

pub const emit_p3_wait_for_wit = codegen_p3_wait_for.emit_component_wit_for_tokens;
pub const emit_p3_async_map_component_wit = codegen_component_async_map.emit_component_wit;
pub const emit_p3_async_call_component_wit = codegen_component_async_call.emit_component_wit;
pub const emit_p3_owned_future_component_wit = codegen_component_future_owned.emit_component_wit;
pub const emit_p3_async_host_arg_component_wit = codegen_component_async_host_arg.emit_component_wit;
pub const emit_p3_resource_probe_wit = codegen_component_resource_probe.emit_component_wit;
pub const emit_p3_wasi_filesystem_preopen_wit = codegen_component_wasi_filesystem_preopen.emit_component_wit;
pub const emit_p3_wasi_sockets_create_bind_drop_wit = codegen_component_wasi_sockets.emit_component_wit;
pub const emit_p3_resource_async_wit = codegen_component_resource_async.emit_component_wit;
pub const emit_p3_async_component_wit = codegen_component_async.emit_component_wit_with_graph;
pub const requires_p3_http_wit_package = codegen_component_async.requires_http_wit_package;

pub fn emit_wat(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) ![]u8 {
    return emit_wat_with_options(allocator, program, tokens, module_graph, .{});
}

pub fn emit_wat_with_options(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
    options: EmitOptions,
) ![]u8 {
    if (options.backend != .gc) return error.UnsupportedGcBackendRoute;

    if (options.p3_async_map_component) {
        var plan = try codegen_component_async_map_plan.analyze(allocator, tokens);
        defer plan.deinit(allocator);
        return codegen_component_async_map.emit_component_wat(allocator, plan);
    }
    if (options.p3_resource_probe_component)
        return finalize_component_wat(allocator, codegen_component_resource_probe.emit_component_wat(allocator, program, tokens, module_graph));
    if (options.p3_wasi_filesystem_preopen_component)
        return finalize_component_wat(allocator, codegen_component_wasi_filesystem_preopen.emit_component_wat(allocator, program, tokens, module_graph));
    if (options.p3_wasi_sockets_create_bind_drop_component)
        return finalize_component_wat(allocator, codegen_component_wasi_sockets.emit_component_wat(allocator, program, tokens, module_graph));
    if (options.p3_resource_async_component)
        return finalize_component_wat(allocator, codegen_component_resource_async.emit_component_wat(allocator, program, tokens, module_graph));
    if (options.p3_async_call_component) {
        var plan = try codegen_component_async.analyze_async_call_component(allocator, tokens);
        defer plan.deinit(allocator);
        return codegen_component_async_call.emit_component_wat(allocator, plan);
    }
    if (options.p3_async_host_arg_component) {
        var plan = try codegen_component_async_host_arg_plan.analyze(allocator, tokens);
        defer plan.deinit(allocator);
        return codegen_component_async_host_arg.emit_component_wat(allocator, plan);
    }
    if (options.p3_owned_future_component) {
        var plan = try codegen_component_future_owned_plan.analyze(allocator, tokens);
        defer plan.deinit(allocator);
        return codegen_component_future_owned.emit_component_wat(allocator, plan);
    }
    if (options.p3_async_component_v2)
        return codegen_component_async.emit_component_wat_v2(allocator, program, tokens, module_graph);
    if (options.p3_async_v2_scalar_i64_component)
        return finalize_component_wat(allocator, codegen_component_async.emit_component_wat_v2_scalar_i64(allocator, program, tokens, module_graph orelse return error.UnsupportedP3AsyncComponent));
    if (options.p3_wasi_filesystem_stat_component) {
        const target = codegen_component_async.target_for_tokens_with_graph(allocator, tokens, module_graph) catch
            return error.UnsupportedP3AsyncComponent;
        if (target != .wasi_filesystem_stat) return error.UnsupportedP3AsyncComponent;
        return codegen_component_async.emit_component_wat(allocator, program, tokens, module_graph);
    }
    if (options.p3_async_component)
        return codegen_component_async.emit_component_wat(allocator, program, tokens, module_graph);
    if (options.gc_core)
        return codegen_gc_core.emit_gc_core_wat(allocator, program, tokens);

    if (options.p3_wait_for_component)
        return finalize_component_wat(allocator, codegen_p3_wait_for.emit_component_wat(allocator, program, tokens, module_graph));
    if (try codegen_task_bridge.emit_if_supported(allocator, program, tokens)) |wat| return wat;
    if (try codegen_generic_async.emit_if_supported(allocator, program, tokens, module_graph)) |wat| return wat;
    if (program_requires_async_lowering(program, tokens, module_graph)) return error.AsyncLoweringUnavailable;
    if (options.host_export) {
        try codegen_gc_diagnostic_compat.validate_host_export_callbacks(allocator, tokens);
        return error.UnsupportedGcBackendRoute;
    }

    validate_gc_sync_host_uses(allocator, tokens, module_graph) catch |err| {
        return codegen_gc_diagnostic_compat.map_gc_rejection(tokens, err) orelse err;
    };
    const gc_wat = emit_checked_gc_sync(allocator, program, tokens, module_graph, options.gc_sync_host_wit_route) catch |err| {
        return codegen_gc_diagnostic_compat.map_gc_rejection(tokens, err) orelse err;
    };
    defer allocator.free(gc_wat);
    return add_gc_wasi_metadata(allocator, gc_wat, tokens, module_graph);
}

fn validate_gc_sync_host_uses(
    allocator: std.mem.Allocator,
    entry_tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) !void {
    var host_imports = std.ArrayList(codegen_model.HostImport).empty;
    defer {
        codegen_host_imports.free_host_imports(allocator, host_imports.items);
        host_imports.deinit(allocator);
    }
    try codegen_host_imports.collect_env_host_imports(allocator, entry_tokens, &host_imports);
    if (module_graph) |graph| {
        try codegen_host_imports.collect_env_host_imports_from_modules(
            allocator,
            graph.modules,
            entry_tokens,
            &host_imports,
        );
    }
    try codegen_imports.validate_host_import_build_uses(entry_tokens, host_imports.items);

    var wasi_imports = std.ArrayList(codegen_wasi_registry.WasiHostImport).empty;
    defer {
        codegen_wasi_registry.free_wasi_host_imports(allocator, wasi_imports.items);
        wasi_imports.deinit(allocator);
    }
    if (module_graph) |graph| {
        try codegen_wasi_registry.collect_wasi_host_imports_from_modules(
            allocator,
            graph.modules,
            entry_tokens,
            &wasi_imports,
        );
    } else {
        try codegen_wasi_registry.collect_wasi_host_imports(
            allocator,
            entry_tokens,
            codegen_wasi_registry.WASI_BINDING_ENTRY_SOURCE,
            &wasi_imports,
        );
    }

    var entry_wasi_imports = std.ArrayList(codegen_wasi_registry.WasiHostImport).empty;
    defer {
        codegen_wasi_registry.free_wasi_host_imports(allocator, entry_wasi_imports.items);
        entry_wasi_imports.deinit(allocator);
    }
    try codegen_wasi_registry.collect_wasi_host_imports(
        allocator,
        entry_tokens,
        codegen_wasi_registry.WASI_BINDING_ENTRY_SOURCE,
        &entry_wasi_imports,
    );
    try codegen_wasi_registry.validate_wasi_host_import_build_uses(entry_tokens, entry_wasi_imports.items);
    if (module_graph) |graph| {
        try codegen_imports.validate_reachable_wasi_host_import_build_uses(allocator, entry_tokens, graph);
    }
}

pub fn emit_test_wat(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) ![]u8 {
    const raw_wat = codegen_gc_sync.emit_gc_wat_for_supported_tests(allocator, program, tokens, module_graph) catch |err| {
        if (codegen_gc_sync.is_gc_sync_admission_rejection(err)) return error.UnsupportedGcBackendRoute;
        return err;
    };
    defer allocator.free(raw_wat);
    return add_backend_marker(allocator, raw_wat, "gc");
}

pub const emit_gc_wat_for_supported_program = codegen_gc_sync.emit_gc_wat_for_supported_program;

pub fn program_requires_async_lowering(
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) bool {
    for (program.func_sigs) |sig| {
        if (sig.is_async or sig.contains_await or sig.resumable) return true;
    }
    if (tokens_require_async_lowering(tokens)) return true;
    if (module_graph) |graph| {
        for (graph.modules) |module| {
            if (tokens_require_async_lowering(module.tokens)) return true;
        }
    }
    return false;
}

fn tokens_require_async_lowering(tokens: []const lexer.Token) bool {
    for (tokens, 0..) |token, idx| {
        if (std.mem.eql(u8, token.lexeme, "async")) return true;
        if (std.mem.eql(u8, token.lexeme, "await_all") or std.mem.eql(u8, token.lexeme, "await_any")) return true;
        if (!std.mem.eql(u8, token.lexeme, "@") or idx + 1 >= tokens.len) continue;
        if (std.mem.eql(u8, tokens[idx + 1].lexeme, "async") or
            std.mem.eql(u8, tokens[idx + 1].lexeme, "await") or
            std.mem.eql(u8, tokens[idx + 1].lexeme, "cancel")) return true;
    }
    return false;
}

fn emit_checked_gc_sync(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
    gc_host_route: ?*const GcSyncHostWitRoute,
) ![]u8 {
    const raw_wat = if (gc_host_route) |route|
        try codegen_gc_sync.emit_gc_wat_for_supported_program_with_host_route(allocator, program, tokens, module_graph, route)
    else
        try codegen_gc_sync.emit_gc_wat_for_supported_program(allocator, program, tokens, module_graph);
    defer allocator.free(raw_wat);
    const wat = try add_backend_marker(allocator, raw_wat, "gc");
    errdefer allocator.free(wat);
    const arc_marker = "__" ++ "arc_";
    if (std.mem.indexOf(u8, wat, arc_marker) != null) return error.GcSyncOutputContainsArc;
    return wat;
}

fn add_backend_marker(allocator: std.mem.Allocator, wat: []const u8, backend: []const u8) ![]u8 {
    const module_prefix = "(module\n";
    if (!std.mem.startsWith(u8, wat, module_prefix)) return error.InvalidBackendModule;
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, module_prefix);
    try generated_text.append_fmt(allocator, &out, "  ;; backend={[backend]s}\n", .{ .backend = backend });
    try out.appendSlice(allocator, wat[module_prefix.len..]);
    return out.toOwnedSlice(allocator);
}

fn add_gc_wasi_metadata(
    allocator: std.mem.Allocator,
    wat: []const u8,
    entry_tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) ![]u8 {
    const module_prefix = "(module\n";
    if (!std.mem.startsWith(u8, wat, module_prefix)) return error.InvalidBackendModule;

    var wasi_imports = std.ArrayList(codegen_wasi_registry.WasiHostImport).empty;
    defer {
        codegen_wasi_registry.free_wasi_host_imports(allocator, wasi_imports.items);
        wasi_imports.deinit(allocator);
    }
    if (module_graph) |graph| {
        try codegen_wasi_registry.collect_wasi_host_imports_from_modules(
            allocator,
            graph.modules,
            entry_tokens,
            &wasi_imports,
        );
    } else {
        try codegen_wasi_registry.collect_wasi_host_imports(
            allocator,
            entry_tokens,
            codegen_wasi_registry.WASI_BINDING_ENTRY_SOURCE,
            &wasi_imports,
        );
    }

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, module_prefix);

    // Keep the backend marker first, then place imports before GC type and
    // function definitions so the generated module retains the canonical
    // core-import ordering used by the legacy WAT route.
    const body = wat[module_prefix.len..];
    if (std.mem.indexOfScalar(u8, body, '\n')) |marker_end| {
        const marker_len = marker_end + 1;
        try out.appendSlice(allocator, body[0..marker_len]);
        try wat_component_metadata.emit_wasi_bindings(allocator, &out, wasi_imports.items);
        try wat_component_metadata.emit_wasi_core_imports(allocator, &out, wasi_imports.items);
        try out.appendSlice(allocator, body[marker_len..]);
    } else {
        try wat_component_metadata.emit_wasi_bindings(allocator, &out, wasi_imports.items);
        try wat_component_metadata.emit_wasi_core_imports(allocator, &out, wasi_imports.items);
        try out.appendSlice(allocator, body);
    }
    return out.toOwnedSlice(allocator);
}

fn finalize_component_wat(allocator: std.mem.Allocator, result: anyerror![]u8) ![]u8 {
    const wat = result catch |err| return err;
    const rewritten = codegen_component_cabi_realloc.rewrite(allocator, wat) catch |err| {
        allocator.free(wat);
        return err;
    };
    allocator.free(wat);
    return rewritten;
}
