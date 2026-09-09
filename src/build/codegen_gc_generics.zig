//! Generic function instantiation / type binding (extracted from codegen_pipeline).
const std = @import("std");
const lexer = @import("lexer.zig");
const codegen_tokens = @import("codegen_tokens.zig");
const codegen_names = @import("codegen_names.zig");
const model = @import("codegen_model.zig");
const context = @import("codegen_context.zig");
const codegen_collect_util = @import("codegen_collect_util.zig");
const codegen_collect_functions = @import("codegen_collect_functions.zig");
const codegen_collect_reflection = @import("codegen_collect_reflection.zig");
const codegen_imports = @import("codegen_imports.zig");
const codegen_body = @import("codegen_body.zig");
const codegen_storage_layout = @import("codegen_storage_layout.zig");
const codegen_union_layout = @import("codegen_union_layout.zig");
const imports = @import("imports.zig");
const test_runner = @import("test_runner.zig");

const LocalSet = context.LocalSet;
const FuncResultParse = model.FuncResultParse;
const free_func_params = model.free_func_params;
const free_func_result_items = model.free_func_result_items;
const CodegenContext = context.CodegenContext;
const CodegenError = model.CodegenError;
const StructDecl = model.StructDecl;
const StructLayout = model.StructLayout;
const FuncDecl = model.FuncDecl;
const FuncParam = model.FuncParam;
const FuncResultItem = model.FuncResultItem;
const HostImport = model.HostImport;
const GenericTypeBinding = model.GenericTypeBinding;
const PayloadEnumDecl = model.PayloadEnumDecl;
const ValueEnumDecl = model.ValueEnumDecl;
const ImportedAliasContext = model.ImportedAliasContext;
const StringDataContext = context.StringDataContext;
const ExprCallHead = model.ExprCallHead;
const UnionLayout = codegen_union_layout.UnionLayout;
const UnionBranch = codegen_union_layout.UnionBranch;
const free_union_layout = codegen_union_layout.free_union_layout;
const tok_eq = codegen_tokens.tok_eq;
const find_matching = codegen_tokens.find_matching;
const find_line_start = codegen_tokens.find_line_start;
const find_top_level_token = codegen_tokens.find_top_level_token;
const find_arg_end = codegen_tokens.find_arg_end;
const trim_parens = codegen_tokens.trim_parens;
const public_decl_name = codegen_names.public_decl_name;
const find_top_level_type_separator = codegen_tokens.find_top_level_type_separator;
const find_top_level_type_separator_from = codegen_tokens.find_top_level_type_separator_from;
const is_storage_type_name = codegen_storage_layout.is_storage_type_name;
const tuple_arity = codegen_storage_layout.tuple_arity;
const is_tuple_type_name = codegen_storage_layout.is_tuple_type_name;
const substitute_struct_field_type = codegen_storage_layout.substitute_struct_field_type;
const append_typed_local_with_decl = codegen_storage_layout.append_typed_local_with_decl;
const find_func_decl_for_call_head = codegen_storage_layout.find_func_decl_for_call_head;
const infer_expr_type = codegen_storage_layout.infer_expr_type;
const call_arg_matches_param = codegen_storage_layout.call_arg_matches_param;
const clone_local_set = codegen_storage_layout.clone_local_set;
const module_tokens_equal = codegen_tokens.module_tokens_equal;
const find_start_func = codegen_tokens.find_start_func;
const find_token = codegen_tokens.find_token;
const find_stmt_end = codegen_tokens.find_stmt_end;
const find_type_arg_end = codegen_tokens.find_type_arg_end;
const append_mangled_type_name = codegen_names.append_mangled_type_name;
const is_core_wasm_scalar = codegen_names.is_core_wasm_scalar;
const find_codegen_import_by_alias = codegen_imports.find_codegen_import_by_alias;
const find_imported_module_index_no_alloc = codegen_imports.find_imported_module_index_no_alloc;
const imported_alias_context_for_tokens = codegen_imports.imported_alias_context_for_tokens;
const call_head_at = codegen_imports.call_head_at;
const call_head_has_type_args = codegen_imports.call_head_has_type_args;
const parse_codegen_type_expr = codegen_collect_util.parse_codegen_type_expr;
const bind_generic_type = codegen_collect_util.bind_generic_type;
const find_generic_binding = codegen_collect_util.find_generic_binding;
const substitute_generic_type_owned = codegen_collect_util.substitute_generic_type_owned;
const is_type_ident_start = codegen_collect_util.is_type_ident_start;
const is_type_ident_part = codegen_collect_util.is_type_ident_part;
const generic_type_args_range = codegen_collect_util.generic_type_args_range;
const same_callable_source_name = codegen_collect_functions.same_callable_source_name;
const has_type_param_name = codegen_collect_util.has_type_param_name;
const find_func_decl = codegen_collect_functions.find_func_decl;
const find_struct_decl = codegen_collect_util.find_struct_decl;
const find_struct_layout = codegen_collect_util.find_struct_layout;
const append_tuple_leaf_types = codegen_collect_util.append_tuple_leaf_types;
const codegen_types_compatible = codegen_storage_layout.codegen_types_compatible;
const collect_body_locals = codegen_body.collect_body_locals;
const apply_collect_guard_return_narrowing = codegen_collect_reflection.apply_collect_guard_return_narrowing;
const apply_guard_loop_control_narrowing = codegen_collect_reflection.apply_guard_loop_control_narrowing;
const append_union_branch_payload_types = codegen_collect_util.append_union_branch_payload_types;
const substitute_generic_type = codegen_storage_layout.substitute_generic_type;

