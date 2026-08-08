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

pub fn build_compile_diagnostic(
    path: []const u8,
    source: []const u8,
    tokens_opt: ?[]const lexer.Token,
    err: anyerror,
    explicit_loc: ?SourceLoc,
) CompileDiagnostic {
    const loc = locate_compile_error(err, source, tokens_opt, explicit_loc);
    return .{
        .path = path,
        .loc = loc,
        .code = @errorName(err),
        .message = error_summary(err),
        .hint = error_hint(err),
        .line_text = get_line_text(source, loc.line),
    };
}

pub fn print_cli_error(io: std.Io, err: anyerror) !void {
    var err_buffer: [512]u8 = undefined;
    var out = std.Io.File.stderr().writer(io, &err_buffer);
    try out.interface.print("error[{s}]: {s}\n", .{ @errorName(err), error_summary(err) });
    try out.interface.print("hint: {s}\n", .{error_hint(err)});
    try out.interface.flush();
}

pub fn print_io_error(io: std.Io, path: []const u8, err: anyerror) !void {
    var err_buffer: [768]u8 = undefined;
    var out = std.Io.File.stderr().writer(io, &err_buffer);
    try write_io_error_to(&out.interface, path, err);
    try out.interface.flush();
}

pub fn print_compile_error(
    io: std.Io,
    path: []const u8,
    source: []const u8,
    tokens_opt: ?[]const lexer.Token,
    err: anyerror,
    explicit_loc: ?SourceLoc,
) !void {
    const diagnostic = build_compile_diagnostic(path, source, tokens_opt, err, explicit_loc);
    try print_diagnostic(io, diagnostic);
}

pub fn print_diagnostic(io: std.Io, diagnostic: CompileDiagnostic) !void {
    var err_buffer: [4096]u8 = undefined;
    var out = std.Io.File.stderr().writer(io, &err_buffer);
    try write_diagnostic_to(&out.interface, diagnostic);
    try out.interface.flush();
}

pub fn write_io_error_to(writer: anytype, path: []const u8, err: anyerror) !void {
    try writer.print("error[{s}]: {s}\n", .{ @errorName(err), error_summary(err) });
    try writer.print("at: {s}\n", .{path});
    try writer.print("hint: {s}\n", .{error_hint(err)});
}

pub fn write_diagnostic_to(writer: anytype, diagnostic: CompileDiagnostic) !void {
    const caret_col = if (diagnostic.loc.col == 0) 1 else diagnostic.loc.col;

    try writer.print("error[{s}]: {s}\n", .{ diagnostic.code, diagnostic.message });
    try writer.print(" --> {s}:{d}:{d}\n", .{ diagnostic.path, diagnostic.loc.line, diagnostic.loc.col });
    try writer.print(" hint: {s}\n", .{diagnostic.hint});
    if (diagnostic.line_text.len != 0) {
        try writer.print(" {d} | {s}\n", .{ diagnostic.loc.line, diagnostic.line_text });
        try writer.print("   | ", .{});
        try write_caret(writer, caret_col);
    }
}

fn write_caret(writer: anytype, col: usize) !void {
    const max_col = if (col > 256) 256 else col;
    var i: usize = 1;
    while (i < max_col) : (i += 1) {
        try writer.print(" ", .{});
    }
    try writer.print("^\n", .{});
}

fn locate_compile_error(
    err: anyerror,
    source: []const u8,
    tokens_opt: ?[]const lexer.Token,
    explicit_loc: ?SourceLoc,
) SourceLoc {
    if (explicit_loc) |loc| return loc;
    if (tokens_opt) |tokens| {
        if (locate_token_error(err, tokens)) |loc| return loc;
        if (tokens.len != 0) return .{ .line = tokens[0].line, .col = tokens[0].col };
    }
    if (locate_source_error(err, source)) |loc| return loc;
    return .{ .line = 1, .col = 1 };
}

fn locate_source_error(err: anyerror, source: []const u8) ?SourceLoc {
    return switch (err) {
        error.UnterminatedString => locate_unterminated_string(source),
        error.InvalidStringEscape => locate_invalid_string_escape(source),
        error.InvalidStringUtf8 => locate_invalid_string_utf8(source),
        error.InvalidComment => locate_invalid_comment(source),
        else => null,
    };
}

