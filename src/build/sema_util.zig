//! Shared semantic-analysis token/name/scan helpers.
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema_error = @import("sema_error.zig");
const type_util = @import("type_name.zig");
const sema_types = @import("sema_types.zig");
const sema_scan = @import("sema_scan.zig");

const CallArgInfo = sema_types.CallArgInfo;
const CallArgShape = sema_types.CallArgShape;
const FuncParamShape = sema_types.FuncParamShape;
const FuncShape = sema_types.FuncShape;
const LocalImportPrefix = sema_types.LocalImportPrefix;
const StructFieldInfo = sema_types.StructFieldInfo;
const StructInfo = sema_types.StructInfo;


// Scan helpers (physical home: sema_scan.zig).
pub const compactTypeName = sema_scan.compactTypeName;
pub const enumDeclHasBranch = sema_scan.enumDeclHasBranch;
pub const findLineEndIdx = sema_scan.findLineEndIdx;
pub const findMatching = sema_scan.findMatching;
pub const findReturnTypeEnd = sema_scan.findReturnTypeEnd;
pub const findStructFieldTypeEnd = sema_scan.findStructFieldTypeEnd;
pub const findTopLevelAssignEqOnLine = sema_scan.findTopLevelAssignEqOnLine;
pub const isArrowAt = sema_scan.isArrowAt;
pub const isFuncDeclStart = sema_scan.isFuncDeclStart;
pub const isKeyword = sema_scan.isKeyword;
pub const isLowerIdentName = sema_scan.isLowerIdentName;
pub const isModernImportAssign = sema_scan.isModernImportAssign;
pub const isPayloadEnumDeclStart = sema_scan.isPayloadEnumDeclStart;
pub const isReadonlyIdentName = sema_scan.isReadonlyIdentName;
pub const isReturnArrowAt = sema_scan.isReturnArrowAt;
pub const isSpreadToken = sema_scan.isSpreadToken;
pub const isStructDeclStart = sema_scan.isStructDeclStart;
pub const isStructFieldName = sema_scan.isStructFieldName;
pub const isTopLevelCommaAny = sema_scan.isTopLevelCommaAny;
pub const isTopLevelDeclHead = sema_scan.isTopLevelDeclHead;
pub const isTopLevelValueDeclStart = sema_scan.isTopLevelValueDeclStart;
pub const isTypeDeclStart = sema_scan.isTypeDeclStart;
pub const isValidDeclaredTypeName = sema_scan.isValidDeclaredTypeName;
pub const normalizeStructFieldName = sema_scan.normalizeStructFieldName;
pub const publicFuncName = sema_scan.publicFuncName;
pub const publicTypeName = sema_scan.publicTypeName;
pub const simpleTypeName = sema_scan.simpleTypeName;
pub const tokEq = sema_scan.tokEq;
pub const topLevelLineAssignIdx = sema_scan.topLevelLineAssignIdx;

