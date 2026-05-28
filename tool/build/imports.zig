const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

const ImportRef = struct {
    alias_idx: usize,
    target: []const u8,
    path_start_idx: usize,
    path_end_idx: usize,
    prefix: ImportPrefix,
};

const ImportPrefix = enum {
    local,
    lib,
    std,
};

const DeclKind = enum {
    type,
    func,
    value,
};

const ModuleRecord = struct {
    path: []const u8,
    source: ?[]const u8,
    owns_source: bool,
    tokens: []const lexer.Token,
    owns_tokens: bool,
};

const FuncParamShape = union(enum) {
    other,
    value: ?[]const u8,
    func: FuncTypeShape,
};

const FuncTypeShape = struct {
    param_count: usize,
    param_types: []?[]const u8,
    return_type: ?[]const u8,
};

const FuncShape = struct {
    name: []const u8,
    start_idx: usize,
    param_shapes: []FuncParamShape,
    return_type: ?[]const u8,
};

const CallArgShape = union(enum) {
    other,
    ident: []const u8,
};

const CallShape = struct {
    name: []const u8,
    start_idx: usize,
    arg_shapes: []CallArgShape,
};

const Context = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    modules: std.ArrayList(ModuleRecord),
    stack: std.ArrayList([]const u8),

    fn init(io: std.Io, allocator: std.mem.Allocator) Context {
        return .{
            .io = io,
            .allocator = allocator,
            .modules = std.ArrayList(ModuleRecord).empty,
            .stack = std.ArrayList([]const u8).empty,
        };
    }

    fn deinit(self: *Context) void {
        for (self.modules.items) |module| {
            if (module.owns_source) self.allocator.free(module.source.?);
            if (module.owns_tokens) self.allocator.free(module.tokens);
            self.allocator.free(module.path);
        }
        self.modules.deinit(self.allocator);
        self.stack.deinit(self.allocator);
    }

    fn findModule(self: *const Context, path: []const u8) ?usize {
        for (self.modules.items, 0..) |module, idx| {
            if (std.mem.eql(u8, module.path, path)) return idx;
        }
        return null;
    }

    fn isLoading(self: *const Context, path: []const u8) bool {
        for (self.stack.items) |it| {
            if (std.mem.eql(u8, it, path)) return true;
        }
        return false;
    }
};

pub const ErrorSite = struct {
    line: usize,
    col: usize,
};

var last_error_site: ?ErrorSite = null;

pub fn takeLastErrorSite() ?ErrorSite {
    const out = last_error_site;
    last_error_site = null;
    return out;
}

pub fn check(
    io: std.Io,
    allocator: std.mem.Allocator,
    input_path: []const u8,
    tokens: []const lexer.Token,
) !void {
    last_error_site = null;
    var ctx = Context.init(io, allocator);
    defer ctx.deinit();
    try loadModule(&ctx, input_path, tokens, false);
}

fn parseLocalImport(tokens: []const lexer.Token, idx: usize) ?ImportRef {
    if (idx >= tokens.len or tokens[idx].kind != .ident) return null;
    if (!isTopLevelDeclHead(tokens, idx)) return null;

    const eq_idx = topLevelLineAssignIdx(tokens, idx) orelse return null;
    const line_end = findLineEndIdx(tokens, idx);
    const at_idx = eq_idx + 1;
    if (at_idx + 1 >= line_end or !tokEq(tokens[at_idx], "@")) return null;
    if (isHostImportLine(tokens, at_idx, line_end)) return null;

    var start_idx = at_idx + 1;
    var prefix: ImportPrefix = .local;
    if (start_idx < line_end and tokEq(tokens[start_idx], "~")) {
        prefix = .lib;
        start_idx += 1;
        if (start_idx >= line_end or !tokEq(tokens[start_idx], "/")) return null;
        start_idx += 1;
    } else if (start_idx < line_end and tokEq(tokens[start_idx], "/")) {
        prefix = .std;
        start_idx += 1;
    }
    if (start_idx >= line_end) return null;

    var i = start_idx;
    var file_end_idx: ?usize = null;
    while (i < line_end) {
        if (tokens[i].kind != .ident) return null;
        if (std.mem.endsWith(u8, tokens[i].lexeme, ".do")) file_end_idx = i;
        i += 1;
        if (i >= line_end or !tokEq(tokens[i], "/")) return null;
        i += 1;
        if (file_end_idx != null) break;
    }
    const file_idx = file_end_idx orelse return null;
    if (i >= line_end or tokens[i].kind != .ident) return null;
    if (i + 1 != line_end) return null;

    return .{
        .alias_idx = idx,
        .target = tokens[i].lexeme,
        .path_start_idx = start_idx,
        .path_end_idx = file_idx + 1,
        .prefix = prefix,
    };
}

