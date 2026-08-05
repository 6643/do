const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const async_model = @import("codegen_async_model.zig");
const component_async_plan = @import("codegen_component_async_plan.zig");
const gc_async_frame = @import("codegen_gc_async_frame.zig");
const async_byte_budget = @import("async_byte_budget.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");
const sema_tokens = @import("sema_tokens.zig");

const string_token_body = sema_tokens.string_token_body;
const tok_eq = sema_tokens.tok_eq;
const resource_result_buffer_slot_bytes: u64 = 8;

pub fn emit_component_wat(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) ![]u8 {
    _ = program;
    _ = module_graph;
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    var plan = component_async_plan.ComponentAsyncFunctionPlan.analyze(allocator, tokens, registry) catch return error.UnsupportedP3AsyncResourceComponent;
    defer plan.deinit(allocator);
    const descriptor = try require_probe_shape(tokens, &plan);
    return if (plan.terminal == .cancel)
        emit_resource_async_cancel_core_wat(allocator, descriptor)
    else
        emit_resource_async_core_wat(allocator, descriptor);
}

pub fn emit_component_wit(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]u8 {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    var plan = component_async_plan.ComponentAsyncFunctionPlan.analyze(allocator, tokens, registry) catch return error.UnsupportedP3AsyncResourceComponent;
    defer plan.deinit(allocator);
    const descriptor = try require_probe_shape(tokens, &plan);
    if (plan.terminal == .cancel) return allocator.dupe(u8, if (descriptor_matches_owned_error_probe(descriptor))
        resource_owned_error_cancel_component_wit
    else
        resource_async_cancel_component_wit);
    return allocator.dupe(u8, if (descriptor_matches_owned_error_probe(descriptor))
        resource_owned_error_component_wit
    else
        resource_async_component_wit);
}

fn require_probe_shape(
    tokens: []const lexer.Token,
    plan: *const component_async_plan.ComponentAsyncFunctionPlan,
) !p3_async_manifest.Descriptor {
    if (plan.operations.len != 1 or
        plan.operations[0].payload_shape != .resource_result_2word or
        (plan.terminal != .return_await and plan.terminal != .cancel) or
        plan.async_plan != null) return error.UnsupportedP3AsyncResourceComponent;
    const descriptor = plan.operations[0].descriptor;
    if (descriptor_matches_probe(descriptor)) {
        if (!matches_probe_resources(tokens)) return error.UnsupportedP3AsyncResourceComponent;
        return descriptor;
    }
    if (descriptor_matches_owned_error_probe(descriptor)) {
        if (!matches_owned_error_probe_resources(tokens)) return error.UnsupportedP3AsyncResourceComponent;
        return descriptor;
    }
    return error.UnsupportedP3AsyncResourceComponent;
}

fn descriptor_matches_probe(descriptor: p3_async_manifest.Descriptor) bool {
    const shape = p3_async_manifest.lowering_shape(descriptor) orelse return false;
    const resource = switch (shape) {
        .resource_result_2word => |value| value,
        else => return false,
    };
    return std.mem.eql(u8, descriptor.locator, "do:resource-probe/http@0.1.0") and
        std.mem.eql(u8, descriptor.member, "send") and
        std.mem.eql(u8, resource.source_param, "HttpRequest") and
        std.mem.eql(u8, descriptor.result, "Result<HttpResponse,HttpError>") and
        std.mem.eql(u8, resource.resource, "request") and
        descriptor.canonical.async_import_module.len != 0 and
        descriptor.canonical.async_import_name.len != 0 and
        std.mem.eql(u8, descriptor.wit.package, "do:resource-probe@0.1.0") and
        std.mem.eql(u8, descriptor.wit.interface, "http") and
        std.mem.eql(u8, descriptor.wit.operation, "send") and
        std.mem.eql(u8, descriptor.wit.world, "async-resource-probe") and
        std.mem.eql(u8, descriptor.wit.parameter, "request");
}

