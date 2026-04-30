const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema = @import("sema.zig");
const codegen = @import("codegen.zig");
const cmd_test = @import("cmd/test.zig");

const SourceLoc = struct {
    line: usize,
    col: usize,
};

const CliMode = enum {
    compile,
    test_mode,
};

const CliArgs = struct {
    mode: CliMode,
    input_path: []const u8,
    output_path: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printUsage();
        return;
    }

    const cli = parseCliArgs(args) catch |err| {
        try printCliError(err);
        std.process.exit(1);
    };

    const source = std.fs.cwd().readFileAlloc(allocator, cli.input_path, 16 * 1024 * 1024) catch |err| {
        try printIoError(cli.input_path, err);
        std.process.exit(1);
    };
    defer allocator.free(source);

    const tokens = lexer.tokenize(allocator, source) catch |err| {
        try printCompileError(cli.input_path, source, null, err, null);
        std.process.exit(1);
    };
    defer allocator.free(tokens);

    var program = parser.parseProgram(allocator, tokens, source.len) catch |err| {
        const parser_site = parser.takeLastErrorSite();
        const explicit = if (parser_site) |site| SourceLoc{ .line = site.line, .col = site.col } else null;
        try printCompileError(cli.input_path, source, tokens, err, explicit);
        std.process.exit(1);
    };
    defer program.deinit(allocator);

    sema.checkProgram(allocator, program, tokens) catch |err| {
        const sema_site = sema.takeLastErrorSite();
        const explicit = if (sema_site) |site| SourceLoc{ .line = site.line, .col = site.col } else null;
        try printCompileError(cli.input_path, source, tokens, err, explicit);
        std.process.exit(1);
    };

    switch (cli.mode) {
        .compile => {
            validateStartEntry(program) catch |err| {
                try printCompileError(cli.input_path, source, tokens, err, null);
                std.process.exit(1);
            };

            const wat = codegen.emitWat(allocator, program) catch |err| {
                try printCompileError(cli.input_path, source, tokens, err, null);
                std.process.exit(1);
            };
            defer allocator.free(wat);

            std.fs.cwd().writeFile(.{ .sub_path = cli.output_path, .data = wat }) catch |err| {
                try printIoError(cli.output_path, err);
                std.process.exit(1);
            };

            var out_buffer: [1024]u8 = undefined;
            var out = std.fs.File.stdout().writer(&out_buffer);
            try out.interface.print(
                "ok: {s} -> {s} (tokens={d}, items={d})\n",
                .{ cli.input_path, cli.output_path, program.token_count, program.top_level_count },
            );
            try out.interface.flush();
        },
        .test_mode => {
            cmd_test.run(allocator, tokens) catch |err| {
                try printCompileError(cli.input_path, source, tokens, err, null);
                std.process.exit(1);
            };
        },
    }
}

fn parseCliArgs(args: []const []const u8) !CliArgs {
    if (args.len < 2) return error.MissingInputPath;
    if (std.mem.eql(u8, args[1], "test")) {
        if (args.len < 3) return error.MissingTestInputPath;
        return .{
            .mode = .test_mode,
            .input_path = args[2],
            .output_path = "",
        };
    }

    return .{
        .mode = .compile,
        .input_path = args[1],
        .output_path = try parseOutputPath(args),
    };
}

fn validateStartEntry(program: parser.Program) !void {
    var start_count: usize = 0;
    var start_sig: ?parser.FuncSig = null;

    for (program.func_sigs) |sig| {
        if (!std.mem.eql(u8, sig.name, "_start")) continue;
        start_count += 1;
        if (start_sig == null) start_sig = sig;
    }

    if (start_count == 0) return error.MissingStartEntry;
    if (start_count > 1) return error.DuplicateStartEntry;
    if (start_sig == null) return error.MissingStartEntry;

    const sig = start_sig.?;
    if (sig.param_min != 0) return error.InvalidStartEntrySig;
    if (sig.param_max == null) return error.InvalidStartEntrySig;
    if (sig.param_max.? != 0) return error.InvalidStartEntrySig;
    if (sig.return_arity != 0) return error.InvalidStartEntrySig;
}

fn parseOutputPath(args: []const []const u8) ![]const u8 {
    var out: []const u8 = "out.wat";
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (!std.mem.eql(u8, args[i], "-o")) continue;
        if (i + 1 >= args.len) return error.MissingOutputPath;
        out = args[i + 1];
        i += 1;
    }
    return out;
}

fn printUsage() !void {
    var out_buffer: [384]u8 = undefined;
    var out = std.fs.File.stdout().writer(&out_buffer);
    try out.interface.print(
        \\do compiler (bootstrap)
        \\usage:
        \\  do <input.do> [-o out.wat]
        \\  do test <input.do>
        \\
    , .{});
    try out.interface.flush();
}

