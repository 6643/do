//! Sema func domain — sig (extracted from sema_func).
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema_error = @import("sema_error.zig");
const type_util = @import("type_name.zig");
const sema_util = @import("sema_util.zig");
const sema_types = @import("sema_types.zig");
const sema_func_shared = @import("sema_func_shared.zig");
const SigTypeParamPair = sema_types.SigTypeParamPair;
const findInlineFuncTypeInIsArg = sema_func_shared.findInlineFuncTypeInIsArg;
const findTopLevelNilInIsArg = sema_func_shared.findTopLevelNilInIsArg;
const freeResolvedFuncTypeShape = sema_func_shared.freeResolvedFuncTypeShape;
const resolveFuncParamTypeShape = sema_func_shared.resolveFuncParamTypeShape;
const typeConstraintIsConcreteFunctionType = sema_func_shared.typeConstraintIsConcreteFunctionType;

const collectFuncShapes = sema_util.collectFuncShapes;
const containsName = sema_util.containsName;
const findConstraintBlockStartBefore = sema_util.findConstraintBlockStartBefore;
const findInlineFuncTypeInParams = sema_util.findInlineFuncTypeInParams;
const findLineEndIdx = sema_util.findLineEndIdx;
const findMatching = sema_util.findMatching;
const findTopLevelAssignEqOnLine = sema_util.findTopLevelAssignEqOnLine;
const freeFuncShapes = sema_util.freeFuncShapes;
const isArrowAt = sema_util.isArrowAt;
const isErrorEnumDeclStart = sema_util.isErrorEnumDeclStart;
const isFuncDeclStart = sema_util.isFuncDeclStart;
const isFuncTypeParam = sema_util.isFuncTypeParam;
const isFuncTypeRange = sema_util.isFuncTypeRange;
const isKeyword = sema_util.isKeyword;
const isLowerIdentName = sema_util.isLowerIdentName;
const isModernImportAssign = sema_util.isModernImportAssign;
const isPayloadEnumDeclStart = sema_util.isPayloadEnumDeclStart;
const isReservedFuncName = sema_util.isReservedFuncName;
const isReturnArrowAt = sema_util.isReturnArrowAt;
const isSpreadToken = sema_util.isSpreadToken;
const isStartDeclStart = sema_util.isStartDeclStart;
const isStructFieldDeclDefault = sema_util.isStructFieldDeclDefault;
const isTopLevelCommaAny = sema_util.isTopLevelCommaAny;
const isTopLevelDeclHead = sema_util.isTopLevelDeclHead;
const isTypeDeclStart = sema_util.isTypeDeclStart;
const isValidDeclaredTypeName = sema_util.isValidDeclaredTypeName;
const isValidFuncDeclName = sema_util.isValidFuncDeclName;
const isValueEnumDeclStart = sema_util.isValueEnumDeclStart;
const isVisibleBindingOrCallableName = sema_util.isVisibleBindingOrCallableName;
const isWitOnlySourceTypeName = sema_util.isWitOnlySourceTypeName;
const markErrorAt = sema_util.markErrorAt;
const parseImportDeclEnd = sema_util.parseImportDeclEnd;
const skipTopLevelImportBrace = sema_util.skipTopLevelImportBrace;
const publicTypeName = sema_util.publicTypeName;
const tokEq = sema_util.tokEq;
const validateIsTypeExpr = sema_util.validateIsTypeExpr;
const FuncParamShape = sema_types.FuncParamShape;
const FuncShape = sema_types.FuncShape;
const FuncTypeShape = sema_types.FuncTypeShape;