pub const callArgInfo = sema_scan.callArgInfo;
pub const callArityCompatibleWithFunc = sema_scan.callArityCompatibleWithFunc;
pub const callNameIdxBeforeOpen = sema_scan.callNameIdxBeforeOpen;
pub const compactTokenRangeEquals = sema_scan.compactTokenRangeEquals;
pub const containsName = sema_scan.containsName;
pub const countTypeArgs = sema_scan.countTypeArgs;
pub const enumDeclAssignIdx = sema_scan.enumDeclAssignIdx;
pub const findConstraintBlockStartBefore = sema_scan.findConstraintBlockStartBefore;
pub const findEnclosingCallOpen = sema_scan.findEnclosingCallOpen;
pub const findInlineFuncTypeInParams = sema_scan.findInlineFuncTypeInParams;
pub const findMatchingInRange = sema_scan.findMatchingInRange;
pub const findNearestValueTypeName = sema_scan.findNearestValueTypeName;
pub const findPlainEqOnLine = sema_scan.findPlainEqOnLine;
pub const findStructInfo = sema_scan.findStructInfo;
pub const findTopLevelComma = sema_scan.findTopLevelComma;
pub const firstNonGap = sema_scan.firstNonGap;
pub const funcParamTypeStart = sema_scan.funcParamTypeStart;
pub const hasKnownFuncCandidate = sema_scan.hasKnownFuncCandidate;
pub const hasLocalStructDecl = sema_scan.hasLocalStructDecl;
pub const hasReturnArrowBeforeOnLine = sema_scan.hasReturnArrowBeforeOnLine;
pub const hasTopLevelComma = sema_scan.hasTopLevelComma;
pub const hasTypeConstraintName = sema_scan.hasTypeConstraintName;
pub const isAllDigits = sema_scan.isAllDigits;
pub const isBaseIntTypeName = sema_scan.isBaseIntTypeName;
pub const isBaseTypeName = sema_scan.isBaseTypeName;
pub const isBuiltinSpecialOrCoreName = sema_scan.isBuiltinSpecialOrCoreName;
pub const isDeclOnlyName = sema_scan.isDeclOnlyName;
pub const isDeclaredTypeName = sema_scan.isDeclaredTypeName;
pub const isDotLowerIdent = sema_scan.isDotLowerIdent;
pub const isErrorEnumDeclStart = sema_scan.isErrorEnumDeclStart;
pub const isErrorTypeName = sema_scan.isErrorTypeName;
pub const isFuncTypeParam = sema_scan.isFuncTypeParam;
pub const isFuncTypeRange = sema_scan.isFuncTypeRange;
pub const isGenericTypeStart = sema_scan.isGenericTypeStart;
pub const isHostImportDeclStart = sema_scan.isHostImportDeclStart;
pub const isHostImportLine = sema_scan.isHostImportLine;
pub const isInsideStructDecl = sema_scan.isInsideStructDecl;
pub const isNonAssignEqual = sema_scan.isNonAssignEqual;
pub const isNumericCoreFuncName = sema_scan.isNumericCoreFuncName;
pub const isReservedCoreAccessName = sema_scan.isReservedCoreAccessName;
pub const isReservedFieldNameBody = sema_scan.isReservedFieldNameBody;
pub const isReservedFuncName = sema_scan.isReservedFuncName;
pub const isReservedSourceName = sema_scan.isReservedSourceName;
pub const isSnakeLowerName = sema_scan.isSnakeLowerName;
pub const isStartDeclStart = sema_scan.isStartDeclStart;
pub const isStructDeclBodyOpen = sema_scan.isStructDeclBodyOpen;
pub const isStructFieldDeclDefault = sema_scan.isStructFieldDeclDefault;
pub const isTopLevelDeclStart = sema_scan.isTopLevelDeclStart;
pub const isTopLevelToken = sema_scan.isTopLevelToken;
pub const isTypeName = sema_scan.isTypeName;
pub const isValidDepFileStem = sema_scan.isValidDepFileStem;
pub const isValidEnumBranchName = sema_scan.isValidEnumBranchName;
pub const isValidFlatFileStem = sema_scan.isValidFlatFileStem;
pub const isValidFuncDeclName = sema_scan.isValidFuncDeclName;
pub const isValidPathSeg = sema_scan.isValidPathSeg;
pub const isValueEnumDeclStart = sema_scan.isValueEnumDeclStart;
pub const isValueLiteralToken = sema_scan.isValueLiteralToken;
pub const isValueTypeName = sema_scan.isValueTypeName;
pub const isWitOnlySourceTypeName = sema_scan.isWitOnlySourceTypeName;
pub const lineStartIdx = sema_scan.lineStartIdx;
pub const markErrorAt = sema_scan.markErrorAt;
pub const stringTokenBody = sema_scan.stringTokenBody;
pub const tokenNameAppearsInRange = sema_scan.tokenNameAppearsInRange;
pub const typeConstraintIsFunctionType = sema_scan.typeConstraintIsFunctionType;
pub const validateImportFileName = sema_scan.validateImportFileName;
pub const validateImportFileNameText = sema_scan.validateImportFileNameText;
pub const validateIsTypeArgList = sema_scan.validateIsTypeArgList;
pub const validateIsTypeAtom = sema_scan.validateIsTypeAtom;
pub const validateIsTypeExpr = sema_scan.validateIsTypeExpr;
pub const validateIsTypeExprUntilComma = sema_scan.validateIsTypeExprUntilComma;

