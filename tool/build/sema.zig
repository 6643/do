const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

const Scope = struct {
    names: std.ArrayListUnmanaged([]const u8) = .empty,
    loop_bindings: std.ArrayListUnmanaged([]const u8) = .empty,

    fn deinit(self: *Scope, allocator: std.mem.Allocator) void {
        self.names.deinit(allocator);
        self.loop_bindings.deinit(allocator);
    }

    fn contains(self: *const Scope, name: []const u8) bool {
        for (self.names.items) |it| {
            if (std.mem.eql(u8, it, name)) return true;
        }
        return false;
    }

    fn containsLoopBinding(self: *const Scope, name: []const u8) bool {
        for (self.loop_bindings.items) |it| {
            if (std.mem.eql(u8, it, name)) return true;
        }
        return false;
    }
};

fn scopesContain(scopes: []const Scope, name: []const u8) bool {
    for (scopes) |scope| {
        if (scope.contains(name)) return true;
    }
    return false;
}

fn scopesContainLoopBinding(scopes: []const Scope, name: []const u8) bool {
    for (scopes) |scope| {
        if (scope.containsLoopBinding(name)) return true;
    }
    return false;
}

const CallArgInfo = struct {
    name: []const u8,
    arg_index: usize,
    arg_count: usize,
};

const ArgRange = struct {
    start: usize,
    end: usize,
};

const FieldMetaBinding = struct {
    name: []const u8,
    struct_name: []const u8,
    body_depth: usize,
};

const LocalImportPrefix = enum {
    local,
    dep,
    std,
};

const HostImportKind = enum {
    env,
    wasi,
};

pub const ErrorSite = struct {
    line: usize,
    col: usize,
};

var last_error_site: ?ErrorSite = null;

pub fn takeLastErrorSite() ?ErrorSite {
    const out = last_error_site;
    last_error_site = null;
    return out;
}

pub fn checkProgram(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
) !void {
    last_error_site = null;
    if (program.source_len == 0) return error.EmptySource;
    if (program.token_count == 0) return error.EmptyTokenStream;
    try checkPrivateLValueAssign(tokens);
    try checkFuncDeclNaming(tokens);
    try checkFuncReturnArrowSyntax(tokens);
    try checkStartDeclSyntax(tokens);
    try checkFuncParamNames(allocator, tokens);
    try checkInlineFuncParamTypes(tokens);
    try checkSynthErrorFuncParamTypes(tokens);
    try checkFuncParamTypeRestrictions(tokens);
    try checkFuncSignatureConflicts(allocator, tokens);
    try checkPathAccess(tokens);
    try checkFieldSegmentPositions(tokens);
    try checkHostImports(tokens);
    try checkLocalImports(tokens);
    if (program.top_level_count == 0) return markErrorAt(tokens, 0, error.NoTopLevelDecl);

    try checkTypeDeclNaming(tokens);
    try checkTypeDeclNameConflicts(allocator, tokens);
    try checkErrorDeclBranches(tokens);
    try checkTopValueDeclNames(tokens);
    try checkStructFieldNames(allocator, tokens);
    try checkTypeRefs(tokens);
    try checkParenthesizedTypeArgs(tokens);
    try checkParenthesizedTypes(tokens);
    try checkGenericTypeArgArity(tokens);
    try checkGenericStructCtorTypeArgs(tokens);
    try checkForbiddenSourceTypeNames(tokens);
    try checkBareNilTypes(tokens);
    try checkInlineFuncTypeUnionBranches(tokens);
    try checkDuplicateUnionBranches(tokens);
    try checkStructCtorFields(allocator, tokens);
    try checkPathIndexSegments(tokens);
    try checkDirectPathSource(tokens);
    try checkConstraintLayout(tokens);
    try checkUnboundTypeParamRefs(tokens);
    try checkSpreadCallTargets(allocator, tokens);
    try checkGenericCallInference(allocator, program, tokens);
    try checkSynthErrorTypePositions(tokens);
    try checkLineStringRootPositions(program, tokens);
    try checkUpperValueExprs(program, tokens);
    try checkSingleValuePositions(allocator, program, tokens);
    try checkKnownConditionBoolSites(allocator, program, tokens);
    try checkLambdaUsage(allocator, program, tokens);
    try checkLambdaOverloadCalls(allocator, program, tokens);
    try checkIsTypeArgs(tokens);
    try checkAsTypeArgs(tokens);
    try checkLoopHeader(tokens);
    try checkFieldReflection(allocator, tokens);
    try checkLoopLabels(allocator, tokens);
    try checkDeferStmts(allocator, tokens);
    try checkAssignmentConstraints(allocator, tokens);
}

fn checkPrivateLValueAssign(tokens: []const lexer.Token) !void {
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

fn isTopLevelDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    if (idx >= tokens.len or tokens[idx].kind != .ident) return false;
    if (isModernImportAssign(tokens, idx)) return true;
    if (isStartDeclStart(tokens, idx) or isFuncDeclStart(tokens, idx)) return true;
    if (isTypeDeclStart(tokens, idx)) return true;
    if (topLevelLineAssignIdx(tokens, idx) != null) return true;
    return tokEq(tokens[idx], "test");
}

fn isPrivateTopValueDeclStart(tokens: []const lexer.Token, idx: usize, eq_idx: usize) bool {
    if (!isTopLevelDeclHead(tokens, idx)) return false;
    if (eq_idx <= idx + 1) return false;
    if (tokens[idx].kind != .ident) return false;
    const name = tokens[idx].lexeme;
    return name.len > 1 and name[0] == '.' and isLowerIdentName(name[1..]) and !isReservedFuncName(name[1..]);
}

fn findPlainEqOnLine(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (!tokEq(tokens[i], "=")) continue;
        if (isNonAssignEqual(tokens, i)) continue;
        return i;
    }
    return null;
}

