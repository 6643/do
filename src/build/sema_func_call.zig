//! Sema func domain — call (extracted from sema_func).
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema_error = @import("sema_error.zig");
const type_util = @import("type_name.zig");
const sema_util = @import("sema_util.zig");
const sema_types = @import("sema_types.zig");
const sema_func_shared = @import("sema_func_shared.zig");
const CallShape = sema_types.CallShape;
const KnownBool = sema_types.KnownBool;
const DirectCallSite = sema_types.DirectCallSite;
const ReturnArityResolve = sema_types.ReturnArityResolve;
const callOpenParenIdx = sema_func_shared.callOpenParenIdx;
const collectCallShapesFromProgram = sema_func_shared.collectCallShapesFromProgram;
const findEnclosingFuncParamTypeName = sema_func_shared.findEnclosingFuncParamTypeName;
const findInlineFuncTypeInIsArg = sema_func_shared.findInlineFuncTypeInIsArg;
const findTopLevelNilInIsArg = sema_func_shared.findTopLevelNilInIsArg;
const isScalarAsTargetTypeName = sema_func_shared.isScalarAsTargetTypeName;

const callArityCompatibleWithFunc = sema_util.callArityCompatibleWithFunc;
const collectFuncShapes = sema_util.collectFuncShapes;
const findConstraintBlockStartBefore = sema_util.findConstraintBlockStartBefore;
const findLineEndIdx = sema_util.findLineEndIdx;
const findMatching = sema_util.findMatching;
const findNearestValueTypeName = sema_util.findNearestValueTypeName;
const findReturnTypeEnd = sema_util.findReturnTypeEnd;
const findTopLevelAssignEqOnLine = sema_util.findTopLevelAssignEqOnLine;
const findTopLevelComma = sema_util.findTopLevelComma;
const firstNonGap = sema_util.firstNonGap;
const freeCallArgShapes = sema_util.freeCallArgShapes;
const freeFuncShapes = sema_util.freeFuncShapes;
const funcParamTypeStart = sema_util.funcParamTypeStart;
const hasKnownFuncCandidate = sema_util.hasKnownFuncCandidate;
const isArrowAt = sema_util.isArrowAt;
const isFuncDeclStart = sema_util.isFuncDeclStart;
const isFuncTypeParam = sema_util.isFuncTypeParam;
const isHostImportDeclStart = sema_util.isHostImportDeclStart;
const isKeyword = sema_util.isKeyword;
const isLocalPayloadEnumCase = sema_util.isLocalPayloadEnumCase;
const isReturnArrowAt = sema_util.isReturnArrowAt;
const isStartDeclStart = sema_util.isStartDeclStart;
const isTopLevelCommaAny = sema_util.isTopLevelCommaAny;
const isTopLevelDeclHead = sema_util.isTopLevelDeclHead;
const isValidDeclaredTypeName = sema_util.isValidDeclaredTypeName;
const isValueLiteralToken = sema_util.isValueLiteralToken;
const markErrorAt = sema_util.markErrorAt;
const parseCallArgShapes = sema_util.parseCallArgShapes;
const publicFuncName = sema_util.publicFuncName;
const publicTypeName = sema_util.publicTypeName;
const tokEq = sema_util.tokEq;
const tokenNameAppearsInRange = sema_util.tokenNameAppearsInRange;
const typeConstraintIsFunctionType = sema_util.typeConstraintIsFunctionType;
const validateIsTypeAtom = sema_util.validateIsTypeAtom;
const validateIsTypeExpr = sema_util.validateIsTypeExpr;
const CallArgShape = sema_types.CallArgShape;
const FuncParamShape = sema_types.FuncParamShape;
const FuncShape = sema_types.FuncShape;
const FuncTypeShape = sema_types.FuncTypeShape;
const LambdaArgShape = sema_types.LambdaArgShape;