pub fn collectFuncShapes(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]FuncShape {
    var out = std.ArrayList(FuncShape).empty;
    errdefer {
        for (out.items) |shape| freeFuncParamShapes(allocator, shape.param_shapes);
        out.deinit(allocator);
    }

    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) {
        if (tokEq(tokens[i], "{")) {
            if (skipTopLevelImportBrace(tokens, i, depth_brace)) |skip_i| {
                i = skip_i + 1;
                continue;
            }
            depth_brace += 1;
            i += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            i += 1;
            continue;
        }
        if (depth_brace != 0 or !isTopLevelDeclHead(tokens, i) or !isFuncDeclStart(tokens, i)) {
            i += 1;
            continue;
        }

        const close_paren = findMatching(tokens, i + 1, "(", ")") catch {
            i += 1;
            continue;
        };
        const params = try parseFuncParamShapes(allocator, tokens, i + 2, close_paren);
        const arity = parseFuncParamArity(tokens, i + 2, close_paren);
        try out.append(allocator, .{
            .name = publicFuncName(tokens[i].lexeme),
            .start_idx = i,
            .param_shapes = params,
            .param_min = arity.param_min,
            .param_max = arity.param_max,
            .return_type = parseTopLevelFuncReturnType(tokens, close_paren + 1),
        });
        i = close_paren + 1;
    }

    const owned = try out.toOwnedSlice(allocator);
    return owned;
}


pub fn freeFuncShapes(allocator: std.mem.Allocator, funcs: []FuncShape) void {
    for (funcs) |shape| freeFuncParamShapes(allocator, shape.param_shapes);
    allocator.free(funcs);
}


pub fn freeFuncParamShapes(allocator: std.mem.Allocator, shapes: []FuncParamShape) void {
    for (shapes) |shape| {
        switch (shape) {
            .other => {},
            .value => |type_name| if (type_name) |name| allocator.free(name),
            .variadic => |type_name| if (type_name) |name| allocator.free(name),
            .func => |func_type| freeFuncTypeParamNames(allocator, func_type.param_types),
        }
    }
    allocator.free(shapes);
}


pub fn freeFuncTypeParamNames(allocator: std.mem.Allocator, param_types: []?[]const u8) void {
    for (param_types) |param_type| {
        if (param_type) |name| allocator.free(name);
    }
    allocator.free(param_types);
}


pub fn freeCallArgShapes(allocator: std.mem.Allocator, shapes: []CallArgShape) void {
    for (shapes) |shape| {
        switch (shape) {
            .other => {},
            .lambda => |lambda| allocator.free(lambda.param_types),
            .ident => {},
            .spread => {},
        }
    }
    allocator.free(shapes);
}


pub fn parseFuncParamShapes(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ![]FuncParamShape {
    var out = std.ArrayList(FuncParamShape).empty;
    errdefer out.deinit(allocator);

    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !isTopLevelCommaAny(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            try out.append(allocator, try parseFuncParamShape(allocator, tokens, seg_start, i));
        }
        seg_start = i + 1;
    }

    return out.toOwnedSlice(allocator);
}


pub fn parseFuncParamShape(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) !FuncParamShape {
    if (start_idx + 1 >= end_idx) return .other;
    const type_start = if (isSpreadToken(tokens[start_idx + 1])) start_idx + 2 else start_idx + 1;
    if (type_start >= end_idx) return .other;
    if (!tokEq(tokens[type_start], "(")) {
        const type_name = try compactTypeName(allocator, tokens, type_start, end_idx);
        if (type_start != start_idx + 1) return .{ .variadic = type_name };
        return .{ .value = type_name };
    }
    const close_param_types = findMatching(tokens, type_start, "(", ")") catch return .other;
    if (close_param_types >= end_idx) return .other;
    if (!isReturnArrowAt(tokens, close_param_types + 1)) return .other;

    const param_types = try parseTypeNameList(allocator, tokens, type_start + 1, close_param_types);
    return .{ .func = .{
        .param_count = param_types.len,
        .param_types = param_types,
        .return_type = simpleTypeName(tokens, close_param_types + 3, end_idx),
    } };
}


pub fn parseFuncParamArity(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) struct { param_min: usize, param_max: ?usize } {
    var min_count: usize = 0;
    var has_variadic = false;
    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !isTopLevelCommaAny(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            if (seg_start + 1 < i and isSpreadToken(tokens[seg_start + 1])) {
                has_variadic = true;
            } else {
                min_count += 1;
            }
        }
        seg_start = i + 1;
    }
    return .{
        .param_min = min_count,
        .param_max = if (has_variadic) null else min_count,
    };
}