pub fn checkPrivateLValueAssign(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) {
        const line_start = i;
        const line_end = findLineEndIdx(tokens, line_start);
        defer i = line_end;

        const t = tokens[line_start];
        if (t.kind != .ident) continue;
        if (t.lexeme.len < 2 or t.lexeme[0] != '.') continue;
        const eq_idx = findTopLevelAssignEqOnLine(tokens, line_start, line_end) orelse continue;
        if (isModernImportAssign(tokens, line_start)) continue;
        if (isTopLevelDeclHead(tokens, line_start) and isTypeDeclStart(tokens, line_start)) continue;
        if (isPrivateTopValueDeclStart(tokens, line_start, eq_idx)) continue;
        if (isStructFieldDeclDefault(tokens, line_start, eq_idx)) continue;
        return markErrorAt(tokens, line_start, error.PrivateIdentCannotBeLValue);
    }
}



pub fn isPrivateTopValueDeclStart(tokens: []const lexer.Token, idx: usize, eq_idx: usize) bool {
    if (!isTopLevelDeclHead(tokens, idx)) return false;
    if (eq_idx <= idx + 1) return false;
    if (tokens[idx].kind != .ident) return false;
    const name = tokens[idx].lexeme;
    return name.len > 1 and name[0] == '.' and isLowerIdentName(name[1..]) and !isReservedFuncName(name[1..]);
}



pub fn checkFuncDeclNaming(tokens: []const lexer.Token) !void {
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

        const t = tokens[i];
        if (t.kind != .ident) continue;
        if (!isTopLevelDeclHead(tokens, i)) continue;
        if (i + 1 >= tokens.len or !tokEq(tokens[i + 1], "(")) continue;
        if (!isValidFuncDeclName(t.lexeme)) {
            return markErrorAt(tokens, i, error.InvalidFuncDeclName);
        }
        if (std.mem.eql(u8, t.lexeme, "start")) continue;
        if (!isReservedFuncName(t.lexeme)) continue;
        return markErrorAt(tokens, i, error.InvalidFuncDeclName);
    }
}



pub fn checkFuncParamNames(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
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

        const t = tokens[i];
        if (t.kind != .ident) continue;
        if (!isTopLevelDeclHead(tokens, i)) continue;
        if (isKeyword(t.lexeme)) continue;
        if (isModernImportAssign(tokens, i)) continue;
        if (i + 1 >= tokens.len or !tokEq(tokens[i + 1], "(")) continue;

        const close_paren = findMatching(tokens, i + 1, "(", ")") catch return markErrorAt(tokens, i + 1, error.InvalidParamName);
        try validateFuncParamNames(allocator, tokens, i + 2, close_paren);
        i = close_paren;
    }
}



pub fn validateFuncParamNames(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize) !void {
    var expect_name = true;
    var saw_variadic = false;
    var expect_variadic_type = false;
    var seen = std.ArrayListUnmanaged([]const u8).empty;
    var depth_angle: usize = 0;
    var depth_paren: usize = 0;
    defer seen.deinit(allocator);

    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (!expect_name) {
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
            if (depth_angle == 0 and depth_paren == 0 and tokEq(tokens[i], ",")) {
                expect_name = true;
                expect_variadic_type = false;
            }
            continue;
        }

        if (expect_variadic_type) {
            if (tokens[i].kind != .ident) return markErrorAt(tokens, i, error.InvalidParamName);
            if (!isValidFuncParamTypeName(tokens[i].lexeme)) return markErrorAt(tokens, i, error.InvalidParamName);
            expect_name = false;
            expect_variadic_type = false;
            continue;
        }

        if (tokens[i].kind != .ident) return markErrorAt(tokens, i, error.InvalidParamName);
        if (isSpreadToken(tokens[i])) {
            if (saw_variadic) return markErrorAt(tokens, i, error.InvalidParamName);
            saw_variadic = true;
            expect_name = false;
            expect_variadic_type = true;
            continue;
        }
        const name = tokens[i].lexeme;
        if (!isValidFuncParamName(name)) return markErrorAt(tokens, i, error.InvalidParamName);
        if (containsName(seen.items, name)) return markErrorAt(tokens, i, error.InvalidParamName);
        if (isVisibleBindingOrCallableName(tokens, name, start_idx)) return markErrorAt(tokens, i, error.InvalidParamName);
        try seen.append(allocator, name);
        expect_name = false;
    }
}



