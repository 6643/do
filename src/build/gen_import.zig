//! Module import resolution, reachability, and string-data collection for codegen.
const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const gen_util = @import("gen_util.zig");
const gen_types = @import("gen_types.zig");
const gen_wasi = @import("gen_wasi.zig");
const gen_host = @import("gen_host.zig");

const tokEq = gen_util.tokEq;
const findMatching = gen_util.findMatching;
const findMatchingInRange = gen_util.findMatchingInRange;
const findLineEnd = gen_util.findLineEnd;
const findLineStart = gen_util.findLineStart;
const isLineStart = gen_util.isLineStart;
const findTopLevelToken = gen_util.findTopLevelToken;
const findArgEnd = gen_util.findArgEnd;
const trimParens = gen_util.trimParens;
const stringTokenBody = gen_util.stringTokenBody;
const publicDeclName = gen_util.publicDeclName;
const decodeQuotedStringToken = gen_util.decodeQuotedStringToken;
const appendFmt = gen_util.appendFmt;
const Range = gen_util.Range;
const moduleTokensEqual = gen_util.moduleTokensEqual;
const findToken = gen_util.findToken;
const findStartFunc = gen_util.findStartFunc;
const isUserFuncDeclStart = gen_util.isUserFuncDeclStart;
const isTypedBindingRhsCall = gen_util.isTypedBindingRhsCall;
const isBareHostCallStatement = gen_util.isBareHostCallStatement;
const stringLiteralArgLexeme = gen_util.stringLiteralArgLexeme;
const isPublicTypeName = gen_util.isPublicTypeName;
const isErrorTypeName = gen_util.isErrorTypeName;
const isBaseIntTypeName = gen_util.isBaseIntTypeName;
const isCoreWasmCallName = gen_util.isCoreWasmCallName;
const isCoreWasmScalar = gen_util.isCoreWasmScalar;

const HostImport = gen_types.HostImport;
const CodegenContext = gen_types.CodegenContext;
const CodegenImportPrefix = gen_types.CodegenImportPrefix;
const CodegenImportRef = gen_types.CodegenImportRef;
const ImportedScalarConst = gen_types.ImportedScalarConst;
const ImportedAliasContext = gen_types.ImportedAliasContext;
const ReachVisit = gen_types.ReachVisit;
const StringData = gen_types.StringData;
const StringDataContext = gen_types.StringDataContext;
const ValueEnumDecl = gen_types.ValueEnumDecl;
const PayloadEnumDecl = gen_types.PayloadEnumDecl;
const StructDecl = gen_types.StructDecl;
const ExprCallHead = gen_types.ExprCallHead;

const WASI_BINDING_ENTRY_SOURCE = gen_wasi.WASI_BINDING_ENTRY_SOURCE;
const WasiHostImport = gen_wasi.WasiHostImport;
const freeWasiHostImports = gen_wasi.freeWasiHostImports;
const collectWasiHostImports = gen_wasi.collectWasiHostImports;
const findWasiHostImport = gen_wasi.findWasiHostImport;
const findWasiHostImportBySource = gen_wasi.findWasiHostImportBySource;
const wasiHostImportUseIsLowerableAtCall = gen_wasi.wasiHostImportUseIsLowerableAtCall;
const wasiLowering = gen_wasi.wasiLowering;
const parseWasiLinkAtArgs = gen_wasi.parseWasiLinkAtArgs;

const findHostImportForTokens = gen_host.findHostImportForTokens;
const hostCallArgsMatch = gen_host.hostCallArgsMatch;
const hostParamIsPtrLen = gen_host.hostParamIsPtrLen;
const hostArgCouldBeStoragePtrLenSyntax = gen_host.hostArgCouldBeStoragePtrLenSyntax;

const test_runner = @import("test_runner.zig");

