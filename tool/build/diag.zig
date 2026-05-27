const std = @import("std");
const lexer = @import("lexer.zig");

pub const SourceLoc = struct {
    line: usize,
    col: usize,
};

pub fn printCliError(io: std.Io, err: anyerror) !void {
    var err_buffer: [512]u8 = undefined;
    var out = std.Io.File.stderr().writer(io, &err_buffer);
    try out.interface.print("error[{s}]: {s}\n", .{ @errorName(err), errorSummary(err) });
    try out.interface.print("hint: {s}\n", .{ errorHint(err) });
    try out.interface.flush();
}

pub fn printIoError(io: std.Io, path: []const u8, err: anyerror) !void {
    var err_buffer: [768]u8 = undefined;
    var out = std.Io.File.stderr().writer(io, &err_buffer);
    try out.interface.print("error[{s}]: {s}\n", .{ @errorName(err), errorSummary(err) });
    try out.interface.print("at: {s}\n", .{ path });
    try out.interface.print("hint: {s}\n", .{ errorHint(err) });
    try out.interface.flush();
}

pub fn printCompileError(
    io: std.Io,
    path: []const u8,
    source: []const u8,
    tokens_opt: ?[]const lexer.Token,
    err: anyerror,
    explicit_loc: ?SourceLoc,
) !void {
    const loc = locateCompileError(err, source, tokens_opt, explicit_loc);
    const line_text = getLineText(source, loc.line);
    const caret_col = if (loc.col == 0) 1 else loc.col;

    var err_buffer: [4096]u8 = undefined;
    var out = std.Io.File.stderr().writer(io, &err_buffer);
    try out.interface.print("error[{s}]: {s}\n", .{ @errorName(err), errorSummary(err) });
    try out.interface.print(" --> {s}:{d}:{d}\n", .{ path, loc.line, loc.col });
    try out.interface.print(" hint: {s}\n", .{ errorHint(err) });
    if (line_text.len != 0) {
        try out.interface.print(" {d} | {s}\n", .{ loc.line, line_text });
        try out.interface.print("   | ", .{});
        try writeCaret(&out, caret_col);
    }
    try out.interface.flush();
}

fn writeCaret(writer: anytype, col: usize) !void {
    const max_col = if (col > 256) 256 else col;
    var i: usize = 1;
    while (i < max_col) : (i += 1) {
        try writer.interface.print(" ", .{});
    }
    try writer.interface.print("^\n", .{});
}

fn locateCompileError(
    err: anyerror,
    source: []const u8,
    tokens_opt: ?[]const lexer.Token,
    explicit_loc: ?SourceLoc,
) SourceLoc {
    if (explicit_loc) |loc| return loc;
    if (tokens_opt) |tokens| {
        if (locateTokenError(err, tokens)) |loc| return loc;
        if (tokens.len != 0) return .{ .line = tokens[0].line, .col = tokens[0].col };
    }
    if (locateSourceError(err, source)) |loc| return loc;
    return .{ .line = 1, .col = 1 };
}

fn locateSourceError(err: anyerror, source: []const u8) ?SourceLoc {
    if (err != error.UnterminatedString) return null;

    var in_string = false;
    var line: usize = 1;
    var col: usize = 1;
    var str_line: usize = 1;
    var str_col: usize = 1;

    var i: usize = 0;
    while (i < source.len) : (i += 1) {
        const ch = source[i];
        if (!in_string and ch == '"') {
            in_string = true;
            str_line = line;
            str_col = col;
            col += 1;
            continue;
        }
        if (in_string and ch == '"') {
            in_string = false;
            col += 1;
            continue;
        }
        if (ch == '\n') {
            if (in_string) return .{ .line = str_line, .col = str_col };
            line += 1;
            col = 1;
            continue;
        }
        col += 1;
    }

    if (in_string) return .{ .line = str_line, .col = str_col };
    return null;
}

