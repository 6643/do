//! Semantic analysis — struct checks.
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema_error = @import("sema_error.zig");
const type_util = @import("type_name.zig");
const sema_util = @import("sema_util.zig");
const sema_types = @import("sema_types.zig");

const callArgInfo = sema_util.callArgInfo;
const collectStructInfos = sema_util.collectStructInfos;
const countTypeArgs = sema_util.countTypeArgs;
const findLineEndIdx = sema_util.findLineEndIdx;
const findMatching = sema_util.findMatching;
const findNearestValueTypeName = sema_util.findNearestValueTypeName;
const findStructInfo = sema_util.findStructInfo;
const findTopLevelAssignEqOnLine = sema_util.findTopLevelAssignEqOnLine;
const findTopLevelComma = sema_util.findTopLevelComma;
const firstNonGap = sema_util.firstNonGap;
const freeStructInfos = sema_util.freeStructInfos;
const hasLocalStructDecl = sema_util.hasLocalStructDecl;
const hasReturnArrowBeforeOnLine = sema_util.hasReturnArrowBeforeOnLine;
const isDotLowerIdent = sema_util.isDotLowerIdent;
const isFuncDeclStart = sema_util.isFuncDeclStart;
const isInsideStructDecl = sema_util.isInsideStructDecl;
const isModernImportAssign = sema_util.isModernImportAssign;
const isNonAssignEqual = sema_util.isNonAssignEqual;
const isReservedFieldNameBody = sema_util.isReservedFieldNameBody;
const isReturnArrowAt = sema_util.isReturnArrowAt;
const isSnakeLowerName = sema_util.isSnakeLowerName;
const isSpreadToken = sema_util.isSpreadToken;
const isStartDeclStart = sema_util.isStartDeclStart;
const isStructDeclBodyOpen = sema_util.isStructDeclBodyOpen;
const isStructDeclStart = sema_util.isStructDeclStart;
const isStructFieldName = sema_util.isStructFieldName;
const isTopLevelCommaAny = sema_util.isTopLevelCommaAny;
const isTopLevelDeclHead = sema_util.isTopLevelDeclHead;
const isTopLevelToken = sema_util.isTopLevelToken;
const isTypeDeclStart = sema_util.isTypeDeclStart;
const isValidDeclaredTypeName = sema_util.isValidDeclaredTypeName;
const lineStartIdx = sema_util.lineStartIdx;
const localStructTypeParamCount = sema_util.localStructTypeParamCount;
const markErrorAt = sema_util.markErrorAt;
const normalizeStructFieldName = sema_util.normalizeStructFieldName;
const parseImportDeclEnd = sema_util.parseImportDeclEnd;
const skipTopLevelImportBrace = sema_util.skipTopLevelImportBrace;
const publicTypeName = sema_util.publicTypeName;
const tokEq = sema_util.tokEq;
const StructFieldInfo = sema_types.StructFieldInfo;
const StructInfo = sema_types.StructInfo;

pub fn checkPathAccess(tokens: []const lexer.Token) !void {
    for (tokens, 0..) |t, i| {
        if (t.kind != .ident) continue;
        if (t.lexeme.len == 0) continue;
        if (t.lexeme[0] == '.') continue;
        if (isImportPathToken(tokens, i)) continue;
        if (std.mem.indexOfScalar(u8, t.lexeme, '.') == null) continue;
        return markErrorAt(tokens, i, error.InvalidPathAccess);
    }
}


pub fn checkFieldSegmentPositions(tokens: []const lexer.Token) !void {
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


fn isImportPathToken(tokens: []const lexer.Token, idx: usize) bool {
    var i = idx;
    while (i > 0 and tokens[i - 1].line == tokens[idx].line) : (i -= 1) {}
    while (i < idx) : (i += 1) {
        if (tokEq(tokens[i], "@")) return true;
    }
    return false;
}


fn findTopLevelAssignEq(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    return findTopLevelAssignEqOnLine(tokens, start_idx, end_idx);
}


pub fn checkPathIndexSegments(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tokEq(tokens[i], "get") and !tokEq(tokens[i], "set")) continue;
        if (i + 1 >= tokens.len or !tokEq(tokens[i + 1], "(")) continue;
        const close_paren = findMatching(tokens, i + 1, "(", ")") catch continue;
        try checkPathArgIndexSegments(tokens, i + 2, close_paren);
        i = close_paren;
    }
}


