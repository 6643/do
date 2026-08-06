const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema_tokens = @import("sema_tokens.zig");
const async_model = @import("codegen_async_model.zig");
const async_byte_budget = @import("async_byte_budget.zig");
const component_async_plan = @import("codegen_component_async_plan.zig");
const gc_async_frame = @import("codegen_gc_async_frame.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");
const p3_http_wit_manifest = @import("p3_http_wit_manifest.zig");

const http_locator = "wasi:http/client@0.3.0-rc-2025-09-16";
const http_types_locator = "wasi:http/types@0.3.0-rc-2025-09-16";
const http_package = "wasi:http@0.3.0-rc-2025-09-16";
const cli_stdin_locator = "wasi:cli/stdin@0.3.0-rc-2025-09-16";
const cli_stdin_read_member = "read-via-stream";
const cli_stdin_wit_sha256 = "c12c40df23a0ad562e743487b907113dbc9daadafa347d65d151d210d1292fc7";
const cli_stdout_locator = "wasi:cli/stdout@0.3.0-rc-2025-09-16";
const cli_stdout_write_member = "write-via-stream";
const cli_stdout_wit_sha256 = "03ff93468efa2d4d3e58e441b924e3ee984d4d8b8080ca45646c92a14609acc4";
const http_result_buffer_slot_bytes: u64 = 64;

pub const HttpServicePlan = struct {
    descriptor: p3_async_manifest.Descriptor,
    parameter_name: []const u8,
    future_name: []const u8,
    terminal: HttpServiceTerminal,

    pub fn analyze(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) !?HttpServicePlan {
        try p3_http_wit_manifest.validate_resource_graph();
        const descriptor = registry.find(http_locator, "send") orelse return error.InvalidP3AsyncManifest;
        if (!is_http_send_descriptor(descriptor)) return error.InvalidP3AsyncManifest;

        const host_name = find_http_send_host(tokens) orelse return null;
        if (!has_http_resource_graph(tokens)) return null;
        const handler = find_handler_named(tokens, "handle");
        if (handler) |value| {
            const future = parse_forwarding_body(tokens, value, host_name) orelse return null;
            return .{
                .descriptor = descriptor,
                .parameter_name = value.parameter_name,
                .future_name = future.name,
                .terminal = .return_await,
            };
        }

        const cancellation_handler = find_cancellation_handler(tokens) orelse return null;
        const future = parse_cancellation_body(tokens, cancellation_handler, host_name) orelse return null;

        return .{
            .descriptor = descriptor,
            .parameter_name = cancellation_handler.parameter_name,
            .future_name = future.name,
            .terminal = .cancel,
        };
    }
};

pub const HttpServiceTerminal = enum {
    return_await,
    cancel,
};

pub const HttpClientSendPlan = struct {
    descriptor: p3_async_manifest.Descriptor,
    parameter_name: []const u8,
    future_name: []const u8,

    pub fn analyze(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) !?HttpClientSendPlan {
        try p3_http_wit_manifest.validate_resource_graph();
        const descriptor = registry.find(http_locator, "send") orelse return error.InvalidP3AsyncManifest;
        if (!is_http_send_descriptor(descriptor)) return error.InvalidP3AsyncManifest;

        const host_name = find_http_send_host(tokens) orelse return null;
        const handler = find_handler_named(tokens, "run") orelse return null;
        if (!has_http_resource_graph(tokens)) return null;
        const future = parse_forwarding_body(tokens, handler, host_name) orelse return null;

        return .{
            .descriptor = descriptor,
            .parameter_name = handler.parameter_name,
            .future_name = future.name,
        };
    }
};

pub const HttpRequestSendPlan = struct {
    request_descriptor: p3_async_manifest.Descriptor,
    send_descriptor: p3_async_manifest.Descriptor,
    request_host_name: []const u8,
    send_host_name: []const u8,

    pub fn analyze(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) !?HttpRequestSendPlan {
        try p3_http_wit_manifest.validate_resource_graph();
        const request_descriptor = registry.find(http_types_locator, "request.new") orelse return error.InvalidP3AsyncManifest;
        const send_descriptor = registry.find(http_locator, "send") orelse return error.InvalidP3AsyncManifest;
        const request_shape = p3_async_manifest.lowering_shape(request_descriptor) orelse return null;
        const send_shape = p3_async_manifest.lowering_shape(send_descriptor) orelse return null;
        switch (request_shape) {
            .http_request_constructor => {},
            else => return null,
        }
        switch (send_shape) {
            .http_resource_result => {},
            else => return null,
        }
        if (!is_http_send_descriptor(send_descriptor)) return error.InvalidP3AsyncManifest;
        const request_host_name = find_http_request_new_host(tokens) orelse return null;
        const send_host_name = find_http_send_host(tokens) orelse return null;
        if (!has_http_resource_graph(tokens) or
            !has_http_request_send_handler(tokens, request_host_name, send_host_name)) return null;
        return .{
            .request_descriptor = request_descriptor,
            .send_descriptor = send_descriptor,
            .request_host_name = request_host_name,
            .send_host_name = send_host_name,
        };
    }
};

pub const HttpResponseBodyPlan = struct {
    descriptor: p3_async_manifest.Descriptor,
    host_name: []const u8,
    response_param: []const u8,
    read_count: usize,
    await_completion: bool,

    pub fn analyze(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) !?HttpResponseBodyPlan {
        try p3_http_wit_manifest.validate_resource_graph();
        const descriptor = registry.find(http_types_locator, "response.consume-body") orelse return error.InvalidP3AsyncManifest;
        const shape = p3_async_manifest.lowering_shape(descriptor) orelse return null;
        switch (shape) {
            .http_stream_reader => {},
            else => return null,
        }
        const host_name = find_http_resource_host(
            tokens,
            "response.consume-body",
            "HttpResponse",
            "Tuple<Stream<u8>,Future<Result<option<trailers>,HttpError>>>",
        ) orelse return null;
        if (find_response_body_handler(tokens, host_name)) |handler| {
            return .{
                .descriptor = descriptor,
                .host_name = host_name,
                .response_param = handler.response_param,
                .read_count = 0,
                .await_completion = false,
            };
        }
        const read_handler = find_response_body_read_handler(tokens, host_name) orelse return null;
        return .{
            .descriptor = descriptor,
            .host_name = host_name,
            .response_param = read_handler.response_param,
            .read_count = read_handler.read_count,
            .await_completion = read_handler.await_completion,
        };
    }
};

pub const HttpRequestConstructorPlan = struct {
    descriptor: p3_async_manifest.Descriptor,
    host_name: []const u8,

    pub fn analyze(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) !?HttpRequestConstructorPlan {
        try p3_http_wit_manifest.validate_resource_graph();
        const descriptor = registry.find(http_types_locator, "request.new") orelse return error.InvalidP3AsyncManifest;
        const shape = p3_async_manifest.lowering_shape(descriptor) orelse return null;
        switch (shape) {
            .http_request_constructor => {},
            else => return null,
        }
        const host_name = find_http_request_new_host(tokens) orelse return null;
        if (!has_http_resource_graph(tokens) or !has_http_request_new_handler(tokens, host_name)) return null;
        return .{ .descriptor = descriptor, .host_name = host_name };
    }
};

pub const HttpRequestBodyPlan = struct {
    request_descriptor: p3_async_manifest.Descriptor,
    send_descriptor: p3_async_manifest.Descriptor,
    body_descriptor: p3_async_manifest.Descriptor,
    request_host_name: []const u8,
    send_host_name: []const u8,
    body_host_name: []const u8,
    body_handles_name: []const u8,
    body_reader_name: []const u8,
    body_completion_name: []const u8,
    await_body_completion: bool,
    request_handles_name: []const u8,
    request_name: []const u8,
    transmission_future_name: []const u8,

    pub fn analyze(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) !?HttpRequestBodyPlan {
        try p3_http_wit_manifest.validate_resource_graph();
        const request_descriptor = registry.find(http_types_locator, "request.new") orelse return error.InvalidP3AsyncManifest;
        const send_descriptor = registry.find(http_locator, "send") orelse return error.InvalidP3AsyncManifest;
        const request_shape = p3_async_manifest.lowering_shape(request_descriptor) orelse return null;
        const send_shape = p3_async_manifest.lowering_shape(send_descriptor) orelse return null;
        switch (request_shape) {
            .http_request_constructor => {},
            else => return null,
        }
        switch (send_shape) {
            .http_resource_result => {},
            else => return null,
        }
        if (!is_http_send_descriptor(send_descriptor)) return error.InvalidP3AsyncManifest;
        const request_host_name = find_http_request_new_body_host(tokens) orelse return null;
        const send_host_name = find_http_send_host(tokens) orelse return null;
        const function = find_http_request_body_function(tokens) orelse return null;
        if (!has_http_resource_graph(tokens)) return null;
        const prefix = component_async_plan.analyze_stream_u8_acquire_prefix(tokens, function.body_start, function.body_end, registry) catch return null;
        if (!is_pinned_cli_stdin_stream_descriptor(prefix.descriptor)) return null;
        var body_next_idx = prefix.next_idx;
        var await_body_completion = false;
        if (parse_http_request_body_completion_await(tokens, body_next_idx, function.body_end, prefix.completion_name)) |next_idx| {
            body_next_idx = next_idx;
            await_body_completion = true;
        }
        const request_binding = parse_http_request_body_constructor(tokens, body_next_idx, function.body_end, request_host_name, prefix.reader_name) orelse return null;
        const send_binding = parse_http_request_body_send(tokens, request_binding.next_idx, function.body_end, send_host_name, request_binding.request_name, prefix.completion_name) orelse return null;
        if (send_binding.next_idx != function.body_end) return null;
        return .{
            .request_descriptor = request_descriptor,
            .send_descriptor = send_descriptor,
            .body_descriptor = prefix.descriptor,
            .request_host_name = request_host_name,
            .send_host_name = send_host_name,
            .body_host_name = prefix.host_name,
            .body_handles_name = prefix.handles_name,
            .body_reader_name = prefix.reader_name,
            .body_completion_name = prefix.completion_name,
            .await_body_completion = await_body_completion,
            .request_handles_name = request_binding.handles_name,
            .request_name = request_binding.request_name,
            .transmission_future_name = send_binding.future_name,
        };
    }
};

pub const HttpRequestBodyProducerPlan = struct {
    request_descriptor: p3_async_manifest.Descriptor,
    send_descriptor: p3_async_manifest.Descriptor,
    stream_descriptor: p3_async_manifest.Descriptor,
    request_host_name: []const u8,
    send_host_name: []const u8,
    stream_reader_name: []const u8,
    stream_writer_name: []const u8,
    write_future_name: []const u8,
    write_values: [component_async_plan.max_guest_producer_writes]u8,
    write_count: usize,
    request_handles_name: []const u8,
    request_name: []const u8,
    transmission_future_name: []const u8,

    pub fn analyze(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) !?HttpRequestBodyProducerPlan {
        try p3_http_wit_manifest.validate_resource_graph();
        const request_descriptor = registry.find(http_types_locator, "request.new") orelse return error.InvalidP3AsyncManifest;
        const send_descriptor = registry.find(http_locator, "send") orelse return error.InvalidP3AsyncManifest;
        const stream_descriptor = registry.find(cli_stdout_locator, cli_stdout_write_member) orelse return error.InvalidP3AsyncManifest;
        switch (p3_async_manifest.lowering_shape(request_descriptor) orelse return null) {
            .http_request_constructor => {},
            else => return null,
        }
        switch (p3_async_manifest.lowering_shape(send_descriptor) orelse return null) {
            .http_resource_result => {},
            else => return null,
        }
        switch (p3_async_manifest.lowering_shape(stream_descriptor) orelse return null) {
            .stream_writer => {},
            else => return null,
        }
        if (!is_pinned_cli_stdout_stream_descriptor(stream_descriptor)) return null;
        if (!is_http_send_descriptor(send_descriptor)) return error.InvalidP3AsyncManifest;
        const request_host_name = find_http_request_new_body_host(tokens) orelse return null;
        const send_host_name = find_http_send_host(tokens) orelse return null;
        const function = find_http_request_body_function(tokens) orelse return null;
        if (!has_http_resource_graph(tokens)) return null;
        const producer_stream = component_async_plan.analyze_guest_stream_prefix(tokens, function.body_start, function.body_end) orelse return null;
        if (producer_stream.capacity != 1 or producer_stream.next_idx > function.body_end) return null;
        const request_binding = parse_http_request_body_constructor(
            tokens,
            producer_stream.next_idx,
            function.body_end,
            request_host_name,
            producer_stream.reader_name,
        ) orelse return null;
        const send_binding = parse_http_request_body_send_start(
            tokens,
            request_binding.next_idx,
            function.body_end,
            send_host_name,
            request_binding.request_name,
        ) orelse return null;
        const writes = component_async_plan.analyze_guest_producer_writes(
            tokens,
            send_binding.next_idx,
            function.body_end,
            producer_stream.writer_name,
        ) orelse return null;
        if (!parse_http_request_body_terminal_await(tokens, writes.next_idx, function.body_end, send_binding.future_name)) return null;
        return .{
            .request_descriptor = request_descriptor,
            .send_descriptor = send_descriptor,
            .stream_descriptor = stream_descriptor,
            .request_host_name = request_host_name,
            .send_host_name = send_host_name,
            .stream_reader_name = producer_stream.reader_name,
            .stream_writer_name = producer_stream.writer_name,
            .write_future_name = writes.write_future_name,
            .write_values = writes.values,
            .write_count = writes.write_count,
            .request_handles_name = request_binding.handles_name,
            .request_name = request_binding.request_name,
            .transmission_future_name = send_binding.future_name,
        };
    }
};

fn is_pinned_cli_stdin_stream_descriptor(descriptor: p3_async_manifest.Descriptor) bool {
    if (!std.mem.eql(u8, descriptor.locator, cli_stdin_locator) or
        !std.mem.eql(u8, descriptor.member, cli_stdin_read_member) or
        !std.mem.eql(u8, descriptor.effect, "stream-reader") or
        descriptor.params.len != 0 or descriptor.resource != null or
        !std.mem.eql(u8, descriptor.result, "tuple<stream<u8>,future<result<_,error-code>>>") or
        !std.mem.eql(u8, descriptor.wit_sha256 orelse return false, cli_stdin_wit_sha256) or
        !std.mem.eql(u8, descriptor.canonical.completion, "result-area") or
        !std.mem.eql(u8, descriptor.canonical.async_import_module, cli_stdin_locator) or
        !std.mem.eql(u8, descriptor.canonical.async_import_name, cli_stdin_read_member) or
        !std.mem.eql(u8, descriptor.wit.package, "wasi:cli@0.3.0-rc-2025-09-16") or
        !std.mem.eql(u8, descriptor.wit.interface, "stdin") or
        !std.mem.eql(u8, descriptor.wit.operation, cli_stdin_read_member) or
        !std.mem.eql(u8, descriptor.wit.world, "stream-stdin-probe") or
        descriptor.wit.parameter.len != 0) return false;

    const shape = switch (p3_async_manifest.lowering_shape(descriptor) orelse return false) {
        .stream_reader_acquire => |value| value,
        else => return false,
    };
    return std.mem.eql(u8, shape.element, "u8") and
        std.mem.eql(u8, shape.read.import_name, "[async-lower][stream-read-0]read-via-stream") and
        std.mem.eql(u8, shape.drop_readable.import_name, "[stream-drop-readable-0]read-via-stream") and
        std.mem.eql(u8, shape.future_drop_readable.import_name, "[future-drop-readable-1]read-via-stream");
}

fn is_pinned_cli_stdout_stream_descriptor(descriptor: p3_async_manifest.Descriptor) bool {
    if (!std.mem.eql(u8, descriptor.locator, cli_stdout_locator) or
        !std.mem.eql(u8, descriptor.member, cli_stdout_write_member) or
        !std.mem.eql(u8, descriptor.effect, "stream-writer") or
        descriptor.params.len != 1 or
        !std.mem.eql(u8, descriptor.params[0], "stream<u8>") or
        !std.mem.eql(u8, descriptor.result, "Result<nil,error-code>") or
        descriptor.resource != null or
        !std.mem.eql(u8, descriptor.wit_sha256 orelse return false, cli_stdout_wit_sha256) or
        !std.mem.eql(u8, descriptor.canonical.completion, "task-return") or
        !std.mem.eql(u8, descriptor.canonical.async_import_module, cli_stdout_locator) or
        !std.mem.eql(u8, descriptor.canonical.async_import_name, "[async-lower]write-via-stream") or
        !std.mem.eql(u8, descriptor.wit.package, "wasi:cli@0.3.0-rc-2025-09-16") or
        !std.mem.eql(u8, descriptor.wit.interface, "stdout") or
        !std.mem.eql(u8, descriptor.wit.operation, cli_stdout_write_member) or
        !std.mem.eql(u8, descriptor.wit.world, "stream-stdout-probe") or
        !std.mem.eql(u8, descriptor.wit.parameter, "data")) return false;

    const shape = switch (p3_async_manifest.lowering_shape(descriptor) orelse return false) {
        .stream_writer => |value| value,
        else => return false,
    };
    return std.mem.eql(u8, shape.element, "u8") and
        std.mem.eql(u8, shape.new.import_name, "[stream-new-0]write-via-stream") and
        std.mem.eql(u8, shape.write.import_name, "[async-lower][stream-write-0]write-via-stream") and
        std.mem.eql(u8, shape.drop_readable.import_name, "[stream-drop-readable-0]write-via-stream") and
        std.mem.eql(u8, shape.drop_writable.import_name, "[stream-drop-writable-0]write-via-stream");
}

pub const HttpResponseStatusPlan = struct {
    get_status_alias: []const u8,
    drop_alias: []const u8,
    response_param: []const u8,

    pub fn analyze(tokens: []const lexer.Token) !?HttpResponseStatusPlan {
        if (!has_resource_shell(tokens, "HttpResponse", p3_http_wit_manifest.HttpResourceGraph.response_path)) return null;
        const get_status_alias = find_http_resource_host(tokens, "response.get-status-code", "HttpResponse", "u16") orelse return null;
        const drop_alias = find_http_resource_host(tokens, "response.drop", "HttpResponse", "nil") orelse return null;
        const response_param = find_status_run(tokens, get_status_alias, drop_alias) orelse return null;
        return .{
            .get_status_alias = get_status_alias,
            .drop_alias = drop_alias,
            .response_param = response_param,
        };
    }
};

pub fn has_http_service_plan(allocator: std.mem.Allocator, tokens: []const lexer.Token) !bool {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    return (try HttpServicePlan.analyze(tokens, registry)) != null;
}

pub fn has_http_service_cancellation_plan(allocator: std.mem.Allocator, tokens: []const lexer.Token) !bool {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    const plan = try HttpServicePlan.analyze(tokens, registry) orelse return false;
    return plan.terminal == .cancel;
}

pub fn has_http_request_send_plan(allocator: std.mem.Allocator, tokens: []const lexer.Token) !bool {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    return (try HttpRequestSendPlan.analyze(tokens, registry)) != null;
}

pub fn has_http_client_send_plan(allocator: std.mem.Allocator, tokens: []const lexer.Token) !bool {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    return (try HttpClientSendPlan.analyze(tokens, registry)) != null;
}

pub fn has_http_response_body_plan(allocator: std.mem.Allocator, tokens: []const lexer.Token) !bool {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    return (try HttpResponseBodyPlan.analyze(tokens, registry)) != null;
}

pub fn has_http_request_constructor_plan(allocator: std.mem.Allocator, tokens: []const lexer.Token) !bool {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    return (try HttpRequestConstructorPlan.analyze(tokens, registry)) != null;
}

pub fn has_http_request_body_plan(allocator: std.mem.Allocator, tokens: []const lexer.Token) !bool {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    return (try HttpRequestBodyPlan.analyze(tokens, registry)) != null;
}

pub fn has_http_request_body_producer_plan(allocator: std.mem.Allocator, tokens: []const lexer.Token) !bool {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    return (try HttpRequestBodyProducerPlan.analyze(tokens, registry)) != null;
}

pub fn has_http_response_status_plan(tokens: []const lexer.Token) !bool {
    return (try HttpResponseStatusPlan.analyze(tokens)) != null;
}

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
    if (try HttpRequestBodyProducerPlan.analyze(tokens, registry)) |plan| {
        return emit_http_request_body_producer_wat(allocator, plan);
    }
    if (try HttpRequestBodyPlan.analyze(tokens, registry)) |plan| {
        return emit_http_request_body_wat(allocator, plan);
    }
    if (try HttpRequestSendPlan.analyze(tokens, registry)) |plan| {
        return emit_http_request_send_wat(allocator, plan);
    }
    if (try HttpRequestConstructorPlan.analyze(tokens, registry)) |plan| {
        return emit_http_request_constructor_wat(allocator, plan);
    }
    if (try HttpResponseBodyPlan.analyze(tokens, registry)) |plan| {
        if (plan.read_count != 0) return emit_http_response_body_read_wat(allocator, plan);
        return emit_http_response_body_wat(allocator, plan);
    }
    if (try HttpServicePlan.analyze(tokens, registry)) |plan| {
        if (plan.terminal == .cancel) return emit_http_cancellation_wat(allocator, plan.descriptor);
        return emit_http_core_wat(allocator, plan.descriptor, "wasi:http/handler@0.3.0-rc-2025-09-16", "handle");
    }
    if (try HttpClientSendPlan.analyze(tokens, registry)) |plan| {
        return emit_http_core_wat(allocator, plan.descriptor, "wasi:http/probe@0.3.0-rc-2025-09-16", "run");
    }
    return error.UnsupportedP3AsyncHttpService;
}

pub fn emit_component_wit(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]u8 {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    if ((try HttpRequestBodyProducerPlan.analyze(tokens, registry)) != null) {
        return allocator.dupe(u8, http_request_body_producer_component_wit);
    }
    if ((try HttpRequestBodyPlan.analyze(tokens, registry)) != null) {
        return allocator.dupe(u8, http_request_body_probe_component_wit);
    }
    if ((try HttpRequestSendPlan.analyze(tokens, registry)) != null) {
        return allocator.dupe(u8, http_request_send_probe_component_wit);
    }
    if ((try HttpRequestConstructorPlan.analyze(tokens, registry)) != null) {
        return allocator.dupe(u8, http_request_empty_probe_component_wit);
    }
    if ((try HttpResponseBodyPlan.analyze(tokens, registry)) != null) {
        return allocator.dupe(u8, http_response_body_probe_component_wit);
    }
    if (try HttpServicePlan.analyze(tokens, registry)) |plan| {
        if (plan.terminal == .cancel) return allocator.dupe(u8, http_payload_cancel_component_wit);
        return allocator.dupe(u8, http_service_component_wit);
    }
    if ((try HttpClientSendPlan.analyze(tokens, registry)) != null) {
        return allocator.dupe(u8, http_client_probe_component_wit);
    }
    return error.UnsupportedP3AsyncHttpService;
}

pub fn emit_response_status_core_wat(allocator: std.mem.Allocator) ![]u8 {
    const operation = p3_http_wit_manifest.HttpResourceGraph.response_get_status_code;
    const wat = try std.fmt.allocPrint(
        allocator,
        http_response_status_core_wat,
        .{ operation.canonical_module, operation.canonical_name },
    );
    errdefer allocator.free(wat);
    return replace_and_free(allocator, wat, "[cabi-budget-runtime]", http_cabi_budget_runtime);
}

pub fn emit_response_status_component_wit(allocator: std.mem.Allocator) ![]u8 {
    return allocator.dupe(u8, http_response_status_component_wit);
}

const Handler = struct {
    parameter_name: []const u8,
    body_start: usize,
    body_end: usize,
};

const ResponseBodyHandler = struct {
    response_param: []const u8,
};

const ResponseBodyReadHandler = struct {
    response_param: []const u8,
    read_count: usize,
    await_completion: bool,
};

const Future = struct {
    name: []const u8,
};

const FunctionHeader = struct {
    name_idx: usize,
    open_params: usize,
    close_params: usize,
    return_start: usize,
    body_open: usize,
};

