const std = @import("std");
const generated_text = @import("codegen_text.zig");
const lexer = @import("lexer.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");
const producer_contract = @import("codegen_component_producer_contract.zig");
const wit_abi_layout = @import("wit_abi_layout.zig");
const wit_abi_types = @import("wit_abi_types.zig");

const canonical_core_wat = @embedFile("owned_record_triple_stream_producer_template.wat");

pub const ProducerError = error{UnsupportedP3OwnedRecordTripleStreamProducer};

pub const OwnedRecordTripleStreamProducerPlan = struct {
    descriptor: p3_async_manifest.Descriptor,
    source_host_name: []const u8,
    sink_host_name: []const u8,
    ticket_type_name: []const u8,
    record_type_name: []const u8,
    error_type_name: []const u8,
    root_name: []const u8,
    mode_name: []const u8,
    layout: p3_async_manifest.RecordLayout,
    producer: p3_async_manifest.ProducerCanonical,
    contract: producer_contract.ProducerContract,
};

pub fn analyze(
    tokens: []const lexer.Token,
    registry: p3_async_manifest.Registry,
) ProducerError!OwnedRecordTripleStreamProducerPlan {
    const descriptor = registry.find(
        "do:g6-2-owned-record-triple-producer@0.1.0",
        "consume-via-stream",
    ) orelse return error.UnsupportedP3OwnedRecordTripleStreamProducer;
    const shape = switch (p3_async_manifest.lowering_shape(descriptor) orelse
        return error.UnsupportedP3OwnedRecordTripleStreamProducer) {
        .record_resource_triple_stream_producer => |value| value,
        else => return error.UnsupportedP3OwnedRecordTripleStreamProducer,
    };

    const source = find_host_binding(tokens, .source) orelse
        return error.UnsupportedP3OwnedRecordTripleStreamProducer;
    const sink = find_host_binding(tokens, .sink) orelse
        return error.UnsupportedP3OwnedRecordTripleStreamProducer;
    if (count_host_bindings(tokens) != 2 or
        !std.mem.eql(u8, source.name, "make_ticket") or
        !std.mem.eql(u8, sink.name, "consume") or
        !std.mem.eql(u8, source.locator, "do:g6-2-owned-record-triple-producer/source@0.1.0") or
        !std.mem.eql(u8, source.member, "make-ticket") or
        !source_signature_is_exact(tokens, source.signature_open) or
        !std.mem.eql(u8, sink.locator, descriptor.locator) or
        !std.mem.eql(u8, sink.member, descriptor.member) or
        !sink_signature_is_exact(tokens, sink.signature_open))
        return error.UnsupportedP3OwnedRecordTripleStreamProducer;

    const ticket = find_resource_decl(tokens) orelse
        return error.UnsupportedP3OwnedRecordTripleStreamProducer;
    if (count_resource_decls(tokens) != 1 or
        !std.mem.eql(u8, ticket.name, "Ticket") or
        !std.mem.eql(u8, ticket.path, "do:g6-2-owned-record-triple-producer/source/ticket") or
        !resource_decl_is_exact(tokens, "Ticket", ticket.path))
        return error.UnsupportedP3OwnedRecordTripleStreamProducer;
    if (count_record_decls(tokens, "ResourceTriple") != 1 or
        !find_triple_record_decl(tokens, "ResourceTriple", "Ticket") or
        !find_error_decl(tokens, "ProducerError") or
        count_error_decls(tokens, "ProducerError") != 1 or
        !find_producer_function(tokens, "produce", "ProducerError") or
        !find_empty_start(tokens))
        return error.UnsupportedP3OwnedRecordTripleStreamProducer;
    if (count_top_level_declarations(tokens) != 7 or
        count_top_level_functions(tokens) != 2 or
        count_named_functions(tokens, "produce") != 1 or
        count_named_functions(tokens, "start") != 1 or
        count_token(tokens, "async") != 0 or
        count_intrinsic(tokens, "async") != 0 or
        count_intrinsic(tokens, "await") != 0 or
        count_intrinsic(tokens, "cancel") != 0)
        return error.UnsupportedP3OwnedRecordTripleStreamProducer;

    if (!std.mem.eql(u8, shape.element, "resource-triple") or
        shape.record_layout.byte_size != 12 or
        shape.record_layout.fields.len != 3 or
        shape.record_layout.source_fields.len != 3 or
        !std.mem.eql(u8, shape.record_layout.name, "resource-triple") or
        !field_is(shape.record_layout.fields[0], "left", "i32", 0) or
        !field_is(shape.record_layout.fields[1], "middle", "i32", 4) or
        !field_is(shape.record_layout.fields[2], "right", "i32", 8) or
        !source_field_is(shape.record_layout.source_fields[0], "left") or
        !source_field_is(shape.record_layout.source_fields[1], "middle") or
        !source_field_is(shape.record_layout.source_fields[2], "right") or
        shape.producer.stream_capacity != 1 or
        !std.mem.eql(u8, shape.producer.source_module, "do:g6-2-owned-record-triple-producer/source@0.1.0") or
        !std.mem.eql(u8, shape.producer.source_import_name, "make-ticket") or
        !std.mem.eql(u8, shape.producer.resource_drop_import, "[resource-drop]ticket") or
        !std.mem.eql(u8, shape.producer.terminal, "task-return") or
        shape.producer.runtime_count_param != null or
        shape.producer.runtime_max != null or
        shape.producer.runtime_mode_param == null or
        !std.mem.eql(u8, shape.producer.runtime_mode_param.?, "u32") or
        shape.producer.batch_count != null or
        shape.producer.batch_lengths != null)
        return error.UnsupportedP3OwnedRecordTripleStreamProducer;

    const contract = producer_contract.producer_contract_from_descriptor(descriptor) catch
        return error.UnsupportedP3OwnedRecordTripleStreamProducer;
    return .{
        .descriptor = descriptor,
        .source_host_name = source.name,
        .sink_host_name = sink.name,
        .ticket_type_name = ticket.name,
        .record_type_name = "ResourceTriple",
        .error_type_name = "ProducerError",
        .root_name = "produce",
        .mode_name = "mode",
        .layout = shape.record_layout,
        .producer = shape.producer,
        .contract = contract,
    };
}