pub fn parseTopLevelFuncReturnType(tokens: []const lexer.Token, start_idx: usize) ?[]const u8 {
    if (start_idx >= tokens.len) return null;
    if (tokEq(tokens[start_idx], "{") or isArrowAt(tokens, start_idx)) return null;

    if (isReturnArrowAt(tokens, start_idx)) {
        return simpleTypeName(tokens, start_idx + 2, findReturnTypeEnd(tokens, start_idx + 2));
    }

    return simpleTypeName(tokens, start_idx, findReturnTypeEnd(tokens, start_idx));
}


pub fn parseCallArgShapes(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ![]CallArgShape {
    var out = std.ArrayList(CallArgShape).empty;
    errdefer out.deinit(allocator);

    var seg_start = start_idx;
    var arg_index: usize = 0;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !isTopLevelCommaAny(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            try out.append(allocator, try parseCallArgShape(allocator, tokens, seg_start, i, arg_index));
            arg_index += 1;
        }
        seg_start = i + 1;
    }

    return out.toOwnedSlice(allocator);
}


pub fn parseCallArgShape(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    arg_index: usize,
) !CallArgShape {
    if (start_idx < end_idx and isSpreadToken(tokens[start_idx])) return .{ .spread = start_idx };

    const close_params = lambdaParamClose(tokens, start_idx, end_idx);
    if (close_params) |close_idx| {
        if (lambdaBodyStart(tokens, close_idx + 1, end_idx) != null) {
            const param_types = try parseLambdaParamTypeList(allocator, tokens, start_idx + 1, close_idx);
            return .{ .lambda = .{
                .arg_index = arg_index,
                .param_count = param_types.len,
                .param_types = param_types,
                .return_type = lambdaReturnTypeName(tokens, close_idx, end_idx),
            } };
        }
    }

    if (start_idx + 1 == end_idx and tokens[start_idx].kind == .ident) {
        return .{ .ident = tokens[start_idx].lexeme };
    }

    return .other;
}


pub fn lambdaParamClose(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (start_idx >= end_idx or !tokEq(tokens[start_idx], "(")) return null;
    const close_idx = findMatching(tokens, start_idx, "(", ")") catch return null;
    if (close_idx >= end_idx) return null;
    return close_idx;
}


pub fn lambdaReturnTypeName(tokens: []const lexer.Token, close_params_idx: usize, end_idx: usize) ?[]const u8 {
    const return_arrow_idx = close_params_idx + 1;
    if (!isReturnArrowAt(tokens, return_arrow_idx)) return null;

    const body_start = lambdaBodyStart(tokens, return_arrow_idx, end_idx) orelse return null;
    const return_end = if (body_start >= 2 and isArrowAt(tokens, body_start - 2))
        body_start - 2
    else
        body_start;
    return simpleTypeName(tokens, return_arrow_idx + 2, return_end);
}


