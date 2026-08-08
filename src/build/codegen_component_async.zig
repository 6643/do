const std = @import("std");
const imports = @import("imports.zig");
const module_graph_types = @import("module_graph.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const codegen_component_resource_async = @import("codegen_component_resource_async.zig");
const codegen_component_cli_stream_stdin = @import("codegen_component_cli_stream_stdin.zig");
const codegen_component_stream_writer = @import("codegen_component_stream_writer.zig");
const codegen_component_wasi_filesystem_read_directory = @import("codegen_component_wasi_filesystem_read_directory.zig");
const codegen_component_wasi_filesystem_get_type = @import("codegen_component_wasi_filesystem_get_type.zig");
const codegen_component_wasi_filesystem_get_flags = @import("codegen_component_wasi_filesystem_get_flags.zig");
const codegen_component_wasi_filesystem_sync = @import("codegen_component_wasi_filesystem_sync.zig");
const codegen_component_record_stream = @import("codegen_component_record_stream.zig");
const codegen_component_record_resource_list_stream = @import("codegen_component_record_resource_list_stream.zig");
const codegen_component_list_resource_producer = @import("codegen_component_list_resource_producer.zig");
const codegen_component_dynamic_list_resource_producer = @import("codegen_component_dynamic_list_resource_producer.zig");
const codegen_component_batched_list_resource_producer = @import("codegen_component_batched_list_resource_producer.zig");
const codegen_component_variant_resource_stream = @import("codegen_component_variant_resource_stream.zig");
const codegen_component_wasi_http = @import("codegen_component_wasi_http.zig");
const codegen_component_cabi_realloc = @import("codegen_component_cabi_realloc.zig");
const codegen_component_generated_async_scalar = @import("codegen_component_generated_async_scalar.zig");
const codegen_component_async_v2_adapter = @import("codegen_component_async_v2_adapter.zig");
const codegen_component_async_v2_scalar_adapter = @import("codegen_component_async_v2_scalar_adapter.zig");
const component_async_plan = @import("codegen_component_async_plan.zig");
const component_async_call_plan = @import("codegen_component_async_call_plan.zig");
const codegen_p3_wait_for = @import("codegen_p3_wait_for.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");
const wat_component_metadata = @import("wat_component_metadata.zig");

pub const Target = enum {
    generic_async,
    generated_async_scalar,
    scalar_unit,
    scalar_result,
    unit_result_tag,
    resource_result_2word,
    http_response_body,
    http_request_constructor,
    http_request_body,
    http_request_body_producer,
    stream_reader,
    record_stream,
    record_resource_list_stream,
    record_resource_list_stream_producer,
    record_resource_list_stream_dynamic_producer,
    record_resource_list_stream_batched_producer,
    variant_resource_stream,
    stream_writer,
    stream_mirror,
    wasi_read_directory,
    wasi_filesystem_get_type,
    wasi_filesystem_get_flags,
    wasi_filesystem_sync,
};

pub const StreamWriterQueue = codegen_component_stream_writer.StreamWriterQueue;
pub const StreamWriterLease = codegen_component_stream_writer.WriterLease;
pub const StreamWriterPushOutcome = codegen_component_stream_writer.PushOutcome;
pub const StreamWriterPopOutcome = codegen_component_stream_writer.PopOutcome;
pub const GuestAsyncCallPlan = component_async_call_plan.GuestAsyncCallPlan;

pub fn analyze_async_call_component(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
) !GuestAsyncCallPlan {
    return component_async_call_plan.analyze(allocator, tokens);
}

pub fn emit_component_wat(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) ![]u8 {
    if (try codegen_component_wasi_http.has_http_response_status_plan(tokens)) {
        return finalize_component_wat(allocator, codegen_component_wasi_http.emit_response_status_core_wat(allocator));
    }
    if (try codegen_component_wasi_http.has_http_request_send_plan(allocator, tokens)) {
        return finalize_component_wat(allocator, codegen_component_wasi_http.emit_component_wat(allocator, program, tokens, module_graph) catch |err| switch (err) {
            error.UnsupportedP3AsyncHttpService => error.UnsupportedP3AsyncComponent,
            else => err,
        });
    }
    if (try codegen_component_wasi_http.has_http_request_body_plan(allocator, tokens)) {
        return finalize_component_wat(allocator, codegen_component_wasi_http.emit_component_wat(allocator, program, tokens, module_graph) catch |err| switch (err) {
            error.UnsupportedP3AsyncHttpService => error.UnsupportedP3AsyncComponent,
            else => err,
        });
    }
    if (try codegen_component_wasi_http.has_http_request_body_producer_plan(allocator, tokens)) {
        return finalize_component_wat(allocator, codegen_component_wasi_http.emit_component_wat(allocator, program, tokens, module_graph) catch |err| switch (err) {
            error.UnsupportedP3AsyncHttpService => error.UnsupportedP3AsyncComponent,
            else => err,
        });
    }
    if (try codegen_component_wasi_http.has_http_request_constructor_plan(allocator, tokens)) {
        return finalize_component_wat(allocator, codegen_component_wasi_http.emit_component_wat(allocator, program, tokens, module_graph) catch |err| switch (err) {
            error.UnsupportedP3AsyncHttpService => error.UnsupportedP3AsyncComponent,
            else => err,
        });
    }
    if (try codegen_component_wasi_http.has_http_response_body_plan(allocator, tokens)) {
        return finalize_component_wat(allocator, codegen_component_wasi_http.emit_component_wat(allocator, program, tokens, module_graph) catch |err| switch (err) {
            error.UnsupportedP3AsyncHttpService => error.UnsupportedP3AsyncComponent,
            else => err,
        });
    }
    if (try codegen_component_wasi_http.has_http_service_plan(allocator, tokens) or
        try codegen_component_wasi_http.has_http_client_send_plan(allocator, tokens))
    {
        return finalize_component_wat(allocator, codegen_component_wasi_http.emit_component_wat(allocator, program, tokens, module_graph) catch |err| switch (err) {
            error.UnsupportedP3AsyncHttpService => error.UnsupportedP3AsyncComponent,
            else => err,
        });
    }
    return switch (try target_for_tokens_with_graph(allocator, tokens, module_graph)) {
        .generic_async => finalize_component_wat(allocator, emit_generic_async_component_wat(allocator, tokens, module_graph)),
        .generated_async_scalar => finalize_component_wat(allocator, codegen_component_generated_async_scalar.emit_component_wat(allocator, program, tokens, module_graph) catch |err| switch (err) {
            error.InvalidGeneratedAsyncScalarTemplate => error.UnsupportedP3AsyncComponent,
            else => err,
        }),
        .scalar_unit, .unit_result_tag => finalize_component_wat(allocator, codegen_p3_wait_for.emit_component_wat(allocator, program, tokens, module_graph) catch |err| switch (err) {
            error.UnsupportedP3WaitForComponent => error.UnsupportedP3AsyncComponent,
            else => err,
        }),
        .scalar_result => finalize_component_wat(allocator, codegen_p3_wait_for.emit_component_wat(allocator, program, tokens, module_graph) catch |err| switch (err) {
            error.UnsupportedP3WaitForComponent => error.UnsupportedP3AsyncComponent,
            else => err,
        }),
        .resource_result_2word => finalize_component_wat(allocator, codegen_component_resource_async.emit_component_wat(allocator, program, tokens, module_graph) catch |err| switch (err) {
            error.UnsupportedP3AsyncResourceComponent => error.UnsupportedP3AsyncComponent,
            else => err,
        }),
        .http_response_body => finalize_component_wat(allocator, codegen_component_wasi_http.emit_component_wat(allocator, program, tokens, module_graph) catch |err| switch (err) {
            error.UnsupportedP3AsyncHttpService => error.UnsupportedP3AsyncComponent,
            else => err,
        }),
        .http_request_constructor => finalize_component_wat(allocator, codegen_component_wasi_http.emit_component_wat(allocator, program, tokens, module_graph) catch |err| switch (err) {
            error.UnsupportedP3AsyncHttpService => error.UnsupportedP3AsyncComponent,
            else => err,
        }),
        .http_request_body => finalize_component_wat(allocator, codegen_component_wasi_http.emit_component_wat(allocator, program, tokens, module_graph) catch |err| switch (err) {
            error.UnsupportedP3AsyncHttpService => error.UnsupportedP3AsyncComponent,
            else => err,
        }),
        .http_request_body_producer => finalize_component_wat(allocator, codegen_component_wasi_http.emit_component_wat(allocator, program, tokens, module_graph) catch |err| switch (err) {
            error.UnsupportedP3AsyncHttpService => error.UnsupportedP3AsyncComponent,
            else => err,
        }),
        .stream_reader => {
            return finalize_component_wat(allocator, codegen_component_cli_stream_stdin.emit_component_wat(allocator, program, tokens, module_graph));
        },
        .record_stream => codegen_component_record_stream.emit_component_wat(allocator, program, tokens, module_graph) catch |err| switch (err) {
            error.UnsupportedP3RecordStreamComponent => error.UnsupportedP3AsyncComponent,
            else => err,
        },
        .record_resource_list_stream => codegen_component_record_resource_list_stream.emit_component_wat(allocator, program, tokens, module_graph) catch |err| switch (err) {
            error.UnsupportedP3RecordResourceListStreamComponent => error.UnsupportedP3AsyncComponent,
            else => err,
        },
        .record_resource_list_stream_producer => codegen_component_list_resource_producer.emit_component_wat_for_tokens(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3ListResourceProducer => error.UnsupportedP3AsyncComponent,
            else => err,
        },
        .record_resource_list_stream_dynamic_producer => codegen_component_dynamic_list_resource_producer.emit_component_wat_for_tokens(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3DynamicListResourceProducer => error.UnsupportedP3AsyncComponent,
            else => err,
        },
        .record_resource_list_stream_batched_producer => codegen_component_batched_list_resource_producer.emit_component_wat_for_tokens(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3BatchedListResourceProducer => error.UnsupportedP3AsyncComponent,
            else => err,
        },
        .variant_resource_stream => finalize_component_wat(allocator, codegen_component_variant_resource_stream.emit_component_wat(allocator, program, tokens, module_graph) catch |err| switch (err) {
            error.UnsupportedP3VariantResourceStream => error.UnsupportedP3AsyncComponent,
            else => err,
        }),
        .stream_writer => finalize_component_wat(allocator, codegen_component_stream_writer.emit_component_wat(allocator, program, tokens, module_graph) catch |err| switch (err) {
            error.UnsupportedP3StreamWriterComponent => error.UnsupportedP3AsyncComponent,
            else => err,
        }),
        .stream_mirror => finalize_component_wat(allocator, codegen_component_stream_writer.emit_stream_mirror_component_wat(allocator, program, tokens, module_graph) catch |err| switch (err) {
            error.UnsupportedP3StreamMirrorComponent => error.UnsupportedP3AsyncComponent,
            else => err,
        }),
        .wasi_read_directory => codegen_component_wasi_filesystem_read_directory.emit_component_wat(allocator, program, tokens, module_graph) catch |err| switch (err) {
            error.UnsupportedP3WasiReadDirectoryComponent => error.UnsupportedP3AsyncComponent,
            else => err,
        },
        .wasi_filesystem_get_type => codegen_component_wasi_filesystem_get_type.emit_component_wat(allocator, program, tokens, module_graph) catch |err| switch (err) {
            error.UnsupportedP3WasiFilesystemGetTypeComponent => error.UnsupportedP3AsyncComponent,
            else => err,
        },
        .wasi_filesystem_get_flags => codegen_component_wasi_filesystem_get_flags.emit_component_wat(allocator, program, tokens, module_graph) catch |err| switch (err) {
            error.UnsupportedP3WasiFilesystemGetFlagsComponent => error.UnsupportedP3AsyncComponent,
            else => err,
        },
        .wasi_filesystem_sync => codegen_component_wasi_filesystem_sync.emit_component_wat(allocator, program, tokens, module_graph) catch |err| switch (err) {
            error.UnsupportedP3WasiFilesystemSyncComponent => error.UnsupportedP3AsyncComponent,
            else => err,
        },
    };
}

/// Test-only opt-in entrypoint for the generic ABI v2 descriptor adapter.
/// The default component dispatch above intentionally remains on the v1
/// emitter until the full differential/runtime review promotes it.
pub fn emit_component_wat_v2_for_test(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
) ![]u8 {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    var plan = try codegen_component_async_v2_adapter.analyze(allocator, tokens, registry);
    defer plan.deinit(allocator);
    return try plan.emit_component_wat(allocator);
}

/// Opt-in entrypoint for the second independent generic ABI v2 shape. The
/// caller supplies the validated import graph so generated-manifest facts stay
/// the admission boundary.
pub fn emit_component_wat_v2_scalar_i64(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: *const imports.ModuleGraph,
) ![]u8 {
    var plan = try codegen_component_async_v2_scalar_adapter.analyze(allocator, program, tokens, module_graph);
    defer plan.deinit(allocator);
    return try plan.emit_component_wat(allocator);
}

/// Explicit Generic ABI v2 promotion profile. This is deliberately separate
/// from the v1 registry dispatcher: only independently verified adapters are
/// admitted, and every other registry target remains rejected before WAT.
pub fn emit_component_wat_v2(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) ![]u8 {
    const target = target_for_tokens_with_graph(allocator, tokens, module_graph) catch
        return error.UnsupportedGenericAbiV2Promotion;

    return switch (target) {
        .variant_resource_stream => blk: {
            var registry = p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json")) catch
                return error.UnsupportedGenericAbiV2Promotion;
            defer registry.deinit(allocator);
            var plan = codegen_component_async_v2_adapter.analyze(allocator, tokens, registry) catch
                return error.UnsupportedGenericAbiV2Promotion;
            defer plan.deinit(allocator);
            break :blk finalize_component_wat(allocator, plan.emit_component_wat(allocator)) catch
                return error.UnsupportedGenericAbiV2Promotion;
        },
        .generated_async_scalar => blk: {
            const graph = module_graph orelse return error.UnsupportedGenericAbiV2Promotion;
            var plan = codegen_component_async_v2_scalar_adapter.analyze(allocator, program, tokens, graph) catch
                return error.UnsupportedGenericAbiV2Promotion;
            defer plan.deinit(allocator);
            break :blk finalize_component_wat(allocator, plan.emit_component_wat(allocator)) catch
                return error.UnsupportedGenericAbiV2Promotion;
        },
        else => error.UnsupportedGenericAbiV2Promotion,
    };
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

fn replace_all(
    allocator: std.mem.Allocator,
    input: []u8,
    needle: []const u8,
    replacement: []const u8,
) ![]u8 {
    if (needle.len == 0) return error.UnsupportedP3AsyncComponent;
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var remainder = input;
    while (std.mem.indexOf(u8, remainder, needle)) |idx| {
        try out.appendSlice(allocator, remainder[0..idx]);
        try out.appendSlice(allocator, replacement);
        remainder = remainder[idx + needle.len ..];
    }
    try out.appendSlice(allocator, remainder);
    allocator.free(input);
    return try out.toOwnedSlice(allocator);
}

fn emit_generic_async_component_wat(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) ![]u8 {
    var plan = try component_async_plan.analyze_generic_async_component(allocator, tokens, module_graph);
    defer plan.deinit(allocator);

    if (plan.source_mode == .descriptor_async) {
        const runtime_wat = try emit_generic_async_runtime_component_wat(allocator, plan);
        defer allocator.free(runtime_wat);
        var out = std.ArrayList(u8).empty;
        errdefer out.deinit(allocator);
        try out.appendSlice(allocator, runtime_wat);
        try wat_component_metadata.emit_async_component_contract(allocator, &out, .{
            .export_name = plan.root_name,
            .host_locator = plan.host_locator,
            .host_member = plan.host_member,
        });
        return try out.toOwnedSlice(allocator);
    }

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, generic_async_component_wat);
    try wat_component_metadata.emit_async_component_contract(allocator, &out, .{
        .export_name = plan.root_name,
        .host_locator = plan.host_locator,
        .host_member = plan.host_member,
    });
    return try out.toOwnedSlice(allocator);
}

fn emit_generic_async_runtime_component_wat(
    allocator: std.mem.Allocator,
    plan: component_async_plan.GenericAsyncComponentPlan,
) ![]u8 {
    var wat = try allocator.dupe(u8, generic_async_runtime_component_wat);
    errdefer allocator.free(wat);
    wat = try replace_all(allocator, wat, "__ASYNC_IMPORT_MODULE__", plan.async_import_module);
    wat = try replace_all(allocator, wat, "__ASYNC_IMPORT_NAME__", plan.async_import_name);
    return wat;
}

fn emit_generic_async_component_wit(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) ![]u8 {
    var plan = try component_async_plan.analyze_generic_async_component(allocator, tokens, module_graph);
    defer plan.deinit(allocator);
    if (plan.source_mode == .descriptor_async) {
        return allocator.dupe(u8,
            \\package do:generic-async-runtime-probe@0.1.0;
            \\
            \\interface host {
            \\  work: async func();
            \\}
            \\
            \\world probe {
            \\  import host;
            \\  export run: async func();
            \\}
            \\
        );
    }
    return allocator.dupe(u8,
        \\package do:generic-async-probe@0.1.0;
        \\
        \\interface host {
        \\  work: func();
        \\}
        \\
        \\world probe {
        \\  import host;
        \\  export run: async func();
        \\}
        \\
    );
}

const generic_async_runtime_component_wat =
    \\(module
    \\  ;; Generic descriptor-backed async runtime slice. The first host call
    \\  ;; is awaited through the callback; the second is cancelled through the
    \\  ;; callback-safe blocked continuation.
    \\  (type $async-lower (func (result i32)))
    \\  (type $task-cancel (func))
    \\  (type $backpressure (func))
    \\  (type $waitable-set-new (func (result i32)))
    \\  (type $waitable-poll (func (param i32 i32) (result i32)))
    \\  (type $waitable (func (param i32 i32)))
    \\  (type $waitable-drop (func (param i32)))
    \\  (type $subtask-cancel (func (param i32) (result i32)))
    \\  (type $context-get (func (result i32)))
    \\  (type $context-set (func (param i32)))
    \\  (type $async-run (func (result i32)))
    \\  (type $async-run-callback (func (param i32 i32 i32) (result i32)))
    \\  (type $task-return (func))
    \\  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
    \\
    \\  (import "__ASYNC_IMPORT_MODULE__" "__ASYNC_IMPORT_NAME__"
    \\    (func $host-work (type $async-lower)))
    \\  (import "[export]$root" "[task-cancel]" (func $task-cancel (type $task-cancel)))
    \\  (import "$root" "[backpressure-inc]" (func $backpressure-inc (type $backpressure)))
    \\  (import "$root" "[backpressure-dec]" (func $backpressure-dec (type $backpressure)))
    \\  (import "$root" "[waitable-set-new]" (func $waitable-set-new (type $waitable-set-new)))
    \\  (import "$root" "[waitable-set-wait]" (func $waitable-set-wait (type $waitable-poll)))
    \\  (import "$root" "[waitable-set-poll]" (func $waitable-set-poll (type $waitable-poll)))
    \\  (import "$root" "[waitable-set-drop]" (func $waitable-set-drop (type $waitable-drop)))
    \\  (import "$root" "[waitable-join]" (func $waitable-join (type $waitable)))
    \\  (import "$root" "[thread-yield]" (func $thread-yield (type $waitable-set-new)))
    \\  (import "$root" "[subtask-drop]" (func $subtask-drop (type $waitable-drop)))
    \\  (import "$root" "[subtask-cancel]" (func $subtask-cancel (type $subtask-cancel)))
    \\  (import "$root" "[context-get-0]" (func $context-get-0 (type $context-get)))
    \\  (import "$root" "[context-set-0]" (func $context-set-0 (type $context-set)))
    \\  (import "[export]$root" "[task-return]run" (func $task-return (type $task-return)))
    \\
    \\  (type $async-frame (struct
    \\    (field $state (mut i32))
    \\    (field $waitable-set (mut i32))
    \\    (field $subtask (mut i32))
    \\    (field $terminal (mut i32))
    \\  ))
    \\  (type $async-free-slot (struct
    \\    (field $handle i32)
    \\    (field $next (ref null $async-free-slot))
    \\  ))
    \\  (table $async-frames 0 (ref null $async-frame))
    \\  (global $async-frame-free-head (mut (ref null $async-free-slot)) (ref.null $async-free-slot))
    \\
    \\  (func $frame-alloc (param $frame (ref $async-frame)) (result i32)
    \\    local.get $frame
    \\    i32.const 1
    \\    table.grow $async-frames)
    \\  (func $frame-free (param $handle i32)
    \\    local.get $handle
    \\    ref.null $async-frame
    \\    table.set $async-frames)
    \\
    \\  (func $terminal-cleanup (param $frame i32)
    \\    local.get $frame
    \\    table.get $async-frames
    \\    ref.as_non_null
    \\    i32.const 1
    \\    struct.set $async-frame $terminal
    \\    local.get $frame
    \\    table.get $async-frames
    \\    ref.as_non_null
    \\    struct.get $async-frame $waitable-set
    \\    call $waitable-set-drop
    \\    i32.const 0
    \\    call $context-set-0
    \\    local.get $frame
    \\    call $frame-free
    \\    call $task-return)
    \\
    \\  (func $start-second (param $frame i32) (result i32)
    \\    (local $subtask i32)
    \\    ;; [generic-async-runtime] await-second
    \\    call $host-work
    \\    local.set $subtask
    \\    local.get $frame
    \\    table.get $async-frames
    \\    ref.as_non_null
    \\    local.get $subtask
    \\    struct.set $async-frame $subtask
    \\    local.get $subtask
    \\    i32.const 2
    \\    i32.eq
    \\    if (result i32)
    \\      local.get $frame
    \\      table.get $async-frames
    \\      ref.as_non_null
    \\      i32.const 2
    \\      struct.set $async-frame $state
    \\      local.get $frame
    \\      call $cancel-second
    \\    else
    \\      local.get $frame
    \\      table.get $async-frames
    \\      ref.as_non_null
    \\      i32.const 3
    \\      struct.set $async-frame $state
    \\      local.get $subtask
    \\      i32.const 4
    \\      i32.shr_u
    \\      local.get $frame
    \\      table.get $async-frames
    \\      ref.as_non_null
    \\      struct.get $async-frame $waitable-set
    \\      call $waitable-join
    \\      local.get $frame
    \\      table.get $async-frames
    \\      ref.as_non_null
    \\      struct.get $async-frame $waitable-set
    \\      i32.const 4
    \\      i32.shl
    \\      i32.const 2
    \\      i32.or
    \\    end)
    \\
    \\  (func $cancel-second (param $frame i32) (result i32)
    \\    (local $subtask i32) (local $cancel-result i32)
    \\    local.get $frame
    \\    table.get $async-frames
    \\    ref.as_non_null
    \\    struct.get $async-frame $subtask
    \\    i32.const 2
    \\    i32.eq
    \\    if
    \\      ;; A ready first Future has no live subtask handle.
    \\    else
    \\      local.get $frame
    \\      table.get $async-frames
    \\      ref.as_non_null
    \\      struct.get $async-frame $subtask
    \\      i32.const 4
    \\      i32.shr_u
    \\      call $subtask-drop
    \\    end
    \\    call $host-work
    \\    local.set $subtask
    \\    local.get $frame
    \\    table.get $async-frames
    \\    ref.as_non_null
    \\    local.get $subtask
    \\    struct.set $async-frame $subtask
    \\    local.get $subtask
    \\    i32.const 2
    \\    i32.eq
    \\    if
    \\      ;; A ready Future is terminal without a cancellation handshake.
    \\    else
    \\      local.get $subtask
    \\      i32.const 4
    \\      i32.shr_u
    \\      call $subtask-cancel
    \\      local.tee $cancel-result
    \\      i32.const -1
    \\      i32.eq
    \\      if
    \\        ;; [generic-async-runtime] cancel-blocked
    \\        local.get $frame
    \\        table.get $async-frames
    \\        ref.as_non_null
    \\        struct.get $async-frame $waitable-set
    \\        local.get $subtask
    \\        i32.const 4
    \\        i32.shr_u
    \\        call $waitable-join
    \\        local.get $frame
    \\        table.get $async-frames
    \\        ref.as_non_null
    \\        struct.get $async-frame $waitable-set
    \\        i32.const 4
    \\        i32.shl
    \\        i32.const 2
    \\        i32.or
    \\        return
    \\      end
    \\      local.get $cancel-result
    \\      i32.const 3
    \\      i32.eq
    \\      local.get $cancel-result
    \\      i32.const 4
    \\      i32.eq
    \\      i32.or
    \\      i32.eqz
    \\      if unreachable end
    \\      local.get $subtask
    \\      i32.const 4
    \\      i32.shr_u
    \\      call $subtask-drop
    \\    end
    \\    local.get $frame
    \\    call $terminal-cleanup
    \\    i32.const 0)
    \\
    \\  (memory (export "memory") 0)
    \\  (func (export "[async-lift]run") (type $async-run)
    \\    (local $frame i32) (local $waitable-set i32) (local $subtask i32)
    \\    call $waitable-set-new
    \\    local.set $waitable-set
    \\    i32.const 1
    \\    local.get $waitable-set
    \\    i32.const 0
    \\    i32.const 0
    \\    struct.new $async-frame
    \\    call $frame-alloc
    \\    local.set $frame
    \\    local.get $frame
    \\    call $context-set-0
    \\    call $host-work
    \\    local.set $subtask
    \\    local.get $frame
    \\    table.get $async-frames
    \\    ref.as_non_null
    \\    local.get $subtask
    \\    struct.set $async-frame $subtask
    \\    local.get $subtask
    \\    i32.const 2
    \\    i32.eq
    \\    if (result i32)
    \\      local.get $frame
    \\      table.get $async-frames
    \\      ref.as_non_null
    \\      i32.const 2
    \\      struct.set $async-frame $state
    \\      local.get $frame
    \\      call $start-second
    \\    else
    \\      ;; [generic-async-runtime] pending
    \\      local.get $subtask
    \\      i32.const 4
    \\      i32.shr_u
    \\      local.get $waitable-set
    \\      call $waitable-join
    \\      local.get $waitable-set
    \\      i32.const 4
    \\      i32.shl
    \\      i32.const 2
    \\      i32.or
    \\    end)
    \\
    \\  (func (export "[callback][async-lift]run") (type $async-run-callback)
    \\    (local $frame i32)
    \\    call $context-get-0
    \\    local.set $frame
    \\    local.get 0
    \\    i32.const 1
    \\    i32.eq
    \\    if (result i32)
    \\      local.get $frame
    \\      table.get $async-frames
    \\      ref.as_non_null
    \\      struct.get $async-frame $state
    \\      i32.const 1
    \\      i32.eq
    \\      if (result i32)
    \\        local.get 2
    \\        i32.const 2
    \\        i32.eq
    \\        if (result i32)
    \\          local.get $frame
    \\          table.get $async-frames
    \\          ref.as_non_null
    \\          struct.get $async-frame $subtask
    \\          i32.const 4
    \\          i32.shr_u
    \\          call $subtask-drop
    \\          local.get $frame
    \\          table.get $async-frames
    \\          ref.as_non_null
    \\          i32.const 2
    \\          struct.set $async-frame $subtask
    \\          local.get $frame
    \\          table.get $async-frames
    \\          ref.as_non_null
    \\          i32.const 2
    \\          struct.set $async-frame $state
    \\          local.get $frame
    \\          call $start-second
    \\        else
    \\          unreachable
    \\        end
    \\      else
    \\        local.get $frame
    \\        table.get $async-frames
    \\        ref.as_non_null
    \\        struct.get $async-frame $state
    \\        i32.const 3
    \\        i32.eq
    \\        if (result i32)
    \\          local.get 2
    \\          i32.const 2
    \\          i32.eq
    \\          if (result i32)
    \\            local.get $frame
    \\            table.get $async-frames
    \\            ref.as_non_null
    \\            struct.get $async-frame $subtask
    \\            i32.const 4
    \\            i32.shr_u
    \\            call $subtask-drop
    \\            local.get $frame
    \\            table.get $async-frames
    \\            ref.as_non_null
    \\            i32.const 2
    \\            struct.set $async-frame $subtask
    \\            local.get $frame
    \\            table.get $async-frames
    \\            ref.as_non_null
    \\            i32.const 2
    \\            struct.set $async-frame $state
    \\            local.get $frame
    \\            call $cancel-second
    \\          else
    \\            unreachable
    \\          end
    \\        else
    \\          local.get $frame
    \\          table.get $async-frames
    \\          ref.as_non_null
    \\          struct.get $async-frame $state
    \\          i32.const 2
    \\          i32.eq
    \\          if (result i32)
    \\          local.get 2
    \\          i32.const 3
    \\          i32.eq
    \\          local.get 2
    \\          i32.const 4
    \\          i32.eq
    \\          i32.or
    \\          if (result i32)
    \\            local.get $frame
    \\            table.get $async-frames
    \\            ref.as_non_null
    \\            struct.get $async-frame $subtask
    \\            i32.const 4
    \\            i32.shr_u
    \\            call $subtask-drop
    \\            local.get $frame
    \\            call $terminal-cleanup
    \\            i32.const 0
    \\          else
    \\            unreachable
    \\          end
    \\          else
    \\            unreachable
    \\          end
    \\        end
    \\      end
    \\    else
    \\      local.get $frame
    \\      table.get $async-frames
    \\      ref.as_non_null
    \\      struct.get $async-frame $waitable-set
    \\      i32.const 4
    \\      i32.shl
    \\      i32.const 2
    \\      i32.or
    \\    end)
    \\  (func (export "cabi_realloc") (type $cabi-realloc) i32.const 0)
    \\  (func (export "_initialize"))
    \\)
;

const generic_async_component_wat =
    \\(module
    \\  (type $host-work (func))
    \\  (type $task-return (func))
    \\  (type $async-run (func (result i32)))
    \\  (type $async-run-callback (func (param i32 i32 i32) (result i32)))
    \\  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
    \\  (type $waitable-set-new (func (result i32)))
    \\  (type $waitable-set-wait (func (param i32 i32) (result i32)))
    \\  (type $waitable-set-drop (func (param i32)))
    \\  (type $waitable-join (func (param i32 i32)))
    \\  (type $subtask-cancel (func (param i32) (result i32)))
    \\
    \\  (import "do:generic-async-probe/host@0.1.0" "work"
    \\    (func $work (type $host-work)))
    \\  (import "[export]$root" "[task-cancel]" (func $task-cancel (type $task-return)))
    \\  (import "$root" "[backpressure-inc]" (func $backpressure-inc (type $task-return)))
    \\  (import "$root" "[backpressure-dec]" (func $backpressure-dec (type $task-return)))
    \\  (import "$root" "[waitable-set-new]" (func $waitable-set-new (type $waitable-set-new)))
    \\  (import "$root" "[waitable-set-wait]" (func $waitable-set-wait (type $waitable-set-wait)))
    \\  (import "$root" "[waitable-set-poll]" (func $waitable-set-poll (type $waitable-set-wait)))
    \\  (import "$root" "[waitable-set-drop]" (func $waitable-set-drop (type $waitable-set-drop)))
    \\  (import "$root" "[waitable-join]" (func $waitable-join (type $waitable-join)))
    \\  (import "$root" "[thread-yield]" (func $thread-yield (type $waitable-set-new)))
    \\  (import "$root" "[subtask-drop]" (func $subtask-drop (type $waitable-set-drop)))
    \\  (import "$root" "[subtask-cancel]" (func $subtask-cancel (type $subtask-cancel)))
    \\  (import "$root" "[context-get-0]" (func $context-get-0 (type $waitable-set-new)))
    \\  (import "$root" "[context-set-0]" (func $context-set-0 (type $waitable-set-drop)))
    \\  (import "[export]$root" "[task-return]run" (func $task-return (type $task-return)))
    \\
    \\  (memory (export "memory") 0)
    \\  (func (export "[async-lift]run") (type $async-run)
    \\    ;; The first admitted slice has unit work and a terminal cancel path.
    \\    ;; The host call is synchronous; task-return is exactly once.
    \\    call $work
    \\    call $work
    \\    call $work
    \\    ;; [generic-async-cancel] is retained as an unreachable ABI probe
    \\    ;; until a Future can carry a runtime subtask handle.
    \\    i32.const 0
    \\    if
    \\      i32.const 0
    \\      call $subtask-cancel
    \\      drop
    \\      i32.const 0
    \\      call $subtask-drop
    \\    end
    \\    call $task-return
    \\    i32.const 0
    \\  )
    \\  (func (export "[callback][async-lift]run") (type $async-run-callback)
    \\    unreachable
    \\  )
    \\  (func (export "cabi_realloc") (type $cabi-realloc)
    \\    unreachable
    \\  )
    \\  (func (export "_initialize"))
    \\)
;

pub fn emit_component_wit(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]u8 {
    return emit_component_wit_with_graph(allocator, tokens, null);
}

pub fn emit_component_wit_with_graph(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) ![]u8 {
    if (try codegen_component_wasi_http.has_http_response_status_plan(tokens)) {
        return codegen_component_wasi_http.emit_response_status_component_wit(allocator);
    }
    if (try codegen_component_wasi_http.has_http_request_send_plan(allocator, tokens)) {
        return codegen_component_wasi_http.emit_component_wit(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3AsyncHttpService => error.UnsupportedP3AsyncComponent,
            else => err,
        };
    }
    if (try codegen_component_wasi_http.has_http_request_body_plan(allocator, tokens)) {
        return codegen_component_wasi_http.emit_component_wit(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3AsyncHttpService => error.UnsupportedP3AsyncComponent,
            else => err,
        };
    }
    if (try codegen_component_wasi_http.has_http_request_body_producer_plan(allocator, tokens)) {
        return codegen_component_wasi_http.emit_component_wit(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3AsyncHttpService => error.UnsupportedP3AsyncComponent,
            else => err,
        };
    }
    if (try codegen_component_wasi_http.has_http_request_constructor_plan(allocator, tokens)) {
        return codegen_component_wasi_http.emit_component_wit(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3AsyncHttpService => error.UnsupportedP3AsyncComponent,
            else => err,
        };
    }
    if (try codegen_component_wasi_http.has_http_response_body_plan(allocator, tokens)) {
        return codegen_component_wasi_http.emit_component_wit(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3AsyncHttpService => error.UnsupportedP3AsyncComponent,
            else => err,
        };
    }
    if (try codegen_component_wasi_http.has_http_service_plan(allocator, tokens) or
        try codegen_component_wasi_http.has_http_client_send_plan(allocator, tokens))
    {
        return codegen_component_wasi_http.emit_component_wit(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3AsyncHttpService => error.UnsupportedP3AsyncComponent,
            else => err,
        };
    }
    return switch (try target_for_tokens_with_graph(allocator, tokens, module_graph)) {
        .generic_async => emit_generic_async_component_wit(allocator, tokens, module_graph),
        .generated_async_scalar => codegen_component_generated_async_scalar.emit_component_wit_with_graph(allocator, tokens, module_graph),
        .scalar_unit, .unit_result_tag => codegen_p3_wait_for.emit_component_wit_for_tokens(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3WaitForComponent => error.UnsupportedP3AsyncComponent,
            else => err,
        },
        .scalar_result => codegen_p3_wait_for.emit_component_wit_for_tokens(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3WaitForComponent => error.UnsupportedP3AsyncComponent,
            else => err,
        },
        .resource_result_2word => codegen_component_resource_async.emit_component_wit(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3AsyncResourceComponent => error.UnsupportedP3AsyncComponent,
            else => err,
        },
        .http_response_body => codegen_component_wasi_http.emit_component_wit(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3AsyncHttpService => error.UnsupportedP3AsyncComponent,
            else => err,
        },
        .http_request_constructor => codegen_component_wasi_http.emit_component_wit(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3AsyncHttpService => error.UnsupportedP3AsyncComponent,
            else => err,
        },
        .http_request_body => codegen_component_wasi_http.emit_component_wit(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3AsyncHttpService => error.UnsupportedP3AsyncComponent,
            else => err,
        },
        .http_request_body_producer => codegen_component_wasi_http.emit_component_wit(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3AsyncHttpService => error.UnsupportedP3AsyncComponent,
            else => err,
        },
        .stream_reader => codegen_component_cli_stream_stdin.emit_component_wit(allocator, tokens),
        .record_stream => codegen_component_record_stream.emit_component_wit(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3RecordStreamComponent => error.UnsupportedP3AsyncComponent,
            else => err,
        },
        .record_resource_list_stream => codegen_component_record_resource_list_stream.emit_component_wit(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3RecordResourceListStreamComponent => error.UnsupportedP3AsyncComponent,
            else => err,
        },
        .record_resource_list_stream_producer => codegen_component_list_resource_producer.emit_component_wit_for_tokens(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3ListResourceProducer => error.UnsupportedP3AsyncComponent,
            else => err,
        },
        .record_resource_list_stream_dynamic_producer => codegen_component_dynamic_list_resource_producer.emit_component_wit_for_tokens(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3DynamicListResourceProducer => error.UnsupportedP3AsyncComponent,
            else => err,
        },
        .record_resource_list_stream_batched_producer => codegen_component_batched_list_resource_producer.emit_component_wit_for_tokens(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3BatchedListResourceProducer => error.UnsupportedP3AsyncComponent,
            else => err,
        },
        .variant_resource_stream => codegen_component_variant_resource_stream.emit_component_wit(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3VariantResourceStream => error.UnsupportedP3AsyncComponent,
            else => err,
        },
        .stream_writer => codegen_component_stream_writer.emit_component_wit(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3StreamWriterComponent => error.UnsupportedP3AsyncComponent,
            else => err,
        },
        .stream_mirror => codegen_component_stream_writer.emit_stream_mirror_component_wit(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3StreamMirrorComponent => error.UnsupportedP3AsyncComponent,
            else => err,
        },
        .wasi_read_directory => codegen_component_wasi_filesystem_read_directory.emit_component_wit(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3WasiReadDirectoryComponent => error.UnsupportedP3AsyncComponent,
            else => err,
        },
        .wasi_filesystem_get_type => codegen_component_wasi_filesystem_get_type.emit_component_wit(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3WasiFilesystemGetTypeComponent => error.UnsupportedP3AsyncComponent,
            else => err,
        },
        .wasi_filesystem_get_flags => codegen_component_wasi_filesystem_get_flags.emit_component_wit(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3WasiFilesystemGetFlagsComponent => error.UnsupportedP3AsyncComponent,
            else => err,
        },
        .wasi_filesystem_sync => codegen_component_wasi_filesystem_sync.emit_component_wit(allocator, tokens) catch |err| switch (err) {
            error.UnsupportedP3WasiFilesystemSyncComponent => error.UnsupportedP3AsyncComponent,
            else => err,
        },
    };
}

pub fn target_for_tokens(allocator: std.mem.Allocator, tokens: []const lexer.Token) !Target {
    return target_for_tokens_with_graph(allocator, tokens, null);
}

pub fn target_for_tokens_with_graph(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) !Target {
    if (try codegen_component_wasi_http.has_http_request_body_producer_plan(allocator, tokens)) {
        return .http_request_body_producer;
    }
    if (try codegen_component_wasi_http.has_http_request_body_plan(allocator, tokens)) {
        return .http_request_body;
    }
    if (try codegen_component_wasi_http.has_http_request_constructor_plan(allocator, tokens)) {
        return .http_request_constructor;
    }
    if (try codegen_component_wasi_http.has_http_response_body_plan(allocator, tokens)) {
        return .http_response_body;
    }
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);

    if (module_graph) |graph| {
        if (component_async_plan.analyze_generated_async_scalar(allocator, tokens, graph)) |plan| {
            var admitted = plan;
            admitted.deinit(allocator);
            return .generated_async_scalar;
        } else |err| switch (err) {
            error.UnsupportedGeneratedAsyncScalarShape => {},
            else => return err,
        }
    }

    if (component_async_plan.analyze_generic_async_component(allocator, tokens, module_graph)) |plan| {
        var admitted = plan;
        admitted.deinit(allocator);
        return .generic_async;
    } else |err| switch (err) {
        error.UnsupportedGenericAsyncComponent => {},
        else => return err,
    }

    if (component_async_plan.StreamMirrorPlan.analyze(tokens, registry)) |_| {
        return .stream_mirror;
    } else |_| {}

    if (codegen_component_list_resource_producer.ListResourceProducerPlan.analyze(tokens, registry)) |_| {
        return .record_resource_list_stream_producer;
    } else |_| {}

    if (codegen_component_dynamic_list_resource_producer.DynamicListResourceProducerPlan.analyze(tokens, registry)) |_| {
        return .record_resource_list_stream_dynamic_producer;
    } else |_| {}

    var target: ?Target = null;
    var idx: usize = 0;
    while (idx + 8 < tokens.len) : (idx += 1) {
        const binding = host_binding_at(tokens, idx) orelse continue;
        const descriptor = registry.find(binding.locator, binding.member) orelse continue;
        const shape = p3_async_manifest.lowering_shape(descriptor) orelse return error.UnsupportedP3AsyncComponent;
        const next: Target = switch (shape) {
            .stream_reader_acquire => if (binding.kind == .host_func and stream_reader_signature_at(tokens, idx)) .stream_reader else return error.UnsupportedP3AsyncComponent,
            .record_stream_reader => blk: {
                const is_read_directory =
                    std.mem.eql(u8, descriptor.locator, "wasi:filesystem/types@0.3.0-rc-2025-09-16") and
                        std.mem.eql(u8, descriptor.member, "descriptor.read-directory");
                if (is_read_directory) {
                    if (binding.kind != .host_async_func or !record_stream_reader_signature_at(tokens, idx)) {
                        return error.UnsupportedP3AsyncComponent;
                    }
                    break :blk .wasi_read_directory;
                }
                if (binding.kind != .host_func) return error.UnsupportedP3AsyncComponent;
                break :blk try record_stream_target_for_tokens(tokens, registry);
            },
            .record_resource_list_stream_reader => if (binding.kind == .host_func and list_resource_stream_signature_at(tokens, idx))
                try list_resource_stream_target_for_tokens(tokens, registry)
            else
                return error.UnsupportedP3AsyncComponent,
            .record_resource_list_stream_producer => if (binding.kind == .host_async_func) blk: {
                _ = codegen_component_list_resource_producer.ListResourceProducerPlan.analyze(tokens, registry) catch
                    return error.UnsupportedP3AsyncComponent;
                break :blk .record_resource_list_stream_producer;
            } else return error.UnsupportedP3AsyncComponent,
            .record_resource_list_stream_dynamic_producer => if (binding.kind == .host_async_func) blk: {
                _ = codegen_component_dynamic_list_resource_producer.DynamicListResourceProducerPlan.analyze(tokens, registry) catch
                    return error.UnsupportedP3AsyncComponent;
                break :blk .record_resource_list_stream_dynamic_producer;
            } else return error.UnsupportedP3AsyncComponent,
            .record_resource_list_stream_batched_producer => if (binding.kind == .host_async_func) blk: {
                _ = codegen_component_batched_list_resource_producer.BatchedListResourceProducerPlan.analyze(tokens, registry) catch
                    return error.UnsupportedP3BatchedListResourceProducer;
                break :blk .record_resource_list_stream_batched_producer;
            } else return error.UnsupportedP3BatchedListResourceProducer,
            .variant_resource_stream_reader => if (binding.kind == .host_func and variant_resource_stream_signature_at(tokens, idx))
                .variant_resource_stream
            else
                return error.UnsupportedP3AsyncComponent,
            .stream_writer => if (binding.kind == .host_async_func and stream_writer_signature_at(tokens, idx)) .stream_writer else return error.UnsupportedP3AsyncComponent,
            .filesystem_get_type => if (binding.kind == .host_async_func) blk: {
                _ = codegen_component_wasi_filesystem_get_type.GetTypePlan.analyze(tokens, registry) catch
                    return error.UnsupportedP3AsyncComponent;
                break :blk .wasi_filesystem_get_type;
            } else return error.UnsupportedP3AsyncComponent,
            .filesystem_get_flags => if (binding.kind == .host_async_func) blk: {
                _ = codegen_component_wasi_filesystem_get_flags.GetFlagsPlan.analyze(tokens, registry) catch
                    return error.UnsupportedP3AsyncComponent;
                break :blk .wasi_filesystem_get_flags;
            } else return error.UnsupportedP3AsyncComponent,
            .filesystem_sync => if (binding.kind == .host_async_func) blk: {
                _ = codegen_component_wasi_filesystem_sync.SyncPlan.analyze(tokens, registry) catch
                    return error.UnsupportedP3AsyncComponent;
                break :blk .wasi_filesystem_sync;
            } else return error.UnsupportedP3AsyncComponent,
            else => try target_for_descriptor(descriptor),
        };
        if (target) |existing| {
            if (existing != next) return error.UnsupportedP3AsyncComponent;
        } else {
            target = next;
        }
    }
    return target orelse error.UnsupportedP3AsyncComponent;
}