/// Descriptor scanners consume already-validated source. Keep the legacy
/// prefix only for direct unit fixtures; normal source admission rejects it
/// before code generation. New source is always the ordinary declaration.
fn find_function_header(tokens: []const lexer.Token, idx: usize, expected_name: []const u8) ?FunctionHeader {
    if (idx >= tokens.len) return null;
    const legacy = tok_eq(tokens[idx], "async");
    const name_idx = if (legacy) idx + 1 else idx;
    if (name_idx + 1 >= tokens.len or tokens[name_idx].kind != .ident or
        !std.mem.eql(u8, tokens[name_idx].lexeme, expected_name) or
        !tok_eq(tokens[name_idx + 1], "(")) return null;
    if (legacy) {
        if (idx > 0 and tokens[idx - 1].line == tokens[idx].line) return null;
    } else if (!sema_tokens.is_top_level_decl_head(tokens, name_idx)) {
        return null;
    } else if (name_idx > 0 and tokens[name_idx - 1].line == tokens[name_idx].line and
        tok_eq(tokens[name_idx - 1], "async")) {
        return null;
    }
    const open_params = name_idx + 1;
    const close_params = find_matching(tokens, open_params, "(", ")") orelse return null;
    if (close_params + 2 >= tokens.len or !tok_eq(tokens[close_params + 1], "-") or
        !tok_eq(tokens[close_params + 2], ">")) return null;
    const body_open = find_next(tokens, close_params + 3, "{") orelse return null;
    return .{
        .name_idx = name_idx,
        .open_params = open_params,
        .close_params = close_params,
        .return_start = close_params + 3,
        .body_open = body_open,
    };
}

fn is_http_send_descriptor(descriptor: p3_async_manifest.Descriptor) bool {
    const shape = p3_async_manifest.lowering_shape(descriptor) orelse return false;
    const http_shape = switch (shape) {
        .http_resource_result => |value| value,
        else => return false,
    };
    return std.mem.eql(u8, descriptor.locator, http_locator) and
        std.mem.eql(u8, descriptor.member, "send") and
        std.mem.eql(u8, http_shape.source_param, "HttpRequest") and
        std.mem.eql(u8, http_shape.request_resource, "request") and
        std.mem.eql(u8, http_shape.response_resource, "response") and
        http_shape.completion_words == 8 and
        std.mem.eql(u8, descriptor.canonical.async_import_module, http_locator) and
        std.mem.eql(u8, descriptor.canonical.async_import_name, "[async-lower]send") and
        std.mem.eql(u8, descriptor.wit.package, http_package) and
        std.mem.eql(u8, descriptor.wit.interface, "client") and
        std.mem.eql(u8, descriptor.wit.operation, "send") and
        std.mem.eql(u8, descriptor.wit.world, "service") and
        std.mem.eql(u8, descriptor.wit.parameter, "request");
}

fn find_http_send_host(tokens: []const lexer.Token) ?[]const u8 {
    var found: ?[]const u8 = null;
    var idx: usize = 0;
    while (idx + 8 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or !tok_eq(tokens[idx + 2], "@") or !tok_eq(tokens[idx + 3], "host_func") or !tok_eq(tokens[idx + 4], "(")) continue;
        const locator = string_token_body(tokens[idx + 5]) orelse continue;
        const member = string_token_body(tokens[idx + 7]) orelse continue;
        if (!tok_eq(tokens[idx + 6], ",") or !tok_eq(tokens[idx + 8], ",") or !std.mem.eql(u8, locator, http_locator) or !std.mem.eql(u8, member, "send")) continue;
        if (found != null) return null;
        found = tokens[idx].lexeme;
    }
    return found;
}

fn find_http_resource_host(
    tokens: []const lexer.Token,
    member: []const u8,
    parameter_type: []const u8,
    result_type: []const u8,
) ?[]const u8 {
    var idx: usize = 0;
    while (idx + 9 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or
            !tok_eq(tokens[idx + 2], "@") or !tok_eq(tokens[idx + 3], "host") or
            !tok_eq(tokens[idx + 4], "(") or tokens[idx + 5].kind != .string or
            !tok_eq(tokens[idx + 6], ",") or tokens[idx + 7].kind != .string or
            !tok_eq(tokens[idx + 8], ",")) continue;
        const locator = string_token_body(tokens[idx + 5]) orelse continue;
        const found_member = string_token_body(tokens[idx + 7]) orelse continue;
        if (!std.mem.eql(u8, locator, "wasi:http/types@0.3.0-rc-2025-09-16") or !std.mem.eql(u8, found_member, member)) continue;

        const signature_start = idx + 9;
        const signature_close = find_matching(tokens, signature_start, "(", ")") orelse continue;
        const declaration_close = find_matching(tokens, idx + 4, "(", ")") orelse continue;
        if (signature_close + 2 >= declaration_close or !tok_eq(tokens[signature_close + 1], "-") or !tok_eq(tokens[signature_close + 2], ">")) continue;
        if (!type_tokens_equal(tokens, signature_start + 1, signature_close, parameter_type) or
            !type_tokens_equal(tokens, signature_close + 3, declaration_close, result_type)) continue;
        return tokens[idx].lexeme;
    }
    return null;
}

fn find_http_request_new_host(tokens: []const lexer.Token) ?[]const u8 {
    var idx: usize = 0;
    while (idx + 9 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or
            !tok_eq(tokens[idx + 2], "@") or !tok_eq(tokens[idx + 3], "host") or
            !tok_eq(tokens[idx + 4], "(") or tokens[idx + 5].kind != .string or
            !tok_eq(tokens[idx + 6], ",") or tokens[idx + 7].kind != .string or
            !tok_eq(tokens[idx + 8], ",")) continue;
        const locator = string_token_body(tokens[idx + 5]) orelse continue;
        const member = string_token_body(tokens[idx + 7]) orelse continue;
        if (!std.mem.eql(u8, locator, http_types_locator) or !std.mem.eql(u8, member, "request.new")) continue;
        const signature_start = idx + 9;
        const signature_close = find_matching(tokens, signature_start, "(", ")") orelse continue;
        const declaration_close = find_matching(tokens, idx + 4, "(", ")") orelse continue;
        if (signature_close != signature_start + 1 or signature_close + 2 >= declaration_close or
            !tok_eq(tokens[signature_close + 1], "-") or !tok_eq(tokens[signature_close + 2], ">")) continue;
        if (!type_tokens_equal(tokens, signature_close + 3, declaration_close, "Tuple<HttpRequest,Future<Result<nil,HttpError>>>")) continue;
        return tokens[idx].lexeme;
    }
    return null;
}

fn find_http_request_new_body_host(tokens: []const lexer.Token) ?[]const u8 {
    var found: ?[]const u8 = null;
    var idx: usize = 0;
    while (idx + 9 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or
            !tok_eq(tokens[idx + 2], "@") or !tok_eq(tokens[idx + 3], "host") or
            !tok_eq(tokens[idx + 4], "(") or tokens[idx + 5].kind != .string or
            !tok_eq(tokens[idx + 6], ",") or tokens[idx + 7].kind != .string or
            !tok_eq(tokens[idx + 8], ",")) continue;
        const locator = string_token_body(tokens[idx + 5]) orelse continue;
        const member = string_token_body(tokens[idx + 7]) orelse continue;
        if (!std.mem.eql(u8, locator, http_types_locator) or !std.mem.eql(u8, member, "request.new")) continue;
        const signature_start = idx + 9;
        const signature_close = find_matching(tokens, signature_start, "(", ")") orelse continue;
        const declaration_close = find_matching(tokens, idx + 4, "(", ")") orelse continue;
        if (signature_close + 2 >= declaration_close or !tok_eq(tokens[signature_close + 1], "-") or
            !tok_eq(tokens[signature_close + 2], ">")) continue;
        if (!type_tokens_equal(tokens, signature_start + 1, signature_close, "Stream<u8>") or
            !type_tokens_equal(tokens, signature_close + 3, declaration_close, "Tuple<HttpRequest,Future<Result<nil,HttpError>>>")) continue;
        if (found != null) return null;
        found = tokens[idx].lexeme;
    }
    return found;
}

const HttpRequestBodyFunction = struct {
    body_start: usize,
    body_end: usize,
};

const HttpRequestBodyBinding = struct {
    handles_name: []const u8,
    request_name: []const u8,
    next_idx: usize,
};

const HttpRequestBodySend = struct {
    future_name: []const u8,
    next_idx: usize,
};

fn find_http_request_body_function(tokens: []const lexer.Token) ?HttpRequestBodyFunction {
    var found: ?HttpRequestBodyFunction = null;
    var idx: usize = 0;
    while (idx < tokens.len) : (idx += 1) {
        const header = find_function_header(tokens, idx, "run") orelse continue;
        if (header.close_params != header.open_params + 1) continue;
        if (!type_tokens_equal(tokens, header.return_start, header.body_open, "Result<HttpResponse,HttpError>")) continue;
        const body_end = find_matching(tokens, header.body_open, "{", "}") orelse continue;
        if (found != null) return null;
        found = .{ .body_start = header.body_open + 1, .body_end = body_end };
    }
    return found;
}

fn parse_http_request_body_constructor(
    tokens: []const lexer.Token,
    idx: usize,
    end_idx: usize,
    host_name: []const u8,
    reader_name: []const u8,
) ?HttpRequestBodyBinding {
    if (idx + 5 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Tuple") or !tok_eq(tokens[idx + 2], "<")) return null;
    const tuple_close = find_matching(tokens, idx + 2, "<", ">") orelse return null;
    if (!type_tokens_equal(tokens, idx + 1, tuple_close + 1, "Tuple<HttpRequest,Future<Result<nil,HttpError>>>") or
        !tok_eq(tokens[tuple_close + 1], "=") or !std.mem.eql(u8, tokens[tuple_close + 2].lexeme, host_name) or
        !tok_eq(tokens[tuple_close + 3], "(") or !std.mem.eql(u8, tokens[tuple_close + 4].lexeme, reader_name) or
        !tok_eq(tokens[tuple_close + 5], ")")) return null;
    const handles_name = tokens[idx].lexeme;
    var pos = tuple_close + 6;
    if (pos + 9 >= end_idx or tokens[pos].kind != .ident or !tok_eq(tokens[pos + 1], "HttpRequest") or
        !tok_eq(tokens[pos + 2], "=") or !tok_eq(tokens[pos + 3], "@") or !tok_eq(tokens[pos + 4], "get") or
        !tok_eq(tokens[pos + 5], "(") or !std.mem.eql(u8, tokens[pos + 6].lexeme, handles_name) or
        !tok_eq(tokens[pos + 7], ",") or !tok_eq(tokens[pos + 8], "0") or !tok_eq(tokens[pos + 9], ")")) return null;
    const request_name = tokens[pos].lexeme;
    pos += 10;
    return .{ .handles_name = handles_name, .request_name = request_name, .next_idx = pos };
}

fn parse_http_request_body_send(
    tokens: []const lexer.Token,
    idx: usize,
    end_idx: usize,
    host_name: []const u8,
    request_name: []const u8,
    completion_name: []const u8,
) ?HttpRequestBodySend {
    if (idx + 8 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Future") or !tok_eq(tokens[idx + 2], "<")) return null;
    const future_close = find_matching(tokens, idx + 2, "<", ">") orelse return null;
    if (!type_tokens_equal(tokens, idx + 1, future_close + 1, "Future<Result<HttpResponse,HttpError>>") or
        !tok_eq(tokens[future_close + 1], "=") or !std.mem.eql(u8, tokens[future_close + 2].lexeme, host_name) or
        !tok_eq(tokens[future_close + 3], "(") or !std.mem.eql(u8, tokens[future_close + 4].lexeme, request_name) or
        !tok_eq(tokens[future_close + 5], ")")) return null;
    const future_name = tokens[idx].lexeme;
    var pos = future_close + 6;
    if (pos + 5 >= end_idx or tokens[pos].kind != .ident or !tok_eq(tokens[pos + 1], "Result") or !tok_eq(tokens[pos + 2], "<")) return null;
    const result_close = find_matching(tokens, pos + 2, "<", ">") orelse return null;
    if (!type_tokens_equal(tokens, pos + 1, result_close + 1, "Result<HttpResponse,HttpError>") or
        !tok_eq(tokens[result_close + 1], "=")) return null;
    const await_end = parse_await_call(tokens, result_close + 2, end_idx, future_name) orelse return null;
    const result_name = tokens[pos].lexeme;
    pos = await_end;
    if (pos + 2 == end_idx and tok_eq(tokens[pos], "return") and std.mem.eql(u8, tokens[pos + 1].lexeme, result_name)) {
        return .{ .future_name = future_name, .next_idx = pos + 2 };
    }
    if (pos + 4 >= end_idx or !tok_eq(tokens[pos], "@") or !tok_eq(tokens[pos + 1], "cancel") or
        !tok_eq(tokens[pos + 2], "(") or tokens[pos + 3].kind != .ident or
        !std.mem.eql(u8, tokens[pos + 3].lexeme, completion_name) or !tok_eq(tokens[pos + 4], ")")) return null;
    pos += 5;
    if (pos + 2 != end_idx or !tok_eq(tokens[pos], "return") or !std.mem.eql(u8, tokens[pos + 1].lexeme, result_name)) return null;
    return .{ .future_name = future_name, .next_idx = pos + 2 };
}

fn parse_http_request_body_send_start(
    tokens: []const lexer.Token,
    idx: usize,
    end_idx: usize,
    host_name: []const u8,
    request_name: []const u8,
) ?HttpRequestBodySend {
    if (idx + 8 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Future") or !tok_eq(tokens[idx + 2], "<")) return null;
    const future_close = find_matching(tokens, idx + 2, "<", ">") orelse return null;
    if (!type_tokens_equal(tokens, idx + 1, future_close + 1, "Future<Result<HttpResponse,HttpError>>") or
        !tok_eq(tokens[future_close + 1], "=") or !std.mem.eql(u8, tokens[future_close + 2].lexeme, host_name) or
        !tok_eq(tokens[future_close + 3], "(") or !std.mem.eql(u8, tokens[future_close + 4].lexeme, request_name) or
        !tok_eq(tokens[future_close + 5], ")")) return null;
    return .{ .future_name = tokens[idx].lexeme, .next_idx = future_close + 6 };
}

fn parse_http_request_body_terminal_await(
    tokens: []const lexer.Token,
    idx: usize,
    end_idx: usize,
    future_name: []const u8,
) bool {
    if (idx + 8 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Result") or !tok_eq(tokens[idx + 2], "<")) return false;
    const result_close = find_matching(tokens, idx + 2, "<", ">") orelse return false;
    if (!type_tokens_equal(tokens, idx + 1, result_close + 1, "Result<HttpResponse,HttpError>") or
        !tok_eq(tokens[result_close + 1], "=")) return false;
    const await_end = parse_await_call(tokens, result_close + 2, end_idx, future_name) orelse return false;
    const result_name = tokens[idx].lexeme;
    return await_end + 2 == end_idx and tok_eq(tokens[await_end], "return") and
        std.mem.eql(u8, tokens[await_end + 1].lexeme, result_name);
}

fn parse_http_request_body_completion_await(
    tokens: []const lexer.Token,
    idx: usize,
    end_idx: usize,
    completion_name: []const u8,
) ?usize {
    if (idx + 10 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Result") or
        !tok_eq(tokens[idx + 2], "<") or !tok_eq(tokens[idx + 3], "nil") or !tok_eq(tokens[idx + 4], ",") or
        tokens[idx + 5].kind != .ident or !std.mem.endsWith(u8, tokens[idx + 5].lexeme, "Error")) return null;
    const result_close = find_matching(tokens, idx + 2, "<", ">") orelse return null;
    if (result_close != idx + 6 or !tok_eq(tokens[result_close + 1], "=")) return null;
    return parse_await_call(tokens, result_close + 2, end_idx, completion_name);
}

fn has_http_request_new_handler(tokens: []const lexer.Token, host_name: []const u8) bool {
    var idx: usize = 0;
    while (idx < tokens.len) : (idx += 1) {
        const header = find_function_header(tokens, idx, "run") orelse continue;
        if (header.close_params != header.open_params + 1 or
            !type_tokens_equal(tokens, header.return_start, header.body_open, "nil")) continue;
        const body_end = find_matching(tokens, header.body_open, "{", "}") orelse continue;
        var pos = header.body_open + 1;
        if (pos + 4 >= body_end or tokens[pos].kind != .ident) continue;
        const tuple_start = pos + 1;
        const tuple_close = find_matching(tokens, tuple_start + 1, "<", ">") orelse continue;
        if (!type_tokens_equal(tokens, tuple_start, tuple_close + 1, "Tuple<HttpRequest,Future<Result<nil,HttpError>>>") or
            !tok_eq(tokens[tuple_close + 1], "=") or !std.mem.eql(u8, tokens[tuple_close + 2].lexeme, host_name) or
            !tok_eq(tokens[tuple_close + 3], "(") or !tok_eq(tokens[tuple_close + 4], ")")) continue;
        pos = tuple_close + 5;
        if (pos + 3 != body_end or !tok_eq(tokens[pos], "_") or !tok_eq(tokens[pos + 1], "=") or
            !std.mem.eql(u8, tokens[pos + 2].lexeme, tokens[header.body_open + 1].lexeme)) continue;
        return true;
    }
    return false;
}

fn has_http_request_send_handler(tokens: []const lexer.Token, request_host_name: []const u8, send_host_name: []const u8) bool {
    var idx: usize = 0;
    while (idx < tokens.len) : (idx += 1) {
        const header = find_function_header(tokens, idx, "run") orelse continue;
        if (header.close_params != header.open_params + 1 or
            !type_tokens_equal(tokens, header.return_start, header.body_open, "Result<HttpResponse,HttpError>")) continue;
        const body_end = find_matching(tokens, header.body_open, "{", "}") orelse continue;
        var pos = header.body_open + 1;
        if (pos + 5 >= body_end or tokens[pos].kind != .ident or !tok_eq(tokens[pos + 1], "Tuple") or
            !tok_eq(tokens[pos + 2], "<")) continue;
        const handles_name = tokens[pos].lexeme;
        const tuple_close = find_matching(tokens, pos + 2, "<", ">") orelse continue;
        if (!type_tokens_equal(tokens, pos + 1, tuple_close + 1, "Tuple<HttpRequest,Future<Result<nil,HttpError>>>") or
            !tok_eq(tokens[tuple_close + 1], "=") or !std.mem.eql(u8, tokens[tuple_close + 2].lexeme, request_host_name) or
            !tok_eq(tokens[tuple_close + 3], "(") or !tok_eq(tokens[tuple_close + 4], ")")) continue;
        pos = tuple_close + 5;

        if (pos + 9 >= body_end or tokens[pos].kind != .ident or !tok_eq(tokens[pos + 1], "HttpRequest") or
            !tok_eq(tokens[pos + 2], "=") or !tok_eq(tokens[pos + 3], "@") or !tok_eq(tokens[pos + 4], "get") or
            !tok_eq(tokens[pos + 5], "(") or !std.mem.eql(u8, tokens[pos + 6].lexeme, handles_name) or
            !tok_eq(tokens[pos + 7], ",") or !tok_eq(tokens[pos + 8], "0") or !tok_eq(tokens[pos + 9], ")")) continue;
        const request_name = tokens[pos].lexeme;
        pos += 10;

        if (pos + 8 >= body_end or tokens[pos].kind != .ident or !tok_eq(tokens[pos + 1], "Future") or
            !tok_eq(tokens[pos + 2], "<")) continue;
        const future_close = find_matching(tokens, pos + 2, "<", ">") orelse continue;
        if (!type_tokens_equal(tokens, pos + 1, future_close + 1, "Future<Result<HttpResponse,HttpError>>") or
            !tok_eq(tokens[future_close + 1], "=") or !std.mem.eql(u8, tokens[future_close + 2].lexeme, send_host_name) or
            !tok_eq(tokens[future_close + 3], "(") or !std.mem.eql(u8, tokens[future_close + 4].lexeme, request_name) or
            !tok_eq(tokens[future_close + 5], ")")) continue;
        const future_name = tokens[pos].lexeme;
        pos = future_close + 6;
        if (!tok_eq(tokens[pos], "return")) continue;
        const await_end = parse_await_call(tokens, pos + 1, body_end, future_name) orelse continue;
        if (await_end != body_end) continue;
        return true;
    }
    return false;
}

fn find_status_run(tokens: []const lexer.Token, get_status_alias: []const u8, drop_alias: []const u8) ?[]const u8 {
    var idx: usize = 0;
    while (idx + 8 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !std.mem.eql(u8, tokens[idx].lexeme, "run") or !tok_eq(tokens[idx + 1], "(")) continue;
        const params_close = find_matching(tokens, idx + 1, "(", ")") orelse continue;
        if (params_close != idx + 4 or tokens[idx + 3].kind != .ident or !tok_eq(tokens[idx + 4], ")")) continue;
        const response_param = tokens[idx + 2].lexeme;
        const body_open = find_next(tokens, params_close + 1, "{") orelse continue;
        if (!type_tokens_equal(tokens, params_close + 3, body_open, "u16")) continue;
        const body_close = find_matching(tokens, body_open, "{", "}") orelse continue;
        const pos = body_open + 1;
        if (pos + 13 != body_close or tokens[pos].kind != .ident or !tok_eq(tokens[pos + 1], "u16") or
            !tok_eq(tokens[pos + 2], "=") or !std.mem.eql(u8, tokens[pos + 3].lexeme, get_status_alias) or
            !tok_eq(tokens[pos + 4], "(") or !std.mem.eql(u8, tokens[pos + 5].lexeme, response_param) or
            !tok_eq(tokens[pos + 6], ")") or !std.mem.eql(u8, tokens[pos + 7].lexeme, drop_alias) or
            !tok_eq(tokens[pos + 8], "(") or !std.mem.eql(u8, tokens[pos + 9].lexeme, response_param) or
            !tok_eq(tokens[pos + 10], ")") or !tok_eq(tokens[pos + 11], "return") or
            !std.mem.eql(u8, tokens[pos + 12].lexeme, tokens[pos].lexeme)) continue;
        return response_param;
    }
    return null;
}

fn has_resource_shell(tokens: []const lexer.Token, name: []const u8, path: []const u8) bool {
    var idx: usize = 0;
    while (idx + 6 < tokens.len) : (idx += 1) {
        if (!std.mem.eql(u8, tokens[idx].lexeme, name) or !tok_eq(tokens[idx + 1], "=") or !tok_eq(tokens[idx + 2], "@") or !tok_eq(tokens[idx + 3], "wasi_resource") or !tok_eq(tokens[idx + 4], "(")) continue;
        const resource_path = string_token_body(tokens[idx + 5]) orelse continue;
        if (std.mem.eql(u8, resource_path, path)) return true;
    }
    return false;
}

fn has_http_resource_graph(tokens: []const lexer.Token) bool {
    return has_resource_shell(tokens, "HttpHeaders", p3_http_wit_manifest.HttpResourceGraph.headers_path) and
        has_resource_shell(tokens, "HttpRequestOptions", p3_http_wit_manifest.HttpResourceGraph.request_options_path) and
        has_resource_shell(tokens, "HttpRequest", p3_http_wit_manifest.HttpResourceGraph.request_path) and
        has_resource_shell(tokens, "HttpResponse", p3_http_wit_manifest.HttpResourceGraph.response_path);
}

fn find_handler_named(tokens: []const lexer.Token, function_name: []const u8) ?Handler {
    var handler: ?Handler = null;
    var idx: usize = 0;
    while (idx < tokens.len) : (idx += 1) {
        const header = find_function_header(tokens, idx, function_name) orelse continue;
        if (handler != null or header.close_params != header.open_params + 3 or
            tokens[header.open_params + 1].kind != .ident or
            !tok_eq(tokens[header.open_params + 2], "HttpRequest") or
            !type_tokens_equal(tokens, header.return_start, header.body_open, "Result<HttpResponse,HttpError>")) return null;
        const body_end = find_matching(tokens, header.body_open, "{", "}") orelse return null;
        handler = .{ .parameter_name = tokens[header.open_params + 1].lexeme, .body_start = header.body_open + 1, .body_end = body_end };
    }
    return handler;
}

fn find_cancellation_handler(tokens: []const lexer.Token) ?Handler {
    var idx: usize = 0;
    while (idx < tokens.len) : (idx += 1) {
        const header = find_function_header(tokens, idx, "cancel_request") orelse continue;
        if (header.close_params != header.open_params + 3 or
            tokens[header.open_params + 1].kind != .ident or
            !tok_eq(tokens[header.open_params + 2], "HttpRequest") or
            !type_tokens_equal(tokens, header.return_start, header.body_open, "nil")) continue;
        const body_end = find_matching(tokens, header.body_open, "{", "}") orelse return null;
        return .{ .parameter_name = tokens[header.open_params + 1].lexeme, .body_start = header.body_open + 1, .body_end = body_end };
    }
    return null;
}

fn find_response_body_handler(tokens: []const lexer.Token, host_name: []const u8) ?ResponseBodyHandler {
    var idx: usize = 0;
    while (idx < tokens.len) : (idx += 1) {
        const header = find_function_header(tokens, idx, "run") orelse continue;
        if (header.close_params != header.open_params + 3 or
            tokens[header.open_params + 1].kind != .ident or
            !tok_eq(tokens[header.open_params + 2], "HttpResponse") or
            !type_tokens_equal(tokens, header.return_start, header.body_open, "nil")) continue;
        const body_end = find_matching(tokens, header.body_open, "{", "}") orelse return null;
        const body_start = header.body_open + 1;
        if (body_start + 6 != body_end or !tok_eq(tokens[body_start], "_") or
            !tok_eq(tokens[body_start + 1], "=") or
            !std.mem.eql(u8, tokens[body_start + 2].lexeme, host_name) or
            !tok_eq(tokens[body_start + 3], "(") or
            !std.mem.eql(u8, tokens[body_start + 4].lexeme, tokens[header.open_params + 1].lexeme) or
            !tok_eq(tokens[body_start + 5], ")")) return null;
        return .{ .response_param = tokens[header.open_params + 1].lexeme };
    }
    return null;
}

fn find_response_body_read_handler(tokens: []const lexer.Token, host_name: []const u8) ?ResponseBodyReadHandler {
    var idx: usize = 0;
    while (idx < tokens.len) : (idx += 1) {
        const header = find_function_header(tokens, idx, "run") orelse continue;
        if (header.close_params != header.open_params + 3 or
            tokens[header.open_params + 1].kind != .ident or
            !tok_eq(tokens[header.open_params + 2], "HttpResponse") or
            !type_tokens_equal(tokens, header.return_start, header.body_open, "nil")) continue;
        const body_end = find_matching(tokens, header.body_open, "{", "}") orelse return null;
        var pos = header.body_open + 1;
        if (pos + 5 >= body_end or tokens[pos].kind != .ident or !tok_eq(tokens[pos + 1], "Tuple") or !tok_eq(tokens[pos + 2], "<")) continue;
        const handles_name = tokens[pos].lexeme;
        const tuple_close = find_matching(tokens, pos + 2, "<", ">") orelse continue;
        if (!type_tokens_equal(tokens, pos + 1, tuple_close + 1, "Tuple<Stream<u8>,Future<Result<option<trailers>,HttpError>>>") or
            !tok_eq(tokens[tuple_close + 1], "=") or !std.mem.eql(u8, tokens[tuple_close + 2].lexeme, host_name) or
            !tok_eq(tokens[tuple_close + 3], "(") or !std.mem.eql(u8, tokens[tuple_close + 4].lexeme, tokens[header.open_params + 1].lexeme) or
            !tok_eq(tokens[tuple_close + 5], ")")) continue;
        pos = tuple_close + 6;

        if (pos + 8 >= body_end or tokens[pos].kind != .ident or !tok_eq(tokens[pos + 1], "Stream") or !tok_eq(tokens[pos + 2], "<")) continue;
        const stream_close = find_matching(tokens, pos + 2, "<", ">") orelse continue;
        const reader_ok = type_tokens_equal(tokens, pos + 1, stream_close + 1, "Stream<u8>") and
            tok_eq(tokens[stream_close + 1], "=") and tok_eq(tokens[stream_close + 2], "@") and
            tok_eq(tokens[stream_close + 3], "get") and tok_eq(tokens[stream_close + 4], "(") and
            std.mem.eql(u8, tokens[stream_close + 5].lexeme, handles_name) and
            tok_eq(tokens[stream_close + 6], ",") and tok_eq(tokens[stream_close + 7], "0") and
            tok_eq(tokens[stream_close + 8], ")");
        if (!reader_ok) continue;
        const reader_name = tokens[pos].lexeme;
        pos = stream_close + 9;

        if (pos + 8 >= body_end or tokens[pos].kind != .ident or !tok_eq(tokens[pos + 1], "Future") or !tok_eq(tokens[pos + 2], "<")) continue;
        const completion_close = find_matching(tokens, pos + 2, "<", ">") orelse continue;
        const completion_ok = type_tokens_equal(tokens, pos + 1, completion_close + 1, "Future<Result<option<trailers>,HttpError>>") and
            tok_eq(tokens[completion_close + 1], "=") and tok_eq(tokens[completion_close + 2], "@") and
            tok_eq(tokens[completion_close + 3], "get") and tok_eq(tokens[completion_close + 4], "(") and
            std.mem.eql(u8, tokens[completion_close + 5].lexeme, handles_name) and
            tok_eq(tokens[completion_close + 6], ",") and tok_eq(tokens[completion_close + 7], "1") and
            tok_eq(tokens[completion_close + 8], ")");
        if (!completion_ok) continue;
        const completion_name = tokens[pos].lexeme;
        pos = completion_close + 9;

        var read_count: usize = 0;
        while (read_count < component_async_plan.max_stream_u8_reads) {
            if (pos + 8 >= body_end or tokens[pos].kind != .ident or !tok_eq(tokens[pos + 1], "Future") or !tok_eq(tokens[pos + 2], "<")) break;
            const pending_close = find_matching(tokens, pos + 2, "<", ">") orelse break;
            if (!type_tokens_equal(tokens, pos + 1, pending_close + 1, "Future<Result<u8,nil>>") or
                !tok_eq(tokens[pending_close + 1], "=") or !tok_eq(tokens[pending_close + 2], "@") or
                !tok_eq(tokens[pending_close + 3], "next") or !tok_eq(tokens[pending_close + 4], "(") or
                !std.mem.eql(u8, tokens[pending_close + 5].lexeme, reader_name) or !tok_eq(tokens[pending_close + 6], ")")) break;
            const pending_name = tokens[pos].lexeme;
            pos = pending_close + 7;

            if (pos + 8 >= body_end or tokens[pos].kind != .ident or !tok_eq(tokens[pos + 1], "Result") or !tok_eq(tokens[pos + 2], "<")) break;
            const item_close = find_matching(tokens, pos + 2, "<", ">") orelse break;
            if (!type_tokens_equal(tokens, pos + 1, item_close + 1, "Result<u8,nil>") or
                !tok_eq(tokens[item_close + 1], "=")) break;
            const item_end = parse_await_call(tokens, item_close + 2, body_end, pending_name) orelse break;
            const item_name = tokens[pos].lexeme;
            pos = item_end;

            if (pos + 2 >= body_end or !tok_eq(tokens[pos], "_") or !tok_eq(tokens[pos + 1], "=") or
                !std.mem.eql(u8, tokens[pos + 2].lexeme, item_name)) break;
            pos += 3;
            read_count += 1;
        }
        if (read_count == 0) continue;

        var await_completion = false;
        if (pos + 2 < body_end and tokens[pos].kind == .ident and tok_eq(tokens[pos + 1], "Result") and tok_eq(tokens[pos + 2], "<")) {
            const trailer_result_close = find_matching(tokens, pos + 2, "<", ">") orelse continue;
            const await_ok = type_tokens_equal(tokens, pos + 1, trailer_result_close + 1, "Result<option<trailers>,HttpError>") and
                tok_eq(tokens[trailer_result_close + 1], "=");
            if (await_ok) {
                const await_end = parse_await_call(tokens, trailer_result_close + 2, body_end, completion_name) orelse continue;
                const result_name = tokens[pos].lexeme;
                const discard_pos = await_end;
                if (discard_pos + 3 == body_end and tok_eq(tokens[discard_pos], "_") and tok_eq(tokens[discard_pos + 1], "=") and
                    std.mem.eql(u8, tokens[discard_pos + 2].lexeme, result_name))
                {
                    await_completion = true;
                    pos = body_end;
                }
            }
        }

        if (!await_completion and (pos + 5 != body_end or !tok_eq(tokens[pos], "@") or !tok_eq(tokens[pos + 1], "cancel") or
            !tok_eq(tokens[pos + 2], "(") or !std.mem.eql(u8, tokens[pos + 3].lexeme, completion_name) or
            !tok_eq(tokens[pos + 4], ")"))) continue;
        return .{ .response_param = tokens[header.open_params + 1].lexeme, .read_count = read_count, .await_completion = await_completion };
    }
    return null;
}

fn parse_forwarding_body(tokens: []const lexer.Token, handler: Handler, host_name: []const u8) ?Future {
    const start = handler.body_start;
    if (start + 8 >= handler.body_end or tokens[start].kind != .ident or !tok_eq(tokens[start + 1], "Future") or !tok_eq(tokens[start + 2], "<")) return null;
    const result_end = find_matching(tokens, start + 2, "<", ">") orelse return null;
    if (!type_tokens_equal(tokens, start + 3, result_end, "Result<HttpResponse,HttpError>")) return null;
    if (result_end + 10 >= handler.body_end or !tok_eq(tokens[result_end + 1], "=") or !std.mem.eql(u8, tokens[result_end + 2].lexeme, host_name) or !tok_eq(tokens[result_end + 3], "(") or !std.mem.eql(u8, tokens[result_end + 4].lexeme, handler.parameter_name) or !tok_eq(tokens[result_end + 5], ")")) return null;
    const future_name = tokens[start].lexeme;
    const return_start = result_end + 6;
    if (is_direct_await_return(tokens, return_start, handler.body_end, future_name)) return .{ .name = future_name };
    if (!is_bound_await_return(tokens, return_start, handler.body_end, future_name)) return null;
    return .{ .name = future_name };
}

fn parse_cancellation_body(tokens: []const lexer.Token, handler: Handler, host_name: []const u8) ?Future {
    const start = handler.body_start;
    if (start + 8 >= handler.body_end or tokens[start].kind != .ident or !tok_eq(tokens[start + 1], "Future") or !tok_eq(tokens[start + 2], "<")) return null;
    const result_end = find_matching(tokens, start + 2, "<", ">") orelse return null;
    if (!type_tokens_equal(tokens, start + 3, result_end, "Result<HttpResponse,HttpError>")) return null;
    if (result_end + 10 >= handler.body_end or !tok_eq(tokens[result_end + 1], "=") or
        !std.mem.eql(u8, tokens[result_end + 2].lexeme, host_name) or !tok_eq(tokens[result_end + 3], "(") or
        !std.mem.eql(u8, tokens[result_end + 4].lexeme, handler.parameter_name) or !tok_eq(tokens[result_end + 5], ")")) return null;
    if (result_end + 11 != handler.body_end or !tok_eq(tokens[result_end + 6], "@") or
        !tok_eq(tokens[result_end + 7], "cancel") or !tok_eq(tokens[result_end + 8], "(") or
        !std.mem.eql(u8, tokens[result_end + 9].lexeme, tokens[start].lexeme) or !tok_eq(tokens[result_end + 10], ")")) return null;
    return .{ .name = tokens[start].lexeme };
}

/// Parse the canonical `@await(future)` operation while accepting the old
/// bare `await(future)` spelling in descriptor unit fixtures during migration.
/// The returned index is the first token after the closing parenthesis.
fn parse_await_call(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    future_name: []const u8,
) ?usize {
    if (start_idx >= end_idx) return null;
    var await_idx = start_idx;
    if (tok_eq(tokens[await_idx], "@")) {
        if (await_idx + 1 >= end_idx or !tok_eq(tokens[await_idx + 1], "await")) return null;
        await_idx += 2;
    } else {
        if (!tok_eq(tokens[await_idx], "await")) return null;
        await_idx += 1;
    }
    if (await_idx >= end_idx or !tok_eq(tokens[await_idx], "(")) return null;
    const close_idx = find_matching(tokens, await_idx, "(", ")") orelse return null;
    if (close_idx >= end_idx or close_idx != await_idx + 2 or
        !std.mem.eql(u8, tokens[await_idx + 1].lexeme, future_name)) return null;
    return close_idx + 1;
}

fn is_direct_await_return(tokens: []const lexer.Token, start: usize, body_end: usize, future_name: []const u8) bool {
    if (start >= body_end or !tok_eq(tokens[start], "return")) return false;
    const await_end = parse_await_call(tokens, start + 1, body_end, future_name) orelse return false;
    return await_end == body_end;
}

fn is_bound_await_return(tokens: []const lexer.Token, start: usize, body_end: usize, future_name: []const u8) bool {
    if (start + 2 >= body_end or tokens[start].kind != .ident or !tok_eq(tokens[start + 1], "Result") or !tok_eq(tokens[start + 2], "<")) return false;
    const result_end = find_matching(tokens, start + 2, "<", ">") orelse return false;
    if (!type_tokens_equal(tokens, start + 1, result_end + 1, "Result<HttpResponse,HttpError>")) return false;
    if (result_end + 1 >= body_end or !tok_eq(tokens[result_end + 1], "=")) return false;
    const await_end = parse_await_call(tokens, result_end + 2, body_end, future_name) orelse return false;
    return await_end + 2 == body_end and tok_eq(tokens[await_end], "return") and
        std.mem.eql(u8, tokens[await_end + 1].lexeme, tokens[start].lexeme);
}

fn find_next(tokens: []const lexer.Token, start: usize, text: []const u8) ?usize {
    var idx = start;
    while (idx < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], text)) return idx;
    }
    return null;
}