fn locateTokenError(err: anyerror, tokens: []const lexer.Token) ?SourceLoc {
    if (tokens.len == 0) return null;

    switch (err) {
        error.InvalidIfHeader,
        error.InvalidIfPatternBind,
        error.MultiReturnInIfCondition,
        error.MultiReturnInIfBindRhs,
        error.InvalidBindingName,
        => return tokenSite(findFirstToken(tokens, "if") orelse tokens[0]),

        error.InvalidLoopHeader => return tokenSite(findFirstToken(tokens, "loop") orelse tokens[0]),
        error.InvalidTestDecl => return tokenSite(findFirstToken(tokens, "test") orelse tokens[0]),
        error.InvalidConstraintDecl => return tokenSite(findFirstToken(tokens, "#") orelse tokens[0]),
        error.InvalidParamName => return tokenSite(findFirstToken(tokens, "(") orelse tokens[0]),
        error.InvalidImportDecl => return tokenSite(findFirstToken(tokens, "@") orelse tokens[0]),
        error.InvalidStartEntrySig, error.DuplicateStartEntry => return tokenSite(findFirstToken(tokens, "_start") orelse tokens[0]),
        error.MissingStartEntry => return tokenSite(tokens[0]),
        error.InvalidDoExpr => return tokenSite(findFirstToken(tokens, "do") orelse tokens[0]),
        error.InvalidBraceExpr => return tokenSite(findFirstToken(tokens, "{") orelse tokens[0]),
        error.InvalidReturnStmt => return tokenSite(findFirstTokenOnLine(tokens, "return") orelse findFirstToken(tokens, "return") orelse tokens[0]),
        error.InvalidStructLiteral => return tokenSite(findFirstStructLitToken(tokens) orelse tokens[0]),
        error.PrivateIdentCannotBeLValue => return tokenSite(findFirstPrivateIdent(tokens) orelse tokens[0]),
        error.DuplicateImmutableBinding => return tokenSite(findDuplicateImmutable(tokens) orelse tokens[0]),
        error.InvalidCallArgList => return tokenSite(findTrailingCommaToken(tokens) orelse tokens[0]),
        error.NoTopLevelDecl => return tokenSite(tokens[0]),
        else => return tokenSite(tokens[0]),
    }
}

fn tokenSite(tok: lexer.Token) SourceLoc {
    return .{ .line = tok.line, .col = tok.col };
}

fn findFirstToken(tokens: []const lexer.Token, lexeme: []const u8) ?lexer.Token {
    for (tokens) |tok| {
        if (std.mem.eql(u8, tok.lexeme, lexeme)) return tok;
    }
    return null;
}

fn findFirstTokenOnLine(tokens: []const lexer.Token, lexeme: []const u8) ?lexer.Token {
    if (tokens.len == 0) return null;
    const target_line = tokens[0].line;
    for (tokens) |tok| {
        if (tok.line != target_line) continue;
        if (std.mem.eql(u8, tok.lexeme, lexeme)) return tok;
    }
    return null;
}

fn findFirstStructLitToken(tokens: []const lexer.Token) ?lexer.Token {
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (tokens[i].lexeme.len == 0) continue;
        if (!std.ascii.isUpper(tokens[i].lexeme[0])) continue;
        if (!std.mem.eql(u8, tokens[i + 1].lexeme, "{")) continue;
        return tokens[i];
    }
    return null;
}

fn findFirstPrivateIdent(tokens: []const lexer.Token) ?lexer.Token {
    for (tokens) |tok| {
        if (tok.kind != .ident) continue;
        if (tok.lexeme.len == 0) continue;
        if (tok.lexeme[0] == '.') return tok;
    }
    return null;
}

fn findDuplicateImmutable(tokens: []const lexer.Token) ?lexer.Token {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        const tok = tokens[i];
        if (tok.kind != .ident) continue;
        if (tok.lexeme.len <= 1) continue;
        if (tok.lexeme[0] != '_') continue;

        var j: usize = 0;
        while (j < i) : (j += 1) {
            const prev = tokens[j];
            if (prev.kind != .ident) continue;
            if (!std.mem.eql(u8, prev.lexeme, tok.lexeme)) continue;
            return tok;
        }
    }
    return null;
}

fn findTrailingCommaToken(tokens: []const lexer.Token) ?lexer.Token {
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (!std.mem.eql(u8, tokens[i].lexeme, ",")) continue;
        if (!std.mem.eql(u8, tokens[i + 1].lexeme, ")")) continue;
        return tokens[i];
    }
    return findFirstToken(tokens, ",");
}

