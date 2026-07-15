//! Generic function instantiation / type binding (extracted from gen_lower).
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const type_util = @import("type_name.zig");
const codegen_tokens = @import("codegen_tokens.zig");
const codegen_names = @import("codegen_names.zig");
const gen_types = @import("gen_types.zig");
const gen_collect = @import("gen_collect.zig");
const gen_import = @import("gen_import.zig");
const gen_wasi_emit = @import("gen_wasi_emit.zig");
const gen_hooks = @import("gen_hooks.zig");
const gen_expr = @import("gen_expr.zig");
const gen_expr_collect = @import("gen_expr_collect.zig");
const gen_storage = @import("gen_storage.zig");
const gen_struct = @import("gen_struct.zig");
const gen_ctrl = @import("gen_ctrl.zig");
const gen_union_emit = @import("gen_union_emit.zig");
const codegen_union_layout = @import("codegen_union_layout.zig");
const gen_host = @import("gen_host.zig");
const codegen_wasi_registry = @import("codegen_wasi_registry.zig");
const gen_ownership = @import("gen_ownership.zig");
const ownership = @import("ownership.zig");
const ownership_facts = @import("ownership_facts.zig");
const imports = @import("imports.zig");
const test_runner = @import("test_runner.zig");
const payload_wat = @import("wat_payload.zig");
const storage_wat = @import("wat_storage.zig");

const LocalSet = gen_types.LocalSet;
const OwnedFuncTypeShape = gen_types.OwnedFuncTypeShape;
const FuncResultParse = gen_types.FuncResultParse;
const freeCallbackBindings = gen_types.freeCallbackBindings;
pub const freeFuncParams = gen_types.freeFuncParams;
const freeFuncResultItems = gen_types.freeFuncResultItems;
const CodegenContext = gen_types.CodegenContext;
const CodegenError = gen_types.CodegenError;
const StructDecl = gen_types.StructDecl;
const StructLayout = gen_types.StructLayout;
const FuncDecl = gen_types.FuncDecl;
const FuncParam = gen_types.FuncParam;
const FuncResultItem = gen_types.FuncResultItem;
const HostImport = gen_types.HostImport;
const FieldReflectionLoopHeader = gen_types.FieldReflectionLoopHeader;
const GenericTypeBinding = gen_types.GenericTypeBinding;
const PayloadEnumDecl = gen_types.PayloadEnumDecl;
const ValueEnumDecl = gen_types.ValueEnumDecl;
const CallbackBinding = gen_types.CallbackBinding;
const FuncTypeShape = gen_types.FuncTypeShape;
const ImportedAliasContext = gen_types.ImportedAliasContext;
const StringDataContext = gen_types.StringDataContext;
const ExprCallHead = gen_types.ExprCallHead;
const storageTypeNameForElemOwned = gen_types.storageTypeNameForElemOwned;
const UnionLayout = codegen_union_layout.UnionLayout;
const freeUnionLayout = codegen_union_layout.free_union_layout;
const WasiHostImport = codegen_wasi_registry.WasiHostImport;
const tokEq = codegen_tokens.tok_eq;
const findMatching = codegen_tokens.find_matching;
const findLineStart = codegen_tokens.find_line_start;
const findTopLevelToken = codegen_tokens.find_top_level_token;
const findArgEnd = codegen_tokens.find_arg_end;
const trimParens = codegen_tokens.trim_parens;
const publicDeclName = codegen_names.public_decl_name;
const appendFmt = codegen_names.append_fmt;
const findTopLevelTypeSeparator = codegen_tokens.find_top_level_type_separator;
const findTopLevelTypeSeparatorFrom = codegen_tokens.find_top_level_type_separator_from;
const findStoragePrimitiveLocal = gen_wasi_emit.findStoragePrimitiveLocal;
const isStorageTypeName = gen_wasi_emit.isStorageTypeName;
const tupleArity = gen_wasi_emit.tupleArity;
const isTupleTypeName = gen_wasi_emit.isTupleTypeName;
const appendFuncParamLocals = gen_expr.appendFuncParamLocals;
const funcHasCallbackParams = gen_expr.funcHasCallbackParams;
const fieldReflectionLoopHeader = gen_ctrl.fieldReflectionLoopHeader;
const appendConditionNarrowingForBranch = gen_ctrl.appendConditionNarrowingForBranch;
const cloneUnionLayoutSubstituted = gen_union_emit.cloneUnionLayoutSubstituted;
const fieldReflectionLocalNamePrefix = gen_struct.fieldReflectionLocalNamePrefix;
const fieldVisibleFromTokens = gen_struct.fieldVisibleFromTokens;
const borrowedFieldMetaLocalSet = gen_struct.borrowedFieldMetaLocalSet;
const applyGuardLoopControlNarrowing = gen_struct.applyGuardLoopControlNarrowing;
const applyCollectGuardReturnNarrowing = gen_struct.applyCollectGuardReturnNarrowing;
const substituteStructFieldType = gen_storage.substituteStructFieldType;
pub const findFuncDeclForCallHead = gen_storage.findFuncDeclForCallHead;
const inferExprType = gen_storage.inferExprType;
const findCallbackBinding = gen_storage.findCallbackBinding;
const callbackBindingsHaveSameShape = gen_storage.callbackBindingsHaveSameShape;
const callArgMatchesParam = gen_storage.callArgMatchesParam;
const callArgsMatchVariadicTail = gen_storage.callArgsMatchVariadicTail;
const lambdaExprShape = gen_storage.lambdaExprShape;
const callbackBindingHasSameConcreteArg = gen_storage.callbackBindingHasSameConcreteArg;
const lambdaParamTypeName = gen_storage.lambdaParamTypeName;
const lambdaExplicitReturnType = gen_storage.lambdaExplicitReturnType;
const inferLambdaExprReturnType = gen_storage.inferLambdaExprReturnType;
const cloneLocalSet = gen_storage.cloneLocalSet;
const findCallbackRefFunc = gen_storage.findCallbackRefFunc;
const findTopLevelGuardLoopControl = gen_ownership.findTopLevelGuardLoopControl;
const moduleTokensEqual = codegen_tokens.module_tokens_equal;
pub const findStartFunc = codegen_tokens.find_start_func;
pub const findToken = codegen_tokens.find_token;
const findStmtEnd = codegen_tokens.find_stmt_end;
const findTypeArgEnd = codegen_tokens.find_type_arg_end;
const appendMangledTypeName = codegen_names.append_mangled_type_name;
const isCoreWasmScalar = codegen_names.is_core_wasm_scalar;
const findCodegenImportByAlias = gen_import.findCodegenImportByAlias;
const findImportedModuleIndexNoAlloc = gen_import.findImportedModuleIndexNoAlloc;
const importedAliasContextForTokens = gen_import.importedAliasContextForTokens;
pub const callHeadAt = gen_import.callHeadAt;
const callHeadHasTypeArgs = gen_import.callHeadHasTypeArgs;
const parseCodegenTypeExpr = gen_collect.parseCodegenTypeExpr;
const parseFuncParamTypeExpr = gen_collect.parseFuncParamTypeExpr;
const isTopLevelCommaAny = gen_collect.isTopLevelCommaAny;
const bindGenericType = gen_collect.bindGenericType;
pub const findGenericBinding = gen_collect.findGenericBinding;
const substituteGenericTypeOwned = gen_collect.substituteGenericTypeOwned;
const isTypeIdentStart = gen_collect.isTypeIdentStart;
const isTypeIdentPart = gen_collect.isTypeIdentPart;
const genericTypeArgsRange = gen_collect.genericTypeArgsRange;
const sameCallableSourceName = gen_collect.sameCallableSourceName;
const hasTypeParamName = gen_collect.hasTypeParamName;
const findFuncDecl = gen_collect.findFuncDecl;
pub const funcParamAbiType = gen_collect.funcParamAbiType;
const findStructDecl = gen_collect.findStructDecl;
const findStructLayout = gen_collect.findStructLayout;
const appendTupleLeafTypes = gen_collect.appendTupleLeafTypes;
const codegenTypesCompatible = gen_wasi_emit.codegenTypesCompatible;
const collectBodyLocals = gen_expr.collectBodyLocals;