pub fn validateHostImportBuildUses(tokens: []const lexer.Token, host_imports: []const HostImport) !void {
    if (host_imports.len == 0) return;

    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        const host_import = findHostImportForTokens(host_imports, tokens, tokens[i].lexeme) orelse continue;
        if (i + 1 >= tokens.len or !tokEq(tokens[i + 1], "(")) continue;

        const close_paren = findMatching(tokens, i + 1, "(", ")") catch return error.InvalidCallArgList;
        if (!hostCallArgsMatch(tokens, i + 2, close_paren, host_import)) return error.NoMatchingCall;
        if (isBareHostCallStatement(tokens, i, close_paren) and host_import.result != null) return error.NoMatchingCall;
        if (isTypedBindingRhsCall(tokens, i) and host_import.result == null) return error.NoMatchingCall;
        i = close_paren;
    }
}

pub fn validateReachableWasiHostImportBuildUses(
    allocator: std.mem.Allocator,
    entry_tokens: []const lexer.Token,
    graph: *const imports.ModuleGraph,
) !void {
    const root_idx = findRootModuleIndex(graph.modules, entry_tokens) orelse return;

    var stack = std.ArrayList(ReachVisit).empty;
    defer stack.deinit(allocator);

    var visited = std.ArrayList(ReachVisit).empty;
    defer visited.deinit(allocator);

    try collectStartBodyCalls(allocator, graph.modules[root_idx].tokens, root_idx, &stack);
    try collectAllFunctionBodyCalls(allocator, graph.modules[root_idx].tokens, root_idx, &stack);
    try validateReachableWasiHostImportStack(allocator, graph, &stack, &visited);
}

pub fn validateReachableWasiHostImportBuildUsesFromTests(
    allocator: std.mem.Allocator,
    entry_tokens: []const lexer.Token,
    graph: *const imports.ModuleGraph,
) !void {
    const root_idx = findRootModuleIndex(graph.modules, entry_tokens) orelse return;

    var stack = std.ArrayList(ReachVisit).empty;
    defer stack.deinit(allocator);

    var visited = std.ArrayList(ReachVisit).empty;
    defer visited.deinit(allocator);

    try collectTestBodyCalls(allocator, graph.modules[root_idx].tokens, root_idx, &stack);
    try collectAllFunctionBodyCalls(allocator, graph.modules[root_idx].tokens, root_idx, &stack);
    try validateReachableWasiHostImportStack(allocator, graph, &stack, &visited);
}

pub fn validateReachableWasiHostImportStack(
    allocator: std.mem.Allocator,
    graph: *const imports.ModuleGraph,
    stack: *std.ArrayList(ReachVisit),
    visited: *std.ArrayList(ReachVisit),
) !void {
    while (stack.items.len != 0) {
        const visit = stack.pop().?;
        if (hasReachVisit(visited.items, visit)) continue;
        try visited.append(allocator, visit);

        const module = graph.modules[visit.module_idx];
        var module_wasi_imports = std.ArrayList(WasiHostImport).empty;
        defer {
            freeWasiHostImports(allocator, module_wasi_imports.items);
            module_wasi_imports.deinit(allocator);
        }
        try collectWasiHostImports(allocator, module.tokens, module.path, &module_wasi_imports);
        if (findWasiHostImport(module_wasi_imports.items, visit.name)) |import| {
            if (visit.call_idx) |call_idx| {
                if (wasiHostImportUseIsLowerableAtCall(module.tokens, call_idx, import)) continue;
            }
            return error.UnsupportedWasiHostImport;
        }

        if (findCodegenImportByAlias(module.tokens, visit.name)) |import_ref| {
            if (findImportedModuleIndex(allocator, graph, visit.module_idx, import_ref)) |child_idx| {
                try pushReachVisit(allocator, stack, .{
                    .module_idx = child_idx,
                    .name = import_ref.target,
                });
            }
            continue;
        }

        try collectFunctionBodyCalls(allocator, module.tokens, visit.module_idx, visit.name, stack);
    }
}