fn resolvePath(
    io: std.Io,
    allocator: std.mem.Allocator,
    input_path: []const u8,
    tokens: []const lexer.Token,
    import_ref: ImportRef,
) ![]u8 {
    const rel = try importPathText(allocator, tokens, import_ref.path_start_idx, import_ref.path_end_idx);
    defer allocator.free(rel);

    switch (import_ref.prefix) {
        .local => {
            const base = std.fs.path.dirname(input_path) orelse ".";
            return std.fs.path.join(allocator, &.{ base, rel });
        },
        .lib => return std.fs.path.join(allocator, &.{ "lib", rel }),
        .std => {
            const lib_path = try std.fs.path.join(allocator, &.{ "lib", rel });
            if (fileExists(io, lib_path)) return lib_path;
            allocator.free(lib_path);
            return std.fs.path.join(allocator, &.{ "src", rel });
        },
    }
}

fn loadModule(
    ctx: *Context,
    path: []const u8,
    tokens_opt: ?[]const lexer.Token,
    owns_tokens: bool,
) !void {
    if (ctx.findModule(path) != null) return;
    if (ctx.isLoading(path)) return error.InvalidImportDecl;

    try ctx.stack.append(ctx.allocator, path);
    defer _ = ctx.stack.pop();

    var source_opt: ?[]const u8 = null;
    var tokens_opt_owned: ?[]const lexer.Token = null;
    const tokens = if (tokens_opt) |tokens| tokens else blk: {
        const source = std.Io.Dir.cwd().readFileAlloc(ctx.io, path, ctx.allocator, .limited(16 * 1024 * 1024)) catch
            return error.InvalidImportDecl;
        source_opt = source;
        const loaded_tokens = lexer.tokenize(ctx.allocator, source) catch {
            ctx.allocator.free(source);
            return error.InvalidImportDecl;
        };
        tokens_opt_owned = loaded_tokens;

        break :blk loaded_tokens;
    };
    const owned = if (tokens_opt == null) true else owns_tokens;
    if (tokens_opt == null) {
        errdefer {
            if (tokens_opt_owned) |owned_tokens| ctx.allocator.free(owned_tokens);
            if (source_opt) |src| ctx.allocator.free(src);
        }
    }

    var imported_func_shapes = std.ArrayList(FuncShape).empty;
    defer {
        freeFuncShapeItems(ctx.allocator, imported_func_shapes.items);
        imported_func_shapes.deinit(ctx.allocator);
    }

    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        const import_ref = parseLocalImport(tokens, i) orelse continue;
        const child_path = resolvePath(ctx.io, ctx.allocator, path, tokens, import_ref) catch
            return markErrorAt(tokens, import_ref.alias_idx, error.InvalidImportDecl);
        defer ctx.allocator.free(child_path);

        loadModule(ctx, child_path, null, false) catch
            return markErrorAt(tokens, import_ref.alias_idx, error.InvalidImportDecl);

        const child_idx = ctx.findModule(child_path) orelse
            return markErrorAt(tokens, import_ref.alias_idx, error.InvalidImportDecl);
        const child_tokens = ctx.modules.items[child_idx].tokens;
        const target_kind = findPublicDeclKind(child_tokens, import_ref.target) orelse
            return markErrorAt(tokens, import_ref.alias_idx, error.InvalidImportDecl);
        if (!aliasMatchesKind(tokens[import_ref.alias_idx].lexeme, target_kind)) {
            return markErrorAt(tokens, import_ref.alias_idx, error.InvalidImportDecl);
        }
        if (target_kind == .func) {
            try checkImportedFuncCalls(ctx, tokens, import_ref, child_tokens);
            try appendImportedAliasFuncShapes(
                ctx.allocator,
                &imported_func_shapes,
                tokens[import_ref.alias_idx].lexeme,
                import_ref.target,
                child_tokens,
            );
        }

        i = findLineEndIdx(tokens, i) - 1;
    }

    try checkImportedFunctionValueResolution(ctx.allocator, tokens, imported_func_shapes.items);

    const cache_path = try ctx.allocator.dupe(u8, path);
    errdefer ctx.allocator.free(cache_path);
    try ctx.modules.append(ctx.allocator, .{
        .path = cache_path,
        .source = source_opt,
        .owns_source = source_opt != null,
        .tokens = tokens,
        .owns_tokens = owned,
    });
}

