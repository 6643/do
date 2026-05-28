const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

const Scope = struct {
    names: std.ArrayListUnmanaged([]const u8) = .empty,

    fn deinit(self: *Scope, allocator: std.mem.Allocator) void {
        self.names.deinit(allocator);
    }

    fn contains(self: *const Scope, name: []const u8) bool {
        for (self.names.items) |it| {
            if (std.mem.eql(u8, it, name)) return true;
        }
        return false;
    }
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
    try checkFuncParamNames(tokens);
    try checkPathAccess(tokens);
    try checkHostImports(tokens);
    if (program.top_level_count == 0) return markErrorAt(tokens, 0, error.NoTopLevelDecl);

    try checkTypeDeclNaming(tokens);
    try checkTopValueDeclNames(tokens);
    try checkStructFieldNames(allocator, tokens);
    try checkTypeRefs(tokens);
    try checkPathIndexSegments(tokens);
    try checkConstraintLayout(tokens);
    try checkSingleValuePositions(program, tokens);
    try checkKnownConditionBoolSites(program, tokens);
    try checkLambdaUsage(allocator, program, tokens);
    try checkLambdaOverloadCalls(allocator, program, tokens);
    try checkIsTypeArgs(tokens);
    try checkIfPatternBind(tokens);
    try checkLoopHeader(tokens);
    try checkLoopLabels(allocator, tokens);
    try checkAssignmentConstraints(allocator, tokens);
}

fn checkPrivateLValueAssign(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        const t = tokens[i];
        if (t.kind != .ident) continue;
        if (t.lexeme.len < 2 or t.lexeme[0] != '.') continue;
        const line_end = findLineEndIdx(tokens, i);
        const eq_idx = findPlainEqOnLine(tokens, i + 1, line_end) orelse continue;
        if (isTopLevelDeclHead(tokens, i) and isTypeDeclStart(tokens, i)) continue;
        if (isStructFieldDeclDefault(tokens, i, eq_idx)) continue;
        return markErrorAt(tokens, i, error.PrivateIdentCannotBeLValue);
    }
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
        if (!isReservedFuncName(t.lexeme)) continue;
        return markErrorAt(tokens, i, error.InvalidFuncDeclName);
    }
}

fn checkFuncParamNames(tokens: []const lexer.Token) !void {
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
        try validateFuncParamNames(tokens, i + 2, close_paren);
        i = close_paren;
    }
}

fn validateFuncParamNames(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) !void {
    var expect_name = true;
    var saw_variadic = false;
    var expect_variadic_type = false;
    var depth_angle: usize = 0;
    var depth_paren: usize = 0;
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
        if (!isValidFuncParamName(tokens[i].lexeme)) return markErrorAt(tokens, i, error.InvalidParamName);
        expect_name = false;
    }
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

fn checkSingleValuePositions(program: parser.Program, tokens: []const lexer.Token) !void {
    for (program.condition_exprs) |site| {
        const call_site = findDirectCallAtRoot(program, site.root_expr_idx);
        if (call_site == null) continue;

        const resolved = resolveConditionCallReturnArity(
            program.func_sigs,
            call_site.?.call.func_name,
            call_site.?.call.arg_count,
        );
        switch (resolved) {
            .unknown => continue, // 可能是外部导入函数, 此阶段不阻断
            .single => continue,
            .multi => {
                switch (site.context) {
                    .if_cond => return markErrorAt(tokens, call_site.?.start_tok_idx, error.MultiReturnInIfCondition),
                    .if_bind_rhs => return markErrorAt(tokens, call_site.?.start_tok_idx, error.MultiReturnInIfBindRhs),
                    .loop_cond => return markErrorAt(tokens, call_site.?.start_tok_idx, error.MultiReturnInLoopCondition),
                }
            },
            .ambiguous => return markErrorAt(tokens, call_site.?.start_tok_idx, error.AmbiguousConditionCallReturnArity),
        }
    }
}

const KnownBool = enum {
    yes,
    no,
    unknown,
};

