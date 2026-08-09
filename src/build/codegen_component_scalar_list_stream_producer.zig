const std = @import("std");
const lexer = @import("lexer.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");
const wit_abi_layout = @import("wit_abi_layout.zig");
const wit_abi_types = @import("wit_abi_types.zig");

const canonical_core_wat = @embedFile("cmin_scalar_list_stream_producer_template.wat");

pub const ProducerError = error{UnsupportedP3ScalarListProducer};

pub const ScalarListStreamProducerPlan = struct {
    descriptor: p3_async_manifest.Descriptor,
    sink_binding_name: []const u8,
    root_name: []const u8,
    count_name: []const u8,
    layout: p3_async_manifest.ScalarListLayout,
    producer: p3_async_manifest.ScalarListProducerCanonical,

    pub fn analyze(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) ProducerError!ScalarListStreamProducerPlan {
        const descriptor = registry.find("do:g6-2-scalar-list-producer@0.1.0", "consume-via-stream") orelse
            return error.UnsupportedP3ScalarListProducer;
        const shape = switch (p3_async_manifest.lowering_shape(descriptor) orelse return error.UnsupportedP3ScalarListProducer) {
            .scalar_list_stream_producer => |value| value,
            else => return error.UnsupportedP3ScalarListProducer,
        };

        const sink = find_sink_binding(tokens) orelse return error.UnsupportedP3ScalarListProducer;
        if (count_host_bindings(tokens) != 1 or
            !std.mem.eql(u8, sink.locator, descriptor.locator) or
            !std.mem.eql(u8, sink.member, descriptor.member) or
            !sink_signature_is_exact(tokens, sink.signature_open) or
            !find_error_decl(tokens, "ProducerError") or
            !find_producer_function(tokens) or
            !find_empty_start(tokens) or
            count_top_level_functions(tokens) != 2 or
            count_named_functions(tokens, "produce") != 1 or
            count_named_functions(tokens, "start") != 1 or
            count_token(tokens, "async") != 0 or
            count_intrinsic(tokens, "async") != 0 or
            count_intrinsic(tokens, "await") != 0 or
            count_intrinsic(tokens, "cancel") != 0) return error.UnsupportedP3ScalarListProducer;

        if (!std.mem.eql(u8, shape.element, "list<u32>") or
            shape.list_layout.result_pointer_offset != 64 or
            shape.list_layout.result_length_offset != 68 or
            shape.list_layout.element_stride != 4 or
            shape.list_layout.max_items != 3 or
            shape.producer.stream_capacity != 1 or
            !std.mem.eql(u8, shape.producer.runtime_count_param, "u32") or
            shape.producer.runtime_max != 3 or
            !std.mem.eql(u8, shape.producer.terminal, "task-return")) return error.UnsupportedP3ScalarListProducer;

        return .{
            .descriptor = descriptor,
            .sink_binding_name = sink.name,
            .root_name = "produce",
            .count_name = "count",
            .layout = shape.list_layout,
            .producer = shape.producer,
        };
    }
};

const SinkBinding = struct {
    name: []const u8,
    locator: []const u8,
    member: []const u8,
    signature_open: usize,
};

pub fn emit_component_wat(allocator: std.mem.Allocator, plan: ScalarListStreamProducerPlan) ![]u8 {
    try validate_internal_plans(allocator, plan);
    if (plan.layout.result_pointer_offset != 64 or plan.layout.result_length_offset != 68 or
        plan.layout.element_stride != 4 or plan.layout.max_items != 3 or
        plan.producer.stream_capacity != 1) return error.UnsupportedP3ScalarListProducer;
    return allocator.dupe(u8, canonical_core_wat);
}

pub fn emit_component_wat_for_tokens(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]u8 {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    const plan = try ScalarListStreamProducerPlan.analyze(tokens, registry);
    return emit_component_wat(allocator, plan);
}

pub fn emit_component_wit(allocator: std.mem.Allocator, plan: ScalarListStreamProducerPlan) ![]u8 {
    try validate_internal_plans(allocator, plan);
    if (!std.mem.eql(u8, plan.descriptor.wit.world, "scalar-list-producer")) return error.UnsupportedP3ScalarListProducer;
    return allocator.dupe(
        u8,
        "package do:g6-2-scalar-list-producer@0.1.0;\n\n" ++
            "interface types {\n  enum error-code { io, pipe, invalid-mode }\n}\n\n" ++
            "interface sink {\n  use types.{error-code};\n  consume-via-stream: async func(data: stream<list<u32>>) -> result<_, error-code>;\n}\n\n" ++
            "world scalar-list-producer {\n  use types.{error-code};\n  import sink;\n  export produce: async func(count: u32) -> result<_, error-code>;\n}\n",
    );
}

pub fn emit_component_wit_for_tokens(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]u8 {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    const plan = try ScalarListStreamProducerPlan.analyze(tokens, registry);
    return emit_component_wit(allocator, plan);
}

fn validate_internal_plans(allocator: std.mem.Allocator, plan: ScalarListStreamProducerPlan) ProducerError!void {
    const accepted_lengths = [_]u32{ 0, 1, 2, 3 };
    var element = wit_abi_types.AbiType.scalar(allocator, .u32);
    defer element.deinit();
    var list = wit_abi_types.AbiType.list(allocator, &element) catch return error.UnsupportedP3ScalarListProducer;
    defer list.deinit();
    var layout = wit_abi_layout.ListLayoutPlan.init(allocator, &list, .{
        .pointer_offset = plan.layout.result_pointer_offset,
        .length_offset = plan.layout.result_length_offset,
        .element_byte_size = 4,
        .element_stride = plan.layout.element_stride,
        .element_alignment = 4,
        .ticket_offset = 0,
        .capacity = plan.layout.max_items,
        .accepted_lengths = &accepted_lengths,
        .allocation = .cabi_realloc,
        .free = .cabi_realloc,
    }) catch return error.UnsupportedP3ScalarListProducer;
    defer layout.deinit();
    for (accepted_lengths) |length| layout.validate_length(length) catch return error.UnsupportedP3ScalarListProducer;
}

