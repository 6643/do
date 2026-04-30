const std = @import("std");
const lexer = @import("lexer.zig");

pub const ConditionContext = enum {
    if_cond,
    if_bind_rhs,
    match_target,
};

pub const FuncSig = struct {
    name: []const u8,
    param_min: usize,
    param_max: ?usize, // null => variadic
    return_arity: usize,
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
    brace_lit,
    struct_lit,
    list_lit,
    map_lit,
    tuple_lit,
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
    body_open_idx: ?usize,
    body_close_idx: ?usize,
};

const ReturnSpecParse = struct {
    next_idx: usize,
    return_arity: usize,
    body_open_idx: ?usize,
    body_close_idx: ?usize,
};

const ParamParse = struct {
    param_min: usize,
    param_max: ?usize,
};

const ExprParse = struct {
    next_idx: usize,
    node_idx: usize,
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
        if (depth_brace == 0 and tokEq(tokens[i], "{")) {
            if (try parseImportDeclEnd(tokens, i)) |next_idx| {
                top_level += 1;
                i = next_idx - 1;
                continue;
            }
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
    return tokEq(tokens[i], "test");
}

fn isFuncDeclStart(tokens: []const lexer.Token, i: usize) bool {
    if (i + 1 >= tokens.len) return false;
    if (tokens[i].kind != .ident) return false;
    if (isKeyword(tokens[i].lexeme)) return false;
    return tokEq(tokens[i + 1], "(");
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

    if (parsed.body_open_idx != null and parsed.body_close_idx != null) {
        try collectConditionExprs(
            allocator,
            out_conds,
            out_nodes,
            tokens,
            parsed.body_open_idx.?,
            parsed.body_close_idx.?,
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
            .line = name_tok.line,
        },
        .body_open_idx = ret.body_open_idx,
        .body_close_idx = ret.body_close_idx,
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
            .body_open_idx = start_idx,
            .body_close_idx = close_brace,
        };
    }
    if (isArrowAt(tokens, start_idx)) {
        const arrow_end = findArrowEnd(tokens, start_idx + 2);
        return .{
            .next_idx = arrow_end,
            .return_arity = 0,
            .body_open_idx = null,
            .body_close_idx = null,
        };
    }

    var arity: usize = 0;
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
                .body_open_idx = i,
                .body_close_idx = close_brace,
            };
        }
        if (isArrowAt(tokens, i)) {
            const arrow_end = findArrowEnd(tokens, i + 2);
            return .{
                .next_idx = arrow_end,
                .return_arity = arity,
                .body_open_idx = null,
                .body_close_idx = null,
            };
        }
    }

    return error.UnterminatedFuncDecl;
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
) !void {
    var i = body_open_idx + 1;
    while (i < body_close_idx) {
        i = try parseBodyStmt(allocator, out_conds, out_nodes, tokens, i, body_close_idx);
    }
}

