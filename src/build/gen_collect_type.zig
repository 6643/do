//! Collect domain — type (extracted from gen_collect).
const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const test_runner = @import("test_runner.zig");
const type_util = @import("type_name.zig");
const gen_util = @import("gen_util.zig");
const gen_types = @import("gen_types.zig");
const gen_union = @import("gen_union.zig");
const gen_import = @import("gen_import.zig");
const gen_wasi = @import("gen_wasi.zig");
const gen_collect_util = @import("gen_collect_util.zig");
const parseCodegenTypeExpr = gen_collect_util.parseCodegenTypeExpr;

const findLineEnd = gen_util.findLineEnd;
const findMatching = gen_util.findMatching;
const publicDeclName = gen_util.publicDeclName;
const tokEq = gen_util.tokEq;
const findImportedModuleIndex = gen_import.findImportedModuleIndex;
const findPayloadEnumDecl = gen_import.findPayloadEnumDecl;
const findPayloadEnumDeclLineByName = gen_import.findPayloadEnumDeclLineByName;
const findRootModuleIndex = gen_import.findRootModuleIndex;
const findValueEnumDecl = gen_import.findValueEnumDecl;
const findValueEnumDeclLineByBranch = gen_import.findValueEnumDeclLineByBranch;
const findValueEnumDeclLineByName = gen_import.findValueEnumDeclLineByName;
const isPayloadEnumDeclStart = gen_import.isPayloadEnumDeclStart;
const isValueEnumDeclStart = gen_import.isValueEnumDeclStart;
const parseCodegenImport = gen_import.parseCodegenImport;
const PayloadEnumCase = gen_types.PayloadEnumCase;
const PayloadEnumDecl = gen_types.PayloadEnumDecl;
const ValueEnumBranch = gen_types.ValueEnumBranch;
const ValueEnumDecl = gen_types.ValueEnumDecl;

pub fn collectValueEnumDecls(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    out: *std.ArrayList(ValueEnumDecl),
) !void {
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
        _ = try collectValueEnumDeclByNameAs(allocator, tokens, publicDeclName(tokens[i].lexeme), publicDeclName(tokens[i].lexeme), false, out);
        i = findLineEnd(tokens, i) - 1;
    }
}


pub fn collectImportedValueEnumDecls(
    allocator: std.mem.Allocator,
    entry_tokens: []const lexer.Token,
    graph: *const imports.ModuleGraph,
    out: *std.ArrayList(ValueEnumDecl),
) !void {
    const root_idx = findRootModuleIndex(graph.modules, entry_tokens) orelse return;

    var i: usize = 0;
    while (i < entry_tokens.len) : (i += 1) {
        const import_ref = parseCodegenImport(entry_tokens, i) orelse continue;
        defer i = findLineEnd(entry_tokens, i) - 1;

        const child_idx = findImportedModuleIndex(allocator, graph, root_idx, import_ref) orelse continue;
        const child_tokens = graph.modules[child_idx].tokens;
        if (findValueEnumDeclLineByName(child_tokens, import_ref.target)) |_| {
            if (findValueEnumDecl(out.items, import_ref.alias) == null) {
                _ = try collectValueEnumDeclByNameAs(allocator, child_tokens, import_ref.target, import_ref.alias, !std.mem.eql(u8, import_ref.target, import_ref.alias), out);
            }
            if (!std.mem.eql(u8, import_ref.alias, import_ref.target) and findValueEnumDecl(out.items, import_ref.target) == null) {
                _ = try collectValueEnumDeclByNameAs(allocator, child_tokens, import_ref.target, import_ref.target, false, out);
            }
            continue;
        }

        if (findValueEnumDeclLineByBranch(child_tokens, import_ref.target)) |enum_idx| {
            const enum_name = publicDeclName(child_tokens[enum_idx].lexeme);
            if (findValueEnumDecl(out.items, enum_name) == null) {
                _ = try collectValueEnumDeclByNameAs(allocator, child_tokens, enum_name, enum_name, false, out);
            }
        }
    }
}