pub fn emit_component_wat(
    allocator: std.mem.Allocator,
    plan: OwnedRecordTripleStreamProducerPlan,
) ![]u8 {
    try validate_internal_plans(allocator, plan);
    const wat = try generated_text.alloc_block(allocator, 0, canonical_core_wat);
    if (std.mem.indexOf(u8, wat, "__arc_") != null) {
        allocator.free(wat);
        return error.UnsupportedP3OwnedRecordTripleStreamProducer;
    }
    return wat;
}

pub fn emit_component_wat_for_tokens(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]u8 {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    const plan = try analyze(tokens, registry);
    return emit_component_wat(allocator, plan);
}

pub fn emit_component_wit(
    allocator: std.mem.Allocator,
    plan: OwnedRecordTripleStreamProducerPlan,
) ![]u8 {
    try validate_internal_plans(allocator, plan);
    if (!std.mem.eql(u8, plan.descriptor.wit.world, "owned-record-triple-producer"))
        return error.UnsupportedP3OwnedRecordTripleStreamProducer;
    return generated_text.alloc_block(allocator, 0,
        \\package do:g6-2-owned-record-triple-producer@0.1.0;
        \\
        \\interface types {
        \\  enum error-code { io, pipe, invalid-mode }
        \\  resource ticket {}
        \\  record resource-triple {
        \\    left: own<ticket>,
        \\    middle: own<ticket>,
        \\    right: own<ticket>,
        \\  }
        \\}
        \\
        \\interface source {
        \\  use types.{ticket};
        \\  make-ticket: func(seed: u32) -> own<ticket>;
        \\}
        \\
        \\interface sink {
        \\  use types.{error-code, resource-triple};
        \\  consume-via-stream: async func(
        \\    data: stream<resource-triple>
        \\  ) -> result<_, error-code>;
        \\}
        \\
        \\world owned-record-triple-producer {
        \\  use types.{error-code};
        \\  import source;
        \\  import sink;
        \\  export produce: async func(
        \\    mode: u32,
        \\    left-seed: u32,
        \\    middle-seed: u32,
        \\    right-seed: u32
        \\  ) -> result<_, error-code>;
        \\}
        \\
    );
}

pub fn emit_component_wit_for_tokens(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]u8 {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    const plan = try analyze(tokens, registry);
    return emit_component_wit(allocator, plan);
}