fn getLineText(source: []const u8, target_line: usize) []const u8 {
    if (target_line == 0) return "";

    var line: usize = 1;
    var start: usize = 0;
    var i: usize = 0;
    while (i < source.len) : (i += 1) {
        if (source[i] != '\n') continue;
        if (line == target_line) return source[start..i];
        line += 1;
        start = i + 1;
    }
    if (line == target_line) return source[start..source.len];
    return "";
}

fn errorSummary(err: anyerror) []const u8 {
    return switch (err) {
        error.UnterminatedString => "字符串语法: `\"text\"`",
        error.InvalidIfHeader => "if 语法: `if expr { ... }`, `if expr return`, `if expr break`, `if expr continue`",
        error.InvalidLoopHeader => "loop 语法: `loop { ... }`, `loop v, i = source { ... }`, `loop v = recv(ch) { ... }`; 绑定名使用 snake_case 或 `_`",
        error.InvalidLoopSource => "集合循环源协议: `len(source) -> usize` 与 `at(source, usize) -> V`",
        error.InvalidStructLiteral => "结构体构造语法: `Type{field = value}` 或已知目标类型的 `.{field = value}`",
        error.InvalidTypeDeclName => "类型声明位使用 UpperCamel；私有类型只在声明位写前置 `.`",
        error.InvalidTypeRef => "类型引用写作 `Type`；私有类型声明写作 `.Type`",
        error.InvalidPathIndex => "路径索引写作 `get(value, .{index})`；字段段写作 `get(value, .field)`",
        error.InvalidPathAccess => "字段读取语法: `get(value, .field)`; 字段写入语法: `set(value, .field, new_value)`",
        error.InvalidFuncDeclName => "函数声明名语法: `lower_name(...) -> Type { ... }`",
        error.InvalidTypedLiteral => "聚合构造语法: `Type{field = value}` 或 `Type<...>{field = value}`",
        error.InvalidBraceExpr => "聚合构造语法: `Type{field = value}` 或已知目标类型的 `.{field = value}`",
        error.InvalidCallArgList => "调用语法: `name(arg, next_arg)` 或 `name(arg, ...rest)`; `is` 语法: `is(value, Type)`",
        error.LiteralCannotBeCalled => "函数调用语法: `name(arg, next_arg)`",
        error.InvalidIfPatternBind => "if 语法: `if expr { ... }`, `if expr return`, `if expr break`, `if expr continue`",
        error.InvalidBindingName => "顶层常量名使用 `_snake_case`; 局部绑定名使用 `snake_case` 或 `_snake_case`",
        error.PrivateIdentCannotBeLValue => "赋值语法: `name = expr`; 字段写入语法: `set(value, .field, new_value)`",
        error.DuplicateImmutableBinding => "同一作用域内 `_name` 写作 1 次",
        error.DuplicateStructFieldName => "结构体字段名按去掉私有标记后的名字唯一; 每个字段名保留 1 个声明",
        error.MultiReturnInIfCondition => "先接收多返回值, 再在 if 使用单值变量",
        error.MultiReturnInIfBindRhs => "if 条件语法使用单值 bool 表达式",
        error.InvalidImportDecl => "导入使用 `name = @path/file.do/symbol`; 函数 alias 和 host import 左侧使用 `LowerIdent`",
        error.NoTopLevelDecl => "top-level 项写作 import/type/func/test",
        error.NoTestDecl => "在文件顶层添加 `test \"name\" { ... }`",
        error.InvalidTestDecl => "使用 `test \"name\" { ... }` 顶层声明",
        error.InvalidConstraintDecl => "约束独立成行；类型参数名写作 `UpperIdent`，类型约束在前，函数约束在后",
        error.InvalidParamName => "参数名写作 `snake_case` 或 `_`; `_name` 写作顶层常量和局部只读绑定",
        error.MissingStartEntry => "编译入口写作 `_start() { ... }`",
        error.InvalidStartEntrySig => "入口签名写作 `_start() { ... }` (无参、无返回)",
        error.DuplicateStartEntry => "顶层 `_start` 写作 1 次",
        error.MissingOutputPath => "示例: `do build input.do -o out.wat`",
        error.MissingTestInputPath => "示例: `do test sample.do`",
        else => "编译失败",
    };
}