pub fn parseLambdaParamNames(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize) ![]const []const u8 {
    var out = std.ArrayList([]const u8).empty;
    errdefer out.deinit(allocator);

    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !isTopLevelCommaAny(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            if (tokens[seg_start].kind != .ident) return error.InvalidLambdaExpr;
            try out.append(allocator, tokens[seg_start].lexeme);
        }
        seg_start = i + 1;
    }
    return out.toOwnedSlice(allocator);
}


pub fn parseLambdaParamTypes(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize) ![]?[]const u8 {
    var out = std.ArrayList(?[]const u8).empty;
    errdefer out.deinit(allocator);

    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !isTopLevelCommaAny(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            try out.append(allocator, lambdaParamTypeName(tokens, seg_start, i));
        }
        seg_start = i + 1;
    }
    return out.toOwnedSlice(allocator);
}


pub fn explicitLambdaTypesMatch(target_types: []const ?[]const u8, lambda_types: []const ?[]const u8) bool {
    if (target_types.len != lambda_types.len) return false;
    for (lambda_types, 0..) |lambda_type, idx| {
        const expected = lambda_type orelse continue;
        const actual = target_types[idx] orelse return false;
        if (!std.mem.eql(u8, actual, expected)) return false;
    }
    return true;
}


pub fn collectGenericFuncInstancesForStart(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    structs: []const StructDecl,
    value_enums: []const ValueEnumDecl,
    payload_enums: []const PayloadEnumDecl,
    struct_layouts: []const StructLayout,
    host_imports: []const HostImport,
    wasi_imports: []const WasiHostImport,
    string_data: *const StringDataContext,
    modules: []const imports.ModuleRecord,
    imported_alias_ctx: ?ImportedAliasContext,
    functions: *std.ArrayList(FuncDecl)) !void {
    if (findStartFunc(tokens)) |idx| {
        try collectGenericFuncInstancesInStartBody(
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
    try collectGenericFuncInstancesForConcreteFuncs(allocator, tokens, structs, value_enums, payload_enums, struct_layouts, host_imports, wasi_imports, string_data, modules, imported_alias_ctx, functions);
}


pub fn collectGenericFuncInstancesInStartBody(
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
    const close_params = findMatching(tokens, start_idx + 1, "(", ")") catch return;
    const open_body = findToken(tokens, close_params + 1, tokens.len, "{") orelse return;
    const body_end = findMatching(tokens, open_body, "{", "}") catch return;

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
    try collectBodyLocals(allocator, tokens, open_body + 1, body_end, ctx, &locals);
    try collectGenericFuncInstancesInRange(allocator, tokens, open_body + 1, body_end, &locals, ctx, functions);
}


pub fn collectGenericFuncInstancesForTests(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    test_decls: []const test_runner.TestDecl,
    structs: []const StructDecl,
    value_enums: []const ValueEnumDecl,
    payload_enums: []const PayloadEnumDecl,
    struct_layouts: []const StructLayout,
    host_imports: []const HostImport,
    wasi_imports: []const WasiHostImport,
    string_data: *const StringDataContext,
    modules: []const imports.ModuleRecord,
    imported_alias_ctx: ?ImportedAliasContext,
    functions: *std.ArrayList(FuncDecl)) !void {
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
        try collectBodyLocals(allocator, tokens, decl.body_start, decl.body_end, ctx, &locals);
        try collectGenericFuncInstancesInRange(allocator, tokens, decl.body_start, decl.body_end, &locals, ctx, functions);
    }
    try collectGenericFuncInstancesForConcreteFuncs(allocator, tokens, structs, value_enums, payload_enums, struct_layouts, host_imports, wasi_imports, string_data, modules, imported_alias_ctx, functions);
}


pub fn collectGenericFuncInstancesForConcreteFuncs(
    allocator: std.mem.Allocator,
    entry_tokens: []const lexer.Token,
    structs: []const StructDecl,
    value_enums: []const ValueEnumDecl,
    payload_enums: []const PayloadEnumDecl,
    struct_layouts: []const StructLayout,
    host_imports: []const HostImport,
    wasi_imports: []const WasiHostImport,
    string_data: *const StringDataContext,
    modules: []const imports.ModuleRecord,
    imported_alias_ctx: ?ImportedAliasContext,
    functions: *std.ArrayList(FuncDecl)) !void {
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
        try appendFuncParamLocals(allocator, func, ctx, &locals);
        try collectBodyLocals(allocator, func.tokens, func.body_start, func.body_end, ctx, &locals);
        try collectGenericFuncInstancesInRange(allocator, func.tokens, func.body_start, func.body_end, &locals, ctx, functions);
    }
}


pub fn instantiateCallbackShape(
    allocator: std.mem.Allocator,
    param: FuncParam,
    bindings: []const GenericTypeBinding,
    owned_types: *std.ArrayList([]const u8)) !?OwnedFuncTypeShape {
    const callback = param.callback orelse return null;
    const param_types = try allocator.alloc(?[]const u8, callback.shape.param_types.len);
    for (callback.shape.param_types, 0..) |param_ty, idx| {
        param_types[idx] = if (param_ty) |ty| try substituteGenericTypeOwned(allocator, ty, bindings, owned_types) else null;
    }
    return .{
        .shape = .{
            .param_types = param_types,
            .return_type = if (callback.shape.return_type) |ty| try substituteGenericTypeOwned(allocator, ty, bindings, owned_types) else null,
        },
        .owned = true,
    };
}


pub fn instantiateFuncTypeShape(
    allocator: std.mem.Allocator,
    shape: FuncTypeShape,
    bindings: []const GenericTypeBinding,
    owned_types: *std.ArrayList([]const u8)) !FuncTypeShape {
    const param_types = try allocator.alloc(?[]const u8, shape.param_types.len);
    errdefer allocator.free(param_types);
    for (shape.param_types, 0..) |param_ty, idx| {
        param_types[idx] = if (param_ty) |ty| try substituteGenericTypeOwned(allocator, ty, bindings, owned_types) else null;
    }
    return .{
        .param_types = param_types,
        .return_type = if (shape.return_type) |ty| try substituteGenericTypeOwned(allocator, ty, bindings, owned_types) else null,
    };
}


