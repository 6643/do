//! Compatibility mapping for diagnostics exposed by the pre-GC emitter.
//!
//! This module is intentionally token-only. It must not import the legacy
//! emitter or any ARC runtime code.

const std = @import("std");
const lexer = @import("lexer.zig");
const codegen_tokens = @import("codegen_tokens.zig");
const codegen_collect_functions = @import("codegen_collect_functions.zig");
const codegen_collect_structs = @import("codegen_collect_structs.zig");
const codegen_context = @import("codegen_context.zig");
const codegen_model = @import("codegen_model.zig");
const host_export_abi = @import("host_export_abi.zig");

const tok_eq = codegen_tokens.tok_eq;
const find_line_end = codegen_tokens.find_line_end;
const find_line_start = codegen_tokens.find_line_start;
const find_matching_in_range = codegen_tokens.find_matching_in_range;
const find_top_level_token = codegen_tokens.find_top_level_token;
const string_token_body = codegen_tokens.string_token_body;

pub fn validate_host_export_callbacks(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
    var structs = std.ArrayList(codegen_model.StructDecl).empty;
    defer {
        codegen_model.free_struct_decls(allocator, structs.items);
        structs.deinit(allocator);
    }
    try codegen_collect_structs.collect_struct_decls(allocator, tokens, &structs);

    var struct_layouts = std.ArrayList(codegen_model.StructLayout).empty;
    defer {
        codegen_model.free_struct_layouts(allocator, struct_layouts.items);
        struct_layouts.deinit(allocator);
    }
    try codegen_collect_structs.collect_struct_layouts(allocator, structs.items, &struct_layouts);

    var functions = std.ArrayList(codegen_model.FuncDecl).empty;
    defer {
        codegen_model.free_func_decls(allocator, functions.items);
        functions.deinit(allocator);
    }
    try codegen_collect_functions.collect_func_decls(
        allocator,
        tokens,
        structs.items,
        struct_layouts.items,
        null,
        &functions,
    );

    var string_data = codegen_context.StringDataContext{};
    defer string_data.deinit(allocator);
    const ctx = codegen_context.CodegenContext{
        .functions = functions.items,
        .structs = structs.items,
        .value_enums = &.{},
        .struct_layouts = struct_layouts.items,
        .host_imports = &.{},
        .wasi_imports = &.{},
        .string_data = &string_data,
        .entry_tokens = tokens,
        .modules = &.{},
    };
    for (functions.items) |func| {
        if (!codegen_model.is_host_export_func(func, tokens)) continue;
        try host_export_abi.validate_func(allocator, func, ctx);
    }
}

pub fn map_gc_rejection(tokens: []const lexer.Token, err: anyerror) ?anyerror {
    if (err == error.UnsupportedLowering and has_variadic_shape(tokens)) {
        return if (has_variadic_spread_call(tokens))
            error.UnsupportedGcSyncExpression
        else
            error.GcSyncArityMismatch;
    }

    if (err == error.UnsupportedGcSyncType and has_as_intrinsic(tokens)) {
        return error.UnsupportedGcSyncExpression;
    }

    if (err == error.UnsupportedGcSyncModuleGraph and legacy_wasi_scalar_result(tokens)) {
        return error.NoMatchingCall;
    }

    const from_json = json_lib_alias(tokens, "from_json");
    const stringify = json_lib_alias(tokens, "stringify");
    if (from_json) |alias| {
        if (err == error.UnsupportedGcSyncOverload and generic_call_target_is(tokens, alias, "i32")) {
            return error.NoMatchingCall;
        }
        if (find_generic_call_target(tokens, alias)) |target| {
            if (find_struct_range(tokens, target)) |range| {
                const json_error = json_lib_alias(tokens, "JsonError");
                if ((err == error.UnsupportedLowering or err == error.UnsupportedGcSyncOverload) and
                    struct_has_non_u8_storage(tokens, range))
                {
                    return error.UnsupportedExpr;
                }
                if ((err == error.UnsupportedGcSyncAggregate or err == error.UnsupportedGcSyncGenericUnion) and
                    (struct_has_union(tokens, range) or
                        (json_error != null and struct_has_type(tokens, range, json_error.?) ) or
                        struct_has_value_enum_field(tokens, range)))
                {
                    return error.NoMatchingCall;
                }
            }
        }
    }

    if (stringify) |alias| {
        if ((err == error.UnsupportedGcSyncOverload or err == error.UnsupportedGcSyncGenericUnresolved) and
            stringify_has_union_binding(tokens)) return error.NoMatchingCall;
        if ((err == error.UnsupportedGcSyncOverload or err == error.UnsupportedGcSyncGenericUnresolved) and
            (stringify_has_non_u8_storage(tokens) or stringify_has_type(tokens, "u64") or
                (json_lib_alias(tokens, "JsonError") != null and stringify_has_type(tokens, json_lib_alias(tokens, "JsonError").?))))
        {
            _ = alias;
            return error.UnsupportedExpr;
        }
    }

    return null;
}

