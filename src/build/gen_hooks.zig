//! Late-bound emit callbacks to break gen domain import cycles.
const std = @import("std");
const lexer = @import("lexer.zig");
const gen_types = @import("gen_types.zig");
const codegen_union_layout = @import("codegen_union_layout.zig");

const LocalSet = gen_types.LocalSet;
const CodegenContext = gen_types.CodegenContext;
const CodegenError = gen_types.CodegenError;
const FuncDecl = gen_types.FuncDecl;
const FuncResultItem = gen_types.FuncResultItem;
const CallLastUseMoveContext = gen_types.CallLastUseMoveContext;
const DeferContext = gen_types.DeferContext;
const LoopControl = gen_types.LoopControl;
const SelfTailTco = gen_types.SelfTailTco;
const UnionLayout = codegen_union_layout.UnionLayout;

pub const EmitExprFn = *const fn (
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    expected_ty: ?[]const u8,
    out: *std.ArrayList(u8),
) CodegenError!bool;

pub const EmitExprMoveFn = *const fn (
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    expected_ty: ?[]const u8,
    move_ctx: ?*const CallLastUseMoveContext,
    out: *std.ArrayList(u8),
) CodegenError!bool;

pub const EmitUserFuncCallMoveFn = *const fn (
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    func: FuncDecl,
    move_ctx: ?*const CallLastUseMoveContext,
    out: *std.ArrayList(u8),
) anyerror!bool;

pub const EmitBodyFn = *const fn (
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_start: usize,
    locals: *const LocalSet,
    return_cleanup_locals: *const LocalSet,
    control_cleanup_locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_items: []const FuncResultItem,
    result_struct: ?[]const u8,
    result_union: ?UnionLayout,
    loop_ctx: ?LoopControl,
    defer_ctx: ?*const DeferContext,
    return_label: ?[]const u8,
    self_tail_tco: ?*const SelfTailTco,
    out: *std.ArrayList(u8),
) anyerror!void;

pub const EmitUnionValueFn = *const fn (
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    layout: UnionLayout,
    copy_managed: bool,
    move_ctx: ?*const CallLastUseMoveContext,
    out: *std.ArrayList(u8),
) CodegenError!bool;

pub const CollectBodyLocalsFn = *const fn (
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    out: *LocalSet,
) anyerror!void;

pub const CollectBodyLocalsWithModeFn = *const fn (
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    out: *LocalSet,
    recurse_nested: bool,
) anyerror!void;