pub fn callbackBindingsForCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    call_head: ExprCallHead,
    params: []const FuncParam,
    ctx: ?CodegenContext) ![]const CallbackBinding {
    var out = std.ArrayList(CallbackBinding).empty;
    errdefer freeCallbackBindings(allocator, out.items);

    var arg_start = call_head.args_start;
    var param_idx: usize = 0;
    while (arg_start < call_head.args_end and param_idx < params.len) {
        const arg_end = findArgEnd(tokens, arg_start, call_head.args_end);
        const param = params[param_idx];
        if (param.callback) |callback| {
            if (try resolveCallbackBindingArg(allocator, tokens, arg_start, arg_end, param.name, callback.shape, ctx)) |binding| {
                try out.append(allocator, binding);
            }
        }

        param_idx += 1;
        arg_start = arg_end;
        if (arg_start < call_head.args_end and tokEq(tokens[arg_start], ",")) arg_start += 1;
    }

    return out.toOwnedSlice(allocator);
}


pub fn resolveCallbackBindingArg(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    arg_start: usize,
    arg_end: usize,
    param_name: []const u8,
    shape: FuncTypeShape,
    ctx: ?CodegenContext) !?CallbackBinding {
    if (lambdaExprShape(tokens, arg_start, arg_end)) |lambda| {
        const lambda_params = try parseLambdaParamNames(allocator, tokens, lambda.open_params + 1, lambda.close_params);
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
        if (findCallbackBinding(codegen_ctx.callback_bindings, tokens[arg_start].lexeme)) |binding| {
            if (!callbackBindingsHaveSameShape(binding.shape, shape)) return null;
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



pub fn cloneFuncParams(allocator: std.mem.Allocator, params: []const FuncParam) ![]const FuncParam {
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


pub fn collectGenericFuncInstancesInRange(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    functions: *std.ArrayList(FuncDecl),
) anyerror!void {
    var active_locals = try cloneLocalSet(allocator, locals);
    defer active_locals.deinit(allocator);

    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        var current_ctx = ctx;
        current_ctx.functions = functions.items;
        const stmt_end = findStmtEnd(tokens, i, end_idx);
        if (tokEq(tokens[i], "if") and findTopLevelToken(tokens, i + 1, stmt_end, "return") != null) {
            try collectGenericFuncInstancesInGuardReturn(allocator, tokens, i, stmt_end, &active_locals, current_ctx, functions);
            i = stmt_end - 1;
            continue;
        }
        if (tokEq(tokens[i], "if") and findTopLevelGuardLoopControl(tokens, i + 1, stmt_end) != null) {
            try collectGenericFuncInstancesInGuardLoopControl(allocator, tokens, i, stmt_end, &active_locals, current_ctx, functions);
            i = stmt_end - 1;
            continue;
        }
        if (fieldReflectionLoopHeader(tokens, i, stmt_end, current_ctx, &active_locals)) |header| {
            try collectGenericFuncInstancesInFieldReflectionLoop(allocator, tokens, header, &active_locals, current_ctx, functions);
            i = stmt_end - 1;
            continue;
        }

        const call_head = callHeadAt(tokens, i, end_idx) orelse continue;
        if (call_head.is_intrinsic) continue;
        try collectGenericFuncInstancesInCallArgs(allocator, tokens, call_head.args_start, call_head.args_end, &active_locals, current_ctx, functions);
        current_ctx.functions = functions.items;
        if (findFuncDeclForCallHead(tokens, call_head, &active_locals, current_ctx)) |func| {
            if (funcHasCallbackParams(func) and func.callback_bindings.len == 0) {
                try collectConcreteCallbackFuncInstanceForCall(allocator, tokens, call_head, current_ctx, func, functions);
            }
            try applyCollectGuardReturnNarrowing(allocator, tokens, i, stmt_end, &active_locals, current_ctx);
            i = call_head.args_end;
            continue;
        }
        var expected_owned_types = std.ArrayList([]const u8).empty;
        defer {
            for (expected_owned_types.items) |owned| allocator.free(owned);
            expected_owned_types.deinit(allocator);
        }
        const expected_result_ty = try directCallExpectedResultType(allocator, tokens, call_head.name_idx, stmt_end, current_ctx, &expected_owned_types);
        try collectGenericFuncInstancesForCall(allocator, tokens, call_head, &active_locals, current_ctx, expected_result_ty, functions);
        try applyCollectGuardReturnNarrowing(allocator, tokens, i, stmt_end, &active_locals, current_ctx);
        i = call_head.args_end;
    }
}


pub fn collectGenericFuncInstancesInGuardReturn(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *LocalSet,
    ctx: CodegenContext,
    functions: *std.ArrayList(FuncDecl)) !void {
    const return_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "return") orelse return;
    try collectGenericFuncInstancesInRange(allocator, tokens, start_idx + 1, return_idx, locals, ctx, functions);

    var return_locals = try cloneLocalSet(allocator, locals);
    defer return_locals.deinit(allocator);
    try appendConditionNarrowingForBranch(allocator, tokens, start_idx + 1, return_idx, &return_locals, ctx, true);
    if (return_idx + 1 < end_idx) {
        try collectGenericFuncInstancesInRange(allocator, tokens, return_idx + 1, end_idx, &return_locals, ctx, functions);
    }

    try applyCollectGuardReturnNarrowing(allocator, tokens, start_idx, end_idx, locals, ctx);
}


pub fn collectGenericFuncInstancesInGuardLoopControl(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *LocalSet,
    ctx: CodegenContext,
    functions: *std.ArrayList(FuncDecl)) !void {
    const control_idx = findTopLevelGuardLoopControl(tokens, start_idx + 1, end_idx) orelse return;
    try collectGenericFuncInstancesInRange(allocator, tokens, start_idx + 1, control_idx, locals, ctx, functions);
    try applyGuardLoopControlNarrowing(allocator, tokens, start_idx, end_idx, locals, ctx);
}


pub fn collectGenericFuncInstancesInCallArgs(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    functions: *std.ArrayList(FuncDecl)) !void {
    var arg_start = args_start;
    while (arg_start < args_end) {
        const arg_end = findArgEnd(tokens, arg_start, args_end);
        if (arg_end == arg_start) return error.NoMatchingCall;
        try collectGenericFuncInstancesInRange(allocator, tokens, arg_start, arg_end, locals, ctx, functions);
        arg_start = arg_end;
        if (arg_start < args_end and tokEq(tokens[arg_start], ",")) arg_start += 1;
    }
}


pub fn collectGenericFuncInstancesInFieldReflectionLoop(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    header: FieldReflectionLoopHeader,
    locals: *const LocalSet,
    ctx: CodegenContext,
    functions: *std.ArrayList(FuncDecl),
) anyerror!void {
    var visible_index: usize = 0;
    for (header.decl.fields, 0..) |field, decl_index| {
        if (!fieldVisibleFromTokens(field, header.decl, tokens)) continue;
        const prefix = try fieldReflectionLocalNamePrefix(allocator, header, visible_index);
        defer allocator.free(prefix);
        var field_locals = try borrowedFieldMetaLocalSet(allocator, locals, .{
            .name = header.field_name,
            .struct_name = header.decl.name,
            .decl_index = decl_index,
            .visible_index = visible_index,
        }, prefix);
        defer field_locals.deinit(allocator);
        field_locals.local_name_prefix = prefix;
        try collectGenericFuncInstancesInRange(allocator, tokens, header.open_brace + 1, header.close_brace, &field_locals, ctx, functions);
        visible_index += 1;
    }
}


pub fn directCallExpectedResultType(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    call_start: usize,
    stmt_end: usize,
    ctx: CodegenContext,
    owned_types: *std.ArrayList([]const u8)) CodegenError!?[]const u8 {
    const stmt_start = findLineStart(tokens, call_start);
    const eq_idx = findTopLevelToken(tokens, stmt_start, stmt_end, "=") orelse return null;
    const rhs = trimParens(tokens, eq_idx + 1, stmt_end);
    if (rhs.start != call_start) return null;
    return typedBindingExpectedType(allocator, tokens, stmt_start, eq_idx, ctx, owned_types);
}


pub fn typedBindingExpectedType(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    stmt_start: usize,
    eq_idx: usize,
    ctx: CodegenContext,
    owned_types: *std.ArrayList([]const u8)) CodegenError!?[]const u8 {
    if (stmt_start + 2 >= eq_idx) return null;
    if (tokens[stmt_start].kind != .ident) return null;
    const parsed = (try parseFuncParamTypeExpr(allocator, tokens, stmt_start + 1, eq_idx, owned_types)) orelse return null;
    if (parsed.next_idx != eq_idx) return null;
    return try substituteGenericTypeOwned(allocator, parsed.ty, ctx.type_bindings, owned_types);
}


pub fn collectGenericFuncInstanceForCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    call_head: ExprCallHead,
    locals: *const LocalSet,
    ctx: CodegenContext,
    template: FuncDecl,
    expected_result_ty: ?[]const u8,
    functions: *std.ArrayList(FuncDecl)) !void {
    var bindings = std.ArrayList(GenericTypeBinding).empty;
    defer bindings.deinit(allocator);

    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }

    if (!try bindExplicitGenericCallTypeArgs(allocator, tokens, call_head, template, &bindings, &owned_types)) return;

    var param_tys = std.ArrayList([]const u8).empty;
    defer param_tys.deinit(allocator);
    if (!try bindGenericFuncCall(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, template, &bindings, &param_tys, &owned_types)) return;
    if (!try bindGenericExpectedResult(allocator, template, expected_result_ty, &bindings, &owned_types)) return;
    if (!genericBindingsCoverTypeParams(template, bindings.items)) return;
    if (!callHeadHasTypeArgs(call_head) and try genericOverloadCoversGenericParams(allocator, functions.items, template, param_tys.items)) {
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
            try storageTypeNameForElemOwned(allocator, param_tys.items[idx], &owned_types)
        else
            null;
        try params.append(allocator, .{
            .name = param.name,
            .ty = param_tys.items[idx],
            .abi_ty = instance_param_abi_ty,
            .variadic = param.variadic,
            .callback = try instantiateCallbackShape(allocator, param, bindings.items, &owned_types),
        });
    }
    const param_items = try params.toOwnedSlice(allocator);
    var param_items_owned = true;
    defer if (param_items_owned) freeFuncParams(allocator, param_items);

    const callback_bindings = try callbackBindingsForCall(allocator, tokens, call_head, param_items, ctx);
    var callback_bindings_owned = true;
    defer if (callback_bindings_owned) freeCallbackBindings(allocator, callback_bindings);

    if (!callHeadHasTypeArgs(call_head) and concreteOverloadCoversGenericParams(functions.items, template, param_items, callback_bindings)) {
        return;
    }

    const instance_name = try genericInstanceName(allocator, template, bindings.items, param_tys.items, callback_bindings);
    var instance_name_owned = true;
    defer if (instance_name_owned) allocator.free(instance_name);
    if (findFuncDecl(functions.items, instance_name) != null) {
        return;
    }
    var results = std.ArrayList([]const u8).empty;
    errdefer results.deinit(allocator);
    for (template.results) |result| {
        try results.append(allocator, try substituteGenericTypeOwned(allocator, result, bindings.items, &owned_types));
    }
    const result_tys = try results.toOwnedSlice(allocator);
    var result_tys_owned = true;
    errdefer if (result_tys_owned) allocator.free(result_tys);
    const parsed_results = try instantiateGenericFuncResultItems(
        allocator,
        template,
        result_tys,
        bindings.items,
        ctx.structs,
        ctx.struct_layouts,
        &owned_types,
    );
    errdefer freeFuncResultItems(allocator, parsed_results.items, parsed_results.result_union);
    if (parsed_results.types.ptr != result_tys.ptr) {
        allocator.free(result_tys);
    }
    result_tys_owned = false;
    const instance_result_tys = parsed_results.types;
    errdefer allocator.free(instance_result_tys);
    const type_bindings = try cloneGenericTypeBindingsOwned(allocator, bindings.items, &owned_types);
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


pub fn bindGenericExpectedResult(
    allocator: std.mem.Allocator,
    template: FuncDecl,
    expected_result_ty: ?[]const u8,
    bindings: *std.ArrayList(GenericTypeBinding),
    owned_types: *std.ArrayList([]const u8)) CodegenError!bool {
    const expected = expected_result_ty orelse return true;
    const template_result = genericTemplateLogicalResultType(template) orelse return true;
    if (!typeContainsTypeParam(template.type_params, template_result)) {
        return codegenTypesCompatible(template_result, expected);
    }
    return try bindGenericTypeFromConcrete(allocator, template_result, expected, template.type_params, bindings, owned_types);
}


pub fn genericTemplateLogicalResultType(template: FuncDecl) ?[]const u8 {
    if (template.result_union) |layout| return layout.source_ty;
    if (template.result_items.len == 1) return template.result_items[0].ty;
    if (template.results.len == 1) return template.results[0];
    return null;
}


pub fn collectGenericFuncInstancesForCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    call_head: ExprCallHead,
    locals: *const LocalSet,
    ctx: CodegenContext,
    expected_result_ty: ?[]const u8,
    functions: *std.ArrayList(FuncDecl)) !void {
    const name = publicDeclName(tokens[call_head.name_idx].lexeme);
    const initial_len = functions.items.len;
    var idx: usize = 0;
    while (idx < initial_len) : (idx += 1) {
        const template = functions.items[idx];
        if (!genericTemplateMatchesCallSite(template, tokens, ctx, name)) continue;
        try collectGenericFuncInstanceForCall(allocator, tokens, call_head, locals, ctx, template, expected_result_ty, functions);
    }
}


