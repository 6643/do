//! Sema func shared helpers (multi-domain).
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema_error = @import("sema_error.zig");
const type_util = @import("type_name.zig");
const sema_util = @import("sema_util.zig");
const sema_types = @import("sema_types.zig");
const CallShape = sema_types.CallShape;
const ResolvedFuncTypeShape = sema_types.ResolvedFuncTypeShape;

const findConstraintBlockStartBefore = sema_util.findConstraintBlockStartBefore;
const findLineEndIdx = sema_util.findLineEndIdx;
const findMatching = sema_util.findMatching;
const findMatchingInRange = sema_util.findMatchingInRange;
const findTopLevelAssignEqOnLine = sema_util.findTopLevelAssignEqOnLine;
const freeFuncTypeParamNames = sema_util.freeFuncTypeParamNames;
const hasTypeConstraintName = sema_util.hasTypeConstraintName;
const isFuncDeclStart = sema_util.isFuncDeclStart;
const isFuncTypeRange = sema_util.isFuncTypeRange;
const isReturnArrowAt = sema_util.isReturnArrowAt;
const isTopLevelCommaAny = sema_util.isTopLevelCommaAny;
const lineStartIdx = sema_util.lineStartIdx;
const parseCallArgShapes = sema_util.parseCallArgShapes;
const parseTypeNameList = sema_util.parseTypeNameList;
const simpleTypeName = sema_util.simpleTypeName;
const tokEq = sema_util.tokEq;
const FuncParamShape = sema_types.FuncParamShape;
const FuncShape = sema_types.FuncShape;

pub fn isScalarAsTargetTypeName(name: []const u8) bool {
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



pub fn findInlineFuncTypeInIsArg(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
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



pub fn findTopLevelNilInIsArg(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
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



pub fn collectCallShapesFromProgram(
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



pub fn resolveFuncParamTypeShape(
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



pub fn freeResolvedFuncTypeShape(allocator: std.mem.Allocator, resolved: ?ResolvedFuncTypeShape) void {
    const item = resolved orelse return;
    if (!item.owned) return;
    freeFuncTypeParamNames(allocator, item.shape.param_types);
}



pub fn parseConcreteFuncTypeConstraintShape(
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



pub fn typeConstraintIsConcreteFunctionType(
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



pub fn funcTypeConstraintUsesPriorTypeParam(
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



pub fn callOpenParenIdx(tokens: []const lexer.Token, name_idx: usize, limit_idx: usize) ?usize {
    if (name_idx + 1 >= limit_idx) return null;
    if (tokEq(tokens[name_idx + 1], "(")) return name_idx + 1;
    if (!tokEq(tokens[name_idx + 1], "<")) return null;

    const close_angle = findMatchingInRange(tokens, name_idx + 1, "<", ">", limit_idx) catch return null;
    if (close_angle + 1 >= limit_idx or !tokEq(tokens[close_angle + 1], "(")) return null;
    return close_angle + 1;
}



pub fn findEnclosingFuncParamTypeName(tokens: []const lexer.Token, before_idx: usize, name: []const u8) ?[]const u8 {
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



pub fn findFuncParamTypeNameBeforeBody(
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



pub fn findParamTypeName(
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



