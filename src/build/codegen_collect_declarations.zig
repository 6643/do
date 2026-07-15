//! Collect domain — type (extracted from codegen_collect).
const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const test_runner = @import("test_runner.zig");
const type_util = @import("type_name.zig");
const codegen_tokens = @import("codegen_tokens.zig");
const codegen_names = @import("codegen_names.zig");
const model = @import("codegen_model.zig");
const codegen_union_layout = @import("codegen_union_layout.zig");
const codegen_imports = @import("codegen_imports.zig");
const codegen_wasi_registry = @import("codegen_wasi_registry.zig");
const codegen_collect_util = @import("codegen_collect_util.zig");
const parse_codegen_type_expr = codegen_collect_util.parse_codegen_type_expr;

const find_line_end = codegen_tokens.find_line_end;
const find_matching = codegen_tokens.find_matching;
const publicDeclName = codegen_names.public_decl_name;
const tok_eq = codegen_tokens.tok_eq;
const find_imported_module_index = codegen_imports.find_imported_module_index;
const find_payload_enum_decl = codegen_imports.find_payload_enum_decl;
const find_payload_enum_decl_line_by_name = codegen_imports.find_payload_enum_decl_line_by_name;
const find_root_module_index = codegen_imports.find_root_module_index;
const find_value_enum_decl = codegen_imports.find_value_enum_decl;
const find_value_enum_decl_line_by_branch = codegen_imports.find_value_enum_decl_line_by_branch;
const find_value_enum_decl_line_by_name = codegen_imports.find_value_enum_decl_line_by_name;
const is_payload_enum_decl_start = codegen_imports.is_payload_enum_decl_start;
const is_value_enum_decl_start = codegen_imports.is_value_enum_decl_start;
const parse_codegen_import = codegen_imports.parse_codegen_import;
const PayloadEnumCase = model.PayloadEnumCase;
const PayloadEnumDecl = model.PayloadEnumDecl;
const ValueEnumBranch = model.ValueEnumBranch;
const ValueEnumDecl = model.ValueEnumDecl;

pub fn collect_value_enum_decls(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    out: *std.ArrayList(ValueEnumDecl),
) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i + 2 < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!is_value_enum_decl_start(tokens, i)) continue;
        _ = try collect_value_enum_decl_by_name_as(allocator, tokens, publicDeclName(tokens[i].lexeme), publicDeclName(tokens[i].lexeme), false, out);
        i = find_line_end(tokens, i) - 1;
    }
}

pub fn collect_imported_value_enum_decls(
    allocator: std.mem.Allocator,
    entry_tokens: []const lexer.Token,
    graph: *const imports.ModuleGraph,
    out: *std.ArrayList(ValueEnumDecl),
) !void {
    const root_idx = find_root_module_index(graph.modules, entry_tokens) orelse return;

    var i: usize = 0;
    while (i < entry_tokens.len) : (i += 1) {
        const import_ref = parse_codegen_import(entry_tokens, i) orelse continue;
        defer i = find_line_end(entry_tokens, i) - 1;

        const child_idx = find_imported_module_index(allocator, graph, root_idx, import_ref) orelse continue;
        const child_tokens = graph.modules[child_idx].tokens;
        if (find_value_enum_decl_line_by_name(child_tokens, import_ref.target)) |_| {
            if (find_value_enum_decl(out.items, import_ref.alias) == null) {
                _ = try collect_value_enum_decl_by_name_as(allocator, child_tokens, import_ref.target, import_ref.alias, !std.mem.eql(u8, import_ref.target, import_ref.alias), out);
            }
            if (!std.mem.eql(u8, import_ref.alias, import_ref.target) and find_value_enum_decl(out.items, import_ref.target) == null) {
                _ = try collect_value_enum_decl_by_name_as(allocator, child_tokens, import_ref.target, import_ref.target, false, out);
            }
            continue;
        }

        if (find_value_enum_decl_line_by_branch(child_tokens, import_ref.target)) |enum_idx| {
            const enum_name = publicDeclName(child_tokens[enum_idx].lexeme);
            if (find_value_enum_decl(out.items, enum_name) == null) {
                _ = try collect_value_enum_decl_by_name_as(allocator, child_tokens, enum_name, enum_name, false, out);
            }
        }
    }
}

