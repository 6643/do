//! Module import resolution, reachability, and string-data collection for codegen.
const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const codegen_tokens = @import("codegen_tokens.zig");
const codegen_names = @import("codegen_names.zig");
const model = @import("codegen_model.zig");
const context = @import("codegen_context.zig");
const codegen_wasi_registry = @import("codegen_wasi_registry.zig");
const codegen_host_imports = @import("codegen_host_imports.zig");

const tok_eq = codegen_tokens.tok_eq;
const find_matching = codegen_tokens.find_matching;
const find_matching_in_range = codegen_tokens.find_matching_in_range;
const find_line_end = codegen_tokens.find_line_end;
const findLineStart = codegen_tokens.find_line_start;
const is_line_start = codegen_tokens.is_line_start;
const find_top_level_token = codegen_tokens.find_top_level_token;
const find_arg_end = codegen_tokens.find_arg_end;
const trim_parens = codegen_tokens.trim_parens;
const string_token_body = codegen_tokens.string_token_body;
const publicDeclName = codegen_names.public_decl_name;
const decodeQuotedStringToken = codegen_tokens.decode_quoted_string_token;
const append_fmt = codegen_names.append_fmt;
const Range = codegen_tokens.Range;
const module_tokens_equal = codegen_tokens.module_tokens_equal;
const find_token = codegen_tokens.find_token;
const find_start_func = codegen_tokens.find_start_func;
const isUserFuncDeclStart = codegen_tokens.is_user_func_decl_start;
const isTypedBindingRhsCall = codegen_tokens.is_typed_binding_rhs_call;
const isBareHostCallStatement = codegen_tokens.is_bare_host_call_statement;
const stringLiteralArgLexeme = codegen_tokens.string_literal_arg_lexeme;
const isPublicTypeName = codegen_names.is_public_type_name;
const is_error_type_name = codegen_names.is_error_type_name;
const is_base_int_type_name = codegen_names.is_base_int_type_name;
const isCoreWasmCallName = codegen_names.is_core_wasm_call_name;
const is_core_wasm_scalar = codegen_names.is_core_wasm_scalar;

const HostImport = model.HostImport;
const CodegenContext = context.CodegenContext;
const CodegenImportPrefix = model.CodegenImportPrefix;
const CodegenImportRef = model.CodegenImportRef;
const ImportedScalarConst = model.ImportedScalarConst;
const ImportedAliasContext = model.ImportedAliasContext;
const ReachVisit = model.ReachVisit;
const StringData = model.StringData;
const StringDataContext = context.StringDataContext;
const ValueEnumDecl = model.ValueEnumDecl;
const PayloadEnumDecl = model.PayloadEnumDecl;
const StructDecl = model.StructDecl;
const ExprCallHead = model.ExprCallHead;

const WASI_BINDING_ENTRY_SOURCE = codegen_wasi_registry.WASI_BINDING_ENTRY_SOURCE;
const WasiHostImport = codegen_wasi_registry.WasiHostImport;
const freeWasiHostImports = codegen_wasi_registry.free_wasi_host_imports;
const collectWasiHostImports = codegen_wasi_registry.collect_wasi_host_imports;
const findWasiHostImport = codegen_wasi_registry.find_wasi_host_import;
const findWasiHostImportBySource = codegen_wasi_registry.find_wasi_host_import_by_source;
const wasiHostImportUseIsLowerableAtCall = codegen_wasi_registry.wasi_host_import_use_is_lowerable_at_call;
const wasi_lowering = codegen_wasi_registry.wasi_lowering;
const parseWasiLinkAtArgs = codegen_wasi_registry.parse_wasi_link_at_args;

const find_host_import_for_tokens = codegen_host_imports.find_host_import_for_tokens;
const host_call_args_match = codegen_host_imports.host_call_args_match;
const host_param_is_ptr_len = codegen_host_imports.host_param_is_ptr_len;
const host_arg_could_be_storage_ptr_len_syntax = codegen_host_imports.host_arg_could_be_storage_ptr_len_syntax;

