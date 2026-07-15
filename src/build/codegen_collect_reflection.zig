//! Pure field-reflection and body-binding collection helpers.

const std = @import("std");
const lexer = @import("lexer.zig");
const codegen_tokens = @import("codegen_tokens.zig");
const codegen_names = @import("codegen_names.zig");
const model = @import("codegen_model.zig");
const context = @import("codegen_context.zig");
const codegen_collect_util = @import("codegen_collect_util.zig");
const codegen_imports = @import("codegen_imports.zig");
const codegen_storage_layout = @import("codegen_storage_layout.zig");
const codegen_callbacks = @import("codegen_callbacks.zig");
const codegen_ownership = @import("codegen_ownership.zig");

const tok_eq = codegen_tokens.tok_eq;
const find_matching_in_range = codegen_tokens.find_matching_in_range;
const find_top_level_block_open = codegen_tokens.find_top_level_block_open;
const find_top_level_token = codegen_tokens.find_top_level_token;
const find_arg_end = codegen_tokens.find_arg_end;
const find_stmt_end = codegen_tokens.find_stmt_end;
const trim_parens = codegen_tokens.trim_parens;
const module_tokens_equal = codegen_tokens.module_tokens_equal;
const public_decl_name = codegen_names.public_decl_name;
const string_token_body = codegen_tokens.string_token_body;
const expr_call_head = codegen_imports.expr_call_head;
const find_top_level_guard_loop_control = codegen_ownership.find_top_level_guard_loop_control;

const LocalSet = context.LocalSet;
const CodegenContext = context.CodegenContext;
const FieldReflectionIfParts = context.FieldReflectionIfParts;
const FieldStaticValue = context.FieldStaticValue;
const FieldMetaLocal = model.FieldMetaLocal;
const StructDecl = model.StructDecl;
const StructField = model.StructField;
const TypedStructBinding = model.TypedStructBinding;
const NilComparisonNarrowing = model.NilComparisonNarrowing;
const IsComparisonNarrowing = model.IsComparisonNarrowing;
const UnionLocal = model.UnionLocal;
const CodegenError = model.CodegenError;
const find_union_local = context.find_union_local;
const find_field_meta_local = codegen_storage_layout.find_field_meta_local;
const field_from_meta = codegen_storage_layout.field_from_meta;
const find_struct_decl = codegen_collect_util.find_struct_decl;
const parse_codegen_type_expr = codegen_collect_util.parse_codegen_type_expr;
const substitute_generic_type_owned = codegen_collect_util.substitute_generic_type_owned;
const infer_expr_type = codegen_storage_layout.infer_expr_type;
const find_union_branch_by_type = codegen_storage_layout.find_union_branch_by_type;