fn validate_internal_plans(
    allocator: std.mem.Allocator,
    plan: OwnedRecordTripleStreamProducerPlan,
) ProducerError!void {
    producer_contract.validate_contract(plan.contract) catch return error.UnsupportedP3OwnedRecordTripleStreamProducer;
    if (!std.mem.eql(u8, plan.contract.descriptor_id, plan.descriptor.locator) or
        plan.contract.sink.capacity != plan.producer.stream_capacity) return error.UnsupportedP3OwnedRecordTripleStreamProducer;
    const record = switch (plan.contract.payload) {
        .record => |value| value,
        else => return error.UnsupportedP3OwnedRecordTripleStreamProducer,
    };
    if (record.byte_size != plan.layout.byte_size or record.fields.len != plan.layout.fields.len) {
        return error.UnsupportedP3OwnedRecordTripleStreamProducer;
    }
    const shape = switch (p3_async_manifest.lowering_shape(plan.descriptor) orelse
        return error.UnsupportedP3OwnedRecordTripleStreamProducer) {
        .record_resource_triple_stream_producer => |value| value,
        else => return error.UnsupportedP3OwnedRecordTripleStreamProducer,
    };
    if (!std.mem.eql(u8, shape.element, "resource-triple") or
        !std.mem.eql(u8, shape.stream.element, "resource-triple") or
        !std.mem.eql(u8, shape.record_layout.name, "resource-triple") or
        shape.record_layout.byte_size != 12 or shape.record_layout.fields.len != 3 or
        shape.record_layout.source_fields.len != 3 or
        !field_is(shape.record_layout.fields[0], "left", "i32", 0) or
        !field_is(shape.record_layout.fields[1], "middle", "i32", 4) or
        !field_is(shape.record_layout.fields[2], "right", "i32", 8) or
        !source_field_is(shape.record_layout.source_fields[0], "left") or
        !source_field_is(shape.record_layout.source_fields[1], "middle") or
        !source_field_is(shape.record_layout.source_fields[2], "right") or
        !std.mem.eql(u8, shape.producer.source_module, "do:g6-2-owned-record-triple-producer/source@0.1.0") or
        !std.mem.eql(u8, shape.producer.source_import_name, "make-ticket") or
        !equal_core_types(shape.producer.source_core_params, &.{"i32"}) or
        !equal_core_types(shape.producer.source_core_results, &.{"i32"}) or
        !std.mem.eql(u8, shape.producer.resource_drop_import, "[resource-drop]ticket") or
        shape.producer.stream_capacity != 1 or
        !std.mem.eql(u8, shape.producer.terminal, "task-return") or
        shape.producer.runtime_count_param != null or shape.producer.runtime_max != null or
        shape.producer.runtime_mode_param == null or
        !std.mem.eql(u8, shape.producer.runtime_mode_param.?, "u32") or
        shape.producer.batch_count != null or shape.producer.batch_lengths != null or
        !std.mem.eql(u8, plan.record_type_name, "ResourceTriple") or
        !std.mem.eql(u8, plan.ticket_type_name, "Ticket") or
        !std.mem.eql(u8, plan.error_type_name, "ProducerError") or
        !std.mem.eql(u8, plan.root_name, "produce") or !std.mem.eql(u8, plan.mode_name, "mode") or
        plan.layout.byte_size != 12 or plan.layout.fields.len != 3 or plan.layout.source_fields.len != 3 or
        !std.mem.eql(u8, plan.layout.name, "resource-triple") or
        !field_is(plan.layout.fields[0], "left", "i32", 0) or
        !field_is(plan.layout.fields[1], "middle", "i32", 4) or
        !field_is(plan.layout.fields[2], "right", "i32", 8) or
        !source_field_is(plan.layout.source_fields[0], "left") or
        !source_field_is(plan.layout.source_fields[1], "middle") or
        !source_field_is(plan.layout.source_fields[2], "right") or
        !std.mem.eql(u8, plan.producer.source_module, shape.producer.source_module) or
        !std.mem.eql(u8, plan.producer.source_import_name, shape.producer.source_import_name) or
        !equal_core_types(plan.producer.source_core_params, shape.producer.source_core_params) or
        !equal_core_types(plan.producer.source_core_results, shape.producer.source_core_results) or
        !std.mem.eql(u8, plan.producer.resource_drop_import, shape.producer.resource_drop_import) or
        plan.producer.stream_capacity != shape.producer.stream_capacity or
        !std.mem.eql(u8, plan.producer.terminal, shape.producer.terminal) or
        !optional_string_equal(plan.producer.runtime_count_param, shape.producer.runtime_count_param) or
        plan.producer.runtime_max != shape.producer.runtime_max or
        !optional_string_equal(plan.producer.runtime_mode_param, shape.producer.runtime_mode_param) or
        plan.producer.batch_count != shape.producer.batch_count or
        !optional_u32_list_equal(plan.producer.batch_lengths, shape.producer.batch_lengths) or
        !valid_named_stream_operation(shape.stream.new, "[stream-new-0]consume-via-stream", &.{}, &.{"i64"}) or
        !valid_named_stream_operation(shape.stream.cancel_read, "[stream-cancel-read-0]consume-via-stream", &.{"i32"}, &.{"i32"}) or
        !valid_named_stream_operation(shape.stream.cancel_write, "[stream-cancel-write-0]consume-via-stream", &.{"i32"}, &.{"i32"}) or
        !valid_named_stream_operation(shape.stream.drop_readable, "[stream-drop-readable-0]consume-via-stream", &.{"i32"}, &.{}) or
        !valid_named_stream_operation(shape.stream.drop_writable, "[stream-drop-writable-0]consume-via-stream", &.{"i32"}, &.{}) or
        !valid_named_stream_operation(shape.stream.read, "[async-lower][stream-read-0]consume-via-stream", &.{ "i32", "i32", "i32" }, &.{"i32"}) or
        !valid_named_stream_operation(shape.stream.write, "[async-lower][stream-write-0]consume-via-stream", &.{ "i32", "i32", "i32" }, &.{"i32"}))
        return error.UnsupportedP3OwnedRecordTripleStreamProducer;

    var ticket = wit_abi_types.AbiType.resource(allocator, "ticket", .own) catch
        return error.UnsupportedP3OwnedRecordTripleStreamProducer;
    defer ticket.deinit();
    var triple = wit_abi_types.AbiType.record(allocator, &.{
        .{ .name = "left", .value = &ticket },
        .{ .name = "middle", .value = &ticket },
        .{ .name = "right", .value = &ticket },
    }) catch return error.UnsupportedP3OwnedRecordTripleStreamProducer;
    defer triple.deinit();
    var layout = wit_abi_layout.LayoutPlan.record(allocator, &triple, .{
        .byte_size = plan.layout.byte_size,
        .alignment = 4,
        .fields = &.{
            .{ .name = "left", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
            .{ .name = "middle", .offset = 4, .byte_size = 4, .alignment = 4, .indirect = null },
            .{ .name = "right", .offset = 8, .byte_size = 4, .alignment = 4, .indirect = null },
        },
    }) catch return error.UnsupportedP3OwnedRecordTripleStreamProducer;
    defer layout.deinit();
    if (layout.byte_size != 12 or layout.alignment != 4 or layout.record_fields.len != 3 or
        layout.record_fields[0].offset != 0 or layout.record_fields[1].offset != 4 or
        layout.record_fields[2].offset != 8 or
        !std.mem.eql(u8, layout.record_fields[0].name, "left") or
        !std.mem.eql(u8, layout.record_fields[1].name, "middle") or
        !std.mem.eql(u8, layout.record_fields[2].name, "right"))
        return error.UnsupportedP3OwnedRecordTripleStreamProducer;
}

const BindingKind = enum { source, sink };

const HostBinding = struct {
    name: []const u8,
    locator: []const u8,
    member: []const u8,
    signature_open: usize,
};

const ResourceDecl = struct { name: []const u8, path: []const u8 };

fn find_host_binding(tokens: []const lexer.Token, wanted: BindingKind) ?HostBinding {
    var found: ?HostBinding = null;
    var idx: usize = 0;
    while (idx + 10 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or !tok_eq(tokens[idx + 2], "@") or
            !tok_eq(tokens[idx + 4], "(") or tokens[idx + 5].kind != .string or !tok_eq(tokens[idx + 6], ",") or
            tokens[idx + 7].kind != .string or !tok_eq(tokens[idx + 8], ",") or !tok_eq(tokens[idx + 9], "(")) continue;
        const kind: BindingKind = if (tok_eq(tokens[idx + 3], "host_func")) .source else if (tok_eq(tokens[idx + 3], "host_async_func")) .sink else continue;
        if (kind != wanted) continue;
        const close = find_matching(tokens, idx + 9, "(", ")") orelse continue;
        if (close + 3 >= tokens.len or !tok_eq(tokens[close + 1], "-") or !tok_eq(tokens[close + 2], ">") or found != null) return null;
        found = .{
            .name = tokens[idx].lexeme,
            .locator = string_body(tokens[idx + 5].lexeme) orelse return null,
            .member = string_body(tokens[idx + 7].lexeme) orelse return null,
            .signature_open = idx + 9,
        };
    }
    return found;
}