fn append_gc_func_param_locals(allocator: std.mem.Allocator, func: FuncDecl, ctx: CodegenContext, locals: *LocalSet) !void {
    for (func.params) |param| {
        if (param.callback != null or param.variadic) return error.UnsupportedLowering;
        try append_typed_local_with_decl(allocator, locals, param.name, param.ty, ctx, true);
    }
}

fn find_top_level_guard_loop_control(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var parens: usize = 0;
    var braces: usize = 0;
    var angles: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "(")) {
            parens += 1;
        } else if (tok_eq(tokens[i], ")")) {
            if (parens > 0) parens -= 1;
        } else if (tok_eq(tokens[i], "{")) {
            braces += 1;
        } else if (tok_eq(tokens[i], "}")) {
            if (braces > 0) braces -= 1;
        } else if (tok_eq(tokens[i], "<")) {
            angles += 1;
        } else if (tok_eq(tokens[i], ">")) {
            if (angles > 0) angles -= 1;
        } else if (parens == 0 and braces == 0 and angles == 0 and (tok_eq(tokens[i], "break") or tok_eq(tokens[i], "continue"))) {
            return i;
        }
    }
    return null;
}
pub fn collect_generic_func_instances_for_start(allocator: std.mem.Allocator, tokens: []const lexer.Token, structs: []const StructDecl, value_enums: []const ValueEnumDecl, payload_enums: []const PayloadEnumDecl, struct_layouts: []const StructLayout, host_imports: []const HostImport, wasi_imports: anytype, string_data: *const StringDataContext, modules: []const imports.ModuleRecord, imported_alias_ctx: ?ImportedAliasContext, functions: *std.ArrayList(FuncDecl)) !void {
    if (find_start_func(tokens)) |idx| {
        try collect_generic_func_instances_in_start_body(
            allocator,
            tokens,
            idx,
            structs,
            value_enums,
            payload_enums,
            struct_layouts,
            host_imports,
            wasi_imports,
            string_data,
            modules,
            imported_alias_ctx,
            functions,
        );
    }
    try collect_generic_func_instances_for_concrete_funcs(allocator, tokens, structs, value_enums, payload_enums, struct_layouts, host_imports, wasi_imports, string_data, modules, imported_alias_ctx, functions);
}

fn collect_generic_func_instances_in_start_body(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    structs: []const StructDecl,
    value_enums: []const ValueEnumDecl,
    payload_enums: []const PayloadEnumDecl,
    struct_layouts: []const StructLayout,
    host_imports: []const HostImport,
    wasi_imports: anytype,
    string_data: *const StringDataContext,
    modules: []const imports.ModuleRecord,
    imported_alias_ctx: ?ImportedAliasContext,
    functions: *std.ArrayList(FuncDecl),
) !void {
    const close_params = find_matching(tokens, start_idx + 1, "(", ")") catch return;
    const open_body = find_token(tokens, close_params + 1, tokens.len, "{") orelse return;
    const body_end = find_matching(tokens, open_body, "{", "}") catch return;

    var locals = LocalSet{};
    defer locals.deinit(allocator);
    const ctx = CodegenContext{
        .functions = functions.items,
        .structs = structs,
        .value_enums = value_enums,
        .payload_enums = payload_enums,
        .struct_layouts = struct_layouts,
        .host_imports = host_imports,
        .wasi_imports = wasi_imports,
        .string_data = string_data,
        .entry_tokens = tokens,
        .modules = modules,
        .imported_alias_ctx = imported_alias_ctx,
    };
    try collect_body_locals(allocator, tokens, open_body + 1, body_end, ctx, &locals);
    try collect_generic_func_instances_in_range(allocator, tokens, open_body + 1, body_end, &locals, ctx, functions);
}

