const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema = @import("sema.zig");
const import_graph = @import("import_graph.zig");
const import_model = @import("import_model.zig");

pub const ModuleRecord = import_model.ModuleRecord;
pub const ModuleGraph = import_model.ModuleGraph;
const ImportRef = import_model.ImportRef;
const ImportPrefix = import_model.ImportPrefix;

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

pub const ErrorSite = struct {
    line: usize,
    col: usize,
};

var last_error_site: ?ErrorSite = null;

pub fn take_last_error_site() ?ErrorSite {
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
    var graph = try check_and_load(io, allocator, input_path, tokens, dep_root);
    defer graph.deinit();
}

pub fn check_and_load(
    io: std.Io,
    allocator: std.mem.Allocator,
    input_path: []const u8,
    tokens: []const lexer.Token,
    dep_root: []const u8,
) !ModuleGraph {
    last_error_site = null;
    var graph = try import_graph.load(
        io,
        allocator,
        input_path,
        tokens,
        dep_root,
        parse_local_import,
        resolve_path,
        is_non_host_import_assign,
        validate_loaded_source,
        mark_error_at,
    );
    errdefer graph.deinit();
    try resolve_imports(allocator, &graph);
    return graph;
}

fn parse_local_import(tokens: []const lexer.Token, idx: usize) ?ImportRef {
    if (idx >= tokens.len or tokens[idx].kind != .ident) return null;
    if (!is_top_level_decl_head(tokens, idx)) return null;

    const eq_idx = top_level_line_assign_idx(tokens, idx) orelse return null;
    const line_end = find_line_end_idx(tokens, idx);
    const at_idx = eq_idx + 1;
    const close_import = parse_lib_import_close(tokens, at_idx, line_end) orelse return null;

    var file_path = string_token_body(tokens[at_idx + 3].lexeme) orelse return null;
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

    if (!is_valid_import_file_name(file_path, prefix)) return null;
    if (!is_valid_import_name(target)) return null;
    if (close_import + 1 != line_end) return null;

    return .{
        .alias_idx = idx,
        .target = target,
        .file_path = file_path,
        .prefix = prefix,
    };
}

fn resolve_path(
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

fn validate_loaded_source(
    allocator: std.mem.Allocator,
    path: []const u8,
    source: []const u8,
    tokens: []const lexer.Token,
) !void {
    _ = path;
    var program = parser.parse_program(allocator, tokens, source.len) catch return error.InvalidImportDecl;
    defer program.deinit(allocator);
    sema.check_program(allocator, program, tokens) catch return error.InvalidImportDecl;
}

fn resolve_imports(allocator: std.mem.Allocator, graph: *const ModuleGraph) !void {
    for (graph.modules) |module| {
        try resolve_module_imports(allocator, graph, module.path, module.tokens);
    }
}

fn resolve_module_imports(
    allocator: std.mem.Allocator,
    graph: *const ModuleGraph,
    path: []const u8,
    tokens: []const lexer.Token,
) !void {
    var imported_func_shapes = std.ArrayList(FuncShape).empty;
    defer {
        free_func_shape_items(allocator, imported_func_shapes.items);
        imported_func_shapes.deinit(allocator);
    }
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        const import_ref = parse_local_import(tokens, i) orelse {
            if (is_non_host_import_assign(tokens, i)) {
                return mark_error_at(tokens, i, error.InvalidImportDecl);
            }
            continue;
        };
        const child_path = resolve_path(allocator, path, import_ref, graph.dep_root) catch
            return mark_error_at(tokens, import_ref.alias_idx, error.InvalidImportDecl);
        defer allocator.free(child_path);

        const child_idx = graph.find_module(child_path) orelse
            return mark_error_at(tokens, import_ref.alias_idx, error.InvalidImportDecl);
        const child_tokens = graph.modules[child_idx].tokens;
        const target_kind = find_public_decl_kind(child_tokens, import_ref.target) orelse
            return mark_error_at(tokens, import_ref.alias_idx, error.InvalidImportDecl);
        if (!alias_matches_kind(tokens[import_ref.alias_idx].lexeme, target_kind)) {
            return mark_error_at(tokens, import_ref.alias_idx, error.InvalidImportDecl);
        }
        if (is_type_like_kind(target_kind) and has_type_name_conflict(tokens, import_ref.alias_idx)) {
            return mark_error_at(tokens, import_ref.alias_idx, error.DuplicateTypeDeclName);
        }
        if (is_type_like_kind(target_kind)) {
            try check_imported_private_field_ctors(allocator, tokens, import_ref, child_tokens);
            try check_imported_type_value_exprs(allocator, tokens, import_ref.alias_idx);
            try check_imported_std_container_direct_access(tokens, import_ref);
        }
        if (target_kind == .func) {
            try check_imported_func_calls(allocator, tokens, import_ref, child_tokens);
            try append_imported_alias_func_shapes(
                allocator,
                &imported_func_shapes,
                import_ref.alias_idx,
                tokens[import_ref.alias_idx].lexeme,
                import_ref.target,
                child_tokens,
            );
        }

        i = find_line_end_idx(tokens, i) - 1;
    }

    try check_imported_function_value_resolution(allocator, tokens, imported_func_shapes.items);
    try check_imported_defer_stmts(allocator, tokens, imported_func_shapes.items);
}

fn check_imported_private_field_ctors(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    import_ref: ImportRef,
    child_tokens: []const lexer.Token,
) !void {
    var private_fields = std.ArrayList(PrivateField).empty;
    defer private_fields.deinit(allocator);

    try collect_private_struct_fields(allocator, &private_fields, child_tokens, import_ref.target);
    if (private_fields.items.len == 0) return;
    const has_required_private = has_required_private_field(private_fields.items);

    const alias = tokens[import_ref.alias_idx].lexeme;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, tokens[i].lexeme, alias)) continue;
        const open_brace = type_ctor_open_after_alias(tokens, i) orelse continue;
        if (is_return_type_before_func_body(tokens, i, open_brace)) continue;
        if (is_top_level_decl_head(tokens, i) and is_type_decl_start(tokens, i)) continue;

        const close_brace = find_matching(tokens, open_brace, "{", "}") catch
            return mark_error_at(tokens, i, error.InvalidStructLiteral);
        if (has_required_private) return mark_error_at(tokens, i, error.InvalidStructLiteral);
        if (find_private_field_init(tokens, open_brace + 1, close_brace, private_fields.items)) |bad_idx| {
            return mark_error_at(tokens, bad_idx, error.InvalidStructLiteral);
        }
    }

    try check_imported_private_field_inferred_ctors(tokens, import_ref.alias_idx, private_fields.items, has_required_private);
    try check_imported_private_field_path_access(tokens, import_ref, private_fields.items);
}

fn has_required_private_field(fields: []const PrivateField) bool {
    for (fields) |field| {
        if (!field.has_default) return true;
    }
    return false;
}

fn check_imported_type_value_exprs(allocator: std.mem.Allocator, tokens: []const lexer.Token, alias_idx: usize) !void {
    const alias = tokens[alias_idx].lexeme;
    var program = parser.parse_program(allocator, tokens, tokens.len) catch
        return mark_error_at(tokens, alias_idx, error.InvalidImportDecl);
    defer program.deinit(allocator);

    for (program.expr_nodes) |node| {
        if (node.kind != .ident) continue;
        const tok = tokens[node.start_tok];
        if (!std.mem.eql(u8, tok.lexeme, alias)) continue;
        return mark_error_at(tokens, node.start_tok, error.InvalidTypeRef);
    }
}

fn is_type_constructor_expr(tokens: []const lexer.Token, start_idx: usize) bool {
    return type_ctor_open_after_alias(tokens, start_idx) != null;
}

fn type_ctor_open_after_alias(tokens: []const lexer.Token, start_idx: usize) ?usize {
    var idx = start_idx + 1;
    if (idx < tokens.len and tok_eq(tokens[idx], "<")) {
        const close_angle = find_matching(tokens, idx, "<", ">") catch return null;
        idx = close_angle + 1;
    }
    if (idx < tokens.len and tok_eq(tokens[idx], "{")) return idx;
    return null;
}

fn is_return_type_before_func_body(tokens: []const lexer.Token, type_idx: usize, open_brace: usize) bool {
    if (open_brace == 0 or tokens[open_brace].line != tokens[type_idx].line) return false;
    if (tokens[open_brace - 1].line != tokens[type_idx].line) return false;
    var i = type_idx;
    while (i > 0) {
        i -= 1;
        if (tokens[i].line != tokens[type_idx].line) return false;
        if (is_return_arrow_at(tokens, i)) return true;
    }
    return false;
}

const BraceRange = struct { open: usize, close: usize };