pub fn checkInlineFuncParamTypes(tokens: []const lexer.Token) !void {
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
        if (!isFuncDeclStart(tokens, i)) continue;

        const close_paren = findMatching(tokens, i + 1, "(", ")") catch
            return markErrorAt(tokens, i, error.InvalidFuncDeclName);
        if (findInlineFuncTypeInParams(tokens, i + 2, close_paren)) |type_start| {
            return markErrorAt(tokens, type_start, error.InvalidFuncDeclName);
        }
        i = close_paren;
    }
}



pub fn checkFuncParamTypeRestrictions(tokens: []const lexer.Token) !void {
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
        if (!isFuncDeclStart(tokens, i)) continue;

        const close_paren = findMatching(tokens, i + 1, "(", ")") catch
            return markErrorAt(tokens, i + 1, error.InvalidParamName);
        try checkParamTypeRange(tokens, i, i + 2, close_paren);
        i = close_paren;
    }
}



pub fn checkSynthErrorFuncParamTypes(tokens: []const lexer.Token) !void {
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
        if (!isFuncDeclStart(tokens, i)) continue;

        const close_paren = findMatching(tokens, i + 1, "(", ")") catch
            return markErrorAt(tokens, i + 1, error.InvalidParamName);
        if (findSynthErrorParamType(tokens, i + 2, close_paren)) |bad_idx| {
            return markErrorAt(tokens, bad_idx, error.InvalidSynthErrorType);
        }
        i = close_paren;
    }
}



pub fn findSynthErrorParamType(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !isTopLevelCommaAny(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            const type_start = if (seg_start + 1 < i and isSpreadToken(tokens[seg_start + 1])) seg_start + 2 else seg_start + 1;
            if (findTopLevelTypeName(tokens, type_start, i, "Error")) |bad_idx| return bad_idx;
        }
        seg_start = i + 1;
    }
    return null;
}



pub fn findTopLevelTypeName(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    name: []const u8,
) ?usize {
    var depth_paren: usize = 0;
    var depth_bracket: usize = 0;
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
        if (tokEq(tokens[i], "[")) {
            depth_bracket += 1;
            continue;
        }
        if (tokEq(tokens[i], "]")) {
            if (depth_bracket > 0) depth_bracket -= 1;
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
        if (depth_paren != 0 or depth_bracket != 0 or depth_angle != 0) continue;
        if (tokens[i].kind == .ident and std.mem.eql(u8, tokens[i].lexeme, name)) return i;
    }
    return null;
}



pub fn checkParamTypeRange(tokens: []const lexer.Token, func_start_idx: usize, start_idx: usize, end_idx: usize) !void {
    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !isTopLevelCommaAny(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) try checkOneParamType(tokens, func_start_idx, seg_start, i);
        seg_start = i + 1;
    }
}



