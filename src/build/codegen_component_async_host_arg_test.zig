const std = @import("std");
const lexer = @import("lexer.zig");
const plan = @import("codegen_component_async_host_arg_plan.zig");
const emitter = @import("codegen_component_async_host_arg.zig");

const positive_source =
    \\work = @host_async_func("do:async-call-arg-probe/host@0.1.0", "work", (u32) -> nil)
    \\helper(value u32) -> nil {
    \\    pending Future<nil> = work(value)
    \\    @await(pending)
    \\}
    \\run() -> nil {
    \\    child Future<nil> = @async(helper(7))
    \\    @await(child)
    \\}
;

test "async host scalar argument emitter preserves the measured frame ABI" {
    const tokens = try lexer.tokenize(std.testing.allocator, positive_source);
    defer std.testing.allocator.free(tokens);
    var lowering = try plan.analyze(std.testing.allocator, tokens);
    defer lowering.deinit(std.testing.allocator);
    const wat = try emitter.emit_component_wat(std.testing.allocator, lowering);
    defer std.testing.allocator.free(wat);
    for ([_][]const u8{
        "(param i32) (result i32)",
        "i32.const 20",
        "i32.const 12",
        "[guest-async-arg-store]",
        "[guest-async-arg-load]",
        "[guest-async-child-drop]",
        "[guest-async-waitable-drop]",
        "[guest-async-context-clear]",
        "[guest-async-frame-free]",
    }) |marker| {
        try std.testing.expect(std.mem.indexOf(u8, wat, marker) != null);
    }
    try std.testing.expect(std.mem.indexOf(u8, wat, "[task-return]helper") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[async-lift]helper") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "[task-cancel]") != null);

    const child_drop = std.mem.lastIndexOf(u8, wat, "[guest-async-child-drop]") orelse return error.TestUnexpectedResult;
    const waitable_drop = std.mem.indexOf(u8, wat, "[guest-async-waitable-drop]") orelse return error.TestUnexpectedResult;
    const context_clear = std.mem.indexOf(u8, wat, "[guest-async-context-clear]") orelse return error.TestUnexpectedResult;
    const frame_free = std.mem.indexOf(u8, wat, "[guest-async-frame-free]") orelse return error.TestUnexpectedResult;
    const root_terminal = std.mem.indexOf(u8, wat, "call $task-return-run") orelse return error.TestUnexpectedResult;
    try std.testing.expect(child_drop < waitable_drop);
    try std.testing.expect(waitable_drop < context_clear);
    try std.testing.expect(context_clear < frame_free);
    try std.testing.expect(frame_free < root_terminal);
}

test "async host scalar argument emitter emits the pinned WIT world" {
    const wit = try emitter.emit_component_wit(std.testing.allocator);
    defer std.testing.allocator.free(wit);
    try std.testing.expectEqualStrings(
        "package do:async-call-arg-probe@0.1.0;\n\n" ++
            "interface host {\n  work: async func(value: u32);\n}\n\n" ++
            "world probe {\n  import host;\n  export run: async func();\n}\n",
        wit,
    );
}
