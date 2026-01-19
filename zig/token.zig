const std = @import("std");

pub const TokenTag = enum {
    // 基础
    eof,
    invalid,
    identifier, // 处理 .age, _Pi, count, ._Secret
    literal_int,
    literal_float,
    literal_text,

    // 关键字
    kw_if,
    kw_else,
    kw_loop,
    kw_break,
    kw_continue,
    kw_return,
    kw_defer,
    kw_match,
    kw_bool,

    // 特殊符号
    assign, // =
    assign_init, // :=
    arrow_fat, // =>
    arrow_out, // -> (break / lambda output)
    arrow_in, // <- (continue)
    hash_tag, // # (label 或 generic)

    // 运算符
    plus,
    minus,
    asterisk,
    slash,
    percent,
    equal_equal,
    not_equal,
    greater,
    greater_equal,
    less,
    less_equal,
    l_shift,
    r_shift,
    pipe, // | (union)

    // 分隔符
    l_paren,
    r_paren,
    l_brace,
    r_brace,
    l_bracket,
    r_bracket,
    comma,
    dot,
    colon,
    semicolon,
};

pub const Token = struct {
    tag: TokenTag,
    loc: struct {
        start: usize,
        end: usize,
        line: u32,
        col: u32,
    },
};