pub fn checkDirectPathSource(tokens: []const lexer.Token) !void {
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


pub fn checkStructFieldNames(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
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
        if (i + 1 >= tokens.len or !tokEq(tokens[i + 1], "{")) continue;

        const open_idx = i + 1;
        const close_idx = findMatching(tokens, open_idx, "{", "}") catch continue;
        try checkOneStructFieldNames(allocator, tokens, open_idx + 1, close_idx);
        i = close_idx;
    }
}


pub fn checkStructCtorFields(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
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


fn isReservedFieldName(name: []const u8) bool {
    const public_name = normalizeStructFieldName(name);
    return isReservedFieldNameBody(public_name);
}


pub fn checkGenericStructCtorTypeArgs(tokens: []const lexer.Token) !void {
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


/// Position-ctor arity for `Tuple<T0,...>{v0,...}` must equal type-arg count.
/// Nested ctors are scanned by not skipping the body after the outer ctor.
/// Named field inits are usually rejected earlier as InvalidStructLiteral by the parser;
/// this path remains as a defensive fallback (InvalidTypedLiteral).
pub fn checkTupleCtorArity(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, publicTypeName(tokens[i].lexeme), "Tuple")) continue;
        if (!tokEq(tokens[i + 1], "<")) continue;

        const close_angle = findMatching(tokens, i + 1, "<", ">") catch continue;
        if (close_angle + 1 >= tokens.len or !tokEq(tokens[close_angle + 1], "{")) {
            i = close_angle;
            continue;
        }
        // `f() -> Tuple<...>{ ... }` is a function body brace, not a position ctor.
        // Lexer emits `->` as two symbol tokens (`-`, `>`).
        if (i >= 2 and tokEq(tokens[i - 2], "-") and tokEq(tokens[i - 1], ">")) {
            i = close_angle;
            continue;
        }
        if (isTopLevelDeclHead(tokens, i) and isTypeDeclStart(tokens, i)) {
            i = close_angle;
            continue;
        }

        const open_brace = close_angle + 1;
        const close_brace = findMatching(tokens, open_brace, "{", "}") catch
            return markErrorAt(tokens, open_brace, error.InvalidTypedLiteral);
        const expected = countTypeArgs(tokens, i + 2, close_angle);
        if (expected < 2) {
            // arity floor already reported by checkGenericTypeArgArity when reachable.
            // Still walk the body so nested Tuple ctors are checked.
            i = open_brace;
            continue;
        }
        if (tupleCtorBodyHasNamedField(tokens, open_brace + 1, close_brace)) {
            return markErrorAt(tokens, open_brace, error.InvalidTypedLiteral);
        }
        const actual = countTupleCtorPositionalArgs(tokens, open_brace + 1, close_brace);
        if (actual != expected) return markErrorAt(tokens, i, error.InvalidTypedLiteral);
        try checkTupleCtorElemLiteralTypes(tokens, i + 2, close_angle, open_brace + 1, close_brace);
        // Do not jump to close_brace: nested `Tuple<...>{...}` lives inside the body.
        i = open_brace;
    }
}


fn tupleCtorBodyHasNamedField(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
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
        return true;
    }
    return false;
}


fn countTupleCtorPositionalArgs(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    if (start_idx >= end_idx) return 0;

    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var count: usize = 1;
    var saw_token = false;

    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEq(tokens[i], "(")) {
            depth_paren += 1;
            saw_token = true;
            continue;
        }
        if (tokEq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            saw_token = true;
            continue;
        }
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            saw_token = true;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            saw_token = true;
            continue;
        }
        if (tokEq(tokens[i], "<")) {
            depth_angle += 1;
            saw_token = true;
            continue;
        }
        if (tokEq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            saw_token = true;
            continue;
        }
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tokEq(tokens[i], ",")) {
            // Trailing comma is not an extra positional arg.
            if (!tupleCtorHasTopLevelTokenAfter(tokens, i + 1, end_idx)) continue;
            count += 1;
            continue;
        }
        saw_token = true;
    }
    if (!saw_token) return 0;
    return count;
}


fn tupleCtorHasTopLevelTokenAfter(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEq(tokens[i], "(")) {
            depth_paren += 1;
            return true;
        }
        if (tokEq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            return true;
        }
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            return true;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            return true;
        }
        if (tokEq(tokens[i], "<")) {
            depth_angle += 1;
            return true;
        }
        if (tokEq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            return true;
        }
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tokEq(tokens[i], ",")) {
            continue;
        }
        return true;
    }
    return false;
}

