const std = @import("std");
const lexer = @import("lexer.zig");

pub const SourceLoc = struct {
    line: usize,
    col: usize,
};

pub const CompileDiagnostic = struct {
    path: []const u8,
    loc: SourceLoc,
    code: []const u8,
    message: []const u8,
    hint: []const u8,
    line_text: []const u8,
};

pub fn buildCompileDiagnostic(
    path: []const u8,
    source: []const u8,
    tokens_opt: ?[]const lexer.Token,
    err: anyerror,
    explicit_loc: ?SourceLoc,
) CompileDiagnostic {
    const loc = locateCompileError(err, source, tokens_opt, explicit_loc);
    return .{
        .path = path,
        .loc = loc,
        .code = @errorName(err),
        .message = errorSummary(err),
        .hint = errorHint(err),
        .line_text = getLineText(source, loc.line),
    };
}

pub fn printCliError(io: std.Io, err: anyerror) !void {
    var err_buffer: [512]u8 = undefined;
    var out = std.Io.File.stderr().writer(io, &err_buffer);
    try out.interface.print("error[{s}]: {s}\n", .{ @errorName(err), errorSummary(err) });
    try out.interface.print("hint: {s}\n", .{errorHint(err)});
    try out.interface.flush();
}

pub fn printIoError(io: std.Io, path: []const u8, err: anyerror) !void {
    var err_buffer: [768]u8 = undefined;
    var out = std.Io.File.stderr().writer(io, &err_buffer);
    try writeIoErrorTo(&out.interface, path, err);
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
    const diagnostic = buildCompileDiagnostic(path, source, tokens_opt, err, explicit_loc);
    try printDiagnostic(io, diagnostic);
}

pub fn printDiagnostic(io: std.Io, diagnostic: CompileDiagnostic) !void {
    var err_buffer: [4096]u8 = undefined;
    var out = std.Io.File.stderr().writer(io, &err_buffer);
    try writeDiagnosticTo(&out.interface, diagnostic);
    try out.interface.flush();
}

pub fn writeIoErrorTo(writer: anytype, path: []const u8, err: anyerror) !void {
    try writer.print("error[{s}]: {s}\n", .{ @errorName(err), errorSummary(err) });
    try writer.print("at: {s}\n", .{path});
    try writer.print("hint: {s}\n", .{errorHint(err)});
}

pub fn writeDiagnosticTo(writer: anytype, diagnostic: CompileDiagnostic) !void {
    const caret_col = if (diagnostic.loc.col == 0) 1 else diagnostic.loc.col;

    try writer.print("error[{s}]: {s}\n", .{ diagnostic.code, diagnostic.message });
    try writer.print(" --> {s}:{d}:{d}\n", .{ diagnostic.path, diagnostic.loc.line, diagnostic.loc.col });
    try writer.print(" hint: {s}\n", .{diagnostic.hint});
    if (diagnostic.line_text.len != 0) {
        try writer.print(" {d} | {s}\n", .{ diagnostic.loc.line, diagnostic.line_text });
        try writer.print("   | ", .{});
        try writeCaret(writer, caret_col);
    }
}

fn writeCaret(writer: anytype, col: usize) !void {
    const max_col = if (col > 256) 256 else col;
    var i: usize = 1;
    while (i < max_col) : (i += 1) {
        try writer.print(" ", .{});
    }
    try writer.print("^\n", .{});
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
    return switch (err) {
        error.UnterminatedString => locateUnterminatedString(source),
        error.InvalidStringEscape => locateInvalidStringEscape(source),
        error.InvalidStringUtf8 => locateInvalidStringUtf8(source),
        error.InvalidComment => locateInvalidComment(source),
        else => null,
    };
}

