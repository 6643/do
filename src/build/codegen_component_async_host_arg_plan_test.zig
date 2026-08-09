const std = @import("std");
const lexer = @import("lexer.zig");
const plan = @import("codegen_component_async_host_arg_plan.zig");

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

test "async host scalar argument planner accepts the exact M1 shape" {
    const tokens = try lexer.tokenize(std.testing.allocator, positive_source);
    defer std.testing.allocator.free(tokens);
    var result = try plan.analyze(std.testing.allocator, tokens);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 7), result.argument_value);
    try std.testing.expectEqualStrings("value", result.argument_name);
    try std.testing.expectEqualStrings("run", result.root_name);
    try std.testing.expectEqualStrings("helper", result.helper_name);
    try std.testing.expectEqualStrings("work", result.host_name);
}

test "async host scalar argument planner rejects every M1 red boundary" {
    const cases = [_][]const u8{
        \\work = @host_async_func("unknown", "work", (u32) -> nil)
        \\helper(value u32) -> nil { pending Future<nil> = work(value) @await(pending) }
        \\run() -> nil { child Future<nil> = @async(helper(7)) @await(child) }
        ,
        \\work = @host_func("do:async-call-arg-probe/host@0.1.0", "work", (u32) -> nil)
        \\helper(value u32) -> nil { pending Future<nil> = work(value) @await(pending) }
        \\run() -> nil { child Future<nil> = @async(helper(7)) @await(child) }
        ,
        \\work = @host_async_func("do:async-call-arg-probe/host@0.1.0", "work", (u32) -> nil)
        \\other = @host_func("do:generic-async-call-probe/host@0.1.0", "work", () -> nil)
        \\helper(value u32) -> nil { pending Future<nil> = work(value) @await(pending) }
        \\run() -> nil { child Future<nil> = @async(helper(7)) @await(child) }
        ,
        \\work = @host_async_func("do:async-call-arg-probe/host@0.1.0", "work", (text) -> nil)
        \\helper(value u32) -> nil { pending Future<nil> = work(value) @await(pending) }
        \\run() -> nil { child Future<nil> = @async(helper(7)) @await(child) }
        ,
        \\work = @host_async_func("do:async-call-arg-probe/host@0.1.0", "work", (u32, u32) -> nil)
        \\helper(value u32) -> nil { pending Future<nil> = work(value) @await(pending) }
        \\run() -> nil { child Future<nil> = @async(helper(7)) @await(child) }
        ,
        \\work = @host_async_func("do:async-call-arg-probe/host@0.1.0", "work", (u32) -> nil)
        \\helper(value u32) -> nil { pending Future<nil> = work(value) @await(pending) }
        \\run() -> nil { child Future<nil> = @async(helper(dynamic)) @await(child) }
        ,
        \\work = @host_async_func("do:async-call-arg-probe/host@0.1.0", "work", (u32) -> nil)
        \\helper(value u32) -> text { pending Future<nil> = work(value) @await(pending) }
        \\run() -> nil { child Future<nil> = @async(helper(7)) @await(child) }
        ,
        \\work = @host_async_func("do:async-call-arg-probe/host@0.1.0", "work", (u32) -> nil)
        \\async helper(value u32) -> nil { pending Future<nil> = work(value) @await(pending) }
        \\run() -> nil { child Future<nil> = @async(helper(7)) @await(child) }
        ,
        \\work = @host_async_func("do:async-call-arg-probe/host@0.1.0", "work", (u32) -> nil)
        \\helper(value u32) -> nil { pending Future<nil> = work(value) @await(pending) }
        \\run() -> nil { child Future<nil> = @async(helper(7)) @await(child) child2 Future<nil> = @async(helper(7)) @await(child2) }
        ,
        \\work = @host_async_func("do:async-call-arg-probe/host@0.1.0", "work", (u32) -> nil)
        \\helper(value u32) -> nil { pending Future<Ticket> = work(value) @await(pending) }
        \\run() -> nil { child Future<nil> = @async(helper(7)) @await(child) }
        ,
        \\work = @host_async_func("do:async-call-arg-probe/host@0.1.0", "work", (u32) -> nil)
        \\helper(value u32) -> nil { pending Future<list<u32>> = work(value) @await(pending) }
        \\run() -> nil { child Future<nil> = @async(helper(7)) @await(child) }
        ,
        \\work = @host_async_func("do:async-call-arg-probe/host@0.1.0", "work", (u32) -> nil)
        \\helper(value u32) -> nil { pending Future<stream<u32>> = work(value) @await(pending) }
        \\run() -> nil { child Future<nil> = @async(helper(7)) @await(child) }
        ,
        \\work = @host_async_func("do:async-call-arg-probe/host@0.1.0", "work", (u32) -> nil)
        \\helper(value u32) -> nil { pending Future<nil> = work(value) @await(pending) }
        \\extra() -> nil { }
        \\run() -> nil { child Future<nil> = @async(helper(7)) @await(child) }
        ,
        \\work = @host_async_func("do:async-call-arg-probe/host@0.1.0", "work", (u32) -> nil)
        \\unused u32 = 99
        \\helper(value u32) -> nil { pending Future<nil> = work(value) @await(pending) }
        \\run() -> nil { child Future<nil> = @async(helper(7)) @await(child) }
        ,
        \\work = @host_async_func("do:async-call-arg-probe/host@0.1.0", "work", (u32) -> nil)
        \\helper(value u32) -> nil { pending Future<nil> = work(value) @await(pending) work(value) @await(pending) }
        \\run() -> nil { child Future<nil> = @async(helper(7)) @await(child) }
        ,
    };
    for (cases) |source| {
        const tokens = try lexer.tokenize(std.testing.allocator, source);
        defer std.testing.allocator.free(tokens);
        try std.testing.expectError(error.UnsupportedP3AsyncHostArgComponent, plan.analyze(std.testing.allocator, tokens));
    }
}