pub fn countLambdaParams(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
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


pub fn parseTypeNameList(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ![]?[]const u8 {
    var out = std.ArrayList(?[]const u8).empty;
    errdefer {
        for (out.items) |param_type| {
            if (param_type) |name| allocator.free(name);
        }
        out.deinit(allocator);
    }

    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !isTopLevelCommaAny(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            try out.append(allocator, try compactTypeName(allocator, tokens, seg_start, i));
        }
        seg_start = i + 1;
    }

    return out.toOwnedSlice(allocator);
}


pub fn parseLambdaParamTypeList(
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


pub fn lambdaParamTypeName(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    if (start_idx + 1 >= end_idx) return null;
    return simpleTypeName(tokens, start_idx + 1, end_idx);
}


pub fn lambdaBodyStart(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (isArrowAt(tokens, start_idx)) return start_idx + 2;
    if (start_idx < end_idx and tokEq(tokens[start_idx], "{")) return start_idx;
    if (start_idx >= end_idx or !isReturnArrowAt(tokens, start_idx)) return null;

    var i = start_idx + 2;
    var depth_angle: usize = 0;
    var depth_paren: usize = 0;
    while (i < end_idx) : (i += 1) {
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


pub fn isVisibleBindingOrCallableName(tokens: []const lexer.Token, name: []const u8, before_idx: usize) bool {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (skipTopLevelImportBrace(tokens, i, depth_brace)) |skip_i| {
                i = skip_i;
                continue;
            }
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!isTopLevelDeclHead(tokens, i)) continue;
        if (i == before_idx) continue;
        if (tokens[i].kind != .ident) continue;
        if (isKeyword(tokens[i].lexeme)) continue;

        const public_name = publicFuncName(tokens[i].lexeme);
        if (!std.mem.eql(u8, public_name, name)) continue;
        if (isFuncDeclStart(tokens, i)) return true;
        if (isModernImportAssign(tokens, i)) {
            const eq_idx = topLevelLineAssignIdx(tokens, i) orelse continue;
            if (eq_idx + 2 >= tokens.len) continue;
            if (!tokEq(tokens[eq_idx + 1], "@")) continue;
            if (tokens[eq_idx + 2].kind != .ident) continue;
            const import_kind = tokens[eq_idx + 2].lexeme;
            if (std.mem.eql(u8, import_kind, "env") or
                std.mem.eql(u8, import_kind, "wasi_func")) return true;
            if (std.mem.eql(u8, import_kind, "lib") and (isLowerIdentName(public_name) or isReadonlyIdentName(tokens[i].lexeme))) return true;
            continue;
        }
        if (isTopLevelValueDeclStart(tokens, i)) return true;
    }
    return false;
}


pub fn parseImportDeclEnd(tokens: []const lexer.Token, start_idx: usize) ?usize {
    const eq_idx = topLevelLineAssignIdx(tokens, start_idx) orelse return null;
    const at_idx = eq_idx + 1;
    if (at_idx + 2 >= tokens.len or !tokEq(tokens[at_idx], "@")) return null;
    if (tokens[at_idx + 1].kind != .ident) return null;
    if (!tokEq(tokens[at_idx + 2], "(")) return null;
    const close_paren = findMatching(tokens, at_idx + 2, "(", ")") catch return null;
    return close_paren + 1;
}


fn findTokenInRange(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, lexeme: []const u8) ?usize {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEq(tokens[i], lexeme)) return i;
    }
    return null;
}

/// When scanning top-level decls and hitting `{`, skip a whole import decl if present.
/// Returns the loop index to assign before `continue` (`next_idx - 1`), else null.
pub fn skipTopLevelImportBrace(tokens: []const lexer.Token, i: usize, depth_brace: usize) ?usize {
    if (depth_brace != 0) return null;
    const next_idx = parseImportDeclEnd(tokens, i) orelse return null;
    return next_idx - 1;
}


pub fn isLocalPayloadEnumCase(tokens: []const lexer.Token, name: []const u8) bool {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (skipTopLevelImportBrace(tokens, i, depth_brace)) |skip_i| {
                i = skip_i;
                continue;
            }
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!isTopLevelDeclHead(tokens, i)) continue;
        if (tokens[i].kind != .ident) continue;
        if (isModernImportAssign(tokens, i)) continue;
        if (!isPayloadEnumDeclStart(tokens, i)) continue;
        if (enumDeclHasBranch(tokens, i, name)) return true;
    }
    return false;
}


pub fn isImportedUpperAlias(tokens: []const lexer.Token, name: []const u8) bool {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (skipTopLevelImportBrace(tokens, i, depth_brace)) |skip_i| {
                i = skip_i;
                continue;
            }
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!isTopLevelDeclHead(tokens, i)) continue;
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, tokens[i].lexeme, name)) continue;
        if (!isValidDeclaredTypeName(tokens[i].lexeme)) continue;
        if (isModernImportAssign(tokens, i)) return true;
    }
    return false;
}


