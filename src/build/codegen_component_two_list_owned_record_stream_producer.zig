const std = @import("std");
const generated_text = @import("codegen_text.zig");
const lexer = @import("lexer.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");
const producer_contract = @import("codegen_component_producer_contract.zig");

const canonical_core_wat = @embedFile("two_list_owned_record_stream_producer_template.wat");

pub const ProducerError = error{UnsupportedP3TwoListOwnedRecordStreamProducer};

pub const TwoListOwnedRecordStreamProducerPlan = struct {
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

    pub fn analyze(
        tokens: []const lexer.Token,
        registry: p3_async_manifest.Registry,
    ) ProducerError!TwoListOwnedRecordStreamProducerPlan {
        const descriptor = registry.find(
            "do:g6-2-owned-record-two-list-producer@0.1.0",
            "consume-via-stream",
        ) orelse return error.UnsupportedP3TwoListOwnedRecordStreamProducer;
        const shape = switch (p3_async_manifest.lowering_shape(descriptor) orelse
            return error.UnsupportedP3TwoListOwnedRecordStreamProducer) {
            .record_resource_two_list_owned_record_stream_producer => |value| value,
            else => return error.UnsupportedP3TwoListOwnedRecordStreamProducer,
        };

        const source = find_host_binding(tokens, .source) orelse
            return error.UnsupportedP3TwoListOwnedRecordStreamProducer;
        const sink = find_host_binding(tokens, .sink) orelse
            return error.UnsupportedP3TwoListOwnedRecordStreamProducer;
        if (count_host_bindings(tokens) != 2 or
            !std.mem.eql(u8, source.name, "make_ticket") or
            !std.mem.eql(u8, sink.name, "consume") or
            !std.mem.eql(u8, source.locator, "do:g6-2-owned-record-two-list-producer/source@0.1.0") or
            !std.mem.eql(u8, source.member, "make-ticket") or
            !source_signature_is_exact(tokens, source.signature_open) or
            !std.mem.eql(u8, sink.locator, descriptor.locator) or
            !std.mem.eql(u8, sink.member, descriptor.member) or
            !sink_signature_is_exact(tokens, sink.signature_open))
            return error.UnsupportedP3TwoListOwnedRecordStreamProducer;

        const ticket = find_resource_decl(tokens) orelse
            return error.UnsupportedP3TwoListOwnedRecordStreamProducer;
        if (count_resource_decls(tokens) != 1 or
            !std.mem.eql(u8, ticket.name, "Ticket") or
            !std.mem.eql(u8, ticket.path, "do:g6-2-owned-record-two-list-producer/source/ticket") or
            !resource_decl_is_exact(tokens, "Ticket", ticket.path))
            return error.UnsupportedP3TwoListOwnedRecordStreamProducer;

        if (count_record_decls(tokens, "TwoListEntry") != 1 or
            !find_record_decl(tokens, "TwoListEntry") or
            !find_error_decl(tokens, "ProducerError") or
            count_error_decls(tokens, "ProducerError") != 1 or
            !find_producer_function(tokens, "produce", "ProducerError") or
            !find_empty_start(tokens))
            return error.UnsupportedP3TwoListOwnedRecordStreamProducer;

        if (count_top_level_declarations(tokens) != 7 or
            count_top_level_functions(tokens) != 2 or
            count_named_functions(tokens, "produce") != 1 or
            count_named_functions(tokens, "start") != 1 or
            count_token(tokens, "async") != 0 or
            count_intrinsic(tokens, "async") != 0 or
            count_intrinsic(tokens, "await") != 0 or
            count_intrinsic(tokens, "cancel") != 0)
            return error.UnsupportedP3TwoListOwnedRecordStreamProducer;

        if (!shape_matches(shape)) return error.UnsupportedP3TwoListOwnedRecordStreamProducer;
        const contract = producer_contract.producer_contract_from_descriptor(descriptor) catch
            return error.UnsupportedP3TwoListOwnedRecordStreamProducer;
        return .{
            .descriptor = descriptor,
            .source_host_name = source.name,
            .sink_host_name = sink.name,
            .ticket_type_name = ticket.name,
            .record_type_name = "TwoListEntry",
            .error_type_name = "ProducerError",
            .root_name = "produce",
            .mode_name = "mode",
            .layout = shape.record_layout,
            .producer = shape.producer,
            .contract = contract,
        };
    }
};