pub fn findRootModuleIndex(modules: []const imports.ModuleRecord, entry_tokens: []const lexer.Token) ?usize {
    for (modules, 0..) |module, idx| {
        if (moduleTokensEqual(module.tokens, entry_tokens)) return idx;
    }
    return null;
}

pub fn wasiSourceForTokens(ctx: CodegenContext, tokens: []const lexer.Token) []const u8 {
    if (moduleTokensEqual(tokens, ctx.entry_tokens)) return WASI_BINDING_ENTRY_SOURCE;
    for (ctx.modules) |module| {
        if (moduleTokensEqual(tokens, module.tokens)) return module.path;
    }
    return WASI_BINDING_ENTRY_SOURCE;
}

pub fn findWasiHostImportForTokens(ctx: CodegenContext, tokens: []const lexer.Token, alias: []const u8) ?WasiHostImport {
    const source = wasiSourceForTokens(ctx, tokens);
    return findWasiHostImportBySource(ctx.wasi_imports, source, alias);
}

pub fn hasReachVisit(items: []const ReachVisit, target: ReachVisit) bool {
    for (items) |item| {
        if (item.module_idx == target.module_idx and std.mem.eql(u8, item.name, target.name)) return true;
    }
    return false;
}

pub fn pushReachVisit(
    allocator: std.mem.Allocator,
    stack: *std.ArrayList(ReachVisit),
    visit: ReachVisit,
) !void {
    if (isCoreWasmCallName(visit.name)) return;
    try stack.append(allocator, visit);
}

pub fn collectStartBodyCalls(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    module_idx: usize,
    out: *std.ArrayList(ReachVisit),
) !void {
    const start_idx = findStartFunc(tokens) orelse return;
    const close_params = findMatching(tokens, start_idx + 1, "(", ")") catch return;
    const open_body = findToken(tokens, close_params + 1, tokens.len, "{") orelse return;
    const close_body = findMatching(tokens, open_body, "{", "}") catch return;
    try collectCallNamesInRange(allocator, tokens, module_idx, open_body + 1, close_body, out);
}

pub fn collectAllFunctionBodyCalls(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    module_idx: usize,
    out: *std.ArrayList(ReachVisit),
) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!isUserFuncDeclStart(tokens, i)) continue;

        const close_params = findMatching(tokens, i + 1, "(", ")") catch continue;
        const open_body = findToken(tokens, close_params + 1, tokens.len, "{") orelse continue;
        const close_body = findMatching(tokens, open_body, "{", "}") catch continue;
        try collectCallNamesInRange(allocator, tokens, module_idx, open_body + 1, close_body, out);
        i = close_body;
    }
}

pub fn collectTestBodyCalls(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    module_idx: usize,
    out: *std.ArrayList(ReachVisit),
) !void {
    const test_decls = try test_runner.collectTopLevelTests(allocator, tokens);
    defer allocator.free(test_decls);

    for (test_decls) |decl| {
        try collectCallNamesInRange(allocator, tokens, module_idx, decl.body_start, decl.body_end, out);
    }
}

pub fn collectFunctionBodyCalls(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    module_idx: usize,
    func_name: []const u8,
    out: *std.ArrayList(ReachVisit),
) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, publicDeclName(tokens[i].lexeme), func_name)) continue;
        if (!tokEq(tokens[i + 1], "(")) continue;

        const close_params = findMatching(tokens, i + 1, "(", ")") catch continue;
        const open_body = findToken(tokens, close_params + 1, tokens.len, "{") orelse continue;
        const close_body = findMatching(tokens, open_body, "{", "}") catch continue;
        try collectCallNamesInRange(allocator, tokens, module_idx, open_body + 1, close_body, out);
        i = close_body;
    }
}