fn matches_probe_resources(tokens: []const lexer.Token) bool {
    return has_resource_decl(tokens, "HttpRequest", "do:resource-probe/http/request") and
        has_resource_decl(tokens, "HttpResponse", "do:resource-probe/http/response");
}

fn descriptor_matches_owned_error_probe(descriptor: p3_async_manifest.Descriptor) bool {
    const shape = p3_async_manifest.lowering_shape(descriptor) orelse return false;
    const resource = switch (shape) {
        .resource_result_2word => |value| value,
        else => return false,
    };
    return std.mem.eql(u8, descriptor.locator, "do:resource-probe-owned-error/http@0.1.0") and
        std.mem.eql(u8, descriptor.member, "send") and
        std.mem.eql(u8, resource.source_param, "HttpRequest") and
        std.mem.eql(u8, descriptor.result, "Result<HttpResponse,HttpErrorResource>") and
        std.mem.eql(u8, resource.resource, "request") and
        descriptor.canonical.async_import_module.len != 0 and
        descriptor.canonical.async_import_name.len != 0 and
        std.mem.eql(u8, descriptor.wit.package, "do:resource-probe-owned-error@0.1.0") and
        std.mem.eql(u8, descriptor.wit.interface, "http") and
        std.mem.eql(u8, descriptor.wit.operation, "send") and
        std.mem.eql(u8, descriptor.wit.world, "owned-error-result-probe") and
        std.mem.eql(u8, descriptor.wit.parameter, "request");
}

fn matches_owned_error_probe_resources(tokens: []const lexer.Token) bool {
    return has_resource_decl(tokens, "HttpRequest", "do:resource-probe-owned-error/http/request") and
        has_resource_decl(tokens, "HttpResponse", "do:resource-probe-owned-error/http/response") and
        has_resource_decl(tokens, "HttpErrorResource", "do:resource-probe-owned-error/http/error-resource");
}

fn has_resource_decl(tokens: []const lexer.Token, type_name: []const u8, path: []const u8) bool {
    var i: usize = 0;
    while (i + 5 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident or !std.mem.eql(u8, tokens[i].lexeme, type_name) or !tok_eq(tokens[i + 1], "=") or !tok_eq(tokens[i + 2], "@") or !tok_eq(tokens[i + 3], "wasi_resource") or !tok_eq(tokens[i + 4], "(")) continue;
        const resource_path = string_token_body(tokens[i + 5].lexeme) orelse continue;
        if (std.mem.eql(u8, resource_path, path)) return true;
    }
    return false;
}

fn emit_resource_async_core_wat(allocator: std.mem.Allocator, descriptor: p3_async_manifest.Descriptor) ![]u8 {
    var slots = [_]async_model.FrameLayoutSlot{.{
        .name = "result-ptr",
        .storage = .i32,
        .offset = 16,
    }};
    const layout = async_model.FrameLayout{ .size = 24, .slots = &slots };
    var gc_frame_runtime = std.ArrayList(u8).empty;
    defer gc_frame_runtime.deinit(allocator);
    try gc_async_frame.emit_frame_table_layout(allocator, &gc_frame_runtime, layout);
    try append_canonical_buffer_metadata(allocator, &gc_frame_runtime);
    try gc_async_frame.emit_frame_table_allocator_with_bytes(allocator, &gc_frame_runtime, layout.size);

    const async_import = try std.fmt.allocPrint(
        allocator,
        "(import \"{s}\" \"{s}\"",
        .{ descriptor.canonical.async_import_module, descriptor.canonical.async_import_name },
    );
    defer allocator.free(async_import);
    var wat = try allocator.dupe(u8, resource_async_core_wat);
    wat = try replace_and_free(allocator, wat, "[gc-frame-runtime]", gc_frame_runtime.items);
    wat = try replace_and_free(allocator, wat, "(import \"do:resource-probe/http@0.1.0\" \"[async-lower]send\"", async_import);
    const error_drop_import = if (descriptor_matches_owned_error_probe(descriptor))
        try std.fmt.allocPrint(
            allocator,
            "  (import \"{s}\" \"[resource-drop]error-resource\" (func $drop-error-resource (type $resource-drop)))\n",
            .{descriptor.canonical.async_import_module},
        )
    else
        try allocator.dupe(u8, "");
    defer allocator.free(error_drop_import);
    const result_marker = if (descriptor_matches_owned_error_probe(descriptor))
        "  ;; [resource-owned-error-result]\n"
    else
        "";
    wat = try replace_and_free(allocator, wat, "[resource-owned-error-result]", result_marker);
    wat = try replace_and_free(allocator, wat, "[resource-owned-error-drop-import]", error_drop_import);
    wat = try replace_and_free(allocator, wat, "do:resource-probe/http@0.1.0", descriptor.canonical.async_import_module);
    return wat;
}