fn checkKnownConditionBoolSites(program: parser.Program, tokens: []const lexer.Token) !void {
    for (program.condition_exprs) |site| {
        const err = switch (site.context) {
            .if_cond => error.NonBoolIfCondition,
            .loop_cond => error.NonBoolLoopCondition,
            else => continue,
        };

        switch (classifyKnownBool(program, tokens, site.root_expr_idx)) {
            .yes, .unknown => continue,
            .no => {
                const start_tok = rootExprStartTok(program, site.root_expr_idx);
                return markErrorAt(tokens, start_tok, err);
            },
        }
    }
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
            return markErrorAt(tokens, i + 1, error.InvalidCallArgList);
        const comma = findTopLevelComma(tokens, i + 2, close_paren) orelse
            return markErrorAt(tokens, i, error.InvalidCallArgList);
        const type_arg = firstNonGap(tokens, comma + 1, close_paren) orelse
            return markErrorAt(tokens, comma, error.InvalidCallArgList);
        if (isValueLiteralToken(tokens[type_arg])) {
            return markErrorAt(tokens, type_arg, error.InvalidCallArgList);
        }
    }
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
};

const FuncParamShape = union(enum) {
    other,
    value: ?[]const u8,
    func: FuncTypeShape,
};

const FuncTypeShape = struct {
    param_count: usize,
    param_types: []?[]const u8,
    return_type: ?[]const u8,
};

const FuncShape = struct {
    name: []const u8,
    start_idx: usize,
    param_shapes: []FuncParamShape,
    return_type: ?[]const u8,
};

const CallArgShape = union(enum) {
    other,
    lambda: LambdaArgShape,
    ident: []const u8,
};

const CallShape = struct {
    name: []const u8,
    start_idx: usize,
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
        if (!callHasTargetFunctionValue(funcs, call)) continue;
        if (!hasKnownFuncCandidate(funcs, call.name)) continue;
        if (countCompatibleFunctionValueCandidates(funcs, call) != 1) {
            return markErrorAt(tokens, call.start_idx, error.NoMatchingCall);
        }
    }

    try checkBareOverloadedFuncAssign(tokens, funcs);

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
        try out.append(allocator, .{
            .name = publicFuncName(tokens[i].lexeme),
            .start_idx = i,
            .param_shapes = params,
            .return_type = parseTopLevelFuncReturnType(tokens, close_paren + 1),
        });
        i = close_paren + 1;
    }

    return out.toOwnedSlice(allocator);
}

fn freeFuncShapes(allocator: std.mem.Allocator, funcs: []FuncShape) void {
    for (funcs) |shape| freeFuncParamShapes(allocator, shape.param_shapes);
    allocator.free(funcs);
}

fn freeFuncParamShapes(allocator: std.mem.Allocator, shapes: []FuncParamShape) void {
    for (shapes) |shape| {
        switch (shape) {
            .other => {},
            .value => {},
            .func => |func_type| allocator.free(func_type.param_types),
        }
    }
    allocator.free(shapes);
}