pub fn checkSingleValuePositions(
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



pub fn checkKnownConditionBoolSites(allocator: std.mem.Allocator, program: parser.Program, tokens: []const lexer.Token) !void {
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



pub fn checkLineStringRootPositions(program: parser.Program, tokens: []const lexer.Token) !void {
    for (program.expr_nodes) |node| {
        if (node.kind != .literal) continue;
        if (!isLineStringToken(tokens[node.start_tok])) continue;
        if (isLineStringRootExpr(program, node.start_tok)) continue;
        return markErrorAt(tokens, node.start_tok, error.UnsupportedExpr);
    }
}



pub fn isLineStringRootExpr(program: parser.Program, start_tok: usize) bool {
    for (program.value_exprs) |site| {
        if (site.context != .rhs) continue;
        if (site.root_expr_idx >= program.expr_nodes.len) continue;
        if (program.expr_nodes[site.root_expr_idx].start_tok == start_tok) return true;
    }
    return false;
}



pub fn isLineStringToken(tok: lexer.Token) bool {
    return tok.kind == .string and tok.lexeme.len >= 2 and tok.lexeme[0] == '\\' and tok.lexeme[1] == '\\';
}



pub fn checkIsTypeArgs(tokens: []const lexer.Token) !void {
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
        // Payload-enum case name as second arg: @is(m, Text)
        if (type_arg + 1 == close_paren and tokens[type_arg].kind == .ident and
            isValidDeclaredTypeName(tokens[type_arg].lexeme) and
            isLocalPayloadEnumCase(tokens, publicTypeName(tokens[type_arg].lexeme)))
        {
            continue;
        }
        if (validateIsTargetTypeExpr(tokens, type_arg, close_paren) != close_paren) {
            return markErrorAt(tokens, type_arg, error.InvalidNarrowing);
        }
    }
}



pub fn checkAsTypeArgs(tokens: []const lexer.Token) !void {
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



pub fn asTypeFirstArg(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    const type_arg = firstNonGap(tokens, start_idx, end_idx) orelse return null;
    if (validateScalarAsTargetType(tokens, type_arg, end_idx) != end_idx) return null;
    return type_arg;
}



pub fn validateScalarAsTargetType(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (start_idx + 1 != end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (!isScalarAsTargetTypeName(tokens[start_idx].lexeme)) return null;
    return end_idx;
}



pub fn validateIsTargetTypeExpr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    return validateIsTypeAtom(tokens, start_idx, end_idx);
}



pub fn checkGenericCallInference(
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
                has_direct_generic_candidate = has_direct_generic_candidate or
                    funcHasUninferredReturnTypeParam(tokens, func);
                continue;
            }

            has_direct_generic_candidate = true;
            if (genericCallInfersDirectTypeParams(tokens, funcs, func, call)) {
                has_inferred_generic_candidate = true;
            }
        }

        if (!has_direct_generic_candidate) continue;
        if (has_inferred_generic_candidate) continue;
        if (has_plain_candidate) continue;
        return markErrorAt(tokens, call.start_idx, error.NoMatchingCall);
    }
}



pub fn checkSpreadCallTargets(
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



pub fn callArgSpreadIndex(args: []const CallArgShape) ?usize {
    for (args, 0..) |arg, arg_idx| {
        if (arg == .spread) return arg_idx;
    }
    return null;
}



pub fn callArgSpreadTokenIdx(args: []const CallArgShape) ?usize {
    for (args) |arg| {
        if (arg == .spread) return arg.spread;
    }
    return null;
}



pub fn callSpreadCompatibleWithFunc(func: FuncShape, arg_count: usize, spread_idx: usize) bool {
    if (!callArityCompatibleWithFunc(func, arg_count)) return false;
    if (func.param_max != null) return false;
    return spread_idx >= func.param_min;
}



pub fn builtinSpreadCallAllowed(name: []const u8, spread_idx: usize) ?bool {
    if (isNumericCoreName(name)) return spread_idx >= 2;
    if (std.mem.eql(u8, name, "put")) return spread_idx == 1;
    if (isBuiltinCallName(name)) return false;
    return null;
}



pub fn isHostImportFuncName(tokens: []const lexer.Token, name: []const u8) bool {
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!isTopLevelDeclHead(tokens, i)) continue;
        if (tokens[i].kind != .ident) continue;
        if (!std.mem.eql(u8, publicFuncName(tokens[i].lexeme), name)) continue;
        if (isHostImportDeclStart(tokens, i)) return true;
    }
    return false;
}



pub fn isNumericCoreName(name: []const u8) bool {
    const names = [_][]const u8{ "add", "sub", "mul", "div", "rem", "min", "max" };
    for (names) |it| {
        if (std.mem.eql(u8, it, name)) return true;
    }
    return false;
}



