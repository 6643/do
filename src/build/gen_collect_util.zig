//! Collect shared pure helpers (extracted from gen_collect).
//! Declaration / layout collection for codegen (no emit).
const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const test_runner = @import("test_runner.zig");
const type_util = @import("type_name.zig");
const gen_util = @import("gen_util.zig");
const gen_types = @import("gen_types.zig");
const gen_union = @import("codegen_union_layout.zig");
const gen_import = @import("gen_import.zig");
const gen_wasi = @import("codegen_wasi_registry.zig");

const alignUp = gen_util.alignUp;
const appendFmt = gen_util.appendFmt;
const appendMangledTypeName = gen_util.appendMangledTypeName;
const compactTokenText = gen_util.compactTokenText;
const findArgEnd = gen_util.findArgEnd;
const findLineEnd = gen_util.findLineEnd;
const findLineStart = gen_util.findLineStart;
const findMatching = gen_util.findMatching;
const findMatchingInRange = gen_util.findMatchingInRange;
const findToken = gen_util.findToken;
const findTopLevelToken = gen_util.findTopLevelToken;
const isBaseIntTypeName = gen_util.isBaseIntTypeName;
const isCoreWasmScalar = gen_util.isCoreWasmScalar;
const isErrorTypeName = gen_util.isErrorTypeName;
const isLineStart = gen_util.isLineStart;
const isPublicTypeName = gen_util.isPublicTypeName;
const isUserFuncDeclStart = gen_util.isUserFuncDeclStart;
const moduleScopedSymbolName = gen_util.moduleScopedSymbolName;
const moduleTokensEqual = gen_util.moduleTokensEqual;
const publicDeclName = gen_util.publicDeclName;
const stringTokenBody = gen_util.stringTokenBody;
const tokEq = gen_util.tokEq;
const freeUnionLayout = gen_union.freeUnionLayout;
const findLocalOrigin = gen_types.findLocalOrigin;
const findTopLevelTypeSeparator = gen_util.findTopLevelTypeSeparator;
const findTypeArgEnd = gen_util.findTypeArgEnd;
const trimParens = gen_util.trimParens;
const findTopLevelTypeSeparatorFrom = gen_util.findTopLevelTypeSeparatorFrom;
const Range = gen_util.Range;

const freeStructDecl = gen_types.freeStructDecl;
const freeStructDecls = gen_types.freeStructDecls;

const GenericTypeArgsRange = type_util.GenericTypeArgsRange;

const TokenRange = struct {
    tokens: []const lexer.Token,
    start: usize,
    end: usize,
};

const findCodegenImportByAlias = gen_import.findCodegenImportByAlias;
const collectStartBodyCalls = gen_import.collectStartBodyCalls;
const collectTestBodyCalls = gen_import.collectTestBodyCalls;
const collectAllFunctionBodyCalls = gen_import.collectAllFunctionBodyCalls;
const collectFunctionBodyCalls = gen_import.collectFunctionBodyCalls;
const findImportedModuleIndex = gen_import.findImportedModuleIndex;
const findPayloadEnumDecl = gen_import.findPayloadEnumDecl;
const findRootModuleIndex = gen_import.findRootModuleIndex;
const findValueEnumDecl = gen_import.findValueEnumDecl;
const findValueEnumDeclLineByBranch = gen_import.findValueEnumDeclLineByBranch;
const findValueEnumDeclLineByName = gen_import.findValueEnumDeclLineByName;
const hasReachVisit = gen_import.hasReachVisit;
const importedAliasContextForTokens = gen_import.importedAliasContextForTokens;
const isPayloadEnumDeclStart = gen_import.isPayloadEnumDeclStart;
const isValueEnumDeclStart = gen_import.isValueEnumDeclStart;
const parseCodegenImport = gen_import.parseCodegenImport;

const isManagedPayloadType = type_util.isManagedPayloadType;
const isTupleTypeName = type_util.isTupleTypeName;
const isTuplePackableLeafType = type_util.isTuplePackableLeafType;
const managedPayloadElemTypeFromName = type_util.managedPayloadElemTypeFromName;
const tupleArity = type_util.tupleArity;
const tupleElementTypeAt = type_util.tupleElementTypeAt;
const tupleScalarLeafStorageByteWidth = type_util.tupleScalarLeafStorageByteWidth;
const typeBaseName = type_util.typeBaseName;
const typePayloadAlignment = type_util.typePayloadAlignment;
const typePayloadBytes = type_util.typePayloadBytes;

