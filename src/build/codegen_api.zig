//! Codegen orchestrator: public entrypoints for WAT emission.
const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const test_runner = @import("test_runner.zig");
const codegen_pipeline = @import("codegen_pipeline.zig");
const model = @import("codegen_model.zig");
const context = @import("codegen_context.zig");
const codegen_tokens = @import("codegen_tokens.zig");
const codegen_names = @import("codegen_names.zig");
const codegen_collect_functions = @import("codegen_collect_functions.zig");
const codegen_collect_structs = @import("codegen_collect_structs.zig");

pub const EmitOptions = model.EmitOptions;
pub const CodegenError = model.CodegenError;

pub const emit_wat = codegen_pipeline.emit_wat;
pub const emit_wat_with_options = codegen_pipeline.emit_wat_with_options;
pub const emit_test_wat = codegen_pipeline.emit_test_wat;

// Types for unit tests
const LocalSet = context.LocalSet;
const SourceOrigin = model.SourceOrigin;
const GenericTypeBinding = model.GenericTypeBinding;
const FuncParam = model.FuncParam;
const StructDecl = model.StructDecl;
const StructField = model.StructField;
const StructLayout = model.StructLayout;
const FuncDecl = model.FuncDecl;
const StringDataContext = context.StringDataContext;
const CodegenContext = context.CodegenContext;
const findLocalOrigin = context.findLocalOrigin;
const findStorageLocalOrigin = context.findStorageLocalOrigin;
const appendLoopSourceStorageLocal = context.appendLoopSourceStorageLocal;
const findStructLocal = context.findStructLocal;
const findMatching = codegen_tokens.find_matching;

// Impl helpers for unit tests
const bindGenericTypeFromConcrete = codegen_pipeline.bindGenericTypeFromConcrete;
const func_param_abi_type = codegen_pipeline.funcParamAbiType;
const func_variadic_elem_type = codegen_pipeline.func_variadic_elem_type;
const cloneFuncParams = codegen_pipeline.cloneFuncParams;
const freeStructDecls = model.freeStructDecls;
const freeFuncDecls = model.freeFuncDecls;
const freeFuncParams = model.freeFuncParams;
const collect_struct_decls = codegen_collect_structs.collect_struct_decls;
const collect_func_decls = codegen_collect_functions.collect_func_decls;
const findStartFunc = codegen_tokens.find_start_func;
const findGenericTemplateForCall = codegen_pipeline.findGenericTemplateForCall;
const directManagedLastUseMoveSourceOrigin = codegen_pipeline.directManagedLastUseMoveSourceOrigin;
const CallLastUseMoveContext = context.CallLastUseMoveContext;
const collectGenericFuncInstancesForTests = codegen_pipeline.collectGenericFuncInstancesForTests;
const collect_body_locals = codegen_pipeline.collect_body_locals;
const emit_scalar_numeric_start_with_backend_ir = codegen_pipeline.emit_scalar_numeric_start_with_backend_ir;
const emit_expr = codegen_pipeline.emit_expr;
const collectGenericFuncInstanceForCall = codegen_pipeline.collectGenericFuncInstanceForCall;
const find_generic_binding = codegen_pipeline.findGenericBinding;
const find_func_decl_for_call_head = codegen_pipeline.find_func_decl_for_call_head;
const bindGenericFuncCall = codegen_pipeline.bindGenericFuncCall;
const findUnionLocal = context.findUnionLocal;
const call_head_at = codegen_pipeline.callHeadAt;
const collect_struct_layouts = codegen_collect_structs.collect_struct_layouts;
const findToken = codegen_tokens.find_token;
const freeStructLayouts = model.freeStructLayouts;
const field_get_last_use_move_source = codegen_pipeline.field_get_last_use_move_source;