fn checkFuncDeclNaming(tokens: []const lexer.Token) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (depth_brace == 0) {
                if (parseImportDeclEnd(tokens, i)) |next_idx| {
                    i = next_idx - 1;
                    continue;
                }
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

fn checkFuncParamNames(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (depth_brace == 0) {
                if (parseImportDeclEnd(tokens, i)) |next_idx| {
                    i = next_idx - 1;
                    continue;
                }
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

fn validateFuncParamNames(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize) !void {
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

fn checkInlineFuncParamTypes(tokens: []const lexer.Token) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (depth_brace == 0) {
                if (parseImportDeclEnd(tokens, i)) |next_idx| {
                    i = next_idx - 1;
                    continue;
                }
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

fn checkFuncParamTypeRestrictions(tokens: []const lexer.Token) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (depth_brace == 0) {
                if (parseImportDeclEnd(tokens, i)) |next_idx| {
                    i = next_idx - 1;
                    continue;
                }
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

fn checkSynthErrorFuncParamTypes(tokens: []const lexer.Token) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (depth_brace == 0) {
                if (parseImportDeclEnd(tokens, i)) |next_idx| {
                    i = next_idx - 1;
                    continue;
                }
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

fn findSynthErrorParamType(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
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

fn findTopLevelTypeName(
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

fn checkParamTypeRange(tokens: []const lexer.Token, func_start_idx: usize, start_idx: usize, end_idx: usize) !void {
    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !isTopLevelCommaAny(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) try checkOneParamType(tokens, func_start_idx, seg_start, i);
        seg_start = i + 1;
    }
}

fn checkOneParamType(tokens: []const lexer.Token, func_start_idx: usize, start_idx: usize, end_idx: usize) !void {
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

fn directParamTypeName(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    if (start_idx + 1 != end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (!isValidDeclaredTypeName(tokens[start_idx].lexeme)) return null;
    return publicTypeName(tokens[start_idx].lexeme);
}

fn findTopLevelPipe(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
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

fn findFuncTypeConstraintBranchInParam(
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

fn isTopLevelTypePipe(tokens: []const lexer.Token, idx: usize, start_idx: usize, end_idx: usize) bool {
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

fn typeConstraintIsFunctionTypeInBlock(
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

fn checkPathAccess(tokens: []const lexer.Token) !void {
    for (tokens, 0..) |t, i| {
        if (t.kind != .ident) continue;
        if (t.lexeme.len == 0) continue;
        if (t.lexeme[0] == '.') continue;
        if (isImportPathToken(tokens, i)) continue;
        if (std.mem.indexOfScalar(u8, t.lexeme, '.') == null) continue;
        return markErrorAt(tokens, i, error.InvalidPathAccess);
    }
}

fn checkFieldSegmentPositions(tokens: []const lexer.Token) !void {
    for (tokens, 0..) |t, i| {
        if (t.kind != .ident) continue;
        if (t.lexeme.len == 0 or t.lexeme[0] != '.') continue;
        if (t.lexeme.len == 1) continue; // `.{...}` inferred aggregate prefix.
        if (isImportPathToken(tokens, i)) continue;
        if (isTopLevelDeclHead(tokens, i) and isModernImportAssign(tokens, i)) continue;
        if (isTopLevelDeclHead(tokens, i) and isTypeDeclStart(tokens, i)) continue;
        if (!std.ascii.isLower(t.lexeme[1])) continue;
        if (!isDotLowerIdent(t.lexeme)) return markErrorAt(tokens, i, error.InvalidPathAccess);
        if (isAllowedFieldSegmentPosition(tokens, i)) continue;
        return markErrorAt(tokens, i, error.InvalidPathAccess);
    }
}

fn isAllowedFieldSegmentPosition(tokens: []const lexer.Token, idx: usize) bool {
    if (isPrivateFuncDeclName(tokens, idx)) return true;
    if (isStructFieldDeclName(tokens, idx)) return true;
    return isGetSetPathFieldSegment(tokens, idx);
}

fn isPrivateFuncDeclName(tokens: []const lexer.Token, idx: usize) bool {
    if (!isTopLevelToken(tokens, idx)) return false;
    if (!isTopLevelDeclHead(tokens, idx)) return false;
    return isFuncDeclStart(tokens, idx);
}

fn isStructFieldDeclName(tokens: []const lexer.Token, idx: usize) bool {
    if (lineStartIdx(tokens, idx) != idx) return false;
    if (!isStructFieldDeclSyntaxName(tokens[idx].lexeme)) return false;
    return isInsideStructDecl(tokens, idx);
}

fn isStructFieldDeclSyntaxName(name: []const u8) bool {
    if (name.len == 0) return false;
    const body = if (name[0] == '.') name[1..] else name;
    return isSnakeLowerName(body);
}

fn isGetSetPathFieldSegment(tokens: []const lexer.Token, idx: usize) bool {
    const info = callArgInfo(tokens, idx) orelse return false;
    if (std.mem.eql(u8, info.name, "get")) return info.arg_index >= 1;
    if (std.mem.eql(u8, info.name, "set")) return info.arg_index >= 1 and info.arg_index + 1 < info.arg_count;
    return false;
}

fn callArgInfo(tokens: []const lexer.Token, idx: usize) ?CallArgInfo {
    const open_idx = findEnclosingCallOpen(tokens, idx) orelse return null;
    const name_idx = callNameIdxBeforeOpen(tokens, open_idx) orelse return null;

    const close_idx = findMatching(tokens, open_idx, "(", ")") catch return null;
    if (idx <= open_idx or idx >= close_idx) return null;

    var current_arg: usize = 0;
    var arg_count: usize = 0;
    var saw_arg_token = false;
    var target_arg: ?usize = null;
    var target_top_level = false;
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;

    var i = open_idx + 1;
    while (i < close_idx) : (i += 1) {
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tokEq(tokens[i], ",")) {
            if (saw_arg_token) arg_count += 1;
            saw_arg_token = false;
            current_arg += 1;
            continue;
        }

        saw_arg_token = true;
        if (i == idx) {
            target_arg = current_arg;
            target_top_level = depth_paren == 0 and depth_brace == 0 and depth_angle == 0;
        }

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
    if (saw_arg_token) arg_count += 1;

    const arg_index = target_arg orelse return null;
    if (!target_top_level) return null;
    return .{
        .name = tokens[name_idx].lexeme,
        .arg_index = arg_index,
        .arg_count = arg_count,
    };
}

fn callNameIdxBeforeOpen(tokens: []const lexer.Token, open_idx: usize) ?usize {
    if (open_idx == 0) return null;
    const name_idx = open_idx - 1;
    if (tokens[name_idx].kind != .ident) return null;
    return name_idx;
}

fn findEnclosingCallOpen(tokens: []const lexer.Token, idx: usize) ?usize {
    var depth: usize = 0;
    var i = idx;
    while (i > 0) {
        i -= 1;
        if (tokEq(tokens[i], ")")) {
            depth += 1;
            continue;
        }
        if (!tokEq(tokens[i], "(")) continue;
        if (depth == 0) return i;
        depth -= 1;
    }
    return null;
}

fn isTopLevelToken(tokens: []const lexer.Token, idx: usize) bool {
    var depth: usize = 0;
    var i: usize = 0;
    while (i < idx) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            depth += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth > 0) depth -= 1;
            continue;
        }
    }
    return depth == 0;
}

fn isImportPathToken(tokens: []const lexer.Token, idx: usize) bool {
    var i = idx;
    while (i > 0 and tokens[i - 1].line == tokens[idx].line) : (i -= 1) {}
    while (i < idx) : (i += 1) {
        if (tokEq(tokens[i], "@")) return true;
    }
    return false;
}

const DirectCallSite = struct {
    call: parser.FuncCallRef,
    start_tok_idx: usize,
};

fn checkSingleValuePositions(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
) !void {
    for (program.value_exprs) |site| {
        if (site.expected_arity <= 1) continue;

        const resolved = rootExprReturnArity(program, site.root_expr_idx);
        const allowed = switch (resolved) {
            .unknown => true,
            .ambiguous => false,
            .arity => |arity| arity == site.expected_arity,
        };
        if (allowed) continue;

        const start_tok = rootExprStartTok(program, site.root_expr_idx);
        const err = switch (site.context) {
            .assign => error.InvalidAssignExpr,
            .rhs => error.MultiReturnInSingleValuePosition,
            .return_value => error.InvalidReturnStmt,
            .single => error.MultiReturnInSingleValuePosition,
        };
        return markErrorAt(tokens, start_tok, err);
    }

    for (program.condition_exprs) |site| {
        const call_site = findDirectCallAtRoot(program, site.root_expr_idx);
        if (call_site == null) continue;

        const resolved = resolveCallReturnArity(
            program.func_sigs,
            call_site.?.call.func_name,
            call_site.?.call.arg_count,
        );
        switch (resolved) {
            .unknown => continue, // 可能是外部导入函数, 此阶段不阻断
            .arity => |arity| {
                if (arity <= 1) continue;
                switch (site.context) {
                    .if_cond => return markErrorAt(tokens, call_site.?.start_tok_idx, error.MultiReturnInIfCondition),
                    .loop_cond => return markErrorAt(tokens, call_site.?.start_tok_idx, error.MultiReturnInLoopCondition),
                }
            },
            .ambiguous => return markErrorAt(tokens, call_site.?.start_tok_idx, error.AmbiguousConditionCallReturnArity),
        }
    }

    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (!isCallHead(tokens, i) and !isBuiltinIntrinsicCallHead(tokens, i)) continue;
        if (isTopLevelDeclHead(tokens, i) and (isFuncDeclStart(tokens, i) or isStartDeclStart(tokens, i))) continue;
        if (isFuncConstraintHead(tokens, i)) continue;

        const open_paren = callOpenParenIdx(tokens, i, tokens.len) orelse continue;
        const close_paren = findMatching(tokens, open_paren, "(", ")") catch
            return markErrorAt(tokens, i + 1, error.InvalidCallArgList);
        const args = try parseCallArgShapes(allocator, tokens, open_paren + 1, close_paren);
        defer freeCallArgShapes(allocator, args);

        const resolved = resolveCallReturnArity(program.func_sigs, tokens[i].lexeme, args.len);
        const arity = switch (resolved) {
            .unknown => continue,
            .ambiguous => return markErrorAt(tokens, i, error.AmbiguousConditionCallReturnArity),
            .arity => |value| value,
        };
        if (arity <= 1) continue;
        if (valueExprAllowsArityAt(program, i, arity)) continue;

        return markErrorAt(tokens, i, error.MultiReturnInSingleValuePosition);
    }
}

const KnownBool = enum {
    yes,
    no,
    unknown,
    no_matching_call,
};

fn checkKnownConditionBoolSites(allocator: std.mem.Allocator, program: parser.Program, tokens: []const lexer.Token) !void {
    const funcs = try collectFuncShapes(allocator, tokens);
    defer freeFuncShapes(allocator, funcs);

    for (program.condition_exprs) |site| {
        const err = switch (site.context) {
            .if_cond => error.NonBoolIfCondition,
            .loop_cond => error.NonBoolLoopCondition,
        };

        switch (try classifyKnownBool(allocator, program, funcs, tokens, site.root_expr_idx)) {
            .yes, .unknown => continue,
            .no_matching_call => {
                const start_tok = rootExprStartTok(program, site.root_expr_idx);
                return markErrorAt(tokens, start_tok, error.NoMatchingCall);
            },
            .no => {
                const start_tok = rootExprStartTok(program, site.root_expr_idx);
                return markErrorAt(tokens, start_tok, err);
            },
        }
    }
}

fn checkLineStringRootPositions(program: parser.Program, tokens: []const lexer.Token) !void {
    for (program.expr_nodes) |node| {
        if (node.kind != .literal) continue;
        if (!isLineStringToken(tokens[node.start_tok])) continue;
        if (isLineStringRootExpr(program, node.start_tok)) continue;
        return markErrorAt(tokens, node.start_tok, error.UnsupportedExpr);
    }
}

fn isLineStringRootExpr(program: parser.Program, start_tok: usize) bool {
    for (program.value_exprs) |site| {
        if (site.context != .rhs) continue;
        if (site.root_expr_idx >= program.expr_nodes.len) continue;
        if (program.expr_nodes[site.root_expr_idx].start_tok == start_tok) return true;
    }
    return false;
}

fn isLineStringToken(tok: lexer.Token) bool {
    return tok.kind == .string and tok.lexeme.len >= 2 and tok.lexeme[0] == '\\' and tok.lexeme[1] == '\\';
}

fn checkLambdaUsage(allocator: std.mem.Allocator, program: parser.Program, tokens: []const lexer.Token) !void {
    for (program.expr_nodes) |node| {
        if (node.kind != .lambda) continue;
        try checkOneLambdaUsage(allocator, tokens, node);
    }
}

fn checkIsTypeArgs(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (!tokEq(tokens[i], "is")) continue;
        if (!tokEq(tokens[i + 1], "(")) continue;
        const close_paren = findMatching(tokens, i + 1, "(", ")") catch
            return markErrorAt(tokens, i + 1, error.InvalidNarrowing);
        const comma = findTopLevelComma(tokens, i + 2, close_paren) orelse
            return markErrorAt(tokens, i, error.InvalidNarrowing);
        const type_arg = firstNonGap(tokens, comma + 1, close_paren) orelse
            return markErrorAt(tokens, comma, error.InvalidNarrowing);
        if (isValueLiteralToken(tokens[type_arg])) {
            return markErrorAt(tokens, type_arg, error.InvalidNarrowing);
        }
        if (findInlineFuncTypeInIsArg(tokens, type_arg, close_paren)) |func_type_idx| {
            return markErrorAt(tokens, func_type_idx, error.InvalidNarrowing);
        }
        if (findTopLevelComma(tokens, type_arg, close_paren)) |extra_comma| {
            return markErrorAt(tokens, extra_comma, error.InvalidNarrowing);
        }
        if (findTopLevelNilInIsArg(tokens, type_arg, close_paren)) |nil_idx| {
            return markErrorAt(tokens, nil_idx, error.InvalidNarrowing);
        }
        if (validateIsTargetTypeExpr(tokens, type_arg, close_paren) != close_paren) {
            return markErrorAt(tokens, type_arg, error.InvalidNarrowing);
        }
    }
}

fn checkAsTypeArgs(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (!tokEq(tokens[i], "as")) continue;
        if (!tokEq(tokens[i + 1], "(")) continue;
        const close_paren = findMatching(tokens, i + 1, "(", ")") catch
            return markErrorAt(tokens, i + 1, error.InvalidCallArgList);
        const comma = findTopLevelComma(tokens, i + 2, close_paren) orelse
            return markErrorAt(tokens, i, error.InvalidCallArgList);

        if (asTypeFirstArg(tokens, i + 2, comma) != null) {
            if (findTopLevelComma(tokens, comma + 1, close_paren)) |extra_comma| {
                return markErrorAt(tokens, extra_comma, error.InvalidCallArgList);
            }
            if (comma + 1 >= close_paren) return markErrorAt(tokens, comma, error.InvalidCallArgList);
            continue;
        }
        return markErrorAt(tokens, i, error.InvalidCallArgList);
    }
}

fn asTypeFirstArg(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    const type_arg = firstNonGap(tokens, start_idx, end_idx) orelse return null;
    if (validateScalarAsTargetType(tokens, type_arg, end_idx) != end_idx) return null;
    return type_arg;
}

fn validateScalarAsTargetType(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (start_idx + 1 != end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (!isScalarAsTargetTypeName(tokens[start_idx].lexeme)) return null;
    return end_idx;
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

fn validateIsTypeExpr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var i = validateIsTypeAtom(tokens, start_idx, end_idx) orelse return null;
    while (i < end_idx) {
        if (!tokEq(tokens[i], "|")) return null;
        i = validateIsTypeAtom(tokens, i + 1, end_idx) orelse return null;
    }
    return i;
}

fn validateIsTargetTypeExpr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    return validateIsTypeAtom(tokens, start_idx, end_idx);
}

fn validateIsTypeAtom(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (start_idx >= end_idx) return null;
    if (tokEq(tokens[start_idx], "(")) return null;
    if (tokEq(tokens[start_idx], "[")) {
        const close_bracket = findMatching(tokens, start_idx, "[", "]") catch return null;
        if (validateIsTypeExpr(tokens, start_idx + 1, close_bracket) != close_bracket) return null;
        return close_bracket + 1;
    }
    if (tokens[start_idx].kind != .ident) return null;
    if (tokEq(tokens[start_idx], "nil")) return start_idx + 1;
    if (isValueLiteralToken(tokens[start_idx])) return null;
    if (!isBaseTypeName(tokens[start_idx].lexeme) and !isValidDeclaredTypeName(tokens[start_idx].lexeme)) return null;

    var next_idx = start_idx + 1;
    if (next_idx < end_idx and tokEq(tokens[next_idx], "<")) {
        const close_angle = findMatching(tokens, next_idx, "<", ">") catch return null;
        if (validateIsTypeArgList(tokens, next_idx + 1, close_angle) == null) return null;
        next_idx = close_angle + 1;
    }
    if (next_idx < end_idx and tokEq(tokens[next_idx], "(")) return null;
    return next_idx;
}

fn validateIsTypeArgList(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (start_idx >= end_idx) return null;
    var i = start_idx;
    while (i < end_idx) {
        const next_idx = validateIsTypeExprUntilComma(tokens, i, end_idx) orelse return null;
        if (next_idx >= end_idx) return next_idx;
        if (!tokEq(tokens[next_idx], ",")) return null;
        i = next_idx + 1;
        if (i >= end_idx) return null;
    }
    return i;
}

fn validateIsTypeExprUntilComma(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var i = validateIsTypeAtom(tokens, start_idx, end_idx) orelse return null;
    while (i < end_idx and !tokEq(tokens[i], ",")) {
        if (!tokEq(tokens[i], "|")) return null;
        i = validateIsTypeAtom(tokens, i + 1, end_idx) orelse return null;
    }
    return i;
}

fn findInlineFuncTypeInIsArg(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (!tokEq(tokens[i], "(")) continue;
        const close_paren = findMatching(tokens, i, "(", ")") catch return null;
        if (close_paren + 2 < end_idx and isReturnArrowAt(tokens, close_paren + 1)) return i;
        if (findInlineFuncTypeInIsArg(tokens, i + 1, close_paren)) |func_type_idx| return func_type_idx;
        i = close_paren;
    }
    return null;
}

fn findTopLevelNilInIsArg(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var depth_angle: usize = 0;
    var depth_bracket: usize = 0;
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
        if (tokEq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tokEq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
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
        if (depth_angle == 0 and depth_bracket == 0 and depth_paren == 0 and tokEq(tokens[i], "nil")) return i;
    }
    return null;
}

fn checkOneLambdaUsage(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    node: parser.ExprNode,
) !void {
    if (!isLambdaCallArgSite(tokens, node.start_tok)) {
        return markErrorAt(tokens, node.start_tok, error.InvalidLambdaExpr);
    }

    const open_paren = lambdaParamOpen(tokens, node.start_tok) orelse
        return markErrorAt(tokens, node.start_tok, error.InvalidLambdaExpr);
    const close_paren = findMatching(tokens, open_paren, "(", ")") catch
        return markErrorAt(tokens, node.start_tok, error.InvalidLambdaExpr);
    const body_start = lambdaBodyStart(tokens, close_paren + 1, node.end_tok) orelse {
        return markErrorAt(tokens, close_paren, error.InvalidLambdaExpr);
    };

    const params = try collectLambdaParamNames(allocator, tokens, open_paren + 1, close_paren);
    defer allocator.free(params);

    if (body_start > node.end_tok) return markErrorAt(tokens, close_paren, error.InvalidLambdaExpr);

    if (try findLambdaCapture(allocator, tokens, body_start, node.end_tok, params)) |bad_idx| {
        return markErrorAt(tokens, bad_idx, error.InvalidLambdaExpr);
    }
}

const LambdaArgShape = struct {
    arg_index: usize,
    param_count: usize,
    param_types: []?[]const u8,
    return_type: ?[]const u8,
};

const FuncParamShape = union(enum) {
    other,
    value: ?[]const u8,
    variadic: ?[]const u8,
    func: FuncTypeShape,
};

const FuncTypeShape = struct {
    param_count: usize,
    param_types: []?[]const u8,
    return_type: ?[]const u8,
};

const ResolvedFuncTypeShape = struct {
    shape: FuncTypeShape,
    owned: bool,
};

const SigTypeParamPair = struct {
    a: []const u8,
    b: []const u8,
};

const FuncShape = struct {
    name: []const u8,
    start_idx: usize,
    param_shapes: []FuncParamShape,
    param_min: usize,
    param_max: ?usize,
    return_type: ?[]const u8,
};

const CallArgShape = union(enum) {
    other,
    lambda: LambdaArgShape,
    ident: []const u8,
    spread: usize,
};

const CallShape = struct {
    name: []const u8,
    start_idx: usize,
    has_explicit_type_args: bool = false,
    arg_shapes: []CallArgShape,
};

fn checkLambdaOverloadCalls(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
) !void {
    const funcs = try collectFuncShapes(allocator, tokens);
    defer freeFuncShapes(allocator, funcs);

    if (funcs.len == 0) return;

    var calls = std.ArrayList(CallShape).empty;
    defer {
        for (calls.items) |call| freeCallArgShapes(allocator, call.arg_shapes);
        calls.deinit(allocator);
    }

    try collectCallShapesFromProgram(allocator, program, tokens, &calls);
    for (calls.items) |call| {
        if (isSetUpdateLambdaCall(call)) continue;
        if (!callHasTargetFunctionValue(tokens, funcs, call)) continue;
        if (!hasKnownFuncCandidate(funcs, call.name)) continue;
        if (try countCompatibleFunctionValueCandidates(allocator, tokens, funcs, call) != 1) {
            return markErrorAt(tokens, call.start_idx, error.NoMatchingCall);
        }
    }

    try checkBareOverloadedFuncAssign(tokens, funcs);
}

fn isSetUpdateLambdaCall(call: CallShape) bool {
    if (!std.mem.eql(u8, call.name, "set")) return false;
    if (call.arg_shapes.len < 3) return false;
    return call.arg_shapes[call.arg_shapes.len - 1] == .lambda;
}

fn checkGenericCallInference(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
) !void {
    const funcs = try collectFuncShapes(allocator, tokens);
    defer freeFuncShapes(allocator, funcs);

    if (funcs.len == 0) return;

    var calls = std.ArrayList(CallShape).empty;
    defer {
        for (calls.items) |call| freeCallArgShapes(allocator, call.arg_shapes);
        calls.deinit(allocator);
    }

    try collectCallShapesFromProgram(allocator, program, tokens, &calls);
    for (calls.items) |call| {
        if (call.has_explicit_type_args) continue;

        var has_plain_candidate = false;
        var has_direct_generic_candidate = false;
        var has_inferred_generic_candidate = false;

        for (funcs) |func| {
            if (!std.mem.eql(u8, func.name, call.name)) continue;
            if (func.param_shapes.len != call.arg_shapes.len) continue;

            if (!funcHasTypeConstraints(tokens, func.start_idx)) {
                has_plain_candidate = true;
                continue;
            }
            if (!funcHasDirectTypeParamParam(tokens, func)) {
                if (funcHasUninferredReturnTypeParam(tokens, func)) {
                    has_direct_generic_candidate = true;
                }
                continue;
            }

            has_direct_generic_candidate = true;
            if (genericCallInfersDirectTypeParams(tokens, func, call)) {
                has_inferred_generic_candidate = true;
            }
        }

        if (!has_direct_generic_candidate) continue;
        if (has_inferred_generic_candidate) continue;
        if (has_plain_candidate) continue;
        return markErrorAt(tokens, call.start_idx, error.NoMatchingCall);
    }
}

fn collectFuncShapes(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]FuncShape {
    var out = std.ArrayList(FuncShape).empty;
    errdefer {
        for (out.items) |shape| freeFuncParamShapes(allocator, shape.param_shapes);
        out.deinit(allocator);
    }

    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) {
        if (tokEq(tokens[i], "{")) {
            if (depth_brace == 0) {
                if (parseImportDeclEnd(tokens, i)) |next_idx| {
                    i = next_idx;
                    continue;
                }
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

fn checkFuncReturnArrowSyntax(tokens: []const lexer.Token) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (depth_brace == 0) {
                if (parseImportDeclEnd(tokens, i)) |next_idx| {
                    i = next_idx - 1;
                    continue;
                }
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

fn checkStartDeclSyntax(tokens: []const lexer.Token) !void {
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

fn checkFuncSignatureConflicts(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
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

fn funcParamShapesEqual(
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

fn funcParamShapeEqual(
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

fn funcParamShapeEqualLexical(
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

fn funcParamValueTypesEqual(
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

fn funcTypeShapeEqual(a: FuncTypeShape, b: FuncTypeShape) bool {
    if (a.param_count != b.param_count) return false;
    if (a.param_types.len != b.param_types.len) return false;
    for (a.param_types, 0..) |a_type, idx| {
        if (!optionalTypeNameEqual(a_type, b.param_types[idx])) return false;
    }
    return optionalTypeNameEqual(a.return_type, b.return_type);
}

fn optionalTypeNameEqual(a: ?[]const u8, b: ?[]const u8) bool {
    if (a) |a_name| {
        const b_name = b orelse return false;
        return std.mem.eql(u8, a_name, b_name);
    }
    return b == null;
}

fn freeFuncShapes(allocator: std.mem.Allocator, funcs: []FuncShape) void {
    for (funcs) |shape| freeFuncParamShapes(allocator, shape.param_shapes);
    allocator.free(funcs);
}

fn freeFuncParamShapes(allocator: std.mem.Allocator, shapes: []FuncParamShape) void {
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

fn freeFuncTypeParamNames(allocator: std.mem.Allocator, param_types: []?[]const u8) void {
    for (param_types) |param_type| {
        if (param_type) |name| allocator.free(name);
    }
    allocator.free(param_types);
}

fn freeCallArgShapes(allocator: std.mem.Allocator, shapes: []CallArgShape) void {
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

fn parseFuncParamShapes(
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

fn parseFuncParamShape(
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

fn parseFuncParamArity(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) struct { param_min: usize, param_max: ?usize } {
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

fn parseTopLevelFuncReturnType(tokens: []const lexer.Token, start_idx: usize) ?[]const u8 {
    if (start_idx >= tokens.len) return null;
    if (tokEq(tokens[start_idx], "{") or isArrowAt(tokens, start_idx)) return null;

    if (isReturnArrowAt(tokens, start_idx)) {
        return simpleTypeName(tokens, start_idx + 2, findReturnTypeEnd(tokens, start_idx + 2));
    }

    return simpleTypeName(tokens, start_idx, findReturnTypeEnd(tokens, start_idx));
}

fn findReturnTypeEnd(tokens: []const lexer.Token, start_idx: usize) usize {
    var i = start_idx;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) return i;
        if (isArrowAt(tokens, i)) return i;
        if (tokens[i].line != tokens[start_idx].line) return i;
    }
    return i;
}

fn collectCallShapesFromProgram(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    out: *std.ArrayList(CallShape),
) !void {
    for (program.expr_nodes) |node| {
        switch (node.kind) {
            .call => {},
            else => continue,
        }

        const call_start = node.start_tok;
        const open_paren = callOpenParenIdx(tokens, call_start, node.end_tok) orelse continue;

        const args_start = open_paren + 1;
        const args_end = node.end_tok - 1;
        const args = try parseCallArgShapes(allocator, tokens, args_start, args_end);
        try out.append(allocator, .{
            .name = tokens[call_start].lexeme,
            .start_idx = node.start_tok,
            .has_explicit_type_args = open_paren != call_start + 1,
            .arg_shapes = args,
        });
    }
}

fn parseCallArgShapes(
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

fn parseCallArgShape(
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

fn checkSpreadCallTargets(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
) !void {
    const funcs = try collectFuncShapes(allocator, tokens);
    defer freeFuncShapes(allocator, funcs);

    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (!isCallHead(tokens, i) and !isBuiltinIntrinsicCallHead(tokens, i)) continue;
        if (isTopLevelDeclHead(tokens, i) and (isFuncDeclStart(tokens, i) or isStartDeclStart(tokens, i))) continue;
        if (isFuncConstraintHead(tokens, i)) continue;

        const open_paren = callOpenParenIdx(tokens, i, tokens.len) orelse continue;
        const close_paren = findMatching(tokens, open_paren, "(", ")") catch
            return markErrorAt(tokens, i + 1, error.InvalidCallArgList);
        const args = try parseCallArgShapes(allocator, tokens, open_paren + 1, close_paren);
        defer freeCallArgShapes(allocator, args);

        const spread_idx = callArgSpreadIndex(args) orelse continue;
        const spread_token_idx = callArgSpreadTokenIdx(args) orelse i;
        const call_name = tokens[i].lexeme;
        if (isHostImportFuncName(tokens, call_name)) {
            return markErrorAt(tokens, spread_token_idx, error.InvalidCallArgList);
        }
        if (builtinSpreadCallAllowed(call_name, spread_idx)) |allowed| {
            if (!allowed) return markErrorAt(tokens, spread_token_idx, error.InvalidCallArgList);
            continue;
        }
        if (!hasKnownFuncCandidate(funcs, call_name)) continue;

        for (funcs) |func| {
            if (!std.mem.eql(u8, func.name, call_name)) continue;
            if (callSpreadCompatibleWithFunc(func, args.len, spread_idx)) break;
        } else {
            return markErrorAt(tokens, spread_token_idx, error.InvalidCallArgList);
        }
    }
}

fn checkDeferStmts(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
) !void {
    const funcs = try collectFuncShapes(allocator, tokens);
    defer freeFuncShapes(allocator, funcs);

    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tokEq(tokens[i], "defer")) continue;
        const body_idx = i + 1;
        if (body_idx >= tokens.len) return markErrorAt(tokens, i, error.NoMatchingCall);
        if (tokEq(tokens[body_idx], "{")) {
            const close_block = findMatching(tokens, body_idx, "{", "}") catch return markErrorAt(tokens, body_idx, error.NoMatchingCall);
            try checkDeferBlockNoControlFlow(tokens, body_idx + 1, close_block);
            i = close_block;
            continue;
        }
        try checkDeferCallStmt(allocator, funcs, tokens, body_idx);
    }
}

fn checkDeferBlockNoControlFlow(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) !void {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEq(tokens[i], "return") or tokEq(tokens[i], "break") or tokEq(tokens[i], "continue")) {
            return markErrorAt(tokens, i, error.NoMatchingCall);
        }
    }
}

fn checkDeferCallStmt(
    allocator: std.mem.Allocator,
    funcs: []const FuncShape,
    tokens: []const lexer.Token,
    call_idx: usize,
) !void {
    if (tokEq(tokens[call_idx], "@")) return markErrorAt(tokens, call_idx, error.NoMatchingCall);
    if (tokens[call_idx].kind != .ident) return markErrorAt(tokens, call_idx, error.NoMatchingCall);
    if (call_idx + 1 >= tokens.len or !tokEq(tokens[call_idx + 1], "(")) return markErrorAt(tokens, call_idx, error.NoMatchingCall);

    const line_end = findLineEndIdx(tokens, call_idx);
    const close_paren = findMatching(tokens, call_idx + 1, "(", ")") catch return markErrorAt(tokens, call_idx, error.NoMatchingCall);
    if (close_paren + 1 != line_end) return markErrorAt(tokens, call_idx, error.NoMatchingCall);

    const args = try parseCallArgShapes(allocator, tokens, call_idx + 2, close_paren);
    defer freeCallArgShapes(allocator, args);

    const name = tokens[call_idx].lexeme;
    var saw_func_candidate = false;
    for (funcs) |func| {
        if (!std.mem.eql(u8, func.name, name)) continue;
        if (!callArityCompatibleWithFunc(func, args.len)) continue;
        saw_func_candidate = true;
        if (funcReturnIsNil(func.return_type)) return;
    }
    if (saw_func_candidate) return markErrorAt(tokens, call_idx, error.NoMatchingCall);

    if (hostImportReturnIsNil(tokens, name)) |is_nil| {
        if (is_nil) return;
        return markErrorAt(tokens, call_idx, error.NoMatchingCall);
    }
}

fn funcReturnIsNil(return_type: ?[]const u8) bool {
    const ty = return_type orelse return true;
    return std.mem.eql(u8, ty, "nil");
}

fn hostImportReturnIsNil(tokens: []const lexer.Token, name: []const u8) ?bool {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (depth_brace == 0) {
                if (parseImportDeclEnd(tokens, i)) |next_idx| {
                    i = next_idx - 1;
                    continue;
                }
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
        if (!std.mem.eql(u8, publicFuncName(tokens[i].lexeme), name)) continue;
        if (!isHostImportDeclStart(tokens, i)) continue;

        const eq_idx = topLevelLineAssignIdx(tokens, i) orelse return null;
        const at_idx = eq_idx + 1;
        const import_end = parseImportDeclEnd(tokens, i) orelse return null;
        const comma_idx = findTopLevelComma(tokens, at_idx + 4, import_end - 1) orelse return null;
        const sig_start = comma_idx + 1;
        if (sig_start >= import_end or !tokEq(tokens[sig_start], "(")) return null;
        const close_params = findMatching(tokens, sig_start, "(", ")") catch return null;
        if (!isReturnArrowAt(tokens, close_params + 1)) return null;

        const return_start = close_params + 3;
        const return_end = import_end - 1;
        return return_start + 1 == return_end and tokEq(tokens[return_start], "nil");
    }
    return null;
}

fn callArgSpreadIndex(args: []const CallArgShape) ?usize {
    for (args, 0..) |arg, arg_idx| {
        if (arg == .spread) return arg_idx;
    }
    return null;
}

fn callArgSpreadTokenIdx(args: []const CallArgShape) ?usize {
    for (args) |arg| {
        if (arg == .spread) return arg.spread;
    }
    return null;
}

fn callSpreadCompatibleWithFunc(func: FuncShape, arg_count: usize, spread_idx: usize) bool {
    if (!callArityCompatibleWithFunc(func, arg_count)) return false;
    if (func.param_max != null) return false;
    return spread_idx >= func.param_min;
}

fn builtinSpreadCallAllowed(name: []const u8, spread_idx: usize) ?bool {
    if (isNumericCoreName(name)) return spread_idx >= 2;
    if (std.mem.eql(u8, name, "put")) return spread_idx == 1;
    if (isBuiltinCallName(name)) return false;
    return null;
}

fn isHostImportFuncName(tokens: []const lexer.Token, name: []const u8) bool {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!isTopLevelDeclHead(tokens, i)) continue;
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, publicFuncName(tokens[i].lexeme), name)) continue;
        if (isHostImportDeclStart(tokens, i)) return true;
    }
    return false;
}

fn isNumericCoreName(name: []const u8) bool {
    const names = [_][]const u8{ "add", "sub", "mul", "div", "rem", "min", "max" };
    for (names) |it| {
        if (std.mem.eql(u8, it, name)) return true;
    }
    return false;
}

fn isBuiltinCallName(name: []const u8) bool {
    const names = [_][]const u8{
        "is",
        "as",
        "and",
        "or",
        "not",
        "eq",
        "ne",
        "lt",
        "le",
        "gt",
        "ge",
        "add",
        "sub",
        "mul",
        "div",
        "rem",
        "get",
        "set",
        "field_name",
        "field_index",
        "field_has_default",
        "field_get",
        "field_set",
        "len",
        "put",
        "load_u8",
        "load_i8",
        "load_u16_le",
        "load_i16_le",
        "load_u32_le",
        "load_i32_le",
        "load_u64_le",
        "load_i64_le",
        "xor",
        "shl",
        "shr",
        "rotl",
        "rotr",
        "clz",
        "ctz",
        "popcnt",
        "abs",
        "neg",
        "sqrt",
        "ceil",
        "floor",
        "trunc",
        "nearest",
        "min",
        "max",
        "copysign",
    };
    for (names) |it| {
        if (std.mem.eql(u8, it, name)) return true;
    }
    return false;
}

fn lambdaParamClose(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (start_idx >= end_idx or !tokEq(tokens[start_idx], "(")) return null;
    const close_idx = findMatching(tokens, start_idx, "(", ")") catch return null;
    if (close_idx >= end_idx) return null;
    return close_idx;
}

fn lambdaReturnTypeName(tokens: []const lexer.Token, close_params_idx: usize, end_idx: usize) ?[]const u8 {
    const return_arrow_idx = close_params_idx + 1;
    if (!isReturnArrowAt(tokens, return_arrow_idx)) return null;

    const body_start = lambdaBodyStart(tokens, return_arrow_idx, end_idx) orelse return null;
    const return_end = if (body_start >= 2 and isArrowAt(tokens, body_start - 2))
        body_start - 2
    else
        body_start;
    return simpleTypeName(tokens, return_arrow_idx + 2, return_end);
}

fn hasKnownFuncCandidate(funcs: []const FuncShape, name: []const u8) bool {
    for (funcs) |func| {
        if (std.mem.eql(u8, func.name, name)) return true;
    }
    return false;
}

fn countCompatibleFunctionValueCandidates(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncShape,
    call: CallShape,
) !usize {
    var count: usize = 0;
    for (funcs) |func| {
        if (!std.mem.eql(u8, func.name, call.name)) continue;
        if (!callArityCompatibleWithFunc(func, call.arg_shapes.len)) continue;
        if (!(try functionValueArgsMatchFunc(allocator, tokens, funcs, func, call))) continue;
        count += 1;
    }
    return count;
}

fn functionValueArgsMatchFunc(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    funcs: []const FuncShape,
    func: FuncShape,
    call: CallShape,
) !bool {
    for (call.arg_shapes, 0..) |arg, arg_index| {
        switch (arg) {
            .other => continue,
            .spread => continue,
            .lambda => |lambda| {
                if (lambda.arg_index >= func.param_shapes.len) return false;
                const target = try resolveFuncParamTypeShape(allocator, tokens, func, func.param_shapes[lambda.arg_index]);
                defer freeResolvedFuncTypeShape(allocator, target);
                const func_type = if (target) |resolved| resolved.shape else return false;
                if (func_type.param_count != lambda.param_count) return false;
                if (!explicitLambdaTypesMatch(func_type.param_types, lambda.param_types)) return false;
            },
            .ident => |name| {
                if (arg_index >= func.param_shapes.len) return false;
                const target = try resolveFuncParamTypeShape(allocator, tokens, func, func.param_shapes[arg_index]);
                defer freeResolvedFuncTypeShape(allocator, target);
                const target_func = if (target) |resolved| resolved.shape else continue;
                if (countFuncsMatchingTarget(funcs, name, target_func) != 1) return false;
            },
        }
    }
    return true;
}

fn countFuncsMatchingTarget(
    funcs: []const FuncShape,
    name: []const u8,
    target_func: FuncTypeShape,
) usize {
    var count: usize = 0;
    for (funcs) |func| {
        if (!std.mem.eql(u8, func.name, name)) continue;
        if (!functionMatchesTarget(func, target_func)) continue;
        count += 1;
    }
    return count;
}

fn functionMatchesTarget(func: FuncShape, target: FuncTypeShape) bool {
    if (func.param_shapes.len != target.param_count) return false;
    for (target.param_types, 0..) |target_type, idx| {
        const expected = target_type orelse continue;
        const actual = switch (func.param_shapes[idx]) {
            .value => |value_type| value_type orelse return false,
            .variadic => |value_type| value_type orelse return false,
            else => return false,
        };
        if (!std.mem.eql(u8, actual, expected)) return false;
    }
    if (target.return_type) |expected_ret| {
        const actual_ret = func.return_type orelse return false;
        if (!std.mem.eql(u8, actual_ret, expected_ret)) return false;
    }
    return true;
}

fn callHasTargetFunctionValue(tokens: []const lexer.Token, funcs: []const FuncShape, call: CallShape) bool {
    for (call.arg_shapes, 0..) |arg, arg_index| {
        if (arg == .lambda and callHasFuncParamCandidateAtIndex(tokens, funcs, call, arg_index)) return true;
        if (arg != .ident) continue;
        const ident = arg.ident;
        if (!hasKnownFuncCandidate(funcs, ident)) continue;
        if (callHasFuncParamCandidateAtIndex(tokens, funcs, call, arg_index)) return true;
    }
    return false;
}

fn callHasFuncParamCandidateAtIndex(tokens: []const lexer.Token, funcs: []const FuncShape, call: CallShape, arg_index: usize) bool {
    for (funcs) |func| {
        if (!std.mem.eql(u8, func.name, call.name)) continue;
        if (!callArityCompatibleWithFunc(func, call.arg_shapes.len)) continue;
        if (arg_index >= func.param_shapes.len) continue;
        if (funcParamShapeIsFunctionLike(tokens, func, func.param_shapes[arg_index])) return true;
    }
    return false;
}

fn funcParamShapeIsFunctionLike(tokens: []const lexer.Token, func: FuncShape, param: FuncParamShape) bool {
    return switch (param) {
        .func => true,
        .value => |type_name| if (type_name) |name|
            typeConstraintIsConcreteFunctionType(tokens, func.start_idx, name)
        else
            false,
        .variadic => |type_name| if (type_name) |name|
            typeConstraintIsConcreteFunctionType(tokens, func.start_idx, name)
        else
            false,
        else => false,
    };
}

fn resolveFuncParamTypeShape(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    func: FuncShape,
    param: FuncParamShape,
) !?ResolvedFuncTypeShape {
    return switch (param) {
        .func => |func_type| .{ .shape = func_type, .owned = false },
        .value => |type_name| if (type_name) |name|
            try parseConcreteFuncTypeConstraintShape(allocator, tokens, func.start_idx, name)
        else
            null,
        .variadic => |type_name| if (type_name) |name|
            try parseConcreteFuncTypeConstraintShape(allocator, tokens, func.start_idx, name)
        else
            null,
        .other => null,
    };
}

fn freeResolvedFuncTypeShape(allocator: std.mem.Allocator, resolved: ?ResolvedFuncTypeShape) void {
    const item = resolved orelse return;
    if (!item.owned) return;
    freeFuncTypeParamNames(allocator, item.shape.param_types);
}

fn parseConcreteFuncTypeConstraintShape(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    func_start_idx: usize,
    constraint_name: []const u8,
) !?ResolvedFuncTypeShape {
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
        if (funcTypeConstraintUsesPriorTypeParam(tokens, block_start, i, eq_idx + 1, line_end)) return null;

        const close_params = findMatching(tokens, eq_idx + 1, "(", ")") catch return null;
        const param_types = try parseTypeNameList(allocator, tokens, eq_idx + 2, close_params);
        return .{
            .shape = .{
                .param_count = param_types.len,
                .param_types = param_types,
                .return_type = simpleTypeName(tokens, close_params + 3, line_end),
            },
            .owned = true,
        };
    }
    return null;
}

fn typeConstraintIsConcreteFunctionType(
    tokens: []const lexer.Token,
    func_start_idx: usize,
    constraint_name: []const u8,
) bool {
    const block_start = findConstraintBlockStartBefore(tokens, func_start_idx) orelse return false;

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
        if (!isFuncTypeRange(tokens, eq_idx + 1, line_end)) return false;
        return !funcTypeConstraintUsesPriorTypeParam(tokens, block_start, i, eq_idx + 1, line_end);
    }
    return false;
}

fn funcTypeConstraintUsesPriorTypeParam(
    tokens: []const lexer.Token,
    block_start: usize,
    constraint_idx: usize,
    type_start: usize,
    type_end: usize,
) bool {
    var i = type_start;
    while (i < type_end) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (hasTypeConstraintName(tokens, block_start, constraint_idx, tokens[i].lexeme)) return true;
    }
    return false;
}

fn checkBareOverloadedFuncAssign(tokens: []const lexer.Token, funcs: []const FuncShape) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tokEq(tokens[i], "=") or isNonAssignEqual(tokens, i)) continue;

        const line_start = lineStartIdx(tokens, i);
        const line_end = findLineEndIdx(tokens, i);
        const rhs_start = i + 1;
        if (rhs_start + 1 != line_end) continue;
        if (tokens[rhs_start].kind != .ident) continue;
        if (countFuncsByName(funcs, tokens[rhs_start].lexeme) < 2) continue;

        if (line_start + 1 != i) continue;
        if (tokens[line_start].kind != .ident) continue;
        return markErrorAt(tokens, rhs_start, error.NoMatchingCall);
    }
}

fn funcHasTypeConstraints(tokens: []const lexer.Token, func_start_idx: usize) bool {
    return findConstraintBlockStartBefore(tokens, func_start_idx) != null;
}

fn funcHasDirectTypeParamParam(tokens: []const lexer.Token, func: FuncShape) bool {
    for (func.param_shapes) |param| {
        const type_name = switch (param) {
            .value => |value_type| value_type orelse continue,
            .variadic => |value_type| value_type orelse continue,
            else => continue,
        };
        if (typeConstraintIsFunctionType(tokens, func.start_idx, type_name)) continue;
        if (isFuncTypeParam(tokens, func.start_idx, type_name)) return true;
    }
    return funcParamTypeRangesContainDataTypeParam(tokens, func);
}

fn funcHasGenericSignatureParam(tokens: []const lexer.Token, func: FuncShape) bool {
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

fn genericCallInfersDirectTypeParams(
    tokens: []const lexer.Token,
    func: FuncShape,
    call: CallShape,
) bool {
    if (funcHasUninferredReturnTypeParam(tokens, func)) return false;
    if (!genericCallHasRequiredLambdaReturnTypes(tokens, func, call)) return false;

    for (func.param_shapes, 0..) |param, param_idx| {
        const type_name = switch (param) {
            .value => |value_type| value_type orelse continue,
            .variadic => |value_type| value_type orelse continue,
            else => continue,
        };
        if (typeConstraintIsFunctionType(tokens, func.start_idx, type_name)) continue;
        if (!isFuncTypeParam(tokens, func.start_idx, type_name)) continue;
        if (hasPriorDirectTypeParam(func, param_idx, type_name)) continue;
        if (!callHasKnownArgForDirectTypeParam(tokens, func, call, type_name)) return false;
    }
    return true;
}

fn funcHasUninferredReturnTypeParam(tokens: []const lexer.Token, func: FuncShape) bool {
    const close_params = findMatching(tokens, func.start_idx + 1, "(", ")") catch return false;
    var return_start = close_params + 1;
    if (return_start >= tokens.len) return false;
    if (isReturnArrowAt(tokens, return_start)) return_start += 2;
    if (return_start >= tokens.len) return false;
    if (tokEq(tokens[return_start], "{") or isArrowAt(tokens, return_start)) return false;

    const return_end = findReturnTypeEnd(tokens, return_start);
    var i = return_start;
    while (i < return_end) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        const name = tokens[i].lexeme;
        if (!isFuncTypeParam(tokens, func.start_idx, name)) continue;
        if (typeConstraintIsFunctionType(tokens, func.start_idx, name)) continue;
        if (!funcParamSideCanBindTypeParam(tokens, func, name)) return true;
    }
    return false;
}

fn funcParamSideCanBindTypeParam(tokens: []const lexer.Token, func: FuncShape, type_name: []const u8) bool {
    if (funcParamTypeRangesContainTypeParam(tokens, func, type_name)) return true;

    for (func.param_shapes, 0..) |param, param_idx| {
        const param_type = switch (param) {
            .value => |value_type| value_type orelse continue,
            .variadic => |value_type| value_type orelse continue,
            .func => |func_type| {
                if (funcTypeShapeContainsTypeParam(func_type, type_name)) return true;
                continue;
            },
            .other => continue,
        };
        if (typeConstraintIsFunctionType(tokens, func.start_idx, param_type)) {
            if (typeConstraintFuncShapeContainsTypeParam(tokens, func.start_idx, param_type, type_name)) return true;
            continue;
        }
        if (!std.mem.eql(u8, param_type, type_name)) continue;
        if (hasPriorDirectTypeParam(func, param_idx, type_name)) continue;
        return true;
    }
    return false;
}

fn funcParamTypeRangesContainDataTypeParam(tokens: []const lexer.Token, func: FuncShape) bool {
    const close_params = findMatching(tokens, func.start_idx + 1, "(", ")") catch return false;
    var seg_start = func.start_idx + 2;
    var i = seg_start;
    while (i <= close_params) : (i += 1) {
        if (i < close_params and !isTopLevelCommaAny(tokens, i, func.start_idx + 2, close_params)) continue;
        if (funcParamTypeRangeContainsDataTypeParam(tokens, func, seg_start, i)) return true;
        seg_start = i + 1;
    }
    return false;
}

fn funcParamTypeRangesContainTypeParam(tokens: []const lexer.Token, func: FuncShape, type_name: []const u8) bool {
    const close_params = findMatching(tokens, func.start_idx + 1, "(", ")") catch return false;
    var seg_start = func.start_idx + 2;
    var i = seg_start;
    while (i <= close_params) : (i += 1) {
        if (i < close_params and !isTopLevelCommaAny(tokens, i, func.start_idx + 2, close_params)) continue;
        if (funcParamTypeRangeContainsTypeParam(tokens, seg_start, i, type_name)) return true;
        seg_start = i + 1;
    }
    return false;
}

fn funcParamTypeRangeContainsDataTypeParam(
    tokens: []const lexer.Token,
    func: FuncShape,
    start_idx: usize,
    end_idx: usize,
) bool {
    const type_start = funcParamTypeStart(tokens, start_idx, end_idx) orelse return false;
    var i = type_start;
    while (i < end_idx) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        const name = tokens[i].lexeme;
        if (!isFuncTypeParam(tokens, func.start_idx, name)) continue;
        if (typeConstraintIsFunctionType(tokens, func.start_idx, name)) continue;
        return true;
    }
    return false;
}

fn funcParamTypeRangeContainsTypeParam(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    type_name: []const u8,
) bool {
    const type_start = funcParamTypeStart(tokens, start_idx, end_idx) orelse return false;
    return tokenNameAppearsInRange(tokens, type_start, end_idx, type_name);
}

fn funcParamTypeStart(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (start_idx + 1 >= end_idx) return null;
    if (isSpreadToken(tokens[start_idx + 1])) {
        if (start_idx + 2 >= end_idx) return null;
        return start_idx + 2;
    }
    return start_idx + 1;
}

fn funcTypeShapeContainsTypeParam(shape: FuncTypeShape, type_name: []const u8) bool {
    for (shape.param_types) |param_type| {
        const name = param_type orelse continue;
        if (std.mem.eql(u8, name, type_name)) return true;
    }
    if (shape.return_type) |ret| {
        if (std.mem.eql(u8, ret, type_name)) return true;
    }
    return false;
}

fn typeConstraintFuncShapeContainsTypeParam(
    tokens: []const lexer.Token,
    func_start_idx: usize,
    constraint_name: []const u8,
    type_name: []const u8,
) bool {
    const block_start = findConstraintBlockStartBefore(tokens, func_start_idx) orelse return false;

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
        if (tokenNameAppearsInRange(tokens, eq_idx + 1, line_end, type_name)) return true;
        return false;
    }
    return false;
}

fn genericCallHasRequiredLambdaReturnTypes(
    tokens: []const lexer.Token,
    func: FuncShape,
    call: CallShape,
) bool {
    for (func.param_shapes, 0..) |param, param_idx| {
        const param_type = switch (param) {
            .value => |value_type| value_type orelse continue,
            .variadic => |value_type| value_type orelse continue,
            else => continue,
        };
        if (!typeConstraintFuncReturnHasTypeParam(tokens, func.start_idx, param_type)) continue;
        if (param_idx >= call.arg_shapes.len) return false;

        switch (call.arg_shapes[param_idx]) {
            .lambda => |lambda| if (lambda.return_type == null) return false,
            else => {},
        }
    }
    return true;
}

fn hasPriorDirectTypeParam(func: FuncShape, before_param_idx: usize, type_name: []const u8) bool {
    var i: usize = 0;
    while (i < before_param_idx) : (i += 1) {
        const prior = switch (func.param_shapes[i]) {
            .value => |value_type| value_type orelse continue,
            .variadic => |value_type| value_type orelse continue,
            else => continue,
        };
        if (std.mem.eql(u8, prior, type_name)) return true;
    }
    return false;
}

fn callHasKnownArgForDirectTypeParam(
    tokens: []const lexer.Token,
    func: FuncShape,
    call: CallShape,
    type_name: []const u8,
) bool {
    for (func.param_shapes, 0..) |param, param_idx| {
        const param_type = switch (param) {
            .value => |value_type| value_type orelse continue,
            .variadic => |value_type| value_type orelse continue,
            else => continue,
        };
        if (!std.mem.eql(u8, param_type, type_name)) continue;
        if (param_idx >= call.arg_shapes.len) return false;

        const arg_name = switch (call.arg_shapes[param_idx]) {
            .ident => |ident| ident,
            else => continue,
        };
        if (hasKnownValueTypeBefore(tokens, call.start_idx, arg_name)) return true;
    }
    return false;
}

fn hasKnownValueTypeBefore(tokens: []const lexer.Token, before_idx: usize, name: []const u8) bool {
    if (findNearestValueTypeName(tokens, before_idx, name) != null) return true;
    return findEnclosingFuncParamTypeName(tokens, before_idx, name) != null;
}

fn isFuncTypeParam(tokens: []const lexer.Token, func_start_idx: usize, name: []const u8) bool {
    const block_start = findConstraintBlockStartBefore(tokens, func_start_idx) orelse return false;

    var i = block_start;
    while (i < func_start_idx) {
        if (!tokEq(tokens[i], "#")) {
            i += 1;
            continue;
        }
        const line_end = findLineEndIdx(tokens, i);
        const is_func_constraint = i + 2 < line_end and tokEq(tokens[i + 2], "(");
        if (!is_func_constraint and i + 1 < line_end and std.mem.eql(u8, tokens[i + 1].lexeme, name)) {
            return true;
        }
        i = line_end;
    }
    return false;
}

fn typeConstraintFuncReturnHasTypeParam(
    tokens: []const lexer.Token,
    func_start_idx: usize,
    constraint_name: []const u8,
) bool {
    const block_start = findConstraintBlockStartBefore(tokens, func_start_idx) orelse return false;

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
        if (eq_idx + 1 >= line_end or !tokEq(tokens[eq_idx + 1], "(")) return false;
        const close_params = findMatching(tokens, eq_idx + 1, "(", ")") catch return false;
        if (!isReturnArrowAt(tokens, close_params + 1)) return false;

        var ret_idx = close_params + 3;
        while (ret_idx < line_end) : (ret_idx += 1) {
            if (tokens[ret_idx].kind != .ident) continue;
            if (isFuncTypeParam(tokens, func_start_idx, tokens[ret_idx].lexeme)) return true;
        }
        return false;
    }
    return false;
}

fn typeConstraintIsFunctionType(
    tokens: []const lexer.Token,
    func_start_idx: usize,
    constraint_name: []const u8,
) bool {
    const block_start = findConstraintBlockStartBefore(tokens, func_start_idx) orelse return false;

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
        if (eq_idx + 1 >= line_end or !tokEq(tokens[eq_idx + 1], "(")) return false;
        const close_params = findMatching(tokens, eq_idx + 1, "(", ")") catch return false;
        return isReturnArrowAt(tokens, close_params + 1);
    }
    return false;
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

        const line_start = lineStartIdx(tokens, prev_idx);
        if (!tokEq(tokens[line_start], "#")) break;

        block_start = line_start;
        scan_idx = line_start;
        expected_line = prev_line;
    }

    return block_start;
}

fn lineStartIdx(tokens: []const lexer.Token, idx: usize) usize {
    var out = idx;
    while (out > 0 and tokens[out - 1].line == tokens[idx].line) : (out -= 1) {}
    return out;
}

fn countFuncsByName(funcs: []const FuncShape, name: []const u8) usize {
    var count: usize = 0;
    for (funcs) |func| {
        if (std.mem.eql(u8, func.name, name)) count += 1;
    }
    return count;
}

fn countLambdaParams(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
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

fn parseTypeNameList(
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

fn parseLambdaParamTypeList(
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

fn lambdaParamTypeName(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    if (start_idx + 1 >= end_idx) return null;
    return simpleTypeName(tokens, start_idx + 1, end_idx);
}

fn compactTypeName(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize) !?[]const u8 {
    if (start_idx + 1 == end_idx and tokens[start_idx].kind == .ident) {
        return try allocator.dupe(u8, tokens[start_idx].lexeme);
    }
    if (validateIsTypeExpr(tokens, start_idx, end_idx) != end_idx) return null;

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        try out.appendSlice(allocator, tokens[i].lexeme);
    }
    const owned = try out.toOwnedSlice(allocator);
    return owned;
}

fn simpleTypeName(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    if (start_idx + 1 != end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    return tokens[start_idx].lexeme;
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

fn isCallHead(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (tokens[idx].kind != .ident) return false;
    if (idx > 0 and tokEq(tokens[idx - 1], "@") and tokens[idx - 1].line == tokens[idx].line) return false;
    if (isKeyword(tokens[idx].lexeme)) return false;
    return callOpenParenIdx(tokens, idx, tokens.len) != null;
}

fn isBuiltinIntrinsicCallHead(tokens: []const lexer.Token, idx: usize) bool {
    if (idx == 0 or idx + 1 >= tokens.len) return false;
    if (tokens[idx].kind != .ident) return false;
    if (!tokEq(tokens[idx - 1], "@") or tokens[idx - 1].line != tokens[idx].line) return false;
    if (!isBuiltinCallName(tokens[idx].lexeme)) return false;
    return tokEq(tokens[idx + 1], "(");
}

fn callOpenParenIdx(tokens: []const lexer.Token, name_idx: usize, limit_idx: usize) ?usize {
    if (name_idx + 1 >= limit_idx) return null;
    if (tokEq(tokens[name_idx + 1], "(")) return name_idx + 1;
    if (!tokEq(tokens[name_idx + 1], "<")) return null;

    const close_angle = findMatchingInRange(tokens, name_idx + 1, "<", ">", limit_idx) catch return null;
    if (close_angle + 1 >= limit_idx or !tokEq(tokens[close_angle + 1], "(")) return null;
    return close_angle + 1;
}

fn isFuncConstraintHead(tokens: []const lexer.Token, idx: usize) bool {
    if (idx == 0 or !tokEq(tokens[idx - 1], "#")) return false;
    return tokens[idx - 1].line == tokens[idx].line;
}

fn isFuncDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (tokens[idx].kind != .ident) return false;
    if (!isValidFuncDeclName(tokens[idx].lexeme)) return false;
    if (isReservedFuncName(tokens[idx].lexeme)) return false;
    return tokEq(tokens[idx + 1], "(");
}

fn isStartDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (tokens[idx].kind != .ident) return false;
    return tokEq(tokens[idx], "start") and tokEq(tokens[idx + 1], "(");
}

fn publicFuncName(name: []const u8) []const u8 {
    if (name.len != 0 and name[0] == '.') return name[1..];
    return name;
}

fn lambdaParamOpen(tokens: []const lexer.Token, start_idx: usize) ?usize {
    if (start_idx >= tokens.len) return null;
    if (tokEq(tokens[start_idx], "(")) return start_idx;
    return null;
}

fn lambdaBodyStart(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
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

fn isLambdaCallArgSite(tokens: []const lexer.Token, start_idx: usize) bool {
    if (isDisallowedSetPathLambda(tokens, start_idx)) return false;
    if (start_idx == 0) return false;
    const prev = tokens[start_idx - 1];
    if (tokEq(prev, ",")) return true;
    if (!tokEq(prev, "(")) return false;
    if (start_idx < 2) return false;
    const before_prev = tokens[start_idx - 2];
    return before_prev.kind == .ident or tokEq(before_prev, ")") or tokEq(before_prev, "]");
}

fn isDisallowedSetPathLambda(tokens: []const lexer.Token, start_idx: usize) bool {
    const info = callArgInfo(tokens, start_idx) orelse return false;
    if (!std.mem.eql(u8, info.name, "set")) return false;
    return info.arg_index + 1 < info.arg_count;
}

fn collectLambdaParamNames(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ![]const []const u8 {
    var out = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    errdefer out.deinit(allocator);

    var i = start_idx;
    while (i < end_idx) {
        if (!isLambdaParamNameToken(tokens[i])) return markErrorAt(tokens, i, error.InvalidLambdaExpr);
        const name = tokens[i].lexeme;
        if (containsName(out.items, name)) return markErrorAt(tokens, i, error.InvalidLambdaExpr);
        if (isVisibleBindingOrCallableName(tokens, name, start_idx)) return markErrorAt(tokens, i, error.InvalidLambdaExpr);
        if (isVisibleLocalBindingBefore(tokens, name, start_idx)) return markErrorAt(tokens, i, error.InvalidLambdaExpr);
        try out.append(allocator, name);
        i += 1;
        if (i >= end_idx) break;

        if (tokEq(tokens[i], ",")) {
            i += 1;
            if (i >= end_idx) return markErrorAt(tokens, end_idx - 1, error.InvalidLambdaExpr);
            continue;
        }

        var depth_paren: usize = 0;
        var depth_angle: usize = 0;
        var depth_brace: usize = 0;
        while (i < end_idx) {
            if (depth_paren == 0 and depth_angle == 0 and depth_brace == 0 and tokEq(tokens[i], ",")) break;

            if (tokEq(tokens[i], "(")) {
                depth_paren += 1;
            } else if (tokEq(tokens[i], ")")) {
                if (depth_paren == 0) return markErrorAt(tokens, i, error.InvalidLambdaExpr);
                depth_paren -= 1;
            } else if (tokEq(tokens[i], "<")) {
                depth_angle += 1;
            } else if (tokEq(tokens[i], ">")) {
                if (depth_angle == 0) return markErrorAt(tokens, i, error.InvalidLambdaExpr);
                depth_angle -= 1;
            } else if (tokEq(tokens[i], "{")) {
                depth_brace += 1;
            } else if (tokEq(tokens[i], "}")) {
                if (depth_brace == 0) return markErrorAt(tokens, i, error.InvalidLambdaExpr);
                depth_brace -= 1;
            }
            i += 1;
        }

        if (depth_paren != 0 or depth_angle != 0 or depth_brace != 0) return markErrorAt(tokens, end_idx - 1, error.InvalidLambdaExpr);
        if (i < end_idx and tokEq(tokens[i], ",")) {
            i += 1;
            if (i >= end_idx) return markErrorAt(tokens, end_idx - 1, error.InvalidLambdaExpr);
        }
    }

    return out.toOwnedSlice(allocator);
}

fn isLambdaParamNameToken(tok: lexer.Token) bool {
    if (tok.kind != .ident) return false;
    if (tok.lexeme.len == 0) return false;
    if (tok.lexeme[0] == '_') return false;
    return std.ascii.isLower(tok.lexeme[0]) and !isReservedFuncName(tok.lexeme);
}

fn findLambdaCapture(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    params: []const []const u8,
) !?usize {
    var locals = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer locals.deinit(allocator);

    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        const tok = tokens[i];
        if (tok.kind != .ident) continue;
        if (tok.lexeme.len == 0) continue;
        if (tok.lexeme[0] == '.') continue;
        if (tok.lexeme[0] == '_') continue;
        if (std.ascii.isUpper(tok.lexeme[0])) continue;
        if (isKeyword(tok.lexeme)) continue;
        if (isAsScalarTypeToken(tokens, i)) continue;
        if (containsName(params, tok.lexeme)) continue;
        if (containsName(locals.items, tok.lexeme)) continue;
        if (isLambdaLocalBindName(tokens, i, start_idx)) {
            try locals.append(allocator, tok.lexeme);
            continue;
        }
        if (i + 1 < end_idx and (tokEq(tokens[i + 1], "(") or tokEq(tokens[i + 1], "{") or tokEq(tokens[i + 1], "<"))) continue;
        return i;
    }
    return null;
}

fn isLambdaLocalBindName(tokens: []const lexer.Token, idx: usize, body_start: usize) bool {
    if (!isLowerIdentName(tokens[idx].lexeme)) return false;
    if (isReservedFuncName(tokens[idx].lexeme)) return false;

    const line_start = lambdaLineStart(tokens, idx, body_start);
    const line_end = findLineEndIdx(tokens, idx);
    const eq_idx = findTopLevelAssignEqOnLine(tokens, line_start, line_end) orelse return false;
    return idx < eq_idx;
}

fn isAsScalarTypeToken(tokens: []const lexer.Token, idx: usize) bool {
    if (!isScalarAsTargetTypeName(tokens[idx].lexeme)) return false;
    const info = callArgInfo(tokens, idx) orelse return false;
    return std.mem.eql(u8, info.name, "as") and (info.arg_index == 0 or info.arg_index == 1);
}

fn lambdaLineStart(tokens: []const lexer.Token, idx: usize, body_start: usize) usize {
    var line_start = idx;
    while (line_start > body_start and tokens[line_start - 1].line == tokens[idx].line) {
        line_start -= 1;
    }
    if (line_start < idx and tokEq(tokens[line_start], "{")) return line_start + 1;
    return line_start;
}

fn containsName(names: []const []const u8, needle: []const u8) bool {
    for (names) |name| {
        if (std.mem.eql(u8, name, needle)) return true;
    }
    return false;
}

fn isVisibleBindingOrCallableName(tokens: []const lexer.Token, name: []const u8, before_idx: usize) bool {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (depth_brace == 0) {
                if (parseImportDeclEnd(tokens, i)) |next_idx| {
                    i = next_idx - 1;
                    continue;
                }
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
            if (std.mem.eql(u8, import_kind, "env") or std.mem.eql(u8, import_kind, "wasi")) return true;
            if (std.mem.eql(u8, import_kind, "lib") and (isLowerIdentName(public_name) or isReadonlyIdentName(tokens[i].lexeme))) return true;
            continue;
        }
        if (isTopLevelValueDeclStart(tokens, i)) return true;
    }
    return false;
}

fn isTopLevelValueDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    if (!isTopLevelDeclHead(tokens, idx)) return false;
    if (tokens[idx].kind != .ident) return false;
    const name = tokens[idx].lexeme;
    if (!isLowerIdentName(name) and !isReadonlyIdentName(name) and !isDotLowerIdent(name)) return false;
    if (idx + 1 >= tokens.len) return false;
    if (tokEq(tokens[idx + 1], "(") or tokEq(tokens[idx + 1], "{")) return false;
    const line_end = findLineEndIdx(tokens, idx);
    const eq_idx = findTopLevelAssignEqOnLine(tokens, idx + 1, line_end) orelse return false;
    return eq_idx > idx + 1;
}

fn isVisibleLocalBindingBefore(tokens: []const lexer.Token, name: []const u8, before_idx: usize) bool {
    if (findEnclosingFuncParamTypeName(tokens, before_idx, name) != null) return true;

    var scopes = [_]bool{false} ** 128;
    var depth: usize = 0;
    var i: usize = 0;
    while (i < before_idx and i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (depth + 1 < scopes.len) depth += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth > 0) {
                scopes[depth] = false;
                depth -= 1;
            }
            continue;
        }
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, tokens[i].lexeme, name)) continue;
        if (!isLocalBindingIntroducer(tokens, i)) continue;
        scopes[depth] = true;
    }
    var d = depth + 1;
    while (d > 0) {
        d -= 1;
        if (scopes[d]) return true;
    }
    return false;
}