fn record_stream_target_for_tokens(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) !Target {
    _ = codegen_component_record_stream.RecordStreamSourcePlan.analyze(tokens, registry) catch
        return error.UnsupportedP3AsyncComponent;
    return .record_stream;
}

fn list_resource_stream_target_for_tokens(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) !Target {
    _ = codegen_component_record_resource_list_stream.ListResourceStreamPlan.analyze(tokens, registry) catch
        return error.UnsupportedP3AsyncComponent;
    return .record_resource_list_stream;
}

pub fn requires_http_wit_package(allocator: std.mem.Allocator, tokens: []const lexer.Token) !bool {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    return (try codegen_component_wasi_http.HttpServicePlan.analyze(tokens, registry)) != null or
        (try codegen_component_wasi_http.HttpClientSendPlan.analyze(tokens, registry)) != null or
        (try codegen_component_wasi_http.HttpRequestSendPlan.analyze(tokens, registry)) != null or
        (try codegen_component_wasi_http.HttpRequestConstructorPlan.analyze(tokens, registry)) != null or
        (try codegen_component_wasi_http.HttpRequestBodyPlan.analyze(tokens, registry)) != null or
        (try codegen_component_wasi_http.HttpRequestBodyProducerPlan.analyze(tokens, registry)) != null or
        (try codegen_component_wasi_http.HttpResponseBodyPlan.analyze(tokens, registry)) != null;
}