const CallbackBinding = gen_types.CallbackBinding;
const CallbackBindingKind = gen_types.CallbackBindingKind;
const CodegenContext = gen_types.CodegenContext;
const CodegenError = gen_types.CodegenError;
const CodegenImportPrefix = gen_types.CodegenImportPrefix;
const CodegenImportRef = gen_types.CodegenImportRef;
const FuncBodyShape = gen_types.FuncBodyShape;
const FuncDecl = gen_types.FuncDecl;
const FuncParam = gen_types.FuncParam;
const FuncResultItem = gen_types.FuncResultItem;
const FuncResultParse = gen_types.FuncResultParse;
const FuncTypeShape = gen_types.FuncTypeShape;
const GenericTypeBinding = gen_types.GenericTypeBinding;
const HostImport = gen_types.HostImport;
const ImportedAliasContext = gen_types.ImportedAliasContext;
const LambdaExprShape = gen_types.LambdaExprShape;
const LocalSet = gen_types.LocalSet;
const ManagedFieldOffset = gen_types.ManagedFieldOffset;
const NO_RESULT_ITEMS = gen_types.NO_RESULT_ITEMS;
const OwnedFuncTypeShape = gen_types.OwnedFuncTypeShape;
const ParsedCodegenType = gen_types.ParsedCodegenType;
const PayloadEnumCase = gen_types.PayloadEnumCase;
const PayloadEnumDecl = gen_types.PayloadEnumDecl;
const ReachVisit = gen_types.ReachVisit;
const StructDecl = gen_types.StructDecl;
const StructErrorResult = gen_types.StructErrorResult;
const StructField = gen_types.StructField;
const StructLayout = gen_types.StructLayout;
const TYPE_ID_FIRST_STRUCT = gen_types.TYPE_ID_FIRST_STRUCT;
const ValueEnumBranch = gen_types.ValueEnumBranch;
const ValueEnumDecl = gen_types.ValueEnumDecl;
const storageTypeNameForElem = gen_types.storageTypeNameForElem;
const TYPE_ID_STORAGE_MANAGED = gen_types.TYPE_ID_STORAGE_MANAGED;
const TYPE_ID_STORAGE_U8 = gen_types.TYPE_ID_STORAGE_U8;

const UnionBranch = gen_union.UnionBranch;
const UnionLayout = gen_union.UnionLayout;

const WasiHostImport = gen_wasi.WasiHostImport;



pub fn parseCodegenTypeExpr(
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


pub fn bindGenericType(
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


pub fn findGenericBinding(bindings: []const GenericTypeBinding, name: []const u8) ?GenericTypeBinding {
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.name, name)) return binding;
    }
    return null;
}


