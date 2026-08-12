//! Restricted synchronous Wasm-GC lowering used by the migration gate.
//!
//! This module intentionally has a small admitted surface.  It lowers scalar
//! values, `text`, and `[u8]` values with typed GC references and fails closed
//! for aggregates, resources, host calls, and async syntax.  The normal ARC
//! pipeline remains the default until the later migration gates are closed.
const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const payload_wat = @import("wat_payload.zig");
const type_name = @import("type_name.zig");
const codegen_tokens = @import("codegen_tokens.zig");
const codegen_names = @import("codegen_names.zig");
const codegen_model = @import("codegen_model.zig");
const codegen_context = @import("codegen_context.zig");
const codegen_collect_structs = @import("codegen_collect_structs.zig");
const codegen_collect_functions = @import("codegen_collect_functions.zig");
const codegen_body = @import("codegen_body.zig");
const gc_adapter = @import("codegen_gc_sync_adapter.zig");
const gc_roots = @import("codegen_gc_roots.zig");
const runtime_gc_prelude = @import("runtime_gc_prelude_wat.zig");

const FuncDecl = codegen_model.FuncDecl;
const StructDecl = codegen_model.StructDecl;
const StructLayout = codegen_model.StructLayout;
const LocalSet = codegen_context.LocalSet;
const CodegenContext = codegen_context.CodegenContext;
const StringDataContext = codegen_context.StringDataContext;
const ImportedAliasContext = codegen_model.ImportedAliasContext;

const tok_eq = codegen_tokens.tok_eq;
const find_matching = codegen_tokens.find_matching;
const find_matching_in_range = codegen_tokens.find_matching_in_range;
const find_stmt_end = codegen_tokens.find_stmt_end;
const find_top_level_block_open = codegen_tokens.find_top_level_block_open;
const find_arg_end = codegen_tokens.find_arg_end;
const trim_parens = codegen_tokens.trim_parens;
const find_start_func = codegen_tokens.find_start_func;
const find_local_name = codegen_context.find_local_name;
const find_local_type = codegen_context.find_local_type;
const public_decl_name = codegen_names.public_decl_name;

const INDENT = "    ";

const DeferredCall = struct {
    start_idx: usize,
    end_idx: usize,
};

const CallShape = struct {
    name_idx: usize,
    open_idx: usize,
    close_idx: usize,
};

