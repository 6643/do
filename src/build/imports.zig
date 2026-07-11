const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema = @import("sema.zig");

const ImportRef = struct {
    alias_idx: usize,
    target: []const u8,
    file_path: []const u8,
    prefix: ImportPrefix,
};

const ImportPrefix = enum {
    local,
    dep,
    std,
};

const PrivateField = struct {
    name: []const u8,
    has_default: bool,
};

const DeclKind = enum {
    type,
    error_type,
    value_enum_type,
    error_branch,
    value_enum_branch,
    func,
    const_value,
    var_value,
};

pub const ModuleRecord = struct {
    path: []const u8,
    source: ?[]const u8,
    owns_source: bool,
    tokens: []const lexer.Token,
    owns_tokens: bool,
};

const FuncParamShape = union(enum) {
    other,
    value: ?[]const u8,
    variadic: ?[]const u8,
    func: FuncTypeShape,
};

const FuncTypeShape = struct {
    param_count: usize,
    param_types: []?[]const u8,
    return_type: ?[]const u8,
};

const ResolvedFuncTypeShape = struct {
    shape: FuncTypeShape,
    owned: bool,
};

const FuncShape = struct {
    name: []const u8,
    start_idx: usize,
    param_shapes: []FuncParamShape,
    param_min: usize,
    param_max: ?usize,
    return_type: ?[]const u8,
    return_arity: usize,
    is_generic: bool = false,
};

const CallArgShape = union(enum) {
    other,
    ident: []const u8,
    spread: usize,
};

const CallShape = struct {
    name: []const u8,
    start_idx: usize,
    arg_shapes: []CallArgShape,
};

const ImportCallArgs = struct {
    shapes: []CallArgShape,
    spread_idx: ?usize,
};

const ReturnArityResolve = union(enum) {
    unknown,
    arity: usize,
    ambiguous,
};

const Context = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    dep_root: []const u8,
    modules: std.ArrayList(ModuleRecord),
    stack: std.ArrayList([]const u8),

    fn init(io: std.Io, allocator: std.mem.Allocator, dep_root: []const u8) Context {
        return .{
            .io = io,
            .allocator = allocator,
            .dep_root = dep_root,
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

    fn intoGraph(self: *Context) !ModuleGraph {
        const modules = try self.modules.toOwnedSlice(self.allocator);
        self.stack.deinit(self.allocator);
        return .{
            .allocator = self.allocator,
            .dep_root = self.dep_root,
            .modules = modules,
        };
    }
};

pub const ModuleGraph = struct {
    allocator: std.mem.Allocator,
    dep_root: []const u8,
    modules: []ModuleRecord,

    pub fn deinit(self: *ModuleGraph) void {
        for (self.modules) |module| {
            if (module.owns_source) self.allocator.free(module.source.?);
            if (module.owns_tokens) self.allocator.free(module.tokens);
            self.allocator.free(module.path);
        }
        self.allocator.free(self.modules);
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
    dep_root: []const u8,
) !void {
    var graph = try checkAndLoad(io, allocator, input_path, tokens, dep_root);
    defer graph.deinit();
}

pub fn checkAndLoad(
    io: std.Io,
    allocator: std.mem.Allocator,
    input_path: []const u8,
    tokens: []const lexer.Token,
    dep_root: []const u8,
) !ModuleGraph {
    last_error_site = null;
    var ctx = Context.init(io, allocator, dep_root);
    errdefer ctx.deinit();
    try loadModule(&ctx, input_path, tokens, false);
    return try ctx.intoGraph();
}

fn parseLocalImport(tokens: []const lexer.Token, idx: usize) ?ImportRef {
    if (idx >= tokens.len or tokens[idx].kind != .ident) return null;
    if (!isTopLevelDeclHead(tokens, idx)) return null;

    const eq_idx = topLevelLineAssignIdx(tokens, idx) orelse return null;
    const line_end = findLineEndIdx(tokens, idx);
    const at_idx = eq_idx + 1;
    const close_import = parseLibImportClose(tokens, at_idx, line_end) orelse return null;

    var file_path = stringTokenBody(tokens[at_idx + 3].lexeme) orelse return null;
    const target = tokens[at_idx + 5].lexeme;
    var prefix: ImportPrefix = .std;
    if (std.mem.startsWith(u8, file_path, "./")) {
        prefix = .local;
        file_path = file_path[2..];
    } else if (std.mem.startsWith(u8, file_path, "~/")) {
        prefix = .dep;
        file_path = file_path[2..];
    } else if (std.mem.startsWith(u8, file_path, "/")) {
        return null;
    }

    if (!isValidImportFileName(file_path, prefix)) return null;
    if (!isValidImportName(target)) return null;
    if (close_import + 1 != line_end) return null;

    return .{
        .alias_idx = idx,
        .target = target,
        .file_path = file_path,
        .prefix = prefix,
    };
}

fn resolvePath(
    allocator: std.mem.Allocator,
    input_path: []const u8,
    import_ref: ImportRef,
    dep_root: []const u8,
) ![]u8 {
    switch (import_ref.prefix) {
        .local => {
            const base = std.fs.path.dirname(input_path) orelse ".";
            return std.fs.path.join(allocator, &.{ base, import_ref.file_path });
        },
        .dep => return std.fs.path.join(allocator, &.{ dep_root, import_ref.file_path }),
        .std => return std.fs.path.join(allocator, &.{ "lib", import_ref.file_path }),
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
    if (source_opt) |source| {
        var program = parser.parseProgram(ctx.allocator, tokens, source.len) catch return error.InvalidImportDecl;
        defer program.deinit(ctx.allocator);
        sema.checkProgram(ctx.allocator, program, tokens) catch return error.InvalidImportDecl;
    }

    var imported_func_shapes = std.ArrayList(FuncShape).empty;
    defer {
        freeFuncShapeItems(ctx.allocator, imported_func_shapes.items);
        imported_func_shapes.deinit(ctx.allocator);
    }
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        const import_ref = parseLocalImport(tokens, i) orelse {
            if (isNonHostImportAssign(tokens, i)) {
                return markErrorAt(tokens, i, error.InvalidImportDecl);
            }
            continue;
        };
        const child_path = resolvePath(ctx.allocator, path, import_ref, ctx.dep_root) catch
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
        if (isTypeLikeKind(target_kind) and hasTypeNameConflict(tokens, import_ref.alias_idx)) {
            return markErrorAt(tokens, import_ref.alias_idx, error.DuplicateTypeDeclName);
        }
        if (isTypeLikeKind(target_kind)) {
            try checkImportedPrivateFieldCtors(ctx, tokens, import_ref, child_tokens);
            try checkImportedTypeValueExprs(ctx.allocator, tokens, import_ref.alias_idx);
            try checkImportedStdContainerDirectAccess(tokens, import_ref);
        }
        if (target_kind == .func) {
            try checkImportedFuncCalls(ctx, tokens, import_ref, child_tokens);
            try appendImportedAliasFuncShapes(
                ctx.allocator,
                &imported_func_shapes,
                import_ref.alias_idx,
                tokens[import_ref.alias_idx].lexeme,
                import_ref.target,
                child_tokens,
            );
        }

        i = findLineEndIdx(tokens, i) - 1;
    }

    try checkImportedFunctionValueResolution(ctx.allocator, tokens, imported_func_shapes.items);
    try checkImportedDeferStmts(ctx.allocator, tokens, imported_func_shapes.items);

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

fn checkImportedPrivateFieldCtors(
    ctx: *Context,
    tokens: []const lexer.Token,
    import_ref: ImportRef,
    child_tokens: []const lexer.Token,
) !void {
    var private_fields = std.ArrayList(PrivateField).empty;
    defer private_fields.deinit(ctx.allocator);

    try collectPrivateStructFields(ctx.allocator, &private_fields, child_tokens, import_ref.target);
    if (private_fields.items.len == 0) return;
    const has_required_private = hasRequiredPrivateField(private_fields.items);

    const alias = tokens[import_ref.alias_idx].lexeme;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, tokens[i].lexeme, alias)) continue;
        const open_brace = typeCtorOpenAfterAlias(tokens, i) orelse continue;
        if (isReturnTypeBeforeFuncBody(tokens, i, open_brace)) continue;
        if (isTopLevelDeclHead(tokens, i) and isTypeDeclStart(tokens, i)) continue;

        const close_brace = findMatching(tokens, open_brace, "{", "}") catch
            return markErrorAt(tokens, i, error.InvalidStructLiteral);
        if (has_required_private) return markErrorAt(tokens, i, error.InvalidStructLiteral);
        if (findPrivateFieldInit(tokens, open_brace + 1, close_brace, private_fields.items)) |bad_idx| {
            return markErrorAt(tokens, bad_idx, error.InvalidStructLiteral);
        }
    }

    try checkImportedPrivateFieldInferredCtors(tokens, import_ref.alias_idx, private_fields.items, has_required_private);
    try checkImportedPrivateFieldPathAccess(tokens, import_ref, private_fields.items);
}