pub fn collect_generic_func_instances_for_tests(allocator: std.mem.Allocator, tokens: []const lexer.Token, test_decls: []const test_runner.TestDecl, structs: []const StructDecl, value_enums: []const ValueEnumDecl, payload_enums: []const PayloadEnumDecl, struct_layouts: []const StructLayout, host_imports: []const HostImport, wasi_imports: anytype, string_data: *const StringDataContext, modules: []const imports.ModuleRecord, imported_alias_ctx: ?ImportedAliasContext, functions: *std.ArrayList(FuncDecl)) !void {
    for (test_decls) |decl| {
        var locals = LocalSet{};
        defer locals.deinit(allocator);
        const ctx = CodegenContext{
            .functions = functions.items,
            .structs = structs,
            .value_enums = value_enums,
            .payload_enums = payload_enums,
            .struct_layouts = struct_layouts,
            .host_imports = host_imports,
            .wasi_imports = wasi_imports,
            .string_data = string_data,
            .entry_tokens = tokens,
            .modules = modules,
            .imported_alias_ctx = imported_alias_ctx,
        };
        try collect_body_locals(allocator, tokens, decl.body_start, decl.body_end, ctx, &locals);
        try collect_generic_func_instances_in_range(allocator, tokens, decl.body_start, decl.body_end, &locals, ctx, functions);
    }
    try collect_generic_func_instances_for_concrete_funcs(allocator, tokens, structs, value_enums, payload_enums, struct_layouts, host_imports, wasi_imports, string_data, modules, imported_alias_ctx, functions);
}

fn collect_generic_func_instances_for_concrete_funcs(allocator: std.mem.Allocator, entry_tokens: []const lexer.Token, structs: []const StructDecl, value_enums: []const ValueEnumDecl, payload_enums: []const PayloadEnumDecl, struct_layouts: []const StructLayout, host_imports: []const HostImport, wasi_imports: anytype, string_data: *const StringDataContext, modules: []const imports.ModuleRecord, imported_alias_ctx: ?ImportedAliasContext, functions: *std.ArrayList(FuncDecl)) !void {
    var i: usize = 0;
    while (i < functions.items.len) : (i += 1) {
        const func = functions.items[i];
        if (func.is_generic_template) continue;

        var locals = LocalSet{};
        defer locals.deinit(allocator);
        const ctx = CodegenContext{
            .functions = functions.items,
            .structs = structs,
            .value_enums = value_enums,
            .payload_enums = payload_enums,
            .struct_layouts = struct_layouts,
            .host_imports = host_imports,
            .wasi_imports = wasi_imports,
            .string_data = string_data,
            .entry_tokens = entry_tokens,
            .modules = modules,
            .imported_alias_ctx = imported_alias_ctx,
            .type_bindings = func.type_bindings,
            .callback_bindings = &.{},
        };
        try append_gc_func_param_locals(allocator, func, ctx, &locals);
        try collect_body_locals(allocator, func.tokens, func.body_start, func.body_end, ctx, &locals);
        try collect_generic_func_instances_in_range(allocator, func.tokens, func.body_start, func.body_end, &locals, ctx, functions);
    }
}

fn collect_generic_func_instances_in_range(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    functions: *std.ArrayList(FuncDecl),
) anyerror!void {
    var active_locals = try clone_local_set(allocator, locals);
    defer active_locals.deinit(allocator);

    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        var current_ctx = ctx;
        current_ctx.functions = functions.items;
        const stmt_end = find_stmt_end(tokens, i, end_idx);
        if (tok_eq(tokens[i], "if") and find_top_level_token(tokens, i + 1, stmt_end, "return") != null) {
            try collect_generic_func_instances_in_guard_return(allocator, tokens, i, stmt_end, &active_locals, current_ctx, functions);
            i = stmt_end - 1;
            continue;
        }
        if (tok_eq(tokens[i], "if") and find_top_level_guard_loop_control(tokens, i + 1, stmt_end) != null) {
            try collect_generic_func_instances_in_guard_loop_control(allocator, tokens, i, stmt_end, &active_locals, current_ctx, functions);
            i = stmt_end - 1;
            continue;
        }
        const call_head = call_head_at(tokens, i, end_idx) orelse continue;
        if (call_head.is_intrinsic) continue;
        try collect_generic_func_instances_in_call_args(allocator, tokens, call_head.args_start, call_head.args_end, &active_locals, current_ctx, functions);
        current_ctx.functions = functions.items;
        if (find_func_decl_for_call_head(tokens, call_head, &active_locals, current_ctx)) |_| {
            try apply_collect_guard_return_narrowing(allocator, tokens, i, stmt_end, &active_locals, current_ctx);
            i = call_head.args_end;
            continue;
        }
        var expected_owned_types = std.ArrayList([]const u8).empty;
        defer {
            for (expected_owned_types.items) |owned| allocator.free(owned);
            expected_owned_types.deinit(allocator);
        }
        const expected_result_ty = try direct_call_expected_result_type(allocator, tokens, call_head.name_idx, stmt_end, current_ctx, &expected_owned_types);
        try collect_generic_func_instances_for_call(allocator, tokens, call_head, &active_locals, current_ctx, expected_result_ty, functions);
        try apply_collect_guard_return_narrowing(allocator, tokens, i, stmt_end, &active_locals, current_ctx);
        i = call_head.args_end;
    }
}