test "LocalSet records source origin metadata" {
    const allocator = std.testing.allocator;
    var locals = LocalSet{};
    defer locals.deinit(allocator);

    try locals.appendBorrowedLocal(allocator, "plain_value", "[u8]", true);
    try std.testing.expectEqual(SourceOrigin.unknown, findLocalOrigin(locals.locals.items, "plain_value").?);

    try locals.appendBorrowedLocalWithOrigin(allocator, "param_value", "[u8]", false, .param_or_import);
    try std.testing.expectEqual(SourceOrigin.param_or_import, findLocalOrigin(locals.locals.items, "param_value").?);

    try appendLoopSourceStorageLocal(allocator, &locals, 7, "[u8]", "u8");
    try std.testing.expectEqual(SourceOrigin.loop_source, findLocalOrigin(locals.locals.items, "__loop_source_7").?);
    try std.testing.expectEqual(SourceOrigin.loop_source, findStorageLocalOrigin(locals.storage_locals.items, "__loop_source_7").?);

    try locals.appendBorrowedLocalWithOrigin(allocator, "__tmp", "usize", true, .compiler_temp);
    try std.testing.expectEqual(SourceOrigin.compiler_temp, findLocalOrigin(locals.locals.items, "__tmp").?);
}

test "move candidate origin metadata lookup" {
    const allocator = std.testing.allocator;
    var locals = LocalSet{};
    defer locals.deinit(allocator);
    var string_data = StringDataContext{};
    defer string_data.deinit(allocator);
    const ctx = CodegenContext{
        .functions = &.{},
        .structs = &.{},
        .value_enums = &.{},
        .struct_layouts = &.{},
        .host_imports = &.{},
        .wasi_imports = &.{},
        .string_data = &string_data,
        .entry_tokens = &.{},
        .modules = &.{},
    };
    const tokens = try lexer.tokenize(allocator, "param_value");
    defer allocator.free(tokens);

    try locals.appendBorrowedLocalWithOrigin(allocator, "param_value", "[u8]", true, .param_or_import);
    const origin = directManagedLastUseMoveSourceOrigin(tokens, 0, tokens.len, tokens.len, "target_value", &locals, ctx, null) orelse unreachable;
    try std.testing.expectEqual(SourceOrigin.param_or_import, origin);
}

test "field-get move candidate preserves struct local origin" {
    const allocator = std.testing.allocator;
    const source =
        \\user User = User{name = "amy"}
        \\user, name
    ;
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);

    var locals = LocalSet{};
    defer locals.deinit(allocator);
    const local_name = try locals.appendStructLocal(allocator, "user", "User", true);
    try std.testing.expectEqualStrings("user", local_name);

    var string_data = StringDataContext{};
    defer string_data.deinit(allocator);
    const fields = [_]StructField{
        .{ .name = "name", .ty = "text" },
    };
    const structs = [_]StructDecl{
        .{
            .name = "User",
            .fields = &fields,
            .layout_source = null,
            .tokens = tokens,
        },
    };
    const ctx = CodegenContext{
        .functions = &.{},
        .structs = &structs,
        .value_enums = &.{},
        .struct_layouts = &.{},
        .host_imports = &.{},
        .wasi_imports = &.{},
        .string_data = &string_data,
        .entry_tokens = tokens,
        .modules = &.{},
    };
    const move_ctx = CallLastUseMoveContext{
        .body_start = 0,
        .stmt_end = tokens.len,
        .body_end = tokens.len,
        .defer_ctx = null,
        .allow_last_use_move = true,
        .allow_field_read_move = true,
    };
    const struct_local = findStructLocal(locals.struct_locals.items, "user") orelse unreachable;
    const move_source = try field_get_last_use_move_source(allocator, tokens, 8, tokens.len, struct_local, "text", move_ctx, &locals, ctx) orelse unreachable;
    try std.testing.expectEqual(SourceOrigin.unknown, move_source.origin);
    try std.testing.expectEqualStrings("user", move_source.source_name);
}

test "generic union binding extracts nullable payload type" {
    const allocator = std.testing.allocator;
    var bindings = std.ArrayList(GenericTypeBinding).empty;
    defer bindings.deinit(allocator);
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }

    try std.testing.expect(try bindGenericTypeFromConcrete(
        allocator,
        "T|nil",
        "text|nil",
        &.{"T"},
        &bindings,
        &owned_types,
    ));
    try std.testing.expectEqual(@as(usize, 1), bindings.items.len);
    try std.testing.expectEqualStrings("T", bindings.items[0].name);
    try std.testing.expectEqualStrings("text", bindings.items[0].ty);
}

test "variadic storage param uses nested storage abi" {
    const param = FuncParam{
        .name = "rest",
        .ty = "[u8]",
        .variadic = true,
    };

    try std.testing.expectEqualStrings("[[u8]]", func_param_abi_type(param));
}