fn hasRequiredPrivateField(fields: []const PrivateField) bool {
    for (fields) |field| {
        if (!field.has_default) return true;
    }
    return false;
}

fn checkImportedTypeValueExprs(allocator: std.mem.Allocator, tokens: []const lexer.Token, alias_idx: usize) !void {
    const alias = tokens[alias_idx].lexeme;
    var program = parser.parseProgram(allocator, tokens, tokens.len) catch
        return markErrorAt(tokens, alias_idx, error.InvalidImportDecl);
    defer program.deinit(allocator);

    for (program.expr_nodes) |node| {
        if (node.kind != .ident) continue;
        const tok = tokens[node.start_tok];
        if (!std.mem.eql(u8, tok.lexeme, alias)) continue;
        return markErrorAt(tokens, node.start_tok, error.InvalidTypeRef);
    }
}

fn isTypeConstructorExpr(tokens: []const lexer.Token, start_idx: usize) bool {
    return typeCtorOpenAfterAlias(tokens, start_idx) != null;
}

fn typeCtorOpenAfterAlias(tokens: []const lexer.Token, start_idx: usize) ?usize {
    var idx = start_idx + 1;
    if (idx < tokens.len and tokEq(tokens[idx], "<")) {
        const close_angle = findMatching(tokens, idx, "<", ">") catch return null;
        idx = close_angle + 1;
    }
    if (idx < tokens.len and tokEq(tokens[idx], "{")) return idx;
    return null;
}

fn isReturnTypeBeforeFuncBody(tokens: []const lexer.Token, type_idx: usize, open_brace: usize) bool {
    if (open_brace == 0 or tokens[open_brace].line != tokens[type_idx].line) return false;
    if (tokens[open_brace - 1].line != tokens[type_idx].line) return false;
    var i = type_idx;
    while (i > 0) {
        i -= 1;
        if (tokens[i].line != tokens[type_idx].line) return false;
        if (isReturnArrowAt(tokens, i)) return true;
    }
    return false;
}

fn collectPrivateStructFields(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(PrivateField),
    tokens: []const lexer.Token,
    target: []const u8,
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
        if (!isTopLevelDeclHead(tokens, i)) continue;
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, tokens[i].lexeme, target)) continue;
        if (isPrivateDeclName(tokens[i].lexeme)) continue;
        if (!tokEq(tokens[i + 1], "{")) continue;

        const close_brace = findMatching(tokens, i + 1, "{", "}") catch return;
        try collectPrivateFieldNames(allocator, out, tokens, i + 2, close_brace);
        return;
    }
}

fn collectPrivateFieldNames(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(PrivateField),
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) !void {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and
            tokens[i].kind == .ident and isPrivateDeclName(tokens[i].lexeme))
        {
            const line_end = @min(findLineEndIdx(tokens, i), end_idx);
            try out.append(allocator, .{
                .name = tokens[i].lexeme[1..],
                .has_default = findTopLevelAssignEqOnLine(tokens, i + 1, line_end) != null,
            });
        }

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
}

fn checkImportedPrivateFieldInferredCtors(
    tokens: []const lexer.Token,
    alias_idx: usize,
    private_fields: []const PrivateField,
    has_required_private: bool,
) !void {
    const alias = tokens[alias_idx].lexeme;
    var line_start: usize = 0;
    while (line_start < tokens.len) {
        const line_end = findLineEndIdx(tokens, line_start);
        if (findDirectAliasInferredCtor(tokens, line_start, line_end, alias)) |dot_idx| {
            if (has_required_private) return markErrorAt(tokens, dot_idx, error.InvalidStructLiteral);
            const open_brace = dot_idx + 1;
            const close_brace = findMatching(tokens, open_brace, "{", "}") catch
                return markErrorAt(tokens, dot_idx, error.InvalidStructLiteral);
            if (findPrivateFieldInit(tokens, open_brace + 1, close_brace, private_fields)) |bad_idx| {
                return markErrorAt(tokens, bad_idx, error.InvalidStructLiteral);
            }
        }
        line_start = line_end;
    }
}

fn checkImportedPrivateFieldPathAccess(
    tokens: []const lexer.Token,
    import_ref: ImportRef,
    private_fields: []const PrivateField,
) !void {
    const alias = tokens[import_ref.alias_idx].lexeme;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tokEq(tokens[i], "get") and !tokEq(tokens[i], "set")) continue;
        if (i == 0 or !tokEq(tokens[i - 1], "@") or tokens[i - 1].line != tokens[i].line) continue;
        if (i + 1 >= tokens.len or !tokEq(tokens[i + 1], "(")) continue;

        const close_paren = findMatching(tokens, i + 1, "(", ")") catch continue;
        const first_start = i + 2;
        const first_end = findTopLevelArgEnd(tokens, first_start, close_paren);
        if (first_end != first_start + 1 or tokens[first_start].kind != .ident) {
            i = close_paren;
            continue;
        }
        if (!valueHasImportedTypeAlias(tokens, i, tokens[first_start].lexeme, alias)) {
            i = close_paren;
            continue;
        }

        var arg_start = first_end;
        while (arg_start < close_paren) {
            if (!tokEq(tokens[arg_start], ",")) break;
            arg_start += 1;
            const arg_end = findTopLevelArgEnd(tokens, arg_start, close_paren);
            if (arg_end == arg_start + 1 and tokens[arg_start].kind == .ident and isPrivatePathField(private_fields, tokens[arg_start].lexeme)) {
                return markErrorAt(tokens, arg_start, error.InvalidPathAccess);
            }
            arg_start = arg_end;
        }

        i = close_paren;
    }
}

fn isPrivatePathField(private_fields: []const PrivateField, name: []const u8) bool {
    if (name.len < 2 or name[0] != '.') return false;
    return isPrivateFieldName(private_fields, name[1..]);
}

fn findPrivateFieldInit(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    private_fields: []const PrivateField,
) ?usize {
    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !isTopLevelCommaAny(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i and tokens[seg_start].kind == .ident and isPrivateFieldName(private_fields, tokens[seg_start].lexeme)) {
            return seg_start;
        }
        seg_start = i + 1;
    }
    return null;
}

fn isPrivateFieldName(private_fields: []const PrivateField, name: []const u8) bool {
    for (private_fields) |field| {
        if (std.mem.eql(u8, field.name, name)) return true;
    }
    return false;
}

fn findDirectAliasInferredCtor(
    tokens: []const lexer.Token,
    line_start: usize,
    line_end: usize,
    alias: []const u8,
) ?usize {
    if (line_start + 3 >= line_end) return null;
    if (tokens[line_start].kind != .ident) return null;
    if (tokens[line_start + 1].kind != .ident) return null;
    if (!std.mem.eql(u8, tokens[line_start + 1].lexeme, alias)) return null;

    const eq_idx = findTopLevelEq(tokens, line_start + 2, line_end) orelse return null;
    if (eq_idx + 2 >= line_end) return null;
    if (!tokEq(tokens[eq_idx + 1], ".") or !tokEq(tokens[eq_idx + 2], "{")) return null;
    return eq_idx + 1;
}

fn checkImportedStdContainerDirectAccess(tokens: []const lexer.Token, import_ref: ImportRef) !void {
    if (import_ref.prefix != .std) return;
    if (!std.mem.eql(u8, import_ref.target, "List") and !std.mem.eql(u8, import_ref.target, "HashMap")) return;

    const alias = tokens[import_ref.alias_idx].lexeme;
    try checkImportedStdContainerDirectLoop(tokens, alias);
    try checkImportedStdContainerDirectPath(tokens, alias);
}

