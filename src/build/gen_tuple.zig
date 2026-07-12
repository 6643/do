//! Tuple / pure-scalar pack helpers (extracted from gen_storage).
const std = @import("std");
const lexer = @import("lexer.zig");
const type_util = @import("type_name.zig");
const payload_wat = @import("gen_payload_wat.zig");
const storage_wat = @import("gen_storage_wat.zig");
const gen_util = @import("gen_util.zig");
const gen_types = @import("gen_types.zig");
const gen_collect = @import("gen_collect.zig");
const gen_import = @import("gen_import.zig");
const gen_wasi_emit = @import("gen_wasi_emit.zig");
const gen_hooks = @import("gen_hooks.zig");

pub const TupleElementInfo = struct {
    index: usize,
    ty: []const u8,
};

const findTopLevelToken = gen_util.findTopLevelToken;
const trimParens = gen_util.trimParens;
const publicDeclName = gen_util.publicDeclName;
const appendFmt = gen_util.appendFmt;
const alignUp = gen_util.alignUp;
const LocalSet = gen_types.LocalSet;
const CodegenContext = gen_types.CodegenContext;
const CodegenError = gen_types.CodegenError;
const StructDecl = gen_types.StructDecl;
const StructLayout = gen_types.StructLayout;
const StructLocal = gen_types.StructLocal;
const FuncResultItem = gen_types.FuncResultItem;
const STORAGE_WRITE_SCAN_TMP_LOCAL = gen_types.STORAGE_WRITE_SCAN_TMP_LOCAL;
const TUPLE_PACK_BASE_TMP_LOCAL = gen_types.TUPLE_PACK_BASE_TMP_LOCAL;
const STORAGE_PAYLOAD_HEADER_BYTES = gen_types.STORAGE_PAYLOAD_HEADER_BYTES;
const findStructLocal = gen_types.findStructLocal;
const findStructDecl = gen_collect.findStructDecl;
const findStructLayout = gen_collect.findStructLayout;
const isPackManagedHandleLeaf = gen_collect.isPackManagedHandleLeaf;
const leafPayloadBytesForPack = gen_collect.leafPayloadBytesForPack;
const pureScalarStructPackWidth = gen_collect.pureScalarStructPackWidth;
const packSlotWidth = gen_collect.packSlotWidth;
const appendTupleLeafTypesWithStructs = gen_collect.appendTupleLeafTypesWithStructs;
const structDeclHasManagedField = gen_collect.structDeclHasManagedField;
const exprCallHead = gen_import.exprCallHead;
const typePayloadBytes = gen_wasi_emit.typePayloadBytes;
const typePayloadAlignment = gen_wasi_emit.typePayloadAlignment;
const isTupleTypeName = gen_wasi_emit.isTupleTypeName;
const tupleArity = gen_wasi_emit.tupleArity;
const tupleElementTypeAt = gen_wasi_emit.tupleElementTypeAt;
const tupleHasManagedPackLeafCtx = gen_wasi_emit.tupleHasManagedPackLeafCtx;
const isTuplePackableLeafType = type_util.isTuplePackableLeafType;