fn emit_resource_async_cancel_core_wat(allocator: std.mem.Allocator, descriptor: p3_async_manifest.Descriptor) ![]u8 {
    const async_import = try std.fmt.allocPrint(
        allocator,
        "(import \"{s}\" \"{s}\"",
        .{ descriptor.canonical.async_import_module, descriptor.canonical.async_import_name },
    );
    defer allocator.free(async_import);
    const error_drop_import = if (descriptor_matches_owned_error_probe(descriptor))
        try std.fmt.allocPrint(
            allocator,
            "  (import \"{s}\" \"[resource-drop]error-resource\" (func $drop-error-resource (type $resource-drop)))\n",
            .{descriptor.canonical.async_import_module},
        )
    else
        try allocator.dupe(u8, "");
    defer allocator.free(error_drop_import);
    var wat = try allocator.dupe(u8, resource_async_cancel_core_wat);
    wat = try replace_and_free(allocator, wat, "[resource-owned-error-cancel-drop-import]", error_drop_import);
    wat = try replace_and_free(allocator, wat, "(import \"do:resource-probe/http@0.1.0\" \"[async-lower]send\"", async_import);
    return replace_and_free(allocator, wat, "do:resource-probe/http@0.1.0", descriptor.canonical.async_import_module);
}

fn append_canonical_buffer_metadata(allocator: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    const bytes = try async_byte_budget.bytes_for_canonical_buffer(0, resource_result_buffer_slot_bytes);
    const metadata = try std.fmt.allocPrint(allocator, "  ;; [canonical-buffer-bytes] {d}\n", .{bytes});
    defer allocator.free(metadata);
    try out.appendSlice(allocator, metadata);
}

fn replace_and_free(allocator: std.mem.Allocator, input: []u8, needle: []const u8, replacement: []const u8) ![]u8 {
    const replaced = try replace_all(allocator, input, needle, replacement);
    allocator.free(input);
    return replaced;
}

fn replace_all(allocator: std.mem.Allocator, input: []const u8, needle: []const u8, replacement: []const u8) ![]u8 {
    if (needle.len == 0) return error.UnsupportedP3AsyncResourceComponent;
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var remainder = input;
    while (std.mem.indexOf(u8, remainder, needle)) |idx| {
        try out.appendSlice(allocator, remainder[0..idx]);
        try out.appendSlice(allocator, replacement);
        remainder = remainder[idx + needle.len ..];
    }
    try out.appendSlice(allocator, remainder);
    return out.toOwnedSlice(allocator);
}

const resource_async_component_wit = @embedFile("p3_async_resource_probe.wit");
const resource_async_cancel_component_wit = @embedFile("p3_async_resource_cancel_probe.wit");
const resource_owned_error_component_wit = @embedFile("p3_async_resource_owned_error_probe.wit");
const resource_owned_error_cancel_component_wit = @embedFile("p3_async_resource_owned_error_cancel_probe.wit");