fn checkImportedStdContainerDirectLoop(tokens: []const lexer.Token, alias: []const u8) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tokEq(tokens[i], "loop")) continue;
        const line_end = findLineEndIdx(tokens, i);
        const eq_idx = findTopLevelEq(tokens, i + 1, line_end) orelse continue;
        if (loopBindCount(tokens, i + 1, eq_idx) < 2) continue;
        const source_idx = eq_idx + 1;
        if (source_idx >= line_end or tokens[source_idx].kind != .ident) continue;
        if (!valueHasNearestTypeAlias(tokens, i, tokens[source_idx].lexeme, alias)) continue;
        return markErrorAt(tokens, source_idx, error.InvalidLoopSource);
    }
}

fn checkImportedStdContainerDirectPath(tokens: []const lexer.Token, alias: []const u8) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tokEq(tokens[i], "get") and !tokEq(tokens[i], "set")) continue;
        if (i + 1 >= tokens.len or !tokEq(tokens[i + 1], "(")) continue;
        const close_paren = findMatching(tokens, i + 1, "(", ")") catch continue;
        const first_arg = firstArgStart(i + 2, close_paren) orelse continue;
        if (tokens[first_arg].kind != .ident) continue;
        if (!valueHasNearestTypeAlias(tokens, i, tokens[first_arg].lexeme, alias)) {
            i = close_paren;
            continue;
        }
        return markErrorAt(tokens, first_arg, error.InvalidPathAccess);
    }
}

fn loopBindCount(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    var count: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokens[i].kind == .ident or tokEq(tokens[i], "_")) count += 1;
    }
    return count;
}

fn firstArgStart(start_idx: usize, end_idx: usize) ?usize {
    if (start_idx >= end_idx) return null;
    return start_idx;
}

fn valueHasNearestTypeAlias(tokens: []const lexer.Token, before_idx: usize, name: []const u8, alias: []const u8) bool {
    var skip_depth: usize = 0;
    var i = before_idx;
    while (i > 0) {
        i -= 1;

        if (tokEq(tokens[i], "}")) {
            skip_depth += 1;
            continue;
        }
        if (tokEq(tokens[i], "{")) {
            if (skip_depth > 0) skip_depth -= 1;
            continue;
        }
        if (skip_depth != 0) continue;
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, tokens[i].lexeme, name)) continue;

        const line_end = findLineEndIdx(tokens, i);
        const eq_idx = findTopLevelEq(tokens, i + 1, line_end) orelse continue;
        if (eq_idx > i + 1 and tokens[i + 1].kind == .ident and std.mem.eql(u8, tokens[i + 1].lexeme, alias)) return true;
        if (eq_idx + 1 < line_end and tokens[eq_idx + 1].kind == .ident and std.mem.eql(u8, tokens[eq_idx + 1].lexeme, alias)) return true;
    }
    return false;
}

fn valueHasImportedTypeAlias(tokens: []const lexer.Token, before_idx: usize, name: []const u8, alias: []const u8) bool {
    if (valueHasNearestTypeAlias(tokens, before_idx, name, alias)) return true;
    return enclosingFuncParamHasTypeAlias(tokens, before_idx, name, alias);
}

fn enclosingFuncParamHasTypeAlias(tokens: []const lexer.Token, before_idx: usize, name: []const u8, alias: []const u8) bool {
    var skip_depth: usize = 0;
    var i = before_idx;
    while (i > 0) {
        i -= 1;
        if (tokEq(tokens[i], "}")) {
            skip_depth += 1;
            continue;
        }
        if (!tokEq(tokens[i], "{")) continue;
        if (skip_depth > 0) {
            skip_depth -= 1;
            continue;
        }
        return funcParamHasTypeAliasBeforeBody(tokens, i, name, alias);
    }
    return false;
}

fn funcParamHasTypeAliasBeforeBody(tokens: []const lexer.Token, body_open_idx: usize, name: []const u8, alias: []const u8) bool {
    const line_start = lineStartIdx(tokens, body_open_idx);
    if (line_start >= body_open_idx) return false;
    if (!isFuncDeclStart(tokens, line_start)) return false;
    const close_params = findMatching(tokens, line_start + 1, "(", ")") catch return false;
    if (close_params >= body_open_idx) return false;
    return paramListHasTypeAlias(tokens, line_start + 2, close_params, name, alias);
}

fn paramListHasTypeAlias(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, name: []const u8, alias: []const u8) bool {
    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !isTopLevelCommaAny(tokens, i, start_idx, end_idx)) continue;
        if (seg_start + 1 < i and tokens[seg_start].kind == .ident and std.mem.eql(u8, tokens[seg_start].lexeme, name)) {
            var type_start = seg_start + 1;
            if (type_start < i and isSpreadToken(tokens[type_start])) type_start += 1;
            if (type_start < i and tokens[type_start].kind == .ident and std.mem.eql(u8, tokens[type_start].lexeme, alias)) return true;
        }
        seg_start = i + 1;
    }
    return false;
}

fn findTopLevelArgEnd(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
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
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tokEq(tokens[i], ",")) return i;
    }
    return end_idx;
}

fn findTopLevelEq(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i: usize = start_idx;
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
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tokEq(tokens[i], "=")) return i;
    }
    return null;
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
        if (isModernImportAssign(tokens, i)) continue;
        if (findPublicEnumMemberKind(tokens, i, target)) |kind| return kind;
        if (!std.mem.eql(u8, tokens[i].lexeme, target)) continue;
        if (isPrivateDeclName(tokens[i].lexeme)) continue;

        if (isFuncDeclStart(tokens, i)) return .func;
        if (isErrorEnumDeclStart(tokens, i)) return .error_type;
        if (isValueEnumDeclStart(tokens, i)) return .value_enum_type;
        if (isValidDeclaredTypeName(tokens[i].lexeme) and isTypeDeclStart(tokens, i)) return .type;
        if (isTopValueDeclStart(tokens, i)) {
            return if (isReadonlyIdentName(tokens[i].lexeme)) .const_value else .var_value;
        }
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
        const call_args = try parseImportCallArgs(ctx.allocator, tokens, i + 2, close_paren);
        defer ctx.allocator.free(call_args.shapes);

        if (!hasCompatibleFuncSig(program.func_sigs, import_ref.target, call_args.shapes.len)) {
            return markErrorAt(tokens, i, error.NoMatchingCall);
        }
        if (call_args.spread_idx) |spread_idx| {
            if (!hasCompatibleSpreadFuncSig(program.func_sigs, import_ref.target, call_args.shapes.len, spread_idx)) {
                return markErrorAt(tokens, call_args.shapes[spread_idx].spread, error.InvalidCallArgList);
            }
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

fn hasCompatibleSpreadFuncSig(func_sigs: []const parser.FuncSig, target: []const u8, arg_count: usize, spread_idx: usize) bool {
    for (func_sigs) |sig| {
        if (!std.mem.eql(u8, sig.name, target)) continue;
        if (!callArityCompatibleWithSig(sig, arg_count)) continue;
        if (sig.param_max != null) continue;
        if (spread_idx < sig.param_min) continue;
        return true;
    }
    return false;
}

fn callArityCompatibleWithSig(sig: parser.FuncSig, arg_count: usize) bool {
    if (sig.param_min > arg_count) return false;
    if (sig.param_max) |max_count| return arg_count <= max_count;
    return true;
}

fn checkImportedFunctionValueResolution(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    imported_funcs: []const FuncShape,
) !void {
    if (imported_funcs.len == 0) return;

    const local_funcs = try collectFuncShapes(allocator, tokens);
    defer freeFuncShapes(allocator, local_funcs);

    try checkImportedFuncSignatureConflicts(tokens, local_funcs, imported_funcs);

    var program = parser.parseProgram(allocator, tokens, tokens.len) catch
        return markErrorAt(tokens, 0, error.InvalidImportDecl);
    defer program.deinit(allocator);

    try checkImportedMultiReturnPositions(tokens, program, local_funcs, imported_funcs);

    var calls = std.ArrayList(CallShape).empty;
    defer {
        for (calls.items) |call| allocator.free(call.arg_shapes);
        calls.deinit(allocator);
    }

    try collectCallShapesFromProgram(allocator, program, tokens, &calls);
    for (calls.items) |call| {
        if (!callUsesImportedFunctionValue(tokens, local_funcs, imported_funcs, call)) continue;
        if (try countCompatibleFunctionValueCandidates(allocator, tokens, local_funcs, imported_funcs, call) != 1) {
            return markErrorAt(tokens, call.start_idx, error.NoMatchingCall);
        }
    }

    try checkBareImportedOverloadedFuncAssign(tokens, local_funcs, imported_funcs);
}

fn checkImportedDeferStmts(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    imported_funcs: []const FuncShape,
) !void {
    if (imported_funcs.len == 0) return;

    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tokEq(tokens[i], "defer")) continue;
        const call_idx = i + 1;
        if (call_idx >= tokens.len) return markErrorAt(tokens, i, error.NoMatchingCall);
        if (tokEq(tokens[call_idx], "{")) {
            const close_block = findMatching(tokens, call_idx, "{", "}") catch return markErrorAt(tokens, call_idx, error.NoMatchingCall);
            i = close_block;
            continue;
        }
        if (tokens[call_idx].kind != .ident) continue;
        if (call_idx + 1 >= tokens.len or !tokEq(tokens[call_idx + 1], "(")) continue;

        const name = tokens[call_idx].lexeme;
        if (!hasKnownFuncCandidate(imported_funcs, name)) continue;
        const line_end = findLineEndIdx(tokens, call_idx);
        const close_paren = findMatching(tokens, call_idx + 1, "(", ")") catch return markErrorAt(tokens, call_idx, error.NoMatchingCall);
        if (close_paren + 1 != line_end) return markErrorAt(tokens, call_idx, error.NoMatchingCall);

        const args = try parseCallArgShapes(allocator, tokens, call_idx + 2, close_paren);
        defer allocator.free(args);

        var saw_func_candidate = false;
        for (imported_funcs) |func| {
            if (!std.mem.eql(u8, func.name, name)) continue;
            if (!callArityCompatibleWithFunc(func, args.len)) continue;
            saw_func_candidate = true;
            if (funcReturnIsNil(func.return_type)) return;
        }
        if (saw_func_candidate) return markErrorAt(tokens, call_idx, error.NoMatchingCall);
    }
}

