const std = @import("std");
const lexer = @import("lexer.zig");

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

        i = findLineEndIdx(tokens, i) - 1;
    }

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

fn isFuncDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (isKeyword(tokens[idx].lexeme)) return false;
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
