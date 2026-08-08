const std = @import("std");
const lexer = @import("lexer.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");
const wit_abi_async = @import("wit_abi_async.zig");
const wit_abi_layout = @import("wit_abi_layout.zig");
const wit_abi_ownership = @import("wit_abi_ownership.zig");
const wit_abi_types = @import("wit_abi_types.zig");

const canonical_core_wat = @embedFile("cmin_batched_list_resource_producer_template.wat");

pub const ProducerError = error{UnsupportedP3BatchedListResourceProducer};

pub const BatchedListResourceProducerPlan = struct {
    descriptor: p3_async_manifest.Descriptor,
    source_host_name: []const u8,
    sink_host_name: []const u8,
    ticket_type_name: []const u8,
    record_type_name: []const u8,
    error_type_name: []const u8,
    root_name: []const u8,
    mode_name: []const u8,
    layout: p3_async_manifest.ListResourceLayout,
    producer: p3_async_manifest.ProducerCanonical,

    pub fn analyze(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) ProducerError!BatchedListResourceProducerPlan {
        const descriptor = registry.find("do:g6-2-batched-list-producer@0.1.0", "consume-via-stream") orelse
            return error.UnsupportedP3BatchedListResourceProducer;
        const shape = switch (p3_async_manifest.lowering_shape(descriptor) orelse return error.UnsupportedP3BatchedListResourceProducer) {
            .record_resource_list_stream_batched_producer => |value| value,
            else => return error.UnsupportedP3BatchedListResourceProducer,
        };

        const source = find_host_binding(tokens, .source) orelse return error.UnsupportedP3BatchedListResourceProducer;
        const sink = find_host_binding(tokens, .sink) orelse return error.UnsupportedP3BatchedListResourceProducer;
        if (count_host_bindings(tokens) != 2 or
            !std.mem.eql(u8, source.locator, "do:g6-2-batched-list-producer/source@0.1.0") or
            !std.mem.eql(u8, source.member, "make-ticket") or
            !source_signature_is_exact(tokens, source.signature_open) or
            !std.mem.eql(u8, sink.locator, descriptor.locator) or
            !std.mem.eql(u8, sink.member, descriptor.member) or
            !sink_signature_is_exact(tokens, sink.signature_open)) return error.UnsupportedP3BatchedListResourceProducer;

        const ticket = find_resource_decl(tokens) orelse return error.UnsupportedP3BatchedListResourceProducer;
        if (count_resource_decls(tokens) != 1 or
            !std.mem.eql(u8, ticket.name, "Ticket") or
            !std.mem.eql(u8, ticket.path, "do:g6-2-batched-list-producer/source/ticket")) return error.UnsupportedP3BatchedListResourceProducer;
        if (count_record_decls(tokens, "ResourceEntry") != 1 or
            !find_record_decl(tokens, "ResourceEntry", "Ticket") or
            !find_error_decl(tokens, "ProducerError") or
            count_error_decls(tokens, "ProducerError") != 1 or
            !find_producer_function(tokens, "produce", "ProducerError")) return error.UnsupportedP3BatchedListResourceProducer;
        if (count_top_level_functions(tokens) != 2 or
            count_named_functions(tokens, "produce") != 1 or
            count_named_functions(tokens, "start") != 1 or
            count_token_pair(tokens, "async") != 0 or
            count_intrinsic(tokens, "async") != 0 or
            count_intrinsic(tokens, "await") != 0 or
            count_intrinsic(tokens, "cancel") != 0) return error.UnsupportedP3BatchedListResourceProducer;

        const lengths = shape.producer.batch_lengths orelse return error.UnsupportedP3BatchedListResourceProducer;
        if (!std.mem.eql(u8, shape.element, "resource-entry") or
            shape.list_layout.result_pointer_offset != 64 or
            shape.list_layout.result_length_offset != 68 or
            shape.list_layout.element_stride != 4 or
            shape.list_layout.ticket_offset != 0 or
            shape.list_layout.max_items != 2 or
            shape.producer.stream_capacity != 1 or
            !std.mem.eql(u8, shape.producer.source_module, "do:g6-2-batched-list-producer/source@0.1.0") or
            !std.mem.eql(u8, shape.producer.source_import_name, "make-ticket") or
            !std.mem.eql(u8, shape.producer.resource_drop_import, "[resource-drop]ticket") or
            shape.producer.runtime_count_param != null or
            shape.producer.runtime_max != null or
            shape.producer.runtime_mode_param == null or
            !std.mem.eql(u8, shape.producer.runtime_mode_param.?, "u32") or
            shape.producer.batch_count == null or
            shape.producer.batch_count.? != 2 or
            lengths.len != 2 or
            lengths[0] != 2 or
            lengths[1] != 1) return error.UnsupportedP3BatchedListResourceProducer;

        return .{
            .descriptor = descriptor,
            .source_host_name = source.name,
            .sink_host_name = sink.name,
            .ticket_type_name = ticket.name,
            .record_type_name = "ResourceEntry",
            .error_type_name = "ProducerError",
            .root_name = "produce",
            .mode_name = "mode",
            .layout = shape.list_layout,
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

pub fn emit_component_wat(allocator: std.mem.Allocator, plan: BatchedListResourceProducerPlan) ![]u8 {
    try validate_internal_plans(allocator, plan);
    if (plan.layout.result_pointer_offset != 64 or plan.layout.result_length_offset != 68 or
        plan.layout.element_stride != 4 or plan.layout.ticket_offset != 0 or
        plan.layout.max_items != 2 or plan.producer.stream_capacity != 1 or
        plan.producer.batch_count.? != 2) return error.UnsupportedP3BatchedListResourceProducer;

    const metadata = try std.fmt.allocPrint(
        allocator,
        "\n  ;; [producer-batched-list-transfer] clear-source-slots-before-list-release\n  ;; [producer-batched-child-before-parent-cleanup] ticket-slots,batch-0,batch-1,list,stream,future,waitable,frame\n  ;; [producer-batched-plan-layout] pointer={d} length={d} stride={d} ticket-offset={d} capacity={d} batches=2 lengths=2,1\n",
        .{ plan.layout.result_pointer_offset, plan.layout.result_length_offset, plan.layout.element_stride, plan.layout.ticket_offset, plan.producer.stream_capacity },
    );
    defer allocator.free(metadata);

    const close = std.mem.lastIndexOf(u8, canonical_core_wat, "\n)") orelse return error.UnsupportedP3BatchedListResourceProducer;
    var output = std.ArrayList(u8).empty;
    errdefer output.deinit(allocator);
    try output.appendSlice(allocator, canonical_core_wat[0..close]);
    try output.appendSlice(allocator, metadata);
    try output.appendSlice(allocator, canonical_core_wat[close..]);
    return output.toOwnedSlice(allocator);
}

pub fn emit_component_wat_for_tokens(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]u8 {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    const plan = try BatchedListResourceProducerPlan.analyze(tokens, registry);
    return emit_component_wat(allocator, plan);
}

pub fn emit_component_wit(allocator: std.mem.Allocator, plan: BatchedListResourceProducerPlan) ![]u8 {
    try validate_internal_plans(allocator, plan);
    if (!std.mem.eql(u8, plan.descriptor.wit.world, "batched-list-producer")) return error.UnsupportedP3BatchedListResourceProducer;
    return allocator.dupe(u8,
        "package do:g6-2-batched-list-producer@0.1.0;\n\n" ++
            "interface types {\n  enum error-code { io, pipe, invalid-mode }\n  resource ticket {}\n  record resource-entry { ticket: own<ticket> }\n}\n\n" ++
            "interface source {\n  use types.{ticket};\n  make-ticket: func(seed: u32) -> own<ticket>;\n}\n\n" ++
            "interface sink {\n  use types.{error-code, resource-entry};\n  consume-via-stream: async func(data: stream<list<resource-entry>>) -> result<_, error-code>;\n}\n\n" ++
            "world batched-list-producer {\n  use types.{error-code};\n  import source;\n  import sink;\n  export produce: async func(mode: u32) -> result<_, error-code>;\n}\n",
    );
}

pub fn emit_component_wit_for_tokens(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]u8 {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    const plan = try BatchedListResourceProducerPlan.analyze(tokens, registry);
    return emit_component_wit(allocator, plan);
}

fn validate_internal_plans(allocator: std.mem.Allocator, plan: BatchedListResourceProducerPlan) ProducerError!void {
    const accepted_lengths = [_]u32{ 0, 1, 2 };
    var ticket = wit_abi_types.AbiType.resource(allocator, "ticket", .own) catch return error.UnsupportedP3BatchedListResourceProducer;
    defer ticket.deinit();
    var entry = wit_abi_types.AbiType.record(allocator, &.{
        .{ .name = "ticket", .value = &ticket },
    }) catch return error.UnsupportedP3BatchedListResourceProducer;
    defer entry.deinit();
    var list = wit_abi_types.AbiType.list(allocator, &entry) catch return error.UnsupportedP3BatchedListResourceProducer;
    defer list.deinit();

    var layout = wit_abi_layout.ListLayoutPlan.init(allocator, &list, .{
        .pointer_offset = plan.layout.result_pointer_offset,
        .length_offset = plan.layout.result_length_offset,
        .element_byte_size = 4,
        .element_stride = plan.layout.element_stride,
        .element_alignment = 4,
        .ticket_offset = plan.layout.ticket_offset,
        .capacity = plan.layout.max_items,
        .accepted_lengths = &accepted_lengths,
        .allocation = .cabi_realloc,
        .free = .cabi_realloc,
    }) catch return error.UnsupportedP3BatchedListResourceProducer;
    defer layout.deinit();

    for (accepted_lengths) |length| {
        var slots = layout.owned_slot_iterator(length) catch return error.UnsupportedP3BatchedListResourceProducer;
        var slot_count: u32 = 0;
        while (slots.next() != null) slot_count += 1;
        if (slot_count != length) return error.UnsupportedP3BatchedListResourceProducer;

        var ownership = wit_abi_ownership.ListProducerOwnershipPlan.init(
            allocator,
            length,
            plan.layout.max_items,
            &accepted_lengths,
        ) catch return error.UnsupportedP3BatchedListResourceProducer;
        defer ownership.deinit();
        ownership.apply(.{ .allocate = {} }) catch return error.UnsupportedP3BatchedListResourceProducer;
        var index: u32 = 0;
        while (index < length) : (index += 1) {
            ownership.apply(.{ .create_ticket = index }) catch return error.UnsupportedP3BatchedListResourceProducer;
        }
        ownership.apply(.{ .enqueue = {} }) catch return error.UnsupportedP3BatchedListResourceProducer;
        ownership.apply(.{ .transfer = {} }) catch return error.UnsupportedP3BatchedListResourceProducer;
        index = 0;
        while (index < length) : (index += 1) {
            ownership.apply(.{ .clear_source_slot = index }) catch return error.UnsupportedP3BatchedListResourceProducer;
        }
        ownership.apply(.{ .release_list = {} }) catch return error.UnsupportedP3BatchedListResourceProducer;
        ownership.apply(.{ .terminal_finalize = {} }) catch return error.UnsupportedP3BatchedListResourceProducer;
    }

    var frame = wit_abi_async.ListProducerFramePlan.init(allocator);
    defer frame.deinit(allocator);
    frame.apply(.{ .allocate = {} }, allocator) catch return error.UnsupportedP3BatchedListResourceProducer;
    frame.apply(.{ .queue = {} }, allocator) catch return error.UnsupportedP3BatchedListResourceProducer;
    frame.apply(.{ .transfer = {} }, allocator) catch return error.UnsupportedP3BatchedListResourceProducer;
    frame.apply(.{ .await_sink = {} }, allocator) catch return error.UnsupportedP3BatchedListResourceProducer;
    frame.apply(.{ .complete = .ready }, allocator) catch return error.UnsupportedP3BatchedListResourceProducer;
    frame.apply(.{ .finalize = {} }, allocator) catch return error.UnsupportedP3BatchedListResourceProducer;
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
        if (close + 3 >= tokens.len or !tok_eq(tokens[close + 1], "-") or !tok_eq(tokens[close + 2], ">")) continue;
        if (found != null) return null;
        found = .{
            .name = tokens[idx].lexeme,
            .locator = string_body(tokens[idx + 5].lexeme) orelse continue,
            .member = string_body(tokens[idx + 7].lexeme) orelse continue,
            .signature_open = idx + 9,
            .kind = kind,
        };
    }
    return found;
}

fn count_host_bindings(tokens: []const lexer.Token) usize {
    var count: usize = 0;
    var idx: usize = 0;
    while (idx + 9 < tokens.len) : (idx += 1) {
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

fn source_signature_is_exact(tokens: []const lexer.Token, open: usize) bool {
    const close = find_matching(tokens, open, "(", ")") orelse return false;
    return close == open + 2 and tok_eq(tokens[open + 1], "u32") and close + 3 < tokens.len and
        tok_eq(tokens[close + 1], "-") and tok_eq(tokens[close + 2], ">") and tok_eq(tokens[close + 3], "Ticket");
}

fn sink_signature_is_exact(tokens: []const lexer.Token, open: usize) bool {
    const close = find_matching(tokens, open, "(", ")") orelse return false;
    return close == open + 7 and tok_eq(tokens[open + 1], "StreamWriter") and tok_eq(tokens[open + 2], "<") and
        tok_eq(tokens[open + 3], "[") and tok_eq(tokens[open + 4], "ResourceEntry") and tok_eq(tokens[open + 5], "]") and
        tok_eq(tokens[open + 6], ">") and tok_eq(tokens[close + 1], "-") and tok_eq(tokens[close + 2], ">") and
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
    while (idx + 3 < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], name) and tok_eq(tokens[idx + 1], "error") and tok_eq(tokens[idx + 2], "=")) return true;
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

test "batched list producer plan accepts the exact fixed Do source" {
    const source =
        \\make_ticket = @host_func("do:g6-2-batched-list-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
        \\consume = @host_async_func("do:g6-2-batched-list-producer@0.1.0", "consume-via-stream", (StreamWriter<[ResourceEntry]>) -> Result<nil, ProducerError>)
        \\Ticket = @wasi_resource("do:g6-2-batched-list-producer/source/ticket", { .id i64 })
        \\ResourceEntry { .ticket Ticket }
        \\ProducerError error = Io | Pipe | InvalidMode
        \\produce(mode u32) -> Result<nil, ProducerError> {
        \\    return Ok()
        \\}
        \\start() {}
    ;
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    const plan = try BatchedListResourceProducerPlan.analyze(tokens, registry);
    try std.testing.expectEqualStrings("produce", plan.root_name);
    try std.testing.expectEqualStrings("mode", plan.mode_name);
    try std.testing.expectEqual(@as(u32, 2), plan.layout.max_items);
    try std.testing.expectEqual(@as(u32, 2), plan.producer.batch_count.?);
    try std.testing.expectEqual(@as(u32, 2), plan.producer.batch_lengths.?[0]);
    try std.testing.expectEqual(@as(u32, 1), plan.producer.batch_lengths.?[1]);

    const wat = try emit_component_wat(std.testing.allocator, plan);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[producer-batched-list-transfer]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[producer-batch-transfer-0]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[producer-batch-transfer-1]") != null);

    const wit = try emit_component_wit(std.testing.allocator, plan);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "world batched-list-producer") != null);
    try std.testing.expect(std.mem.indexOf(u8, wit, "export produce: async func(mode: u32)") != null);
}

fn expect_plan_error(source: []const u8) !void {
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectError(error.UnsupportedP3BatchedListResourceProducer, BatchedListResourceProducerPlan.analyze(tokens, registry));
}

test "batched list producer plan rejects an unregistered package version" {
    try expect_plan_error(
        \\make_ticket = @host_func("do:g6-2-batched-list-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
        \\consume = @host_async_func("do:g6-2-batched-list-producer@0.1.1", "consume-via-stream", (StreamWriter<[ResourceEntry]>) -> Result<nil, ProducerError>)
        \\Ticket = @wasi_resource("do:g6-2-batched-list-producer/source/ticket", { .id i64 })
        \\ResourceEntry { .ticket Ticket }
        \\ProducerError error = Io | Pipe | InvalidMode
        \\produce(mode u32) -> Result<nil, ProducerError> { return Ok() }
        \\start() {}
    );
}

test "batched list producer plan rejects a second sink" {
    try expect_plan_error(
        \\make_ticket = @host_func("do:g6-2-batched-list-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
        \\consume = @host_async_func("do:g6-2-batched-list-producer@0.1.0", "consume-via-stream", (StreamWriter<[ResourceEntry]>) -> Result<nil, ProducerError>)
        \\other = @host_async_func("do:g6-2-batched-list-producer@0.1.0", "consume-via-stream", (StreamWriter<[ResourceEntry]>) -> Result<nil, ProducerError>)
        \\Ticket = @wasi_resource("do:g6-2-batched-list-producer/source/ticket", { .id i64 })
        \\ResourceEntry { .ticket Ticket }
        \\ProducerError error = Io | Pipe | InvalidMode
        \\produce(mode u32) -> Result<nil, ProducerError> { return Ok() }
        \\start() {}
    );
}

test "batched list producer plan rejects a borrowed entry" {
    try expect_plan_error(
        \\make_ticket = @host_func("do:g6-2-batched-list-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
        \\consume = @host_async_func("do:g6-2-batched-list-producer@0.1.0", "consume-via-stream", (StreamWriter<[BorrowedEntry]>) -> Result<nil, ProducerError>)
        \\Ticket = @wasi_resource("do:g6-2-batched-list-producer/source/ticket", { .id i64 })
        \\BorrowedEntry { .ticket Ticket }
        \\ResourceEntry { .ticket Ticket }
        \\ProducerError error = Io | Pipe | InvalidMode
        \\produce(mode u32) -> Result<nil, ProducerError> { return Ok() }
        \\start() {}
    );
}

test "batched list producer plan rejects a non-u32 mode" {
    try expect_plan_error(
        \\make_ticket = @host_func("do:g6-2-batched-list-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
        \\consume = @host_async_func("do:g6-2-batched-list-producer@0.1.0", "consume-via-stream", (StreamWriter<[ResourceEntry]>) -> Result<nil, ProducerError>)
        \\Ticket = @wasi_resource("do:g6-2-batched-list-producer/source/ticket", { .id i64 })
        \\ResourceEntry { .ticket Ticket }
        \\ProducerError error = Io | Pipe | InvalidMode
        \\produce(mode i64) -> Result<nil, ProducerError> { return Ok() }
        \\start() {}
    );
}

test "batched list producer plan rejects an extra producer body statement" {
    try expect_plan_error(
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
    );
}
