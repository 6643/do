//! Sema func domain — lambda (extracted from sema_func).
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema_error = @import("sema_error.zig");
const type_util = @import("type_name.zig");
const sema_util = @import("sema_util.zig");
const sema_types = @import("sema_types.zig");
const sema_func_shared = @import("sema_func_shared.zig");
const CallShape = sema_types.CallShape;
const collectCallShapesFromProgram = sema_func_shared.collectCallShapesFromProgram;
const findEnclosingFuncParamTypeName = sema_func_shared.findEnclosingFuncParamTypeName;
const freeResolvedFuncTypeShape = sema_func_shared.freeResolvedFuncTypeShape;
const isScalarAsTargetTypeName = sema_func_shared.isScalarAsTargetTypeName;
const resolveFuncParamTypeShape = sema_func_shared.resolveFuncParamTypeShape;
const typeConstraintIsConcreteFunctionType = sema_func_shared.typeConstraintIsConcreteFunctionType;

const callArgInfo = sema_util.callArgInfo;
const callArityCompatibleWithFunc = sema_util.callArityCompatibleWithFunc;
const collectFuncShapes = sema_util.collectFuncShapes;
const containsName = sema_util.containsName;
const findLineEndIdx = sema_util.findLineEndIdx;
const findMatching = sema_util.findMatching;
const findTopLevelAssignEqOnLine = sema_util.findTopLevelAssignEqOnLine;
const freeCallArgShapes = sema_util.freeCallArgShapes;
const freeFuncShapes = sema_util.freeFuncShapes;
const hasKnownFuncCandidate = sema_util.hasKnownFuncCandidate;
const isKeyword = sema_util.isKeyword;
const isLowerIdentName = sema_util.isLowerIdentName;
const isNonAssignEqual = sema_util.isNonAssignEqual;
const isReservedFuncName = sema_util.isReservedFuncName;
const isTopLevelDeclHead = sema_util.isTopLevelDeclHead;
const isTopLevelToken = sema_util.isTopLevelToken;
const isVisibleBindingOrCallableName = sema_util.isVisibleBindingOrCallableName;
const lambdaBodyStart = sema_util.lambdaBodyStart;
const lineStartIdx = sema_util.lineStartIdx;
const markErrorAt = sema_util.markErrorAt;
const tokEq = sema_util.tokEq;
const FuncParamShape = sema_types.FuncParamShape;
const FuncShape = sema_types.FuncShape;
const FuncTypeShape = sema_types.FuncTypeShape;

pub fn checkLambdaUsage(allocator: std.mem.Allocator, program: parser.Program, tokens: []const lexer.Token) !void {
    for (program.expr_nodes) |node| {
        if (node.kind != .lambda) continue;
        try checkOneLambdaUsage(allocator, tokens, node);
    }
}