fn isLocalBindingIntroducer(tokens: []const lexer.Token, idx: usize) bool {
    if (idx >= tokens.len) return false;
    if (!isLowerIdentName(tokens[idx].lexeme)) return false;
    if (isReservedFuncName(tokens[idx].lexeme)) return false;
    const line_start = lineStartIdx(tokens, idx);
    if (line_start >= tokens.len) return false;
    if (isTopLevelToken(tokens, line_start) and isTopLevelDeclHead(tokens, line_start)) return false;
    if (tokEq(tokens[line_start], "loop")) return false;
    const line_end = findLineEndIdx(tokens, idx);
    const eq_idx = findTopLevelAssignEqOnLine(tokens, line_start, line_end) orelse return false;
    if (idx >= eq_idx) return false;
    if (idx == line_start and eq_idx > idx + 1) return true;
    return false;
}

fn isArrowAt(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 1 < tokens.len and tokEq(tokens[idx], "=") and tokEq(tokens[idx + 1], ">");
}

fn isReturnArrowAt(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 1 < tokens.len and tokEq(tokens[idx], "-") and tokEq(tokens[idx + 1], ">");
}

fn rootExprStartTok(program: parser.Program, root_idx: usize) usize {
    if (root_idx >= program.expr_nodes.len) return 0;
    const node = program.expr_nodes[root_idx];
    return switch (node.kind) {
        .paren => rootExprStartTok(program, node.data.child),
        else => node.start_tok,
    };
}

fn classifyKnownBool(
    allocator: std.mem.Allocator,
    program: parser.Program,
    funcs: []const FuncShape,
    tokens: []const lexer.Token,
    root_idx: usize,
) !KnownBool {
    if (root_idx >= program.expr_nodes.len) return .unknown;
    const node = program.expr_nodes[root_idx];

    return switch (node.kind) {
        .paren => try classifyKnownBool(allocator, program, funcs, tokens, node.data.child),
        .literal => classifyLiteralBool(tokens, node.start_tok),
        .ident => classifyTypedIdentBool(tokens, node.start_tok),
        .call => try classifyCallBool(allocator, funcs, tokens, node),
        .lambda,
        .inferred_agg_lit,
        .struct_lit,
        => .no,
    };
}

fn classifyLiteralBool(tokens: []const lexer.Token, tok_idx: usize) KnownBool {
    if (tok_idx >= tokens.len) return .unknown;
    if (tokEq(tokens[tok_idx], "true") or tokEq(tokens[tok_idx], "false")) return .yes;
    return .no;
}

fn classifyTypedIdentBool(tokens: []const lexer.Token, ident_tok_idx: usize) KnownBool {
    if (ident_tok_idx >= tokens.len) return .unknown;
    const name = tokens[ident_tok_idx].lexeme;
    const typed = findNearestTypedBinding(tokens, ident_tok_idx, name) orelse return .unknown;
    return if (typed) .yes else .no;
}

fn findNearestTypedBinding(tokens: []const lexer.Token, ident_tok_idx: usize, name: []const u8) ?bool {
    var skip_depth: usize = 0;
    var i = ident_tok_idx;
    while (i > 0) {
        i -= 1;

        if (tokEq(tokens[i], "}")) {
            skip_depth += 1;
            continue;
        }
        if (tokEq(tokens[i], "{")) {
            if (skip_depth > 0) {
                skip_depth -= 1;
            }
            continue;
        }
        if (skip_depth != 0) continue;
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, tokens[i].lexeme, name)) continue;

        if (typedBindingBool(tokens, i)) |is_bool| return is_bool;
    }
    return null;
}

fn typedBindingBool(tokens: []const lexer.Token, name_idx: usize) ?bool {
    if (name_idx + 2 >= tokens.len) return null;
    const line_end = findLineEndIdx(tokens, name_idx);
    if (line_end <= name_idx + 1) return null;

    const eq_idx = findTopLevelAssignEqOnLine(tokens, name_idx + 1, line_end) orelse return null;
    if (eq_idx == name_idx + 1) return inferBoolFromAssignmentRhs(tokens, name_idx, eq_idx + 1, line_end);
    return isBoolTypeSpec(tokens, name_idx + 1, eq_idx);
}

fn inferBoolFromAssignmentRhs(tokens: []const lexer.Token, name_idx: usize, rhs_start: usize, line_end: usize) ?bool {
    if (rhs_start + 5 > line_end) return null;
    if (!tokEq(tokens[rhs_start], "get")) return null;
    if (!tokEq(tokens[rhs_start + 1], "(")) return null;
    if (tokens[rhs_start + 2].kind != .ident) return null;
    if (!tokEq(tokens[rhs_start + 3], ",")) return null;
    if (tokens[rhs_start + 4].kind != .ident) return null;
    if (tokens[rhs_start + 4].lexeme.len < 2 or tokens[rhs_start + 4].lexeme[0] != '.') return null;
    if (rhs_start + 6 != line_end or !tokEq(tokens[rhs_start + 5], ")")) return null;

    const source_name = tokens[rhs_start + 2].lexeme;
    const source_type = findNearestValueTypeName(tokens, name_idx, source_name) orelse return null;
    return findStructFieldBoolType(tokens, source_type, tokens[rhs_start + 4].lexeme[1..]);
}

fn findNearestValueTypeName(tokens: []const lexer.Token, before_idx: usize, name: []const u8) ?[]const u8 {
    var skip_depth: usize = 0;
    var i = before_idx;
    while (i > 0) {
        i -= 1;

        if (tokEq(tokens[i], "}")) {
            skip_depth += 1;
            continue;
        }
        if (tokEq(tokens[i], "{")) {
            if (skip_depth > 0) skip_depth -= 1;
            continue;
        }
        if (skip_depth != 0) continue;
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, tokens[i].lexeme, name)) continue;

        const line_end = findLineEndIdx(tokens, i);
        const eq_idx = findTopLevelAssignEqOnLine(tokens, i + 1, line_end) orelse continue;
        if (eq_idx > i + 1 and tokens[i + 1].kind == .ident and isValueTypeName(tokens[i + 1].lexeme)) return tokens[i + 1].lexeme;
        if (eq_idx > i + 1 and tokens[i + 1].kind == .ident and isGenericTypeStart(tokens, i + 1, eq_idx)) return tokens[i + 1].lexeme;
        if (tokens[eq_idx + 1].kind == .ident and eq_idx + 2 < line_end and tokEq(tokens[eq_idx + 2], "{")) return tokens[eq_idx + 1].lexeme;
    }
    return null;
}

fn findEnclosingFuncParamTypeName(tokens: []const lexer.Token, before_idx: usize, name: []const u8) ?[]const u8 {
    var skip_depth: usize = 0;
    var i = before_idx;
    while (i > 0) {
        i -= 1;

        if (tokEq(tokens[i], "}")) {
            skip_depth += 1;
            continue;
        }
        if (!tokEq(tokens[i], "{")) continue;
        if (skip_depth > 0) {
            skip_depth -= 1;
            continue;
        }
        if (findFuncParamTypeNameBeforeBody(tokens, i, name)) |type_name| return type_name;
    }
    return null;
}

fn findFuncParamTypeNameBeforeBody(
    tokens: []const lexer.Token,
    body_open_idx: usize,
    name: []const u8,
) ?[]const u8 {
    const line_start = lineStartIdx(tokens, body_open_idx);
    if (line_start >= body_open_idx) return null;
    if (!isFuncDeclStart(tokens, line_start)) return null;

    const close_paren = findMatching(tokens, line_start + 1, "(", ")") catch return null;
    if (close_paren >= body_open_idx) return null;
    return findParamTypeName(tokens, line_start + 2, close_paren, name);
}

fn findParamTypeName(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    name: []const u8,
) ?[]const u8 {
    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !isTopLevelCommaAny(tokens, i, start_idx, end_idx)) continue;
        if (seg_start + 1 < i and tokens[seg_start].kind == .ident and std.mem.eql(u8, tokens[seg_start].lexeme, name)) {
            if (tokens[seg_start + 1].kind == .ident) return tokens[seg_start + 1].lexeme;
        }
        seg_start = i + 1;
    }
    return null;
}

fn isGenericTypeStart(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 1 >= end_idx or !tokEq(tokens[start_idx + 1], "<")) return false;
    _ = findMatching(tokens, start_idx + 1, "<", ">") catch return false;
    return true;
}

fn findStructFieldBoolType(tokens: []const lexer.Token, type_name: []const u8, field_name: []const u8) ?bool {
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
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, publicTypeName(tokens[i].lexeme), type_name)) continue;
        if (i + 1 >= tokens.len or !tokEq(tokens[i + 1], "{")) continue;

        const close_idx = findMatching(tokens, i + 1, "{", "}") catch return null;
        return findFieldBoolType(tokens, i + 2, close_idx, field_name);
    }
    return null;
}

fn findFieldBoolType(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, field_name: []const u8) ?bool {
    var i = start_idx;
    while (i < end_idx) {
        if (tokens[i].kind != .ident) {
            i += 1;
            continue;
        }
        const name = if (tokens[i].lexeme.len != 0 and tokens[i].lexeme[0] == '.') tokens[i].lexeme[1..] else tokens[i].lexeme;
        const type_start = i + 1;
        const line_end = @min(findLineEndIdx(tokens, i), end_idx);
        const type_end = findTopLevelAssignEqOnLine(tokens, type_start, line_end) orelse line_end;
        if (std.mem.eql(u8, name, field_name)) return isBoolTypeSpec(tokens, type_start, type_end);
        i = line_end;
    }
    return null;
}

fn isDeclaredTypeName(name: []const u8) bool {
    return name.len != 0 and std.ascii.isUpper(name[0]);
}

fn isValueTypeName(name: []const u8) bool {
    return isDeclaredTypeName(name) or isBaseTypeName(name);
}

fn publicTypeName(name: []const u8) []const u8 {
    if (name.len != 0 and name[0] == '.') return name[1..];
    return name;
}

fn findLineEndIdx(tokens: []const lexer.Token, start_idx: usize) usize {
    if (start_idx >= tokens.len) return start_idx;
    const line = tokens[start_idx].line;
    var i = start_idx;
    while (i < tokens.len and tokens[i].line == line) : (i += 1) {}
    return i;
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
        if (depth_paren != 0 or depth_brace != 0 or depth_angle != 0) continue;
        if (!tokEq(tokens[i], "=")) continue;
        if (isNonAssignEqual(tokens, i)) continue;
        return i;
    }
    return null;
}

fn findTopLevelAssignEq(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    return findTopLevelAssignEqOnLine(tokens, start_idx, end_idx);
}

fn isBoolTypeSpec(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    return end_idx == start_idx + 1 and tokEq(tokens[start_idx], "bool");
}

fn checkPathIndexSegments(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tokEq(tokens[i], "get") and !tokEq(tokens[i], "set")) continue;
        if (i + 1 >= tokens.len or !tokEq(tokens[i + 1], "(")) continue;
        const close_paren = findMatching(tokens, i + 1, "(", ")") catch continue;
        try checkPathArgIndexSegments(tokens, i + 2, close_paren);
        i = close_paren;
    }
}

fn checkDirectPathSource(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tokEq(tokens[i], "get") and !tokEq(tokens[i], "set")) continue;
        if (i + 1 >= tokens.len or !tokEq(tokens[i + 1], "(")) continue;
        const close_paren = findMatching(tokens, i + 1, "(", ")") catch continue;
        const first_arg = firstNonGap(tokens, i + 2, close_paren) orelse continue;
        if (first_arg >= close_paren or tokens[first_arg].kind != .ident) continue;
        const source_type = findNearestValueTypeName(tokens, i, tokens[first_arg].lexeme) orelse continue;
        if ((std.mem.eql(u8, source_type, "List") or std.mem.eql(u8, source_type, "HashMap")) and
            !hasLocalStructDecl(tokens, source_type))
        {
            return markErrorAt(tokens, first_arg, error.InvalidPathAccess);
        }
        i = close_paren;
    }
}

fn hasLocalStructDecl(tokens: []const lexer.Token, name: []const u8) bool {
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
        if (!isTopLevelDeclHead(tokens, i)) continue;
        if (!std.mem.eql(u8, publicTypeName(tokens[i].lexeme), name)) continue;
        if (i + 1 < tokens.len and tokEq(tokens[i + 1], "{")) return true;
    }
    return false;
}

fn checkPathArgIndexSegments(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) !void {
    const path_start = findPathArgStart(tokens, start_idx, end_idx) orelse return;
    if (path_start + 1 >= end_idx or !tokEq(tokens[path_start], ".") or !tokEq(tokens[path_start + 1], "{")) return;
    const path_close = findMatching(tokens, path_start + 1, "{", "}") catch return markErrorAt(tokens, path_start, error.InvalidPathIndex);
    if (isLegacyPathList(tokens, path_start + 2, path_close)) {
        return markErrorAt(tokens, path_start, error.InvalidPathIndex);
    }
}

fn findPathArgStart(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var comma_count: usize = 0;
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
        if (!tokEq(tokens[i], ",")) continue;

        comma_count += 1;
        if (comma_count == 1) return i + 1;
    }
    return null;
}

fn isLegacyPathList(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (isTopLevelPathFieldInit(tokens, i, start_idx, end_idx)) return false;
    }
    return true;
}

fn isTopLevelPathFieldInit(tokens: []const lexer.Token, eq_idx: usize, start_idx: usize, end_idx: usize) bool {
    if (!tokEq(tokens[eq_idx], "=")) return false;

    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < eq_idx and i < end_idx) : (i += 1) {
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

fn classifyCallBool(
    allocator: std.mem.Allocator,
    funcs: []const FuncShape,
    tokens: []const lexer.Token,
    node: parser.ExprNode,
) !KnownBool {
    const call = node.data.call;
    if (isBuiltinBoolCall(call.func_name)) return .yes;

    const call_start = node.start_tok;
    const open_paren = callOpenParenIdx(tokens, call_start, node.end_tok) orelse return .unknown;

    const args_start = open_paren + 1;
    const args_end = node.end_tok - 1;
    const args = try parseCallArgShapes(allocator, tokens, args_start, args_end);
    defer freeCallArgShapes(allocator, args);

    var matched_fixed_count: usize = 0;
    var fixed_return_type: ?[]const u8 = null;
    var best_variadic_min: ?usize = null;
    var best_variadic_count: usize = 0;
    var variadic_return_type: ?[]const u8 = null;

    for (funcs) |func| {
        if (!std.mem.eql(u8, func.name, call.func_name)) continue;
        if (!callArityCompatibleWithFunc(func, args.len)) continue;
        if (!conditionCallArgsMatchFunc(tokens, func, args, call_start)) continue;
        if (func.param_max != null) {
            matched_fixed_count += 1;
            fixed_return_type = func.return_type;
        } else {
            if (best_variadic_min == null or func.param_min > best_variadic_min.?) {
                best_variadic_min = func.param_min;
                best_variadic_count = 1;
                variadic_return_type = func.return_type;
            } else if (func.param_min == best_variadic_min.?) {
                best_variadic_count += 1;
            }
        }
    }

    if (matched_fixed_count > 1) return .no_matching_call;
    if (matched_fixed_count == 1) {
        const return_type = fixed_return_type orelse return .no;
        return if (std.mem.eql(u8, return_type, "bool")) .yes else .no;
    }
    if (best_variadic_min == null) return .unknown;
    if (best_variadic_count > 1) return .no_matching_call;
    const return_type = variadic_return_type orelse return .no;
    return if (std.mem.eql(u8, return_type, "bool")) .yes else .no;
}

fn callArityCompatibleWithFunc(func: FuncShape, arg_count: usize) bool {
    if (arg_count < func.param_min) return false;
    if (func.param_max) |max_count| return arg_count <= max_count;
    return true;
}

fn conditionCallArgsMatchFunc(
    tokens: []const lexer.Token,
    func: FuncShape,
    args: []const CallArgShape,
    call_start: usize,
) bool {
    for (args, 0..) |arg, arg_index| {
        if (arg_index >= func.param_shapes.len) return false;
        switch (func.param_shapes[arg_index]) {
            .other => continue,
            .func => continue,
            .value => |param_type| {
                const expected = param_type orelse continue;
                const actual = conditionCallArgValueType(tokens, arg, call_start) orelse continue;
                if (!std.mem.eql(u8, actual, expected)) return false;
            },
            .variadic => |param_type| {
                const expected = param_type orelse continue;
                const actual = conditionCallArgValueType(tokens, arg, call_start) orelse continue;
                if (!std.mem.eql(u8, actual, expected)) return false;
            },
        }
    }
    return true;
}

fn conditionCallArgValueType(tokens: []const lexer.Token, arg: CallArgShape, call_start: usize) ?[]const u8 {
    return switch (arg) {
        .ident => |name| findNearestValueTypeName(tokens, call_start, name),
        else => null,
    };
}

fn isBuiltinBoolCall(name: []const u8) bool {
    const builtin = [_][]const u8{
        "is",
        "eq",
        "ne",
        "lt",
        "le",
        "gt",
        "ge",
        "and",
        "or",
        "not",
    };
    for (builtin) |it| {
        if (std.mem.eql(u8, it, name)) return true;
    }
    return false;
}

fn findDirectCallAtRoot(program: parser.Program, root_idx: usize) ?DirectCallSite {
    if (root_idx >= program.expr_nodes.len) return null;
    const node = program.expr_nodes[root_idx];

    return switch (node.kind) {
        .call => .{
            .call = node.data.call,
            .start_tok_idx = node.start_tok,
        },
        else => null,
    };
}

fn rootExprReturnArity(program: parser.Program, root_idx: usize) ReturnArityResolve {
    if (root_idx >= program.expr_nodes.len) return .{ .arity = 1 };
    const node = program.expr_nodes[root_idx];

    return switch (node.kind) {
        .call => resolveCallReturnArity(
            program.func_sigs,
            node.data.call.func_name,
            node.data.call.arg_count,
        ),
        else => .{ .arity = 1 },
    };
}

const ReturnArityResolve = union(enum) {
    unknown,
    arity: usize,
    ambiguous,
};

fn resolveCallReturnArity(
    func_sigs: []const parser.FuncSig,
    func_name: []const u8,
    arg_count: usize,
) ReturnArityResolve {
    var matched_arity: ?usize = null;

    for (func_sigs) |sig| {
        if (!std.mem.eql(u8, sig.name, func_name)) continue;
        if (!isArgCountCompatible(sig, arg_count)) continue;

        if (matched_arity) |arity| {
            if (arity != sig.return_arity) return .ambiguous;
            continue;
        }
        matched_arity = sig.return_arity;
    }

    if (matched_arity) |arity| return .{ .arity = arity };
    return .unknown;
}

fn valueExprAllowsArityAt(program: parser.Program, start_tok: usize, arity: usize) bool {
    for (program.value_exprs) |site| {
        if (site.expected_arity != arity) continue;
        if (site.context != .assign and site.context != .return_value) continue;
        if (!rootExprMatchesCallStart(program, site.root_expr_idx, start_tok)) continue;
        return true;
    }
    return false;
}

fn rootExprMatchesCallStart(program: parser.Program, root_idx: usize, start_tok: usize) bool {
    if (root_idx >= program.expr_nodes.len) return false;
    const node = program.expr_nodes[root_idx];
    return switch (node.kind) {
        .call => node.start_tok == start_tok,
        else => false,
    };
}

fn isArgCountCompatible(sig: parser.FuncSig, arg_count: usize) bool {
    if (arg_count < sig.param_min) return false;
    if (sig.param_max) |max_count| {
        return arg_count <= max_count;
    }
    return true;
}

fn parseImportDeclEnd(tokens: []const lexer.Token, start_idx: usize) ?usize {
    const eq_idx = topLevelLineAssignIdx(tokens, start_idx) orelse return null;
    const at_idx = eq_idx + 1;
    if (at_idx + 2 >= tokens.len or !tokEq(tokens[at_idx], "@")) return null;
    if (tokens[at_idx + 1].kind != .ident) return null;
    if (!tokEq(tokens[at_idx + 2], "(")) return null;
    const close_paren = findMatching(tokens, at_idx + 2, "(", ")") catch return null;
    return close_paren + 1;
}

fn findMatching(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8) !usize {
    return findMatchingInRange(tokens, open_idx, open, close, tokens.len);
}

fn findMatchingInRange(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8, limit: usize) !usize {
    if (open_idx >= tokens.len or !tokEq(tokens[open_idx], open)) return error.InvalidGroupStart;

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

fn checkTypeDeclNaming(tokens: []const lexer.Token) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (depth_brace == 0) {
                if (parseImportDeclEnd(tokens, i)) |next_idx| {
                    i = next_idx - 1;
                    continue;
                }
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
        if (!isTypeDeclStart(tokens, i)) continue;
        if ((isErrorTypeName(t.lexeme) or isPrivateErrorTypeName(t.lexeme)) and isStructDeclStart(tokens, i)) {
            return markErrorAt(tokens, i, error.InvalidTypeDeclName);
        }
        if (isValidDeclaredTypeName(t.lexeme)) continue;
        return markErrorAt(tokens, i, error.InvalidTypeDeclName);
    }
}

fn isStructDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 1 < tokens.len and tokEq(tokens[idx + 1], "{");
}

fn checkTypeDeclNameConflicts(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
    var seen = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer seen.deinit(allocator);

    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (depth_brace == 0) {
                if (parseImportDeclEnd(tokens, i)) |next_idx| {
                    i = next_idx - 1;
                    continue;
                }
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
        if (!isTypeDeclStart(tokens, i)) continue;
        if (!isValidDeclaredTypeName(tokens[i].lexeme)) continue;

        const name = publicTypeName(tokens[i].lexeme);
        for (seen.items) |prev| {
            if (std.mem.eql(u8, prev, name)) {
                return markErrorAt(tokens, i, error.DuplicateTypeDeclName);
            }
        }
        try seen.append(allocator, name);
    }
}

fn checkErrorDeclBranches(tokens: []const lexer.Token) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (depth_brace == 0) {
                if (parseImportDeclEnd(tokens, i)) |next_idx| {
                    i = next_idx - 1;
                    continue;
                }
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
        if (isPrivateErrorTypeName(tokens[i].lexeme) and i + 1 < tokens.len and
            (tokEq(tokens[i + 1], "=") or tokEq(tokens[i + 1], "error")))
        {
            return markErrorAt(tokens, i, error.InvalidErrorBranchName);
        }
        if (isErrorTypeName(tokens[i].lexeme)) {
            if (!isErrorEnumDeclStart(tokens, i)) {
                if (isTypeDeclStart(tokens, i)) return markErrorAt(tokens, i, error.InvalidErrorBranchName);
                continue;
            }

            try validateErrorEnumBranches(tokens, i, i + 3);
            i = findLineEndIdx(tokens, i) - 1;
            continue;
        }
        if (isValueEnumDeclStart(tokens, i)) {
            try validateValueEnumBranches(tokens, i, i + 3);
            i = findLineEndIdx(tokens, i) - 1;
            continue;
        }
    }
}