fn collect_generic_func_instances_in_guard_return(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *LocalSet, ctx: CodegenContext, functions: *std.ArrayList(FuncDecl)) !void {
    const return_idx = find_top_level_token(tokens, start_idx + 1, end_idx, "return") orelse return;
    try collect_generic_func_instances_in_range(allocator, tokens, start_idx + 1, return_idx, locals, ctx, functions);

    var return_locals = try clone_local_set(allocator, locals);
    defer return_locals.deinit(allocator);
    if (return_idx + 1 < end_idx) {
        try collect_generic_func_instances_in_range(allocator, tokens, return_idx + 1, end_idx, &return_locals, ctx, functions);
    }

    try apply_collect_guard_return_narrowing(allocator, tokens, start_idx, end_idx, locals, ctx);
}

fn collect_generic_func_instances_in_guard_loop_control(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *LocalSet, ctx: CodegenContext, functions: *std.ArrayList(FuncDecl)) !void {
    const control_idx = find_top_level_guard_loop_control(tokens, start_idx + 1, end_idx) orelse return;
    try collect_generic_func_instances_in_range(allocator, tokens, start_idx + 1, control_idx, locals, ctx, functions);
    try apply_guard_loop_control_narrowing(allocator, tokens, start_idx, end_idx, locals, ctx);
}

fn collect_generic_func_instances_in_call_args(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, functions: *std.ArrayList(FuncDecl)) !void {
    var arg_start = args_start;
    while (arg_start < args_end) {
        const arg_end = find_arg_end(tokens, arg_start, args_end);
        if (arg_end == arg_start) return error.NoMatchingCall;
        try collect_generic_func_instances_in_range(allocator, tokens, arg_start, arg_end, locals, ctx, functions);
        arg_start = arg_end;
        if (arg_start < args_end and tok_eq(tokens[arg_start], ",")) arg_start += 1;
    }
}

fn direct_call_expected_result_type(allocator: std.mem.Allocator, tokens: []const lexer.Token, call_start: usize, stmt_end: usize, ctx: CodegenContext, owned_types: *std.ArrayList([]const u8)) CodegenError!?[]const u8 {
    const stmt_start = find_line_start(tokens, call_start);
    const eq_idx = find_top_level_token(tokens, stmt_start, stmt_end, "=") orelse return null;
    const rhs = trim_parens(tokens, eq_idx + 1, stmt_end);
    if (rhs.start != call_start) return null;
    return typed_binding_expected_type(allocator, tokens, stmt_start, eq_idx, ctx, owned_types);
}

fn typed_binding_expected_type(allocator: std.mem.Allocator, tokens: []const lexer.Token, stmt_start: usize, eq_idx: usize, ctx: CodegenContext, owned_types: *std.ArrayList([]const u8)) CodegenError!?[]const u8 {
    if (stmt_start + 2 >= eq_idx) return null;
    if (tokens[stmt_start].kind != .ident) return null;
    const parsed = (try parse_codegen_type_expr(allocator, tokens, stmt_start + 1, eq_idx, owned_types)) orelse return null;
    if (parsed.next_idx != eq_idx) return null;
    return try substitute_generic_type_owned(allocator, parsed.ty, ctx.type_bindings, owned_types);
}

