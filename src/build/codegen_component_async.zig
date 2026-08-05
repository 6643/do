const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const codegen_component_resource_async = @import("codegen_component_resource_async.zig");
const codegen_component_cli_stream_stdin = @import("codegen_component_cli_stream_stdin.zig");
const codegen_component_stream_writer = @import("codegen_component_stream_writer.zig");
const codegen_component_wasi_filesystem_read_directory = @import("codegen_component_wasi_filesystem_read_directory.zig");
const codegen_component_record_stream = @import("codegen_component_record_stream.zig");
const codegen_component_record_resource_list_stream = @import("codegen_component_record_resource_list_stream.zig");
const codegen_component_variant_resource_stream = @import("codegen_component_variant_resource_stream.zig");
const codegen_component_wasi_http = @import("codegen_component_wasi_http.zig");
const codegen_component_cabi_realloc = @import("codegen_component_cabi_realloc.zig");
const component_async_plan = @import("codegen_component_async_plan.zig");
const codegen_p3_wait_for = @import("codegen_p3_wait_for.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");

pub const Target = enum {
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
    variant_resource_stream,
    stream_writer,
    stream_mirror,
    wasi_read_directory,
};

pub const StreamWriterQueue = codegen_component_stream_writer.StreamWriterQueue;
pub const StreamWriterLease = codegen_component_stream_writer.WriterLease;
pub const StreamWriterPushOutcome = codegen_component_stream_writer.PushOutcome;
pub const StreamWriterPopOutcome = codegen_component_stream_writer.PopOutcome;

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
    return switch (try target_for_tokens(allocator, tokens)) {
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

pub fn emit_component_wit(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]u8 {
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
    return switch (try target_for_tokens(allocator, tokens)) {
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
    };
}

pub fn target_for_tokens(allocator: std.mem.Allocator, tokens: []const lexer.Token) !Target {
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

    if (component_async_plan.StreamMirrorPlan.analyze(tokens, registry)) |_| {
        return .stream_mirror;
    } else |_| {}

    var target: ?Target = null;
    var idx: usize = 0;
    while (idx + 8 < tokens.len) : (idx += 1) {
        const binding = host_binding_at(tokens, idx) orelse continue;
        const descriptor = registry.find(binding.locator, binding.member) orelse continue;
        const shape = p3_async_manifest.lowering_shape(descriptor) orelse return error.UnsupportedP3AsyncComponent;
        const next: Target = switch (shape) {
            .stream_reader_acquire => if ((binding.kind == .host or binding.kind == .host_func) and stream_reader_signature_at(tokens, idx)) .stream_reader else return error.UnsupportedP3AsyncComponent,
            .record_stream_reader => if ((binding.kind == .host or binding.kind == .host_func) and record_stream_reader_signature_at(tokens, idx))
                .wasi_read_directory
            else if (binding.kind == .host or binding.kind == .host_func)
                try record_stream_target_for_tokens(tokens, registry)
            else
                return error.UnsupportedP3AsyncComponent,
            .record_resource_list_stream_reader => if ((binding.kind == .host or binding.kind == .host_func) and list_resource_stream_signature_at(tokens, idx))
                try list_resource_stream_target_for_tokens(tokens, registry)
            else
                return error.UnsupportedP3AsyncComponent,
            .variant_resource_stream_reader => if ((binding.kind == .host or binding.kind == .host_func) and variant_resource_stream_signature_at(tokens, idx))
                .variant_resource_stream
            else
                return error.UnsupportedP3AsyncComponent,
            .stream_writer => if (stream_writer_signature_at(tokens, idx)) .stream_writer else return error.UnsupportedP3AsyncComponent,
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
        .stream_reader_acquire => .stream_reader,
        .record_stream_reader => .wasi_read_directory,
        .record_resource_list_stream_reader => error.UnsupportedP3AsyncComponent,
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
    host,
    host_func,
};

const HostFuncBinding = struct {
    locator: []const u8,
    member: []const u8,
    kind: HostBindingKind,
};

fn host_binding_at(tokens: []const lexer.Token, idx: usize) ?HostFuncBinding {
    if (idx + 8 >= tokens.len or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or !tok_eq(tokens[idx + 2], "@") or !tok_eq(tokens[idx + 4], "(")) return null;
    const kind: HostBindingKind = if (tok_eq(tokens[idx + 3], "host")) .host else if (tok_eq(tokens[idx + 3], "host_func")) .host_func else return null;
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
        \\wait_for = @host_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
    ;
    const scalar_tokens = try lexer.tokenize(std.testing.allocator, scalar_source);
    defer std.testing.allocator.free(scalar_tokens);
    try std.testing.expectEqual(Target.scalar_unit, try target_for_tokens(std.testing.allocator, scalar_tokens));

    const resource_source =
        \\send = @host_func("do:resource-probe/http@0.1.0", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
    ;
    const resource_tokens = try lexer.tokenize(std.testing.allocator, resource_source);
    defer std.testing.allocator.free(resource_tokens);
    try std.testing.expectEqual(Target.resource_result_2word, try target_for_tokens(std.testing.allocator, resource_tokens));

    const cli_result_source =
        \\run = @host_func("wasi:cli@0.3.0", "run.run", () -> Result<nil, nil>)
    ;
    const cli_result_tokens = try lexer.tokenize(std.testing.allocator, cli_result_source);
    defer std.testing.allocator.free(cli_result_tokens);
    try std.testing.expectEqual(Target.unit_result_tag, try target_for_tokens(std.testing.allocator, cli_result_tokens));

    const scalar_result_source =
        \\result_run = @host_func("do:result-probe@0.1.0", "run", (i32) -> Result<i32, i32>)
    ;
    const scalar_result_tokens = try lexer.tokenize(std.testing.allocator, scalar_result_source);
    defer std.testing.allocator.free(scalar_result_tokens);
    try std.testing.expectEqual(Target.scalar_result, try target_for_tokens(std.testing.allocator, scalar_result_tokens));

    const writer_source =
        \\stdout_write = @host_func("wasi:cli/stdout@0.3.0-rc-2025-09-16", "write-via-stream", (StreamWriter<u8>) -> Result<nil, StdoutError>)
    ;
    const writer_tokens = try lexer.tokenize(std.testing.allocator, writer_source);
    defer std.testing.allocator.free(writer_tokens);
    try std.testing.expectEqual(Target.stream_writer, try target_for_tokens(std.testing.allocator, writer_tokens));
}

test "generic Component async target classifies the bounded stream mirror" {
    const source =
        \\probe_read = @host("do:stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, ProbeError>>>)
        \\sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
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
        \\send = @host_func("wasi:http/client@0.3.0-rc-2025-09-16", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectError(error.UnsupportedP3AsyncComponent, target_for_tokens(std.testing.allocator, tokens));
}

test "generic Component async target classifies the pinned CLI stdin stream acquisition" {
    const source =
        \\stdin_read = @host("wasi:cli/stdin@0.3.0-rc-2025-09-16", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, StdinError>>>)
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    const target = try target_for_tokens(std.testing.allocator, tokens);
    try std.testing.expectEqualStrings("stream_reader", @tagName(target));
}

test "generic Component async target classifies the pinned read-directory record stream" {
    const source =
        \\.host_read_directory = @host("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.read-directory", (Dir) -> Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>>)
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try std.testing.expectEqual(Target.wasi_read_directory, try target_for_tokens(std.testing.allocator, tokens));
}

test "generic Component async target rejects a non-pinned read-directory descriptor" {
    const source =
        \\.host_read_directory = @host("do:filesystem/types@0.3.0", "descriptor.read-directory", (Dir) -> Tuple<Stream<DirectoryEntry>, Future<Result<nil, DirectoryError>>>)
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    try std.testing.expectError(error.UnsupportedP3AsyncComponent, target_for_tokens(std.testing.allocator, tokens));
}

test "generic Component async target classifies a descriptor-owned stream reader" {
    const source =
        \\probe_read = @host("do:stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, ProbeError>>>)
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

test "HTTP WIT package selection requires the exact service plan" {
    const http_source =
        \\send = @host_func("wasi:http/client@0.3.0-rc-2025-09-16", "send", (HttpRequest) -> Result<HttpResponse, HttpError>)
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
        \\wait_for = @host_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
    ;
    const clocks_tokens = try lexer.tokenize(std.testing.allocator, clocks_source);
    defer std.testing.allocator.free(clocks_tokens);
    try std.testing.expect(!(try requires_http_wit_package(std.testing.allocator, clocks_tokens)));
}

test "generic Component async target rejects scalar control flow without a lowering" {
    const source =
        \\wait_for = @host_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
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

test "generic Component async target accepts the registered scalar if probe" {
    const source =
        \\wait_for = @host_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
        \\wait_until = @host_func("wasi:clocks@0.3.0", "monotonic-clock.wait-until", (u64) -> nil)
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
        \\stdin_read = @host("wasi:cli/stdin@0.3.0-rc-2025-09-16", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, StdinError>>>)
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
        \\probe_read = @host("do:stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, ProbeError>>>)
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
        \\stdout_write = @host_func("wasi:cli/stdout@0.3.0-rc-2025-09-16", "write-via-stream", (StreamWriter<u8>) -> Result<nil, StdoutError>)
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
        \\wait_for = @host_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
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
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, null);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[task-return]run") != null);
    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "world http-client-probe") != null);
}