fn find_sink_binding(tokens: []const lexer.Token) ?SinkBinding {
    var found: ?SinkBinding = null;
    var idx: usize = 0;
    while (idx + 10 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or !tok_eq(tokens[idx + 2], "@") or
            !tok_eq(tokens[idx + 3], "host_async_func") or !tok_eq(tokens[idx + 4], "(") or
            tokens[idx + 5].kind != .string or !tok_eq(tokens[idx + 6], ",") or tokens[idx + 7].kind != .string or
            !tok_eq(tokens[idx + 8], ",") or !tok_eq(tokens[idx + 9], "(")) continue;
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

fn sink_signature_is_exact(tokens: []const lexer.Token, open: usize) bool {
    const close = find_matching(tokens, open, "(", ")") orelse return false;
    return close == open + 7 and tok_eq(tokens[open + 1], "StreamWriter") and tok_eq(tokens[open + 2], "<") and
        tok_eq(tokens[open + 3], "[") and tok_eq(tokens[open + 4], "u32") and tok_eq(tokens[open + 5], "]") and
        tok_eq(tokens[open + 6], ">") and tok_eq(tokens[close + 1], "-") and tok_eq(tokens[close + 2], ">") and
        tok_eq(tokens[close + 3], "Result") and tok_eq(tokens[close + 4], "<") and tok_eq(tokens[close + 5], "nil") and
        tok_eq(tokens[close + 6], ",") and tok_eq(tokens[close + 7], "ProducerError") and tok_eq(tokens[close + 8], ">");
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

fn find_producer_function(tokens: []const lexer.Token) bool {
    var idx: usize = 0;
    while (idx + 14 < tokens.len) : (idx += 1) {
        if (!tok_eq(tokens[idx], "produce") or !tok_eq(tokens[idx + 1], "(") or !tok_eq(tokens[idx + 2], "count") or
            !tok_eq(tokens[idx + 3], "u32") or !tok_eq(tokens[idx + 4], ")") or !tok_eq(tokens[idx + 5], "-") or
            !tok_eq(tokens[idx + 6], ">") or !tok_eq(tokens[idx + 7], "Result") or !tok_eq(tokens[idx + 8], "<") or
            !tok_eq(tokens[idx + 9], "nil") or !tok_eq(tokens[idx + 10], ",") or !tok_eq(tokens[idx + 11], "ProducerError") or
            !tok_eq(tokens[idx + 12], ">") or !tok_eq(tokens[idx + 13], "{") or !tok_eq(tokens[idx + 14], "return")) continue;
        const close = find_matching(tokens, idx + 13, "{", "}") orelse continue;
        return close == idx + 18 and tok_eq(tokens[idx + 15], "Ok") and tok_eq(tokens[idx + 16], "(") and tok_eq(tokens[idx + 17], ")");
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

fn string_body(lexeme: []const u8) ?[]const u8 {
    if (lexeme.len < 2 or lexeme[0] != '"' or lexeme[lexeme.len - 1] != '"') return null;
    return lexeme[1 .. lexeme.len - 1];
}

fn tok_eq(token: lexer.Token, expected: []const u8) bool {
    return std.mem.eql(u8, token.lexeme, expected);
}

test "scalar list producer plan accepts the pinned source and emits scalar list ABI" {
    const source =
        \\consume = @host_async_func("do:g6-2-scalar-list-producer@0.1.0", "consume-via-stream", (StreamWriter<[u32]>) -> Result<nil, ProducerError>)
        \\ProducerError error = Io | Pipe | InvalidMode
        \\produce(count u32) -> Result<nil, ProducerError> { return Ok() }
        \\start() {}
    ;
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    const plan = try ScalarListStreamProducerPlan.analyze(tokens, registry);
    const wat = try emit_component_wat(std.testing.allocator, plan);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[producer-list-pointer]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 10") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 20") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 30") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[producer-list-transfer]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[producer-list-release-exactly-once]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[resource-drop]") == null);

    const wit = try emit_component_wit(std.testing.allocator, plan);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "package do:g6-2-scalar-list-producer@0.1.0;") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "world scalar-list-producer") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "stream<list<u32>>") != null);
}

test "scalar list producer plan rejects a different stream element" {
    const source =
        \\consume = @host_async_func("do:g6-2-scalar-list-producer@0.1.0", "consume-via-stream", (StreamWriter<[u64]>) -> Result<nil, ProducerError>)
        \\ProducerError error = Io | Pipe | InvalidMode
        \\produce(count u32) -> Result<nil, ProducerError> { return Ok() }
        \\start() {}
    ;
    try expect_plan_error(source);
}

test "scalar list producer plan rejects a non-fixed producer body" {
    const source =
        \\consume = @host_async_func("do:g6-2-scalar-list-producer@0.1.0", "consume-via-stream", (StreamWriter<[u32]>) -> Result<nil, ProducerError>)
        \\ProducerError error = Io | Pipe | InvalidMode
        \\produce(count u32) -> Result<nil, ProducerError> { selected u32 = count return Ok() }
        \\start() {}
    ;
    try expect_plan_error(source);
}

fn expect_plan_error(source: []const u8) !void {
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectError(error.UnsupportedP3ScalarListProducer, ScalarListStreamProducerPlan.analyze(tokens, registry));
}
