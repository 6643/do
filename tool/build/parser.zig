const std = @import("std");
const lexer = @import("lexer.zig");

pub const ConditionContext = enum {
    if_cond,
    if_bind_rhs,
    loop_cond,
};

pub const FuncBodyKind = enum {
    block,
    arrow,
};

pub const FuncSig = struct {
    name: []const u8,
    param_min: usize,
    param_max: ?usize, // null => variadic
    return_arity: usize,
    returns_bool: bool,
    line: usize,
};

pub const FuncCallRef = struct {
    func_name: []const u8,
    arg_count: usize,
};

pub const ExprKind = enum {
    ident,
    literal,
    call,
    do_call,
    lambda,
    inferred_agg_lit,
    struct_lit,
    paren,
};

pub const ExprNodeData = union(enum) {
    none: void,
    call: FuncCallRef,
    child: usize,
};

pub const ExprNode = struct {
    kind: ExprKind,
    start_tok: usize,
    end_tok: usize, // exclusive
    data: ExprNodeData,
};

pub const ConditionExpr = struct {
    root_expr_idx: usize,
    context: ConditionContext,
    line: usize,
};

pub const Program = struct {
    source_len: usize,
    token_count: usize,
    top_level_count: usize,
    func_sigs: []FuncSig,
    condition_exprs: []ConditionExpr,
    expr_nodes: []ExprNode,

    pub fn deinit(self: *Program, allocator: std.mem.Allocator) void {
        allocator.free(self.func_sigs);
        allocator.free(self.condition_exprs);
        allocator.free(self.expr_nodes);
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

const FuncParseResult = struct {
    next_idx: usize,
    sig: FuncSig,
    body_kind: FuncBodyKind,
    body_start_idx: usize,
    body_end_idx: usize,
};

const ReturnSpecParse = struct {
    next_idx: usize,
    return_arity: usize,
    returns_bool: bool,
    body_kind: FuncBodyKind,
    body_start_idx: usize,
    body_end_idx: usize,
};

const ReturnContext = struct {
    expected_arity: usize,
    allow_empty_nil: bool,
};

const BreakContinueParse = struct {
    next_idx: usize,
    label: ?usize,
};

const TestReturnContext = ReturnContext{
    .expected_arity = 0,
    .allow_empty_nil = true,
};

const ParamParse = struct {
    param_min: usize,
    param_max: ?usize,
};

const ExprParse = struct {
    next_idx: usize,
    node_idx: usize,
};

const ExprListParse = struct {
    count: usize,
    first_node_idx: usize,
};

const CallExprParse = struct {
    next_idx: usize,
    arg_count: usize,
};

const IfCondParse = struct {
    context: ConditionContext,
    root_expr_idx: usize,
    next_idx: usize,
};

pub fn parseProgram(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    source_len: usize,
) !Program {
    last_error_site = null;
    if (source_len == 0) return error.EmptySource;
    if (tokens.len == 0) return error.EmptyProgram;

    var func_sigs_list = try std.ArrayList(FuncSig).initCapacity(allocator, 0);
    defer func_sigs_list.deinit(allocator);

    var cond_exprs_list = try std.ArrayList(ConditionExpr).initCapacity(allocator, 0);
    defer cond_exprs_list.deinit(allocator);

    var expr_nodes_list = try std.ArrayList(ExprNode).initCapacity(allocator, 0);
    defer expr_nodes_list.deinit(allocator);

    const top_level = try countTopLevel(tokens);

    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) {
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            i += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            i += 1;
            continue;
        }
        if (depth_brace != 0) {
            i += 1;
            continue;
        }
        if (isModernImportAssign(tokens, i)) {
            i = skipModernImportLine(tokens, i);
            continue;
        }
        if (isTestDeclStart(tokens, i)) {
            i = try parseTopLevelTestDecl(
                allocator,
                &cond_exprs_list,
                &expr_nodes_list,
                tokens,
                i,
            );
            continue;
        }
        if (!isFuncDeclStart(tokens, i)) {
            i += 1;
            continue;
        }
        i = try parseTopLevelFuncDecl(
            allocator,
            &func_sigs_list,
            &cond_exprs_list,
            &expr_nodes_list,
            tokens,
            i,
        );
    }

    const func_sigs = try func_sigs_list.toOwnedSlice(allocator);
    errdefer allocator.free(func_sigs);
    const condition_exprs = try cond_exprs_list.toOwnedSlice(allocator);
    errdefer allocator.free(condition_exprs);
    const expr_nodes = try expr_nodes_list.toOwnedSlice(allocator);
    errdefer allocator.free(expr_nodes);

    return .{
        .source_len = source_len,
        .token_count = tokens.len,
        .top_level_count = top_level,
        .func_sigs = func_sigs,
        .condition_exprs = condition_exprs,
        .expr_nodes = expr_nodes,
    };
}

fn countTopLevel(tokens: []const lexer.Token) !usize {
    var top_level: usize = 0;
    var depth_brace: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (depth_brace == 0 and isTopLevelDeclHead(tokens, i) and isModernImportAssign(tokens, i)) {
            top_level += 1;
            i = findLineEnd(tokens, i, tokens.len) - 1;
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
        if (depth_brace != 0) continue;

        const t = tokens[i];
        if (t.kind != .ident) continue;
        if (std.mem.eql(u8, t.lexeme, "test")) {
            top_level += 1;
            continue;
        }
        if (i + 1 < tokens.len and tokEq(tokens[i + 1], "(") and !isKeyword(t.lexeme)) {
            top_level += 1;
            continue;
        }
        if (i + 1 < tokens.len and tokEq(tokens[i + 1], "{")) {
            top_level += 1;
        }
    }
    return top_level;
}

fn isTestDeclStart(tokens: []const lexer.Token, i: usize) bool {
    if (i >= tokens.len) return false;
    if (tokens[i].kind != .ident) return false;
    if (!isTopLevelDeclHead(tokens, i)) return false;
    return tokEq(tokens[i], "test");
}

fn isFuncDeclStart(tokens: []const lexer.Token, i: usize) bool {
    if (i + 1 >= tokens.len) return false;
    if (tokens[i].kind != .ident) return false;
    if (isKeyword(tokens[i].lexeme)) return false;
    if (!isTopLevelDeclHead(tokens, i)) return false;
    return tokEq(tokens[i + 1], "(");
}

