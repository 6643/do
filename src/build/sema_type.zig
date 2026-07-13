//! Semantic analysis — type checks.
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema_error = @import("sema_error.zig");
const type_util = @import("type_name.zig");
const sema_util = @import("sema_util.zig");
const sema_types = @import("sema_types.zig");

const callArgInfo = sema_util.callArgInfo;
const countTypeArgs = sema_util.countTypeArgs;
const enumDeclAssignIdx = sema_util.enumDeclAssignIdx;
const enumDeclHasBranch = sema_util.enumDeclHasBranch;
const findConstraintBlockStartBefore = sema_util.findConstraintBlockStartBefore;
const findEnclosingCallOpen = sema_util.findEnclosingCallOpen;
const findLineEndIdx = sema_util.findLineEndIdx;
const findMatching = sema_util.findMatching;
const findStructFieldTypeEnd = sema_util.findStructFieldTypeEnd;
const findTopLevelAssignEqOnLine = sema_util.findTopLevelAssignEqOnLine;
const hasConcreteTypeName = sema_util.hasConcreteTypeName;
const hasReturnArrowBeforeOnLine = sema_util.hasReturnArrowBeforeOnLine;
const hasTypeConstraintName = sema_util.hasTypeConstraintName;
const isArrowAt = sema_util.isArrowAt;
const isBaseTypeName = sema_util.isBaseTypeName;
const isErrorEnumDeclStart = sema_util.isErrorEnumDeclStart;
const isErrorTypeName = sema_util.isErrorTypeName;
const isFuncDeclStart = sema_util.isFuncDeclStart;
const isFuncTypeRange = sema_util.isFuncTypeRange;
const isImportedUpperAlias = sema_util.isImportedUpperAlias;
const isKeyword = sema_util.isKeyword;
const isLocalPayloadEnumCase = sema_util.isLocalPayloadEnumCase;
const isLowerIdentName = sema_util.isLowerIdentName;
const isModernImportAssign = sema_util.isModernImportAssign;
const isNonAssignEqual = sema_util.isNonAssignEqual;
const isPayloadEnumDeclStart = sema_util.isPayloadEnumDeclStart;
const isReadonlyIdentName = sema_util.isReadonlyIdentName;
const isReservedFuncName = sema_util.isReservedFuncName;
const isReturnArrowAt = sema_util.isReturnArrowAt;
const isSpreadToken = sema_util.isSpreadToken;
const isStructDeclStart = sema_util.isStructDeclStart;
const isStructFieldName = sema_util.isStructFieldName;
const isTopLevelDeclHead = sema_util.isTopLevelDeclHead;
const isTypeDeclStart = sema_util.isTypeDeclStart;
const isValidDeclaredTypeName = sema_util.isValidDeclaredTypeName;
const isValidEnumBranchName = sema_util.isValidEnumBranchName;
const isValueEnumDeclStart = sema_util.isValueEnumDeclStart;
const isWitOnlySourceTypeName = sema_util.isWitOnlySourceTypeName;
const lineStartIdx = sema_util.lineStartIdx;
const localStructTypeParamCount = sema_util.localStructTypeParamCount;
const markErrorAt = sema_util.markErrorAt;
const parseImportDeclEnd = sema_util.parseImportDeclEnd;
const skipTopLevelImportBrace = sema_util.skipTopLevelImportBrace;
const publicTypeName = sema_util.publicTypeName;
const tokEq = sema_util.tokEq;
const validateIsTypeExpr = sema_util.validateIsTypeExpr;

pub fn checkTypeDeclNaming(tokens: []const lexer.Token) !void {
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
        if (!isTypeDeclStart(tokens, i)) continue;
        if ((isErrorTypeName(t.lexeme) or isPrivateErrorTypeName(t.lexeme)) and isStructDeclStart(tokens, i)) {
            return markErrorAt(tokens, i, error.InvalidTypeDeclName);
        }
        if (isValidDeclaredTypeName(t.lexeme)) continue;
        return markErrorAt(tokens, i, error.InvalidTypeDeclName);
    }
}