pub fn emitTupleReturnLocal(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_items: []const FuncResultItem,
    out: *std.ArrayList(u8)) !bool {
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





pub fn emitTupleLocalSet(
    allocator: std.mem.Allocator,
    base: []const u8,
    tuple_ty: []const u8,
    ctx: CodegenContext,
    out: *std.ArrayList(u8)) !void {
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





pub fn emitTupleLocalGet(
    allocator: std.mem.Allocator,
    base: []const u8,
    tuple_ty: []const u8,
    ctx: CodegenContext,
    out: *std.ArrayList(u8)) !void {
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







pub fn emitTupleGetBinding(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    tuple_local: StructLocal,
    out: *std.ArrayList(u8)
) CodegenError!bool {
    const eq_idx = findTopLevelToken(tokens, start_idx + 1, end_idx, "=") orelse return false;
    const rhs_range = trimParens(tokens, eq_idx + 1, end_idx);
    const call_head = exprCallHead(tokens, rhs_range) orelse return false;
    if (!call_head.is_intrinsic) return false;
    if (!std.mem.eql(u8, tokens[call_head.name_idx].lexeme, "get")) return false;
    if (!try gen_hooks.emitExpr(allocator, tokens, rhs_range.start, rhs_range.end, locals, ctx, tuple_local.ty, out)) {
        return false;
    }
    try emitTupleLocalSet(allocator, tuple_local.name, tuple_local.ty, ctx, out);
    return true;
}













pub fn emitStorageIncCopiedPackElements(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    storage_local: []const u8,
    copy_len_local: []const u8,
    layout: StructLayout) !void {
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





pub fn tuplePackSpillLocal(ty: []const u8) []const u8 {
    return payload_wat.tuplePackSpillLocal(ty);
}





pub fn appendStoreTupleScalarLeavesFromStack(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    base_local: []const u8,
    indent: []const u8) CodegenError!void {
    // Legacy path without struct table (scalar/managed only).
    try payload_wat.appendStoreTupleScalarLeavesFromStack(allocator, out, tuple_ty, base_local, indent);
}





pub fn appendStoreTupleScalarLeavesFromStackCtx(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    base_local: []const u8,
    indent: []const u8,
    ctx: CodegenContext) CodegenError!void {
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
/// Store packed leaves; if any managed leaf, inc first so storage shares ownership with stack values.




pub fn appendStoreTupleLeavesOwningFromStack(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    base_local: []const u8,
    indent: []const u8) CodegenError!void {
    try payload_wat.appendIncManagedTupleLeavesOnStack(allocator, out, tuple_ty, indent);
    try payload_wat.appendStoreTupleScalarLeavesFromStack(allocator, out, tuple_ty, base_local, indent);
}





pub fn appendStoreTupleLeavesOwningFromStackCtx(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    base_local: []const u8,
    indent: []const u8,
    ctx: CodegenContext) CodegenError!void {
    try appendIncManagedTupleLeavesOnStackCtx(allocator, out, tuple_ty, indent, ctx);
    try appendStoreTupleScalarLeavesFromStackCtx(allocator, out, tuple_ty, base_local, indent, ctx);
}





pub fn appendIncManagedTupleLeavesOnStackCtx(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    indent: []const u8,
    ctx: CodegenContext) CodegenError!void {
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





pub fn appendLoadTupleScalarLeavesToStack(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    base_local: []const u8,
    indent: []const u8) CodegenError!void {
    try payload_wat.appendLoadTupleScalarLeavesToStack(allocator, out, tuple_ty, base_local, indent);
}





pub fn appendLoadTupleScalarLeavesToStackCtx(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    base_local: []const u8,
    indent: []const u8,
    ctx: CodegenContext) CodegenError!void {
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
/// Load packed leaves and inc managed ones for a consumer that will own the result.




pub fn appendLoadTupleLeavesOwningToStack(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    base_local: []const u8,
    indent: []const u8) CodegenError!void {
    try payload_wat.appendLoadTupleScalarLeavesToStack(allocator, out, tuple_ty, base_local, indent);
    try payload_wat.appendIncManagedTupleLeavesOnStack(allocator, out, tuple_ty, indent);
}





pub fn appendLoadTupleLeavesOwningToStackCtx(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    base_local: []const u8,
    indent: []const u8,
    ctx: CodegenContext) CodegenError!void {
    try appendLoadTupleScalarLeavesToStackCtx(allocator, out, tuple_ty, base_local, indent, ctx);
    try appendIncManagedTupleLeavesOnStackCtx(allocator, out, tuple_ty, indent, ctx);
}





pub fn appendLoadTupleElementFromPackedBaseCtx(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    elem_index: usize,
    base_local: []const u8,
    indent: []const u8,
    ctx: CodegenContext) CodegenError!void {
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





pub fn appendLoadTupleLeafTypesOfStructToStack(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    decl: StructDecl,
    base_local: []const u8,
    indent: []const u8,
    ctx: CodegenContext) CodegenError!void {
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





pub fn appendLoadTupleElementOwningFromPackedBase(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    elem_index: usize,
    base_local: []const u8,
    indent: []const u8,
    ctx: CodegenContext) CodegenError!void {
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





pub fn emitIncManagedTupleLeavesAtBase(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    base_local: []const u8,
    indent: []const u8,
    ctx: CodegenContext) CodegenError!void {
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





pub fn emitDecManagedTupleLeavesAtBase(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tuple_ty: []const u8,
    base_local: []const u8,
    indent: []const u8,
    ctx: CodegenContext) CodegenError!void {
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





pub fn appendStoreForPayloadType(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    ty: []const u8) !void {
    try payload_wat.appendStoreForPayloadType(allocator, out, ty);
}





pub fn appendStoreForPayloadTypeWithIndent(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    ty: []const u8,
    indent: []const u8) !void {
    try payload_wat.appendStoreForPayloadTypeWithIndent(allocator, out, ty, indent);
}





pub fn appendLoadForPayloadTypeWithIndent(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    ty: []const u8,
    indent: []const u8) !void {
    try payload_wat.appendLoadForPayloadTypeWithIndent(allocator, out, ty, indent);
}





pub fn emitPureScalarStructLocalSet(
    allocator: std.mem.Allocator,
    base: []const u8,
    decl: StructDecl,
    out: *std.ArrayList(u8)) !void {
    var field_idx = decl.fields.len;
    while (field_idx > 0) {
        field_idx -= 1;
        try appendFmt(allocator, out, "    local.set ${s}.{s}\n", .{
            base,
            publicDeclName(decl.fields[field_idx].name),
        });
    }
}




pub fn emitPureScalarStructLocalGet(
    allocator: std.mem.Allocator,
    base: []const u8,
    decl: StructDecl,
    out: *std.ArrayList(u8)) !void {
    for (decl.fields) |field| {
        try appendFmt(allocator, out, "    local.get ${s}.{s}\n", .{
            base,
            publicDeclName(field.name),
        });
    }
}




pub fn singleTupleResultItem(result_items: []const FuncResultItem) ?FuncResultItem {
    if (result_items.len != 1) return null;
    const item = result_items[0];
    if (!isTupleTypeName(item.ty)) return null;
    if (item.abi_len < 2) return null;
    return item;
}




pub fn tupleElementPackOffsetWithStructs(tuple_ty: []const u8, index: usize, structs: []const StructDecl) ?usize {
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




pub fn tupleGetElementInfo(tokens: []const lexer.Token, second_start: usize, second_end: usize, tuple_ty: []const u8) ?TupleElementInfo {
    if (second_end != second_start + 1) return null;
    if (tokens[second_start].kind != .number) return null;
    const index = std.fmt.parseInt(usize, tokens[second_start].lexeme, 10) catch return null;
    const ty = tupleElementTypeAt(tuple_ty, index) orelse return null;
    return .{ .index = index, .ty = ty };
}




