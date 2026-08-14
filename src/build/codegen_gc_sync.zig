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
const codegen_collect_declarations = @import("codegen_collect_declarations.zig");
const codegen_collect_functions = @import("codegen_collect_functions.zig");
const codegen_generics = @import("codegen_generics.zig");
const codegen_body = @import("codegen_body.zig");
const gc_adapter = @import("codegen_gc_sync_adapter.zig");
const gc_model_adapter = @import("codegen_gc_model_adapter.zig");
const gc_roots = @import("codegen_gc_roots.zig");
const runtime_gc_prelude = @import("runtime_gc_prelude_wat.zig");
const gc_layout = @import("codegen_gc_layout.zig");
const gc_representation = @import("codegen_gc_representation.zig");
const codegen_imports = @import("codegen_imports.zig");
const test_runner = @import("test_runner.zig");
const wat_function_body = @import("wat_function_body.zig");

const FuncDecl = codegen_model.FuncDecl;
const StructDecl = codegen_model.StructDecl;
const StructLayout = codegen_model.StructLayout;
const PayloadEnumDecl = codegen_model.PayloadEnumDecl;
const LocalSet = codegen_context.LocalSet;
const CodegenContext = codegen_context.CodegenContext;
const StringDataContext = codegen_context.StringDataContext;
const ImportedAliasContext = codegen_model.ImportedAliasContext;
const TestDecl = test_runner.TestDecl;

const tok_eq = codegen_tokens.tok_eq;
const find_matching = codegen_tokens.find_matching;
const find_matching_in_range = codegen_tokens.find_matching_in_range;
const find_stmt_end = codegen_tokens.find_stmt_end;
const find_line_end = codegen_tokens.find_line_end;
const find_top_level_block_open = codegen_tokens.find_top_level_block_open;
const find_arg_end = codegen_tokens.find_arg_end;
const find_top_level_token = codegen_tokens.find_top_level_token;
const trim_parens = codegen_tokens.trim_parens;
const find_start_func = codegen_tokens.find_start_func;
const find_local_name = codegen_context.find_local_name;
const find_local_type = codegen_context.find_local_type;
const public_decl_name = codegen_names.public_decl_name;
const find_root_module_index = codegen_imports.find_root_module_index;

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

const GcListTemps = struct {
    bytes_next_name: []u8,
    scalar_next_names: [gc_layout.scalar_array_specs.len][]u8,
    has_scalar_arrays: [gc_layout.scalar_array_specs.len]bool,
    length_name: []u8,

    fn deinit(self: GcListTemps, allocator: std.mem.Allocator) void {
        allocator.free(self.bytes_next_name);
        for (self.scalar_next_names) |name| allocator.free(name);
        allocator.free(self.length_name);
    }
};

