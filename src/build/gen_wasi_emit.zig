//! WASI host call / result emit (no host table parse; see gen_wasi.zig).
const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const type_util = @import("type_name.zig");
const payload_wat = @import("gen_payload_wat.zig");
const storage_wat = @import("gen_storage_wat.zig");
const gen_util = @import("gen_util.zig");
const gen_types = @import("gen_types.zig");
const gen_union = @import("gen_union.zig");
const gen_wasi = @import("gen_wasi.zig");
const gen_collect = @import("gen_collect.zig");
const gen_import = @import("gen_import.zig");

const tokEq = gen_util.tokEq;
const findMatching = gen_util.findMatching;
const findMatchingInRange = gen_util.findMatchingInRange;
const findLineEnd = gen_util.findLineEnd;
const findLineStart = gen_util.findLineStart;
const isLineStart = gen_util.isLineStart;
const findTopLevelToken = gen_util.findTopLevelToken;
const findArgEnd = gen_util.findArgEnd;
const trimParens = gen_util.trimParens;
const publicDeclName = gen_util.publicDeclName;
const appendFmt = gen_util.appendFmt;
const stringLiteralArgLexeme = gen_util.stringLiteralArgLexeme;
const Range = gen_util.Range;
const alignUp = gen_util.alignUp;
const STORAGE_OVERWRITE_TMP_LOCAL = gen_types.STORAGE_OVERWRITE_TMP_LOCAL;
const WASI_FAMILY_TMP_LOCAL = gen_types.WASI_FAMILY_TMP_LOCAL;
const findValueEnumDecl = gen_import.findValueEnumDecl;
const isErrorLikeType = gen_collect.isErrorLikeType;
const moduleTokensEqual = gen_util.moduleTokensEqual;

const LocalSet = gen_types.LocalSet;
const Local = gen_types.Local;
const CodegenContext = gen_types.CodegenContext;
const CodegenError = gen_types.CodegenError;
const StructDecl = gen_types.StructDecl;
const StructField = gen_types.StructField;
const StructLayout = gen_types.StructLayout;
const StructLocal = gen_types.StructLocal;
const StorageLocal = gen_types.StorageLocal;
const UnionLocal = gen_types.UnionLocal;
const FuncDecl = gen_types.FuncDecl;
const HostImport = gen_types.HostImport;
const TYPE_ID_STORAGE_U8 = gen_types.TYPE_ID_STORAGE_U8;
const TYPE_ID_STORAGE_MANAGED = gen_types.TYPE_ID_STORAGE_MANAGED;
const TYPE_ID_FIRST_STRUCT = gen_types.TYPE_ID_FIRST_STRUCT;
const findLocalType = gen_types.findLocalType;
const findStorageLocal = gen_types.findStorageLocal;
const findStructLocal = gen_types.findStructLocal;
const findUnionLocal = gen_types.findUnionLocal;
const storageTypeNameForElem = gen_types.storageTypeNameForElem;

const UnionLayout = gen_union.UnionLayout;
const UnionBranch = gen_union.UnionBranch;
const unionLayoutsEqual = gen_union.unionLayoutsEqual;
const freeUnionLayout = gen_union.freeUnionLayout;
const cloneUnionLayout = gen_union.cloneUnionLayout;
const unionBranchIsStatusI32 = gen_union.unionBranchIsStatusI32;

const WasiHostImport = gen_wasi.WasiHostImport;
const wasiLowering = gen_wasi.wasiLowering;
const appendWasiImportSymbol = gen_wasi.appendWasiImportSymbol;
const findWasiHostImport = gen_wasi.findWasiHostImport;
const findWasiHostImportBySource = gen_wasi.findWasiHostImportBySource;
const parseWasiLinkAtArgs = gen_wasi.parseWasiLinkAtArgs;
const wasiCoarseFailedVariantName = gen_wasi.wasiCoarseFailedVariantName;
const wasiCoarseClosedVariantName = gen_wasi.wasiCoarseClosedVariantName;
const wasiCoarseErrorAlwaysFailed = gen_wasi.wasiCoarseErrorAlwaysFailed;
const WASI_BINDING_ENTRY_SOURCE = gen_wasi.WASI_BINDING_ENTRY_SOURCE;

const findWasiHostImportForTokens = gen_import.findWasiHostImportForTokens;
const wasiSourceForTokens = gen_import.wasiSourceForTokens;
const findRootModuleIndex = gen_import.findRootModuleIndex;
const exprCallHead = gen_import.exprCallHead;
const callHeadAt = gen_import.callHeadAt;

fn emitWasiFamilyArg(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    if (!try emit_expr(allocator, tokens, start_idx, end_idx, locals, ctx, "i32", out)) {
        if (!try emit_expr(allocator, tokens, start_idx, end_idx, locals, ctx, "u8", out)) return false;
        try out.appendSlice(allocator, "    i32.extend8_u\n");
    }
    try appendFmt(allocator, out, "    local.set ${s}\n", .{WASI_FAMILY_TMP_LOCAL});

    // Accept both the public 4/6 family values and already-canonical 0/1 values.
    try appendFmt(allocator, out, "    local.get ${s}\n", .{WASI_FAMILY_TMP_LOCAL});
    try out.appendSlice(allocator, "    i32.const 0\n    i32.eq\n    if (result i32)\n      i32.const 0\n    else\n");
    try appendFmt(allocator, out, "      local.get ${s}\n", .{WASI_FAMILY_TMP_LOCAL});
    try out.appendSlice(allocator, "      i32.const 1\n      i32.eq\n      if (result i32)\n        i32.const 1\n      else\n");
    try appendFmt(allocator, out, "        local.get ${s}\n", .{WASI_FAMILY_TMP_LOCAL});
    try out.appendSlice(allocator, "        i32.const 4\n        i32.eq\n        if (result i32)\n          i32.const 0\n        else\n");
    try appendFmt(allocator, out, "          local.get ${s}\n", .{WASI_FAMILY_TMP_LOCAL});
    try out.appendSlice(allocator, "          i32.const 6\n          i32.eq\n          if (result i32)\n            i32.const 1\n          else\n            unreachable\n          end\n        end\n      end\n    end\n");
    return true;
}

const findStructDecl = gen_collect.findStructDecl;
const findStructLayout = gen_collect.findStructLayout;
const findStructLayoutExact = gen_collect.findStructLayoutExact;
const isPackManagedHandleLeaf = gen_collect.isPackManagedHandleLeaf;
const leafPayloadBytesForPack = gen_collect.leafPayloadBytesForPack;
const pureScalarStructPackWidth = gen_collect.pureScalarStructPackWidth;
const packSlotWidth = gen_collect.packSlotWidth;
const tuplePackWidthWithStructs = gen_collect.tuplePackWidthWithStructs;
const funcParamAbiType = gen_collect.funcParamAbiType;

/// Callback into gen_lower emitExpr (breaks import cycle).
pub const EmitExprFn = *const fn (
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    expected_ty: ?[]const u8,
    out: *std.ArrayList(u8),
) CodegenError!bool;

pub fn findUnionBranchByType(layout: UnionLayout, ty: []const u8) ?UnionBranch {
    for (layout.branches) |branch| {
        if (codegenTypesCompatible(branch.ty, ty)) return branch;
    }
    return null;
}


pub fn codegenTypesCompatible(expected: []const u8, actual: []const u8) bool {
    if (std.mem.eql(u8, expected, actual)) return true;
    if (std.mem.eql(u8, expected, "text") and std.mem.eql(u8, actual, "[u8]")) return true;
    if (std.mem.eql(u8, expected, "[u8]") and std.mem.eql(u8, actual, "text")) return true;
    return false;
}


pub fn isManagedLocalType(ty: []const u8, ctx: CodegenContext) bool {
    if (isManagedPayloadType(ty)) return true;
    // Storage-pack layouts describe `[Tuple<...>]` element packing, not a managed object type.
    if (findStructLayoutExact(ctx.struct_layouts, ty)) |layout| {
        if (layout.is_storage_pack) return false;
    }
    return findStructLayout(ctx.struct_layouts, ty) != null;
}


pub fn emitStorageLenPtr(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
) !void {
    try storage_wat.emitStorageLenPtr(allocator, out, name);
}


pub fn emitStorageDataPtr(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    name: []const u8,
) !void {
    try storage_wat.emitStorageDataPtr(allocator, out, name);
}