fn funcReturnIsNil(return_type: ?[]const u8) bool {
    const ty = return_type orelse return true;
    return std.mem.eql(u8, ty, "nil");
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

fn checkImportedMultiReturnPositions(
    tokens: []const lexer.Token,
    program: parser.Program,
    local_funcs: []const FuncShape,
    imported_funcs: []const FuncShape,
) !void {
    for (program.value_exprs) |site| {
        if (site.expected_arity <= 1) continue;

        const resolved = rootExprReturnArity(program, local_funcs, imported_funcs, site.root_expr_idx);
        const allowed = switch (resolved) {
            .unknown => true,
            .ambiguous => false,
            .arity => |arity| arity == site.expected_arity,
        };
        if (allowed) continue;

        const start_tok = rootExprStartTok(program, site.root_expr_idx);
        const err = switch (site.context) {
            .assign => error.InvalidAssignExpr,
            .rhs => error.MultiReturnInSingleValuePosition,
            .return_value => error.InvalidReturnStmt,
            .single => error.MultiReturnInSingleValuePosition,
        };
        return markErrorAt(tokens, start_tok, err);
    }

    for (program.condition_exprs) |site| {
        const call_site = findDirectCallAtRoot(program, site.root_expr_idx) orelse continue;
        const resolved = resolveFuncReturnArity(
            local_funcs,
            imported_funcs,
            call_site.call.func_name,
            call_site.call.arg_count,
        );
        switch (resolved) {
            .unknown => continue,
            .arity => |arity| {
                if (arity <= 1) continue;
                const err = switch (site.context) {
                    .if_cond => error.MultiReturnInIfCondition,
                    .loop_cond => error.MultiReturnInLoopCondition,
                };
                return markErrorAt(tokens, call_site.start_tok_idx, err);
            },
            .ambiguous => return markErrorAt(tokens, call_site.start_tok_idx, error.AmbiguousConditionCallReturnArity),
        }
    }

    for (program.expr_nodes) |node| {
        switch (node.kind) {
            .call => {},
            else => continue,
        }

        const resolved = resolveFuncReturnArity(
            local_funcs,
            imported_funcs,
            node.data.call.func_name,
            node.data.call.arg_count,
        );
        const arity = switch (resolved) {
            .unknown => continue,
            .ambiguous => return markErrorAt(tokens, node.start_tok, error.AmbiguousConditionCallReturnArity),
            .arity => |value| value,
        };
        if (arity <= 1) continue;

        const call_start = node.start_tok;
        if (valueExprAllowsArityAt(program, call_start, arity)) continue;
        return markErrorAt(tokens, call_start, error.MultiReturnInSingleValuePosition);
    }

    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (!isCallHead(tokens, i)) continue;
        if (isTopLevelDeclHead(tokens, i) and isFuncDeclStart(tokens, i)) continue;
        if (isFuncConstraintHead(tokens, i)) continue;

        const close_paren = findMatching(tokens, i + 1, "(", ")") catch
            return markErrorAt(tokens, i + 1, error.InvalidCallArgList);
        const arg_count = countCallArgs(tokens, i + 2, close_paren) catch
            return markErrorAt(tokens, i + 1, error.InvalidCallArgList);

        const resolved = resolveFuncReturnArity(local_funcs, imported_funcs, tokens[i].lexeme, arg_count);
        const arity = switch (resolved) {
            .unknown => continue,
            .ambiguous => return markErrorAt(tokens, i, error.AmbiguousConditionCallReturnArity),
            .arity => |value| value,
        };
        if (arity <= 1) continue;
        if (valueExprAllowsArityAt(program, i, arity)) continue;

        return markErrorAt(tokens, i, error.MultiReturnInSingleValuePosition);
    }
}

fn rootExprReturnArity(
    program: parser.Program,
    local_funcs: []const FuncShape,
    imported_funcs: []const FuncShape,
    root_idx: usize,
) ReturnArityResolve {
    if (root_idx >= program.expr_nodes.len) return .{ .arity = 1 };
    const node = program.expr_nodes[root_idx];

    return switch (node.kind) {
        .paren => rootExprReturnArity(program, local_funcs, imported_funcs, node.data.child),
        .call => resolveFuncReturnArity(
            local_funcs,
            imported_funcs,
            node.data.call.func_name,
            node.data.call.arg_count,
        ),
        else => .{ .arity = 1 },
    };
}

fn resolveFuncReturnArity(
    local_funcs: []const FuncShape,
    imported_funcs: []const FuncShape,
    name: []const u8,
    arg_count: usize,
) ReturnArityResolve {
    var matched_arity: ?usize = null;

    if (!mergeFuncReturnArity(local_funcs, name, arg_count, &matched_arity)) return .ambiguous;
    if (!mergeFuncReturnArity(imported_funcs, name, arg_count, &matched_arity)) return .ambiguous;

    if (matched_arity) |arity| return .{ .arity = arity };
    return .unknown;
}

fn mergeFuncReturnArity(
    funcs: []const FuncShape,
    name: []const u8,
    arg_count: usize,
    matched_arity: *?usize,
) bool {
    for (funcs) |func| {
        if (!std.mem.eql(u8, func.name, name)) continue;
        if (!callArityCompatibleWithFunc(func, arg_count)) continue;

        if (matched_arity.*) |arity| {
            if (arity != func.return_arity) return false;
            continue;
        }
        matched_arity.* = func.return_arity;
    }
    return true;
}

const DirectCallSite = struct {
    call: parser.FuncCallRef,
    start_tok_idx: usize,
};

fn findDirectCallAtRoot(program: parser.Program, root_idx: usize) ?DirectCallSite {
    if (root_idx >= program.expr_nodes.len) return null;
    const node = program.expr_nodes[root_idx];

    return switch (node.kind) {
        .call => .{
            .call = node.data.call,
            .start_tok_idx = node.start_tok,
        },
        .paren => findDirectCallAtRoot(program, node.data.child),
        else => null,
    };
}