fn target_for_descriptor(descriptor: p3_async_manifest.Descriptor) !Target {
    const shape = p3_async_manifest.lowering_shape(descriptor) orelse return error.UnsupportedP3AsyncComponent;
    return switch (shape) {
        .scalar_unit => .scalar_unit,
        .scalar_result => .scalar_result,
        .unit_result_tag => .unit_result_tag,
        .future_owned_resource => error.UnsupportedP3AsyncComponent,
        .stream_reader_acquire => .stream_reader,
        .record_stream_reader => .wasi_read_directory,
        .filesystem_get_type => .wasi_filesystem_get_type,
        .filesystem_get_flags => .wasi_filesystem_get_flags,
        .filesystem_sync => .wasi_filesystem_sync,
        .record_resource_list_stream_reader => error.UnsupportedP3AsyncComponent,
        .record_resource_list_stream_producer => .record_resource_list_stream_producer,
        .record_resource_list_stream_dynamic_producer => .record_resource_list_stream_dynamic_producer,
        .record_resource_list_stream_batched_producer => .record_resource_list_stream_batched_producer,
        .variant_resource_stream_reader => .variant_resource_stream,
        .stream_writer => .stream_writer,
        .http_resource_result => error.UnsupportedP3AsyncComponent,
        .http_request_constructor => error.UnsupportedP3AsyncComponent,
        .http_stream_reader => error.UnsupportedP3AsyncComponent,
        .resource_result_2word => if (std.mem.eql(u8, descriptor.locator, "do:resource-probe/http@0.1.0") and
            std.mem.eql(u8, descriptor.member, "send"))
            .resource_result_2word
        else if (std.mem.eql(u8, descriptor.locator, "do:resource-probe-owned-error/http@0.1.0") and
            std.mem.eql(u8, descriptor.member, "send") and
            std.mem.eql(u8, descriptor.result, "Result<HttpResponse,HttpErrorResource>"))
            .resource_result_2word
        else
            error.UnsupportedP3AsyncComponent,
    };
}