pub fn emit_component_wat(
    allocator: std.mem.Allocator,
    plan: TwoListOwnedRecordStreamProducerPlan,
) ![]u8 {
    try validate_internal_plan(plan);
    const wat = try generated_text.alloc_block(allocator, 0, canonical_core_wat);
    if (std.mem.indexOf(u8, wat, "__arc_") != null or
        std.mem.indexOf(u8, wat, "(ref ") != null or
        std.mem.indexOf(u8, wat, "(struct ") != null or
        std.mem.indexOf(u8, wat, "(array ") != null)
    {
        allocator.free(wat);
        return error.UnsupportedP3TwoListOwnedRecordStreamProducer;
    }
    return wat;
}

pub fn emit_component_wat_for_tokens(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
) ![]u8 {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    const plan = try TwoListOwnedRecordStreamProducerPlan.analyze(tokens, registry);
    return emit_component_wat(allocator, plan);
}

pub fn emit_component_wit(
    allocator: std.mem.Allocator,
    plan: TwoListOwnedRecordStreamProducerPlan,
) ![]u8 {
    try validate_internal_plan(plan);
    if (!std.mem.eql(u8, plan.descriptor.wit.world, "owned-record-two-list-producer"))
        return error.UnsupportedP3TwoListOwnedRecordStreamProducer;
    return generated_text.alloc_block(allocator, 0,
        \\package do:g6-2-owned-record-two-list-producer@0.1.0;
        \\
        \\interface types {
        \\  enum error-code { io, pipe, invalid-mode }
        \\  resource ticket {}
        \\  record two-list-entry {
        \\    first: list<u32>,
        \\    second: list<u32>,
        \\    ticket: own<ticket>,
        \\  }
        \\}
        \\
        \\interface source {
        \\  use types.{ticket};
        \\  make-ticket: func(seed: u32) -> own<ticket>;
        \\}
        \\
        \\interface sink {
        \\  use types.{error-code, two-list-entry};
        \\  consume-via-stream: async func(
        \\    data: stream<two-list-entry>
        \\  ) -> result<_, error-code>;
        \\}
        \\
        \\world owned-record-two-list-producer {
        \\  use types.{error-code};
        \\  import source;
        \\  import sink;
        \\  export produce: async func(mode: u32) -> result<_, error-code>;
        \\}
        \\
    );
}

pub fn emit_component_wit_for_tokens(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
) ![]u8 {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    const plan = try TwoListOwnedRecordStreamProducerPlan.analyze(tokens, registry);
    return emit_component_wit(allocator, plan);
}

