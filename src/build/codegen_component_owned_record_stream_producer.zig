const std = @import("std");
const generated_text = @import("codegen_text.zig");
const lexer = @import("lexer.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");
const wit_abi_layout = @import("wit_abi_layout.zig");
const wit_abi_types = @import("wit_abi_types.zig");

const canonical_core_wat = @embedFile("owned_record_stream_producer_template.wat");

pub const ProducerError = error{UnsupportedP3OwnedRecordStreamProducer};

pub const OwnedRecordStreamProducerPlan = struct {
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

    pub fn analyze(
        tokens: []const lexer.Token,
        registry: p3_async_manifest.Registry,
    ) ProducerError!OwnedRecordStreamProducerPlan {
        const descriptor = registry.find("do:g6-2-owned-record-producer@0.1.0", "consume-via-stream") orelse
            return error.UnsupportedP3OwnedRecordStreamProducer;
        const shape = switch (p3_async_manifest.lowering_shape(descriptor) orelse return error.UnsupportedP3OwnedRecordStreamProducer) {
            .owned_record_stream_producer => |value| value,
            else => return error.UnsupportedP3OwnedRecordStreamProducer,
        };

        const source = find_host_binding(tokens, .source) orelse return error.UnsupportedP3OwnedRecordStreamProducer;
        const sink = find_host_binding(tokens, .sink) orelse return error.UnsupportedP3OwnedRecordStreamProducer;
        if (count_host_bindings(tokens) != 2 or
            !std.mem.eql(u8, source.locator, "do:g6-2-owned-record-producer/source@0.1.0") or
            !std.mem.eql(u8, source.member, "make-ticket") or
            !source_signature_is_exact(tokens, source.signature_open) or
            !std.mem.eql(u8, sink.locator, descriptor.locator) or
            !std.mem.eql(u8, sink.member, descriptor.member) or
            !sink_signature_is_exact(tokens, sink.signature_open)) return error.UnsupportedP3OwnedRecordStreamProducer;

        const ticket = find_resource_decl(tokens) orelse return error.UnsupportedP3OwnedRecordStreamProducer;
        if (count_resource_decls(tokens) != 1 or
            !std.mem.eql(u8, ticket.name, "Ticket") or
            !std.mem.eql(u8, ticket.path, "do:g6-2-owned-record-producer/source/ticket") or
            !resource_decl_is_exact(tokens, "Ticket", ticket.path)) return error.UnsupportedP3OwnedRecordStreamProducer;
        if (count_record_decls(tokens, "ResourceEntry") != 1 or
            !find_record_decl(tokens, "ResourceEntry", "Ticket") or
            !find_error_decl(tokens, "ProducerError") or
            count_error_decls(tokens, "ProducerError") != 1 or
            !find_producer_function(tokens, "produce", "ProducerError") or
            !find_empty_start(tokens)) return error.UnsupportedP3OwnedRecordStreamProducer;
        if (count_top_level_declarations(tokens) != 7 or
            count_top_level_functions(tokens) != 2 or
            count_named_functions(tokens, "produce") != 1 or
            count_named_functions(tokens, "start") != 1 or
            count_token_pair(tokens, "async") != 0 or
            count_intrinsic(tokens, "async") != 0 or
            count_intrinsic(tokens, "await") != 0 or
            count_intrinsic(tokens, "cancel") != 0) return error.UnsupportedP3OwnedRecordStreamProducer;

        if (!std.mem.eql(u8, shape.element, "resource-entry") or
            shape.record_layout.byte_size != 4 or
            shape.record_layout.fields.len != 1 or
            shape.record_layout.source_fields.len != 1 or
            !std.mem.eql(u8, shape.record_layout.name, "resource-entry") or
            !std.mem.eql(u8, shape.record_layout.fields[0].name, "ticket") or
            !std.mem.eql(u8, shape.record_layout.fields[0].core_type, "i32") or
            shape.record_layout.fields[0].offset != 0 or
            !std.mem.eql(u8, shape.record_layout.source_fields[0].name, "ticket") or
            !std.mem.eql(u8, shape.record_layout.source_fields[0].source_type, "ticket") or
            shape.record_layout.source_fields[0].ownership != .own or
            shape.record_layout.source_fields[0].resource == null or
            !std.mem.eql(u8, shape.record_layout.source_fields[0].resource.?, "ticket") or
            shape.record_layout.source_fields[0].drop_import == null or
            !std.mem.eql(u8, shape.record_layout.source_fields[0].drop_import.?, "[resource-drop]ticket") or
            shape.producer.stream_capacity != 1 or
            !std.mem.eql(u8, shape.producer.source_module, "do:g6-2-owned-record-producer/source@0.1.0") or
            !std.mem.eql(u8, shape.producer.source_import_name, "make-ticket") or
            !std.mem.eql(u8, shape.producer.resource_drop_import, "[resource-drop]ticket") or
            !std.mem.eql(u8, shape.producer.terminal, "task-return") or
            shape.producer.runtime_count_param != null or
            shape.producer.runtime_max != null or
            shape.producer.runtime_mode_param == null or
            !std.mem.eql(u8, shape.producer.runtime_mode_param.?, "u32") or
            shape.producer.batch_count != null or
            shape.producer.batch_lengths != null) return error.UnsupportedP3OwnedRecordStreamProducer;

        return .{
            .descriptor = descriptor,
            .source_host_name = source.name,
            .sink_host_name = sink.name,
            .ticket_type_name = ticket.name,
            .record_type_name = "ResourceEntry",
            .error_type_name = "ProducerError",
            .root_name = "produce",
            .mode_name = "mode",
            .layout = shape.record_layout,
            .producer = shape.producer,
        };
    }
};