const test_runner = @import("test_runner.zig");

pub fn validate_host_import_build_uses(tokens: []const lexer.Token, host_imports: []const HostImport) !void {
    if (host_imports.len == 0) return;

    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        const host_import = find_host_import_for_tokens(host_imports, tokens, tokens[i].lexeme) orelse continue;
        if (i + 1 >= tokens.len or !tok_eq(tokens[i + 1], "(")) continue;

        const close_paren = find_matching(tokens, i + 1, "(", ")") catch return error.InvalidCallArgList;
        if (!host_call_args_match(tokens, i + 2, close_paren, host_import)) return error.NoMatchingCall;
        if (isBareHostCallStatement(tokens, i, close_paren) and host_import.result != null) return error.NoMatchingCall;
        if (isTypedBindingRhsCall(tokens, i) and host_import.result == null) return error.NoMatchingCall;
        i = close_paren;
    }
}

pub fn validate_reachable_wasi_host_import_build_uses(
    allocator: std.mem.Allocator,
    entry_tokens: []const lexer.Token,
    graph: *const imports.ModuleGraph,
) !void {
    const root_idx = find_root_module_index(graph.modules, entry_tokens) orelse return;

    var stack = std.ArrayList(ReachVisit).empty;
    defer stack.deinit(allocator);

    var visited = std.ArrayList(ReachVisit).empty;
    defer visited.deinit(allocator);

    try collect_start_body_calls(allocator, graph.modules[root_idx].tokens, root_idx, &stack);
    try collect_all_function_body_calls(allocator, graph.modules[root_idx].tokens, root_idx, &stack);
    try validate_reachable_wasi_host_import_stack(allocator, graph, &stack, &visited);
}

pub fn validate_reachable_wasi_host_import_build_uses_from_tests(
    allocator: std.mem.Allocator,
    entry_tokens: []const lexer.Token,
    graph: *const imports.ModuleGraph,
) !void {
    const root_idx = find_root_module_index(graph.modules, entry_tokens) orelse return;

    var stack = std.ArrayList(ReachVisit).empty;
    defer stack.deinit(allocator);

    var visited = std.ArrayList(ReachVisit).empty;
    defer visited.deinit(allocator);

    try collect_test_body_calls(allocator, graph.modules[root_idx].tokens, root_idx, &stack);
    try collect_all_function_body_calls(allocator, graph.modules[root_idx].tokens, root_idx, &stack);
    try validate_reachable_wasi_host_import_stack(allocator, graph, &stack, &visited);
}

pub fn validate_reachable_wasi_host_import_stack(
    allocator: std.mem.Allocator,
    graph: *const imports.ModuleGraph,
    stack: *std.ArrayList(ReachVisit),
    visited: *std.ArrayList(ReachVisit),
) !void {
    while (stack.items.len != 0) {
        const visit = stack.pop().?;
        if (has_reach_visit(visited.items, visit)) continue;
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

        if (find_codegen_import_by_alias(module.tokens, visit.name)) |import_ref| {
            if (find_imported_module_index(allocator, graph, visit.module_idx, import_ref)) |child_idx| {
                try push_reach_visit(allocator, stack, .{
                    .module_idx = child_idx,
                    .name = import_ref.target,
                });
            }
            continue;
        }

        try collect_function_body_calls(allocator, module.tokens, visit.module_idx, visit.name, stack);
    }
}

pub fn find_root_module_index(modules: []const imports.ModuleRecord, entry_tokens: []const lexer.Token) ?usize {
    for (modules, 0..) |module, idx| {
        if (module_tokens_equal(module.tokens, entry_tokens)) return idx;
    }
    return null;
}

pub fn wasi_source_for_tokens(ctx: CodegenContext, tokens: []const lexer.Token) []const u8 {
    if (module_tokens_equal(tokens, ctx.entry_tokens)) return WASI_BINDING_ENTRY_SOURCE;
    for (ctx.modules) |module| {
        if (module_tokens_equal(tokens, module.tokens)) return module.path;
    }
    return WASI_BINDING_ENTRY_SOURCE;
}

