const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const imports = @import("imports.zig");
const module_graph = @import("module_graph.zig");
const generated_wit_manifest = @import("generated_wit_manifest.zig");
const generated_async_scalar_plan = @import("codegen_generated_async_scalar_plan.zig");

const invalid_template = error.InvalidGeneratedAsyncScalarTemplate;

pub fn emit_component_wat(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph_opt: ?*const imports.ModuleGraph,
) ![]u8 {
    var plan = try generated_async_scalar_plan.analyze(allocator, program, tokens, module_graph_opt);
    defer plan.deinit(allocator);
    return render_wat(allocator, plan);
}

pub fn emit_component_wit(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]u8 {
    const source = if (has_future_type(tokens, "i64"))
        @embedFile("generated_async_scalar_i64_component.wit")
        else
        @embedFile("generated_async_scalar_component.wit");
    return allocator.dupe(u8, source);
}

pub fn emit_component_wit_with_graph(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    graph_opt: ?*const imports.ModuleGraph,
) ![]u8 {
    var plan = try generated_async_scalar_plan.analyze_tokens(allocator, tokens, graph_opt);
    defer plan.deinit(allocator);
    const source = if (std.mem.eql(u8, plan.payload.encoding, "core-s64"))
        @embedFile("generated_async_scalar_i64_component.wit")
    else
        @embedFile("generated_async_scalar_component.wit");
    return allocator.dupe(u8, source);
}

fn render_wat(
    allocator: std.mem.Allocator,
    plan: generated_async_scalar_plan.GeneratedAsyncScalarPlan,
) ![]u8 {
    var wat = try allocator.dupe(u8, @embedFile("generated_async_scalar_component_template.wat"));
    errdefer allocator.free(wat);

    var offset_buf: [32]u8 = undefined;
    var byte_size_buf: [32]u8 = undefined;
    var alignment_buf: [32]u8 = undefined;
    const offset = try std.fmt.bufPrint(&offset_buf, "{}", .{plan.payload.offset});
    const byte_size = try std.fmt.bufPrint(&byte_size_buf, "{}", .{plan.payload.byte_size});
    const alignment = try std.fmt.bufPrint(&alignment_buf, "{}", .{plan.payload.alignment});
    const payload_ops = payload_operations(plan.payload) orelse return invalid_template;

    wat = try replace_required(allocator, wat, "__ASYNC_IMPORT_MODULE__", plan.async_import_module);
    wat = try replace_required(allocator, wat, "__ASYNC_IMPORT_NAME__", plan.async_import_name);
    wat = try replace_required(allocator, wat, "__ASYNC_COMPLETION__", plan.completion);
    wat = try replace_required(allocator, wat, "__PAYLOAD_OFFSET__", offset);
    wat = try replace_required(allocator, wat, "__PAYLOAD_BYTE_SIZE__", byte_size);
    wat = try replace_required(allocator, wat, "__PAYLOAD_ALIGNMENT__", alignment);
    wat = try replace_required(allocator, wat, "__PAYLOAD_ENCODING__", plan.payload.encoding);
    wat = try replace_required(allocator, wat, "__PAYLOAD_LOAD__", payload_ops.load);
    wat = try replace_required(allocator, wat, "__PAYLOAD_STORE__", payload_ops.store);
    wat = try replace_required(allocator, wat, "__PAYLOAD_ZERO__", payload_ops.zero);
    return wat;
}

const PayloadOperations = struct {
    load: []const u8,
    store: []const u8,
    zero: []const u8,
};

fn payload_operations(payload: generated_wit_manifest.GeneratedScalarPayload) ?PayloadOperations {
    if (std.mem.eql(u8, payload.core_type, "i32") and
        std.mem.eql(u8, payload.encoding, "core-u32") and payload.byte_size == 4 and payload.alignment == 4)
    {
        return .{ .load = "i32.load", .store = "i32.store", .zero = "i32.const 0" };
    }
    if (std.mem.eql(u8, payload.core_type, "i64") and
        std.mem.eql(u8, payload.encoding, "core-s64") and payload.byte_size == 8 and payload.alignment == 8)
    {
        return .{ .load = "i64.load", .store = "i64.store", .zero = "i64.const 0" };
    }
    return null;
}