pub fn emitWasiResultFilesizeMultiAssignment(
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

    emit_expr: EmitExprFn,
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

    if (!try emitWasiResultFilesizeCall(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr)) {
        return error.NoMatchingCall;
    }
    try emitWasiResultFilesizeValues(allocator, out);
    try appendFmt(allocator, out, "    local.set ${s}\n", .{status_name});
    try appendFmt(allocator, out, "    local.set ${s}\n", .{written_name});
    return true;
}


pub fn emitWasiResultU64StreamStatusMultiAssignment(
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

    emit_expr: EmitExprFn,
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

    if (!try emitWasiResultU64StreamCall(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr)) {
        return error.NoMatchingCall;
    }
    try emitWasiResultFilesizeValues(allocator, out);
    try appendFmt(allocator, out, "    local.set ${s}\n", .{status_name});
    try appendFmt(allocator, out, "    local.set ${s}\n", .{value_name});
    return true;
}


pub fn emitWasiResultDescriptorStatusMultiAssignment(
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

    emit_expr: EmitExprFn,
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

    if (!try emitWasiResultDescriptorCall(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr)) {
        return error.NoMatchingCall;
    }
    try emitWasiResultDescriptorValues(allocator, out);
    try appendFmt(allocator, out, "    local.set ${s}\n", .{status_name});
    try appendFmt(allocator, out, "    local.set ${s}\n", .{descriptor_name});
    return true;
}


pub fn emitWasiResultUnitStatusMultiAssignment(
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

    emit_expr: EmitExprFn,
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

    if (!try emitWasiResultUnitCall(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr)) {
        return error.NoMatchingCall;
    }
    try emitWasiResultUnitStatusValue(allocator, out);
    try appendFmt(allocator, out, "    local.set ${s}\n", .{status_name});
    return true;
}


pub fn emitWasiResultReadMultiAssignment(
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

    emit_expr: EmitExprFn,
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

    if (!try emitWasiResultReadCall(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr)) {
        return error.NoMatchingCall;
    }
    try emitWasiResultReadValues(allocator, out);
    try appendFmt(allocator, out, "    local.set ${s}\n", .{status_name});
    try appendFmt(allocator, out, "    local.set ${s}\n", .{done_name});
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try emitReplaceManagedLocalFromTmp(allocator, data_name, out);
    return true;
}


pub fn emitWasiResultListU8StatusMultiAssignment(
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

    emit_expr: EmitExprFn,
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

    if (!try emitWasiResultListU8Call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr)) {
        return error.NoMatchingCall;
    }
    try emitWasiResultListU8Values(allocator, out);
    try appendFmt(allocator, out, "    local.set ${s}\n", .{status_name});
    try appendFmt(allocator, out, "    local.set ${s}\n", .{STORAGE_OVERWRITE_TMP_LOCAL});
    try emitReplaceManagedLocalFromTmp(allocator, data_name, out);
    return true;
}


pub fn emitWasiRecordStructBinding(
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


pub fn emitWasiRecordReturnCall(
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


pub fn emitWasiRecordResultFields(
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


pub fn emitReplaceManagedLocalFromTmp(
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


pub fn emitBareWasiHostImportCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),

    emit_expr: EmitExprFn,
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
        emit_expr);
}


/// Branch index inside `@wasi_enum("target", arm|arm(n)|…)` arms (1-based).
fn branchValueInWasiEnumArms(
    tokens: []const lexer.Token,
    arms_start: usize,
    close_call: usize,
    branch_name: []const u8,
) ?usize {
    var arm_j = arms_start;
    while (arm_j < close_call) : (arm_j += 1) {
        if (tokEq(tokens[arm_j], ",")) {
            arm_j += 1;
            break;
        }
    }
    var branch_idx: usize = 1;
    while (arm_j < close_call) : (arm_j += 1) {
        if (tokEq(tokens[arm_j], "|") or tokEq(tokens[arm_j], ",")) continue;
        if (tokens[arm_j].kind != .ident) return null;
        const arm = tokens[arm_j].lexeme;
        const has_discr = arm_j + 3 < close_call and tokEq(tokens[arm_j + 1], "(") and
            tokens[arm_j + 2].kind == .number and tokEq(tokens[arm_j + 3], ")");
        if (std.mem.eql(u8, arm, branch_name)) return branch_idx;
        if (has_discr) arm_j += 3;
        branch_idx += 1;
    }
    return null;
}

/// Branch index in plain `Name error = a|b|c` arms (1-based).
fn branchValueInPlainErrorArms(
    tokens: []const lexer.Token,
    arms_start: usize,
    line_end: usize,
    branch_name: []const u8,
) ?usize {
    var j = arms_start;
    var branch_idx: usize = 1;
    while (j < line_end) : (j += 1) {
        if (tokEq(tokens[j], "|")) continue;
        if (tokens[j].kind != .ident) return null;
        if (std.mem.eql(u8, tokens[j].lexeme, branch_name)) return branch_idx;
        branch_idx += 1;
    }
    return null;
}

pub fn errorEnumBranchValue(tokens: []const lexer.Token, enum_name: []const u8, branch_name: []const u8) ?usize {
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
        const arms_start = i + 3;
        // Skip declarative `@wasi_enum("target", …)` prefix when present.
        if (arms_start < line_end and tokEq(tokens[arms_start], "@") and arms_start + 2 < line_end and
            tokens[arms_start + 1].kind == .ident and std.mem.eql(u8, tokens[arms_start + 1].lexeme, "wasi_enum") and
            tokEq(tokens[arms_start + 2], "("))
        {
            const close_call = findMatchingInRange(tokens, arms_start + 2, "(", ")", line_end) catch return null;
            return branchValueInWasiEnumArms(tokens, arms_start + 3, close_call, branch_name);
        }
        return branchValueInPlainErrorArms(tokens, arms_start, line_end, branch_name);
    }
    return null;
}