fn find_matching(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8) ?usize {
    var depth: usize = 0;
    var idx = open_idx;
    while (idx < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], open)) {
            depth += 1;
            continue;
        }
        if (!tok_eq(tokens[idx], close)) continue;
        depth -= 1;
        if (depth == 0) return idx;
    }
    return null;
}

fn type_tokens_equal(tokens: []const lexer.Token, start: usize, end: usize, expected: []const u8) bool {
    var expected_idx: usize = 0;
    for (tokens[start..end]) |token| {
        if (expected_idx + token.lexeme.len > expected.len or !std.mem.eql(u8, expected[expected_idx .. expected_idx + token.lexeme.len], token.lexeme)) return false;
        expected_idx += token.lexeme.len;
    }
    return expected_idx == expected.len;
}

fn string_token_body(token: lexer.Token) ?[]const u8 {
    if (token.kind != .string or token.lexeme.len < 2) return null;
    return token.lexeme[1 .. token.lexeme.len - 1];
}

fn tok_eq(token: lexer.Token, text: []const u8) bool {
    return std.mem.eql(u8, token.lexeme, text);
}

fn emit_http_service_core_wat(allocator: std.mem.Allocator, descriptor: p3_async_manifest.Descriptor) ![]u8 {
    return emit_http_core_wat(allocator, descriptor, "wasi:http/handler@0.3.0-rc-2025-09-16", "handle");
}

fn emit_http_cancellation_wat(allocator: std.mem.Allocator, descriptor: p3_async_manifest.Descriptor) ![]u8 {
    if (!is_http_send_descriptor(descriptor)) return error.UnsupportedP3AsyncHttpService;
    var wat = try allocator.dupe(u8, http_payload_cancel_core_wat);
    errdefer allocator.free(wat);
    const async_import = try std.fmt.allocPrint(
        allocator,
        "(import \"{s}\" \"{s}\"",
        .{ descriptor.canonical.async_import_module, descriptor.canonical.async_import_name },
    );
    defer allocator.free(async_import);
    wat = try replace_and_free(allocator, wat, "(import \"wasi:http/client@0.3.0-rc-2025-09-16\" \"[async-lower]send\"", async_import);
    return wat;
}

fn emit_http_response_body_wat(allocator: std.mem.Allocator, plan: HttpResponseBodyPlan) ![]u8 {
    const shape = switch (p3_async_manifest.lowering_shape(plan.descriptor) orelse return error.UnsupportedP3AsyncHttpService) {
        .http_stream_reader => |value| value,
        else => return error.UnsupportedP3AsyncHttpService,
    };
    var wat = try allocator.dupe(u8, http_response_body_core_wat);
    errdefer allocator.free(wat);
    wat = try replace_and_free(allocator, wat, "[cabi-budget-runtime]", http_cabi_budget_runtime);
    const future_new_name = try replace_http_payload_alias(allocator, shape.future_new.import_name);
    defer allocator.free(future_new_name);
    const future_write_name = try replace_http_payload_alias(allocator, shape.future_write.import_name);
    defer allocator.free(future_write_name);
    const future_drop_writable_name = try replace_http_payload_alias(allocator, shape.future_drop_writable.import_name);
    defer allocator.free(future_drop_writable_name);
    const stream_drop_name = try replace_http_payload_alias(allocator, shape.drop_readable.import_name);
    defer allocator.free(stream_drop_name);
    const future_drop_name = try replace_http_payload_alias(allocator, shape.future_drop_readable.import_name);
    defer allocator.free(future_drop_name);
    wat = try replace_and_free(allocator, wat, "[consume-body-module]", plan.descriptor.canonical.async_import_module);
    wat = try replace_and_free(allocator, wat, "[consume-body-name]", plan.descriptor.canonical.async_import_name);
    wat = try replace_and_free(allocator, wat, "[future-new-name]", future_new_name);
    wat = try replace_and_free(allocator, wat, "[future-write-name]", future_write_name);
    wat = try replace_and_free(allocator, wat, "[future-drop-writable-name]", future_drop_writable_name);
    wat = try replace_and_free(allocator, wat, "[stream-drop-name]", stream_drop_name);
    wat = try replace_and_free(allocator, wat, "[future-drop-name]", future_drop_name);
    wat = try replace_and_free(allocator, wat, "[task-return-locator]", "wasi:http/probe@0.3.0-rc-2025-09-16");
    wat = try replace_and_free(allocator, wat, "[async-lift-name]", "[async-lift]wasi:http/probe@0.3.0-rc-2025-09-16#run");
    wat = try replace_and_free(allocator, wat, "[callback-async-lift-name]", "[callback][async-lift]wasi:http/probe@0.3.0-rc-2025-09-16#run");
    return wat;
}

fn emit_http_response_body_read_wat(allocator: std.mem.Allocator, plan: HttpResponseBodyPlan) ![]u8 {
    const shape = switch (p3_async_manifest.lowering_shape(plan.descriptor) orelse return error.UnsupportedP3AsyncHttpService) {
        .http_stream_reader => |value| value,
        else => return error.UnsupportedP3AsyncHttpService,
    };
    var wat = try allocator.dupe(u8, http_response_body_read_core_wat);
    errdefer allocator.free(wat);
    wat = try replace_and_free(allocator, wat, "[cabi-budget-runtime]", http_cabi_budget_runtime);
    const read_count = try std.fmt.allocPrint(allocator, "{d}", .{plan.read_count});
    defer allocator.free(read_count);
    const future_new_name = try replace_http_payload_alias(allocator, shape.future_new.import_name);
    defer allocator.free(future_new_name);
    const future_write_name = try replace_http_payload_alias(allocator, shape.future_write.import_name);
    defer allocator.free(future_write_name);
    const future_drop_writable_name = try replace_http_payload_alias(allocator, shape.future_drop_writable.import_name);
    defer allocator.free(future_drop_writable_name);
    const stream_read_name = try replace_http_payload_alias(allocator, shape.read.import_name);
    defer allocator.free(stream_read_name);
    const stream_drop_name = try replace_http_payload_alias(allocator, shape.drop_readable.import_name);
    defer allocator.free(stream_drop_name);
    const future_drop_name = try replace_http_payload_alias(allocator, shape.future_drop_readable.import_name);
    defer allocator.free(future_drop_name);
    const future_read_name = if (plan.await_completion)
        try replace_http_payload_alias(allocator, shape.future_read.import_name)
    else
        try allocator.dupe(u8, "");
    defer allocator.free(future_read_name);
    const future_read_import = if (plan.await_completion)
        try std.fmt.allocPrint(allocator, "  (import \"{s}\" \"{s}\" (func $future-read (type $future-read)))", .{ plan.descriptor.canonical.async_import_module, future_read_name })
    else
        try allocator.dupe(u8, "");
    defer allocator.free(future_read_import);
    const trailers_functions = if (plan.await_completion)
        try allocator.dupe(u8, http_response_trailers_read_functions)
    else
        try allocator.dupe(u8, "");
    defer allocator.free(trailers_functions);
    const finish_body = if (plan.await_completion)
        "local.get $frame\n      call $start-trailers"
    else
        "local.get $frame\n      call $cleanup";
    const future_event_handler = if (plan.await_completion)
        "local.get $event\n        i32.const 4\n        i32.eq\n        if (result i32)\n          local.get $frame\n          local.get $payload\n          call $accept-trailers\n        else\n          unreachable\n        end"
    else
        "local.get $frame\n        call $cleanup";
    wat = try replace_and_free(allocator, wat, "[consume-body-module]", plan.descriptor.canonical.async_import_module);
    wat = try replace_and_free(allocator, wat, "[consume-body-name]", plan.descriptor.canonical.async_import_name);
    wat = try replace_and_free(allocator, wat, "[future-new-name]", future_new_name);
    wat = try replace_and_free(allocator, wat, "[future-write-name]", future_write_name);
    wat = try replace_and_free(allocator, wat, "[future-drop-writable-name]", future_drop_writable_name);
    wat = try replace_and_free(allocator, wat, "[stream-read-name]", stream_read_name);
    wat = try replace_and_free(allocator, wat, "[future-read-import]", future_read_import);
    wat = try replace_and_free(allocator, wat, "[trailers-read-functions]", trailers_functions);
    wat = try replace_and_free(allocator, wat, "[finish-body]", finish_body);
    wat = try replace_and_free(allocator, wat, "[future-event-handler]", future_event_handler);
    wat = try replace_and_free(allocator, wat, "[stream-read-count-value]", read_count);
    wat = try replace_and_free(allocator, wat, "[stream-drop-name]", stream_drop_name);
    wat = try replace_and_free(allocator, wat, "[future-drop-name]", future_drop_name);
    wat = try replace_and_free(allocator, wat, "[task-return-locator]", "wasi:http/probe@0.3.0-rc-2025-09-16");
    wat = try replace_and_free(allocator, wat, "[async-lift-name]", "[async-lift]wasi:http/probe@0.3.0-rc-2025-09-16#run");
    wat = try replace_and_free(allocator, wat, "[callback-async-lift-name]", "[callback][async-lift]wasi:http/probe@0.3.0-rc-2025-09-16#run");
    return wat;
}

fn emit_http_request_constructor_wat(allocator: std.mem.Allocator, plan: HttpRequestConstructorPlan) ![]u8 {
    const shape = switch (p3_async_manifest.lowering_shape(plan.descriptor) orelse return error.UnsupportedP3AsyncHttpService) {
        .http_request_constructor => |value| value,
        else => return error.UnsupportedP3AsyncHttpService,
    };
    const future_new = shape.trailers_future.new orelse return error.UnsupportedP3AsyncHttpService;
    const future_write = shape.trailers_future.write orelse return error.UnsupportedP3AsyncHttpService;
    const future_drop_writable = shape.trailers_future.drop_writable orelse return error.UnsupportedP3AsyncHttpService;
    var wat = try allocator.dupe(u8, http_request_empty_core_wat);
    errdefer allocator.free(wat);
    wat = try replace_and_free(allocator, wat, "[cabi-budget-runtime]", http_cabi_budget_runtime);
    wat = try replace_and_free(allocator, wat, "[request-new-module]", plan.descriptor.canonical.async_import_module);
    wat = try replace_and_free(allocator, wat, "[request-new-name]", plan.descriptor.canonical.async_import_name);
    wat = try replace_and_free(allocator, wat, "[fields-module]", http_types_locator);
    wat = try replace_and_free(allocator, wat, "[future-new-name]", future_new.import_name);
    wat = try replace_and_free(allocator, wat, "[future-write-name]", future_write.import_name);
    wat = try replace_and_free(allocator, wat, "[future-drop-writable-name]", future_drop_writable.import_name);
    wat = try replace_and_free(allocator, wat, "[transmission-drop-name]", shape.transmission_future.drop_readable.import_name);
    wat = try replace_and_free(allocator, wat, "[task-return-locator]", "wasi:http/probe@0.3.0-rc-2025-09-16");
    wat = try replace_and_free(allocator, wat, "[async-lift-name]", "[async-lift]wasi:http/probe@0.3.0-rc-2025-09-16#run");
    wat = try replace_and_free(allocator, wat, "[callback-async-lift-name]", "[callback][async-lift]wasi:http/probe@0.3.0-rc-2025-09-16#run");
    return wat;
}