fn locateUnterminatedString(source: []const u8) ?SourceLoc {
    var in_string = false;
    var line: usize = 1;
    var col: usize = 1;
    var str_line: usize = 1;
    var str_col: usize = 1;

    var i: usize = 0;
    while (i < source.len) {
        const ch = source[i];
        if (!in_string and ch == '"') {
            in_string = true;
            str_line = line;
            str_col = col;
            col += 1;
            i += 1;
            continue;
        }
        if (in_string and ch == '"') {
            in_string = false;
            col += 1;
            i += 1;
            continue;
        }
        if (isLineBreak(source, i)) {
            if (in_string) return .{ .line = str_line, .col = str_col };
            i = skipLineBreak(source, i);
            line += 1;
            col = 1;
            continue;
        }
        col += 1;
        i += 1;
    }

    if (in_string) return .{ .line = str_line, .col = str_col };
    return null;
}

fn locateInvalidStringEscape(source: []const u8) ?SourceLoc {
    var in_string = false;
    var line: usize = 1;
    var col: usize = 1;
    var i: usize = 0;
    while (i < source.len) {
        const ch = source[i];
        if (!in_string and ch == '"') {
            in_string = true;
            i += 1;
            col += 1;
            continue;
        }
        if (in_string and ch == '"') {
            in_string = false;
            i += 1;
            col += 1;
            continue;
        }
        if (isLineBreak(source, i)) {
            i = skipLineBreak(source, i);
            line += 1;
            col = 1;
            in_string = false;
            continue;
        }
        if (in_string and ch == '\\') {
            if (i + 1 >= source.len) return .{ .line = line, .col = col };
            const esc = source[i + 1];
            if (esc == '"' or esc == '\\' or esc == 'n' or esc == 'r' or esc == 't') {
                i += 2;
                col += 2;
                continue;
            }
            if (esc == 'x') {
                if (i + 3 >= source.len or !std.ascii.isHex(source[i + 2]) or !std.ascii.isHex(source[i + 3])) {
                    return .{ .line = line, .col = col };
                }
                i += 4;
                col += 4;
                continue;
            }
            return .{ .line = line, .col = col };
        }
        i += 1;
        col += 1;
    }
    return null;
}

fn locateInvalidStringUtf8(source: []const u8) ?SourceLoc {
    var line: usize = 1;
    var col: usize = 1;
    var i: usize = 0;
    while (i < source.len) {
        if (isLineBreak(source, i)) {
            i = skipLineBreak(source, i);
            line += 1;
            col = 1;
            continue;
        }
        if (source[i] == '"' or (source[i] == '\\' and i + 1 < source.len and source[i + 1] == '\\')) {
            return .{ .line = line, .col = col };
        }
        i += 1;
        col += 1;
    }
    return null;
}

fn locateInvalidComment(source: []const u8) ?SourceLoc {
    var line: usize = 1;
    var col: usize = 1;
    var i: usize = 0;
    while (i + 1 < source.len) {
        if (isLineBreak(source, i)) {
            i = skipLineBreak(source, i);
            line += 1;
            col = 1;
            continue;
        }
        if (source[i] == '/' and (source[i + 1] == '/' or source[i + 1] == '*')) {
            if (!isCommentLineStart(source, i)) return .{ .line = line, .col = col };
            if (source[i + 1] == '*') {
                if (!blockCommentClosesCleanly(source, i)) return .{ .line = line, .col = col };
            }
        }
        i += 1;
        col += 1;
    }
    return null;
}