fn collect_generic_func_instance_for_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, call_head: ExprCallHead, locals: *const LocalSet, ctx: CodegenContext, template: FuncDecl, expected_result_ty: ?[]const u8, functions: *std.ArrayList(FuncDecl)) !void {
    var bindings = std.ArrayList(GenericTypeBinding).empty;
    defer bindings.deinit(allocator);

    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }

    if (!try bind_explicit_generic_call_type_args(allocator, tokens, call_head, template, &bindings, &owned_types)) return;

    var param_tys = std.ArrayList([]const u8).empty;
    defer param_tys.deinit(allocator);
    if (!try bind_generic_func_call(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, template, &bindings, &param_tys, &owned_types)) return;
    if (!try bind_generic_expected_result(allocator, template, expected_result_ty, &bindings, &owned_types)) return;
    if (!generic_bindings_cover_type_params(template, bindings.items)) return;
    var params = std.ArrayList(FuncParam).empty;
    errdefer {
        for (params.items) |param| {
            if (param.callback) |callback| {
                if (callback.owned) allocator.free(callback.shape.param_types);
            }
        }
        params.deinit(allocator);
    }
    for (template.params, 0..) |param, idx| {
        if (param.variadic or param.callback != null) return;
        try params.append(allocator, .{
            .name = param.name,
            .ty = param_tys.items[idx],
            .abi_ty = null,
            .variadic = false,
            .callback = null,
        });
    }
    const param_items = try params.toOwnedSlice(allocator);
    var param_items_owned = true;
    defer if (param_items_owned) free_func_params(allocator, param_items);

    const instance_name = try generic_instance_name(allocator, template, bindings.items, param_tys.items);
    var instance_name_owned = true;
    defer if (instance_name_owned) allocator.free(instance_name);
    if (find_func_decl(functions.items, instance_name) != null) {
        return;
    }
    var results = std.ArrayList([]const u8).empty;
    errdefer results.deinit(allocator);
    for (template.results) |result| {
        try results.append(allocator, try substitute_generic_type_owned(allocator, result, bindings.items, &owned_types));
    }
    const result_tys = try results.toOwnedSlice(allocator);
    var result_tys_owned = true;
    errdefer if (result_tys_owned) allocator.free(result_tys);
    const parsed_results = try instantiate_generic_func_result_items(
        allocator,
        template,
        result_tys,
        bindings.items,
        ctx.structs,
        ctx.struct_layouts,
        &owned_types,
    );
    errdefer free_func_result_items(allocator, parsed_results.items, parsed_results.result_union);
    if (parsed_results.types.ptr != result_tys.ptr) {
        allocator.free(result_tys);
    }
    result_tys_owned = false;
    const instance_result_tys = parsed_results.types;
    errdefer allocator.free(instance_result_tys);
    const type_bindings = try clone_generic_type_bindings_owned(allocator, bindings.items, &owned_types);
    errdefer allocator.free(type_bindings);
    const instance_owned_types = try owned_types.toOwnedSlice(allocator);
    owned_types = .empty;
    errdefer {
        for (instance_owned_types) |owned| allocator.free(owned);
        allocator.free(instance_owned_types);
    }

    try functions.append(allocator, .{
        .name = instance_name,
        .source_name = template.source_name,
        .params = param_items,
        .result = if (instance_result_tys.len == 1) instance_result_tys[0] else null,
        .results = instance_result_tys,
        .result_items = parsed_results.items,
        .result_struct = parsed_results.result_struct,
        .result_union = parsed_results.result_union,
        .type_bindings = type_bindings,
        .callback_bindings = &.{},
        .owned_name = true,
        .owned_types = instance_owned_types,
        .tokens = template.tokens,
        .start_idx = template.start_idx,
        .arrow = template.arrow,
        .body_start = template.body_start,
        .body_end = template.body_end,
    });
    param_items_owned = false;
    instance_name_owned = false;
}

fn bind_generic_expected_result(allocator: std.mem.Allocator, template: FuncDecl, expected_result_ty: ?[]const u8, bindings: *std.ArrayList(GenericTypeBinding), owned_types: *std.ArrayList([]const u8)) CodegenError!bool {
    const expected = expected_result_ty orelse return true;
    const template_result = generic_template_logical_result_type(template) orelse return true;
    if (!type_contains_type_param(template.type_params, template_result)) {
        return codegen_types_compatible(template_result, expected);
    }
    return try bind_generic_type_from_concrete(allocator, template_result, expected, template.type_params, bindings, owned_types);
}

fn generic_template_logical_result_type(template: FuncDecl) ?[]const u8 {
    if (template.result_union) |layout| return layout.source_ty;
    if (template.result_items.len == 1) return template.result_items[0].ty;
    if (template.results.len == 1) return template.results[0];
    return null;
}

fn collect_generic_func_instances_for_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, call_head: ExprCallHead, locals: *const LocalSet, ctx: CodegenContext, expected_result_ty: ?[]const u8, functions: *std.ArrayList(FuncDecl)) !void {
    const name = public_decl_name(tokens[call_head.name_idx].lexeme);
    const initial_len = functions.items.len;
    var idx: usize = 0;
    while (idx < initial_len) : (idx += 1) {
        const template = functions.items[idx];
        if (!generic_template_matches_call_site(template, tokens, ctx, name)) continue;
        try collect_generic_func_instance_for_call(allocator, tokens, call_head, locals, ctx, template, expected_result_ty, functions);
    }
}

fn generic_template_matches_call_site(template: FuncDecl, tokens: []const lexer.Token, ctx: CodegenContext, name: []const u8) bool {
    if (!template.is_generic_template) return false;
    if (module_tokens_equal(template.tokens, tokens)) {
        return std.mem.eql(u8, template.name, name) or same_callable_source_name(template.source_name, name);
    }

    const import_ref = find_codegen_import_by_alias(tokens, name) orelse return false;
    const import_ctx = imported_alias_context_for_tokens(ctx.imported_alias_ctx, tokens) orelse return false;
    const child_idx = find_imported_module_index_no_alloc(import_ctx.graph, import_ctx.module_idx, import_ref) orelse return false;
    const child_tokens = import_ctx.graph.modules[child_idx].tokens;
    if (!module_tokens_equal(template.tokens, child_tokens)) return false;
    if (std.mem.eql(u8, template.name, import_ref.alias)) return true;
    return same_callable_source_name(template.source_name, public_decl_name(import_ref.target));
}