fn count_host_bindings(tokens: []const lexer.Token) usize {
    var count: usize = 0;
    var idx: usize = 0;
    while (idx + 3 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind == .ident and tok_eq(tokens[idx + 1], "=") and tok_eq(tokens[idx + 2], "@") and
            (tok_eq(tokens[idx + 3], "host_func") or tok_eq(tokens[idx + 3], "host_async_func"))) count += 1;
    }
    return count;
}

fn count_resource_decls(tokens: []const lexer.Token) usize {
    var count: usize = 0;
    var idx: usize = 0;
    while (idx + 5 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind == .ident and tok_eq(tokens[idx + 1], "=") and tok_eq(tokens[idx + 2], "@") and
            tok_eq(tokens[idx + 3], "wasi_resource") and tok_eq(tokens[idx + 4], "(") and tokens[idx + 5].kind == .string) count += 1;
    }
    return count;
}

fn count_record_decls(tokens: []const lexer.Token, name: []const u8) usize {
    var count: usize = 0;
    var idx: usize = 0;
    while (idx + 1 < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], name) and tok_eq(tokens[idx + 1], "{")) count += 1;
    }
    return count;
}

fn count_error_decls(tokens: []const lexer.Token, name: []const u8) usize {
    var count: usize = 0;
    var idx: usize = 0;
    while (idx + 2 < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], name) and tok_eq(tokens[idx + 1], "error") and tok_eq(tokens[idx + 2], "=")) count += 1;
    }
    return count;
}