fn rootExprStartTok(program: parser.Program, root_idx: usize) usize {
    if (root_idx >= program.expr_nodes.len) return 0;
    const node = program.expr_nodes[root_idx];
    return switch (node.kind) {
        .paren => rootExprStartTok(program, node.data.child),
        else => node.start_tok,
    };
}

fn valueExprAllowsArityAt(program: parser.Program, start_tok: usize, arity: usize) bool {
    for (program.value_exprs) |site| {
        if (site.expected_arity != arity) continue;
        if (!rootExprMatchesCallStart(program, site.root_expr_idx, start_tok)) continue;
        return true;
    }
    return false;
}

fn rootExprMatchesCallStart(program: parser.Program, root_idx: usize, start_tok: usize) bool {
    if (root_idx >= program.expr_nodes.len) return false;
    const node = program.expr_nodes[root_idx];
    return switch (node.kind) {
        .paren => rootExprMatchesCallStart(program, node.data.child, start_tok),
        .call => node.start_tok == start_tok,
        else => false,
    };
}

fn appendImportedAliasFuncShapes(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(FuncShape),
    alias_idx: usize,
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
        const arity = parseFuncParamArity(child_tokens, i + 2, close_paren);
        const return_arity = parseTopLevelFuncReturnArity(child_tokens, close_paren + 1);
        try out.append(allocator, .{
            .name = alias,
            .start_idx = alias_idx,
            .param_shapes = params,
            .param_min = arity.param_min,
            .param_max = arity.param_max,
            .return_type = parseTopLevelFuncReturnType(child_tokens, close_paren + 1),
            .return_arity = return_arity,
            .is_generic = funcHasGenericSignatureParam(child_tokens, i, params),
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
        const arity = parseFuncParamArity(tokens, i + 2, close_paren);
        const return_arity = parseTopLevelFuncReturnArity(tokens, close_paren + 1);
        try out.append(allocator, .{
            .name = publicFuncName(tokens[i].lexeme),
            .start_idx = i,
            .param_shapes = params,
            .param_min = arity.param_min,
            .param_max = arity.param_max,
            .return_type = parseTopLevelFuncReturnType(tokens, close_paren + 1),
            .return_arity = return_arity,
            .is_generic = funcHasGenericSignatureParam(tokens, i, params),
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
            .value => |type_name| if (type_name) |name| allocator.free(name),
            .variadic => |type_name| if (type_name) |name| allocator.free(name),
            .func => |func_type| allocator.free(func_type.param_types),
        }
    }
    allocator.free(shapes);
}

fn checkImportedFuncSignatureConflicts(
    tokens: []const lexer.Token,
    local_funcs: []const FuncShape,
    imported_funcs: []const FuncShape,
) !void {
    for (imported_funcs, 0..) |imported, idx| {
        for (local_funcs) |local| {
            if (!funcSignaturesConflict(imported, local)) continue;
            return markErrorAt(tokens, imported.start_idx, error.DuplicateFuncSignature);
        }
        for (imported_funcs[0..idx]) |prev| {
            if (!funcSignaturesConflict(imported, prev)) continue;
            return markErrorAt(tokens, imported.start_idx, error.DuplicateFuncSignature);
        }
    }
}

fn funcSignaturesConflict(a: FuncShape, b: FuncShape) bool {
    if (!std.mem.eql(u8, a.name, b.name)) return false;
    if (funcParamShapesEqual(a.param_shapes, b.param_shapes)) return true;
    if (a.param_shapes.len != b.param_shapes.len) return false;
    if (!a.is_generic and !b.is_generic) return false;
    return a.is_generic == b.is_generic;
}

fn funcHasGenericSignatureParam(tokens: []const lexer.Token, func_start_idx: usize, params: []const FuncParamShape) bool {
    for (params) |param| {
        const type_name = switch (param) {
            .value => |value_type| value_type orelse continue,
            .variadic => |value_type| value_type orelse continue,
            else => continue,
        };
        if (!isFuncTypeParam(tokens, func_start_idx, type_name)) continue;
        if (typeConstraintIsConcreteFunctionType(tokens, func_start_idx, type_name)) continue;
        return true;
    }
    return false;
}

fn funcSignaturesEqual(a: FuncShape, b: FuncShape) bool {
    if (!std.mem.eql(u8, a.name, b.name)) return false;
    return funcParamShapesEqual(a.param_shapes, b.param_shapes);
}

fn funcParamShapesEqual(a: []const FuncParamShape, b: []const FuncParamShape) bool {
    if (a.len != b.len) return false;
    for (a, 0..) |item, idx| {
        if (!funcParamShapeEqual(item, b[idx])) return false;
    }
    return true;
}

fn funcParamShapeEqual(a: FuncParamShape, b: FuncParamShape) bool {
    return switch (a) {
        .other => switch (b) {
            .other => true,
            else => false,
        },
        .value => |a_type| switch (b) {
            .value => |b_type| optionalTypeNameEqual(a_type, b_type),
            else => false,
        },
        .variadic => |a_type| switch (b) {
            .variadic => |b_type| optionalTypeNameEqual(a_type, b_type),
            else => false,
        },
        .func => |a_func| switch (b) {
            .func => |b_func| funcTypeShapeEqual(a_func, b_func),
            else => false,
        },
    };
}

fn funcTypeShapeEqual(a: FuncTypeShape, b: FuncTypeShape) bool {
    if (a.param_count != b.param_count) return false;
    if (a.param_types.len != b.param_types.len) return false;
    for (a.param_types, 0..) |a_type, idx| {
        if (!optionalTypeNameEqual(a_type, b.param_types[idx])) return false;
    }
    return optionalTypeNameEqual(a.return_type, b.return_type);
}

fn optionalTypeNameEqual(a: ?[]const u8, b: ?[]const u8) bool {
    if (a) |a_name| {
        const b_name = b orelse return false;
        return std.mem.eql(u8, a_name, b_name);
    }
    return b == null;
}

fn parseFuncParamShapes(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ![]FuncParamShape {
    var out = std.ArrayList(FuncParamShape).empty;
    errdefer {
        for (out.items) |shape| {
            switch (shape) {
                .value => |type_name| if (type_name) |name| allocator.free(name),
                .variadic => |type_name| if (type_name) |name| allocator.free(name),
                .func => |func_type| allocator.free(func_type.param_types),
                .other => {},
            }
        }
        out.deinit(allocator);
    }

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
    const type_start = if (isSpreadToken(tokens[start_idx + 1])) start_idx + 2 else start_idx + 1;
    if (type_start >= end_idx) return .other;
    if (!tokEq(tokens[type_start], "(")) {
        const type_name = try compactTypeName(allocator, tokens, type_start, end_idx);
        if (type_start != start_idx + 1) return .{ .variadic = type_name };
        return .{ .value = type_name };
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

fn compactTypeName(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) !?[]const u8 {
    if (start_idx >= end_idx) return null;

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        try out.appendSlice(allocator, tokens[i].lexeme);
    }
    return try out.toOwnedSlice(allocator);
}

fn parseFuncParamArity(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) struct { param_min: usize, param_max: ?usize } {
    var min_count: usize = 0;
    var has_variadic = false;
    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !isTopLevelCommaAny(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            if (seg_start + 1 < i and isSpreadToken(tokens[seg_start + 1])) {
                has_variadic = true;
            } else {
                min_count += 1;
            }
        }
        seg_start = i + 1;
    }
    return .{
        .param_min = min_count,
        .param_max = if (has_variadic) null else min_count,
    };
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
            .call => {},
            else => continue,
        }

        const call_start = node.start_tok;
        if (call_start + 1 >= node.end_tok) continue;
        if (!tokEq(tokens[call_start + 1], "(")) continue;

        const args_start = call_start + 2;
        const args_end = node.end_tok - 1;
        const args = try parseCallArgShapes(allocator, tokens, args_start, args_end);
        try out.append(allocator, .{
            .name = tokens[call_start].lexeme,
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
            if (isSpreadToken(tokens[seg_start])) {
                try out.append(allocator, .{ .spread = seg_start });
            } else if (seg_start + 1 == i and tokens[seg_start].kind == .ident) {
                try out.append(allocator, .{ .ident = tokens[seg_start].lexeme });
            } else {
                try out.append(allocator, .other);
            }
        }
        seg_start = i + 1;
    }

    return out.toOwnedSlice(allocator);
}

fn parseImportCallArgs(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) !ImportCallArgs {
    const shapes = try parseCallArgShapes(allocator, tokens, start_idx, end_idx);
    errdefer allocator.free(shapes);

    return .{
        .shapes = shapes,
        .spread_idx = callArgSpreadIndex(shapes),
    };
}

fn callArgSpreadIndex(args: []const CallArgShape) ?usize {
    for (args, 0..) |arg, arg_idx| {
        if (arg == .spread) return arg_idx;
    }
    return null;
}

fn callUsesImportedFunctionValue(
    tokens: []const lexer.Token,
    local_funcs: []const FuncShape,
    imported_funcs: []const FuncShape,
    call: CallShape,
) bool {
    for (call.arg_shapes, 0..) |arg, arg_index| {
        if (arg != .ident) continue;
        const name = arg.ident;
        if (!hasKnownFuncCandidate(imported_funcs, name)) continue;
        if (callHasFuncParamCandidateAtIndex(tokens, local_funcs, imported_funcs, call, arg_index)) return true;
    }
    return false;
}

fn callHasFuncParamCandidateAtIndex(
    tokens: []const lexer.Token,
    local_funcs: []const FuncShape,
    imported_funcs: []const FuncShape,
    call: CallShape,
    arg_index: usize,
) bool {
    for (local_funcs) |func| {
        if (!std.mem.eql(u8, func.name, call.name)) continue;
        if (!callArityCompatibleWithFunc(func, call.arg_shapes.len)) continue;
        if (arg_index >= func.param_shapes.len) continue;
        if (funcParamShapeIsFunctionLike(tokens, func, func.param_shapes[arg_index], true)) return true;
    }
    for (imported_funcs) |func| {
        if (!std.mem.eql(u8, func.name, call.name)) continue;
        if (!callArityCompatibleWithFunc(func, call.arg_shapes.len)) continue;
        if (arg_index >= func.param_shapes.len) continue;
        if (funcParamShapeIsFunctionLike(tokens, func, func.param_shapes[arg_index], false)) return true;
    }
    return false;
}

fn countCompatibleFunctionValueCandidates(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    local_funcs: []const FuncShape,
    imported_funcs: []const FuncShape,
    call: CallShape,
) !usize {
    var count: usize = 0;
    for (local_funcs) |func| {
        if (!std.mem.eql(u8, func.name, call.name)) continue;
        if (!callArityCompatibleWithFunc(func, call.arg_shapes.len)) continue;
        if (!(try functionValueArgsMatchFunc(allocator, tokens, local_funcs, imported_funcs, func, call, true))) continue;
        count += 1;
    }
    for (imported_funcs) |func| {
        if (!std.mem.eql(u8, func.name, call.name)) continue;
        if (!callArityCompatibleWithFunc(func, call.arg_shapes.len)) continue;
        if (!(try functionValueArgsMatchFunc(allocator, tokens, local_funcs, imported_funcs, func, call, false))) continue;
        count += 1;
    }
    return count;
}

fn callArityCompatibleWithFunc(func: FuncShape, arg_count: usize) bool {
    if (arg_count < func.param_min) return false;
    if (func.param_max) |max_count| return arg_count <= max_count;
    return true;
}

fn functionValueArgsMatchFunc(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    local_funcs: []const FuncShape,
    imported_funcs: []const FuncShape,
    func: FuncShape,
    call: CallShape,
    allow_named_constraints: bool,
) !bool {
    for (call.arg_shapes, 0..) |arg, arg_index| {
        if (arg != .ident) continue;
        const name = arg.ident;
        if (!hasKnownFuncCandidate(local_funcs, name) and !hasKnownFuncCandidate(imported_funcs, name)) continue;
        if (arg_index >= func.param_shapes.len) return false;

        const target = try resolveFuncParamTypeShape(allocator, tokens, func, func.param_shapes[arg_index], allow_named_constraints);
        defer freeResolvedFuncTypeShape(allocator, target);
        const target_func = if (target) |resolved| resolved.shape else continue;
        if (countFuncsMatchingTarget(local_funcs, imported_funcs, name, target_func) != 1) return false;
    }
    return true;
}

fn funcParamShapeIsFunctionLike(
    tokens: []const lexer.Token,
    func: FuncShape,
    param: FuncParamShape,
    allow_named_constraints: bool,
) bool {
    return switch (param) {
        .func => true,
        .value => |type_name| if (allow_named_constraints) blk: {
            const name = type_name orelse break :blk false;
            break :blk typeConstraintIsConcreteFunctionType(tokens, func.start_idx, name);
        } else false,
        .variadic => |type_name| if (allow_named_constraints) blk: {
            const name = type_name orelse break :blk false;
            break :blk typeConstraintIsConcreteFunctionType(tokens, func.start_idx, name);
        } else false,
        else => false,
    };
}

fn resolveFuncParamTypeShape(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    func: FuncShape,
    param: FuncParamShape,
    allow_named_constraints: bool,
) !?ResolvedFuncTypeShape {
    return switch (param) {
        .func => |func_type| .{ .shape = func_type, .owned = false },
        .value => |type_name| if (allow_named_constraints) blk: {
            const name = type_name orelse break :blk null;
            break :blk try parseConcreteFuncTypeConstraintShape(allocator, tokens, func.start_idx, name);
        } else null,
        .variadic => |type_name| if (allow_named_constraints) blk: {
            const name = type_name orelse break :blk null;
            break :blk try parseConcreteFuncTypeConstraintShape(allocator, tokens, func.start_idx, name);
        } else null,
        .other => null,
    };
}

fn freeResolvedFuncTypeShape(allocator: std.mem.Allocator, resolved: ?ResolvedFuncTypeShape) void {
    const item = resolved orelse return;
    if (!item.owned) return;
    allocator.free(item.shape.param_types);
}

fn parseConcreteFuncTypeConstraintShape(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    func_start_idx: usize,
    constraint_name: []const u8,
) !?ResolvedFuncTypeShape {
    const block_start = findConstraintBlockStartBefore(tokens, func_start_idx) orelse return null;

    var i = block_start;
    while (i < func_start_idx) {
        if (!tokEq(tokens[i], "#")) {
            i += 1;
            continue;
        }
        const line_end = findLineEndIdx(tokens, i);
        const is_func_constraint = i + 2 < line_end and tokEq(tokens[i + 2], "(");
        if (is_func_constraint or i + 1 >= line_end or !std.mem.eql(u8, tokens[i + 1].lexeme, constraint_name)) {
            i = line_end;
            continue;
        }

        const eq_idx = findTopLevelAssignEqOnLine(tokens, i + 2, line_end) orelse return null;
        if (!isFuncTypeRange(tokens, eq_idx + 1, line_end)) return null;
        if (funcTypeConstraintUsesPriorTypeParam(tokens, block_start, i, eq_idx + 1, line_end)) return null;

        const close_params = findMatching(tokens, eq_idx + 1, "(", ")") catch return null;
        const param_types = try parseTypeNameList(allocator, tokens, eq_idx + 2, close_params);
        return .{
            .shape = .{
                .param_count = param_types.len,
                .param_types = param_types,
                .return_type = simpleTypeName(tokens, close_params + 3, line_end),
            },
            .owned = true,
        };
    }
    return null;
}

fn typeConstraintIsConcreteFunctionType(
    tokens: []const lexer.Token,
    func_start_idx: usize,
    constraint_name: []const u8,
) bool {
    const block_start = findConstraintBlockStartBefore(tokens, func_start_idx) orelse return false;

    var i = block_start;
    while (i < func_start_idx) {
        if (!tokEq(tokens[i], "#")) {
            i += 1;
            continue;
        }
        const line_end = findLineEndIdx(tokens, i);
        const is_func_constraint = i + 2 < line_end and tokEq(tokens[i + 2], "(");
        if (is_func_constraint or i + 1 >= line_end or !std.mem.eql(u8, tokens[i + 1].lexeme, constraint_name)) {
            i = line_end;
            continue;
        }

        const eq_idx = findTopLevelAssignEqOnLine(tokens, i + 2, line_end) orelse return false;
        if (!isFuncTypeRange(tokens, eq_idx + 1, line_end)) return false;
        return !funcTypeConstraintUsesPriorTypeParam(tokens, block_start, i, eq_idx + 1, line_end);
    }
    return false;
}

fn isFuncTypeParam(tokens: []const lexer.Token, func_start_idx: usize, name: []const u8) bool {
    const block_start = findConstraintBlockStartBefore(tokens, func_start_idx) orelse return false;

    var i = block_start;
    while (i < func_start_idx) {
        if (!tokEq(tokens[i], "#")) {
            i += 1;
            continue;
        }
        const line_end = findLineEndIdx(tokens, i);
        const is_func_constraint = i + 2 < line_end and tokEq(tokens[i + 2], "(");
        if (!is_func_constraint and i + 1 < line_end and std.mem.eql(u8, tokens[i + 1].lexeme, name)) {
            return true;
        }
        i = line_end;
    }
    return false;
}

fn funcTypeConstraintUsesPriorTypeParam(
    tokens: []const lexer.Token,
    block_start: usize,
    constraint_idx: usize,
    type_start: usize,
    type_end: usize,
) bool {
    var i = type_start;
    while (i < type_end) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (hasTypeConstraintName(tokens, block_start, constraint_idx, tokens[i].lexeme)) return true;
    }
    return false;
}

fn hasTypeConstraintName(
    tokens: []const lexer.Token,
    block_start: usize,
    before_idx: usize,
    name: []const u8,
) bool {
    var i = block_start;
    while (i < before_idx) {
        if (!tokEq(tokens[i], "#")) {
            i += 1;
            continue;
        }
        const line_end = findLineEndIdx(tokens, i);
        const is_func_constraint = i + 2 < line_end and tokEq(tokens[i + 2], "(");
        if (!is_func_constraint and i + 1 < line_end and std.mem.eql(u8, tokens[i + 1].lexeme, name)) {
            return true;
        }
        i = line_end;
    }
    return false;
}

fn findConstraintBlockStartBefore(tokens: []const lexer.Token, decl_start_idx: usize) ?usize {
    if (decl_start_idx == 0 or decl_start_idx >= tokens.len) return null;

    var scan_idx = decl_start_idx;
    var expected_line = tokens[decl_start_idx].line;
    var block_start: ?usize = null;

    while (scan_idx > 0) {
        const prev_idx = scan_idx - 1;
        const prev_line = tokens[prev_idx].line;
        if (prev_line + 1 != expected_line) break;

        const line_start = lineStartIdx(tokens, prev_idx);
        if (!tokEq(tokens[line_start], "#")) break;

        block_start = line_start;
        scan_idx = line_start;
        expected_line = prev_line;
    }

    return block_start;
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
            .variadic => |value_type| value_type orelse return false,
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

fn parseTopLevelFuncReturnArity(tokens: []const lexer.Token, input_start_idx: usize) usize {
    var start_idx = input_start_idx;
    if (isReturnArrowAt(tokens, start_idx)) start_idx += 2;
    if (start_idx >= tokens.len) return 0;
    if (tokEq(tokens[start_idx], "{") or isArrowAt(tokens, start_idx)) return 0;

    if (tokEq(tokens[start_idx], "nil")) {
        if (start_idx + 1 >= tokens.len) return 0;
        if (tokEq(tokens[start_idx + 1], "{") or isArrowAt(tokens, start_idx + 1)) return 0;
    }

    var arity: usize = 0;
    var i = start_idx;
    while (i < tokens.len) {
        const seg_start = i;
        var depth_angle: usize = 0;
        var depth_paren: usize = 0;

        while (i < tokens.len) : (i += 1) {
            if (tokEq(tokens[i], "<")) {
                depth_angle += 1;
                continue;
            }
            if (tokEq(tokens[i], ">")) {
                if (depth_angle > 0) depth_angle -= 1;
                continue;
            }
            if (tokEq(tokens[i], "(")) {
                depth_paren += 1;
                continue;
            }
            if (tokEq(tokens[i], ")")) {
                if (depth_paren > 0) depth_paren -= 1;
                continue;
            }
            if (depth_angle == 0 and depth_paren == 0 and tokEq(tokens[i], ",")) break;
            if (depth_angle == 0 and depth_paren == 0 and (tokEq(tokens[i], "{") or isArrowAt(tokens, i))) break;
            if (tokens[i].line != tokens[start_idx].line) break;
        }

        if (seg_start == i) return arity;
        arity += 1;

        if (i >= tokens.len) return arity;
        if (tokEq(tokens[i], ",")) {
            i += 1;
            continue;
        }
        return arity;
    }
    return arity;
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

fn isSpreadToken(tok: lexer.Token) bool {
    return tok.kind == .symbol and tokEq(tok, "...");
}

fn isCallHead(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (tokens[idx].kind != .ident) return false;
    if (idx > 0 and tokEq(tokens[idx - 1], "@") and tokens[idx - 1].line == tokens[idx].line) return false;
    if (isKeyword(tokens[idx].lexeme)) return false;
    return tokEq(tokens[idx + 1], "(");
}

fn isFuncConstraintHead(tokens: []const lexer.Token, idx: usize) bool {
    if (idx == 0 or !tokEq(tokens[idx - 1], "#")) return false;
    return tokens[idx - 1].line == tokens[idx].line;
}

fn isArrowAt(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 1 < tokens.len and tokEq(tokens[idx], "=") and tokEq(tokens[idx + 1], ">");
}

fn isReturnArrowAt(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 1 < tokens.len and tokEq(tokens[idx], "-") and tokEq(tokens[idx + 1], ">");
}

fn isFuncTypeRange(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx >= end_idx or !tokEq(tokens[start_idx], "(")) return false;
    const close_idx = findMatching(tokens, start_idx, "(", ")") catch return false;
    return close_idx + 2 < end_idx and isReturnArrowAt(tokens, close_idx + 1);
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

fn findPublicEnumMemberKind(tokens: []const lexer.Token, line_start_idx: usize, target: []const u8) ?DeclKind {
    const eq_idx = enumDeclAssignIdx(tokens, line_start_idx) orelse return null;
    if (isPrivateDeclName(tokens[line_start_idx].lexeme)) return null;
    const line_end = findLineEndIdx(tokens, line_start_idx);
    const kind: DeclKind = if (isErrorEnumDeclStart(tokens, line_start_idx)) .error_branch else .value_enum_branch;

    var i = eq_idx + 1;
    while (i < line_end) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (isPrivateDeclName(tokens[i].lexeme)) continue;
        if (std.mem.eql(u8, tokens[i].lexeme, target)) return kind;
    }
    return null;
}

fn aliasMatchesKind(alias: []const u8, kind: DeclKind) bool {
    return switch (kind) {
        .type, .value_enum_type => isValidDeclaredTypeName(alias) and !isErrorTypeName(alias),
        .error_type => isErrorTypeName(alias),
        .error_branch, .value_enum_branch => isValidErrorBranchName(alias) and !isErrorTypeName(alias),
        .func => isLowerIdentName(alias),
        .const_value => isReadonlyIdentName(alias),
        .var_value => isLowerIdentName(alias),
    };
}

fn isTypeLikeKind(kind: DeclKind) bool {
    return switch (kind) {
        .type, .error_type, .value_enum_type => true,
        .error_branch, .value_enum_branch, .func, .const_value, .var_value => false,
    };
}

fn isValidErrorBranchName(name: []const u8) bool {
    if (!isValidDeclaredTypeName(name)) return false;
    if (std.mem.eql(u8, name, "Error")) return false;
    return true;
}

fn isErrorTypeName(name: []const u8) bool {
    if (name.len == 0 or name[0] == '.') return false;
    if (!isValidDeclaredTypeName(name)) return false;
    if (std.mem.eql(u8, name, "Error")) return false;
    return std.mem.endsWith(u8, name, "Error");
}

fn enumDeclAssignIdx(tokens: []const lexer.Token, line_start_idx: usize) ?usize {
    if (isErrorEnumDeclStart(tokens, line_start_idx) or isValueEnumDeclStart(tokens, line_start_idx)) {
        return line_start_idx + 2;
    }
    return null;
}

fn isErrorEnumDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 2 < tokens.len and
        isErrorTypeName(tokens[idx].lexeme) and
        tokEq(tokens[idx + 1], "error") and
        tokEq(tokens[idx + 2], "=");
}

fn isValueEnumDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 2 < tokens.len and
        isValidDeclaredTypeName(tokens[idx].lexeme) and
        !isErrorTypeName(tokens[idx].lexeme) and
        isBaseIntTypeName(tokens[idx + 1].lexeme) and
        tokEq(tokens[idx + 2], "=");
}

