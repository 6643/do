const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema = @import("sema.zig");
const codegen = @import("codegen.zig");

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

const TestDecl = struct {
    name_lexeme: []const u8,
    line: usize,
    col: usize,
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
            const test_decls = collectTopLevelTests(allocator, tokens) catch |err| {
                try printCompileError(cli.input_path, source, tokens, err, null);
                std.process.exit(1);
            };
            defer allocator.free(test_decls);

            if (test_decls.len == 0) {
                try printCompileError(cli.input_path, source, tokens, error.NoTestDecl, null);
                std.process.exit(1);
            }
            try printTestReport(test_decls);
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

fn printTestReport(test_decls: []const TestDecl) !void {
    var out_buffer: [4096]u8 = undefined;
    var out = std.fs.File.stdout().writer(&out_buffer);

    for (test_decls) |decl| {
        try out.interface.print("test {s} ... ok\n", .{decl.name_lexeme});
    }
    try out.interface.print("ok: {d} passed; 0 failed\n", .{test_decls.len});
    try out.interface.flush();
}

fn collectTopLevelTests(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]TestDecl {
    var out = try std.ArrayList(TestDecl).initCapacity(allocator, 0);
    defer out.deinit(allocator);

    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) {
        if (tokEqToken(tokens[i], "{")) {
            depth_brace += 1;
            i += 1;
            continue;
        }
        if (tokEqToken(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            i += 1;
            continue;
        }
        if (depth_brace != 0) {
            i += 1;
            continue;
        }

        if (tokens[i].kind != .ident or !std.mem.eql(u8, tokens[i].lexeme, "test")) {
            i += 1;
            continue;
        }
        if (i + 2 >= tokens.len) return error.InvalidTestDecl;
        if (tokens[i + 1].kind != .string) return error.InvalidTestDecl;
        if (!tokEqToken(tokens[i + 2], "{")) return error.InvalidTestDecl;

        const close_brace = try findMatchingToken(tokens, i + 2, "{", "}");
        try out.append(allocator, .{
            .name_lexeme = tokens[i + 1].lexeme,
            .line = tokens[i].line,
            .col = tokens[i].col,
        });
        i = close_brace + 1;
    }

    return out.toOwnedSlice(allocator);
}

fn findMatchingToken(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8) !usize {
    if (open_idx >= tokens.len or !tokEqToken(tokens[open_idx], open)) return error.InvalidGroupStart;

    var depth: usize = 0;
    var i = open_idx;
    while (i < tokens.len) : (i += 1) {
        if (tokEqToken(tokens[i], open)) {
            depth += 1;
            continue;
        }
        if (!tokEqToken(tokens[i], close)) continue;
        if (depth == 0) return error.InvalidGroupDepth;
        depth -= 1;
        if (depth == 0) return i;
    }
    return error.UnterminatedGroup;
}

fn tokEqToken(tok: lexer.Token, lexeme: []const u8) bool {
    return std.mem.eql(u8, tok.lexeme, lexeme);
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

        error.MultiReturnInMatchTarget => return tokenSite(findFirstToken(tokens, "match") orelse tokens[0]),
        error.InvalidTestDecl => return tokenSite(findFirstToken(tokens, "test") orelse tokens[0]),
        error.InvalidImportDecl => return tokenSite(findFirstToken(tokens, "@") orelse tokens[0]),
        error.InvalidStartEntrySig, error.DuplicateStartEntry => return tokenSite(findFirstToken(tokens, "_start") orelse tokens[0]),
        error.MissingStartEntry => return tokenSite(tokens[0]),
        error.InvalidDoExpr => return tokenSite(findFirstToken(tokens, "do") orelse tokens[0]),
        error.DoneCallNeedsArg, error.DoneCallArity => return tokenSite(findFirstToken(tokens, "done") orelse tokens[0]),
        error.AsyncCtrlArity => return tokenSite(findFirstAsyncCtrlToken(tokens) orelse tokens[0]),
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
        if (std.mem.eql(u8, tok.lexeme, "wait_timeout")) return tok;
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
        error.InvalidStructLiteral => "结构体字面量语法无效",
        error.InvalidListLiteral => "List 字面量语法无效",
        error.InvalidMapLiteral => "Map 字面量语法无效",
        error.InvalidTupleLiteral => "Tuple 字面量语法无效",
        error.InvalidCallArgList => "调用参数列表语法无效",
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
        error.InvalidStructLiteral => "结构体字面量必须使用 `name: value`.",
        error.InvalidListLiteral => "List 字面量只允许表达式列表, 不允许 `k:v`.",
        error.InvalidMapLiteral => "Map 字面量只允许 `key: value` 项.",
        error.InvalidTupleLiteral => "Tuple 字面量只允许表达式列表.",
        error.InvalidCallArgList => "检查逗号分隔, 允许尾逗号但不允许空实参.",
        error.DoneCallNeedsArg => "将 `done()` 改为 `done(future)`.",
        error.DoneCallArity => "将 `done(...)` 参数个数收敛为 1.",
        error.AsyncCtrlArity => "wait/cancel/status 需 1 参, wait_timeout 需 2 参.",
        error.InvalidIfPatternBind => "使用 `if Type(x) := expr` 或 `if Type{...} := expr`.",
        error.PrivateIdentCannotBeLValue => "将 `.x = ...` 改为普通变量或 set 接口.",
        error.DuplicateImmutableBinding => "同一作用域内 `_name` 仅允许声明 1 次.",
        error.MultiReturnInIfCondition => "先接收多返回值, 再在 if 使用单值变量.",
        error.MultiReturnInIfBindRhs => "if 模式绑定右侧改为单值表达式.",
        error.MultiReturnInMatchTarget => "先接收多返回值, 再把单值变量传给 match.",
        error.InvalidImportDecl => "使用 `{item, ...} := @(\"path\")`; 冲突名(关键字/async 控制名)需显式重命名.",
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

test "locate source error for unterminated string" {
    const src =
        \\_start() {
        \\    x = "abc
        \\}
    ;
    const loc = locateSourceError(error.UnterminatedString, src).?;
    try std.testing.expectEqual(@as(usize, 2), loc.line);
}

test "locate token error for do expr" {
    const src =
        \\_start() {
        \\    x = do
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, src);
    defer std.testing.allocator.free(tokens);

    const loc = locateTokenError(error.InvalidDoExpr, tokens).?;
    try std.testing.expectEqual(@as(usize, 2), loc.line);
}

test "collect top-level tests" {
    const src =
        \\helper() {
        \\    return
        \\}
        \\
        \\test "a" {
        \\    x = 1
        \\}
        \\
        \\test "b" {
        \\    y = 2
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, src);
    defer std.testing.allocator.free(tokens);

    const decls = try collectTopLevelTests(std.testing.allocator, tokens);
    defer std.testing.allocator.free(decls);

    try std.testing.expectEqual(@as(usize, 2), decls.len);
    try std.testing.expectEqualStrings("\"a\"", decls[0].name_lexeme);
    try std.testing.expectEqualStrings("\"b\"", decls[1].name_lexeme);
}

test "validate _start entry accepts zero-arg no-return" {
    const src =
        \\_start() {
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, src);
    defer std.testing.allocator.free(tokens);

    var program = try parser.parseProgram(std.testing.allocator, tokens, src.len);
    defer program.deinit(std.testing.allocator);

    try validateStartEntry(program);
}

test "validate _start entry rejects missing _start" {
    const src =
        \\helper() {
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, src);
    defer std.testing.allocator.free(tokens);

    var program = try parser.parseProgram(std.testing.allocator, tokens, src.len);
    defer program.deinit(std.testing.allocator);

    try std.testing.expectError(error.MissingStartEntry, validateStartEntry(program));
}

test "validate _start entry rejects invalid signature" {
    const src =
        \\_start(a i32) i32 {
        \\    return a
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, src);
    defer std.testing.allocator.free(tokens);

    var program = try parser.parseProgram(std.testing.allocator, tokens, src.len);
    defer program.deinit(std.testing.allocator);

    try std.testing.expectError(error.InvalidStartEntrySig, validateStartEntry(program));
}