fn wasi_record_fields_range(tokens: []const lexer.Token, name_idx: usize) ?BraceRange {
    if (name_idx + 5 >= tokens.len) return null;
    if (!tok_eq(tokens[name_idx + 1], "=") or !tok_eq(tokens[name_idx + 2], "@")) return null;
    if (tokens[name_idx + 3].kind != .ident) return null;
    const kind = tokens[name_idx + 3].lexeme;
    if (!std.mem.eql(u8, kind, "wasi_resource") and !std.mem.eql(u8, kind, "wasi_record")) return null;
    if (!tok_eq(tokens[name_idx + 4], "(")) return null;
    const close_call = find_matching(tokens, name_idx + 4, "(", ")") catch return null;
    var j = name_idx + 5;
    while (j < close_call) : (j += 1) {
        if (!tok_eq(tokens[j], "{")) continue;
        const close_brace = find_matching(tokens, j, "{", "}") catch return null;
        return .{ .open = j, .close = close_brace };
    }
    return null;
}

fn collect_private_struct_fields(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(PrivateField),
    tokens: []const lexer.Token,
    target: []const u8,
) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!is_top_level_decl_head(tokens, i)) continue;
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, tokens[i].lexeme, target)) continue;
        if (is_private_decl_name(tokens[i].lexeme)) continue;

        // Classic: Name { fields }
        if (tok_eq(tokens[i + 1], "{")) {
            const close_brace = find_matching(tokens, i + 1, "{", "}") catch return;
            try collect_private_field_names(allocator, out, tokens, i + 2, close_brace);
            return;
        }

        // Declarative: Name = @wasi_resource|wasi_record("…", { fields })
        if (wasi_record_fields_range(tokens, i)) |fields| {
            try collect_private_field_names(allocator, out, tokens, fields.open + 1, fields.close);
            return;
        }
    }
}

fn collect_private_field_names(
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
            tokens[i].kind == .ident and is_private_decl_name(tokens[i].lexeme))
        {
            const line_end = @min(find_line_end_idx(tokens, i), end_idx);
            try out.append(allocator, .{
                .name = tokens[i].lexeme[1..],
                .has_default = find_top_level_assign_eq_on_line(tokens, i + 1, line_end) != null,
            });
        }

        if (tok_eq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tok_eq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tok_eq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
    }
}

fn check_imported_private_field_inferred_ctors(
    tokens: []const lexer.Token,
    alias_idx: usize,
    private_fields: []const PrivateField,
    has_required_private: bool,
) !void {
    const alias = tokens[alias_idx].lexeme;
    var line_start: usize = 0;
    while (line_start < tokens.len) {
        const line_end = find_line_end_idx(tokens, line_start);
        if (find_direct_alias_inferred_ctor(tokens, line_start, line_end, alias)) |dot_idx| {
            if (has_required_private) return mark_error_at(tokens, dot_idx, error.InvalidStructLiteral);
            const open_brace = dot_idx + 1;
            const close_brace = find_matching(tokens, open_brace, "{", "}") catch
                return mark_error_at(tokens, dot_idx, error.InvalidStructLiteral);
            if (find_private_field_init(tokens, open_brace + 1, close_brace, private_fields)) |bad_idx| {
                return mark_error_at(tokens, bad_idx, error.InvalidStructLiteral);
            }
        }
        line_start = line_end;
    }
}

fn check_imported_private_field_path_access(
    tokens: []const lexer.Token,
    import_ref: ImportRef,
    private_fields: []const PrivateField,
) !void {
    const alias = tokens[import_ref.alias_idx].lexeme;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tok_eq(tokens[i], "get") and !tok_eq(tokens[i], "set")) continue;
        if (i == 0 or !tok_eq(tokens[i - 1], "@") or tokens[i - 1].line != tokens[i].line) continue;
        if (i + 1 >= tokens.len or !tok_eq(tokens[i + 1], "(")) continue;

        const close_paren = find_matching(tokens, i + 1, "(", ")") catch continue;
        const first_start = i + 2;
        const first_end = find_top_level_arg_end(tokens, first_start, close_paren);
        if (first_end != first_start + 1 or tokens[first_start].kind != .ident) {
            i = close_paren;
            continue;
        }
        if (!value_has_imported_type_alias(tokens, i, tokens[first_start].lexeme, alias)) {
            i = close_paren;
            continue;
        }

        var arg_start = first_end;
        while (arg_start < close_paren) {
            if (!tok_eq(tokens[arg_start], ",")) break;
            arg_start += 1;
            const arg_end = find_top_level_arg_end(tokens, arg_start, close_paren);
            if (arg_end == arg_start + 1 and tokens[arg_start].kind == .ident and is_private_path_field(private_fields, tokens[arg_start].lexeme)) {
                return mark_error_at(tokens, arg_start, error.InvalidPathAccess);
            }
            arg_start = arg_end;
        }

        i = close_paren;
    }
}

fn is_private_path_field(private_fields: []const PrivateField, name: []const u8) bool {
    if (name.len < 2 or name[0] != '.') return false;
    return is_private_field_name(private_fields, name[1..]);
}

fn find_private_field_init(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    private_fields: []const PrivateField,
) ?usize {
    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !is_top_level_comma_any(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i and tokens[seg_start].kind == .ident and is_private_field_name(private_fields, tokens[seg_start].lexeme)) {
            return seg_start;
        }
        seg_start = i + 1;
    }
    return null;
}

fn is_private_field_name(private_fields: []const PrivateField, name: []const u8) bool {
    for (private_fields) |field| {
        if (std.mem.eql(u8, field.name, name)) return true;
    }
    return false;
}

fn find_direct_alias_inferred_ctor(
    tokens: []const lexer.Token,
    line_start: usize,
    line_end: usize,
    alias: []const u8,
) ?usize {
    if (line_start + 3 >= line_end) return null;
    if (tokens[line_start].kind != .ident) return null;
    if (tokens[line_start + 1].kind != .ident) return null;
    if (!std.mem.eql(u8, tokens[line_start + 1].lexeme, alias)) return null;

    const eq_idx = find_top_level_eq(tokens, line_start + 2, line_end) orelse return null;
    if (eq_idx + 2 >= line_end) return null;
    if (!tok_eq(tokens[eq_idx + 1], ".") or !tok_eq(tokens[eq_idx + 2], "{")) return null;
    return eq_idx + 1;
}

fn check_imported_std_container_direct_access(tokens: []const lexer.Token, import_ref: ImportRef) !void {
    if (import_ref.prefix != .std) return;
    if (!std.mem.eql(u8, import_ref.target, "List") and !std.mem.eql(u8, import_ref.target, "HashMap")) return;

    const alias = tokens[import_ref.alias_idx].lexeme;
    try check_imported_std_container_direct_loop(tokens, alias);
    try check_imported_std_container_direct_path(tokens, alias);
}

fn check_imported_std_container_direct_loop(tokens: []const lexer.Token, alias: []const u8) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tok_eq(tokens[i], "loop")) continue;
        const line_end = find_line_end_idx(tokens, i);
        const eq_idx = find_top_level_eq(tokens, i + 1, line_end) orelse continue;
        if (loop_bind_count(tokens, i + 1, eq_idx) < 2) continue;
        const source_idx = eq_idx + 1;
        if (source_idx >= line_end or tokens[source_idx].kind != .ident) continue;
        if (!value_has_nearest_type_alias(tokens, i, tokens[source_idx].lexeme, alias)) continue;
        return mark_error_at(tokens, source_idx, error.InvalidLoopSource);
    }
}

fn check_imported_std_container_direct_path(tokens: []const lexer.Token, alias: []const u8) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tok_eq(tokens[i], "get") and !tok_eq(tokens[i], "set")) continue;
        if (i + 1 >= tokens.len or !tok_eq(tokens[i + 1], "(")) continue;
        const close_paren = find_matching(tokens, i + 1, "(", ")") catch continue;
        const first_arg = first_arg_start(i + 2, close_paren) orelse continue;
        if (tokens[first_arg].kind != .ident) continue;
        if (!value_has_nearest_type_alias(tokens, i, tokens[first_arg].lexeme, alias)) {
            i = close_paren;
            continue;
        }
        return mark_error_at(tokens, first_arg, error.InvalidPathAccess);
    }
}

fn loop_bind_count(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    var count: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokens[i].kind == .ident or tok_eq(tokens[i], "_")) count += 1;
    }
    return count;
}

fn first_arg_start(start_idx: usize, end_idx: usize) ?usize {
    if (start_idx >= end_idx) return null;
    return start_idx;
}

fn value_has_nearest_type_alias(tokens: []const lexer.Token, before_idx: usize, name: []const u8, alias: []const u8) bool {
    var skip_depth: usize = 0;
    var i = before_idx;
    while (i > 0) {
        i -= 1;

        if (tok_eq(tokens[i], "}")) {
            skip_depth += 1;
            continue;
        }
        if (tok_eq(tokens[i], "{")) {
            if (skip_depth > 0) skip_depth -= 1;
            continue;
        }
        if (skip_depth != 0) continue;
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, tokens[i].lexeme, name)) continue;

        const line_end = find_line_end_idx(tokens, i);
        const eq_idx = find_top_level_eq(tokens, i + 1, line_end) orelse continue;
        if (eq_idx > i + 1 and tokens[i + 1].kind == .ident and std.mem.eql(u8, tokens[i + 1].lexeme, alias)) return true;
        if (eq_idx + 1 < line_end and tokens[eq_idx + 1].kind == .ident and std.mem.eql(u8, tokens[eq_idx + 1].lexeme, alias)) return true;
    }
    return false;
}