const BodyEmitter = struct {
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    functions: []const FuncDecl,
    locals: *const LocalSet,
    out: *std.ArrayList(u8),
    label_id: usize = 0,
    active_break_label: ?[]const u8 = null,
    active_loop_label: ?[]const u8 = null,

    fn append(self: *BodyEmitter, comptime fmt: []const u8, args: anytype) !void {
        const text = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(text);
        try self.out.appendSlice(self.allocator, text);
    }

    fn next_label(self: *BodyEmitter, prefix: []const u8) ![]u8 {
        const id = self.label_id;
        self.label_id += 1;
        return try std.fmt.allocPrint(self.allocator, "__gc_{s}_{d}", .{ prefix, id });
    }

    fn find_func(self: *BodyEmitter, name: []const u8) ?FuncDecl {
        for (self.functions) |func| {
            if (std.mem.eql(u8, public_decl_name(func.name), public_decl_name(name))) return func;
        }
        return null;
    }

    fn parse_call(self: *BodyEmitter, start_idx: usize, end_idx: usize) ?CallShape {
        if (start_idx + 2 > end_idx) return null;
        if (self.tokens[start_idx].kind != .ident or !tok_eq(self.tokens[start_idx + 1], "(")) return null;
        const close_idx = find_matching(self.tokens, start_idx + 1, "(", ")") catch return null;
        if (close_idx + 1 != end_idx) return null;
        return .{ .name_idx = start_idx, .open_idx = start_idx + 1, .close_idx = close_idx };
    }

    fn ensure_compatible(expected: ?[]const u8, actual: []const u8) !void {
        const wanted = expected orelse return;
        if (std.mem.eql(u8, wanted, actual)) return;
        if (type_name.is_core_wasm_scalar(wanted) and type_name.is_core_wasm_scalar(actual) and
            std.mem.eql(u8, payload_wat.wasm_type(wanted), payload_wat.wasm_type(actual))) return;
        return error.GcSyncTypeMismatch;
    }

    fn emit_literal(self: *BodyEmitter, token: lexer.Token) ![]const u8 {
        if (token.kind == .string) {
            const bytes = try codegen_tokens.decode_quoted_string_token(self.allocator, token.lexeme);
            defer self.allocator.free(bytes);
            try self.append(INDENT ++ "i32.const {d}\n", .{bytes.len});
            if (bytes.len == 0) {
                try self.append(INDENT ++ "array.new_default $do_bytes\n", .{});
            } else {
                for (bytes) |byte| try self.append(INDENT ++ "i32.const {d}\n", .{byte});
                try self.append(INDENT ++ "array.new_fixed $do_bytes {d}\n", .{bytes.len});
            }
            try self.append(INDENT ++ "struct.new $do_text\n", .{});
            return "text";
        }
        return error.UnsupportedGcSyncExpression;
    }

    fn emit_call_expr(self: *BodyEmitter, shape: CallShape, expected: ?[]const u8) anyerror![]const u8 {
        const name = self.tokens[shape.name_idx].lexeme;
        const func = self.find_func(name) orelse return error.UnsupportedGcSyncCall;
        if (func.is_async or func.contains_await) return error.UnsupportedGcSyncCall;

        var arg_idx = shape.open_idx + 1;
        var param_idx: usize = 0;
        while (arg_idx < shape.close_idx) {
            if (param_idx >= func.params.len) return error.GcSyncArityMismatch;
            const arg_end = find_arg_end(self.tokens, arg_idx, shape.close_idx);
            if (arg_end <= arg_idx) return error.GcSyncArityMismatch;
            _ = try self.emit_expr(arg_idx, arg_end, func.params[param_idx].ty);
            param_idx += 1;
            arg_idx = arg_end;
            if (arg_idx < shape.close_idx and tok_eq(self.tokens[arg_idx], ",")) arg_idx += 1;
        }
        if (param_idx != func.params.len) return error.GcSyncArityMismatch;
        try self.append(INDENT ++ "call ${s}\n", .{func.name});
        if (func.results.len == 0) {
            if (expected != null) return error.GcSyncTypeMismatch;
            return "nil";
        }
        if (func.results.len != 1) return error.UnsupportedGcSyncResult;
        try ensure_compatible(expected, func.results[0]);
        return func.results[0];
    }

    fn emit_expr(self: *BodyEmitter, start_idx: usize, end_idx: usize, expected: ?[]const u8) anyerror![]const u8 {
        const range = trim_parens(self.tokens, start_idx, end_idx);
        if (range.start >= range.end) return error.UnsupportedGcSyncExpression;
        if (range.start + 1 == range.end) {
            const token = self.tokens[range.start];
            if (token.kind == .string) {
                const actual = try self.emit_literal(token);
                try ensure_compatible(expected, actual);
                return actual;
            }
            if (token.kind == .number) {
                const ty = expected orelse "i32";
                if (!type_name.is_core_wasm_scalar(ty)) return error.GcSyncTypeMismatch;
                const wasm_ty = try wasm_type_for(ty);
                try self.append(INDENT ++ "{s}.const {s}\n", .{ wasm_ty, token.lexeme });
                return ty;
            }
            if (token.kind == .ident) {
                if (std.mem.eql(u8, token.lexeme, "true") or std.mem.eql(u8, token.lexeme, "false")) {
                    const ty = expected orelse "bool";
                    try ensure_compatible(expected, "bool");
                    try self.append(INDENT ++ "i32.const {d}\n", .{@intFromBool(std.mem.eql(u8, token.lexeme, "true"))});
                    return ty;
                }
                if (std.mem.eql(u8, token.lexeme, "nil")) return "nil";
                const local_name = find_local_name(self.locals.locals.items, token.lexeme) orelse return error.UnknownGcSyncLocal;
                const local_ty = find_local_type(self.locals.locals.items, token.lexeme) orelse return error.UnknownGcSyncLocal;
                try ensure_compatible(expected, local_ty);
                try self.append(INDENT ++ "local.get ${s}\n", .{local_name});
                return local_ty;
            }
            return error.UnsupportedGcSyncExpression;
        }

        const shape = self.parse_call(range.start, range.end) orelse return error.UnsupportedGcSyncExpression;
        return self.emit_call_expr(shape, expected);
    }

    fn emit_deferred(self: *BodyEmitter, deferred: []const DeferredCall) !void {
        var idx = deferred.len;
        while (idx > 0) {
            idx -= 1;
            const call = deferred[idx];
            const result_ty = try self.emit_expr(call.start_idx, call.end_idx, null);
            if (!std.mem.eql(u8, result_ty, "nil")) try self.append(INDENT ++ "drop\n", .{});
        }
    }

    fn emit_return(self: *BodyEmitter, start_idx: usize, end_idx: usize, result_ty: ?[]const u8, deferred: *std.ArrayList(DeferredCall)) anyerror!void {
        try self.emit_deferred(deferred.items);
        if (start_idx + 1 == end_idx) {
            if (result_ty != null) return error.MissingGcSyncReturn;
            try self.append(INDENT ++ "return\n", .{});
            return;
        }
        if (result_ty) |ty| if (gc_adapter.is_admitted_managed_type(ty)) try self.append(INDENT ++ ";; gc-root return_value\n", .{});
        const actual = try self.emit_expr(start_idx + 1, end_idx, result_ty);
        if (result_ty == null or std.mem.eql(u8, actual, "nil")) return error.UnexpectedGcSyncReturn;
        try self.append(INDENT ++ "return\n", .{});
    }

    fn emit_if(self: *BodyEmitter, start_idx: usize, end_idx: usize, result_ty: ?[]const u8, deferred: *std.ArrayList(DeferredCall)) anyerror!void {
        const open_idx = find_top_level_block_open(self.tokens, start_idx + 1, end_idx) orelse return error.UnsupportedGcSyncControl;
        const close_idx = find_matching_in_range(self.tokens, open_idx, "{", "}", end_idx) catch return error.UnsupportedGcSyncControl;
        if (close_idx >= end_idx) return error.UnsupportedGcSyncControl;
        _ = try self.emit_expr(start_idx + 1, open_idx, "bool");
        try self.append(INDENT ++ "if\n", .{});
        _ = try self.emit_body(open_idx + 1, close_idx, result_ty, deferred);
        if (close_idx + 1 < end_idx and tok_eq(self.tokens[close_idx + 1], "else")) {
            const else_open = find_top_level_block_open(self.tokens, close_idx + 2, end_idx) orelse return error.UnsupportedGcSyncControl;
            const else_close = find_matching_in_range(self.tokens, else_open, "{", "}", end_idx) catch return error.UnsupportedGcSyncControl;
            try self.append(INDENT ++ "else\n", .{});
            _ = try self.emit_body(else_open + 1, else_close, result_ty, deferred);
        }
        try self.append(INDENT ++ "end\n" ++ INDENT ++ ";; gc-root branch_join\n", .{});
    }

    fn emit_loop(self: *BodyEmitter, start_idx: usize, end_idx: usize, result_ty: ?[]const u8, deferred: *std.ArrayList(DeferredCall)) anyerror!void {
        const open_idx = find_top_level_block_open(self.tokens, start_idx + 1, end_idx) orelse return error.UnsupportedGcSyncControl;
        const close_idx = find_matching_in_range(self.tokens, open_idx, "{", "}", end_idx) catch return error.UnsupportedGcSyncControl;
        if (close_idx + 1 != end_idx) return error.UnsupportedGcSyncControl;
        const break_label = try self.next_label("break");
        defer self.allocator.free(break_label);
        const loop_label = try self.next_label("loop");
        defer self.allocator.free(loop_label);
        const previous_break = self.active_break_label;
        const previous_loop = self.active_loop_label;
        self.active_break_label = break_label;
        self.active_loop_label = loop_label;
        defer {
            self.active_break_label = previous_break;
            self.active_loop_label = previous_loop;
        }
        try self.append(INDENT ++ "block ${s}\n" ++ INDENT ++ "loop ${s}\n", .{ break_label, loop_label });
        _ = try self.emit_body(open_idx + 1, close_idx, result_ty, deferred);
        try self.append(INDENT ++ "end\n" ++ INDENT ++ "end\n" ++ INDENT ++ ";; gc-root loop_join\n", .{});
    }

    fn emit_assignment(self: *BodyEmitter, start_idx: usize, end_idx: usize) !void {
        if (start_idx >= end_idx or self.tokens[start_idx].kind != .ident) return error.UnsupportedGcSyncStatement;
        var eq_idx: ?usize = null;
        var expr_start: usize = 0;
        if (start_idx + 2 < end_idx and tok_eq(self.tokens[start_idx + 2], "=")) {
            eq_idx = start_idx + 2;
            expr_start = start_idx + 3;
        } else if (start_idx + 1 < end_idx and tok_eq(self.tokens[start_idx + 1], "=")) {
            eq_idx = start_idx + 1;
            expr_start = start_idx + 2;
        }
        _ = eq_idx orelse return error.UnsupportedGcSyncStatement;
        const target_name = find_local_name(self.locals.locals.items, self.tokens[start_idx].lexeme) orelse return error.UnknownGcSyncLocal;
        const target_ty = find_local_type(self.locals.locals.items, self.tokens[start_idx].lexeme) orelse return error.UnknownGcSyncLocal;
        if (gc_adapter.is_admitted_managed_type(target_ty)) try self.append(INDENT ++ ";; gc-root overwrite ${s}\n", .{target_name});
        _ = try self.emit_expr(expr_start, end_idx, target_ty);
        try self.append(INDENT ++ "local.set ${s}\n", .{target_name});
    }

    fn emit_body(self: *BodyEmitter, start_idx: usize, end_idx: usize, result_ty: ?[]const u8, deferred: *std.ArrayList(DeferredCall)) anyerror!bool {
        const inherited_defer_count = deferred.items.len;
        var i = start_idx;
        var saw_return = false;
        while (i < end_idx) {
            const stmt_end = find_stmt_end(self.tokens, i, end_idx);
            if (stmt_end <= i) return error.UnsupportedGcSyncStatement;
            if (tok_eq(self.tokens[i], "if")) {
                try self.emit_if(i, stmt_end, result_ty, deferred);
            } else if (tok_eq(self.tokens[i], "loop")) {
                try self.emit_loop(i, stmt_end, result_ty, deferred);
            } else if (tok_eq(self.tokens[i], "defer")) {
                if (i + 1 >= stmt_end) return error.UnsupportedGcSyncStatement;
                try deferred.append(self.allocator, .{ .start_idx = i + 1, .end_idx = stmt_end });
            } else if (tok_eq(self.tokens[i], "return")) {
                try self.emit_return(i, stmt_end, result_ty, deferred);
                saw_return = true;
                break;
            } else if (tok_eq(self.tokens[i], "break")) {
                try self.emit_deferred(deferred.items[inherited_defer_count..]);
                deferred.shrinkRetainingCapacity(inherited_defer_count);
                try self.append(INDENT ++ "br ${s}\n", .{self.active_break_label orelse return error.UnsupportedGcSyncControl});
            } else if (tok_eq(self.tokens[i], "continue")) {
                try self.emit_deferred(deferred.items[inherited_defer_count..]);
                deferred.shrinkRetainingCapacity(inherited_defer_count);
                try self.append(INDENT ++ "br ${s}\n", .{self.active_loop_label orelse return error.UnsupportedGcSyncControl});
            } else if (self.tokens[i].kind == .ident and ((i + 1 < stmt_end and tok_eq(self.tokens[i + 1], "=")) or (i + 2 < stmt_end and tok_eq(self.tokens[i + 2], "=")))) {
                try self.emit_assignment(i, stmt_end);
            } else {
                const result = try self.emit_expr(i, stmt_end, null);
                if (!std.mem.eql(u8, result, "nil")) try self.append(INDENT ++ "drop\n", .{});
            }
            i = stmt_end;
        }
        if (!saw_return) try self.emit_deferred(deferred.items[inherited_defer_count..]);
        deferred.shrinkRetainingCapacity(inherited_defer_count);
        return saw_return;
    }
};