pub fn checkOneLambdaUsage(
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



pub fn checkLambdaOverloadCalls(
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



pub fn isSetUpdateLambdaCall(call: CallShape) bool {
    if (!std.mem.eql(u8, call.name, "set")) return false;
    if (call.arg_shapes.len < 3) return false;
    return call.arg_shapes[call.arg_shapes.len - 1] == .lambda;
}



pub fn countCompatibleFunctionValueCandidates(
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



pub fn functionValueArgsMatchFunc(
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



pub fn countFuncsMatchingTarget(
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



pub fn functionMatchesTarget(func: FuncShape, target: FuncTypeShape) bool {
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



pub fn callHasTargetFunctionValue(tokens: []const lexer.Token, funcs: []const FuncShape, call: CallShape) bool {
    for (call.arg_shapes, 0..) |arg, arg_index| {
        if (arg == .lambda and callHasFuncParamCandidateAtIndex(tokens, funcs, call, arg_index)) return true;
        if (arg != .ident) continue;
        const ident = arg.ident;
        if (!hasKnownFuncCandidate(funcs, ident)) continue;
        if (callHasFuncParamCandidateAtIndex(tokens, funcs, call, arg_index)) return true;
    }
    return false;
}



pub fn callHasFuncParamCandidateAtIndex(tokens: []const lexer.Token, funcs: []const FuncShape, call: CallShape, arg_index: usize) bool {
    for (funcs) |func| {
        if (!std.mem.eql(u8, func.name, call.name)) continue;
        if (!callArityCompatibleWithFunc(func, call.arg_shapes.len)) continue;
        if (arg_index >= func.param_shapes.len) continue;
        if (funcParamShapeIsFunctionLike(tokens, func, func.param_shapes[arg_index])) return true;
    }
    return false;
}



pub fn funcParamShapeIsFunctionLike(tokens: []const lexer.Token, func: FuncShape, param: FuncParamShape) bool {
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



pub fn checkBareOverloadedFuncAssign(tokens: []const lexer.Token, funcs: []const FuncShape) !void {
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



pub fn countFuncsByName(funcs: []const FuncShape, name: []const u8) usize {
    var count: usize = 0;
    for (funcs) |func| {
        if (std.mem.eql(u8, func.name, name)) count += 1;
    }
    return count;
}



pub fn explicitLambdaTypesMatch(target_types: []const ?[]const u8, lambda_types: []const ?[]const u8) bool {
    if (target_types.len != lambda_types.len) return false;
    for (lambda_types, 0..) |lambda_type, idx| {
        const expected = lambda_type orelse continue;
        const actual = target_types[idx] orelse return false;
        if (!std.mem.eql(u8, actual, expected)) return false;
    }
    return true;
}



pub fn lambdaParamOpen(tokens: []const lexer.Token, start_idx: usize) ?usize {
    if (start_idx >= tokens.len) return null;
    if (tokEq(tokens[start_idx], "(")) return start_idx;
    return null;
}



pub fn isLambdaCallArgSite(tokens: []const lexer.Token, start_idx: usize) bool {
    if (isDisallowedSetPathLambda(tokens, start_idx)) return false;
    if (start_idx == 0) return false;
    const prev = tokens[start_idx - 1];
    if (tokEq(prev, ",")) return true;
    if (!tokEq(prev, "(")) return false;
    if (start_idx < 2) return false;
    const before_prev = tokens[start_idx - 2];
    return before_prev.kind == .ident or tokEq(before_prev, ")") or tokEq(before_prev, "]");
}



pub fn isDisallowedSetPathLambda(tokens: []const lexer.Token, start_idx: usize) bool {
    const info = callArgInfo(tokens, start_idx) orelse return false;
    if (!std.mem.eql(u8, info.name, "set")) return false;
    return info.arg_index + 1 < info.arg_count;
}



fn skipLambdaParamTypeTail(tokens: []const lexer.Token, start_i: usize, end_idx: usize) !usize {
    var i = start_i;
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
    if (depth_paren != 0 or depth_angle != 0 or depth_brace != 0) {
        return markErrorAt(tokens, end_idx - 1, error.InvalidLambdaExpr);
    }
    return i;
}

pub fn collectLambdaParamNames(
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

        i = try skipLambdaParamTypeTail(tokens, i, end_idx);
        if (i < end_idx and tokEq(tokens[i], ",")) {
            i += 1;
            if (i >= end_idx) return markErrorAt(tokens, end_idx - 1, error.InvalidLambdaExpr);
        }
    }

    return out.toOwnedSlice(allocator);
}



pub fn isLambdaParamNameToken(tok: lexer.Token) bool {
    if (tok.kind != .ident) return false;
    if (tok.lexeme.len == 0) return false;
    if (tok.lexeme[0] == '_') return false;
    return std.ascii.isLower(tok.lexeme[0]) and !isReservedFuncName(tok.lexeme);
}



pub fn findLambdaCapture(
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



pub fn isLambdaLocalBindName(tokens: []const lexer.Token, idx: usize, body_start: usize) bool {
    if (!isLowerIdentName(tokens[idx].lexeme)) return false;
    if (isReservedFuncName(tokens[idx].lexeme)) return false;

    const line_start = lambdaLineStart(tokens, idx, body_start);
    const line_end = findLineEndIdx(tokens, idx);
    const eq_idx = findTopLevelAssignEqOnLine(tokens, line_start, line_end) orelse return false;
    return idx < eq_idx;
}



pub fn isAsScalarTypeToken(tokens: []const lexer.Token, idx: usize) bool {
    if (!isScalarAsTargetTypeName(tokens[idx].lexeme)) return false;
    const info = callArgInfo(tokens, idx) orelse return false;
    return std.mem.eql(u8, info.name, "as") and (info.arg_index == 0 or info.arg_index == 1);
}



pub fn lambdaLineStart(tokens: []const lexer.Token, idx: usize, body_start: usize) usize {
    var line_start = idx;
    while (line_start > body_start and tokens[line_start - 1].line == tokens[idx].line) {
        line_start -= 1;
    }
    if (line_start < idx and tokEq(tokens[line_start], "{")) return line_start + 1;
    return line_start;
}



pub fn isVisibleLocalBindingBefore(tokens: []const lexer.Token, name: []const u8, before_idx: usize) bool {
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



pub fn isLocalBindingIntroducer(tokens: []const lexer.Token, idx: usize) bool {
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