fn has_future_type(tokens: []const lexer.Token, value_type: []const u8) bool {
    for (tokens, 0..) |token, index| {
        if (token.kind != .ident or !std.mem.eql(u8, token.lexeme, "Future") or index + 3 >= tokens.len) continue;
        if (tokens[index + 1].lexeme.len == 1 and tokens[index + 1].lexeme[0] == '<' and
            std.mem.eql(u8, tokens[index + 2].lexeme, value_type) and
            tokens[index + 3].lexeme.len == 1 and tokens[index + 3].lexeme[0] == '>') return true;
    }
    return false;
}

fn replace_required(
    allocator: std.mem.Allocator,
    input: []u8,
    needle: []const u8,
    replacement: []const u8,
) ![]u8 {
    if (needle.len == 0) return invalid_template;
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var remainder = input;
    var found = false;
    while (std.mem.indexOf(u8, remainder, needle)) |idx| {
        found = true;
        try out.appendSlice(allocator, remainder[0..idx]);
        try out.appendSlice(allocator, replacement);
        remainder = remainder[idx + needle.len ..];
    }
    if (!found) return invalid_template;
    try out.appendSlice(allocator, remainder);
    const owned = try out.toOwnedSlice(allocator);
    allocator.free(input);
    return owned;
}

test "generated scalar emitter preserves measured payload and cleanup ABI" {
    const source = @embedFile("test/check/430_generated_async_scalar.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    var graph = try test_graph(std.testing.allocator);
    defer graph.deinit();

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, &graph);
    defer std.testing.allocator.free(wat);

    try std.testing.expect(std.mem.indexOf(u8, wat, "do:generic-async-scalar-probe/host@0.1.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lower][future-read-0]completion") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lower][future-cancel-read-0]completion") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[future-drop-readable-0]completion") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[scalar-payload] offset=12 byte-size=4 alignment=4 encoding=core-u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-scalar] ready") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-scalar] pending") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-scalar] cancel") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $future-read") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $future-cancel-read") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $future-drop-readable") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $waitable-set-drop") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $task-return") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $host-work") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[generic-async-runtime]") == null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, wat, "[scalar-payload-load]"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, wat, "[scalar-payload-store]"));
}

test "generated scalar emitter emits the pinned WIT world" {
    const source = @embedFile("test/check/430_generated_async_scalar.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);

    try std.testing.expectEqualStrings(@embedFile("generated_async_scalar_component.wit"), wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "completion: func() -> future<u32>") != null);
}

test "generated scalar emitter emits i64 payload operations and WIT" {
    const source = @embedFile("test/check/431_generated_async_scalar_i64.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    var graph = try test_i64_graph(std.testing.allocator);
    defer graph.deinit();

    const wat = try emit_component_wat(std.testing.allocator, program, tokens, &graph);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[scalar-payload] offset=16 byte-size=8 alignment=8 encoding=core-s64") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.load") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.store") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.const 0") != null);

    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expectEqualStrings(@embedFile("generated_async_scalar_i64_component.wit"), wit);
}

fn test_graph(allocator: std.mem.Allocator) !imports.ModuleGraph {
    const lowerings = try allocator.alloc(module_graph.GeneratedAsyncLowering, 1);
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

fn test_i64_graph(allocator: std.mem.Allocator) !imports.ModuleGraph {
    const lowerings = try allocator.alloc(module_graph.GeneratedAsyncLowering, 1);
    errdefer allocator.free(lowerings);
    lowerings[0] = .{
        .locator = try allocator.dupe(u8, "do:generic-async-scalar-i64-probe/host@0.1.0"),
        .member = try allocator.dupe(u8, "completion"),
        .source_signature = try allocator.dupe(u8, "() -> Future<i64>"),
        .wit_package = try allocator.dupe(u8, "do:generic-async-scalar-i64-probe@0.1.0"),
        .wit_world = try allocator.dupe(u8, "probe"),
        .wit_interface = try allocator.dupe(u8, "host"),
        .wit_member = try allocator.dupe(u8, "completion"),
        .async_import_module = try allocator.dupe(u8, "do:generic-async-scalar-i64-probe/host@0.1.0"),
        .async_import_name = try allocator.dupe(u8, "[async-lower][future-read-0]completion"),
        .completion = try allocator.dupe(u8, "completion"),
        .wit_sha256 = [_]u8{0} ** 32,
        .payload = .{
            .core_type = try allocator.dupe(u8, "i64"),
            .offset = 16,
            .byte_size = 8,
            .alignment = 8,
            .encoding = try allocator.dupe(u8, "core-s64"),
        },
    };
    return .{
        .allocator = allocator,
        .dep_root = "",
        .modules = &.{},
        .generated_async_lowerings = lowerings,
    };
}