pub fn checkOneParamType(tokens: []const lexer.Token, func_start_idx: usize, start_idx: usize, end_idx: usize) !void {
    if (start_idx + 1 >= end_idx) return markErrorAt(tokens, start_idx, error.InvalidParamName);
    const type_start = if (isSpreadToken(tokens[start_idx + 1])) start_idx + 2 else start_idx + 1;
    const is_variadic = type_start != start_idx + 1;
    if (type_start >= end_idx) return markErrorAt(tokens, start_idx + 1, error.InvalidParamName);
    if (findInlineFuncTypeInIsArg(tokens, type_start, end_idx)) |func_type_idx| {
        return markErrorAt(tokens, func_type_idx, error.InvalidTypeRef);
    }
    if (validateIsTypeExpr(tokens, type_start, end_idx) != end_idx) {
        return markErrorAt(tokens, type_start, error.InvalidTypeRef);
    }
    if (is_variadic) {
        if (findTopLevelPipe(tokens, type_start, end_idx)) |pipe_idx| {
            return markErrorAt(tokens, pipe_idx, error.InvalidTypeRef);
        }
    }
    if (findTopLevelPipe(tokens, type_start, end_idx)) |_| {
        if (findTopLevelNilInIsArg(tokens, type_start, end_idx)) |nil_idx| {
            if (nil_idx + 1 != end_idx) return markErrorAt(tokens, nil_idx, error.InvalidTypeRef);
        }
        if (findFuncTypeConstraintBranchInParam(tokens, func_start_idx, type_start, end_idx)) |bad_idx| {
            return markErrorAt(tokens, bad_idx, error.InvalidTypeRef);
        }
    }
    if (tokEq(tokens[type_start], "nil")) {
        return markErrorAt(tokens, type_start, error.InvalidTypeRef);
    }
    if (tokens[type_start].kind == .ident and isWitOnlySourceTypeName(tokens[type_start].lexeme)) {
        return markErrorAt(tokens, type_start, error.InvalidTypeRef);
    }
    if (directParamTypeName(tokens, type_start, end_idx)) |name| {
        if (isLocalUnionAlias(tokens, name)) return markErrorAt(tokens, type_start, error.InvalidTypeRef);
    }
}



pub fn directParamTypeName(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    if (start_idx + 1 != end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (!isValidDeclaredTypeName(tokens[start_idx].lexeme)) return null;
    return publicTypeName(tokens[start_idx].lexeme);
}



pub fn findTopLevelPipe(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var depth_paren: usize = 0;
    var depth_bracket: usize = 0;
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
        if (tokEq(tokens[i], "[")) {
            depth_bracket += 1;
            continue;
        }
        if (tokEq(tokens[i], "]")) {
            if (depth_bracket > 0) depth_bracket -= 1;
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
        if (depth_paren == 0 and depth_bracket == 0 and depth_angle == 0 and tokEq(tokens[i], "|")) return i;
    }
    return null;
}



pub fn findFuncTypeConstraintBranchInParam(
    tokens: []const lexer.Token,
    func_start_idx: usize,
    start_idx: usize,
    end_idx: usize,
) ?usize {
    const block_start = findConstraintBlockStartBefore(tokens, func_start_idx) orelse return null;
    var branch_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !isTopLevelTypePipe(tokens, i, start_idx, end_idx)) continue;
        if (directParamTypeName(tokens, branch_start, i)) |name| {
            if (typeConstraintIsFunctionTypeInBlock(tokens, block_start, func_start_idx, name)) return branch_start;
        }
        branch_start = i + 1;
    }
    return null;
}



pub fn isTopLevelTypePipe(tokens: []const lexer.Token, idx: usize, start_idx: usize, end_idx: usize) bool {
    if (!tokEq(tokens[idx], "|")) return false;

    var depth_paren: usize = 0;
    var depth_bracket: usize = 0;
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
        if (tokEq(tokens[i], "[")) {
            depth_bracket += 1;
            continue;
        }
        if (tokEq(tokens[i], "]")) {
            if (depth_bracket > 0) depth_bracket -= 1;
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
    return depth_paren == 0 and depth_bracket == 0 and depth_angle == 0;
}



pub fn typeConstraintIsFunctionTypeInBlock(
    tokens: []const lexer.Token,
    block_start: usize,
    func_start_idx: usize,
    constraint_name: []const u8,
) bool {
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

        const eq_idx = findTopLevelAssignEqOnLine(tokens, i + 2, line_end) orelse return false;
        return isFuncTypeRange(tokens, eq_idx + 1, line_end);
    }
    return false;
}



pub fn checkFuncReturnArrowSyntax(tokens: []const lexer.Token) !void {
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
        if (!isFuncDeclStart(tokens, i) and !isStartDeclStart(tokens, i)) continue;

        const close_paren = findMatching(tokens, i + 1, "(", ")") catch continue;
        const next_idx = close_paren + 1;
        if (next_idx >= tokens.len) continue;
        if (tokEq(tokens[next_idx], "{") or isArrowAt(tokens, next_idx) or isReturnArrowAt(tokens, next_idx)) continue;
        return markErrorAt(tokens, i, error.InvalidFuncDeclName);
    }
}



