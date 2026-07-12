const std = @import("std");
const backend_ir = @import("backend_ir.zig");
const component_metadata_wat = @import("component_metadata_wat.zig");
const function_body_wat = @import("function_body_wat.zig");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const ownership = @import("ownership.zig");
const ownership_facts = @import("ownership_facts.zig");
const parser = @import("parser.zig");
const payload_wat = @import("codegen_payload_wat.zig");
const runtime_prelude_wat = @import("runtime_prelude_wat.zig");
const storage_wat = @import("codegen_storage_wat.zig");
const test_runner = @import("test_runner.zig");
const type_util = @import("type_name.zig");

const SourceOrigin = enum {
    unknown,
    fresh_local,
    param_or_import,
    helper_shared,
    collection_value,
    recv_value,
    loop_source,
    union_payload,
    compiler_temp,
};

const Local = struct {
    name: []const u8,
    source_name: ?[]const u8 = null,
    ty: []const u8,
    origin: SourceOrigin = .unknown,
    emit_decl: bool = true,
    release_on_scope_exit: bool = true,
};

const StructField = struct {
    name: []const u8,
    ty: []const u8,
    default_start: ?usize = null,
    default_end: usize = 0,
};

const StructDecl = struct {
    name: []const u8,
    type_params: []const []const u8 = &.{},
    fields: []const StructField,
    layout_source: ?[]const u8,
    owned_types: []const []const u8 = &.{},
    tokens: []const lexer.Token,
};

const ValueEnumBranch = struct {
    name: []const u8,
    value: []const u8,
};

const ValueEnumDecl = struct {
    name: []const u8,
    source_name: []const u8,
    carrier: []const u8,
    branches: []const ValueEnumBranch,
    owned_name: bool = false,
};

const ManagedFieldOffset = runtime_prelude_wat.ManagedFieldOffset;
const StructLayout = runtime_prelude_wat.StructLayout;

const StructLocal = struct {
    name: []const u8,
    source_name: ?[]const u8 = null,
    ty: []const u8,
    origin: SourceOrigin = .unknown,
};

const TypedStructBinding = struct {
    decl: StructDecl,
    ty: []const u8,
};

const StorageLocal = struct {
    name: []const u8,
    source_name: ?[]const u8 = null,
    ty: []const u8,
    elem_ty: []const u8,
    origin: SourceOrigin = .unknown,
};

const UnionBranch = struct {
    ty: []const u8,
    tag: usize,
    payload_start: usize,
    payload_len: usize,
};

const UnionLayout = struct {
    source_ty: []const u8,
    branches: []const UnionBranch,
    payload_tys: []const []const u8,
};

const UnionLocal = struct {
    name: []const u8,
    source_name: ?[]const u8 = null,
    layout: UnionLayout,
    owns_layout: bool = false,
    origin: SourceOrigin = .unknown,
};

const InferredUnionBinding = struct {
    layout: UnionLayout,
    owns_layout: bool,
};

const NarrowedUnionLocal = struct {
    name: []const u8,
    source_name: ?[]const u8 = null,
    ty: []const u8,
};

const FieldMetaLocal = struct {
    name: []const u8,
    struct_name: []const u8,
    decl_index: usize,
    visible_index: usize,
};

pub const EmitOptions = struct {
    component_core: bool = false,
};

const TYPE_ID_STORAGE_U8: usize = storage_wat.TYPE_ID_STORAGE_U8;
const TYPE_ID_STORAGE_MANAGED: usize = storage_wat.TYPE_ID_STORAGE_MANAGED;
const TYPE_ID_FIRST_STRUCT: usize = storage_wat.TYPE_ID_FIRST_STRUCT;
const STORAGE_PAYLOAD_HEADER_BYTES: usize = storage_wat.STORAGE_PAYLOAD_HEADER_BYTES;
const STORAGE_OVERWRITE_TMP_LOCAL = storage_wat.STORAGE_OVERWRITE_TMP_LOCAL;
const STORAGE_PUT_SOURCE_TMP_LOCAL = "__storage_put_source_tmp";
const VARIADIC_PACK_TMP_LOCAL = "__variadic_pack_tmp";
const STORAGE_WRITE_INDEX_TMP_LOCAL = "__storage_write_index_tmp";
const STORAGE_WRITE_LEN_TMP_LOCAL = "__storage_write_len_tmp";
const STORAGE_WRITE_NEXT_TMP_LOCAL = "__storage_write_next_tmp";
const STORAGE_WRITE_SCAN_TMP_LOCAL = "__storage_write_scan_tmp";
const STORAGE_WRITE_TARGET_TMP_LOCAL = "__storage_write_target_tmp";
const TUPLE_PACK_BASE_TMP_LOCAL = "__tuple_pack_base_tmp";
const TUPLE_PACK_SPILL_I32 = payload_wat.TUPLE_PACK_SPILL_I32;
const TUPLE_PACK_SPILL_I64 = payload_wat.TUPLE_PACK_SPILL_I64;
const TUPLE_PACK_SPILL_F32 = payload_wat.TUPLE_PACK_SPILL_F32;
const TUPLE_PACK_SPILL_F64 = payload_wat.TUPLE_PACK_SPILL_F64;
const STRUCT_LITERAL_TMP_LOCAL = "__struct_literal_tmp";
const NUMERIC_SELECT_LEFT_TMP_I32 = "__numeric_select_left_i32";
const NUMERIC_SELECT_RIGHT_TMP_I32 = "__numeric_select_right_i32";
const NUMERIC_SELECT_LEFT_TMP_I64 = "__numeric_select_left_i64";
const NUMERIC_SELECT_RIGHT_TMP_I64 = "__numeric_select_right_i64";

const NumericSelectTemps = struct {
    left: []const u8,
    right: []const u8,
};

const LocalSet = struct {
    locals: std.ArrayList(Local) = .empty,
    struct_locals: std.ArrayList(StructLocal) = .empty,
    storage_locals: std.ArrayList(StorageLocal) = .empty,
    union_locals: std.ArrayList(UnionLocal) = .empty,
    narrowed_union_locals: std.ArrayList(NarrowedUnionLocal) = .empty,
    field_meta_locals: std.ArrayList(FieldMetaLocal) = .empty,
    owned_names: std.ArrayList([]const u8) = .empty,
    local_name_prefix: ?[]const u8 = null,

    fn deinit(self: *LocalSet, allocator: std.mem.Allocator) void {
        for (self.owned_names.items) |name| {
            allocator.free(name);
        }
        for (self.union_locals.items) |union_local| {
            if (union_local.owns_layout) freeUnionLayout(allocator, union_local.layout);
        }
        self.owned_names.deinit(allocator);
        self.field_meta_locals.deinit(allocator);
        self.narrowed_union_locals.deinit(allocator);
        self.union_locals.deinit(allocator);
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
        return self.appendBorrowedLocalWithOrigin(allocator, name, ty, emit_decl, .unknown);
    }

    fn appendBorrowedLocalWithOrigin(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        ty: []const u8,
        emit_decl: bool,
        origin: SourceOrigin,
    ) !void {
        const resolved = try self.scopedLocalName(allocator, name, emit_decl);
        if (findLocalType(self.locals.items, resolved.name)) |existing_ty| {
            if (!std.mem.eql(u8, existing_ty, ty)) return error.NoMatchingCall;
            return;
        }
        try self.locals.append(allocator, .{
            .name = resolved.name,
            .source_name = resolved.source_name,
            .ty = ty,
            .origin = origin,
            .emit_decl = emit_decl,
        });
    }

    fn appendOwnedLocal(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        ty: []const u8,
    ) !void {
        return self.appendOwnedLocalWithOrigin(allocator, name, ty, .fresh_local);
    }

    fn appendOwnedLocalWithOrigin(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        ty: []const u8,
        origin: SourceOrigin,
    ) !void {
        try self.owned_names.append(allocator, name);
        errdefer allocator.free(name);
        errdefer _ = self.owned_names.pop();
        try self.locals.append(allocator, .{
            .name = name,
            .ty = ty,
            .origin = origin,
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
        return self.appendStorageLocalWithTypeAndOrigin(allocator, name, ty, elem_ty, emit_decl, .unknown);
    }

    fn appendStorageLocalWithTypeAndOrigin(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        ty: []const u8,
        elem_ty: []const u8,
        emit_decl: bool,
        origin: SourceOrigin,
    ) !void {
        const resolved = try self.scopedLocalName(allocator, name, emit_decl);
        try self.storage_locals.append(allocator, .{
            .name = resolved.name,
            .source_name = resolved.source_name,
            .ty = ty,
            .elem_ty = elem_ty,
            .origin = origin,
        });
        try self.locals.append(allocator, .{
            .name = resolved.name,
            .source_name = resolved.source_name,
            .ty = ty,
            .origin = origin,
            .emit_decl = emit_decl,
        });
    }

    fn appendUnionLocal(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        layout: UnionLayout,
        emit_decl: bool,
        owns_layout: bool,
    ) !void {
        return self.appendUnionLocalWithOrigin(allocator, name, layout, emit_decl, owns_layout, .unknown);
    }

    fn appendUnionLocalWithOrigin(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        layout: UnionLayout,
        emit_decl: bool,
        owns_layout: bool,
        origin: SourceOrigin,
    ) !void {
        return self.appendUnionLocalWithOriginAndRelease(allocator, name, layout, emit_decl, owns_layout, origin, true);
    }

    fn appendUnionTempLocal(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        layout: UnionLayout,
        owns_layout: bool,
    ) !void {
        return self.appendUnionLocalWithOriginAndRelease(allocator, name, layout, true, owns_layout, .compiler_temp, false);
    }

    fn appendUnionLocalWithOriginAndRelease(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        layout: UnionLayout,
        emit_decl: bool,
        owns_layout: bool,
        origin: SourceOrigin,
        release_on_scope_exit: bool,
    ) !void {
        if (findUnionLocalExact(self.union_locals.items, name)) |existing| {
            if (!unionLayoutsEqual(existing.layout, layout)) return error.NoMatchingCall;
            if (owns_layout) freeUnionLayout(allocator, layout);
            return;
        }
        const resolved = try self.scopedLocalName(allocator, name, emit_decl);
        try self.union_locals.append(allocator, .{
            .name = resolved.name,
            .source_name = resolved.source_name,
            .layout = layout,
            .owns_layout = owns_layout,
            .origin = origin,
        });
        for (layout.payload_tys, 0..) |payload_ty, idx| {
            const payload_name = try unionPayloadLocalName(allocator, resolved.name, idx);
            errdefer allocator.free(payload_name);
            try self.owned_names.append(allocator, payload_name);
            errdefer _ = self.owned_names.pop();
            try self.locals.append(allocator, .{
                .name = payload_name,
                .ty = payload_ty,
                .origin = .union_payload,
                .emit_decl = emit_decl,
                .release_on_scope_exit = release_on_scope_exit,
            });
        }

        const tag_name = try unionTagLocalName(allocator, resolved.name);
        errdefer allocator.free(tag_name);
        try self.owned_names.append(allocator, tag_name);
        errdefer _ = self.owned_names.pop();
        try self.locals.append(allocator, .{
            .name = tag_name,
            .ty = "i32",
            .origin = .compiler_temp,
            .emit_decl = emit_decl,
            .release_on_scope_exit = false,
        });
    }

    fn appendStructLocal(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        ty: []const u8,
        emit_decl: bool,
    ) ![]const u8 {
        return self.appendStructLocalWithOrigin(allocator, name, ty, emit_decl, .unknown);
    }

    fn appendStructLocalWithOrigin(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        ty: []const u8,
        emit_decl: bool,
        origin: SourceOrigin,
    ) ![]const u8 {
        const resolved = try self.scopedLocalName(allocator, name, emit_decl);
        try self.struct_locals.append(allocator, .{
            .name = resolved.name,
            .source_name = resolved.source_name,
            .ty = ty,
            .origin = origin,
        });
        return resolved.name;
    }

    const ScopedLocalName = struct {
        name: []const u8,
        source_name: ?[]const u8,
    };

    fn scopedLocalName(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        emit_decl: bool,
    ) !ScopedLocalName {
        const prefix = self.local_name_prefix orelse return .{ .name = name, .source_name = null };
        if (!emit_decl or isCompilerLocalName(name)) return .{ .name = name, .source_name = null };
        const owned = try std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, name });
        errdefer allocator.free(owned);
        try self.owned_names.append(allocator, owned);
        return .{ .name = owned, .source_name = name };
    }

    fn ensureStorageWriteTemps(self: *LocalSet, allocator: std.mem.Allocator) !void {
        if (!hasLocal(self.locals.items, STORAGE_OVERWRITE_TMP_LOCAL)) {
            try self.appendBorrowedLocal(allocator, STORAGE_OVERWRITE_TMP_LOCAL, "usize", true);
        }
        if (!hasLocal(self.locals.items, STORAGE_PUT_SOURCE_TMP_LOCAL)) {
            try self.appendBorrowedLocal(allocator, STORAGE_PUT_SOURCE_TMP_LOCAL, "usize", true);
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
        if (!hasLocal(self.locals.items, STORAGE_WRITE_TARGET_TMP_LOCAL)) {
            try self.appendBorrowedLocal(allocator, STORAGE_WRITE_TARGET_TMP_LOCAL, "usize", true);
        }
    }

    fn ensureTuplePackTemps(self: *LocalSet, allocator: std.mem.Allocator) !void {
        if (!hasLocal(self.locals.items, TUPLE_PACK_BASE_TMP_LOCAL)) {
            try self.appendBorrowedLocal(allocator, TUPLE_PACK_BASE_TMP_LOCAL, "usize", true);
        }
        if (!hasLocal(self.locals.items, TUPLE_PACK_SPILL_I32)) {
            try self.appendBorrowedLocal(allocator, TUPLE_PACK_SPILL_I32, "i32", true);
        }
        // Extra i32 spills for multi-leaf pack pop/push (e.g. text+u8, Cell+u8).
        if (!hasLocal(self.locals.items, payload_wat.TUPLE_PACK_SPILL_I32_1)) {
            try self.appendBorrowedLocal(allocator, payload_wat.TUPLE_PACK_SPILL_I32_1, "i32", true);
        }
        if (!hasLocal(self.locals.items, payload_wat.TUPLE_PACK_SPILL_I32_2)) {
            try self.appendBorrowedLocal(allocator, payload_wat.TUPLE_PACK_SPILL_I32_2, "i32", true);
        }
        if (!hasLocal(self.locals.items, payload_wat.TUPLE_PACK_SPILL_I32_3)) {
            try self.appendBorrowedLocal(allocator, payload_wat.TUPLE_PACK_SPILL_I32_3, "i32", true);
        }
        if (!hasLocal(self.locals.items, TUPLE_PACK_SPILL_I64)) {
            try self.appendBorrowedLocal(allocator, TUPLE_PACK_SPILL_I64, "i64", true);
        }
        if (!hasLocal(self.locals.items, TUPLE_PACK_SPILL_F32)) {
            try self.appendBorrowedLocal(allocator, TUPLE_PACK_SPILL_F32, "f32", true);
        }
        if (!hasLocal(self.locals.items, TUPLE_PACK_SPILL_F64)) {
            try self.appendBorrowedLocal(allocator, TUPLE_PACK_SPILL_F64, "f64", true);
        }
    }

    fn ensureVariadicPackTmp(self: *LocalSet, allocator: std.mem.Allocator) !void {
        if (!hasLocal(self.locals.items, VARIADIC_PACK_TMP_LOCAL)) {
            try self.appendBorrowedLocal(allocator, VARIADIC_PACK_TMP_LOCAL, "usize", true);
        }
    }

    fn ensureStructLiteralTmp(self: *LocalSet, allocator: std.mem.Allocator) !void {
        if (!hasLocal(self.locals.items, STRUCT_LITERAL_TMP_LOCAL)) {
            try self.appendBorrowedLocal(allocator, STRUCT_LITERAL_TMP_LOCAL, "usize", true);
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

    fn appendNarrowedUnionLocal(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        union_local: UnionLocal,
        ty: []const u8,
    ) !void {
        try self.narrowed_union_locals.append(allocator, .{
            .name = union_local.name,
            .source_name = union_local.source_name,
            .ty = ty,
        });
    }
};

const EMPTY_LOCAL_SET = LocalSet{};

const FuncParam = struct {
    name: []const u8,
    ty: []const u8,
    abi_ty: ?[]const u8 = null,
    variadic: bool = false,
    callback: ?OwnedFuncTypeShape = null,
};

const GenericTypeBinding = struct {
    name: []const u8,
    ty: []const u8,
};

const FuncTypeShape = struct {
    param_types: []const ?[]const u8,
    return_type: ?[]const u8,
};

const OwnedFuncTypeShape = struct {
    shape: FuncTypeShape,
    owned: bool,
};

const CallbackBindingKind = enum {
    lambda,
    func_ref,
};

const CallbackBinding = struct {
    param_name: []const u8,
    shape: FuncTypeShape,
    kind: CallbackBindingKind,
    arg_tokens: []const lexer.Token,
    arg_start: usize,
    arg_end: usize,
    lambda_params: []const []const u8 = &.{},
    body_start: usize = 0,
    body_end: usize = 0,
    func_name: ?[]const u8 = null,
};

const LambdaExprShape = struct {
    open_params: usize,
    close_params: usize,
    body_start: usize,
    body_end: usize,
    is_block: bool,
};

const CallbackCallArg = struct {
    source_name: []const u8,
    actual_name: ?[]const u8 = null,
    ty: []const u8,
    expr_tokens: []const lexer.Token,
    expr_start: usize,
    expr_end: usize,
};

const FuncDecl = struct {
    name: []const u8,
    source_name: []const u8 = "",
    params: []const FuncParam,
    result: ?[]const u8,
    results: []const []const u8,
    result_items: []const FuncResultItem,
    result_struct: ?[]const u8,
    result_union: ?UnionLayout,
    type_params: []const []const u8 = &.{},
    type_bindings: []const GenericTypeBinding = &.{},
    callback_bindings: []const CallbackBinding = &.{},
    is_generic_template: bool = false,
    owned_name: bool = false,
    owned_types: []const []const u8 = &.{},
    tokens: []const lexer.Token,
    start_idx: usize,
    arrow: bool,
    body_start: usize,
    body_end: usize,
};

const FuncResultParse = struct {
    types: []const []const u8,
    items: []const FuncResultItem = &.{},
    owns_items: bool = true,
    result_struct: ?[]const u8 = null,
    result_union: ?UnionLayout = null,
};

const FuncResultItem = struct {
    ty: []const u8,
    abi_start: usize,
    abi_len: usize,
    union_layout: ?UnionLayout = null,
};

const MultiResultLhsKind = enum {
    scalar,
    managed,
    union_value,
    unmanaged_struct,
};

const MultiResultLhs = struct {
    name: []const u8,
    ty: []const u8,
    item: FuncResultItem,
    kind: MultiResultLhsKind,
};

const NO_RESULT_ITEMS: []const FuncResultItem = &.{};

const ParsedCodegenType = struct {
    ty: []const u8,
    next_idx: usize,
};

const StructFieldAbiSlot = struct {
    name_suffix: []const u8,
    ty: []const u8,
    offset: usize,
    managed: bool,
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
    value_enums: []const ValueEnumDecl,
    struct_layouts: []const StructLayout,
    host_imports: []const HostImport,
    wasi_imports: []const WasiHostImport,
    string_data: *const StringDataContext,
    entry_tokens: []const lexer.Token,
    modules: []const imports.ModuleRecord,
    imported_alias_ctx: ?ImportedAliasContext = null,
    type_bindings: []const GenericTypeBinding = &.{},
    callback_bindings: []const CallbackBinding = &.{},
    callback_call_args: []const CallbackCallArg = &.{},
};

const LoopControl = struct {
    parent: ?*const LoopControl,
    source_label: ?[]const u8,
    break_label: []const u8,
    continue_label: []const u8,
    cleanup_locals: *const LocalSet,
    defer_ctx: *const DeferContext,
};

const SelfTailTco = struct {
    func: FuncDecl,
    loop_label: []const u8,
};

const CollectionLoopHeader = struct {
    value_name: ?[]const u8,
    index_name: ?[]const u8,
    source_name: []const u8,
    source_ty: []const u8,
    source_start: usize,
    source_end: usize,
    source_is_expr: bool = false,
    elem_ty: []const u8,
    elem_bytes: usize,
    open_brace: usize,
    close_brace: usize,
};

const RecvLoopHeader = struct {
    value_name: ?[]const u8,
    count_name: ?[]const u8,
    source_name: []const u8,
    elem_ty: []const u8,
    elem_bytes: usize,
    open_brace: usize,
    close_brace: usize,
};

const FieldReflectionLoopHeader = struct {
    field_name: []const u8,
    decl: StructDecl,
    loop_idx: usize,
    open_brace: usize,
    close_brace: usize,
};

const FieldStaticValue = union(enum) {
    bool: bool,
    int: usize,
    text: []const u8,
};

const FieldReflectionIfParts = struct {
    cond_start: usize,
    cond_end: usize,
    then_start: usize,
    then_end: usize,
    else_if_start: ?usize = null,
    else_start: ?usize = null,
    else_end: usize = 0,
};

const UnionStructPayload = struct {
    branch: UnionBranch,
    decl: StructDecl,
};

const NilComparisonNarrowing = struct {
    union_local: UnionLocal,
    payload_ty: []const u8,
    non_nil_when_true: bool,
};

const IsComparisonNarrowing = struct {
    union_local: UnionLocal,
    payload_ty: []const u8,
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

const WasiLowering = component_metadata_wat.WasiLowering;

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

const ImportedScalarConst = struct {
    ty: []const u8,
    value: []const u8,
};

const ReachVisit = struct {
    module_idx: usize,
    name: []const u8,
    call_idx: ?usize = null,
};

const StringData = runtime_prelude_wat.StringData;

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

    fn internRaw(self: *StringDataContext, allocator: std.mem.Allocator, key: []const u8, bytes: []const u8) !StringData {
        for (self.items.items) |item| {
            if (std.mem.eql(u8, item.lexeme, key)) return item;
        }

        const owned_bytes = try allocator.dupe(u8, bytes);
        errdefer allocator.free(owned_bytes);
        const data = StringData{
            .lexeme = key,
            .bytes = owned_bytes,
            .ptr = self.next_ptr,
        };
        self.next_ptr += @max(owned_bytes.len, 1);
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
    try collectStringDataForStructFieldNames(allocator, structs.items, &string_data);

    var value_enums = std.ArrayList(ValueEnumDecl).empty;
    defer {
        freeValueEnumDecls(allocator, value_enums.items);
        value_enums.deinit(allocator);
    }
    try collectValueEnumDecls(allocator, tokens, &value_enums);
    if (module_graph) |graph| {
        try collectImportedValueEnumDecls(allocator, tokens, graph, &value_enums);
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
        value_enums.items,
        struct_layouts.items,
        host_imports.items,
        wasi_imports.items,
        &string_data,
        if (module_graph) |graph| graph.modules else &.{},
        imported_alias_ctx,
        &functions,
    );
    try collectConcreteGenericStructLayouts(allocator, structs.items, functions.items, &struct_layouts);
    try collectStoragePackLayoutsFromTokens(allocator, tokens, structs.items, &struct_layouts);
    if (module_graph) |graph| {
        for (graph.modules) |module| {
            try collectStoragePackLayoutsFromTokens(allocator, module.tokens, structs.items, &struct_layouts);
        }
    }
    try mangleOverloadedFunctionNames(allocator, &functions);

    const ctx = CodegenContext{
        .functions = functions.items,
        .structs = structs.items,
        .value_enums = value_enums.items,
        .struct_layouts = struct_layouts.items,
        .host_imports = host_imports.items,
        .wasi_imports = wasi_imports.items,
        .string_data = &string_data,
        .entry_tokens = tokens,
        .modules = if (module_graph) |graph| graph.modules else &.{},
        .imported_alias_ctx = imported_alias_ctx,
    };

    try out.appendSlice(allocator, "(module\n");
    try appendFmt(allocator, &out, "  ;; source_len={d}\n", .{program.source_len});
    try appendFmt(allocator, &out, "  ;; token_count={d}\n", .{program.token_count});
    try appendFmt(allocator, &out, "  ;; top_level_count={d}\n", .{program.top_level_count});
    try component_metadata_wat.emitWasiBindings(allocator, &out, wasi_imports.items);
    try component_metadata_wat.emitWasiCoreImports(allocator, &out, wasi_imports.items);
    try component_metadata_wat.emitHostImports(allocator, &out, host_imports.items);
    try runtime_prelude_wat.emitStringDataMemory(allocator, &out, string_data.items.items, .{ .component_core = options.component_core });
    try runtime_prelude_wat.emitArcRuntimePrelude(allocator, &out, string_data.items.items, struct_layouts.items);
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
    try collectStringDataForStructFieldNames(allocator, structs.items, &string_data);

    var value_enums = std.ArrayList(ValueEnumDecl).empty;
    defer {
        freeValueEnumDecls(allocator, value_enums.items);
        value_enums.deinit(allocator);
    }
    try collectValueEnumDecls(allocator, tokens, &value_enums);
    if (module_graph) |graph| {
        try collectImportedValueEnumDecls(allocator, tokens, graph, &value_enums);
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
        value_enums.items,
        struct_layouts.items,
        host_imports.items,
        wasi_imports.items,
        &string_data,
        if (module_graph) |graph| graph.modules else &.{},
        imported_alias_ctx,
        &functions,
    );
    try collectConcreteGenericStructLayouts(allocator, structs.items, functions.items, &struct_layouts);
    try collectStoragePackLayoutsFromTokens(allocator, tokens, structs.items, &struct_layouts);
    if (module_graph) |graph| {
        for (graph.modules) |module| {
            try collectStoragePackLayoutsFromTokens(allocator, module.tokens, structs.items, &struct_layouts);
        }
    }
    try mangleOverloadedFunctionNames(allocator, &functions);

    const ctx = CodegenContext{
        .functions = functions.items,
        .structs = structs.items,
        .value_enums = value_enums.items,
        .struct_layouts = struct_layouts.items,
        .host_imports = host_imports.items,
        .wasi_imports = wasi_imports.items,
        .string_data = &string_data,
        .entry_tokens = tokens,
        .modules = if (module_graph) |graph| graph.modules else &.{},
        .imported_alias_ctx = imported_alias_ctx,
    };

    try out.appendSlice(allocator, "(module\n");
    try appendFmt(allocator, &out, "  ;; source_len={d}\n", .{program.source_len});
    try appendFmt(allocator, &out, "  ;; token_count={d}\n", .{program.token_count});
    try appendFmt(allocator, &out, "  ;; top_level_count={d}\n", .{program.top_level_count});
    try appendFmt(allocator, &out, "  ;; compiled_test_count={d}\n", .{test_decls.len});
    try component_metadata_wat.emitWasiBindings(allocator, &out, wasi_imports.items);
    try component_metadata_wat.emitWasiCoreImports(allocator, &out, wasi_imports.items);
    try component_metadata_wat.emitHostImports(allocator, &out, host_imports.items);
    try runtime_prelude_wat.emitStringDataMemory(allocator, &out, string_data.items.items, .{});
    try runtime_prelude_wat.emitArcRuntimePrelude(allocator, &out, string_data.items.items, struct_layouts.items);
    try emitUserFuncs(allocator, ctx, &out);
    try emitTestFuncs(allocator, tokens, test_decls, ctx, &out);
    try function_body_wat.emitTestStartFunc(allocator, &out, test_decls.len);
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
    var cleanup_locals = LocalSet{};
    defer cleanup_locals.deinit(allocator);
    try collectDirectBodyLocals(allocator, tokens, open_body + 1, close_body, ctx, &cleanup_locals);

    try function_body_wat.emitFuncOpen(allocator, out, "_start");
    for (locals.locals.items) |local| {
        if (!local.emit_decl) continue;
        try function_body_wat.emitLocalDecl(allocator, out, local.name, codegenWasmType(ctx, local.ty));
    }
    const no_results: []const []const u8 = &.{};
    const root_defer = DeferContext{
        .parent = null,
        .start_idx = open_body + 1,
        .end_idx = close_body,
        .registered_end_idx = close_body,
    };
    var backend_ir_body = std.ArrayList(u8).empty;
    defer backend_ir_body.deinit(allocator);
    const emitted_backend_ir = try emitScalarNumericStartWithBackendIr(allocator, tokens, open_body + 1, close_body, &locals, ctx, &backend_ir_body);
    if (emitted_backend_ir) {
        try out.appendSlice(allocator, "    ;; backend-ir-lowering scalar-numeric-start\n");
        try out.appendSlice(allocator, backend_ir_body.items);
    }
    if (!emitted_backend_ir) {
        try emitBody(allocator, tokens, open_body + 1, close_body, open_body + 1, &locals, &cleanup_locals, &EMPTY_LOCAL_SET, ctx, no_results, NO_RESULT_ITEMS, null, null, null, &root_defer, null, null, out);
    }
    if (!bodyEndsWithPlainReturn(tokens, open_body + 1, close_body)) {
        try emitFallthroughReleaseManagedLocals(allocator, &cleanup_locals, ctx, out);
    }
    try function_body_wat.emitFuncClose(allocator, out);
    try function_body_wat.emitFuncExport(allocator, out, "_start", "_start");
}

const BackendIrLocal = struct {
    name: []const u8,
    value: backend_ir.ValueId,
};

fn emitScalarNumericStartWithBackendIr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    var func = try backend_ir.Function.create(allocator, "_start_ir");
    defer func.deinit(allocator);
    const block_id = try func.addBlockId(allocator);

    var ir_locals = std.ArrayList(BackendIrLocal).empty;
    defer ir_locals.deinit(allocator);

    var i = start_idx;
    var saw_return = false;
    while (i < end_idx) {
        const stmt_end = findStmtEnd(tokens, i, end_idx);
        if (isPlainNilReturnStmt(tokens, i, stmt_end)) {
            try func.setTerminator(block_id, .ret);
            saw_return = true;
            i = stmt_end;
            continue;
        }

        const scalar_ty = typedScalarBindingType(tokens, i, stmt_end, ctx) orelse return false;
        if (!std.mem.eql(u8, scalar_ty, "i32")) return false;
        const eq_idx = findTopLevelToken(tokens, i + 1, stmt_end, "=") orelse return false;
        const target_source_name = tokens[i].lexeme;
        const target_name = resolvedLocalName(locals.locals.items, target_source_name);
        const value = func.allocValue();
        try func.setValueName(allocator, value, target_name);
        try ir_locals.append(allocator, .{ .name = target_source_name, .value = value });
        try ir_locals.append(allocator, .{ .name = target_name, .value = value });

        if (!try appendScalarNumericExprIr(allocator, tokens, eq_idx + 1, stmt_end, "i32", &func, block_id, ir_locals.items)) {
            return false;
        }
        try func.appendInstr(allocator, block_id, .{ .local_set = value });
        i = stmt_end;
    }
    if (!saw_return) return false;

    const body = try backend_ir.emitFunctionBodyWat(allocator, &func);
    defer allocator.free(body);
    try out.appendSlice(allocator, body);
    return true;
}

fn isPlainNilReturnStmt(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    return start_idx + 1 == end_idx and tokEq(tokens[start_idx], "return");
}

fn appendScalarNumericExprIr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    expected_ty: []const u8,
    func: *backend_ir.Function,
    block_id: backend_ir.BlockId,
    ir_locals: []const BackendIrLocal,
) CodegenError!bool {
    if (!std.mem.eql(u8, expected_ty, "i32")) return false;
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.start >= range.end) return false;

    if (range.start + 1 == range.end) {
        const tok = tokens[range.start];
        if (tok.kind == .number) {
            const value = std.fmt.parseInt(i32, tok.lexeme, 0) catch return false;
            try func.appendInstr(allocator, block_id, .{ .const_value = .{ .i32 = value } });
            return true;
        }
        if (tok.kind == .ident) {
            const local = findBackendIrLocal(ir_locals, tok.lexeme) orelse return false;
            try func.appendInstr(allocator, block_id, .{ .local_get = local });
            return true;
        }
        return false;
    }

    const call_head = exprCallHead(tokens, range) orelse return false;
    if (!call_head.is_intrinsic) return false;
    const op = numericCoreIrOp(tokens[call_head.name_idx].lexeme) orelse return false;

    var arg_start = call_head.args_start;
    var emitted = false;
    while (arg_start < call_head.args_end) {
        const arg_end = findArgEnd(tokens, arg_start, call_head.args_end);
        if (!try appendScalarNumericExprIr(allocator, tokens, arg_start, arg_end, expected_ty, func, block_id, ir_locals)) {
            return false;
        }
        if (emitted) {
            try func.appendInstr(allocator, block_id, .{ .numeric = .{ .ty = .i32, .op = op } });
        }
        emitted = true;
        arg_start = arg_end;
        if (arg_start < call_head.args_end and tokEq(tokens[arg_start], ",")) arg_start += 1;
    }
    return emitted;
}

fn findBackendIrLocal(ir_locals: []const BackendIrLocal, name: []const u8) ?backend_ir.ValueId {
    for (ir_locals) |local| {
        if (std.mem.eql(u8, local.name, name)) return local.value;
    }
    return null;
}

fn numericCoreIrOp(name: []const u8) ?backend_ir.NumericOp {
    if (std.mem.eql(u8, name, "add")) return .add;
    if (std.mem.eql(u8, name, "sub")) return .sub;
    if (std.mem.eql(u8, name, "mul")) return .mul;
    return null;
}

fn emitTestFuncs(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    test_decls: []const test_runner.TestDecl,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !void {
    for (test_decls, 0..) |decl, idx| {
        try function_body_wat.emitCompiledTestOpen(allocator, out, idx, decl.name_lexeme);

        var locals = LocalSet{};
        defer locals.deinit(allocator);
        try collectBodyLocals(allocator, tokens, decl.body_start, decl.body_end, ctx, &locals);
        var cleanup_locals = LocalSet{};
        defer cleanup_locals.deinit(allocator);
        try collectDirectBodyLocals(allocator, tokens, decl.body_start, decl.body_end, ctx, &cleanup_locals);

        for (locals.locals.items) |local| {
            if (!local.emit_decl) continue;
            try function_body_wat.emitLocalDecl(allocator, out, local.name, codegenWasmType(ctx, local.ty));
        }
        const no_results: []const []const u8 = &.{};
        const root_defer = DeferContext{
            .parent = null,
            .start_idx = decl.body_start,
            .end_idx = decl.body_end,
            .registered_end_idx = decl.body_end,
        };
        try emitBody(allocator, tokens, decl.body_start, decl.body_end, decl.body_start, &locals, &cleanup_locals, &EMPTY_LOCAL_SET, ctx, no_results, NO_RESULT_ITEMS, null, null, null, &root_defer, null, null, out);
        if (!bodyEndsWithPlainReturn(tokens, decl.body_start, decl.body_end)) {
            try emitFallthroughReleaseManagedLocals(allocator, &cleanup_locals, ctx, out);
        }
        try out.appendSlice(allocator, "    unreachable\n");
        try function_body_wat.emitFuncClose(allocator, out);
        try function_body_wat.emitCompiledTestExport(allocator, out, idx);
    }
}

fn emitUserFuncs(
    allocator: std.mem.Allocator,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !void {
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (funcHasCallbackParams(func) and func.callback_bindings.len == 0) continue;
        try emitUserFunc(allocator, func, ctx, out);
    }
}

fn emitUserFunc(
    allocator: std.mem.Allocator,
    func: FuncDecl,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !void {
    var func_ctx = ctx;
    func_ctx.type_bindings = func.type_bindings;
    func_ctx.callback_bindings = func.callback_bindings;
    var signature_owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (signature_owned_types.items) |owned| allocator.free(owned);
        signature_owned_types.deinit(allocator);
    }

    const tokens = func.tokens;
    try appendFmt(allocator, out, "  (func ${s}", .{func.name});
    for (func.params) |param| {
        if (param.callback != null) continue;
        const abi_ty = funcParamAbiType(param);
        if (try parseTypeUnionLayoutFromName(allocator, tokens, abi_ty, func_ctx.structs, func_ctx.struct_layouts, &signature_owned_types)) |layout| {
            defer freeUnionLayout(allocator, layout);
            for (layout.payload_tys, 0..) |payload_ty, idx| {
                try appendFmt(allocator, out, " (param ${s}.__union_payload_{d} {s})", .{
                    param.name,
                    idx,
                    codegenWasmType(func_ctx, payload_ty),
                });
            }
            try appendFmt(allocator, out, " (param ${s}.__union_tag i32)", .{param.name});
            continue;
        }
        if (findStructDecl(func_ctx.structs, abi_ty)) |decl| {
            if (findStructLayout(func_ctx.struct_layouts, abi_ty) == null) {
                for (decl.fields) |field| {
                    const field_ty = try substituteStructFieldType(allocator, decl, abi_ty, field.ty, &signature_owned_types);
                    try appendStructFieldAbiParams(allocator, tokens, out, param.name, field.name, field_ty, func_ctx, &signature_owned_types);
                }
                continue;
            }
        }
        if (isTupleTypeName(abi_ty)) {
            try appendTupleParamAbi(allocator, out, param.name, abi_ty, func_ctx);
            continue;
        }
        try appendFmt(allocator, out, " (param ${s} {s})", .{ param.name, codegenWasmType(func_ctx, abi_ty) });
    }
    if (func.results.len != 0) {
        try out.appendSlice(allocator, " (result");
        for (func.results) |result| {
            try appendFmt(allocator, out, " {s}", .{codegenWasmType(func_ctx, result)});
        }
        try out.appendSlice(allocator, ")");
    }
    try out.appendSlice(allocator, "\n");

    var locals = LocalSet{};
    defer locals.deinit(allocator);
    try appendFuncParamLocals(allocator, func, func_ctx, &locals);
    try collectBodyLocals(allocator, tokens, func.body_start, func.body_end, func_ctx, &locals);
    var cleanup_locals = LocalSet{};
    defer cleanup_locals.deinit(allocator);
    try appendFuncParamLocals(allocator, func, func_ctx, &cleanup_locals);
    try collectDirectBodyLocals(allocator, tokens, func.body_start, func.body_end, func_ctx, &cleanup_locals);

    const self_tail_tco = try buildSelfTailTco(allocator, func, tokens, &locals, &cleanup_locals, func_ctx);
    defer if (self_tail_tco) |tco| allocator.free(tco.loop_label);

    for (locals.locals.items) |local| {
        if (!local.emit_decl) continue;
        try function_body_wat.emitLocalDecl(allocator, out, local.name, codegenWasmType(func_ctx, local.ty));
    }
    if (self_tail_tco) |tco| {
        for (tco.func.params) |param| {
            if (param.callback != null) continue;
            try appendFmt(allocator, out, "    (local $__tail_arg_{s} {s})\n", .{
                param.name,
                codegenWasmType(func_ctx, param.ty),
            });
        }
    }
    if (func.arrow) {
        if (func.results.len != 1) return error.NoMatchingCall;
        if (!try emitExpr(allocator, tokens, func.body_start, func.body_end, &locals, func_ctx, func.results[0], out)) {
            return error.NoMatchingCall;
        }
        try emitFallthroughReleaseManagedLocals(allocator, &cleanup_locals, func_ctx, out);
        try out.appendSlice(allocator, "    return\n");
    } else {
        const root_defer = DeferContext{
            .parent = null,
            .start_idx = func.body_start,
            .end_idx = func.body_end,
            .registered_end_idx = func.body_end,
        };
        const can_reach_end = bodyCanReachEnd(tokens, func.body_start, func.body_end);
        if (self_tail_tco) |tco| {
            try appendFmt(allocator, out, "    loop ${s}\n", .{tco.loop_label});
            try emitSelfTailLoopLocalReset(allocator, tco.func, &locals, func_ctx, out);
            try emitBody(allocator, tokens, func.body_start, func.body_end, func.body_start, &locals, &cleanup_locals, &EMPTY_LOCAL_SET, func_ctx, func.results, func.result_items, func.result_struct, func.result_union, null, &root_defer, null, &tco, out);
            try out.appendSlice(allocator, "    end\n");
            if (func.results.len != 0 and !can_reach_end) {
                try out.appendSlice(allocator, "    unreachable\n");
            }
        } else {
            try emitBody(allocator, tokens, func.body_start, func.body_end, func.body_start, &locals, &cleanup_locals, &EMPTY_LOCAL_SET, func_ctx, func.results, func.result_items, func.result_struct, func.result_union, null, &root_defer, null, null, out);
        }
        if (!bodyEndsWithPlainReturn(tokens, func.body_start, func.body_end)) {
            try emitFallthroughReleaseManagedLocals(allocator, &cleanup_locals, func_ctx, out);
            if (func.results.len != 0 and !can_reach_end) {
                try out.appendSlice(allocator, "    unreachable\n");
            }
        }
    }
    try function_body_wat.emitFuncClose(allocator, out);
}

fn buildSelfTailTco(
    allocator: std.mem.Allocator,
    func: FuncDecl,
    tokens: []const lexer.Token,
    locals: *const LocalSet,
    cleanup_locals: *const LocalSet,
    ctx: CodegenContext,
) !?SelfTailTco {
    if (func.arrow) return null;
    if (func.results.len != 1) return null;
    if (!isCodegenScalarType(ctx, func.results[0])) return null;
    if (!funcHasSelfTailReturn(tokens, func.body_start, func.body_end, func)) return null;
    if (funcHasDeferStmt(tokens, func.body_start, func.body_end)) return null;
    for (func.params) |param| {
        if (param.callback != null) return null;
        if (param.variadic) return null;
        if (!isCodegenScalarType(ctx, param.ty)) return null;
    }
    for (locals.locals.items) |local| {
        if (!local.emit_decl) continue;
        if (!isCodegenScalarType(ctx, local.ty)) return null;
    }
    for (cleanup_locals.locals.items) |local| {
        if (!local.emit_decl) continue;
        if (!isCodegenScalarType(ctx, local.ty)) return null;
    }
    if (hasManagedCleanupLocals(cleanup_locals, ctx)) return null;
    return .{
        .func = func,
        .loop_label = try std.fmt.allocPrint(allocator, "__tail_{s}", .{func.name}),
    };
}

fn funcHasSelfTailReturn(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, func: FuncDecl) bool {
    var i = start_idx;
    while (i < end_idx) {
        if (tokEq(tokens[i], "return")) {
            const stmt_end = findStmtEnd(tokens, i, end_idx);
            const range = trimParens(tokens, i + 1, stmt_end);
            if (exprCallHead(tokens, range)) |call_head| {
                if (!call_head.is_intrinsic and sameCallableSourceName(func.source_name, publicDeclName(tokens[call_head.name_idx].lexeme))) {
                    return true;
                }
            }
        }
        i += 1;
    }
    return false;
}

fn funcHasDeferStmt(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEq(tokens[i], "defer")) return true;
    }
    return false;
}

fn hasManagedCleanupLocals(locals: *const LocalSet, ctx: CodegenContext) bool {
    for (locals.locals.items) |local| {
        if (!local.release_on_scope_exit) continue;
        if (managedLocalKindForType(local.ty, ctx) != null) return true;
    }
    return false;
}

fn emitSelfTailLoopLocalReset(
    allocator: std.mem.Allocator,
    func: FuncDecl,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !void {
    for (locals.locals.items) |local| {
        if (!local.emit_decl) continue;
        var is_param = false;
        for (func.params) |param| {
            if (param.callback != null) continue;
            if (std.mem.eql(u8, local.name, param.name)) {
                is_param = true;
                break;
            }
        }
        if (is_param) continue;
        try emitZeroValueForType(allocator, ctx, out, local.ty);
        try appendFmt(allocator, out, "    local.set ${s}\n", .{local.name});
    }
}

fn collectBodyLocals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    out: *LocalSet,
) !void {
    try collectBodyLocalsWithMode(allocator, tokens, start_idx, end_idx, ctx, out, true);
}

fn collectDirectBodyLocals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    out: *LocalSet,
) !void {
    try collectBodyLocalsWithMode(allocator, tokens, start_idx, end_idx, ctx, out, false);
}

fn collectBodyLocalsWithMode(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    out: *LocalSet,
    recurse_nested: bool,
) !void {
    var i = start_idx;
    while (i < end_idx) {
        const stmt_end = findStmtEnd(tokens, i, end_idx);
        if (stmtContainsStringLiteral(tokens, i, stmt_end) or
            stmtContainsFieldNameIntrinsic(tokens, i, stmt_end) or
            stmtContainsStorageAggLiteral(tokens, i, stmt_end) or
            stmtContainsStructLiteralExpr(tokens, i, stmt_end) or
            stmtContainsGetIntrinsic(tokens, i, stmt_end) or
            stmtContainsStorageComparisonIntrinsic(tokens, i, stmt_end) or
            stmtContainsNilComparisonCall(tokens, i, stmt_end) or
            stmtContainsUnionPayloadComparisonCall(tokens, i, stmt_end, out, ctx))
        {
            try out.ensureStorageWriteTemps(allocator);
        }
        if (stmtContainsStructLiteralExpr(tokens, i, stmt_end)) {
            try out.ensureStructLiteralTmp(allocator);
        }
        if (stmtContainsVariadicUserCall(tokens, i, stmt_end, out, ctx)) {
            try out.ensureStorageWriteTemps(allocator);
            try out.ensureVariadicPackTmp(allocator);
        }
        if (stmtContainsNumericSelectIntrinsic(tokens, i, stmt_end)) {
            try out.ensureNumericSelectTemps(allocator);
        }
        if (isDiscardAssignment(tokens, i, stmt_end)) {
            i = stmt_end;
            continue;
        }
        if (try isDeadManagedAliasBinding(allocator, tokens, i, stmt_end, end_idx, out, ctx)) {
            i = stmt_end;
            continue;
        }
        if (recurse_nested and try collectLoopBlockLocals(allocator, tokens, i, stmt_end, ctx, out)) {
            // Loop block locals collected recursively.
        } else if (recurse_nested and try collectIfBlockLocals(allocator, tokens, i, stmt_end, ctx, out)) {
            // Block locals collected recursively.
        } else if (recurse_nested and try collectDeferBlockLocals(allocator, tokens, i, stmt_end, ctx, out)) {
            // Cleanup block locals collected recursively.
        } else if (try typedUnionBindingLayout(allocator, tokens, i, stmt_end, ctx, &out.owned_names)) |layout| {
            defer freeUnionLayout(allocator, layout);
            const local_layout = try cloneUnionLayout(allocator, layout);
            try out.appendUnionLocal(allocator, tokens[i].lexeme, local_layout, true, true);
        } else if (try inferredUnionCallBinding(allocator, tokens, i, stmt_end, out, ctx, &out.owned_names)) |binding| {
            errdefer if (binding.owns_layout) freeUnionLayout(allocator, binding.layout);
            try out.appendUnionLocal(allocator, tokens[i].lexeme, binding.layout, true, binding.owns_layout);
        } else if (typedScalarBindingType(tokens, i, stmt_end, ctx)) |ty| {
            try out.appendBorrowedLocal(allocator, tokens[i].lexeme, ty, true);
        } else if (!hasLocal(out.locals.items, tokens[i].lexeme) and
            findStructLocal(out.struct_locals.items, tokens[i].lexeme) == null and
            inferredStructCtorBinding(tokens, i, stmt_end, ctx.structs) != null)
        {
            // Unmanaged pure-scalar structs live in struct_locals + field slots (`out.n`),
            // not as a single `out` scalar local. Reassignment (e.g. `out = @field_set(...)`)
            // must not invent a field-reflection-scoped shadow binding.
            const decl = inferredStructCtorBinding(tokens, i, stmt_end, ctx.structs).?;
            const local_name = try out.appendStructLocal(allocator, tokens[i].lexeme, decl.name, true);
            if (findStructLayout(ctx.struct_layouts, decl.name) != null) {
                try out.appendBorrowedLocal(allocator, tokens[i].lexeme, decl.name, true);
                for (decl.fields) |field| {
                    try appendManagedStructFieldMetaLocal(allocator, out, local_name, field.name, field.ty);
                }
                try out.ensureStorageWriteTemps(allocator);
            } else {
                for (decl.fields) |field| {
                    try appendLocalField(allocator, out, tokens, ctx, local_name, field.name, field.ty);
                }
            }
        } else if (!hasLocal(out.locals.items, tokens[i].lexeme) and
            findStructLocal(out.struct_locals.items, tokens[i].lexeme) == null and
            inferredStructBinding(tokens, i, stmt_end, out, ctx) != null)
        {
            const binding = inferredStructBinding(tokens, i, stmt_end, out, ctx).?;
            const local_name = try out.appendStructLocal(allocator, tokens[i].lexeme, binding.ty, true);
            if (findStructLayout(ctx.struct_layouts, binding.ty) != null) {
                try out.appendBorrowedLocal(allocator, tokens[i].lexeme, binding.ty, true);
                for (binding.decl.fields) |field| {
                    const field_ty = try substituteStructFieldType(allocator, binding.decl, binding.ty, field.ty, &out.owned_names);
                    try appendManagedStructFieldMetaLocal(allocator, out, local_name, field.name, field_ty);
                }
                try out.ensureStorageWriteTemps(allocator);
            } else {
                for (binding.decl.fields) |field| {
                    const field_ty = try substituteStructFieldType(allocator, binding.decl, binding.ty, field.ty, &out.owned_names);
                    try appendLocalField(allocator, out, tokens, ctx, local_name, field.name, field_ty);
                }
            }
        } else if (!hasLocal(out.locals.items, tokens[i].lexeme) and inferredScalarBindingType(tokens, i, stmt_end, out, ctx) != null) {
            const ty = inferredScalarBindingType(tokens, i, stmt_end, out, ctx).?;
            try out.appendBorrowedLocal(allocator, tokens[i].lexeme, ty, true);
        } else if (!hasLocal(out.locals.items, tokens[i].lexeme) and inferredManagedPayloadBinding(tokens, i, stmt_end, out, ctx) != null) {
            const binding = inferredManagedPayloadBinding(tokens, i, stmt_end, out, ctx).?;
            if (isTupleTypeName(binding.elem_ty) and tupleScalarLeafStorageByteWidthCtx(binding.elem_ty, ctx) == null) {
                return error.UnsupportedTupleStorageLeaf;
            }
            try out.appendStorageLocalWithType(allocator, tokens[i].lexeme, binding.ty, binding.elem_ty, true);
            try out.ensureStorageWriteTemps(allocator);
            if (tupleScalarLeafStorageByteWidthCtx(binding.elem_ty, ctx) != null) {
                try out.ensureTuplePackTemps(allocator);
            }
        } else if (try typedManagedPayloadBinding(allocator, tokens, i, stmt_end, ctx, &out.owned_names)) |binding| {
            if (isTupleTypeName(binding.elem_ty) and tupleScalarLeafStorageByteWidthCtx(binding.elem_ty, ctx) == null) {
                return error.UnsupportedTupleStorageLeaf;
            }
            try out.appendStorageLocalWithType(allocator, tokens[i].lexeme, binding.ty, binding.elem_ty, true);
            try out.ensureStorageWriteTemps(allocator);
            if (tupleScalarLeafStorageByteWidthCtx(binding.elem_ty, ctx) != null) {
                try out.ensureTuplePackTemps(allocator);
            }
        } else if (managedPayloadBinding(tokens, i, stmt_end)) |binding| {
            if (isTupleTypeName(binding.elem_ty) and tupleScalarLeafStorageByteWidthCtx(binding.elem_ty, ctx) == null) {
                return error.UnsupportedTupleStorageLeaf;
            }
            try out.appendStorageLocalWithType(allocator, tokens[i].lexeme, binding.ty, binding.elem_ty, true);
            try out.ensureStorageWriteTemps(allocator);
            if (tupleScalarLeafStorageByteWidthCtx(binding.elem_ty, ctx) != null) {
                try out.ensureTuplePackTemps(allocator);
            }
        } else if (storageBindingElemType(tokens, i, stmt_end)) |raw_elem_ty| {
            const elem_ty = try substituteGenericTypeOwned(allocator, raw_elem_ty, ctx.type_bindings, &out.owned_names);
            // Scheme A: scalar + managed handle + pure-scalar nested struct slots.
            if (isTupleTypeName(elem_ty) and tupleScalarLeafStorageByteWidthCtx(elem_ty, ctx) == null) {
                return error.UnsupportedTupleStorageLeaf;
            }
            try out.appendStorageLocal(allocator, tokens[i].lexeme, elem_ty, true);
            try out.ensureStorageWriteTemps(allocator);
            if (tupleScalarLeafStorageByteWidthCtx(elem_ty, ctx) != null) {
                try out.ensureTuplePackTemps(allocator);
            }
        } else if (try collectMultiResultAssignmentLocals(allocator, tokens, i, stmt_end, ctx, out)) {
            // Multi-result inferred locals collected.
        } else if (isManagedLocalAssignmentStmt(tokens, i, stmt_end, out, ctx)) {
            try out.ensureStorageWriteTemps(allocator);
        } else if (multiResultAssignmentNeedsManagedTmp(tokens, i, stmt_end, out, ctx)) {
            if (!hasLocal(out.locals.items, STORAGE_OVERWRITE_TMP_LOCAL)) {
                try out.appendBorrowedLocal(allocator, STORAGE_OVERWRITE_TMP_LOCAL, "usize", true);
            }
        } else if (try typedStructBinding(allocator, tokens, i, stmt_end, ctx, &out.owned_names)) |binding| {
            const local_name = try out.appendStructLocal(allocator, tokens[i].lexeme, binding.ty, true);
            if (findStructLayout(ctx.struct_layouts, binding.ty) != null) {
                try out.appendBorrowedLocal(allocator, tokens[i].lexeme, binding.ty, true);
                for (binding.decl.fields) |field| {
                    const field_ty = try substituteStructFieldType(allocator, binding.decl, binding.ty, field.ty, &out.owned_names);
                    try appendManagedStructFieldMetaLocal(allocator, out, local_name, field.name, field_ty);
                }
                try out.ensureStorageWriteTemps(allocator);
            } else {
                for (binding.decl.fields) |field| {
                    const field_ty = try substituteStructFieldType(allocator, binding.decl, binding.ty, field.ty, &out.owned_names);
                    try appendLocalField(allocator, out, tokens, ctx, local_name, field.name, field_ty);
                }
            }
        } else if (try typedTupleBindingType(allocator, tokens, i, stmt_end, ctx, &out.owned_names)) |tuple_ty| {
            const local_name = try out.appendStructLocal(allocator, tokens[i].lexeme, tuple_ty, true);
            try appendTupleLocalFields(allocator, out, tokens, ctx, local_name, tuple_ty);
        }
        i = stmt_end;
    }
}

fn collectMultiResultAssignmentLocals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    out: *LocalSet,
) CodegenError!bool {
    const eq_idx = findTopLevelToken(tokens, start_idx, end_idx, "=") orelse return false;
    if (findTopLevelToken(tokens, start_idx, eq_idx, ",") == null) return false;

    const rhs_range = trimParens(tokens, eq_idx + 1, end_idx);
    const call_head = exprCallHead(tokens, rhs_range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = findFuncDeclForCallHead(tokens, call_head, out, ctx) orelse return false;
    if (func.results.len <= 1 or func.result_items.len == 0) return false;

    var lhs_start = start_idx;
    var item_idx: usize = 0;
    while (lhs_start < eq_idx) {
        if (item_idx >= func.result_items.len) return error.NoMatchingCall;
        const lhs_end = findArgEnd(tokens, lhs_start, eq_idx);
        if (lhs_end != lhs_start + 1 or tokens[lhs_start].kind != .ident) return error.NoMatchingCall;
        const name = tokens[lhs_start].lexeme;
        if (!std.mem.eql(u8, name, "_")) {
            const item = func.result_items[item_idx];
            if (item.union_layout) |layout| {
                if (findUnionLocal(out.union_locals.items, name) == null) {
                    const cloned = try cloneUnionLayout(allocator, layout);
                    try out.appendUnionLocal(allocator, name, cloned, true, true);
                }
            } else if (findLocalType(out.locals.items, name) == null and
                findStructLocal(out.struct_locals.items, name) == null and
                findStorageLocal(out.storage_locals.items, name) == null)
            {
                try appendTypedLocalWithDecl(allocator, out, name, item.ty, ctx, true);
            }
        }

        item_idx += 1;
        lhs_start = lhs_end;
        if (lhs_start < eq_idx and tokEq(tokens[lhs_start], ",")) lhs_start += 1;
    }
    if (item_idx != func.result_items.len) return error.NoMatchingCall;
    return true;
}

fn stmtContainsVariadicUserCall(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        const call_head = callHeadAt(tokens, i, end_idx) orelse continue;
        if (call_head.is_intrinsic) continue;
        const func = findFuncDeclForCallHead(tokens, call_head, locals, ctx) orelse {
            i = call_head.args_end;
            continue;
        };
        if (funcHasVariadicParam(func)) return true;
        i = call_head.args_end;
    }
    return false;
}

fn stmtContainsStorageAggLiteral(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (tokEq(tokens[i], ".") and tokEq(tokens[i + 1], "{")) return true;
    }
    return false;
}

fn stmtContainsNilComparisonCall(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        const call_head = callHeadAt(tokens, i, end_idx) orelse continue;
        if (!call_head.is_intrinsic) {
            i = call_head.args_end;
            continue;
        }
        const call_name = tokens[call_head.name_idx].lexeme;
        if (!std.mem.eql(u8, call_name, "eq") and !std.mem.eql(u8, call_name, "ne")) {
            i = call_head.args_end;
            continue;
        }
        const first_end = findArgEnd(tokens, call_head.args_start, call_head.args_end);
        if (first_end == call_head.args_start or first_end >= call_head.args_end or !tokEq(tokens[first_end], ",")) {
            i = call_head.args_end;
            continue;
        }
        const second_start = first_end + 1;
        const second_end = findArgEnd(tokens, second_start, call_head.args_end);
        if (second_end != call_head.args_end) {
            i = call_head.args_end;
            continue;
        }
        const first_nil = first_end == call_head.args_start + 1 and tokEq(tokens[call_head.args_start], "nil");
        const second_nil = second_end == second_start + 1 and tokEq(tokens[second_start], "nil");
        if (first_nil or second_nil) return true;
        i = call_head.args_end;
    }
    return false;
}

fn stmtContainsUnionPayloadComparisonCall(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        const call_head = callHeadAt(tokens, i, end_idx) orelse continue;
        if (!call_head.is_intrinsic) {
            i = call_head.args_end;
            continue;
        }
        const call_name = tokens[call_head.name_idx].lexeme;
        if (!std.mem.eql(u8, call_name, "eq") and !std.mem.eql(u8, call_name, "ne")) {
            i = call_head.args_end;
            continue;
        }
        if (unionPayloadComparisonCallBranch(tokens, call_head.args_start, call_head.args_end, locals, ctx) != null) return true;
        i = call_head.args_end;
    }
    return false;
}

fn stmtContainsStructLiteralExpr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (tokens[i].kind == .ident and tokEq(tokens[i + 1], "{")) return true;
        if (tokens[i].kind == .ident and tokEq(tokens[i + 1], "<")) {
            var depth: usize = 0;
            var j = i + 1;
            while (j < end_idx) : (j += 1) {
                if (tokEq(tokens[j], "<")) {
                    depth += 1;
                } else if (tokEq(tokens[j], ">")) {
                    if (depth == 0) break;
                    depth -= 1;
                    if (depth == 0) {
                        j += 1;
                        break;
                    }
                }
            }
            if (j < end_idx and tokEq(tokens[j], "{")) return true;
        }
        if (tokEq(tokens[i], ".") and tokEq(tokens[i + 1], "{")) return true;
    }
    return false;
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
    if (fieldReflectionLoopHeader(tokens, start_idx, end_idx, ctx, out)) |header| {
        try collectFieldReflectionLoopLocals(allocator, tokens, header, ctx, out);
        return true;
    } else if (collectionLoopHeader(tokens, start_idx, end_idx, ctx, out)) |header| {
        try appendLoopIndexLocal(allocator, out, start_idx);
        if (header.source_is_expr) {
            try appendLoopSourceStorageLocal(allocator, out, start_idx, header.source_ty, header.elem_ty);
        }
        if (isManagedLocalType(header.elem_ty, ctx)) {
            try out.ensureStorageWriteTemps(allocator);
        }
        if (header.value_name) |value_name| {
            if (!hasLocal(out.locals.items, value_name)) {
                if (isTupleTypeName(header.elem_ty)) {
                    const local_name = try out.appendStructLocalWithOrigin(allocator, value_name, header.elem_ty, true, .collection_value);
                    try appendTupleLocalFields(allocator, out, tokens, ctx, local_name, header.elem_ty);
                    try out.ensureTuplePackTemps(allocator);
                } else {
                    try out.appendBorrowedLocalWithOrigin(allocator, value_name, header.elem_ty, true, .collection_value);
                }
            }
        }
        if (header.index_name) |index_name| {
            if (!hasLocal(out.locals.items, index_name)) {
                try out.appendBorrowedLocal(allocator, index_name, "usize", true);
            }
        }
    } else if (recvLoopHeader(tokens, start_idx, end_idx, ctx, out)) |header| {
        try appendLoopCountLocal(allocator, out, start_idx);
        if (isManagedLocalType(header.elem_ty, ctx)) {
            try out.ensureStorageWriteTemps(allocator);
        }
        if (header.value_name) |value_name| {
            if (!hasLocal(out.locals.items, value_name)) {
                if (isTupleTypeName(header.elem_ty)) {
                    const local_name = try out.appendStructLocalWithOrigin(allocator, value_name, header.elem_ty, true, .recv_value);
                    try appendTupleLocalFields(allocator, out, tokens, ctx, local_name, header.elem_ty);
                    try out.ensureTuplePackTemps(allocator);
                } else {
                    try out.appendBorrowedLocalWithOrigin(allocator, value_name, header.elem_ty, true, .recv_value);
                }
            }
        }
        if (header.count_name) |count_name| {
            if (!hasLocal(out.locals.items, count_name)) {
                try out.appendBorrowedLocal(allocator, count_name, "usize", true);
            }
        }
    }
    try collectBodyLocals(allocator, tokens, open_brace + 1, close_brace, ctx, out);
    return true;
}

fn collectFieldReflectionLoopLocals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    header: FieldReflectionLoopHeader,
    ctx: CodegenContext,
    out: *LocalSet,
) CodegenError!void {
    var visible_index: usize = 0;
    for (header.decl.fields, 0..) |field, decl_index| {
        if (!fieldVisibleFromTokens(field, header.decl, tokens)) continue;
        const prefix = try fieldReflectionLocalNamePrefix(allocator, header, visible_index);
        defer allocator.free(prefix);
        var field_locals = try borrowedFieldMetaLocalSet(allocator, out, .{
            .name = header.field_name,
            .struct_name = header.decl.name,
            .decl_index = decl_index,
            .visible_index = visible_index,
        }, prefix);
        defer field_locals.deinit(allocator);
        field_locals.local_name_prefix = prefix;
        try collectFieldReflectionBodyLocals(allocator, tokens, header.open_brace + 1, header.close_brace, ctx, &field_locals);
        try appendDeclOnlyLocals(allocator, out, &field_locals);
        visible_index += 1;
    }
}

fn collectFieldReflectionBodyLocals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    out: *LocalSet,
) CodegenError!void {
    var i = start_idx;
    while (i < end_idx) {
        const stmt_end = findStmtEnd(tokens, i, end_idx);
        if (fieldReflectionIfParts(tokens, i, stmt_end)) |parts| {
            if (fieldStaticBoolExpr(tokens, parts.cond_start, parts.cond_end, out, ctx)) |condition| {
                if (condition) {
                    try collectFieldReflectionBodyLocals(allocator, tokens, parts.then_start, parts.then_end, ctx, out);
                } else if (parts.else_if_start) |nested_if| {
                    try collectFieldReflectionBodyLocals(allocator, tokens, nested_if, stmt_end, ctx, out);
                } else if (parts.else_start) |else_start| {
                    try collectFieldReflectionBodyLocals(allocator, tokens, else_start, parts.else_end, ctx, out);
                }
                i = stmt_end;
                continue;
            }
        }
        try collectBodyLocals(allocator, tokens, i, stmt_end, ctx, out);
        try applyCollectGuardReturnNarrowing(allocator, tokens, i, stmt_end, out, ctx);
        try applyGuardLoopControlNarrowing(allocator, tokens, i, stmt_end, out, ctx);
        i = stmt_end;
    }
}

fn appendLoopIndexLocal(
    allocator: std.mem.Allocator,
    out: *LocalSet,
    loop_id: usize,
) !void {
    const name = try std.fmt.allocPrint(allocator, "__loop_index_{d}", .{loop_id});
    if (hasLocal(out.locals.items, name)) {
        allocator.free(name);
        return;
    }
    try out.appendOwnedLocalWithOrigin(allocator, name, "usize", .compiler_temp);
}

fn appendLoopCountLocal(
    allocator: std.mem.Allocator,
    out: *LocalSet,
    loop_id: usize,
) !void {
    const name = try std.fmt.allocPrint(allocator, "__loop_count_{d}", .{loop_id});
    if (hasLocal(out.locals.items, name)) {
        allocator.free(name);
        return;
    }
    try out.appendOwnedLocalWithOrigin(allocator, name, "usize", .compiler_temp);
}

fn appendLoopSourceStorageLocal(
    allocator: std.mem.Allocator,
    out: *LocalSet,
    loop_id: usize,
    ty: []const u8,
    elem_ty: []const u8,
) !void {
    const name = try loopSourceLocalName(allocator, loop_id);
    if (hasLocal(out.locals.items, name)) {
        allocator.free(name);
        return;
    }
    try out.owned_names.append(allocator, name);
    errdefer allocator.free(name);
    errdefer _ = out.owned_names.pop();
    try out.locals.append(allocator, .{
        .name = name,
        .ty = ty,
        .origin = .loop_source,
        .emit_decl = true,
    });
    try out.storage_locals.append(allocator, .{
        .name = name,
        .ty = ty,
        .elem_ty = elem_ty,
        .origin = .loop_source,
    });
}

fn loopSourceLocalName(allocator: std.mem.Allocator, loop_id: usize) ![]u8 {
    return try std.fmt.allocPrint(allocator, "__loop_source_{d}", .{loop_id});
}

fn fieldReflectionLoopHeader(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    locals: *const LocalSet,
) ?FieldReflectionLoopHeader {
    _ = locals;
    if (start_idx + 8 > end_idx) return null;
    if (!tokEq(tokens[start_idx], "loop")) return null;
    const open_brace = findTopLevelBlockOpen(tokens, start_idx + 1, end_idx) orelse return null;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return null;
    if (close_brace + 1 != end_idx) return null;
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, open_brace, "=") orelse return null;
    if (eq_idx != start_idx + 2) return null;
    if (tokens[start_idx + 1].kind != .ident) return null;
    if (eq_idx + 5 != open_brace) return null;
    if (!std.mem.eql(u8, tokens[eq_idx + 1].lexeme, "fields")) return null;
    if (!tokEq(tokens[eq_idx + 2], "(")) return null;
    if (tokens[eq_idx + 3].kind != .ident) return null;
    if (!tokEq(tokens[eq_idx + 4], ")")) return null;
    const type_name = substituteGenericType(tokens[eq_idx + 3].lexeme, ctx.type_bindings);
    const decl = findStructDecl(ctx.structs, type_name) orelse return null;
    return .{
        .field_name = tokens[start_idx + 1].lexeme,
        .decl = decl,
        .loop_idx = start_idx,
        .open_brace = open_brace,
        .close_brace = close_brace,
    };
}

fn collectionLoopHeader(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    locals: *const LocalSet,
) ?CollectionLoopHeader {
    if (start_idx + 6 > end_idx) return null;
    if (!tokEq(tokens[start_idx], "loop")) return null;
    const open_brace = findTopLevelBlockOpen(tokens, start_idx + 1, end_idx) orelse return null;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return null;
    if (close_brace + 1 != end_idx) return null;
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, open_brace, "=") orelse return null;
    const binds = parseCollectionLoopBinds(tokens, start_idx + 1, eq_idx) orelse return null;
    const source_start = eq_idx + 1;
    const source_end = open_brace;
    if (source_start >= source_end) return null;

    if (source_end == source_start + 1 and tokens[source_start].kind == .ident) {
        const storage = findStoragePrimitiveLocal(locals.storage_locals.items, tokens[source_start].lexeme) orelse return null;
        const elem_bytes = storageElementByteWidthForType(storage.elem_ty, ctx) orelse return null;
        return .{
            .value_name = binds.value_name,
            .index_name = binds.index_name,
            .source_name = tokens[source_start].lexeme,
            .source_ty = storage.ty,
            .source_start = source_start,
            .source_end = source_end,
            .elem_ty = storage.elem_ty,
            .elem_bytes = elem_bytes,
            .open_brace = open_brace,
            .close_brace = close_brace,
        };
    }

    const source_ty = inferExprType(tokens, source_start, source_end, locals, ctx) orelse return null;
    const elem_ty = storageElemTypeFromName(source_ty) orelse return null;
    const elem_bytes = storageElementByteWidthForType(elem_ty, ctx) orelse return null;
    return .{
        .value_name = binds.value_name,
        .index_name = binds.index_name,
        .source_name = "",
        .source_ty = source_ty,
        .source_start = source_start,
        .source_end = source_end,
        .source_is_expr = true,
        .elem_ty = elem_ty,
        .elem_bytes = elem_bytes,
        .open_brace = open_brace,
        .close_brace = close_brace,
    };
}

fn recvLoopHeader(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    locals: *const LocalSet,
) ?RecvLoopHeader {
    if (start_idx + 8 > end_idx) return null;
    if (!tokEq(tokens[start_idx], "loop")) return null;
    const open_brace = findTopLevelBlockOpen(tokens, start_idx + 1, end_idx) orelse return null;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return null;
    if (close_brace + 1 != end_idx) return null;
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, open_brace, "=") orelse return null;
    if (eq_idx + 5 != open_brace) return null;
    if (!tokEq(tokens[eq_idx + 1], "recv")) return null;
    if (!tokEq(tokens[eq_idx + 2], "(")) return null;
    if (tokens[eq_idx + 3].kind != .ident) return null;
    if (!tokEq(tokens[eq_idx + 4], ")")) return null;
    const storage = findStoragePrimitiveLocal(locals.storage_locals.items, tokens[eq_idx + 3].lexeme) orelse return null;
    const elem_bytes = storageElementByteWidthForType(storage.elem_ty, ctx) orelse return null;
    const binds = parseRecvLoopBinds(tokens, start_idx + 1, eq_idx) orelse return null;
    return .{
        .value_name = binds.value_name,
        .count_name = binds.count_name,
        .source_name = tokens[eq_idx + 3].lexeme,
        .elem_ty = storage.elem_ty,
        .elem_bytes = elem_bytes,
        .open_brace = open_brace,
        .close_brace = close_brace,
    };
}

const CollectionLoopBinds = struct {
    value_name: ?[]const u8,
    index_name: ?[]const u8,
};

const RecvLoopBinds = struct {
    value_name: ?[]const u8,
    count_name: ?[]const u8,
};

fn parseCollectionLoopBinds(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ?CollectionLoopBinds {
    if (start_idx + 3 != end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (!tokEq(tokens[start_idx + 1], ",")) return null;
    if (tokens[start_idx + 2].kind != .ident) return null;
    return .{
        .value_name = loopBindName(tokens[start_idx].lexeme),
        .index_name = loopBindName(tokens[start_idx + 2].lexeme),
    };
}

fn parseRecvLoopBinds(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ?RecvLoopBinds {
    if (start_idx + 1 == end_idx) {
        if (tokens[start_idx].kind != .ident) return null;
        return .{
            .value_name = loopBindName(tokens[start_idx].lexeme),
            .count_name = null,
        };
    }
    if (start_idx + 3 != end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (!tokEq(tokens[start_idx + 1], ",")) return null;
    if (tokens[start_idx + 2].kind != .ident) return null;
    return .{
        .value_name = loopBindName(tokens[start_idx].lexeme),
        .count_name = loopBindName(tokens[start_idx + 2].lexeme),
    };
}

fn loopBindName(name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, "_")) return null;
    return name;
}

fn labelForLoopStart(tokens: []const lexer.Token, loop_idx: usize) ?[]const u8 {
    if (loop_idx < 2) return null;
    const label_idx = previousLineStart(tokens, loop_idx) orelse return null;
    if (!tokEq(tokens[label_idx], "#")) return null;
    if (label_idx + 2 != loop_idx) return null;
    if (tokens[label_idx + 1].kind != .ident) return null;
    return tokens[label_idx + 1].lexeme;
}

fn previousLineStart(tokens: []const lexer.Token, idx: usize) ?usize {
    if (idx == 0 or idx > tokens.len) return null;
    const prev_line = tokens[idx - 1].line;
    var start = idx - 1;
    while (start > 0 and tokens[start - 1].line == prev_line) {
        start -= 1;
    }
    return start;
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
            .source_name = local.source_name,
            .ty = ty,
            .origin = local.origin,
            .emit_decl = local.emit_decl,
            .release_on_scope_exit = false,
        });
    }
    for (source.storage_locals.items) |storage| {
        if (findStorageLocalExact(out.storage_locals.items, storage.name) != null) continue;
        const name = try allocator.dupe(u8, storage.name);
        errdefer allocator.free(name);
        try out.owned_names.append(allocator, name);
        errdefer _ = out.owned_names.pop();

        const elem_ty = try allocator.dupe(u8, storage.elem_ty);
        errdefer allocator.free(elem_ty);
        try out.owned_names.append(allocator, elem_ty);
        errdefer _ = out.owned_names.pop();

        const ty = try allocator.dupe(u8, storage.ty);
        errdefer allocator.free(ty);
        try out.owned_names.append(allocator, ty);
        errdefer _ = out.owned_names.pop();

        try out.storage_locals.append(allocator, .{
            .name = name,
            .source_name = storage.source_name,
            .ty = ty,
            .elem_ty = elem_ty,
            .origin = storage.origin,
        });
    }
    for (source.struct_locals.items) |struct_local| {
        if (findStructLocalExact(out.struct_locals.items, struct_local.name) != null) continue;
        const name = try allocator.dupe(u8, struct_local.name);
        errdefer allocator.free(name);
        try out.owned_names.append(allocator, name);
        errdefer _ = out.owned_names.pop();

        const ty = try allocator.dupe(u8, struct_local.ty);
        errdefer allocator.free(ty);
        try out.owned_names.append(allocator, ty);
        errdefer _ = out.owned_names.pop();

        try out.struct_locals.append(allocator, .{
            .name = name,
            .source_name = struct_local.source_name,
            .ty = ty,
            .origin = struct_local.origin,
        });
    }
    for (source.union_locals.items) |union_local| {
        if (findUnionLocalExact(out.union_locals.items, union_local.name) != null) continue;
        const name = try allocator.dupe(u8, union_local.name);
        errdefer allocator.free(name);
        try out.owned_names.append(allocator, name);
        errdefer _ = out.owned_names.pop();
        const layout = try cloneUnionLayout(allocator, union_local.layout);
        try out.union_locals.append(allocator, .{
            .name = name,
            .source_name = union_local.source_name,
            .layout = layout,
            .owns_layout = true,
            .origin = union_local.origin,
        });
    }
}

fn appendLocalField(
    allocator: std.mem.Allocator,
    out: *LocalSet,
    tokens: []const lexer.Token,
    ctx: CodegenContext,
    base: []const u8,
    field: []const u8,
    ty: []const u8,
) !void {
    const name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ base, publicDeclName(field) });
    if (isTupleTypeName(ty)) {
        try out.owned_names.append(allocator, name);
        const local_name = try out.appendStructLocal(allocator, name, ty, true);
        try appendTupleLocalFields(allocator, out, tokens, ctx, local_name, ty);
        return;
    }
    // Pure-scalar unmanaged struct slot (e.g. Tuple.0 : Point) — nested field locals, not a single i32.
    if (findStructDecl(ctx.structs, ty)) |decl| {
        if (findStructLayout(ctx.struct_layouts, ty) == null and pureScalarStructPackWidth(decl, ctx.structs) != null) {
            try out.owned_names.append(allocator, name);
            const local_name = try out.appendStructLocal(allocator, name, ty, true);
            for (decl.fields) |sf| {
                const field_ty = try substituteStructFieldType(allocator, decl, ty, sf.ty, &out.owned_names);
                try appendLocalField(allocator, out, tokens, ctx, local_name, sf.name, field_ty);
            }
            return;
        }
    }
    if (try parseTypeUnionLayoutFromName(allocator, tokens, ty, ctx.structs, ctx.struct_layouts, &out.owned_names)) |layout| {
        errdefer freeUnionLayout(allocator, layout);
        const exists = findUnionLocalExact(out.union_locals.items, name) != null;
        if (!exists) {
            errdefer allocator.free(name);
            try out.owned_names.append(allocator, name);
            errdefer _ = out.owned_names.pop();
        } else {
            defer allocator.free(name);
        }
        return out.appendUnionLocal(allocator, name, layout, true, true);
    }
    try out.appendOwnedLocal(allocator, name, ty);
}

fn unionPayloadLocalName(allocator: std.mem.Allocator, base: []const u8, idx: usize) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}.__union_payload_{d}", .{ base, idx });
}

fn unionTagLocalName(allocator: std.mem.Allocator, base: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}.__union_tag", .{base});
}

fn appendUnionPayloadLocalGet(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    base: []const u8,
    idx: usize,
) !void {
    try appendFmt(allocator, out, "    local.get ${s}.__union_payload_{d}\n", .{ base, idx });
}

fn appendUnionPayloadLocalSet(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    base: []const u8,
    idx: usize,
) !void {
    try appendFmt(allocator, out, "    local.set ${s}.__union_payload_{d}\n", .{ base, idx });
}

fn appendUnionTagLocalGet(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    base: []const u8,
) !void {
    try appendFmt(allocator, out, "    local.get ${s}.__union_tag\n", .{base});
}

fn appendUnionTagLocalSet(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    base: []const u8,
) !void {
    try appendFmt(allocator, out, "    local.set ${s}.__union_tag\n", .{base});
}

fn appendBorrowedLocalField(
    allocator: std.mem.Allocator,
    out: *LocalSet,
    tokens: []const lexer.Token,
    ctx: CodegenContext,
    base: []const u8,
    field: []const u8,
    ty: []const u8,
) !void {
    const name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ base, publicDeclName(field) });
    if (isTupleTypeName(ty)) {
        try out.owned_names.append(allocator, name);
        const local_name = try out.appendStructLocal(allocator, name, ty, false);
        try appendTupleLocalFieldsBorrowed(allocator, out, tokens, ctx, local_name, ty);
        return;
    }
    if (findStructDecl(ctx.structs, ty)) |decl| {
        if (findStructLayout(ctx.struct_layouts, ty) == null and pureScalarStructPackWidth(decl, ctx.structs) != null) {
            try out.owned_names.append(allocator, name);
            const local_name = try out.appendStructLocal(allocator, name, ty, false);
            for (decl.fields) |sf| {
                const field_ty = try substituteStructFieldType(allocator, decl, ty, sf.ty, &out.owned_names);
                try appendBorrowedLocalField(allocator, out, tokens, ctx, local_name, sf.name, field_ty);
            }
            return;
        }
    }
    try out.owned_names.append(allocator, name);
    if (try parseTypeUnionLayoutFromName(allocator, tokens, ty, ctx.structs, ctx.struct_layouts, &out.owned_names)) |layout| {
        errdefer freeUnionLayout(allocator, layout);
        return out.appendUnionLocal(allocator, name, layout, false, true);
    }
    try out.appendBorrowedLocal(allocator, name, ty, false);
}

fn appendManagedStructFieldMetaLocal(
    allocator: std.mem.Allocator,
    out: *LocalSet,
    base: []const u8,
    field: []const u8,
    ty: []const u8,
) !void {
    const name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ base, publicDeclName(field) });
    try out.owned_names.append(allocator, name);
    try out.locals.append(allocator, .{
        .name = name,
        .ty = ty,
        .emit_decl = false,
        .release_on_scope_exit = false,
    });
}

fn appendStructFieldAbiParams(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    out: *std.ArrayList(u8),
    base: []const u8,
    field: []const u8,
    field_ty: []const u8,
    ctx: CodegenContext,
    owned_types: *std.ArrayList([]const u8),
) !void {
    const field_name = publicDeclName(field);
    if (try parseTypeUnionLayoutFromName(allocator, tokens, field_ty, ctx.structs, ctx.struct_layouts, owned_types)) |layout| {
        defer freeUnionLayout(allocator, layout);
        for (layout.payload_tys, 0..) |payload_ty, idx| {
            try appendFmt(allocator, out, " (param ${s}.{s}.__union_payload_{d} {s})", .{
                base,
                field_name,
                idx,
                codegenWasmType(ctx, payload_ty),
            });
        }
        try appendFmt(allocator, out, " (param ${s}.{s}.__union_tag i32)", .{ base, field_name });
        return;
    }
    try appendFmt(allocator, out, " (param ${s}.{s} {s})", .{
        base,
        field_name,
        codegenWasmType(ctx, field_ty),
    });
}

fn isCompilerLocalName(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "__") or std.mem.indexOf(u8, name, ".__") != null;
}

fn fieldReflectionLocalNamePrefix(
    allocator: std.mem.Allocator,
    header: FieldReflectionLoopHeader,
    visible_index: usize,
) ![]u8 {
    return std.fmt.allocPrint(allocator, "__field_{d}_{d}_", .{ header.open_brace, visible_index });
}

fn emitReturnStmt(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_start: usize,
    locals: *const LocalSet,
    return_cleanup_locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_items: []const FuncResultItem,
    result_struct: ?[]const u8,
    result_union: ?UnionLayout,
    defer_ctx: ?*const DeferContext,
    return_label: ?[]const u8,
    self_tail_tco: ?*const SelfTailTco,
    out: *std.ArrayList(u8),
) !bool {
    if (start_idx >= end_idx or !tokEq(tokens[start_idx], "return")) return false;
    if (self_tail_tco) |tco| {
        if (try emitSelfTailReturn(allocator, tokens, start_idx, end_idx, locals, ctx, tco.*, out)) {
            return true;
        }
    }
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
    if (result_union != null and try emitUnionReturn(allocator, tokens, start_idx, end_idx, locals, ctx, result_union.?, &move_names, defer_ctx, out)) {
        // Union value emitted as payload slots followed by runtime tag.
    } else if (try emitUnmanagedStructErrorUnionReturn(allocator, tokens, start_idx, end_idx, body_start, locals, ctx, result_tys, result_struct, defer_ctx, out)) {
        // Unmanaged struct plus error tag emitted as payload fields followed by status.
    } else if (try emitUnmanagedStructReturnLocal(allocator, tokens, start_idx, end_idx, locals, ctx, result_tys, result_struct, out)) {
        // Unmanaged struct fields emitted in declaration order.
    } else if (try emitTupleReturnLocal(allocator, tokens, start_idx, end_idx, locals, ctx, result_tys, result_items, out)) {
        // Tuple elements emitted as multi-value results in declaration order.
    } else if (try emitWasiRecordReturnCall(allocator, tokens, start_idx + 1, end_idx, locals, ctx, result_tys, result_struct, out)) {
        // WIT record result fields emitted in declaration order.
    } else if (result_tys.len > 1 and try emitMultiResultReturnCall(allocator, tokens, start_idx + 1, end_idx, locals, ctx, result_tys, defer_ctx, out)) {
        // Multi-result call passthrough emitted.
    } else if (result_tys.len > 1 and try emitTupleReturnExpr(allocator, tokens, start_idx + 1, end_idx, locals, ctx, result_tys, result_items, out)) {
        // Tuple constructor or multi-value expression returned as flattened ABI values.
    } else if (result_tys.len > 1 and result_items.len != 0) {
        try emitMultiResultReturnValues(allocator, tokens, start_idx + 1, end_idx, locals, ctx, result_items, &move_names, out);
    } else if (result_tys.len > 1) {
        try emitMultiResultReturnAbiValues(allocator, tokens, start_idx + 1, end_idx, locals, ctx, result_tys, &move_names, out);
    } else if (result_tys.len == 0 and start_idx + 2 == end_idx and tokEq(tokens[start_idx + 1], "nil")) {
        // `return nil` is the explicit spelling of an empty return in test/nil functions.
    } else if (start_idx + 1 < end_idx) {
        var emitted_move_call = false;
        var return_move_ctx: ?CallLastUseMoveContext = null;
        if (expected_ty) |ty| {
            if (isManagedLocalType(ty, ctx)) {
                return_move_ctx = .{
                    .body_start = body_start,
                    .stmt_end = end_idx,
                    .body_end = end_idx,
                    .defer_ctx = defer_ctx,
                    .allow_last_use_move = true,
                    .allow_field_read_move = true,
                };
                emitted_move_call = try emitManagedHandleCallExprWithMoveContext(
                    allocator,
                    tokens,
                    start_idx + 1,
                    end_idx,
                    end_idx,
                    true,
                    locals,
                    defer_ctx,
                    ctx,
                    ty,
                    out,
                );
            }
        }
        if (!emitted_move_call and !try emitExprWithMoveContext(allocator, tokens, start_idx + 1, end_idx, locals, ctx, expected_ty, if (return_move_ctx) |*move_ctx| move_ctx else null, out)) {
            return error.NoMatchingCall;
        }
    }
    try emitDeferCleanupStack(allocator, tokens, defer_ctx, locals, ctx, out);
    if (return_label) |label| {
        try appendFmt(allocator, out, "    br ${s}\n", .{label});
    } else {
        const release_plan = try buildReturnOwnershipPlan(allocator, return_cleanup_locals, ctx, move_names.items);
        defer release_plan.deinit(allocator);
        try emitOwnershipReleasePlan(allocator, release_plan, out);
        try out.appendSlice(allocator, "    return\n");
    }
    return true;
}

fn emitSelfTailReturn(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    tco: SelfTailTco,
    out: *std.ArrayList(u8),
) !bool {
    const range = trimParens(tokens, start_idx + 1, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return false;
    if (call_head.is_intrinsic) return false;
    if (!sameCallableSourceName(tco.func.source_name, publicDeclName(tokens[call_head.name_idx].lexeme))) return false;
    if (!callArgsMatchFuncParams(tokens, call_head.args_start, call_head.args_end, locals, ctx, tco.func)) return false;

    var arg_start = call_head.args_start;
    var param_idx: usize = 0;
    while (arg_start < call_head.args_end) {
        if (param_idx >= tco.func.params.len) return false;
        const param = tco.func.params[param_idx];
        if (param.callback != null or param.variadic) return false;
        const arg_end = findArgEnd(tokens, arg_start, call_head.args_end);
        if (!try emitExpr(allocator, tokens, arg_start, arg_end, locals, ctx, param.ty, out)) {
            return error.NoMatchingCall;
        }
        try appendFmt(allocator, out, "    local.set $__tail_arg_{s}\n", .{param.name});
        param_idx += 1;
        arg_start = arg_end;
        if (arg_start < call_head.args_end and tokEq(tokens[arg_start], ",")) arg_start += 1;
    }
    if (param_idx != tco.func.params.len) return false;

    for (tco.func.params) |param| {
        if (param.callback != null) continue;
        try appendFmt(allocator, out, "    local.get $__tail_arg_{s}\n", .{param.name});
        try appendFmt(allocator, out, "    local.set ${s}\n", .{param.name});
    }
    try appendFmt(allocator, out, "    br ${s}\n", .{tco.loop_label});
    return true;
}

fn emitUnmanagedStructErrorUnionReturn(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_start: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_struct: ?[]const u8,
    defer_ctx: ?*const DeferContext,
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
            const func = findFuncDeclForCallHead(tokens, call_head, locals, ctx) orelse return false;
            if (func.results.len == result_tys.len) {
                var matches = true;
                for (result_tys, 0..) |result_ty, i| {
                    if (!std.mem.eql(u8, result_ty, func.results[i])) {
                        matches = false;
                        break;
                    }
                }
                if (matches) {
                    const move_ctx = CallLastUseMoveContext{
                        .body_start = body_start,
                        .stmt_end = end_idx,
                        .body_end = end_idx,
                        .defer_ctx = defer_ctx,
                        .allow_last_use_move = true,
                    };
                    return try emitUserFuncCallWithMoveContext(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, &move_ctx, out);
                }
            }
        }
        return false;
    }

    if (range.end == range.start + 1 and tokens[range.start].kind == .ident) {
        const name = tokens[range.start].lexeme;
        if (findStructLocal(locals.struct_locals.items, name)) |struct_local| {
            if (std.mem.eql(u8, struct_local.ty, struct_name) and findStructLayout(ctx.struct_layouts, struct_name) == null) {
                try emitStructFieldsFromLocal(allocator, tokens, struct_local, decl, locals, ctx, false, out);
                try out.appendSlice(allocator, "    i32.const 0\n");
                return true;
            }
        }

        if (errorEnumBranchValue(tokens, error_name, name) != null or std.mem.eql(u8, findLocalType(locals.locals.items, name) orelse "", error_name)) {
            for (decl.fields) |field| {
                try emitZeroValueForType(allocator, ctx, out, field.ty);
            }
            if (!try emitExpr(allocator, tokens, range.start, range.end, locals, ctx, error_name, out)) return error.NoMatchingCall;
            return true;
        }
    }

    return false;
}

fn emitMultiResultReturnValues(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    result_items: []const FuncResultItem,
    move_names: *std.ArrayList([]const u8),
    out: *std.ArrayList(u8),
) CodegenError!void {
    var expr_start = start_idx;
    var item_idx: usize = 0;
    while (expr_start < end_idx) {
        if (item_idx >= result_items.len) return error.NoMatchingCall;
        const expr_end = findArgEnd(tokens, expr_start, end_idx);
        const item = result_items[item_idx];
        if (item.union_layout) |layout| {
            try collectUnionReturnMoveNames(allocator, tokens, expr_start, expr_end, locals, ctx, layout, move_names);
            if (!try emitUnionValue(allocator, tokens, expr_start, expr_end, locals, ctx, layout, false, null, out)) {
                return error.NoMatchingCall;
            }
        } else {
            try emitSingleReturnAbiValue(allocator, tokens, expr_start, expr_end, locals, ctx, item.ty, move_names, null, out);
        }
        item_idx += 1;
        expr_start = expr_end;
        if (expr_start < end_idx and tokEq(tokens[expr_start], ",")) expr_start += 1;
    }
    if (item_idx != result_items.len) return error.NoMatchingCall;
}

fn emitMultiResultReturnAbiValues(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    move_names: *std.ArrayList([]const u8),
    out: *std.ArrayList(u8),
) CodegenError!void {
    var expr_start = start_idx;
    var result_idx: usize = 0;
    while (expr_start < end_idx) {
        if (result_idx >= result_tys.len) return error.NoMatchingCall;
        const expr_end = findArgEnd(tokens, expr_start, end_idx);
        try emitSingleReturnAbiValue(allocator, tokens, expr_start, expr_end, locals, ctx, result_tys[result_idx], move_names, null, out);
        result_idx += 1;
        expr_start = expr_end;
        if (expr_start < end_idx and tokEq(tokens[expr_start], ",")) expr_start += 1;
    }
    if (result_idx != result_tys.len) return error.NoMatchingCall;
}

fn emitSingleReturnAbiValue(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    expected_ty: []const u8,
    move_names: *std.ArrayList([]const u8),
    move_ctx: ?*const CallLastUseMoveContext,
    out: *std.ArrayList(u8),
) CodegenError!void {
    if (try emitStorageAggReturnValue(allocator, tokens, start_idx, end_idx, locals, ctx, expected_ty, out)) {
        return;
    }

    var copy_returned_managed_local = false;
    if (isManagedLocalType(expected_ty, ctx)) {
        if (directManagedLocalExprName(tokens, start_idx, end_idx, locals, ctx)) |name| {
            if (hasBorrowedName(move_names.items, name)) {
                copy_returned_managed_local = true;
                try appendFmt(allocator, out, "    ;; arc-return-copy {s}\n", .{name});
            } else {
                try move_names.append(allocator, name);
                try appendFmt(allocator, out, "    ;; arc-return-move {s}\n", .{name});
            }
        }
    }
    var emitted_move_call = false;
    if (isManagedLocalType(expected_ty, ctx)) {
        if (move_ctx) |ctx_info| {
            emitted_move_call = try emitManagedHandleCallExprWithMoveContext(
                allocator,
                tokens,
                start_idx,
                end_idx,
                ctx_info.body_end,
                ctx_info.allow_last_use_move,
                locals,
                ctx_info.defer_ctx,
                ctx,
                expected_ty,
                out,
            );
        }
    }
    if (!emitted_move_call and !try emitExprWithMoveContext(allocator, tokens, start_idx, end_idx, locals, ctx, expected_ty, move_ctx, out)) {
        return error.NoMatchingCall;
    }
    if (copy_returned_managed_local) {
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
}

fn emitStorageAggReturnValue(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    expected_ty: []const u8,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const elem_ty = managedPayloadElemTypeFromName(expected_ty) orelse return false;
    const range = trimParens(tokens, start_idx, end_idx);
    if (!isStorageAggLiteralExpr(tokens, range.start, range.end)) return false;
    if (!try emitStorageAggLiteral(allocator, tokens, range.start, range.end, STORAGE_OVERWRITE_TMP_LOCAL, elem_ty, locals, ctx, out)) {
        return error.NoMatchingCall;
    }
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    return true;
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
    if (isTupleTypeName(struct_name)) return false;
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

fn singleTupleResultItem(result_items: []const FuncResultItem) ?FuncResultItem {
    if (result_items.len != 1) return null;
    const item = result_items[0];
    if (!isTupleTypeName(item.ty)) return null;
    if (item.abi_len < 2) return null;
    return item;
}

fn emitTupleReturnLocal(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_items: []const FuncResultItem,
    out: *std.ArrayList(u8),
) !bool {
    const item = singleTupleResultItem(result_items) orelse return false;
    if (item.abi_len != result_tys.len) return false;
    if (start_idx + 2 != end_idx) return false;
    if (tokens[start_idx + 1].kind != .ident) return false;
    const local_name = tokens[start_idx + 1].lexeme;
    const tuple_local = findStructLocal(locals.struct_locals.items, local_name) orelse return false;
    if (!std.mem.eql(u8, tuple_local.ty, item.ty)) return false;

    var leaf_types = std.ArrayList([]const u8).empty;
    defer leaf_types.deinit(allocator);
    try appendTupleLeafTypesWithStructs(allocator, item.ty, ctx.structs, &leaf_types);
    if (leaf_types.items.len != result_tys.len) return error.NoMatchingCall;
    for (leaf_types.items, 0..) |leaf_ty, idx| {
        if (!std.mem.eql(u8, leaf_ty, result_tys[idx])) return error.NoMatchingCall;
    }
    try emitTupleLocalGet(allocator, tuple_local.name, item.ty, ctx, out);
    return true;
}

fn emitTupleReturnExpr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_items: []const FuncResultItem,
    out: *std.ArrayList(u8),
) !bool {
    const item = singleTupleResultItem(result_items) orelse return false;
    if (item.abi_len != result_tys.len) return false;
    return try emitTupleExpr(allocator, tokens, start_idx, end_idx, locals, ctx, item.ty, out);
}

fn emitUnionReturn(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    layout: UnionLayout,
    move_names: *std.ArrayList([]const u8),
    defer_ctx: ?*const DeferContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (start_idx + 1 >= end_idx) return error.NoMatchingCall;
    const expr_start = start_idx + 1;
    const expr_end = end_idx;
    try collectUnionReturnMoveNames(allocator, tokens, expr_start, expr_end, locals, ctx, layout, move_names);
    const move_ctx = CallLastUseMoveContext{
        .stmt_end = end_idx,
        .body_end = end_idx,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = true,
    };
    return try emitUnionValue(allocator, tokens, expr_start, expr_end, locals, ctx, layout, false, &move_ctx, out);
}

fn collectUnionReturnMoveNames(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    layout: UnionLayout,
    move_names: *std.ArrayList([]const u8),
) !void {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.end != range.start + 1 or tokens[range.start].kind != .ident) return;
    const name = tokens[range.start].lexeme;
    if (findUnionLocal(locals.union_locals.items, name)) |union_local| {
        if (!unionLayoutsAbiCompatible(ctx, union_local.layout, layout)) return;
        for (layout.payload_tys, 0..) |payload_ty, idx| {
            if (!isManagedLocalType(payload_ty, ctx)) continue;
            const payload_name = try unionPayloadLocalName(allocator, union_local.name, idx);
            defer allocator.free(payload_name);
            const local_name = findLocalName(locals.locals.items, payload_name) orelse return;
            try move_names.append(allocator, local_name);
        }
        return;
    }
    const raw_ty = findLocalType(locals.locals.items, name) orelse return;
    const ty = substituteGenericType(raw_ty, ctx.type_bindings);
    if (!isManagedLocalType(ty, ctx)) return;
    if (findUnionBranchByCompatibleType(layout, ty) == null and !unionLayoutHasSinglePayloadAbiType(ctx, layout, ty)) return;
    try move_names.append(allocator, findLocalName(locals.locals.items, name) orelse name);
}

fn unionLayoutHasSinglePayloadAbiType(ctx: CodegenContext, layout: UnionLayout, ty: []const u8) bool {
    const target_wasm_ty = codegenWasmType(ctx, ty);
    for (layout.branches) |branch| {
        if (branch.payload_len != 1) continue;
        const payload_ty = layout.payload_tys[branch.payload_start];
        if (std.mem.eql(u8, codegenWasmType(ctx, payload_ty), target_wasm_ty)) return true;
    }
    return false;
}

fn emitUnionValue(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    layout: UnionLayout,
    copy_managed: bool,
    move_ctx: ?*const CallLastUseMoveContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.start >= range.end) return false;

    if (exprCallHead(tokens, range)) |call_head| {
        if (call_head.is_intrinsic) {
            const call_name = tokens[call_head.name_idx].lexeme;
            if (std.mem.eql(u8, call_name, "field_get")) {
                return try emitUnionFieldGetValue(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, layout, copy_managed, out);
            }
        } else {
            if (findFuncDeclForCallHead(tokens, call_head, locals, ctx)) |func| {
                if (func.result_union) |func_union| {
                    if (unionLayoutsAbiCompatible(ctx, func_union, layout)) {
                        return try emitUserFuncCallWithMoveContext(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, move_ctx, out);
                    }
                }
            }
        }
    }

    if (range.end == range.start + 1 and tokEq(tokens[range.start], "nil")) {
        for (layout.payload_tys) |payload_ty| {
            try emitZeroValueForType(allocator, ctx, out, payload_ty);
        }
        try out.appendSlice(allocator, "    i32.const 0\n");
        return true;
    }

    if (range.end == range.start + 1 and tokens[range.start].kind == .ident) {
        const name = tokens[range.start].lexeme;
        if (findUnionLocal(locals.union_locals.items, name)) |union_local| {
            if (unionLayoutsEqual(union_local.layout, layout)) {
                for (layout.payload_tys, 0..) |payload_ty, idx| {
                    try appendUnionPayloadLocalGet(allocator, out, union_local.name, idx);
                    if (copy_managed and isManagedLocalType(payload_ty, ctx)) {
                        try out.appendSlice(allocator, "    call $__arc_inc\n");
                    }
                }
                try appendUnionTagLocalGet(allocator, out, union_local.name);
                return true;
            }
        }
    }

    for (layout.branches) |branch| {
        if (branch.tag == 0) continue;
        if (try emitUnionBranchValue(allocator, tokens, range.start, range.end, locals, ctx, layout, branch, copy_managed, out)) {
            return true;
        }
    }
    return false;
}

fn emitUnionFieldGetValue(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    layout: UnionLayout,
    copy_managed: bool,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1 or tokens[start_idx].kind != .ident) return false;
    if (first_end >= end_idx or !tokEq(tokens[first_end], ",")) return false;
    const field_start = first_end + 1;
    const field_end = findArgEnd(tokens, field_start, end_idx);
    if (field_end != end_idx) return false;
    if (field_end != field_start + 1 or tokens[field_start].kind != .ident) return false;

    const struct_local = findStructLocal(locals.struct_locals.items, tokens[start_idx].lexeme) orelse return false;
    const meta = findFieldMetaLocal(locals.field_meta_locals.items, tokens[field_start].lexeme) orelse return false;
    if (!std.mem.eql(u8, typeBaseName(struct_local.ty), meta.struct_name)) return false;
    const field = fieldFromMeta(ctx, meta) orelse return false;

    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    const field_layout = (try parseTypeUnionLayoutFromName(allocator, tokens, field.ty, ctx.structs, ctx.struct_layouts, &owned_types)) orelse return false;
    defer freeUnionLayout(allocator, field_layout);
    if (!unionLayoutsEqual(field_layout, layout)) return false;

    const field_name = publicDeclName(field.name);
    const union_local_name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ struct_local.name, field_name });
    defer allocator.free(union_local_name);
    const union_local = findUnionLocal(locals.union_locals.items, union_local_name) orelse return false;
    if (!unionLayoutsEqual(union_local.layout, layout)) return false;

    for (layout.payload_tys, 0..) |payload_ty, idx| {
        try appendUnionPayloadLocalGet(allocator, out, union_local.name, idx);
        if (copy_managed and isManagedLocalType(payload_ty, ctx)) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
    }
    try appendUnionTagLocalGet(allocator, out, union_local.name);
    return true;
}

fn emitUnionBranchValue(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    layout: UnionLayout,
    branch: UnionBranch,
    copy_managed: bool,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    var branch_payload = std.ArrayList(u8).empty;
    defer branch_payload.deinit(allocator);
    if (!try emitUnionBranchPayload(allocator, tokens, start_idx, end_idx, locals, ctx, branch, copy_managed, &branch_payload)) {
        return false;
    }

    for (layout.payload_tys, 0..) |payload_ty, idx| {
        if (idx == branch.payload_start) {
            try out.appendSlice(allocator, branch_payload.items);
        } else if (idx > branch.payload_start and idx < branch.payload_start + branch.payload_len) {
            continue;
        } else {
            try emitZeroValueForType(allocator, ctx, out, payload_ty);
        }
    }
    try appendFmt(allocator, out, "    i32.const {d}\n", .{branch.tag});
    return true;
}

fn emitUnionBranchPayload(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    branch: UnionBranch,
    copy_managed: bool,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (branch.payload_len == 0) return false;
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.end == range.start + 1 and tokens[range.start].kind == .ident) {
        const name = tokens[range.start].lexeme;
        if (findStructLocal(locals.struct_locals.items, name)) |struct_local| {
            if (std.mem.eql(u8, struct_local.ty, branch.ty) and findStructLayout(ctx.struct_layouts, branch.ty) == null) {
                const decl = findStructDecl(ctx.structs, branch.ty) orelse return false;
                for (decl.fields) |field| {
                    try appendFmt(allocator, out, "    local.get ${s}.{s}\n", .{ struct_local.name, publicDeclName(field.name) });
                }
                return true;
            }
        }
    }

    if (!try emitExpr(allocator, tokens, range.start, range.end, locals, ctx, branch.ty, out)) return false;
    if (copy_managed and isManagedLocalType(branch.ty, ctx) and isDirectManagedLocalExpr(tokens, range.start, range.end, locals, ctx)) {
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
    return true;
}

fn unionLayoutsEqual(a: UnionLayout, b: UnionLayout) bool {
    if (a.branches.len != b.branches.len) return false;
    if (a.payload_tys.len != b.payload_tys.len) return false;
    for (a.payload_tys, 0..) |ty, idx| {
        if (!std.mem.eql(u8, ty, b.payload_tys[idx])) return false;
    }
    for (a.branches, 0..) |branch, idx| {
        const other = b.branches[idx];
        if (!std.mem.eql(u8, branch.ty, other.ty)) return false;
        if (branch.tag != other.tag) return false;
        if (branch.payload_start != other.payload_start) return false;
        if (branch.payload_len != other.payload_len) return false;
    }
    return true;
}

fn unionLayoutsAbiCompatible(ctx: CodegenContext, a: UnionLayout, b: UnionLayout) bool {
    if (a.branches.len != b.branches.len) return false;
    if (a.payload_tys.len != b.payload_tys.len) return false;
    for (a.payload_tys, 0..) |ty, idx| {
        if (!std.mem.eql(u8, codegenWasmType(ctx, ty), codegenWasmType(ctx, b.payload_tys[idx]))) return false;
    }
    for (a.branches, 0..) |branch, idx| {
        const other = b.branches[idx];
        if (branch.tag != other.tag) return false;
        if (branch.payload_start != other.payload_start) return false;
        if (branch.payload_len != other.payload_len) return false;
    }
    return true;
}

fn freeUnionLayout(allocator: std.mem.Allocator, layout: UnionLayout) void {
    allocator.free(layout.branches);
    allocator.free(layout.payload_tys);
}

fn cloneUnionLayout(allocator: std.mem.Allocator, layout: UnionLayout) !UnionLayout {
    const branches = try allocator.dupe(UnionBranch, layout.branches);
    errdefer allocator.free(branches);
    const payload_tys = try allocator.dupe([]const u8, layout.payload_tys);
    return .{
        .source_ty = layout.source_ty,
        .branches = branches,
        .payload_tys = payload_tys,
    };
}

fn cloneUnionLayoutSubstituted(
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
        const branch_ty = substituteGenericType(branch.ty, bindings);
        try source_ty.appendSlice(allocator, branch_ty);

        const payload_start = payload_tys.items.len;
        if (branch.tag != 0) {
            try appendUnionBranchPayloadTypes(allocator, tokens, branch_ty, structs, struct_layouts, &payload_tys);
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

fn parseTypeUnionLayoutFromName(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    ty: []const u8,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    owned_types: *std.ArrayList([]const u8),
) !?UnionLayout {
    if (findTopLevelTypeSeparator(ty, '|') == null) return null;
    var branches = std.ArrayList(UnionBranch).empty;
    errdefer branches.deinit(allocator);
    var payload_tys = std.ArrayList([]const u8).empty;
    errdefer payload_tys.deinit(allocator);

    var next_non_nil_tag: usize = 1;
    var branch_start: usize = 0;
    while (branch_start < ty.len) {
        const branch_end = findTopLevelTypeSeparatorFrom(ty, branch_start, '|') orelse ty.len;
        if (branch_end == branch_start) return error.NoMatchingCall;
        const branch_ty = ty[branch_start..branch_end];
        const payload_start = payload_tys.items.len;
        if (std.mem.eql(u8, branch_ty, "nil")) {
            try branches.append(allocator, .{
                .ty = "nil",
                .tag = 0,
                .payload_start = payload_start,
                .payload_len = 0,
            });
        } else {
            try appendUnionBranchPayloadTypes(allocator, tokens, branch_ty, structs, struct_layouts, &payload_tys);
            try branches.append(allocator, .{
                .ty = branch_ty,
                .tag = next_non_nil_tag,
                .payload_start = payload_start,
                .payload_len = payload_tys.items.len - payload_start,
            });
            next_non_nil_tag += 1;
        }
        branch_start = branch_end + 1;
    }

    if (branches.items.len < 2) return null;
    const source_ty = try allocator.dupe(u8, ty);
    errdefer allocator.free(source_ty);
    try owned_types.append(allocator, source_ty);
    return .{
        .source_ty = source_ty,
        .branches = try branches.toOwnedSlice(allocator),
        .payload_tys = try payload_tys.toOwnedSlice(allocator),
    };
}

fn findUnionBranchByType(layout: UnionLayout, ty: []const u8) ?UnionBranch {
    for (layout.branches) |branch| {
        if (codegenTypesCompatible(branch.ty, ty)) return branch;
    }
    return null;
}

fn findUnionBranchByCompatibleType(layout: UnionLayout, ty: []const u8) ?UnionBranch {
    for (layout.branches) |branch| {
        if (codegenTypesCompatible(branch.ty, ty)) return branch;
    }
    return null;
}

fn codegenTypesCompatible(expected: []const u8, actual: []const u8) bool {
    if (std.mem.eql(u8, expected, actual)) return true;
    if (std.mem.eql(u8, expected, "text") and std.mem.eql(u8, actual, "[u8]")) return true;
    if (std.mem.eql(u8, expected, "[u8]") and std.mem.eql(u8, actual, "text")) return true;
    return false;
}

fn emitZeroValueForType(
    allocator: std.mem.Allocator,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
    ty: []const u8,
) !void {
    try appendFmt(allocator, out, "    {s}.const 0\n", .{codegenWasmType(ctx, ty)});
}

fn emitMultiResultReturnCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    defer_ctx: ?*const DeferContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const range = trimParens(tokens, start_idx, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = findFuncDeclForCallHead(tokens, call_head, locals, ctx) orelse return false;
    if (func.results.len != result_tys.len) return false;
    for (result_tys, 0..) |result_ty, i| {
        if (!std.mem.eql(u8, result_ty, func.results[i])) return false;
    }
    const move_ctx = CallLastUseMoveContext{
        .stmt_end = end_idx,
        .body_end = end_idx,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = true,
    };
    return try emitUserFuncCallWithMoveContext(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, &move_ctx, out);
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
    const release_plan = try buildReturnOwnershipPlan(allocator, locals, ctx, skip_names);
    defer release_plan.deinit(allocator);
    try emitOwnershipReleasePlan(allocator, release_plan, out);
}

fn emitFallthroughReleaseManagedLocals(
    allocator: std.mem.Allocator,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !void {
    const release_plan = try buildFallthroughOwnershipPlan(allocator, locals, ctx);
    defer release_plan.deinit(allocator);
    if (release_plan.release_steps.len == 0) return;
    try out.appendSlice(allocator, "    ;; arc-fallthrough-release\n");
    try emitOwnershipReleasePlan(allocator, release_plan, out);
}

fn emitBlockReleaseManagedLocals(
    allocator: std.mem.Allocator,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !void {
    const release_plan = try buildBlockOwnershipPlan(allocator, locals, ctx);
    defer release_plan.deinit(allocator);
    if (release_plan.release_steps.len == 0) return;
    try out.appendSlice(allocator, "    ;; arc-block-release\n");
    try emitOwnershipReleasePlan(allocator, release_plan, out);
}

fn hasManagedLocals(locals: *const LocalSet, ctx: CodegenContext) bool {
    for (locals.locals.items) |local| {
        if (!local.release_on_scope_exit) continue;
        if (isManagedLocalType(local.ty, ctx)) return true;
    }
    return false;
}

const OwnedLoopFrames = struct {
    frames: []const ownership.LoopFrame,

    fn deinit(self: OwnedLoopFrames, allocator: std.mem.Allocator) void {
        for (self.frames) |frame| {
            if (frame.locals.len != 0) allocator.free(frame.locals);
        }
        if (self.frames.len != 0) allocator.free(self.frames);
    }
};

fn managedLocalKindForType(ty: []const u8, ctx: CodegenContext) ?ownership.ManagedLocalKind {
    if (isManagedPayloadType(ty)) return .storage;
    if (findStructLayout(ctx.struct_layouts, ty) != null) return .managed_struct;
    return null;
}

fn collectManagedOwnershipLocals(
    allocator: std.mem.Allocator,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ![]const ownership.ManagedLocal {
    var managed = std.ArrayList(ownership.ManagedLocal).empty;
    errdefer managed.deinit(allocator);

    for (locals.locals.items) |local| {
        if (!local.release_on_scope_exit) continue;
        const kind = managedLocalKindForType(local.ty, ctx) orelse continue;
        try managed.append(allocator, .{
            .name = local.name,
            .kind = kind,
        });
    }

    if (managed.items.len == 0) {
        managed.deinit(allocator);
        return &.{};
    }
    return try managed.toOwnedSlice(allocator);
}

fn buildReturnOwnershipPlan(
    allocator: std.mem.Allocator,
    locals: *const LocalSet,
    ctx: CodegenContext,
    skip_names: []const []const u8,
) !ownership.ExitPlan {
    const managed = try collectManagedOwnershipLocals(allocator, locals, ctx);
    defer if (managed.len != 0) allocator.free(managed);
    return ownership.buildReturnExitPlanWithFacts(allocator, managed, .{
        .cleanup_visible = true,
        .release_skip_names = skip_names,
    });
}

fn buildGuardReturnOwnershipPlan(
    allocator: std.mem.Allocator,
    locals: *const LocalSet,
    ctx: CodegenContext,
    skip_names: []const []const u8,
) !ownership.ExitPlan {
    const managed = try collectManagedOwnershipLocals(allocator, locals, ctx);
    defer if (managed.len != 0) allocator.free(managed);
    return ownership.buildGuardReturnExitPlanWithFacts(allocator, managed, .{
        .cleanup_visible = true,
        .release_skip_names = skip_names,
    });
}

fn buildFallthroughOwnershipPlan(
    allocator: std.mem.Allocator,
    locals: *const LocalSet,
    ctx: CodegenContext,
) !ownership.ExitPlan {
    const managed = try collectManagedOwnershipLocals(allocator, locals, ctx);
    defer if (managed.len != 0) allocator.free(managed);
    return ownership.buildFallthroughExitPlanWithFacts(allocator, managed, .{});
}

fn buildBlockOwnershipPlan(
    allocator: std.mem.Allocator,
    locals: *const LocalSet,
    ctx: CodegenContext,
) !ownership.ExitPlan {
    const managed = try collectManagedOwnershipLocals(allocator, locals, ctx);
    defer if (managed.len != 0) allocator.free(managed);
    return ownership.buildBlockExitPlanWithFacts(allocator, managed, .{});
}

fn collectLoopControlFrames(
    allocator: std.mem.Allocator,
    start: *const LoopControl,
    target: *const LoopControl,
    ctx: CodegenContext,
) !OwnedLoopFrames {
    var frames = std.ArrayList(ownership.LoopFrame).empty;
    errdefer {
        for (frames.items) |frame| {
            if (frame.locals.len != 0) allocator.free(frame.locals);
        }
        frames.deinit(allocator);
    }

    var cursor: ?*const LoopControl = start;
    while (cursor) |control| {
        const managed = try collectManagedOwnershipLocals(allocator, control.cleanup_locals, ctx);
        try frames.append(allocator, .{
            .locals = managed,
            .path_facts = .{},
        });
        if (sameLoopControl(control, target)) break;
        cursor = control.parent;
    }

    if (frames.items.len == 0) {
        frames.deinit(allocator);
        return .{ .frames = &.{} };
    }

    return .{
        .frames = try frames.toOwnedSlice(allocator),
    };
}

fn emitOwnershipReleasePlan(
    allocator: std.mem.Allocator,
    release_plan: ownership.ExitPlan,
    out: *std.ArrayList(u8),
) !void {
    for (release_plan.release_steps) |step| {
        try appendFmt(allocator, out, "    ;; arc-release-local {s}\n", .{step.local_name});
        try appendFmt(allocator, out, "    local.get ${s}\n", .{step.local_name});
        try out.appendSlice(allocator, "    call $__arc_dec\n");
        if (!step.clear_after_release) continue;
        try out.appendSlice(allocator, "    i32.const 0\n");
        try appendFmt(allocator, out, "    local.set ${s}\n", .{step.local_name});
    }
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

fn bodyCanReachEnd(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i < end_idx) {
        const stmt_end = findStmtEnd(tokens, i, end_idx);
        if (!stmtCanReachEnd(tokens, i, stmt_end)) return false;
        i = stmt_end;
    }
    return true;
}

fn stmtCanReachEnd(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx >= end_idx) return true;
    if (tokEq(tokens[start_idx], "return")) return false;
    if (tokEq(tokens[start_idx], "break") or tokEq(tokens[start_idx], "continue")) return false;
    if (tokEq(tokens[start_idx], "if")) return ifStmtCanReachEnd(tokens, start_idx, end_idx);
    if (tokEq(tokens[start_idx], "loop")) return loopStmtCanReachEnd(tokens, start_idx, end_idx);
    return true;
}

fn ifStmtCanReachEnd(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    const open_brace = findTopLevelBlockOpen(tokens, start_idx + 1, end_idx) orelse return true;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return true;

    var else_if_start: ?usize = null;
    var else_open: ?usize = null;
    var else_close: ?usize = null;
    if (close_brace + 1 < end_idx and tokEq(tokens[close_brace + 1], "else")) {
        if (close_brace + 2 >= end_idx) return true;
        if (tokEq(tokens[close_brace + 2], "if")) {
            else_if_start = close_brace + 2;
        } else if (tokEq(tokens[close_brace + 2], "{")) {
            const close_else = findMatchingInRange(tokens, close_brace + 2, "{", "}", end_idx) catch return true;
            if (close_else + 1 != end_idx) return true;
            else_open = close_brace + 2;
            else_close = close_else;
        } else {
            return true;
        }
    } else if (close_brace + 1 != end_idx) {
        return true;
    }

    const then_can_reach_end = bodyCanReachEnd(tokens, open_brace + 1, close_brace);
    const else_can_reach_end = if (else_if_start) |nested_if|
        ifStmtCanReachEnd(tokens, nested_if, end_idx)
    else if (else_open) |open_else|
        bodyCanReachEnd(tokens, open_else + 1, else_close orelse return true)
    else
        true;
    return then_can_reach_end or else_can_reach_end;
}

fn loopStmtCanReachEnd(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    const open_brace = findTopLevelBlockOpen(tokens, start_idx + 1, end_idx) orelse return true;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return true;
    if (close_brace + 1 != end_idx) return true;
    return loopBodyCanBreakCurrentLoop(tokens, open_brace + 1, close_brace, labelForLoopStart(tokens, start_idx));
}

fn isManagedLocalType(ty: []const u8, ctx: CodegenContext) bool {
    if (isManagedPayloadType(ty)) return true;
    // Storage-pack layouts describe `[Tuple<...>]` element packing, not a managed object type.
    if (findStructLayoutExact(ctx.struct_layouts, ty)) |layout| {
        if (layout.is_storage_pack) return false;
    }
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
    const name = tokens[start_idx].lexeme;

    if (findUnionLocal(locals.union_locals.items, name)) |union_local| {
        const payload_ty = unionLocalDefaultPayloadType(tokens, union_local) orelse return null;
        if (!isManagedLocalType(payload_ty, ctx)) return null;
        var matched_idx: ?usize = null;
        for (union_local.layout.payload_tys, 0..) |candidate_ty, idx| {
            if (!std.mem.eql(u8, candidate_ty, payload_ty)) continue;
            if (matched_idx != null) return null;
            matched_idx = idx;
        }
        return unionPayloadLocalNameFromLocals(locals.locals.items, union_local.name, matched_idx orelse return null);
    }

    const ty = findLocalType(locals.locals.items, name) orelse return null;
    if (!isManagedLocalType(ty, ctx)) return null;
    if (isUnionPayloadLocalName(locals.union_locals.items, name)) return name;
    return findLocalName(locals.locals.items, name);
}

const LastUseManagedMoveSource = struct {
    source_name: []const u8,
    actual_name: []const u8,
    origin: SourceOrigin,
};

const CallLastUseMoveContext = struct {
    body_start: usize = 0,
    stmt_end: usize,
    body_end: usize,
    defer_ctx: ?*const DeferContext,
    allow_last_use_move: bool,
    allow_field_read_move: bool = false,
};

fn isDeadManagedAliasBinding(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    stmt_end: usize,
    body_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) CodegenError!bool {
    if (start_idx >= stmt_end or tokens[start_idx].kind != .ident) return false;
    const target_name = tokens[start_idx].lexeme;
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, stmt_end, "=") orelse return false;
    if (tokenRangeUsesIdent(tokens, stmt_end, body_end, target_name)) return false;
    if (!isDirectManagedLocalExpr(tokens, eq_idx + 1, stmt_end, locals, ctx)) return false;
    if (storageBindingElemType(tokens, start_idx, stmt_end) != null) return true;
    if (managedPayloadBinding(tokens, start_idx, stmt_end) != null) return true;

    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    const binding = (try typedStructBinding(allocator, tokens, start_idx, stmt_end, ctx, &owned_types)) orelse return false;
    return findStructLayout(ctx.struct_layouts, binding.ty) != null;
}

fn tokenRangeUsesIdent(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    name: []const u8,
) bool {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (std.mem.eql(u8, tokens[i].lexeme, name)) return true;
    }
    return false;
}

fn hasRegisteredDeferStmt(
    tokens: []const lexer.Token,
    defer_ctx: ?*const DeferContext,
) bool {
    var cursor = defer_ctx;
    while (cursor) |scope| {
        const scan_end = @min(scope.registered_end_idx, scope.end_idx);
        var i = scope.start_idx;
        while (i < scan_end) {
            const stmt_end = findStmtEnd(tokens, i, scope.end_idx);
            if (isDeferStmt(tokens, i, stmt_end)) return true;
            i = stmt_end;
        }
        cursor = scope.parent;
    }
    return false;
}

fn structLocalSourceName(local: StructLocal) []const u8 {
    return local.source_name orelse local.name;
}

fn factsSourceOrigin(origin: SourceOrigin) ownership_facts.SourceOrigin {
    return switch (origin) {
        .unknown => .unknown,
        .fresh_local => .fresh_local,
        .param_or_import => .param_or_import,
        .helper_shared => .helper_shared,
        .collection_value => .collection_value,
        .recv_value => .recv_value,
        .loop_source => .loop_source,
        .union_payload => .union_payload,
        .compiler_temp => .compiler_temp,
    };
}

fn directManagedLastUseMoveSource(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_end: usize,
    target_source_name: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    defer_ctx: ?*const DeferContext,
) ?LastUseManagedMoveSource {
    if (end_idx != start_idx + 1 or tokens[start_idx].kind != .ident) return null;
    const source_name = tokens[start_idx].lexeme;
    if (std.mem.eql(u8, source_name, target_source_name)) return null;
    if (hasRegisteredDeferStmt(tokens, defer_ctx)) return null;
    const actual_name = directManagedLocalExprName(tokens, start_idx, end_idx, locals, ctx) orelse return null;
    const origin = findLocalOrigin(locals.locals.items, source_name) orelse .unknown;
    if (tokenRangeUsesIdent(tokens, end_idx, body_end, source_name)) return null;
    return .{
        .source_name = source_name,
        .actual_name = actual_name,
        .origin = origin,
    };
}

fn directManagedLastUseMoveSourceOrigin(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_end: usize,
    target_source_name: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    defer_ctx: ?*const DeferContext,
) ?SourceOrigin {
    const source = directManagedLastUseMoveSource(tokens, start_idx, end_idx, body_end, target_source_name, locals, ctx, defer_ctx) orelse return null;
    return source.origin;
}

fn freshStructLiteralBindingStmtEnd(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    body_start: usize,
    expr_start: usize,
    source_name: []const u8,
    struct_ty: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
) CodegenError!?usize {
    var i = body_start;
    while (i < expr_start) {
        const stmt_end = findStmtEnd(tokens, i, expr_start);
        if (tokens[i].kind == .ident and std.mem.eql(u8, tokens[i].lexeme, source_name)) {
            const eq_idx = findTopLevelToken(tokens, i + 1, stmt_end, "=") orelse return null;
            if (!isStructLiteralRhs(tokens, eq_idx + 1, stmt_end)) return null;

            var owned_types = std.ArrayList([]const u8).empty;
            defer {
                for (owned_types.items) |owned| allocator.free(owned);
                owned_types.deinit(allocator);
            }

            if (try typedStructBinding(allocator, tokens, i, stmt_end, ctx, &owned_types)) |binding| {
                if (std.mem.eql(u8, binding.ty, struct_ty)) return stmt_end;
                return null;
            }
            if (inferredStructBinding(tokens, i, stmt_end, locals, ctx)) |binding| {
                if (std.mem.eql(u8, binding.ty, struct_ty)) return stmt_end;
            }
            return null;
        }
        i = stmt_end;
    }
    return null;
}

fn fieldGetLastUseMoveSource(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    struct_local: StructLocal,
    field_ty: []const u8,
    move_ctx: CallLastUseMoveContext,
    locals: *const LocalSet,
    ctx: CodegenContext,
) CodegenError!?LastUseManagedMoveSource {
    if (!isManagedLocalType(field_ty, ctx)) return null;

    const body_start = move_ctx.body_start;
    const source_name = structLocalSourceName(struct_local);
    const decl_end = (try freshStructLiteralBindingStmtEnd(
        allocator,
        tokens,
        body_start,
        start_idx,
        source_name,
        struct_local.ty,
        locals,
        ctx,
    )) orelse return null;
    const fresh_source_gap = tokenRangeUsesIdent(tokens, decl_end, start_idx, source_name);
    const after_expr_use = tokenRangeUsesIdent(tokens, end_idx, move_ctx.stmt_end, source_name);
    const body_rest_use = tokenRangeUsesIdent(tokens, move_ctx.stmt_end, move_ctx.body_end, source_name);
    const candidate = ownership_facts.MoveCandidate{
        .kind = .field_get,
        .source = .{
            .source_name = source_name,
            .actual_name = struct_local.name,
            .origin = .fresh_local,
        },
        .expr_range = .{ .start = start_idx, .end = end_idx },
        .context = .{
            .body = .{ .start = move_ctx.body_start, .end = move_ctx.body_end },
            .statement = .{ .end = move_ctx.stmt_end },
            .defer_visible = hasRegisteredDeferStmt(tokens, move_ctx.defer_ctx),
            .allow_last_use_move = move_ctx.allow_last_use_move,
            .allow_field_read_move = move_ctx.allow_field_read_move,
        },
        .future_use = .{
            .fresh_source_gap = if (fresh_source_gap) .{ .start = decl_end, .end = start_idx } else null,
            .after_expr = if (after_expr_use) .{ .start = end_idx, .end = move_ctx.stmt_end } else null,
            .body_rest = if (body_rest_use) .{ .start = move_ctx.stmt_end, .end = move_ctx.body_end } else null,
        },
    };
    const decision = ownership_facts.decideFieldGetMove(candidate);
    if (!decision.accepted) return null;
    return .{
        .source_name = source_name,
        .actual_name = struct_local.name,
        .origin = struct_local.origin,
    };
}

fn directManagedCallLastUseMoveSource(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    move_ctx: CallLastUseMoveContext,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?LastUseManagedMoveSource {
    if (end_idx != start_idx + 1 or tokens[start_idx].kind != .ident) return null;
    const source_name = tokens[start_idx].lexeme;
    const actual_name = directManagedLocalExprName(tokens, start_idx, end_idx, locals, ctx) orelse return null;
    const origin = findLocalOrigin(locals.locals.items, source_name) orelse .unknown;
    const after_arg_use = tokenRangeUsesIdent(tokens, end_idx, move_ctx.stmt_end, source_name);
    const after_stmt_use = tokenRangeUsesIdent(tokens, move_ctx.stmt_end, move_ctx.body_end, source_name);
    const candidate = ownership_facts.MoveCandidate{
        .kind = .call_arg,
        .source = .{
            .source_name = source_name,
            .actual_name = actual_name,
            .origin = factsSourceOrigin(origin),
        },
        .expr_range = .{ .start = start_idx, .end = end_idx },
        .context = .{
            .body = .{ .start = move_ctx.body_start, .end = move_ctx.body_end },
            .statement = .{ .end = move_ctx.stmt_end },
            .arg = .{ .start = start_idx, .end = end_idx },
            .defer_visible = hasRegisteredDeferStmt(tokens, move_ctx.defer_ctx),
            .allow_last_use_move = move_ctx.allow_last_use_move,
        },
        .future_use = .{
            .after_arg = if (after_arg_use) .{ .start = end_idx, .end = move_ctx.stmt_end } else null,
            .after_stmt = if (after_stmt_use) .{ .start = move_ctx.stmt_end, .end = move_ctx.body_end } else null,
        },
    };
    const decision = ownership_facts.decideCallArgMove(candidate);
    if (!decision.accepted) return null;
    return .{
        .source_name = source_name,
        .actual_name = actual_name,
        .origin = origin,
    };
}

fn directManagedCallLastUseMoveSourceOrigin(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    move_ctx: CallLastUseMoveContext,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?SourceOrigin {
    const source = directManagedCallLastUseMoveSource(tokens, start_idx, end_idx, move_ctx, locals, ctx) orelse return null;
    return source.origin;
}

fn directManagedUnionBindingCallMoveSource(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    args_end: usize,
    stmt_end: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    ctx: CodegenContext,
    defer_ctx: ?*const DeferContext,
) ?LastUseManagedMoveSource {
    if (end_idx != start_idx + 1 or tokens[start_idx].kind != .ident) return null;
    if (!allow_last_use_move) return null;
    if (hasRegisteredDeferStmt(tokens, defer_ctx)) return null;
    const source_name = tokens[start_idx].lexeme;
    const actual_name = directManagedLocalExprName(tokens, start_idx, end_idx, locals, ctx) orelse return null;
    const origin = findLocalOrigin(locals.locals.items, source_name) orelse .unknown;
    if (tokenRangeUsesIdent(tokens, end_idx, args_end, source_name)) return null;
    if (tokenRangeUsesIdent(tokens, stmt_end, body_end, source_name)) return null;
    return .{
        .source_name = source_name,
        .actual_name = actual_name,
        .origin = origin,
    };
}

fn directManagedUnionBindingCallMoveSourceOrigin(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    args_end: usize,
    stmt_end: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    ctx: CodegenContext,
    defer_ctx: ?*const DeferContext,
) ?SourceOrigin {
    const source = directManagedUnionBindingCallMoveSource(tokens, start_idx, end_idx, args_end, stmt_end, body_end, allow_last_use_move, locals, ctx, defer_ctx) orelse return null;
    return source.origin;
}

fn hasMoveSource(sources: []const LastUseManagedMoveSource, actual_name: []const u8) bool {
    for (sources) |source| {
        if (std.mem.eql(u8, source.actual_name, actual_name)) return true;
    }
    return false;
}

fn unionPayloadLocalNameFromLocals(
    locals: []const Local,
    base: []const u8,
    idx: usize,
) ?[]const u8 {
    var suffix_buf: [32]u8 = undefined;
    const suffix = std.fmt.bufPrint(&suffix_buf, ".__union_payload_{d}", .{idx}) catch return null;
    for (locals) |local| {
        if (local.name.len != base.len + suffix.len) continue;
        if (!std.mem.startsWith(u8, local.name, base)) continue;
        if (!std.mem.eql(u8, local.name[base.len..], suffix)) continue;
        return local.name;
    }
    return null;
}

fn isUnionPayloadLocalName(
    union_locals: []const UnionLocal,
    name: []const u8,
) bool {
    for (union_locals) |union_local| {
        for (union_local.layout.payload_tys, 0..) |_, idx| {
            var suffix_buf: [32]u8 = undefined;
            const suffix = std.fmt.bufPrint(&suffix_buf, ".__union_payload_{d}", .{idx}) catch return false;
            if (name.len != union_local.name.len + suffix.len) continue;
            if (!std.mem.startsWith(u8, name, union_local.name)) continue;
            if (!std.mem.eql(u8, name[union_local.name.len..], suffix)) continue;
            return true;
        }
    }
    return false;
}

fn emitStorageBinding(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_start: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !void {
    const source_name = tokens[start_idx].lexeme;
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return error.NoMatchingCall;
    if (eq_idx + 1 >= end_idx) return error.NoMatchingCall;
    const storage = findStorageLocal(locals.storage_locals.items, source_name) orelse return error.NoMatchingCall;
    const target_name = storage.name;
    if (tokens[eq_idx + 1].kind == .string) {
        if (!std.mem.eql(u8, storage.elem_ty, "u8")) return error.NoMatchingCall;
        try emitStorageU8StringLiteral(allocator, tokens, eq_idx + 1, target_name, ctx, out);
        return;
    }

    if (try emitStorageAggLiteral(allocator, tokens, eq_idx + 1, end_idx, target_name, storage.elem_ty, locals, ctx, out)) return;

    if (try emitStorageWriteExpr(allocator, tokens, eq_idx + 1, end_idx, target_name, locals, ctx, out)) {
        try appendFmt(allocator, out, "    local.set ${s}\n", .{target_name});
        return;
    }

    const expected_ty = findLocalType(locals.locals.items, source_name) orelse return error.NoMatchingCall;
    const emitted_move_call = try emitManagedHandleCallExprWithMoveContext(
        allocator,
        tokens,
        eq_idx + 1,
        end_idx,
        body_end,
        allow_last_use_move,
        locals,
        defer_ctx,
        ctx,
        expected_ty,
        out,
    );
    if (emitted_move_call or try emitStorageHandleBindingExpr(allocator, tokens, eq_idx + 1, end_idx, body_start, body_end, allow_last_use_move, expected_ty, locals, defer_ctx, ctx, out)) {
        if (!emitted_move_call and isDirectManagedLocalExpr(tokens, eq_idx + 1, end_idx, locals, ctx)) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
        try appendFmt(allocator, out, "    local.set ${s}\n", .{target_name});
        return;
    }

    return error.NoMatchingCall;
}

fn emitStorageHandleBindingExpr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_start: usize,
    body_end: usize,
    allow_last_use_move: bool,
    expected_ty: []const u8,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (!std.mem.eql(u8, inferExprType(tokens, start_idx, end_idx, locals, ctx) orelse "", expected_ty)) return false;
    const move_ctx = if (allow_last_use_move) CallLastUseMoveContext{
        .body_start = body_start,
        .stmt_end = end_idx,
        .body_end = body_end,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = true,
        .allow_field_read_move = true,
    } else null;
    if (!try emitExprWithMoveContext(allocator, tokens, start_idx, end_idx, locals, ctx, expected_ty, if (move_ctx) |*ctx_info| ctx_info else null, out)) return false;
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

fn emitStorageU8RawStringValue(
    allocator: std.mem.Allocator,
    key: []const u8,
    local_name: []const u8,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !void {
    const data = ctx.string_data.find(key) orelse return error.NoMatchingCall;
    try appendFmt(allocator, out, "    i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES + data.bytes.len});
    try appendFmt(allocator, out, "    i32.const {d}\n", .{TYPE_ID_STORAGE_U8});
    try out.appendSlice(allocator, "    call $__arc_alloc\n");
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
    try appendFmt(allocator, out, "    local.get ${s}\n", .{local_name});
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
    try out.appendSlice(allocator, "    call $__arc_alloc\n");
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
    try out.appendSlice(allocator, "    call $__arc_alloc\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{local_name});
    const aggregate_name = if (isManagedLocalType(elem_ty, ctx) and std.mem.eql(u8, local_name, STORAGE_OVERWRITE_TMP_LOCAL))
        STORAGE_WRITE_NEXT_TMP_LOCAL
    else
        local_name;
    if (!std.mem.eql(u8, aggregate_name, local_name)) {
        try appendFmt(allocator, out, "    local.get ${s}\n", .{local_name});
        try appendFmt(allocator, out, "    local.set ${s}\n", .{aggregate_name});
    }
    try emitStorageLenPtr(allocator, out, aggregate_name);
    try appendFmt(allocator, out, "    i32.const {d}\n", .{count});
    try out.appendSlice(allocator, "    i32.store\n");
    try emitStorageCapPtr(allocator, out, aggregate_name);
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
        if (isTupleTypeName(elem_ty)) {
            // Multi-value leaves cannot sit under a store address; pack via base temp.
            if (!try emitExpr(allocator, tokens, item_start, item_end, locals, ctx, elem_ty, out)) return error.NoMatchingCall;
            try emitStorageDataPtr(allocator, out, aggregate_name);
            if (item_index * elem_bytes != 0) {
                try appendFmt(allocator, out, "    i32.const {d}\n", .{item_index * elem_bytes});
                try out.appendSlice(allocator, "    i32.add\n");
            }
            try appendFmt(allocator, out, "    local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
            try appendStoreTupleLeavesOwningFromStackCtx(allocator, out, elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "    ", ctx);
        } else {
            try emitStorageDataPtr(allocator, out, aggregate_name);
            if (item_index * elem_bytes != 0) {
                try appendFmt(allocator, out, "    i32.const {d}\n", .{item_index * elem_bytes});
                try out.appendSlice(allocator, "    i32.add\n");
            }
            if (!try emitExpr(allocator, tokens, item_start, item_end, locals, ctx, elem_ty, out)) return error.NoMatchingCall;
            if (isManagedLocalType(elem_ty, ctx) and isDirectManagedLocalExpr(tokens, item_start, item_end, locals, ctx)) {
                try out.appendSlice(allocator, "    ;; storage-managed-element-inc\n");
                try out.appendSlice(allocator, "    call $__arc_inc\n");
            }
            try appendStoreForPayloadType(allocator, out, elem_ty);
        }
        item_index += 1;
        item_start = item_end;
        if (item_start < close_brace and tokEq(tokens[item_start], ",")) item_start += 1;
    }
    if (item_index != count) return error.NoMatchingCall;
    if (!std.mem.eql(u8, aggregate_name, local_name)) {
        try appendFmt(allocator, out, "    local.get ${s}\n", .{aggregate_name});
        try appendFmt(allocator, out, "    local.set ${s}\n", .{local_name});
    }
    return true;
}

fn isStorageAggLiteralExpr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 2 > end_idx) return false;
    if (!tokEq(tokens[start_idx], ".")) return false;
    if (!tokEq(tokens[start_idx + 1], "{")) return false;
    const close_brace = findMatchingInRange(tokens, start_idx + 1, "{", "}", end_idx) catch return false;
    return close_brace + 1 == end_idx;
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
    try storage_wat.emitStoragePayloadPtr(allocator, out, name);
}

fn emitStorageLenPtr(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
) !void {
    try storage_wat.emitStorageLenPtr(allocator, out, name);
}

fn emitStorageLenPtrWithIndent(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
    indent: []const u8,
) !void {
    try storage_wat.emitStorageLenPtrWithIndent(allocator, out, name, indent);
}

fn emitStorageCapPtr(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
) !void {
    try storage_wat.emitStorageCapPtr(allocator, out, name);
}

fn emitStorageCapPtrWithIndent(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
    indent: []const u8,
) !void {
    try storage_wat.emitStorageCapPtrWithIndent(allocator, out, name, indent);
}

fn emitStorageDataPtr(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
) !void {
    try storage_wat.emitStorageDataPtr(allocator, out, name);
}

fn emitStoragePayloadPtrWithIndent(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
    indent: []const u8,
) !void {
    try storage_wat.emitStoragePayloadPtrWithIndent(allocator, out, name, indent);
}

fn emitStructFieldValue(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    field_ty: []const u8,
    copy_managed: bool,
    out: *std.ArrayList(u8),
) CodegenError!void {
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    if (try parseTypeUnionLayoutFromName(allocator, tokens, field_ty, ctx.structs, ctx.struct_layouts, &owned_types)) |layout| {
        defer freeUnionLayout(allocator, layout);
        if (!try emitUnionValue(allocator, tokens, start_idx, end_idx, locals, ctx, layout, copy_managed, null, out)) {
            return error.NoMatchingCall;
        }
        return;
    }
    if (!try emitExpr(allocator, tokens, start_idx, end_idx, locals, ctx, field_ty, out)) {
        return error.NoMatchingCall;
    }
}

fn emitStructFieldLocalGet(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    base: []const u8,
    field_name: []const u8,
    field_ty: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    copy_managed: bool,
    out: *std.ArrayList(u8),
) CodegenError!void {
    _ = tokens;
    const union_local_name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ base, field_name });
    defer allocator.free(union_local_name);
    if (findUnionLocal(locals.union_locals.items, union_local_name)) |union_local| {
        for (union_local.layout.payload_tys, 0..) |payload_ty, idx| {
            try appendUnionPayloadLocalGet(allocator, out, union_local.name, idx);
            if (copy_managed and isManagedLocalType(payload_ty, ctx)) {
                try out.appendSlice(allocator, "    call $__arc_inc\n");
            }
        }
        try appendUnionTagLocalGet(allocator, out, union_local.name);
        return;
    }
    try appendFmt(allocator, out, "    local.get ${s}.{s}\n", .{ base, field_name });
    if (copy_managed and isManagedLocalType(field_ty, ctx)) {
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
}

fn emitStructFieldLocalSet(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    base: []const u8,
    field_name: []const u8,
    field_ty: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!void {
    const union_local_name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ base, field_name });
    defer allocator.free(union_local_name);
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    if (try parseTypeUnionLayoutFromName(allocator, tokens, field_ty, ctx.structs, ctx.struct_layouts, &owned_types)) |layout| {
        defer freeUnionLayout(allocator, layout);
        const union_local = findUnionLocal(locals.union_locals.items, union_local_name) orelse return error.NoMatchingCall;
        if (!unionLayoutsEqual(union_local.layout, layout)) return error.NoMatchingCall;
        var idx = union_local.layout.payload_tys.len + 1;
        while (idx > 0) {
            idx -= 1;
            if (idx == union_local.layout.payload_tys.len) {
                try appendUnionTagLocalSet(allocator, out, union_local.name);
            } else {
                try appendUnionPayloadLocalSet(allocator, out, union_local.name, idx);
            }
        }
        return;
    }
    if (isTupleTypeName(field_ty)) {
        return try emitTupleLocalSet(allocator, union_local_name, field_ty, ctx, out);
    }
    try appendFmt(allocator, out, "    local.set ${s}.{s}\n", .{ base, field_name });
}

fn emitStructFieldsFromLocal(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    struct_local: StructLocal,
    decl: StructDecl,
    locals: *const LocalSet,
    ctx: CodegenContext,
    copy_managed: bool,
    out: *std.ArrayList(u8),
) CodegenError!void {
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    for (decl.fields) |field| {
        const field_ty = try substituteStructFieldType(allocator, decl, struct_local.ty, field.ty, &owned_types);
        try emitStructFieldLocalGet(allocator, tokens, struct_local.name, publicDeclName(field.name), field_ty, locals, ctx, copy_managed, out);
    }
}

fn emitUserFuncArg(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    arg_start: usize,
    arg_end: usize,
    param_ty: []const u8,
    copy_managed: bool,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    if (try parseTypeUnionLayoutFromName(allocator, tokens, param_ty, ctx.structs, ctx.struct_layouts, &owned_types)) |layout| {
        defer freeUnionLayout(allocator, layout);
        return try emitUnionValue(allocator, tokens, arg_start, arg_end, locals, ctx, layout, copy_managed, null, out);
    }
    if (isTupleTypeName(param_ty)) {
        if (try emitTupleExpr(allocator, tokens, arg_start, arg_end, locals, ctx, param_ty, out)) {
            return true;
        }
    }
    const range = trimParens(tokens, arg_start, arg_end);
    if (range.end == range.start + 1 and tokens[range.start].kind == .ident) {
        if (findStructLocal(locals.struct_locals.items, tokens[range.start].lexeme)) |struct_local| {
            if (std.mem.eql(u8, struct_local.ty, param_ty) and findStructLayout(ctx.struct_layouts, param_ty) == null) {
                const decl = findStructDecl(ctx.structs, param_ty) orelse return false;
                try emitStructFieldsFromLocal(allocator, tokens, struct_local, decl, locals, ctx, false, out);
                return true;
            }
        }
        if (try emitUnionStructPayloadForType(allocator, tokens, tokens[range.start].lexeme, param_ty, locals, ctx, false, out)) {
            return true;
        }
    }
    return try emitExpr(allocator, tokens, arg_start, arg_end, locals, ctx, param_ty, out);
}

fn emitUnionStructPayloadForType(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    name: []const u8,
    ty: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    copy_managed: bool,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (findNarrowedUnionType(locals.narrowed_union_locals.items, name)) |narrowed_ty| {
        if (!std.mem.eql(u8, narrowed_ty, ty)) return false;
    } else {
        return false;
    }
    const union_local = findUnionLocal(locals.union_locals.items, name) orelse return false;
    const payload = unionLocalDefaultStructPayload(tokens, ctx, union_local) orelse return false;
    if (!std.mem.eql(u8, payload.decl.name, ty)) return false;

    if (payload.branch.payload_len == 1) {
        if (findStructLayout(ctx.struct_layouts, payload.decl.name) != null) {
            try appendUnionPayloadLocalGet(allocator, out, union_local.name, payload.branch.payload_start);
            if (copy_managed) try out.appendSlice(allocator, "    call $__arc_inc\n");
            return true;
        }
    }

    var idx = payload.branch.payload_start;
    for (payload.decl.fields) |field| {
        try appendUnionPayloadLocalGet(allocator, out, union_local.name, idx);
        if (copy_managed and isManagedLocalType(field.ty, ctx)) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
        idx += 1;
    }
    return true;
}

fn emitStructBinding(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    decl: StructDecl,
    out: *std.ArrayList(u8),
) !void {
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    const source_name = tokens[start_idx].lexeme;
    const struct_local = findStructLocal(locals.struct_locals.items, source_name);
    const target_name = if (struct_local) |local| local.name else resolvedLocalName(locals.locals.items, source_name);
    const struct_ty = if (struct_local) |local|
        local.ty
    else if (try typedStructBinding(allocator, tokens, start_idx, end_idx, ctx, &owned_types)) |binding|
        binding.ty
    else if (inferredStructBinding(tokens, start_idx, end_idx, locals, ctx)) |binding|
        binding.ty
    else
        decl.name;
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return error.NoMatchingCall;
    if (eq_idx + 1 >= end_idx) return error.NoMatchingCall;
    if (findStructLayout(ctx.struct_layouts, struct_ty) != null and !isStructLiteralRhs(tokens, eq_idx + 1, end_idx)) {
        if (try emitManagedStructSetBinding(allocator, tokens, eq_idx + 1, end_idx, target_name, locals, ctx, decl, struct_ty, &owned_types, out)) {
            return;
        }
        const emitted_move_call = try emitManagedHandleCallExprWithMoveContext(
            allocator,
            tokens,
            eq_idx + 1,
            end_idx,
            body_end,
            allow_last_use_move,
            locals,
            defer_ctx,
            ctx,
            struct_ty,
            out,
        );
        if (!emitted_move_call and !try emitExpr(allocator, tokens, eq_idx + 1, end_idx, locals, ctx, struct_ty, out)) return error.NoMatchingCall;
        if (!emitted_move_call and isDirectManagedLocalExpr(tokens, eq_idx + 1, end_idx, locals, ctx)) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
        try appendFmt(allocator, out, "    local.set ${s}\n", .{target_name});
        return;
    }
    if (findStructLayout(ctx.struct_layouts, struct_ty) == null) {
        if (try emitWasiRecordStructBinding(allocator, tokens, start_idx, end_idx, locals, ctx, decl, out)) {
            return;
        }
        if (try emitUnmanagedStructCallBinding(
            allocator,
            tokens,
            start_idx,
            end_idx,
            body_end,
            allow_last_use_move,
            locals,
            defer_ctx,
            ctx,
            decl,
            struct_ty,
            out,
        )) {
            return;
        }
        if (!isStructLiteralRhs(tokens, eq_idx + 1, end_idx)) {
            if (!try emitExpr(allocator, tokens, eq_idx + 1, end_idx, locals, ctx, struct_ty, out)) return error.NoMatchingCall;
            var field_idx = decl.fields.len;
            while (field_idx > 0) {
                field_idx -= 1;
                try appendFmt(allocator, out, "    local.set ${s}.{s}\n", .{
                    target_name,
                    publicDeclName(decl.fields[field_idx].name),
                });
            }
            return;
        }
    }
    const open_brace = structLiteralOpenRhs(tokens, eq_idx + 1, end_idx) orelse return error.NoMatchingCall;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return error.NoMatchingCall;
    if (close_brace + 1 != end_idx) return error.NoMatchingCall;

    if (findStructLayout(ctx.struct_layouts, struct_ty)) |layout| {
        try appendFmt(allocator, out, "    i32.const {d}\n", .{layout.payload_bytes});
        try appendFmt(allocator, out, "    i32.const {d}\n", .{layout.type_id});
        try out.appendSlice(allocator, "    call $__arc_alloc\n");
        try appendFmt(allocator, out, "    local.set ${s}\n", .{target_name});
        try emitManagedStructFields(allocator, tokens, open_brace + 1, close_brace, target_name, locals, ctx, decl, struct_ty, layout, &owned_types, out);
        return;
    }

    for (decl.fields) |field| {
        const field_name = publicDeclName(field.name);
        const literal_field = findStructLiteralField(tokens, open_brace + 1, close_brace, field_name);
        const expr_tokens = if (literal_field != null) tokens else decl.tokens;
        const expr_start = if (literal_field) |found| found.value_start else field.default_start orelse return error.NoMatchingCall;
        const expr_end = if (literal_field) |found| found.value_end else field.default_end;
        const field_ty = try substituteStructFieldType(allocator, decl, struct_ty, field.ty, &owned_types);
        try emitStructFieldValue(allocator, expr_tokens, expr_start, expr_end, locals, ctx, field_ty, false, out);
        try emitStructFieldLocalSet(allocator, tokens, target_name, field_name, field_ty, locals, ctx, out);
    }
}

fn emitManagedStructSetBinding(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    target_name: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    decl: StructDecl,
    struct_ty: []const u8,
    owned_types: *std.ArrayList([]const u8),
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const layout = findStructLayout(ctx.struct_layouts, struct_ty) orelse return false;
    const range = trimParens(tokens, start_idx, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return false;
    if (!call_head.is_intrinsic) return false;
    if (!std.mem.eql(u8, tokens[call_head.name_idx].lexeme, "set")) return false;

    const first_end = findArgEnd(tokens, call_head.args_start, call_head.args_end);
    if (first_end != call_head.args_start + 1 or tokens[call_head.args_start].kind != .ident) return false;
    if (first_end >= call_head.args_end or !tokEq(tokens[first_end], ",")) return false;
    const source_local = findStructLocal(locals.struct_locals.items, tokens[call_head.args_start].lexeme) orelse return false;
    if (!std.mem.eql(u8, source_local.ty, struct_ty)) return false;

    const field_start = first_end + 1;
    const field_end = findArgEnd(tokens, field_start, call_head.args_end);
    if (field_end != field_start + 1 or !isDotIdent(tokens[field_start].lexeme)) return false;
    if (field_end >= call_head.args_end or !tokEq(tokens[field_end], ",")) return false;
    const value_start = field_end + 1;
    const value_end = findArgEnd(tokens, value_start, call_head.args_end);
    if (value_end != call_head.args_end) return false;
    const target_field = publicDeclName(tokens[field_start].lexeme);

    try appendFmt(allocator, out, "    i32.const {d}\n", .{layout.payload_bytes});
    try appendFmt(allocator, out, "    i32.const {d}\n", .{layout.type_id});
    try out.appendSlice(allocator, "    call $__arc_alloc\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{target_name});

    for (decl.fields) |field| {
        const field_name = publicDeclName(field.name);
        const field_ty = try substituteStructFieldType(allocator, decl, struct_ty, field.ty, owned_types);
        const field_offset = structFieldPayloadOffset(decl, field_name) orelse return false;
        try appendManagedStructFieldPtr(allocator, out, target_name, field_offset);
        if (std.mem.eql(u8, field_name, target_field)) {
            if (!try emitExpr(allocator, tokens, value_start, value_end, locals, ctx, field_ty, out)) return false;
            if (isManagedStructField(layout, field_name) and isDirectManagedLocalExpr(tokens, value_start, value_end, locals, ctx)) {
                try out.appendSlice(allocator, "    call $__arc_inc\n");
            }
            try appendStoreForPayloadType(allocator, out, field_ty);
            continue;
        }

        try appendManagedStructFieldPtr(allocator, out, source_local.name, field_offset);
        try appendLoadForPayloadType(allocator, out, field_ty);
        if (isManagedStructField(layout, field_name)) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
        try appendStoreForPayloadType(allocator, out, field_ty);
    }
    return true;
}

fn isStructLiteralRhs(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    return structLiteralOpenRhs(tokens, start_idx, end_idx) != null;
}

fn structLiteralOpenRhs(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (start_idx + 1 >= end_idx) return null;
    if (tokens[start_idx].kind == .ident and tokEq(tokens[start_idx + 1], "{")) return start_idx + 1;
    if (tokens[start_idx].kind == .ident and tokEq(tokens[start_idx + 1], "<")) {
        const close_angle = findMatchingInRange(tokens, start_idx + 1, "<", ">", end_idx) catch return null;
        if (close_angle + 1 < end_idx and tokEq(tokens[close_angle + 1], "{")) return close_angle + 1;
    }
    if (tokEq(tokens[start_idx], ".") and tokEq(tokens[start_idx + 1], "{")) return start_idx + 1;
    return null;
}

fn emitStructLiteralExpr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    expected_ty: []const u8,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const decl = findStructDecl(ctx.structs, expected_ty) orelse return false;
    const open_brace = structLiteralOpenRhs(tokens, start_idx, end_idx) orelse return false;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return false;
    if (close_brace + 1 != end_idx) return false;

    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }

    if (findStructLayout(ctx.struct_layouts, expected_ty)) |layout| {
        try appendFmt(allocator, out, "    i32.const {d}\n", .{layout.payload_bytes});
        try appendFmt(allocator, out, "    i32.const {d}\n", .{layout.type_id});
        try out.appendSlice(allocator, "    call $__arc_alloc\n");
        try appendFmt(allocator, out, "    local.set ${s}\n", .{STRUCT_LITERAL_TMP_LOCAL});
        try emitManagedStructFields(allocator, tokens, open_brace + 1, close_brace, STRUCT_LITERAL_TMP_LOCAL, locals, ctx, decl, expected_ty, layout, &owned_types, out);
        try appendFmt(allocator, out, "    local.get ${s}\n", .{STRUCT_LITERAL_TMP_LOCAL});
        return true;
    }

    for (decl.fields) |field| {
        const field_name = publicDeclName(field.name);
        const literal_field = findStructLiteralField(tokens, open_brace + 1, close_brace, field_name);
        const expr_tokens = if (literal_field != null) tokens else decl.tokens;
        const expr_start = if (literal_field) |found| found.value_start else field.default_start orelse return error.NoMatchingCall;
        const expr_end = if (literal_field) |found| found.value_end else field.default_end;
        const field_ty = try substituteStructFieldType(allocator, decl, expected_ty, field.ty, &owned_types);
        try emitStructFieldValue(allocator, expr_tokens, expr_start, expr_end, locals, ctx, field_ty, false, out);
    }
    return true;
}

fn emitUnmanagedStructCallBinding(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    decl: StructDecl,
    struct_ty: []const u8,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return false;
    const rhs_range = trimParens(tokens, eq_idx + 1, end_idx);
    const call_head = exprCallHead(tokens, rhs_range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = findFuncDeclForCallHead(tokens, call_head, locals, ctx) orelse return false;
    const result_struct = func.result_struct orelse return false;
    if (!std.mem.eql(u8, result_struct, struct_ty)) return false;
    if (func.results.len != decl.fields.len) return error.NoMatchingCall;
    for (decl.fields, 0..) |field, idx| {
        const field_ty = try substituteStructFieldType(allocator, decl, struct_ty, field.ty, &owned_types);
        if (!std.mem.eql(u8, field_ty, func.results[idx])) return error.NoMatchingCall;
    }
    const move_ctx = CallLastUseMoveContext{
        .body_start = 0,
        .stmt_end = end_idx,
        .body_end = body_end,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = allow_last_use_move,
    };
    if (!try emitUserFuncCallWithMoveContext(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, &move_ctx, out)) {
        return error.NoMatchingCall;
    }

    var i = decl.fields.len;
    while (i > 0) {
        i -= 1;
        const field = decl.fields[i];
        const field_ty = try substituteStructFieldType(allocator, decl, struct_ty, field.ty, &owned_types);
        try emitStructFieldLocalSet(allocator, tokens, tokens[start_idx].lexeme, publicDeclName(field.name), field_ty, locals, ctx, out);
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

    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try appendWasiImportSymbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");

    for (decl.fields) |field| {
        const field_name = publicDeclName(field.name);
        const field_offset = structFieldPayloadOffset(decl, field_name) orelse return error.NoMatchingCall;
        try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
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
    struct_ty: []const u8,
    layout: StructLayout,
    owned_types: *std.ArrayList([]const u8),
    out: *std.ArrayList(u8),
) !void {
    for (decl.fields) |field| {
        const field_name = publicDeclName(field.name);
        const literal_field = findStructLiteralField(tokens, start_idx, end_idx, field_name);
        const expr_tokens = if (literal_field) |_| tokens else decl.tokens;
        const expr_start = if (literal_field) |found| found.value_start else field.default_start orelse return error.NoMatchingCall;
        const expr_end = if (literal_field) |found| found.value_end else field.default_end;
        const field_offset = structFieldPayloadOffset(decl, field_name) orelse return error.NoMatchingCall;
        const field_ty = try substituteStructFieldType(allocator, decl, struct_ty, field.ty, owned_types);

        try appendFmt(allocator, out, "    local.get ${s}\n", .{local_name});
        try out.appendSlice(allocator, "    call $__arc_payload\n");
        try appendFmt(allocator, out, "    i32.const {d}\n", .{field_offset});
        try out.appendSlice(allocator, "    i32.add\n");
        if (!try emitExpr(allocator, expr_tokens, expr_start, expr_end, locals, ctx, field_ty, out)) return error.NoMatchingCall;
        if (isManagedStructField(layout, field_name) and isDirectManagedLocalExpr(expr_tokens, expr_start, expr_end, locals, ctx)) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
        try appendStoreForPayloadType(allocator, out, field_ty);
    }
}

fn emitStructSetAssignment(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
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
    const field_ty = findLocalFieldType(locals.locals.items, struct_local.name, field_name) orelse
        findStructFieldType(decl, field_name) orelse return false;

    if (findStructLayout(ctx.struct_layouts, struct_local.ty)) |layout| {
        const field_offset = structFieldPayloadOffset(decl, field_name) orelse return false;
        try appendFmt(allocator, out, "    ;; arc-managed-struct-set name={s} field={s} offset={d}\n", .{
            tokens[start_idx].lexeme,
            field_name,
            field_offset,
        });
        if (isManagedStructField(layout, field_name)) {
            try emitManagedStructFieldSet(
                allocator,
                tokens,
                value_start,
                close_paren,
                body_end,
                allow_last_use_move,
                tokens[start_idx].lexeme,
                field_name,
                field_offset,
                field_ty,
                locals,
                defer_ctx,
                ctx,
                out,
            );
            return true;
        }
        try appendManagedStructFieldPtr(allocator, out, tokens[start_idx].lexeme, field_offset);
        if (!try emitExpr(allocator, tokens, value_start, close_paren, locals, ctx, field_ty, out)) return error.NoMatchingCall;
        try appendStoreForPayloadType(allocator, out, field_ty);
        return true;
    }

    if (!try emitExpr(allocator, tokens, value_start, close_paren, locals, ctx, field_ty, out)) return error.NoMatchingCall;
    try appendFmt(allocator, out, "    local.set ${s}.{s}\n", .{
        struct_local.name,
        field_name,
    });
    return true;
}

fn emitStructFieldMetaSetAssignment(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
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
    if (!std.mem.eql(u8, tokens[name_idx].lexeme, "field_set")) return false;
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
    if (field_end != field_start + 1 or tokens[field_start].kind != .ident) return false;
    const meta = findFieldMetaLocal(locals.field_meta_locals.items, tokens[field_start].lexeme) orelse return false;
    if (!std.mem.eql(u8, typeBaseName(struct_local.ty), meta.struct_name)) return false;
    if (field_end >= close_paren or !tokEq(tokens[field_end], ",")) return false;

    const value_start = field_end + 1;
    const field = fieldFromMeta(ctx, meta) orelse return false;
    const field_name = publicDeclName(field.name);
    const field_ty = findLocalFieldType(locals.locals.items, struct_local.name, field_name) orelse field.ty;

    try appendFmt(allocator, out, "    ;; field-set name={s} field={s}\n", .{
        tokens[start_idx].lexeme,
        field_name,
    });

    if (findStructLayout(ctx.struct_layouts, struct_local.ty)) |layout| {
        const decl = findStructDecl(ctx.structs, struct_local.ty) orelse return false;
        const field_offset = structFieldPayloadOffset(decl, field_name) orelse return false;
        if (isManagedStructField(layout, field_name)) {
            try emitManagedStructFieldSet(
                allocator,
                tokens,
                value_start,
                close_paren,
                body_end,
                allow_last_use_move,
                tokens[start_idx].lexeme,
                field_name,
                field_offset,
                field_ty,
                locals,
                defer_ctx,
                ctx,
                out,
            );
            return true;
        }
        try appendManagedStructFieldPtr(allocator, out, tokens[start_idx].lexeme, field_offset);
        if (!try emitExpr(allocator, tokens, value_start, close_paren, locals, ctx, field_ty, out)) return error.NoMatchingCall;
        try appendStoreForPayloadType(allocator, out, field_ty);
        return true;
    }

    if (!try emitExpr(allocator, tokens, value_start, close_paren, locals, ctx, field_ty, out)) return error.NoMatchingCall;
    try appendFmt(allocator, out, "    local.set ${s}.{s}\n", .{
        struct_local.name,
        field_name,
    });
    return true;
}

fn emitManagedStructFieldSet(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    value_start: usize,
    value_end: usize,
    body_end: usize,
    allow_last_use_move: bool,
    target_name: []const u8,
    field_name: []const u8,
    field_offset: usize,
    field_ty: []const u8,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!void {
    const move_ctx = if (allow_last_use_move) CallLastUseMoveContext{
        .stmt_end = value_end,
        .body_end = body_end,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = true,
    } else null;
    if (!try emitExprWithMoveContext(allocator, tokens, value_start, value_end, locals, ctx, field_ty, if (move_ctx) |*ctx_info| ctx_info else null, out)) return error.NoMatchingCall;
    const move_source = if (allow_last_use_move)
        directManagedLastUseMoveSource(tokens, value_start, value_end, body_end, target_name, locals, ctx, defer_ctx)
    else
        null;
    if (move_source == null and isDirectManagedLocalExpr(tokens, value_start, value_end, locals, ctx)) {
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});

    const struct_local = findStructLocal(locals.struct_locals.items, target_name) orelse return error.NoMatchingCall;
    const decl = findStructDecl(ctx.structs, struct_local.ty) orelse return error.NoMatchingCall;
    const layout = findStructLayout(ctx.struct_layouts, struct_local.ty) orelse return error.NoMatchingCall;

    try appendFmt(allocator, out, "    local.get ${s}\n", .{target_name});
    try out.appendSlice(allocator, "    call $__arc_rc\n");
    try out.appendSlice(allocator, "    i32.const 1\n");
    try out.appendSlice(allocator, "    i32.eq\n");
    try out.appendSlice(allocator, "    if (result i32)\n");
    try appendFmt(allocator, out, "      ;; arc-managed-struct-reuse {s}.{s}\n", .{ target_name, field_name });
    try appendFmt(allocator, out, "      ;; arc-overwrite-release {s}.{s}\n", .{ target_name, field_name });
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try appendManagedStructFieldPtr(allocator, out, target_name, field_offset);
    try appendLoadForPayloadType(allocator, out, field_ty);
    try out.appendSlice(allocator, "      i32.ne\n");
    try out.appendSlice(allocator, "      if\n");
    try appendManagedStructFieldPtr(allocator, out, target_name, field_offset);
    try appendLoadForPayloadType(allocator, out, field_ty);
    try out.appendSlice(allocator, "        call $__arc_dec\n");
    try out.appendSlice(allocator, "      end\n");
    try appendManagedStructFieldPtr(allocator, out, target_name, field_offset);
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try appendStoreForPayloadType(allocator, out, field_ty);
    try appendFmt(allocator, out, "      local.get ${s}\n", .{target_name});
    try out.appendSlice(allocator, "    else\n");
    try appendFmt(allocator, out, "      ;; arc-managed-struct-clone-set {s}.{s}\n", .{ target_name, field_name });
    try emitManagedStructCloneWithFieldSet(allocator, target_name, field_name, decl, struct_local.ty, layout, out);
    try out.appendSlice(allocator, "    end\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{target_name});
    if (move_source) |source| {
        try appendFmt(allocator, out, "    ;; field-set-move {s}\n", .{source.source_name});
        try emitZeroValueForType(allocator, ctx, out, field_ty);
        try appendFmt(allocator, out, "    local.set ${s}\n", .{source.actual_name});
    }
}

fn emitManagedStructCloneWithFieldSet(
    allocator: std.mem.Allocator,
    target_name: []const u8,
    target_field_name: []const u8,
    decl: StructDecl,
    struct_ty: []const u8,
    layout: StructLayout,
    out: *std.ArrayList(u8),
) CodegenError!void {
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }

    try appendFmt(allocator, out, "      i32.const {d}\n", .{layout.payload_bytes});
    try appendFmt(allocator, out, "      i32.const {d}\n", .{layout.type_id});
    try out.appendSlice(allocator, "      call $__arc_alloc\n");
    try appendFmt(allocator, out, "      local.set ${s}\n", .{STORAGE_WRITE_TARGET_TMP_LOCAL});

    for (decl.fields) |field| {
        const field_name = publicDeclName(field.name);
        const field_ty = try substituteStructFieldType(allocator, decl, struct_ty, field.ty, &owned_types);
        const field_offset = structFieldPayloadOffset(decl, field_name) orelse return error.NoMatchingCall;

        try appendManagedStructFieldPtr(allocator, out, STORAGE_WRITE_TARGET_TMP_LOCAL, field_offset);
        if (std.mem.eql(u8, field_name, target_field_name)) {
            try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
            try appendStoreForPayloadType(allocator, out, field_ty);
            continue;
        }

        try appendManagedStructFieldPtr(allocator, out, target_name, field_offset);
        try appendLoadForPayloadType(allocator, out, field_ty);
        if (isManagedStructField(layout, field_name)) {
            try out.appendSlice(allocator, "      call $__arc_inc\n");
        }
        try appendStoreForPayloadType(allocator, out, field_ty);
    }

    try appendFmt(allocator, out, "      local.get ${s}\n", .{target_name});
    try out.appendSlice(allocator, "      call $__arc_dec\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_TARGET_TMP_LOCAL});
}

fn appendManagedStructFieldPtr(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    local_name: []const u8,
    field_offset: usize,
) !void {
    try appendFmt(allocator, out, "    local.get ${s}\n", .{local_name});
    try out.appendSlice(allocator, "    call $__arc_payload\n");
    try appendFmt(allocator, out, "    i32.const {d}\n", .{field_offset});
    try out.appendSlice(allocator, "    i32.add\n");
}

fn emitBody(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_start: usize,
    locals: *const LocalSet,
    return_cleanup_locals: *const LocalSet,
    control_cleanup_locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_items: []const FuncResultItem,
    result_struct: ?[]const u8,
    result_union: ?UnionLayout,
    loop_ctx: ?LoopControl,
    defer_ctx: ?*const DeferContext,
    return_label: ?[]const u8,
    self_tail_tco: ?*const SelfTailTco,
    out: *std.ArrayList(u8),
) !void {
    const allow_call_arg_last_use_move = loop_ctx == null;
    var active_locals = try cloneLocalSet(allocator, locals);
    defer active_locals.deinit(allocator);
    const active = &active_locals;
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
        } else if (try emitLoopControlStmt(allocator, tokens, i, stmt_end, active, control_cleanup_locals, loop_ctx, exit_defer_ctx, ctx, out)) {
            // Loop control emitted.
        } else if (try emitGuardLoopControlIf(allocator, tokens, i, stmt_end, active, control_cleanup_locals, loop_ctx, exit_defer_ctx, ctx, out)) {
            // Guard loop control emitted.
            try applyGuardLoopControlNarrowing(allocator, tokens, i, stmt_end, active, ctx);
        } else if (try emitLoopBlock(allocator, tokens, i, stmt_end, body_start, active, return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, defer_ctx, return_label, out)) {
            // Loop block emitted.
        } else if (try emitIfBlock(allocator, tokens, i, stmt_end, body_start, active, return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, defer_ctx, return_label, self_tail_tco, out)) {
            // If block emitted.
            try applyIfBlockFallthroughNarrowing(allocator, tokens, i, stmt_end, active, ctx);
        } else if (try emitGuardReturnIf(allocator, tokens, i, stmt_end, end_idx, body_start, allow_call_arg_last_use_move, active, return_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, exit_defer_ctx, return_label, self_tail_tco, out)) {
            // Guard return emitted.
            try applyGuardReturnNilNarrowing(allocator, tokens, i, stmt_end, active);
            try applyGuardReturnIsNarrowing(allocator, tokens, i, stmt_end, active, ctx);
        } else if (try emitReturnStmt(allocator, tokens, i, stmt_end, body_start, active, return_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, exit_defer_ctx, return_label, self_tail_tco, out)) {
            // Return emitted.
        } else if (try emitDiscardAssignment(allocator, tokens, i, stmt_end, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, out)) {
            // Discard assignment emitted.
        } else if (try isDeadManagedAliasBinding(allocator, tokens, i, stmt_end, end_idx, active, ctx)) {
            // Dead managed alias binding elided.
        } else if (try emitUnionBinding(allocator, tokens, i, stmt_end, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, out)) {
            // Union binding emitted.
        } else if (try emitMultiResultAssignment(allocator, tokens, i, stmt_end, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, out)) {
            // Multi-result assignment emitted.
        } else if (try emitStructFieldMetaSetAssignment(allocator, tokens, i, stmt_end, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, out)) {
            // Struct field metadata assignment emitted.
        } else if (try emitStructSetAssignment(allocator, tokens, i, stmt_end, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, out)) {
            // Struct field assignment emitted.
        } else if (try emitStorageAssignment(allocator, tokens, i, stmt_end, start_idx, end_idx, active, exit_defer_ctx, ctx, out)) {
            // Storage assignment emitted.
        } else if (try emitManagedLocalAssignment(allocator, tokens, i, stmt_end, end_idx, active, exit_defer_ctx, ctx, out)) {
            // Managed handle assignment emitted.
        } else if (managedPayloadBinding(tokens, i, stmt_end) != null) {
            try emitStorageBinding(allocator, tokens, i, stmt_end, start_idx, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, out);
        } else if (storageBindingElemType(tokens, i, stmt_end) != null) {
            try emitStorageBinding(allocator, tokens, i, stmt_end, start_idx, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, out);
        } else if (isCollectedTypedStorageBinding(tokens, i, stmt_end, active)) {
            try emitStorageBinding(allocator, tokens, i, stmt_end, start_idx, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, out);
        } else if (try emitTupleBinding(allocator, tokens, i, stmt_end, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, out)) {
            // Tuple field local binding emitted.
        } else if (try typedStructBindingDecl(allocator, tokens, i, stmt_end, ctx)) |decl| {
            try emitStructBinding(allocator, tokens, i, stmt_end, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, decl, out);
        } else if (inferredStructCtorBinding(tokens, i, stmt_end, ctx.structs)) |decl| {
            try emitStructBinding(allocator, tokens, i, stmt_end, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, decl, out);
        } else if (inferredStructBinding(tokens, i, stmt_end, active, ctx)) |binding| {
            try emitStructBinding(allocator, tokens, i, stmt_end, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, binding.decl, out);
        } else if (try emitScalarAssignment(allocator, tokens, i, stmt_end, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, out)) {
            // Scalar assignment emitted.
        } else if (typedScalarBindingType(tokens, i, stmt_end, ctx)) |scalar_ty| {
            const eq_idx = findTopLevelToken(tokens, i, stmt_end, "=") orelse {
                i = stmt_end;
                continue;
            };
            const emitted = try emitScalarCallExprWithMoveContext(
                allocator,
                tokens,
                eq_idx + 1,
                stmt_end,
                end_idx,
                allow_call_arg_last_use_move,
                active,
                exit_defer_ctx,
                ctx,
                scalar_ty,
                out,
            ) or try emitExpr(allocator, tokens, eq_idx + 1, stmt_end, active, ctx, scalar_ty, out);
            if (!emitted) return error.NoMatchingCall;
            try appendFmt(allocator, out, "    local.set ${s}\n", .{resolvedLocalName(active.locals.items, tokens[i].lexeme)});
        } else if (try emitInferredScalarBinding(allocator, tokens, i, stmt_end, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, out)) {
            // Inferred scalar binding emitted.
        } else if (try emitBareUserFuncCallWithMoveContext(allocator, tokens, i, stmt_end, end_idx, allow_call_arg_last_use_move, active, exit_defer_ctx, ctx, out)) {
            // Nil-return user function call emitted.
        } else if (try emitBareWasiHostImportCall(allocator, tokens, i, stmt_end, active, ctx, out)) {
            // Statement-only WASI result-area call emitted.
        } else if (isHostImportCallExpr(tokens, i, stmt_end, ctx) or isWasiHostImportCallExpr(tokens, i, stmt_end, ctx)) {
            if (!try emitExpr(allocator, tokens, i, stmt_end, active, ctx, null, out)) {
                return error.NoMatchingCall;
            }
        }
        clearNarrowedUnionLocalsForAssignments(tokens, i, stmt_end, active);
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

fn isCollectedTypedStorageBinding(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
) bool {
    if (start_idx + 3 >= end_idx) return false;
    if (tokens[start_idx].kind != .ident) return false;
    if (tokEq(tokens[start_idx + 1], "=")) return false;
    if (findStorageLocal(locals.storage_locals.items, tokens[start_idx].lexeme) == null) return false;
    return findTopLevelToken(tokens, start_idx + 1, end_idx, "=") != null;
}

fn isDiscardAssignment(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 3 > end_idx) return false;
    if (tokens[start_idx].kind != .ident) return false;
    if (!std.mem.eql(u8, tokens[start_idx].lexeme, "_")) return false;
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return false;
    return eq_idx == start_idx + 1 and eq_idx + 1 < end_idx;
}

fn discardExprIsPureNoop(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.start >= range.end) return true;
    if (range.end == range.start + 1) return true;
    if (isStorageAggLiteralExpr(tokens, range.start, range.end)) return true;
    return false;
}

fn emitDiscardStackValue(
    allocator: std.mem.Allocator,
    ty: []const u8,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !void {
    if (isManagedLocalType(ty, ctx)) {
        try out.appendSlice(allocator, "    call $__arc_dec\n");
    } else {
        try out.appendSlice(allocator, "    drop\n");
    }
}

fn emitDiscardAssignment(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (!isDiscardAssignment(tokens, start_idx, end_idx)) return false;
    const eq_idx = start_idx + 1;
    const rhs_start = eq_idx + 1;
    if (discardExprIsPureNoop(tokens, rhs_start, end_idx)) return true;

    if (try emitBareUserFuncCallWithMoveContext(allocator, tokens, rhs_start, end_idx, body_end, allow_last_use_move, locals, defer_ctx, ctx, out)) {
        return true;
    }
    if (try emitBareWasiHostImportCall(allocator, tokens, rhs_start, end_idx, locals, ctx, out)) return true;

    const range = trimParens(tokens, rhs_start, end_idx);
    if (exprCallHead(tokens, range)) |call_head| {
        if (!call_head.is_intrinsic) {
            if (findFuncDeclForCallHead(tokens, call_head, locals, ctx)) |func| {
                if (func.results.len > 1) {
                    const move_ctx = CallLastUseMoveContext{
                        .stmt_end = end_idx,
                        .body_end = body_end,
                        .defer_ctx = defer_ctx,
                        .allow_last_use_move = allow_last_use_move,
                    };
                    if (!try emitUserFuncCallWithMoveContext(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, &move_ctx, out)) {
                        return error.NoMatchingCall;
                    }
                    var result_idx = func.results.len;
                    while (result_idx > 0) {
                        result_idx -= 1;
                        try emitDiscardStackValue(allocator, func.results[result_idx], ctx, out);
                    }
                    return true;
                }
            }
        }
    }

    const ty = inferExprType(tokens, rhs_start, end_idx, locals, ctx) orelse return error.NoMatchingCall;
    const move_ctx = CallLastUseMoveContext{
        .stmt_end = end_idx,
        .body_end = body_end,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = allow_last_use_move,
    };
    if (!try emitExprWithMoveContext(allocator, tokens, rhs_start, end_idx, locals, ctx, ty, &move_ctx, out)) {
        return error.NoMatchingCall;
    }
    try emitDiscardStackValue(allocator, ty, ctx, out);
    return true;
}

fn emitTupleLocalSet(
    allocator: std.mem.Allocator,
    base: []const u8,
    tuple_ty: []const u8,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !void {
    const arity = tupleArity(tuple_ty) orelse return error.UnsupportedLowering;
    var idx = arity;
    while (idx > 0) {
        idx -= 1;
        const elem_ty = tupleElementTypeAt(tuple_ty, idx) orelse return error.UnsupportedLowering;
        if (isTupleTypeName(elem_ty)) {
            const nested_base = try std.fmt.allocPrint(allocator, "{s}.{d}", .{ base, idx });
            defer allocator.free(nested_base);
            try emitTupleLocalSet(allocator, nested_base, elem_ty, ctx, out);
        } else if (findStructDecl(ctx.structs, elem_ty)) |decl| {
            if (findStructLayout(ctx.struct_layouts, elem_ty) == null and pureScalarStructPackWidth(decl, ctx.structs) != null) {
                const nested_base = try std.fmt.allocPrint(allocator, "{s}.{d}", .{ base, idx });
                defer allocator.free(nested_base);
                try emitPureScalarStructLocalSet(allocator, nested_base, decl, out);
            } else {
                try appendFmt(allocator, out, "    local.set ${s}.{d}\n", .{ base, idx });
            }
        } else {
            try appendFmt(allocator, out, "    local.set ${s}.{d}\n", .{ base, idx });
        }
    }
}

fn emitPureScalarStructLocalSet(
    allocator: std.mem.Allocator,
    base: []const u8,
    decl: StructDecl,
    out: *std.ArrayList(u8),
) !void {
    var field_idx = decl.fields.len;
    while (field_idx > 0) {
        field_idx -= 1;
        try appendFmt(allocator, out, "    local.set ${s}.{s}\n", .{
            base,
            publicDeclName(decl.fields[field_idx].name),
        });
    }
}

fn emitPureScalarStructLocalGet(
    allocator: std.mem.Allocator,
    base: []const u8,
    decl: StructDecl,
    out: *std.ArrayList(u8),
) !void {
    for (decl.fields) |field| {
        try appendFmt(allocator, out, "    local.get ${s}.{s}\n", .{
            base,
            publicDeclName(field.name),
        });
    }
}

fn emitTupleLocalGet(
    allocator: std.mem.Allocator,
    base: []const u8,
    tuple_ty: []const u8,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !void {
    const arity = tupleArity(tuple_ty) orelse return error.UnsupportedLowering;
    var idx: usize = 0;
    while (idx < arity) : (idx += 1) {
        const elem_ty = tupleElementTypeAt(tuple_ty, idx) orelse return error.UnsupportedLowering;
        if (isTupleTypeName(elem_ty)) {
            const nested_base = try std.fmt.allocPrint(allocator, "{s}.{d}", .{ base, idx });
            defer allocator.free(nested_base);
            try emitTupleLocalGet(allocator, nested_base, elem_ty, ctx, out);
        } else if (findStructDecl(ctx.structs, elem_ty)) |decl| {
            if (findStructLayout(ctx.struct_layouts, elem_ty) == null and pureScalarStructPackWidth(decl, ctx.structs) != null) {
                const nested_base = try std.fmt.allocPrint(allocator, "{s}.{d}", .{ base, idx });
                defer allocator.free(nested_base);
                try emitPureScalarStructLocalGet(allocator, nested_base, decl, out);
            } else {
                try appendFmt(allocator, out, "    local.get ${s}.{d}\n", .{ base, idx });
            }
        } else {
            try appendFmt(allocator, out, "    local.get ${s}.{d}\n", .{ base, idx });
        }
    }
}

fn emitTupleBinding(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (start_idx + 3 >= end_idx) return false;
    if (tokens[start_idx].kind != .ident) return false;
    const tuple_local = findStructLocal(locals.struct_locals.items, tokens[start_idx].lexeme) orelse return false;
    if (!isTupleTypeName(tuple_local.ty)) return false;
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return false;
    if (try emitTupleCallBinding(
        allocator,
        tokens,
        start_idx,
        end_idx,
        body_end,
        allow_last_use_move,
        locals,
        defer_ctx,
        ctx,
        tuple_local,
        out,
    )) {
        return true;
    }
    if (try emitTupleGetBinding(
        allocator,
        tokens,
        start_idx,
        end_idx,
        locals,
        ctx,
        tuple_local,
        out,
    )) {
        return true;
    }
    const open_brace = structLiteralOpenRhs(tokens, eq_idx + 1, end_idx) orelse return false;

    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return false;
    if (close_brace + 1 != end_idx) return false;

    const arity = tupleArity(tuple_local.ty) orelse return false;
    var expr_start = open_brace + 1;
    var idx: usize = 0;
    while (expr_start < close_brace) {
        const expr_end = findArgEnd(tokens, expr_start, close_brace);
        if (idx >= arity) return error.NoMatchingCall;
        const elem_ty = tupleElementTypeAt(tuple_local.ty, idx) orelse return error.UnsupportedLowering;
        if (!try emitExpr(allocator, tokens, expr_start, expr_end, locals, ctx, elem_ty, out)) return error.NoMatchingCall;
        idx += 1;
        expr_start = expr_end;
        if (expr_start < close_brace) {
            if (!tokEq(tokens[expr_start], ",")) return error.NoMatchingCall;
            expr_start += 1;
        }
    }
    if (idx != arity) return error.NoMatchingCall;
    try emitTupleLocalSet(allocator, tuple_local.name, tuple_local.ty, ctx, out);
    return true;
}

fn emitTupleGetBinding(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    tuple_local: StructLocal,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return false;
    const rhs_range = trimParens(tokens, eq_idx + 1, end_idx);
    const call_head = exprCallHead(tokens, rhs_range) orelse return false;
    if (!call_head.is_intrinsic) return false;
    if (!std.mem.eql(u8, tokens[call_head.name_idx].lexeme, "get")) return false;
    if (!try emitExpr(allocator, tokens, rhs_range.start, rhs_range.end, locals, ctx, tuple_local.ty, out)) {
        return false;
    }
    try emitTupleLocalSet(allocator, tuple_local.name, tuple_local.ty, ctx, out);
    return true;
}

fn emitTupleCallBinding(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    tuple_local: StructLocal,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return false;
    const rhs_range = trimParens(tokens, eq_idx + 1, end_idx);
    const call_head = exprCallHead(tokens, rhs_range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = findFuncDeclForCallHead(tokens, call_head, locals, ctx) orelse return false;
    const result_struct = func.result_struct orelse return false;
    if (!std.mem.eql(u8, result_struct, tuple_local.ty)) return false;
    var leaf_types = std.ArrayList([]const u8).empty;
    defer leaf_types.deinit(allocator);
    try appendTupleLeafTypes(allocator, tuple_local.ty, &leaf_types);
    if (func.results.len != leaf_types.items.len) return error.NoMatchingCall;
    for (leaf_types.items, 0..) |leaf_ty, idx| {
        if (!std.mem.eql(u8, leaf_ty, func.results[idx])) return error.NoMatchingCall;
    }
    const move_ctx = CallLastUseMoveContext{
        .body_start = 0,
        .stmt_end = end_idx,
        .body_end = body_end,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = allow_last_use_move,
    };
    if (!try emitUserFuncCallWithMoveContext(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, &move_ctx, out)) {
        return error.NoMatchingCall;
    }
    try emitTupleLocalSet(allocator, tuple_local.name, tuple_local.ty, ctx, out);
    return true;
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

fn applyGuardReturnNilNarrowing(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *LocalSet,
) !void {
    if (start_idx >= end_idx or !tokEq(tokens[start_idx], "if")) return;
    const return_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "return") orelse return;
    const narrowing = nilComparisonNarrowing(tokens, start_idx + 1, return_idx, locals) orelse return;
    if (narrowing.non_nil_when_true) return;
    try locals.appendNarrowedUnionLocal(allocator, narrowing.union_local, narrowing.payload_ty);
}

fn applyGuardReturnIsNarrowing(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *LocalSet,
    ctx: CodegenContext,
) !void {
    if (start_idx >= end_idx or !tokEq(tokens[start_idx], "if")) return;
    const return_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "return") orelse return;
    const narrowing = try isComparisonNarrowing(allocator, tokens, start_idx + 1, return_idx, locals, ctx) orelse return;
    const payload_ty = unionLocalSingleRemainingPayloadType(narrowing.union_local, narrowing.payload_ty) orelse return;
    try locals.appendNarrowedUnionLocal(allocator, narrowing.union_local, payload_ty);
}

fn applyGuardLoopControlNarrowing(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *LocalSet,
    ctx: CodegenContext,
) !void {
    if (start_idx >= end_idx or !tokEq(tokens[start_idx], "if")) return;
    const control_idx = findTopLevelGuardLoopControl(tokens, start_idx + 1, end_idx) orelse return;

    if (nilComparisonNarrowing(tokens, start_idx + 1, control_idx, locals)) |narrowing| {
        if (!narrowing.non_nil_when_true) {
            try locals.appendNarrowedUnionLocal(allocator, narrowing.union_local, narrowing.payload_ty);
        }
    }

    if (try isComparisonNarrowing(allocator, tokens, start_idx + 1, control_idx, locals, ctx)) |narrowing| {
        const payload_ty = unionLocalSingleRemainingPayloadType(narrowing.union_local, narrowing.payload_ty) orelse return;
        try locals.appendNarrowedUnionLocal(allocator, narrowing.union_local, payload_ty);
    }
}

fn applyIfBlockFallthroughNarrowing(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *LocalSet,
    ctx: CodegenContext,
) !void {
    if (start_idx >= end_idx or !tokEq(tokens[start_idx], "if")) return;
    const open_brace = findTopLevelBlockOpen(tokens, start_idx + 1, end_idx) orelse return;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return;
    if (bodyCanReachEnd(tokens, open_brace + 1, close_brace)) return;
    try appendConditionNarrowingForBranch(allocator, tokens, start_idx + 1, open_brace, locals, ctx, false);
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
    try collectDirectBodyLocals(allocator, tokens, open_brace + 1, close_brace, ctx, &cleanup_locals);

    const no_results: []const []const u8 = &.{};
    const cleanup_defer = DeferContext{
        .parent = null,
        .start_idx = open_brace + 1,
        .end_idx = close_brace,
        .registered_end_idx = close_brace,
    };
    try out.appendSlice(allocator, "    block $defer_cleanup_exit\n");
    try emitBody(allocator, tokens, open_brace + 1, close_brace, open_brace + 1, locals, &cleanup_locals, &EMPTY_LOCAL_SET, ctx, no_results, NO_RESULT_ITEMS, null, null, null, &cleanup_defer, "defer_cleanup_exit", null, out);
    try out.appendSlice(allocator, "    end\n");
    try emitBlockReleaseManagedLocals(allocator, &cleanup_locals, ctx, out);
}

fn emitStorageAssignment(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_start: usize,
    body_end: usize,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !bool {
    if (start_idx + 2 >= end_idx) return false;
    if (tokens[start_idx].kind != .ident) return false;
    const source_name = tokens[start_idx].lexeme;
    const storage = findStorageLocal(locals.storage_locals.items, source_name) orelse return false;
    const target_name = storage.name;
    if (!tokEq(tokens[start_idx + 1], "=")) return false;
    const rhs_start = start_idx + 2;
    if (rhs_start < end_idx and tokens[rhs_start].kind == .string) {
        if (!std.mem.eql(u8, storage.elem_ty, "u8")) return error.NoMatchingCall;
        try emitOverwriteReleaseManagedLocal(allocator, target_name, out);
        try emitStorageU8StringLiteral(allocator, tokens, rhs_start, target_name, ctx, out);
        return true;
    }
    if (try emitStorageAggLiteral(allocator, tokens, rhs_start, end_idx, STORAGE_OVERWRITE_TMP_LOCAL, storage.elem_ty, locals, ctx, out)) {
        try emitReplaceManagedLocalFromTmp(allocator, target_name, out);
        return true;
    }
    if (try emitStorageHandleAssignmentExpr(allocator, tokens, rhs_start, end_idx, body_start, body_end, source_name, target_name, locals, defer_ctx, ctx, out)) {
        return true;
    }
    if (!try emitStorageWriteExpr(allocator, tokens, rhs_start, end_idx, target_name, locals, ctx, out)) {
        return error.NoMatchingCall;
    }
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try emitReplaceManagedLocalFromTmp(allocator, target_name, out);
    return true;
}

fn emitMultiResultAssignment(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
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
    const func = findFuncDeclForCallHead(tokens, call_head, locals, ctx) orelse return false;
    if (func.results.len <= 1) return false;
    if (func.result_items.len == 0) return false;

    var lhs_items = std.ArrayList(MultiResultLhs).empty;
    defer lhs_items.deinit(allocator);

    var lhs_start = start_idx;
    var item_idx: usize = 0;
    while (lhs_start < eq_idx) {
        if (item_idx >= func.result_items.len) return error.NoMatchingCall;
        const lhs_end = findArgEnd(tokens, lhs_start, eq_idx);
        if (lhs_end != lhs_start + 1 or tokens[lhs_start].kind != .ident) return error.NoMatchingCall;
        const lhs = multiResultLhsForItem(tokens[lhs_start].lexeme, func.result_items[item_idx], locals, ctx) orelse return error.NoMatchingCall;
        try lhs_items.append(allocator, lhs);

        item_idx += 1;
        lhs_start = lhs_end;
        if (lhs_start < eq_idx and tokEq(tokens[lhs_start], ",")) lhs_start += 1;
    }
    if (item_idx != func.result_items.len) return error.NoMatchingCall;

    const move_ctx = CallLastUseMoveContext{
        .body_start = 0,
        .stmt_end = end_idx,
        .body_end = body_end,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = allow_last_use_move,
    };
    if (!try emitUserFuncCallWithMoveContext(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, &move_ctx, out)) {
        return error.NoMatchingCall;
    }

    var i = lhs_items.items.len;
    while (i > 0) {
        i -= 1;
        try emitMultiResultLhsSet(allocator, lhs_items.items[i], ctx, out);
    }
    return true;
}

fn multiResultLhsForItem(
    name: []const u8,
    item: FuncResultItem,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?MultiResultLhs {
    if (item.union_layout) |layout| {
        const union_local = findUnionLocal(locals.union_locals.items, name) orelse return null;
        if (!unionLayoutsEqual(union_local.layout, layout)) return null;
        return .{ .name = union_local.name, .ty = item.ty, .item = item, .kind = .union_value };
    }

    if (findStructLocal(locals.struct_locals.items, name)) |struct_local| {
        if (!std.mem.eql(u8, struct_local.ty, item.ty)) return null;
        if (findStructLayout(ctx.struct_layouts, item.ty) != null) {
            const local_name = findLocalName(locals.locals.items, name) orelse return null;
            const local_ty = findLocalType(locals.locals.items, name) orelse return null;
            if (!std.mem.eql(u8, local_ty, item.ty)) return null;
            if (item.abi_len != 1) return null;
            return .{ .name = local_name, .ty = local_ty, .item = item, .kind = .managed };
        }
        const decl = findStructDecl(ctx.structs, item.ty) orelse return null;
        if (item.abi_len != decl.fields.len) return null;
        return .{ .name = struct_local.name, .ty = item.ty, .item = item, .kind = .unmanaged_struct };
    }

    const local_name = findLocalName(locals.locals.items, name) orelse return null;
    const local_ty = findLocalType(locals.locals.items, name) orelse return null;
    if (!std.mem.eql(u8, local_ty, item.ty)) return null;
    if (item.abi_len != 1) return null;
    if (isManagedLocalType(local_ty, ctx)) {
        return .{ .name = local_name, .ty = local_ty, .item = item, .kind = .managed };
    }
    if (isCodegenScalarType(ctx, local_ty)) {
        return .{ .name = local_name, .ty = local_ty, .item = item, .kind = .scalar };
    }
    return null;
}

fn emitMultiResultLhsSet(
    allocator: std.mem.Allocator,
    lhs: MultiResultLhs,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !void {
    switch (lhs.kind) {
        .scalar => try appendFmt(allocator, out, "    local.set ${s}\n", .{lhs.name}),
        .managed => {
            try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
            try emitReplaceManagedLocalFromTmp(allocator, lhs.name, out);
        },
        .union_value => {
            var idx = lhs.item.abi_len;
            while (idx > 0) {
                idx -= 1;
                if (idx == lhs.item.abi_len - 1) {
                    try appendUnionTagLocalSet(allocator, out, lhs.name);
                } else {
                    try appendUnionPayloadLocalSet(allocator, out, lhs.name, idx);
                }
            }
        },
        .unmanaged_struct => {
            const decl = findStructDecl(ctx.structs, lhs.ty) orelse return error.NoMatchingCall;
            if (decl.fields.len != lhs.item.abi_len) return error.NoMatchingCall;
            var idx = decl.fields.len;
            while (idx > 0) {
                idx -= 1;
                try appendFmt(allocator, out, "    local.set ${s}.{s}\n", .{
                    lhs.name,
                    publicDeclName(decl.fields[idx].name),
                });
            }
        },
    }
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
    const func = findFuncDeclForCallHead(tokens, call_head, locals, ctx) orelse return false;
    if (func.results.len <= 1) return false;
    if (func.result_items.len == 0) return false;

    var lhs_start = start_idx;
    var item_idx: usize = 0;
    while (lhs_start < eq_idx) {
        if (item_idx >= func.result_items.len) return false;
        const lhs_end = findArgEnd(tokens, lhs_start, eq_idx);
        if (lhs_end != lhs_start + 1 or tokens[lhs_start].kind != .ident) return false;
        const lhs = multiResultLhsForItem(tokens[lhs_start].lexeme, func.result_items[item_idx], locals, ctx) orelse return false;
        if (lhs.kind == .managed) return true;

        item_idx += 1;
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
    body_start: usize,
    body_end: usize,
    target_source_name: []const u8,
    target_name: []const u8,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (end_idx == start_idx + 1 and tokens[start_idx].kind == .ident) {
        if (directManagedLocalExprName(tokens, start_idx, end_idx, locals, ctx)) |actual_name| {
            if (std.mem.eql(u8, actual_name, target_name)) return true;
        }
    }
    const expected_ty = findLocalType(locals.locals.items, target_name) orelse return false;
    if (!try emitStorageHandleBindingExpr(allocator, tokens, start_idx, end_idx, body_start, body_end, true, expected_ty, locals, defer_ctx, ctx, out)) return false;
    const move_source = directManagedLastUseMoveSource(tokens, start_idx, end_idx, body_end, target_source_name, locals, ctx, defer_ctx);
    if (move_source == null and isDirectManagedLocalExpr(tokens, start_idx, end_idx, locals, ctx)) {
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try emitReplaceManagedLocalFromTmp(allocator, target_name, out);
    if (move_source) |source| {
        try appendFmt(allocator, out, "    ;; arc-overwrite-move {s}\n", .{source.source_name});
        try out.appendSlice(allocator, "    i32.const 0\n");
        try appendFmt(allocator, out, "    local.set ${s}\n", .{source.actual_name});
    }
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
    try out.appendSlice(allocator, "      call $__arc_dec\n");
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
    try out.appendSlice(allocator, "    call $__arc_dec\n");
}

fn emitManagedLocalAssignment(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_end: usize,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (!isManagedLocalAssignmentStmt(tokens, start_idx, end_idx, locals, ctx)) return false;
    const target_name = tokens[start_idx].lexeme;
    const target_local_name = findLocalName(locals.locals.items, target_name) orelse return false;
    const target_ty = findLocalType(locals.locals.items, target_name) orelse return false;
    const rhs_start = start_idx + 2;

    if (end_idx == rhs_start + 1 and tokens[rhs_start].kind == .ident) {
        if (directManagedLocalExprName(tokens, rhs_start, end_idx, locals, ctx)) |actual_name| {
            if (std.mem.eql(u8, actual_name, target_local_name)) return true;
        }
    }

    if (!try emitExpr(allocator, tokens, rhs_start, end_idx, locals, ctx, target_ty, out)) {
        return error.NoMatchingCall;
    }
    const move_source = directManagedLastUseMoveSource(tokens, rhs_start, end_idx, body_end, target_name, locals, ctx, defer_ctx);
    if (move_source == null and isDirectManagedLocalExpr(tokens, rhs_start, end_idx, locals, ctx)) {
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try emitReplaceManagedLocalFromTmp(allocator, target_local_name, out);
    if (move_source) |source| {
        try appendFmt(allocator, out, "    ;; arc-overwrite-move {s}\n", .{source.source_name});
        try out.appendSlice(allocator, "    i32.const 0\n");
        try appendFmt(allocator, out, "    local.set ${s}\n", .{source.actual_name});
    }
    return true;
}

fn emitScalarCallExprWithMoveContext(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    expected_ty: []const u8,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const range = trimParens(tokens, start_idx, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = findFuncDeclForCallHead(tokens, call_head, locals, ctx) orelse return false;
    if (func.results.len != 1) return false;
    if (!std.mem.eql(u8, func.results[0], expected_ty)) return false;
    const move_ctx = CallLastUseMoveContext{
        .stmt_end = end_idx,
        .body_end = body_end,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = allow_last_use_move,
    };
    return try emitUserFuncCallWithMoveContext(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, &move_ctx, out);
}

fn emitManagedHandleCallExprWithMoveContext(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    expected_ty: []const u8,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const range = trimParens(tokens, start_idx, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = findFuncDeclForCallHead(tokens, call_head, locals, ctx) orelse return false;
    if (func.results.len != 1) return false;
    if (!std.mem.eql(u8, func.results[0], expected_ty)) return false;
    const move_ctx = CallLastUseMoveContext{
        .stmt_end = end_idx,
        .body_end = body_end,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = allow_last_use_move,
    };
    return try emitUserFuncCallWithMoveContext(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, &move_ctx, out);
}

fn emitScalarAssignment(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (start_idx + 3 > end_idx) return false;
    if (tokens[start_idx].kind != .ident) return false;
    if (!tokEq(tokens[start_idx + 1], "=")) return false;

    const target_ty = findLocalType(locals.locals.items, tokens[start_idx].lexeme) orelse return false;
    const target_name = findLocalName(locals.locals.items, tokens[start_idx].lexeme) orelse return false;
    if (!isCodegenScalarType(ctx, target_ty)) return false;
    if (!try emitScalarCallExprWithMoveContext(allocator, tokens, start_idx + 2, end_idx, body_end, allow_last_use_move, locals, defer_ctx, ctx, target_ty, out) and
        !try emitExpr(allocator, tokens, start_idx + 2, end_idx, locals, ctx, target_ty, out))
    {
        return error.NoMatchingCall;
    }
    try appendFmt(allocator, out, "    local.set ${s}\n", .{target_name});
    return true;
}

fn emitInferredScalarBinding(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const ty = inferredScalarBindingType(tokens, start_idx, end_idx, locals, ctx) orelse return false;
    if (!try emitScalarCallExprWithMoveContext(allocator, tokens, start_idx + 2, end_idx, body_end, allow_last_use_move, locals, defer_ctx, ctx, ty, out) and
        !try emitExpr(allocator, tokens, start_idx + 2, end_idx, locals, ctx, ty, out))
    {
        return error.NoMatchingCall;
    }
    const target_name = findLocalName(locals.locals.items, tokens[start_idx].lexeme) orelse return false;
    try appendFmt(allocator, out, "    local.set ${s}\n", .{target_name});
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
    return emitExprWithMoveContext(allocator, tokens, start_idx, end_idx, locals, ctx, expected_ty, null, out);
}

fn emitExprWithMoveContext(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    expected_ty: ?[]const u8,
    move_ctx: ?*const CallLastUseMoveContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.start >= range.end) return false;

    if (expected_ty) |ty| {
        if (try emitTupleExpr(allocator, tokens, range.start, range.end, locals, ctx, ty, out)) {
            return true;
        }
        if (managedPayloadElemTypeFromName(ty)) |elem_ty| {
            if (isStorageAggLiteralExpr(tokens, range.start, range.end)) {
                if (!try emitStorageAggLiteral(allocator, tokens, range.start, range.end, STORAGE_OVERWRITE_TMP_LOCAL, elem_ty, locals, ctx, out)) {
                    return error.NoMatchingCall;
                }
                try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
                return true;
            }
        }
        if (try emitStructLiteralExpr(allocator, tokens, range.start, range.end, locals, ctx, ty, out)) {
            return true;
        }
    }

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
            try emitNumberConst(allocator, ctx, out, tok.lexeme, expected_ty orelse "i32");
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
                if (valueEnumBranchValue(ctx, tokens, ty, tok.lexeme)) |value| {
                    try emitNumberConst(allocator, ctx, out, value, ty);
                    return true;
                }
            }
        }
        if (tok.kind == .ident and std.mem.eql(u8, tok.lexeme, "true")) {
            if (expected_ty) |ty| {
                if (!std.mem.eql(u8, ty, "bool")) return false;
            }
            try out.appendSlice(allocator, "    i32.const 1\n");
            return true;
        }
        if (tok.kind == .ident and std.mem.eql(u8, tok.lexeme, "false")) {
            if (expected_ty) |ty| {
                if (!std.mem.eql(u8, ty, "bool")) return false;
            }
            try out.appendSlice(allocator, "    i32.const 0\n");
            return true;
        }
        if (tok.kind == .ident) {
            if (expected_ty) |ty| {
                if (findStructLocal(locals.struct_locals.items, tok.lexeme)) |struct_local| {
                    if (std.mem.eql(u8, struct_local.ty, ty) and findStructLayout(ctx.struct_layouts, ty) == null) {
                        const decl = findStructDecl(ctx.structs, ty) orelse return false;
                        try emitStructFieldsFromLocal(allocator, tokens, struct_local, decl, locals, ctx, false, out);
                        return true;
                    }
                }
                if (try emitUnionLocalPayloadForType(allocator, tok.lexeme, ty, locals, ctx, out)) {
                    return true;
                }
            }
        }
        if (tok.kind == .ident) {
            if (findLocalName(locals.locals.items, tok.lexeme)) |local_name| {
                try appendFmt(allocator, out, "    local.get ${s}\n", .{local_name});
                return true;
            }
        }
        if (tok.kind == .ident) {
            if (findCallbackCallArg(ctx.callback_call_args, tok.lexeme)) |callback_arg| {
                return try emitExpr(
                    allocator,
                    callback_arg.expr_tokens,
                    callback_arg.expr_start,
                    callback_arg.expr_end,
                    locals,
                    ctx,
                    callback_arg.ty,
                    out,
                );
            }
        }
        if (tok.kind == .ident) {
            if (localScalarConst(tokens, tok.lexeme)) |local_const| {
                const ty = expected_ty orelse local_const.ty;
                try emitNumberConst(allocator, ctx, out, local_const.value, ty);
                return true;
            }
        }
        if (tok.kind == .ident) {
            const imported_const = importedScalarConst(ctx, tokens, tok.lexeme) orelse return false;
            const ty = expected_ty orelse imported_const.ty;
            try emitNumberConst(allocator, ctx, out, imported_const.value, ty);
            return true;
        }
        return false;
    }

    const call_head = exprCallHead(tokens, range) orelse return false;
    const call_name = tokens[call_head.name_idx].lexeme;

    if (call_head.is_intrinsic) {
        if (try emitFieldReflectionIntrinsic(allocator, tokens, call_head.args_start, call_head.args_end, call_name, locals, ctx, move_ctx, out)) {
            return true;
        }

        if (shouldEmitBoolSpecialCall(call_name, expected_ty, tokens, call_head.args_start, call_head.args_end, locals, ctx)) {
            return try emitBoolSpecialCall(allocator, tokens, call_head.args_start, call_head.args_end, call_name, locals, ctx, out);
        }

        if (std.mem.eql(u8, call_name, "as")) {
            if (try emitScalarAsCall(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, out)) {
                return true;
            }
            return false;
        }

        if (std.mem.eql(u8, call_name, "is")) {
            return try emitUnionIsCall(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, out);
        }

        if (std.mem.eql(u8, call_name, "eq") or std.mem.eql(u8, call_name, "ne")) {
            if (try emitUnionNilComparison(allocator, tokens, call_head.args_start, call_head.args_end, move_ctx, call_name, locals, ctx, out)) {
                return true;
            }
            if (try emitUnionPayloadComparisonLocal(allocator, tokens, call_head.args_start, call_head.args_end, call_name, locals, ctx, out)) {
                return true;
            }
            if (try emitUnionErrorBranchComparison(allocator, tokens, call_head.args_start, call_head.args_end, call_name, locals, ctx, out)) {
                return true;
            }
            if (try emitUnionPayloadComparisonCall(allocator, tokens, call_head.args_start, call_head.args_end, call_name, locals, ctx, out)) {
                return true;
            }
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
            if (try emitStorageContentComparisonCall(allocator, tokens, call_head.args_start, call_head.args_end, call_name, locals, ctx, out)) {
                return true;
            }

            const cmp_ty = inferExprType(tokens, call_head.args_start, findArgEnd(tokens, call_head.args_start, call_head.args_end), locals, ctx) orelse "i32";
            const op_ty = codegenScalarType(ctx, cmp_ty);
            const op = comparisonWasmOp(call_name, op_ty) orelse return false;
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
            return try emitGetCall(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, move_ctx, out);
        }
        if (std.mem.eql(u8, call_name, "set")) {
            if (try emitStructSetExpr(allocator, tokens, call_head.args_start, call_head.args_end, expected_ty, locals, ctx, out)) {
                return true;
            }
            return try emitStorageSetExpr(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, out);
        }
        if (std.mem.eql(u8, call_name, "put")) {
            return try emitStoragePutExpr(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, out);
        }
        if (isMemoryLoadName(call_name)) {
            return try emitMemoryLoadCall(allocator, tokens, call_head.args_start, call_head.args_end, call_name, locals, ctx, out);
        }

        return false;
    }

    if (isCoreWasmCallName(call_name)) return false;

    if (findCallbackBinding(ctx.callback_bindings, call_name)) |binding| {
        return try emitCallbackBindingCall(allocator, tokens, call_head, locals, ctx, binding, out);
    }

    if (findFuncDeclForCallHead(tokens, call_head, locals, ctx)) |func| {
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

fn emitStorageContentComparisonCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    call_name: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (!std.mem.eql(u8, call_name, "eq") and !std.mem.eql(u8, call_name, "ne")) return false;
    const first_end = findArgEnd(tokens, args_start, args_end);
    if (first_end >= args_end or !tokEq(tokens[first_end], ",")) return false;
    const second_start = first_end + 1;
    const second_end = findArgEnd(tokens, second_start, args_end);
    if (second_end != args_end) return false;

    const cmp_ty = inferStorageContentComparisonType(tokens, args_start, first_end, second_start, second_end, locals, ctx) orelse return false;
    if (try emitManagedPayloadStorageContentComparisonCall(allocator, tokens, args_start, first_end, second_start, second_end, cmp_ty, call_name, locals, ctx, out)) {
        return true;
    }
    if (!try emitExpr(allocator, tokens, args_start, first_end, locals, ctx, cmp_ty, out)) return false;
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
    if (!try emitExpr(allocator, tokens, second_start, second_end, locals, ctx, cmp_ty, out)) return false;
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try out.appendSlice(allocator, "    call $__storage_equal_u8\n");
    if (std.mem.eql(u8, call_name, "ne")) {
        try out.appendSlice(allocator, "    i32.eqz\n");
    }
    return true;
}

fn emitManagedPayloadStorageContentComparisonCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    left_start: usize,
    left_end: usize,
    right_start: usize,
    right_end: usize,
    cmp_ty: []const u8,
    call_name: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const elem_ty = storageElemTypeFromName(cmp_ty) orelse return false;
    const nested_elem_ty = managedPayloadElemTypeFromName(elem_ty) orelse return false;
    if (!std.mem.eql(u8, nested_elem_ty, "u8")) return false;

    if (!try emitExpr(allocator, tokens, left_start, left_end, locals, ctx, cmp_ty, out)) return false;
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
    if (!try emitExpr(allocator, tokens, right_start, right_end, locals, ctx, cmp_ty, out)) return false;
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});

    try appendFmt(allocator, out, "    i32.const 0\n    local.set ${s}\n", .{STORAGE_WRITE_SCAN_TMP_LOCAL});
    try appendFmt(allocator, out, "    i32.const 1\n    local.set ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try out.appendSlice(allocator, "    block $storage_managed_eq_done\n");
    try emitStorageLenPtr(allocator, out, STORAGE_PUT_SOURCE_TMP_LOCAL);
    try out.appendSlice(allocator, "      i32.load\n");
    try emitStorageLenPtr(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL);
    try out.appendSlice(allocator,
        \\      i32.load
        \\      i32.ne
        \\      if
        \\
    );
    try appendFmt(allocator, out, "        i32.const 0\n        local.set ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try out.appendSlice(allocator,
        \\        br $storage_managed_eq_done
        \\      end
        \\      loop $storage_managed_eq_loop
        \\
    );
    try appendFmt(allocator, out, "        local.get ${s}\n", .{STORAGE_WRITE_SCAN_TMP_LOCAL});
    try emitStorageLenPtr(allocator, out, STORAGE_PUT_SOURCE_TMP_LOCAL);
    try out.appendSlice(allocator,
        \\        i32.load
        \\        i32.ge_u
        \\        br_if $storage_managed_eq_done
        \\
    );
    try emitStorageDataPtr(allocator, out, STORAGE_PUT_SOURCE_TMP_LOCAL);
    try appendFmt(allocator, out, "        local.get ${s}\n", .{STORAGE_WRITE_SCAN_TMP_LOCAL});
    try out.appendSlice(allocator,
        \\        i32.const 4
        \\        i32.mul
        \\        i32.add
        \\        i32.load
        \\
    );
    try emitStorageDataPtr(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL);
    try appendFmt(allocator, out, "        local.get ${s}\n", .{STORAGE_WRITE_SCAN_TMP_LOCAL});
    try out.appendSlice(allocator,
        \\        i32.const 4
        \\        i32.mul
        \\        i32.add
        \\        i32.load
        \\        call $__storage_equal_u8
        \\        i32.eqz
        \\        if
        \\
    );
    try appendFmt(allocator, out, "          i32.const 0\n          local.set ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try out.appendSlice(allocator,
        \\          br $storage_managed_eq_done
        \\        end
        \\
    );
    try appendFmt(allocator, out, "        local.get ${s}\n        i32.const 1\n        i32.add\n        local.set ${s}\n", .{
        STORAGE_WRITE_SCAN_TMP_LOCAL,
        STORAGE_WRITE_SCAN_TMP_LOCAL,
    });
    try out.appendSlice(allocator,
        \\        br $storage_managed_eq_loop
        \\      end
        \\    end
        \\
    );
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    if (std.mem.eql(u8, call_name, "ne")) {
        try out.appendSlice(allocator, "    i32.eqz\n");
    }
    return true;
}

fn inferStorageContentComparisonType(
    tokens: []const lexer.Token,
    left_start: usize,
    left_end: usize,
    right_start: usize,
    right_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    const left_ty = inferExprType(tokens, left_start, left_end, locals, ctx);
    const right_ty = inferExprType(tokens, right_start, right_end, locals, ctx);
    if (left_ty) |ty| {
        if (isManagedPayloadComparableType(ty) and storageContentArgCompatible(tokens, right_start, right_end, right_ty, ty)) return ty;
    }
    if (right_ty) |ty| {
        if (isManagedPayloadComparableType(ty) and storageContentArgCompatible(tokens, left_start, left_end, left_ty, ty)) return ty;
    }
    if (isStringLiteralArg(tokens, left_start, left_end) and isStringLiteralArg(tokens, right_start, right_end)) return "text";
    return null;
}

fn storageContentArgCompatible(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    inferred_ty: ?[]const u8,
    target_ty: []const u8,
) bool {
    if (inferred_ty) |ty| return codegenTypesCompatible(target_ty, ty);
    if (isStorageAggLiteralExpr(tokens, start_idx, end_idx)) return true;
    return isStringLiteralArg(tokens, start_idx, end_idx);
}

fn isManagedPayloadComparableType(ty: []const u8) bool {
    return managedPayloadElemTypeFromName(ty) != null;
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
    return emitBareUserFuncCallWithMoveContext(allocator, tokens, start_idx, end_idx, end_idx, true, locals, null, ctx, out);
}

fn emitBareUserFuncCallWithMoveContext(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const range = trimParens(tokens, start_idx, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = findFuncDeclForCallHead(tokens, call_head, locals, ctx) orelse return false;
    if (func.results.len != 0) return false;
    const move_ctx = CallLastUseMoveContext{
        .stmt_end = end_idx,
        .body_end = body_end,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = allow_last_use_move,
    };
    if (!try emitUserFuncCallWithMoveContext(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, &move_ctx, out)) {
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

fn emitTupleExpr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    expected_ty: []const u8,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (!isTupleTypeName(expected_ty)) return false;
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.start >= range.end) return false;

    if (range.end == range.start + 1 and tokens[range.start].kind == .ident) {
        const tuple_local = findStructLocal(locals.struct_locals.items, tokens[range.start].lexeme) orelse return false;
        if (!std.mem.eql(u8, tuple_local.ty, expected_ty)) return false;
        try emitTupleLocalGet(allocator, tuple_local.name, expected_ty, ctx, out);
        return true;
    }

    const open_brace = structLiteralOpenRhs(tokens, range.start, range.end) orelse return false;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", range.end) catch return false;
    if (close_brace + 1 != range.end) return false;

    const literal_ty = compactTokenText(allocator, tokens, range.start, open_brace) catch return false;
    defer allocator.free(literal_ty);
    if (!std.mem.eql(u8, literal_ty, expected_ty)) return false;

    const arity = tupleArity(expected_ty) orelse return false;
    var expr_start = open_brace + 1;
    var idx: usize = 0;
    while (expr_start < close_brace) {
        const expr_end = findArgEnd(tokens, expr_start, close_brace);
        if (idx >= arity) return error.NoMatchingCall;
        const elem_ty = tupleElementTypeAt(expected_ty, idx) orelse return error.UnsupportedLowering;
        if (!try emitExpr(allocator, tokens, expr_start, expr_end, locals, ctx, elem_ty, out)) return error.NoMatchingCall;
        idx += 1;
        expr_start = expr_end;
        if (expr_start < close_brace) {
            if (!tokEq(tokens[expr_start], ",")) return error.NoMatchingCall;
            expr_start += 1;
        }
    }
    if (idx != arity) return error.NoMatchingCall;
    return true;
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

fn emitUnionIsCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const first_end = findArgEnd(tokens, args_start, args_end);
    if (first_end != args_start + 1 or tokens[args_start].kind != .ident) return false;
    if (first_end >= args_end or !tokEq(tokens[first_end], ",")) return false;
    const union_local = findUnionLocal(locals.union_locals.items, tokens[args_start].lexeme) orelse return false;
    const type_start = first_end + 1;
    const type_end = args_end;

    var tags = std.ArrayList(usize).empty;
    defer tags.deinit(allocator);
    try collectUnionIsTags(allocator, tokens, type_start, type_end, ctx, union_local.layout, &tags);
    if (tags.items.len == 0) return false;

    for (tags.items, 0..) |tag, idx| {
        try appendUnionTagLocalGet(allocator, out, union_local.name);
        try appendFmt(allocator, out, "    i32.const {d}\n", .{tag});
        try out.appendSlice(allocator, "    i32.eq\n");
        if (idx != 0) try out.appendSlice(allocator, "    i32.or\n");
    }
    return true;
}

fn collectUnionIsTags(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    layout: UnionLayout,
    out: *std.ArrayList(usize),
) CodegenError!void {
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }

    var branch_start = start_idx;
    while (branch_start < end_idx) {
        if (tokEq(tokens[branch_start], "|")) {
            branch_start += 1;
            continue;
        }
        const branch_end = findTopLevelToken(tokens, branch_start, end_idx, "|") orelse end_idx;
        if (branch_end == branch_start) return error.NoMatchingCall;
        if (branch_end == branch_start + 1 and tokEq(tokens[branch_start], "nil")) return error.NoMatchingCall;
        const parsed_ty = (try parseCodegenTypeExpr(allocator, tokens, branch_start, branch_end, &owned_types)) orelse return error.NoMatchingCall;
        if (parsed_ty.next_idx != branch_end) return error.NoMatchingCall;
        const branch = findUnionBranchByType(layout, parsed_ty.ty) orelse return error.NoMatchingCall;
        if (branch.tag == 0) return error.NoMatchingCall;
        try out.append(allocator, branch.tag);
        branch_start = branch_end;
        if (branch_start < end_idx and tokEq(tokens[branch_start], "|")) branch_start += 1;
    }

    _ = ctx;
}

fn emitUnionNilComparison(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    move_ctx: ?*const CallLastUseMoveContext,
    call_name: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const first_end = findArgEnd(tokens, args_start, args_end);
    if (first_end == args_start or first_end >= args_end or !tokEq(tokens[first_end], ",")) return false;
    const second_start = first_end + 1;
    const second_end = findArgEnd(tokens, second_start, args_end);
    if (second_end != args_end) return false;

    const first_union = unionLocalSingleIdent(tokens, args_start, first_end, locals);
    const second_union = unionLocalSingleIdent(tokens, second_start, second_end, locals);
    const first_nil = first_end == args_start + 1 and tokEq(tokens[args_start], "nil");
    const second_nil = second_end == second_start + 1 and tokEq(tokens[second_start], "nil");

    if (first_union != null and second_nil) {
        try appendUnionTagLocalGet(allocator, out, first_union.?.name);
    } else if (second_union != null and first_nil) {
        try appendUnionTagLocalGet(allocator, out, second_union.?.name);
    } else if (second_nil) {
        if (!try emitUnionExprTagAndDiscardPayload(allocator, tokens, args_start, first_end, move_ctx, locals, ctx, out)) {
            return false;
        }
    } else if (first_nil) {
        if (!try emitUnionExprTagAndDiscardPayload(allocator, tokens, second_start, second_end, move_ctx, locals, ctx, out)) {
            return false;
        }
    } else {
        return false;
    }
    try out.appendSlice(allocator, "    i32.const 0\n");
    if (std.mem.eql(u8, call_name, "eq")) {
        try out.appendSlice(allocator, "    i32.eq\n");
    } else {
        try out.appendSlice(allocator, "    i32.ne\n");
    }
    return true;
}

fn emitUnionExprTagAndDiscardPayload(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    move_ctx: ?*const CallLastUseMoveContext,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const range = trimParens(tokens, start_idx, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = findFuncDeclForCallHead(tokens, call_head, locals, ctx) orelse return false;
    const layout = func.result_union orelse return false;
    if (!try emitUserFuncCallWithMoveContext(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, move_ctx, out)) {
        return false;
    }
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    var idx = layout.payload_tys.len;
    while (idx > 0) {
        idx -= 1;
        if (isManagedLocalType(layout.payload_tys[idx], ctx)) {
            try out.appendSlice(allocator, "    call $__arc_dec\n");
        } else {
            try out.appendSlice(allocator, "    drop\n");
        }
    }
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    return true;
}

fn unionPayloadComparisonCallBranch(
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?UnionBranch {
    const first_end = findArgEnd(tokens, args_start, args_end);
    if (first_end == args_start or first_end >= args_end or !tokEq(tokens[first_end], ",")) return null;
    const second_start = first_end + 1;
    const second_end = findArgEnd(tokens, second_start, args_end);
    if (second_end != args_end) return null;
    const range = trimParens(tokens, args_start, first_end);
    const call_head = exprCallHead(tokens, range) orelse return null;
    if (call_head.is_intrinsic) return null;
    const func = findFuncDeclForCallHead(tokens, call_head, locals, ctx) orelse return null;
    const layout = func.result_union orelse return null;
    return unionPayloadComparisonBranchForValue(tokens, second_start, second_end, locals, ctx, layout);
}

fn unionPayloadComparisonBranchForValue(
    tokens: []const lexer.Token,
    value_start: usize,
    value_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    layout: UnionLayout,
) ?UnionBranch {
    if (layout.payload_tys.len != 1) return null;
    for (layout.branches) |branch| {
        if (branch.tag == 0 or branch.payload_len != 1 or branch.payload_start != 0) continue;
        if (!isCodegenScalarType(ctx, branch.ty)) continue;
        if (!callArgMatchesParam(tokens, value_start, value_end, locals, ctx, branch.ty)) continue;
        return branch;
    }
    return null;
}

fn emitUnionPayloadComparisonCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    call_name: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const first_end = findArgEnd(tokens, args_start, args_end);
    if (first_end == args_start or first_end >= args_end or !tokEq(tokens[first_end], ",")) return false;
    const second_start = first_end + 1;
    const second_end = findArgEnd(tokens, second_start, args_end);
    if (second_end != args_end) return false;
    const range = trimParens(tokens, args_start, first_end);
    const call_head = exprCallHead(tokens, range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const func = findFuncDeclForCallHead(tokens, call_head, locals, ctx) orelse return false;
    const layout = func.result_union orelse return false;
    const branch = unionPayloadComparisonBranchForValue(tokens, second_start, second_end, locals, ctx, layout) orelse return false;

    if (!try emitUserFuncCall(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, func, out)) {
        return false;
    }
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    if (!try emitExpr(allocator, tokens, second_start, second_end, locals, ctx, branch.ty, out)) {
        return false;
    }
    const op_ty = codegenScalarType(ctx, branch.ty);
    const eq_op = comparisonWasmOp("eq", op_ty) orelse return false;
    try appendFmt(allocator, out, "    {s}\n", .{eq_op});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try appendFmt(allocator, out, "    i32.const {d}\n", .{branch.tag});
    try out.appendSlice(allocator, "    i32.eq\n");
    try out.appendSlice(allocator, "    i32.and\n");
    if (std.mem.eql(u8, call_name, "ne")) {
        try out.appendSlice(allocator, "    i32.eqz\n");
    }
    return true;
}

fn emitUnionPayloadComparisonLocal(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    call_name: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const first_end = findArgEnd(tokens, args_start, args_end);
    if (first_end == args_start or first_end >= args_end or !tokEq(tokens[first_end], ",")) return false;
    const second_start = first_end + 1;
    const second_end = findArgEnd(tokens, second_start, args_end);
    if (second_end != args_end) return false;

    const first_union = unionLocalSingleIdent(tokens, args_start, first_end, locals);
    const second_union = unionLocalSingleIdent(tokens, second_start, second_end, locals);
    if (first_union != null and second_union != null) return false;

    const union_local = first_union orelse second_union orelse return false;
    const value_start = if (first_union != null) second_start else args_start;
    const value_end = if (first_union != null) second_end else first_end;
    const branch = unionPayloadComparisonBranchForLocalValue(tokens, value_start, value_end, locals, ctx, union_local.layout) orelse return false;

    try appendUnionPayloadLocalGet(allocator, out, union_local.name, branch.payload_start);
    if (!try emitExpr(allocator, tokens, value_start, value_end, locals, ctx, branch.ty, out)) {
        return false;
    }
    const op_ty = codegenScalarType(ctx, branch.ty);
    const eq_op = comparisonWasmOp("eq", op_ty) orelse return false;
    try appendFmt(allocator, out, "    {s}\n", .{eq_op});
    try appendUnionTagLocalGet(allocator, out, union_local.name);
    try appendFmt(allocator, out, "    i32.const {d}\n", .{branch.tag});
    try out.appendSlice(allocator, "    i32.eq\n");
    try out.appendSlice(allocator, "    i32.and\n");
    if (std.mem.eql(u8, call_name, "ne")) {
        try out.appendSlice(allocator, "    i32.eqz\n");
    }
    return true;
}

fn unionPayloadComparisonBranchForLocalValue(
    tokens: []const lexer.Token,
    value_start: usize,
    value_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    layout: UnionLayout,
) ?UnionBranch {
    for (layout.branches) |branch| {
        if (branch.tag == 0 or branch.payload_len != 1) continue;
        if (!isCodegenScalarType(ctx, branch.ty)) continue;
        if (!callArgMatchesParam(tokens, value_start, value_end, locals, ctx, branch.ty)) continue;
        return branch;
    }
    return null;
}

fn emitUnionErrorBranchComparison(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    call_name: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const first_end = findArgEnd(tokens, args_start, args_end);
    if (first_end == args_start or first_end >= args_end or !tokEq(tokens[first_end], ",")) return false;
    const second_start = first_end + 1;
    const second_end = findArgEnd(tokens, second_start, args_end);
    if (second_end != args_end) return false;

    const first_union = unionLocalSingleIdent(tokens, args_start, first_end, locals);
    const second_union = unionLocalSingleIdent(tokens, second_start, second_end, locals);
    const union_local = first_union orelse second_union orelse return false;
    const value_start = if (first_union != null) second_start else args_start;
    const value_end = if (first_union != null) second_end else first_end;

    for (union_local.layout.branches) |branch| {
        if (branch.tag == 0 or branch.payload_len != 1) continue;
        const branch_value = errorBranchValueForComparison(allocator, ctx, tokens, value_start, value_end, branch.ty) orelse continue;
        try appendUnionTagLocalGet(allocator, out, union_local.name);
        try appendFmt(allocator, out, "    i32.const {d}\n", .{branch.tag});
        try out.appendSlice(allocator, "    i32.eq\n");
        try appendUnionPayloadLocalGet(allocator, out, union_local.name, branch.payload_start);
        try appendFmt(allocator, out, "    i32.const {d}\n", .{branch_value});
        try out.appendSlice(allocator, "    i32.eq\n");
        try out.appendSlice(allocator, "    i32.and\n");
        if (std.mem.eql(u8, call_name, "ne")) {
            try out.appendSlice(allocator, "    i32.eqz\n");
        }
        return true;
    }
    return false;
}

fn errorBranchValueForComparison(
    allocator: std.mem.Allocator,
    ctx: CodegenContext,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    error_ty: []const u8,
) ?usize {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.end != range.start + 1 or tokens[range.start].kind != .ident) return null;
    const name = tokens[range.start].lexeme;
    if (errorEnumBranchValue(tokens, error_ty, name)) |value| return value;
    return importedErrorBranchValue(allocator, ctx.imported_alias_ctx, tokens, name, error_ty);
}

fn emitUnionLocalPayloadForType(
    allocator: std.mem.Allocator,
    name: []const u8,
    ty: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const union_local = findUnionLocal(locals.union_locals.items, name) orelse return false;
    var matched: ?UnionBranch = null;
    for (union_local.layout.branches) |branch| {
        if (branch.payload_len != 1) continue;
        const concrete_branch_ty = substituteGenericType(branch.ty, ctx.type_bindings);
        if (!codegenTypesCompatible(concrete_branch_ty, ty)) continue;
        if (matched != null) return false;
        matched = branch;
    }
    const branch = matched orelse return false;

    const narrowed_ty = findNarrowedUnionType(locals.narrowed_union_locals.items, name) orelse
        return error.UnionPayloadRequiresNarrowing;
    const concrete_narrowed_ty = substituteGenericType(narrowed_ty, ctx.type_bindings);
    if (!codegenTypesCompatible(concrete_narrowed_ty, ty)) return false;

    try appendUnionPayloadLocalGet(allocator, out, union_local.name, branch.payload_start);
    return true;
}

fn unionLocalDefaultPayloadType(tokens: []const lexer.Token, union_local: UnionLocal) ?[]const u8 {
    var matched: ?[]const u8 = null;
    for (union_local.layout.branches) |branch| {
        if (branch.payload_len != 1) continue;
        if (std.mem.eql(u8, branch.ty, "nil")) continue;
        if (isErrorLikeType(tokens, branch.ty)) continue;
        if (matched != null) return null;
        matched = branch.ty;
    }
    return matched;
}

fn nilComparisonNarrowing(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
) ?NilComparisonNarrowing {
    const range = trimParens(tokens, start_idx, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return null;
    if (!call_head.is_intrinsic) return null;
    const call_name = tokens[call_head.name_idx].lexeme;
    if (!std.mem.eql(u8, call_name, "eq") and !std.mem.eql(u8, call_name, "ne")) return null;

    const first_end = findArgEnd(tokens, call_head.args_start, call_head.args_end);
    if (first_end == call_head.args_start or first_end >= call_head.args_end or !tokEq(tokens[first_end], ",")) return null;
    const second_start = first_end + 1;
    const second_end = findArgEnd(tokens, second_start, call_head.args_end);
    if (second_end != call_head.args_end) return null;

    const left_ident = singleIdentExpr(tokens, call_head.args_start, first_end);
    const right_ident = singleIdentExpr(tokens, second_start, second_end);
    const left_nil = singleNilExpr(tokens, call_head.args_start, first_end);
    const right_nil = singleNilExpr(tokens, second_start, second_end);
    const name = if (left_ident != null and right_nil)
        left_ident.?
    else if (right_ident != null and left_nil)
        right_ident.?
    else
        return null;

    const union_local = findUnionLocal(locals.union_locals.items, name) orelse return null;
    const payload_ty = unionLocalSingleNonNilPayloadType(union_local) orelse return null;
    return .{
        .union_local = union_local,
        .payload_ty = payload_ty,
        .non_nil_when_true = std.mem.eql(u8, call_name, "ne"),
    };
}

fn isComparisonNarrowing(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) CodegenError!?IsComparisonNarrowing {
    const range = trimParens(tokens, start_idx, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return null;
    if (!call_head.is_intrinsic) return null;
    if (!std.mem.eql(u8, tokens[call_head.name_idx].lexeme, "is")) return null;

    const first_end = findArgEnd(tokens, call_head.args_start, call_head.args_end);
    if (first_end != call_head.args_start + 1 or tokens[call_head.args_start].kind != .ident) return null;
    if (first_end >= call_head.args_end or !tokEq(tokens[first_end], ",")) return null;
    const union_local = findUnionLocal(locals.union_locals.items, tokens[call_head.args_start].lexeme) orelse return null;
    const type_start = first_end + 1;
    const type_end = trimTrailingComma(tokens, type_start, call_head.args_end);
    if (type_start >= type_end) return null;
    if (findTopLevelToken(tokens, type_start, type_end, "|") != null) return null;

    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    const parsed_ty = (try parseCodegenTypeExpr(allocator, tokens, type_start, type_end, &owned_types)) orelse return null;
    if (parsed_ty.next_idx != type_end) return null;
    const target_ty = try substituteGenericTypeOwned(allocator, parsed_ty.ty, ctx.type_bindings, &owned_types);
    if (std.mem.eql(u8, target_ty, "nil")) return null;
    const branch = findUnionBranchByType(union_local.layout, target_ty) orelse return null;
    if (branch.tag == 0) return null;
    return .{
        .union_local = union_local,
        .payload_ty = branch.ty,
    };
}

fn singleIdentExpr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.end != range.start + 1) return null;
    if (tokens[range.start].kind != .ident) return null;
    return tokens[range.start].lexeme;
}

fn singleNilExpr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    const range = trimParens(tokens, start_idx, end_idx);
    return range.end == range.start + 1 and tokEq(tokens[range.start], "nil");
}

fn unionLocalSingleNonNilPayloadType(union_local: UnionLocal) ?[]const u8 {
    var matched: ?[]const u8 = null;
    for (union_local.layout.branches) |branch| {
        if (std.mem.eql(u8, branch.ty, "nil")) continue;
        if (matched != null) return null;
        matched = branch.ty;
    }
    return matched;
}

fn unionLocalSingleRemainingPayloadType(union_local: UnionLocal, excluded_ty: []const u8) ?[]const u8 {
    var matched: ?[]const u8 = null;
    for (union_local.layout.branches) |branch| {
        if (std.mem.eql(u8, branch.ty, "nil")) continue;
        if (std.mem.eql(u8, branch.ty, excluded_ty)) continue;
        if (matched != null) return null;
        matched = branch.ty;
    }
    return matched;
}

fn appendNilComparisonNarrowingForBranch(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    cond_start: usize,
    cond_end: usize,
    locals: *LocalSet,
    branch_is_true: bool,
) !void {
    const narrowing = nilComparisonNarrowing(tokens, cond_start, cond_end, locals) orelse return;
    if (narrowing.non_nil_when_true != branch_is_true) return;
    try locals.appendNarrowedUnionLocal(allocator, narrowing.union_local, narrowing.payload_ty);
}

fn appendConditionNarrowingForBranch(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    cond_start: usize,
    cond_end: usize,
    locals: *LocalSet,
    ctx: CodegenContext,
    branch_is_true: bool,
) !void {
    try appendNilComparisonNarrowingForBranch(allocator, tokens, cond_start, cond_end, locals, branch_is_true);
    const narrowing = try isComparisonNarrowing(allocator, tokens, cond_start, cond_end, locals, ctx) orelse return;
    if (branch_is_true) {
        try locals.appendNarrowedUnionLocal(allocator, narrowing.union_local, narrowing.payload_ty);
    } else {
        const payload_ty = unionLocalSingleRemainingPayloadType(narrowing.union_local, narrowing.payload_ty) orelse return;
        try locals.appendNarrowedUnionLocal(allocator, narrowing.union_local, payload_ty);
    }
}

fn unionLocalDefaultStructPayload(tokens: []const lexer.Token, ctx: CodegenContext, union_local: UnionLocal) ?UnionStructPayload {
    var matched: ?UnionStructPayload = null;
    for (union_local.layout.branches) |branch| {
        if (std.mem.eql(u8, branch.ty, "nil")) continue;
        if (isErrorLikeType(tokens, branch.ty)) continue;
        const decl = findStructDecl(ctx.structs, branch.ty) orelse continue;
        if (findStructLayout(ctx.struct_layouts, branch.ty) == null and branch.payload_len != decl.fields.len) continue;
        if (findStructLayout(ctx.struct_layouts, branch.ty) != null and branch.payload_len != 1) continue;
        if (matched != null) return null;
        matched = .{ .branch = branch, .decl = decl };
    }
    return matched;
}

fn unionLocalSingleIdent(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
) ?UnionLocal {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.end != range.start + 1 or tokens[range.start].kind != .ident) return null;
    return findUnionLocal(locals.union_locals.items, tokens[range.start].lexeme);
}

fn trimTrailingComma(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    if (start_idx < end_idx and tokEq(tokens[end_idx - 1], ",")) return end_idx - 1;
    return end_idx;
}

fn fieldReflectionIfParts(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ?FieldReflectionIfParts {
    if (start_idx + 4 > end_idx) return null;
    if (!tokEq(tokens[start_idx], "if")) return null;
    const open_brace = findTopLevelBlockOpen(tokens, start_idx + 1, end_idx) orelse return null;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return null;
    var parts = FieldReflectionIfParts{
        .cond_start = start_idx + 1,
        .cond_end = open_brace,
        .then_start = open_brace + 1,
        .then_end = close_brace,
    };
    if (close_brace + 1 == end_idx) return parts;
    if (close_brace + 1 >= end_idx or !tokEq(tokens[close_brace + 1], "else")) return null;
    if (close_brace + 2 >= end_idx) return null;
    if (tokEq(tokens[close_brace + 2], "if")) {
        parts.else_if_start = close_brace + 2;
        return parts;
    }
    if (!tokEq(tokens[close_brace + 2], "{")) return null;
    const close_else = findMatchingInRange(tokens, close_brace + 2, "{", "}", end_idx) catch return null;
    if (close_else + 1 != end_idx) return null;
    parts.else_start = close_brace + 3;
    parts.else_end = close_else;
    return parts;
}

fn fieldStaticBoolExpr(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?bool {
    if (fieldStaticValue(tokens, start_idx, end_idx, locals, ctx)) |value| {
        return switch (value) {
            .bool => |b| b,
            else => null,
        };
    }

    const range = trimParens(tokens, start_idx, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return null;
    const call_name = tokens[call_head.name_idx].lexeme;
    if (call_head.is_intrinsic and std.mem.eql(u8, call_name, "not")) {
        const arg_end = findArgEnd(tokens, call_head.args_start, call_head.args_end);
        if (arg_end != call_head.args_end) return null;
        return !(fieldStaticBoolExpr(tokens, call_head.args_start, arg_end, locals, ctx) orelse return null);
    }
    if (call_head.is_intrinsic and (std.mem.eql(u8, call_name, "and") or std.mem.eql(u8, call_name, "or"))) {
        var arg_start = call_head.args_start;
        var saw_arg = false;
        while (arg_start < call_head.args_end) {
            const arg_end = findArgEnd(tokens, arg_start, call_head.args_end);
            const value = fieldStaticBoolExpr(tokens, arg_start, arg_end, locals, ctx) orelse return null;
            saw_arg = true;
            if (std.mem.eql(u8, call_name, "and") and !value) return false;
            if (std.mem.eql(u8, call_name, "or") and value) return true;
            arg_start = arg_end;
            if (arg_start < call_head.args_end and tokEq(tokens[arg_start], ",")) arg_start += 1;
        }
        if (!saw_arg) return null;
        return std.mem.eql(u8, call_name, "and");
    }
    if (call_head.is_intrinsic and (std.mem.eql(u8, call_name, "eq") or std.mem.eql(u8, call_name, "ne"))) {
        const first_end = findArgEnd(tokens, call_head.args_start, call_head.args_end);
        if (first_end >= call_head.args_end or !tokEq(tokens[first_end], ",")) return null;
        const second_start = first_end + 1;
        const second_end = findArgEnd(tokens, second_start, call_head.args_end);
        if (second_end != call_head.args_end) return null;
        const left = fieldStaticValue(tokens, call_head.args_start, first_end, locals, ctx) orelse return null;
        const right = fieldStaticValue(tokens, second_start, second_end, locals, ctx) orelse return null;
        const is_equal = fieldStaticValuesEqual(left, right);
        return if (std.mem.eql(u8, call_name, "eq")) is_equal else !is_equal;
    }
    return null;
}

fn fieldStaticValue(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?FieldStaticValue {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.start >= range.end) return null;

    if (range.end == range.start + 1) {
        const tok = tokens[range.start];
        if (tok.kind == .number) return .{ .int = std.fmt.parseUnsigned(usize, tok.lexeme, 10) catch return null };
        if (tok.kind == .string) return .{ .text = stringTokenBody(tok.lexeme) orelse return null };
        if (tokEq(tok, "true")) return .{ .bool = true };
        if (tokEq(tok, "false")) return .{ .bool = false };
        return null;
    }

    const call_head = exprCallHead(tokens, range) orelse return null;
    if (!call_head.is_intrinsic) return null;
    const call_name = tokens[call_head.name_idx].lexeme;
    if (std.mem.eql(u8, call_name, "field_name")) {
        const meta = singleFieldMetaArg(tokens, call_head.args_start, call_head.args_end, locals) orelse return null;
        const field = fieldFromMeta(ctx, meta) orelse return null;
        return .{ .text = publicDeclName(field.name) };
    }
    if (std.mem.eql(u8, call_name, "field_index")) {
        const meta = singleFieldMetaArg(tokens, call_head.args_start, call_head.args_end, locals) orelse return null;
        return .{ .int = meta.visible_index };
    }
    if (std.mem.eql(u8, call_name, "field_has_default")) {
        const meta = singleFieldMetaArg(tokens, call_head.args_start, call_head.args_end, locals) orelse return null;
        const field = fieldFromMeta(ctx, meta) orelse return null;
        return .{ .bool = field.default_start != null };
    }
    return null;
}

fn fieldStaticValuesEqual(left: FieldStaticValue, right: FieldStaticValue) bool {
    return switch (left) {
        .bool => |l| switch (right) {
            .bool => |r| l == r,
            else => false,
        },
        .int => |l| switch (right) {
            .int => |r| l == r,
            else => false,
        },
        .text => |l| switch (right) {
            .text => |r| std.mem.eql(u8, l, r),
            else => false,
        },
    };
}

fn singleFieldMetaArg(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
) ?FieldMetaLocal {
    const arg_end = findArgEnd(tokens, start_idx, end_idx);
    if (arg_end != end_idx) return null;
    const range = trimParens(tokens, start_idx, arg_end);
    if (range.end != range.start + 1) return null;
    if (tokens[range.start].kind != .ident) return null;
    return findFieldMetaLocal(locals.field_meta_locals.items, tokens[range.start].lexeme);
}

fn findFieldMetaLocal(locals: []const FieldMetaLocal, name: []const u8) ?FieldMetaLocal {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (std.mem.eql(u8, local.name, name)) return local;
    }
    return null;
}

fn fieldFromMeta(ctx: CodegenContext, meta: FieldMetaLocal) ?StructField {
    const decl = findStructDecl(ctx.structs, meta.struct_name) orelse return null;
    if (meta.decl_index >= decl.fields.len) return null;
    return decl.fields[meta.decl_index];
}

fn fieldVisibleFromTokens(field: StructField, decl: StructDecl, tokens: []const lexer.Token) bool {
    if (!isPrivateFieldName(field.name)) return true;
    return moduleTokensEqual(decl.tokens, tokens);
}

fn isPrivateFieldName(name: []const u8) bool {
    return name.len > 1 and name[0] == '.';
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

    // Prefer canonical WIT signature for known targets so do-side sugar still lowers.
    if (knownWasiWitSignature(target)) |wit| {
        return .{
            .source = source,
            .alias = alias,
            .target = target,
            .params = try allocator.dupe(u8, wit.params),
            .result = try allocator.dupe(u8, wit.result),
        };
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
            if (findImportedModuleIndex(allocator, graph, visit.module_idx, import_ref)) |child_idx| {
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
        const call_head = callHeadAt(tokens, i, end_idx) orelse continue;
        try collectCallNamesInRange(allocator, tokens, module_idx, call_head.args_start, call_head.args_end, out);
        if (!call_head.is_intrinsic and !isLoopSourceSpecialCallName(tokens[call_head.name_idx].lexeme)) {
            try pushReachVisit(allocator, out, .{
                .module_idx = module_idx,
                .name = tokens[call_head.name_idx].lexeme,
                .call_idx = call_head.name_idx,
            });
        }
        i = call_head.args_end;
    }
}

fn isLoopSourceSpecialCallName(name: []const u8) bool {
    return std.mem.eql(u8, name, "fields") or std.mem.eql(u8, name, "recv");
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

fn importedScalarConst(ctx: CodegenContext, tokens: []const lexer.Token, alias: []const u8) ?ImportedScalarConst {
    const import_ctx = importedAliasContextForTokens(ctx.imported_alias_ctx, tokens) orelse return null;
    const import_ref = findCodegenImportByAlias(tokens, alias) orelse return null;
    const child_idx = findImportedModuleIndexNoAlloc(import_ctx.graph, import_ctx.module_idx, import_ref) orelse return null;
    return localScalarConst(import_ctx.graph.modules[child_idx].tokens, import_ref.target);
}

fn findImportedModuleIndexNoAlloc(
    graph: *const imports.ModuleGraph,
    current_idx: usize,
    import_ref: CodegenImportRef,
) ?usize {
    for (graph.modules, 0..) |module, idx| {
        if (moduleMatchesImportPath(graph, current_idx, module.path, import_ref)) return idx;
    }
    return null;
}

fn moduleMatchesImportPath(
    graph: *const imports.ModuleGraph,
    current_idx: usize,
    path: []const u8,
    import_ref: CodegenImportRef,
) bool {
    return switch (import_ref.prefix) {
        .std => pathHasBaseAndFile(path, "lib", import_ref.file_path),
        .dep => pathHasBaseAndFile(path, graph.dep_root, import_ref.file_path),
        .local => pathHasBaseAndFile(path, std.fs.path.dirname(graph.modules[current_idx].path) orelse ".", import_ref.file_path),
    };
}

fn pathHasBaseAndFile(path: []const u8, base: []const u8, file_path: []const u8) bool {
    if (std.mem.eql(u8, base, ".")) return std.mem.eql(u8, path, file_path) or pathHasBaseAndFile(path, "", file_path);
    if (base.len == 0) return std.mem.eql(u8, path, file_path);
    if (!std.mem.startsWith(u8, path, base)) return false;
    if (path.len != base.len + 1 + file_path.len) return false;
    if (path[base.len] != '/') return false;
    return std.mem.eql(u8, path[base.len + 1 ..], file_path);
}

fn localScalarConst(tokens: []const lexer.Token, name: []const u8) ?ImportedScalarConst {
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
        if (!isLineStart(tokens, i)) continue;
        if (tokens[i].kind != .ident or !std.mem.eql(u8, tokens[i].lexeme, name)) continue;
        if (tokens[i + 1].kind != .ident or !isCoreWasmScalar(tokens[i + 1].lexeme)) return null;
        if (!tokEq(tokens[i + 2], "=")) return null;
        const line_end = findLineEnd(tokens, i);
        if (i + 4 != line_end) return null;
        const value = tokens[i + 3];
        if (value.kind != .number) return null;
        return .{ .ty = tokens[i + 1].lexeme, .value = value.lexeme };
    }
    return null;
}

fn findImportedModuleIndex(
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
            return findModuleByPath(modules, resolved);
        },
        .std => {
            const resolved = std.fs.path.join(allocator, &.{ "lib", import_ref.file_path }) catch return null;
            defer allocator.free(resolved);
            return findModuleByPath(modules, resolved);
        },
        .dep => {
            const resolved = std.fs.path.join(allocator, &.{ graph.dep_root, import_ref.file_path }) catch return null;
            defer allocator.free(resolved);
            return findModuleByPath(modules, resolved);
        },
    }
}

fn findModuleByPath(modules: []const imports.ModuleRecord, path: []const u8) ?usize {
    for (modules, 0..) |module, idx| {
        if (std.mem.eql(u8, module.path, path)) return idx;
    }
    return null;
}

fn publicDeclName(name: []const u8) []const u8 {
    if (name.len > 1 and name[0] == '.') return name[1..];
    return name;
}

fn isPublicTypeName(name: []const u8) bool {
    return name.len != 0 and std.ascii.isUpper(name[0]);
}

fn isErrorTypeName(name: []const u8) bool {
    return std.mem.eql(u8, name, "Error") or std.mem.endsWith(u8, name, "Error");
}

fn isBaseIntTypeName(name: []const u8) bool {
    return std.mem.eql(u8, name, "i8") or
        std.mem.eql(u8, name, "i16") or
        std.mem.eql(u8, name, "i32") or
        std.mem.eql(u8, name, "i64") or
        std.mem.eql(u8, name, "u8") or
        std.mem.eql(u8, name, "u16") or
        std.mem.eql(u8, name, "u32") or
        std.mem.eql(u8, name, "u64") or
        std.mem.eql(u8, name, "isize") or
        std.mem.eql(u8, name, "usize");
}

fn isValueEnumDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 2 < tokens.len and
        isLineStart(tokens, idx) and
        tokens[idx].kind == .ident and
        isPublicTypeName(publicDeclName(tokens[idx].lexeme)) and
        !isErrorTypeName(publicDeclName(tokens[idx].lexeme)) and
        isBaseIntTypeName(tokens[idx + 1].lexeme) and
        tokEq(tokens[idx + 2], "=");
}

fn findValueEnumDecl(value_enums: []const ValueEnumDecl, name: []const u8) ?ValueEnumDecl {
    for (value_enums) |decl| {
        if (std.mem.eql(u8, decl.name, name)) return decl;
    }
    return null;
}

fn findValueEnumDeclLineByName(tokens: []const lexer.Token, name: []const u8) ?usize {
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
        if (std.mem.eql(u8, publicDeclName(tokens[i].lexeme), name)) return i;
        i = findLineEnd(tokens, i) - 1;
    }
    return null;
}

fn findValueEnumDeclLineByBranch(tokens: []const lexer.Token, branch_name: []const u8) ?usize {
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
        if (valueEnumLineHasBranch(tokens, i, branch_name)) return i;
        i = findLineEnd(tokens, i) - 1;
    }
    return null;
}

fn valueEnumLineHasBranch(tokens: []const lexer.Token, enum_idx: usize, branch_name: []const u8) bool {
    const line_end = findLineEnd(tokens, enum_idx);
    var j = enum_idx + 3;
    while (j + 3 < line_end) {
        if (tokEq(tokens[j], "|")) {
            j += 1;
            continue;
        }
        if (tokens[j].kind == .ident and std.mem.eql(u8, publicDeclName(tokens[j].lexeme), branch_name)) return true;
        j += 4;
    }
    return false;
}

fn isCoreWasmCallName(name: []const u8) bool {
    return std.mem.eql(u8, name, "is") or
        std.mem.eql(u8, name, "as") or
        isBoolSpecialFuncName(name) or
        isNumericCoreFuncName(name) or
        isNumericUnarySelectCoreFuncName(name) or
        isNumericBinarySelectCoreFuncName(name) or
        isComparisonCoreFuncName(name) or
        std.mem.eql(u8, name, "get") or
        std.mem.eql(u8, name, "set") or
        std.mem.eql(u8, name, "field_name") or
        std.mem.eql(u8, name, "field_index") or
        std.mem.eql(u8, name, "field_has_default") or
        std.mem.eql(u8, name, "field_get") or
        std.mem.eql(u8, name, "field_set") or
        std.mem.eql(u8, name, "len") or
        std.mem.eql(u8, name, "put") or
        isMemoryLoadName(name) or
        isBitwiseCoreFuncName(name) or
        isCountBitsCoreFuncName(name) or
        isFloatUnaryCoreFuncName(name) or
        isFloatBinaryCoreFuncName(name);
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

fn collectStringDataForStructFieldNames(
    allocator: std.mem.Allocator,
    structs: []const StructDecl,
    out: *StringDataContext,
) !void {
    for (structs) |decl| {
        for (decl.fields) |field| {
            const field_name = publicDeclName(field.name);
            _ = try out.internRaw(allocator, field_name, field_name);
        }
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
        if (isUserFuncDeclStart(tokens, i)) {
            pending_type_params.clearRetainingCapacity();
            const close_params = findMatching(tokens, i + 1, "(", ")") catch continue;
            const body = parseFuncBodyShape(tokens, close_params) catch continue;
            i = body.next_idx;
            continue;
        }
        // Declarative: Name = @wasi_resource|wasi_record("…", { fields })
        if (isWasiStructBindingStructStart(tokens, i)) {
            const close_call = findMatching(tokens, i + 4, "(", ")") catch continue;
            var brace_open: ?usize = null;
            var j = i + 5;
            while (j < close_call) : (j += 1) {
                if (tokEq(tokens[j], "{")) {
                    brace_open = j;
                    break;
                }
            }
            const open_brace = brace_open orelse continue;
            const close_brace = findMatching(tokens, open_brace, "{", "}") catch continue;
            var fields = std.ArrayList(StructField).empty;
            var owned_types = std.ArrayList([]const u8).empty;
            errdefer {
                for (owned_types.items) |owned| allocator.free(owned);
                owned_types.deinit(allocator);
                fields.deinit(allocator);
            }
            try appendStructFieldsInBraceRange(allocator, tokens, open_brace, close_brace, &fields, &owned_types);
            try out.append(allocator, .{
                .name = tokens[i].lexeme,
                .type_params = &[_][]const u8{},
                .fields = try fields.toOwnedSlice(allocator),
                .layout_source = null,
                .owned_types = try owned_types.toOwnedSlice(allocator),
                .tokens = tokens,
            });
            pending_type_params.clearRetainingCapacity();
            i = close_call;
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

        try appendStructFieldsInBraceRange(allocator, tokens, open_brace, close_brace, &fields, &owned_types);

        try out.append(allocator, .{
            .name = tokens[i].lexeme,
            .type_params = type_params,
            .fields = try fields.toOwnedSlice(allocator),
            .layout_source = null,
            .owned_types = try owned_types.toOwnedSlice(allocator),
            .tokens = tokens,
        });
        type_params_owned = false;
        pending_type_params.clearRetainingCapacity();
        i = close_brace;
    }
}

fn isWasiStructBindingStructStart(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 5 >= tokens.len) return false;
    if (!isLineStart(tokens, idx)) return false;
    if (tokens[idx].kind != .ident) return false;
    if (!tokEq(tokens[idx + 1], "=")) return false;
    if (!tokEq(tokens[idx + 2], "@")) return false;
    if (tokens[idx + 3].kind != .ident) return false;
    const kind = tokens[idx + 3].lexeme;
    if (!std.mem.eql(u8, kind, "wasi_resource") and !std.mem.eql(u8, kind, "wasi_record")) return false;
    return tokEq(tokens[idx + 4], "(");
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

        const child_idx = findImportedModuleIndex(allocator, graph, root_idx, import_ref) orelse continue;
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
        if (isUserFuncDeclStart(tokens, i)) {
            pending_type_params.clearRetainingCapacity();
            const close_params = findMatching(tokens, i + 1, "(", ")") catch continue;
            const body = parseFuncBodyShape(tokens, close_params) catch continue;
            i = body.next_idx;
            continue;
        }
        if (!isTopLevelStructDeclStart(tokens, i)) continue;
        const open_brace = i + 1;
        const close_brace = try findMatching(tokens, open_brace, "{", "}");
        if (!std.mem.eql(u8, publicDeclName(tokens[i].lexeme), target_name)) {
            pending_type_params.clearRetainingCapacity();
            i = close_brace;
            continue;
        }
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

        try appendStructFieldsInBraceRange(allocator, tokens, open_brace, close_brace, &fields, &owned_types);

        try out.append(allocator, .{
            .name = emit_name,
            .type_params = type_params,
            .fields = try fields.toOwnedSlice(allocator),
            .layout_source = layout_source,
            .owned_types = try owned_types.toOwnedSlice(allocator),
            .tokens = tokens,
        });
        type_params_owned = false;
        return true;
    }
    return false;
}

/// Collect struct fields inside `{ … }`. Clamps each field span to `close_brace` so
/// single-line bodies like `{ .id i64 }` do not include trailing `}` / `)` in the type span.
fn appendStructFieldsInBraceRange(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    open_brace: usize,
    close_brace: usize,
    fields: *std.ArrayList(StructField),
    owned_types: *std.ArrayList([]const u8),
) !void {
    var field_idx = open_brace + 1;
    while (field_idx < close_brace) {
        // Never scan past the closing brace — single-line `{ .id i64 }` would otherwise
        // treat `} )` as part of the field type and drop the field.
        const line_end = @min(findLineEnd(tokens, field_idx), close_brace);
        const default_idx = findTopLevelToken(tokens, field_idx + 1, line_end, "=");
        const type_end = default_idx orelse line_end;
        if (tokens[field_idx].kind == .ident) {
            if (try parseStructFieldTypeExpr(allocator, tokens, field_idx + 1, type_end, owned_types)) |parsed_ty| {
                try fields.append(allocator, .{
                    .name = tokens[field_idx].lexeme,
                    .ty = parsed_ty,
                    .default_start = if (default_idx) |idx| idx + 1 else null,
                    .default_end = line_end,
                });
            }
        }
        field_idx = line_end;
    }
}

fn collectValueEnumDecls(
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

fn collectImportedValueEnumDecls(
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

fn collectValueEnumDeclByNameAs(
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
            if (try fieldTypeHasManagedLayout(allocator, structs, field.ty)) {
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

fn collectConcreteGenericStructLayouts(
    allocator: std.mem.Allocator,
    structs: []const StructDecl,
    functions: []const FuncDecl,
    out: *std.ArrayList(StructLayout),
) !void {
    var next_type_id = nextStructLayoutTypeId(out.items);
    for (functions) |func| {
        if (func.is_generic_template) continue;
        for (func.params) |param| {
            try collectConcreteGenericStructLayoutFromType(allocator, structs, funcParamAbiType(param), out, &next_type_id);
        }
        for (func.results) |result_ty| {
            try collectConcreteGenericStructLayoutFromType(allocator, structs, result_ty, out, &next_type_id);
        }
        for (func.result_items) |item| {
            try collectConcreteGenericStructLayoutFromType(allocator, structs, item.ty, out, &next_type_id);
        }
    }
}

/// Register scheme-A packed `[Tuple<...>]` layouts when any leaf is managed payload.
/// Layout name is the element Tuple type; payload_bytes is packed element width; managed offsets relative to element start.
fn collectStoragePackLayoutsFromTokens(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    structs: []const StructDecl,
    out: *std.ArrayList(StructLayout),
) !void {
    var owned = std.ArrayList([]const u8).empty;
    defer {
        for (owned.items) |n| allocator.free(n);
        owned.deinit(allocator);
    }
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tokEq(tokens[i], "[")) continue;
        const close = findMatchingInRange(tokens, i, "[", "]", tokens.len) catch continue;
        if (close <= i + 1) continue;
        const parsed = (try parseCodegenTypeExpr(allocator, tokens, i + 1, close, &owned)) orelse continue;
        if (parsed.next_idx != close) continue;
        try ensureStoragePackLayoutWithStructs(allocator, parsed.ty, structs, out);
    }
}

fn ensureStoragePackLayout(
    allocator: std.mem.Allocator,
    elem_ty: []const u8,
    out: *std.ArrayList(StructLayout),
) !void {
    // Pure-scalar struct slots need structs table; managed-only path uses type_name flatten.
    try ensureStoragePackLayoutWithStructs(allocator, elem_ty, &.{}, out);
}

fn ensureStoragePackLayoutWithStructs(
    allocator: std.mem.Allocator,
    elem_ty: []const u8,
    structs: []const StructDecl,
    out: *std.ArrayList(StructLayout),
) !void {
    if (!isTupleTypeName(elem_ty)) return;
    const width = if (structs.len != 0)
        tuplePackWidthWithStructs(elem_ty, structs)
    else
        tupleScalarLeafStorageByteWidth(elem_ty);
    const w = width orelse return;

    var leaf_types = std.ArrayList([]const u8).empty;
    defer leaf_types.deinit(allocator);
    if (structs.len != 0) {
        try appendTupleLeafTypesWithStructs(allocator, elem_ty, structs, &leaf_types);
    } else {
        try appendTupleLeafTypes(allocator, elem_ty, &leaf_types);
    }

    var managed_fields = std.ArrayList(ManagedFieldOffset).empty;
    errdefer managed_fields.deinit(allocator);
    var offset: usize = 0;
    var managed_idx: usize = 0;
    for (leaf_types.items) |leaf_ty| {
        const leaf_bytes = leafPayloadBytesForPack(leaf_ty, structs) orelse return;
        if (isPackManagedHandleLeaf(leaf_ty, structs)) {
            try managed_fields.append(allocator, .{
                .name = managedLeafFieldName(managed_idx),
                .offset = offset,
            });
            managed_idx += 1;
        }
        offset += leaf_bytes;
    }
    if (managed_fields.items.len == 0) {
        managed_fields.deinit(allocator);
        return;
    }
    if (findStructLayoutExact(out.items, elem_ty)) |existing| {
        if (existing.is_storage_pack) {
            managed_fields.deinit(allocator);
            return;
        }
    }

    const owned_name = try allocator.dupe(u8, elem_ty);
    errdefer allocator.free(owned_name);
    try out.append(allocator, .{
        .name = owned_name,
        .type_id = nextStructLayoutTypeId(out.items),
        .payload_bytes = w,
        .managed_fields = try managed_fields.toOwnedSlice(allocator),
        .owned_name = true,
        .is_storage_pack = true,
    });
}

fn managedLeafFieldName(idx: usize) []const u8 {
    return switch (idx) {
        0 => "m0",
        1 => "m1",
        2 => "m2",
        3 => "m3",
        4 => "m4",
        5 => "m5",
        6 => "m6",
        7 => "m7",
        else => "mN",
    };
}

fn nextStructLayoutTypeId(layouts: []const StructLayout) usize {
    var next_type_id: usize = TYPE_ID_FIRST_STRUCT;
    for (layouts) |layout| {
        next_type_id = @max(next_type_id, layout.type_id + 1);
    }
    return next_type_id;
}

fn collectConcreteGenericStructLayoutFromType(
    allocator: std.mem.Allocator,
    structs: []const StructDecl,
    ty: []const u8,
    out: *std.ArrayList(StructLayout),
    next_type_id: *usize,
) !void {
    if (managedPayloadElemTypeFromName(ty)) |elem_ty| {
        try collectConcreteGenericStructLayoutFromType(allocator, structs, elem_ty, out, next_type_id);
        return;
    }

    const args = genericTypeArgsRange(ty) orelse return;
    const decl = findStructDecl(structs, args.base) orelse return;
    if (decl.type_params.len == 0) return;
    if (findStructLayoutExact(out.items, ty) != null) return;
    if (findStructLayoutExact(out.items, args.base) != null) return;

    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    var bindings = std.ArrayList(GenericTypeBinding).empty;
    defer bindings.deinit(allocator);
    if (!try bindStructTypeArgs(allocator, decl, ty, &bindings, &owned_types)) return;

    var managed_fields = std.ArrayList(ManagedFieldOffset).empty;
    errdefer managed_fields.deinit(allocator);
    var offset: usize = 0;
    for (decl.fields) |field| {
        const field_ty = try substituteGenericTypeOwned(allocator, field.ty, bindings.items, &owned_types);
        try collectConcreteGenericStructLayoutFromType(allocator, structs, field_ty, out, next_type_id);

        const field_align = typePayloadAlignment(field_ty);
        offset = alignUp(offset, field_align);
        if (fieldConcreteTypeHasManagedLayout(out.items, field_ty)) {
            try managed_fields.append(allocator, .{
                .name = publicDeclName(field.name),
                .offset = offset,
            });
        }
        offset += typePayloadBytes(field_ty);
    }

    if (managed_fields.items.len == 0) {
        managed_fields.deinit(allocator);
        return;
    }

    const owned_name = try allocator.dupe(u8, ty);
    errdefer allocator.free(owned_name);
    try out.append(allocator, .{
        .name = owned_name,
        .type_id = next_type_id.*,
        .payload_bytes = alignUp(offset, 4),
        .managed_fields = try managed_fields.toOwnedSlice(allocator),
        .owned_name = true,
    });
    next_type_id.* += 1;
}

fn fieldConcreteTypeHasManagedLayout(layouts: []const StructLayout, ty: []const u8) bool {
    if (isManagedPayloadType(ty)) return true;
    return findStructLayout(layouts, ty) != null;
}

fn fieldTypeHasManagedLayout(allocator: std.mem.Allocator, structs: []const StructDecl, ty: []const u8) !bool {
    if (isManagedPayloadType(ty)) return true;
    var stack = std.ArrayList([]const u8).empty;
    defer stack.deinit(allocator);
    return try structTypeHasManagedLayout(allocator, structs, ty, &stack);
}

fn structTypeHasManagedLayout(
    allocator: std.mem.Allocator,
    structs: []const StructDecl,
    ty: []const u8,
    stack: *std.ArrayList([]const u8),
) !bool {
    const name = typeBaseName(ty);
    if (hasTypeName(stack.items, name)) return true;
    const decl = findStructDecl(structs, name) orelse return false;

    try stack.append(allocator, name);
    defer _ = stack.pop();

    for (decl.fields) |field| {
        if (isManagedPayloadType(field.ty)) return true;
        if (try structTypeHasManagedLayout(allocator, structs, field.ty, stack)) return true;
    }
    return false;
}

fn hasTypeName(names: []const []const u8, needle: []const u8) bool {
    for (names) |name| {
        if (std.mem.eql(u8, name, needle)) return true;
    }
    return false;
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

fn parseStructFieldTypeExpr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    owned_types: *std.ArrayList([]const u8),
) !?[]const u8 {
    if (start_idx >= end_idx) return null;
    if (hasTopLevelToken(tokens, start_idx, end_idx, "|")) {
        const ty = try compactTokenText(allocator, tokens, start_idx, end_idx);
        errdefer allocator.free(ty);
        try owned_types.append(allocator, ty);
        return ty;
    }
    const parsed = (try parseCodegenTypeExpr(allocator, tokens, start_idx, end_idx, owned_types)) orelse return null;
    if (parsed.next_idx != end_idx) return null;
    return parsed.ty;
}

fn parseFuncParamTypeExpr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    owned_types: *std.ArrayList([]const u8),
) !?ParsedCodegenType {
    if (start_idx >= end_idx) return null;
    if (hasTopLevelToken(tokens, start_idx, end_idx, "|")) {
        const ty = try compactTokenText(allocator, tokens, start_idx, end_idx);
        errdefer allocator.free(ty);
        try owned_types.append(allocator, ty);
        return .{ .ty = ty, .next_idx = end_idx };
    }
    return parseCodegenTypeExpr(allocator, tokens, start_idx, end_idx, owned_types);
}

fn isArrowAt(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 1 < tokens.len and tokEq(tokens[idx], "=") and tokEq(tokens[idx + 1], ">");
}

fn isReturnArrowAt(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 1 < tokens.len and tokEq(tokens[idx], "-") and tokEq(tokens[idx + 1], ">");
}

fn findConstraintBlockStartBefore(tokens: []const lexer.Token, decl_start_idx: usize) ?usize {
    if (decl_start_idx == 0 or decl_start_idx >= tokens.len) return null;

    var scan_idx = decl_start_idx;
    var expected_line = tokens[decl_start_idx].line;
    var block_start: ?usize = null;
    while (scan_idx > 0) {
        const prev_idx = scan_idx - 1;
        const prev_line = tokens[prev_idx].line;
        if (prev_line + 1 != expected_line) break;

        const line_start = findLineStart(tokens, prev_idx);
        if (!tokEq(tokens[line_start], "#")) break;

        block_start = line_start;
        scan_idx = line_start;
        expected_line = prev_line;
    }
    return block_start;
}

fn findLineEndIdx(tokens: []const lexer.Token, start_idx: usize) usize {
    return findLineEnd(tokens, start_idx);
}

fn findTopLevelAssignEqOnLine(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
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
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tokEq(tokens[i], "=")) return i;
    }
    return null;
}

fn simpleTypeName(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    if (start_idx + 1 != end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    return tokens[start_idx].lexeme;
}

fn isTopLevelCommaAny(tokens: []const lexer.Token, idx: usize, start_idx: usize, end_idx: usize) bool {
    if (!tokEq(tokens[idx], ",")) return false;

    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < idx and i < end_idx) : (i += 1) {
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
    }
    return depth_paren == 0 and depth_brace == 0 and depth_angle == 0;
}

fn parseTypeNameList(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ![]?[]const u8 {
    var out = std.ArrayList(?[]const u8).empty;
    errdefer out.deinit(allocator);

    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !isTopLevelCommaAny(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            try out.append(allocator, simpleTypeName(tokens, seg_start, i));
        }
        seg_start = i + 1;
    }
    return out.toOwnedSlice(allocator);
}

fn parseFuncTypeConstraintShape(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    func_start_idx: usize,
    constraint_name: []const u8,
) !?OwnedFuncTypeShape {
    const block_start = findConstraintBlockStartBefore(tokens, func_start_idx) orelse return null;

    var i = block_start;
    while (i < func_start_idx) {
        if (!tokEq(tokens[i], "#")) {
            i += 1;
            continue;
        }
        const line_end = findLineEndIdx(tokens, i);
        const is_func_constraint = i + 2 < line_end and tokEq(tokens[i + 2], "(");
        if (is_func_constraint or i + 1 >= line_end or !std.mem.eql(u8, tokens[i + 1].lexeme, constraint_name)) {
            i = line_end;
            continue;
        }

        const eq_idx = findTopLevelAssignEqOnLine(tokens, i + 2, line_end) orelse return null;
        if (!isFuncTypeRange(tokens, eq_idx + 1, line_end)) return null;
        const close_params = findMatching(tokens, eq_idx + 1, "(", ")") catch return null;
        const param_types = try parseTypeNameList(allocator, tokens, eq_idx + 2, close_params);
        return .{
            .shape = .{
                .param_types = param_types,
                .return_type = simpleTypeName(tokens, close_params + 3, line_end),
            },
            .owned = true,
        };
    }
    return null;
}

fn isFuncTypeRange(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx >= end_idx or !tokEq(tokens[start_idx], "(")) return false;
    const close_idx = findMatching(tokens, start_idx, "(", ")") catch return false;
    return close_idx + 2 < end_idx and isReturnArrowAt(tokens, close_idx + 1);
}

fn lambdaBodyStart(tokens: []const lexer.Token, start_idx: usize, limit_idx: usize) ?usize {
    if (isArrowAt(tokens, start_idx)) return start_idx + 2;
    if (start_idx < limit_idx and tokEq(tokens[start_idx], "{")) return start_idx;
    if (start_idx >= limit_idx or !isReturnArrowAt(tokens, start_idx)) return null;

    var i = start_idx + 2;
    var depth_angle: usize = 0;
    var depth_paren: usize = 0;
    while (i < limit_idx) : (i += 1) {
        if (tokEq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tokEq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (tokEq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tokEq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (depth_angle == 0 and depth_paren == 0 and isArrowAt(tokens, i)) return i + 2;
        if (depth_angle == 0 and depth_paren == 0 and tokEq(tokens[i], "{")) return i;
    }
    return null;
}

fn lambdaExprShape(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?LambdaExprShape {
    const range = trimParens(tokens, start_idx, end_idx);
    if (range.start >= range.end or !tokEq(tokens[range.start], "(")) return null;
    const close_params = findMatchingInRange(tokens, range.start, "(", ")", range.end) catch return null;
    const body_start = lambdaBodyStart(tokens, close_params + 1, range.end) orelse return null;
    if (body_start >= range.end) return null;
    if (tokEq(tokens[body_start], "{")) {
        const close_block = findMatchingInRange(tokens, body_start, "{", "}", range.end) catch return null;
        if (close_block + 1 != range.end) return null;
        return .{
            .open_params = range.start,
            .close_params = close_params,
            .body_start = body_start + 1,
            .body_end = close_block,
            .is_block = true,
        };
    }
    return .{
        .open_params = range.start,
        .close_params = close_params,
        .body_start = body_start,
        .body_end = range.end,
        .is_block = false,
    };
}

fn parseLambdaParamNames(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ![]const []const u8 {
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

fn lambdaParamTypeName(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    if (start_idx + 1 >= end_idx) return null;
    return simpleTypeName(tokens, start_idx + 1, end_idx);
}

fn parseLambdaParamTypes(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ![]?[]const u8 {
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

fn explicitLambdaTypesMatch(target_types: []const ?[]const u8, lambda_types: []const ?[]const u8) bool {
    if (target_types.len != lambda_types.len) return false;
    for (lambda_types, 0..) |lambda_type, idx| {
        const expected = lambda_type orelse continue;
        const actual = target_types[idx] orelse return false;
        if (!std.mem.eql(u8, actual, expected)) return false;
    }
    return true;
}

fn lambdaExplicitReturnType(tokens: []const lexer.Token, lambda: LambdaExprShape) ?[]const u8 {
    if (!isReturnArrowAt(tokens, lambda.close_params + 1)) return null;
    const ret_start = lambda.close_params + 3;
    const ret_end = if (lambda.is_block) lambda.body_start - 1 else lambda.body_start - 2;
    if (ret_start >= ret_end) return null;
    return simpleTypeName(tokens, ret_start, ret_end);
}

fn appendTypedLocalWithDecl(
    allocator: std.mem.Allocator,
    locals: *LocalSet,
    name: []const u8,
    ty: []const u8,
    ctx: CodegenContext,
    emit_decl: bool,
) !void {
    if (managedPayloadElemTypeFromName(ty)) |elem_ty| {
        try locals.appendBorrowedLocal(allocator, name, ty, emit_decl);
        try locals.storage_locals.append(allocator, .{
            .name = name,
            .ty = ty,
            .elem_ty = elem_ty,
        });
        return;
    }

    if (findStructDecl(ctx.structs, ty)) |decl| {
        try locals.struct_locals.append(allocator, .{
            .name = name,
            .ty = ty,
        });
        if (findStructLayout(ctx.struct_layouts, ty) != null) {
            try locals.appendBorrowedLocal(allocator, name, ty, emit_decl);
            for (decl.fields) |field| {
                const field_ty = try substituteStructFieldType(allocator, decl, ty, field.ty, &locals.owned_names);
                try appendManagedStructFieldMetaLocal(allocator, locals, name, field.name, field_ty);
            }
            return;
        }
        for (decl.fields) |field| {
            const field_ty = try substituteStructFieldType(allocator, decl, ty, field.ty, &locals.owned_names);
            try appendBorrowedLocalField(allocator, locals, ctx.entry_tokens, ctx, name, field.name, field_ty);
        }
        return;
    }

    try locals.appendBorrowedLocal(allocator, name, ty, emit_decl);
}

fn appendTypedLocal(
    allocator: std.mem.Allocator,
    locals: *LocalSet,
    name: []const u8,
    ty: []const u8,
    ctx: CodegenContext,
) !void {
    return appendTypedLocalWithDecl(allocator, locals, name, ty, ctx, false);
}

fn inferLambdaExprReturnType(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    lambda: LambdaExprShape,
    shape: FuncTypeShape,
    locals: *const LocalSet,
    ctx: CodegenContext,
) !?[]const u8 {
    if (lambda.close_params + 1 < tokens.len and isReturnArrowAt(tokens, lambda.close_params + 1)) {
        return lambdaExplicitReturnType(tokens, lambda);
    }
    if (lambda.is_block) return "nil";
    if (shape.param_types.len == 0) {
        return inferExprType(tokens, lambda.body_start, lambda.body_end, locals, ctx);
    }

    var lambda_locals = try cloneLocalSet(allocator, locals);
    defer lambda_locals.deinit(allocator);

    var seg_start = lambda.open_params + 1;
    var seg_idx: usize = 0;
    var i = lambda.open_params + 1;
    while (i <= lambda.close_params) : (i += 1) {
        if (i < lambda.close_params and !isTopLevelCommaAny(tokens, i, lambda.open_params + 1, lambda.close_params)) continue;
        if (seg_start < i) {
            if (seg_idx >= shape.param_types.len) return null;
            const param_ty = shape.param_types[seg_idx] orelse return null;
            if (tokens[seg_start].kind != .ident) return null;
            try appendTypedLocal(allocator, &lambda_locals, tokens[seg_start].lexeme, param_ty, ctx);
            seg_idx += 1;
        }
        seg_start = i + 1;
    }
    if (seg_idx != shape.param_types.len) return null;
    return inferExprType(tokens, lambda.body_start, lambda.body_end, &lambda_locals, ctx);
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
        const parsed_results = (try parseFuncDeclResultTypes(
            allocator,
            tokens,
            body.result_start,
            body.result_end,
            type_params,
            structs,
            struct_layouts,
            imported_alias_ctx,
            &owned_types,
        )) orelse continue;
        const results = parsed_results.types;
        var results_owned = true;
        errdefer if (results_owned) allocator.free(results);
        const result_items = parsed_results.items;
        var result_items_owned = parsed_results.owns_items;
        errdefer if (result_items_owned) allocator.free(result_items);

        var params = std.ArrayList(FuncParam).empty;
        errdefer {
            for (params.items) |param| {
                if (param.callback) |callback| {
                    if (callback.owned) allocator.free(callback.shape.param_types);
                }
            }
            params.deinit(allocator);
        }
        var param_idx = open_params + 1;
        while (param_idx < close_params) {
            if (tokEq(tokens[param_idx], ",")) {
                param_idx += 1;
                continue;
            }
            if (tokens[param_idx].kind != .ident) return error.InvalidParamName;
            const param_end = findArgEnd(tokens, param_idx, close_params);
            if (param_end == param_idx + 1) {
                if (type_params.len == 0) return error.InvalidParamName;
                try params.append(allocator, .{
                    .name = tokens[param_idx].lexeme,
                    .ty = "",
                });
                param_idx = param_end;
                if (param_idx < close_params and tokEq(tokens[param_idx], ",")) param_idx += 1;
                continue;
            }
            var type_start = param_idx + 1;
            var variadic = false;
            if (type_start < close_params and tokEq(tokens[type_start], "...")) {
                variadic = true;
                type_start += 1;
            }
            const parsed_ty = (try parseFuncParamTypeExpr(allocator, tokens, type_start, param_end, &owned_types)) orelse return error.InvalidParamName;
            const callback = try parseFuncTypeConstraintShape(allocator, tokens, i, parsed_ty.ty);
            try params.append(allocator, .{
                .name = tokens[param_idx].lexeme,
                .ty = parsed_ty.ty,
                .variadic = variadic,
                .callback = callback,
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
            .result_items = result_items,
            .result_struct = parsed_results.result_struct,
            .result_union = parsed_results.result_union,
            .type_params = type_params,
            .is_generic_template = type_params.len != 0,
            .owned_types = try owned_types.toOwnedSlice(allocator),
            .tokens = tokens,
            .start_idx = i,
            .arrow = body.arrow,
            .body_start = body.body_start,
            .body_end = body.body_end,
        });
        results_owned = false;
        result_items_owned = false;
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
            const child_idx = findImportedModuleIndex(allocator, graph, visit.module_idx, import_ref) orelse continue;
            if (findFuncDecl(out.items, import_ref.alias) == null) {
                _ = try collectFuncDeclByNameAs(
                    allocator,
                    graph.modules[child_idx].tokens,
                    structs,
                    struct_layouts,
                    .{ .graph = graph, .module_idx = child_idx },
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
            defer allocator.free(emit_name);
            _ = try collectFuncDeclByNameAs(
                allocator,
                module.tokens,
                structs,
                struct_layouts,
                .{ .graph = graph, .module_idx = visit.module_idx },
                publicDeclName(visit.name),
                emit_name,
                true,
                out,
            );
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
            const child_idx = findImportedModuleIndex(allocator, graph, visit.module_idx, import_ref) orelse continue;
            if (findFuncDecl(out.items, import_ref.alias) == null) {
                _ = try collectFuncDeclByNameAs(
                    allocator,
                    graph.modules[child_idx].tokens,
                    structs,
                    struct_layouts,
                    .{ .graph = graph, .module_idx = child_idx },
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
            defer allocator.free(emit_name);
            _ = try collectFuncDeclByNameAs(
                allocator,
                module.tokens,
                structs,
                struct_layouts,
                .{ .graph = graph, .module_idx = visit.module_idx },
                publicDeclName(visit.name),
                emit_name,
                true,
                out,
            );
        }
        try collectFunctionBodyCalls(allocator, module.tokens, visit.module_idx, visit.name, &stack);
    }
}

fn collectGenericFuncInstancesForStart(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    structs: []const StructDecl,
    value_enums: []const ValueEnumDecl,
    struct_layouts: []const StructLayout,
    host_imports: []const HostImport,
    wasi_imports: []const WasiHostImport,
    string_data: *const StringDataContext,
    modules: []const imports.ModuleRecord,
    imported_alias_ctx: ?ImportedAliasContext,
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
                        .value_enums = value_enums,
                        .struct_layouts = struct_layouts,
                        .host_imports = host_imports,
                        .wasi_imports = wasi_imports,
                        .string_data = string_data,
                        .entry_tokens = tokens,
                        .modules = modules,
                        .imported_alias_ctx = imported_alias_ctx,
                    };
                    try collectBodyLocals(allocator, tokens, open + 1, body_end, ctx, &locals);
                    try collectGenericFuncInstancesInRange(allocator, tokens, open + 1, body_end, &locals, ctx, functions);
                }
            }
        }
    }
    try collectGenericFuncInstancesForConcreteFuncs(allocator, tokens, structs, value_enums, struct_layouts, host_imports, wasi_imports, string_data, modules, imported_alias_ctx, functions);
}

fn collectGenericFuncInstancesForTests(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    test_decls: []const test_runner.TestDecl,
    structs: []const StructDecl,
    value_enums: []const ValueEnumDecl,
    struct_layouts: []const StructLayout,
    host_imports: []const HostImport,
    wasi_imports: []const WasiHostImport,
    string_data: *const StringDataContext,
    modules: []const imports.ModuleRecord,
    imported_alias_ctx: ?ImportedAliasContext,
    functions: *std.ArrayList(FuncDecl),
) !void {
    for (test_decls) |decl| {
        var locals = LocalSet{};
        defer locals.deinit(allocator);
        const ctx = CodegenContext{
            .functions = functions.items,
            .structs = structs,
            .value_enums = value_enums,
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
    try collectGenericFuncInstancesForConcreteFuncs(allocator, tokens, structs, value_enums, struct_layouts, host_imports, wasi_imports, string_data, modules, imported_alias_ctx, functions);
}

fn collectGenericFuncInstancesForConcreteFuncs(
    allocator: std.mem.Allocator,
    entry_tokens: []const lexer.Token,
    structs: []const StructDecl,
    value_enums: []const ValueEnumDecl,
    struct_layouts: []const StructLayout,
    host_imports: []const HostImport,
    wasi_imports: []const WasiHostImport,
    string_data: *const StringDataContext,
    modules: []const imports.ModuleRecord,
    imported_alias_ctx: ?ImportedAliasContext,
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
            .value_enums = value_enums,
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

fn appendFuncParamLocals(
    allocator: std.mem.Allocator,
    func: FuncDecl,
    ctx: CodegenContext,
    locals: *LocalSet,
) !void {
    for (func.params) |param| {
        if (param.callback != null) continue;
        const raw_abi_ty = funcParamAbiType(param);
        const abi_ty = try substituteGenericTypeOwned(allocator, raw_abi_ty, ctx.type_bindings, &locals.owned_names);
        if (try parseTypeUnionLayoutFromName(allocator, func.tokens, abi_ty, ctx.structs, ctx.struct_layouts, &locals.owned_names)) |layout| {
            errdefer freeUnionLayout(allocator, layout);
            try locals.appendUnionLocalWithOrigin(allocator, param.name, layout, false, true, .param_or_import);
        } else if (managedPayloadElemTypeFromName(abi_ty)) |elem_ty| {
            try locals.appendBorrowedLocalWithOrigin(allocator, param.name, abi_ty, false, .param_or_import);
            try locals.storage_locals.append(allocator, .{ .name = param.name, .ty = abi_ty, .elem_ty = elem_ty });
        } else if (findStructDecl(ctx.structs, abi_ty)) |decl| {
            try locals.struct_locals.append(allocator, .{ .name = param.name, .ty = abi_ty, .origin = .param_or_import });
            if (findStructLayout(ctx.struct_layouts, abi_ty) != null) {
                try locals.appendBorrowedLocalWithOrigin(allocator, param.name, abi_ty, false, .param_or_import);
                for (decl.fields) |field| {
                    const field_ty = try substituteStructFieldType(allocator, decl, abi_ty, field.ty, &locals.owned_names);
                    try appendManagedStructFieldMetaLocal(allocator, locals, param.name, field.name, field_ty);
                }
            } else {
                for (decl.fields) |field| {
                    const field_ty = try substituteStructFieldType(allocator, decl, abi_ty, field.ty, &locals.owned_names);
                    try appendBorrowedLocalField(allocator, locals, func.tokens, ctx, param.name, field.name, field_ty);
                }
            }
        } else if (isTupleTypeName(abi_ty)) {
            try locals.struct_locals.append(allocator, .{ .name = param.name, .ty = abi_ty, .origin = .param_or_import });
            const arity = tupleArity(abi_ty) orelse return error.UnsupportedLowering;
            var elem_idx: usize = 0;
            while (elem_idx < arity) : (elem_idx += 1) {
                const elem_ty = tupleElementTypeAt(abi_ty, elem_idx) orelse return error.UnsupportedLowering;
                var field_buf: [32]u8 = undefined;
                const field_name = try std.fmt.bufPrint(&field_buf, "{d}", .{elem_idx});
                try appendBorrowedLocalField(allocator, locals, func.tokens, ctx, param.name, field_name, elem_ty);
            }
        } else {
            try locals.appendBorrowedLocalWithOrigin(allocator, param.name, abi_ty, false, .param_or_import);
        }
    }
}

fn instantiateCallbackShape(
    allocator: std.mem.Allocator,
    param: FuncParam,
    bindings: []const GenericTypeBinding,
    owned_types: *std.ArrayList([]const u8),
) !?OwnedFuncTypeShape {
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

fn instantiateFuncTypeShape(
    allocator: std.mem.Allocator,
    shape: FuncTypeShape,
    bindings: []const GenericTypeBinding,
    owned_types: *std.ArrayList([]const u8),
) !FuncTypeShape {
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

fn callbackBindingsForCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    call_head: ExprCallHead,
    params: []const FuncParam,
    ctx: ?CodegenContext,
) ![]const CallbackBinding {
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

fn resolveCallbackBindingArg(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    arg_start: usize,
    arg_end: usize,
    param_name: []const u8,
    shape: FuncTypeShape,
    ctx: ?CodegenContext,
) !?CallbackBinding {
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

    if (arg_end == arg_start + 1 and tokens[arg_start].kind == .ident) {
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

    return null;
}

fn callbackBindingsHaveSameShape(left: FuncTypeShape, right: FuncTypeShape) bool {
    if (left.param_types.len != right.param_types.len) return false;
    for (left.param_types, 0..) |left_ty, idx| {
        const right_ty = right.param_types[idx];
        if (left_ty == null or right_ty == null) continue;
        if (!std.mem.eql(u8, left_ty.?, right_ty.?)) return false;
    }
    if (left.return_type == null and right.return_type == null) return true;
    if (left.return_type == null or right.return_type == null) return false;
    return std.mem.eql(u8, left.return_type.?, right.return_type.?);
}

fn freeCallbackBindings(allocator: std.mem.Allocator, bindings: []const CallbackBinding) void {
    for (bindings) |binding| {
        if (binding.lambda_params.len != 0) allocator.free(binding.lambda_params);
    }
    allocator.free(bindings);
}

fn funcHasCallbackParams(func: FuncDecl) bool {
    for (func.params) |param| {
        if (param.callback != null) return true;
    }
    return false;
}

fn cloneFuncParams(allocator: std.mem.Allocator, params: []const FuncParam) ![]const FuncParam {
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

fn collectGenericFuncInstancesInRange(
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

fn collectGenericFuncInstancesInGuardReturn(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *LocalSet,
    ctx: CodegenContext,
    functions: *std.ArrayList(FuncDecl),
) !void {
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

fn collectGenericFuncInstancesInGuardLoopControl(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *LocalSet,
    ctx: CodegenContext,
    functions: *std.ArrayList(FuncDecl),
) !void {
    const control_idx = findTopLevelGuardLoopControl(tokens, start_idx + 1, end_idx) orelse return;
    try collectGenericFuncInstancesInRange(allocator, tokens, start_idx + 1, control_idx, locals, ctx, functions);
    try applyGuardLoopControlNarrowing(allocator, tokens, start_idx, end_idx, locals, ctx);
}

fn applyCollectGuardReturnNarrowing(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *LocalSet,
    ctx: CodegenContext,
) !void {
    try applyGuardReturnNilNarrowing(allocator, tokens, start_idx, end_idx, locals);
    try applyGuardReturnIsNarrowing(allocator, tokens, start_idx, end_idx, locals, ctx);
}

fn collectGenericFuncInstancesInCallArgs(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    functions: *std.ArrayList(FuncDecl),
) !void {
    var arg_start = args_start;
    while (arg_start < args_end) {
        const arg_end = findArgEnd(tokens, arg_start, args_end);
        if (arg_end == arg_start) return error.NoMatchingCall;
        try collectGenericFuncInstancesInRange(allocator, tokens, arg_start, arg_end, locals, ctx, functions);
        arg_start = arg_end;
        if (arg_start < args_end and tokEq(tokens[arg_start], ",")) arg_start += 1;
    }
}

fn collectGenericFuncInstancesInFieldReflectionLoop(
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

fn directCallExpectedResultType(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    call_start: usize,
    stmt_end: usize,
    ctx: CodegenContext,
    owned_types: *std.ArrayList([]const u8),
) CodegenError!?[]const u8 {
    const stmt_start = findLineStart(tokens, call_start);
    const eq_idx = findTopLevelToken(tokens, stmt_start, stmt_end, "=") orelse return null;
    const rhs = trimParens(tokens, eq_idx + 1, stmt_end);
    if (rhs.start != call_start) return null;
    return typedBindingExpectedType(allocator, tokens, stmt_start, eq_idx, ctx, owned_types);
}

fn typedBindingExpectedType(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    stmt_start: usize,
    eq_idx: usize,
    ctx: CodegenContext,
    owned_types: *std.ArrayList([]const u8),
) CodegenError!?[]const u8 {
    if (stmt_start + 2 >= eq_idx) return null;
    if (tokens[stmt_start].kind != .ident) return null;
    const parsed = (try parseFuncParamTypeExpr(allocator, tokens, stmt_start + 1, eq_idx, owned_types)) orelse return null;
    if (parsed.next_idx != eq_idx) return null;
    return try substituteGenericTypeOwned(allocator, parsed.ty, ctx.type_bindings, owned_types);
}

fn collectGenericFuncInstanceForCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    call_head: ExprCallHead,
    locals: *const LocalSet,
    ctx: CodegenContext,
    template: FuncDecl,
    expected_result_ty: ?[]const u8,
    functions: *std.ArrayList(FuncDecl),
) !void {
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

fn bindGenericExpectedResult(
    allocator: std.mem.Allocator,
    template: FuncDecl,
    expected_result_ty: ?[]const u8,
    bindings: *std.ArrayList(GenericTypeBinding),
    owned_types: *std.ArrayList([]const u8),
) CodegenError!bool {
    const expected = expected_result_ty orelse return true;
    const template_result = genericTemplateLogicalResultType(template) orelse return true;
    if (!typeContainsTypeParam(template.type_params, template_result)) {
        return codegenTypesCompatible(template_result, expected);
    }
    return try bindGenericTypeFromConcrete(allocator, template_result, expected, template.type_params, bindings, owned_types);
}

fn genericTemplateLogicalResultType(template: FuncDecl) ?[]const u8 {
    if (template.result_union) |layout| return layout.source_ty;
    if (template.result_items.len == 1) return template.result_items[0].ty;
    if (template.results.len == 1) return template.results[0];
    return null;
}

fn collectGenericFuncInstancesForCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    call_head: ExprCallHead,
    locals: *const LocalSet,
    ctx: CodegenContext,
    expected_result_ty: ?[]const u8,
    functions: *std.ArrayList(FuncDecl),
) !void {
    const name = publicDeclName(tokens[call_head.name_idx].lexeme);
    const initial_len = functions.items.len;
    var idx: usize = 0;
    while (idx < initial_len) : (idx += 1) {
        const template = functions.items[idx];
        if (!genericTemplateMatchesCallSite(template, tokens, ctx, name)) continue;
        try collectGenericFuncInstanceForCall(allocator, tokens, call_head, locals, ctx, template, expected_result_ty, functions);
    }
}

fn genericTemplateMatchesCallSite(template: FuncDecl, tokens: []const lexer.Token, ctx: CodegenContext, name: []const u8) bool {
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

fn collectConcreteCallbackFuncInstanceForCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    call_head: ExprCallHead,
    ctx: CodegenContext,
    func: FuncDecl,
    functions: *std.ArrayList(FuncDecl),
) !void {
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

fn concreteOverloadCoversGenericParams(
    functions: []const FuncDecl,
    template: FuncDecl,
    params: []const FuncParam,
    callback_bindings: []const CallbackBinding,
) bool {
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

fn callbackBindingsHaveSameConcreteArgs(left: []const CallbackBinding, right: []const CallbackBinding) bool {
    if (left.len != right.len) return false;
    for (left, 0..) |left_binding, idx| {
        if (!callbackBindingHasSameConcreteArg(left_binding, right[idx])) return false;
    }
    return true;
}

fn callbackBindingHasSameConcreteArg(left: CallbackBinding, right: CallbackBinding) bool {
    if (left.kind != right.kind) return false;
    if (!callbackBindingsHaveSameShape(left.shape, right.shape)) return false;
    return switch (left.kind) {
        .lambda => moduleTokensEqual(left.arg_tokens, right.arg_tokens) and left.arg_start == right.arg_start and left.arg_end == right.arg_end,
        .func_ref => blk: {
            const left_name = left.func_name orelse break :blk false;
            const right_name = right.func_name orelse break :blk false;
            break :blk moduleTokensEqual(left.arg_tokens, right.arg_tokens) and sameCallableSourceName(left_name, right_name);
        },
    };
}

fn funcParamsHaveSameConcreteCallShape(left: FuncParam, right: FuncParam) bool {
    if (left.variadic != right.variadic) return false;
    if (left.callback != null or right.callback != null) {
        const left_callback = left.callback orelse return false;
        const right_callback = right.callback orelse return false;
        return callbackBindingsHaveSameShape(left_callback.shape, right_callback.shape);
    }
    return std.mem.eql(u8, funcParamAbiType(left), funcParamAbiType(right));
}

fn genericOverloadCoversGenericParams(
    allocator: std.mem.Allocator,
    functions: []const FuncDecl,
    template: FuncDecl,
    param_tys: []const []const u8,
) !bool {
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

fn genericTemplateSpecificity(template: FuncDecl) usize {
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

fn genericTemplateMatchesConcreteParams(
    allocator: std.mem.Allocator,
    template: FuncDecl,
    param_tys: []const []const u8,
) !bool {
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

fn instantiateGenericFuncResultItems(
    allocator: std.mem.Allocator,
    template: FuncDecl,
    result_tys: []const []const u8,
    bindings: []const GenericTypeBinding,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    owned_types: *std.ArrayList([]const u8),
) !FuncResultParse {
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
        if (findStructDecl(structs, result_ty)) |decl| {
            if (findStructLayout(struct_layouts, result_ty) == null) {
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
                if (result_tys.len == 1) result_struct = result_ty;
                continue;
            }
        }

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

fn bindGenericFuncCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    template: FuncDecl,
    bindings: *std.ArrayList(GenericTypeBinding),
    param_tys: *std.ArrayList([]const u8),
    owned_types: *std.ArrayList([]const u8),
) !bool {
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
                if (!callArgMatchesParam(tokens, arg_start, arg_end, locals, ctx, concrete_before)) {
                    return false;
                }
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

fn prebindGenericCallbackArgs(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    ctx: CodegenContext,
    template: FuncDecl,
    bindings: *std.ArrayList(GenericTypeBinding),
    owned_types: *std.ArrayList([]const u8),
) !bool {
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

fn prebindGenericCallbackArg(
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
    if (lambdaExprShape(tokens, arg_start, arg_end)) |lambda| {
        const lambda_param_types = try parseLambdaParamTypes(allocator, tokens, lambda.open_params + 1, lambda.close_params);
        defer allocator.free(lambda_param_types);
        if (lambda_param_types.len != shape.param_types.len) return false;

        for (shape.param_types, 0..) |shape_ty, idx| {
            const expected_ty = shape_ty orelse continue;
            const explicit_ty = lambda_param_types[idx] orelse continue;
            if (!typeContainsTypeParam(template.type_params, expected_ty)) continue;
            if (!try bindGenericTypeFromConcrete(allocator, expected_ty, explicit_ty, template.type_params, bindings, owned_types)) return false;
        }
        if (shape.return_type) |ret_ty| {
            if (lambdaExplicitReturnType(tokens, lambda)) |lambda_ret| {
                if (typeContainsTypeParam(template.type_params, ret_ty)) {
                    if (!try bindGenericTypeFromConcrete(allocator, ret_ty, lambda_ret, template.type_params, bindings, owned_types)) return false;
                }
            }
        }
        return true;
    }

    if (arg_end == arg_start + 1 and tokens[arg_start].kind == .ident) {
        const binding = findCallbackBinding(ctx.callback_bindings, tokens[arg_start].lexeme) orelse {
            return try prebindGenericCallbackFuncRef(allocator, tokens, ctx, template, shape, tokens[arg_start].lexeme, bindings, owned_types);
        };
        if (binding.shape.param_types.len != shape.param_types.len) return false;
        for (shape.param_types, 0..) |shape_ty, idx| {
            const expected_ty = shape_ty orelse continue;
            const upstream_ty = binding.shape.param_types[idx] orelse continue;
            if (!typeContainsTypeParam(template.type_params, expected_ty)) continue;
            if (!try bindGenericTypeFromConcrete(allocator, expected_ty, upstream_ty, template.type_params, bindings, owned_types)) return false;
        }
        if (shape.return_type) |ret_ty| {
            if (binding.shape.return_type) |upstream_ret| {
                if (typeContainsTypeParam(template.type_params, ret_ty)) {
                    if (!try bindGenericTypeFromConcrete(allocator, ret_ty, upstream_ret, template.type_params, bindings, owned_types)) return false;
                }
            }
        }
    }
    return true;
}

fn prebindGenericCallbackFuncRef(
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
            if (!typeContainsTypeParam(template.type_params, expected_ty)) continue;
            if (!try bindGenericTypeFromConcrete(allocator, expected_ty, funcParamAbiType(func.params[idx]), template.type_params, bindings, owned_types)) return false;
        }
        if (shape.return_type) |ret_ty| {
            if (typeContainsTypeParam(template.type_params, ret_ty)) {
                const func_ret = genericTemplateLogicalResultType(func) orelse return false;
                if (!try bindGenericTypeFromConcrete(allocator, ret_ty, func_ret, template.type_params, bindings, owned_types)) return false;
            }
        }
        return true;
    }
    return true;
}

fn bindGenericVariadicTail(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    template: FuncDecl,
    param_ty: []const u8,
    bindings: *std.ArrayList(GenericTypeBinding),
    owned_types: *std.ArrayList([]const u8),
) !bool {
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
                const arg_ty = inferExprType(tokens, tail_start, tail_end, locals, ctx);
                if (arg_ty) |actual_ty| {
                    if (!try bindGenericTypeFromConcrete(allocator, param_ty, actual_ty, template.type_params, bindings, owned_types)) return false;
                }
            }
            tail_start = tail_end;
            if (tail_start < args_end and tokEq(tokens[tail_start], ",")) tail_start += 1;
        }
    }

    const concrete_ty = try substituteGenericTypeOwned(allocator, param_ty, bindings.items, owned_types);
    if (typeContainsTypeParam(template.type_params, concrete_ty)) return false;
    return callArgsMatchVariadicTail(tokens, args_start, args_end, locals, ctx, concrete_ty);
}

fn bindGenericCallbackArg(
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
        if (findCallbackBinding(ctx.callback_bindings, tokens[arg_start].lexeme)) |binding| {
            for (callback.shape.param_types, 0..) |expected_ty, idx| {
                const shape_ty = expected_ty orelse {
                    if (idx >= binding.shape.param_types.len) return false;
                    continue;
                };
                if (idx >= binding.shape.param_types.len) return false;
                const upstream_ty = binding.shape.param_types[idx] orelse return false;
                if (!typeContainsTypeParam(template.type_params, shape_ty)) {
                    const concrete_ty = try substituteGenericTypeOwned(allocator, shape_ty, bindings.items, owned_types);
                    if (!std.mem.eql(u8, concrete_ty, upstream_ty)) return false;
                    continue;
                }

                if (!try bindGenericTypeFromConcrete(allocator, shape_ty, upstream_ty, template.type_params, bindings, owned_types)) return false;
            }
            if (binding.shape.param_types.len != callback.shape.param_types.len) return false;

            if (callback.shape.return_type) |ret_ty| {
                const upstream_ret = binding.shape.return_type orelse return false;
                if (!typeContainsTypeParam(template.type_params, ret_ty)) {
                    const concrete_ret = try substituteGenericTypeOwned(allocator, ret_ty, bindings.items, owned_types);
                    return std.mem.eql(u8, concrete_ret, upstream_ret);
                }
                return try bindGenericTypeFromConcrete(allocator, ret_ty, upstream_ret, template.type_params, bindings, owned_types);
            }
            return binding.shape.return_type == null;
        }
        const concrete_shape = try instantiateFuncTypeShape(allocator, callback.shape, bindings.items, owned_types);
        defer allocator.free(concrete_shape.param_types);
        return findCallbackRefFunc(tokens, ctx, tokens[arg_start].lexeme, concrete_shape) != null;
    }
    if (lambdaExprShape(tokens, arg_start, arg_end)) |lambda| {
        const lambda_param_types = try parseLambdaParamTypes(allocator, tokens, lambda.open_params + 1, lambda.close_params);
        defer allocator.free(lambda_param_types);
        if (lambda_param_types.len != callback.shape.param_types.len) return false;

        for (callback.shape.param_types, 0..) |expected_ty, idx| {
            const explicit_ty = lambda_param_types[idx];
            const shape_ty = expected_ty orelse continue;
            if (!typeContainsTypeParam(template.type_params, shape_ty)) {
                const concrete_ty = try substituteGenericTypeOwned(allocator, shape_ty, bindings.items, owned_types);
                if (explicit_ty) |ty| {
                    if (!std.mem.eql(u8, concrete_ty, ty)) return false;
                }
                continue;
            }

            if (explicit_ty) |ty| {
                if (!try bindGenericTypeFromConcrete(allocator, shape_ty, ty, template.type_params, bindings, owned_types)) return false;
                continue;
            }
            const concrete_ty = try substituteGenericTypeOwned(allocator, shape_ty, bindings.items, owned_types);
            if (typeContainsTypeParam(template.type_params, concrete_ty)) return false;
        }

        if (callback.shape.return_type) |ret_ty| {
            const concrete_shape = try instantiateFuncTypeShape(allocator, callback.shape, bindings.items, owned_types);
            defer allocator.free(concrete_shape.param_types);
            const lambda_ret = (try inferLambdaExprReturnType(allocator, tokens, lambda, concrete_shape, locals, ctx)) orelse return false;
            if (!typeContainsTypeParam(template.type_params, ret_ty)) {
                const concrete_ret = try substituteGenericTypeOwned(allocator, ret_ty, bindings.items, owned_types);
                return std.mem.eql(u8, concrete_ret, lambda_ret);
            }
            return try bindGenericTypeFromConcrete(allocator, ret_ty, lambda_ret, template.type_params, bindings, owned_types);
        }
        return true;
    }

    return false;
}

fn inferUntypedGenericParamAbiType(
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

fn bindExplicitGenericCallTypeArgs(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    call_head: ExprCallHead,
    template: FuncDecl,
    bindings: *std.ArrayList(GenericTypeBinding),
    owned_types: *std.ArrayList([]const u8),
) !bool {
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

fn bindGenericType(
    allocator: std.mem.Allocator,
    bindings: *std.ArrayList(GenericTypeBinding),
    name: []const u8,
    ty: []const u8,
    owned_types: *std.ArrayList([]const u8),
) !bool {
    for (bindings.items) |binding| {
        if (!std.mem.eql(u8, binding.name, name)) continue;
        return std.mem.eql(u8, binding.ty, ty);
    }
    const owned_ty = try allocator.dupe(u8, ty);
    errdefer allocator.free(owned_ty);
    try owned_types.append(allocator, owned_ty);
    try bindings.append(allocator, .{ .name = name, .ty = owned_ty });
    return true;
}

fn cloneGenericTypeBindingsOwned(
    allocator: std.mem.Allocator,
    bindings: []const GenericTypeBinding,
    owned_types: *std.ArrayList([]const u8),
) ![]const GenericTypeBinding {
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

fn substituteGenericTypeOwned(
    allocator: std.mem.Allocator,
    ty: []const u8,
    bindings: []const GenericTypeBinding,
    owned_types: *std.ArrayList([]const u8),
) ![]const u8 {
    if (findGenericBinding(bindings, ty)) |binding| return binding.ty;
    if (!typeContainsGenericBinding(ty, bindings)) return ty;

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < ty.len) {
        if (!isTypeIdentStart(ty[i])) {
            try out.append(allocator, ty[i]);
            i += 1;
            continue;
        }

        const ident_start = i;
        i += 1;
        while (i < ty.len and isTypeIdentPart(ty[i])) i += 1;
        const ident = ty[ident_start..i];
        if (findGenericBinding(bindings, ident)) |binding| {
            try out.appendSlice(allocator, binding.ty);
        } else {
            try out.appendSlice(allocator, ident);
        }
    }

    const owned = try out.toOwnedSlice(allocator);
    errdefer allocator.free(owned);
    try owned_types.append(allocator, owned);
    return owned;
}

fn typeContainsGenericBinding(ty: []const u8, bindings: []const GenericTypeBinding) bool {
    var i: usize = 0;
    while (i < ty.len) {
        if (!isTypeIdentStart(ty[i])) {
            i += 1;
            continue;
        }
        const ident_start = i;
        i += 1;
        while (i < ty.len and isTypeIdentPart(ty[i])) i += 1;
        if (findGenericBinding(bindings, ty[ident_start..i]) != null) return true;
    }
    return false;
}

fn typeContainsTypeParam(type_params: []const []const u8, ty: []const u8) bool {
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

fn isTypeIdentStart(ch: u8) bool {
    return ch == '_' or (ch >= 'A' and ch <= 'Z') or (ch >= 'a' and ch <= 'z');
}

fn isTypeIdentPart(ch: u8) bool {
    return isTypeIdentStart(ch) or (ch >= '0' and ch <= '9');
}

fn bindGenericTypeFromConcrete(
    allocator: std.mem.Allocator,
    expected_ty: []const u8,
    actual_ty: []const u8,
    type_params: []const []const u8,
    bindings: *std.ArrayList(GenericTypeBinding),
    owned_types: *std.ArrayList([]const u8),
) CodegenError!bool {
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

const GenericTypeArgsRange = type_util.GenericTypeArgsRange;

fn genericTypeArgsRange(ty: []const u8) ?GenericTypeArgsRange {
    return type_util.genericTypeArgsRange(ty);
}

fn bindGenericTypeListFromConcrete(
    allocator: std.mem.Allocator,
    expected: []const u8,
    actual: []const u8,
    sep: u8,
    type_params: []const []const u8,
    bindings: *std.ArrayList(GenericTypeBinding),
    owned_types: *std.ArrayList([]const u8),
) CodegenError!bool {
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

fn findTopLevelTypeSeparator(ty: []const u8, sep: u8) ?usize {
    return findTopLevelTypeSeparatorFrom(ty, 0, sep);
}

fn findTopLevelTypeSeparatorFrom(ty: []const u8, start_idx: usize, sep: u8) ?usize {
    return type_util.findTopLevelTypeSeparatorFrom(ty, start_idx, sep);
}

fn bindStructTypeArgs(
    allocator: std.mem.Allocator,
    decl: StructDecl,
    concrete_ty: []const u8,
    bindings: *std.ArrayList(GenericTypeBinding),
    owned_types: *std.ArrayList([]const u8),
) !bool {
    if (decl.type_params.len == 0) return true;
    const args = genericTypeArgsRange(concrete_ty) orelse return false;
    if (!std.mem.eql(u8, args.base, decl.name)) return false;

    var arg_start: usize = 0;
    var param_idx: usize = 0;
    while (arg_start < args.args.len) {
        if (param_idx >= decl.type_params.len) return false;
        const arg_end = findTopLevelTypeSeparatorFrom(args.args, arg_start, ',') orelse args.args.len;
        if (arg_start == arg_end) return false;
        if (!try bindGenericType(allocator, bindings, decl.type_params[param_idx], args.args[arg_start..arg_end], owned_types)) return false;
        param_idx += 1;
        arg_start = arg_end;
        if (arg_start < args.args.len) arg_start += 1;
    }
    return param_idx == decl.type_params.len;
}

fn substituteStructFieldType(
    allocator: std.mem.Allocator,
    decl: StructDecl,
    concrete_ty: []const u8,
    field_ty: []const u8,
    owned_types: *std.ArrayList([]const u8),
) ![]const u8 {
    if (decl.type_params.len == 0) return field_ty;
    var bindings = std.ArrayList(GenericTypeBinding).empty;
    defer bindings.deinit(allocator);
    if (!try bindStructTypeArgs(allocator, decl, concrete_ty, &bindings, owned_types)) return field_ty;
    return try substituteGenericTypeOwned(allocator, field_ty, bindings.items, owned_types);
}

fn genericInstanceName(
    allocator: std.mem.Allocator,
    template: FuncDecl,
    bindings: []const GenericTypeBinding,
    param_tys: []const []const u8,
    callback_bindings: []const CallbackBinding,
) ![]u8 {
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

fn funcHasUntypedParams(func: FuncDecl) bool {
    for (func.params) |param| {
        if (param.ty.len == 0) return true;
    }
    return false;
}

fn moduleScopedSymbolName(
    allocator: std.mem.Allocator,
    module_idx: usize,
    name: []const u8,
) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try appendFmt(allocator, &out, "__mod_{d}__", .{module_idx});
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

fn findGenericTemplateForCall(functions: []const FuncDecl, tokens: []const lexer.Token, ctx: CodegenContext, name: []const u8) ?FuncDecl {
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

fn mangleOverloadedFunctionNames(
    allocator: std.mem.Allocator,
    functions: *std.ArrayList(FuncDecl),
) !void {
    for (functions.items, 0..) |func, idx| {
        if (func.is_generic_template) continue;
        if (!functionSourceNameHasMultipleConcreteDecls(functions.items, func.tokens, func.source_name)) continue;

        const next_name = try functionSignatureSymbolName(allocator, func);
        errdefer allocator.free(next_name);
        if (std.mem.eql(u8, next_name, func.name)) {
            allocator.free(next_name);
            continue;
        }
        if (functions.items[idx].owned_name) allocator.free(functions.items[idx].name);
        functions.items[idx].name = next_name;
        functions.items[idx].owned_name = true;
    }
}

fn functionSourceNameHasMultipleConcreteDecls(
    functions: []const FuncDecl,
    tokens: []const lexer.Token,
    source_name: []const u8,
) bool {
    var count: usize = 0;
    for (functions) |func| {
        if (func.is_generic_template) continue;
        if (!moduleTokensEqual(func.tokens, tokens)) continue;
        if (!sameCallableSourceName(func.source_name, source_name)) continue;
        count += 1;
        if (count > 1) return true;
    }
    return false;
}

fn sameCallableSourceName(left: []const u8, right: []const u8) bool {
    return std.mem.eql(u8, publicDeclName(left), publicDeclName(right));
}

fn functionSignatureSymbolName(
    allocator: std.mem.Allocator,
    func: FuncDecl,
) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, func.name);
    if (func.params.len == 0) {
        try out.appendSlice(allocator, "__nil");
        return out.toOwnedSlice(allocator);
    }
    for (func.params) |param| {
        try out.appendSlice(allocator, "__");
        if (param.variadic) try out.appendSlice(allocator, "rest_");
        try appendMangledTypeName(allocator, &out, param.ty);
    }
    return out.toOwnedSlice(allocator);
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
            if (findImportedModuleIndex(allocator, graph, visit.module_idx, import_ref)) |child_idx| {
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
    imported_alias_ctx: ?ImportedAliasContext,
    target_name: []const u8,
    emit_name: []const u8,
    owned_emit_name: bool,
    out: *std.ArrayList(FuncDecl),
) !bool {
    var depth_brace: usize = 0;
    var pending_type_params = std.ArrayList([]const u8).empty;
    defer pending_type_params.deinit(allocator);
    var collected = false;
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
        const close_params = findMatching(tokens, open_params, "(", ")") catch {
            pending_type_params.clearRetainingCapacity();
            continue;
        };
        const body = parseFuncBodyShape(tokens, close_params) catch {
            pending_type_params.clearRetainingCapacity();
            continue;
        };
        if (!std.mem.eql(u8, publicDeclName(tokens[i].lexeme), target_name)) {
            pending_type_params.clearRetainingCapacity();
            i = body.next_idx;
            continue;
        }
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
        const parsed_results = (try parseFuncDeclResultTypes(
            allocator,
            tokens,
            body.result_start,
            body.result_end,
            type_params,
            structs,
            struct_layouts,
            imported_alias_ctx,
            &owned_types,
        )) orelse return false;
        const results = parsed_results.types;
        var results_owned = true;
        errdefer if (results_owned) allocator.free(results);
        const result_items = parsed_results.items;
        var result_items_owned = parsed_results.owns_items;
        errdefer if (result_items_owned) allocator.free(result_items);

        var params = std.ArrayList(FuncParam).empty;
        errdefer {
            for (params.items) |param| {
                if (param.callback) |callback| {
                    if (callback.owned) allocator.free(callback.shape.param_types);
                }
            }
            params.deinit(allocator);
        }
        var param_idx = open_params + 1;
        while (param_idx < close_params) {
            if (tokEq(tokens[param_idx], ",")) {
                param_idx += 1;
                continue;
            }
            if (tokens[param_idx].kind != .ident) return error.InvalidParamName;
            const param_end = findArgEnd(tokens, param_idx, close_params);
            if (param_end == param_idx + 1) {
                if (type_params.len == 0) return error.InvalidParamName;
                try params.append(allocator, .{
                    .name = tokens[param_idx].lexeme,
                    .ty = "",
                });
                param_idx = param_end;
                if (param_idx < close_params and tokEq(tokens[param_idx], ",")) param_idx += 1;
                continue;
            }
            var type_start = param_idx + 1;
            var variadic = false;
            if (type_start < close_params and tokEq(tokens[type_start], "...")) {
                variadic = true;
                type_start += 1;
            }
            const parsed_ty = (try parseFuncParamTypeExpr(allocator, tokens, type_start, param_end, &owned_types)) orelse return error.InvalidParamName;
            const callback = try parseFuncTypeConstraintShape(allocator, tokens, i, parsed_ty.ty);
            try params.append(allocator, .{
                .name = tokens[param_idx].lexeme,
                .ty = parsed_ty.ty,
                .variadic = variadic,
                .callback = callback,
            });
            param_idx = parsed_ty.next_idx;
            if (param_idx < close_params and tokEq(tokens[param_idx], ",")) param_idx += 1;
        }

        const decl_name = if (owned_emit_name) try allocator.dupe(u8, emit_name) else emit_name;
        var decl_name_owned = owned_emit_name;
        errdefer if (decl_name_owned) allocator.free(decl_name);

        try out.append(allocator, .{
            .name = decl_name,
            .source_name = target_name,
            .params = try params.toOwnedSlice(allocator),
            .result = if (results.len == 1) results[0] else null,
            .results = results,
            .result_items = result_items,
            .result_struct = parsed_results.result_struct,
            .result_union = parsed_results.result_union,
            .type_params = type_params,
            .is_generic_template = type_params.len != 0,
            .owned_name = owned_emit_name,
            .owned_types = try owned_types.toOwnedSlice(allocator),
            .tokens = tokens,
            .start_idx = i,
            .arrow = body.arrow,
            .body_start = body.body_start,
            .body_end = body.body_end,
        });
        results_owned = false;
        result_items_owned = false;
        type_params_owned = false;
        decl_name_owned = false;
        collected = true;
        pending_type_params.clearRetainingCapacity();
        i = body.next_idx;
        continue;
    }
    return collected;
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

fn parseFuncDeclResultTypes(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    type_params: []const []const u8,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    imported_alias_ctx: ?ImportedAliasContext,
    owned_types: *std.ArrayList([]const u8),
) !?FuncResultParse {
    if (start_idx == end_idx) {
        return .{
            .types = try allocator.alloc([]const u8, 0),
            .items = try allocator.alloc(FuncResultItem, 0),
        };
    }

    if (type_params.len != 0) {
        const uses_type_param = typeParamsAppearInRange(tokens, start_idx, end_idx, type_params);
        if (uses_type_param) {
            return try parseGenericFuncResultTypes(
                allocator,
                tokens,
                start_idx,
                end_idx,
                type_params,
                structs,
                struct_layouts,
                owned_types,
            );
        }
    }

    if (try parseFuncResultTypes(allocator, tokens, start_idx, end_idx, structs, struct_layouts, imported_alias_ctx, owned_types)) |parsed| {
        return parsed;
    }
    if (type_params.len != 0) {
        return try parseGenericFuncResultTypes(
            allocator,
            tokens,
            start_idx,
            end_idx,
            type_params,
            structs,
            struct_layouts,
            owned_types,
        );
    }
    return null;
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
    var items = std.ArrayList(FuncResultItem).empty;
    errdefer items.deinit(allocator);

    if (start_idx + 1 == end_idx and tokEq(tokens[start_idx], "nil")) {
        return .{
            .types = try results.toOwnedSlice(allocator),
            .items = try items.toOwnedSlice(allocator),
        };
    }

    if (try parseUnionTypeLayout(allocator, tokens, start_idx, end_idx, structs, struct_layouts, imported_alias_ctx, owned_types)) |layout| {
        const abi_start = results.items.len;
        for (layout.payload_tys) |payload_ty| {
            try results.append(allocator, payload_ty);
        }
        try results.append(allocator, "i32");
        try items.append(allocator, .{
            .ty = layout.source_ty,
            .abi_start = abi_start,
            .abi_len = layout.payload_tys.len + 1,
            .union_layout = layout,
        });
        return .{
            .types = try results.toOwnedSlice(allocator),
            .items = try items.toOwnedSlice(allocator),
            .result_union = layout,
        };
    }

    if (parseErrorNilResultType(tokens, start_idx, end_idx)) |result_ty| {
        const abi_start = results.items.len;
        try results.append(allocator, result_ty);
        try items.append(allocator, .{ .ty = result_ty, .abi_start = abi_start, .abi_len = 1 });
        return .{
            .types = try results.toOwnedSlice(allocator),
            .items = try items.toOwnedSlice(allocator),
        };
    }

    if (parseStructErrorResultType(tokens, start_idx, end_idx, structs, struct_layouts)) |parsed| {
        const decl = findStructDecl(structs, parsed.struct_name) orelse return null;
        const abi_start = results.items.len;
        for (decl.fields) |field| {
            if (!isCoreWasmScalar(field.ty)) return null;
            try results.append(allocator, field.ty);
        }
        try results.append(allocator, parsed.error_name);
        try items.append(allocator, .{ .ty = parsed.struct_name, .abi_start = abi_start, .abi_len = decl.fields.len + 1 });
        return .{
            .types = try results.toOwnedSlice(allocator),
            .items = try items.toOwnedSlice(allocator),
            .result_struct = parsed.struct_name,
        };
    }

    if (start_idx + 1 == end_idx and tokens[start_idx].kind == .ident) {
        const struct_name = tokens[start_idx].lexeme;
        if (findStructLayout(struct_layouts, struct_name) == null) {
            if (findStructDecl(structs, struct_name)) |decl| {
                const abi_start = results.items.len;
                for (decl.fields) |field| {
                    if (!isCoreWasmScalar(field.ty)) return null;
                    try results.append(allocator, field.ty);
                }
                try items.append(allocator, .{ .ty = struct_name, .abi_start = abi_start, .abi_len = decl.fields.len });
                return .{
                    .types = try results.toOwnedSlice(allocator),
                    .items = try items.toOwnedSlice(allocator),
                    .result_struct = struct_name,
                };
            }
        }
        if (isErrorEnumType(tokens, struct_name)) {
            const abi_start = results.items.len;
            try results.append(allocator, struct_name);
            try items.append(allocator, .{ .ty = struct_name, .abi_start = abi_start, .abi_len = 1 });
            return .{
                .types = try results.toOwnedSlice(allocator),
                .items = try items.toOwnedSlice(allocator),
            };
        }
        if (errorNilAliasTarget(tokens, struct_name)) |error_name| {
            const abi_start = results.items.len;
            try results.append(allocator, error_name);
            try items.append(allocator, .{ .ty = error_name, .abi_start = abi_start, .abi_len = 1 });
            return .{
                .types = try results.toOwnedSlice(allocator),
                .items = try items.toOwnedSlice(allocator),
            };
        }
        if (importedErrorNilAliasTarget(allocator, imported_alias_ctx, tokens, struct_name)) |error_name| {
            const abi_start = results.items.len;
            try results.append(allocator, error_name);
            try items.append(allocator, .{ .ty = error_name, .abi_start = abi_start, .abi_len = 1 });
            return .{
                .types = try results.toOwnedSlice(allocator),
                .items = try items.toOwnedSlice(allocator),
            };
        }
    }

    var i = start_idx;
    while (i < end_idx) {
        if (tokEq(tokens[i], ",")) {
            i += 1;
            continue;
        }

        if (try parseUnionTypeLayout(allocator, tokens, i, findArgEnd(tokens, i, end_idx), structs, struct_layouts, imported_alias_ctx, owned_types)) |layout| {
            const item_end = findArgEnd(tokens, i, end_idx);
            if (item_end == i) return null;
            const abi_start = results.items.len;
            for (layout.payload_tys) |payload_ty| {
                try results.append(allocator, payload_ty);
            }
            try results.append(allocator, "i32");
            try items.append(allocator, .{
                .ty = layout.source_ty,
                .abi_start = abi_start,
                .abi_len = layout.payload_tys.len + 1,
                .union_layout = layout,
            });
            i = item_end;
            if (i < end_idx and tokEq(tokens[i], ",")) i += 1;
            continue;
        }

        const parsed_ty = (try parseCodegenTypeExpr(allocator, tokens, i, end_idx, owned_types)) orelse return null;
        const result_ty = parsed_ty.ty;
        if (isTupleTypeName(result_ty)) {
            const arity = tupleArity(result_ty) orelse return null;
            if (arity < 2) return null;
            const abi_start = results.items.len;
            const leaf_start = results.items.len;
            try appendTupleLeafTypes(allocator, result_ty, &results);
            if (results.items.len - leaf_start < 2) return null;
            for (results.items[leaf_start..]) |leaf_ty| {
                if (!isCoreWasmScalar(leaf_ty)) return null;
            }
            try items.append(allocator, .{
                .ty = result_ty,
                .abi_start = abi_start,
                .abi_len = results.items.len - abi_start,
            });
            i = parsed_ty.next_idx;
            if (i < end_idx and tokEq(tokens[i], ",")) i += 1;
            continue;
        }
        const accepted = isCoreWasmScalar(result_ty) or
            managedPayloadElemTypeFromName(result_ty) != null or
            findStructLayout(struct_layouts, result_ty) != null or
            (tokens[i].kind == .ident and errorNilAliasTarget(tokens, tokens[i].lexeme) != null) or
            (tokens[i].kind == .ident and importedErrorNilAliasTarget(allocator, imported_alias_ctx, tokens, tokens[i].lexeme) != null);
        if (!accepted) return null;

        const abi_start = results.items.len;
        try results.append(allocator, result_ty);
        try items.append(allocator, .{ .ty = result_ty, .abi_start = abi_start, .abi_len = 1 });
        i = parsed_ty.next_idx;
        if (i < end_idx and tokEq(tokens[i], ",")) i += 1;
    }

    var result_struct: ?[]const u8 = null;
    if (items.items.len == 1 and isTupleTypeName(items.items[0].ty) and items.items[0].abi_len >= 2) {
        result_struct = items.items[0].ty;
    }

    return .{
        .types = try results.toOwnedSlice(allocator),
        .items = try items.toOwnedSlice(allocator),
        .result_struct = result_struct,
    };
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
    var items = std.ArrayList(FuncResultItem).empty;
    errdefer items.deinit(allocator);

    if (start_idx + 1 == end_idx and tokEq(tokens[start_idx], "nil")) {
        return .{
            .types = try results.toOwnedSlice(allocator),
            .items = try items.toOwnedSlice(allocator),
        };
    }

    if (try parseGenericInlineUnionLayout(allocator, tokens, start_idx, end_idx, type_params, structs, struct_layouts, owned_types)) |layout| {
        const abi_start = results.items.len;
        for (layout.payload_tys) |payload_ty| {
            try results.append(allocator, payload_ty);
        }
        try results.append(allocator, "i32");
        try items.append(allocator, .{
            .ty = layout.source_ty,
            .abi_start = abi_start,
            .abi_len = layout.payload_tys.len + 1,
            .union_layout = layout,
        });
        return .{
            .types = try results.toOwnedSlice(allocator),
            .items = try items.toOwnedSlice(allocator),
            .result_union = layout,
        };
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
        try items.append(allocator, .{ .ty = result_ty, .abi_start = results.items.len - 1, .abi_len = 1 });
        i = parsed_ty.next_idx;
        if (i < end_idx and tokEq(tokens[i], ",")) i += 1;
    }

    return .{
        .types = try results.toOwnedSlice(allocator),
        .items = try items.toOwnedSlice(allocator),
    };
}

fn parseGenericInlineUnionLayout(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    type_params: []const []const u8,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    owned_types: *std.ArrayList([]const u8),
) !?UnionLayout {
    if (!hasTopLevelToken(tokens, start_idx, end_idx, "|")) return null;

    var branches = std.ArrayList(UnionBranch).empty;
    errdefer branches.deinit(allocator);
    var payload_tys = std.ArrayList([]const u8).empty;
    errdefer payload_tys.deinit(allocator);

    var next_non_nil_tag: usize = 1;
    var branch_start = start_idx;
    while (branch_start < end_idx) {
        if (tokEq(tokens[branch_start], "|")) {
            branch_start += 1;
            continue;
        }

        const branch_end = findTopLevelToken(tokens, branch_start, end_idx, "|") orelse end_idx;
        if (branch_end == branch_start) return null;
        const payload_start = payload_tys.items.len;

        if (branch_end == branch_start + 1 and tokEq(tokens[branch_start], "nil")) {
            try branches.append(allocator, .{
                .ty = "nil",
                .tag = 0,
                .payload_start = payload_start,
                .payload_len = 0,
            });
        } else {
            const parsed_ty = (try parseCodegenTypeExpr(allocator, tokens, branch_start, branch_end, owned_types)) orelse return null;
            if (parsed_ty.next_idx != branch_end) return null;
            if (hasTypeParamName(type_params, parsed_ty.ty)) {
                try payload_tys.append(allocator, parsed_ty.ty);
            } else {
                try appendUnionBranchPayloadTypes(allocator, tokens, parsed_ty.ty, structs, struct_layouts, &payload_tys);
            }
            try branches.append(allocator, .{
                .ty = parsed_ty.ty,
                .tag = next_non_nil_tag,
                .payload_start = payload_start,
                .payload_len = payload_tys.items.len - payload_start,
            });
            next_non_nil_tag += 1;
        }

        branch_start = branch_end;
        if (branch_start < end_idx and tokEq(tokens[branch_start], "|")) branch_start += 1;
    }

    if (branches.items.len < 2) return null;
    const source_ty = try compactTokenText(allocator, tokens, start_idx, end_idx);
    errdefer allocator.free(source_ty);
    try owned_types.append(allocator, source_ty);

    return .{
        .source_ty = source_ty,
        .branches = try branches.toOwnedSlice(allocator),
        .payload_tys = try payload_tys.toOwnedSlice(allocator),
    };
}

fn hasTypeParamName(type_params: []const []const u8, name: []const u8) bool {
    for (type_params) |type_param| {
        if (std.mem.eql(u8, type_param, name)) return true;
    }
    return false;
}

fn typeParamsAppearInRange(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    type_params: []const []const u8,
) bool {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (hasTypeParamName(type_params, tokens[i].lexeme)) return true;
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

fn parseUnionTypeLayout(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    imported_alias_ctx: ?ImportedAliasContext,
    owned_types: *std.ArrayList([]const u8),
) !?UnionLayout {
    const range = unionTypeExprRange(allocator, tokens, start_idx, end_idx, imported_alias_ctx) orelse return null;
    return try parseInlineUnionLayout(allocator, range.tokens, range.start, range.end, structs, struct_layouts, owned_types);
}

fn unionTypeExprRange(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    imported_alias_ctx: ?ImportedAliasContext,
) ?TokenRange {
    if (hasTopLevelToken(tokens, start_idx, end_idx, "|")) return .{ .tokens = tokens, .start = start_idx, .end = end_idx };
    if (start_idx + 1 != end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (localUnionAliasRange(tokens, tokens[start_idx].lexeme)) |range| {
        return .{ .tokens = tokens, .start = range.start, .end = range.end };
    }
    return importedUnionAliasRange(allocator, imported_alias_ctx, tokens, tokens[start_idx].lexeme);
}

fn localUnionAliasRange(tokens: []const lexer.Token, name: []const u8) ?Range {
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
        if (!isLineStart(tokens, i)) continue;
        if (tokens[i].kind != .ident or !std.mem.eql(u8, tokens[i].lexeme, name)) continue;
        if (!tokEq(tokens[i + 1], "=")) continue;
        const line_end = findLineEnd(tokens, i);
        const rhs_start = i + 2;
        if (!hasTopLevelToken(tokens, rhs_start, line_end, "|")) return null;
        return .{ .start = rhs_start, .end = line_end };
    }
    return null;
}

fn importedUnionAliasRange(
    allocator: std.mem.Allocator,
    imported_alias_ctx: ?ImportedAliasContext,
    tokens: []const lexer.Token,
    name: []const u8,
) ?TokenRange {
    const ctx = importedAliasContextForTokens(imported_alias_ctx, tokens) orelse return null;
    const import_ref = findCodegenImportByAlias(tokens, name) orelse return null;
    const child_idx = findImportedModuleIndex(allocator, ctx.graph, ctx.module_idx, import_ref) orelse return null;
    const child_tokens = ctx.graph.modules[child_idx].tokens;
    const range = localUnionAliasRange(child_tokens, import_ref.target) orelse return null;
    return .{ .tokens = child_tokens, .start = range.start, .end = range.end };
}

fn importedAliasContextForTokens(imported_alias_ctx: ?ImportedAliasContext, tokens: []const lexer.Token) ?ImportedAliasContext {
    const ctx = imported_alias_ctx orelse return null;
    const module_idx = findRootModuleIndex(ctx.graph.modules, tokens) orelse ctx.module_idx;
    return .{ .graph = ctx.graph, .module_idx = module_idx };
}

fn parseInlineUnionLayout(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    owned_types: *std.ArrayList([]const u8),
) !?UnionLayout {
    if (!hasTopLevelToken(tokens, start_idx, end_idx, "|")) return null;

    var branches = std.ArrayList(UnionBranch).empty;
    errdefer branches.deinit(allocator);
    var payload_tys = std.ArrayList([]const u8).empty;
    errdefer payload_tys.deinit(allocator);

    var next_non_nil_tag: usize = 1;
    var branch_start = start_idx;
    while (branch_start < end_idx) {
        if (tokEq(tokens[branch_start], "|")) {
            branch_start += 1;
            continue;
        }

        const branch_end = findTopLevelToken(tokens, branch_start, end_idx, "|") orelse end_idx;
        if (branch_end == branch_start) return null;
        const payload_start = payload_tys.items.len;

        if (branch_end == branch_start + 1 and tokEq(tokens[branch_start], "nil")) {
            try branches.append(allocator, .{
                .ty = "nil",
                .tag = 0,
                .payload_start = payload_start,
                .payload_len = 0,
            });
        } else {
            const parsed_ty = (try parseCodegenTypeExpr(allocator, tokens, branch_start, branch_end, owned_types)) orelse return null;
            if (parsed_ty.next_idx != branch_end) return null;
            try appendUnionBranchPayloadTypes(allocator, tokens, parsed_ty.ty, structs, struct_layouts, &payload_tys);
            try branches.append(allocator, .{
                .ty = parsed_ty.ty,
                .tag = next_non_nil_tag,
                .payload_start = payload_start,
                .payload_len = payload_tys.items.len - payload_start,
            });
            next_non_nil_tag += 1;
        }

        branch_start = branch_end;
        if (branch_start < end_idx and tokEq(tokens[branch_start], "|")) branch_start += 1;
    }

    if (branches.items.len < 2) return null;
    const source_ty = try compactTokenText(allocator, tokens, start_idx, end_idx);
    errdefer allocator.free(source_ty);
    try owned_types.append(allocator, source_ty);

    return .{
        .source_ty = source_ty,
        .branches = try branches.toOwnedSlice(allocator),
        .payload_tys = try payload_tys.toOwnedSlice(allocator),
    };
}

fn appendUnionBranchPayloadTypes(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    ty: []const u8,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    out: *std.ArrayList([]const u8),
) !void {
    if (findStructDecl(structs, ty)) |decl| {
        if (findStructLayout(struct_layouts, ty) == null) {
            for (decl.fields) |field| try out.append(allocator, field.ty);
            return;
        }
    }
    if (isCoreWasmScalar(ty) or isErrorLikeType(tokens, ty) or managedPayloadElemTypeFromName(ty) != null or findStructLayout(struct_layouts, ty) != null) {
        try out.append(allocator, ty);
        return;
    }
    return error.NoMatchingCall;
}

fn hasTopLevelToken(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, lexeme: []const u8) bool {
    return findTopLevelToken(tokens, start_idx, end_idx, lexeme) != null;
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
    const child_idx = findImportedModuleIndex(allocator, ctx.graph, ctx.module_idx, import_ref) orelse return null;
    return errorNilAliasTarget(ctx.graph.modules[child_idx].tokens, import_ref.target);
}

fn importedErrorBranchValue(
    allocator: std.mem.Allocator,
    imported_alias_ctx: ?ImportedAliasContext,
    tokens: []const lexer.Token,
    name: []const u8,
    enum_name: []const u8,
) ?usize {
    const ctx = imported_alias_ctx orelse return null;
    const import_ref = findCodegenImportByAlias(tokens, name) orelse return null;
    const child_idx = findImportedModuleIndex(allocator, ctx.graph, ctx.module_idx, import_ref) orelse return null;
    return errorEnumBranchValue(ctx.graph.modules[child_idx].tokens, enum_name, import_ref.target);
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
        var j = i + 3;
        // Skip declarative `@wasi_enum("target", …)` prefix when present.
        if (j < line_end and tokEq(tokens[j], "@") and j + 2 < line_end and
            tokens[j + 1].kind == .ident and std.mem.eql(u8, tokens[j + 1].lexeme, "wasi_enum") and
            tokEq(tokens[j + 2], "("))
        {
            const close_call = findMatchingInRange(tokens, j + 2, "(", ")", line_end) catch return null;
            // Arms start after optional target string and comma inside the call.
            j = j + 3;
            while (j < close_call) : (j += 1) {
                if (tokEq(tokens[j], ",")) {
                    j += 1;
                    break;
                }
            }
            const arms_end = close_call;
            var branch_idx: usize = 1;
            while (j < arms_end) : (j += 1) {
                if (tokEq(tokens[j], "|") or tokEq(tokens[j], ",")) continue;
                // Optional explicit discr: Name(1)
                if (tokens[j].kind != .ident) return null;
                const arm = tokens[j].lexeme;
                if (j + 3 < arms_end and tokEq(tokens[j + 1], "(") and tokens[j + 2].kind == .number and tokEq(tokens[j + 3], ")")) {
                    // Explicit status/discr value — still identity by name for @eq.
                    if (std.mem.eql(u8, arm, branch_name)) return branch_idx;
                    j += 3;
                    branch_idx += 1;
                    continue;
                }
                if (std.mem.eql(u8, arm, branch_name)) return branch_idx;
                branch_idx += 1;
            }
            return null;
        }

        var branch_idx: usize = 1;
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

fn freeValueEnumDecls(allocator: std.mem.Allocator, value_enums: []const ValueEnumDecl) void {
    for (value_enums) |decl| {
        if (decl.owned_name) allocator.free(decl.name);
        allocator.free(decl.branches);
    }
}

fn freeStructLayouts(allocator: std.mem.Allocator, layouts: []const StructLayout) void {
    for (layouts) |layout| {
        if (layout.owned_name) allocator.free(layout.name);
        allocator.free(layout.managed_fields);
    }
}

fn freeFuncParams(allocator: std.mem.Allocator, params: []const FuncParam) void {
    for (params) |param| {
        if (param.callback) |callback| {
            if (callback.owned) allocator.free(callback.shape.param_types);
        }
    }
    allocator.free(params);
}

fn freeFuncDecls(allocator: std.mem.Allocator, funcs: []const FuncDecl) void {
    for (funcs) |func| {
        if (func.owned_name) allocator.free(func.name);
        if (func.type_params.len != 0) allocator.free(func.type_params);
        if (func.type_bindings.len != 0) allocator.free(func.type_bindings);
        if (func.callback_bindings.len != 0) freeCallbackBindings(allocator, func.callback_bindings);
        freeFuncResultItems(allocator, func.result_items, func.result_union);
        for (func.owned_types) |owned| {
            allocator.free(owned);
        }
        if (func.owned_types.len != 0) allocator.free(func.owned_types);
        freeFuncParams(allocator, func.params);
        allocator.free(func.results);
    }
}

fn freeFuncResultItems(allocator: std.mem.Allocator, items: []const FuncResultItem, result_union: ?UnionLayout) void {
    for (items) |item| {
        const layout = item.union_layout orelse continue;
        if (result_union) |single_layout| {
            if (unionLayoutsEqual(layout, single_layout)) continue;
        }
        freeUnionLayout(allocator, layout);
    }
    if (result_union) |layout| freeUnionLayout(allocator, layout);
    allocator.free(items);
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
    return null;
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
    return component_metadata_wat.wasiLowering(import);
}

fn appendWasiImportSymbol(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    target: []const u8,
) !void {
    try component_metadata_wat.appendWasiImportSymbol(allocator, out, target);
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
    if (tokens[idx + 3].kind != .ident) return false;
    const kind = tokens[idx + 3].lexeme;
    if (!std.mem.eql(u8, kind, "wasi_func")) return false;
    return tokEq(tokens[idx + 4], "(");
}

/// Canonical WIT params/result for known targets (codegen always stores WIT form).
fn knownWasiWitSignature(target: []const u8) ?struct { params: []const u8, result: []const u8 } {
    const known = [_]struct { target: []const u8, params: []const u8, result: []const u8 }{
        .{ .target = "filesystem/types/descriptor.write", .params = "descriptor,list<u8>,filesize", .result = "result<filesize,error-code>" },
        .{ .target = "filesystem/types/descriptor.read", .params = "descriptor,filesize,filesize", .result = "result<tuple<list<u8>,bool>,error-code>" },
        .{ .target = "filesystem/types/descriptor.sync", .params = "descriptor", .result = "result<_,error-code>" },
        .{ .target = "filesystem/types/descriptor.link-at", .params = "descriptor,path-flags,text,borrow<descriptor>,text", .result = "result<_,error-code>" },
        .{ .target = "filesystem/types/descriptor.create-directory-at", .params = "descriptor,text", .result = "result<_,error-code>" },
        .{ .target = "filesystem/types/descriptor.open-at", .params = "descriptor,path-flags,text,open-flags,descriptor-flags", .result = "result<descriptor,error-code>" },
        .{ .target = "filesystem/types/descriptor.remove-directory-at", .params = "descriptor,text", .result = "result<_,error-code>" },
        .{ .target = "filesystem/types/descriptor.drop", .params = "descriptor", .result = "nil" },
        .{ .target = "filesystem/preopens/get-directories", .params = "", .result = "list<tuple<descriptor,text>>" },
        .{ .target = "io/streams/input-stream.read", .params = "input-stream,u64", .result = "result<list<u8>,stream-error>" },
        .{ .target = "io/streams/output-stream.check-write", .params = "output-stream", .result = "result<u64,stream-error>" },
        .{ .target = "io/streams/output-stream.write", .params = "output-stream,list<u8>", .result = "result<_,stream-error>" },
        .{ .target = "io/streams/output-stream.flush", .params = "output-stream", .result = "result<_,stream-error>" },
        .{ .target = "clocks/system-clock/now", .params = "", .result = "Datetime" },
        .{ .target = "clocks/system-clock/get-resolution", .params = "", .result = "u64" },
        .{ .target = "clocks/monotonic-clock/now", .params = "", .result = "u64" },
        .{ .target = "clocks/monotonic-clock/get-resolution", .params = "", .result = "u64" },
        .{ .target = "random/random/get-random-bytes", .params = "u64", .result = "list<u8>" },
        .{ .target = "random/random/get-random-u64", .params = "", .result = "u64" },
    };
    for (known) |item| {
        if (std.mem.eql(u8, item.target, target)) return .{ .params = item.params, .result = item.result };
    }
    return null;
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

fn isStringLiteralArg(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    return stringLiteralArgLexeme(tokens, start_idx, end_idx) != null;
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

fn stmtContainsStorageComparisonIntrinsic(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (!tokEq(tokens[i], "@")) continue;
        if (tokens[i + 1].kind != .ident) continue;
        const name = tokens[i + 1].lexeme;
        if (std.mem.eql(u8, name, "eq") or std.mem.eql(u8, name, "ne")) return true;
    }
    return false;
}

fn stmtContainsFieldNameIntrinsic(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (!tokEq(tokens[i], "@")) continue;
        if (tokens[i + 1].kind != .ident) continue;
        if (std.mem.eql(u8, tokens[i + 1].lexeme, "field_name")) return true;
    }
    return false;
}

fn stmtContainsGetIntrinsic(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (!tokEq(tokens[i], "@")) continue;
        if (tokens[i + 1].kind != .ident) continue;
        if (std.mem.eql(u8, tokens[i + 1].lexeme, "get") or
            std.mem.eql(u8, tokens[i + 1].lexeme, "field_get")) return true;
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

const TokenRange = struct {
    tokens: []const lexer.Token,
    start: usize,
    end: usize,
};

const ExprCallHead = struct {
    name_idx: usize,
    type_args_start: usize = 0,
    type_args_end: usize = 0,
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
    if (name_idx + 1 >= range.end) return null;
    var open_paren = name_idx + 1;
    var type_args_start: usize = 0;
    var type_args_end: usize = 0;
    if (tokEq(tokens[open_paren], "<")) {
        if (is_intrinsic) return null;
        const close_angle = findMatchingInRange(tokens, open_paren, "<", ">", range.end) catch return null;
        if (close_angle + 1 >= range.end or !tokEq(tokens[close_angle + 1], "(")) return null;
        type_args_start = open_paren + 1;
        type_args_end = close_angle;
        open_paren = close_angle + 1;
    } else if (!tokEq(tokens[open_paren], "(")) {
        return null;
    }

    const close_paren = findMatchingInRange(tokens, open_paren, "(", ")", range.end) catch return null;
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

fn callHeadAt(tokens: []const lexer.Token, idx: usize, limit: usize) ?ExprCallHead {
    if (idx >= limit) return null;

    var name_idx = idx;
    var is_intrinsic = false;
    if (tokEq(tokens[name_idx], "@")) {
        name_idx += 1;
        if (name_idx >= limit) return null;
        is_intrinsic = true;
    } else if (idx > 0 and tokEq(tokens[idx - 1], "@") and tokens[idx - 1].line == tokens[idx].line) {
        return null;
    }

    if (tokens[name_idx].kind != .ident) return null;
    if (name_idx + 1 >= limit) return null;

    var open_paren = name_idx + 1;
    var type_args_start: usize = 0;
    var type_args_end: usize = 0;
    if (tokEq(tokens[open_paren], "<")) {
        if (is_intrinsic) return null;
        const close_angle = findMatchingInRange(tokens, open_paren, "<", ">", limit) catch return null;
        if (close_angle + 1 >= limit or !tokEq(tokens[close_angle + 1], "(")) return null;
        type_args_start = open_paren + 1;
        type_args_end = close_angle;
        open_paren = close_angle + 1;
    } else if (!tokEq(tokens[open_paren], "(")) {
        return null;
    }

    const close_paren = findMatchingInRange(tokens, open_paren, "(", ")", limit) catch return null;
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

fn callHeadHasTypeArgs(call_head: ExprCallHead) bool {
    return call_head.type_args_start != 0 or call_head.type_args_end != 0;
}

fn isTypedScalarBinding(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext) bool {
    return typedScalarBindingType(tokens, start_idx, end_idx, ctx) != null;
}

fn typedScalarBindingType(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext) ?[]const u8 {
    if (start_idx + 3 >= end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    const ty = substituteGenericType(tokens[start_idx + 1].lexeme, ctx.type_bindings);
    if (!isCodegenScalarOrErrorType(tokens, ctx, ty)) return null;
    if (findTopLevelToken(tokens, start_idx + 2, end_idx, "=") == null) return null;
    return ty;
}

fn typedUnionBindingLayout(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    owned_types: *std.ArrayList([]const u8),
) CodegenError!?UnionLayout {
    if (start_idx + 3 >= end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return null;
    if (eq_idx <= start_idx + 1) return null;
    return try parseUnionTypeLayout(
        allocator,
        tokens,
        start_idx + 1,
        eq_idx,
        ctx.structs,
        ctx.struct_layouts,
        importedAliasContextForTokens(ctx.imported_alias_ctx, tokens),
        owned_types,
    );
}

fn inferredUnionCallBinding(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    owned_types: *std.ArrayList([]const u8),
) CodegenError!?InferredUnionBinding {
    if (start_idx + 3 > end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (!tokEq(tokens[start_idx + 1], "=")) return null;
    const range = trimParens(tokens, start_idx + 2, end_idx);
    const call_head = exprCallHead(tokens, range) orelse return null;
    if (call_head.is_intrinsic) return null;
    if (findFuncDeclForCallHead(tokens, call_head, locals, ctx)) |func| {
        if (func.result_union) |layout| {
            return .{ .layout = layout, .owns_layout = false };
        }
        return null;
    }
    if (try inferGenericCallUnionResultLayout(allocator, tokens, call_head, locals, ctx, owned_types)) |layout| {
        return .{ .layout = layout, .owns_layout = true };
    }
    return null;
}

fn inferGenericCallUnionResultLayout(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    call_head: ExprCallHead,
    locals: *const LocalSet,
    ctx: CodegenContext,
    result_owned_types: *std.ArrayList([]const u8),
) CodegenError!?UnionLayout {
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

fn emitUnionBinding(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (start_idx + 3 > end_idx) return false;
    if (tokens[start_idx].kind != .ident) return false;
    const union_local = findUnionLocal(locals.union_locals.items, tokens[start_idx].lexeme) orelse return false;
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return false;
    const move_ctx = CallLastUseMoveContext{
        .stmt_end = end_idx,
        .body_end = body_end,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = allow_last_use_move,
    };
    const rhs_range = trimParens(tokens, eq_idx + 1, end_idx);
    if (exprCallHead(tokens, rhs_range)) |call_head| {
        if (!call_head.is_intrinsic) {
            if (findFuncDeclForCallHead(tokens, call_head, locals, ctx)) |func| {
                if (func.result_union) |func_union| {
                    if (unionLayoutsAbiCompatible(ctx, func_union, union_local.layout)) {
                        if (!try emitUserFuncCallWithUnionBindingMove(
                            allocator,
                            tokens,
                            call_head.args_start,
                            call_head.args_end,
                            end_idx,
                            body_end,
                            allow_last_use_move,
                            locals,
                            defer_ctx,
                            ctx,
                            func,
                            out,
                        )) {
                            return error.NoMatchingCall;
                        }
                        var call_idx = union_local.layout.payload_tys.len + 1;
                        while (call_idx > 0) {
                            call_idx -= 1;
                            if (call_idx == union_local.layout.payload_tys.len) {
                                try appendUnionTagLocalSet(allocator, out, union_local.name);
                            } else {
                                try appendUnionPayloadLocalSet(allocator, out, union_local.name, call_idx);
                            }
                        }
                        return true;
                    }
                }
            }
            // Unit fallible host (`result<_,error-code>`) → exclusive `nil | i32` union.
            if (findWasiHostImportForTokens(ctx, tokens, tokens[call_head.name_idx].lexeme)) |wasi_import| {
                if (try emitWasiUnitResultAsUnionValue(
                    allocator,
                    tokens,
                    call_head.args_start,
                    call_head.args_end,
                    locals,
                    ctx,
                    wasi_import,
                    union_local.layout,
                    out,
                )) {
                    var wasi_idx = union_local.layout.payload_tys.len + 1;
                    while (wasi_idx > 0) {
                        wasi_idx -= 1;
                        if (wasi_idx == union_local.layout.payload_tys.len) {
                            try appendUnionTagLocalSet(allocator, out, union_local.name);
                        } else {
                            try appendUnionPayloadLocalSet(allocator, out, union_local.name, wasi_idx);
                        }
                    }
                    return true;
                }
            }
        }
    }
    if (!try emitUnionValue(allocator, tokens, eq_idx + 1, end_idx, locals, ctx, union_local.layout, true, &move_ctx, out)) {
        return error.NoMatchingCall;
    }
    var idx = union_local.layout.payload_tys.len + 1;
    while (idx > 0) {
        idx -= 1;
        if (idx == union_local.layout.payload_tys.len) {
            try appendUnionTagLocalSet(allocator, out, union_local.name);
        } else {
            try appendUnionPayloadLocalSet(allocator, out, union_local.name, idx);
        }
    }
    return true;
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
    if (!isCodegenScalarType(ctx, ty)) return null;
    return ty;
}

fn typedTupleBindingType(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    owned_types: *std.ArrayList([]const u8),
) CodegenError!?[]const u8 {
    if (start_idx + 3 >= end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return null;
    if (eq_idx <= start_idx + 1) return null;
    const parsed_ty = (try parseCodegenTypeExpr(allocator, tokens, start_idx + 1, eq_idx, owned_types)) orelse return null;
    if (parsed_ty.next_idx != eq_idx) return null;
    const ty = try substituteGenericTypeOwned(allocator, parsed_ty.ty, ctx.type_bindings, owned_types);
    if (!isTupleTypeName(ty)) return null;
    return ty;
}

fn appendTupleLocalFields(
    allocator: std.mem.Allocator,
    out: *LocalSet,
    tokens: []const lexer.Token,
    ctx: CodegenContext,
    base: []const u8,
    tuple_ty: []const u8,
) CodegenError!void {
    const arity = tupleArity(tuple_ty) orelse return error.UnsupportedLowering;
    var idx: usize = 0;
    while (idx < arity) : (idx += 1) {
        const elem_ty = tupleElementTypeAt(tuple_ty, idx) orelse return error.UnsupportedLowering;
        var field_buf: [32]u8 = undefined;
        const field_name = try std.fmt.bufPrint(&field_buf, "{d}", .{idx});
        try appendLocalField(allocator, out, tokens, ctx, base, field_name, elem_ty);
    }
}

fn appendTupleLocalFieldsBorrowed(
    allocator: std.mem.Allocator,
    out: *LocalSet,
    tokens: []const lexer.Token,
    ctx: CodegenContext,
    base: []const u8,
    tuple_ty: []const u8,
) CodegenError!void {
    const arity = tupleArity(tuple_ty) orelse return error.UnsupportedLowering;
    var idx: usize = 0;
    while (idx < arity) : (idx += 1) {
        const elem_ty = tupleElementTypeAt(tuple_ty, idx) orelse return error.UnsupportedLowering;
        var field_buf: [32]u8 = undefined;
        const field_name = try std.fmt.bufPrint(&field_buf, "{d}", .{idx});
        try appendBorrowedLocalField(allocator, out, tokens, ctx, base, field_name, elem_ty);
    }
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

fn typedManagedPayloadBinding(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    owned_types: *std.ArrayList([]const u8),
) CodegenError!?ManagedPayloadBinding {
    if (start_idx + 3 >= end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return null;
    if (eq_idx <= start_idx + 1) return null;
    const parsed = (try parseCodegenTypeExpr(allocator, tokens, start_idx + 1, eq_idx, owned_types)) orelse return null;
    if (parsed.next_idx != eq_idx) return null;
    const ty = try substituteGenericTypeOwned(allocator, parsed.ty, ctx.type_bindings, owned_types);
    const elem_ty = managedPayloadElemTypeFromName(ty) orelse return null;
    return .{ .ty = ty, .elem_ty = elem_ty };
}

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
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    owned_types: *std.ArrayList([]const u8),
) CodegenError!?TypedStructBinding {
    if (start_idx + 3 >= end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return null;
    if (eq_idx <= start_idx + 1) return null;
    const parsed_ty = (try parseCodegenTypeExpr(allocator, tokens, start_idx + 1, eq_idx, owned_types)) orelse return null;
    if (parsed_ty.next_idx != eq_idx) return null;
    const ty = try substituteGenericTypeOwned(allocator, parsed_ty.ty, ctx.type_bindings, owned_types);
    const decl = findStructDecl(ctx.structs, ty) orelse return null;
    return .{ .decl = decl, .ty = ty };
}

fn typedStructBindingDecl(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
) CodegenError!?StructDecl {
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    const binding = (try typedStructBinding(allocator, tokens, start_idx, end_idx, ctx, &owned_types)) orelse return null;
    return binding.decl;
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

fn inferredStructBinding(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?TypedStructBinding {
    if (start_idx + 3 > end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (!tokEq(tokens[start_idx + 1], "=")) return null;
    const ty = inferExprType(tokens, start_idx + 2, end_idx, locals, ctx) orelse return null;
    const decl = findStructDecl(ctx.structs, ty) orelse return null;
    return .{ .decl = decl, .ty = ty };
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
    const storage_name = findStorageReadableLocalName(tokens, locals, tokens[start_idx].lexeme) orelse return false;
    try emitStorageLenPtr(allocator, out, storage_name);
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
    move_ctx: ?*const CallLastUseMoveContext,
    out: *std.ArrayList(u8),
) !bool {
    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (first_end >= end_idx or !tokEq(tokens[first_end], ",")) return false;
    const second_start = first_end + 1;
    const second_end = findArgEnd(tokens, second_start, end_idx);
    if (try emitTupleFieldPathGetCall(allocator, tokens, start_idx, end_idx, first_end, locals, ctx, out)) {
        return true;
    }
    if (second_end != end_idx) {
        return try emitPathGetCall(allocator, tokens, start_idx, end_idx, first_end, locals, ctx, out);
    }

    if (try emitManagedStructExprFieldGet(allocator, tokens, start_idx, first_end, second_start, second_end, locals, ctx, out)) {
        return true;
    }

    if (first_end != start_idx + 1 or tokens[start_idx].kind != .ident) {
        const storage_ty = inferExprType(tokens, start_idx, first_end, locals, ctx) orelse return false;
        const elem_ty = storageElemTypeFromName(storage_ty) orelse return false;
        const elem_bytes = storageElementByteWidthForType(elem_ty, ctx) orelse return false;
        if (!try emitExpr(allocator, tokens, start_idx, first_end, locals, ctx, storage_ty, out)) return false;
        try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
        try emitStorageBoundsCheck(allocator, tokens, second_start, second_end, locals, ctx, STORAGE_PUT_SOURCE_TMP_LOCAL, 1, out);
        if (isTupleTypeName(elem_ty)) {
            try emitStorageDataPtr(allocator, out, STORAGE_PUT_SOURCE_TMP_LOCAL);
            if (!try emitExpr(allocator, tokens, second_start, second_end, locals, ctx, "usize", out)) return false;
            if (elem_bytes != 1) {
                try appendFmt(allocator, out, "    i32.const {d}\n", .{elem_bytes});
                try out.appendSlice(allocator, "    i32.mul\n");
            }
            try out.appendSlice(allocator, "    i32.add\n");
            try appendFmt(allocator, out, "    local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
            try appendLoadTupleLeavesOwningToStackCtx(allocator, out, elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "    ", ctx);
        } else {
            try emitStorageDataPtr(allocator, out, STORAGE_PUT_SOURCE_TMP_LOCAL);
            if (!try emitExpr(allocator, tokens, second_start, second_end, locals, ctx, "usize", out)) return false;
            if (elem_bytes != 1) {
                try appendFmt(allocator, out, "    i32.const {d}\n", .{elem_bytes});
                try out.appendSlice(allocator, "    i32.mul\n");
            }
            try out.appendSlice(allocator, "    i32.add\n");
            try appendLoadForPayloadType(allocator, out, elem_ty);
            if (isManagedLocalType(elem_ty, ctx)) {
                try out.appendSlice(allocator, "    ;; storage-managed-get-inc\n");
                try out.appendSlice(allocator, "    call $__arc_inc\n");
            }
        }
        return true;
    }

    const name = tokens[start_idx].lexeme;

    if (try emitUnionStoragePayloadGetCall(allocator, tokens, name, second_start, second_end, locals, ctx, out)) {
        return true;
    }

    if (findStoragePrimitiveLocal(locals.storage_locals.items, name)) |storage| {
        const elem_bytes = storageElementByteWidthForType(storage.elem_ty, ctx) orelse return false;
        try emitStorageBoundsCheck(allocator, tokens, second_start, second_end, locals, ctx, name, 1, out);
        if (isTupleTypeName(storage.elem_ty)) {
            try emitStorageDataPtr(allocator, out, name);
            if (!try emitExpr(allocator, tokens, second_start, second_end, locals, ctx, "usize", out)) return false;
            if (elem_bytes != 1) {
                try appendFmt(allocator, out, "    i32.const {d}\n", .{elem_bytes});
                try out.appendSlice(allocator, "    i32.mul\n");
            }
            try out.appendSlice(allocator, "    i32.add\n");
            try appendFmt(allocator, out, "    local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
            try appendLoadTupleLeavesOwningToStackCtx(allocator, out, storage.elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "    ", ctx);
        } else {
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
                try out.appendSlice(allocator, "    call $__arc_inc\n");
            }
        }
        return true;
    }

    if (findStructLocal(locals.struct_locals.items, name)) |struct_local| {
        if (isTupleTypeName(struct_local.ty)) {
            const elem_info = tupleGetElementInfo(tokens, second_start, second_end, struct_local.ty) orelse return false;
            if (isTupleTypeName(elem_info.ty)) {
                const nested_base = try std.fmt.allocPrint(allocator, "{s}.{d}", .{ struct_local.name, elem_info.index });
                defer allocator.free(nested_base);
                try emitTupleLocalGet(allocator, nested_base, elem_info.ty, ctx, out);
                return true;
            }
            if (findStructDecl(ctx.structs, elem_info.ty)) |decl| {
                if (findStructLayout(ctx.struct_layouts, elem_info.ty) == null and pureScalarStructPackWidth(decl, ctx.structs) != null) {
                    const nested_base = try std.fmt.allocPrint(allocator, "{s}.{d}", .{ struct_local.name, elem_info.index });
                    defer allocator.free(nested_base);
                    try emitPureScalarStructLocalGet(allocator, nested_base, decl, out);
                    return true;
                }
            }
            try appendFmt(allocator, out, "    local.get ${s}.{d}\n", .{ struct_local.name, elem_info.index });
            if (isManagedLocalType(elem_info.ty, ctx)) {
                try out.appendSlice(allocator, "    call $__arc_inc\n");
            }
            return true;
        }
    }

    if (findStructLocal(locals.struct_locals.items, name)) |struct_local| {
        if (second_end != second_start + 1 or !isDotIdent(tokens[second_start].lexeme)) return false;
        const field_name = publicDeclName(tokens[second_start].lexeme);
        if (findStructLayout(ctx.struct_layouts, struct_local.ty)) |layout| {
            const decl = findStructDecl(ctx.structs, struct_local.ty) orelse return false;
            const field_ty = findLocalFieldType(locals.locals.items, struct_local.name, field_name) orelse
                findStructFieldType(decl, field_name) orelse return false;
            const field_offset = structFieldPayloadOffset(decl, field_name) orelse return false;
            const move_source = if (move_ctx) |ctx_info|
                try fieldGetLastUseMoveSource(allocator, tokens, start_idx, end_idx, struct_local, field_ty, ctx_info.*, locals, ctx)
            else
                null;
            try appendFmt(allocator, out, "    local.get ${s}\n", .{struct_local.name});
            try out.appendSlice(allocator, "    call $__arc_payload\n");
            try appendFmt(allocator, out, "    i32.const {d}\n", .{field_offset});
            try out.appendSlice(allocator, "    i32.add\n");
            try appendLoadForPayloadType(allocator, out, field_ty);
            if (isManagedStructField(layout, field_name) and move_source == null) {
                try out.appendSlice(allocator, "    call $__arc_inc\n");
            }
            if (move_source) |source| {
                try appendFmt(allocator, out, "    ;; field-get-move {s}.{s}\n", .{ source.source_name, field_name });
                try emitZeroValueForType(allocator, ctx, out, field_ty);
                try appendManagedStructFieldPtr(allocator, out, struct_local.name, field_offset);
                try appendStoreForPayloadType(allocator, out, field_ty);
            }
            return true;
        }
        const decl = findStructDecl(ctx.structs, struct_local.ty) orelse return false;
        const field_ty = findLocalFieldType(locals.locals.items, struct_local.name, field_name) orelse
            findStructFieldType(decl, field_name) orelse return false;
        if (try emitUnmanagedStructFieldGet(allocator, tokens, struct_local, field_name, field_ty, locals, ctx, out)) {
            return true;
        }
        try appendFmt(allocator, out, "    local.get ${s}.{s}\n", .{ struct_local.name, field_name });
        return true;
    }

    if (try emitUnionStructFieldGetCall(allocator, tokens, name, tokens[second_start], second_end == second_start + 1, locals, ctx, out)) {
        return true;
    }

    return false;
}

fn emitPathGetCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    first_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }

    var current = PathGetValue{
        .expr_start = start_idx,
        .expr_end = first_end,
        .ty = inferExprType(tokens, start_idx, first_end, locals, ctx) orelse return false,
        .local_name = null,
        .owned = false,
    };

    var segment_start = first_end + 1;
    while (segment_start < end_idx) {
        const segment_end = findArgEnd(tokens, segment_start, end_idx);
        if (segment_end == segment_start) return false;
        const has_more = segment_end < end_idx;
        if (has_more and !tokEq(tokens[segment_end], ",")) return false;

        const next_ty = if (try emitPathGetSegment(
            allocator,
            tokens,
            &current,
            segment_start,
            segment_end,
            has_more,
            locals,
            ctx,
            &owned_types,
            out,
        )) |ty| ty else return false;

        // Tuple path intermediate keeps packed base in $__tuple_pack_base_tmp (raw pointer, not managed).
        const next_local: ?[]const u8 = if (!has_more)
            null
        else if (isTupleTypeName(next_ty))
            TUPLE_PACK_BASE_TMP_LOCAL
        else
            STORAGE_OVERWRITE_TMP_LOCAL;
        current = .{
            .expr_start = 0,
            .expr_end = 0,
            .ty = next_ty,
            .local_name = next_local,
            .owned = has_more and next_local != null and
                std.mem.eql(u8, next_local.?, STORAGE_OVERWRITE_TMP_LOCAL) and
                isManagedLocalType(next_ty, ctx),
        };

        if (!has_more) return true;
        segment_start = segment_end + 1;
    }

    return false;
}

const PathGetValue = struct {
    expr_start: usize,
    expr_end: usize,
    ty: []const u8,
    local_name: ?[]const u8,
    owned: bool,
};

fn emitPathGetSegment(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    current: *PathGetValue,
    segment_start: usize,
    segment_end: usize,
    has_more: bool,
    locals: *const LocalSet,
    ctx: CodegenContext,
    owned_types: *std.ArrayList([]const u8),
    out: *std.ArrayList(u8),
) CodegenError!?[]const u8 {
    if (segment_end == segment_start + 1 and isDotIdent(tokens[segment_start].lexeme)) {
        return try emitPathGetFieldSegment(
            allocator,
            tokens,
            current,
            tokens[segment_start].lexeme,
            has_more,
            locals,
            ctx,
            owned_types,
            out,
        );
    }

    return try emitPathGetIndexSegment(
        allocator,
        tokens,
        current,
        segment_start,
        segment_end,
        has_more,
        locals,
        ctx,
        out,
    );
}

fn emitPathGetIndexSegment(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    current: *PathGetValue,
    index_start: usize,
    index_end: usize,
    has_more: bool,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!?[]const u8 {
    // Intermediate Tuple from prior path segment: index into packed leaves at base tmp.
    if (isTupleTypeName(current.ty) and current.local_name != null and
        std.mem.eql(u8, current.local_name.?, TUPLE_PACK_BASE_TMP_LOCAL))
    {
        const elem_info = tupleGetElementInfo(tokens, index_start, index_end, current.ty) orelse return null;
        if (has_more and isTupleTypeName(elem_info.ty)) {
            // Nested Tuple: advance base to sub-element start; keep pointer intermediate.
            const elem_offset = tupleElementPackOffsetWithStructs(current.ty, elem_info.index, ctx.structs) orelse return error.UnsupportedLowering;
            if (elem_offset != 0) {
                try appendFmt(allocator, out, "    local.get ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
                try appendFmt(allocator, out, "    i32.const {d}\n", .{elem_offset});
                try out.appendSlice(allocator, "    i32.add\n");
                try appendFmt(allocator, out, "    local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
            }
            return elem_info.ty;
        }
        // Nested pure-scalar struct slot: advance base for further field path segments.
        if (has_more and findStructDecl(ctx.structs, elem_info.ty) != null and
            findStructLayout(ctx.struct_layouts, elem_info.ty) == null and
            pureScalarStructPackWidth(findStructDecl(ctx.structs, elem_info.ty).?, ctx.structs) != null)
        {
            const elem_offset = tupleElementPackOffsetWithStructs(current.ty, elem_info.index, ctx.structs) orelse return error.UnsupportedLowering;
            if (elem_offset != 0) {
                try appendFmt(allocator, out, "    local.get ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
                try appendFmt(allocator, out, "    i32.const {d}\n", .{elem_offset});
                try out.appendSlice(allocator, "    i32.add\n");
                try appendFmt(allocator, out, "    local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
            }
            return elem_info.ty;
        }
        try appendLoadTupleElementOwningFromPackedBase(
            allocator,
            out,
            current.ty,
            elem_info.index,
            TUPLE_PACK_BASE_TMP_LOCAL,
            "    ",
            ctx,
        );
        if (has_more) {
            if (isTupleTypeName(elem_info.ty)) return error.UnsupportedLowering;
            try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
        }
        return elem_info.ty;
    }

    const elem_ty = storageElemTypeFromName(current.ty) orelse return null;
    const elem_bytes = storageElementByteWidthForType(elem_ty, ctx) orelse return null;
    const storage_name = try ensurePathGetCurrentLocal(allocator, tokens, current, locals, ctx, out);

    try emitStorageBoundsCheck(allocator, tokens, index_start, index_end, locals, ctx, storage_name, 1, out);
    if (isTupleTypeName(elem_ty)) {
        try emitStorageDataPtr(allocator, out, storage_name);
        if (!try emitExpr(allocator, tokens, index_start, index_end, locals, ctx, "usize", out)) return error.NoMatchingCall;
        if (elem_bytes != 1) {
            try appendFmt(allocator, out, "    i32.const {d}\n", .{elem_bytes});
            try out.appendSlice(allocator, "    i32.mul\n");
        }
        try out.appendSlice(allocator, "    i32.add\n");
        try appendFmt(allocator, out, "    local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
        try releasePathGetCurrentIfOwned(allocator, current.*, ctx, out);
        if (has_more) {
            // Keep packed element base for @get(storage, i, j) chaining.
            return elem_ty;
        }
        try appendLoadTupleLeavesOwningToStackCtx(allocator, out, elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "    ", ctx);
        return elem_ty;
    }
    try emitStorageDataPtr(allocator, out, storage_name);
    if (!try emitExpr(allocator, tokens, index_start, index_end, locals, ctx, "usize", out)) return error.NoMatchingCall;
    if (elem_bytes != 1) {
        try appendFmt(allocator, out, "    i32.const {d}\n", .{elem_bytes});
        try out.appendSlice(allocator, "    i32.mul\n");
    }
    try out.appendSlice(allocator, "    i32.add\n");
    try appendLoadForPayloadType(allocator, out, elem_ty);
    if (isManagedLocalType(elem_ty, ctx)) {
        try out.appendSlice(allocator, "    ;; path-storage-managed-get-inc\n");
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
    try releasePathGetCurrentIfOwned(allocator, current.*, ctx, out);
    if (has_more) {
        try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    }
    return elem_ty;
}

fn emitPathGetFieldSegment(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    current: *PathGetValue,
    dot_field: []const u8,
    has_more: bool,
    locals: *const LocalSet,
    ctx: CodegenContext,
    owned_types: *std.ArrayList([]const u8),
    out: *std.ArrayList(u8),
) CodegenError!?[]const u8 {
    const layout = findStructLayout(ctx.struct_layouts, current.ty) orelse return null;
    const decl = findStructDecl(ctx.structs, current.ty) orelse return null;
    const field_name = publicDeclName(dot_field);
    const field = findStructField(decl, field_name) orelse return null;
    const field_ty = try substituteStructFieldType(allocator, decl, current.ty, field.ty, owned_types);
    const field_offset = structFieldPayloadOffset(decl, field_name) orelse return null;
    const struct_name = try ensurePathGetCurrentLocal(allocator, tokens, current, locals, ctx, out);

    try appendManagedStructFieldPtr(allocator, out, struct_name, field_offset);
    try appendLoadForPayloadType(allocator, out, field_ty);
    if (isManagedStructField(layout, field_name)) {
        try out.appendSlice(allocator, "    ;; path-field-managed-get-inc\n");
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
    try releasePathGetCurrentIfOwned(allocator, current.*, ctx, out);
    if (has_more) {
        try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    }
    return field_ty;
}

fn ensurePathGetCurrentLocal(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    current: *PathGetValue,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError![]const u8 {
    if (current.local_name) |name| return name;
    if (!try emitExpr(allocator, tokens, current.expr_start, current.expr_end, locals, ctx, current.ty, out)) {
        return error.NoMatchingCall;
    }
    current.owned = isManagedLocalType(current.ty, ctx) and !isDirectManagedLocalExpr(tokens, current.expr_start, current.expr_end, locals, ctx);
    current.local_name = STORAGE_OVERWRITE_TMP_LOCAL;
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    return STORAGE_OVERWRITE_TMP_LOCAL;
}

fn releasePathGetCurrentIfOwned(
    allocator: std.mem.Allocator,
    current: PathGetValue,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !void {
    if (!current.owned or !isManagedLocalType(current.ty, ctx)) return;
    const local_name = current.local_name orelse return;
    try appendFmt(allocator, out, "    ;; path-get-release {s}\n", .{local_name});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{local_name});
    try out.appendSlice(allocator, "    call $__arc_dec\n");
}

fn emitManagedStructExprFieldGet(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    value_start: usize,
    value_end: usize,
    field_start: usize,
    field_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (field_end != field_start + 1 or !isDotIdent(tokens[field_start].lexeme)) return false;
    if (value_end == value_start + 1 and tokens[value_start].kind == .ident) return false;
    const struct_ty = inferExprType(tokens, value_start, value_end, locals, ctx) orelse return false;
    const layout = findStructLayout(ctx.struct_layouts, struct_ty) orelse return false;
    const decl = findStructDecl(ctx.structs, struct_ty) orelse return false;
    const field_name = publicDeclName(tokens[field_start].lexeme);
    const field = findStructField(decl, field_name) orelse return false;
    const field_offset = structFieldPayloadOffset(decl, field_name) orelse return false;

    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    const field_ty = try substituteStructFieldType(allocator, decl, struct_ty, field.ty, &owned_types);

    if (!try emitExpr(allocator, tokens, value_start, value_end, locals, ctx, struct_ty, out)) return false;
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try appendManagedStructFieldPtr(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, field_offset);
    try appendLoadForPayloadType(allocator, out, field_ty);
    if (isManagedStructField(layout, field_name)) {
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try out.appendSlice(allocator, "    call $__arc_dec\n");
    return true;
}

fn findStorageReadableLocalName(
    tokens: []const lexer.Token,
    locals: *const LocalSet,
    name: []const u8,
) ?[]const u8 {
    _ = tokens;
    if (findStoragePrimitiveLocal(locals.storage_locals.items, name)) |storage| return storage.name;

    const ty = findNarrowedUnionType(locals.narrowed_union_locals.items, name) orelse return null;
    if (storageElemTypeFromName(ty) == null) return null;
    const union_local = findUnionLocal(locals.union_locals.items, name) orelse return null;

    var matched: ?UnionBranch = null;
    for (union_local.layout.branches) |branch| {
        if (branch.payload_len != 1) continue;
        if (!codegenTypesCompatible(branch.ty, ty)) continue;
        if (matched != null) return null;
        matched = branch;
    }
    const branch = matched orelse return null;
    return unionPayloadLocalNameFromLocals(locals.locals.items, union_local.name, branch.payload_start);
}

fn emitUnionStoragePayloadGetCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    name: []const u8,
    index_start: usize,
    index_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const ty = findNarrowedUnionType(locals.narrowed_union_locals.items, name) orelse return false;
    const elem_ty = storageElemTypeFromName(ty) orelse return false;
    const elem_bytes = storageElementByteWidthForType(elem_ty, ctx) orelse return false;
    const storage_name = findStorageReadableLocalName(tokens, locals, name) orelse return false;

    try emitStorageBoundsCheck(allocator, tokens, index_start, index_end, locals, ctx, storage_name, 1, out);
    if (isTupleTypeName(elem_ty)) {
        try emitStorageDataPtr(allocator, out, storage_name);
        if (!try emitExpr(allocator, tokens, index_start, index_end, locals, ctx, "usize", out)) return false;
        if (elem_bytes != 1) {
            try appendFmt(allocator, out, "    i32.const {d}\n", .{elem_bytes});
            try out.appendSlice(allocator, "    i32.mul\n");
        }
        try out.appendSlice(allocator, "    i32.add\n");
        try appendFmt(allocator, out, "    local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
        try appendLoadTupleLeavesOwningToStackCtx(allocator, out, elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "    ", ctx);
    } else {
        try emitStorageDataPtr(allocator, out, storage_name);
        if (!try emitExpr(allocator, tokens, index_start, index_end, locals, ctx, "usize", out)) return false;
        if (elem_bytes != 1) {
            try appendFmt(allocator, out, "    i32.const {d}\n", .{elem_bytes});
            try out.appendSlice(allocator, "    i32.mul\n");
        }
        try out.appendSlice(allocator, "    i32.add\n");
        try appendLoadForPayloadType(allocator, out, elem_ty);
        if (isManagedLocalType(elem_ty, ctx)) {
            try out.appendSlice(allocator, "    ;; storage-managed-get-inc\n");
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
    }
    return true;
}

fn emitUnionStructFieldGetCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    name: []const u8,
    field_tok: lexer.Token,
    single_field_arg: bool,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (!single_field_arg or !isDotIdent(field_tok.lexeme)) return false;
    const union_local = findUnionLocal(locals.union_locals.items, name) orelse return false;
    const payload = unionLocalDefaultStructPayload(tokens, ctx, union_local) orelse return false;
    const field_name = publicDeclName(field_tok.lexeme);
    const field_offset = structFieldPayloadOffset(payload.decl, field_name) orelse return false;

    if (payload.branch.payload_len == 1) {
        if (findStructLayout(ctx.struct_layouts, payload.decl.name)) |layout| {
            const field_ty = findStructFieldType(payload.decl, field_name) orelse return false;
            try appendUnionPayloadLocalGet(allocator, out, name, payload.branch.payload_start);
            try out.appendSlice(allocator, "    call $__arc_payload\n");
            try appendFmt(allocator, out, "    i32.const {d}\n", .{field_offset});
            try out.appendSlice(allocator, "    i32.add\n");
            try appendLoadForPayloadType(allocator, out, field_ty);
            if (isManagedStructField(layout, field_name)) {
                try out.appendSlice(allocator, "    call $__arc_inc\n");
            }
            return true;
        }
    }

    var idx = payload.branch.payload_start;
    var offset: usize = 0;
    for (payload.decl.fields) |field| {
        offset = alignUp(offset, typePayloadAlignment(field.ty));
        if (std.mem.eql(u8, publicDeclName(field.name), field_name)) {
            try appendUnionPayloadLocalGet(allocator, out, name, idx);
            return true;
        }
        offset += typePayloadBytes(field.ty);
        idx += 1;
    }
    return false;
}

fn emitFieldReflectionIntrinsic(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    call_name: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    move_ctx: ?*const CallLastUseMoveContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (std.mem.eql(u8, call_name, "field_name")) {
        const meta = singleFieldMetaArg(tokens, start_idx, end_idx, locals) orelse return false;
        const field = fieldFromMeta(ctx, meta) orelse return false;
        try emitStorageU8RawStringValue(allocator, publicDeclName(field.name), STORAGE_OVERWRITE_TMP_LOCAL, ctx, out);
        return true;
    }
    if (std.mem.eql(u8, call_name, "field_index")) {
        const meta = singleFieldMetaArg(tokens, start_idx, end_idx, locals) orelse return false;
        try appendFmt(allocator, out, "    i32.const {d}\n", .{meta.visible_index});
        return true;
    }
    if (std.mem.eql(u8, call_name, "field_has_default")) {
        const meta = singleFieldMetaArg(tokens, start_idx, end_idx, locals) orelse return false;
        const field = fieldFromMeta(ctx, meta) orelse return false;
        try appendFmt(allocator, out, "    i32.const {d}\n", .{@intFromBool(field.default_start != null)});
        return true;
    }
    if (std.mem.eql(u8, call_name, "field_get")) {
        return try emitFieldGetCall(allocator, tokens, start_idx, end_idx, locals, ctx, move_ctx, out);
    }
    return false;
}

fn emitFieldGetCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    move_ctx: ?*const CallLastUseMoveContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1 or tokens[start_idx].kind != .ident) return false;
    if (first_end >= end_idx or !tokEq(tokens[first_end], ",")) return false;
    const field_start = first_end + 1;
    const field_end = findArgEnd(tokens, field_start, end_idx);
    if (field_end != end_idx) return false;
    if (field_end != field_start + 1 or tokens[field_start].kind != .ident) return false;

    const name = tokens[start_idx].lexeme;
    const struct_local = findStructLocal(locals.struct_locals.items, name) orelse return false;
    const meta = findFieldMetaLocal(locals.field_meta_locals.items, tokens[field_start].lexeme) orelse return false;
    if (!std.mem.eql(u8, typeBaseName(struct_local.ty), meta.struct_name)) return false;
    const field = fieldFromMeta(ctx, meta) orelse return false;
    const field_name = publicDeclName(field.name);

    if (findStructLayout(ctx.struct_layouts, struct_local.ty)) |layout| {
        const decl = findStructDecl(ctx.structs, struct_local.ty) orelse return false;
        const field_offset = structFieldPayloadOffset(decl, field_name) orelse return false;
        const move_source = if (move_ctx) |ctx_info|
            try fieldGetLastUseMoveSource(allocator, tokens, start_idx, end_idx, struct_local, field.ty, ctx_info.*, locals, ctx)
        else
            null;
        try appendFmt(allocator, out, "    local.get ${s}\n", .{struct_local.name});
        try out.appendSlice(allocator, "    call $__arc_payload\n");
        try appendFmt(allocator, out, "    i32.const {d}\n", .{field_offset});
        try out.appendSlice(allocator, "    i32.add\n");
        try appendLoadForPayloadType(allocator, out, field.ty);
        if (isManagedStructField(layout, field_name) and move_source == null) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
        if (move_source) |source| {
            try appendFmt(allocator, out, "    ;; field-get-move {s}.{s}\n", .{ source.source_name, field_name });
            try emitZeroValueForType(allocator, ctx, out, field.ty);
            try appendManagedStructFieldPtr(allocator, out, struct_local.name, field_offset);
            try appendStoreForPayloadType(allocator, out, field.ty);
        }
        return true;
    }

    if (try emitUnmanagedStructFieldGet(allocator, tokens, struct_local, field_name, field.ty, locals, ctx, out)) {
        return true;
    }
    try appendFmt(allocator, out, "    local.get ${s}.{s}\n", .{
        struct_local.name,
        field_name,
    });
    return true;
}

fn emitUnmanagedStructFieldGet(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    struct_local: StructLocal,
    field_name: []const u8,
    field_ty: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    const layout = (try parseTypeUnionLayoutFromName(allocator, tokens, field_ty, ctx.structs, ctx.struct_layouts, &owned_types)) orelse return false;
    defer freeUnionLayout(allocator, layout);
    const union_local_name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ struct_local.name, field_name });
    defer allocator.free(union_local_name);
    const union_local = findUnionLocal(locals.union_locals.items, union_local_name) orelse return false;
    if (!unionLayoutsEqual(union_local.layout, layout)) return false;
    for (layout.payload_tys, 0..) |payload_ty, idx| {
        try appendUnionPayloadLocalGet(allocator, out, union_local.name, idx);
        if (isManagedLocalType(payload_ty, ctx)) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
    }
    try appendUnionTagLocalGet(allocator, out, union_local.name);
    return true;
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
    if (findStoragePrimitiveLocal(locals.storage_locals.items, tokens[start_idx].lexeme) == null) return false;
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
    try out.appendSlice(allocator, "    call $__storage_check_range\n");
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
    const storage = findStoragePrimitiveLocal(locals.storage_locals.items, tokens[start_idx].lexeme) orelse return false;
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
    try out.appendSlice(allocator, "    call $__storage_set_u8\n");
    try emitStorageAliasRelease(allocator, out, tokens[start_idx].lexeme, target_name);
    return true;
}

fn emitStorageSetExpr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (start_idx >= end_idx or tokens[start_idx].kind != .ident) return false;
    if (findStoragePrimitiveLocal(locals.storage_locals.items, tokens[start_idx].lexeme) == null) return false;
    return try emitStorageSetCall(allocator, tokens, start_idx, end_idx, tokens[start_idx].lexeme, locals, ctx, out);
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
    const storage = findStoragePrimitiveLocal(locals.storage_locals.items, tokens[start_idx].lexeme) orelse return false;
    if (first_end >= end_idx or !tokEq(tokens[first_end], ",")) return false;

    const first_value_start = first_end + 1;
    const first_value_end = findArgEnd(tokens, first_value_start, end_idx);
    if (first_value_end == first_value_start) return false;
    if (first_value_start < end_idx and tokEq(tokens[first_value_start], "...")) {
        if (first_value_end != end_idx) return false;
        return try emitStoragePutSpreadCall(allocator, tokens, first_value_start + 1, first_value_end, tokens[start_idx].lexeme, target_name, storage.elem_ty, locals, ctx, out);
    }
    if (first_value_end == end_idx) {
        return try emitStoragePutOneCall(allocator, tokens, first_value_start, first_value_end, tokens[start_idx].lexeme, target_name, storage.elem_ty, locals, ctx, out);
    }

    if (!try emitStoragePutOneCall(allocator, tokens, first_value_start, first_value_end, tokens[start_idx].lexeme, target_name, storage.elem_ty, locals, ctx, out)) return false;
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});

    var value_start = first_value_end;
    while (value_start < end_idx) {
        if (!tokEq(tokens[value_start], ",")) return false;
        value_start += 1;
        if (value_start >= end_idx) return false;
        if (tokEq(tokens[value_start], "...")) return false;

        const value_end = findArgEnd(tokens, value_start, end_idx);
        if (value_end == value_start) return false;
        if (!try emitStoragePutOneCall(allocator, tokens, value_start, value_end, STORAGE_PUT_SOURCE_TMP_LOCAL, STORAGE_PUT_SOURCE_TMP_LOCAL, storage.elem_ty, locals, ctx, out)) return false;
        try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
        try emitReplaceStoragePutSourceTmp(allocator, target_name, out);
        value_start = value_end;
    }

    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
    return true;
}

fn emitStoragePutExpr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (start_idx >= end_idx or tokens[start_idx].kind != .ident) return false;
    if (findStoragePrimitiveLocal(locals.storage_locals.items, tokens[start_idx].lexeme) == null) return false;
    return try emitStoragePutCall(allocator, tokens, start_idx, end_idx, tokens[start_idx].lexeme, locals, ctx, out);
}

fn emitStructSetExpr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    expected_ty: ?[]const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1 or tokens[start_idx].kind != .ident) return false;
    if (first_end >= end_idx or !tokEq(tokens[first_end], ",")) return false;
    const field_start = first_end + 1;
    const field_end = findArgEnd(tokens, field_start, end_idx);
    if (field_end != field_start + 1 or !isDotIdent(tokens[field_start].lexeme)) return false;
    if (field_end >= end_idx or !tokEq(tokens[field_end], ",")) return false;
    const value_start = field_end + 1;
    const value_end = findArgEnd(tokens, value_start, end_idx);
    if (value_end != end_idx) return false;

    const struct_local = findStructLocal(locals.struct_locals.items, tokens[start_idx].lexeme) orelse return false;
    const struct_ty = expected_ty orelse struct_local.ty;
    if (!std.mem.eql(u8, struct_local.ty, struct_ty)) return false;
    if (findStructLayout(ctx.struct_layouts, struct_ty) != null) return false;

    const decl = findStructDecl(ctx.structs, struct_ty) orelse return false;
    const target_field = publicDeclName(tokens[field_start].lexeme);
    for (decl.fields) |field| {
        const field_name = publicDeclName(field.name);
        const field_ty = findLocalFieldType(locals.locals.items, struct_local.name, field_name) orelse
            findStructFieldType(decl, field_name) orelse return false;
        if (std.mem.eql(u8, field_name, target_field)) {
            if (!try emitExpr(allocator, tokens, value_start, value_end, locals, ctx, field_ty, out)) return false;
            continue;
        }
        try appendFmt(allocator, out, "    local.get ${s}.{s}\n", .{
            struct_local.name,
            field_name,
        });
    }
    return true;
}

fn emitStoragePutOneCall(
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
    if (isManagedLocalType(elem_ty, ctx)) {
        return try emitStoragePutManagedCall(allocator, tokens, value_start, value_end, source_name, target_name, elem_ty, locals, ctx, out);
    }
    if (!std.mem.eql(u8, elem_ty, "u8")) {
        return try emitStoragePutScalarCall(allocator, tokens, value_start, value_end, source_name, target_name, elem_ty, locals, ctx, out);
    }

    try emitStorageAliasProtect(allocator, out, source_name, target_name);
    try appendFmt(allocator, out, "    local.get ${s}\n", .{source_name});
    if (!try emitExpr(allocator, tokens, value_start, value_end, locals, ctx, "u8", out)) return false;
    try out.appendSlice(allocator, "    call $__storage_put_u8\n");
    try emitStorageAliasRelease(allocator, out, source_name, target_name);
    return true;
}

fn emitStoragePutSpreadCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    spread_start: usize,
    spread_end: usize,
    source_name: []const u8,
    target_name: []const u8,
    elem_ty: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (spread_end != spread_start + 1 or tokens[spread_start].kind != .ident) return false;
    const rest_name = tokens[spread_start].lexeme;
    const rest = findStoragePrimitiveLocal(locals.storage_locals.items, rest_name) orelse return false;
    if (!std.mem.eql(u8, rest.elem_ty, elem_ty)) return false;
    const elem_bytes = storageElementByteWidthForType(elem_ty, ctx) orelse return false;

    try appendFmt(allocator, out, "    local.get ${s}\n", .{source_name});
    if (isDirectManagedLocalExpr(tokens, spread_start, spread_end, locals, ctx)) {
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
    try out.appendSlice(allocator, "    i32.const 0\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try out.appendSlice(allocator, "    block $storage_put_spread_done\n");
    try out.appendSlice(allocator, "      loop $storage_put_spread_scan\n");
    try appendFmt(allocator, out, "        local.get ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try emitStorageLenPtr(allocator, out, rest_name);
    try out.appendSlice(allocator, "        i32.load\n");
    try out.appendSlice(allocator, "        i32.ge_u\n");
    try out.appendSlice(allocator, "        br_if $storage_put_spread_done\n");
    if (isManagedLocalType(elem_ty, ctx)) {
        try emitStorageElementPtrFromLocalWithIndent(allocator, out, rest_name, STORAGE_WRITE_INDEX_TMP_LOCAL, 4, "        ");
        try out.appendSlice(allocator, "        i32.load\n");
        try out.appendSlice(allocator, "        call $__arc_inc\n");
        try appendFmt(allocator, out, "        local.get ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
        try out.appendSlice(allocator, "        call $__storage_put_managed_borrow\n");
    } else if (std.mem.eql(u8, elem_ty, "u8")) {
        try appendFmt(allocator, out, "        local.get ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
        try emitStorageElementPtrFromLocalWithIndent(allocator, out, rest_name, STORAGE_WRITE_INDEX_TMP_LOCAL, elem_bytes, "        ");
        try appendLoadForPayloadTypeWithIndent(allocator, out, elem_ty, "        ");
        try out.appendSlice(allocator, "        call $__storage_put_u8\n");
    } else {
        try emitStoragePutSpreadScalarElement(allocator, rest_name, elem_ty, elem_bytes, ctx, out);
    }
    try appendFmt(allocator, out, "        local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try emitReplaceStoragePutSourceTmp(allocator, target_name, out);
    try appendFmt(allocator, out, "        local.get ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try out.appendSlice(allocator, "        i32.const 1\n");
    try out.appendSlice(allocator, "        i32.add\n");
    try appendFmt(allocator, out, "        local.set ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try out.appendSlice(allocator, "        br $storage_put_spread_scan\n");
    try out.appendSlice(allocator, "      end\n");
    try out.appendSlice(allocator, "    end\n");
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
    return true;
}

fn emitReplaceStoragePutSourceTmp(
    allocator: std.mem.Allocator,
    target_name: []const u8,
    out: *std.ArrayList(u8),
) !void {
    try out.appendSlice(allocator, "    ;; storage-put-source-replace\n");
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
    try out.appendSlice(allocator, "    i32.ne\n");
    try out.appendSlice(allocator, "    if\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
    try appendFmt(allocator, out, "      local.get ${s}\n", .{target_name});
    try out.appendSlice(allocator, "      i32.ne\n");
    try out.appendSlice(allocator, "      if\n");
    try appendFmt(allocator, out, "        local.get ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
    try out.appendSlice(allocator, "        call $__arc_dec\n");
    try out.appendSlice(allocator, "      end\n");
    try out.appendSlice(allocator, "    end\n");
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
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
    const elem_bytes = storageElementByteWidthForType(elem_ty, ctx) orelse return false;
    try out.appendSlice(allocator, "    ;; storage-set-scalar\n");
    try emitStorageAliasProtect(allocator, out, source_name, target_name);
    if (!try emitExpr(allocator, tokens, index_start, index_end, locals, ctx, "usize", out)) return false;
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{source_name});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try out.appendSlice(allocator, "    i32.const 1\n");
    try out.appendSlice(allocator, "    call $__storage_check_range\n");
    try appendFmt(allocator, out, "    local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "    call $__arc_rc\n");
    try out.appendSlice(allocator, "    i32.const 1\n");
    try out.appendSlice(allocator, "    i32.eq\n");
    try out.appendSlice(allocator, "    if (result i32)\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "    else\n");
    try emitStorageCloneCurrentLenForElem(allocator, out, source_name, elem_ty, elem_bytes, ctx);
    try out.appendSlice(allocator, "    end\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    if (isTupleTypeName(elem_ty)) {
        if (tupleHasManagedPackLeafCtx(elem_ty, ctx)) {
            // Dec replaced managed leaves before writing new ones.
            try emitStorageElementPtrFromLocal(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, elem_bytes);
            try appendFmt(allocator, out, "    local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
            try emitDecManagedTupleLeavesAtBase(allocator, out, elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "    ", ctx);
        }
        if (!try emitExpr(allocator, tokens, value_start, value_end, locals, ctx, elem_ty, out)) return false;
        try emitStorageElementPtrFromLocal(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, elem_bytes);
        try appendFmt(allocator, out, "    local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
        try appendStoreTupleLeavesOwningFromStackCtx(allocator, out, elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "    ", ctx);
    } else {
        try emitStorageElementPtrFromLocal(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, elem_bytes);
        if (!try emitExpr(allocator, tokens, value_start, value_end, locals, ctx, elem_ty, out)) return false;
        try appendStoreForPayloadType(allocator, out, elem_ty);
    }
    try emitStorageAliasRelease(allocator, out, source_name, target_name);
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    return true;
}

fn emitStoragePutSpreadScalarElement(
    allocator: std.mem.Allocator,
    rest_name: []const u8,
    elem_ty: []const u8,
    elem_bytes: usize,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!void {
    try out.appendSlice(allocator, "        ;; storage-put-spread-scalar\n");
    try emitStorageLenPtrWithIndent(allocator, out, STORAGE_PUT_SOURCE_TMP_LOCAL, "        ");
    try out.appendSlice(allocator, "        i32.load\n");
    try appendFmt(allocator, out, "        local.set ${s}\n", .{STORAGE_WRITE_LEN_TMP_LOCAL});
    try appendFmt(allocator, out, "        local.get ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
    try out.appendSlice(allocator, "        call $__arc_rc\n");
    try out.appendSlice(allocator, "        i32.const 1\n");
    try out.appendSlice(allocator, "        i32.eq\n");
    try appendFmt(allocator, out, "        local.get ${s}\n", .{STORAGE_WRITE_LEN_TMP_LOCAL});
    try emitStorageCapPtrWithIndent(allocator, out, STORAGE_PUT_SOURCE_TMP_LOCAL, "        ");
    try out.appendSlice(allocator, "        i32.load\n");
    try out.appendSlice(allocator, "        i32.lt_u\n");
    try out.appendSlice(allocator, "        i32.and\n");
    try out.appendSlice(allocator, "        if (result i32)\n");
    try appendFmt(allocator, out, "          local.get ${s}\n", .{STORAGE_PUT_SOURCE_TMP_LOCAL});
    try out.appendSlice(allocator, "        else\n");
    try appendFmt(allocator, out, "          local.get ${s}\n", .{STORAGE_WRITE_LEN_TMP_LOCAL});
    try out.appendSlice(allocator, "          i32.const 1\n");
    try out.appendSlice(allocator, "          i32.add\n");
    try appendFmt(allocator, out, "          local.set ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try emitStorageCloneWithLenLocalForElem(allocator, out, STORAGE_PUT_SOURCE_TMP_LOCAL, elem_ty, elem_bytes, STORAGE_WRITE_NEXT_TMP_LOCAL, STORAGE_WRITE_LEN_TMP_LOCAL, ctx);
    try out.appendSlice(allocator, "        end\n");
    try appendFmt(allocator, out, "        local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    if (isTupleTypeName(elem_ty)) {
        try emitStorageElementPtrFromLocalWithIndent(allocator, out, rest_name, STORAGE_WRITE_INDEX_TMP_LOCAL, elem_bytes, "        ");
        try appendFmt(allocator, out, "        local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
        // Spread copy: load without owning-inc, store without owning-inc (clone path already inced, or unique).
        try appendLoadTupleScalarLeavesToStackCtx(allocator, out, elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "        ", ctx);
        try emitStorageElementPtrFromLocalWithIndent(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_LEN_TMP_LOCAL, elem_bytes, "        ");
        try appendFmt(allocator, out, "        local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
        try appendStoreTupleScalarLeavesFromStackCtx(allocator, out, elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "        ", ctx);
        if (tupleHasManagedPackLeafCtx(elem_ty, ctx)) {
            // Unique-append path copies handles without clone-inc; share ownership with source element.
            try emitStorageElementPtrFromLocalWithIndent(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_LEN_TMP_LOCAL, elem_bytes, "        ");
            try appendFmt(allocator, out, "        local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
            try emitIncManagedTupleLeavesAtBase(allocator, out, elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "        ", ctx);
        }
    } else {
        try emitStorageElementPtrFromLocalWithIndent(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_LEN_TMP_LOCAL, elem_bytes, "        ");
        try emitStorageElementPtrFromLocalWithIndent(allocator, out, rest_name, STORAGE_WRITE_INDEX_TMP_LOCAL, elem_bytes, "        ");
        try appendLoadForPayloadTypeWithIndent(allocator, out, elem_ty, "        ");
        try appendStoreForPayloadTypeWithIndent(allocator, out, elem_ty, "        ");
    }
    try emitStorageLenPtrWithIndent(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, "        ");
    try appendFmt(allocator, out, "        local.get ${s}\n", .{STORAGE_WRITE_LEN_TMP_LOCAL});
    try out.appendSlice(allocator, "        i32.const 1\n");
    try out.appendSlice(allocator, "        i32.add\n");
    try out.appendSlice(allocator, "        i32.store\n");
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
    const elem_bytes = storageElementByteWidthForType(elem_ty, ctx) orelse return false;
    try out.appendSlice(allocator, "    ;; storage-put-scalar\n");
    try emitStorageAliasProtect(allocator, out, source_name, target_name);
    try emitStorageLenPtr(allocator, out, source_name);
    try out.appendSlice(allocator, "    i32.load\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "    call $__arc_rc\n");
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
    try emitStorageCloneWithLenLocalForElem(allocator, out, source_name, elem_ty, elem_bytes, STORAGE_WRITE_LEN_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, ctx);
    try out.appendSlice(allocator, "    end\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    if (isTupleTypeName(elem_ty)) {
        if (!try emitExpr(allocator, tokens, value_start, value_end, locals, ctx, elem_ty, out)) return false;
        try emitStorageElementPtrFromLocal(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, elem_bytes);
        try appendFmt(allocator, out, "    local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
        try appendStoreTupleLeavesOwningFromStackCtx(allocator, out, elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "    ", ctx);
    } else {
        try emitStorageElementPtrFromLocal(allocator, out, STORAGE_OVERWRITE_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, elem_bytes);
        if (!try emitExpr(allocator, tokens, value_start, value_end, locals, ctx, elem_ty, out)) return false;
        try appendStoreForPayloadType(allocator, out, elem_ty);
    }
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
    try out.appendSlice(allocator, "    call $__storage_check_range\n");
    try appendFmt(allocator, out, "    local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "    call $__arc_rc\n");
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
    try out.appendSlice(allocator, "    call $__arc_dec\n");
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
    try out.appendSlice(allocator, "    call $__arc_rc\n");
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
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_WRITE_TARGET_TMP_LOCAL});
    try emitStorageElementPtrFromLocal(allocator, out, STORAGE_WRITE_TARGET_TMP_LOCAL, STORAGE_WRITE_INDEX_TMP_LOCAL, 4);
    if (!try emitManagedStorageValue(allocator, tokens, value_start, value_end, elem_ty, locals, ctx, out)) return false;
    try out.appendSlice(allocator, "    i32.store\n");
    try emitStorageLenPtr(allocator, out, STORAGE_WRITE_TARGET_TMP_LOCAL);
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_WRITE_INDEX_TMP_LOCAL});
    try out.appendSlice(allocator, "    i32.const 1\n");
    try out.appendSlice(allocator, "    i32.add\n");
    try out.appendSlice(allocator, "    i32.store\n");
    try emitStorageAliasRelease(allocator, out, source_name, target_name);
    try appendFmt(allocator, out, "    local.get ${s}\n", .{STORAGE_WRITE_TARGET_TMP_LOCAL});
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
        try out.appendSlice(allocator, "    call $__arc_inc\n");
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

fn emitStorageCloneCurrentLenForElem(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    source_name: []const u8,
    elem_ty: []const u8,
    elem_bytes: usize,
    ctx: CodegenContext,
) !void {
    try emitStorageLenPtr(allocator, out, source_name);
    try out.appendSlice(allocator, "      i32.load\n");
    try appendFmt(allocator, out, "      local.set ${s}\n", .{STORAGE_WRITE_LEN_TMP_LOCAL});
    try emitStorageCloneWithLenLocalForElem(allocator, out, source_name, elem_ty, elem_bytes, STORAGE_WRITE_LEN_TMP_LOCAL, STORAGE_WRITE_LEN_TMP_LOCAL, ctx);
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
    try out.appendSlice(allocator, "      call $__arc_alloc\n");
    try appendFmt(allocator, out, "      local.set ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try out.appendSlice(allocator, "      call $__arc_payload\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{next_len_local});
    try out.appendSlice(allocator, "      i32.store\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try out.appendSlice(allocator, "      call $__arc_payload\n");
    try out.appendSlice(allocator, "      i32.const 4\n");
    try out.appendSlice(allocator, "      i32.add\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{next_len_local});
    try out.appendSlice(allocator, "      i32.store\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try out.appendSlice(allocator, "      call $__arc_payload\n");
    try appendFmt(allocator, out, "      i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES});
    try out.appendSlice(allocator, "      i32.add\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "      call $__arc_payload\n");
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
    try out.appendSlice(allocator, "          call $__arc_payload\n");
    try appendFmt(allocator, out, "          i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES});
    try out.appendSlice(allocator, "          i32.add\n");
    try appendFmt(allocator, out, "          local.get ${s}\n", .{STORAGE_WRITE_SCAN_TMP_LOCAL});
    try out.appendSlice(allocator, "          i32.const 4\n");
    try out.appendSlice(allocator, "          i32.mul\n");
    try out.appendSlice(allocator, "          i32.add\n");
    try out.appendSlice(allocator, "          i32.load\n");
    try out.appendSlice(allocator, "          call $__arc_inc\n");
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
    try emitStorageCloneWithLenLocalTyped(allocator, out, source_name, elem_bytes, next_len_local, copy_len_local, TYPE_ID_STORAGE_U8, null);
}

fn emitStorageCloneWithLenLocalForElem(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    source_name: []const u8,
    elem_ty: []const u8,
    elem_bytes: usize,
    next_len_local: []const u8,
    copy_len_local: []const u8,
    ctx: CodegenContext,
) !void {
    const type_id = storageTypeIdForElement(elem_ty, ctx);
    const pack = storagePackLayoutForElem(elem_ty, ctx);
    try emitStorageCloneWithLenLocalTyped(allocator, out, source_name, elem_bytes, next_len_local, copy_len_local, type_id, pack);
}

fn emitStorageCloneWithLenLocalTyped(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    source_name: []const u8,
    elem_bytes: usize,
    next_len_local: []const u8,
    copy_len_local: []const u8,
    type_id: usize,
    pack_layout: ?StructLayout,
) !void {
    try appendFmt(allocator, out, "      local.get ${s}\n", .{next_len_local});
    if (elem_bytes != 1) {
        try appendFmt(allocator, out, "      i32.const {d}\n", .{elem_bytes});
        try out.appendSlice(allocator, "      i32.mul\n");
    }
    try appendFmt(allocator, out, "      i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES});
    try out.appendSlice(allocator, "      i32.add\n");
    try appendFmt(allocator, out, "      i32.const {d}\n", .{type_id});
    try out.appendSlice(allocator, "      call $__arc_alloc\n");
    try appendFmt(allocator, out, "      local.set ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try out.appendSlice(allocator, "      call $__arc_payload\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{next_len_local});
    try out.appendSlice(allocator, "      i32.store\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try out.appendSlice(allocator, "      call $__arc_payload\n");
    try out.appendSlice(allocator, "      i32.const 4\n");
    try out.appendSlice(allocator, "      i32.add\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{next_len_local});
    try out.appendSlice(allocator, "      i32.store\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
    try out.appendSlice(allocator, "      call $__arc_payload\n");
    try appendFmt(allocator, out, "      i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES});
    try out.appendSlice(allocator, "      i32.add\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{source_name});
    try out.appendSlice(allocator, "      call $__arc_payload\n");
    try appendFmt(allocator, out, "      i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES});
    try out.appendSlice(allocator, "      i32.add\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{copy_len_local});
    if (elem_bytes != 1) {
        try appendFmt(allocator, out, "      i32.const {d}\n", .{elem_bytes});
        try out.appendSlice(allocator, "      i32.mul\n");
    }
    try out.appendSlice(allocator, "      memory.copy\n");
    if (pack_layout) |layout| {
        try emitStorageIncCopiedPackElements(allocator, out, STORAGE_WRITE_NEXT_TMP_LOCAL, copy_len_local, layout);
    }
    try appendFmt(allocator, out, "      local.get ${s}\n", .{STORAGE_WRITE_NEXT_TMP_LOCAL});
}

fn emitStorageIncCopiedPackElements(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    storage_local: []const u8,
    copy_len_local: []const u8,
    layout: StructLayout,
) !void {
    try out.appendSlice(allocator, "      ;; storage-pack-clone-inc\n");
    try out.appendSlice(allocator, "      i32.const 0\n");
    try appendFmt(allocator, out, "      local.set ${s}\n", .{STORAGE_WRITE_SCAN_TMP_LOCAL});
    try out.appendSlice(allocator, "      block $storage_pack_clone_inc_done\n");
    try out.appendSlice(allocator, "        loop $storage_pack_clone_inc_scan\n");
    try appendFmt(allocator, out, "          local.get ${s}\n", .{STORAGE_WRITE_SCAN_TMP_LOCAL});
    try appendFmt(allocator, out, "          local.get ${s}\n", .{copy_len_local});
    try out.appendSlice(allocator, "          i32.ge_u\n");
    try out.appendSlice(allocator, "          br_if $storage_pack_clone_inc_done\n");
    for (layout.managed_fields) |field| {
        try appendFmt(allocator, out, "          local.get ${s}\n", .{storage_local});
        try out.appendSlice(allocator, "          call $__arc_payload\n");
        try appendFmt(allocator, out, "          i32.const {d}\n", .{STORAGE_PAYLOAD_HEADER_BYTES});
        try out.appendSlice(allocator, "          i32.add\n");
        try appendFmt(allocator, out, "          local.get ${s}\n", .{STORAGE_WRITE_SCAN_TMP_LOCAL});
        try appendFmt(allocator, out, "          i32.const {d}\n", .{layout.payload_bytes});
        try out.appendSlice(allocator, "          i32.mul\n");
        try out.appendSlice(allocator, "          i32.add\n");
        if (field.offset != 0) {
            try appendFmt(allocator, out, "          i32.const {d}\n", .{field.offset});
            try out.appendSlice(allocator, "          i32.add\n");
        }
        try out.appendSlice(allocator, "          i32.load\n");
        try out.appendSlice(allocator, "          call $__arc_inc\n");
        try out.appendSlice(allocator, "          drop\n");
    }
    try appendFmt(allocator, out, "          local.get ${s}\n", .{STORAGE_WRITE_SCAN_TMP_LOCAL});
    try out.appendSlice(allocator, "          i32.const 1\n");
    try out.appendSlice(allocator, "          i32.add\n");
    try appendFmt(allocator, out, "          local.set ${s}\n", .{STORAGE_WRITE_SCAN_TMP_LOCAL});
    try out.appendSlice(allocator, "          br $storage_pack_clone_inc_scan\n");
    try out.appendSlice(allocator, "        end\n");
    try out.appendSlice(allocator, "      end\n");
}

fn emitStorageElementPtrFromLocal(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    storage_local: []const u8,
    index_local: []const u8,
    elem_bytes: usize,
) !void {
    try storage_wat.emitStorageElementPtrFromLocal(allocator, out, storage_local, index_local, elem_bytes);
}

fn emitStorageElementPtrFromLocalWithIndent(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    storage_local: []const u8,
    index_local: []const u8,
    elem_bytes: usize,
    indent: []const u8,
) !void {
    try storage_wat.emitStorageElementPtrFromLocalWithIndent(allocator, out, storage_local, index_local, elem_bytes, indent);
}

fn emitStorageAliasProtect(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    source_name: []const u8,
    target_name: []const u8,
) !void {
    try storage_wat.emitStorageAliasProtect(allocator, out, source_name, target_name);
}

fn emitStorageAliasRelease(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    source_name: []const u8,
    target_name: []const u8,
) !void {
    try storage_wat.emitStorageAliasRelease(allocator, out, source_name, target_name);
}

fn emitScalarAsCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !bool {
    const target_end = findArgEnd(tokens, args_start, args_end);
    if (target_end == args_start or target_end >= args_end or !tokEq(tokens[target_end], ",")) return false;
    const target_ty = scalarAsTargetType(tokens, args_start, target_end) orelse return false;

    const source_start = target_end + 1;
    const source_end = trimTrailingComma(tokens, source_start, args_end);
    if (source_start >= source_end) return false;

    const source_ty = inferExprType(tokens, source_start, source_end, locals, ctx) orelse target_ty;
    if (!isCoreWasmScalar(source_ty)) return false;
    if (!try emitExpr(allocator, tokens, source_start, source_end, locals, ctx, source_ty, out)) return false;
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
    if (lowering.result_list_preopen) {
        return try emitWasiListPreopenResultCall(allocator, tokens, args_start, args_end, locals, ctx, import, out);
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
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try appendWasiImportSymbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    try out.appendSlice(allocator,
        \\    global.get $__wasi_result_area_base
        \\    i32.load
        \\    global.get $__wasi_result_area_base
        \\    i32.const 4
        \\    i32.add
        \\    i32.load
        \\    call $__wasi_list_u8_to_storage
        \\
    );
    return true;
}

/// G6.1 A: () -> list<tuple<descriptor,string>> as do [Tuple<i32,text>].
fn emitWasiListPreopenResultCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    _ = tokens;
    _ = locals;
    _ = ctx;
    if (!std.mem.eql(u8, import.target, "filesystem/preopens/get-directories")) return false;
    if (args_start != args_end) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try appendWasiImportSymbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    try out.appendSlice(allocator,
        \\    global.get $__wasi_result_area_base
        \\    i32.load
        \\    global.get $__wasi_result_area_base
        \\    i32.const 4
        \\    i32.add
        \\    i32.load
        \\    call $__wasi_list_preopen_to_storage
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
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
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
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
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
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
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
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
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
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
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
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
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
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
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
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
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
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
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
        \\    global.get $__wasi_result_area_base
        \\    i32.load
        \\    i32.eqz
        \\    if (result i32)
        \\      i32.const 0
        \\    else
        \\      global.get $__wasi_result_area_base
        \\      i32.const 4
        \\      i32.add
        \\      i32.load
        \\      i32.const 1
        \\      i32.add
        \\    end
        \\
    );
}

/// Lower unit fallible WASI host into exclusive union stack values: payload slots + tag.
/// Phase-1 shape: `nil | i32` (nil = ok / tag 0; i32 = status error-code+1 / never 0).
fn emitWasiUnitResultAsUnionValue(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    layout: UnionLayout,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const lowering = wasiLowering(import) orelse return false;
    if (!lowering.result_unit_error) return false;

    const nil_branch = findUnionBranchByType(layout, "nil") orelse return false;
    if (nil_branch.tag != 0) return false;

    var err_branch: ?UnionBranch = null;
    for (layout.branches) |branch| {
        if (std.mem.eql(u8, branch.ty, "nil")) continue;
        if (err_branch != null) return false;
        if (branch.payload_len != 1) return false;
        if (branch.payload_start >= layout.payload_tys.len) return false;
        if (!std.mem.eql(u8, layout.payload_tys[branch.payload_start], "i32")) return false;
        err_branch = branch;
    }
    const err = err_branch orelse return false;
    // Single i32 payload slot only for this phase.
    if (layout.payload_tys.len != 1) return false;

    if (!try emitWasiResultUnitCall(allocator, tokens, args_start, args_end, locals, ctx, import, out)) {
        return error.NoMatchingCall;
    }

    // Stack: i32 payload, i32 tag (matches emitUnionValue order).
    try out.appendSlice(allocator,
        \\    global.get $__wasi_result_area_base
        \\    i32.load
        \\    i32.eqz
        \\    if (result i32 i32)
        \\      i32.const 0
        \\      i32.const 0
        \\    else
        \\      global.get $__wasi_result_area_base
        \\      i32.const 4
        \\      i32.add
        \\      i32.load
        \\      i32.const 1
        \\      i32.add
        \\
    );
    try appendFmt(allocator, out, "      i32.const {d}\n", .{err.tag});
    try out.appendSlice(allocator, "    end\n");
    return true;
}

fn emitWasiResultReadValues(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
) !void {
    try out.appendSlice(allocator,
        \\    global.get $__wasi_result_area_base
        \\    i32.load
        \\    i32.eqz
        \\    if (result i32 i32 i32)
        \\      global.get $__wasi_result_area_base
        \\      i32.const 4
        \\      i32.add
        \\      i32.load
        \\      global.get $__wasi_result_area_base
        \\      i32.const 8
        \\      i32.add
        \\      i32.load
        \\      call $__wasi_list_u8_to_storage
        \\      global.get $__wasi_result_area_base
        \\      i32.const 12
        \\      i32.add
        \\      i32.load8_u
        \\      i32.const 0
        \\    else
    );
    try emitEmptyStorageU8Value(allocator, out);
    try out.appendSlice(allocator,
        \\      i32.const 0
        \\      global.get $__wasi_result_area_base
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
        \\    global.get $__wasi_result_area_base
        \\    i32.load
        \\    i32.eqz
        \\    if (result i32 i32)
        \\      global.get $__wasi_result_area_base
        \\      i32.const 4
        \\      i32.add
        \\      i32.load
        \\      global.get $__wasi_result_area_base
        \\      i32.const 8
        \\      i32.add
        \\      i32.load
        \\      call $__wasi_list_u8_to_storage
        \\      i32.const 0
        \\    else
    );
    try emitEmptyStorageU8Value(allocator, out);
    try out.appendSlice(allocator,
        \\      global.get $__wasi_result_area_base
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
        \\    global.get $__wasi_result_area_base
        \\    i32.load
        \\    i32.eqz
        \\    if (result i32 i32)
        \\      global.get $__wasi_result_area_base
        \\      i32.const 4
        \\      i32.add
        \\      i32.load
        \\      i32.const 0
        \\    else
        \\      i32.const 0
        \\      global.get $__wasi_result_area_base
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
    try storage_wat.emitEmptyStorageU8Value(allocator, out);
}

fn emitEmptyStorageForElemType(
    allocator: std.mem.Allocator,
    elem_ty: []const u8,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!void {
    const type_id = storageTypeIdForElement(elem_ty, ctx);
    try storage_wat.emitEmptyStorageWithTypeId(allocator, out, type_id, "    ");
}

fn emitWasiResultFilesizeValues(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
) !void {
    try out.appendSlice(allocator,
        \\    global.get $__wasi_result_area_base
        \\    i32.load
        \\    i32.eqz
        \\    if (result i64 i32)
        \\      global.get $__wasi_result_area_base
        \\      i32.const 8
        \\      i32.add
        \\      i64.load
        \\      i32.const 0
        \\    else
        \\      i64.const 0
        \\      global.get $__wasi_result_area_base
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
    const storage = findStoragePrimitiveLocal(locals.storage_locals.items, tokens[range.start].lexeme) orelse return false;
    if (!std.mem.eql(u8, storage.elem_ty, "u8")) return false;

    try emitStorageDataPtr(allocator, out, tokens[range.start].lexeme);
    try emitStorageLenPtr(allocator, out, tokens[range.start].lexeme);
    try out.appendSlice(allocator, "    i32.load\n");
    return true;
}

fn findCallbackBinding(bindings: []const CallbackBinding, name: []const u8) ?CallbackBinding {
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.param_name, name)) return binding;
    }
    return null;
}

fn findCallbackCallArg(args: []const CallbackCallArg, name: []const u8) ?CallbackCallArg {
    for (args) |arg| {
        if (std.mem.eql(u8, arg.source_name, name)) return arg;
    }
    return null;
}

fn cloneLocalSet(allocator: std.mem.Allocator, locals: *const LocalSet) !LocalSet {
    var out = LocalSet{};
    try out.locals.appendSlice(allocator, locals.locals.items);
    try out.struct_locals.appendSlice(allocator, locals.struct_locals.items);
    try out.storage_locals.appendSlice(allocator, locals.storage_locals.items);
    for (locals.union_locals.items) |union_local| {
        try out.union_locals.append(allocator, .{
            .name = union_local.name,
            .source_name = union_local.source_name,
            .layout = union_local.layout,
            .owns_layout = false,
            .origin = union_local.origin,
        });
    }
    try out.narrowed_union_locals.appendSlice(allocator, locals.narrowed_union_locals.items);
    try out.field_meta_locals.appendSlice(allocator, locals.field_meta_locals.items);
    out.local_name_prefix = locals.local_name_prefix;
    return out;
}

fn mergeReturnCleanupLocals(
    allocator: std.mem.Allocator,
    parent: *const LocalSet,
    direct: *const LocalSet,
) !LocalSet {
    var out = try cloneLocalSet(allocator, parent);
    errdefer out.deinit(allocator);
    for (direct.locals.items) |local| {
        if (hasLocal(out.locals.items, local.name)) continue;
        try out.locals.append(allocator, local);
    }
    return out;
}

fn appendCallbackArgAliasLocals(
    allocator: std.mem.Allocator,
    parent: *const LocalSet,
    locals: *LocalSet,
    arg: CallbackCallArg,
) !void {
    const actual = arg.actual_name orelse return;
    if (findLocalType(parent.locals.items, actual)) |ty| {
        const actual_name = findLocalName(parent.locals.items, actual) orelse actual;
        try locals.locals.append(allocator, .{
            .name = actual_name,
            .source_name = arg.source_name,
            .ty = ty,
            .origin = findLocalOrigin(parent.locals.items, actual) orelse .unknown,
            .emit_decl = false,
        });
    }
    if (findStructLocal(parent.struct_locals.items, actual)) |struct_local| {
        try locals.struct_locals.append(allocator, .{
            .name = struct_local.name,
            .source_name = arg.source_name,
            .ty = struct_local.ty,
            .origin = struct_local.origin,
        });
    }
    if (findStorageLocal(parent.storage_locals.items, actual)) |storage_local| {
        try locals.storage_locals.append(allocator, .{
            .name = storage_local.name,
            .source_name = arg.source_name,
            .ty = storage_local.ty,
            .elem_ty = storage_local.elem_ty,
        });
    }
    if (findUnionLocal(parent.union_locals.items, actual)) |union_local| {
        try locals.union_locals.append(allocator, .{
            .name = union_local.name,
            .source_name = arg.source_name,
            .layout = union_local.layout,
            .owns_layout = false,
        });
    }
}

fn collectCallbackCallArgs(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    call_head: ExprCallHead,
    locals: *const LocalSet,
    ctx: CodegenContext,
    binding: CallbackBinding,
) ![]const CallbackCallArg {
    var out = std.ArrayList(CallbackCallArg).empty;
    errdefer out.deinit(allocator);

    var arg_start = call_head.args_start;
    var idx: usize = 0;
    while (arg_start < call_head.args_end) {
        if (idx >= binding.lambda_params.len or idx >= binding.shape.param_types.len) return error.NoMatchingCall;
        const arg_end = findArgEnd(tokens, arg_start, call_head.args_end);
        const range = trimParens(tokens, arg_start, arg_end);
        const actual_name: ?[]const u8 = if (range.end == range.start + 1 and tokens[range.start].kind == .ident)
            tokens[range.start].lexeme
        else
            null;
        const arg_ty = binding.shape.param_types[idx] orelse inferExprType(tokens, arg_start, arg_end, locals, ctx) orelse return error.NoMatchingCall;
        try out.append(allocator, .{
            .source_name = binding.lambda_params[idx],
            .actual_name = actual_name,
            .ty = arg_ty,
            .expr_tokens = tokens,
            .expr_start = arg_start,
            .expr_end = arg_end,
        });
        idx += 1;
        arg_start = arg_end;
        if (arg_start < call_head.args_end and tokEq(tokens[arg_start], ",")) arg_start += 1;
    }
    if (idx != binding.lambda_params.len) return error.NoMatchingCall;
    return out.toOwnedSlice(allocator);
}

fn emitCallbackBindingLambdaCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    call_head: ExprCallHead,
    locals: *const LocalSet,
    ctx: CodegenContext,
    binding: CallbackBinding,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (binding.lambda_params.len != binding.shape.param_types.len) return false;
    const callback_args = try collectCallbackCallArgs(allocator, tokens, call_head, locals, ctx, binding);
    defer allocator.free(callback_args);

    var lambda_locals = try cloneLocalSet(allocator, locals);
    defer lambda_locals.deinit(allocator);
    for (callback_args) |arg| {
        try appendCallbackArgAliasLocals(allocator, locals, &lambda_locals, arg);
    }

    var lambda_ctx = ctx;
    lambda_ctx.callback_call_args = callback_args;
    if (!lambdaShapeIsBlock(binding)) {
        return try emitExpr(
            allocator,
            binding.arg_tokens,
            binding.body_start,
            binding.body_end,
            &lambda_locals,
            lambda_ctx,
            binding.shape.return_type,
            out,
        );
    }

    try collectBodyLocals(allocator, binding.arg_tokens, binding.body_start, binding.body_end, lambda_ctx, &lambda_locals);
    if (binding.shape.return_type) |ret_ty| {
        try appendFmt(allocator, out, "    block $__lambda_ret (result {s})\n", .{codegenWasmType(lambda_ctx, ret_ty)});
    } else {
        try out.appendSlice(allocator, "    block $__lambda_ret\n");
    }
    const lambda_defer = DeferContext{
        .parent = null,
        .start_idx = binding.body_start,
        .end_idx = binding.body_end,
        .registered_end_idx = binding.body_end,
    };
    const lambda_results: []const []const u8 = if (binding.shape.return_type) |ret_ty|
        &[_][]const u8{ret_ty}
    else
        &.{};
    try emitBody(
        allocator,
        binding.arg_tokens,
        binding.body_start,
        binding.body_end,
        binding.body_start,
        &lambda_locals,
        &lambda_locals,
        &EMPTY_LOCAL_SET,
        lambda_ctx,
        lambda_results,
        NO_RESULT_ITEMS,
        null,
        null,
        null,
        &lambda_defer,
        "__lambda_ret",
        null,
        out,
    );
    try out.appendSlice(allocator, "    end\n");
    return true;
}

fn lambdaShapeIsBlock(binding: CallbackBinding) bool {
    return binding.body_start > 0 and binding.body_end > binding.body_start and tokEq(binding.arg_tokens[binding.body_start - 1], "{");
}

fn emitCallbackBindingFuncRefCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    call_head: ExprCallHead,
    locals: *const LocalSet,
    ctx: CodegenContext,
    binding: CallbackBinding,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const func_name = binding.func_name orelse return false;
    const target = findCallbackRefFunc(binding.arg_tokens, ctx, func_name, binding.shape) orelse return false;
    return try emitUserFuncCall(allocator, tokens, call_head.args_start, call_head.args_end, locals, ctx, target, out);
}

fn emitCallbackBindingCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    call_head: ExprCallHead,
    locals: *const LocalSet,
    ctx: CodegenContext,
    binding: CallbackBinding,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    return switch (binding.kind) {
        .lambda => try emitCallbackBindingLambdaCall(allocator, tokens, call_head, locals, ctx, binding, out),
        .func_ref => try emitCallbackBindingFuncRefCall(allocator, tokens, call_head, locals, ctx, binding, out),
    };
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
    return emitUserFuncCallWithMoveContext(allocator, tokens, start_idx, end_idx, locals, ctx, func, null, out);
}

fn emitUserFuncCallWithMoveContext(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    func: FuncDecl,
    move_ctx: ?*const CallLastUseMoveContext,
    out: *std.ArrayList(u8),
) !bool {
    const variadic_idx = funcVariadicParamIndex(func);
    var move_sources = std.ArrayList(LastUseManagedMoveSource).empty;
    defer move_sources.deinit(allocator);
    var arg_start = start_idx;
    var param_idx: usize = 0;
    while (arg_start < end_idx and (variadic_idx == null or param_idx < variadic_idx.?)) {
        if (param_idx >= func.params.len) return false;
        const arg_end = findArgEnd(tokens, arg_start, end_idx);
        const param = func.params[param_idx];
        if (param.callback) |callback| {
            if (!callArgMatchesCallbackShape(tokens, arg_start, arg_end, locals, ctx, callback.shape)) return false;
        } else {
            const param_ty = param.ty;
            const move_source = if (move_ctx) |ctx_info|
                directManagedCallLastUseMoveSource(tokens, arg_start, arg_end, ctx_info.*, locals, ctx)
            else
                null;
            const param_is_union = findTopLevelTypeSeparator(param_ty, '|') != null;
            if (!try emitUserFuncArg(allocator, tokens, arg_start, arg_end, param_ty, move_source == null, locals, ctx, out)) return false;
            if (!param_is_union and move_source == null and isDirectManagedLocalExpr(tokens, arg_start, arg_end, locals, ctx)) {
                try out.appendSlice(allocator, "    call $__arc_inc\n");
            } else if (move_source) |source| {
                if (!hasMoveSource(move_sources.items, source.actual_name)) {
                    try move_sources.append(allocator, source);
                }
            }
        }
        param_idx += 1;
        arg_start = arg_end;
        if (arg_start < end_idx and tokEq(tokens[arg_start], ",")) arg_start += 1;
    }

    if (variadic_idx) |rest_idx| {
        if (rest_idx >= func.params.len) return false;
        if (!try emitVariadicPackArg(allocator, tokens, arg_start, end_idx, funcVariadicElemType(func.params[rest_idx]), locals, ctx, out)) return false;
        param_idx = func.params.len;
    } else if (param_idx != func.params.len) {
        return false;
    }
    try appendFmt(allocator, out, "    call ${s}\n", .{func.name});
    for (move_sources.items) |source| {
        try appendFmt(allocator, out, "    ;; arc-call-move {s}\n", .{source.source_name});
        try out.appendSlice(allocator, "    i32.const 0\n");
        try appendFmt(allocator, out, "    local.set ${s}\n", .{source.actual_name});
    }
    return true;
}

fn emitUserFuncCallWithUnionBindingMove(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    stmt_end: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    func: FuncDecl,
    out: *std.ArrayList(u8),
) !bool {
    const variadic_idx = funcVariadicParamIndex(func);
    var move_sources = std.ArrayList(LastUseManagedMoveSource).empty;
    defer move_sources.deinit(allocator);
    var arg_start = start_idx;
    var param_idx: usize = 0;
    while (arg_start < end_idx and (variadic_idx == null or param_idx < variadic_idx.?)) {
        if (param_idx >= func.params.len) return false;
        const arg_end = findArgEnd(tokens, arg_start, end_idx);
        const param = func.params[param_idx];
        if (param.callback) |callback| {
            if (!callArgMatchesCallbackShape(tokens, arg_start, arg_end, locals, ctx, callback.shape)) return false;
        } else {
            const param_ty = param.ty;
            const move_source = directManagedUnionBindingCallMoveSource(
                tokens,
                arg_start,
                arg_end,
                end_idx,
                stmt_end,
                body_end,
                allow_last_use_move,
                locals,
                ctx,
                defer_ctx,
            );
            const param_is_union = findTopLevelTypeSeparator(param_ty, '|') != null;
            if (!try emitUserFuncArg(allocator, tokens, arg_start, arg_end, param_ty, move_source == null, locals, ctx, out)) return false;
            if (!param_is_union and move_source == null and isDirectManagedLocalExpr(tokens, arg_start, arg_end, locals, ctx)) {
                try out.appendSlice(allocator, "    call $__arc_inc\n");
            } else if (move_source) |source| {
                if (!hasMoveSource(move_sources.items, source.actual_name)) {
                    try move_sources.append(allocator, source);
                }
            }
        }
        param_idx += 1;
        arg_start = arg_end;
        if (arg_start < end_idx and tokEq(tokens[arg_start], ",")) arg_start += 1;
    }

    if (variadic_idx) |rest_idx| {
        if (rest_idx >= func.params.len) return false;
        if (!try emitVariadicPackArg(allocator, tokens, arg_start, end_idx, funcVariadicElemType(func.params[rest_idx]), locals, ctx, out)) return false;
        param_idx = func.params.len;
    } else if (param_idx != func.params.len) {
        return false;
    }
    try appendFmt(allocator, out, "    call ${s}\n", .{func.name});
    for (move_sources.items) |source| {
        try appendFmt(allocator, out, "    ;; arc-call-move {s}\n", .{source.source_name});
        try out.appendSlice(allocator, "    i32.const 0\n");
        try appendFmt(allocator, out, "    local.set ${s}\n", .{source.actual_name});
    }
    return true;
}

fn emitVariadicPackArg(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    elem_ty: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (start_idx < end_idx and tokEq(tokens[start_idx], "...")) {
        const spread_start = start_idx + 1;
        if (findArgEnd(tokens, spread_start, end_idx) != end_idx) return false;
        if (spread_start + 1 != end_idx or tokens[spread_start].kind != .ident) return false;
        const rest = findStoragePrimitiveLocal(locals.storage_locals.items, tokens[spread_start].lexeme) orelse return false;
        if (!std.mem.eql(u8, rest.elem_ty, elem_ty)) return false;
        try appendFmt(allocator, out, "    local.get ${s}\n", .{tokens[spread_start].lexeme});
        return true;
    }

    try emitEmptyStorageForElemType(allocator, elem_ty, ctx, out);
    try appendFmt(allocator, out, "    local.set ${s}\n", .{VARIADIC_PACK_TMP_LOCAL});

    var arg_start = start_idx;
    while (arg_start < end_idx) {
        const arg_end = findArgEnd(tokens, arg_start, end_idx);
        if (arg_end == arg_start) return false;
        if (!try emitStoragePutOneCall(allocator, tokens, arg_start, arg_end, VARIADIC_PACK_TMP_LOCAL, VARIADIC_PACK_TMP_LOCAL, elem_ty, locals, ctx, out)) return false;
        try appendFmt(allocator, out, "    local.set ${s}\n", .{VARIADIC_PACK_TMP_LOCAL});
        arg_start = arg_end;
        if (arg_start < end_idx and tokEq(tokens[arg_start], ",")) arg_start += 1;
    }

    try appendFmt(allocator, out, "    local.get ${s}\n", .{VARIADIC_PACK_TMP_LOCAL});
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
        if (sameCallableSourceName(func.source_name, source_name)) return func;
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
    var fallback: ?FuncDecl = null;
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (!moduleTokensEqual(func.tokens, tokens)) continue;
        if (!sameCallableSourceName(func.source_name, name)) continue;
        if (!callArgsMatchFuncParams(tokens, args_start, args_end, locals, ctx, func)) continue;
        if (func.callback_bindings.len != 0) return func;
        if (fallback == null) fallback = func;
    }
    if (fallback) |func| return func;
    const import_ref = findCodegenImportByAlias(tokens, name) orelse return null;
    fallback = null;
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (!std.mem.eql(u8, func.name, import_ref.alias)) continue;
        if (!callArgsMatchFuncParams(tokens, args_start, args_end, locals, ctx, func)) continue;
        if (func.callback_bindings.len != 0) return func;
        if (fallback == null) fallback = func;
    }
    if (fallback) |func| return func;
    const import_ctx = importedAliasContextForTokens(ctx.imported_alias_ctx, tokens) orelse return null;
    const child_idx = findImportedModuleIndexNoAlloc(import_ctx.graph, import_ctx.module_idx, import_ref) orelse return null;
    const child_tokens = import_ctx.graph.modules[child_idx].tokens;
    fallback = null;
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (!moduleTokensEqual(func.tokens, child_tokens)) continue;
        if (!sameCallableSourceName(func.source_name, import_ref.alias)) continue;
        if (!callArgsMatchFuncParams(tokens, args_start, args_end, locals, ctx, func)) continue;
        if (func.callback_bindings.len != 0) return func;
        if (fallback == null) fallback = func;
    }
    if (fallback) |func| return func;
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (!moduleTokensEqual(func.tokens, child_tokens)) continue;
        if (!sameCallableSourceName(func.source_name, publicDeclName(import_ref.target))) continue;
        if (!callArgsMatchFuncParams(tokens, args_start, args_end, locals, ctx, func)) continue;
        if (func.callback_bindings.len != 0) return func;
        if (fallback == null) fallback = func;
    }
    return fallback;
}

fn findFuncDeclForCallHead(
    tokens: []const lexer.Token,
    call_head: ExprCallHead,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?FuncDecl {
    const name = tokens[call_head.name_idx].lexeme;
    if (!callHeadHasTypeArgs(call_head)) {
        return findFuncDeclForCall(tokens, call_head.args_start, call_head.args_end, locals, ctx, name);
    }

    var fallback: ?FuncDecl = null;
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (!moduleTokensEqual(func.tokens, tokens)) continue;
        if (!sameCallableSourceName(func.source_name, name)) continue;
        if (!callExplicitTypeArgsMatchBindings(tokens, call_head, func.type_bindings)) continue;
        if (!callArgsMatchFuncParams(tokens, call_head.args_start, call_head.args_end, locals, ctx, func)) continue;
        if (func.callback_bindings.len != 0) return func;
        if (fallback == null) fallback = func;
    }
    if (fallback) |func| return func;

    const import_ref = findCodegenImportByAlias(tokens, name) orelse return null;
    fallback = null;
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (!std.mem.eql(u8, func.name, import_ref.alias)) continue;
        if (!callExplicitTypeArgsMatchBindings(tokens, call_head, func.type_bindings)) continue;
        if (!callArgsMatchFuncParams(tokens, call_head.args_start, call_head.args_end, locals, ctx, func)) continue;
        if (func.callback_bindings.len != 0) return func;
        if (fallback == null) fallback = func;
    }
    if (fallback) |func| return func;

    const import_ctx = importedAliasContextForTokens(ctx.imported_alias_ctx, tokens) orelse return null;
    const child_idx = findImportedModuleIndexNoAlloc(import_ctx.graph, import_ctx.module_idx, import_ref) orelse return null;
    const child_tokens = import_ctx.graph.modules[child_idx].tokens;
    fallback = null;
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (!moduleTokensEqual(func.tokens, child_tokens)) continue;
        if (!sameCallableSourceName(func.source_name, import_ref.alias)) continue;
        if (!callExplicitTypeArgsMatchBindings(tokens, call_head, func.type_bindings)) continue;
        if (!callArgsMatchFuncParams(tokens, call_head.args_start, call_head.args_end, locals, ctx, func)) continue;
        if (func.callback_bindings.len != 0) return func;
        if (fallback == null) fallback = func;
    }
    if (fallback) |func| return func;
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (!moduleTokensEqual(func.tokens, child_tokens)) continue;
        if (!sameCallableSourceName(func.source_name, publicDeclName(import_ref.target))) continue;
        if (!callExplicitTypeArgsMatchBindings(tokens, call_head, func.type_bindings)) continue;
        if (!callArgsMatchFuncParams(tokens, call_head.args_start, call_head.args_end, locals, ctx, func)) continue;
        if (func.callback_bindings.len != 0) return func;
        if (fallback == null) fallback = func;
    }
    return fallback;
}

fn callExplicitTypeArgsMatchBindings(
    tokens: []const lexer.Token,
    call_head: ExprCallHead,
    bindings: []const GenericTypeBinding,
) bool {
    if (bindings.len == 0) return false;

    var type_start = call_head.type_args_start;
    var binding_idx: usize = 0;
    while (type_start < call_head.type_args_end) {
        if (binding_idx >= bindings.len) return false;
        if (tokEq(tokens[type_start], ",")) return false;

        const type_end = findTypeArgEnd(tokens, type_start, call_head.type_args_end);
        if (type_end == type_start) return false;
        if (!tokenTextEqualsCompact(tokens, type_start, type_end, bindings[binding_idx].ty)) return false;

        binding_idx += 1;
        type_start = type_end;
        if (type_start < call_head.type_args_end) {
            if (!tokEq(tokens[type_start], ",")) return false;
            type_start += 1;
            if (type_start >= call_head.type_args_end) return false;
        }
    }
    return binding_idx == bindings.len;
}

fn funcHasVariadicParam(func: FuncDecl) bool {
    return funcVariadicParamIndex(func) != null;
}

fn funcVariadicParamIndex(func: FuncDecl) ?usize {
    for (func.params, 0..) |param, idx| {
        if (param.variadic) return idx;
    }
    return null;
}

fn funcParamAbiType(param: FuncParam) []const u8 {
    if (param.abi_ty) |abi_ty| return abi_ty;
    if (!param.variadic) return param.ty;
    return storageTypeNameForElem(param.ty) orelse param.ty;
}

fn funcVariadicElemType(param: FuncParam) []const u8 {
    if (!param.variadic) return param.ty;
    return param.ty;
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
    while (arg_start < args_end and (param_idx < func.params.len and !func.params[param_idx].variadic)) {
        const arg_end = findArgEnd(tokens, arg_start, args_end);
        if (func.params[param_idx].callback) |callback| {
            if (!callArgMatchesCallbackShape(tokens, arg_start, arg_end, locals, ctx, callback.shape)) return false;
            if (findCallbackBinding(func.callback_bindings, func.params[param_idx].name)) |binding| {
                if (!callArgMatchesConcreteCallbackBinding(tokens, arg_start, arg_end, ctx, callback.shape, binding)) return false;
            }
        } else if (!callArgMatchesParam(tokens, arg_start, arg_end, locals, ctx, func.params[param_idx].ty)) {
            return false;
        }
        param_idx += 1;
        arg_start = arg_end;
        if (arg_start < args_end and tokEq(tokens[arg_start], ",")) arg_start += 1;
    }
    if (param_idx == func.params.len) return arg_start >= args_end;
    if (!func.params[param_idx].variadic) return false;
    if (param_idx + 1 != func.params.len) return false;
    return callArgsMatchVariadicTail(tokens, arg_start, args_end, locals, ctx, funcVariadicElemType(func.params[param_idx]));
}

fn callArgMatchesConcreteCallbackBinding(
    tokens: []const lexer.Token,
    arg_start: usize,
    arg_end: usize,
    ctx: CodegenContext,
    shape: FuncTypeShape,
    binding: CallbackBinding,
) bool {
    if (!callbackBindingsHaveSameShape(binding.shape, shape)) return false;
    if (lambdaExprShape(tokens, arg_start, arg_end) != null) {
        return binding.kind == .lambda and moduleTokensEqual(binding.arg_tokens, tokens) and binding.arg_start == arg_start and binding.arg_end == arg_end;
    }

    const range = trimParens(tokens, arg_start, arg_end);
    if (range.end != range.start + 1 or tokens[range.start].kind != .ident) return false;
    const name = tokens[range.start].lexeme;
    if (findCallbackBinding(ctx.callback_bindings, name)) |upstream| {
        return callbackBindingHasSameConcreteArg(binding, upstream);
    }
    if (binding.kind != .func_ref) return false;
    const func_name = binding.func_name orelse return false;
    return moduleTokensEqual(binding.arg_tokens, tokens) and sameCallableSourceName(func_name, name);
}

fn callbackFunctionMatchesShape(func: FuncDecl, shape: FuncTypeShape) bool {
    if (func.params.len != shape.param_types.len) return false;
    for (shape.param_types, 0..) |target_ty, idx| {
        const expected = target_ty orelse continue;
        if (!std.mem.eql(u8, func.params[idx].ty, expected)) return false;
    }
    if (shape.return_type) |ret_ty| {
        if (std.mem.eql(u8, ret_ty, "nil")) {
            return func.result == null or std.mem.eql(u8, func.result.?, "nil");
        }
        const actual_ret = func.result orelse return false;
        if (!std.mem.eql(u8, actual_ret, ret_ty)) return false;
    }
    return true;
}

fn callbackLambdaReturnMatchesShape(
    tokens: []const lexer.Token,
    lambda: LambdaExprShape,
    shape: FuncTypeShape,
    locals: *const LocalSet,
    ctx: CodegenContext,
) bool {
    if (shape.return_type) |ret_ty| {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const lambda_ret = inferLambdaExprReturnType(arena.allocator(), tokens, lambda, shape, locals, ctx) catch return false;
        if (lambda_ret) |actual| {
            if (std.mem.eql(u8, actual, "nil")) return std.mem.eql(u8, ret_ty, "nil");
            return std.mem.eql(u8, ret_ty, actual);
        }
        return false;
    }
    if (!lambda.is_block) return true;
    if (isReturnArrowAt(tokens, lambda.close_params + 1)) {
        if (lambdaExplicitReturnType(tokens, lambda)) |lambda_ret| {
            return std.mem.eql(u8, lambda_ret, "nil");
        }
        return false;
    }
    return true;
}

fn findCallbackRefFunc(tokens: []const lexer.Token, ctx: CodegenContext, name: []const u8, shape: FuncTypeShape) ?FuncDecl {
    for (ctx.functions) |func| {
        if (func.is_generic_template) continue;
        if (!moduleTokensEqual(func.tokens, tokens)) continue;
        if (!sameCallableSourceName(func.source_name, name)) continue;
        if (callbackFunctionMatchesShape(func, shape)) return func;
    }
    return null;
}

fn lambdaParamCount(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    if (start_idx >= end_idx) return 0;
    var count: usize = 0;
    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !isTopLevelCommaAny(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) count += 1;
        seg_start = i + 1;
    }
    return count;
}

fn lambdaExplicitTypesMatchShape(tokens: []const lexer.Token, lambda: LambdaExprShape, shape: FuncTypeShape) bool {
    var seg_start = lambda.open_params + 1;
    var seg_idx: usize = 0;
    var i = lambda.open_params + 1;
    while (i <= lambda.close_params) : (i += 1) {
        if (i < lambda.close_params and !isTopLevelCommaAny(tokens, i, lambda.open_params + 1, lambda.close_params)) continue;
        if (seg_start < i) {
            if (seg_idx >= shape.param_types.len) return false;
            if (lambdaParamTypeName(tokens, seg_start, i)) |ty| {
                const expected = shape.param_types[seg_idx] orelse return false;
                if (!std.mem.eql(u8, expected, ty)) return false;
            }
            seg_idx += 1;
        }
        seg_start = i + 1;
    }
    return seg_idx == shape.param_types.len;
}

fn callArgMatchesCallbackShape(
    tokens: []const lexer.Token,
    arg_start: usize,
    arg_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    shape: FuncTypeShape,
) bool {
    if (lambdaExprShape(tokens, arg_start, arg_end)) |lambda| {
        if (lambdaParamCount(tokens, lambda.open_params + 1, lambda.close_params) != shape.param_types.len) return false;
        if (!lambdaExplicitTypesMatchShape(tokens, lambda, shape)) return false;
        if (shape.return_type == null and lambda.is_block and isReturnArrowAt(tokens, lambda.close_params + 1)) {
            if (lambdaExplicitReturnType(tokens, lambda)) |lambda_ret| {
                if (!std.mem.eql(u8, lambda_ret, "nil")) return false;
            }
        }
        return callbackLambdaReturnMatchesShape(tokens, lambda, shape, locals, ctx);
    }

    const range = trimParens(tokens, arg_start, arg_end);
    if (range.end == range.start + 1 and tokens[range.start].kind == .ident) {
        if (findCallbackBinding(ctx.callback_bindings, tokens[range.start].lexeme)) |binding| {
            return callbackBindingsHaveSameShape(binding.shape, shape);
        }
        return findCallbackRefFunc(tokens, ctx, tokens[range.start].lexeme, shape) != null;
    }
    return false;
}

fn callArgsMatchVariadicTail(
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    elem_ty: []const u8,
) bool {
    if (args_start >= args_end) return true;
    if (tokEq(tokens[args_start], "...")) {
        const rest_start = args_start + 1;
        if (findArgEnd(tokens, rest_start, args_end) != args_end) return false;
        if (rest_start + 1 != args_end or tokens[rest_start].kind != .ident) return false;
        const rest = findStoragePrimitiveLocal(locals.storage_locals.items, tokens[rest_start].lexeme) orelse return false;
        return std.mem.eql(u8, rest.elem_ty, elem_ty);
    }

    var arg_start = args_start;
    while (arg_start < args_end) {
        const arg_end = findArgEnd(tokens, arg_start, args_end);
        if (arg_end == arg_start) return false;
        if (!callArgMatchesParam(tokens, arg_start, arg_end, locals, ctx, elem_ty)) return false;
        arg_start = arg_end;
        if (arg_start < args_end and tokEq(tokens[arg_start], ",")) arg_start += 1;
    }
    return true;
}

fn callArgMatchesParam(
    tokens: []const lexer.Token,
    arg_start: usize,
    arg_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    param_ty: []const u8,
) bool {
    if (findTopLevelTypeSeparator(param_ty, '|') != null) {
        return callArgMatchesUnionParam(tokens, arg_start, arg_end, locals, ctx, param_ty);
    }

    if (inferExprType(tokens, arg_start, arg_end, locals, ctx)) |arg_ty| {
        return codegenTypesCompatible(param_ty, arg_ty);
    }

    if (managedPayloadElemTypeFromName(param_ty) != null and isStorageAggLiteralExpr(tokens, arg_start, arg_end)) {
        return true;
    }

    if (structLiteralExprMatchesType(tokens, arg_start, arg_end, param_ty, ctx)) {
        return true;
    }

    const range = trimParens(tokens, arg_start, arg_end);
    if (range.end != range.start + 1) return false;

    const tok = tokens[range.start];
    if (tok.kind == .ident) {
        if (errorEnumBranchValue(tokens, param_ty, tok.lexeme) != null) return true;
        if (valueEnumBranchValue(ctx, tokens, param_ty, tok.lexeme) != null) return true;
        if (findStructLocal(locals.struct_locals.items, tok.lexeme)) |struct_local| {
            return std.mem.eql(u8, struct_local.ty, param_ty);
        }
    }
    if (tok.kind == .number) {
        return isCoreIntegerScalar(param_ty) or isCoreFloatScalar(param_ty);
    }
    if (tok.kind == .string) {
        return std.mem.eql(u8, param_ty, "text") or storageElemTypeFromName(param_ty) != null;
    }
    if (tok.kind == .ident and (std.mem.eql(u8, tok.lexeme, "true") or std.mem.eql(u8, tok.lexeme, "false"))) {
        return std.mem.eql(u8, param_ty, "bool");
    }
    return false;
}

fn structLiteralExprMatchesType(
    tokens: []const lexer.Token,
    arg_start: usize,
    arg_end: usize,
    param_ty: []const u8,
    ctx: CodegenContext,
) bool {
    const range = trimParens(tokens, arg_start, arg_end);
    const open_brace = structLiteralOpenRhs(tokens, range.start, range.end) orelse return false;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", range.end) catch return false;
    if (close_brace + 1 != range.end) return false;
    if (tokens[range.start].kind != .ident) return false;
    const literal_base = tokens[range.start].lexeme;
    if (!std.mem.eql(u8, typeBaseName(param_ty), literal_base)) return false;
    return findStructDecl(ctx.structs, param_ty) != null;
}

fn callArgMatchesUnionParam(
    tokens: []const lexer.Token,
    arg_start: usize,
    arg_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    param_ty: []const u8,
) bool {
    const range = trimParens(tokens, arg_start, arg_end);
    if (range.start >= range.end) return false;
    if (range.end == range.start + 1 and tokEq(tokens[range.start], "nil")) {
        return unionTypeNameHasBranch(param_ty, "nil");
    }
    if (inferExprType(tokens, arg_start, arg_end, locals, ctx)) |arg_ty| {
        if (codegenTypesCompatible(param_ty, arg_ty)) return true;
        return unionTypeNameHasBranch(param_ty, arg_ty);
    }
    return false;
}

fn unionTypeNameHasBranch(ty: []const u8, branch_ty: []const u8) bool {
    var branch_start: usize = 0;
    while (branch_start < ty.len) {
        const branch_end = findTopLevelTypeSeparatorFrom(ty, branch_start, '|') orelse ty.len;
        if (std.mem.eql(u8, ty[branch_start..branch_end], branch_ty)) return true;
        branch_start = branch_end + 1;
    }
    return false;
}

fn findStructDecl(structs: []const StructDecl, name: []const u8) ?StructDecl {
    const lookup_name = typeBaseName(name);
    for (structs) |decl| {
        if (std.mem.eql(u8, decl.name, lookup_name)) return decl;
    }
    return null;
}

fn findStructLayout(layouts: []const StructLayout, name: []const u8) ?StructLayout {
    for (layouts) |layout| {
        if (std.mem.eql(u8, layout.name, name)) return layout;
    }
    const lookup_name = typeBaseName(name);
    for (layouts) |layout| {
        if (std.mem.eql(u8, layout.name, lookup_name)) return layout;
    }
    return null;
}

fn findStructLayoutExact(layouts: []const StructLayout, name: []const u8) ?StructLayout {
    for (layouts) |layout| {
        if (std.mem.eql(u8, layout.name, name)) return layout;
    }
    return null;
}

fn typeBaseName(ty: []const u8) []const u8 {
    return type_util.typeBaseName(ty);
}

fn findStructFieldType(decl: StructDecl, field_name: []const u8) ?[]const u8 {
    for (decl.fields) |field| {
        if (std.mem.eql(u8, publicDeclName(field.name), field_name)) return field.ty;
    }
    return null;
}

fn findStructField(decl: StructDecl, field_name: []const u8) ?StructField {
    for (decl.fields) |field| {
        if (std.mem.eql(u8, publicDeclName(field.name), field_name)) return field;
    }
    return null;
}

const StructLiteralFieldRange = struct {
    value_start: usize,
    value_end: usize,
};

fn findStructLiteralField(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    field_name: []const u8,
) ?StructLiteralFieldRange {
    var field_start = start_idx;
    while (field_start < end_idx) {
        if (tokEq(tokens[field_start], ",")) {
            field_start += 1;
            continue;
        }
        if (tokens[field_start].kind != .ident) return null;
        const assign_idx = findTopLevelToken(tokens, field_start + 1, end_idx, "=") orelse return null;
        const field_end = findStructLiteralFieldEnd(tokens, assign_idx + 1, end_idx);
        if (std.mem.eql(u8, publicDeclName(tokens[field_start].lexeme), field_name)) {
            return .{ .value_start = assign_idx + 1, .value_end = field_end };
        }
        field_start = field_end;
        if (field_start < end_idx and tokEq(tokens[field_start], ",")) field_start += 1;
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
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (localNameMatches(local.name, local.source_name, name)) return local;
    }
    return null;
}

fn findStructLocalExact(locals: []const StructLocal, name: []const u8) ?StructLocal {
    for (locals) |local| {
        if (std.mem.eql(u8, local.name, name)) return local;
    }
    return null;
}

fn findUnionLocal(locals: []const UnionLocal, name: []const u8) ?UnionLocal {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (localNameMatches(local.name, local.source_name, name)) return local;
    }
    return null;
}

fn findUnionLocalExact(locals: []const UnionLocal, name: []const u8) ?UnionLocal {
    for (locals) |local| {
        if (std.mem.eql(u8, local.name, name)) return local;
    }
    return null;
}

fn findNarrowedUnionType(locals: []const NarrowedUnionLocal, name: []const u8) ?[]const u8 {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (localNameMatches(local.name, local.source_name, name)) return local.ty;
    }
    return null;
}

fn clearNarrowedUnionLocalsForAssignments(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *LocalSet,
) void {
    const eq_idx = findTopLevelToken(tokens, start_idx, end_idx, "=") orelse return;
    var lhs_start = start_idx;
    while (lhs_start < eq_idx) {
        const lhs_end = findArgEnd(tokens, lhs_start, eq_idx);
        if (lhs_end == lhs_start + 1 and tokens[lhs_start].kind == .ident) {
            clearNarrowedUnionLocal(locals, tokens[lhs_start].lexeme);
        }
        lhs_start = lhs_end;
        if (lhs_start < eq_idx and tokEq(tokens[lhs_start], ",")) lhs_start += 1;
    }
}

fn clearNarrowedUnionLocal(locals: *LocalSet, name: []const u8) void {
    var i = locals.narrowed_union_locals.items.len;
    while (i > 0) {
        i -= 1;
        const local = locals.narrowed_union_locals.items[i];
        if (localNameMatches(local.name, local.source_name, name)) {
            _ = locals.narrowed_union_locals.orderedRemove(i);
        }
    }
}

fn findStorageLocal(locals: []const StorageLocal, name: []const u8) ?StorageLocal {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (localNameMatches(local.name, local.source_name, name)) return local;
    }
    return null;
}

fn findStorageLocalExact(locals: []const StorageLocal, name: []const u8) ?StorageLocal {
    for (locals) |local| {
        if (std.mem.eql(u8, local.name, name)) return local;
    }
    return null;
}

fn findStoragePrimitiveLocal(locals: []const StorageLocal, name: []const u8) ?StorageLocal {
    const local = findStorageLocal(locals, name) orelse return null;
    if (storageElemTypeFromName(local.ty) == null) return null;
    return local;
}

fn findLocalOrigin(locals: []const Local, name: []const u8) ?SourceOrigin {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (localNameMatches(local.name, local.source_name, name)) return local.origin;
    }
    return null;
}

fn findStorageLocalOrigin(locals: []const StorageLocal, name: []const u8) ?SourceOrigin {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (localNameMatches(local.name, local.source_name, name)) return local.origin;
    }
    return null;
}

fn findLocalType(locals: []const Local, name: []const u8) ?[]const u8 {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (localNameMatches(local.name, local.source_name, name)) return local.ty;
    }
    return null;
}

fn findLocalFieldType(locals: []const Local, base: []const u8, field: []const u8) ?[]const u8 {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (localFieldNameMatches(local.name, base, field)) return local.ty;
        if (local.source_name) |source| {
            if (localFieldNameMatches(source, base, field)) return local.ty;
        }
    }
    return null;
}

fn localFieldNameMatches(name: []const u8, base: []const u8, field: []const u8) bool {
    if (name.len != base.len + 1 + field.len) return false;
    if (!std.mem.eql(u8, name[0..base.len], base)) return false;
    if (name[base.len] != '.') return false;
    return std.mem.eql(u8, name[base.len + 1 ..], field);
}

fn findLocalName(locals: []const Local, name: []const u8) ?[]const u8 {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (localNameMatches(local.name, local.source_name, name)) return local.name;
    }
    return null;
}

fn resolvedLocalName(locals: []const Local, name: []const u8) []const u8 {
    return findLocalName(locals, name) orelse name;
}

fn localNameMatches(name: []const u8, source_name: ?[]const u8, needle: []const u8) bool {
    if (std.mem.eql(u8, name, needle)) return true;
    if (source_name) |source| return std.mem.eql(u8, source, needle);
    return false;
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
    body_end: usize,
    body_start: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    return_cleanup_locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_items: []const FuncResultItem,
    result_struct: ?[]const u8,
    result_union: ?UnionLayout,
    defer_ctx: ?*const DeferContext,
    return_label: ?[]const u8,
    self_tail_tco: ?*const SelfTailTco,
    out: *std.ArrayList(u8),
) !bool {
    _ = result_struct;
    if (start_idx + 3 > end_idx) return false;
    if (!tokEq(tokens[start_idx], "if")) return false;

    const return_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "return") orelse return false;
    const has_return_expr = return_idx + 1 < end_idx;
    var move_names = std.ArrayList([]const u8).empty;
    defer move_names.deinit(allocator);

    const cond_move_ctx = CallLastUseMoveContext{
        .body_start = body_start,
        .stmt_end = return_idx,
        .body_end = body_end,
        .defer_ctx = defer_ctx,
        .allow_last_use_move = allow_last_use_move,
    };
    const emitted = try emitExprWithMoveContext(allocator, tokens, start_idx + 1, return_idx, locals, ctx, "bool", &cond_move_ctx, out);
    if (!emitted) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    if\n");
    var return_active_locals = try cloneLocalSet(allocator, locals);
    defer return_active_locals.deinit(allocator);
    try appendConditionNarrowingForBranch(allocator, tokens, start_idx + 1, return_idx, &return_active_locals, ctx, true);
    if (self_tail_tco) |tco| {
        if (try emitSelfTailReturn(allocator, tokens, return_idx, end_idx, &return_active_locals, ctx, tco.*, out)) {
            try out.appendSlice(allocator, "    end\n");
            return true;
        }
    }
    if (has_return_expr) {
        if (result_union) |layout| {
            try collectUnionReturnMoveNames(allocator, tokens, return_idx + 1, end_idx, &return_active_locals, ctx, layout, &move_names);
            const move_ctx = CallLastUseMoveContext{
                .body_start = body_start,
                .stmt_end = end_idx,
                .body_end = end_idx,
                .defer_ctx = defer_ctx,
                .allow_last_use_move = true,
                .allow_field_read_move = true,
            };
            if (!try emitUnionValue(allocator, tokens, return_idx + 1, end_idx, &return_active_locals, ctx, layout, false, &move_ctx, out)) {
                return error.NoMatchingCall;
            }
        } else if (result_tys.len > 1 and result_items.len != 0) {
            try emitMultiResultReturnValues(allocator, tokens, return_idx + 1, end_idx, &return_active_locals, ctx, result_items, &move_names, out);
        } else if (result_tys.len > 1) {
            try emitMultiResultReturnAbiValues(allocator, tokens, return_idx + 1, end_idx, &return_active_locals, ctx, result_tys, &move_names, out);
        } else {
            if (result_tys.len != 1) return error.NoMatchingCall;
            const move_ctx = CallLastUseMoveContext{
                .body_start = body_start,
                .stmt_end = end_idx,
                .body_end = end_idx,
                .defer_ctx = defer_ctx,
                .allow_last_use_move = true,
                .allow_field_read_move = true,
            };
            try emitSingleReturnAbiValue(allocator, tokens, return_idx + 1, end_idx, &return_active_locals, ctx, result_tys[0], &move_names, &move_ctx, out);
        }
    } else if (result_tys.len != 0) {
        return error.NoMatchingCall;
    }
    try emitDeferCleanupStack(allocator, tokens, defer_ctx, locals, ctx, out);
    if (return_label) |label| {
        try appendFmt(allocator, out, "      br ${s}\n", .{label});
    } else {
        try out.appendSlice(allocator, "      ;; arc-guard-return-release\n");
        const release_plan = try buildGuardReturnOwnershipPlan(allocator, return_cleanup_locals, ctx, move_names.items);
        defer release_plan.deinit(allocator);
        try emitOwnershipReleasePlan(allocator, release_plan, out);
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
    body_start: usize,
    locals: *const LocalSet,
    return_cleanup_locals: *const LocalSet,
    control_cleanup_locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_items: []const FuncResultItem,
    result_struct: ?[]const u8,
    result_union: ?UnionLayout,
    loop_ctx: ?LoopControl,
    defer_ctx: ?*const DeferContext,
    return_label: ?[]const u8,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (start_idx + 3 > end_idx) return false;
    if (!tokEq(tokens[start_idx], "loop")) return false;
    const open_brace = findTopLevelBlockOpen(tokens, start_idx + 1, end_idx) orelse return false;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return false;
    if (close_brace + 1 != end_idx) return false;
    const loop_label = labelForLoopStart(tokens, start_idx);
    if (fieldReflectionLoopHeader(tokens, start_idx, end_idx, ctx, locals)) |header| {
        return try emitFieldReflectionLoopBlock(allocator, tokens, header, body_start, locals, return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, defer_ctx, return_label, out);
    }
    if (collectionLoopHeader(tokens, start_idx, end_idx, ctx, locals)) |header| {
        return try emitCollectionLoopBlock(allocator, tokens, start_idx, header, body_start, loop_label, locals, return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, defer_ctx, return_label, out);
    }
    if (recvLoopHeader(tokens, start_idx, end_idx, ctx, locals)) |header| {
        return try emitRecvLoopBlock(allocator, tokens, start_idx, header, body_start, loop_label, locals, return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, defer_ctx, return_label, out);
    }
    if (open_brace != start_idx + 1) {
        return error.UnsupportedExpr;
    }

    const break_label = try std.fmt.allocPrint(allocator, "__loop_break_{d}", .{start_idx});
    defer allocator.free(break_label);
    const body_label = try std.fmt.allocPrint(allocator, "__loop_body_{d}", .{start_idx});
    defer allocator.free(body_label);

    try out.appendSlice(allocator, "    ;; loop-block\n");
    try appendFmt(allocator, out, "    block ${s}\n", .{break_label});
    try appendFmt(allocator, out, "    loop ${s}\n", .{body_label});
    var loop_locals = LocalSet{};
    defer loop_locals.deinit(allocator);
    try collectDirectBodyLocals(allocator, tokens, open_brace + 1, close_brace, ctx, &loop_locals);
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
    const nested_loop = LoopControl{
        .parent = if (loop_ctx) |*control| control else null,
        .source_label = loop_label,
        .break_label = break_label,
        .continue_label = body_label,
        .cleanup_locals = &loop_locals,
        .defer_ctx = &loop_defer,
    };
    var active_return_cleanup_locals = try mergeReturnCleanupLocals(allocator, return_cleanup_locals, &loop_locals);
    defer active_return_cleanup_locals.deinit(allocator);
    try emitBody(allocator, tokens, open_brace + 1, close_brace, body_start, locals, &active_return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, nested_loop, &loop_defer, return_label, null, out);
    if (bodyCanReachEnd(tokens, open_brace + 1, close_brace)) {
        try emitBlockReleaseManagedLocals(allocator, &loop_locals, ctx, out);
        try appendFmt(allocator, out, "    br ${s}\n", .{body_label});
    }
    try out.appendSlice(allocator, "    end\n");
    try out.appendSlice(allocator, "    end\n");
    if (!loopBodyCanBreakCurrentLoop(tokens, open_brace + 1, close_brace, loop_label)) {
        try out.appendSlice(allocator, "    unreachable\n");
    }
    return true;
}

fn emitFieldReflectionLoopBlock(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    header: FieldReflectionLoopHeader,
    body_start: usize,
    locals: *const LocalSet,
    return_cleanup_locals: *const LocalSet,
    control_cleanup_locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_items: []const FuncResultItem,
    result_struct: ?[]const u8,
    result_union: ?UnionLayout,
    loop_ctx: ?LoopControl,
    defer_ctx: ?*const DeferContext,
    return_label: ?[]const u8,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const source_label = labelForLoopStart(tokens, header.loop_idx);
    const break_label = try std.fmt.allocPrint(allocator, "__field_break_{d}", .{header.loop_idx});
    defer allocator.free(break_label);

    try appendFmt(allocator, out, "    ;; field-reflect-loop type={s}\n", .{header.decl.name});
    try appendFmt(allocator, out, "    block ${s}\n", .{break_label});
    var visible_index: usize = 0;
    for (header.decl.fields, 0..) |field, decl_index| {
        if (!fieldVisibleFromTokens(field, header.decl, tokens)) continue;
        const prefix = try fieldReflectionLocalNamePrefix(allocator, header, visible_index);
        defer allocator.free(prefix);
        const continue_label = try std.fmt.allocPrint(allocator, "__field_continue_{d}_{d}", .{ header.loop_idx, visible_index });
        defer allocator.free(continue_label);
        var field_locals = try borrowedFieldMetaLocalSet(allocator, locals, .{
            .name = header.field_name,
            .struct_name = header.decl.name,
            .decl_index = decl_index,
            .visible_index = visible_index,
        }, prefix);
        defer field_locals.deinit(allocator);
        field_locals.local_name_prefix = prefix;
        try collectFieldReflectionBodyLocals(allocator, tokens, header.open_brace + 1, header.close_brace, ctx, &field_locals);
        var field_cleanup_locals = try fieldReflectionScopedCleanupLocalSet(allocator, &field_locals, prefix);
        defer field_cleanup_locals.deinit(allocator);
        const field_loop = LoopControl{
            .parent = if (loop_ctx) |*control| control else null,
            .source_label = source_label,
            .break_label = break_label,
            .continue_label = continue_label,
            .cleanup_locals = &field_cleanup_locals,
            .defer_ctx = defer_ctx orelse return error.NoMatchingCall,
        };
        try appendFmt(allocator, out, "    block ${s}\n", .{continue_label});
        var active_return_cleanup_locals = try mergeReturnCleanupLocals(allocator, return_cleanup_locals, &field_cleanup_locals);
        defer active_return_cleanup_locals.deinit(allocator);
        var active_control_cleanup_locals = try mergeReturnCleanupLocals(allocator, control_cleanup_locals, &field_cleanup_locals);
        defer active_control_cleanup_locals.deinit(allocator);
        try emitFieldReflectionBody(allocator, tokens, header.open_brace + 1, header.close_brace, body_start, &field_locals, &active_return_cleanup_locals, &active_control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, field_loop, defer_ctx, return_label, out);
        if (bodyCanReachEnd(tokens, header.open_brace + 1, header.close_brace)) {
            try emitBlockReleaseManagedLocals(allocator, &field_cleanup_locals, ctx, out);
        }
        try out.appendSlice(allocator, "    end\n");
        visible_index += 1;
    }
    try out.appendSlice(allocator, "    end\n");
    return true;
}

fn fieldReflectionScopedCleanupLocalSet(
    allocator: std.mem.Allocator,
    source: *const LocalSet,
    scoped_prefix: []const u8,
) !LocalSet {
    var out = LocalSet{};
    errdefer out.deinit(allocator);
    for (source.locals.items) |local| {
        if (!std.mem.startsWith(u8, local.name, scoped_prefix)) continue;
        try out.locals.append(allocator, .{
            .name = local.name,
            .source_name = local.source_name,
            .ty = local.ty,
            .emit_decl = false,
            .release_on_scope_exit = true,
        });
    }
    return out;
}

fn emitFieldReflectionBody(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_start: usize,
    locals: *const LocalSet,
    return_cleanup_locals: *const LocalSet,
    control_cleanup_locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_items: []const FuncResultItem,
    result_struct: ?[]const u8,
    result_union: ?UnionLayout,
    loop_ctx: ?LoopControl,
    defer_ctx: ?*const DeferContext,
    return_label: ?[]const u8,
    out: *std.ArrayList(u8),
) CodegenError!void {
    var i = start_idx;
    var segment_start = start_idx;
    while (i < end_idx) {
        const stmt_end = findStmtEnd(tokens, i, end_idx);
        if (fieldReflectionIfParts(tokens, i, stmt_end)) |parts| {
            if (fieldStaticBoolExpr(tokens, parts.cond_start, parts.cond_end, locals, ctx)) |condition| {
                if (segment_start < i) {
                    try emitBody(allocator, tokens, segment_start, i, body_start, locals, return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, defer_ctx, return_label, null, out);
                }
                if (condition) {
                    try emitFieldReflectionBody(allocator, tokens, parts.then_start, parts.then_end, body_start, locals, return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, defer_ctx, return_label, out);
                } else if (parts.else_if_start) |nested_if| {
                    try emitFieldReflectionBody(allocator, tokens, nested_if, stmt_end, body_start, locals, return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, defer_ctx, return_label, out);
                } else if (parts.else_start) |else_start| {
                    try emitFieldReflectionBody(allocator, tokens, else_start, parts.else_end, body_start, locals, return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, defer_ctx, return_label, out);
                }
                i = stmt_end;
                segment_start = stmt_end;
                continue;
            }
        }
        i = stmt_end;
    }
    if (segment_start < end_idx) {
        try emitBody(allocator, tokens, segment_start, end_idx, body_start, locals, return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, defer_ctx, return_label, null, out);
    }
}

fn borrowedFieldMetaLocalSet(
    allocator: std.mem.Allocator,
    parent: *const LocalSet,
    meta: FieldMetaLocal,
    scoped_prefix: []const u8,
) !LocalSet {
    var out = LocalSet{};
    errdefer out.deinit(allocator);
    for (parent.locals.items) |local| {
        if (!fieldReflectionLocalVisible(local.name, scoped_prefix)) continue;
        try out.locals.append(allocator, local);
    }
    for (parent.struct_locals.items) |local| {
        if (!fieldReflectionLocalVisible(local.name, scoped_prefix)) continue;
        try out.struct_locals.append(allocator, local);
    }
    for (parent.storage_locals.items) |local| {
        if (!fieldReflectionLocalVisible(local.name, scoped_prefix)) continue;
        try out.storage_locals.append(allocator, local);
    }
    for (parent.union_locals.items) |union_local| {
        if (!fieldReflectionLocalVisible(union_local.name, scoped_prefix)) continue;
        try out.union_locals.append(allocator, .{
            .name = union_local.name,
            .source_name = union_local.source_name,
            .layout = union_local.layout,
            .owns_layout = false,
        });
    }
    try out.field_meta_locals.appendSlice(allocator, parent.field_meta_locals.items);
    try out.field_meta_locals.append(allocator, meta);
    return out;
}

fn fieldReflectionLocalVisible(name: []const u8, scoped_prefix: []const u8) bool {
    if (!std.mem.startsWith(u8, name, "__field_")) return true;
    return std.mem.startsWith(u8, name, scoped_prefix);
}

fn loopBodyCanBreakCurrentLoop(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    loop_label: ?[]const u8,
) bool {
    if (loop_label) |label| {
        if (tokenRangeContainsLabeledBreak(tokens, start_idx, end_idx, label)) return true;
    }

    var i = start_idx;
    while (i < end_idx) {
        const stmt_end = findStmtEnd(tokens, i, end_idx);
        if (stmtBreaksCurrentLoop(tokens, i, stmt_end, loop_label)) return true;
        i = stmt_end;
    }
    return false;
}

fn stmtBreaksCurrentLoop(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    loop_label: ?[]const u8,
) bool {
    if (start_idx >= end_idx) return false;
    if (tokEq(tokens[start_idx], "break")) return breakTargetsCurrentLoop(tokens, start_idx, end_idx, loop_label);
    if (!tokEq(tokens[start_idx], "if")) return false;
    const control_idx = findTopLevelGuardLoopControl(tokens, start_idx + 1, end_idx) orelse return false;
    if (!tokEq(tokens[control_idx], "break")) return false;
    return breakTargetsCurrentLoop(tokens, control_idx, end_idx, loop_label);
}

fn breakTargetsCurrentLoop(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    loop_label: ?[]const u8,
) bool {
    if (end_idx == start_idx + 1) return true;
    if (end_idx != start_idx + 3 or !tokEq(tokens[start_idx + 1], "#")) return false;
    const label = loop_label orelse return false;
    return tokens[start_idx + 2].kind == .ident and std.mem.eql(u8, tokens[start_idx + 2].lexeme, label);
}

fn tokenRangeContainsLabeledBreak(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    label: []const u8,
) bool {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEq(tokens[i], "loop")) {
            if (labelForLoopStart(tokens, i)) |nested_label| {
                if (std.mem.eql(u8, nested_label, label)) {
                    const open_brace = findTopLevelBlockOpen(tokens, i + 1, end_idx) orelse continue;
                    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch continue;
                    i = close_brace;
                    continue;
                }
            }
        }

        if (i + 2 >= end_idx) continue;
        if (!tokEq(tokens[i], "break")) continue;
        if (!tokEq(tokens[i + 1], "#")) continue;
        if (tokens[i + 2].kind != .ident) continue;
        if (std.mem.eql(u8, tokens[i + 2].lexeme, label)) return true;
    }
    return false;
}

fn emitCollectionLoopBlock(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    header: CollectionLoopHeader,
    body_start: usize,
    loop_label: ?[]const u8,
    locals: *const LocalSet,
    return_cleanup_locals: *const LocalSet,
    control_cleanup_locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_items: []const FuncResultItem,
    result_struct: ?[]const u8,
    result_union: ?UnionLayout,
    parent_loop_ctx: ?LoopControl,
    defer_ctx: ?*const DeferContext,
    return_label: ?[]const u8,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const break_label = try std.fmt.allocPrint(allocator, "__loop_break_{d}", .{start_idx});
    defer allocator.free(break_label);
    const body_label = try std.fmt.allocPrint(allocator, "__loop_body_{d}", .{start_idx});
    defer allocator.free(body_label);
    const continue_label = try std.fmt.allocPrint(allocator, "__loop_continue_{d}", .{start_idx});
    defer allocator.free(continue_label);
    const index_local = try std.fmt.allocPrint(allocator, "__loop_index_{d}", .{start_idx});
    defer allocator.free(index_local);
    const owned_source_name = if (header.source_is_expr) try loopSourceLocalName(allocator, start_idx) else null;
    defer if (owned_source_name) |name| allocator.free(name);
    const source_name = owned_source_name orelse header.source_name;
    var loop_header = header;
    loop_header.source_name = source_name;

    if (header.source_is_expr) {
        if (!try emitExpr(allocator, tokens, header.source_start, header.source_end, locals, ctx, header.source_ty, out)) {
            return error.NoMatchingCall;
        }
        if (isDirectManagedLocalExpr(tokens, header.source_start, header.source_end, locals, ctx)) {
            try out.appendSlice(allocator, "    call $__arc_inc\n");
        }
        try appendFmt(allocator, out, "    local.set ${s}\n", .{source_name});
    }

    try out.appendSlice(allocator, "    ;; loop-collection\n");
    try out.appendSlice(allocator, "    i32.const 0\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{index_local});
    try appendFmt(allocator, out, "    block ${s}\n", .{break_label});
    try appendFmt(allocator, out, "    loop ${s}\n", .{body_label});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{index_local});
    try emitStorageLenPtr(allocator, out, source_name);
    try out.appendSlice(allocator, "    i32.load\n");
    try out.appendSlice(allocator, "    i32.ge_u\n");
    try appendFmt(allocator, out, "    br_if ${s}\n", .{break_label});
    try emitCollectionLoopBindings(allocator, loop_header, index_local, ctx, out);
    try appendFmt(allocator, out, "    block ${s}\n", .{continue_label});

    var loop_locals = LocalSet{};
    defer loop_locals.deinit(allocator);
    if (header.value_name) |value_name| {
        if (isManagedLocalType(header.elem_ty, ctx)) {
            try loop_locals.appendBorrowedLocalWithOrigin(allocator, value_name, header.elem_ty, false, .collection_value);
        }
    }
    try collectDirectBodyLocals(allocator, tokens, header.open_brace + 1, header.close_brace, ctx, &loop_locals);
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
        .start_idx = header.open_brace + 1,
        .end_idx = header.close_brace,
        .registered_end_idx = header.close_brace,
    };
    const nested_loop = LoopControl{
        .parent = if (parent_loop_ctx) |*control| control else null,
        .source_label = loop_label,
        .break_label = break_label,
        .continue_label = continue_label,
        .cleanup_locals = &loop_locals,
        .defer_ctx = &loop_defer,
    };
    var active_return_cleanup_locals = try mergeReturnCleanupLocals(allocator, return_cleanup_locals, &loop_locals);
    defer active_return_cleanup_locals.deinit(allocator);
    try emitBody(allocator, tokens, header.open_brace + 1, header.close_brace, body_start, locals, &active_return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, nested_loop, &loop_defer, return_label, null, out);
    if (bodyCanReachEnd(tokens, header.open_brace + 1, header.close_brace)) {
        try emitBlockReleaseManagedLocals(allocator, &loop_locals, ctx, out);
    }
    try out.appendSlice(allocator, "    end\n");
    if (bodyCanReachEnd(tokens, header.open_brace + 1, header.close_brace)) {
        try appendFmt(allocator, out, "    local.get ${s}\n", .{index_local});
        try out.appendSlice(allocator, "    i32.const 1\n");
        try out.appendSlice(allocator, "    i32.add\n");
        try appendFmt(allocator, out, "    local.set ${s}\n", .{index_local});
        try appendFmt(allocator, out, "    br ${s}\n", .{body_label});
    }
    try out.appendSlice(allocator, "    end\n");
    try out.appendSlice(allocator, "    end\n");
    return true;
}

fn emitCollectionLoopBindings(
    allocator: std.mem.Allocator,
    header: CollectionLoopHeader,
    index_local: []const u8,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!void {
    if (header.index_name) |index_name| {
        try appendFmt(allocator, out, "    local.get ${s}\n", .{index_local});
        try appendFmt(allocator, out, "    local.set ${s}\n", .{index_name});
    }
    if (header.value_name) |value_name| {
        if (isTupleTypeName(header.elem_ty)) {
            try emitStorageElementPtrFromLocal(allocator, out, header.source_name, index_local, header.elem_bytes);
            try appendFmt(allocator, out, "    local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
            try appendLoadTupleLeavesOwningToStackCtx(allocator, out, header.elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "    ", ctx);
            try emitTupleLocalSet(allocator, value_name, header.elem_ty, ctx, out);
        } else {
            try emitStorageElementPtrFromLocal(allocator, out, header.source_name, index_local, header.elem_bytes);
            try appendLoadForPayloadType(allocator, out, header.elem_ty);
            if (isManagedLocalType(header.elem_ty, ctx)) {
                try out.appendSlice(allocator, "    call $__arc_inc\n");
            }
            try appendFmt(allocator, out, "    local.set ${s}\n", .{value_name});
        }
    }
}

fn emitRecvLoopBlock(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    header: RecvLoopHeader,
    body_start: usize,
    loop_label: ?[]const u8,
    locals: *const LocalSet,
    return_cleanup_locals: *const LocalSet,
    control_cleanup_locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_items: []const FuncResultItem,
    result_struct: ?[]const u8,
    result_union: ?UnionLayout,
    parent_loop_ctx: ?LoopControl,
    defer_ctx: ?*const DeferContext,
    return_label: ?[]const u8,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const break_label = try std.fmt.allocPrint(allocator, "__loop_break_{d}", .{start_idx});
    defer allocator.free(break_label);
    const body_label = try std.fmt.allocPrint(allocator, "__loop_body_{d}", .{start_idx});
    defer allocator.free(body_label);
    const continue_label = try std.fmt.allocPrint(allocator, "__loop_continue_{d}", .{start_idx});
    defer allocator.free(continue_label);
    const count_local = try std.fmt.allocPrint(allocator, "__loop_count_{d}", .{start_idx});
    defer allocator.free(count_local);

    try out.appendSlice(allocator, "    ;; loop-recv\n");
    try out.appendSlice(allocator, "    i32.const 0\n");
    try appendFmt(allocator, out, "    local.set ${s}\n", .{count_local});
    try appendFmt(allocator, out, "    block ${s}\n", .{break_label});
    try appendFmt(allocator, out, "    loop ${s}\n", .{body_label});
    try appendFmt(allocator, out, "    local.get ${s}\n", .{count_local});
    try emitStorageLenPtr(allocator, out, header.source_name);
    try out.appendSlice(allocator, "    i32.load\n");
    try out.appendSlice(allocator, "    i32.ge_u\n");
    try appendFmt(allocator, out, "    br_if ${s}\n", .{break_label});
    try emitRecvLoopBindings(allocator, header, count_local, ctx, out);
    try appendFmt(allocator, out, "    block ${s}\n", .{continue_label});

    var loop_locals = LocalSet{};
    defer loop_locals.deinit(allocator);
    if (header.value_name) |value_name| {
        if (isManagedLocalType(header.elem_ty, ctx)) {
            try loop_locals.appendBorrowedLocalWithOrigin(allocator, value_name, header.elem_ty, false, .recv_value);
        }
    }
    try collectDirectBodyLocals(allocator, tokens, header.open_brace + 1, header.close_brace, ctx, &loop_locals);
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
        .start_idx = header.open_brace + 1,
        .end_idx = header.close_brace,
        .registered_end_idx = header.close_brace,
    };
    const nested_loop = LoopControl{
        .parent = if (parent_loop_ctx) |*control| control else null,
        .source_label = loop_label,
        .break_label = break_label,
        .continue_label = continue_label,
        .cleanup_locals = &loop_locals,
        .defer_ctx = &loop_defer,
    };
    var active_return_cleanup_locals = try mergeReturnCleanupLocals(allocator, return_cleanup_locals, &loop_locals);
    defer active_return_cleanup_locals.deinit(allocator);
    try emitBody(allocator, tokens, header.open_brace + 1, header.close_brace, body_start, locals, &active_return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, nested_loop, &loop_defer, return_label, null, out);
    if (bodyCanReachEnd(tokens, header.open_brace + 1, header.close_brace)) {
        try emitBlockReleaseManagedLocals(allocator, &loop_locals, ctx, out);
    }
    try out.appendSlice(allocator, "    end\n");
    if (bodyCanReachEnd(tokens, header.open_brace + 1, header.close_brace)) {
        try appendFmt(allocator, out, "    local.get ${s}\n", .{count_local});
        try out.appendSlice(allocator, "    i32.const 1\n");
        try out.appendSlice(allocator, "    i32.add\n");
        try appendFmt(allocator, out, "    local.set ${s}\n", .{count_local});
        try appendFmt(allocator, out, "    br ${s}\n", .{body_label});
    }
    try out.appendSlice(allocator, "    end\n");
    try out.appendSlice(allocator, "    end\n");
    return true;
}

fn emitRecvLoopBindings(
    allocator: std.mem.Allocator,
    header: RecvLoopHeader,
    count_local: []const u8,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!void {
    if (header.count_name) |count_name| {
        try appendFmt(allocator, out, "    local.get ${s}\n", .{count_local});
        try appendFmt(allocator, out, "    local.set ${s}\n", .{count_name});
    }
    if (header.value_name) |value_name| {
        if (isTupleTypeName(header.elem_ty)) {
            try emitStorageElementPtrFromLocal(allocator, out, header.source_name, count_local, header.elem_bytes);
            try appendFmt(allocator, out, "    local.set ${s}\n", .{TUPLE_PACK_BASE_TMP_LOCAL});
            try appendLoadTupleLeavesOwningToStackCtx(allocator, out, header.elem_ty, TUPLE_PACK_BASE_TMP_LOCAL, "    ", ctx);
            try emitTupleLocalSet(allocator, value_name, header.elem_ty, ctx, out);
        } else {
            try emitStorageElementPtrFromLocal(allocator, out, header.source_name, count_local, header.elem_bytes);
            try appendLoadForPayloadType(allocator, out, header.elem_ty);
            if (isManagedLocalType(header.elem_ty, ctx)) {
                try out.appendSlice(allocator, "    call $__arc_inc\n");
            }
            try appendFmt(allocator, out, "    local.set ${s}\n", .{value_name});
        }
    }
}

fn emitLoopControlStmt(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    control_cleanup_locals: *const LocalSet,
    loop_ctx: ?LoopControl,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !bool {
    if (tokens[start_idx].kind != .ident) return false;
    if (std.mem.eql(u8, tokens[start_idx].lexeme, "break") or std.mem.eql(u8, tokens[start_idx].lexeme, "continue")) {
        if (!validLoopControlTail(tokens, start_idx, end_idx)) return error.UnsupportedExpr;
    } else {
        return false;
    }
    try emitLoopControlJump(allocator, tokens, start_idx, end_idx, loop_ctx, defer_ctx, locals, control_cleanup_locals, ctx, out);
    return true;
}

fn emitGuardLoopControlIf(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    control_cleanup_locals: *const LocalSet,
    loop_ctx: ?LoopControl,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !bool {
    if (start_idx + 3 > end_idx) return false;
    if (!tokEq(tokens[start_idx], "if")) return false;
    const control_idx = findTopLevelGuardLoopControl(tokens, start_idx + 1, end_idx) orelse return false;
    if (!validLoopControlTail(tokens, control_idx, end_idx)) return error.UnsupportedExpr;
    if (!try emitExpr(allocator, tokens, start_idx + 1, control_idx, locals, ctx, "bool", out)) {
        return error.NoMatchingCall;
    }
    try out.appendSlice(allocator, "    if\n");
    try emitLoopControlJump(allocator, tokens, control_idx, end_idx, loop_ctx, defer_ctx, locals, control_cleanup_locals, ctx, out);
    try out.appendSlice(allocator, "    end\n");
    return true;
}

fn emitLoopControlJump(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    loop_ctx: ?LoopControl,
    defer_ctx: ?*const DeferContext,
    locals: *const LocalSet,
    control_cleanup_locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) !void {
    const current_control = if (loop_ctx) |*control| control else return error.NoMatchingCall;
    const control = resolveLoopControl(tokens, start_idx, end_idx, current_control) orelse return error.NoMatchingCall;
    if (std.mem.eql(u8, tokens[start_idx].lexeme, "break")) {
        try emitDeferCleanupStackThrough(allocator, tokens, defer_ctx, control.defer_ctx, locals, ctx, out);
        try out.appendSlice(allocator, "    ;; loop-break-release\n");
        try emitBlockReleaseManagedLocals(allocator, control_cleanup_locals, ctx, out);
        try emitLoopControlReleaseChain(allocator, current_control, control, ctx, .break_stmt, out);
        try appendFmt(allocator, out, "    br ${s}\n", .{control.break_label});
        return;
    }
    if (std.mem.eql(u8, tokens[start_idx].lexeme, "continue")) {
        try emitDeferCleanupStackThrough(allocator, tokens, defer_ctx, control.defer_ctx, locals, ctx, out);
        try out.appendSlice(allocator, "    ;; loop-continue-release\n");
        try emitBlockReleaseManagedLocals(allocator, control_cleanup_locals, ctx, out);
        try emitLoopControlReleaseChain(allocator, current_control, control, ctx, .continue_stmt, out);
        try appendFmt(allocator, out, "    br ${s}\n", .{control.continue_label});
        return;
    }
    return error.NoMatchingCall;
}

fn validLoopControlTail(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (end_idx == start_idx + 1) return true;
    return end_idx == start_idx + 3 and tokEq(tokens[start_idx + 1], "#") and tokens[start_idx + 2].kind == .ident;
}

fn findTopLevelGuardLoopControl(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
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
        if (depth_paren != 0 or depth_brace != 0 or depth_angle != 0) continue;
        if (tokEq(tokens[i], "break") or tokEq(tokens[i], "continue")) return i;
    }
    return null;
}

fn resolveLoopControl(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    first: *const LoopControl,
) ?*const LoopControl {
    if (end_idx == start_idx + 1) return first;
    const target_label = tokens[start_idx + 2].lexeme;
    var cursor: ?*const LoopControl = first;
    while (cursor) |control| {
        if (control.source_label) |label| {
            if (std.mem.eql(u8, label, target_label)) return control;
        }
        cursor = control.parent;
    }
    return null;
}

fn emitLoopControlReleaseChain(
    allocator: std.mem.Allocator,
    start: *const LoopControl,
    target: *const LoopControl,
    ctx: CodegenContext,
    kind: ownership.ExitKind,
    out: *std.ArrayList(u8),
) !void {
    const frames = try collectLoopControlFrames(allocator, start, target, ctx);
    defer frames.deinit(allocator);
    const release_plan = try ownership.buildLoopControlExitPlan(allocator, kind, frames.frames);
    defer release_plan.deinit(allocator);
    try emitOwnershipReleasePlan(allocator, release_plan, out);
}

fn sameLoopControl(a: *const LoopControl, b: *const LoopControl) bool {
    return std.mem.eql(u8, a.break_label, b.break_label);
}

fn emitIfBlock(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_start: usize,
    locals: *const LocalSet,
    return_cleanup_locals: *const LocalSet,
    control_cleanup_locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_items: []const FuncResultItem,
    result_struct: ?[]const u8,
    result_union: ?UnionLayout,
    loop_ctx: ?LoopControl,
    defer_ctx: ?*const DeferContext,
    return_label: ?[]const u8,
    self_tail_tco: ?*const SelfTailTco,
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
    try collectDirectBodyLocals(allocator, tokens, open_brace + 1, close_brace, ctx, &then_locals);
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
    var then_return_cleanup_locals = try mergeReturnCleanupLocals(allocator, return_cleanup_locals, &then_locals);
    defer then_return_cleanup_locals.deinit(allocator);
    var then_control_cleanup_locals = try mergeReturnCleanupLocals(allocator, control_cleanup_locals, &then_locals);
    defer then_control_cleanup_locals.deinit(allocator);
    var then_active_locals = try cloneLocalSet(allocator, locals);
    defer then_active_locals.deinit(allocator);
    try appendConditionNarrowingForBranch(allocator, tokens, start_idx + 1, open_brace, &then_active_locals, ctx, true);
    try emitBody(allocator, tokens, open_brace + 1, close_brace, body_start, &then_active_locals, &then_return_cleanup_locals, &then_control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, &then_defer, return_label, self_tail_tco, out);
    if (bodyCanReachEnd(tokens, open_brace + 1, close_brace)) {
        try emitBlockReleaseManagedLocals(allocator, &then_locals, ctx, out);
    }
    if (else_if_start) |nested_if| {
        try out.appendSlice(allocator, "    else\n");
        var else_if_active_locals = try cloneLocalSet(allocator, locals);
        defer else_if_active_locals.deinit(allocator);
        try appendConditionNarrowingForBranch(allocator, tokens, start_idx + 1, open_brace, &else_if_active_locals, ctx, false);
        if (!try emitIfBlock(allocator, tokens, nested_if, end_idx, body_start, &else_if_active_locals, return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, defer_ctx, return_label, self_tail_tco, out)) return false;
    } else if (else_open) |open_else| {
        const close_else = else_close orelse return false;
        try out.appendSlice(allocator, "    else\n");
        var else_locals = LocalSet{};
        defer else_locals.deinit(allocator);
        try collectDirectBodyLocals(allocator, tokens, open_else + 1, close_else, ctx, &else_locals);
        const else_defer = DeferContext{
            .parent = parent_defer_ptr,
            .start_idx = open_else + 1,
            .end_idx = close_else,
            .registered_end_idx = close_else,
        };
        var else_return_cleanup_locals = try mergeReturnCleanupLocals(allocator, return_cleanup_locals, &else_locals);
        defer else_return_cleanup_locals.deinit(allocator);
        var else_control_cleanup_locals = try mergeReturnCleanupLocals(allocator, control_cleanup_locals, &else_locals);
        defer else_control_cleanup_locals.deinit(allocator);
        var else_active_locals = try cloneLocalSet(allocator, locals);
        defer else_active_locals.deinit(allocator);
        try appendConditionNarrowingForBranch(allocator, tokens, start_idx + 1, open_brace, &else_active_locals, ctx, false);
        try emitBody(allocator, tokens, open_else + 1, close_else, body_start, &else_active_locals, &else_return_cleanup_locals, &else_control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, &else_defer, return_label, self_tail_tco, out);
        if (bodyCanReachEnd(tokens, open_else + 1, close_else)) {
            try emitBlockReleaseManagedLocals(allocator, &else_locals, ctx, out);
        }
    }
    try out.appendSlice(allocator, "    end\n");
    return true;
}

fn wasmType(ty: []const u8) []const u8 {
    return payload_wat.wasmType(ty);
}

fn valueEnumCarrier(ctx: CodegenContext, ty: []const u8) ?[]const u8 {
    const decl = findValueEnumDecl(ctx.value_enums, ty) orelse return null;
    return decl.carrier;
}

fn codegenScalarType(ctx: CodegenContext, ty: []const u8) []const u8 {
    return valueEnumCarrier(ctx, ty) orelse ty;
}

fn codegenWasmType(ctx: CodegenContext, ty: []const u8) []const u8 {
    return wasmType(codegenScalarType(ctx, ty));
}

fn isCodegenScalarType(ctx: CodegenContext, ty: []const u8) bool {
    return isCoreWasmScalar(ty) or valueEnumCarrier(ctx, ty) != null;
}

fn isCodegenScalarOrErrorType(tokens: []const lexer.Token, ctx: CodegenContext, ty: []const u8) bool {
    return isCodegenScalarType(ctx, ty) or isErrorLikeType(tokens, ty);
}

fn valueEnumBranchValue(
    ctx: CodegenContext,
    tokens: []const lexer.Token,
    enum_name: []const u8,
    branch_name: []const u8,
) ?[]const u8 {
    if (findValueEnumDecl(ctx.value_enums, enum_name)) |decl| {
        if (findValueEnumBranchValue(decl, branch_name)) |value| return value;
    }
    const import_ref = findCodegenImportByAlias(tokens, branch_name) orelse return null;
    for (ctx.modules) |module| {
        if (!valueEnumSourceMatchesImport(module.tokens, import_ref)) continue;
        const enum_idx = findValueEnumDeclLineByBranch(module.tokens, import_ref.target) orelse return null;
        if (!valueEnumTypeMatchesImportAlias(ctx, module.tokens, enum_idx, enum_name)) return null;
        return valueEnumBranchValueInLine(module.tokens, enum_idx, import_ref.target);
    }
    return null;
}

fn valueEnumTypeMatchesImportAlias(
    ctx: CodegenContext,
    tokens: []const lexer.Token,
    enum_idx: usize,
    expected_name: []const u8,
) bool {
    const source_name = publicDeclName(tokens[enum_idx].lexeme);
    if (std.mem.eql(u8, source_name, expected_name)) return true;
    const decl = findValueEnumDecl(ctx.value_enums, expected_name) orelse return false;
    return std.mem.eql(u8, decl.source_name, source_name);
}

fn findValueEnumBranchValue(decl: ValueEnumDecl, branch_name: []const u8) ?[]const u8 {
    for (decl.branches) |branch| {
        if (std.mem.eql(u8, branch.name, branch_name)) return branch.value;
    }
    return null;
}

fn valueEnumBranchValueInLine(tokens: []const lexer.Token, enum_idx: usize, branch_name: []const u8) ?[]const u8 {
    const line_end = findLineEnd(tokens, enum_idx);
    var j = enum_idx + 3;
    while (j + 3 < line_end) {
        if (tokEq(tokens[j], "|")) {
            j += 1;
            continue;
        }
        if (tokens[j].kind == .ident and std.mem.eql(u8, publicDeclName(tokens[j].lexeme), branch_name)) return tokens[j + 2].lexeme;
        j += 4;
    }
    return null;
}

fn valueEnumSourceMatchesImport(tokens: []const lexer.Token, import_ref: CodegenImportRef) bool {
    if (findValueEnumDeclLineByName(tokens, import_ref.target) != null) return true;
    return findValueEnumDeclLineByBranch(tokens, import_ref.target) != null;
}

fn typePayloadBytes(ty: []const u8) usize {
    return type_util.typePayloadBytes(ty);
}

fn typePayloadAlignment(ty: []const u8) usize {
    return type_util.typePayloadAlignment(ty);
}

fn isManagedPayloadType(ty: []const u8) bool {
    return type_util.isManagedPayloadType(ty);
}

fn managedPayloadElemTypeFromName(ty: []const u8) ?[]const u8 {
    return type_util.managedPayloadElemTypeFromName(ty);
}

fn storageTypeNameForElem(elem_ty: []const u8) ?[]const u8 {
    return type_util.storageTypeNameForElem(elem_ty);
}

fn storageTypeNameForElemOwned(
    allocator: std.mem.Allocator,
    elem_ty: []const u8,
    owned_types: *std.ArrayList([]const u8),
) ![]const u8 {
    if (storageTypeNameForElem(elem_ty)) |ty| return ty;
    const owned = try std.fmt.allocPrint(allocator, "[{s}]", .{elem_ty});
    errdefer allocator.free(owned);
    try owned_types.append(allocator, owned);
    return owned;
}

fn isStorageTypeName(ty: []const u8) bool {
    return type_util.isStorageTypeName(ty);
}

fn storageElemTypeFromName(ty: []const u8) ?[]const u8 {
    return type_util.storageElemTypeFromName(ty);
}

fn storageElementByteWidth(elem_ty: []const u8) ?usize {
    return type_util.storageElementByteWidth(elem_ty);
}

/// Pure-scalar unmanaged struct nested pack width (declaration order + alignUp, no managed fields).
fn pureScalarStructPackWidth(decl: StructDecl, structs: []const StructDecl) ?usize {
    if (decl.fields.len == 0) return null;
    var offset: usize = 0;
    for (decl.fields) |field| {
        const field_ty = field.ty;
        if (type_util.isManagedPayloadType(field_ty)) return null;
        if (isTupleTypeName(field_ty)) {
            // Nested Tuple inside pure-scalar struct: recursive width without managed.
            const w = tuplePackWidthWithStructs(field_ty, structs) orelse return null;
            offset = alignUp(offset, typePayloadAlignment(field_ty));
            offset += w;
            continue;
        }
        if (findStructDecl(structs, field_ty)) |nested| {
            // Nested managed struct inside pure-scalar parent is not pure-scalar.
            if (structDeclHasManagedField(nested, structs)) return null;
            const w = pureScalarStructPackWidth(nested, structs) orelse return null;
            offset = alignUp(offset, 1);
            offset += w;
            continue;
        }
        if (!type_util.isCoreWasmScalar(field_ty)) return null;
        offset = alignUp(offset, typePayloadAlignment(field_ty));
        offset += typePayloadBytes(field_ty);
    }
    return offset;
}

/// True when a named struct carries managed payload (directly or nested) and lowers as ARC handle.
fn structDeclHasManagedField(decl: StructDecl, structs: []const StructDecl) bool {
    for (decl.fields) |field| {
        if (type_util.isManagedPayloadType(field.ty)) return true;
        if (findStructDecl(structs, field.ty)) |nested| {
            if (structDeclHasManagedField(nested, structs)) return true;
        }
    }
    return false;
}

/// Terminal pack leaf that is a managed object handle (text / [T] / managed struct).
fn isPackManagedHandleLeaf(ty: []const u8, structs: []const StructDecl) bool {
    if (type_util.isManagedPayloadType(ty)) return true;
    const decl = findStructDecl(structs, ty) orelse return false;
    return structDeclHasManagedField(decl, structs);
}

/// Terminal leaf storeable in scheme-A pack (scalar, managed payload, or managed-struct handle).
fn isPackTerminalLeafType(ty: []const u8, structs: []const StructDecl) bool {
    if (type_util.isTuplePackableLeafType(ty)) return true;
    return isPackManagedHandleLeaf(ty, structs);
}

fn packSlotWidth(ty: []const u8, structs: []const StructDecl) ?usize {
    if (isTupleTypeName(ty)) return tuplePackWidthWithStructs(ty, structs);
    if (findStructDecl(structs, ty)) |decl| {
        if (pureScalarStructPackWidth(decl, structs)) |w| return w;
        // Managed struct direct slot: one i32 ARC handle (never flatten fields into Tuple).
        if (structDeclHasManagedField(decl, structs)) return 4;
        return null;
    }
    if (type_util.isTuplePackableLeafType(ty)) return typePayloadBytes(ty);
    return null;
}

/// Scheme A element width: scalar, managed handle, nested Tuple, pure-scalar struct sub-layout,
/// or managed-struct handle slot (never type-flatten).
fn tuplePackWidthWithStructs(tuple_ty: []const u8, structs: []const StructDecl) ?usize {
    if (!isTupleTypeName(tuple_ty)) return null;
    const arity = tupleArity(tuple_ty) orelse return null;
    var total: usize = 0;
    var idx: usize = 0;
    while (idx < arity) : (idx += 1) {
        const elem_ty = tupleElementTypeAt(tuple_ty, idx) orelse return null;
        total += packSlotWidth(elem_ty, structs) orelse return null;
    }
    return total;
}

fn tupleElementPackOffsetWithStructs(tuple_ty: []const u8, index: usize, structs: []const StructDecl) ?usize {
    if (!isTupleTypeName(tuple_ty)) return null;
    const arity = tupleArity(tuple_ty) orelse return null;
    if (index >= arity) return null;
    var offset: usize = 0;
    var idx: usize = 0;
    while (idx < index) : (idx += 1) {
        const elem_ty = tupleElementTypeAt(tuple_ty, idx) orelse return null;
        offset += packSlotWidth(elem_ty, structs) orelse return null;
    }
    return offset;
}

/// Append terminal pack leaf types in order.
/// Pure-scalar struct fields expand nested; managed-struct slots stay one handle leaf (type name).
fn appendTupleLeafTypesWithStructs(
    allocator: std.mem.Allocator,
    ty: []const u8,
    structs: []const StructDecl,
    out: *std.ArrayList([]const u8),
) CodegenError!void {
    if (isTupleTypeName(ty)) {
        const arity = tupleArity(ty) orelse return error.UnsupportedLowering;
        var idx: usize = 0;
        while (idx < arity) : (idx += 1) {
            const elem_ty = tupleElementTypeAt(ty, idx) orelse return error.UnsupportedLowering;
            try appendTupleLeafTypesWithStructs(allocator, elem_ty, structs, out);
        }
        return;
    }
    if (findStructDecl(structs, ty)) |decl| {
        if (structDeclHasManagedField(decl, structs)) {
            // Managed struct: single ARC handle leaf; do not expand fields into the pack.
            try out.append(allocator, ty);
            return;
        }
        if (pureScalarStructPackWidth(decl, structs) == null) return error.UnsupportedTupleStorageLeaf;
        for (decl.fields) |field| {
            try appendTupleLeafTypesWithStructs(allocator, field.ty, structs, out);
        }
        return;
    }
    if (!type_util.isTuplePackableLeafType(ty)) return error.UnsupportedTupleStorageLeaf;
    try out.append(allocator, ty);
}

/// Scheme A: packed Tuple storage layout (scalar + managed + struct nested slots).
fn tupleScalarLeafStorageByteWidth(tuple_ty: []const u8) ?usize {
    return type_util.tupleScalarLeafStorageByteWidth(tuple_ty);
}

fn tupleScalarLeafStorageByteWidthCtx(tuple_ty: []const u8, ctx: CodegenContext) ?usize {
    if (tuplePackWidthWithStructs(tuple_ty, ctx.structs)) |w| return w;
    return type_util.tupleScalarLeafStorageByteWidth(tuple_ty);
}

fn tupleHasManagedPackLeaf(tuple_ty: []const u8) bool {
    return type_util.tupleHasManagedPackLeaf(tuple_ty);
}

fn tupleHasManagedPackLeafWithStructs(tuple_ty: []const u8, structs: []const StructDecl) bool {
    if (!isTupleTypeName(tuple_ty)) return false;
    const arity = tupleArity(tuple_ty) orelse return false;
    var idx: usize = 0;
    while (idx < arity) : (idx += 1) {
        const elem_ty = tupleElementTypeAt(tuple_ty, idx) orelse return false;
        if (isTupleTypeName(elem_ty)) {
            if (tupleHasManagedPackLeafWithStructs(elem_ty, structs)) return true;
            continue;
        }
        if (isPackManagedHandleLeaf(elem_ty, structs)) return true;
    }
    return false;
}

fn tupleHasManagedPackLeafCtx(tuple_ty: []const u8, ctx: CodegenContext) bool {
    if (tupleHasManagedPackLeafWithStructs(tuple_ty, ctx.structs)) return true;
    return tupleHasManagedPackLeaf(tuple_ty);
}

fn leafPayloadBytesForPack(leaf_ty: []const u8, structs: []const StructDecl) ?usize {
    if (type_util.isTuplePackableLeafType(leaf_ty)) return typePayloadBytes(leaf_ty);
    if (isPackManagedHandleLeaf(leaf_ty, structs)) return 4;
    return null;
}

fn storageElementByteWidthForType(elem_ty: []const u8, ctx: CodegenContext) ?usize {
    if (storageElementByteWidth(elem_ty)) |width| return width;
    if (tupleScalarLeafStorageByteWidthCtx(elem_ty, ctx)) |width| return width;
    if (isManagedLocalType(elem_ty, ctx)) return 4;
    return null;
}

fn tuplePackSpillLocal(ty: []const u8) []const u8 {
    return payload_wat.tuplePackSpillLocal(ty);
}

fn appendStoreTupleScalarLeavesFromStack(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    base_local: []const u8,
    indent: []const u8,
) CodegenError!void {
    // Legacy path without struct table (scalar/managed only).
    try payload_wat.appendStoreTupleScalarLeavesFromStack(allocator, out, tuple_ty, base_local, indent);
}

fn appendStoreTupleScalarLeavesFromStackCtx(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    base_local: []const u8,
    indent: []const u8,
    ctx: CodegenContext,
) CodegenError!void {
    var leaf_types = std.ArrayList([]const u8).empty;
    defer leaf_types.deinit(allocator);
    try appendTupleLeafTypesWithStructs(allocator, tuple_ty, ctx.structs, &leaf_types);
    if (leaf_types.items.len == 0) return error.UnsupportedLowering;

    var offsets = try allocator.alloc(usize, leaf_types.items.len);
    defer allocator.free(offsets);
    var offset: usize = 0;
    for (leaf_types.items, 0..) |leaf_ty, i| {
        const leaf_bytes = leafPayloadBytesForPack(leaf_ty, ctx.structs) orelse return error.UnsupportedTupleStorageLeaf;
        offsets[i] = offset;
        offset += leaf_bytes;
    }

    var i = leaf_types.items.len;
    while (i > 0) {
        i -= 1;
        const leaf_ty = leaf_types.items[i];
        // Managed-struct handles use the i32 spill path (same as text / [T]).
        const spill = tuplePackSpillLocal(if (isPackManagedHandleLeaf(leaf_ty, ctx.structs)) "i32" else leaf_ty);
        try appendFmt(allocator, out, "{s}local.set ${s}\n", .{ indent, spill });
        try appendFmt(allocator, out, "{s}local.get ${s}\n", .{ indent, base_local });
        if (offsets[i] != 0) {
            try appendFmt(allocator, out, "{s}i32.const {d}\n", .{ indent, offsets[i] });
            try appendFmt(allocator, out, "{s}i32.add\n", .{indent});
        }
        try appendFmt(allocator, out, "{s}local.get ${s}\n", .{ indent, spill });
        // Handles and scalars both store as i32/i64/f* payload widths.
        const store_ty = if (isPackManagedHandleLeaf(leaf_ty, ctx.structs)) "i32" else leaf_ty;
        try payload_wat.appendStoreForPayloadTypeWithIndent(allocator, out, store_ty, indent);
    }
}

/// Store packed leaves; if any managed leaf, inc first so storage shares ownership with stack values.
fn appendStoreTupleLeavesOwningFromStack(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    base_local: []const u8,
    indent: []const u8,
) CodegenError!void {
    try payload_wat.appendIncManagedTupleLeavesOnStack(allocator, out, tuple_ty, indent);
    try payload_wat.appendStoreTupleScalarLeavesFromStack(allocator, out, tuple_ty, base_local, indent);
}

fn appendStoreTupleLeavesOwningFromStackCtx(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    base_local: []const u8,
    indent: []const u8,
    ctx: CodegenContext,
) CodegenError!void {
    try appendIncManagedTupleLeavesOnStackCtx(allocator, out, tuple_ty, indent, ctx);
    try appendStoreTupleScalarLeavesFromStackCtx(allocator, out, tuple_ty, base_local, indent, ctx);
}

fn appendIncManagedTupleLeavesOnStackCtx(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    indent: []const u8,
    ctx: CodegenContext,
) CodegenError!void {
    var leaf_types = std.ArrayList([]const u8).empty;
    defer leaf_types.deinit(allocator);
    try appendTupleLeafTypesWithStructs(allocator, tuple_ty, ctx.structs, &leaf_types);
    var has_managed = false;
    for (leaf_types.items) |leaf_ty| {
        if (isPackManagedHandleLeaf(leaf_ty, ctx.structs)) {
            has_managed = true;
            break;
        }
    }
    if (!has_managed) return;

    var spills = try allocator.alloc([]const u8, leaf_types.items.len);
    defer allocator.free(spills);
    var i = leaf_types.items.len;
    while (i > 0) {
        i -= 1;
        const leaf_ty = leaf_types.items[i];
        const spill_ty = if (isPackManagedHandleLeaf(leaf_ty, ctx.structs)) "i32" else leaf_ty;
        // Per-leaf spill: same wasm type (text handle + u8) must not share one temp.
        const spill = payload_wat.tuplePackSpillLocalAt(spill_ty, i);
        spills[i] = spill;
        try appendFmt(allocator, out, "{s}local.set ${s}\n", .{ indent, spill });
    }
    for (leaf_types.items, 0..) |leaf_ty, idx| {
        try appendFmt(allocator, out, "{s}local.get ${s}\n", .{ indent, spills[idx] });
        if (isPackManagedHandleLeaf(leaf_ty, ctx.structs)) {
            try appendFmt(allocator, out, "{s};; tuple-pack-managed-leaf-inc\n", .{indent});
            try appendFmt(allocator, out, "{s}call $__arc_inc\n", .{indent});
        }
    }
}

fn appendLoadTupleScalarLeavesToStack(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    base_local: []const u8,
    indent: []const u8,
) CodegenError!void {
    try payload_wat.appendLoadTupleScalarLeavesToStack(allocator, out, tuple_ty, base_local, indent);
}

fn appendLoadTupleScalarLeavesToStackCtx(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    base_local: []const u8,
    indent: []const u8,
    ctx: CodegenContext,
) CodegenError!void {
    var leaf_types = std.ArrayList([]const u8).empty;
    defer leaf_types.deinit(allocator);
    try appendTupleLeafTypesWithStructs(allocator, tuple_ty, ctx.structs, &leaf_types);
    if (leaf_types.items.len == 0) return error.UnsupportedLowering;

    var offset: usize = 0;
    for (leaf_types.items) |leaf_ty| {
        const leaf_bytes = leafPayloadBytesForPack(leaf_ty, ctx.structs) orelse return error.UnsupportedTupleStorageLeaf;
        try appendFmt(allocator, out, "{s}local.get ${s}\n", .{ indent, base_local });
        if (offset != 0) {
            try appendFmt(allocator, out, "{s}i32.const {d}\n", .{ indent, offset });
            try appendFmt(allocator, out, "{s}i32.add\n", .{indent});
        }
        const load_ty = if (isPackManagedHandleLeaf(leaf_ty, ctx.structs)) "i32" else leaf_ty;
        try payload_wat.appendLoadForPayloadTypeWithIndent(allocator, out, load_ty, indent);
        offset += leaf_bytes;
    }
}

/// Load packed leaves and inc managed ones for a consumer that will own the result.
fn appendLoadTupleLeavesOwningToStack(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    base_local: []const u8,
    indent: []const u8,
) CodegenError!void {
    try payload_wat.appendLoadTupleScalarLeavesToStack(allocator, out, tuple_ty, base_local, indent);
    try payload_wat.appendIncManagedTupleLeavesOnStack(allocator, out, tuple_ty, indent);
}

fn appendLoadTupleLeavesOwningToStackCtx(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    base_local: []const u8,
    indent: []const u8,
    ctx: CodegenContext,
) CodegenError!void {
    try appendLoadTupleScalarLeavesToStackCtx(allocator, out, tuple_ty, base_local, indent, ctx);
    try appendIncManagedTupleLeavesOnStackCtx(allocator, out, tuple_ty, indent, ctx);
}

fn appendLoadTupleElementFromPackedBaseCtx(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    elem_index: usize,
    base_local: []const u8,
    indent: []const u8,
    ctx: CodegenContext,
) CodegenError!void {
    const elem_ty = tupleElementTypeAt(tuple_ty, elem_index) orelse return error.UnsupportedLowering;
    const elem_offset = tupleElementPackOffsetWithStructs(tuple_ty, elem_index, ctx.structs) orelse return error.UnsupportedLowering;
    if (isTupleTypeName(elem_ty)) {
        if (elem_offset != 0) {
            try appendFmt(allocator, out, "{s}local.get ${s}\n", .{ indent, base_local });
            try appendFmt(allocator, out, "{s}i32.const {d}\n", .{ indent, elem_offset });
            try appendFmt(allocator, out, "{s}i32.add\n", .{indent});
            try appendFmt(allocator, out, "{s}local.set ${s}\n", .{ indent, base_local });
        }
        try appendLoadTupleScalarLeavesToStackCtx(allocator, out, elem_ty, base_local, indent, ctx);
        return;
    }
    if (findStructDecl(ctx.structs, elem_ty)) |decl| {
        if (structDeclHasManagedField(decl, ctx.structs)) {
            // Managed struct slot: load one i32 ARC handle (object stays nested type Cell).
            try appendFmt(allocator, out, "{s}local.get ${s}\n", .{ indent, base_local });
            if (elem_offset != 0) {
                try appendFmt(allocator, out, "{s}i32.const {d}\n", .{ indent, elem_offset });
                try appendFmt(allocator, out, "{s}i32.add\n", .{indent});
            }
            try payload_wat.appendLoadForPayloadTypeWithIndent(allocator, out, "i32", indent);
            return;
        }
        if (pureScalarStructPackWidth(decl, ctx.structs) == null) return error.UnsupportedTupleStorageLeaf;
        // Nested pure-scalar struct subregion: load field leaves onto stack (declaration order).
        if (elem_offset != 0) {
            try appendFmt(allocator, out, "{s}local.get ${s}\n", .{ indent, base_local });
            try appendFmt(allocator, out, "{s}i32.const {d}\n", .{ indent, elem_offset });
            try appendFmt(allocator, out, "{s}i32.add\n", .{indent});
            try appendFmt(allocator, out, "{s}local.set ${s}\n", .{ indent, base_local });
        }
        try appendLoadTupleLeafTypesOfStructToStack(allocator, out, decl, base_local, indent, ctx);
        return;
    }
    if (!type_util.isTuplePackableLeafType(elem_ty)) return error.UnsupportedTupleStorageLeaf;
    try appendFmt(allocator, out, "{s}local.get ${s}\n", .{ indent, base_local });
    if (elem_offset != 0) {
        try appendFmt(allocator, out, "{s}i32.const {d}\n", .{ indent, elem_offset });
        try appendFmt(allocator, out, "{s}i32.add\n", .{indent});
    }
    try payload_wat.appendLoadForPayloadTypeWithIndent(allocator, out, elem_ty, indent);
}

fn appendLoadTupleLeafTypesOfStructToStack(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    decl: StructDecl,
    base_local: []const u8,
    indent: []const u8,
    ctx: CodegenContext,
) CodegenError!void {
    var offset: usize = 0;
    for (decl.fields) |field| {
        const field_ty = field.ty;
        offset = alignUp(offset, typePayloadAlignment(field_ty));
        if (isTupleTypeName(field_ty)) {
            // Nested tuple field inside pure-scalar struct: load from sub-base.
            const sub_base = TUPLE_PACK_BASE_TMP_LOCAL;
            if (offset != 0) {
                try appendFmt(allocator, out, "{s}local.get ${s}\n", .{ indent, base_local });
                try appendFmt(allocator, out, "{s}i32.const {d}\n", .{ indent, offset });
                try appendFmt(allocator, out, "{s}i32.add\n", .{indent});
                try appendFmt(allocator, out, "{s}local.set ${s}\n", .{ indent, sub_base });
                try appendLoadTupleScalarLeavesToStackCtx(allocator, out, field_ty, sub_base, indent, ctx);
            } else {
                try appendLoadTupleScalarLeavesToStackCtx(allocator, out, field_ty, base_local, indent, ctx);
            }
            offset += packSlotWidth(field_ty, ctx.structs) orelse return error.UnsupportedLowering;
            continue;
        }
        if (findStructDecl(ctx.structs, field_ty)) |nested| {
            if (pureScalarStructPackWidth(nested, ctx.structs) == null) return error.UnsupportedTupleStorageLeaf;
            const sub_base = TUPLE_PACK_BASE_TMP_LOCAL;
            if (offset != 0) {
                try appendFmt(allocator, out, "{s}local.get ${s}\n", .{ indent, base_local });
                try appendFmt(allocator, out, "{s}i32.const {d}\n", .{ indent, offset });
                try appendFmt(allocator, out, "{s}i32.add\n", .{indent});
                try appendFmt(allocator, out, "{s}local.set ${s}\n", .{ indent, sub_base });
                try appendLoadTupleLeafTypesOfStructToStack(allocator, out, nested, sub_base, indent, ctx);
            } else {
                try appendLoadTupleLeafTypesOfStructToStack(allocator, out, nested, base_local, indent, ctx);
            }
            offset += pureScalarStructPackWidth(nested, ctx.structs).?;
            continue;
        }
        try appendFmt(allocator, out, "{s}local.get ${s}\n", .{ indent, base_local });
        if (offset != 0) {
            try appendFmt(allocator, out, "{s}i32.const {d}\n", .{ indent, offset });
            try appendFmt(allocator, out, "{s}i32.add\n", .{indent});
        }
        try payload_wat.appendLoadForPayloadTypeWithIndent(allocator, out, field_ty, indent);
        offset += typePayloadBytes(field_ty);
    }
}

fn appendLoadTupleElementOwningFromPackedBase(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    elem_index: usize,
    base_local: []const u8,
    indent: []const u8,
    ctx: CodegenContext,
) CodegenError!void {
    const elem_ty = tupleElementTypeAt(tuple_ty, elem_index) orelse return error.UnsupportedLowering;
    try appendLoadTupleElementFromPackedBaseCtx(allocator, out, tuple_ty, elem_index, base_local, indent, ctx);
    if (isTupleTypeName(elem_ty)) {
        try appendIncManagedTupleLeavesOnStackCtx(allocator, out, elem_ty, indent, ctx);
    } else if (isPackManagedHandleLeaf(elem_ty, ctx.structs)) {
        try out.appendSlice(allocator, indent);
        try out.appendSlice(allocator, ";; tuple-pack-element-managed-inc\n");
        try out.appendSlice(allocator, indent);
        try out.appendSlice(allocator, "call $__arc_inc\n");
    }
    // pure-scalar struct slot: no managed leaves to inc
}

fn emitIncManagedTupleLeavesAtBase(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    base_local: []const u8,
    indent: []const u8,
    ctx: CodegenContext,
) CodegenError!void {
    if (!tupleHasManagedPackLeafCtx(tuple_ty, ctx)) return;
    var leaf_types = std.ArrayList([]const u8).empty;
    defer leaf_types.deinit(allocator);
    try appendTupleLeafTypesWithStructs(allocator, tuple_ty, ctx.structs, &leaf_types);
    var offset: usize = 0;
    for (leaf_types.items) |leaf_ty| {
        const leaf_bytes = leafPayloadBytesForPack(leaf_ty, ctx.structs) orelse return error.UnsupportedTupleStorageLeaf;
        if (isPackManagedHandleLeaf(leaf_ty, ctx.structs)) {
            try appendFmt(allocator, out, "{s}local.get ${s}\n", .{ indent, base_local });
            if (offset != 0) {
                try appendFmt(allocator, out, "{s}i32.const {d}\n", .{ indent, offset });
                try appendFmt(allocator, out, "{s}i32.add\n", .{indent});
            }
            try appendFmt(allocator, out, "{s}i32.load\n", .{indent});
            try appendFmt(allocator, out, "{s};; tuple-pack-leaf-inc-at-base\n", .{indent});
            try appendFmt(allocator, out, "{s}call $__arc_inc\n", .{indent});
            try appendFmt(allocator, out, "{s}drop\n", .{indent});
        }
        offset += leaf_bytes;
    }
}

fn emitDecManagedTupleLeavesAtBase(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    base_local: []const u8,
    indent: []const u8,
    ctx: CodegenContext,
) CodegenError!void {
    if (!tupleHasManagedPackLeafCtx(tuple_ty, ctx)) return;
    var leaf_types = std.ArrayList([]const u8).empty;
    defer leaf_types.deinit(allocator);
    try appendTupleLeafTypesWithStructs(allocator, tuple_ty, ctx.structs, &leaf_types);
    var offset: usize = 0;
    for (leaf_types.items) |leaf_ty| {
        const leaf_bytes = leafPayloadBytesForPack(leaf_ty, ctx.structs) orelse return error.UnsupportedTupleStorageLeaf;
        if (isPackManagedHandleLeaf(leaf_ty, ctx.structs)) {
            try appendFmt(allocator, out, "{s}local.get ${s}\n", .{ indent, base_local });
            if (offset != 0) {
                try appendFmt(allocator, out, "{s}i32.const {d}\n", .{ indent, offset });
                try appendFmt(allocator, out, "{s}i32.add\n", .{indent});
            }
            try appendFmt(allocator, out, "{s}i32.load\n", .{indent});
            try appendFmt(allocator, out, "{s};; tuple-pack-leaf-dec-at-base\n", .{indent});
            try appendFmt(allocator, out, "{s}call $__arc_dec\n", .{indent});
        }
        offset += leaf_bytes;
    }
}

fn appendStorePayloadOrTupleFromStack(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    elem_ty: []const u8,
    base_local: []const u8,
    indent: []const u8,
) CodegenError!void {
    try payload_wat.appendStorePayloadOrTupleFromStack(allocator, out, elem_ty, base_local, indent);
}

fn appendLoadPayloadOrTupleToStack(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    elem_ty: []const u8,
    base_local: []const u8,
    indent: []const u8,
) CodegenError!void {
    try payload_wat.appendLoadPayloadOrTupleToStack(allocator, out, elem_ty, base_local, indent);
}

fn storageTypeIdForElement(elem_ty: []const u8, ctx: CodegenContext) usize {
    if (isTupleTypeName(elem_ty) and tupleHasManagedPackLeafCtx(elem_ty, ctx)) {
        if (findStructLayoutExact(ctx.struct_layouts, elem_ty)) |layout| {
            if (layout.is_storage_pack) return layout.type_id;
        }
    }
    if (isManagedLocalType(elem_ty, ctx) and storageElementByteWidth(elem_ty) == null and tupleScalarLeafStorageByteWidthCtx(elem_ty, ctx) == null)
        return TYPE_ID_STORAGE_MANAGED;
    return TYPE_ID_STORAGE_U8;
}

fn storagePackLayoutForElem(elem_ty: []const u8, ctx: CodegenContext) ?StructLayout {
    if (!isTupleTypeName(elem_ty) or !tupleHasManagedPackLeafCtx(elem_ty, ctx)) return null;
    const layout = findStructLayoutExact(ctx.struct_layouts, elem_ty) orelse return null;
    if (!layout.is_storage_pack) return null;
    return layout;
}

fn isCoreWasmScalar(ty: []const u8) bool {
    return type_util.isCoreWasmScalar(ty);
}

fn isCoreIntegerScalar(ty: []const u8) bool {
    return type_util.isCoreIntegerScalar(ty);
}

fn isCoreFloatScalar(ty: []const u8) bool {
    return type_util.isCoreFloatScalar(ty);
}

fn emitNumberConst(
    allocator: std.mem.Allocator,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
    lexeme: []const u8,
    ty: []const u8,
) !void {
    try appendFmt(allocator, out, "    {s}.const {s}\n", .{ codegenWasmType(ctx, ty), lexeme });
}

fn appendStoreForPayloadType(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    ty: []const u8,
) !void {
    try payload_wat.appendStoreForPayloadType(allocator, out, ty);
}

fn appendStoreForPayloadTypeWithIndent(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    ty: []const u8,
    indent: []const u8,
) !void {
    try payload_wat.appendStoreForPayloadTypeWithIndent(allocator, out, ty, indent);
}

fn appendLoadForPayloadType(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    ty: []const u8,
) !void {
    try payload_wat.appendLoadForPayloadType(allocator, out, ty);
}

fn appendLoadForPayloadTypeWithIndent(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    ty: []const u8,
    indent: []const u8,
) !void {
    try payload_wat.appendLoadForPayloadTypeWithIndent(allocator, out, ty, indent);
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

fn inferScalarAsCallType(tokens: []const lexer.Token, args_start: usize, args_end: usize) ?[]const u8 {
    const target_end = findArgEnd(tokens, args_start, args_end);
    if (target_end == args_start or target_end >= args_end or !tokEq(tokens[target_end], ",")) return null;
    return scalarAsTargetType(tokens, args_start, target_end);
}

fn scalarAsTargetType(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    if (start_idx + 1 != end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (!isScalarAsTargetTypeName(tokens[start_idx].lexeme)) return null;
    return tokens[start_idx].lexeme;
}

fn isScalarAsTargetTypeName(name: []const u8) bool {
    const names = [_][]const u8{
        "u8",
        "u16",
        "u32",
        "u64",
        "usize",
        "isize",
        "i8",
        "i16",
        "i32",
        "i64",
        "f32",
        "f64",
    };
    for (names) |it| {
        if (std.mem.eql(u8, it, name)) return true;
    }
    return false;
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
        if (tok.kind == .ident) {
            if (findNarrowedUnionType(locals.narrowed_union_locals.items, tok.lexeme)) |ty| return substituteGenericType(ty, ctx.type_bindings);
            if (findLocalType(locals.locals.items, tok.lexeme)) |ty| return ty;
            if (findStructLocal(locals.struct_locals.items, tok.lexeme)) |struct_local| return struct_local.ty;
            if (findUnionLocal(locals.union_locals.items, tok.lexeme)) |union_local| {
                return substituteGenericType(union_local.layout.source_ty, ctx.type_bindings);
            }
            if (findCallbackCallArg(ctx.callback_call_args, tok.lexeme)) |callback_arg| return callback_arg.ty;
            return if (localScalarConst(tokens, tok.lexeme)) |local_const| local_const.ty else if (importedScalarConst(ctx, tokens, tok.lexeme)) |imported_const| imported_const.ty else null;
        }
        return null;
    }

    const call_head = exprCallHead(tokens, range) orelse return null;
    const call_name = tokens[call_head.name_idx].lexeme;
    if (call_head.is_intrinsic) {
        if (shouldInferBoolSpecialCall(call_name, tokens, call_head.args_start, call_head.args_end, locals, ctx)) return "bool";
        if (std.mem.eql(u8, call_name, "is")) return "bool";
        if (std.mem.eql(u8, call_name, "as")) return inferScalarAsCallType(tokens, call_head.args_start, call_head.args_end);
        if (isComparisonCoreFuncName(call_name)) return "bool";
        if (std.mem.eql(u8, call_name, "len")) return "usize";
        if (std.mem.eql(u8, call_name, "set")) return inferSetCallType(tokens, call_head.args_start, call_head.args_end, locals);
        if (std.mem.eql(u8, call_name, "put")) return inferPutCallType(tokens, call_head.args_start, call_head.args_end, locals);
        if (std.mem.eql(u8, call_name, "field_name")) return "text";
        if (std.mem.eql(u8, call_name, "field_index")) return "usize";
        if (std.mem.eql(u8, call_name, "field_has_default")) return "bool";
        if (std.mem.eql(u8, call_name, "field_get")) {
            return inferFieldGetCallType(tokens, call_head.args_start, call_head.args_end, locals, ctx);
        }
        if (std.mem.eql(u8, call_name, "field_set")) {
            return inferFieldSetCallType(tokens, call_head.args_start, call_head.args_end, locals);
        }
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

    if (findCallbackBinding(ctx.callback_bindings, call_name)) |binding| return binding.shape.return_type;
    if (findFuncDeclForCallHead(tokens, call_head, locals, ctx)) |func| return func.result;
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
    if (lowering.result_list_preopen) return "[Tuple<i32,text>]";
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
    if (first_end >= end_idx or !tokEq(tokens[first_end], ",")) return null;

    const second_start = first_end + 1;
    const second_end = findArgEnd(tokens, second_start, end_idx);
    if (inferTupleFieldPathGetType(tokens, start_idx, end_idx, first_end, locals, ctx)) |tuple_ty| return tuple_ty;
    if (second_end != end_idx) {
        return inferPathGetCallType(tokens, start_idx, end_idx, first_end, locals, ctx);
    }

    if (second_end == second_start + 1 and isDotIdent(tokens[second_start].lexeme)) {
        if (inferManagedStructExprFieldType(tokens, start_idx, first_end, tokens[second_start].lexeme, locals, ctx)) |field_ty| {
            return field_ty;
        }
    }

    if (first_end != start_idx + 1 or tokens[start_idx].kind != .ident) {
        const storage_ty = inferExprType(tokens, start_idx, first_end, locals, ctx) orelse return null;
        if (storageElemTypeFromName(storage_ty)) |elem_ty| return elem_ty;
        return null;
    }

    const name = tokens[start_idx].lexeme;
    if (findStoragePrimitiveLocal(locals.storage_locals.items, name)) |storage| return storage.elem_ty;

    if (findStructLocal(locals.struct_locals.items, name)) |struct_local| {
        if (isTupleTypeName(struct_local.ty)) {
            const elem_info = tupleGetElementInfo(tokens, second_start, second_end, struct_local.ty) orelse return null;
            return elem_info.ty;
        }
    }

    if (second_end != second_start + 1 or !isDotIdent(tokens[second_start].lexeme)) return null;

    const field_name = publicDeclName(tokens[second_start].lexeme);
    if (findStructLocal(locals.struct_locals.items, name)) |struct_local| {
        if (findLocalFieldType(locals.locals.items, struct_local.name, field_name)) |field_ty| return field_ty;
        const decl = findStructDecl(ctx.structs, struct_local.ty) orelse return null;
        return findStructFieldType(decl, field_name);
    }
    if (findUnionLocal(locals.union_locals.items, name)) |union_local| {
        const payload = unionLocalDefaultStructPayload(tokens, ctx, union_local) orelse return null;
        return findStructFieldType(payload.decl, field_name);
    }
    return null;
}

fn inferPathGetCallType(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    first_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    var current_ty = inferExprType(tokens, start_idx, first_end, locals, ctx) orelse return null;
    var segment_start = first_end + 1;
    while (segment_start < end_idx) {
        const segment_end = findArgEnd(tokens, segment_start, end_idx);
        if (segment_end == segment_start) return null;
        const has_more = segment_end < end_idx;
        if (has_more and !tokEq(tokens[segment_end], ",")) return null;

        if (segment_end == segment_start + 1 and isDotIdent(tokens[segment_start].lexeme)) {
            const decl = findStructDecl(ctx.structs, current_ty) orelse return null;
            const field_ty = findConcreteStructFieldTypeNoAlloc(decl, current_ty, publicDeclName(tokens[segment_start].lexeme)) orelse return null;
            current_ty = substituteGenericType(field_ty, ctx.type_bindings);
        } else if (isTupleTypeName(current_ty)) {
            const elem_info = tupleGetElementInfo(tokens, segment_start, segment_end, current_ty) orelse return null;
            current_ty = elem_info.ty;
        } else {
            current_ty = storageElemTypeFromName(current_ty) orelse return null;
        }

        if (!has_more) return current_ty;
        segment_start = segment_end + 1;
    }
    return null;
}

fn inferManagedStructExprFieldType(
    tokens: []const lexer.Token,
    value_start: usize,
    value_end: usize,
    dot_field: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    if (value_end == value_start + 1 and tokens[value_start].kind == .ident) return null;
    const struct_ty = inferExprType(tokens, value_start, value_end, locals, ctx) orelse return null;
    if (findStructLayout(ctx.struct_layouts, struct_ty) == null) return null;
    const decl = findStructDecl(ctx.structs, struct_ty) orelse return null;
    return findConcreteStructFieldTypeNoAlloc(decl, struct_ty, publicDeclName(dot_field));
}

fn findConcreteStructFieldTypeNoAlloc(decl: StructDecl, concrete_ty: []const u8, field_name: []const u8) ?[]const u8 {
    const field = findStructField(decl, field_name) orelse return null;
    if (decl.type_params.len == 0) return field.ty;
    for (decl.type_params, 0..) |type_param, idx| {
        if (!std.mem.eql(u8, field.ty, type_param)) continue;
        return genericTypeArgAt(concrete_ty, idx);
    }
    return field.ty;
}

fn genericTypeArgAt(concrete_ty: []const u8, target_idx: usize) ?[]const u8 {
    return type_util.genericTypeArgAt(concrete_ty, target_idx);
}

fn appendTupleLeafTypes(
    allocator: std.mem.Allocator,
    tuple_ty: []const u8,
    out: *std.ArrayList([]const u8),
) CodegenError!void {
    // Malformed Tuple type names are a lowering invariant failure, not overload miss.
    type_util.appendTupleLeafTypes(allocator, tuple_ty, out) catch return error.UnsupportedLowering;
}

fn appendTupleParamAbi(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    base: []const u8,
    tuple_ty: []const u8,
    ctx: CodegenContext,
) CodegenError!void {
    const arity = tupleArity(tuple_ty) orelse return error.UnsupportedLowering;
    var idx: usize = 0;
    while (idx < arity) : (idx += 1) {
        const elem_ty = tupleElementTypeAt(tuple_ty, idx) orelse return error.UnsupportedLowering;
        const nested_base = try std.fmt.allocPrint(allocator, "{s}.{d}", .{ base, idx });
        defer allocator.free(nested_base);
        if (isTupleTypeName(elem_ty)) {
            try appendTupleParamAbi(allocator, out, nested_base, elem_ty, ctx);
        } else {
            try appendFmt(allocator, out, " (param ${s} {s})", .{
                nested_base,
                codegenWasmType(ctx, elem_ty),
            });
        }
    }
}

fn isTupleTypeName(ty: []const u8) bool {
    return type_util.isTupleTypeName(ty);
}

fn tupleArity(tuple_ty: []const u8) ?usize {
    return type_util.tupleArity(tuple_ty);
}

fn tupleElementTypeAt(tuple_ty: []const u8, idx: usize) ?[]const u8 {
    return type_util.tupleElementTypeAt(tuple_ty, idx);
}

const TupleElementInfo = struct {
    index: usize,
    ty: []const u8,
};

fn tupleGetElementInfo(tokens: []const lexer.Token, second_start: usize, second_end: usize, tuple_ty: []const u8) ?TupleElementInfo {
    if (second_end != second_start + 1) return null;
    if (tokens[second_start].kind != .number) return null;
    const index = std.fmt.parseInt(usize, tokens[second_start].lexeme, 10) catch return null;
    const ty = tupleElementTypeAt(tuple_ty, index) orelse return null;
    return .{ .index = index, .ty = ty };
}

fn tupleFieldPathType(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    first_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    if (first_end != start_idx + 1 or tokens[start_idx].kind != .ident or first_end >= end_idx or !tokEq(tokens[first_end], ",")) return null;
    const field_start = first_end + 1;
    const field_end = findArgEnd(tokens, field_start, end_idx);
    if (field_end != field_start + 1 or !isDotIdent(tokens[field_start].lexeme) or field_end >= end_idx or !tokEq(tokens[field_end], ",")) return null;
    const index_start = field_end + 1;
    const index_end = findArgEnd(tokens, index_start, end_idx);
    if (index_end != end_idx) return null;

    const struct_local = findStructLocal(locals.struct_locals.items, tokens[start_idx].lexeme) orelse return null;
    const decl = findStructDecl(ctx.structs, struct_local.ty) orelse return null;
    const field_ty = findLocalFieldType(locals.locals.items, struct_local.name, publicDeclName(tokens[field_start].lexeme)) orelse
        findStructFieldType(decl, publicDeclName(tokens[field_start].lexeme)) orelse return null;
    if (!isTupleTypeName(field_ty)) return null;
    return field_ty;
}

fn inferTupleFieldPathGetType(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    first_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    const field_ty = tupleFieldPathType(tokens, start_idx, end_idx, first_end, locals, ctx) orelse return null;
    const field_start = first_end + 1;
    const field_end = findArgEnd(tokens, field_start, end_idx);
    const index_start = field_end + 1;
    const index_end = findArgEnd(tokens, index_start, end_idx);
    const elem_info = tupleGetElementInfo(tokens, index_start, index_end, field_ty) orelse return null;
    return elem_info.ty;
}

fn emitTupleFieldPathGetCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    first_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const field_ty = tupleFieldPathType(tokens, start_idx, end_idx, first_end, locals, ctx) orelse return false;
    const field_start = first_end + 1;
    const field_end = findArgEnd(tokens, field_start, end_idx);
    const index_start = field_end + 1;
    const index_end = findArgEnd(tokens, index_start, end_idx);
    const elem_info = tupleGetElementInfo(tokens, index_start, index_end, field_ty) orelse return false;
    const struct_local = findStructLocal(locals.struct_locals.items, tokens[start_idx].lexeme) orelse return false;
    const field_name = publicDeclName(tokens[field_start].lexeme);
    try appendFmt(allocator, out, "    local.get ${s}.{s}.{d}\n", .{ struct_local.name, field_name, elem_info.index });
    if (isManagedLocalType(elem_info.ty, ctx)) {
        try out.appendSlice(allocator, "    call $__arc_inc\n");
    }
    return true;
}

fn inferFieldGetCallType(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
) ?[]const u8 {
    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1 or tokens[start_idx].kind != .ident) return null;
    if (first_end >= end_idx or !tokEq(tokens[first_end], ",")) return null;
    const field_start = first_end + 1;
    const field_end = findArgEnd(tokens, field_start, end_idx);
    if (field_end != end_idx) return null;
    if (field_end != field_start + 1 or tokens[field_start].kind != .ident) return null;

    const struct_local = findStructLocal(locals.struct_locals.items, tokens[start_idx].lexeme) orelse return null;
    const meta = findFieldMetaLocal(locals.field_meta_locals.items, tokens[field_start].lexeme) orelse return null;
    if (!std.mem.eql(u8, typeBaseName(struct_local.ty), meta.struct_name)) return null;
    const field = fieldFromMeta(ctx, meta) orelse return null;
    return field.ty;
}

fn inferFieldSetCallType(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
) ?[]const u8 {
    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1 or tokens[start_idx].kind != .ident) return null;
    if (first_end >= end_idx or !tokEq(tokens[first_end], ",")) return null;
    const field_start = first_end + 1;
    const field_end = findArgEnd(tokens, field_start, end_idx);
    if (field_end != field_start + 1 or tokens[field_start].kind != .ident) return null;
    if (field_end >= end_idx or !tokEq(tokens[field_end], ",")) return null;
    if (findArgEnd(tokens, field_end + 1, end_idx) != end_idx) return null;
    return (findStructLocal(locals.struct_locals.items, tokens[start_idx].lexeme) orelse return null).ty;
}

fn inferSetCallType(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
) ?[]const u8 {
    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1 or tokens[start_idx].kind != .ident) return null;
    if (first_end >= end_idx or !tokEq(tokens[first_end], ",")) return null;
    const second_start = first_end + 1;
    const second_end = findArgEnd(tokens, second_start, end_idx);
    if (second_end >= end_idx or !tokEq(tokens[second_end], ",")) return null;
    if (findArgEnd(tokens, second_end + 1, end_idx) != end_idx) return null;

    if (findStoragePrimitiveLocal(locals.storage_locals.items, tokens[start_idx].lexeme)) |storage| return storage.ty;
    if (findStructLocal(locals.struct_locals.items, tokens[start_idx].lexeme)) |struct_local| return struct_local.ty;
    return null;
}

fn inferPutCallType(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
) ?[]const u8 {
    const first_end = findArgEnd(tokens, start_idx, end_idx);
    if (first_end != start_idx + 1 or tokens[start_idx].kind != .ident) return null;
    if (first_end >= end_idx or !tokEq(tokens[first_end], ",")) return null;
    if (findStoragePrimitiveLocal(locals.storage_locals.items, tokens[start_idx].lexeme)) |storage| return storage.ty;
    return null;
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

fn findTypeArgEnd(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
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

fn tokenTextEqualsCompact(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, expected: []const u8) bool {
    var offset: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        const lexeme = tokens[i].lexeme;
        if (offset + lexeme.len > expected.len) return false;
        if (!std.mem.eql(u8, expected[offset .. offset + lexeme.len], lexeme)) return false;
        offset += lexeme.len;
    }
    return offset == expected.len;
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
    const move_source = try fieldGetLastUseMoveSource(allocator, tokens, 8, tokens.len, struct_local, "text", move_ctx, &locals, ctx) orelse unreachable;
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

    try std.testing.expectEqualStrings("[[u8]]", funcParamAbiType(param));
}

test "variadic storage param keeps storage element type" {
    const param = FuncParam{
        .name = "rest",
        .ty = "[u8]",
        .variadic = true,
    };

    try std.testing.expectEqualStrings("[u8]", funcVariadicElemType(param));
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

    try std.testing.expectEqualStrings("[[u8]]", funcParamAbiType(cloned[0]));
    try std.testing.expectEqualStrings("[u8]", funcVariadicElemType(cloned[0]));
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
    try collectStructDecls(allocator, tokens, &structs);

    var layouts = std.ArrayList(StructLayout).empty;
    defer {
        freeStructLayouts(allocator, layouts.items);
        layouts.deinit(allocator);
    }
    try collectStructLayouts(allocator, structs.items, &layouts);

    var functions = std.ArrayList(FuncDecl).empty;
    defer {
        freeFuncDecls(allocator, functions.items);
        functions.deinit(allocator);
    }
    try collectFuncDecls(allocator, tokens, structs.items, layouts.items, null, &functions);
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
    try collectBodyLocals(allocator, tokens, start_open + 1, start_close, ctx, &locals);

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
    try collectFuncDecls(allocator, tokens, &.{}, &.{}, null, &functions);

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
    const call_head = callHeadAt(tokens, call_idx, tokens.len) orelse unreachable;

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
    try std.testing.expectEqualStrings("i32", findGenericBinding(bindings.items, "A").?.ty);
    try std.testing.expectEqualStrings("i32", findGenericBinding(bindings.items, "B").?.ty);

    try collectGenericFuncInstanceForCall(allocator, tokens, call_head, &locals, ctx, template, "i32", &functions);
    try std.testing.expect(findFuncDeclForCallHead(tokens, call_head, &locals, .{
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
    try collectFuncDecls(allocator, tokens, &.{}, &.{}, null, &collected_functions);
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
        &string_data,
        &.{},
        null,
        &collected_functions,
    );
    var collected_locals = LocalSet{};
    defer collected_locals.deinit(allocator);
    try collectBodyLocals(allocator, tokens, tests[0].body_start, tests[0].body_end, .{
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
    try std.testing.expect(findFuncDeclForCallHead(tokens, call_head, &collected_locals, .{
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
    try std.testing.expect(try emitExpr(allocator, tokens, call_head.name_idx, call_head.args_end + 1, &collected_locals, .{
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
    try collectFuncDecls(allocator, tokens, &.{}, &.{}, null, &functions);

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
    try collectBodyLocals(allocator, tokens, tests[0].body_start, tests[0].body_end, ctx, &locals);
    const first_call_idx = findToken(tokens, 0, tokens.len, "apply_value") orelse unreachable;
    const call_idx = findToken(tokens, first_call_idx + 1, tokens.len, "apply_value") orelse unreachable;
    const call_head = callHeadAt(tokens, call_idx, tokens.len) orelse unreachable;
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
    try std.testing.expectEqualStrings("bool", findGenericBinding(bindings.items, "A").?.ty);
    try std.testing.expectEqualStrings("i32", findGenericBinding(bindings.items, "B").?.ty);
    try collectGenericFuncInstanceForCall(allocator, tokens, call_head, &locals, ctx, template, "i32", &functions);
    const direct_func = findFuncDeclForCallHead(tokens, call_head, &locals, .{
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
    const func = findFuncDeclForCallHead(tokens, call_head, &locals, ctx) orelse unreachable;
    try std.testing.expect(func.callback_bindings.len == 1);
    try std.testing.expect(func.callback_bindings[0].kind == .func_ref);

    var wat = std.ArrayList(u8).empty;
    defer wat.deinit(allocator);
    try std.testing.expect(try emitExpr(allocator, tokens, call_head.name_idx, call_head.args_end + 1, &locals, ctx, "i32", &wat));
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
    try collectFuncDecls(allocator, tokens, &.{}, &.{}, null, &functions);

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
    try collectBodyLocals(allocator, tokens, tests[0].body_start, tests[0].body_end, ctx, &locals);

    const def_idx = findToken(tokens, 0, tokens.len, "compose") orelse unreachable;
    const same_idx = findToken(tokens, def_idx + 1, tokens.len, "compose") orelse unreachable;
    const hetero_idx = findToken(tokens, same_idx + 1, tokens.len, "compose") orelse unreachable;
    const same_head = callHeadAt(tokens, same_idx, tokens.len) orelse unreachable;
    const hetero_head = callHeadAt(tokens, hetero_idx, tokens.len) orelse unreachable;
    try std.testing.expect(findFuncDeclForCallHead(tokens, same_head, &locals, ctx) != null);
    try std.testing.expect(findFuncDeclForCallHead(tokens, hetero_head, &locals, ctx) != null);

    var same_wat = std.ArrayList(u8).empty;
    defer same_wat.deinit(allocator);
    try std.testing.expect(try emitExpr(allocator, tokens, same_idx, same_head.args_end + 1, &locals, ctx, "i32", &same_wat));

    var hetero_wat = std.ArrayList(u8).empty;
    defer hetero_wat.deinit(allocator);
    try std.testing.expect(try emitExpr(allocator, tokens, hetero_idx, hetero_head.args_end + 1, &locals, ctx, "bool", &hetero_wat));
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
    try collectBodyLocals(allocator, tokens, open_body + 1, close_body, ctx, &locals);

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    try std.testing.expect(try emitScalarNumericStartWithBackendIr(allocator, tokens, open_body + 1, close_body, &locals, ctx, &out));
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