fn value_has_imported_type_alias(tokens: []const lexer.Token, before_idx: usize, name: []const u8, alias: []const u8) bool {
    if (value_has_nearest_type_alias(tokens, before_idx, name, alias)) return true;
    return enclosing_func_param_has_type_alias(tokens, before_idx, name, alias);
}

fn enclosing_func_param_has_type_alias(tokens: []const lexer.Token, before_idx: usize, name: []const u8, alias: []const u8) bool {
    var skip_depth: usize = 0;
    var i = before_idx;
    while (i > 0) {
        i -= 1;
        if (tok_eq(tokens[i], "}")) {
            skip_depth += 1;
            continue;
        }
        if (!tok_eq(tokens[i], "{")) continue;
        if (skip_depth > 0) {
            skip_depth -= 1;
            continue;
        }
        return func_param_has_type_alias_before_body(tokens, i, name, alias);
    }
    return false;
}

fn func_param_has_type_alias_before_body(tokens: []const lexer.Token, body_open_idx: usize, name: []const u8, alias: []const u8) bool {
    const line_start = line_start_idx(tokens, body_open_idx);
    if (line_start >= body_open_idx) return false;
    if (!is_func_decl_start(tokens, line_start)) return false;
    const close_params = find_matching(tokens, line_start + 1, "(", ")") catch return false;
    if (close_params >= body_open_idx) return false;
    return param_list_has_type_alias(tokens, line_start + 2, close_params, name, alias);
}

fn param_list_has_type_alias(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, name: []const u8, alias: []const u8) bool {
    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !is_top_level_comma_any(tokens, i, start_idx, end_idx)) continue;
        if (seg_start + 1 < i and tokens[seg_start].kind == .ident and std.mem.eql(u8, tokens[seg_start].lexeme, name)) {
            var type_start = seg_start + 1;
            if (type_start < i and is_spread_token(tokens[type_start])) type_start += 1;
            if (type_start < i and tokens[type_start].kind == .ident and std.mem.eql(u8, tokens[type_start].lexeme, alias)) return true;
        }
        seg_start = i + 1;
    }
    return false;
}

fn find_top_level_arg_end(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tok_eq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tok_eq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tok_eq(tokens[i], ",")) return i;
    }
    return end_idx;
}

fn find_top_level_eq(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i: usize = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tok_eq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tok_eq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tok_eq(tokens[i], "=")) return i;
    }
    return null;
}

fn import_path_text(
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
        if (tok_eq(tokens[i], "/")) {
            try out.append(allocator, '/');
        }
    }
    return out.toOwnedSlice(allocator);
}

fn find_public_decl_kind(tokens: []const lexer.Token, target: []const u8) ?DeclKind {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!is_top_level_decl_head(tokens, i)) continue;
        if (tokens[i].kind != .ident) continue;
        if (is_modern_import_assign(tokens, i)) continue;
        if (find_public_enum_member_kind(tokens, i, target)) |kind| return kind;
        if (!std.mem.eql(u8, tokens[i].lexeme, target)) continue;
        if (is_private_decl_name(tokens[i].lexeme)) continue;

        if (is_func_decl_start(tokens, i)) return .func;
        if (is_error_enum_decl_start(tokens, i)) return .error_type;
        if (is_value_enum_decl_start(tokens, i)) return .value_enum_type;
        if (is_valid_declared_type_name(tokens[i].lexeme) and is_type_decl_start(tokens, i)) return .type;
        if (is_top_value_decl_start(tokens, i)) {
            return if (is_readonly_ident_name(tokens[i].lexeme)) .const_value else .var_value;
        }
    }
    return null;
}

fn check_imported_func_calls(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    import_ref: ImportRef,
    child_tokens: []const lexer.Token,
) !void {
    var program = parser.parse_program(allocator, child_tokens, child_tokens.len) catch
        return mark_error_at(tokens, import_ref.alias_idx, error.InvalidImportDecl);
    defer program.deinit(allocator);

    const alias = tokens[import_ref.alias_idx].lexeme;
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, tokens[i].lexeme, alias)) continue;
        if (i + 1 >= tokens.len or !tok_eq(tokens[i + 1], "(")) continue;
        if (depth_brace == 0 and is_func_decl_start(tokens, i)) continue;

        const close_paren = find_matching(tokens, i + 1, "(", ")") catch
            return mark_error_at(tokens, i, error.InvalidCallArgList);
        const call_args = try parse_import_call_args(allocator, tokens, i + 2, close_paren);
        defer allocator.free(call_args.shapes);

        if (!has_compatible_func_sig(program.func_sigs, import_ref.target, call_args.shapes.len)) {
            return mark_error_at(tokens, i, error.NoMatchingCall);
        }
        if (call_args.spread_idx) |spread_idx| {
            if (!has_compatible_spread_func_sig(program.func_sigs, import_ref.target, call_args.shapes.len, spread_idx)) {
                return mark_error_at(tokens, call_args.shapes[spread_idx].spread, error.InvalidCallArgList);
            }
        }
        i = close_paren;
    }
}

fn has_compatible_func_sig(func_sigs: []const parser.FuncSig, target: []const u8, arg_count: usize) bool {
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

fn has_compatible_spread_func_sig(func_sigs: []const parser.FuncSig, target: []const u8, arg_count: usize, spread_idx: usize) bool {
    for (func_sigs) |sig| {
        if (!std.mem.eql(u8, sig.name, target)) continue;
        if (!call_arity_compatible_with_sig(sig, arg_count)) continue;
        if (sig.param_max != null) continue;
        if (spread_idx < sig.param_min) continue;
        return true;
    }
    return false;
}

fn call_arity_compatible_with_sig(sig: parser.FuncSig, arg_count: usize) bool {
    if (sig.param_min > arg_count) return false;
    if (sig.param_max) |max_count| return arg_count <= max_count;
    return true;
}

fn check_imported_function_value_resolution(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    imported_funcs: []const FuncShape,
) !void {
    if (imported_funcs.len == 0) return;

    const local_funcs = try collect_func_shapes(allocator, tokens);
    defer free_func_shapes(allocator, local_funcs);

    try check_imported_func_signature_conflicts(tokens, local_funcs, imported_funcs);

    var program = parser.parse_program(allocator, tokens, tokens.len) catch
        return mark_error_at(tokens, 0, error.InvalidImportDecl);
    defer program.deinit(allocator);

    try check_imported_multi_return_positions(tokens, program, local_funcs, imported_funcs);

    var calls = std.ArrayList(CallShape).empty;
    defer {
        for (calls.items) |call| allocator.free(call.arg_shapes);
        calls.deinit(allocator);
    }

    try collect_call_shapes_from_program(allocator, program, tokens, &calls);
    for (calls.items) |call| {
        if (!call_uses_imported_function_value(tokens, local_funcs, imported_funcs, call)) continue;
        if (try count_compatible_function_value_candidates(allocator, tokens, local_funcs, imported_funcs, call) != 1) {
            return mark_error_at(tokens, call.start_idx, error.NoMatchingCall);
        }
    }

    try check_bare_imported_overloaded_func_assign(tokens, local_funcs, imported_funcs);
}

fn check_imported_defer_stmts(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    imported_funcs: []const FuncShape,
) !void {
    if (imported_funcs.len == 0) return;

    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tok_eq(tokens[i], "defer")) continue;
        const call_idx = i + 1;
        if (call_idx >= tokens.len) return mark_error_at(tokens, i, error.NoMatchingCall);
        if (tok_eq(tokens[call_idx], "{")) {
            const close_block = find_matching(tokens, call_idx, "{", "}") catch return mark_error_at(tokens, call_idx, error.NoMatchingCall);
            i = close_block;
            continue;
        }
        if (tokens[call_idx].kind != .ident) continue;
        if (call_idx + 1 >= tokens.len or !tok_eq(tokens[call_idx + 1], "(")) continue;

        const name = tokens[call_idx].lexeme;
        if (!has_known_func_candidate(imported_funcs, name)) continue;
        const line_end = find_line_end_idx(tokens, call_idx);
        const close_paren = find_matching(tokens, call_idx + 1, "(", ")") catch return mark_error_at(tokens, call_idx, error.NoMatchingCall);
        if (close_paren + 1 != line_end) return mark_error_at(tokens, call_idx, error.NoMatchingCall);

        const args = try parse_call_arg_shapes(allocator, tokens, call_idx + 2, close_paren);
        defer allocator.free(args);

        var saw_func_candidate = false;
        for (imported_funcs) |func| {
            if (!std.mem.eql(u8, func.name, name)) continue;
            if (!call_arity_compatible_with_func(func, args.len)) continue;
            saw_func_candidate = true;
            if (func_return_is_nil(func.return_type)) return;
        }
        if (saw_func_candidate) return mark_error_at(tokens, call_idx, error.NoMatchingCall);
    }
}