pub fn collectStructInfos(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]StructInfo {
    var out = std.ArrayList(StructInfo).empty;
    errdefer freeStructInfos(allocator, out.items);

    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (skipTopLevelImportBrace(tokens, i, depth_brace)) |skip_i| {
                i = skip_i;
                continue;
            }
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!isTopLevelDeclHead(tokens, i)) continue;
        if (!isTypeDeclStart(tokens, i)) continue;

        // Declarative: Name = @wasi_resource|wasi_record("…", { fields })
        if (i + 5 < tokens.len and tokEq(tokens[i + 1], "=") and tokEq(tokens[i + 2], "@") and
            tokens[i + 3].kind == .ident and
            (std.mem.eql(u8, tokens[i + 3].lexeme, "wasi_resource") or
                std.mem.eql(u8, tokens[i + 3].lexeme, "wasi_record")) and
            tokEq(tokens[i + 4], "("))
        {
            const close_call = findMatching(tokens, i + 4, "(", ")") catch continue;
            const open_brace = findTokenInRange(tokens, i + 5, close_call, "{") orelse continue;
            const close_brace = findMatching(tokens, open_brace, "{", "}") catch continue;
            try out.append(allocator, .{
                .name = publicTypeName(tokens[i].lexeme),
                .fields = try collectStructFieldInfos(allocator, tokens, open_brace + 1, close_brace),
            });
            i = close_call;
            continue;
        }

        // Classic: Name { fields }
        if (i + 1 >= tokens.len or !tokEq(tokens[i + 1], "{")) continue;

        const close_idx = findMatching(tokens, i + 1, "{", "}") catch continue;
        try out.append(allocator, .{
            .name = publicTypeName(tokens[i].lexeme),
            .fields = try collectStructFieldInfos(allocator, tokens, i + 2, close_idx),
        });
        i = close_idx;
    }

    return out.toOwnedSlice(allocator);
}


pub fn collectStructFieldInfos(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ![]StructFieldInfo {
    var out = std.ArrayList(StructFieldInfo).empty;
    errdefer {
        for (out.items) |field| {
            if (field.ty) |ty| allocator.free(ty);
        }
        out.deinit(allocator);
    }

    var i = start_idx;
    while (i < end_idx) {
        // Clamp to brace end so single-line `{ .id i64 }` does not pull `}` into the type span.
        const line_end = @min(findLineEndIdx(tokens, i), end_idx);
        if (tokens[i].kind == .ident and isStructFieldName(tokens[i].lexeme)) {
            const type_end = findStructFieldTypeEnd(tokens, i + 1, line_end);
            {
                const ty = try compactTypeName(allocator, tokens, i + 1, type_end);
                errdefer if (ty) |owned| allocator.free(owned);
                try out.append(allocator, .{
                    .name = normalizeStructFieldName(tokens[i].lexeme),
                    .ty = ty,
                    .has_default = findTopLevelAssignEqOnLine(tokens, i, line_end) != null,
                });
            }
        }
        i = line_end;
    }

    return out.toOwnedSlice(allocator);
}


pub fn freeStructInfos(allocator: std.mem.Allocator, structs: []StructInfo) void {
    for (structs) |info| {
        for (info.fields) |field| {
            if (field.ty) |ty| allocator.free(ty);
        }
        allocator.free(info.fields);
    }
    allocator.free(structs);
}


pub fn localStructTypeParamCount(tokens: []const lexer.Token, name: []const u8) ?usize {
    var depth_brace: usize = 0;
    var in_constraint_block = false;
    var type_constraint_count: usize = 0;
    var last_constraint_line: usize = 0;

    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (skipTopLevelImportBrace(tokens, i, depth_brace)) |skip_i| {
                i = skip_i;
                continue;
            }
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;

        if (!tokEq(tokens[i], "#")) {
            const is_target_struct = tokens[i].kind == .ident and isStructDeclStart(tokens, i) and
                std.mem.eql(u8, publicTypeName(tokens[i].lexeme), name);
            if (is_target_struct and in_constraint_block and tokens[i].line == last_constraint_line + 1 and type_constraint_count > 0) {
                return type_constraint_count;
            }
            if (is_target_struct) return 0;
            if (in_constraint_block) {
                in_constraint_block = false;
                type_constraint_count = 0;
            }
            continue;
        }

        const line_end = findLineEndIdx(tokens, i);
        const is_func_constraint = (i + 2 < line_end and tokEq(tokens[i + 2], "("));
        if (!is_func_constraint) type_constraint_count += 1;
        in_constraint_block = true;
        last_constraint_line = tokens[i].line;
        i = line_end - 1;
    }
    return null;
}


pub fn hasConcreteTypeName(tokens: []const lexer.Token, name: []const u8) bool {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (skipTopLevelImportBrace(tokens, i, depth_brace)) |skip_i| {
                i = skip_i;
                continue;
            }
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!isTopLevelDeclHead(tokens, i)) continue;
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, publicTypeName(tokens[i].lexeme), name)) continue;
        if (isModernImportAssign(tokens, i)) return true;
        if (isTypeDeclStart(tokens, i)) return true;
    }
    return false;
}