pub fn checkStartDeclSyntax(tokens: []const lexer.Token) !void {
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
        if (!isTopLevelDeclHead(tokens, i)) continue;
        if (!isStartDeclStart(tokens, i)) continue;

        const close_paren = findMatching(tokens, i + 1, "(", ")") catch
            return markErrorAt(tokens, i, error.InvalidStartEntrySig);
        if (close_paren != i + 2) return markErrorAt(tokens, i, error.InvalidStartEntrySig);
        if (close_paren + 1 >= tokens.len or !tokEq(tokens[close_paren + 1], "{")) {
            return markErrorAt(tokens, i, error.InvalidStartEntrySig);
        }
    }
}



pub fn checkFuncSignatureConflicts(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
    const funcs = try collectFuncShapes(allocator, tokens);
    defer freeFuncShapes(allocator, funcs);

    for (funcs, 0..) |func, idx| {
        for (funcs[idx + 1 ..]) |next| {
            if (!std.mem.eql(u8, func.name, next.name)) continue;
            if (!(try funcParamShapesEqual(allocator, tokens, func, next))) continue;
            return markErrorAt(tokens, next.start_idx, error.DuplicateFuncSignature);
        }
    }

    for (funcs, 0..) |func, idx| {
        for (funcs[idx + 1 ..]) |next| {
            if (!std.mem.eql(u8, func.name, next.name)) continue;
            if (func.param_shapes.len != next.param_shapes.len) continue;
            const func_is_generic = funcHasGenericSignatureParam(tokens, func);
            const next_is_generic = funcHasGenericSignatureParam(tokens, next);
            if (!func_is_generic and !next_is_generic) continue;
            if (func_is_generic != next_is_generic) continue;
            return markErrorAt(tokens, next.start_idx, error.DuplicateFuncSignature);
        }
    }
}



pub fn funcParamShapesEqual(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    a: FuncShape,
    b: FuncShape,
) !bool {
    if (a.param_shapes.len != b.param_shapes.len) return false;
    var type_param_pairs = std.ArrayList(SigTypeParamPair).empty;
    defer type_param_pairs.deinit(allocator);

    for (a.param_shapes, 0..) |item, idx| {
        if (!(try funcParamShapeEqual(allocator, tokens, a, item, b, b.param_shapes[idx], &type_param_pairs))) return false;
    }
    return true;
}



pub fn funcParamShapeEqual(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    a_func: FuncShape,
    a: FuncParamShape,
    b_func: FuncShape,
    b: FuncParamShape,
    type_param_pairs: *std.ArrayList(SigTypeParamPair),
) !bool {
    const a_resolved = try resolveFuncParamTypeShape(allocator, tokens, a_func, a);
    defer freeResolvedFuncTypeShape(allocator, a_resolved);
    const b_resolved = try resolveFuncParamTypeShape(allocator, tokens, b_func, b);
    defer freeResolvedFuncTypeShape(allocator, b_resolved);

    if (a_resolved != null or b_resolved != null) {
        const a_func_type = if (a_resolved) |resolved| resolved.shape else return false;
        const b_func_type = if (b_resolved) |resolved| resolved.shape else return false;
        return funcTypeShapeEqual(a_func_type, b_func_type);
    }

    return try funcParamShapeEqualLexical(allocator, tokens, a_func, a, b_func, b, type_param_pairs);
}