fn func_return_is_nil(return_type: ?[]const u8) bool {
    const ty = return_type orelse return true;
    return std.mem.eql(u8, ty, "nil");
}

fn check_bare_imported_overloaded_func_assign(
    tokens: []const lexer.Token,
    local_funcs: []const FuncShape,
    imported_funcs: []const FuncShape,
) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tok_eq(tokens[i], "=") or is_non_assign_equal(tokens, i)) continue;

        const line_start = line_start_idx(tokens, i);
        const line_end = find_line_end_idx(tokens, i);
        const rhs_start = i + 1;
        if (rhs_start + 1 != line_end) continue;
        if (tokens[rhs_start].kind != .ident) continue;

        const rhs_name = tokens[rhs_start].lexeme;
        if (!has_known_func_candidate(imported_funcs, rhs_name)) continue;
        if (count_funcs_by_name(local_funcs, imported_funcs, rhs_name) < 2) continue;
        if (line_start + 1 != i) continue;
        if (tokens[line_start].kind != .ident) continue;
        return mark_error_at(tokens, rhs_start, error.NoMatchingCall);
    }
}

fn check_imported_multi_return_positions(
    tokens: []const lexer.Token,
    program: parser.Program,
    local_funcs: []const FuncShape,
    imported_funcs: []const FuncShape,
) !void {
    for (program.value_exprs) |site| {
        if (site.expected_arity <= 1) continue;

        const resolved = root_expr_return_arity(program, local_funcs, imported_funcs, site.root_expr_idx);
        const allowed = switch (resolved) {
            .unknown => true,
            .ambiguous => false,
            .arity => |arity| arity == site.expected_arity,
        };
        if (allowed) continue;

        const start_tok = root_expr_start_tok(program, site.root_expr_idx);
        const err = switch (site.context) {
            .assign => error.InvalidAssignExpr,
            .rhs => error.MultiReturnInSingleValuePosition,
            .return_value => error.InvalidReturnStmt,
            .single => error.MultiReturnInSingleValuePosition,
        };
        return mark_error_at(tokens, start_tok, err);
    }

    for (program.condition_exprs) |site| {
        const call_site = find_direct_call_at_root(program, site.root_expr_idx) orelse continue;
        const resolved = resolve_func_return_arity(
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
                return mark_error_at(tokens, call_site.start_tok_idx, err);
            },
            .ambiguous => return mark_error_at(tokens, call_site.start_tok_idx, error.AmbiguousConditionCallReturnArity),
        }
    }

    for (program.expr_nodes) |node| {
        switch (node.kind) {
            .call => {},
            else => continue,
        }

        const resolved = resolve_func_return_arity(
            local_funcs,
            imported_funcs,
            node.data.call.func_name,
            node.data.call.arg_count,
        );
        const arity = switch (resolved) {
            .unknown => continue,
            .ambiguous => return mark_error_at(tokens, node.start_tok, error.AmbiguousConditionCallReturnArity),
            .arity => |value| value,
        };
        if (arity <= 1) continue;

        const call_start = node.start_tok;
        if (value_expr_allows_arity_at(program, call_start, arity)) continue;
        return mark_error_at(tokens, call_start, error.MultiReturnInSingleValuePosition);
    }

    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (!is_call_head(tokens, i)) continue;
        if (is_top_level_decl_head(tokens, i) and is_func_decl_start(tokens, i)) continue;
        if (is_func_constraint_head(tokens, i)) continue;

        const close_paren = find_matching(tokens, i + 1, "(", ")") catch
            return mark_error_at(tokens, i + 1, error.InvalidCallArgList);
        const arg_count = count_call_args(tokens, i + 2, close_paren) catch
            return mark_error_at(tokens, i + 1, error.InvalidCallArgList);

        const resolved = resolve_func_return_arity(local_funcs, imported_funcs, tokens[i].lexeme, arg_count);
        const arity = switch (resolved) {
            .unknown => continue,
            .ambiguous => return mark_error_at(tokens, i, error.AmbiguousConditionCallReturnArity),
            .arity => |value| value,
        };
        if (arity <= 1) continue;
        if (value_expr_allows_arity_at(program, i, arity)) continue;

        return mark_error_at(tokens, i, error.MultiReturnInSingleValuePosition);
    }
}

fn root_expr_return_arity(
    program: parser.Program,
    local_funcs: []const FuncShape,
    imported_funcs: []const FuncShape,
    root_idx: usize,
) ReturnArityResolve {
    if (root_idx >= program.expr_nodes.len) return .{ .arity = 1 };
    const node = program.expr_nodes[root_idx];

    return switch (node.kind) {
        .paren => root_expr_return_arity(program, local_funcs, imported_funcs, node.data.child),
        .call => resolve_func_return_arity(
            local_funcs,
            imported_funcs,
            node.data.call.func_name,
            node.data.call.arg_count,
        ),
        else => .{ .arity = 1 },
    };
}

fn resolve_func_return_arity(
    local_funcs: []const FuncShape,
    imported_funcs: []const FuncShape,
    name: []const u8,
    arg_count: usize,
) ReturnArityResolve {
    var matched_arity: ?usize = null;

    if (!merge_func_return_arity(local_funcs, name, arg_count, &matched_arity)) return .ambiguous;
    if (!merge_func_return_arity(imported_funcs, name, arg_count, &matched_arity)) return .ambiguous;

    if (matched_arity) |arity| return .{ .arity = arity };
    return .unknown;
}