fn clone_union_layout_substituted(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    layout: UnionLayout,
    bindings: []const GenericTypeBinding,
    owned_types: *std.ArrayList([]const u8),
) !UnionLayout {
    var branches = std.ArrayList(UnionBranch).empty;
    errdefer branches.deinit(allocator);
    var payload_tys = std.ArrayList([]const u8).empty;
    errdefer payload_tys.deinit(allocator);
    var source_ty = std.ArrayList(u8).empty;
    errdefer source_ty.deinit(allocator);

    for (layout.branches, 0..) |branch, idx| {
        if (idx != 0) try source_ty.append(allocator, '|');
        const branch_ty = substitute_generic_type(branch.ty, bindings);
        try source_ty.appendSlice(allocator, branch_ty);
        const payload_start = payload_tys.items.len;
        if (branch.tag != 0) {
            try append_union_branch_payload_types(allocator, tokens, branch_ty, structs, struct_layouts, &payload_tys);
        }
        try branches.append(allocator, .{
            .ty = branch_ty,
            .tag = branch.tag,
            .payload_start = payload_start,
            .payload_len = payload_tys.items.len - payload_start,
        });
    }

    const owned_source_ty = try source_ty.toOwnedSlice(allocator);
    errdefer allocator.free(owned_source_ty);
    try owned_types.append(allocator, owned_source_ty);
    return .{
        .source_ty = owned_source_ty,
        .branches = try branches.toOwnedSlice(allocator),
        .payload_tys = try payload_tys.toOwnedSlice(allocator),
    };
}