const BodyEmitter = struct {
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    functions: []const FuncDecl,
    gc_structs: []const gc_representation.StructShape,
    gc_layouts: []const gc_layout.GcStructLayout,
    gc_payload_unions: []const gc_layout.GcPayloadUnionLayout,
    locals: *const LocalSet,
    out: *std.ArrayList(u8),
    gc_list_temps: GcListTemps,
    label_id: usize = 0,
    active_break_label: ?[]const u8 = null,
    active_loop_label: ?[]const u8 = null,

    fn append(self: *BodyEmitter, comptime fmt: []const u8, args: anytype) !void {
        const text = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(text);
        try self.out.appendSlice(self.allocator, text);
    }

    fn list_next_name(self: *const BodyEmitter, list_ty: []const u8) ![]const u8 {
        if (std.mem.eql(u8, list_ty, "[u8]")) return self.gc_list_temps.bytes_next_name;
        for (gc_layout.scalar_array_specs, 0..) |spec, index| {
            if (std.mem.eql(u8, list_ty, spec.list_ty)) return self.gc_list_temps.scalar_next_names[index];
        }
        return error.UnsupportedGcSyncType;
    }

    fn list_array_name(self: *const BodyEmitter, list_ty: []const u8) ![]const u8 {
        _ = self;
        if (std.mem.eql(u8, list_ty, "[u8]")) return "$do_bytes";
        const spec = gc_layout.scalar_array_spec_for_type(list_ty) orelse return error.UnsupportedGcSyncType;
        return spec.array_name;
    }

    fn next_label(self: *BodyEmitter, prefix: []const u8) ![]u8 {
        const id = self.label_id;
        self.label_id += 1;
        return try std.fmt.allocPrint(self.allocator, "__gc_{s}_{d}", .{ prefix, id });
    }

    fn find_func(self: *BodyEmitter, name: []const u8, expected: ?[]const u8) ?FuncDecl {
        for (self.functions) |func| {
            if (!func.is_generic_template and std.mem.eql(u8, public_decl_name(func.name), public_decl_name(name))) return func;
        }
        for (self.functions) |func| {
            if (func.is_generic_template or !std.mem.eql(u8, public_decl_name(func.source_name), public_decl_name(name))) continue;
            if (expected == null or (func.results.len == 1 and std.mem.eql(u8, func.results[0], expected.?))) return func;
        }
        return null;
    }

    fn find_payload_union(self: *BodyEmitter, name: []const u8) ?gc_layout.GcPayloadUnionLayout {
        return find_gc_payload_union(self.gc_payload_unions, name);
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

    fn validate_numeric_literal(ty: []const u8, raw: []const u8) !void {
        if (std.mem.eql(u8, ty, "bool")) return error.GcSyncTypeMismatch;
        if (type_name.is_float_type_name(ty)) {
            _ = std.fmt.parseFloat(f64, raw) catch return error.GcSyncTypeMismatch;
            return;
        }
        if (!type_name.is_integer_type_name(ty)) return error.GcSyncTypeMismatch;
        const value = std.fmt.parseInt(i128, raw, 10) catch return error.GcSyncTypeMismatch;
        if (std.mem.eql(u8, ty, "i8")) {
            if (value < std.math.minInt(i8) or value > std.math.maxInt(i8)) return error.GcSyncTypeMismatch;
        } else if (std.mem.eql(u8, ty, "i16")) {
            if (value < std.math.minInt(i16) or value > std.math.maxInt(i16)) return error.GcSyncTypeMismatch;
        } else if (std.mem.eql(u8, ty, "i32")) {
            if (value < std.math.minInt(i32) or value > std.math.maxInt(i32)) return error.GcSyncTypeMismatch;
        } else if (std.mem.eql(u8, ty, "i64")) {
            if (value < std.math.minInt(i64) or value > std.math.maxInt(i64)) return error.GcSyncTypeMismatch;
        } else if (std.mem.eql(u8, ty, "u8")) {
            if (value < 0 or value > std.math.maxInt(u8)) return error.GcSyncTypeMismatch;
        } else if (std.mem.eql(u8, ty, "u16")) {
            if (value < 0 or value > std.math.maxInt(u16)) return error.GcSyncTypeMismatch;
        } else if (std.mem.eql(u8, ty, "u32")) {
            if (value < 0 or value > std.math.maxInt(u32)) return error.GcSyncTypeMismatch;
        } else if (std.mem.eql(u8, ty, "u64")) {
            if (value < 0 or value > std.math.maxInt(u64)) return error.GcSyncTypeMismatch;
        } else if (std.mem.eql(u8, ty, "isize")) {
            if (value < std.math.minInt(i32) or value > std.math.maxInt(i32)) return error.GcSyncTypeMismatch;
        } else if (std.mem.eql(u8, ty, "usize")) {
            if (value < 0 or value > std.math.maxInt(u32)) return error.GcSyncTypeMismatch;
        }
    }

    fn emit_literal(self: *BodyEmitter, token: lexer.Token) ![]const u8 {
        if (token.kind == .string) {
            const bytes = try codegen_tokens.decode_quoted_string_token(self.allocator, token.lexeme);
            defer self.allocator.free(bytes);
            try self.append(INDENT ++ "i32.const {d}\n", .{bytes.len});
            if (bytes.len == 0) {
                try self.append(INDENT ++ "i32.const 0\n", .{});
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

    fn emit_byte_list_literal(self: *BodyEmitter, start_idx: usize, end_idx: usize, expected: ?[]const u8) ![]const u8 {
        const list_ty = expected orelse return error.UnsupportedGcSyncType;
        const array_name = try self.list_array_name(list_ty);
        const elem_ty = type_name.storage_elem_type_from_name(list_ty) orelse return error.UnsupportedGcSyncType;
        if (!type_name.is_core_wasm_scalar(elem_ty)) return error.UnsupportedGcSyncType;
        if (start_idx + 2 > end_idx or !tok_eq(self.tokens[start_idx], ".") or !tok_eq(self.tokens[start_idx + 1], "{")) {
            return error.UnsupportedGcSyncExpression;
        }
        const close_brace = find_matching_in_range(self.tokens, start_idx + 1, "{", "}", end_idx) catch return error.UnsupportedGcSyncExpression;
        if (close_brace + 1 != end_idx) return error.UnsupportedGcSyncExpression;

        var count: usize = 0;
        var item_start = start_idx + 2;
        while (item_start < close_brace) {
            if (tok_eq(self.tokens[item_start], ",")) {
                item_start += 1;
                continue;
            }
            const item_end = find_arg_end(self.tokens, item_start, close_brace);
            if (item_end == item_start + 2 and tok_eq(self.tokens[item_start], "-") and self.tokens[item_start + 1].kind == .number) {
                return error.GcSyncTypeMismatch;
            }
            if (item_end <= item_start or item_end != item_start + 1) {
                return error.UnsupportedGcSyncExpression;
            }
            const token = self.tokens[item_start];
            if (std.mem.eql(u8, elem_ty, "bool")) {
                if (token.kind != .ident or
                    (!std.mem.eql(u8, token.lexeme, "true") and !std.mem.eql(u8, token.lexeme, "false")))
                {
                    return error.GcSyncTypeMismatch;
                }
                try self.append(INDENT ++ "i32.const {d}\n", .{@intFromBool(std.mem.eql(u8, token.lexeme, "true"))});
            } else {
                if (token.kind != .number) return error.UnsupportedGcSyncExpression;
                const value = token.lexeme;
                try validate_numeric_literal(elem_ty, value);
                try self.append(INDENT ++ "{s}.const {s}\n", .{ payload_wat.wasm_type(elem_ty), value });
            }
            count += 1;
            item_start = item_end;
            if (item_start < close_brace and tok_eq(self.tokens[item_start], ",")) item_start += 1;
        }

        if (count == 0) {
            try self.append(INDENT ++ "i32.const 0\n    array.new_default ", .{});
            try self.append("{s}\n", .{array_name});
        } else {
            try self.append(INDENT ++ "array.new_fixed {s} {d}\n", .{ array_name, count });
        }
        return list_ty;
    }

    fn emit_call_expr(self: *BodyEmitter, shape: CallShape, expected: ?[]const u8) anyerror![]const u8 {
        const name = self.tokens[shape.name_idx].lexeme;
        const func = self.find_func(name, expected) orelse return error.UnsupportedGcSyncCall;
        if (func.is_async or func.contains_await) return error.UnsupportedGcSyncCall;

        var arg_idx = shape.open_idx + 1;
        var param_idx: usize = 0;
        while (arg_idx < shape.close_idx) {
            if (param_idx >= func.params.len) return error.GcSyncArityMismatch;
            const arg_end = find_arg_end(self.tokens, arg_idx, shape.close_idx);
            if (arg_end <= arg_idx) return error.GcSyncArityMismatch;
            const actual_ty = try self.emit_expr(arg_idx, arg_end, func.params[param_idx].ty);
            if (!std.mem.eql(u8, actual_ty, func.params[param_idx].ty)) return error.GcSyncTypeMismatch;
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
        if (gc_adapter.is_admitted_managed_type_with_layouts_and_unions(
            func.results[0],
            self.gc_structs,
            self.gc_layouts,
            self.gc_payload_unions,
        )) {
            try self.append(INDENT ++ ";; gc-root call_result\n", .{});
        }
        try ensure_compatible(expected, func.results[0]);
        return func.results[0];
    }

    fn emit_payload_union_ctor(self: *BodyEmitter, start_idx: usize, end_idx: usize, expected: ?[]const u8) anyerror!?[]const u8 {
        const expected_ty = expected orelse return null;
        const layout = self.find_payload_union(expected_ty) orelse return null;
        if (start_idx + 1 == end_idx and self.tokens[start_idx].kind == .ident and
            std.mem.eql(u8, self.tokens[start_idx].lexeme, layout.unit_case))
        {
            try self.append(INDENT ++ "i32.const {d}\n    ref.null $do_bytes\n    struct.new $", .{layout.unit_tag});
            for (layout.name) |ch| try self.out.append(self.allocator, std.ascii.toLower(ch));
            try self.out.appendSlice(self.allocator, "\n");
            return expected_ty;
        }
        const shape = self.parse_call(start_idx, end_idx) orelse return null;
        const case_name = self.tokens[shape.name_idx].lexeme;
        if (std.mem.eql(u8, case_name, layout.unit_case)) return error.UnsupportedGcSyncUnionConstructor;
        if (!std.mem.eql(u8, case_name, layout.managed_case)) return null;
        const arg_start = shape.open_idx + 1;
        if (arg_start >= shape.close_idx) return error.UnsupportedGcSyncUnionConstructor;
        const arg_end = find_arg_end(self.tokens, arg_start, shape.close_idx);
        if (arg_end != shape.close_idx) return error.UnsupportedGcSyncUnionConstructor;
        try self.append(INDENT ++ "i32.const {d}\n", .{layout.managed_tag});
        _ = try self.emit_expr(arg_start, arg_end, "[u8]");
        try self.append(INDENT ++ "struct.new $", .{});
        for (layout.name) |ch| try self.out.append(self.allocator, std.ascii.toLower(ch));
        try self.out.appendSlice(self.allocator, "\n");
        return expected_ty;
    }

    fn emit_get_field_expr(self: *BodyEmitter, start_idx: usize, end_idx: usize, expected: ?[]const u8) anyerror!?[]const u8 {
        if (start_idx + 1 >= end_idx or !tok_eq(self.tokens[start_idx], "@") or !tok_eq(self.tokens[start_idx + 1], "get")) return null;
        if (start_idx + 2 >= end_idx or !tok_eq(self.tokens[start_idx + 2], "(")) return null;
        const close_idx = find_matching_in_range(self.tokens, start_idx + 2, "(", ")", end_idx) catch return error.UnsupportedGcSyncExpression;
        if (close_idx + 1 != end_idx) return error.UnsupportedGcSyncExpression;
        const first_end = find_arg_end(self.tokens, start_idx + 3, close_idx);
        if (first_end >= close_idx or !tok_eq(self.tokens[first_end], ",")) return error.UnsupportedGcSyncExpression;
        const second_start = first_end + 1;
        if (second_start + 1 != close_idx or self.tokens[second_start].kind != .ident) return error.UnsupportedGcSyncExpression;
        const field_token = self.tokens[second_start];
        if (field_token.lexeme.len < 2 or field_token.lexeme[0] != '.') return error.UnsupportedGcSyncExpression;
        if (first_end != start_idx + 4 or self.tokens[start_idx + 3].kind != .ident) return error.UnsupportedGcSyncExpression;
        const local_name = find_local_name(self.locals.locals.items, self.tokens[start_idx + 3].lexeme) orelse return error.UnknownGcSyncLocal;
        const struct_ty = find_local_type(self.locals.locals.items, self.tokens[start_idx + 3].lexeme) orelse return error.UnknownGcSyncLocal;
        const layout = find_gc_layout(self.gc_layouts, struct_ty) orelse return error.UnsupportedGcSyncType;
        const field_name = field_token.lexeme[1..];
        const field = find_gc_field(layout, field_name) orelse return error.UnsupportedGcSyncExpression;
        const inline_scalar = field.rep == .inline_value and type_name.is_core_wasm_scalar(field.ty);
        const admitted_managed = field.rep == .gc_managed and
            (std.mem.eql(u8, field.ty, "[u8]") or
                std.mem.eql(u8, field.ty, "text") or
                find_gc_layout(self.gc_layouts, field.ty) != null);
        if (!inline_scalar and !admitted_managed) return error.UnsupportedGcSyncType;
        try ensure_compatible(expected, field.ty);
        try self.append(INDENT ++ "local.get ${s}\n    ref.as_non_null\n    struct.get $", .{local_name});
        for (layout.name) |ch| try self.out.append(self.allocator, std.ascii.toLower(ch));
        try self.append(" ${s}\n", .{public_decl_name(field.name)});
        return field.ty;
    }

    fn emit_get_tuple_expr(self: *BodyEmitter, start_idx: usize, end_idx: usize, expected: ?[]const u8) anyerror!?[]const u8 {
        if (start_idx + 1 >= end_idx or !tok_eq(self.tokens[start_idx], "@") or !tok_eq(self.tokens[start_idx + 1], "get")) return null;
        if (start_idx + 2 >= end_idx or !tok_eq(self.tokens[start_idx + 2], "(")) return null;
        const close_idx = find_matching_in_range(self.tokens, start_idx + 2, "(", ")", end_idx) catch return error.UnsupportedGcSyncExpression;
        if (close_idx + 1 != end_idx) return error.UnsupportedGcSyncExpression;
        const receiver_end = find_arg_end(self.tokens, start_idx + 3, close_idx);
        if (receiver_end != start_idx + 4 or receiver_end >= close_idx or !tok_eq(self.tokens[receiver_end], ",") or self.tokens[start_idx + 3].kind != .ident) return error.UnsupportedGcSyncExpression;
        const receiver_name = find_local_name(self.locals.locals.items, self.tokens[start_idx + 3].lexeme) orelse return error.UnknownGcSyncLocal;
        const receiver_ty = find_local_type(self.locals.locals.items, self.tokens[start_idx + 3].lexeme) orelse return error.UnknownGcSyncLocal;
        if (!gc_adapter.is_gc_sync_tuple_text_bytes(receiver_ty)) return null;
        const index_idx = receiver_end + 1;
        if (index_idx + 1 != close_idx or self.tokens[index_idx].kind != .number) return error.UnsupportedGcSyncExpression;
        const index = std.fmt.parseInt(u8, self.tokens[index_idx].lexeme, 10) catch return error.UnsupportedGcSyncExpression;
        const field_ty: []const u8 = switch (index) {
            0 => "text",
            1 => "[u8]",
            else => return error.UnsupportedGcSyncExpression,
        };
        try ensure_compatible(expected, field_ty);
        const field_name = if (index == 0) "text" else "bytes";
        try self.append(INDENT ++ "local.get ${s}\n    ref.as_non_null\n    struct.get $tuple_text_bytes ${s}\n", .{ receiver_name, field_name });
        return field_ty;
    }

    fn tuple_bytes_receiver_local(self: *BodyEmitter, start_idx: usize, end_idx: usize) anyerror!?[]const u8 {
        if (start_idx + 2 >= end_idx or !tok_eq(self.tokens[start_idx], "@") or !tok_eq(self.tokens[start_idx + 1], "get") or !tok_eq(self.tokens[start_idx + 2], "(")) return null;
        const close_idx = find_matching_in_range(self.tokens, start_idx + 2, "(", ")", end_idx) catch return null;
        if (close_idx + 1 != end_idx) return null;
        const receiver_end = find_arg_end(self.tokens, start_idx + 3, close_idx);
        if (receiver_end != start_idx + 4 or receiver_end >= close_idx or !tok_eq(self.tokens[receiver_end], ",") or self.tokens[start_idx + 3].kind != .ident) return null;
        const index_idx = receiver_end + 1;
        if (index_idx + 1 != close_idx or !tok_eq(self.tokens[index_idx], "1")) return null;
        const receiver_ty = find_local_type(self.locals.locals.items, self.tokens[start_idx + 3].lexeme) orelse return error.UnknownGcSyncLocal;
        if (!gc_adapter.is_gc_sync_tuple_text_bytes(receiver_ty)) return null;
        return find_local_name(self.locals.locals.items, self.tokens[start_idx + 3].lexeme) orelse error.UnknownGcSyncLocal;
    }

    fn emit_tuple_bytes_get(self: *BodyEmitter, tuple_name: []const u8) !void {
        try self.append(INDENT ++ "local.get ${s}\n    ref.as_non_null\n    struct.get $tuple_text_bytes $bytes\n", .{tuple_name});
    }

    fn emit_tuple_text_bytes_constructor(self: *BodyEmitter, start_idx: usize, end_idx: usize, expected: ?[]const u8) anyerror!?[]const u8 {
        if (expected == null or !gc_adapter.is_gc_sync_tuple_text_bytes(expected.?)) return null;
        if (start_idx + 8 >= end_idx or !tok_eq(self.tokens[start_idx], "Tuple") or !tok_eq(self.tokens[start_idx + 1], "<")) return null;
        const close_angle = find_matching_in_range(self.tokens, start_idx + 1, "<", ">", end_idx) catch return error.UnsupportedGcSyncExpression;
        if (close_angle != start_idx + 7 or !tok_eq(self.tokens[start_idx + 2], "text") or !tok_eq(self.tokens[start_idx + 3], ",") or !tok_eq(self.tokens[start_idx + 4], "[") or !tok_eq(self.tokens[start_idx + 5], "u8") or !tok_eq(self.tokens[start_idx + 6], "]")) return error.UnsupportedGcSyncType;
        if (close_angle + 1 >= end_idx or !tok_eq(self.tokens[close_angle + 1], "{")) return error.UnsupportedGcSyncExpression;
        const close_brace = find_matching_in_range(self.tokens, close_angle + 1, "{", "}", end_idx) catch return error.UnsupportedGcSyncExpression;
        if (close_brace + 1 != end_idx) return error.UnsupportedGcSyncExpression;
        var element_start = close_angle + 2;
        const first_end = find_arg_end(self.tokens, element_start, close_brace);
        if (first_end >= close_brace or !tok_eq(self.tokens[first_end], ",")) return error.UnsupportedGcSyncExpression;
        _ = try self.emit_expr(element_start, first_end, "text");
        element_start = first_end + 1;
        const second_end = find_arg_end(self.tokens, element_start, close_brace);
        if (second_end != close_brace) return error.UnsupportedGcSyncExpression;
        _ = try self.emit_expr(element_start, second_end, "[u8]");
        try self.append(INDENT ++ "struct.new $tuple_text_bytes\n", .{});
        return expected.?;
    }

    fn emit_set_field_expr(self: *BodyEmitter, start_idx: usize, end_idx: usize, expected: ?[]const u8) anyerror!?[]const u8 {
        if (start_idx + 1 >= end_idx or !tok_eq(self.tokens[start_idx], "@") or !tok_eq(self.tokens[start_idx + 1], "set")) return null;
        if (start_idx + 2 >= end_idx or !tok_eq(self.tokens[start_idx + 2], "(")) return null;
        const close_idx = find_matching_in_range(self.tokens, start_idx + 2, "(", ")", end_idx) catch return error.UnsupportedGcSyncExpression;
        if (close_idx + 1 != end_idx) return error.UnsupportedGcSyncExpression;

        const target_end = find_arg_end(self.tokens, start_idx + 3, close_idx);
        if (target_end >= close_idx or !tok_eq(self.tokens[target_end], ",")) return error.UnsupportedGcSyncExpression;
        if (try self.emit_set_tuple_bytes_expr(start_idx + 3, target_end, close_idx, expected)) |tuple_ty| return tuple_ty;
        if (target_end != start_idx + 4 or self.tokens[start_idx + 3].kind != .ident) return error.UnsupportedGcSyncExpression;
        const source_token = self.tokens[start_idx + 3];
        const local_name = find_local_name(self.locals.locals.items, source_token.lexeme) orelse return error.UnknownGcSyncLocal;
        const struct_ty = find_local_type(self.locals.locals.items, source_token.lexeme) orelse return error.UnknownGcSyncLocal;
        if (std.mem.eql(u8, struct_ty, "[u8]") or gc_layout.scalar_array_spec_for_type(struct_ty) != null) {
            return @as(?[]const u8, try self.emit_set_scalar_list_expr(local_name, struct_ty, target_end, close_idx, expected));
        }
        const layout = find_gc_layout(self.gc_layouts, struct_ty) orelse return error.UnsupportedGcSyncType;

        const field_start = target_end + 1;
        const field_end = find_arg_end(self.tokens, field_start, close_idx);
        if (field_end != field_start + 1 or self.tokens[field_start].kind != .ident) return error.UnsupportedGcSyncExpression;
        const field_token = self.tokens[field_start];
        if (field_token.lexeme.len < 2 or field_token.lexeme[0] != '.') return error.UnsupportedGcSyncExpression;
        if (field_end >= close_idx or !tok_eq(self.tokens[field_end], ",")) return error.UnsupportedGcSyncExpression;
        const target_field_name = field_token.lexeme[1..];
        const target_field = find_gc_field(layout, target_field_name) orelse return error.UnsupportedGcSyncExpression;
        const scalar_field = target_field.rep == .inline_value and type_name.is_core_wasm_scalar(target_field.ty);
        const managed_byte_field = target_field.rep == .gc_managed and std.mem.eql(u8, target_field.ty, "[u8]");
        const managed_scalar_array_field = target_field.rep == .gc_managed and gc_layout.scalar_array_spec_for_type(target_field.ty) != null;
        const managed_text_field = target_field.rep == .gc_managed and std.mem.eql(u8, target_field.ty, "text");
        const managed_struct_field = target_field.rep == .gc_managed and find_gc_layout(self.gc_layouts, target_field.ty) != null;
        if (!scalar_field and !managed_byte_field and !managed_scalar_array_field and !managed_text_field and !managed_struct_field) return error.UnsupportedGcSyncType;

        const value_start = field_end + 1;
        if (value_start >= close_idx) return error.UnsupportedGcSyncExpression;
        const value_end = find_arg_end(self.tokens, value_start, close_idx);
        if (value_end != close_idx) return error.UnsupportedGcSyncExpression;
        try ensure_compatible(expected, struct_ty);
        if (managed_byte_field and !self.is_direct_local_of_type(value_start, value_end, "[u8]")) {
            return error.UnsupportedGcSyncProducer;
        }
        if (managed_scalar_array_field and !self.is_direct_local_of_type(value_start, value_end, target_field.ty)) {
            return error.UnsupportedGcSyncProducer;
        }
        if (managed_text_field and !self.is_direct_local_of_type(value_start, value_end, "text") and
            !(value_start + 1 == value_end and self.tokens[value_start].kind == .string))
        {
            return error.UnsupportedGcSyncProducer;
        }
        if (managed_struct_field and !self.is_direct_local_of_type(value_start, value_end, target_field.ty)) {
            return error.UnsupportedGcSyncProducer;
        }

        // Published values remain immutable: rebuild the aggregate and reuse
        // unchanged child references instead of mutating the source object.
        for (layout.fields) |field| {
            if (std.mem.eql(u8, public_decl_name(field.name), target_field_name)) {
                _ = try self.emit_expr(value_start, value_end, field.ty);
                continue;
            }
            try self.append(INDENT ++ "local.get ${s}\n    ref.as_non_null\n    struct.get $", .{local_name});
            for (layout.name) |ch| try self.out.append(self.allocator, std.ascii.toLower(ch));
            try self.append(" ${s}\n", .{public_decl_name(field.name)});
        }
        try self.append(INDENT ++ "struct.new $", .{});
        for (layout.name) |ch| try self.out.append(self.allocator, std.ascii.toLower(ch));
        try self.out.appendSlice(self.allocator, "\n");
        return struct_ty;
    }

    fn emit_set_tuple_bytes_expr(self: *BodyEmitter, receiver_start: usize, receiver_end: usize, close_idx: usize, expected: ?[]const u8) anyerror!?[]const u8 {
        const tuple_name = try self.tuple_bytes_receiver_local(receiver_start, receiver_end) orelse return null;
        const index_start = receiver_end + 1;
        if (index_start >= close_idx) return error.UnsupportedGcSyncExpression;
        const index_end = find_arg_end(self.tokens, index_start, close_idx);
        if (index_end >= close_idx or !tok_eq(self.tokens[index_end], ",")) return error.UnsupportedGcSyncExpression;
        const value_start = index_end + 1;
        if (value_start >= close_idx) return error.UnsupportedGcSyncExpression;
        const value_end = find_arg_end(self.tokens, value_start, close_idx);
        if (value_end != close_idx) return error.UnsupportedGcSyncExpression;
        try ensure_compatible(expected, "[u8]");

        try self.emit_tuple_bytes_get(tuple_name);
        const next_name = try self.list_next_name("[u8]");
        try self.append(INDENT ++ "ref.as_non_null\n    array.len\n    local.set ${s}\n", .{self.gc_list_temps.length_name});
        try self.append(INDENT ++ "local.get ${s}\n    i32.eqz\n    if unreachable end\n", .{self.gc_list_temps.length_name});
        try self.append(INDENT ++ "local.get ${s}\n    array.new_default $do_bytes\n    local.set ${s}\n", .{ self.gc_list_temps.length_name, next_name });
        try self.append(INDENT ++ "local.get ${s}\n    i32.const 0\n", .{next_name});
        try self.emit_tuple_bytes_get(tuple_name);
        try self.append(INDENT ++ "ref.as_non_null\n    i32.const 0\n    local.get ${s}\n    array.copy $do_bytes $do_bytes\n", .{self.gc_list_temps.length_name});
        try self.append(INDENT ++ "local.get ${s}\n", .{next_name});
        _ = try self.emit_expr(index_start, index_end, "usize");
        _ = try self.emit_expr(value_start, value_end, "u8");
        try self.append(INDENT ++ "array.set $do_bytes\n    local.get ${s}\n", .{next_name});
        return "[u8]";
    }

    fn is_direct_local_of_type(self: *BodyEmitter, start_idx: usize, end_idx: usize, expected: []const u8) bool {
        if (start_idx + 1 != end_idx or self.tokens[start_idx].kind != .ident) return false;
        const local_ty = find_local_type(self.locals.locals.items, self.tokens[start_idx].lexeme) orelse return false;
        return std.mem.eql(u8, local_ty, expected);
    }

    fn emit_set_byte_list_expr(
        self: *BodyEmitter,
        source_name: []const u8,
        target_end: usize,
        close_idx: usize,
        expected: ?[]const u8,
    ) anyerror![]const u8 {
        return self.emit_set_scalar_list_expr(source_name, "[u8]", target_end, close_idx, expected);
    }

    fn emit_set_scalar_list_expr(
        self: *BodyEmitter,
        source_name: []const u8,
        list_ty: []const u8,
        target_end: usize,
        close_idx: usize,
        expected: ?[]const u8,
    ) anyerror![]const u8 {
        const index_start = target_end + 1;
        if (index_start >= close_idx) return error.UnsupportedGcSyncExpression;
        const index_end = find_arg_end(self.tokens, index_start, close_idx);
        if (index_end >= close_idx or !tok_eq(self.tokens[index_end], ",")) return error.UnsupportedGcSyncExpression;
        const value_start = index_end + 1;
        if (value_start >= close_idx) return error.UnsupportedGcSyncExpression;
        const value_end = find_arg_end(self.tokens, value_start, close_idx);
        if (value_end != close_idx) return error.UnsupportedGcSyncExpression;
        try ensure_compatible(expected, list_ty);
        const elem_ty = type_name.storage_elem_type_from_name(list_ty) orelse return error.UnsupportedGcSyncType;
        const array_name = try self.list_array_name(list_ty);
        const next_name = try self.list_next_name(list_ty);

        // A published list is immutable. Make a private backing copy before
        // the only in-place array.set in this lowering path.
        try self.append(INDENT ++ "local.get ${s}\n    ref.as_non_null\n    array.len\n    local.set ${s}\n", .{ source_name, self.gc_list_temps.length_name });
        try self.append(INDENT ++ "local.get ${s}\n    i32.eqz\n    if unreachable end\n", .{self.gc_list_temps.length_name});
        try self.append(INDENT ++ "local.get ${s}\n    array.new_default {s}\n    local.set ${s}\n", .{ self.gc_list_temps.length_name, array_name, next_name });
        try self.append(INDENT ++ "local.get ${s}\n    i32.const 0\n    local.get ${s}\n    ref.as_non_null\n    i32.const 0\n    local.get ${s}\n    array.copy {s} {s}\n", .{ next_name, source_name, self.gc_list_temps.length_name, array_name, array_name });
        try self.append(INDENT ++ "local.get ${s}\n", .{next_name});
        _ = try self.emit_expr(index_start, index_end, "usize");
        const value_ty = try self.emit_expr(value_start, value_end, elem_ty);
        if (!std.mem.eql(u8, value_ty, elem_ty)) return error.UnsupportedGcSyncType;
        try self.append(INDENT ++ "array.set {s}\n    local.get ${s}\n", .{ array_name, next_name });
        return list_ty;
    }

    fn emit_put_byte_list_expr(
        self: *BodyEmitter,
        start_idx: usize,
        end_idx: usize,
        expected: ?[]const u8,
    ) anyerror!?[]const u8 {
        if (start_idx + 2 >= end_idx or !tok_eq(self.tokens[start_idx], "@") or !tok_eq(self.tokens[start_idx + 1], "put")) return null;
        if (!tok_eq(self.tokens[start_idx + 2], "(")) return error.UnsupportedGcSyncExpression;
        const close_idx = find_matching_in_range(self.tokens, start_idx + 2, "(", ")", end_idx) catch return error.UnsupportedGcSyncExpression;
        if (close_idx + 1 != end_idx) return error.UnsupportedGcSyncExpression;

        const receiver_end = find_arg_end(self.tokens, start_idx + 3, close_idx);
        if (receiver_end != start_idx + 4 or receiver_end >= close_idx or !tok_eq(self.tokens[receiver_end], ",") or self.tokens[start_idx + 3].kind != .ident) return error.UnsupportedGcSyncExpression;
        const receiver_name = find_local_name(self.locals.locals.items, self.tokens[start_idx + 3].lexeme) orelse return error.UnknownGcSyncLocal;
        const receiver_ty = find_local_type(self.locals.locals.items, self.tokens[start_idx + 3].lexeme) orelse return error.UnknownGcSyncLocal;
        if (!std.mem.eql(u8, receiver_ty, "[u8]")) return error.UnsupportedGcSyncType;

        const value_start = receiver_end + 1;
        if (value_start >= close_idx or tok_eq(self.tokens[value_start], "...")) return error.UnsupportedGcSyncExpression;
        const value_end = find_arg_end(self.tokens, value_start, close_idx);
        if (value_end != close_idx) return error.UnsupportedGcSyncExpression;
        if (value_end == value_start + 2 and tok_eq(self.tokens[value_start], "-") and self.tokens[value_start + 1].kind == .number) return error.GcSyncTypeMismatch;
        try ensure_compatible(expected, "[u8]");
        try self.ensure_exact_u8_put_value(value_start, value_end);
        const next_name = try self.list_next_name("[u8]");

        // Published lists remain immutable. Copy the source into a private
        // result backing, then append exactly one checked u8 element.
        try self.append(INDENT ++ "local.get ${s}\n    ref.as_non_null\n    array.len\n    local.set ${s}\n", .{ receiver_name, self.gc_list_temps.length_name });
        try self.append(INDENT ++ "local.get ${s}\n    i32.const 1\n    i32.add\n    array.new_default $do_bytes\n    local.set ${s}\n", .{ self.gc_list_temps.length_name, next_name });
        try self.append(INDENT ++ "local.get ${s}\n    i32.const 0\n    local.get ${s}\n    ref.as_non_null\n    i32.const 0\n    local.get ${s}\n    array.copy $do_bytes $do_bytes\n", .{ next_name, receiver_name, self.gc_list_temps.length_name });
        try self.append(INDENT ++ "local.get ${s}\n    local.get ${s}\n", .{ next_name, self.gc_list_temps.length_name });
        _ = try self.emit_expr(value_start, value_end, "u8");
        try self.append(INDENT ++ "array.set $do_bytes\n    local.get ${s}\n", .{next_name});
        return "[u8]";
    }

    fn ensure_exact_u8_put_value(self: *BodyEmitter, start_idx: usize, end_idx: usize) !void {
        if (start_idx + 1 == end_idx) {
            const token = self.tokens[start_idx];
            if (token.kind == .number) return;
            if (token.kind == .ident) {
                if (std.mem.eql(u8, token.lexeme, "true") or std.mem.eql(u8, token.lexeme, "false") or std.mem.eql(u8, token.lexeme, "nil")) return error.UnsupportedGcSyncType;
                const local_ty = find_local_type(self.locals.locals.items, token.lexeme) orelse return error.UnknownGcSyncLocal;
                if (!std.mem.eql(u8, local_ty, "u8")) return error.UnsupportedGcSyncType;
                return;
            }
            return error.UnsupportedGcSyncType;
        }
        const shape = self.parse_call(start_idx, end_idx) orelse return error.UnsupportedGcSyncExpression;
        const func = self.find_func(self.tokens[shape.name_idx].lexeme, "u8") orelse return error.UnsupportedGcSyncCall;
        if (func.results.len != 1 or !std.mem.eql(u8, func.results[0], "u8")) return error.UnsupportedGcSyncType;
    }

    fn emit_len_expr(self: *BodyEmitter, start_idx: usize, end_idx: usize, expected: ?[]const u8) anyerror!?[]const u8 {
        if (start_idx + 2 >= end_idx or !tok_eq(self.tokens[start_idx], "@") or !tok_eq(self.tokens[start_idx + 1], "len")) return null;
        if (!tok_eq(self.tokens[start_idx + 2], "(")) return error.UnsupportedGcSyncExpression;
        const close_idx = find_matching_in_range(self.tokens, start_idx + 2, "(", ")", end_idx) catch return error.UnsupportedGcSyncExpression;
        if (close_idx + 1 != end_idx) return error.UnsupportedGcSyncExpression;

        const arg_start = start_idx + 3;
        const arg_end = find_arg_end(self.tokens, arg_start, close_idx);
        if (arg_end != close_idx) return error.UnsupportedGcSyncExpression;
        const operand_ty = try self.emit_expr(arg_start, arg_end, null);
        const is_text = std.mem.eql(u8, operand_ty, "text");
        const is_list = std.mem.eql(u8, operand_ty, "[u8]") or gc_layout.scalar_array_spec_for_type(operand_ty) != null;
        if (!is_text and !is_list) return error.UnsupportedGcSyncType;
        try ensure_compatible(expected, "usize");
        if (is_text) {
            try self.append(INDENT ++ "ref.as_non_null\n    struct.get $do_text $length\n", .{});
        } else {
            try self.append(INDENT ++ "ref.as_non_null\n    array.len\n", .{});
        }
        return "usize";
    }

    fn emit_eq_expr(self: *BodyEmitter, start_idx: usize, end_idx: usize, expected: ?[]const u8) anyerror!?[]const u8 {
        if (start_idx + 2 >= end_idx or !tok_eq(self.tokens[start_idx], "@") or !tok_eq(self.tokens[start_idx + 1], "eq")) return null;
        if (!tok_eq(self.tokens[start_idx + 2], "(")) return error.UnsupportedGcSyncExpression;
        const close_idx = find_matching_in_range(self.tokens, start_idx + 2, "(", ")", end_idx) catch return error.UnsupportedGcSyncExpression;
        if (close_idx + 1 != end_idx) return error.UnsupportedGcSyncExpression;

        const first_end = find_arg_end(self.tokens, start_idx + 3, close_idx);
        if (first_end >= close_idx or !tok_eq(self.tokens[first_end], ",")) return error.UnsupportedGcSyncExpression;
        const second_start = first_end + 1;
        const second_end = find_arg_end(self.tokens, second_start, close_idx);
        if (second_end != close_idx) return error.UnsupportedGcSyncExpression;

        try ensure_compatible(expected, "bool");
        const left_ty = try self.emit_expr(start_idx + 3, first_end, null);
        if (!type_name.is_core_wasm_scalar(left_ty)) return error.UnsupportedGcSyncType;
        const right_ty = try self.emit_expr(second_start, second_end, left_ty);
        if (!std.mem.eql(u8, left_ty, right_ty)) return error.GcSyncTypeMismatch;

        const op = if (std.mem.eql(u8, payload_wat.wasm_type(left_ty), "i64"))
            "i64.eq"
        else if (std.mem.eql(u8, payload_wat.wasm_type(left_ty), "f32"))
            "f32.eq"
        else if (std.mem.eql(u8, payload_wat.wasm_type(left_ty), "f64"))
            "f64.eq"
        else
            "i32.eq";
        try self.append(INDENT ++ "{s}\n", .{op});
        return "bool";
    }

    fn emit_expr(self: *BodyEmitter, start_idx: usize, end_idx: usize, expected: ?[]const u8) anyerror![]const u8 {
        const range = trim_parens(self.tokens, start_idx, end_idx);
        if (range.start >= range.end) return error.UnsupportedGcSyncExpression;
        if (range.start + 1 < range.end and tok_eq(self.tokens[range.start], ".") and tok_eq(self.tokens[range.start + 1], "{")) {
            return self.emit_byte_list_literal(range.start, range.end, expected);
        }
        if (try self.emit_len_expr(range.start, range.end, expected)) |length_ty| return length_ty;
        if (try self.emit_eq_expr(range.start, range.end, expected)) |comparison_ty| return comparison_ty;
        if (try self.emit_put_byte_list_expr(range.start, range.end, expected)) |list_ty| return list_ty;
        if (try self.emit_get_tuple_expr(range.start, range.end, expected)) |field_ty| return field_ty;
        if (try self.emit_get_field_expr(range.start, range.end, expected)) |field_ty| return field_ty;
        if (try self.emit_set_field_expr(range.start, range.end, expected)) |struct_ty| return struct_ty;
        if (try self.emit_tuple_text_bytes_constructor(range.start, range.end, expected)) |tuple_ty| return tuple_ty;
        if (try self.emit_payload_union_ctor(range.start, range.end, expected)) |union_ty| return union_ty;
        if (range.start + 1 == range.end) {
            const token = self.tokens[range.start];
            if (token.kind == .string) {
                const actual = try self.emit_literal(token);
                try ensure_compatible(expected, actual);
                return actual;
            }
            if (token.kind == .number) {
                const ty = expected orelse "i32";
                try validate_numeric_literal(ty, token.lexeme);
                const wasm_ty = try gc_adapter.classify_admitted_type_with_layouts(ty, self.gc_structs, self.gc_layouts);
                if (wasm_ty.rep != .inline_value) return error.GcSyncTypeMismatch;
                try self.append(INDENT ++ "{s}.const {s}\n", .{ wasm_ty.wasm_type, token.lexeme });
                return ty;
            }
            if (token.kind == .ident) {
                if (std.mem.eql(u8, token.lexeme, "true") or std.mem.eql(u8, token.lexeme, "false")) {
                    try ensure_compatible(expected, "bool");
                    try self.append(INDENT ++ "i32.const {d}\n", .{@intFromBool(std.mem.eql(u8, token.lexeme, "true"))});
                    return "bool";
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
        if (result_ty) |ty| if (gc_adapter.is_admitted_managed_type_with_layouts(ty, self.gc_structs, self.gc_layouts)) try self.append(INDENT ++ ";; gc-root return_value\n", .{});
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
        const eq_idx = find_top_level_token(self.tokens, start_idx + 1, end_idx, "=") orelse return error.UnsupportedGcSyncStatement;
        const expr_start = eq_idx + 1;
        if (expr_start >= end_idx) return error.UnsupportedGcSyncStatement;
        const target_name = find_local_name(self.locals.locals.items, self.tokens[start_idx].lexeme) orelse return error.UnknownGcSyncLocal;
        const target_ty = find_local_type(self.locals.locals.items, self.tokens[start_idx].lexeme) orelse return error.UnknownGcSyncLocal;
        if (gc_adapter.is_admitted_managed_type_with_layouts(target_ty, self.gc_structs, self.gc_layouts)) try self.append(INDENT ++ ";; gc-root overwrite ${s}\n", .{target_name});
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
            } else if (self.tokens[i].kind == .ident and find_top_level_token(self.tokens, i + 1, stmt_end, "=") != null) {
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

fn is_supported_type_with_layouts(
    ty: []const u8,
    structs: []const gc_representation.StructShape,
    layouts: []const gc_layout.GcStructLayout,
    payload_unions: []const gc_layout.GcPayloadUnionLayout,
) bool {
    _ = gc_adapter.classify_admitted_type_with_layouts_and_unions(ty, structs, layouts, payload_unions) catch return false;
    return true;
}

fn is_tuple_storage_type(ty: []const u8) bool {
    const element_ty = type_name.storage_elem_type_from_name(ty) orelse return false;
    return type_name.is_tuple_type_name(element_ty);
}

fn collect_wasi_resource_names(allocator: std.mem.Allocator, tokens: []const lexer.Token, out: *std.ArrayList([]const u8)) !void {
    var i: usize = 0;
    while (i + 4 < tokens.len) : (i += 1) {
        if (tokens[i].kind != .ident or !tok_eq(tokens[i + 1], "=") or
            !tok_eq(tokens[i + 2], "@") or !tok_eq(tokens[i + 3], "wasi_resource")) continue;
        for (out.items) |existing| {
            if (std.mem.eql(u8, existing, tokens[i].lexeme)) break;
        } else {
            try out.append(allocator, tokens[i].lexeme);
        }
        i = find_line_end(tokens, i);
        if (i == 0) break;
        i -= 1;
    }
}

fn module_has_host_or_wit_binding(tokens: []const lexer.Token) bool {
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (!tok_eq(tokens[i], "@") or tokens[i + 1].kind != .ident) continue;
        const intrinsic = tokens[i + 1].lexeme;
        if (std.mem.eql(u8, intrinsic, "host") or
            std.mem.startsWith(u8, intrinsic, "host_") or
            std.mem.startsWith(u8, intrinsic, "wasi_")) return true;
    }
    return false;
}

fn graph_has_host_or_wit_binding(graph: *const imports.ModuleGraph) bool {
    for (graph.modules) |module| {
        if (module_has_host_or_wit_binding(module.tokens)) return true;
    }
    return false;
}

fn append_wasm_type(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    ty: []const u8,
    structs: []const gc_representation.StructShape,
    layouts: []const gc_layout.GcStructLayout,
    payload_unions: []const gc_layout.GcPayloadUnionLayout,
) !void {
    try gc_adapter.append_wasm_type_for_with_unions(allocator, out, ty, structs, layouts, payload_unions);
}

fn append_fmt(allocator: std.mem.Allocator, out: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}

fn find_gc_layout(layouts: []const gc_layout.GcStructLayout, name: []const u8) ?gc_layout.GcStructLayout {
    for (layouts) |layout| if (std.mem.eql(u8, layout.name, name)) return layout;
    return null;
}

fn find_gc_payload_union(layouts: []const gc_layout.GcPayloadUnionLayout, name: []const u8) ?gc_layout.GcPayloadUnionLayout {
    for (layouts) |layout| if (std.mem.eql(u8, layout.name, name)) return layout;
    return null;
}

fn find_gc_field(layout: gc_layout.GcStructLayout, name: []const u8) ?gc_layout.GcFieldLayout {
    for (layout.fields) |field| if (std.mem.eql(u8, public_decl_name(field.name), name)) return field;
    return null;
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

fn append_function_signature(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    func: FuncDecl,
    structs: []const gc_representation.StructShape,
    layouts: []const gc_layout.GcStructLayout,
    payload_unions: []const gc_layout.GcPayloadUnionLayout,
) !void {
    try append_fmt(allocator, out, "  (func ${s}", .{func.name});
    for (func.params) |param| {
        if (param.callback != null) return error.UnsupportedGcSyncCallback;
        if (!is_supported_type_with_layouts(param.ty, structs, layouts, payload_unions) or std.mem.eql(u8, param.ty, "nil")) return error.UnsupportedGcSyncType;
        try append_fmt(allocator, out, " (param ${s} ", .{param.name});
        try append_wasm_type(allocator, out, param.ty, structs, layouts, payload_unions);
        try out.append(allocator, ')');
    }
    if (func.results.len > 1) return error.UnsupportedGcSyncResult;
    if (func.results.len == 1) {
        if (!is_supported_type_with_layouts(func.results[0], structs, layouts, payload_unions) or std.mem.eql(u8, func.results[0], "nil")) return error.UnsupportedGcSyncType;
        try out.appendSlice(allocator, " (result ");
        try append_wasm_type(allocator, out, func.results[0], structs, layouts, payload_unions);
        try out.append(allocator, ')');
    }
    try out.appendSlice(allocator, "\n");
}

fn append_func_params(allocator: std.mem.Allocator, func: FuncDecl, locals: *LocalSet) !void {
    for (func.params) |param| {
        if (param.callback != null) return error.UnsupportedGcSyncCallback;
        try locals.append_borrowed_local_with_origin(allocator, param.name, param.ty, false, .param_or_import);
    }
}

fn append_gc_locals(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    locals: *const LocalSet,
    structs: []const gc_representation.StructShape,
    layouts: []const gc_layout.GcStructLayout,
    payload_unions: []const gc_layout.GcPayloadUnionLayout,
    gc_list_temps: GcListTemps,
) !void {
    for (locals.locals.items) |local| {
        if (!local.emit_decl) continue;
        if (!is_supported_type_with_layouts(local.ty, structs, layouts, payload_unions) or std.mem.eql(u8, local.ty, "nil")) return error.UnsupportedGcSyncType;
        try append_fmt(allocator, out, INDENT ++ "(local ${s} ", .{local.name});
        try append_wasm_type(allocator, out, local.ty, structs, layouts, payload_unions);
        try out.appendSlice(allocator, ")\n");
    }
    try append_fmt(allocator, out, INDENT ++ "(local ${s} (ref null $do_bytes))\n", .{gc_list_temps.bytes_next_name});
    for (gc_layout.scalar_array_specs, 0..) |spec, index| {
        if (gc_list_temps.has_scalar_arrays[index]) {
            try append_fmt(allocator, out, INDENT ++ "(local ${s} (ref null {s}))\n", .{ gc_list_temps.scalar_next_names[index], spec.array_name });
        }
    }
    try append_fmt(allocator, out, INDENT ++ "(local ${s} i32)\n", .{gc_list_temps.length_name});
}

fn choose_gc_list_temps(allocator: std.mem.Allocator, locals: []const codegen_model.Local, scalar_arrays: [gc_layout.scalar_array_specs.len]bool) !GcListTemps {
    var suffix: usize = 0;
    while (true) : (suffix += 1) {
        const bytes_next_name = if (suffix == 0)
            try allocator.dupe(u8, "__gc_list_next")
        else
            try std.fmt.allocPrint(allocator, "__gc_list_next_{d}", .{suffix});
        errdefer allocator.free(bytes_next_name);
        var scalar_next_names: [gc_layout.scalar_array_specs.len][]u8 = undefined;
        var allocated: usize = 0;
        errdefer for (scalar_next_names[0..allocated]) |name| allocator.free(name);
        for (gc_layout.scalar_array_specs, 0..) |spec, index| {
            scalar_next_names[index] = if (suffix == 0)
                try std.fmt.allocPrint(allocator, "__gc_{s}_list_next", .{spec.elem_ty})
            else
                try std.fmt.allocPrint(allocator, "__gc_{s}_list_next_{d}", .{ spec.elem_ty, suffix });
            allocated += 1;
        }
        const length_name = if (suffix == 0)
            try allocator.dupe(u8, "__gc_list_length")
        else
            try std.fmt.allocPrint(allocator, "__gc_list_length_{d}", .{suffix});
        errdefer allocator.free(length_name);
        var collision = has_wat_local_name(locals, bytes_next_name) or has_wat_local_name(locals, length_name);
        for (scalar_next_names) |name| collision = collision or has_wat_local_name(locals, name);
        if (!collision) {
            return .{ .bytes_next_name = bytes_next_name, .scalar_next_names = scalar_next_names, .has_scalar_arrays = scalar_arrays, .length_name = length_name };
        }
        allocator.free(bytes_next_name);
        for (scalar_next_names) |name| allocator.free(name);
        allocator.free(length_name);
    }
}

fn has_wat_local_name(locals: []const codegen_model.Local, name: []const u8) bool {
    for (locals) |local| if (std.mem.eql(u8, local.name, name)) return true;
    return false;
}

fn emit_func(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    func: FuncDecl,
    functions: []const FuncDecl,
    base_ctx: CodegenContext,
    gc_structs: []const gc_representation.StructShape,
    gc_layouts: []const gc_layout.GcStructLayout,
    payload_unions: []const gc_layout.GcPayloadUnionLayout,
    scalar_arrays: [gc_layout.scalar_array_specs.len]bool,
) !void {
    try append_function_signature(allocator, out, func, gc_structs, gc_layouts, payload_unions);
    var locals = LocalSet{};
    defer locals.deinit(allocator);
    try append_func_params(allocator, func, &locals);
    try codegen_body.collect_body_locals(allocator, func.tokens, func.body_start, func.body_end, base_ctx, &locals);
    const gc_list_temps = try choose_gc_list_temps(allocator, locals.locals.items, scalar_arrays);
    defer gc_list_temps.deinit(allocator);

    var root_locals = std.ArrayList(gc_roots.RootLocal).empty;
    defer root_locals.deinit(allocator);
    for (locals.locals.items) |local| {
        if (!is_supported_type_with_layouts(local.ty, gc_structs, gc_layouts, payload_unions) or std.mem.eql(u8, local.ty, "nil")) return error.UnsupportedGcSyncType;
        const rep = (try gc_adapter.classify_admitted_type_with_layouts_and_unions(local.ty, gc_structs, gc_layouts, payload_unions)).rep;
        try root_locals.append(allocator, .{ .name = local.name, .rep = rep });
    }
    const root_plan = try gc_roots.build_root_plan(allocator, root_locals.items, .synchronous);
    defer gc_roots.deinit_root_plan(allocator, root_plan);

    try append_gc_locals(allocator, out, &locals, gc_structs, gc_layouts, payload_unions, gc_list_temps);
    for (root_plan.slots) |slot| {
        try append_fmt(allocator, out, INDENT ++ ";; gc-root {s} ${s}\n", .{ append_root_point_name(slot.point), slot.name });
    }

    var emitter = BodyEmitter{ .allocator = allocator, .tokens = func.tokens, .functions = functions, .gc_structs = gc_structs, .gc_layouts = gc_layouts, .gc_payload_unions = payload_unions, .locals = &locals, .out = out, .gc_list_temps = gc_list_temps };
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

fn emit_test_func(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    test_decl: TestDecl,
    index: usize,
    tokens: []const lexer.Token,
    functions: []const FuncDecl,
    base_ctx: CodegenContext,
    gc_structs: []const gc_representation.StructShape,
    gc_layouts: []const gc_layout.GcStructLayout,
    payload_unions: []const gc_layout.GcPayloadUnionLayout,
    scalar_arrays: [gc_layout.scalar_array_specs.len]bool,
) !void {
    try wat_function_body.emit_compiled_test_open(allocator, out, index, test_decl.name_lexeme);

    var locals = LocalSet{};
    defer locals.deinit(allocator);
    try codegen_body.collect_body_locals(allocator, tokens, test_decl.body_start, test_decl.body_end, base_ctx, &locals);
    const gc_list_temps = try choose_gc_list_temps(allocator, locals.locals.items, scalar_arrays);
    defer gc_list_temps.deinit(allocator);

    var root_locals = std.ArrayList(gc_roots.RootLocal).empty;
    defer root_locals.deinit(allocator);
    for (locals.locals.items) |local| {
        if (!is_supported_type_with_layouts(local.ty, gc_structs, gc_layouts, payload_unions) or std.mem.eql(u8, local.ty, "nil")) return error.UnsupportedGcSyncType;
        const rep = (try gc_adapter.classify_admitted_type_with_layouts_and_unions(local.ty, gc_structs, gc_layouts, payload_unions)).rep;
        try root_locals.append(allocator, .{ .name = local.name, .rep = rep });
    }
    const root_plan = try gc_roots.build_root_plan(allocator, root_locals.items, .synchronous);
    defer gc_roots.deinit_root_plan(allocator, root_plan);

    try append_gc_locals(allocator, out, &locals, gc_structs, gc_layouts, payload_unions, gc_list_temps);
    for (root_plan.slots) |slot| {
        try append_fmt(allocator, out, INDENT ++ ";; gc-root {s} ${s}\n", .{ append_root_point_name(slot.point), slot.name });
    }

    var emitter = BodyEmitter{
        .allocator = allocator,
        .tokens = tokens,
        .functions = functions,
        .gc_structs = gc_structs,
        .gc_layouts = gc_layouts,
        .gc_payload_unions = payload_unions,
        .locals = &locals,
        .out = out,
        .gc_list_temps = gc_list_temps,
    };
    var deferred = std.ArrayList(DeferredCall).empty;
    defer deferred.deinit(allocator);
    _ = try emitter.emit_body(test_decl.body_start, test_decl.body_end, null, &deferred);
    try out.appendSlice(allocator, INDENT ++ "unreachable\n");
    try wat_function_body.emit_func_close(allocator, out);
    try wat_function_body.emit_compiled_test_export(allocator, out, index);
}

fn emit_start(allocator: std.mem.Allocator, out: *std.ArrayList(u8), tokens: []const lexer.Token, functions: []const FuncDecl, base_ctx: CodegenContext, gc_structs: []const gc_representation.StructShape, gc_layouts: []const gc_layout.GcStructLayout, payload_unions: []const gc_layout.GcPayloadUnionLayout, scalar_arrays: [gc_layout.scalar_array_specs.len]bool) !void {
    const start_idx = find_start_func(tokens) orelse return;
    const close_params = try find_matching(tokens, start_idx + 1, "(", ")");
    const open_body = find_top_level_block_open(tokens, close_params + 1, tokens.len) orelse return error.UnsupportedGcSyncControl;
    const close_body = try find_matching(tokens, open_body, "{", "}");

    var locals = LocalSet{};
    defer locals.deinit(allocator);
    try codegen_body.collect_body_locals(allocator, tokens, open_body + 1, close_body, base_ctx, &locals);
    const gc_list_temps = try choose_gc_list_temps(allocator, locals.locals.items, scalar_arrays);
    defer gc_list_temps.deinit(allocator);
    var root_locals = std.ArrayList(gc_roots.RootLocal).empty;
    defer root_locals.deinit(allocator);
    for (locals.locals.items) |local| {
        if (!is_supported_type_with_layouts(local.ty, gc_structs, gc_layouts, payload_unions) or std.mem.eql(u8, local.ty, "nil")) return error.UnsupportedGcSyncType;
        const rep = (try gc_adapter.classify_admitted_type_with_layouts_and_unions(local.ty, gc_structs, gc_layouts, payload_unions)).rep;
        try root_locals.append(allocator, .{ .name = local.name, .rep = rep });
    }
    const root_plan = try gc_roots.build_root_plan(allocator, root_locals.items, .synchronous);
    defer gc_roots.deinit_root_plan(allocator, root_plan);

    try out.appendSlice(allocator, "  (func $_start\n");
    try append_gc_locals(allocator, out, &locals, gc_structs, gc_layouts, payload_unions, gc_list_temps);
    for (root_plan.slots) |slot| try append_fmt(allocator, out, INDENT ++ ";; gc-root {s} ${s}\n", .{ append_root_point_name(slot.point), slot.name });
    var emitter = BodyEmitter{ .allocator = allocator, .tokens = tokens, .functions = functions, .gc_structs = gc_structs, .gc_layouts = gc_layouts, .gc_payload_unions = payload_unions, .locals = &locals, .out = out, .gc_list_temps = gc_list_temps };
    var deferred = std.ArrayList(DeferredCall).empty;
    defer deferred.deinit(allocator);
    _ = try emitter.emit_body(open_body + 1, close_body, null, &deferred);
    try out.appendSlice(allocator, "  )\n  (export \"_start\" (func $_start))\n");
}

fn emit_gc_wat_for_supported_program_with_tests(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
    test_decls: []const TestDecl,
) ![]u8 {
    if (tokens.len == 0) return error.UnsupportedGcSyncProgram;
    if (module_graph) |graph| {
        // Component/WIT and host bindings need their canonical ABI marshalling
        // path. Keep the parsed GC route fail-closed until that boundary is
        // wired; plain synchronous @lib imports remain admitted below.
        if (graph_has_host_or_wit_binding(graph)) return error.UnsupportedGcSyncModuleGraph;
    }

    var structs = std.ArrayList(StructDecl).empty;
    defer {
        codegen_model.free_struct_decls(allocator, structs.items);
        structs.deinit(allocator);
    }
    try codegen_collect_structs.collect_struct_decls(allocator, tokens, &structs);
    if (module_graph) |graph| {
        try codegen_collect_structs.collect_imported_struct_decls(allocator, tokens, graph, &structs);
    }
    var resource_names = std.ArrayList([]const u8).empty;
    defer resource_names.deinit(allocator);
    collect_wasi_resource_names(allocator, tokens, &resource_names) catch return error.UnsupportedGcSyncAggregate;
    const gc_structs = try gc_model_adapter.collect_struct_shapes(allocator, structs.items);
    defer gc_model_adapter.deinit_struct_shapes(allocator, gc_structs);
    var gc_layouts = std.ArrayList(gc_layout.GcStructLayout).empty;
    defer {
        for (gc_layouts.items) |layout| gc_model_adapter.deinit_struct_layout(allocator, layout);
        gc_layouts.deinit(allocator);
    }
    for (structs.items) |decl| {
        const layout = gc_model_adapter.collect_struct_layout(allocator, decl, structs.items, resource_names.items) catch |err| switch (err) {
            error.ResourceInManagedAggregate, error.UnsupportedGcAggregate, error.UnknownType => return error.UnsupportedGcSyncAggregate,
            else => return err,
        };
        if (layout.fields.len == 0) return error.UnsupportedGcSyncAggregate;
        try gc_layouts.append(allocator, layout);
    }

    var source_struct_layouts = std.ArrayList(StructLayout).empty;
    defer {
        codegen_model.free_struct_layouts(allocator, source_struct_layouts.items);
        source_struct_layouts.deinit(allocator);
    }
    try codegen_collect_structs.collect_struct_layouts(allocator, structs.items, &source_struct_layouts);
    const struct_layouts = source_struct_layouts.items;
    var payload_enums = std.ArrayList(PayloadEnumDecl).empty;
    defer {
        codegen_model.free_payload_enum_decls(allocator, payload_enums.items);
        payload_enums.deinit(allocator);
    }
    try codegen_collect_declarations.collect_payload_enum_decls(allocator, tokens, &payload_enums);
    if (module_graph) |graph| {
        try codegen_collect_declarations.collect_imported_payload_enum_decls(allocator, tokens, graph, &payload_enums);
    }
    var functions = std.ArrayList(FuncDecl).empty;
    defer {
        codegen_model.free_func_decls(allocator, functions.items);
        functions.deinit(allocator);
    }
    const imported_alias_ctx: ?ImportedAliasContext = if (module_graph) |graph|
        if (find_root_module_index(graph.modules, tokens)) |idx| ImportedAliasContext{ .graph = graph, .module_idx = idx } else null
    else
        null;
    try codegen_collect_functions.collect_gc_sync_func_decls(allocator, tokens, structs.items, struct_layouts, payload_enums.items, imported_alias_ctx, &functions);
    if (module_graph) |graph| {
        try codegen_collect_functions.collect_direct_gc_sync_imported_func_decls(
            allocator,
            tokens,
            graph,
            structs.items,
            struct_layouts,
            payload_enums.items,
            &functions,
        );
    }
    var generic_string_data = StringDataContext{};
    defer generic_string_data.deinit(allocator);
    const generic_result = if (test_decls.len != 0)
        codegen_generics.collect_generic_func_instances_for_tests(
            allocator,
            tokens,
            test_decls,
            structs.items,
            &.{},
            payload_enums.items,
            struct_layouts,
            &.{},
            &.{},
            &generic_string_data,
            &.{},
            imported_alias_ctx,
            &functions,
        )
    else
        codegen_generics.collect_generic_func_instances_for_start(
            allocator,
            tokens,
            structs.items,
            &.{},
            payload_enums.items,
            struct_layouts,
            &.{},
            &.{},
            &generic_string_data,
            &.{},
            imported_alias_ctx,
            &functions,
        );
    generic_result catch |err| switch (err) {
        // The generic collector also prepares payload-enum parameter locals.
        // A malformed payload is therefore observed here before the typed GC
        // union gate below. Preserve the public GC boundary and distinguish
        // the generic-substitution case from an ordinary malformed union.
        error.NoMatchingCall => {
            for (functions.items) |func| {
                if (func.is_generic_template) return error.UnsupportedGcSyncGenericUnion;
            }
            return error.UnsupportedGcSyncUnionPayload;
        },
        else => return err,
    };
    for (functions.items) |func| {
        if (!func.is_generic_template and func.type_bindings.len != 0) {
            try validate_gc_sync_generic_bindings(func, gc_structs, gc_layouts.items, resource_names.items, payload_enums.items);
        }
    }
    var payload_unions = std.ArrayList(gc_layout.GcPayloadUnionLayout).empty;
    defer payload_unions.deinit(allocator);
    for (payload_enums.items) |decl| {
        const payload_union = gc_layout.collect_payload_union_layout(decl.name, decl.cases) catch |err| switch (err) {
            error.UnsupportedGcSyncUnionArms => return error.UnsupportedGcSyncUnionArms,
            error.UnsupportedGcSyncUnionPayload => return error.UnsupportedGcSyncUnionPayload,
        };
        try payload_unions.append(allocator, payload_union);
    }
    for (functions.items, 0..) |func, idx| {
        if (func.is_generic_template) continue;
        for (functions.items[0..idx]) |previous| {
            if (std.mem.eql(u8, previous.name, func.name)) return error.UnsupportedGcSyncOverload;
        }
        if (func.is_async or func.contains_await) return error.UnsupportedGcSyncAsync;
        for (func.params) |param| {
            if (is_tuple_storage_type(param.ty)) return error.UnsupportedGcSyncTupleStorage;
            if (std.mem.eql(u8, param.ty, "nil") or !is_supported_type_with_layouts(param.ty, gc_structs, gc_layouts.items, payload_unions.items)) return error.UnsupportedGcSyncType;
        }
        for (func.results) |result| {
            if (is_tuple_storage_type(result)) return error.UnsupportedGcSyncTupleStorage;
            if (std.mem.eql(u8, result, "nil") or !is_supported_type_with_layouts(result, gc_structs, gc_layouts.items, payload_unions.items)) return error.UnsupportedGcSyncType;
        }
        try validate_gc_sync_tuple_admission(func);
    }
    for (functions.items) |template| {
        if (!template.is_generic_template) continue;
        var resolved = false;
        for (functions.items) |func| {
            if (!func.is_generic_template and func.type_bindings.len != 0 and
                std.mem.eql(u8, func.source_name, template.source_name))
            {
                resolved = true;
                break;
            }
        }
        if (!resolved) return error.UnsupportedGcSyncGenericUnresolved;
    }
    if (resource_names.items.len != 0) return error.UnsupportedGcSyncAggregate;

    var string_data = StringDataContext{};
    defer string_data.deinit(allocator);
    const base_ctx = CodegenContext{
        .functions = functions.items,
        .structs = structs.items,
        .struct_layouts = struct_layouts,
        .value_enums = &.{},
        .payload_enums = payload_enums.items,
        .host_imports = &.{},
        .wasi_imports = &.{},
        .string_data = &string_data,
        .entry_tokens = tokens,
        .modules = if (module_graph) |graph| @as([]const imports.ModuleRecord, graph.modules) else &.{},
        .imported_alias_ctx = imported_alias_ctx,
    };

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, "(module\n");
    try append_fmt(allocator, &out, "  ;; gc-sync source_len={d} token_count={d}\n", .{ program.source_len, program.token_count });
    const has_tuple_text_bytes = has_gc_sync_tuple_text_bytes(functions.items) or test_decls.len != 0;
    var scalar_arrays = has_gc_sync_scalar_arrays(functions.items, gc_layouts.items);
    if (test_decls.len != 0) scalar_arrays = [_]bool{true} ** gc_layout.scalar_array_specs.len;
    try runtime_gc_prelude.emit_gc_sync_prelude(allocator, &out, gc_layouts.items, payload_unions.items, has_tuple_text_bytes, scalar_arrays);
    for (functions.items) |func| if (!func.is_generic_template) try emit_func(allocator, &out, func, functions.items, base_ctx, gc_structs, gc_layouts.items, payload_unions.items, scalar_arrays);
    if (test_decls.len != 0) {
        for (test_decls, 0..) |test_decl, index| {
            try emit_test_func(allocator, &out, test_decl, index, tokens, functions.items, base_ctx, gc_structs, gc_layouts.items, payload_unions.items, scalar_arrays);
        }
        try wat_function_body.emit_test_start_func(allocator, &out, test_decls.len);
    } else {
        try emit_start(allocator, &out, tokens, functions.items, base_ctx, gc_structs, gc_layouts.items, payload_unions.items, scalar_arrays);
    }
    try out.appendSlice(allocator, ")\n");
    return out.toOwnedSlice(allocator);
}

pub fn emit_gc_wat_for_supported_program(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) ![]u8 {
    return emit_gc_wat_for_supported_program_with_tests(allocator, program, tokens, module_graph, &.{});
}

pub fn emit_gc_wat_for_supported_tests(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) ![]u8 {
    const test_decls = try test_runner.collect_top_level_tests(allocator, tokens);
    defer allocator.free(test_decls);
    if (test_decls.len == 0) return error.NoTestDecl;
    return emit_gc_wat_for_supported_program_with_tests(allocator, program, tokens, module_graph, test_decls);
}

/// Only these errors mean that a source shape is outside the temporary GC
/// admission surface. Unexpected failures must propagate instead of silently
/// selecting the ARC transition emitter.
pub fn is_gc_sync_admission_rejection(err: anyerror) bool {
    return switch (err) {
        error.GcSyncArityMismatch,
        error.GcSyncTypeMismatch,
        error.MissingGcSyncReturn,
        error.NoMatchingCall,
        error.ResourceInManagedAggregate,
        error.UnexpectedGcSyncReturn,
        error.UnknownGcSyncLocal,
        error.UnknownType,
        error.UnsupportedGcAggregate,
        error.UnsupportedGcSyncAggregate,
        error.UnsupportedGcSyncAsync,
        error.UnsupportedGcSyncCall,
        error.UnsupportedGcSyncCallback,
        error.UnsupportedGcSyncControl,
        error.UnsupportedGcSyncExpression,
        error.UnsupportedGcSyncGenericResource,
        error.UnsupportedGcSyncGenericUnion,
        error.UnsupportedGcSyncGenericUnresolved,
        error.UnsupportedGcSyncModuleGraph,
        error.UnsupportedGcSyncOverload,
        error.UnsupportedGcSyncProducer,
        error.UnsupportedGcSyncProgram,
        error.UnsupportedGcSyncResult,
        error.UnsupportedGcSyncStatement,
        error.UnsupportedGcSyncTupleStorage,
        error.UnsupportedGcSyncType,
        error.UnsupportedGcSyncUnionArms,
        error.UnsupportedGcSyncUnionConstructor,
        error.UnsupportedGcSyncUnionPayload,
        => true,
        else => false,
    };
}

fn validate_gc_sync_generic_bindings(
    func: FuncDecl,
    gc_structs: []const gc_representation.StructShape,
    gc_layouts: []const gc_layout.GcStructLayout,
    resource_names: []const []const u8,
    payload_enums: []const PayloadEnumDecl,
) !void {
    for (func.type_bindings) |binding| {
        for (resource_names) |resource_name| {
            if (std.mem.eql(u8, resource_name, binding.ty)) return error.UnsupportedGcSyncGenericResource;
        }
        for (payload_enums) |payload_enum| {
            if (std.mem.eql(u8, payload_enum.name, binding.ty)) return error.UnsupportedGcSyncGenericUnion;
        }
        if (!is_supported_type_with_layouts(binding.ty, gc_structs, gc_layouts, &.{})) return error.UnsupportedGcSyncGenericUnresolved;
    }
}

fn has_gc_sync_tuple_text_bytes(functions: []const FuncDecl) bool {
    for (functions) |func| {
        for (func.params) |param| if (gc_adapter.is_gc_sync_tuple_text_bytes(param.ty)) return true;
        for (func.results) |result| if (gc_adapter.is_gc_sync_tuple_text_bytes(result)) return true;
    }
    return false;
}

fn has_gc_sync_scalar_arrays(functions: []const FuncDecl, layouts: []const gc_layout.GcStructLayout) [gc_layout.scalar_array_specs.len]bool {
    var result = [_]bool{false} ** gc_layout.scalar_array_specs.len;
    for (gc_layout.scalar_array_specs, 0..) |spec, index| {
        for (functions) |func| {
            for (func.params) |param| {
                if (std.mem.eql(u8, param.ty, spec.list_ty)) result[index] = true;
            }
            for (func.results) |value| {
                if (std.mem.eql(u8, value, spec.list_ty)) result[index] = true;
            }
            var i: usize = func.body_start;
            while (i + 2 < func.body_end and i + 2 < func.tokens.len) : (i += 1) {
                if (tok_eq(func.tokens[i], "[") and tok_eq(func.tokens[i + 1], spec.elem_ty) and tok_eq(func.tokens[i + 2], "]")) result[index] = true;
            }
        }
        for (layouts) |layout| {
            for (layout.fields) |field| {
                if (std.mem.eql(u8, field.ty, spec.list_ty)) result[index] = true;
            }
        }
    }
    return result;
}

fn has_gc_sync_u32_array(functions: []const FuncDecl, layouts: []const gc_layout.GcStructLayout) bool {
    for (functions) |func| {
        for (func.params) |param| {
            if (std.mem.eql(u8, param.ty, "[u32]")) return true;
        }
        for (func.results) |result| {
            if (std.mem.eql(u8, result, "[u32]")) return true;
        }
    }
    for (layouts) |layout| {
        for (layout.fields) |field| {
            if (std.mem.eql(u8, field.ty, "[u32]")) return true;
        }
    }
    for (functions) |func| {
        var i: usize = func.body_start;
        while (i + 2 < func.body_end and i + 2 < func.tokens.len) : (i += 1) {
            if (tok_eq(func.tokens[i], "[") and tok_eq(func.tokens[i + 1], "u32") and tok_eq(func.tokens[i + 2], "]")) return true;
        }
    }
    return false;
}

fn validate_gc_sync_tuple_admission(func: FuncDecl) !void {
    var uses_tuple = false;
    for (func.params) |param| uses_tuple = uses_tuple or gc_adapter.is_gc_sync_tuple_text_bytes(param.ty);
    for (func.results) |result| uses_tuple = uses_tuple or gc_adapter.is_gc_sync_tuple_text_bytes(result);
    if (!uses_tuple) return;
    if (!is_gc_sync_tuple_text_bytes_rewrite(func)) return error.UnsupportedGcSyncType;
}

fn is_gc_sync_tuple_text_bytes_rewrite(func: FuncDecl) bool {
    if (func.params.len != 1 or func.results.len != 1) return false;
    if (!gc_adapter.is_gc_sync_tuple_text_bytes(func.params[0].ty) or !gc_adapter.is_gc_sync_tuple_text_bytes(func.results[0])) return false;
    const tokens = func.tokens;
    var expr_start = func.body_start;
    if (!func.arrow) {
        if (expr_start >= func.body_end or !tok_eq(tokens[expr_start], "return")) return false;
        expr_start += 1;
    }
    const end_idx = func.body_end;
    if (expr_start + 8 >= end_idx or !tok_eq(tokens[expr_start], "Tuple") or !tok_eq(tokens[expr_start + 1], "<")) return false;
    const close_angle = find_matching_in_range(tokens, expr_start + 1, "<", ">", end_idx) catch return false;
    if (close_angle != expr_start + 7 or !tok_eq(tokens[expr_start + 2], "text") or !tok_eq(tokens[expr_start + 3], ",") or !tok_eq(tokens[expr_start + 4], "[") or !tok_eq(tokens[expr_start + 5], "u8") or !tok_eq(tokens[expr_start + 6], "]")) return false;
    if (close_angle + 1 >= end_idx or !tok_eq(tokens[close_angle + 1], "{")) return false;
    const close_brace = find_matching_in_range(tokens, close_angle + 1, "{", "}", end_idx) catch return false;
    if (close_brace + 1 != end_idx) return false;
    const first_end = find_arg_end(tokens, close_angle + 2, close_brace);
    if (first_end >= close_brace or !tok_eq(tokens[first_end], ",")) return false;
    if (!is_gc_sync_tuple_get(tokens, func.params[0].name, close_angle + 2, first_end, "0")) return false;
    const second_start = first_end + 1;
    return is_gc_sync_tuple_bytes_set(tokens, func.params[0].name, second_start, close_brace);
}

fn is_gc_sync_tuple_get(tokens: []const lexer.Token, receiver_name: []const u8, start_idx: usize, end_idx: usize, index: []const u8) bool {
    if (start_idx + 3 >= end_idx or !tok_eq(tokens[start_idx], "@") or !tok_eq(tokens[start_idx + 1], "get") or !tok_eq(tokens[start_idx + 2], "(")) return false;
    const close_idx = find_matching_in_range(tokens, start_idx + 2, "(", ")", end_idx) catch return false;
    return close_idx + 1 == end_idx and tok_eq(tokens[start_idx + 3], receiver_name) and tok_eq(tokens[start_idx + 4], ",") and tok_eq(tokens[start_idx + 5], index) and tok_eq(tokens[start_idx + 6], ")");
}

fn is_gc_sync_tuple_bytes_set(tokens: []const lexer.Token, receiver_name: []const u8, start_idx: usize, end_idx: usize) bool {
    if (start_idx + 5 >= end_idx or !tok_eq(tokens[start_idx], "@") or !tok_eq(tokens[start_idx + 1], "set") or !tok_eq(tokens[start_idx + 2], "(")) return false;
    const close_idx = find_matching_in_range(tokens, start_idx + 2, "(", ")", end_idx) catch return false;
    if (close_idx + 1 != end_idx) return false;
    const receiver_end = find_arg_end(tokens, start_idx + 3, close_idx);
    if (!is_gc_sync_tuple_get(tokens, receiver_name, start_idx + 3, receiver_end, "1")) return false;
    const index_start = receiver_end + 1;
    const index_end = find_arg_end(tokens, index_start, close_idx);
    const value_start = index_end + 1;
    return index_end < close_idx and tok_eq(tokens[index_end], ",") and value_start + 1 == close_idx and tok_eq(tokens[index_start], "0") and tok_eq(tokens[value_start], "65");
}

fn emit_test_source(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);
    var program = try parser.parse_program(allocator, tokens, source.len);
    defer program.deinit(allocator);
    return emit_gc_wat_for_supported_program(allocator, program, tokens, null);
}

test "GC sync rejects managed-element list updates before WAT emission" {
    const source =
        \\Box {
        \\    value text
        \\}
        \\replace(values [Box], value Box) -> [Box] {
        \\    return @set(values, 0, value)
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.UnsupportedGcSyncType, emit_test_source(std.testing.allocator, source));
}

test "GC sync lowers an i16 list literal through a typed GC array" {
    const source =
        \\make() -> [i16] {
        \\    return .{7, 12, 17}
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_i16 (array (mut i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(result (ref null $do_i16))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_fixed $do_i16 3") != null);
}

test "GC sync lowers a u32 list literal through a typed GC array" {
    const source =
        \\make() -> [u32] {
        \\    return .{7, 12, 17}
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_u32 (array (mut i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(result (ref null $do_u32))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_fixed $do_u32 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync lowers an immutable u32 list update through a typed GC array" {
    const source =
        \\update(input [u32]) -> [u32] {
        \\    return @set(input, 1, 65)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.copy $do_u32 $do_u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync lowers an i16 list literal and immutable update through a typed GC array" {
    const source =
        \\make() -> [i16] {
        \\    return .{7, 12, 17}
        \\}
        \\update(input [i16]) -> [i16] {
        \\    return @set(input, 1, 65)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_i16 (array (mut i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_fixed $do_i16 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.copy $do_i16 $do_i16") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_i16") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync lowers an i32 list literal and immutable update through a typed GC array" {
    const source =
        \\make() -> [i32] {
        \\    return .{7, 12, 17}
        \\}
        \\update(input [i32]) -> [i32] {
        \\    return @set(input, 1, 65)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_i32 (array (mut i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_fixed $do_i32 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.copy $do_i32 $do_i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_i32") != null);
}

test "GC sync lowers a bool list literal through a typed GC array" {
    const source =
        \\make() -> [bool] {
        \\    return .{true, false}
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_bool (array (mut i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_fixed $do_bool 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 1\n    i32.const 0") != null);
}

test "GC sync lowers an i64 list literal and immutable update through a typed GC array" {
    const source =
        \\make() -> [i64] {
        \\    return .{7, 12, 17}
        \\}
        \\update(input [i64]) -> [i64] {
        \\    return @set(input, 1, 65)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_i64 (array (mut i64)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_fixed $do_i64 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.copy $do_i64 $do_i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_i64") != null);
}

test "GC sync lowers float list literals through typed GC arrays" {
    const source =
        \\make_f32() -> [f32] {
        \\    return .{1.5, 2.25}
        \\}
        \\make_f64() -> [f64] {
        \\    return .{1.5, 2.25}
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_f32 (array (mut f32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_f64 (array (mut f64)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_fixed $do_f32 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_fixed $do_f64 2") != null);
}

test "GC sync lowers float list updates through typed GC arrays" {
    const source =
        \\update_f32(input [f32]) -> [f32] {
        \\    return @set(input, 1, 3.5)
        \\}
        \\update_f64(input [f64]) -> [f64] {
        \\    return @set(input, 1, 3.5)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.copy $do_f32 $do_f32") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_f32") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.copy $do_f64 $do_f64") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_f64") != null);
}

test "GC sync lowers remaining scalar list types through typed GC arrays" {
    const source =
        \\make_i8() -> [i8] {
        \\    return .{7, 12, 17}
        \\}
        \\make_u16() -> [u16] {
        \\    return .{7, 12, 17}
        \\}
        \\make_u64() -> [u64] {
        \\    return .{7, 12, 17}
        \\}
        \\make_isize() -> [isize] {
        \\    return .{7, 12, 17}
        \\}
        \\make_usize() -> [usize] {
        \\    return .{7, 12, 17}
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_i8 (array (mut i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_u16 (array (mut i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_u64 (array (mut i64)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_isize (array (mut i32)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_usize (array (mut i32)))") != null);
}

test "GC sync rejects multi-value put before WAT emission" {
    const source =
        \\append(values [u8]) -> [u8] {
        \\    return @put(values, 1, 2)
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.UnsupportedGcSyncExpression, emit_test_source(std.testing.allocator, source));
}

test "GC sync rejects call-produced managed field replacement" {
    const source =
        \\Box {
        \\    value [u8]
        \\}
        \\make() -> [u8] {
        \\    return .{1, 2}
        \\}
        \\replace(box Box) -> Box {
        \\    return @set(box, .value, make())
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.UnsupportedGcSyncProducer, emit_test_source(std.testing.allocator, source));
}

test "GC sync lowers a pure payload union through a typed GC carrier" {
    const source =
        \\Message = Empty | Bytes([u8])
        \\rewrite(value Message, bytes [u8]) -> Message {
        \\    return Bytes(bytes)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $message (struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(field $tag i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(field $bytes (ref null $do_bytes))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(param $value (ref null $message))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(result (ref null $message))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $message") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $message\n    return") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync rejects payload union with more than one managed arm" {
    const source =
        \\Message = Empty | Bytes([u8]) | Text(text)
        \\rewrite(value Message, bytes [u8], text_value text) -> Message {
        \\    return Bytes(bytes)
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.UnsupportedGcSyncUnionArms, emit_test_source(std.testing.allocator, source));
}

test "GC sync rejects payload union with non-byte payload" {
    const source =
        \\Message = Empty | File(File)
        \\rewrite(value Message, file File) -> Message {
        \\    return File(file)
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.UnsupportedGcSyncUnionPayload, emit_test_source(std.testing.allocator, source));
}

test "GC sync rejects payload union with unresolved payload" {
    const source =
        \\Message = Empty | Unknown(Missing)
        \\rewrite(value Message, missing Missing) -> Message {
        \\    return Unknown(missing)
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.UnsupportedGcSyncUnionPayload, emit_test_source(std.testing.allocator, source));
}

test "GC sync rejects payload union with scalar plus managed payload slots" {
    const source =
        \\Message = Empty | Pair(Tuple<i32, [u8]>)
        \\rewrite(value Message, pair Tuple<i32, [u8]>) -> Message {
        \\    return Pair(pair)
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.UnsupportedGcSyncUnionPayload, emit_test_source(std.testing.allocator, source));
}

test "GC sync lowers direct text identity and literal rebuild with typed references" {
    const source =
        \\identity(value text) -> text {
        \\    return value
        \\}
        \\rebuild() -> text {
        \\    return "hello"
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(param $value (ref null $do_text))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(result (ref null $do_text))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $do_text") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 5\n    i32.const 104\n    i32.const 101\n    array.new_fixed $do_bytes 5") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync omits an unused u32 array type from text-only programs" {
    const source =
        \\identity(value text) -> text {
        \\    return value
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "$do_u32") == null);
}

test "GC sync lowers managed text through a parsed branch join" {
    const source =
        \\choose(flag bool, left text, right text) -> text {
        \\    if flag {
        \\        return left
        \\    }
        \\    return right
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $choose") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(ref null $do_text)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-root branch_join") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "if\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync lowers managed text through a parsed loop" {
    const source =
        \\repeat(left text) -> text {
        \\    loop {
        \\        return left
        \\    }
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-root loop_join") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "loop $__gc_loop_") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync lowers managed text with parsed defer cleanup" {
    const source =
        \\noop() {}
        \\finish(value text) -> text {
        \\    defer noop()
        \\    return value
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $noop") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(result (ref null $do_text))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync rebuilds a struct for direct text field replacement" {
    const source =
        \\Message {
        \\    body text
        \\    tag i32
        \\}
        \\replace(message Message, body text) -> Message {
        \\    return @set(message, .body, body)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(field $body (ref null $do_text))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $message $tag") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $message") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync rebuilds a struct for a scalar-list managed field replacement" {
    const source =
        \\Box {
        \\    flags [bool]
        \\    tag i32
        \\}
        \\replace(box Box, flags [bool]) -> Box {
        \\    return @set(box, .flags, flags)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(field $flags (ref null $do_bool))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $box $tag") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync rebuilds a struct for float scalar-list managed field replacements" {
    const source =
        \\F32Box {
        \\    values [f32]
        \\    tag i32
        \\}
        \\F64Box {
        \\    values [f64]
        \\    tag i32
        \\}
        \\replace_f32(box F32Box, values [f32]) -> F32Box {
        \\    return @set(box, .values, values)
        \\}
        \\replace_f64(box F64Box, values [f64]) -> F64Box {
        \\    return @set(box, .values, values)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(field $values (ref null $do_f32))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(field $values (ref null $do_f64))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $f32box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $f64box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync rebuilds a nested managed struct field from a direct local" {
    const source =
        \\Inner {
        \\    value [u8]
        \\}
        \\Outer {
        \\    inner Inner
        \\    tag i32
        \\}
        \\replace(outer Outer, inner Inner) -> Outer {
        \\    return @set(outer, .inner, inner)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $inner ") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(field $inner (ref null $inner))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $outer $tag") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $outer") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync gets a nested managed struct field as its declared type" {
    const source =
        \\Inner {
        \\    value [u8]
        \\}
        \\Outer {
        \\    inner Inner
        \\}
        \\get_inner(outer Outer) -> Inner {
        \\    return @get(outer, .inner)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(result (ref null $inner))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $outer $inner") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync rejects a nested managed struct producer before WAT emission" {
    const source =
        \\Inner {
        \\    value [u8]
        \\}
        \\Outer {
        \\    inner Inner
        \\}
        \\identity(inner Inner) -> Inner {
        \\    return inner
        \\}
        \\replace(outer Outer, inner Inner) -> Outer {
        \\    return @set(outer, .inner, identity(inner))
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.UnsupportedGcSyncProducer, emit_test_source(std.testing.allocator, source));
}

test "GC sync lowers a byte-list literal through a typed local" {
    const source =
        \\make() -> [u8] {
        \\    value [u8] = .{7, 12, 17}
        \\    return value
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(local $value (ref null $do_bytes))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_fixed $do_bytes 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync admits one direct call returning a classified managed value" {
    const source =
        \\make() -> [u8] {
        \\    return .{1, 2, 3}
        \\}
        \\relay() -> [u8] {
        \\    return make()
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $make") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(result (ref null $do_bytes))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync lowers a Tuple text byte-list persistent update" {
    const source =
        \\rewrite(pair Tuple<text, [u8]>) -> Tuple<text, [u8]> {
        \\    return Tuple<text, [u8]>{@get(pair, 0), @set(@get(pair, 1), 0, 65)}
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(param $pair (ref null $tuple_text_bytes))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(result (ref null $tuple_text_bytes))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $tuple_text_bytes $text") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.copy $do_bytes $do_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $tuple_text_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync rejects tuple identity outside the admitted persistent rewrite" {
    const source =
        \\identity(pair Tuple<text, [u8]>) -> Tuple<text, [u8]> {
        \\    return pair
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.UnsupportedGcSyncType, emit_test_source(std.testing.allocator, source));
}

test "GC sync rejects a nonzero tuple byte-list update index" {
    const source =
        \\rewrite(pair Tuple<text, [u8]>) -> Tuple<text, [u8]> {
        \\    return Tuple<text, [u8]>{@get(pair, 0), @set(@get(pair, 1), 1, 65)}
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.UnsupportedGcSyncType, emit_test_source(std.testing.allocator, source));
}

test "GC sync rejects a local tuple outside the admitted rewrite" {
    const source =
        \\start() {
        \\    pair Tuple<text, [u8]> = Tuple<text, [u8]>{"hi", .{1, 2}}
        \\    _ = pair
        \\}
    ;
    try std.testing.expectError(error.UnknownGcSyncLocal, emit_test_source(std.testing.allocator, source));
}

test "GC sync rejects Tuple storage with a dedicated boundary" {
    const source =
        \\identity(values [Tuple<text, [u8]>]) -> [Tuple<text, [u8]>] {
        \\    return values
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.UnsupportedGcSyncTupleStorage, emit_test_source(std.testing.allocator, source));
}

test "GC sync rejects a missing managed child before WAT" {
    const source =
        \\Outer {
        \\    child Missing
        \\}
        \\identity(value Outer) -> Outer {
        \\    return value
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.UnsupportedGcSyncAggregate, emit_test_source(std.testing.allocator, source));
}

test "GC sync rejects a direct managed struct cycle before WAT" {
    const source =
        \\A {
        \\    next B
        \\}
        \\B {
        \\    next A
        \\}
        \\identity(value A) -> A {
        \\    return value
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.UnsupportedGcSyncAggregate, emit_test_source(std.testing.allocator, source));
}

test "GC sync rejects a resource field from a managed aggregate" {
    const source =
        \\Ticket = @wasi_resource("do:gc/ticket", { .id i64 })
        \\Envelope {
        \\    ticket Ticket
        \\}
        \\identity(value Envelope) -> Envelope {
        \\    return value
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.UnsupportedGcSyncAggregate, emit_test_source(std.testing.allocator, source));
}

test "GC sync rejects a standalone WASI resource declaration" {
    const source =
        \\Ticket = @wasi_resource("do:gc/ticket", { .id i64 })
        \\identity(value i32) -> i32 {
        \\    return value
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.UnsupportedGcSyncAggregate, emit_test_source(std.testing.allocator, source));
}

test "GC sync lowers one resolved generic managed identity" {
    const source =
        \\#T
        \\identity(value T) -> T {
        \\    return value
        \\}
        \\relay(input text) -> text {
        \\    return identity(input)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $identity__text (param $value (ref null $do_text)) (result (ref null $do_text))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $identity__text") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $identity (param") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync lowers a resolved generic managed field update" {
    const source =
        \\Box {
        \\    value [u8]
        \\}
        \\#T
        \\update(box T, next [u8]) -> T {
        \\    return @set(box, .value, next)
        \\}
        \\relay(box Box, next [u8]) -> Box {
        \\    return update(box, next)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $update__Box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(param $box (ref null $box))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $update__Box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync rejects an unresolved generic binding before WAT" {
    const source =
        \\#T
        \\identity(value T) -> T {
        \\    return value
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.UnsupportedGcSyncGenericUnresolved, emit_test_source(std.testing.allocator, source));
}

test "GC sync rejects a resource generic binding before WAT" {
    const source =
        \\Ticket = @wasi_resource("do:gc/ticket", { .id i64 })
        \\#T
        \\identity(value T) -> T {
        \\    return value
        \\}
        \\relay(value Ticket) -> Ticket {
        \\    return identity(value)
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.UnsupportedGcSyncGenericResource, emit_test_source(std.testing.allocator, source));
}

test "GC sync rejects a generic union binding before WAT" {
    const source =
        \\Choice = TextValue(text) | BytesValue([u8])
        \\#T
        \\identity(value T) -> T {
        \\    return value
        \\}
        \\relay(value Choice) -> Choice {
        \\    return identity(value)
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.UnsupportedGcSyncGenericUnion, emit_test_source(std.testing.allocator, source));
}

test "GC sync lowers len for admitted managed values" {
    const source =
        \\text_len(value text) -> usize {
        \\    return @len(value)
        \\}
        \\bytes_len(value [u8]) -> usize {
        \\    return @len(value)
        \\}
        \\scalar_len(value [i16]) -> usize {
        \\    return @len(value)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $do_text $length") != null);
    try std.testing.expect(std.mem.count(u8, wat, "array.len") >= 2);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync lowers eq for admitted scalar values" {
    const source =
        \\eq_i64(value i64) -> bool {
        \\    return @eq(value, 7)
        \\}
        \\eq_f32(value f32) -> bool {
        \\    return @eq(value, 1.5)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i64.eq") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "f32.eq") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync rejects a floating literal when eq expects bool" {
    const source =
        \\same(flag bool) -> bool {
        \\    return @eq(flag, 1.5)
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.GcSyncTypeMismatch, emit_test_source(std.testing.allocator, source));
}

test "GC sync rejects a floating literal when eq expects an integer" {
    const source =
        \\same(value i32) -> bool {
        \\    return @eq(value, 1.5)
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.GcSyncTypeMismatch, emit_test_source(std.testing.allocator, source));
}

test "GC sync rejects an integer literal outside its scalar range" {
    const source =
        \\same(value i8) -> bool {
        \\    return @eq(value, 128)
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.GcSyncTypeMismatch, emit_test_source(std.testing.allocator, source));
}

test "GC sync rejects len for an unadmitted managed aggregate" {
    const source =
        \\Box {
        \\    value [u8]
        \\}
        \\length(value Box) -> usize {
        \\    return @len(value)
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.UnsupportedGcSyncType, emit_test_source(std.testing.allocator, source));
}

test "GC sync rejects eq for managed references" {
    const source =
        \\same(left text, right text) -> bool {
        \\    return @eq(left, right)
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.UnsupportedGcSyncType, emit_test_source(std.testing.allocator, source));
}