fn importPathText(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokens[i].kind == .ident) {
            try out.appendSlice(allocator, tokens[i].lexeme);
            continue;
        }
        if (tokEq(tokens[i], "/")) {
            try out.append(allocator, '/');
        }
    }
    return out.toOwnedSlice(allocator);
}

fn fileExists(io: std.Io, path: []const u8) bool {
    std.Io.Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}

fn findPublicDeclKind(tokens: []const lexer.Token, target: []const u8) ?DeclKind {
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
        if (!isTopLevelDeclHead(tokens, i)) continue;
        if (tokens[i].kind != .ident) continue;
        if (findPublicUnionMember(tokens, i, target)) return .type;
        if (!std.mem.eql(u8, tokens[i].lexeme, target)) continue;
        if (isPrivateDeclName(tokens[i].lexeme)) continue;

        if (isFuncDeclStart(tokens, i)) return .func;
        if (isHostImportDeclStart(tokens, i)) return .func;
        if (isValidDeclaredTypeName(tokens[i].lexeme) and isTypeDeclStart(tokens, i)) return .type;
        if (isTopValueDeclStart(tokens, i)) return .value;
    }
    return null;
}

fn checkImportedFuncCalls(
    ctx: *Context,
    tokens: []const lexer.Token,
    import_ref: ImportRef,
    child_tokens: []const lexer.Token,
) !void {
    var program = parser.parseProgram(ctx.allocator, child_tokens, child_tokens.len) catch
        return markErrorAt(tokens, import_ref.alias_idx, error.InvalidImportDecl);
    defer program.deinit(ctx.allocator);

    const alias = tokens[import_ref.alias_idx].lexeme;
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
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, tokens[i].lexeme, alias)) continue;
        if (i + 1 >= tokens.len or !tokEq(tokens[i + 1], "(")) continue;
        if (depth_brace == 0 and isFuncDeclStart(tokens, i)) continue;

        const close_paren = findMatching(tokens, i + 1, "(", ")") catch
            return markErrorAt(tokens, i, error.InvalidCallArgList);
        const arg_count = try countCallArgs(tokens, i + 2, close_paren);
        if (!hasCompatibleFuncSig(program.func_sigs, import_ref.target, arg_count)) {
            return markErrorAt(tokens, i, error.NoMatchingCall);
        }
        i = close_paren;
    }
}

fn hasCompatibleFuncSig(func_sigs: []const parser.FuncSig, target: []const u8, arg_count: usize) bool {
    for (func_sigs) |sig| {
        if (!std.mem.eql(u8, sig.name, target)) continue;
        if (sig.param_min > arg_count) continue;
        if (sig.param_max) |max_count| {
            if (arg_count > max_count) continue;
        }
        return true;
    }
    return false;
}

fn checkImportedFunctionValueResolution(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    imported_funcs: []const FuncShape,
) !void {
    if (imported_funcs.len == 0) return;

    const local_funcs = try collectFuncShapes(allocator, tokens);
    defer freeFuncShapes(allocator, local_funcs);

    var program = parser.parseProgram(allocator, tokens, tokens.len) catch
        return markErrorAt(tokens, 0, error.InvalidImportDecl);
    defer program.deinit(allocator);

    var calls = std.ArrayList(CallShape).empty;
    defer {
        for (calls.items) |call| allocator.free(call.arg_shapes);
        calls.deinit(allocator);
    }

    try collectCallShapesFromProgram(allocator, program, tokens, &calls);
    for (calls.items) |call| {
        if (!callUsesImportedFunctionValue(local_funcs, imported_funcs, call)) continue;
        if (countCompatibleFunctionValueCandidates(local_funcs, imported_funcs, call) != 1) {
            return markErrorAt(tokens, call.start_idx, error.NoMatchingCall);
        }
    }

    try checkBareImportedOverloadedFuncAssign(tokens, local_funcs, imported_funcs);
}

