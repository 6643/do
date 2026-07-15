//! Generic function instantiation / type binding (extracted from codegen_pipeline).
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const type_util = @import("type_name.zig");
const codegen_tokens = @import("codegen_tokens.zig");
const codegen_names = @import("codegen_names.zig");
const model = @import("codegen_model.zig");
const context = @import("codegen_context.zig");
const codegen_collect_util = @import("codegen_collect_util.zig");
const codegen_collect_functions = @import("codegen_collect_functions.zig");
const codegen_collect_structs = @import("codegen_collect_structs.zig");
const codegen_imports = @import("codegen_imports.zig");
const codegen_emit_wasi = @import("codegen_emit_wasi.zig");
const codegen_callbacks = @import("codegen_callbacks.zig");
const codegen_emit_expression = @import("codegen_emit_expression.zig");
const codegen_emit_call = @import("codegen_emit_call.zig");
const codegen_collect_body = @import("codegen_collect_body.zig");
const codegen_emit_storage_values = @import("codegen_emit_storage_values.zig");
const codegen_emit_storage_operations = @import("codegen_emit_storage_operations.zig");
const codegen_storage_layout = @import("codegen_storage_layout.zig");
const codegen_emit_struct = @import("codegen_emit_struct.zig");
const codegen_emit_struct_fields = @import("codegen_emit_struct_fields.zig");
const codegen_emit_control = @import("codegen_emit_control.zig");
const codegen_emit_union = @import("codegen_emit_union.zig");
const codegen_union_layout = @import("codegen_union_layout.zig");
const codegen_host_imports = @import("codegen_host_imports.zig");
const codegen_wasi_registry = @import("codegen_wasi_registry.zig");
const codegen_ownership = @import("codegen_ownership.zig");
const ownership = @import("ownership.zig");
const ownership_facts = @import("ownership_facts.zig");
const imports = @import("imports.zig");
const test_runner = @import("test_runner.zig");
const payload_wat = @import("wat_payload.zig");
const storage_wat = @import("wat_storage.zig");

const LocalSet = context.LocalSet;
const OwnedFuncTypeShape = model.OwnedFuncTypeShape;
const FuncResultParse = model.FuncResultParse;
const free_callback_bindings = model.free_callback_bindings;
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
const FieldReflectionLoopHeader = context.FieldReflectionLoopHeader;
const GenericTypeBinding = model.GenericTypeBinding;
const PayloadEnumDecl = model.PayloadEnumDecl;
const ValueEnumDecl = model.ValueEnumDecl;
const CallbackBinding = model.CallbackBinding;
const FuncTypeShape = model.FuncTypeShape;
const ImportedAliasContext = model.ImportedAliasContext;
const StringDataContext = context.StringDataContext;
const ExprCallHead = model.ExprCallHead;
const storage_type_name_for_elem_owned = context.storage_type_name_for_elem_owned;
const UnionLayout = codegen_union_layout.UnionLayout;
const freeUnionLayout = codegen_union_layout.free_union_layout;
const WasiHostImport = codegen_wasi_registry.WasiHostImport;
const tok_eq = codegen_tokens.tok_eq;
const find_matching = codegen_tokens.find_matching;
const findLineStart = codegen_tokens.find_line_start;
const find_top_level_token = codegen_tokens.find_top_level_token;
const find_arg_end = codegen_tokens.find_arg_end;
const trim_parens = codegen_tokens.trim_parens;
const publicDeclName = codegen_names.public_decl_name;
const append_fmt = codegen_names.append_fmt;
const findTopLevelTypeSeparator = codegen_tokens.find_top_level_type_separator;
const find_top_level_type_separator_from = codegen_tokens.find_top_level_type_separator_from;
const find_storage_primitive_local = codegen_emit_wasi.find_storage_primitive_local;
const is_storage_type_name = codegen_emit_wasi.is_storage_type_name;
const tuple_arity = codegen_emit_wasi.tuple_arity;
const is_tuple_type_name = codegen_emit_wasi.is_tuple_type_name;
const append_func_param_locals = codegen_emit_call.append_func_param_locals;
const func_has_callback_params = codegen_emit_call.func_has_callback_params;
const field_reflection_loop_header = codegen_emit_control.field_reflection_loop_header;
const append_condition_narrowing_for_branch = codegen_emit_control.append_condition_narrowing_for_branch;
const clone_union_layout_substituted = codegen_emit_union.clone_union_layout_substituted;
const field_reflection_local_name_prefix = codegen_emit_struct_fields.field_reflection_local_name_prefix;
const field_visible_from_tokens = codegen_emit_struct_fields.field_visible_from_tokens;
const borrowed_field_meta_local_set = codegen_emit_struct_fields.borrowed_field_meta_local_set;
const apply_guard_loop_control_narrowing = codegen_emit_struct_fields.apply_guard_loop_control_narrowing;
const apply_collect_guard_return_narrowing = codegen_emit_struct_fields.apply_collect_guard_return_narrowing;
const substitute_struct_field_type = codegen_storage_layout.substitute_struct_field_type;
pub const find_func_decl_for_call_head = codegen_storage_layout.find_func_decl_for_call_head;
const infer_expr_type = codegen_storage_layout.infer_expr_type;
const find_callback_binding = codegen_storage_layout.find_callback_binding;
const callback_bindings_have_same_shape = codegen_storage_layout.callback_bindings_have_same_shape;
const call_arg_matches_param = codegen_storage_layout.call_arg_matches_param;
const call_args_match_variadic_tail = codegen_storage_layout.call_args_match_variadic_tail;
const lambda_expr_shape = codegen_storage_layout.lambda_expr_shape;
const callback_binding_has_same_concrete_arg = codegen_storage_layout.callback_binding_has_same_concrete_arg;
const lambda_param_type_name = codegen_storage_layout.lambda_param_type_name;
const lambda_explicit_return_type = codegen_storage_layout.lambda_explicit_return_type;
const infer_lambda_expr_return_type = codegen_storage_layout.infer_lambda_expr_return_type;
const clone_local_set = codegen_storage_layout.clone_local_set;
const find_callback_ref_func = codegen_storage_layout.find_callback_ref_func;
const find_top_level_guard_loop_control = codegen_ownership.find_top_level_guard_loop_control;
const module_tokens_equal = codegen_tokens.module_tokens_equal;
pub const findStartFunc = codegen_tokens.find_start_func;
pub const findToken = codegen_tokens.find_token;
const find_stmt_end = codegen_tokens.find_stmt_end;
const findTypeArgEnd = codegen_tokens.find_type_arg_end;
const appendMangledTypeName = codegen_names.append_mangled_type_name;
const is_core_wasm_scalar = codegen_names.is_core_wasm_scalar;
const find_codegen_import_by_alias = codegen_imports.find_codegen_import_by_alias;
const find_imported_module_index_no_alloc = codegen_imports.find_imported_module_index_no_alloc;
const imported_alias_context_for_tokens = codegen_imports.imported_alias_context_for_tokens;
pub const call_head_at = codegen_imports.call_head_at;
const call_head_has_type_args = codegen_imports.call_head_has_type_args;
const parse_codegen_type_expr = codegen_collect_util.parse_codegen_type_expr;
const parse_func_param_type_expr = codegen_collect_functions.parse_func_param_type_expr;
const is_top_level_comma_any = codegen_collect_functions.is_top_level_comma_any;
const bind_generic_type = codegen_collect_util.bind_generic_type;
pub const find_generic_binding = codegen_collect_util.find_generic_binding;
const substitute_generic_type_owned = codegen_collect_util.substitute_generic_type_owned;
const is_type_ident_start = codegen_collect_util.is_type_ident_start;
const is_type_ident_part = codegen_collect_util.is_type_ident_part;
const generic_type_args_range = codegen_collect_util.generic_type_args_range;
const same_callable_source_name = codegen_collect_functions.same_callable_source_name;
const has_type_param_name = codegen_collect_util.has_type_param_name;
const find_func_decl = codegen_collect_functions.find_func_decl;
pub const func_param_abi_type = codegen_collect_util.func_param_abi_type;
const find_struct_decl = codegen_collect_util.find_struct_decl;
const find_struct_layout = codegen_collect_util.find_struct_layout;
const append_tuple_leaf_types = codegen_collect_util.append_tuple_leaf_types;
const codegen_types_compatible = codegen_emit_wasi.codegen_types_compatible;
const collect_body_locals = codegen_collect_body.collect_body_locals;