const HostBindingKind = enum {
    host_func,
    host_async_func,
};

const HostFuncBinding = struct {
    locator: []const u8,
    member: []const u8,
    kind: HostBindingKind,
};

fn host_binding_at(tokens: []const lexer.Token, idx: usize) ?HostFuncBinding {
    if (idx + 8 >= tokens.len or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or !tok_eq(tokens[idx + 2], "@") or !tok_eq(tokens[idx + 4], "(")) return null;
    const kind: HostBindingKind = if (tok_eq(tokens[idx + 3], "host_func")) .host_func else if (tok_eq(tokens[idx + 3], "host_async_func")) .host_async_func else return null;
    if (!tok_eq(tokens[idx + 6], ",") or !tok_eq(tokens[idx + 8], ",")) return null;
    const locator = string_token_body(tokens[idx + 5]) orelse return null;
    const member = string_token_body(tokens[idx + 7]) orelse return null;
    return .{ .locator = locator, .member = member, .kind = kind };
}

fn stream_reader_signature_at(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 30 >= tokens.len or
        !tok_eq(tokens[idx + 9], "(") or !tok_eq(tokens[idx + 10], ")") or
        !tok_eq(tokens[idx + 11], "-") or !tok_eq(tokens[idx + 12], ">") or
        !tok_eq(tokens[idx + 13], "Tuple") or !tok_eq(tokens[idx + 14], "<") or
        !tok_eq(tokens[idx + 15], "Stream") or !tok_eq(tokens[idx + 16], "<") or
        !tok_eq(tokens[idx + 17], "u8") or !tok_eq(tokens[idx + 18], ">") or
        !tok_eq(tokens[idx + 19], ",") or !tok_eq(tokens[idx + 20], "Future") or
        !tok_eq(tokens[idx + 21], "<") or !tok_eq(tokens[idx + 22], "Result") or
        !tok_eq(tokens[idx + 23], "<") or !tok_eq(tokens[idx + 24], "nil") or
        !tok_eq(tokens[idx + 25], ",") or tokens[idx + 26].kind != .ident or
        !tok_eq(tokens[idx + 27], ">") or !tok_eq(tokens[idx + 28], ">") or
        !tok_eq(tokens[idx + 29], ">") or !tok_eq(tokens[idx + 30], ")"))
    {
        return false;
    }
    return std.mem.endsWith(u8, tokens[idx + 26].lexeme, "Error");
}

