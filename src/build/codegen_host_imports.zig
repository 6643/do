//! Env host import collect/parse (@host("env", member, sig)).
const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const codegen_tokens = @import("codegen_tokens.zig");
const codegen_names = @import("codegen_names.zig");
const model = @import("codegen_model.zig");
const context = @import("codegen_context.zig");

const tok_eq = codegen_tokens.tok_eq;
const find_matching_in_range = codegen_tokens.find_matching_in_range;
const find_line_end = codegen_tokens.find_line_end;
const is_line_start = codegen_tokens.is_line_start;
const find_arg_end = codegen_tokens.find_arg_end;
const find_top_level_token = codegen_tokens.find_top_level_token;
const trim_parens = codegen_tokens.trim_parens;
const string_token_body = codegen_tokens.string_token_body;
const public_decl_name = codegen_names.public_decl_name;
const append_fmt = codegen_names.append_fmt;

const HostImport = model.HostImport;
const CodegenError = model.CodegenError;
const LocalSet = context.LocalSet;
const storage_type_name_for_elem = context.storage_type_name_for_elem;
const module_tokens_equal = codegen_tokens.module_tokens_equal;
const string_literal_arg_lexeme = codegen_tokens.string_literal_arg_lexeme;
const append_mangled_type_name = codegen_names.append_mangled_type_name;
const module_scoped_symbol_name = codegen_names.module_scoped_symbol_name;