fn merge_func_return_arity(
    funcs: []const FuncShape,
    name: []const u8,
    arg_count: usize,
    matched_arity: *?usize,
) bool {
    for (funcs) |func| {
        if (!std.mem.eql(u8, func.name, name)) continue;
        if (!call_arity_compatible_with_func(func, arg_count)) continue;

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

fn find_direct_call_at_root(program: parser.Program, root_idx: usize) ?DirectCallSite {
    if (root_idx >= program.expr_nodes.len) return null;
    const node = program.expr_nodes[root_idx];

    return switch (node.kind) {
        .call => .{
            .call = node.data.call,
            .start_tok_idx = node.start_tok,
        },
        .paren => find_direct_call_at_root(program, node.data.child),
        else => null,
    };
}

fn root_expr_start_tok(program: parser.Program, root_idx: usize) usize {
    if (root_idx >= program.expr_nodes.len) return 0;
    const node = program.expr_nodes[root_idx];
    return switch (node.kind) {
        .paren => root_expr_start_tok(program, node.data.child),
        else => node.start_tok,
    };
}

fn value_expr_allows_arity_at(program: parser.Program, start_tok: usize, arity: usize) bool {
    for (program.value_exprs) |site| {
        if (site.expected_arity != arity) continue;
        if (!root_expr_matches_call_start(program, site.root_expr_idx, start_tok)) continue;
        return true;
    }
    return false;
}

fn root_expr_matches_call_start(program: parser.Program, root_idx: usize, start_tok: usize) bool {
    if (root_idx >= program.expr_nodes.len) return false;
    const node = program.expr_nodes[root_idx];
    return switch (node.kind) {
        .paren => root_expr_matches_call_start(program, node.data.child, start_tok),
        .call => node.start_tok == start_tok,
        else => false,
    };
}

fn append_imported_alias_func_shapes(
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
        if (tok_eq(child_tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(child_tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!is_top_level_decl_head(child_tokens, i)) continue;
        if (!is_func_decl_start(child_tokens, i)) continue;

        const decl_name = child_tokens[i].lexeme;
        if (is_private_decl_name(decl_name)) continue;
        if (!std.mem.eql(u8, decl_name, target)) continue;

        const close_paren = find_matching(child_tokens, i + 1, "(", ")") catch continue;
        const params = try parse_func_param_shapes(allocator, child_tokens, i + 2, close_paren);
        const arity = parse_func_param_arity(child_tokens, i + 2, close_paren);
        const return_arity = parse_top_level_func_return_arity(child_tokens, close_paren + 1);
        try out.append(allocator, .{
            .name = alias,
            .start_idx = alias_idx,
            .param_shapes = params,
            .param_min = arity.param_min,
            .param_max = arity.param_max,
            .return_type = parse_top_level_func_return_type(child_tokens, close_paren + 1),
            .return_arity = return_arity,
            .is_generic = func_has_generic_signature_param(child_tokens, i, params),
        });
        i = close_paren;
    }
}

fn collect_func_shapes(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]FuncShape {
    var out = std.ArrayList(FuncShape).empty;
    errdefer {
        free_func_shape_items(allocator, out.items);
        out.deinit(allocator);
    }

    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!is_top_level_decl_head(tokens, i) or !is_func_decl_start(tokens, i)) continue;

        const close_paren = find_matching(tokens, i + 1, "(", ")") catch continue;
        const params = try parse_func_param_shapes(allocator, tokens, i + 2, close_paren);
        const arity = parse_func_param_arity(tokens, i + 2, close_paren);
        const return_arity = parse_top_level_func_return_arity(tokens, close_paren + 1);
        try out.append(allocator, .{
            .name = public_func_name(tokens[i].lexeme),
            .start_idx = i,
            .param_shapes = params,
            .param_min = arity.param_min,
            .param_max = arity.param_max,
            .return_type = parse_top_level_func_return_type(tokens, close_paren + 1),
            .return_arity = return_arity,
            .is_generic = func_has_generic_signature_param(tokens, i, params),
        });
        i = close_paren;
    }

    return out.toOwnedSlice(allocator);
}

fn free_func_shapes(allocator: std.mem.Allocator, funcs: []const FuncShape) void {
    free_func_shape_items(allocator, funcs);
    allocator.free(funcs);
}

fn free_func_shape_items(allocator: std.mem.Allocator, funcs: []const FuncShape) void {
    for (funcs) |shape| {
        free_func_param_shapes(allocator, shape.param_shapes);
    }
}

fn free_func_param_shapes(allocator: std.mem.Allocator, shapes: []const FuncParamShape) void {
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

fn check_imported_func_signature_conflicts(
    tokens: []const lexer.Token,
    local_funcs: []const FuncShape,
    imported_funcs: []const FuncShape,
) !void {
    for (imported_funcs, 0..) |imported, idx| {
        for (local_funcs) |local| {
            if (!func_signatures_conflict(imported, local)) continue;
            return mark_error_at(tokens, imported.start_idx, error.DuplicateFuncSignature);
        }
        for (imported_funcs[0..idx]) |prev| {
            if (!func_signatures_conflict(imported, prev)) continue;
            return mark_error_at(tokens, imported.start_idx, error.DuplicateFuncSignature);
        }
    }
}

fn func_signatures_conflict(a: FuncShape, b: FuncShape) bool {
    if (!std.mem.eql(u8, a.name, b.name)) return false;
    if (func_param_shapes_equal(a.param_shapes, b.param_shapes)) return true;
    if (a.param_shapes.len != b.param_shapes.len) return false;
    if (!a.is_generic and !b.is_generic) return false;
    return a.is_generic == b.is_generic;
}

fn func_has_generic_signature_param(tokens: []const lexer.Token, func_start_idx: usize, params: []const FuncParamShape) bool {
    for (params) |param| {
        const type_name = switch (param) {
            .value => |value_type| value_type orelse continue,
            .variadic => |value_type| value_type orelse continue,
            else => continue,
        };
        if (!is_func_type_param(tokens, func_start_idx, type_name)) continue;
        if (type_constraint_is_concrete_function_type(tokens, func_start_idx, type_name)) continue;
        return true;
    }
    return false;
}

fn func_signatures_equal(a: FuncShape, b: FuncShape) bool {
    if (!std.mem.eql(u8, a.name, b.name)) return false;
    return func_param_shapes_equal(a.param_shapes, b.param_shapes);
}

fn func_param_shapes_equal(a: []const FuncParamShape, b: []const FuncParamShape) bool {
    if (a.len != b.len) return false;
    for (a, 0..) |item, idx| {
        if (!func_param_shape_equal(item, b[idx])) return false;
    }
    return true;
}

fn func_param_shape_equal(a: FuncParamShape, b: FuncParamShape) bool {
    return switch (a) {
        .other => switch (b) {
            .other => true,
            else => false,
        },
        .value => |a_type| switch (b) {
            .value => |b_type| optional_type_name_equal(a_type, b_type),
            else => false,
        },
        .variadic => |a_type| switch (b) {
            .variadic => |b_type| optional_type_name_equal(a_type, b_type),
            else => false,
        },
        .func => |a_func| switch (b) {
            .func => |b_func| func_type_shape_equal(a_func, b_func),
            else => false,
        },
    };
}

fn func_type_shape_equal(a: FuncTypeShape, b: FuncTypeShape) bool {
    if (a.param_count != b.param_count) return false;
    if (a.param_types.len != b.param_types.len) return false;
    for (a.param_types, 0..) |a_type, idx| {
        if (!optional_type_name_equal(a_type, b.param_types[idx])) return false;
    }
    return optional_type_name_equal(a.return_type, b.return_type);
}

fn optional_type_name_equal(a: ?[]const u8, b: ?[]const u8) bool {
    if (a) |a_name| {
        const b_name = b orelse return false;
        return std.mem.eql(u8, a_name, b_name);
    }
    return b == null;
}

fn parse_func_param_shapes(
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
        if (i < end_idx and !is_top_level_comma_any(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            try out.append(allocator, try parse_func_param_shape(allocator, tokens, seg_start, i));
        }
        seg_start = i + 1;
    }

    return out.toOwnedSlice(allocator);
}

fn parse_func_param_shape(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) !FuncParamShape {
    if (start_idx + 1 >= end_idx) return .other;
    const type_start = if (is_spread_token(tokens[start_idx + 1])) start_idx + 2 else start_idx + 1;
    if (type_start >= end_idx) return .other;
    if (!tok_eq(tokens[type_start], "(")) {
        const type_name = try compact_type_name(allocator, tokens, type_start, end_idx);
        if (type_start != start_idx + 1) return .{ .variadic = type_name };
        return .{ .value = type_name };
    }

    const close_param_types = find_matching(tokens, type_start, "(", ")") catch return .other;
    if (close_param_types >= end_idx) return .other;
    if (!is_return_arrow_at(tokens, close_param_types + 1)) return .other;

    const param_types = try parse_type_name_list(allocator, tokens, type_start + 1, close_param_types);
    return .{ .func = .{
        .param_count = param_types.len,
        .param_types = param_types,
        .return_type = simple_type_name(tokens, close_param_types + 3, end_idx),
    } };
}

fn compact_type_name(
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

fn parse_func_param_arity(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) struct { param_min: usize, param_max: ?usize } {
    var min_count: usize = 0;
    var has_variadic = false;
    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !is_top_level_comma_any(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            if (seg_start + 1 < i and is_spread_token(tokens[seg_start + 1])) {
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

fn parse_type_name_list(
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
        if (i < end_idx and !is_top_level_comma_any(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            try out.append(allocator, simple_type_name(tokens, seg_start, i));
        }
        seg_start = i + 1;
    }
    return out.toOwnedSlice(allocator);
}

fn collect_call_shapes_from_program(
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
        if (!tok_eq(tokens[call_start + 1], "(")) continue;

        const args_start = call_start + 2;
        const args_end = node.end_tok - 1;
        const args = try parse_call_arg_shapes(allocator, tokens, args_start, args_end);
        try out.append(allocator, .{
            .name = tokens[call_start].lexeme,
            .start_idx = node.start_tok,
            .arg_shapes = args,
        });
    }
}

fn parse_call_arg_shapes(
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
        if (i < end_idx and !is_top_level_comma_any(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            if (is_spread_token(tokens[seg_start])) {
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

fn parse_import_call_args(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) !ImportCallArgs {
    const shapes = try parse_call_arg_shapes(allocator, tokens, start_idx, end_idx);
    errdefer allocator.free(shapes);

    return .{
        .shapes = shapes,
        .spread_idx = call_arg_spread_index(shapes),
    };
}

fn call_arg_spread_index(args: []const CallArgShape) ?usize {
    for (args, 0..) |arg, arg_idx| {
        if (arg == .spread) return arg_idx;
    }
    return null;
}

fn call_uses_imported_function_value(
    tokens: []const lexer.Token,
    local_funcs: []const FuncShape,
    imported_funcs: []const FuncShape,
    call: CallShape,
) bool {
    for (call.arg_shapes, 0..) |arg, arg_index| {
        if (arg != .ident) continue;
        const name = arg.ident;
        if (!has_known_func_candidate(imported_funcs, name)) continue;
        if (call_has_func_param_candidate_at_index(tokens, local_funcs, imported_funcs, call, arg_index)) return true;
    }
    return false;
}

fn call_has_func_param_candidate_at_index(
    tokens: []const lexer.Token,
    local_funcs: []const FuncShape,
    imported_funcs: []const FuncShape,
    call: CallShape,
    arg_index: usize,
) bool {
    for (local_funcs) |func| {
        if (!std.mem.eql(u8, func.name, call.name)) continue;
        if (!call_arity_compatible_with_func(func, call.arg_shapes.len)) continue;
        if (arg_index >= func.param_shapes.len) continue;
        if (func_param_shape_is_function_like(tokens, func, func.param_shapes[arg_index], true)) return true;
    }
    for (imported_funcs) |func| {
        if (!std.mem.eql(u8, func.name, call.name)) continue;
        if (!call_arity_compatible_with_func(func, call.arg_shapes.len)) continue;
        if (arg_index >= func.param_shapes.len) continue;
        if (func_param_shape_is_function_like(tokens, func, func.param_shapes[arg_index], false)) return true;
    }
    return false;
}

fn count_compatible_function_value_candidates(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    local_funcs: []const FuncShape,
    imported_funcs: []const FuncShape,
    call: CallShape,
) !usize {
    var count: usize = 0;
    for (local_funcs) |func| {
        if (!std.mem.eql(u8, func.name, call.name)) continue;
        if (!call_arity_compatible_with_func(func, call.arg_shapes.len)) continue;
        if (!(try function_value_args_match_func(allocator, tokens, local_funcs, imported_funcs, func, call, true))) continue;
        count += 1;
    }
    for (imported_funcs) |func| {
        if (!std.mem.eql(u8, func.name, call.name)) continue;
        if (!call_arity_compatible_with_func(func, call.arg_shapes.len)) continue;
        if (!(try function_value_args_match_func(allocator, tokens, local_funcs, imported_funcs, func, call, false))) continue;
        count += 1;
    }
    return count;
}

fn call_arity_compatible_with_func(func: FuncShape, arg_count: usize) bool {
    if (arg_count < func.param_min) return false;
    if (func.param_max) |max_count| return arg_count <= max_count;
    return true;
}

fn function_value_args_match_func(
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
        if (!has_known_func_candidate(local_funcs, name) and !has_known_func_candidate(imported_funcs, name)) continue;
        if (arg_index >= func.param_shapes.len) return false;

        const target = try resolve_func_param_type_shape(allocator, tokens, func, func.param_shapes[arg_index], allow_named_constraints);
        defer free_resolved_func_type_shape(allocator, target);
        const target_func = if (target) |resolved| resolved.shape else continue;
        if (count_funcs_matching_target(local_funcs, imported_funcs, name, target_func) != 1) return false;
    }
    return true;
}

fn func_param_shape_is_function_like(
    tokens: []const lexer.Token,
    func: FuncShape,
    param: FuncParamShape,
    allow_named_constraints: bool,
) bool {
    return switch (param) {
        .func => true,
        .value => |type_name| if (allow_named_constraints) blk: {
            const name = type_name orelse break :blk false;
            break :blk type_constraint_is_concrete_function_type(tokens, func.start_idx, name);
        } else false,
        .variadic => |type_name| if (allow_named_constraints) blk: {
            const name = type_name orelse break :blk false;
            break :blk type_constraint_is_concrete_function_type(tokens, func.start_idx, name);
        } else false,
        else => false,
    };
}

fn resolve_func_param_type_shape(
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
            break :blk try parse_concrete_func_type_constraint_shape(allocator, tokens, func.start_idx, name);
        } else null,
        .variadic => |type_name| if (allow_named_constraints) blk: {
            const name = type_name orelse break :blk null;
            break :blk try parse_concrete_func_type_constraint_shape(allocator, tokens, func.start_idx, name);
        } else null,
        .other => null,
    };
}

fn free_resolved_func_type_shape(allocator: std.mem.Allocator, resolved: ?ResolvedFuncTypeShape) void {
    const item = resolved orelse return;
    if (!item.owned) return;
    allocator.free(item.shape.param_types);
}

fn parse_concrete_func_type_constraint_shape(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    func_start_idx: usize,
    constraint_name: []const u8,
) !?ResolvedFuncTypeShape {
    const block_start = find_constraint_block_start_before(tokens, func_start_idx) orelse return null;

    var i = block_start;
    while (i < func_start_idx) {
        if (!tok_eq(tokens[i], "#")) {
            i += 1;
            continue;
        }
        const line_end = find_line_end_idx(tokens, i);
        const is_func_constraint = i + 2 < line_end and tok_eq(tokens[i + 2], "(");
        if (is_func_constraint or i + 1 >= line_end or !std.mem.eql(u8, tokens[i + 1].lexeme, constraint_name)) {
            i = line_end;
            continue;
        }

        const eq_idx = find_top_level_assign_eq_on_line(tokens, i + 2, line_end) orelse return null;
        if (!is_func_type_range(tokens, eq_idx + 1, line_end)) return null;
        if (func_type_constraint_uses_prior_type_param(tokens, block_start, i, eq_idx + 1, line_end)) return null;

        const close_params = find_matching(tokens, eq_idx + 1, "(", ")") catch return null;
        const param_types = try parse_type_name_list(allocator, tokens, eq_idx + 2, close_params);
        return .{
            .shape = .{
                .param_count = param_types.len,
                .param_types = param_types,
                .return_type = simple_type_name(tokens, close_params + 3, line_end),
            },
            .owned = true,
        };
    }
    return null;
}

fn type_constraint_is_concrete_function_type(
    tokens: []const lexer.Token,
    func_start_idx: usize,
    constraint_name: []const u8,
) bool {
    const block_start = find_constraint_block_start_before(tokens, func_start_idx) orelse return false;

    var i = block_start;
    while (i < func_start_idx) {
        if (!tok_eq(tokens[i], "#")) {
            i += 1;
            continue;
        }
        const line_end = find_line_end_idx(tokens, i);
        const is_func_constraint = i + 2 < line_end and tok_eq(tokens[i + 2], "(");
        if (is_func_constraint or i + 1 >= line_end or !std.mem.eql(u8, tokens[i + 1].lexeme, constraint_name)) {
            i = line_end;
            continue;
        }

        const eq_idx = find_top_level_assign_eq_on_line(tokens, i + 2, line_end) orelse return false;
        if (!is_func_type_range(tokens, eq_idx + 1, line_end)) return false;
        return !func_type_constraint_uses_prior_type_param(tokens, block_start, i, eq_idx + 1, line_end);
    }
    return false;
}

fn is_func_type_param(tokens: []const lexer.Token, func_start_idx: usize, name: []const u8) bool {
    const block_start = find_constraint_block_start_before(tokens, func_start_idx) orelse return false;

    var i = block_start;
    while (i < func_start_idx) {
        if (!tok_eq(tokens[i], "#")) {
            i += 1;
            continue;
        }
        const line_end = find_line_end_idx(tokens, i);
        const is_func_constraint = i + 2 < line_end and tok_eq(tokens[i + 2], "(");
        if (!is_func_constraint and i + 1 < line_end and std.mem.eql(u8, tokens[i + 1].lexeme, name)) {
            return true;
        }
        i = line_end;
    }
    return false;
}

fn func_type_constraint_uses_prior_type_param(
    tokens: []const lexer.Token,
    block_start: usize,
    constraint_idx: usize,
    type_start: usize,
    type_end: usize,
) bool {
    var i = type_start;
    while (i < type_end) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (has_type_constraint_name(tokens, block_start, constraint_idx, tokens[i].lexeme)) return true;
    }
    return false;
}

fn has_type_constraint_name(
    tokens: []const lexer.Token,
    block_start: usize,
    before_idx: usize,
    name: []const u8,
) bool {
    var i = block_start;
    while (i < before_idx) {
        if (!tok_eq(tokens[i], "#")) {
            i += 1;
            continue;
        }
        const line_end = find_line_end_idx(tokens, i);
        const is_func_constraint = i + 2 < line_end and tok_eq(tokens[i + 2], "(");
        if (!is_func_constraint and i + 1 < line_end and std.mem.eql(u8, tokens[i + 1].lexeme, name)) {
            return true;
        }
        i = line_end;
    }
    return false;
}

fn find_constraint_block_start_before(tokens: []const lexer.Token, decl_start_idx: usize) ?usize {
    if (decl_start_idx == 0 or decl_start_idx >= tokens.len) return null;

    var scan_idx = decl_start_idx;
    var expected_line = tokens[decl_start_idx].line;
    var block_start: ?usize = null;

    while (scan_idx > 0) {
        const prev_idx = scan_idx - 1;
        const prev_line = tokens[prev_idx].line;
        if (prev_line + 1 != expected_line) break;

        const line_start = line_start_idx(tokens, prev_idx);
        if (!tok_eq(tokens[line_start], "#")) break;

        block_start = line_start;
        scan_idx = line_start;
        expected_line = prev_line;
    }

    return block_start;
}

fn count_funcs_matching_target(
    local_funcs: []const FuncShape,
    imported_funcs: []const FuncShape,
    name: []const u8,
    target_func: FuncTypeShape,
) usize {
    var count: usize = 0;
    for (local_funcs) |func| {
        if (!std.mem.eql(u8, func.name, name)) continue;
        if (!function_matches_target(func, target_func)) continue;
        count += 1;
    }
    for (imported_funcs) |func| {
        if (!std.mem.eql(u8, func.name, name)) continue;
        if (!function_matches_target(func, target_func)) continue;
        count += 1;
    }
    return count;
}

fn function_matches_target(func: FuncShape, target: FuncTypeShape) bool {
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

fn count_funcs_by_name(local_funcs: []const FuncShape, imported_funcs: []const FuncShape, name: []const u8) usize {
    var count: usize = 0;
    for (local_funcs) |func| {
        if (std.mem.eql(u8, func.name, name)) count += 1;
    }
    for (imported_funcs) |func| {
        if (std.mem.eql(u8, func.name, name)) count += 1;
    }
    return count;
}

fn parse_top_level_func_return_type(tokens: []const lexer.Token, start_idx: usize) ?[]const u8 {
    if (start_idx >= tokens.len) return null;
    if (tok_eq(tokens[start_idx], "{") or is_arrow_at(tokens, start_idx)) return null;

    if (is_return_arrow_at(tokens, start_idx)) {
        return simple_type_name(tokens, start_idx + 2, find_return_type_end(tokens, start_idx + 2));
    }

    return simple_type_name(tokens, start_idx, find_return_type_end(tokens, start_idx));
}

fn scan_top_level_return_type_segment_end(tokens: []const lexer.Token, start_i: usize, start_line: usize) usize {
    var i = start_i;
    var depth_angle: usize = 0;
    var depth_paren: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokens[i].line != start_line) break;
        if (tok_eq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tok_eq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tok_eq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (depth_angle != 0 or depth_paren != 0) continue;
        if (tok_eq(tokens[i], ",") or tok_eq(tokens[i], "{") or is_arrow_at(tokens, i)) break;
    }
    return i;
}

fn parse_top_level_func_return_arity(tokens: []const lexer.Token, input_start_idx: usize) usize {
    var start_idx = input_start_idx;
    if (is_return_arrow_at(tokens, start_idx)) start_idx += 2;
    if (start_idx >= tokens.len) return 0;
    if (tok_eq(tokens[start_idx], "{") or is_arrow_at(tokens, start_idx)) return 0;

    if (tok_eq(tokens[start_idx], "nil")) {
        if (start_idx + 1 >= tokens.len) return 0;
        if (tok_eq(tokens[start_idx + 1], "{") or is_arrow_at(tokens, start_idx + 1)) return 0;
    }

    var arity: usize = 0;
    var i = start_idx;
    const start_line = tokens[start_idx].line;
    while (i < tokens.len) {
        const seg_start = i;
        i = scan_top_level_return_type_segment_end(tokens, i, start_line);
        if (seg_start == i) return arity;
        arity += 1;
        if (i >= tokens.len) return arity;
        if (tok_eq(tokens[i], ",")) {
            i += 1;
            continue;
        }
        return arity;
    }
    return arity;
}

fn find_return_type_end(tokens: []const lexer.Token, start_idx: usize) usize {
    var i = start_idx;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) return i;
        if (is_arrow_at(tokens, i)) return i;
        if (tokens[i].line != tokens[start_idx].line) return i;
    }
    return i;
}

fn simple_type_name(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    if (start_idx + 1 != end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    return tokens[start_idx].lexeme;
}

fn is_top_level_comma_any(tokens: []const lexer.Token, idx: usize, start_idx: usize, end_idx: usize) bool {
    if (!tok_eq(tokens[idx], ",")) return false;

    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < idx and i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tok_eq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tok_eq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
    }

    return depth_paren == 0 and depth_brace == 0 and depth_angle == 0;
}

fn has_known_func_candidate(funcs: []const FuncShape, name: []const u8) bool {
    for (funcs) |func| {
        if (std.mem.eql(u8, func.name, name)) return true;
    }
    return false;
}

fn line_start_idx(tokens: []const lexer.Token, idx: usize) usize {
    var out = idx;
    while (out > 0 and tokens[out - 1].line == tokens[idx].line) : (out -= 1) {}
    return out;
}

fn public_func_name(name: []const u8) []const u8 {
    if (name.len != 0 and name[0] == '.') return name[1..];
    return name;
}

fn is_spread_token(tok: lexer.Token) bool {
    return tok.kind == .symbol and tok_eq(tok, "...");
}

fn is_call_head(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (tokens[idx].kind != .ident) return false;
    if (idx > 0 and tok_eq(tokens[idx - 1], "@") and tokens[idx - 1].line == tokens[idx].line) return false;
    if (is_keyword(tokens[idx].lexeme)) return false;
    return tok_eq(tokens[idx + 1], "(");
}

fn is_func_constraint_head(tokens: []const lexer.Token, idx: usize) bool {
    if (idx == 0 or !tok_eq(tokens[idx - 1], "#")) return false;
    return tokens[idx - 1].line == tokens[idx].line;
}

fn is_arrow_at(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 1 < tokens.len and tok_eq(tokens[idx], "=") and tok_eq(tokens[idx + 1], ">");
}

fn is_return_arrow_at(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 1 < tokens.len and tok_eq(tokens[idx], "-") and tok_eq(tokens[idx + 1], ">");
}

fn is_func_type_range(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx >= end_idx or !tok_eq(tokens[start_idx], "(")) return false;
    const close_idx = find_matching(tokens, start_idx, "(", ")") catch return false;
    return close_idx + 2 < end_idx and is_return_arrow_at(tokens, close_idx + 1);
}

fn count_call_args(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) !usize {
    if (start_idx >= end_idx) return 0;

    var count: usize = 1;
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tok_eq(tokens[i], ")")) {
            if (depth_paren == 0) return error.InvalidCallArgList;
            depth_paren -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace == 0) return error.InvalidCallArgList;
            depth_brace -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tok_eq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (depth_paren != 0 or depth_brace != 0 or depth_angle != 0) continue;
        if (tok_eq(tokens[i], ",")) count += 1;
    }
    if (depth_paren != 0 or depth_brace != 0 or depth_angle != 0) return error.InvalidCallArgList;
    return count;
}