fn count_top_level_declarations(tokens: []const lexer.Token) usize {
    var depth: usize = 0;
    var paren_depth: usize = 0;
    var count: usize = 0;
    var idx: usize = 0;
    while (idx + 1 < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], "(")) {
            paren_depth += 1;
            continue;
        }
        if (tok_eq(tokens[idx], ")")) {
            if (paren_depth > 0) paren_depth -= 1;
            continue;
        }
        if (tok_eq(tokens[idx], "{")) {
            depth += 1;
            continue;
        }
        if (tok_eq(tokens[idx], "}")) {
            if (depth > 0) depth -= 1;
            continue;
        }
        if (depth != 0 or paren_depth != 0 or tokens[idx].kind != .ident) continue;
        const previous_is_at = idx > 0 and tok_eq(tokens[idx - 1], "@");
        const previous_is_ident = idx > 0 and tokens[idx - 1].kind == .ident;
        const is_declaration_head =
            (tok_eq(tokens[idx + 1], "=") and !previous_is_at and !(tok_eq(tokens[idx], "error") and previous_is_ident)) or
            (tok_eq(tokens[idx + 1], "{") and !previous_is_at) or
            (tok_eq(tokens[idx + 1], "(") and !previous_is_at) or tok_eq(tokens[idx + 1], "error");
        if (is_declaration_head) count += 1;
    }
    return count;
}

fn source_signature_is_exact(tokens: []const lexer.Token, open: usize) bool {
    const close = find_matching(tokens, open, "(", ")") orelse return false;
    return close == open + 2 and tok_eq(tokens[open + 1], "u32") and close + 3 < tokens.len and
        tok_eq(tokens[close + 1], "-") and tok_eq(tokens[close + 2], ">") and tok_eq(tokens[close + 3], "Ticket");
}

fn sink_signature_is_exact(tokens: []const lexer.Token, open: usize) bool {
    const close = find_matching(tokens, open, "(", ")") orelse return false;
    return close == open + 5 and tok_eq(tokens[open + 1], "StreamWriter") and tok_eq(tokens[open + 2], "<") and
        tok_eq(tokens[open + 3], "ResourceTriple") and tok_eq(tokens[open + 4], ">") and
        tok_eq(tokens[close + 1], "-") and tok_eq(tokens[close + 2], ">") and tok_eq(tokens[close + 3], "Result") and
        tok_eq(tokens[close + 4], "<") and tok_eq(tokens[close + 5], "nil") and tok_eq(tokens[close + 6], ",") and
        tok_eq(tokens[close + 7], "ProducerError") and tok_eq(tokens[close + 8], ">");
}

fn find_resource_decl(tokens: []const lexer.Token) ?ResourceDecl {
    var idx: usize = 0;
    while (idx + 6 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or !tok_eq(tokens[idx + 2], "@") or
            !tok_eq(tokens[idx + 3], "wasi_resource") or !tok_eq(tokens[idx + 4], "(") or tokens[idx + 5].kind != .string) continue;
        return .{ .name = tokens[idx].lexeme, .path = string_body(tokens[idx + 5].lexeme) orelse continue };
    }
    return null;
}

