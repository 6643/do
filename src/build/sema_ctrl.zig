//! Semantic analysis — ctrl checks.
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema_error = @import("sema_error.zig");
const type_util = @import("type_name.zig");
const sema_util = @import("sema_util.zig");
const sema_types = @import("sema_types.zig");

const callArgInfo = sema_util.callArgInfo;
const callArityCompatibleWithFunc = sema_util.callArityCompatibleWithFunc;
const collectFuncShapes = sema_util.collectFuncShapes;
const collectStructInfos = sema_util.collectStructInfos;
const compactTokenRangeEquals = sema_util.compactTokenRangeEquals;
const findInlineFuncTypeInParams = sema_util.findInlineFuncTypeInParams;
const findLineEndIdx = sema_util.findLineEndIdx;
const findMatching = sema_util.findMatching;
const findMatchingInRange = sema_util.findMatchingInRange;
const findNearestValueTypeName = sema_util.findNearestValueTypeName;
const findReturnTypeEnd = sema_util.findReturnTypeEnd;
const findStructFieldTypeEnd = sema_util.findStructFieldTypeEnd;
const findStructInfo = sema_util.findStructInfo;
const findTopLevelAssignEqOnLine = sema_util.findTopLevelAssignEqOnLine;
const findTopLevelComma = sema_util.findTopLevelComma;
const freeCallArgShapes = sema_util.freeCallArgShapes;
const freeFuncShapes = sema_util.freeFuncShapes;
const freeStructInfos = sema_util.freeStructInfos;
const funcParamTypeStart = sema_util.funcParamTypeStart;
const hasConcreteTypeName = sema_util.hasConcreteTypeName;
const hasKnownFuncCandidate = sema_util.hasKnownFuncCandidate;
const hasLocalStructDecl = sema_util.hasLocalStructDecl;
const hasTypeConstraintName = sema_util.hasTypeConstraintName;
const isArrowAt = sema_util.isArrowAt;
const isBaseIntTypeName = sema_util.isBaseIntTypeName;
const isBuiltinSpecialOrCoreName = sema_util.isBuiltinSpecialOrCoreName;
const isDeclOnlyName = sema_util.isDeclOnlyName;
const isFuncDeclStart = sema_util.isFuncDeclStart;
const isFuncTypeParam = sema_util.isFuncTypeParam;
const isFuncTypeRange = sema_util.isFuncTypeRange;
const isHostImportDeclStart = sema_util.isHostImportDeclStart;
const isImportedUpperAlias = sema_util.isImportedUpperAlias;
const isKeyword = sema_util.isKeyword;
const isLowerIdentName = sema_util.isLowerIdentName;
const isModernImportAssign = sema_util.isModernImportAssign;
const isNonAssignEqual = sema_util.isNonAssignEqual;
const isReadonlyIdentName = sema_util.isReadonlyIdentName;
const isReservedFuncName = sema_util.isReservedFuncName;
const isReservedSourceName = sema_util.isReservedSourceName;
const isReturnArrowAt = sema_util.isReturnArrowAt;
const isSnakeLowerName = sema_util.isSnakeLowerName;
const isStructDeclStart = sema_util.isStructDeclStart;
const isStructFieldDeclDefault = sema_util.isStructFieldDeclDefault;
const isStructFieldName = sema_util.isStructFieldName;
const isTopLevelCommaAny = sema_util.isTopLevelCommaAny;
const isTopLevelDeclHead = sema_util.isTopLevelDeclHead;
const isTypeDeclStart = sema_util.isTypeDeclStart;
const isValidDeclaredTypeName = sema_util.isValidDeclaredTypeName;
const isVisibleBindingOrCallableName = sema_util.isVisibleBindingOrCallableName;
const lineStartIdx = sema_util.lineStartIdx;
const markErrorAt = sema_util.markErrorAt;
const parseCallArgShapes = sema_util.parseCallArgShapes;
const parseImportDeclEnd = sema_util.parseImportDeclEnd;
const skipTopLevelImportBrace = sema_util.skipTopLevelImportBrace;
const publicFuncName = sema_util.publicFuncName;
const publicTypeName = sema_util.publicTypeName;
const stringTokenBody = sema_util.stringTokenBody;
const tokEq = sema_util.tokEq;
const tokenNameAppearsInRange = sema_util.tokenNameAppearsInRange;
const topLevelLineAssignIdx = sema_util.topLevelLineAssignIdx;
const typeConstraintIsFunctionType = sema_util.typeConstraintIsFunctionType;
const CallArgInfo = sema_types.CallArgInfo;
const FuncParamShape = sema_types.FuncParamShape;
const FuncShape = sema_types.FuncShape;
const StructInfo = sema_types.StructInfo;

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