fn validate_internal_plan(plan: TwoListOwnedRecordStreamProducerPlan) ProducerError!void {
    producer_contract.validate_contract(plan.contract) catch
        return error.UnsupportedP3TwoListOwnedRecordStreamProducer;
    if (!std.mem.eql(u8, plan.contract.descriptor_id, plan.descriptor.locator) or
        plan.contract.descriptor_hash == null or
        !std.mem.eql(u8, plan.contract.descriptor_hash.?, plan.descriptor.wit_sha256 orelse "") or
        plan.contract.sink.capacity != plan.producer.stream_capacity or
        plan.producer.stream_capacity != 1 or
        !std.mem.eql(u8, plan.producer.terminal, "task-return"))
        return error.UnsupportedP3TwoListOwnedRecordStreamProducer;

    const shape = switch (p3_async_manifest.lowering_shape(plan.descriptor) orelse
        return error.UnsupportedP3TwoListOwnedRecordStreamProducer) {
        .record_resource_two_list_owned_record_stream_producer => |value| value,
        else => return error.UnsupportedP3TwoListOwnedRecordStreamProducer,
    };
    if (!shape_matches(shape) or
        !std.mem.eql(u8, plan.source_host_name, "make_ticket") or
        !std.mem.eql(u8, plan.sink_host_name, "consume") or
        !std.mem.eql(u8, plan.ticket_type_name, "Ticket") or
        !std.mem.eql(u8, plan.record_type_name, "TwoListEntry") or
        !std.mem.eql(u8, plan.error_type_name, "ProducerError") or
        !std.mem.eql(u8, plan.root_name, "produce") or
        !std.mem.eql(u8, plan.mode_name, "mode"))
        return error.UnsupportedP3TwoListOwnedRecordStreamProducer;

    const record = switch (plan.contract.payload) {
        .record => |value| value,
        else => return error.UnsupportedP3TwoListOwnedRecordStreamProducer,
    };
    if (!record_layout_matches(record) or !record_layout_matches(plan.layout))
        return error.UnsupportedP3TwoListOwnedRecordStreamProducer;

    if (plan.contract.ownership.leaves.len != 1 or plan.contract.ownership.parents.len != 0)
        return error.UnsupportedP3TwoListOwnedRecordStreamProducer;
    const leaf = plan.contract.ownership.leaves[0];
    if (leaf.path.len != 1 or !std.mem.eql(u8, leaf.path[0], "ticket") or
        !std.mem.eql(u8, leaf.resource, "ticket") or leaf.handle_offset != 16 or
        !std.mem.eql(u8, leaf.drop_import, "[resource-drop]ticket") or leaf.bit != 0)
        return error.UnsupportedP3TwoListOwnedRecordStreamProducer;

    if (plan.contract.list_allocations.len != 2 or
        !allocation_matches(plan.contract.list_allocations[0], "first", 0, 4) or
        !allocation_matches(plan.contract.list_allocations[1], "second", 8, 12))
        return error.UnsupportedP3TwoListOwnedRecordStreamProducer;
    if (!std.mem.eql(u8, plan.contract.source.module, plan.producer.source_module) or
        !std.mem.eql(u8, plan.contract.source.import_name, plan.producer.source_import_name) or
        !equal_core_types(plan.contract.source.core_params, &.{"i32"}) or
        !equal_core_types(plan.contract.source.core_results, &.{"i32"}))
        return error.UnsupportedP3TwoListOwnedRecordStreamProducer;
    if (!named_operation_matches(shape.stream.new, "[stream-new-0]consume-via-stream", &.{}, &.{"i64"}) or
        !named_operation_matches(shape.stream.cancel_read, "[stream-cancel-read-0]consume-via-stream", &.{"i32"}, &.{"i32"}) or
        !named_operation_matches(shape.stream.cancel_write, "[stream-cancel-write-0]consume-via-stream", &.{"i32"}, &.{"i32"}) or
        !named_operation_matches(shape.stream.drop_readable, "[stream-drop-readable-0]consume-via-stream", &.{"i32"}, &.{}) or
        !named_operation_matches(shape.stream.drop_writable, "[stream-drop-writable-0]consume-via-stream", &.{"i32"}, &.{}) or
        !named_operation_matches(shape.stream.read, "[async-lower][stream-read-0]consume-via-stream", &.{ "i32", "i32", "i32" }, &.{"i32"}) or
        !named_operation_matches(shape.stream.write, "[async-lower][stream-write-0]consume-via-stream", &.{ "i32", "i32", "i32" }, &.{"i32"}))
        return error.UnsupportedP3TwoListOwnedRecordStreamProducer;
}

