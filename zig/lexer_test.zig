const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const TokenTag = @import("token.zig").TokenTag;

test "lexer: basic identifiers and prefixes" {
    const source = "count .age _Pi ._Secret";
    var lexer = Lexer.init(source);

    const expected = [_]TokenTag{
        .identifier, // count
        .identifier, // .age
        .identifier, // _Pi
        .identifier, // ._Secret
        .eof,
    };

    for (expected) |tag| {
        const tok = lexer.next();
        try std.testing.expectEqual(tag, tok.tag);
    }
}

test "lexer: control flow arrows and assign" {
    const source = "-> <- => := =";
    var lexer = Lexer.init(source);

    const expected = [_]TokenTag{
        .arrow_out,   // ->
        .arrow_in,    // <-
        .arrow_ret,   // =>
        .assign_init, // :=
        .assign,      // =
        .eof,
    };

    for (expected) |tag| {
        const tok = lexer.next();
        try std.testing.expectEqual(tag, tok.tag);
    }
}

test "lexer: keywords and loop labels" {
    const source = "if else loop #outer defer nil";
    var lexer = Lexer.init(source);

    const expected = [_]TokenTag{
        .kw_if,
        .kw_else,
        .kw_loop,
        .hash_tag,
        .identifier, // outer
        .kw_defer,
        .kw_nil,
        .eof,
    };

    for (expected) |tag| {
        const tok = lexer.next();
        try std.testing.expectEqual(tag, tok.tag);
    }
}

test "lexer: numbers and complex cases" {
    const source = "123 3.14 // comment\n456";
    var lexer = Lexer.init(source);

    try std.testing.expectEqual(TokenTag.literal_int, lexer.next().tag);
    try std.testing.expectEqual(TokenTag.literal_float, lexer.next().tag);
    try std.testing.expectEqual(TokenTag.literal_int, lexer.next().tag);
    try std.testing.expectEqual(TokenTag.eof, lexer.next().tag);
}