pub fn emitWasiHostImportExpr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    allow_statement_result: bool,
    out: *std.ArrayList(u8),

    emit_expr: EmitExprFn,
) CodegenError!bool {
    const lowering = wasiLowering(import) orelse return false;
    if (lowering.resource_drop) {
        if (!allow_statement_result) return false;
        return try emitWasiResourceDropCall(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
    }
    if (lowering.result_storage_elem) |elem_ty| {
        if (!std.mem.eql(u8, elem_ty, "u8")) return false;
        return try emitWasiListU8ResultCall(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
    }
    if (lowering.result_list_preopen) {
        return try emitWasiListPreopenResultCall(allocator, tokens, args_start, args_end, locals, ctx, import, out);
    }
    if (lowering.result_unit_error) {
        if (!allow_statement_result) return false;
        return try emitWasiResultUnitCall(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
    }
    if (lowering.result_list_u8_error) return false;
    if (lowering.result_filesize_error) {
        if (!allow_statement_result) return false;
        return try emitWasiResultFilesizeCall(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
    }
    if (lowering.result_u64_stream_error) {
        if (!allow_statement_result) return false;
        return try emitWasiResultU64StreamCall(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
    }
    if (lowering.result_record != null) return false;
    if (lowering.result == null) return false;
    if (args_start != args_end) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    call $");
    try appendWasiImportSymbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}


pub fn emitWasiResourceDropCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),

    emit_expr: EmitExprFn,
) CodegenError!bool {
    const arg_end = findArgEnd(tokens, args_start, args_end);
    if (arg_end != args_end) return error.NoMatchingCall;
    // Bare i32 or resource shell (Dir/File) via `.id`.
    if (!try emitWasiDescriptorHandleArg(allocator, tokens, args_start, arg_end, locals, ctx, out, emit_expr)) {
        return error.NoMatchingCall;
    }
    try out.appendSlice(allocator, "    call $");
    try appendWasiImportSymbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}


pub fn emitWasiListU8ResultCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),

    emit_expr: EmitExprFn,
) CodegenError!bool {
    if (!std.mem.eql(u8, import.target, "random/random/get-random-bytes")) return false;
    const arg_end = findArgEnd(tokens, args_start, args_end);
    if (arg_end == args_start or arg_end != args_end) return error.NoMatchingCall;
    if (!try emit_expr(allocator, tokens, args_start, arg_end, locals, ctx, "u64", out)) return error.NoMatchingCall;
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

/// G6.1 / P3: () -> list<tuple<descriptor,string>> as do [Tuple<Dir,text>] (Dir.id i64 + text).
/// G6.1 / P3: () -> list<tuple<descriptor,string>> as do [Tuple<Dir,text>] (Dir.id i64 + text).

pub fn emitWasiListPreopenResultCall(
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
    if (!std.mem.eql(u8, import.target, "filesystem/preopens/get-directories")) return false;
    if (args_start != args_end) return error.NoMatchingCall;
    // Prefer registered storage-pack layout for Tuple<Dir,text>; fall back is wrong for release.
    const pack_type_id = storageTypeIdForElement("Tuple<Dir,text>", ctx);
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
        \\
    );
    try appendFmt(allocator, out, "    i32.const {d}\n", .{pack_type_id});
    try out.appendSlice(allocator, "    call $__wasi_list_preopen_to_storage\n");
    return true;
}


pub fn emitWasiResultUnitCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),

    emit_expr: EmitExprFn,
) CodegenError!bool {
    if (std.mem.eql(u8, import.target, "filesystem/types/descriptor.link-at")) {
        return try emitWasiResultLinkAtCall(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
    }
    if (std.mem.eql(u8, import.target, "filesystem/types/descriptor.create-directory-at") or
        std.mem.eql(u8, import.target, "filesystem/types/descriptor.remove-directory-at"))
    {
        return try emitWasiResultDescriptorPathCall(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
    }
    if (std.mem.eql(u8, import.target, "io/streams/output-stream.write")) {
        return try emitWasiResultOutputWriteCall(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
    }
    // G6.3: tcp/udp-socket.bind(socket, IpSocketAddress)
    if (std.mem.eql(u8, import.target, "sockets/types/tcp-socket.bind") or
        std.mem.eql(u8, import.target, "sockets/types/udp-socket.bind"))
    {
        return try emitWasiResultSocketBindCall(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr);
    }
    if (!std.mem.eql(u8, import.target, "filesystem/types/descriptor.sync") and
        !std.mem.eql(u8, import.target, "io/streams/output-stream.flush"))
    {
        return false;
    }
    const arg_end = findArgEnd(tokens, args_start, args_end);
    if (arg_end == args_start or arg_end != args_end) return error.NoMatchingCall;
    // Bare i32 or File/OutputStream resource shell via `.id`.
    if (!try emitWasiDescriptorHandleArg(allocator, tokens, args_start, arg_end, locals, ctx, out, emit_expr)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try appendWasiImportSymbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}

/// Scratch offset past result-area header for packing `ip-socket-address` (G6.3).
const SOCKET_ADDR_PACK_OFF: u32 = 64;

/// Lower tcp/udp-socket.bind: handle + pack IpSocketAddress (payload enum) + unit result area.
pub fn emitWasiResultSocketBindCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),

    emit_expr: EmitExprFn,
) CodegenError!bool {
    if (!std.mem.eql(u8, import.target, "sockets/types/tcp-socket.bind") and
        !std.mem.eql(u8, import.target, "sockets/types/udp-socket.bind"))
        return false;

    const socket_end = findArgEnd(tokens, args_start, args_end);
    if (socket_end == args_start or socket_end >= args_end or !tokEq(tokens[socket_end], ",")) return error.NoMatchingCall;
    const addr_start = socket_end + 1;
    const addr_end = findArgEnd(tokens, addr_start, args_end);
    if (addr_end == addr_start or addr_end != args_end) return error.NoMatchingCall;

    if (!try emitWasiDescriptorHandleArg(allocator, tokens, args_start, socket_end, locals, ctx, out, emit_expr)) return error.NoMatchingCall;
    if (!try emitWasiPackIpSocketAddressArg(allocator, tokens, addr_start, addr_end, locals, ctx, out, emit_expr)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try appendWasiImportSymbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}

/// Pack IpSocketAddress (payload enum V4|V6 or ctor) into scratch; leave ptr on stack.
fn emitWasiPackIpSocketAddressArg(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
    emit_expr: EmitExprFn,
) CodegenError!bool {
    _ = ctx;
    _ = emit_expr; // pack uses struct/union locals only in v1
    const range = trimParens(tokens, start_idx, end_idx);

    // Local payload-enum: name with __union_tag / __union_payload_*
    if (range.end == range.start + 1 and tokens[range.start].kind == .ident) {
        const uname = tokens[range.start].lexeme;
        if (findUnionLocal(locals.union_locals.items, uname) != null) {
            return try emitWasiPackIpSocketAddressFromUnionLocal(allocator, uname, out);
        }
    }

    // Ctor V4(expr) / V6(expr)
    const call_head = exprCallHead(tokens, range) orelse return false;
    if (call_head.is_intrinsic) return false;
    const case_name = publicDeclName(tokens[call_head.name_idx].lexeme);
    const is_v4 = std.mem.eql(u8, case_name, "V4");
    const is_v6 = std.mem.eql(u8, case_name, "V6");
    if (!is_v4 and !is_v6) return false;

    // Payload must be unmanaged struct local for v1 pack.
    const payload_range = trimParens(tokens, call_head.args_start, call_head.args_end);
    if (payload_range.end != payload_range.start + 1 or tokens[payload_range.start].kind != .ident) return false;
    const sname = tokens[payload_range.start].lexeme;
    const struct_local = findStructLocal(locals.struct_locals.items, sname) orelse return false;

    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try appendFmt(allocator, out, "    i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF});
    try out.appendSlice(allocator, "    i32.add\n");
    // ptr stays on stack for store sequence via local tee pattern: duplicate with local? Use get/set base each time.
    // Store disc
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try appendFmt(allocator, out, "    i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF});
    try out.appendSlice(allocator, "    i32.add\n");
    if (is_v4) {
        try out.appendSlice(allocator, "    i32.const 0\n"); // ipv4 disc
        try out.appendSlice(allocator, "    i32.store\n");
        // port u16 @ +4
        try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
        try appendFmt(allocator, out, "    i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF + 4});
        try out.appendSlice(allocator, "    i32.add\n");
        try appendFmt(allocator, out, "    local.get ${s}.port\n", .{struct_local.name});
        try out.appendSlice(allocator, "    i32.store16\n");
        // pad u16 @ +6, then a,b,c,d @ +8..+11
        try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
        try appendFmt(allocator, out, "    i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF + 6});
        try out.appendSlice(allocator, "    i32.add\n    i32.const 0\n    i32.store16\n");
        inline for (.{ "a", "b", "c", "d" }, 0..) |field, fi| {
            try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
            try appendFmt(allocator, out, "    i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF + 8 + fi});
            try out.appendSlice(allocator, "    i32.add\n");
            try appendFmt(allocator, out, "    local.get ${s}.{s}\n", .{ struct_local.name, field });
            try out.appendSlice(allocator, "    i32.store8\n");
        }
    } else {
        try out.appendSlice(allocator, "    i32.const 1\n"); // ipv6 disc
        try out.appendSlice(allocator, "    i32.store\n");
        // port @ +4
        try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
        try appendFmt(allocator, out, "    i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF + 4});
        try out.appendSlice(allocator, "    i32.add\n");
        try appendFmt(allocator, out, "    local.get ${s}.port\n", .{struct_local.name});
        try out.appendSlice(allocator, "    i32.store16\n");
        // flowinfo = 0 @ +8
        try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
        try appendFmt(allocator, out, "    i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF + 8});
        try out.appendSlice(allocator, "    i32.add\n");
        try out.appendSlice(allocator, "    i32.const 0\n");
        try out.appendSlice(allocator, "    i32.store\n");
        // addr[16] from hi||lo in network byte order @ +12.
        try appendStoreU64BigEndianField(allocator, out, struct_local.name, "hi", SOCKET_ADDR_PACK_OFF + 12, "    ");
        try appendStoreU64BigEndianField(allocator, out, struct_local.name, "lo", SOCKET_ADDR_PACK_OFF + 20, "    ");
        // scope_id = 0 @ +28
        try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
        try appendFmt(allocator, out, "    i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF + 28});
        try out.appendSlice(allocator, "    i32.add\n");
        try out.appendSlice(allocator, "    i32.const 0\n");
        try out.appendSlice(allocator, "    i32.store\n");
    }
    // leave pack ptr on stack
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try appendFmt(allocator, out, "    i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF});
    try out.appendSlice(allocator, "    i32.add\n");
    return true;
}

fn emitWasiPackIpSocketAddressFromUnionLocal(
    allocator: std.mem.Allocator,
    uname: []const u8,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    // Tag 0 = V4, 1 = V6. Payloads: V4 a,b,c,d,port; V6 hi,lo,port (max slots overlap).
    // For v1, only support packing when tag known at emit is too hard; always emit branch on tag.
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try appendFmt(allocator, out, "    i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF});
    try out.appendSlice(allocator, "    i32.add\n");
    try appendFmt(allocator, out, "    local.get ${s}.__union_tag\n", .{uname});
    try out.appendSlice(allocator, "    i32.store\n"); // disc = case tag (0=V4, 1=V6)

    // Common: port is last payload field for both — V4 has 5 slots (0..4), V6 has 3 (0..2).
    // Layout for V4: p0=a p1=b p2=c p3=d p4=port
    // Layout for V6: p0=hi p1=lo p2=port — different; branch on tag.
    try appendFmt(allocator, out, "    local.get ${s}.__union_tag\n", .{uname});
    try out.appendSlice(allocator, "    i32.eqz\n");
    try out.appendSlice(allocator, "    if\n");
    // V4 pack: port @+4, padding @+6, bytes @+8..+11.
    try out.appendSlice(allocator, "      global.get $__wasi_result_area_base\n");
    try appendFmt(allocator, out, "      i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF + 4});
    try out.appendSlice(allocator, "      i32.add\n");
    try appendFmt(allocator, out, "      local.get ${s}.__union_payload_4\n", .{uname});
    try out.appendSlice(allocator, "      i32.store16\n");
    try out.appendSlice(allocator, "      global.get $__wasi_result_area_base\n");
    try appendFmt(allocator, out, "      i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF + 6});
    try out.appendSlice(allocator, "      i32.add\n      i32.const 0\n      i32.store16\n");
    inline for (0..4) |fi| {
        try out.appendSlice(allocator, "      global.get $__wasi_result_area_base\n");
        try appendFmt(allocator, out, "      i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF + 8 + fi});
        try out.appendSlice(allocator, "      i32.add\n");
        try appendFmt(allocator, out, "      local.get ${s}.__union_payload_{d}\n", .{ uname, fi });
        try out.appendSlice(allocator, "      i32.store8\n");
    }
    try out.appendSlice(allocator, "    else\n");
    // V6 pack
    try out.appendSlice(allocator, "      global.get $__wasi_result_area_base\n");
    try appendFmt(allocator, out, "      i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF + 4});
    try out.appendSlice(allocator, "      i32.add\n");
    try appendFmt(allocator, out, "      local.get ${s}.__union_payload_2\n", .{uname});
    try out.appendSlice(allocator, "      i32.store16\n");
    try out.appendSlice(allocator, "      global.get $__wasi_result_area_base\n");
    try appendFmt(allocator, out, "      i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF + 8});
    try out.appendSlice(allocator, "      i32.add\n");
    try out.appendSlice(allocator, "      i32.const 0\n");
    try out.appendSlice(allocator, "      i32.store\n");
    try appendStoreU64BigEndianField(allocator, out, uname, "__union_payload_0", SOCKET_ADDR_PACK_OFF + 12, "      ");
    try appendStoreU64BigEndianField(allocator, out, uname, "__union_payload_1", SOCKET_ADDR_PACK_OFF + 20, "      ");
    try out.appendSlice(allocator, "      global.get $__wasi_result_area_base\n");
    try appendFmt(allocator, out, "      i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF + 28});
    try out.appendSlice(allocator, "      i32.add\n");
    try out.appendSlice(allocator, "      i32.const 0\n");
    try out.appendSlice(allocator, "      i32.store\n");
    try out.appendSlice(allocator, "    end\n");

    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try appendFmt(allocator, out, "    i32.const {d}\n", .{SOCKET_ADDR_PACK_OFF});
    try out.appendSlice(allocator, "    i32.add\n");
    return true;
}

fn appendStoreU64BigEndianField(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    local_base: []const u8,
    field_name: []const u8,
    offset: u32,
    indent: []const u8,
) !void {
    inline for (0..8) |byte_idx| {
        const shift: u32 = @as(u32, 56 - byte_idx * 8);
        try appendFmt(allocator, out, "{s}global.get $__wasi_result_area_base\n", .{indent});
        try appendFmt(allocator, out, "{s}i32.const {d}\n", .{ indent, offset + byte_idx });
        try appendFmt(allocator, out, "{s}i32.add\n", .{indent});
        try appendFmt(allocator, out, "{s}local.get ${s}.{s}\n", .{ indent, local_base, field_name });
        try appendFmt(allocator, out, "{s}i64.const {d}\n", .{ indent, shift });
        try appendFmt(allocator, out, "{s}i64.shr_u\n", .{indent});
        try appendFmt(allocator, out, "{s}i64.const 255\n{s}i64.and\n{s}i64.store8\n", .{ indent, indent, indent });
    }
}


pub fn emitWasiResultDescriptorPathCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),

    emit_expr: EmitExprFn,
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

    // Bare i32 or Dir resource shell via `.id`.
    if (!try emitWasiDescriptorHandleArg(allocator, tokens, args_start, descriptor_end, locals, ctx, out, emit_expr)) return error.NoMatchingCall;
    if (!try emitWasiStringArg(allocator, tokens, path_start, path_end, locals, ctx, out)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try appendWasiImportSymbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}


pub fn emitWasiResultOutputWriteCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),

    emit_expr: EmitExprFn,
) CodegenError!bool {
    if (!std.mem.eql(u8, import.target, "io/streams/output-stream.write")) return false;

    const stream_end = findArgEnd(tokens, args_start, args_end);
    if (stream_end == args_start or stream_end >= args_end or !tokEq(tokens[stream_end], ",")) return error.NoMatchingCall;
    const data_start = stream_end + 1;
    const data_end = findArgEnd(tokens, data_start, args_end);
    if (data_end == data_start or data_end != args_end) return error.NoMatchingCall;

    // Bare i32 or OutputStream resource shell via `.id`.
    if (!try emitWasiDescriptorHandleArg(allocator, tokens, args_start, stream_end, locals, ctx, out, emit_expr)) return error.NoMatchingCall;
    if (!try emitWasiListU8Arg(allocator, tokens, data_start, data_end, locals, out)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try appendWasiImportSymbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}


pub fn emitWasiResultDescriptorCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),

    emit_expr: EmitExprFn,
) CodegenError!bool {
    // G6.3: tcp/udp-socket.create(family) -> result<socket, error-code>
    if (std.mem.eql(u8, import.target, "sockets/types/tcp-socket.create") or
        std.mem.eql(u8, import.target, "sockets/types/udp-socket.create"))
    {
        const family_end = findArgEnd(tokens, args_start, args_end);
        if (family_end == args_start or family_end != args_end) return error.NoMatchingCall;
        if (!try emitWasiFamilyArg(allocator, tokens, args_start, family_end, locals, ctx, out, emit_expr)) return error.NoMatchingCall;
        try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
        try out.appendSlice(allocator, "    call $");
        try appendWasiImportSymbol(allocator, out, import.target);
        try out.appendSlice(allocator, "\n");
        return true;
    }

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

    if (!try emitWasiDescriptorHandleArg(allocator, tokens, args_start, descriptor_end, locals, ctx, out, emit_expr)) return error.NoMatchingCall;
    if (!try emit_expr(allocator, tokens, path_flags_start, path_flags_end, locals, ctx, "i32", out)) return error.NoMatchingCall;
    if (!try emitWasiStringArg(allocator, tokens, path_start, path_end, locals, ctx, out)) return error.NoMatchingCall;
    if (!try emit_expr(allocator, tokens, open_flags_start, open_flags_end, locals, ctx, "i32", out)) return error.NoMatchingCall;
    if (!try emit_expr(allocator, tokens, descriptor_flags_start, descriptor_flags_end, locals, ctx, "i32", out)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try appendWasiImportSymbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}

/// Lower descriptor/resource handle arg: bare i32, or unmanaged resource struct `.id` (i64 → i32).
/// Lower descriptor/resource handle arg: bare i32, or unmanaged resource struct `.id` (i64 → i32).

pub fn emitWasiDescriptorHandleArg(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),

    emit_expr: EmitExprFn,
) CodegenError!bool {
    if (try emit_expr(allocator, tokens, start_idx, end_idx, locals, ctx, "i32", out)) return true;

    const range = trimParens(tokens, start_idx, end_idx);
    if (range.end != range.start + 1 or tokens[range.start].kind != .ident) return false;
    const struct_local = findStructLocal(locals.struct_locals.items, tokens[range.start].lexeme) orelse return false;
    if (findStructLayout(ctx.struct_layouts, struct_local.ty) != null) return false;
    const decl = findStructDecl(ctx.structs, struct_local.ty) orelse return false;
    var id_ty: ?[]const u8 = null;
    for (decl.fields) |field| {
        if (std.mem.eql(u8, publicDeclName(field.name), "id")) {
            id_ty = field.ty;
            break;
        }
    }
    const field_ty = id_ty orelse return false;
    try appendFmt(allocator, out, "    local.get ${s}.id\n", .{struct_local.name});
    if (std.mem.eql(u8, field_ty, "i64")) {
        try out.appendSlice(allocator, "    i32.wrap_i64\n");
        return true;
    }
    if (std.mem.eql(u8, field_ty, "i32")) return true;
    return false;
}


pub fn emitWasiResultLinkAtCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),

    emit_expr: EmitExprFn,
) CodegenError!bool {
    if (!std.mem.eql(u8, import.target, "filesystem/types/descriptor.link-at")) return false;
    const args = parseWasiLinkAtArgs(tokens, args_start, args_end) orelse return error.NoMatchingCall;

    // Bare i32 or File resource shells via `.id` for both descriptor args.
    if (!try emitWasiDescriptorHandleArg(allocator, tokens, args.descriptor_start, args.descriptor_end, locals, ctx, out, emit_expr)) return error.NoMatchingCall;
    if (!try emit_expr(allocator, tokens, args.old_flags_start, args.old_flags_end, locals, ctx, "i32", out)) return error.NoMatchingCall;
    if (!try emitWasiStringArg(allocator, tokens, args.old_path_start, args.old_path_end, locals, ctx, out)) return error.NoMatchingCall;
    if (!try emitWasiDescriptorHandleArg(allocator, tokens, args.new_descriptor_start, args.new_descriptor_end, locals, ctx, out, emit_expr)) return error.NoMatchingCall;
    if (!try emitWasiStringArg(allocator, tokens, args.new_path_start, args.new_path_end, locals, ctx, out)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try appendWasiImportSymbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}



pub fn emitWasiStringArg(
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


pub fn emitWasiResultFilesizeCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),

    emit_expr: EmitExprFn,
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

    // Bare i32 or File resource shell via `.id`.
    if (!try emitWasiDescriptorHandleArg(allocator, tokens, args_start, descriptor_end, locals, ctx, out, emit_expr)) return error.NoMatchingCall;
    if (!try emitWasiListU8Arg(allocator, tokens, buffer_start, buffer_end, locals, out)) return error.NoMatchingCall;
    if (!try emit_expr(allocator, tokens, offset_start, offset_end, locals, ctx, "u64", out)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try appendWasiImportSymbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}


pub fn emitWasiResultU64StreamCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),

    emit_expr: EmitExprFn,
) CodegenError!bool {
    if (!std.mem.eql(u8, import.target, "io/streams/output-stream.check-write")) return false;

    const stream_end = findArgEnd(tokens, args_start, args_end);
    if (stream_end == args_start or stream_end != args_end) return error.NoMatchingCall;

    // Bare i32 or OutputStream resource shell via `.id`.
    if (!try emitWasiDescriptorHandleArg(allocator, tokens, args_start, stream_end, locals, ctx, out, emit_expr)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try appendWasiImportSymbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}


pub fn emitWasiResultReadCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),

    emit_expr: EmitExprFn,
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

    // Bare i32 or File resource shell via `.id`.
    if (!try emitWasiDescriptorHandleArg(allocator, tokens, args_start, descriptor_end, locals, ctx, out, emit_expr)) return error.NoMatchingCall;
    if (!try emit_expr(allocator, tokens, length_start, length_end, locals, ctx, "u64", out)) return error.NoMatchingCall;
    if (!try emit_expr(allocator, tokens, offset_start, offset_end, locals, ctx, "u64", out)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try appendWasiImportSymbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}


pub fn emitWasiResultListU8Call(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    out: *std.ArrayList(u8),

    emit_expr: EmitExprFn,
) CodegenError!bool {
    if (!std.mem.eql(u8, import.target, "io/streams/input-stream.read")) return false;

    const stream_end = findArgEnd(tokens, args_start, args_end);
    if (stream_end == args_start or stream_end >= args_end or !tokEq(tokens[stream_end], ",")) return error.NoMatchingCall;
    const len_start = stream_end + 1;
    const len_end = findArgEnd(tokens, len_start, args_end);
    if (len_end == len_start or len_end != args_end) return error.NoMatchingCall;

    // Bare i32 or InputStream resource shell via `.id`.
    if (!try emitWasiDescriptorHandleArg(allocator, tokens, args_start, stream_end, locals, ctx, out, emit_expr)) return error.NoMatchingCall;
    if (!try emit_expr(allocator, tokens, len_start, len_end, locals, ctx, "u64", out)) return error.NoMatchingCall;
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    call $");
    try appendWasiImportSymbol(allocator, out, import.target);
    try out.appendSlice(allocator, "\n");
    return true;
}


pub fn emitWasiResultUnitStatusValue(
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




/// Emit error-enum payload for WASI err arm: open → always *Failed; unit/write → status 1 (*Closed) else *Failed.
/// Loads error-code from result-area offset `code_offset` (open-at/unit = 4; filesize write = 8).
/// Emit error-enum payload for WASI err arm: open → always *Failed; unit/write → status 1 (*Closed) else *Failed.
/// Loads error-code from result-area offset `code_offset` (open-at/unit = 4; filesize write = 8).

pub fn emitWasiCoarseErrorEnumPayload(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    import: WasiHostImport,
    err_ty: []const u8,
    code_offset: u32,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const failed_name = wasiCoarseFailedVariantName(import, err_ty) orelse return false;
    const failed_val = errorEnumBranchValue(tokens, err_ty, failed_name) orelse return false;
    if (wasiCoarseErrorAlwaysFailed(import)) {
        try appendFmt(allocator, out, "      i32.const {d}\n", .{failed_val});
        return true;
    }
    const closed_name = wasiCoarseClosedVariantName(err_ty) orelse return false;
    const closed_val = errorEnumBranchValue(tokens, err_ty, closed_name) orelse return false;
    // status = error-code+1; 1 ⇒ Closed (same as *status_to_error helpers).
    try out.appendSlice(allocator, "      global.get $__wasi_result_area_base\n");
    try appendFmt(allocator, out, "      i32.const {d}\n", .{code_offset});
    try out.appendSlice(allocator,
        \\      i32.add
        \\      i32.load
        \\      i32.const 1
        \\      i32.add
        \\      i32.const 1
        \\      i32.eq
        \\      if (result i32)
        \\
    );
    try appendFmt(allocator, out, "        i32.const {d}\n", .{closed_val});
    try out.appendSlice(allocator, "      else\n");
    try appendFmt(allocator, out, "        i32.const {d}\n", .{failed_val});
    try out.appendSlice(allocator, "      end\n");
    return true;
}



pub fn unionBranchIsCoarseError(tokens: []const lexer.Token, layout: UnionLayout, branch: UnionBranch) bool {
    if (!isErrorLikeType(tokens, branch.ty)) return false;
    if (branch.payload_len != 1) return false;
    if (branch.payload_start >= layout.payload_tys.len) return false;
    return isErrorLikeType(tokens, layout.payload_tys[branch.payload_start]);
}

/// Lower unit fallible WASI host into exclusive union stack values: payload slots + tag.
/// Shapes: `nil | i32` (status), or `nil | DirError` / `DirError | nil` / FileError variants (coarse).
/// Lower unit fallible WASI host into exclusive union stack values: payload slots + tag.
/// Shapes: `nil | i32` (status), or `nil | DirError` / `DirError | nil` / FileError variants (coarse).

pub fn emitWasiUnitResultAsUnionValue(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    layout: UnionLayout,
    out: *std.ArrayList(u8),

    emit_expr: EmitExprFn,
) CodegenError!bool {
    const lowering = wasiLowering(import) orelse return false;
    if (!lowering.result_unit_error) return false;

    const nil_branch = findUnionBranchByType(layout, "nil") orelse return false;
    if (nil_branch.tag != 0) return false;

    var err_branch: ?UnionBranch = null;
    var err_is_coarse = false;
    for (layout.branches) |branch| {
        if (std.mem.eql(u8, branch.ty, "nil")) continue;
        if (err_branch != null) return false;
        if (unionBranchIsStatusI32(layout, branch)) {
            err_branch = branch;
            err_is_coarse = false;
            continue;
        }
        if (unionBranchIsCoarseError(tokens, layout, branch)) {
            err_branch = branch;
            err_is_coarse = true;
            continue;
        }
        return false;
    }
    const err = err_branch orelse return false;
    // Single i32/error payload slot only for this phase.
    if (layout.payload_tys.len != 1) return false;

    if (!try emitWasiResultUnitCall(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr)) {
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
        \\
    );
    if (err_is_coarse) {
        if (!try emitWasiCoarseErrorEnumPayload(allocator, tokens, import, err.ty, 4, out)) {
            return error.NoMatchingCall;
        }
    } else {
        try out.appendSlice(allocator,
            \\      global.get $__wasi_result_area_base
            \\      i32.const 4
            \\      i32.add
            \\      i32.load
            \\      i32.const 1
            \\      i32.add
            \\
        );
    }
    try appendFmt(allocator, out, "      i32.const {d}\n", .{err.tag});
    try out.appendSlice(allocator, "    end\n");
    return true;
}

/// Lower `result<filesize,error-code>` / stream check-write into exclusive union: e.g. `u64 | i32` or `u64 | FileError`.
/// Ok arm is written filesize/allowed (u64); err arm is status i32 or coarse FileError.
/// Lower `result<filesize,error-code>` / stream check-write into exclusive union: e.g. `u64 | i32` or `u64 | FileError`.
/// Ok arm is written filesize/allowed (u64); err arm is status i32 or coarse FileError.

pub fn emitWasiFilesizeResultAsUnionValue(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    layout: UnionLayout,
    out: *std.ArrayList(u8),

    emit_expr: EmitExprFn,
) CodegenError!bool {
    const lowering = wasiLowering(import) orelse return false;
    // Same result-area layout for write filesize and stream check-write u64.
    if (!lowering.result_filesize_error and !lowering.result_u64_stream_error) return false;
    if (layout.branches.len != 2) return false;

    var ok_branch: ?UnionBranch = null;
    var err_branch: ?UnionBranch = null;
    var err_is_coarse = false;
    for (layout.branches) |branch| {
        if (unionBranchIsStatusI32(layout, branch)) {
            if (err_branch != null) return false;
            err_branch = branch;
            err_is_coarse = false;
            continue;
        }
        if (unionBranchIsCoarseError(tokens, layout, branch)) {
            if (err_branch != null) return false;
            err_branch = branch;
            err_is_coarse = true;
            continue;
        }
        // Ok arm: scalar filesize (u64).
        if (std.mem.eql(u8, branch.ty, "u64") and branch.payload_len == 1 and
            branch.payload_start < layout.payload_tys.len and
            std.mem.eql(u8, layout.payload_tys[branch.payload_start], "u64"))
        {
            if (ok_branch != null) return false;
            ok_branch = branch;
            continue;
        }
        return false;
    }
    const ok = ok_branch orelse return false;
    const err = err_branch orelse return false;
    if (layout.payload_tys.len != 2) return false;

    if (lowering.result_filesize_error) {
        if (!try emitWasiResultFilesizeCall(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr)) {
            return error.NoMatchingCall;
        }
    } else if (!try emitWasiResultU64StreamCall(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr)) {
        return error.NoMatchingCall;
    }

    // Stack: payload slots…, tag (matches emitUnionValue / emitWasiResultFilesizeValues).
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    i32.load\n");
    try out.appendSlice(allocator, "    i32.eqz\n");
    try out.appendSlice(allocator, "    if (result");
    for (layout.payload_tys) |payload_ty| {
        try appendFmt(allocator, out, " {s}", .{codegenWasmType(ctx, payload_ty)});
    }
    try out.appendSlice(allocator, " i32)\n");

    // ok: filesize at result-area +8; zero err slot; ok tag
    for (layout.payload_tys, 0..) |payload_ty, idx| {
        if (idx == ok.payload_start) {
            try out.appendSlice(allocator,
                \\      global.get $__wasi_result_area_base
                \\      i32.const 8
                \\      i32.add
                \\      i64.load
                \\
            );
        } else {
            try appendFmt(allocator, out, "      {s}.const 0\n", .{codegenWasmType(ctx, payload_ty)});
        }
    }
    try appendFmt(allocator, out, "      i32.const {d}\n", .{ok.tag});

    try out.appendSlice(allocator, "    else\n");
    // err: zero ok slot; status or coarse FileError at +8; err tag
    for (layout.payload_tys, 0..) |payload_ty, idx| {
        if (idx == err.payload_start and err_is_coarse) {
            if (!try emitWasiCoarseErrorEnumPayload(allocator, tokens, import, err.ty, 8, out)) {
                return error.NoMatchingCall;
            }
        } else if (idx == err.payload_start) {
            try out.appendSlice(allocator,
                \\      global.get $__wasi_result_area_base
                \\      i32.const 8
                \\      i32.add
                \\      i32.load
                \\      i32.const 1
                \\      i32.add
                \\
            );
        } else {
            try appendFmt(allocator, out, "      {s}.const 0\n", .{codegenWasmType(ctx, payload_ty)});
        }
    }
    try appendFmt(allocator, out, "      i32.const {d}\n", .{err.tag});
    try out.appendSlice(allocator, "    end\n");
    return true;
}

/// Lower `result<tuple<list<u8>,bool>,error-code>` into exclusive union: e.g. `Tuple<[u8], bool> | i32`.
/// Ok arm is flattened tuple leaves (storage handle + bool); err arm is status i32 (error-code+1).
/// Lower `result<tuple<list<u8>,bool>,error-code>` into exclusive union: e.g. `Tuple<[u8], bool> | i32`.
/// Ok arm is flattened tuple leaves (storage handle + bool); err arm is status i32 (error-code+1).

pub fn emitWasiReadResultAsUnionValue(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    layout: UnionLayout,
    out: *std.ArrayList(u8),

    emit_expr: EmitExprFn,
) CodegenError!bool {
    const lowering = wasiLowering(import) orelse return false;
    if (!lowering.result_read_error) return false;
    if (layout.branches.len != 2) return false;

    var ok_branch: ?UnionBranch = null;
    var err_branch: ?UnionBranch = null;
    for (layout.branches) |branch| {
        if (std.mem.eql(u8, branch.ty, "i32") and branch.payload_len == 1 and
            branch.payload_start < layout.payload_tys.len and
            std.mem.eql(u8, layout.payload_tys[branch.payload_start], "i32"))
        {
            if (err_branch != null) return false;
            err_branch = branch;
            continue;
        }
        // Ok arm: Tuple<[u8], bool> → two leaf slots.
        if (isTupleTypeName(branch.ty) and branch.payload_len == 2 and
            branch.payload_start + 1 < layout.payload_tys.len and
            std.mem.eql(u8, layout.payload_tys[branch.payload_start], "[u8]") and
            std.mem.eql(u8, layout.payload_tys[branch.payload_start + 1], "bool"))
        {
            if (ok_branch != null) return false;
            ok_branch = branch;
            continue;
        }
        return false;
    }
    const ok = ok_branch orelse return false;
    const err = err_branch orelse return false;
    if (layout.payload_tys.len != 3) return false;
    if (!std.mem.eql(u8, ok.ty, "Tuple<[u8],bool>") and !std.mem.eql(u8, ok.ty, "Tuple<[u8], bool>")) {
        // Compact source_ty from tokens drops spaces; branch.ty is compact.
        // Accept only the two-leaf shape already checked above.
        if (!(isTupleTypeName(ok.ty) and
            std.mem.eql(u8, layout.payload_tys[ok.payload_start], "[u8]") and
            std.mem.eql(u8, layout.payload_tys[ok.payload_start + 1], "bool")))
        {
            return false;
        }
    }

    if (!try emitWasiResultReadCall(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr)) {
        return error.NoMatchingCall;
    }

    // Stack: payload slots…, tag (matches emitUnionValue / multi-lhs data,done,status order).
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    i32.load\n");
    try out.appendSlice(allocator, "    i32.eqz\n");
    try out.appendSlice(allocator, "    if (result");
    for (layout.payload_tys) |payload_ty| {
        try appendFmt(allocator, out, " {s}", .{codegenWasmType(ctx, payload_ty)});
    }
    try out.appendSlice(allocator, " i32)\n");

    // ok: list→storage + done bool; zero err slot; ok tag
    for (layout.payload_tys, 0..) |payload_ty, idx| {
        if (idx == ok.payload_start) {
            try out.appendSlice(allocator,
                \\      global.get $__wasi_result_area_base
                \\      i32.const 4
                \\      i32.add
                \\      i32.load
                \\      global.get $__wasi_result_area_base
                \\      i32.const 8
                \\      i32.add
                \\      i32.load
                \\      call $__wasi_list_u8_to_storage
                \\
            );
        } else if (idx == ok.payload_start + 1) {
            try out.appendSlice(allocator,
                \\      global.get $__wasi_result_area_base
                \\      i32.const 12
                \\      i32.add
                \\      i32.load8_u
                \\
            );
        } else {
            try appendFmt(allocator, out, "      {s}.const 0\n", .{codegenWasmType(ctx, payload_ty)});
        }
    }
    try appendFmt(allocator, out, "      i32.const {d}\n", .{ok.tag});

    try out.appendSlice(allocator, "    else\n");
    // err: empty storage + false done in ok slots; status = error-code + 1 at +4; err tag
    for (layout.payload_tys, 0..) |payload_ty, idx| {
        if (idx == ok.payload_start) {
            try storage_wat.emitEmptyStorageU8Value(allocator, out);
        } else if (idx == ok.payload_start + 1) {
            try out.appendSlice(allocator, "      i32.const 0\n");
        } else if (idx == err.payload_start) {
            try out.appendSlice(allocator,
                \\      global.get $__wasi_result_area_base
                \\      i32.const 4
                \\      i32.add
                \\      i32.load
                \\      i32.const 1
                \\      i32.add
                \\
            );
        } else {
            try appendFmt(allocator, out, "      {s}.const 0\n", .{codegenWasmType(ctx, payload_ty)});
        }
    }
    try appendFmt(allocator, out, "      i32.const {d}\n", .{err.tag});
    try out.appendSlice(allocator, "    end\n");
    return true;
}

/// Lower `result<list<u8>,stream-error>` into exclusive union stack: e.g. `[u8] | i32` or `[u8] | StreamError`.
/// Ok arm is storage handle from list{ptr,len}; err arm is status i32 or coarse StreamError.
/// Lower `result<list<u8>,stream-error>` into exclusive union stack: e.g. `[u8] | i32` or `[u8] | StreamError`.
/// Ok arm is storage handle from list{ptr,len}; err arm is status i32 or coarse StreamError.

pub fn emitWasiListU8ResultAsUnionValue(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    layout: UnionLayout,
    out: *std.ArrayList(u8),

    emit_expr: EmitExprFn,
) CodegenError!bool {
    const lowering = wasiLowering(import) orelse return false;
    if (!lowering.result_list_u8_error) return false;
    if (layout.branches.len != 2) return false;

    var ok_branch: ?UnionBranch = null;
    var err_branch: ?UnionBranch = null;
    var err_is_coarse = false;
    for (layout.branches) |branch| {
        if (unionBranchIsStatusI32(layout, branch)) {
            if (err_branch != null) return false;
            err_branch = branch;
            err_is_coarse = false;
            continue;
        }
        if (unionBranchIsCoarseError(tokens, layout, branch)) {
            if (err_branch != null) return false;
            err_branch = branch;
            err_is_coarse = true;
            continue;
        }
        // Ok arm: managed list storage ([u8] handle as i32).
        if (isStorageTypeName(branch.ty) and branch.payload_len == 1 and
            branch.payload_start < layout.payload_tys.len and
            isStorageTypeName(layout.payload_tys[branch.payload_start]))
        {
            if (ok_branch != null) return false;
            ok_branch = branch;
            continue;
        }
        return false;
    }
    const ok = ok_branch orelse return false;
    const err = err_branch orelse return false;
    if (layout.payload_tys.len != 2) return false;
    // Stream-read list is u8-only for this phase.
    if (!std.mem.eql(u8, ok.ty, "[u8]")) return false;
    if (!std.mem.eql(u8, layout.payload_tys[ok.payload_start], "[u8]")) return false;

    if (!try emitWasiResultListU8Call(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr)) {
        return error.NoMatchingCall;
    }

    // Stack: payload slots…, tag (matches emitUnionValue / multi-lhs list+status order).
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    i32.load\n");
    try out.appendSlice(allocator, "    i32.eqz\n");
    try out.appendSlice(allocator, "    if (result");
    for (layout.payload_tys) |payload_ty| {
        try appendFmt(allocator, out, " {s}", .{codegenWasmType(ctx, payload_ty)});
    }
    try out.appendSlice(allocator, " i32)\n");

    // ok: storage handle from list{ptr,len}; zero err slot; ok tag
    for (layout.payload_tys, 0..) |payload_ty, idx| {
        if (idx == ok.payload_start) {
            try out.appendSlice(allocator,
                \\      global.get $__wasi_result_area_base
                \\      i32.const 4
                \\      i32.add
                \\      i32.load
                \\      global.get $__wasi_result_area_base
                \\      i32.const 8
                \\      i32.add
                \\      i32.load
                \\      call $__wasi_list_u8_to_storage
                \\
            );
        } else {
            try appendFmt(allocator, out, "      {s}.const 0\n", .{codegenWasmType(ctx, payload_ty)});
        }
    }
    try appendFmt(allocator, out, "      i32.const {d}\n", .{ok.tag});

    try out.appendSlice(allocator, "    else\n");
    // err: empty storage in ok slot; status or coarse StreamError at +4; err tag
    for (layout.payload_tys, 0..) |payload_ty, idx| {
        if (idx == ok.payload_start) {
            try storage_wat.emitEmptyStorageU8Value(allocator, out);
        } else if (idx == err.payload_start and err_is_coarse) {
            if (!try emitWasiCoarseErrorEnumPayload(allocator, tokens, import, err.ty, 4, out)) {
                return false;
            }
        } else if (idx == err.payload_start) {
            try out.appendSlice(allocator,
                    \\      global.get $__wasi_result_area_base
                    \\      i32.const 4
                    \\      i32.add
                    \\      i32.load
                    \\      i32.const 1
                    \\      i32.add
                    \\
            );
        } else {
            try appendFmt(allocator, out, "      {s}.const 0\n", .{codegenWasmType(ctx, payload_ty)});
        }
    }
    try appendFmt(allocator, out, "      i32.const {d}\n", .{err.tag});
    try out.appendSlice(allocator, "    end\n");
    return true;
}

/// Lower `result<descriptor,error-code>` into exclusive union stack: e.g. `Dir | i32` or `Dir | DirError`.
/// Ok arm carries resource payload (Dir.id as i64 from descriptor); err arm is status i32 or coarse error enum.
/// Lower `result<descriptor,error-code>` into exclusive union stack: e.g. `Dir | i32` or `Dir | DirError`.
/// Ok arm carries resource payload (Dir.id as i64 from descriptor); err arm is status i32 or coarse error enum.

pub fn emitWasiDescriptorResultAsUnionValue(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    args_start: usize,
    args_end: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    import: WasiHostImport,
    layout: UnionLayout,
    out: *std.ArrayList(u8),

    emit_expr: EmitExprFn,
) CodegenError!bool {
    const lowering = wasiLowering(import) orelse return false;
    if (!lowering.result_descriptor_error) return false;
    if (layout.branches.len != 2) return false;

    var ok_branch: ?UnionBranch = null;
    var err_branch: ?UnionBranch = null;
    var err_is_coarse = false;
    for (layout.branches) |branch| {
        if (unionBranchIsStatusI32(layout, branch)) {
            if (err_branch != null) return false;
            err_branch = branch;
            err_is_coarse = false;
            continue;
        }
        if (unionBranchIsCoarseError(tokens, layout, branch)) {
            if (err_branch != null) return false;
            err_branch = branch;
            err_is_coarse = true;
            continue;
        }
        if (ok_branch != null) return false;
        if (branch.payload_len == 0) return false;
        ok_branch = branch;
    }
    const ok = ok_branch orelse return false;
    const err = err_branch orelse return false;
    // Ok payload must be a single scalar slot (Dir → i64 id, or bare i32 descriptor sugar).
    if (ok.payload_len != 1) return false;
    if (ok.payload_start >= layout.payload_tys.len) return false;
    const ok_payload_ty = layout.payload_tys[ok.payload_start];
    if (!std.mem.eql(u8, ok_payload_ty, "i32") and !std.mem.eql(u8, ok_payload_ty, "i64")) return false;

    if (!try emitWasiResultDescriptorCall(allocator, tokens, args_start, args_end, locals, ctx, import, out, emit_expr)) {
        return error.NoMatchingCall;
    }

    // Stack: payload slots…, tag (matches emitUnionValue / emitUnionBranchValue order).
    try out.appendSlice(allocator, "    global.get $__wasi_result_area_base\n");
    try out.appendSlice(allocator, "    i32.load\n");
    try out.appendSlice(allocator, "    i32.eqz\n");
    try out.appendSlice(allocator, "    if (result");
    for (layout.payload_tys) |payload_ty| {
        try appendFmt(allocator, out, " {s}", .{codegenWasmType(ctx, payload_ty)});
    }
    try out.appendSlice(allocator, " i32)\n");

    // ok: fill ok payload from descriptor; zero other slots; ok tag
    for (layout.payload_tys, 0..) |payload_ty, idx| {
        if (idx == ok.payload_start) {
            try out.appendSlice(allocator,
                \\      global.get $__wasi_result_area_base
                \\      i32.const 4
                \\      i32.add
                \\      i32.load
                \\
            );
            if (std.mem.eql(u8, payload_ty, "i64")) {
                try out.appendSlice(allocator, "      i64.extend_i32_s\n");
            }
        } else {
            try appendFmt(allocator, out, "      {s}.const 0\n", .{codegenWasmType(ctx, payload_ty)});
        }
    }
    try appendFmt(allocator, out, "      i32.const {d}\n", .{ok.tag});

    try out.appendSlice(allocator, "    else\n");
    // err: zero ok slots; status or coarse *OpenFailed; err tag
    for (layout.payload_tys, 0..) |payload_ty, idx| {
        if (idx == err.payload_start and err_is_coarse) {
            if (!try emitWasiCoarseErrorEnumPayload(allocator, tokens, import, err.ty, 4, out)) {
                return error.NoMatchingCall;
            }
        } else if (idx == err.payload_start) {
            try out.appendSlice(allocator,
                    \\      global.get $__wasi_result_area_base
                    \\      i32.const 4
                    \\      i32.add
                    \\      i32.load
                    \\      i32.const 1
                    \\      i32.add
                    \\
            );
        } else {
            try appendFmt(allocator, out, "      {s}.const 0\n", .{codegenWasmType(ctx, payload_ty)});
        }
    }
    try appendFmt(allocator, out, "      i32.const {d}\n", .{err.tag});
    try out.appendSlice(allocator, "    end\n");
    return true;
}


pub fn emitWasiResultReadValues(
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
    try storage_wat.emitEmptyStorageU8Value(allocator, out);
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


pub fn emitWasiResultListU8Values(
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
    try storage_wat.emitEmptyStorageU8Value(allocator, out);
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


pub fn emitWasiResultDescriptorValues(
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


pub fn emitWasiResultFilesizeValues(
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


pub fn emitWasiListU8Arg(
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


pub fn structFieldPayloadOffset(decl: StructDecl, field_name: []const u8) ?usize {
    var offset: usize = 0;
    for (decl.fields) |field| {
        offset = alignUp(offset, typePayloadAlignment(field.ty));
        if (std.mem.eql(u8, publicDeclName(field.name), field_name)) return offset;
        offset += typePayloadBytes(field.ty);
    }
    return null;
}


pub fn findStoragePrimitiveLocal(locals: []const StorageLocal, name: []const u8) ?StorageLocal {
    const local = findStorageLocal(locals, name) orelse return null;
    if (storageElemTypeFromName(local.ty) == null) return null;
    return local;
}


pub fn wasmType(ty: []const u8) []const u8 {
    return payload_wat.wasmType(ty);
}


pub fn valueEnumCarrier(ctx: CodegenContext, ty: []const u8) ?[]const u8 {
    const decl = findValueEnumDecl(ctx.value_enums, ty) orelse return null;
    return decl.carrier;
}


pub fn codegenScalarType(ctx: CodegenContext, ty: []const u8) []const u8 {
    return valueEnumCarrier(ctx, ty) orelse ty;
}


pub fn codegenWasmType(ctx: CodegenContext, ty: []const u8) []const u8 {
    return wasmType(codegenScalarType(ctx, ty));
}


pub fn typePayloadBytes(ty: []const u8) usize {
    return type_util.typePayloadBytes(ty);
}


pub fn typePayloadAlignment(ty: []const u8) usize {
    return type_util.typePayloadAlignment(ty);
}


pub fn isManagedPayloadType(ty: []const u8) bool {
    return type_util.isManagedPayloadType(ty);
}


pub fn isStorageTypeName(ty: []const u8) bool {
    return type_util.isStorageTypeName(ty);
}


pub fn storageElemTypeFromName(ty: []const u8) ?[]const u8 {
    return type_util.storageElemTypeFromName(ty);
}


pub fn storageElementByteWidth(elem_ty: []const u8) ?usize {
    return type_util.storageElementByteWidth(elem_ty);
}

/// Pure-scalar unmanaged struct nested pack width (declaration order + alignUp, no managed fields).
/// Pure-scalar unmanaged struct nested pack width (declaration order + alignUp, no managed fields).

pub fn tupleScalarLeafStorageByteWidth(tuple_ty: []const u8) ?usize {
    return type_util.tupleScalarLeafStorageByteWidth(tuple_ty);
}


pub fn tupleScalarLeafStorageByteWidthCtx(tuple_ty: []const u8, ctx: CodegenContext) ?usize {
    if (tuplePackWidthWithStructs(tuple_ty, ctx.structs)) |w| return w;
    return type_util.tupleScalarLeafStorageByteWidth(tuple_ty);
}


pub fn tupleHasManagedPackLeaf(tuple_ty: []const u8) bool {
    return type_util.tupleHasManagedPackLeaf(tuple_ty);
}


pub fn tupleHasManagedPackLeafWithStructs(tuple_ty: []const u8, structs: []const StructDecl) bool {
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


pub fn tupleHasManagedPackLeafCtx(tuple_ty: []const u8, ctx: CodegenContext) bool {
    if (tupleHasManagedPackLeafWithStructs(tuple_ty, ctx.structs)) return true;
    return tupleHasManagedPackLeaf(tuple_ty);
}


pub fn storageTypeIdForElement(elem_ty: []const u8, ctx: CodegenContext) usize {
    if (isTupleTypeName(elem_ty) and tupleHasManagedPackLeafCtx(elem_ty, ctx)) {
        if (findStructLayoutExact(ctx.struct_layouts, elem_ty)) |layout| {
            if (layout.is_storage_pack) return layout.type_id;
        }
    }
    if (isManagedLocalType(elem_ty, ctx) and storageElementByteWidth(elem_ty) == null and tupleScalarLeafStorageByteWidthCtx(elem_ty, ctx) == null)
        return TYPE_ID_STORAGE_MANAGED;
    return TYPE_ID_STORAGE_U8;
}


pub fn appendLoadForPayloadType(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    ty: []const u8,
) !void {
    try payload_wat.appendLoadForPayloadType(allocator, out, ty);
}


pub fn isTupleTypeName(ty: []const u8) bool {
    return type_util.isTupleTypeName(ty);
}


pub fn tupleArity(tuple_ty: []const u8) ?usize {
    return type_util.tupleArity(tuple_ty);
}


pub fn tupleElementTypeAt(tuple_ty: []const u8, idx: usize) ?[]const u8 {
    return type_util.tupleElementTypeAt(tuple_ty, idx);
}