pub fn substituteGenericTypeOwned(
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


pub fn typeContainsGenericBinding(ty: []const u8, bindings: []const GenericTypeBinding) bool {
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


pub fn isTypeIdentStart(ch: u8) bool {
    return ch == '_' or (ch >= 'A' and ch <= 'Z') or (ch >= 'a' and ch <= 'z');
}


pub fn isTypeIdentPart(ch: u8) bool {
    return isTypeIdentStart(ch) or (ch >= '0' and ch <= '9');
}


pub fn genericTypeArgsRange(ty: []const u8) ?GenericTypeArgsRange {
    return type_util.genericTypeArgsRange(ty);
}


pub fn parseFuncBodyShape(tokens: []const lexer.Token, close_params: usize) !FuncBodyShape {
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


pub fn parseGenericInlineUnionLayout(
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
            branch_start = branch_end;
            if (branch_start < end_idx and tokEq(tokens[branch_start], "|")) branch_start += 1;
            continue;
        }
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


pub fn hasTypeParamName(type_params: []const []const u8, name: []const u8) bool {
    for (type_params) |type_param| {
        if (std.mem.eql(u8, type_param, name)) return true;
    }
    return false;
}


pub fn parseStructErrorResultType(
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


pub fn parseUnionTypeLayout(
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


pub fn unionTypeExprRange(
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


pub fn localUnionAliasRange(tokens: []const lexer.Token, name: []const u8) ?Range {
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


pub fn importedUnionAliasRange(
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


pub fn appendUnionBranchPayloadTypes(
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
    // Tuple-in-union: flatten leaf ABI slots (e.g. Tuple<[u8],bool> → [u8], bool).
    if (isTupleTypeName(ty)) {
        try appendTupleLeafTypesWithStructs(allocator, ty, structs, out);
        return;
    }
    if (isCoreWasmScalar(ty) or isErrorLikeType(tokens, ty) or managedPayloadElemTypeFromName(ty) != null or findStructLayout(struct_layouts, ty) != null) {
        try out.append(allocator, ty);
        return;
    }
    return error.NoMatchingCall;
}


pub fn hasTopLevelToken(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, lexeme: []const u8) bool {
    return findTopLevelToken(tokens, start_idx, end_idx, lexeme) != null;
}


pub fn isUnmanagedScalarStruct(
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


pub fn isErrorLikeType(tokens: []const lexer.Token, name: []const u8) bool {
    return isErrorEnumType(tokens, name) or errorNilAliasTarget(tokens, name) != null or std.mem.endsWith(u8, name, "Error");
}


pub fn isErrorEnumType(tokens: []const lexer.Token, name: []const u8) bool {
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


pub fn errorNilAliasTarget(tokens: []const lexer.Token, name: []const u8) ?[]const u8 {
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


pub fn isErrorEnumTypeNameForLowering(tokens: []const lexer.Token, name: []const u8) bool {
    return isErrorEnumType(tokens, name) or std.mem.endsWith(u8, name, "Error");
}


pub fn funcParamAbiType(param: FuncParam) []const u8 {
    if (param.abi_ty) |abi_ty| return abi_ty;
    if (!param.variadic) return param.ty;
    return storageTypeNameForElem(param.ty) orelse param.ty;
}


pub fn findStructDecl(structs: []const StructDecl, name: []const u8) ?StructDecl {
    const lookup_name = typeBaseName(name);
    for (structs) |decl| {
        if (std.mem.eql(u8, decl.name, lookup_name)) return decl;
    }
    return null;
}


pub fn findStructLayout(layouts: []const StructLayout, name: []const u8) ?StructLayout {
    for (layouts) |layout| {
        if (std.mem.eql(u8, layout.name, name)) return layout;
    }
    const lookup_name = typeBaseName(name);
    for (layouts) |layout| {
        if (std.mem.eql(u8, layout.name, lookup_name)) return layout;
    }
    return null;
}


pub fn isTopLevelStructDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (!isLineStart(tokens, idx)) return false;
    if (tokens[idx].kind != .ident) return false;
    if (std.mem.eql(u8, tokens[idx].lexeme, "start")) return false;
    return tokEq(tokens[idx + 1], "{");
}


pub fn pureScalarStructPackWidth(decl: StructDecl, structs: []const StructDecl) ?usize {
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
/// True when a named struct carries managed payload (directly or nested) and lowers as ARC handle.


pub fn structDeclHasManagedField(decl: StructDecl, structs: []const StructDecl) bool {
    for (decl.fields) |field| {
        if (type_util.isManagedPayloadType(field.ty)) return true;
        if (findStructDecl(structs, field.ty)) |nested| {
            if (structDeclHasManagedField(nested, structs)) return true;
        }
    }
    return false;
}

/// Terminal pack leaf that is a managed object handle (text / [T] / managed struct).
/// Terminal pack leaf that is a managed object handle (text / [T] / managed struct).


pub fn packSlotWidth(ty: []const u8, structs: []const StructDecl) ?usize {
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
/// Scheme A element width: scalar, managed handle, nested Tuple, pure-scalar struct sub-layout,
/// or managed-struct handle slot (never type-flatten).


pub fn tuplePackWidthWithStructs(tuple_ty: []const u8, structs: []const StructDecl) ?usize {
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


pub fn appendTupleLeafTypesWithStructs(
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
/// Scheme A: packed Tuple storage layout (scalar + managed + struct nested slots).


pub fn appendTupleLeafTypes(
    allocator: std.mem.Allocator,
    tuple_ty: []const u8,
    out: *std.ArrayList([]const u8),
) CodegenError!void {
    // Malformed Tuple type names are a lowering invariant failure, not overload miss.
    type_util.appendTupleLeafTypes(allocator, tuple_ty, out) catch return error.UnsupportedLowering;
}

// pack leaf helpers (shared with storage layout collect)



pub fn parseInlineUnionLayout(
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