pub fn collectCallNamesInRange(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    module_idx: usize,
    start_idx: usize,
    end_idx: usize,
    out: *std.ArrayList(ReachVisit),
) !void {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        const call_head = callHeadAt(tokens, i, end_idx) orelse continue;
        try collectCallNamesInRange(allocator, tokens, module_idx, call_head.args_start, call_head.args_end, out);
        if (!call_head.is_intrinsic and !isLoopSourceSpecialCallName(tokens[call_head.name_idx].lexeme)) {
            try pushReachVisit(allocator, out, .{
                .module_idx = module_idx,
                .name = tokens[call_head.name_idx].lexeme,
                .call_idx = call_head.name_idx,
            });
        }
        i = call_head.args_end;
    }
}

pub fn isLoopSourceSpecialCallName(name: []const u8) bool {
    return std.mem.eql(u8, name, "fields") or std.mem.eql(u8, name, "recv");
}

pub fn findCodegenImportByAlias(tokens: []const lexer.Token, alias: []const u8) ?CodegenImportRef {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        const import_ref = parseCodegenImport(tokens, i) orelse continue;
        if (std.mem.eql(u8, import_ref.alias, alias)) return import_ref;
        i = findLineEnd(tokens, i) - 1;
    }
    return null;
}

pub fn parseCodegenImport(tokens: []const lexer.Token, idx: usize) ?CodegenImportRef {
    const line_end = findLineEnd(tokens, idx);
    if (idx + 8 >= line_end) return null;
    if (tokens[idx].kind != .ident) return null;
    if (!tokEq(tokens[idx + 1], "=")) return null;
    if (!tokEq(tokens[idx + 2], "@")) return null;
    if (tokens[idx + 3].kind != .ident or !std.mem.eql(u8, tokens[idx + 3].lexeme, "lib")) return null;
    if (!tokEq(tokens[idx + 4], "(")) return null;
    if (tokens[idx + 5].kind != .string) return null;
    if (!tokEq(tokens[idx + 6], ",")) return null;
    if (tokens[idx + 7].kind != .ident) return null;
    if (!tokEq(tokens[idx + 8], ")")) return null;
    if (idx + 9 != line_end) return null;

    var file_path = stringTokenBody(tokens[idx + 5].lexeme) orelse return null;
    var prefix: CodegenImportPrefix = .std;
    if (std.mem.startsWith(u8, file_path, "./")) {
        prefix = .local;
        file_path = file_path[2..];
    } else if (std.mem.startsWith(u8, file_path, "~/")) {
        prefix = .dep;
        file_path = file_path[2..];
    } else if (std.mem.startsWith(u8, file_path, "/")) {
        return null;
    }

    return .{
        .alias = tokens[idx].lexeme,
        .target = tokens[idx + 7].lexeme,
        .file_path = file_path,
        .prefix = prefix,
    };
}

pub fn importedScalarConst(ctx: CodegenContext, tokens: []const lexer.Token, alias: []const u8) ?ImportedScalarConst {
    const import_ctx = importedAliasContextForTokens(ctx.imported_alias_ctx, tokens) orelse return null;
    const import_ref = findCodegenImportByAlias(tokens, alias) orelse return null;
    const child_idx = findImportedModuleIndexNoAlloc(import_ctx.graph, import_ctx.module_idx, import_ref) orelse return null;
    return localScalarConst(import_ctx.graph.modules[child_idx].tokens, import_ref.target);
}

pub fn findImportedModuleIndexNoAlloc(
    graph: *const imports.ModuleGraph,
    current_idx: usize,
    import_ref: CodegenImportRef,
) ?usize {
    for (graph.modules, 0..) |module, idx| {
        if (moduleMatchesImportPath(graph, current_idx, module.path, import_ref)) return idx;
    }
    return null;
}

pub fn moduleMatchesImportPath(
    graph: *const imports.ModuleGraph,
    current_idx: usize,
    path: []const u8,
    import_ref: CodegenImportRef,
) bool {
    return switch (import_ref.prefix) {
        .std => pathHasBaseAndFile(path, "lib", import_ref.file_path),
        .dep => pathHasBaseAndFile(path, graph.dep_root, import_ref.file_path),
        .local => pathHasBaseAndFile(path, std.fs.path.dirname(graph.modules[current_idx].path) orelse ".", import_ref.file_path),
    };
}