test "variadic storage param keeps storage element type" {
    const param = FuncParam{
        .name = "rest",
        .ty = "[u8]",
        .variadic = true,
    };

    try std.testing.expectEqualStrings("[u8]", func_variadic_elem_type(param));
}

test "cloneFuncParams preserves variadic abi type" {
    const allocator = std.testing.allocator;
    const params = [_]FuncParam{.{
        .name = "rest",
        .ty = "[u8]",
        .abi_ty = "[[u8]]",
        .variadic = true,
    }};

    const cloned = try cloneFuncParams(allocator, &params);
    defer freeFuncParams(allocator, cloned);

    try std.testing.expectEqualStrings("[[u8]]", func_param_abi_type(cloned[0]));
    try std.testing.expectEqualStrings("[u8]", func_variadic_elem_type(cloned[0]));
}

test "inferred generic union call binding returns substituted union layout" {
    const allocator = std.testing.allocator;
    const source =
        \\JsonError error = Bad
        \\
        \\encode_value(value text, depth usize) -> [u8] | JsonError {
        \\    return value
        \\}
        \\
        \\#T
        \\encode_value(value T | nil, depth usize) -> [u8] | JsonError {
        \\    if @eq(value, nil) return "null"
        \\    return encode_value(value, depth)
        \\}
        \\
        \\start() {
        \\    value text | nil = nil
        \\    encoded = encode_value(value, 1)
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);

    var structs = std.ArrayList(StructDecl).empty;
    defer {
        freeStructDecls(allocator, structs.items);
        structs.deinit(allocator);
    }
    try collect_struct_decls(allocator, tokens, &structs);

    var layouts = std.ArrayList(StructLayout).empty;
    defer {
        freeStructLayouts(allocator, layouts.items);
        layouts.deinit(allocator);
    }
    try collect_struct_layouts(allocator, structs.items, &layouts);

    var functions = std.ArrayList(FuncDecl).empty;
    defer {
        freeFuncDecls(allocator, functions.items);
        functions.deinit(allocator);
    }
    try collect_func_decls(allocator, tokens, structs.items, layouts.items, null, &functions);
    try std.testing.expect(functions.items.len >= 2);
    var has_nullable_template = false;
    for (functions.items) |func| {
        if (func.is_generic_template and std.mem.eql(u8, func.source_name, "encode_value") and func.result_union != null) {
            has_nullable_template = true;
        }
    }
    try std.testing.expect(has_nullable_template);

    var string_data = StringDataContext{};
    defer string_data.deinit(allocator);
    const ctx = CodegenContext{
        .functions = functions.items,
        .structs = structs.items,
        .value_enums = &.{},
        .struct_layouts = layouts.items,
        .host_imports = &.{},
        .wasi_imports = &.{},
        .string_data = &string_data,
        .entry_tokens = tokens,
        .modules = &.{},
    };

    var locals = LocalSet{};
    defer locals.deinit(allocator);
    const start_idx = findStartFunc(tokens) orelse unreachable;
    const start_open = findToken(tokens, start_idx, tokens.len, "{").?;
    const start_close = try findMatching(tokens, start_open, "{", "}");
    try collect_body_locals(allocator, tokens, start_open + 1, start_close, ctx, &locals);

    const encoded = findUnionLocal(locals.union_locals.items, "encoded") orelse unreachable;
    try std.testing.expectEqualStrings("[u8]|JsonError", encoded.layout.source_ty);
}