fn validateErrorEnumBranches(tokens: []const lexer.Token, enum_idx: usize, start_idx: usize) !void {
    const line_end = findLineEndIdx(tokens, enum_idx);
    var expect_branch = true;
    var j = start_idx;
    while (j < line_end) : (j += 1) {
        if (!expect_branch) {
            if (!tokEq(tokens[j], "|")) return markErrorAt(tokens, j, error.InvalidErrorBranchName);
            expect_branch = true;
            continue;
        }
        if (!isValidErrorBranchName(tokens[j])) return markErrorAt(tokens, j, error.InvalidErrorBranchName);
        if (hasVisibleEnumBranchNameConflict(tokens, j, publicTypeName(tokens[j].lexeme))) {
            return markErrorAt(tokens, j, error.InvalidErrorBranchName);
        }
        expect_branch = false;
    }
    if (expect_branch) return markErrorAt(tokens, line_end - 1, error.InvalidErrorBranchName);
}

fn validateValueEnumBranches(tokens: []const lexer.Token, enum_idx: usize, start_idx: usize) !void {
    const line_end = findLineEndIdx(tokens, enum_idx);
    var expect_branch = true;
    var j = start_idx;
    while (j < line_end) {
        if (!expect_branch) {
            if (!tokEq(tokens[j], "|")) return markErrorAt(tokens, j, error.InvalidErrorBranchName);
            expect_branch = true;
            j += 1;
            continue;
        }
        if (!isValidEnumBranchName(tokens[j])) return markErrorAt(tokens, j, error.InvalidErrorBranchName);
        if (hasPriorEnumBranchName(tokens, start_idx, j, publicTypeName(tokens[j].lexeme))) {
            return markErrorAt(tokens, j, error.InvalidErrorBranchName);
        }
        if (hasVisibleEnumBranchNameConflict(tokens, j, publicTypeName(tokens[j].lexeme))) {
            return markErrorAt(tokens, j, error.InvalidErrorBranchName);
        }
        if (j + 4 > line_end or !tokEq(tokens[j + 1], "(") or !tokEq(tokens[j + 3], ")")) {
            return markErrorAt(tokens, j, error.InvalidErrorBranchName);
        }
        if (tokens[j + 2].kind != .number) return markErrorAt(tokens, j + 2, error.InvalidErrorBranchName);
        const value = parseEnumCarrierValue(tokens[j + 2].lexeme) orelse return markErrorAt(tokens, j + 2, error.InvalidErrorBranchName);
        if (!enumCarrierValueInRange(tokens[enum_idx + 1].lexeme, value)) {
            return markErrorAt(tokens, j + 2, error.InvalidErrorBranchName);
        }
        if (hasPriorEnumCarrierValue(tokens, start_idx, j, value)) {
            return markErrorAt(tokens, j + 2, error.InvalidErrorBranchName);
        }
        j += 4;
        expect_branch = false;
    }
    if (expect_branch) return markErrorAt(tokens, line_end - 1, error.InvalidErrorBranchName);
}

fn hasPriorEnumBranchName(tokens: []const lexer.Token, start_idx: usize, before_idx: usize, name: []const u8) bool {
    var j = start_idx;
    while (j < before_idx) : (j += 1) {
        if (tokens[j].kind != .ident) continue;
        if (!std.mem.eql(u8, publicTypeName(tokens[j].lexeme), name)) continue;
        return true;
    }
    return false;
}

fn hasVisibleEnumBranchNameConflict(tokens: []const lexer.Token, branch_idx: usize, name: []const u8) bool {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (depth_brace == 0) {
                if (parseImportDeclEnd(tokens, i)) |next_idx| {
                    i = next_idx - 1;
                    continue;
                }
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

        if (isModernImportAssign(tokens, i)) {
            if (isValidDeclaredTypeName(tokens[i].lexeme) and std.mem.eql(u8, publicTypeName(tokens[i].lexeme), name)) {
                return true;
            }
            i = (parseImportDeclEnd(tokens, i) orelse findLineEndIdx(tokens, i)) - 1;
            continue;
        }

        if (isTypeDeclStart(tokens, i) and isValidDeclaredTypeName(tokens[i].lexeme)) {
            if (std.mem.eql(u8, publicTypeName(tokens[i].lexeme), name)) return true;
        }

        if (!isErrorEnumDeclStart(tokens, i) and !isValueEnumDeclStart(tokens, i)) continue;
        if (enumDeclHasPriorBranch(tokens, i, branch_idx, name)) return true;
        i = findLineEndIdx(tokens, i) - 1;
    }
    return false;
}

fn enumDeclHasPriorBranch(tokens: []const lexer.Token, line_start_idx: usize, branch_idx: usize, name: []const u8) bool {
    const eq_idx = enumDeclAssignIdx(tokens, line_start_idx) orelse return false;
    const line_end = findLineEndIdx(tokens, line_start_idx);

    var i = eq_idx + 1;
    var expect_branch = true;
    while (i < line_end) : (i += 1) {
        if (!expect_branch) {
            if (tokEq(tokens[i], "|")) expect_branch = true;
            continue;
        }
        if (tokens[i].kind != .ident) continue;
        if (i >= branch_idx) return false;
        if (std.mem.eql(u8, publicTypeName(tokens[i].lexeme), name)) return true;
        expect_branch = false;
    }
    return false;
}

fn hasPriorEnumCarrierValue(tokens: []const lexer.Token, start_idx: usize, before_idx: usize, value: i128) bool {
    var j = start_idx;
    while (j + 3 < before_idx) {
        if (tokens[j].kind == .ident and tokEq(tokens[j + 1], "(") and tokens[j + 2].kind == .number and tokEq(tokens[j + 3], ")")) {
            if (parseEnumCarrierValue(tokens[j + 2].lexeme)) |prev| {
                if (prev == value) return true;
            }
            j += 4;
            continue;
        }
        j += 1;
    }
    return false;
}

fn parseEnumCarrierValue(raw: []const u8) ?i128 {
    return std.fmt.parseInt(i128, raw, 10) catch null;
}

fn enumCarrierValueInRange(carrier: []const u8, value: i128) bool {
    if (std.mem.eql(u8, carrier, "i8")) return value >= -128 and value <= 127;
    if (std.mem.eql(u8, carrier, "i16")) return value >= -32768 and value <= 32767;
    if (std.mem.eql(u8, carrier, "i32")) return value >= -2147483648 and value <= 2147483647;
    if (std.mem.eql(u8, carrier, "isize")) return value >= -2147483648 and value <= 2147483647;
    if (std.mem.eql(u8, carrier, "i64")) {
        return value >= -9223372036854775808 and value <= 9223372036854775807;
    }
    if (std.mem.eql(u8, carrier, "u8")) return value >= 0 and value <= 255;
    if (std.mem.eql(u8, carrier, "u16")) return value >= 0 and value <= 65535;
    if (std.mem.eql(u8, carrier, "u32")) return value >= 0 and value <= 4294967295;
    if (std.mem.eql(u8, carrier, "usize")) return value >= 0 and value <= 4294967295;
    if (std.mem.eql(u8, carrier, "u64")) return value >= 0 and value <= 18446744073709551615;
    return false;
}

fn isErrorEnumDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 2 < tokens.len and
        isErrorTypeName(tokens[idx].lexeme) and
        tokEq(tokens[idx + 1], "error") and
        tokEq(tokens[idx + 2], "=");
}

fn isValueEnumDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 2 < tokens.len and
        isValidDeclaredTypeName(tokens[idx].lexeme) and
        !isErrorTypeName(tokens[idx].lexeme) and
        isBaseIntTypeName(tokens[idx + 1].lexeme) and
        tokEq(tokens[idx + 2], "=");
}

fn isLocalUnionAlias(tokens: []const lexer.Token, name: []const u8) bool {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (depth_brace == 0) {
                if (parseImportDeclEnd(tokens, i)) |next_idx| {
                    i = next_idx - 1;
                    continue;
                }
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
        if (isErrorEnumDeclStart(tokens, i) or isValueEnumDeclStart(tokens, i)) return false;
        const line_end = findLineEndIdx(tokens, i);
        const eq_idx = findTopLevelAssignEqOnLine(tokens, i + 1, line_end) orelse return false;
        return findTokenOnLine(tokens, eq_idx + 1, line_end, "|") != null;
    }
    return false;
}

fn isValidErrorBranchName(tok: lexer.Token) bool {
    if (tok.kind != .ident) return false;
    if (!isValidDeclaredTypeName(tok.lexeme)) return false;
    if (std.mem.eql(u8, tok.lexeme, "Error")) return false;
    if (isErrorTypeName(tok.lexeme)) return false;
    return true;
}

fn isValidEnumBranchName(tok: lexer.Token) bool {
    if (tok.kind != .ident) return false;
    const name = publicTypeName(tok.lexeme);
    if (!isValidDeclaredTypeName(name)) return false;
    if (std.mem.eql(u8, name, "Error")) return false;
    if (isErrorTypeName(name)) return false;
    return true;
}

fn isErrorTypeName(name: []const u8) bool {
    if (name.len == 0 or name[0] == '.') return false;
    if (!isValidDeclaredTypeName(name)) return false;
    if (std.mem.eql(u8, name, "Error")) return false;
    return std.mem.endsWith(u8, name, "Error");
}

fn isPrivateErrorTypeName(name: []const u8) bool {
    if (name.len < 2 or name[0] != '.') return false;
    return isErrorTypeName(name[1..]);
}

fn checkSynthErrorTypePositions(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, tokens[i].lexeme, "Error")) continue;

        const line_start = lineStartIdx(tokens, i);
        if (line_start == i and isModernImportAssign(tokens, i)) {
            i = findLineEndIdx(tokens, i) - 1;
            continue;
        }
        return markErrorAt(tokens, i, error.InvalidSynthErrorType);
    }
}

fn checkUpperValueExprs(program: parser.Program, tokens: []const lexer.Token) !void {
    for (program.expr_nodes) |node| {
        if (node.kind != .ident) continue;
        const tok = tokens[node.start_tok];
        if (!isValidDeclaredTypeName(tok.lexeme)) continue;
        if (isTypeConstructorExpr(tokens, node.start_tok)) continue;
        if (isLocalErrorBranchValue(tokens, tok.lexeme)) continue;
        if (isImportedUpperAlias(tokens, tok.lexeme)) continue;
        return markErrorAt(tokens, node.start_tok, error.InvalidTypeRef);
    }
}

fn isTypeConstructorExpr(tokens: []const lexer.Token, start_idx: usize) bool {
    var idx = start_idx + 1;
    if (idx < tokens.len and tokEq(tokens[idx], "<")) {
        const close_angle = findMatching(tokens, idx, "<", ">") catch return false;
        idx = close_angle + 1;
    }
    return idx < tokens.len and tokEq(tokens[idx], "{");
}

fn isLocalErrorBranchValue(tokens: []const lexer.Token, name: []const u8) bool {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (depth_brace == 0) {
                if (parseImportDeclEnd(tokens, i)) |next_idx| {
                    i = next_idx - 1;
                    continue;
                }
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
        if (!isErrorEnumDeclStart(tokens, i) and !isValueEnumDeclStart(tokens, i)) continue;
        if (enumDeclHasBranch(tokens, i, name)) return true;
    }
    return false;
}

fn isImportedUpperAlias(tokens: []const lexer.Token, name: []const u8) bool {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (depth_brace == 0) {
                if (parseImportDeclEnd(tokens, i)) |next_idx| {
                    i = next_idx - 1;
                    continue;
                }
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

fn enumDeclHasBranch(tokens: []const lexer.Token, line_start_idx: usize, name: []const u8) bool {
    const eq_idx = enumDeclAssignIdx(tokens, line_start_idx) orelse return false;
    const line_end = findLineEndIdx(tokens, line_start_idx);

    var i = eq_idx + 1;
    while (i < line_end) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (std.mem.eql(u8, publicTypeName(tokens[i].lexeme), name)) return true;
    }
    return false;
}

fn enumDeclAssignIdx(tokens: []const lexer.Token, line_start_idx: usize) ?usize {
    if (isErrorEnumDeclStart(tokens, line_start_idx) or isValueEnumDeclStart(tokens, line_start_idx)) {
        return line_start_idx + 2;
    }
    return null;
}

fn checkTopValueDeclNames(tokens: []const lexer.Token) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (depth_brace == 0) {
                if (parseImportDeclEnd(tokens, i)) |next_idx| {
                    i = next_idx - 1;
                    continue;
                }
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
        if (isTopLevelDeclHead(tokens, i) and isTypeDeclStart(tokens, i)) continue;
        if (i + 1 < tokens.len and tokEq(tokens[i + 1], "(")) continue;

        const line_end = findLineEndIdx(tokens, i);
        const eq_idx = findTopLevelAssignEqOnLine(tokens, i + 1, line_end) orelse continue;
        if (eq_idx <= i + 1) return markErrorAt(tokens, i, error.InvalidBindingName);
        if (isValidTopValueDeclName(t.lexeme)) continue;
        return markErrorAt(tokens, i, error.InvalidBindingName);
    }
}

fn isValidTopValueDeclName(name: []const u8) bool {
    if (isReadonlyIdentName(name)) return true;
    if (isLowerIdentName(name) and !isReservedFuncName(name)) return true;
    return name.len > 1 and name[0] == '.' and isLowerIdentName(name[1..]) and !isReservedFuncName(name[1..]);
}

fn checkStructFieldNames(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (depth_brace == 0) {
                if (parseImportDeclEnd(tokens, i)) |next_idx| {
                    i = next_idx - 1;
                    continue;
                }
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
        if (i + 1 >= tokens.len or !tokEq(tokens[i + 1], "{")) continue;

        const open_idx = i + 1;
        const close_idx = findMatching(tokens, open_idx, "{", "}") catch continue;
        try checkOneStructFieldNames(allocator, tokens, open_idx + 1, close_idx);
        i = close_idx;
    }
}

const StructFieldInfo = struct {
    name: []const u8,
    ty: ?[]const u8,
    has_default: bool,
};

const StructInfo = struct {
    name: []const u8,
    fields: []const StructFieldInfo,
};

fn checkStructCtorFields(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
    const structs = try collectStructInfos(allocator, tokens);
    defer freeStructInfos(allocator, structs);
    if (structs.len == 0) return;

    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], ".")) {
            if (i + 1 >= tokens.len or !tokEq(tokens[i + 1], "{")) continue;
            const struct_info = inferredStructCtorInfo(structs, tokens, i) orelse continue;
            const close_idx = findMatching(tokens, i + 1, "{", "}") catch
                return markErrorAt(tokens, i + 1, error.InvalidStructLiteral);
            try checkOneStructCtorFields(allocator, tokens, i, i + 2, close_idx, struct_info);
            i = close_idx;
            continue;
        }

        if (tokens[i].kind == .ident) {
            if (i + 1 >= tokens.len or !tokEq(tokens[i + 1], "{")) continue;
            if (isTopLevelDeclHead(tokens, i) and isTypeDeclStart(tokens, i)) continue;
            if (isFunctionReturnTypeBeforeBody(tokens, i)) continue;
            if (!isStructCtorExprContext(tokens, i)) continue;
            const struct_info = findStructInfo(structs, publicTypeName(tokens[i].lexeme)) orelse continue;
            const close_idx = findMatching(tokens, i + 1, "{", "}") catch
                return markErrorAt(tokens, i + 1, error.InvalidStructLiteral);
            try checkOneStructCtorFields(allocator, tokens, i, i + 2, close_idx, struct_info);
            i = close_idx;
            continue;
        }
    }
}

fn collectStructInfos(allocator: std.mem.Allocator, tokens: []const lexer.Token) ![]StructInfo {
    var out = std.ArrayList(StructInfo).empty;
    errdefer freeStructInfos(allocator, out.items);

    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (depth_brace == 0) {
                if (parseImportDeclEnd(tokens, i)) |next_idx| {
                    i = next_idx - 1;
                    continue;
                }
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

fn collectStructFieldInfos(
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
        const line_end = findLineEndIdx(tokens, i);
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

fn freeStructInfos(allocator: std.mem.Allocator, structs: []StructInfo) void {
    for (structs) |info| {
        for (info.fields) |field| {
            if (field.ty) |ty| allocator.free(ty);
        }
        allocator.free(info.fields);
    }
    allocator.free(structs);
}

fn findStructInfo(structs: []const StructInfo, name: []const u8) ?StructInfo {
    for (structs) |info| {
        if (std.mem.eql(u8, info.name, name)) return info;
    }
    return null;
}

fn isFunctionReturnTypeBeforeBody(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (!tokEq(tokens[idx + 1], "{")) return false;
    return hasReturnArrowBeforeOnLine(tokens, idx);
}

fn isStructCtorExprContext(tokens: []const lexer.Token, idx: usize) bool {
    if (idx == 0) return true;
    if (tokens[idx - 1].line != tokens[idx].line) return true;

    const prev = tokens[idx - 1];
    if (tokEq(prev, "=")) return true;
    if (tokEq(prev, "return")) return true;
    if (tokEq(prev, "(") or tokEq(prev, ",") or tokEq(prev, "[")) return true;
    if (tokEq(prev, "{")) return !isStructDeclBodyOpen(tokens, idx - 1);
    if (isSpreadToken(prev)) return true;
    if (idx >= 2 and isReturnArrowAt(tokens, idx - 2)) return false;
    if (prev.kind == .ident or tokEq(prev, "]") or tokEq(prev, ">") or tokEq(prev, "|")) return false;
    return true;
}

fn inferredStructCtorInfo(structs: []const StructInfo, tokens: []const lexer.Token, dot_idx: usize) ?StructInfo {
    const line_start = lineStartIdx(tokens, dot_idx);
    if (dot_idx == 0) return null;
    const eq_idx = dot_idx - 1;
    if (tokens[eq_idx].line != tokens[dot_idx].line or !tokEq(tokens[eq_idx], "=")) return null;
    if (isNonAssignEqual(tokens, eq_idx)) return null;
    if (line_start + 1 >= eq_idx) return null;
    if (tokens[line_start].kind != .ident) return null;

    const type_idx = line_start + 1;
    if (tokens[type_idx].kind != .ident) return null;
    return findStructInfo(structs, publicTypeName(tokens[type_idx].lexeme));
}

fn checkOneStructCtorFields(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    ctor_idx: usize,
    start_idx: usize,
    end_idx: usize,
    struct_info: StructInfo,
) !void {
    var seen = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer seen.deinit(allocator);

    var field_start = start_idx;
    while (field_start < end_idx) {
        if (tokEq(tokens[field_start], ",")) {
            field_start += 1;
            continue;
        }
        const assign_idx = findTopLevelAssignEq(tokens, field_start, end_idx) orelse
            return markErrorAt(tokens, field_start, error.InvalidStructLiteral);
        if (assign_idx == field_start or tokens[field_start].kind != .ident) {
            return markErrorAt(tokens, field_start, error.InvalidStructLiteral);
        }
        if (assign_idx != field_start + 1) {
            return markErrorAt(tokens, field_start, error.InvalidStructLiteral);
        }
        const field_end = findStructCtorFieldEnd(tokens, assign_idx + 1, end_idx);
        if (field_end == assign_idx + 1) return markErrorAt(tokens, assign_idx, error.InvalidStructLiteral);
        const field_name = normalizeStructFieldName(tokens[field_start].lexeme);
        if (findStructFieldInfo(struct_info.fields, field_name) == null) {
            return markErrorAt(tokens, field_start, error.InvalidStructLiteral);
        }
        if (hasSeenField(seen.items, field_name)) {
            return markErrorAt(tokens, field_start, error.InvalidStructLiteral);
        }
        try seen.append(allocator, field_name);
        field_start = field_end;
        if (field_start < end_idx and tokEq(tokens[field_start], ",")) field_start += 1;
    }

    for (struct_info.fields) |field| {
        if (field.has_default) continue;
        if (hasSeenField(seen.items, field.name)) continue;
        return markErrorAt(tokens, ctor_idx, error.InvalidStructLiteral);
    }
}

fn findStructFieldInfo(fields: []const StructFieldInfo, name: []const u8) ?StructFieldInfo {
    for (fields) |field| {
        if (std.mem.eql(u8, field.name, name)) return field;
    }
    return null;
}

fn hasSeenField(seen: []const []const u8, name: []const u8) bool {
    for (seen) |field_name| {
        if (std.mem.eql(u8, field_name, name)) return true;
    }
    return false;
}

fn findStructCtorFieldEnd(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
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

fn checkOneStructFieldNames(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) !void {
    var seen = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer seen.deinit(allocator);

    var i = start_idx;
    while (i < end_idx) {
        if (tokens[i].kind != .ident or !isStructFieldName(tokens[i].lexeme)) {
            if (tokens[i].kind == .ident and isReservedFieldName(tokens[i].lexeme)) {
                return markErrorAt(tokens, i, error.InvalidTypeRef);
            }
            i = findLineEndIdx(tokens, i);
            continue;
        }
        const field_name = normalizeStructFieldName(tokens[i].lexeme);
        for (seen.items) |prev| {
            if (std.mem.eql(u8, prev, field_name)) {
                return markErrorAt(tokens, i, error.DuplicateStructFieldName);
            }
        }
        try seen.append(allocator, field_name);
        i = findLineEndIdx(tokens, i);
    }
}

fn normalizeStructFieldName(name: []const u8) []const u8 {
    if (name.len > 0 and name[0] == '.') return name[1..];
    return name;
}

fn isReservedFieldName(name: []const u8) bool {
    const public_name = normalizeStructFieldName(name);
    return isReservedFieldNameBody(public_name);
}

fn isReservedFieldNameBody(name: []const u8) bool {
    return isKeyword(name) or isDeclOnlyName(name) or isReservedCoreAccessName(name) or isReservedSourceName(name);
}

fn isReservedCoreAccessName(name: []const u8) bool {
    return std.mem.eql(u8, name, "get") or std.mem.eql(u8, name, "set");
}

fn isTopLevelDeclHead(tokens: []const lexer.Token, idx: usize) bool {
    if (idx == 0) return true;
    if (tokens[idx - 1].line == tokens[idx].line) return false;

    const prev = tokens[idx - 1];
    if (tokEq(prev, "=")) return false;
    if (tokEq(prev, "|")) return false;
    if (tokEq(prev, ",")) return false;
    if (tokEq(prev, ":")) return false;
    return true;
}

fn checkHostImports(tokens: []const lexer.Token) !void {
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
        if (!isHostImportDeclStart(tokens, i)) continue;
        try validateHostImportDecl(tokens, i);
        i = (parseImportDeclEnd(tokens, i) orelse i + 1) - 1;
    }
}

fn checkLocalImports(tokens: []const lexer.Token) !void {
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
        if (!isModernImportAssign(tokens, i)) continue;

        const eq_idx = topLevelLineAssignIdx(tokens, i) orelse return markErrorAt(tokens, i, error.InvalidImportDecl);
        const at_idx = eq_idx + 1;
        if (isHostImportLine(tokens, at_idx)) {
            i = (parseImportDeclEnd(tokens, i) orelse i + 1) - 1;
            continue;
        }

        try validateLocalImportDecl(tokens, i, at_idx);
        i = (parseImportDeclEnd(tokens, i) orelse i + 1) - 1;
    }
}

fn isHostImportDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    const eq_idx = topLevelLineAssignIdx(tokens, idx) orelse return false;
    const at_idx = eq_idx + 1;
    if (at_idx >= tokens.len or !tokEq(tokens[at_idx], "@")) return false;
    return isHostImportLine(tokens, at_idx);
}

fn isModernImportAssign(tokens: []const lexer.Token, idx: usize) bool {
    const eq_idx = topLevelLineAssignIdx(tokens, idx) orelse return false;
    const at_idx = eq_idx + 1;
    if (at_idx + 1 >= tokens.len or !tokEq(tokens[at_idx], "@")) return false;
    if (tokens[at_idx + 1].kind != .ident) return false;
    return std.mem.eql(u8, tokens[at_idx + 1].lexeme, "lib") or
        std.mem.eql(u8, tokens[at_idx + 1].lexeme, "env") or
        std.mem.eql(u8, tokens[at_idx + 1].lexeme, "wasi");
}

fn validateHostImportDecl(tokens: []const lexer.Token, name_idx: usize) !void {
    if (tokens[name_idx].kind != .ident) return markErrorAt(tokens, name_idx, error.InvalidImportDecl);
    const alias = publicFuncName(tokens[name_idx].lexeme);
    if (!isValidImportName(alias)) return markErrorAt(tokens, name_idx, error.InvalidImportDecl);
    if (!isLowerIdentName(alias)) return markErrorAt(tokens, name_idx, error.InvalidImportDecl);

    const eq_idx = topLevelLineAssignIdx(tokens, name_idx) orelse return markErrorAt(tokens, name_idx, error.InvalidImportDecl);
    const at_idx = eq_idx + 1;
    try validateHostImportLine(tokens, at_idx, parseImportDeclEnd(tokens, name_idx) orelse return markErrorAt(tokens, at_idx, error.InvalidImportDecl));
}

fn isValidImportName(name: []const u8) bool {
    return (isValidDeclaredTypeName(name) or isLowerIdentName(name) or isReadonlyIdentName(name)) and !isReservedFuncName(name);
}

fn importAliasMatchesTarget(alias: []const u8, target: []const u8) bool {
    if (isValidDeclaredTypeName(target)) return isValidDeclaredTypeName(alias);
    if (isLowerIdentName(target)) return isLowerIdentName(alias);
    if (isReadonlyIdentName(target)) return isReadonlyIdentName(alias);
    return false;
}

fn topLevelLineAssignIdx(tokens: []const lexer.Token, line_start: usize) ?usize {
    const line_end = findLineEndIdx(tokens, line_start);
    return findTopLevelAssignEqOnLine(tokens, line_start + 1, line_end);
}

fn isHostImportLine(tokens: []const lexer.Token, at_idx: usize) bool {
    if (at_idx + 2 >= tokens.len) return false;
    if (!tokEq(tokens[at_idx], "@")) return false;
    if (tokens[at_idx + 1].kind != .ident) return false;
    if (!tokEq(tokens[at_idx + 2], "(")) return false;
    return std.mem.eql(u8, tokens[at_idx + 1].lexeme, "env") or std.mem.eql(u8, tokens[at_idx + 1].lexeme, "wasi");
}

fn validateLocalImportDecl(tokens: []const lexer.Token, name_idx: usize, at_idx: usize) !void {
    if (tokens[name_idx].kind != .ident) return markErrorAt(tokens, name_idx, error.InvalidImportDecl);
    if (tokens[name_idx].lexeme.len != 0 and tokens[name_idx].lexeme[0] == '.') return markErrorAt(tokens, name_idx, error.InvalidImportDecl);
    if (!isValidImportName(tokens[name_idx].lexeme)) return markErrorAt(tokens, name_idx, error.InvalidImportDecl);

    const close_idx = parseImportDeclEnd(tokens, name_idx) orelse return markErrorAt(tokens, at_idx, error.InvalidImportDecl);
    if (at_idx + 7 != close_idx) return markErrorAt(tokens, at_idx, error.InvalidImportDecl);
    if (tokens[at_idx + 1].kind != .ident or !std.mem.eql(u8, tokens[at_idx + 1].lexeme, "lib")) return markErrorAt(tokens, at_idx, error.InvalidImportDecl);
    if (!tokEq(tokens[at_idx + 2], "(")) return markErrorAt(tokens, at_idx + 2, error.InvalidImportDecl);
    if (tokens[at_idx + 3].kind != .string) return markErrorAt(tokens, at_idx + 3, error.InvalidImportDecl);
    if (!tokEq(tokens[at_idx + 4], ",")) return markErrorAt(tokens, at_idx + 4, error.InvalidImportDecl);
    if (tokens[at_idx + 5].kind != .ident) return markErrorAt(tokens, at_idx + 5, error.InvalidImportDecl);

    var file_path = stringTokenBody(tokens[at_idx + 3].lexeme) orelse return markErrorAt(tokens, at_idx + 3, error.InvalidImportDecl);
    const target = tokens[at_idx + 5].lexeme;
    var prefix: LocalImportPrefix = .std;
    if (std.mem.startsWith(u8, file_path, "./")) {
        prefix = .local;
        file_path = file_path[2..];
    } else if (std.mem.startsWith(u8, file_path, "~/")) {
        prefix = .dep;
        file_path = file_path[2..];
    } else if (std.mem.startsWith(u8, file_path, "/")) {
        return markErrorAt(tokens, at_idx + 3, error.InvalidImportDecl);
    }

    try validateImportFileNameText(tokens, at_idx + 3, file_path, prefix);
    if (!isValidImportName(target)) return markErrorAt(tokens, at_idx + 3, error.InvalidImportDecl);
    if (!importAliasMatchesTarget(tokens[name_idx].lexeme, target)) return markErrorAt(tokens, name_idx, error.InvalidImportDecl);
}

fn validateImportFileNameText(tokens: []const lexer.Token, site_idx: usize, s: []const u8, prefix: LocalImportPrefix) !void {
    if (!std.mem.endsWith(u8, s, ".do")) return markErrorAt(tokens, site_idx, error.InvalidImportDecl);
    const stem = s[0 .. s.len - 3];
    const ok = switch (prefix) {
        .local, .std => isValidFlatFileStem(stem),
        .dep => isValidDepFileStem(stem),
    };
    if (!ok) return markErrorAt(tokens, site_idx, error.InvalidImportDecl);
}

fn validateImportFileName(tokens: []const lexer.Token, idx: usize, prefix: LocalImportPrefix) !void {
    try validateImportFileNameText(tokens, idx, tokens[idx].lexeme, prefix);
}

fn isValidFlatFileStem(stem: []const u8) bool {
    var count: usize = 0;
    var start: usize = 0;
    while (start <= stem.len) {
        const dot_idx = std.mem.indexOfScalarPos(u8, stem, start, '.') orelse stem.len;
        if (!isValidPathSeg(stem[start..dot_idx])) return false;
        count += 1;
        if (dot_idx == stem.len) break;
        start = dot_idx + 1;
    }
    return count != 0;
}

fn isValidDepFileStem(stem: []const u8) bool {
    var count: usize = 0;
    var start: usize = 0;
    while (start <= stem.len) {
        const dot_idx = std.mem.indexOfScalarPos(u8, stem, start, '.') orelse stem.len;
        const seg = stem[start..dot_idx];
        if (!isAllDigits(seg) and !isValidPathSeg(seg)) return false;
        count += 1;
        if (dot_idx == stem.len) break;
        start = dot_idx + 1;
    }
    return count >= 2;
}

fn isAllDigits(seg: []const u8) bool {
    if (seg.len == 0) return false;
    for (seg) |ch| {
        if (ch < '0' or ch > '9') return false;
    }
    return true;
}

fn isValidPathSeg(seg: []const u8) bool {
    if (seg.len == 0) return false;
    if (seg[0] < 'a' or seg[0] > 'z') return false;
    if (seg[seg.len - 1] == '_') return false;

    var prev_underscore = false;
    for (seg[1..]) |ch| {
        if ((ch >= 'a' and ch <= 'z') or (ch >= '0' and ch <= '9')) {
            prev_underscore = false;
            continue;
        }
        if (ch >= '0' and ch <= '9') {
            prev_underscore = false;
            continue;
        }
        if (ch == '_') {
            if (prev_underscore) return false;
            prev_underscore = true;
            continue;
        }
        return false;
    }
    return true;
}

fn validateHostImportLine(tokens: []const lexer.Token, at_idx: usize, import_end: usize) !void {
    if (at_idx + 5 > import_end) return markErrorAt(tokens, at_idx, error.InvalidImportDecl);
    if (!tokEq(tokens[at_idx], "@")) return markErrorAt(tokens, at_idx, error.InvalidImportDecl);
    if (tokens[at_idx + 1].kind != .ident) return markErrorAt(tokens, at_idx + 1, error.InvalidImportDecl);
    if (!tokEq(tokens[at_idx + 2], "(")) return markErrorAt(tokens, at_idx + 2, error.InvalidImportDecl);
    if (tokens[at_idx + 3].kind != .string) return markErrorAt(tokens, at_idx + 3, error.InvalidImportDecl);

    const target = stringTokenBody(tokens[at_idx + 3].lexeme) orelse return markErrorAt(tokens, at_idx + 3, error.InvalidImportDecl);
    const kind = try validateHostImportTarget(tokens, at_idx, at_idx + 1);
    const comma_idx = findTopLevelComma(tokens, at_idx + 4, import_end - 1) orelse return markErrorAt(tokens, at_idx + 3, error.InvalidImportDecl);
    if (comma_idx + 1 >= import_end - 1) return markErrorAt(tokens, comma_idx, error.InvalidImportDecl);
    try validateHostSignature(tokens, comma_idx + 1, import_end - 1, kind);
    if (kind == .wasi) {
        try validateKnownWasiSignature(tokens, at_idx + 3, target, comma_idx + 1, import_end - 1);
    }
}

fn validateHostImportTarget(tokens: []const lexer.Token, at_idx: usize, name_idx: usize) !HostImportKind {
    const target = stringTokenBody(tokens[at_idx + 3].lexeme) orelse return markErrorAt(tokens, at_idx + 3, error.InvalidImportDecl);
    if (std.mem.eql(u8, tokens[name_idx].lexeme, "env")) {
        if (!isValidPathSeg(target)) return markErrorAt(tokens, at_idx + 3, error.InvalidImportDecl);
        return .env;
    }
    if (std.mem.eql(u8, tokens[name_idx].lexeme, "wasi")) {
        if (!isValidWitTargetPath(target)) return markErrorAt(tokens, at_idx + 3, error.InvalidImportDecl);
        return .wasi;
    }
    return markErrorAt(tokens, name_idx, error.InvalidImportDecl);
}

fn validateHostSignature(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, kind: HostImportKind) !void {
    if (start_idx >= end_idx) return markErrorAt(tokens, @min(start_idx, tokens.len - 1), error.InvalidImportDecl);
    if (!tokEq(tokens[start_idx], "(")) return markErrorAt(tokens, start_idx, error.InvalidImportDecl);
    const close_idx = findMatching(tokens, start_idx, "(", ")") catch return markErrorAt(tokens, start_idx, error.InvalidImportDecl);
    if (close_idx + 3 >= end_idx or !tokEq(tokens[close_idx + 1], "-") or !tokEq(tokens[close_idx + 2], ">")) return markErrorAt(tokens, close_idx, error.InvalidImportDecl);
    try validateHostImportParams(tokens, start_idx + 1, close_idx, kind);
    try validateHostReturnType(tokens, close_idx + 3, end_idx, kind);
}

const KnownWasiSignature = struct {
    target: []const u8,
    params: []const u8,
    result: []const u8,
    result_record: ?KnownWasiRecord = null,
};

const KnownWasiRecord = struct {
    name: []const u8,
    fields: []const KnownWasiRecordField,
};

const KnownWasiRecordField = struct {
    name: []const u8,
    ty: []const u8,
};

const WIT_DATETIME_FIELDS = [_]KnownWasiRecordField{
    .{ .name = "seconds", .ty = "i64" },
    .{ .name = "nanoseconds", .ty = "u32" },
};

fn validateKnownWasiSignature(
    tokens: []const lexer.Token,
    site_idx: usize,
    target: []const u8,
    sig_start: usize,
    sig_end: usize,
) !void {
    const known = findKnownWasiSignature(target) orelse return;
    const close_idx = findMatching(tokens, sig_start, "(", ")") catch
        return markErrorAt(tokens, sig_start, error.InvalidImportDecl);
    if (close_idx + 3 >= sig_end or !tokEq(tokens[close_idx + 1], "-") or !tokEq(tokens[close_idx + 2], ">")) {
        return markErrorAt(tokens, sig_start, error.InvalidImportDecl);
    }
    if (!compactTokenRangeEquals(tokens, sig_start + 1, close_idx, known.params)) {
        return markErrorAt(tokens, site_idx, error.InvalidImportDecl);
    }
    if (!compactTokenRangeEquals(tokens, close_idx + 3, sig_end, known.result)) {
        return markErrorAt(tokens, site_idx, error.InvalidImportDecl);
    }
    if (known.result_record) |record| {
        if (!knownWasiRecordMirrorMatches(tokens, record)) return markErrorAt(tokens, site_idx, error.InvalidImportDecl);
    }
}

fn findKnownWasiSignature(target: []const u8) ?KnownWasiSignature {
    const known = [_]KnownWasiSignature{
        .{ .target = "filesystem/types/descriptor.write", .params = "descriptor,list<u8>,filesize", .result = "result<filesize,error-code>" },
        .{ .target = "filesystem/types/descriptor.read", .params = "descriptor,filesize,filesize", .result = "result<tuple<list<u8>,bool>,error-code>" },
        .{ .target = "filesystem/types/descriptor.sync", .params = "descriptor", .result = "result<_,error-code>" },
        .{ .target = "filesystem/types/descriptor.link-at", .params = "descriptor,path-flags,text,borrow<descriptor>,text", .result = "result<_,error-code>" },
        .{ .target = "filesystem/types/descriptor.create-directory-at", .params = "descriptor,text", .result = "result<_,error-code>" },
        .{ .target = "filesystem/types/descriptor.open-at", .params = "descriptor,path-flags,text,open-flags,descriptor-flags", .result = "result<descriptor,error-code>" },
        .{ .target = "filesystem/types/descriptor.remove-directory-at", .params = "descriptor,text", .result = "result<_,error-code>" },
        .{ .target = "filesystem/types/descriptor.read-directory", .params = "descriptor", .result = "tuple<stream<directory-entry>,future<result<_,error-code>>>" },
        .{ .target = "filesystem/types/descriptor.drop", .params = "descriptor", .result = "nil" },
        .{ .target = "filesystem/preopens/get-directories", .params = "", .result = "list<tuple<descriptor,text>>" },
        .{ .target = "io/streams/input-stream.read", .params = "input-stream,u64", .result = "result<list<u8>,stream-error>" },
        .{ .target = "io/streams/output-stream.check-write", .params = "output-stream", .result = "result<u64,stream-error>" },
        .{ .target = "io/streams/output-stream.write", .params = "output-stream,list<u8>", .result = "result<_,stream-error>" },
        .{ .target = "io/streams/output-stream.flush", .params = "output-stream", .result = "result<_,stream-error>" },
        .{ .target = "sockets/types/tcp-socket.create", .params = "ip-address-family", .result = "result<tcp-socket,error-code>" },
        .{ .target = "sockets/types/tcp-socket.bind", .params = "tcp-socket,ip-socket-address", .result = "result<_,error-code>" },
        .{ .target = "sockets/types/udp-socket.create", .params = "ip-address-family", .result = "result<udp-socket,error-code>" },
        .{ .target = "sockets/types/udp-socket.bind", .params = "udp-socket,ip-socket-address", .result = "result<_,error-code>" },
        .{ .target = "http/client/send", .params = "request", .result = "result<response,error-code>" },
        .{ .target = "text/char/echo", .params = "char", .result = "char" },
        .{
            .target = "clocks/system-clock/now",
            .params = "",
            .result = "Datetime",
            .result_record = .{ .name = "Datetime", .fields = &WIT_DATETIME_FIELDS },
        },
        .{ .target = "clocks/system-clock/get-resolution", .params = "", .result = "u64" },
        .{ .target = "clocks/monotonic-clock/now", .params = "", .result = "u64" },
        .{ .target = "clocks/monotonic-clock/get-resolution", .params = "", .result = "u64" },
        .{ .target = "random/random/get-random-bytes", .params = "u64", .result = "list<u8>" },
        .{ .target = "random/random/get-random-u64", .params = "", .result = "u64" },
    };
    for (known) |item| {
        if (std.mem.eql(u8, item.target, target)) return item;
    }
    return null;
}

fn compactTokenRangeEquals(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, expected: []const u8) bool {
    var pos: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        const lexeme = tokens[i].lexeme;
        if (pos + lexeme.len > expected.len) return false;
        if (!std.mem.eql(u8, expected[pos .. pos + lexeme.len], lexeme)) return false;
        pos += lexeme.len;
    }
    return pos == expected.len;
}