fn checkBareImportedOverloadedFuncAssign(
    tokens: []const lexer.Token,
    local_funcs: []const FuncShape,
    imported_funcs: []const FuncShape,
) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tokEq(tokens[i], "=") or isNonAssignEqual(tokens, i)) continue;

        const line_start = lineStartIdx(tokens, i);
        const line_end = findLineEndIdx(tokens, i);
        const rhs_start = i + 1;
        if (rhs_start + 1 != line_end) continue;
        if (tokens[rhs_start].kind != .ident) continue;

        const rhs_name = tokens[rhs_start].lexeme;
        if (!hasKnownFuncCandidate(imported_funcs, rhs_name)) continue;
        if (countFuncsByName(local_funcs, imported_funcs, rhs_name) < 2) continue;
        if (line_start + 1 != i) continue;
        if (tokens[line_start].kind != .ident) continue;
        return markErrorAt(tokens, rhs_start, error.NoMatchingCall);
    }
}

fn appendImportedAliasFuncShapes(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(FuncShape),
    alias: []const u8,
    target: []const u8,
    child_tokens: []const lexer.Token,
) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < child_tokens.len) : (i += 1) {
        if (tokEq(child_tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(child_tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!isTopLevelDeclHead(child_tokens, i)) continue;
        if (!isFuncDeclStart(child_tokens, i)) continue;

        const decl_name = child_tokens[i].lexeme;
        if (isPrivateDeclName(decl_name)) continue;
        if (!std.mem.eql(u8, decl_name, target)) continue;

        const close_paren = findMatching(child_tokens, i + 1, "(", ")") catch continue;
        const params = try parseFuncParamShapes(allocator, child_tokens, i + 2, close_paren);
        try out.append(allocator, .{
            .name = alias,
            .start_idx = i,
            .param_shapes = params,
            .return_type = parseTopLevelFuncReturnType(child_tokens, close_paren + 1),
        });
        i = close_paren;
    }
}

fn collectFuncShapes(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]FuncShape {
    var out = std.ArrayList(FuncShape).empty;
    errdefer {
        freeFuncShapeItems(allocator, out.items);
        out.deinit(allocator);
    }

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
        if (!isTopLevelDeclHead(tokens, i) or !isFuncDeclStart(tokens, i)) continue;

        const close_paren = findMatching(tokens, i + 1, "(", ")") catch continue;
        const params = try parseFuncParamShapes(allocator, tokens, i + 2, close_paren);
        try out.append(allocator, .{
            .name = publicFuncName(tokens[i].lexeme),
            .start_idx = i,
            .param_shapes = params,
            .return_type = parseTopLevelFuncReturnType(tokens, close_paren + 1),
        });
        i = close_paren;
    }

    return out.toOwnedSlice(allocator);
}

fn freeFuncShapes(allocator: std.mem.Allocator, funcs: []const FuncShape) void {
    freeFuncShapeItems(allocator, funcs);
    allocator.free(funcs);
}

fn freeFuncShapeItems(allocator: std.mem.Allocator, funcs: []const FuncShape) void {
    for (funcs) |shape| {
        freeFuncParamShapes(allocator, shape.param_shapes);
    }
}

fn freeFuncParamShapes(allocator: std.mem.Allocator, shapes: []const FuncParamShape) void {
    for (shapes) |shape| {
        switch (shape) {
            .other => {},
            .value => {},
            .func => |func_type| allocator.free(func_type.param_types),
        }
    }
    allocator.free(shapes);
}

fn parseFuncParamShapes(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ![]FuncParamShape {
    var out = std.ArrayList(FuncParamShape).empty;
    errdefer out.deinit(allocator);

    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !isTopLevelCommaAny(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            try out.append(allocator, try parseFuncParamShape(allocator, tokens, seg_start, i));
        }
        seg_start = i + 1;
    }

    return out.toOwnedSlice(allocator);
}