pub fn parse_lambda_param_names(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ![]const []const u8 {
    var out = std.ArrayList([]const u8).empty;
    errdefer out.deinit(allocator);

    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !is_top_level_comma_any(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            if (tokens[seg_start].kind != .ident) return error.InvalidLambdaExpr;
            try out.append(allocator, tokens[seg_start].lexeme);
        }
        seg_start = i + 1;
    }
    return out.toOwnedSlice(allocator);
}

pub fn parse_lambda_param_types(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ![]?[]const u8 {
    var out = std.ArrayList(?[]const u8).empty;
    errdefer out.deinit(allocator);

    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !is_top_level_comma_any(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            try out.append(allocator, lambda_param_type_name(tokens, seg_start, i));
        }
        seg_start = i + 1;
    }
    return out.toOwnedSlice(allocator);
}

pub fn explicit_lambda_types_match(target_types: []const ?[]const u8, lambda_types: []const ?[]const u8) bool {
    if (target_types.len != lambda_types.len) return false;
    for (lambda_types, 0..) |lambda_type, idx| {
        const expected = lambda_type orelse continue;
        const actual = target_types[idx] orelse return false;
        if (!std.mem.eql(u8, actual, expected)) return false;
    }
    return true;
}

pub fn collect_generic_func_instances_for_start(allocator: std.mem.Allocator, tokens: []const lexer.Token, structs: []const StructDecl, value_enums: []const ValueEnumDecl, payload_enums: []const PayloadEnumDecl, struct_layouts: []const StructLayout, host_imports: []const HostImport, wasi_imports: []const WasiHostImport, string_data: *const StringDataContext, modules: []const imports.ModuleRecord, imported_alias_ctx: ?ImportedAliasContext, functions: *std.ArrayList(FuncDecl)) !void {
    if (findStartFunc(tokens)) |idx| {
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

pub fn collect_generic_func_instances_in_start_body(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    structs: []const StructDecl,
    value_enums: []const ValueEnumDecl,
    payload_enums: []const PayloadEnumDecl,
    struct_layouts: []const StructLayout,
    host_imports: []const HostImport,
    wasi_imports: []const WasiHostImport,
    string_data: *const StringDataContext,
    modules: []const imports.ModuleRecord,
    imported_alias_ctx: ?ImportedAliasContext,
    functions: *std.ArrayList(FuncDecl),
) !void {
    const close_params = find_matching(tokens, start_idx + 1, "(", ")") catch return;
    const open_body = findToken(tokens, close_params + 1, tokens.len, "{") orelse return;
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

pub fn collect_generic_func_instances_for_tests(allocator: std.mem.Allocator, tokens: []const lexer.Token, test_decls: []const test_runner.TestDecl, structs: []const StructDecl, value_enums: []const ValueEnumDecl, payload_enums: []const PayloadEnumDecl, struct_layouts: []const StructLayout, host_imports: []const HostImport, wasi_imports: []const WasiHostImport, string_data: *const StringDataContext, modules: []const imports.ModuleRecord, imported_alias_ctx: ?ImportedAliasContext, functions: *std.ArrayList(FuncDecl)) !void {
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

pub fn collect_generic_func_instances_for_concrete_funcs(allocator: std.mem.Allocator, entry_tokens: []const lexer.Token, structs: []const StructDecl, value_enums: []const ValueEnumDecl, payload_enums: []const PayloadEnumDecl, struct_layouts: []const StructLayout, host_imports: []const HostImport, wasi_imports: []const WasiHostImport, string_data: *const StringDataContext, modules: []const imports.ModuleRecord, imported_alias_ctx: ?ImportedAliasContext, functions: *std.ArrayList(FuncDecl)) !void {
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
            .callback_bindings = func.callback_bindings,
        };
        try append_func_param_locals(allocator, func, ctx, &locals);
        try collect_body_locals(allocator, func.tokens, func.body_start, func.body_end, ctx, &locals);
        try collect_generic_func_instances_in_range(allocator, func.tokens, func.body_start, func.body_end, &locals, ctx, functions);
    }
}

pub fn instantiate_callback_shape(allocator: std.mem.Allocator, param: FuncParam, bindings: []const GenericTypeBinding, owned_types: *std.ArrayList([]const u8)) !?OwnedFuncTypeShape {
    const callback = param.callback orelse return null;
    const param_types = try allocator.alloc(?[]const u8, callback.shape.param_types.len);
    for (callback.shape.param_types, 0..) |param_ty, idx| {
        param_types[idx] = if (param_ty) |ty| try substitute_generic_type_owned(allocator, ty, bindings, owned_types) else null;
    }
    return .{
        .shape = .{
            .param_types = param_types,
            .return_type = if (callback.shape.return_type) |ty| try substitute_generic_type_owned(allocator, ty, bindings, owned_types) else null,
        },
        .owned = true,
    };
}

pub fn instantiate_func_type_shape(allocator: std.mem.Allocator, shape: FuncTypeShape, bindings: []const GenericTypeBinding, owned_types: *std.ArrayList([]const u8)) !FuncTypeShape {
    const param_types = try allocator.alloc(?[]const u8, shape.param_types.len);
    errdefer allocator.free(param_types);
    for (shape.param_types, 0..) |param_ty, idx| {
        param_types[idx] = if (param_ty) |ty| try substitute_generic_type_owned(allocator, ty, bindings, owned_types) else null;
    }
    return .{
        .param_types = param_types,
        .return_type = if (shape.return_type) |ty| try substitute_generic_type_owned(allocator, ty, bindings, owned_types) else null,
    };
}

pub fn callback_bindings_for_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, call_head: ExprCallHead, params: []const FuncParam, ctx: ?CodegenContext) ![]const CallbackBinding {
    var out = std.ArrayList(CallbackBinding).empty;
    errdefer free_callback_bindings(allocator, out.items);

    var arg_start = call_head.args_start;
    var param_idx: usize = 0;
    while (arg_start < call_head.args_end and param_idx < params.len) {
        const arg_end = find_arg_end(tokens, arg_start, call_head.args_end);
        const param = params[param_idx];
        if (param.callback) |callback| {
            if (try resolve_callback_binding_arg(allocator, tokens, arg_start, arg_end, param.name, callback.shape, ctx)) |binding| {
                try out.append(allocator, binding);
            }
        }

        param_idx += 1;
        arg_start = arg_end;
        if (arg_start < call_head.args_end and tok_eq(tokens[arg_start], ",")) arg_start += 1;
    }

    return out.toOwnedSlice(allocator);
}

pub fn resolve_callback_binding_arg(allocator: std.mem.Allocator, tokens: []const lexer.Token, arg_start: usize, arg_end: usize, param_name: []const u8, shape: FuncTypeShape, ctx: ?CodegenContext) !?CallbackBinding {
    if (lambda_expr_shape(tokens, arg_start, arg_end)) |lambda| {
        const lambda_params = try parse_lambda_param_names(allocator, tokens, lambda.open_params + 1, lambda.close_params);
        return .{
            .param_name = param_name,
            .shape = shape,
            .kind = .lambda,
            .arg_tokens = tokens,
            .arg_start = arg_start,
            .arg_end = arg_end,
            .lambda_params = lambda_params,
            .body_start = lambda.body_start,
            .body_end = lambda.body_end,
        };
    }

    if (arg_end != arg_start + 1 or tokens[arg_start].kind != .ident) return null;

    // Named callback binding already in scope: clone shape-compatible binding.
    if (ctx) |codegen_ctx| {
        if (find_callback_binding(codegen_ctx.callback_bindings, tokens[arg_start].lexeme)) |binding| {
            if (!callback_bindings_have_same_shape(binding.shape, shape)) return null;
            const lambda_params = if (binding.lambda_params.len == 0)
                &[_][]const u8{}
            else
                try allocator.dupe([]const u8, binding.lambda_params);
            return .{
                .param_name = param_name,
                .shape = shape,
                .kind = binding.kind,
                .arg_tokens = binding.arg_tokens,
                .arg_start = binding.arg_start,
                .arg_end = binding.arg_end,
                .lambda_params = lambda_params,
                .body_start = binding.body_start,
                .body_end = binding.body_end,
                .func_name = binding.func_name,
            };
        }
    }

    return .{
        .param_name = param_name,
        .shape = shape,
        .kind = .func_ref,
        .arg_tokens = tokens,
        .arg_start = arg_start,
        .arg_end = arg_end,
        .func_name = tokens[arg_start].lexeme,
    };
}

pub fn clone_func_params(allocator: std.mem.Allocator, params: []const FuncParam) ![]const FuncParam {
    var out = std.ArrayList(FuncParam).empty;
    errdefer {
        for (out.items) |param| {
            if (param.callback) |callback| {
                if (callback.owned) allocator.free(callback.shape.param_types);
            }
        }
        out.deinit(allocator);
    }

    for (params) |param| {
        try out.append(allocator, .{
            .name = param.name,
            .ty = param.ty,
            .abi_ty = param.abi_ty,
            .variadic = param.variadic,
            .callback = if (param.callback) |callback| blk: {
                const param_types = try allocator.alloc(?[]const u8, callback.shape.param_types.len);
                @memcpy(param_types, callback.shape.param_types);
                break :blk .{
                    .shape = .{
                        .param_types = param_types,
                        .return_type = callback.shape.return_type,
                    },
                    .owned = true,
                };
            } else null,
        });
    }
    return out.toOwnedSlice(allocator);
}

pub fn collect_generic_func_instances_in_range(
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
        if (field_reflection_loop_header(tokens, i, stmt_end, current_ctx, &active_locals)) |header| {
            try collect_generic_func_instances_in_field_reflection_loop(allocator, tokens, header, &active_locals, current_ctx, functions);
            i = stmt_end - 1;
            continue;
        }

        const call_head = call_head_at(tokens, i, end_idx) orelse continue;
        if (call_head.is_intrinsic) continue;
        try collect_generic_func_instances_in_call_args(allocator, tokens, call_head.args_start, call_head.args_end, &active_locals, current_ctx, functions);
        current_ctx.functions = functions.items;
        if (find_func_decl_for_call_head(tokens, call_head, &active_locals, current_ctx)) |func| {
            if (func_has_callback_params(func) and func.callback_bindings.len == 0) {
                try collect_concrete_callback_func_instance_for_call(allocator, tokens, call_head, current_ctx, func, functions);
            }
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

pub fn collect_generic_func_instances_in_guard_return(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *LocalSet, ctx: CodegenContext, functions: *std.ArrayList(FuncDecl)) !void {
    const return_idx = find_top_level_token(tokens, start_idx + 1, end_idx, "return") orelse return;
    try collect_generic_func_instances_in_range(allocator, tokens, start_idx + 1, return_idx, locals, ctx, functions);

    var return_locals = try clone_local_set(allocator, locals);
    defer return_locals.deinit(allocator);
    try append_condition_narrowing_for_branch(allocator, tokens, start_idx + 1, return_idx, &return_locals, ctx, true);
    if (return_idx + 1 < end_idx) {
        try collect_generic_func_instances_in_range(allocator, tokens, return_idx + 1, end_idx, &return_locals, ctx, functions);
    }

    try apply_collect_guard_return_narrowing(allocator, tokens, start_idx, end_idx, locals, ctx);
}

pub fn collect_generic_func_instances_in_guard_loop_control(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *LocalSet, ctx: CodegenContext, functions: *std.ArrayList(FuncDecl)) !void {
    const control_idx = find_top_level_guard_loop_control(tokens, start_idx + 1, end_idx) orelse return;
    try collect_generic_func_instances_in_range(allocator, tokens, start_idx + 1, control_idx, locals, ctx, functions);
    try apply_guard_loop_control_narrowing(allocator, tokens, start_idx, end_idx, locals, ctx);
}

pub fn collect_generic_func_instances_in_call_args(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, functions: *std.ArrayList(FuncDecl)) !void {
    var arg_start = args_start;
    while (arg_start < args_end) {
        const arg_end = find_arg_end(tokens, arg_start, args_end);
        if (arg_end == arg_start) return error.NoMatchingCall;
        try collect_generic_func_instances_in_range(allocator, tokens, arg_start, arg_end, locals, ctx, functions);
        arg_start = arg_end;
        if (arg_start < args_end and tok_eq(tokens[arg_start], ",")) arg_start += 1;
    }
}

pub fn collect_generic_func_instances_in_field_reflection_loop(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    header: FieldReflectionLoopHeader,
    locals: *const LocalSet,
    ctx: CodegenContext,
    functions: *std.ArrayList(FuncDecl),
) anyerror!void {
    var visible_index: usize = 0;
    for (header.decl.fields, 0..) |field, decl_index| {
        if (!field_visible_from_tokens(field, header.decl, tokens)) continue;
        const prefix = try field_reflection_local_name_prefix(allocator, header, visible_index);
        defer allocator.free(prefix);
        var field_locals = try borrowed_field_meta_local_set(allocator, locals, .{
            .name = header.field_name,
            .struct_name = header.decl.name,
            .decl_index = decl_index,
            .visible_index = visible_index,
        }, prefix);
        defer field_locals.deinit(allocator);
        field_locals.local_name_prefix = prefix;
        try collect_generic_func_instances_in_range(allocator, tokens, header.open_brace + 1, header.close_brace, &field_locals, ctx, functions);
        visible_index += 1;
    }
}

pub fn direct_call_expected_result_type(allocator: std.mem.Allocator, tokens: []const lexer.Token, call_start: usize, stmt_end: usize, ctx: CodegenContext, owned_types: *std.ArrayList([]const u8)) CodegenError!?[]const u8 {
    const stmt_start = findLineStart(tokens, call_start);
    const eq_idx = find_top_level_token(tokens, stmt_start, stmt_end, "=") orelse return null;
    const rhs = trim_parens(tokens, eq_idx + 1, stmt_end);
    if (rhs.start != call_start) return null;
    return typed_binding_expected_type(allocator, tokens, stmt_start, eq_idx, ctx, owned_types);
}

pub fn typed_binding_expected_type(allocator: std.mem.Allocator, tokens: []const lexer.Token, stmt_start: usize, eq_idx: usize, ctx: CodegenContext, owned_types: *std.ArrayList([]const u8)) CodegenError!?[]const u8 {
    if (stmt_start + 2 >= eq_idx) return null;
    if (tokens[stmt_start].kind != .ident) return null;
    const parsed = (try parse_func_param_type_expr(allocator, tokens, stmt_start + 1, eq_idx, owned_types)) orelse return null;
    if (parsed.next_idx != eq_idx) return null;
    return try substitute_generic_type_owned(allocator, parsed.ty, ctx.type_bindings, owned_types);
}

pub fn collect_generic_func_instance_for_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, call_head: ExprCallHead, locals: *const LocalSet, ctx: CodegenContext, template: FuncDecl, expected_result_ty: ?[]const u8, functions: *std.ArrayList(FuncDecl)) !void {
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
    if (!call_head_has_type_args(call_head) and try generic_overload_covers_generic_params(allocator, functions.items, template, param_tys.items)) {
        return;
    }

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
        const instance_param_abi_ty = if (param.variadic)
            try storage_type_name_for_elem_owned(allocator, param_tys.items[idx], &owned_types)
        else
            null;
        try params.append(allocator, .{
            .name = param.name,
            .ty = param_tys.items[idx],
            .abi_ty = instance_param_abi_ty,
            .variadic = param.variadic,
            .callback = try instantiate_callback_shape(allocator, param, bindings.items, &owned_types),
        });
    }
    const param_items = try params.toOwnedSlice(allocator);
    var param_items_owned = true;
    defer if (param_items_owned) free_func_params(allocator, param_items);

    const callback_bindings = try callback_bindings_for_call(allocator, tokens, call_head, param_items, ctx);
    var callback_bindings_owned = true;
    defer if (callback_bindings_owned) free_callback_bindings(allocator, callback_bindings);

    if (!call_head_has_type_args(call_head) and concrete_overload_covers_generic_params(functions.items, template, param_items, callback_bindings)) {
        return;
    }

    const instance_name = try generic_instance_name(allocator, template, bindings.items, param_tys.items, callback_bindings);
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
        .callback_bindings = callback_bindings,
        .owned_name = true,
        .owned_types = instance_owned_types,
        .tokens = template.tokens,
        .start_idx = template.start_idx,
        .arrow = template.arrow,
        .body_start = template.body_start,
        .body_end = template.body_end,
    });
    param_items_owned = false;
    callback_bindings_owned = false;
    instance_name_owned = false;
}