fn hasTypeNameConflict(tokens: []const lexer.Token, alias_idx: usize) bool {
    const alias = publicTypeName(tokens[alias_idx].lexeme);

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
        if (i == alias_idx) continue;
        if (!isTopLevelDeclHead(tokens, i)) continue;
        if (tokens[i].kind != .ident) continue;
        if (!isValidDeclaredTypeName(tokens[i].lexeme)) continue;
        if (!isModernImportAssign(tokens, i) and !isTypeDeclStart(tokens, i)) continue;
        if (std.mem.eql(u8, publicTypeName(tokens[i].lexeme), alias)) return true;
    }

    return false;
}

fn publicTypeName(name: []const u8) []const u8 {
    if (name.len != 0 and name[0] == '.') return name[1..];
    return name;
}

fn isModernImportAssign(tokens: []const lexer.Token, idx: usize) bool {
    const eq_idx = topLevelLineAssignIdx(tokens, idx) orelse return false;
    const line_end = findLineEndIdx(tokens, idx);
    const at_idx = eq_idx + 1;
    if (at_idx + 1 >= line_end or !tokEq(tokens[at_idx], "@")) return false;
    if (tokens[at_idx + 1].kind != .ident) return false;
    return std.mem.eql(u8, tokens[at_idx + 1].lexeme, "lib") or
        std.mem.eql(u8, tokens[at_idx + 1].lexeme, "env") or
        std.mem.eql(u8, tokens[at_idx + 1].lexeme, "wasi");
}