fn locateTokenError(err: anyerror, tokens: []const lexer.Token) ?SourceLoc {
    if (tokens.len == 0) return null;

    switch (err) {
        error.InvalidIfHeader,
        error.InvalidIfPatternBind,
        error.MultiReturnInIfCondition,
        error.MultiReturnInIfBindRhs,
        error.MultiReturnInLoopCondition,
        error.AmbiguousConditionCallReturnArity,
        error.InvalidBindingName,
        => return tokenSite(findFirstToken(tokens, "if") orelse tokens[0]),

        error.InvalidLoopHeader => return tokenSite(findFirstToken(tokens, "loop") orelse tokens[0]),
        error.InvalidNarrowing => return tokenSite(findFirstToken(tokens, "is") orelse tokens[0]),
        error.UnionPayloadRequiresNarrowing => return tokenSite(tokens[0]),
        error.InvalidTestDecl => return tokenSite(findFirstToken(tokens, "test") orelse tokens[0]),
        error.InvalidConstraintDecl => return tokenSite(findFirstToken(tokens, "#") orelse tokens[0]),
        error.InvalidParamName => return tokenSite(findFirstToken(tokens, "(") orelse tokens[0]),
        error.InvalidImportDecl => return tokenSite(findFirstToken(tokens, "@") orelse tokens[0]),
        error.InvalidStartEntrySig, error.DuplicateStartEntry => return tokenSite(findFirstToken(tokens, "start") orelse tokens[0]),
        error.MissingStartEntry => return tokenSite(tokens[0]),
        error.InvalidBraceExpr => return tokenSite(findFirstToken(tokens, "{") orelse tokens[0]),
        error.InvalidReturnStmt => return tokenSite(findFirstTokenOnLine(tokens, "return") orelse findFirstToken(tokens, "return") orelse tokens[0]),
        error.InvalidStructLiteral => return tokenSite(findFirstStructLitToken(tokens) orelse tokens[0]),
        error.PrivateIdentCannotBeLValue => return tokenSite(findFirstPrivateIdent(tokens) orelse tokens[0]),
        error.DuplicateImmutableBinding => return tokenSite(findDuplicateImmutable(tokens) orelse tokens[0]),
        error.DuplicateLocalBinding => return tokenSite(tokens[0]),
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
    while (i < source.len) {
        if (!isLineBreak(source, i)) {
            i += 1;
            continue;
        }
        if (line == target_line) return source[start..i];
        i = skipLineBreak(source, i);
        line += 1;
        start = i;
    }
    if (line == target_line) return source[start..source.len];
    return "";
}

fn isLineBreak(source: []const u8, idx: usize) bool {
    return source[idx] == '\n' or source[idx] == '\r';
}

fn skipLineBreak(source: []const u8, idx: usize) usize {
    if (source[idx] == '\r' and idx + 1 < source.len and source[idx + 1] == '\n') return idx + 2;
    return idx + 1;
}

fn isCommentLineStart(source: []const u8, idx: usize) bool {
    var i = idx;
    while (i > 0) : (i -= 1) {
        const prev = source[i - 1];
        if (prev == '\n' or prev == '\r') return true;
        if (prev != ' ' and prev != '\t') return false;
    }
    return true;
}

fn blockCommentClosesCleanly(source: []const u8, start_idx: usize) bool {
    var i = start_idx + 2;
    while (i + 1 < source.len) : (i += 1) {
        if (source[i] != '*' or source[i + 1] != '/') continue;
        i += 2;
        while (i < source.len) : (i += 1) {
            const ch = source[i];
            if (ch == '\n' or ch == '\r') return true;
            if (ch != ' ' and ch != '\t') return false;
        }
        return true;
    }
    return false;
}

pub fn errorSummary(err: anyerror) []const u8 {
    return switch (err) {
        error.UnterminatedString => "字符串语法: `\"text\"`",
        error.InvalidStringEscape => "字符串 escape 只支持 `\\\"`, `\\\\`, `\\n`, `\\r`, `\\t`, `\\xNN`",
        error.InvalidStringUtf8 => "字符串字面量解码后必须是有效 UTF-8",
        error.InvalidComment => "注释只能独立成行；行注释写 `// ...`，块注释写 `/* ... */`",
        error.InvalidIfHeader => "if 语法: `if expr { ... }`, `if expr return`, `if expr break`, `if expr continue`",
        error.InvalidLoopHeader => "loop 语法: `loop { ... }`, `loop v, i = source { ... }`, `loop v = recv(ch) { ... }`, `loop field = fields(Type) { ... }`; 绑定名使用 snake_case 或 `_`",
        error.InvalidLoopSource => "集合循环源必须是 `[T]` 或显式 `[T]` 视图函数结果",
        error.InvalidStructLiteral => "结构体构造语法: `Type{field = value}` 或已知目标类型的 `.{field = value}`",
        error.InvalidTypeDeclName => "类型声明位使用 UpperCamel；私有类型只在声明位写前置 `.`；`XxxError` 名只用于错误枚举",
        error.InvalidErrorBranchName => "错误枚举不支持私有声明；错误枚举写作 `XxxError error = Branch | OtherBranch`；value enum 承载值必须在范围内且唯一",
        error.InvalidSynthErrorType => "源码类型位不能使用合成 `Error`",
        error.InvalidTypeRef => "类型引用写作 `Type`；普通固定数据参数可写平铺 union/nullable；变参元素、函数类型和接口约束参数不接收 union/nullable；私有类型声明写作 `.Type`；裸 `nil` 类型非法；重复 union 分支非法；`nil` 分支最多一次；匿名函数类型不能直接作为 union 分支；TypeArgs 不接受 `(T)` 或匿名函数类型；`Tuple` 至少两个类型参数",
        error.InvalidPathIndex => "路径参数写作 `@get(value, index, .field)`；字段段写作 `.field`；`Tuple` 数字索引必须是编译期整数字面量且落在 `0..arity-1`",
        error.InvalidPathAccess => "字段读取语法: `@get(value, .field)`; 字段写入语法: `@set(value, .field, new_value)`；字段段只用于 @get/@set 路径参数",
        error.InvalidFieldReflection => "字段反射语法: `loop field = fields(StructOrTypeParam) { ... }`; `@field_*` 的 field 参数必须来自当前字段反射循环",
        error.InvalidNarrowing => "收窄语法: `@is(value, Type)` 只能直接作为条件头使用; Type 必须是单个可达非 nil 类型",
        error.UnionPayloadRequiresNarrowing => "union payload 使用前必须先通过直接 `@is(value, Type)` 或直接 `@eq/@ne(value, nil)` 收窄",
        error.InvalidFuncDeclName => "函数声明名语法: `lower_name(...) -> Type { ... }` 或 `.lower_name(...) -> Type { ... }`",
        error.InvalidTypedLiteral => "聚合构造语法: `Type{field = value}`、`Type<...>{field = value}` 或 `Tuple<T0, T1, ...>{v0, v1, ...}` 位置构造；实参数量/明显字面量类型必须与类型参数一致",
        error.InvalidBraceExpr => "聚合构造语法: `Type{field = value}`、已知目标类型的 `.{field = value}` 或 `.{expr, ...}`",
        error.NoMatchingCall => "函数调用需要匹配可见函数签名",
        error.InvalidReturnStmt => "return 语句返回位数不匹配",
        error.InvalidCallExpr => "函数调用语法: `name(arg, next_arg)`；内建/core 调用写 `@name(arg, next_arg)`；私有函数调用去掉声明位前置点",
        error.InvalidCallArgList => "调用语法: `name(arg, next_arg)`、`name(arg, ...rest)` 或内建 `@name(...)`; `@is/@as` 语法: `@is(value, Type)` / `@as(Type, value)`",
        error.InvalidReservedName => "内建名和声明专用名只能用于保留位置",
        error.LiteralCannotBeCalled => "函数调用语法: `name(arg, next_arg)`",
        error.InvalidIfPatternBind => "if 语法: `if expr { ... }`, `if expr return`, `if expr break`, `if expr continue`",
        error.InvalidBindingName => "顶层值写作 `_snake_case Type = expr`、`snake_case Type = expr` 或 `.snake_case Type = expr`; 局部绑定名使用 `snake_case` 或 `_snake_case`",
        error.PrivateIdentCannotBeLValue => "赋值语法: `name = expr`; 字段写入语法: `@set(value, .field, new_value)`",
        error.DuplicateImmutableBinding => "可见作用域内 `_name` 只能绑定 1 次",
        error.DuplicateLocalBinding => "局部绑定名不能重声明, 也不能遮蔽可见外层绑定",
        error.DuplicateTypeDeclName => "类型名按去掉私有标记后的名字唯一",
        error.DuplicateFuncSignature => "函数签名按去掉私有标记后的名字和参数类型序列唯一",
        error.DuplicateHostImportAlias => "host import alias 在同一模块内只能绑定 1 次",
        error.DuplicateStructFieldName => "结构体字段名按去掉私有标记后的名字唯一; 每个字段名保留 1 个声明",
        error.MultiReturnInIfCondition => "先接收多返回值, 再在 if 使用单值变量",
        error.MultiReturnInIfBindRhs => "if 条件语法使用单值 bool 表达式",
        error.MultiReturnInLoopCondition => "先接收多返回值, 再在 loop 条件使用单值变量",
        error.MultiReturnInSingleValuePosition => "多返回调用只能用于多左值赋值右侧或完整 return 位",
        error.AmbiguousConditionCallReturnArity => "调用返回位数不唯一, 需要先显式接收或选择具体重载",
        error.InvalidImportDecl => "导入使用 `name = @lib(\"file.do\", symbol)`, `name = @lib(\"./file.do\", symbol)`, `name = @lib(\"~/vendor.name.do\", symbol)`；host import 左侧使用 `LowerIdent` 或 `.LowerIdent`，右侧使用 `@env(\"name\", (...) -> Type)` 或 `@wasi(\"path/member\", (...) -> Type)`",
        error.NoTopLevelDecl => "top-level 项写作 import/type/value/start/func/test",
        error.NoTestDecl => "在文件顶层添加 `test \"name\" { ... }`",
        error.InvalidTestDecl => "使用 `test \"name\" { ... }` 顶层声明",
        error.InvalidConstraintDecl => "约束独立成行；类型参数名写作 `UpperIdent`，函数约束前必须先有类型约束",
        error.InvalidParamName => "参数名写作 `snake_case`; `_name` 写作顶层常量和局部只读绑定",
        error.MissingStartEntry => "编译入口写作 `start() { ... }`",
        error.InvalidStartEntrySig => "入口签名写作 `start() { ... }` (无参、无返回)",
        error.DuplicateStartEntry => "顶层 `start` 写作 1 次",
        error.UnsupportedWasiHostImport => "这个 WIT host import 签名尚未支持 lowering",
        error.MissingOutputPath => "示例: `do build input.do -o out.wat` 或 `do test sample.do --compiled -o sample.wat`",
        error.MissingTestInputPath => "示例: `do test sample.do` 或 `do test sample.do --compiled -o sample.wat`",
        error.UnexpectedCliArg => "命令只接受一个输入文件和已声明的选项",
        error.OutputRequiresCompiledTest => "`do test -o out.wat` 需要同时写 `--compiled`",
        error.FormatMismatch => "input is not formatted",
        else => "编译失败",
    };
}

pub fn errorHint(err: anyerror) []const u8 {
    return switch (err) {
        error.UnterminatedString => "字符串语法: `\"text\"`",
        error.InvalidStringEscape => "普通字符串 escape 写作 `\\\"`, `\\\\`, `\\n`, `\\r`, `\\t` 或 `\\xNN`",
        error.InvalidStringUtf8 => "`\"\\xFF\"` 不是合法 UTF-8 文本；原始字节写作 `[u8] = .{255}`",
        error.InvalidComment => "行尾注释非法；把 `// ...` 或 `/* ... */` 放到独立注释行",
        error.InvalidIfHeader => "if 语法: `if expr { ... }`, `if expr return`, `if expr break`, `if expr continue`",
        error.InvalidLoopHeader => "loop 语法: `loop { ... }`, `loop v, i = source { ... }`, `loop v = recv(ch) { ... }`, `loop field = fields(Type) { ... }`; 绑定名使用 snake_case 或 `_`",
        error.InvalidLoopSource => "集合循环源必须是 `[T]` 或显式 `[T]` 视图函数结果",
        error.InvalidStructLiteral => "结构体构造语法: `Type{field = value}` 或已知目标类型的 `.{field = value}`",
        error.InvalidTypeDeclName => "类型声明位使用 UpperCamel；私有类型只在声明位写前置 `.`；错误枚举写作 `XxxError error = ...`",
        error.InvalidErrorBranchName => "错误枚举写作 public `XxxError error = NotFound | PermissionDenied`；value enum 写作 `Status i8 = Ready(1) | Done(2)`，承载值按基础整数类型检查范围且不能重复",
        error.InvalidSynthErrorType => "返回、字段、局部绑定和 alias 使用具体错误枚举类型；源码类型位不能直接写合成 `Error`",
        error.InvalidTypeRef => "类型引用写作 `Type`；普通固定数据参数可写 `T | nil`；变参元素、函数类型和接口约束参数不接收 union/nullable；私有类型声明写作 `.Type`；同一 union 内分支唯一，`nil` 分支最多一次；函数类型不能写入 union；TypeArgs 写 `List<T>`；`Tuple` 至少两个类型参数",
        error.InvalidPathIndex => "路径参数写作 `@get(value, index, .field)`；字段段写作 `.field`；`Tuple` 数字索引必须是编译期整数字面量且落在 `0..arity-1`",
        error.InvalidPathAccess => "字段段只用于 @get/@set 路径参数；普通函数参数使用有类型表达式",
        error.InvalidFieldReflection => "`fields(...)` 只接收可见结构体或当前泛型类型参数；`@field_set` 写作 `target = @field_set(target, field, value)`",
        error.InvalidNarrowing => "`@is` 不进入普通值表达式或 `@and/@or/@not` 子条件; v1 不支持 `@is(value, A | B)` 或 `@is(value, nil)`",
        error.UnionPayloadRequiresNarrowing => "先写 `if @is(value, Type) { ... }` 或 `if @eq(value, nil) return` 后, 再把 union 值当作 payload 使用",
        error.InvalidFuncDeclName => "函数声明名语法: `lower_name(...) -> Type { ... }` 或 `.lower_name(...) -> Type { ... }`",
        error.InvalidTypedLiteral => "Tuple 位置构造写作 `Tuple<T0, T1, ...>{v0, v1, ...}`；实参数量与类型参数一致，字面量类型须匹配，不支持命名字段；尾逗号忽略不计入 arity",
        error.InvalidBraceExpr => "聚合构造语法: `Type{field = value}`、已知目标类型的 `.{field = value}` 或 `.{expr, ...}`",
        error.NoMatchingCall => "函数调用语法: `name(arg, next_arg)`；实参数量需匹配可见重载",
        error.InvalidReturnStmt => "return 语句返回位数不匹配",
        error.InvalidCallExpr => "私有函数声明写 `.name(...)`，调用写 `name(...)`",
        error.InvalidCallArgList => "调用语法: `name(arg, next_arg)`、`name(arg, ...rest)` 或内建 `@name(...)`; `@is/@as` 语法: `@is(value, Type)` / `@as(Type, value)`",
        error.InvalidReservedName => "内建/core 名按 `@name(...)` 固定调用语法使用；入口和测试使用 `start() { ... }` 或 `test \"name\" { ... }`",
        error.LiteralCannotBeCalled => "函数调用语法: `name(arg, next_arg)`",
        error.InvalidIfPatternBind => "if 语法: `if expr { ... }`, `if expr return`, `if expr break`, `if expr continue`",
        error.InvalidBindingName => "顶层值必须显式写类型；常量用 `_snake_case`，模块变量用 `snake_case` 或 `.snake_case`",
        error.PrivateIdentCannotBeLValue => "赋值语法: `name = expr`; 字段写入语法: `@set(value, .field, new_value)`",
        error.DuplicateImmutableBinding => "可见作用域内 `_name` 只能绑定 1 次",
        error.DuplicateLocalBinding => "局部绑定写作 `name Type = expr`; 已有同名绑定时只能写 `name = expr` 赋值",
        error.DuplicateTypeDeclName => "`.` 只表示可见性，类型命名冲突按去点后的实际 name 判断",
        error.DuplicateFuncSignature => "`.` 只表示可见性，函数重载身份按去点后的 name 和参数类型序列判断",
        error.DuplicateHostImportAlias => "`@env` / `@wasi` alias 是当前模块内的 host binding 身份; 同名 binding 要放在不同 source 模块或改名",
        error.DuplicateStructFieldName => "结构体字段名按去掉私有标记后的名字唯一; 每个字段名保留 1 个声明",
        error.MultiReturnInIfCondition => "先接收多返回值, 再在 if 使用单值变量",
        error.MultiReturnInIfBindRhs => "if 条件语法使用单值 bool 表达式",
        error.MultiReturnInLoopCondition => "先接收多返回值, 再在 loop 条件使用单值变量",
        error.MultiReturnInSingleValuePosition => "写作 `a, b = f()` 或 `return f()`; 单变量、实参和聚合元素位不能隐式承载多返回",
        error.AmbiguousConditionCallReturnArity => "给实参加类型或先绑定到具体签名, 让调用返回位数唯一",
        error.InvalidImportDecl => "导入语法: `name = @lib(\"file.do\", symbol)`, `name = @lib(\"./file.do\", symbol)`, `name = @lib(\"~/vendor.name.do\", symbol)`; host import 左侧使用 `LowerIdent` 或 `.LowerIdent`，右侧使用 `@env(\"name\", (...) -> Type)` 或 `@wasi(\"path/member\", (...) -> Type)`",
        error.NoTopLevelDecl => "至少声明 1 个 top-level 项: import/type/value/start/func/test",
        error.NoTestDecl => "在文件顶层添加 `test \"name\" { ... }`",
        error.InvalidTestDecl => "使用 `test \"name\" { ... }` 顶层声明",
        error.InvalidConstraintDecl => "约束独立成行；类型参数名写作 `UpperIdent`，函数约束前必须先有类型约束",
        error.InvalidParamName => "参数名写作 `snake_case`; `_name` 写作顶层常量和局部只读绑定",
        error.MissingStartEntry => "编译入口写作 `start() { ... }`",
        error.InvalidStartEntrySig => "入口签名写作 `start() { ... }` (无参、无返回)",
        error.DuplicateStartEntry => "顶层 `start` 写作 1 次",
        error.UnsupportedWasiHostImport => "已登记的 scalar/record/list<u8>、descriptor.sync 语句调用和 descriptor.write 多左值调用可 lower；复杂 result/resource/variant/flags 需要后续 component lowering",
        error.MissingOutputPath => "示例: `do build input.do -o out.wat` 或 `do test sample.do --compiled -o sample.wat`",
        error.MissingTestInputPath => "示例: `do test sample.do` 或 `do test sample.do --compiled -o sample.wat`",
        error.UnexpectedCliArg => "build 写作 `do build input.do [-o out.wat]`; test 写作 `do test input.do` 或 `do test input.do --compiled [-o out.wat]`",
        error.OutputRequiresCompiledTest => "生成 WAT 的测试入口写作 `do test input.do --compiled -o out.wat`",
        error.FormatMismatch => "运行 `do fmt input.do` 查看格式化后的 stdout 输出",
        else => "语法示例: `if expr { ... }`, `loop { ... }`, `@get(value, .field)`, `Type{field = value}`",
    };
}

test "buildCompileDiagnostic uses explicit source location" {
    const source =
        \\one
        \\two
        \\three
        \\
    ;
    const diagnostic = buildCompileDiagnostic(
        "bad.do",
        source,
        null,
        error.InvalidIfHeader,
        .{ .line = 2, .col = 3 },
    );
    try std.testing.expectEqualStrings("bad.do", diagnostic.path);
    try std.testing.expectEqual(@as(usize, 2), diagnostic.loc.line);
    try std.testing.expectEqual(@as(usize, 3), diagnostic.loc.col);
    try std.testing.expectEqualStrings("two", diagnostic.line_text);
    try std.testing.expectEqualStrings("InvalidIfHeader", diagnostic.code);
    try std.testing.expectEqualStrings(errorSummary(error.InvalidIfHeader), diagnostic.message);
    try std.testing.expectEqualStrings(errorHint(error.InvalidIfHeader), diagnostic.hint);
}

test "return statement diagnostic has specific summary" {
    try std.testing.expectEqualStrings(
        "return 语句返回位数不匹配",
        errorSummary(error.InvalidReturnStmt),
    );
}

test "buildCompileDiagnostic falls back to source lexer location" {
    const source = "\"abc";
    const diagnostic = buildCompileDiagnostic(
        "bad.do",
        source,
        null,
        error.UnterminatedString,
        null,
    );
    try std.testing.expectEqual(@as(usize, 1), diagnostic.loc.line);
    try std.testing.expectEqual(@as(usize, 1), diagnostic.loc.col);
    try std.testing.expectEqualStrings("\"abc", diagnostic.line_text);
}