pub fn field_reflection_if_parts(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?FieldReflectionIfParts {
    if (start_idx + 4 > end_idx) return null;
    if (!tok_eq(tokens[start_idx], "if")) return null;
    const open_brace = find_top_level_block_open(tokens, start_idx + 1, end_idx) orelse return null;
    const close_brace = find_matching_in_range(tokens, open_brace, "{", "}", end_idx) catch return null;
    var parts = FieldReflectionIfParts{
        .cond_start = start_idx + 1,
        .cond_end = open_brace,
        .then_start = open_brace + 1,
        .then_end = close_brace,
    };
    if (close_brace + 1 == end_idx) return parts;
    if (close_brace + 1 >= end_idx or !tok_eq(tokens[close_brace + 1], "else")) return null;
    if (close_brace + 2 >= end_idx) return null;
    if (tok_eq(tokens[close_brace + 2], "if")) {
        parts.else_if_start = close_brace + 2;
        return parts;
    }
    if (!tok_eq(tokens[close_brace + 2], "{")) return null;
    const close_else = find_matching_in_range(tokens, close_brace + 2, "{", "}", end_idx) catch return null;
    if (close_else + 1 != end_idx) return null;
    parts.else_start = close_brace + 3;
    parts.else_end = close_else;
    return parts;
}

pub fn field_static_values_equal(left: FieldStaticValue, right: FieldStaticValue) bool {
    return switch (left) {
        .bool => |left_bool| switch (right) {
            .bool => |right_bool| left_bool == right_bool,
            else => false,
        },
        .int => |left_int| switch (right) {
            .int => |right_int| left_int == right_int,
            else => false,
        },
        .text => |left_text| switch (right) {
            .text => |right_text| std.mem.eql(u8, left_text, right_text),
            else => false,
        },
    };
}

pub fn single_field_meta_arg(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet) ?FieldMetaLocal {
    const arg_end = find_arg_end(tokens, start_idx, end_idx);
    if (arg_end != end_idx) return null;
    const range = trim_parens(tokens, start_idx, arg_end);
    if (range.end != range.start + 1) return null;
    if (tokens[range.start].kind != .ident) return null;
    return find_field_meta_local(locals.field_meta_locals.items, tokens[range.start].lexeme);
}

pub fn field_static_value(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext) ?FieldStaticValue {
    const range = trim_parens(tokens, start_idx, end_idx);
    if (range.start >= range.end) return null;

    if (range.end == range.start + 1) {
        const tok = tokens[range.start];
        if (tok.kind == .number) return .{ .int = std.fmt.parseUnsigned(usize, tok.lexeme, 10) catch return null };
        if (tok.kind == .string) return .{ .text = string_token_body(tok.lexeme) orelse return null };
        if (tok_eq(tok, "true")) return .{ .bool = true };
        if (tok_eq(tok, "false")) return .{ .bool = false };
        return null;
    }

    const call_head = expr_call_head(tokens, range) orelse return null;
    if (!call_head.is_intrinsic) return null;
    const call_name = tokens[call_head.name_idx].lexeme;
    if (std.mem.eql(u8, call_name, "field_name")) {
        const meta = single_field_meta_arg(tokens, call_head.args_start, call_head.args_end, locals) orelse return null;
        const field = field_from_meta(ctx, meta) orelse return null;
        return .{ .text = public_decl_name(field.name) };
    }
    if (std.mem.eql(u8, call_name, "field_index")) {
        const meta = single_field_meta_arg(tokens, call_head.args_start, call_head.args_end, locals) orelse return null;
        return .{ .int = meta.visible_index };
    }
    if (std.mem.eql(u8, call_name, "field_has_default")) {
        const meta = single_field_meta_arg(tokens, call_head.args_start, call_head.args_end, locals) orelse return null;
        const field = field_from_meta(ctx, meta) orelse return null;
        return .{ .bool = field.default_start != null };
    }
    return null;
}

pub fn field_static_bool_expr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext) ?bool {
    if (field_static_value(tokens, start_idx, end_idx, locals, ctx)) |value| {
        return switch (value) {
            .bool => |boolean| boolean,
            else => null,
        };
    }

    const range = trim_parens(tokens, start_idx, end_idx);
    const call_head = expr_call_head(tokens, range) orelse return null;
    const call_name = tokens[call_head.name_idx].lexeme;
    if (call_head.is_intrinsic and std.mem.eql(u8, call_name, "not")) {
        const arg_end = find_arg_end(tokens, call_head.args_start, call_head.args_end);
        if (arg_end != call_head.args_end) return null;
        return !(field_static_bool_expr(tokens, call_head.args_start, arg_end, locals, ctx) orelse return null);
    }
    if (call_head.is_intrinsic and (std.mem.eql(u8, call_name, "and") or std.mem.eql(u8, call_name, "or"))) {
        var arg_start = call_head.args_start;
        var saw_arg = false;
        while (arg_start < call_head.args_end) {
            const arg_end = find_arg_end(tokens, arg_start, call_head.args_end);
            const value = field_static_bool_expr(tokens, arg_start, arg_end, locals, ctx) orelse return null;
            saw_arg = true;
            if (std.mem.eql(u8, call_name, "and") and !value) return false;
            if (std.mem.eql(u8, call_name, "or") and value) return true;
            arg_start = arg_end;
            if (arg_start < call_head.args_end and tok_eq(tokens[arg_start], ",")) arg_start += 1;
        }
        if (!saw_arg) return null;
        return std.mem.eql(u8, call_name, "and");
    }
    if (call_head.is_intrinsic and (std.mem.eql(u8, call_name, "eq") or std.mem.eql(u8, call_name, "ne"))) {
        const first_end = find_arg_end(tokens, call_head.args_start, call_head.args_end);
        if (first_end >= call_head.args_end or !tok_eq(tokens[first_end], ",")) return null;
        const second_start = first_end + 1;
        const second_end = find_arg_end(tokens, second_start, call_head.args_end);
        if (second_end != call_head.args_end) return null;
        const left = field_static_value(tokens, call_head.args_start, first_end, locals, ctx) orelse return null;
        const right = field_static_value(tokens, second_start, second_end, locals, ctx) orelse return null;
        const equal = field_static_values_equal(left, right);
        return if (std.mem.eql(u8, call_name, "eq")) equal else !equal;
    }
    return null;
}