pub fn find_wasi_host_import_for_tokens(ctx: CodegenContext, tokens: []const lexer.Token, alias: []const u8) ?WasiHostImport {
    const source = wasi_source_for_tokens(ctx, tokens);
    return findWasiHostImportBySource(ctx.wasi_imports, source, alias);
}

pub fn has_reach_visit(items: []const ReachVisit, target: ReachVisit) bool {
    for (items) |item| {
        if (item.module_idx == target.module_idx and std.mem.eql(u8, item.name, target.name)) return true;
    }
    return false;
}

pub fn push_reach_visit(
    allocator: std.mem.Allocator,
    stack: *std.ArrayList(ReachVisit),
    visit: ReachVisit,
) !void {
    if (isCoreWasmCallName(visit.name)) return;
    try stack.append(allocator, visit);
}

pub fn collect_start_body_calls(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    module_idx: usize,
    out: *std.ArrayList(ReachVisit),
) !void {
    const start_idx = find_start_func(tokens) orelse return;
    const close_params = find_matching(tokens, start_idx + 1, "(", ")") catch return;
    const open_body = find_token(tokens, close_params + 1, tokens.len, "{") orelse return;
    const close_body = find_matching(tokens, open_body, "{", "}") catch return;
    try collect_call_names_in_range(allocator, tokens, module_idx, open_body + 1, close_body, out);
}

pub fn collect_all_function_body_calls(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    module_idx: usize,
    out: *std.ArrayList(ReachVisit),
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
        if (!isUserFuncDeclStart(tokens, i)) continue;

        const close_params = find_matching(tokens, i + 1, "(", ")") catch continue;
        const open_body = find_token(tokens, close_params + 1, tokens.len, "{") orelse continue;
        const close_body = find_matching(tokens, open_body, "{", "}") catch continue;
        try collect_call_names_in_range(allocator, tokens, module_idx, open_body + 1, close_body, out);
        i = close_body;
    }
}

pub fn collect_test_body_calls(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    module_idx: usize,
    out: *std.ArrayList(ReachVisit),
) !void {
    const test_decls = try test_runner.collect_top_level_tests(allocator, tokens);
    defer allocator.free(test_decls);

    for (test_decls) |decl| {
        try collect_call_names_in_range(allocator, tokens, module_idx, decl.body_start, decl.body_end, out);
    }
}

pub fn collect_function_body_calls(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    module_idx: usize,
    func_name: []const u8,
    out: *std.ArrayList(ReachVisit),
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
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, publicDeclName(tokens[i].lexeme), func_name)) continue;
        if (!tok_eq(tokens[i + 1], "(")) continue;

        const close_params = find_matching(tokens, i + 1, "(", ")") catch continue;
        const open_body = find_token(tokens, close_params + 1, tokens.len, "{") orelse continue;
        const close_body = find_matching(tokens, open_body, "{", "}") catch continue;
        try collect_call_names_in_range(allocator, tokens, module_idx, open_body + 1, close_body, out);
        i = close_body;
    }
}

pub fn collect_call_names_in_range(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    module_idx: usize,
    start_idx: usize,
    end_idx: usize,
    out: *std.ArrayList(ReachVisit),
) !void {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        const call_head = call_head_at(tokens, i, end_idx) orelse continue;
        try collect_call_names_in_range(allocator, tokens, module_idx, call_head.args_start, call_head.args_end, out);
        if (!call_head.is_intrinsic and !is_loop_source_special_call_name(tokens[call_head.name_idx].lexeme)) {
            try push_reach_visit(allocator, out, .{
                .module_idx = module_idx,
                .name = tokens[call_head.name_idx].lexeme,
                .call_idx = call_head.name_idx,
            });
        }
        i = call_head.args_end;
    }
}

pub fn is_loop_source_special_call_name(name: []const u8) bool {
    return std.mem.eql(u8, name, "fields") or std.mem.eql(u8, name, "recv");
}