pub fn genericTemplateMatchesCallSite(template: FuncDecl, tokens: []const lexer.Token, ctx: CodegenContext, name: []const u8) bool {
    if (!template.is_generic_template) return false;
    if (moduleTokensEqual(template.tokens, tokens)) {
        return std.mem.eql(u8, template.name, name) or sameCallableSourceName(template.source_name, name);
    }

    const import_ref = findCodegenImportByAlias(tokens, name) orelse return false;
    const import_ctx = importedAliasContextForTokens(ctx.imported_alias_ctx, tokens) orelse return false;
    const child_idx = findImportedModuleIndexNoAlloc(import_ctx.graph, import_ctx.module_idx, import_ref) orelse return false;
    const child_tokens = import_ctx.graph.modules[child_idx].tokens;
    if (!moduleTokensEqual(template.tokens, child_tokens)) return false;
    if (std.mem.eql(u8, template.name, import_ref.alias)) return true;
    return sameCallableSourceName(template.source_name, publicDeclName(import_ref.target));
}


pub fn collectConcreteCallbackFuncInstanceForCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    call_head: ExprCallHead,
    ctx: CodegenContext,
    func: FuncDecl,
    functions: *std.ArrayList(FuncDecl)) !void {
    const param_items = try cloneFuncParams(allocator, func.params);
    var param_items_owned = true;
    defer if (param_items_owned) freeFuncParams(allocator, param_items);

    const callback_bindings = try callbackBindingsForCall(allocator, tokens, call_head, param_items, ctx);
    var callback_bindings_owned = true;
    defer if (callback_bindings_owned) freeCallbackBindings(allocator, callback_bindings);
    if (callback_bindings.len == 0) return;

    const instance_name = try genericInstanceName(allocator, func, &.{}, &.{}, callback_bindings);
    var instance_name_owned = true;
    defer if (instance_name_owned) allocator.free(instance_name);
    if (findFuncDecl(functions.items, instance_name) != null) {
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
    const parsed_results = try instantiateGenericFuncResultItems(
        allocator,
        func,
        result_tys,
        &.{},
        ctx.structs,
        ctx.struct_layouts,
        &owned_types,
    );
    errdefer freeFuncResultItems(allocator, parsed_results.items, parsed_results.result_union);
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
    try appendFuncParamLocals(allocator, instance, instance_ctx, &instance_locals);
    try collectBodyLocals(allocator, instance.tokens, instance.body_start, instance.body_end, instance_ctx, &instance_locals);
    try collectGenericFuncInstancesInRange(allocator, instance.tokens, instance.body_start, instance.body_end, &instance_locals, instance_ctx, functions);
}


pub fn concreteOverloadCoversGenericParams(
    functions: []const FuncDecl,
    template: FuncDecl,
    params: []const FuncParam,
    callback_bindings: []const CallbackBinding) bool {
    for (functions) |func| {
        if (func.is_generic_template) continue;
        if (!moduleTokensEqual(func.tokens, template.tokens)) continue;
        if (!sameCallableSourceName(func.source_name, template.source_name)) continue;
        if (func.params.len != params.len) continue;
        if (!callbackBindingsHaveSameConcreteArgs(func.callback_bindings, callback_bindings)) continue;

        var matches = true;
        for (func.params, 0..) |param, idx| {
            if (!funcParamsHaveSameConcreteCallShape(param, params[idx])) {
                matches = false;
                break;
            }
        }
        if (matches) return true;
    }
    return false;
}


pub fn callbackBindingsHaveSameConcreteArgs(left: []const CallbackBinding, right: []const CallbackBinding) bool {
    if (left.len != right.len) return false;
    for (left, 0..) |left_binding, idx| {
        if (!callbackBindingHasSameConcreteArg(left_binding, right[idx])) return false;
    }
    return true;
}



pub fn funcParamsHaveSameConcreteCallShape(left: FuncParam, right: FuncParam) bool {
    if (left.variadic != right.variadic) return false;
    if (left.callback != null or right.callback != null) {
        const left_callback = left.callback orelse return false;
        const right_callback = right.callback orelse return false;
        return callbackBindingsHaveSameShape(left_callback.shape, right_callback.shape);
    }
    return std.mem.eql(u8, funcParamAbiType(left), funcParamAbiType(right));
}


pub fn genericOverloadCoversGenericParams(
    allocator: std.mem.Allocator,
    functions: []const FuncDecl,
    template: FuncDecl,
    param_tys: []const []const u8) !bool {
    const current_specificity = genericTemplateSpecificity(template);
    for (functions) |candidate| {
        if (!candidate.is_generic_template) continue;
        if (candidate.start_idx == template.start_idx and moduleTokensEqual(candidate.tokens, template.tokens)) continue;
        if (!moduleTokensEqual(candidate.tokens, template.tokens)) continue;
        if (!sameCallableSourceName(candidate.source_name, template.source_name)) continue;
        if (candidate.params.len != param_tys.len) continue;
        if (genericTemplateSpecificity(candidate) <= current_specificity) continue;
        if (try genericTemplateMatchesConcreteParams(allocator, candidate, param_tys)) return true;
    }
    return false;
}


pub fn genericTemplateSpecificity(template: FuncDecl) usize {
    var score: usize = 0;
    for (template.params) |param| {
        const ty = funcParamAbiType(param);
        if (!typeContainsTypeParam(template.type_params, ty)) {
            score += 2;
        } else if (!hasTypeParamName(template.type_params, ty)) {
            score += 1;
        }
    }
    return score;
}


pub fn genericTemplateMatchesConcreteParams(
    allocator: std.mem.Allocator,
    template: FuncDecl,
    param_tys: []const []const u8) !bool {
    var bindings = std.ArrayList(GenericTypeBinding).empty;
    defer bindings.deinit(allocator);
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }

    for (template.params, 0..) |param, idx| {
        if (param.callback != null or param.variadic) return false;
        if (!try bindGenericTypeFromConcrete(
            allocator,
            param.ty,
            param_tys[idx],
            template.type_params,
            &bindings,
            &owned_types,
        )) return false;
    }
    return genericBindingsCoverTypeParams(template, bindings.items);
}