fn instantiate_generic_func_result_items(allocator: std.mem.Allocator, template: FuncDecl, result_tys: []const []const u8, bindings: []const GenericTypeBinding, structs: []const StructDecl, struct_layouts: []const StructLayout, owned_types: *std.ArrayList([]const u8)) !FuncResultParse {
    if (template.result_union) |layout| {
        const next_layout = try clone_union_layout_substituted(
            allocator,
            template.tokens,
            structs,
            struct_layouts,
            layout,
            bindings,
            owned_types,
        );
        errdefer free_union_layout(allocator, next_layout);
        var types = std.ArrayList([]const u8).empty;
        errdefer types.deinit(allocator);
        for (next_layout.payload_tys) |payload_ty| {
            try types.append(allocator, payload_ty);
        }
        try types.append(allocator, "i32");
        const item = try allocator.alloc(FuncResultItem, 1);
        errdefer allocator.free(item);
        item[0] = .{
            .ty = next_layout.source_ty,
            .abi_start = 0,
            .abi_len = next_layout.payload_tys.len + 1,
            .union_layout = next_layout,
        };
        return .{
            .types = try types.toOwnedSlice(allocator),
            .items = item,
            .result_union = next_layout,
        };
    }

    var types = std.ArrayList([]const u8).empty;
    errdefer types.deinit(allocator);
    var items = std.ArrayList(FuncResultItem).empty;
    errdefer items.deinit(allocator);
    var result_struct: ?[]const u8 = null;

    for (result_tys) |result_ty| {
        const abi_start = types.items.len;
        if (is_tuple_type_name(result_ty)) {
            const arity = tuple_arity(result_ty) orelse return error.UnsupportedLowering;
            if (arity < 2) return error.NoMatchingCall;
            const leaf_start = types.items.len;
            try append_tuple_leaf_types(allocator, result_ty, &types);
            if (types.items.len - leaf_start < 2) return error.NoMatchingCall;
            for (types.items[leaf_start..]) |leaf_ty| {
                if (!is_core_wasm_scalar(leaf_ty)) return error.NoMatchingCall;
            }
            try items.append(allocator, .{
                .ty = result_ty,
                .abi_start = abi_start,
                .abi_len = types.items.len - abi_start,
            });
            if (result_tys.len == 1) result_struct = result_ty;
            continue;
        }
        if (try append_unmanaged_struct_result_abi(
            allocator,
            result_ty,
            result_tys.len,
            abi_start,
            structs,
            struct_layouts,
            owned_types,
            &types,
            &items,
            &result_struct,
        )) continue;

        try types.append(allocator, result_ty);
        try items.append(allocator, .{
            .ty = result_ty,
            .abi_start = abi_start,
            .abi_len = 1,
        });
    }

    return .{
        .types = try types.toOwnedSlice(allocator),
        .items = try items.toOwnedSlice(allocator),
        .result_struct = result_struct,
    };
}
fn append_unmanaged_struct_result_abi(
    allocator: std.mem.Allocator,
    result_ty: []const u8,
    result_count: usize,
    abi_start: usize,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    owned_types: *std.ArrayList([]const u8),
    types: *std.ArrayList([]const u8),
    items: *std.ArrayList(FuncResultItem),
    result_struct: *?[]const u8,
) !bool {
    const decl = find_struct_decl(structs, result_ty) orelse return false;
    if (find_struct_layout(struct_layouts, result_ty) != null) return false;

    for (decl.fields) |field| {
        const field_ty = try substitute_struct_field_type(allocator, decl, result_ty, field.ty, owned_types);
        if (!is_core_wasm_scalar(field_ty)) return error.NoMatchingCall;
        try types.append(allocator, field_ty);
    }
    try items.append(allocator, .{
        .ty = result_ty,
        .abi_start = abi_start,
        .abi_len = decl.fields.len,
    });
    if (result_count == 1) result_struct.* = result_ty;
    return true;
}
fn bind_generic_func_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, template: FuncDecl, bindings: *std.ArrayList(GenericTypeBinding), param_tys: *std.ArrayList([]const u8), owned_types: *std.ArrayList([]const u8)) !bool {
    var arg_start = args_start;
    var param_idx: usize = 0;
    while (arg_start < args_end) {
        if (param_idx >= template.params.len) return false;
        const arg_end = find_arg_end(tokens, arg_start, args_end);
        const param = template.params[param_idx];
        const param_ty = param.ty;
        if (param.callback != null or param.variadic) {
            return false;
        } else if (param_ty.len == 0) {
            const arg_ty = infer_untyped_generic_param_abi_type(tokens, arg_start, arg_end, locals, ctx) orelse return false;
            try param_tys.append(allocator, arg_ty);
        } else if (type_contains_type_param(template.type_params, param_ty)) {
            const concrete_before = try substitute_generic_type_owned(allocator, param_ty, bindings.items, owned_types);
            if (!type_contains_type_param(template.type_params, concrete_before)) {
                if (!call_arg_matches_param(tokens, arg_start, arg_end, locals, ctx, concrete_before)) return false;
                try param_tys.append(allocator, concrete_before);
                param_idx += 1;
                arg_start = arg_end;
                if (arg_start < args_end and tok_eq(tokens[arg_start], ",")) arg_start += 1;
                continue;
            }
            const arg_ty = infer_expr_type(tokens, arg_start, arg_end, locals, ctx) orelse return false;
            if (!try bind_generic_type_from_concrete(allocator, param_ty, arg_ty, template.type_params, bindings, owned_types)) {
                return false;
            }
            const concrete_ty = try substitute_generic_type_owned(allocator, param_ty, bindings.items, owned_types);
            if (!call_arg_matches_param(tokens, arg_start, arg_end, locals, ctx, concrete_ty)) {
                return false;
            }
            try param_tys.append(allocator, concrete_ty);
        } else {
            const concrete_ty = try substitute_generic_type_owned(allocator, param_ty, bindings.items, owned_types);
            if (!call_arg_matches_param(tokens, arg_start, arg_end, locals, ctx, concrete_ty)) {
                return false;
            }
            try param_tys.append(allocator, concrete_ty);
        }
        param_idx += 1;
        arg_start = arg_end;
        if (arg_start < args_end and tok_eq(tokens[arg_start], ",")) arg_start += 1;
    }
    if (param_idx == template.params.len) {
        return param_tys.items.len == template.params.len;
    }
    return false;
}
fn infer_untyped_generic_param_abi_type(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    const range = trim_parens(tokens, start_idx, end_idx);
    if (range.end == range.start + 1 and tokens[range.start].kind == .string) return "[u8]";
    return infer_expr_type(tokens, start_idx, end_idx, locals, ctx);
}
fn bind_explicit_generic_call_type_args(allocator: std.mem.Allocator, tokens: []const lexer.Token, call_head: ExprCallHead, template: FuncDecl, bindings: *std.ArrayList(GenericTypeBinding), owned_types: *std.ArrayList([]const u8)) !bool {
    if (!call_head_has_type_args(call_head)) return true;
    if (template.type_params.len == 0) return false;

    var type_start = call_head.type_args_start;
    var type_idx: usize = 0;
    while (type_start < call_head.type_args_end) {
        if (type_idx >= template.type_params.len) return false;
        if (tok_eq(tokens[type_start], ",")) return false;

        const type_end = find_type_arg_end(tokens, type_start, call_head.type_args_end);
        if (type_end == type_start) return false;
        const parsed_ty = (try parse_codegen_type_expr(allocator, tokens, type_start, type_end, owned_types)) orelse return false;
        if (parsed_ty.next_idx != type_end) return false;
        if (!try bind_generic_type(allocator, bindings, template.type_params[type_idx], parsed_ty.ty, owned_types)) return false;

        type_idx += 1;
        type_start = type_end;
        if (type_start < call_head.type_args_end) {
            if (!tok_eq(tokens[type_start], ",")) return false;
            type_start += 1;
            if (type_start >= call_head.type_args_end) return false;
        }
    }

    return type_idx == template.type_params.len;
}