pub fn find_codegen_import_by_alias(tokens: []const lexer.Token, alias: []const u8) ?CodegenImportRef {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        const import_ref = parse_codegen_import(tokens, i) orelse continue;
        if (std.mem.eql(u8, import_ref.alias, alias)) return import_ref;
        i = find_line_end(tokens, i) - 1;
    }
    return null;
}

pub fn parse_codegen_import(tokens: []const lexer.Token, idx: usize) ?CodegenImportRef {
    const line_end = find_line_end(tokens, idx);
    if (idx + 8 >= line_end) return null;
    if (tokens[idx].kind != .ident) return null;
    if (!tok_eq(tokens[idx + 1], "=")) return null;
    if (!tok_eq(tokens[idx + 2], "@")) return null;
    if (tokens[idx + 3].kind != .ident or !std.mem.eql(u8, tokens[idx + 3].lexeme, "lib")) return null;
    if (!tok_eq(tokens[idx + 4], "(")) return null;
    if (tokens[idx + 5].kind != .string) return null;
    if (!tok_eq(tokens[idx + 6], ",")) return null;
    if (tokens[idx + 7].kind != .ident) return null;
    if (!tok_eq(tokens[idx + 8], ")")) return null;
    if (idx + 9 != line_end) return null;

    var file_path = string_token_body(tokens[idx + 5].lexeme) orelse return null;
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

pub fn imported_scalar_const(ctx: CodegenContext, tokens: []const lexer.Token, alias: []const u8) ?ImportedScalarConst {
    const import_ctx = imported_alias_context_for_tokens(ctx.imported_alias_ctx, tokens) orelse return null;
    const import_ref = find_codegen_import_by_alias(tokens, alias) orelse return null;
    const child_idx = find_imported_module_index_no_alloc(import_ctx.graph, import_ctx.module_idx, import_ref) orelse return null;
    return local_scalar_const(import_ctx.graph.modules[child_idx].tokens, import_ref.target);
}

pub fn find_imported_module_index_no_alloc(
    graph: *const imports.ModuleGraph,
    current_idx: usize,
    import_ref: CodegenImportRef,
) ?usize {
    for (graph.modules, 0..) |module, idx| {
        if (module_matches_import_path(graph, current_idx, module.path, import_ref)) return idx;
    }
    return null;
}

pub fn module_matches_import_path(
    graph: *const imports.ModuleGraph,
    current_idx: usize,
    path: []const u8,
    import_ref: CodegenImportRef,
) bool {
    return switch (import_ref.prefix) {
        .std => path_has_base_and_file(path, "lib", import_ref.file_path),
        .dep => path_has_base_and_file(path, graph.dep_root, import_ref.file_path),
        .local => path_has_base_and_file(path, std.fs.path.dirname(graph.modules[current_idx].path) orelse ".", import_ref.file_path),
    };
}

pub fn path_has_base_and_file(path: []const u8, base: []const u8, file_path: []const u8) bool {
    if (std.mem.eql(u8, base, ".")) return std.mem.eql(u8, path, file_path) or path_has_base_and_file(path, "", file_path);
    if (base.len == 0) return std.mem.eql(u8, path, file_path);
    if (!std.mem.startsWith(u8, path, base)) return false;
    if (path.len != base.len + 1 + file_path.len) return false;
    if (path[base.len] != '/') return false;
    return std.mem.eql(u8, path[base.len + 1 ..], file_path);
}

pub fn local_scalar_const(tokens: []const lexer.Token, name: []const u8) ?ImportedScalarConst {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i + 4 < tokens.len) : (i += 1) {
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
        if (tokens[i].kind != .ident or !std.mem.eql(u8, tokens[i].lexeme, name)) continue;
        if (tokens[i + 1].kind != .ident or !is_core_wasm_scalar(tokens[i + 1].lexeme)) return null;
        if (!tok_eq(tokens[i + 2], "=")) return null;
        const line_end = find_line_end(tokens, i);
        if (i + 4 != line_end) return null;
        const value = tokens[i + 3];
        if (value.kind != .number) return null;
        return .{ .ty = tokens[i + 1].lexeme, .value = value.lexeme };
    }
    return null;
}