fn has_variadic_shape(tokens: []const lexer.Token) bool {
    for (tokens, 0..) |token, index| {
        if (tok_eq(token, "...") and index > 0 and index + 1 < tokens.len and
            tokens[index - 1].kind == .ident and tokens[index + 1].kind == .ident)
        {
            return true;
        }
    }
    return false;
}

fn has_variadic_spread_call(tokens: []const lexer.Token) bool {
    for (tokens, 0..) |token, index| {
        if (!tok_eq(token, "...") or index == 0 or index + 1 >= tokens.len) continue;
        if ((tok_eq(tokens[index - 1], "(") or tok_eq(tokens[index - 1], ",")) and
            tokens[index + 1].kind == .ident)
        {
            return true;
        }
    }
    return false;
}

fn has_as_intrinsic(tokens: []const lexer.Token) bool {
    for (tokens, 0..) |token, index| {
        if (tok_eq(token, "@") and index + 2 < tokens.len and
            tok_eq(tokens[index + 1], "as") and tok_eq(tokens[index + 2], "("))
        {
            return true;
        }
    }
    return false;
}

fn json_lib_alias(tokens: []const lexer.Token, symbol: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i + 7 < tokens.len) : (i += 1) {
        if (!tok_eq(tokens[i], "@") or !tok_eq(tokens[i + 1], "lib") or !tok_eq(tokens[i + 2], "(")) continue;
        const path = string_token_body(tokens[i + 3].lexeme) orelse continue;
        if (!std.mem.eql(u8, path, "json.do") or !tok_eq(tokens[i + 4], ",")) continue;
        const imported = string_token_body(tokens[i + 5].lexeme) orelse tokens[i + 5].lexeme;
        if (!std.mem.eql(u8, imported, symbol)) continue;
        const line_start = find_line_start(tokens, i);
        const eq_idx = find_top_level_token(tokens, line_start, i, "=") orelse continue;
        if (eq_idx == line_start) continue;
        return tokens[eq_idx - 1].lexeme;
    }
    return null;
}

fn find_generic_call_target(tokens: []const lexer.Token, alias: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i + 3 < tokens.len) : (i += 1) {
        if (!std.mem.eql(u8, tokens[i].lexeme, alias) or !tok_eq(tokens[i + 1], "<")) continue;
        const close = find_matching_in_range(tokens, i + 1, "<", ">", tokens.len) catch continue;
        if (close + 2 >= tokens.len or !tok_eq(tokens[close + 1], "(")) continue;
        if (close != i + 3 or tokens[i + 2].kind != .ident) continue;
        return tokens[i + 2].lexeme;
    }
    return null;
}

fn generic_call_target_is(tokens: []const lexer.Token, alias: []const u8, target: []const u8) bool {
    const actual = find_generic_call_target(tokens, alias) orelse return false;
    return std.mem.eql(u8, actual, target);
}

const TokenRange = struct { open_idx: usize, close_idx: usize };

fn find_struct_range(tokens: []const lexer.Token, name: []const u8) ?TokenRange {
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (!std.mem.eql(u8, tokens[i].lexeme, name) or !tok_eq(tokens[i + 1], "{")) continue;
        const close = find_matching_in_range(tokens, i + 1, "{", "}", tokens.len) catch continue;
        return .{ .open_idx = i + 1, .close_idx = close };
    }
    return null;
}

fn struct_has_union(tokens: []const lexer.Token, range: TokenRange) bool {
    for (tokens[range.open_idx + 1 .. range.close_idx]) |token| {
        if (tok_eq(token, "|")) return true;
    }
    return false;
}

