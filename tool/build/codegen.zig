const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const test_runner = @import("test_runner.zig");

const Local = struct {
    name: []const u8,
    ty: []const u8,
    emit_decl: bool = true,
    release_on_scope_exit: bool = true,
};

const StructField = struct {
    name: []const u8,
    ty: []const u8,
};

const StructDecl = struct {
    name: []const u8,
    type_params: []const []const u8 = &.{},
    fields: []const StructField,
    layout_source: ?[]const u8,
    owned_types: []const []const u8 = &.{},
};

const ManagedFieldOffset = struct {
    name: []const u8,
    offset: usize,
};

const StructLayout = struct {
    name: []const u8,
    type_id: usize,
    payload_bytes: usize,
    managed_fields: []const ManagedFieldOffset,
};

const StructLocal = struct {
    name: []const u8,
    ty: []const u8,
};

const StorageLocal = struct {
    name: []const u8,
    elem_ty: []const u8,
};

pub const EmitOptions = struct {
    component_core: bool = false,
};

const TYPE_ID_STORAGE_U8: usize = 1;
const TYPE_ID_STORAGE_MANAGED: usize = 65535;
const TYPE_ID_FIRST_STRUCT: usize = TYPE_ID_STORAGE_U8 + 1;
const STORAGE_PAYLOAD_HEADER_BYTES: usize = 8;
const STORAGE_OVERWRITE_TMP_LOCAL = "__do_storage_overwrite_tmp";
const STORAGE_WRITE_INDEX_TMP_LOCAL = "__do_storage_write_index_tmp";
const STORAGE_WRITE_LEN_TMP_LOCAL = "__do_storage_write_len_tmp";
const STORAGE_WRITE_NEXT_TMP_LOCAL = "__do_storage_write_next_tmp";
const STORAGE_WRITE_SCAN_TMP_LOCAL = "__do_storage_write_scan_tmp";
const NUMERIC_SELECT_LEFT_TMP_I32 = "__do_numeric_select_left_i32";
const NUMERIC_SELECT_RIGHT_TMP_I32 = "__do_numeric_select_right_i32";
const NUMERIC_SELECT_LEFT_TMP_I64 = "__do_numeric_select_left_i64";
const NUMERIC_SELECT_RIGHT_TMP_I64 = "__do_numeric_select_right_i64";

const NumericSelectTemps = struct {
    left: []const u8,
    right: []const u8,
};

const LocalSet = struct {
    locals: std.ArrayList(Local) = .empty,
    struct_locals: std.ArrayList(StructLocal) = .empty,
    storage_locals: std.ArrayList(StorageLocal) = .empty,
    owned_names: std.ArrayList([]const u8) = .empty,

    fn deinit(self: *LocalSet, allocator: std.mem.Allocator) void {
        for (self.owned_names.items) |name| {
            allocator.free(name);
        }
        self.owned_names.deinit(allocator);
        self.storage_locals.deinit(allocator);
        self.struct_locals.deinit(allocator);
        self.locals.deinit(allocator);
    }

    fn appendBorrowedLocal(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        ty: []const u8,
        emit_decl: bool,
    ) !void {
        try self.locals.append(allocator, .{
            .name = name,
            .ty = ty,
            .emit_decl = emit_decl,
        });
    }

    fn appendOwnedLocal(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        ty: []const u8,
    ) !void {
        try self.owned_names.append(allocator, name);
        errdefer allocator.free(name);
        errdefer _ = self.owned_names.pop();
        try self.locals.append(allocator, .{
            .name = name,
            .ty = ty,
            .emit_decl = true,
        });
    }

    fn appendStorageLocal(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        elem_ty: []const u8,
        emit_decl: bool,
    ) !void {
        const ty = storageTypeNameForElem(elem_ty) orelse blk: {
            const owned_ty = try std.fmt.allocPrint(allocator, "[{s}]", .{elem_ty});
            errdefer allocator.free(owned_ty);
            try self.owned_names.append(allocator, owned_ty);
            break :blk owned_ty;
        };
        try self.appendStorageLocalWithType(allocator, name, ty, elem_ty, emit_decl);
    }

    fn appendStorageLocalWithType(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        ty: []const u8,
        elem_ty: []const u8,
        emit_decl: bool,
    ) !void {
        try self.storage_locals.append(allocator, .{ .name = name, .elem_ty = elem_ty });
        try self.locals.append(allocator, .{
            .name = name,
            .ty = ty,
            .emit_decl = emit_decl,
        });
    }

    fn ensureStorageWriteTemps(self: *LocalSet, allocator: std.mem.Allocator) !void {
        if (!hasLocal(self.locals.items, STORAGE_OVERWRITE_TMP_LOCAL)) {
            try self.appendBorrowedLocal(allocator, STORAGE_OVERWRITE_TMP_LOCAL, "usize", true);
        }
        if (!hasLocal(self.locals.items, STORAGE_WRITE_INDEX_TMP_LOCAL)) {
            try self.appendBorrowedLocal(allocator, STORAGE_WRITE_INDEX_TMP_LOCAL, "usize", true);
        }
        if (!hasLocal(self.locals.items, STORAGE_WRITE_LEN_TMP_LOCAL)) {
            try self.appendBorrowedLocal(allocator, STORAGE_WRITE_LEN_TMP_LOCAL, "usize", true);
        }
        if (!hasLocal(self.locals.items, STORAGE_WRITE_NEXT_TMP_LOCAL)) {
            try self.appendBorrowedLocal(allocator, STORAGE_WRITE_NEXT_TMP_LOCAL, "usize", true);
        }
        if (!hasLocal(self.locals.items, STORAGE_WRITE_SCAN_TMP_LOCAL)) {
            try self.appendBorrowedLocal(allocator, STORAGE_WRITE_SCAN_TMP_LOCAL, "usize", true);
        }
    }

    fn ensureNumericSelectTemps(self: *LocalSet, allocator: std.mem.Allocator) !void {
        if (!hasLocal(self.locals.items, NUMERIC_SELECT_LEFT_TMP_I32)) {
            try self.appendBorrowedLocal(allocator, NUMERIC_SELECT_LEFT_TMP_I32, "i32", true);
        }
        if (!hasLocal(self.locals.items, NUMERIC_SELECT_RIGHT_TMP_I32)) {
            try self.appendBorrowedLocal(allocator, NUMERIC_SELECT_RIGHT_TMP_I32, "i32", true);
        }
        if (!hasLocal(self.locals.items, NUMERIC_SELECT_LEFT_TMP_I64)) {
            try self.appendBorrowedLocal(allocator, NUMERIC_SELECT_LEFT_TMP_I64, "i64", true);
        }
        if (!hasLocal(self.locals.items, NUMERIC_SELECT_RIGHT_TMP_I64)) {
            try self.appendBorrowedLocal(allocator, NUMERIC_SELECT_RIGHT_TMP_I64, "i64", true);
        }
    }
};

const FuncParam = struct {
    name: []const u8,
    ty: []const u8,
    variadic: bool = false,
};

const GenericTypeBinding = struct {
    name: []const u8,
    ty: []const u8,
};

const FuncDecl = struct {
    name: []const u8,
    source_name: []const u8 = "",
    params: []const FuncParam,
    result: ?[]const u8,
    results: []const []const u8,
    result_struct: ?[]const u8,
    type_params: []const []const u8 = &.{},
    type_bindings: []const GenericTypeBinding = &.{},
    is_generic_template: bool = false,
    owned_name: bool = false,
    owned_types: []const []const u8 = &.{},
    tokens: []const lexer.Token,
    arrow: bool,
    body_start: usize,
    body_end: usize,
};

const FuncResultParse = struct {
    types: []const []const u8,
    result_struct: ?[]const u8 = null,
};

const ParsedCodegenType = struct {
    ty: []const u8,
    next_idx: usize,
};

const FuncBodyShape = struct {
    result_start: usize,
    result_end: usize,
    body_start: usize,
    body_end: usize,
    arrow: bool,
    next_idx: usize,
};

const StructErrorResult = struct {
    struct_name: []const u8,
    error_name: []const u8,
};

const ImportedAliasContext = struct {
    graph: *const imports.ModuleGraph,
    module_idx: usize,
};

const CodegenContext = struct {
    functions: []const FuncDecl,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    host_imports: []const HostImport,
    wasi_imports: []const WasiHostImport,
    string_data: *const StringDataContext,
    entry_tokens: []const lexer.Token,
    modules: []const imports.ModuleRecord,
    type_bindings: []const GenericTypeBinding = &.{},
};

const LoopControl = struct {
    cleanup_locals: *const LocalSet,
    defer_ctx: *const DeferContext,
};

const DeferContext = struct {
    parent: ?*const DeferContext,
    start_idx: usize,
    end_idx: usize,
    registered_end_idx: usize,
};

const DeferItemKind = enum {
    call,
    block,
};

const DeferItem = struct {
    kind: DeferItemKind,
    start_idx: usize,
    end_idx: usize,
};

const CodegenError = anyerror;

const HostImport = struct {
    alias: []const u8,
    source_alias: []const u8,
    field: []const u8,
    params: []const []const u8,
    result: ?[]const u8,
    tokens: []const lexer.Token,
    owned_alias: bool = false,
};

const WasiHostImport = struct {
    source: []const u8,
    alias: []const u8,
    target: []const u8,
    params: []const u8,
    result: []const u8,
};

const WasiLowering = struct {
    module: []const u8,
    name: []const u8,
    param: ?[]const u8 = null,
    result: ?[]const u8 = null,
    result_record: ?[]const u8 = null,
    result_storage_elem: ?[]const u8 = null,
    result_unit_error: bool = false,
    result_link_at_error: bool = false,
    result_filesize_error: bool = false,
    result_descriptor_error: bool = false,
    result_u64_stream_error: bool = false,
    result_read_error: bool = false,
    result_list_u8_error: bool = false,
    resource_drop: bool = false,
};

const WasiLinkAtArgs = struct {
    descriptor_start: usize,
    descriptor_end: usize,
    old_flags_start: usize,
    old_flags_end: usize,
    old_path_start: usize,
    old_path_end: usize,
    new_descriptor_start: usize,
    new_descriptor_end: usize,
    new_path_start: usize,
    new_path_end: usize,
};

const WASI_BINDING_ENTRY_SOURCE = "entry";

const CodegenImportPrefix = enum {
    local,
    dep,
    std,
};

const CodegenImportRef = struct {
    alias: []const u8,
    target: []const u8,
    file_path: []const u8,
    prefix: CodegenImportPrefix,
};

const ReachVisit = struct {
    module_idx: usize,
    name: []const u8,
    call_idx: ?usize = null,
};

const StringData = struct {
    lexeme: []const u8,
    bytes: []const u8,
    ptr: usize,
};

const ARC_BLOCK_SIZE: usize = 1024;
const ARC_OBJECT_HEADER_BYTES: usize = 8;
const ARC_RELEASE_WORKLIST_BYTES: usize = 512;
const WASI_RESULT_AREA_BYTES: usize = 64;

const StringDataContext = struct {
    items: std.ArrayList(StringData) = .empty,
    next_ptr: usize = 1024,

    fn deinit(self: *StringDataContext, allocator: std.mem.Allocator) void {
        for (self.items.items) |item| {
            allocator.free(item.bytes);
        }
        self.items.deinit(allocator);
    }

    fn intern(self: *StringDataContext, allocator: std.mem.Allocator, lexeme: []const u8) !StringData {
        for (self.items.items) |item| {
            if (std.mem.eql(u8, item.lexeme, lexeme)) return item;
        }

        const bytes = try decodeQuotedStringToken(allocator, lexeme);
        errdefer allocator.free(bytes);
        const data = StringData{
            .lexeme = lexeme,
            .bytes = bytes,
            .ptr = self.next_ptr,
        };
        self.next_ptr += @max(bytes.len, 1);
        try self.items.append(allocator, data);
        return data;
    }

    fn find(self: *const StringDataContext, lexeme: []const u8) ?StringData {
        for (self.items.items) |item| {
            if (std.mem.eql(u8, item.lexeme, lexeme)) return item;
        }
        return null;
    }
};

pub fn emitWat(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) ![]u8 {
    return emitWatWithOptions(allocator, program, tokens, module_graph, .{});
}

pub fn emitWatWithOptions(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
    options: EmitOptions,
) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    var host_imports = std.ArrayList(HostImport).empty;
    defer {
        freeHostImports(allocator, host_imports.items);
        host_imports.deinit(allocator);
    }
    try collectEnvHostImports(allocator, tokens, &host_imports);
    if (module_graph) |graph| {
        try collectEnvHostImportsFromModules(allocator, graph.modules, tokens, &host_imports);
    }
    try validateHostImportBuildUses(tokens, host_imports.items);

    var wasi_imports = std.ArrayList(WasiHostImport).empty;
    defer {
        freeWasiHostImports(allocator, wasi_imports.items);
        wasi_imports.deinit(allocator);
    }
    if (module_graph) |graph| {
        try collectWasiHostImportsFromModules(allocator, graph.modules, tokens, &wasi_imports);
    } else {
        try collectWasiHostImports(allocator, tokens, WASI_BINDING_ENTRY_SOURCE, &wasi_imports);
    }
    var entry_wasi_imports = std.ArrayList(WasiHostImport).empty;
    defer {
        freeWasiHostImports(allocator, entry_wasi_imports.items);
        entry_wasi_imports.deinit(allocator);
    }
    try collectWasiHostImports(allocator, tokens, WASI_BINDING_ENTRY_SOURCE, &entry_wasi_imports);
    try validateWasiHostImportBuildUses(tokens, entry_wasi_imports.items);
    if (module_graph) |graph| {
        try validateReachableWasiHostImportBuildUses(allocator, tokens, graph);
    }

    var string_data = StringDataContext{};
    defer string_data.deinit(allocator);
    try collectStringDataForHostCalls(allocator, tokens, host_imports.items, &string_data);
    try collectStringDataForWasiHostCalls(allocator, tokens, WASI_BINDING_ENTRY_SOURCE, wasi_imports.items, &string_data);
    try collectStringDataForStorageLiterals(allocator, tokens, &string_data);
    if (module_graph) |graph| {
        for (graph.modules) |module| {
            const source = if (moduleTokensEqual(module.tokens, tokens))
                WASI_BINDING_ENTRY_SOURCE
            else
                module.path;
            try collectStringDataForHostCalls(allocator, module.tokens, host_imports.items, &string_data);
            try collectStringDataForWasiHostCalls(allocator, module.tokens, source, wasi_imports.items, &string_data);
            try collectStringDataForStorageLiterals(allocator, module.tokens, &string_data);
        }
    }

    var structs = std.ArrayList(StructDecl).empty;
    defer {
        freeStructDecls(allocator, structs.items);
        structs.deinit(allocator);
    }
    try collectStructDecls(allocator, tokens, &structs);
    if (module_graph) |graph| {
        try collectImportedStructDecls(allocator, tokens, graph, &structs);
    }

    var struct_layouts = std.ArrayList(StructLayout).empty;
    defer {
        freeStructLayouts(allocator, struct_layouts.items);
        struct_layouts.deinit(allocator);
    }
    try collectStructLayouts(allocator, structs.items, &struct_layouts);

    var functions = std.ArrayList(FuncDecl).empty;
    defer {
        freeFuncDecls(allocator, functions.items);
        functions.deinit(allocator);
    }
    const imported_alias_ctx: ?ImportedAliasContext = if (module_graph) |graph|
        if (findRootModuleIndex(graph.modules, tokens)) |idx| ImportedAliasContext{ .graph = graph, .module_idx = idx } else null
    else
        null;
    try collectFuncDecls(allocator, tokens, structs.items, struct_layouts.items, imported_alias_ctx, &functions);
    if (module_graph) |graph| {
        try collectDirectImportedFuncDecls(allocator, tokens, graph, structs.items, struct_layouts.items, &functions);
    }
    try collectGenericFuncInstancesForStart(
        allocator,
        tokens,
        structs.items,
        struct_layouts.items,
        host_imports.items,
        wasi_imports.items,
        &string_data,
        if (module_graph) |graph| graph.modules else &.{},
        &functions,
    );

    const ctx = CodegenContext{
        .functions = functions.items,
        .structs = structs.items,
        .struct_layouts = struct_layouts.items,
        .host_imports = host_imports.items,
        .wasi_imports = wasi_imports.items,
        .string_data = &string_data,
        .entry_tokens = tokens,
        .modules = if (module_graph) |graph| graph.modules else &.{},
    };

    try out.appendSlice(allocator, "(module\n");
    try appendFmt(allocator, &out, "  ;; source_len={d}\n", .{program.source_len});
    try appendFmt(allocator, &out, "  ;; token_count={d}\n", .{program.token_count});
    try appendFmt(allocator, &out, "  ;; top_level_count={d}\n", .{program.top_level_count});
    try emitWasiBindings(allocator, &out, wasi_imports.items);
    try emitWasiCoreImports(allocator, &out, wasi_imports.items);
    try emitHostImports(allocator, &out, host_imports.items);
    try emitStringDataMemory(allocator, &out, string_data.items.items, options);
    try emitArcRuntimePrelude(allocator, &out, string_data.items.items, struct_layouts.items);
    try emitUserFuncs(allocator, ctx, &out);
    try emitStartFunc(allocator, tokens, ctx, &out);
    try out.appendSlice(allocator, ")\n");
    return out.toOwnedSlice(allocator);
}

pub fn emitTestWat(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    const test_decls = try test_runner.collectTopLevelTests(allocator, tokens);
    defer allocator.free(test_decls);
    if (test_decls.len == 0) return error.NoTestDecl;

    var host_imports = std.ArrayList(HostImport).empty;
    defer {
        freeHostImports(allocator, host_imports.items);
        host_imports.deinit(allocator);
    }
    try collectEnvHostImports(allocator, tokens, &host_imports);
    if (module_graph) |graph| {
        try collectEnvHostImportsFromModules(allocator, graph.modules, tokens, &host_imports);
    }
    try validateHostImportBuildUses(tokens, host_imports.items);

    var wasi_imports = std.ArrayList(WasiHostImport).empty;
    defer {
        freeWasiHostImports(allocator, wasi_imports.items);
        wasi_imports.deinit(allocator);
    }
    if (module_graph) |graph| {
        try collectWasiHostImportsFromModules(allocator, graph.modules, tokens, &wasi_imports);
    } else {
        try collectWasiHostImports(allocator, tokens, WASI_BINDING_ENTRY_SOURCE, &wasi_imports);
    }
    var entry_wasi_imports = std.ArrayList(WasiHostImport).empty;
    defer {
        freeWasiHostImports(allocator, entry_wasi_imports.items);
        entry_wasi_imports.deinit(allocator);
    }
    try collectWasiHostImports(allocator, tokens, WASI_BINDING_ENTRY_SOURCE, &entry_wasi_imports);
    try validateWasiHostImportBuildUses(tokens, entry_wasi_imports.items);
    if (module_graph) |graph| {
        try validateReachableWasiHostImportBuildUsesFromTests(allocator, tokens, graph);
    }

    var string_data = StringDataContext{};
    defer string_data.deinit(allocator);
    try collectStringDataForHostCalls(allocator, tokens, host_imports.items, &string_data);
    try collectStringDataForWasiHostCalls(allocator, tokens, WASI_BINDING_ENTRY_SOURCE, wasi_imports.items, &string_data);
    try collectStringDataForStorageLiterals(allocator, tokens, &string_data);
    if (module_graph) |graph| {
        for (graph.modules) |module| {
            const source = if (moduleTokensEqual(module.tokens, tokens))
                WASI_BINDING_ENTRY_SOURCE
            else
                module.path;
            try collectStringDataForHostCalls(allocator, module.tokens, host_imports.items, &string_data);
            try collectStringDataForWasiHostCalls(allocator, module.tokens, source, wasi_imports.items, &string_data);
            try collectStringDataForStorageLiterals(allocator, module.tokens, &string_data);
        }
    }

    var structs = std.ArrayList(StructDecl).empty;
    defer {
        freeStructDecls(allocator, structs.items);
        structs.deinit(allocator);
    }
    try collectStructDecls(allocator, tokens, &structs);
    if (module_graph) |graph| {
        try collectImportedStructDecls(allocator, tokens, graph, &structs);
    }

    var struct_layouts = std.ArrayList(StructLayout).empty;
    defer {
        freeStructLayouts(allocator, struct_layouts.items);
        struct_layouts.deinit(allocator);
    }
    try collectStructLayouts(allocator, structs.items, &struct_layouts);

    var functions = std.ArrayList(FuncDecl).empty;
    defer {
        freeFuncDecls(allocator, functions.items);
        functions.deinit(allocator);
    }
    const imported_alias_ctx: ?ImportedAliasContext = if (module_graph) |graph|
        if (findRootModuleIndex(graph.modules, tokens)) |idx| ImportedAliasContext{ .graph = graph, .module_idx = idx } else null
    else
        null;
    try collectFuncDecls(allocator, tokens, structs.items, struct_layouts.items, imported_alias_ctx, &functions);
    if (module_graph) |graph| {
        try collectDirectImportedFuncDeclsFromTests(allocator, tokens, graph, structs.items, struct_layouts.items, &functions);
    }
    try collectGenericFuncInstancesForTests(
        allocator,
        tokens,
        test_decls,
        structs.items,
        struct_layouts.items,
        host_imports.items,
        wasi_imports.items,
        &string_data,
        if (module_graph) |graph| graph.modules else &.{},
        &functions,
    );

    const ctx = CodegenContext{
        .functions = functions.items,
        .structs = structs.items,
        .struct_layouts = struct_layouts.items,
        .host_imports = host_imports.items,
        .wasi_imports = wasi_imports.items,
        .string_data = &string_data,
        .entry_tokens = tokens,
        .modules = if (module_graph) |graph| graph.modules else &.{},
    };

    try out.appendSlice(allocator, "(module\n");
    try appendFmt(allocator, &out, "  ;; source_len={d}\n", .{program.source_len});
    try appendFmt(allocator, &out, "  ;; token_count={d}\n", .{program.token_count});
    try appendFmt(allocator, &out, "  ;; top_level_count={d}\n", .{program.top_level_count});
    try appendFmt(allocator, &out, "  ;; compiled_test_count={d}\n", .{test_decls.len});
    try emitWasiBindings(allocator, &out, wasi_imports.items);
    try emitWasiCoreImports(allocator, &out, wasi_imports.items);
    try emitHostImports(allocator, &out, host_imports.items);
    try emitStringDataMemory(allocator, &out, string_data.items.items, .{});
    try emitArcRuntimePrelude(allocator, &out, string_data.items.items, struct_layouts.items);
    try emitUserFuncs(allocator, ctx, &out);
    try emitTestFuncs(allocator, tokens, test_decls, ctx, &out);
    try emitTestStartFunc(allocator, test_decls.len, &out);
    try out.appendSlice(allocator, ")\n");
    return out.toOwnedSlice(allocator);
}

fn emitStartFunc(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !void {
    const start_idx = findStartFunc(tokens) orelse return;
    const open_params = start_idx + 1;
    const close_params = try findMatching(tokens, open_params, "(", ")");
    const open_body = findToken(tokens, close_params + 1, tokens.len, "{") orelse return;
    const close_body = try findMatching(tokens, open_body, "{", "}");

    var locals = LocalSet{};
    defer locals.deinit(allocator);
    try collectBodyLocals(allocator, tokens, open_body + 1, close_body, ctx, &locals);

    try out.appendSlice(allocator, "  (func $_start\n");
    for (locals.locals.items) |local| {
        if (!local.emit_decl) continue;
        try appendFmt(allocator, out, "    (local ${s} {s})\n", .{ local.name, wasmType(local.ty) });
    }
    const no_results: []const []const u8 = &.{};
    const root_defer = DeferContext{
        .parent = null,
        .start_idx = open_body + 1,
        .end_idx = close_body,
        .registered_end_idx = close_body,
    };
    try emitBody(allocator, tokens, open_body + 1, close_body, &locals, ctx, no_results, null, null, &root_defer, null, out);
    if (!bodyEndsWithPlainReturn(tokens, open_body + 1, close_body)) {
        try emitFallthroughReleaseManagedLocals(allocator, &locals, ctx, out);
    }
    try out.appendSlice(allocator, "  )\n");
    try out.appendSlice(allocator, "  (export \"_start\" (func $_start))\n");
}

fn emitTestFuncs(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    test_decls: []const test_runner.TestDecl,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !void {
    for (test_decls, 0..) |decl, idx| {
        try appendFmt(allocator, out, "  ;; compiled-test {d} {s}\n", .{ idx, decl.name_lexeme });
        try appendFmt(allocator, out, "  (func $__do_test_{d}\n", .{idx});

        var locals = LocalSet{};
        defer locals.deinit(allocator);
        try collectBodyLocals(allocator, tokens, decl.body_start, decl.body_end, ctx, &locals);

        for (locals.locals.items) |local| {
            if (!local.emit_decl) continue;
            try appendFmt(allocator, out, "    (local ${s} {s})\n", .{ local.name, wasmType(local.ty) });
        }
        const no_results: []const []const u8 = &.{};
        const root_defer = DeferContext{
            .parent = null,
            .start_idx = decl.body_start,
            .end_idx = decl.body_end,
            .registered_end_idx = decl.body_end,
        };
        try emitBody(allocator, tokens, decl.body_start, decl.body_end, &locals, ctx, no_results, null, null, &root_defer, null, out);
        if (!bodyEndsWithPlainReturn(tokens, decl.body_start, decl.body_end)) {
            try emitFallthroughReleaseManagedLocals(allocator, &locals, ctx, out);
        }
        try out.appendSlice(allocator, "    unreachable\n");
        try out.appendSlice(allocator, "  )\n");
        try appendFmt(allocator, out, "  (export \"__do_test_{d}\" (func $__do_test_{d}))\n", .{ idx, idx });
    }
}

fn emitTestStartFunc(
    allocator: std.mem.Allocator,
    test_count: usize,
    out: *std.ArrayList(u8),
) !void {
    try out.appendSlice(allocator, "  (func $_start\n");
    for (0..test_count) |idx| {
        try appendFmt(allocator, out, "    call $__do_test_{d}\n", .{idx});
    }
    try out.appendSlice(allocator, "  )\n");
    try out.appendSlice(allocator, "  (export \"_start\" (func $_start))\n");
}

fn emitUserFuncs(
    allocator: std.mem.Allocator,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !void {
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        try emitUserFunc(allocator, func, ctx, out);
    }
}

fn emitUserFunc(
    allocator: std.mem.Allocator,
    func: FuncDecl,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !void {
    const tokens = func.tokens;
    try appendFmt(allocator, out, "  (func ${s}", .{func.name});
    for (func.params) |param| {
        if (findStructDecl(ctx.structs, param.ty)) |decl| {
            if (findStructLayout(ctx.struct_layouts, param.ty) == null) {
                for (decl.fields) |field| {
                    try appendFmt(allocator, out, " (param ${s}.{s} {s})", .{
                        param.name,
                        publicDeclName(field.name),
                        wasmType(field.ty),
                    });
                }
                continue;
            }
        }
        try appendFmt(allocator, out, " (param ${s} {s})", .{ param.name, wasmType(param.ty) });
    }
    if (func.results.len != 0) {
        try out.appendSlice(allocator, " (result");
        for (func.results) |result| {
            try appendFmt(allocator, out, " {s}", .{wasmType(result)});
        }
        try out.appendSlice(allocator, ")");
    }
    try out.appendSlice(allocator, "\n");

    var locals = LocalSet{};
    defer locals.deinit(allocator);
    for (func.params) |param| {
        if (managedPayloadElemTypeFromName(param.ty)) |elem_ty| {
            try locals.appendBorrowedLocal(allocator, param.name, param.ty, false);
            try locals.storage_locals.append(allocator, .{ .name = param.name, .elem_ty = elem_ty });
        } else if (findStructDecl(ctx.structs, param.ty)) |decl| {
            try locals.struct_locals.append(allocator, .{ .name = param.name, .ty = param.ty });
            if (findStructLayout(ctx.struct_layouts, param.ty) != null) {
                try locals.appendBorrowedLocal(allocator, param.name, param.ty, false);
            } else {
                for (decl.fields) |field| {
                    try appendBorrowedLocalField(allocator, &locals, param.name, field.name, field.ty);
                }
            }
        } else {
            try locals.appendBorrowedLocal(allocator, param.name, param.ty, false);
        }
    }
    try collectBodyLocals(allocator, tokens, func.body_start, func.body_end, ctx, &locals);

    for (locals.locals.items) |local| {
        if (!local.emit_decl) continue;
        try appendFmt(allocator, out, "    (local ${s} {s})\n", .{ local.name, wasmType(local.ty) });
    }
    if (func.arrow) {
        if (func.results.len != 1) return error.NoMatchingCall;
        if (!try emitExpr(allocator, tokens, func.body_start, func.body_end, &locals, ctx, func.results[0], out)) {
            return error.NoMatchingCall;
        }
        try emitFallthroughReleaseManagedLocals(allocator, &locals, ctx, out);
        try out.appendSlice(allocator, "    return\n");
    } else {
        const root_defer = DeferContext{
            .parent = null,
            .start_idx = func.body_start,
            .end_idx = func.body_end,
            .registered_end_idx = func.body_end,
        };
        try emitBody(allocator, tokens, func.body_start, func.body_end, &locals, ctx, func.results, func.result_struct, null, &root_defer, null, out);
        if (!bodyEndsWithPlainReturn(tokens, func.body_start, func.body_end)) {
            try emitFallthroughReleaseManagedLocals(allocator, &locals, ctx, out);
        }
    }
    try out.appendSlice(allocator, "  )\n");
}

fn collectBodyLocals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    out: *LocalSet,
) !void {
    var i = start_idx;
    while (i < end_idx) {
        const stmt_end = findStmtEnd(tokens, i, end_idx);
        if (stmtContainsStringLiteral(tokens, i, stmt_end)) {
            try out.ensureStorageWriteTemps(allocator);
        }
        if (stmtContainsNumericSelectIntrinsic(tokens, i, stmt_end)) {
            try out.ensureNumericSelectTemps(allocator);
        }
        if (try collectLoopBlockLocals(allocator, tokens, i, stmt_end, ctx, out)) {
            // Loop block locals collected recursively.
        } else if (try collectIfBlockLocals(allocator, tokens, i, stmt_end, ctx, out)) {
            // Block locals collected recursively.
        } else if (try collectDeferBlockLocals(allocator, tokens, i, stmt_end, ctx, out)) {
            // Cleanup block locals collected recursively.
        } else if (isTypedScalarBinding(tokens, i, stmt_end)) {
            try out.appendBorrowedLocal(allocator, tokens[i].lexeme, tokens[i + 1].lexeme, true);
        } else if (!hasLocal(out.locals.items, tokens[i].lexeme) and inferredStructCtorBinding(tokens, i, stmt_end, ctx.structs) != null) {
            const decl = inferredStructCtorBinding(tokens, i, stmt_end, ctx.structs).?;
            try out.struct_locals.append(allocator, .{ .name = tokens[i].lexeme, .ty = decl.name });
            if (findStructLayout(ctx.struct_layouts, decl.name) != null) {
                try out.appendBorrowedLocal(allocator, tokens[i].lexeme, decl.name, true);
            } else {
                for (decl.fields) |field| {
                    try appendLocalField(allocator, out, tokens[i].lexeme, field.name, field.ty);
                }
            }
        } else if (!hasLocal(out.locals.items, tokens[i].lexeme) and inferredScalarBindingType(tokens, i, stmt_end, out, ctx) != null) {
            const ty = inferredScalarBindingType(tokens, i, stmt_end, out, ctx).?;
            try out.appendBorrowedLocal(allocator, tokens[i].lexeme, ty, true);
        } else if (!hasLocal(out.locals.items, tokens[i].lexeme) and inferredManagedPayloadBinding(tokens, i, stmt_end, out, ctx) != null) {
            const binding = inferredManagedPayloadBinding(tokens, i, stmt_end, out, ctx).?;
            try out.appendStorageLocalWithType(allocator, tokens[i].lexeme, binding.ty, binding.elem_ty, true);
            try out.ensureStorageWriteTemps(allocator);
        } else if (managedPayloadBinding(tokens, i, stmt_end)) |binding| {
            try out.appendStorageLocalWithType(allocator, tokens[i].lexeme, binding.ty, binding.elem_ty, true);
            try out.ensureStorageWriteTemps(allocator);
        } else if (storageBindingElemType(tokens, i, stmt_end)) |elem_ty| {
            try out.appendStorageLocal(allocator, tokens[i].lexeme, elem_ty, true);
            try out.ensureStorageWriteTemps(allocator);
        } else if (isManagedLocalAssignmentStmt(tokens, i, stmt_end, out, ctx)) {
            try out.ensureStorageWriteTemps(allocator);
        } else if (multiResultAssignmentNeedsManagedTmp(tokens, i, stmt_end, out, ctx)) {
            if (!hasLocal(out.locals.items, STORAGE_OVERWRITE_TMP_LOCAL)) {
                try out.appendBorrowedLocal(allocator, STORAGE_OVERWRITE_TMP_LOCAL, "usize", true);
            }
        } else if (typedStructBinding(tokens, i, stmt_end, ctx.structs)) |decl| {
            try out.struct_locals.append(allocator, .{ .name = tokens[i].lexeme, .ty = decl.name });
            if (findStructLayout(ctx.struct_layouts, decl.name) != null) {
                try out.appendBorrowedLocal(allocator, tokens[i].lexeme, decl.name, true);
            } else {
                for (decl.fields) |field| {
                    try appendLocalField(allocator, out, tokens[i].lexeme, field.name, field.ty);
                }
            }
        }
        i = stmt_end;
    }
}

fn collectLoopBlockLocals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    out: *LocalSet,
) CodegenError!bool {
    if (start_idx + 3 > end_idx) return false;
    if (!tokEq(tokens[start_idx], "loop")) return false;
    const open_brace = findTopLevelBlockOpen(tokens, start_idx + 1, end_idx) orelse return false;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return false;
    if (close_brace + 1 != end_idx) return false;
    try collectBodyLocals(allocator, tokens, open_brace + 1, close_brace, ctx, out);
    return true;
}

fn collectIfBlockLocals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    out: *LocalSet,
) CodegenError!bool {
    if (start_idx + 4 > end_idx) return false;
    if (!tokEq(tokens[start_idx], "if")) return false;
    const open_brace = findTopLevelBlockOpen(tokens, start_idx + 1, end_idx) orelse return false;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return false;
    try collectBodyLocals(allocator, tokens, open_brace + 1, close_brace, ctx, out);

    if (close_brace + 1 == end_idx) return true;
    if (close_brace + 1 >= end_idx or !tokEq(tokens[close_brace + 1], "else")) return false;
    if (close_brace + 2 >= end_idx) return false;

    if (tokEq(tokens[close_brace + 2], "if")) {
        _ = try collectIfBlockLocals(allocator, tokens, close_brace + 2, end_idx, ctx, out);
        return true;
    }
    if (!tokEq(tokens[close_brace + 2], "{")) return false;
    const close_else = findMatchingInRange(tokens, close_brace + 2, "{", "}", end_idx) catch return false;
    if (close_else + 1 != end_idx) return false;
    try collectBodyLocals(allocator, tokens, close_brace + 3, close_else, ctx, out);
    return true;
}

fn collectDeferBlockLocals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    out: *LocalSet,
) CodegenError!bool {
    if (start_idx + 2 > end_idx) return false;
    if (!tokEq(tokens[start_idx], "defer")) return false;
    if (!tokEq(tokens[start_idx + 1], "{")) return false;
    const close_brace = findMatchingInRange(tokens, start_idx + 1, "{", "}", end_idx) catch return false;
    var cleanup_locals = LocalSet{};
    defer cleanup_locals.deinit(allocator);
    try collectBodyLocals(allocator, tokens, start_idx + 2, close_brace, ctx, &cleanup_locals);
    try appendDeclOnlyLocals(allocator, out, &cleanup_locals);
    return true;
}

fn appendDeclOnlyLocals(
    allocator: std.mem.Allocator,
    out: *LocalSet,
    source: *const LocalSet,
) !void {
    for (source.locals.items) |local| {
        if (hasLocal(out.locals.items, local.name)) continue;
        const name = try allocator.dupe(u8, local.name);
        errdefer allocator.free(name);
        try out.owned_names.append(allocator, name);
        errdefer _ = out.owned_names.pop();

        const ty = try allocator.dupe(u8, local.ty);
        errdefer allocator.free(ty);
        try out.owned_names.append(allocator, ty);
        errdefer _ = out.owned_names.pop();

        try out.locals.append(allocator, .{
            .name = name,
            .ty = ty,
            .emit_decl = local.emit_decl,
            .release_on_scope_exit = false,
        });
    }
    for (source.storage_locals.items) |storage| {
        if (findStorageLocal(out.storage_locals.items, storage.name) != null) continue;
        const name = try allocator.dupe(u8, storage.name);
        errdefer allocator.free(name);
        try out.owned_names.append(allocator, name);
        errdefer _ = out.owned_names.pop();

        const elem_ty = try allocator.dupe(u8, storage.elem_ty);
        errdefer allocator.free(elem_ty);
        try out.owned_names.append(allocator, elem_ty);
        errdefer _ = out.owned_names.pop();

        try out.storage_locals.append(allocator, .{ .name = name, .elem_ty = elem_ty });
    }
    for (source.struct_locals.items) |struct_local| {
        if (findStructLocal(out.struct_locals.items, struct_local.name) != null) continue;
        const name = try allocator.dupe(u8, struct_local.name);
        errdefer allocator.free(name);
        try out.owned_names.append(allocator, name);
        errdefer _ = out.owned_names.pop();

        const ty = try allocator.dupe(u8, struct_local.ty);
        errdefer allocator.free(ty);
        try out.owned_names.append(allocator, ty);
        errdefer _ = out.owned_names.pop();

        try out.struct_locals.append(allocator, .{ .name = name, .ty = ty });
    }
}

fn appendLocalField(
    allocator: std.mem.Allocator,
    out: *LocalSet,
    base: []const u8,
    field: []const u8,
    ty: []const u8,
) !void {
    const name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ base, publicDeclName(field) });
    try out.appendOwnedLocal(allocator, name, ty);
}

fn appendBorrowedLocalField(
    allocator: std.mem.Allocator,
    out: *LocalSet,
    base: []const u8,
    field: []const u8,
    ty: []const u8,
) !void {
    const name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ base, publicDeclName(field) });
    try out.owned_names.append(allocator, name);
    try out.appendBorrowedLocal(allocator, name, ty, false);
}

fn emitReturnStmt(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_struct: ?[]const u8,
    defer_ctx: ?*const DeferContext,
    return_label: ?[]const u8,
    out: *std.ArrayList(u8),
) !bool {
    if (start_idx >= end_idx or !tokEq(tokens[start_idx], "return")) return false;
    const expected_ty: ?[]const u8 = if (result_tys.len == 1) result_tys[0] else null;
    var move_names = std.ArrayList([]const u8).empty;
    defer move_names.deinit(allocator);

    const single_move_name = if (expected_ty) |ty|
        if (isManagedLocalType(ty, ctx)) directManagedLocalExprName(tokens, start_idx + 1, end_idx, locals, ctx) else null
    else
        null;
    if (single_move_name) |name| {
        try move_names.append(allocator, name);
        try appendFmt(allocator, out, "    ;; arc-return-move {s}\n", .{name});
    }
    if (try emitUnmanagedStructErrorUnionReturn(allocator, tokens, start_idx, end_idx, locals, ctx, result_tys, result_struct, out)) {
        // Unmanaged struct plus error tag emitted as payload fields followed by status.
    } else if (try emitUnmanagedStructReturnLocal(allocator, tokens, start_idx, end_idx, locals, ctx, result_tys, result_struct, out)) {
        // Unmanaged struct fields emitted in declaration order.
    } else if (try emitWasiRecordReturnCall(allocator, tokens, start_idx + 1, end_idx, locals, ctx, result_tys, result_struct, out)) {
        // WIT record result fields emitted in declaration order.
    } else if (result_tys.len > 1 and try emitMultiResultReturnCall(allocator, tokens, start_idx + 1, end_idx, locals, ctx, result_tys, out)) {
        // Multi-result call passthrough emitted.
    } else if (result_tys.len > 1) {
        var expr_start = start_idx + 1;
        var result_idx: usize = 0;
        while (expr_start < end_idx) {
            if (result_idx >= result_tys.len) return error.NoMatchingCall;
            const expr_end = findArgEnd(tokens, expr_start, end_idx);
            var copy_returned_managed_local = false;
            if (isManagedLocalType(result_tys[result_idx], ctx)) {
                if (directManagedLocalExprName(tokens, expr_start, expr_end, locals, ctx)) |name| {
                    if (hasBorrowedName(move_names.items, name)) {
                        copy_returned_managed_local = true;
                        try appendFmt(allocator, out, "    ;; arc-return-copy {s}\n", .{name});
                    } else {
                        try move_names.append(allocator, name);
                        try appendFmt(allocator, out, "    ;; arc-return-move {s}\n", .{name});
                    }
                }
            }
            if (!try emitExpr(allocator, tokens, expr_start, expr_end, locals, ctx, result_tys[result_idx], out)) {
                return error.NoMatchingCall;
            }
            if (copy_returned_managed_local) {
                try out.appendSlice(allocator, "    call $__do_arc_inc\n");
            }
            result_idx += 1;
            expr_start = expr_end;
            if (expr_start < end_idx and tokEq(tokens[expr_start], ",")) expr_start += 1;
        }
        if (result_idx != result_tys.len) return error.NoMatchingCall;
    } else if (result_tys.len == 0 and start_idx + 2 == end_idx and tokEq(tokens[start_idx + 1], "nil")) {
        // `return nil` is the explicit spelling of an empty return in test/nil functions.
    } else if (start_idx + 1 < end_idx) {
        if (!try emitExpr(allocator, tokens, start_idx + 1, end_idx, locals, ctx, expected_ty, out)) {
            return error.NoMatchingCall;
        }
    }
    try emitDeferCleanupStack(allocator, tokens, defer_ctx, locals, ctx, out);
    if (return_label) |label| {
        try appendFmt(allocator, out, "    br ${s}\n", .{label});
    } else {
        try emitReleaseManagedLocalsExceptMany(allocator, locals, ctx, move_names.items, out);
        try out.appendSlice(allocator, "    return\n");
    }
    return true;
}

fn emitUnmanagedStructErrorUnionReturn(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_struct: ?[]const u8,
    out: *std.ArrayList(u8),
) !bool {
    const error_name = unmanagedStructErrorUnionResult(tokens, ctx, result_tys, result_struct) orelse return false;
    const struct_name = result_struct.?;
    const decl = findStructDecl(ctx.structs, struct_name) orelse return error.NoMatchingCall;
    if (start_idx + 1 >= end_idx) return error.NoMatchingCall;

    const expr_start = start_idx + 1;
    const expr_end = end_idx;
    const range = trimParens(tokens, expr_start, expr_end);
    if (exprCallHead(tokens, range)) |call_head| {
        if (!call_head.is_intrinsic) {
            const func = findFuncDeclForCall(tokens, call_head.args_start, call_head.args_end, locals, ctx, tokens[call_head.name_idx].lexeme) orelse return false;
            if (func.results.len == result_tys.len) {
                var matches = true;
                for (result_tys, 0..) |result_ty, i| {
                    if (!std.mem.eql(u8, result_ty, func.results[i])) {
                        matches = false;
                        break;
                    }
                }
                if (matches) {
                    return try emitUserFuncCall(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, out);
                }
            }
        }
        return false;
    }

    if (range.end == range.start + 1 and tokens[range.start].kind == .ident) {
        const name = tokens[range.start].lexeme;
        if (findStructLocal(locals.struct_locals.items, name)) |struct_local| {
            if (std.mem.eql(u8, struct_local.ty, struct_name) and findStructLayout(ctx.struct_layouts, struct_name) == null) {
                for (decl.fields) |field| {
                    try appendFmt(allocator, out, "    local.get ${s}.{s}\n", .{
                        name,
                        publicDeclName(field.name),
                    });
                }
                try out.appendSlice(allocator, "    i32.const 0\n");
                return true;
            }
        }

        if (errorEnumBranchValue(tokens, error_name, name) != null or std.mem.eql(u8, findLocalType(locals.locals.items, name) orelse "", error_name)) {
            for (decl.fields) |field| {
                try emitZeroValueForType(allocator, out, field.ty);
            }
            if (!try emitExpr(allocator, tokens, range.start, range.end, locals, ctx, error_name, out)) return error.NoMatchingCall;
            return true;
        }
    }

    return false;
}

fn emitUnmanagedStructReturnLocal(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_struct: ?[]const u8,
    out: *std.ArrayList(u8),
) !bool {
    const struct_name = result_struct orelse return false;
    if (start_idx + 2 != end_idx) return false;
    if (tokens[start_idx + 1].kind != .ident) return false;
    const local_name = tokens[start_idx + 1].lexeme;
    const struct_local = findStructLocal(locals.struct_locals.items, local_name) orelse return false;
    if (!std.mem.eql(u8, struct_local.ty, struct_name)) return false;
    if (findStructLayout(ctx.struct_layouts, struct_name) != null) return false;
    const decl = findStructDecl(ctx.structs, struct_name) orelse return error.NoMatchingCall;
    if (decl.fields.len != result_tys.len) return error.NoMatchingCall;

    for (decl.fields, 0..) |field, idx| {
        if (!std.mem.eql(u8, field.ty, result_tys[idx])) return error.NoMatchingCall;
        try appendFmt(allocator, out, "    local.get ${s}.{s}\n", .{
            local_name,
            publicDeclName(field.name),
        });
    }
    return true;
}

fn emitZeroValueForType(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    ty: []const u8,
) !void {
    try appendFmt(allocator, out, "    {s}.const 0\n", .{wasmType(ty)});
}

fn emitMultiResultReturnCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const range = trimParens(tokens, start_idx, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = findFuncDeclForCall(tokens, call_head.args_start, call_head.args_end, locals, ctx, tokens[call_head.name_idx].lexeme) orelse return false;
    if (func.results.len != result_tys.len) return false;
    for (result_tys, 0..) |result_ty, i| {
        if (!std.mem.eql(u8, result_ty, func.results[i])) return false;
    }
    return try emitUserFuncCall(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, out);
}

fn emitReleaseManagedLocals(
    allocator: std.mem.Allocator,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !void {
    try emitReleaseManagedLocalsExcept(allocator, locals, ctx, null, out);
}

fn emitReleaseManagedLocalsExcept(
    allocator: std.mem.Allocator,
    locals: *const LocalSet,
    ctx: CodegenContext,
    skip_name: ?[]const u8,
    out: *std.ArrayList(u8),
) !void {
    if (skip_name) |name| {
        const skip_names = [_][]const u8{name};
        return emitReleaseManagedLocalsExceptMany(allocator, locals, ctx, &skip_names, out);
    }
    return emitReleaseManagedLocalsExceptMany(allocator, locals, ctx, &.{}, out);
}

fn emitReleaseManagedLocalsExceptMany(
    allocator: std.mem.Allocator,
    locals: *const LocalSet,
    ctx: CodegenContext,
    skip_names: []const []const u8,
    out: *std.ArrayList(u8),
) !void {
    var i = locals.locals.items.len;
    while (i > 0) {
        i -= 1;
        const local = locals.locals.items[i];
        if (!local.release_on_scope_exit) continue;
        if (!isManagedLocalType(local.ty, ctx)) continue;
        if (hasBorrowedName(skip_names, local.name)) continue;
        try appendFmt(allocator, out, "    ;; arc-release-local {s}\n", .{local.name});
        try appendFmt(allocator, out, "    local.get ${s}\n", .{local.name});
        try out.appendSlice(allocator, "    call $__do_arc_dec\n");
    }
}

fn emitFallthroughReleaseManagedLocals(
    allocator: std.mem.Allocator,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !void {
    if (!hasManagedLocals(locals, ctx)) return;
    try out.appendSlice(allocator, "    ;; arc-fallthrough-release\n");
    try emitReleaseManagedLocals(allocator, locals, ctx, out);
}

fn emitBlockReleaseManagedLocals(
    allocator: std.mem.Allocator,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !void {
    if (!hasManagedLocals(locals, ctx)) return;
    try out.appendSlice(allocator, "    ;; arc-block-release\n");
    var i = locals.locals.items.len;
    while (i > 0) {
        i -= 1;
        const local = locals.locals.items[i];
        if (!local.release_on_scope_exit) continue;
        if (!isManagedLocalType(local.ty, ctx)) continue;
        try appendFmt(allocator, out, "    ;; arc-release-local {s}\n", .{local.name});
        try appendFmt(allocator, out, "    local.get ${s}\n", .{local.name});
        try out.appendSlice(allocator, "    call $__do_arc_dec\n");
        try out.appendSlice(allocator, "    i32.const 0\n");
        try appendFmt(allocator, out, "    local.set ${s}\n", .{local.name});
    }
}

fn hasManagedLocals(locals: *const LocalSet, ctx: CodegenContext) bool {
    for (locals.locals.items) |local| {
        if (!local.release_on_scope_exit) continue;
        if (isManagedLocalType(local.ty, ctx)) return true;
    }
    return false;
}

fn bodyEndsWithPlainReturn(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    var last_start: ?usize = null;
    while (i < end_idx) {
        const stmt_end = findStmtEnd(tokens, i, end_idx);
        if (i < stmt_end) last_start = i;
        i = stmt_end;
    }
    const idx = last_start orelse return false;
    return tokEq(tokens[idx], "return");
}

fn isManagedLocalType(ty: []const u8, ctx: CodegenContext) bool {
    if (isManagedPayloadType(ty)) return true;
    return findStructLayout(ctx.struct_layouts, ty) != null;
}

fn isDirectManagedLocalExpr(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) bool {
    return directManagedLocalExprName(tokens, start_idx, end_idx, locals, ctx) != null;
}

fn directManagedLocalExprName(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    if (end_idx != start_idx + 1) return null;
    if (tokens[start_idx].kind != .ident) return null;
    const ty = findLocalType(locals.locals.items, tokens[start_idx].lexeme) orelse return null;
    if (!isManagedLocalType(ty, ctx)) return null;
    return tokens[start_idx].lexeme;
}

fn emitStorageBinding(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !void {
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return error.NoMatchingCall;
    if (eq_idx + 1 >= end_idx) return error.NoMatchingCall;
    const storage = findStorageLocal(locals.storage_locals.items, tokens[start_idx].lexeme) orelse return error.NoMatchingCall;
    if (tokens[eq_idx + 1].kind == .string) {
        if (!std.mem.eql(u8, storage.elem_ty, "u8")) return error.NoMatchingCall;
        try emitStorageU8StringLiteral(allocator, tokens, eq_idx + 1, tokens[start_idx].lexeme, ctx, out);
        return;
    }

    if (try emitStorageAggLiteral(allocator, tokens, eq_idx + 1, end_idx, tokens[start_idx].lexeme, storage.elem_ty, locals, ctx, out)) {
        return;
    }

    const expected_ty = findLocalType(locals.locals.items, tokens[start_idx].lexeme) orelse return error.NoMatchingCall;
    if (try emitStorageHandleBindingExpr(allocator, tokens, eq_idx + 1, end_idx, expected_ty, locals, ctx, out)) {
        if (isDirectManagedLocalExpr(tokens, eq_idx + 1, end_idx, locals, ctx)) {
            try out.appendSlice(allocator, "    call $__do_arc_inc\n");
        }
        try appendFmt(allocator, out, "    local.set ${s}\n", .{tokens[start_idx].lexeme});
        return;
    }

    if (!try emitStorageWriteExpr(allocator, tokens, eq_idx + 1, end_idx, tokens[start_idx].lexeme, locals, ctx, out)) return error.NoMatchingCall;
    try appendFmt(allocator, out, "    local.set ${s}\n", .{tokens[start_idx].lexeme});
}

fn emitStorageHandleBindingExpr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    expected_ty: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (!std.mem.eql(u8, inferExprType(tokens, start_idx, end_idx, locals, ctx) orelse "", expected_ty)) return false;
    if (!try emitExpr(allocator, tokens, start_idx, end_idx, locals, ctx, expected_ty, out)) return false;
    return true;
}

fn emitStorageU8StringLiteral(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    string_idx: usize,
    local_name: []const u8,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !void {
    try emitStorageU8StringLiteralIntoLocal(allocator, tokens, string_idx, local_name, ctx, out);
}

fn emitStorageU8StringLiteralValue(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    string_idx: usize,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !void {
    try emitStorageU8StringLiteralIntoLocal(allocator, tokens, string_idx, STORAGE_OVERWRITE_TMP_LOCAL, ctx, out);
    try out.appendSlice(allocator, "    local.get $" ++ STORAGE_OVERWRITE_TMP_LOCAL ++ "\n");
}

fn emitStorageU8StringLiteralIntoLocal(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    string_idx: usize,
    local_name: []const u8,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !void {
    const data = ctx.string_data.find(tokens[string_idx].lexeme) orelse return error.NoMatchingCall;
    try appendFmt(allocator, out, "    i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES + data.bytes.len});
    try appendFmt(allocator, out, "    i32.const {d}\n", .{TYPE_ID_STORAGE_U8});
    try out.appendSlice(allocator, "    call $__do_arc_alloc\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{local_name});
    try emitStorageLenPtr(allocator, out, local_name);
    try appendFmt(allocator, out, "    i32.const {d}\n", .{data.bytes.len});
    try out.appendSlice(allocator, "    i32.store\n");
    try emitStorageCapPtr(allocator, out, local_name);
    try appendFmt(allocator, out, "    i32.const {d}\n", .{data.bytes.len});
    try out.appendSlice(allocator, "    i32.store\n");
    try emitStorageDataPtr(allocator, out, local_name);
    try appendFmt(allocator, out, "    i32.const {d}\n", .{data.ptr});
    try appendFmt(allocator, out, "    i32.const {d}\n", .{data.bytes.len});
    try out.appendSlice(allocator, "    memory.copy\n");
}

fn emitStorageAggLiteral(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    local_name: []const u8,
    elem_ty: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (start_idx + 2 > end_idx) return false;
    if (!tokEq(tokens[start_idx], ".")) return false;
    if (!tokEq(tokens[start_idx + 1], "{")) return false;
    const close_brace = findMatchingInRange(tokens, start_idx + 1, "{", "}", end_idx) catch return false;
    if (close_brace + 1 != end_idx) return false;

    const elem_bytes = storageElementByteWidthForType(elem_ty, ctx) orelse return false;
    const type_id = storageTypeIdForElement(elem_ty, ctx);
    const count = countAggLiteralItems(tokens, start_idx + 2, close_brace);
    try appendFmt(allocator, out, "    i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES + count * elem_bytes});
    try appendFmt(allocator, out, "    i32.const {d}\n", .{type_id});
    try out.appendSlice(allocator, "    call $__do_arc_alloc\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{local_name});
    try emitStorageLenPtr(allocator, out, local_name);
    try appendFmt(allocator, out, "    i32.const {d}\n", .{count});
    try out.appendSlice(allocator, "    i32.store\n");
    try emitStorageCapPtr(allocator, out, local_name);
    try appendFmt(allocator, out, "    i32.const {d}\n", .{count});
    try out.appendSlice(allocator, "    i32.store\n");

    var item_start = start_idx + 2;
    var item_index: usize = 0;
    while (item_start < close_brace) {
        if (tokEq(tokens[item_start], ",")) {
            item_start += 1;
            continue;
        }
        const item_end = findArgEnd(tokens, item_start, close_brace);
        if (item_end == item_start) return error.NoMatchingCall;
        try emitStorageDataPtr(allocator, out, local_name);
        if (item_index * elem_bytes != 0) {
            try appendFmt(allocator, out, "    i32.const {d}\n", .{item_index * elem_bytes});
            try out.appendSlice(allocator, "    i32.add\n");
        }
        if (!try emitExpr(allocator, tokens, item_start, item_end, locals, ctx, elem_ty, out)) return error.NoMatchingCall;
        if (isManagedLocalType(elem_ty, ctx) and isDirectManagedLocalExpr(tokens, item_start, item_end, locals, ctx)) {
            try out.appendSlice(allocator, "    ;; storage-managed-element-inc\n");
            try out.appendSlice(allocator, "    call $__do_arc_inc\n");
        }
        try appendStoreForPayloadType(allocator, out, elem_ty);
        item_index += 1;
        item_start = item_end;
        if (item_start < close_brace and tokEq(tokens[item_start], ",")) item_start += 1;
    }
    if (item_index != count) return error.NoMatchingCall;
    return true;
}

fn countAggLiteralItems(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    var count: usize = 0;
    var item_start = start_idx;
    while (item_start < end_idx) {
        if (tokEq(tokens[item_start], ",")) {
            item_start += 1;
            continue;
        }
        const item_end = findArgEnd(tokens, item_start, end_idx);
        if (item_end == item_start) break;
        count += 1;
        item_start = item_end;
        if (item_start < end_idx and tokEq(tokens[item_start], ",")) item_start += 1;
    }
    return count;
}

fn emitStoragePayloadPtr(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
) !void {
    try appendFmt(allocator, out, "    local.get ${s}\n", .{name});
    try out.appendSlice(allocator, "    call $__do_arc_payload\n");
}

fn emitStorageLenPtr(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
) !void {
    try emitStoragePayloadPtr(allocator, out, name);
}

fn emitStorageCapPtr(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
) !void {
    try emitStoragePayloadPtr(allocator, out, name);
    try out.appendSlice(allocator, "    i32.const 4\n");
    try out.appendSlice(allocator, "    i32.add\n");
}

fn emitStorageDataPtr(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
) !void {
    try emitStoragePayloadPtr(allocator, out, name);
    try appendFmt(allocator, out, "    i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES});
    try out.appendSlice(allocator, "    i32.add\n");
}

fn emitStructBinding(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    decl: StructDecl,
    out: *std.ArrayList(u8),
) !void {
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return error.NoMatchingCall;
    if (eq_idx + 1 >= end_idx) return error.NoMatchingCall;
    if (findStructLayout(ctx.struct_layouts, decl.name) != null and (eq_idx + 2 >= end_idx or !tokEq(tokens[eq_idx + 2], "{"))) {
        if (!try emitExpr(allocator, tokens, eq_idx + 1, end_idx, locals, ctx, decl.name, out)) return error.NoMatchingCall;
        if (isDirectManagedLocalExpr(tokens, eq_idx + 1, end_idx, locals, ctx)) {
            try out.appendSlice(allocator, "    call $__do_arc_inc\n");
        }
        try appendFmt(allocator, out, "    local.set ${s}\n", .{tokens[start_idx].lexeme});
        return;
    }
    if (findStructLayout(ctx.struct_layouts, decl.name) == null) {
        if (try emitWasiRecordStructBinding(allocator, tokens, start_idx, end_idx, locals, ctx, decl, out)) {
            return;
        }
        if (try emitUnmanagedStructCallBinding(allocator, tokens, start_idx, end_idx, locals, ctx, decl, out)) {
            return;
        }
    }
    if (eq_idx + 2 >= end_idx) return error.NoMatchingCall;
    if (tokens[eq_idx + 1].kind != .ident) return error.NoMatchingCall;
    if (!tokEq(tokens[eq_idx + 2], "{")) return error.NoMatchingCall;
    const close_brace = findMatchingInRange(tokens, eq_idx + 2, "{", "}", end_idx) catch return error.NoMatchingCall;
    if (close_brace + 1 != end_idx) return error.NoMatchingCall;

    if (findStructLayout(ctx.struct_layouts, decl.name)) |layout| {
        try appendFmt(allocator, out, "    i32.const {d}\n", .{layout.payload_bytes});
        try appendFmt(allocator, out, "    i32.const {d}\n", .{layout.type_id});
        try out.appendSlice(allocator, "    call $__do_arc_alloc\n");
        try appendFmt(allocator, out, "    local.set ${s}\n", .{tokens[start_idx].lexeme});
        try emitManagedStructFields(allocator, tokens, eq_idx + 3, close_brace, tokens[start_idx].lexeme, locals, ctx, decl, layout, out);
        return;
    }

    var field_start = eq_idx + 3;
    while (field_start < close_brace) {
        if (tokEq(tokens[field_start], ",")) {
            field_start += 1;
            continue;
        }
        if (tokens[field_start].kind != .ident) return error.NoMatchingCall;
        const assign_idx = findTopLevelToken(tokens, field_start + 1, close_brace, "=") orelse return error.NoMatchingCall;
        const field_end = findStructLiteralFieldEnd(tokens, assign_idx + 1, close_brace);
        const field_ty = findStructFieldType(decl, publicDeclName(tokens[field_start].lexeme));
        if (!try emitExpr(allocator, tokens, assign_idx + 1, field_end, locals, ctx, field_ty, out)) return error.NoMatchingCall;
        try appendFmt(allocator, out, "    local.set ${s}.{s}\n", .{
            tokens[start_idx].lexeme,
            publicDeclName(tokens[field_start].lexeme),
        });
        field_start = field_end;
        if (field_start < close_brace and tokEq(tokens[field_start], ",")) field_start += 1;
    }
}

fn emitUnmanagedStructCallBinding(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    decl: StructDecl,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return false;
    const rhs_range = trimParens(tokens, eq_idx + 1, end_idx);
    const call_head = exprCallHead(tokens, rhs_range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = findFuncDeclForCall(tokens, call_head.args_start, call_head.args_end, locals, ctx, tokens[call_head.name_idx].lexeme) orelse return false;
    const result_struct = func.result_struct orelse return false;
    if (!std.mem.eql(u8, result_struct, decl.name)) return false;
    if (func.results.len != decl.fields.len) return error.NoMatchingCall;
    for (decl.fields, 0..) |field, idx| {
        if (!std.mem.eql(u8, field.ty, func.results[idx])) return error.NoMatchingCall;
    }
    if (!try emitUserFuncCall(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, out)) {
        return error.NoMatchingCall;
    }

    var i = decl.fields.len;
    while (i > 0) {
        i -= 1;
        try appendFmt(allocator, out, "    local.set ${s}.{s}\n", .{
            tokens[start_idx].lexeme,
            publicDeclName(decl.fields[i].name),
        });
    }
    return true;
}

fn emitWasiResultFilesizeMultiAssignment(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    lhs_start_idx: usize,
    eq_idx: usize,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const lowering = wasiLowering(import) orelse return false;
    if (!lowering.result_filesize_error) return false;

    const first_lhs_end = findArgEnd(tokens, lhs_start_idx, eq_idx);
    if (first_lhs_end != lhs_start_idx + 1 or tokens[lhs_start_idx].kind != .ident) return error.NoMatchingCall;
    if (first_lhs_end >= eq_idx or !tokEq(tokens[first_lhs_end], ",")) return error.NoMatchingCall;
    const second_lhs_start = first_lhs_end + 1;
    const second_lhs_end = findArgEnd(tokens, second_lhs_start, eq_idx);
    if (second_lhs_end != second_lhs_start + 1 or second_lhs_end != eq_idx or tokens[second_lhs_start].kind != .ident) {
        return error.NoMatchingCall;
    }

    const written_name = tokens[lhs_start_idx].lexeme;
    const status_name = tokens[second_lhs_start].lexeme;
    const written_ty = findLocalType(locals.locals.items, written_name) orelse return error.NoMatchingCall;
    const status_ty = findLocalType(locals.locals.items, status_name) orelse return error.NoMatchingCall;
    if (!std.mem.eql(u8, written_ty, "u64")) return error.NoMatchingCall;
    if (!std.mem.eql(u8, status_ty, "i32")) return error.NoMatchingCall;

    if (!try emitWasiResultFilesizeCall(allocator, tokens, args_start, args_end, locals, ctx, import, out)) {
        return error.NoMatchingCall;
    }
    try emitWasiResultFilesizeValues(allocator, out);
    try appendFmt(allocator, out, "    local.set ${s}\n", .{status_name});
    try appendFmt(allocator, out, "    local.set ${s}\n", .{written_name});
    return true;
}

fn emitWasiResultU64StreamStatusMultiAssignment(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    lhs_start_idx: usize,
    eq_idx: usize,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const lowering = wasiLowering(import) orelse return false;
    if (!lowering.result_u64_stream_error) return false;

    const first_lhs_end = findArgEnd(tokens, lhs_start_idx, eq_idx);
    if (first_lhs_end != lhs_start_idx + 1 or tokens[lhs_start_idx].kind != .ident) return error.NoMatchingCall;
    if (first_lhs_end >= eq_idx or !tokEq(tokens[first_lhs_end], ",")) return error.NoMatchingCall;
    const second_lhs_start = first_lhs_end + 1;
    const second_lhs_end = findArgEnd(tokens, second_lhs_start, eq_idx);
    if (second_lhs_end != second_lhs_start + 1 or second_lhs_end != eq_idx or tokens[second_lhs_start].kind != .ident) {
        return error.NoMatchingCall;
    }

    const value_name = tokens[lhs_start_idx].lexeme;
    const status_name = tokens[second_lhs_start].lexeme;
    const value_ty = findLocalType(locals.locals.items, value_name) orelse return error.NoMatchingCall;
    const status_ty = findLocalType(locals.locals.items, status_name) orelse return error.NoMatchingCall;
    if (!std.mem.eql(u8, value_ty, "u64")) return error.NoMatchingCall;
    if (!std.mem.eql(u8, status_ty, "i32")) return error.NoMatchingCall;

    if (!try emitWasiResultU64StreamCall(allocator, tokens, args_start, args_end, locals, ctx, import, out)) {
        return error.NoMatchingCall;
    }
    try emitWasiResultFilesizeValues(allocator, out);
    try appendFmt(allocator, out, "    local.set ${s}\n", .{status_name});
    try appendFmt(allocator, out, "    local.set ${s}\n", .{value_name});
    return true;
}

fn emitWasiResultDescriptorStatusMultiAssignment(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    lhs_start_idx: usize,
    eq_idx: usize,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const lowering = wasiLowering(import) orelse return false;
    if (!lowering.result_descriptor_error) return false;

    const first_lhs_end = findArgEnd(tokens, lhs_start_idx, eq_idx);
    if (first_lhs_end != lhs_start_idx + 1 or tokens[lhs_start_idx].kind != .ident) return error.NoMatchingCall;
    if (first_lhs_end >= eq_idx or !tokEq(tokens[first_lhs_end], ",")) return error.NoMatchingCall;
    const second_lhs_start = first_lhs_end + 1;
    const second_lhs_end = findArgEnd(tokens, second_lhs_start, eq_idx);
    if (second_lhs_end != second_lhs_start + 1 or second_lhs_end != eq_idx or tokens[second_lhs_start].kind != .ident) {
        return error.NoMatchingCall;
    }

    const descriptor_name = tokens[lhs_start_idx].lexeme;
    const status_name = tokens[second_lhs_start].lexeme;
    const descriptor_ty = findLocalType(locals.locals.items, descriptor_name) orelse return error.NoMatchingCall;
    const status_ty = findLocalType(locals.locals.items, status_name) orelse return error.NoMatchingCall;
    if (!std.mem.eql(u8, descriptor_ty, "i32")) return error.NoMatchingCall;
    if (!std.mem.eql(u8, status_ty, "i32")) return error.NoMatchingCall;

    if (!try emitWasiResultDescriptorCall(allocator, tokens, args_start, args_end, locals, ctx, import, out)) {
        return error.NoMatchingCall;
    }
    try emitWasiResultDescriptorValues(allocator, out);
    try appendFmt(allocator, out, "    local.set ${s}\n", .{status_name});
    try appendFmt(allocator, out, "    local.set ${s}\n", .{descriptor_name});
    return true;
}

fn emitWasiResultUnitStatusMultiAssignment(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    lhs_start_idx: usize,
    eq_idx: usize,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const lowering = wasiLowering(import) orelse return false;
    if (!lowering.result_unit_error) return false;

    const discard_lhs_end = findArgEnd(tokens, lhs_start_idx, eq_idx);
    if (discard_lhs_end != lhs_start_idx + 1 or tokens[lhs_start_idx].kind != .ident) return error.NoMatchingCall;
    if (!std.mem.eql(u8, tokens[lhs_start_idx].lexeme, "_")) return error.NoMatchingCall;
    if (discard_lhs_end >= eq_idx or !tokEq(tokens[discard_lhs_end], ",")) return error.NoMatchingCall;

    const status_lhs_start = discard_lhs_end + 1;
    const status_lhs_end = findArgEnd(tokens, status_lhs_start, eq_idx);
    if (status_lhs_end != status_lhs_start + 1 or status_lhs_end != eq_idx or tokens[status_lhs_start].kind != .ident) {
        return error.NoMatchingCall;
    }

    const status_name = tokens[status_lhs_start].lexeme;
    const status_ty = findLocalType(locals.locals.items, status_name) orelse return error.NoMatchingCall;
    if (!std.mem.eql(u8, status_ty, "i32")) return error.NoMatchingCall;

    if (!try emitWasiResultUnitCall(allocator, tokens, args_start, args_end, locals, ctx, import, out)) {
        return error.NoMatchingCall;
    }
    try emitWasiResultUnitStatusValue(allocator, out);
    try appendFmt(allocator, out, "    local.set ${s}\n", .{status_name});
    return true;
}

fn emitWasiResultReadMultiAssignment(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    lhs_start_idx: usize,
    eq_idx: usize,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const lowering = wasiLowering(import) orelse return false;
    if (!lowering.result_read_error) return false;

    const data_lhs_end = findArgEnd(tokens, lhs_start_idx, eq_idx);
    if (data_lhs_end != lhs_start_idx + 1 or tokens[lhs_start_idx].kind != .ident) return error.NoMatchingCall;
    if (data_lhs_end >= eq_idx or !tokEq(tokens[data_lhs_end], ",")) return error.NoMatchingCall;

    const done_lhs_start = data_lhs_end + 1;
    const done_lhs_end = findArgEnd(tokens, done_lhs_start, eq_idx);
    if (done_lhs_end != done_lhs_start + 1 or done_lhs_end >= eq_idx or tokens[done_lhs_start].kind != .ident) {
        return error.NoMatchingCall;
    }
    if (!tokEq(tokens[done_lhs_end], ",")) return error.NoMatchingCall;

    const status_lhs_start = done_lhs_end + 1;
    const status_lhs_end = findArgEnd(tokens, status_lhs_start, eq_idx);
    if (status_lhs_end != status_lhs_start + 1 or status_lhs_end != eq_idx or tokens[status_lhs_start].kind != .ident) {
        return error.NoMatchingCall;
    }

    const data_name = tokens[lhs_start_idx].lexeme;
    const done_name = tokens[done_lhs_start].lexeme;
    const status_name = tokens[status_lhs_start].lexeme;
    const data_storage = findStorageLocal(locals.storage_locals.items, data_name) orelse return error.NoMatchingCall;
    const done_ty = findLocalType(locals.locals.items, done_name) orelse return error.NoMatchingCall;
    const status_ty = findLocalType(locals.locals.items, status_name) orelse return error.NoMatchingCall;
    if (!std.mem.eql(u8, data_storage.elem_ty, "u8")) return error.NoMatchingCall;
    if (!std.mem.eql(u8, done_ty, "bool")) return error.NoMatchingCall;
    if (!std.mem.eql(u8, status_ty, "i32")) return error.NoMatchingCall;

    if (!try emitWasiResultReadCall(allocator, tokens, args_start, args_end, locals, ctx, import, out)) {
        return error.NoMatchingCall;
    }
    try emitWasiResultReadValues(allocator, out);
    try appendFmt(allocator, out, "    local.set ${s}\n", .{status_name});
    try appendFmt(allocator, out, "    local.set ${s}\n", .{done_name});
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try emitReplaceManagedLocalFromTmp(allocator, data_name, out);
    return true;
}

fn emitWasiResultListU8StatusMultiAssignment(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    lhs_start_idx: usize,
    eq_idx: usize,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const lowering = wasiLowering(import) orelse return false;
    if (!lowering.result_list_u8_error) return false;

    const data_lhs_end = findArgEnd(tokens, lhs_start_idx, eq_idx);
    if (data_lhs_end != lhs_start_idx + 1 or tokens[lhs_start_idx].kind != .ident) return error.NoMatchingCall;
    if (data_lhs_end >= eq_idx or !tokEq(tokens[data_lhs_end], ",")) return error.NoMatchingCall;

    const status_lhs_start = data_lhs_end + 1;
    const status_lhs_end = findArgEnd(tokens, status_lhs_start, eq_idx);
    if (status_lhs_end != status_lhs_start + 1 or status_lhs_end != eq_idx or tokens[status_lhs_start].kind != .ident) {
        return error.NoMatchingCall;
    }

    const data_name = tokens[lhs_start_idx].lexeme;
    const status_name = tokens[status_lhs_start].lexeme;
    const data_storage = findStorageLocal(locals.storage_locals.items, data_name) orelse return error.NoMatchingCall;
    const status_ty = findLocalType(locals.locals.items, status_name) orelse return error.NoMatchingCall;
    if (!std.mem.eql(u8, data_storage.elem_ty, "u8")) return error.NoMatchingCall;
    if (!std.mem.eql(u8, status_ty, "i32")) return error.NoMatchingCall;

    if (!try emitWasiResultListU8Call(allocator, tokens, args_start, args_end, locals, ctx, import, out)) {
        return error.NoMatchingCall;
    }
    try emitWasiResultListU8Values(allocator, out);
    try appendFmt(allocator, out, "    local.set ${s}\n", .{status_name});
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try emitReplaceManagedLocalFromTmp(allocator, data_name, out);
    return true;
}

fn emitWasiRecordStructBinding(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    decl: StructDecl,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return false;
    const rhs_range = trimParens(tokens, eq_idx + 1, end_idx);
    const call_head = exprCallHead(tokens, rhs_range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const import = findWasiHostImportForTokens(ctx, tokens, tokens[call_head.name_idx].lexeme) orelse return false;
    if (!try emitWasiRecordResultFields(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, import, decl.name, out)) {
        return false;
    }

    var i = decl.fields.len;
    while (i > 0) {
        i -= 1;
        try appendFmt(allocator, out, "    local.set ${s}.{s}\n", .{
            tokens[start_idx].lexeme,
            publicDeclName(decl.fields[i].name),
        });
    }
    return true;
}

fn emitWasiRecordReturnCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_struct: ?[]const u8,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const struct_name = result_struct orelse return false;
    const range = trimParens(tokens, start_idx, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const import = findWasiHostImportForTokens(ctx, tokens, tokens[call_head.name_idx].lexeme) orelse return false;
    const decl = findStructDecl(ctx.structs, struct_name) orelse return error.NoMatchingCall;
    if (decl.fields.len != result_tys.len) return error.NoMatchingCall;
    for (decl.fields, 0..) |field, idx| {
        if (!std.mem.eql(u8, field.ty, result_tys[idx])) return error.NoMatchingCall;
    }
    return try emitWasiRecordResultFields(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, import, struct_name, out);
}

fn emitWasiRecordResultFields(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    struct_name: []const u8,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    _ = locals;
    _ = tokens;
    if (args_start != args_end) return error.NoMatchingCall;
    const lowering = wasiLowering(import) orelse return false;
    const result_record = lowering.result_record orelse return false;
    if (!std.mem.eql(u8, result_record, struct_name)) return false;
    if (findStructLayout(ctx.struct_layouts, struct_name) != null) return false;
    const decl = findStructDecl(ctx.structs, struct_name) orelse return error.NoMatchingCall;

    try out.appendSlice(allocator, "    global.get $__do_wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try appendWasiImportSymbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");

    for (decl.fields) |field| {
        const field_name = publicDeclName(field.name);
        const field_offset = structFieldPayloadOffset(decl, field_name) orelse return error.NoMatchingCall;
        try out.appendSlice(allocator, "    global.get $__do_wasi_result_area_base\n");
        if (field_offset != 0) {
            try appendFmt(allocator, out, "    i32.const {d}\n", .{field_offset});
            try out.appendSlice(allocator, "    i32.add\n");
        }
        try appendLoadForPayloadType(allocator, out, field.ty);
    }
    return true;
}

fn emitManagedStructFields(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    local_name: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    decl: StructDecl,
    layout: StructLayout,
    out: *std.ArrayList(u8),
) !void {
    var field_start = start_idx;
    while (field_start < end_idx) {
        if (tokEq(tokens[field_start], ",")) {
            field_start += 1;
            continue;
        }
        if (tokens[field_start].kind != .ident) return error.NoMatchingCall;
        const assign_idx = findTopLevelToken(tokens, field_start + 1, end_idx, "=") orelse return error.NoMatchingCall;
        const field_name = publicDeclName(tokens[field_start].lexeme);
        const field_end = findStructLiteralFieldEnd(tokens, assign_idx + 1, end_idx);
        const field_ty = findStructFieldType(decl, field_name) orelse return error.NoMatchingCall;
        const field_offset = structFieldPayloadOffset(decl, field_name) orelse return error.NoMatchingCall;

        try appendFmt(allocator, out, "    local.get ${s}\n", .{local_name});
        try out.appendSlice(allocator, "    call $__do_arc_payload\n");
        try appendFmt(allocator, out, "    i32.const {d}\n", .{field_offset});
        try out.appendSlice(allocator, "    i32.add\n");
        if (!try emitExpr(allocator, tokens, assign_idx + 1, field_end, locals, ctx, field_ty, out)) return error.NoMatchingCall;
        if (isManagedStructField(layout, field_name) and isDirectManagedLocalExpr(tokens, assign_idx + 1, field_end, locals, ctx)) {
            try out.appendSlice(allocator, "    call $__do_arc_inc\n");
        }
        try appendStoreForPayloadType(allocator, out, field_ty);

        field_start = field_end;
        if (field_start < end_idx and tokEq(tokens[field_start], ",")) field_start += 1;
    }
}

fn emitStructSetAssignment(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !bool {
    if (start_idx + 6 >= end_idx) return false;
    if (tokens[start_idx].kind != .ident) return false;
    const struct_local = findStructLocal(locals.struct_locals.items, tokens[start_idx].lexeme) orelse return false;
    if (!tokEq(tokens[start_idx + 1], "=")) return false;

    var name_idx = start_idx + 2;
    if (tokEq(tokens[name_idx], "@")) {
        name_idx += 1;
        if (name_idx >= end_idx) return false;
    }
    if (!std.mem.eql(u8, tokens[name_idx].lexeme, "set")) return false;
    if (name_idx + 1 >= end_idx or !tokEq(tokens[name_idx + 1], "(")) return false;

    const open_paren = name_idx + 1;
    const args_start = open_paren + 1;
    const close_paren = findMatchingInRange(tokens, open_paren, "(", ")", end_idx) catch return false;
    if (close_paren + 1 != end_idx) return false;

    const first_end = findArgEnd(tokens, args_start, close_paren);
    if (first_end != args_start + 1 or !std.mem.eql(u8, tokens[args_start].lexeme, tokens[start_idx].lexeme)) return false;
    if (first_end >= close_paren or !tokEq(tokens[first_end], ",")) return false;
    const field_start = first_end + 1;
    const field_end = findArgEnd(tokens, field_start, close_paren);
    if (field_end != field_start + 1 or !isDotIdent(tokens[field_start].lexeme)) return false;
    if (field_end >= close_paren or !tokEq(tokens[field_end], ",")) return false;
    const value_start = field_end + 1;
    const field_name = publicDeclName(tokens[field_start].lexeme);
    const decl = findStructDecl(ctx.structs, struct_local.ty) orelse return false;
    const field_ty = findStructFieldType(decl, field_name) orelse return false;

    if (findStructLayout(ctx.struct_layouts, struct_local.ty)) |layout| {
        const field_offset = structFieldPayloadOffset(decl, field_name) orelse return false;
        try appendFmt(allocator, out, "    ;; arc-managed-struct-set name={s} field={s} offset={d}\n", .{
            tokens[start_idx].lexeme,
            field_name,
            field_offset,
        });
        if (isManagedStructField(layout, field_name)) {
            if (!try emitExpr(allocator, tokens, value_start, close_paren, locals, ctx, field_ty, out)) return error.NoMatchingCall;
            if (isDirectManagedLocalExpr(tokens, value_start, close_paren, locals, ctx)) {
                try out.appendSlice(allocator, "    call $__do_arc_inc\n");
            }
            try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
            try appendManagedStructFieldPtr(allocator, out, tokens[start_idx].lexeme, field_offset);
            try appendLoadForPayloadType(allocator, out, field_ty);
            try out.appendSlice(allocator, "    call $__do_arc_dec\n");
            try appendManagedStructFieldPtr(allocator, out, tokens[start_idx].lexeme, field_offset);
            try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
            try appendStoreForPayloadType(allocator, out, field_ty);
            return true;
        }
        try appendManagedStructFieldPtr(allocator, out, tokens[start_idx].lexeme, field_offset);
        if (!try emitExpr(allocator, tokens, value_start, close_paren, locals, ctx, field_ty, out)) return error.NoMatchingCall;
        try appendStoreForPayloadType(allocator, out, field_ty);
        return true;
    }

    if (!try emitExpr(allocator, tokens, value_start, close_paren, locals, ctx, field_ty, out)) return error.NoMatchingCall;
    try appendFmt(allocator, out, "    local.set ${s}.{s}\n", .{
        tokens[start_idx].lexeme,
        field_name,
    });
    return true;
}

fn appendManagedStructFieldPtr(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    local_name: []const u8,
    field_offset: usize,
) !void {
    try appendFmt(allocator, out, "    local.get ${s}\n", .{local_name});
    try out.appendSlice(allocator, "    call $__do_arc_payload\n");
    try appendFmt(allocator, out, "    i32.const {d}\n", .{field_offset});
    try out.appendSlice(allocator, "    i32.add\n");
}

fn emitBody(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_struct: ?[]const u8,
    loop_ctx: ?LoopControl,
    defer_ctx: ?*const DeferContext,
    return_label: ?[]const u8,
    out: *std.ArrayList(u8),
) !void {
    var i = start_idx;
    while (i < end_idx) {
        const stmt_end = findStmtEnd(tokens, i, end_idx);
        var exit_defer_storage: DeferContext = undefined;
        const exit_defer_ctx: ?*const DeferContext = if (defer_ctx) |scope| blk: {
            exit_defer_storage = .{
                .parent = scope.parent,
                .start_idx = scope.start_idx,
                .end_idx = scope.end_idx,
                .registered_end_idx = i,
            };
            break :blk &exit_defer_storage;
        } else null;

        if (isDeferStmt(tokens, i, stmt_end)) {
            // Cleanup registration only; execution happens on block exit paths.
        } else if (try emitLoopControlStmt(allocator, tokens, i, stmt_end, locals, loop_ctx, exit_defer_ctx, ctx, out)) {
            // Loop control emitted.
        } else if (try emitLoopBlock(allocator, tokens, i, stmt_end, locals, ctx, result_tys, result_struct, defer_ctx, return_label, out)) {
            // Loop block emitted.
        } else if (try emitIfBlock(allocator, tokens, i, stmt_end, locals, ctx, result_tys, result_struct, loop_ctx, defer_ctx, return_label, out)) {
            // If block emitted.
        } else if (try emitGuardReturnIf(allocator, tokens, i, stmt_end, locals, ctx, result_tys, result_struct, exit_defer_ctx, return_label, out)) {
            // Guard return emitted.
        } else if (try emitReturnStmt(allocator, tokens, i, stmt_end, locals, ctx, result_tys, result_struct, exit_defer_ctx, return_label, out)) {
            // Return emitted.
        } else if (try emitMultiResultAssignment(allocator, tokens, i, stmt_end, locals, ctx, out)) {
            // Multi-result assignment emitted.
        } else if (try emitStructSetAssignment(allocator, tokens, i, stmt_end, locals, ctx, out)) {
            // Struct field assignment emitted.
        } else if (try emitStorageAssignment(allocator, tokens, i, stmt_end, locals, ctx, out)) {
            // Storage assignment emitted.
        } else if (managedPayloadBinding(tokens, i, stmt_end) != null) {
            try emitStorageBinding(allocator, tokens, i, stmt_end, locals, ctx, out);
        } else if (storageBindingElemType(tokens, i, stmt_end) != null) {
            try emitStorageBinding(allocator, tokens, i, stmt_end, locals, ctx, out);
        } else if (typedStructBinding(tokens, i, stmt_end, ctx.structs)) |decl| {
            try emitStructBinding(allocator, tokens, i, stmt_end, locals, ctx, decl, out);
        } else if (inferredStructCtorBinding(tokens, i, stmt_end, ctx.structs)) |decl| {
            try emitStructBinding(allocator, tokens, i, stmt_end, locals, ctx, decl, out);
        } else if (try emitManagedLocalAssignment(allocator, tokens, i, stmt_end, locals, ctx, out)) {
            // Managed handle assignment emitted.
        } else if (isTypedScalarBinding(tokens, i, stmt_end)) {
            const eq_idx = findTopLevelToken(tokens, i, stmt_end, "=") orelse {
                i = stmt_end;
                continue;
            };
            const emitted = try emitExpr(allocator, tokens, eq_idx + 1, stmt_end, locals, ctx, tokens[i + 1].lexeme, out);
            if (!emitted) return error.NoMatchingCall;
            try appendFmt(allocator, out, "    local.set ${s}\n", .{tokens[i].lexeme});
        } else if (try emitInferredScalarBinding(allocator, tokens, i, stmt_end, locals, ctx, out)) {
            // Inferred scalar binding emitted.
        } else if (try emitBareUserFuncCall(allocator, tokens, i, stmt_end, locals, ctx, out)) {
            // Nil-return user function call emitted.
        } else if (try emitBareWasiHostImportCall(allocator, tokens, i, stmt_end, locals, ctx, out)) {
            // Statement-only WASI result-area call emitted.
        } else if (isHostImportCallExpr(tokens, i, stmt_end, ctx) or isWasiHostImportCallExpr(tokens, i, stmt_end, ctx)) {
            if (!try emitExpr(allocator, tokens, i, stmt_end, locals, ctx, null, out)) {
                return error.NoMatchingCall;
            }
        }
        i = stmt_end;
    }
    if (defer_ctx) |scope| {
        if (!bodyEndsWithPlainReturn(tokens, start_idx, end_idx)) {
            const normal_defer = DeferContext{
                .parent = scope.parent,
                .start_idx = scope.start_idx,
                .end_idx = scope.end_idx,
                .registered_end_idx = end_idx,
            };
            try emitDeferredCleanupsForContext(allocator, tokens, &normal_defer, locals, ctx, out);
        }
    }
}

fn isDeferStmt(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    return start_idx + 1 < end_idx and tokEq(tokens[start_idx], "defer");
}

fn emitDeferCleanupStack(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    defer_ctx: ?*const DeferContext,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!void {
    const scope = defer_ctx orelse return;
    try emitDeferredCleanupsForContext(allocator, tokens, scope, locals, ctx, out);
    try emitDeferCleanupStack(allocator, tokens, scope.parent, locals, ctx, out);
}

fn emitDeferCleanupStackThrough(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    defer_ctx: ?*const DeferContext,
    stop_ctx: *const DeferContext,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!void {
    var cursor = defer_ctx;
    while (cursor) |scope| {
        try emitDeferredCleanupsForContext(allocator, tokens, scope, locals, ctx, out);
        if (sameDeferScope(scope, stop_ctx)) return;
        cursor = scope.parent;
    }
    try emitDeferredCleanupsForContext(allocator, tokens, stop_ctx, locals, ctx, out);
}

fn sameDeferScope(a: *const DeferContext, b: *const DeferContext) bool {
    return a.start_idx == b.start_idx and a.end_idx == b.end_idx;
}

fn emitDeferredCleanupsForContext(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    defer_ctx: *const DeferContext,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!void {
    const scan_end = @min(defer_ctx.registered_end_idx, defer_ctx.end_idx);
    var items = std.ArrayList(DeferItem).empty;
    defer items.deinit(allocator);

    var i = defer_ctx.start_idx;
    while (i < scan_end) {
        const stmt_end = findStmtEnd(tokens, i, defer_ctx.end_idx);
        if (parseDeferItem(tokens, i, stmt_end)) |item| {
            try items.append(allocator, item);
        }
        i = stmt_end;
    }

    var idx = items.items.len;
    while (idx > 0) {
        idx -= 1;
        try emitDeferCleanupItem(allocator, tokens, items.items[idx], locals, ctx, out);
    }
}

fn parseDeferItem(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?DeferItem {
    if (!isDeferStmt(tokens, start_idx, end_idx)) return null;
    const body_idx = start_idx + 1;
    if (tokEq(tokens[body_idx], "{")) {
        const close_brace = findMatchingInRange(tokens, body_idx, "{", "}", end_idx) catch return null;
        return .{
            .kind = .block,
            .start_idx = body_idx,
            .end_idx = close_brace,
        };
    }
    return .{
        .kind = .call,
        .start_idx = body_idx,
        .end_idx = end_idx,
    };
}

fn emitDeferCleanupItem(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    item: DeferItem,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!void {
    switch (item.kind) {
        .call => try emitDeferCleanupCall(allocator, tokens, item.start_idx, item.end_idx, locals, ctx, out),
        .block => try emitDeferCleanupBlock(allocator, tokens, item.start_idx, item.end_idx, locals, ctx, out),
    }
}

fn emitDeferCleanupCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!void {
    const range = trimParens(tokens, start_idx, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return error.NoMatchingCall;
    if (call_head.is_intrinsic) return error.NoMatchingCall;
    try appendFmt(allocator, out, "    ;; defer-cleanup-call {s}\n", .{tokens[call_head.name_idx].lexeme});

    if (try emitBareUserFuncCall(allocator, tokens, start_idx, end_idx, locals, ctx, out)) return;
    if (try emitBareWasiHostImportCall(allocator, tokens, start_idx, end_idx, locals, ctx, out)) return;
    if (isHostImportCallExpr(tokens, start_idx, end_idx, ctx) or isWasiHostImportCallExpr(tokens, start_idx, end_idx, ctx)) {
        if (!try emitExpr(allocator, tokens, start_idx, end_idx, locals, ctx, null, out)) {
            return error.NoMatchingCall;
        }
        return;
    }
    return error.NoMatchingCall;
}

fn emitDeferCleanupBlock(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    open_brace: usize,
    close_brace: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!void {
    try out.appendSlice(allocator, "    ;; defer-cleanup-block\n");
    var cleanup_locals = LocalSet{};
    defer cleanup_locals.deinit(allocator);
    try collectBodyLocals(allocator, tokens, open_brace + 1, close_brace, ctx, &cleanup_locals);

    const no_results: []const []const u8 = &.{};
    const cleanup_defer = DeferContext{
        .parent = null,
        .start_idx = open_brace + 1,
        .end_idx = close_brace,
        .registered_end_idx = close_brace,
    };
    try out.appendSlice(allocator, "    block $defer_cleanup_exit\n");
    try emitBody(allocator, tokens, open_brace + 1, close_brace, locals, ctx, no_results, null, null, &cleanup_defer, "defer_cleanup_exit", out);
    try out.appendSlice(allocator, "    end\n");
    try emitBlockReleaseManagedLocals(allocator, &cleanup_locals, ctx, out);
}

fn emitStorageAssignment(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !bool {
    if (start_idx + 2 >= end_idx) return false;
    if (tokens[start_idx].kind != .ident) return false;
    const storage = findStorageLocal(locals.storage_locals.items, tokens[start_idx].lexeme) orelse return false;
    if (!tokEq(tokens[start_idx + 1], "=")) return false;
    const rhs_start = start_idx + 2;
    if (rhs_start < end_idx and tokens[rhs_start].kind == .string) {
        if (!std.mem.eql(u8, storage.elem_ty, "u8")) return error.NoMatchingCall;
        try emitOverwriteReleaseManagedLocal(allocator, tokens[start_idx].lexeme, out);
        try emitStorageU8StringLiteral(allocator, tokens, rhs_start, tokens[start_idx].lexeme, ctx, out);
        return true;
    }
    if (try emitStorageAggLiteral(allocator, tokens, rhs_start, end_idx, STORAGE_OVERWRITE_TMP_LOCAL, storage.elem_ty, locals, ctx, out)) {
        try emitReplaceManagedLocalFromTmp(allocator, tokens[start_idx].lexeme, out);
        return true;
    }
    if (try emitStorageHandleAssignmentExpr(allocator, tokens, rhs_start, end_idx, tokens[start_idx].lexeme, locals, ctx, out)) {
        return true;
    }
    if (!try emitStorageWriteExpr(allocator, tokens, rhs_start, end_idx, tokens[start_idx].lexeme, locals, ctx, out)) {
        return error.NoMatchingCall;
    }
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try emitReplaceManagedLocalFromTmp(allocator, tokens[start_idx].lexeme, out);
    return true;
}

fn emitMultiResultAssignment(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const eq_idx = findTopLevelToken(tokens, start_idx, end_idx, "=") orelse return false;
    if (findTopLevelToken(tokens, start_idx, eq_idx, ",") == null) return false;

    const rhs_range = trimParens(tokens, eq_idx + 1, end_idx);
    const call_head = exprCallHead(tokens, rhs_range) orelse return false;
    if (call_head.is_intrinsic) return false;
    if (findWasiHostImportForTokens(ctx, tokens, tokens[call_head.name_idx].lexeme)) |wasi_import| {
        if (try emitWasiResultUnitStatusMultiAssignment(
            allocator,
            tokens,
            start_idx,
            eq_idx,
            call_head.args_start,
            call_head.args_end,
            locals,
            ctx,
            wasi_import,
            out,
        )) {
            return true;
        }
        if (try emitWasiResultFilesizeMultiAssignment(
            allocator,
            tokens,
            start_idx,
            eq_idx,
            call_head.args_start,
            call_head.args_end,
            locals,
            ctx,
            wasi_import,
            out,
        )) {
            return true;
        }
        if (try emitWasiResultU64StreamStatusMultiAssignment(
            allocator,
            tokens,
            start_idx,
            eq_idx,
            call_head.args_start,
            call_head.args_end,
            locals,
            ctx,
            wasi_import,
            out,
        )) {
            return true;
        }
        if (try emitWasiResultDescriptorStatusMultiAssignment(
            allocator,
            tokens,
            start_idx,
            eq_idx,
            call_head.args_start,
            call_head.args_end,
            locals,
            ctx,
            wasi_import,
            out,
        )) {
            return true;
        }
        if (try emitWasiResultReadMultiAssignment(
            allocator,
            tokens,
            start_idx,
            eq_idx,
            call_head.args_start,
            call_head.args_end,
            locals,
            ctx,
            wasi_import,
            out,
        )) {
            return true;
        }
        return try emitWasiResultListU8StatusMultiAssignment(
            allocator,
            tokens,
            start_idx,
            eq_idx,
            call_head.args_start,
            call_head.args_end,
            locals,
            ctx,
            wasi_import,
            out,
        );
    }
    const func = findFuncDeclForCall(tokens, call_head.args_start, call_head.args_end, locals, ctx, tokens[call_head.name_idx].lexeme) orelse return false;
    if (func.results.len <= 1) return false;

    var lhs_names = std.ArrayList([]const u8).empty;
    defer lhs_names.deinit(allocator);
    var lhs_types = std.ArrayList([]const u8).empty;
    defer lhs_types.deinit(allocator);

    var lhs_start = start_idx;
    var result_idx: usize = 0;
    while (lhs_start < eq_idx) {
        if (result_idx >= func.results.len) return error.NoMatchingCall;
        const lhs_end = findArgEnd(tokens, lhs_start, eq_idx);
        if (lhs_end != lhs_start + 1 or tokens[lhs_start].kind != .ident) return error.NoMatchingCall;
        const local_ty = findLocalType(locals.locals.items, tokens[lhs_start].lexeme) orelse return error.NoMatchingCall;
        if (!isCoreWasmScalar(local_ty) and !isManagedLocalType(local_ty, ctx)) return error.NoMatchingCall;
        if (!isCoreWasmScalar(func.results[result_idx]) and !isManagedLocalType(func.results[result_idx], ctx)) return error.NoMatchingCall;
        if (!std.mem.eql(u8, local_ty, func.results[result_idx])) return error.NoMatchingCall;
        try lhs_names.append(allocator, tokens[lhs_start].lexeme);
        try lhs_types.append(allocator, local_ty);

        result_idx += 1;
        lhs_start = lhs_end;
        if (lhs_start < eq_idx and tokEq(tokens[lhs_start], ",")) lhs_start += 1;
    }
    if (result_idx != func.results.len) return error.NoMatchingCall;

    if (!try emitUserFuncCall(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, out)) {
        return error.NoMatchingCall;
    }

    var i = lhs_names.items.len;
    while (i > 0) {
        i -= 1;
        if (isManagedLocalType(lhs_types.items[i], ctx)) {
            try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
            try emitReplaceManagedLocalFromTmp(allocator, lhs_names.items[i], out);
        } else {
            try appendFmt(allocator, out, "    local.set ${s}\n", .{lhs_names.items[i]});
        }
    }
    return true;
}

fn multiResultAssignmentNeedsManagedTmp(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) bool {
    const eq_idx = findTopLevelToken(tokens, start_idx, end_idx, "=") orelse return false;
    if (findTopLevelToken(tokens, start_idx, eq_idx, ",") == null) return false;

    const rhs_range = trimParens(tokens, eq_idx + 1, end_idx);
    const call_head = exprCallHead(tokens, rhs_range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = findFuncDeclForCall(tokens, call_head.args_start, call_head.args_end, locals, ctx, tokens[call_head.name_idx].lexeme) orelse return false;
    if (func.results.len <= 1) return false;

    var lhs_start = start_idx;
    var result_idx: usize = 0;
    while (lhs_start < eq_idx) {
        if (result_idx >= func.results.len) return false;
        const lhs_end = findArgEnd(tokens, lhs_start, eq_idx);
        if (lhs_end != lhs_start + 1 or tokens[lhs_start].kind != .ident) return false;
        const local_ty = findLocalType(locals.locals.items, tokens[lhs_start].lexeme) orelse return false;
        if (isManagedLocalType(local_ty, ctx)) return true;

        result_idx += 1;
        lhs_start = lhs_end;
        if (lhs_start < eq_idx and tokEq(tokens[lhs_start], ",")) lhs_start += 1;
    }
    return false;
}

fn emitStorageHandleAssignmentExpr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    target_name: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (end_idx == start_idx + 1 and tokens[start_idx].kind == .ident) {
        if (std.mem.eql(u8, tokens[start_idx].lexeme, target_name)) return true;
    }
    const expected_ty = findLocalType(locals.locals.items, target_name) orelse return false;
    if (!try emitStorageHandleBindingExpr(allocator, tokens, start_idx, end_idx, expected_ty, locals, ctx, out)) return false;
    if (isDirectManagedLocalExpr(tokens, start_idx, end_idx, locals, ctx)) {
        try out.appendSlice(allocator, "    call $__do_arc_inc\n");
    }
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try emitReplaceManagedLocalFromTmp(allocator, target_name, out);
    return true;
}

fn emitReplaceManagedLocalFromTmp(
    allocator: std.mem.Allocator,
    name: []const u8,
    out: *std.ArrayList(u8),
) !void {
    try appendFmt(allocator, out, "    ;; arc-overwrite-release {s}\n", .{name});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{name});
    try out.appendSlice(allocator, "    i32.ne\n");
    try out.appendSlice(allocator, "    if\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{name});
    try out.appendSlice(allocator, "      call $__do_arc_dec\n");
    try out.appendSlice(allocator, "    end\n");
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try appendFmt(allocator, out, "    local.set ${s}\n", .{name});
}

fn emitOverwriteReleaseManagedLocal(
    allocator: std.mem.Allocator,
    name: []const u8,
    out: *std.ArrayList(u8),
) !void {
    try appendFmt(allocator, out, "    ;; arc-overwrite-release {s}\n", .{name});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{name});
    try out.appendSlice(allocator, "    call $__do_arc_dec\n");
}

fn emitManagedLocalAssignment(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (!isManagedLocalAssignmentStmt(tokens, start_idx, end_idx, locals, ctx)) return false;
    const target_name = tokens[start_idx].lexeme;
    const target_ty = findLocalType(locals.locals.items, target_name) orelse return false;
    const rhs_start = start_idx + 2;

    if (end_idx == rhs_start + 1 and tokens[rhs_start].kind == .ident) {
        if (std.mem.eql(u8, tokens[rhs_start].lexeme, target_name)) return true;
    }

    if (!try emitExpr(allocator, tokens, rhs_start, end_idx, locals, ctx, target_ty, out)) {
        return error.NoMatchingCall;
    }
    if (isDirectManagedLocalExpr(tokens, rhs_start, end_idx, locals, ctx)) {
        try out.appendSlice(allocator, "    call $__do_arc_inc\n");
    }
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try emitReplaceManagedLocalFromTmp(allocator, target_name, out);
    return true;
}

fn emitInferredScalarBinding(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const ty = inferredScalarBindingType(tokens, start_idx, end_idx, locals, ctx) orelse return false;
    if (!try emitExpr(allocator, tokens, start_idx + 2, end_idx, locals, ctx, ty, out)) {
        return error.NoMatchingCall;
    }
    try appendFmt(allocator, out, "    local.set ${s}\n", .{tokens[start_idx].lexeme});
    return true;
}

fn emitExpr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    expected_ty: ?[]const u8,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.start >= range.end) return false;

    if (range.end == range.start + 1) {
        const tok = tokens[range.start];
        if (tok.kind == .string) {
            const ty = expected_ty orelse return false;
            if (!std.mem.eql(u8, ty, "text") and storageElemTypeFromName(ty) == null) return false;
            const elem_ty = managedPayloadElemTypeFromName(ty) orelse return false;
            if (!std.mem.eql(u8, elem_ty, "u8")) return false;
            try emitStorageU8StringLiteralValue(allocator, tokens, range.start, ctx, out);
            return true;
        }
        if (tok.kind == .number) {
            try emitNumberConst(allocator, out, tok.lexeme, expected_ty orelse "i32");
            return true;
        }
        if (tokEq(tok, "nil")) {
            const ty = expected_ty orelse return false;
            if (!isErrorLikeType(tokens, ty)) return false;
            try out.appendSlice(allocator, "    i32.const 0\n");
            return true;
        }
        if (tok.kind == .ident) {
            if (expected_ty) |ty| {
                if (errorEnumBranchValue(tokens, ty, tok.lexeme)) |value| {
                    try appendFmt(allocator, out, "    i32.const {d}\n", .{value});
                    return true;
                }
            }
        }
        if (tok.kind == .ident and std.mem.eql(u8, tok.lexeme, "true")) {
            try out.appendSlice(allocator, "    i32.const 1\n");
            return true;
        }
        if (tok.kind == .ident and std.mem.eql(u8, tok.lexeme, "false")) {
            try out.appendSlice(allocator, "    i32.const 0\n");
            return true;
        }
        if (tok.kind == .ident) {
            if (expected_ty) |ty| {
                if (findStructLocal(locals.struct_locals.items, tok.lexeme)) |struct_local| {
                    if (std.mem.eql(u8, struct_local.ty, ty) and findStructLayout(ctx.struct_layouts, ty) == null) {
                        const decl = findStructDecl(ctx.structs, ty) orelse return false;
                        for (decl.fields) |field| {
                            try appendFmt(allocator, out, "    local.get ${s}.{s}\n", .{
                                tok.lexeme,
                                publicDeclName(field.name),
                            });
                        }
                        return true;
                    }
                }
            }
        }
        if (tok.kind == .ident and hasLocal(locals.locals.items, tok.lexeme)) {
            try appendFmt(allocator, out, "    local.get ${s}\n", .{tok.lexeme});
            return true;
        }
        return false;
    }

    const call_head = exprCallHead(tokens, range) orelse return false;
    const call_name = tokens[call_head.name_idx].lexeme;

    if (call_head.is_intrinsic) {
        if (shouldEmitBoolSpecialCall(call_name, expected_ty, tokens, call_head.args_start, call_head.args_end, locals, ctx)) {
            return try emitBoolSpecialCall(allocator, tokens, call_head.args_start, call_head.args_end, call_name, locals, ctx, out);
        }

        if (scalarConvertResultType(call_name)) |target_ty| {
            return try emitScalarConvertCall(allocator, tokens, call_head.args_start, call_head.args_end, target_ty, locals, ctx, out);
        }

        if (isNumericCoreFuncName(call_name)) {
            const op_ty = expected_ty orelse inferExprType(tokens, call_head.args_start, findArgEnd(tokens, call_head.args_start, call_head.args_end), locals, ctx) orelse "i32";
            const op = numericWasmOp(call_name, op_ty) orelse return false;
            var arg_start = call_head.args_start;
            var emitted = false;
            while (arg_start < call_head.args_end) {
                const arg_end = findArgEnd(tokens, arg_start, call_head.args_end);
                if (!try emitExpr(allocator, tokens, arg_start, arg_end, locals, ctx, op_ty, out)) {
                    return false;
                }
                if (emitted) try appendFmt(allocator, out, "    {s}\n", .{op});
                emitted = true;
                arg_start = arg_end;
                if (arg_start < call_head.args_end and tokEq(tokens[arg_start], ",")) arg_start += 1;
            }
            return emitted;
        }

        if (isBitwiseCoreFuncName(call_name)) {
            const op_ty = expected_ty orelse inferExprType(tokens, call_head.args_start, findArgEnd(tokens, call_head.args_start, call_head.args_end), locals, ctx) orelse "i32";
            if (!isCoreIntegerScalar(op_ty)) return false;
            const op = bitwiseWasmOp(call_name, op_ty) orelse return false;
            const first_end = findArgEnd(tokens, call_head.args_start, call_head.args_end);
            if (!try emitExpr(allocator, tokens, call_head.args_start, first_end, locals, ctx, op_ty, out)) return false;
            if (first_end >= call_head.args_end or !tokEq(tokens[first_end], ",")) return false;
            const second_start = first_end + 1;
            const second_end = findArgEnd(tokens, second_start, call_head.args_end);
            if (second_end != call_head.args_end) return false;
            if (!try emitExpr(allocator, tokens, second_start, second_end, locals, ctx, op_ty, out)) return false;
            try appendFmt(allocator, out, "    {s}\n", .{op});
            return true;
        }

        if (isCountBitsCoreFuncName(call_name)) {
            const op_ty = expected_ty orelse inferExprType(tokens, call_head.args_start, findArgEnd(tokens, call_head.args_start, call_head.args_end), locals, ctx) orelse "i32";
            if (!isCoreIntegerScalar(op_ty)) return false;
            const op = countBitsWasmOp(call_name, op_ty) orelse return false;
            const arg_end = findArgEnd(tokens, call_head.args_start, call_head.args_end);
            if (arg_end != call_head.args_end) return false;
            if (!try emitExpr(allocator, tokens, call_head.args_start, arg_end, locals, ctx, op_ty, out)) return false;
            try appendFmt(allocator, out, "    {s}\n", .{op});
            return true;
        }

        if (isNumericUnarySelectCoreFuncName(call_name)) {
            const arg_end = findArgEnd(tokens, call_head.args_start, call_head.args_end);
            if (arg_end != call_head.args_end) return false;
            return try emitNumericUnarySelectCall(allocator, tokens, call_head.args_start, arg_end, call_name, expected_ty, locals, ctx, out);
        }

        if (isNumericBinarySelectCoreFuncName(call_name)) {
            const first_end = findArgEnd(tokens, call_head.args_start, call_head.args_end);
            const op_ty = expected_ty orelse inferExprType(tokens, call_head.args_start, first_end, locals, ctx) orelse "i32";
            return try emitNumericBinarySelectCall(allocator, tokens, call_head.args_start, call_head.args_end, call_name, op_ty, locals, ctx, out);
        }

        if (isFloatUnaryCoreFuncName(call_name)) {
            const arg_end = findArgEnd(tokens, call_head.args_start, call_head.args_end);
            if (arg_end != call_head.args_end) return false;
            const op_ty = expected_ty orelse inferExprType(tokens, call_head.args_start, arg_end, locals, ctx) orelse return false;
            if (!isCoreFloatScalar(op_ty)) return false;
            const op = floatUnaryWasmOp(call_name, op_ty) orelse return false;
            if (!try emitExpr(allocator, tokens, call_head.args_start, arg_end, locals, ctx, op_ty, out)) return false;
            try appendFmt(allocator, out, "    {s}\n", .{op});
            return true;
        }

        if (isFloatBinaryCoreFuncName(call_name)) {
            const first_end = findArgEnd(tokens, call_head.args_start, call_head.args_end);
            const op_ty = expected_ty orelse inferExprType(tokens, call_head.args_start, first_end, locals, ctx) orelse return false;
            if (!isCoreFloatScalar(op_ty)) return false;
            const op = floatBinaryWasmOp(call_name, op_ty) orelse return false;
            if (!try emitExpr(allocator, tokens, call_head.args_start, first_end, locals, ctx, op_ty, out)) return false;
            if (first_end >= call_head.args_end or !tokEq(tokens[first_end], ",")) return false;
            const second_start = first_end + 1;
            const second_end = findArgEnd(tokens, second_start, call_head.args_end);
            if (second_end != call_head.args_end) return false;
            if (!try emitExpr(allocator, tokens, second_start, second_end, locals, ctx, op_ty, out)) return false;
            try appendFmt(allocator, out, "    {s}\n", .{op});
            return true;
        }

        if (isComparisonCoreFuncName(call_name)) {
            const cmp_ty = inferExprType(tokens, call_head.args_start, findArgEnd(tokens, call_head.args_start, call_head.args_end), locals, ctx) orelse "i32";
            const op = comparisonWasmOp(call_name, cmp_ty) orelse return false;
            var arg_start = call_head.args_start;
            var emitted_count: usize = 0;
            while (arg_start < call_head.args_end) {
                const arg_end = findArgEnd(tokens, arg_start, call_head.args_end);
                if (!try emitExpr(allocator, tokens, arg_start, arg_end, locals, ctx, cmp_ty, out)) {
                    return false;
                }
                emitted_count += 1;
                arg_start = arg_end;
                if (arg_start < call_head.args_end and tokEq(tokens[arg_start], ",")) arg_start += 1;
            }
            if (emitted_count == 2) {
                try appendFmt(allocator, out, "    {s}\n", .{op});
                return true;
            }
            return false;
        }

        if (std.mem.eql(u8, call_name, "len")) {
            return try emitLenCall(allocator, tokens, call_head.args_start, call_head.args_end, locals, out);
        }
        if (std.mem.eql(u8, call_name, "get")) {
            return try emitGetCall(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, out);
        }
        if (isMemoryLoadName(call_name)) {
            return try emitMemoryLoadCall(allocator, tokens, call_head.args_start, call_head.args_end, call_name, locals, ctx, out);
        }

        return false;
    }

    if (isCoreWasmCallName(call_name)) return false;

    if (findFuncDeclForCall(tokens, call_head.args_start, call_head.args_end, locals, ctx, call_name)) |func| {
        return try emitUserFuncCall(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, out);
    }

    if (findWasiHostImportForTokens(ctx, tokens, call_name)) |wasi_import| {
        return try emitWasiHostImportExpr(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, wasi_import, false, out);
    }

    const host_import = findHostImportForTokens(ctx.host_imports, tokens, call_name) orelse return false;
    var arg_start = call_head.args_start;
    var param_idx: usize = 0;
    while (arg_start < call_head.args_end) {
        const arg_end = findArgEnd(tokens, arg_start, call_head.args_end);
        if (stringLiteralArgLexeme(tokens, arg_start, arg_end)) |lexeme| {
            if (!hostParamIsPtrLen(host_import, param_idx)) return error.NoMatchingCall;
            const data = ctx.string_data.find(lexeme) orelse return error.NoMatchingCall;
            try appendFmt(allocator, out, "    i32.const {d}\n", .{data.ptr});
            try appendFmt(allocator, out, "    i32.const {d}\n", .{data.bytes.len});
            param_idx += 2;
        } else if (try emitStoragePtrLenHostArg(allocator, tokens, arg_start, arg_end, locals, host_import, param_idx, out)) {
            param_idx += 2;
        } else {
            const param_ty = if (param_idx < host_import.params.len) host_import.params[param_idx] else null;
            if (!try emitExpr(allocator, tokens, arg_start, arg_end, locals, ctx, param_ty, out)) {
                return false;
            }
            param_idx += 1;
        }
        arg_start = arg_end;
        if (arg_start < call_head.args_end and tokEq(tokens[arg_start], ",")) arg_start += 1;
    }
    if (param_idx != host_import.params.len) return error.NoMatchingCall;
    try appendFmt(allocator, out, "    call ${s}\n", .{host_import.alias});
    return true;
}

fn emitNumericUnarySelectCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    arg_start: usize,
    arg_end: usize,
    call_name: []const u8,
    expected_ty: ?[]const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (!std.mem.eql(u8, call_name, "abs")) return false;
    const source_ty = inferExprType(tokens, arg_start, arg_end, locals, ctx) orelse absSourceTypeFromResult(expected_ty) orelse "i32";
    const result_ty = absResultType(source_ty) orelse return false;
    if (expected_ty) |expected| {
        if (!std.mem.eql(u8, result_ty, expected)) return false;
    }
    if (isCoreFloatScalar(source_ty)) {
        const op = floatUnaryWasmOp(call_name, source_ty) orelse return false;
        if (!try emitExpr(allocator, tokens, arg_start, arg_end, locals, ctx, source_ty, out)) return false;
        try appendFmt(allocator, out, "    {s}\n", .{op});
        return true;
    }
    if (!isCoreIntegerScalar(source_ty) or isUnsignedScalar(source_ty)) return false;

    const tmp = numericSelectLeftTmp(source_ty);
    const wt = wasmType(source_ty);
    const cmp = comparisonWasmOp("lt", source_ty) orelse return false;
    try appendFmt(allocator, out, "    {s}.const 0\n", .{wt});
    if (!try emitExpr(allocator, tokens, arg_start, arg_end, locals, ctx, source_ty, out)) return false;
    try appendFmt(allocator, out, "    local.tee ${s}\n", .{tmp});
    try appendFmt(allocator, out, "    {s}.sub\n", .{wt});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{tmp});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{tmp});
    try appendFmt(allocator, out, "    {s}.const 0\n", .{wt});
    try appendFmt(allocator, out, "    {s}\n", .{cmp});
    try out.appendSlice(allocator, "    select\n");
    return true;
}

fn emitNumericBinarySelectCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    call_name: []const u8,
    op_ty: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const first_end = findArgEnd(tokens, args_start, args_end);
    if (first_end >= args_end or !tokEq(tokens[first_end], ",")) return false;

    if (isCoreFloatScalar(op_ty)) {
        const op = floatBinaryWasmOp(call_name, op_ty) orelse return false;
        if (!try emitExpr(allocator, tokens, args_start, first_end, locals, ctx, op_ty, out)) return false;
        var arg_start = first_end + 1;
        var emitted_count: usize = 1;
        while (arg_start < args_end) {
            const arg_end = findArgEnd(tokens, arg_start, args_end);
            if (!try emitExpr(allocator, tokens, arg_start, arg_end, locals, ctx, op_ty, out)) return false;
            try appendFmt(allocator, out, "    {s}\n", .{op});
            emitted_count += 1;
            arg_start = arg_end;
            if (arg_start < args_end and tokEq(tokens[arg_start], ",")) arg_start += 1;
        }
        if (emitted_count < 2) return false;
        return true;
    }
    if (!isCoreIntegerScalar(op_ty)) return false;

    const temps = numericSelectTemps(op_ty);
    const cmp_name = if (std.mem.eql(u8, call_name, "min")) "lt" else if (std.mem.eql(u8, call_name, "max")) "gt" else return false;
    const cmp = comparisonWasmOp(cmp_name, op_ty) orelse return false;
    if (!try emitExpr(allocator, tokens, args_start, first_end, locals, ctx, op_ty, out)) return false;
    try appendFmt(allocator, out, "    local.set ${s}\n", .{temps.left});
    var arg_start = first_end + 1;
    var emitted_count: usize = 1;
    while (arg_start < args_end) {
        const arg_end = findArgEnd(tokens, arg_start, args_end);
        if (!try emitExpr(allocator, tokens, arg_start, arg_end, locals, ctx, op_ty, out)) return false;
        try appendFmt(allocator, out, "    local.set ${s}\n", .{temps.right});
        try appendNumericSelectFromTemps(allocator, out, temps, cmp);
        emitted_count += 1;
        arg_start = arg_end;
        if (arg_start < args_end) {
            if (!tokEq(tokens[arg_start], ",")) return false;
            arg_start += 1;
            if (arg_start < args_end) {
                try appendFmt(allocator, out, "    local.set ${s}\n", .{temps.left});
            }
        }
    }
    if (emitted_count < 2) return false;
    return true;
}

fn appendNumericSelectFromTemps(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    temps: NumericSelectTemps,
    cmp: []const u8,
) !void {
    try appendFmt(allocator, out, "    local.get ${s}\n", .{temps.left});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{temps.right});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{temps.left});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{temps.right});
    try appendFmt(allocator, out, "    {s}\n", .{cmp});
    try out.appendSlice(allocator, "    select\n");
}

fn emitBareUserFuncCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const range = trimParens(tokens, start_idx, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = findFuncDeclForCall(tokens, call_head.args_start, call_head.args_end, locals, ctx, tokens[call_head.name_idx].lexeme) orelse return false;
    if (func.results.len != 0) return false;
    if (!try emitUserFuncCall(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, out)) {
        return error.NoMatchingCall;
    }
    return true;
}

fn emitBareWasiHostImportCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const range = trimParens(tokens, start_idx, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const wasi_import = findWasiHostImportForTokens(ctx, tokens, tokens[call_head.name_idx].lexeme) orelse return false;
    const lowering = wasiLowering(wasi_import) orelse return false;
    if (!lowering.resource_drop and !lowering.result_unit_error and !lowering.result_filesize_error and !lowering.result_u64_stream_error) return false;
    return try emitWasiHostImportExpr(
        allocator,
        tokens,
        call_head.args_start,
        call_head.args_end,
        locals,
        ctx,
        wasi_import,
        true,
        out,
    );
}

fn emitStoragePtrLenHostArg(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    host_import: HostImport,
    param_idx: usize,
    out: *std.ArrayList(u8),
) !bool {
    if (!hostParamIsPtrLen(host_import, param_idx)) return false;
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.end != range.start + 1) return false;
    if (tokens[range.start].kind != .ident) return false;
    const storage = findStorageLocal(locals.storage_locals.items, tokens[range.start].lexeme) orelse return false;
    if (!std.mem.eql(u8, storage.elem_ty, "u8")) return false;

    try emitStorageDataPtr(allocator, out, tokens[range.start].lexeme);
    try emitStorageLenPtr(allocator, out, tokens[range.start].lexeme);
    try out.appendSlice(allocator, "    i32.load\n");
    return true;
}

fn emitBoolSpecialCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    name: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (std.mem.eql(u8, name, "not")) {
        const arg_end = findArgEnd(tokens, args_start, args_end);
        if (arg_end != args_end) return false;
        if (!try emitExpr(allocator, tokens, args_start, arg_end, locals, ctx, "bool", out)) return false;
        try out.appendSlice(allocator, "    i32.eqz\n");
        return true;
    }

    if (std.mem.eql(u8, name, "and")) {
        return try emitShortCircuitAnd(allocator, tokens, args_start, args_end, locals, ctx, out);
    }
    if (std.mem.eql(u8, name, "or")) {
        return try emitShortCircuitOr(allocator, tokens, args_start, args_end, locals, ctx, out);
    }
    return false;
}

fn shouldEmitBoolSpecialCall(
    name: []const u8,
    expected_ty: ?[]const u8,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) bool {
    if (!isBoolSpecialFuncName(name)) return false;
    if (std.mem.eql(u8, name, "not")) return true;
    if (expected_ty) |ty| {
        if (!std.mem.eql(u8, ty, "bool")) return false;
        return shouldInferBoolSpecialCall(name, tokens, args_start, args_end, locals, ctx);
    }
    return shouldInferBoolSpecialCall(name, tokens, args_start, args_end, locals, ctx);
}

fn shouldInferBoolSpecialCall(
    name: []const u8,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) bool {
    if (!isBoolSpecialFuncName(name)) return false;
    if (std.mem.eql(u8, name, "not")) return true;
    const first_end = findArgEnd(tokens, args_start, args_end);
    if (first_end == args_start + 1 and (tokEq(tokens[args_start], "true") or tokEq(tokens[args_start], "false"))) return true;
    const first_ty = inferExprType(tokens, args_start, first_end, locals, ctx) orelse return false;
    return std.mem.eql(u8, first_ty, "bool");
}

fn emitShortCircuitAnd(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (start_idx >= end_idx) return false;

    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (!try emitExpr(allocator, tokens, start_idx, first_end, locals, ctx, "bool", out)) return false;
    if (first_end == end_idx) return true;
    if (!tokEq(tokens[first_end], ",")) return false;

    try out.appendSlice(allocator, "    if (result i32)\n");
    if (!try emitShortCircuitAnd(allocator, tokens, first_end + 1, end_idx, locals, ctx, out)) return false;
    try out.appendSlice(allocator, "    else\n");
    try out.appendSlice(allocator, "    i32.const 0\n");
    try out.appendSlice(allocator, "    end\n");
    return true;
}

fn emitShortCircuitOr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (start_idx >= end_idx) return false;

    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (!try emitExpr(allocator, tokens, start_idx, first_end, locals, ctx, "bool", out)) return false;
    if (first_end == end_idx) return true;
    if (!tokEq(tokens[first_end], ",")) return false;

    try out.appendSlice(allocator, "    if (result i32)\n");
    try out.appendSlice(allocator, "    i32.const 1\n");
    try out.appendSlice(allocator, "    else\n");
    if (!try emitShortCircuitOr(allocator, tokens, first_end + 1, end_idx, locals, ctx, out)) return false;
    try out.appendSlice(allocator, "    end\n");
    return true;
}

fn collectEnvHostImports(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    out: *std.ArrayList(HostImport),
) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!isLineStart(tokens, i)) continue;
        if (!isEnvHostImportStart(tokens, i)) continue;

        const line_end = findLineEnd(tokens, i);
        const import = try parseEnvHostImport(allocator, tokens, i, line_end);
        errdefer allocator.free(import.params);
        try out.append(allocator, import);
        i = line_end - 1;
    }
}

fn collectEnvHostImportsFromModules(
    allocator: std.mem.Allocator,
    modules: []const imports.ModuleRecord,
    entry_tokens: []const lexer.Token,
    out: *std.ArrayList(HostImport),
) !void {
    for (modules, 0..) |module, module_idx| {
        if (moduleTokensEqual(module.tokens, entry_tokens)) continue;

        var module_imports = std.ArrayList(HostImport).empty;
        defer {
            freeHostImports(allocator, module_imports.items);
            module_imports.deinit(allocator);
        }
        try collectEnvHostImports(allocator, module.tokens, &module_imports);
        for (module_imports.items) |*host_import| {
            if (findHostImportForTokens(out.items, module.tokens, host_import.source_alias) != null) continue;
            const emit_alias = try moduleScopedSymbolName(allocator, module_idx, host_import.source_alias);
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

fn parseEnvHostImport(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    line_end: usize,
) !HostImport {
    const alias = publicDeclName(tokens[start_idx].lexeme);
    const field = stringTokenBody(tokens[start_idx + 5].lexeme) orelse return error.InvalidImportDecl;
    const comma_idx = findTopLevelToken(tokens, start_idx + 6, line_end - 1, ",") orelse return error.InvalidImportDecl;
    const open_idx = comma_idx + 1;
    const close_idx = try findMatchingInRange(tokens, open_idx, "(", ")", line_end);
    if (close_idx + 1 >= line_end or !tokEq(tokens[close_idx + 1], "-")) return error.InvalidImportDecl;
    if (close_idx + 2 >= line_end or !tokEq(tokens[close_idx + 2], ">")) return error.InvalidImportDecl;

    var params = std.ArrayList([]const u8).empty;
    errdefer params.deinit(allocator);

    var i = open_idx + 1;
    while (i < close_idx) {
        if (tokEq(tokens[i], ",")) {
            i += 1;
            continue;
        }
        try params.append(allocator, tokens[i].lexeme);
        i += 1;
        if (i < close_idx and tokEq(tokens[i], ",")) i += 1;
    }

    const result_end = findMatchingInRange(tokens, start_idx + 4, "(", ")", line_end) catch return error.InvalidImportDecl;
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

fn collectWasiHostImports(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    source: []const u8,
    out: *std.ArrayList(WasiHostImport),
) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!isLineStart(tokens, i)) continue;
        if (!isWasiHostImportStart(tokens, i)) continue;

        const line_end = findLineEnd(tokens, i);
        const import = try parseWasiHostImport(allocator, tokens, i, line_end, source);
        errdefer allocator.free(import.params);
        errdefer allocator.free(import.result);
        try out.append(allocator, import);
        i = line_end - 1;
    }
}

fn collectWasiHostImportsFromModules(
    allocator: std.mem.Allocator,
    modules: []const imports.ModuleRecord,
    entry_tokens: []const lexer.Token,
    out: *std.ArrayList(WasiHostImport),
) !void {
    for (modules) |module| {
        const source = if (moduleTokensEqual(module.tokens, entry_tokens))
            WASI_BINDING_ENTRY_SOURCE
        else
            module.path;
        try collectWasiHostImports(allocator, module.tokens, source, out);
    }
}

fn parseWasiHostImport(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    line_end: usize,
    source: []const u8,
) !WasiHostImport {
    const alias = publicDeclName(tokens[start_idx].lexeme);
    const target = stringTokenBody(tokens[start_idx + 5].lexeme) orelse return error.InvalidImportDecl;
    const comma_idx = findTopLevelToken(tokens, start_idx + 6, line_end - 1, ",") orelse return error.InvalidImportDecl;
    const close_idx = findMatchingInRange(tokens, start_idx + 4, "(", ")", line_end) catch return error.InvalidImportDecl;
    if (close_idx + 1 != line_end) return error.InvalidImportDecl;
    const open_params = comma_idx + 1;
    if (open_params >= close_idx or !tokEq(tokens[open_params], "(")) return error.InvalidImportDecl;
    const close_params = findMatchingInRange(tokens, open_params, "(", ")", close_idx) catch return error.InvalidImportDecl;
    if (close_params + 3 > close_idx or !tokEq(tokens[close_params + 1], "-") or !tokEq(tokens[close_params + 2], ">")) {
        return error.InvalidImportDecl;
    }

    const params = try compactTokenText(allocator, tokens, open_params + 1, close_params);
    errdefer allocator.free(params);
    const result = try compactTokenText(allocator, tokens, close_params + 3, close_idx);
    errdefer allocator.free(result);

    return .{
        .source = source,
        .alias = alias,
        .target = target,
        .params = params,
        .result = result,
    };
}

fn emitWasiBindings(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wasi_imports: []const WasiHostImport,
) !void {
    for (wasi_imports) |import| {
        try appendFmt(allocator, out, "  ;; wasi-bind source=\"{s}\" alias=\"{s}\" target=\"{s}\" params=\"", .{
            import.source,
            import.alias,
            import.target,
        });
        try appendDoSignatureAsWit(allocator, out, import.params);
        try out.appendSlice(allocator, "\" result=\"");
        try appendDoSignatureAsWit(allocator, out, import.result);
        try out.appendSlice(allocator, "\"\n");
    }
}

fn emitWasiCoreImports(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wasi_imports: []const WasiHostImport,
) !void {
    var seen = std.ArrayList([]const u8).empty;
    defer seen.deinit(allocator);

    for (wasi_imports) |import| {
        const lowering = wasiLowering(import) orelse continue;
        if (hasString(seen.items, import.target)) continue;
        try seen.append(allocator, import.target);

        try appendFmt(allocator, out, "  (import \"{s}\" \"{s}\" (func $", .{
            lowering.module,
            lowering.name,
        });
        try appendWasiImportSymbol(allocator, out, import.target);
        if (lowering.param != null) {
            try appendFmt(allocator, out, " (param {s})", .{lowering.param.?});
        }
        if (lowering.result != null) {
            try appendFmt(allocator, out, " (result {s})", .{lowering.result.?});
        }
        try out.appendSlice(allocator, "))\n");
    }
}

fn emitHostImports(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    host_imports: []const HostImport,
) !void {
    for (host_imports) |host_import| {
        try appendFmt(allocator, out, "  (import \"env\" \"{s}\" (func ${s}", .{ host_import.field, host_import.alias });
        if (host_import.params.len != 0) {
            try out.appendSlice(allocator, " (param");
            for (host_import.params) |param| {
                try appendFmt(allocator, out, " {s}", .{wasmType(param)});
            }
            try out.appendSlice(allocator, ")");
        }
        if (host_import.result) |result| {
            try appendFmt(allocator, out, " (result {s})", .{wasmType(result)});
        }
        try out.appendSlice(allocator, "))\n");
    }
}

fn emitStringDataMemory(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    string_data: []const StringData,
    options: EmitOptions,
) !void {
    if (options.component_core) {
        try out.appendSlice(allocator, "  (memory 1)\n");
    } else {
        try out.appendSlice(allocator, "  (memory (export \"memory\") 1)\n");
    }
    try out.appendSlice(allocator, "  (export \"cm32p2_memory\" (memory 0))\n");
    for (string_data) |data| {
        try appendFmt(allocator, out, "  (data (i32.const {d}) ", .{data.ptr});
        try appendWatStringLiteral(allocator, out, data.bytes);
        try out.appendSlice(allocator, ")\n");
    }
}

fn emitArcRuntimePrelude(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    string_data: []const StringData,
    struct_layouts: []const StructLayout,
) !void {
    const heap_base = alignedArcHeapBase(string_data);
    const release_worklist_base = heap_base - ARC_RELEASE_WORKLIST_BYTES;
    const wasi_result_area_base = release_worklist_base - WASI_RESULT_AREA_BYTES;

    try appendFmt(allocator, out, "  ;; arc-runtime block_size={d} object_header={d}\n", .{ ARC_BLOCK_SIZE, ARC_OBJECT_HEADER_BYTES });
    try appendFmt(allocator, out, "  (global $__do_heap_base i32 (i32.const {d}))\n", .{heap_base});
    try appendFmt(allocator, out, "  (global $__do_heap_cursor (mut i32) (i32.const {d}))\n", .{heap_base});
    try appendFmt(allocator, out, "  (global $__do_wasi_result_area_base i32 (i32.const {d}))\n", .{wasi_result_area_base});
    try appendFmt(allocator, out, "  (global $__do_release_worklist_base i32 (i32.const {d}))\n", .{release_worklist_base});
    try out.appendSlice(allocator,
        \\  ;; arc-runtime memory grow helper v0
        \\  (func $__do_memory_grow_to (param $end i32)
        \\    memory.size
        \\    i32.const 16
        \\    i32.shl
        \\    local.get $end
        \\    i32.lt_u
        \\    if
        \\      local.get $end
        \\      i32.const 65535
        \\      i32.add
        \\      i32.const 16
        \\      i32.shr_u
        \\      memory.size
        \\      i32.sub
        \\      memory.grow
        \\      i32.const -1
        \\      i32.eq
        \\      if
        \\        unreachable
        \\      end
        \\    end
        \\  )
        \\  (func $cm32p2_realloc (export "cm32p2_realloc") (param $old_ptr i32) (param $old_size i32) (param $align i32) (param $new_size i32) (result i32)
        \\    (local $ptr i32)
        \\    (local $copy_len i32)
        \\    local.get $new_size
        \\    i32.eqz
        \\    if
        \\      i32.const 0
        \\      return
        \\    end
        \\    global.get $__do_heap_cursor
        \\    local.get $align
        \\    i32.const 1
        \\    i32.sub
        \\    i32.add
        \\    local.get $align
        \\    i32.const 1
        \\    i32.sub
        \\    i32.const -1
        \\    i32.xor
        \\    i32.and
        \\    local.set $ptr
        \\    local.get $ptr
        \\    local.get $new_size
        \\    i32.add
        \\    call $__do_memory_grow_to
        \\    local.get $ptr
        \\    local.get $new_size
        \\    i32.add
        \\    global.set $__do_heap_cursor
        \\    local.get $old_ptr
        \\    i32.eqz
        \\    i32.eqz
        \\    if
        \\      local.get $old_size
        \\      local.set $copy_len
        \\      local.get $new_size
        \\      local.get $old_size
        \\      i32.lt_u
        \\      if
        \\        local.get $new_size
        \\        local.set $copy_len
        \\      end
        \\      local.get $ptr
        \\      local.get $old_ptr
        \\      local.get $copy_len
        \\      memory.copy
        \\    end
        \\    local.get $ptr
        \\  )
        \\  (func $cm32p2_initialize (export "cm32p2_initialize"))
        \\  (func $__do_wasi_list_u8_to_storage (param $ptr i32) (param $len i32) (result i32)
        \\    (local $object i32)
        \\    local.get $len
        \\    i32.const 8
        \\    i32.add
        \\    i32.const 1
        \\    call $__do_arc_alloc
        \\    local.set $object
        \\    local.get $object
        \\    call $__do_arc_payload
        \\    local.get $len
        \\    i32.store
        \\    local.get $object
        \\    call $__do_arc_payload
        \\    i32.const 4
        \\    i32.add
        \\    local.get $len
        \\    i32.store
        \\    local.get $object
        \\    call $__do_arc_payload
        \\    i32.const 8
        \\    i32.add
        \\    local.get $ptr
        \\    local.get $len
        \\    memory.copy
        \\    local.get $object
        \\  )
        \\  ;; arc-runtime free span list v1
        \\  (global $__do_free_span_head (mut i32) (i32.const -1))
        \\  (func $__do_free_span_push (param $block i32)
        \\    local.get $block
        \\    i32.const 8
        \\    i32.add
        \\    global.get $__do_free_span_head
        \\    i32.store
        \\    local.get $block
        \\    global.set $__do_free_span_head
        \\  )
        \\  (func $__do_free_span_find (param $required_span i32) (result i32)
        \\    (local $block i32)
        \\    global.get $__do_free_span_head
        \\    local.set $block
        \\    block $not_found
        \\      loop $scan
        \\        local.get $block
        \\        i32.const -1
        \\        i32.eq
        \\        br_if $not_found
        \\        local.get $block
        \\        i32.load8_u
        \\        i32.eqz
        \\        local.get $block
        \\        i32.const 4
        \\        i32.add
        \\        i32.load
        \\        local.get $required_span
        \\        i32.ge_u
        \\        i32.and
        \\        if
        \\          local.get $block
        \\          return
        \\        end
        \\        local.get $block
        \\        i32.const 8
        \\        i32.add
        \\        i32.load
        \\        local.set $block
        \\        br $scan
        \\      end
        \\    end
        \\    i32.const -1
        \\  )
        \\  ;; arc-runtime free span unlink v1
        \\  (func $__do_free_span_unlink (param $target i32)
        \\    (local $prev i32)
        \\    (local $block i32)
        \\    i32.const -1
        \\    local.set $prev
        \\    global.get $__do_free_span_head
        \\    local.set $block
        \\    block $done
        \\      loop $scan
        \\        local.get $block
        \\        i32.const -1
        \\        i32.eq
        \\        br_if $done
        \\        local.get $block
        \\        local.get $target
        \\        i32.eq
        \\        if
        \\          local.get $prev
        \\          i32.const -1
        \\          i32.eq
        \\          if
        \\            local.get $block
        \\            i32.const 8
        \\            i32.add
        \\            i32.load
        \\            global.set $__do_free_span_head
        \\          else
        \\            local.get $prev
        \\            i32.const 8
        \\            i32.add
        \\            local.get $block
        \\            i32.const 8
        \\            i32.add
        \\            i32.load
        \\            i32.store
        \\          end
        \\          return
        \\        end
        \\        local.get $block
        \\        local.set $prev
        \\        local.get $block
        \\        i32.const 8
        \\        i32.add
        \\        i32.load
        \\        local.set $block
        \\        br $scan
        \\      end
        \\    end
        \\  )
        \\  ;; arc-runtime free span split v1
        \\  (func $__do_free_span_split_tail (param $block i32) (param $used_span i32)
        \\    (local $original_span i32)
        \\    (local $tail_block i32)
        \\    local.get $block
        \\    i32.const 4
        \\    i32.add
        \\    i32.load
        \\    local.set $original_span
        \\    local.get $original_span
        \\    local.get $used_span
        \\    i32.le_u
        \\    if
        \\      return
        \\    end
        \\    local.get $block
        \\    local.get $used_span
        \\    i32.const 1024
        \\    i32.mul
        \\    i32.add
        \\    local.set $tail_block
        \\    local.get $tail_block
        \\    i32.const 0
        \\    i32.store8
        \\    local.get $tail_block
        \\    i32.const 4
        \\    i32.add
        \\    local.get $original_span
        \\    local.get $used_span
        \\    i32.sub
        \\    i32.store
        \\    local.get $tail_block
        \\    i32.const 8
        \\    i32.add
        \\    i32.const 0
        \\    i32.store
        \\    local.get $tail_block
        \\    call $__do_free_span_push
        \\    local.get $block
        \\    i32.const 4
        \\    i32.add
        \\    local.get $used_span
        \\    i32.store
        \\  )
        \\  ;; arc-runtime free span merge v1
        \\  (func $__do_free_span_merge_neighbors (param $block i32) (result i32)
        \\    (local $candidate i32)
        \\    (local $block_span i32)
        \\    (local $candidate_span i32)
        \\    (local $block_end i32)
        \\    (local $candidate_end i32)
        \\    block $done
        \\      loop $restart
        \\        local.get $block
        \\        i32.const 4
        \\        i32.add
        \\        i32.load
        \\        local.set $block_span
        \\        local.get $block
        \\        local.get $block_span
        \\        i32.const 1024
        \\        i32.mul
        \\        i32.add
        \\        local.set $block_end
        \\        global.get $__do_free_span_head
        \\        local.set $candidate
        \\        block $scan_done
        \\          loop $scan
        \\            local.get $candidate
        \\            i32.const -1
        \\            i32.eq
        \\            br_if $scan_done
        \\            local.get $candidate
        \\            local.get $block
        \\            i32.eq
        \\            if
        \\              local.get $candidate
        \\              i32.const 8
        \\              i32.add
        \\              i32.load
        \\              local.set $candidate
        \\              br $scan
        \\            end
        \\            local.get $candidate
        \\            i32.load8_u
        \\            i32.eqz
        \\            if
        \\              local.get $candidate
        \\              i32.const 4
        \\              i32.add
        \\              i32.load
        \\              local.set $candidate_span
        \\              local.get $candidate
        \\              local.get $candidate_span
        \\              i32.const 1024
        \\              i32.mul
        \\              i32.add
        \\              local.set $candidate_end
        \\              local.get $block_end
        \\              local.get $candidate
        \\              i32.eq
        \\              if
        \\                local.get $candidate
        \\                call $__do_free_span_unlink
        \\                local.get $block
        \\                i32.const 4
        \\                i32.add
        \\                local.get $block_span
        \\                local.get $candidate_span
        \\                i32.add
        \\                i32.store
        \\                br $restart
        \\              end
        \\              local.get $candidate_end
        \\              local.get $block
        \\              i32.eq
        \\              if
        \\                local.get $candidate
        \\                call $__do_free_span_unlink
        \\                local.get $candidate
        \\                i32.const 4
        \\                i32.add
        \\                local.get $candidate_span
        \\                local.get $block_span
        \\                i32.add
        \\                i32.store
        \\                local.get $block
        \\                i32.const 0
        \\                i32.store8
        \\                local.get $candidate
        \\                local.set $block
        \\                br $restart
        \\              end
        \\            end
        \\            local.get $candidate
        \\            i32.const 8
        \\            i32.add
        \\            i32.load
        \\            local.set $candidate
        \\            br $scan
        \\          end
        \\        end
        \\        br $done
        \\      end
        \\    end
        \\    local.get $block
        \\  )
        \\  ;; arc-runtime generic slot class table v1
        \\  (func $__do_slot_class_table_addr (param $slot_units i32) (result i32)
        \\    local.get $slot_units
        \\    i32.const 2
        \\    i32.shl
        \\  )
        \\  (func $__do_slot_class_table_get (param $slot_units i32) (result i32)
        \\    (local $stored i32)
        \\    ;; zero table slot means no block
        \\    local.get $slot_units
        \\    call $__do_slot_class_table_addr
        \\    i32.load
        \\    local.tee $stored
        \\    i32.eqz
        \\    if (result i32)
        \\      i32.const -1
        \\    else
        \\      local.get $stored
        \\      i32.const 1
        \\      i32.sub
        \\    end
        \\  )
        \\  (func $__do_slot_class_table_set (param $slot_units i32) (param $head i32)
        \\    local.get $slot_units
        \\    call $__do_slot_class_table_addr
        \\    local.get $head
        \\    i32.const 1
        \\    i32.add
        \\    i32.store
        \\  )
        \\  ;; arc-runtime slot class state v1
        \\  (global $__do_slot_class_4 (mut i32) (i32.const -1))
        \\  (func $__do_slot_class_head_ptr (param $slot_units i32) (result i32)
        \\    local.get $slot_units
        \\    i32.const 4
        \\    i32.eq
        \\    if (result i32)
        \\      global.get $__do_slot_class_4
        \\    else
        \\      local.get $slot_units
        \\      call $__do_slot_class_table_get
        \\    end
        \\  )
        \\  (func $__do_slot_class_set_head (param $slot_units i32) (param $head i32)
        \\    local.get $slot_units
        \\    local.get $head
        \\    call $__do_slot_class_table_set
        \\    local.get $slot_units
        \\    i32.const 4
        \\    i32.eq
        \\    if
        \\      local.get $head
        \\      global.set $__do_slot_class_4
        \\    end
        \\  )
        \\  (func $__do_slot_class_unlink_block (param $slot_units i32) (param $target i32)
        \\    (local $prev i32)
        \\    (local $block i32)
        \\    i32.const -1
        \\    local.set $prev
        \\    local.get $slot_units
        \\    call $__do_slot_class_head_ptr
        \\    local.set $block
        \\    block $done
        \\      loop $scan
        \\        local.get $block
        \\        i32.const -1
        \\        i32.eq
        \\        br_if $done
        \\        local.get $block
        \\        local.get $target
        \\        i32.eq
        \\        if
        \\          local.get $prev
        \\          i32.const -1
        \\          i32.eq
        \\          if
        \\            local.get $slot_units
        \\            local.get $block
        \\            i32.const 4
        \\            i32.add
        \\            i32.load
        \\            call $__do_slot_class_set_head
        \\          else
        \\            local.get $prev
        \\            i32.const 4
        \\            i32.add
        \\            local.get $block
        \\            i32.const 4
        \\            i32.add
        \\            i32.load
        \\            i32.store
        \\          end
        \\          return
        \\        end
        \\        local.get $block
        \\        local.set $prev
        \\        local.get $block
        \\        i32.const 4
        \\        i32.add
        \\        i32.load
        \\        local.set $block
        \\        br $scan
        \\      end
        \\    end
        \\  )
        \\  ;; arc-runtime small slot reuse v1
        \\  (func $__do_small_data_start (param $cap i32) (result i32)
        \\    i32.const 8
        \\    local.get $cap
        \\    i32.const 7
        \\    i32.add
        \\    i32.const 3
        \\    i32.shr_u
        \\    i32.add
        \\    i32.const 3
        \\    i32.add
        \\    i32.const -4
        \\    i32.and
        \\  )
        \\  (func $__do_small_find_free_slot (param $block i32) (result i32)
        \\    (local $cap i32)
        \\    (local $slot i32)
        \\    (local $byte i32)
        \\    local.get $block
        \\    i32.load8_u
        \\    local.set $cap
        \\    i32.const 0
        \\    local.set $slot
        \\    block $not_found
        \\      loop $scan
        \\        local.get $slot
        \\        local.get $cap
        \\        i32.ge_u
        \\        br_if $not_found
        \\        local.get $block
        \\        i32.const 8
        \\        i32.add
        \\        local.get $slot
        \\        i32.const 3
        \\        i32.shr_u
        \\        i32.add
        \\        i32.load8_u
        \\        local.set $byte
        \\        local.get $byte
        \\        i32.const 1
        \\        local.get $slot
        \\        i32.const 7
        \\        i32.and
        \\        i32.shl
        \\        i32.and
        \\        i32.eqz
        \\        if
        \\          local.get $slot
        \\          return
        \\        end
        \\        local.get $slot
        \\        i32.const 1
        \\        i32.add
        \\        local.set $slot
        \\        br $scan
        \\      end
        \\    end
        \\    i32.const -1
        \\  )
        \\  (func $__do_small_find_block_with_slot (param $start_block i32) (result i32)
        \\    (local $block i32)
        \\    local.get $start_block
        \\    local.set $block
        \\    block $not_found
        \\      loop $scan
        \\        local.get $block
        \\        i32.const -1
        \\        i32.eq
        \\        br_if $not_found
        \\        local.get $block
        \\        call $__do_small_find_free_slot
        \\        i32.const -1
        \\        i32.ne
        \\        if
        \\          local.get $block
        \\          return
        \\        end
        \\        local.get $block
        \\        i32.const 4
        \\        i32.add
        \\        i32.load
        \\        local.set $block
        \\        br $scan
        \\      end
        \\    end
        \\    i32.const -1
        \\  )
        \\  (func $__do_arc_alloc_from_small (param $block i32) (param $type_id i32) (result i32)
        \\    (local $cap i32)
        \\    (local $slot i32)
        \\    (local $slot_size i32)
        \\    (local $bitmap_addr i32)
        \\    (local $mask i32)
        \\    (local $data_start i32)
        \\    (local $object i32)
        \\    local.get $block
        \\    call $__do_small_find_free_slot
        \\    local.tee $slot
        \\    i32.const -1
        \\    i32.eq
        \\    if
        \\      unreachable
        \\    end
        \\    local.get $block
        \\    i32.load8_u
        \\    local.set $cap
        \\    local.get $block
        \\    i32.const 1
        \\    i32.add
        \\    i32.load8_u
        \\    i32.const 2
        \\    i32.shl
        \\    local.set $slot_size
        \\    local.get $block
        \\    i32.const 8
        \\    i32.add
        \\    local.get $slot
        \\    i32.const 3
        \\    i32.shr_u
        \\    i32.add
        \\    local.set $bitmap_addr
        \\    i32.const 1
        \\    local.get $slot
        \\    i32.const 7
        \\    i32.and
        \\    i32.shl
        \\    local.set $mask
        \\    local.get $bitmap_addr
        \\    local.get $bitmap_addr
        \\    i32.load8_u
        \\    local.get $mask
        \\    i32.or
        \\    i32.store8
        \\    local.get $cap
        \\    call $__do_small_data_start
        \\    local.set $data_start
        \\    local.get $block
        \\    local.get $data_start
        \\    i32.add
        \\    local.get $slot
        \\    local.get $slot_size
        \\    i32.mul
        \\    i32.add
        \\    local.set $object
        \\    local.get $object
        \\    i32.const 1
        \\    i32.store
        \\    local.get $object
        \\    i32.const 4
        \\    i32.add
        \\    local.get $type_id
        \\    i32.store
        \\    local.get $object
        \\  )
        \\  ;; arc-runtime small slot release v1
        \\  (func $__do_small_block_for_object (param $object i32) (result i32)
        \\    local.get $object
        \\    i32.const -1024
        \\    i32.and
        \\  )
        \\  (func $__do_small_slot_for_object (param $object i32) (result i32)
        \\    (local $block i32)
        \\    (local $cap i32)
        \\    (local $data_start i32)
        \\    (local $slot_size i32)
        \\    local.get $object
        \\    call $__do_small_block_for_object
        \\    local.set $block
        \\    local.get $block
        \\    i32.load8_u
        \\    local.set $cap
        \\    local.get $cap
        \\    call $__do_small_data_start
        \\    local.set $data_start
        \\    local.get $block
        \\    i32.const 1
        \\    i32.add
        \\    i32.load8_u
        \\    i32.const 2
        \\    i32.shl
        \\    local.set $slot_size
        \\    local.get $object
        \\    local.get $block
        \\    i32.sub
        \\    local.get $data_start
        \\    i32.sub
        \\    local.get $slot_size
        \\    i32.div_u
        \\  )
        \\  (func $__do_arc_release_small (param $object i32)
        \\    (local $block i32)
        \\    (local $slot i32)
        \\    (local $bitmap_addr i32)
        \\    (local $mask i32)
        \\    local.get $object
        \\    call $__do_small_block_for_object
        \\    local.tee $block
        \\    i32.load8_u
        \\    i32.const 1
        \\    i32.le_u
        \\    if
        \\      return
        \\    end
        \\    local.get $object
        \\    call $__do_small_slot_for_object
        \\    local.set $slot
        \\    local.get $block
        \\    i32.const 8
        \\    i32.add
        \\    local.get $slot
        \\    i32.const 3
        \\    i32.shr_u
        \\    i32.add
        \\    local.set $bitmap_addr
        \\    i32.const 1
        \\    local.get $slot
        \\    i32.const 7
        \\    i32.and
        \\    i32.shl
        \\    i32.const -1
        \\    i32.xor
        \\    local.set $mask
        \\    local.get $bitmap_addr
        \\    local.get $bitmap_addr
        \\    i32.load8_u
        \\    local.get $mask
        \\    i32.and
        \\    i32.store8
        \\    local.get $block
        \\    call $__do_small_is_empty
        \\    if
        \\      local.get $block
        \\      call $__do_reclaim_empty_small_block
        \\    end
        \\  )
        \\  ;; arc-runtime empty small block reclaim v1
        \\  (func $__do_small_is_empty (param $block i32) (result i32)
        \\    (local $cap i32)
        \\    (local $bitmap_bytes i32)
        \\    (local $byte_index i32)
        \\    local.get $block
        \\    i32.load8_u
        \\    local.set $cap
        \\    local.get $cap
        \\    i32.const 7
        \\    i32.add
        \\    i32.const 3
        \\    i32.shr_u
        \\    local.set $bitmap_bytes
        \\    i32.const 0
        \\    local.set $byte_index
        \\    block $empty
        \\      loop $scan
        \\        local.get $byte_index
        \\        local.get $bitmap_bytes
        \\        i32.ge_u
        \\        br_if $empty
        \\        local.get $block
        \\        i32.const 8
        \\        i32.add
        \\        local.get $byte_index
        \\        i32.add
        \\        i32.load8_u
        \\        i32.eqz
        \\        if
        \\        else
        \\          i32.const 0
        \\          return
        \\        end
        \\        local.get $byte_index
        \\        i32.const 1
        \\        i32.add
        \\        local.set $byte_index
        \\        br $scan
        \\      end
        \\    end
        \\    i32.const 1
        \\  )
        \\  (func $__do_reclaim_empty_small_block (param $block i32)
        \\    (local $slot_units i32)
        \\    local.get $block
        \\    i32.const 1
        \\    i32.add
        \\    i32.load8_u
        \\    local.set $slot_units
        \\    local.get $slot_units
        \\    local.get $block
        \\    call $__do_slot_class_unlink_block
        \\    local.get $block
        \\    i32.const 0
        \\    i32.store8
        \\    local.get $block
        \\    i32.const 4
        \\    i32.add
        \\    i32.const 1
        \\    i32.store
        \\    local.get $block
        \\    i32.const 8
        \\    i32.add
        \\    i32.const 0
        \\    i32.store
        \\    local.get $block
        \\    call $__do_free_span_merge_neighbors
        \\    call $__do_free_span_push
        \\  )
        \\  ;; arc-runtime layout table v1
        \\
    );
    try emitArcLayoutTable(allocator, out, struct_layouts);
    try out.appendSlice(allocator,
        \\  ;; arc-runtime large span release v1
        \\  (func $__do_arc_release_large (param $object i32)
        \\    (local $block i32)
        \\    (local $span_len i32)
        \\    local.get $object
        \\    call $__do_small_block_for_object
        \\    local.set $block
        \\    local.get $block
        \\    i32.const 4
        \\    i32.add
        \\    i32.load
        \\    local.set $span_len
        \\    local.get $block
        \\    i32.const 0
        \\    i32.store8
        \\    local.get $block
        \\    i32.const 4
        \\    i32.add
        \\    local.get $span_len
        \\    i32.store
        \\    local.get $block
        \\    i32.const 8
        \\    i32.add
        \\    i32.const 0
        \\    i32.store
        \\    local.get $block
        \\    call $__do_free_span_merge_neighbors
        \\    call $__do_free_span_push
        \\  )
        \\  ;; arc-runtime allocator v1
        \\  (func $__do_arc_alloc (param $payload_bytes i32) (param $type_id i32) (result i32)
        \\    (local $object_bytes i32)
        \\    local.get $payload_bytes
        \\    i32.const 8
        \\    i32.add
        \\    i32.const 3
        \\    i32.add
        \\    i32.const -4
        \\    i32.and
        \\    local.set $object_bytes
        \\    local.get $object_bytes
        \\    i32.const 1024
        \\    i32.lt_u
        \\    if (result i32)
        \\      local.get $payload_bytes
        \\      local.get $type_id
        \\      call $__do_arc_alloc_small
        \\    else
        \\      local.get $payload_bytes
        \\      local.get $type_id
        \\      call $__do_arc_alloc_large
        \\    end
        \\  )
        \\  ;; arc-runtime small block allocator v1
        \\  (func $__do_arc_alloc_small (param $payload_bytes i32) (param $type_id i32) (result i32)
        \\    (local $object_bytes i32)
        \\    (local $slot_units i32)
        \\    (local $cap i32)
        \\    (local $block i32)
        \\    (local $class_head i32)
        \\    (local $reuse_block i32)
        \\    (local $data_start i32)
        \\    local.get $payload_bytes
        \\    i32.const 8
        \\    i32.add
        \\    i32.const 3
        \\    i32.add
        \\    i32.const -4
        \\    i32.and
        \\    local.set $object_bytes
        \\    local.get $object_bytes
        \\    i32.const 2
        \\    i32.add
        \\    i32.const 2
        \\    i32.shr_u
        \\    local.set $slot_units
        \\    i32.const 1024
        \\    local.get $object_bytes
        \\    i32.div_u
        \\    local.set $cap
        \\    local.get $cap
        \\    i32.const 504
        \\    i32.gt_u
        \\    if
        \\      i32.const 504
        \\      local.set $cap
        \\    end
        \\    block $cap_done
        \\      loop $cap_scan
        \\        local.get $cap
        \\        i32.const 1
        \\        i32.le_u
        \\        br_if $cap_done
        \\        local.get $cap
        \\        call $__do_small_data_start
        \\        local.get $cap
        \\        local.get $object_bytes
        \\        i32.mul
        \\        i32.add
        \\        i32.const 1024
        \\        i32.le_u
        \\        br_if $cap_done
        \\        local.get $cap
        \\        i32.const 1
        \\        i32.sub
        \\        local.set $cap
        \\        br $cap_scan
        \\      end
        \\    end
        \\    local.get $cap
        \\    i32.const 1
        \\    i32.le_u
        \\    if (result i32)
        \\      local.get $payload_bytes
        \\      local.get $type_id
        \\      call $__do_arc_alloc_large
        \\    else
        \\      global.get $__do_heap_cursor
        \\      local.set $block
        \\      local.get $slot_units
        \\      call $__do_slot_class_head_ptr
        \\      local.set $class_head
        \\      local.get $class_head
        \\      call $__do_small_find_block_with_slot
        \\      local.tee $reuse_block
        \\      i32.const -1
        \\      i32.ne
        \\      if
        \\        local.get $reuse_block
        \\        local.get $type_id
        \\        call $__do_arc_alloc_from_small
        \\        return
        \\      end
        \\      local.get $block
        \\      i32.const 1024
        \\      i32.add
        \\      call $__do_memory_grow_to
        \\      local.get $block
        \\      local.get $cap
        \\      i32.store8
        \\      local.get $block
        \\      i32.const 1
        \\      i32.add
        \\      local.get $slot_units
        \\      i32.store8
        \\      local.get $block
        \\      i32.const 2
        \\      i32.add
        \\      i32.const 0
        \\      i32.store8
        \\      local.get $block
        \\      i32.const 3
        \\      i32.add
        \\      i32.const 0
        \\      i32.store8
        \\      local.get $block
        \\      i32.const 4
        \\      i32.add
        \\      local.get $class_head
        \\      i32.store
        \\      local.get $block
        \\      i32.const 8
        \\      i32.add
        \\      i32.const 0
        \\      i32.store8
        \\      local.get $cap
        \\      call $__do_small_data_start
        \\      local.set $data_start
        \\      local.get $block
        \\      i32.const 1024
        \\      i32.add
        \\      global.set $__do_heap_cursor
        \\      local.get $slot_units
        \\      local.get $block
        \\      call $__do_slot_class_set_head
        \\      local.get $block
        \\      local.get $type_id
        \\      call $__do_arc_alloc_from_small
        \\    end
        \\  )
        \\  ;; arc-runtime large block allocator v1
        \\  (func $__do_arc_alloc_large (param $payload_bytes i32) (param $type_id i32) (result i32)
        \\    (local $object_bytes i32)
        \\    (local $span_len i32)
        \\    (local $block i32)
        \\    (local $free_block i32)
        \\    (local $object i32)
        \\    local.get $payload_bytes
        \\    i32.const 8
        \\    i32.add
        \\    i32.const 3
        \\    i32.add
        \\    i32.const -4
        \\    i32.and
        \\    local.set $object_bytes
        \\    local.get $object_bytes
        \\    i32.const 8
        \\    i32.add
        \\    i32.const 1023
        \\    i32.add
        \\    i32.const 1024
        \\    i32.div_u
        \\    local.set $span_len
        \\    local.get $span_len
        \\    call $__do_free_span_find
        \\    local.tee $free_block
        \\    i32.const -1
        \\    i32.ne
        \\    if
        \\      local.get $free_block
        \\      call $__do_free_span_unlink
        \\      local.get $free_block
        \\      local.get $span_len
        \\      call $__do_free_span_split_tail
        \\      local.get $free_block
        \\      local.get $payload_bytes
        \\      local.get $type_id
        \\      call $__do_arc_alloc_from_large_block
        \\      return
        \\    end
        \\    global.get $__do_heap_cursor
        \\    local.set $block
        \\    local.get $block
        \\    local.get $span_len
        \\    i32.const 1024
        \\    i32.mul
        \\    i32.add
        \\    call $__do_memory_grow_to
        \\    local.get $block
        \\    i32.const 1
        \\    i32.store8
        \\    local.get $block
        \\    i32.const 4
        \\    i32.add
        \\    local.get $span_len
        \\    i32.store
        \\    local.get $block
        \\    i32.const 8
        \\    i32.add
        \\    local.set $object
        \\    local.get $block
        \\    local.get $span_len
        \\    i32.const 1024
        \\    i32.mul
        \\    i32.add
        \\    global.set $__do_heap_cursor
        \\    local.get $object
        \\    i32.const 1
        \\    i32.store
        \\    local.get $object
        \\    i32.const 4
        \\    i32.add
        \\    local.get $type_id
        \\    i32.store
        \\    local.get $object
        \\  )
        \\  (func $__do_arc_alloc_from_large_block (param $block i32) (param $payload_bytes i32) (param $type_id i32) (result i32)
        \\    (local $object i32)
        \\    local.get $block
        \\    i32.const 1
        \\    i32.store8
        \\    local.get $block
        \\    i32.const 8
        \\    i32.add
        \\    local.set $object
        \\    local.get $object
        \\    i32.const 1
        \\    i32.store
        \\    local.get $object
        \\    i32.const 4
        \\    i32.add
        \\    local.get $type_id
        \\    i32.store
        \\    local.get $object
        \\  )
        \\  ;; arc-runtime bump allocator fallback v0
        \\  (func $__do_arc_alloc_bump (param $payload_bytes i32) (param $type_id i32) (result i32)
        \\    (local $object i32)
        \\    (local $next i32)
        \\    global.get $__do_heap_cursor
        \\    local.set $object
        \\    local.get $object
        \\    i32.const 8
        \\    i32.add
        \\    local.get $payload_bytes
        \\    i32.const 3
        \\    i32.add
        \\    i32.const -4
        \\    i32.and
        \\    i32.add
        \\    local.set $next
        \\    local.get $next
        \\    call $__do_memory_grow_to
        \\    local.get $object
        \\    i32.const 1
        \\    i32.store
        \\    local.get $object
        \\    i32.const 4
        \\    i32.add
        \\    local.get $type_id
        \\    i32.store
        \\    local.get $next
        \\    global.set $__do_heap_cursor
        \\    local.get $object
        \\  )
        \\  ;; arc-runtime release worklist v1
        \\  (global $__do_release_worklist_top (mut i32) (i32.const 0))
        \\  (func $__do_release_worklist_push (param $object i32)
        \\    global.get $__do_release_worklist_top
        \\    i32.const 128
        \\    i32.ge_u
        \\    if
        \\      unreachable
        \\    end
        \\    global.get $__do_release_worklist_base
        \\    global.get $__do_release_worklist_top
        \\    i32.const 2
        \\    i32.shl
        \\    i32.add
        \\    local.get $object
        \\    i32.store
        \\    global.get $__do_release_worklist_top
        \\    i32.const 1
        \\    i32.add
        \\    global.set $__do_release_worklist_top
        \\  )
        \\  (func $__do_release_worklist_pop (result i32)
        \\    global.get $__do_release_worklist_top
        \\    i32.eqz
        \\    if (result i32)
        \\      i32.const 0
        \\    else
        \\      global.get $__do_release_worklist_top
        \\      i32.const 1
        \\      i32.sub
        \\      global.set $__do_release_worklist_top
        \\      global.get $__do_release_worklist_base
        \\      global.get $__do_release_worklist_top
        \\      i32.const 2
        \\      i32.shl
        \\      i32.add
        \\      i32.load
        \\    end
        \\  )
        \\  ;; arc-storage-managed-release
        \\  (func $__do_arc_release_storage_managed_children (param $object i32)
        \\    (local $count i32)
        \\    (local $index i32)
        \\    (local $child i32)
        \\    local.get $object
        \\    call $__do_arc_payload
        \\    i32.load
        \\    local.set $count
        \\    i32.const 0
        \\    local.set $index
        \\    block $done
        \\      loop $scan
        \\        local.get $index
        \\        local.get $count
        \\        i32.ge_u
        \\        br_if $done
        \\        local.get $object
        \\        call $__do_arc_payload
        \\        i32.const 8
        \\        i32.add
        \\        local.get $index
        \\        i32.const 4
        \\        i32.mul
        \\        i32.add
        \\        i32.load
        \\        local.tee $child
        \\        i32.eqz
        \\        if
        \\        else
        \\          local.get $child
        \\          call $__do_arc_dec_no_drain
        \\        end
        \\        local.get $index
        \\        i32.const 1
        \\        i32.add
        \\        local.set $index
        \\        br $scan
        \\      end
        \\    end
        \\  )
        \\  ;; arc-runtime managed child release v1
        \\  (func $__do_arc_release_managed_children (param $object i32)
        \\    (local $type_id i32)
        \\    (local $count i32)
        \\    (local $index i32)
        \\    (local $child i32)
        \\    local.get $object
        \\    call $__do_arc_type_id
        \\    local.set $type_id
        \\    local.get $type_id
        \\    i32.const 65535
        \\    i32.eq
        \\    if
        \\      local.get $object
        \\      call $__do_arc_release_storage_managed_children
        \\      return
        \\    end
        \\    local.get $type_id
        \\    call $__do_layout_managed_count
        \\    local.set $count
        \\    i32.const 0
        \\    local.set $index
        \\    block $done
        \\      loop $scan
        \\        local.get $index
        \\        local.get $count
        \\        i32.ge_u
        \\        br_if $done
        \\        local.get $object
        \\        call $__do_arc_payload
        \\        local.get $type_id
        \\        local.get $index
        \\        call $__do_layout_managed_offset
        \\        i32.add
        \\        i32.load
        \\        local.tee $child
        \\        i32.eqz
        \\        if
        \\        else
        \\          local.get $child
        \\          call $__do_arc_dec_no_drain
        \\        end
        \\        local.get $index
        \\        i32.const 1
        \\        i32.add
        \\        local.set $index
        \\        br $scan
        \\      end
        \\    end
        \\  )
        \\  (func $__do_arc_release (param $object i32)
        \\    local.get $object
        \\    call $__do_arc_release_managed_children
        \\    local.get $object
        \\    call $__do_small_block_for_object
        \\    i32.load8_u
        \\    i32.const 1
        \\    i32.eq
        \\    if
        \\      local.get $object
        \\      call $__do_arc_release_large
        \\    else
        \\      local.get $object
        \\      call $__do_arc_release_small
        \\    end
        \\  )
        \\  ;; arc-runtime refcount primitives v1
        \\  (func $__do_arc_inc (param $object i32) (result i32)
        \\    ;; arc-inc-zero-sentinel
        \\    local.get $object
        \\    i32.eqz
        \\    if (result i32)
        \\      i32.const 0
        \\    else
        \\      local.get $object
        \\      local.get $object
        \\      i32.load
        \\      i32.const 1
        \\      i32.add
        \\      i32.store
        \\      local.get $object
        \\    end
        \\  )
        \\  (func $__do_arc_dec_no_drain (param $object i32)
        \\    (local $next_rc i32)
        \\    ;; arc-dec-zero-sentinel
        \\    local.get $object
        \\    i32.eqz
        \\    if
        \\      return
        \\    end
        \\    local.get $object
        \\    local.get $object
        \\    i32.load
        \\    i32.const 1
        \\    i32.sub
        \\    local.tee $next_rc
        \\    i32.store
        \\    local.get $next_rc
        \\    i32.eqz
        \\    if
        \\      local.get $object
        \\      call $__do_release_worklist_push
        \\    end
        \\  )
        \\  (func $__do_arc_drain_release_worklist
        \\    (local $object i32)
        \\    block $done
        \\      loop $drain
        \\        call $__do_release_worklist_pop
        \\        local.tee $object
        \\        i32.eqz
        \\        br_if $done
        \\        local.get $object
        \\        call $__do_arc_release
        \\        br $drain
        \\      end
        \\    end
        \\  )
        \\  (func $__do_arc_dec (param $object i32)
        \\    local.get $object
        \\    call $__do_arc_dec_no_drain
        \\    call $__do_arc_drain_release_worklist
        \\  )
        \\  ;; arc-runtime object header accessors v0
        \\  (func $__do_arc_payload (param $object i32) (result i32)
        \\    local.get $object
        \\    i32.const 8
        \\    i32.add
        \\  )
        \\  (func $__do_arc_rc (param $object i32) (result i32)
        \\    local.get $object
        \\    i32.load
        \\  )
        \\  (func $__do_arc_type_id (param $object i32) (result i32)
        \\    local.get $object
        \\    i32.const 4
        \\    i32.add
        \\    i32.load
        \\  )
        \\  ;; arc-runtime storage range check v0
        \\  (func $__do_storage_check_range (param $storage i32) (param $offset i32) (param $width i32)
        \\    local.get $offset
        \\    local.get $width
        \\    i32.add
        \\    local.get $storage
        \\    call $__do_arc_payload
        \\    i32.load
        \\    i32.gt_u
        \\    if
        \\      unreachable
        \\    end
        \\  )
        \\  ;; arc-runtime storage write helpers v1
        \\  (func $__do_storage_set_u8 (param $storage i32) (param $index i32) (param $value i32) (result i32)
        \\    (local $len i32)
        \\    (local $next i32)
        \\    local.get $storage
        \\    local.get $index
        \\    i32.const 1
        \\    call $__do_storage_check_range
        \\    local.get $storage
        \\    call $__do_arc_payload
        \\    i32.load
        \\    local.set $len
        \\    local.get $storage
        \\    call $__do_arc_rc
        \\    i32.const 1
        \\    i32.eq
        \\    if
        \\      local.get $storage
        \\      call $__do_arc_payload
        \\      i32.const 8
        \\      i32.add
        \\      local.get $index
        \\      i32.add
        \\      local.get $value
        \\      i32.store8
        \\      local.get $storage
        \\      return
        \\    end
        \\    local.get $len
        \\    i32.const 8
        \\    i32.add
        \\    i32.const 1
        \\    call $__do_arc_alloc
        \\    local.set $next
        \\    local.get $next
        \\    call $__do_arc_payload
        \\    local.get $len
        \\    i32.store
        \\    local.get $next
        \\    call $__do_arc_payload
        \\    i32.const 4
        \\    i32.add
        \\    local.get $len
        \\    i32.store
        \\    local.get $next
        \\    call $__do_arc_payload
        \\    i32.const 8
        \\    i32.add
        \\    local.get $storage
        \\    call $__do_arc_payload
        \\    i32.const 8
        \\    i32.add
        \\    local.get $len
        \\    memory.copy
        \\    local.get $next
        \\    call $__do_arc_payload
        \\    i32.const 8
        \\    i32.add
        \\    local.get $index
        \\    i32.add
        \\    local.get $value
        \\    i32.store8
        \\    local.get $next
        \\  )
        \\  (func $__do_storage_put_u8 (param $storage i32) (param $value i32) (result i32)
        \\    (local $len i32)
        \\    (local $cap i32)
        \\    (local $next_len i32)
        \\    (local $next i32)
        \\    local.get $storage
        \\    call $__do_arc_payload
        \\    i32.load
        \\    local.set $len
        \\    local.get $storage
        \\    call $__do_arc_payload
        \\    i32.const 4
        \\    i32.add
        \\    i32.load
        \\    local.set $cap
        \\    local.get $len
        \\    i32.const 1
        \\    i32.add
        \\    local.set $next_len
        \\    local.get $storage
        \\    call $__do_arc_rc
        \\    i32.const 1
        \\    i32.eq
        \\    local.get $len
        \\    local.get $cap
        \\    i32.lt_u
        \\    i32.and
        \\    if
        \\      local.get $storage
        \\      call $__do_arc_payload
        \\      i32.const 8
        \\      i32.add
        \\      local.get $len
        \\      i32.add
        \\      local.get $value
        \\      i32.store8
        \\      local.get $storage
        \\      call $__do_arc_payload
        \\      local.get $next_len
        \\      i32.store
        \\      local.get $storage
        \\      return
        \\    end
        \\    local.get $next_len
        \\    i32.const 8
        \\    i32.add
        \\    i32.const 1
        \\    call $__do_arc_alloc
        \\    local.set $next
        \\    local.get $next
        \\    call $__do_arc_payload
        \\    local.get $next_len
        \\    i32.store
        \\    local.get $next
        \\    call $__do_arc_payload
        \\    i32.const 4
        \\    i32.add
        \\    local.get $next_len
        \\    i32.store
        \\    local.get $next
        \\    call $__do_arc_payload
        \\    i32.const 8
        \\    i32.add
        \\    local.get $storage
        \\    call $__do_arc_payload
        \\    i32.const 8
        \\    i32.add
        \\    local.get $len
        \\    memory.copy
        \\    local.get $next
        \\    call $__do_arc_payload
        \\    i32.const 8
        \\    i32.add
        \\    local.get $len
        \\    i32.add
        \\    local.get $value
        \\    i32.store8
        \\    local.get $next
        \\  )
        \\
    );
}

fn emitArcLayoutTable(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    struct_layouts: []const StructLayout,
) !void {
    for (struct_layouts) |layout| {
        try appendFmt(allocator, out, "  ;; arc-layout type_id={d} name={s} managed_count={d} payload_bytes={d}\n", .{
            layout.type_id,
            layout.name,
            layout.managed_fields.len,
            layout.payload_bytes,
        });
        for (layout.managed_fields, 0..) |field, index| {
            try appendFmt(allocator, out, "  ;; arc-layout-managed-offset type_id={d} index={d} offset={d} field={s}\n", .{
                layout.type_id,
                index,
                field.offset,
                field.name,
            });
        }
    }

    try out.appendSlice(allocator,
        \\  (func $__do_layout_managed_count (param $type_id i32) (result i32)
        \\    local.get $type_id
        \\    i32.const 1
        \\    i32.eq
        \\    if
        \\      i32.const 0
        \\      return
        \\    end
        \\
    );
    for (struct_layouts, 0..) |layout, index| {
        if (hasEarlierLayoutTypeId(struct_layouts[0..index], layout.type_id)) continue;
        try appendFmt(allocator, out,
            \\    local.get $type_id
            \\    i32.const {d}
            \\    i32.eq
            \\    if
            \\      i32.const {d}
            \\      return
            \\    end
            \\
        , .{ layout.type_id, layout.managed_fields.len });
    }
    try out.appendSlice(allocator,
        \\    unreachable
        \\  )
        \\  (func $__do_layout_managed_offset (param $type_id i32) (param $index i32) (result i32)
        \\    local.get $type_id
        \\    i32.const 1
        \\    i32.eq
        \\    if
        \\      unreachable
        \\    end
        \\
    );
    for (struct_layouts, 0..) |layout, index| {
        if (hasEarlierLayoutTypeId(struct_layouts[0..index], layout.type_id)) continue;
        try appendFmt(allocator, out,
            \\    local.get $type_id
            \\    i32.const {d}
            \\    i32.eq
            \\    if
            \\
        , .{layout.type_id});
        for (layout.managed_fields, 0..) |field, field_index| {
            try appendFmt(allocator, out,
                \\      local.get $index
                \\      i32.const {d}
                \\      i32.eq
                \\      if
                \\        i32.const {d}
                \\        return
                \\      end
                \\
            , .{ field_index, field.offset });
        }
        try out.appendSlice(allocator,
            \\      unreachable
            \\    end
            \\
        );
    }
    try out.appendSlice(allocator,
        \\    unreachable
        \\  )
    );
}

fn hasEarlierLayoutTypeId(layouts: []const StructLayout, type_id: usize) bool {
    for (layouts) |layout| {
        if (layout.type_id == type_id) return true;
    }
    return false;
}

fn alignedArcHeapBase(string_data: []const StringData) usize {
    var end: usize = ARC_BLOCK_SIZE;
    for (string_data) |data| {
        end = @max(end, data.ptr + data.bytes.len);
    }
    return alignUp(end + WASI_RESULT_AREA_BYTES + ARC_RELEASE_WORKLIST_BYTES, ARC_BLOCK_SIZE);
}

fn alignUp(value: usize, alignment: usize) usize {
    return ((value + alignment - 1) / alignment) * alignment;
}

fn validateHostImportBuildUses(tokens: []const lexer.Token, host_imports: []const HostImport) !void {
    if (host_imports.len == 0) return;

    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        const host_import = findHostImportForTokens(host_imports, tokens, tokens[i].lexeme) orelse continue;
        if (i + 1 >= tokens.len or !tokEq(tokens[i + 1], "(")) continue;

        const close_paren = findMatching(tokens, i + 1, "(", ")") catch return error.InvalidCallArgList;
        if (!hostCallArgsMatch(tokens, i + 2, close_paren, host_import)) return error.NoMatchingCall;
        if (isBareHostCallStatement(tokens, i, close_paren) and host_import.result != null) return error.NoMatchingCall;
        if (isTypedBindingRhsCall(tokens, i) and host_import.result == null) return error.NoMatchingCall;
        i = close_paren;
    }
}

fn validateWasiHostImportBuildUses(tokens: []const lexer.Token, wasi_imports: []const WasiHostImport) !void {
    if (wasi_imports.len == 0) return;

    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        const import = findWasiHostImport(wasi_imports, tokens[i].lexeme) orelse continue;
        if (!tokEq(tokens[i + 1], "(")) continue;
        if (wasiHostImportUseIsLowerableAtCall(tokens, i, import)) continue;
        return error.UnsupportedWasiHostImport;
    }
}

fn validateReachableWasiHostImportBuildUses(
    allocator: std.mem.Allocator,
    entry_tokens: []const lexer.Token,
    graph: *const imports.ModuleGraph,
) !void {
    const root_idx = findRootModuleIndex(graph.modules, entry_tokens) orelse return;

    var stack = std.ArrayList(ReachVisit).empty;
    defer stack.deinit(allocator);

    var visited = std.ArrayList(ReachVisit).empty;
    defer visited.deinit(allocator);

    try collectStartBodyCalls(allocator, graph.modules[root_idx].tokens, root_idx, &stack);
    try collectAllFunctionBodyCalls(allocator, graph.modules[root_idx].tokens, root_idx, &stack);
    try validateReachableWasiHostImportStack(allocator, graph, &stack, &visited);
}

fn validateReachableWasiHostImportBuildUsesFromTests(
    allocator: std.mem.Allocator,
    entry_tokens: []const lexer.Token,
    graph: *const imports.ModuleGraph,
) !void {
    const root_idx = findRootModuleIndex(graph.modules, entry_tokens) orelse return;

    var stack = std.ArrayList(ReachVisit).empty;
    defer stack.deinit(allocator);

    var visited = std.ArrayList(ReachVisit).empty;
    defer visited.deinit(allocator);

    try collectTestBodyCalls(allocator, graph.modules[root_idx].tokens, root_idx, &stack);
    try collectAllFunctionBodyCalls(allocator, graph.modules[root_idx].tokens, root_idx, &stack);
    try validateReachableWasiHostImportStack(allocator, graph, &stack, &visited);
}

fn validateReachableWasiHostImportStack(
    allocator: std.mem.Allocator,
    graph: *const imports.ModuleGraph,
    stack: *std.ArrayList(ReachVisit),
    visited: *std.ArrayList(ReachVisit),
) !void {
    while (stack.items.len != 0) {
        const visit = stack.pop().?;
        if (hasReachVisit(visited.items, visit)) continue;
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

        if (findCodegenImportByAlias(module.tokens, visit.name)) |import_ref| {
            if (findImportedModuleIndex(allocator, graph.modules, visit.module_idx, import_ref)) |child_idx| {
                try pushReachVisit(allocator, stack, .{
                    .module_idx = child_idx,
                    .name = import_ref.target,
                });
            }
            continue;
        }

        try collectFunctionBodyCalls(allocator, module.tokens, visit.module_idx, visit.name, stack);
    }
}

fn findRootModuleIndex(modules: []const imports.ModuleRecord, entry_tokens: []const lexer.Token) ?usize {
    for (modules, 0..) |module, idx| {
        if (moduleTokensEqual(module.tokens, entry_tokens)) return idx;
    }
    return null;
}

fn moduleTokensEqual(a: []const lexer.Token, b: []const lexer.Token) bool {
    return a.ptr == b.ptr and a.len == b.len;
}

fn wasiSourceForTokens(ctx: CodegenContext, tokens: []const lexer.Token) []const u8 {
    if (moduleTokensEqual(tokens, ctx.entry_tokens)) return WASI_BINDING_ENTRY_SOURCE;
    for (ctx.modules) |module| {
        if (moduleTokensEqual(tokens, module.tokens)) return module.path;
    }
    return WASI_BINDING_ENTRY_SOURCE;
}

fn findWasiHostImportForTokens(ctx: CodegenContext, tokens: []const lexer.Token, alias: []const u8) ?WasiHostImport {
    const source = wasiSourceForTokens(ctx, tokens);
    return findWasiHostImportBySource(ctx.wasi_imports, source, alias);
}

fn hasReachVisit(items: []const ReachVisit, target: ReachVisit) bool {
    for (items) |item| {
        if (item.module_idx == target.module_idx and std.mem.eql(u8, item.name, target.name)) return true;
    }
    return false;
}

fn pushReachVisit(
    allocator: std.mem.Allocator,
    stack: *std.ArrayList(ReachVisit),
    visit: ReachVisit,
) !void {
    if (isCoreWasmCallName(visit.name)) return;
    try stack.append(allocator, visit);
}

fn collectStartBodyCalls(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    module_idx: usize,
    out: *std.ArrayList(ReachVisit),
) !void {
    const start_idx = findStartFunc(tokens) orelse return;
    const close_params = findMatching(tokens, start_idx + 1, "(", ")") catch return;
    const open_body = findToken(tokens, close_params + 1, tokens.len, "{") orelse return;
    const close_body = findMatching(tokens, open_body, "{", "}") catch return;
    try collectCallNamesInRange(allocator, tokens, module_idx, open_body + 1, close_body, out);
}

fn collectAllFunctionBodyCalls(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    module_idx: usize,
    out: *std.ArrayList(ReachVisit),
) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!isUserFuncDeclStart(tokens, i)) continue;

        const close_params = findMatching(tokens, i + 1, "(", ")") catch continue;
        const open_body = findToken(tokens, close_params + 1, tokens.len, "{") orelse continue;
        const close_body = findMatching(tokens, open_body, "{", "}") catch continue;
        try collectCallNamesInRange(allocator, tokens, module_idx, open_body + 1, close_body, out);
        i = close_body;
    }
}

fn collectTestBodyCalls(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    module_idx: usize,
    out: *std.ArrayList(ReachVisit),
) !void {
    const test_decls = try test_runner.collectTopLevelTests(allocator, tokens);
    defer allocator.free(test_decls);

    for (test_decls) |decl| {
        try collectCallNamesInRange(allocator, tokens, module_idx, decl.body_start, decl.body_end, out);
    }
}

fn collectFunctionBodyCalls(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    module_idx: usize,
    func_name: []const u8,
    out: *std.ArrayList(ReachVisit),
) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, publicDeclName(tokens[i].lexeme), func_name)) continue;
        if (!tokEq(tokens[i + 1], "(")) continue;

        const close_params = findMatching(tokens, i + 1, "(", ")") catch continue;
        const open_body = findToken(tokens, close_params + 1, tokens.len, "{") orelse continue;
        const close_body = findMatching(tokens, open_body, "{", "}") catch continue;
        try collectCallNamesInRange(allocator, tokens, module_idx, open_body + 1, close_body, out);
        i = close_body;
    }
}

fn collectCallNamesInRange(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    module_idx: usize,
    start_idx: usize,
    end_idx: usize,
    out: *std.ArrayList(ReachVisit),
) !void {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (!tokEq(tokens[i + 1], "(")) continue;
        try pushReachVisit(allocator, out, .{
            .module_idx = module_idx,
            .name = tokens[i].lexeme,
            .call_idx = i,
        });
    }
}

fn wasiHostImportUseIsLowerableAtCall(
    tokens: []const lexer.Token,
    call_idx: usize,
    import: WasiHostImport,
) bool {
    const lowering = wasiLowering(import) orelse return false;
    if (lowering.result_link_at_error) return isWasiResultUnitStatusMultiAssignmentCall(tokens, call_idx);
    if (lowering.result_read_error) return isWasiResultReadMultiAssignmentCall(tokens, call_idx);
    if (lowering.result_list_u8_error) return isWasiResultListU8StatusMultiAssignmentCall(tokens, call_idx);
    return true;
}

fn isWasiResultUnitStatusMultiAssignmentCall(tokens: []const lexer.Token, call_idx: usize) bool {
    const line_start = findLineStart(tokens, call_idx);
    const line_end = findLineEnd(tokens, call_idx);
    const eq_idx = findTopLevelToken(tokens, line_start, call_idx, "=") orelse return false;

    const first_lhs_end = findArgEnd(tokens, line_start, eq_idx);
    if (first_lhs_end != line_start + 1 or tokens[line_start].kind != .ident) return false;
    if (!std.mem.eql(u8, tokens[line_start].lexeme, "_")) return false;
    if (first_lhs_end >= eq_idx or !tokEq(tokens[first_lhs_end], ",")) return false;

    const status_lhs_start = first_lhs_end + 1;
    const status_lhs_end = findArgEnd(tokens, status_lhs_start, eq_idx);
    if (status_lhs_end != status_lhs_start + 1 or status_lhs_end != eq_idx) return false;
    if (tokens[status_lhs_start].kind != .ident) return false;

    const rhs_range = trimParens(tokens, eq_idx + 1, line_end);
    const call_head = exprCallHead(tokens, rhs_range) orelse return false;
    return !call_head.is_intrinsic and call_head.name_idx == call_idx;
}

fn isWasiResultReadMultiAssignmentCall(tokens: []const lexer.Token, call_idx: usize) bool {
    const line_start = findLineStart(tokens, call_idx);
    const line_end = findLineEnd(tokens, call_idx);
    const eq_idx = findTopLevelToken(tokens, line_start, call_idx, "=") orelse return false;
    if (findTopLevelToken(tokens, line_start, eq_idx, ",") == null) return false;
    const rhs_range = trimParens(tokens, eq_idx + 1, line_end);
    const call_head = exprCallHead(tokens, rhs_range) orelse return false;
    return !call_head.is_intrinsic and call_head.name_idx == call_idx;
}

fn isWasiResultListU8StatusMultiAssignmentCall(tokens: []const lexer.Token, call_idx: usize) bool {
    const line_start = findLineStart(tokens, call_idx);
    const line_end = findLineEnd(tokens, call_idx);
    const eq_idx = findTopLevelToken(tokens, line_start, call_idx, "=") orelse return false;

    const data_lhs_end = findArgEnd(tokens, line_start, eq_idx);
    if (data_lhs_end != line_start + 1 or tokens[line_start].kind != .ident) return false;
    if (data_lhs_end >= eq_idx or !tokEq(tokens[data_lhs_end], ",")) return false;

    const status_lhs_start = data_lhs_end + 1;
    const status_lhs_end = findArgEnd(tokens, status_lhs_start, eq_idx);
    if (status_lhs_end != status_lhs_start + 1 or status_lhs_end != eq_idx) return false;
    if (tokens[status_lhs_start].kind != .ident) return false;

    const rhs_range = trimParens(tokens, eq_idx + 1, line_end);
    const call_head = exprCallHead(tokens, rhs_range) orelse return false;
    return !call_head.is_intrinsic and call_head.name_idx == call_idx;
}

fn findCodegenImportByAlias(tokens: []const lexer.Token, alias: []const u8) ?CodegenImportRef {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        const import_ref = parseCodegenImport(tokens, i) orelse continue;
        if (std.mem.eql(u8, import_ref.alias, alias)) return import_ref;
        i = findLineEnd(tokens, i) - 1;
    }
    return null;
}

fn parseCodegenImport(tokens: []const lexer.Token, idx: usize) ?CodegenImportRef {
    const line_end = findLineEnd(tokens, idx);
    if (idx + 8 >= line_end) return null;
    if (tokens[idx].kind != .ident) return null;
    if (!tokEq(tokens[idx + 1], "=")) return null;
    if (!tokEq(tokens[idx + 2], "@")) return null;
    if (tokens[idx + 3].kind != .ident or !std.mem.eql(u8, tokens[idx + 3].lexeme, "lib")) return null;
    if (!tokEq(tokens[idx + 4], "(")) return null;
    if (tokens[idx + 5].kind != .string) return null;
    if (!tokEq(tokens[idx + 6], ",")) return null;
    if (tokens[idx + 7].kind != .ident) return null;
    if (!tokEq(tokens[idx + 8], ")")) return null;
    if (idx + 9 != line_end) return null;

    var file_path = stringTokenBody(tokens[idx + 5].lexeme) orelse return null;
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

fn findImportedModuleIndex(
    allocator: std.mem.Allocator,
    modules: []const imports.ModuleRecord,
    current_idx: usize,
    import_ref: CodegenImportRef,
) ?usize {
    switch (import_ref.prefix) {
        .local => {
            const base = std.fs.path.dirname(modules[current_idx].path) orelse ".";
            const resolved = std.fs.path.join(allocator, &.{ base, import_ref.file_path }) catch return null;
            defer allocator.free(resolved);
            return findModuleByPath(modules, resolved);
        },
        .std => {
            const resolved = std.fs.path.join(allocator, &.{ "src", import_ref.file_path }) catch return null;
            defer allocator.free(resolved);
            return findModuleByPath(modules, resolved);
        },
        .dep => return findModuleByBasename(modules, import_ref.file_path),
    }
}

fn findModuleByPath(modules: []const imports.ModuleRecord, path: []const u8) ?usize {
    for (modules, 0..) |module, idx| {
        if (std.mem.eql(u8, module.path, path)) return idx;
    }
    return null;
}

fn findModuleByBasename(modules: []const imports.ModuleRecord, file_path: []const u8) ?usize {
    for (modules, 0..) |module, idx| {
        if (std.mem.eql(u8, std.fs.path.basename(module.path), file_path)) return idx;
    }
    return null;
}

fn publicDeclName(name: []const u8) []const u8 {
    if (name.len > 1 and name[0] == '.') return name[1..];
    return name;
}

fn isCoreWasmCallName(name: []const u8) bool {
    return isBoolSpecialFuncName(name) or
        isNumericCoreFuncName(name) or
        isNumericUnarySelectCoreFuncName(name) or
        isNumericBinarySelectCoreFuncName(name) or
        isComparisonCoreFuncName(name) or
        std.mem.eql(u8, name, "get") or
        std.mem.eql(u8, name, "set") or
        std.mem.eql(u8, name, "len") or
        std.mem.eql(u8, name, "put") or
        isMemoryLoadName(name) or
        isBitwiseCoreFuncName(name) or
        isCountBitsCoreFuncName(name) or
        isFloatUnaryCoreFuncName(name) or
        isFloatBinaryCoreFuncName(name) or
        std.mem.eql(u8, name, "to_u8") or
        std.mem.eql(u8, name, "to_u16") or
        std.mem.eql(u8, name, "to_u32") or
        std.mem.eql(u8, name, "to_u64") or
        std.mem.eql(u8, name, "to_usize") or
        std.mem.eql(u8, name, "to_isize") or
        std.mem.eql(u8, name, "to_i8") or
        std.mem.eql(u8, name, "to_i16") or
        std.mem.eql(u8, name, "to_i32") or
        std.mem.eql(u8, name, "to_i64") or
        std.mem.eql(u8, name, "to_f32") or
        std.mem.eql(u8, name, "to_f64");
}

fn collectStringDataForHostCalls(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    host_imports: []const HostImport,
    out: *StringDataContext,
) !void {
    if (host_imports.len == 0) return;

    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        const host_import = findHostImportForTokens(host_imports, tokens, tokens[i].lexeme) orelse continue;
        if (!tokEq(tokens[i + 1], "(")) continue;

        const close_paren = findMatching(tokens, i + 1, "(", ")") catch return error.InvalidCallArgList;
        var arg_start = i + 2;
        var param_idx: usize = 0;
        while (arg_start < close_paren) {
            const arg_end = findArgEnd(tokens, arg_start, close_paren);
            if (stringLiteralArgLexeme(tokens, arg_start, arg_end)) |lexeme| {
                if (!hostParamIsPtrLen(host_import, param_idx)) return error.NoMatchingCall;
                _ = try out.intern(allocator, lexeme);
                param_idx += 2;
            } else if (hostArgCouldBeStoragePtrLenSyntax(tokens, arg_start, arg_end) and hostParamIsPtrLen(host_import, param_idx)) {
                param_idx += 2;
            } else {
                param_idx += 1;
            }
            arg_start = arg_end;
            if (arg_start < close_paren and tokEq(tokens[arg_start], ",")) arg_start += 1;
        }
        i = close_paren;
    }
}

fn collectStringDataForWasiHostCalls(
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
        const lowering = wasiLowering(import) orelse continue;
        if (!lowering.result_link_at_error) continue;
        if (!tokEq(tokens[i + 1], "(")) continue;

        const close_paren = findMatching(tokens, i + 1, "(", ")") catch return error.InvalidCallArgList;
        const args = parseWasiLinkAtArgs(tokens, i + 2, close_paren) orelse return error.NoMatchingCall;
        if (stringLiteralArgLexeme(tokens, args.old_path_start, args.old_path_end)) |old_path| {
            _ = try out.intern(allocator, old_path);
        } else if (!hostArgCouldBeStoragePtrLenSyntax(tokens, args.old_path_start, args.old_path_end)) {
            return error.NoMatchingCall;
        }
        if (stringLiteralArgLexeme(tokens, args.new_path_start, args.new_path_end)) |new_path| {
            _ = try out.intern(allocator, new_path);
        } else if (!hostArgCouldBeStoragePtrLenSyntax(tokens, args.new_path_start, args.new_path_end)) {
            return error.NoMatchingCall;
        }
        i = close_paren;
    }
}

fn collectStringDataForStorageLiterals(
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
            tokEq(tokens[i + 1], "[") and
            tokEq(tokens[i + 2], "u8") and
            tokEq(tokens[i + 3], "]") and
            tokEq(tokens[i + 4], "="))
            i + 4
        else if (tokEq(tokens[i + 1], "text") and tokEq(tokens[i + 2], "="))
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
        if (!hasBorrowedName(storage_names.items, tokens[i].lexeme)) continue;
        if (!tokEq(tokens[i + 1], "=")) continue;
        if (tokens[i + 2].kind != .string) continue;
        _ = try out.intern(allocator, tokens[i + 2].lexeme);
    }

    i = 0;
    var depth_brace: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace == 0) continue;
        if (tokens[i].kind != .string) continue;
        if (tokens[i].lexeme.len < 2 or tokens[i].lexeme[0] != '"') continue;
        _ = try out.intern(allocator, tokens[i].lexeme);
    }
}

fn hasBorrowedName(names: []const []const u8, name: []const u8) bool {
    for (names) |candidate| {
        if (std.mem.eql(u8, candidate, name)) return true;
    }
    return false;
}

fn collectStructDecls(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    out: *std.ArrayList(StructDecl),
) !void {
    var depth_brace: usize = 0;
    var pending_type_params = std.ArrayList([]const u8).empty;
    defer pending_type_params.deinit(allocator);
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (isLineStart(tokens, i) and tokEq(tokens[i], "#")) {
            const line_end = findLineEnd(tokens, i);
            if (line_end == i + 2 and tokens[i + 1].kind == .ident) {
                try pending_type_params.append(allocator, tokens[i + 1].lexeme);
            }
            i = line_end - 1;
            continue;
        }
        if (!isTopLevelStructDeclStart(tokens, i)) continue;

        const open_brace = i + 1;
        const close_brace = try findMatching(tokens, open_brace, "{", "}");
        const type_params = if (pending_type_params.items.len == 0)
            &[_][]const u8{}
        else
            try allocator.dupe([]const u8, pending_type_params.items);
        var type_params_owned = pending_type_params.items.len != 0;
        errdefer if (type_params_owned) allocator.free(type_params);
        var fields = std.ArrayList(StructField).empty;
        var owned_types = std.ArrayList([]const u8).empty;
        errdefer {
            for (owned_types.items) |owned| allocator.free(owned);
            owned_types.deinit(allocator);
            fields.deinit(allocator);
        }

        var field_idx = open_brace + 1;
        while (field_idx < close_brace) {
            const line_end = findLineEnd(tokens, field_idx);
            const type_end = findTopLevelToken(tokens, field_idx + 1, line_end, "=") orelse line_end;
            if (tokens[field_idx].kind == .ident) {
                if (try parseCodegenTypeExpr(allocator, tokens, field_idx + 1, type_end, &owned_types)) |parsed_ty| {
                    if (parsed_ty.next_idx == type_end) {
                        try fields.append(allocator, .{
                            .name = tokens[field_idx].lexeme,
                            .ty = parsed_ty.ty,
                        });
                    }
                }
            }
            field_idx = @min(line_end, close_brace);
        }

        try out.append(allocator, .{
            .name = tokens[i].lexeme,
            .type_params = type_params,
            .fields = try fields.toOwnedSlice(allocator),
            .layout_source = null,
            .owned_types = try owned_types.toOwnedSlice(allocator),
        });
        type_params_owned = false;
        pending_type_params.clearRetainingCapacity();
        i = close_brace;
    }
}

fn collectImportedStructDecls(
    allocator: std.mem.Allocator,
    entry_tokens: []const lexer.Token,
    graph: *const imports.ModuleGraph,
    out: *std.ArrayList(StructDecl),
) !void {
    const root_idx = findRootModuleIndex(graph.modules, entry_tokens) orelse return;

    var i: usize = 0;
    while (i < entry_tokens.len) : (i += 1) {
        const import_ref = parseCodegenImport(entry_tokens, i) orelse continue;
        defer i = findLineEnd(entry_tokens, i) - 1;

        const child_idx = findImportedModuleIndex(allocator, graph.modules, root_idx, import_ref) orelse continue;
        if (!std.mem.eql(u8, import_ref.alias, import_ref.target) and findStructDecl(out.items, import_ref.target) == null) {
            _ = try collectStructDeclByNameAs(
                allocator,
                graph.modules[child_idx].tokens,
                import_ref.target,
                import_ref.target,
                null,
                out,
            );
        }
        if (findStructDecl(out.items, import_ref.alias) != null) continue;
        _ = try collectStructDeclByNameAs(
            allocator,
            graph.modules[child_idx].tokens,
            import_ref.target,
            import_ref.alias,
            if (std.mem.eql(u8, import_ref.alias, import_ref.target)) null else import_ref.target,
            out,
        );
    }

    for (graph.modules, 0..) |module, idx| {
        if (idx == root_idx) continue;
        var module_structs = std.ArrayList(StructDecl).empty;
        defer module_structs.deinit(allocator);
        try collectStructDecls(allocator, module.tokens, &module_structs);
        for (module_structs.items) |decl| {
            if (findStructDecl(out.items, decl.name) != null) {
                freeStructDecl(allocator, decl);
                continue;
            }
            try out.append(allocator, decl);
        }
    }
}

fn collectStructDeclByNameAs(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    target_name: []const u8,
    emit_name: []const u8,
    layout_source: ?[]const u8,
    out: *std.ArrayList(StructDecl),
) !bool {
    var depth_brace: usize = 0;
    var pending_type_params = std.ArrayList([]const u8).empty;
    defer pending_type_params.deinit(allocator);
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (isLineStart(tokens, i) and tokEq(tokens[i], "#")) {
            const line_end = findLineEnd(tokens, i);
            if (line_end == i + 2 and tokens[i + 1].kind == .ident) {
                try pending_type_params.append(allocator, tokens[i + 1].lexeme);
            }
            i = line_end - 1;
            continue;
        }
        if (!isTopLevelStructDeclStart(tokens, i)) continue;
        if (!std.mem.eql(u8, publicDeclName(tokens[i].lexeme), target_name)) continue;

        const open_brace = i + 1;
        const close_brace = try findMatching(tokens, open_brace, "{", "}");
        const type_params = if (pending_type_params.items.len == 0)
            &[_][]const u8{}
        else
            try allocator.dupe([]const u8, pending_type_params.items);
        var type_params_owned = pending_type_params.items.len != 0;
        errdefer if (type_params_owned) allocator.free(type_params);
        var fields = std.ArrayList(StructField).empty;
        var owned_types = std.ArrayList([]const u8).empty;
        errdefer {
            for (owned_types.items) |owned| allocator.free(owned);
            owned_types.deinit(allocator);
            fields.deinit(allocator);
        }

        var field_idx = open_brace + 1;
        while (field_idx < close_brace) {
            const line_end = findLineEnd(tokens, field_idx);
            const type_end = findTopLevelToken(tokens, field_idx + 1, line_end, "=") orelse line_end;
            if (tokens[field_idx].kind == .ident) {
                if (try parseCodegenTypeExpr(allocator, tokens, field_idx + 1, type_end, &owned_types)) |parsed_ty| {
                    if (parsed_ty.next_idx == type_end) {
                        try fields.append(allocator, .{
                            .name = tokens[field_idx].lexeme,
                            .ty = parsed_ty.ty,
                        });
                    }
                }
            }
            field_idx = @min(line_end, close_brace);
        }

        try out.append(allocator, .{
            .name = emit_name,
            .type_params = type_params,
            .fields = try fields.toOwnedSlice(allocator),
            .layout_source = layout_source,
            .owned_types = try owned_types.toOwnedSlice(allocator),
        });
        type_params_owned = false;
        return true;
    }
    return false;
}
fn collectStructLayouts(
    allocator: std.mem.Allocator,
    structs: []const StructDecl,
    out: *std.ArrayList(StructLayout),
) !void {
    var next_type_id: usize = TYPE_ID_FIRST_STRUCT;
    for (structs) |decl| {
        if (decl.layout_source) |source_name| {
            const source_layout = findStructLayout(out.items, source_name) orelse continue;
            try out.append(allocator, .{
                .name = decl.name,
                .type_id = source_layout.type_id,
                .payload_bytes = source_layout.payload_bytes,
                .managed_fields = try cloneManagedFields(allocator, source_layout.managed_fields),
            });
            continue;
        }

        var managed_fields = std.ArrayList(ManagedFieldOffset).empty;
        errdefer managed_fields.deinit(allocator);

        var offset: usize = 0;
        for (decl.fields) |field| {
            const field_align = typePayloadAlignment(field.ty);
            offset = alignUp(offset, field_align);
            if (isManagedPayloadType(field.ty)) {
                try managed_fields.append(allocator, .{
                    .name = publicDeclName(field.name),
                    .offset = offset,
                });
            }
            offset += typePayloadBytes(field.ty);
        }

        if (managed_fields.items.len == 0) {
            managed_fields.deinit(allocator);
            continue;
        }

        try out.append(allocator, .{
            .name = decl.name,
            .type_id = next_type_id,
            .payload_bytes = alignUp(offset, 4),
            .managed_fields = try managed_fields.toOwnedSlice(allocator),
        });
        next_type_id += 1;
    }
}

fn cloneManagedFields(
    allocator: std.mem.Allocator,
    fields: []const ManagedFieldOffset,
) ![]const ManagedFieldOffset {
    const out = try allocator.alloc(ManagedFieldOffset, fields.len);
    @memcpy(out, fields);
    return out;
}

fn parseCodegenTypeExpr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    owned_types: *std.ArrayList([]const u8),
) !?ParsedCodegenType {
    if (start_idx >= end_idx) return null;

    if (tokEq(tokens[start_idx], "[")) {
        const close_bracket = findMatchingInRange(tokens, start_idx, "[", "]", end_idx) catch return null;
        if (close_bracket <= start_idx + 1) return null;
        if (close_bracket == start_idx + 2 and tokens[start_idx + 1].kind == .ident) {
            if (storageTypeNameForElem(tokens[start_idx + 1].lexeme)) |storage_ty| {
                return .{ .ty = storage_ty, .next_idx = close_bracket + 1 };
            }
        }
        const ty = try compactTokenText(allocator, tokens, start_idx, close_bracket + 1);
        errdefer allocator.free(ty);
        try owned_types.append(allocator, ty);
        return .{ .ty = ty, .next_idx = close_bracket + 1 };
    }

    if (tokens[start_idx].kind != .ident) return null;
    if (start_idx + 1 < end_idx and tokEq(tokens[start_idx + 1], "<")) {
        const close_angle = findMatchingInRange(tokens, start_idx + 1, "<", ">", end_idx) catch return null;
        const ty = try compactTokenText(allocator, tokens, start_idx, close_angle + 1);
        errdefer allocator.free(ty);
        try owned_types.append(allocator, ty);
        return .{ .ty = ty, .next_idx = close_angle + 1 };
    }

    return .{ .ty = tokens[start_idx].lexeme, .next_idx = start_idx + 1 };
}

fn collectFuncDecls(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    imported_alias_ctx: ?ImportedAliasContext,
    out: *std.ArrayList(FuncDecl),
) !void {
    var depth_brace: usize = 0;
    var pending_type_params = std.ArrayList([]const u8).empty;
    defer pending_type_params.deinit(allocator);
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (isLineStart(tokens, i) and tokEq(tokens[i], "#")) {
            const line_end = findLineEnd(tokens, i);
            if (line_end == i + 2 and tokens[i + 1].kind == .ident) {
                try pending_type_params.append(allocator, tokens[i + 1].lexeme);
            }
            i = line_end - 1;
            continue;
        }
        if (isTopLevelStructDeclStart(tokens, i)) {
            pending_type_params.clearRetainingCapacity();
            i = (findMatching(tokens, i + 1, "{", "}") catch i);
            continue;
        }
        if (!isUserFuncDeclStart(tokens, i)) continue;

        const open_params = i + 1;
        const close_params = try findMatching(tokens, open_params, "(", ")");
        const body = parseFuncBodyShape(tokens, close_params) catch continue;
        var owned_types = std.ArrayList([]const u8).empty;
        errdefer {
            for (owned_types.items) |owned| allocator.free(owned);
            owned_types.deinit(allocator);
        }
        const type_params = if (pending_type_params.items.len == 0)
            &[_][]const u8{}
        else
            try allocator.dupe([]const u8, pending_type_params.items);
        var type_params_owned = pending_type_params.items.len != 0;
        errdefer if (type_params_owned) allocator.free(type_params);
        const parsed_results = if (body.result_start == body.result_end)
            FuncResultParse{ .types = try allocator.alloc([]const u8, 0) }
        else blk: {
            if (try parseFuncResultTypes(allocator, tokens, body.result_start, body.result_end, structs, struct_layouts, imported_alias_ctx, &owned_types)) |parsed| {
                break :blk parsed;
            }
            if (type_params.len != 0) {
                if (try parseGenericFuncResultTypes(allocator, tokens, body.result_start, body.result_end, type_params, structs, struct_layouts, &owned_types)) |parsed| {
                    break :blk parsed;
                }
            }
            continue;
        };
        const results = parsed_results.types;
        var results_owned = true;
        errdefer if (results_owned) allocator.free(results);

        var params = std.ArrayList(FuncParam).empty;
        errdefer params.deinit(allocator);
        var param_idx = open_params + 1;
        while (param_idx < close_params) {
            if (tokEq(tokens[param_idx], ",")) {
                param_idx += 1;
                continue;
            }
            if (param_idx + 1 >= close_params) return error.InvalidParamName;
            if (tokens[param_idx].kind != .ident) return error.InvalidParamName;
            var type_start = param_idx + 1;
            var variadic = false;
            if (type_start < close_params and tokEq(tokens[type_start], "...")) {
                variadic = true;
                type_start += 1;
            }
            const parsed_ty = (try parseCodegenTypeExpr(allocator, tokens, type_start, close_params, &owned_types)) orelse return error.InvalidParamName;
            try params.append(allocator, .{
                .name = tokens[param_idx].lexeme,
                .ty = parsed_ty.ty,
                .variadic = variadic,
            });
            param_idx = parsed_ty.next_idx;
            if (param_idx < close_params and tokEq(tokens[param_idx], ",")) param_idx += 1;
        }

        try out.append(allocator, .{
            .name = publicDeclName(tokens[i].lexeme),
            .source_name = publicDeclName(tokens[i].lexeme),
            .params = try params.toOwnedSlice(allocator),
            .result = if (results.len == 1) results[0] else null,
            .results = results,
            .result_struct = parsed_results.result_struct,
            .type_params = type_params,
            .is_generic_template = type_params.len != 0,
            .owned_types = try owned_types.toOwnedSlice(allocator),
            .tokens = tokens,
            .arrow = body.arrow,
            .body_start = body.body_start,
            .body_end = body.body_end,
        });
        results_owned = false;
        type_params_owned = false;
        pending_type_params.clearRetainingCapacity();
        i = body.next_idx;
    }
}

fn collectDirectImportedFuncDecls(
    allocator: std.mem.Allocator,
    entry_tokens: []const lexer.Token,
    graph: *const imports.ModuleGraph,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    out: *std.ArrayList(FuncDecl),
) !void {
    const root_idx = findRootModuleIndex(graph.modules, entry_tokens) orelse return;

    var stack = std.ArrayList(ReachVisit).empty;
    defer stack.deinit(allocator);

    var visited = std.ArrayList(ReachVisit).empty;
    defer visited.deinit(allocator);

    try collectStartBodyCalls(allocator, graph.modules[root_idx].tokens, root_idx, &stack);
    try collectAllFunctionBodyCalls(allocator, graph.modules[root_idx].tokens, root_idx, &stack);
    while (stack.items.len != 0) {
        const visit = stack.pop().?;
        if (hasReachVisit(visited.items, visit)) continue;
        try visited.append(allocator, visit);

        const module = graph.modules[visit.module_idx];
        if (findCodegenImportByAlias(module.tokens, visit.name)) |import_ref| {
            const child_idx = findImportedModuleIndex(allocator, graph.modules, visit.module_idx, import_ref) orelse continue;
            if (findFuncDecl(out.items, import_ref.alias) == null) {
                _ = try collectFuncDeclByNameAs(
                    allocator,
                    graph.modules[child_idx].tokens,
                    structs,
                    struct_layouts,
                    import_ref.target,
                    import_ref.alias,
                    false,
                    out,
                );
            }
            try collectFunctionBodyCalls(allocator, graph.modules[child_idx].tokens, child_idx, import_ref.target, &stack);
            continue;
        }

        if (visit.module_idx != root_idx and findFuncDeclBySourceForTokens(out.items, module.tokens, publicDeclName(visit.name)) == null) {
            const emit_name = try moduleScopedSymbolName(allocator, visit.module_idx, publicDeclName(visit.name));
            var emit_name_owned = true;
            errdefer if (emit_name_owned) allocator.free(emit_name);
            const collected = try collectFuncDeclByNameAs(
                allocator,
                module.tokens,
                structs,
                struct_layouts,
                publicDeclName(visit.name),
                emit_name,
                true,
                out,
            );
            if (collected) {
                emit_name_owned = false;
            } else {
                allocator.free(emit_name);
                emit_name_owned = false;
            }
        }
        try collectFunctionBodyCalls(allocator, module.tokens, visit.module_idx, visit.name, &stack);
    }
}

fn collectDirectImportedFuncDeclsFromTests(
    allocator: std.mem.Allocator,
    entry_tokens: []const lexer.Token,
    graph: *const imports.ModuleGraph,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    out: *std.ArrayList(FuncDecl),
) !void {
    const root_idx = findRootModuleIndex(graph.modules, entry_tokens) orelse return;

    var stack = std.ArrayList(ReachVisit).empty;
    defer stack.deinit(allocator);

    var visited = std.ArrayList(ReachVisit).empty;
    defer visited.deinit(allocator);

    try collectTestBodyCalls(allocator, graph.modules[root_idx].tokens, root_idx, &stack);
    try collectAllFunctionBodyCalls(allocator, graph.modules[root_idx].tokens, root_idx, &stack);
    while (stack.items.len != 0) {
        const visit = stack.pop().?;
        if (hasReachVisit(visited.items, visit)) continue;
        try visited.append(allocator, visit);

        const module = graph.modules[visit.module_idx];
        if (findCodegenImportByAlias(module.tokens, visit.name)) |import_ref| {
            const child_idx = findImportedModuleIndex(allocator, graph.modules, visit.module_idx, import_ref) orelse continue;
            if (findFuncDecl(out.items, import_ref.alias) == null) {
                _ = try collectFuncDeclByNameAs(
                    allocator,
                    graph.modules[child_idx].tokens,
                    structs,
                    struct_layouts,
                    import_ref.target,
                    import_ref.alias,
                    false,
                    out,
                );
            }
            try collectFunctionBodyCalls(allocator, graph.modules[child_idx].tokens, child_idx, import_ref.target, &stack);
            continue;
        }

        if (visit.module_idx != root_idx and findFuncDeclBySourceForTokens(out.items, module.tokens, publicDeclName(visit.name)) == null) {
            const emit_name = try moduleScopedSymbolName(allocator, visit.module_idx, publicDeclName(visit.name));
            var emit_name_owned = true;
            errdefer if (emit_name_owned) allocator.free(emit_name);
            const collected = try collectFuncDeclByNameAs(
                allocator,
                module.tokens,
                structs,
                struct_layouts,
                publicDeclName(visit.name),
                emit_name,
                true,
                out,
            );
            if (collected) {
                emit_name_owned = false;
            } else {
                allocator.free(emit_name);
                emit_name_owned = false;
            }
        }
        try collectFunctionBodyCalls(allocator, module.tokens, visit.module_idx, visit.name, &stack);
    }
}

fn collectGenericFuncInstancesForStart(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    host_imports: []const HostImport,
    wasi_imports: []const WasiHostImport,
    string_data: *const StringDataContext,
    modules: []const imports.ModuleRecord,
    functions: *std.ArrayList(FuncDecl),
) !void {
    const start_idx = findStartFunc(tokens);
    if (start_idx) |idx| {
        const close_params = findMatching(tokens, idx + 1, "(", ")") catch null;
        if (close_params) |close| {
            const open_body = findToken(tokens, close + 1, tokens.len, "{");
            if (open_body) |open| {
                const close_body = findMatching(tokens, open, "{", "}") catch null;
                if (close_body) |body_end| {
                    var locals = LocalSet{};
                    defer locals.deinit(allocator);
                    const ctx = CodegenContext{
                        .functions = functions.items,
                        .structs = structs,
                        .struct_layouts = struct_layouts,
                        .host_imports = host_imports,
                        .wasi_imports = wasi_imports,
                        .string_data = string_data,
                        .entry_tokens = tokens,
                        .modules = modules,
                    };
                    try collectBodyLocals(allocator, tokens, open + 1, body_end, ctx, &locals);
                    try collectGenericFuncInstancesInRange(allocator, tokens, open + 1, body_end, &locals, ctx, functions);
                }
            }
        }
    }
    try collectGenericFuncInstancesForConcreteFuncs(allocator, tokens, structs, struct_layouts, host_imports, wasi_imports, string_data, modules, functions);
}

fn collectGenericFuncInstancesForTests(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    test_decls: []const test_runner.TestDecl,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    host_imports: []const HostImport,
    wasi_imports: []const WasiHostImport,
    string_data: *const StringDataContext,
    modules: []const imports.ModuleRecord,
    functions: *std.ArrayList(FuncDecl),
) !void {
    for (test_decls) |decl| {
        var locals = LocalSet{};
        defer locals.deinit(allocator);
        const ctx = CodegenContext{
            .functions = functions.items,
            .structs = structs,
            .struct_layouts = struct_layouts,
            .host_imports = host_imports,
            .wasi_imports = wasi_imports,
            .string_data = string_data,
            .entry_tokens = tokens,
            .modules = modules,
        };
        try collectBodyLocals(allocator, tokens, decl.body_start, decl.body_end, ctx, &locals);
        try collectGenericFuncInstancesInRange(allocator, tokens, decl.body_start, decl.body_end, &locals, ctx, functions);
    }
    try collectGenericFuncInstancesForConcreteFuncs(allocator, tokens, structs, struct_layouts, host_imports, wasi_imports, string_data, modules, functions);
}

fn collectGenericFuncInstancesForConcreteFuncs(
    allocator: std.mem.Allocator,
    entry_tokens: []const lexer.Token,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    host_imports: []const HostImport,
    wasi_imports: []const WasiHostImport,
    string_data: *const StringDataContext,
    modules: []const imports.ModuleRecord,
    functions: *std.ArrayList(FuncDecl),
) !void {
    var i: usize = 0;
    while (i < functions.items.len) : (i += 1) {
        const func = functions.items[i];
        if (func.is_generic_template) continue;

        var locals = LocalSet{};
        defer locals.deinit(allocator);
        const ctx = CodegenContext{
            .functions = functions.items,
            .structs = structs,
            .struct_layouts = struct_layouts,
            .host_imports = host_imports,
            .wasi_imports = wasi_imports,
            .string_data = string_data,
            .entry_tokens = entry_tokens,
            .modules = modules,
        };
        try appendFuncParamLocals(allocator, func, ctx, &locals);
        try collectBodyLocals(allocator, func.tokens, func.body_start, func.body_end, ctx, &locals);
        try collectGenericFuncInstancesInRange(allocator, func.tokens, func.body_start, func.body_end, &locals, ctx, functions);
    }
}

fn appendFuncParamLocals(
    allocator: std.mem.Allocator,
    func: FuncDecl,
    ctx: CodegenContext,
    locals: *LocalSet,
) !void {
    for (func.params) |param| {
        if (managedPayloadElemTypeFromName(param.ty)) |elem_ty| {
            try locals.appendBorrowedLocal(allocator, param.name, param.ty, false);
            try locals.storage_locals.append(allocator, .{ .name = param.name, .elem_ty = elem_ty });
        } else if (findStructDecl(ctx.structs, param.ty)) |decl| {
            try locals.struct_locals.append(allocator, .{ .name = param.name, .ty = param.ty });
            if (findStructLayout(ctx.struct_layouts, param.ty) != null) {
                try locals.appendBorrowedLocal(allocator, param.name, param.ty, false);
            } else {
                for (decl.fields) |field| {
                    try appendBorrowedLocalField(allocator, locals, param.name, field.name, field.ty);
                }
            }
        } else {
            try locals.appendBorrowedLocal(allocator, param.name, param.ty, false);
        }
    }
}

fn collectGenericFuncInstancesInRange(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    functions: *std.ArrayList(FuncDecl),
) !void {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (i > start_idx and tokEq(tokens[i - 1], "@")) continue;
        if (!tokEq(tokens[i + 1], "(")) continue;
        const close_paren = findMatchingInRange(tokens, i + 1, "(", ")", end_idx) catch continue;
        const template = findGenericTemplate(functions.items, publicDeclName(tokens[i].lexeme)) orelse continue;
        try collectGenericFuncInstanceForCall(allocator, tokens, i + 2, close_paren, locals, ctx, template, functions);
        i = close_paren;
    }
}

fn collectGenericFuncInstanceForCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    template: FuncDecl,
    functions: *std.ArrayList(FuncDecl),
) !void {
    var bindings = std.ArrayList(GenericTypeBinding).empty;
    defer bindings.deinit(allocator);
    if (!try bindGenericFuncCall(allocator, tokens, args_start, args_end, locals, ctx, template, &bindings)) return;
    if (!genericBindingsCoverTypeParams(template, bindings.items)) return;

    const instance_name = try genericInstanceName(allocator, template, bindings.items);
    errdefer allocator.free(instance_name);
    if (findFuncDecl(functions.items, instance_name) != null) {
        allocator.free(instance_name);
        return;
    }

    var params = std.ArrayList(FuncParam).empty;
    errdefer params.deinit(allocator);
    for (template.params) |param| {
        try params.append(allocator, .{
            .name = param.name,
            .ty = substituteGenericType(param.ty, bindings.items),
        });
    }
    const param_items = try params.toOwnedSlice(allocator);
    errdefer allocator.free(param_items);

    var results = std.ArrayList([]const u8).empty;
    errdefer results.deinit(allocator);
    for (template.results) |result| {
        try results.append(allocator, substituteGenericType(result, bindings.items));
    }
    const result_items = try results.toOwnedSlice(allocator);
    errdefer allocator.free(result_items);

    try functions.append(allocator, .{
        .name = instance_name,
        .source_name = template.name,
        .params = param_items,
        .result = if (result_items.len == 1) result_items[0] else null,
        .results = result_items,
        .result_struct = null,
        .owned_name = true,
        .tokens = template.tokens,
        .arrow = template.arrow,
        .body_start = template.body_start,
        .body_end = template.body_end,
    });
}

fn bindGenericFuncCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    template: FuncDecl,
    bindings: *std.ArrayList(GenericTypeBinding),
) !bool {
    var arg_start = args_start;
    var param_idx: usize = 0;
    while (arg_start < args_end) {
        if (param_idx >= template.params.len) return false;
        const arg_end = findArgEnd(tokens, arg_start, args_end);
        const arg_ty = inferExprType(tokens, arg_start, arg_end, locals, ctx) orelse return false;
        const param_ty = template.params[param_idx].ty;
        if (hasTypeParamName(template.type_params, param_ty)) {
            if (!try bindGenericType(allocator, bindings, param_ty, arg_ty)) return false;
        } else if (!std.mem.eql(u8, param_ty, arg_ty)) {
            return false;
        }
        param_idx += 1;
        arg_start = arg_end;
        if (arg_start < args_end and tokEq(tokens[arg_start], ",")) arg_start += 1;
    }
    return param_idx == template.params.len;
}

fn bindGenericType(
    allocator: std.mem.Allocator,
    bindings: *std.ArrayList(GenericTypeBinding),
    name: []const u8,
    ty: []const u8,
) !bool {
    for (bindings.items) |binding| {
        if (!std.mem.eql(u8, binding.name, name)) continue;
        return std.mem.eql(u8, binding.ty, ty);
    }
    try bindings.append(allocator, .{ .name = name, .ty = ty });
    return true;
}

fn genericBindingsCoverTypeParams(template: FuncDecl, bindings: []const GenericTypeBinding) bool {
    for (template.type_params) |type_param| {
        if (findGenericBinding(bindings, type_param) == null) return false;
    }
    return true;
}

fn findGenericBinding(bindings: []const GenericTypeBinding, name: []const u8) ?GenericTypeBinding {
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.name, name)) return binding;
    }
    return null;
}

fn substituteGenericType(ty: []const u8, bindings: []const GenericTypeBinding) []const u8 {
    if (findGenericBinding(bindings, ty)) |binding| return binding.ty;
    return ty;
}

fn genericInstanceName(
    allocator: std.mem.Allocator,
    template: FuncDecl,
    bindings: []const GenericTypeBinding,
) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, template.name);
    for (template.type_params) |type_param| {
        const binding = findGenericBinding(bindings, type_param) orelse return error.NoMatchingCall;
        try out.appendSlice(allocator, "__");
        try appendMangledTypeName(allocator, &out, binding.ty);
    }
    return out.toOwnedSlice(allocator);
}

fn moduleScopedSymbolName(
    allocator: std.mem.Allocator,
    module_idx: usize,
    name: []const u8,
) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try appendFmt(allocator, &out, "__do_mod_{d}__", .{module_idx});
    try appendMangledTypeName(allocator, &out, publicDeclName(name));
    return out.toOwnedSlice(allocator);
}

fn appendMangledTypeName(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    ty: []const u8,
) !void {
    for (ty) |ch| {
        if ((ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or (ch >= '0' and ch <= '9')) {
            try out.append(allocator, ch);
        } else {
            try out.append(allocator, '_');
        }
    }
}

fn findGenericTemplate(functions: []const FuncDecl, name: []const u8) ?FuncDecl {
    for (functions) |func| {
        if (!func.is_generic_template) continue;
        if (std.mem.eql(u8, func.name, name)) return func;
    }
    return null;
}

fn isCodegenImportAliasReachable(
    allocator: std.mem.Allocator,
    graph: *const imports.ModuleGraph,
    root_idx: usize,
    alias: []const u8,
) !bool {
    var stack = std.ArrayList(ReachVisit).empty;
    defer stack.deinit(allocator);

    var visited = std.ArrayList(ReachVisit).empty;
    defer visited.deinit(allocator);

    try collectStartBodyCalls(allocator, graph.modules[root_idx].tokens, root_idx, &stack);
    while (stack.items.len != 0) {
        const visit = stack.pop().?;
        if (visit.module_idx == root_idx and std.mem.eql(u8, visit.name, alias)) return true;
        if (hasReachVisit(visited.items, visit)) continue;
        try visited.append(allocator, visit);

        const module = graph.modules[visit.module_idx];
        if (findCodegenImportByAlias(module.tokens, visit.name)) |import_ref| {
            if (findImportedModuleIndex(allocator, graph.modules, visit.module_idx, import_ref)) |child_idx| {
                try pushReachVisit(allocator, &stack, .{
                    .module_idx = child_idx,
                    .name = import_ref.target,
                });
            }
            continue;
        }

        try collectFunctionBodyCalls(allocator, module.tokens, visit.module_idx, visit.name, &stack);
    }
    return false;
}

fn collectFuncDeclByNameAs(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    target_name: []const u8,
    emit_name: []const u8,
    owned_emit_name: bool,
    out: *std.ArrayList(FuncDecl),
) !bool {
    var depth_brace: usize = 0;
    var pending_type_params = std.ArrayList([]const u8).empty;
    defer pending_type_params.deinit(allocator);
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (isLineStart(tokens, i) and tokEq(tokens[i], "#")) {
            const line_end = findLineEnd(tokens, i);
            if (line_end == i + 2 and tokens[i + 1].kind == .ident) {
                try pending_type_params.append(allocator, tokens[i + 1].lexeme);
            }
            i = line_end - 1;
            continue;
        }
        if (isTopLevelStructDeclStart(tokens, i)) {
            pending_type_params.clearRetainingCapacity();
            i = (findMatching(tokens, i + 1, "{", "}") catch i);
            continue;
        }
        if (!isUserFuncDeclStart(tokens, i)) continue;
        if (!std.mem.eql(u8, publicDeclName(tokens[i].lexeme), target_name)) continue;

        const open_params = i + 1;
        const close_params = try findMatching(tokens, open_params, "(", ")");
        const body = parseFuncBodyShape(tokens, close_params) catch return false;
        var owned_types = std.ArrayList([]const u8).empty;
        errdefer {
            for (owned_types.items) |owned| allocator.free(owned);
            owned_types.deinit(allocator);
        }
        const type_params = if (pending_type_params.items.len == 0)
            &[_][]const u8{}
        else
            try allocator.dupe([]const u8, pending_type_params.items);
        var type_params_owned = pending_type_params.items.len != 0;
        errdefer if (type_params_owned) allocator.free(type_params);
        const parsed_results = if (body.result_start == body.result_end)
            FuncResultParse{ .types = try allocator.alloc([]const u8, 0) }
        else blk: {
            if (try parseFuncResultTypes(allocator, tokens, body.result_start, body.result_end, structs, struct_layouts, null, &owned_types)) |parsed| {
                break :blk parsed;
            }
            if (type_params.len != 0) {
                if (try parseGenericFuncResultTypes(allocator, tokens, body.result_start, body.result_end, type_params, structs, struct_layouts, &owned_types)) |parsed| {
                    break :blk parsed;
                }
            }
            return false;
        };
        const results = parsed_results.types;
        var results_owned = true;
        errdefer if (results_owned) allocator.free(results);

        var params = std.ArrayList(FuncParam).empty;
        errdefer params.deinit(allocator);
        var param_idx = open_params + 1;
        while (param_idx < close_params) {
            if (tokEq(tokens[param_idx], ",")) {
                param_idx += 1;
                continue;
            }
            if (param_idx + 1 >= close_params) return error.InvalidParamName;
            if (tokens[param_idx].kind != .ident) return error.InvalidParamName;
            var type_start = param_idx + 1;
            var variadic = false;
            if (type_start < close_params and tokEq(tokens[type_start], "...")) {
                variadic = true;
                type_start += 1;
            }
            const parsed_ty = (try parseCodegenTypeExpr(allocator, tokens, type_start, close_params, &owned_types)) orelse return error.InvalidParamName;
            try params.append(allocator, .{
                .name = tokens[param_idx].lexeme,
                .ty = parsed_ty.ty,
                .variadic = variadic,
            });
            param_idx = parsed_ty.next_idx;
            if (param_idx < close_params and tokEq(tokens[param_idx], ",")) param_idx += 1;
        }

        try out.append(allocator, .{
            .name = emit_name,
            .source_name = target_name,
            .params = try params.toOwnedSlice(allocator),
            .result = if (results.len == 1) results[0] else null,
            .results = results,
            .result_struct = parsed_results.result_struct,
            .type_params = type_params,
            .is_generic_template = type_params.len != 0,
            .owned_name = owned_emit_name,
            .owned_types = try owned_types.toOwnedSlice(allocator),
            .tokens = tokens,
            .arrow = body.arrow,
            .body_start = body.body_start,
            .body_end = body.body_end,
        });
        results_owned = false;
        type_params_owned = false;
        return true;
    }
    return false;
}

fn parseFuncBodyShape(tokens: []const lexer.Token, close_params: usize) !FuncBodyShape {
    const after_params = close_params + 1;
    if (after_params < tokens.len and tokEq(tokens[after_params], "{")) {
        const close_body = try findMatching(tokens, after_params, "{", "}");
        return .{
            .result_start = after_params,
            .result_end = after_params,
            .body_start = after_params + 1,
            .body_end = close_body,
            .arrow = false,
            .next_idx = close_body,
        };
    }

    if (after_params + 1 >= tokens.len or !tokEq(tokens[after_params], "-") or !tokEq(tokens[after_params + 1], ">")) {
        return error.NoMatchingCall;
    }

    const result_start = after_params + 2;
    if (result_start >= tokens.len) return error.NoMatchingCall;
    const arrow_idx = findTopLevelToken(tokens, result_start, findLineEnd(tokens, close_params), "=") orelse {
        const open_body = findToken(tokens, result_start, tokens.len, "{") orelse return error.NoMatchingCall;
        const close_body = try findMatching(tokens, open_body, "{", "}");
        return .{
            .result_start = result_start,
            .result_end = open_body,
            .body_start = open_body + 1,
            .body_end = close_body,
            .arrow = false,
            .next_idx = close_body,
        };
    };
    if (arrow_idx == result_start or arrow_idx + 1 >= tokens.len or !tokEq(tokens[arrow_idx + 1], ">")) return error.NoMatchingCall;
    if (arrow_idx + 2 >= tokens.len) return error.NoMatchingCall;

    return .{
        .result_start = result_start,
        .result_end = arrow_idx,
        .body_start = arrow_idx + 2,
        .body_end = findLineEnd(tokens, arrow_idx),
        .arrow = true,
        .next_idx = findLineEnd(tokens, arrow_idx) - 1,
    };
}

fn parseFuncResultTypes(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    imported_alias_ctx: ?ImportedAliasContext,
    owned_types: *std.ArrayList([]const u8),
) !?FuncResultParse {
    var results = std.ArrayList([]const u8).empty;
    errdefer results.deinit(allocator);

    if (start_idx + 1 == end_idx and tokEq(tokens[start_idx], "nil")) {
        return .{ .types = try results.toOwnedSlice(allocator) };
    }

    if (parseErrorNilResultType(tokens, start_idx, end_idx)) |result_ty| {
        try results.append(allocator, result_ty);
        return .{ .types = try results.toOwnedSlice(allocator) };
    }

    if (parseStructErrorResultType(tokens, start_idx, end_idx, structs, struct_layouts)) |parsed| {
        const decl = findStructDecl(structs, parsed.struct_name) orelse return null;
        for (decl.fields) |field| {
            if (!isCoreWasmScalar(field.ty)) return null;
            try results.append(allocator, field.ty);
        }
        try results.append(allocator, parsed.error_name);
        return .{
            .types = try results.toOwnedSlice(allocator),
            .result_struct = parsed.struct_name,
        };
    }

    if (start_idx + 1 == end_idx and tokens[start_idx].kind == .ident) {
        const struct_name = tokens[start_idx].lexeme;
        if (findStructLayout(struct_layouts, struct_name) == null) {
            if (findStructDecl(structs, struct_name)) |decl| {
                for (decl.fields) |field| {
                    if (!isCoreWasmScalar(field.ty)) return null;
                    try results.append(allocator, field.ty);
                }
                return .{
                    .types = try results.toOwnedSlice(allocator),
                    .result_struct = struct_name,
                };
            }
        }
        if (isErrorEnumType(tokens, struct_name)) {
            try results.append(allocator, struct_name);
            return .{ .types = try results.toOwnedSlice(allocator) };
        }
        if (errorNilAliasTarget(tokens, struct_name)) |error_name| {
            try results.append(allocator, error_name);
            return .{ .types = try results.toOwnedSlice(allocator) };
        }
        if (importedErrorNilAliasTarget(allocator, imported_alias_ctx, tokens, struct_name)) |error_name| {
            try results.append(allocator, error_name);
            return .{ .types = try results.toOwnedSlice(allocator) };
        }
    }

    var i = start_idx;
    while (i < end_idx) {
        if (tokEq(tokens[i], ",")) {
            i += 1;
            continue;
        }

        const parsed_ty = (try parseCodegenTypeExpr(allocator, tokens, i, end_idx, owned_types)) orelse return null;
        const result_ty = parsed_ty.ty;
        const accepted = isCoreWasmScalar(result_ty) or
            managedPayloadElemTypeFromName(result_ty) != null or
            findStructLayout(struct_layouts, result_ty) != null or
            (tokens[i].kind == .ident and errorNilAliasTarget(tokens, tokens[i].lexeme) != null) or
            (tokens[i].kind == .ident and importedErrorNilAliasTarget(allocator, imported_alias_ctx, tokens, tokens[i].lexeme) != null);
        if (!accepted) return null;

        try results.append(allocator, result_ty);
        i = parsed_ty.next_idx;
        if (i < end_idx and tokEq(tokens[i], ",")) i += 1;
    }

    return .{ .types = try results.toOwnedSlice(allocator) };
}

fn parseGenericFuncResultTypes(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    type_params: []const []const u8,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    owned_types: *std.ArrayList([]const u8),
) !?FuncResultParse {
    var results = std.ArrayList([]const u8).empty;
    errdefer results.deinit(allocator);

    if (start_idx + 1 == end_idx and tokEq(tokens[start_idx], "nil")) {
        return .{ .types = try results.toOwnedSlice(allocator) };
    }

    var i = start_idx;
    while (i < end_idx) {
        if (tokEq(tokens[i], ",")) {
            i += 1;
            continue;
        }

        const parsed_ty = (try parseCodegenTypeExpr(allocator, tokens, i, end_idx, owned_types)) orelse return null;
        const result_ty = parsed_ty.ty;
        const accepted = isCoreWasmScalar(result_ty) or
            hasTypeParamName(type_params, result_ty) or
            managedPayloadElemTypeFromName(result_ty) != null or
            findStructLayout(struct_layouts, result_ty) != null or
            findStructDecl(structs, result_ty) != null;
        if (!accepted) return null;

        try results.append(allocator, result_ty);
        i = parsed_ty.next_idx;
        if (i < end_idx and tokEq(tokens[i], ",")) i += 1;
    }

    return .{ .types = try results.toOwnedSlice(allocator) };
}

fn hasTypeParamName(type_params: []const []const u8, name: []const u8) bool {
    for (type_params) |type_param| {
        if (std.mem.eql(u8, type_param, name)) return true;
    }
    return false;
}

fn parseStructErrorResultType(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
) ?StructErrorResult {
    if (start_idx + 3 != end_idx) return null;
    if (!tokEq(tokens[start_idx + 1], "|")) return null;

    const left = tokens[start_idx].lexeme;
    const right = tokens[start_idx + 2].lexeme;
    if (tokens[start_idx].kind == .ident and tokens[start_idx + 2].kind == .ident) {
        if (isUnmanagedScalarStruct(structs, struct_layouts, left) and isErrorLikeType(tokens, right)) {
            return .{ .struct_name = left, .error_name = right };
        }
        if (isErrorLikeType(tokens, left) and isUnmanagedScalarStruct(structs, struct_layouts, right)) {
            return .{ .struct_name = right, .error_name = left };
        }
    }
    return null;
}

fn parseErrorNilResultType(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    if (start_idx + 3 != end_idx) return null;
    if (!tokEq(tokens[start_idx + 1], "|")) return null;
    if (tokens[start_idx].kind == .ident and tokEq(tokens[start_idx + 2], "nil") and isErrorLikeType(tokens, tokens[start_idx].lexeme)) {
        return tokens[start_idx].lexeme;
    }
    if (tokEq(tokens[start_idx], "nil") and tokens[start_idx + 2].kind == .ident and isErrorLikeType(tokens, tokens[start_idx + 2].lexeme)) {
        return tokens[start_idx + 2].lexeme;
    }
    return null;
}

fn isUnmanagedScalarStruct(
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    name: []const u8,
) bool {
    if (findStructLayout(struct_layouts, name) != null) return false;
    const decl = findStructDecl(structs, name) orelse return false;
    for (decl.fields) |field| {
        if (!isCoreWasmScalar(field.ty)) return false;
    }
    return true;
}

fn unmanagedStructErrorUnionResult(
    tokens: []const lexer.Token,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_struct: ?[]const u8,
) ?[]const u8 {
    const struct_name = result_struct orelse return null;
    if (findStructLayout(ctx.struct_layouts, struct_name) != null) return null;
    const decl = findStructDecl(ctx.structs, struct_name) orelse return null;
    if (result_tys.len != decl.fields.len + 1) return null;
    for (decl.fields, 0..) |field, idx| {
        if (!std.mem.eql(u8, field.ty, result_tys[idx])) return null;
    }
    const error_name = result_tys[decl.fields.len];
    if (!isErrorLikeType(tokens, error_name)) return null;
    return error_name;
}

fn isErrorLikeType(tokens: []const lexer.Token, name: []const u8) bool {
    return isErrorEnumType(tokens, name) or errorNilAliasTarget(tokens, name) != null or std.mem.endsWith(u8, name, "Error");
}

fn isErrorEnumType(tokens: []const lexer.Token, name: []const u8) bool {
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
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, tokens[i].lexeme, name)) continue;
        if (tokEq(tokens[i + 1], "error") and tokEq(tokens[i + 2], "=")) return true;
    }
    return false;
}

fn errorNilAliasTarget(tokens: []const lexer.Token, name: []const u8) ?[]const u8 {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i + 4 < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (tokens[i].kind != .ident or !std.mem.eql(u8, tokens[i].lexeme, name)) continue;
        if (!tokEq(tokens[i + 1], "=")) continue;

        const line_end = findLineEnd(tokens, i);
        if (i + 5 != line_end) return null;
        if (tokens[i + 2].kind == .ident and tokEq(tokens[i + 3], "|") and tokEq(tokens[i + 4], "nil") and
            isErrorEnumTypeNameForLowering(tokens, tokens[i + 2].lexeme))
        {
            return tokens[i + 2].lexeme;
        }
        if (tokEq(tokens[i + 2], "nil") and tokEq(tokens[i + 3], "|") and tokens[i + 4].kind == .ident and
            isErrorEnumTypeNameForLowering(tokens, tokens[i + 4].lexeme))
        {
            return tokens[i + 4].lexeme;
        }
        return null;
    }
    return null;
}

fn importedErrorNilAliasTarget(
    allocator: std.mem.Allocator,
    imported_alias_ctx: ?ImportedAliasContext,
    tokens: []const lexer.Token,
    name: []const u8,
) ?[]const u8 {
    const ctx = imported_alias_ctx orelse return null;
    const import_ref = findCodegenImportByAlias(tokens, name) orelse return null;
    const child_idx = findImportedModuleIndex(allocator, ctx.graph.modules, ctx.module_idx, import_ref) orelse return null;
    return errorNilAliasTarget(ctx.graph.modules[child_idx].tokens, import_ref.target);
}

fn isErrorEnumTypeNameForLowering(tokens: []const lexer.Token, name: []const u8) bool {
    return isErrorEnumType(tokens, name) or std.mem.endsWith(u8, name, "Error");
}

fn errorEnumBranchValue(tokens: []const lexer.Token, enum_name: []const u8, branch_name: []const u8) ?usize {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i + 3 < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, tokens[i].lexeme, enum_name)) continue;
        if (!tokEq(tokens[i + 1], "error") or !tokEq(tokens[i + 2], "=")) continue;

        const line_end = findLineEnd(tokens, i);
        var branch_idx: usize = 1;
        var j = i + 3;
        while (j < line_end) : (j += 1) {
            if (tokEq(tokens[j], "|")) continue;
            if (tokens[j].kind != .ident) return null;
            if (std.mem.eql(u8, tokens[j].lexeme, branch_name)) return branch_idx;
            branch_idx += 1;
        }
        return null;
    }
    return null;
}

fn freeHostImports(allocator: std.mem.Allocator, host_imports: []const HostImport) void {
    for (host_imports) |host_import| {
        if (host_import.owned_alias) allocator.free(host_import.alias);
        allocator.free(host_import.params);
    }
}

fn freeStructDecls(allocator: std.mem.Allocator, structs: []const StructDecl) void {
    for (structs) |decl| {
        freeStructDecl(allocator, decl);
    }
}

fn freeStructDecl(allocator: std.mem.Allocator, decl: StructDecl) void {
    if (decl.type_params.len != 0) allocator.free(decl.type_params);
    for (decl.owned_types) |owned| {
        allocator.free(owned);
    }
    if (decl.owned_types.len != 0) allocator.free(decl.owned_types);
    allocator.free(decl.fields);
}

fn freeStructLayouts(allocator: std.mem.Allocator, layouts: []const StructLayout) void {
    for (layouts) |layout| {
        allocator.free(layout.managed_fields);
    }
}

fn freeFuncDecls(allocator: std.mem.Allocator, funcs: []const FuncDecl) void {
    for (funcs) |func| {
        if (func.owned_name) allocator.free(func.name);
        if (func.type_params.len != 0) allocator.free(func.type_params);
        if (func.type_bindings.len != 0) allocator.free(func.type_bindings);
        for (func.owned_types) |owned| {
            allocator.free(owned);
        }
        if (func.owned_types.len != 0) allocator.free(func.owned_types);
        allocator.free(func.params);
        allocator.free(func.results);
    }
}

fn freeWasiHostImports(allocator: std.mem.Allocator, wasi_imports: []const WasiHostImport) void {
    for (wasi_imports) |import| {
        allocator.free(import.params);
        allocator.free(import.result);
    }
}

fn compactTokenText(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        try out.appendSlice(allocator, tokens[i].lexeme);
    }

    return out.toOwnedSlice(allocator);
}

fn appendWitTokenText(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) !void {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokens[i].kind == .ident and std.mem.eql(u8, tokens[i].lexeme, "text")) {
            try out.appendSlice(allocator, "string");
        } else {
            try out.appendSlice(allocator, tokens[i].lexeme);
        }
    }
}

fn compactWitTokenText(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try appendWitTokenText(allocator, &out, tokens, start_idx, end_idx);
    return out.toOwnedSlice(allocator);
}

fn appendDoSignatureAsWit(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    signature: []const u8,
) !void {
    var i: usize = 0;
    while (i < signature.len) {
        if (isWitIdentChar(signature[i])) {
            const start = i;
            while (i < signature.len and isWitIdentChar(signature[i])) : (i += 1) {}
            const ident = signature[start..i];
            if (std.mem.eql(u8, ident, "text")) {
                try out.appendSlice(allocator, "string");
            } else {
                try out.appendSlice(allocator, ident);
            }
            continue;
        }
        try out.append(allocator, signature[i]);
        i += 1;
    }
}

fn isWitIdentChar(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '-';
}

fn findHostImport(host_imports: []const HostImport, alias: []const u8) ?HostImport {
    for (host_imports) |host_import| {
        if (std.mem.eql(u8, host_import.alias, alias)) return host_import;
    }
    return null;
}

fn findHostImportForTokens(host_imports: []const HostImport, tokens: []const lexer.Token, alias: []const u8) ?HostImport {
    for (host_imports) |host_import| {
        if (!moduleTokensEqual(host_import.tokens, tokens)) continue;
        if (std.mem.eql(u8, host_import.source_alias, alias)) return host_import;
    }
    return findHostImport(host_imports, alias);
}

fn findWasiHostImport(wasi_imports: []const WasiHostImport, alias: []const u8) ?WasiHostImport {
    for (wasi_imports) |import| {
        if (std.mem.eql(u8, import.alias, alias)) return import;
    }
    return null;
}

fn findWasiHostImportBySource(wasi_imports: []const WasiHostImport, source: []const u8, alias: []const u8) ?WasiHostImport {
    for (wasi_imports) |import| {
        if (!std.mem.eql(u8, import.source, source)) continue;
        if (std.mem.eql(u8, import.alias, alias)) return import;
    }
    return null;
}

fn wasiLowering(import: WasiHostImport) ?WasiLowering {
    if (std.mem.eql(u8, import.target, "clocks/system-clock/now") and
        std.mem.eql(u8, import.params, "") and
        std.mem.eql(u8, import.result, "Datetime"))
    {
        return .{
            .module = "cm32p2|wasi:clocks/system-clock",
            .name = "now",
            .param = "i32",
            .result_record = "Datetime",
        };
    }
    if (std.mem.eql(u8, import.target, "clocks/system-clock/get-resolution") and
        std.mem.eql(u8, import.params, "") and
        std.mem.eql(u8, import.result, "u64"))
    {
        return .{ .module = "cm32p2|wasi:clocks/system-clock", .name = "get-resolution", .result = "i64" };
    }
    if (std.mem.eql(u8, import.target, "clocks/monotonic-clock/now") and
        std.mem.eql(u8, import.params, "") and
        std.mem.eql(u8, import.result, "u64"))
    {
        return .{ .module = "cm32p2|wasi:clocks/monotonic-clock", .name = "now", .result = "i64" };
    }
    if (std.mem.eql(u8, import.target, "clocks/monotonic-clock/get-resolution") and
        std.mem.eql(u8, import.params, "") and
        std.mem.eql(u8, import.result, "u64"))
    {
        return .{ .module = "cm32p2|wasi:clocks/monotonic-clock", .name = "get-resolution", .result = "i64" };
    }
    if (std.mem.eql(u8, import.target, "random/random/get-random-u64") and
        std.mem.eql(u8, import.params, "") and
        std.mem.eql(u8, import.result, "u64"))
    {
        return .{ .module = "cm32p2|wasi:random/random", .name = "get-random-u64", .result = "i64" };
    }
    if (std.mem.eql(u8, import.target, "random/random/get-random-bytes") and
        std.mem.eql(u8, import.params, "u64") and
        std.mem.eql(u8, import.result, "list<u8>"))
    {
        return .{ .module = "cm32p2|wasi:random/random", .name = "get-random-bytes", .param = "i64 i32", .result_storage_elem = "u8" };
    }
    if (std.mem.eql(u8, import.target, "filesystem/types/descriptor.sync") and
        std.mem.eql(u8, import.params, "descriptor") and
        std.mem.eql(u8, import.result, "result<_,error-code>"))
    {
        return .{ .module = "cm32p2|wasi:filesystem/types", .name = "[method]descriptor.sync", .param = "i32 i32", .result_unit_error = true };
    }
    if (std.mem.eql(u8, import.target, "filesystem/types/descriptor.link-at") and
        std.mem.eql(u8, import.params, "descriptor,path-flags,text,borrow<descriptor>,text") and
        std.mem.eql(u8, import.result, "result<_,error-code>"))
    {
        return .{
            .module = "cm32p2|wasi:filesystem/types",
            .name = "[method]descriptor.link-at",
            .param = "i32 i32 i32 i32 i32 i32 i32 i32",
            .result_unit_error = true,
            .result_link_at_error = true,
        };
    }
    if (std.mem.eql(u8, import.target, "filesystem/types/descriptor.create-directory-at") and
        std.mem.eql(u8, import.params, "descriptor,text") and
        std.mem.eql(u8, import.result, "result<_,error-code>"))
    {
        return .{ .module = "cm32p2|wasi:filesystem/types", .name = "[method]descriptor.create-directory-at", .param = "i32 i32 i32 i32", .result_unit_error = true };
    }
    if (std.mem.eql(u8, import.target, "filesystem/types/descriptor.remove-directory-at") and
        std.mem.eql(u8, import.params, "descriptor,text") and
        std.mem.eql(u8, import.result, "result<_,error-code>"))
    {
        return .{ .module = "cm32p2|wasi:filesystem/types", .name = "[method]descriptor.remove-directory-at", .param = "i32 i32 i32 i32", .result_unit_error = true };
    }
    if (std.mem.eql(u8, import.target, "filesystem/types/descriptor.write") and
        std.mem.eql(u8, import.params, "descriptor,list<u8>,filesize") and
        std.mem.eql(u8, import.result, "result<filesize,error-code>"))
    {
        return .{ .module = "cm32p2|wasi:filesystem/types", .name = "[method]descriptor.write", .param = "i32 i32 i32 i64 i32", .result_filesize_error = true };
    }
    if (std.mem.eql(u8, import.target, "filesystem/types/descriptor.read") and
        std.mem.eql(u8, import.params, "descriptor,filesize,filesize") and
        std.mem.eql(u8, import.result, "result<tuple<list<u8>,bool>,error-code>"))
    {
        return .{ .module = "cm32p2|wasi:filesystem/types", .name = "[method]descriptor.read", .param = "i32 i64 i64 i32", .result_read_error = true };
    }
    if (std.mem.eql(u8, import.target, "filesystem/types/descriptor.open-at") and
        std.mem.eql(u8, import.params, "descriptor,path-flags,text,open-flags,descriptor-flags") and
        std.mem.eql(u8, import.result, "result<descriptor,error-code>"))
    {
        return .{ .module = "cm32p2|wasi:filesystem/types", .name = "[method]descriptor.open-at", .param = "i32 i32 i32 i32 i32 i32 i32", .result_descriptor_error = true };
    }
    if (std.mem.eql(u8, import.target, "filesystem/types/descriptor.drop") and
        std.mem.eql(u8, import.params, "descriptor") and
        std.mem.eql(u8, import.result, "nil"))
    {
        return .{ .module = "cm32p2|wasi:filesystem/types", .name = "[resource-drop]descriptor", .param = "i32", .resource_drop = true };
    }
    if (std.mem.eql(u8, import.target, "io/streams/input-stream.read") and
        std.mem.eql(u8, import.params, "input-stream,u64") and
        std.mem.eql(u8, import.result, "result<list<u8>,stream-error>"))
    {
        return .{ .module = "cm32p2|wasi:io/streams", .name = "[method]input-stream.read", .param = "i32 i64 i32", .result_list_u8_error = true };
    }
    if (std.mem.eql(u8, import.target, "io/streams/output-stream.check-write") and
        std.mem.eql(u8, import.params, "output-stream") and
        std.mem.eql(u8, import.result, "result<u64,stream-error>"))
    {
        return .{ .module = "cm32p2|wasi:io/streams", .name = "[method]output-stream.check-write", .param = "i32 i32", .result_u64_stream_error = true };
    }
    if (std.mem.eql(u8, import.target, "io/streams/output-stream.write") and
        std.mem.eql(u8, import.params, "output-stream,list<u8>") and
        std.mem.eql(u8, import.result, "result<_,stream-error>"))
    {
        return .{ .module = "cm32p2|wasi:io/streams", .name = "[method]output-stream.write", .param = "i32 i32 i32 i32", .result_unit_error = true };
    }
    if (std.mem.eql(u8, import.target, "io/streams/output-stream.flush") and
        std.mem.eql(u8, import.params, "output-stream") and
        std.mem.eql(u8, import.result, "result<_,stream-error>"))
    {
        return .{ .module = "cm32p2|wasi:io/streams", .name = "[method]output-stream.flush", .param = "i32 i32", .result_unit_error = true };
    }
    return null;
}

fn appendWasiImportSymbol(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    target: []const u8,
) !void {
    try out.appendSlice(allocator, "__wasi_import_");
    for (target) |ch| {
        if (std.ascii.isAlphanumeric(ch) or ch == '_') {
            try out.append(allocator, ch);
        } else {
            try out.append(allocator, '_');
        }
    }
}

fn hasString(items: []const []const u8, target: []const u8) bool {
    for (items) |item| {
        if (std.mem.eql(u8, item, target)) return true;
    }
    return false;
}

fn isEnvHostImportStart(tokens: []const lexer.Token, idx: usize) bool {
    const line_end = findLineEnd(tokens, idx);
    if (idx + 6 >= line_end) return false;
    if (tokens[idx].kind != .ident) return false;
    if (!tokEq(tokens[idx + 1], "=")) return false;
    if (!tokEq(tokens[idx + 2], "@")) return false;
    if (tokens[idx + 3].kind != .ident or !std.mem.eql(u8, tokens[idx + 3].lexeme, "env")) return false;
    if (!tokEq(tokens[idx + 4], "(")) return false;
    if (tokens[idx + 5].kind != .string) return false;
    return findTopLevelToken(tokens, idx + 6, line_end - 1, ",") != null;
}

fn isWasiHostImportStart(tokens: []const lexer.Token, idx: usize) bool {
    const line_end = findLineEnd(tokens, idx);
    if (idx + 4 >= line_end) return false;
    if (tokens[idx].kind != .ident) return false;
    if (!tokEq(tokens[idx + 1], "=")) return false;
    if (!tokEq(tokens[idx + 2], "@")) return false;
    if (tokens[idx + 3].kind != .ident or !std.mem.eql(u8, tokens[idx + 3].lexeme, "wasi")) return false;
    return tokEq(tokens[idx + 4], "(");
}

fn stringTokenBody(s: []const u8) ?[]const u8 {
    if (s.len < 2) return null;
    if (s[0] != '"' or s[s.len - 1] != '"') return null;
    return s[1 .. s.len - 1];
}

fn isLineStart(tokens: []const lexer.Token, idx: usize) bool {
    return idx == 0 or tokens[idx - 1].line != tokens[idx].line;
}

fn findLineEnd(tokens: []const lexer.Token, start_idx: usize) usize {
    const line = tokens[start_idx].line;
    var i = start_idx;
    while (i < tokens.len and tokens[i].line == line) : (i += 1) {}
    return i;
}

fn isTypedBindingRhsCall(tokens: []const lexer.Token, call_idx: usize) bool {
    const line_start = findLineStart(tokens, call_idx);
    if (line_start + 3 > call_idx) return false;
    if (tokens[line_start].kind != .ident) return false;
    if (tokens[line_start + 1].kind != .ident) return false;
    const eq_idx = findTopLevelToken(tokens, line_start + 2, call_idx, "=") orelse return false;
    return eq_idx + 1 == call_idx;
}

fn isBareHostCallStatement(tokens: []const lexer.Token, call_idx: usize, close_paren: usize) bool {
    const line_start = findLineStart(tokens, call_idx);
    const line_end = findLineEnd(tokens, call_idx);
    return line_start == call_idx and close_paren + 1 == line_end;
}

fn hostCallArgsMatch(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, host_import: HostImport) bool {
    var param_idx: usize = 0;
    var arg_start = start_idx;
    while (arg_start < end_idx) {
        const arg_end = findArgEnd(tokens, arg_start, end_idx);
        if (stringLiteralArgLexeme(tokens, arg_start, arg_end)) |_| {
            if (!hostParamIsPtrLen(host_import, param_idx)) return false;
            param_idx += 2;
        } else if (hostArgCouldBeStoragePtrLenSyntax(tokens, arg_start, arg_end) and hostParamIsPtrLen(host_import, param_idx)) {
            param_idx += 2;
        } else {
            if (param_idx >= host_import.params.len) return false;
            param_idx += 1;
        }
        arg_start = arg_end;
        if (arg_start < end_idx) {
            if (!tokEq(tokens[arg_start], ",")) return false;
            arg_start += 1;
        }
    }
    return param_idx == host_import.params.len;
}

fn hostParamIsPtrLen(host_import: HostImport, param_idx: usize) bool {
    if (param_idx + 1 >= host_import.params.len) return false;
    return std.mem.eql(u8, host_import.params[param_idx], "i32") and
        std.mem.eql(u8, host_import.params[param_idx + 1], "i32");
}

fn hostArgCouldBeStoragePtrLenSyntax(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    const range = trimParens(tokens, start_idx, end_idx);
    return range.end == range.start + 1 and tokens[range.start].kind == .ident;
}

fn stringLiteralArgLexeme(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.end != range.start + 1) return null;
    const tok = tokens[range.start];
    if (tok.kind != .string) return null;
    if (tok.lexeme.len < 2 or tok.lexeme[0] != '"') return null;
    return tok.lexeme;
}

fn stmtContainsStringLiteral(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokens[i].kind != .string) continue;
        if (tokens[i].lexeme.len < 2 or tokens[i].lexeme[0] != '"') continue;
        return true;
    }
    return false;
}

fn stmtContainsNumericSelectIntrinsic(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (!tokEq(tokens[i], "@")) continue;
        if (tokens[i + 1].kind != .ident) continue;
        const name = tokens[i + 1].lexeme;
        if (std.mem.eql(u8, name, "abs") or std.mem.eql(u8, name, "min") or std.mem.eql(u8, name, "max")) {
            return true;
        }
    }
    return false;
}

fn isHostImportCallExpr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext) bool {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.start + 2 > range.end) return false;
    if (tokens[range.start].kind != .ident) return false;
    if (findHostImportForTokens(ctx.host_imports, tokens, tokens[range.start].lexeme) == null) return false;
    if (!tokEq(tokens[range.start + 1], "(")) return false;
    const close_paren = findMatchingInRange(tokens, range.start + 1, "(", ")", range.end) catch return false;
    return close_paren + 1 == range.end;
}

fn isWasiHostImportCallExpr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext) bool {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.start + 2 > range.end) return false;
    if (tokens[range.start].kind != .ident) return false;
    if (findWasiHostImportForTokens(ctx, tokens, tokens[range.start].lexeme) == null) return false;
    if (!tokEq(tokens[range.start + 1], "(")) return false;
    const close_paren = findMatchingInRange(tokens, range.start + 1, "(", ")", range.end) catch return false;
    return close_paren + 1 == range.end;
}

fn findLineStart(tokens: []const lexer.Token, idx: usize) usize {
    var i = idx;
    while (i > 0 and tokens[i - 1].line == tokens[idx].line) : (i -= 1) {}
    return i;
}

const Range = struct {
    start: usize,
    end: usize,
};

const ExprCallHead = struct {
    name_idx: usize,
    args_start: usize,
    args_end: usize,
    is_intrinsic: bool,
};

fn trimParens(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) Range {
    var start = start_idx;
    var end = end_idx;
    while (start + 1 < end and tokEq(tokens[start], "(")) {
        const close = findMatchingInRange(tokens, start, "(", ")", end) catch break;
        if (close + 1 != end) break;
        start += 1;
        end -= 1;
    }
    return .{ .start = start, .end = end };
}

fn exprCallHead(tokens: []const lexer.Token, range: Range) ?ExprCallHead {
    var name_idx = range.start;
    var is_intrinsic = false;
    if (tokEq(tokens[name_idx], "@")) {
        if (name_idx + 1 >= range.end) return null;
        name_idx += 1;
        is_intrinsic = true;
    }
    if (tokens[name_idx].kind != .ident) return null;
    if (name_idx + 1 >= range.end or !tokEq(tokens[name_idx + 1], "(")) return null;
    const close_paren = findMatchingInRange(tokens, name_idx + 1, "(", ")", range.end) catch return null;
    if (close_paren + 1 != range.end) return null;
    if (is_intrinsic and !isCoreWasmCallName(tokens[name_idx].lexeme)) return null;
    return .{
        .name_idx = name_idx,
        .args_start = name_idx + 2,
        .args_end = close_paren,
        .is_intrinsic = is_intrinsic,
    };
}

fn isTypedScalarBinding(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 3 >= end_idx) return false;
    if (tokens[start_idx].kind != .ident) return false;
    if (!isCoreWasmScalar(tokens[start_idx + 1].lexeme)) return false;
    return findTopLevelToken(tokens, start_idx + 2, end_idx, "=") != null;
}

fn inferredScalarBindingType(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    if (start_idx + 3 > end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (!tokEq(tokens[start_idx + 1], "=")) return null;
    const ty = inferExprType(tokens, start_idx + 2, end_idx, locals, ctx) orelse return null;
    if (!isCoreWasmScalar(ty)) return null;
    return ty;
}

fn inferredManagedPayloadBinding(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?ManagedPayloadBinding {
    if (start_idx + 3 > end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (!tokEq(tokens[start_idx + 1], "=")) return null;
    const ty = inferExprType(tokens, start_idx + 2, end_idx, locals, ctx) orelse return null;
    const elem_ty = managedPayloadElemTypeFromName(ty) orelse return null;
    return .{ .ty = ty, .elem_ty = elem_ty };
}

fn storageBindingElemType(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    if (start_idx + 5 >= end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    const parsed = parseStorageType(tokens, start_idx + 1, end_idx) orelse return null;
    if (findTopLevelToken(tokens, parsed.next_idx, end_idx, "=") == null) return null;
    return parsed.elem_ty;
}

const ManagedPayloadBinding = struct {
    ty: []const u8,
    elem_ty: []const u8,
};

fn managedPayloadBinding(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?ManagedPayloadBinding {
    if (start_idx + 3 >= end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (tokens[start_idx + 1].kind != .ident) return null;
    const ty = tokens[start_idx + 1].lexeme;
    if (storageElemTypeFromName(ty) != null) return null;
    const elem_ty = managedPayloadElemTypeFromName(ty) orelse return null;
    if (findTopLevelToken(tokens, start_idx + 2, end_idx, "=") == null) return null;
    return .{ .ty = ty, .elem_ty = elem_ty };
}

fn isManagedLocalAssignmentStmt(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) bool {
    if (start_idx + 2 >= end_idx) return false;
    if (tokens[start_idx].kind != .ident) return false;
    if (!tokEq(tokens[start_idx + 1], "=")) return false;
    const target_ty = findLocalType(locals.locals.items, tokens[start_idx].lexeme) orelse return false;
    return isManagedLocalType(target_ty, ctx);
}

fn isStorageU8Type(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    const parsed = parseStorageType(tokens, start_idx, end_idx) orelse return false;
    return std.mem.eql(u8, parsed.elem_ty, "u8");
}

const ParsedStorageType = struct {
    elem_ty: []const u8,
    next_idx: usize,
};

fn parseStorageType(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?ParsedStorageType {
    if (start_idx + 2 >= end_idx) return null;
    if (!tokEq(tokens[start_idx], "[")) return null;
    if (tokens[start_idx + 1].kind != .ident) return null;
    if (!tokEq(tokens[start_idx + 2], "]")) return null;
    return .{
        .elem_ty = tokens[start_idx + 1].lexeme,
        .next_idx = start_idx + 3,
    };
}

fn typedStructBinding(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    structs: []const StructDecl,
) ?StructDecl {
    if (start_idx + 3 >= end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (tokens[start_idx + 1].kind != .ident) return null;
    const decl = findStructDecl(structs, tokens[start_idx + 1].lexeme) orelse return null;
    if (findTopLevelToken(tokens, start_idx + 2, end_idx, "=") == null) return null;
    return decl;
}

fn inferredStructCtorBinding(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    structs: []const StructDecl,
) ?StructDecl {
    if (start_idx + 4 > end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (!tokEq(tokens[start_idx + 1], "=")) return null;
    if (tokens[start_idx + 2].kind != .ident) return null;
    if (!tokEq(tokens[start_idx + 3], "{")) return null;
    const close_brace = findMatchingInRange(tokens, start_idx + 3, "{", "}", end_idx) catch return null;
    if (close_brace + 1 != end_idx) return null;
    return findStructDecl(structs, tokens[start_idx + 2].lexeme);
}

fn emitLenCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    out: *std.ArrayList(u8),
) !bool {
    const arg_end = findArgEnd(tokens, start_idx, end_idx);
    if (arg_end != start_idx + 1 or arg_end != end_idx) return false;
    if (tokens[start_idx].kind != .ident) return false;
    if (findStorageLocal(locals.storage_locals.items, tokens[start_idx].lexeme) == null) return false;
    try emitStorageLenPtr(allocator, out, tokens[start_idx].lexeme);
    try out.appendSlice(allocator, "    i32.load\n");
    return true;
}

fn emitGetCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !bool {
    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1) return false;
    if (tokens[start_idx].kind != .ident) return false;
    if (first_end >= end_idx or !tokEq(tokens[first_end], ",")) return false;

    const name = tokens[start_idx].lexeme;
    const second_start = first_end + 1;
    const second_end = findArgEnd(tokens, second_start, end_idx);
    if (second_end != end_idx) return false;

    if (findStorageLocal(locals.storage_locals.items, name)) |storage| {
        const elem_bytes = storageElementByteWidthForType(storage.elem_ty, ctx) orelse return false;
        try emitStorageBoundsCheck(allocator, tokens, second_start, second_end, locals, ctx, name, 1, out);
        try emitStorageDataPtr(allocator, out, name);
        if (!try emitExpr(allocator, tokens, second_start, second_end, locals, ctx, "usize", out)) return false;
        if (elem_bytes != 1) {
            try appendFmt(allocator, out, "    i32.const {d}\n", .{elem_bytes});
            try out.appendSlice(allocator, "    i32.mul\n");
        }
        try out.appendSlice(allocator, "    i32.add\n");
        try appendLoadForPayloadType(allocator, out, storage.elem_ty);
        if (isManagedLocalType(storage.elem_ty, ctx)) {
            try out.appendSlice(allocator, "    ;; storage-managed-get-inc\n");
            try out.appendSlice(allocator, "    call $__do_arc_inc\n");
        }
        return true;
    }

    if (findStructLocal(locals.struct_locals.items, name)) |struct_local| {
        if (second_end != second_start + 1 or !isDotIdent(tokens[second_start].lexeme)) return false;
        const field_name = publicDeclName(tokens[second_start].lexeme);
        if (findStructLayout(ctx.struct_layouts, struct_local.ty)) |layout| {
            const decl = findStructDecl(ctx.structs, struct_local.ty) orelse return false;
            const field_ty = findStructFieldType(decl, field_name) orelse return false;
            const field_offset = structFieldPayloadOffset(decl, field_name) orelse return false;
            try appendFmt(allocator, out, "    local.get ${s}\n", .{name});
            try out.appendSlice(allocator, "    call $__do_arc_payload\n");
            try appendFmt(allocator, out, "    i32.const {d}\n", .{field_offset});
            try out.appendSlice(allocator, "    i32.add\n");
            try appendLoadForPayloadType(allocator, out, field_ty);
            if (isManagedStructField(layout, field_name)) {
                try out.appendSlice(allocator, "    call $__do_arc_inc\n");
            }
            return true;
        }
        try appendFmt(allocator, out, "    local.get ${s}.{s}\n", .{
            name,
            field_name,
        });
        return true;
    }

    return false;
}

fn emitMemoryLoadCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    call_name: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !bool {
    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1) return false;
    if (tokens[start_idx].kind != .ident) return false;
    if (findStorageLocal(locals.storage_locals.items, tokens[start_idx].lexeme) == null) return false;
    if (first_end >= end_idx or !tokEq(tokens[first_end], ",")) return false;

    const second_start = first_end + 1;
    const second_end = findArgEnd(tokens, second_start, end_idx);
    if (second_end != end_idx) return false;

    const op = memoryLoadWasmOp(call_name) orelse return false;
    const width = memoryLoadByteWidth(call_name) orelse return false;
    try emitStorageBoundsCheck(allocator, tokens, second_start, second_end, locals, ctx, tokens[start_idx].lexeme, width, out);
    try emitStorageDataPtr(allocator, out, tokens[start_idx].lexeme);
    if (!try emitExpr(allocator, tokens, second_start, second_end, locals, ctx, "usize", out)) return false;
    try out.appendSlice(allocator, "    i32.add\n");
    try appendFmt(allocator, out, "    {s}\n", .{op});
    return true;
}

fn emitStorageBoundsCheck(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    offset_start: usize,
    offset_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    storage_name: []const u8,
    width: usize,
    out: *std.ArrayList(u8),
) !void {
    try appendFmt(allocator, out, "    local.get ${s}\n", .{storage_name});
    if (!try emitExpr(allocator, tokens, offset_start, offset_end, locals, ctx, "usize", out)) return error.NoMatchingCall;
    try appendFmt(allocator, out, "    i32.const {d}\n", .{width});
    try out.appendSlice(allocator, "    call $__do_storage_check_range\n");
}

fn emitStorageWriteExpr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    target_name: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const range = trimParens(tokens, start_idx, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return false;
    if (!call_head.is_intrinsic) return false;
    const call_name = tokens[call_head.name_idx].lexeme;
    if (std.mem.eql(u8, call_name, "set")) {
        return try emitStorageSetCall(allocator, tokens, call_head.args_start, call_head.args_end, target_name, locals, ctx, out);
    }
    if (std.mem.eql(u8, call_name, "put")) {
        return try emitStoragePutCall(allocator, tokens, call_head.args_start, call_head.args_end, target_name, locals, ctx, out);
    }
    return false;
}

fn emitStorageSetCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    target_name: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1) return false;
    if (tokens[start_idx].kind != .ident) return false;
    const storage = findStorageLocal(locals.storage_locals.items, tokens[start_idx].lexeme) orelse return false;
    if (first_end >= end_idx or !tokEq(tokens[first_end], ",")) return false;

    const index_start = first_end + 1;
    const index_end = findArgEnd(tokens, index_start, end_idx);
    if (index_end >= end_idx or !tokEq(tokens[index_end], ",")) return false;

    const value_start = index_end + 1;
    const value_end = findArgEnd(tokens, value_start, end_idx);
    if (value_end != end_idx) return false;

    if (isManagedLocalType(storage.elem_ty, ctx)) {
        return try emitStorageSetManagedCall(allocator, tokens, index_start, index_end, value_start, value_end, tokens[start_idx].lexeme, target_name, storage.elem_ty, locals, ctx, out);
    }
    if (!std.mem.eql(u8, storage.elem_ty, "u8")) {
        return try emitStorageSetScalarCall(allocator, tokens, index_start, index_end, value_start, value_end, tokens[start_idx].lexeme, target_name, storage.elem_ty, locals, ctx, out);
    }

    try emitStorageAliasProtect(allocator, out, tokens[start_idx].lexeme, target_name);
    try appendFmt(allocator, out, "    local.get ${s}\n", .{tokens[start_idx].lexeme});
    if (!try emitExpr(allocator, tokens, index_start, index_end, locals, ctx, "usize", out)) return false;
    if (!try emitExpr(allocator, tokens, value_start, value_end, locals, ctx, "u8", out)) return false;
    try out.appendSlice(allocator, "    call $__do_storage_set_u8\n");
    try emitStorageAliasRelease(allocator, out, tokens[start_idx].lexeme, target_name);
    return true;
}

fn emitStoragePutCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    target_name: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1) return false;
    if (tokens[start_idx].kind != .ident) return false;
    const storage = findStorageLocal(locals.storage_locals.items, tokens[start_idx].lexeme) orelse return false;
    if (first_end >= end_idx or !tokEq(tokens[first_end], ",")) return false;

    const value_start = first_end + 1;
    const value_end = findArgEnd(tokens, value_start, end_idx);
    if (value_end != end_idx) return false;

    if (isManagedLocalType(storage.elem_ty, ctx)) {
        return try emitStoragePutManagedCall(allocator, tokens, value_start, value_end, tokens[start_idx].lexeme, target_name, storage.elem_ty, locals, ctx, out);
    }
    if (!std.mem.eql(u8, storage.elem_ty, "u8")) {
        return try emitStoragePutScalarCall(allocator, tokens, value_start, value_end, tokens[start_idx].lexeme, target_name, storage.elem_ty, locals, ctx, out);
    }

    try emitStorageAliasProtect(allocator, out, tokens[start_idx].lexeme, target_name);
    try appendFmt(allocator, out, "    local.get ${s}\n", .{tokens[start_idx].lexeme});
    if (!try emitExpr(allocator, tokens, value_start, value_end, locals, ctx, "u8", out)) return false;
    try out.appendSlice(allocator, "    call $__do_storage_put_u8\n");
    try emitStorageAliasRelease(allocator, out, tokens[start_idx].lexeme, target_name);
    return true;
}

fn emitStorageSetScalarCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    index_start: usize,
    index_end: usize,
    value_start: usize,
    value_end: usize,
    source_name: []const u8,
    target_name: []const u8,
    elem_ty: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const elem_bytes = storageElementByteWidth(elem_ty) orelse return false;
    try out.appendSlice(allocator, "    ;; storage-set-scalar\n");
    try emitStorageAliasProtect(allocator, out, source_name, target_name);
    if (!try emitExpr(allocator, tokens, index_start, index_end, locals, ctx, "usize", out)) return false;
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{source_name});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try out.appendSlice(allocator, "    i32.const 1\n");
    try out.appendSlice(allocator, "    call $__do_storage_check_range\n");
    try appendFmt(allocator, out, "    local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "    call $__do_arc_rc\n");
    try out.appendSlice(allocator, "    i32.const 1\n");
    try out.appendSlice(allocator, "    i32.eq\n");
    try out.appendSlice(allocator, "    if (result i32)\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "    else\n");
    try emitStorageCloneCurrentLen(allocator, out, source_name, elem_bytes);
    try out.appendSlice(allocator, "    end\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try emitStorageElementPtrFromLocal(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, elem_bytes);
    if (!try emitExpr(allocator, tokens, value_start, value_end, locals, ctx, elem_ty, out)) return false;
    try appendStoreForPayloadType(allocator, out, elem_ty);
    try emitStorageAliasRelease(allocator, out, source_name, target_name);
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    return true;
}

fn emitStoragePutScalarCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    value_start: usize,
    value_end: usize,
    source_name: []const u8,
    target_name: []const u8,
    elem_ty: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const elem_bytes = storageElementByteWidth(elem_ty) orelse return false;
    try out.appendSlice(allocator, "    ;; storage-put-scalar\n");
    try emitStorageAliasProtect(allocator, out, source_name, target_name);
    try emitStorageLenPtr(allocator, out, source_name);
    try out.appendSlice(allocator, "    i32.load\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "    call $__do_arc_rc\n");
    try out.appendSlice(allocator, "    i32.const 1\n");
    try out.appendSlice(allocator, "    i32.eq\n");
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try emitStorageCapPtr(allocator, out, source_name);
    try out.appendSlice(allocator, "    i32.load\n");
    try out.appendSlice(allocator, "    i32.lt_u\n");
    try out.appendSlice(allocator, "    i32.and\n");
    try out.appendSlice(allocator, "    if (result i32)\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "    else\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try out.appendSlice(allocator, "      i32.const 1\n");
    try out.appendSlice(allocator, "      i32.add\n");
    try appendFmt(allocator, out, "      local.set ${s}\n", .{STORAGE_WRITE_LEN_TMP_LOCAL});
    try emitStorageCloneWithLenLocal(allocator, out, source_name, elem_bytes, STORAGE_WRITE_LEN_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL);
    try out.appendSlice(allocator, "    end\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try emitStorageElementPtrFromLocal(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, elem_bytes);
    if (!try emitExpr(allocator, tokens, value_start, value_end, locals, ctx, elem_ty, out)) return false;
    try appendStoreForPayloadType(allocator, out, elem_ty);
    try emitStorageLenPtr(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL);
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try out.appendSlice(allocator, "    i32.const 1\n");
    try out.appendSlice(allocator, "    i32.add\n");
    try out.appendSlice(allocator, "    i32.store\n");
    try emitStorageAliasRelease(allocator, out, source_name, target_name);
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    return true;
}

fn emitStorageSetManagedCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    index_start: usize,
    index_end: usize,
    value_start: usize,
    value_end: usize,
    source_name: []const u8,
    target_name: []const u8,
    elem_ty: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    try out.appendSlice(allocator, "    ;; storage-set-managed\n");
    try emitStorageAliasProtect(allocator, out, source_name, target_name);
    if (!try emitExpr(allocator, tokens, index_start, index_end, locals, ctx, "usize", out)) return false;
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{source_name});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try out.appendSlice(allocator, "    i32.const 1\n");
    try out.appendSlice(allocator, "    call $__do_storage_check_range\n");
    try appendFmt(allocator, out, "    local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "    call $__do_arc_rc\n");
    try out.appendSlice(allocator, "    i32.const 1\n");
    try out.appendSlice(allocator, "    i32.eq\n");
    try out.appendSlice(allocator, "    if (result i32)\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "    else\n");
    try emitStorageCloneManagedCurrentLen(allocator, out, source_name);
    try out.appendSlice(allocator, "    end\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try emitStorageElementPtrFromLocal(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, 4);
    try out.appendSlice(allocator, "    i32.load\n");
    try out.appendSlice(allocator, "    ;; storage-managed-overwrite-dec\n");
    try out.appendSlice(allocator, "    call $__do_arc_dec\n");
    try emitStorageElementPtrFromLocal(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, 4);
    if (!try emitManagedStorageValue(allocator, tokens, value_start, value_end, elem_ty, locals, ctx, out)) return false;
    try out.appendSlice(allocator, "    i32.store\n");
    try emitStorageAliasRelease(allocator, out, source_name, target_name);
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    return true;
}

fn emitStoragePutManagedCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    value_start: usize,
    value_end: usize,
    source_name: []const u8,
    target_name: []const u8,
    elem_ty: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    try out.appendSlice(allocator, "    ;; storage-put-managed\n");
    try emitStorageAliasProtect(allocator, out, source_name, target_name);
    try emitStorageLenPtr(allocator, out, source_name);
    try out.appendSlice(allocator, "    i32.load\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "    call $__do_arc_rc\n");
    try out.appendSlice(allocator, "    i32.const 1\n");
    try out.appendSlice(allocator, "    i32.eq\n");
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try emitStorageCapPtr(allocator, out, source_name);
    try out.appendSlice(allocator, "    i32.load\n");
    try out.appendSlice(allocator, "    i32.lt_u\n");
    try out.appendSlice(allocator, "    i32.and\n");
    try out.appendSlice(allocator, "    if (result i32)\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "    else\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try out.appendSlice(allocator, "      i32.const 1\n");
    try out.appendSlice(allocator, "      i32.add\n");
    try appendFmt(allocator, out, "      local.set ${s}\n", .{STORAGE_WRITE_LEN_TMP_LOCAL});
    try emitStorageCloneManagedWithLenLocal(allocator, out, source_name, STORAGE_WRITE_LEN_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL);
    try out.appendSlice(allocator, "    end\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try emitStorageElementPtrFromLocal(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, 4);
    if (!try emitManagedStorageValue(allocator, tokens, value_start, value_end, elem_ty, locals, ctx, out)) return false;
    try out.appendSlice(allocator, "    i32.store\n");
    try emitStorageLenPtr(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL);
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try out.appendSlice(allocator, "    i32.const 1\n");
    try out.appendSlice(allocator, "    i32.add\n");
    try out.appendSlice(allocator, "    i32.store\n");
    try emitStorageAliasRelease(allocator, out, source_name, target_name);
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    return true;
}

fn emitManagedStorageValue(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    elem_ty: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (!try emitExpr(allocator, tokens, start_idx, end_idx, locals, ctx, elem_ty, out)) return false;
    if (isDirectManagedLocalExpr(tokens, start_idx, end_idx, locals, ctx)) {
        try out.appendSlice(allocator, "    ;; storage-managed-write-inc\n");
        try out.appendSlice(allocator, "    call $__do_arc_inc\n");
    }
    return true;
}

fn emitStorageCloneCurrentLen(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    source_name: []const u8,
    elem_bytes: usize,
) !void {
    try emitStorageLenPtr(allocator, out, source_name);
    try out.appendSlice(allocator, "      i32.load\n");
    try appendFmt(allocator, out, "      local.set ${s}\n", .{STORAGE_WRITE_LEN_TMP_LOCAL});
    try emitStorageCloneWithLenLocal(allocator, out, source_name, elem_bytes, STORAGE_WRITE_LEN_TMP_LOCAL, STORAGE_WRITE_LEN_TMP_LOCAL);
}

fn emitStorageCloneManagedCurrentLen(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    source_name: []const u8,
) !void {
    try emitStorageLenPtr(allocator, out, source_name);
    try out.appendSlice(allocator, "      i32.load\n");
    try appendFmt(allocator, out, "      local.set ${s}\n", .{STORAGE_WRITE_LEN_TMP_LOCAL});
    try emitStorageCloneManagedWithLenLocal(allocator, out, source_name, STORAGE_WRITE_LEN_TMP_LOCAL, STORAGE_WRITE_LEN_TMP_LOCAL);
}

fn emitStorageCloneManagedWithLenLocal(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    source_name: []const u8,
    next_len_local: []const u8,
    copy_len_local: []const u8,
) !void {
    try appendFmt(allocator, out, "      local.get ${s}\n", .{next_len_local});
    try out.appendSlice(allocator, "      i32.const 4\n");
    try out.appendSlice(allocator, "      i32.mul\n");
    try appendFmt(allocator, out, "      i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES});
    try out.appendSlice(allocator, "      i32.add\n");
    try appendFmt(allocator, out, "      i32.const {d}\n", .{TYPE_ID_STORAGE_MANAGED});
    try out.appendSlice(allocator, "      call $__do_arc_alloc\n");
    try appendFmt(allocator, out, "      local.set ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try out.appendSlice(allocator, "      call $__do_arc_payload\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{next_len_local});
    try out.appendSlice(allocator, "      i32.store\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try out.appendSlice(allocator, "      call $__do_arc_payload\n");
    try out.appendSlice(allocator, "      i32.const 4\n");
    try out.appendSlice(allocator, "      i32.add\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{next_len_local});
    try out.appendSlice(allocator, "      i32.store\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try out.appendSlice(allocator, "      call $__do_arc_payload\n");
    try appendFmt(allocator, out, "      i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES});
    try out.appendSlice(allocator, "      i32.add\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "      call $__do_arc_payload\n");
    try appendFmt(allocator, out, "      i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES});
    try out.appendSlice(allocator, "      i32.add\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{copy_len_local});
    try out.appendSlice(allocator, "      i32.const 4\n");
    try out.appendSlice(allocator, "      i32.mul\n");
    try out.appendSlice(allocator, "      memory.copy\n");
    try emitStorageIncCopiedManagedElements(allocator, out, STORAGE_WRITE_NEXT_TMP_LOCAL, copy_len_local);
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
}

fn emitStorageIncCopiedManagedElements(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    storage_local: []const u8,
    copy_len_local: []const u8,
) !void {
    try out.appendSlice(allocator, "      ;; storage-managed-clone-inc\n");
    try out.appendSlice(allocator, "      i32.const 0\n");
    try appendFmt(allocator, out, "      local.set ${s}\n", .{STORAGE_WRITE_SCAN_TMP_LOCAL});
    try out.appendSlice(allocator, "      block $storage_clone_inc_done\n");
    try out.appendSlice(allocator, "        loop $storage_clone_inc_scan\n");
    try appendFmt(allocator, out, "          local.get ${s}\n", .{STORAGE_WRITE_SCAN_TMP_LOCAL});
    try appendFmt(allocator, out, "          local.get ${s}\n", .{copy_len_local});
    try out.appendSlice(allocator, "          i32.ge_u\n");
    try out.appendSlice(allocator, "          br_if $storage_clone_inc_done\n");
    try appendFmt(allocator, out, "          local.get ${s}\n", .{storage_local});
    try out.appendSlice(allocator, "          call $__do_arc_payload\n");
    try appendFmt(allocator, out, "          i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES});
    try out.appendSlice(allocator, "          i32.add\n");
    try appendFmt(allocator, out, "          local.get ${s}\n", .{STORAGE_WRITE_SCAN_TMP_LOCAL});
    try out.appendSlice(allocator, "          i32.const 4\n");
    try out.appendSlice(allocator, "          i32.mul\n");
    try out.appendSlice(allocator, "          i32.add\n");
    try out.appendSlice(allocator, "          i32.load\n");
    try out.appendSlice(allocator, "          call $__do_arc_inc\n");
    try out.appendSlice(allocator, "          drop\n");
    try appendFmt(allocator, out, "          local.get ${s}\n", .{STORAGE_WRITE_SCAN_TMP_LOCAL});
    try out.appendSlice(allocator, "          i32.const 1\n");
    try out.appendSlice(allocator, "          i32.add\n");
    try appendFmt(allocator, out, "          local.set ${s}\n", .{STORAGE_WRITE_SCAN_TMP_LOCAL});
    try out.appendSlice(allocator, "          br $storage_clone_inc_scan\n");
    try out.appendSlice(allocator, "        end\n");
    try out.appendSlice(allocator, "      end\n");
}

fn emitStorageCloneWithLenLocal(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    source_name: []const u8,
    elem_bytes: usize,
    next_len_local: []const u8,
    copy_len_local: []const u8,
) !void {
    try appendFmt(allocator, out, "      local.get ${s}\n", .{next_len_local});
    if (elem_bytes != 1) {
        try appendFmt(allocator, out, "      i32.const {d}\n", .{elem_bytes});
        try out.appendSlice(allocator, "      i32.mul\n");
    }
    try appendFmt(allocator, out, "      i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES});
    try out.appendSlice(allocator, "      i32.add\n");
    try appendFmt(allocator, out, "      i32.const {d}\n", .{TYPE_ID_STORAGE_U8});
    try out.appendSlice(allocator, "      call $__do_arc_alloc\n");
    try appendFmt(allocator, out, "      local.set ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try out.appendSlice(allocator, "      call $__do_arc_payload\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{next_len_local});
    try out.appendSlice(allocator, "      i32.store\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try out.appendSlice(allocator, "      call $__do_arc_payload\n");
    try out.appendSlice(allocator, "      i32.const 4\n");
    try out.appendSlice(allocator, "      i32.add\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{next_len_local});
    try out.appendSlice(allocator, "      i32.store\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try out.appendSlice(allocator, "      call $__do_arc_payload\n");
    try appendFmt(allocator, out, "      i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES});
    try out.appendSlice(allocator, "      i32.add\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "      call $__do_arc_payload\n");
    try appendFmt(allocator, out, "      i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES});
    try out.appendSlice(allocator, "      i32.add\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{copy_len_local});
    if (elem_bytes != 1) {
        try appendFmt(allocator, out, "      i32.const {d}\n", .{elem_bytes});
        try out.appendSlice(allocator, "      i32.mul\n");
    }
    try out.appendSlice(allocator, "      memory.copy\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
}

fn emitStorageElementPtrFromLocal(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    storage_local: []const u8,
    index_local: []const u8,
    elem_bytes: usize,
) !void {
    try appendFmt(allocator, out, "    local.get ${s}\n", .{storage_local});
    try out.appendSlice(allocator, "    call $__do_arc_payload\n");
    try appendFmt(allocator, out, "    i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES});
    try out.appendSlice(allocator, "    i32.add\n");
    try appendFmt(allocator, out, "    local.get ${s}\n", .{index_local});
    if (elem_bytes != 1) {
        try appendFmt(allocator, out, "    i32.const {d}\n", .{elem_bytes});
        try out.appendSlice(allocator, "    i32.mul\n");
    }
    try out.appendSlice(allocator, "    i32.add\n");
}

fn emitStorageAliasProtect(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    source_name: []const u8,
    target_name: []const u8,
) !void {
    if (std.mem.eql(u8, source_name, target_name)) return;
    try appendFmt(allocator, out, "    local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "    call $__do_arc_inc\n");
    try out.appendSlice(allocator, "    drop\n");
}

fn emitStorageAliasRelease(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    source_name: []const u8,
    target_name: []const u8,
) !void {
    if (std.mem.eql(u8, source_name, target_name)) return;
    try appendFmt(allocator, out, "    local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "    call $__do_arc_dec\n");
}

fn emitScalarConvertCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    target_ty: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !bool {
    const arg_end = findArgEnd(tokens, start_idx, end_idx);
    if (arg_end != end_idx) return false;
    if (!isCoreWasmScalar(target_ty)) return false;

    const source_ty = inferExprType(tokens, start_idx, arg_end, locals, ctx) orelse target_ty;
    if (!isCoreWasmScalar(source_ty)) return false;
    if (!try emitExpr(allocator, tokens, start_idx, arg_end, locals, ctx, source_ty, out)) return false;
    if (scalarConvertWasmOp(source_ty, target_ty)) |op| {
        try appendFmt(allocator, out, "    {s}\n", .{op});
    }
    return true;
}

fn emitWasiHostImportExpr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    allow_statement_result: bool,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const lowering = wasiLowering(import) orelse return false;
    if (lowering.resource_drop) {
        if (!allow_statement_result) return false;
        return try emitWasiResourceDropCall(allocator, tokens, args_start, args_end, locals, ctx, import, out);
    }
    if (lowering.result_storage_elem) |elem_ty| {
        if (!std.mem.eql(u8, elem_ty, "u8")) return false;
        return try emitWasiListU8ResultCall(allocator, tokens, args_start, args_end, locals, ctx, import, out);
    }
    if (lowering.result_unit_error) {
        if (!allow_statement_result) return false;
        return try emitWasiResultUnitCall(allocator, tokens, args_start, args_end, locals, ctx, import, out);
    }
    if (lowering.result_list_u8_error) return false;
    if (lowering.result_filesize_error) {
        if (!allow_statement_result) return false;
        return try emitWasiResultFilesizeCall(allocator, tokens, args_start, args_end, locals, ctx, import, out);
    }
    if (lowering.result_u64_stream_error) {
        if (!allow_statement_result) return false;
        return try emitWasiResultU64StreamCall(allocator, tokens, args_start, args_end, locals, ctx, import, out);
    }
    if (lowering.result_record != null) return false;
    if (lowering.result == null) return false;
    if (args_start != args_end) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    call $");
    try appendWasiImportSymbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}

fn emitWasiResourceDropCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const arg_end = findArgEnd(tokens, args_start, args_end);
    if (arg_end != args_end) return error.NoMatchingCall;
    if (!try emitExpr(allocator, tokens, args_start, arg_end, locals, ctx, "i32", out)) {
        return error.NoMatchingCall;
    }
    try out.appendSlice(allocator, "    call $");
    try appendWasiImportSymbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}

fn emitWasiListU8ResultCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (!std.mem.eql(u8, import.target, "random/random/get-random-bytes")) return false;
    const arg_end = findArgEnd(tokens, args_start, args_end);
    if (arg_end == args_start or arg_end != args_end) return error.NoMatchingCall;
    if (!try emitExpr(allocator, tokens, args_start, arg_end, locals, ctx, "u64", out)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__do_wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try appendWasiImportSymbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    try out.appendSlice(allocator,
        \\    global.get $__do_wasi_result_area_base
        \\    i32.load
        \\    global.get $__do_wasi_result_area_base
        \\    i32.const 4
        \\    i32.add
        \\    i32.load
        \\    call $__do_wasi_list_u8_to_storage
        \\
    );
    return true;
}

fn emitWasiResultUnitCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (std.mem.eql(u8, import.target, "filesystem/types/descriptor.link-at")) {
        return try emitWasiResultLinkAtCall(allocator, tokens, args_start, args_end, locals, ctx, import, out);
    }
    if (std.mem.eql(u8, import.target, "filesystem/types/descriptor.create-directory-at") or
        std.mem.eql(u8, import.target, "filesystem/types/descriptor.remove-directory-at"))
    {
        return try emitWasiResultDescriptorPathCall(allocator, tokens, args_start, args_end, locals, ctx, import, out);
    }
    if (std.mem.eql(u8, import.target, "io/streams/output-stream.write")) {
        return try emitWasiResultOutputWriteCall(allocator, tokens, args_start, args_end, locals, ctx, import, out);
    }
    if (!std.mem.eql(u8, import.target, "filesystem/types/descriptor.sync") and
        !std.mem.eql(u8, import.target, "io/streams/output-stream.flush"))
    {
        return false;
    }
    const arg_end = findArgEnd(tokens, args_start, args_end);
    if (arg_end == args_start or arg_end != args_end) return error.NoMatchingCall;
    if (!try emitExpr(allocator, tokens, args_start, arg_end, locals, ctx, "i32", out)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__do_wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try appendWasiImportSymbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}

fn emitWasiResultDescriptorPathCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (!std.mem.eql(u8, import.target, "filesystem/types/descriptor.create-directory-at") and
        !std.mem.eql(u8, import.target, "filesystem/types/descriptor.remove-directory-at"))
    {
        return false;
    }

    const descriptor_end = findArgEnd(tokens, args_start, args_end);
    if (descriptor_end == args_start or descriptor_end >= args_end or !tokEq(tokens[descriptor_end], ",")) return error.NoMatchingCall;
    const path_start = descriptor_end + 1;
    const path_end = findArgEnd(tokens, path_start, args_end);
    if (path_end == path_start or path_end != args_end) return error.NoMatchingCall;

    if (!try emitExpr(allocator, tokens, args_start, descriptor_end, locals, ctx, "i32", out)) return error.NoMatchingCall;
    if (!try emitWasiStringArg(allocator, tokens, path_start, path_end, locals, ctx, out)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__do_wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try appendWasiImportSymbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}

fn emitWasiResultOutputWriteCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (!std.mem.eql(u8, import.target, "io/streams/output-stream.write")) return false;

    const stream_end = findArgEnd(tokens, args_start, args_end);
    if (stream_end == args_start or stream_end >= args_end or !tokEq(tokens[stream_end], ",")) return error.NoMatchingCall;
    const data_start = stream_end + 1;
    const data_end = findArgEnd(tokens, data_start, args_end);
    if (data_end == data_start or data_end != args_end) return error.NoMatchingCall;

    if (!try emitExpr(allocator, tokens, args_start, stream_end, locals, ctx, "i32", out)) return error.NoMatchingCall;
    if (!try emitWasiListU8Arg(allocator, tokens, data_start, data_end, locals, out)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__do_wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try appendWasiImportSymbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}

fn emitWasiResultDescriptorCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (!std.mem.eql(u8, import.target, "filesystem/types/descriptor.open-at")) return false;

    const descriptor_end = findArgEnd(tokens, args_start, args_end);
    if (descriptor_end == args_start or descriptor_end >= args_end or !tokEq(tokens[descriptor_end], ",")) return error.NoMatchingCall;
    const path_flags_start = descriptor_end + 1;
    const path_flags_end = findArgEnd(tokens, path_flags_start, args_end);
    if (path_flags_end == path_flags_start or path_flags_end >= args_end or !tokEq(tokens[path_flags_end], ",")) return error.NoMatchingCall;
    const path_start = path_flags_end + 1;
    const path_end = findArgEnd(tokens, path_start, args_end);
    if (path_end == path_start or path_end >= args_end or !tokEq(tokens[path_end], ",")) return error.NoMatchingCall;
    const open_flags_start = path_end + 1;
    const open_flags_end = findArgEnd(tokens, open_flags_start, args_end);
    if (open_flags_end == open_flags_start or open_flags_end >= args_end or !tokEq(tokens[open_flags_end], ",")) return error.NoMatchingCall;
    const descriptor_flags_start = open_flags_end + 1;
    const descriptor_flags_end = findArgEnd(tokens, descriptor_flags_start, args_end);
    if (descriptor_flags_end == descriptor_flags_start or descriptor_flags_end != args_end) return error.NoMatchingCall;

    if (!try emitExpr(allocator, tokens, args_start, descriptor_end, locals, ctx, "i32", out)) return error.NoMatchingCall;
    if (!try emitExpr(allocator, tokens, path_flags_start, path_flags_end, locals, ctx, "i32", out)) return error.NoMatchingCall;
    if (!try emitWasiStringArg(allocator, tokens, path_start, path_end, locals, ctx, out)) return error.NoMatchingCall;
    if (!try emitExpr(allocator, tokens, open_flags_start, open_flags_end, locals, ctx, "i32", out)) return error.NoMatchingCall;
    if (!try emitExpr(allocator, tokens, descriptor_flags_start, descriptor_flags_end, locals, ctx, "i32", out)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__do_wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try appendWasiImportSymbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}

fn emitWasiResultLinkAtCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (!std.mem.eql(u8, import.target, "filesystem/types/descriptor.link-at")) return false;
    const args = parseWasiLinkAtArgs(tokens, args_start, args_end) orelse return error.NoMatchingCall;

    if (!try emitExpr(allocator, tokens, args.descriptor_start, args.descriptor_end, locals, ctx, "i32", out)) return error.NoMatchingCall;
    if (!try emitExpr(allocator, tokens, args.old_flags_start, args.old_flags_end, locals, ctx, "i32", out)) return error.NoMatchingCall;
    if (!try emitWasiStringArg(allocator, tokens, args.old_path_start, args.old_path_end, locals, ctx, out)) return error.NoMatchingCall;
    if (!try emitExpr(allocator, tokens, args.new_descriptor_start, args.new_descriptor_end, locals, ctx, "i32", out)) return error.NoMatchingCall;
    if (!try emitWasiStringArg(allocator, tokens, args.new_path_start, args.new_path_end, locals, ctx, out)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__do_wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try appendWasiImportSymbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}

fn parseWasiLinkAtArgs(tokens: []const lexer.Token, args_start: usize, args_end: usize) ?WasiLinkAtArgs {
    const descriptor_end = findArgEnd(tokens, args_start, args_end);
    if (descriptor_end == args_start or descriptor_end >= args_end or !tokEq(tokens[descriptor_end], ",")) return null;

    const old_flags_start = descriptor_end + 1;
    const old_flags_end = findArgEnd(tokens, old_flags_start, args_end);
    if (old_flags_end == old_flags_start or old_flags_end >= args_end or !tokEq(tokens[old_flags_end], ",")) return null;

    const old_path_start = old_flags_end + 1;
    const old_path_end = findArgEnd(tokens, old_path_start, args_end);
    if (old_path_end == old_path_start or old_path_end >= args_end or !tokEq(tokens[old_path_end], ",")) return null;

    const new_descriptor_start = old_path_end + 1;
    const new_descriptor_end = findArgEnd(tokens, new_descriptor_start, args_end);
    if (new_descriptor_end == new_descriptor_start or new_descriptor_end >= args_end or !tokEq(tokens[new_descriptor_end], ",")) return null;

    const new_path_start = new_descriptor_end + 1;
    const new_path_end = findArgEnd(tokens, new_path_start, args_end);
    if (new_path_end == new_path_start or new_path_end != args_end) return null;

    return .{
        .descriptor_start = args_start,
        .descriptor_end = descriptor_end,
        .old_flags_start = old_flags_start,
        .old_flags_end = old_flags_end,
        .old_path_start = old_path_start,
        .old_path_end = old_path_end,
        .new_descriptor_start = new_descriptor_start,
        .new_descriptor_end = new_descriptor_end,
        .new_path_start = new_path_start,
        .new_path_end = new_path_end,
    };
}

fn emitWasiStringArg(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !bool {
    if (stringLiteralArgLexeme(tokens, start_idx, end_idx)) |lexeme| {
        const data = ctx.string_data.find(lexeme) orelse return error.NoMatchingCall;
        try appendFmt(allocator, out, "    i32.const {d}\n", .{data.ptr});
        try appendFmt(allocator, out, "    i32.const {d}\n", .{data.bytes.len});
        return true;
    }

    const range = trimParens(tokens, start_idx, end_idx);
    if (range.end != range.start + 1) return false;
    if (tokens[range.start].kind != .ident) return false;
    const local_ty = findLocalType(locals.locals.items, tokens[range.start].lexeme) orelse return false;
    if (!std.mem.eql(u8, local_ty, "text")) return false;
    const storage = findStorageLocal(locals.storage_locals.items, tokens[range.start].lexeme) orelse return false;
    if (!std.mem.eql(u8, storage.elem_ty, "u8")) return false;

    try emitStorageDataPtr(allocator, out, tokens[range.start].lexeme);
    try emitStorageLenPtr(allocator, out, tokens[range.start].lexeme);
    try out.appendSlice(allocator, "    i32.load\n");
    return true;
}

fn emitWasiResultFilesizeCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (!std.mem.eql(u8, import.target, "filesystem/types/descriptor.write")) return false;

    const descriptor_end = findArgEnd(tokens, args_start, args_end);
    if (descriptor_end == args_start or descriptor_end >= args_end or !tokEq(tokens[descriptor_end], ",")) return error.NoMatchingCall;
    const buffer_start = descriptor_end + 1;
    const buffer_end = findArgEnd(tokens, buffer_start, args_end);
    if (buffer_end == buffer_start or buffer_end >= args_end or !tokEq(tokens[buffer_end], ",")) return error.NoMatchingCall;
    const offset_start = buffer_end + 1;
    const offset_end = findArgEnd(tokens, offset_start, args_end);
    if (offset_end == offset_start or offset_end != args_end) return error.NoMatchingCall;

    if (!try emitExpr(allocator, tokens, args_start, descriptor_end, locals, ctx, "i32", out)) return error.NoMatchingCall;
    if (!try emitWasiListU8Arg(allocator, tokens, buffer_start, buffer_end, locals, out)) return error.NoMatchingCall;
    if (!try emitExpr(allocator, tokens, offset_start, offset_end, locals, ctx, "u64", out)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__do_wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try appendWasiImportSymbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}

fn emitWasiResultU64StreamCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (!std.mem.eql(u8, import.target, "io/streams/output-stream.check-write")) return false;

    const stream_end = findArgEnd(tokens, args_start, args_end);
    if (stream_end == args_start or stream_end != args_end) return error.NoMatchingCall;

    if (!try emitExpr(allocator, tokens, args_start, stream_end, locals, ctx, "i32", out)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__do_wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try appendWasiImportSymbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}

fn emitWasiResultReadCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (!std.mem.eql(u8, import.target, "filesystem/types/descriptor.read")) return false;

    const descriptor_end = findArgEnd(tokens, args_start, args_end);
    if (descriptor_end == args_start or descriptor_end >= args_end or !tokEq(tokens[descriptor_end], ",")) return error.NoMatchingCall;
    const length_start = descriptor_end + 1;
    const length_end = findArgEnd(tokens, length_start, args_end);
    if (length_end == length_start or length_end >= args_end or !tokEq(tokens[length_end], ",")) return error.NoMatchingCall;
    const offset_start = length_end + 1;
    const offset_end = findArgEnd(tokens, offset_start, args_end);
    if (offset_end == offset_start or offset_end != args_end) return error.NoMatchingCall;

    if (!try emitExpr(allocator, tokens, args_start, descriptor_end, locals, ctx, "i32", out)) return error.NoMatchingCall;
    if (!try emitExpr(allocator, tokens, length_start, length_end, locals, ctx, "u64", out)) return error.NoMatchingCall;
    if (!try emitExpr(allocator, tokens, offset_start, offset_end, locals, ctx, "u64", out)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__do_wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try appendWasiImportSymbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}

fn emitWasiResultListU8Call(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (!std.mem.eql(u8, import.target, "io/streams/input-stream.read")) return false;

    const stream_end = findArgEnd(tokens, args_start, args_end);
    if (stream_end == args_start or stream_end >= args_end or !tokEq(tokens[stream_end], ",")) return error.NoMatchingCall;
    const len_start = stream_end + 1;
    const len_end = findArgEnd(tokens, len_start, args_end);
    if (len_end == len_start or len_end != args_end) return error.NoMatchingCall;

    if (!try emitExpr(allocator, tokens, args_start, stream_end, locals, ctx, "i32", out)) return error.NoMatchingCall;
    if (!try emitExpr(allocator, tokens, len_start, len_end, locals, ctx, "u64", out)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__do_wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try appendWasiImportSymbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}

fn emitWasiResultUnitStatusValue(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
) !void {
    try out.appendSlice(allocator,
        \\    global.get $__do_wasi_result_area_base
        \\    i32.load
        \\    i32.eqz
        \\    if (result i32)
        \\      i32.const 0
        \\    else
        \\      global.get $__do_wasi_result_area_base
        \\      i32.const 4
        \\      i32.add
        \\      i32.load
        \\      i32.const 1
        \\      i32.add
        \\    end
        \\
    );
}

fn emitWasiResultReadValues(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
) !void {
    try out.appendSlice(allocator,
        \\    global.get $__do_wasi_result_area_base
        \\    i32.load
        \\    i32.eqz
        \\    if (result i32 i32 i32)
        \\      global.get $__do_wasi_result_area_base
        \\      i32.const 4
        \\      i32.add
        \\      i32.load
        \\      global.get $__do_wasi_result_area_base
        \\      i32.const 8
        \\      i32.add
        \\      i32.load
        \\      call $__do_wasi_list_u8_to_storage
        \\      global.get $__do_wasi_result_area_base
        \\      i32.const 12
        \\      i32.add
        \\      i32.load8_u
        \\      i32.const 0
        \\    else
    );
    try emitEmptyStorageU8Value(allocator, out);
    try out.appendSlice(allocator,
        \\      i32.const 0
        \\      global.get $__do_wasi_result_area_base
        \\      i32.const 4
        \\      i32.add
        \\      i32.load
        \\      i32.const 1
        \\      i32.add
        \\    end
        \\
    );
}

fn emitWasiResultListU8Values(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
) !void {
    try out.appendSlice(allocator,
        \\    global.get $__do_wasi_result_area_base
        \\    i32.load
        \\    i32.eqz
        \\    if (result i32 i32)
        \\      global.get $__do_wasi_result_area_base
        \\      i32.const 4
        \\      i32.add
        \\      i32.load
        \\      global.get $__do_wasi_result_area_base
        \\      i32.const 8
        \\      i32.add
        \\      i32.load
        \\      call $__do_wasi_list_u8_to_storage
        \\      i32.const 0
        \\    else
    );
    try emitEmptyStorageU8Value(allocator, out);
    try out.appendSlice(allocator,
        \\      global.get $__do_wasi_result_area_base
        \\      i32.const 4
        \\      i32.add
        \\      i32.load
        \\      i32.const 1
        \\      i32.add
        \\    end
        \\
    );
}

fn emitWasiResultDescriptorValues(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
) !void {
    try out.appendSlice(allocator,
        \\    global.get $__do_wasi_result_area_base
        \\    i32.load
        \\    i32.eqz
        \\    if (result i32 i32)
        \\      global.get $__do_wasi_result_area_base
        \\      i32.const 4
        \\      i32.add
        \\      i32.load
        \\      i32.const 0
        \\    else
        \\      i32.const 0
        \\      global.get $__do_wasi_result_area_base
        \\      i32.const 4
        \\      i32.add
        \\      i32.load
        \\      i32.const 1
        \\      i32.add
        \\    end
        \\
    );
}

fn emitEmptyStorageU8Value(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
) !void {
    try appendFmt(allocator, out, "      i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES});
    try appendFmt(allocator, out, "      i32.const {d}\n", .{TYPE_ID_STORAGE_U8});
    try out.appendSlice(allocator,
        \\      call $__do_arc_alloc
        \\      local.set $__do_storage_overwrite_tmp
        \\      local.get $__do_storage_overwrite_tmp
        \\      call $__do_arc_payload
        \\      i32.const 0
        \\      i32.store
        \\      local.get $__do_storage_overwrite_tmp
        \\      call $__do_arc_payload
        \\      i32.const 4
        \\      i32.add
        \\      i32.const 0
        \\      i32.store
        \\      local.get $__do_storage_overwrite_tmp
        \\
    );
}

fn emitWasiResultFilesizeValues(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
) !void {
    try out.appendSlice(allocator,
        \\    global.get $__do_wasi_result_area_base
        \\    i32.load
        \\    i32.eqz
        \\    if (result i64 i32)
        \\      global.get $__do_wasi_result_area_base
        \\      i32.const 8
        \\      i32.add
        \\      i64.load
        \\      i32.const 0
        \\    else
        \\      i64.const 0
        \\      global.get $__do_wasi_result_area_base
        \\      i32.const 8
        \\      i32.add
        \\      i32.load
        \\      i32.const 1
        \\      i32.add
        \\    end
        \\
    );
}

fn emitWasiListU8Arg(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    out: *std.ArrayList(u8),
) !bool {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.end != range.start + 1) return false;
    if (tokens[range.start].kind != .ident) return false;
    const storage = findStorageLocal(locals.storage_locals.items, tokens[range.start].lexeme) orelse return false;
    if (!std.mem.eql(u8, storage.elem_ty, "u8")) return false;

    try emitStorageDataPtr(allocator, out, tokens[range.start].lexeme);
    try emitStorageLenPtr(allocator, out, tokens[range.start].lexeme);
    try out.appendSlice(allocator, "    i32.load\n");
    return true;
}

fn emitUserFuncCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    func: FuncDecl,
    out: *std.ArrayList(u8),
) !bool {
    var arg_start = start_idx;
    var count: usize = 0;
    while (arg_start < end_idx) {
        const arg_end = findArgEnd(tokens, arg_start, end_idx);
        const param_ty = if (count < func.params.len) func.params[count].ty else null;
        if (!try emitExpr(allocator, tokens, arg_start, arg_end, locals, ctx, param_ty, out)) return false;
        if (isDirectManagedLocalExpr(tokens, arg_start, arg_end, locals, ctx)) {
            try out.appendSlice(allocator, "    call $__do_arc_inc\n");
        }
        count += 1;
        arg_start = arg_end;
        if (arg_start < end_idx and tokEq(tokens[arg_start], ",")) arg_start += 1;
    }
    if (count != func.params.len) return false;
    try appendFmt(allocator, out, "    call ${s}\n", .{func.name});
    return true;
}

fn findFuncDecl(functions: []const FuncDecl, name: []const u8) ?FuncDecl {
    for (functions) |func| {
        if (std.mem.eql(u8, func.name, name)) return func;
    }
    return null;
}

fn findFuncDeclBySourceForTokens(functions: []const FuncDecl, tokens: []const lexer.Token, source_name: []const u8) ?FuncDecl {
    for (functions) |func| {
        if (!moduleTokensEqual(func.tokens, tokens)) continue;
        if (std.mem.eql(u8, func.source_name, source_name)) return func;
    }
    return null;
}

fn findFuncDeclForCall(
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    name: []const u8,
) ?FuncDecl {
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (!moduleTokensEqual(func.tokens, tokens)) continue;
        if (!std.mem.eql(u8, func.source_name, name)) continue;
        return func;
    }
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (std.mem.eql(u8, func.name, name)) return func;
    }
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (!std.mem.eql(u8, func.source_name, name)) continue;
        if (callArgsMatchFuncParams(tokens, args_start, args_end, locals, ctx, func)) return func;
    }
    return null;
}

fn callArgsMatchFuncParams(
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    func: FuncDecl,
) bool {
    var arg_start = args_start;
    var param_idx: usize = 0;
    while (arg_start < args_end) {
        if (param_idx >= func.params.len) return false;
        const arg_end = findArgEnd(tokens, arg_start, args_end);
        const arg_ty = inferExprType(tokens, arg_start, arg_end, locals, ctx) orelse return false;
        if (!std.mem.eql(u8, arg_ty, func.params[param_idx].ty)) return false;
        param_idx += 1;
        arg_start = arg_end;
        if (arg_start < args_end and tokEq(tokens[arg_start], ",")) arg_start += 1;
    }
    return param_idx == func.params.len;
}

fn findStructDecl(structs: []const StructDecl, name: []const u8) ?StructDecl {
    const lookup_name = typeBaseName(name);
    for (structs) |decl| {
        if (std.mem.eql(u8, decl.name, lookup_name)) return decl;
    }
    return null;
}

fn findStructLayout(layouts: []const StructLayout, name: []const u8) ?StructLayout {
    const lookup_name = typeBaseName(name);
    for (layouts) |layout| {
        if (std.mem.eql(u8, layout.name, lookup_name)) return layout;
    }
    return null;
}

fn typeBaseName(ty: []const u8) []const u8 {
    for (ty, 0..) |ch, idx| {
        if (ch == '<') return ty[0..idx];
    }
    return ty;
}

fn findStructFieldType(decl: StructDecl, field_name: []const u8) ?[]const u8 {
    for (decl.fields) |field| {
        if (std.mem.eql(u8, publicDeclName(field.name), field_name)) return field.ty;
    }
    return null;
}

fn structFieldPayloadOffset(decl: StructDecl, field_name: []const u8) ?usize {
    var offset: usize = 0;
    for (decl.fields) |field| {
        offset = alignUp(offset, typePayloadAlignment(field.ty));
        if (std.mem.eql(u8, publicDeclName(field.name), field_name)) return offset;
        offset += typePayloadBytes(field.ty);
    }
    return null;
}

fn isManagedStructField(layout: StructLayout, field_name: []const u8) bool {
    for (layout.managed_fields) |field| {
        if (std.mem.eql(u8, field.name, field_name)) return true;
    }
    return false;
}

fn findStructLocal(locals: []const StructLocal, name: []const u8) ?StructLocal {
    for (locals) |local| {
        if (std.mem.eql(u8, local.name, name)) return local;
    }
    return null;
}

fn findStorageLocal(locals: []const StorageLocal, name: []const u8) ?StorageLocal {
    for (locals) |local| {
        if (std.mem.eql(u8, local.name, name)) return local;
    }
    return null;
}

fn findLocalType(locals: []const Local, name: []const u8) ?[]const u8 {
    for (locals) |local| {
        if (std.mem.eql(u8, local.name, name)) return local.ty;
    }
    return null;
}

fn isTopLevelStructDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (!isLineStart(tokens, idx)) return false;
    if (tokens[idx].kind != .ident) return false;
    if (std.mem.eql(u8, tokens[idx].lexeme, "start")) return false;
    return tokEq(tokens[idx + 1], "{");
}

fn isUserFuncDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (!isLineStart(tokens, idx)) return false;
    if (tokens[idx].kind != .ident) return false;
    if (std.mem.eql(u8, tokens[idx].lexeme, "start")) return false;
    return tokEq(tokens[idx + 1], "(");
}

fn isDotIdent(name: []const u8) bool {
    return name.len > 1 and name[0] == '.';
}

fn findStructLiteralFieldEnd(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tokEq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (tokEq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tokEq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tokEq(tokens[i], ",")) return i;
    }
    return end_idx;
}

fn emitGuardReturnIf(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_struct: ?[]const u8,
    defer_ctx: ?*const DeferContext,
    return_label: ?[]const u8,
    out: *std.ArrayList(u8),
) !bool {
    _ = result_struct;
    if (start_idx + 3 > end_idx) return false;
    if (!tokEq(tokens[start_idx], "if")) return false;

    const return_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "return") orelse return false;
    const has_return_expr = return_idx + 1 < end_idx;

    const emitted = try emitExpr(allocator, tokens, start_idx + 1, return_idx, locals, ctx, "bool", out);
    if (!emitted) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    if\n");
    if (has_return_expr) {
        if (result_tys.len != 1) return error.NoMatchingCall;
        if (!try emitExpr(allocator, tokens, return_idx + 1, end_idx, locals, ctx, result_tys[0], out)) {
            return error.NoMatchingCall;
        }
    } else if (result_tys.len != 0) {
        return error.NoMatchingCall;
    }
    try emitDeferCleanupStack(allocator, tokens, defer_ctx, locals, ctx, out);
    if (return_label) |label| {
        try appendFmt(allocator, out, "      br ${s}\n", .{label});
    } else {
        try out.appendSlice(allocator, "      ;; arc-guard-return-release\n");
        try emitReleaseManagedLocals(allocator, locals, ctx, out);
        try out.appendSlice(allocator, "      return\n");
    }
    try out.appendSlice(allocator, "    end\n");
    return true;
}

fn emitLoopBlock(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_struct: ?[]const u8,
    defer_ctx: ?*const DeferContext,
    return_label: ?[]const u8,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (start_idx + 3 > end_idx) return false;
    if (!tokEq(tokens[start_idx], "loop")) return false;
    const open_brace = findTopLevelBlockOpen(tokens, start_idx + 1, end_idx) orelse return false;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return false;
    if (close_brace + 1 != end_idx) return false;

    try out.appendSlice(allocator, "    ;; loop-block\n");
    try out.appendSlice(allocator, "    block $loop_break\n");
    try out.appendSlice(allocator, "    loop $loop_body\n");
    var loop_locals = LocalSet{};
    defer loop_locals.deinit(allocator);
    try collectBodyLocals(allocator, tokens, open_brace + 1, close_brace, ctx, &loop_locals);
    var parent_defer_storage: DeferContext = undefined;
    const parent_defer_ptr: ?*const DeferContext = if (defer_ctx) |scope| blk: {
        parent_defer_storage = .{
            .parent = scope.parent,
            .start_idx = scope.start_idx,
            .end_idx = scope.end_idx,
            .registered_end_idx = start_idx,
        };
        break :blk &parent_defer_storage;
    } else null;
    const loop_defer = DeferContext{
        .parent = parent_defer_ptr,
        .start_idx = open_brace + 1,
        .end_idx = close_brace,
        .registered_end_idx = close_brace,
    };
    const nested_loop = LoopControl{ .cleanup_locals = &loop_locals, .defer_ctx = &loop_defer };
    try emitBody(allocator, tokens, open_brace + 1, close_brace, locals, ctx, result_tys, result_struct, nested_loop, &loop_defer, return_label, out);
    try emitBlockReleaseManagedLocals(allocator, &loop_locals, ctx, out);
    try out.appendSlice(allocator, "    br $loop_body\n");
    try out.appendSlice(allocator, "    end\n");
    try out.appendSlice(allocator, "    end\n");
    return true;
}

fn emitLoopControlStmt(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    loop_ctx: ?LoopControl,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !bool {
    if (end_idx != start_idx + 1) return false;
    if (tokens[start_idx].kind != .ident) return false;
    const control = loop_ctx orelse return false;
    if (std.mem.eql(u8, tokens[start_idx].lexeme, "break")) {
        try emitDeferCleanupStackThrough(allocator, tokens, defer_ctx, control.defer_ctx, locals, ctx, out);
        try out.appendSlice(allocator, "    ;; loop-break-release\n");
        try emitBlockReleaseManagedLocals(allocator, control.cleanup_locals, ctx, out);
        try out.appendSlice(allocator, "    br $loop_break\n");
        return true;
    }
    if (std.mem.eql(u8, tokens[start_idx].lexeme, "continue")) {
        try emitDeferCleanupStackThrough(allocator, tokens, defer_ctx, control.defer_ctx, locals, ctx, out);
        try out.appendSlice(allocator, "    ;; loop-continue-release\n");
        try emitBlockReleaseManagedLocals(allocator, control.cleanup_locals, ctx, out);
        try out.appendSlice(allocator, "    br $loop_body\n");
        return true;
    }
    return false;
}

fn emitIfBlock(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_struct: ?[]const u8,
    loop_ctx: ?LoopControl,
    defer_ctx: ?*const DeferContext,
    return_label: ?[]const u8,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (start_idx + 4 > end_idx) return false;
    if (!tokEq(tokens[start_idx], "if")) return false;

    const open_brace = findTopLevelBlockOpen(tokens, start_idx + 1, end_idx) orelse return false;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return false;
    var else_if_start: ?usize = null;
    var else_open: ?usize = null;
    var else_close: ?usize = null;
    if (close_brace + 1 < end_idx and tokEq(tokens[close_brace + 1], "else")) {
        if (close_brace + 2 >= end_idx) return false;
        if (tokEq(tokens[close_brace + 2], "if")) {
            else_if_start = close_brace + 2;
        } else if (tokEq(tokens[close_brace + 2], "{")) {
            const close_else = findMatchingInRange(tokens, close_brace + 2, "{", "}", end_idx) catch return false;
            if (close_else + 1 != end_idx) return false;
            else_open = close_brace + 2;
            else_close = close_else;
        } else {
            return false;
        }
    } else if (close_brace + 1 != end_idx) {
        return false;
    }

    if (else_if_start != null) {
        try out.appendSlice(allocator, "    ;; if-else-if-block\n");
    } else if (else_open != null) {
        try out.appendSlice(allocator, "    ;; if-else-block\n");
    } else {
        try out.appendSlice(allocator, "    ;; if-block\n");
    }
    const emitted = try emitExpr(allocator, tokens, start_idx + 1, open_brace, locals, ctx, "bool", out);
    if (!emitted) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    if\n");
    var then_locals = LocalSet{};
    defer then_locals.deinit(allocator);
    try collectBodyLocals(allocator, tokens, open_brace + 1, close_brace, ctx, &then_locals);
    var parent_defer_storage: DeferContext = undefined;
    const parent_defer_ptr: ?*const DeferContext = if (defer_ctx) |scope| blk: {
        parent_defer_storage = .{
            .parent = scope.parent,
            .start_idx = scope.start_idx,
            .end_idx = scope.end_idx,
            .registered_end_idx = start_idx,
        };
        break :blk &parent_defer_storage;
    } else null;
    const then_defer = DeferContext{
        .parent = parent_defer_ptr,
        .start_idx = open_brace + 1,
        .end_idx = close_brace,
        .registered_end_idx = close_brace,
    };
    try emitBody(allocator, tokens, open_brace + 1, close_brace, locals, ctx, result_tys, result_struct, loop_ctx, &then_defer, return_label, out);
    try emitBlockReleaseManagedLocals(allocator, &then_locals, ctx, out);
    if (else_if_start) |nested_if| {
        try out.appendSlice(allocator, "    else\n");
        if (!try emitIfBlock(allocator, tokens, nested_if, end_idx, locals, ctx, result_tys, result_struct, loop_ctx, defer_ctx, return_label, out)) return false;
    } else if (else_open) |open_else| {
        const close_else = else_close orelse return false;
        try out.appendSlice(allocator, "    else\n");
        var else_locals = LocalSet{};
        defer else_locals.deinit(allocator);
        try collectBodyLocals(allocator, tokens, open_else + 1, close_else, ctx, &else_locals);
        const else_defer = DeferContext{
            .parent = parent_defer_ptr,
            .start_idx = open_else + 1,
            .end_idx = close_else,
            .registered_end_idx = close_else,
        };
        try emitBody(allocator, tokens, open_else + 1, close_else, locals, ctx, result_tys, result_struct, loop_ctx, &else_defer, return_label, out);
        try emitBlockReleaseManagedLocals(allocator, &else_locals, ctx, out);
    }
    try out.appendSlice(allocator, "    end\n");
    return true;
}

fn wasmType(ty: []const u8) []const u8 {
    if (std.mem.eql(u8, ty, "bool")) return "i32";
    if (std.mem.eql(u8, ty, "i8") or std.mem.eql(u8, ty, "u8")) return "i32";
    if (std.mem.eql(u8, ty, "i16") or std.mem.eql(u8, ty, "u16")) return "i32";
    if (std.mem.eql(u8, ty, "i32") or std.mem.eql(u8, ty, "u32")) return "i32";
    if (std.mem.eql(u8, ty, "isize") or std.mem.eql(u8, ty, "usize")) return "i32";
    if (std.mem.eql(u8, ty, "i64") or std.mem.eql(u8, ty, "u64")) return "i64";
    if (std.mem.eql(u8, ty, "f32")) return "f32";
    if (std.mem.eql(u8, ty, "f64")) return "f64";
    return "i32";
}

fn typePayloadBytes(ty: []const u8) usize {
    if (isManagedPayloadType(ty)) return 4;
    if (std.mem.eql(u8, ty, "bool")) return 4;
    if (std.mem.eql(u8, ty, "i8") or std.mem.eql(u8, ty, "u8")) return 1;
    if (std.mem.eql(u8, ty, "i16") or std.mem.eql(u8, ty, "u16")) return 2;
    if (std.mem.eql(u8, ty, "i32") or std.mem.eql(u8, ty, "u32")) return 4;
    if (std.mem.eql(u8, ty, "isize") or std.mem.eql(u8, ty, "usize")) return 4;
    if (std.mem.eql(u8, ty, "i64") or std.mem.eql(u8, ty, "u64")) return 8;
    if (std.mem.eql(u8, ty, "f32")) return 4;
    if (std.mem.eql(u8, ty, "f64")) return 8;
    return 4;
}

fn typePayloadAlignment(ty: []const u8) usize {
    return @min(typePayloadBytes(ty), 4);
}

fn isManagedPayloadType(ty: []const u8) bool {
    return managedPayloadElemTypeFromName(ty) != null;
}

fn managedPayloadElemTypeFromName(ty: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, ty, "text")) return "u8";
    return storageElemTypeFromName(ty);
}

fn storageTypeNameForElem(elem_ty: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, elem_ty, "bool")) return "[bool]";
    if (std.mem.eql(u8, elem_ty, "i8")) return "[i8]";
    if (std.mem.eql(u8, elem_ty, "u8")) return "[u8]";
    if (std.mem.eql(u8, elem_ty, "i16")) return "[i16]";
    if (std.mem.eql(u8, elem_ty, "u16")) return "[u16]";
    if (std.mem.eql(u8, elem_ty, "i32")) return "[i32]";
    if (std.mem.eql(u8, elem_ty, "u32")) return "[u32]";
    if (std.mem.eql(u8, elem_ty, "isize")) return "[isize]";
    if (std.mem.eql(u8, elem_ty, "usize")) return "[usize]";
    if (std.mem.eql(u8, elem_ty, "i64")) return "[i64]";
    if (std.mem.eql(u8, elem_ty, "u64")) return "[u64]";
    if (std.mem.eql(u8, elem_ty, "f32")) return "[f32]";
    if (std.mem.eql(u8, elem_ty, "f64")) return "[f64]";
    return null;
}

fn isStorageTypeName(ty: []const u8) bool {
    return ty.len >= 3 and ty[0] == '[' and ty[ty.len - 1] == ']';
}

fn storageElemTypeFromName(ty: []const u8) ?[]const u8 {
    if (!isStorageTypeName(ty)) return null;
    const elem_ty = ty[1 .. ty.len - 1];
    return elem_ty;
}

fn storageElementByteWidth(elem_ty: []const u8) ?usize {
    if (std.mem.eql(u8, elem_ty, "i8") or std.mem.eql(u8, elem_ty, "u8")) return 1;
    if (std.mem.eql(u8, elem_ty, "i16") or std.mem.eql(u8, elem_ty, "u16")) return 2;
    if (std.mem.eql(u8, elem_ty, "i64") or std.mem.eql(u8, elem_ty, "u64")) return 8;
    if (std.mem.eql(u8, elem_ty, "f64")) return 8;
    if (std.mem.eql(u8, elem_ty, "bool")) return 4;
    if (std.mem.eql(u8, elem_ty, "i32") or std.mem.eql(u8, elem_ty, "u32")) return 4;
    if (std.mem.eql(u8, elem_ty, "isize") or std.mem.eql(u8, elem_ty, "usize")) return 4;
    if (std.mem.eql(u8, elem_ty, "f32")) return 4;
    return null;
}

fn storageElementByteWidthForType(elem_ty: []const u8, ctx: CodegenContext) ?usize {
    if (storageElementByteWidth(elem_ty)) |width| return width;
    if (isManagedLocalType(elem_ty, ctx)) return 4;
    return null;
}

fn storageTypeIdForElement(elem_ty: []const u8, ctx: CodegenContext) usize {
    if (isManagedLocalType(elem_ty, ctx) and storageElementByteWidth(elem_ty) == null) return TYPE_ID_STORAGE_MANAGED;
    return TYPE_ID_STORAGE_U8;
}

fn isCoreWasmScalar(ty: []const u8) bool {
    return std.mem.eql(u8, ty, "bool") or
        std.mem.eql(u8, ty, "i8") or
        std.mem.eql(u8, ty, "i16") or
        std.mem.eql(u8, ty, "i32") or
        std.mem.eql(u8, ty, "isize") or
        std.mem.eql(u8, ty, "u32") or
        std.mem.eql(u8, ty, "u8") or
        std.mem.eql(u8, ty, "u16") or
        std.mem.eql(u8, ty, "usize") or
        std.mem.eql(u8, ty, "i64") or
        std.mem.eql(u8, ty, "u64") or
        std.mem.eql(u8, ty, "f32") or
        std.mem.eql(u8, ty, "f64");
}

fn isCoreIntegerScalar(ty: []const u8) bool {
    return std.mem.eql(u8, ty, "i8") or
        std.mem.eql(u8, ty, "i16") or
        std.mem.eql(u8, ty, "i32") or
        std.mem.eql(u8, ty, "i64") or
        std.mem.eql(u8, ty, "u8") or
        std.mem.eql(u8, ty, "u16") or
        std.mem.eql(u8, ty, "u32") or
        std.mem.eql(u8, ty, "u64") or
        std.mem.eql(u8, ty, "isize") or
        std.mem.eql(u8, ty, "usize");
}

fn isCoreFloatScalar(ty: []const u8) bool {
    return std.mem.eql(u8, ty, "f32") or
        std.mem.eql(u8, ty, "f64");
}

fn emitNumberConst(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    lexeme: []const u8,
    ty: []const u8,
) !void {
    try appendFmt(allocator, out, "    {s}.const {s}\n", .{ wasmType(ty), lexeme });
}

fn appendStoreForPayloadType(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    ty: []const u8,
) !void {
    if (std.mem.eql(u8, ty, "i8") or std.mem.eql(u8, ty, "u8")) {
        try out.appendSlice(allocator, "    i32.store8\n");
        return;
    }
    if (std.mem.eql(u8, ty, "i16") or std.mem.eql(u8, ty, "u16")) {
        try out.appendSlice(allocator, "    i32.store16\n");
        return;
    }
    if (std.mem.eql(u8, ty, "i64") or std.mem.eql(u8, ty, "u64")) {
        try out.appendSlice(allocator, "    i64.store\n");
        return;
    }
    if (std.mem.eql(u8, ty, "f32")) {
        try out.appendSlice(allocator, "    f32.store\n");
        return;
    }
    if (std.mem.eql(u8, ty, "f64")) {
        try out.appendSlice(allocator, "    f64.store\n");
        return;
    }
    try out.appendSlice(allocator, "    i32.store\n");
}

fn appendLoadForPayloadType(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    ty: []const u8,
) !void {
    if (std.mem.eql(u8, ty, "i8")) {
        try out.appendSlice(allocator, "    i32.load8_s\n");
        return;
    }
    if (std.mem.eql(u8, ty, "u8")) {
        try out.appendSlice(allocator, "    i32.load8_u\n");
        return;
    }
    if (std.mem.eql(u8, ty, "i16")) {
        try out.appendSlice(allocator, "    i32.load16_s\n");
        return;
    }
    if (std.mem.eql(u8, ty, "u16")) {
        try out.appendSlice(allocator, "    i32.load16_u\n");
        return;
    }
    if (std.mem.eql(u8, ty, "i64") or std.mem.eql(u8, ty, "u64")) {
        try out.appendSlice(allocator, "    i64.load\n");
        return;
    }
    if (std.mem.eql(u8, ty, "f32")) {
        try out.appendSlice(allocator, "    f32.load\n");
        return;
    }
    if (std.mem.eql(u8, ty, "f64")) {
        try out.appendSlice(allocator, "    f64.load\n");
        return;
    }
    try out.appendSlice(allocator, "    i32.load\n");
}

fn isNumericCoreFuncName(name: []const u8) bool {
    return std.mem.eql(u8, name, "add") or
        std.mem.eql(u8, name, "sub") or
        std.mem.eql(u8, name, "mul") or
        std.mem.eql(u8, name, "div") or
        std.mem.eql(u8, name, "rem");
}

fn isBitwiseCoreFuncName(name: []const u8) bool {
    return std.mem.eql(u8, name, "and") or
        std.mem.eql(u8, name, "or") or
        std.mem.eql(u8, name, "xor") or
        std.mem.eql(u8, name, "shl") or
        std.mem.eql(u8, name, "shr") or
        std.mem.eql(u8, name, "rotl") or
        std.mem.eql(u8, name, "rotr");
}

fn isCountBitsCoreFuncName(name: []const u8) bool {
    return std.mem.eql(u8, name, "clz") or
        std.mem.eql(u8, name, "ctz") or
        std.mem.eql(u8, name, "popcnt");
}

fn isNumericUnarySelectCoreFuncName(name: []const u8) bool {
    return std.mem.eql(u8, name, "abs");
}

fn isNumericBinarySelectCoreFuncName(name: []const u8) bool {
    return std.mem.eql(u8, name, "min") or
        std.mem.eql(u8, name, "max");
}

fn isFloatUnaryCoreFuncName(name: []const u8) bool {
    return std.mem.eql(u8, name, "neg") or
        std.mem.eql(u8, name, "sqrt") or
        std.mem.eql(u8, name, "ceil") or
        std.mem.eql(u8, name, "floor") or
        std.mem.eql(u8, name, "trunc") or
        std.mem.eql(u8, name, "nearest");
}

fn isFloatBinaryCoreFuncName(name: []const u8) bool {
    return std.mem.eql(u8, name, "copysign");
}

fn isBoolSpecialFuncName(name: []const u8) bool {
    return std.mem.eql(u8, name, "and") or
        std.mem.eql(u8, name, "or") or
        std.mem.eql(u8, name, "not");
}

fn isComparisonCoreFuncName(name: []const u8) bool {
    return std.mem.eql(u8, name, "eq") or
        std.mem.eql(u8, name, "ne") or
        std.mem.eql(u8, name, "lt") or
        std.mem.eql(u8, name, "le") or
        std.mem.eql(u8, name, "gt") or
        std.mem.eql(u8, name, "ge");
}

fn isUnsignedScalar(ty: []const u8) bool {
    return std.mem.eql(u8, ty, "u8") or
        std.mem.eql(u8, ty, "u16") or
        std.mem.eql(u8, ty, "u32") or
        std.mem.eql(u8, ty, "u64") or
        std.mem.eql(u8, ty, "usize");
}

fn absResultType(source_ty: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, source_ty, "i8")) return "u8";
    if (std.mem.eql(u8, source_ty, "i16")) return "u16";
    if (std.mem.eql(u8, source_ty, "i32")) return "u32";
    if (std.mem.eql(u8, source_ty, "i64")) return "u64";
    if (std.mem.eql(u8, source_ty, "isize")) return "usize";
    if (std.mem.eql(u8, source_ty, "f32")) return "f32";
    if (std.mem.eql(u8, source_ty, "f64")) return "f64";
    return null;
}

fn absSourceTypeFromResult(result_ty: ?[]const u8) ?[]const u8 {
    const ty = result_ty orelse return null;
    if (std.mem.eql(u8, ty, "u8")) return "i8";
    if (std.mem.eql(u8, ty, "u16")) return "i16";
    if (std.mem.eql(u8, ty, "u32")) return "i32";
    if (std.mem.eql(u8, ty, "u64")) return "i64";
    if (std.mem.eql(u8, ty, "usize")) return "isize";
    if (std.mem.eql(u8, ty, "f32")) return "f32";
    if (std.mem.eql(u8, ty, "f64")) return "f64";
    return null;
}

fn numericSelectTemps(ty: []const u8) NumericSelectTemps {
    if (std.mem.eql(u8, wasmType(ty), "i64")) {
        return .{ .left = NUMERIC_SELECT_LEFT_TMP_I64, .right = NUMERIC_SELECT_RIGHT_TMP_I64 };
    }
    return .{ .left = NUMERIC_SELECT_LEFT_TMP_I32, .right = NUMERIC_SELECT_RIGHT_TMP_I32 };
}

fn numericSelectLeftTmp(ty: []const u8) []const u8 {
    return numericSelectTemps(ty).left;
}

fn bitwiseWasmOp(name: []const u8, ty: []const u8) ?[]const u8 {
    const wt = wasmType(ty);
    if (std.mem.eql(u8, name, "and")) return if (std.mem.eql(u8, wt, "i64")) "i64.and" else "i32.and";
    if (std.mem.eql(u8, name, "or")) return if (std.mem.eql(u8, wt, "i64")) "i64.or" else "i32.or";
    if (std.mem.eql(u8, name, "xor")) return if (std.mem.eql(u8, wt, "i64")) "i64.xor" else "i32.xor";
    if (std.mem.eql(u8, name, "shl")) return if (std.mem.eql(u8, wt, "i64")) "i64.shl" else "i32.shl";
    if (std.mem.eql(u8, name, "shr")) {
        if (std.mem.eql(u8, wt, "i64")) return if (isUnsignedScalar(ty)) "i64.shr_u" else "i64.shr_s";
        return if (isUnsignedScalar(ty)) "i32.shr_u" else "i32.shr_s";
    }
    if (std.mem.eql(u8, name, "rotl")) return if (std.mem.eql(u8, wt, "i64")) "i64.rotl" else "i32.rotl";
    if (std.mem.eql(u8, name, "rotr")) return if (std.mem.eql(u8, wt, "i64")) "i64.rotr" else "i32.rotr";
    return null;
}

fn countBitsWasmOp(name: []const u8, ty: []const u8) ?[]const u8 {
    const wt = wasmType(ty);
    if (std.mem.eql(u8, name, "clz")) return if (std.mem.eql(u8, wt, "i64")) "i64.clz" else "i32.clz";
    if (std.mem.eql(u8, name, "ctz")) return if (std.mem.eql(u8, wt, "i64")) "i64.ctz" else "i32.ctz";
    if (std.mem.eql(u8, name, "popcnt")) return if (std.mem.eql(u8, wt, "i64")) "i64.popcnt" else "i32.popcnt";
    return null;
}

fn floatUnaryWasmOp(name: []const u8, ty: []const u8) ?[]const u8 {
    const wt = wasmType(ty);
    if (!std.mem.eql(u8, wt, "f32") and !std.mem.eql(u8, wt, "f64")) return null;
    if (std.mem.eql(u8, name, "abs")) return if (std.mem.eql(u8, wt, "f32")) "f32.abs" else "f64.abs";
    if (std.mem.eql(u8, name, "neg")) return if (std.mem.eql(u8, wt, "f32")) "f32.neg" else "f64.neg";
    if (std.mem.eql(u8, name, "sqrt")) return if (std.mem.eql(u8, wt, "f32")) "f32.sqrt" else "f64.sqrt";
    if (std.mem.eql(u8, name, "ceil")) return if (std.mem.eql(u8, wt, "f32")) "f32.ceil" else "f64.ceil";
    if (std.mem.eql(u8, name, "floor")) return if (std.mem.eql(u8, wt, "f32")) "f32.floor" else "f64.floor";
    if (std.mem.eql(u8, name, "trunc")) return if (std.mem.eql(u8, wt, "f32")) "f32.trunc" else "f64.trunc";
    if (std.mem.eql(u8, name, "nearest")) return if (std.mem.eql(u8, wt, "f32")) "f32.nearest" else "f64.nearest";
    return null;
}

fn floatBinaryWasmOp(name: []const u8, ty: []const u8) ?[]const u8 {
    const wt = wasmType(ty);
    if (!std.mem.eql(u8, wt, "f32") and !std.mem.eql(u8, wt, "f64")) return null;
    if (std.mem.eql(u8, name, "min")) return if (std.mem.eql(u8, wt, "f32")) "f32.min" else "f64.min";
    if (std.mem.eql(u8, name, "max")) return if (std.mem.eql(u8, wt, "f32")) "f32.max" else "f64.max";
    if (std.mem.eql(u8, name, "copysign")) return if (std.mem.eql(u8, wt, "f32")) "f32.copysign" else "f64.copysign";
    return null;
}

fn numericWasmOp(name: []const u8, ty: []const u8) ?[]const u8 {
    const wt = wasmType(ty);
    if (std.mem.eql(u8, name, "add")) {
        if (std.mem.eql(u8, wt, "i64")) return "i64.add";
        if (std.mem.eql(u8, wt, "f32")) return "f32.add";
        if (std.mem.eql(u8, wt, "f64")) return "f64.add";
        return "i32.add";
    }
    if (std.mem.eql(u8, name, "sub")) {
        if (std.mem.eql(u8, wt, "i64")) return "i64.sub";
        if (std.mem.eql(u8, wt, "f32")) return "f32.sub";
        if (std.mem.eql(u8, wt, "f64")) return "f64.sub";
        return "i32.sub";
    }
    if (std.mem.eql(u8, name, "mul")) {
        if (std.mem.eql(u8, wt, "i64")) return "i64.mul";
        if (std.mem.eql(u8, wt, "f32")) return "f32.mul";
        if (std.mem.eql(u8, wt, "f64")) return "f64.mul";
        return "i32.mul";
    }
    if (std.mem.eql(u8, name, "div")) {
        if (std.mem.eql(u8, wt, "f32")) return "f32.div";
        if (std.mem.eql(u8, wt, "f64")) return "f64.div";
        if (std.mem.eql(u8, wt, "i64")) return if (isUnsignedScalar(ty)) "i64.div_u" else "i64.div_s";
        return if (isUnsignedScalar(ty)) "i32.div_u" else "i32.div_s";
    }
    if (std.mem.eql(u8, name, "rem")) {
        if (std.mem.eql(u8, wt, "f32") or std.mem.eql(u8, wt, "f64")) return null;
        if (std.mem.eql(u8, wt, "i64")) return if (isUnsignedScalar(ty)) "i64.rem_u" else "i64.rem_s";
        return if (isUnsignedScalar(ty)) "i32.rem_u" else "i32.rem_s";
    }
    return null;
}

fn comparisonWasmOp(name: []const u8, ty: []const u8) ?[]const u8 {
    const wt = wasmType(ty);
    if (std.mem.eql(u8, name, "eq")) {
        if (std.mem.eql(u8, wt, "i64")) return "i64.eq";
        if (std.mem.eql(u8, wt, "f32")) return "f32.eq";
        if (std.mem.eql(u8, wt, "f64")) return "f64.eq";
        return "i32.eq";
    }
    if (std.mem.eql(u8, name, "ne")) {
        if (std.mem.eql(u8, wt, "i64")) return "i64.ne";
        if (std.mem.eql(u8, wt, "f32")) return "f32.ne";
        if (std.mem.eql(u8, wt, "f64")) return "f64.ne";
        return "i32.ne";
    }
    if (std.mem.eql(u8, name, "lt")) {
        if (std.mem.eql(u8, wt, "i64")) return if (isUnsignedScalar(ty)) "i64.lt_u" else "i64.lt_s";
        if (std.mem.eql(u8, wt, "f32")) return "f32.lt";
        if (std.mem.eql(u8, wt, "f64")) return "f64.lt";
        return if (isUnsignedScalar(ty)) "i32.lt_u" else "i32.lt_s";
    }
    if (std.mem.eql(u8, name, "le")) {
        if (std.mem.eql(u8, wt, "i64")) return if (isUnsignedScalar(ty)) "i64.le_u" else "i64.le_s";
        if (std.mem.eql(u8, wt, "f32")) return "f32.le";
        if (std.mem.eql(u8, wt, "f64")) return "f64.le";
        return if (isUnsignedScalar(ty)) "i32.le_u" else "i32.le_s";
    }
    if (std.mem.eql(u8, name, "gt")) {
        if (std.mem.eql(u8, wt, "i64")) return if (isUnsignedScalar(ty)) "i64.gt_u" else "i64.gt_s";
        if (std.mem.eql(u8, wt, "f32")) return "f32.gt";
        if (std.mem.eql(u8, wt, "f64")) return "f64.gt";
        return if (isUnsignedScalar(ty)) "i32.gt_u" else "i32.gt_s";
    }
    if (std.mem.eql(u8, name, "ge")) {
        if (std.mem.eql(u8, wt, "i64")) return if (isUnsignedScalar(ty)) "i64.ge_u" else "i64.ge_s";
        if (std.mem.eql(u8, wt, "f32")) return "f32.ge";
        if (std.mem.eql(u8, wt, "f64")) return "f64.ge";
        return if (isUnsignedScalar(ty)) "i32.ge_u" else "i32.ge_s";
    }
    return null;
}

fn scalarConvertWasmOp(source_ty: []const u8, target_ty: []const u8) ?[]const u8 {
    const source_wt = wasmType(source_ty);
    const target_wt = wasmType(target_ty);
    if (std.mem.eql(u8, source_wt, target_wt)) return null;

    if (std.mem.eql(u8, source_wt, "i32") and std.mem.eql(u8, target_wt, "i64")) {
        return if (isUnsignedScalar(source_ty)) "i64.extend_i32_u" else "i64.extend_i32_s";
    }
    if (std.mem.eql(u8, source_wt, "i64") and std.mem.eql(u8, target_wt, "i32")) return "i32.wrap_i64";

    if (std.mem.eql(u8, source_wt, "i32") and std.mem.eql(u8, target_wt, "f32")) {
        return if (isUnsignedScalar(source_ty)) "f32.convert_i32_u" else "f32.convert_i32_s";
    }
    if (std.mem.eql(u8, source_wt, "i32") and std.mem.eql(u8, target_wt, "f64")) {
        return if (isUnsignedScalar(source_ty)) "f64.convert_i32_u" else "f64.convert_i32_s";
    }
    if (std.mem.eql(u8, source_wt, "i64") and std.mem.eql(u8, target_wt, "f32")) {
        return if (isUnsignedScalar(source_ty)) "f32.convert_i64_u" else "f32.convert_i64_s";
    }
    if (std.mem.eql(u8, source_wt, "i64") and std.mem.eql(u8, target_wt, "f64")) {
        return if (isUnsignedScalar(source_ty)) "f64.convert_i64_u" else "f64.convert_i64_s";
    }

    if (std.mem.eql(u8, source_wt, "f32") and std.mem.eql(u8, target_wt, "i32")) {
        return if (isUnsignedScalar(target_ty)) "i32.trunc_f32_u" else "i32.trunc_f32_s";
    }
    if (std.mem.eql(u8, source_wt, "f32") and std.mem.eql(u8, target_wt, "i64")) {
        return if (isUnsignedScalar(target_ty)) "i64.trunc_f32_u" else "i64.trunc_f32_s";
    }
    if (std.mem.eql(u8, source_wt, "f64") and std.mem.eql(u8, target_wt, "i32")) {
        return if (isUnsignedScalar(target_ty)) "i32.trunc_f64_u" else "i32.trunc_f64_s";
    }
    if (std.mem.eql(u8, source_wt, "f64") and std.mem.eql(u8, target_wt, "i64")) {
        return if (isUnsignedScalar(target_ty)) "i64.trunc_f64_u" else "i64.trunc_f64_s";
    }

    if (std.mem.eql(u8, source_wt, "f32") and std.mem.eql(u8, target_wt, "f64")) return "f64.promote_f32";
    if (std.mem.eql(u8, source_wt, "f64") and std.mem.eql(u8, target_wt, "f32")) return "f32.demote_f64";
    return null;
}

fn scalarConvertResultType(name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, "to_u8")) return "u8";
    if (std.mem.eql(u8, name, "to_u16")) return "u16";
    if (std.mem.eql(u8, name, "to_u32")) return "u32";
    if (std.mem.eql(u8, name, "to_u64")) return "u64";
    if (std.mem.eql(u8, name, "to_usize")) return "usize";
    if (std.mem.eql(u8, name, "to_isize")) return "isize";
    if (std.mem.eql(u8, name, "to_i8")) return "i8";
    if (std.mem.eql(u8, name, "to_i16")) return "i16";
    if (std.mem.eql(u8, name, "to_i32")) return "i32";
    if (std.mem.eql(u8, name, "to_i64")) return "i64";
    if (std.mem.eql(u8, name, "to_f32")) return "f32";
    if (std.mem.eql(u8, name, "to_f64")) return "f64";
    return null;
}

fn inferExprType(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.start >= range.end) return null;

    if (range.end == range.start + 1) {
        const tok = tokens[range.start];
        if (tok.kind == .ident) return findLocalType(locals.locals.items, tok.lexeme);
        return null;
    }

    const call_head = exprCallHead(tokens, range) orelse return null;
    const call_name = tokens[call_head.name_idx].lexeme;
    if (call_head.is_intrinsic) {
        if (shouldInferBoolSpecialCall(call_name, tokens, call_head.args_start, call_head.args_end, locals, ctx)) return "bool";
        if (isComparisonCoreFuncName(call_name)) return "bool";
        if (std.mem.eql(u8, call_name, "len")) return "usize";
        if (scalarConvertResultType(call_name)) |ty| return ty;
        if (std.mem.eql(u8, call_name, "get")) {
            return inferGetCallType(tokens, call_head.args_start, call_head.args_end, locals, ctx);
        }
        if (isMemoryLoadName(call_name)) return memoryLoadResultType(call_name);
        if (isNumericCoreFuncName(call_name)) {
            return inferFirstArgTypeOrDefaultS32(tokens, call_head.args_start, call_head.args_end, locals, ctx);
        }
        if (isBitwiseCoreFuncName(call_name)) {
            return inferExprType(tokens, call_head.args_start, findArgEnd(tokens, call_head.args_start, call_head.args_end), locals, ctx);
        }
        if (isCountBitsCoreFuncName(call_name)) {
            return inferExprType(tokens, call_head.args_start, findArgEnd(tokens, call_head.args_start, call_head.args_end), locals, ctx);
        }
        if (isNumericUnarySelectCoreFuncName(call_name)) {
            const first_end = findArgEnd(tokens, call_head.args_start, call_head.args_end);
            const source_ty = inferExprType(tokens, call_head.args_start, first_end, locals, ctx) orelse "i32";
            return absResultType(source_ty);
        }
        if (isNumericBinarySelectCoreFuncName(call_name)) {
            return inferExprType(tokens, call_head.args_start, findArgEnd(tokens, call_head.args_start, call_head.args_end), locals, ctx);
        }
        if (isFloatUnaryCoreFuncName(call_name) or isFloatBinaryCoreFuncName(call_name)) {
            return inferExprType(tokens, call_head.args_start, findArgEnd(tokens, call_head.args_start, call_head.args_end), locals, ctx);
        }
    }

    if (findFuncDeclForCall(tokens, call_head.args_start, call_head.args_end, locals, ctx, call_name)) |func| return func.result;
    if (findWasiHostImportForTokens(ctx, tokens, call_name)) |import| return wasiDoResultType(import);
    if (findHostImportForTokens(ctx.host_imports, tokens, call_name)) |host_import| return host_import.result;
    return null;
}

fn inferFirstArgTypeOrDefaultS32(
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    const first_end = findArgEnd(tokens, args_start, args_end);
    return inferExprType(tokens, args_start, first_end, locals, ctx) orelse "i32";
}

fn wasiDoResultType(import: WasiHostImport) ?[]const u8 {
    const lowering = wasiLowering(import) orelse return null;
    if (lowering.result_storage_elem) |elem_ty| return storageTypeNameForElem(elem_ty);
    if (lowering.result_record) |record| return record;
    return import.result;
}

fn isMemoryLoadName(name: []const u8) bool {
    return std.mem.eql(u8, name, "load_u8") or
        std.mem.eql(u8, name, "load_i8") or
        std.mem.eql(u8, name, "load_u16_le") or
        std.mem.eql(u8, name, "load_i16_le") or
        std.mem.eql(u8, name, "load_u32_le") or
        std.mem.eql(u8, name, "load_i32_le") or
        std.mem.eql(u8, name, "load_u64_le") or
        std.mem.eql(u8, name, "load_i64_le");
}

fn memoryLoadResultType(name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, "load_u8")) return "u8";
    if (std.mem.eql(u8, name, "load_i8")) return "i8";
    if (std.mem.eql(u8, name, "load_u16_le")) return "u16";
    if (std.mem.eql(u8, name, "load_i16_le")) return "i16";
    if (std.mem.eql(u8, name, "load_u32_le")) return "u32";
    if (std.mem.eql(u8, name, "load_i32_le")) return "i32";
    if (std.mem.eql(u8, name, "load_u64_le")) return "u64";
    if (std.mem.eql(u8, name, "load_i64_le")) return "i64";
    return null;
}

fn memoryLoadWasmOp(name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, "load_u8")) return "i32.load8_u";
    if (std.mem.eql(u8, name, "load_i8")) return "i32.load8_s";
    if (std.mem.eql(u8, name, "load_u16_le")) return "i32.load16_u";
    if (std.mem.eql(u8, name, "load_i16_le")) return "i32.load16_s";
    if (std.mem.eql(u8, name, "load_u32_le")) return "i32.load";
    if (std.mem.eql(u8, name, "load_i32_le")) return "i32.load";
    if (std.mem.eql(u8, name, "load_u64_le")) return "i64.load";
    if (std.mem.eql(u8, name, "load_i64_le")) return "i64.load";
    return null;
}

fn memoryLoadByteWidth(name: []const u8) ?usize {
    if (std.mem.eql(u8, name, "load_u8")) return 1;
    if (std.mem.eql(u8, name, "load_i8")) return 1;
    if (std.mem.eql(u8, name, "load_u16_le")) return 2;
    if (std.mem.eql(u8, name, "load_i16_le")) return 2;
    if (std.mem.eql(u8, name, "load_u32_le")) return 4;
    if (std.mem.eql(u8, name, "load_i32_le")) return 4;
    if (std.mem.eql(u8, name, "load_u64_le")) return 8;
    if (std.mem.eql(u8, name, "load_i64_le")) return 8;
    return null;
}

fn inferGetCallType(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (first_end >= end_idx or !tokEq(tokens[first_end], ",")) return null;

    const name = tokens[start_idx].lexeme;
    if (findStorageLocal(locals.storage_locals.items, name)) |storage| return storage.elem_ty;
    const struct_local = findStructLocal(locals.struct_locals.items, name) orelse return null;

    const second_start = first_end + 1;
    const second_end = findArgEnd(tokens, second_start, end_idx);
    if (second_end != end_idx) return null;
    if (second_end != second_start + 1 or !isDotIdent(tokens[second_start].lexeme)) return null;
    const decl = findStructDecl(ctx.structs, struct_local.ty) orelse return null;
    return findStructFieldType(decl, publicDeclName(tokens[second_start].lexeme));
}

fn hasLocal(locals: []const Local, name: []const u8) bool {
    for (locals) |local| {
        if (std.mem.eql(u8, local.name, name)) return true;
    }
    return false;
}

fn findStartFunc(tokens: []const lexer.Token) ?usize {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (tokens[i].kind == .ident and std.mem.eql(u8, tokens[i].lexeme, "start") and tokEq(tokens[i + 1], "(")) return i;
    }
    return null;
}

fn findToken(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, lexeme: []const u8) ?usize {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEq(tokens[i], lexeme)) return i;
    }
    return null;
}

fn findTopLevelToken(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, lexeme: []const u8) ?usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tokEq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (tokEq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tokEq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tokEq(tokens[i], lexeme)) return i;
    }
    return null;
}

fn findTopLevelBlockOpen(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var depth_paren: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tokEq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tokEq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tokEq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (depth_paren == 0 and depth_angle == 0 and tokEq(tokens[i], "{")) return i;
    }
    return null;
}

fn findStmtEnd(tokens: []const lexer.Token, start_idx: usize, limit_idx: usize) usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < limit_idx) : (i += 1) {
        if (tokEq(tokens[i], "(")) {
            depth_paren += 1;
        } else if (tokEq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
        } else if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
        } else if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
        } else if (tokEq(tokens[i], "<")) {
            depth_angle += 1;
        } else if (tokEq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
        }

        if (depth_paren != 0 or depth_brace != 0 or depth_angle != 0) continue;
        if (i + 1 >= limit_idx or tokens[i + 1].line != tokens[i].line) return i + 1;
    }
    return limit_idx;
}

fn findArgEnd(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    var depth_paren: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tokEq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (depth_paren == 0 and tokEq(tokens[i], ",")) return i;
    }
    return end_idx;
}

fn findMatching(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8) !usize {
    return findMatchingInRange(tokens, open_idx, open, close, tokens.len);
}

fn findMatchingInRange(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8, limit: usize) !usize {
    if (open_idx >= limit or !tokEq(tokens[open_idx], open)) return error.InvalidGroupStart;

    var depth: usize = 0;
    var i = open_idx;
    while (i < limit) : (i += 1) {
        if (tokEq(tokens[i], open)) {
            depth += 1;
            continue;
        }
        if (!tokEq(tokens[i], close)) continue;
        if (depth == 0) return error.InvalidGroupDepth;
        depth -= 1;
        if (depth == 0) return i;
    }
    return error.UnterminatedGroup;
}

fn tokEq(t: lexer.Token, s: []const u8) bool {
    return std.mem.eql(u8, t.lexeme, s);
}

fn decodeQuotedStringToken(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    if (raw.len < 2 or raw[0] != '"' or raw[raw.len - 1] != '"') return error.InvalidStringEscape;

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    const body = raw[1 .. raw.len - 1];
    var i: usize = 0;
    while (i < body.len) {
        if (body[i] != '\\') {
            try out.append(allocator, body[i]);
            i += 1;
            continue;
        }

        i += 1;
        if (i >= body.len) return error.InvalidStringEscape;
        switch (body[i]) {
            '"' => try out.append(allocator, '"'),
            '\\' => try out.append(allocator, '\\'),
            'n' => try out.append(allocator, '\n'),
            'r' => try out.append(allocator, '\r'),
            't' => try out.append(allocator, '\t'),
            'x' => {
                if (i + 2 >= body.len) return error.InvalidStringEscape;
                const hi = hexValue(body[i + 1]) orelse return error.InvalidStringEscape;
                const lo = hexValue(body[i + 2]) orelse return error.InvalidStringEscape;
                try out.append(allocator, (hi << 4) | lo);
                i += 2;
            },
            else => return error.InvalidStringEscape,
        }
        i += 1;
    }

    return out.toOwnedSlice(allocator);
}

fn appendWatStringLiteral(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    bytes: []const u8,
) !void {
    try out.append(allocator, '"');
    for (bytes) |byte| {
        if (byte >= 0x20 and byte <= 0x7e and byte != '"' and byte != '\\') {
            try out.append(allocator, byte);
            continue;
        }
        try appendWatByteEscape(allocator, out, byte);
    }
    try out.append(allocator, '"');
}

fn appendWatByteEscape(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    byte: u8,
) !void {
    const digits = "0123456789abcdef";
    try out.append(allocator, '\\');
    try out.append(allocator, digits[byte >> 4]);
    try out.append(allocator, digits[byte & 0x0f]);
}

fn hexValue(ch: u8) ?u8 {
    if (ch >= '0' and ch <= '9') return ch - '0';
    if (ch >= 'a' and ch <= 'f') return ch - 'a' + 10;
    if (ch >= 'A' and ch <= 'F') return ch - 'A' + 10;
    return null;
}

fn appendFmt(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}
