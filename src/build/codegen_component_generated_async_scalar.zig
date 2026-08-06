const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const imports = @import("imports.zig");
const module_graph = @import("module_graph.zig");
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
    _ = tokens;
    return allocator.dupe(u8, @embedFile("generated_async_scalar_component.wit"));
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

    wat = try replace_required(allocator, wat, "__ASYNC_IMPORT_MODULE__", plan.async_import_module);
    wat = try replace_required(allocator, wat, "__ASYNC_IMPORT_NAME__", plan.async_import_name);
    wat = try replace_required(allocator, wat, "__ASYNC_COMPLETION__", plan.completion);
    wat = try replace_required(allocator, wat, "__PAYLOAD_OFFSET__", offset);
    wat = try replace_required(allocator, wat, "__PAYLOAD_BYTE_SIZE__", byte_size);
    wat = try replace_required(allocator, wat, "__PAYLOAD_ALIGNMENT__", alignment);
    wat = try replace_required(allocator, wat, "__PAYLOAD_ENCODING__", plan.payload.encoding);
    return wat;
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