fn isModernImportAssign(tokens: []const lexer.Token, idx: usize) bool {
    if (idx >= tokens.len or tokens[idx].kind != .ident) return false;
    if (!isTopLevelDeclHead(tokens, idx)) return false;
    const eq_idx = topLevelLineAssignIdx(tokens, idx) orelse return false;
    return eq_idx + 1 < tokens.len and tokEq(tokens[eq_idx + 1], "@");
}

fn skipModernImportLine(tokens: []const lexer.Token, idx: usize) usize {
    return findLineEnd(tokens, idx, tokens.len);
}

fn topLevelLineAssignIdx(tokens: []const lexer.Token, line_start: usize) ?usize {
    const line_end = findLineEnd(tokens, line_start, tokens.len);
    return findTopLevelAssignEq(tokens, line_start + 1, line_end);
}

fn isTopLevelDeclHead(tokens: []const lexer.Token, idx: usize) bool {
    if (idx == 0) return true;
    return tokens[idx - 1].line != tokens[idx].line;
}

fn parseTopLevelFuncDecl(
    allocator: std.mem.Allocator,
    out_func_sigs: *std.ArrayList(FuncSig),
    out_conds: *std.ArrayList(ConditionExpr),
    out_nodes: *std.ArrayList(ExprNode),
    tokens: []const lexer.Token,
    start_idx: usize,
) !usize {
    const parsed = try parseFunctionDecl(tokens, start_idx);
    try out_func_sigs.append(allocator, parsed.sig);

    const return_ctx: ReturnContext = .{
        .expected_arity = parsed.sig.return_arity,
        .allow_empty_nil = parsed.sig.return_arity == 0,
    };
    if (parsed.body_kind == .block) {
        try collectConditionExprs(
            allocator,
            out_conds,
            out_nodes,
            tokens,
            parsed.body_start_idx,
            parsed.body_end_idx,
            return_ctx,
        );
    } else {
        try validateArrowBodyReturns(
            allocator,
            out_nodes,
            tokens,
            parsed.body_start_idx,
            parsed.body_end_idx,
            return_ctx,
        );
    }
    return parsed.next_idx;
}

fn parseTopLevelTestDecl(
    allocator: std.mem.Allocator,
    out_conds: *std.ArrayList(ConditionExpr),
    out_nodes: *std.ArrayList(ExprNode),
    tokens: []const lexer.Token,
    start_idx: usize,
) !usize {
    if (start_idx + 2 >= tokens.len) return markErrorAt(tokens, start_idx, error.InvalidTestDecl);
    if (tokens[start_idx + 1].kind != .string) return markErrorAt(tokens, start_idx + 1, error.InvalidTestDecl);
    if (!tokEq(tokens[start_idx + 2], "{")) return markErrorAt(tokens, start_idx + 2, error.InvalidTestDecl);

    const close_brace = findMatching(tokens, start_idx + 2, "{", "}") catch
        return markErrorAt(tokens, start_idx + 2, error.InvalidTestDecl);

    try collectConditionExprs(
        allocator,
        out_conds,
        out_nodes,
        tokens,
        start_idx + 2,
        close_brace,
        TestReturnContext,
    );
    return close_brace + 1;
}

fn parseFunctionDecl(tokens: []const lexer.Token, start_idx: usize) !FuncParseResult {
    const name_tok = tokens[start_idx];
    const open_paren_idx = start_idx + 1;
    const close_paren_idx = try findMatching(tokens, open_paren_idx, "(", ")");

    const params = try parseParamRange(tokens, open_paren_idx + 1, close_paren_idx);
    const ret = try parseReturnSpec(tokens, close_paren_idx + 1);

    return .{
        .next_idx = ret.next_idx,
        .sig = .{
            .name = name_tok.lexeme,
            .param_min = params.param_min,
            .param_max = params.param_max,
            .return_arity = ret.return_arity,
            .returns_bool = ret.returns_bool,
            .line = name_tok.line,
        },
        .body_kind = ret.body_kind,
        .body_start_idx = ret.body_start_idx,
        .body_end_idx = ret.body_end_idx,
    };
}