const BindingKind = enum { source, sink };

const HostBinding = struct {
    name: []const u8,
    locator: []const u8,
    member: []const u8,
    signature_open: usize,
    kind: BindingKind,
};

const ResourceDecl = struct { name: []const u8, path: []const u8 };

pub fn emit_component_wat(allocator: std.mem.Allocator, plan: OwnedRecordStreamProducerPlan) ![]u8 {
    try validate_internal_plans(allocator, plan);
    if (plan.layout.byte_size != 4 or plan.layout.fields.len != 1 or
        plan.layout.fields[0].offset != 0 or plan.producer.stream_capacity != 1 or
        !std.mem.eql(u8, plan.layout.fields[0].name, "ticket")) return error.UnsupportedP3OwnedRecordStreamProducer;

    const wat = try generated_text.alloc_block(allocator, 0, canonical_core_wat);
    if (std.mem.indexOf(u8, wat, "__arc_") != null) {
        allocator.free(wat);
        return error.UnsupportedP3OwnedRecordStreamProducer;
    }
    return wat;
}

pub fn emit_component_wat_for_tokens(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]u8 {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    const plan = try OwnedRecordStreamProducerPlan.analyze(tokens, registry);
    return emit_component_wat(allocator, plan);
}

pub fn emit_component_wit(allocator: std.mem.Allocator, plan: OwnedRecordStreamProducerPlan) ![]u8 {
    try validate_internal_plans(allocator, plan);
    if (!std.mem.eql(u8, plan.descriptor.wit.world, "owned-record-producer")) {
        return error.UnsupportedP3OwnedRecordStreamProducer;
    }
    return generated_text.alloc_block(allocator, 0,
        \\package do:g6-2-owned-record-producer@0.1.0;
        \\
        \\interface types {
        \\  enum error-code { io, pipe, invalid-mode }
        \\  resource ticket {}
        \\  record resource-entry { ticket: own<ticket> }
        \\}
        \\
        \\interface source {
        \\  use types.{ticket};
        \\  make-ticket: func(seed: u32) -> own<ticket>;
        \\}
        \\
        \\interface sink {
        \\  use types.{error-code, resource-entry};
        \\  consume-via-stream: async func(
        \\    data: stream<resource-entry>
        \\  ) -> result<_, error-code>;
        \\}
        \\
        \\world owned-record-producer {
        \\  use types.{error-code};
        \\  import source;
        \\  import sink;
        \\  export produce: async func(mode: u32) -> result<_, error-code>;
        \\}
        \\
    );
}

pub fn emit_component_wit_for_tokens(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]u8 {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    const plan = try OwnedRecordStreamProducerPlan.analyze(tokens, registry);
    return emit_component_wit(allocator, plan);
}