const StructDeclRange = struct {
    open_idx: usize,
    close_idx: usize,
};

fn knownWasiRecordMirrorMatches(tokens: []const lexer.Token, record: KnownWasiRecord) bool {
    const decl = findPublicStructDecl(tokens, record.name) orelse return false;

    var field_idx: usize = 0;
    var i = decl.open_idx + 1;
    while (i < decl.close_idx) {
        const line_end = findLineEndIdx(tokens, i);
        if (tokens[i].kind != .ident or !isStructFieldName(tokens[i].lexeme) or i + 1 >= line_end) {
            i = line_end;
            continue;
        }
        if (field_idx >= record.fields.len) return false;

        const expected = record.fields[field_idx];
        if (!std.mem.eql(u8, normalizeStructFieldName(tokens[i].lexeme), expected.name)) return false;

        const type_end = findStructFieldTypeEnd(tokens, i + 1, line_end);
        if (!compactTokenRangeEquals(tokens, i + 1, type_end, expected.ty)) return false;

        field_idx += 1;
        i = line_end;
    }

    return field_idx == record.fields.len;
}

fn validateHostImportParams(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, kind: HostImportKind) !void {
    var i = start_idx;
    while (i < end_idx) {
        if (tokEq(tokens[i], ",")) {
            i += 1;
            continue;
        }

        const next = try validateHostParamType(tokens, i, end_idx, kind);
        i = next;
        if (i < end_idx) {
            if (!tokEq(tokens[i], ",")) return markErrorAt(tokens, i, error.InvalidImportDecl);
            i += 1;
        }
    }
}

fn validateHostReturnType(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, kind: HostImportKind) !void {
    const next = try validateHostReturnTypeAt(tokens, start_idx, end_idx, kind);
    if (next != end_idx) return markErrorAt(tokens, next, error.InvalidImportDecl);
}

fn validateHostParamType(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, kind: HostImportKind) !usize {
    if (start_idx >= end_idx) return markErrorAt(tokens, @min(start_idx, tokens.len - 1), error.InvalidImportDecl);
    switch (kind) {
        .env => {
            if (tokens[start_idx].kind == .ident and isHostParamType(tokens[start_idx].lexeme)) {
                return start_idx + 1;
            }
            return markErrorAt(tokens, start_idx, error.InvalidImportDecl);
        },
        .wasi => {
            const next = parseWitType(tokens, start_idx, end_idx) orelse
                return markErrorAt(tokens, start_idx, error.InvalidImportDecl);
            return next;
        },
    }
}

fn validateHostReturnTypeAt(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, kind: HostImportKind) !usize {
    if (start_idx >= end_idx) return markErrorAt(tokens, @min(start_idx, tokens.len - 1), error.InvalidImportDecl);
    switch (kind) {
        .env => {
            if (tokens[start_idx].kind == .ident and isHostReturnType(tokens[start_idx].lexeme)) {
                return start_idx + 1;
            }
            return markErrorAt(tokens, start_idx, error.InvalidImportDecl);
        },
        .wasi => {
            const next = parseWitType(tokens, start_idx, end_idx) orelse
                return markErrorAt(tokens, start_idx, error.InvalidImportDecl);
            return next;
        },
    }
}

fn stringTokenBody(s: []const u8) ?[]const u8 {
    if (s.len < 2) return null;
    if (s[0] != '"' or s[s.len - 1] != '"') return null;
    return s[1 .. s.len - 1];
}

fn isValidWitTargetPath(path: []const u8) bool {
    var count: usize = 0;
    var start: usize = 0;
    while (start <= path.len) {
        const slash_idx = std.mem.indexOfScalarPos(u8, path, start, '/') orelse path.len;
        const seg = path[start..slash_idx];
        if (!isValidWitPathName(seg)) return false;
        count += 1;
        if (slash_idx == path.len) break;
        start = slash_idx + 1;
    }
    return count >= 3;
}

fn isHostParamType(name: []const u8) bool {
    const allowed = [_][]const u8{
        "i32",
        "i64",
        "f32",
        "f64",
    };
    for (allowed) |it| {
        if (std.mem.eql(u8, it, name)) return true;
    }
    return false;
}

fn isHostReturnType(name: []const u8) bool {
    if (std.mem.eql(u8, name, "nil")) return true;
    return isHostParamType(name);
}

fn parseWitType(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (start_idx >= end_idx or tokens[start_idx].kind != .ident) return null;
    const name = tokens[start_idx].lexeme;

    if (std.mem.eql(u8, name, "list")) {
        if (start_idx + 2 >= end_idx or !tokEq(tokens[start_idx + 1], "<")) return null;
        const item_end = parseWitType(tokens, start_idx + 2, end_idx) orelse return null;
        if (item_end >= end_idx or !tokEq(tokens[item_end], ">")) return null;
        return item_end + 1;
    }

    if (std.mem.eql(u8, name, "result")) {
        if (start_idx + 4 >= end_idx or !tokEq(tokens[start_idx + 1], "<")) return null;
        const ok_end = parseWitType(tokens, start_idx + 2, end_idx) orelse return null;
        if (ok_end >= end_idx or !tokEq(tokens[ok_end], ",")) return null;
        const err_end = parseWitType(tokens, ok_end + 1, end_idx) orelse return null;
        if (err_end >= end_idx or !tokEq(tokens[err_end], ">")) return null;
        return err_end + 1;
    }

    if (std.mem.eql(u8, name, "tuple")) {
        if (start_idx + 4 >= end_idx or !tokEq(tokens[start_idx + 1], "<")) return null;
        var i = start_idx + 2;
        var count: usize = 0;
        while (i < end_idx) {
            const next = parseWitType(tokens, i, end_idx) orelse return null;
            count += 1;
            i = next;
            if (i >= end_idx) return null;
            if (tokEq(tokens[i], ">")) return if (count >= 2) i + 1 else null;
            if (!tokEq(tokens[i], ",")) return null;
            i += 1;
        }
        return null;
    }

    if (std.mem.eql(u8, name, "option") or std.mem.eql(u8, name, "borrow") or std.mem.eql(u8, name, "own")) {
        if (start_idx + 2 >= end_idx or !tokEq(tokens[start_idx + 1], "<")) return null;
        const item_end = parseWitType(tokens, start_idx + 2, end_idx) orelse return null;
        if (item_end >= end_idx or !tokEq(tokens[item_end], ">")) return null;
        return item_end + 1;
    }

    if (std.mem.eql(u8, name, "_")) return start_idx + 1;
    if (hasPublicStructDecl(tokens, name)) return start_idx + 1;

    return parseWitName(tokens, start_idx, end_idx);
}

fn hasPublicStructDecl(tokens: []const lexer.Token, name: []const u8) bool {
    return findPublicStructDecl(tokens, name) != null;
}

fn findPublicStructDecl(tokens: []const lexer.Token, name: []const u8) ?StructDeclRange {
    if (!isValidDeclaredTypeName(name)) return null;

    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (depth_brace == 0) {
                if (parseImportDeclEnd(tokens, i)) |next_idx| {
                    i = next_idx - 1;
                    continue;
                }
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
        if (i + 1 >= tokens.len or !tokEq(tokens[i + 1], "{")) continue;
        const close_idx = findMatching(tokens, i + 1, "{", "}") catch return null;
        return .{ .open_idx = i + 1, .close_idx = close_idx };
    }
    return null;
}

fn parseWitName(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (tokens[start_idx].kind != .ident or !isValidWitPathName(tokens[start_idx].lexeme)) return null;
    var i = start_idx + 1;
    while (i + 1 < end_idx and tokEq(tokens[i], "-")) {
        if (tokens[i + 1].kind != .ident or !isValidWitPathName(tokens[i + 1].lexeme)) return null;
        i += 2;
    }
    return i;
}

fn isValidWitPathName(name: []const u8) bool {
    var start: usize = 0;
    while (start <= name.len) {
        const dot_idx = std.mem.indexOfScalarPos(u8, name, start, '.') orelse name.len;
        if (!isValidWitNamePart(name[start..dot_idx])) return false;
        if (dot_idx == name.len) return true;
        start = dot_idx + 1;
    }
    return false;
}

fn isValidWitNamePart(name: []const u8) bool {
    if (name.len == 0) return false;
    if (name[0] < 'a' or name[0] > 'z') return false;
    if (name[name.len - 1] == '-') return false;

    var prev_dash = false;
    for (name[1..]) |ch| {
        if (ch >= 'a' and ch <= 'z') {
            prev_dash = false;
            continue;
        }
        if (ch >= '0' and ch <= '9') {
            prev_dash = false;
            continue;
        }
        if (ch == '-') {
            if (prev_dash) return false;
            prev_dash = true;
            continue;
        }
        return false;
    }
    return true;
}

fn findTokenOnLine(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, s: []const u8) ?usize {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEq(tokens[i], s)) return i;
    }
    return null;
}

fn hasTopLevelComma(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
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
        if (depth_paren == 0 and depth_angle == 0 and tokEq(tokens[i], ",")) return true;
    }
    return false;
}

fn findTopLevelComma(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
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
        if (depth_paren == 0 and depth_angle == 0 and tokEq(tokens[i], ",")) return i;
    }
    return null;
}

fn firstNonGap(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        _ = tokens;
        return i;
    }
    return null;
}

fn isValueLiteralToken(t: lexer.Token) bool {
    if (t.kind == .number or t.kind == .string) return true;
    if (tokEq(t, "true") or tokEq(t, "false") or tokEq(t, "nil")) return true;
    return false;
}

fn isTypeDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (tokEq(tokens[idx + 1], "(")) return false; // func decl
    if (isErrorEnumDeclStart(tokens, idx) or isValueEnumDeclStart(tokens, idx)) return true;

    var next_idx = idx + 1;
    if (tokEq(tokens[next_idx], "<")) {
        const close_angle = findMatching(tokens, next_idx, "<", ">") catch return false;
        next_idx = close_angle + 1;
        if (next_idx >= tokens.len) return false;
    }

    return tokEq(tokens[next_idx], "{");
}

fn isValidDeclaredTypeName(name: []const u8) bool {
    if (name.len == 0) return false;
    if (name[0] == '.') return isValidDeclaredTypeName(name[1..]);
    if (std.mem.eql(u8, name, "Error")) return false;
    if (!std.ascii.isUpper(name[0])) return false;

    var i: usize = 1;
    while (i < name.len) : (i += 1) {
        if (std.ascii.isAlphabetic(name[i])) continue;
        if (std.ascii.isDigit(name[i])) continue;
        return false;
    }
    return true;
}

fn isLowerIdentName(name: []const u8) bool {
    return isSnakeLowerName(name);
}

fn isReadonlyIdentName(name: []const u8) bool {
    if (name.len < 2) return false;
    if (name[0] != '_') return false;
    return isSnakeLowerName(name[1..]);
}

fn isSnakeLowerName(name: []const u8) bool {
    if (name.len == 0) return false;
    if (!std.ascii.isLower(name[0])) return false;

    var prev_underscore = false;
    for (name[1..]) |ch| {
        if (std.ascii.isLower(ch) or std.ascii.isDigit(ch)) {
            prev_underscore = false;
            continue;
        }
        if (ch == '_' and !prev_underscore) {
            prev_underscore = true;
            continue;
        }
        return false;
    }

    return !prev_underscore;
}

fn isValidLocalBindingName(name: []const u8) bool {
    return (isLowerIdentName(name) or isReadonlyIdentName(name)) and !isReservedFuncName(name);
}

fn isValidLoopBindingName(name: []const u8) bool {
    return std.mem.eql(u8, name, "_") or (isLowerIdentName(name) and !isReservedFuncName(name));
}

fn isValidFuncParamName(name: []const u8) bool {
    return isLowerIdentName(name) and !isReservedFuncName(name);
}

fn isValidFuncParamTypeName(name: []const u8) bool {
    return name.len != 0 and (std.ascii.isUpper(name[0]) or name[0] == '[' or name[0] == '(' or name[0] == '.');
}

fn isSpreadToken(tok: lexer.Token) bool {
    return tok.kind == .symbol and tokEq(tok, "...");
}

fn checkTypeRefs(tokens: []const lexer.Token) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (depth_brace == 0) {
                if (parseImportDeclEnd(tokens, i)) |next_idx| {
                    i = next_idx - 1;
                    continue;
                }
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
        if (t.lexeme.len < 2 or t.lexeme[0] != '.') continue;
        if (!std.ascii.isUpper(t.lexeme[1])) continue;
        if (isTopLevelDeclHead(tokens, i) and isTypeDeclStart(tokens, i)) continue;
        if (isValueEnumBranchDeclToken(tokens, i)) continue;
        return markErrorAt(tokens, i, error.InvalidTypeRef);
    }
}

fn checkForbiddenSourceTypeNames(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (!isForbiddenSourceTypeName(tokens[i].lexeme)) continue;
        if (!isSourceTypeNameContext(tokens, i)) continue;
        return markErrorAt(tokens, i, error.InvalidTypeRef);
    }
}

fn isForbiddenSourceTypeName(name: []const u8) bool {
    return isWitOnlySourceTypeName(name);
}

fn isSourceTypeNameContext(tokens: []const lexer.Token, idx: usize) bool {
    if (isInsideHostImportCall(tokens, idx)) return false;
    if (isSecondIsArg(tokens, idx)) return true;

    if (idx > 0 and tokens[idx - 1].line == tokens[idx].line) {
        const prev = tokens[idx - 1];
        if (tokEq(prev, "=")) return isTypeDeclOrConstraintLine(tokens, idx);
        if (tokEq(prev, "[") or tokEq(prev, "<") or tokEq(prev, "|") or tokEq(prev, ",")) return true;
        if (idx >= 2 and isReturnArrowAt(tokens, idx - 2)) return true;
        if (prev.kind == .ident and !isKeyword(prev.lexeme)) return true;
        if (isSpreadToken(prev)) return true;
    }

    if (idx + 1 < tokens.len and tokens[idx + 1].line == tokens[idx].line) {
        const next = tokens[idx + 1];
        if (tokEq(next, "]") or tokEq(next, ">") or tokEq(next, "|") or tokEq(next, ",") or tokEq(next, "{")) return true;
    }

    return false;
}

fn isInsideHostImportCall(tokens: []const lexer.Token, idx: usize) bool {
    const open_idx = findEnclosingCallOpen(tokens, idx) orelse return false;
    if (open_idx < 2) return false;
    if (!tokEq(tokens[open_idx - 2], "@")) return false;
    if (tokens[open_idx - 1].kind != .ident) return false;
    const name = tokens[open_idx - 1].lexeme;
    return std.mem.eql(u8, name, "env") or std.mem.eql(u8, name, "wasi");
}

fn isValueEnumBranchDeclToken(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 2 >= tokens.len) return false;
    if (!tokEq(tokens[idx + 1], "(")) return false;

    var line_start = idx;
    while (line_start > 0 and tokens[line_start - 1].line == tokens[idx].line) {
        line_start -= 1;
    }
    if (!isValueEnumDeclStart(tokens, line_start)) return false;

    const branch_start = line_start + 3;
    if (idx == branch_start) return true;
    return idx > branch_start and tokEq(tokens[idx - 1], "|");
}

fn checkBareNilTypes(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tokEq(tokens[i], "nil")) continue;
        if (isNilUnionBranch(tokens, i)) {
            if (hasDuplicateNilInUnionSegment(tokens, i)) {
                return markErrorAt(tokens, i, error.InvalidTypeRef);
            }
            continue;
        }
        if (isNilReturnSpec(tokens, i)) continue;
        if (isParenthesizedNilType(tokens, i)) return markErrorAt(tokens, i, error.InvalidTypeRef);
        if (isUntypedNilAssignment(tokens, i)) return markErrorAt(tokens, i, error.InvalidTypeRef);
        if (!isBareNilTypeContext(tokens, i)) continue;
        return markErrorAt(tokens, i, error.InvalidTypeRef);
    }
}

fn isParenthesizedNilType(tokens: []const lexer.Token, idx: usize) bool {
    if (idx == 0 or idx + 1 >= tokens.len) return false;
    if (tokens[idx - 1].line != tokens[idx].line or tokens[idx + 1].line != tokens[idx].line) return false;
    if (!tokEq(tokens[idx - 1], "(") or !tokEq(tokens[idx + 1], ")")) return false;
    const close_idx = findMatchingOpen(tokens, idx + 1, "(", ")") orelse return false;
    return close_idx == idx - 1;
}

fn isUntypedNilAssignment(tokens: []const lexer.Token, idx: usize) bool {
    if (idx == 0 or tokens[idx - 1].line != tokens[idx].line) return false;
    const eq_idx = idx - 1;
    if (!tokEq(tokens[eq_idx], "=") or isNonAssignEqual(tokens, eq_idx)) return false;

    const line_start = lineStartIdx(tokens, idx);
    const line_end = findLineEndIdx(tokens, idx);
    const assign_eq = findTopLevelAssignEqOnLine(tokens, line_start, line_end) orelse return false;
    if (assign_eq != eq_idx) return false;
    if (idx + 1 != line_end) return false;
    return !assignmentLhsHasTypeAnnotation(tokens, line_start, eq_idx);
}

fn assignmentLhsHasTypeAnnotation(tokens: []const lexer.Token, start_idx: usize, eq_idx: usize) bool {
    var i = start_idx + 1;
    while (i < eq_idx) : (i += 1) {
        if (isTypeAtomStart(tokens[i])) return true;
        if (isSpreadToken(tokens[i])) return true;
    }
    return false;
}

fn checkParenthesizedTypeArgs(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tokEq(tokens[i], "(")) continue;
        if (!isTypeArgStartAfterSeparator(tokens, i)) continue;
        return markErrorAt(tokens, i, error.InvalidTypeRef);
    }
}

fn checkParenthesizedTypes(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tokEq(tokens[i], "(")) continue;
        if (isFieldsLoopSourceTypeParen(tokens, i)) continue;
        if (isFuncTypeStart(tokens, i)) continue;
        const close_idx = findMatching(tokens, i, "(", ")") catch continue;
        if (!isParenthesizedTypeContext(tokens, i, close_idx)) continue;
        if (!isTypeExprRangeAllowParens(tokens, i + 1, close_idx)) continue;
        return markErrorAt(tokens, i, error.InvalidTypeRef);
    }
}

fn isFieldsLoopSourceTypeParen(tokens: []const lexer.Token, open_idx: usize) bool {
    if (open_idx == 0 or tokens[open_idx - 1].line != tokens[open_idx].line) return false;
    if (tokens[open_idx - 1].kind != .ident or !std.mem.eql(u8, tokens[open_idx - 1].lexeme, "fields")) return false;
    const close_idx = findMatching(tokens, open_idx, "(", ")") catch return false;
    if (open_idx + 2 != close_idx) return false;
    if (tokens[open_idx + 1].kind != .ident or !isValidDeclaredTypeName(tokens[open_idx + 1].lexeme)) return false;
    if (close_idx + 1 >= tokens.len or tokens[close_idx + 1].line != tokens[open_idx].line or !tokEq(tokens[close_idx + 1], "{")) return false;

    const line_start = lineStartIdx(tokens, open_idx);
    const line_end = findLineEndIdx(tokens, open_idx);
    if (!tokEq(tokens[line_start], "loop")) return false;
    const bind_idx = findTopLevelAssignEqOnLine(tokens, line_start + 1, line_end) orelse return false;
    if (bind_idx + 1 != open_idx - 1) return false;
    if (line_start + 2 != bind_idx) return false;
    return tokens[line_start + 1].kind == .ident and !isKeyword(tokens[line_start + 1].lexeme);
}

fn isParenthesizedTypeContext(tokens: []const lexer.Token, open_idx: usize, close_idx: usize) bool {
    const prev_idx = previousTokenSameLine(tokens, open_idx) orelse return false;
    const prev = tokens[prev_idx];

    if (tokEq(prev, "[") or tokEq(prev, "<") or tokEq(prev, "|")) return true;
    if (tokEq(prev, "=")) return isTypeDeclOrConstraintLine(tokens, open_idx);
    if (tokEq(prev, ">") and prev_idx > 0 and tokEq(tokens[prev_idx - 1], "-")) return true;
    if (tokEq(prev, ",") and hasReturnArrowBeforeOnLine(tokens, open_idx)) return true;
    if (tokEq(prev, ",") and isInsideFuncTypeParamList(tokens, open_idx)) return true;
    if (tokEq(prev, ",") and isSecondIsArg(tokens, open_idx)) return true;
    if (tokEq(prev, "(") and isInsideFuncTypeParamList(tokens, open_idx)) return true;
    if (isSpreadToken(prev)) return true;
    if (prev.kind == .ident and canParenthesizedTypeFollowName(tokens, close_idx)) return true;
    return false;
}

fn previousTokenSameLine(tokens: []const lexer.Token, idx: usize) ?usize {
    if (idx == 0) return null;
    const prev_idx = idx - 1;
    if (tokens[prev_idx].line != tokens[idx].line) return null;
    return prev_idx;
}

fn canParenthesizedTypeFollowName(tokens: []const lexer.Token, close_idx: usize) bool {
    const next_idx = close_idx + 1;
    if (next_idx >= tokens.len) return true;
    if (tokens[next_idx].line != tokens[close_idx].line) return true;
    const next = tokens[next_idx];
    if (tokEq(next, "=") or tokEq(next, "|") or tokEq(next, ",") or tokEq(next, ")") or tokEq(next, "{")) return true;
    return false;
}

fn hasReturnArrowBeforeOnLine(tokens: []const lexer.Token, idx: usize) bool {
    var i = lineStartIdx(tokens, idx);
    while (i + 1 < idx) : (i += 1) {
        if (isReturnArrowAt(tokens, i)) return true;
    }
    return false;
}

fn isInsideFuncTypeParamList(tokens: []const lexer.Token, idx: usize) bool {
    var i = idx;
    while (i > 0 and tokens[i - 1].line == tokens[idx].line) {
        i -= 1;
        if (!tokEq(tokens[i], "(")) continue;
        const close_idx = findMatching(tokens, i, "(", ")") catch continue;
        if (close_idx <= idx) continue;
        if (close_idx + 2 >= tokens.len) continue;
        if (isReturnArrowAt(tokens, close_idx + 1)) return true;
    }
    return false;
}

fn isSecondIsArg(tokens: []const lexer.Token, idx: usize) bool {
    const info = callArgInfo(tokens, idx) orelse return false;
    return std.mem.eql(u8, info.name, "is") and info.arg_index == 1;
}

fn isTypeExprRangeAllowParens(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx >= end_idx) return false;
    var idx = parseTypeAtomAllowParens(tokens, start_idx, end_idx) orelse return false;
    while (idx < end_idx) {
        if (!tokEq(tokens[idx], "|")) return false;
        idx = parseTypeAtomAllowParens(tokens, idx + 1, end_idx) orelse return false;
    }
    return idx == end_idx;
}

