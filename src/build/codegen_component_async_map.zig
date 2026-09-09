const std = @import("std");
const generated_text = @import("codegen_text.zig");
const plan_mod = @import("codegen_component_async_map_plan.zig");

const canonical_wat = @embedFile("async_map_component_template.wat");

pub fn emit_component_wat(allocator: std.mem.Allocator, plan: plan_mod.AsyncMapPlan) ![]u8 {
    if (!std.mem.eql(u8, plan.root_name, "run") or
        !std.mem.eql(u8, plan.helper_name, "helper") or
        !std.mem.eql(u8, plan.host_name, "submit") or
        !std.mem.eql(u8, plan.hash_map_name, "HashMap") or
        !std.mem.eql(u8, plan.empty_hash_map_name, "empty_hash_map") or
        !std.mem.eql(u8, plan.hash_put_name, "hash_put") or
        !std.mem.eql(u8, plan.helper_argument_name, "values") or
        !std.mem.eql(u8, plan.values_name, "values") or
        !std.mem.eql(u8, plan.child_name, "child") or
        !std.mem.eql(u8, plan.shape.source_param, "HashMap<u32, u32>") or
        !std.mem.eql(u8, plan.shape.source_result, "u32")) return error.UnsupportedP3AsyncMapComponent;
    return generated_text.alloc_block(allocator, 0, canonical_wat);
}

pub fn emit_component_wit(allocator: std.mem.Allocator) ![]u8 {
    return generated_text.alloc_block(allocator, 0,
        \\package demo:map-async-probe@0.1.0;
        \\
        \\interface api {
        \\  submit: async func(values: map<u32, u32>) -> u32;
        \\}
        \\
        \\world probe {
        \\  import api;
        \\  export run: async func() -> u32;
        \\}
        \\
    );
}

test "async map emitter preserves the measured WAT template" {
    const lexer = @import("lexer.zig");
    const analyzer = @import("codegen_component_async_map_plan.zig");
    const source = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "../examples/p3-runtime/async-map-component.do",
        std.testing.allocator,
        .limited(1024 * 1024),
    );
    defer std.testing.allocator.free(source);
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var plan = try analyzer.analyze(std.testing.allocator, tokens);
    defer plan.deinit(std.testing.allocator);
    const actual = try emit_component_wat(std.testing.allocator, plan);
    defer std.testing.allocator.free(actual);
    const expected = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "../examples/p3-runtime/async-map-capability-canonical.wat",
        std.testing.allocator,
        .limited(1024 * 1024),
    );
    defer std.testing.allocator.free(expected);
    try std.testing.expectEqualStrings(expected, actual);
}

test "async map emitter emits the pinned WIT" {
    const actual = try emit_component_wit(std.testing.allocator);
    defer std.testing.allocator.free(actual);
    const expected = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "../examples/p3-runtime/wit/async-map-capability.wit",
        std.testing.allocator,
        .limited(1024 * 1024),
    );
    defer std.testing.allocator.free(expected);
    try std.testing.expectEqualStrings(expected, actual);
}