test "generic callback prebinds literal argument type from lambda" {
    const allocator = std.testing.allocator;
    const source =
        \\#A
        \\#B
        \\#P = (A) -> B
        \\apply_value(value A, p P) -> B {
        \\    return p(value)
        \\}
        \\
        \\test "apply" {
        \\    result i32 = apply_value(2, (x i32) -> i32 => @add(x, 1))
        \\    if @eq(result, 3) return
        \\}
    ;
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);

    var functions = std.ArrayList(FuncDecl).empty;
    defer {
        freeFuncDecls(allocator, functions.items);
        functions.deinit(allocator);
    }
    try collect_func_decls(allocator, tokens, &.{}, &.{}, null, &functions);

    var string_data = StringDataContext{};
    defer string_data.deinit(allocator);
    const ctx = CodegenContext{
        .functions = functions.items,
        .structs = &.{},
        .value_enums = &.{},
        .struct_layouts = &.{},
        .host_imports = &.{},
        .wasi_imports = &.{},
        .string_data = &string_data,
        .entry_tokens = tokens,
        .modules = &.{},
    };
    const template = findGenericTemplateForCall(functions.items, tokens, ctx, "apply_value") orelse unreachable;

    const first_call_idx = findToken(tokens, 0, tokens.len, "apply_value") orelse unreachable;
    const call_idx = findToken(tokens, first_call_idx + 1, tokens.len, "apply_value") orelse unreachable;
    const call_head = call_head_at(tokens, call_idx, tokens.len) orelse unreachable;

    var locals = LocalSet{};
    defer locals.deinit(allocator);
    var bindings = std.ArrayList(GenericTypeBinding).empty;
    defer bindings.deinit(allocator);
    var param_tys = std.ArrayList([]const u8).empty;
    defer param_tys.deinit(allocator);
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }

    try std.testing.expect(try bindGenericFuncCall(allocator, tokens, call_head.args_start, call_head.args_end, &locals, ctx, template, &bindings, &param_tys, &owned_types));
    try std.testing.expectEqualStrings("i32", find_generic_binding(bindings.items, "A").?.ty);
    try std.testing.expectEqualStrings("i32", find_generic_binding(bindings.items, "B").?.ty);

    try collectGenericFuncInstanceForCall(allocator, tokens, call_head, &locals, ctx, template, "i32", &functions);
    try std.testing.expect(find_func_decl_for_call_head(tokens, call_head, &locals, .{
        .functions = functions.items,
        .structs = &.{},
        .value_enums = &.{},
        .struct_layouts = &.{},
        .host_imports = &.{},
        .wasi_imports = &.{},
        .string_data = &string_data,
        .entry_tokens = tokens,
        .modules = &.{},
    }) != null);

    var collected_functions = std.ArrayList(FuncDecl).empty;
    defer {
        freeFuncDecls(allocator, collected_functions.items);
        collected_functions.deinit(allocator);
    }
    try collect_func_decls(allocator, tokens, &.{}, &.{}, null, &collected_functions);
    const tests = try test_runner.collectTopLevelTests(allocator, tokens);
    defer allocator.free(tests);
    try collectGenericFuncInstancesForTests(
        allocator,
        tokens,
        tests,
        &.{},
        &.{},
        &.{},
        &.{},
        &.{},
        &.{},
        &string_data,
        &.{},
        null,
        &collected_functions,
    );
    var collected_locals = LocalSet{};
    defer collected_locals.deinit(allocator);
    try collect_body_locals(allocator, tokens, tests[0].body_start, tests[0].body_end, .{
        .functions = collected_functions.items,
        .structs = &.{},
        .value_enums = &.{},
        .struct_layouts = &.{},
        .host_imports = &.{},
        .wasi_imports = &.{},
        .string_data = &string_data,
        .entry_tokens = tokens,
        .modules = &.{},
    }, &collected_locals);
    try std.testing.expect(find_func_decl_for_call_head(tokens, call_head, &collected_locals, .{
        .functions = collected_functions.items,
        .structs = &.{},
        .value_enums = &.{},
        .struct_layouts = &.{},
        .host_imports = &.{},
        .wasi_imports = &.{},
        .string_data = &string_data,
        .entry_tokens = tokens,
        .modules = &.{},
    }) != null);

    var wat = std.ArrayList(u8).empty;
    defer wat.deinit(allocator);
    try std.testing.expect(try emit_expr(allocator, tokens, call_head.name_idx, call_head.args_end + 1, &collected_locals, .{
        .functions = collected_functions.items,
        .structs = &.{},
        .value_enums = &.{},
        .struct_layouts = &.{},
        .host_imports = &.{},
        .wasi_imports = &.{},
        .string_data = &string_data,
        .entry_tokens = tokens,
        .modules = &.{},
    }, "i32", &wat));
}