fn emit_http_request_body_producer_wat(allocator: std.mem.Allocator, plan: HttpRequestBodyProducerPlan) ![]u8 {
    const request_shape = switch (p3_async_manifest.lowering_shape(plan.request_descriptor) orelse return error.UnsupportedP3AsyncHttpService) {
        .http_request_constructor => |value| value,
        else => return error.UnsupportedP3AsyncHttpService,
    };
    const send_descriptor = plan.send_descriptor;
    const stream_shape = switch (p3_async_manifest.lowering_shape(plan.stream_descriptor) orelse return error.UnsupportedP3AsyncHttpService) {
        .stream_writer => |value| value,
        else => return error.UnsupportedP3AsyncHttpService,
    };
    const future_new = request_shape.trailers_future.new orelse return error.UnsupportedP3AsyncHttpService;
    const future_write = request_shape.trailers_future.write orelse return error.UnsupportedP3AsyncHttpService;
    const future_drop_writable = request_shape.trailers_future.drop_writable orelse return error.UnsupportedP3AsyncHttpService;

    var slots = [_]async_model.FrameLayoutSlot{
        .{ .name = "result-ptr", .storage = .i32, .offset = 16 },
        .{ .name = "producer-reader", .storage = .i32, .offset = 20 },
        .{ .name = "producer-writer", .storage = .i32, .offset = 24 },
        .{ .name = "producer-index", .storage = .i32, .offset = 28 },
        .{ .name = "producer-subtask", .storage = .i32, .offset = 32 },
    };
    const layout = async_model.FrameLayout{ .size = 36, .slots = &slots };
    var gc_frame_runtime = std.ArrayList(u8).empty;
    defer gc_frame_runtime.deinit(allocator);
    try gc_async_frame.emit_frame_table_layout(allocator, &gc_frame_runtime, layout);
    try gc_async_frame.emit_frame_table_allocator_with_bytes(allocator, &gc_frame_runtime, layout.size);

    const task_return_params = try render_core_param_list(allocator, send_descriptor.canonical.completion_params);
    defer allocator.free(task_return_params);
    const task_return_zero_tail = try render_zero_tail(allocator, send_descriptor.canonical.completion_params);
    defer allocator.free(task_return_zero_tail);
    const producer_data = try render_producer_data(allocator, plan.write_values[0..plan.write_count]);
    defer allocator.free(producer_data);

    var producer_imports = try allocator.dupe(u8, http_request_body_producer_imports);
    defer allocator.free(producer_imports);
    producer_imports = try replace_and_free(allocator, producer_imports, "[types-module]", http_types_locator);
    producer_imports = try replace_and_free(allocator, producer_imports, "[request-new-name]", plan.request_descriptor.canonical.async_import_name);
    producer_imports = try replace_and_free(allocator, producer_imports, "[future-new-name]", future_new.import_name);
    producer_imports = try replace_and_free(allocator, producer_imports, "[future-write-name]", future_write.import_name);
    producer_imports = try replace_and_free(allocator, producer_imports, "[future-drop-writable-name]", future_drop_writable.import_name);
    producer_imports = try replace_and_free(allocator, producer_imports, "[transmission-drop-name]", request_shape.transmission_future.drop_readable.import_name);
    producer_imports = try replace_and_free(allocator, producer_imports, "[stream-module]", plan.stream_descriptor.canonical.async_import_module);
    producer_imports = try replace_and_free(allocator, producer_imports, "[stream-new-name]", stream_shape.new.import_name);
    producer_imports = try replace_and_free(allocator, producer_imports, "[stream-write-name]", stream_shape.write.import_name);
    producer_imports = try replace_and_free(allocator, producer_imports, "[stream-drop-readable-name]", stream_shape.drop_readable.import_name);
    producer_imports = try replace_and_free(allocator, producer_imports, "[stream-drop-writable-name]", stream_shape.drop_writable.import_name);

    var helpers = try allocator.dupe(u8, http_request_body_producer_helpers_wat);
    defer allocator.free(helpers);
    const write_count = try std.fmt.allocPrint(allocator, "{d}", .{plan.write_count});
    defer allocator.free(write_count);
    helpers = try replace_and_free(allocator, helpers, "[producer-count]", write_count);

    var wat = try allocator.dupe(u8, http_service_core_wat);
    errdefer allocator.free(wat);
    wat = try replace_and_free(allocator, wat, "[gc-frame-runtime]", gc_frame_runtime.items);
    wat = try replace_and_free(allocator, wat, "[task-return-params]", task_return_params);
    const task_return_error_lowering = try render_http_error_variant_lowering(allocator, send_descriptor, task_return_zero_tail);
    defer allocator.free(task_return_error_lowering);
    const task_return_ok_lowering = try render_http_ok_result_lowering(allocator, send_descriptor.canonical.completion_params, task_return_zero_tail);
    defer allocator.free(task_return_ok_lowering);
    wat = try replace_and_free(allocator, wat, "[task-return-zero-tail]", task_return_zero_tail);
    wat = try replace_and_free(allocator, wat, "[task-return-error-lowering]", task_return_error_lowering);
    wat = try replace_and_free(allocator, wat, "[task-return-ok-lowering]", task_return_ok_lowering);
    const send_import_anchor = "  (import \"wasi:http/client@0.3.0-rc-2025-09-16\" \"[async-lower]send\" (func $send (type $async-lower-send)))";
    const send_imports = try std.fmt.allocPrint(allocator, "{s}\n{s}", .{ send_import_anchor, producer_imports });
    defer allocator.free(send_imports);
    wat = try replace_and_free(allocator, wat, send_import_anchor, send_imports);
    wat = try replace_and_free(allocator, wat, "[body-future-event-handler]", http_request_body_producer_event_handler);
    wat = try replace_and_free(allocator, wat, "[async-lift]wasi:http/handler@0.3.0-rc-2025-09-16#handle", "[async-lift]wasi:http/probe@0.3.0-rc-2025-09-16#run");
    wat = try replace_and_free(allocator, wat, "[callback][async-lift]wasi:http/handler@0.3.0-rc-2025-09-16#handle", "[callback][async-lift]wasi:http/probe@0.3.0-rc-2025-09-16#run");
    wat = try replace_and_free(allocator, wat, "[export]wasi:http/handler@0.3.0-rc-2025-09-16", "[export]wasi:http/probe@0.3.0-rc-2025-09-16");
    wat = try replace_and_free(allocator, wat, "[task-return]handle", "[task-return]run");
    wat = try replace_and_free(allocator, wat, "(type $async-handler (func (param i32) (result i32)))", "(type $async-handler (func (result i32)))");
    wat = try replace_and_free(allocator, wat, "(param $request i32) (result i32)", "(result i32)");
    wat = try replace_and_free(allocator, wat, "(memory (export \"memory\") 1)", "(memory (export \"memory\") 1)\n  (data (i32.const 512) \"[producer-data]\")");
    wat = try replace_and_free(allocator, wat, "[producer-data]", producer_data);

    const frame_values = try producer_frame_values(allocator);
    defer allocator.free(frame_values);
    wat = try replace_and_free(
        allocator,
        wat,
        "    i32.const 1\n    call $waitable-set-new\n    i32.const 0\n    i32.const 0\n    i32.const 0\n    struct.new $async-frame",
        frame_values,
    );
    const old_send_start =
        "    local.get $request\n" ++
        "    local.get $frame-ref\n" ++
        "    struct.get $async-frame $slot-result-ptr\n" ++
        "    call $send\n" ++
        "    local.set $subtask\n" ++
        "[immediate-completion]";
    wat = try replace_and_free(allocator, wat, old_send_start, "    local.get $frame-ref\n    call $start-producer\n");
    const helper_prefix = try std.fmt.allocPrint(allocator, "{s}\n  (func $result-buffer-for-handle", .{helpers});
    defer allocator.free(helper_prefix);
    wat = try replace_and_free(allocator, wat, "  (func $result-buffer-for-handle", helper_prefix);
    wat = try replace_and_free(
        allocator,
        wat,
        "      call $canonical-buffer-release",
        "      local.get $frame-ref\n      call $drop-producer-reader\n      call $canonical-buffer-release",
    );
    return wat;
}

fn replace_http_payload_alias(allocator: std.mem.Allocator, import_name: []const u8) ![]u8 {
    const suffix = "response.consume-body";
    if (!std.mem.endsWith(u8, import_name, suffix)) return error.UnsupportedP3AsyncHttpService;

    const alias = "consume-body-payload";
    const prefix_len = import_name.len - suffix.len;
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, import_name[0..prefix_len]);
    try out.appendSlice(allocator, alias);
    return out.toOwnedSlice(allocator);
}

fn emit_http_core_wat(
    allocator: std.mem.Allocator,
    descriptor: p3_async_manifest.Descriptor,
    export_locator: []const u8,
    export_name: []const u8,
) ![]u8 {
    var slots = [_]async_model.FrameLayoutSlot{.{
        .name = "result-ptr",
        .storage = .i32,
        .offset = 16,
    }};
    const layout = async_model.FrameLayout{ .size = 24, .slots = &slots };
    var gc_frame_runtime = std.ArrayList(u8).empty;
    defer gc_frame_runtime.deinit(allocator);
    try gc_async_frame.emit_frame_table_layout(allocator, &gc_frame_runtime, layout);
    try append_canonical_buffer_metadata(allocator, &gc_frame_runtime, http_result_buffer_slot_bytes);
    try gc_async_frame.emit_frame_table_allocator_with_bytes(allocator, &gc_frame_runtime, layout.size);

    const async_import = try std.fmt.allocPrint(
        allocator,
        "(import \"{s}\" \"{s}\"",
        .{ descriptor.canonical.async_import_module, descriptor.canonical.async_import_name },
    );
    defer allocator.free(async_import);
    const task_return_import = try std.fmt.allocPrint(
        allocator,
        "(import \"[export]{s}\" \"[task-return]{s}\"",
        .{ export_locator, export_name },
    );
    defer allocator.free(task_return_import);
    const async_lift_export = try std.fmt.allocPrint(
        allocator,
        "[async-lift]{s}#{s}",
        .{ export_locator, export_name },
    );
    defer allocator.free(async_lift_export);
    const async_callback_export = try std.fmt.allocPrint(
        allocator,
        "[callback][async-lift]{s}#{s}",
        .{ export_locator, export_name },
    );
    defer allocator.free(async_callback_export);
    const task_return_params = try render_core_param_list(allocator, descriptor.canonical.completion_params);
    defer allocator.free(task_return_params);
    const task_return_zero_tail = try render_zero_tail(allocator, descriptor.canonical.completion_params);
    defer allocator.free(task_return_zero_tail);
    const task_return_error_lowering = try render_http_error_variant_lowering(allocator, descriptor, task_return_zero_tail);
    defer allocator.free(task_return_error_lowering);
    const task_return_ok_lowering = try render_http_ok_result_lowering(allocator, descriptor.canonical.completion_params, task_return_zero_tail);
    defer allocator.free(task_return_ok_lowering);
    const immediate_completion = try render_http_immediate_completion(
        allocator,
        task_return_error_lowering,
        task_return_ok_lowering,
    );
    defer allocator.free(immediate_completion);
    var wat = try allocator.dupe(u8, http_service_core_wat);
    wat = try replace_and_free(allocator, wat, "[gc-frame-runtime]", gc_frame_runtime.items);
    wat = try replace_and_free(allocator, wat, "[task-return-params]", task_return_params);
    wat = try replace_and_free(allocator, wat, "[task-return-zero-tail]", task_return_zero_tail);
    wat = try replace_and_free(allocator, wat, "[task-return-error-lowering]", task_return_error_lowering);
    wat = try replace_and_free(allocator, wat, "[task-return-ok-lowering]", task_return_ok_lowering);
    wat = try replace_and_free(allocator, wat, "[immediate-completion]", immediate_completion);
    wat = try replace_and_free(allocator, wat, "(import \"wasi:http/client@0.3.0-rc-2025-09-16\" \"[async-lower]send\"", async_import);
    wat = try replace_and_free(allocator, wat, "(import \"[export]wasi:http/handler@0.3.0-rc-2025-09-16\" \"[task-return]handle\"", task_return_import);
    wat = try replace_and_free(allocator, wat, "[async-lift]wasi:http/handler@0.3.0-rc-2025-09-16#handle", async_lift_export);
    wat = try replace_and_free(allocator, wat, "[callback][async-lift]wasi:http/handler@0.3.0-rc-2025-09-16#handle", async_callback_export);
    wat = try replace_and_free(allocator, wat, "[body-future-event-handler]", "        local.get $frame-ref\n        struct.get $async-frame $waitable-set\n        i32.const 4\n        i32.shl\n        i32.const 2\n        i32.or");
    return wat;
}

fn render_http_immediate_completion(
    allocator: std.mem.Allocator,
    error_lowering: []const u8,
    ok_lowering: []const u8,
) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "    local.get $subtask\n" ++
            "    i32.const 2\n" ++
            "    i32.eq\n" ++
            "    if (result i32)\n" ++
            "      local.get $frame-ref\n" ++
            "      struct.get $async-frame $slot-result-ptr\n" ++
            "      i32.load\n" ++
            "      if\n" ++
            "        local.get $frame-ref\n" ++
            "        struct.get $async-frame $slot-result-ptr\n" ++
            "        i32.const 8\n" ++
            "        i32.add\n" ++
            "        i32.load\n" ++
            "        local.set $error-tag\n" ++
            "{s}\n" ++
            "      else\n" ++
            "{s}\n" ++
            "      end\n" ++
            "      call $canonical-buffer-release\n" ++
            "      i32.const 0\n" ++
            "      call $context-set-0\n" ++
            "      local.get $frame\n" ++
            "      call $frame-free\n" ++
            "      i32.const 0\n" ++
            "    else\n" ++
            "      local.get $subtask\n" ++
            "      i32.const 4\n" ++
            "      i32.shr_u\n" ++
            "      local.get $frame-ref\n" ++
            "      struct.get $async-frame $waitable-set\n" ++
            "      call $waitable-join\n" ++
            "      local.get $frame-ref\n" ++
            "      struct.get $async-frame $waitable-set\n" ++
            "      i32.const 4\n" ++
            "      i32.shl\n" ++
            "      i32.const 2\n" ++
            "      i32.or\n" ++
            "    end",
        .{ error_lowering, ok_lowering },
    );
}

fn append_canonical_buffer_metadata(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    slot_bytes: u64,
) !void {
    const bytes = try async_byte_budget.bytes_for_canonical_buffer(0, slot_bytes);
    const metadata = try std.fmt.allocPrint(allocator, "  ;; [canonical-buffer-bytes] {d}\n", .{bytes});
    defer allocator.free(metadata);
    try out.appendSlice(allocator, metadata);
}

fn emit_http_request_send_wat(allocator: std.mem.Allocator, plan: HttpRequestSendPlan) ![]u8 {
    const request_shape = switch (p3_async_manifest.lowering_shape(plan.request_descriptor) orelse return error.UnsupportedP3AsyncHttpService) {
        .http_request_constructor => |value| value,
        else => return error.UnsupportedP3AsyncHttpService,
    };
    _ = switch (p3_async_manifest.lowering_shape(plan.send_descriptor) orelse return error.UnsupportedP3AsyncHttpService) {
        .http_resource_result => {},
        else => return error.UnsupportedP3AsyncHttpService,
    };
    const future_new = request_shape.trailers_future.new orelse return error.UnsupportedP3AsyncHttpService;
    const future_write = request_shape.trailers_future.write orelse return error.UnsupportedP3AsyncHttpService;
    const future_drop_writable = request_shape.trailers_future.drop_writable orelse return error.UnsupportedP3AsyncHttpService;

    var slots = [_]async_model.FrameLayoutSlot{.{
        .name = "result-ptr",
        .storage = .i32,
        .offset = 16,
    }};
    const layout = async_model.FrameLayout{ .size = 24, .slots = &slots };
    var gc_frame_runtime = std.ArrayList(u8).empty;
    defer gc_frame_runtime.deinit(allocator);
    try gc_async_frame.emit_frame_table_layout(allocator, &gc_frame_runtime, layout);
    try gc_async_frame.emit_frame_table_allocator_with_bytes(allocator, &gc_frame_runtime, layout.size);

    const task_return_params = try render_core_param_list(allocator, plan.send_descriptor.canonical.completion_params);
    defer allocator.free(task_return_params);
    const task_return_zero_tail = try render_zero_tail(allocator, plan.send_descriptor.canonical.completion_params);
    defer allocator.free(task_return_zero_tail);
    const task_return_error_lowering = try render_http_error_variant_lowering(allocator, plan.send_descriptor, task_return_zero_tail);
    defer allocator.free(task_return_error_lowering);
    const task_return_ok_lowering = try render_http_ok_result_lowering(allocator, plan.send_descriptor.canonical.completion_params, task_return_zero_tail);
    defer allocator.free(task_return_ok_lowering);
    const immediate_completion = try render_http_immediate_completion(
        allocator,
        task_return_error_lowering,
        task_return_ok_lowering,
    );
    defer allocator.free(immediate_completion);
    const task_return_import = try std.fmt.allocPrint(
        allocator,
        "(import \"[export]wasi:http/probe@0.3.0-rc-2025-09-16\" \"[task-return]run\"",
        .{},
    );
    defer allocator.free(task_return_import);
    const async_lift_export = "[async-lift]wasi:http/probe@0.3.0-rc-2025-09-16#run";
    const async_callback_export = "[callback][async-lift]wasi:http/probe@0.3.0-rc-2025-09-16#run";

    var request_imports = try allocator.dupe(u8, http_request_send_imports);
    defer allocator.free(request_imports);
    request_imports = try replace_and_free(allocator, request_imports, "[types-module]", http_types_locator);
    request_imports = try replace_and_free(allocator, request_imports, "[request-new-name]", plan.request_descriptor.canonical.async_import_name);
    request_imports = try replace_and_free(allocator, request_imports, "[future-new-name]", future_new.import_name);
    request_imports = try replace_and_free(allocator, request_imports, "[future-write-name]", future_write.import_name);
    request_imports = try replace_and_free(allocator, request_imports, "[future-drop-writable-name]", future_drop_writable.import_name);
    request_imports = try replace_and_free(allocator, request_imports, "[transmission-drop-name]", request_shape.transmission_future.drop_readable.import_name);

    const send_import_anchor = "  (import \"wasi:http/client@0.3.0-rc-2025-09-16\" \"[async-lower]send\" (func $send (type $async-lower-send)))";
    const send_imports = try std.fmt.allocPrint(allocator, "{s}\n{s}", .{ send_import_anchor, request_imports });
    defer allocator.free(send_imports);
    const constructor_helper = try allocator.dupe(u8, http_request_constructor_helper_wat);
    defer allocator.free(constructor_helper);
    const helper_prefix = try std.fmt.allocPrint(allocator, "{s}\n  (func $result-buffer-for-handle", .{constructor_helper});
    defer allocator.free(helper_prefix);

    var wat = try allocator.dupe(u8, http_service_core_wat);
    errdefer allocator.free(wat);
    wat = try replace_and_free(allocator, wat, "[gc-frame-runtime]", gc_frame_runtime.items);
    wat = try replace_and_free(allocator, wat, "[task-return-params]", task_return_params);
    wat = try replace_and_free(allocator, wat, "[task-return-zero-tail]", task_return_zero_tail);
    wat = try replace_and_free(allocator, wat, "[task-return-error-lowering]", task_return_error_lowering);
    wat = try replace_and_free(allocator, wat, "[task-return-ok-lowering]", task_return_ok_lowering);
    wat = try replace_and_free(allocator, wat, "[immediate-completion]", immediate_completion);
    wat = try replace_and_free(allocator, wat, send_import_anchor, send_imports);
    wat = try replace_and_free(allocator, wat, "(type $async-handler (func (param i32) (result i32)))", "(type $async-handler (func (result i32)))");
    wat = try replace_and_free(allocator, wat, "(param $request i32) (result i32)", "(result i32)");
    wat = try replace_and_free(allocator, wat, "local.get $request\n    local.get $frame-ref", "call $construct-request\n    local.get $frame-ref");
    wat = try replace_and_free(allocator, wat, "  (func $result-buffer-for-handle", helper_prefix);
    wat = try replace_and_free(allocator, wat, "[async-lift]wasi:http/handler@0.3.0-rc-2025-09-16#handle", async_lift_export);
    wat = try replace_and_free(allocator, wat, "[callback][async-lift]wasi:http/handler@0.3.0-rc-2025-09-16#handle", async_callback_export);
    wat = try replace_and_free(allocator, wat, "(import \"[export]wasi:http/handler@0.3.0-rc-2025-09-16\" \"[task-return]handle\"", task_return_import);
    wat = try replace_and_free(allocator, wat, "[body-future-event-handler]", "        local.get $frame-ref\n        struct.get $async-frame $waitable-set\n        i32.const 4\n        i32.shl\n        i32.const 2\n        i32.or");
    return wat;
}