fn record_stream_reader_signature_at(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 31 >= tokens.len or
        !tok_eq(tokens[idx + 9], "(") or
        !tok_eq(tokens[idx + 10], "Dir") or
        !tok_eq(tokens[idx + 11], ")") or
        !tok_eq(tokens[idx + 12], "-") or
        !tok_eq(tokens[idx + 13], ">") or
        !tok_eq(tokens[idx + 14], "Tuple") or
        !tok_eq(tokens[idx + 15], "<") or
        !tok_eq(tokens[idx + 16], "Stream") or
        !tok_eq(tokens[idx + 17], "<") or
        !tok_eq(tokens[idx + 18], "DirectoryEntry") or
        !tok_eq(tokens[idx + 19], ">") or
        !tok_eq(tokens[idx + 20], ",") or
        !tok_eq(tokens[idx + 21], "Future") or
        !tok_eq(tokens[idx + 22], "<") or
        !tok_eq(tokens[idx + 23], "Result") or
        !tok_eq(tokens[idx + 24], "<") or
        !tok_eq(tokens[idx + 25], "nil") or
        !tok_eq(tokens[idx + 26], ",") or
        !tok_eq(tokens[idx + 27], "DirectoryError") or
        !tok_eq(tokens[idx + 28], ">") or
        !tok_eq(tokens[idx + 29], ">") or
        !tok_eq(tokens[idx + 30], ">") or
        !tok_eq(tokens[idx + 31], ")")) return false;
    return true;
}

fn list_resource_stream_signature_at(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 32 >= tokens.len or
        !tok_eq(tokens[idx + 9], "(") or
        !tok_eq(tokens[idx + 10], ")") or
        !tok_eq(tokens[idx + 11], "-") or
        !tok_eq(tokens[idx + 12], ">") or
        !tok_eq(tokens[idx + 13], "Tuple") or
        !tok_eq(tokens[idx + 14], "<") or
        !tok_eq(tokens[idx + 15], "Stream") or
        !tok_eq(tokens[idx + 16], "<") or
        !tok_eq(tokens[idx + 17], "[") or
        !tok_eq(tokens[idx + 18], "ResourceEntry") or
        !tok_eq(tokens[idx + 19], "]") or
        !tok_eq(tokens[idx + 20], ">") or
        !tok_eq(tokens[idx + 21], ",") or
        !tok_eq(tokens[idx + 22], "Future") or
        !tok_eq(tokens[idx + 23], "<") or
        !tok_eq(tokens[idx + 24], "Result") or
        !tok_eq(tokens[idx + 25], "<") or
        !tok_eq(tokens[idx + 26], "nil") or
        !tok_eq(tokens[idx + 27], ",") or
        !tok_eq(tokens[idx + 28], "ProbeError") or
        !tok_eq(tokens[idx + 29], ">") or
        !tok_eq(tokens[idx + 30], ">") or
        !tok_eq(tokens[idx + 31], ">") or
        !tok_eq(tokens[idx + 32], ")")) return false;
    return true;
}

fn variant_resource_stream_signature_at(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 34 >= tokens.len or
        !tok_eq(tokens[idx + 9], "(") or !tok_eq(tokens[idx + 10], ")") or
        !tok_eq(tokens[idx + 11], "-") or !tok_eq(tokens[idx + 12], ">") or
        !tok_eq(tokens[idx + 13], "Tuple") or !tok_eq(tokens[idx + 14], "<") or
        !tok_eq(tokens[idx + 15], "Stream") or !tok_eq(tokens[idx + 16], "<") or
        !tok_eq(tokens[idx + 17], "Ticket") or !tok_eq(tokens[idx + 18], "|") or
        !tok_eq(tokens[idx + 19], "nil") or !tok_eq(tokens[idx + 20], "|") or
        !tok_eq(tokens[idx + 21], "EventError") or !tok_eq(tokens[idx + 22], ">") or
        !tok_eq(tokens[idx + 23], ",") or !tok_eq(tokens[idx + 24], "Future") or
        !tok_eq(tokens[idx + 25], "<") or !tok_eq(tokens[idx + 26], "Result") or
        !tok_eq(tokens[idx + 27], "<") or !tok_eq(tokens[idx + 28], "nil") or
        !tok_eq(tokens[idx + 29], ",") or !tok_eq(tokens[idx + 30], "EventError") or
        !tok_eq(tokens[idx + 31], ">") or !tok_eq(tokens[idx + 32], ">") or
        !tok_eq(tokens[idx + 33], ">") or !tok_eq(tokens[idx + 34], ")")) return false;
    return true;
}

fn stream_writer_signature_at(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 23 >= tokens.len or
        !tok_eq(tokens[idx + 9], "(") or !tok_eq(tokens[idx + 10], "StreamWriter") or
        !tok_eq(tokens[idx + 11], "<") or !tok_eq(tokens[idx + 12], "u8") or
        !tok_eq(tokens[idx + 13], ">") or !tok_eq(tokens[idx + 14], ")") or
        !tok_eq(tokens[idx + 15], "-") or !tok_eq(tokens[idx + 16], ">") or
        !tok_eq(tokens[idx + 17], "Result") or !tok_eq(tokens[idx + 18], "<") or
        !tok_eq(tokens[idx + 19], "nil") or !tok_eq(tokens[idx + 20], ",") or
        tokens[idx + 21].kind != .ident or !tok_eq(tokens[idx + 22], ">") or
        !tok_eq(tokens[idx + 23], ")")) return false;
    return std.mem.endsWith(u8, tokens[idx + 21].lexeme, "Error");
}

fn string_token_body(token: lexer.Token) ?[]const u8 {
    if (token.kind != .string or token.lexeme.len < 2) return null;
    return token.lexeme[1 .. token.lexeme.len - 1];
}

fn tok_eq(token: lexer.Token, text: []const u8) bool {
    return std.mem.eql(u8, token.lexeme, text);
}