/// One positional segment of a typed tuple ctor: literal vs matching type arg.
fn checkTupleCtorSegmentLiteral(
    tokens: []const lexer.Token,
    type_args_start: usize,
    type_args_end: usize,
    seg_start: usize,
    seg_end: usize,
    arg_idx: usize,
) !void {
    if (seg_start >= seg_end) return;
    const type_range = nthTypeArgRange(tokens, type_args_start, type_args_end, arg_idx) orelse return;
    if (tuplePositionalArgCompatibleWithType(tokens, seg_start, seg_end, type_range.start, type_range.end)) return;
    return markErrorAt(tokens, seg_start, error.InvalidTypedLiteral);
}

/// Lightweight literal-vs-type-arg checks for position ctors.
/// Covers obvious mismatches (bool vs integer, etc.); complex exprs stay for later phases.
fn checkTupleCtorElemLiteralTypes(
    tokens: []const lexer.Token,
    type_args_start: usize,
    type_args_end: usize,
    body_start: usize,
    body_end: usize,
) !void {
    var arg_idx: usize = 0;
    var seg_start = body_start;
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = body_start;
    while (i <= body_end) : (i += 1) {
        const at_end = i == body_end;
        const at_top_comma = !at_end and depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tokEq(tokens[i], ",");
        if (!at_end and !at_top_comma) {
            // Flat depth bookkeeping stays inline (not a complete named boundary).
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
            continue;
        }

        try checkTupleCtorSegmentLiteral(tokens, type_args_start, type_args_end, seg_start, i, arg_idx);
        if (seg_start < i) arg_idx += 1;
        seg_start = i + 1;
    }
}


const TypeArgRange = struct { start: usize, end: usize };


fn nthTypeArgRange(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, want: usize) ?TypeArgRange {
    if (start_idx >= end_idx) return null;
    var depth_paren: usize = 0;
    var depth_bracket: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var idx: usize = 0;
    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        const at_end = i == end_idx;
        const at_top_comma = !at_end and depth_paren == 0 and depth_bracket == 0 and depth_brace == 0 and depth_angle == 0 and tokEq(tokens[i], ",");
        if (!at_end and !at_top_comma) {
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
                if (depth_angle > 0) depth_angle -= 1;
                continue;
            }
            continue;
        }
        if (idx == want and seg_start < i) return .{ .start = seg_start, .end = i };
        idx += 1;
        seg_start = i + 1;
    }
    return null;
}


fn tuplePositionalArgCompatibleWithType(
    tokens: []const lexer.Token,
    arg_start: usize,
    arg_end: usize,
    type_start: usize,
    type_end: usize,
) bool {
    if (arg_start >= arg_end or type_start >= type_end) return true;

    // Nested position ctor: `Tuple<...>{...}` against a Tuple type arg.
    if (tokens[arg_start].kind == .ident and
        std.mem.eql(u8, publicTypeName(tokens[arg_start].lexeme), "Tuple") and
        arg_start + 1 < arg_end and tokEq(tokens[arg_start + 1], "<"))
    {
        if (tokens[type_start].kind != .ident) return true;
        if (!std.mem.eql(u8, publicTypeName(tokens[type_start].lexeme), "Tuple")) return false;
        return true;
    }

    // Single-token literal against a simple type name.
    if (arg_end != arg_start + 1) return true;
    if (type_end != type_start + 1 or tokens[type_start].kind != .ident) return true;

    const ty = publicTypeName(tokens[type_start].lexeme);
    const lit = tokens[arg_start];

    if (std.mem.eql(u8, lit.lexeme, "true") or std.mem.eql(u8, lit.lexeme, "false")) {
        return std.mem.eql(u8, ty, "bool");
    }
    if (lit.kind == .number) {
        return isIntegerTypeName(ty) or isFloatTypeName(ty);
    }
    if (lit.kind == .string) {
        return std.mem.eql(u8, ty, "text");
    }
    return true;
}


fn isIntegerTypeName(ty: []const u8) bool {
    return type_util.isIntegerTypeName(ty);
}


fn isFloatTypeName(ty: []const u8) bool {
    return type_util.isFloatTypeName(ty);
}

/// `@get(tuple, N)` requires compile-time integer N in `0..arity-1` when the source is Tuple.