const resource_async_cancel_core_wat =
    \\(module
    \\  (type $async-lower-send (func (param i32 i32) (result i32)))
    \\  (type $resource-drop (func (param i32)))
    \\  (type $task-return (func))
    \\  (type $root-noargs (func))
    \\  (type $root-cancel (func (param i32) (result i32)))
    \\  (type $async-run (func (param i32) (result i32)))
    \\  (type $async-run-callback (func (param i32 i32 i32) (result i32)))
    \\  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
    \\  (import "do:resource-probe/http@0.1.0" "[async-lower]send"
    \\    (func $send (type $async-lower-send)))
    \\  (import "do:resource-probe/http@0.1.0" "[resource-drop]request"
    \\    (func $drop-request (type $resource-drop)))
    \\  (import "do:resource-probe/http@0.1.0" "[resource-drop]response"
    \\    (func $drop-response (type $resource-drop)))
    \\[resource-owned-error-cancel-drop-import]
    \\  (import "[export]$root" "[task-cancel]" (func $task-cancel (type $root-noargs)))
    \\  (import "$root" "[subtask-cancel]" (func $subtask-cancel (type $root-cancel)))
    \\  (import "$root" "[subtask-drop]" (func $subtask-drop (type $resource-drop)))
    \\  (import "[export]$root" "[task-return]cancel" (func $task-return (type $task-return)))
    \\  (memory (export "memory") 1)
    \\  (func (export "[async-lift]cancel") (type $async-run)
    \\    (local $subtask i32)
    \\    local.get 0
    \\    i32.const 0
    \\    call $send
    \\    local.set $subtask
    \\    local.get $subtask
    \\    i32.const 2
    \\    i32.eq
    \\    if (result i32)
    \\      ;; [resource-result-cancel] immediate terminal
    \\      call $task-return
    \\      i32.const 0
    \\    else
    \\      local.get $subtask
    \\      i32.const 4
    \\      i32.shr_u
    \\      call $subtask-cancel
    \\      i32.const 4
    \\      i32.ne
    \\      if
    \\        unreachable
    \\      end
    \\      ;; [resource-result-cancel] pending terminal
    \\      local.get $subtask
    \\      i32.const 4
    \\      i32.shr_u
    \\      call $subtask-drop
    \\      call $task-return
    \\      i32.const 0
    \\    end
    \\  )
    \\  (func (export "[callback][async-lift]cancel") (type $async-run-callback)
    \\    unreachable)
    \\  (func (export "cabi_realloc") (type $cabi-realloc) unreachable)
    \\  (func (export "_initialize"))
    \\)
;