pub fn pathHasBaseAndFile(path: []const u8, base: []const u8, file_path: []const u8) bool {
    if (std.mem.eql(u8, base, ".")) return std.mem.eql(u8, path, file_path) or pathHasBaseAndFile(path, "", file_path);
    if (base.len == 0) return std.mem.eql(u8, path, file_path);
    if (!std.mem.startsWith(u8, path, base)) return false;
    if (path.len != base.len + 1 + file_path.len) return false;
    if (path[base.len] != '/') return false;
    return std.mem.eql(u8, path[base.len + 1 ..], file_path);
}

pub fn localScalarConst(tokens: []const lexer.Token, name: []const u8) ?ImportedScalarConst {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i + 4 < tokens.len) : (i += 1) {
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
        if (tokens[i].kind != .ident or !std.mem.eql(u8, tokens[i].lexeme, name)) continue;
        if (tokens[i + 1].kind != .ident or !isCoreWasmScalar(tokens[i + 1].lexeme)) return null;
        if (!tokEq(tokens[i + 2], "=")) return null;
        const line_end = findLineEnd(tokens, i);
        if (i + 4 != line_end) return null;
        const value = tokens[i + 3];
        if (value.kind != .number) return null;
        return .{ .ty = tokens[i + 1].lexeme, .value = value.lexeme };
    }
    return null;
}

pub fn findImportedModuleIndex(
    allocator: std.mem.Allocator,
    graph: *const imports.ModuleGraph,
    current_idx: usize,
    import_ref: CodegenImportRef,
) ?usize {
    const modules = graph.modules;
    switch (import_ref.prefix) {
        .local => {
            const base = std.fs.path.dirname(modules[current_idx].path) orelse ".";
            const resolved = std.fs.path.join(allocator, &.{ base, import_ref.file_path }) catch return null;
            defer allocator.free(resolved);
            return findModuleByPath(modules, resolved);
        },
        .std => {
            const resolved = std.fs.path.join(allocator, &.{ "lib", import_ref.file_path }) catch return null;
            defer allocator.free(resolved);
            return findModuleByPath(modules, resolved);
        },
        .dep => {
            const resolved = std.fs.path.join(allocator, &.{ graph.dep_root, import_ref.file_path }) catch return null;
            defer allocator.free(resolved);
            return findModuleByPath(modules, resolved);
        },
    }
}

pub fn findModuleByPath(modules: []const imports.ModuleRecord, path: []const u8) ?usize {
    for (modules, 0..) |module, idx| {
        if (std.mem.eql(u8, module.path, path)) return idx;
    }
    return null;
}

pub fn isValueEnumDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 2 < tokens.len and
        isLineStart(tokens, idx) and
        tokens[idx].kind == .ident and
        isPublicTypeName(publicDeclName(tokens[idx].lexeme)) and
        !isErrorTypeName(publicDeclName(tokens[idx].lexeme)) and
        isBaseIntTypeName(tokens[idx + 1].lexeme) and
        tokEq(tokens[idx + 2], "=");
}

/// `Message = Quit | Text([u8])` — mirrors sema `isPayloadEnumDeclStart` (codegen copy).
/// `Message = Quit | Text([u8])` — mirrors sema `isPayloadEnumDeclStart` (codegen copy).