fn validate_internal_plans(allocator: std.mem.Allocator, plan: OwnedRecordStreamProducerPlan) ProducerError!void {
    var ticket = wit_abi_types.AbiType.resource(allocator, "ticket", .own) catch return error.UnsupportedP3OwnedRecordStreamProducer;
    defer ticket.deinit();
    var entry = wit_abi_types.AbiType.record(allocator, &.{
        .{ .name = "ticket", .value = &ticket },
    }) catch return error.UnsupportedP3OwnedRecordStreamProducer;
    defer entry.deinit();

    var layout = wit_abi_layout.LayoutPlan.record(allocator, &entry, .{
        .byte_size = plan.layout.byte_size,
        .alignment = 4,
        .fields = &.{.{
            .name = "ticket",
            .offset = 0,
            .byte_size = 4,
            .alignment = 4,
            .indirect = null,
        }},
    }) catch return error.UnsupportedP3OwnedRecordStreamProducer;
    defer layout.deinit();
    if (layout.byte_size != 4 or layout.alignment != 4 or layout.record_fields.len != 1 or
        layout.record_fields[0].offset != 0 or !std.mem.eql(u8, layout.record_fields[0].name, "ticket")) {
        return error.UnsupportedP3OwnedRecordStreamProducer;
    }
}

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
            .kind = kind,
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
            (tok_eq(tokens[idx + 1], "=") and !previous_is_at and
                !(tok_eq(tokens[idx], "error") and previous_is_ident)) or
            (tok_eq(tokens[idx + 1], "{") and !previous_is_at) or
            (tok_eq(tokens[idx + 1], "(") and !previous_is_at) or
            tok_eq(tokens[idx + 1], "error");
        if (is_declaration_head) {
            count += 1;
        }
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
        tok_eq(tokens[open + 3], "ResourceEntry") and tok_eq(tokens[open + 4], ">") and
        tok_eq(tokens[close + 1], "-") and tok_eq(tokens[close + 2], ">") and
        tok_eq(tokens[close + 3], "Result") and tok_eq(tokens[close + 4], "<") and tok_eq(tokens[close + 5], "nil") and
        tok_eq(tokens[close + 6], ",") and tok_eq(tokens[close + 7], "ProducerError") and tok_eq(tokens[close + 8], ">");
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
            !tok_eq(tokens[idx + 3], "wasi_resource") or !tok_eq(tokens[idx + 4], "(") or
            tokens[idx + 5].kind != .string or !std.mem.eql(u8, string_body(tokens[idx + 5].lexeme) orelse return false, path) or
            !tok_eq(tokens[idx + 6], ",") or !tok_eq(tokens[idx + 7], "{") or !tok_eq(tokens[idx + 8], ".id") or
            !tok_eq(tokens[idx + 9], "i64") or !tok_eq(tokens[idx + 10], "}") or !tok_eq(tokens[idx + 11], ")")) continue;
        return true;
    }
    return false;
}

fn find_record_decl(tokens: []const lexer.Token, name: []const u8, field_type: []const u8) bool {
    var idx: usize = 0;
    while (idx + 5 < tokens.len) : (idx += 1) {
        if (!tok_eq(tokens[idx], name) or !tok_eq(tokens[idx + 1], "{") or !tok_eq(tokens[idx + 2], ".ticket") or
            !tok_eq(tokens[idx + 3], field_type) or !tok_eq(tokens[idx + 4], "}")) continue;
        return true;
    }
    return false;
}

fn find_error_decl(tokens: []const lexer.Token, name: []const u8) bool {
    var idx: usize = 0;
    while (idx + 8 < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], name) and tok_eq(tokens[idx + 1], "error") and tok_eq(tokens[idx + 2], "=") and
            tok_eq(tokens[idx + 3], "Io") and tok_eq(tokens[idx + 4], "|") and tok_eq(tokens[idx + 5], "Pipe") and
            tok_eq(tokens[idx + 6], "|") and tok_eq(tokens[idx + 7], "InvalidMode")) return true;
    }
    return false;
}