pub fn bind_generic_expected_result(allocator: std.mem.Allocator, template: FuncDecl, expected_result_ty: ?[]const u8, bindings: *std.ArrayList(GenericTypeBinding), owned_types: *std.ArrayList([]const u8)) CodegenError!bool {
    const expected = expected_result_ty orelse return true;
    const template_result = generic_template_logical_result_type(template) orelse return true;
    if (!type_contains_type_param(template.type_params, template_result)) {
        return codegen_types_compatible(template_result, expected);
    }
    return try bind_generic_type_from_concrete(allocator, template_result, expected, template.type_params, bindings, owned_types);
}

pub fn generic_template_logical_result_type(template: FuncDecl) ?[]const u8 {
    if (template.result_union) |layout| return layout.source_ty;
    if (template.result_items.len == 1) return template.result_items[0].ty;
    if (template.results.len == 1) return template.results[0];
    return null;
}

pub fn collect_generic_func_instances_for_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, call_head: ExprCallHead, locals: *const LocalSet, ctx: CodegenContext, expected_result_ty: ?[]const u8, functions: *std.ArrayList(FuncDecl)) !void {
    const name = publicDeclName(tokens[call_head.name_idx].lexeme);
    const initial_len = functions.items.len;
    var idx: usize = 0;
    while (idx < initial_len) : (idx += 1) {
        const template = functions.items[idx];
        if (!generic_template_matches_call_site(template, tokens, ctx, name)) continue;
        try collect_generic_func_instance_for_call(allocator, tokens, call_head, locals, ctx, template, expected_result_ty, functions);
    }
}