fn resource_decl_is_exact(tokens: []const lexer.Token, name: []const u8, path: []const u8) bool {
    var idx: usize = 0;
    while (idx + 12 < tokens.len) : (idx += 1) {
        if (!tok_eq(tokens[idx], name) or !tok_eq(tokens[idx + 1], "=") or !tok_eq(tokens[idx + 2], "@") or
            !tok_eq(tokens[idx + 3], "wasi_resource") or !tok_eq(tokens[idx + 4], "(") or tokens[idx + 5].kind != .string or
            !std.mem.eql(u8, string_body(tokens[idx + 5].lexeme) orelse return false, path) or !tok_eq(tokens[idx + 6], ",") or
            !tok_eq(tokens[idx + 7], "{") or !tok_eq(tokens[idx + 8], ".id") or !tok_eq(tokens[idx + 9], "i64") or
            !tok_eq(tokens[idx + 10], "}") or !tok_eq(tokens[idx + 11], ")")) continue;
        return true;
    }
    return false;
}

fn find_triple_record_decl(tokens: []const lexer.Token, name: []const u8, field_type: []const u8) bool {
    var idx: usize = 0;
    while (idx + 10 < tokens.len) : (idx += 1) {
        if (!tok_eq(tokens[idx], name) or !tok_eq(tokens[idx + 1], "{") or !tok_eq(tokens[idx + 2], ".left") or
            !tok_eq(tokens[idx + 3], field_type) or !tok_eq(tokens[idx + 4], ".middle") or !tok_eq(tokens[idx + 5], field_type) or
            !tok_eq(tokens[idx + 6], ".right") or !tok_eq(tokens[idx + 7], field_type) or !tok_eq(tokens[idx + 8], "}")) continue;
        return true;
    }
    return false;
}

fn find_error_decl(tokens: []const lexer.Token, name: []const u8) bool {
    var idx: usize = 0;
    while (idx + 8 < tokens.len) : (idx += 1) if (tok_eq(tokens[idx], name) and tok_eq(tokens[idx + 1], "error") and tok_eq(tokens[idx + 2], "=") and tok_eq(tokens[idx + 3], "Io") and tok_eq(tokens[idx + 4], "|") and tok_eq(tokens[idx + 5], "Pipe") and tok_eq(tokens[idx + 6], "|") and tok_eq(tokens[idx + 7], "InvalidMode") and !tok_eq(tokens[idx + 8], "|")) return true;
    return false;
}

fn find_producer_function(tokens: []const lexer.Token, name: []const u8, error_name: []const u8) bool {
    var idx: usize = 0;
    while (idx + 18 < tokens.len) : (idx += 1) {
        if (!tok_eq(tokens[idx], name) or !tok_eq(tokens[idx + 1], "(")) continue;
        const close = find_matching(tokens, idx + 1, "(", ")") orelse continue;
        if (close != idx + 13 or !tok_eq(tokens[idx + 2], "mode") or !tok_eq(tokens[idx + 3], "u32") or
            !tok_eq(tokens[idx + 4], ",") or !tok_eq(tokens[idx + 5], "left_seed") or !tok_eq(tokens[idx + 6], "u32") or
            !tok_eq(tokens[idx + 7], ",") or !tok_eq(tokens[idx + 8], "middle_seed") or !tok_eq(tokens[idx + 9], "u32") or
            !tok_eq(tokens[idx + 10], ",") or !tok_eq(tokens[idx + 11], "right_seed") or !tok_eq(tokens[idx + 12], "u32") or
            !tok_eq(tokens[close + 1], "-") or !tok_eq(tokens[close + 2], ">") or !tok_eq(tokens[close + 3], "Result") or
            !tok_eq(tokens[close + 4], "<") or !tok_eq(tokens[close + 5], "nil") or !tok_eq(tokens[close + 6], ",") or
            !tok_eq(tokens[close + 7], error_name) or !tok_eq(tokens[close + 8], ">") or !tok_eq(tokens[close + 9], "{")) continue;
        const body_close = find_matching(tokens, close + 9, "{", "}") orelse continue;
        return body_close == close + 14 and tok_eq(tokens[close + 10], "return") and tok_eq(tokens[close + 11], "Ok") and
            tok_eq(tokens[close + 12], "(") and tok_eq(tokens[close + 13], ")");
    }
    return false;
}

