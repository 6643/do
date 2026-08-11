const std = @import("std");
const lexer = @import("lexer.zig");
const control_flow = @import("codegen_control_flow.zig");

test "control-flow module detects a terminal return" {
    const allocator = std.testing.allocator;
    const tokens = try lexer.tokenize(allocator, "if true { return } else { return }");
    defer allocator.free(tokens);

    try std.testing.expect(!control_flow.body_can_reach_end(tokens, 0, tokens.len));
}

test "control-flow module finds a labeled loop break" {
    const allocator = std.testing.allocator;
    const tokens = try lexer.tokenize(allocator, "#outer\nloop { if true { break #outer } }");
    defer allocator.free(tokens);

    var loop_idx: ?usize = null;
    for (tokens, 0..) |token, index| {
        if (token.kind == .ident and std.mem.eql(u8, token.lexeme, "loop")) {
            loop_idx = index;
            break;
        }
    }
    try std.testing.expect(control_flow.loop_stmt_can_reach_end(tokens, loop_idx orelse return error.TestUnexpectedResult, tokens.len));
}