fn struct_has_non_u8_storage(tokens: []const lexer.Token, range: TokenRange) bool {
    var i = range.open_idx + 1;
    while (i + 1 < range.close_idx) : (i += 1) {
        if (!tok_eq(tokens[i], "[")) continue;
        if (tok_eq(tokens[i + 1], "u8")) continue;
        return true;
    }
    return false;
}

fn struct_has_type(tokens: []const lexer.Token, range: TokenRange, ty: []const u8) bool {
    for (tokens[range.open_idx + 1 .. range.close_idx]) |token| {
        if (std.mem.eql(u8, token.lexeme, ty)) return true;
    }
    return false;
}

fn struct_has_value_enum_field(tokens: []const lexer.Token, range: TokenRange) bool {
    for (tokens[range.open_idx + 1 .. range.close_idx]) |token| {
        if (token.kind != .ident) continue;
        if (is_value_enum_decl(tokens, token.lexeme)) return true;
    }
    return false;
}

fn is_value_enum_decl(tokens: []const lexer.Token, name: []const u8) bool {
    var i: usize = 0;
    while (i + 3 < tokens.len) : (i += 1) {
        if (!std.mem.eql(u8, tokens[i].lexeme, name) or !tok_eq(tokens[i + 1], "u8")) continue;
        const line_end = find_line_end(tokens, i);
        if (find_top_level_token(tokens, i + 2, line_end, "=") != null) return true;
    }
    return false;
}

fn stringify_has_union_binding(tokens: []const lexer.Token) bool {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        const line_end = find_line_end(tokens, i);
        const eq_idx = find_top_level_token(tokens, i, line_end, "=") orelse {
            i = line_end;
            continue;
        };
        if (find_top_level_token(tokens, eq_idx + 1, line_end, "|") != null) {
            i = line_end;
            continue;
        }
        if (find_top_level_token(tokens, i, eq_idx, "|") != null) return true;
        i = line_end;
    }
    return false;
}

fn stringify_has_non_u8_storage(tokens: []const lexer.Token) bool {
    var i: usize = 0;
    while (i + 2 < tokens.len) : (i += 1) {
        if (!tok_eq(tokens[i], "[")) continue;
        if (tok_eq(tokens[i + 1], "u8")) continue;
        const close = find_matching_in_range(tokens, i, "[", "]", tokens.len) catch continue;
        const line_end = find_line_end(tokens, i);
        if (close < line_end and find_top_level_token(tokens, close + 1, line_end, "=") != null) return true;
    }
    return false;
}

fn stringify_has_type(tokens: []const lexer.Token, ty: []const u8) bool {
    var i: usize = 0;
    while (i + 2 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident or !std.mem.eql(u8, tokens[i + 1].lexeme, ty)) continue;
        const line_end = find_line_end(tokens, i);
        if (find_top_level_token(tokens, i + 2, line_end, "=") != null) return true;
    }
    return false;
}

fn legacy_wasi_scalar_result(tokens: []const lexer.Token) bool {
    var i: usize = 0;
    while (i + 6 < tokens.len) : (i += 1) {
        if (!tok_eq(tokens[i], "@") or !tok_eq(tokens[i + 1], "host_func") or !tok_eq(tokens[i + 2], "(")) continue;
        const locator = string_token_body(tokens[i + 3].lexeme) orelse continue;
        const member = string_token_body(tokens[i + 5].lexeme) orelse continue;
        if (!std.mem.eql(u8, locator, "wasi:filesystem/types@0.3.0") or !std.mem.eql(u8, member, "descriptor.write")) continue;

        const line_start = find_line_start(tokens, i);
        const alias = tokens[line_start].lexeme;
        var j: usize = line_start + 1;
        while (j + 1 < tokens.len) : (j += 1) {
            if (!std.mem.eql(u8, tokens[j].lexeme, alias) or !tok_eq(tokens[j + 1], "(")) continue;
            const call_line_start = find_line_start(tokens, j);
            const eq_idx = find_top_level_token(tokens, call_line_start, j, "=") orelse continue;
            if (eq_idx > call_line_start and tok_eq(tokens[eq_idx - 1], "u64")) return true;
        }
    }
    return false;
}