fn isNonHostImportAssign(tokens: []const lexer.Token, idx: usize) bool {
    if (!isModernImportAssign(tokens, idx)) return false;
    const eq_idx = topLevelLineAssignIdx(tokens, idx) orelse return false;
    const line_end = findLineEndIdx(tokens, idx);
    const at_idx = eq_idx + 1;
    return !isHostImportLine(tokens, at_idx, line_end);
}

fn parseLibImportClose(tokens: []const lexer.Token, at_idx: usize, line_end: usize) ?usize {
    if (at_idx + 6 >= line_end) return null;
    if (!tokEq(tokens[at_idx], "@")) return null;
    if (tokens[at_idx + 1].kind != .ident or !std.mem.eql(u8, tokens[at_idx + 1].lexeme, "lib")) return null;
    if (!tokEq(tokens[at_idx + 2], "(")) return null;
    if (tokens[at_idx + 3].kind != .string) return null;
    if (!tokEq(tokens[at_idx + 4], ",")) return null;
    if (tokens[at_idx + 5].kind != .ident) return null;
    if (!tokEq(tokens[at_idx + 6], ")")) return null;
    return at_idx + 6;
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
    if (isErrorEnumDeclStart(tokens, idx) or isValueEnumDeclStart(tokens, idx)) return true;

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
    if (tokens[eq_idx].line != tokens[idx].line) return false;
    if (isModernImportAssign(tokens, idx)) return false;
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
    if (at_idx + 3 >= line_end) return false;
    if (!tokEq(tokens[at_idx], "@")) return false;
    if (tokens[at_idx + 1].kind != .ident) return false;
    if (std.mem.eql(u8, tokens[at_idx + 1].lexeme, "env")) {
        return tokEq(tokens[at_idx + 2], "(");
    }
    if (std.mem.eql(u8, tokens[at_idx + 1].lexeme, "wasi")) {
        return tokEq(tokens[at_idx + 2], "(");
    }
    return false;
}