fn find_empty_start(tokens: []const lexer.Token) bool {
    var idx: usize = 0;
    while (idx + 4 < tokens.len) : (idx += 1) if (tok_eq(tokens[idx], "start") and tok_eq(tokens[idx + 1], "(") and tok_eq(tokens[idx + 2], ")") and tok_eq(tokens[idx + 3], "{") and tok_eq(tokens[idx + 4], "}")) return true;
    return false;
}

fn count_top_level_functions(tokens: []const lexer.Token) usize {
    var depth: usize = 0;
    var count: usize = 0;
    var idx: usize = 0;
    while (idx + 1 < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], "{")) {
            depth += 1;
            continue;
        }
        if (tok_eq(tokens[idx], "}")) {
            if (depth > 0) depth -= 1;
            continue;
        }
        if (depth == 0 and tokens[idx].kind == .ident and tok_eq(tokens[idx + 1], "(") and (idx == 0 or !tok_eq(tokens[idx - 1], "@"))) count += 1;
    }
    return count;
}

fn count_named_functions(tokens: []const lexer.Token, name: []const u8) usize {
    var count: usize = 0;
    var depth: usize = 0;
    var idx: usize = 0;
    while (idx + 1 < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], "{")) {
            depth += 1;
            continue;
        }
        if (tok_eq(tokens[idx], "}")) {
            if (depth > 0) depth -= 1;
            continue;
        }
        if (depth == 0 and tok_eq(tokens[idx], name) and tok_eq(tokens[idx + 1], "(")) count += 1;
    }
    return count;
}

fn count_token(tokens: []const lexer.Token, name: []const u8) usize {
    var count: usize = 0;
    for (tokens) |token| {
        if (tok_eq(token, name)) count += 1;
    }
    return count;
}

fn count_intrinsic(tokens: []const lexer.Token, name: []const u8) usize {
    var count: usize = 0;
    var idx: usize = 0;
    while (idx + 1 < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], "@") and tok_eq(tokens[idx + 1], name)) count += 1;
    }
    return count;
}

fn find_matching(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8) ?usize {
    if (open_idx >= tokens.len or !tok_eq(tokens[open_idx], open)) return null;
    var depth: usize = 0;
    for (tokens[open_idx..], 0..) |token, offset| {
        if (tok_eq(token, open)) depth += 1;
        if (tok_eq(token, close)) {
            depth -= 1;
            if (depth == 0) return open_idx + offset;
        }
    }
    return null;
}

fn valid_named_stream_operation(operation: p3_async_manifest.StreamOperation, name: []const u8, params: []const []const u8, results: []const []const u8) bool {
    return std.mem.eql(u8, operation.import_name, name) and equal_core_types(operation.core_params, params) and equal_core_types(operation.core_results, results);
}

fn equal_core_types(actual: []const []const u8, expected: []const []const u8) bool {
    if (actual.len != expected.len) return false;
    for (actual, expected) |left, right| if (!std.mem.eql(u8, left, right)) return false;
    return true;
}

fn optional_u32_list_equal(actual: ?[]const u32, expected: ?[]const u32) bool {
    if (actual == null or expected == null) return actual == null and expected == null;
    if (actual.?.len != expected.?.len) return false;
    for (actual.?, expected.?) |left, right| if (left != right) return false;
    return true;
}

fn optional_string_equal(actual: ?[]const u8, expected: ?[]const u8) bool {
    if (actual == null or expected == null) return actual == null and expected == null;
    return std.mem.eql(u8, actual.?, expected.?);
}

fn field_is(field: p3_async_manifest.RecordField, name: []const u8, core_type: []const u8, offset: u32) bool {
    return std.mem.eql(u8, field.name, name) and std.mem.eql(u8, field.core_type, core_type) and field.offset == offset;
}

fn source_field_is(field: p3_async_manifest.RecordSourceField, name: []const u8) bool {
    return std.mem.eql(u8, field.name, name) and std.mem.eql(u8, field.source_type, "ticket") and field.storage.len == 1 and
        std.mem.eql(u8, field.storage[0], name) and field.ownership == .own and field.resource != null and
        std.mem.eql(u8, field.resource.?, "ticket") and field.drop_import != null and
        std.mem.eql(u8, field.drop_import.?, "[resource-drop]ticket") and field.nested_fields.len == 0;
}

fn string_body(lexeme: []const u8) ?[]const u8 {
    if (lexeme.len < 2 or lexeme[0] != '"' or lexeme[lexeme.len - 1] != '"') return null;
    return lexeme[1 .. lexeme.len - 1];
}