fn locate_unterminated_string(source: []const u8) ?SourceLoc {
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
        if (is_line_break(source, i)) {
            if (in_string) return .{ .line = str_line, .col = str_col };
            i = skip_line_break(source, i);
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

fn locate_invalid_string_escape(source: []const u8) ?SourceLoc {
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
        if (is_line_break(source, i)) {
            i = skip_line_break(source, i);
            line += 1;
            col = 1;
            in_string = false;
            continue;
        }
        if (in_string and ch == '\\') {
            const esc_len = string_escape_byte_len(source, i) orelse return .{ .line = line, .col = col };
            i += esc_len;
            col += esc_len;
            continue;
        }
        i += 1;
        col += 1;
    }
    return null;
}

fn locate_invalid_string_utf8(source: []const u8) ?SourceLoc {
    var line: usize = 1;
    var col: usize = 1;
    var i: usize = 0;
    while (i < source.len) {
        if (is_line_break(source, i)) {
            i = skip_line_break(source, i);
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

fn locate_invalid_comment(source: []const u8) ?SourceLoc {
    var line: usize = 1;
    var col: usize = 1;
    var i: usize = 0;
    while (i + 1 < source.len) {
        if (is_line_break(source, i)) {
            i = skip_line_break(source, i);
            line += 1;
            col = 1;
            continue;
        }
        if (source[i] == '/' and (source[i + 1] == '/' or source[i + 1] == '*')) {
            if (!is_comment_line_start(source, i)) return .{ .line = line, .col = col };
            if (source[i + 1] == '*' and !block_comment_closes_cleanly(source, i)) {
                return .{ .line = line, .col = col };
            }
        }
        i += 1;
        col += 1;
    }
    return null;
}

fn locate_token_error(err: anyerror, tokens: []const lexer.Token) ?SourceLoc {
    if (tokens.len == 0) return null;

    switch (err) {
        error.InvalidIfHeader,
        error.InvalidIfPatternBind,
        error.MultiReturnInIfCondition,
        error.MultiReturnInIfBindRhs,
        error.MultiReturnInLoopCondition,
        error.AmbiguousConditionCallReturnArity,
        error.InvalidBindingName,
        => return token_site(find_first_token(tokens, "if") orelse tokens[0]),

        error.InvalidLoopHeader => return token_site(find_first_token(tokens, "loop") orelse tokens[0]),
        error.InvalidNarrowing => return token_site(find_first_token(tokens, "is") orelse tokens[0]),
        error.UnionPayloadRequiresNarrowing => return token_site(tokens[0]),
        error.InvalidTestDecl => return token_site(find_first_token(tokens, "test") orelse tokens[0]),
        error.InvalidConstraintDecl => return token_site(find_first_token(tokens, "#") orelse tokens[0]),
        error.InvalidParamName => return token_site(find_first_token(tokens, "(") orelse tokens[0]),
        error.InvalidImportDecl => return token_site(find_first_token(tokens, "@") orelse tokens[0]),
        error.InvalidStartEntrySig, error.DuplicateStartEntry => return token_site(find_first_token(tokens, "start") orelse tokens[0]),
        error.MissingStartEntry => return token_site(tokens[0]),
        error.InvalidBraceExpr => return token_site(find_first_token(tokens, "{") orelse tokens[0]),
        error.InvalidReturnStmt => return token_site(find_first_token_on_line(tokens, "return") orelse find_first_token(tokens, "return") orelse tokens[0]),
        error.InvalidStructLiteral => return token_site(find_first_struct_lit_token(tokens) orelse tokens[0]),
        error.PrivateIdentCannotBeLValue => return token_site(find_first_private_ident(tokens) orelse tokens[0]),
        error.DuplicateImmutableBinding => return token_site(find_duplicate_immutable(tokens) orelse tokens[0]),
        error.DuplicateLocalBinding => return token_site(tokens[0]),
        error.InvalidCallArgList => return token_site(find_trailing_comma_token(tokens) orelse tokens[0]),
        error.NoTopLevelDecl => return token_site(tokens[0]),
        else => return token_site(tokens[0]),
    }
}

fn token_site(tok: lexer.Token) SourceLoc {
    return .{ .line = tok.line, .col = tok.col };
}

fn find_first_token(tokens: []const lexer.Token, lexeme: []const u8) ?lexer.Token {
    for (tokens) |tok| {
        if (std.mem.eql(u8, tok.lexeme, lexeme)) return tok;
    }
    return null;
}

fn find_first_token_on_line(tokens: []const lexer.Token, lexeme: []const u8) ?lexer.Token {
    if (tokens.len == 0) return null;
    const target_line = tokens[0].line;
    for (tokens) |tok| {
        if (tok.line != target_line) continue;
        if (std.mem.eql(u8, tok.lexeme, lexeme)) return tok;
    }
    return null;
}

fn find_first_struct_lit_token(tokens: []const lexer.Token) ?lexer.Token {
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

fn find_first_private_ident(tokens: []const lexer.Token) ?lexer.Token {
    for (tokens) |tok| {
        if (tok.kind != .ident) continue;
        if (tok.lexeme.len == 0) continue;
        if (tok.lexeme[0] == '.') return tok;
    }
    return null;
}

fn find_duplicate_immutable(tokens: []const lexer.Token) ?lexer.Token {
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

fn find_trailing_comma_token(tokens: []const lexer.Token) ?lexer.Token {
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (!std.mem.eql(u8, tokens[i].lexeme, ",")) continue;
        if (!std.mem.eql(u8, tokens[i + 1].lexeme, ")")) continue;
        return tokens[i];
    }
    return find_first_token(tokens, ",");
}

fn get_line_text(source: []const u8, target_line: usize) []const u8 {
    if (target_line == 0) return "";

    var line: usize = 1;
    var start: usize = 0;
    var i: usize = 0;
    while (i < source.len) {
        if (!is_line_break(source, i)) {
            i += 1;
            continue;
        }
        if (line == target_line) return source[start..i];
        i = skip_line_break(source, i);
        line += 1;
        start = i;
    }
    if (line == target_line) return source[start..source.len];
    return "";
}

/// Bytes consumed by a string escape starting at `\` (`source[idx] == '\\'`).
/// Returns null when the escape is incomplete or invalid.
fn string_escape_byte_len(source: []const u8, idx: usize) ?usize {
    if (idx + 1 >= source.len) return null;
    const esc = source[idx + 1];
    if (esc == '"' or esc == '\\' or esc == 'n' or esc == 'r' or esc == 't') return 2;
    if (esc != 'x') return null;
    if (idx + 3 >= source.len or !std.ascii.isHex(source[idx + 2]) or !std.ascii.isHex(source[idx + 3])) return null;
    return 4;
}

fn is_line_break(source: []const u8, idx: usize) bool {
    return source[idx] == '\n' or source[idx] == '\r';
}

fn skip_line_break(source: []const u8, idx: usize) usize {
    if (source[idx] == '\r' and idx + 1 < source.len and source[idx + 1] == '\n') return idx + 2;
    return idx + 1;
}

fn is_comment_line_start(source: []const u8, idx: usize) bool {
    var i = idx;
    while (i > 0) : (i -= 1) {
        const prev = source[i - 1];
        if (prev == '\n' or prev == '\r') return true;
        if (prev != ' ' and prev != '\t') return false;
    }
    return true;
}

fn block_comment_closes_cleanly(source: []const u8, start_idx: usize) bool {
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

pub fn error_summary(err: anyerror) []const u8 {
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
        error.InvalidResultType => "`Result` 是内建类型，必须写作 `Result<T, E>`",
        error.InvalidResultConstructor => "`Ok`/`Err` 只能在已知 `Result<T, E>` 目标类型中构造",
        error.InvalidPathIndex => "路径参数写作 `@get(value, index, .field)`；字段段写作 `.field`；`Tuple` 数字索引必须是编译期整数字面量且落在 `0..arity-1`",
        error.InvalidPathAccess => "字段读取语法: `@get(value, .field)`; 字段写入语法: `@set(value, .field, new_value)`；字段段只用于 @get/@set 路径参数",
        error.InvalidFieldReflection => "字段反射语法: `loop field = fields(StructOrTypeParam) { ... }`; `@field_*` 的 field 参数必须来自当前字段反射循环",
        error.InvalidNarrowing => "收窄语法: `@is(value, Type)` 只能直接作为条件头使用; Type 必须是单个可达非 nil 类型",
        error.DeprecatedAsyncFunctionDecl => "`async name(...) -> T` 已弃用；改写为普通 `name(...) -> T`，用 `Future<T> = @async(name(...))` 创建任务",
        error.InvalidAsyncReturn => "`async name(...) -> T` 仅是迁移期兼容；普通函数不能直接返回 `Future<T>`",
        error.ImplicitFutureCreation => "普通函数调用不会隐式创建 Future；改写为 `Future<T> = @async(call(...))`；仅登记的 WIT async host binding 可直接返回 Future",
        error.InvalidAwaitContext => "`@await` 和 `@cancel` 只能在包含异步操作的普通函数中消费 `Future<T>` 局部绑定",
        error.FutureAlreadyConsumed => "每个 `Future<T>` 只能被 await、取消或聚合等待消费一次",
        error.FutureDropped => "`Future<T>` 不能在函数作用域结束时未消费",
        error.StreamReaderAlreadyConsumed => "每个 `StreamReader<T>` 只能转移给一个消费者",
        error.StreamReaderTypeMismatch => "`StreamReader<T>` 只能转移给相同元素类型的 consumer",
        error.InvalidStreamReaderRead => "`@next(reader)` 只能在包含异步操作的普通函数中读取当前 `Stream<T>` 或 `StreamReader<T>` owner，并绑定为 `Future<Result<T, nil>>`",
        error.StreamWriterLeaseDropped => "`StreamWriter<T>` lease 不能在 async 作用域结束时未收尾",
        error.StreamWriterLeasePathConflict => "`StreamWriter<T>` lease 在控制流合流后没有一致的收尾状态",
        error.StreamWriterDeferredTransfer => "`StreamWriter<T>` lease 不能带着当前作用域的 defer cleanup 转移",
        error.StreamWriterAlreadyFinalized => "每个 `StreamWriter<T>` lease 只能转移、关闭或中止一次",
        error.StreamWriterTypeMismatch => "`StreamWriter<T>` lease 只能转移给相同元素类型的 owner",
        error.InvalidStreamWriterFinalization => "`close`/`abort` 只能终结当前包含异步操作的普通函数中的 `StreamWriter<T>` owner",
        error.InvalidStreamWriterWrite => "`writer(value)` 必须返回 `Future<Result<nil, E>>`，且 value 类型必须与 `StreamWriter<T>` 的 T 相同",
        error.UnknownP3AsyncHostDescriptor => "P3 async host descriptor 未在 pinned registry 中登记",
        error.P3AsyncHostSignatureMismatch => "P3 async host 声明签名与 pinned descriptor 不一致",
        error.ResourceAlreadyConsumed => "资源 owner 已通过 own 调用、drop 或同类型赋值转移，不能再次使用",
        error.ResourceDropped => "资源 owner 不能在作用域结束时仍处于活动状态；必须显式 transfer 或 drop",
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
        error.InvalidImportDecl => "导入使用 `name = @lib(\"file.do\", symbol)`, `name = @lib(\"./file.do\", symbol)`, `name = @lib(\"~/vendor.name.do\", symbol)`；同步 host import 使用 `@host_func(\"env\", \"name\", (...) -> Type)` 或 `@host_func(\"wasi:pkg/iface@0.3.0\", \"member\", (...) -> Type)`，WIT async func 使用 `@host_async_func(...)`",
        error.GeneratedWitManifestMissing => "生成的 `wit/*.do` 模块必须和同目录 `manifest.json` 一起使用",
        error.GeneratedWitManifestInvalid => "生成的 WIT manifest 结构无效；重新运行 `do wit bind`",
        error.GeneratedWitManifestMismatch => "生成的 WIT 模块、manifest 哈希或 async/future 元数据不一致；重新运行 `do wit bind`",
        error.NoTopLevelDecl => "top-level 项写作 import/type/value/start/func/test",
        error.NoTestDecl => "在文件顶层添加 `test \"name\" { ... }`",
        error.InvalidTestDecl => "使用 `test \"name\" { ... }` 顶层声明",
        error.InvalidConstraintDecl => "约束独立成行；类型参数名写作 `UpperIdent`，函数约束前必须先有类型约束",
        error.InvalidParamName => "参数名写作 `snake_case`; `_name` 写作顶层常量和局部只读绑定",
        error.MissingStartEntry => "编译入口写作 `start() { ... }`",
        error.InvalidStartEntrySig => "入口签名写作 `start() { ... }` (无参、无返回)",
        error.DuplicateStartEntry => "顶层 `start` 写作 1 次",
        error.UnsupportedWasiHostImport => "这个 WIT host import 签名尚未支持 lowering",
        error.AsyncLoweringUnavailable => "async 声明已通过前端检查，但 resumable lowering 尚未实现",
        error.UnsupportedP3WaitForComponent => "此 P3 Component 目标只支持 pinned wait-for probe 源码形态",
        error.UnsupportedP3AsyncResourceComponent => "此 P3 Component 目标只支持 private async resource Result probe 源码形态",
        error.UnsupportedP3OwnedFutureComponent => "此 P3 Component 目标只支持 private Future<Ticket> -> future<own<ticket>> 源码形态",
        error.UnsupportedP3BatchedListResourceProducer => "此 P3 Component 目标只支持 pinned batched list resource producer 源码形态",
        error.UnsupportedP3AsyncComponent => "此统一 P3 async Component 目标不支持该 descriptor 或源码形态",
        error.UnsupportedGenericAbiV2Promotion => "Generic ABI v2 promotion profile rejected this target",
        error.UnsupportedGenericAbiV2Scalar => "opt-in Generic ABI v2 只接受 pinned generated Future<i64> scalar shape",
        error.InvalidGenericAbiV2ScalarLayout => "Generic ABI v2 scalar-i64 的 measured layout 无效",
        error.InvalidGenericAbiV2ScalarTemplate => "Generic ABI v2 scalar-i64 模板不完整",
        error.UnsupportedGcCoreLowering => "此 Core Wasm GC target 只支持已实现的受限源码形态",
        error.UnsupportedLowering => "当前编译路径尚未支持该 lowering",
        error.UnsupportedTupleStorageLeaf => "非 packable 叶子的 `[Tuple]` storage 尚未支持 scheme-A pack",
        error.MissingOutputPath => "示例: `do build input.do -o out.wat` 或 `do test sample.do --compiled -o sample.wat`",
        error.MissingP3WitOutputPath => "`--p3-wit-output` 后需要一个 WIT 输出路径",
        error.P3WitOutputRequiresP3Target => "`--p3-wit-output` 只能与 P3 Component target 一起使用",
        error.MissingP3WitPackageOutputPath => "`--p3-wit-package-output` 后需要一个目录输出路径",
        error.P3WitPackageOutputRequiresP3Target => "`--p3-wit-package-output` 只能与 P3 Component target 一起使用",
        error.P3WitPackageOutputRequiresUnifiedTarget => "`--p3-wit-package-output` 只能与 `--p3-async-component` 一起使用",
        error.P3WitPackageOutputRequiresHttpService => "`--p3-wit-package-output` 只用于 pinned `wasi:http/client.send` service package",
        error.MissingTestInputPath => "示例: `do test sample.do` 或 `do test sample.do --compiled -o sample.wat`",
        error.UnexpectedCliArg => "命令只接受一个输入文件和已声明的选项",
        error.OutputRequiresCompiledTest => "`do test -o out.wat` 需要同时写 `--compiled`",
        error.FormatMismatch => "input is not formatted",
        else => "编译失败",
    };
}

pub fn error_hint(err: anyerror) []const u8 {
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
        error.InvalidResultType => "`Result` 是内建类型，必须写作 `Result<T, E>`",
        error.InvalidResultConstructor => "`Ok`/`Err` 只能在已知 `Result<T, E>` 目标类型中构造",
        error.InvalidPathIndex => "路径参数写作 `@get(value, index, .field)`；字段段写作 `.field`；`Tuple` 数字索引必须是编译期整数字面量且落在 `0..arity-1`",
        error.InvalidPathAccess => "字段段只用于 @get/@set 路径参数；普通函数参数使用有类型表达式",
        error.InvalidFieldReflection => "`fields(...)` 只接收可见结构体或当前泛型类型参数；`@field_set` 写作 `target = @field_set(target, field, value)`",
        error.InvalidNarrowing => "`@is` 不进入普通值表达式或 `@and/@or/@not` 子条件; v1 不支持 `@is(value, A | B)` 或 `@is(value, nil)`",
        error.DeprecatedAsyncFunctionDecl => "删除声明前的 `async`；普通函数通过 `@async(call)` 显式创建 Future，再用 `@await` 或 `@cancel` 消费",
        error.InvalidAsyncReturn => "`async name(...) -> T` 仅是迁移期兼容；普通函数不能直接返回 `Future<T>`，也不能声明 `Future<T>` 返回形态",
        error.ImplicitFutureCreation => "把 `Future<T> = call(...)` 改成 `Future<T> = @async(call(...))`；WIT `async func` 生成 binding 是唯一直接调用例外",
        error.InvalidAwaitContext => "`@await(future)`、聚合等待或 `@cancel(future)` 只能写在包含异步操作的普通函数中，参数必须是可见的 `Future<T>` 局部绑定",
        error.FutureAlreadyConsumed => "Future 已被消费；await、取消和聚合等待都会转移其所有权",
        error.FutureDropped => "在返回、失败或取消清理前消费 Future；不能让 Future 静默离开函数作用域",
        error.StreamReaderAlreadyConsumed => "reader 已转移给另一消费者；保留唯一 owner 并从该绑定继续读取",
        error.StreamReaderTypeMismatch => "目标绑定的 `T` 必须与当前 `StreamReader<T>` owner 相同",
        error.InvalidStreamReaderRead => "在包含异步操作的普通函数中写 `pending Future<Result<T, nil>> = @next(reader)`；reader 与 Result 的 T 必须相同",
        error.StreamWriterLeaseDropped => "在作用域结束前调用 `close(writer)`、`abort(writer, err)`，或使用 `defer close(writer)`",
        error.StreamWriterLeasePathConflict => "让每条可达路径都执行相同的 `close`/`abort`/`defer close`，再使用或离开作用域",
        error.StreamWriterDeferredTransfer => "在当前 defer 作用域内调用 `close`/`abort`，或移除 defer 后再转移唯一 owner",
        error.StreamWriterAlreadyFinalized => "writer 已转移或完成收尾；从当前唯一 owner 继续使用",
        error.StreamWriterTypeMismatch => "目标绑定的 `T` 必须与当前 `StreamWriter<T>` owner 相同",
        error.InvalidStreamWriterFinalization => "在包含异步操作的普通函数中对当前 writer 调用 `close(writer)` 或 `abort(writer, err)`",
        error.InvalidStreamWriterWrite => "在包含异步操作的普通函数中写 `pending Future<Result<nil, E>> = writer(value)`；value 与 writer 的 T 必须相同",
        error.UnknownP3AsyncHostDescriptor => "使用已登记的 locator/member；不要由名称推断 WIT async ABI",
        error.P3AsyncHostSignatureMismatch => "当前 pinned wait-for 声明写作 `(u64) -> nil`",
        error.ResourceAlreadyConsumed => "从当前唯一 owner 继续使用；own 调用、drop 和同类型赋值都会转移它",
        error.ResourceDropped => "在离开作用域前 transfer 给新绑定，或调用已登记的 drop host import",
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
        error.DuplicateHostImportAlias => "`@host` alias 是当前模块内的 host binding 身份; 同名 binding 要放在不同 source 模块或改名",
        error.DuplicateStructFieldName => "结构体字段名按去掉私有标记后的名字唯一; 每个字段名保留 1 个声明",
        error.MultiReturnInIfCondition => "先接收多返回值, 再在 if 使用单值变量",
        error.MultiReturnInIfBindRhs => "if 条件语法使用单值 bool 表达式",
        error.MultiReturnInLoopCondition => "先接收多返回值, 再在 loop 条件使用单值变量",
        error.MultiReturnInSingleValuePosition => "写作 `a, b = f()` 或 `return f()`; 单变量、实参和聚合元素位不能隐式承载多返回",
        error.AmbiguousConditionCallReturnArity => "给实参加类型或先绑定到具体签名, 让调用返回位数唯一",
        error.InvalidImportDecl => "导入语法: `name = @lib(\"file.do\", symbol)`, `name = @lib(\"./file.do\", symbol)`, `name = @lib(\"~/vendor.name.do\", symbol)`; 同步 host import 使用 `@host_func(...)`，WIT async func 使用 `@host_async_func(...)`；旧 `@host` 与 `@host_sync_func` 不接受",
        error.GeneratedWitManifestMissing => "恢复同目录 `manifest.json`，或从 WIT 源重新运行 `do wit bind`",
        error.GeneratedWitManifestInvalid => "不要手工编辑 generated manifest；重新运行 `do wit bind`",
        error.GeneratedWitManifestMismatch => "同步生成的 `.do` 文件和 `manifest.json`；普通 host 调用不会绕过这个校验",
        error.NoTopLevelDecl => "至少声明 1 个 top-level 项: import/type/value/start/func/test",
        error.NoTestDecl => "在文件顶层添加 `test \"name\" { ... }`",
        error.InvalidTestDecl => "使用 `test \"name\" { ... }` 顶层声明",
        error.InvalidConstraintDecl => "约束独立成行；类型参数名写作 `UpperIdent`，函数约束前必须先有类型约束",
        error.InvalidParamName => "参数名写作 `snake_case`; `_name` 写作顶层常量和局部只读绑定",
        error.MissingStartEntry => "编译入口写作 `start() { ... }`",
        error.InvalidStartEntrySig => "入口签名写作 `start() { ... }` (无参、无返回)",
        error.DuplicateStartEntry => "顶层 `start` 写作 1 次",
        error.UnsupportedWasiHostImport => "已登记的 scalar/record/list<u8>、descriptor.sync 语句调用和 descriptor.write 多左值调用可 lower；复杂 result/resource/variant/flags 需要后续 component lowering",
        error.AsyncLoweringUnavailable => "先使用 `do check` 验证前端；`do build` 需要 await frame、调度和清理 lowering",
        error.UnsupportedP3WaitForComponent => "旧版 pinned P3 compatibility probe 仍使用迁移期 `async run(u64) -> nil`；新源码使用普通 `run(u64) -> nil` 与 `@await/@cancel`，其他 async 形式仍由 AsyncLoweringUnavailable 拒绝",
        error.UnsupportedP3AsyncResourceComponent => "旧版 private probe 仍使用迁移期 `async run(HttpRequest) -> Result<HttpResponse, HttpError>`；新源码使用普通函数声明与显式 `@await/@cancel`，真实 HTTP 仅支持固定 `wasi:http/client.send` service 源码形态",
        error.UnsupportedP3OwnedFutureComponent => "仅使用已注册的 `Future<Ticket>`、单次 `@await` 与 `--p3-owned-future-component`；own/borrow/ref 不是 Do 源码语法",
        error.UnsupportedP3BatchedListResourceProducer => "源码必须只包含已登记 batched descriptor、`StreamWriter<[ResourceEntry]>` sink、`produce(mode u32) -> Result<nil, ProducerError>` 与空额外状态；任意 producer expression、borrow 或第二个 sink 均拒绝",
        error.UnsupportedP3AsyncComponent => "使用 `--p3-async-component` 时，支持已登记的 scalar/unit clocks、`wasi:cli/run.run` 的 `Result<nil,nil>`、private `do:resource-probe/http/send` 两字 Result，以及固定 `wasi:http/client.send` service；list、Stream、payload error-code 与其他 descriptor 仍需完整 canonical layout lowering",
        error.UnsupportedGenericAbiV2Promotion => "`--p3-async-component-v2` 只接受已测量的 private variant-resource-stream 与 generated `Future<i64>` shape；其他 target 在 WAT 生成前保持拒绝",
        error.UnsupportedGenericAbiV2Scalar => "使用 `--p3-async-v2-scalar-i64` 时必须加载 pinned generated `Future<i64>` manifest；其他 payload、签名或模块路径保持拒绝",
        error.InvalidGenericAbiV2ScalarLayout => "generated scalar-i64 manifest 的 core width、offset、byte-size 或 alignment 与已测量 ABI 不一致",
        error.InvalidGenericAbiV2ScalarTemplate => "Generic ABI v2 scalar-i64 emitter template 缺少必需的 ABI placeholder",
        error.UnsupportedGcCoreLowering => "使用 `identity(value text) -> text { return value }`，或 `update(input [u8]) -> [u8] { return @set(input, 0, 65) }`，并使用空 `start()`；其他 text/list/managed struct GC lowering 尚未接入该 target",
        error.UnsupportedLowering => "常见后置边界: 非 packable 的 `[Tuple]` storage 直接元素；该错误不是重载匹配失败",
        error.UnsupportedTupleStorageLeaf => "直接元素须为标量、managed handle (`text` / `[T]`)、嵌套 Tuple、pure-scalar 具名 struct 子布局、或含 managed 字段的具名 struct 句柄槽；禁止拍平为扁平 Tuple；该错误不是重载匹配失败",
        error.MissingOutputPath => "示例: `do build input.do -o out.wat` 或 `do test sample.do --compiled -o sample.wat`",
        error.MissingP3WitOutputPath => "写作 `--p3-wit-output out.wit`；它与 `--p3-async-component` 配对输出 assembly sidecar",
        error.P3WitOutputRequiresP3Target => "写作 `do build input.do --p3-async-component --p3-wit-output out.wit -o out.wat`",
        error.MissingP3WitPackageOutputPath => "写作 `--p3-wit-package-output out.wit-package`；该目录保留完整 WIT dependencies",
        error.P3WitPackageOutputRequiresP3Target => "写作 `do build input.do --p3-async-component --p3-wit-package-output out.wit-package -o out.wat`",
        error.P3WitPackageOutputRequiresUnifiedTarget => "使用统一 `--p3-async-component`，不与单独 probe target 混用",
        error.P3WitPackageOutputRequiresHttpService => "源码必须声明 pinned `wasi:http/client@0.3.0-rc-2025-09-16` 的固定 async `send` service 形态；该 package 不启用通用 HTTP/resource/Stream lowering",
        error.MissingTestInputPath => "示例: `do test sample.do` 或 `do test sample.do --compiled -o sample.wat`",
        error.UnexpectedCliArg => "build 写作 `do build input.do [-o out.wat]`; test 写作 `do test input.do` 或 `do test input.do --compiled [-o out.wat]`",
        error.OutputRequiresCompiledTest => "生成 WAT 的测试入口写作 `do test input.do --compiled -o out.wat`",
        error.FormatMismatch => "运行 `do fmt input.do` 查看格式化后的 stdout 输出",
        else => "语法示例: `if expr { ... }`, `loop { ... }`, `@get(value, .field)`, `Type{field = value}`",
    };
}

test "build_compile_diagnostic uses explicit source location" {
    const source =
        \\one
        \\two
        \\three
        \\
    ;
    const diagnostic = build_compile_diagnostic(
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
    try std.testing.expectEqualStrings(error_summary(error.InvalidIfHeader), diagnostic.message);
    try std.testing.expectEqualStrings(error_hint(error.InvalidIfHeader), diagnostic.hint);
}

test "return statement diagnostic has specific summary" {
    try std.testing.expectEqualStrings(
        "return 语句返回位数不匹配",
        error_summary(error.InvalidReturnStmt),
    );
}

test "tuple non-packable storage leaf has dedicated diagnostic" {
    try std.testing.expectEqualStrings(
        "非 packable 叶子的 `[Tuple]` storage 尚未支持 scheme-A pack",
        error_summary(error.UnsupportedTupleStorageLeaf),
    );
    try std.testing.expectEqualStrings(
        "直接元素须为标量、managed handle (`text` / `[T]`)、嵌套 Tuple、pure-scalar 具名 struct 子布局、或含 managed 字段的具名 struct 句柄槽；禁止拍平为扁平 Tuple；该错误不是重载匹配失败",
        error_hint(error.UnsupportedTupleStorageLeaf),
    );
    const diagnostic = build_compile_diagnostic(
        "tuple_storage.do",
        "items [Tuple<Point, u8>] = .{}\n",
        null,
        error.UnsupportedTupleStorageLeaf,
        .{ .line = 1, .col = 1 },
    );
    try std.testing.expectEqualStrings("UnsupportedTupleStorageLeaf", diagnostic.code);
    try std.testing.expectEqualStrings(error_summary(error.UnsupportedTupleStorageLeaf), diagnostic.message);
    try std.testing.expectEqualStrings(error_hint(error.UnsupportedTupleStorageLeaf), diagnostic.hint);
}

test "P3 async component diagnostic includes the admitted HTTP service" {
    try std.testing.expectEqualStrings(
        "使用 `--p3-async-component` 时，支持已登记的 scalar/unit clocks、`wasi:cli/run.run` 的 `Result<nil,nil>`、private `do:resource-probe/http/send` 两字 Result，以及固定 `wasi:http/client.send` service；list、Stream、payload error-code 与其他 descriptor 仍需完整 canonical layout lowering",
        error_hint(error.UnsupportedP3AsyncComponent),
    );
}

test "Generic ABI v2 promotion diagnostic names the two admitted shapes" {
    try std.testing.expectEqualStrings(
        "Generic ABI v2 promotion profile rejected this target",
        error_summary(error.UnsupportedGenericAbiV2Promotion),
    );
    try std.testing.expectEqualStrings(
        "`--p3-async-component-v2` 只接受已测量的 private variant-resource-stream 与 generated `Future<i64>` shape；其他 target 在 WAT 生成前保持拒绝",
        error_hint(error.UnsupportedGenericAbiV2Promotion),
    );
}

test "path-sensitive writer diagnostics have dedicated summary and hint" {
    try std.testing.expectEqualStrings(
        "`StreamWriter<T>` lease 在控制流合流后没有一致的收尾状态",
        error_summary(error.StreamWriterLeasePathConflict),
    );
    try std.testing.expectEqualStrings(
        "让每条可达路径都执行相同的 `close`/`abort`/`defer close`，再使用或离开作用域",
        error_hint(error.StreamWriterLeasePathConflict),
    );
    try std.testing.expectEqualStrings(
        "`StreamWriter<T>` lease 不能带着当前作用域的 defer cleanup 转移",
        error_summary(error.StreamWriterDeferredTransfer),
    );
    try std.testing.expectEqualStrings(
        "在当前 defer 作用域内调用 `close`/`abort`，或移除 defer 后再转移唯一 owner",
        error_hint(error.StreamWriterDeferredTransfer),
    );
}

test "colorless async diagnostics do not advertise legacy async declarations" {
    try std.testing.expectEqualStrings(
        "`@next(reader)` 只能在包含异步操作的普通函数中读取当前 `Stream<T>` 或 `StreamReader<T>` owner，并绑定为 `Future<Result<T, nil>>`",
        error_summary(error.InvalidStreamReaderRead),
    );
    try std.testing.expectEqualStrings(
        "在包含异步操作的普通函数中写 `pending Future<Result<T, nil>> = @next(reader)`；reader 与 Result 的 T 必须相同",
        error_hint(error.InvalidStreamReaderRead),
    );
    try std.testing.expectEqualStrings(
        "`close`/`abort` 只能终结当前包含异步操作的普通函数中的 `StreamWriter<T>` owner",
        error_summary(error.InvalidStreamWriterFinalization),
    );
    try std.testing.expectEqualStrings(
        "在包含异步操作的普通函数中对当前 writer 调用 `close(writer)` 或 `abort(writer, err)`",
        error_hint(error.InvalidStreamWriterFinalization),
    );
    try std.testing.expectEqualStrings(
        "在包含异步操作的普通函数中写 `pending Future<Result<nil, E>> = writer(value)`；value 与 writer 的 T 必须相同",
        error_hint(error.InvalidStreamWriterWrite),
    );
}

test "build_compile_diagnostic falls back to source lexer location" {
    const source = "\"abc";
    const diagnostic = build_compile_diagnostic(
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