fn shape_matches(shape: p3_async_manifest.TwoListOwnedRecordStreamProducerShape) bool {
    return std.mem.eql(u8, shape.element, "two-list-entry") and
        std.mem.eql(u8, shape.stream.element, "two-list-entry") and
        record_layout_matches(shape.record_layout) and
        shape.producer.stream_capacity == 1 and
        std.mem.eql(u8, shape.producer.source_module, "do:g6-2-owned-record-two-list-producer/source@0.1.0") and
        std.mem.eql(u8, shape.producer.source_import_name, "make-ticket") and
        equal_core_types(shape.producer.source_core_params, &.{"i32"}) and
        equal_core_types(shape.producer.source_core_results, &.{"i32"}) and
        std.mem.eql(u8, shape.producer.resource_drop_import, "[resource-drop]ticket") and
        std.mem.eql(u8, shape.producer.terminal, "task-return") and
        shape.producer.runtime_count_param == null and shape.producer.runtime_max == null and
        shape.producer.runtime_mode_param != null and
        std.mem.eql(u8, shape.producer.runtime_mode_param.?, "u32") and
        shape.producer.batch_count == null and shape.producer.batch_lengths == null and
        named_operation_matches(shape.stream.new, "[stream-new-0]consume-via-stream", &.{}, &.{"i64"}) and
        named_operation_matches(shape.stream.cancel_read, "[stream-cancel-read-0]consume-via-stream", &.{"i32"}, &.{"i32"}) and
        named_operation_matches(shape.stream.cancel_write, "[stream-cancel-write-0]consume-via-stream", &.{"i32"}, &.{"i32"}) and
        named_operation_matches(shape.stream.drop_readable, "[stream-drop-readable-0]consume-via-stream", &.{"i32"}, &.{}) and
        named_operation_matches(shape.stream.drop_writable, "[stream-drop-writable-0]consume-via-stream", &.{"i32"}, &.{}) and
        named_operation_matches(shape.stream.read, "[async-lower][stream-read-0]consume-via-stream", &.{ "i32", "i32", "i32" }, &.{"i32"}) and
        named_operation_matches(shape.stream.write, "[async-lower][stream-write-0]consume-via-stream", &.{ "i32", "i32", "i32" }, &.{"i32"});
}

fn record_layout_matches(layout: p3_async_manifest.RecordLayout) bool {
    return std.mem.eql(u8, layout.name, "two-list-entry") and
        layout.byte_size == 20 and layout.alignment == 4 and
        layout.fields.len == 3 and layout.source_fields.len == 3 and
        field_matches(layout.fields[0], "first", "i32", 0) and
        field_matches(layout.fields[1], "second", "i32", 8) and
        field_matches(layout.fields[2], "ticket", "i32", 16) and
        list_source_matches(layout.source_fields[0], "first") and
        list_source_matches(layout.source_fields[1], "second") and
        owned_source_matches(layout.source_fields[2]);
}

fn list_source_matches(field: p3_async_manifest.RecordSourceField, name: []const u8) bool {
    return std.mem.eql(u8, field.name, name) and
        std.mem.eql(u8, field.source_type, "list<u32>") and
        field.storage.len == 1 and std.mem.eql(u8, field.storage[0], name) and
        field.ownership == .none and field.resource == null and
        field.drop_import == null and field.nested_fields.len == 0;
}

fn owned_source_matches(field: p3_async_manifest.RecordSourceField) bool {
    return std.mem.eql(u8, field.name, "ticket") and
        std.mem.eql(u8, field.source_type, "ticket") and
        field.storage.len == 1 and std.mem.eql(u8, field.storage[0], "ticket") and
        field.ownership == .own and field.resource != null and
        std.mem.eql(u8, field.resource.?, "ticket") and field.drop_import != null and
        std.mem.eql(u8, field.drop_import.?, "[resource-drop]ticket") and
        field.nested_fields.len == 0;
}