const resource_async_core_wat =
    \\(module
    \\  (type $async-lower-send (func (param i32 i32) (result i32)))
    \\  (type $resource-drop (func (param i32)))
    \\  (type $task-return (func (param i32 i32)))
    \\  (type $waitable-set-new (func (result i32)))
    \\  (type $waitable-join (func (param i32 i32)))
    \\  (type $async-run (func (param i32) (result i32)))
    \\  (type $async-run-callback (func (param i32 i32 i32) (result i32)))
    \\  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
    \\  (type $initialize (func))
    \\  (import "do:resource-probe/http@0.1.0" "[async-lower]send" (func $send (type $async-lower-send)))
    \\  (import "do:resource-probe/http@0.1.0" "[resource-drop]request" (func $drop-request (type $resource-drop)))
    \\  (import "do:resource-probe/http@0.1.0" "[resource-drop]response" (func $drop-response (type $resource-drop)))
    \\[resource-owned-error-drop-import]
    \\[resource-owned-error-result]
    \\  (import "$root" "[waitable-set-new]" (func $waitable-set-new (type $waitable-set-new)))
    \\  (import "$root" "[waitable-set-wait]" (func $waitable-set-wait (param i32 i32) (result i32)))
    \\  (import "$root" "[waitable-join]" (func $waitable-join (type $waitable-join)))
    \\  (import "$root" "[context-get-0]" (func $context-get-0 (result i32)))
    \\  (import "$root" "[context-set-0]" (func $context-set-0 (param i32)))
    \\  (import "[export]$root" "[task-return]run" (func $task-return (type $task-return)))
    \\  (memory (export "memory") 1)
    \\  (global $heap-next (mut i32) (i32.const 65536))
    \\[gc-frame-runtime]
    \\  (func $result-buffer-for-handle (param $handle i32) (result i32)
    \\    (local $required-bytes i32)
    \\    i64.const 8
    \\    call $async-byte-budget-reserve
    \\    i32.eqz
    \\    if unreachable end
    \\    local.get $handle
    \\    i32.const 3
    \\    i32.shl
    \\    i32.const 8
    \\    i32.add
    \\    local.tee $required-bytes
    \\    memory.size
    \\    i32.const 16
    \\    i32.shl
    \\    i32.gt_u
    \\    if
    \\      local.get $required-bytes
    \\      i32.const 65535
    \\      i32.add
    \\      i32.const 16
    \\      i32.shr_u
    \\      memory.size
    \\      i32.sub
    \\      memory.grow
    \\      i32.const -1
    \\      i32.eq
    \\      if
    \\        i64.const 8
    \\        call $async-byte-budget-release
    \\        unreachable
    \\      end
    \\    end
    \\    local.get $handle
    \\    i32.const 3
    \\    i32.shl
    \\  )
    \\  (func $canonical-buffer-release
    \\    i64.const 8
    \\    call $async-byte-budget-release
    \\  )
    \\  (func (export "[async-lift]run") (type $async-run) (param $request i32) (result i32) (local $frame i32) (local $frame-ref (ref $async-frame)) (local $subtask i32)
    \\    i32.const 1
    \\    call $waitable-set-new
    \\    i32.const 0
    \\    i32.const 0
    \\    i32.const 0
    \\    struct.new $async-frame
    \\    call $frame-alloc
    \\    local.tee $frame
    \\    call $context-set-0
    \\    local.get $frame
    \\    table.get $async-frames
    \\    ref.as_non_null
    \\    local.set $frame-ref
    \\    local.get $frame-ref
    \\    local.get $frame
    \\    call $result-buffer-for-handle
    \\    struct.set $async-frame $slot-result-ptr
    \\    local.get $request
    \\    local.get $frame-ref
    \\    struct.get $async-frame $slot-result-ptr
    \\    call $send
    \\    local.set $subtask
    \\    local.get $subtask
    \\    i32.const 2
    \\    i32.eq
    \\    if (result i32)
    \\      i32.const 0
    \\      call $context-set-0
    \\      local.get $frame-ref
    \\      struct.get $async-frame $slot-result-ptr
    \\      i32.load
    \\      local.get $frame-ref
    \\      struct.get $async-frame $slot-result-ptr
    \\      i32.const 4
    \\      i32.add
    \\      i32.load
    \\      call $task-return
    \\      call $canonical-buffer-release
    \\      local.get $frame
    \\      call $frame-free
    \\      i32.const 0
    \\    else
    \\    local.get $subtask
    \\    i32.const 4
    \\    i32.shr_u
    \\    local.get $frame-ref
    \\    struct.get $async-frame $waitable-set
    \\    call $waitable-join
    \\    local.get $frame-ref
    \\    struct.get $async-frame $waitable-set
    \\    i32.const 4
    \\    i32.shl
    \\    i32.const 2
    \\    i32.or
    \\    end
    \\  )
    \\  (func (export "[callback][async-lift]run") (type $async-run-callback) (param i32 i32 i32) (result i32) (local $frame i32) (local $frame-ref (ref $async-frame))
    \\    call $context-get-0
    \\    local.set $frame
    \\    local.get $frame
    \\    table.get $async-frames
    \\    ref.as_non_null
    \\    local.set $frame-ref
    \\    local.get 0
    \\    i32.const 1
    \\    i32.eq
    \\    local.get 2
    \\    i32.const 2
    \\    i32.eq
    \\    i32.and
    \\    if (result i32)
    \\      local.get $frame-ref
    \\      struct.get $async-frame $slot-result-ptr
    \\      i32.load
    \\      local.get $frame-ref
    \\      struct.get $async-frame $slot-result-ptr
    \\      i32.const 4
    \\      i32.add
    \\      i32.load
    \\      call $task-return
    \\      call $canonical-buffer-release
    \\      i32.const 0
    \\      call $context-set-0
    \\      local.get $frame
    \\      call $frame-free
    \\      i32.const 0
    \\    else
    \\      local.get 0
    \\      i32.const 1
    \\      i32.eq
    \\      local.get 2
    \\      i32.const 1
    \\      i32.eq
    \\      i32.and
    \\      if (result i32)
    \\        ;; [resource-result-error-terminal]
    \\        local.get $frame-ref
    \\        struct.get $async-frame $slot-result-ptr
    \\        i32.const 0
    \\        i32.store
    \\        local.get $frame-ref
    \\        struct.get $async-frame $slot-result-ptr
    \\        i32.const 4
    \\        i32.add
    \\        local.get 2
    \\        i32.store
    \\        local.get $frame-ref
    \\        struct.get $async-frame $slot-result-ptr
    \\        i32.load
    \\        local.get $frame-ref
    \\        struct.get $async-frame $slot-result-ptr
    \\        i32.const 4
    \\        i32.add
    \\        i32.load
    \\        call $task-return
    \\        call $canonical-buffer-release
    \\        i32.const 0
    \\        call $context-set-0
    \\        local.get $frame
    \\        call $frame-free
    \\        i32.const 0
    \\      else
    \\        local.get $frame-ref
    \\        struct.get $async-frame $waitable-set
    \\        i32.const 4
    \\        i32.shl
    \\        i32.const 2
    \\        i32.or
    \\      end
    \\    end
    \\  )
    \\  (func (export "cabi_realloc") (type $cabi-realloc) (param $old i32) (param $old-size i32) (param $align i32) (param $size i32) (result i32)
    \\    (local $ptr i32)
    \\    (local $end i32)
    \\    (local $budget-delta i64)
    \\    local.get $size
    \\    local.get $old-size
    \\    i32.gt_u
    \\    if
    \\      local.get $size
    \\      local.get $old-size
    \\      i32.sub
    \\      i64.extend_i32_u
    \\      local.tee $budget-delta
    \\      call $async-byte-budget-reserve
    \\      i32.eqz
    \\      if unreachable end
    \\    else
    \\      local.get $old-size
    \\      local.get $size
    \\      i32.gt_u
    \\      if
    \\        local.get $old-size
    \\        local.get $size
    \\        i32.sub
    \\        i64.extend_i32_u
    \\        call $async-byte-budget-release
    \\      end
    \\    end
    \\    global.get $heap-next
    \\    local.set $ptr
    \\    local.get $ptr
    \\    local.get $size
    \\    i32.add
    \\    local.set $end
    \\    local.get $end
    \\    memory.size
    \\    i32.const 16
    \\    i32.shl
    \\    i32.gt_u
    \\    if
    \\      local.get $end
    \\      i32.const 65535
    \\      i32.add
    \\      i32.const 16
    \\      i32.shr_u
    \\      memory.size
    \\      i32.sub
    \\      memory.grow
    \\      i32.const -1
    \\      i32.eq
    \\      if
    \\        local.get $budget-delta
    \\        call $async-byte-budget-release
    \\        unreachable
    \\      end
    \\    end
    \\    local.get $end
    \\    global.set $heap-next
    \\    local.get $ptr
    \\  )
    \\  (func (export "_initialize") (type $initialize))
    \\)