fn expect_reason(source: []const u8, expected: plan.RejectReason) !void {
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    const reason = (try plan.rejection_reason(std.testing.allocator, tokens)) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(expected, reason);
    try std.testing.expectEqualStrings(expected.identifier(), reason.identifier());
    try std.testing.expectError(error.UnsupportedP3AsyncHostArgComponent, plan.analyze(std.testing.allocator, tokens));
}

test "async host scalar argument planner exposes stable boundary identifiers" {
    try expect_reason(
        \\work = @host_async_func("unknown", "work", (u32) -> nil)
        \\helper(value u32) -> nil { pending Future<nil> = work(value) @await(pending) }
        \\run() -> nil { child Future<nil> = @async(helper(7)) @await(child) }
        ,
        .unknown_host_descriptor,
    );
    try expect_reason(
        \\work = @host_func("do:async-call-arg-probe/host@0.1.0", "work", (u32) -> nil)
        \\helper(value u32) -> nil { pending Future<nil> = work(value) @await(pending) }
        \\run() -> nil { child Future<nil> = @async(helper(7)) @await(child) }
        ,
        .marker_mismatch,
    );
    try expect_reason(
        \\work = @host_async_func("do:async-call-arg-probe/host@0.1.0", "work", (text) -> nil)
        \\helper(value u32) -> nil { pending Future<nil> = work(value) @await(pending) }
        \\run() -> nil { child Future<nil> = @async(helper(7)) @await(child) }
        ,
        .type_unsupported,
    );
    try expect_reason(
        \\work = @host_async_func("do:async-call-arg-probe/host@0.1.0", "work", (u32, u32) -> nil)
        \\helper(value u32) -> nil { pending Future<nil> = work(value) @await(pending) }
        \\run() -> nil { child Future<nil> = @async(helper(7)) @await(child) }
        ,
        .arity_unsupported,
    );
    try expect_reason(
        \\work = @host_async_func("do:async-call-arg-probe/host@0.1.0", "work", (u32) -> nil)
        \\helper(value u32) -> nil { pending Future<nil> = work(value) @await(pending) }
        \\run() -> nil { child Future<nil> = @async(helper(dynamic)) @await(child) }
        ,
        .dynamic_root,
    );
    try expect_reason(
        \\work = @host_async_func("do:async-call-arg-probe/host@0.1.0", "work", (u32) -> nil)
        \\helper(value u32) -> text { pending Future<nil> = work(value) @await(pending) }
        \\run() -> nil { child Future<nil> = @async(helper(7)) @await(child) }
        ,
        .helper_payload,
    );
    try expect_reason(
        \\work = @host_async_func("do:async-call-arg-probe/host@0.1.0", "work", (u32) -> nil)
        \\inner() -> nil { }
        \\helper(value u32) -> nil { inner() pending Future<nil> = work(value) @await(pending) }
        \\run() -> nil { child Future<nil> = @async(helper(7)) @await(child) }
        ,
        .nested_helper,
    );
    try expect_reason(
        \\work = @host_async_func("do:async-call-arg-probe/host@0.1.0", "work", (u32) -> nil)
        \\helper(value u32) -> nil { pending Future<nil> = work(value) @await(pending) }
        \\run() -> nil { first Future<nil> = @async(helper(7)) second Future<nil> = @async(helper(7)) @await(first) @await(second) }
        ,
        .multiple_children,
    );
    try expect_reason(
        \\work = @host_async_func("do:async-call-arg-probe/host@0.1.0", "work", (u32) -> nil)
        \\helper(value u32) -> nil { pending Future<list<u32>> = work(value) @await(pending) }
        \\run() -> nil { child Future<nil> = @async(helper(7)) @await(child) }
        ,
        .payload_unsupported,
    );
    try expect_reason(
        \\work = @host_async_func("do:async-call-arg-probe/host@0.1.0", "work", (u32) -> nil)
        \\async helper(value u32) -> nil { pending Future<nil> = work(value) @await(pending) }
        \\run() -> nil { child Future<nil> = @async(helper(7)) @await(child) }
        ,
        .legacy_async_decl,
    );
}