pub fn collect_field_reflection_static_if(allocator: std.mem.Allocator, tokens: []const lexer.Token, i: usize, stmt_end: usize, ctx: CodegenContext, out: *LocalSet) CodegenError!bool {
    const parts = field_reflection_if_parts(tokens, i, stmt_end) orelse return false;
    const condition = field_static_bool_expr(tokens, parts.cond_start, parts.cond_end, out, ctx) orelse return false;
    try collect_field_reflection_static_branch(allocator, tokens, parts, condition, stmt_end, ctx, out);
    return true;
}

pub fn collect_field_reflection_static_branch(allocator: std.mem.Allocator, tokens: []const lexer.Token, parts: FieldReflectionIfParts, condition: bool, stmt_end: usize, ctx: CodegenContext, out: *LocalSet) CodegenError!void {
    if (condition) {
        try collect_field_reflection_body_locals(allocator, tokens, parts.then_start, parts.then_end, ctx, out);
        return;
    }
    if (parts.else_if_start) |nested_if| {
        try collect_field_reflection_body_locals(allocator, tokens, nested_if, stmt_end, ctx, out);
        return;
    }
    if (parts.else_start) |else_start| {
        try collect_field_reflection_body_locals(allocator, tokens, else_start, parts.else_end, ctx, out);
    }
}

pub fn collect_field_reflection_body_locals(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext, out: *LocalSet) CodegenError!void {
    var i = start_idx;
    while (i < end_idx) {
        const stmt_end = find_stmt_end(tokens, i, end_idx);
        if (try collect_field_reflection_static_if(allocator, tokens, i, stmt_end, ctx, out)) {
            i = stmt_end;
            continue;
        }
        try codegen_callbacks.collect_body_locals(allocator, tokens, i, stmt_end, ctx, out);
        try apply_collect_guard_return_narrowing(allocator, tokens, i, stmt_end, out, ctx);
        try apply_guard_loop_control_narrowing(allocator, tokens, i, stmt_end, out, ctx);
        i = stmt_end;
    }
}

pub fn nil_comparison_narrowing(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet) ?NilComparisonNarrowing {
    const range = trim_parens(tokens, start_idx, end_idx);
    const call_head = expr_call_head(tokens, range) orelse return null;
    if (!call_head.is_intrinsic) return null;
    const call_name = tokens[call_head.name_idx].lexeme;
    if (!std.mem.eql(u8, call_name, "eq") and !std.mem.eql(u8, call_name, "ne")) return null;

    const first_end = find_arg_end(tokens, call_head.args_start, call_head.args_end);
    if (first_end == call_head.args_start or first_end >= call_head.args_end or !tok_eq(tokens[first_end], ",")) return null;
    const second_start = first_end + 1;
    const second_end = find_arg_end(tokens, second_start, call_head.args_end);
    if (second_end != call_head.args_end) return null;

    const left_ident = single_ident_expr(tokens, call_head.args_start, first_end);
    const right_ident = single_ident_expr(tokens, second_start, second_end);
    const left_nil = single_nil_expr(tokens, call_head.args_start, first_end);
    const right_nil = single_nil_expr(tokens, second_start, second_end);
    const name = if (left_ident != null and right_nil)
        left_ident.?
    else if (right_ident != null and left_nil)
        right_ident.?
    else
        return null;

    const union_local = find_union_local(locals.union_locals.items, name) orelse return null;
    const payload_ty = union_local_single_non_nil_payload_type(union_local) orelse return null;
    return .{
        .union_local = union_local,
        .payload_ty = payload_ty,
        .non_nil_when_true = std.mem.eql(u8, call_name, "ne"),
    };
}

