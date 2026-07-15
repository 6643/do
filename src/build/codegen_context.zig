//! Mutable codegen collection state and local-name helpers.
const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const payload_wat = @import("wat_payload.zig");
const type_util = @import("type_name.zig");
const codegen_tokens = @import("codegen_tokens.zig");
const codegen_union_layout = @import("codegen_union_layout.zig");
const codegen_wasi_registry = @import("codegen_wasi_registry.zig");
const model = @import("codegen_model.zig");
const constants = @import("codegen_constants.zig");

const decodeQuotedStringToken = codegen_tokens.decode_quoted_string_token;
const freeUnionLayout = codegen_union_layout.free_union_layout;
const UnionLayout = codegen_union_layout.UnionLayout;
const unionLayoutsEqual = codegen_union_layout.union_layouts_equal;
const WasiHostImport = codegen_wasi_registry.WasiHostImport;
const Local = model.Local;
const StructLocal = model.StructLocal;
const StorageLocal = model.StorageLocal;
const UnionLocal = model.UnionLocal;
const NarrowedUnionLocal = model.NarrowedUnionLocal;
const FieldMetaLocal = model.FieldMetaLocal;
const SourceOrigin = model.SourceOrigin;
const FuncDecl = model.FuncDecl;
const StructDecl = model.StructDecl;
const ValueEnumDecl = model.ValueEnumDecl;
const PayloadEnumDecl = model.PayloadEnumDecl;
const StructLayout = model.StructLayout;
const HostImport = model.HostImport;
const ImportedAliasContext = model.ImportedAliasContext;
const GenericTypeBinding = model.GenericTypeBinding;
const CallbackBinding = model.CallbackBinding;
const CallbackCallArg = model.CallbackCallArg;
const StringData = model.StringData;
const STORAGE_OVERWRITE_TMP_LOCAL = constants.STORAGE_OVERWRITE_TMP_LOCAL;
const WASI_FAMILY_TMP_LOCAL = constants.WASI_FAMILY_TMP_LOCAL;
const STORAGE_PUT_SOURCE_TMP_LOCAL = constants.STORAGE_PUT_SOURCE_TMP_LOCAL;
const VARIADIC_PACK_TMP_LOCAL = constants.VARIADIC_PACK_TMP_LOCAL;
const STORAGE_WRITE_INDEX_TMP_LOCAL = constants.STORAGE_WRITE_INDEX_TMP_LOCAL;
const STORAGE_WRITE_LEN_TMP_LOCAL = constants.STORAGE_WRITE_LEN_TMP_LOCAL;
const STORAGE_WRITE_NEXT_TMP_LOCAL = constants.STORAGE_WRITE_NEXT_TMP_LOCAL;
const STORAGE_WRITE_SCAN_TMP_LOCAL = constants.STORAGE_WRITE_SCAN_TMP_LOCAL;
const STORAGE_WRITE_TARGET_TMP_LOCAL = constants.STORAGE_WRITE_TARGET_TMP_LOCAL;
const TUPLE_PACK_BASE_TMP_LOCAL = constants.TUPLE_PACK_BASE_TMP_LOCAL;
const TUPLE_PACK_SPILL_I32 = constants.TUPLE_PACK_SPILL_I32;
const TUPLE_PACK_SPILL_I64 = constants.TUPLE_PACK_SPILL_I64;
const TUPLE_PACK_SPILL_F32 = constants.TUPLE_PACK_SPILL_F32;
const TUPLE_PACK_SPILL_F64 = constants.TUPLE_PACK_SPILL_F64;
const STRUCT_LITERAL_TMP_LOCAL = constants.STRUCT_LITERAL_TMP_LOCAL;
const NUMERIC_SELECT_LEFT_TMP_I32 = constants.NUMERIC_SELECT_LEFT_TMP_I32;
const NUMERIC_SELECT_RIGHT_TMP_I32 = constants.NUMERIC_SELECT_RIGHT_TMP_I32;
const NUMERIC_SELECT_LEFT_TMP_I64 = constants.NUMERIC_SELECT_LEFT_TMP_I64;
const NUMERIC_SELECT_RIGHT_TMP_I64 = constants.NUMERIC_SELECT_RIGHT_TMP_I64;

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

    pub fn append_borrowed_local(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        ty: []const u8,
        emit_decl: bool,
    ) !void {
        return self.append_borrowed_local_with_origin(allocator, name, ty, emit_decl, .unknown);
    }

    pub fn append_borrowed_local_with_origin(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        ty: []const u8,
        emit_decl: bool,
        origin: SourceOrigin,
    ) !void {
        const resolved = try self.scoped_local_name(allocator, name, emit_decl);
        if (find_local_type(self.locals.items, resolved.name)) |existing_ty| {
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

    pub fn append_owned_local(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        ty: []const u8,
    ) !void {
        return self.append_owned_local_with_origin(allocator, name, ty, .fresh_local);
    }

    pub fn append_owned_local_with_origin(
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

    pub fn append_storage_local(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        elem_ty: []const u8,
        emit_decl: bool,
    ) !void {
        const ty = storage_type_name_for_elem(elem_ty) orelse blk: {
            const owned_ty = try std.fmt.allocPrint(allocator, "[{s}]", .{elem_ty});
            errdefer allocator.free(owned_ty);
            try self.owned_names.append(allocator, owned_ty);
            break :blk owned_ty;
        };
        try self.append_storage_local_with_type(allocator, name, ty, elem_ty, emit_decl);
    }

    pub fn append_storage_local_with_type(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        ty: []const u8,
        elem_ty: []const u8,
        emit_decl: bool,
    ) !void {
        return self.append_storage_local_with_type_and_origin(allocator, name, ty, elem_ty, emit_decl, .unknown);
    }

    pub fn append_storage_local_with_type_and_origin(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        ty: []const u8,
        elem_ty: []const u8,
        emit_decl: bool,
        origin: SourceOrigin,
    ) !void {
        const resolved = try self.scoped_local_name(allocator, name, emit_decl);
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

    pub fn append_union_local(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        layout: UnionLayout,
        emit_decl: bool,
        owns_layout: bool,
    ) !void {
        return self.append_union_local_with_origin(allocator, name, layout, emit_decl, owns_layout, .unknown);
    }

    pub fn append_union_local_with_origin(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        layout: UnionLayout,
        emit_decl: bool,
        owns_layout: bool,
        origin: SourceOrigin,
    ) !void {
        return self.append_union_local_with_origin_and_release(allocator, name, layout, emit_decl, owns_layout, origin, true);
    }

    pub fn append_union_temp_local(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        layout: UnionLayout,
        owns_layout: bool,
    ) !void {
        return self.append_union_local_with_origin_and_release(allocator, name, layout, true, owns_layout, .compiler_temp, false);
    }

    pub fn append_union_local_with_origin_and_release(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        layout: UnionLayout,
        emit_decl: bool,
        owns_layout: bool,
        origin: SourceOrigin,
        release_on_scope_exit: bool,
    ) !void {
        if (find_union_local_exact(self.union_locals.items, name)) |existing| {
            if (!unionLayoutsEqual(existing.layout, layout)) return error.NoMatchingCall;
            if (owns_layout) freeUnionLayout(allocator, layout);
            return;
        }
        const resolved = try self.scoped_local_name(allocator, name, emit_decl);
        try self.union_locals.append(allocator, .{
            .name = resolved.name,
            .source_name = resolved.source_name,
            .layout = layout,
            .owns_layout = owns_layout,
            .origin = origin,
        });
        for (layout.payload_tys, 0..) |payload_ty, idx| {
            const payload_name = try union_payload_local_name(allocator, resolved.name, idx);
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

        const tag_name = try union_tag_local_name(allocator, resolved.name);
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

    pub fn append_struct_local(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        ty: []const u8,
        emit_decl: bool,
    ) ![]const u8 {
        return self.append_struct_local_with_origin(allocator, name, ty, emit_decl, .unknown);
    }

    pub fn append_struct_local_with_origin(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        ty: []const u8,
        emit_decl: bool,
        origin: SourceOrigin,
    ) ![]const u8 {
        const resolved = try self.scoped_local_name(allocator, name, emit_decl);
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

    pub fn scoped_local_name(
        self: *LocalSet,
        allocator: std.mem.Allocator,
        name: []const u8,
        emit_decl: bool,
    ) !ScopedLocalName {
        const prefix = self.local_name_prefix orelse return .{ .name = name, .source_name = null };
        if (!emit_decl or is_compiler_local_name(name)) return .{ .name = name, .source_name = null };
        const owned = try std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, name });
        errdefer allocator.free(owned);
        try self.owned_names.append(allocator, owned);
        return .{ .name = owned, .source_name = name };
    }

    pub fn ensure_storage_write_temps(self: *LocalSet, allocator: std.mem.Allocator) !void {
        if (!has_local(self.locals.items, STORAGE_OVERWRITE_TMP_LOCAL)) {
            try self.append_borrowed_local(allocator, STORAGE_OVERWRITE_TMP_LOCAL, "usize", true);
        }
        if (!has_local(self.locals.items, STORAGE_PUT_SOURCE_TMP_LOCAL)) {
            try self.append_borrowed_local(allocator, STORAGE_PUT_SOURCE_TMP_LOCAL, "usize", true);
        }
        if (!has_local(self.locals.items, STORAGE_WRITE_INDEX_TMP_LOCAL)) {
            try self.append_borrowed_local(allocator, STORAGE_WRITE_INDEX_TMP_LOCAL, "usize", true);
        }
        if (!has_local(self.locals.items, STORAGE_WRITE_LEN_TMP_LOCAL)) {
            try self.append_borrowed_local(allocator, STORAGE_WRITE_LEN_TMP_LOCAL, "usize", true);
        }
        if (!has_local(self.locals.items, STORAGE_WRITE_NEXT_TMP_LOCAL)) {
            try self.append_borrowed_local(allocator, STORAGE_WRITE_NEXT_TMP_LOCAL, "usize", true);
        }
        if (!has_local(self.locals.items, STORAGE_WRITE_SCAN_TMP_LOCAL)) {
            try self.append_borrowed_local(allocator, STORAGE_WRITE_SCAN_TMP_LOCAL, "usize", true);
        }
        if (!has_local(self.locals.items, STORAGE_WRITE_TARGET_TMP_LOCAL)) {
            try self.append_borrowed_local(allocator, STORAGE_WRITE_TARGET_TMP_LOCAL, "usize", true);
        }
    }

    pub fn ensure_wasi_family_tmp(self: *LocalSet, allocator: std.mem.Allocator) !void {
        if (!has_local(self.locals.items, WASI_FAMILY_TMP_LOCAL)) {
            try self.append_borrowed_local(allocator, WASI_FAMILY_TMP_LOCAL, "usize", true);
        }
    }

    pub fn ensure_tuple_pack_temps(self: *LocalSet, allocator: std.mem.Allocator) !void {
        if (!has_local(self.locals.items, TUPLE_PACK_BASE_TMP_LOCAL)) {
            try self.append_borrowed_local(allocator, TUPLE_PACK_BASE_TMP_LOCAL, "usize", true);
        }
        if (!has_local(self.locals.items, TUPLE_PACK_SPILL_I32)) {
            try self.append_borrowed_local(allocator, TUPLE_PACK_SPILL_I32, "i32", true);
        }
        // Extra i32 spills for multi-leaf pack pop/push (e.g. text+u8, Cell+u8).
        if (!has_local(self.locals.items, payload_wat.TUPLE_PACK_SPILL_I32_1)) {
            try self.append_borrowed_local(allocator, payload_wat.TUPLE_PACK_SPILL_I32_1, "i32", true);
        }
        if (!has_local(self.locals.items, payload_wat.TUPLE_PACK_SPILL_I32_2)) {
            try self.append_borrowed_local(allocator, payload_wat.TUPLE_PACK_SPILL_I32_2, "i32", true);
        }
        if (!has_local(self.locals.items, payload_wat.TUPLE_PACK_SPILL_I32_3)) {
            try self.append_borrowed_local(allocator, payload_wat.TUPLE_PACK_SPILL_I32_3, "i32", true);
        }
        if (!has_local(self.locals.items, TUPLE_PACK_SPILL_I64)) {
            try self.append_borrowed_local(allocator, TUPLE_PACK_SPILL_I64, "i64", true);
        }
        if (!has_local(self.locals.items, TUPLE_PACK_SPILL_F32)) {
            try self.append_borrowed_local(allocator, TUPLE_PACK_SPILL_F32, "f32", true);
        }
        if (!has_local(self.locals.items, TUPLE_PACK_SPILL_F64)) {
            try self.append_borrowed_local(allocator, TUPLE_PACK_SPILL_F64, "f64", true);
        }
    }

    pub fn ensure_variadic_pack_tmp(self: *LocalSet, allocator: std.mem.Allocator) !void {
        if (!has_local(self.locals.items, VARIADIC_PACK_TMP_LOCAL)) {
            try self.append_borrowed_local(allocator, VARIADIC_PACK_TMP_LOCAL, "usize", true);
        }
    }

    pub fn ensure_struct_literal_tmp(self: *LocalSet, allocator: std.mem.Allocator) !void {
        if (!has_local(self.locals.items, STRUCT_LITERAL_TMP_LOCAL)) {
            try self.append_borrowed_local(allocator, STRUCT_LITERAL_TMP_LOCAL, "usize", true);
        }
    }

    pub fn ensure_numeric_select_temps(self: *LocalSet, allocator: std.mem.Allocator) !void {
        if (!has_local(self.locals.items, NUMERIC_SELECT_LEFT_TMP_I32)) {
            try self.append_borrowed_local(allocator, NUMERIC_SELECT_LEFT_TMP_I32, "i32", true);
        }
        if (!has_local(self.locals.items, NUMERIC_SELECT_RIGHT_TMP_I32)) {
            try self.append_borrowed_local(allocator, NUMERIC_SELECT_RIGHT_TMP_I32, "i32", true);
        }
        if (!has_local(self.locals.items, NUMERIC_SELECT_LEFT_TMP_I64)) {
            try self.append_borrowed_local(allocator, NUMERIC_SELECT_LEFT_TMP_I64, "i64", true);
        }
        if (!has_local(self.locals.items, NUMERIC_SELECT_RIGHT_TMP_I64)) {
            try self.append_borrowed_local(allocator, NUMERIC_SELECT_RIGHT_TMP_I64, "i64", true);
        }
    }

    pub fn append_narrowed_union_local(
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

    pub fn intern_raw(self: *StringDataContext, allocator: std.mem.Allocator, key: []const u8, bytes: []const u8) !StringData {
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

pub fn find_local_type(locals: []const Local, name: []const u8) ?[]const u8 {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (local_name_matches(local.name, local.source_name, name)) return local.ty;
    }
    return null;
}

pub fn find_local_origin(locals: []const Local, name: []const u8) ?SourceOrigin {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (local_name_matches(local.name, local.source_name, name)) return local.origin;
    }
    return null;
}

pub fn find_storage_local_origin(locals: []const StorageLocal, name: []const u8) ?SourceOrigin {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (local_name_matches(local.name, local.source_name, name)) return local.origin;
    }
    return null;
}

pub fn storage_type_name_for_elem(elem_ty: []const u8) ?[]const u8 {
    return type_util.storage_type_name_for_elem(elem_ty);
}

pub fn storage_type_name_for_elem_owned(
    allocator: std.mem.Allocator,
    elem_ty: []const u8,
    owned_types: *std.ArrayList([]const u8),
) ![]const u8 {
    if (storage_type_name_for_elem(elem_ty)) |ty| return ty;
    const owned = try std.fmt.allocPrint(allocator, "[{s}]", .{elem_ty});
    errdefer allocator.free(owned);
    try owned_types.append(allocator, owned);
    return owned;
}

pub fn is_compiler_local_name(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "__") or std.mem.indexOf(u8, name, ".__") != null;
}

pub fn union_payload_local_name(allocator: std.mem.Allocator, base: []const u8, idx: usize) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}.__union_payload_{d}", .{ base, idx });
}

pub fn union_tag_local_name(allocator: std.mem.Allocator, base: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}.__union_tag", .{base});
}