fn printCliError(err: anyerror) !void {
    var err_buffer: [512]u8 = undefined;
    var out = std.fs.File.stderr().writer(&err_buffer);
    try out.interface.print("error[{s}]: {s}\n", .{ @errorName(err), errorSummary(err) });
    try out.interface.print("hint: {s}\n", .{ errorHint(err) });
    try out.interface.flush();
}

fn printIoError(path: []const u8, err: anyerror) !void {
    var err_buffer: [768]u8 = undefined;
    var out = std.fs.File.stderr().writer(&err_buffer);
    try out.interface.print("error[{s}]: {s}\n", .{ @errorName(err), errorSummary(err) });
    try out.interface.print("at: {s}\n", .{ path });
    try out.interface.print("hint: {s}\n", .{ errorHint(err) });
    try out.interface.flush();
}

fn printCompileError(
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
    var out = std.fs.File.stderr().writer(&err_buffer);
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
        => return tokenSite(findFirstToken(tokens, "if") orelse tokens[0]),

        error.InvalidLoopHeader => return tokenSite(findFirstToken(tokens, "loop") orelse tokens[0]),
        error.InvalidMatchHeader,
        error.MultiReturnInMatchTarget,
        => return tokenSite(findFirstToken(tokens, "match") orelse tokens[0]),
        error.InvalidTestDecl => return tokenSite(findFirstToken(tokens, "test") orelse tokens[0]),
        error.InvalidImportDecl => return tokenSite(findFirstToken(tokens, "@") orelse tokens[0]),
        error.InvalidStartEntrySig, error.DuplicateStartEntry => return tokenSite(findFirstToken(tokens, "_start") orelse tokens[0]),
        error.MissingStartEntry => return tokenSite(tokens[0]),
        error.InvalidDoExpr => return tokenSite(findFirstToken(tokens, "do") orelse tokens[0]),
        error.DoneCallNeedsArg, error.DoneCallArity => return tokenSite(findFirstToken(tokens, "done") orelse tokens[0]),
        error.AsyncCtrlArity => return tokenSite(findFirstAsyncCtrlToken(tokens) orelse tokens[0]),
        error.InvalidBraceExpr => return tokenSite(findFirstToken(tokens, "{") orelse tokens[0]),
        error.InvalidListLiteral => return tokenSite(findFirstToken(tokens, "List") orelse tokens[0]),
        error.InvalidMapLiteral => return tokenSite(findFirstToken(tokens, "Map") orelse tokens[0]),
        error.InvalidTupleLiteral => return tokenSite(findFirstToken(tokens, "Tuple") orelse tokens[0]),
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

fn findFirstAsyncCtrlToken(tokens: []const lexer.Token) ?lexer.Token {
    for (tokens) |tok| {
        if (std.mem.eql(u8, tok.lexeme, "wait")) return tok;
        if (std.mem.eql(u8, tok.lexeme, "wait_one")) return tok;
        if (std.mem.eql(u8, tok.lexeme, "wait_any")) return tok;
        if (std.mem.eql(u8, tok.lexeme, "wait_all")) return tok;
        if (std.mem.eql(u8, tok.lexeme, "cancel")) return tok;
        if (std.mem.eql(u8, tok.lexeme, "status")) return tok;
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
        error.UnterminatedString => "字符串未闭合",
        error.InvalidIfHeader => "if 头部语法无效",
        error.InvalidMatchHeader => "match 头部语法无效",
        error.InvalidLoopHeader => "loop 头部语法无效",
        error.InvalidStructLiteral => "结构体字面量语法无效",
        error.InvalidTypeDeclName => "类型声明命名不合法",
        error.InvalidFuncDeclName => "函数声明命名不合法",
        error.InvalidTypedLiteral => "集合字面量语法无效",
        error.InvalidBraceExpr => "花括号表达式语法无效",
        error.InvalidListLiteral => "List 字面量语法无效",
        error.InvalidMapLiteral => "Map 字面量语法无效",
        error.InvalidTupleLiteral => "Tuple 字面量语法无效",
        error.InvalidCallArgList => "调用参数列表语法无效",
        error.LiteralCannotBeCalled => "字面量不能作为函数调用",
        error.DoneCallNeedsArg => "done 调用缺少参数",
        error.DoneCallArity => "done 只允许 1 个参数",
        error.AsyncCtrlArity => "异步控制函数参数个数不合法",
        error.InvalidIfPatternBind => "if 模式绑定必须使用类型模式",
        error.PrivateIdentCannotBeLValue => "私有标识符不能作为赋值左值",
        error.DuplicateImmutableBinding => "不可变绑定在同一作用域重复声明",
        error.MultiReturnInIfCondition => "if 条件位不能直接使用多返回调用",
        error.MultiReturnInIfBindRhs => "if 模式绑定右侧不能直接使用多返回调用",
        error.MultiReturnInMatchTarget => "match 目标位不能直接使用多返回调用",
        error.InvalidImportDecl => "导入声明语法无效",
        error.NoTopLevelDecl => "程序缺少顶层声明",
        error.NoTestDecl => "测试文件缺少顶层 test 声明",
        error.InvalidTestDecl => "test 声明语法无效",
        error.MissingStartEntry => "缺少入口函数 _start",
        error.InvalidStartEntrySig => "_start 函数签名无效",
        error.DuplicateStartEntry => "入口函数 _start 重复定义",
        error.MissingOutputPath => "缺少 -o 的输出路径参数",
        error.MissingTestInputPath => "缺少 test 子命令输入文件路径",
        else => "编译失败",
    };
}

fn errorHint(err: anyerror) []const u8 {
    return switch (err) {
        error.UnterminatedString => "补全字符串右侧的双引号.",
        error.InvalidIfHeader => "if 头部只允许 `Expr` 或 `TypePattern := Expr`.",
        error.InvalidMatchHeader => "match 头部固定为 `match Expr { ... }`, 不允许目标表达式后残留 token.",
        error.InvalidLoopHeader => "loop 头部支持 `loop {}`, `loop cond {}`, `loop v := iterable {}`, `loop v, i := iterable {}`.",
        error.InvalidStructLiteral => "结构体字面量必须使用 `name: value`.",
        error.InvalidTypeDeclName => "自建类型名使用 UpperCamel, 仅允许字母数字, 且首字母大写.",
        error.InvalidFuncDeclName => "函数声明名不能使用关键字或字面量保留字.",
        error.InvalidTypedLiteral => "集合字面量写法使用 `Type<...>{...}`; 空值写 `Type<...>{}`.",
        error.InvalidBraceExpr => "花括号表达式仅允许纯表达式列表或纯 `key: value` 列表, 不允许混用.",
        error.InvalidListLiteral => "List 字面量只允许表达式列表, 不允许 `k:v`.",
        error.InvalidMapLiteral => "Map 字面量只允许 `key: value` 项.",
        error.InvalidTupleLiteral => "Tuple 字面量只允许表达式列表.",
        error.InvalidCallArgList => "检查逗号分隔, 允许尾逗号但不允许空实参.",
        error.LiteralCannotBeCalled => "去掉字面量后的 `(...)`; 若要调用函数, 使用合法标识符作为被调用者.",
        error.DoneCallNeedsArg => "将 `done()` 改为 `done(future)`.",
        error.DoneCallArity => "将 `done(...)` 参数个数收敛为 1.",
        error.AsyncCtrlArity => "同名普通函数仅在实参数匹配时优先; 不匹配时回退内建规则: wait 需 1 或 2 参, cancel/status 需 1 参, wait_one/wait_any/wait_all 需 >=2 参(首参为 timeout).",
        error.InvalidIfPatternBind => "使用 `if Type(x) := expr` 或 `if Type{...} := expr`.",
        error.PrivateIdentCannotBeLValue => "将 `.x = ...` 改为普通变量或 set 接口.",
        error.DuplicateImmutableBinding => "同一作用域内 `_name` 仅允许声明 1 次.",
        error.MultiReturnInIfCondition => "先接收多返回值, 再在 if 使用单值变量.",
        error.MultiReturnInIfBindRhs => "if 模式绑定右侧改为单值表达式.",
        error.MultiReturnInMatchTarget => "先接收多返回值, 再把单值变量传给 match.",
        error.InvalidImportDecl => "使用 `{item, ...} := @(\"path\")`; 冲突名(关键字/字面量保留字)需显式重命名.",
        error.NoTopLevelDecl => "至少声明 1 个 top-level 项: import/type/func/test.",
        error.NoTestDecl => "在文件顶层添加 `test \"name\" { ... }`.",
        error.InvalidTestDecl => "使用 `test \"name\" { ... }` 顶层声明.",
        error.MissingStartEntry => "编译入口必须声明为 `_start() { ... }`.",
        error.InvalidStartEntrySig => "将入口签名改为 `_start() { ... }` (无参、无返回).",
        error.DuplicateStartEntry => "保留且仅保留 1 个顶层 `_start` 声明.",
        error.MissingOutputPath => "示例: `do input.do -o out.wat`.",
        error.MissingTestInputPath => "示例: `do test sample.do`.",
        else => "查看语法规范并修正后重试.",
    };
}