pub fn generic_template_matches_call_site(template: FuncDecl, tokens: []const lexer.Token, ctx: CodegenContext, name: []const u8) bool {
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
    return same_callable_source_name(template.source_name, publicDeclName(import_ref.target));
}

pub fn collect_concrete_callback_func_instance_for_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, call_head: ExprCallHead, ctx: CodegenContext, func: FuncDecl, functions: *std.ArrayList(FuncDecl)) !void {
    const param_items = try clone_func_params(allocator, func.params);
    var param_items_owned = true;
    defer if (param_items_owned) free_func_params(allocator, param_items);

    const callback_bindings = try callback_bindings_for_call(allocator, tokens, call_head, param_items, ctx);
    var callback_bindings_owned = true;
    defer if (callback_bindings_owned) free_callback_bindings(allocator, callback_bindings);
    if (callback_bindings.len == 0) return;

    const instance_name = try generic_instance_name(allocator, func, &.{}, &.{}, callback_bindings);
    var instance_name_owned = true;
    defer if (instance_name_owned) allocator.free(instance_name);
    if (find_func_decl(functions.items, instance_name) != null) {
        return;
    }

    var owned_types = std.ArrayList([]const u8).empty;
    errdefer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }

    const result_tys = try allocator.dupe([]const u8, func.results);
    var result_tys_owned = true;
    errdefer if (result_tys_owned) allocator.free(result_tys);
    const parsed_results = try instantiate_generic_func_result_items(
        allocator,
        func,
        result_tys,
        &.{},
        ctx.structs,
        ctx.struct_layouts,
        &owned_types,
    );
    errdefer free_func_result_items(allocator, parsed_results.items, parsed_results.result_union);
    if (parsed_results.types.ptr != result_tys.ptr) allocator.free(result_tys);
    result_tys_owned = false;

    const instance_result_tys = parsed_results.types;
    errdefer allocator.free(instance_result_tys);
    const type_bindings = if (func.type_bindings.len == 0)
        &[_]GenericTypeBinding{}
    else
        try allocator.dupe(GenericTypeBinding, func.type_bindings);
    errdefer if (func.type_bindings.len != 0) allocator.free(type_bindings);
    const instance_owned_types = try owned_types.toOwnedSlice(allocator);
    errdefer {
        for (instance_owned_types) |owned| allocator.free(owned);
        allocator.free(instance_owned_types);
    }
    const new_index = functions.items.len;

    try functions.append(allocator, .{
        .name = instance_name,
        .source_name = func.source_name,
        .params = param_items,
        .result = if (instance_result_tys.len == 1) instance_result_tys[0] else null,
        .results = instance_result_tys,
        .result_items = parsed_results.items,
        .result_struct = parsed_results.result_struct,
        .result_union = parsed_results.result_union,
        .type_bindings = type_bindings,
        .callback_bindings = callback_bindings,
        .owned_name = true,
        .owned_types = instance_owned_types,
        .tokens = func.tokens,
        .start_idx = func.start_idx,
        .arrow = func.arrow,
        .body_start = func.body_start,
        .body_end = func.body_end,
    });
    param_items_owned = false;
    callback_bindings_owned = false;
    instance_name_owned = false;
    owned_types = .empty;

    const instance = functions.items[new_index];
    var instance_locals = LocalSet{};
    defer instance_locals.deinit(allocator);
    var instance_ctx = ctx;
    instance_ctx.functions = functions.items;
    instance_ctx.type_bindings = instance.type_bindings;
    instance_ctx.callback_bindings = instance.callback_bindings;
    try append_func_param_locals(allocator, instance, instance_ctx, &instance_locals);
    try collect_body_locals(allocator, instance.tokens, instance.body_start, instance.body_end, instance_ctx, &instance_locals);
    try collect_generic_func_instances_in_range(allocator, instance.tokens, instance.body_start, instance.body_end, &instance_locals, instance_ctx, functions);
}

