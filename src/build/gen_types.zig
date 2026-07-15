//! Shared codegen types and LocalSet (no emit).
const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const runtime_prelude_wat = @import("runtime_prelude_wat.zig");
const storage_wat = @import("gen_storage_wat.zig");
const payload_wat = @import("gen_payload_wat.zig");
const type_util = @import("type_name.zig");
const gen_util = @import("gen_util.zig");
const gen_union = @import("gen_union.zig");
const gen_wasi = @import("gen_wasi.zig");

const decodeQuotedStringToken = gen_util.decodeQuotedStringToken;
const freeUnionLayout = gen_union.freeUnionLayout;
const UnionLayout = gen_union.UnionLayout;
const UnionBranch = gen_union.UnionBranch;
const unionLayoutsEqual = gen_union.unionLayoutsEqual;
const WasiHostImport = gen_wasi.WasiHostImport;

pub const SourceOrigin = enum {
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

pub const Local = struct {
    name: []const u8,
    source_name: ?[]const u8 = null,
    ty: []const u8,
    origin: SourceOrigin = .unknown,
    emit_decl: bool = true,
    release_on_scope_exit: bool = true,
};

pub const StructField = struct {
    name: []const u8,
    ty: []const u8,
    default_start: ?usize = null,
    default_end: usize = 0,
};

pub const StructDecl = struct {
    name: []const u8,
    type_params: []const []const u8 = &.{},
    fields: []const StructField,
    layout_source: ?[]const u8,
    owned_types: []const []const u8 = &.{},
    tokens: []const lexer.Token,
};

pub const ValueEnumBranch = struct {
    name: []const u8,
    value: []const u8,
};

pub const ValueEnumDecl = struct {
    name: []const u8,
    source_name: []const u8,
    carrier: []const u8,
    branches: []const ValueEnumBranch,
    owned_name: bool = false,
};

/// L1 payload enum: `Message = Quit | Text([u8]) | Binary([u8])`.
/// Tags are by case name order (0..); payload slots use max-payload overlap.
pub const PayloadEnumCase = struct {
    name: []const u8,
    /// null = unit case (no payload).
    payload_ty: ?[]const u8,
};

pub const PayloadEnumDecl = struct {
    name: []const u8,
    cases: []const PayloadEnumCase,
    /// Owned type strings for non-ident payload type exprs (none in L1 simple forms usually).
    owned_payload_tys: []const []const u8 = &.{},
    owned_name: bool = false,
};

pub const ManagedFieldOffset = runtime_prelude_wat.ManagedFieldOffset;
pub const StructLayout = runtime_prelude_wat.StructLayout;

pub const StructLocal = struct {
    name: []const u8,
    source_name: ?[]const u8 = null,
    ty: []const u8,
    origin: SourceOrigin = .unknown,
};

pub const TypedStructBinding = struct {
    decl: StructDecl,
    ty: []const u8,
};

pub const StorageLocal = struct {
    name: []const u8,
    source_name: ?[]const u8 = null,
    ty: []const u8,
    elem_ty: []const u8,
    origin: SourceOrigin = .unknown,
};



pub const UnionLocal = struct {
    name: []const u8,
    source_name: ?[]const u8 = null,
    layout: UnionLayout,
    owns_layout: bool = false,
    origin: SourceOrigin = .unknown,
};

pub const InferredUnionBinding = struct {
    layout: UnionLayout,
    owns_layout: bool,
};

pub const NarrowedUnionLocal = struct {
    name: []const u8,
    source_name: ?[]const u8 = null,
    ty: []const u8,
};

pub const FieldMetaLocal = struct {
    name: []const u8,
    struct_name: []const u8,
    decl_index: usize,
    visible_index: usize,
};

pub const EmitOptions = struct {
    component_core: bool = false,
};

pub const TYPE_ID_STORAGE_U8: usize = storage_wat.TYPE_ID_STORAGE_U8;
pub const TYPE_ID_STORAGE_MANAGED: usize = storage_wat.TYPE_ID_STORAGE_MANAGED;
pub const TYPE_ID_FIRST_STRUCT: usize = storage_wat.TYPE_ID_FIRST_STRUCT;
pub const STORAGE_PAYLOAD_HEADER_BYTES: usize = storage_wat.STORAGE_PAYLOAD_HEADER_BYTES;
pub const STORAGE_OVERWRITE_TMP_LOCAL = storage_wat.STORAGE_OVERWRITE_TMP_LOCAL;
pub const WASI_FAMILY_TMP_LOCAL = "__wasi_family_tmp";
pub const STORAGE_PUT_SOURCE_TMP_LOCAL = "__storage_put_source_tmp";
pub const VARIADIC_PACK_TMP_LOCAL = "__variadic_pack_tmp";
pub const STORAGE_WRITE_INDEX_TMP_LOCAL = "__storage_write_index_tmp";
pub const STORAGE_WRITE_LEN_TMP_LOCAL = "__storage_write_len_tmp";
pub const STORAGE_WRITE_NEXT_TMP_LOCAL = "__storage_write_next_tmp";
pub const STORAGE_WRITE_SCAN_TMP_LOCAL = "__storage_write_scan_tmp";
pub const STORAGE_WRITE_TARGET_TMP_LOCAL = "__storage_write_target_tmp";
pub const TUPLE_PACK_BASE_TMP_LOCAL = "__tuple_pack_base_tmp";
pub const TUPLE_PACK_SPILL_I32 = payload_wat.TUPLE_PACK_SPILL_I32;
pub const TUPLE_PACK_SPILL_I64 = payload_wat.TUPLE_PACK_SPILL_I64;
pub const TUPLE_PACK_SPILL_F32 = payload_wat.TUPLE_PACK_SPILL_F32;
pub const TUPLE_PACK_SPILL_F64 = payload_wat.TUPLE_PACK_SPILL_F64;
pub const STRUCT_LITERAL_TMP_LOCAL = "__struct_literal_tmp";
pub const NUMERIC_SELECT_LEFT_TMP_I32 = "__numeric_select_left_i32";
pub const NUMERIC_SELECT_RIGHT_TMP_I32 = "__numeric_select_right_i32";
pub const NUMERIC_SELECT_LEFT_TMP_I64 = "__numeric_select_left_i64";
pub const NUMERIC_SELECT_RIGHT_TMP_I64 = "__numeric_select_right_i64";

pub const NumericSelectTemps = struct {
    left: []const u8,
    right: []const u8,
};

pub const LocalSet = struct {
    locals: std.ArrayList(Local) = .empty,
    struct_locals: std.ArrayList(StructLocal) = .empty,
    storage_locals: std.ArrayList(StorageLocal) = .empty,
    union_locals: std.ArrayList(UnionLocal) = .empty,
    narrowed_union_locals: std.ArrayList(NarrowedUnionLocal) = .empty,
    field_meta_locals: std.ArrayList(FieldMetaLocal) = .empty,
    owned_names: std.ArrayList([]const u8) = .empty,
    local_name_prefix: ?[]const u8 = null,

    pub fn deinit(self: *LocalSet, allocator: std.mem.Allocator) void {
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

    pub fn appendBorrowedLocal(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        ty: []const u8,
        emit_decl: bool,
    ) !void {
        return self.appendBorrowedLocalWithOrigin(allocator, name, ty, emit_decl, .unknown);
    }

    pub fn appendBorrowedLocalWithOrigin(
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

    pub fn appendOwnedLocal(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        ty: []const u8,
    ) !void {
        return self.appendOwnedLocalWithOrigin(allocator, name, ty, .fresh_local);
    }

    pub fn appendOwnedLocalWithOrigin(
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

    pub fn appendStorageLocal(
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

    pub fn appendStorageLocalWithType(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        ty: []const u8,
        elem_ty: []const u8,
        emit_decl: bool,
    ) !void {
        return self.appendStorageLocalWithTypeAndOrigin(allocator, name, ty, elem_ty, emit_decl, .unknown);
    }

    pub fn appendStorageLocalWithTypeAndOrigin(
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

    pub fn appendUnionLocal(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        layout: UnionLayout,
        emit_decl: bool,
        owns_layout: bool,
    ) !void {
        return self.appendUnionLocalWithOrigin(allocator, name, layout, emit_decl, owns_layout, .unknown);
    }

    pub fn appendUnionLocalWithOrigin(
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

    pub fn appendUnionTempLocal(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        layout: UnionLayout,
        owns_layout: bool,
    ) !void {
        return self.appendUnionLocalWithOriginAndRelease(allocator, name, layout, true, owns_layout, .compiler_temp, false);
    }

    pub fn appendUnionLocalWithOriginAndRelease(
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

    pub fn appendStructLocal(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        ty: []const u8,
        emit_decl: bool,
    ) ![]const u8 {
        return self.appendStructLocalWithOrigin(allocator, name, ty, emit_decl, .unknown);
    }

    pub fn appendStructLocalWithOrigin(
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

    pub fn scopedLocalName(
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

    pub fn ensureStorageWriteTemps(self: *LocalSet, allocator: std.mem.Allocator) !void {
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

    pub fn ensureWasiFamilyTmp(self: *LocalSet, allocator: std.mem.Allocator) !void {
        if (!hasLocal(self.locals.items, WASI_FAMILY_TMP_LOCAL)) {
            try self.appendBorrowedLocal(allocator, WASI_FAMILY_TMP_LOCAL, "usize", true);
        }
    }

    pub fn ensureTuplePackTemps(self: *LocalSet, allocator: std.mem.Allocator) !void {
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

    pub fn ensureVariadicPackTmp(self: *LocalSet, allocator: std.mem.Allocator) !void {
        if (!hasLocal(self.locals.items, VARIADIC_PACK_TMP_LOCAL)) {
            try self.appendBorrowedLocal(allocator, VARIADIC_PACK_TMP_LOCAL, "usize", true);
        }
    }

    pub fn ensureStructLiteralTmp(self: *LocalSet, allocator: std.mem.Allocator) !void {
        if (!hasLocal(self.locals.items, STRUCT_LITERAL_TMP_LOCAL)) {
            try self.appendBorrowedLocal(allocator, STRUCT_LITERAL_TMP_LOCAL, "usize", true);
        }
    }

    pub fn ensureNumericSelectTemps(self: *LocalSet, allocator: std.mem.Allocator) !void {
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

    pub fn appendNarrowedUnionLocal(
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

pub const EMPTY_LOCAL_SET = LocalSet{};

pub const FuncParam = struct {
    name: []const u8,
    ty: []const u8,
    abi_ty: ?[]const u8 = null,
    variadic: bool = false,
    callback: ?OwnedFuncTypeShape = null,
};

pub const GenericTypeBinding = struct {
    name: []const u8,
    ty: []const u8,
};

pub const FuncTypeShape = struct {
    param_types: []const ?[]const u8,
    return_type: ?[]const u8,
};

pub const OwnedFuncTypeShape = struct {
    shape: FuncTypeShape,
    owned: bool,
};

pub const CallbackBindingKind = enum {
    lambda,
    func_ref,
};

pub const CallbackBinding = struct {
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

pub const LambdaExprShape = struct {
    open_params: usize,
    close_params: usize,
    body_start: usize,
    body_end: usize,
    is_block: bool,
};

pub const CallbackCallArg = struct {
    source_name: []const u8,
    actual_name: ?[]const u8 = null,
    ty: []const u8,
    expr_tokens: []const lexer.Token,
    expr_start: usize,
    expr_end: usize,
};

pub const FuncDecl = struct {
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

pub const FuncResultParse = struct {
    types: []const []const u8,
    items: []const FuncResultItem = &.{},
    owns_items: bool = true,
    result_struct: ?[]const u8 = null,
    result_union: ?UnionLayout = null,
};

pub const FuncResultItem = struct {
    ty: []const u8,
    abi_start: usize,
    abi_len: usize,
    union_layout: ?UnionLayout = null,
};

pub const MultiResultLhsKind = enum {
    scalar,
    managed,
    union_value,
    unmanaged_struct,
};

pub const MultiResultLhs = struct {
    name: []const u8,
    ty: []const u8,
    item: FuncResultItem,
    kind: MultiResultLhsKind,
};

pub const NO_RESULT_ITEMS: []const FuncResultItem = &.{};

pub const ParsedCodegenType = struct {
    ty: []const u8,
    next_idx: usize,
};

pub const StructFieldAbiSlot = struct {
    name_suffix: []const u8,
    ty: []const u8,
    offset: usize,
    managed: bool,
};

pub const FuncBodyShape = struct {
    result_start: usize,
    result_end: usize,
    body_start: usize,
    body_end: usize,
    arrow: bool,
    next_idx: usize,
};

pub const StructErrorResult = struct {
    struct_name: []const u8,
    error_name: []const u8,
};

pub const ImportedAliasContext = struct {
    graph: *const imports.ModuleGraph,
    module_idx: usize,
};

pub const CodegenContext = struct {
    functions: []const FuncDecl,
    structs: []const StructDecl,
    value_enums: []const ValueEnumDecl,
    payload_enums: []const PayloadEnumDecl = &.{},
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

pub const LoopControl = struct {
    parent: ?*const LoopControl,
    source_label: ?[]const u8,
    break_label: []const u8,
    continue_label: []const u8,
    cleanup_locals: *const LocalSet,
    defer_ctx: *const DeferContext,
};

pub const SelfTailTco = struct {
    func: FuncDecl,
    loop_label: []const u8,
};

pub const CollectionLoopHeader = struct {
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

pub const RecvLoopHeader = struct {
    value_name: ?[]const u8,
    count_name: ?[]const u8,
    source_name: []const u8,
    elem_ty: []const u8,
    elem_bytes: usize,
    open_brace: usize,
    close_brace: usize,
};

pub const FieldReflectionLoopHeader = struct {
    field_name: []const u8,
    decl: StructDecl,
    loop_idx: usize,
    open_brace: usize,
    close_brace: usize,
};

pub const FieldStaticValue = union(enum) {
    bool: bool,
    int: usize,
    text: []const u8,
};

pub const FieldReflectionIfParts = struct {
    cond_start: usize,
    cond_end: usize,
    then_start: usize,
    then_end: usize,
    else_if_start: ?usize = null,
    else_start: ?usize = null,
    else_end: usize = 0,
};

pub const UnionStructPayload = struct {
    branch: UnionBranch,
    decl: StructDecl,
};

pub const NilComparisonNarrowing = struct {
    union_local: UnionLocal,
    payload_ty: []const u8,
    non_nil_when_true: bool,
};

pub const IsComparisonNarrowing = struct {
    union_local: UnionLocal,
    payload_ty: []const u8,
};

pub const DeferContext = struct {
    parent: ?*const DeferContext,
    start_idx: usize,
    end_idx: usize,
    registered_end_idx: usize,
};

pub const DeferItemKind = enum {
    call,
    block,
};

pub const DeferItem = struct {
    kind: DeferItemKind,
    start_idx: usize,
    end_idx: usize,
};

pub const CodegenError = anyerror;

pub const HostImport = struct {
    alias: []const u8,
    source_alias: []const u8,
    field: []const u8,
    params: []const []const u8,
    result: ?[]const u8,
    tokens: []const lexer.Token,
    owned_alias: bool = false,
};





pub const CodegenImportPrefix = enum {
    local,
    dep,
    std,
};

pub const CodegenImportRef = struct {
    alias: []const u8,
    target: []const u8,
    file_path: []const u8,
    prefix: CodegenImportPrefix,
};

pub const ImportedScalarConst = struct {
    ty: []const u8,
    value: []const u8,
};

pub const ReachVisit = struct {
    module_idx: usize,
    name: []const u8,
    call_idx: ?usize = null,
};

pub const StringData = runtime_prelude_wat.StringData;

pub const StringDataContext = struct {
    items: std.ArrayList(StringData) = .empty,
    next_ptr: usize = 1024,

    pub fn deinit(self: *StringDataContext, allocator: std.mem.Allocator) void {
        for (self.items.items) |item| {
            allocator.free(item.bytes);
        }
        self.items.deinit(allocator);
    }

    pub fn intern(self: *StringDataContext, allocator: std.mem.Allocator, lexeme: []const u8) !StringData {
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

    pub fn internRaw(self: *StringDataContext, allocator: std.mem.Allocator, key: []const u8, bytes: []const u8) !StringData {
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

    pub fn find(self: *const StringDataContext, lexeme: []const u8) ?StringData {
        for (self.items.items) |item| {
            if (std.mem.eql(u8, item.lexeme, lexeme)) return item;
        }
        return null;
    }
};

pub fn findLocalType(locals: []const Local, name: []const u8) ?[]const u8 {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (localNameMatches(local.name, local.source_name, name)) return local.ty;
    }
    return null;
}

pub fn findLocalOrigin(locals: []const Local, name: []const u8) ?SourceOrigin {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (localNameMatches(local.name, local.source_name, name)) return local.origin;
    }
    return null;
}

pub fn findStorageLocalOrigin(locals: []const StorageLocal, name: []const u8) ?SourceOrigin {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (localNameMatches(local.name, local.source_name, name)) return local.origin;
    }
    return null;
}

pub fn storageTypeNameForElem(elem_ty: []const u8) ?[]const u8 {
    return type_util.storageTypeNameForElem(elem_ty);
}

pub fn storageTypeNameForElemOwned(
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

pub fn isCompilerLocalName(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "__") or std.mem.indexOf(u8, name, ".__") != null;
}

pub fn unionPayloadLocalName(allocator: std.mem.Allocator, base: []const u8, idx: usize) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}.__union_payload_{d}", .{ base, idx });
}

pub fn unionTagLocalName(allocator: std.mem.Allocator, base: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}.__union_tag", .{base});
}

pub fn findUnionLocalExact(locals: []const UnionLocal, name: []const u8) ?UnionLocal {
    for (locals) |local| {
        if (std.mem.eql(u8, local.name, name)) return local;
    }
    return null;
}

pub fn hasLocal(locals: []const Local, name: []const u8) bool {
    for (locals) |local| {
        if (std.mem.eql(u8, local.name, name)) return true;
    }
    return false;
}

pub fn appendLoopSourceStorageLocal(
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

pub fn findStructLocal(locals: []const StructLocal, name: []const u8) ?StructLocal {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (localNameMatches(local.name, local.source_name, name)) return local;
    }
    return null;
}

pub fn findStorageLocal(locals: []const StorageLocal, name: []const u8) ?StorageLocal {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (localNameMatches(local.name, local.source_name, name)) return local;
    }
    return null;
}

pub fn findUnionLocal(locals: []const UnionLocal, name: []const u8) ?UnionLocal {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (localNameMatches(local.name, local.source_name, name)) return local;
    }
    return null;
}


pub fn localNameMatches(name: []const u8, source_name: ?[]const u8, needle: []const u8) bool {
    if (std.mem.eql(u8, name, needle)) return true;
    if (source_name) |source| return std.mem.eql(u8, source, needle);
    return false;
}


pub fn loopSourceLocalName(allocator: std.mem.Allocator, loop_id: usize) ![]u8 {
    return try std.fmt.allocPrint(allocator, "__loop_source_{d}", .{loop_id});
}

// Call-site head parsed from tokens (shared by lower/import).
pub const ExprCallHead = struct {
    name_idx: usize,
    type_args_start: usize = 0,
    type_args_end: usize = 0,
    args_start: usize,
    args_end: usize,
    is_intrinsic: bool,
};

// --- free helpers for owned decl/layout slices ---

pub fn freeCallbackBindings(allocator: std.mem.Allocator, bindings: []const CallbackBinding) void {
    for (bindings) |binding| {
        if (binding.lambda_params.len != 0) allocator.free(binding.lambda_params);
    }
    allocator.free(bindings);
}

pub fn freeStructDecls(allocator: std.mem.Allocator, structs: []const StructDecl) void {
    for (structs) |decl| {
        freeStructDecl(allocator, decl);
    }
}

pub fn freeStructDecl(allocator: std.mem.Allocator, decl: StructDecl) void {
    if (decl.type_params.len != 0) allocator.free(decl.type_params);
    for (decl.owned_types) |owned| {
        allocator.free(owned);
    }
    if (decl.owned_types.len != 0) allocator.free(decl.owned_types);
    allocator.free(decl.fields);
}

pub fn freeValueEnumDecls(allocator: std.mem.Allocator, value_enums: []const ValueEnumDecl) void {
    for (value_enums) |decl| {
        if (decl.owned_name) allocator.free(decl.name);
        allocator.free(decl.branches);
    }
}

pub fn freePayloadEnumDecls(allocator: std.mem.Allocator, payload_enums: []const PayloadEnumDecl) void {
    for (payload_enums) |decl| {
        if (decl.owned_name) allocator.free(decl.name);
        for (decl.owned_payload_tys) |owned| allocator.free(owned);
        if (decl.owned_payload_tys.len != 0) allocator.free(decl.owned_payload_tys);
        allocator.free(decl.cases);
    }
}

pub fn freeStructLayouts(allocator: std.mem.Allocator, layouts: []const StructLayout) void {
    for (layouts) |layout| {
        if (layout.owned_name) allocator.free(layout.name);
        allocator.free(layout.managed_fields);
    }
}

pub fn freeFuncParams(allocator: std.mem.Allocator, params: []const FuncParam) void {
    for (params) |param| {
        if (param.callback) |callback| {
            if (callback.owned) allocator.free(callback.shape.param_types);
        }
    }
    allocator.free(params);
}

pub fn freeFuncDecls(allocator: std.mem.Allocator, funcs: []const FuncDecl) void {
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

pub fn freeFuncResultItems(allocator: std.mem.Allocator, items: []const FuncResultItem, result_union: ?UnionLayout) void {
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

// moved from gen_lower for domain share
pub const CallLastUseMoveContext = struct {
    body_start: usize = 0,
    stmt_end: usize,
    body_end: usize,
    defer_ctx: ?*const DeferContext,
    allow_last_use_move: bool,
    allow_field_read_move: bool = false,
};

pub const LastUseManagedMoveSource = struct {
    source_name: []const u8,
    actual_name: []const u8,
    origin: SourceOrigin,
};

