//! Shared sema token/name/scan predicates (extracted from sema_util).
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema_error = @import("sema_error.zig");
const type_util = @import("type_name.zig");
const sema_types = @import("sema_types.zig");

const CallArgInfo = sema_types.CallArgInfo;
const FuncShape = sema_types.FuncShape;
const LocalImportPrefix = sema_types.LocalImportPrefix;
const StructInfo = sema_types.StructInfo;

pub fn isTopLevelDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    if (idx >= tokens.len or tokens[idx].kind != .ident) return false;
    if (isModernImportAssign(tokens, idx)) return true;
    if (isStartDeclStart(tokens, idx) or isFuncDeclStart(tokens, idx)) return true;
    if (isTypeDeclStart(tokens, idx)) return true;
    if (topLevelLineAssignIdx(tokens, idx) != null) return true;
    return tokEq(tokens[idx], "test");
}



pub fn findPlainEqOnLine(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (!tokEq(tokens[i], "=")) continue;
        if (isNonAssignEqual(tokens, i)) continue;
        return i;
    }
    return null;
}



pub fn callArgInfo(tokens: []const lexer.Token, idx: usize) ?CallArgInfo {
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



pub fn callNameIdxBeforeOpen(tokens: []const lexer.Token, open_idx: usize) ?usize {
    if (open_idx == 0) return null;
    const name_idx = open_idx - 1;
    if (tokens[name_idx].kind != .ident) return null;
    return name_idx;
}



pub fn findEnclosingCallOpen(tokens: []const lexer.Token, idx: usize) ?usize {
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



pub fn isTopLevelToken(tokens: []const lexer.Token, idx: usize) bool {
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



pub fn validateIsTypeExpr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var i = validateIsTypeAtom(tokens, start_idx, end_idx) orelse return null;
    while (i < end_idx) {
        if (!tokEq(tokens[i], "|")) return null;
        i = validateIsTypeAtom(tokens, i + 1, end_idx) orelse return null;
    }
    return i;
}



pub fn validateIsTypeAtom(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
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



pub fn validateIsTypeArgList(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
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



pub fn validateIsTypeExprUntilComma(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var i = validateIsTypeAtom(tokens, start_idx, end_idx) orelse return null;
    while (i < end_idx and !tokEq(tokens[i], ",")) {
        if (!tokEq(tokens[i], "|")) return null;
        i = validateIsTypeAtom(tokens, i + 1, end_idx) orelse return null;
    }
    return i;
}



pub fn findReturnTypeEnd(tokens: []const lexer.Token, start_idx: usize) usize {
    var i = start_idx;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) return i;
        if (isArrowAt(tokens, i)) return i;
        if (tokens[i].line != tokens[start_idx].line) return i;
    }
    return i;
}



pub fn hasKnownFuncCandidate(funcs: []const FuncShape, name: []const u8) bool {
    for (funcs) |func| {
        if (std.mem.eql(u8, func.name, name)) return true;
    }
    return false;
}



pub fn funcParamTypeStart(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (start_idx + 1 >= end_idx) return null;
    if (isSpreadToken(tokens[start_idx + 1])) {
        if (start_idx + 2 >= end_idx) return null;
        return start_idx + 2;
    }
    return start_idx + 1;
}



pub fn isFuncTypeParam(tokens: []const lexer.Token, func_start_idx: usize, name: []const u8) bool {
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



pub fn typeConstraintIsFunctionType(
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



pub fn findConstraintBlockStartBefore(tokens: []const lexer.Token, decl_start_idx: usize) ?usize {
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



pub fn lineStartIdx(tokens: []const lexer.Token, idx: usize) usize {
    var out = idx;
    while (out > 0 and tokens[out - 1].line == tokens[idx].line) : (out -= 1) {}
    return out;
}



pub fn compactTypeName(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize) !?[]const u8 {
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



pub fn simpleTypeName(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    if (start_idx + 1 != end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    return tokens[start_idx].lexeme;
}



pub fn isTopLevelCommaAny(tokens: []const lexer.Token, idx: usize, start_idx: usize, end_idx: usize) bool {
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



pub fn isFuncDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (tokens[idx].kind != .ident) return false;
    if (!isValidFuncDeclName(tokens[idx].lexeme)) return false;
    if (isReservedFuncName(tokens[idx].lexeme)) return false;
    return tokEq(tokens[idx + 1], "(");
}



pub fn isStartDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (tokens[idx].kind != .ident) return false;
    return tokEq(tokens[idx], "start") and tokEq(tokens[idx + 1], "(");
}



pub fn publicFuncName(name: []const u8) []const u8 {
    if (name.len != 0 and name[0] == '.') return name[1..];
    return name;
}



pub fn containsName(names: []const []const u8, needle: []const u8) bool {
    for (names) |name| {
        if (std.mem.eql(u8, name, needle)) return true;
    }
    return false;
}



pub fn isTopLevelValueDeclStart(tokens: []const lexer.Token, idx: usize) bool {
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



pub fn isArrowAt(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 1 < tokens.len and tokEq(tokens[idx], "=") and tokEq(tokens[idx + 1], ">");
}



pub fn isReturnArrowAt(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 1 < tokens.len and tokEq(tokens[idx], "-") and tokEq(tokens[idx + 1], ">");
}



pub fn findNearestValueTypeName(tokens: []const lexer.Token, before_idx: usize, name: []const u8) ?[]const u8 {
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



pub fn isGenericTypeStart(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 1 >= end_idx or !tokEq(tokens[start_idx + 1], "<")) return false;
    _ = findMatching(tokens, start_idx + 1, "<", ">") catch return false;
    return true;
}



pub fn isDeclaredTypeName(name: []const u8) bool {
    return name.len != 0 and std.ascii.isUpper(name[0]);
}



pub fn isValueTypeName(name: []const u8) bool {
    return isDeclaredTypeName(name) or isBaseTypeName(name);
}



pub fn publicTypeName(name: []const u8) []const u8 {
    if (name.len != 0 and name[0] == '.') return name[1..];
    return name;
}



pub fn findLineEndIdx(tokens: []const lexer.Token, start_idx: usize) usize {
    if (start_idx >= tokens.len) return start_idx;
    const line = tokens[start_idx].line;
    var i = start_idx;
    while (i < tokens.len and tokens[i].line == line) : (i += 1) {}
    return i;
}



pub fn findTopLevelAssignEqOnLine(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
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



pub fn hasLocalStructDecl(tokens: []const lexer.Token, name: []const u8) bool {
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



pub fn callArityCompatibleWithFunc(func: FuncShape, arg_count: usize) bool {
    if (arg_count < func.param_min) return false;
    if (func.param_max) |max_count| return arg_count <= max_count;
    return true;
}



pub fn findMatching(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8) !usize {
    return findMatchingInRange(tokens, open_idx, open, close, tokens.len);
}



pub fn findMatchingInRange(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8, limit: usize) !usize {
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



pub fn isStructDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 1 < tokens.len and tokEq(tokens[idx + 1], "{");
}



pub fn isErrorEnumDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 2 < tokens.len and
        isErrorTypeName(tokens[idx].lexeme) and
        tokEq(tokens[idx + 1], "error") and
        tokEq(tokens[idx + 2], "=");
}



pub fn isValueEnumDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 2 < tokens.len and
        isValidDeclaredTypeName(tokens[idx].lexeme) and
        !isErrorTypeName(tokens[idx].lexeme) and
        isBaseIntTypeName(tokens[idx + 1].lexeme) and
        tokEq(tokens[idx + 2], "=");
}

/// `Message = Quit | Text([u8]) | Binary([u8])` — tagged payload enum (L1).
/// Disambiguated from value/error enums and from `Name = @wasi_*` bindings.

/// `Message = Quit | Text([u8]) | Binary([u8])` — tagged payload enum (L1).
/// Disambiguated from value/error enums and from `Name = @wasi_*` bindings.

/// `Message = Quit | Text([u8]) | Binary([u8])` — tagged payload enum (L1).
/// Disambiguated from value/error enums and from `Name = @wasi_*` bindings.
pub fn isPayloadEnumDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 2 >= tokens.len) return false;
    if (tokens[idx].kind != .ident) return false;
    if (!isValidDeclaredTypeName(tokens[idx].lexeme)) return false;
    if (isErrorTypeName(tokens[idx].lexeme)) return false;
    if (isErrorEnumDeclStart(tokens, idx) or isValueEnumDeclStart(tokens, idx)) return false;
    if (!tokEq(tokens[idx + 1], "=")) return false;
    // WASI / lib binding: Name = @...
    if (tokEq(tokens[idx + 2], "@")) return false;

    const line_end = findLineEndIdx(tokens, idx);
    var j = idx + 2;
    var saw_case = false;
    var expect_case = true;
    while (j < line_end) {
        if (!expect_case) {
            if (!tokEq(tokens[j], "|")) return false;
            expect_case = true;
            j += 1;
            continue;
        }
        if (tokens[j].kind != .ident) return false;
        if (!isValidEnumBranchName(tokens[j])) return false;
        j += 1;
        if (j < line_end and tokEq(tokens[j], "(")) {
            const close = findMatching(tokens, j, "(", ")") catch return false;
            if (close <= j + 1) return false;
            // Value-enum style numeric carrier: Case(0) — not payload enum.
            if (close == j + 2 and tokens[j + 1].kind == .number) return false;
            // Payload type must be a type expr, not a bare value literal.
            if (tokens[j + 1].kind == .number or tokens[j + 1].kind == .string) return false;
            if (tokEq(tokens[j + 1], "true") or tokEq(tokens[j + 1], "false") or tokEq(tokens[j + 1], "nil")) return false;
            // Type atom from j+1 .. close must fully consume.
            if (validateIsTypeExpr(tokens, j + 1, close) != close) return false;
            j = close + 1;
        }
        saw_case = true;
        expect_case = false;
    }
    if (!saw_case or expect_case) return false;
    return true;
}



pub fn isValidEnumBranchName(tok: lexer.Token) bool {
    if (tok.kind != .ident) return false;
    const name = publicTypeName(tok.lexeme);
    if (!isValidDeclaredTypeName(name)) return false;
    if (std.mem.eql(u8, name, "Error")) return false;
    if (isErrorTypeName(name)) return false;
    return true;
}



pub fn isErrorTypeName(name: []const u8) bool {
    if (name.len == 0 or name[0] == '.') return false;
    if (!isValidDeclaredTypeName(name)) return false;
    if (std.mem.eql(u8, name, "Error")) return false;
    return std.mem.endsWith(u8, name, "Error");
}



pub fn enumDeclHasBranch(tokens: []const lexer.Token, line_start_idx: usize, name: []const u8) bool {
    const eq_idx = enumDeclAssignIdx(tokens, line_start_idx) orelse return false;
    const line_end = findLineEndIdx(tokens, line_start_idx);

    var i = eq_idx + 1;
    while (i < line_end) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (std.mem.eql(u8, publicTypeName(tokens[i].lexeme), name)) return true;
    }
    return false;
}



pub fn enumDeclAssignIdx(tokens: []const lexer.Token, line_start_idx: usize) ?usize {
    if (isErrorEnumDeclStart(tokens, line_start_idx) or isValueEnumDeclStart(tokens, line_start_idx)) {
        return line_start_idx + 2;
    }
    if (isPayloadEnumDeclStart(tokens, line_start_idx)) {
        return line_start_idx + 1; // Name = …
    }
    return null;
}



pub fn findStructInfo(structs: []const StructInfo, name: []const u8) ?StructInfo {
    for (structs) |info| {
        if (std.mem.eql(u8, info.name, name)) return info;
    }
    return null;
}



pub fn normalizeStructFieldName(name: []const u8) []const u8 {
    if (name.len > 0 and name[0] == '.') return name[1..];
    return name;
}



pub fn isReservedFieldNameBody(name: []const u8) bool {
    return isKeyword(name) or isDeclOnlyName(name) or isReservedCoreAccessName(name) or isReservedSourceName(name);
}



pub fn isReservedCoreAccessName(name: []const u8) bool {
    return std.mem.eql(u8, name, "get") or std.mem.eql(u8, name, "set");
}



pub fn isTopLevelDeclHead(tokens: []const lexer.Token, idx: usize) bool {
    if (idx == 0) return true;
    if (tokens[idx - 1].line == tokens[idx].line) return false;

    const prev = tokens[idx - 1];
    if (tokEq(prev, "=")) return false;
    if (tokEq(prev, "|")) return false;
    if (tokEq(prev, ",")) return false;
    if (tokEq(prev, ":")) return false;
    return true;
}



pub fn isHostImportDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    const eq_idx = topLevelLineAssignIdx(tokens, idx) orelse return false;
    const at_idx = eq_idx + 1;
    if (at_idx >= tokens.len or !tokEq(tokens[at_idx], "@")) return false;
    return isHostImportLine(tokens, at_idx);
}



pub fn isModernImportAssign(tokens: []const lexer.Token, idx: usize) bool {
    const eq_idx = topLevelLineAssignIdx(tokens, idx) orelse return false;
    const at_idx = eq_idx + 1;
    if (at_idx + 1 >= tokens.len or !tokEq(tokens[at_idx], "@")) return false;
    if (tokens[at_idx + 1].kind != .ident) return false;
    return std.mem.eql(u8, tokens[at_idx + 1].lexeme, "lib") or
        std.mem.eql(u8, tokens[at_idx + 1].lexeme, "host");
}



pub fn topLevelLineAssignIdx(tokens: []const lexer.Token, line_start: usize) ?usize {
    const line_end = findLineEndIdx(tokens, line_start);
    return findTopLevelAssignEqOnLine(tokens, line_start + 1, line_end);
}



pub fn isHostImportLine(tokens: []const lexer.Token, at_idx: usize) bool {
    if (at_idx + 2 >= tokens.len) return false;
    if (!tokEq(tokens[at_idx], "@")) return false;
    if (tokens[at_idx + 1].kind != .ident) return false;
    if (!tokEq(tokens[at_idx + 2], "(")) return false;
    return std.mem.eql(u8, tokens[at_idx + 1].lexeme, "host");
}



pub fn validateImportFileNameText(tokens: []const lexer.Token, site_idx: usize, s: []const u8, prefix: LocalImportPrefix) !void {
    if (!std.mem.endsWith(u8, s, ".do")) return markErrorAt(tokens, site_idx, error.InvalidImportDecl);
    const stem = s[0 .. s.len - 3];
    const ok = switch (prefix) {
        .local, .std => isValidFlatFileStem(stem),
        .dep => isValidDepFileStem(stem),
    };
    if (!ok) return markErrorAt(tokens, site_idx, error.InvalidImportDecl);
}



pub fn validateImportFileName(tokens: []const lexer.Token, idx: usize, prefix: LocalImportPrefix) !void {
    try validateImportFileNameText(tokens, idx, tokens[idx].lexeme, prefix);
}



pub fn isValidFlatFileStem(stem: []const u8) bool {
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



pub fn isValidDepFileStem(stem: []const u8) bool {
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



pub fn isAllDigits(seg: []const u8) bool {
    if (seg.len == 0) return false;
    for (seg) |ch| {
        if (ch < '0' or ch > '9') return false;
    }
    return true;
}



pub fn isValidPathSeg(seg: []const u8) bool {
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



pub fn compactTokenRangeEquals(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, expected: []const u8) bool {
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



pub fn stringTokenBody(s: []const u8) ?[]const u8 {
    if (s.len < 2) return null;
    if (s[0] != '"' or s[s.len - 1] != '"') return null;
    return s[1 .. s.len - 1];
}



pub fn hasTopLevelComma(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
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



pub fn findTopLevelComma(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
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



pub fn firstNonGap(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        _ = tokens;
        return i;
    }
    return null;
}



pub fn isValueLiteralToken(t: lexer.Token) bool {
    if (t.kind == .number or t.kind == .string) return true;
    if (tokEq(t, "true") or tokEq(t, "false") or tokEq(t, "nil")) return true;
    return false;
}



pub fn isTypeDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (tokEq(tokens[idx + 1], "(")) return false; // func decl
    if (isErrorEnumDeclStart(tokens, idx) or isValueEnumDeclStart(tokens, idx) or isPayloadEnumDeclStart(tokens, idx)) return true;
    // Declarative WASI type binding: Name = @wasi_resource|wasi_record("…", { … })
    if (tokEq(tokens[idx + 1], "=") and idx + 5 < tokens.len and
        tokEq(tokens[idx + 2], "@") and tokens[idx + 3].kind == .ident and
        (std.mem.eql(u8, tokens[idx + 3].lexeme, "wasi_resource") or
            std.mem.eql(u8, tokens[idx + 3].lexeme, "wasi_record")) and
        tokEq(tokens[idx + 4], "("))
    {
        return isValidDeclaredTypeName(tokens[idx].lexeme);
    }

    var next_idx = idx + 1;
    if (tokEq(tokens[next_idx], "<")) {
        const close_angle = findMatching(tokens, next_idx, "<", ">") catch return false;
        next_idx = close_angle + 1;
        if (next_idx >= tokens.len) return false;
    }

    return tokEq(tokens[next_idx], "{");
}



pub fn isValidDeclaredTypeName(name: []const u8) bool {
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



pub fn isLowerIdentName(name: []const u8) bool {
    return isSnakeLowerName(name);
}



pub fn isReadonlyIdentName(name: []const u8) bool {
    if (name.len < 2) return false;
    if (name[0] != '_') return false;
    return isSnakeLowerName(name[1..]);
}



pub fn isSnakeLowerName(name: []const u8) bool {
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



pub fn isSpreadToken(tok: lexer.Token) bool {
    return tok.kind == .symbol and tokEq(tok, "...");
}



pub fn hasReturnArrowBeforeOnLine(tokens: []const lexer.Token, idx: usize) bool {
    var i = lineStartIdx(tokens, idx);
    while (i + 1 < idx) : (i += 1) {
        if (isReturnArrowAt(tokens, i)) return true;
    }
    return false;
}



pub fn countTypeArgs(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
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



pub fn isFuncTypeRange(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx >= end_idx or !tokEq(tokens[start_idx], "(")) return false;
    const close_idx = findMatching(tokens, start_idx, "(", ")") catch return false;
    return close_idx + 2 < end_idx and isReturnArrowAt(tokens, close_idx + 1);
}



pub fn isBaseTypeName(name: []const u8) bool {
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



pub fn isWitOnlySourceTypeName(name: []const u8) bool {
    return std.mem.eql(u8, name, "char") or std.mem.eql(u8, name, "tuple");
}



pub fn isBaseIntTypeName(name: []const u8) bool {
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



pub fn hasTypeConstraintName(
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



pub fn findInlineFuncTypeInParams(
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



pub fn findStructFieldTypeEnd(tokens: []const lexer.Token, start_idx: usize, line_end: usize) usize {
    var i = start_idx;
    while (i < line_end) : (i += 1) {
        if (tokEq(tokens[i], "=")) return i;
    }
    return line_end;
}



pub fn tokenNameAppearsInRange(
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



pub fn isStructFieldDeclDefault(tokens: []const lexer.Token, line_start: usize, eq_idx: usize) bool {
    if (line_start >= eq_idx) return false;
    if (tokens[line_start].kind != .ident) return false;
    if (tokens[line_start].lexeme.len == 0) return false;
    if (!isStructFieldName(tokens[line_start].lexeme)) return false;
    if (line_start + 2 > eq_idx) return false;
    return isInsideStructDecl(tokens, line_start);
}



pub fn isStructFieldName(name: []const u8) bool {
    if (name.len == 0) return false;
    const body = if (name[0] == '.') name[1..] else name;
    return isSnakeLowerName(body) and !isReservedFieldNameBody(body);
}



pub fn isDotLowerIdent(name: []const u8) bool {
    return name.len > 1 and name[0] == '.' and isSnakeLowerName(name[1..]);
}



pub fn isInsideStructDecl(tokens: []const lexer.Token, idx: usize) bool {
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



pub fn isStructDeclBodyOpen(tokens: []const lexer.Token, open_idx: usize) bool {
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



pub fn isNonAssignEqual(tokens: []const lexer.Token, idx: usize) bool {
    if (idx > 0 and tokEq(tokens[idx - 1], "=")) return true; // ==
    if (idx + 1 < tokens.len and tokEq(tokens[idx + 1], "=")) return true; // ==
    if (idx + 1 < tokens.len and tokEq(tokens[idx + 1], ">")) return true; // =>
    return false;
}



pub fn tokEq(t: lexer.Token, s: []const u8) bool {
    return std.mem.eql(u8, t.lexeme, s);
}



pub fn isKeyword(name: []const u8) bool {
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



pub fn isReservedFuncName(name: []const u8) bool {
    const public_name = if (name.len != 0 and name[0] == '.') name[1..] else name;
    if (std.mem.eql(u8, public_name, "start")) return true;
    if (isKeyword(public_name)) return true;
    if (isReservedSourceName(public_name)) return true;
    return isBuiltinSpecialOrCoreName(public_name);
}



pub fn isReservedSourceName(name: []const u8) bool {
    return isBaseTypeName(name) or isWitOnlySourceTypeName(name);
}



pub fn isDeclOnlyName(name: []const u8) bool {
    const public_name = if (name.len != 0 and name[0] == '.') name[1..] else name;
    return std.mem.eql(u8, public_name, "start") or std.mem.eql(u8, public_name, "test");
}



pub fn isNumericCoreFuncName(name: []const u8) bool {
    const names = [_][]const u8{ "add", "sub", "mul", "div", "rem" };
    for (names) |it| {
        if (std.mem.eql(u8, it, name)) return true;
    }
    return false;
}



pub fn isBuiltinSpecialOrCoreName(name: []const u8) bool {
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



pub fn isValidFuncDeclName(name: []const u8) bool {
    if (name.len == 0) return false;
    if (isSnakeLowerName(name)) return true;
    if (name[0] == '.') return isSnakeLowerName(name[1..]);
    return false;
}



pub fn isTypeName(name: []const u8) bool {
    if (name.len == 0) return false;
    return std.ascii.isUpper(name[0]);
}



pub fn markErrorAt(tokens: []const lexer.Token, idx: usize, err: anyerror) anyerror {
    return sema_error.markErrorAt(tokens, idx, err);
}



