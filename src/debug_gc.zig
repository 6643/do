const std = @import("std");
const lexer = @import("build/lexer.zig");
const parser = @import("build/parser.zig");
const gc_sync = @import("build/codegen_gc_sync.zig");

pub fn main(init: std.process.Init) !void {
    const source = @embedFile("build/test/compiled_ok/20_compiled_test_guard_union_storage_return_move.do");
    const allocator = init.gpa;
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);
    var program = try parser.parse_program(allocator, tokens, source.len);
    defer program.deinit(allocator);
    const wat = gc_sync.emit_gc_wat_for_supported_tests(allocator, program, tokens, null) catch |err| {
        std.debug.print("error={s}\n", .{@errorName(err)});
        if (@errorReturnTrace()) |trace| std.debug.dumpErrorReturnTrace(trace);
        return;
    };
    defer allocator.free(wat);
    std.debug.print("ok bytes={d}\n", .{wat.len});
}