fn clone_generic_type_bindings_owned(allocator: std.mem.Allocator, bindings: []const GenericTypeBinding, owned_types: *std.ArrayList([]const u8)) ![]const GenericTypeBinding {
    const out = try allocator.alloc(GenericTypeBinding, bindings.len);
    errdefer allocator.free(out);
    for (bindings, 0..) |binding, idx| {
        const owned_ty = try allocator.dupe(u8, binding.ty);
        errdefer allocator.free(owned_ty);
        try owned_types.append(allocator, owned_ty);
        out[idx] = .{
            .name = binding.name,
            .ty = owned_ty,
        };
    }
    return out;
}

fn generic_bindings_cover_type_params(template: FuncDecl, bindings: []const GenericTypeBinding) bool {
    for (template.type_params) |type_param| {
        if (find_generic_binding(bindings, type_param) == null) return false;
    }
    return true;
}
fn type_contains_type_param(type_params: []const []const u8, ty: []const u8) bool {
    var i: usize = 0;
    while (i < ty.len) {
        if (!is_type_ident_start(ty[i])) {
            i += 1;
            continue;
        }
        const ident_start = i;
        i += 1;
        while (i < ty.len and is_type_ident_part(ty[i])) i += 1;
        if (has_type_param_name(type_params, ty[ident_start..i])) return true;
    }
    return false;
}

fn bind_generic_type_from_concrete(allocator: std.mem.Allocator, expected_ty: []const u8, actual_ty: []const u8, type_params: []const []const u8, bindings: *std.ArrayList(GenericTypeBinding), owned_types: *std.ArrayList([]const u8)) CodegenError!bool {
    if (try bind_generic_type_list_from_concrete(allocator, expected_ty, actual_ty, '|', type_params, bindings, owned_types)) return true;

    if (has_type_param_name(type_params, expected_ty)) {
        return try bind_generic_type(allocator, bindings, expected_ty, actual_ty, owned_types);
    }
    if (!type_contains_type_param(type_params, expected_ty)) {
        return std.mem.eql(u8, expected_ty, actual_ty);
    }

    if (is_storage_type_name(expected_ty) and is_storage_type_name(actual_ty)) {
        return try bind_generic_type_from_concrete(
            allocator,
            expected_ty[1 .. expected_ty.len - 1],
            actual_ty[1 .. actual_ty.len - 1],
            type_params,
            bindings,
            owned_types,
        );
    }

    const expected_args = generic_type_args_range(expected_ty) orelse return false;
    const actual_args = generic_type_args_range(actual_ty) orelse return false;
    if (!std.mem.eql(u8, expected_args.base, actual_args.base)) return false;
    if (find_top_level_type_separator(expected_args.args, ',') == null and find_top_level_type_separator(actual_args.args, ',') == null) {
        return try bind_generic_type_from_concrete(
            allocator,
            expected_args.args,
            actual_args.args,
            type_params,
            bindings,
            owned_types,
        );
    }
    return try bind_generic_type_list_from_concrete(
        allocator,
        expected_args.args,
        actual_args.args,
        ',',
        type_params,
        bindings,
        owned_types,
    );
}

fn bind_generic_type_list_from_concrete(allocator: std.mem.Allocator, expected: []const u8, actual: []const u8, sep: u8, type_params: []const []const u8, bindings: *std.ArrayList(GenericTypeBinding), owned_types: *std.ArrayList([]const u8)) CodegenError!bool {
    if (find_top_level_type_separator(expected, sep) == null and find_top_level_type_separator(actual, sep) == null) return false;

    var expected_start: usize = 0;
    var actual_start: usize = 0;
    while (true) {
        const expected_end = find_top_level_type_separator_from(expected, expected_start, sep) orelse expected.len;
        const actual_end = find_top_level_type_separator_from(actual, actual_start, sep) orelse actual.len;
        if (expected_start == expected_end or actual_start == actual_end) return false;
        if (!try bind_generic_type_from_concrete(
            allocator,
            expected[expected_start..expected_end],
            actual[actual_start..actual_end],
            type_params,
            bindings,
            owned_types,
        )) return false;
        if (expected_end == expected.len or actual_end == actual.len) {
            return expected_end == expected.len and actual_end == actual.len;
        }
        expected_start = expected_end + 1;
        actual_start = actual_end + 1;
    }
}

fn generic_instance_name(allocator: std.mem.Allocator, template: FuncDecl, bindings: []const GenericTypeBinding, param_tys: []const []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, template.name);
    for (template.type_params) |type_param| {
        const binding = find_generic_binding(bindings, type_param) orelse return error.NoMatchingCall;
        try out.appendSlice(allocator, "__");
        try append_mangled_type_name(allocator, &out, binding.ty);
    }
    if (func_has_untyped_params(template)) {
        try out.appendSlice(allocator, "__abi");
        for (param_tys) |param_ty| {
            try out.appendSlice(allocator, "__");
            try append_mangled_type_name(allocator, &out, param_ty);
        }
    }
    return out.toOwnedSlice(allocator);
}

fn func_has_untyped_params(func: FuncDecl) bool {
    for (func.params) |param| {
        if (param.ty.len == 0) return true;
    }
    return false;
}