pub fn find_imported_module_index(
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
            return find_module_by_path(modules, resolved);
        },
        .std => {
            const resolved = std.fs.path.join(allocator, &.{ "lib", import_ref.file_path }) catch return null;
            defer allocator.free(resolved);
            return find_module_by_path(modules, resolved);
        },
        .dep => {
            const resolved = std.fs.path.join(allocator, &.{ graph.dep_root, import_ref.file_path }) catch return null;
            defer allocator.free(resolved);
            return find_module_by_path(modules, resolved);
        },
    }
}

pub fn find_module_by_path(modules: []const imports.ModuleRecord, path: []const u8) ?usize {
    for (modules, 0..) |module, idx| {
        if (std.mem.eql(u8, module.path, path)) return idx;
    }
    return null;
}

pub fn is_value_enum_decl_start(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 2 < tokens.len and
        is_line_start(tokens, idx) and
        tokens[idx].kind == .ident and
        isPublicTypeName(publicDeclName(tokens[idx].lexeme)) and
        !is_error_type_name(publicDeclName(tokens[idx].lexeme)) and
        is_base_int_type_name(tokens[idx + 1].lexeme) and
        tok_eq(tokens[idx + 2], "=");
}

/// `Message = Quit | Text([u8])` — mirrors sema `is_payload_enum_decl_start` (codegen copy).
/// `Message = Quit | Text([u8])` — mirrors sema `is_payload_enum_decl_start` (codegen copy).
pub fn is_payload_enum_decl_start(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 2 >= tokens.len) return false;
    if (!is_line_start(tokens, idx)) return false;
    if (tokens[idx].kind != .ident) return false;
    if (!isPublicTypeName(publicDeclName(tokens[idx].lexeme))) return false;
    if (is_error_type_name(publicDeclName(tokens[idx].lexeme))) return false;
    if (is_value_enum_decl_start(tokens, idx)) return false;
    if (idx + 2 < tokens.len and tok_eq(tokens[idx + 1], "error") and tok_eq(tokens[idx + 2], "=")) return false;
    if (!tok_eq(tokens[idx + 1], "=")) return false;
    if (tok_eq(tokens[idx + 2], "@")) return false;

    const line_end = find_line_end(tokens, idx);
    var j = idx + 2;
    var saw_case = false;
    var expect_case = true;
    while (j < line_end) {
        if (!expect_case) {
            if (!tok_eq(tokens[j], "|")) return false;
            expect_case = true;
            j += 1;
            continue;
        }
        if (tokens[j].kind != .ident) return false;
        if (!isPublicTypeName(publicDeclName(tokens[j].lexeme))) return false;
        j += 1;
        if (j < line_end and tok_eq(tokens[j], "(")) {
            const close = find_matching(tokens, j, "(", ")") catch return false;
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

pub fn find_value_enum_decl(value_enums: []const ValueEnumDecl, name: []const u8) ?ValueEnumDecl {
    for (value_enums) |decl| {
        if (std.mem.eql(u8, decl.name, name)) return decl;
    }
    return null;
}

pub fn find_payload_enum_decl(payload_enums: []const PayloadEnumDecl, name: []const u8) ?PayloadEnumDecl {
    for (payload_enums) |decl| {
        if (std.mem.eql(u8, decl.name, name)) return decl;
    }
    return null;
}

pub fn find_payload_enum_decl_line_by_name(tokens: []const lexer.Token, name: []const u8) ?usize {
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
        if (std.mem.eql(u8, publicDeclName(tokens[i].lexeme), name)) return i;
        i = find_line_end(tokens, i) - 1;
    }
    return null;
}

pub fn find_value_enum_decl_line_by_name(tokens: []const lexer.Token, name: []const u8) ?usize {
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
        if (std.mem.eql(u8, publicDeclName(tokens[i].lexeme), name)) return i;
        i = find_line_end(tokens, i) - 1;
    }
    return null;
}