fn find_public_enum_member_kind(tokens: []const lexer.Token, start_idx: usize, target: []const u8) ?DeclKind {
    const eq_idx = enum_decl_assign_idx(tokens, start_idx) orelse return null;
    if (is_private_decl_name(tokens[start_idx].lexeme)) return null;
    const line_end = find_line_end_idx(tokens, start_idx);
    const kind: DeclKind = if (is_error_enum_decl_start(tokens, start_idx)) .error_branch else .value_enum_branch;

    var i = eq_idx + 1;
    while (i < line_end) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (is_private_decl_name(tokens[i].lexeme)) continue;
        if (std.mem.eql(u8, tokens[i].lexeme, target)) return kind;
    }
    return null;
}

fn alias_matches_kind(alias: []const u8, kind: DeclKind) bool {
    return switch (kind) {
        .type, .value_enum_type => is_valid_declared_type_name(alias) and !is_error_type_name(alias),
        .error_type => is_error_type_name(alias),
        .error_branch, .value_enum_branch => is_valid_error_branch_name(alias) and !is_error_type_name(alias),
        .func => is_lower_ident_name(alias),
        .const_value => is_readonly_ident_name(alias),
        .var_value => is_lower_ident_name(alias),
    };
}

fn is_type_like_kind(kind: DeclKind) bool {
    return switch (kind) {
        .type, .error_type, .value_enum_type => true,
        .error_branch, .value_enum_branch, .func, .const_value, .var_value => false,
    };
}