test "generic Component async target classifies registered descriptor shapes" {
    const scalar_source =
        \\wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
    ;
    const scalar_tokens = try lexer.tokenize(std.testing.allocator, scalar_source);
    defer std.testing.allocator.free(scalar_tokens);
    try std.testing.expectEqual(Target.scalar_unit, try target_for_tokens(std.testing.allocator, scalar_tokens));

    const resource_source =
        \\send = @host_async_func("do:resource-probe/http@0.1.0", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
    ;
    const resource_tokens = try lexer.tokenize(std.testing.allocator, resource_source);
    defer std.testing.allocator.free(resource_tokens);
    try std.testing.expectEqual(Target.resource_result_2word, try target_for_tokens(std.testing.allocator, resource_tokens));

    const cli_result_source =
        \\run = @host_async_func("wasi:cli@0.3.0", "run.run", () -> Result<nil, nil>)
    ;
    const cli_result_tokens = try lexer.tokenize(std.testing.allocator, cli_result_source);
    defer std.testing.allocator.free(cli_result_tokens);
    try std.testing.expectEqual(Target.unit_result_tag, try target_for_tokens(std.testing.allocator, cli_result_tokens));

    const scalar_result_source =
        \\result_run = @host_async_func("do:result-probe@0.1.0", "run", (i32) -> Result<i32, i32>)
    ;
    const scalar_result_tokens = try lexer.tokenize(std.testing.allocator, scalar_result_source);
    defer std.testing.allocator.free(scalar_result_tokens);
    try std.testing.expectEqual(Target.scalar_result, try target_for_tokens(std.testing.allocator, scalar_result_tokens));

    const writer_source =
        \\stdout_write = @host_async_func("wasi:cli/stdout@0.3.0-rc-2025-09-16", "write-via-stream", (StreamWriter<u8>) -> Result<nil, StdoutError>)
    ;
    const writer_tokens = try lexer.tokenize(std.testing.allocator, writer_source);
    defer std.testing.allocator.free(writer_tokens);
    try std.testing.expectEqual(Target.stream_writer, try target_for_tokens(std.testing.allocator, writer_tokens));
}

test "generic Component async target classifies the pinned batched list resource producer" {
    const source =
        \\make_ticket = @host_func("do:g6-2-batched-list-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
        \\consume = @host_async_func("do:g6-2-batched-list-producer@0.1.0", "consume-via-stream", (StreamWriter<[ResourceEntry]>) -> Result<nil, ProducerError>)
        \\Ticket = @wasi_resource("do:g6-2-batched-list-producer/source/ticket", { .id i64 })
        \\ResourceEntry { .ticket Ticket }
        \\ProducerError error = Io | Pipe | InvalidMode
        \\produce(mode u32) -> Result<nil, ProducerError> { return Ok() }
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try std.testing.expectEqual(
        Target.record_resource_list_stream_batched_producer,
        try target_for_tokens(std.testing.allocator, tokens),
    );
}

test "generic Component async target rejects a non-fixed batched producer before emission" {
    const source =
        \\make_ticket = @host_func("do:g6-2-batched-list-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
        \\consume = @host_async_func("do:g6-2-batched-list-producer@0.1.0", "consume-via-stream", (StreamWriter<[ResourceEntry]>) -> Result<nil, ProducerError>)
        \\Ticket = @wasi_resource("do:g6-2-batched-list-producer/source/ticket", { .id i64 })
        \\ResourceEntry { .ticket Ticket }
        \\ProducerError error = Io | Pipe | InvalidMode
        \\produce(mode u32) -> Result<nil, ProducerError> {
        \\    selected u32 = mode
        \\    _ = selected
        \\    return Ok()
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try std.testing.expectError(
        error.UnsupportedP3BatchedListResourceProducer,
        target_for_tokens(std.testing.allocator, tokens),
    );
}

test "generic Component async target classifies the bounded stream mirror" {
    const source =
        \\probe_read = @host_func("do:stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, ProbeError>>>)
        \\sink_write = @host_async_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\StreamError error = StreamClosed | StreamWriteFailed
        \\async produce() -> Result<nil, ProbeError> {
        \\    source Tuple<Stream<u8>, Future<Result<nil, ProbeError>>> = probe_read()
        \\    input Stream<u8> = @get(source, 0)
        \\    source_done Future<Result<nil, ProbeError>> = @get(source, 1)
        \\    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
        \\    defer close(writer)
        \\    remaining u64 = 3
        \\    loop {
        \\        if @eq(remaining, 0) { break }
        \\        read_pending Future<Result<u8, nil>> = @next(input)
        \\        item Result<u8, nil> = await(read_pending)
        \\        if @is(item, Ok) {
        \\            value u8 = item
        \\            write_pending Future<Result<nil, StreamError>> = writer(value)
        \\            write_result Result<nil, StreamError> = await(write_pending)
        \\            _ = write_result
        \\            remaining = @sub(remaining, 1)
        \\        } else { break }
        \\    }
        \\    @cancel(source_done)
        \\    pending Future<Result<nil, ProbeError>> = sink_write(writer)
        \\    return await(pending)
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try std.testing.expectEqual(Target.stream_mirror, try target_for_tokens(std.testing.allocator, tokens));
}

test "generic Component async target rejects unlowered HTTP descriptor" {
    const source =
        \\send = @host_async_func("wasi:http/client@0.3.0-rc-2025-09-16", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectError(error.UnsupportedP3AsyncComponent, target_for_tokens(std.testing.allocator, tokens));
}

test "generic Component async target classifies the pinned CLI stdin stream acquisition" {
    const source =
        \\stdin_read = @host_func("wasi:cli/stdin@0.3.0-rc-2025-09-16", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, StdinError>>>)
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    const target = try target_for_tokens(std.testing.allocator, tokens);
    try std.testing.expectEqualStrings("stream_reader", @tagName(target));
}

test "generic Component async target classifies the pinned read-directory record stream" {
    const source =
        \\.host_read_directory = @host_async_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.read-directory", (Dir) -> Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>>)
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try std.testing.expectEqual(Target.wasi_read_directory, try target_for_tokens(std.testing.allocator, tokens));
}

test "generic Component async target classifies pinned filesystem descriptor get-type" {
    const source = @embedFile("test/compile_ok/459_wasi_filesystem_get_type_component.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try std.testing.expectEqual(Target.wasi_filesystem_get_type, try target_for_tokens(std.testing.allocator, tokens));
    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "get-type: async func()") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "enum descriptor-type") != null);
}

test "generic Component async target classifies pinned filesystem descriptor sync" {
    const source = @embedFile("test/compile_ok/462_wasi_filesystem_sync_component.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try std.testing.expectEqual(Target.wasi_filesystem_sync, try target_for_tokens(std.testing.allocator, tokens));
    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "sync: async func() -> result<_, error-code>") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "run: async func(file: own<descriptor>)") != null);
}

test "generic Component async target classifies pinned filesystem descriptor get-flags" {
    const source = @embedFile("test/compile_ok/471_wasi_filesystem_get_flags_component.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try std.testing.expectEqual(Target.wasi_filesystem_get_flags, try target_for_tokens(std.testing.allocator, tokens));
    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "get-flags: async func()") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "flags descriptor-flags") != null);
}

test "filesystem descriptor get-flags target rejects a second await" {
    const source =
        \\get_flags = @host_async_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.get-flags", (Dir) -> u8 | FlagsError)
        \\Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
        \\FlagsError error = Io | NoEntry
        \\run(directory Dir) -> u8 | FlagsError {
        \\    pending Future<u8 | FlagsError> = get_flags(directory)
        \\    first u8 | FlagsError = @await(pending)
        \\    second u8 | FlagsError = @await(pending)
        \\    return second
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectError(error.UnsupportedP3AsyncComponent, target_for_tokens(std.testing.allocator, tokens));
}

test "filesystem descriptor sync target rejects a second await" {
    const source = @embedFile("test/compile_err/465_wasi_filesystem_sync_second_await.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectError(error.UnsupportedP3AsyncComponent, target_for_tokens(std.testing.allocator, tokens));
}

test "filesystem descriptor get-type target rejects a second await" {
    const source =
        \\get_type = @host_async_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.get-type", (Dir) -> DescriptorType | FileError)
        \\Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
        \\DescriptorType = Unknown | Directory | RegularFile
        \\FileError error = Io | NoEntry
        \\run(directory Dir) -> DescriptorType | FileError {
        \\    pending Future<DescriptorType | FileError> = get_type(directory)
        \\    first DescriptorType | FileError = @await(pending)
        \\    second DescriptorType | FileError = @await(pending)
        \\    return second
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectError(error.UnsupportedP3AsyncComponent, target_for_tokens(std.testing.allocator, tokens));
}

test "generic Component async target rejects a non-pinned read-directory descriptor" {
    const source =
        \\.host_read_directory = @host_func("do:filesystem/types@0.3.0", "descriptor.read-directory", (Dir) -> Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>>)
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try std.testing.expectError(error.UnsupportedP3AsyncComponent, target_for_tokens(std.testing.allocator, tokens));
}

test "generic Component async target classifies a descriptor-owned stream reader" {
    const source =
        \\probe_read = @host_func("do:stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, ProbeError>>>)
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    const target = try target_for_tokens(std.testing.allocator, tokens);
    try std.testing.expectEqual(Target.stream_reader, target);
}

test "generic Component async target classifies a descriptor-owned record stream" {
    const source =
        \\probe_read = @host_func("do:record-stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<ProbeEntry>, Future<Result<nil, ProbeError>>>)
        \\async run() -> Result<nil, ProbeError> {
        \\    handles Tuple<Stream<ProbeEntry>, Future<Result<nil, ProbeError>>> = probe_read()
        \\    reader Stream<ProbeEntry> = @get(handles, 0)
        \\    completion Future<Result<nil, ProbeError>> = @get(handles, 1)
        \\    loop {
        \\        pending Future<Result<ProbeEntry, nil>> = @next(reader)
        \\        item Result<ProbeEntry, nil> = await(pending)
        \\        if @is(item, Ok) {
        \\            entry ProbeEntry = item
        \\            _ = entry
        \\        } else {
        \\            break
        \\        }
        \\    }
        \\    completed Result<nil, ProbeError> = await(completion)
        \\    if @is(completed, Err) return completed
        \\    return Ok()
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectEqual(Target.record_stream, try target_for_tokens(std.testing.allocator, tokens));
}

test "generic Component async target requires the bounded list-owned resource source" {
    const source =
        \\probe_read = @host_func("do:record-resource-list-stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<[ResourceEntry]>, Future<Result<nil, ProbeError>>>)
        \\Ticket = @wasi_resource("do:record-resource-list-stream-probe/source/ticket", { .id i64 })
        \\ResourceEntry { .ticket Ticket }
        \\ProbeError error = Io
        \\async run() -> Result<nil, ProbeError> {
        \\    handles Tuple<Stream<[ResourceEntry]>, Future<Result<nil, ProbeError>>> = probe_read()
        \\    reader Stream<[ResourceEntry]> = @get(handles, 0)
        \\    completion Future<Result<nil, ProbeError>> = @get(handles, 1)
        \\    pending Future<Result<[ResourceEntry], nil>> = @next(reader)
        \\    item Result<[ResourceEntry], nil> = await(pending)
        \\    _ = item
        \\    completed Result<nil, ProbeError> = await(completion)
        \\    if @is(completed, Err) return completed
        \\    return Ok()
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectEqual(Target.record_resource_list_stream, try target_for_tokens(std.testing.allocator, tokens));

    const repeated_read =
        \\probe_read = @host_func("do:record-resource-list-stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<[ResourceEntry]>, Future<Result<nil, ProbeError>>>)
        \\Ticket = @wasi_resource("do:record-resource-list-stream-probe/source/ticket", { .id i64 })
        \\ResourceEntry { .ticket Ticket }
        \\ProbeError error = Io
        \\async run() -> Result<nil, ProbeError> {
        \\    handles Tuple<Stream<[ResourceEntry]>, Future<Result<nil, ProbeError>>> = probe_read()
        \\    reader Stream<[ResourceEntry]> = @get(handles, 0)
        \\    completion Future<Result<nil, ProbeError>> = @get(handles, 1)
        \\    first Future<Result<[ResourceEntry], nil>> = @next(reader)
        \\    first_item Result<[ResourceEntry], nil> = await(first)
        \\    _ = first_item
        \\    second Future<Result<[ResourceEntry], nil>> = @next(reader)
        \\    second_item Result<[ResourceEntry], nil> = await(second)
        \\    _ = second_item
        \\    completed Result<nil, ProbeError> = await(completion)
        \\    if @is(completed, Err) return completed
        \\    return Ok()
        \\}
        \\start() {}
    ;
    const repeated_tokens = try lexer.tokenize(std.testing.allocator, repeated_read);
    defer std.testing.allocator.free(repeated_tokens);
    try std.testing.expectError(error.UnsupportedP3AsyncComponent, target_for_tokens(std.testing.allocator, repeated_tokens));
}

test "generic Component async target classifies the C-min list resource producer" {
    const source = @embedFile("test/check/447_g6_2_c_min_list_resource_producer.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectEqual(
        Target.record_resource_list_stream_producer,
        try target_for_tokens(std.testing.allocator, tokens),
    );
}

test "generic Component async target classifies the bounded dynamic list producer" {
    const source = @embedFile("test/check/448_g6_2_dynamic_list_resource_producer.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectEqual(
        Target.record_resource_list_stream_dynamic_producer,
        try target_for_tokens(std.testing.allocator, tokens),
    );
}

test "generic Component async target classifies the variant resource stream" {
    const source =
        \\probe_read = @host_func("do:variant-resource-stream-canonical@0.1.0", "read-via-stream", () -> Tuple<Stream<Ticket | nil | EventError>, Future<Result<nil, EventError>>>)
        \\Ticket = @wasi_resource("do:variant-resource-stream-canonical/source/ticket", { .id i64 })
        \\EventError error = Io
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try std.testing.expectEqual(Target.variant_resource_stream, try target_for_tokens(std.testing.allocator, tokens));
}

test "v2 variant adapter is opt-in and emits an independent artifact" {
    const source =
        \\probe_read = @host_func("do:variant-resource-stream-canonical@0.1.0", "read-via-stream", () -> Tuple<Stream<Ticket | nil | EventError>, Future<Result<nil, EventError>>>)
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    const wat = try emit_component_wat_v2_for_test(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[event-tag-offset]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[resource-drop]ticket") != null);
}

test "v2 scalar-i64 adapter is opt-in and emits an independent artifact" {
    const source = @embedFile("test/check/431_generated_async_scalar_i64.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    var graph = try codegen_component_async_v2_scalar_adapter.test_i64_graph(std.testing.allocator);
    defer graph.deinit();
    const wat = try emit_component_wat_v2_scalar_i64(std.testing.allocator, program, tokens, &graph);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "generic ABI v2 independent scalar-i64 emitter template") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[scalar-payload] offset=16 byte-size=8 alignment=8 encoding=core-s64") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.load") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.store") != null);
}

test "v2 promotion dispatches only the independent private shapes" {
    const variant_source =
        \\probe_read = @host_func("do:variant-resource-stream-canonical@0.1.0", "read-via-stream", () -> Tuple<Stream<Ticket | nil | EventError>, Future<Result<nil, EventError>>>)
    ;
    const variant_tokens = try lexer.tokenize(std.testing.allocator, variant_source);
    defer std.testing.allocator.free(variant_tokens);
    const variant_wat = try emit_component_wat_v2(std.testing.allocator, undefined, variant_tokens, null);
    defer std.testing.allocator.free(variant_wat);
    try std.testing.expect(std.mem.indexOf(u8, variant_wat, "generic ABI v2 independent descriptor emitter template") != null);

    const scalar_source = @embedFile("test/check/431_generated_async_scalar_i64.do");
    const scalar_tokens = try lexer.tokenize(std.testing.allocator, scalar_source);
    defer std.testing.allocator.free(scalar_tokens);
    var scalar_program = try parser.parse_program(std.testing.allocator, scalar_tokens, scalar_source.len);
    defer scalar_program.deinit(std.testing.allocator);
    var scalar_graph = try codegen_component_async_v2_scalar_adapter.test_i64_graph(std.testing.allocator);
    defer scalar_graph.deinit();
    const scalar_wat = try emit_component_wat_v2(std.testing.allocator, scalar_program, scalar_tokens, &scalar_graph);
    defer std.testing.allocator.free(scalar_wat);
    try std.testing.expect(std.mem.indexOf(u8, scalar_wat, "generic ABI v2 independent scalar-i64 emitter template") != null);
}

test "v2 promotion rejects v1 generated scalar before WAT emission" {
    const source = @embedFile("test/check/430_generated_async_scalar.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    var graph = try generated_scalar_test_graph(std.testing.allocator);
    defer graph.deinit();

    try std.testing.expectError(
        error.UnsupportedGenericAbiV2Promotion,
        emit_component_wat_v2(std.testing.allocator, program, tokens, &graph),
    );
}

test "v2 promotion leaves default variant dispatch on v1" {
    const source =
        \\probe_read = @host_func("do:variant-resource-stream-canonical@0.1.0", "read-via-stream", () -> Tuple<Stream<Ticket | nil | EventError>, Future<Result<nil, EventError>>>)
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    const wat = try emit_component_wat(std.testing.allocator, undefined, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "generic ABI v2 independent descriptor emitter template") == null);
}

test "HTTP WIT package selection requires the exact service plan" {
    const http_source =
        \\send = @host_async_func("wasi:http/client@0.3.0-rc-2025-09-16", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
        \\HttpHeaders = @wasi_resource("http/types/fields", { .id i64 })
        \\HttpRequestOptions = @wasi_resource("http/types/request-options", { .id i64 })
        \\HttpRequest = @wasi_resource("http/types/request", { .id i64 })
        \\HttpResponse = @wasi_resource("http/types/response", { .id i64 })
        \\async handle(request HttpRequest) -> Result<HttpResponse, HttpError> {
        \\    pending Future<Result<HttpResponse, HttpError>> = send(request)
        \\    return await(pending)
        \\}
    ;
    const http_tokens = try lexer.tokenize(std.testing.allocator, http_source);
    defer std.testing.allocator.free(http_tokens);
    try std.testing.expect(try requires_http_wit_package(std.testing.allocator, http_tokens));

    const clocks_source =
        \\wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
    ;
    const clocks_tokens = try lexer.tokenize(std.testing.allocator, clocks_source);
    defer std.testing.allocator.free(clocks_tokens);
    try std.testing.expect(!(try requires_http_wit_package(std.testing.allocator, clocks_tokens)));
}

test "generic Component async target rejects scalar control flow without a lowering" {
    const source =
        \\wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\async run(how_long u64) -> nil {
        \\    pending Future<nil> = wait_for(how_long)
        \\    if true {
        \\        await(pending)
        \\    }
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    try std.testing.expectError(
        error.UnsupportedP3AsyncComponent,
        emit_component_wat(std.testing.allocator, program, tokens, null),
    );
}

test "generic Component async target admits the exact host-driven Future slice" {
    const source =
        \\work = @host_async_func("do:generic-async-probe/host@0.1.0", "work", () -> nil)
        \\run() -> nil {
        \\    ready Future<nil> = @async(work())
        \\    @await(ready)
        \\    middle Future<nil> = @async(work())
        \\    @await(middle)
        \\    pending Future<nil> = @async(work())
        \\    @cancel(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectEqual(Target.generic_async, try target_for_tokens(std.testing.allocator, tokens));
}

test "generated scalar async target is distinct from unit generic lowering" {
    const source = @embedFile("test/check/430_generated_async_scalar.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var graph = try generated_scalar_test_graph(std.testing.allocator);
    defer graph.deinit();

    try std.testing.expectEqual(
        Target.generated_async_scalar,
        try target_for_tokens_with_graph(std.testing.allocator, tokens, &graph),
    );
}

test "generated scalar async target emits its WAT and WIT contracts" {
    const source = @embedFile("test/check/430_generated_async_scalar.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    var graph = try generated_scalar_test_graph(std.testing.allocator);
    defer graph.deinit();

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, &graph);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lower][future-read-0]completion") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[scalar-payload] offset=12 byte-size=4 alignment=4 encoding=core-u32") != null);

    const wit = try emit_component_wit_with_graph(std.testing.allocator, tokens, &graph);
    defer std.testing.allocator.free(wit);
    try std.testing.expectEqualStrings(@embedFile("generated_async_scalar_component.wit"), wit);
}

fn generated_scalar_test_graph(allocator: std.mem.Allocator) !module_graph_types.ModuleGraph {
    const lowerings = try allocator.alloc(module_graph_types.GeneratedAsyncLowering, 1);
    errdefer allocator.free(lowerings);
    lowerings[0] = .{
        .locator = try allocator.dupe(u8, "do:generic-async-scalar-probe/host@0.1.0"),
        .member = try allocator.dupe(u8, "completion"),
        .source_signature = try allocator.dupe(u8, "() -> Future<u32>"),
        .wit_package = try allocator.dupe(u8, "do:generic-async-scalar-probe@0.1.0"),
        .wit_world = try allocator.dupe(u8, "probe"),
        .wit_interface = try allocator.dupe(u8, "host"),
        .wit_member = try allocator.dupe(u8, "completion"),
        .async_import_module = try allocator.dupe(u8, "do:generic-async-scalar-probe/host@0.1.0"),
        .async_import_name = try allocator.dupe(u8, "[async-lower][future-read-0]completion"),
        .completion = try allocator.dupe(u8, "completion"),
        .wit_sha256 = [_]u8{0} ** 32,
        .payload = .{
            .core_type = try allocator.dupe(u8, "i32"),
            .offset = 12,
            .byte_size = 4,
            .alignment = 4,
            .encoding = try allocator.dupe(u8, "core-u32"),
        },
    };
    return .{
        .allocator = allocator,
        .dep_root = "",
        .modules = &.{},
        .generated_async_lowerings = lowerings,
    };
}

test "generic Component async target rejects an async root declaration" {
    const source =
        \\work = @host_async_func("do:generic-async-probe/host@0.1.0", "work", () -> nil)
        \\async run() -> nil {
        \\    ready Future<nil> = @async(work())
        \\    @await(ready)
        \\    middle Future<nil> = @async(work())
        \\    @await(middle)
        \\    pending Future<nil> = @async(work())
        \\    @cancel(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try std.testing.expectError(
        error.UnsupportedP3AsyncComponent,
        target_for_tokens(std.testing.allocator, tokens),
    );
}

test "generic Component async target emits stable host and async metadata" {
    const source =
        \\work = @host_async_func("do:generic-async-probe/host@0.1.0", "work", () -> nil)
        \\
        \\run() -> nil {
        \\    ready Future<nil> = @async(work())
        \\    @await(ready)
        \\    middle Future<nil> = @async(work())
        \\    @await(middle)
        \\    pending Future<nil> = @async(work())
        \\    @cancel(pending)
        \\}
        \\
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "do:generic-async-probe/host@0.1.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lift]run") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[callback][async-lift]run") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[task-return]run") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[subtask-cancel]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[subtask-drop]") != null);
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, wat, "call $work"));

    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expectEqualStrings(
        \\package do:generic-async-probe@0.1.0;
        \\
        \\interface host {
        \\  work: func();
        \\}
        \\
        \\world probe {
        \\  import host;
        \\  export run: async func();
        \\}
        \\
    , wit);
}

test "generic runtime async target emits reachable pending and cancel paths" {
    const source = @embedFile("test/check/427_generic_async_runtime_contract.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    try std.testing.expectEqual(Target.generic_async, try target_for_tokens(std.testing.allocator, tokens));
    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lower]work") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $subtask-cancel") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $subtask-drop") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $waitable-set-drop") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $context-get-0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $task-return") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[generic-async-runtime] cancel-blocked") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const -1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[generic-async-runtime] pending") != null);
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, wat, "call $host-work"));
    try std.testing.expect(std.mem.indexOf(u8, wat, "]run") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func (export \"[callback][async-lift]run\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func (export \"[callback][async-lift]run\") (type $async-run-callback)\n    unreachable") == null);

    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "package do:generic-async-runtime-probe@0.1.0;") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "work: async func();") != null);
}

test "generic Component async target accepts the registered scalar if probe" {
    const source =
        \\wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\wait_until = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-until", (u64) -> nil)
        \\async run(input u64) -> nil {
        \\    if @eq(input, 27815) {
        \\        first Future<nil> = wait_for(input)
        \\        await(first)
        \\        return
        \\    } else {
        \\        second Future<nil> = wait_until(input)
        \\        await(second)
        \\        return
        \\    }
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.eq") != null);
}

test "generic Component async target emits the pinned CLI stdin stream operations" {
    const source =
        \\stdin_read = @host_func("wasi:cli/stdin@0.3.0-rc-2025-09-16", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, StdinError>>>)
        \\StdinError error = Io | IllegalByteSequence | Pipe
        \\async run() -> nil {
        \\    handles Tuple<Stream<u8>, Future<Result<nil, StdinError>>> = stdin_read()
        \\    reader Stream<u8> = @get(handles, 0)
        \\    completion Future<Result<nil, StdinError>> = @get(handles, 1)
        \\    pending Future<Result<u8, nil>> = @next(reader)
        \\    item Result<u8, nil> = await(pending)
        \\    _ = item
        \\    second_pending Future<Result<u8, nil>> = @next(reader)
        \\    second_item Result<u8, nil> = await(second_pending)
        \\    _ = second_item
        \\    eof_pending Future<Result<u8, nil>> = @next(reader)
        \\    eof Result<u8, nil> = await(eof_pending)
        \\    _ = eof
        \\    @cancel(completion)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[stream-acquire]read-via-stream") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lower][stream-read-0]read-via-stream") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lower][future-read-1]read-via-stream") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lower][future-cancel-read-1]read-via-stream") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[future-drop-readable-1]read-via-stream") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[stream-drop-readable-0]read-via-stream") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[future-drop-readable-1]read-via-stream") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[stream-eof]Err(nil)") != null);

    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "world stream-stdin-probe") != null);
}