pub fn collect_value_enum_decl_by_name_as(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    target_name: []const u8,
    emit_name: []const u8,
    own_emit_name: bool,
    out: *std.ArrayList(ValueEnumDecl),
) !bool {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i + 2 < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!is_value_enum_decl_start(tokens, i)) continue;
        if (!std.mem.eql(u8, publicDeclName(tokens[i].lexeme), target_name)) continue;

        const line_end = find_line_end(tokens, i);
        var branches = std.ArrayList(ValueEnumBranch).empty;
        errdefer branches.deinit(allocator);
        var j = i + 3;
        while (j + 3 < line_end) {
            if (tok_eq(tokens[j], "|")) {
                j += 1;
                continue;
            }
            if (tokens[j].kind != .ident or !tok_eq(tokens[j + 1], "(") or tokens[j + 2].kind != .number or !tok_eq(tokens[j + 3], ")")) {
                return false;
            }
            try branches.append(allocator, .{
                .name = publicDeclName(tokens[j].lexeme),
                .value = tokens[j + 2].lexeme,
            });
            j += 4;
        }

        const owned_name = if (own_emit_name) try allocator.dupe(u8, emit_name) else emit_name;
        errdefer if (own_emit_name) allocator.free(owned_name);
        try out.append(allocator, .{
            .name = owned_name,
            .source_name = target_name,
            .carrier = tokens[i + 1].lexeme,
            .branches = try branches.toOwnedSlice(allocator),
            .owned_name = own_emit_name,
        });
        return true;
    }
    return false;
}

pub fn collect_payload_enum_decls(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    out: *std.ArrayList(PayloadEnumDecl),
) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i + 2 < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!is_payload_enum_decl_start(tokens, i)) continue;
        if (!try collect_payload_enum_decl_at(allocator, tokens, i, out)) {
            return error.NoMatchingCall;
        }
        i = find_line_end(tokens, i) - 1;
    }
}

/// Collect payload enums from imported modules so module-local types
/// (e.g. `IpSocketAddress` in lib/tcp.do) resolve when lowering imported funcs.
pub fn collect_imported_payload_enum_decls(
    allocator: std.mem.Allocator,
    entry_tokens: []const lexer.Token,
    graph: *const imports.ModuleGraph,
    out: *std.ArrayList(PayloadEnumDecl),
) !void {
    const root_idx = find_root_module_index(graph.modules, entry_tokens) orelse return;

    var i: usize = 0;
    while (i < entry_tokens.len) : (i += 1) {
        const import_ref = parse_codegen_import(entry_tokens, i) orelse continue;
        defer i = find_line_end(entry_tokens, i) - 1;

        const child_idx = find_imported_module_index(allocator, graph, root_idx, import_ref) orelse continue;
        const child_tokens = graph.modules[child_idx].tokens;
        const enum_idx = find_payload_enum_decl_line_by_name(child_tokens, import_ref.target) orelse continue;

        // Same-name import: collect under target name if missing.
        if (std.mem.eql(u8, import_ref.alias, import_ref.target)) {
            if (find_payload_enum_decl(out.items, import_ref.target) == null) {
                if (!try collect_payload_enum_decl_at(allocator, child_tokens, enum_idx, out)) {
                    return error.NoMatchingCall;
                }
            }
            continue;
        }

        // Aliased import: ensure both target and alias entries when needed.
        if (find_payload_enum_decl(out.items, import_ref.target) == null) {
            if (!try collect_payload_enum_decl_at(allocator, child_tokens, enum_idx, out)) {
                return error.NoMatchingCall;
            }
        }
        if (find_payload_enum_decl(out.items, import_ref.alias) == null) {
            if (!try collect_payload_enum_decl_by_name_as(allocator, child_tokens, import_ref.target, import_ref.alias, true, out)) {
                return error.NoMatchingCall;
            }
        }
    }

    // Module-local payload enums used only inside imported function bodies.
    for (graph.modules, 0..) |module, idx| {
        if (idx == root_idx) continue;
        try collect_payload_enum_decls(allocator, module.tokens, out);
    }
}