;

test "private async resource probe emits a two-word Result completion frame" {
    const source =
        \\send = @host_func("do:resource-probe/http@0.1.0", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
        \\HttpRequest = @wasi_resource("do:resource-probe/http/request", { .id i64 })
        \\HttpResponse = @wasi_resource("do:resource-probe/http/response", { .id i64 })
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
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lower]send") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $async-frame (struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(field $slot-result-ptr (mut i32))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(table $async-frames 0 (ref null $async-frame))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "table.get $async-frames") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "$result-buffer-for-handle") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "global $frame-next") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 8") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; [canonical-buffer-bytes] 8") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.const 8\n    call $async-byte-budget-reserve") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $canonical-buffer-release") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $task-return\n      call $canonical-buffer-release\n      local.get $frame\n      call $frame-free") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $task-return\n      call $canonical-buffer-release\n      i32.const 0\n      call $context-set-0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[resource-result-error-terminal]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 0\n        i32.store") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[task-return]run") != null);
    const realloc_start = std.mem.indexOf(u8, wat, "(func (export \"cabi_realloc\")") orelse return error.TestUnexpectedResult;
    const realloc = wat[realloc_start..];
    try std.testing.expect(std.mem.indexOf(u8, realloc, "call $async-byte-budget-reserve") != null);
    try std.testing.expect(std.mem.indexOf(u8, realloc, "call $async-byte-budget-release") != null);
    try std.testing.expect(std.mem.indexOf(u8, realloc, "memory.grow") != null);
}