fn parseTypeAtomAllowParens(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (start_idx >= end_idx) return null;

    if (tokEq(tokens[start_idx], "(")) {
        if (isFuncTypeStart(tokens, start_idx)) return null;
        const close_idx = findMatching(tokens, start_idx, "(", ")") catch return null;
        if (close_idx >= end_idx) return null;
        if (!isTypeExprRangeAllowParens(tokens, start_idx + 1, close_idx)) return null;
        return close_idx + 1;
    }

    if (tokEq(tokens[start_idx], "[")) {
        const close_idx = findMatching(tokens, start_idx, "[", "]") catch return null;
        if (close_idx >= end_idx) return null;
        if (!isTypeExprRangeAllowParens(tokens, start_idx + 1, close_idx)) return null;
        return close_idx + 1;
    }

    if (tokens[start_idx].kind != .ident) return null;
    if (!isTypeAtomName(tokens[start_idx].lexeme)) return null;

    var idx = start_idx + 1;
    if (idx < end_idx and tokEq(tokens[idx], "<")) {
        const close_angle = findMatching(tokens, idx, "<", ">") catch return null;
        if (close_angle >= end_idx) return null;
        if (!isTypeArgListRange(tokens, idx + 1, close_angle)) return null;
        idx = close_angle + 1;
    }
    return idx;
}

fn isTypeAtomName(name: []const u8) bool {
    if (isBaseTypeName(name) or std.mem.eql(u8, name, "nil")) return true;
    return isValidDeclaredTypeName(name);
}

fn isTypeArgListRange(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx >= end_idx) return false;
    var idx = parseTypeAtomAllowParens(tokens, start_idx, end_idx) orelse return false;
    while (idx < end_idx) {
        if (!tokEq(tokens[idx], "|") and !tokEq(tokens[idx], ",")) return false;
        idx = parseTypeAtomAllowParens(tokens, idx + 1, end_idx) orelse return false;
    }
    return idx == end_idx;
}

fn checkGenericStructCtorTypeArgs(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (!isValidDeclaredTypeName(tokens[i].lexeme)) continue;
        if (!tokEq(tokens[i + 1], "{")) continue;
        if (isTopLevelDeclHead(tokens, i) and isStructDeclStart(tokens, i)) continue;
        if (!isGenericStructTypeName(tokens, publicTypeName(tokens[i].lexeme))) continue;
        return markErrorAt(tokens, i, error.InvalidTypeRef);
    }
}

fn checkGenericTypeArgArity(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (!isValidDeclaredTypeName(tokens[i].lexeme)) continue;
        if (!tokEq(tokens[i + 1], "<")) continue;

        const close_angle = findMatching(tokens, i + 1, "<", ">") catch continue;
        const type_name = publicTypeName(tokens[i].lexeme);
        const expected_count = localStructTypeParamCount(tokens, type_name) orelse {
            if (isLocalNonStructTypeName(tokens, type_name)) return markErrorAt(tokens, i, error.InvalidTypeRef);
            i = close_angle;
            continue;
        };
        const actual_count = countTypeArgs(tokens, i + 2, close_angle);
        if (actual_count != expected_count) return markErrorAt(tokens, i, error.InvalidTypeRef);
        i = close_angle;
    }
}

fn countTypeArgs(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    if (start_idx >= end_idx) return 0;

    var depth_paren: usize = 0;
    var depth_bracket: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var count: usize = 1;

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
            if (i > start_idx and tokEq(tokens[i - 1], "-")) continue;
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (tokEq(tokens[i], ",") and depth_paren == 0 and depth_bracket == 0 and depth_brace == 0 and depth_angle == 0) {
            count += 1;
        }
    }
    return count;
}

fn isGenericStructTypeName(tokens: []const lexer.Token, name: []const u8) bool {
    return genericStructTypeParamCount(tokens, name) != null;
}

fn genericStructTypeParamCount(tokens: []const lexer.Token, name: []const u8) ?usize {
    const count = localStructTypeParamCount(tokens, name) orelse return null;
    return if (count == 0) null else count;
}

fn localStructTypeParamCount(tokens: []const lexer.Token, name: []const u8) ?usize {
    var depth_brace: usize = 0;
    var in_constraint_block = false;
    var type_constraint_count: usize = 0;
    var last_constraint_line: usize = 0;

    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (depth_brace == 0) {
                if (parseImportDeclEnd(tokens, i)) |next_idx| {
                    i = next_idx - 1;
                    continue;
                }
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
            if (tokens[i].kind == .ident and isStructDeclStart(tokens, i) and
                std.mem.eql(u8, publicTypeName(tokens[i].lexeme), name))
            {
                if (in_constraint_block and tokens[i].line == last_constraint_line + 1 and type_constraint_count > 0) {
                    return type_constraint_count;
                }
                return 0;
            }
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

fn isLocalNonStructTypeName(tokens: []const lexer.Token, name: []const u8) bool {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (depth_brace == 0) {
                if (parseImportDeclEnd(tokens, i)) |next_idx| {
                    i = next_idx - 1;
                    continue;
                }
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
        if (isModernImportAssign(tokens, i)) continue;
        if (!isTypeDeclStart(tokens, i)) continue;
        return !isStructDeclStart(tokens, i);
    }
    return false;
}

fn checkUnboundTypeParamRefs(tokens: []const lexer.Token) !void {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (depth_brace == 0) {
                if (parseImportDeclEnd(tokens, i)) |next_idx| {
                    i = next_idx - 1;
                    continue;
                }
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

        if (isFuncDeclStart(tokens, i)) {
            const close_paren = findMatching(tokens, i + 1, "(", ")") catch continue;
            try checkUnboundTypeNamesInRange(tokens, i, i + 2, close_paren);
            try checkUnboundTypeNamesInRange(tokens, i, close_paren + 1, findFuncDeclSignatureEnd(tokens, close_paren + 1));
            i = close_paren;
            continue;
        }

        if (isStructDeclStart(tokens, i)) {
            const close_brace = findMatching(tokens, i + 1, "{", "}") catch continue;
            try checkUnboundStructFieldTypeNames(tokens, i, i + 2, close_brace);
            i = close_brace;
        }
    }
}

fn checkUnboundStructFieldTypeNames(
    tokens: []const lexer.Token,
    decl_start_idx: usize,
    field_start: usize,
    field_end: usize,
) !void {
    var i = field_start;
    while (i < field_end) {
        const line_start = i;
        const line_end = @min(findLineEndIdx(tokens, i), field_end);
        if (line_start + 1 < line_end and tokens[line_start].kind == .ident and isStructFieldName(tokens[line_start].lexeme)) {
            const type_end = findStructFieldTypeEnd(tokens, line_start + 1, line_end);
            try checkUnboundTypeNamesInRange(tokens, decl_start_idx, line_start + 1, type_end);
        }
        i = line_end;
    }
}

fn checkUnboundTypeNamesInRange(
    tokens: []const lexer.Token,
    decl_start_idx: usize,
    start_idx: usize,
    end_idx: usize,
) !void {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (isWitOnlySourceTypeName(tokens[i].lexeme)) {
            return markErrorAt(tokens, i, error.InvalidTypeRef);
        }
        if (!isValidDeclaredTypeName(tokens[i].lexeme)) continue;
        const name = publicTypeName(tokens[i].lexeme);
        if (hasConcreteTypeName(tokens, name)) continue;
        if (declHasTypeConstraintName(tokens, decl_start_idx, name)) continue;
        if (!hasPriorTypeConstraintName(tokens, decl_start_idx, name)) continue;
        return markErrorAt(tokens, i, error.InvalidTypeRef);
    }
}

fn declHasTypeConstraintName(tokens: []const lexer.Token, decl_start_idx: usize, name: []const u8) bool {
    const block_start = findConstraintBlockStartBefore(tokens, decl_start_idx) orelse return false;
    return hasTypeConstraintName(tokens, block_start, decl_start_idx, name);
}

fn hasPriorTypeConstraintName(tokens: []const lexer.Token, before_idx: usize, name: []const u8) bool {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < before_idx and i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (depth_brace == 0) {
                if (parseImportDeclEnd(tokens, i)) |next_idx| {
                    i = next_idx - 1;
                    continue;
                }
            }
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (!tokEq(tokens[i], "#")) continue;

        const line_end = findLineEndIdx(tokens, i);
        const is_func_constraint = i + 2 < line_end and tokEq(tokens[i + 2], "(");
        if (!is_func_constraint and i + 1 < line_end and std.mem.eql(u8, tokens[i + 1].lexeme, name)) return true;
        i = line_end - 1;
    }
    return false;
}

fn findFuncDeclSignatureEnd(tokens: []const lexer.Token, start_idx: usize) usize {
    var i = start_idx;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) return i;
        if (isArrowAt(tokens, i)) return i;
    }
    return i;
}

fn isTypeArgStartAfterSeparator(tokens: []const lexer.Token, idx: usize) bool {
    if (idx == 0) return false;
    const prev = tokens[idx - 1];
    if (!tokEq(prev, "<") and !tokEq(prev, ",")) return false;
    return hasOpenTypeArgAngleBefore(tokens, idx);
}

fn hasOpenTypeArgAngleBefore(tokens: []const lexer.Token, idx: usize) bool {
    var depth_angle: usize = 0;
    var i = lineStartIdx(tokens, idx);
    while (i < idx) : (i += 1) {
        if (tokEq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (!tokEq(tokens[i], ">")) continue;
        if (i > 0 and tokEq(tokens[i - 1], "-")) continue;
        if (depth_angle > 0) depth_angle -= 1;
    }
    return depth_angle > 0;
}

fn isNilUnionBranch(tokens: []const lexer.Token, idx: usize) bool {
    if (idx > 0 and tokens[idx - 1].line == tokens[idx].line and tokEq(tokens[idx - 1], "|")) return true;
    if (idx + 1 < tokens.len and tokens[idx + 1].line == tokens[idx].line and tokEq(tokens[idx + 1], "|")) return true;
    return false;
}

fn hasDuplicateNilInUnionSegment(tokens: []const lexer.Token, idx: usize) bool {
    const start = nilUnionSegmentStart(tokens, idx);
    const end = nilUnionSegmentEnd(tokens, idx);
    var nil_count: usize = 0;
    var saw_pipe = false;

    var i = start;
    while (i < end) : (i += 1) {
        if (tokEq(tokens[i], "|")) {
            saw_pipe = true;
            continue;
        }
        if (tokEq(tokens[i], "nil")) nil_count += 1;
    }

    return saw_pipe and nil_count > 1;
}

fn nilUnionSegmentStart(tokens: []const lexer.Token, idx: usize) usize {
    var start = idx;
    while (start > 0 and tokens[start - 1].line == tokens[idx].line) {
        if (isNilUnionBoundaryBefore(tokens, start)) break;
        start -= 1;
    }
    return start;
}

fn nilUnionSegmentEnd(tokens: []const lexer.Token, idx: usize) usize {
    var end = idx + 1;
    while (end < tokens.len and tokens[end].line == tokens[idx].line) : (end += 1) {
        if (isNilUnionBoundaryToken(tokens[end])) break;
        if (tokEq(tokens[end], "{")) break;
    }
    return end;
}

fn isNilUnionBoundaryBefore(tokens: []const lexer.Token, idx: usize) bool {
    const prev = tokens[idx - 1];
    if (isNilUnionBoundaryToken(prev)) return true;
    return idx >= 2 and tokEq(tokens[idx - 2], "-") and tokEq(tokens[idx - 1], ">");
}

fn isNilUnionBoundaryToken(tok: lexer.Token) bool {
    return tokEq(tok, ",") or tokEq(tok, "(") or tokEq(tok, ")") or tokEq(tok, "=");
}

fn checkDuplicateUnionBranches(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) {
        if (!tokEq(tokens[i], "|")) {
            i += 1;
            continue;
        }

        const start = unionSegmentStart(tokens, i);
        const end = unionSegmentEnd(tokens, i);
        try checkDuplicateUnionBranchSegment(tokens, start, end);
        i = end;
    }
}

fn unionSegmentStart(tokens: []const lexer.Token, idx: usize) usize {
    var depth_paren: usize = 0;
    var depth_angle: usize = 0;
    var depth_bracket: usize = 0;
    var start = idx;

    while (start > 0 and tokens[start - 1].line == tokens[idx].line) {
        if (depth_paren == 0 and depth_angle == 0 and depth_bracket == 0 and isUnionSegmentBoundaryBefore(tokens, start)) break;

        const prev_idx = start - 1;
        if (tokEq(tokens[prev_idx], ")")) {
            depth_paren += 1;
        } else if (tokEq(tokens[prev_idx], "(")) {
            if (depth_paren == 0) break;
            depth_paren -= 1;
        } else if (tokEq(tokens[prev_idx], ">")) {
            depth_angle += 1;
        } else if (tokEq(tokens[prev_idx], "<")) {
            if (depth_angle == 0) break;
            depth_angle -= 1;
        } else if (tokEq(tokens[prev_idx], "]")) {
            depth_bracket += 1;
        } else if (tokEq(tokens[prev_idx], "[")) {
            if (depth_bracket == 0) break;
            depth_bracket -= 1;
        }

        start = prev_idx;
    }

    return start;
}

fn unionSegmentEnd(tokens: []const lexer.Token, idx: usize) usize {
    var depth_paren: usize = 0;
    var depth_angle: usize = 0;
    var depth_bracket: usize = 0;
    var end = idx + 1;

    while (end < tokens.len and tokens[end].line == tokens[idx].line) : (end += 1) {
        if (depth_paren == 0 and depth_angle == 0 and depth_bracket == 0 and isUnionSegmentEndBoundary(tokens[end])) break;

        if (tokEq(tokens[end], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tokEq(tokens[end], ")")) {
            if (depth_paren == 0) break;
            depth_paren -= 1;
            continue;
        }
        if (tokEq(tokens[end], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tokEq(tokens[end], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (tokEq(tokens[end], "[")) {
            depth_bracket += 1;
            continue;
        }
        if (tokEq(tokens[end], "]")) {
            if (depth_bracket == 0) break;
            depth_bracket -= 1;
            continue;
        }
    }

    return end;
}

fn isUnionSegmentBoundaryBefore(tokens: []const lexer.Token, idx: usize) bool {
    const prev = tokens[idx - 1];
    if (tokEq(prev, ",") or tokEq(prev, "=") or tokEq(prev, "{")) return true;
    return idx >= 2 and tokEq(tokens[idx - 2], "-") and tokEq(tokens[idx - 1], ">");
}

fn isUnionSegmentEndBoundary(tok: lexer.Token) bool {
    return tokEq(tok, ",") or tokEq(tok, "=") or tokEq(tok, "{") or tokEq(tok, ")");
}

fn checkInlineFuncTypeUnionBranches(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tokEq(tokens[i], "|")) continue;
        if (inlineFuncTypeBranchBeforePipe(tokens, i)) |site| return markErrorAt(tokens, site, error.InvalidTypeRef);
        if (inlineFuncTypeBranchAfterPipe(tokens, i)) |site| return markErrorAt(tokens, site, error.InvalidTypeRef);
    }
}

fn inlineFuncTypeBranchBeforePipe(tokens: []const lexer.Token, pipe_idx: usize) ?usize {
    if (pipe_idx == 0) return null;
    const close_idx = pipe_idx - 1;
    if (!tokEq(tokens[close_idx], ")")) return null;
    const open_idx = findMatchingOpen(tokens, close_idx, "(", ")") orelse return null;
    if (!isParenthesizedFuncTypeBranch(tokens, open_idx, pipe_idx)) return null;
    return open_idx;
}

fn inlineFuncTypeBranchAfterPipe(tokens: []const lexer.Token, pipe_idx: usize) ?usize {
    const start_idx = pipe_idx + 1;
    if (start_idx >= tokens.len) return null;
    if (!tokEq(tokens[start_idx], "(")) return null;
    if (isFuncTypeStart(tokens, start_idx)) return start_idx;
    if (!isParenthesizedFuncTypeBranchStart(tokens, start_idx)) return null;
    return start_idx;
}

fn isParenthesizedFuncTypeBranchStart(tokens: []const lexer.Token, start_idx: usize) bool {
    const close_idx = findMatching(tokens, start_idx, "(", ")") catch return false;
    return isParenthesizedFuncTypeBranch(tokens, start_idx, close_idx + 1);
}

fn isParenthesizedFuncTypeBranch(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var start = start_idx;
    var end = end_idx;
    while (start < end and tokEq(tokens[start], "(")) {
        const close_idx = findMatching(tokens, start, "(", ")") catch return false;
        if (close_idx + 1 != end) return false;
        const inner_start = start + 1;
        const inner_end = close_idx;
        if (isFuncTypeRange(tokens, inner_start, inner_end)) return true;
        start = inner_start;
        end = inner_end;
    }
    return false;
}

fn isFuncTypeStart(tokens: []const lexer.Token, start_idx: usize) bool {
    const close_idx = findMatching(tokens, start_idx, "(", ")") catch return false;
    return close_idx + 2 < tokens.len and isReturnArrowAt(tokens, close_idx + 1);
}

fn isFuncTypeRange(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx >= end_idx or !tokEq(tokens[start_idx], "(")) return false;
    const close_idx = findMatching(tokens, start_idx, "(", ")") catch return false;
    return close_idx + 2 < end_idx and isReturnArrowAt(tokens, close_idx + 1);
}

fn findMatchingOpen(tokens: []const lexer.Token, close_idx: usize, open: []const u8, close: []const u8) ?usize {
    if (close_idx >= tokens.len or !tokEq(tokens[close_idx], close)) return null;

    var depth: usize = 0;
    var i = close_idx + 1;
    while (i > 0) {
        i -= 1;
        if (tokEq(tokens[i], close)) {
            depth += 1;
            continue;
        }
        if (!tokEq(tokens[i], open)) continue;

        if (depth == 0) return null;
        depth -= 1;
        if (depth == 0) return i;
    }
    return null;
}

const TokenRange = struct {
    start: usize,
    end: usize,
};

fn checkDuplicateUnionBranchSegment(tokens: []const lexer.Token, start: usize, end: usize) !void {
    var branch_start = start;
    while (branch_start < end) {
        const branch_end = findNextUnionPipe(tokens, branch_start, end);
        const branch_range = normalizedUnionBranchRange(tokens, branch_start, branch_end);

        var prev_start = start;
        while (prev_start < branch_start) {
            const prev_end = findNextUnionPipe(tokens, prev_start, end);
            const prev_range = normalizedUnionBranchRange(tokens, prev_start, prev_end);
            if (unionBranchesEqual(tokens, prev_range, branch_range)) {
                return markErrorAt(tokens, branch_range.start, error.InvalidTypeRef);
            }
            prev_start = if (prev_end < end) prev_end + 1 else end;
        }

        branch_start = if (branch_end < end) branch_end + 1 else end;
    }
}

fn findNextUnionPipe(tokens: []const lexer.Token, start: usize, end: usize) usize {
    var depth_paren: usize = 0;
    var depth_angle: usize = 0;
    var depth_bracket: usize = 0;

    var i = start;
    while (i < end) : (i += 1) {
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
        if (tokEq(tokens[i], "[")) {
            depth_bracket += 1;
            continue;
        }
        if (tokEq(tokens[i], "]")) {
            if (depth_bracket > 0) depth_bracket -= 1;
            continue;
        }
        if (depth_paren == 0 and depth_angle == 0 and depth_bracket == 0 and tokEq(tokens[i], "|")) return i;
    }
    return end;
}

fn normalizedUnionBranchRange(tokens: []const lexer.Token, start: usize, end: usize) TokenRange {
    var out = TokenRange{
        .start = normalizedUnionBranchStart(tokens, start, end),
        .end = end,
    };

    while (out.start + 1 < out.end and tokEq(tokens[out.start], "(")) {
        const close_idx = findMatching(tokens, out.start, "(", ")") catch break;
        if (close_idx + 1 != out.end) break;
        out.start += 1;
        out.end -= 1;
    }

    return out;
}

fn normalizedUnionBranchStart(tokens: []const lexer.Token, start: usize, end: usize) usize {
    if (start + 1 >= end) return start;
    if (tokens[start].kind != .ident) return start;
    if (!isLowerIdentName(tokens[start].lexeme)) return start;
    if (!isTypeAtomStart(tokens[start + 1])) return start;
    return start + 1;
}

fn isTypeAtomStart(tok: lexer.Token) bool {
    if (tokEq(tok, "[") or tokEq(tok, "(")) return true;
    if (tok.kind != .ident or tok.lexeme.len == 0) return false;
    if (std.ascii.isUpper(tok.lexeme[0])) return true;
    return isBaseTypeName(tok.lexeme) or tokEq(tok, "nil");
}

fn isBaseTypeName(name: []const u8) bool {
    const base_types = [_][]const u8{
        "i8",    "i16",   "i32", "i64",
        "u8",    "u16",   "u32", "u64",
        "isize", "usize", "f32", "f64",
        "bool",  "text",
    };
    for (base_types) |it| {
        if (std.mem.eql(u8, it, name)) return true;
    }
    return false;
}

fn isWitOnlySourceTypeName(name: []const u8) bool {
    return std.mem.eql(u8, name, "char");
}

fn isBaseIntTypeName(name: []const u8) bool {
    const base_int_types = [_][]const u8{
        "i8",    "i16",   "i32", "i64",
        "u8",    "u16",   "u32", "u64",
        "isize", "usize",
    };
    for (base_int_types) |it| {
        if (std.mem.eql(u8, it, name)) return true;
    }
    return false;
}

fn isBaseFloatTypeName(name: []const u8) bool {
    return std.mem.eql(u8, name, "f32") or std.mem.eql(u8, name, "f64");
}

fn unionBranchesEqual(
    tokens: []const lexer.Token,
    a: TokenRange,
    b: TokenRange,
) bool {
    if (a.end - a.start != b.end - b.start) return false;
    var offset: usize = 0;
    while (offset < a.end - a.start) : (offset += 1) {
        if (!std.mem.eql(u8, tokens[a.start + offset].lexeme, tokens[b.start + offset].lexeme)) return false;
    }
    return true;
}

fn isNilReturnSpec(tokens: []const lexer.Token, idx: usize) bool {
    return idx >= 2 and
        tokens[idx - 2].line == tokens[idx].line and
        tokens[idx - 1].line == tokens[idx].line and
        tokEq(tokens[idx - 2], "-") and
        tokEq(tokens[idx - 1], ">");
}

fn isBareNilTypeContext(tokens: []const lexer.Token, idx: usize) bool {
    if (idx > 0 and tokens[idx - 1].line == tokens[idx].line) {
        const prev = tokens[idx - 1];
        if (tokEq(prev, "=")) return isTypeDeclOrConstraintLine(tokens, idx);
        if (tokEq(prev, "[") or tokEq(prev, "<")) return true;
        if (prev.kind == .ident and !isKeyword(prev.lexeme)) return true;
    }
    if (idx + 1 < tokens.len and tokens[idx + 1].line == tokens[idx].line) {
        const next = tokens[idx + 1];
        if (tokEq(next, "]") or tokEq(next, ">")) return true;
    }
    return false;
}

fn isTypeDeclOrConstraintLine(tokens: []const lexer.Token, idx: usize) bool {
    const line_start = lineStartIdx(tokens, idx);
    if (tokEq(tokens[line_start], "#")) return true;
    if (tokens[line_start].kind != .ident) return false;
    if (!isValidDeclaredTypeName(tokens[line_start].lexeme)) return false;
    if (!isTopLevelDeclHead(tokens, line_start)) return false;
    return isTypeDeclStart(tokens, line_start);
}

fn checkLoopHeader(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (parseImportDeclEnd(tokens, i)) |next_idx| {
                i = next_idx - 1;
                continue;
            }
        }

        if (!tokEq(tokens[i], "loop")) continue;
        const open_brace = findLoopBlockOpen(tokens, i) orelse return markErrorAt(tokens, i, error.InvalidLoopHeader);
        if (open_brace <= i) return markErrorAt(tokens, i, error.InvalidLoopHeader);

        const header_start = i + 1;
        if (open_brace == header_start) {
            i = open_brace;
            continue; // loop { ... }
        }

        const bind = findLoopBindAssign(tokens, header_start, open_brace) orelse
            return markErrorAt(tokens, header_start, error.InvalidLoopHeader);

        try validateLoopBindLhs(tokens, header_start, bind);
        if (bind + 1 >= open_brace) return markErrorAt(tokens, bind, error.InvalidLoopHeader);
        try checkLoopSource(tokens, header_start, bind, open_brace);
        i = open_brace;
    }
}

const LoopLabelDecl = struct {
    loop_line: usize,
    name: []const u8,
};

const PendingLoopLabel = struct {
    open_idx: usize,
    name: []const u8,
};

const ActiveLoopLabel = struct {
    name: []const u8,
    body_depth: usize,
};

const ActiveLoop = struct {
    body_depth: usize,
};

fn checkLoopLabels(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
    var label_decls = try std.ArrayList(LoopLabelDecl).initCapacity(allocator, 0);
    defer label_decls.deinit(allocator);

    var brace_depth: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) {
        const line_start = i;
        const line_no = tokens[i].line;
        const line_end = findLineEndIdx(tokens, i);

        if (brace_depth > 0 and tokEq(tokens[line_start], "#")) {
            if (line_start + 1 >= line_end or tokens[line_start + 1].kind != .ident) {
                return markErrorAt(tokens, line_start, error.InvalidLoopHeader);
            }
            if (!isValidLoopLabelName(tokens[line_start + 1].lexeme)) {
                return markErrorAt(tokens, line_start + 1, error.InvalidLoopHeader);
            }

            const next_line_start = line_end;
            if (next_line_start >= tokens.len or tokens[next_line_start].line != line_no + 1) {
                return markErrorAt(tokens, line_start, error.InvalidLoopHeader);
            }
            if (!tokEq(tokens[next_line_start], "loop")) {
                return markErrorAt(tokens, next_line_start, error.InvalidLoopHeader);
            }

            try label_decls.append(allocator, .{
                .loop_line = tokens[next_line_start].line,
                .name = tokens[line_start + 1].lexeme,
            });
        }

        var j = line_start;
        while (j < line_end) : (j += 1) {
            if (tokEq(tokens[j], "{")) {
                brace_depth += 1;
                continue;
            }
            if (tokEq(tokens[j], "}")) {
                if (brace_depth > 0) brace_depth -= 1;
            }
        }

        i = line_end;
    }

    var pending_loops = try std.ArrayList(PendingLoopLabel).initCapacity(allocator, 0);
    defer pending_loops.deinit(allocator);

    var pending_loop_opens = try std.ArrayList(usize).initCapacity(allocator, 0);
    defer pending_loop_opens.deinit(allocator);

    var active_loops = try std.ArrayList(ActiveLoop).initCapacity(allocator, 0);
    defer active_loops.deinit(allocator);

    var active_labels = try std.ArrayList(ActiveLoopLabel).initCapacity(allocator, 0);
    defer active_labels.deinit(allocator);

    brace_depth = 0;
    i = 0;
    while (i < tokens.len) {
        const line_start = i;
        const line_end = findLineEndIdx(tokens, i);

        var j = line_start;
        while (j < line_end) : (j += 1) {
            if (tokEq(tokens[j], "loop")) {
                const open_idx = findLoopBlockOpen(tokens, j) orelse return markErrorAt(tokens, j, error.InvalidLoopHeader);
                try pending_loop_opens.append(allocator, open_idx);
                if (labelDeclForLine(label_decls.items, tokens[j].line)) |label_name| {
                    try pending_loops.append(allocator, .{ .open_idx = open_idx, .name = label_name });
                }
            }

            if (tokEq(tokens[j], "break") or tokEq(tokens[j], "continue")) {
                if (active_loops.items.len == 0) {
                    return markErrorAt(tokens, j, error.InvalidLoopHeader);
                }
                if (j + 1 < line_end and tokEq(tokens[j + 1], "#")) {
                    if (j + 2 >= line_end or tokens[j + 2].kind != .ident) {
                        return markErrorAt(tokens, j + 1, error.InvalidLoopHeader);
                    }
                    if (!isValidLoopLabelName(tokens[j + 2].lexeme)) {
                        return markErrorAt(tokens, j + 2, error.InvalidLoopHeader);
                    }
                    if (!labelIsActive(active_labels.items, tokens[j + 2].lexeme)) {
                        return markErrorAt(tokens, j + 1, error.InvalidLoopHeader);
                    }
                }
            }

            if (tokEq(tokens[j], "{")) {
                brace_depth += 1;
                if (pending_loop_opens.items.len > 0 and pending_loop_opens.items[pending_loop_opens.items.len - 1] == j) {
                    _ = pending_loop_opens.pop();
                    try active_loops.append(allocator, .{
                        .body_depth = brace_depth,
                    });
                }
                if (pending_loops.items.len > 0 and pending_loops.items[pending_loops.items.len - 1].open_idx == j) {
                    const pending = pending_loops.pop().?;
                    try active_labels.append(allocator, .{
                        .name = pending.name,
                        .body_depth = brace_depth,
                    });
                }
                continue;
            }
            if (tokEq(tokens[j], "}")) {
                if (brace_depth > 0) brace_depth -= 1;
                while (active_loops.items.len > 0 and active_loops.items[active_loops.items.len - 1].body_depth > brace_depth) {
                    _ = active_loops.pop();
                }
                while (active_labels.items.len > 0 and active_labels.items[active_labels.items.len - 1].body_depth > brace_depth) {
                    _ = active_labels.pop();
                }
            }
        }

        i = line_end;
    }
}

fn labelDeclForLine(decls: []const LoopLabelDecl, line: usize) ?[]const u8 {
    for (decls) |decl| {
        if (decl.loop_line == line) return decl.name;
    }
    return null;
}

fn labelIsActive(labels: []const ActiveLoopLabel, name: []const u8) bool {
    var idx = labels.len;
    while (idx > 0) {
        idx -= 1;
        if (std.mem.eql(u8, labels[idx].name, name)) return true;
    }
    return false;
}

fn isValidLoopLabelName(name: []const u8) bool {
    return isSnakeLowerName(name) and !isKeyword(name);
}

fn checkLoopSource(tokens: []const lexer.Token, header_start: usize, bind_idx: usize, open_brace: usize) !void {
    if (header_start + 1 == bind_idx) {
        if (!isRecvLoopSource(tokens, bind_idx + 1, open_brace) and !isFieldsLoopSource(tokens, bind_idx + 1, open_brace)) {
            return markErrorAt(tokens, bind_idx + 1, error.InvalidLoopHeader);
        }
        return;
    }
    if (bind_idx + 1 >= open_brace) return markErrorAt(tokens, bind_idx, error.InvalidLoopHeader);
    if (tokens[bind_idx + 1].kind != .ident) return;

    const source_name = tokens[bind_idx + 1].lexeme;
    const source_type = findNearestValueTypeName(tokens, bind_idx, source_name) orelse return;
    if (isUnsupportedDirectLoopSource(source_type)) {
        return markErrorAt(tokens, bind_idx + 1, error.InvalidLoopSource);
    }
}

fn isRecvLoopSource(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 3 >= end_idx) return false;
    if (!tokEq(tokens[start_idx], "recv")) return false;
    if (!tokEq(tokens[start_idx + 1], "(")) return false;
    const close_idx = findMatching(tokens, start_idx + 1, "(", ")") catch return false;
    return close_idx + 1 == end_idx;
}

fn isFieldsLoopSource(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 4 != end_idx) return false;
    if (tokens[start_idx].kind != .ident or !std.mem.eql(u8, tokens[start_idx].lexeme, "fields")) return false;
    if (!tokEq(tokens[start_idx + 1], "(")) return false;
    if (tokens[start_idx + 2].kind != .ident) return false;
    if (!isValidDeclaredTypeName(tokens[start_idx + 2].lexeme)) return false;
    return tokEq(tokens[start_idx + 3], ")");
}

