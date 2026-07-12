//! Env host import collect/parse (@env).
const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const gen_util = @import("gen_util.zig");
const gen_types = @import("gen_types.zig");

const tokEq = gen_util.tokEq;
const findMatchingInRange = gen_util.findMatchingInRange;
const findLineEnd = gen_util.findLineEnd;
const isLineStart = gen_util.isLineStart;
const findArgEnd = gen_util.findArgEnd;
const findTopLevelToken = gen_util.findTopLevelToken;
const trimParens = gen_util.trimParens;
const stringTokenBody = gen_util.stringTokenBody;
const publicDeclName = gen_util.publicDeclName;
const appendFmt = gen_util.appendFmt;

const HostImport = gen_types.HostImport;
const CodegenError = gen_types.CodegenError;
const LocalSet = gen_types.LocalSet;
const storageTypeNameForElem = gen_types.storageTypeNameForElem;
const moduleTokensEqual = gen_util.moduleTokensEqual;
const stringLiteralArgLexeme = gen_util.stringLiteralArgLexeme;
const appendMangledTypeName = gen_util.appendMangledTypeName;
const moduleScopedSymbolName = gen_util.moduleScopedSymbolName;

pub fn collectEnvHostImports(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    out: *std.ArrayList(HostImport),
) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!isLineStart(tokens, i)) continue;
        if (!isEnvHostImportStart(tokens, i)) continue;

        const line_end = findLineEnd(tokens, i);
        const import = try parseEnvHostImport(allocator, tokens, i, line_end);
        errdefer allocator.free(import.params);
        try out.append(allocator, import);
        i = line_end - 1;
    }
}
pub fn collectEnvHostImportsFromModules(
    allocator: std.mem.Allocator,
    modules: []const imports.ModuleRecord,
    entry_tokens: []const lexer.Token,
    out: *std.ArrayList(HostImport),
) !void {
    for (modules, 0..) |module, module_idx| {
        if (moduleTokensEqual(module.tokens, entry_tokens)) continue;

        var module_imports = std.ArrayList(HostImport).empty;
        defer {
            freeHostImports(allocator, module_imports.items);
            module_imports.deinit(allocator);
        }
        try collectEnvHostImports(allocator, module.tokens, &module_imports);
        for (module_imports.items) |*host_import| {
            if (findHostImportForTokens(out.items, module.tokens, host_import.source_alias) != null) continue;
            const emit_alias = try moduleScopedSymbolName(allocator, module_idx, host_import.source_alias);
            var emit_alias_owned = true;
            errdefer if (emit_alias_owned) allocator.free(emit_alias);
            host_import.alias = emit_alias;
            host_import.owned_alias = true;
            try out.append(allocator, host_import.*);
            emit_alias_owned = false;
            host_import.params = &.{};
            host_import.alias = host_import.source_alias;
            host_import.owned_alias = false;
        }
    }
}
pub fn parseEnvHostImport(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    line_end: usize,
) !HostImport {
    const alias = publicDeclName(tokens[start_idx].lexeme);
    const field = stringTokenBody(tokens[start_idx + 5].lexeme) orelse return error.InvalidImportDecl;
    const comma_idx = findTopLevelToken(tokens, start_idx + 6, line_end - 1, ",") orelse return error.InvalidImportDecl;
    const open_idx = comma_idx + 1;
    const close_idx = try findMatchingInRange(tokens, open_idx, "(", ")", line_end);
    if (close_idx + 1 >= line_end or !tokEq(tokens[close_idx + 1], "-")) return error.InvalidImportDecl;
    if (close_idx + 2 >= line_end or !tokEq(tokens[close_idx + 2], ">")) return error.InvalidImportDecl;

    var params = std.ArrayList([]const u8).empty;
    errdefer params.deinit(allocator);

    var i = open_idx + 1;
    while (i < close_idx) {
        if (tokEq(tokens[i], ",")) {
            i += 1;
            continue;
        }
        try params.append(allocator, tokens[i].lexeme);
        i += 1;
        if (i < close_idx and tokEq(tokens[i], ",")) i += 1;
    }

    const result_end = findMatchingInRange(tokens, start_idx + 4, "(", ")", line_end) catch return error.InvalidImportDecl;
    if (result_end + 1 != line_end) {
        return error.InvalidImportDecl;
    }
    const result_tok = tokens[close_idx + 3].lexeme;
    const result: ?[]const u8 = if (std.mem.eql(u8, result_tok, "nil")) null else result_tok;

    return .{
        .alias = alias,
        .source_alias = alias,
        .field = field,
        .params = try params.toOwnedSlice(allocator),
        .result = result,
        .tokens = tokens,
    };
}
pub fn freeHostImports(allocator: std.mem.Allocator, host_imports: []const HostImport) void {
    for (host_imports) |host_import| {
        if (host_import.owned_alias) allocator.free(host_import.alias);
        allocator.free(host_import.params);
    }
}
pub fn findHostImport(host_imports: []const HostImport, alias: []const u8) ?HostImport {
    for (host_imports) |host_import| {
        if (std.mem.eql(u8, host_import.alias, alias)) return host_import;
    }
    return null;
}
pub fn findHostImportForTokens(host_imports: []const HostImport, tokens: []const lexer.Token, alias: []const u8) ?HostImport {
    for (host_imports) |host_import| {
        if (!moduleTokensEqual(host_import.tokens, tokens)) continue;
        if (std.mem.eql(u8, host_import.source_alias, alias)) return host_import;
    }
    return null;
}
pub fn isEnvHostImportStart(tokens: []const lexer.Token, idx: usize) bool {
    const line_end = findLineEnd(tokens, idx);
    if (idx + 6 >= line_end) return false;
    if (tokens[idx].kind != .ident) return false;
    if (!tokEq(tokens[idx + 1], "=")) return false;
    if (!tokEq(tokens[idx + 2], "@")) return false;
    if (tokens[idx + 3].kind != .ident or !std.mem.eql(u8, tokens[idx + 3].lexeme, "env")) return false;
    if (!tokEq(tokens[idx + 4], "(")) return false;
    if (tokens[idx + 5].kind != .string) return false;
    return findTopLevelToken(tokens, idx + 6, line_end - 1, ",") != null;
}
pub fn hostCallArgsMatch(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, host_import: HostImport) bool {
    var param_idx: usize = 0;
    var arg_start = start_idx;
    while (arg_start < end_idx) {
        const arg_end = findArgEnd(tokens, arg_start, end_idx);
        if (stringLiteralArgLexeme(tokens, arg_start, arg_end)) |_| {
            if (!hostParamIsPtrLen(host_import, param_idx)) return false;
            param_idx += 2;
        } else if (hostArgCouldBeStoragePtrLenSyntax(tokens, arg_start, arg_end) and hostParamIsPtrLen(host_import, param_idx)) {
            param_idx += 2;
        } else {
            if (param_idx >= host_import.params.len) return false;
            param_idx += 1;
        }
        arg_start = arg_end;
        if (arg_start < end_idx) {
            if (!tokEq(tokens[arg_start], ",")) return false;
            arg_start += 1;
        }
    }
    return param_idx == host_import.params.len;
}
pub fn hostParamIsPtrLen(host_import: HostImport, param_idx: usize) bool {
    if (param_idx + 1 >= host_import.params.len) return false;
    return std.mem.eql(u8, host_import.params[param_idx], "i32") and
        std.mem.eql(u8, host_import.params[param_idx + 1], "i32");
}
pub fn hostArgCouldBeStoragePtrLenSyntax(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    const range = trimParens(tokens, start_idx, end_idx);
    return range.end == range.start + 1 and tokens[range.start].kind == .ident;
}