test "private async resource cancellation emits direct subtask cancellation" {
    const source =
        \\send = @host_func("do:resource-probe/http@0.1.0", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
        \\HttpRequest = @wasi_resource("do:resource-probe/http/request", { .id i64 })
        \\HttpResponse = @wasi_resource("do:resource-probe/http/response", { .id i64 })
        \\HttpError error = HttpFailure
        \\async cancel_request(request HttpRequest) -> nil {
        \\    completion Future<Result<HttpResponse, HttpError>> = send(request)
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
    try std.testing.expect(std.mem.indexOf(u8, wat, "[resource-result-cancel]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[subtask-cancel]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $subtask-cancel") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[subtask-drop]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $subtask-drop") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[task-return]cancel") != null);

    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "world async-resource-cancel-probe") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "export cancel: async func(request: request);") != null);
}

test "private async resource probe checks immediate host completion before joining" {
    const source =
        \\send = @host_func("do:resource-probe/http@0.1.0", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
        \\HttpRequest = @wasi_resource("do:resource-probe/http/request", { .id i64 })
        \\HttpResponse = @wasi_resource("do:resource-probe/http/response", { .id i64 })
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
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 2\n    i32.eq\n    if (result i32)") != null);
}

test "private async resource probe resolves a renamed descriptor binding" {
    const source =
        \\dispatch = @host_func("do:resource-probe/http@0.1.0", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
        \\HttpRequest = @wasi_resource("do:resource-probe/http/request", { .id i64 })
        \\HttpResponse = @wasi_resource("do:resource-probe/http/response", { .id i64 })
        \\HttpError error = HttpFailure
        \\async run(request HttpRequest) -> Result<HttpResponse, HttpError> {
        \\    pending Future<Result<HttpResponse, HttpError>> = dispatch(request)
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
    try std.testing.expect(std.mem.indexOf(u8, wat, "do:resource-probe/http@0.1.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lower]send") != null);

    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "world async-resource-probe") != null);
}

test "private owned-error resource probe emits its private WIT and drop import" {
    const source =
        \\send = @host_func("do:resource-probe-owned-error/http@0.1.0", "send", (HttpRequest) -> Result<HttpResponse, HttpErrorResource>)
        \\HttpRequest = @wasi_resource("do:resource-probe-owned-error/http/request", { .id i64 })
        \\HttpResponse = @wasi_resource("do:resource-probe-owned-error/http/response", { .id i64 })
        \\HttpErrorResource = @wasi_resource("do:resource-probe-owned-error/http/error-resource", { .id i64 })
        \\async run(request HttpRequest) -> Result<HttpResponse, HttpErrorResource> {
        \\    pending Future<Result<HttpResponse, HttpErrorResource>> = send(request)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const descriptor = registry.find("do:resource-probe-owned-error/http@0.1.0", "send") orelse return error.TestUnexpectedResult;
    try std.testing.expect(descriptor_matches_owned_error_probe(descriptor));
    try std.testing.expect(matches_owned_error_probe_resources(tokens));
    const plan = try component_async_plan.ComponentAsyncFunctionPlan.analyze(std.testing.allocator, tokens, registry);
    defer {
        var owned_plan = plan;
        owned_plan.deinit(std.testing.allocator);
    }
    const wat = try emit_component_wat(std.testing.allocator, undefined, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; [resource-owned-error-result]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[resource-drop]error-resource") != null);
    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "world owned-error-result-probe") != null);
}

test "private owned-error resource cancellation preserves its package and resource graph" {
    const source =
        \\send = @host_func("do:resource-probe-owned-error/http@0.1.0", "send", (HttpRequest) -> Result<HttpResponse, HttpErrorResource>)
        \\HttpRequest = @wasi_resource("do:resource-probe-owned-error/http/request", { .id i64 })
        \\HttpResponse = @wasi_resource("do:resource-probe-owned-error/http/response", { .id i64 })
        \\HttpErrorResource = @wasi_resource("do:resource-probe-owned-error/http/error-resource", { .id i64 })
        \\async cancel_request(request HttpRequest) -> nil {
        \\    completion Future<Result<HttpResponse, HttpErrorResource>> = send(request)
        \\    @cancel(completion)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    const wat = try emit_component_wat(std.testing.allocator, undefined, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(import \"do:resource-probe-owned-error/http@0.1.0\" \"[async-lower]send\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[resource-drop]error-resource") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "do:resource-probe/http@0.1.0") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[resource-result-cancel]") != null);

    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "package do:resource-probe-owned-error@0.1.0;") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "world owned-error-resource-cancel-probe") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "use http.{request, response, error-resource};") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "export cancel: async func(request: request);") != null);
}