fn emit_http_request_body_wat(allocator: std.mem.Allocator, plan: HttpRequestBodyPlan) ![]u8 {
    const request_shape = switch (p3_async_manifest.lowering_shape(plan.request_descriptor) orelse return error.UnsupportedP3AsyncHttpService) {
        .http_request_constructor => |value| value,
        else => return error.UnsupportedP3AsyncHttpService,
    };
    const body_shape = switch (p3_async_manifest.lowering_shape(plan.body_descriptor) orelse return error.UnsupportedP3AsyncHttpService) {
        .stream_reader_acquire => |value| value,
        else => return error.UnsupportedP3AsyncHttpService,
    };
    _ = switch (p3_async_manifest.lowering_shape(plan.send_descriptor) orelse return error.UnsupportedP3AsyncHttpService) {
        .http_resource_result => {},
        else => return error.UnsupportedP3AsyncHttpService,
    };
    const future_new = request_shape.trailers_future.new orelse return error.UnsupportedP3AsyncHttpService;
    const future_write = request_shape.trailers_future.write orelse return error.UnsupportedP3AsyncHttpService;
    const future_drop_writable = request_shape.trailers_future.drop_writable orelse return error.UnsupportedP3AsyncHttpService;
    const body_future_read = if (plan.await_body_completion)
        (plan.body_descriptor.canonical.future orelse return error.UnsupportedP3AsyncHttpService).read orelse return error.UnsupportedP3AsyncHttpService
    else
        null;

    var slots = [_]async_model.FrameLayoutSlot{
        .{ .name = "result-ptr", .storage = .i32, .offset = 16 },
        .{ .name = "body-completion", .storage = .i32, .offset = 20 },
        .{ .name = "body-request", .storage = .i32, .offset = 24 },
        .{ .name = "body-completion-result", .storage = .i32, .offset = 28 },
    };
    const layout = async_model.FrameLayout{ .size = 32, .slots = &slots };
    var gc_frame_runtime = std.ArrayList(u8).empty;
    defer gc_frame_runtime.deinit(allocator);
    try gc_async_frame.emit_frame_table_layout(allocator, &gc_frame_runtime, layout);
    try gc_async_frame.emit_frame_table_allocator_with_bytes(allocator, &gc_frame_runtime, layout.size);

    const task_return_params = try render_core_param_list(allocator, plan.send_descriptor.canonical.completion_params);
    defer allocator.free(task_return_params);
    const task_return_zero_tail = try render_zero_tail(allocator, plan.send_descriptor.canonical.completion_params);
    defer allocator.free(task_return_zero_tail);
    const task_return_error_lowering = try render_http_error_variant_lowering(allocator, plan.send_descriptor, task_return_zero_tail);
    defer allocator.free(task_return_error_lowering);
    const task_return_ok_lowering = try render_http_ok_result_lowering(allocator, plan.send_descriptor.canonical.completion_params, task_return_zero_tail);
    defer allocator.free(task_return_ok_lowering);
    const immediate_completion = try render_http_immediate_completion(
        allocator,
        task_return_error_lowering,
        task_return_ok_lowering,
    );
    defer allocator.free(immediate_completion);
    const task_return_import = try std.fmt.allocPrint(
        allocator,
        "(import \"[export]wasi:http/probe@0.3.0-rc-2025-09-16\" \"[task-return]run\"",
        .{},
    );
    defer allocator.free(task_return_import);
    const async_lift_export = "[async-lift]wasi:http/probe@0.3.0-rc-2025-09-16#run";
    const async_callback_export = "[callback][async-lift]wasi:http/probe@0.3.0-rc-2025-09-16#run";

    var request_imports = try allocator.dupe(u8, http_request_send_imports);
    defer allocator.free(request_imports);
    request_imports = try replace_and_free(allocator, request_imports, "[types-module]", http_types_locator);
    request_imports = try replace_and_free(allocator, request_imports, "[request-new-name]", plan.request_descriptor.canonical.async_import_name);
    request_imports = try replace_and_free(allocator, request_imports, "[future-new-name]", future_new.import_name);
    request_imports = try replace_and_free(allocator, request_imports, "[future-write-name]", future_write.import_name);
    request_imports = try replace_and_free(allocator, request_imports, "[future-drop-writable-name]", future_drop_writable.import_name);
    request_imports = try replace_and_free(allocator, request_imports, "[transmission-drop-name]", request_shape.transmission_future.drop_readable.import_name);
    const body_future_read_import = if (body_future_read) |operation|
        try std.fmt.allocPrint(
            allocator,
            "  (type $body-future-read (func (param i32 i32) (result i32)))\n  (import \"{s}\" \"{s}\" (func $body-future-read (type $body-future-read)))\n",
            .{ plan.body_descriptor.canonical.async_import_module, operation.import_name },
        )
    else
        try allocator.dupe(u8, "");
    defer allocator.free(body_future_read_import);
    const body_imports = try std.fmt.allocPrint(
        allocator,
        "  (type $body-acquire (func (param i32)))\n  (type $body-drop (func (param i32)))\n  (import \"{s}\" \"{s}\" (func $body-acquire (type $body-acquire)))\n  (import \"{s}\" \"{s}\" (func $body-completion-drop (type $body-drop)))\n{s}",
        .{ plan.body_descriptor.canonical.async_import_module, plan.body_descriptor.canonical.async_import_name, plan.body_descriptor.canonical.async_import_module, body_shape.future_drop_readable.import_name, body_future_read_import },
    );
    defer allocator.free(body_imports);
    const send_import_anchor = "  (import \"wasi:http/client@0.3.0-rc-2025-09-16\" \"[async-lower]send\" (func $send (type $async-lower-send)))";
    const send_imports = try std.fmt.allocPrint(allocator, "{s}\n{s}\n{s}", .{ send_import_anchor, request_imports, body_imports });
    defer allocator.free(send_imports);

    var helper = try allocator.dupe(u8, http_request_body_constructor_helper_wat);
    defer allocator.free(helper);
    helper = try replace_and_free(allocator, helper, "[body-module]", plan.body_descriptor.canonical.async_import_module);
    helper = try replace_and_free(allocator, helper, "[body-acquire-name]", plan.body_descriptor.canonical.async_import_name);
    helper = try replace_and_free(allocator, helper, "[request-module]", http_types_locator);
    helper = try replace_and_free(allocator, helper, "[request-new-name]", plan.request_descriptor.canonical.async_import_name);
    helper = try replace_and_free(allocator, helper, "[future-new-name]", future_new.import_name);
    helper = try replace_and_free(allocator, helper, "[future-write-name]", future_write.import_name);
    helper = try replace_and_free(allocator, helper, "[future-drop-writable-name]", future_drop_writable.import_name);
    helper = try replace_and_free(allocator, helper, "[transmission-drop-name]", request_shape.transmission_future.drop_readable.import_name);
    const construct_acquire = if (plan.await_body_completion)
        ""
    else
        "    local.get $frame-ref\n    call $acquire-body";
    helper = try replace_and_free(allocator, helper, "[construct-acquire]", construct_acquire);
    const body_completion_functions = if (plan.await_body_completion)
        http_request_body_completion_await_functions
    else
        "";
    helper = try replace_and_free(allocator, helper, "[body-completion-functions]", body_completion_functions);
    const helper_prefix = try std.fmt.allocPrint(allocator, "{s}\n  (func $result-buffer-for-handle", .{helper});
    defer allocator.free(helper_prefix);

    var wat = try allocator.dupe(u8, http_service_core_wat);
    errdefer allocator.free(wat);
    wat = try replace_and_free(allocator, wat, "[gc-frame-runtime]", gc_frame_runtime.items);
    wat = try replace_and_free(allocator, wat, "[task-return-params]", task_return_params);
    wat = try replace_and_free(allocator, wat, "[task-return-zero-tail]", task_return_zero_tail);
    wat = try replace_and_free(allocator, wat, "[task-return-error-lowering]", task_return_error_lowering);
    wat = try replace_and_free(allocator, wat, "[task-return-ok-lowering]", task_return_ok_lowering);
    wat = try replace_and_free(allocator, wat, send_import_anchor, send_imports);
    wat = try replace_and_free(allocator, wat, "(type $async-handler (func (param i32) (result i32)))", "(type $async-handler (func (result i32)))");
    wat = try replace_and_free(allocator, wat, "(param $request i32) (result i32)", "(result i32)");
    const request_start = if (plan.await_body_completion)
        "    local.get $frame-ref\n    call $start-body-request"
    else
        "    local.get $frame-ref\n    call $construct-request\n    local.get $frame-ref\n    struct.get $async-frame $slot-result-ptr\n    call $send";
    wat = try replace_and_free(allocator, wat, "    local.get $request\n    local.get $frame-ref\n    struct.get $async-frame $slot-result-ptr\n    call $send", request_start);
    const request_wait = if (plan.await_body_completion) "    return" else immediate_completion;
    wat = try replace_and_free(allocator, wat, "[immediate-completion]", request_wait);
    const body_future_event_handler = if (plan.await_body_completion)
        "        local.get $event\n        i32.const 4\n        i32.eq\n        if (result i32)\n          local.get $frame-ref\n          local.get $payload\n          call $accept-body-completion\n        else\n          unreachable\n        end"
    else
        "        local.get $frame-ref\n        struct.get $async-frame $waitable-set\n        i32.const 4\n        i32.shl\n        i32.const 2\n        i32.or";
    wat = try replace_and_free(allocator, wat, "[body-future-event-handler]", body_future_event_handler);
    wat = try replace_and_free(allocator, wat, "    i32.const 0\n    i32.const 0\n    i32.const 0\n    struct.new $async-frame", "    i32.const 0\n    i32.const 0\n    i32.const 0\n    i32.const 0\n    i32.const 0\n    i32.const 0\n    struct.new $async-frame");
    wat = try replace_and_free(allocator, wat, "  (func $result-buffer-for-handle", helper_prefix);
    wat = try replace_and_free(allocator, wat, "[async-lift]wasi:http/handler@0.3.0-rc-2025-09-16#handle", async_lift_export);
    wat = try replace_and_free(allocator, wat, "[callback][async-lift]wasi:http/handler@0.3.0-rc-2025-09-16#handle", async_callback_export);
    wat = try replace_and_free(allocator, wat, "(import \"[export]wasi:http/handler@0.3.0-rc-2025-09-16\" \"[task-return]handle\"", task_return_import);
    wat = try replace_all_with_body_cleanup(allocator, wat);
    return wat;
}

fn replace_all_with_body_cleanup(allocator: std.mem.Allocator, input: []u8) ![]u8 {
    const needle = "        call $task-return";
    const replacement = "        local.get $frame-ref\n        call $drop-body-completion\n        call $task-return";
    return replace_and_free(allocator, input, needle, replacement);
}

fn render_core_param_list(allocator: std.mem.Allocator, params: []const []const u8) ![]u8 {
    if (params.len == 0) return error.UnsupportedP3AsyncHttpService;
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    for (params, 0..) |param, index| {
        if (!std.mem.eql(u8, param, "i32") and !std.mem.eql(u8, param, "i64")) return error.UnsupportedP3AsyncHttpService;
        if (index != 0) try out.append(allocator, ' ');
        try out.appendSlice(allocator, param);
    }
    return out.toOwnedSlice(allocator);
}

fn render_zero_tail(allocator: std.mem.Allocator, params: []const []const u8) ![]u8 {
    if (params.len < 3) return error.UnsupportedP3AsyncHttpService;
    return render_zero_words(allocator, params[2..]);
}

fn render_http_ok_result_lowering(
    allocator: std.mem.Allocator,
    completion_params: []const []const u8,
    zero_tail: []const u8,
) ![]u8 {
    if (completion_params.len < 3 or
        !std.mem.eql(u8, completion_params[0], "i32") or
        !std.mem.eql(u8, completion_params[1], "i32")) return error.UnsupportedP3AsyncHttpService;
    return std.fmt.allocPrint(
        allocator,
        "        i32.const 0\n" ++
            "        local.get $frame-ref\n" ++
            "        struct.get $async-frame $slot-result-ptr\n" ++
            "        i32.const 8\n" ++
            "        i32.add\n" ++
            "        i32.load\n" ++
            "{s}\n" ++
            "        call $task-return",
        .{zero_tail},
    );
}

fn render_zero_words(allocator: std.mem.Allocator, params: []const []const u8) ![]u8 {
    if (params.len == 0) return error.UnsupportedP3AsyncHttpService;
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    for (params, 0..) |param, index| {
        if (!std.mem.eql(u8, param, "i32") and !std.mem.eql(u8, param, "i64")) return error.UnsupportedP3AsyncHttpService;
        if (index != 0) try out.appendSlice(allocator, "\n        ");
        try out.appendSlice(allocator, param);
        try out.appendSlice(allocator, ".const 0");
    }
    return out.toOwnedSlice(allocator);
}

const http_error_guard_discriminants = [_]i32{ 1, 14, 17, 21, 22, 23, 24, 26, 27, 28, 29, 30, 31, 32 };

fn render_http_error_tag_guards(
    allocator: std.mem.Allocator,
    descriptor: p3_async_manifest.Descriptor,
    allow_dns_payload: bool,
) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    for (http_error_guard_discriminants) |discriminant| {
        if (allow_dns_payload and discriminant == 1 and descriptor_has_dns_error_variant(descriptor)) continue;
        const guard = try std.fmt.allocPrint(
            allocator,
            "        local.get $error-tag\n" ++
                "        i32.const {d}\n" ++
                "        i32.eq\n" ++
                "        if unreachable end\n",
            .{discriminant},
        );
        defer allocator.free(guard);
        try out.appendSlice(allocator, guard);
    }
    return out.toOwnedSlice(allocator);
}

fn descriptor_has_dns_error_variant(descriptor: p3_async_manifest.Descriptor) bool {
    for (descriptor.canonical.error_variants) |variant| {
        if (variant.discriminant == 1 and std.mem.eql(u8, variant.variant, "DNS-error")) return true;
    }
    return false;
}

fn render_http_error_variant_lowering(
    allocator: std.mem.Allocator,
    descriptor: p3_async_manifest.Descriptor,
    fallback_zero_tail: []const u8,
) ![]u8 {
    var internal_payload: ?p3_async_manifest.ErrorVariantPayload = null;
    for (descriptor.canonical.error_variants) |variant| {
        if (std.mem.eql(u8, variant.variant, "internal-error")) {
            internal_payload = variant;
            break;
        }
    }

    const payload = internal_payload orelse {
        const tag_guards = try render_http_error_tag_guards(allocator, descriptor, false);
        defer allocator.free(tag_guards);
        return std.fmt.allocPrint(
            allocator,
            "{s}" ++
                "        local.get $error-tag\n" ++
                "        i32.const 38\n" ++
                "        i32.eq\n" ++
                "        if unreachable end\n" ++
                "        i32.const 1\n" ++
                "        local.get $error-tag\n" ++
                "        {s}\n" ++
                "        call $task-return",
            .{ tag_guards, fallback_zero_tail },
        );
    };
    if (payload.fields.len != 1 or payload.fields[0].kind != .optional_string) return error.UnsupportedP3AsyncHttpService;
    const field = payload.fields[0];
    if (field.offset != 16 or field.core_words.len != 3) return error.UnsupportedP3AsyncHttpService;
    const pointer_offset = field.offset + 4;
    const length_offset = field.offset + 8;
    if (descriptor.canonical.completion_params.len <= 2 + field.core_words.len) return error.UnsupportedP3AsyncHttpService;
    const residual_zero_tail = try render_zero_words(allocator, descriptor.canonical.completion_params[2 + field.core_words.len ..]);
    defer allocator.free(residual_zero_tail);
    const dns_fallback = try render_http_dns_error_variant_fallback(allocator, descriptor, fallback_zero_tail);
    defer allocator.free(dns_fallback);
    const tag_guards = try render_http_error_tag_guards(allocator, descriptor, true);
    defer allocator.free(tag_guards);
    return std.fmt.allocPrint(
        allocator,
        "{s}" ++
            "        ;; [error-variant:internal-error]\n" ++
            "        local.get $error-tag\n" ++
            "        i32.const {d}\n" ++
            "        i32.eq\n" ++
            "        if\n" ++
            "          i32.const 1\n" ++
            "          local.get $error-tag\n" ++
            "          local.get $frame-ref\n" ++
            "          struct.get $async-frame $slot-result-ptr\n" ++
            "          i32.const {d}\n" ++
            "          i32.add\n" ++
            "          i32.load\n" ++
            "          local.get $frame-ref\n" ++
            "          struct.get $async-frame $slot-result-ptr\n" ++
            "          i32.const {d}\n" ++
            "          i32.add\n" ++
            "          i32.load\n" ++
            "          i64.extend_i32_u\n" ++
            "          local.get $frame-ref\n" ++
            "          struct.get $async-frame $slot-result-ptr\n" ++
            "          i32.const {d}\n" ++
            "          i32.add\n" ++
            "          i32.load\n" ++
            "          {s}\n" ++
            "          call $task-return\n" ++
            "        else\n" ++
            "{s}\n" ++
            "        end",
        .{ tag_guards, payload.discriminant, field.offset, pointer_offset, length_offset, residual_zero_tail, dns_fallback },
    );
}

fn render_http_dns_error_variant_fallback(
    allocator: std.mem.Allocator,
    descriptor: p3_async_manifest.Descriptor,
    fallback_zero_tail: []const u8,
) ![]u8 {
    var dns_payload: ?p3_async_manifest.ErrorVariantPayload = null;
    for (descriptor.canonical.error_variants) |variant| {
        if (std.mem.eql(u8, variant.variant, "DNS-error")) {
            dns_payload = variant;
            break;
        }
    }
    const payload = dns_payload orelse return allocator.dupe(u8, fallback_zero_tail);
    if (payload.discriminant != 1 or payload.byte_size != 32 or payload.fields.len != 2) return error.UnsupportedP3AsyncHttpService;
    const rcode = payload.fields[0];
    const info_code = payload.fields[1];
    if (!std.mem.eql(u8, rcode.name, "rcode") or rcode.kind != .optional_string or rcode.offset != 16 or
        rcode.core_words.len != 3 or !std.mem.eql(u8, rcode.core_words[0], "i32") or
        !std.mem.eql(u8, rcode.core_words[1], "i64") or !std.mem.eql(u8, rcode.core_words[2], "i32") or
        !std.mem.eql(u8, info_code.name, "info-code") or info_code.kind != .optional_u16 or
        info_code.offset != 28 or info_code.core_words.len != 2 or
        !std.mem.eql(u8, info_code.core_words[0], "i32") or !std.mem.eql(u8, info_code.core_words[1], "i32"))
        return error.UnsupportedP3AsyncHttpService;
    if (descriptor.canonical.completion_params.len <= 2 + rcode.core_words.len + info_code.core_words.len)
        return error.UnsupportedP3AsyncHttpService;
    const residual_zero_tail = try render_zero_words(
        allocator,
        descriptor.canonical.completion_params[2 + rcode.core_words.len + info_code.core_words.len ..],
    );
    defer allocator.free(residual_zero_tail);
    return std.fmt.allocPrint(
        allocator,
        "        local.get $error-tag\n" ++
            "        i32.const {d}\n" ++
            "        i32.eq\n" ++
            "        if\n" ++
            "          ;; [error-variant:DNS-error]\n" ++
            "          i32.const 1\n" ++
            "          local.get $error-tag\n" ++
            "          local.get $frame-ref\n" ++
            "          struct.get $async-frame $slot-result-ptr\n" ++
            "          i32.const {d}\n" ++
            "          i32.add\n" ++
            "          i32.load8_u\n" ++
            "          local.get $frame-ref\n" ++
            "          struct.get $async-frame $slot-result-ptr\n" ++
            "          i32.const {d}\n" ++
            "          i32.add\n" ++
            "          i32.load\n" ++
            "          i64.extend_i32_u\n" ++
            "          local.get $frame-ref\n" ++
            "          struct.get $async-frame $slot-result-ptr\n" ++
            "          i32.const {d}\n" ++
            "          i32.add\n" ++
            "          i32.load\n" ++
            "          local.get $frame-ref\n" ++
            "          struct.get $async-frame $slot-result-ptr\n" ++
            "          i32.const {d}\n" ++
            "          i32.add\n" ++
            "          i32.load8_u\n" ++
            "          local.get $frame-ref\n" ++
            "          struct.get $async-frame $slot-result-ptr\n" ++
            "          i32.const {d}\n" ++
            "          i32.add\n" ++
            "          i32.load16_u\n" ++
            "          {s}\n" ++
            "          call $task-return\n" ++
            "        else\n" ++
            "          i32.const 1\n" ++
            "          local.get $error-tag\n" ++
            "          {s}\n" ++
            "          call $task-return\n" ++
            "        end",
        .{
            payload.discriminant,
            rcode.offset,
            rcode.offset + 4,
            rcode.offset + 8,
            info_code.offset,
            info_code.offset + 2,
            residual_zero_tail,
            fallback_zero_tail,
        },
    );
}

fn replace_and_free(allocator: std.mem.Allocator, input: []u8, needle: []const u8, replacement: []const u8) ![]u8 {
    const replaced = try replace_all(allocator, input, needle, replacement);
    allocator.free(input);
    return replaced;
}