fn checkFieldReflection(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
    const funcs = try collectFuncShapes(allocator, tokens);
    defer freeFuncShapes(allocator, funcs);

    const structs = try collectStructInfos(allocator, tokens);
    defer freeStructInfos(allocator, structs);

    var field_bindings = try std.ArrayList(FieldMetaBinding).initCapacity(allocator, 0);
    defer field_bindings.deinit(allocator);

    var pending_field_loop_opens = try std.ArrayList(FieldMetaBinding).initCapacity(allocator, 0);
    defer pending_field_loop_opens.deinit(allocator);

    var brace_depth: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "loop")) {
            if (try fieldReflectionLoopBinding(tokens, i)) |binding| {
                try pending_field_loop_opens.append(allocator, binding);
            }
        }

        if (tokens[i].kind == .ident and isFieldReflectFuncName(tokens[i].lexeme)) {
            try checkFieldReflectCall(tokens, i, field_bindings.items);
            if (std.mem.eql(u8, tokens[i].lexeme, "field_get")) {
                try checkFieldGetStaticUse(allocator, tokens, i, field_bindings.items, structs, funcs);
            } else if (std.mem.eql(u8, tokens[i].lexeme, "field_set")) {
                try checkFieldSetStaticUse(allocator, tokens, i, field_bindings.items, structs, funcs);
            }
        }

        if (tokens[i].kind == .ident and isActiveFieldMetaBinding(field_bindings.items, tokens[i].lexeme) and
            !isAllowedFieldMetaUse(tokens, i))
        {
            return markErrorAt(tokens, i, error.InvalidFieldReflection);
        }

        if (tokEq(tokens[i], "{")) {
            brace_depth += 1;
            while (pending_field_loop_opens.items.len > 0) {
                const last = pending_field_loop_opens.items[pending_field_loop_opens.items.len - 1];
                if (last.body_depth != brace_depth) break;
                const binding = pending_field_loop_opens.pop().?;
                try field_bindings.append(allocator, binding);
            }
            continue;
        }

        if (tokEq(tokens[i], "}")) {
            if (brace_depth > 0) brace_depth -= 1;
            while (field_bindings.items.len > 0 and field_bindings.items[field_bindings.items.len - 1].body_depth > brace_depth) {
                _ = field_bindings.pop();
            }
            continue;
        }
    }
}

fn isActiveFieldMetaBinding(field_bindings: []const FieldMetaBinding, name: []const u8) bool {
    return findActiveFieldMetaBinding(field_bindings, name) != null;
}

fn findActiveFieldMetaBinding(field_bindings: []const FieldMetaBinding, name: []const u8) ?FieldMetaBinding {
    for (field_bindings) |binding| {
        if (std.mem.eql(u8, binding.name, name)) return binding;
    }
    return null;
}

fn isFieldReflectFuncName(name: []const u8) bool {
    return std.mem.eql(u8, name, "field_name") or
        std.mem.eql(u8, name, "field_index") or
        std.mem.eql(u8, name, "field_has_default") or
        std.mem.eql(u8, name, "field_get") or
        std.mem.eql(u8, name, "field_set");
}

fn isAllowedFieldMetaUse(tokens: []const lexer.Token, field_idx: usize) bool {
    var i = field_idx;
    while (i > 0) {
        i -= 1;
        if (!tokEq(tokens[i], "@")) continue;
        if (i + 2 >= tokens.len) continue;
        if (tokens[i + 1].kind != .ident or !isFieldReflectFuncName(tokens[i + 1].lexeme)) continue;
        if (!tokEq(tokens[i + 2], "(")) continue;

        const close_paren = findMatching(tokens, i + 2, "(", ")") catch return false;
        if (close_paren < field_idx) continue;
        const field_arg = fieldReflectFieldArgRange(tokens, i + 1, close_paren) orelse return false;
        return field_arg.start == field_idx and field_arg.end == field_idx + 1;
    }
    return false;
}

fn fieldReflectionLoopBinding(tokens: []const lexer.Token, loop_idx: usize) !?FieldMetaBinding {
    const open_brace = findLoopBlockOpen(tokens, loop_idx) orelse return null;
    const bind_idx = findLoopBindAssign(tokens, loop_idx + 1, open_brace) orelse return null;
    if (loop_idx + 2 != bind_idx) return null;
    if (tokens[loop_idx + 1].kind != .ident) return null;
    if (!isFieldsLoopSource(tokens, bind_idx + 1, open_brace)) return null;

    const type_idx = bind_idx + 3;
    if (!fieldReflectionSourceTypeAllowed(tokens, loop_idx, type_idx)) {
        return markErrorAt(tokens, type_idx, error.InvalidFieldReflection);
    }

    return .{
        .name = tokens[loop_idx + 1].lexeme,
        .struct_name = publicTypeName(tokens[type_idx].lexeme),
        .body_depth = braceDepthBefore(tokens, open_brace) + 1,
    };
}

fn fieldReflectionSourceTypeAllowed(tokens: []const lexer.Token, loop_idx: usize, type_idx: usize) bool {
    const type_name = publicTypeName(tokens[type_idx].lexeme);
    if (hasLocalStructDecl(tokens, type_name)) return true;
    if (isFuncTypeParamAt(tokens, loop_idx, type_name)) return true;
    if (isImportedUpperAlias(tokens, type_name)) return true;
    return false;
}

fn isFuncTypeParamAt(tokens: []const lexer.Token, idx: usize, name: []const u8) bool {
    const func_start = findEnclosingFuncStart(tokens, idx) orelse return false;
    return isFuncTypeParam(tokens, func_start, name);
}

fn findEnclosingFuncStart(tokens: []const lexer.Token, idx: usize) ?usize {
    var skip_depth: usize = 0;
    var i = idx;
    while (i > 0) {
        i -= 1;

        if (tokEq(tokens[i], "}")) {
            skip_depth += 1;
            continue;
        }
        if (!tokEq(tokens[i], "{")) continue;
        if (skip_depth > 0) {
            skip_depth -= 1;
            continue;
        }

        const line_start = lineStartIdx(tokens, i);
        if (line_start < i and isFuncDeclStart(tokens, line_start)) return line_start;
    }
    return null;
}

fn checkFieldReflectCall(tokens: []const lexer.Token, name_idx: usize, field_bindings: []const FieldMetaBinding) !void {
    if (name_idx == 0 or !tokEq(tokens[name_idx - 1], "@")) return;
    if (name_idx + 1 >= tokens.len or !tokEq(tokens[name_idx + 1], "(")) {
        return markErrorAt(tokens, name_idx, error.InvalidFieldReflection);
    }

    const close_paren = findMatching(tokens, name_idx + 1, "(", ")") catch
        return markErrorAt(tokens, name_idx + 1, error.InvalidFieldReflection);
    const field_arg = fieldReflectFieldArgRange(tokens, name_idx, close_paren) orelse
        return markErrorAt(tokens, name_idx, error.InvalidFieldReflection);
    if (!isFieldMetaArg(tokens, field_arg, field_bindings)) {
        return markErrorAt(tokens, field_arg.start, error.InvalidFieldReflection);
    }
    if (std.mem.eql(u8, tokens[name_idx].lexeme, "field_set") and !isFieldSetSelfAssignment(tokens, name_idx, close_paren)) {
        return markErrorAt(tokens, name_idx, error.InvalidFieldReflection);
    }
}

fn fieldReflectFieldArgRange(tokens: []const lexer.Token, name_idx: usize, close_paren: usize) ?ArgRange {
    if (std.mem.eql(u8, tokens[name_idx].lexeme, "field_name") or
        std.mem.eql(u8, tokens[name_idx].lexeme, "field_index") or
        std.mem.eql(u8, tokens[name_idx].lexeme, "field_has_default"))
    {
        return singleArgRange(tokens, name_idx + 2, close_paren);
    }

    if (std.mem.eql(u8, tokens[name_idx].lexeme, "field_get") or
        std.mem.eql(u8, tokens[name_idx].lexeme, "field_set"))
    {
        return nthArgRange(tokens, name_idx + 2, close_paren, 1);
    }

    return null;
}

fn isFieldMetaArg(tokens: []const lexer.Token, arg: ArgRange, field_bindings: []const FieldMetaBinding) bool {
    if (arg.start + 1 != arg.end) return false;
    if (tokens[arg.start].kind != .ident) return false;
    for (field_bindings) |binding| {
        if (std.mem.eql(u8, binding.name, tokens[arg.start].lexeme)) return true;
    }
    return false;
}

fn isFieldSetSelfAssignment(tokens: []const lexer.Token, name_idx: usize, close_paren: usize) bool {
    const line_start = lineStartIdx(tokens, name_idx);
    const line_end = findLineEndIdx(tokens, name_idx);
    if (close_paren + 1 != line_end) return false;
    const eq_idx = findTopLevelAssignEqOnLine(tokens, line_start, line_end) orelse return false;
    if (eq_idx + 1 != name_idx - 1) return false;
    if (line_start + 1 != eq_idx or tokens[line_start].kind != .ident) return false;

    const target_arg = nthArgRange(tokens, name_idx + 2, close_paren, 0) orelse return false;
    if (target_arg.start + 1 != target_arg.end) return false;
    if (tokens[target_arg.start].kind != .ident) return false;
    return std.mem.eql(u8, tokens[line_start].lexeme, tokens[target_arg.start].lexeme);
}

const FieldGetCandidate = struct {
    name: []const u8,
    ty: []const u8,
    index: usize,
    has_default: bool,
};

const FieldGetBindingUse = struct {
    type_start: usize,
    type_end: usize,
};

const FieldStaticValue = union(enum) {
    bool: bool,
    int: usize,
    text: []const u8,
};

const FieldStaticIfParts = struct {
    cond_start: usize,
    cond_end: usize,
    then_start: usize,
    then_end: usize,
    else_if_start: ?usize = null,
    else_start: ?usize = null,
    else_end: usize = 0,
};

const FieldExprRange = struct {
    start: usize,
    end: usize,
};

const FieldStaticCallHead = struct {
    name_idx: usize,
    args_start: usize,
    args_end: usize,
    is_intrinsic: bool,
};

fn checkFieldGetStaticUse(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    name_idx: usize,
    field_bindings: []const FieldMetaBinding,
    structs: []const StructInfo,
    funcs: []const FuncShape,
) !void {
    if (name_idx == 0 or !tokEq(tokens[name_idx - 1], "@")) return;
    if (name_idx + 1 >= tokens.len or !tokEq(tokens[name_idx + 1], "(")) return;

    const close_paren = findMatching(tokens, name_idx + 1, "(", ")") catch return;
    const field_arg = fieldReflectFieldArgRange(tokens, name_idx, close_paren) orelse return;
    if (field_arg.start + 1 != field_arg.end or tokens[field_arg.start].kind != .ident) return;

    const binding = findActiveFieldMetaBinding(field_bindings, tokens[field_arg.start].lexeme) orelse return;
    const struct_info = findStructInfo(structs, binding.struct_name) orelse return;

    var candidates = try collectFieldGetCandidatesAtUse(allocator, tokens, name_idx, binding, struct_info);
    defer candidates.deinit(allocator);
    if (candidates.items.len == 0) return;

    if (fieldGetDirectBindingUse(tokens, name_idx, close_paren)) |binding_use| {
        if (!fieldGetCandidatesMatchBinding(tokens, candidates.items, binding_use)) {
            return markErrorAt(tokens, name_idx, error.InvalidFieldReflection);
        }
    }

    if (callArgInfo(tokens, name_idx)) |call| {
        if (hasKnownFuncCandidate(funcs, call.name) and !fieldGetCandidatesMatchCall(tokens, funcs, call, candidates.items)) {
            return markErrorAt(tokens, name_idx, error.InvalidFieldReflection);
        }
    }
}

fn checkFieldSetStaticUse(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    name_idx: usize,
    field_bindings: []const FieldMetaBinding,
    structs: []const StructInfo,
    funcs: []const FuncShape,
) !void {
    if (name_idx == 0 or !tokEq(tokens[name_idx - 1], "@")) return;
    if (name_idx + 1 >= tokens.len or !tokEq(tokens[name_idx + 1], "(")) return;

    const close_paren = findMatching(tokens, name_idx + 1, "(", ")") catch return;
    const field_arg = fieldReflectFieldArgRange(tokens, name_idx, close_paren) orelse return;
    if (field_arg.start + 1 != field_arg.end or tokens[field_arg.start].kind != .ident) return;

    const binding = findActiveFieldMetaBinding(field_bindings, tokens[field_arg.start].lexeme) orelse return;
    const struct_info = findStructInfo(structs, binding.struct_name) orelse return;

    const value_arg = fieldSetValueArgRange(tokens, name_idx, close_paren) orelse
        return markErrorAt(tokens, name_idx, error.InvalidFieldReflection);

    var candidates = try collectFieldGetCandidatesAtUse(allocator, tokens, name_idx, binding, struct_info);
    defer candidates.deinit(allocator);
    if (candidates.items.len == 0) return;

    if (!fieldSetCandidatesAcceptValue(tokens, funcs, value_arg, candidates.items)) {
        return markErrorAt(tokens, name_idx, error.InvalidFieldReflection);
    }
}

fn fieldSetValueArgRange(tokens: []const lexer.Token, name_idx: usize, close_paren: usize) ?ArgRange {
    const args_start = name_idx + 2;
    const first_end = findArgEndAny(tokens, args_start, close_paren);
    if (first_end >= close_paren or !tokEq(tokens[first_end], ",")) return null;
    const field_start = first_end + 1;
    const field_end = findArgEndAny(tokens, field_start, close_paren);
    if (field_end >= close_paren or !tokEq(tokens[field_end], ",")) return null;
    const value_start = field_end + 1;
    const value_end = findArgEndAny(tokens, value_start, close_paren);
    if (value_start >= value_end or value_end != close_paren) return null;
    return .{ .start = value_start, .end = value_end };
}

fn fieldSetCandidatesAcceptValue(
    tokens: []const lexer.Token,
    funcs: []const FuncShape,
    value_arg: ArgRange,
    candidates: []const FieldGetCandidate,
) bool {
    for (candidates) |candidate| {
        if (!(fieldSetValueCompatibleWithType(tokens, funcs, value_arg.start, value_arg.end, candidate.ty) orelse true)) {
            return false;
        }
    }
    return true;
}

fn fieldSetValueCompatibleWithType(
    tokens: []const lexer.Token,
    funcs: []const FuncShape,
    start_idx: usize,
    end_idx: usize,
    expected_ty: []const u8,
) ?bool {
    const range = fieldTrimParens(tokens, start_idx, end_idx);
    if (range.start >= range.end) return null;

    if (range.end == range.start + 1) {
        const tok = tokens[range.start];
        if (tok.kind == .string) {
            return fieldSetExpectedAcceptsKnownType(expected_ty, "text") or fieldSetExpectedAcceptsKnownType(expected_ty, "[u8]");
        }
        if (tok.kind == .number) {
            return fieldSetNumberLiteralAcceptsType(tok.lexeme, expected_ty);
        }
        if (tokEq(tok, "true") or tokEq(tok, "false")) {
            return fieldSetExpectedAcceptsKnownType(expected_ty, "bool");
        }
        if (tokEq(tok, "nil")) {
            return fieldSetExpectedAcceptsKnownType(expected_ty, "nil");
        }
        if (tok.kind == .ident) {
            const actual_ty = findNearestValueTypeName(tokens, range.start, tok.lexeme) orelse return null;
            return fieldSetExpectedAcceptsKnownType(expected_ty, actual_ty);
        }
        return null;
    }

    const call_head = fieldStaticCallHead(tokens, range) orelse return null;
    if (call_head.is_intrinsic) return null;
    const actual_ty = fieldSetCallReturnType(tokens, funcs, call_head) orelse return null;
    return fieldSetExpectedAcceptsKnownType(expected_ty, actual_ty);
}

fn fieldSetCallReturnType(tokens: []const lexer.Token, funcs: []const FuncShape, call: FieldStaticCallHead) ?[]const u8 {
    const arg_count = countFieldStaticCallArgs(tokens, call.args_start, call.args_end) orelse return null;
    var found: ?[]const u8 = null;
    for (funcs) |func| {
        if (!std.mem.eql(u8, func.name, tokens[call.name_idx].lexeme)) continue;
        if (!callArityCompatibleWithFunc(func, arg_count)) continue;
        const return_ty = func.return_type orelse return null;
        if (found) |prev| {
            if (!std.mem.eql(u8, prev, return_ty)) return null;
        } else {
            found = return_ty;
        }
    }
    return found;
}

fn countFieldStaticCallArgs(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (start_idx == end_idx) return 0;
    var count: usize = 0;
    var arg_start = start_idx;
    while (arg_start < end_idx) {
        const arg_end = findArgEndAny(tokens, arg_start, end_idx);
        if (arg_end == arg_start) return null;
        count += 1;
        arg_start = arg_end;
        if (arg_start < end_idx) {
            if (!tokEq(tokens[arg_start], ",")) return null;
            arg_start += 1;
        }
    }
    return count;
}

fn fieldSetExpectedAcceptsKnownType(expected_ty: []const u8, actual_ty: []const u8) bool {
    if (std.mem.eql(u8, expected_ty, actual_ty)) return true;
    var it = std.mem.splitScalar(u8, expected_ty, '|');
    while (it.next()) |branch| {
        if (std.mem.eql(u8, branch, actual_ty)) return true;
    }
    return false;
}

fn fieldSetNumberLiteralAcceptsType(lexeme: []const u8, expected_ty: []const u8) bool {
    const is_float = std.mem.indexOfScalar(u8, lexeme, '.') != null;
    if (fieldSetNumericBranchAcceptsLiteral(expected_ty, is_float)) return true;
    var it = std.mem.splitScalar(u8, expected_ty, '|');
    while (it.next()) |branch| {
        if (fieldSetNumericBranchAcceptsLiteral(branch, is_float)) return true;
    }
    return false;
}

fn fieldSetNumericBranchAcceptsLiteral(branch_ty: []const u8, is_float_literal: bool) bool {
    if (is_float_literal) return isBaseFloatTypeName(branch_ty);
    return isBaseIntTypeName(branch_ty) or isBaseFloatTypeName(branch_ty);
}

fn collectFieldGetCandidatesAtUse(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    use_idx: usize,
    binding: FieldMetaBinding,
    struct_info: StructInfo,
) !std.ArrayList(FieldGetCandidate) {
    var candidates = std.ArrayList(FieldGetCandidate).empty;
    errdefer candidates.deinit(allocator);

    for (struct_info.fields, 0..) |field, idx| {
        const ty = field.ty orelse continue;
        try candidates.append(allocator, .{
            .name = field.name,
            .ty = ty,
            .index = idx,
            .has_default = field.has_default,
        });
    }

    try filterFieldGetCandidatesByStaticGuards(allocator, tokens, use_idx, binding, &candidates);
    return candidates;
}

fn filterFieldGetCandidatesByStaticGuards(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    use_idx: usize,
    binding: FieldMetaBinding,
    candidates: *std.ArrayList(FieldGetCandidate),
) !void {
    var i: usize = 0;
    while (i < use_idx and i < tokens.len) : (i += 1) {
        if (!tokEq(tokens[i], "if")) continue;
        const stmt_end = findFieldStaticStmtEnd(tokens, i, tokens.len);
        const parts = fieldStaticIfParts(tokens, i, stmt_end) orelse continue;

        if (use_idx >= parts.then_start and use_idx < parts.then_end) {
            try filterFieldGetCandidatesByCondition(allocator, tokens, parts.cond_start, parts.cond_end, true, binding, candidates);
            continue;
        }
        if (parts.else_if_start) |else_if_start| {
            if (use_idx >= else_if_start and use_idx < stmt_end) {
                try filterFieldGetCandidatesByCondition(allocator, tokens, parts.cond_start, parts.cond_end, false, binding, candidates);
            }
            continue;
        }
        if (parts.else_start) |else_start| {
            if (use_idx >= else_start and use_idx < parts.else_end) {
                try filterFieldGetCandidatesByCondition(allocator, tokens, parts.cond_start, parts.cond_end, false, binding, candidates);
            }
        }
    }
}

fn filterFieldGetCandidatesByCondition(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    cond_start: usize,
    cond_end: usize,
    expected: bool,
    binding: FieldMetaBinding,
    candidates: *std.ArrayList(FieldGetCandidate),
) !void {
    var idx: usize = 0;
    while (idx < candidates.items.len) {
        const value = fieldStaticBoolForCandidate(tokens, cond_start, cond_end, binding, candidates.items[idx]) orelse return;
        if (value == expected) {
            idx += 1;
            continue;
        }
        _ = candidates.orderedRemove(idx);
    }
    _ = allocator;
}

fn fieldGetCandidatesMatchBinding(
    tokens: []const lexer.Token,
    candidates: []const FieldGetCandidate,
    binding_use: FieldGetBindingUse,
) bool {
    if (candidates.len <= 1) {
        if (binding_use.type_start == binding_use.type_end) return true;
        return compactTokenRangeEquals(tokens, binding_use.type_start, binding_use.type_end, candidates[0].ty);
    }

    if (binding_use.type_start == binding_use.type_end) return fieldGetCandidateTypesHomogeneous(candidates);
    for (candidates) |candidate| {
        if (!compactTokenRangeEquals(tokens, binding_use.type_start, binding_use.type_end, candidate.ty)) return false;
    }
    return true;
}

fn fieldGetCandidateTypesHomogeneous(candidates: []const FieldGetCandidate) bool {
    if (candidates.len <= 1) return true;
    const first = candidates[0].ty;
    for (candidates[1..]) |candidate| {
        if (!std.mem.eql(u8, first, candidate.ty)) return false;
    }
    return true;
}

fn fieldGetDirectBindingUse(
    tokens: []const lexer.Token,
    name_idx: usize,
    close_paren: usize,
) ?FieldGetBindingUse {
    if (name_idx == 0 or !tokEq(tokens[name_idx - 1], "@")) return null;
    const line_start = lineStartIdx(tokens, name_idx);
    const line_end = findLineEndIdx(tokens, name_idx);
    if (close_paren + 1 != line_end) return null;

    const eq_idx = findTopLevelAssignEqOnLine(tokens, line_start, line_end) orelse return null;
    if (eq_idx + 1 != name_idx - 1) return null;
    if (line_start >= eq_idx or tokens[line_start].kind != .ident) return null;
    if (findTopLevelComma(tokens, line_start, eq_idx) != null) return null;

    if (eq_idx == line_start + 1) {
        return .{ .type_start = eq_idx, .type_end = eq_idx };
    }
    return .{ .type_start = line_start + 1, .type_end = eq_idx };
}

fn fieldGetCandidatesMatchCall(
    tokens: []const lexer.Token,
    funcs: []const FuncShape,
    call: CallArgInfo,
    candidates: []const FieldGetCandidate,
) bool {
    for (candidates) |candidate| {
        if (!fieldGetCallAcceptsType(tokens, funcs, call, candidate.ty)) return false;
    }
    return true;
}

fn fieldGetCallAcceptsType(
    tokens: []const lexer.Token,
    funcs: []const FuncShape,
    call: CallArgInfo,
    actual_ty: []const u8,
) bool {
    for (funcs) |func| {
        if (!std.mem.eql(u8, func.name, call.name)) continue;
        if (!callArityCompatibleWithFunc(func, call.arg_count)) continue;
        const param = fieldGetParamShapeForArg(func, call.arg_index) orelse continue;
        if (fieldGetParamAcceptsType(tokens, func, param, actual_ty)) return true;
    }
    return false;
}

fn fieldGetParamShapeForArg(func: FuncShape, arg_index: usize) ?FuncParamShape {
    if (arg_index < func.param_shapes.len) return func.param_shapes[arg_index];
    if (func.param_shapes.len == 0) return null;
    const last = func.param_shapes[func.param_shapes.len - 1];
    return switch (last) {
        .variadic => last,
        else => null,
    };
}

fn fieldGetParamAcceptsType(
    tokens: []const lexer.Token,
    func: FuncShape,
    param: FuncParamShape,
    actual_ty: []const u8,
) bool {
    const expected = switch (param) {
        .value => |ty| ty orelse return true,
        .variadic => |ty| ty orelse return true,
        .other => return true,
        .func => return false,
    };
    if (std.mem.eql(u8, expected, actual_ty)) return true;
    if (isFuncTypeParam(tokens, func.start_idx, expected) and !typeConstraintIsFunctionType(tokens, func.start_idx, expected)) return true;
    return fieldGetParamContainsDataTypeParam(tokens, func, expected);
}

fn fieldGetParamContainsDataTypeParam(tokens: []const lexer.Token, func: FuncShape, expected: []const u8) bool {
    const close_params = findMatching(tokens, func.start_idx + 1, "(", ")") catch return false;
    var seg_start = func.start_idx + 2;
    var i = seg_start;
    while (i <= close_params) : (i += 1) {
        if (i < close_params and !isTopLevelCommaAny(tokens, i, func.start_idx + 2, close_params)) continue;
        const type_start = funcParamTypeStart(tokens, seg_start, i) orelse {
            seg_start = i + 1;
            continue;
        };
        if (!compactTokenRangeEquals(tokens, type_start, i, expected)) {
            seg_start = i + 1;
            continue;
        }
        var j = type_start;
        while (j < i) : (j += 1) {
            if (tokens[j].kind != .ident) continue;
            if (isFuncTypeParam(tokens, func.start_idx, tokens[j].lexeme) and !typeConstraintIsFunctionType(tokens, func.start_idx, tokens[j].lexeme)) return true;
        }
        return false;
    }
    return false;
}