pub fn find_union_local_exact(locals: []const UnionLocal, name: []const u8) ?UnionLocal {
    for (locals) |local| {
        if (std.mem.eql(u8, local.name, name)) return local;
    }
    return null;
}

pub fn has_local(locals: []const Local, name: []const u8) bool {
    for (locals) |local| {
        if (std.mem.eql(u8, local.name, name)) return true;
    }
    return false;
}

pub fn append_loop_source_storage_local(
    allocator: std.mem.Allocator,
    out: *LocalSet,
    loop_id: usize,
    ty: []const u8,
    elem_ty: []const u8,
) !void {
    const name = try loop_source_local_name(allocator, loop_id);
    if (has_local(out.locals.items, name)) {
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

pub fn find_struct_local(locals: []const StructLocal, name: []const u8) ?StructLocal {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (local_name_matches(local.name, local.source_name, name)) return local;
    }
    return null;
}

pub fn find_storage_local(locals: []const StorageLocal, name: []const u8) ?StorageLocal {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (local_name_matches(local.name, local.source_name, name)) return local;
    }
    return null;
}

pub fn find_union_local(locals: []const UnionLocal, name: []const u8) ?UnionLocal {
    var i = locals.len;
    while (i > 0) {
        i -= 1;
        const local = locals[i];
        if (local_name_matches(local.name, local.source_name, name)) return local;
    }
    return null;
}

pub fn local_name_matches(name: []const u8, source_name: ?[]const u8, needle: []const u8) bool {
    if (std.mem.eql(u8, name, needle)) return true;
    if (source_name) |source| return std.mem.eql(u8, source, needle);
    return false;
}

pub fn loop_source_local_name(allocator: std.mem.Allocator, loop_id: usize) ![]u8 {
    return try std.fmt.allocPrint(allocator, "__loop_source_{d}", .{loop_id});
}
// moved from codegen_pipeline for domain share
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
