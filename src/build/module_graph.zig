const std = @import("std");
const lexer = @import("lexer.zig");

pub const ImportPrefix = enum {
    local,
    dep,
    std,
};

pub const ImportRef = struct {
    alias_idx: usize,
    target: []const u8,
    file_path: []const u8,
    prefix: ImportPrefix,
};

pub const ModuleRecord = struct {
    path: []const u8,
    source: ?[]const u8,
    owns_source: bool,
    tokens: []const lexer.Token,
    owns_tokens: bool,
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

    pub fn find_module(self: *const ModuleGraph, path: []const u8) ?usize {
        for (self.modules, 0..) |module, idx| {
            if (std.mem.eql(u8, module.path, path)) return idx;
        }
        return null;
    }
};

pub const ParseImportFn = *const fn (tokens: []const lexer.Token, idx: usize) ?ImportRef;
pub const ResolvePathFn = *const fn (
    allocator: std.mem.Allocator,
    input_path: []const u8,
    import_ref: ImportRef,
    dep_root: []const u8,
) anyerror![]u8;
pub const IsNonHostImportFn = *const fn (tokens: []const lexer.Token, idx: usize) bool;
pub const ValidateSourceFn = *const fn (
    allocator: std.mem.Allocator,
    path: []const u8,
    source: []const u8,
    tokens: []const lexer.Token,
) anyerror!void;
pub const MarkErrorFn = *const fn (tokens: []const lexer.Token, idx: usize, err: anyerror) anyerror;

const Context = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    dep_root: []const u8,
    modules: std.ArrayList(ModuleRecord),
    stack: std.ArrayList([]const u8),
    parse_import: ParseImportFn,
    resolve_path: ResolvePathFn,
    is_non_host_import: IsNonHostImportFn,
    validate_source: ValidateSourceFn,
    mark_error: MarkErrorFn,

    fn init(
        io: std.Io,
        allocator: std.mem.Allocator,
        dep_root: []const u8,
        parse_import: ParseImportFn,
        resolve_path: ResolvePathFn,
        is_non_host_import: IsNonHostImportFn,
        validate_source: ValidateSourceFn,
        mark_error: MarkErrorFn,
    ) Context {
        return .{
            .io = io,
            .allocator = allocator,
            .dep_root = dep_root,
            .modules = std.ArrayList(ModuleRecord).empty,
            .stack = std.ArrayList([]const u8).empty,
            .parse_import = parse_import,
            .resolve_path = resolve_path,
            .is_non_host_import = is_non_host_import,
            .validate_source = validate_source,
            .mark_error = mark_error,
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

    fn find_module(self: *const Context, path: []const u8) ?usize {
        for (self.modules.items, 0..) |module, idx| {
            if (std.mem.eql(u8, module.path, path)) return idx;
        }
        return null;
    }

    fn is_loading(self: *const Context, path: []const u8) bool {
        for (self.stack.items) |loaded_path| {
            if (std.mem.eql(u8, loaded_path, path)) return true;
        }
        return false;
    }

    fn into_graph(self: *Context) !ModuleGraph {
        const modules = try self.modules.toOwnedSlice(self.allocator);
        self.stack.deinit(self.allocator);
        return .{
            .allocator = self.allocator,
            .dep_root = self.dep_root,
            .modules = modules,
        };
    }
};

pub fn load(
    io: std.Io,
    allocator: std.mem.Allocator,
    input_path: []const u8,
    tokens: []const lexer.Token,
    dep_root: []const u8,
    parse_import: ParseImportFn,
    resolve_path: ResolvePathFn,
    is_non_host_import: IsNonHostImportFn,
    validate_source: ValidateSourceFn,
    mark_error: MarkErrorFn,
) !ModuleGraph {
    var ctx = Context.init(
        io,
        allocator,
        dep_root,
        parse_import,
        resolve_path,
        is_non_host_import,
        validate_source,
        mark_error,
    );
    errdefer ctx.deinit();
    try load_module(&ctx, input_path, tokens, false);
    return ctx.into_graph();
}

fn load_module(
    ctx: *Context,
    path: []const u8,
    root_tokens: ?[]const lexer.Token,
    owns_root_tokens: bool,
) !void {
    if (ctx.find_module(path) != null) return;
    if (ctx.is_loading(path)) return error.InvalidImportDecl;

    try ctx.stack.append(ctx.allocator, path);
    defer _ = ctx.stack.pop();

    var source_opt: ?[]const u8 = null;
    var loaded_tokens_opt: ?[]const lexer.Token = null;
    const tokens = if (root_tokens) |root| root else blk: {
        const source = std.Io.Dir.cwd().readFileAlloc(
            ctx.io,
            path,
            ctx.allocator,
            .limited(16 * 1024 * 1024),
        ) catch return error.InvalidImportDecl;
        source_opt = source;
        const loaded = lexer.tokenize(ctx.allocator, source) catch {
            ctx.allocator.free(source);
            return error.InvalidImportDecl;
        };
        loaded_tokens_opt = loaded;
        break :blk loaded;
    };

    const owns_tokens = if (root_tokens == null) true else owns_root_tokens;
    if (root_tokens == null) {
        errdefer {
            if (loaded_tokens_opt) |loaded| ctx.allocator.free(loaded);
            if (source_opt) |source| ctx.allocator.free(source);
        }
    }
    if (source_opt) |source| {
        ctx.validate_source(ctx.allocator, path, source, tokens) catch return error.InvalidImportDecl;
    }

    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        const import_ref = ctx.parse_import(tokens, i) orelse {
            if (ctx.is_non_host_import(tokens, i)) {
                return ctx.mark_error(tokens, i, error.InvalidImportDecl);
            }
            continue;
        };

        const child_path = ctx.resolve_path(ctx.allocator, path, import_ref, ctx.dep_root) catch
            return ctx.mark_error(tokens, import_ref.alias_idx, error.InvalidImportDecl);
        defer ctx.allocator.free(child_path);

        load_module(ctx, child_path, null, false) catch
            return ctx.mark_error(tokens, import_ref.alias_idx, error.InvalidImportDecl);

        i = find_line_end(tokens, i) - 1;
    }

    const cache_path = try ctx.allocator.dupe(u8, path);
    errdefer ctx.allocator.free(cache_path);
    try ctx.modules.append(ctx.allocator, .{
        .path = cache_path,
        .source = source_opt,
        .owns_source = source_opt != null,
        .tokens = tokens,
        .owns_tokens = owns_tokens,
    });
}

fn find_line_end(tokens: []const lexer.Token, start_idx: usize) usize {
    if (start_idx >= tokens.len) return start_idx;
    const line = tokens[start_idx].line;
    var i = start_idx;
    while (i < tokens.len and tokens[i].line == line) : (i += 1) {}
    return i;
}