pub fn find_value_enum_decl_line_by_branch(tokens: []const lexer.Token, branch_name: []const u8) ?usize {
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
        if (value_enum_line_has_branch(tokens, i, branch_name)) return i;
        i = find_line_end(tokens, i) - 1;
    }
    return null;
}

pub fn value_enum_line_has_branch(tokens: []const lexer.Token, enum_idx: usize, branch_name: []const u8) bool {
    const line_end = find_line_end(tokens, enum_idx);
    var j = enum_idx + 3;
    while (j + 3 < line_end) {
        if (tok_eq(tokens[j], "|")) {
            j += 1;
            continue;
        }
        if (tokens[j].kind == .ident and std.mem.eql(u8, publicDeclName(tokens[j].lexeme), branch_name)) return true;
        j += 4;
    }
    return false;
}

pub fn collect_string_data_for_host_calls(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    host_imports: []const HostImport,
    out: *StringDataContext,
) !void {
    if (host_imports.len == 0) return;

    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        const host_import = find_host_import_for_tokens(host_imports, tokens, tokens[i].lexeme) orelse continue;
        if (!tok_eq(tokens[i + 1], "(")) continue;

        const close_paren = find_matching(tokens, i + 1, "(", ")") catch return error.InvalidCallArgList;
        var arg_start = i + 2;
        var param_idx: usize = 0;
        while (arg_start < close_paren) {
            const arg_end = find_arg_end(tokens, arg_start, close_paren);
            if (stringLiteralArgLexeme(tokens, arg_start, arg_end)) |lexeme| {
                if (!host_param_is_ptr_len(host_import, param_idx)) return error.NoMatchingCall;
                _ = try out.intern(allocator, lexeme);
                param_idx += 2;
            } else if (host_arg_could_be_storage_ptr_len_syntax(tokens, arg_start, arg_end) and host_param_is_ptr_len(host_import, param_idx)) {
                param_idx += 2;
            } else {
                param_idx += 1;
            }
            arg_start = arg_end;
            if (arg_start < close_paren and tok_eq(tokens[arg_start], ",")) arg_start += 1;
        }
        i = close_paren;
    }
}

pub fn collect_string_data_for_wasi_host_calls(
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
        const lowering = wasi_lowering(import) orelse continue;
        if (!lowering.result_link_at_error) continue;
        if (!tok_eq(tokens[i + 1], "(")) continue;

        const close_paren = find_matching(tokens, i + 1, "(", ")") catch return error.InvalidCallArgList;
        const args = parseWasiLinkAtArgs(tokens, i + 2, close_paren) orelse return error.NoMatchingCall;
        if (stringLiteralArgLexeme(tokens, args.old_path_start, args.old_path_end)) |old_path| {
            _ = try out.intern(allocator, old_path);
        } else if (!host_arg_could_be_storage_ptr_len_syntax(tokens, args.old_path_start, args.old_path_end)) {
            return error.NoMatchingCall;
        }
        if (stringLiteralArgLexeme(tokens, args.new_path_start, args.new_path_end)) |new_path| {
            _ = try out.intern(allocator, new_path);
        } else if (!host_arg_could_be_storage_ptr_len_syntax(tokens, args.new_path_start, args.new_path_end)) {
            return error.NoMatchingCall;
        }
        i = close_paren;
    }
}

pub fn collect_string_data_for_storage_literals(
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
            tok_eq(tokens[i + 1], "[") and
            tok_eq(tokens[i + 2], "u8") and
            tok_eq(tokens[i + 3], "]") and
            tok_eq(tokens[i + 4], "="))
            i + 4
        else if (tok_eq(tokens[i + 1], "text") and tok_eq(tokens[i + 2], "="))
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
        if (!has_borrowed_name(storage_names.items, tokens[i].lexeme)) continue;
        if (!tok_eq(tokens[i + 1], "=")) continue;
        if (tokens[i + 2].kind != .string) continue;
        _ = try out.intern(allocator, tokens[i + 2].lexeme);
    }

    i = 0;
    var depth_brace: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace == 0) continue;
        if (tokens[i].kind != .string) continue;
        if (tokens[i].lexeme.len < 2 or tokens[i].lexeme[0] != '"') continue;
        _ = try out.intern(allocator, tokens[i].lexeme);
    }
}