fn is_supported_type(ty: []const u8) bool {
    return gc_adapter.is_supported_type(ty);
}

fn wasm_type_for(ty: []const u8) ![]const u8 {
    return gc_adapter.wasm_type_for(ty);
}

fn append_fmt(allocator: std.mem.Allocator, out: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}

fn append_root_point_name(point: gc_roots.RootPoint) []const u8 {
    return switch (point) {
        .local_bind => "local_bind",
        .overwrite => "overwrite",
        .branch_join => "branch_join",
        .loop_join => "loop_join",
        .return_value => "return_value",
        .suspend_frame => "suspend_frame",
        .resume_frame => "resume_frame",
        .cancel_frame => "cancel_frame",
        .terminal => "terminal",
    };
}

fn append_function_signature(allocator: std.mem.Allocator, out: *std.ArrayList(u8), func: FuncDecl) !void {
    try append_fmt(allocator, out, "  (func ${s}", .{func.name});
    for (func.params) |param| {
        if (param.callback != null) return error.UnsupportedGcSyncCallback;
        if (!is_supported_type(param.ty) or std.mem.eql(u8, param.ty, "nil")) return error.UnsupportedGcSyncType;
        try append_fmt(allocator, out, " (param ${s} {s})", .{ param.name, try wasm_type_for(param.ty) });
    }
    if (func.results.len > 1) return error.UnsupportedGcSyncResult;
    if (func.results.len == 1) {
        if (!is_supported_type(func.results[0]) or std.mem.eql(u8, func.results[0], "nil")) return error.UnsupportedGcSyncType;
        try append_fmt(allocator, out, " (result {s})", .{try wasm_type_for(func.results[0])});
    }
    try out.appendSlice(allocator, "\n");
}