fn is_valid_error_branch_name(name: []const u8) bool {
    if (!is_valid_declared_type_name(name)) return false;
    if (std.mem.eql(u8, name, "Error")) return false;
    return true;
}

fn is_error_type_name(name: []const u8) bool {
    if (name.len == 0 or name[0] == '.') return false;
    if (!is_valid_declared_type_name(name)) return false;
    if (std.mem.eql(u8, name, "Error")) return false;
    return std.mem.endsWith(u8, name, "Error");
}

fn enum_decl_assign_idx(tokens: []const lexer.Token, start_idx: usize) ?usize {
    if (is_error_enum_decl_start(tokens, start_idx) or is_value_enum_decl_start(tokens, start_idx)) {
        return start_idx + 2;
    }
    return null;
}

fn is_error_enum_decl_start(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 2 < tokens.len and
        is_error_type_name(tokens[idx].lexeme) and
        tok_eq(tokens[idx + 1], "error") and
        tok_eq(tokens[idx + 2], "=");
}

fn is_value_enum_decl_start(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 2 < tokens.len and
        is_valid_declared_type_name(tokens[idx].lexeme) and
        !is_error_type_name(tokens[idx].lexeme) and
        is_base_int_type_name(tokens[idx + 1].lexeme) and
        tok_eq(tokens[idx + 2], "=");
}

fn has_type_name_conflict(tokens: []const lexer.Token, alias_idx: usize) bool {
    const alias = public_type_name(tokens[alias_idx].lexeme);

    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (i == alias_idx) continue;
        if (!is_top_level_decl_head(tokens, i)) continue;
        if (tokens[i].kind != .ident) continue;
        if (!is_valid_declared_type_name(tokens[i].lexeme)) continue;
        if (!is_modern_import_assign(tokens, i) and !is_type_decl_start(tokens, i)) continue;
        if (std.mem.eql(u8, public_type_name(tokens[i].lexeme), alias)) return true;
    }

    return false;
}

fn public_type_name(name: []const u8) []const u8 {
    if (name.len != 0 and name[0] == '.') return name[1..];
    return name;
}

fn is_modern_import_assign(tokens: []const lexer.Token, idx: usize) bool {
    const eq_idx = top_level_line_assign_idx(tokens, idx) orelse return false;
    const line_end = find_line_end_idx(tokens, idx);
    const at_idx = eq_idx + 1;
    if (at_idx + 1 >= line_end or !tok_eq(tokens[at_idx], "@")) return false;
    if (tokens[at_idx + 1].kind != .ident) return false;
    return std.mem.eql(u8, tokens[at_idx + 1].lexeme, "lib") or
        std.mem.eql(u8, tokens[at_idx + 1].lexeme, "host");
}