fn replace_all(allocator: std.mem.Allocator, input: []const u8, needle: []const u8, replacement: []const u8) ![]u8 {
    if (needle.len == 0) return error.UnsupportedP3AsyncHttpService;
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

const http_response_trailers_read_functions =
    \\  (func $wait-on-trailers (param $frame i32) (result i32)
    \\    local.get $frame
    \\    i32.const 8
    \\    i32.add
    \\    i32.load
    \\    local.get $frame
    \\    i32.load
    \\    call $waitable-join
    \\    local.get $frame
    \\    i32.load
    \\    i32.const 4
    \\    i32.shl
    \\    i32.const 2
    \\    i32.or
    \\  )
    \\  (func $accept-trailers (param $frame i32) (param $code i32) (result i32)
    \\    local.get $code
    \\    i32.const 0
    \\    i32.ne
    \\    if unreachable end
    \\    local.get $frame
    \\    call $cleanup
    \\  )
    \\  (func $start-trailers (param $frame i32) (result i32) (local $code i32)
    \\    local.get $frame
    \\    i32.const 8
    \\    i32.add
    \\    i32.load
    \\    i32.const 24
    \\    call $future-read
    \\    local.tee $code
    \\    i32.const -1
    \\    i32.eq
    \\    if (result i32)
    \\      local.get $frame
    \\      call $wait-on-trailers
    \\    else
    \\      local.get $frame
    \\      local.get $code
    \\      call $accept-trailers
    \\    end
    \\  )
;

const http_cabi_budget_runtime =
    \\  ;; Canonical realloc owns its byte-budget delta transactionally.
    \\  ;; The -1 limit keeps the historical unlimited default.
    \\  (global $async-byte-budget-used (mut i64) (i64.const 0))
    \\  (global $async-byte-budget-limit (mut i64) (i64.const -1))
    \\  (func $async-byte-budget-limit (export "[async-config]byte-budget-limit") (param $limit i64) (result i32)
    \\    local.get $limit
    \\    i64.const -1
    \\    i64.eq
    \\    if (result i32)
    \\      local.get $limit
    \\      global.set $async-byte-budget-limit
    \\      i32.const 1
    \\    else
    \\      local.get $limit
    \\      i64.const 0
    \\      i64.lt_s
    \\      if (result i32)
    \\        i32.const 0
    \\      else
    \\        global.get $async-byte-budget-used
    \\        local.get $limit
    \\        i64.gt_u
    \\        if (result i32)
    \\          i32.const 0
    \\        else
    \\          local.get $limit
    \\          global.set $async-byte-budget-limit
    \\          i32.const 1
    \\        end
    \\      end
    \\    end
    \\  )
    \\  (func (export "byte-budget-limit") (param $limit i64) (result i32)
    \\    local.get $limit
    \\    call $async-byte-budget-limit)
    \\  (func $async-byte-budget-reserve (param $bytes i64) (result i32)
    \\    (local $next i64)
    \\    global.get $async-byte-budget-used
    \\    local.get $bytes
    \\    i64.add
    \\    local.tee $next
    \\    global.get $async-byte-budget-used
    \\    i64.lt_u
    \\    if (result i32)
    \\      i32.const 0
    \\    else
    \\      global.get $async-byte-budget-limit
    \\      i64.const -1
    \\      i64.eq
    \\      if (result i32)
    \\        i32.const 1
    \\      else
    \\        local.get $next
    \\        global.get $async-byte-budget-limit
    \\        i64.le_u
    \\      end
    \\      if (result i32)
    \\        local.get $next
    \\        global.set $async-byte-budget-used
    \\        i32.const 1
    \\      else
    \\        i32.const 0
    \\      end
    \\    end
    \\  )
    \\  (func $async-byte-budget-release (param $bytes i64)
    \\    global.get $async-byte-budget-used
    \\    local.get $bytes
    \\    i64.lt_u
    \\    if unreachable end
    \\    global.get $async-byte-budget-used
    \\    local.get $bytes
    \\    i64.sub
    \\    global.set $async-byte-budget-used
    \\  )
    \\  (global $heap-next (mut i32) (i32.const 65536))
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
;

const http_response_body_core_wat =
    \\(module
    \\  (type $consume-body (func (param i32 i32 i32)))
    \\  (type $future-new (func (result i64)))
    \\  (type $future-write (func (param i32 i32) (result i32)))
    \\  (type $resource-drop (func (param i32)))
    \\  (type $async-run (func (param i32) (result i32)))
    \\  (type $async-run-callback (func (param i32 i32 i32) (result i32)))
    \\  (type $task-return (func))
    \\  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
    \\  (type $initialize (func))
    \\  (import "[consume-body-module]" "[consume-body-name]" (func $consume-body (type $consume-body)))
    \\  (import "[consume-body-module]" "[future-new-name]" (func $future-new (type $future-new)))
    \\  (import "[consume-body-module]" "[future-write-name]" (func $future-write (type $future-write)))
    \\  (import "[consume-body-module]" "[future-drop-writable-name]" (func $future-drop-writable (type $resource-drop)))
    \\  (import "[consume-body-module]" "[stream-drop-name]" (func $stream-drop-readable (type $resource-drop)))
    \\  (import "[consume-body-module]" "[future-drop-name]" (func $future-drop-readable (type $resource-drop)))
    \\  (import "[export][task-return-locator]" "[task-return]run" (func $task-return (type $task-return)))
    \\  (memory (export "memory") 1)
    \\[cabi-budget-runtime]
    \\  (func (export "[async-lift-name]") (type $async-run) (param $response i32) (result i32) (local $future-pair i64)
    \\    call $future-new
    \\    local.set $future-pair
    \\    local.get $response
    \\    local.get $future-pair
    \\    i32.wrap_i64
    \\    i32.const 36
    \\    call $consume-body
    \\    i32.const 48
    \\    i32.const 0
    \\    i32.store
    \\    local.get $future-pair
    \\    i64.const 32
    \\    i64.shr_u
    \\    i32.wrap_i64
    \\    i32.const 48
    \\    call $future-write
    \\    drop
    \\    local.get $future-pair
    \\    i64.const 32
    \\    i64.shr_u
    \\    i32.wrap_i64
    \\    call $future-drop-writable
    \\    i32.const 36
    \\    i32.load
    \\    call $stream-drop-readable
    \\    i32.const 40
    \\    i32.load
    \\    call $future-drop-readable
    \\    call $task-return
    \\    i32.const 0
    \\  )
    \\  (func (export "[callback-async-lift-name]") (type $async-run-callback) (param i32 i32 i32) (result i32)
    \\    i32.const 0
    \\  )
    \\  (func (export "_initialize") (type $initialize))
    \\)
;

const http_response_body_read_core_wat =
    \\(module
    \\  (type $consume-body (func (param i32 i32 i32)))
    \\  (type $future-new (func (result i64)))
    \\  (type $future-write (func (param i32 i32) (result i32)))
    \\  (type $stream-read (func (param i32 i32 i32) (result i32)))
    \\  (type $future-read (func (param i32 i32) (result i32)))
    \\  (type $resource-drop (func (param i32)))
    \\  (type $waitable-set-new (func (result i32)))
    \\  (type $waitable-join (func (param i32 i32)))
    \\  (type $waitable-set-drop (func (param i32)))
    \\  (type $async-run (func (param i32) (result i32)))
    \\  (type $async-run-callback (func (param i32 i32 i32) (result i32)))
    \\  (type $task-return (func))
    \\  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
    \\  (type $initialize (func))
    \\  (import "[consume-body-module]" "[consume-body-name]" (func $consume-body (type $consume-body)))
    \\  (import "[consume-body-module]" "[future-new-name]" (func $future-new (type $future-new)))
    \\  (import "[consume-body-module]" "[future-write-name]" (func $future-write (type $future-write)))
    \\  (import "[consume-body-module]" "[future-drop-writable-name]" (func $future-drop-writable (type $resource-drop)))
    \\  (import "[consume-body-module]" "[stream-read-name]" (func $stream-read (type $stream-read)))
    \\[future-read-import]
    \\  (import "[consume-body-module]" "[stream-drop-name]" (func $stream-drop-readable (type $resource-drop)))
    \\  (import "[consume-body-module]" "[future-drop-name]" (func $future-drop-readable (type $resource-drop)))
    \\  (import "$root" "[waitable-set-new]" (func $waitable-set-new (type $waitable-set-new)))
    \\  (import "$root" "[waitable-set-wait]" (func $waitable-set-wait (param i32 i32) (result i32)))
    \\  (import "$root" "[waitable-set-poll]" (func $waitable-set-poll (param i32 i32) (result i32)))
    \\  (import "$root" "[waitable-set-drop]" (func $waitable-set-drop (type $waitable-set-drop)))
    \\  (import "$root" "[waitable-join]" (func $waitable-join (param i32 i32)))
    \\  (import "$root" "[context-get-0]" (func $context-get-0 (result i32)))
    \\  (import "$root" "[context-set-0]" (func $context-set-0 (param i32)))
    \\  (import "[export][task-return-locator]" "[task-return]run" (func $task-return (type $task-return)))
    \\  (memory (export "memory") 1)
    \\[cabi-budget-runtime]
    \\  (global $frame-free (mut i32) (i32.const 0))
    \\  (global $frame-next (mut i32) (i32.const 1024))
    \\  (func $frame-alloc (result i32) (local $frame i32)
    \\    global.get $frame-free
    \\    local.tee $frame
    \\    i32.eqz
    \\    if (result i32)
    \\      global.get $frame-next
    \\      local.set $frame
    \\      global.get $frame-next
    \\      i32.const 64
    \\      i32.add
    \\      global.set $frame-next
    \\      local.get $frame
    \\    else
    \\      local.get $frame
    \\      i32.load
    \\      global.set $frame-free
    \\      local.get $frame
    \\    end
    \\  )
    \\  (func $frame-free (param $frame i32)
    \\    local.get $frame
    \\    global.get $frame-free
    \\    i32.store
    \\    local.get $frame
    \\    global.set $frame-free
    \\  )
    \\  (func $cleanup (param $frame i32) (result i32)
    \\    local.get $frame
    \\    i32.const 8
    \\    i32.add
    \\    i32.load
    \\    call $future-drop-readable
    \\    local.get $frame
    \\    i32.const 4
    \\    i32.add
    \\    i32.load
    \\    call $stream-drop-readable
    \\    local.get $frame
    \\    i32.load
    \\    call $waitable-set-drop
    \\    i32.const 0
    \\    call $context-set-0
    \\    local.get $frame
    \\    call $frame-free
    \\    call $task-return
    \\    i32.const 0
    \\  )
    \\  (func $wait-on-stream (param $frame i32) (result i32)
    \\    local.get $frame
    \\    i32.const 4
    \\    i32.add
    \\    i32.load
    \\    local.get $frame
    \\    i32.load
    \\    call $waitable-join
    \\    local.get $frame
    \\    i32.load
    \\    i32.const 4
    \\    i32.shl
    \\    i32.const 2
    \\    i32.or
    \\  )
    \\[trailers-read-functions]
    \\  (func $accept-read (param $frame i32) (param $code i32) (result i32)
    \\    ;; [stream-eof] Err(nil) is a terminal body result at any bounded read.
    \\    local.get $code
    \\    i32.const 1
    \\    i32.eq
    \\    if
    \\      [finish-body]
    \\      return
    \\    end
    \\    local.get $code
    \\    i32.const 16
    \\    i32.ne
    \\    if unreachable end
    \\    local.get $frame
    \\    i32.const 20
    \\    i32.add
    \\    local.get $frame
    \\    i32.const 20
    \\    i32.add
    \\    i32.load
    \\    i32.const 1
    \\    i32.add
    \\    i32.store
    \\    local.get $frame
    \\    i32.const 20
    \\    i32.add
    \\    i32.load
    \\    i32.const [stream-read-count-value]
    \\    i32.eq
    \\    if
    \\      [finish-body]
    \\      return
    \\    end
    \\    local.get $frame
    \\    call $start-read
    \\  )
    \\  (func $start-read (param $frame i32) (result i32) (local $code i32)
    \\    local.get $frame
    \\    i32.const 4
    \\    i32.add
    \\    i32.load
    \\    local.get $frame
    \\    i32.const 16
    \\    i32.add
    \\    i32.const 1
    \\    call $stream-read
    \\    local.tee $code
    \\    i32.const -1
    \\    i32.eq
    \\    if (result i32)
    \\      local.get $frame
    \\      call $wait-on-stream
    \\    else
    \\      local.get $frame
    \\      local.get $code
    \\      call $accept-read
    \\    end
    \\  )
    \\  (func (export "[async-lift-name]") (type $async-run) (param $response i32) (result i32) (local $frame i32) (local $future-pair i64)
    \\    call $frame-alloc
    \\    local.tee $frame
    \\    call $context-set-0
    \\    local.get $frame
    \\    call $waitable-set-new
    \\    i32.store
    \\    call $future-new
    \\    local.set $future-pair
    \\    local.get $response
    \\    local.get $future-pair
    \\    i32.wrap_i64
    \\    local.get $frame
    \\    i32.const 32
    \\    i32.add
    \\    call $consume-body
    \\    local.get $frame
    \\    i32.const 48
    \\    i32.add
    \\    i32.const 0
    \\    i32.store
    \\    local.get $future-pair
    \\    i64.const 32
    \\    i64.shr_u
    \\    i32.wrap_i64
    \\    local.get $frame
    \\    i32.const 48
    \\    i32.add
    \\    call $future-write
    \\    drop
    \\    local.get $future-pair
    \\    i64.const 32
    \\    i64.shr_u
    \\    i32.wrap_i64
    \\    call $future-drop-writable
    \\    local.get $frame
    \\    i32.const 4
    \\    i32.add
    \\    local.get $frame
    \\    i32.const 32
    \\    i32.add
    \\    i32.load
    \\    i32.store
    \\    local.get $frame
    \\    i32.const 8
    \\    i32.add
    \\    local.get $frame
    \\    i32.const 36
    \\    i32.add
    \\    i32.load
    \\    i32.store
    \\    ;; [stream-read-count] [stream-read-count-value]
    \\    ;; [stream-read-index-offset] 20
    \\    local.get $frame
    \\    i32.const 20
    \\    i32.add
    \\    i32.const 0
    \\    i32.store
    \\    local.get $frame
    \\    call $start-read
    \\  )
    \\  (func (export "[callback-async-lift-name]") (type $async-run-callback) (param $event i32) (param $index i32) (param $payload i32) (result i32) (local $frame i32)
    \\    call $context-get-0
    \\    local.set $frame
    \\    local.get $event
    \\    i32.const 2
    \\    i32.eq
    \\    if (result i32)
    \\      local.get $frame
    \\      local.get $payload
    \\      call $accept-read
    \\    else
    \\[future-event-handler]
    \\    end
    \\  )
    \\  (func (export "_initialize") (type $initialize))
    \\)
;

const http_payload_cancel_core_wat =
    \\(module
    \\  (type $async-lower-send (func (param i32 i32) (result i32)))
    \\  (type $resource-drop (func (param i32)))
    \\  (type $task-return (func))
    \\  (type $root-noargs (func))
    \\  (type $root-new (func (result i32)))
    \\  (type $root-wait (func (param i32 i32) (result i32)))
    \\  (type $root-join (func (param i32 i32)))
    \\  (type $root-cancel (func (param i32) (result i32)))
    \\  (type $async-run (func (param i32) (result i32)))
    \\  (type $async-run-callback (func (param i32 i32 i32) (result i32)))
    \\  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
    \\  (import "wasi:http/client@0.3.0-rc-2025-09-16" "[async-lower]send"
    \\    (func $send (type $async-lower-send)))
    \\  (import "wasi:http/types@0.3.0-rc-2025-09-16" "[resource-drop]request"
    \\    (func $drop-request (type $resource-drop)))
    \\  (import "wasi:http/types@0.3.0-rc-2025-09-16" "[resource-drop]response"
    \\    (func $drop-response (type $resource-drop)))
    \\  (import "[export]$root" "[task-cancel]" (func $task-cancel (type $root-noargs)))
    \\  (import "$root" "[backpressure-inc]" (func $backpressure-inc (type $root-noargs)))
    \\  (import "$root" "[backpressure-dec]" (func $backpressure-dec (type $root-noargs)))
    \\  (import "$root" "[waitable-set-new]" (func $waitable-set-new (type $root-new)))
    \\  (import "$root" "[waitable-set-wait]" (func $waitable-set-wait (type $root-wait)))
    \\  (import "$root" "[waitable-set-poll]" (func $waitable-set-poll (type $root-wait)))
    \\  (import "$root" "[waitable-set-drop]" (func $waitable-set-drop (type $resource-drop)))
    \\  (import "$root" "[waitable-join]" (func $waitable-join (type $root-join)))
    \\  (import "$root" "[thread-yield]" (func $thread-yield (type $root-new)))
    \\  (import "$root" "[subtask-drop]" (func $subtask-drop (type $resource-drop)))
    \\  (import "$root" "[subtask-cancel]" (func $subtask-cancel (type $root-cancel)))
    \\  (import "[export]$root" "[task-return]cancel" (func $task-return (type $task-return)))
    \\  (memory (export "memory") 1)
    \\  (global $cabi-payload-state (mut i32) (i32.const 0))
    \\  (global $cabi-payload-len (mut i32) (i32.const 0))
    \\  ;; One canonical string can occupy [128, 65536) at a time. An exact
    \\  ;; release returns this private slot to idle for a later sequential call.
    \\  (func $cabi-realloc (type $cabi-realloc)
    \\    (param $old i32) (param $old-size i32) (param $align i32) (param $size i32) (result i32)
    \\    local.get $old
    \\    i32.eqz
    \\    if (result i32)
    \\      local.get $old-size
    \\      i32.eqz
    \\      if else unreachable end
    \\      local.get $align
    \\      i32.const 1
    \\      i32.ne
    \\      if unreachable end
    \\      local.get $size
    \\      i32.eqz
    \\      if unreachable end
    \\      local.get $size
    \\      i32.const 65408
    \\      i32.gt_u
    \\      if unreachable end
    \\      global.get $cabi-payload-state
    \\      i32.eqz
    \\      if else unreachable end
    \\      local.get $size
    \\      global.set $cabi-payload-len
    \\      i32.const 1
    \\      global.set $cabi-payload-state
    \\      i32.const 128
    \\    else
    \\      local.get $old
    \\      i32.const 128
    \\      i32.ne
    \\      if unreachable end
    \\      local.get $old-size
    \\      global.get $cabi-payload-len
    \\      i32.ne
    \\      if unreachable end
    \\      local.get $align
    \\      i32.const 1
    \\      i32.ne
    \\      if unreachable end
    \\      local.get $size
    \\      i32.eqz
    \\      if else unreachable end
    \\      global.get $cabi-payload-state
    \\      i32.const 1
    \\      i32.ne
    \\      if unreachable end
    \\      i32.const 0
    \\      global.set $cabi-payload-len
    \\      i32.const 0
    \\      global.set $cabi-payload-state
    \\      i32.const 0
    \\    end
    \\  )
    \\  (func $discard-canonical-string (param $ptr i32) (param $len i32)
    \\    local.get $len
    \\    i32.eqz
    \\    if unreachable end
    \\    local.get $ptr
    \\    local.get $len
    \\    i32.const 1
    \\    i32.const 0
    \\    call $cabi-realloc
    \\    drop
    \\  )
    \\  (func $validate-optional-discriminant (param $discriminant i32)
    \\    local.get $discriminant
    \\    i32.const 1
    \\    i32.gt_u
    \\    if unreachable end
    \\  )
    \\  (func (export "[async-lift]cancel") (type $async-run)
    \\    (local $subtask i32)
    \\    (local $error-tag i32)
    \\    (local $optional-tag i32)
    \\    local.get 0
    \\    ;; [http-payload-cancel] canonical result area [64, 128)
    \\    i32.const 64
    \\    call $send
    \\    local.set $subtask
    \\    local.get $subtask
    \\    i32.const 2
    \\    i32.eq
    \\    if (result i32)
    \\      ;; [http-payload-cancel] immediate terminal
    \\      i32.const 64
    \\      i32.load
    \\      if
    \\        i32.const 64
    \\        i32.const 8
    \\        i32.add
    \\        i32.load
    \\        local.tee $error-tag
    \\        i32.eqz
    \\        if
    \\          ;; [http-payload-cancel] immediate dns-timeout
    \\        else
    \\          local.get $error-tag
    \\          i32.const 38
    \\          i32.eq
    \\          if
    \\            ;; [http-payload-cancel] immediate internal-error discard
    \\            i32.const 80
    \\            i32.load
    \\            local.tee $optional-tag
    \\            call $validate-optional-discriminant
    \\            local.get $optional-tag
    \\            if
    \\              i32.const 84
    \\              i32.load
    \\              i32.const 88
    \\              i32.load
    \\              call $discard-canonical-string
    \\            end
    \\          else
    \\            local.get $error-tag
    \\            i32.const 1
    \\            i32.ne
    \\            if unreachable end
    \\            ;; [http-payload-cancel] immediate dns-error rcode discard
    \\            i32.const 92
    \\            i32.load8_u
    \\            i32.const 1
    \\            i32.gt_u
    \\            if unreachable end
    \\            i32.const 80
    \\            i32.load
    \\            local.tee $optional-tag
    \\            call $validate-optional-discriminant
    \\            local.get $optional-tag
    \\            if
    \\              i32.const 84
    \\              i32.load
    \\              i32.const 88
    \\              i32.load
    \\              call $discard-canonical-string
    \\            end
    \\          end
    \\        end
    \\      else
    \\        ;; [http-payload-cancel] immediate ok response
    \\        i32.const 64
    \\        i32.const 8
    \\        i32.add
    \\        i32.load
    \\        call $drop-response
    \\      end
    \\      call $task-return
    \\      i32.const 0
    \\    else
    \\      local.get $subtask
    \\      i32.const 4
    \\      i32.shr_u
    \\      call $subtask-cancel
    \\      i32.const 4
    \\      i32.ne
    \\      if unreachable end
    \\      ;; [http-payload-cancel] pending terminal
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
    \\  (export "cabi_realloc" (func $cabi-realloc))
    \\  (func (export "_initialize") (type $root-noargs))
    \\)
;

const http_service_core_wat =
    \\(module
    \\  (type $async-lower-send (func (param i32 i32) (result i32)))
    \\  (type $resource-drop (func (param i32)))
    \\  (type $async-handler (func (param i32) (result i32)))
    \\  (type $async-handler-callback (func (param i32 i32 i32) (result i32)))
    \\  (type $root-noargs (func))
    \\  (type $root-new (func (result i32)))
    \\  (type $root-wait (func (param i32 i32) (result i32)))
    \\  (type $root-join (func (param i32 i32)))
    \\  (type $root-cancel (func (param i32) (result i32)))
    \\  (type $task-return (func (param [task-return-params])))
    \\  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
    \\  (import "wasi:http/client@0.3.0-rc-2025-09-16" "[async-lower]send" (func $send (type $async-lower-send)))
    \\  (import "wasi:http/types@0.3.0-rc-2025-09-16" "[resource-drop]request" (func $drop-request (type $resource-drop)))
    \\  (import "wasi:http/types@0.3.0-rc-2025-09-16" "[resource-drop]response" (func $drop-response (type $resource-drop)))
    \\  (import "[export]$root" "[task-cancel]" (func $task-cancel (type $root-noargs)))
    \\  (import "$root" "[backpressure-inc]" (func $backpressure-inc (type $root-noargs)))
    \\  (import "$root" "[backpressure-dec]" (func $backpressure-dec (type $root-noargs)))
    \\  (import "$root" "[waitable-set-new]" (func $waitable-set-new (type $root-new)))
    \\  (import "$root" "[waitable-set-wait]" (func $waitable-set-wait (type $root-wait)))
    \\  (import "$root" "[waitable-set-poll]" (func $waitable-set-poll (type $root-wait)))
    \\  (import "$root" "[waitable-set-drop]" (func $waitable-set-drop (type $resource-drop)))
    \\  (import "$root" "[waitable-join]" (func $waitable-join (type $root-join)))
    \\  (import "$root" "[thread-yield]" (func $thread-yield (type $root-new)))
    \\  (import "$root" "[subtask-drop]" (func $subtask-drop (type $resource-drop)))
    \\  (import "$root" "[subtask-cancel]" (func $subtask-cancel (type $root-cancel)))
    \\  (import "$root" "[context-get-0]" (func $context-get-0 (type $root-new)))
    \\  (import "$root" "[context-set-0]" (func $context-set-0 (type $resource-drop)))
    \\  (import "[export]wasi:http/handler@0.3.0-rc-2025-09-16" "[task-return]handle" (func $task-return (type $task-return)))
    \\  (memory (export "memory") 1)
    \\[gc-frame-runtime]
    \\  ;; Result<response, error-code> occupies 40 bytes in canonical memory.
    \\  (func $result-buffer-for-handle (param $handle i32) (result i32)
    \\    (local $required-bytes i32)
    \\    i64.const 64
    \\    call $async-byte-budget-reserve
    \\    i32.eqz
    \\    if unreachable end
    \\    local.get $handle
    \\    i32.const 6
    \\    i32.shl
    \\    i32.const 64
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
    \\        i64.const 64
    \\        call $async-byte-budget-release
    \\        unreachable
    \\      end
    \\    end
    \\    local.get $handle
    \\    i32.const 6
    \\    i32.shl
    \\  )
    \\  (func $canonical-buffer-release
    \\    i64.const 64
    \\    call $async-byte-budget-release
    \\  )
    \\  (func (export "[async-lift]wasi:http/handler@0.3.0-rc-2025-09-16#handle") (type $async-handler) (param $request i32) (result i32) (local $frame i32) (local $frame-ref (ref $async-frame)) (local $subtask i32) (local $error-tag i32)
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
    \\[immediate-completion]
    \\  )
    \\  (func (export "[callback][async-lift]wasi:http/handler@0.3.0-rc-2025-09-16#handle") (type $async-handler-callback) (param $event i32) (param $index i32) (param $payload i32) (result i32) (local $frame i32) (local $frame-ref (ref $async-frame)) (local $error-tag i32)
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
    \\      if
    \\        ;; [result:err]
    \\        local.get $frame-ref
    \\        struct.get $async-frame $slot-result-ptr
    \\        i32.const 8
    \\        i32.add
    \\        i32.load
    \\        local.set $error-tag
    \\[task-return-error-lowering]
    \\      else
    \\        ;; [result:ok]
    \\[task-return-ok-lowering]
    \\      end
    \\      call $canonical-buffer-release
    \\      i32.const 0
    \\      call $context-set-0
    \\      local.get $frame
    \\      call $frame-free
    \\      i32.const 0
    \\    else
    \\[body-future-event-handler]
    \\    end
    \\  )
    \\  (func (export "cabi_realloc") (type $cabi-realloc) unreachable)
    \\  (func (export "_initialize") (type $root-noargs))
    \\)
;

const http_service_component_wit =
    \\package wasi:http@0.3.0-rc-2025-09-16;
    \\
    \\interface client {
    \\  use types.{request, response, error-code};
    \\  send: async func(request: request) -> result<response, error-code>;
    \\}
    \\
    \\interface handler {
    \\  use types.{request, response, error-code};
    \\  handle: async func(request: request) -> result<response, error-code>;
    \\}
    \\
    \\world service {
    \\  import client;
    \\  export handler;
    \\}
;

const http_payload_cancel_component_wit =
    \\package do:http-payload-cancel@0.1.0;
    \\
    \\world http-payload-cancel {
    \\  import wasi:http/client@0.3.0-rc-2025-09-16;
    \\  use wasi:http/types@0.3.0-rc-2025-09-16.{request};
    \\  export cancel: async func(request: request);
    \\}
;

const http_client_probe_component_wit =
    \\package wasi:http@0.3.0-rc-2025-09-16;
    \\
    \\interface types {
    \\  variant error-code { dns-timeout }
    \\  resource request {}
    \\  resource response {}
    \\}
    \\
    \\interface client {
    \\  use types.{request, response, error-code};
    \\  send: async func(request: request) -> result<response, error-code>;
    \\}
    \\
    \\interface probe {
    \\  use types.{request, response, error-code};
    \\  run: async func(request: request) -> result<response, error-code>;
    \\}
    \\
    \\world http-client-probe {
    \\  import client;
    \\  export probe;
    \\}
;

const http_response_body_probe_component_wit =
    \\package wasi:http@0.3.0-rc-2025-09-16;
    \\
    \\interface probe {
    \\  use types.{response};
    \\  run: async func(response: response);
    \\}
    \\
    \\world http-response-body-probe {
    \\  import types;
    \\  export probe;
    \\}
;

const http_request_send_imports =
    \\  (type $fields-new (func (result i32)))
    \\  (type $future-new (func (result i64)))
    \\  (type $future-write (func (param i32 i32) (result i32)))
    \\  (type $future-drop (func (param i32)))
    \\  (type $request-new (func (param i32 i32 i32 i32 i32 i32 i32)))
    \\  (import "[types-module]" "[constructor]fields" (func $fields-new (type $fields-new)))
    \\  (import "[types-module]" "[request-new-name]" (func $request-new (type $request-new)))
    \\  (import "[types-module]" "[future-new-name]" (func $future-new (type $future-new)))
    \\  (import "[types-module]" "[future-write-name]" (func $future-write (type $future-write)))
    \\  (import "[types-module]" "[future-drop-writable-name]" (func $future-drop-writable (type $future-drop)))
    \\  (import "[types-module]" "[transmission-drop-name]" (func $transmission-drop (type $future-drop)))
;

const http_request_constructor_helper_wat =
    \\  (func $construct-request (result i32) (local $future-pair i64) (local $headers i32)
    \\    call $fields-new
    \\    local.set $headers
    \\    call $future-new
    \\    local.set $future-pair
    \\    i32.const 80
    \\    i32.const 0
    \\    i32.store
    \\    i32.const 84
    \\    i32.const 0
    \\    i32.store
    \\    local.get $headers
    \\    i32.const 0
    \\    i32.const 0
    \\    local.get $future-pair
    \\    i32.wrap_i64
    \\    i32.const 0
    \\    i32.const 0
    \\    i32.const 64
    \\    call $request-new
    \\    local.get $future-pair
    \\    i64.const 32
    \\    i64.shr_u
    \\    i32.wrap_i64
    \\    i32.const 80
    \\    call $future-write
    \\    drop
    \\    local.get $future-pair
    \\    i64.const 32
    \\    i64.shr_u
    \\    i32.wrap_i64
    \\    call $future-drop-writable
    \\    i32.const 68
    \\    i32.load
    \\    call $transmission-drop
    \\    i32.const 64
    \\    i32.load
    \\  )
;

const http_request_body_constructor_helper_wat =
    \\  (func $drop-body-completion (param $frame-ref (ref $async-frame))
    \\    local.get $frame-ref
    \\    struct.get $async-frame $slot-body-completion
    \\    call $body-completion-drop
    \\  )
    \\  (func $acquire-body (param $frame-ref (ref $async-frame))
    \\    local.get $frame-ref
    \\    struct.get $async-frame $slot-result-ptr
    \\    call $body-acquire
    \\    local.get $frame-ref
    \\    local.get $frame-ref
    \\    struct.get $async-frame $slot-result-ptr
    \\    i32.const 4
    \\    i32.add
    \\    i32.load
    \\    struct.set $async-frame $slot-body-completion
    \\    local.get $frame-ref
    \\    local.get $frame-ref
    \\    struct.get $async-frame $slot-result-ptr
    \\    i32.const 48
    \\    i32.add
    \\    struct.set $async-frame $slot-body-completion-result
    \\  )
    \\[body-completion-functions]
    \\  (func $construct-request (param $frame-ref (ref $async-frame)) (result i32) (local $future-pair i64) (local $headers i32) (local $result-ptr i32) (local $reader i32)
    \\    local.get $frame-ref
    \\    struct.get $async-frame $slot-result-ptr
    \\    local.set $result-ptr
    \\[construct-acquire]
    \\    local.get $result-ptr
    \\    i32.load
    \\    local.set $reader
    \\    local.get $frame-ref
    \\    local.get $result-ptr
    \\    i32.const 4
    \\    i32.add
    \\    i32.load
    \\    struct.set $async-frame $slot-body-completion
    \\    local.get $frame-ref
    \\    local.get $result-ptr
    \\    i32.const 48
    \\    i32.add
    \\    struct.set $async-frame $slot-body-completion-result
    \\    call $fields-new
    \\    local.set $headers
    \\    call $future-new
    \\    local.set $future-pair
    \\    local.get $result-ptr
    \\    i32.const 16
    \\    i32.add
    \\    i32.const 0
    \\    i32.store
    \\    local.get $result-ptr
    \\    i32.const 20
    \\    i32.add
    \\    i32.const 0
    \\    i32.store
    \\    local.get $headers
    \\    i32.const 1
    \\    local.get $reader
    \\    local.get $future-pair
    \\    i32.wrap_i64
    \\    i32.const 0
    \\    i32.const 0
    \\    local.get $result-ptr
    \\    call $request-new
    \\    local.get $future-pair
    \\    i64.const 32
    \\    i64.shr_u
    \\    i32.wrap_i64
    \\    local.get $result-ptr
    \\    i32.const 16
    \\    i32.add
    \\    call $future-write
    \\    drop
    \\    local.get $future-pair
    \\    i64.const 32
    \\    i64.shr_u
    \\    i32.wrap_i64
    \\    call $future-drop-writable
    \\    local.get $result-ptr
    \\    i32.const 4
    \\    i32.add
    \\    i32.load
    \\    call $transmission-drop
    \\    local.get $frame-ref
    \\    local.get $result-ptr
    \\    i32.load
    \\    struct.set $async-frame $slot-body-request
    \\    local.get $result-ptr
    \\    i32.load
    \\  )
;

const http_request_body_producer_imports =
    \\  (type $producer-fields-new (func (result i32)))
    \\  (type $producer-future-new (func (result i64)))
    \\  (type $producer-future-write (func (param i32 i32) (result i32)))
    \\  (type $producer-future-drop (func (param i32)))
    \\  (type $producer-request-new (func (param i32 i32 i32 i32 i32 i32 i32)))
    \\  (type $producer-stream-new (func (result i64)))
    \\  (type $producer-stream-write (func (param i32 i32 i32) (result i32)))
    \\  (type $producer-stream-drop (func (param i32)))
    \\  (import "[types-module]" "[constructor]fields" (func $producer-fields-new (type $producer-fields-new)))
    \\  (import "[types-module]" "[request-new-name]" (func $producer-request-new (type $producer-request-new)))
    \\  (import "[types-module]" "[future-new-name]" (func $producer-future-new (type $producer-future-new)))
    \\  (import "[types-module]" "[future-write-name]" (func $producer-future-write (type $producer-future-write)))
    \\  (import "[types-module]" "[future-drop-writable-name]" (func $producer-future-drop-writable (type $producer-future-drop)))
    \\  (import "[types-module]" "[transmission-drop-name]" (func $producer-transmission-drop (type $producer-future-drop)))
    \\  (import "[stream-module]" "[stream-new-name]" (func $producer-stream-new (type $producer-stream-new)))
    \\  (import "[stream-module]" "[stream-write-name]" (func $producer-stream-write (type $producer-stream-write)))
    \\  (import "[stream-module]" "[stream-drop-readable-name]" (func $producer-stream-drop-readable (type $producer-stream-drop)))
    \\  (import "[stream-module]" "[stream-drop-writable-name]" (func $producer-stream-drop-writable (type $producer-stream-drop)))
;

const http_request_body_producer_helpers_wat =
    \\  (func $drop-producer-reader (param $frame-ref (ref $async-frame))
    \\    local.get $frame-ref
    \\    struct.get $async-frame $slot-producer-reader
    \\    i32.eqz
    \\    if
    \\    else
    \\      local.get $frame-ref
    \\      struct.get $async-frame $slot-producer-reader
    \\      call $producer-stream-drop-readable
    \\      local.get $frame-ref
    \\      i32.const 0
    \\      struct.set $async-frame $slot-producer-reader
    \\    end
    \\  )
    \\  (func $start-producer-send (param $frame-ref (ref $async-frame)) (local $subtask i32)
    \\    i32.const 64
    \\    i32.load
    \\    local.get $frame-ref
    \\    struct.get $async-frame $slot-result-ptr
    \\    call $send
    \\    local.set $subtask
    \\    local.get $frame-ref
    \\    local.get $subtask
    \\    struct.set $async-frame $slot-producer-subtask
    \\  )
    \\  (func $wait-producer-send (param $frame-ref (ref $async-frame)) (result i32)
    \\    local.get $frame-ref
    \\    struct.get $async-frame $slot-producer-subtask
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
    \\  )
    \\  (func $construct-producer-request (param $frame-ref (ref $async-frame)) (local $headers i32) (local $future-pair i64)
    \\    call $producer-fields-new
    \\    local.set $headers
    \\    call $producer-future-new
    \\    local.set $future-pair
    \\    i32.const 80
    \\    i32.const 0
    \\    i32.store
    \\    i32.const 84
    \\    i32.const 0
    \\    i32.store
    \\    local.get $headers
    \\    i32.const 1
    \\    local.get $frame-ref
    \\    struct.get $async-frame $slot-producer-reader
    \\    local.get $future-pair
    \\    i32.wrap_i64
    \\    i32.const 0
    \\    i32.const 0
    \\    i32.const 64
    \\    call $producer-request-new
    \\    local.get $future-pair
    \\    i64.const 32
    \\    i64.shr_u
    \\    i32.wrap_i64
    \\    i32.const 80
    \\    call $producer-future-write
    \\    drop
    \\    local.get $future-pair
    \\    i64.const 32
    \\    i64.shr_u
    \\    i32.wrap_i64
    \\    call $producer-future-drop-writable
    \\    i32.const 68
    \\    i32.load
    \\    call $producer-transmission-drop
    \\    local.get $frame-ref
    \\    i32.const 0
    \\    struct.set $async-frame $slot-producer-reader
    \\    local.get $frame-ref
    \\    call $start-producer-send
    \\  )
    \\  (func $start-producer-write (param $frame-ref (ref $async-frame)) (result i32) (local $status i32)
    \\    local.get $frame-ref
    \\    struct.get $async-frame $slot-producer-index
    \\    i32.const [producer-count]
    \\    i32.ge_u
    \\    if (result i32)
    \\      local.get $frame-ref
    \\      struct.get $async-frame $slot-producer-writer
    \\      call $producer-stream-drop-writable
    \\      local.get $frame-ref
    \\      i32.const 0
    \\      struct.set $async-frame $slot-producer-writer
    \\      local.get $frame-ref
    \\      call $wait-producer-send
    \\    else
    \\      local.get $frame-ref
    \\      struct.get $async-frame $slot-producer-writer
    \\      i32.const 512
    \\      local.get $frame-ref
    \\      struct.get $async-frame $slot-producer-index
    \\      i32.add
    \\      i32.const 1
    \\      call $producer-stream-write
    \\      local.tee $status
    \\      i32.const 15
    \\      i32.and
    \\      i32.eqz
    \\      if (result i32)
    \\        local.get $frame-ref
    \\        local.get $frame-ref
    \\        struct.get $async-frame $slot-producer-index
    \\        i32.const 1
    \\        i32.add
    \\        struct.set $async-frame $slot-producer-index
    \\        local.get $frame-ref
    \\        call $start-producer-write
    \\      else
    \\        local.get $status
    \\        i32.const -1
    \\        i32.eq
    \\        if (result i32)
    \\          local.get $frame-ref
    \\          struct.get $async-frame $slot-producer-writer
    \\          local.get $frame-ref
    \\          struct.get $async-frame $waitable-set
    \\          call $waitable-join
    \\          local.get $frame-ref
    \\          struct.get $async-frame $waitable-set
    \\          i32.const 4
    \\          i32.shl
    \\          i32.const 2
    \\          i32.or
    \\        else
    \\          unreachable
    \\        end
    \\      end
    \\    end
    \\  )
    \\  (func $start-producer (param $frame-ref (ref $async-frame)) (result i32) (local $pair i64)
    \\    call $producer-stream-new
    \\    local.set $pair
    \\    local.get $frame-ref
    \\    local.get $pair
    \\    i32.wrap_i64
    \\    struct.set $async-frame $slot-producer-reader
    \\    local.get $frame-ref
    \\    local.get $pair
    \\    i64.const 32
    \\    i64.shr_u
    \\    i32.wrap_i64
    \\    struct.set $async-frame $slot-producer-writer
    \\    local.get $frame-ref
    \\    i32.const 0
    \\    struct.set $async-frame $slot-producer-index
    \\    local.get $frame-ref
    \\    call $construct-producer-request
    \\    local.get $frame-ref
    \\    call $start-producer-write
    \\  )
    \\  (func $accept-producer-write (param $frame-ref (ref $async-frame)) (param $code i32) (result i32)
    \\    local.get $code
    \\    i32.const 15
    \\    i32.and
    \\    i32.eqz
    \\    if (result i32)
    \\      local.get $frame-ref
    \\      local.get $frame-ref
    \\      struct.get $async-frame $slot-producer-index
    \\      i32.const 1
    \\      i32.add
    \\      struct.set $async-frame $slot-producer-index
    \\      local.get $frame-ref
    \\      call $start-producer-write
    \\    else
    \\      unreachable
    \\    end
    \\  )
;

const http_request_body_producer_event_handler =
    \\      local.get $event
    \\      i32.const 3
    \\      i32.eq
    \\      if (result i32)
    \\        local.get $frame-ref
    \\        local.get $payload
    \\        call $accept-producer-write
    \\      else
    \\        unreachable
    \\      end
;

fn producer_frame_values(allocator: std.mem.Allocator) ![]u8 {
    return allocator.dupe(
        u8,
        "    i32.const 1\n" ++
            "    call $waitable-set-new\n" ++
            "    i32.const 0\n" ++
            "    i32.const 0\n" ++
            "    i32.const 0\n" ++
            "    i32.const 0\n" ++
            "    i32.const 0\n" ++
            "    i32.const 0\n" ++
            "    i32.const 0\n" ++
            "    struct.new $async-frame",
    );
}

fn render_producer_data(allocator: std.mem.Allocator, values: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    const digits = "0123456789abcdef";
    for (values) |value| {
        try out.append(allocator, '\\');
        try out.append(allocator, digits[value >> 4]);
        try out.append(allocator, digits[value & 0x0f]);
    }
    return out.toOwnedSlice(allocator);
}

const http_request_body_completion_await_functions =
    \\  (func $wait-on-body-completion (param $frame-ref (ref $async-frame)) (result i32)
    \\    local.get $frame-ref
    \\    struct.get $async-frame $slot-body-completion
    \\    local.get $frame-ref
    \\    struct.get $async-frame $waitable-set
    \\    call $waitable-join
    \\    local.get $frame-ref
    \\    struct.get $async-frame $waitable-set
    \\    i32.const 4
    \\    i32.shl
    \\    i32.const 2
    \\    i32.or
    \\  )
    \\  (func $start-send (param $frame-ref (ref $async-frame)) (result i32) (local $subtask i32)
    \\    local.get $frame-ref
    \\    struct.get $async-frame $slot-body-request
    \\    local.get $frame-ref
    \\    struct.get $async-frame $slot-result-ptr
    \\    call $send
    \\    local.set $subtask
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
    \\  )
    \\  (func $accept-body-completion (param $frame-ref (ref $async-frame)) (param $code i32) (result i32)
    \\    local.get $code
    \\    i32.const 0
    \\    i32.ne
    \\    if unreachable end
    \\    local.get $frame-ref
    \\    call $construct-request
    \\    drop
    \\    local.get $frame-ref
    \\    call $start-send
    \\  )
    \\  (func $start-body-completion (param $frame-ref (ref $async-frame)) (result i32) (local $code i32)
    \\    local.get $frame-ref
    \\    struct.get $async-frame $slot-body-completion
    \\    local.get $frame-ref
    \\    struct.get $async-frame $slot-body-completion-result
    \\    call $body-future-read
    \\    local.tee $code
    \\    i32.const -1
    \\    i32.eq
    \\    if (result i32)
    \\      local.get $frame-ref
    \\      call $wait-on-body-completion
    \\    else
    \\      local.get $frame-ref
    \\      local.get $code
    \\      call $accept-body-completion
    \\    end
    \\  )
    \\  (func $start-body-request (param $frame-ref (ref $async-frame)) (result i32)
    \\    local.get $frame-ref
    \\    call $acquire-body
    \\    local.get $frame-ref
    \\    call $start-body-completion
    \\  )
;

const http_request_empty_probe_component_wit =
    \\package wasi:http@0.3.0-rc-2025-09-16;
    \\
    \\interface types {
    \\  variant error-code { dns-timeout }
    \\  resource fields {
    \\    constructor();
    \\  }
    \\  resource request {
    \\    new: static func(
    \\      headers: fields,
    \\      contents: option<stream<u8>>,
    \\      trailers: future<result<option<fields>, error-code>>,
    \\      options: option<request-options>
    \\    ) -> tuple<request, future<result<_, error-code>>>;
    \\  }
    \\  request-new-payload: func(
    \\    headers: fields,
    \\    contents: option<stream<u8>>,
    \\    trailers: future<result<option<fields>, error-code>>,
    \\    options: option<request-options>
    \\  ) -> tuple<request, future<result<_, error-code>>>;
    \\  resource request-options {}
    \\}
    \\
    \\interface probe {
    \\  run: async func();
    \\}
    \\
    \\world http-request-probe {
    \\  import types;
    \\  export probe;
    \\}
;

const http_request_body_probe_component_wit =
    \\package wasi:http@0.3.0-rc-2025-09-16;
    \\
    \\interface types {
    \\  variant error-code { dns-timeout }
    \\  resource fields {
    \\    constructor();
    \\  }
    \\  resource request {
    \\    new: static func(
    \\      headers: fields,
    \\      contents: option<stream<u8>>,
    \\      trailers: future<result<option<fields>, error-code>>,
    \\      options: option<request-options>
    \\    ) -> tuple<request, future<result<_, error-code>>>;
    \\  }
    \\  resource request-options {}
    \\  resource response {}
    \\  request-new-payload: func(
    \\    headers: fields,
    \\    contents: option<stream<u8>>,
    \\    trailers: future<result<option<fields>, error-code>>,
    \\    options: option<request-options>
    \\  ) -> tuple<request, future<result<_, error-code>>>;
    \\}
    \\
    \\interface client {
    \\  use types.{request, response, error-code};
    \\  send: async func(request: request) -> result<response, error-code>;
    \\}
    \\
    \\interface probe {
    \\  use types.{response, error-code};
    \\  run: async func() -> result<response, error-code>;
    \\}
    \\
    \\world http-request-body-probe {
    \\  import types;
    \\  import client;
    \\  import wasi:cli/stdin@0.3.0-rc-2025-09-16;
    \\  export probe;
    \\}
;

const http_request_body_producer_component_wit =
    \\package wasi:http@0.3.0-rc-2025-09-16;
    \\
    \\interface types {
    \\  variant error-code { dns-timeout }
    \\  resource fields {
    \\    constructor();
    \\  }
    \\  resource request {
    \\    new: static func(
    \\      headers: fields,
    \\      contents: option<stream<u8>>,
    \\      trailers: future<result<option<fields>, error-code>>,
    \\      options: option<request-options>
    \\    ) -> tuple<request, future<result<_, error-code>>>;
    \\  }
    \\  request-new-payload: func(
    \\    headers: fields,
    \\    contents: option<stream<u8>>,
    \\    trailers: future<result<option<fields>, error-code>>,
    \\    options: option<request-options>
    \\  ) -> tuple<request, future<result<_, error-code>>>;
    \\  resource request-options {}
    \\  resource response {}
    \\}
    \\
    \\interface client {
    \\  use types.{request, response, error-code};
    \\  send: async func(request: request) -> result<response, error-code>;
    \\}
    \\
    \\interface probe {
    \\  use types.{response, error-code};
    \\  run: async func() -> result<response, error-code>;
    \\}
    \\
    \\world http-request-body-producer-probe {
    \\  import types;
    \\  import client;
    \\  import wasi:cli/stdout@0.3.0-rc-2025-09-16;
    \\  export probe;
    \\}
;

const http_request_send_probe_component_wit =
    \\package wasi:http@0.3.0-rc-2025-09-16;
    \\
    \\interface types {
    \\  resource fields {
    \\    constructor();
    \\  }
    \\  resource request {
    \\    new: static func(
    \\      headers: fields,
    \\      contents: option<stream<u8>>,
    \\      trailers: future<result<option<fields>, error-code>>,
    \\      options: option<request-options>
    \\    ) -> tuple<request, future<result<_, error-code>>>;
    \\  }
    \\  request-new-payload: func(
    \\    headers: fields,
    \\    contents: option<stream<u8>>,
    \\    trailers: future<result<option<fields>, error-code>>,
    \\    options: option<request-options>
    \\  ) -> tuple<request, future<result<_, error-code>>>;
    \\  resource request-options {}
    \\  resource response {}
    \\  variant error-code { dns-timeout }
    \\}
    \\
    \\interface client {
    \\  use types.{request, response, error-code};
    \\  send: async func(request: request) -> result<response, error-code>;
    \\}
    \\
    \\interface probe {
    \\  use types.{response, error-code};
    \\  run: async func() -> result<response, error-code>;
    \\}
    \\
    \\world http-request-empty-service-probe {
    \\  import types;
    \\  import client;
    \\  export probe;
    \\}
;

const http_request_empty_core_wat =
    \\(module
    \\  (type $fields-new (func (result i32)))
    \\  (type $future-new (func (result i64)))
    \\  (type $future-write (func (param i32 i32) (result i32)))
    \\  (type $future-drop (func (param i32)))
    \\  (type $request-new (func (param i32 i32 i32 i32 i32 i32 i32)))
    \\  (type $async-run (func (result i32)))
    \\  (type $async-run-callback (func (param i32 i32 i32) (result i32)))
    \\  (type $task-return (func))
    \\  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
    \\  (type $initialize (func))
    \\  (import "[fields-module]" "[constructor]fields" (func $fields-new (type $fields-new)))
    \\  (import "[request-new-module]" "[request-new-name]" (func $request-new (type $request-new)))
    \\  (import "[request-new-module]" "[future-new-name]" (func $future-new (type $future-new)))
    \\  (import "[request-new-module]" "[future-write-name]" (func $future-write (type $future-write)))
    \\  (import "[request-new-module]" "[future-drop-writable-name]" (func $future-drop-writable (type $future-drop)))
    \\  (import "[request-new-module]" "[transmission-drop-name]" (func $transmission-drop (type $future-drop)))
    \\  (import "[fields-module]" "[resource-drop]request" (func $request-drop (type $future-drop)))
    \\  (import "[export][task-return-locator]" "[task-return]run" (func $task-return (type $task-return)))
    \\  (memory (export "memory") 1)
    \\[cabi-budget-runtime]
    \\  (func (export "[async-lift-name]") (type $async-run) (local $future-pair i64) (local $headers i32)
    \\    call $fields-new
    \\    local.set $headers
    \\    call $future-new
    \\    local.set $future-pair
    \\    i32.const 80
    \\    i32.const 0
    \\    i32.store
    \\    i32.const 84
    \\    i32.const 0
    \\    i32.store
    \\    local.get $headers
    \\    i32.const 0
    \\    i32.const 0
    \\    local.get $future-pair
    \\    i32.wrap_i64
    \\    i32.const 0
    \\    i32.const 0
    \\    i32.const 64
    \\    call $request-new
    \\    local.get $future-pair
    \\    i64.const 32
    \\    i64.shr_u
    \\    i32.wrap_i64
    \\    i32.const 80
    \\    call $future-write
    \\    drop
    \\    local.get $future-pair
    \\    i64.const 32
    \\    i64.shr_u
    \\    i32.wrap_i64
    \\    call $future-drop-writable
    \\    i32.const 68
    \\    i32.load
    \\    call $transmission-drop
    \\    i32.const 64
    \\    i32.load
    \\    call $request-drop
    \\    call $task-return
    \\    i32.const 0
    \\  )
    \\  (func (export "[callback-async-lift-name]") (type $async-run-callback)
    \\    i32.const 0
    \\  )
    \\  (func (export "_initialize") (type $initialize))
    \\)
;

const http_response_status_core_wat =
    \\(module
    \\  (type $status (func (param i32) (result i32)))
    \\  (type $drop (func (param i32)))
    \\  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
    \\  (type $initialize (func))
    \\  (import "{s}" "{s}" (func $get-status-code (type $status)))
    \\  (import "wasi:http/types@0.3.0-rc-2025-09-16" "[resource-drop]response" (func $drop-response (type $drop)))
    \\  (memory (export "memory") 1)
    \\[cabi-budget-runtime]
    \\  (func $run (param $response i32) (result i32) (local $status i32)
    \\    local.get $response
    \\    call $get-status-code
    \\    local.set $status
    \\    local.get $response
    \\    call $drop-response
    \\    local.get $status
    \\  )
    \\  (export "run" (func $run))
    \\  (export "wasi:http/probe@0.3.0-rc-2025-09-16#run" (func $run))
    \\  (func $cabi-post-run (param i32))
    \\  (export "cabi_post_run" (func $cabi-post-run))
    \\  (export "cabi_post_wasi:http/probe@0.3.0-rc-2025-09-16#run" (func $cabi-post-run))
    \\  (func (export "_initialize") (type $initialize))
    \\)
;

const http_response_status_component_wit =
    \\package wasi:http@0.3.0-rc-2025-09-16;
    \\
    \\interface types {
    \\  resource response {
    \\    get-status-code: func() -> u16;
    \\  }
    \\}
    \\
    \\interface probe {
    \\  use types.{response};
    \\  run: func(response: own<response>) -> u16;
    \\}
    \\
    \\world http-status-probe {
    \\  import types;
    \\  export probe;
    \\}
;

test "HTTP service plan accepts an exact handler forwarding client send" {
    const source =
        \\send = @host_func("wasi:http/client@0.3.0-rc-2025-09-16", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
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
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    try std.testing.expect((try HttpServicePlan.analyze(tokens, registry)) != null);
}

test "HTTP service plan accepts an exact cancellation handler for a payload Result" {
    const source =
        \\send = @host_func("wasi:http/client@0.3.0-rc-2025-09-16", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
        \\HttpHeaders = @wasi_resource("http/types/fields", { .id i64 })
        \\HttpRequestOptions = @wasi_resource("http/types/request-options", { .id i64 })
        \\HttpRequest = @wasi_resource("http/types/request", { .id i64 })
        \\HttpResponse = @wasi_resource("http/types/response", { .id i64 })
        \\HttpError error = HttpFailure
        \\cancel_request(request HttpRequest) -> nil {
        \\    completion Future<Result<HttpResponse, HttpError>> = send(request)
        \\    @cancel(completion)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    try std.testing.expect((try HttpServicePlan.analyze(tokens, registry)) != null);
}

test "HTTP service plan accepts the checked-in service fixture" {
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "../examples/p3-runtime/http-service.do", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(source);
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    try std.testing.expect((try HttpServicePlan.analyze(tokens, registry)) != null);
}

test "HTTP client send plan lowers a direct async run" {
    const source =
        \\send = @host_func("wasi:http/client@0.3.0-rc-2025-09-16", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
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
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    try std.testing.expect((try HttpClientSendPlan.analyze(tokens, registry)) != null);
    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "world http-client-probe") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "run: async func(request: request)") != null);

    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[task-return]run") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lift]wasi:http/probe@0.3.0-rc-2025-09-16#run") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[callback][async-lift]wasi:http/probe@0.3.0-rc-2025-09-16#run") != null);
}

test "HTTP request constructor plan feeds the constructed request to client send" {
    const source =
        \\request_new = @host("wasi:http/types@0.3.0-rc-2025-09-16", "request.new", () -> Tuple<HttpRequest, Future<Result<nil, HttpError>>>)
        \\send = @host_func("wasi:http/client@0.3.0-rc-2025-09-16", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
        \\HttpHeaders = @wasi_resource("http/types/fields", { .id i64 })
        \\HttpRequestOptions = @wasi_resource("http/types/request-options", { .id i64 })
        \\HttpRequest = @wasi_resource("http/types/request", { .id i64 })
        \\HttpResponse = @wasi_resource("http/types/response", { .id i64 })
        \\HttpError error = HttpFailure
        \\async run() -> Result<HttpResponse, HttpError> {
        \\    handles Tuple<HttpRequest, Future<Result<nil, HttpError>>> = request_new()
        \\    request HttpRequest = @get(handles, 0)
        \\    pending Future<Result<HttpResponse, HttpError>> = send(request)
        \\    return await(pending)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    try std.testing.expect((try HttpRequestSendPlan.analyze(tokens, registry)) != null);

    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $construct-request") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $send") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[future-drop-writable-1]request-new-payload") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lift]wasi:http/probe@0.3.0-rc-2025-09-16#run") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[body-future-event-handler]") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.get $frame-ref\n        struct.get $async-frame $waitable-set\n        i32.const 4\n        i32.shl\n        i32.const 2\n        i32.or") != null);
}