fn append_func_params(allocator: std.mem.Allocator, func: FuncDecl, locals: *LocalSet) !void {
    for (func.params) |param| {
        if (param.callback != null) return error.UnsupportedGcSyncCallback;
        try locals.append_borrowed_local_with_origin(allocator, param.name, param.ty, false, .param_or_import);
    }
}

fn append_gc_locals(allocator: std.mem.Allocator, out: *std.ArrayList(u8), locals: *const LocalSet) !void {
    for (locals.locals.items) |local| {
        if (!local.emit_decl) continue;
        if (!is_supported_type(local.ty) or std.mem.eql(u8, local.ty, "nil")) return error.UnsupportedGcSyncType;
        try append_fmt(allocator, out, INDENT ++ "(local ${s} {s})\n", .{ local.name, try wasm_type_for(local.ty) });
    }
}

fn emit_func(allocator: std.mem.Allocator, out: *std.ArrayList(u8), func: FuncDecl, functions: []const FuncDecl, base_ctx: CodegenContext) !void {
    try append_function_signature(allocator, out, func);
    var locals = LocalSet{};
    defer locals.deinit(allocator);
    try append_func_params(allocator, func, &locals);
    try codegen_body.collect_body_locals(allocator, func.tokens, func.body_start, func.body_end, base_ctx, &locals);

    var root_locals = std.ArrayList(gc_roots.RootLocal).empty;
    defer root_locals.deinit(allocator);
    for (locals.locals.items) |local| {
        if (!is_supported_type(local.ty) or std.mem.eql(u8, local.ty, "nil")) return error.UnsupportedGcSyncType;
        const rep = (try gc_adapter.classify_admitted_type(local.ty, &.{})).rep;
        try root_locals.append(allocator, .{ .name = local.name, .rep = rep });
    }
    const root_plan = try gc_roots.build_root_plan(allocator, root_locals.items, .synchronous);
    defer gc_roots.deinit_root_plan(allocator, root_plan);

    try append_gc_locals(allocator, out, &locals);
    for (root_plan.slots) |slot| {
        try append_fmt(allocator, out, INDENT ++ ";; gc-root {s} ${s}\n", .{ append_root_point_name(slot.point), slot.name });
    }

    var emitter = BodyEmitter{ .allocator = allocator, .tokens = func.tokens, .functions = functions, .locals = &locals, .out = out };
    var deferred = std.ArrayList(DeferredCall).empty;
    defer deferred.deinit(allocator);
    if (func.arrow) {
        if (func.results.len != 1) return error.UnsupportedGcSyncResult;
        _ = try emitter.emit_expr(func.body_start, func.body_end, func.results[0]);
        try out.appendSlice(allocator, INDENT ++ "return\n");
    } else {
        const result_ty = if (func.results.len == 1) func.results[0] else null;
        const saw_return = try emitter.emit_body(func.body_start, func.body_end, result_ty, &deferred);
        if (result_ty != null and !saw_return) try out.appendSlice(allocator, INDENT ++ "unreachable\n");
    }
    try out.appendSlice(allocator, "  )\n");
}