pub fn collect_env_host_imports(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    out: *std.ArrayList(HostImport),
) !void {
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
        if (!is_line_start(tokens, i)) continue;
        if (!is_env_host_import_start(tokens, i)) continue;

        const line_end = find_line_end(tokens, i);
        const import = try parse_env_host_import(allocator, tokens, i, line_end);
        errdefer allocator.free(import.params);
        try out.append(allocator, import);
        i = line_end - 1;
    }
}
pub fn collect_env_host_imports_from_modules(
    allocator: std.mem.Allocator,
    modules: []const imports.ModuleRecord,
    entry_tokens: []const lexer.Token,
    out: *std.ArrayList(HostImport),
) !void {
    for (modules, 0..) |module, module_idx| {
        if (module_tokens_equal(module.tokens, entry_tokens)) continue;

        var module_imports = std.ArrayList(HostImport).empty;
        defer {
            free_host_imports(allocator, module_imports.items);
            module_imports.deinit(allocator);
        }
        try collect_env_host_imports(allocator, module.tokens, &module_imports);
        for (module_imports.items) |*host_import| {
            if (find_host_import_for_tokens(out.items, module.tokens, host_import.source_alias) != null) continue;
            const emit_alias = try module_scoped_symbol_name(allocator, module_idx, host_import.source_alias);
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
pub fn parse_env_host_import(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    line_end: usize,
) !HostImport {
    // name = @host("env", "field", (...) -> T)
    const alias = public_decl_name(tokens[start_idx].lexeme);
    const locator = string_token_body(tokens[start_idx + 5].lexeme) orelse return error.InvalidImportDecl;
    if (!std.mem.eql(u8, locator, "env")) return error.InvalidImportDecl;
    if (!tok_eq(tokens[start_idx + 6], ",")) return error.InvalidImportDecl;
    const field = string_token_body(tokens[start_idx + 7].lexeme) orelse return error.InvalidImportDecl;
    if (!tok_eq(tokens[start_idx + 8], ",")) return error.InvalidImportDecl;
    const open_idx = start_idx + 9;
    if (open_idx >= line_end or !tok_eq(tokens[open_idx], "(")) return error.InvalidImportDecl;
    const close_idx = try find_matching_in_range(tokens, open_idx, "(", ")", line_end);
    if (close_idx + 1 >= line_end or !tok_eq(tokens[close_idx + 1], "-")) return error.InvalidImportDecl;
    if (close_idx + 2 >= line_end or !tok_eq(tokens[close_idx + 2], ">")) return error.InvalidImportDecl;

    var params = std.ArrayList([]const u8).empty;
    errdefer params.deinit(allocator);

    var i = open_idx + 1;
    while (i < close_idx) {
        if (tok_eq(tokens[i], ",")) {
            i += 1;
            continue;
        }
        try params.append(allocator, tokens[i].lexeme);
        i += 1;
        if (i < close_idx and tok_eq(tokens[i], ",")) i += 1;
    }

    const result_end = find_matching_in_range(tokens, start_idx + 4, "(", ")", line_end) catch return error.InvalidImportDecl;
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
pub fn free_host_imports(allocator: std.mem.Allocator, host_imports: []const HostImport) void {
    for (host_imports) |host_import| {
        if (host_import.owned_alias) allocator.free(host_import.alias);
        allocator.free(host_import.params);
    }
}
pub fn find_host_import(host_imports: []const HostImport, alias: []const u8) ?HostImport {
    for (host_imports) |host_import| {
        if (std.mem.eql(u8, host_import.alias, alias)) return host_import;
    }
    return null;
}
pub fn find_host_import_for_tokens(host_imports: []const HostImport, tokens: []const lexer.Token, alias: []const u8) ?HostImport {
    for (host_imports) |host_import| {
        if (!module_tokens_equal(host_import.tokens, tokens)) continue;
        if (std.mem.eql(u8, host_import.source_alias, alias)) return host_import;
    }
    return null;
}
pub fn is_env_host_import_start(tokens: []const lexer.Token, idx: usize) bool {
    // name = @host("env", "field", ...)
    const line_end = find_line_end(tokens, idx);
    if (idx + 9 >= line_end) return false;
    if (tokens[idx].kind != .ident) return false;
    if (!tok_eq(tokens[idx + 1], "=")) return false;
    if (!tok_eq(tokens[idx + 2], "@")) return false;
    if (tokens[idx + 3].kind != .ident or !std.mem.eql(u8, tokens[idx + 3].lexeme, "host")) return false;
    if (!tok_eq(tokens[idx + 4], "(")) return false;
    if (tokens[idx + 5].kind != .string) return false;
    const locator = string_token_body(tokens[idx + 5].lexeme) orelse return false;
    if (!std.mem.eql(u8, locator, "env")) return false;
    if (!tok_eq(tokens[idx + 6], ",")) return false;
    if (tokens[idx + 7].kind != .string) return false;
    if (!tok_eq(tokens[idx + 8], ",")) return false;
    return true;
}
pub fn host_call_args_match(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, host_import: HostImport) bool {
    var param_idx: usize = 0;
    var arg_start = start_idx;
    while (arg_start < end_idx) {
        const arg_end = find_arg_end(tokens, arg_start, end_idx);
        if (string_literal_arg_lexeme(tokens, arg_start, arg_end)) |_| {
            if (!host_param_is_ptr_len(host_import, param_idx)) return false;
            param_idx += 2;
        } else if (host_arg_could_be_storage_ptr_len_syntax(tokens, arg_start, arg_end) and host_param_is_ptr_len(host_import, param_idx)) {
            param_idx += 2;
        } else {
            if (param_idx >= host_import.params.len) return false;
            param_idx += 1;
        }
        arg_start = arg_end;
        if (arg_start < end_idx) {
            if (!tok_eq(tokens[arg_start], ",")) return false;
            arg_start += 1;
        }
    }
    return param_idx == host_import.params.len;
}
pub fn host_param_is_ptr_len(host_import: HostImport, param_idx: usize) bool {
    if (param_idx + 1 >= host_import.params.len) return false;
    return std.mem.eql(u8, host_import.params[param_idx], "i32") and
        std.mem.eql(u8, host_import.params[param_idx + 1], "i32");
}
pub fn host_arg_could_be_storage_ptr_len_syntax(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    const range = trim_parens(tokens, start_idx, end_idx);
    return range.end == range.start + 1 and tokens[range.start].kind == .ident;
}