fn parseFuncParamShape(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) !FuncParamShape {
    if (start_idx + 1 >= end_idx) return .other;
    const type_start = start_idx + 1;
    if (!tokEq(tokens[type_start], "(")) {
        return .{ .value = simpleTypeName(tokens, type_start, end_idx) };
    }

    const close_param_types = findMatching(tokens, type_start, "(", ")") catch return .other;
    if (close_param_types >= end_idx) return .other;
    if (!isReturnArrowAt(tokens, close_param_types + 1)) return .other;

    const param_types = try parseTypeNameList(allocator, tokens, type_start + 1, close_param_types);
    return .{ .func = .{
        .param_count = param_types.len,
        .param_types = param_types,
        .return_type = simpleTypeName(tokens, close_param_types + 3, end_idx),
    } };
}

fn parseTypeNameList(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ![]?[]const u8 {
    var out = std.ArrayList(?[]const u8).empty;
    errdefer out.deinit(allocator);

    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !isTopLevelCommaAny(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            try out.append(allocator, simpleTypeName(tokens, seg_start, i));
        }
        seg_start = i + 1;
    }
    return out.toOwnedSlice(allocator);
}

fn collectCallShapesFromProgram(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    out: *std.ArrayList(CallShape),
) !void {
    for (program.expr_nodes) |node| {
        switch (node.kind) {
            .call, .do_call => {},
            else => continue,
        }

        const call_start = if (node.kind == .do_call) node.start_tok + 1 else node.start_tok;
        if (call_start + 1 >= node.end_tok) continue;
        if (!tokEq(tokens[call_start + 1], "(")) continue;

        const args_start = call_start + 2;
        const args_end = node.end_tok - 1;
        const args = try parseCallArgShapes(allocator, tokens, args_start, args_end);
        try out.append(allocator, .{
            .name = if (node.kind == .do_call) node.data.call.func_name else tokens[call_start].lexeme,
            .start_idx = node.start_tok,
            .arg_shapes = args,
        });
    }
}

fn parseCallArgShapes(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ![]CallArgShape {
    var out = std.ArrayList(CallArgShape).empty;
    errdefer out.deinit(allocator);

    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !isTopLevelCommaAny(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            if (seg_start + 1 == i and tokens[seg_start].kind == .ident) {
                try out.append(allocator, .{ .ident = tokens[seg_start].lexeme });
            } else {
                try out.append(allocator, .other);
            }
        }
        seg_start = i + 1;
    }

    return out.toOwnedSlice(allocator);
}

fn callUsesImportedFunctionValue(
    local_funcs: []const FuncShape,
    imported_funcs: []const FuncShape,
    call: CallShape,
) bool {
    for (call.arg_shapes, 0..) |arg, arg_index| {
        if (arg != .ident) continue;
        const name = arg.ident;
        if (!hasKnownFuncCandidate(imported_funcs, name)) continue;
        if (callHasFuncParamCandidateAtIndex(local_funcs, imported_funcs, call, arg_index)) return true;
    }
    return false;
}

fn callHasFuncParamCandidateAtIndex(
    local_funcs: []const FuncShape,
    imported_funcs: []const FuncShape,
    call: CallShape,
    arg_index: usize,
) bool {
    for (local_funcs) |func| {
        if (!std.mem.eql(u8, func.name, call.name)) continue;
        if (func.param_shapes.len != call.arg_shapes.len) continue;
        if (arg_index >= func.param_shapes.len) continue;
        if (func.param_shapes[arg_index] == .func) return true;
    }
    for (imported_funcs) |func| {
        if (!std.mem.eql(u8, func.name, call.name)) continue;
        if (func.param_shapes.len != call.arg_shapes.len) continue;
        if (arg_index >= func.param_shapes.len) continue;
        if (func.param_shapes[arg_index] == .func) return true;
    }
    return false;
}

fn countCompatibleFunctionValueCandidates(
    local_funcs: []const FuncShape,
    imported_funcs: []const FuncShape,
    call: CallShape,
) usize {
    var count: usize = 0;
    for (local_funcs) |func| {
        if (!std.mem.eql(u8, func.name, call.name)) continue;
        if (func.param_shapes.len != call.arg_shapes.len) continue;
        if (!functionValueArgsMatchFunc(local_funcs, imported_funcs, func, call)) continue;
        count += 1;
    }
    for (imported_funcs) |func| {
        if (!std.mem.eql(u8, func.name, call.name)) continue;
        if (func.param_shapes.len != call.arg_shapes.len) continue;
        if (!functionValueArgsMatchFunc(local_funcs, imported_funcs, func, call)) continue;
        count += 1;
    }
    return count;
}

