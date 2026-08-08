const std = @import("std");
const lexer = @import("lexer.zig");
const plan = @import("codegen_component_async_call_plan.zig");

const positive_source =
    \\work = @host_async_func("do:generic-async-call-probe/host@0.1.0", "work", () -> nil)
    \\helper() -> nil {
    \\    pending Future<nil> = work()
    \\    @await(pending)
    \\}
    \\run() -> nil {
    \\    child Future<nil> = @async(helper())
    \\    @await(child)
    \\}
    \\start() {}
;

test "async call component admits the exact local-frame shape" {
    const tokens = try lexer.tokenize(std.testing.allocator, positive_source);
    defer std.testing.allocator.free(tokens);
    var result = try plan.analyze(std.testing.allocator, tokens);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("run", result.root_name);
    try std.testing.expectEqualStrings("helper", result.helper_name);
    try std.testing.expectEqualStrings("work", result.host_name);
    try std.testing.expectEqualStrings("do:generic-async-call-probe/host@0.1.0", result.host_locator);
    try std.testing.expectEqualStrings("work", result.host_member);
    try std.testing.expectEqual(plan.ChildState.host_pending, result.child_state);
    try std.testing.expectEqual(plan.ParentResumeState.child_complete, result.parent_resume_state);
}

test "async call component rejects helper payload" {
    const source =
        \\work = @host_async_func("do:generic-async-call-probe/host@0.1.0", "work", () -> nil)
        \\helper() -> i32 {
        \\    pending Future<nil> = work()
        \\    @await(pending)
        \\}
        \\run() -> nil {
        \\    child Future<nil> = @async(helper())
        \\    @await(child)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectError(error.UnsupportedP3AsyncCallComponent, plan.analyze(std.testing.allocator, tokens));
}

test "async call component rejects two live children" {
    const source =
        \\work = @host_async_func("do:generic-async-call-probe/host@0.1.0", "work", () -> nil)
        \\helper() -> nil {
        \\    pending Future<nil> = work()
        \\    @await(pending)
        \\}
        \\run() -> nil {
        \\    first Future<nil> = @async(helper())
        \\    second Future<nil> = @async(helper())
        \\    @await(first)
        \\    @await(second)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectError(error.UnsupportedP3AsyncCallComponent, plan.analyze(std.testing.allocator, tokens));
}

test "async call component rejects nested helper calls" {
    const source =
        \\work = @host_async_func("do:generic-async-call-probe/host@0.1.0", "work", () -> nil)
        \\inner() -> nil {}
        \\helper() -> nil {
        \\    inner()
        \\    pending Future<nil> = work()
        \\    @await(pending)
        \\}
        \\run() -> nil {
        \\    child Future<nil> = @async(helper())
        \\    @await(child)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectError(error.UnsupportedP3AsyncCallComponent, plan.analyze(std.testing.allocator, tokens));
}

test "async call component admits one scalar helper argument" {
    const source = @embedFile("test/compile_ok/466_async_call_scalar_argument_component.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    var result = try plan.analyze(std.testing.allocator, tokens);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(@hasField(@TypeOf(result), "argument_name"));
    try std.testing.expect(@hasField(@TypeOf(result), "argument_value"));
    if (@hasField(@TypeOf(result), "argument_name")) {
        try std.testing.expectEqualStrings("value", @field(result, "argument_name"));
    }
    if (@hasField(@TypeOf(result), "argument_value")) {
        try std.testing.expectEqual(@as(u32, 7), @field(result, "argument_value"));
    }
}
