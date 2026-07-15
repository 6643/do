//! Late-bound emit callbacks to break gen domain import cycles.
const std = @import("std");
const lexer = @import("lexer.zig");
const model = @import("codegen_model.zig");
const context = @import("codegen_context.zig");
const codegen_union_layout = @import("codegen_union_layout.zig");

const LocalSet = context.LocalSet;
const CodegenContext = context.CodegenContext;
const CodegenError = model.CodegenError;
const FuncDecl = model.FuncDecl;
const FuncResultItem = model.FuncResultItem;
const CallLastUseMoveContext = context.CallLastUseMoveContext;
const DeferContext = context.DeferContext;
const LoopControl = context.LoopControl;
const SelfTailTco = context.SelfTailTco;
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

var emit_expr_hook: EmitExprFn = undefined;
var emit_expr_move_hook: EmitExprMoveFn = undefined;
var emit_user_func_call_move_hook: EmitUserFuncCallMoveFn = undefined;
var emit_body_hook: ?EmitBodyFn = null;
var emit_union_value_hook: ?EmitUnionValueFn = null;
var collect_body_locals_hook: ?CollectBodyLocalsFn = null;
var collect_body_locals_with_mode_hook: ?CollectBodyLocalsWithModeFn = null;
var emit_multi_result_assignment_hook: ?EmitMultiResultAssignmentFn = null;
var emit_bare_user_func_call_hook: ?EmitBareUserFuncCallFn = null;
var emit_bare_user_func_call_move_hook: ?EmitBareUserFuncCallMoveFn = null;
var emit_user_func_call_union_binding_move_hook: ?EmitUserFuncCallUnionBindingMoveFn = null;
var emit_union_struct_payload_for_type_hook: ?EmitUnionStructPayloadForTypeFn = null;

pub const InferGenericCallUnionResultFn = *const fn (
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    call_head: model.ExprCallHead,
    locals: *const LocalSet,
    ctx: CodegenContext,
    result_owned_types: *std.ArrayList([]const u8),
) CodegenError!?UnionLayout;

pub var infer_generic_call_union_result: ?InferGenericCallUnionResultFn = null;

pub fn install_infer_generic_call_union_result(f: InferGenericCallUnionResultFn) void {
    infer_generic_call_union_result = f;
}

pub var installed: bool = false;

pub fn install(
    expr: EmitExprFn,
    expr_move: EmitExprMoveFn,
    user_call_move: EmitUserFuncCallMoveFn,
) void {
    emit_expr_hook = expr;
    emit_expr_move_hook = expr_move;
    emit_user_func_call_move_hook = user_call_move;
    installed = true;
}

pub fn install_body(f: EmitBodyFn) void {
    emit_body_hook = f;
}
pub fn install_union_value(f: EmitUnionValueFn) void {
    emit_union_value_hook = f;
}
pub fn install_collect_body_locals(f: CollectBodyLocalsFn) void {
    collect_body_locals_hook = f;
}
pub fn install_collect_body_locals_with_mode(f: CollectBodyLocalsWithModeFn) void {
    collect_body_locals_with_mode_hook = f;
}
pub fn install_emit_multi_result_assignment(f: EmitMultiResultAssignmentFn) void {
    emit_multi_result_assignment_hook = f;
}
pub fn install_emit_bare_user_func_call(f: EmitBareUserFuncCallFn) void {
    emit_bare_user_func_call_hook = f;
}
pub fn install_emit_bare_user_func_call_move(f: EmitBareUserFuncCallMoveFn) void {
    emit_bare_user_func_call_move_hook = f;
}
pub fn install_emit_user_func_call_union_binding_move(f: EmitUserFuncCallUnionBindingMoveFn) void {
    emit_user_func_call_union_binding_move_hook = f;
}
pub fn install_emit_union_struct_payload_for_type(f: EmitUnionStructPayloadForTypeFn) void {
    emit_union_struct_payload_for_type_hook = f;
}

pub fn emit_expr(
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
    return emit_expr_hook(allocator, tokens, start_idx, end_idx, locals, ctx, expected_ty, out);
}

pub fn emit_expr_with_move_context(
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
    return emit_expr_move_hook(allocator, tokens, start_idx, end_idx, locals, ctx, expected_ty, move_ctx, out);
}

pub fn emit_user_func_call_with_move_context(
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
    return emit_user_func_call_move_hook(allocator, tokens, start_idx, end_idx, locals, ctx, func, move_ctx, out);
}

pub fn emit_body(
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
    const f = emit_body_hook orelse return error.UnsupportedLowering;
    return f(allocator, tokens, start_idx, end_idx, body_start, locals, return_cleanup_locals, control_cleanup_locals, ctx, result_tys, result_items, result_struct, result_union, loop_ctx, defer_ctx, return_label, self_tail_tco, out);
}

pub fn emit_union_value(
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
    const f = emit_union_value_hook orelse return error.UnsupportedLowering;
    return f(allocator, tokens, start_idx, end_idx, locals, ctx, layout, copy_managed, move_ctx, out);
}

pub fn collect_body_locals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    out: *LocalSet,
) anyerror!void {
    const f = collect_body_locals_hook orelse return error.UnsupportedLowering;
    return f(allocator, tokens, start_idx, end_idx, ctx, out);
}

pub fn collect_body_locals_with_mode(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    ctx: CodegenContext,
    out: *LocalSet,
    recurse_nested: bool,
) anyerror!void {
    const f = collect_body_locals_with_mode_hook orelse return error.UnsupportedLowering;
    return f(allocator, tokens, start_idx, end_idx, ctx, out, recurse_nested);
}

pub fn emit_multi_result_assignment(
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
    const f = emit_multi_result_assignment_hook orelse return error.UnsupportedLowering;
    return f(allocator, tokens, start_idx, end_idx, body_end, allow_last_use_move, locals, defer_ctx, ctx, out);
}

pub fn emit_bare_user_func_call(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    locals: *const LocalSet,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const f = emit_bare_user_func_call_hook orelse return error.UnsupportedLowering;
    return f(allocator, tokens, start_idx, end_idx, locals, ctx, out);
}

pub fn emit_bare_user_func_call_with_move_context(
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
    const f = emit_bare_user_func_call_move_hook orelse return error.UnsupportedLowering;
    return f(allocator, tokens, start_idx, end_idx, body_end, allow_last_use_move, locals, defer_ctx, ctx, out);
}

pub fn emit_user_func_call_with_union_binding_move(
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
    const f = emit_user_func_call_union_binding_move_hook orelse return error.UnsupportedLowering;
    return f(allocator, tokens, start_idx, end_idx, stmt_end, body_end, allow_last_use_move, locals, defer_ctx, ctx, func, out);
}

pub fn emit_union_struct_payload_for_type(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    name: []const u8,
    ty: []const u8,
    locals: *const LocalSet,
    ctx: CodegenContext,
    copy_managed: bool,
    out: *std.ArrayList(u8),
) CodegenError!bool {
    const f = emit_union_struct_payload_for_type_hook orelse return error.UnsupportedLowering;
    return f(allocator, tokens, name, ty, locals, ctx, copy_managed, out);
}