fn functionValueArgsMatchFunc(
    local_funcs: []const FuncShape,
    imported_funcs: []const FuncShape,
    func: FuncShape,
    call: CallShape,
) bool {
    for (call.arg_shapes, 0..) |arg, arg_index| {
        if (arg != .ident) continue;
        const name = arg.ident;
        if (!hasKnownFuncCandidate(local_funcs, name) and !hasKnownFuncCandidate(imported_funcs, name)) continue;
        if (arg_index >= func.param_shapes.len) return false;

        const target = func.param_shapes[arg_index];
        switch (target) {
            .func => |target_func| {
                if (countFuncsMatchingTarget(local_funcs, imported_funcs, name, target_func) != 1) return false;
            },
            else => continue,
        }
    }
    return true;
}

fn countFuncsMatchingTarget(
    local_funcs: []const FuncShape,
    imported_funcs: []const FuncShape,
    name: []const u8,
    target_func: FuncTypeShape,
) usize {
    var count: usize = 0;
    for (local_funcs) |func| {
        if (!std.mem.eql(u8, func.name, name)) continue;
        if (!functionMatchesTarget(func, target_func)) continue;
        count += 1;
    }
    for (imported_funcs) |func| {
        if (!std.mem.eql(u8, func.name, name)) continue;
        if (!functionMatchesTarget(func, target_func)) continue;
        count += 1;
    }
    return count;
}

fn functionMatchesTarget(func: FuncShape, target: FuncTypeShape) bool {
    if (func.param_shapes.len != target.param_count) return false;
    for (target.param_types, 0..) |target_type, idx| {
        const expected = target_type orelse continue;
        const actual = switch (func.param_shapes[idx]) {
            .value => |value_type| value_type orelse return false,
            else => return false,
        };
        if (!std.mem.eql(u8, actual, expected)) return false;
    }
    if (target.return_type) |expected_ret| {
        const actual_ret = func.return_type orelse return false;
        if (!std.mem.eql(u8, actual_ret, expected_ret)) return false;
    }
    return true;
}

fn countFuncsByName(local_funcs: []const FuncShape, imported_funcs: []const FuncShape, name: []const u8) usize {
    var count: usize = 0;
    for (local_funcs) |func| {
        if (std.mem.eql(u8, func.name, name)) count += 1;
    }
    for (imported_funcs) |func| {
        if (std.mem.eql(u8, func.name, name)) count += 1;
    }
    return count;
}

fn parseTopLevelFuncReturnType(tokens: []const lexer.Token, start_idx: usize) ?[]const u8 {
    if (start_idx >= tokens.len) return null;
    if (tokEq(tokens[start_idx], "{") or isArrowAt(tokens, start_idx)) return null;

    if (isReturnArrowAt(tokens, start_idx)) {
        return simpleTypeName(tokens, start_idx + 2, findReturnTypeEnd(tokens, start_idx + 2));
    }

    return simpleTypeName(tokens, start_idx, findReturnTypeEnd(tokens, start_idx));
}

fn findReturnTypeEnd(tokens: []const lexer.Token, start_idx: usize) usize {
    var i = start_idx;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) return i;
        if (isArrowAt(tokens, i)) return i;
        if (tokens[i].line != tokens[start_idx].line) return i;
    }
    return i;
}