pub const EmitMultiResultAssignmentFn = *const fn (
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool;

pub const EmitBareUserFuncCallFn = *const fn (
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool;

pub const EmitBareUserFuncCallMoveFn = *const fn (
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool;

pub const EmitUserFuncCallUnionBindingMoveFn = *const fn (
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    stmt_end: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    func: FuncDecl,
    out: *std.ArrayList(u8),
) anyerror!bool;

pub const EmitUnionStructPayloadForTypeFn = *const fn (
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    name: []const u8,
    ty: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    copy_managed: bool,
    out: *std.ArrayList(u8),
) CodegenError!bool;

pub var emit_expr: EmitExprFn = undefined;
pub var emit_expr_move: EmitExprMoveFn = undefined;
pub var emit_user_func_call_move: EmitUserFuncCallMoveFn = undefined;
pub var emit_body: ?EmitBodyFn = null;
pub var emit_union_value: ?EmitUnionValueFn = null;
pub var collect_body_locals: ?CollectBodyLocalsFn = null;
pub var collect_body_locals_with_mode: ?CollectBodyLocalsWithModeFn = null;
pub var emit_multi_result_assignment: ?EmitMultiResultAssignmentFn = null;
pub var emit_bare_user_func_call: ?EmitBareUserFuncCallFn = null;
pub var emit_bare_user_func_call_move: ?EmitBareUserFuncCallMoveFn = null;
pub var emit_user_func_call_union_binding_move: ?EmitUserFuncCallUnionBindingMoveFn = null;
pub var emit_union_struct_payload_for_type: ?EmitUnionStructPayloadForTypeFn = null;

pub const InferGenericCallUnionResultFn = *const fn (
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    call_head: gen_types.ExprCallHead,
    locals: *const LocalSet,
    ctx: CodegenContext,
    result_owned_types: *std.ArrayList([]const u8),
) CodegenError!?UnionLayout;

pub var infer_generic_call_union_result: ?InferGenericCallUnionResultFn = null;

pub fn installInferGenericCallUnionResult(f: InferGenericCallUnionResultFn) void {
    infer_generic_call_union_result = f;
}


pub var installed: bool = false;

pub fn install(
    expr: EmitExprFn,
    expr_move: EmitExprMoveFn,
    user_call_move: EmitUserFuncCallMoveFn,
) void {
    emit_expr = expr;
    emit_expr_move = expr_move;
    emit_user_func_call_move = user_call_move;
    installed = true;
}

pub fn installBody(f: EmitBodyFn) void {
    emit_body = f;
}
pub fn installUnionValue(f: EmitUnionValueFn) void {
    emit_union_value = f;
}
pub fn installCollectBodyLocals(f: CollectBodyLocalsFn) void {
    collect_body_locals = f;
}
pub fn installCollectBodyLocalsWithMode(f: CollectBodyLocalsWithModeFn) void {
    collect_body_locals_with_mode = f;
}
pub fn installEmitMultiResultAssignment(f: EmitMultiResultAssignmentFn) void {
    emit_multi_result_assignment = f;
}
pub fn installEmitBareUserFuncCall(f: EmitBareUserFuncCallFn) void {
    emit_bare_user_func_call = f;
}
pub fn installEmitBareUserFuncCallMove(f: EmitBareUserFuncCallMoveFn) void {
    emit_bare_user_func_call_move = f;
}
pub fn installEmitUserFuncCallUnionBindingMove(f: EmitUserFuncCallUnionBindingMoveFn) void {
    emit_user_func_call_union_binding_move = f;
}
pub fn installEmitUnionStructPayloadForType(f: EmitUnionStructPayloadForTypeFn) void {
    emit_union_struct_payload_for_type = f;
}

pub fn emitExpr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    expected_ty: ?[]const u8,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (!installed) return error.UnsupportedLowering;
    return emit_expr(allocator, tokens, start_idx, end_idx, locals, ctx, expected_ty, out);
}

pub fn emitExprWithMoveContext(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    expected_ty: ?[]const u8,
    move_ctx: ?*const CallLastUseMoveContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    if (!installed) return error.UnsupportedLowering;
    return emit_expr_move(allocator, tokens, start_idx, end_idx, locals, ctx, expected_ty, move_ctx, out);
}

pub fn emitUserFuncCallWithMoveContext(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    func: FuncDecl,
    move_ctx: ?*const CallLastUseMoveContext,
    out: *std.ArrayList(u8),
) anyerror!bool {
    if (!installed) return error.UnsupportedLowering;
    return emit_user_func_call_move(allocator, tokens, start_idx, end_idx, locals, ctx, func, move_ctx, out);
}

pub fn emitBody(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_start: usize,
    locals: *const LocalSet,
    return_cleanup_locals: *const LocalSet,
    control_cleanup_locals: *const LocalSet,
    ctx: CodegenContext,
    result_tys: []const []const u8,
    result_items: []const FuncResultItem,
    result_struct: ?[]const u8,
    result_union: ?UnionLayout,
    loop_ctx: ?LoopControl,
    defer_ctx: ?*const DeferContext,
    return_label: ?[]const u8,
    self_tail_tco: ?*const SelfTailTco,
    out: *std.ArrayList(u8),
) anyerror!void {
    const f = emit_body orelse return error.UnsupportedLowering;
    return f(allocator, tokens, start_idx, end_idx, body_start, locals, return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, defer_ctx, return_label, self_tail_tco, out);
}

pub fn emitUnionValue(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    layout: UnionLayout,
    copy_managed: bool,
    move_ctx: ?*const CallLastUseMoveContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const f = emit_union_value orelse return error.UnsupportedLowering;
    return f(allocator, tokens, start_idx, end_idx, locals, ctx, layout, copy_managed, move_ctx, out);
}

pub fn collectBodyLocals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    out: *LocalSet,
) anyerror!void {
    const f = collect_body_locals orelse return error.UnsupportedLowering;
    return f(allocator, tokens, start_idx, end_idx, ctx, out);
}

pub fn collectBodyLocalsWithMode(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    out: *LocalSet,
    recurse_nested: bool,
) anyerror!void {
    const f = collect_body_locals_with_mode orelse return error.UnsupportedLowering;
    return f(allocator, tokens, start_idx, end_idx, ctx, out, recurse_nested);
}

pub fn emitMultiResultAssignment(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const f = emit_multi_result_assignment orelse return error.UnsupportedLowering;
    return f(allocator, tokens, start_idx, end_idx, body_end, allow_last_use_move, locals, defer_ctx, ctx, out);
}

pub fn emitBareUserFuncCall(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const f = emit_bare_user_func_call orelse return error.UnsupportedLowering;
    return f(allocator, tokens, start_idx, end_idx, locals, ctx, out);
}

pub fn emitBareUserFuncCallWithMoveContext(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const f = emit_bare_user_func_call_move orelse return error.UnsupportedLowering;
    return f(allocator, tokens, start_idx, end_idx, body_end, allow_last_use_move, locals, defer_ctx, ctx, out);
}

pub fn emitUserFuncCallWithUnionBindingMove(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    stmt_end: usize,
    body_end: usize,
    allow_last_use_move: bool,
    locals: *const LocalSet,
    defer_ctx: ?*const DeferContext,
    ctx: CodegenContext,
    func: FuncDecl,
    out: *std.ArrayList(u8),
) anyerror!bool {
    const f = emit_user_func_call_union_binding_move orelse return error.UnsupportedLowering;
    return f(allocator, tokens, start_idx, end_idx, stmt_end, body_end, allow_last_use_move, locals, defer_ctx, ctx, func, out);
}

pub fn emitUnionStructPayloadForType(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    name: []const u8,
    ty: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    copy_managed: bool,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const f = emit_union_struct_payload_for_type orelse return error.UnsupportedLowering;
    return f(allocator, tokens, name, ty, locals, ctx, copy_managed, out);
}