test "generic callback prebinds literal argument type from function ref" {
    const allocator = std.testing.allocator;
    const source =
        \\#A
        \\#B
        \\#P = (A) -> B
        \\apply_value(value A, p P) -> B {
        \\    return p(value)
        \\}
        \\
        \\bool_to_i32(x bool) -> i32 {
        \\    if x return 1
        \\    return 0
        \\}
        \\
        \\test "apply" {
        \\    result i32 = apply_value(true, bool_to_i32)
        \\    if @eq(result, 1) return
        \\}
    ;
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);

    var functions = std.ArrayList(FuncDecl).empty;
    defer {
        freeFuncDecls(allocator, functions.items);
        functions.deinit(allocator);
    }
    try collect_func_decls(allocator, tokens, &.{}, &.{}, null, &functions);

    var string_data = StringDataContext{};
    defer string_data.deinit(allocator);
    const tests = try test_runner.collectTopLevelTests(allocator, tokens);
    defer allocator.free(tests);
    try collectGenericFuncInstancesForTests(
        allocator,
        tokens,
        tests,
        &.{},
        &.{},
        &.{},
        &.{},
        &.{},
        &.{},
        &string_data,
        &.{},
        null,
        &functions,
    );
    var locals = LocalSet{};
    defer locals.deinit(allocator);
    const ctx = CodegenContext{
        .functions = functions.items,
        .structs = &.{},
        .value_enums = &.{},
        .struct_layouts = &.{},
        .host_imports = &.{},
        .wasi_imports = &.{},
        .string_data = &string_data,
        .entry_tokens = tokens,
        .modules = &.{},
    };
    try collect_body_locals(allocator, tokens, tests[0].body_start, tests[0].body_end, ctx, &locals);
    const first_call_idx = findToken(tokens, 0, tokens.len, "apply_value") orelse unreachable;
    const call_idx = findToken(tokens, first_call_idx + 1, tokens.len, "apply_value") orelse unreachable;
    const call_head = call_head_at(tokens, call_idx, tokens.len) orelse unreachable;
    const template = findGenericTemplateForCall(functions.items, tokens, ctx, "apply_value") orelse unreachable;
    var bindings = std.ArrayList(GenericTypeBinding).empty;
    defer bindings.deinit(allocator);
    var param_tys = std.ArrayList([]const u8).empty;
    defer param_tys.deinit(allocator);
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    try std.testing.expect(try bindGenericFuncCall(allocator, tokens, call_head.args_start, call_head.args_end, &locals, ctx, template, &bindings, &param_tys, &owned_types));
    try std.testing.expectEqualStrings("bool", find_generic_binding(bindings.items, "A").?.ty);
    try std.testing.expectEqualStrings("i32", find_generic_binding(bindings.items, "B").?.ty);
    try collectGenericFuncInstanceForCall(allocator, tokens, call_head, &locals, ctx, template, "i32", &functions);
    const direct_func = find_func_decl_for_call_head(tokens, call_head, &locals, .{
        .functions = functions.items,
        .structs = &.{},
        .value_enums = &.{},
        .struct_layouts = &.{},
        .host_imports = &.{},
        .wasi_imports = &.{},
        .string_data = &string_data,
        .entry_tokens = tokens,
        .modules = &.{},
    }) orelse unreachable;
    try std.testing.expect(direct_func.callback_bindings.len == 1);
    const func = find_func_decl_for_call_head(tokens, call_head, &locals, ctx) orelse unreachable;
    try std.testing.expect(func.callback_bindings.len == 1);
    try std.testing.expect(func.callback_bindings[0].kind == .func_ref);

    var wat = std.ArrayList(u8).empty;
    defer wat.deinit(allocator);
    try std.testing.expect(try emit_expr(allocator, tokens, call_head.name_idx, call_head.args_end + 1, &locals, ctx, "i32", &wat));
}