pub fn checkTypeDeclNameConflicts(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
    var seen = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer seen.deinit(allocator);

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


pub fn checkErrorDeclBranches(tokens: []const lexer.Token) !void {
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
        if (isPayloadEnumDeclStart(tokens, i)) {
            try validatePayloadEnumBranches(tokens, i, i + 2);
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


fn validatePayloadEnumBranches(tokens: []const lexer.Token, enum_idx: usize, start_idx: usize) !void {
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
        j += 1;
        if (j < line_end and tokEq(tokens[j], "(")) {
            const close = findMatching(tokens, j, "(", ")") catch
                return markErrorAt(tokens, j, error.InvalidErrorBranchName);
            if (close <= j + 1) return markErrorAt(tokens, j, error.InvalidErrorBranchName);
            // No value-enum style numeric carriers in payload enums.
            if (close == j + 2 and tokens[j + 1].kind == .number) {
                return markErrorAt(tokens, j + 1, error.InvalidErrorBranchName);
            }
            if (tokens[j + 1].kind == .number or tokens[j + 1].kind == .string) {
                return markErrorAt(tokens, j + 1, error.InvalidErrorBranchName);
            }
            if (validateIsTypeExpr(tokens, j + 1, close) != close) {
                return markErrorAt(tokens, j + 1, error.InvalidErrorBranchName);
            }
            j = close + 1;
        }
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

        if (!isErrorEnumDeclStart(tokens, i) and !isValueEnumDeclStart(tokens, i) and !isPayloadEnumDeclStart(tokens, i)) continue;
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


fn isValidErrorBranchName(tok: lexer.Token) bool {
    if (tok.kind != .ident) return false;
    if (!isValidDeclaredTypeName(tok.lexeme)) return false;
    if (std.mem.eql(u8, tok.lexeme, "Error")) return false;
    if (isErrorTypeName(tok.lexeme)) return false;
    return true;
}


fn isPrivateErrorTypeName(name: []const u8) bool {
    if (name.len < 2 or name[0] != '.') return false;
    return isErrorTypeName(name[1..]);
}


pub fn checkSynthErrorTypePositions(tokens: []const lexer.Token) !void {
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


pub fn checkUpperValueExprs(program: parser.Program, tokens: []const lexer.Token) !void {
    for (program.expr_nodes) |node| {
        if (node.kind != .ident) continue;
        const tok = tokens[node.start_tok];
        if (!isValidDeclaredTypeName(tok.lexeme)) continue;
        if (isTypeConstructorExpr(tokens, node.start_tok)) continue;
        if (isPayloadEnumCaseCtorExpr(tokens, node.start_tok)) continue;
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

/// `Text(buf)` / unit case `Quit` used as payload-enum constructor.

/// `Text(buf)` / unit case `Quit` used as payload-enum constructor.
fn isPayloadEnumCaseCtorExpr(tokens: []const lexer.Token, start_idx: usize) bool {
    if (start_idx >= tokens.len or tokens[start_idx].kind != .ident) return false;
    const name = publicTypeName(tokens[start_idx].lexeme);
    if (!isLocalPayloadEnumCase(tokens, name)) return false;
    // Unit case: bare Ident. Payload case: Ident(expr).
    if (start_idx + 1 < tokens.len and tokEq(tokens[start_idx + 1], "(")) return true;
    return true;
}


fn isLocalErrorBranchValue(tokens: []const lexer.Token, name: []const u8) bool {
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
        if (!isErrorEnumDeclStart(tokens, i) and !isValueEnumDeclStart(tokens, i) and !isPayloadEnumDeclStart(tokens, i)) continue;
        if (enumDeclHasBranch(tokens, i, name)) return true;
    }
    return false;
}


pub fn checkTopValueDeclNames(tokens: []const lexer.Token) !void {
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


pub fn checkTypeRefs(tokens: []const lexer.Token) !void {
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
        if (t.lexeme.len < 2 or t.lexeme[0] != '.') continue;
        if (!std.ascii.isUpper(t.lexeme[1])) continue;
        if (isTopLevelDeclHead(tokens, i) and isTypeDeclStart(tokens, i)) continue;
        if (isValueEnumBranchDeclToken(tokens, i)) continue;
        return markErrorAt(tokens, i, error.InvalidTypeRef);
    }
}


pub fn checkForbiddenSourceTypeNames(tokens: []const lexer.Token) !void {
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
    return std.mem.eql(u8, name, "host");
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


pub fn checkBareNilTypes(tokens: []const lexer.Token) !void {
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


pub fn checkParenthesizedTypeArgs(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tokEq(tokens[i], "(")) continue;
        if (!isTypeArgStartAfterSeparator(tokens, i)) continue;
        return markErrorAt(tokens, i, error.InvalidTypeRef);
    }
}


pub fn checkParenthesizedTypes(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tokEq(tokens[i], "(")) continue;
        if (isFieldsLoopSourceTypeParen(tokens, i)) continue;
        if (isFuncTypeStart(tokens, i)) continue;
        if (isPayloadEnumCasePayloadParen(tokens, i)) continue;
        const close_idx = findMatching(tokens, i, "(", ")") catch continue;
        if (!isParenthesizedTypeContext(tokens, i, close_idx)) continue;
        if (!isTypeExprRangeAllowParens(tokens, i + 1, close_idx)) continue;
        return markErrorAt(tokens, i, error.InvalidTypeRef);
    }
}

/// `Text([u8])` payload paren on a payload-enum case arm.

/// `Text([u8])` payload paren on a payload-enum case arm.
fn isPayloadEnumCasePayloadParen(tokens: []const lexer.Token, open_idx: usize) bool {
    if (open_idx == 0) return false;
    if (tokens[open_idx - 1].kind != .ident) return false;
    if (tokens[open_idx - 1].line != tokens[open_idx].line) return false;
    if (!isValidEnumBranchName(tokens[open_idx - 1])) return false;

    const line_start = lineStartIdx(tokens, open_idx);
    if (!isPayloadEnumDeclStart(tokens, line_start)) return false;

    // Case must be at case position after `=` / `|`.
    const case_idx = open_idx - 1;
    if (case_idx == line_start + 2) return true; // first case after Name =
    if (case_idx > line_start + 2 and tokEq(tokens[case_idx - 1], "|")) return true;
    return false;
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


pub fn checkGenericTypeArgArity(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (!isValidDeclaredTypeName(tokens[i].lexeme)) continue;
        if (!tokEq(tokens[i + 1], "<")) continue;

        const close_angle = findMatching(tokens, i + 1, "<", ">") catch continue;
        const type_name = publicTypeName(tokens[i].lexeme);
        if (std.mem.eql(u8, type_name, "Tuple")) {
            const actual_count = countTypeArgs(tokens, i + 2, close_angle);
            if (actual_count < 2) return markErrorAt(tokens, i, error.InvalidTypeRef);
            i = close_angle;
            continue;
        }
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

/// Position-ctor arity for `Tuple<T0,...>{v0,...}` must equal type-arg count.
/// Nested ctors are scanned by not skipping the body after the outer ctor.
/// Named field inits are usually rejected earlier as InvalidStructLiteral by the parser;
/// this path remains as a defensive fallback (InvalidTypedLiteral).

fn isLocalNonStructTypeName(tokens: []const lexer.Token, name: []const u8) bool {
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
        if (isModernImportAssign(tokens, i)) continue;
        if (!isTypeDeclStart(tokens, i)) continue;
        return !isStructDeclStart(tokens, i);
    }
    return false;
}


pub fn checkUnboundTypeParamRefs(tokens: []const lexer.Token) !void {
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


pub fn checkDuplicateUnionBranches(tokens: []const lexer.Token) !void {
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


pub fn checkInlineFuncTypeUnionBranches(tokens: []const lexer.Token) !void {
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