pub fn is_comparison_narrowing(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext) CodegenError!?IsComparisonNarrowing {
    const range = trim_parens(tokens, start_idx, end_idx);
    const call_head = expr_call_head(tokens, range) orelse return null;
    if (!call_head.is_intrinsic) return null;
    if (!std.mem.eql(u8, tokens[call_head.name_idx].lexeme, "is")) return null;

    const first_end = find_arg_end(tokens, call_head.args_start, call_head.args_end);
    if (first_end != call_head.args_start + 1 or tokens[call_head.args_start].kind != .ident) return null;
    if (first_end >= call_head.args_end or !tok_eq(tokens[first_end], ",")) return null;
    const union_local = find_union_local(locals.union_locals.items, tokens[call_head.args_start].lexeme) orelse return null;
    const type_start = first_end + 1;
    const type_end = trim_trailing_comma(tokens, type_start, call_head.args_end);
    if (type_start >= type_end) return null;

    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    const parsed_ty = (try parse_codegen_type_expr(allocator, tokens, type_start, type_end, &owned_types)) orelse return null;
    if (parsed_ty.next_idx != type_end) return null;
    const target_ty = try substitute_generic_type_owned(allocator, parsed_ty.ty, ctx.type_bindings, &owned_types);
    if (std.mem.eql(u8, target_ty, "nil")) return null;
    const branch = find_union_branch_by_type(union_local.layout, target_ty) orelse return null;
    if (branch.tag == 0 and std.mem.eql(u8, branch.ty, "nil")) return null;
    return .{
        .union_local = union_local,
        .payload_ty = branch.payload_type orelse branch.ty,
    };
}

pub fn single_ident_expr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    const range = trim_parens(tokens, start_idx, end_idx);
    if (range.end != range.start + 1) return null;
    if (tokens[range.start].kind != .ident) return null;
    return tokens[range.start].lexeme;
}

pub fn single_nil_expr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    const range = trim_parens(tokens, start_idx, end_idx);
    return range.end == range.start + 1 and tok_eq(tokens[range.start], "nil");
}

pub fn union_local_single_non_nil_payload_type(union_local: UnionLocal) ?[]const u8 {
    var matched: ?[]const u8 = null;
    for (union_local.layout.branches) |branch| {
        if (std.mem.eql(u8, branch.ty, "nil")) continue;
        if (matched != null) return null;
        matched = branch.ty;
    }
    return matched;
}

pub fn union_local_single_remaining_payload_type(union_local: UnionLocal, excluded_ty: []const u8) ?[]const u8 {
    var matched: ?[]const u8 = null;
    for (union_local.layout.branches) |branch| {
        if (std.mem.eql(u8, branch.ty, "nil")) continue;
        if (std.mem.eql(u8, branch.ty, excluded_ty)) continue;
        if (matched != null) return null;
        matched = branch.ty;
    }
    return matched;
}

pub fn trim_trailing_comma(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) usize {
    if (start_idx < end_idx and tok_eq(tokens[end_idx - 1], ",")) return end_idx - 1;
    return end_idx;
}