test "generic multi callback instances collect" {
    const allocator = std.testing.allocator;
    const source =
        \\#A
        \\#B
        \\#C
        \\#P = (A) -> B
        \\#Q = (B) -> C
        \\compose(value A, p P, q Q) -> C {
        \\    return q(p(value))
        \\}
        \\
        \\test "compose multi" {
        \\    same i32 = compose(2, (x i32) -> i32 => @add(x, 1), (x i32) -> i32 => @mul(x, 3))
        \\    hetero bool = compose(2, (x i32) -> i64 => @as(i64, @add(x, 1)), (x i64) -> bool => @gt(x, 0))
        \\    ok bool = true
        \\    ok = @and(ok, @eq(same, 9))
        \\    ok = @and(ok, hetero)
        \\    if ok return
        \\}
    ;
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);

    var functions = std.ArrayList(FuncDecl).empty;
    defer {
        freeFuncDecls(allocator, functions.items);
        functions.deinit(allocator);
    }
    try collect_func_decls(allocator, tokens, &.{}, &.{}, null, &functions);

    var string_data = StringDataContext{};
    defer string_data.deinit(allocator);
    const tests = try test_runner.collectTopLevelTests(allocator, tokens);
    defer allocator.free(tests);
    try collectGenericFuncInstancesForTests(
        allocator,
        tokens,
        tests,
        &.{},
        &.{},
        &.{},
        &.{},
        &.{},
        &.{},
        &string_data,
        &.{},
        null,
        &functions,
    );
    const ctx = CodegenContext{
        .functions = functions.items,
        .structs = &.{},
        .value_enums = &.{},
        .struct_layouts = &.{},
        .host_imports = &.{},
        .wasi_imports = &.{},
        .string_data = &string_data,
        .entry_tokens = tokens,
        .modules = &.{},
    };
    var locals = LocalSet{};
    defer locals.deinit(allocator);
    try collect_body_locals(allocator, tokens, tests[0].body_start, tests[0].body_end, ctx, &locals);

    const def_idx = findToken(tokens, 0, tokens.len, "compose") orelse unreachable;
    const same_idx = findToken(tokens, def_idx + 1, tokens.len, "compose") orelse unreachable;
    const hetero_idx = findToken(tokens, same_idx + 1, tokens.len, "compose") orelse unreachable;
    const same_head = call_head_at(tokens, same_idx, tokens.len) orelse unreachable;
    const hetero_head = call_head_at(tokens, hetero_idx, tokens.len) orelse unreachable;
    try std.testing.expect(find_func_decl_for_call_head(tokens, same_head, &locals, ctx) != null);
    try std.testing.expect(find_func_decl_for_call_head(tokens, hetero_head, &locals, ctx) != null);

    var same_wat = std.ArrayList(u8).empty;
    defer same_wat.deinit(allocator);
    try std.testing.expect(try emit_expr(allocator, tokens, same_idx, same_head.args_end + 1, &locals, ctx, "i32", &same_wat));

    var hetero_wat = std.ArrayList(u8).empty;
    defer hetero_wat.deinit(allocator);
    try std.testing.expect(try emit_expr(allocator, tokens, hetero_idx, hetero_head.args_end + 1, &locals, ctx, "bool", &hetero_wat));
}

test "backend ir lowering emits selected scalar numeric start body" {
    const allocator = std.testing.allocator;
    const source =
        \\start() {
        \\    x i32 = @add(1, 2, 3)
        \\    y i32 = @mul(x, 4)
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);

    var string_data = StringDataContext{};
    defer string_data.deinit(allocator);
    const ctx = CodegenContext{
        .functions = &.{},
        .structs = &.{},
        .value_enums = &.{},
        .struct_layouts = &.{},
        .host_imports = &.{},
        .wasi_imports = &.{},
        .string_data = &string_data,
        .entry_tokens = tokens,
        .modules = &.{},
    };
    const start_idx = findStartFunc(tokens) orelse unreachable;
    const open_params = start_idx + 1;
    const close_params = try findMatching(tokens, open_params, "(", ")");
    const open_body = findToken(tokens, close_params + 1, tokens.len, "{") orelse unreachable;
    const close_body = try findMatching(tokens, open_body, "{", "}");

    var locals = LocalSet{};
    defer locals.deinit(allocator);
    try collect_body_locals(allocator, tokens, open_body + 1, close_body, ctx, &locals);

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    try std.testing.expect(try emit_scalar_numeric_start_with_backend_ir(allocator, tokens, open_body + 1, close_body, &locals, ctx, &out));
    try std.testing.expectEqualStrings(
        \\    i32.const 1
        \\    i32.const 2
        \\    i32.add
        \\    i32.const 3
        \\    i32.add
        \\    local.set $x
        \\    local.get $x
        \\    i32.const 4
        \\    i32.mul
        \\    local.set $y
        \\    return
        \\
    , out.items);
}