fn tok_eq(token: lexer.Token, expected: []const u8) bool {
    return std.mem.eql(u8, token.lexeme, expected);
}

const exact_source =
    \\make_ticket = @host_func("do:g6-2-owned-record-triple-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
    \\consume = @host_async_func("do:g6-2-owned-record-triple-producer@0.1.0", "consume-via-stream", (StreamWriter<ResourceTriple>) -> Result<nil, ProducerError>)
    \\Ticket = @wasi_resource("do:g6-2-owned-record-triple-producer/source/ticket", { .id i64 })
    \\ResourceTriple {
    \\    .left Ticket
    \\    .middle Ticket
    \\    .right Ticket
    \\}
    \\ProducerError error = Io | Pipe | InvalidMode
    \\produce(mode u32, left_seed u32, middle_seed u32, right_seed u32) -> Result<nil, ProducerError> { return Ok() }
    \\start() {}
;

test "owned record triple producer admits the pinned source shape" {
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const tokens = try lexer.tokenize(std.testing.allocator, exact_source);
    defer std.testing.allocator.free(tokens);

    const plan = try analyze(tokens, registry);
    try std.testing.expectEqualStrings("ResourceTriple", plan.record_type_name);
    try std.testing.expectEqual(@as(u32, 12), plan.layout.byte_size);
    try std.testing.expectEqual(@as(usize, 3), plan.layout.fields.len);
    try std.testing.expectEqualStrings(plan.descriptor.locator, plan.contract.descriptor_id);
    try std.testing.expectEqual(@as(usize, 3), plan.contract.ownership.leaves.len);
    try std.testing.expectEqual(@as(u32, 8), plan.contract.ownership.leaves[2].handle_offset);
}

test "owned record triple producer emits the pinned WAT and WIT contracts" {
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const tokens = try lexer.tokenize(std.testing.allocator, exact_source);
    defer std.testing.allocator.free(tokens);
    const plan = try analyze(tokens, registry);

    const wat = try emit_component_wat(std.testing.allocator, plan);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[producer-record-byte-size] 12") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[producer-record-left-offset] 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[producer-record-middle-offset] 4") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[producer-record-right-offset] 8") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[producer-input-word-count] 4") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[producer-seed-order] left then middle then right") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);

    const wit = try emit_component_wit(std.testing.allocator, plan);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "package do:g6-2-owned-record-triple-producer@0.1.0;") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "record resource-triple") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "world owned-record-triple-producer") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "right-seed: u32") != null);
}

fn expect_rejected_mutation(old: []const u8, new: []const u8) !void {
    const mutated = try std.mem.replaceOwned(u8, std.testing.allocator, exact_source, old, new);
    defer std.testing.allocator.free(mutated);
    const tokens = try lexer.tokenize(std.testing.allocator, mutated);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    try std.testing.expectError(
        error.UnsupportedP3OwnedRecordTripleStreamProducer,
        analyze(tokens, registry),
    );
    try std.testing.expectError(
        error.UnsupportedP3OwnedRecordTripleStreamProducer,
        emit_component_wat_for_tokens(std.testing.allocator, tokens),
    );
}

test "owned record triple producer rejects non-triple record shapes" {
    try expect_rejected_mutation(".middle Ticket\n    .right Ticket", ".right Ticket");
    try expect_rejected_mutation(".middle Ticket", ".middle borrow<Ticket>");
    try expect_rejected_mutation(
        ".left Ticket\n    .middle Ticket\n    .right Ticket",
        ".right Ticket\n    .middle Ticket\n    .left Ticket",
    );
    try expect_rejected_mutation(".right Ticket\n}", ".right Ticket\n    .extra Ticket\n}");
}

test "owned record triple producer rejects seed signature and async drift" {
    try expect_rejected_mutation("middle_seed u32", "middle_seed i64");
    try expect_rejected_mutation(
        "left_seed u32, middle_seed u32, right_seed u32",
        "left_seed u32, right_seed u32, middle_seed u32",
    );
    try expect_rejected_mutation("return Ok()", "return @async()");
    try expect_rejected_mutation("Io | Pipe | InvalidMode", "Io | Pipe | InvalidMode | Other");
}

test "owned record triple producer rejects an unregistered descriptor" {
    try expect_rejected_mutation(
        "do:g6-2-owned-record-triple-producer@0.1.0",
        "do:g6-2-owned-record-triple-unregistered@0.1.0",
    );
}