pub fn isPayloadEnumDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 2 >= tokens.len) return false;
    if (!isLineStart(tokens, idx)) return false;
    if (tokens[idx].kind != .ident) return false;
    if (!isPublicTypeName(publicDeclName(tokens[idx].lexeme))) return false;
    if (isErrorTypeName(publicDeclName(tokens[idx].lexeme))) return false;
    if (isValueEnumDeclStart(tokens, idx)) return false;
    if (idx + 2 < tokens.len and tokEq(tokens[idx + 1], "error") and tokEq(tokens[idx + 2], "=")) return false;
    if (!tokEq(tokens[idx + 1], "=")) return false;
    if (tokEq(tokens[idx + 2], "@")) return false;

    const line_end = findLineEnd(tokens, idx);
    var j = idx + 2;
    var saw_case = false;
    var expect_case = true;
    while (j < line_end) {
        if (!expect_case) {
            if (!tokEq(tokens[j], "|")) return false;
            expect_case = true;
            j += 1;
            continue;
        }
        if (tokens[j].kind != .ident) return false;
        if (!isPublicTypeName(publicDeclName(tokens[j].lexeme))) return false;
        j += 1;
        if (j < line_end and tokEq(tokens[j], "(")) {
            const close = findMatching(tokens, j, "(", ")") catch return false;
            if (close <= j + 1) return false;
            if (close == j + 2 and tokens[j + 1].kind == .number) return false;
            if (tokens[j + 1].kind == .number or tokens[j + 1].kind == .string) return false;
            j = close + 1;
        }
        saw_case = true;
        expect_case = false;
    }
    return saw_case and !expect_case;
}

pub fn findValueEnumDecl(value_enums: []const ValueEnumDecl, name: []const u8) ?ValueEnumDecl {
    for (value_enums) |decl| {
        if (std.mem.eql(u8, decl.name, name)) return decl;
    }
    return null;
}

pub fn findPayloadEnumDecl(payload_enums: []const PayloadEnumDecl, name: []const u8) ?PayloadEnumDecl {
    for (payload_enums) |decl| {
        if (std.mem.eql(u8, decl.name, name)) return decl;
    }
    return null;
}

pub fn findValueEnumDeclLineByName(tokens: []const lexer.Token, name: []const u8) ?usize {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i + 2 < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!isValueEnumDeclStart(tokens, i)) continue;
        if (std.mem.eql(u8, publicDeclName(tokens[i].lexeme), name)) return i;
        i = findLineEnd(tokens, i) - 1;
    }
    return null;
}

pub fn findValueEnumDeclLineByBranch(tokens: []const lexer.Token, branch_name: []const u8) ?usize {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i + 2 < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!isValueEnumDeclStart(tokens, i)) continue;
        if (valueEnumLineHasBranch(tokens, i, branch_name)) return i;
        i = findLineEnd(tokens, i) - 1;
    }
    return null;
}

pub fn valueEnumLineHasBranch(tokens: []const lexer.Token, enum_idx: usize, branch_name: []const u8) bool {
    const line_end = findLineEnd(tokens, enum_idx);
    var j = enum_idx + 3;
    while (j + 3 < line_end) {
        if (tokEq(tokens[j], "|")) {
            j += 1;
            continue;
        }
        if (tokens[j].kind == .ident and std.mem.eql(u8, publicDeclName(tokens[j].lexeme), branch_name)) return true;
        j += 4;
    }
    return false;
}

pub fn collectStringDataForHostCalls(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    host_imports: []const HostImport,
    out: *StringDataContext,
) !void {
    if (host_imports.len == 0) return;

    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        const host_import = findHostImportForTokens(host_imports, tokens, tokens[i].lexeme) orelse continue;
        if (!tokEq(tokens[i + 1], "(")) continue;

        const close_paren = findMatching(tokens, i + 1, "(", ")") catch return error.InvalidCallArgList;
        var arg_start = i + 2;
        var param_idx: usize = 0;
        while (arg_start < close_paren) {
            const arg_end = findArgEnd(tokens, arg_start, close_paren);
            if (stringLiteralArgLexeme(tokens, arg_start, arg_end)) |lexeme| {
                if (!hostParamIsPtrLen(host_import, param_idx)) return error.NoMatchingCall;
                _ = try out.intern(allocator, lexeme);
                param_idx += 2;
            } else if (hostArgCouldBeStoragePtrLenSyntax(tokens, arg_start, arg_end) and hostParamIsPtrLen(host_import, param_idx)) {
                param_idx += 2;
            } else {
                param_idx += 1;
            }
            arg_start = arg_end;
            if (arg_start < close_paren and tokEq(tokens[arg_start], ",")) arg_start += 1;
        }
        i = close_paren;
    }
}