fn freeCallArgShapes(allocator: std.mem.Allocator, shapes: []CallArgShape) void {
    for (shapes) |shape| {
        switch (shape) {
            .other => {},
            .lambda => |lambda| allocator.free(lambda.param_types),
            .ident => {},
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
    const type_start = start_idx + 1;
    if (!tokEq(tokens[type_start], "(")) {
        return .{ .value = simpleTypeName(tokens, type_start, end_idx) };
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
            .call, .do_call => {},
            else => continue,
        }

        const call_start = if (node.kind == .do_call) node.start_tok + 1 else node.start_tok;
        if (call_start + 1 >= node.end_tok) continue;
        if (!tokEq(tokens[call_start + 1], "(")) continue;

        const args_start = call_start + 2;
        const args_end = node.end_tok - 1;
        const args = try parseCallArgShapes(allocator, tokens, args_start, args_end);
        try out.append(allocator, .{
            .name = if (node.kind == .do_call) node.data.call.func_name else tokens[call_start].lexeme,
            .start_idx = node.start_tok,
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
    const close_params = lambdaParamClose(tokens, start_idx, end_idx);
    if (close_params) |close_idx| {
        if (lambdaBodyStart(tokens, close_idx + 1, end_idx) != null) {
            const param_types = try parseLambdaParamTypeList(allocator, tokens, start_idx + 1, close_idx);
            return .{ .lambda = .{
                .arg_index = arg_index,
                .param_count = param_types.len,
                .param_types = param_types,
            } };
        }
    }

    if (start_idx + 1 == end_idx and tokens[start_idx].kind == .ident) {
        return .{ .ident = tokens[start_idx].lexeme };
    }

    return .other;
}

fn lambdaParamClose(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (start_idx >= end_idx or !tokEq(tokens[start_idx], "(")) return null;
    const close_idx = findMatching(tokens, start_idx, "(", ")") catch return null;
    if (close_idx >= end_idx) return null;
    return close_idx;
}

fn hasKnownFuncCandidate(funcs: []const FuncShape, name: []const u8) bool {
    for (funcs) |func| {
        if (std.mem.eql(u8, func.name, name)) return true;
    }
    return false;
}

fn countCompatibleFunctionValueCandidates(funcs: []const FuncShape, call: CallShape) usize {
    var count: usize = 0;
    for (funcs) |func| {
        if (!std.mem.eql(u8, func.name, call.name)) continue;
        if (func.param_shapes.len != call.arg_shapes.len) continue;
        if (!functionValueArgsMatchFunc(funcs, func, call)) continue;
        count += 1;
    }
    return count;
}

fn functionValueArgsMatchFunc(funcs: []const FuncShape, func: FuncShape, call: CallShape) bool {
    for (call.arg_shapes, 0..) |arg, arg_index| {
        switch (arg) {
            .other => continue,
            .lambda => |lambda| {
                if (lambda.arg_index >= func.param_shapes.len) return false;
                const target = func.param_shapes[lambda.arg_index];
                switch (target) {
                    .other => return false,
                    .value => return false,
                    .func => |func_type| {
                        if (func_type.param_count != lambda.param_count) return false;
                        if (!explicitLambdaTypesMatch(func_type.param_types, lambda.param_types)) return false;
                    },
                }
            },
            .ident => |name| {
                if (arg_index >= func.param_shapes.len) return false;
                const target = func.param_shapes[arg_index];
                switch (target) {
                    .func => |target_func| {
                        if (countFuncsMatchingTarget(funcs, name, target_func) != 1) return false;
                    },
                    else => continue,
                }
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

fn callHasTargetFunctionValue(funcs: []const FuncShape, call: CallShape) bool {
    for (call.arg_shapes, 0..) |arg, arg_index| {
        if (arg == .lambda) return true;
        if (arg != .ident) continue;
        const ident = arg.ident;
        if (!hasKnownFuncCandidate(funcs, ident)) continue;
        if (callHasFuncParamCandidateAtIndex(funcs, call, arg_index)) return true;
    }
    return false;
}

fn callHasFuncParamCandidateAtIndex(funcs: []const FuncShape, call: CallShape, arg_index: usize) bool {
    for (funcs) |func| {
        if (!std.mem.eql(u8, func.name, call.name)) continue;
        if (func.param_shapes.len != call.arg_shapes.len) continue;
        if (arg_index >= func.param_shapes.len) continue;
        if (func.param_shapes[arg_index] == .func) return true;
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
    errdefer out.deinit(allocator);

    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !isTopLevelCommaAny(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            try out.append(allocator, simpleTypeName(tokens, seg_start, i));
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
    if (isKeyword(tokens[idx].lexeme)) return false;
    return tokEq(tokens[idx + 1], "(");
}

fn isFuncDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (tokens[idx].kind != .ident) return false;
    if (!isValidFuncDeclName(tokens[idx].lexeme)) return false;
    return tokEq(tokens[idx + 1], "(");
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
    if (start_idx == 0) return false;
    const prev = tokens[start_idx - 1];
    if (tokEq(prev, ",")) return true;
    if (!tokEq(prev, "(")) return false;
    if (start_idx < 2) return false;
    const before_prev = tokens[start_idx - 2];
    return before_prev.kind == .ident or tokEq(before_prev, ")") or tokEq(before_prev, "]");
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
        try out.append(allocator, tokens[i].lexeme);
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
    if (tok.lexeme[0] == '_') return tok.lexeme.len == 1;
    return std.ascii.isLower(tok.lexeme[0]) and !isKeyword(tok.lexeme);
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
        if (tok.lexeme[0] == '_') continue;
        if (std.ascii.isUpper(tok.lexeme[0])) continue;
        if (isKeyword(tok.lexeme)) continue;
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

    const line_start = lambdaLineStart(tokens, idx, body_start);
    const line_end = findLineEndIdx(tokens, idx);
    const eq_idx = findTopLevelAssignEqOnLine(tokens, line_start, line_end) orelse return false;
    return idx < eq_idx;
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

fn classifyKnownBool(program: parser.Program, tokens: []const lexer.Token, root_idx: usize) KnownBool {
    if (root_idx >= program.expr_nodes.len) return .unknown;
    const node = program.expr_nodes[root_idx];

    return switch (node.kind) {
        .paren => classifyKnownBool(program, tokens, node.data.child),
        .literal => classifyLiteralBool(tokens, node.start_tok),
        .ident => classifyTypedIdentBool(tokens, node.start_tok),
        .call, .do_call => classifyCallBool(program.func_sigs, node.data.call),
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
        if (eq_idx > i + 1 and tokens[i + 1].kind == .ident and isDeclaredTypeName(tokens[i + 1].lexeme)) return tokens[i + 1].lexeme;
        if (eq_idx > i + 1 and tokens[i + 1].kind == .ident and isGenericTypeStart(tokens, i + 1, eq_idx)) return tokens[i + 1].lexeme;
        if (tokens[eq_idx + 1].kind == .ident and eq_idx + 2 < line_end and tokEq(tokens[eq_idx + 2], "{")) return tokens[eq_idx + 1].lexeme;
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
    while (i + 1 < end_idx) {
        if (tokens[i].kind != .ident or tokens[i + 1].kind != .ident) {
            i += 1;
            continue;
        }
        const name = if (tokens[i].lexeme.len != 0 and tokens[i].lexeme[0] == '.') tokens[i].lexeme[1..] else tokens[i].lexeme;
        if (std.mem.eql(u8, name, field_name)) return isBoolTypeSpec(tokens, i + 1, i + 2);
        i += 2;
        while (i < end_idx and tokens[i].line == tokens[i - 1].line) : (i += 1) {}
    }
    return null;
}

fn isDeclaredTypeName(name: []const u8) bool {
    return name.len != 0 and std.ascii.isUpper(name[0]);
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

fn classifyCallBool(func_sigs: []const parser.FuncSig, call: parser.FuncCallRef) KnownBool {
    if (isBuiltinBoolCall(call.func_name)) return .yes;

    var saw_candidate = false;
    var saw_bool = false;
    var saw_non_bool = false;

    for (func_sigs) |sig| {
        if (!std.mem.eql(u8, sig.name, call.func_name)) continue;
        if (!isArgCountCompatible(sig, call.arg_count)) continue;
        saw_candidate = true;
        if (sig.return_arity == 1 and sig.returns_bool) {
            saw_bool = true;
        } else {
            saw_non_bool = true;
        }
    }

    if (!saw_candidate) return .unknown;
    if (saw_bool and saw_non_bool) return .unknown;
    if (saw_bool) return .yes;
    return .no;
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
        .paren => findDirectCallAtRoot(program, node.data.child),
        else => null,
    };
}

const ReturnArityResolve = enum {
    unknown,
    single,
    multi,
    ambiguous,
};

fn resolveConditionCallReturnArity(
    func_sigs: []const parser.FuncSig,
    func_name: []const u8,
    arg_count: usize,
) ReturnArityResolve {
    var seen = false;
    var seen_single = false;
    var seen_multi = false;

    for (func_sigs) |sig| {
        if (!std.mem.eql(u8, sig.name, func_name)) continue;
        if (!isArgCountCompatible(sig, arg_count)) continue;
        seen = true;
        if (sig.return_arity <= 1) {
            seen_single = true;
        } else {
            seen_multi = true;
        }
    }

    if (!seen) return .unknown;
    if (seen_single and seen_multi) return .ambiguous;
    if (seen_multi) return .multi;
    return .single;
}

fn isArgCountCompatible(sig: parser.FuncSig, arg_count: usize) bool {
    if (arg_count < sig.param_min) return false;
    if (sig.param_max) |max_count| {
        return arg_count <= max_count;
    }
    return true;
}

fn parseImportDeclEnd(tokens: []const lexer.Token, start_idx: usize) ?usize {
    if (!tokEq(tokens[start_idx], "{")) return null;
    const close_brace = findMatching(tokens, start_idx, "{", "}") catch return null;
    if (close_brace + 5 >= tokens.len) return null;

    const colon_idx = close_brace + 1;
    if (!tokEq(tokens[colon_idx], ":")) return null;
    if (!tokEq(tokens[colon_idx + 1], "=")) return null;
    if (!tokEq(tokens[colon_idx + 2], "@")) return null;
    if (!tokEq(tokens[colon_idx + 3], "(")) return null;
    if (tokens[colon_idx + 4].kind != .string) return null;

    const close_paren = findMatching(tokens, colon_idx + 3, "(", ")") catch return null;
    if (close_paren != colon_idx + 5) return null;
    return close_paren + 1;
}

fn findMatching(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8) !usize {
    if (open_idx >= tokens.len or !tokEq(tokens[open_idx], open)) return error.InvalidGroupStart;

    var depth: usize = 0;
    var i = open_idx;
    while (i < tokens.len) : (i += 1) {
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

fn checkIfPatternBind(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            if (parseImportDeclEnd(tokens, i)) |next_idx| {
                i = next_idx - 1;
                continue;
            }
        }

        if (!tokEq(tokens[i], "if")) continue;

        var bind_colon_idx: ?usize = null;
        var j = i + 1;
        while (j < tokens.len and (j - i) <= 48) : (j += 1) {
            if (tokEq(tokens[j], "{")) break;
            if (tokEq(tokens[j], ":") and j + 1 < tokens.len and tokEq(tokens[j + 1], "=")) {
                bind_colon_idx = j;
                break;
            }
        }
        if (bind_colon_idx == null) continue;

        const bind_idx = bind_colon_idx.?;
        if (i + 1 >= bind_idx) return markErrorAt(tokens, i, error.InvalidIfPatternBind);
        const first = tokens[i + 1];
        if (first.kind != .ident) return markErrorAt(tokens, i + 1, error.InvalidIfPatternBind);
        if (!isTypeName(first.lexeme)) return markErrorAt(tokens, i + 1, error.InvalidIfPatternBind);
        if (i + 2 >= bind_idx) return markErrorAt(tokens, i + 2, error.InvalidIfPatternBind);

        const open = tokens[i + 2];
        const close = tokens[bind_idx - 1];
        if (tokEq(open, "(") and tokEq(close, ")")) continue;
        if (tokEq(open, "{") and tokEq(close, "}")) continue;
        return markErrorAt(tokens, bind_idx, error.InvalidIfPatternBind);
    }
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
        if (isValidDeclaredTypeName(t.lexeme)) continue;
        return markErrorAt(tokens, i, error.InvalidTypeDeclName);
    }
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
        if (isTypeDeclStart(tokens, i)) continue;
        if (i + 1 < tokens.len and tokEq(tokens[i + 1], "(")) continue;

        const line_end = findLineEndIdx(tokens, i);
        if (findTopLevelAssignEqOnLine(tokens, i + 1, line_end) == null) continue;
        if (isReadonlyIdentName(t.lexeme)) continue;
        return markErrorAt(tokens, i, error.InvalidBindingName);
    }
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
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!isTopLevelDeclHead(tokens, i)) continue;
        if (!isHostImportDeclStart(tokens, i)) continue;
        try validateHostImportDecl(tokens, i);
    }
}

fn isHostImportDeclStart(tokens: []const lexer.Token, idx: usize) bool {
    const eq_idx = topLevelLineAssignIdx(tokens, idx) orelse return false;
    const line_end = findLineEndIdx(tokens, idx);
    const at_idx = eq_idx + 1;
    if (at_idx >= line_end or !tokEq(tokens[at_idx], "@")) return false;
    return isHostImportLine(tokens, at_idx, line_end);
}

fn isModernImportAssign(tokens: []const lexer.Token, idx: usize) bool {
    const eq_idx = topLevelLineAssignIdx(tokens, idx) orelse return false;
    return eq_idx + 1 < tokens.len and tokEq(tokens[eq_idx + 1], "@");
}

fn validateHostImportDecl(tokens: []const lexer.Token, name_idx: usize) !void {
    if (tokens[name_idx].kind != .ident) return markErrorAt(tokens, name_idx, error.InvalidImportDecl);
    if (tokens[name_idx].lexeme.len != 0 and tokens[name_idx].lexeme[0] == '.') {
        return markErrorAt(tokens, name_idx, error.InvalidImportDecl);
    }
    if (!isValidImportName(tokens[name_idx].lexeme)) {
        return markErrorAt(tokens, name_idx, error.InvalidImportDecl);
    }

    const eq_idx = topLevelLineAssignIdx(tokens, name_idx) orelse return markErrorAt(tokens, name_idx, error.InvalidImportDecl);
    const line_end = findLineEndIdx(tokens, name_idx);
    const at_idx = eq_idx + 1;
    if (at_idx >= line_end or !tokEq(tokens[at_idx], "@")) return markErrorAt(tokens, eq_idx, error.InvalidImportDecl);
    if (at_idx + 1 >= line_end) return markErrorAt(tokens, at_idx, error.InvalidImportDecl);

    if (!isLowerIdentName(tokens[name_idx].lexeme)) {
        return markErrorAt(tokens, name_idx, error.InvalidImportDecl);
    }
    try validateHostImportLine(tokens, at_idx, line_end);
}

fn isValidImportName(name: []const u8) bool {
    return isValidDeclaredTypeName(name) or isLowerIdentName(name) or isReadonlyIdentName(name);
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

fn isHostImportLine(tokens: []const lexer.Token, at_idx: usize, line_end: usize) bool {
    if (at_idx + 2 >= line_end) return false;
    if (tokens[at_idx + 1].kind != .ident or !tokEq(tokens[at_idx + 2], "/")) return false;
    if (std.mem.indexOf(u8, tokens[at_idx + 1].lexeme, ".do") != null) return false;
    return findTokenOnLine(tokens, at_idx + 3, line_end, "(") != null;
}

fn validateLocalImportPath(tokens: []const lexer.Token, start_idx: usize, line_end: usize) !usize {
    var i = start_idx;
    if (i < line_end and tokEq(tokens[i], "~")) i += 1;
    if (i < line_end and tokEq(tokens[i], "/")) i += 1;
    if (i >= line_end) return markErrorAt(tokens, start_idx, error.InvalidImportDecl);

    var saw_file = false;
    while (i < line_end) {
        if (tokens[i].kind != .ident) return markErrorAt(tokens, i, error.InvalidImportDecl);
        const is_file = try validateImportPathIdent(tokens, i);
        i += 1;
        if (i >= line_end) return markErrorAt(tokens, i - 1, error.InvalidImportDecl);
        if (!tokEq(tokens[i], "/")) return markErrorAt(tokens, i, error.InvalidImportDecl);
        i += 1;
        if (i >= line_end) return markErrorAt(tokens, i - 1, error.InvalidImportDecl);
        if (!is_file) continue;

        saw_file = true;
        if (tokens[i].kind != .ident) return markErrorAt(tokens, i, error.InvalidImportDecl);
        if (!isValidImportName(tokens[i].lexeme)) return markErrorAt(tokens, i, error.InvalidImportDecl);
        if (i + 1 != line_end) return markErrorAt(tokens, i + 1, error.InvalidImportDecl);
        return i;
    }
    if (!saw_file) return markErrorAt(tokens, start_idx, error.InvalidImportDecl);
    return markErrorAt(tokens, start_idx, error.InvalidImportDecl);
}

fn validateImportPathIdent(tokens: []const lexer.Token, idx: usize) !bool {
    const s = tokens[idx].lexeme;
    const dot_idx = std.mem.indexOf(u8, s, ".do") orelse {
        try validatePathSegToken(tokens, idx, s);
        return false;
    };
    try validatePathSegToken(tokens, idx, s[0..dot_idx]);
    if (dot_idx + 3 != s.len) return markErrorAt(tokens, idx, error.InvalidImportDecl);
    return true;
}

fn validatePathSegToken(tokens: []const lexer.Token, idx: usize, seg: []const u8) !void {
    if (seg.len == 0) return markErrorAt(tokens, idx, error.InvalidImportDecl);
    if (seg[0] == '_' or seg[seg.len - 1] == '_') return markErrorAt(tokens, idx, error.InvalidImportDecl);
    var prev_underscore = false;
    for (seg, 0..) |ch, i| {
        if (ch >= 'a' and ch <= 'z') {
            prev_underscore = false;
            continue;
        }
        if (i != 0 and ch >= '0' and ch <= '9') {
            prev_underscore = false;
            continue;
        }
        if (ch == '_') {
            if (prev_underscore) return markErrorAt(tokens, idx, error.InvalidImportDecl);
            prev_underscore = true;
            continue;
        }
        return markErrorAt(tokens, idx, error.InvalidImportDecl);
    }
}

fn validateHostImportLine(tokens: []const lexer.Token, at_idx: usize, line_end: usize) !void {
    const open_idx = findTokenOnLine(tokens, at_idx + 1, line_end, "(") orelse return markErrorAt(tokens, at_idx, error.InvalidImportDecl);
    const close_idx = findMatching(tokens, open_idx, "(", ")") catch return markErrorAt(tokens, open_idx, error.InvalidImportDecl);
    if (close_idx >= line_end) return markErrorAt(tokens, open_idx, error.InvalidImportDecl);
    try validateHostImportParams(tokens, open_idx + 1, close_idx);

    if (close_idx + 3 > line_end or !tokEq(tokens[close_idx + 1], "-") or !tokEq(tokens[close_idx + 2], ">")) {
        return markErrorAt(tokens, close_idx, error.InvalidImportDecl);
    }
    const ret_start = close_idx + 3;
    if (ret_start >= line_end) return markErrorAt(tokens, close_idx, error.InvalidImportDecl);
    if (hasTopLevelComma(tokens, ret_start, line_end)) return markErrorAt(tokens, ret_start, error.InvalidImportDecl);
    try validateHostReturnType(tokens, ret_start, line_end);
}

fn findParamTypeEnd(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    var i = start_idx;
    while (i < end_idx and !tokEq(tokens[i], ",")) : (i += 1) {}
    return i;
}

fn validateHostImportParams(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) !void {
    if (start_idx >= end_idx) return;
    var i = start_idx;
    while (i < end_idx) {
        const type_end = findParamTypeEnd(tokens, i, end_idx);
        try validateHostParamType(tokens, i, type_end);
        i = type_end;
        if (i >= end_idx) break;
        if (!tokEq(tokens[i], ",")) return markErrorAt(tokens, i, error.InvalidImportDecl);
        i += 1;
    }
}

fn validateHostParamType(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) !void {
    if (end_idx != start_idx + 1 or tokens[start_idx].kind != .ident) return markErrorAt(tokens, start_idx, error.InvalidImportDecl);
    if (isHostParamType(tokens[start_idx].lexeme)) return;
    return markErrorAt(tokens, start_idx, error.InvalidImportDecl);
}

fn validateHostReturnType(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) !void {
    if (end_idx != start_idx + 1 or tokens[start_idx].kind != .ident) return markErrorAt(tokens, start_idx, error.InvalidImportDecl);
    if (isHostReturnType(tokens[start_idx].lexeme)) return;
    return markErrorAt(tokens, start_idx, error.InvalidImportDecl);
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

    var next_idx = idx + 1;
    if (tokEq(tokens[next_idx], "<")) {
        const close_angle = findMatching(tokens, next_idx, "<", ">") catch return false;
        next_idx = close_angle + 1;
        if (next_idx >= tokens.len) return false;
    }

    if (tokEq(tokens[next_idx], "{")) return true; // struct decl
    if (tokEq(tokens[next_idx], "=")) return true; // alias / union / typeset alias
    return false;
}

fn isValidDeclaredTypeName(name: []const u8) bool {
    if (name.len == 0) return false;
    if (name[0] == '.') return isValidDeclaredTypeName(name[1..]);
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
    return isLowerIdentName(name) or isReadonlyIdentName(name);
}

fn isValidLoopBindingName(name: []const u8) bool {
    return std.mem.eql(u8, name, "_") or isLowerIdentName(name);
}

fn isValidFuncParamName(name: []const u8) bool {
    return std.mem.eql(u8, name, "_") or isLowerIdentName(name);
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
        return markErrorAt(tokens, i, error.InvalidTypeRef);
    }
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
                if (labelDeclForLine(label_decls.items, tokens[j].line)) |label_name| {
                    try pending_loops.append(allocator, .{ .open_idx = open_idx, .name = label_name });
                }
            }

            if (tokEq(tokens[j], "break") or tokEq(tokens[j], "continue")) {
                if (j + 1 < line_end and tokEq(tokens[j + 1], "#")) {
                    if (j + 2 >= line_end or tokens[j + 2].kind != .ident) {
                        return markErrorAt(tokens, j + 1, error.InvalidLoopHeader);
                    }
                    if (!labelIsActive(active_labels.items, tokens[j + 2].lexeme)) {
                        return markErrorAt(tokens, j + 1, error.InvalidLoopHeader);
                    }
                }
            }

            if (tokEq(tokens[j], "{")) {
                brace_depth += 1;
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

fn checkLoopSource(tokens: []const lexer.Token, header_start: usize, bind_idx: usize, open_brace: usize) !void {
    if (header_start + 1 == bind_idx) {
        if (!isRecvLoopSource(tokens, bind_idx + 1, open_brace)) {
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

fn isUnsupportedDirectLoopSource(type_name: []const u8) bool {
    return std.mem.eql(u8, type_name, "HashMap");
}

fn checkConstraintLayout(tokens: []const lexer.Token) !void {
    var depth_brace: usize = 0;
    var in_constraint_block = false;
    var saw_func_constraint = false;
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
            if (in_constraint_block) {
                if (tokens[i].line != last_constraint_line + 1) {
                    return markErrorAt(tokens, i, error.InvalidConstraintDecl);
                }
                in_constraint_block = false;
                saw_func_constraint = false;
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

        const is_func_constraint = (i + 2 < line_end and tokEq(tokens[i + 2], "("));
        if (!is_func_constraint and !isValidDeclaredTypeName(tokens[i + 1].lexeme)) {
            return markErrorAt(tokens, i + 1, error.InvalidConstraintDecl);
        }
        if (is_func_constraint and !isLowerIdentName(tokens[i + 1].lexeme)) {
            return markErrorAt(tokens, i + 1, error.InvalidConstraintDecl);
        }
        if (!is_func_constraint and saw_func_constraint) {
            return markErrorAt(tokens, i, error.InvalidConstraintDecl);
        }
        if (is_func_constraint) saw_func_constraint = true;

        in_constraint_block = true;
        last_constraint_line = line;
        i = line_end - 1;
    }
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
            try scopes.append(allocator, .{});
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

        try validateAssignmentLhsNames(tokens, line_start, stmt_eq_idx);

        var k = line_start;
        while (k < i) : (k += 1) {
            const t = tokens[k];
            if (t.kind != .ident) continue;
            if (t.lexeme.len == 0) continue;

            if (t.lexeme[0] == '.') return markErrorAt(tokens, k, error.PrivateIdentCannotBeLValue);
            if (t.lexeme[0] != '_') continue;
            if (std.mem.eql(u8, t.lexeme, "_")) continue;

            var current = &scopes.items[scopes.items.len - 1];
            if (current.contains(t.lexeme)) return markErrorAt(tokens, k, error.DuplicateImmutableBinding);
            try current.names.append(allocator, t.lexeme);
        }
    }
}

fn validateAssignmentLhsNames(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) !void {
    var expect_name = true;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (!expect_name) {
            if (tokEq(tokens[i], ",")) expect_name = true;
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
    return isSnakeLowerName(body);
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
    if (isKeyword(public_name)) return true;
    const reserved = [_][]const u8{
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
    for (reserved) |it| {
        if (std.mem.eql(u8, it, public_name)) return true;
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