pub fn isBuiltinCallName(name: []const u8) bool {
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



pub fn funcHasTypeConstraints(tokens: []const lexer.Token, func_start_idx: usize) bool {
    return findConstraintBlockStartBefore(tokens, func_start_idx) != null;
}



pub fn funcHasDirectTypeParamParam(tokens: []const lexer.Token, func: FuncShape) bool {
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



pub fn genericCallInfersDirectTypeParams(
    tokens: []const lexer.Token,
    funcs: []const FuncShape,
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
        if (!callHasKnownArgForDirectTypeParam(tokens, funcs, func, call, type_name)) return false;
    }
    return true;
}



pub fn funcHasUninferredReturnTypeParam(tokens: []const lexer.Token, func: FuncShape) bool {
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



pub fn funcParamSideCanBindTypeParam(tokens: []const lexer.Token, func: FuncShape, type_name: []const u8) bool {
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



pub fn funcParamTypeRangesContainDataTypeParam(tokens: []const lexer.Token, func: FuncShape) bool {
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



pub fn funcParamTypeRangesContainTypeParam(tokens: []const lexer.Token, func: FuncShape, type_name: []const u8) bool {
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



pub fn funcParamTypeRangeContainsDataTypeParam(
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



pub fn funcParamTypeRangeContainsTypeParam(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    type_name: []const u8,
) bool {
    const type_start = funcParamTypeStart(tokens, start_idx, end_idx) orelse return false;
    return tokenNameAppearsInRange(tokens, type_start, end_idx, type_name);
}



pub fn funcTypeShapeContainsTypeParam(shape: FuncTypeShape, type_name: []const u8) bool {
    for (shape.param_types) |param_type| {
        const name = param_type orelse continue;
        if (std.mem.eql(u8, name, type_name)) return true;
    }
    if (shape.return_type) |ret| {
        if (std.mem.eql(u8, ret, type_name)) return true;
    }
    return false;
}



pub fn typeConstraintFuncShapeContainsTypeParam(
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



pub fn genericCallHasRequiredLambdaReturnTypes(
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



pub fn hasPriorDirectTypeParam(func: FuncShape, before_param_idx: usize, type_name: []const u8) bool {
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



pub fn callHasKnownArgForDirectTypeParam(
    tokens: []const lexer.Token,
    funcs: []const FuncShape,
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
    if (callHasKnownCallbackArgForTypeParam(tokens, funcs, func, call, type_name)) return true;
    return false;
}



pub fn callHasKnownCallbackArgForTypeParam(
    tokens: []const lexer.Token,
    funcs: []const FuncShape,
    func: FuncShape,
    call: CallShape,
    type_name: []const u8,
) bool {
    for (func.param_shapes, 0..) |param, param_idx| {
        const constraint_name = switch (param) {
            .value => |value_type| value_type orelse continue,
            .variadic => |value_type| value_type orelse continue,
            .func => continue,
            .other => continue,
        };
        if (!typeConstraintIsFunctionType(tokens, func.start_idx, constraint_name)) continue;
        if (param_idx >= call.arg_shapes.len) return false;
        switch (call.arg_shapes[param_idx]) {
            .lambda => |lambda| {
                if (lambdaBindsTypeParamThroughConstraint(tokens, func.start_idx, constraint_name, type_name, lambda)) return true;
            },
            .ident => |name| {
                if (functionRefBindsTypeParamThroughConstraint(tokens, funcs, func.start_idx, constraint_name, type_name, name)) return true;
            },
            else => {},
        }
    }
    return false;
}



pub fn functionRefBindsTypeParamThroughConstraint(
    tokens: []const lexer.Token,
    funcs: []const FuncShape,
    func_start_idx: usize,
    constraint_name: []const u8,
    type_name: []const u8,
    func_ref_name: []const u8,
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

        for (funcs) |candidate| {
            if (!std.mem.eql(u8, candidate.name, func_ref_name)) continue;
            if (funcCandidateBindsTypeParamInConstraint(
                tokens,
                candidate,
                eq_idx,
                close_params,
                line_end,
                type_name,
            )) return true;
        }
        return false;
    }
    return false;
}



pub fn lambdaBindsTypeParamThroughConstraint(
    tokens: []const lexer.Token,
    func_start_idx: usize,
    constraint_name: []const u8,
    type_name: []const u8,
    lambda: LambdaArgShape,
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

        if (lambdaBindsTypeParamInConstraintParams(
            tokens,
            lambda,
            eq_idx,
            close_params,
            line_end,
            type_name,
        )) return true;
        return false;
    }
    return false;
}

fn paramShapeHasConcreteType(shape: FuncParamShape) bool {
    return switch (shape) {
        .value => |value_type| value_type != null,
        .variadic => |value_type| value_type != null,
        else => false,
    };
}

fn funcCandidateBindsTypeParamInConstraint(
    tokens: []const lexer.Token,
    candidate: FuncShape,
    eq_idx: usize,
    close_params: usize,
    line_end: usize,
    type_name: []const u8,
) bool {
    var seg_start = eq_idx + 2;
    var seg_idx: usize = 0;
    var seg = seg_start;
    while (seg <= close_params) : (seg += 1) {
        if (seg < close_params and !isTopLevelCommaAny(tokens, seg, eq_idx + 2, close_params)) continue;
        if (seg_start >= seg) {
            seg_start = seg + 1;
            continue;
        }
        if (seg_idx < candidate.param_shapes.len and
            tokenNameAppearsInRange(tokens, seg_start, seg, type_name) and
            paramShapeHasConcreteType(candidate.param_shapes[seg_idx]))
        {
            return true;
        }
        seg_idx += 1;
        seg_start = seg + 1;
    }
    if (!isReturnArrowAt(tokens, close_params + 1)) return false;
    if (candidate.return_type == null) return false;
    return tokenNameAppearsInRange(tokens, close_params + 3, line_end, type_name);
}

fn lambdaBindsTypeParamInConstraintParams(
    tokens: []const lexer.Token,
    lambda: LambdaArgShape,
    eq_idx: usize,
    close_params: usize,
    line_end: usize,
    type_name: []const u8,
) bool {
    var seg_start = eq_idx + 2;
    var seg_idx: usize = 0;
    var seg = seg_start;
    while (seg <= close_params) : (seg += 1) {
        if (seg < close_params and !isTopLevelCommaAny(tokens, seg, eq_idx + 2, close_params)) continue;
        if (seg_start >= seg) {
            seg_start = seg + 1;
            continue;
        }
        if (seg_idx < lambda.param_types.len and
            lambda.param_types[seg_idx] != null and
            tokenNameAppearsInRange(tokens, seg_start, seg, type_name))
        {
            return true;
        }
        seg_idx += 1;
        seg_start = seg + 1;
    }
    if (!isReturnArrowAt(tokens, close_params + 1)) return false;
    if (lambda.return_type == null) return false;
    return tokenNameAppearsInRange(tokens, close_params + 3, line_end, type_name);
}



pub fn hasKnownValueTypeBefore(tokens: []const lexer.Token, before_idx: usize, name: []const u8) bool {
    if (findNearestValueTypeName(tokens, before_idx, name) != null) return true;
    if (hasNearestValueTypeExpr(tokens, before_idx, name)) return true;
    return findEnclosingFuncParamTypeName(tokens, before_idx, name) != null;
}



pub fn hasNearestValueTypeExpr(tokens: []const lexer.Token, before_idx: usize, name: []const u8) bool {
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
        return validateIsTypeExpr(tokens, i + 1, eq_idx) == eq_idx;
    }
    return false;
}



pub fn typeConstraintFuncReturnHasTypeParam(
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



pub fn isCallHead(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    if (tokens[idx].kind != .ident) return false;
    if (idx > 0 and tokEq(tokens[idx - 1], "@") and tokens[idx - 1].line == tokens[idx].line) return false;
    if (isKeyword(tokens[idx].lexeme)) return false;
    return callOpenParenIdx(tokens, idx, tokens.len) != null;
}



pub fn isBuiltinIntrinsicCallHead(tokens: []const lexer.Token, idx: usize) bool {
    if (idx == 0 or idx + 1 >= tokens.len) return false;
    if (tokens[idx].kind != .ident) return false;
    if (!tokEq(tokens[idx - 1], "@") or tokens[idx - 1].line != tokens[idx].line) return false;
    if (!isBuiltinCallName(tokens[idx].lexeme)) return false;
    return tokEq(tokens[idx + 1], "(");
}



pub fn isFuncConstraintHead(tokens: []const lexer.Token, idx: usize) bool {
    if (idx == 0 or !tokEq(tokens[idx - 1], "#")) return false;
    return tokens[idx - 1].line == tokens[idx].line;
}



pub fn rootExprStartTok(program: parser.Program, root_idx: usize) usize {
    if (root_idx >= program.expr_nodes.len) return 0;
    const node = program.expr_nodes[root_idx];
    return switch (node.kind) {
        .paren => rootExprStartTok(program, node.data.child),
        else => node.start_tok,
    };
}



pub fn classifyKnownBool(
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



pub fn classifyLiteralBool(tokens: []const lexer.Token, tok_idx: usize) KnownBool {
    if (tok_idx >= tokens.len) return .unknown;
    if (tokEq(tokens[tok_idx], "true") or tokEq(tokens[tok_idx], "false")) return .yes;
    return .no;
}



pub fn classifyTypedIdentBool(tokens: []const lexer.Token, ident_tok_idx: usize) KnownBool {
    if (ident_tok_idx >= tokens.len) return .unknown;
    const name = tokens[ident_tok_idx].lexeme;
    const typed = findNearestTypedBinding(tokens, ident_tok_idx, name) orelse return .unknown;
    return if (typed) .yes else .no;
}



pub fn findNearestTypedBinding(tokens: []const lexer.Token, ident_tok_idx: usize, name: []const u8) ?bool {
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



pub fn typedBindingBool(tokens: []const lexer.Token, name_idx: usize) ?bool {
    if (name_idx + 2 >= tokens.len) return null;
    const line_end = findLineEndIdx(tokens, name_idx);
    if (line_end <= name_idx + 1) return null;

    const eq_idx = findTopLevelAssignEqOnLine(tokens, name_idx + 1, line_end) orelse return null;
    if (eq_idx == name_idx + 1) return inferBoolFromAssignmentRhs(tokens, name_idx, eq_idx + 1, line_end);
    return isBoolTypeSpec(tokens, name_idx + 1, eq_idx);
}



pub fn inferBoolFromAssignmentRhs(tokens: []const lexer.Token, name_idx: usize, rhs_start: usize, line_end: usize) ?bool {
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



pub fn findStructFieldBoolType(tokens: []const lexer.Token, type_name: []const u8, field_name: []const u8) ?bool {
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



pub fn findFieldBoolType(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, field_name: []const u8) ?bool {
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



pub fn isBoolTypeSpec(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    return end_idx == start_idx + 1 and tokEq(tokens[start_idx], "bool");
}



pub fn classifyCallBool(
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
            continue;
        }
        if (best_variadic_min == null or func.param_min > best_variadic_min.?) {
            best_variadic_min = func.param_min;
            best_variadic_count = 1;
            variadic_return_type = func.return_type;
            continue;
        }
        if (func.param_min == best_variadic_min.?) best_variadic_count += 1;
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



pub fn conditionCallArgsMatchFunc(
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



pub fn conditionCallArgValueType(tokens: []const lexer.Token, arg: CallArgShape, call_start: usize) ?[]const u8 {
    return switch (arg) {
        .ident => |name| findNearestValueTypeName(tokens, call_start, name),
        else => null,
    };
}



pub fn isBuiltinBoolCall(name: []const u8) bool {
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



pub fn findDirectCallAtRoot(program: parser.Program, root_idx: usize) ?DirectCallSite {
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



pub fn rootExprReturnArity(program: parser.Program, root_idx: usize) ReturnArityResolve {
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



pub fn resolveCallReturnArity(
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



pub fn valueExprAllowsArityAt(program: parser.Program, start_tok: usize, arity: usize) bool {
    for (program.value_exprs) |site| {
        if (site.expected_arity != arity) continue;
        if (site.context != .assign and site.context != .return_value) continue;
        if (!rootExprMatchesCallStart(program, site.root_expr_idx, start_tok)) continue;
        return true;
    }
    return false;
}



pub fn rootExprMatchesCallStart(program: parser.Program, root_idx: usize, start_tok: usize) bool {
    if (root_idx >= program.expr_nodes.len) return false;
    const node = program.expr_nodes[root_idx];
    return switch (node.kind) {
        .call => node.start_tok == start_tok,
        else => false,
    };
}



pub fn isArgCountCompatible(sig: parser.FuncSig, arg_count: usize) bool {
    if (arg_count < sig.param_min) return false;
    if (sig.param_max) |max_count| {
        return arg_count <= max_count;
    }
    return true;
}