fn is_non_host_import_assign(tokens: []const lexer.Token, idx: usize) bool {
    if (!is_modern_import_assign(tokens, idx)) return false;
    const eq_idx = top_level_line_assign_idx(tokens, idx) orelse return false;
    const line_end = find_line_end_idx(tokens, idx);
    const at_idx = eq_idx + 1;
    return !is_host_import_line(tokens, at_idx, line_end);
}

fn parse_lib_import_close(tokens: []const lexer.Token, at_idx: usize, line_end: usize) ?usize {
    if (at_idx + 6 >= line_end) return null;
    if (!tok_eq(tokens[at_idx], "@")) return null;
    if (tokens[at_idx + 1].kind != .ident or !std.mem.eql(u8, tokens[at_idx + 1].lexeme, "lib")) return null;
    if (!tok_eq(tokens[at_idx + 2], "(")) return null;
    if (tokens[at_idx + 3].kind != .string) return null;
    if (!tok_eq(tokens[at_idx + 4], ",")) return null;
    if (tokens[at_idx + 5].kind != .ident) return null;
    if (!tok_eq(tokens[at_idx + 6], ")")) return null;
    return at_idx + 6;
}

fn is_private_decl_name(name: []const u8) bool {
    return name.len != 0 and name[0] == '.';
}

fn is_private_func_decl_name(name: []const u8) bool {
    return name.len > 1 and name[0] == '.' and is_lower_ident_name(name[1..]);
}

fn is_func_decl_start(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (is_keyword(tokens[idx].lexeme)) return false;
    if (!is_lower_ident_name(tokens[idx].lexeme) and !is_private_func_decl_name(tokens[idx].lexeme)) return false;
    return tok_eq(tokens[idx + 1], "(");
}

fn is_type_decl_start(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (tok_eq(tokens[idx + 1], "(")) return false;
    if (is_error_enum_decl_start(tokens, idx) or is_value_enum_decl_start(tokens, idx)) return true;

    var next_idx = idx + 1;
    if (tok_eq(tokens[next_idx], "<")) {
        const close_angle = find_matching(tokens, next_idx, "<", ">") catch return false;
        next_idx = close_angle + 1;
        if (next_idx >= tokens.len) return false;
    }

    return tok_eq(tokens[next_idx], "{") or tok_eq(tokens[next_idx], "=");
}

fn is_top_value_decl_start(tokens: []const lexer.Token, idx: usize) bool {
    const eq_idx = top_level_line_assign_idx(tokens, idx) orelse return false;
    if (tokens[eq_idx].line != tokens[idx].line) return false;
    if (is_modern_import_assign(tokens, idx)) return false;
    return true;
}

fn is_host_import_decl_start(tokens: []const lexer.Token, idx: usize) bool {
    const eq_idx = top_level_line_assign_idx(tokens, idx) orelse return false;
    const line_end = find_line_end_idx(tokens, idx);
    const at_idx = eq_idx + 1;
    if (at_idx >= line_end or !tok_eq(tokens[at_idx], "@")) return false;
    return is_host_import_line(tokens, at_idx, line_end);
}

fn is_host_import_line(tokens: []const lexer.Token, at_idx: usize, line_end: usize) bool {
    if (at_idx + 3 >= line_end) return false;
    if (!tok_eq(tokens[at_idx], "@")) return false;
    if (tokens[at_idx + 1].kind != .ident) return false;
    if (std.mem.eql(u8, tokens[at_idx + 1].lexeme, "host"))
    {
        return tok_eq(tokens[at_idx + 2], "(");
    }
    return false;
}

fn is_valid_import_name(name: []const u8) bool {
    if (name.len == 0 or name[0] == '.') return false;
    return (is_valid_declared_type_name(name) or is_lower_ident_name(name) or is_readonly_ident_name(name)) and !is_reserved_func_name(name);
}

fn string_token_body(s: []const u8) ?[]const u8 {
    if (s.len < 2) return null;
    if (s[0] != '"' or s[s.len - 1] != '"') return null;
    return s[1 .. s.len - 1];
}

fn is_valid_import_file_name(name: []const u8, prefix: ImportPrefix) bool {
    if (!std.mem.endsWith(u8, name, ".do")) return false;
    const stem = name[0 .. name.len - 3];
    if (stem.len == 0) return false;
    return switch (prefix) {
        .dep => is_valid_dep_file_stem(stem),
        .local, .std => is_valid_flat_file_stem(stem),
    };
}

fn is_valid_flat_file_stem(stem: []const u8) bool {
    var count: usize = 0;
    var start: usize = 0;
    while (start <= stem.len) {
        const dot_idx = std.mem.indexOfScalarPos(u8, stem, start, '.') orelse stem.len;
        if (!is_valid_path_seg(stem[start..dot_idx])) return false;
        count += 1;
        if (dot_idx == stem.len) break;
        start = dot_idx + 1;
    }
    return count != 0;
}

fn is_valid_dep_file_stem(stem: []const u8) bool {
    var count: usize = 0;
    var start: usize = 0;
    while (start <= stem.len) {
        const dot_idx = std.mem.indexOfScalarPos(u8, stem, start, '.') orelse stem.len;
        const seg = stem[start..dot_idx];
        if (!is_all_digits(seg) and !is_valid_path_seg(seg)) return false;
        count += 1;
        if (dot_idx == stem.len) break;
        start = dot_idx + 1;
    }
    return count >= 2;
}

fn is_all_digits(seg: []const u8) bool {
    if (seg.len == 0) return false;
    for (seg) |ch| {
        if (ch < '0' or ch > '9') return false;
    }
    return true;
}

fn is_valid_path_seg(seg: []const u8) bool {
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

fn top_level_line_assign_idx(tokens: []const lexer.Token, line_start: usize) ?usize {
    const line_end = find_line_end_idx(tokens, line_start);
    return find_top_level_assign_eq_on_line(tokens, line_start + 1, line_end);
}

fn find_top_level_assign_eq_on_line(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tok_eq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tok_eq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (depth_paren != 0 or depth_brace != 0 or depth_angle != 0) continue;
        if (tok_eq(tokens[i], "=") and !is_non_assign_equal(tokens, i)) return i;
    }
    return null;
}

fn find_line_end_idx(tokens: []const lexer.Token, start_idx: usize) usize {
    if (start_idx >= tokens.len) return start_idx;
    const line = tokens[start_idx].line;
    var i = start_idx;
    while (i < tokens.len and tokens[i].line == line) : (i += 1) {}
    return i;
}

fn find_token_on_line(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, s: []const u8) ?usize {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], s)) return i;
    }
    return null;
}

fn find_matching(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8) !usize {
    if (open_idx >= tokens.len or !tok_eq(tokens[open_idx], open)) return error.InvalidGroupStart;

    var depth: usize = 0;
    var i = open_idx;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], open)) {
            depth += 1;
            continue;
        }
        if (!tok_eq(tokens[i], close)) continue;
        if (depth == 0) return error.InvalidGroupDepth;
        depth -= 1;
        if (depth == 0) return i;
    }
    return error.UnterminatedGroup;
}

fn is_non_assign_equal(tokens: []const lexer.Token, idx: usize) bool {
    if (idx > 0 and tok_eq(tokens[idx - 1], "=")) return true;
    if (idx + 1 < tokens.len and tok_eq(tokens[idx + 1], "=")) return true;
    if (idx + 1 < tokens.len and tok_eq(tokens[idx + 1], ">")) return true;
    return false;
}

fn is_top_level_decl_head(tokens: []const lexer.Token, idx: usize) bool {
    if (idx == 0) return true;
    if (tokens[idx - 1].line == tokens[idx].line) return false;
    const prev = tokens[idx - 1];
    if (tok_eq(prev, "=")) return false;
    if (tok_eq(prev, "|")) return false;
    if (tok_eq(prev, ",")) return false;
    if (tok_eq(prev, ":")) return false;
    return true;
}

fn is_valid_declared_type_name(name: []const u8) bool {
    if (name.len == 0) return false;
    if (name[0] == '.') return is_valid_declared_type_name(name[1..]);
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

fn is_base_int_type_name(name: []const u8) bool {
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

fn is_lower_ident_name(name: []const u8) bool {
    return is_snake_lower_name(name);
}

fn is_readonly_ident_name(name: []const u8) bool {
    if (name.len < 2) return false;
    if (name[0] != '_') return false;
    return is_snake_lower_name(name[1..]);
}

fn is_snake_lower_name(name: []const u8) bool {
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

fn is_keyword(name: []const u8) bool {
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

fn is_reserved_func_name(name: []const u8) bool {
    const public_name = if (name.len != 0 and name[0] == '.') name[1..] else name;
    if (std.mem.eql(u8, public_name, "start")) return true;
    if (is_keyword(public_name)) return true;
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

fn mark_error_at(tokens: []const lexer.Token, idx: usize, err: anyerror) anyerror {
    if (idx < tokens.len) {
        last_error_site = .{ .line = tokens[idx].line, .col = tokens[idx].col };
    }
    return err;
}

fn tok_eq(t: lexer.Token, s: []const u8) bool {
    return std.mem.eql(u8, t.lexeme, s);
}