test "HTTP response body plan accepts the pinned consume-body acquisition" {
    const source =
        \\consume_body = @host("wasi:http/types@0.3.0-rc-2025-09-16", "response.consume-body", (HttpResponse) -> Tuple<Stream<u8>, Future<Result<option<trailers>, HttpError>>>)
        \\HttpResponse = @wasi_resource("http/types/response", { .id i64 })
        \\HttpError error = HttpFailure
        \\
        \\async run(response HttpResponse) -> nil {
        \\    _ = consume_body(response)
        \\}
        \\
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    try std.testing.expect((try HttpResponseBodyPlan.analyze(tokens, registry)) != null);
}

test "HTTP response body plan accepts one stream read" {
    const source =
        \\consume_body = @host("wasi:http/types@0.3.0-rc-2025-09-16", "response.consume-body", (HttpResponse) -> Tuple<Stream<u8>, Future<Result<option<trailers>, HttpError>>>)
        \\HttpResponse = @wasi_resource("http/types/response", { .id i64 })
        \\HttpError error = HttpFailure
        \\
        \\async run(response HttpResponse) -> nil {
        \\    handles Tuple<Stream<u8>, Future<Result<option<trailers>, HttpError>>> = consume_body(response)
        \\    reader Stream<u8> = @get(handles, 0)
        \\    completion Future<Result<option<trailers>, HttpError>> = @get(handles, 1)
        \\    pending Future<Result<u8, nil>> = @next(reader)
        \\    item Result<u8, nil> = await(pending)
        \\    _ = item
        \\    @cancel(completion)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    const plan = (try HttpResponseBodyPlan.analyze(tokens, registry)).?;
    try std.testing.expectEqual(@as(usize, 1), plan.read_count);
    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[stream-read-name]") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[stream-eof] Err(nil)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "stream-read") != null);
}

test "HTTP response body plan accepts two stream reads" {
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "../examples/p3-runtime/http-response-consume-body-two-read.do", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(source);
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = (try HttpResponseBodyPlan.analyze(tokens, registry)).?;
    try std.testing.expectEqual(@as(usize, 2), plan.read_count);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[stream-read-count] 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[stream-read-index-offset] 20") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 2\n    i32.eq") != null);
}