pub fn instantiateGenericFuncResultItems(
    allocator: std.mem.Allocator,
    template: FuncDecl,
    result_tys: []const []const u8,
    bindings: []const GenericTypeBinding,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    owned_types: *std.ArrayList([]const u8)) !FuncResultParse {
    if (template.result_union) |layout| {
        const next_layout = try cloneUnionLayoutSubstituted(
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
        if (isTupleTypeName(result_ty)) {
            const arity = tupleArity(result_ty) orelse return error.UnsupportedLowering;
            if (arity < 2) return error.NoMatchingCall;
            const leaf_start = types.items.len;
            try appendTupleLeafTypes(allocator, result_ty, &types);
            if (types.items.len - leaf_start < 2) return error.NoMatchingCall;
            for (types.items[leaf_start..]) |leaf_ty| {
                if (!isCoreWasmScalar(leaf_ty)) return error.NoMatchingCall;
            }
            try items.append(allocator, .{
                .ty = result_ty,
                .abi_start = abi_start,
                .abi_len = types.items.len - abi_start,
            });
            if (result_tys.len == 1) result_struct = result_ty;
            continue;
        }
        if (try appendUnmanagedStructResultAbi(
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
pub fn appendUnmanagedStructResultAbi(
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
    const decl = findStructDecl(structs, result_ty) orelse return false;
    if (findStructLayout(struct_layouts, result_ty) != null) return false;

    for (decl.fields) |field| {
        const field_ty = try substituteStructFieldType(allocator, decl, result_ty, field.ty, owned_types);
        if (!isCoreWasmScalar(field_ty)) return error.NoMatchingCall;
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


pub fn bindGenericFuncCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    template: FuncDecl,
    bindings: *std.ArrayList(GenericTypeBinding),
    param_tys: *std.ArrayList([]const u8),
    owned_types: *std.ArrayList([]const u8)) !bool {
    if (!try prebindGenericCallbackArgs(allocator, tokens, args_start, args_end, ctx, template, bindings, owned_types)) {
        return false;
    }

    var arg_start = args_start;
    var param_idx: usize = 0;
    while (arg_start < args_end) {
        if (param_idx >= template.params.len) return false;
        const arg_end = findArgEnd(tokens, arg_start, args_end);
        const param = template.params[param_idx];
        const param_ty = param.ty;
        if (param.variadic) {
            if (param_idx + 1 != template.params.len) return false;
            if (!try bindGenericVariadicTail(allocator, tokens, arg_start, args_end, locals, ctx, template, param_ty, bindings, owned_types)) {
                return false;
            }
            const concrete_ty = try substituteGenericTypeOwned(allocator, param_ty, bindings.items, owned_types);
            if (typeContainsTypeParam(template.type_params, concrete_ty)) return false;
            try param_tys.append(allocator, concrete_ty);
            return param_tys.items.len == template.params.len;
        } else if (param.callback != null) {
            if (!try bindGenericCallbackArg(allocator, tokens, arg_start, arg_end, locals, ctx, template, param, bindings, owned_types)) {
                return false;
            }
            try param_tys.append(allocator, param_ty);
        } else if (param_ty.len == 0) {
            const arg_ty = inferUntypedGenericParamAbiType(tokens, arg_start, arg_end, locals, ctx) orelse return false;
            try param_tys.append(allocator, arg_ty);
        } else if (typeContainsTypeParam(template.type_params, param_ty)) {
            const concrete_before = try substituteGenericTypeOwned(allocator, param_ty, bindings.items, owned_types);
            if (!typeContainsTypeParam(template.type_params, concrete_before)) {
                if (!callArgMatchesParam(tokens, arg_start, arg_end, locals, ctx, concrete_before)) return false;
                try param_tys.append(allocator, concrete_before);
                param_idx += 1;
                arg_start = arg_end;
                if (arg_start < args_end and tokEq(tokens[arg_start], ",")) arg_start += 1;
                continue;
            }
            const arg_ty = inferExprType(tokens, arg_start, arg_end, locals, ctx) orelse return false;
            if (!try bindGenericTypeFromConcrete(allocator, param_ty, arg_ty, template.type_params, bindings, owned_types)) {
                return false;
            }
            const concrete_ty = try substituteGenericTypeOwned(allocator, param_ty, bindings.items, owned_types);
            if (!callArgMatchesParam(tokens, arg_start, arg_end, locals, ctx, concrete_ty)) {
                return false;
            }
            try param_tys.append(allocator, concrete_ty);
        } else {
            const concrete_ty = try substituteGenericTypeOwned(allocator, param_ty, bindings.items, owned_types);
            if (!callArgMatchesParam(tokens, arg_start, arg_end, locals, ctx, concrete_ty)) {
                return false;
            }
            try param_tys.append(allocator, concrete_ty);
        }
        param_idx += 1;
        arg_start = arg_end;
        if (arg_start < args_end and tokEq(tokens[arg_start], ",")) arg_start += 1;
    }
    if (param_idx == template.params.len) {
        return param_tys.items.len == template.params.len;
    }
    if (param_idx + 1 == template.params.len and template.params[param_idx].variadic) {
        if (!try bindGenericVariadicTail(
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
        const concrete_ty = try substituteGenericTypeOwned(allocator, template.params[param_idx].ty, bindings.items, owned_types);
        if (typeContainsTypeParam(template.type_params, concrete_ty)) return false;
        try param_tys.append(allocator, concrete_ty);
        return param_tys.items.len == template.params.len;
    }
    return false;
}


pub fn prebindGenericCallbackArgs(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    ctx: CodegenContext,
    template: FuncDecl,
    bindings: *std.ArrayList(GenericTypeBinding),
    owned_types: *std.ArrayList([]const u8)) !bool {
    var arg_start = args_start;
    var param_idx: usize = 0;
    while (arg_start < args_end and param_idx < template.params.len) {
        const arg_end = findArgEnd(tokens, arg_start, args_end);
        const param = template.params[param_idx];
        if (param.callback) |callback| {
            if (!try prebindGenericCallbackArg(allocator, tokens, arg_start, arg_end, ctx, template, callback.shape, bindings, owned_types)) {
                return false;
            }
        }
        param_idx += 1;
        arg_start = arg_end;
        if (arg_start < args_end and tokEq(tokens[arg_start], ",")) arg_start += 1;
    }
    return true;
}


pub fn prebindGenericCallbackArg(
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
    if (lambdaExprShape(tokens, arg_start, arg_end) != null) {
        return prebindGenericCallbackLambda(allocator, tokens, arg_start, arg_end, template, shape, bindings, owned_types);
    }
    if (arg_end != arg_start + 1 or tokens[arg_start].kind != .ident) return true;
    return prebindGenericCallbackIdent(
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


pub fn prebindGenericTypeIfParam(
    allocator: std.mem.Allocator,
    expected_ty: []const u8,
    concrete_ty: []const u8,
    type_params: []const []const u8,
    bindings: *std.ArrayList(GenericTypeBinding),
    owned_types: *std.ArrayList([]const u8),
) !bool {
    if (!typeContainsTypeParam(type_params, expected_ty)) return true;
    return bindGenericTypeFromConcrete(allocator, expected_ty, concrete_ty, type_params, bindings, owned_types);
}


pub fn prebindGenericCallbackLambda(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    arg_start: usize,
    arg_end: usize,
    template: FuncDecl,
    shape: FuncTypeShape,
    bindings: *std.ArrayList(GenericTypeBinding),
    owned_types: *std.ArrayList([]const u8),
) !bool {
    const lambda = lambdaExprShape(tokens, arg_start, arg_end) orelse return false;
    const lambda_param_types = try parseLambdaParamTypes(allocator, tokens, lambda.open_params + 1, lambda.close_params);
    defer allocator.free(lambda_param_types);
    if (lambda_param_types.len != shape.param_types.len) return false;

    for (shape.param_types, 0..) |shape_ty, idx| {
        const expected_ty = shape_ty orelse continue;
        const explicit_ty = lambda_param_types[idx] orelse continue;
        if (!try prebindGenericTypeIfParam(allocator, expected_ty, explicit_ty, template.type_params, bindings, owned_types)) {
            return false;
        }
    }
    const ret_ty = shape.return_type orelse return true;
    const lambda_ret = lambdaExplicitReturnType(tokens, lambda) orelse return true;
    return try prebindGenericTypeIfParam(allocator, ret_ty, lambda_ret, template.type_params, bindings, owned_types);
}


pub fn prebindGenericCallbackIdent(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    arg_start: usize,
    ctx: CodegenContext,
    template: FuncDecl,
    shape: FuncTypeShape,
    bindings: *std.ArrayList(GenericTypeBinding),
    owned_types: *std.ArrayList([]const u8),
) !bool {
    const binding = findCallbackBinding(ctx.callback_bindings, tokens[arg_start].lexeme) orelse {
        return prebindGenericCallbackFuncRef(
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
        if (!try prebindGenericTypeIfParam(allocator, expected_ty, upstream_ty, template.type_params, bindings, owned_types)) {
            return false;
        }
    }
    const ret_ty = shape.return_type orelse return true;
    const upstream_ret = binding.shape.return_type orelse return true;
    return try prebindGenericTypeIfParam(allocator, ret_ty, upstream_ret, template.type_params, bindings, owned_types);
}


pub fn prebindGenericCallbackFuncRef(
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
        if (!moduleTokensEqual(func.tokens, tokens)) continue;
        if (!sameCallableSourceName(func.source_name, func_name)) continue;
        if (func.params.len != shape.param_types.len) continue;

        for (shape.param_types, 0..) |shape_ty, idx| {
            const expected_ty = shape_ty orelse continue;
            if (!try prebindGenericTypeIfParam(
                allocator,
                expected_ty,
                funcParamAbiType(func.params[idx]),
                template.type_params,
                bindings,
                owned_types,
            )) return false;
        }
        if (shape.return_type) |ret_ty| {
            if (!typeContainsTypeParam(template.type_params, ret_ty)) return true;
            const func_ret = genericTemplateLogicalResultType(func) orelse return false;
            if (!try bindGenericTypeFromConcrete(allocator, ret_ty, func_ret, template.type_params, bindings, owned_types)) {
                return false;
            }
        }
        return true;
    }
    return true;
}


pub fn bindGenericVariadicTail(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    template: FuncDecl,
    param_ty: []const u8,
    bindings: *std.ArrayList(GenericTypeBinding),
    owned_types: *std.ArrayList([]const u8)) !bool {
    if (args_start < args_end and tokEq(tokens[args_start], "...")) {
        const rest_start = args_start + 1;
        if (findArgEnd(tokens, rest_start, args_end) != args_end) return false;
        if (rest_start + 1 != args_end or tokens[rest_start].kind != .ident) return false;
        const rest = findStoragePrimitiveLocal(locals.storage_locals.items, tokens[rest_start].lexeme) orelse return false;
        if (typeContainsTypeParam(template.type_params, param_ty)) {
            if (!try bindGenericTypeFromConcrete(allocator, param_ty, rest.elem_ty, template.type_params, bindings, owned_types)) return false;
        }
    } else {
        var tail_start = args_start;
        while (tail_start < args_end) {
            const tail_end = findArgEnd(tokens, tail_start, args_end);
            if (tail_end == tail_start) return false;
            if (typeContainsTypeParam(template.type_params, param_ty)) {
                const actual_ty = inferExprType(tokens, tail_start, tail_end, locals, ctx) orelse {
                    tail_start = tail_end;
                    if (tail_start < args_end and tokEq(tokens[tail_start], ",")) tail_start += 1;
                    continue;
                };
                if (!try bindGenericTypeFromConcrete(allocator, param_ty, actual_ty, template.type_params, bindings, owned_types)) return false;
            }
            tail_start = tail_end;
            if (tail_start < args_end and tokEq(tokens[tail_start], ",")) tail_start += 1;
        }
    }

    const concrete_ty = try substituteGenericTypeOwned(allocator, param_ty, bindings.items, owned_types);
    if (typeContainsTypeParam(template.type_params, concrete_ty)) return false;
    return callArgsMatchVariadicTail(tokens, args_start, args_end, locals, ctx, concrete_ty);
}


pub fn bindGenericCallbackArg(
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
        return bindGenericCallbackIdentArg(
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
    return bindGenericCallbackLambdaArg(
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


pub fn matchOrBindGenericType(
    allocator: std.mem.Allocator,
    shape_ty: []const u8,
    concrete_ty: []const u8,
    type_params: []const []const u8,
    bindings: *std.ArrayList(GenericTypeBinding),
    owned_types: *std.ArrayList([]const u8),
) !bool {
    if (!typeContainsTypeParam(type_params, shape_ty)) {
        const resolved = try substituteGenericTypeOwned(allocator, shape_ty, bindings.items, owned_types);
        return std.mem.eql(u8, resolved, concrete_ty);
    }
    return bindGenericTypeFromConcrete(allocator, shape_ty, concrete_ty, type_params, bindings, owned_types);
}


pub fn bindGenericCallbackIdentArg(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    arg_start: usize,
    ctx: CodegenContext,
    template: FuncDecl,
    shape: FuncTypeShape,
    bindings: *std.ArrayList(GenericTypeBinding),
    owned_types: *std.ArrayList([]const u8),
) !bool {
    const binding = findCallbackBinding(ctx.callback_bindings, tokens[arg_start].lexeme) orelse {
        const concrete_shape = try instantiateFuncTypeShape(allocator, shape, bindings.items, owned_types);
        defer allocator.free(concrete_shape.param_types);
        return findCallbackRefFunc(tokens, ctx, tokens[arg_start].lexeme, concrete_shape) != null;
    };
    if (binding.shape.param_types.len != shape.param_types.len) return false;

    for (shape.param_types, 0..) |expected_ty, idx| {
        const shape_ty = expected_ty orelse {
            if (idx >= binding.shape.param_types.len) return false;
            continue;
        };
        if (idx >= binding.shape.param_types.len) return false;
        const upstream_ty = binding.shape.param_types[idx] orelse return false;
        if (!try matchOrBindGenericType(allocator, shape_ty, upstream_ty, template.type_params, bindings, owned_types)) {
            return false;
        }
    }

    const ret_ty = shape.return_type orelse return binding.shape.return_type == null;
    const upstream_ret = binding.shape.return_type orelse return false;
    return try matchOrBindGenericType(allocator, ret_ty, upstream_ret, template.type_params, bindings, owned_types);
}


pub fn bindGenericCallbackLambdaArg(
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
    const lambda = lambdaExprShape(tokens, arg_start, arg_end) orelse return false;
    const lambda_param_types = try parseLambdaParamTypes(allocator, tokens, lambda.open_params + 1, lambda.close_params);
    defer allocator.free(lambda_param_types);
    if (lambda_param_types.len != shape.param_types.len) return false;

    for (shape.param_types, 0..) |expected_ty, idx| {
        const shape_ty = expected_ty orelse continue;
        const explicit_ty = lambda_param_types[idx];
        if (!typeContainsTypeParam(template.type_params, shape_ty)) {
            const concrete_ty = try substituteGenericTypeOwned(allocator, shape_ty, bindings.items, owned_types);
            if (explicit_ty) |ty| {
                if (!std.mem.eql(u8, concrete_ty, ty)) return false;
            }
            continue;
        }
        if (explicit_ty) |ty| {
            if (!try bindGenericTypeFromConcrete(allocator, shape_ty, ty, template.type_params, bindings, owned_types)) {
                return false;
            }
            continue;
        }
        const concrete_ty = try substituteGenericTypeOwned(allocator, shape_ty, bindings.items, owned_types);
        if (typeContainsTypeParam(template.type_params, concrete_ty)) return false;
    }

    const ret_ty = shape.return_type orelse return true;
    const concrete_shape = try instantiateFuncTypeShape(allocator, shape, bindings.items, owned_types);
    defer allocator.free(concrete_shape.param_types);
    const lambda_ret = (try inferLambdaExprReturnType(allocator, tokens, lambda, concrete_shape, locals, ctx)) orelse return false;
    return try matchOrBindGenericType(allocator, ret_ty, lambda_ret, template.type_params, bindings, owned_types);
}


pub fn inferUntypedGenericParamAbiType(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.end == range.start + 1 and tokens[range.start].kind == .string) return "[u8]";
    return inferExprType(tokens, start_idx, end_idx, locals, ctx);
}


pub fn bindExplicitGenericCallTypeArgs(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    call_head: ExprCallHead,
    template: FuncDecl,
    bindings: *std.ArrayList(GenericTypeBinding),
    owned_types: *std.ArrayList([]const u8)) !bool {
    if (!callHeadHasTypeArgs(call_head)) return true;
    if (template.type_params.len == 0) return false;

    var type_start = call_head.type_args_start;
    var type_idx: usize = 0;
    while (type_start < call_head.type_args_end) {
        if (type_idx >= template.type_params.len) return false;
        if (tokEq(tokens[type_start], ",")) return false;

        const type_end = findTypeArgEnd(tokens, type_start, call_head.type_args_end);
        if (type_end == type_start) return false;
        const parsed_ty = (try parseCodegenTypeExpr(allocator, tokens, type_start, type_end, owned_types)) orelse return false;
        if (parsed_ty.next_idx != type_end) return false;
        if (!try bindGenericType(allocator, bindings, template.type_params[type_idx], parsed_ty.ty, owned_types)) return false;

        type_idx += 1;
        type_start = type_end;
        if (type_start < call_head.type_args_end) {
            if (!tokEq(tokens[type_start], ",")) return false;
            type_start += 1;
            if (type_start >= call_head.type_args_end) return false;
        }
    }

    return type_idx == template.type_params.len;
}


pub fn cloneGenericTypeBindingsOwned(
    allocator: std.mem.Allocator,
    bindings: []const GenericTypeBinding,
    owned_types: *std.ArrayList([]const u8)) ![]const GenericTypeBinding {
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


pub fn genericBindingsCoverTypeParams(template: FuncDecl, bindings: []const GenericTypeBinding) bool {
    for (template.type_params) |type_param| {
        if (findGenericBinding(bindings, type_param) == null) return false;
    }
    return true;
}



pub fn typeContainsTypeParam(type_params: []const []const u8, ty: []const u8) bool {
    var i: usize = 0;
    while (i < ty.len) {
        if (!isTypeIdentStart(ty[i])) {
            i += 1;
            continue;
        }
        const ident_start = i;
        i += 1;
        while (i < ty.len and isTypeIdentPart(ty[i])) i += 1;
        if (hasTypeParamName(type_params, ty[ident_start..i])) return true;
    }
    return false;
}


pub fn bindGenericTypeFromConcrete(
    allocator: std.mem.Allocator,
    expected_ty: []const u8,
    actual_ty: []const u8,
    type_params: []const []const u8,
    bindings: *std.ArrayList(GenericTypeBinding),
    owned_types: *std.ArrayList([]const u8)) CodegenError!bool {
    if (try bindGenericTypeListFromConcrete(allocator, expected_ty, actual_ty, '|', type_params, bindings, owned_types)) return true;

    if (hasTypeParamName(type_params, expected_ty)) {
        return try bindGenericType(allocator, bindings, expected_ty, actual_ty, owned_types);
    }
    if (!typeContainsTypeParam(type_params, expected_ty)) {
        return std.mem.eql(u8, expected_ty, actual_ty);
    }

    if (isStorageTypeName(expected_ty) and isStorageTypeName(actual_ty)) {
        return try bindGenericTypeFromConcrete(
            allocator,
            expected_ty[1 .. expected_ty.len - 1],
            actual_ty[1 .. actual_ty.len - 1],
            type_params,
            bindings,
            owned_types,
        );
    }

    const expected_args = genericTypeArgsRange(expected_ty) orelse return false;
    const actual_args = genericTypeArgsRange(actual_ty) orelse return false;
    if (!std.mem.eql(u8, expected_args.base, actual_args.base)) return false;
    if (findTopLevelTypeSeparator(expected_args.args, ',') == null and findTopLevelTypeSeparator(actual_args.args, ',') == null) {
        return try bindGenericTypeFromConcrete(
            allocator,
            expected_args.args,
            actual_args.args,
            type_params,
            bindings,
            owned_types,
        );
    }
    return try bindGenericTypeListFromConcrete(
        allocator,
        expected_args.args,
        actual_args.args,
        ',',
        type_params,
        bindings,
        owned_types,
    );
}


pub fn bindGenericTypeListFromConcrete(
    allocator: std.mem.Allocator,
    expected: []const u8,
    actual: []const u8,
    sep: u8,
    type_params: []const []const u8,
    bindings: *std.ArrayList(GenericTypeBinding),
    owned_types: *std.ArrayList([]const u8)) CodegenError!bool {
    if (findTopLevelTypeSeparator(expected, sep) == null and findTopLevelTypeSeparator(actual, sep) == null) return false;

    var expected_start: usize = 0;
    var actual_start: usize = 0;
    while (true) {
        const expected_end = findTopLevelTypeSeparatorFrom(expected, expected_start, sep) orelse expected.len;
        const actual_end = findTopLevelTypeSeparatorFrom(actual, actual_start, sep) orelse actual.len;
        if (expected_start == expected_end or actual_start == actual_end) return false;
        if (!try bindGenericTypeFromConcrete(
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





pub fn genericInstanceName(
    allocator: std.mem.Allocator,
    template: FuncDecl,
    bindings: []const GenericTypeBinding,
    param_tys: []const []const u8,
    callback_bindings: []const CallbackBinding) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, template.name);
    for (template.type_params) |type_param| {
        const binding = findGenericBinding(bindings, type_param) orelse return error.NoMatchingCall;
        try out.appendSlice(allocator, "__");
        try appendMangledTypeName(allocator, &out, binding.ty);
    }
    if (funcHasUntypedParams(template)) {
        try out.appendSlice(allocator, "__abi");
        for (param_tys) |param_ty| {
            try out.appendSlice(allocator, "__");
            try appendMangledTypeName(allocator, &out, param_ty);
        }
    }
    for (callback_bindings) |binding| {
        try appendFmt(allocator, &out, "__cb_{d}_{d}", .{ binding.arg_start, binding.arg_end });
    }
    return out.toOwnedSlice(allocator);
}


pub fn funcHasUntypedParams(func: FuncDecl) bool {
    for (func.params) |param| {
        if (param.ty.len == 0) return true;
    }
    return false;
}


pub fn findGenericTemplateForCall(functions: []const FuncDecl, tokens: []const lexer.Token, ctx: CodegenContext, name: []const u8) ?FuncDecl {
    for (functions) |func| {
        if (!func.is_generic_template) continue;
        if (!moduleTokensEqual(func.tokens, tokens)) continue;
        if (std.mem.eql(u8, func.name, name) or sameCallableSourceName(func.source_name, name)) return func;
    }

    const import_ref = findCodegenImportByAlias(tokens, name) orelse return null;
    const import_ctx = importedAliasContextForTokens(ctx.imported_alias_ctx, tokens) orelse return null;
    const child_idx = findImportedModuleIndexNoAlloc(import_ctx.graph, import_ctx.module_idx, import_ref) orelse return null;
    const child_tokens = import_ctx.graph.modules[child_idx].tokens;
    for (functions) |func| {
        if (!func.is_generic_template) continue;
        if (!moduleTokensEqual(func.tokens, child_tokens)) continue;
        if (std.mem.eql(u8, func.name, import_ref.alias)) return func;
        if (sameCallableSourceName(func.source_name, publicDeclName(import_ref.target))) return func;
    }
    return null;
}


pub fn inferGenericCallUnionResultLayout(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    call_head: ExprCallHead,
    locals: *const LocalSet,
    ctx: CodegenContext,
    result_owned_types: *std.ArrayList([]const u8)) CodegenError!?UnionLayout {
    const name = publicDeclName(tokens[call_head.name_idx].lexeme);
    for (ctx.functions) |template| {
        if (!genericTemplateMatchesCallSite(template, tokens, ctx, name)) continue;

        var bindings = std.ArrayList(GenericTypeBinding).empty;
        defer bindings.deinit(allocator);
        var param_tys = std.ArrayList([]const u8).empty;
        defer param_tys.deinit(allocator);
        var owned_types = std.ArrayList([]const u8).empty;
        defer {
            for (owned_types.items) |owned| allocator.free(owned);
            owned_types.deinit(allocator);
        }

        if (!try bindExplicitGenericCallTypeArgs(allocator, tokens, call_head, template, &bindings, &owned_types)) continue;
        if (!try bindGenericFuncCall(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, template, &bindings, &param_tys, &owned_types)) continue;
        if (!genericBindingsCoverTypeParams(template, bindings.items)) continue;
        const layout = template.result_union orelse continue;
        return try cloneUnionLayoutSubstituted(
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