test "generic Component async target emits a descriptor-owned stream reader" {
    const source =
        \\probe_read = @host_func("do:stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, ProbeError>>>)
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\async run() -> nil {
        \\    handles Tuple<Stream<u8>, Future<Result<nil, ProbeError>>> = probe_read()
        \\    reader Stream<u8> = @get(handles, 0)
        \\    completion Future<Result<nil, ProbeError>> = @get(handles, 1)
        \\    pending Future<Result<u8, nil>> = @next(reader)
        \\    item Result<u8, nil> = await(pending)
        \\    _ = item
        \\    @cancel(completion)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "do:stream-probe/source@0.1.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lower][stream-read-0]read-via-stream") != null);

    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "package do:stream-probe@0.1.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "world stream-probe") != null);
}

test "generic Component async writer exposes WIT and emits WAT lowering" {
    const source =
        \\stdout_write = @host_async_func("wasi:cli/stdout@0.3.0-rc-2025-09-16", "write-via-stream", (StreamWriter<u8>) -> Result<nil, StdoutError>)
        \\async write(writer StreamWriter<u8>) -> Result<nil, StdoutError> {
        \\    defer close(writer)
        \\    pending Future<Result<nil, StdoutError>> = stdout_write(writer)
        \\    return await(pending)
        \\}
        \\StdoutError error = Io
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectEqual(Target.stream_writer, try target_for_tokens(std.testing.allocator, tokens));

    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "package wasi:cli@0.3.0-rc-2025-09-16") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "export write: async func(data: stream<u8>)") != null);

    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[writer-endpoint-mode] forwarded-reader") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $writer-enqueue") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lower][stream-write-0]write-via-stream") != null);
}