pub fn collect_payload_enum_decl_by_name_as(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    target_name: []const u8,
    emit_name: []const u8,
    own_emit_name: bool,
    out: *std.ArrayList(PayloadEnumDecl),
) !bool {
    if (find_payload_enum_decl(out.items, emit_name) != null) return true;
    const enum_idx = find_payload_enum_decl_line_by_name(tokens, target_name) orelse return false;
    if (!is_payload_enum_decl_start(tokens, enum_idx)) return false;

    const line_end = find_line_end(tokens, enum_idx);
    var cases = std.ArrayList(PayloadEnumCase).empty;
    errdefer cases.deinit(allocator);
    var owned_payload_tys = std.ArrayList([]const u8).empty;
    errdefer {
        for (owned_payload_tys.items) |owned| allocator.free(owned);
        owned_payload_tys.deinit(allocator);
    }

    var j = enum_idx + 2; // after Name =
    while (j < line_end) {
        if (tok_eq(tokens[j], "|")) {
            j += 1;
            continue;
        }
        if (tokens[j].kind != .ident) return false;
        const case_name = publicDeclName(tokens[j].lexeme);
        j += 1;
        var payload_ty: ?[]const u8 = null;
        if (j < line_end and tok_eq(tokens[j], "(")) {
            const close = find_matching(tokens, j, "(", ")") catch return false;
            const parsed = (try parse_codegen_type_expr(allocator, tokens, j + 1, close, &owned_payload_tys)) orelse return false;
            if (parsed.next_idx != close) return false;
            payload_ty = parsed.ty;
            j = close + 1;
        }
        try cases.append(allocator, .{
            .name = case_name,
            .payload_ty = payload_ty,
        });
    }

    const owned_name = if (own_emit_name) try allocator.dupe(u8, emit_name) else emit_name;
    errdefer if (own_emit_name) allocator.free(owned_name);
    try out.append(allocator, .{
        .name = owned_name,
        .cases = try cases.toOwnedSlice(allocator),
        .owned_payload_tys = try owned_payload_tys.toOwnedSlice(allocator),
        .owned_name = own_emit_name,
    });
    return true;
}

pub fn collect_payload_enum_decl_at(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    enum_idx: usize,
    out: *std.ArrayList(PayloadEnumDecl),
) !bool {
    if (!is_payload_enum_decl_start(tokens, enum_idx)) return false;
    const name = publicDeclName(tokens[enum_idx].lexeme);
    if (find_payload_enum_decl(out.items, name) != null) return true;

    const line_end = find_line_end(tokens, enum_idx);
    var cases = std.ArrayList(PayloadEnumCase).empty;
    errdefer cases.deinit(allocator);
    var owned_payload_tys = std.ArrayList([]const u8).empty;
    errdefer {
        for (owned_payload_tys.items) |owned| allocator.free(owned);
        owned_payload_tys.deinit(allocator);
    }

    var j = enum_idx + 2; // after Name =
    while (j < line_end) {
        if (tok_eq(tokens[j], "|")) {
            j += 1;
            continue;
        }
        if (tokens[j].kind != .ident) return false;
        const case_name = publicDeclName(tokens[j].lexeme);
        j += 1;
        var payload_ty: ?[]const u8 = null;
        if (j < line_end and tok_eq(tokens[j], "(")) {
            const close = find_matching(tokens, j, "(", ")") catch return false;
            // Type expr lives strictly inside the parens: tokens[j+1 .. close].
            const parsed = (try parse_codegen_type_expr(allocator, tokens, j + 1, close, &owned_payload_tys)) orelse return false;
            if (parsed.next_idx != close) return false;
            payload_ty = parsed.ty;
            j = close + 1;
        }
        try cases.append(allocator, .{
            .name = case_name,
            .payload_ty = payload_ty,
        });
    }

    try out.append(allocator, .{
        .name = name,
        .cases = try cases.toOwnedSlice(allocator),
        .owned_payload_tys = try owned_payload_tys.toOwnedSlice(allocator),
        .owned_name = false,
    });
    return true;
}