fn isValidImportName(name: []const u8) bool {
    if (name.len == 0 or name[0] == '.') return false;
    return (isValidDeclaredTypeName(name) or isLowerIdentName(name) or isReadonlyIdentName(name)) and !isReservedFuncName(name);
}

fn stringTokenBody(s: []const u8) ?[]const u8 {
    if (s.len < 2) return null;
    if (s[0] != '"' or s[s.len - 1] != '"') return null;
    return s[1 .. s.len - 1];
}

fn isValidImportFileName(name: []const u8, prefix: ImportPrefix) bool {
    if (!std.mem.endsWith(u8, name, ".do")) return false;
    const stem = name[0 .. name.len - 3];
    if (stem.len == 0) return false;
    return switch (prefix) {
        .dep => isValidDepFileStem(stem),
        .local, .std => isValidFlatFileStem(stem),
    };
}

fn isValidFlatFileStem(stem: []const u8) bool {
    var count: usize = 0;
    var start: usize = 0;
    while (start <= stem.len) {
        const dot_idx = std.mem.indexOfScalarPos(u8, stem, start, '.') orelse stem.len;
        if (!isValidPathSeg(stem[start..dot_idx])) return false;
        count += 1;
        if (dot_idx == stem.len) break;
        start = dot_idx + 1;
    }
    return count != 0;
}

fn isValidDepFileStem(stem: []const u8) bool {
    var count: usize = 0;
    var start: usize = 0;
    while (start <= stem.len) {
        const dot_idx = std.mem.indexOfScalarPos(u8, stem, start, '.') orelse stem.len;
        const seg = stem[start..dot_idx];
        if (!isAllDigits(seg) and !isValidPathSeg(seg)) return false;
        count += 1;
        if (dot_idx == stem.len) break;
        start = dot_idx + 1;
    }
    return count >= 2;
}

fn isAllDigits(seg: []const u8) bool {
    if (seg.len == 0) return false;
    for (seg) |ch| {
        if (ch < '0' or ch > '9') return false;
    }
    return true;
}

fn isValidPathSeg(seg: []const u8) bool {
    if (seg.len == 0) return false;
    if (seg[0] < 'a' or seg[0] > 'z') return false;
    if (seg[seg.len - 1] == '_') return false;

    var prev_underscore = false;
    for (seg[1..]) |ch| {
        if ((ch >= 'a' and ch <= 'z') or (ch >= '0' and ch <= '9')) {
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
    return true;
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
    if (std.mem.eql(u8, name, "Error")) return false;
    if (!std.ascii.isUpper(name[0])) return false;

    var i: usize = 1;
    while (i < name.len) : (i += 1) {
        if (std.ascii.isAlphabetic(name[i])) continue;
        if (std.ascii.isDigit(name[i])) continue;
        return false;
    }
    return true;
}

fn isBaseIntTypeName(name: []const u8) bool {
    const base_int_types = [_][]const u8{
        "i8",    "i16",   "i32", "i64",
        "u8",    "u16",   "u32", "u64",
        "isize", "usize",
    };
    for (base_int_types) |it| {
        if (std.mem.eql(u8, it, name)) return true;
    }
    return false;
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

fn isReservedFuncName(name: []const u8) bool {
    const public_name = if (name.len != 0 and name[0] == '.') name[1..] else name;
    if (std.mem.eql(u8, public_name, "start")) return true;
    if (isKeyword(public_name)) return true;
    const reserved = [_][]const u8{
        "is",          "and",         "or",          "not",         "recv",
        "get",         "set",         "eq",          "ne",          "lt",
        "le",          "gt",          "ge",          "add",         "sub",
        "mul",         "div",         "rem",         "len",         "put",
        "load_u8",     "load_i8",     "load_u16_le", "load_i16_le", "load_u32_le",
        "load_i32_le", "load_u64_le", "load_i64_le", "xor",         "shl",
        "shr",         "rotl",        "rotr",        "clz",         "ctz",
        "popcnt",      "abs",         "neg",         "sqrt",        "ceil",
        "floor",       "trunc",       "nearest",     "min",         "max",
        "copysign",
    };
    for (reserved) |it| {
        if (std.mem.eql(u8, it, public_name)) return true;
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