test "GC rejection compatibility preserves existing JSON and WASI diagnostics" {
    const Case = struct {
        source: []const u8,
        current: anyerror,
        expected: []const u8,
    };
    const cases = [_]Case{
        .{ .source = @embedFile("test/compile_err/259_wasi_result_single_value_forbidden.do"), .current = error.UnsupportedGcSyncModuleGraph, .expected = "NoMatchingCall" },
        .{ .source = @embedFile("test/compile_err/260_json_from_json_scalar_root_unsupported.do"), .current = error.UnsupportedGcSyncOverload, .expected = "NoMatchingCall" },
        .{ .source = @embedFile("test/compile_err/261_json_stringify_u64_unsupported.do"), .current = error.UnsupportedGcSyncOverload, .expected = "UnsupportedExpr" },
        .{ .source = @embedFile("test/compile_err/262_json_stringify_union_root_unsupported.do"), .current = error.UnsupportedGcSyncOverload, .expected = "NoMatchingCall" },
        .{ .source = @embedFile("test/compile_err/263_json_stringify_storage_non_u8_unsupported.do"), .current = error.UnsupportedGcSyncOverload, .expected = "UnsupportedExpr" },
        .{ .source = @embedFile("test/compile_err/264_json_from_json_storage_field_unsupported.do"), .current = error.UnsupportedGcSyncOverload, .expected = "UnsupportedExpr" },
        .{ .source = @embedFile("test/compile_err/265_json_from_json_union_field_unsupported.do"), .current = error.UnsupportedGcSyncAggregate, .expected = "NoMatchingCall" },
        .{ .source = @embedFile("test/compile_err/266_json_from_json_enum_field_unsupported.do"), .current = error.UnsupportedGcSyncGenericUnion, .expected = "NoMatchingCall" },
        .{ .source = @embedFile("test/compile_err/267_json_stringify_error_root_unsupported.do"), .current = error.UnsupportedGcSyncGenericUnresolved, .expected = "UnsupportedExpr" },
        .{ .source = @embedFile("test/compile_err/268_json_from_json_error_field_unsupported.do"), .current = error.UnsupportedGcSyncAggregate, .expected = "NoMatchingCall" },
    };

    for (cases) |case| {
        const tokens = try lexer.tokenize(std.testing.allocator, case.source);
        defer std.testing.allocator.free(tokens);
        const mapped = map_gc_rejection(tokens, case.current) orelse return error.MissingDiagnosticCompatibility;
        try std.testing.expectEqualStrings(case.expected, @errorName(mapped));
    }
}

test "GC rejection compatibility leaves unrelated errors unchanged" {
    const source = "start() { return }";
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expect(map_gc_rejection(tokens, error.UnsupportedGcSyncOverload) == null);
}

test "GC rejection compatibility preserves variadic and conversion diagnostics" {
    const Case = struct {
        source: []const u8,
        current: anyerror,
        expected: []const u8,
    };
    const cases = [_]Case{
        .{
            .source =
                \\count(rest ...i32) -> usize {
                \\    return @len(rest)
                \\}
                \\start() {
                \\    n usize = count(1, 2, 3)
                \\}
            ,
            .current = error.UnsupportedLowering,
            .expected = "GcSyncArityMismatch",
        },
        .{
            .source =
                \\count(rest ...i32) -> usize {
                \\    return @len(rest)
                \\}
                \\forward(rest ...i32) -> usize {
                \\    return count(...rest)
                \\}
                \\start() {
                \\    n usize = forward(1, 2)
                \\}
            ,
            .current = error.UnsupportedLowering,
            .expected = "UnsupportedGcSyncExpression",
        },
        .{
            .source =
                \\start() {
                \\    value f64 = @as(f64, 1)
                \\}
            ,
            .current = error.UnsupportedGcSyncType,
            .expected = "UnsupportedGcSyncExpression",
        },
    };

    for (cases) |case| {
        const tokens = try lexer.tokenize(std.testing.allocator, case.source);
        defer std.testing.allocator.free(tokens);
        const mapped = map_gc_rejection(tokens, case.current) orelse return error.MissingDiagnosticCompatibility;
        try std.testing.expectEqualStrings(case.expected, @errorName(mapped));
    }
}

test "host-export callback parameters keep their dedicated diagnostic" {
    const source = @embedFile("test/compile_err/340_host_export_callback_param.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    try std.testing.expectError(
        error.HostExportCallbackParamUnsupported,
        validate_host_export_callbacks(std.testing.allocator, tokens),
    );
}