fn emit_start(allocator: std.mem.Allocator, out: *std.ArrayList(u8), tokens: []const lexer.Token, functions: []const FuncDecl, base_ctx: CodegenContext) !void {
    const start_idx = find_start_func(tokens) orelse return;
    const close_params = try find_matching(tokens, start_idx + 1, "(", ")");
    const open_body = find_top_level_block_open(tokens, close_params + 1, tokens.len) orelse return error.UnsupportedGcSyncControl;
    const close_body = try find_matching(tokens, open_body, "{", "}");

    var locals = LocalSet{};
    defer locals.deinit(allocator);
    try codegen_body.collect_body_locals(allocator, tokens, open_body + 1, close_body, base_ctx, &locals);
    var root_locals = std.ArrayList(gc_roots.RootLocal).empty;
    defer root_locals.deinit(allocator);
    for (locals.locals.items) |local| {
        if (!is_supported_type(local.ty) or std.mem.eql(u8, local.ty, "nil")) return error.UnsupportedGcSyncType;
        const rep = (try gc_adapter.classify_admitted_type(local.ty, &.{})).rep;
        try root_locals.append(allocator, .{ .name = local.name, .rep = rep });
    }
    const root_plan = try gc_roots.build_root_plan(allocator, root_locals.items, .synchronous);
    defer gc_roots.deinit_root_plan(allocator, root_plan);

    try out.appendSlice(allocator, "  (func $_start\n");
    try append_gc_locals(allocator, out, &locals);
    for (root_plan.slots) |slot| try append_fmt(allocator, out, INDENT ++ ";; gc-root {s} ${s}\n", .{ append_root_point_name(slot.point), slot.name });
    var emitter = BodyEmitter{ .allocator = allocator, .tokens = tokens, .functions = functions, .locals = &locals, .out = out };
    var deferred = std.ArrayList(DeferredCall).empty;
    defer deferred.deinit(allocator);
    _ = try emitter.emit_body(open_body + 1, close_body, null, &deferred);
    try out.appendSlice(allocator, "  )\n  (export \"_start\" (func $_start))\n");
}