const ArgRange = struct {
    start: usize,
    end: usize,
};

const FieldMetaBinding = struct {
    name: []const u8,
    struct_name: []const u8,
    body_depth: usize,
};

pub fn checkDeferStmts(
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


fn isValidLocalBindingName(name: []const u8) bool {
    return (isLowerIdentName(name) or isReadonlyIdentName(name)) and !isReservedFuncName(name);
}


fn isValidLoopBindingName(name: []const u8) bool {
    return std.mem.eql(u8, name, "_") or (isLowerIdentName(name) and !isReservedFuncName(name));
}


fn isBaseFloatTypeName(name: []const u8) bool {
    return std.mem.eql(u8, name, "f32") or std.mem.eql(u8, name, "f64");
}


pub fn checkLoopHeader(tokens: []const lexer.Token) !void {
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



/// Pass 1: collect `#label` immediately followed by `loop` (label decls only).
fn collectLoopLabelDecls(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    out: *std.ArrayList(LoopLabelDecl),
) !void {
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
            try out.append(allocator, .{
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
            if (tokEq(tokens[j], "}") and brace_depth > 0) brace_depth -= 1;
        }
        i = line_end;
    }
}

/// Register a `loop` keyword: queue its body open-brace (and optional label).
fn registerPendingLoop(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    loop_idx: usize,
    label_decls: []const LoopLabelDecl,
    pending_loop_opens: *std.ArrayList(usize),
    pending_loops: *std.ArrayList(PendingLoopLabel),
) !void {
    const open_idx = findLoopBlockOpen(tokens, loop_idx) orelse {
        return markErrorAt(tokens, loop_idx, error.InvalidLoopHeader);
    };
    try pending_loop_opens.append(allocator, open_idx);
    const label_name = labelDeclForLine(label_decls, tokens[loop_idx].line) orelse return;
    try pending_loops.append(allocator, .{ .open_idx = open_idx, .name = label_name });
}

/// When `{` is reached: activate any pending loop/label whose body opens here.
fn activatePendingLoopBody(
    allocator: std.mem.Allocator,
    open_idx: usize,
    brace_depth: usize,
    pending_loop_opens: *std.ArrayList(usize),
    pending_loops: *std.ArrayList(PendingLoopLabel),
    active_loops: *std.ArrayList(ActiveLoop),
    active_labels: *std.ArrayList(ActiveLoopLabel),
) !void {
    if (pending_loop_opens.items.len > 0 and
        pending_loop_opens.items[pending_loop_opens.items.len - 1] == open_idx)
    {
        _ = pending_loop_opens.pop();
        try active_loops.append(allocator, .{ .body_depth = brace_depth });
    }
    if (pending_loops.items.len == 0) return;
    if (pending_loops.items[pending_loops.items.len - 1].open_idx != open_idx) return;
    const pending = pending_loops.pop().?;
    try active_labels.append(allocator, .{
        .name = pending.name,
        .body_depth = brace_depth,
    });
}

/// After `}`: drop active loops/labels whose body depth is no longer live.
fn popActiveLoopsPastDepth(
    brace_depth: usize,
    active_loops: *std.ArrayList(ActiveLoop),
    active_labels: *std.ArrayList(ActiveLoopLabel),
) void {
    while (active_loops.items.len > 0 and
        active_loops.items[active_loops.items.len - 1].body_depth > brace_depth)
    {
        _ = active_loops.pop();
    }
    while (active_labels.items.len > 0 and
        active_labels.items[active_labels.items.len - 1].body_depth > brace_depth)
    {
        _ = active_labels.pop();
    }
}

/// Pass 2: walk tokens, track active loop/label stack, validate break/continue.
fn checkLoopLabelStack(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    label_decls: []const LoopLabelDecl,
) !void {
    var pending_loops = try std.ArrayList(PendingLoopLabel).initCapacity(allocator, 0);
    defer pending_loops.deinit(allocator);
    var pending_loop_opens = try std.ArrayList(usize).initCapacity(allocator, 0);
    defer pending_loop_opens.deinit(allocator);
    var active_loops = try std.ArrayList(ActiveLoop).initCapacity(allocator, 0);
    defer active_loops.deinit(allocator);
    var active_labels = try std.ArrayList(ActiveLoopLabel).initCapacity(allocator, 0);
    defer active_labels.deinit(allocator);

    var brace_depth: usize = 0;
    var i: usize = 0;
    while (i < tokens.len) {
        const line_start = i;
        const line_end = findLineEndIdx(tokens, i);
        var j = line_start;
        while (j < line_end) : (j += 1) {
            if (tokEq(tokens[j], "loop")) {
                try registerPendingLoop(allocator, tokens, j, label_decls, &pending_loop_opens, &pending_loops);
            } else if (tokEq(tokens[j], "break") or tokEq(tokens[j], "continue")) {
                try validateBreakOrContinue(tokens, j, line_end, active_loops.items.len, active_labels.items);
            } else if (tokEq(tokens[j], "{")) {
                brace_depth += 1;
                try activatePendingLoopBody(
                    allocator,
                    j,
                    brace_depth,
                    &pending_loop_opens,
                    &pending_loops,
                    &active_loops,
                    &active_labels,
                );
            } else if (tokEq(tokens[j], "}")) {
                if (brace_depth > 0) brace_depth -= 1;
                popActiveLoopsPastDepth(brace_depth, &active_loops, &active_labels);
            }
        }
        i = line_end;
    }
}

pub fn checkLoopLabels(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
    var label_decls = try std.ArrayList(LoopLabelDecl).initCapacity(allocator, 0);
    defer label_decls.deinit(allocator);
    try collectLoopLabelDecls(allocator, tokens, &label_decls);
    try checkLoopLabelStack(allocator, tokens, label_decls.items);
}


fn labelDeclForLine(decls: []const LoopLabelDecl, line: usize) ?[]const u8 {
    for (decls) |decl| {
        if (decl.loop_line == line) return decl.name;
    }
    return null;
}


fn validateBreakOrContinue(
    tokens: []const lexer.Token,
    j: usize,
    line_end: usize,
    active_loop_count: usize,
    active_labels: []const ActiveLoopLabel,
) !void {
    if (active_loop_count == 0) return markErrorAt(tokens, j, error.InvalidLoopHeader);
    if (j + 1 >= line_end or !tokEq(tokens[j + 1], "#")) return;
    if (j + 2 >= line_end or tokens[j + 2].kind != .ident) {
        return markErrorAt(tokens, j + 1, error.InvalidLoopHeader);
    }
    if (!isValidLoopLabelName(tokens[j + 2].lexeme)) {
        return markErrorAt(tokens, j + 2, error.InvalidLoopHeader);
    }
    if (!labelIsActive(active_labels, tokens[j + 2].lexeme)) {
        return markErrorAt(tokens, j + 1, error.InvalidLoopHeader);
    }
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


pub fn checkFieldReflection(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
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


pub fn checkConstraintLayout(tokens: []const lexer.Token) !void {
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

        if (!tokEq(tokens[i], "#")) {
            if (in_constraint_block) {
                try validateConstraintBlockFollower(tokens, i, last_constraint_line, saw_func_type_constraint, saw_func_constraint, constraint_block_start.?);
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


pub fn checkAssignmentConstraints(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
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
        try registerSingleLhsBinding(allocator, tokens, line_start, stmt_eq_idx, &scopes);

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


fn registerSingleLhsBinding(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    line_start: usize,
    stmt_eq_idx: usize,
    scopes: *std.ArrayList(Scope),
) !void {
    if (findTopLevelComma(tokens, line_start, stmt_eq_idx) != null) return;
    const lhs_name = tokens[line_start].lexeme;
    if (lhs_name.len == 0 or lhs_name[0] == '.' or lhs_name[0] == '_') return;
    if (isSingleLocalValueDecl(tokens, line_start, stmt_eq_idx)) {
        if (scopesContain(scopes.items, lhs_name)) return markErrorAt(tokens, line_start, error.DuplicateLocalBinding);
        var current = &scopes.items[scopes.items.len - 1];
        try current.names.append(allocator, lhs_name);
        return;
    }
    if (scopesContain(scopes.items, lhs_name)) return;
    var current = &scopes.items[scopes.items.len - 1];
    try current.names.append(allocator, lhs_name);
}

fn validateConstraintFollowingDecl(
    tokens: []const lexer.Token,
    i: usize,
    constraint_block_start: usize,
) !void {
    if (isFuncDeclStart(tokens, i)) {
        const close_paren = findMatching(tokens, i + 1, "(", ")") catch
            return markErrorAt(tokens, i, error.InvalidConstraintDecl);
        if (findInlineFuncTypeInParams(tokens, i + 2, close_paren)) |name_idx| {
            return markErrorAt(tokens, name_idx, error.InvalidConstraintDecl);
        }
        if (findUnusedTypeConstraintInFuncParams(tokens, constraint_block_start, i, i + 2, close_paren)) |name_idx| {
            return markErrorAt(tokens, name_idx, error.InvalidConstraintDecl);
        }
        return;
    }
    if (!isStructDeclStart(tokens, i)) return;
    const close_brace = findMatching(tokens, i + 1, "{", "}") catch
        return markErrorAt(tokens, i, error.InvalidConstraintDecl);
    if (findUnusedTypeConstraintInStructFields(tokens, constraint_block_start, i, i + 2, close_brace)) |name_idx| {
        return markErrorAt(tokens, name_idx, error.InvalidConstraintDecl);
    }
}

fn validateConstraintBlockFollower(
    tokens: []const lexer.Token,
    i: usize,
    last_constraint_line: usize,
    saw_func_type_constraint: bool,
    saw_func_constraint: bool,
    constraint_block_start: usize,
) !void {
    if (tokens[i].line != last_constraint_line + 1) {
        return markErrorAt(tokens, i, error.InvalidConstraintDecl);
    }
    if ((saw_func_type_constraint or saw_func_constraint) and !isFuncDeclStart(tokens, i)) {
        return markErrorAt(tokens, i, error.InvalidConstraintDecl);
    }
    if (!isFuncDeclStart(tokens, i) and !isStructDeclStart(tokens, i)) {
        return markErrorAt(tokens, i, error.InvalidConstraintDecl);
    }
    try validateConstraintFollowingDecl(tokens, i, constraint_block_start);
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


fn isAllowedConstraintFuncName(name: []const u8) bool {
    if (!isLowerIdentName(name)) return false;
    if (isDeclOnlyName(name)) return false;
    if (isBuiltinSpecialOrCoreName(name)) return false;
    if (isReservedSourceName(name)) return false;
    return !isKeyword(name);
}