fn find_producer_function(tokens: []const lexer.Token, name: []const u8, error_name: []const u8) bool {
    var idx: usize = 0;
    while (idx + 10 < tokens.len) : (idx += 1) {
        if (!tok_eq(tokens[idx], name) or !tok_eq(tokens[idx + 1], "(")) continue;
        const params_close = find_matching(tokens, idx + 1, "(", ")") orelse continue;
        if (params_close != idx + 4 or !tok_eq(tokens[idx + 2], "mode") or !tok_eq(tokens[idx + 3], "u32") or
            !tok_eq(tokens[params_close + 1], "-") or !tok_eq(tokens[params_close + 2], ">") or
            !tok_eq(tokens[params_close + 3], "Result") or !tok_eq(tokens[params_close + 4], "<") or
            !tok_eq(tokens[params_close + 5], "nil") or !tok_eq(tokens[params_close + 6], ",") or
            !tok_eq(tokens[params_close + 7], error_name) or !tok_eq(tokens[params_close + 8], ">") or
            !tok_eq(tokens[params_close + 9], "{")) continue;
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
        if (tok_eq(tokens[idx], "start") and tok_eq(tokens[idx + 1], "(") and tok_eq(tokens[idx + 2], ")") and
            tok_eq(tokens[idx + 3], "{") and tok_eq(tokens[idx + 4], "}")) return true;
    }
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
        if (depth == 0 and tokens[idx].kind == .ident and tok_eq(tokens[idx + 1], "(") and
            (idx == 0 or !tok_eq(tokens[idx - 1], "@"))) count += 1;
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

fn count_token_pair(tokens: []const lexer.Token, name: []const u8) usize {
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

fn string_body(lexeme: []const u8) ?[]const u8 {
    if (lexeme.len < 2 or lexeme[0] != '"' or lexeme[lexeme.len - 1] != '"') return null;
    return lexeme[1 .. lexeme.len - 1];
}

fn tok_eq(token: lexer.Token, expected: []const u8) bool {
    return std.mem.eql(u8, token.lexeme, expected);
}

const exact_source =
    \\make_ticket = @host_func("do:g6-2-owned-record-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
    \\consume = @host_async_func("do:g6-2-owned-record-producer@0.1.0", "consume-via-stream", (StreamWriter<ResourceEntry>) -> Result<nil, ProducerError>)
    \\Ticket = @wasi_resource("do:g6-2-owned-record-producer/source/ticket", { .id i64 })
    \\ResourceEntry { .ticket Ticket }
    \\ProducerError error = Io | Pipe | InvalidMode
    \\produce(mode u32) -> Result<nil, ProducerError> {
    \\    return Ok()
    \\}
    \\start() {}
;

fn expect_plan_error(source: []const u8) !void {
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectError(
        error.UnsupportedP3OwnedRecordStreamProducer,
        OwnedRecordStreamProducerPlan.analyze(tokens, registry),
    );
}

test "owned record producer plan accepts the exact Do source" {
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const tokens = try lexer.tokenize(std.testing.allocator, exact_source);
    defer std.testing.allocator.free(tokens);

    const plan = try OwnedRecordStreamProducerPlan.analyze(tokens, registry);
    try std.testing.expectEqualStrings("make_ticket", plan.source_host_name);
    try std.testing.expectEqualStrings("consume", plan.sink_host_name);
    try std.testing.expectEqualStrings("Ticket", plan.ticket_type_name);
    try std.testing.expectEqualStrings("ResourceEntry", plan.record_type_name);
    try std.testing.expectEqualStrings("ProducerError", plan.error_type_name);
    try std.testing.expectEqualStrings("produce", plan.root_name);
    try std.testing.expectEqualStrings("mode", plan.mode_name);
    try std.testing.expectEqual(@as(u32, 4), plan.layout.byte_size);
    try std.testing.expectEqual(@as(u32, 1), plan.producer.stream_capacity);
}

test "owned record producer emitter preserves the pinned direct-record contracts" {
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const tokens = try lexer.tokenize(std.testing.allocator, exact_source);
    defer std.testing.allocator.free(tokens);

    const plan = try OwnedRecordStreamProducerPlan.analyze(tokens, registry);
    const wat = try emit_component_wat(std.testing.allocator, plan);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[producer-record-byte-size] 4") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[producer-record-transfer]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[producer-resource-drop-exactly-once]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);

    const wit = try emit_component_wit(std.testing.allocator, plan);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "package do:g6-2-owned-record-producer@0.1.0;\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "data: stream<resource-entry>\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "world owned-record-producer") != null);
}

test "owned record producer plan rejects list-shaped sink" {
    try expect_plan_error(
        \\make_ticket = @host_func("do:g6-2-owned-record-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
        \\consume = @host_async_func("do:g6-2-owned-record-producer@0.1.0", "consume-via-stream", (StreamWriter<[ResourceEntry]>) -> Result<nil, ProducerError>)
        \\Ticket = @wasi_resource("do:g6-2-owned-record-producer/source/ticket", { .id i64 })
        \\ResourceEntry { .ticket Ticket }
        \\ProducerError error = Io | Pipe | InvalidMode
        \\produce(mode u32) -> Result<nil, ProducerError> { return Ok() }
        \\start() {}
    );
}

test "owned record producer plan rejects an unrelated record element" {
    try expect_plan_error(
        \\make_ticket = @host_func("do:g6-2-owned-record-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
        \\consume = @host_async_func("do:g6-2-owned-record-producer@0.1.0", "consume-via-stream", (StreamWriter<OtherEntry>) -> Result<nil, ProducerError>)
        \\Ticket = @wasi_resource("do:g6-2-owned-record-producer/source/ticket", { .id i64 })
        \\ResourceEntry { .ticket Ticket }
        \\OtherEntry { .ticket Ticket }
        \\ProducerError error = Io | Pipe | InvalidMode
        \\produce(mode u32) -> Result<nil, ProducerError> { return Ok() }
        \\start() {}
    );
}

test "owned record producer plan rejects a borrowed record field" {
    try expect_plan_error(
        \\make_ticket = @host_func("do:g6-2-owned-record-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
        \\consume = @host_async_func("do:g6-2-owned-record-producer@0.1.0", "consume-via-stream", (StreamWriter<ResourceEntry>) -> Result<nil, ProducerError>)
        \\Ticket = @wasi_resource("do:g6-2-owned-record-producer/source/ticket", { .id i64 })
        \\ResourceEntry { .ticket borrow<Ticket> }
        \\ProducerError error = Io | Pipe | InvalidMode
        \\produce(mode u32) -> Result<nil, ProducerError> { return Ok() }
        \\start() {}
    );
}

test "owned record producer plan rejects a second host binding" {
    try expect_plan_error(
        \\make_ticket = @host_func("do:g6-2-owned-record-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
        \\consume = @host_async_func("do:g6-2-owned-record-producer@0.1.0", "consume-via-stream", (StreamWriter<ResourceEntry>) -> Result<nil, ProducerError>)
        \\extra = @host_func("env", "extra", () -> nil)
        \\Ticket = @wasi_resource("do:g6-2-owned-record-producer/source/ticket", { .id i64 })
        \\ResourceEntry { .ticket Ticket }
        \\ProducerError error = Io | Pipe | InvalidMode
        \\produce(mode u32) -> Result<nil, ProducerError> { return Ok() }
        \\start() {}
    );
}

test "owned record producer plan rejects a changed resource path" {
    try expect_plan_error(
        \\make_ticket = @host_func("do:g6-2-owned-record-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
        \\consume = @host_async_func("do:g6-2-owned-record-producer@0.1.0", "consume-via-stream", (StreamWriter<ResourceEntry>) -> Result<nil, ProducerError>)
        \\Ticket = @wasi_resource("do:g6-2-owned-record-producer/source/other-ticket", { .id i64 })
        \\ResourceEntry { .ticket Ticket }
        \\ProducerError error = Io | Pipe | InvalidMode
        \\produce(mode u32) -> Result<nil, ProducerError> { return Ok() }
        \\start() {}
    );
}

test "owned record producer plan rejects an async ticket source" {
    try expect_plan_error(
        \\make_ticket = @host_async_func("do:g6-2-owned-record-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
        \\consume = @host_async_func("do:g6-2-owned-record-producer@0.1.0", "consume-via-stream", (StreamWriter<ResourceEntry>) -> Result<nil, ProducerError>)
        \\Ticket = @wasi_resource("do:g6-2-owned-record-producer/source/ticket", { .id i64 })
        \\ResourceEntry { .ticket Ticket }
        \\ProducerError error = Io | Pipe | InvalidMode
        \\produce(mode u32) -> Result<nil, ProducerError> { return Ok() }
        \\start() {}
    );
}

test "owned record producer plan rejects a non-sentinel producer body" {
    try expect_plan_error(
        \\make_ticket = @host_func("do:g6-2-owned-record-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
        \\consume = @host_async_func("do:g6-2-owned-record-producer@0.1.0", "consume-via-stream", (StreamWriter<ResourceEntry>) -> Result<nil, ProducerError>)
        \\Ticket = @wasi_resource("do:g6-2-owned-record-producer/source/ticket", { .id i64 })
        \\ResourceEntry { .ticket Ticket }
        \\ProducerError error = Io | Pipe | InvalidMode
        \\produce(mode u32) -> Result<nil, ProducerError> { return Err(Io) }
        \\start() {}
    );
}

test "owned record producer plan rejects an await intrinsic" {
    try expect_plan_error(
        \\make_ticket = @host_func("do:g6-2-owned-record-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
        \\consume = @host_async_func("do:g6-2-owned-record-producer@0.1.0", "consume-via-stream", (StreamWriter<ResourceEntry>) -> Result<nil, ProducerError>)
        \\Ticket = @wasi_resource("do:g6-2-owned-record-producer/source/ticket", { .id i64 })
        \\ResourceEntry { .ticket Ticket }
        \\ProducerError error = Io | Pipe | InvalidMode
        \\produce(mode u32) -> Result<nil, ProducerError> { return Ok() }
        \\start() { @await(mode) }
    );
}