pub fn collectStringDataForWasiHostCalls(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    source: []const u8,
    wasi_imports: []const WasiHostImport,
    out: *StringDataContext,
) !void {
    if (wasi_imports.len == 0) return;

    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        const import = findWasiHostImportBySource(wasi_imports, source, tokens[i].lexeme) orelse continue;
        const lowering = wasiLowering(import) orelse continue;
        if (!lowering.result_link_at_error) continue;
        if (!tokEq(tokens[i + 1], "(")) continue;

        const close_paren = findMatching(tokens, i + 1, "(", ")") catch return error.InvalidCallArgList;
        const args = parseWasiLinkAtArgs(tokens, i + 2, close_paren) orelse return error.NoMatchingCall;
        if (stringLiteralArgLexeme(tokens, args.old_path_start, args.old_path_end)) |old_path| {
            _ = try out.intern(allocator, old_path);
        } else if (!hostArgCouldBeStoragePtrLenSyntax(tokens, args.old_path_start, args.old_path_end)) {
            return error.NoMatchingCall;
        }
        if (stringLiteralArgLexeme(tokens, args.new_path_start, args.new_path_end)) |new_path| {
            _ = try out.intern(allocator, new_path);
        } else if (!hostArgCouldBeStoragePtrLenSyntax(tokens, args.new_path_start, args.new_path_end)) {
            return error.NoMatchingCall;
        }
        i = close_paren;
    }
}

pub fn collectStringDataForStorageLiterals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    out: *StringDataContext,
) !void {
    var storage_names = std.ArrayList([]const u8).empty;
    defer storage_names.deinit(allocator);

    var i: usize = 0;
    while (i + 3 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        const eq_idx: usize = if (i + 5 < tokens.len and
            tokEq(tokens[i + 1], "[") and
            tokEq(tokens[i + 2], "u8") and
            tokEq(tokens[i + 3], "]") and
            tokEq(tokens[i + 4], "="))
            i + 4
        else if (tokEq(tokens[i + 1], "text") and tokEq(tokens[i + 2], "="))
            i + 2
        else
            continue;
        try storage_names.append(allocator, tokens[i].lexeme);
        if (eq_idx + 1 < tokens.len and tokens[eq_idx + 1].kind == .string) {
            _ = try out.intern(allocator, tokens[eq_idx + 1].lexeme);
        }
    }

    i = 0;
    while (i + 2 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (!hasBorrowedName(storage_names.items, tokens[i].lexeme)) continue;
        if (!tokEq(tokens[i + 1], "=")) continue;
        if (tokens[i + 2].kind != .string) continue;
        _ = try out.intern(allocator, tokens[i + 2].lexeme);
    }

    i = 0;
    var depth_brace: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace == 0) continue;
        if (tokens[i].kind != .string) continue;
        if (tokens[i].lexeme.len < 2 or tokens[i].lexeme[0] != '"') continue;
        _ = try out.intern(allocator, tokens[i].lexeme);
    }
}

pub fn collectStringDataForStructFieldNames(
    allocator: std.mem.Allocator,
    structs: []const StructDecl,
    out: *StringDataContext,
) !void {
    for (structs) |decl| {
        for (decl.fields) |field| {
            const field_name = publicDeclName(field.name);
            _ = try out.internRaw(allocator, field_name, field_name);
        }
    }
}

pub fn hasBorrowedName(names: []const []const u8, name: []const u8) bool {
    for (names) |candidate| {
        if (std.mem.eql(u8, candidate, name)) return true;
    }
    return false;
}