test "generic Component async target routes clocks, HTTP service, and private resource Result emitters" {
    const scalar_source =
        \\wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\async run(how_long u64) -> nil {
        \\    pending Future<nil> = wait_for(how_long)
        \\    await(pending)
        \\}
        \\start() {}
    ;
    const scalar_tokens = try lexer.tokenize(std.testing.allocator, scalar_source);
    defer std.testing.allocator.free(scalar_tokens);
    var scalar_program = try parser.parse_program(std.testing.allocator, scalar_tokens, scalar_source.len);
    defer scalar_program.deinit(std.testing.allocator);
    const scalar_wat = try emit_component_wat(std.testing.allocator, scalar_program, scalar_tokens, null);
    defer std.testing.allocator.free(scalar_wat);
    try std.testing.expect(std.mem.indexOf(u8, scalar_wat, "[async-lower]wait-for") != null);

    const http_source =
        \\send = @host_async_func("wasi:http/client@0.3.0-rc-2025-09-16", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
        \\HttpHeaders = @wasi_resource("http/types/fields", { .id i64 })
        \\HttpRequestOptions = @wasi_resource("http/types/request-options", { .id i64 })
        \\HttpRequest = @wasi_resource("http/types/request", { .id i64 })
        \\HttpResponse = @wasi_resource("http/types/response", { .id i64 })
        \\HttpError error = HttpFailure
        \\async handle(request HttpRequest) -> Result<HttpResponse, HttpError> {
        \\    pending Future<Result<HttpResponse, HttpError>> = send(request)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const http_tokens = try lexer.tokenize(std.testing.allocator, http_source);
    defer std.testing.allocator.free(http_tokens);
    var http_program = try parser.parse_program(std.testing.allocator, http_tokens, http_source.len);
    defer http_program.deinit(std.testing.allocator);
    const http_wat = try emit_component_wat(std.testing.allocator, http_program, http_tokens, null);
    defer std.testing.allocator.free(http_wat);
    try std.testing.expect(std.mem.indexOf(u8, http_wat, "[task-return]handle") != null);
    const http_wit = try emit_component_wit(std.testing.allocator, http_tokens);
    defer std.testing.allocator.free(http_wit);
    try std.testing.expect(std.mem.indexOf(u8, http_wit, "world service") != null);
    try std.testing.expect(std.mem.indexOf(u8, http_wit, "interface client") != null);

    const resource_source =
        \\dispatch = @host_async_func("do:resource-probe/http@0.1.0", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
        \\HttpRequest = @wasi_resource("do:resource-probe/http/request", { .id i64 })
        \\HttpResponse = @wasi_resource("do:resource-probe/http/response", { .id i64 })
        \\HttpError error = HttpFailure
        \\async run(request HttpRequest) -> Result<HttpResponse, HttpError> {
        \\    pending Future<Result<HttpResponse, HttpError>> = dispatch(request)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const resource_tokens = try lexer.tokenize(std.testing.allocator, resource_source);
    defer std.testing.allocator.free(resource_tokens);
    var resource_program = try parser.parse_program(std.testing.allocator, resource_tokens, resource_source.len);
    defer resource_program.deinit(std.testing.allocator);
    const resource_wat = try emit_component_wat(std.testing.allocator, resource_program, resource_tokens, null);
    defer std.testing.allocator.free(resource_wat);
    try std.testing.expect(std.mem.indexOf(u8, resource_wat, "[async-lower]send") != null);
    const resource_wit = try emit_component_wit(std.testing.allocator, resource_tokens);
    defer std.testing.allocator.free(resource_wit);
    try std.testing.expect(std.mem.indexOf(u8, resource_wit, "world async-resource-probe") != null);

    const owned_error_source =
        \\send = @host_async_func("do:resource-probe-owned-error/http@0.1.0", "send", (HttpRequest) -> Result<HttpResponse, HttpErrorResource>)
        \\HttpRequest = @wasi_resource("do:resource-probe-owned-error/http/request", { .id i64 })
        \\HttpResponse = @wasi_resource("do:resource-probe-owned-error/http/response", { .id i64 })
        \\HttpErrorResource = @wasi_resource("do:resource-probe-owned-error/http/error-resource", { .id i64 })
        \\async run(request HttpRequest) -> Result<HttpResponse, HttpErrorResource> {
        \\    pending Future<Result<HttpResponse, HttpErrorResource>> = send(request)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const owned_error_tokens = try lexer.tokenize(std.testing.allocator, owned_error_source);
    defer std.testing.allocator.free(owned_error_tokens);
    var owned_error_program = try parser.parse_program(std.testing.allocator, owned_error_tokens, owned_error_source.len);
    defer owned_error_program.deinit(std.testing.allocator);
    try std.testing.expectEqual(Target.resource_result_2word, try target_for_tokens(std.testing.allocator, owned_error_tokens));
    const owned_error_wat = try emit_component_wat(std.testing.allocator, owned_error_program, owned_error_tokens, null);
    defer std.testing.allocator.free(owned_error_wat);
    try std.testing.expect(std.mem.indexOf(u8, owned_error_wat, ";; [resource-owned-error-result]") != null);
    const owned_error_wit = try emit_component_wit(std.testing.allocator, owned_error_tokens);
    defer std.testing.allocator.free(owned_error_wit);
    try std.testing.expect(std.mem.indexOf(u8, owned_error_wit, "world owned-error-result-probe") != null);
}

test "generic Component async target routes the HTTP response status probe" {
    const source =
        \\get_status = @host_func("wasi:http/types@0.3.0-rc-2025-09-16", "response.get-status-code", (HttpResponse) -> u16)
        \\drop_response = @host_func("wasi:http/types@0.3.0-rc-2025-09-16", "response.drop", (HttpResponse) -> nil)
        \\HttpResponse = @wasi_resource("http/types/response", { .id i64 })
        \\run(response HttpResponse) -> u16 {
        \\    status u16 = get_status(response)
        \\    drop_response(response)
        \\    return status
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[method]response.get-status-code") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[resource-drop]response") != null);

    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "world http-status-probe") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "get-status-code: func() -> u16") != null);
}

test "generic Component async target routes direct HTTP client send" {
    const source =
        \\send = @host_async_func("wasi:http/client@0.3.0-rc-2025-09-16", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
        \\HttpHeaders = @wasi_resource("http/types/fields", { .id i64 })
        \\HttpRequestOptions = @wasi_resource("http/types/request-options", { .id i64 })
        \\HttpRequest = @wasi_resource("http/types/request", { .id i64 })
        \\HttpResponse = @wasi_resource("http/types/response", { .id i64 })
        \\HttpError error = HttpFailure
        \\async run(request HttpRequest) -> Result<HttpResponse, HttpError> {
        \\    pending Future<Result<HttpResponse, HttpError>> = send(request)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[task-return]run") != null);
    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "world http-client-probe") != null);
}