fn findFieldStaticStmtEnd(tokens: []const lexer.Token, start_idx: usize, limit_idx: usize) usize {
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

fn fieldStaticIfParts(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ?FieldStaticIfParts {
    if (start_idx + 4 > end_idx) return null;
    if (!tokEq(tokens[start_idx], "if")) return null;
    const open_brace = findFieldStaticBlockOpen(tokens, start_idx + 1, end_idx) orelse return null;
    const close_brace = findMatchingInRange(tokens, open_brace, "{", "}", end_idx) catch return null;
    var parts = FieldStaticIfParts{
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

fn findFieldStaticBlockOpen(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
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

fn fieldStaticBoolForCandidate(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    binding: FieldMetaBinding,
    candidate: FieldGetCandidate,
) ?bool {
    if (fieldStaticValueForCandidate(tokens, start_idx, end_idx, binding, candidate)) |value| {
        return switch (value) {
            .bool => |b| b,
            else => null,
        };
    }

    const range = fieldTrimParens(tokens, start_idx, end_idx);
    const call_head = fieldStaticCallHead(tokens, range) orelse return null;
    const call_name = tokens[call_head.name_idx].lexeme;
    if (!call_head.is_intrinsic) return null;

    if (std.mem.eql(u8, call_name, "not")) {
        const arg_end = findArgEndAny(tokens, call_head.args_start, call_head.args_end);
        if (arg_end != call_head.args_end) return null;
        return !(fieldStaticBoolForCandidate(tokens, call_head.args_start, arg_end, binding, candidate) orelse return null);
    }
    if (std.mem.eql(u8, call_name, "and") or std.mem.eql(u8, call_name, "or")) {
        var arg_start = call_head.args_start;
        var saw_arg = false;
        while (arg_start < call_head.args_end) {
            const arg_end = findArgEndAny(tokens, arg_start, call_head.args_end);
            const value = fieldStaticBoolForCandidate(tokens, arg_start, arg_end, binding, candidate) orelse return null;
            saw_arg = true;
            if (std.mem.eql(u8, call_name, "and") and !value) return false;
            if (std.mem.eql(u8, call_name, "or") and value) return true;
            arg_start = arg_end;
            if (arg_start < call_head.args_end and tokEq(tokens[arg_start], ",")) arg_start += 1;
        }
        if (!saw_arg) return null;
        return std.mem.eql(u8, call_name, "and");
    }
    if (std.mem.eql(u8, call_name, "eq") or std.mem.eql(u8, call_name, "ne")) {
        const first_end = findArgEndAny(tokens, call_head.args_start, call_head.args_end);
        if (first_end >= call_head.args_end or !tokEq(tokens[first_end], ",")) return null;
        const second_start = first_end + 1;
        const second_end = findArgEndAny(tokens, second_start, call_head.args_end);
        if (second_end != call_head.args_end) return null;
        const left = fieldStaticValueForCandidate(tokens, call_head.args_start, first_end, binding, candidate) orelse return null;
        const right = fieldStaticValueForCandidate(tokens, second_start, second_end, binding, candidate) orelse return null;
        const is_equal = fieldStaticValuesEqual(left, right);
        return if (std.mem.eql(u8, call_name, "eq")) is_equal else !is_equal;
    }
    return null;
}

fn fieldStaticValueForCandidate(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    binding: FieldMetaBinding,
    candidate: FieldGetCandidate,
) ?FieldStaticValue {
    const range = fieldTrimParens(tokens, start_idx, end_idx);
    if (range.start >= range.end) return null;

    if (range.end == range.start + 1) {
        const tok = tokens[range.start];
        if (tok.kind == .number) return .{ .int = std.fmt.parseUnsigned(usize, tok.lexeme, 10) catch return null };
        if (tok.kind == .string) return .{ .text = stringTokenBody(tok.lexeme) orelse return null };
        if (tokEq(tok, "true")) return .{ .bool = true };
        if (tokEq(tok, "false")) return .{ .bool = false };
        return null;
    }

    const call_head = fieldStaticCallHead(tokens, range) orelse return null;
    if (!call_head.is_intrinsic) return null;
    const call_name = tokens[call_head.name_idx].lexeme;
    if (std.mem.eql(u8, call_name, "field_name")) {
        if (!fieldStaticSingleMetaArgMatches(tokens, call_head.args_start, call_head.args_end, binding.name)) return null;
        return .{ .text = candidate.name };
    }
    if (std.mem.eql(u8, call_name, "field_index")) {
        if (!fieldStaticSingleMetaArgMatches(tokens, call_head.args_start, call_head.args_end, binding.name)) return null;
        return .{ .int = candidate.index };
    }
    if (std.mem.eql(u8, call_name, "field_has_default")) {
        if (!fieldStaticSingleMetaArgMatches(tokens, call_head.args_start, call_head.args_end, binding.name)) return null;
        return .{ .bool = candidate.has_default };
    }
    return null;
}

fn fieldStaticSingleMetaArgMatches(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    binding_name: []const u8,
) bool {
    const arg = singleArgRange(tokens, start_idx, end_idx) orelse return false;
    if (arg.start + 1 != arg.end or tokens[arg.start].kind != .ident) return false;
    return std.mem.eql(u8, tokens[arg.start].lexeme, binding_name);
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

fn fieldTrimParens(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) FieldExprRange {
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

fn fieldStaticCallHead(tokens: []const lexer.Token, range: FieldExprRange) ?FieldStaticCallHead {
    if (range.start >= range.end) return null;
    var name_idx = range.start;
    var is_intrinsic = false;
    if (tokEq(tokens[name_idx], "@")) {
        is_intrinsic = true;
        name_idx += 1;
    }
    if (name_idx >= range.end or tokens[name_idx].kind != .ident) return null;
    if (name_idx + 1 >= range.end or !tokEq(tokens[name_idx + 1], "(")) return null;
    const close_paren = findMatchingInRange(tokens, name_idx + 1, "(", ")", range.end) catch return null;
    if (close_paren + 1 != range.end) return null;
    return .{
        .name_idx = name_idx,
        .args_start = name_idx + 2,
        .args_end = close_paren,
        .is_intrinsic = is_intrinsic,
    };
}

fn findArgEndAny(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
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

fn singleArgRange(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?ArgRange {
    var count: usize = 0;
    var out: ?ArgRange = null;
    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !isTopLevelCommaAny(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            count += 1;
            out = .{ .start = seg_start, .end = i };
        }
        seg_start = i + 1;
    }
    if (count != 1) return null;
    return out;
}

fn nthArgRange(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, arg_index: usize) ?ArgRange {
    var current: usize = 0;
    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !isTopLevelCommaAny(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            if (current == arg_index) return .{ .start = seg_start, .end = i };
            current += 1;
        }
        seg_start = i + 1;
    }
    return null;
}

fn braceDepthBefore(tokens: []const lexer.Token, before_idx: usize) usize {
    var depth: usize = 0;
    var i: usize = 0;
    while (i < before_idx) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            depth += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth > 0) depth -= 1;
        }
    }
    return depth;
}

fn isUnsupportedDirectLoopSource(type_name: []const u8) bool {
    return std.mem.eql(u8, type_name, "List") or std.mem.eql(u8, type_name, "HashMap");
}

fn checkConstraintLayout(tokens: []const lexer.Token) !void {
    var depth_brace: usize = 0;
    var in_constraint_block = false;
    var saw_type_constraint = false;
    var saw_func_type_constraint = false;
    var saw_func_constraint = false;
    var last_constraint_line: usize = 0;
    var constraint_block_start: ?usize = null;

    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (depth_brace == 0) {
                if (parseImportDeclEnd(tokens, i)) |next_idx| {
                    i = next_idx - 1;
                    continue;
                }
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
            if (in_constraint_block) {
                if (tokens[i].line != last_constraint_line + 1) {
                    return markErrorAt(tokens, i, error.InvalidConstraintDecl);
                }
                if ((saw_func_type_constraint or saw_func_constraint) and !isFuncDeclStart(tokens, i)) {
                    return markErrorAt(tokens, i, error.InvalidConstraintDecl);
                }
                if (!isFuncDeclStart(tokens, i) and !isStructDeclStart(tokens, i)) {
                    return markErrorAt(tokens, i, error.InvalidConstraintDecl);
                }
                if (isFuncDeclStart(tokens, i)) {
                    const close_paren = findMatching(tokens, i + 1, "(", ")") catch
                        return markErrorAt(tokens, i, error.InvalidConstraintDecl);
                    if (findInlineFuncTypeInParams(tokens, i + 2, close_paren)) |name_idx| {
                        return markErrorAt(tokens, name_idx, error.InvalidConstraintDecl);
                    }
                    if (findUnusedTypeConstraintInFuncParams(tokens, constraint_block_start.?, i, i + 2, close_paren)) |name_idx| {
                        return markErrorAt(tokens, name_idx, error.InvalidConstraintDecl);
                    }
                } else if (isStructDeclStart(tokens, i)) {
                    const close_brace = findMatching(tokens, i + 1, "{", "}") catch
                        return markErrorAt(tokens, i, error.InvalidConstraintDecl);
                    if (findUnusedTypeConstraintInStructFields(tokens, constraint_block_start.?, i, i + 2, close_brace)) |name_idx| {
                        return markErrorAt(tokens, name_idx, error.InvalidConstraintDecl);
                    }
                }
                in_constraint_block = false;
                saw_type_constraint = false;
                saw_func_type_constraint = false;
                saw_func_constraint = false;
                constraint_block_start = null;
            }
            continue;
        }

        const line = tokens[i].line;
        const line_end = findLineEndIdx(tokens, i);
        if (i + 1 >= line_end or tokens[i + 1].kind != .ident) {
            return markErrorAt(tokens, i, error.InvalidConstraintDecl);
        }

        var depth_paren: usize = 0;
        var depth_angle: usize = 0;
        var j = i + 1;
        while (j < line_end) : (j += 1) {
            if (tokEq(tokens[j], "(")) {
                depth_paren += 1;
                continue;
            }
            if (tokEq(tokens[j], ")")) {
                if (depth_paren > 0) depth_paren -= 1;
                continue;
            }
            if (tokEq(tokens[j], "<")) {
                depth_angle += 1;
                continue;
            }
            if (tokEq(tokens[j], ">")) {
                if (depth_angle > 0) depth_angle -= 1;
                continue;
            }
            if (depth_paren != 0 or depth_angle != 0) continue;
            if (tokEq(tokens[j], "#")) return markErrorAt(tokens, j, error.InvalidConstraintDecl);
            if (tokens[j].kind == .ident and j > i + 1 and j + 1 < line_end and tokEq(tokens[j + 1], "(")) {
                return markErrorAt(tokens, j, error.InvalidConstraintDecl);
            }
        }

        const eq_idx = findTopLevelAssignEqOnLine(tokens, i + 2, line_end);
        const is_func_type_constraint = eq_idx != null;
        const is_func_constraint = (!is_func_type_constraint and i + 2 < line_end and tokEq(tokens[i + 2], "("));
        const is_type_constraint = !is_func_type_constraint and !is_func_constraint;

        if (!is_func_constraint and !isValidDeclaredTypeName(tokens[i + 1].lexeme)) {
            return markErrorAt(tokens, i + 1, error.InvalidConstraintDecl);
        }
        if (is_type_constraint and line_end != i + 2) {
            return markErrorAt(tokens, i, error.InvalidConstraintDecl);
        }
        if (is_func_type_constraint) {
            const assign_idx = eq_idx.?;
            if (assign_idx != i + 2) return markErrorAt(tokens, i, error.InvalidConstraintDecl);
            if (!isFuncTypeRange(tokens, assign_idx + 1, line_end)) {
                return markErrorAt(tokens, assign_idx + 1, error.InvalidConstraintDecl);
            }
        }
        if (is_func_constraint and !isAllowedConstraintFuncName(tokens[i + 1].lexeme)) {
            return markErrorAt(tokens, i + 1, error.InvalidConstraintDecl);
        }
        if (is_type_constraint and (saw_func_type_constraint or saw_func_constraint)) {
            return markErrorAt(tokens, i, error.InvalidConstraintDecl);
        }
        if (is_func_type_constraint and saw_func_constraint) {
            return markErrorAt(tokens, i, error.InvalidConstraintDecl);
        }
        if (is_func_constraint and !saw_type_constraint) {
            return markErrorAt(tokens, i, error.InvalidConstraintDecl);
        }
        const block_start = constraint_block_start orelse i;
        if (constraint_block_start == null) constraint_block_start = i;
        if (!is_func_constraint and hasConcreteTypeName(tokens, publicTypeName(tokens[i + 1].lexeme))) {
            return markErrorAt(tokens, i + 1, error.InvalidConstraintDecl);
        }
        if (!is_func_constraint and hasDuplicateTypeConstraintName(tokens, block_start, i, tokens[i + 1].lexeme)) {
            return markErrorAt(tokens, i + 1, error.InvalidConstraintDecl);
        }
        if (is_func_type_constraint) {
            if (findImplicitTypeParamInTypeConstraint(tokens, block_start, i, line_end)) |name_idx| {
                return markErrorAt(tokens, name_idx, error.InvalidConstraintDecl);
            }
        }
        if (is_type_constraint) {
            if (findImplicitTypeParamInTypeConstraint(tokens, block_start, i, line_end)) |name_idx| {
                return markErrorAt(tokens, name_idx, error.InvalidConstraintDecl);
            }
        }
        if (is_func_constraint and hasDuplicateFuncConstraintSignature(tokens, block_start, i, line_end)) {
            return markErrorAt(tokens, i + 1, error.InvalidConstraintDecl);
        }
        if (is_func_constraint) {
            if (findImplicitTypeParamInFuncConstraint(tokens, block_start, i, line_end)) |name_idx| {
                return markErrorAt(tokens, name_idx, error.InvalidConstraintDecl);
            }
        }
        if (is_type_constraint) saw_type_constraint = true;
        if (is_func_type_constraint) saw_func_type_constraint = true;
        if (is_func_constraint) saw_func_constraint = true;

        in_constraint_block = true;
        last_constraint_line = line;
        i = line_end - 1;
    }
}

fn hasDuplicateTypeConstraintName(
    tokens: []const lexer.Token,
    block_start: usize,
    before_idx: usize,
    name: []const u8,
) bool {
    var i = block_start;
    while (i < before_idx) {
        if (!tokEq(tokens[i], "#")) {
            i += 1;
            continue;
        }
        const line_end = findLineEndIdx(tokens, i);
        const is_func_constraint = (i + 2 < line_end and tokEq(tokens[i + 2], "("));
        if (!is_func_constraint and i + 1 < line_end and std.mem.eql(u8, tokens[i + 1].lexeme, name)) {
            return true;
        }
        i = line_end;
    }
    return false;
}

fn hasDuplicateFuncConstraintSignature(
    tokens: []const lexer.Token,
    block_start: usize,
    current_idx: usize,
    current_line_end: usize,
) bool {
    var i = block_start;
    while (i < current_idx) {
        if (!tokEq(tokens[i], "#")) {
            i += 1;
            continue;
        }
        const line_end = findLineEndIdx(tokens, i);
        const is_func_constraint = (i + 2 < line_end and tokEq(tokens[i + 2], "("));
        if (is_func_constraint and
            std.mem.eql(u8, tokens[i + 1].lexeme, tokens[current_idx + 1].lexeme) and
            funcConstraintParamsEqual(tokens, i, line_end, current_idx, current_line_end))
        {
            return true;
        }
        i = line_end;
    }
    return false;
}

fn funcConstraintParamsEqual(
    tokens: []const lexer.Token,
    a_idx: usize,
    a_line_end: usize,
    b_idx: usize,
    b_line_end: usize,
) bool {
    const a_open = a_idx + 2;
    const b_open = b_idx + 2;
    if (a_open >= a_line_end or b_open >= b_line_end) return false;
    const a_close = findMatching(tokens, a_open, "(", ")") catch return false;
    const b_close = findMatching(tokens, b_open, "(", ")") catch return false;
    if (a_close > a_line_end or b_close > b_line_end) return false;
    return tokenRangesEqual(tokens, a_open + 1, a_close, b_open + 1, b_close);
}

fn findImplicitTypeParamInTypeConstraint(
    tokens: []const lexer.Token,
    block_start: usize,
    constraint_idx: usize,
    line_end: usize,
) ?usize {
    const eq_idx = findTopLevelAssignEqOnLine(tokens, constraint_idx + 2, line_end) orelse return null;
    var i = eq_idx + 1;
    while (i < line_end) : (i += 1) {
        if (!isValidDeclaredTypeName(tokens[i].lexeme)) continue;
        const name = publicTypeName(tokens[i].lexeme);
        if (hasTypeConstraintName(tokens, block_start, constraint_idx, name)) continue;
        if (hasConcreteTypeName(tokens, name)) continue;
        return i;
    }
    return null;
}

fn findImplicitTypeParamInFuncConstraint(
    tokens: []const lexer.Token,
    block_start: usize,
    constraint_idx: usize,
    line_end: usize,
) ?usize {
    var i = constraint_idx + 2;
    while (i < line_end) : (i += 1) {
        if (!isValidDeclaredTypeName(tokens[i].lexeme)) continue;
        const name = publicTypeName(tokens[i].lexeme);
        if (hasTypeConstraintName(tokens, block_start, constraint_idx, name)) continue;
        if (hasConcreteTypeName(tokens, name)) continue;
        return i;
    }
    return null;
}

fn hasTypeConstraintName(
    tokens: []const lexer.Token,
    block_start: usize,
    before_idx: usize,
    name: []const u8,
) bool {
    var i = block_start;
    while (i < before_idx) {
        if (!tokEq(tokens[i], "#")) {
            i += 1;
            continue;
        }
        const line_end = findLineEndIdx(tokens, i);
        const is_func_constraint = (i + 2 < line_end and tokEq(tokens[i + 2], "("));
        if (!is_func_constraint and i + 1 < line_end and std.mem.eql(u8, tokens[i + 1].lexeme, name)) {
            return true;
        }
        i = line_end;
    }
    return false;
}

fn hasConcreteTypeName(tokens: []const lexer.Token, name: []const u8) bool {
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (depth_brace == 0) {
                if (parseImportDeclEnd(tokens, i)) |next_idx| {
                    i = next_idx - 1;
                    continue;
                }
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

fn tokenRangesEqual(
    tokens: []const lexer.Token,
    a_start: usize,
    a_end: usize,
    b_start: usize,
    b_end: usize,
) bool {
    if (a_end - a_start != b_end - b_start) return false;
    var offset: usize = 0;
    while (offset < a_end - a_start) : (offset += 1) {
        if (!std.mem.eql(u8, tokens[a_start + offset].lexeme, tokens[b_start + offset].lexeme)) return false;
    }
    return true;
}

fn findUnusedTypeConstraintInFuncParams(
    tokens: []const lexer.Token,
    block_start: usize,
    before_idx: usize,
    param_start: usize,
    param_end: usize,
) ?usize {
    var i = block_start;
    while (i < before_idx) {
        if (!tokEq(tokens[i], "#")) {
            i += 1;
            continue;
        }
        const line_end = findLineEndIdx(tokens, i);
        const is_func_constraint = (i + 2 < line_end and tokEq(tokens[i + 2], "("));
        if (!is_func_constraint and i + 1 < line_end) {
            const name = tokens[i + 1].lexeme;
            if (!tokenNameAppearsInRange(tokens, param_start, param_end, name) and
                !typeConstraintFeedsFuncParam(tokens, block_start, before_idx, param_start, param_end, name) and
                !funcReturnTypeContainsName(tokens, before_idx, param_end, name))
            {
                return i + 1;
            }
        }
        i = line_end;
    }
    return null;
}

fn findInlineFuncTypeInParams(
    tokens: []const lexer.Token,
    param_start: usize,
    param_end: usize,
) ?usize {
    var seg_start = param_start;
    var i = param_start;
    while (i <= param_end) : (i += 1) {
        if (i < param_end and !isTopLevelCommaAny(tokens, i, param_start, param_end)) continue;
        if (seg_start + 1 < i) {
            const type_start = seg_start + 1;
            if (isFuncTypeRange(tokens, type_start, i)) return type_start;
            if (type_start + 1 < i and isSpreadToken(tokens[type_start]) and isFuncTypeRange(tokens, type_start + 1, i)) {
                return type_start + 1;
            }
        }
        seg_start = i + 1;
    }
    return null;
}

fn typeConstraintFeedsFuncParam(
    tokens: []const lexer.Token,
    block_start: usize,
    before_idx: usize,
    param_start: usize,
    param_end: usize,
    name: []const u8,
) bool {
    var i = block_start;
    while (i < before_idx) {
        if (!tokEq(tokens[i], "#")) {
            i += 1;
            continue;
        }
        const line_end = findLineEndIdx(tokens, i);
        const is_func_constraint = (i + 2 < line_end and tokEq(tokens[i + 2], "("));
        if (is_func_constraint or i + 1 >= line_end) {
            i = line_end;
            continue;
        }

        const carrier = tokens[i + 1].lexeme;
        if (tokenNameAppearsInRange(tokens, param_start, param_end, carrier) and
            tokenNameAppearsInRange(tokens, i + 2, line_end, name))
        {
            return true;
        }
        i = line_end;
    }
    return false;
}

fn funcReturnTypeContainsName(
    tokens: []const lexer.Token,
    func_start_idx: usize,
    close_params_idx: usize,
    name: []const u8,
) bool {
    _ = func_start_idx;
    var return_start = close_params_idx + 1;
    if (return_start >= tokens.len) return false;
    if (isReturnArrowAt(tokens, return_start)) return_start += 2;
    if (return_start >= tokens.len) return false;
    if (tokEq(tokens[return_start], "{") or isArrowAt(tokens, return_start)) return false;

    const return_end = findReturnTypeEnd(tokens, return_start);
    return tokenNameAppearsInRange(tokens, return_start, return_end, name);
}

fn findUnusedTypeConstraintInStructFields(
    tokens: []const lexer.Token,
    block_start: usize,
    before_idx: usize,
    field_start: usize,
    field_end: usize,
) ?usize {
    var i = block_start;
    while (i < before_idx) {
        if (!tokEq(tokens[i], "#")) {
            i += 1;
            continue;
        }
        const line_end = findLineEndIdx(tokens, i);
        const is_func_constraint = (i + 2 < line_end and tokEq(tokens[i + 2], "("));
        if (!is_func_constraint and i + 1 < line_end) {
            const name = tokens[i + 1].lexeme;
            if (!structFieldTypeContainsName(tokens, field_start, field_end, name)) return i + 1;
        }
        i = line_end;
    }
    return null;
}

fn structFieldTypeContainsName(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    name: []const u8,
) bool {
    var i = start_idx;
    while (i < end_idx) {
        const line_end = findLineEndIdx(tokens, i);
        if (tokens[i].kind != .ident or !isStructFieldName(tokens[i].lexeme) or i + 1 >= line_end) {
            i = line_end;
            continue;
        }

        const type_end = findStructFieldTypeEnd(tokens, i + 1, line_end);
        if (tokenNameAppearsInRange(tokens, i + 1, type_end, name)) return true;
        i = line_end;
    }
    return false;
}

fn findStructFieldTypeEnd(tokens: []const lexer.Token, start_idx: usize, line_end: usize) usize {
    var i = start_idx;
    while (i < line_end) : (i += 1) {
        if (tokEq(tokens[i], "=")) return i;
    }
    return line_end;
}

fn tokenNameAppearsInRange(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    name: []const u8,
) bool {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokens[i].kind == .ident and std.mem.eql(u8, tokens[i].lexeme, name)) return true;
    }
    return false;
}

fn findLoopBlockOpen(tokens: []const lexer.Token, loop_idx: usize) ?usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = loop_idx + 1;
    while (i < tokens.len) : (i += 1) {
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
        if (tokEq(tokens[i], "{")) {
            if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0) return i;
            depth_brace += 1;
            continue;
        }
        if (!tokEq(tokens[i], "}")) continue;
        if (depth_brace > 0) depth_brace -= 1;
    }
    return null;
}

fn findLoopBindAssign(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var found: ?usize = null;
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
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
        if (tokEq(tokens[i], "{")) {
            if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0) break;
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }

        if (depth_paren != 0 or depth_brace != 0 or depth_angle != 0) continue;
        if (tokEq(tokens[i], ":") and tokEq(tokens[i + 1], "=")) return null;
        if (!tokEq(tokens[i], "=")) continue;
        if (found != null) return null;
        found = i;
    }
    return found;
}

fn validateLoopBindLhs(tokens: []const lexer.Token, start_idx: usize, bind_idx: usize) !void {
    if (start_idx >= bind_idx) return markErrorAt(tokens, bind_idx, error.InvalidLoopHeader);
    if (tokens[start_idx].kind != .ident) return markErrorAt(tokens, start_idx, error.InvalidLoopHeader);
    if (isKeyword(tokens[start_idx].lexeme)) return markErrorAt(tokens, start_idx, error.InvalidLoopHeader);
    if (!isValidLoopBindingName(tokens[start_idx].lexeme)) return markErrorAt(tokens, start_idx, error.InvalidLoopHeader);

    if (start_idx + 1 == bind_idx) return;
    if (start_idx + 3 != bind_idx) return markErrorAt(tokens, start_idx + 1, error.InvalidLoopHeader);
    if (!tokEq(tokens[start_idx + 1], ",")) return markErrorAt(tokens, start_idx + 1, error.InvalidLoopHeader);
    if (tokens[start_idx + 2].kind != .ident) return markErrorAt(tokens, start_idx + 2, error.InvalidLoopHeader);
    if (isKeyword(tokens[start_idx + 2].lexeme)) return markErrorAt(tokens, start_idx + 2, error.InvalidLoopHeader);
    if (!isValidLoopBindingName(tokens[start_idx + 2].lexeme)) return markErrorAt(tokens, start_idx + 2, error.InvalidLoopHeader);
}

fn checkAssignmentConstraints(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
    var scopes: std.ArrayListUnmanaged(Scope) = .empty;
    defer {
        for (scopes.items) |*scope| scope.deinit(allocator);
        scopes.deinit(allocator);
    }

    try scopes.append(allocator, .{});

    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            var scope: Scope = .{};
            errdefer scope.deinit(allocator);
            if (loopHeaderForBodyOpen(tokens, i)) |loop_idx| {
                try appendLoopBodyBindings(allocator, &scope, tokens, loop_idx, i, scopes.items);
            }
            try scopes.append(allocator, scope);
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (scopes.items.len <= 1) return markErrorAt(tokens, i, error.UnbalancedScope);
            var popped = scopes.pop().?;
            popped.deinit(allocator);
            continue;
        }
        if (!tokEq(tokens[i], "=")) continue;
        if (isNonAssignEqual(tokens, i)) continue;

        var line_start = i;
        while (line_start > 0 and tokens[line_start - 1].line == tokens[i].line) {
            line_start -= 1;
        }
        const line_end = findLineEndIdx(tokens, i);
        const stmt_eq_idx = findTopLevelAssignEqOnLine(tokens, line_start, line_end) orelse continue;
        if (stmt_eq_idx != i) continue;
        const is_top_level = scopes.items.len == 1;

        if (tokEq(tokens[line_start], "#")) {
            continue;
        }
        if (is_top_level and isModernImportAssign(tokens, line_start)) {
            continue;
        }

        if (line_start < i and tokens[line_start].kind == .ident and tokens[line_start].lexeme.len > 0 and tokens[line_start].lexeme[0] == '.') {
            if (is_top_level and isTopLevelDeclHead(tokens, line_start) and isTypeDeclStart(tokens, line_start)) {
                continue;
            }
            if (!isStructFieldDeclDefault(tokens, line_start, i)) {
                return markErrorAt(tokens, line_start, error.PrivateIdentCannotBeLValue);
            }
        }
        if (is_top_level and line_start + 1 <= i and isTopLevelDeclHead(tokens, line_start) and isTypeDeclStart(tokens, line_start)) {
            continue;
        }
        if (isStructFieldDeclDefault(tokens, line_start, i)) {
            continue;
        }
        if (tokEq(tokens[line_start], "loop")) {
            continue;
        }

        try validateAssignmentLhsNames(tokens, line_start, stmt_eq_idx);
        if (findTopLevelComma(tokens, line_start, stmt_eq_idx) == null) {
            const lhs_name = tokens[line_start].lexeme;
            if (lhs_name.len != 0 and lhs_name[0] != '.' and lhs_name[0] != '_') {
                if (isSingleLocalValueDecl(tokens, line_start, stmt_eq_idx)) {
                    if (scopesContain(scopes.items, lhs_name)) return markErrorAt(tokens, line_start, error.DuplicateLocalBinding);
                    var current = &scopes.items[scopes.items.len - 1];
                    try current.names.append(allocator, lhs_name);
                } else if (!scopesContain(scopes.items, lhs_name)) {
                    var current = &scopes.items[scopes.items.len - 1];
                    try current.names.append(allocator, lhs_name);
                }
            }
        }

        var k = line_start;
        while (k < i) : (k += 1) {
            const t = tokens[k];
            if (t.kind != .ident) continue;
            if (t.lexeme.len == 0) continue;

            if (t.lexeme[0] == '.') return markErrorAt(tokens, k, error.PrivateIdentCannotBeLValue);
            if (scopesContainLoopBinding(scopes.items, t.lexeme)) return markErrorAt(tokens, k, error.InvalidAssignExpr);
            if (k == line_start and t.lexeme[0] != '_') continue;
            if (std.mem.eql(u8, t.lexeme, "_")) continue;

            if (t.lexeme[0] == '_') {
                if (scopesContain(scopes.items, t.lexeme)) return markErrorAt(tokens, k, error.DuplicateImmutableBinding);
                var current = &scopes.items[scopes.items.len - 1];
                try current.names.append(allocator, t.lexeme);
            }
        }
    }
}

fn isSingleLocalValueDecl(tokens: []const lexer.Token, start_idx: usize, eq_idx: usize) bool {
    if (tokens[start_idx].kind != .ident) return false;
    return eq_idx > start_idx + 1;
}

fn loopHeaderForBodyOpen(tokens: []const lexer.Token, open_idx: usize) ?usize {
    var i = open_idx;
    while (i > 0) {
        i -= 1;
        if (!tokEq(tokens[i], "loop")) continue;
        const body_open = findLoopBlockOpen(tokens, i) orelse continue;
        if (body_open == open_idx) return i;
    }
    return null;
}

fn appendLoopBodyBindings(
    allocator: std.mem.Allocator,
    scope: *Scope,
    tokens: []const lexer.Token,
    loop_idx: usize,
    open_idx: usize,
    outer_scopes: []const Scope,
) !void {
    const header_start = loop_idx + 1;
    if (header_start == open_idx) return;

    const bind_idx = findLoopBindAssign(tokens, header_start, open_idx) orelse
        return markErrorAt(tokens, loop_idx, error.InvalidLoopHeader);
    try appendLoopBindingName(allocator, scope, tokens, header_start, outer_scopes);

    if (header_start + 3 == bind_idx) {
        try appendLoopBindingName(allocator, scope, tokens, header_start + 2, outer_scopes);
    }
}

fn appendLoopBindingName(
    allocator: std.mem.Allocator,
    scope: *Scope,
    tokens: []const lexer.Token,
    idx: usize,
    outer_scopes: []const Scope,
) !void {
    const name = tokens[idx].lexeme;
    if (std.mem.eql(u8, name, "_")) return;
    if (scope.containsLoopBinding(name) or scopesContain(outer_scopes, name) or scopesContainLoopBinding(outer_scopes, name)) {
        return markErrorAt(tokens, idx, error.InvalidLoopHeader);
    }
    if (isVisibleBindingOrCallableName(tokens, name, idx)) return markErrorAt(tokens, idx, error.InvalidLoopHeader);
    try scope.loop_bindings.append(allocator, name);
}

fn validateAssignmentLhsNames(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) !void {
    var expect_name = true;
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

        const at_top_level = depth_paren == 0 and depth_bracket == 0 and depth_angle == 0;
        if (!expect_name) {
            if (at_top_level and tokEq(tokens[i], ",")) expect_name = true;
            continue;
        }

        const t = tokens[i];
        if (t.kind != .ident) continue;
        if (t.lexeme.len == 0) continue;
        if (t.lexeme[0] == '.') return markErrorAt(tokens, i, error.PrivateIdentCannotBeLValue);
        if (std.mem.eql(u8, t.lexeme, "_")) {
            expect_name = false;
            continue;
        }
        if (!isValidLocalBindingName(t.lexeme)) return markErrorAt(tokens, i, error.InvalidBindingName);
        expect_name = false;
    }
}

fn isStructFieldDeclDefault(tokens: []const lexer.Token, line_start: usize, eq_idx: usize) bool {
    if (line_start >= eq_idx) return false;
    if (tokens[line_start].kind != .ident) return false;
    if (tokens[line_start].lexeme.len == 0) return false;
    if (!isStructFieldName(tokens[line_start].lexeme)) return false;
    if (line_start + 2 > eq_idx) return false;
    return isInsideStructDecl(tokens, line_start);
}

fn isStructFieldName(name: []const u8) bool {
    if (name.len == 0) return false;
    const body = if (name[0] == '.') name[1..] else name;
    return isSnakeLowerName(body) and !isReservedFieldNameBody(body);
}

fn isDotLowerIdent(name: []const u8) bool {
    return name.len > 1 and name[0] == '.' and isSnakeLowerName(name[1..]);
}

fn isInsideStructDecl(tokens: []const lexer.Token, idx: usize) bool {
    var depth: usize = 0;
    var i = idx;
    while (i > 0) {
        i -= 1;
        if (tokEq(tokens[i], "}")) {
            depth += 1;
            continue;
        }
        if (!tokEq(tokens[i], "{")) continue;
        if (depth > 0) {
            depth -= 1;
            continue;
        }
        return isStructDeclBodyOpen(tokens, i);
    }
    return false;
}

fn isStructDeclBodyOpen(tokens: []const lexer.Token, open_idx: usize) bool {
    var i = open_idx;
    while (i > 0 and tokens[i - 1].line == tokens[open_idx].line) {
        i -= 1;
    }
    if (i >= open_idx) return false;
    if (tokens[i].kind != .ident) return false;
    if (isKeyword(tokens[i].lexeme)) return false;
    if (tokens[i].lexeme.len == 0 or !std.ascii.isUpper(tokens[i].lexeme[0])) return false;
    if (i + 1 < open_idx and tokens[i + 1].kind == .string) return false;
    if (i + 1 < open_idx and tokEq(tokens[i + 1], "(")) return false;
    return isTypeDeclStart(tokens, i);
}

fn isNonAssignEqual(tokens: []const lexer.Token, idx: usize) bool {
    if (idx > 0 and tokEq(tokens[idx - 1], "=")) return true; // ==
    if (idx + 1 < tokens.len and tokEq(tokens[idx + 1], "=")) return true; // ==
    if (idx + 1 < tokens.len and tokEq(tokens[idx + 1], ">")) return true; // =>
    return false;
}

fn tokEq(t: lexer.Token, s: []const u8) bool {
    return std.mem.eql(u8, t.lexeme, s);
}

fn isKeyword(name: []const u8) bool {
    const keywords = [_][]const u8{
        "if",
        "else",
        "loop",
        "break",
        "continue",
        "return",
        "defer",
        "do",
        "test",
        "true",
        "false",
        "nil",
    };
    for (keywords) |kw| {
        if (std.mem.eql(u8, name, kw)) return true;
    }
    return false;
}

fn isReservedFuncName(name: []const u8) bool {
    const public_name = if (name.len != 0 and name[0] == '.') name[1..] else name;
    if (std.mem.eql(u8, public_name, "start")) return true;
    if (isKeyword(public_name)) return true;
    if (isReservedSourceName(public_name)) return true;
    return isBuiltinSpecialOrCoreName(public_name);
}

fn isReservedSourceName(name: []const u8) bool {
    return isBaseTypeName(name) or isWitOnlySourceTypeName(name);
}

fn isDeclOnlyName(name: []const u8) bool {
    const public_name = if (name.len != 0 and name[0] == '.') name[1..] else name;
    return std.mem.eql(u8, public_name, "start") or std.mem.eql(u8, public_name, "test");
}

fn isAllowedConstraintFuncName(name: []const u8) bool {
    if (!isLowerIdentName(name)) return false;
    if (isDeclOnlyName(name)) return false;
    if (isBuiltinSpecialOrCoreName(name)) return false;
    if (isReservedSourceName(name)) return false;
    return !isKeyword(name);
}

fn isNumericCoreFuncName(name: []const u8) bool {
    const names = [_][]const u8{ "add", "sub", "mul", "div", "rem" };
    for (names) |it| {
        if (std.mem.eql(u8, it, name)) return true;
    }
    return false;
}

fn isBuiltinSpecialOrCoreName(name: []const u8) bool {
    const names = [_][]const u8{
        "is",          "as",                "and",         "or",          "not",
        "recv",        "fields",            "get",         "set",         "field_name",
        "field_index", "field_has_default", "field_get",   "field_set",   "eq",
        "ne",          "lt",                "le",          "gt",          "ge",
        "add",         "sub",               "mul",         "div",         "rem",
        "len",         "put",               "load_u8",     "load_i8",     "load_u16_le",
        "load_i16_le", "load_u32_le",       "load_i32_le", "load_u64_le", "load_i64_le",
        "xor",         "shl",               "shr",         "rotl",        "rotr",
        "clz",         "ctz",               "popcnt",      "abs",         "neg",
        "sqrt",        "ceil",              "floor",       "trunc",       "nearest",
        "min",         "max",               "copysign",
    };
    for (names) |it| {
        if (std.mem.eql(u8, it, name)) return true;
    }
    return false;
}

fn isValidFuncDeclName(name: []const u8) bool {
    if (name.len == 0) return false;
    if (isSnakeLowerName(name)) return true;
    if (name[0] == '.') return isSnakeLowerName(name[1..]);
    return false;
}

fn isTypeName(name: []const u8) bool {
    if (name.len == 0) return false;
    return std.ascii.isUpper(name[0]);
}

fn markErrorAt(tokens: []const lexer.Token, idx: usize, err: anyerror) anyerror {
    if (tokens.len != 0) {
        const safe_idx = if (idx < tokens.len) idx else tokens.len - 1;
        last_error_site = .{
            .line = tokens[safe_idx].line,
            .col = tokens[safe_idx].col,
        };
    }
    return err;
}

test "private host import is not a private lvalue assignment" {
    const source =
        \\.host_log = @env("console_log", (i32, i32) -> nil)
        \\
        \\test "ok" {
        \\    return
        \\}
        \\
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parseProgram(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    try checkProgram(std.testing.allocator, program, tokens);
}

test "private assignment is rejected" {
    const source =
        \\.value = 1
        \\
        \\test "bad" {
        \\    return
        \\}
        \\
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parseProgram(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    try std.testing.expectError(error.PrivateIdentCannotBeLValue, checkProgram(std.testing.allocator, program, tokens));
}