fn parseParamRange(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) !ParamParse {
    if (start_idx >= end_idx) return .{ .param_min = 0, .param_max = 0 };

    var min_count: usize = 0;
    var has_variadic = false;
    var seg_start = start_idx;
    var depth_angle: usize = 0;
    var depth_paren: usize = 0;

    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        const t = tokens[i];
        if (tokEq(t, "<")) {
            depth_angle += 1;
            continue;
        }
        if (tokEq(t, ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (tokEq(t, "(")) {
            depth_paren += 1;
            continue;
        }
        if (tokEq(t, ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (!tokEq(t, ",") or depth_angle != 0 or depth_paren != 0) continue;

        if (seg_start < i) {
            if (segmentContains(tokens, seg_start, i, "...")) {
                has_variadic = true;
            } else {
                min_count += 1;
            }
        }
        seg_start = i + 1;
    }

    if (seg_start < end_idx) {
        if (segmentContains(tokens, seg_start, end_idx, "...")) {
            has_variadic = true;
        } else {
            min_count += 1;
        }
    }

    return .{
        .param_min = min_count,
        .param_max = if (has_variadic) null else min_count,
    };
}

fn parseReturnSpec(tokens: []const lexer.Token, start_idx: usize) !ReturnSpecParse {
    if (start_idx >= tokens.len) return error.UnterminatedFuncDecl;

    if (tokEq(tokens[start_idx], "{")) {
        const close_brace = try findMatching(tokens, start_idx, "{", "}");
        return .{
            .next_idx = close_brace + 1,
            .return_arity = 0,
            .returns_bool = false,
            .body_kind = .block,
            .body_start_idx = start_idx,
            .body_end_idx = close_brace,
        };
    }
    if (isArrowAt(tokens, start_idx)) {
        const arrow_end = findArrowEnd(tokens, start_idx + 2);
        return .{
            .next_idx = arrow_end,
            .return_arity = 0,
            .returns_bool = false,
            .body_kind = .arrow,
            .body_start_idx = start_idx + 2,
            .body_end_idx = arrow_end,
        };
    }

    if (start_idx + 1 <= tokens.len and tokEq(tokens[start_idx], "nil")) {
        if (start_idx + 1 >= tokens.len) {
            return .{
                .next_idx = start_idx + 1,
                .return_arity = 0,
                .returns_bool = false,
                .body_kind = .arrow,
                .body_start_idx = start_idx + 1,
                .body_end_idx = start_idx + 1,
            };
        }
        if (tokEq(tokens[start_idx + 1], "{")) {
            const close_brace = try findMatching(tokens, start_idx + 1, "{", "}");
            return .{
                .next_idx = close_brace + 1,
                .return_arity = 0,
                .returns_bool = false,
                .body_kind = .block,
                .body_start_idx = start_idx + 1,
                .body_end_idx = close_brace,
            };
        }
        if (isArrowAt(tokens, start_idx + 1)) {
            const arrow_end = findArrowEnd(tokens, start_idx + 3);
            return .{
                .next_idx = arrow_end,
                .return_arity = 0,
                .returns_bool = false,
                .body_kind = .arrow,
                .body_start_idx = start_idx + 3,
                .body_end_idx = arrow_end,
            };
        }
    }

    var arity: usize = 0;
    var returns_bool = false;
    var i = start_idx;
    while (i < tokens.len) {
        const seg_start = i;
        var depth_angle: usize = 0;
        var depth_paren: usize = 0;

        while (i < tokens.len) : (i += 1) {
            const t = tokens[i];
            if (tokEq(t, "<")) {
                depth_angle += 1;
                continue;
            }
            if (tokEq(t, ">")) {
                if (depth_angle > 0) depth_angle -= 1;
                continue;
            }
            if (tokEq(t, "(")) {
                depth_paren += 1;
                continue;
            }
            if (tokEq(t, ")")) {
                if (depth_paren > 0) depth_paren -= 1;
                continue;
            }
            if (depth_angle == 0 and depth_paren == 0 and tokEq(t, ",")) break;
            if (depth_angle == 0 and depth_paren == 0 and (tokEq(t, "{") or isArrowAt(tokens, i))) break;
        }

        if (seg_start == i) return error.InvalidReturnSpec;
        if (arity == 0) {
            returns_bool = isBoolTypeSegment(tokens, seg_start, i);
        } else {
            returns_bool = false;
        }
        arity += 1;

        if (i >= tokens.len) return error.UnterminatedFuncDecl;
        if (tokEq(tokens[i], ",")) {
            i += 1;
            continue;
        }
        if (tokEq(tokens[i], "{")) {
            const close_brace = try findMatching(tokens, i, "{", "}");
            return .{
                .next_idx = close_brace + 1,
                .return_arity = arity,
                .returns_bool = arity == 1 and returns_bool,
                .body_kind = .block,
                .body_start_idx = i,
                .body_end_idx = close_brace,
            };
        }
        if (isArrowAt(tokens, i)) {
            const arrow_end = findArrowEnd(tokens, i + 2);
            return .{
                .next_idx = arrow_end,
                .return_arity = arity,
                .returns_bool = arity == 1 and returns_bool,
                .body_kind = .arrow,
                .body_start_idx = i + 2,
                .body_end_idx = arrow_end,
            };
        }
    }

    return error.UnterminatedFuncDecl;
}

fn isBoolTypeSegment(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    return end_idx == start_idx + 1 and tokEq(tokens[start_idx], "bool");
}

fn findArrowEnd(tokens: []const lexer.Token, start_idx: usize) usize {
    if (start_idx >= tokens.len) return start_idx;
    const line = tokens[start_idx].line;
    var i = start_idx;
    while (i < tokens.len and tokens[i].line == line) : (i += 1) {}
    return i;
}

fn collectConditionExprs(
    allocator: std.mem.Allocator,
    out_conds: *std.ArrayList(ConditionExpr),
    out_nodes: *std.ArrayList(ExprNode),
    tokens: []const lexer.Token,
    body_open_idx: usize,
    body_close_idx: usize,
    return_ctx: ReturnContext,
) !void {
    var i = body_open_idx + 1;
    while (i < body_close_idx) {
        i = try parseBodyStmt(allocator, out_conds, out_nodes, tokens, i, body_close_idx, return_ctx);
    }
}

fn parseBodyStmt(
    allocator: std.mem.Allocator,
    out_conds: *std.ArrayList(ConditionExpr),
    out_nodes: *std.ArrayList(ExprNode),
    tokens: []const lexer.Token,
    stmt_idx: usize,
    limit_idx: usize,
    return_ctx: ReturnContext,
) !usize {
    if (stmt_idx >= limit_idx) return stmt_idx + 1;
    if (isLineStringToken(tokens[stmt_idx])) {
        return markErrorAt(tokens, stmt_idx, error.UnsupportedExpr);
    }
    if (tokens[stmt_idx].kind == .ident and tokens[stmt_idx].lexeme.len > 0 and tokens[stmt_idx].lexeme[0] == '.') {
        const line_end = findLineEnd(tokens, stmt_idx, limit_idx);
        if (stmt_idx + 1 < line_end and tokEq(tokens[stmt_idx + 1], "=")) {
            return markErrorAt(tokens, stmt_idx, error.PrivateIdentCannotBeLValue);
        }
    }
    if (tokEq(tokens[stmt_idx], "if")) {
        return parseIfStmt(allocator, out_conds, out_nodes, tokens, stmt_idx, limit_idx);
    }
    if (tokEq(tokens[stmt_idx], "loop")) {
        return parseLoopStmt(allocator, out_nodes, tokens, stmt_idx, limit_idx);
    }
    if (tokEq(tokens[stmt_idx], "break") or tokEq(tokens[stmt_idx], "continue")) {
        return parseBreakContinueStmt(tokens, stmt_idx, limit_idx);
    }
    if (tokEq(tokens[stmt_idx], "return")) {
        return parseReturnStmt(allocator, out_nodes, tokens, stmt_idx, limit_idx, return_ctx);
    }
    if (tokEq(tokens[stmt_idx], "=")) {
        return parseAssignStmt(allocator, out_nodes, tokens, stmt_idx, limit_idx);
    }
    return stmt_idx + 1;
}

fn parseIfStmt(
    allocator: std.mem.Allocator,
    out_conds: *std.ArrayList(ConditionExpr),
    out_nodes: *std.ArrayList(ExprNode),
    tokens: []const lexer.Token,
    if_idx: usize,
    limit_idx: usize,
) !usize {
    try maybeRecordIfConditionExpr(allocator, out_conds, out_nodes, tokens, if_idx, limit_idx);
    return if_idx + 1;
}

fn isLineStringToken(tok: lexer.Token) bool {
    return tok.kind == .string and tok.lexeme.len >= 2 and tok.lexeme[0] == '\\' and tok.lexeme[1] == '\\';
}

fn parseLoopStmt(
    allocator: std.mem.Allocator,
    out_nodes: *std.ArrayList(ExprNode),
    tokens: []const lexer.Token,
    loop_idx: usize,
    limit_idx: usize,
) !usize {
    const header_start = loop_idx + 1;
    if (header_start >= limit_idx) return markErrorAt(tokens, loop_idx, error.InvalidLoopHeader);

    if (tokEq(tokens[header_start], "{")) return header_start + 1; // loop { ... }

    if (try parseLoopBindHeader(
        allocator,
        out_nodes,
        tokens,
        header_start,
        limit_idx,
    )) |open_brace_idx| {
        return open_brace_idx + 1; // loop <bind> = <expr> { ... }
    }

    return markErrorAt(tokens, header_start, error.InvalidLoopHeader);
}

fn parseBreakContinueStmt(tokens: []const lexer.Token, stmt_idx: usize, limit_idx: usize) !usize {
    const parsed = try parseBreakContinueTail(tokens, stmt_idx, limit_idx);
    return parsed.next_idx;
}

fn parseBreakContinueTail(tokens: []const lexer.Token, stmt_idx: usize, limit_idx: usize) !BreakContinueParse {
    const line_end = findLineEnd(tokens, stmt_idx, limit_idx);
    var next_idx = stmt_idx + 1;
    var label: ?usize = null;

    if (next_idx < line_end and tokEq(tokens[next_idx], "#")) {
        if (next_idx + 1 >= line_end) return markErrorAt(tokens, next_idx, error.InvalidLoopHeader);
        if (tokens[next_idx + 1].kind != .ident) return markErrorAt(tokens, next_idx + 1, error.InvalidLoopHeader);
        label = next_idx + 1;
        next_idx += 2;
    }

    if (next_idx < line_end) {
        return markErrorAt(tokens, next_idx, error.InvalidLoopHeader);
    }
    return .{ .next_idx = line_end, .label = label };
}

fn validateArrowBodyReturns(
    allocator: std.mem.Allocator,
    out_nodes: *std.ArrayList(ExprNode),
    tokens: []const lexer.Token,
    body_start_idx: usize,
    body_end_idx: usize,
    return_ctx: ReturnContext,
) !void {
    if (body_start_idx >= body_end_idx) return;

    const expr = try parseExpr(allocator, out_nodes, tokens, body_start_idx, body_end_idx);
    if (expr.next_idx != body_end_idx) return markErrorAt(tokens, expr.next_idx, error.InvalidReturnStmt);
    if (return_ctx.expected_arity == 0 and return_ctx.allow_empty_nil) {
        if (expr.node_idx < out_nodes.items.len) {
            const node = out_nodes.items[expr.node_idx];
            if (node.kind == .literal and tokEq(tokens[node.start_tok], "nil")) return;
        }
    }
    if (return_ctx.expected_arity != 1) return markErrorAt(tokens, body_start_idx, error.InvalidReturnStmt);
}

fn parseReturnStmt(
    allocator: std.mem.Allocator,
    out_nodes: *std.ArrayList(ExprNode),
    tokens: []const lexer.Token,
    return_idx: usize,
    limit_idx: usize,
    return_ctx: ReturnContext,
) !usize {
    const line_end = findLineEnd(tokens, return_idx, limit_idx);
    if (line_end <= return_idx) return markErrorAt(tokens, return_idx, error.InvalidReturnStmt);

    const tail_start = return_idx + 1;
    if (tail_start >= line_end) {
        if (return_ctx.allow_empty_nil) return line_end;
        return markErrorAt(tokens, return_idx, error.InvalidReturnStmt);
    }

    const tail_end = findAssignRhsEnd(tokens, tail_start, limit_idx);
    const exprs = try parseReturnExprList(allocator, out_nodes, tokens, tail_start, tail_end);
    if (return_ctx.expected_arity == 0) {
        if (return_ctx.allow_empty_nil and exprs.count == 1 and exprs.first_node_idx < out_nodes.items.len) {
            const node = out_nodes.items[exprs.first_node_idx];
            if (node.kind == .literal and tokEq(tokens[node.start_tok], "nil")) return line_end;
        }
        return markErrorAt(tokens, tail_start, error.InvalidReturnStmt);
    }
    if (return_ctx.expected_arity != exprs.count) return markErrorAt(tokens, tail_start, error.InvalidReturnStmt);
    return tail_end;
}

fn parseReturnExprList(
    allocator: std.mem.Allocator,
    out_nodes: *std.ArrayList(ExprNode),
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) !ExprListParse {
    var count: usize = 0;
    var first_node_idx: usize = 0;
    var i = start_idx;
    while (i < end_idx) {
        const expr = try parseExpr(allocator, out_nodes, tokens, i, end_idx);
        if (count == 0) first_node_idx = expr.node_idx;
        count += 1;
        i = expr.next_idx;
        if (i >= end_idx) break;
        if (!tokEq(tokens[i], ",")) return markErrorAt(tokens, i, error.InvalidReturnStmt);
        i += 1;
        if (i >= end_idx) return markErrorAt(tokens, i - 1, error.InvalidReturnStmt);
    }
    return .{ .count = count, .first_node_idx = first_node_idx };
}

fn parseLoopBindHeader(
    allocator: std.mem.Allocator,
    out_nodes: *std.ArrayList(ExprNode),
    tokens: []const lexer.Token,
    header_start: usize,
    limit_idx: usize,
) !?usize {
    const bind_idx = findLoopBindAssign(tokens, header_start, limit_idx) orelse return null;
    try validateLoopBindLhs(tokens, header_start, bind_idx);

    const rhs_start = bind_idx + 1;
    if (rhs_start >= limit_idx) return markErrorAt(tokens, bind_idx, error.InvalidLoopHeader);

    const rhs = parseExpr(allocator, out_nodes, tokens, rhs_start, limit_idx) catch
        return markErrorAt(tokens, rhs_start, error.InvalidLoopHeader);
    if (rhs.next_idx >= limit_idx) return markErrorAt(tokens, rhs.next_idx, error.InvalidLoopHeader);
    if (!tokEq(tokens[rhs.next_idx], "{")) return markErrorAt(tokens, rhs.next_idx, error.InvalidLoopHeader);
    return rhs.next_idx;
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
        if (tokEq(tokens[i], "{")) {
            if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0) break;
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

    if (start_idx + 1 == bind_idx) return;
    if (start_idx + 3 != bind_idx) return markErrorAt(tokens, start_idx + 1, error.InvalidLoopHeader);
    if (!tokEq(tokens[start_idx + 1], ",")) return markErrorAt(tokens, start_idx + 1, error.InvalidLoopHeader);
    if (tokens[start_idx + 2].kind != .ident) return markErrorAt(tokens, start_idx + 2, error.InvalidLoopHeader);
    if (isKeyword(tokens[start_idx + 2].lexeme)) return markErrorAt(tokens, start_idx + 2, error.InvalidLoopHeader);
}

fn validateLoopBindRhsExpr(
    allocator: std.mem.Allocator,
    out_nodes: *std.ArrayList(ExprNode),
    tokens: []const lexer.Token,
    rhs_start: usize,
    rhs_end: usize,
) !void {
    if (rhs_start >= rhs_end) return markErrorAt(tokens, rhs_start, error.InvalidLoopHeader);
    const parsed = parseExpr(allocator, out_nodes, tokens, rhs_start, rhs_end) catch
        return markErrorAt(tokens, rhs_start, error.InvalidLoopHeader);
    if (parsed.next_idx != rhs_end) return markErrorAt(tokens, parsed.next_idx, error.InvalidLoopHeader);
}

fn parseAssignStmt(
    allocator: std.mem.Allocator,
    out_nodes: *std.ArrayList(ExprNode),
    tokens: []const lexer.Token,
    eq_idx: usize,
    limit_idx: usize,
) !usize {
    if (isNonAssignEqual(tokens, eq_idx)) return eq_idx + 1;
    const rhs_start = eq_idx + 1;
    if (rhs_start >= limit_idx) return markErrorAt(tokens, eq_idx, error.InvalidAssignExpr);

    const rhs_end = findAssignRhsEnd(tokens, rhs_start, limit_idx);
    if (rhs_start >= rhs_end) return markErrorAt(tokens, eq_idx, error.InvalidAssignExpr);

    const parsed = try parseExpr(allocator, out_nodes, tokens, rhs_start, rhs_end);
    if (parsed.next_idx != rhs_end) return markErrorAt(tokens, parsed.next_idx, error.InvalidAssignExpr);
    return rhs_end;
}

fn findAssignRhsEnd(tokens: []const lexer.Token, start_idx: usize, limit_idx: usize) usize {
    if (start_idx >= limit_idx) return start_idx;

    const start_line = tokens[start_idx].line;
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var i = start_idx;

    while (i < limit_idx) : (i += 1) {
        if (tokens[i].line != start_line and depth_paren == 0 and depth_brace == 0) break;

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
        if (!tokEq(tokens[i], "}")) continue;

        if (depth_brace == 0 and depth_paren == 0) break;
        if (depth_brace > 0) depth_brace -= 1;
    }
    return i;
}

fn maybeRecordIfConditionExpr(
    allocator: std.mem.Allocator,
    out_conds: *std.ArrayList(ConditionExpr),
    out_nodes: *std.ArrayList(ExprNode),
    tokens: []const lexer.Token,
    if_idx: usize,
    limit_idx: usize,
) !void {
    if (if_idx + 1 >= limit_idx) return;
    const parsed = try parseIfHeaderCondition(allocator, out_nodes, tokens, if_idx + 1, limit_idx);
    try validateIfHeaderTail(allocator, out_nodes, tokens, parsed.next_idx, limit_idx);

    try out_conds.append(allocator, .{
        .root_expr_idx = parsed.root_expr_idx,
        .context = parsed.context,
        .line = tokens[if_idx].line,
    });
}

fn parseIfHeaderCondition(
    allocator: std.mem.Allocator,
    out_nodes: *std.ArrayList(ExprNode),
    tokens: []const lexer.Token,
    start_idx: usize,
    limit_idx: usize,
) anyerror!IfCondParse {
    if (start_idx >= limit_idx) return markErrorAt(tokens, start_idx, error.InvalidIfHeader);

    const pattern_end = try parseIfTypePattern(tokens, start_idx, limit_idx);
    if (pattern_end) |end_idx| {
        if (end_idx + 1 < limit_idx and tokEq(tokens[end_idx], ":") and tokEq(tokens[end_idx + 1], "=")) {
            const rhs = try parseExpr(allocator, out_nodes, tokens, end_idx + 2, limit_idx);
            return .{
                .context = .if_bind_rhs,
                .root_expr_idx = rhs.node_idx,
                .next_idx = rhs.next_idx,
            };
        }
    }

    const cond = try parseExpr(allocator, out_nodes, tokens, start_idx, limit_idx);
    return .{
        .context = .if_cond,
        .root_expr_idx = cond.node_idx,
        .next_idx = cond.next_idx,
    };
}

fn validateIfHeaderTail(
    allocator: std.mem.Allocator,
    out_nodes: *std.ArrayList(ExprNode),
    tokens: []const lexer.Token,
    next_idx: usize,
    limit_idx: usize,
) !void {
    if (next_idx >= limit_idx) return markErrorAt(tokens, next_idx, error.InvalidIfHeader);
    if (tokEq(tokens[next_idx], "{")) return;
    if (next_idx + 1 < limit_idx and tokEq(tokens[next_idx], ":") and tokEq(tokens[next_idx + 1], "=")) return;

    const line_end = findLineEnd(tokens, next_idx, limit_idx);
    if (line_end <= next_idx) return markErrorAt(tokens, next_idx, error.InvalidIfHeader);
    if (isOneLineIfStmtKeyword(tokens[next_idx])) return;

    const stmt = parseExpr(allocator, out_nodes, tokens, next_idx, line_end) catch
        return markErrorAt(tokens, next_idx, error.InvalidIfHeader);
    if (stmt.next_idx == line_end) return;
    if (tokEq(tokens[stmt.next_idx], "{")) return markErrorAt(tokens, next_idx, error.InvalidIfHeader);
    return markErrorAt(tokens, stmt.next_idx, error.InvalidIfHeader);
}

fn findLineEnd(tokens: []const lexer.Token, start_idx: usize, limit_idx: usize) usize {
    if (start_idx >= limit_idx) return start_idx;
    const line = tokens[start_idx].line;
    var i = start_idx;
    while (i < limit_idx and tokens[i].line == line) : (i += 1) {}
    return i;
}

fn isOneLineIfStmtKeyword(tok: lexer.Token) bool {
    if (tok.kind != .ident) return false;
    if (tokEq(tok, "return")) return true;
    if (tokEq(tok, "defer")) return true;
    if (tokEq(tok, "break")) return true;
    if (tokEq(tok, "continue")) return true;
    return false;
}

fn findTopLevelAssignEq(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
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
        if (depth_paren != 0 or depth_brace != 0) continue;
        if (!tokEq(tokens[i], "=")) continue;
        if (isNonAssignEqual(tokens, i)) continue;
        return i;
    }
    return null;
}

fn parseIfTypePattern(tokens: []const lexer.Token, start_idx: usize, limit_idx: usize) anyerror!?usize {
    if (start_idx + 1 >= limit_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (!isTypeName(tokens[start_idx].lexeme)) return null;

    if (tokEq(tokens[start_idx + 1], "(")) {
        const close_paren = try findMatchingInRange(tokens, start_idx + 1, "(", ")", limit_idx);
        return close_paren + 1;
    }
    if (tokEq(tokens[start_idx + 1], "{")) {
        const close_brace = try findMatchingInRange(tokens, start_idx + 1, "{", "}", limit_idx);
        return close_brace + 1;
    }
    return null;
}

fn parseExpr(
    allocator: std.mem.Allocator,
    out_nodes: *std.ArrayList(ExprNode),
    tokens: []const lexer.Token,
    start_idx: usize,
    limit_idx: usize,
) anyerror!ExprParse {
    if (start_idx >= limit_idx) return markErrorAt(tokens, start_idx, error.InvalidExpr);
    const t = tokens[start_idx];

    if (tokEq(t, "do")) {
        if (start_idx + 1 >= limit_idx) return markErrorAt(tokens, start_idx, error.InvalidDoExpr);
        const call = try parseCallExpr(allocator, out_nodes, tokens, start_idx + 1, limit_idx);
        const idx = try appendExprNode(allocator, out_nodes, .{
            .kind = .do_call,
            .start_tok = start_idx,
            .end_tok = call.next_idx,
            .data = .{
                .call = .{
                    .func_name = tokens[start_idx + 1].lexeme,
                    .arg_count = call.arg_count,
                },
            },
        });
        return .{ .next_idx = call.next_idx, .node_idx = idx };
    }

    if (tokEq(t, ".")) {
        if (start_idx + 1 < limit_idx and tokEq(tokens[start_idx + 1], "{")) {
            return parseInferredAggLiteral(allocator, out_nodes, tokens, start_idx, limit_idx);
        }
        return markErrorAt(tokens, start_idx, error.UnsupportedExpr);
    }

    if (tokEq(t, "(")) {
        if (try parseLambdaExpr(allocator, out_nodes, tokens, start_idx, limit_idx)) |lambda| {
            return lambda;
        }
        const inner = try parseExpr(allocator, out_nodes, tokens, start_idx + 1, limit_idx);
        if (inner.next_idx >= limit_idx or !tokEq(tokens[inner.next_idx], ")")) {
            return markErrorAt(tokens, start_idx, error.InvalidParenExpr);
        }
        const end_idx = inner.next_idx + 1;
        const idx = try appendExprNode(allocator, out_nodes, .{
            .kind = .paren,
            .start_tok = start_idx,
            .end_tok = end_idx,
            .data = .{ .child = inner.node_idx },
        });
        return .{ .next_idx = end_idx, .node_idx = idx };
    }

    if (t.kind == .number or t.kind == .string or tokEq(t, "true") or tokEq(t, "false") or tokEq(t, "nil")) {
        if (start_idx + 1 < limit_idx and tokEq(tokens[start_idx + 1], "(")) {
            return markErrorAt(tokens, start_idx, error.LiteralCannotBeCalled);
        }
        const idx = try appendExprNode(allocator, out_nodes, .{
            .kind = .literal,
            .start_tok = start_idx,
            .end_tok = start_idx + 1,
            .data = .{ .none = {} },
        });
        return .{ .next_idx = start_idx + 1, .node_idx = idx };
    }

    if (t.kind == .ident) {
        if (start_idx + 1 < limit_idx and tokEq(tokens[start_idx + 1], "(")) {
            const call = try parseCallExpr(allocator, out_nodes, tokens, start_idx, limit_idx);
            const idx = try appendExprNode(allocator, out_nodes, .{
                .kind = .call,
                .start_tok = start_idx,
                .end_tok = call.next_idx,
                .data = .{
                    .call = .{
                        .func_name = t.lexeme,
                        .arg_count = call.arg_count,
                    },
                },
            });
            return .{ .next_idx = call.next_idx, .node_idx = idx };
        }

        if (isTypeName(t.lexeme) and hasTypeCtorBody(tokens, start_idx, limit_idx)) {
            const lit = try parseStructLiteral(allocator, out_nodes, tokens, start_idx, limit_idx);
            return lit;
        }

        const idx = try appendExprNode(allocator, out_nodes, .{
            .kind = .ident,
            .start_tok = start_idx,
            .end_tok = start_idx + 1,
            .data = .{ .none = {} },
        });
        return .{ .next_idx = start_idx + 1, .node_idx = idx };
    }

    if (tokEq(t, "{")) {
        return markErrorAt(tokens, start_idx, error.InvalidBraceExpr);
    }

    return markErrorAt(tokens, start_idx, error.UnsupportedExpr);
}

fn parseCallExpr(
    allocator: std.mem.Allocator,
    out_nodes: *std.ArrayList(ExprNode),
    tokens: []const lexer.Token,
    name_idx: usize,
    limit_idx: usize,
) anyerror!CallExprParse {
    if (name_idx + 1 >= limit_idx) return markErrorAt(tokens, name_idx, error.InvalidCallExpr);
    if (tokens[name_idx].kind != .ident) return markErrorAt(tokens, name_idx, error.InvalidCallExpr);
    if (!tokEq(tokens[name_idx + 1], "(")) return markErrorAt(tokens, name_idx + 1, error.InvalidCallExpr);

    const close_paren = try findMatchingInRange(tokens, name_idx + 1, "(", ")", limit_idx);
    const argc = try countArgsByExpr(allocator, out_nodes, tokens, name_idx + 2, close_paren);
    return .{
        .next_idx = close_paren + 1,
        .arg_count = argc,
    };
}

fn countArgsByExpr(
    allocator: std.mem.Allocator,
    out_nodes: *std.ArrayList(ExprNode),
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) anyerror!usize {
    if (start_idx >= end_idx) return 0;
    var i = start_idx;
    var argc: usize = 0;
    while (i < end_idx) {
        const expr = try parseExpr(allocator, out_nodes, tokens, i, end_idx);
        _ = expr.node_idx;
        argc += 1;
        i = expr.next_idx;
        if (i >= end_idx) break;
        if (!tokEq(tokens[i], ",")) return markErrorAt(tokens, i, error.InvalidCallArgList);
        i += 1;
        if (i >= end_idx) break; // allow trailing comma
    }
    return argc;
}

fn parseStructLiteral(
    allocator: std.mem.Allocator,
    out_nodes: *std.ArrayList(ExprNode),
    tokens: []const lexer.Token,
    type_idx: usize,
    limit_idx: usize,
) anyerror!ExprParse {
    const open_brace = try parseTypeCtorOpenBrace(tokens, type_idx, limit_idx);
    if (open_brace == null) {
        return markErrorAt(tokens, type_idx, error.InvalidStructLiteral);
    }

    const open_idx = open_brace.?;
    const close_brace = try findMatchingInRange(tokens, open_idx, "{", "}", limit_idx);
    try parseStructNamedArgs(allocator, out_nodes, tokens, open_idx + 1, close_brace);

    const idx = try appendExprNode(allocator, out_nodes, .{
        .kind = .struct_lit,
        .start_tok = type_idx,
        .end_tok = close_brace + 1,
        .data = .{ .none = {} },
    });
    return .{ .next_idx = close_brace + 1, .node_idx = idx };
}

fn parseTypeCtorOpenBrace(tokens: []const lexer.Token, type_idx: usize, limit_idx: usize) !?usize {
    if (type_idx + 1 >= limit_idx) return null;
    if (tokEq(tokens[type_idx + 1], "{")) return type_idx + 1;
    if (!tokEq(tokens[type_idx + 1], "<")) return null;

    const close_angle = try findMatchingInRange(tokens, type_idx + 1, "<", ">", limit_idx);
    if (close_angle + 1 >= limit_idx or !tokEq(tokens[close_angle + 1], "{")) return null;
    return close_angle + 1;
}

fn hasTypeCtorBody(tokens: []const lexer.Token, type_idx: usize, limit_idx: usize) bool {
    return (parseTypeCtorOpenBrace(tokens, type_idx, limit_idx) catch null) != null;
}

fn parseInferredAggLiteral(
    allocator: std.mem.Allocator,
    out_nodes: *std.ArrayList(ExprNode),
    tokens: []const lexer.Token,
    start_idx: usize,
    limit_idx: usize,
) anyerror!ExprParse {
    if (start_idx + 1 >= limit_idx or !tokEq(tokens[start_idx], ".") or !tokEq(tokens[start_idx + 1], "{")) {
        return markErrorAt(tokens, start_idx, error.InvalidExpr);
    }

    const close_brace = try findMatchingInRange(tokens, start_idx + 1, "{", "}", limit_idx);
    if (hasTopLevelEqual(tokens, start_idx + 2, close_brace)) {
        try parsePairItems(allocator, out_nodes, tokens, start_idx + 2, close_brace, "=", error.InvalidBraceExpr);
    } else {
        try parseExprItems(allocator, out_nodes, tokens, start_idx + 2, close_brace, error.InvalidExpr);
    }

    const idx = try appendExprNode(allocator, out_nodes, .{
        .kind = .inferred_agg_lit,
        .start_tok = start_idx,
        .end_tok = close_brace + 1,
        .data = .{ .none = {} },
    });
    return .{ .next_idx = close_brace + 1, .node_idx = idx };
}

fn hasTopLevelEqual(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
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
        if (tokEq(tokens[i], "=")) {
            if (i > 0 and tokEq(tokens[i - 1], ":")) continue;
            if (i + 1 < end_idx and tokEq(tokens[i + 1], ">")) continue;
            return true;
        }
    }
    return false;
}

fn parseStructNamedArgs(
    allocator: std.mem.Allocator,
    out_nodes: *std.ArrayList(ExprNode),
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) anyerror!void {
    if (start_idx >= end_idx) return;

    var i = start_idx;
    while (i < end_idx) {
        if (tokens[i].kind != .ident or !isStructFieldInitName(tokens[i].lexeme)) {
            return markErrorAt(tokens, i, error.InvalidStructLiteral);
        }
        i += 1;
        if (i >= end_idx or !tokEq(tokens[i], "=")) return markErrorAt(tokens, i, error.InvalidStructLiteral);
        i += 1;
        if (i >= end_idx) return markErrorAt(tokens, i, error.InvalidStructLiteral);

        const value = try parseExpr(allocator, out_nodes, tokens, i, end_idx);
        i = value.next_idx;
        if (i >= end_idx) break;
        if (!tokEq(tokens[i], ",")) return markErrorAt(tokens, i, error.InvalidStructLiteral);
        i += 1;
        if (i >= end_idx) return; // allow trailing comma
    }
}

fn isStructFieldInitName(name: []const u8) bool {
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

fn parseExprItems(
    allocator: std.mem.Allocator,
    out_nodes: *std.ArrayList(ExprNode),
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    invalid_err: anyerror,
) anyerror!void {
    if (start_idx >= end_idx) return;

    var i = start_idx;
    while (i < end_idx) {
        const first = try parseExpr(allocator, out_nodes, tokens, i, end_idx);
        i = first.next_idx;
        if (i >= end_idx) break;
        if (!tokEq(tokens[i], ",")) return markErrorAt(tokens, i, invalid_err);
        i += 1;
        if (i >= end_idx) return; // allow trailing comma
    }
}

fn parsePairItems(
    allocator: std.mem.Allocator,
    out_nodes: *std.ArrayList(ExprNode),
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    separator: []const u8,
    invalid_err: anyerror,
) anyerror!void {
    if (start_idx >= end_idx) return;

    var i = start_idx;
    while (i < end_idx) {
        const key = try parseExpr(allocator, out_nodes, tokens, i, end_idx);
        i = key.next_idx;
        if (i >= end_idx or !tokEq(tokens[i], separator)) return markErrorAt(tokens, i, invalid_err);
        i += 1;
        if (i >= end_idx) return markErrorAt(tokens, i, invalid_err);

        const value = try parseExpr(allocator, out_nodes, tokens, i, end_idx);
        i = value.next_idx;
        if (i >= end_idx) break;
        if (!tokEq(tokens[i], ",")) return markErrorAt(tokens, i, invalid_err);
        i += 1;
        if (i >= end_idx) return; // allow trailing comma
    }
}

fn parseLambdaExpr(
    allocator: std.mem.Allocator,
    out_nodes: *std.ArrayList(ExprNode),
    tokens: []const lexer.Token,
    start_idx: usize,
    limit_idx: usize,
) anyerror!?ExprParse {
    if (start_idx >= limit_idx or !tokEq(tokens[start_idx], "(")) return null;

    const close_paren = findMatchingInRange(tokens, start_idx, "(", ")", limit_idx) catch return null;
    if (!isArrowAt(tokens, close_paren + 1)) return null;
    if (close_paren + 3 > limit_idx) return markErrorAt(tokens, close_paren + 1, error.InvalidLambdaExpr);

    const body = try parseExpr(allocator, out_nodes, tokens, close_paren + 3, limit_idx);
    const idx = try appendExprNode(allocator, out_nodes, .{
        .kind = .lambda,
        .start_tok = start_idx,
        .end_tok = body.next_idx,
        .data = .{ .child = body.node_idx },
    });
    return .{ .next_idx = body.next_idx, .node_idx = idx };
}

fn appendExprNode(
    allocator: std.mem.Allocator,
    out_nodes: *std.ArrayList(ExprNode),
    node: ExprNode,
) !usize {
    try out_nodes.append(allocator, node);
    return out_nodes.items.len - 1;
}

fn findMatching(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8) !usize {
    return findMatchingInRange(tokens, open_idx, open, close, tokens.len);
}

fn findMatchingInRange(
    tokens: []const lexer.Token,
    open_idx: usize,
    open: []const u8,
    close: []const u8,
    limit: usize,
) !usize {
    if (open_idx >= limit or !tokEq(tokens[open_idx], open)) return error.InvalidGroupStart;

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

fn segmentContains(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, target: []const u8) bool {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokEq(tokens[i], target)) return true;
    }
    return false;
}

fn isArrowAt(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 1 >= tokens.len) return false;
    return tokEq(tokens[idx], "=") and tokEq(tokens[idx + 1], ">");
}

fn isNonAssignEqual(tokens: []const lexer.Token, idx: usize) bool {
    if (idx > 0 and tokEq(tokens[idx - 1], ":")) return true; // :=
    if (idx > 0 and tokEq(tokens[idx - 1], "=")) return true; // ==
    if (idx + 1 < tokens.len and tokEq(tokens[idx + 1], "=")) return true; // ==
    if (idx + 1 < tokens.len and tokEq(tokens[idx + 1], ">")) return true; // =>
    return false;
}

fn tokEq(t: lexer.Token, s: []const u8) bool {
    return std.mem.eql(u8, t.lexeme, s);
}

fn isTypeName(name: []const u8) bool {
    if (name.len == 0) return false;
    return std.ascii.isUpper(name[0]);
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
        if (std.mem.eql(u8, kw, name)) return true;
    }
    return false;
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

test "bool and nil literals parse as literal nodes" {
    const allocator = std.testing.allocator;
    const cases = [_][]const u8{
        "true",
        "false",
        "nil",
    };

    for (cases) |source| {
        const tokens = try lexer.tokenize(allocator, source);
        defer allocator.free(tokens);

        var nodes = try std.ArrayList(ExprNode).initCapacity(allocator, 0);
        defer nodes.deinit(allocator);

        const parsed = try parseExpr(allocator, &nodes, tokens, 0, tokens.len);
        try std.testing.expectEqual(tokens.len, parsed.next_idx);
        try std.testing.expectEqual(ExprKind.literal, nodes.items[parsed.node_idx].kind);
    }
}

test "literal cannot be called" {
    const allocator = std.testing.allocator;
    const tokens = try lexer.tokenize(allocator, "true(1)");
    defer allocator.free(tokens);

    var nodes = try std.ArrayList(ExprNode).initCapacity(allocator, 0);
    defer nodes.deinit(allocator);

    try std.testing.expectError(error.LiteralCannotBeCalled, parseExpr(allocator, &nodes, tokens, 0, tokens.len));
}

test "struct literal uses equals" {
    const allocator = std.testing.allocator;
    const tokens = try lexer.tokenize(allocator, "User{name = \"tom\"}");
    defer allocator.free(tokens);

    var nodes = try std.ArrayList(ExprNode).initCapacity(allocator, 0);
    defer nodes.deinit(allocator);

    const parsed = try parseExpr(allocator, &nodes, tokens, 0, tokens.len);
    try std.testing.expectEqual(tokens.len, parsed.next_idx);
    try std.testing.expectEqual(ExprKind.struct_lit, nodes.items[parsed.node_idx].kind);
}

test "struct literal colon is invalid" {
    const allocator = std.testing.allocator;
    const tokens = try lexer.tokenize(allocator, "User{name: \"tom\"}");
    defer allocator.free(tokens);

    var nodes = try std.ArrayList(ExprNode).initCapacity(allocator, 0);
    defer nodes.deinit(allocator);

    try std.testing.expectError(error.InvalidStructLiteral, parseExpr(allocator, &nodes, tokens, 0, tokens.len));
}