test "private async resource probe rejects a mismatched task-return shape" {
    const descriptor = p3_async_manifest.Descriptor{
        .locator = "do:resource-probe/http@0.1.0",
        .member = "send",
        .effect = "async",
        .params = &.{"HttpRequest"},
        .result = "Result<HttpResponse,HttpError>",
        .resource = "request",
        .wit_sha256 = null,
        .canonical = .{
            .core_params = &.{ "i32", "i32" },
            .core_results = &.{ "i32", "i32" },
            .completion_params = &.{"i32"},
            .completion = "task-return",
            .result_payload = null,
            .async_import_module = "do:resource-probe/http@0.1.0",
            .async_import_name = "[async-lower]send",
        },
        .wit = .{ .package = "do:resource-probe@0.1.0", .interface = "http", .operation = "send", .world = "async-resource-probe", .parameter = "request" },
    };
    try std.testing.expect(!descriptor_matches_probe(descriptor));
}

test "private async resource probe accepts a registry-provided canonical import" {
    const descriptor = p3_async_manifest.Descriptor{
        .locator = "do:resource-probe/http@0.1.0",
        .member = "send",
        .effect = "async",
        .params = &.{"HttpRequest"},
        .result = "Result<HttpResponse,HttpError>",
        .resource = "request",
        .wit_sha256 = null,
        .canonical = .{
            .core_params = &.{ "i32", "i32" },
            .core_results = &.{ "i32", "i32" },
            .completion_params = &.{ "i32", "i32" },
            .completion = "task-return",
            .result_payload = null,
            .async_import_module = "test:resource-probe/http@0.1.0",
            .async_import_name = "[async-lower]dispatch",
        },
        .wit = .{ .package = "do:resource-probe@0.1.0", .interface = "http", .operation = "send", .world = "async-resource-probe", .parameter = "request" },
    };
    try std.testing.expect(descriptor_matches_probe(descriptor));
    const wat = try emit_resource_async_core_wat(std.testing.allocator, descriptor);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(import \"test:resource-probe/http@0.1.0\" \"[async-lower]dispatch\"") != null);
}
