const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const imports = @import("imports.zig");
const generic_async_plan = @import("codegen_generic_async_plan.zig");

pub fn emit_if_supported(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) !?[]u8 {
    if (!has_generic_async_operation(tokens)) return null;
    var plan = generic_async_plan.analyze(allocator, program, tokens, module_graph) catch |err| switch (err) {
        error.UnsupportedGenericAsyncShape => return null,
        else => return err,
    };
    defer plan.deinit(allocator);

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try emit_wat(allocator, &out, plan);
    return try out.toOwnedSlice(allocator);
}

fn emit_wat(allocator: std.mem.Allocator, out: *std.ArrayList(u8), plan: generic_async_plan.GenericAsyncPlan) !void {
    try out.appendSlice(allocator,
        \\(module
        \\  ;; generic async vertical slice
        \\  (type $generic-async-frame (struct
        \\    (field $state (mut i32))
        \\    (field $future (mut i32))
        \\    (field $terminal (mut i32))
        \\  ))
        \\  (func $generic-frame-alloc (result i32)
        \\    i32.const 0)
        \\  (func $generic-frame-free (param $handle i32))
    );
    try append_fmt(allocator, out, "  (func ${s})\n", .{plan.work_name});
    try append_fmt(allocator, out,
        \\  (func ${s}
        \\    (local $frame i32)
        \\    ;; [generic-async-frame]
        \\    call $generic-frame-alloc
        \\    local.set $frame
        \\    i32.const 0
        \\    drop
        \\    ;; [generic-async-suspend]
        \\    call ${s}
        \\    ;; [generic-async-cancel]
        \\    local.get $frame
        \\    call $generic-frame-free
        \\    ;; [generic-async-terminal]
        \\  )
    , .{ plan.root_name, plan.work_name });
    try append_fmt(allocator, out,
        \\  (func $start
        \\    call ${s})
        \\  (export "run" (func ${s}))
        \\  (export "_start" (func $start))
        \\)
    , .{ plan.root_name, plan.root_name });
}

fn has_generic_async_operation(tokens: []const lexer.Token) bool {
    for (tokens, 0..) |token, idx| {
        if (!std.mem.eql(u8, token.lexeme, "@") or idx + 1 >= tokens.len) continue;
        if (std.mem.eql(u8, tokens[idx + 1].lexeme, "async") or
            std.mem.eql(u8, tokens[idx + 1].lexeme, "await") or
            std.mem.eql(u8, tokens[idx + 1].lexeme, "cancel")) return true;
    }
    return false;
}

fn append_fmt(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}

fn count_marker(wat: []const u8, marker: []const u8) usize {
    var count: usize = 0;
    var offset: usize = 0;
    while (std.mem.indexOfPos(u8, wat, offset, marker)) |idx| {
        count += 1;
        offset = idx + marker.len;
    }
    return count;
}

test "generic async emitter produces one resumable state machine" {
    const source = @embedFile("test/check/417_generic_async_single_future.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    const wat = (try emit_if_supported(std.testing.allocator, program, tokens, null)).?;
    defer std.testing.allocator.free(wat);
    try std.testing.expectEqual(@as(usize, 1), count_marker(wat, "[generic-async-frame]"));
    try std.testing.expectEqual(@as(usize, 1), count_marker(wat, "[generic-async-suspend]"));
    try std.testing.expectEqual(@as(usize, 1), count_marker(wat, "[generic-async-cancel]"));
    try std.testing.expectEqual(@as(usize, 1), count_marker(wat, "[generic-async-terminal]"));
}

test "generic async emitter leaves unsupported shapes to the guard" {
    const source =
        \\work() -> i32 { return 1 }
        \\run() -> nil {
        \\    pending Future<i32> = @async(work())
        \\    @await(pending)
        \\    other Future<nil> = @async(work())
        \\    @cancel(other)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);
    try std.testing.expect((try emit_if_supported(std.testing.allocator, program, tokens, null)) == null);
}