fn allocation_matches(
    allocation: producer_contract.ListAllocation,
    name: []const u8,
    pointer_offset: u32,
    length_offset: u32,
) bool {
    return allocation.path.len == 1 and std.mem.eql(u8, allocation.path[0], name) and
        std.mem.eql(u8, allocation.element_core_type, "u32") and
        allocation.pointer_offset == pointer_offset and allocation.length_offset == length_offset and
        allocation.element_stride == 4 and allocation.max_items == 3 and
        std.mem.eql(u8, allocation.release_import, "cabi_realloc");
}

fn named_operation_matches(
    operation: p3_async_manifest.StreamOperation,
    import_name: []const u8,
    params: []const []const u8,
    results: []const []const u8,
) bool {
    return std.mem.eql(u8, operation.import_name, import_name) and
        equal_core_types(operation.core_params, params) and
        equal_core_types(operation.core_results, results);
}

fn equal_core_types(actual: []const []const u8, expected: []const []const u8) bool {
    if (actual.len != expected.len) return false;
    for (actual, 0..) |value, index| {
        if (!std.mem.eql(u8, value, expected[index])) return false;
    }
    return true;
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
        if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or
            !tok_eq(tokens[idx + 2], "@") or !tok_eq(tokens[idx + 4], "(") or
            tokens[idx + 5].kind != .string or !tok_eq(tokens[idx + 6], ",") or
            tokens[idx + 7].kind != .string or !tok_eq(tokens[idx + 8], ",") or
            !tok_eq(tokens[idx + 9], "(")) continue;
        const kind: BindingKind = if (tok_eq(tokens[idx + 3], "host_func")) .source else if (tok_eq(tokens[idx + 3], "host_async_func")) .sink else continue;
        if (kind != wanted) continue;
        const close = find_matching(tokens, idx + 9, "(", ")") orelse continue;
        if (close + 3 >= tokens.len or !tok_eq(tokens[close + 1], "-") or
            !tok_eq(tokens[close + 2], ">") or found != null) return null;
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
    for (tokens, 0..) |token, idx| {
        if (token.kind == .ident and idx + 3 < tokens.len and
            tok_eq(tokens[idx + 1], "=") and tok_eq(tokens[idx + 2], "@") and
            (tok_eq(tokens[idx + 3], "host_func") or tok_eq(tokens[idx + 3], "host_async_func"))) count += 1;
    }
    return count;
}

fn count_resource_decls(tokens: []const lexer.Token) usize {
    var count: usize = 0;
    for (tokens, 0..) |token, idx| {
        if (token.kind == .ident and idx + 5 < tokens.len and
            tok_eq(tokens[idx + 1], "=") and tok_eq(tokens[idx + 2], "@") and
            tok_eq(tokens[idx + 3], "wasi_resource") and tok_eq(tokens[idx + 4], "(") and
            tokens[idx + 5].kind == .string) count += 1;
    }
    return count;
}

fn count_record_decls(tokens: []const lexer.Token, name: []const u8) usize {
    var count: usize = 0;
    for (tokens, 0..) |token, idx| {
        if (idx + 1 < tokens.len and tok_eq(token, name) and tok_eq(tokens[idx + 1], "{")) count += 1;
    }
    return count;
}

fn count_error_decls(tokens: []const lexer.Token, name: []const u8) usize {
    var count: usize = 0;
    for (tokens, 0..) |token, idx| {
        if (idx + 2 < tokens.len and tok_eq(token, name) and tok_eq(tokens[idx + 1], "error") and
            tok_eq(tokens[idx + 2], "=")) count += 1;
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
            (tok_eq(tokens[idx + 1], "=") and !previous_is_at and
                !(tok_eq(tokens[idx], "error") and previous_is_ident)) or
            (tok_eq(tokens[idx + 1], "{") and !previous_is_at) or
            (tok_eq(tokens[idx + 1], "(") and !previous_is_at) or
            tok_eq(tokens[idx + 1], "error");
        if (is_declaration_head) count += 1;
    }
    return count;
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
        if (depth == 0 and tokens[idx].kind == .ident and tok_eq(tokens[idx + 1], "(") and
            (idx == 0 or !tok_eq(tokens[idx - 1], "@"))) count += 1;
    }
    return count;
}