pub fn concrete_overload_covers_generic_params(functions: []const FuncDecl, template: FuncDecl, params: []const FuncParam, callback_bindings: []const CallbackBinding) bool {
    for (functions) |func| {
        if (func.is_generic_template) continue;
        if (!module_tokens_equal(func.tokens, template.tokens)) continue;
        if (!same_callable_source_name(func.source_name, template.source_name)) continue;
        if (func.params.len != params.len) continue;
        if (!callback_bindings_have_same_concrete_args(func.callback_bindings, callback_bindings)) continue;

        var matches = true;
        for (func.params, 0..) |param, idx| {
            if (!func_params_have_same_concrete_call_shape(param, params[idx])) {
                matches = false;
                break;
            }
        }
        if (matches) return true;
    }
    return false;
}

pub fn callback_bindings_have_same_concrete_args(left: []const CallbackBinding, right: []const CallbackBinding) bool {
    if (left.len != right.len) return false;
    for (left, 0..) |left_binding, idx| {
        if (!callback_binding_has_same_concrete_arg(left_binding, right[idx])) return false;
    }
    return true;
}

pub fn func_params_have_same_concrete_call_shape(left: FuncParam, right: FuncParam) bool {
    if (left.variadic != right.variadic) return false;
    if (left.callback != null or right.callback != null) {
        const left_callback = left.callback orelse return false;
        const right_callback = right.callback orelse return false;
        return callback_bindings_have_same_shape(left_callback.shape, right_callback.shape);
    }
    return std.mem.eql(u8, func_param_abi_type(left), func_param_abi_type(right));
}

pub fn generic_overload_covers_generic_params(allocator: std.mem.Allocator, functions: []const FuncDecl, template: FuncDecl, param_tys: []const []const u8) !bool {
    const current_specificity = generic_template_specificity(template);
    for (functions) |candidate| {
        if (!candidate.is_generic_template) continue;
        if (candidate.start_idx == template.start_idx and module_tokens_equal(candidate.tokens, template.tokens)) continue;
        if (!module_tokens_equal(candidate.tokens, template.tokens)) continue;
        if (!same_callable_source_name(candidate.source_name, template.source_name)) continue;
        if (candidate.params.len != param_tys.len) continue;
        if (generic_template_specificity(candidate) <= current_specificity) continue;
        if (try generic_template_matches_concrete_params(allocator, candidate, param_tys)) return true;
    }
    return false;
}

pub fn generic_template_specificity(template: FuncDecl) usize {
    var score: usize = 0;
    for (template.params) |param| {
        const ty = func_param_abi_type(param);
        if (!type_contains_type_param(template.type_params, ty)) {
            score += 2;
        } else if (!has_type_param_name(template.type_params, ty)) {
            score += 1;
        }
    }
    return score;
}

pub fn generic_template_matches_concrete_params(allocator: std.mem.Allocator, template: FuncDecl, param_tys: []const []const u8) !bool {
    var bindings = std.ArrayList(GenericTypeBinding).empty;
    defer bindings.deinit(allocator);
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }

    for (template.params, 0..) |param, idx| {
        if (param.callback != null or param.variadic) return false;
        if (!try bind_generic_type_from_concrete(
            allocator,
            param.ty,
            param_tys[idx],
            template.type_params,
            &bindings,
            &owned_types,
        )) return false;
    }
    return generic_bindings_cover_type_params(template, bindings.items);
}