pub fn emit_gc_wat_for_supported_program(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) ![]u8 {
    if (module_graph != null) return error.UnsupportedGcSyncModuleGraph;
    if (tokens.len == 0) return error.UnsupportedGcSyncProgram;

    var structs = std.ArrayList(StructDecl).empty;
    defer {
        codegen_model.free_struct_decls(allocator, structs.items);
        structs.deinit(allocator);
    }
    try codegen_collect_structs.collect_struct_decls(allocator, tokens, &structs);
    if (structs.items.len != 0) return error.UnsupportedGcSyncAggregate;

    const struct_layouts: []const StructLayout = &.{};
    var functions = std.ArrayList(FuncDecl).empty;
    defer {
        codegen_model.free_func_decls(allocator, functions.items);
        functions.deinit(allocator);
    }
    const imported_alias_ctx: ?ImportedAliasContext = null;
    try codegen_collect_functions.collect_func_decls(allocator, tokens, structs.items, struct_layouts, imported_alias_ctx, &functions);
    for (functions.items, 0..) |func, idx| {
        if (func.is_generic_template) return error.UnsupportedGcSyncGeneric;
        for (functions.items[0..idx]) |previous| {
            if (std.mem.eql(u8, previous.name, func.name)) return error.UnsupportedGcSyncOverload;
        }
        if (func.is_async or func.contains_await) return error.UnsupportedGcSyncAsync;
        for (func.params) |param| if (!is_supported_type(param.ty) or std.mem.eql(u8, param.ty, "nil")) return error.UnsupportedGcSyncType;
        for (func.results) |result| if (!is_supported_type(result) or std.mem.eql(u8, result, "nil")) return error.UnsupportedGcSyncType;
    }

    var string_data = StringDataContext{};
    defer string_data.deinit(allocator);
    const base_ctx = CodegenContext{
        .functions = functions.items,
        .structs = structs.items,
        .struct_layouts = struct_layouts,
        .value_enums = &.{},
        .payload_enums = &.{},
        .host_imports = &.{},
        .wasi_imports = &.{},
        .string_data = &string_data,
        .entry_tokens = tokens,
        .modules = &.{},
    };

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, "(module\n");
    try append_fmt(allocator, &out, "  ;; gc-sync source_len={d} token_count={d}\n", .{ program.source_len, program.token_count });
    try runtime_gc_prelude.emit_text_prelude(allocator, &out);
    for (functions.items) |func| try emit_func(allocator, &out, func, functions.items, base_ctx);
    try emit_start(allocator, &out, tokens, functions.items, base_ctx);
    try out.appendSlice(allocator, ")\n");
    return out.toOwnedSlice(allocator);
}