fn count_named_functions(tokens: []const lexer.Token, name: []const u8) usize {
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

fn source_signature_is_exact(tokens: []const lexer.Token, open: usize) bool {
    const close = find_matching(tokens, open, "(", ")") orelse return false;
    return close == open + 2 and tok_eq(tokens[open + 1], "u32") and close + 3 < tokens.len and
        tok_eq(tokens[close + 1], "-") and tok_eq(tokens[close + 2], ">") and
        tok_eq(tokens[close + 3], "Ticket");
}

fn sink_signature_is_exact(tokens: []const lexer.Token, open: usize) bool {
    const close = find_matching(tokens, open, "(", ")") orelse return false;
    return close == open + 5 and tok_eq(tokens[open + 1], "StreamWriter") and
        tok_eq(tokens[open + 2], "<") and tok_eq(tokens[open + 3], "TwoListEntry") and
        tok_eq(tokens[open + 4], ">") and tok_eq(tokens[close + 1], "-") and
        tok_eq(tokens[close + 2], ">") and tok_eq(tokens[close + 3], "Result") and
        tok_eq(tokens[close + 4], "<") and tok_eq(tokens[close + 5], "nil") and
        tok_eq(tokens[close + 6], ",") and tok_eq(tokens[close + 7], "ProducerError") and
        tok_eq(tokens[close + 8], ">");
}

fn find_record_decl(tokens: []const lexer.Token, name: []const u8) bool {
    var idx: usize = 0;
    while (idx + 14 < tokens.len) : (idx += 1) {
        if (!tok_eq(tokens[idx], name) or !tok_eq(tokens[idx + 1], "{") or
            !tok_eq(tokens[idx + 2], ".first") or !tok_eq(tokens[idx + 3], "[") or
            !tok_eq(tokens[idx + 4], "u32") or !tok_eq(tokens[idx + 5], "]") or
            !tok_eq(tokens[idx + 6], ".second") or !tok_eq(tokens[idx + 7], "[") or
            !tok_eq(tokens[idx + 8], "u32") or !tok_eq(tokens[idx + 9], "]") or
            !tok_eq(tokens[idx + 10], ".ticket") or !tok_eq(tokens[idx + 11], "Ticket") or
            !tok_eq(tokens[idx + 12], "}")) continue;
        return true;
    }
    return false;
}

fn find_error_decl(tokens: []const lexer.Token, name: []const u8) bool {
    var idx: usize = 0;
    while (idx + 8 < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], name) and tok_eq(tokens[idx + 1], "error") and
            tok_eq(tokens[idx + 2], "=") and tok_eq(tokens[idx + 3], "Io") and
            tok_eq(tokens[idx + 4], "|") and tok_eq(tokens[idx + 5], "Pipe") and
            tok_eq(tokens[idx + 6], "|") and tok_eq(tokens[idx + 7], "InvalidMode")) return true;
    }
    return false;
}