fn parseBodyStmt(
    allocator: std.mem.Allocator,
    out_conds: *std.ArrayList(ConditionExpr),
    out_nodes: *std.ArrayList(ExprNode),
    tokens: []const lexer.Token,
    stmt_idx: usize,
    limit_idx: usize,
) !usize {
    if (stmt_idx >= limit_idx) return stmt_idx + 1;
    if (tokEq(tokens[stmt_idx], "if")) {
        return parseIfStmt(allocator, out_conds, out_nodes, tokens, stmt_idx, limit_idx);
    }
    if (tokEq(tokens[stmt_idx], "match")) {
        return parseMatchStmt(allocator, out_conds, out_nodes, tokens, stmt_idx, limit_idx);
    }
    if (tokEq(tokens[stmt_idx], "loop")) {
        return parseLoopStmt(allocator, out_nodes, tokens, stmt_idx, limit_idx);
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

fn parseMatchStmt(
    allocator: std.mem.Allocator,
    out_conds: *std.ArrayList(ConditionExpr),
    out_nodes: *std.ArrayList(ExprNode),
    tokens: []const lexer.Token,
    match_idx: usize,
    limit_idx: usize,
) !usize {
    try maybeRecordMatchConditionExpr(allocator, out_conds, out_nodes, tokens, match_idx, limit_idx);
    return match_idx + 1;
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
        return open_brace_idx + 1; // loop <bind> := <expr> { ... }
    }

    const cond = parseExpr(allocator, out_nodes, tokens, header_start, limit_idx) catch
        return markErrorAt(tokens, header_start, error.InvalidLoopHeader);
    if (cond.next_idx >= limit_idx) return markErrorAt(tokens, cond.next_idx, error.InvalidLoopHeader);
    if (!tokEq(tokens[cond.next_idx], "{")) return markErrorAt(tokens, cond.next_idx, error.InvalidLoopHeader);
    return cond.next_idx + 1; // loop <cond-expr> { ... }
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

    const rhs_start = bind_idx + 2;
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
        if (!tokEq(tokens[i], ":") or !tokEq(tokens[i + 1], "=")) continue;
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

fn maybeRecordMatchConditionExpr(
    allocator: std.mem.Allocator,
    out_conds: *std.ArrayList(ConditionExpr),
    out_nodes: *std.ArrayList(ExprNode),
    tokens: []const lexer.Token,
    match_idx: usize,
    limit_idx: usize,
) !void {
    if (match_idx + 1 >= limit_idx) return;
    const parsed = try parseExpr(allocator, out_nodes, tokens, match_idx + 1, limit_idx);
    try validateMatchHeaderTail(tokens, parsed.next_idx, limit_idx);

    try out_conds.append(allocator, .{
        .root_expr_idx = parsed.node_idx,
        .context = .match_target,
        .line = tokens[match_idx].line,
    });
}

fn validateMatchHeaderTail(tokens: []const lexer.Token, next_idx: usize, limit_idx: usize) !void {
    if (next_idx >= limit_idx) return markErrorAt(tokens, next_idx, error.InvalidMatchHeader);
    if (tokEq(tokens[next_idx], "{")) return;
    return markErrorAt(tokens, next_idx, error.InvalidMatchHeader);
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

    if (findTopLevelAssignEq(tokens, next_idx, line_end)) |eq_idx| {
        if (eq_idx + 1 >= line_end) return markErrorAt(tokens, eq_idx, error.InvalidIfHeader);
        const rhs = parseExpr(allocator, out_nodes, tokens, eq_idx + 1, line_end) catch
            return markErrorAt(tokens, eq_idx + 1, error.InvalidIfHeader);
        if (rhs.next_idx != line_end) return markErrorAt(tokens, rhs.next_idx, error.InvalidIfHeader);
        return;
    }

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

    if (tokEq(t, "|")) {
        return parseLambdaExpr(allocator, out_nodes, tokens, start_idx, limit_idx);
    }

    if (tokEq(t, "(")) {
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

    if (tokEq(t, "{")) {
        return parseBraceLiteral(allocator, out_nodes, tokens, start_idx, limit_idx);
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

        if (start_idx + 1 < limit_idx and tokEq(tokens[start_idx + 1], "<") and isTypedCollectionLiteralName(t.lexeme)) {
            const lit = try parseTypedCollectionLiteral(allocator, out_nodes, tokens, start_idx, limit_idx);
            return lit;
        }

        if (start_idx + 1 < limit_idx and tokEq(tokens[start_idx + 1], "{") and isTypeName(t.lexeme)) {
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
    if (type_idx + 1 >= limit_idx or !tokEq(tokens[type_idx + 1], "{")) {
        return markErrorAt(tokens, type_idx, error.InvalidStructLiteral);
    }
    const close_brace = try findMatchingInRange(tokens, type_idx + 1, "{", "}", limit_idx);
    try parseStructNamedArgs(allocator, out_nodes, tokens, type_idx + 2, close_brace);

    const idx = try appendExprNode(allocator, out_nodes, .{
        .kind = .struct_lit,
        .start_tok = type_idx,
        .end_tok = close_brace + 1,
        .data = .{ .none = {} },
    });
    return .{ .next_idx = close_brace + 1, .node_idx = idx };
}

fn parseBraceLiteral(
    allocator: std.mem.Allocator,
    out_nodes: *std.ArrayList(ExprNode),
    tokens: []const lexer.Token,
    start_idx: usize,
    limit_idx: usize,
) anyerror!ExprParse {
    if (start_idx >= limit_idx or !tokEq(tokens[start_idx], "{")) {
        return markErrorAt(tokens, start_idx, error.InvalidExpr);
    }

    const close_brace = try findMatchingInRange(tokens, start_idx, "{", "}", limit_idx);
    if (hasTopLevelColon(tokens, start_idx + 1, close_brace)) {
        try parsePairItems(allocator, out_nodes, tokens, start_idx + 1, close_brace, error.InvalidBraceExpr);
    } else {
        try parseExprItems(allocator, out_nodes, tokens, start_idx + 1, close_brace, error.InvalidExpr);
    }

    const idx = try appendExprNode(allocator, out_nodes, .{
        .kind = .brace_lit,
        .start_tok = start_idx,
        .end_tok = close_brace + 1,
        .data = .{ .none = {} },
    });
    return .{ .next_idx = close_brace + 1, .node_idx = idx };
}

fn hasTopLevelColon(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
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
        if (tokEq(tokens[i], ":")) return true;
    }
    return false;
}

fn parseTypedCollectionLiteral(
    allocator: std.mem.Allocator,
    out_nodes: *std.ArrayList(ExprNode),
    tokens: []const lexer.Token,
    name_idx: usize,
    limit_idx: usize,
) anyerror!ExprParse {
    if (name_idx + 1 >= limit_idx or !tokEq(tokens[name_idx + 1], "<")) {
        return markErrorAt(tokens, name_idx, error.InvalidTypedLiteral);
    }
    const close_angle = try findMatchingInRange(tokens, name_idx + 1, "<", ">", limit_idx);
    if (close_angle + 1 >= limit_idx or !tokEq(tokens[close_angle + 1], "{")) {
        return markErrorAt(tokens, close_angle, error.InvalidTypedLiteral);
    }

    const close_brace = try findMatchingInRange(tokens, close_angle + 1, "{", "}", limit_idx);
    const name = tokens[name_idx].lexeme;
    const kind = collectionKindForName(name);
    if (std.mem.eql(u8, name, "List")) {
        try parseExprItems(allocator, out_nodes, tokens, close_angle + 2, close_brace, error.InvalidListLiteral);
    } else if (std.mem.eql(u8, name, "Map")) {
        try parsePairItems(allocator, out_nodes, tokens, close_angle + 2, close_brace, error.InvalidMapLiteral);
    } else {
        try parseExprItems(allocator, out_nodes, tokens, close_angle + 2, close_brace, error.InvalidTupleLiteral);
    }

    const idx = try appendExprNode(allocator, out_nodes, .{
        .kind = kind,
        .start_tok = name_idx,
        .end_tok = close_brace + 1,
        .data = .{ .none = {} },
    });
    return .{ .next_idx = close_brace + 1, .node_idx = idx };
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
        if (tokens[i].kind != .ident) return markErrorAt(tokens, i, error.InvalidStructLiteral);
        i += 1;
        if (i >= end_idx or !tokEq(tokens[i], ":")) return markErrorAt(tokens, i, error.InvalidStructLiteral);
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
    invalid_err: anyerror,
) anyerror!void {
    if (start_idx >= end_idx) return;

    var i = start_idx;
    while (i < end_idx) {
        const key = try parseExpr(allocator, out_nodes, tokens, i, end_idx);
        i = key.next_idx;
        if (i >= end_idx or !tokEq(tokens[i], ":")) return markErrorAt(tokens, i, invalid_err);
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
) anyerror!ExprParse {
    if (!tokEq(tokens[start_idx], "|")) return markErrorAt(tokens, start_idx, error.InvalidLambdaExpr);
    var i = start_idx + 1;
    while (i < limit_idx and !tokEq(tokens[i], "|")) : (i += 1) {}
    if (i >= limit_idx) return markErrorAt(tokens, start_idx, error.InvalidLambdaExpr);

    const body = try parseExpr(allocator, out_nodes, tokens, i + 1, limit_idx);
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

fn collectionKindForName(name: []const u8) ExprKind {
    if (std.mem.eql(u8, name, "List")) return .list_lit;
    if (std.mem.eql(u8, name, "Map")) return .map_lit;
    return .tuple_lit;
}

fn isTypedCollectionLiteralName(name: []const u8) bool {
    return std.mem.eql(u8, name, "List") or
        std.mem.eql(u8, name, "Map") or
        std.mem.eql(u8, name, "Tuple");
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
        "match",
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

fn parseImportDeclEnd(tokens: []const lexer.Token, start_idx: usize) anyerror!?usize {
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
    if (close_paren != colon_idx + 5) return markErrorAt(tokens, colon_idx + 3, error.InvalidImportDecl);

    try validateImportItems(tokens, start_idx + 1, close_brace);
    return close_paren + 1;
}

fn validateImportItems(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) anyerror!void {
    if (start_idx >= end_idx) return markErrorAt(tokens, start_idx, error.InvalidImportDecl);

    var i = start_idx;
    while (i < end_idx) {
        const item_end = try findImportItemEnd(tokens, i, end_idx);
        try validateImportItem(tokens, i, item_end);
        i = item_end;
        if (i >= end_idx) break;
        if (!tokEq(tokens[i], ",")) return markErrorAt(tokens, i, error.InvalidImportDecl);
        i += 1;
        if (i >= end_idx) return; // allow trailing comma
    }
}

fn findImportItemEnd(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) anyerror!usize {
    if (start_idx >= end_idx) return markErrorAt(tokens, start_idx, error.InvalidImportDecl);

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
            if (depth_paren == 0) return markErrorAt(tokens, i, error.InvalidImportDecl);
            depth_paren -= 1;
            continue;
        }
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace == 0) return markErrorAt(tokens, i, error.InvalidImportDecl);
            depth_brace -= 1;
            continue;
        }
        if (tokEq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tokEq(tokens[i], ">")) {
            if (depth_angle == 0) continue; // allow function arrow `=>`
            depth_angle -= 1;
            continue;
        }
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tokEq(tokens[i], ",")) break;
    }

    if (depth_paren != 0 or depth_brace != 0 or depth_angle != 0) {
        return markErrorAt(tokens, start_idx, error.InvalidImportDecl);
    }
    return i;
}

fn validateImportItem(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) anyerror!void {
    if (start_idx >= end_idx) return markErrorAt(tokens, start_idx, error.InvalidImportDecl);
    if (tokens[start_idx].kind != .ident) return markErrorAt(tokens, start_idx, error.InvalidImportDecl);
    if (isImportConflictName(tokens[start_idx].lexeme)) return markErrorAt(tokens, start_idx, error.InvalidImportDecl);
    if (start_idx + 1 == end_idx) return; // plain symbol import: {sqrt}

    if (tokEq(tokens[start_idx + 1], ":")) {
        if (start_idx + 3 != end_idx) return markErrorAt(tokens, start_idx + 1, error.InvalidImportDecl);
        if (tokens[start_idx + 2].kind != .ident) return markErrorAt(tokens, start_idx + 2, error.InvalidImportDecl);
        return; // renamed symbol import: {m_sqrt:sqrt}
    }

    if (tokEq(tokens[start_idx + 1], "{")) {
        return validateImportTypeItem(tokens, start_idx, end_idx);
    }
    if (tokEq(tokens[start_idx + 1], "(")) {
        return validateImportFuncItem(tokens, start_idx, end_idx);
    }
    return validateImportValueItem(tokens, start_idx, end_idx);
}

fn validateImportValueItem(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) anyerror!void {
    const type_end = try parseImportTypeExpr(tokens, start_idx + 1, end_idx);
    if (type_end != end_idx) return markErrorAt(tokens, type_end, error.InvalidImportDecl);
}

fn validateImportTypeItem(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) anyerror!void {
    const open_idx = start_idx + 1;
    const close_brace = try findMatchingInRange(tokens, open_idx, "{", "}", end_idx);
    if (close_brace + 1 != end_idx) return markErrorAt(tokens, close_brace + 1, error.InvalidImportDecl);
    if (open_idx + 1 >= close_brace) return;

    var i = open_idx + 1;
    while (i < close_brace) {
        if (tokens[i].kind != .ident) return markErrorAt(tokens, i, error.InvalidImportDecl);
        i += 1;
        if (i >= close_brace) return markErrorAt(tokens, i, error.InvalidImportDecl);

        const type_end = try parseImportTypeExpr(tokens, i, close_brace);
        if (type_end <= i) return markErrorAt(tokens, i, error.InvalidImportDecl);
        i = type_end;
        if (i >= close_brace) break;
        if (!tokEq(tokens[i], ",")) return markErrorAt(tokens, i, error.InvalidImportDecl);
        i += 1;
        if (i >= close_brace) return; // allow trailing comma
    }
}

fn validateImportFuncItem(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) anyerror!void {
    const open_idx = start_idx + 1;
    const close_paren = try findMatchingInRange(tokens, open_idx, "(", ")", end_idx);
    if (open_idx + 1 < close_paren) {
        try parseImportTypeList(tokens, open_idx + 1, close_paren);
    }

    var i = close_paren + 1;
    if (i + 2 > end_idx) return markErrorAt(tokens, i, error.InvalidImportDecl);
    if (!tokEq(tokens[i], "=")) return markErrorAt(tokens, i, error.InvalidImportDecl);
    if (!tokEq(tokens[i + 1], ">")) return markErrorAt(tokens, i + 1, error.InvalidImportDecl);
    i += 2;
    if (i >= end_idx) return markErrorAt(tokens, i, error.InvalidImportDecl);

    const ret_end = try parseImportTypeExpr(tokens, i, end_idx);
    if (ret_end != end_idx) return markErrorAt(tokens, ret_end, error.InvalidImportDecl);
}

fn parseImportTypeExpr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) anyerror!usize {
    if (start_idx >= end_idx) return markErrorAt(tokens, start_idx, error.InvalidImportDecl);

    if (tokEq(tokens[start_idx], "(")) {
        const close_paren = try findMatchingInRange(tokens, start_idx, "(", ")", end_idx);
        const inner_end = try parseImportTypeExpr(tokens, start_idx + 1, close_paren);
        if (inner_end != close_paren) return markErrorAt(tokens, start_idx, error.InvalidImportDecl);
        return close_paren + 1;
    }

    if (tokens[start_idx].kind != .ident) return markErrorAt(tokens, start_idx, error.InvalidImportDecl);
    const i = start_idx + 1;
    if (i >= end_idx or !tokEq(tokens[i], "<")) return i;

    const close_angle = try findMatchingInRange(tokens, i, "<", ">", end_idx);
    if (i + 1 == close_angle) return markErrorAt(tokens, i, error.InvalidImportDecl);
    try parseImportTypeList(tokens, i + 1, close_angle);
    return close_angle + 1;
}

fn parseImportTypeList(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) anyerror!void {
    if (start_idx >= end_idx) return markErrorAt(tokens, start_idx, error.InvalidImportDecl);

    var i = start_idx;
    while (i < end_idx) {
        const type_end = try parseImportTypeExpr(tokens, i, end_idx);
        if (type_end <= i or type_end > end_idx) return markErrorAt(tokens, i, error.InvalidImportDecl);
        i = type_end;
        if (i >= end_idx) break;
        if (!tokEq(tokens[i], ",")) return markErrorAt(tokens, i, error.InvalidImportDecl);
        i += 1;
        if (i >= end_idx) return; // allow trailing comma
    }
}

fn isImportConflictName(name: []const u8) bool {
    return isKeyword(name);
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
