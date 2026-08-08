const std = @import("std");
const lexer = @import("lexer.zig");
const call_plan = @import("codegen_component_async_call_plan.zig");
const emitter = @import("codegen_component_async_call.zig");

const source =
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

test "async call emitter produces an isolated root-owned frame" {
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var plan = try call_plan.analyze(std.testing.allocator, tokens);
    defer plan.deinit(std.testing.allocator);
    const wat = try emitter.emit_component_wat(std.testing.allocator, plan);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[guest-async-child]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[guest-async-parent-resume]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[guest-async-child-drop]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[guest-async-root-terminal]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lower]work") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[task-return]run") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[task-return]helper") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lift]helper") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[guest-inline-helper]") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[guest-inline-resume]") == null);
}

test "async call emitter writes the private probe WIT" {
    const wit = try emitter.emit_component_wit(std.testing.allocator);
    defer std.testing.allocator.free(wit);
    try std.testing.expectEqualStrings(
        "package do:generic-async-call-probe@0.1.0;\n\ninterface host {\n  work: async func();\n}\n\nworld probe {\n  import host;\n  export run: async func();\n}\n",
        wit,
    );
}

test "async call emitter reserves the inline helper phase" {
    const inline_source =
        \\work = @host_async_func("do:generic-async-call-probe/host@0.1.0", "work", () -> nil)
        \\helper() -> nil {
        \\    pending Future<nil> = work()
        \\    @await(pending)
        \\}
        \\run() -> nil {
        \\    helper()
        \\    child Future<nil> = @async(helper())
        \\    @await(child)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, inline_source);
    defer std.testing.allocator.free(tokens);
    var inline_plan = try call_plan.analyze(std.testing.allocator, tokens);
    defer inline_plan.deinit(std.testing.allocator);
    const wat = try emitter.emit_component_wat(std.testing.allocator, inline_plan);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[guest-inline-helper]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[guest-inline-resume]") != null);
}

test "async call emitter carries the scalar argument in the root frame" {
    const scalar_source = @embedFile("test/compile_ok/466_async_call_scalar_argument_component.do");
    const tokens = try lexer.tokenize(std.testing.allocator, scalar_source);
    defer std.testing.allocator.free(tokens);
    var plan = try call_plan.analyze(std.testing.allocator, tokens);
    defer plan.deinit(std.testing.allocator);
    const wat = try emitter.emit_component_wat(std.testing.allocator, plan);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[guest-async-arg-store]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[guest-async-arg-load]") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 7") != null);
}