fn find_producer_function(tokens: []const lexer.Token, name: []const u8, error_name: []const u8) bool {
    var idx: usize = 0;
    while (idx + 10 < tokens.len) : (idx += 1) {
        if (!tok_eq(tokens[idx], name) or !tok_eq(tokens[idx + 1], "(")) continue;
        const params_close = find_matching(tokens, idx + 1, "(", ")") orelse continue;
        if (params_close != idx + 4 or !tok_eq(tokens[idx + 2], "mode") or
            !tok_eq(tokens[idx + 3], "u32") or !tok_eq(tokens[params_close + 1], "-") or
            !tok_eq(tokens[params_close + 2], ">") or !tok_eq(tokens[params_close + 3], "Result") or
            !tok_eq(tokens[params_close + 4], "<") or !tok_eq(tokens[params_close + 5], "nil") or
            !tok_eq(tokens[params_close + 6], ",") or !tok_eq(tokens[params_close + 7], error_name) or
            !tok_eq(tokens[params_close + 8], ">") or !tok_eq(tokens[params_close + 9], "{")) continue;
        const body_close = find_matching(tokens, params_close + 9, "{", "}") orelse continue;
        return body_close == params_close + 14 and tok_eq(tokens[params_close + 10], "return") and
            tok_eq(tokens[params_close + 11], "Ok") and tok_eq(tokens[params_close + 12], "(") and
            tok_eq(tokens[params_close + 13], ")");
    }
    return false;
}

fn find_empty_start(tokens: []const lexer.Token) bool {
    var idx: usize = 0;
    while (idx + 4 < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], "start") and tok_eq(tokens[idx + 1], "(") and
            tok_eq(tokens[idx + 2], ")") and tok_eq(tokens[idx + 3], "{") and
            tok_eq(tokens[idx + 4], "}")) return true;
    }
    return false;
}

fn resource_decl_is_exact(tokens: []const lexer.Token, name: []const u8, path: []const u8) bool {
    var idx: usize = 0;
    while (idx + 12 < tokens.len) : (idx += 1) {
        if (!tok_eq(tokens[idx], name) or !tok_eq(tokens[idx + 1], "=") or
            !tok_eq(tokens[idx + 2], "@") or !tok_eq(tokens[idx + 3], "wasi_resource") or
            !tok_eq(tokens[idx + 4], "(") or tokens[idx + 5].kind != .string or
            !std.mem.eql(u8, string_body(tokens[idx + 5].lexeme) orelse return false, path) or
            !tok_eq(tokens[idx + 6], ",") or !tok_eq(tokens[idx + 7], "{") or
            !tok_eq(tokens[idx + 8], ".id") or !tok_eq(tokens[idx + 9], "i64") or
            !tok_eq(tokens[idx + 10], "}") or !tok_eq(tokens[idx + 11], ")")) continue;
        return true;
    }
    return false;
}

fn find_resource_decl(tokens: []const lexer.Token) ?ResourceDecl {
    var idx: usize = 0;
    while (idx + 6 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or
            !tok_eq(tokens[idx + 2], "@") or !tok_eq(tokens[idx + 3], "wasi_resource") or
            !tok_eq(tokens[idx + 4], "(") or tokens[idx + 5].kind != .string) continue;
        return .{ .name = tokens[idx].lexeme, .path = string_body(tokens[idx + 5].lexeme) orelse continue };
    }
    return null;
}

fn find_matching(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8) ?usize {
    if (open_idx >= tokens.len or !tok_eq(tokens[open_idx], open)) return null;
    var depth: usize = 0;
    for (tokens[open_idx..], 0..) |token, offset| {
        if (tok_eq(token, open)) depth += 1;
        if (tok_eq(token, close)) {
            if (depth == 0) return null;
            depth -= 1;
            if (depth == 0) return open_idx + offset;
        }
    }
    return null;
}

fn string_body(lexeme: []const u8) ?[]const u8 {
    if (lexeme.len < 2 or lexeme[0] != '"' or lexeme[lexeme.len - 1] != '"') return null;
    return lexeme[1 .. lexeme.len - 1];
}

fn field_matches(field: p3_async_manifest.RecordField, name: []const u8, core_type: []const u8, offset: u32) bool {
    return std.mem.eql(u8, field.name, name) and std.mem.eql(u8, field.core_type, core_type) and field.offset == offset;
}

fn tok_eq(token: lexer.Token, expected: []const u8) bool {
    return std.mem.eql(u8, token.lexeme, expected);
}