/// `@get(tuple, N)` requires compile-time integer N in `0..arity-1` when the source is Tuple.
pub fn checkTupleGetIndex(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tokEq(tokens[i], "get")) continue;
        if (i + 1 >= tokens.len or !tokEq(tokens[i + 1], "(")) continue;
        if (i == 0 or !tokEq(tokens[i - 1], "@") or tokens[i - 1].line != tokens[i].line) continue;

        const close_paren = findMatching(tokens, i + 1, "(", ")") catch continue;
        const first_end = findTopLevelComma(tokens, i + 2, close_paren) orelse {
            i = close_paren;
            continue;
        };
        if (first_end <= i + 2) {
            i = close_paren;
            continue;
        }
        // Only simple two-arg `@get(source, index)` form.
        if (findTopLevelComma(tokens, first_end + 1, close_paren) != null) {
            i = close_paren;
            continue;
        }

        const source_start = i + 2;
        const source_end = first_end;
        if (source_end != source_start + 1 or tokens[source_start].kind != .ident) {
            i = close_paren;
            continue;
        }

        const arity = findNearestTupleArity(tokens, i, tokens[source_start].lexeme) orelse {
            i = close_paren;
            continue;
        };

        const index_start = first_end + 1;
        const index_end = close_paren;
        if (index_end != index_start + 1 or tokens[index_start].kind != .number) {
            return markErrorAt(tokens, index_start, error.InvalidPathIndex);
        }
        const index = std.fmt.parseInt(usize, tokens[index_start].lexeme, 10) catch
            return markErrorAt(tokens, index_start, error.InvalidPathIndex);
        if (index >= arity) return markErrorAt(tokens, index_start, error.InvalidPathIndex);
        i = close_paren;
    }
}

/// Returns arity when the nearest binding type of `name` before `before_idx` is `Tuple<...>`.

/// Returns arity when the nearest binding type of `name` before `before_idx` is `Tuple<...>`.
fn findNearestTupleArity(tokens: []const lexer.Token, before_idx: usize, name: []const u8) ?usize {
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
        if (eq_idx <= i + 1) continue;
        if (tokens[i + 1].kind != .ident) continue;
        if (!std.mem.eql(u8, publicTypeName(tokens[i + 1].lexeme), "Tuple")) continue;
        if (i + 2 >= eq_idx or !tokEq(tokens[i + 2], "<")) continue;
        const close_angle = findMatching(tokens, i + 2, "<", ">") catch continue;
        if (close_angle > eq_idx) continue;
        return countTypeArgs(tokens, i + 3, close_angle);
    }

    // Function param: `name Tuple<...>`
    return findEnclosingFuncParamTupleArity(tokens, before_idx, name);
}


fn findEnclosingFuncParamTupleArity(tokens: []const lexer.Token, before_idx: usize, name: []const u8) ?usize {
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
        if (findFuncParamTupleArityBeforeBody(tokens, i, name)) |arity| return arity;
    }
    return null;
}


fn findFuncParamTupleArityBeforeBody(tokens: []const lexer.Token, body_open_idx: usize, name: []const u8) ?usize {
    const line_start = lineStartIdx(tokens, body_open_idx);
    if (line_start >= body_open_idx) return null;
    if (!isFuncDeclStart(tokens, line_start) and !isStartDeclStart(tokens, line_start)) return null;

    const close_paren = findMatching(tokens, line_start + 1, "(", ")") catch return null;
    if (close_paren >= body_open_idx) return null;

    var seg_start = line_start + 2;
    var j = seg_start;
    while (j <= close_paren) : (j += 1) {
        if (j < close_paren and !isTopLevelCommaAny(tokens, j, line_start + 2, close_paren)) continue;
        if (seg_start + 1 < j and tokens[seg_start].kind == .ident and std.mem.eql(u8, tokens[seg_start].lexeme, name)) {
            if (tokens[seg_start + 1].kind == .ident and
                std.mem.eql(u8, publicTypeName(tokens[seg_start + 1].lexeme), "Tuple") and
                seg_start + 2 < j and tokEq(tokens[seg_start + 2], "<"))
            {
                const close_angle = findMatching(tokens, seg_start + 2, "<", ">") catch return null;
                if (close_angle < j) return countTypeArgs(tokens, seg_start + 3, close_angle);
            }
        }
        seg_start = j + 1;
    }
    return null;
}


fn isGenericStructTypeName(tokens: []const lexer.Token, name: []const u8) bool {
    return genericStructTypeParamCount(tokens, name) != null;
}


fn genericStructTypeParamCount(tokens: []const lexer.Token, name: []const u8) ?usize {
    const count = localStructTypeParamCount(tokens, name) orelse return null;
    return if (count == 0) null else count;
}