pub fn collectValueEnumDeclByNameAs(
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
        if (!std.mem.eql(u8, publicDeclName(tokens[i].lexeme), target_name)) continue;

        const line_end = findLineEnd(tokens, i);
        var branches = std.ArrayList(ValueEnumBranch).empty;
        errdefer branches.deinit(allocator);
        var j = i + 3;
        while (j + 3 < line_end) {
            if (tokEq(tokens[j], "|")) {
                j += 1;
                continue;
            }
            if (tokens[j].kind != .ident or !tokEq(tokens[j + 1], "(") or tokens[j + 2].kind != .number or !tokEq(tokens[j + 3], ")")) {
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


pub fn collectPayloadEnumDecls(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    out: *std.ArrayList(PayloadEnumDecl),
) !void {
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
        if (!isPayloadEnumDeclStart(tokens, i)) continue;
        if (!try collectPayloadEnumDeclAt(allocator, tokens, i, out)) {
            return error.NoMatchingCall;
        }
        i = findLineEnd(tokens, i) - 1;
    }
}

/// Collect payload enums from imported modules so module-local types
/// (e.g. `IpSocketAddress` in lib/tcp.do) resolve when lowering imported funcs.
pub fn collectImportedPayloadEnumDecls(
    allocator: std.mem.Allocator,
    entry_tokens: []const lexer.Token,
    graph: *const imports.ModuleGraph,
    out: *std.ArrayList(PayloadEnumDecl),
) !void {
    const root_idx = findRootModuleIndex(graph.modules, entry_tokens) orelse return;

    var i: usize = 0;
    while (i < entry_tokens.len) : (i += 1) {
        const import_ref = parseCodegenImport(entry_tokens, i) orelse continue;
        defer i = findLineEnd(entry_tokens, i) - 1;

        const child_idx = findImportedModuleIndex(allocator, graph, root_idx, import_ref) orelse continue;
        const child_tokens = graph.modules[child_idx].tokens;
        const enum_idx = findPayloadEnumDeclLineByName(child_tokens, import_ref.target) orelse continue;

        // Same-name import: collect under target name if missing.
        if (std.mem.eql(u8, import_ref.alias, import_ref.target)) {
            if (findPayloadEnumDecl(out.items, import_ref.target) == null) {
                if (!try collectPayloadEnumDeclAt(allocator, child_tokens, enum_idx, out)) {
                    return error.NoMatchingCall;
                }
            }
            continue;
        }

        // Aliased import: ensure both target and alias entries when needed.
        if (findPayloadEnumDecl(out.items, import_ref.target) == null) {
            if (!try collectPayloadEnumDeclAt(allocator, child_tokens, enum_idx, out)) {
                return error.NoMatchingCall;
            }
        }
        if (findPayloadEnumDecl(out.items, import_ref.alias) == null) {
            if (!try collectPayloadEnumDeclByNameAs(allocator, child_tokens, import_ref.target, import_ref.alias, true, out)) {
                return error.NoMatchingCall;
            }
        }
    }

    // Module-local payload enums used only inside imported function bodies.
    for (graph.modules, 0..) |module, idx| {
        if (idx == root_idx) continue;
        try collectPayloadEnumDecls(allocator, module.tokens, out);
    }
}

pub fn collectPayloadEnumDeclByNameAs(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    target_name: []const u8,
    emit_name: []const u8,
    own_emit_name: bool,
    out: *std.ArrayList(PayloadEnumDecl),
) !bool {
    if (findPayloadEnumDecl(out.items, emit_name) != null) return true;
    const enum_idx = findPayloadEnumDeclLineByName(tokens, target_name) orelse return false;
    if (!isPayloadEnumDeclStart(tokens, enum_idx)) return false;

    const line_end = findLineEnd(tokens, enum_idx);
    var cases = std.ArrayList(PayloadEnumCase).empty;
    errdefer cases.deinit(allocator);
    var owned_payload_tys = std.ArrayList([]const u8).empty;
    errdefer {
        for (owned_payload_tys.items) |owned| allocator.free(owned);
        owned_payload_tys.deinit(allocator);
    }

    var j = enum_idx + 2; // after Name =
    while (j < line_end) {
        if (tokEq(tokens[j], "|")) {
            j += 1;
            continue;
        }
        if (tokens[j].kind != .ident) return false;
        const case_name = publicDeclName(tokens[j].lexeme);
        j += 1;
        var payload_ty: ?[]const u8 = null;
        if (j < line_end and tokEq(tokens[j], "(")) {
            const close = findMatching(tokens, j, "(", ")") catch return false;
            const parsed = (try parseCodegenTypeExpr(allocator, tokens, j + 1, close, &owned_payload_tys)) orelse return false;
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


pub fn collectPayloadEnumDeclAt(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    enum_idx: usize,
    out: *std.ArrayList(PayloadEnumDecl),
) !bool {
    if (!isPayloadEnumDeclStart(tokens, enum_idx)) return false;
    const name = publicDeclName(tokens[enum_idx].lexeme);
    if (findPayloadEnumDecl(out.items, name) != null) return true;

    const line_end = findLineEnd(tokens, enum_idx);
    var cases = std.ArrayList(PayloadEnumCase).empty;
    errdefer cases.deinit(allocator);
    var owned_payload_tys = std.ArrayList([]const u8).empty;
    errdefer {
        for (owned_payload_tys.items) |owned| allocator.free(owned);
        owned_payload_tys.deinit(allocator);
    }

    var j = enum_idx + 2; // after Name =
    while (j < line_end) {
        if (tokEq(tokens[j], "|")) {
            j += 1;
            continue;
        }
        if (tokens[j].kind != .ident) return false;
        const case_name = publicDeclName(tokens[j].lexeme);
        j += 1;
        var payload_ty: ?[]const u8 = null;
        if (j < line_end and tokEq(tokens[j], "(")) {
            const close = findMatching(tokens, j, "(", ")") catch return false;
            // Type expr lives strictly inside the parens: tokens[j+1 .. close].
            const parsed = (try parseCodegenTypeExpr(allocator, tokens, j + 1, close, &owned_payload_tys)) orelse return false;
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