fn simpleTypeName(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    if (start_idx + 1 != end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    return tokens[start_idx].lexeme;
}

fn isTopLevelCommaAny(tokens: []const lexer.Token, idx: usize, start_idx: usize, end_idx: usize) bool {
    if (!tokEq(tokens[idx], ",")) return false;

    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < idx and i < end_idx) : (i += 1) {
        if (tokEq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tokEq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (tokEq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tokEq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
    }

    return depth_paren == 0 and depth_brace == 0 and depth_angle == 0;
}

fn hasKnownFuncCandidate(funcs: []const FuncShape, name: []const u8) bool {
    for (funcs) |func| {
        if (std.mem.eql(u8, func.name, name)) return true;
    }
    return false;
}

fn lineStartIdx(tokens: []const lexer.Token, idx: usize) usize {
    var out = idx;
    while (out > 0 and tokens[out - 1].line == tokens[idx].line) : (out -= 1) {}
    return out;
}

fn publicFuncName(name: []const u8) []const u8 {
    if (name.len != 0 and name[0] == '.') return name[1..];
    return name;
}

fn isArrowAt(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 1 < tokens.len and tokEq(tokens[idx], "=") and tokEq(tokens[idx + 1], ">");
}

fn isReturnArrowAt(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 1 < tokens.len and tokEq(tokens[idx], "-") and tokEq(tokens[idx + 1], ">");
}

fn countCallArgs(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) !usize {
    if (start_idx >= end_idx) return 0;

    var count: usize = 1;
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tokEq(tokens[i], ")")) {
            if (depth_paren == 0) return error.InvalidCallArgList;
            depth_paren -= 1;
            continue;
        }
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace == 0) return error.InvalidCallArgList;
            depth_brace -= 1;
            continue;
        }
        if (tokEq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tokEq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (depth_paren != 0 or depth_brace != 0 or depth_angle != 0) continue;
        if (tokEq(tokens[i], ",")) count += 1;
    }
    if (depth_paren != 0 or depth_brace != 0 or depth_angle != 0) return error.InvalidCallArgList;
    return count;
}

fn findPublicUnionMember(tokens: []const lexer.Token, line_start_idx: usize, target: []const u8) bool {
    if (tokens[line_start_idx].lexeme.len == 0) return false;
    if (!std.mem.endsWith(u8, tokens[line_start_idx].lexeme, "Error")) return false;
    const eq_idx = topLevelLineAssignIdx(tokens, line_start_idx) orelse return false;
    const line_end = findLineEndIdx(tokens, line_start_idx);

    var i = eq_idx + 1;
    while (i < line_end) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (isPrivateDeclName(tokens[i].lexeme)) continue;
        if (std.mem.eql(u8, tokens[i].lexeme, target)) return true;
    }
    return false;
}

fn aliasMatchesKind(alias: []const u8, kind: DeclKind) bool {
    return switch (kind) {
        .type => isValidDeclaredTypeName(alias),
        .func => isLowerIdentName(alias),
        .value => isReadonlyIdentName(alias),
    };
}

fn isPrivateDeclName(name: []const u8) bool {
    return name.len != 0 and name[0] == '.';
}

fn isPrivateFuncDeclName(name: []const u8) bool {
    return name.len > 1 and name[0] == '.' and isLowerIdentName(name[1..]);
}

fn isFuncDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (isKeyword(tokens[idx].lexeme)) return false;
    if (!isLowerIdentName(tokens[idx].lexeme) and !isPrivateFuncDeclName(tokens[idx].lexeme)) return false;
    return tokEq(tokens[idx + 1], "(");
}

fn isTypeDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (tokEq(tokens[idx + 1], "(")) return false;

    var next_idx = idx + 1;
    if (tokEq(tokens[next_idx], "<")) {
        const close_angle = findMatching(tokens, next_idx, "<", ">") catch return false;
        next_idx = close_angle + 1;
        if (next_idx >= tokens.len) return false;
    }

    return tokEq(tokens[next_idx], "{") or tokEq(tokens[next_idx], "=");
}

fn isTopValueDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    const eq_idx = topLevelLineAssignIdx(tokens, idx) orelse return false;
    if (eq_idx + 1 < tokens.len and tokEq(tokens[eq_idx + 1], "@")) return false;
    return true;
}

fn isHostImportDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    const eq_idx = topLevelLineAssignIdx(tokens, idx) orelse return false;
    const line_end = findLineEndIdx(tokens, idx);
    const at_idx = eq_idx + 1;
    if (at_idx >= line_end or !tokEq(tokens[at_idx], "@")) return false;
    return isHostImportLine(tokens, at_idx, line_end);
}

fn isHostImportLine(tokens: []const lexer.Token, at_idx: usize, line_end: usize) bool {
    if (at_idx + 2 >= line_end) return false;
    if (tokens[at_idx + 1].kind != .ident or !tokEq(tokens[at_idx + 2], "/")) return false;
    if (std.mem.indexOf(u8, tokens[at_idx + 1].lexeme, ".do") != null) return false;
    return findTokenOnLine(tokens, at_idx + 3, line_end, "(") != null;
}