pub fn collect_string_data_for_struct_field_names(
    allocator: std.mem.Allocator,
    structs: []const StructDecl,
    out: *StringDataContext,
) !void {
    for (structs) |decl| {
        for (decl.fields) |field| {
            const field_name = publicDeclName(field.name);
            _ = try out.intern_raw(allocator, field_name, field_name);
        }
    }
}

pub fn has_borrowed_name(names: []const []const u8, name: []const u8) bool {
    for (names) |candidate| {
        if (std.mem.eql(u8, candidate, name)) return true;
    }
    return false;
}

pub fn imported_alias_context_for_tokens(imported_alias_ctx: ?ImportedAliasContext, tokens: []const lexer.Token) ?ImportedAliasContext {
    const ctx = imported_alias_ctx orelse return null;
    const module_idx = find_root_module_index(ctx.graph.modules, tokens) orelse ctx.module_idx;
    return .{ .graph = ctx.graph, .module_idx = module_idx };
}

pub fn call_head_at(tokens: []const lexer.Token, idx: usize, limit: usize) ?ExprCallHead {
    if (idx >= limit) return null;

    var name_idx = idx;
    var is_intrinsic = false;
    if (tok_eq(tokens[name_idx], "@")) {
        name_idx += 1;
        if (name_idx >= limit) return null;
        is_intrinsic = true;
    } else if (idx > 0 and tok_eq(tokens[idx - 1], "@") and tokens[idx - 1].line == tokens[idx].line) {
        return null;
    }

    if (tokens[name_idx].kind != .ident) return null;
    if (name_idx + 1 >= limit) return null;

    var open_paren = name_idx + 1;
    var type_args_start: usize = 0;
    var type_args_end: usize = 0;
    if (tok_eq(tokens[open_paren], "<")) {
        if (is_intrinsic) return null;
        const close_angle = find_matching_in_range(tokens, open_paren, "<", ">", limit) catch return null;
        if (close_angle + 1 >= limit or !tok_eq(tokens[close_angle + 1], "(")) return null;
        type_args_start = open_paren + 1;
        type_args_end = close_angle;
        open_paren = close_angle + 1;
    } else if (!tok_eq(tokens[open_paren], "(")) {
        return null;
    }

    const close_paren = find_matching_in_range(tokens, open_paren, "(", ")", limit) catch return null;
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

pub fn expr_call_head(tokens: []const lexer.Token, range: Range) ?ExprCallHead {
    var name_idx = range.start;
    var is_intrinsic = false;
    if (tok_eq(tokens[name_idx], "@")) {
        if (name_idx + 1 >= range.end) return null;
        name_idx += 1;
        is_intrinsic = true;
    }
    if (tokens[name_idx].kind != .ident) return null;
    if (name_idx + 1 >= range.end) return null;
    var open_paren = name_idx + 1;
    var type_args_start: usize = 0;
    var type_args_end: usize = 0;
    if (tok_eq(tokens[open_paren], "<")) {
        if (is_intrinsic) return null;
        const close_angle = find_matching_in_range(tokens, open_paren, "<", ">", range.end) catch return null;
        if (close_angle + 1 >= range.end or !tok_eq(tokens[close_angle + 1], "(")) return null;
        type_args_start = open_paren + 1;
        type_args_end = close_angle;
        open_paren = close_angle + 1;
    } else if (!tok_eq(tokens[open_paren], "(")) {
        return null;
    }

    const close_paren = find_matching_in_range(tokens, open_paren, "(", ")", range.end) catch return null;
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

pub fn call_head_has_type_args(call_head: ExprCallHead) bool {
    return call_head.type_args_start != 0 or call_head.type_args_end != 0;
}