pub fn apply_guard_return_nil_narrowing(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *LocalSet) !void {
    if (start_idx >= end_idx or !tok_eq(tokens[start_idx], "if")) return;
    const return_idx = find_top_level_token(tokens, start_idx + 1, end_idx, "return") orelse return;
    const narrowing = nil_comparison_narrowing(tokens, start_idx + 1, return_idx, locals) orelse return;
    if (narrowing.non_nil_when_true) return;
    try locals.append_narrowed_union_local(allocator, narrowing.union_local, narrowing.payload_ty);
}

pub fn apply_guard_return_is_narrowing(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *LocalSet, ctx: CodegenContext) !void {
    if (start_idx >= end_idx or !tok_eq(tokens[start_idx], "if")) return;
    const return_idx = find_top_level_token(tokens, start_idx + 1, end_idx, "return") orelse return;
    const narrowing = try is_comparison_narrowing(allocator, tokens, start_idx + 1, return_idx, locals, ctx) orelse return;
    const payload_ty = union_local_single_remaining_payload_type(narrowing.union_local, narrowing.payload_ty) orelse return;
    try locals.append_narrowed_union_local(allocator, narrowing.union_local, payload_ty);
}

pub fn apply_guard_loop_control_narrowing(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *LocalSet, ctx: CodegenContext) !void {
    if (start_idx >= end_idx or !tok_eq(tokens[start_idx], "if")) return;
    const control_idx = find_top_level_guard_loop_control(tokens, start_idx + 1, end_idx) orelse return;

    if (nil_comparison_narrowing(tokens, start_idx + 1, control_idx, locals)) |narrowing| {
        if (!narrowing.non_nil_when_true) {
            try locals.append_narrowed_union_local(allocator, narrowing.union_local, narrowing.payload_ty);
        }
    }

    if (try is_comparison_narrowing(allocator, tokens, start_idx + 1, control_idx, locals, ctx)) |narrowing| {
        const payload_ty = union_local_single_remaining_payload_type(narrowing.union_local, narrowing.payload_ty) orelse return;
        try locals.append_narrowed_union_local(allocator, narrowing.union_local, payload_ty);
    }
}

pub fn apply_collect_guard_return_narrowing(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *LocalSet, ctx: CodegenContext) !void {
    try apply_guard_return_nil_narrowing(allocator, tokens, start_idx, end_idx, locals);
    try apply_guard_return_is_narrowing(allocator, tokens, start_idx, end_idx, locals, ctx);
}

pub fn field_visible_from_tokens(field: StructField, decl: StructDecl, tokens: []const lexer.Token) bool {
    if (!is_private_field_name(field.name)) return true;
    return module_tokens_equal(decl.tokens, tokens);
}

pub fn is_private_field_name(name: []const u8) bool {
    return name.len > 1 and name[0] == '.';
}

pub fn typed_struct_binding(allocator: std.mem.Allocator, tokens: []const lexer.Token, start_idx: usize, end_idx: usize, ctx: CodegenContext, owned_types: *std.ArrayList([]const u8)) CodegenError!?TypedStructBinding {
    if (start_idx + 3 >= end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    const eq_idx = find_top_level_token(tokens, start_idx + 1, end_idx, "=") orelse return null;
    if (eq_idx <= start_idx + 1) return null;
    const parsed_ty = (try parse_codegen_type_expr(allocator, tokens, start_idx + 1, eq_idx, owned_types)) orelse return null;
    if (parsed_ty.next_idx != eq_idx) return null;
    const ty = try substitute_generic_type_owned(allocator, parsed_ty.ty, ctx.type_bindings, owned_types);
    const decl = find_struct_decl(ctx.structs, ty) orelse return null;
    return .{ .decl = decl, .ty = ty };
}

pub fn inferred_struct_binding(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, locals: *const LocalSet, ctx: CodegenContext) ?TypedStructBinding {
    if (start_idx + 3 > end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    if (!tok_eq(tokens[start_idx + 1], "=")) return null;
    const ty = infer_expr_type(tokens, start_idx + 2, end_idx, locals, ctx) orelse return null;
    const decl = find_struct_decl(ctx.structs, ty) orelse return null;
    return .{ .decl = decl, .ty = ty };
}