fn topLevelLineAssignIdx(tokens: []const lexer.Token, line_start: usize) ?usize {
    const line_end = findLineEndIdx(tokens, line_start);
    return findTopLevelAssignEqOnLine(tokens, line_start + 1, line_end);
}

fn findTopLevelAssignEqOnLine(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tokEq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (tokEq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tokEq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (depth_paren != 0 or depth_brace != 0 or depth_angle != 0) continue;
        if (tokEq(tokens[i], "=") and !isNonAssignEqual(tokens, i)) return i;
    }
    return null;
}

fn findLineEndIdx(tokens: []const lexer.Token, start_idx: usize) usize {
    if (start_idx >= tokens.len) return start_idx;
    const line = tokens[start_idx].line;
    var i = start_idx;
    while (i < tokens.len and tokens[i].line == line) : (i += 1) {}
    return i;
}

fn findTokenOnLine(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, s: []const u8) ?usize {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEq(tokens[i], s)) return i;
    }
    return null;
}

fn findMatching(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8) !usize {
    if (open_idx >= tokens.len or !tokEq(tokens[open_idx], open)) return error.InvalidGroupStart;

    var depth: usize = 0;
    var i = open_idx;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], open)) {
            depth += 1;
            continue;
        }
        if (!tokEq(tokens[i], close)) continue;
        if (depth == 0) return error.InvalidGroupDepth;
        depth -= 1;
        if (depth == 0) return i;
    }
    return error.UnterminatedGroup;
}

fn isNonAssignEqual(tokens: []const lexer.Token, idx: usize) bool {
    if (idx > 0 and tokEq(tokens[idx - 1], "=")) return true;
    if (idx + 1 < tokens.len and tokEq(tokens[idx + 1], "=")) return true;
    if (idx + 1 < tokens.len and tokEq(tokens[idx + 1], ">")) return true;
    return false;
}

fn isTopLevelDeclHead(tokens: []const lexer.Token, idx: usize) bool {
    if (idx == 0) return true;
    if (tokens[idx - 1].line == tokens[idx].line) return false;
    const prev = tokens[idx - 1];
    if (tokEq(prev, "=")) return false;
    if (tokEq(prev, "|")) return false;
    if (tokEq(prev, ",")) return false;
    if (tokEq(prev, ":")) return false;
    return true;
}

fn isValidDeclaredTypeName(name: []const u8) bool {
    if (name.len == 0) return false;
    if (name[0] == '.') return isValidDeclaredTypeName(name[1..]);
    if (!std.ascii.isUpper(name[0])) return false;

    var i: usize = 1;
    while (i < name.len) : (i += 1) {
        if (std.ascii.isAlphabetic(name[i])) continue;
        if (std.ascii.isDigit(name[i])) continue;
        return false;
    }
    return true;
}

fn isLowerIdentName(name: []const u8) bool {
    return isSnakeLowerName(name);
}

fn isReadonlyIdentName(name: []const u8) bool {
    if (name.len < 2) return false;
    if (name[0] != '_') return false;
    return isSnakeLowerName(name[1..]);
}

fn isSnakeLowerName(name: []const u8) bool {
    if (name.len == 0) return false;
    if (!std.ascii.isLower(name[0])) return false;

    var prev_underscore = false;
    for (name[1..]) |ch| {
        if (std.ascii.isLower(ch) or std.ascii.isDigit(ch)) {
            prev_underscore = false;
            continue;
        }
        if (ch == '_') {
            if (prev_underscore) return false;
            prev_underscore = true;
            continue;
        }
        return false;
    }
    return !prev_underscore;
}

fn isKeyword(name: []const u8) bool {
    const keywords = [_][]const u8{
        "if",
        "else",
        "loop",
        "break",
        "continue",
        "return",
        "defer",
        "do",
        "test",
        "true",
        "false",
        "nil",
    };
    for (keywords) |kw| {
        if (std.mem.eql(u8, name, kw)) return true;
    }
    return false;
}

fn markErrorAt(tokens: []const lexer.Token, idx: usize, err: anyerror) anyerror {
    if (idx < tokens.len) {
        last_error_site = .{ .line = tokens[idx].line, .col = tokens[idx].col };
    }
    return err;
}

fn tokEq(t: lexer.Token, s: []const u8) bool {
    return std.mem.eql(u8, t.lexeme, s);
}
