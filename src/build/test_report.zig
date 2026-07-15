const std = @import("std");
const lexer = @import("lexer.zig");
const model = @import("test_values.zig");

pub const EvalTestFn = *const fn (
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const model.FuncDecl,
    decl: model.TestDecl,
) anyerror!model.TestStatus;

pub fn run_and_print(
    io: std.Io,
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const model.FuncDecl,
    test_decls: []const model.TestDecl,
    eval_test: EvalTestFn,
) !void {
    var out_buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(io, &out_buffer);

    var passed: usize = 0;
    var failed: usize = 0;
    var skipped: usize = 0;
    for (test_decls) |decl| {
        const status = try eval_test(allocator, tokens, funcs, decl);
        switch (status) {
            .pass => {
                passed += 1;
                try out.interface.print("test {s} ... ok\n", .{decl.name_lexeme});
            },
            .fail => {
                failed += 1;
                try out.interface.print("test {s} ... failed\n", .{decl.name_lexeme});
            },
            .skip => {
                skipped += 1;
                try out.interface.print("test {s} ... skipped\n", .{decl.name_lexeme});
            },
        }
    }

    if (failed == 0) {
        try out.interface.print("ok: {d} passed; 0 failed; {d} skipped\n", .{ passed, skipped });
        try out.interface.flush();
        return;
    }

    try out.interface.print("failed: {d} passed; {d} failed; {d} skipped\n", .{ passed, failed, skipped });
    try out.interface.flush();
    return error.TestFailed;
}