pub fn instantiate_generic_func_result_items(allocator: std.mem.Allocator, template: FuncDecl, result_tys: []const []const u8, bindings: []const GenericTypeBinding, structs: []const StructDecl, struct_layouts: []const StructLayout, owned_types: *std.ArrayList([]const u8)) !FuncResultParse {
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
        errdefer freeUnionLayout(allocator, next_layout);
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

/// Expand pure-scalar unmanaged struct result into ABI slots. Returns false if not applicable.
/// Expand pure-scalar unmanaged struct result into ABI slots. Returns false if not applicable.
pub fn append_unmanaged_struct_result_abi(
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

pub fn bind_generic_func_call(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, template: FuncDecl, bindings: *std.ArrayList(GenericTypeBinding), param_tys: *std.ArrayList([]const u8), owned_types: *std.ArrayList([]const u8)) !bool {
    if (!try prebind_generic_callback_args(allocator, tokens, args_start, args_end, ctx, template, bindings, owned_types)) {
        return false;
    }

    var arg_start = args_start;
    var param_idx: usize = 0;
    while (arg_start < args_end) {
        if (param_idx >= template.params.len) return false;
        const arg_end = find_arg_end(tokens, arg_start, args_end);
        const param = template.params[param_idx];
        const param_ty = param.ty;
        if (param.variadic) {
            if (param_idx + 1 != template.params.len) return false;
            if (!try bind_generic_variadic_tail(allocator, tokens, arg_start, args_end, locals, ctx, template, param_ty, bindings, owned_types)) {
                return false;
            }
            const concrete_ty = try substitute_generic_type_owned(allocator, param_ty, bindings.items, owned_types);
            if (type_contains_type_param(template.type_params, concrete_ty)) return false;
            try param_tys.append(allocator, concrete_ty);
            return param_tys.items.len == template.params.len;
        } else if (param.callback != null) {
            if (!try bind_generic_callback_arg(allocator, tokens, arg_start, arg_end, locals, ctx, template, param, bindings, owned_types)) {
                return false;
            }
            try param_tys.append(allocator, param_ty);
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
    if (param_idx + 1 == template.params.len and template.params[param_idx].variadic) {
        if (!try bind_generic_variadic_tail(
            allocator,
            tokens,
            arg_start,
            args_end,
            locals,
            ctx,
            template,
            template.params[param_idx].ty,
            bindings,
            owned_types,
        )) return false;
        const concrete_ty = try substitute_generic_type_owned(allocator, template.params[param_idx].ty, bindings.items, owned_types);
        if (type_contains_type_param(template.type_params, concrete_ty)) return false;
        try param_tys.append(allocator, concrete_ty);
        return param_tys.items.len == template.params.len;
    }
    return false;
}

pub fn prebind_generic_callback_args(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, ctx: CodegenContext, template: FuncDecl, bindings: *std.ArrayList(GenericTypeBinding), owned_types: *std.ArrayList([]const u8)) !bool {
    var arg_start = args_start;
    var param_idx: usize = 0;
    while (arg_start < args_end and param_idx < template.params.len) {
        const arg_end = find_arg_end(tokens, arg_start, args_end);
        const param = template.params[param_idx];
        if (param.callback) |callback| {
            if (!try prebind_generic_callback_arg(allocator, tokens, arg_start, arg_end, ctx, template, callback.shape, bindings, owned_types)) {
                return false;
            }
        }
        param_idx += 1;
        arg_start = arg_end;
        if (arg_start < args_end and tok_eq(tokens[arg_start], ",")) arg_start += 1;
    }
    return true;
}

pub fn prebind_generic_callback_arg(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    arg_start: usize,
    arg_end: usize,
    ctx: CodegenContext,
    template: FuncDecl,
    shape: FuncTypeShape,
    bindings: *std.ArrayList(GenericTypeBinding),
    owned_types: *std.ArrayList([]const u8),
) !bool {
    if (lambda_expr_shape(tokens, arg_start, arg_end) != null) {
        return prebind_generic_callback_lambda(allocator, tokens, arg_start, arg_end, template, shape, bindings, owned_types);
    }
    if (arg_end != arg_start + 1 or tokens[arg_start].kind != .ident) return true;
    return prebind_generic_callback_ident(
        allocator,
        tokens,
        arg_start,
        ctx,
        template,
        shape,
        bindings,
        owned_types,
    );
}

pub fn prebind_generic_type_if_param(
    allocator: std.mem.Allocator,
    expected_ty: []const u8,
    concrete_ty: []const u8,
    type_params: []const []const u8,
    bindings: *std.ArrayList(GenericTypeBinding),
    owned_types: *std.ArrayList([]const u8),
) !bool {
    if (!type_contains_type_param(type_params, expected_ty)) return true;
    return bind_generic_type_from_concrete(allocator, expected_ty, concrete_ty, type_params, bindings, owned_types);
}

pub fn prebind_generic_callback_lambda(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    arg_start: usize,
    arg_end: usize,
    template: FuncDecl,
    shape: FuncTypeShape,
    bindings: *std.ArrayList(GenericTypeBinding),
    owned_types: *std.ArrayList([]const u8),
) !bool {
    const lambda = lambda_expr_shape(tokens, arg_start, arg_end) orelse return false;
    const lambda_param_types = try parse_lambda_param_types(allocator, tokens, lambda.open_params + 1, lambda.close_params);
    defer allocator.free(lambda_param_types);
    if (lambda_param_types.len != shape.param_types.len) return false;

    for (shape.param_types, 0..) |shape_ty, idx| {
        const expected_ty = shape_ty orelse continue;
        const explicit_ty = lambda_param_types[idx] orelse continue;
        if (!try prebind_generic_type_if_param(allocator, expected_ty, explicit_ty, template.type_params, bindings, owned_types)) {
            return false;
        }
    }
    const ret_ty = shape.return_type orelse return true;
    const lambda_ret = lambda_explicit_return_type(tokens, lambda) orelse return true;
    return try prebind_generic_type_if_param(allocator, ret_ty, lambda_ret, template.type_params, bindings, owned_types);
}

pub fn prebind_generic_callback_ident(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    arg_start: usize,
    ctx: CodegenContext,
    template: FuncDecl,
    shape: FuncTypeShape,
    bindings: *std.ArrayList(GenericTypeBinding),
    owned_types: *std.ArrayList([]const u8),
) !bool {
    const binding = find_callback_binding(ctx.callback_bindings, tokens[arg_start].lexeme) orelse {
        return prebind_generic_callback_func_ref(
            allocator,
            tokens,
            ctx,
            template,
            shape,
            tokens[arg_start].lexeme,
            bindings,
            owned_types,
        );
    };
    if (binding.shape.param_types.len != shape.param_types.len) return true;
    for (shape.param_types, 0..) |shape_ty, idx| {
        const expected_ty = shape_ty orelse continue;
        const upstream_ty = binding.shape.param_types[idx] orelse continue;
        if (!try prebind_generic_type_if_param(allocator, expected_ty, upstream_ty, template.type_params, bindings, owned_types)) {
            return false;
        }
    }
    const ret_ty = shape.return_type orelse return true;
    const upstream_ret = binding.shape.return_type orelse return true;
    return try prebind_generic_type_if_param(allocator, ret_ty, upstream_ret, template.type_params, bindings, owned_types);
}

pub fn prebind_generic_callback_func_ref(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    ctx: CodegenContext,
    template: FuncDecl,
    shape: FuncTypeShape,
    func_name: []const u8,
    bindings: *std.ArrayList(GenericTypeBinding),
    owned_types: *std.ArrayList([]const u8),
) !bool {
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (!module_tokens_equal(func.tokens, tokens)) continue;
        if (!same_callable_source_name(func.source_name, func_name)) continue;
        if (func.params.len != shape.param_types.len) continue;

        for (shape.param_types, 0..) |shape_ty, idx| {
            const expected_ty = shape_ty orelse continue;
            if (!try prebind_generic_type_if_param(
                allocator,
                expected_ty,
                func_param_abi_type(func.params[idx]),
                template.type_params,
                bindings,
                owned_types,
            )) return false;
        }
        if (shape.return_type) |ret_ty| {
            if (!type_contains_type_param(template.type_params, ret_ty)) return true;
            const func_ret = generic_template_logical_result_type(func) orelse return false;
            if (!try bind_generic_type_from_concrete(allocator, ret_ty, func_ret, template.type_params, bindings, owned_types)) {
                return false;
            }
        }
        return true;
    }
    return true;
}

pub fn bind_generic_variadic_tail(allocator: std.mem.Allocator, tokens: []const lexer.Token, args_start: usize, args_end: usize, locals: *const LocalSet, ctx: CodegenContext, template: FuncDecl, param_ty: []const u8, bindings: *std.ArrayList(GenericTypeBinding), owned_types: *std.ArrayList([]const u8)) !bool {
    if (args_start < args_end and tok_eq(tokens[args_start], "...")) {
        const rest_start = args_start + 1;
        if (find_arg_end(tokens, rest_start, args_end) != args_end) return false;
        if (rest_start + 1 != args_end or tokens[rest_start].kind != .ident) return false;
        const rest = find_storage_primitive_local(locals.storage_locals.items, tokens[rest_start].lexeme) orelse return false;
        if (type_contains_type_param(template.type_params, param_ty)) {
            if (!try bind_generic_type_from_concrete(allocator, param_ty, rest.elem_ty, template.type_params, bindings, owned_types)) return false;
        }
    } else {
        var tail_start = args_start;
        while (tail_start < args_end) {
            const tail_end = find_arg_end(tokens, tail_start, args_end);
            if (tail_end == tail_start) return false;
            if (type_contains_type_param(template.type_params, param_ty)) {
                const actual_ty = infer_expr_type(tokens, tail_start, tail_end, locals, ctx) orelse {
                    tail_start = tail_end;
                    if (tail_start < args_end and tok_eq(tokens[tail_start], ",")) tail_start += 1;
                    continue;
                };
                if (!try bind_generic_type_from_concrete(allocator, param_ty, actual_ty, template.type_params, bindings, owned_types)) return false;
            }
            tail_start = tail_end;
            if (tail_start < args_end and tok_eq(tokens[tail_start], ",")) tail_start += 1;
        }
    }

    const concrete_ty = try substitute_generic_type_owned(allocator, param_ty, bindings.items, owned_types);
    if (type_contains_type_param(template.type_params, concrete_ty)) return false;
    return call_args_match_variadic_tail(tokens, args_start, args_end, locals, ctx, concrete_ty);
}

pub fn bind_generic_callback_arg(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    arg_start: usize,
    arg_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    template: FuncDecl,
    param: FuncParam,
    bindings: *std.ArrayList(GenericTypeBinding),
    owned_types: *std.ArrayList([]const u8),
) !bool {
    const callback = param.callback orelse return false;
    if (arg_end == arg_start + 1 and tokens[arg_start].kind == .ident) {
        return bind_generic_callback_ident_arg(
            allocator,
            tokens,
            arg_start,
            ctx,
            template,
            callback.shape,
            bindings,
            owned_types,
        );
    }
    return bind_generic_callback_lambda_arg(
        allocator,
        tokens,
        arg_start,
        arg_end,
        locals,
        ctx,
        template,
        callback.shape,
        bindings,
        owned_types,
    );
}

pub fn match_or_bind_generic_type(
    allocator: std.mem.Allocator,
    shape_ty: []const u8,
    concrete_ty: []const u8,
    type_params: []const []const u8,
    bindings: *std.ArrayList(GenericTypeBinding),
    owned_types: *std.ArrayList([]const u8),
) !bool {
    if (!type_contains_type_param(type_params, shape_ty)) {
        const resolved = try substitute_generic_type_owned(allocator, shape_ty, bindings.items, owned_types);
        return std.mem.eql(u8, resolved, concrete_ty);
    }
    return bind_generic_type_from_concrete(allocator, shape_ty, concrete_ty, type_params, bindings, owned_types);
}

pub fn bind_generic_callback_ident_arg(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    arg_start: usize,
    ctx: CodegenContext,
    template: FuncDecl,
    shape: FuncTypeShape,
    bindings: *std.ArrayList(GenericTypeBinding),
    owned_types: *std.ArrayList([]const u8),
) !bool {
    const binding = find_callback_binding(ctx.callback_bindings, tokens[arg_start].lexeme) orelse {
        const concrete_shape = try instantiate_func_type_shape(allocator, shape, bindings.items, owned_types);
        defer allocator.free(concrete_shape.param_types);
        return find_callback_ref_func(tokens, ctx, tokens[arg_start].lexeme, concrete_shape) != null;
    };
    if (binding.shape.param_types.len != shape.param_types.len) return false;

    for (shape.param_types, 0..) |expected_ty, idx| {
        const shape_ty = expected_ty orelse {
            if (idx >= binding.shape.param_types.len) return false;
            continue;
        };
        if (idx >= binding.shape.param_types.len) return false;
        const upstream_ty = binding.shape.param_types[idx] orelse return false;
        if (!try match_or_bind_generic_type(allocator, shape_ty, upstream_ty, template.type_params, bindings, owned_types)) {
            return false;
        }
    }

    const ret_ty = shape.return_type orelse return binding.shape.return_type == null;
    const upstream_ret = binding.shape.return_type orelse return false;
    return try match_or_bind_generic_type(allocator, ret_ty, upstream_ret, template.type_params, bindings, owned_types);
}

pub fn bind_generic_callback_lambda_arg(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    arg_start: usize,
    arg_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    template: FuncDecl,
    shape: FuncTypeShape,
    bindings: *std.ArrayList(GenericTypeBinding),
    owned_types: *std.ArrayList([]const u8),
) !bool {
    const lambda = lambda_expr_shape(tokens, arg_start, arg_end) orelse return false;
    const lambda_param_types = try parse_lambda_param_types(allocator, tokens, lambda.open_params + 1, lambda.close_params);
    defer allocator.free(lambda_param_types);
    if (lambda_param_types.len != shape.param_types.len) return false;

    for (shape.param_types, 0..) |expected_ty, idx| {
        const shape_ty = expected_ty orelse continue;
        const explicit_ty = lambda_param_types[idx];
        if (!type_contains_type_param(template.type_params, shape_ty)) {
            const concrete_ty = try substitute_generic_type_owned(allocator, shape_ty, bindings.items, owned_types);
            if (explicit_ty) |ty| {
                if (!std.mem.eql(u8, concrete_ty, ty)) return false;
            }
            continue;
        }
        if (explicit_ty) |ty| {
            if (!try bind_generic_type_from_concrete(allocator, shape_ty, ty, template.type_params, bindings, owned_types)) {
                return false;
            }
            continue;
        }
        const concrete_ty = try substitute_generic_type_owned(allocator, shape_ty, bindings.items, owned_types);
        if (type_contains_type_param(template.type_params, concrete_ty)) return false;
    }

    const ret_ty = shape.return_type orelse return true;
    const concrete_shape = try instantiate_func_type_shape(allocator, shape, bindings.items, owned_types);
    defer allocator.free(concrete_shape.param_types);
    const lambda_ret = (try infer_lambda_expr_return_type(allocator, tokens, lambda, concrete_shape, locals, ctx)) orelse return false;
    return try match_or_bind_generic_type(allocator, ret_ty, lambda_ret, template.type_params, bindings, owned_types);
}

pub fn infer_untyped_generic_param_abi_type(
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

pub fn bind_explicit_generic_call_type_args(allocator: std.mem.Allocator, tokens: []const lexer.Token, call_head: ExprCallHead, template: FuncDecl, bindings: *std.ArrayList(GenericTypeBinding), owned_types: *std.ArrayList([]const u8)) !bool {
    if (!call_head_has_type_args(call_head)) return true;
    if (template.type_params.len == 0) return false;

    var type_start = call_head.type_args_start;
    var type_idx: usize = 0;
    while (type_start < call_head.type_args_end) {
        if (type_idx >= template.type_params.len) return false;
        if (tok_eq(tokens[type_start], ",")) return false;

        const type_end = findTypeArgEnd(tokens, type_start, call_head.type_args_end);
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

pub fn clone_generic_type_bindings_owned(allocator: std.mem.Allocator, bindings: []const GenericTypeBinding, owned_types: *std.ArrayList([]const u8)) ![]const GenericTypeBinding {
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

pub fn generic_bindings_cover_type_params(template: FuncDecl, bindings: []const GenericTypeBinding) bool {
    for (template.type_params) |type_param| {
        if (find_generic_binding(bindings, type_param) == null) return false;
    }
    return true;
}

pub fn type_contains_type_param(type_params: []const []const u8, ty: []const u8) bool {
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

pub fn bind_generic_type_from_concrete(allocator: std.mem.Allocator, expected_ty: []const u8, actual_ty: []const u8, type_params: []const []const u8, bindings: *std.ArrayList(GenericTypeBinding), owned_types: *std.ArrayList([]const u8)) CodegenError!bool {
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
    if (findTopLevelTypeSeparator(expected_args.args, ',') == null and findTopLevelTypeSeparator(actual_args.args, ',') == null) {
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

pub fn bind_generic_type_list_from_concrete(allocator: std.mem.Allocator, expected: []const u8, actual: []const u8, sep: u8, type_params: []const []const u8, bindings: *std.ArrayList(GenericTypeBinding), owned_types: *std.ArrayList([]const u8)) CodegenError!bool {
    if (findTopLevelTypeSeparator(expected, sep) == null and findTopLevelTypeSeparator(actual, sep) == null) return false;

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

pub fn generic_instance_name(allocator: std.mem.Allocator, template: FuncDecl, bindings: []const GenericTypeBinding, param_tys: []const []const u8, callback_bindings: []const CallbackBinding) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, template.name);
    for (template.type_params) |type_param| {
        const binding = find_generic_binding(bindings, type_param) orelse return error.NoMatchingCall;
        try out.appendSlice(allocator, "__");
        try appendMangledTypeName(allocator, &out, binding.ty);
    }
    if (func_has_untyped_params(template)) {
        try out.appendSlice(allocator, "__abi");
        for (param_tys) |param_ty| {
            try out.appendSlice(allocator, "__");
            try appendMangledTypeName(allocator, &out, param_ty);
        }
    }
    for (callback_bindings) |binding| {
        try append_fmt(allocator, &out, "__cb_{d}_{d}", .{ binding.arg_start, binding.arg_end });
    }
    return out.toOwnedSlice(allocator);
}

pub fn func_has_untyped_params(func: FuncDecl) bool {
    for (func.params) |param| {
        if (param.ty.len == 0) return true;
    }
    return false;
}

pub fn find_generic_template_for_call(functions: []const FuncDecl, tokens: []const lexer.Token, ctx: CodegenContext, name: []const u8) ?FuncDecl {
    for (functions) |func| {
        if (!func.is_generic_template) continue;
        if (!module_tokens_equal(func.tokens, tokens)) continue;
        if (std.mem.eql(u8, func.name, name) or same_callable_source_name(func.source_name, name)) return func;
    }

    const import_ref = find_codegen_import_by_alias(tokens, name) orelse return null;
    const import_ctx = imported_alias_context_for_tokens(ctx.imported_alias_ctx, tokens) orelse return null;
    const child_idx = find_imported_module_index_no_alloc(import_ctx.graph, import_ctx.module_idx, import_ref) orelse return null;
    const child_tokens = import_ctx.graph.modules[child_idx].tokens;
    for (functions) |func| {
        if (!func.is_generic_template) continue;
        if (!module_tokens_equal(func.tokens, child_tokens)) continue;
        if (std.mem.eql(u8, func.name, import_ref.alias)) return func;
        if (same_callable_source_name(func.source_name, publicDeclName(import_ref.target))) return func;
    }
    return null;
}

pub fn infer_generic_call_union_result_layout(allocator: std.mem.Allocator, tokens: []const lexer.Token, call_head: ExprCallHead, locals: *const LocalSet, ctx: CodegenContext, result_owned_types: *std.ArrayList([]const u8)) CodegenError!?UnionLayout {
    const name = publicDeclName(tokens[call_head.name_idx].lexeme);
    for (ctx.functions) |template| {
        if (!generic_template_matches_call_site(template, tokens, ctx, name)) continue;

        var bindings = std.ArrayList(GenericTypeBinding).empty;
        defer bindings.deinit(allocator);
        var param_tys = std.ArrayList([]const u8).empty;
        defer param_tys.deinit(allocator);
        var owned_types = std.ArrayList([]const u8).empty;
        defer {
            for (owned_types.items) |owned| allocator.free(owned);
            owned_types.deinit(allocator);
        }

        if (!try bind_explicit_generic_call_type_args(allocator, tokens, call_head, template, &bindings, &owned_types)) continue;
        if (!try bind_generic_func_call(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, template, &bindings, &param_tys, &owned_types)) continue;
        if (!generic_bindings_cover_type_params(template, bindings.items)) continue;
        const layout = template.result_union orelse continue;
        return try clone_union_layout_substituted(
            allocator,
            template.tokens,
            ctx.structs,
            ctx.struct_layouts,
            layout,
            bindings.items,
            result_owned_types,
        );
    }
    return null;
}