pub fn importedAliasContextForTokens(imported_alias_ctx: ?ImportedAliasContext, tokens: []const lexer.Token) ?ImportedAliasContext {
    const ctx = imported_alias_ctx orelse return null;
    const module_idx = findRootModuleIndex(ctx.graph.modules, tokens) orelse ctx.module_idx;
    return .{ .graph = ctx.graph, .module_idx = module_idx };
}

pub fn callHeadAt(tokens: []const lexer.Token, idx: usize, limit: usize) ?ExprCallHead {
    if (idx >= limit) return null;

    var name_idx = idx;
    var is_intrinsic = false;
    if (tokEq(tokens[name_idx], "@")) {
        name_idx += 1;
        if (name_idx >= limit) return null;
        is_intrinsic = true;
    } else if (idx > 0 and tokEq(tokens[idx - 1], "@") and tokens[idx - 1].line == tokens[idx].line) {
        return null;
    }

    if (tokens[name_idx].kind != .ident) return null;
    if (name_idx + 1 >= limit) return null;

    var open_paren = name_idx + 1;
    var type_args_start: usize = 0;
    var type_args_end: usize = 0;
    if (tokEq(tokens[open_paren], "<")) {
        if (is_intrinsic) return null;
        const close_angle = findMatchingInRange(tokens, open_paren, "<", ">", limit) catch return null;
        if (close_angle + 1 >= limit or !tokEq(tokens[close_angle + 1], "(")) return null;
        type_args_start = open_paren + 1;
        type_args_end = close_angle;
        open_paren = close_angle + 1;
    } else if (!tokEq(tokens[open_paren], "(")) {
        return null;
    }

    const close_paren = findMatchingInRange(tokens, open_paren, "(", ")", limit) catch return null;
    if (is_intrinsic and !isCoreWasmCallName(tokens[name_idx].lexeme)) return null;
    return .{
        .name_idx = name_idx,
        .type_args_start = type_args_start,
        .type_args_end = type_args_end,
        .args_start = open_paren + 1,
        .args_end = close_paren,
        .is_intrinsic = is_intrinsic,
    };
}

pub fn exprCallHead(tokens: []const lexer.Token, range: Range) ?ExprCallHead {
    var name_idx = range.start;
    var is_intrinsic = false;
    if (tokEq(tokens[name_idx], "@")) {
        if (name_idx + 1 >= range.end) return null;
        name_idx += 1;
        is_intrinsic = true;
    }
    if (tokens[name_idx].kind != .ident) return null;
    if (name_idx + 1 >= range.end) return null;
    var open_paren = name_idx + 1;
    var type_args_start: usize = 0;
    var type_args_end: usize = 0;
    if (tokEq(tokens[open_paren], "<")) {
        if (is_intrinsic) return null;
        const close_angle = findMatchingInRange(tokens, open_paren, "<", ">", range.end) catch return null;
        if (close_angle + 1 >= range.end or !tokEq(tokens[close_angle + 1], "(")) return null;
        type_args_start = open_paren + 1;
        type_args_end = close_angle;
        open_paren = close_angle + 1;
    } else if (!tokEq(tokens[open_paren], "(")) {
        return null;
    }

    const close_paren = findMatchingInRange(tokens, open_paren, "(", ")", range.end) catch return null;
    if (close_paren + 1 != range.end) return null;
    if (is_intrinsic and !isCoreWasmCallName(tokens[name_idx].lexeme)) return null;
    return .{
        .name_idx = name_idx,
        .type_args_start = type_args_start,
        .type_args_end = type_args_end,
        .args_start = open_paren + 1,
        .args_end = close_paren,
        .is_intrinsic = is_intrinsic,
    };
}

pub fn callHeadHasTypeArgs(call_head: ExprCallHead) bool {
    return call_head.type_args_start != 0 or call_head.type_args_end != 0;
}