test "HTTP response body plan accepts the bounded third stream read" {
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "../examples/p3-runtime/http-response-consume-body-three-read.do", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(source);
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = (try HttpResponseBodyPlan.analyze(tokens, registry)).?;
    try std.testing.expectEqual(@as(usize, 3), plan.read_count);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[stream-read-count] 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 3\n    i32.eq") != null);
}

test "HTTP response body plan rejects a fourth stream read" {
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "../examples/p3-runtime/http-response-consume-body-four-read.do", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(source);
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    try std.testing.expect((try HttpResponseBodyPlan.analyze(tokens, registry)) == null);
}

test "HTTP response body plan accepts awaiting the trailers future" {
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "../examples/p3-runtime/http-response-consume-body-await-trailers.do", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(source);
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = try HttpResponseBodyPlan.analyze(tokens, registry);
    try std.testing.expect(plan != null);
    try std.testing.expect(plan.?.await_completion);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lower][future-read-2]consume-body-payload") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 24") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $accept-trailers") != null);
}

test "HTTP request constructor plan emits the empty request lifecycle" {
    const source =
        \\request_new = @host("wasi:http/types@0.3.0-rc-2025-09-16", "request.new", () -> Tuple<HttpRequest, Future<Result<nil, HttpError>>>)
        \\HttpHeaders = @wasi_resource("http/types/fields", { .id i64 })
        \\HttpRequestOptions = @wasi_resource("http/types/request-options", { .id i64 })
        \\HttpRequest = @wasi_resource("http/types/request", { .id i64 })
        \\HttpResponse = @wasi_resource("http/types/response", { .id i64 })
        \\HttpError error = HttpFailure
        \\async run() -> nil {
        \\    handles Tuple<HttpRequest, Future<Result<nil, HttpError>>> = request_new()
        \\    _ = handles
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    try std.testing.expect((try HttpRequestConstructorPlan.analyze(tokens, registry)) != null);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[constructor]fields") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[future-new-1]request-new-payload") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[future-write-1]request-new-payload") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[future-drop-writable-1]request-new-payload") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[static]request.new") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[resource-drop]request") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $async-byte-budget-reserve") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $async-byte-budget-release") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "memory.grow") != null);
}

test "HTTP request body plan accepts one fixed stream source" {
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "../examples/p3-runtime/http-request-body.do", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(source);
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const plan = try HttpRequestBodyPlan.analyze(tokens, registry);
    try std.testing.expect(plan != null);
    try std.testing.expectEqualStrings("reader", plan.?.body_reader_name);
    try std.testing.expectEqualStrings("source_done", plan.?.body_completion_name);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(import \"wasi:cli/stdin@0.3.0-rc-2025-09-16\" \"read-via-stream\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 1\n    local.get $reader") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[future-drop-readable-1]read-via-stream") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $drop-body-completion") != null);
}

test "HTTP request body producer plan rejects writes before request send" {
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "../examples/p3-runtime/http-request-body-producer.do", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(source);
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    try std.testing.expect((try HttpRequestBodyProducerPlan.analyze(tokens, registry)) == null);
}

test "HTTP request body producer plan accepts request send before guest writes" {
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "../examples/p3-runtime/http-request-body-producer-send-first.do", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(source);
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = try HttpRequestBodyProducerPlan.analyze(tokens, registry);
    try std.testing.expect(plan != null);
    try std.testing.expectEqual(@as(usize, 2), plan.?.write_count);
}

test "HTTP request body producer plan rejects capacity other than one" {
    var source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "../examples/p3-runtime/http-request-body-producer-send-first.do", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(source);
    const marker = "new_stream<u8>(1)";
    const marker_start = std.mem.indexOf(u8, source, marker) orelse return error.TestUnexpectedResult;
    source[marker_start + marker.len - 2] = '2';
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    try std.testing.expect((try HttpRequestBodyProducerPlan.analyze(tokens, registry)) == null);
}

test "HTTP request body producer plan rejects non-literal write values" {
    var source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "../examples/p3-runtime/http-request-body-producer-send-first.do", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(source);
    const marker = "writer(second)";
    const marker_start = std.mem.indexOf(u8, source, marker) orelse return error.TestUnexpectedResult;
    source[marker_start + marker.len - 6] = 'x';
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    try std.testing.expect((try HttpRequestBodyProducerPlan.analyze(tokens, registry)) == null);
}

test "HTTP request body producer plan rejects a spoofed CLI stdout stream descriptor" {
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "../examples/p3-runtime/http-request-body-producer.do", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(source);
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    var index: usize = 0;
    while (index < registry.descriptors.len and
        (!std.mem.eql(u8, registry.descriptors[index].locator, cli_stdout_locator) or
            !std.mem.eql(u8, registry.descriptors[index].member, cli_stdout_write_member))) : (index += 1)
    {}
    try std.testing.expect(index < registry.descriptors.len);

    const original_module = registry.descriptors[index].canonical.async_import_module;
    registry.descriptors[index].canonical.async_import_module = "do:spoofed-stream@0.1.0";
    defer registry.descriptors[index].canonical.async_import_module = original_module;
    try std.testing.expect((try HttpRequestBodyProducerPlan.analyze(tokens, registry)) == null);
}

test "HTTP request body plan rejects a non-pinned stream source" {
    const source =
        \\probe_read = @host_func("do:stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, ProbeError>>>)
        \\request_new = @host("wasi:http/types@0.3.0-rc-2025-09-16", "request.new", (Stream<u8>) -> Tuple<HttpRequest, Future<Result<nil, HttpError>>>)
        \\send = @host_func("wasi:http/client@0.3.0-rc-2025-09-16", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
        \\HttpHeaders = @wasi_resource("http/types/fields", { .id i64 })
        \\HttpRequestOptions = @wasi_resource("http/types/request-options", { .id i64 })
        \\HttpRequest = @wasi_resource("http/types/request", { .id i64 })
        \\HttpResponse = @wasi_resource("http/types/response", { .id i64 })
        \\ProbeError error = Io | IllegalByteSequence | Pipe
        \\HttpError error = HttpFailure
        \\async run() -> Result<HttpResponse, HttpError> {
        \\    source Tuple<Stream<u8>, Future<Result<nil, ProbeError>>> = probe_read()
        \\    reader Stream<u8> = @get(source, 0)
        \\    source_done Future<Result<nil, ProbeError>> = @get(source, 1)
        \\    handles Tuple<HttpRequest, Future<Result<nil, HttpError>>> = request_new(reader)
        \\    request HttpRequest = @get(handles, 0)
        \\    pending Future<Result<HttpResponse, HttpError>> = send(request)
        \\    result Result<HttpResponse, HttpError> = await(pending)
        \\    @cancel(source_done)
        \\    return result
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    try std.testing.expect((try HttpRequestBodyPlan.analyze(tokens, registry)) == null);
}

test "HTTP request body plan rejects a spoofed CLI stream canonical descriptor" {
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "../examples/p3-runtime/http-request-body.do", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(source);
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    var index: usize = 0;
    while (index < registry.descriptors.len and
        (!std.mem.eql(u8, registry.descriptors[index].locator, cli_stdin_locator) or
            !std.mem.eql(u8, registry.descriptors[index].member, cli_stdin_read_member))) : (index += 1)
    {}
    try std.testing.expect(index < registry.descriptors.len);
    const original_async_import_module = registry.descriptors[index].canonical.async_import_module;
    registry.descriptors[index].canonical.async_import_module = "do:spoofed-stream@0.1.0";
    defer registry.descriptors[index].canonical.async_import_module = original_async_import_module;

    try std.testing.expect((try HttpRequestBodyPlan.analyze(tokens, registry)) == null);
}

test "HTTP request body plan accepts serialized source completion await" {
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "../examples/p3-runtime/http-request-body-await-completion.do", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(source);
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = try HttpRequestBodyPlan.analyze(tokens, registry);
    try std.testing.expect(plan != null);
    try std.testing.expect(plan.?.await_body_completion);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lower][future-read-1]read-via-stream") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $start-body-completion") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $start-body-request") != null);
}

test "HTTP response body emitter creates the input future with the pinned type indexes" {
    const source =
        \\consume_body = @host("wasi:http/types@0.3.0-rc-2025-09-16", "response.consume-body", (HttpResponse) -> Tuple<Stream<u8>, Future<Result<option<trailers>, HttpError>>>)
        \\HttpResponse = @wasi_resource("http/types/response", { .id i64 })
        \\HttpError error = HttpFailure
        \\async run(response HttpResponse) -> nil {
        \\    _ = consume_body(response)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[static]response.consume-body") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[future-new-0]consume-body-payload") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[future-write-0]consume-body-payload") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[stream-drop-readable-1]consume-body-payload") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[future-drop-readable-2]consume-body-payload") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lower][future-read-2]consume-body-payload") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(import \"wasi:http/types@0.3.0-rc-2025-09-16\" \"[future-new-0]consume-body-payload\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[stream-drop-readable-0]response.consume-body") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[future-drop-readable-1]response.consume-body") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $async-byte-budget-reserve") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $async-byte-budget-release") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "memory.grow") != null);
}

test "HTTP response status plan preserves a borrowed response and explicit drop" {
    const source =
        \\get_status = @host("wasi:http/types@0.3.0-rc-2025-09-16", "response.get-status-code", (HttpResponse) -> u16)
        \\drop_response = @host("wasi:http/types@0.3.0-rc-2025-09-16", "response.drop", (HttpResponse) -> nil)
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
    const plan = try HttpResponseStatusPlan.analyze(tokens);
    try std.testing.expect(plan != null);

    const wat = try emit_response_status_core_wat(std.testing.allocator);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "wasi:http/types@0.3.0-rc-2025-09-16") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[method]response.get-status-code") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[resource-drop]response") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $async-byte-budget-reserve") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $async-byte-budget-release") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "memory.grow") != null);
}

test "HTTP service emitter forwards the resource Result through the handler completion ABI" {
    const source =
        \\send = @host_func("wasi:http/client@0.3.0-rc-2025-09-16", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
        \\HttpHeaders = @wasi_resource("http/types/fields", { .id i64 })
        \\HttpRequestOptions = @wasi_resource("http/types/request-options", { .id i64 })
        \\HttpRequest = @wasi_resource("http/types/request", { .id i64 })
        \\HttpResponse = @wasi_resource("http/types/response", { .id i64 })
        \\HttpError error = HttpFailure
        \\async handle(request HttpRequest) -> Result<HttpResponse, HttpError> {
        \\    pending Future<Result<HttpResponse, HttpError>> = send(request)
        \\    replied Result<HttpResponse, HttpError> = await(pending)
        \\    return replied
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lift]wasi:http/handler@0.3.0-rc-2025-09-16#handle") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $task-return (func (param i32 i32 i32 i64 i32 i32 i32 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(field $slot-result-ptr (mut i32))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 32\n        i32.eq\n        if unreachable end") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; [result:err]\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; [result:ok]\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; [error-variant:internal-error]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 0\n        local.get $frame-ref\n        struct.get $async-frame $slot-result-ptr\n        i32.const 8") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; [canonical-buffer-bytes] 64") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func (export \"byte-budget-limit\") (param $limit i64) (result i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.const 64\n    call $async-byte-budget-reserve") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $canonical-buffer-release") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $canonical-buffer-release\n      i32.const 0\n      call $context-set-0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "global $frame-next") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[body-future-event-handler]") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.get $frame-ref\n        struct.get $async-frame $waitable-set\n        i32.const 4\n        i32.shl\n        i32.const 2\n        i32.or") != null);
}

test "HTTP service emitter completes an immediately returned send without joining a handle" {
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const descriptor = registry.find(http_locator, "send") orelse return error.TestUnexpectedResult;
    const wat = try emit_http_service_core_wat(std.testing.allocator, descriptor);
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "local.set $subtask\n" ++
        "    local.get $subtask\n" ++
        "    i32.const 2\n" ++
        "    i32.eq\n" ++
        "    if (result i32)") != null);
}

test "HTTP payload cancellation emitter uses the private nil terminal path" {
    const source =
        \\send = @host_func("wasi:http/client@0.3.0-rc-2025-09-16", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
        \\HttpHeaders = @wasi_resource("http/types/fields", { .id i64 })
        \\HttpRequestOptions = @wasi_resource("http/types/request-options", { .id i64 })
        \\HttpRequest = @wasi_resource("http/types/request", { .id i64 })
        \\HttpResponse = @wasi_resource("http/types/response", { .id i64 })
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
    try std.testing.expect(std.mem.indexOf(u8, wat, "[http-payload-cancel] pending terminal") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lower]send") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $subtask-cancel") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $subtask-drop") != null);
    const cancel_call = std.mem.indexOf(u8, wat, "call $subtask-cancel") orelse return error.TestUnexpectedResult;
    const drop_call = std.mem.indexOf(u8, wat, "call $subtask-drop") orelse return error.TestUnexpectedResult;
    try std.testing.expect(cancel_call < drop_call);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; [http-payload-cancel] canonical result area") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 64\n    call $send") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; [http-payload-cancel] immediate ok response") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; [http-payload-cancel] immediate ok response\n        i32.const 64\n        i32.const 8\n        i32.add\n        i32.load\n        call $drop-response") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; [http-payload-cancel] immediate dns-timeout") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; [http-payload-cancel] immediate dns-error rcode discard") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; [http-payload-cancel] immediate internal-error discard") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(global $cabi-payload-state (mut i32) (i32.const 0))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $discard-canonical-string (param $ptr i32) (param $len i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $validate-optional-discriminant (param $discriminant i32)") != null);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, wat, "call $discard-canonical-string"));
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $validate-optional-discriminant") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.get $discriminant\n    i32.const 1\n    i32.gt_u\n    if unreachable end") != null);
    const optional_string_branch = "local.get $optional-tag\n            if\n              i32.const 84\n              i32.load\n              i32.const 88\n              i32.load\n              call $discard-canonical-string";
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, wat, optional_string_branch));
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 80\n            i32.load\n            i32.const 84") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 92\n            i32.load8_u\n            i32.const 1\n            i32.gt_u\n            if unreachable end") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 0\n      global.set $cabi-payload-len\n      i32.const 0\n      global.set $cabi-payload-state\n      i32.const 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[task-return]cancel") != null);

    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "world http-payload-cancel") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "export cancel: async func(request: request);") != null);
}

test "HTTP service emitter derives task-return parameter types from the descriptor" {
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    var descriptor = registry.find(http_locator, "send") orelse return error.TestUnexpectedResult;
    const all_i32 = [_][]const u8{ "i32", "i32", "i32", "i32", "i32", "i32", "i32", "i32" };
    descriptor.canonical.completion_params = &all_i32;
    const wat = try emit_http_service_core_wat(std.testing.allocator, descriptor);
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $task-return (func (param i32 i32 i32 i32 i32 i32 i32 i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $task-return (func (param i32 i32 i32 i64") == null);
}

test "HTTP service emitter lowers the proven internal error payload" {
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const descriptor = registry.find(http_locator, "send") orelse return error.TestUnexpectedResult;
    const wat = try emit_http_service_core_wat(std.testing.allocator, descriptor);
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, ";; [error-variant:internal-error]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 16\n          i32.add\n          i32.load") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 38\n        i32.eq\n        if unreachable end") == null);
}

test "HTTP service emitter lowers the proven DNS error payload" {
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const descriptor = registry.find(http_locator, "send") orelse return error.TestUnexpectedResult;
    const wat = try emit_http_service_core_wat(std.testing.allocator, descriptor);
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, ";; [error-variant:DNS-error]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.load8_u") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 30\n          i32.add\n          i32.load16_u") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.load16_u") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 1\n        i32.eq\n        if unreachable end") == null);
}

test "HTTP service WIT sidecar preserves nominal resource identities" {
    const source =
        \\send = @host_func("wasi:http/client@0.3.0-rc-2025-09-16", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
        \\HttpHeaders = @wasi_resource("http/types/fields", { .id i64 })
        \\HttpRequestOptions = @wasi_resource("http/types/request-options", { .id i64 })
        \\HttpRequest = @wasi_resource("http/types/request", { .id i64 })
        \\HttpResponse = @wasi_resource("http/types/response", { .id i64 })
        \\HttpError error = HttpFailure
        \\async handle(request HttpRequest) -> Result<HttpResponse, HttpError> {
        \\    pending Future<Result<HttpResponse, HttpError>> = send(request)
        \\    return await(pending)
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "use types.{request, response, error-code};") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "world service") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "status u16") == null);
}

test "HTTP service plan rejects a non-handler async export" {
    const source =
        \\send = @host_func("wasi:http/client@0.3.0-rc-2025-09-16", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
        \\HttpHeaders = @wasi_resource("http/types/fields", { .id i64 })
        \\HttpRequestOptions = @wasi_resource("http/types/request-options", { .id i64 })
        \\HttpRequest = @wasi_resource("http/types/request", { .id i64 })
        \\HttpResponse = @wasi_resource("http/types/response", { .id i64 })
        \\async run(request HttpRequest) -> Result<HttpResponse, HttpError> {
        \\    pending Future<Result<HttpResponse, HttpError>> = send(request)
        \\    return await(pending)
        \\}
    ;
    try expect_no_http_service_plan(source);
}

test "HTTP service plan rejects a wrong response resource shell" {
    const source =
        \\send = @host_func("wasi:http/client@0.3.0-rc-2025-09-16", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
        \\HttpHeaders = @wasi_resource("http/types/fields", { .id i64 })
        \\HttpRequestOptions = @wasi_resource("http/types/request-options", { .id i64 })
        \\HttpRequest = @wasi_resource("http/types/request", { .id i64 })
        \\HttpResponse = @wasi_resource("http/types/not-response", { .id i64 })
        \\async handle(request HttpRequest) -> Result<HttpResponse, HttpError> {
        \\    pending Future<Result<HttpResponse, HttpError>> = send(request)
        \\    return await(pending)
        \\}
    ;
    try expect_no_http_service_plan(source);
}

test "HTTP service plan rejects an incomplete request resource graph" {
    const source =
        \\send = @host_func("wasi:http/client@0.3.0-rc-2025-09-16", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
        \\HttpRequest = @wasi_resource("http/types/request", { .id i64 })
        \\HttpResponse = @wasi_resource("http/types/response", { .id i64 })
        \\async handle(request HttpRequest) -> Result<HttpResponse, HttpError> {
        \\    pending Future<Result<HttpResponse, HttpError>> = send(request)
        \\    return await(pending)
        \\}
    ;
    try expect_no_http_service_plan(source);
}

test "HTTP service plan accepts an awaited Result binding that is directly returned" {
    const source =
        \\send = @host_func("wasi:http/client@0.3.0-rc-2025-09-16", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
        \\HttpHeaders = @wasi_resource("http/types/fields", { .id i64 })
        \\HttpRequestOptions = @wasi_resource("http/types/request-options", { .id i64 })
        \\HttpRequest = @wasi_resource("http/types/request", { .id i64 })
        \\HttpResponse = @wasi_resource("http/types/response", { .id i64 })
        \\async handle(request HttpRequest) -> Result<HttpResponse, HttpError> {
        \\    pending Future<Result<HttpResponse, HttpError>> = send(request)
        \\    replied Result<HttpResponse, HttpError> = await(pending)
        \\    return replied
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    try std.testing.expect((try HttpServicePlan.analyze(tokens, registry)) != null);
}

fn expect_no_http_service_plan(source: []const u8) !void {
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    try std.testing.expect((try HttpServicePlan.analyze(tokens, registry)) == null);
}