pub fn funcParamShapeEqualLexical(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    a_func: FuncShape,
    a: FuncParamShape,
    b_func: FuncShape,
    b: FuncParamShape,
    type_param_pairs: *std.ArrayList(SigTypeParamPair),
) !bool {
    return switch (a) {
        .other => switch (b) {
            .other => true,
            else => false,
        },
        .value => |a_type| switch (b) {
            .value => |b_type| try funcParamValueTypesEqual(allocator, tokens, a_func, a_type, b_func, b_type, type_param_pairs),
            else => false,
        },
        .variadic => |a_type| switch (b) {
            .variadic => |b_type| try funcParamValueTypesEqual(allocator, tokens, a_func, a_type, b_func, b_type, type_param_pairs),
            else => false,
        },
        .func => |a_func_type| switch (b) {
            .func => |b_func_type| funcTypeShapeEqual(a_func_type, b_func_type),
            else => false,
        },
    };
}



pub fn funcParamValueTypesEqual(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    a_func: FuncShape,
    a_type: ?[]const u8,
    b_func: FuncShape,
    b_type: ?[]const u8,
    type_param_pairs: *std.ArrayList(SigTypeParamPair),
) !bool {
    const a_name = a_type orelse return b_type == null;
    const b_name = b_type orelse return false;

    const a_is_param = isFuncTypeParam(tokens, a_func.start_idx, a_name);
    const b_is_param = isFuncTypeParam(tokens, b_func.start_idx, b_name);
    if (!a_is_param and !b_is_param) return std.mem.eql(u8, a_name, b_name);
    if (a_is_param != b_is_param) return false;

    for (type_param_pairs.items) |pair| {
        if (std.mem.eql(u8, pair.a, a_name)) return std.mem.eql(u8, pair.b, b_name);
        if (std.mem.eql(u8, pair.b, b_name)) return false;
    }
    try type_param_pairs.append(allocator, .{ .a = a_name, .b = b_name });
    return true;
}



pub fn funcTypeShapeEqual(a: FuncTypeShape, b: FuncTypeShape) bool {
    if (a.param_count != b.param_count) return false;
    if (a.param_types.len != b.param_types.len) return false;
    for (a.param_types, 0..) |a_type, idx| {
        if (!optionalTypeNameEqual(a_type, b.param_types[idx])) return false;
    }
    return optionalTypeNameEqual(a.return_type, b.return_type);
}



pub fn optionalTypeNameEqual(a: ?[]const u8, b: ?[]const u8) bool {
    if (a) |a_name| {
        const b_name = b orelse return false;
        return std.mem.eql(u8, a_name, b_name);
    }
    return b == null;
}



pub fn funcHasGenericSignatureParam(tokens: []const lexer.Token, func: FuncShape) bool {
    for (func.param_shapes) |param| {
        const type_name = switch (param) {
            .value => |value_type| value_type orelse continue,
            .variadic => |value_type| value_type orelse continue,
            else => continue,
        };
        if (!isFuncTypeParam(tokens, func.start_idx, type_name)) continue;
        if (typeConstraintIsConcreteFunctionType(tokens, func.start_idx, type_name)) continue;
        return true;
    }
    return false;
}



pub fn isLocalUnionAlias(tokens: []const lexer.Token, name: []const u8) bool {
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
        if (isModernImportAssign(tokens, i)) return false;
        if (isErrorEnumDeclStart(tokens, i) or isValueEnumDeclStart(tokens, i) or isPayloadEnumDeclStart(tokens, i)) return false;
        const line_end = findLineEndIdx(tokens, i);
        const eq_idx = findTopLevelAssignEqOnLine(tokens, i + 1, line_end) orelse return false;
        return findTokenOnLine(tokens, eq_idx + 1, line_end, "|") != null;
    }
    return false;
}



pub fn findTokenOnLine(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, s: []const u8) ?usize {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEq(tokens[i], s)) return i;
    }
    return null;
}



pub fn isValidFuncParamName(name: []const u8) bool {
    return isLowerIdentName(name) and !isReservedFuncName(name);
}



pub fn isValidFuncParamTypeName(name: []const u8) bool {
    return name.len != 0 and (std.ascii.isUpper(name[0]) or name[0] == '[' or name[0] == '(' or name[0] == '.');
}