fn errorHint(err: anyerror) []const u8 {
    return switch (err) {
        error.UnterminatedString => "字符串语法: `\"text\"`",
        error.InvalidIfHeader => "if 语法: `if expr { ... }`, `if expr return`, `if expr break`, `if expr continue`",
        error.InvalidLoopHeader => "loop 语法: `loop { ... }`, `loop v, i = source { ... }`, `loop v = recv(ch) { ... }`; 绑定名使用 snake_case 或 `_`",
        error.InvalidLoopSource => "集合循环源协议: `len(source) -> usize` 与 `at(source, usize) -> V`",
        error.InvalidStructLiteral => "结构体构造语法: `Type{field = value}` 或已知目标类型的 `.{field = value}`",
        error.InvalidTypeDeclName => "类型声明位使用 UpperCamel；私有类型只在声明位写前置 `.`",
        error.InvalidTypeRef => "类型引用写作 `Type`；私有类型声明写作 `.Type`",
        error.InvalidPathIndex => "路径索引写作 `get(value, .{index})`；字段段写作 `get(value, .field)`",
        error.InvalidPathAccess => "字段读取语法: `get(value, .field)`; 字段写入语法: `set(value, .field, new_value)`",
        error.InvalidFuncDeclName => "函数声明名语法: `lower_name(...) -> Type { ... }`",
        error.InvalidTypedLiteral => "聚合构造语法: `Type{field = value}` 或 `Type<...>{field = value}`",
        error.InvalidBraceExpr => "聚合构造语法: `Type{field = value}` 或已知目标类型的 `.{field = value}`",
        error.InvalidReturnStmt => "return 语句返回位数不匹配",
        error.InvalidCallArgList => "调用语法: `name(arg, next_arg)` 或 `name(arg, ...rest)`; `is` 语法: `is(value, Type)`",
        error.LiteralCannotBeCalled => "函数调用语法: `name(arg, next_arg)`",
        error.InvalidIfPatternBind => "if 语法: `if expr { ... }`, `if expr return`, `if expr break`, `if expr continue`",
        error.InvalidBindingName => "顶层常量名使用 `_snake_case`; 局部绑定名使用 `snake_case` 或 `_snake_case`",
        error.PrivateIdentCannotBeLValue => "赋值语法: `name = expr`; 字段写入语法: `set(value, .field, new_value)`",
        error.DuplicateImmutableBinding => "同一作用域内 `_name` 写作 1 次",
        error.DuplicateStructFieldName => "结构体字段名按去掉私有标记后的名字唯一; 每个字段名保留 1 个声明",
        error.MultiReturnInIfCondition => "先接收多返回值, 再在 if 使用单值变量",
        error.MultiReturnInIfBindRhs => "if 条件语法使用单值 bool 表达式",
        error.InvalidImportDecl => "导入使用 `name = @path/file.do/symbol`; 函数 alias 和 host import 左侧使用 `LowerIdent`",
        error.NoTopLevelDecl => "至少声明 1 个 top-level 项: import/type/func/test",
        error.NoTestDecl => "在文件顶层添加 `test \"name\" { ... }`",
        error.InvalidTestDecl => "使用 `test \"name\" { ... }` 顶层声明",
        error.InvalidConstraintDecl => "约束独立成行；类型参数名写作 `UpperIdent`，类型约束在前，函数约束在后",
        error.InvalidParamName => "参数名写作 `snake_case` 或 `_`; `_name` 写作顶层常量和局部只读绑定",
        error.MissingStartEntry => "编译入口写作 `_start() { ... }`",
        error.InvalidStartEntrySig => "入口签名写作 `_start() { ... }` (无参、无返回)",
        error.DuplicateStartEntry => "顶层 `_start` 写作 1 次",
        error.MissingOutputPath => "示例: `do build input.do -o out.wat`",
        error.MissingTestInputPath => "示例: `do test sample.do`",
        else => "语法示例: `if expr { ... }`, `loop { ... }`, `get(value, .field)`, `Type{field = value}`",
    };
}
