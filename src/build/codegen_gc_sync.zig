//! Restricted synchronous Wasm-GC lowering used by the migration gate.
//!
//! This module intentionally has a small admitted surface.  It lowers scalar
//! values, `text`, and `[u8]` values with typed GC references and fails closed
//! for aggregates, resources, host calls, and async syntax.  The normal ARC
//! pipeline remains the default until the later migration gates are closed.
const std = @import("std");
const generated_text = @import("codegen_text.zig");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const payload_wat = @import("wat_payload.zig");
const type_name = @import("type_name.zig");
const codegen_tokens = @import("codegen_tokens.zig");
const codegen_control_flow = @import("codegen_control_flow.zig");
const codegen_names = @import("codegen_names.zig");
const codegen_model = @import("codegen_model.zig");
const codegen_context = @import("codegen_context.zig");
const codegen_collect_structs = @import("codegen_collect_structs.zig");
const codegen_collect_declarations = @import("codegen_collect_declarations.zig");
const codegen_collect_util = @import("codegen_collect_util.zig");
const codegen_collect_reflection = @import("codegen_collect_reflection.zig");
const codegen_storage_layout = @import("codegen_storage_layout.zig");
const codegen_union_layout = @import("codegen_union_layout.zig");
const codegen_collect_functions = @import("codegen_collect_functions.zig");
const codegen_generics = @import("codegen_generics.zig");
const codegen_body = @import("codegen_body.zig");
const codegen_callbacks = @import("codegen_callbacks.zig");
const gc_adapter = @import("codegen_gc_sync_adapter.zig");
const gc_model_adapter = @import("codegen_gc_model_adapter.zig");
const gc_roots = @import("codegen_gc_roots.zig");
const runtime_gc_prelude = @import("runtime_gc_prelude_wat.zig");
const gc_layout = @import("codegen_gc_layout.zig");
const gc_representation = @import("codegen_gc_representation.zig");
const codegen_imports = @import("codegen_imports.zig");
const codegen_host_imports = @import("codegen_host_imports.zig");
const marshal_plan = @import("codegen_component_marshal_plan.zig");
const marshal_module = @import("codegen_component_marshal_module.zig");
const marshal_wat = @import("codegen_component_marshal_wat.zig");
const test_runner = @import("test_runner.zig");
const wat_function_body = @import("wat_function_body.zig");

const FuncDecl = codegen_model.FuncDecl;
const FuncResultItem = codegen_model.FuncResultItem;
const StructDecl = codegen_model.StructDecl;
const StructLayout = codegen_model.StructLayout;
const PayloadEnumDecl = codegen_model.PayloadEnumDecl;
const LocalSet = codegen_context.LocalSet;
const CodegenContext = codegen_context.CodegenContext;
const CollectionLoopHeader = codegen_context.CollectionLoopHeader;
const StringDataContext = codegen_context.StringDataContext;
const ImportedAliasContext = codegen_model.ImportedAliasContext;
const GcSyncHostWitRoute = codegen_model.GcSyncHostWitRoute;
const HostImport = codegen_model.HostImport;
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
const find_struct_local = codegen_context.find_struct_local;
const find_union_local = codegen_context.find_union_local;
const union_payload_local_name_from_locals = codegen_context.union_payload_local_name_from_locals;
const public_decl_name = codegen_names.public_decl_name;
const find_root_module_index = codegen_imports.find_root_module_index;
const is_error_like_type = codegen_collect_util.is_error_like_type;
const func_param_abi_type = codegen_collect_util.func_param_abi_type;
const union_layouts_equal = codegen_union_layout.union_layouts_equal;
const find_field_meta_local = codegen_storage_layout.find_field_meta_local;
const field_from_meta = codegen_storage_layout.field_from_meta;

const INDENT = "    ";

const DeferredCall = struct {
    start_idx: usize,
    end_idx: usize,
};

const GcLoopFrame = struct {
    source_label: ?[]const u8,
    break_label: []const u8,
    continue_label: []const u8,
};

const CallShape = struct {
    name_idx: usize,
    open_idx: usize,
    close_idx: usize,
};

const StructCtorValue = struct {
    start_idx: usize,
    end_idx: usize,
};

const max_nested_managed_segments: usize = 5;

const GenericNestedFieldPath = struct {
    root_local: []const u8,
    root_ty: []const u8,
    layouts: [max_nested_managed_segments + 1]gc_layout.GcStructLayout,
    managed_fields: [max_nested_managed_segments]gc_layout.GcFieldLayout,
    managed_depth: usize,
    terminal_field: gc_layout.GcFieldLayout,
    value_start: ?usize,
    value_end: ?usize,
};

const GcListTemps = struct {
    bytes_next_name: []u8,
    scalar_next_names: [gc_layout.scalar_array_specs.len][]u8,
    has_scalar_arrays: [gc_layout.scalar_array_specs.len]bool,
    managed_next_names: [][]u8,
    length_name: []u8,

    fn deinit(self: GcListTemps, allocator: std.mem.Allocator) void {
        allocator.free(self.bytes_next_name);
        for (self.scalar_next_names) |name| allocator.free(name);
        for (self.managed_next_names) |name| allocator.free(name);
        allocator.free(self.managed_next_names);
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
    gc_managed_arrays: []const gc_layout.GcManagedArrayLayout,
    locals: *LocalSet,
    result_tys: []const []const u8,
    result_items: []const FuncResultItem,
    result_struct: ?[]const u8,
    ctx: CodegenContext,
    out: *std.ArrayList(u8),
    gc_list_temps: GcListTemps,
    loop_stack: *std.ArrayList(GcLoopFrame),
    gc_host_route: ?*const GcSyncHostWitRoute = null,
    label_id: usize = 0,
    active_break_label: ?[]const u8 = null,
    active_loop_label: ?[]const u8 = null,

    fn append_fmt(self: *BodyEmitter, comptime fmt: []const u8, args: anytype) !void {
        try generated_text.append_fmt(self.allocator, self.out, fmt, args);
    }

    fn append_static(self: *BodyEmitter, text: []const u8) !void {
        try self.out.appendSlice(self.allocator, text);
    }

    fn append_block(self: *BodyEmitter, base_indent: usize, template: []const u8) !void {
        try generated_text.append_block(self.allocator, self.out, base_indent, template);
    }

    fn append_fmt_block(self: *BodyEmitter, base_indent: usize, comptime template: []const u8, args: anytype) !void {
        try generated_text.append_fmt_block(self.allocator, self.out, base_indent, template, args);
    }

    fn list_next_name(self: *const BodyEmitter, list_ty: []const u8) ![]const u8 {
        if (std.mem.eql(u8, list_ty, "[u8]")) return self.gc_list_temps.bytes_next_name;
        for (gc_layout.scalar_array_specs, 0..) |spec, index| {
            if (std.mem.eql(u8, list_ty, spec.list_ty)) return self.gc_list_temps.scalar_next_names[index];
        }
        for (self.gc_managed_arrays, 0..) |managed_array, index| {
            if (std.mem.eql(u8, managed_array.list_ty, list_ty)) return self.gc_list_temps.managed_next_names[index];
        }
        return error.UnsupportedGcSyncType;
    }

    fn list_array_name(self: *const BodyEmitter, list_ty: []const u8) ![]const u8 {
        if (std.mem.eql(u8, list_ty, "[u8]")) return "$do_bytes";
        if (gc_layout.scalar_array_spec_for_type(list_ty)) |spec| return spec.array_name;
        for (self.gc_managed_arrays) |managed_array| {
            if (std.mem.eql(u8, managed_array.list_ty, list_ty)) return managed_array.array_name;
        }
        return error.UnsupportedGcSyncType;
    }

    fn next_label(self: *BodyEmitter, prefix: []const u8) ![]u8 {
        const id = self.label_id;
        self.label_id += 1;
        return try std.fmt.allocPrint(self.allocator, "__gc_{s}_{d}", .{ prefix, id });
    }

    fn loop_control_target(self: *BodyEmitter, start_idx: usize, end_idx: usize, is_break: bool) ![]const u8 {
        var requested_label: ?[]const u8 = null;
        if (end_idx == start_idx + 1) {
            requested_label = null;
        } else if (end_idx == start_idx + 3 and tok_eq(self.tokens[start_idx + 1], "#") and
            self.tokens[start_idx + 2].kind == .ident)
        {
            requested_label = self.tokens[start_idx + 2].lexeme;
        } else {
            return error.UnsupportedGcSyncControl;
        }

        var index = self.loop_stack.items.len;
        while (index > 0) {
            index -= 1;
            const frame = self.loop_stack.items[index];
            if (requested_label) |label| {
                if (frame.source_label) |source_label| {
                    if (!std.mem.eql(u8, source_label, label)) continue;
                    return if (is_break) frame.break_label else frame.continue_label;
                }
                continue;
            }
            return if (is_break) frame.break_label else frame.continue_label;
        }
        return error.UnsupportedGcSyncControl;
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

    fn find_scalar_union(self: *BodyEmitter, name: []const u8) ?codegen_union_layout.UnionLayout {
        for (self.locals.union_locals.items) |union_local| {
            if (std.mem.eql(u8, union_local.layout.source_ty, name) and
                is_gc_scalar_union_layout(self.tokens, union_local.layout)) return union_local.layout;
        }
        for (self.functions) |func| {
            if (func.result_union) |layout| {
                if (std.mem.eql(u8, layout.source_ty, name) and is_gc_scalar_union_layout(self.tokens, layout)) return layout;
            }
        }
        return null;
    }

    fn scalar_union_result_layout(self: *const BodyEmitter) ?codegen_union_layout.UnionLayout {
        if (self.result_items.len != 1) return null;
        const layout = self.result_items[0].union_layout orelse return null;
        if (!is_gc_scalar_union_layout(self.tokens, layout)) return null;
        return layout;
    }

    fn emit_scalar_zero(self: *BodyEmitter, ty: []const u8) !void {
        const wasm_ty = gc_scalar_slot_wasm_type(self.tokens, ty) orelse return error.UnsupportedGcSyncType;
        try self.append_fmt("    {[wasm_ty]s}.const 0\n", .{ .wasm_ty = wasm_ty });
    }

    fn union_payload_local(self: *const BodyEmitter, base: []const u8, index: usize) ![]const u8 {
        return union_payload_local_name_from_locals(self.locals.locals.items, base, index) orelse error.UnknownGcSyncLocal;
    }

    fn union_tag_local(self: *const BodyEmitter, base: []const u8) ![]const u8 {
        return union_tag_local_name_from_locals(self.locals.locals.items, base) orelse error.UnknownGcSyncLocal;
    }

    fn append_struct_symbol(self: *BodyEmitter, name: []const u8) !void {
        try self.out.appendSlice(self.allocator, "$");
        for (name) |ch| try self.out.append(self.allocator, std.ascii.toLower(ch));
    }

    fn append_nested_temp_symbol(self: *BodyEmitter, name: []const u8) !void {
        try self.out.appendSlice(self.allocator, "$__gc_nested_");
        for (name) |ch| try self.out.append(self.allocator, std.ascii.toLower(ch));
    }

    fn emit_struct_field_from_local(
        self: *BodyEmitter,
        local_name: []const u8,
        layout: gc_layout.GcStructLayout,
        field: gc_layout.GcFieldLayout,
    ) !void {
        try self.append_fmt_block(4,
            \\local.get ${[local_name]s}
            \\ref.as_non_null
            \\struct.get{[space]s}
        , .{ .local_name = local_name, .space = " " });
        try self.append_struct_symbol(layout.name);
        try self.append_fmt(" ${[name]s}\n", .{ .name = public_decl_name(field.name) });
    }

    fn emit_reflection_text_value(self: *BodyEmitter, value: []const u8) !void {
        try self.append_fmt("    i32.const {[length]d}\n", .{ .length = value.len });
        if (value.len == 0) {
            try self.append_block(4,
                \\i32.const 0
                \\array.new_default $do_bytes
                \\
            );
        } else {
            for (value) |byte| try self.append_fmt("    i32.const {[byte]d}\n", .{ .byte = byte });
            try self.append_fmt("    array.new_fixed $do_bytes {[length]d}\n", .{ .length = value.len });
        }
        try self.append_static("    struct.new $do_text\n");
    }

    fn emit_field_reflection_intrinsic(self: *BodyEmitter, start_idx: usize, end_idx: usize, expected: ?[]const u8) anyerror!?[]const u8 {
        if (start_idx + 2 >= end_idx or !tok_eq(self.tokens[start_idx], "@") or
            (!tok_eq(self.tokens[start_idx + 1], "field_name") and
                !tok_eq(self.tokens[start_idx + 1], "field_index") and
                !tok_eq(self.tokens[start_idx + 1], "field_has_default"))) return null;
        if (!tok_eq(self.tokens[start_idx + 2], "(")) return error.UnsupportedGcSyncExpression;
        const close_idx = find_matching_in_range(self.tokens, start_idx + 2, "(", ")", end_idx) catch return error.UnsupportedGcSyncExpression;
        if (close_idx + 1 != end_idx) return error.UnsupportedGcSyncExpression;
        const arg_end = find_arg_end(self.tokens, start_idx + 3, close_idx);
        if (arg_end != close_idx or arg_end != start_idx + 4 or self.tokens[start_idx + 3].kind != .ident) return error.UnsupportedGcSyncExpression;
        const meta = find_field_meta_local(self.locals.field_meta_locals.items, self.tokens[start_idx + 3].lexeme) orelse return error.UnsupportedGcSyncExpression;
        const field = field_from_meta(self.ctx, meta) orelse return error.UnsupportedGcSyncExpression;
        if (tok_eq(self.tokens[start_idx + 1], "field_name")) {
            try ensure_compatible(expected, "text");
            try self.emit_reflection_text_value(public_decl_name(field.name));
            return "text";
        }
        if (tok_eq(self.tokens[start_idx + 1], "field_index")) {
            try ensure_compatible(expected, "usize");
            try self.append_fmt("    i32.const {[index]d}\n", .{ .index = meta.visible_index });
            return "usize";
        }
        try ensure_compatible(expected, "bool");
        try self.append_fmt("    i32.const {[value]d}\n", .{ .value = @intFromBool(field.default_start != null) });
        return "bool";
    }

    fn emit_field_get_reflection_expr(self: *BodyEmitter, start_idx: usize, end_idx: usize, expected: ?[]const u8) anyerror!?[]const u8 {
        if (start_idx + 2 >= end_idx or !tok_eq(self.tokens[start_idx], "@") or !tok_eq(self.tokens[start_idx + 1], "field_get")) return null;
        if (!tok_eq(self.tokens[start_idx + 2], "(")) return error.UnsupportedGcSyncExpression;
        const close_idx = find_matching_in_range(self.tokens, start_idx + 2, "(", ")", end_idx) catch return error.UnsupportedGcSyncExpression;
        if (close_idx + 1 != end_idx) return error.UnsupportedGcSyncExpression;
        const root_end = find_arg_end(self.tokens, start_idx + 3, close_idx);
        if (root_end >= close_idx or !tok_eq(self.tokens[root_end], ",") or root_end != start_idx + 4 or self.tokens[start_idx + 3].kind != .ident) return error.UnsupportedGcSyncExpression;
        const field_start = root_end + 1;
        const field_end = find_arg_end(self.tokens, field_start, close_idx);
        if (field_end != close_idx or field_end != field_start + 1 or self.tokens[field_start].kind != .ident) return error.UnsupportedGcSyncExpression;
        const root_name = self.tokens[start_idx + 3].lexeme;
        const root_local = find_local_name(self.locals.locals.items, root_name) orelse return error.UnknownGcSyncLocal;
        const root_ty = find_local_type(self.locals.locals.items, root_name) orelse return error.UnknownGcSyncLocal;
        const meta = find_field_meta_local(self.locals.field_meta_locals.items, self.tokens[field_start].lexeme) orelse return error.UnsupportedGcSyncExpression;
        if (!std.mem.eql(u8, root_ty, meta.struct_name)) return error.GcSyncTypeMismatch;
        const layout = find_gc_layout(self.gc_layouts, root_ty) orelse return error.UnsupportedGcSyncType;
        const field = field_from_meta(self.ctx, meta) orelse return error.UnsupportedGcSyncExpression;
        const gc_field = find_gc_field(layout, public_decl_name(field.name)) orelse return error.UnsupportedGcSyncExpression;
        try ensure_compatible(expected, field.ty);
        try self.emit_struct_field_from_local(root_local, layout, gc_field);
        return field.ty;
    }

    fn emit_struct_new(self: *BodyEmitter, layout: gc_layout.GcStructLayout) !void {
        try self.append_static(INDENT ++ "struct.new ");
        try self.append_struct_symbol(layout.name);
        try self.append_static("\n");
    }

    fn field_segment_name(self: *const BodyEmitter, start_idx: usize, end_idx: usize) ?[]const u8 {
        if (start_idx + 1 != end_idx or self.tokens[start_idx].kind != .ident) return null;
        const lexeme = self.tokens[start_idx].lexeme;
        if (lexeme.len < 2 or lexeme[0] != '.') return null;
        return lexeme[1..];
    }

    fn parse_generic_nested_field_path(
        self: *BodyEmitter,
        args_start: usize,
        args_end: usize,
        with_value: bool,
    ) anyerror!?GenericNestedFieldPath {
        const root_end = find_arg_end(self.tokens, args_start, args_end);
        if (root_end >= args_end or !tok_eq(self.tokens[root_end], ",") or
            root_end != args_start + 1 or self.tokens[args_start].kind != .ident)
        {
            return null;
        }
        const root_local = find_local_name(self.locals.locals.items, self.tokens[args_start].lexeme) orelse return null;
        const root_ty = find_local_type(self.locals.locals.items, self.tokens[args_start].lexeme) orelse return null;
        const root_layout = find_gc_layout(self.gc_layouts, root_ty) orelse return null;

        var path = std.mem.zeroes(GenericNestedFieldPath);
        path.root_local = root_local;
        path.root_ty = root_ty;
        path.layouts[0] = root_layout;

        var depth: usize = 0;
        var cursor = root_end + 1;
        if (cursor >= args_end) return null;

        if (!with_value) {
            while (cursor < args_end) {
                const segment_end = find_arg_end(self.tokens, cursor, args_end);
                const segment_name = self.field_segment_name(cursor, segment_end) orelse return error.UnsupportedGcSyncExpression;
                const current_layout = path.layouts[depth];
                const field = find_gc_field(current_layout, segment_name) orelse return error.UnsupportedGcSyncExpression;
                const has_next_segment = segment_end < args_end;
                if (has_next_segment) {
                    const child_layout = if (field.rep == .gc_managed)
                        find_gc_layout(self.gc_layouts, field.ty)
                    else
                        null;
                    if (child_layout == null) return null;
                    if (depth >= max_nested_managed_segments) return error.UnsupportedGcSyncExpression;
                    path.managed_fields[depth] = field;
                    path.layouts[depth + 1] = child_layout.?;
                    depth += 1;
                    cursor = segment_end + 1;
                    continue;
                }
                if (depth == 0) return null;
                path.managed_depth = depth;
                path.terminal_field = field;
                return path;
            }
            return null;
        }

        while (cursor < args_end) {
            const segment_end = find_arg_end(self.tokens, cursor, args_end);
            if (segment_end >= args_end) return null;
            const segment_name = self.field_segment_name(cursor, segment_end) orelse return error.UnsupportedGcSyncExpression;
            const current_layout = path.layouts[depth];
            const field = find_gc_field(current_layout, segment_name) orelse return error.UnsupportedGcSyncExpression;
            const value_start = segment_end + 1;
            if (value_start >= args_end) return error.UnsupportedGcSyncExpression;
            const value_end = find_arg_end(self.tokens, value_start, args_end);
            const next_is_field = self.field_segment_name(value_start, value_end) != null;
            if (next_is_field) {
                const child_layout = if (field.rep == .gc_managed)
                    find_gc_layout(self.gc_layouts, field.ty)
                else
                    null;
                if (child_layout == null) return null;
                if (depth >= max_nested_managed_segments) return error.UnsupportedGcSyncExpression;
                path.managed_fields[depth] = field;
                path.layouts[depth + 1] = child_layout.?;
                depth += 1;
                cursor = value_start;
                continue;
            }
            if (depth == 0) return null;
            if (value_end != args_end) return error.UnsupportedGcSyncExpression;
            path.managed_depth = depth;
            path.terminal_field = field;
            path.value_start = value_start;
            path.value_end = value_end;
            return path;
        }
        return null;
    }

    fn emit_struct_field_chain_from_local(
        self: *BodyEmitter,
        local_name: []const u8,
        layouts: []const gc_layout.GcStructLayout,
        fields: []const gc_layout.GcFieldLayout,
    ) !void {
        if (layouts.len != fields.len or layouts.len == 0) return error.UnsupportedGcSyncExpression;
        try self.append_fmt("    local.get ${[name]s}\n", .{ .name = local_name });
        for (layouts, fields) |layout, field| {
            try self.append_fmt_block(4,
                \\ref.as_non_null
                \\struct.get{[space]s}
            , .{ .space = " " });
            try self.append_struct_symbol(layout.name);
            try self.append_fmt(" ${[name]s}\n", .{ .name = public_decl_name(field.name) });
        }
    }

    fn emit_struct_field_chain_to_field(
        self: *BodyEmitter,
        local_name: []const u8,
        layouts: []const gc_layout.GcStructLayout,
        fields: []const gc_layout.GcFieldLayout,
        terminal_layout: gc_layout.GcStructLayout,
        terminal_field: gc_layout.GcFieldLayout,
    ) !void {
        if (layouts.len != fields.len) return error.UnsupportedGcSyncExpression;
        try self.append_fmt("    local.get ${[name]s}\n", .{ .name = local_name });
        for (layouts, fields) |layout, field| {
            try self.append_fmt_block(4,
                \\ref.as_non_null
                \\struct.get{[space]s}
            , .{ .space = " " });
            try self.append_struct_symbol(layout.name);
            try self.append_fmt(" ${[name]s}\n", .{ .name = public_decl_name(field.name) });
        }
        try self.append_fmt_block(4,
            \\ref.as_non_null
            \\struct.get{[space]s}
        , .{ .space = " " });
        try self.append_struct_symbol(terminal_layout.name);
        try self.append_fmt(" ${[name]s}\n", .{ .name = public_decl_name(terminal_field.name) });
    }

    fn emit_generic_nested_get(self: *BodyEmitter, path: GenericNestedFieldPath) !void {
        const depth = path.managed_depth;
        try self.emit_struct_field_chain_from_local(
            path.root_local,
            path.layouts[0..depth],
            path.managed_fields[0..depth],
        );
        try self.append_fmt_block(4,
            \\ref.as_non_null
            \\struct.get{[space]s}
        , .{ .space = " " });
        try self.append_struct_symbol(path.layouts[depth].name);
        try self.append_fmt(" ${[name]s}\n", .{ .name = public_decl_name(path.terminal_field.name) });
    }

    fn emit_generic_nested_set(
        self: *BodyEmitter,
        path: GenericNestedFieldPath,
        expected: ?[]const u8,
    ) ![]const u8 {
        if (path.terminal_field.rep != .inline_value or !type_name.is_core_wasm_scalar(path.terminal_field.ty)) {
            return error.UnsupportedGcSyncType;
        }
        try ensure_compatible(expected, path.root_ty);
        const value_start = path.value_start orelse return error.UnsupportedGcSyncExpression;
        const value_end = path.value_end orelse return error.UnsupportedGcSyncExpression;

        var level = path.managed_depth;
        while (true) {
            const layout = path.layouts[level];
            for (layout.fields) |field| {
                if (level == path.managed_depth and field.field_index == path.terminal_field.field_index) {
                    _ = try self.emit_expr(value_start, value_end, field.ty);
                } else if (level < path.managed_depth and field.field_index == path.managed_fields[level].field_index) {
                    try self.append_static(INDENT ++ "local.get ");
                    try self.append_nested_temp_symbol(path.layouts[level + 1].name);
                    try self.append_static("\n");
                } else {
                    try self.emit_struct_field_chain_to_field(
                        path.root_local,
                        path.layouts[0..level],
                        path.managed_fields[0..level],
                        layout,
                        field,
                    );
                }
            }
            try self.emit_struct_new(layout);
            if (level == 0) return path.root_ty;
            try self.append_static(INDENT ++ "local.set ");
            try self.append_nested_temp_symbol(layout.name);
            try self.append_static("\n");
            level -= 1;
        }
    }

    fn emit_scalar_union_local(self: *BodyEmitter, union_local: codegen_model.UnionLocal, layout: codegen_union_layout.UnionLayout) !void {
        if (!is_gc_scalar_union_layout(self.tokens, layout)) return error.UnsupportedGcSyncType;
        for (layout.payload_tys, 0..) |_, index| {
            const name = try self.union_payload_local(union_local.name, index);
            try self.append_fmt("    local.get ${[name]s}\n", .{ .name = name });
        }
        const tag = try self.union_tag_local(union_local.name);
        try self.append_fmt("    local.get ${[name]s}\n", .{ .name = tag });
    }

    fn store_scalar_union_local(self: *BodyEmitter, union_local: codegen_model.UnionLocal, layout: codegen_union_layout.UnionLayout) !void {
        var index = layout.payload_tys.len + 1;
        while (index > 0) {
            index -= 1;
            if (index == layout.payload_tys.len) {
                const tag = try self.union_tag_local(union_local.name);
                try self.append_fmt("    local.set ${[name]s}\n", .{ .name = tag });
            } else {
                const payload = try self.union_payload_local(union_local.name, index);
                try self.append_fmt("    local.set ${[name]s}\n", .{ .name = payload });
            }
        }
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

    fn emit_literal(self: *BodyEmitter, token: lexer.Token, expected: ?[]const u8) ![]const u8 {
        if (token.kind == .string) {
            const bytes = try codegen_tokens.decode_quoted_string_token(self.allocator, token.lexeme);
            defer self.allocator.free(bytes);
            if (expected) |wanted| {
                if (std.mem.eql(u8, wanted, "[u8]")) {
                    if (bytes.len == 0) {
                        try self.append_block(4,
                            \\i32.const 0
                            \\array.new_default $do_bytes
                            \\
                        );
                    } else {
                        for (bytes) |byte| try self.append_fmt("    i32.const {[byte]d}\n", .{ .byte = byte });
                        try self.append_fmt("    array.new_fixed $do_bytes {[length]d}\n", .{ .length = bytes.len });
                    }
                    return "[u8]";
                }
            }
            try self.append_fmt("    i32.const {[length]d}\n", .{ .length = bytes.len });
            if (bytes.len == 0) {
                try self.append_static("    i32.const 0\n");
                try self.append_static("    array.new_default $do_bytes\n");
            } else {
                for (bytes) |byte| try self.append_fmt("    i32.const {[byte]d}\n", .{ .byte = byte });
                try self.append_fmt("    array.new_fixed $do_bytes {[length]d}\n", .{ .length = bytes.len });
            }
            try self.append_static("    struct.new $do_text\n");
            return "text";
        }
        return error.UnsupportedGcSyncExpression;
    }

    fn emit_byte_list_literal(self: *BodyEmitter, start_idx: usize, end_idx: usize, expected: ?[]const u8) ![]const u8 {
        const list_ty = expected orelse return error.UnsupportedGcSyncType;
        const array_name = try self.list_array_name(list_ty);
        const elem_ty = type_name.storage_elem_type_from_name(list_ty) orelse return error.UnsupportedGcSyncType;
        const scalar_elem = type_name.is_core_wasm_scalar(elem_ty);
        const managed_elem = gc_adapter.is_admitted_managed_type_with_layouts(elem_ty, self.gc_structs, self.gc_layouts);
        if (!scalar_elem and !managed_elem) return error.UnsupportedGcSyncType;
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
            if (!scalar_elem) {
                const actual_ty = try self.emit_expr(item_start, item_end, elem_ty);
                try ensure_compatible(elem_ty, actual_ty);
            } else if (std.mem.eql(u8, elem_ty, "bool")) {
                if (token.kind != .ident or
                    (!std.mem.eql(u8, token.lexeme, "true") and !std.mem.eql(u8, token.lexeme, "false")))
                {
                    return error.GcSyncTypeMismatch;
                }
                try self.append_fmt("    i32.const {[value]d}\n", .{ .value = @intFromBool(std.mem.eql(u8, token.lexeme, "true")) });
            } else {
                if (token.kind != .number) return error.UnsupportedGcSyncExpression;
                const value = token.lexeme;
                try validate_numeric_literal(elem_ty, value);
                try self.append_fmt("    {[wasm_type]s}.const {[value]s}\n", .{
                    .wasm_type = payload_wat.wasm_type(elem_ty),
                    .value = value,
                });
            }
            count += 1;
            item_start = item_end;
            if (item_start < close_brace and tok_eq(self.tokens[item_start], ",")) item_start += 1;
        }

        if (count == 0) {
            try self.append_fmt_block(4,
                \\i32.const 0
                \\array.new_default{[space]s}
            , .{ .space = " " });
            try self.append_fmt("{[array_name]s}\n", .{ .array_name = array_name });
        } else {
            try self.append_fmt("    array.new_fixed {[array_name]s} {[count]d}\n", .{
                .array_name = array_name,
                .count = count,
            });
        }
        return list_ty;
    }

    fn emit_gc_host_call(
        self: *BodyEmitter,
        route: *const GcSyncHostWitRoute,
        shape: CallShape,
        expected: ?[]const u8,
    ) anyerror![]const u8 {
        const host = route.host_import;
        const plan = route.plan;
        if (host.tokens.ptr != self.tokens.ptr or host.tokens.len != self.tokens.len) return error.UnsupportedGcSyncCall;
        try marshal_plan.validate_sync_value_plan(plan);

        switch (plan.direction) {
            .lower => {
                if (host.params.len != 1 or host.result != null or plan.abi.arguments.len != 1 or plan.abi.results.len != 0) {
                    return error.UnsupportedGcSyncCall;
                }
                if (expected) |wanted| if (!std.mem.eql(u8, wanted, "nil")) return error.GcSyncTypeMismatch;
                const arg_start = shape.open_idx + 1;
                if (arg_start >= shape.close_idx) return error.GcSyncArityMismatch;
                const arg_end = find_arg_end(self.tokens, arg_start, shape.close_idx);
                if (arg_end <= arg_start or (arg_end < shape.close_idx and !tok_eq(self.tokens[arg_end], ","))) return error.GcSyncArityMismatch;
                const actual_ty = if (try is_pure_scalar_record_plan(plan))
                    try self.emit_inline_scalar_record_value(arg_start, arg_end, host.params[0])
                else
                    try self.emit_expr(arg_start, arg_end, host.params[0]);
                if (!std.mem.eql(u8, actual_ty, host.params[0])) return error.GcSyncTypeMismatch;
                if (arg_end != shape.close_idx) return error.GcSyncArityMismatch;
                try self.append_fmt("    call ${[name]s}\n", .{ .name = host.alias });
                return "nil";
            },
            .lift => {
                if (host.params.len != 0 or host.result == null or plan.abi.arguments.len != 0 or plan.abi.results.len != 1) {
                    return error.UnsupportedGcSyncCall;
                }
                if (shape.open_idx + 1 != shape.close_idx) return error.GcSyncArityMismatch;
                try self.append_fmt("    call ${[name]s}\n", .{ .name = host.alias });
                try ensure_compatible(expected, host.result.?);
                return host.result.?;
            },
        }
    }

    fn emit_inline_scalar_record_value(self: *BodyEmitter, start_idx: usize, end_idx: usize, expected: []const u8) anyerror![]const u8 {
        const range = trim_parens(self.tokens, start_idx, end_idx);
        if (range.end == range.start + 1 and self.tokens[range.start].kind == .ident) {
            const local = find_struct_local(self.locals.struct_locals.items, self.tokens[range.start].lexeme) orelse return error.UnknownGcSyncLocal;
            if (!std.mem.eql(u8, local.ty, expected)) return error.GcSyncTypeMismatch;
            try self.emit_inline_scalar_record_local(local.name, expected);
            return expected;
        }
        try self.emit_inline_struct_values(range.start, range.end, expected);
        return expected;
    }

    fn emit_inline_scalar_record_local(self: *BodyEmitter, local_name: []const u8, ty: []const u8) anyerror!void {
        const shape = self.inline_scalar_struct_shape(ty) orelse return error.UnsupportedGcSyncType;
        for (shape.fields) |field| {
            const field_name = try std.fmt.allocPrint(self.allocator, "{[base]s}.{[field]s}", .{
                .base = local_name,
                .field = public_decl_name(field.name),
            });
            defer self.allocator.free(field_name);
            if (self.inline_scalar_struct_shape(field.ty) != null) {
                try self.emit_inline_scalar_record_local(field_name, field.ty);
            } else {
                const field_local = find_local_name(self.locals.locals.items, field_name) orelse return error.UnknownGcSyncLocal;
                try self.append_fmt("    local.get ${[name]s}\n", .{ .name = field_local });
            }
        }
    }

    fn emit_inline_scalar_record_local_sets(self: *BodyEmitter, local_name: []const u8, ty: []const u8) anyerror!void {
        const shape = self.inline_scalar_struct_shape(ty) orelse return error.UnsupportedGcSyncType;
        var index = shape.fields.len;
        while (index > 0) {
            index -= 1;
            const field = shape.fields[index];
            const field_name = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ local_name, public_decl_name(field.name) });
            defer self.allocator.free(field_name);
            if (self.inline_scalar_struct_shape(field.ty) != null) {
                try self.emit_inline_scalar_record_local_sets(field_name, field.ty);
            } else {
                const field_local = find_local_name(self.locals.locals.items, field_name) orelse return error.UnknownGcSyncLocal;
                try self.append_fmt("    local.set ${[name]s}\n", .{ .name = field_local });
            }
        }
    }

    fn emit_call_expr(self: *BodyEmitter, shape: CallShape, expected: ?[]const u8) anyerror![]const u8 {
        const name = self.tokens[shape.name_idx].lexeme;
        if (self.gc_host_route) |route| {
            if (std.mem.eql(u8, name, route.host_import.source_alias)) {
                return self.emit_gc_host_call(route, shape, expected);
            }
        }
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
        try self.append_fmt("    call ${[name]s}\n", .{ .name = func.name });
        if (func.results.len == 0) {
            if (expected != null) return error.GcSyncTypeMismatch;
            return "nil";
        }
        if (func.result_union) |layout| {
            if (is_gc_scalar_union_layout(self.tokens, layout)) {
                if (expected == null or !std.mem.eql(u8, expected.?, layout.source_ty)) return error.UnsupportedGcSyncResult;
                return layout.source_ty;
            }
            if (find_gc_payload_union(self.gc_payload_unions, layout.source_ty) != null) {
                if (expected) |wanted| try ensure_compatible(wanted, layout.source_ty);
                try self.append_static("    ;; gc-root call_result\n");
                return layout.source_ty;
            }
            return error.UnsupportedGcSyncResult;
        }
        if (func.results.len != 1) return error.UnsupportedGcSyncResult;
        if (gc_adapter.is_admitted_managed_type_with_layouts_and_unions(
            func.results[0],
            self.gc_structs,
            self.gc_layouts,
            self.gc_payload_unions,
        )) {
            try self.append_static("    ;; gc-root call_result\n");
        }
        try ensure_compatible(expected, func.results[0]);
        return func.results[0];
    }

    fn emit_multi_result_return(self: *BodyEmitter, start_idx: usize, end_idx: usize) anyerror!void {
        if (self.result_tys.len <= 1) return error.UnsupportedGcSyncResult;
        const range = trim_parens(self.tokens, start_idx, end_idx);
        if (self.parse_call(range.start, range.end)) |shape| {
            const func = self.find_func(self.tokens[shape.name_idx].lexeme, null) orelse return error.UnsupportedGcSyncCall;
            if (func.is_async or func.contains_await or func.results.len != self.result_tys.len or func.result_items.len != func.results.len) return error.UnsupportedGcSyncResult;
            for (func.results, self.result_tys, func.result_items) |actual_ty, expected_ty, item| {
                if (item.abi_len != 1 or item.union_layout != null or !self.is_supported_multi_result_type(actual_ty)) return error.UnsupportedGcSyncResult;
                try ensure_compatible(expected_ty, actual_ty);
            }

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
            try self.append_fmt_block(4,
                \\call ${[name]s}
                \\return
                \\
            , .{ .name = func.name });
            return;
        }
        var expr_start = start_idx;
        var result_idx: usize = 0;
        while (expr_start < end_idx) {
            if (result_idx >= self.result_tys.len) return error.GcSyncArityMismatch;
            const expr_end = find_arg_end(self.tokens, expr_start, end_idx);
            if (expr_end <= expr_start) return error.GcSyncArityMismatch;
            const result_ty = self.result_tys[result_idx];
            if (!self.is_supported_multi_result_type(result_ty)) return error.UnsupportedGcSyncResult;
            _ = try self.emit_expr(expr_start, expr_end, result_ty);
            result_idx += 1;
            expr_start = expr_end;
            if (expr_start < end_idx and tok_eq(self.tokens[expr_start], ",")) expr_start += 1;
        }
        if (result_idx != self.result_tys.len) return error.GcSyncArityMismatch;
        try self.append_static("    return\n");
    }

    fn emit_multi_result_assignment(self: *BodyEmitter, start_idx: usize, end_idx: usize) anyerror!void {
        const eq_idx = find_top_level_token(self.tokens, start_idx, end_idx, "=") orelse return error.UnsupportedGcSyncStatement;
        if (find_top_level_token(self.tokens, start_idx, eq_idx, ",") == null) return error.UnsupportedGcSyncStatement;
        const range = trim_parens(self.tokens, eq_idx + 1, end_idx);
        const shape = self.parse_call(range.start, range.end) orelse return error.UnsupportedGcSyncStatement;
        const func = self.find_func(self.tokens[shape.name_idx].lexeme, null) orelse return error.UnsupportedGcSyncCall;
        if (func.is_async or func.contains_await or func.results.len <= 1 or func.result_items.len != func.results.len) return error.UnsupportedGcSyncResult;

        var lhs_names = std.ArrayList([]const u8).empty;
        defer lhs_names.deinit(self.allocator);
        var lhs_start = start_idx;
        var result_idx: usize = 0;
        while (lhs_start < eq_idx) {
            if (result_idx >= func.results.len) return error.GcSyncArityMismatch;
            const lhs_end = find_arg_end(self.tokens, lhs_start, eq_idx);
            if (lhs_end != lhs_start + 1 or self.tokens[lhs_start].kind != .ident) return error.UnsupportedGcSyncStatement;
            const local_name = find_local_name(self.locals.locals.items, self.tokens[lhs_start].lexeme) orelse return error.UnknownGcSyncLocal;
            const local_ty = find_local_type(self.locals.locals.items, self.tokens[lhs_start].lexeme) orelse return error.UnknownGcSyncLocal;
            const result_ty = func.results[result_idx];
            const item = func.result_items[result_idx];
            if (item.abi_len != 1 or item.union_layout != null or !self.is_supported_multi_result_type(result_ty)) return error.UnsupportedGcSyncResult;
            try BodyEmitter.ensure_compatible(local_ty, result_ty);
            try lhs_names.append(self.allocator, local_name);
            result_idx += 1;
            lhs_start = lhs_end;
            if (lhs_start < eq_idx and tok_eq(self.tokens[lhs_start], ",")) lhs_start += 1;
        }
        if (result_idx != func.results.len) return error.GcSyncArityMismatch;

        var arg_idx = shape.open_idx + 1;
        var param_idx: usize = 0;
        while (arg_idx < shape.close_idx) {
            if (param_idx >= func.params.len) return error.GcSyncArityMismatch;
            const arg_end = find_arg_end(self.tokens, arg_idx, shape.close_idx);
            if (arg_end <= arg_idx) return error.GcSyncArityMismatch;
            const actual_ty = try self.emit_expr(arg_idx, arg_end, func.params[param_idx].ty);
            try BodyEmitter.ensure_compatible(func.params[param_idx].ty, actual_ty);
            param_idx += 1;
            arg_idx = arg_end;
            if (arg_idx < shape.close_idx and tok_eq(self.tokens[arg_idx], ",")) arg_idx += 1;
        }
        if (param_idx != func.params.len) return error.GcSyncArityMismatch;
        try self.append_fmt("    call ${[name]s}\n", .{ .name = func.name });

        var set_idx = lhs_names.items.len;
        while (set_idx > 0) {
            set_idx -= 1;
            try self.append_fmt("    local.set ${[name]s}\n", .{ .name = lhs_names.items[set_idx] });
        }
    }

    fn emit_payload_union_ctor(self: *BodyEmitter, start_idx: usize, end_idx: usize, expected: ?[]const u8) anyerror!?[]const u8 {
        const expected_ty = expected orelse return null;
        const layout = self.find_payload_union(expected_ty) orelse return null;
        if (start_idx + 1 == end_idx and self.tokens[start_idx].kind == .ident and
            std.mem.eql(u8, self.tokens[start_idx].lexeme, layout.unit_case))
        {
            try self.emit_payload_union_fields(layout, layout.unit_tag, null);
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
        try self.emit_payload_union_fields(layout, layout.managed_tag, .{ .start = arg_start, .end = arg_end });
        return expected_ty;
    }

    const ExprRange = struct { start: usize, end: usize };

    fn emit_payload_union_fields(
        self: *BodyEmitter,
        layout: gc_layout.GcPayloadUnionLayout,
        tag: u32,
        managed_expr: ?ExprRange,
    ) !void {
        try self.append_fmt("    i32.const {[tag]d}\n", .{ .tag = tag });
        for (layout.payload_tys, 0..) |payload_ty, index| {
            if (index == layout.managed_payload_index) {
                if (managed_expr) |expr| {
                    _ = try self.emit_expr(expr.start, expr.end, "[u8]");
                } else {
                    try self.append_static("    ref.null $do_bytes\n");
                }
            } else {
                try self.emit_scalar_zero(payload_ty);
            }
        }
        try self.append_static(INDENT ++ "struct.new $");
        for (layout.name) |ch| try self.out.append(self.allocator, std.ascii.toLower(ch));
        try self.out.appendSlice(self.allocator, "\n");
    }

    fn emit_managed_union_value(
        self: *BodyEmitter,
        start_idx: usize,
        end_idx: usize,
        layout: gc_layout.GcPayloadUnionLayout,
    ) anyerror!bool {
        if (end_idx == start_idx + 1 and tok_eq(self.tokens[start_idx], layout.unit_case)) {
            try self.emit_payload_union_fields(layout, layout.unit_tag, null);
            return true;
        }
        if (end_idx == start_idx + 1 and self.tokens[start_idx].kind == .ident) {
            const local_ty = find_local_type(self.locals.locals.items, self.tokens[start_idx].lexeme) orelse return false;
            if (std.mem.eql(u8, local_ty, "[u8]")) {
                try self.emit_payload_union_fields(layout, layout.managed_tag, .{ .start = start_idx, .end = end_idx });
                return true;
            }
        }
        return false;
    }

    fn emit_scalar_union_branch(
        self: *BodyEmitter,
        start_idx: usize,
        end_idx: usize,
        layout: codegen_union_layout.UnionLayout,
        branch: codegen_union_layout.UnionBranch,
    ) anyerror!bool {
        const range = trim_parens(self.tokens, start_idx, end_idx);
        var payload_start = branch.payload_start;
        var payload_end = branch.payload_start + branch.payload_len;
        if (payload_end > layout.payload_tys.len) return error.UnsupportedGcSyncUnionConstructor;

        for (layout.payload_tys[0..payload_start]) |payload_ty| try self.emit_scalar_zero(payload_ty);

        var emitted_payload = false;
        if (branch.payload_len == 0) {
            emitted_payload = range.end == range.start + 1 and
                self.tokens[range.start].kind == .ident and
                std.mem.eql(u8, public_decl_name(self.tokens[range.start].lexeme), public_decl_name(branch.ty));
            if (!emitted_payload) {
                if (self.parse_call(range.start, range.end)) |shape| {
                    emitted_payload = self.tokens[shape.name_idx].kind == .ident and
                        shape.open_idx + 1 == shape.close_idx and
                        std.mem.eql(u8, public_decl_name(self.tokens[shape.name_idx].lexeme), public_decl_name(branch.ty));
                }
            }
        } else if (self.inline_scalar_struct_shape(branch.ty)) |shape| {
            if (range.end == range.start + 1 and self.tokens[range.start].kind == .ident) {
                const local = find_struct_local(self.locals.struct_locals.items, self.tokens[range.start].lexeme) orelse return false;
                if (std.mem.eql(u8, local.ty, branch.ty)) {
                    for (shape.fields) |field| {
                        const field_name = try std.fmt.allocPrint(self.allocator, "{[base]s}.{[field]s}", .{
                            .base = local.name,
                            .field = public_decl_name(field.name),
                        });
                        defer self.allocator.free(field_name);
                        const field_local = find_local_name(self.locals.locals.items, field_name) orelse return error.UnknownGcSyncLocal;
                        try self.append_fmt("    local.get ${[name]s}\n", .{ .name = field_local });
                    }
                    emitted_payload = true;
                }
            } else if (range.start + 1 < range.end and self.tokens[range.start].kind == .ident and
                std.mem.eql(u8, self.tokens[range.start].lexeme, branch.ty))
            {
                try self.emit_inline_struct_values(range.start, range.end, branch.ty);
                emitted_payload = true;
            }
        } else if (branch.payload_len == 1 and is_error_like_type(self.tokens, branch.ty) and
            range.end == range.start + 1 and self.tokens[range.start].kind == .ident and
            !std.mem.eql(u8, self.tokens[range.start].lexeme, branch.ty))
        {
            try self.append_static("    i32.const 1\n");
            emitted_payload = true;
        } else if (branch.payload_len == 1) {
            const payload_ty = layout.payload_tys[branch.payload_start];
            _ = try self.emit_expr(range.start, range.end, payload_ty);
            emitted_payload = true;
        }
        if (!emitted_payload) return false;
        payload_start = branch.payload_start;
        payload_end = branch.payload_start + branch.payload_len;
        for (layout.payload_tys[payload_end..]) |payload_ty| try self.emit_scalar_zero(payload_ty);
        try self.append_fmt("    i32.const {[tag]d}\n", .{ .tag = branch.tag });
        return true;
    }

    fn emit_scalar_union_value(
        self: *BodyEmitter,
        start_idx: usize,
        end_idx: usize,
        layout: codegen_union_layout.UnionLayout,
    ) anyerror!void {
        if (!is_gc_scalar_union_layout(self.tokens, layout)) return error.UnsupportedGcSyncType;
        const range = trim_parens(self.tokens, start_idx, end_idx);
        if (range.start >= range.end) return error.UnsupportedGcSyncExpression;
        if (self.parse_call(range.start, range.end)) |shape| {
            const actual = try self.emit_call_expr(shape, layout.source_ty);
            if (!std.mem.eql(u8, actual, layout.source_ty)) return error.GcSyncTypeMismatch;
            return;
        }
        if (range.end == range.start + 1 and tok_eq(self.tokens[range.start], "nil")) {
            for (layout.payload_tys) |payload_ty| try self.emit_scalar_zero(payload_ty);
            try self.append_static("    i32.const 0\n");
            return;
        }
        if (range.end == range.start + 1 and self.tokens[range.start].kind == .ident) {
            if (find_union_local(self.locals.union_locals.items, self.tokens[range.start].lexeme)) |union_local| {
                if (union_layouts_equal(union_local.layout, layout)) {
                    try self.emit_scalar_union_local(union_local, layout);
                    return;
                }
            }
        }
        for (layout.branches) |branch| {
            if (try self.emit_scalar_union_branch(range.start, range.end, layout, branch)) return;
        }
        return error.UnsupportedGcSyncUnionConstructor;
    }

    fn emit_scalar_union_result_values(self: *BodyEmitter, start_idx: usize, end_idx: usize, layout: codegen_union_layout.UnionLayout) !void {
        try self.emit_scalar_union_value(start_idx, end_idx, layout);
    }

    fn emit_get_field_expr(self: *BodyEmitter, start_idx: usize, end_idx: usize, expected: ?[]const u8) anyerror!?[]const u8 {
        if (start_idx + 1 >= end_idx or !tok_eq(self.tokens[start_idx], "@") or !tok_eq(self.tokens[start_idx + 1], "get")) return null;
        if (start_idx + 2 >= end_idx or !tok_eq(self.tokens[start_idx + 2], "(")) return null;
        const close_idx = find_matching_in_range(self.tokens, start_idx + 2, "(", ")", end_idx) catch return error.UnsupportedGcSyncExpression;
        if (close_idx + 1 != end_idx) return error.UnsupportedGcSyncExpression;
        if (try self.parse_generic_nested_field_path(start_idx + 3, close_idx, false)) |path| {
            try ensure_compatible(expected, path.terminal_field.ty);
            try self.emit_generic_nested_get(path);
            return path.terminal_field.ty;
        }
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
                find_gc_layout(self.gc_layouts, field.ty) != null or
                gc_adapter.is_managed_list_type(field.ty, self.gc_structs));
        if (!inline_scalar and !admitted_managed) return error.UnsupportedGcSyncType;
        try ensure_compatible(expected, field.ty);
        try generated_text.append_fmt_block(self.allocator, self.out, 4,
            \\    local.get ${[name]s}
            \\    ref.as_non_null
            \\    struct.get $
        , .{ .name = local_name });
        for (layout.name) |ch| try self.out.append(self.allocator, std.ascii.toLower(ch));
        try self.append_fmt(" ${[name]s}\n", .{ .name = public_decl_name(field.name) });
        return field.ty;
    }

    fn emit_get_scalar_list_expr(self: *BodyEmitter, start_idx: usize, end_idx: usize, expected: ?[]const u8) anyerror!?[]const u8 {
        if (start_idx + 1 >= end_idx or !tok_eq(self.tokens[start_idx], "@") or !tok_eq(self.tokens[start_idx + 1], "get")) return null;
        if (start_idx + 2 >= end_idx or !tok_eq(self.tokens[start_idx + 2], "(")) return error.UnsupportedGcSyncExpression;
        const close_idx = find_matching_in_range(self.tokens, start_idx + 2, "(", ")", end_idx) catch return error.UnsupportedGcSyncExpression;
        if (close_idx + 1 != end_idx) return error.UnsupportedGcSyncExpression;
        const receiver_end = find_arg_end(self.tokens, start_idx + 3, close_idx);
        if (receiver_end != start_idx + 4 or receiver_end >= close_idx or !tok_eq(self.tokens[receiver_end], ",") or self.tokens[start_idx + 3].kind != .ident) return null;
        const receiver_name = find_local_name(self.locals.locals.items, self.tokens[start_idx + 3].lexeme) orelse return error.UnknownGcSyncLocal;
        const list_ty = find_local_type(self.locals.locals.items, self.tokens[start_idx + 3].lexeme) orelse return error.UnknownGcSyncLocal;
        if (!std.mem.eql(u8, list_ty, "[u8]") and
            gc_layout.scalar_array_spec_for_type(list_ty) == null and
            !gc_adapter.is_managed_list_type(list_ty, self.gc_structs)) return null;
        const index_start = receiver_end + 1;
        const index_end = find_arg_end(self.tokens, index_start, close_idx);
        if (index_end != close_idx) return error.UnsupportedGcSyncExpression;
        const elem_ty = type_name.storage_elem_type_from_name(list_ty) orelse return error.UnsupportedGcSyncType;
        try ensure_compatible(expected, elem_ty);
        const array_name = try self.list_array_name(list_ty);
        try generated_text.append_fmt_block(self.allocator, self.out, 4,
            \\    local.get ${[name]s}
            \\    ref.as_non_null
        , .{ .name = receiver_name });
        _ = try self.emit_expr(index_start, index_end, "usize");
        try self.append_fmt("    array.get {[array_name]s}\n", .{ .array_name = array_name });
        return elem_ty;
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
        try self.append_fmt_block(4,
            \\local.get ${[receiver]s}
            \\ref.as_non_null
            \\struct.get $tuple_text_bytes ${[field]s}
            \\
        , .{ .receiver = receiver_name, .field = field_name });
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
        try generated_text.append_fmt_block(self.allocator, self.out, 4,
            \\    local.get ${[name]s}
            \\    ref.as_non_null
            \\    struct.get $tuple_text_bytes $bytes
        , .{ .name = tuple_name });
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
        try self.append_static("    struct.new $tuple_text_bytes\n");
        return expected.?;
    }

    fn inline_scalar_struct_shape(self: *const BodyEmitter, ty: []const u8) ?gc_representation.StructShape {
        for (self.gc_structs) |shape| {
            if (!std.mem.eql(u8, shape.name, ty)) continue;
            const rep = gc_representation.classify_type(ty, self.gc_structs, &.{}) catch return null;
            if (rep != .inline_value) return null;
            return shape;
        }
        return null;
    }

    fn emit_inline_scalar_struct_replacement(
        self: *BodyEmitter,
        local_name: []const u8,
        ty: []const u8,
        target_field_name: []const u8,
        value_start: usize,
        value_end: usize,
    ) anyerror!void {
        const shape = self.inline_scalar_struct_shape(ty) orelse return error.UnsupportedGcSyncType;
        for (shape.fields) |field| {
            const field_name = public_decl_name(field.name);
            if (std.mem.eql(u8, field_name, target_field_name)) {
                if (self.inline_scalar_struct_shape(field.ty) != null) return error.UnsupportedGcSyncType;
                _ = try self.emit_expr(value_start, value_end, field.ty);
                continue;
            }

            const nested_name = try std.fmt.allocPrint(self.allocator, "{[base]s}.{[field]s}", .{
                .base = local_name,
                .field = field_name,
            });
            defer self.allocator.free(nested_name);
            if (self.inline_scalar_struct_shape(field.ty) != null) {
                try self.emit_inline_scalar_record_local(nested_name, field.ty);
            } else {
                const field_local = find_local_name(self.locals.locals.items, nested_name) orelse return error.UnknownGcSyncLocal;
                try self.append_static("    ;; gc-root-read\n    ;; gc-unique-reuse\n");
                try self.append_fmt("    local.get ${[name]s}\n", .{ .name = field_local });
            }
        }
    }

    fn struct_field_local(self: *const BodyEmitter, struct_name: []const u8, field_name: []const u8) ![]const u8 {
        const candidate = try std.fmt.allocPrint(self.allocator, "{[base]s}.{[field]s}", .{
            .base = struct_name,
            .field = field_name,
        });
        defer self.allocator.free(candidate);
        return find_local_name(self.locals.locals.items, candidate) orelse error.UnknownGcSyncLocal;
    }

    fn emit_inline_struct_field_get(self: *BodyEmitter, struct_name: []const u8, field_name: []const u8) !void {
        const local_name = try self.struct_field_local(struct_name, field_name);
        try self.append_fmt("    local.get ${[name]s}\n", .{ .name = local_name });
    }

    fn emit_inline_struct_field_set(self: *BodyEmitter, struct_name: []const u8, field_name: []const u8) !void {
        const local_name = try self.struct_field_local(struct_name, field_name);
        try self.append_fmt("    local.set ${[name]s}\n", .{ .name = local_name });
    }

    fn emit_inline_struct_values(self: *BodyEmitter, start_idx: usize, end_idx: usize, expected: []const u8) anyerror!void {
        const shape = self.inline_scalar_struct_shape(expected) orelse return error.UnsupportedGcSyncType;
        if (start_idx + 2 >= end_idx or self.tokens[start_idx].kind != .ident or
            !std.mem.eql(u8, self.tokens[start_idx].lexeme, expected) or !tok_eq(self.tokens[start_idx + 1], "{")) return error.UnsupportedGcSyncExpression;
        const close_idx = find_matching_in_range(self.tokens, start_idx + 1, "{", "}", end_idx) catch return error.UnsupportedGcSyncExpression;
        if (close_idx + 1 != end_idx) return error.UnsupportedGcSyncExpression;

        for (shape.fields) |field| {
            var field_start: ?usize = null;
            var i = start_idx + 2;
            while (i + 1 < close_idx) : (i += 1) {
                if (self.tokens[i].kind != .ident or
                    (!std.mem.eql(u8, self.tokens[i].lexeme, field.name) and
                        !std.mem.eql(u8, self.tokens[i].lexeme, public_decl_name(field.name))) or
                    !tok_eq(self.tokens[i + 1], "=") or field_start != null) continue;
                field_start = i;
                break;
            }
            const field_idx = field_start orelse return error.UnsupportedGcSyncExpression;
            const value_start = field_idx + 2;
            const value_end = find_arg_end(self.tokens, value_start, close_idx);
            if (value_end <= value_start) return error.UnsupportedGcSyncExpression;
            const actual = try self.emit_expr(value_start, value_end, field.ty);
            try BodyEmitter.ensure_compatible(field.ty, actual);
        }
    }

    fn emit_inline_struct_call_values(self: *BodyEmitter, start_idx: usize, end_idx: usize, expected: []const u8) anyerror!void {
        const shape = self.inline_scalar_struct_shape(expected) orelse return error.UnsupportedGcSyncType;
        const call = self.parse_call(start_idx, end_idx) orelse return error.UnsupportedGcSyncExpression;
        if (self.gc_host_route) |route| {
            if (std.mem.eql(u8, self.tokens[call.name_idx].lexeme, route.host_import.source_alias)) {
                const actual = try self.emit_gc_host_call(route, call, expected);
                try BodyEmitter.ensure_compatible(expected, actual);
                return;
            }
        }
        const func = self.find_func(self.tokens[call.name_idx].lexeme, null) orelse return error.UnsupportedGcSyncCall;
        if (func.is_async or func.contains_await or func.result_struct == null or
            !std.mem.eql(u8, func.result_struct.?, expected) or func.result_items.len != 1 or
            func.result_items[0].abi_len != shape.fields.len or func.results.len != shape.fields.len) return error.UnsupportedGcSyncResult;
        for (shape.fields, 0..) |field, index| {
            try BodyEmitter.ensure_compatible(field.ty, func.results[index]);
        }

        var arg_idx = call.open_idx + 1;
        var param_idx: usize = 0;
        while (arg_idx < call.close_idx) {
            if (param_idx >= func.params.len) return error.GcSyncArityMismatch;
            const arg_end = find_arg_end(self.tokens, arg_idx, call.close_idx);
            if (arg_end <= arg_idx) return error.GcSyncArityMismatch;
            const actual = try self.emit_expr(arg_idx, arg_end, func.params[param_idx].ty);
            try BodyEmitter.ensure_compatible(func.params[param_idx].ty, actual);
            param_idx += 1;
            arg_idx = arg_end;
            if (arg_idx < call.close_idx and tok_eq(self.tokens[arg_idx], ",")) arg_idx += 1;
        }
        if (param_idx != func.params.len) return error.GcSyncArityMismatch;
        try self.append_fmt("    call ${[name]s}\n", .{ .name = func.name });
    }

    fn emit_inline_struct_result_values(self: *BodyEmitter, start_idx: usize, end_idx: usize, expected: []const u8) anyerror!void {
        const range = trim_parens(self.tokens, start_idx, end_idx);
        if (try self.emit_set_field_expr(range.start, range.end, expected)) |actual| {
            try ensure_compatible(expected, actual);
            return;
        }
        if (self.parse_call(range.start, range.end) != null) {
            try self.emit_inline_struct_call_values(range.start, range.end, expected);
            return;
        }
        if (range.end == range.start + 1 and self.tokens[range.start].kind == .ident) {
            const struct_local = find_struct_local(self.locals.struct_locals.items, self.tokens[range.start].lexeme) orelse return error.UnknownGcSyncLocal;
            if (!std.mem.eql(u8, struct_local.ty, expected)) return error.GcSyncTypeMismatch;
            try self.emit_inline_scalar_record_local(struct_local.name, expected);
            return;
        }
        try self.emit_inline_struct_values(range.start, range.end, expected);
    }

    fn emit_inline_struct_assignment(self: *BodyEmitter, target_name: []const u8, target_ty: []const u8, expr_start: usize, expr_end: usize) anyerror!void {
        try self.emit_inline_struct_result_values(expr_start, expr_end, target_ty);
        try self.emit_inline_scalar_record_local_sets(target_name, target_ty);
    }

    fn has_inline_scalar_struct_result(self: *const BodyEmitter) bool {
        return self.result_struct != null and self.result_items.len == 1 and self.result_items[0].abi_len == self.result_tys.len and self.inline_scalar_struct_shape(self.result_struct.?) != null;
    }

    fn emit_struct_ctor_expr(self: *BodyEmitter, start_idx: usize, end_idx: usize, expected: ?[]const u8) anyerror!?[]const u8 {
        const expected_ty = expected orelse return null;
        if (self.inline_scalar_struct_shape(expected_ty) != null) {
            try self.emit_inline_struct_values(start_idx, end_idx, expected_ty);
            return expected_ty;
        }
        const open_idx = if (start_idx + 1 < end_idx and self.tokens[start_idx].kind == .ident and
            !tok_eq(self.tokens[start_idx], ".") and tok_eq(self.tokens[start_idx + 1], "{"))
        blk: {
            if (!std.mem.eql(u8, self.tokens[start_idx].lexeme, expected_ty)) return null;
            break :blk start_idx + 1;
        } else if (start_idx + 1 < end_idx and tok_eq(self.tokens[start_idx], ".") and tok_eq(self.tokens[start_idx + 1], "{"))
            start_idx + 1
        else
            return null;
        const layout = find_gc_layout(self.gc_layouts, expected_ty) orelse return null;
        const close_idx = find_matching_in_range(self.tokens, open_idx, "{", "}", end_idx) catch return error.UnsupportedGcSyncExpression;
        if (close_idx + 1 != end_idx) return error.UnsupportedGcSyncExpression;

        var values = try self.allocator.alloc(?StructCtorValue, layout.fields.len);
        defer self.allocator.free(values);
        for (values) |*value| value.* = null;

        var field_start = open_idx + 1;
        while (field_start < close_idx) {
            if (tok_eq(self.tokens[field_start], ",")) {
                field_start += 1;
                continue;
            }
            if (self.tokens[field_start].kind != .ident or field_start + 1 >= close_idx or !tok_eq(self.tokens[field_start + 1], "=")) return error.UnsupportedGcSyncExpression;
            const value_start = field_start + 2;
            const value_end = find_arg_end(self.tokens, value_start, close_idx);
            if (value_end <= value_start) return error.UnsupportedGcSyncExpression;
            const field = find_gc_field(layout, self.tokens[field_start].lexeme) orelse return error.UnsupportedGcSyncExpression;
            const field_index: usize = @intCast(field.field_index);
            if (values[field_index] != null) return error.UnsupportedGcSyncExpression;
            values[field_index] = .{ .start_idx = value_start, .end_idx = value_end };
            field_start = value_end;
            if (field_start < close_idx and !tok_eq(self.tokens[field_start], ",")) return error.UnsupportedGcSyncExpression;
        }

        for (layout.fields, 0..) |field, index| {
            const value = values[index] orelse return error.UnsupportedGcSyncExpression;
            _ = try self.emit_expr(value.start_idx, value.end_idx, field.ty);
        }
        try self.append_static(INDENT ++ "struct.new $");
        for (layout.name) |ch| try self.out.append(self.allocator, std.ascii.toLower(ch));
        try self.out.appendSlice(self.allocator, "\n");
        return expected_ty;
    }

    fn emit_set_field_expr(self: *BodyEmitter, start_idx: usize, end_idx: usize, expected: ?[]const u8) anyerror!?[]const u8 {
        if (start_idx + 1 >= end_idx or !tok_eq(self.tokens[start_idx], "@") or !tok_eq(self.tokens[start_idx + 1], "set")) return null;
        if (start_idx + 2 >= end_idx or !tok_eq(self.tokens[start_idx + 2], "(")) return null;
        const close_idx = find_matching_in_range(self.tokens, start_idx + 2, "(", ")", end_idx) catch return error.UnsupportedGcSyncExpression;
        if (close_idx + 1 != end_idx) return error.UnsupportedGcSyncExpression;

        if (try self.parse_generic_nested_field_path(start_idx + 3, close_idx, true)) |path| {
            return @as(?[]const u8, try self.emit_generic_nested_set(path, expected));
        }
        const target_end = find_arg_end(self.tokens, start_idx + 3, close_idx);
        if (target_end >= close_idx or !tok_eq(self.tokens[target_end], ",")) return error.UnsupportedGcSyncExpression;
        if (try self.emit_set_tuple_bytes_expr(start_idx + 3, target_end, close_idx, expected)) |tuple_ty| return tuple_ty;
        if (target_end != start_idx + 4 or self.tokens[start_idx + 3].kind != .ident) return error.UnsupportedGcSyncExpression;
        const source_token = self.tokens[start_idx + 3];
        const struct_local = find_struct_local(self.locals.struct_locals.items, source_token.lexeme);
        const local_name = find_local_name(self.locals.locals.items, source_token.lexeme) orelse
            if (struct_local) |local| local.name else return error.UnknownGcSyncLocal;
        const struct_ty = find_local_type(self.locals.locals.items, source_token.lexeme) orelse
            if (struct_local) |local| local.ty else return error.UnknownGcSyncLocal;
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
        const managed_struct_list_field = target_field.rep == .gc_managed and gc_adapter.is_managed_list_type(target_field.ty, self.gc_structs);
        if (!scalar_field and !managed_byte_field and !managed_scalar_array_field and !managed_text_field and !managed_struct_field and !managed_struct_list_field) return error.UnsupportedGcSyncType;

        const value_start = field_end + 1;
        if (value_start >= close_idx) return error.UnsupportedGcSyncExpression;
        const value_end = find_arg_end(self.tokens, value_start, close_idx);
        if (value_end != close_idx) return error.UnsupportedGcSyncExpression;
        try ensure_compatible(expected, struct_ty);

        if (self.inline_scalar_struct_shape(struct_ty) != null) {
            if (target_field.rep != .inline_value or gc_scalar_slot_wasm_type(self.tokens, target_field.ty) == null) {
                return error.UnsupportedGcSyncType;
            }
            try self.append_static("    ;; gc-value-replacement\n");
            try self.emit_inline_scalar_struct_replacement(local_name, struct_ty, target_field_name, value_start, value_end);
            return struct_ty;
        }

        const direct_managed_call = if (target_field.rep == .gc_managed)
            self.is_direct_managed_call_producer(value_start, value_end, target_field.ty)
        else
            false;
        if (managed_byte_field) {
            if (try self.emit_nested_byte_field_expr(
                value_start,
                value_end,
                expected,
                source_token.lexeme,
                local_name,
                struct_ty,
                layout,
                target_field_name,
            )) |nested_ty| return nested_ty;
        }
        if (managed_byte_field and !self.is_direct_local_of_type(value_start, value_end, "[u8]") and
            !self.is_direct_field_get_of_type(value_start, value_end, "[u8]") and !direct_managed_call)
        {
            return error.UnsupportedGcSyncProducer;
        }
        if (managed_scalar_array_field and !self.is_direct_local_of_type(value_start, value_end, target_field.ty) and
            !self.is_direct_field_get_of_type(value_start, value_end, target_field.ty) and !direct_managed_call)
        {
            return error.UnsupportedGcSyncProducer;
        }
        if (managed_text_field and !self.is_direct_local_of_type(value_start, value_end, "text") and
            !(value_start + 1 == value_end and self.tokens[value_start].kind == .string) and
            !self.is_direct_field_get_of_type(value_start, value_end, "text") and !direct_managed_call)
        {
            return error.UnsupportedGcSyncProducer;
        }
        if (managed_struct_field and !self.is_direct_local_of_type(value_start, value_end, target_field.ty) and
            !self.is_direct_field_get_of_type(value_start, value_end, target_field.ty) and !direct_managed_call)
        {
            return error.UnsupportedGcSyncProducer;
        }
        if (managed_struct_list_field and !self.is_direct_local_of_type(value_start, value_end, target_field.ty) and
            !self.is_direct_field_get_of_type(value_start, value_end, target_field.ty) and !direct_managed_call)
        {
            return error.UnsupportedGcSyncProducer;
        }

        // Published values remain immutable: rebuild the aggregate and reuse
        // unchanged child references instead of mutating the source object.
        for (layout.fields) |field| {
            if (std.mem.eql(u8, public_decl_name(field.name), target_field_name)) {
                _ = try self.emit_expr(value_start, value_end, field.ty);
                continue;
            }
            try generated_text.append_fmt_block(self.allocator, self.out, 4,
                \\    local.get ${[name]s}
                \\    ref.as_non_null
                \\    struct.get $
            , .{ .name = local_name });
            for (layout.name) |ch| try self.out.append(self.allocator, std.ascii.toLower(ch));
            try self.append_fmt(" ${[name]s}\n", .{ .name = public_decl_name(field.name) });
        }
        try self.append_static(INDENT ++ "struct.new $");
        for (layout.name) |ch| try self.out.append(self.allocator, std.ascii.toLower(ch));
        try self.out.appendSlice(self.allocator, "\n");
        return struct_ty;
    }

    fn emit_nested_byte_field_expr(
        self: *BodyEmitter,
        start_idx: usize,
        end_idx: usize,
        expected: ?[]const u8,
        source_name: []const u8,
        local_name: []const u8,
        struct_ty: []const u8,
        layout: gc_layout.GcStructLayout,
        field_name: []const u8,
    ) anyerror!?[]const u8 {
        if (start_idx + 2 >= end_idx or !tok_eq(self.tokens[start_idx], "@") or
            !tok_eq(self.tokens[start_idx + 1], "set") or !tok_eq(self.tokens[start_idx + 2], "(")) return null;
        const inner_close = find_matching_in_range(self.tokens, start_idx + 2, "(", ")", end_idx) catch return error.UnsupportedGcSyncExpression;
        if (inner_close + 1 != end_idx) return error.UnsupportedGcSyncExpression;

        const inner_target_end = find_arg_end(self.tokens, start_idx + 3, inner_close);
        if (inner_target_end >= inner_close or !tok_eq(self.tokens[inner_target_end], ",")) return error.UnsupportedGcSyncProducer;
        if (!self.is_exact_get_field_local(start_idx + 3, inner_target_end, source_name, field_name)) return error.UnsupportedGcSyncProducer;

        const index_start = inner_target_end + 1;
        if (index_start >= inner_close) return error.UnsupportedGcSyncExpression;
        const index_end = find_arg_end(self.tokens, index_start, inner_close);
        if (index_end >= inner_close or !tok_eq(self.tokens[index_end], ",")) return error.UnsupportedGcSyncExpression;
        const value_start = index_end + 1;
        if (value_start >= inner_close) return error.UnsupportedGcSyncExpression;
        const value_end = find_arg_end(self.tokens, value_start, inner_close);
        if (value_end != inner_close) return error.UnsupportedGcSyncExpression;
        try ensure_compatible(expected, struct_ty);

        const next_name = try self.list_next_name("[u8]");
        try generated_text.append_fmt_block(self.allocator, self.out, 4,
            \\    local.get ${[name]s}
            \\    ref.as_non_null
            \\    struct.get $
        , .{ .name = local_name });
        for (layout.name) |ch| try self.out.append(self.allocator, std.ascii.toLower(ch));
        try self.append_fmt(" ${[field]s}\n", .{ .field = field_name });
        try generated_text.append_fmt_block(self.allocator, self.out, 4,
            \\    ref.as_non_null
            \\    array.len
            \\    local.set ${[length]s}
        , .{ .length = self.gc_list_temps.length_name });
        try generated_text.append_fmt_block(self.allocator, self.out, 4,
            \\    local.get ${[length]s}
            \\    i32.eqz
            \\    if unreachable end
        , .{ .length = self.gc_list_temps.length_name });
        try generated_text.append_fmt_block(self.allocator, self.out, 4,
            \\    local.get ${[length]s}
            \\    array.new_default $do_bytes
            \\    local.set ${[next]s}
        , .{ .length = self.gc_list_temps.length_name, .next = next_name });
        try generated_text.append_fmt_block(self.allocator, self.out, 4,
            \\    local.get ${[next]s}
            \\    i32.const 0
            \\    local.get ${[local]s}
            \\    ref.as_non_null
            \\    struct.get $
        , .{ .next = next_name, .local = local_name });
        for (layout.name) |ch| try self.out.append(self.allocator, std.ascii.toLower(ch));
        try self.append_fmt(" ${[field]s}\n", .{ .field = field_name });
        try generated_text.append_fmt_block(self.allocator, self.out, 4,
            \\    ref.as_non_null
            \\    i32.const 0
            \\    local.get ${[length]s}
            \\    array.copy $do_bytes $do_bytes
        , .{ .length = self.gc_list_temps.length_name });
        try self.append_fmt("    local.get ${[name]s}\n", .{ .name = next_name });
        _ = try self.emit_expr(index_start, index_end, "usize");
        _ = try self.emit_expr(value_start, value_end, "u8");
        try self.append_static("    array.set $do_bytes\n");

        // Keep the old outer object and its other fields untouched.
        for (layout.fields) |field| {
            if (std.mem.eql(u8, public_decl_name(field.name), field_name)) {
                try self.append_fmt("    local.get ${[name]s}\n", .{ .name = next_name });
                continue;
            }
            try generated_text.append_fmt_block(self.allocator, self.out, 4,
                \\    local.get ${[name]s}
                \\    ref.as_non_null
                \\    struct.get $
            , .{ .name = local_name });
            for (layout.name) |ch| try self.out.append(self.allocator, std.ascii.toLower(ch));
            try self.append_fmt(" ${[name]s}\n", .{ .name = public_decl_name(field.name) });
        }
        try self.append_static(INDENT ++ "struct.new $");
        for (layout.name) |ch| try self.out.append(self.allocator, std.ascii.toLower(ch));
        try self.out.appendSlice(self.allocator, "\n");
        return struct_ty;
    }

    fn is_exact_get_field_local(
        self: *const BodyEmitter,
        start_idx: usize,
        end_idx: usize,
        local_name: []const u8,
        field_name: []const u8,
    ) bool {
        if (start_idx + 2 >= end_idx or !tok_eq(self.tokens[start_idx], "@") or
            !tok_eq(self.tokens[start_idx + 1], "get") or !tok_eq(self.tokens[start_idx + 2], "(")) return false;
        const close_idx = find_matching_in_range(self.tokens, start_idx + 2, "(", ")", end_idx) catch return false;
        if (close_idx + 1 != end_idx) return false;
        const receiver_end = find_arg_end(self.tokens, start_idx + 3, close_idx);
        if (receiver_end >= close_idx or !tok_eq(self.tokens[receiver_end], ",") or receiver_end != start_idx + 4) return false;
        if (self.tokens[start_idx + 3].kind != .ident or !std.mem.eql(u8, self.tokens[start_idx + 3].lexeme, local_name)) return false;
        const field_idx = receiver_end + 1;
        if (field_idx + 1 != close_idx or self.tokens[field_idx].kind != .ident) return false;
        const field_token = self.tokens[field_idx];
        return field_token.lexeme.len == field_name.len + 1 and field_token.lexeme[0] == '.' and
            std.mem.eql(u8, field_token.lexeme[1..], field_name);
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
        try generated_text.append_fmt_block(self.allocator, self.out, 4,
            \\    ref.as_non_null
            \\    array.len
            \\    local.set ${[length]s}
        , .{ .length = self.gc_list_temps.length_name });
        try generated_text.append_fmt_block(self.allocator, self.out, 4,
            \\    local.get ${[length]s}
            \\    i32.eqz
            \\    if unreachable end
        , .{ .length = self.gc_list_temps.length_name });
        try generated_text.append_fmt_block(self.allocator, self.out, 4,
            \\    local.get ${[length]s}
            \\    array.new_default $do_bytes
            \\    local.set ${[next]s}
        , .{ .length = self.gc_list_temps.length_name, .next = next_name });
        try self.append_fmt_block(4,
            \\local.get ${[name]s}
            \\i32.const 0
            \\
        , .{ .name = next_name });
        try self.emit_tuple_bytes_get(tuple_name);
        try generated_text.append_fmt_block(self.allocator, self.out, 4,
            \\    ref.as_non_null
            \\    i32.const 0
            \\    local.get ${[length]s}
            \\    array.copy $do_bytes $do_bytes
        , .{ .length = self.gc_list_temps.length_name });
        try self.append_fmt("    local.get ${[name]s}\n", .{ .name = next_name });
        _ = try self.emit_expr(index_start, index_end, "usize");
        _ = try self.emit_expr(value_start, value_end, "u8");
        try self.append_fmt_block(4,
            \\array.set $do_bytes
            \\local.get ${[name]s}
            \\
        , .{ .name = next_name });
        return "[u8]";
    }

    fn is_direct_local_of_type(self: *BodyEmitter, start_idx: usize, end_idx: usize, expected: []const u8) bool {
        if (start_idx + 1 != end_idx or self.tokens[start_idx].kind != .ident) return false;
        const local_ty = find_local_type(self.locals.locals.items, self.tokens[start_idx].lexeme) orelse return false;
        return std.mem.eql(u8, local_ty, expected);
    }

    fn is_supported_multi_result_type(self: *const BodyEmitter, ty: []const u8) bool {
        return is_bounded_multi_result_type(ty) or find_gc_layout(self.gc_layouts, ty) != null;
    }

    fn is_direct_field_get_of_type(self: *BodyEmitter, start_idx: usize, end_idx: usize, expected: []const u8) bool {
        if (start_idx + 2 >= end_idx or !tok_eq(self.tokens[start_idx], "@") or
            !tok_eq(self.tokens[start_idx + 1], "get") or !tok_eq(self.tokens[start_idx + 2], "(")) return false;
        const close_idx = find_matching_in_range(self.tokens, start_idx + 2, "(", ")", end_idx) catch return false;
        if (close_idx + 1 != end_idx) return false;
        const receiver_end = find_arg_end(self.tokens, start_idx + 3, close_idx);
        if (receiver_end != start_idx + 4 or receiver_end >= close_idx or !tok_eq(self.tokens[receiver_end], ",") or
            self.tokens[start_idx + 3].kind != .ident) return false;
        const receiver_ty = find_local_type(self.locals.locals.items, self.tokens[start_idx + 3].lexeme) orelse return false;
        const layout = find_gc_layout(self.gc_layouts, receiver_ty) orelse return false;
        const field_idx = receiver_end + 1;
        if (field_idx + 1 != close_idx or self.tokens[field_idx].kind != .ident) return false;
        const field_token = self.tokens[field_idx];
        if (field_token.lexeme.len < 2 or field_token.lexeme[0] != '.') return false;
        const field = find_gc_field(layout, field_token.lexeme[1..]) orelse return false;
        return std.mem.eql(u8, field.ty, expected);
    }

    fn is_direct_managed_call_producer(self: *BodyEmitter, start_idx: usize, end_idx: usize, expected: []const u8) bool {
        if (!std.mem.eql(u8, expected, "[u8]") and !std.mem.eql(u8, expected, "text")) return false;
        const range = trim_parens(self.tokens, start_idx, end_idx);
        const shape = self.parse_call(range.start, range.end) orelse return false;
        const func = self.find_func(self.tokens[shape.name_idx].lexeme, expected) orelse return false;
        if (func.is_async or func.contains_await or func.results.len != 1 or
            !std.mem.eql(u8, func.results[0], expected)) return false;

        // Keep this admission to one direct call. Its arguments may be
        // literals, locals, or field reads, but not another call chain.
        var arg_idx = shape.open_idx + 1;
        while (arg_idx < shape.close_idx) {
            const arg_end = find_arg_end(self.tokens, arg_idx, shape.close_idx);
            if (arg_end <= arg_idx) return false;
            const arg_range = trim_parens(self.tokens, arg_idx, arg_end);
            if (self.parse_call(arg_range.start, arg_range.end) != null) return false;
            arg_idx = arg_end;
            if (arg_idx < shape.close_idx and tok_eq(self.tokens[arg_idx], ",")) arg_idx += 1;
        }
        return true;
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
        try generated_text.append_fmt_block(self.allocator, self.out, 4,
            \\    local.get ${[source]s}
            \\    ref.as_non_null
            \\    array.len
            \\    local.set ${[length]s}
        , .{ .source = source_name, .length = self.gc_list_temps.length_name });
        try generated_text.append_fmt_block(self.allocator, self.out, 4,
            \\    local.get ${[length]s}
            \\    i32.eqz
            \\    if unreachable end
        , .{ .length = self.gc_list_temps.length_name });
        try generated_text.append_fmt_block(self.allocator, self.out, 4,
            \\    local.get ${[length]s}
            \\    array.new_default {[array]s}
            \\    local.set ${[next]s}
        , .{
            .length = self.gc_list_temps.length_name,
            .array = array_name,
            .next = next_name,
        });
        try generated_text.append_fmt_block(self.allocator, self.out, 4,
            \\    local.get ${[next]s}
            \\    i32.const 0
            \\    local.get ${[source]s}
            \\    ref.as_non_null
            \\    i32.const 0
            \\    local.get ${[length]s}
            \\    array.copy {[array]s} {[array]s}
        , .{
            .next = next_name,
            .source = source_name,
            .length = self.gc_list_temps.length_name,
            .array = array_name,
        });
        try self.append_fmt("    local.get ${[name]s}\n", .{ .name = next_name });
        _ = try self.emit_expr(index_start, index_end, "usize");
        const value_ty = try self.emit_expr(value_start, value_end, elem_ty);
        if (!std.mem.eql(u8, value_ty, elem_ty)) return error.UnsupportedGcSyncType;
        try self.append_fmt_block(4,
            \\array.set {[array]s}
            \\local.get ${[next]s}
            \\
        , .{
            .array = array_name,
            .next = next_name,
        });
        return list_ty;
    }

    fn emit_put_scalar_list_expr(
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
        const elem_ty = type_name.storage_elem_type_from_name(receiver_ty) orelse return error.UnsupportedGcSyncType;
        const is_scalar_list = std.mem.eql(u8, receiver_ty, "[u8]") or gc_layout.scalar_array_spec_for_type(receiver_ty) != null;
        const is_managed_list = gc_adapter.is_managed_list_type(receiver_ty, self.gc_structs);
        if (!is_scalar_list and !is_managed_list) return error.UnsupportedGcSyncType;

        const value_start = receiver_end + 1;
        if (value_start >= close_idx or tok_eq(self.tokens[value_start], "...")) return error.UnsupportedGcSyncExpression;
        const value_end = find_arg_end(self.tokens, value_start, close_idx);
        if (value_end != close_idx) return error.UnsupportedGcSyncExpression;
        if (value_end == value_start + 2 and tok_eq(self.tokens[value_start], "-") and self.tokens[value_start + 1].kind == .number) return error.GcSyncTypeMismatch;
        try ensure_compatible(expected, receiver_ty);
        try self.ensure_exact_put_value(value_start, value_end, elem_ty);
        const array_name = try self.list_array_name(receiver_ty);
        const next_name = try self.list_next_name(receiver_ty);

        // Published lists remain immutable. Copy the source into a private
        // result backing, then append exactly one checked u8 element.
        try generated_text.append_fmt_block(self.allocator, self.out, 4,
            \\    local.get ${[receiver]s}
            \\    ref.as_non_null
            \\    array.len
            \\    local.set ${[length]s}
        , .{ .receiver = receiver_name, .length = self.gc_list_temps.length_name });
        try generated_text.append_fmt_block(self.allocator, self.out, 4,
            \\    local.get ${[length]s}
            \\    i32.const 1
            \\    i32.add
            \\    array.new_default {[array]s}
            \\    local.set ${[next]s}
        , .{
            .length = self.gc_list_temps.length_name,
            .array = array_name,
            .next = next_name,
        });
        try generated_text.append_fmt_block(self.allocator, self.out, 4,
            \\    local.get ${[next]s}
            \\    i32.const 0
            \\    local.get ${[receiver]s}
            \\    ref.as_non_null
            \\    i32.const 0
            \\    local.get ${[length]s}
            \\    array.copy {[array]s} {[array]s}
        , .{
            .next = next_name,
            .receiver = receiver_name,
            .length = self.gc_list_temps.length_name,
            .array = array_name,
        });
        try generated_text.append_fmt_block(self.allocator, self.out, 4,
            \\    local.get ${[next]s}
            \\    local.get ${[length]s}
        , .{ .next = next_name, .length = self.gc_list_temps.length_name });
        _ = try self.emit_expr(value_start, value_end, elem_ty);
        try self.append_fmt_block(4,
            \\array.set {[array]s}
            \\local.get ${[next]s}
            \\
        , .{
            .array = array_name,
            .next = next_name,
        });
        return receiver_ty;
    }

    fn emit_field_reflection_body(self: *BodyEmitter, start_idx: usize, end_idx: usize, result_ty: ?[]const u8, deferred: *std.ArrayList(DeferredCall)) anyerror!bool {
        var i = start_idx;
        while (i < end_idx) {
            const stmt_end = find_stmt_end(self.tokens, i, end_idx);
            if (stmt_end <= i) return error.UnsupportedGcSyncStatement;
            if (tok_eq(self.tokens[i], "if")) {
                const parts = codegen_collect_reflection.field_reflection_if_parts(self.tokens, i, stmt_end) orelse return error.UnsupportedGcSyncExpression;
                const condition = codegen_collect_reflection.field_static_bool_expr(self.tokens, parts.cond_start, parts.cond_end, self.locals, self.ctx) orelse return error.UnsupportedGcSyncExpression;
                if (condition) {
                    if (try self.emit_body(parts.then_start, parts.then_end, result_ty, deferred)) return true;
                } else if (parts.else_if_start) |nested_if| {
                    if (try self.emit_field_reflection_body(nested_if, stmt_end, result_ty, deferred)) return true;
                } else if (parts.else_start) |else_start| {
                    if (try self.emit_field_reflection_body(else_start, parts.else_end, result_ty, deferred)) return true;
                }
            } else if (try self.emit_body(i, stmt_end, result_ty, deferred)) {
                return true;
            }
            i = stmt_end;
        }
        return false;
    }

    fn emit_field_reflection_loop(self: *BodyEmitter, start_idx: usize, end_idx: usize, result_ty: ?[]const u8, deferred: *std.ArrayList(DeferredCall)) anyerror!void {
        const header = codegen_body.field_reflection_loop_header(self.tokens, start_idx, end_idx, self.ctx, self.locals) orelse return error.UnsupportedGcSyncExpression;
        try self.append_fmt("    ;; field-reflect-gc type={[type_name]s}\n", .{ .type_name = header.decl.name });
        var visible_index: usize = 0;
        for (header.decl.fields, 0..) |field, decl_index| {
            if (!codegen_collect_reflection.field_visible_from_tokens(field, header.decl, self.tokens)) continue;
            const prefix = try codegen_context.field_reflection_local_name_prefix(self.allocator, header, visible_index);
            defer self.allocator.free(prefix);
            var field_locals = try codegen_context.borrowed_field_meta_local_set(self.allocator, self.locals, .{
                .name = header.field_name,
                .struct_name = header.decl.name,
                .decl_index = decl_index,
                .visible_index = visible_index,
            }, prefix);
            defer field_locals.deinit(self.allocator);
            field_locals.local_name_prefix = prefix;
            const saw_return = blk: {
                const saved_locals = self.locals;
                defer self.locals = saved_locals;
                self.locals = &field_locals;
                break :blk try self.emit_field_reflection_body(header.open_brace + 1, header.close_brace, result_ty, deferred);
            };
            if (saw_return) break;
            visible_index += 1;
        }
    }

    fn emit_scalar_arithmetic_expr(self: *BodyEmitter, start_idx: usize, end_idx: usize, expected: ?[]const u8) anyerror!?[]const u8 {
        if (start_idx + 2 >= end_idx or !tok_eq(self.tokens[start_idx], "@") or
            (!tok_eq(self.tokens[start_idx + 1], "add") and !tok_eq(self.tokens[start_idx + 1], "sub"))) return null;
        if (!tok_eq(self.tokens[start_idx + 2], "(")) return error.UnsupportedGcSyncExpression;
        const close_idx = find_matching_in_range(self.tokens, start_idx + 2, "(", ")", end_idx) catch return error.UnsupportedGcSyncExpression;
        if (close_idx + 1 != end_idx) return error.UnsupportedGcSyncExpression;
        const first_end = find_arg_end(self.tokens, start_idx + 3, close_idx);
        if (first_end >= close_idx or !tok_eq(self.tokens[first_end], ",")) return error.UnsupportedGcSyncExpression;
        const second_start = first_end + 1;
        const second_end = find_arg_end(self.tokens, second_start, close_idx);
        if (second_end != close_idx) return error.UnsupportedGcSyncExpression;

        const left_ty = try self.emit_expr(start_idx + 3, first_end, expected);
        if (!type_name.is_core_wasm_scalar(left_ty) or std.mem.eql(u8, left_ty, "bool")) return error.UnsupportedGcSyncType;
        try ensure_compatible(expected, left_ty);
        const right_ty = try self.emit_expr(second_start, second_end, left_ty);
        try ensure_compatible(left_ty, right_ty);
        const wasm_ty = payload_wat.wasm_type(left_ty);
        const op = if (tok_eq(self.tokens[start_idx + 1], "add"))
            if (std.mem.eql(u8, wasm_ty, "i64")) "i64.add" else if (std.mem.eql(u8, wasm_ty, "f32")) "f32.add" else if (std.mem.eql(u8, wasm_ty, "f64")) "f64.add" else "i32.add"
        else if (std.mem.eql(u8, wasm_ty, "i64")) "i64.sub" else if (std.mem.eql(u8, wasm_ty, "f32")) "f32.sub" else if (std.mem.eql(u8, wasm_ty, "f64")) "f64.sub" else "i32.sub";
        try self.append_fmt("    {[op]s}\n", .{ .op = op });
        return left_ty;
    }

    fn ensure_exact_put_value(self: *BodyEmitter, start_idx: usize, end_idx: usize, elem_ty: []const u8) !void {
        if (start_idx + 1 == end_idx) {
            const token = self.tokens[start_idx];
            if (token.kind == .number) return validate_numeric_literal(elem_ty, token.lexeme);
            if (token.kind == .ident) {
                if (std.mem.eql(u8, token.lexeme, "true") or std.mem.eql(u8, token.lexeme, "false") or std.mem.eql(u8, token.lexeme, "nil")) return error.UnsupportedGcSyncType;
                const local_ty = find_local_type(self.locals.locals.items, token.lexeme) orelse return error.UnknownGcSyncLocal;
                if (!std.mem.eql(u8, local_ty, elem_ty)) return error.UnsupportedGcSyncType;
                return;
            }
            return error.UnsupportedGcSyncType;
        }
        const shape = self.parse_call(start_idx, end_idx) orelse return error.UnsupportedGcSyncExpression;
        const func = self.find_func(self.tokens[shape.name_idx].lexeme, elem_ty) orelse return error.UnsupportedGcSyncCall;
        if (func.results.len != 1 or !std.mem.eql(u8, func.results[0], elem_ty)) return error.UnsupportedGcSyncType;
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
        const is_list = std.mem.eql(u8, operand_ty, "[u8]") or
            gc_layout.scalar_array_spec_for_type(operand_ty) != null or
            gc_adapter.is_managed_list_type(operand_ty, self.gc_structs);
        if (!is_text and !is_list) return error.UnsupportedGcSyncType;
        try ensure_compatible(expected, "usize");
        if (is_text) {
            try self.append_block(4,
                \\ref.as_non_null
                \\struct.get $do_text $length
                \\
            );
        } else {
            try self.append_block(4,
                \\ref.as_non_null
                \\array.len
                \\
            );
        }
        return "usize";
    }

    fn emit_is_expr(self: *BodyEmitter, start_idx: usize, end_idx: usize, expected: ?[]const u8) anyerror!?[]const u8 {
        if (start_idx + 2 >= end_idx or !tok_eq(self.tokens[start_idx], "@") or !tok_eq(self.tokens[start_idx + 1], "is") or
            !tok_eq(self.tokens[start_idx + 2], "(")) return null;
        const close_idx = find_matching_in_range(self.tokens, start_idx + 2, "(", ")", end_idx) catch return error.UnsupportedGcSyncExpression;
        if (close_idx + 1 != end_idx) return error.UnsupportedGcSyncExpression;
        const value_end = find_arg_end(self.tokens, start_idx + 3, close_idx);
        if (value_end >= close_idx or !tok_eq(self.tokens[value_end], ",") or value_end != start_idx + 4 or
            self.tokens[start_idx + 3].kind != .ident) return error.UnsupportedGcSyncExpression;
        const union_local = find_union_local(self.locals.union_locals.items, self.tokens[start_idx + 3].lexeme) orelse return error.UnsupportedGcSyncType;
        if (!is_gc_scalar_union_layout(self.tokens, union_local.layout)) return error.UnsupportedGcSyncType;
        const type_start = value_end + 1;
        if (type_start + 1 != close_idx or self.tokens[type_start].kind != .ident) return error.UnsupportedGcSyncExpression;
        const wanted = self.tokens[type_start].lexeme;
        try ensure_compatible(expected, "bool");
        var matched = false;
        for (union_local.layout.branches) |branch| {
            if (!std.mem.eql(u8, public_decl_name(branch.ty), public_decl_name(wanted))) continue;
            try self.append_fmt_block(4,
                \\local.get ${[name]s}
                \\i32.const {[tag]d}
                \\i32.eq
                \\
            , .{
                .name = try self.union_tag_local(union_local.name),
                .tag = branch.tag,
            });
            matched = true;
            break;
        }
        if (!matched) return error.UnsupportedGcSyncType;
        return "bool";
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
        if (second_end == second_start + 1 and tok_eq(self.tokens[second_start], "nil")) {
            const left_range = trim_parens(self.tokens, start_idx + 3, first_end);
            if (self.parse_call(left_range.start, left_range.end)) |shape| {
                const func = self.find_func(self.tokens[shape.name_idx].lexeme, null) orelse return error.UnsupportedGcSyncCall;
                if (func.result_union) |union_layout| {
                    if (find_gc_payload_union(self.gc_payload_unions, union_layout.source_ty)) |payload_union| {
                        _ = try self.emit_expr(left_range.start, left_range.end, union_layout.source_ty);
            try generated_text.append_block(self.allocator, self.out, 4,
                \\    ref.as_non_null
                \\    struct.get $
            );
                        for (payload_union.name) |ch| try self.out.append(self.allocator, std.ascii.toLower(ch));
                        try self.append_static(" $tag\n");
                        try self.append_fmt_block(4,
                            \\i32.const {[tag]d}
                            \\i32.eq
                        , .{ .tag = payload_union.unit_tag });
                        return "bool";
                    }
                }
            }
        }
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
        try self.append_fmt("    {[op]s}\n", .{ .op = op });
        return "bool";
    }

    fn emit_expr(self: *BodyEmitter, start_idx: usize, end_idx: usize, expected: ?[]const u8) anyerror![]const u8 {
        const range = trim_parens(self.tokens, start_idx, end_idx);
        if (range.start >= range.end) return error.UnsupportedGcSyncExpression;
        if (expected) |expected_ty| {
            if (self.find_scalar_union(expected_ty)) |union_layout| {
                try self.emit_scalar_union_value(range.start, range.end, union_layout);
                return expected_ty;
            }
            if (self.find_payload_union(expected_ty)) |payload_union| {
                if (try self.emit_managed_union_value(range.start, range.end, payload_union)) return expected_ty;
            }
        }
        if (range.start + 1 < range.end and tok_eq(self.tokens[range.start], ".") and tok_eq(self.tokens[range.start + 1], "{")) {
            if (try self.emit_struct_ctor_expr(range.start, range.end, expected)) |struct_ty| return struct_ty;
            return self.emit_byte_list_literal(range.start, range.end, expected);
        }
        if (try self.emit_scalar_arithmetic_expr(range.start, range.end, expected)) |arithmetic_ty| return arithmetic_ty;
        if (try self.emit_field_reflection_intrinsic(range.start, range.end, expected)) |reflection_ty| return reflection_ty;
        if (try self.emit_field_get_reflection_expr(range.start, range.end, expected)) |field_ty| return field_ty;
        if (try self.emit_len_expr(range.start, range.end, expected)) |length_ty| return length_ty;
        if (try self.emit_is_expr(range.start, range.end, expected)) |is_ty| return is_ty;
        if (try self.emit_eq_expr(range.start, range.end, expected)) |comparison_ty| return comparison_ty;
        if (try self.emit_put_scalar_list_expr(range.start, range.end, expected)) |list_ty| return list_ty;
        if (try self.emit_get_scalar_list_expr(range.start, range.end, expected)) |element_ty| return element_ty;
        if (try self.emit_get_tuple_expr(range.start, range.end, expected)) |field_ty| return field_ty;
        if (try self.emit_get_field_expr(range.start, range.end, expected)) |field_ty| return field_ty;
        if (try self.emit_set_field_expr(range.start, range.end, expected)) |struct_ty| return struct_ty;
        if (try self.emit_tuple_text_bytes_constructor(range.start, range.end, expected)) |tuple_ty| return tuple_ty;
        if (try self.emit_struct_ctor_expr(range.start, range.end, expected)) |struct_ty| return struct_ty;
        if (try self.emit_payload_union_ctor(range.start, range.end, expected)) |union_ty| return union_ty;
        if (range.start + 1 == range.end) {
            const token = self.tokens[range.start];
            if (token.kind == .string) {
                const actual = try self.emit_literal(token, expected);
                try ensure_compatible(expected, actual);
                return actual;
            }
            if (token.kind == .number) {
                const ty = expected orelse "i32";
                try validate_numeric_literal(ty, token.lexeme);
                const wasm_ty = try gc_adapter.classify_admitted_type_with_layouts(ty, self.gc_structs, self.gc_layouts);
                if (wasm_ty.rep != .inline_value) return error.GcSyncTypeMismatch;
                try self.append_fmt("    {[wasm_type]s}.const {[value]s}\n", .{
                    .wasm_type = wasm_ty.wasm_type,
                    .value = token.lexeme,
                });
                return ty;
            }
            if (token.kind == .ident) {
                if (std.mem.eql(u8, token.lexeme, "true") or std.mem.eql(u8, token.lexeme, "false")) {
                    try ensure_compatible(expected, "bool");
                    try self.append_fmt("    i32.const {[value]d}\n", .{ .value = @intFromBool(std.mem.eql(u8, token.lexeme, "true")) });
                    return "bool";
                }
                if (std.mem.eql(u8, token.lexeme, "nil")) return "nil";
                if (find_union_local(self.locals.union_locals.items, token.lexeme)) |union_local| {
                    try ensure_compatible(expected, union_local.layout.source_ty);
                    if (is_gc_scalar_union_layout(self.tokens, union_local.layout)) {
                        try self.emit_scalar_union_local(union_local, union_local.layout);
                    } else {
                        try self.append_fmt("    local.get ${[name]s}\n", .{ .name = union_local.name });
                    }
                    return union_local.layout.source_ty;
                }
                const local_name = find_local_name(self.locals.locals.items, token.lexeme) orelse return error.UnknownGcSyncLocal;
                const local_ty = find_local_type(self.locals.locals.items, token.lexeme) orelse return error.UnknownGcSyncLocal;
                try ensure_compatible(expected, local_ty);
                try self.append_fmt("    local.get ${[name]s}\n", .{ .name = local_name });
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
            try self.emit_result_drops(call.start_idx, call.end_idx, result_ty);
        }
    }

    fn emit_result_drops(self: *BodyEmitter, start_idx: usize, end_idx: usize, result_ty: []const u8) !void {
        if (std.mem.eql(u8, result_ty, "nil")) return;
        var count: usize = 1;
        if (self.gc_host_route) |route| {
            if (route.plan.direction == .lift and
                std.mem.eql(u8, self.tokens[trim_parens(self.tokens, start_idx, end_idx).start].lexeme, route.host_import.source_alias))
            {
                count = marshal_wat.sync_scalar_record_leaf_count(route.plan) catch 1;
            }
        }
        for (0..count) |_| try self.append_static("    drop\n");
    }

    fn emit_return(self: *BodyEmitter, start_idx: usize, end_idx: usize, result_ty: ?[]const u8, deferred: *std.ArrayList(DeferredCall)) anyerror!void {
        try self.emit_deferred(deferred.items);
        if (start_idx + 1 == end_idx) {
            if (result_ty != null) return error.MissingGcSyncReturn;
            try self.append_static("    return\n");
            return;
        }
        if (self.scalar_union_result_layout()) |union_layout| {
            try self.emit_scalar_union_result_values(start_idx + 1, end_idx, union_layout);
            try self.append_static("    return\n");
            return;
        }
        if (self.has_inline_scalar_struct_result()) {
            try self.emit_inline_struct_result_values(start_idx + 1, end_idx, self.result_struct.?);
            try self.append_static("    return\n");
            return;
        }
        if (self.result_items.len == 1 and self.result_items[0].union_layout != null) {
            if (find_gc_payload_union(self.gc_payload_unions, self.result_items[0].ty)) |payload_union| {
                if (!try self.emit_managed_union_value(start_idx + 1, end_idx, payload_union)) return error.UnsupportedGcSyncExpression;
                try self.append_static("    return\n");
                return;
            }
        }
        if (self.result_tys.len > 1) {
            try self.emit_multi_result_return(start_idx + 1, end_idx);
            return;
        }
        if (result_ty) |ty| if (gc_adapter.is_admitted_managed_type_with_layouts(ty, self.gc_structs, self.gc_layouts)) try self.append_static("    ;; gc-root return_value\n");
        const actual = try self.emit_expr(start_idx + 1, end_idx, result_ty);
        if (result_ty == null) {
            if (!std.mem.eql(u8, actual, "nil")) return error.UnexpectedGcSyncReturn;
            return;
        }
        if (std.mem.eql(u8, actual, "nil")) return error.UnexpectedGcSyncReturn;
        try self.append_static("    return\n");
    }

    fn emit_if(self: *BodyEmitter, start_idx: usize, end_idx: usize, result_ty: ?[]const u8, deferred: *std.ArrayList(DeferredCall)) anyerror!void {
        const open_idx = find_top_level_block_open(self.tokens, start_idx + 1, end_idx) orelse return error.UnsupportedGcSyncControl;
        const close_idx = find_matching_in_range(self.tokens, open_idx, "{", "}", end_idx) catch return error.UnsupportedGcSyncControl;
        if (close_idx >= end_idx) return error.UnsupportedGcSyncControl;
        _ = try self.emit_expr(start_idx + 1, open_idx, "bool");
        try self.append_static("    if\n");
        _ = try self.emit_body(open_idx + 1, close_idx, result_ty, deferred);
        if (close_idx + 1 < end_idx and tok_eq(self.tokens[close_idx + 1], "else")) {
            try self.append_static("    else\n");
            if (close_idx + 2 < end_idx and tok_eq(self.tokens[close_idx + 2], "if")) {
                // Keep nested else-if lowering on the same typed GC path.
                // The recursive emitter remains bounded by the enclosing
                // statement range and preserves one branch-join marker per
                // nested decision.
                try self.emit_if(close_idx + 2, end_idx, result_ty, deferred);
            } else {
                const else_open = find_top_level_block_open(self.tokens, close_idx + 2, end_idx) orelse return error.UnsupportedGcSyncControl;
                const else_close = find_matching_in_range(self.tokens, else_open, "{", "}", end_idx) catch return error.UnsupportedGcSyncControl;
                if (else_close + 1 != end_idx) return error.UnsupportedGcSyncControl;
                _ = try self.emit_body(else_open + 1, else_close, result_ty, deferred);
            }
        }
        try self.append_block(4,
            \\end
            \\;; gc-root branch_join
            \\
        );
    }

    fn emit_guard_return(self: *BodyEmitter, start_idx: usize, end_idx: usize, result_ty: ?[]const u8, deferred: *std.ArrayList(DeferredCall)) anyerror!bool {
        const return_idx = find_top_level_token(self.tokens, start_idx + 1, end_idx, "return") orelse return false;
        if (return_idx == start_idx + 1) return error.UnsupportedGcSyncControl;
        _ = try self.emit_expr(start_idx + 1, return_idx, "bool");
        try self.append_static("    if\n");
        try self.emit_return(return_idx, end_idx, result_ty, deferred);
        try self.append_block(4,
            \\end
            \\;; gc-root guard_join
            \\
        );
        return true;
    }

    fn emit_guard_loop_control(self: *BodyEmitter, start_idx: usize, end_idx: usize) anyerror!bool {
        const break_idx = find_top_level_token(self.tokens, start_idx + 1, end_idx, "break");
        const continue_idx = find_top_level_token(self.tokens, start_idx + 1, end_idx, "continue");
        const control_idx = break_idx orelse continue_idx orelse return false;
        _ = try self.emit_expr(start_idx + 1, control_idx, "bool");
        try self.append_static("    if\n");
        if (break_idx != null) {
            try self.append_fmt("    br ${[label]s}\n", .{ .label = try self.loop_control_target(control_idx, end_idx, true) });
        } else {
            try self.append_fmt("    br ${[label]s}\n", .{ .label = try self.loop_control_target(control_idx, end_idx, false) });
        }
        try self.append_static("    end\n");
        return true;
    }

    fn emit_collection_loop(self: *BodyEmitter, start_idx: usize, header: CollectionLoopHeader, result_ty: ?[]const u8, deferred: *std.ArrayList(DeferredCall)) !void {
        if (header.source_is_expr) return error.UnsupportedGcSyncProducer;
        const array_name = try self.list_array_name(header.source_ty);
        const index_local = try std.fmt.allocPrint(self.allocator, "__loop_index_{d}", .{start_idx});
        defer self.allocator.free(index_local);
        const break_label = try self.next_label("collection_break");
        defer self.allocator.free(break_label);
        const body_label = try self.next_label("collection_body");
        defer self.allocator.free(body_label);
        const continue_label = try self.next_label("collection_continue");
        defer self.allocator.free(continue_label);

        const previous_break = self.active_break_label;
        const previous_loop = self.active_loop_label;
        self.active_break_label = break_label;
        self.active_loop_label = continue_label;
        defer {
            self.active_break_label = previous_break;
            self.active_loop_label = previous_loop;
        }
        try self.loop_stack.append(self.allocator, .{
            .source_label = codegen_control_flow.label_for_loop_start(self.tokens, start_idx),
            .break_label = break_label,
            .continue_label = continue_label,
        });
        defer _ = self.loop_stack.pop();

        try self.append_fmt_block(4,
            \\;; gc-loop-collection
            \\i32.const 0
            \\local.set ${[index]s}
            \\block ${[break_label]s}
            \\loop ${[body_label]s}
            \\
        , .{ .index = index_local, .break_label = break_label, .body_label = body_label });
        try self.append_fmt_block(4,
            \\local.get ${[index]s}
            \\local.get ${[source]s}
            \\ref.as_non_null
            \\array.len
            \\i32.ge_u
            \\br_if ${[break_label]s}
            \\
        , .{ .index = index_local, .source = header.source_name, .break_label = break_label });

        if (header.index_name) |index_name| {
            try self.append_fmt_block(4,
                \\local.get ${[index]s}
                \\local.set ${[name]s}
                \\
            , .{ .index = index_local, .name = index_name });
        }
        if (header.value_name) |value_name| {
            try self.append_fmt_block(4,
                \\local.get ${[source]s}
                \\ref.as_non_null
                \\local.get ${[index]s}
                \\array.get {[array]s}
                \\local.set ${[name]s}
                \\
            , .{
                .source = header.source_name,
                .index = index_local,
                .array = array_name,
                .name = value_name,
            });
        }
        try self.append_fmt("    block ${[label]s}\n", .{ .label = continue_label });
        _ = try self.emit_body(header.open_brace + 1, header.close_brace, result_ty, deferred);
        try self.append_fmt_block(4,
            \\end
            \\local.get ${[index]s}
            \\i32.const 1
            \\i32.add
            \\local.set ${[next_index]s}
            \\br ${[body]s}
            \\end
            \\end
            \\
        , .{ .index = index_local, .next_index = index_local, .body = body_label });
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
        try self.loop_stack.append(self.allocator, .{
            .source_label = codegen_control_flow.label_for_loop_start(self.tokens, start_idx),
            .break_label = break_label,
            .continue_label = loop_label,
        });
        defer _ = self.loop_stack.pop();
        try self.append_fmt_block(4,
            \\block ${[break_label]s}
            \\loop ${[loop_label]s}
            \\
        , .{ .break_label = break_label, .loop_label = loop_label });
        _ = try self.emit_body(open_idx + 1, close_idx, result_ty, deferred);
        try self.append_block(4,
            \\end
            \\end
            \\;; gc-root loop_join
            \\
        );
    }

    fn emit_assignment(self: *BodyEmitter, start_idx: usize, end_idx: usize) !void {
        if (start_idx >= end_idx or self.tokens[start_idx].kind != .ident) return error.UnsupportedGcSyncStatement;
        const eq_idx = find_top_level_token(self.tokens, start_idx + 1, end_idx, "=") orelse return error.UnsupportedGcSyncStatement;
        const expr_start = eq_idx + 1;
        if (expr_start >= end_idx) return error.UnsupportedGcSyncStatement;
        if (find_struct_local(self.locals.struct_locals.items, self.tokens[start_idx].lexeme)) |struct_local| {
            if (self.inline_scalar_struct_shape(struct_local.ty) != null) {
                try self.emit_inline_struct_assignment(struct_local.name, struct_local.ty, expr_start, end_idx);
                return;
            }
        }
        var inferred_binding = false;
        for (self.locals.locals.items) |local| {
            if (std.mem.eql(u8, local.name, self.tokens[start_idx].lexeme)) {
                inferred_binding = local.origin == .fresh_local;
                break;
            }
        }
        const is_binding = eq_idx > start_idx + 1 or inferred_binding;
        var target_name: []const u8 = undefined;
        var target_ty: []const u8 = undefined;
        var managed_target = false;
        if (find_union_local(self.locals.union_locals.items, self.tokens[start_idx].lexeme)) |union_local| {
            target_name = union_local.name;
            target_ty = union_local.layout.source_ty;
            if (is_gc_scalar_union_layout(self.tokens, union_local.layout)) {
                try self.emit_scalar_union_value(expr_start, end_idx, union_local.layout);
                try self.store_scalar_union_local(union_local, union_local.layout);
                return;
            }
            managed_target = find_gc_payload_union(self.gc_payload_unions, target_ty) != null;
        } else {
            target_name = find_local_name(self.locals.locals.items, self.tokens[start_idx].lexeme) orelse return error.UnknownGcSyncLocal;
            target_ty = find_local_type(self.locals.locals.items, self.tokens[start_idx].lexeme) orelse return error.UnknownGcSyncLocal;
            managed_target = gc_adapter.is_admitted_managed_type_with_layouts(target_ty, self.gc_structs, self.gc_layouts);
        }
        if (managed_target and !is_binding) try self.append_fmt("    ;; gc-root overwrite ${[name]s}\n", .{ .name = target_name });
        _ = try self.emit_expr(expr_start, end_idx, target_ty);
        try self.append_fmt("    local.set ${[name]s}\n", .{ .name = target_name });
        if (managed_target and is_binding) try self.append_fmt("    ;; gc-root local_bind ${[name]s}\n", .{ .name = target_name });
        if (inferred_binding) {
            for (self.locals.locals.items) |*local| {
                if (std.mem.eql(u8, local.name, target_name)) {
                    local.origin = .unknown;
                    break;
                }
            }
        }
    }

    fn emit_body(self: *BodyEmitter, start_idx: usize, end_idx: usize, result_ty: ?[]const u8, deferred: *std.ArrayList(DeferredCall)) anyerror!bool {
        const inherited_defer_count = deferred.items.len;
        var i = start_idx;
        var saw_return = false;
        while (i < end_idx) {
            const stmt_end = find_stmt_end(self.tokens, i, end_idx);
            if (stmt_end <= i) return error.UnsupportedGcSyncStatement;
            if (tok_eq(self.tokens[i], "if")) {
                if (!try self.emit_guard_loop_control(i, stmt_end) and
                    !try self.emit_guard_return(i, stmt_end, result_ty, deferred))
                {
                    try self.emit_if(i, stmt_end, result_ty, deferred);
                }
            } else if (tok_eq(self.tokens[i], "loop")) {
                if (codegen_body.field_reflection_loop_header(self.tokens, i, stmt_end, self.ctx, self.locals) != null) {
                    try self.emit_field_reflection_loop(i, stmt_end, result_ty, deferred);
                } else if (codegen_body.collection_loop_header(self.tokens, i, stmt_end, self.ctx, self.locals)) |header| {
                    try self.emit_collection_loop(i, header, result_ty, deferred);
                } else {
                    try self.emit_loop(i, stmt_end, result_ty, deferred);
                }
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
                try self.append_fmt("    br ${[label]s}\n", .{ .label = try self.loop_control_target(i, stmt_end, true) });
            } else if (tok_eq(self.tokens[i], "continue")) {
                try self.emit_deferred(deferred.items[inherited_defer_count..]);
                deferred.shrinkRetainingCapacity(inherited_defer_count);
                try self.append_fmt("    br ${[label]s}\n", .{ .label = try self.loop_control_target(i, stmt_end, false) });
            } else if (tok_eq(self.tokens[i], "#") and i + 1 < stmt_end and self.tokens[i + 1].kind == .ident) {
                // A label declaration belongs to the following loop and has
                // no direct WAT instruction of its own.
            } else if (self.tokens[i].kind == .ident and find_top_level_token(self.tokens, i + 1, stmt_end, "=") != null) {
                const eq_idx = find_top_level_token(self.tokens, i + 1, stmt_end, "=") orelse return error.UnsupportedGcSyncStatement;
                if (find_top_level_token(self.tokens, i, eq_idx, ",") != null) {
                    try self.emit_multi_result_assignment(i, stmt_end);
                } else {
                    try self.emit_assignment(i, stmt_end);
                }
            } else {
                const result = try self.emit_expr(i, stmt_end, null);
                try self.emit_result_drops(i, stmt_end, result);
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

fn is_bounded_multi_result_type(ty: []const u8) bool {
    return type_name.is_core_wasm_scalar(ty) or std.mem.eql(u8, ty, "[u8]");
}

fn is_bounded_multi_result_type_with_layouts(tokens: []const lexer.Token, ty: []const u8, layouts: []const gc_layout.GcStructLayout) bool {
    return is_bounded_multi_result_type(ty) or is_gc_scalar_slot_type(tokens, ty) or find_gc_layout(layouts, ty) != null;
}

fn is_supported_type_with_layouts(
    ty: []const u8,
    structs: []const gc_representation.StructShape,
    layouts: []const gc_layout.GcStructLayout,
    payload_unions: []const gc_layout.GcPayloadUnionLayout,
    managed_arrays: []const gc_layout.GcManagedArrayLayout,
) bool {
    if (is_inline_scalar_struct_type(structs, ty)) return true;
    _ = gc_adapter.classify_admitted_type_with_layouts_and_unions_and_arrays(ty, structs, layouts, payload_unions, managed_arrays) catch return false;
    return true;
}

fn is_inline_scalar_struct_type(structs: []const gc_representation.StructShape, ty: []const u8) bool {
    const shape = for (structs) |candidate| {
        if (std.mem.eql(u8, candidate.name, ty)) break candidate;
    } else return false;

    const rep = gc_representation.classify_type(ty, structs, &.{}) catch return false;
    if (rep != .inline_value) return false;
    for (shape.fields) |field| {
        if (is_inline_scalar_struct_type(structs, field.ty)) continue;
        if (!type_name.is_core_wasm_scalar(field.ty)) return false;
    }
    return shape.fields.len != 0;
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

fn tokens_have_host_func_binding(tokens: []const lexer.Token) bool {
    for (tokens, 0..) |token, index| {
        if (!tok_eq(token, "@") or index + 3 >= tokens.len) continue;
        if (tokens[index + 1].kind == .ident and
            std.mem.eql(u8, tokens[index + 1].lexeme, "host_func")) return true;
    }
    return false;
}

fn emit_gc_host_support(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    route: *const GcSyncHostWitRoute,
) !void {
    if (try is_pure_scalar_record_plan(route.plan)) {
        const canonical = try marshal_module.canonical_import_for_plan(allocator, route.plan.descriptor);
        defer allocator.free(canonical.module);
        try marshal_module.emit_sync_marshal_gc_support(allocator, out, route.plan, .{
            .direction = route.plan.direction,
            .function_name = route.host_import.alias,
            .input_local = "input",
            .realloc_name = "cabi_realloc",
            .canonical_call_name = "__gc_canonical_call",
            .canonical_import_module = canonical.module,
            .canonical_import_name = canonical.name,
        });
        const scalar_bridge = try marshal_wat.emit_sync_scalar_record_bridge_function(allocator, route.plan, .{
            .function_name = route.host_import.alias,
            .input_local = "input",
            .realloc_name = "cabi_realloc",
            .canonical_call_name = "__gc_canonical_call",
            .root_type_name = route.host_import.result orelse route.host_import.params[0],
        });
        defer allocator.free(scalar_bridge);
        try out.appendSlice(allocator, scalar_bridge);
        return;
    }
    const canonical = try marshal_module.canonical_import_for_plan(allocator, route.plan.descriptor);
    defer allocator.free(canonical.module);
    const root_type_name = switch (route.plan.direction) {
        .lower => if (route.host_import.params.len == 1)
            route.host_import.params[0]
        else
            return error.UnsupportedGcSyncCall,
        .lift => route.host_import.result orelse return error.UnsupportedGcSyncCall,
    };

    try marshal_module.emit_sync_marshal_gc_support(allocator, out, route.plan, .{
        .direction = route.plan.direction,
        .function_name = route.host_import.alias,
        .input_local = "input",
        .realloc_name = "cabi_realloc",
        .canonical_call_name = "__gc_canonical_call",
        .canonical_import_module = canonical.module,
        .canonical_import_name = canonical.name,
    });
    const function_wat = try marshal_wat.emit_sync_marshal_function(allocator, route.plan, .{
        .function_name = route.host_import.alias,
        .input_local = "input",
        .realloc_name = "cabi_realloc",
        .canonical_call_name = "__gc_canonical_call",
        .root_type_name = root_type_name,
    });
    defer allocator.free(function_wat);
    try out.appendSlice(allocator, function_wat);
}

fn is_pure_scalar_record_plan(plan: *const marshal_plan.SyncValuePlan) !bool {
    if (plan.root.kind != .record or plan.root.children.len == 0) return false;
    return is_pure_scalar_record_node(&plan.root);
}

fn is_pure_scalar_record_node(node: *const marshal_plan.MarshalNode) bool {
    return switch (node.kind) {
        .scalar => node.measured != null and node.measured.?.core_type != null,
        .record => node.children.len != 0 and blk: {
            for (node.children) |*child| if (!is_pure_scalar_record_node(child)) break :blk false;
            break :blk true;
        },
        else => false,
    };
}

fn append_wasm_type(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    ty: []const u8,
    structs: []const gc_representation.StructShape,
    layouts: []const gc_layout.GcStructLayout,
    payload_unions: []const gc_layout.GcPayloadUnionLayout,
    managed_arrays: []const gc_layout.GcManagedArrayLayout,
) !void {
    try gc_adapter.append_wasm_type_for_with_unions_and_arrays(allocator, out, ty, structs, layouts, payload_unions, managed_arrays);
}

fn append_fmt(allocator: std.mem.Allocator, out: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
    try generated_text.append_fmt(allocator, out, fmt, args);
}

fn find_gc_layout(layouts: []const gc_layout.GcStructLayout, name: []const u8) ?gc_layout.GcStructLayout {
    for (layouts) |layout| if (std.mem.eql(u8, layout.name, name)) return layout;
    return null;
}

fn find_gc_payload_union(layouts: []const gc_layout.GcPayloadUnionLayout, name: []const u8) ?gc_layout.GcPayloadUnionLayout {
    for (layouts) |layout| if (std.mem.eql(u8, layout.source_ty, name)) return layout;
    return null;
}

fn collect_inline_payload_union_layout(layout: codegen_union_layout.UnionLayout) ?gc_layout.GcPayloadUnionLayout {
    var unit_case: ?[]const u8 = null;
    var unit_tag: u32 = 0;
    var managed_case: ?[]const u8 = null;
    var managed_tag: u32 = 0;
    var managed_payload_index: u32 = 0;
    for (layout.branches) |branch| {
        if (branch.payload_len == 0) {
            if (unit_case != null) return null;
            unit_case = branch.ty;
            unit_tag = @intCast(branch.tag);
            continue;
        }
        if (branch.payload_len != 1 or branch.payload_start >= layout.payload_tys.len or
            !std.mem.eql(u8, layout.payload_tys[branch.payload_start], "[u8]")) continue;
        if (managed_case != null) return null;
        managed_case = branch.ty;
        managed_tag = @intCast(branch.tag);
        managed_payload_index = @intCast(branch.payload_start);
    }
    if (unit_case == null or managed_case == null) return null;
    return .{
        .name = "do_union",
        .source_ty = layout.source_ty,
        .unit_case = unit_case.?,
        .managed_case = managed_case.?,
        .unit_tag = unit_tag,
        .managed_tag = managed_tag,
        .payload_tys = layout.payload_tys,
        .managed_payload_index = managed_payload_index,
    };
}

fn is_gc_scalar_slot_type(tokens: []const lexer.Token, ty: []const u8) bool {
    return type_name.is_core_wasm_scalar(ty) or is_error_like_type(tokens, ty);
}

fn gc_scalar_slot_wasm_type(tokens: []const lexer.Token, ty: []const u8) ?[]const u8 {
    if (type_name.is_core_wasm_scalar(ty)) return payload_wat.wasm_type(ty);
    if (is_error_like_type(tokens, ty)) return "i32";
    return null;
}

fn is_gc_scalar_union_layout(tokens: []const lexer.Token, layout: codegen_union_layout.UnionLayout) bool {
    if (layout.branches.len < 2) return false;
    for (layout.payload_tys) |payload_ty| {
        if (!is_gc_scalar_slot_type(tokens, payload_ty)) return false;
    }
    return true;
}

fn union_tag_local_name_from_locals(locals: []const codegen_model.Local, base: []const u8) ?[]const u8 {
    var suffix_buf: [32]u8 = undefined;
    const suffix = std.fmt.bufPrint(&suffix_buf, ".__union_tag", .{}) catch return null;
    for (locals) |local| {
        if (local.name.len != base.len + suffix.len) continue;
        if (!std.mem.startsWith(u8, local.name, base)) continue;
        if (!std.mem.eql(u8, local.name[base.len..], suffix)) continue;
        return local.name;
    }
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
    managed_arrays: []const gc_layout.GcManagedArrayLayout,
) !void {
    try append_fmt(allocator, out, "  (func ${[name]s}", .{ .name = func.name });
    for (func.params) |param| {
        if (param.callback != null) return error.UnsupportedGcSyncCallback;
        const param_ty = func_param_abi_type(param);
        if (is_inline_scalar_struct_type(structs, param_ty)) {
            try append_inline_scalar_param_signature(allocator, out, func.tokens, structs, param.name, param_ty);
            continue;
        }
        if ((!is_supported_type_with_layouts(param_ty, structs, layouts, payload_unions, managed_arrays) and
            !is_gc_scalar_slot_type(func.tokens, param_ty)) or std.mem.eql(u8, param_ty, "nil")) return error.UnsupportedGcSyncType;
        try append_fmt(allocator, out, " (param ${[name]s} ", .{ .name = param.name });
        if (gc_scalar_slot_wasm_type(func.tokens, param_ty)) |wasm_ty| {
            try out.appendSlice(allocator, wasm_ty);
        } else {
            try append_wasm_type(allocator, out, param_ty, structs, layouts, payload_unions, managed_arrays);
        }
        try out.append(allocator, ')');
    }
    const result_payload_union = if (func.result_union) |union_layout|
        find_gc_payload_union(payload_unions, union_layout.source_ty)
    else
        null;
    if (result_payload_union) |payload_union| {
        try out.appendSlice(allocator, " (result ");
        try append_wasm_type(allocator, out, payload_union.source_ty, structs, layouts, payload_unions, managed_arrays);
        try out.append(allocator, ')');
    } else if (func.results.len > 1) {
        for (func.results) |result| {
            if (!is_bounded_multi_result_type_with_layouts(func.tokens, result, layouts)) return error.UnsupportedGcSyncResult;
        }
        try out.appendSlice(allocator, " (result");
        for (func.results) |result| {
            try out.appendSlice(allocator, " ");
            if (gc_scalar_slot_wasm_type(func.tokens, result)) |wasm_ty| {
                try out.appendSlice(allocator, wasm_ty);
            } else {
                try append_wasm_type(allocator, out, result, structs, layouts, payload_unions, managed_arrays);
            }
        }
        try out.append(allocator, ')');
    } else if (func.results.len == 1) {
        if ((!is_supported_type_with_layouts(func.results[0], structs, layouts, payload_unions, managed_arrays) and
            !is_gc_scalar_slot_type(func.tokens, func.results[0])) or std.mem.eql(u8, func.results[0], "nil")) return error.UnsupportedGcSyncType;
        try out.appendSlice(allocator, " (result ");
        if (gc_scalar_slot_wasm_type(func.tokens, func.results[0])) |wasm_ty| {
            try out.appendSlice(allocator, wasm_ty);
        } else {
            try append_wasm_type(allocator, out, func.results[0], structs, layouts, payload_unions, managed_arrays);
        }
        try out.append(allocator, ')');
    }
    try out.appendSlice(allocator, "\n");
}

fn append_inline_scalar_param_signature(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tokens: []const lexer.Token,
    structs: []const gc_representation.StructShape,
    base_name: []const u8,
    ty: []const u8,
) !void {
    const shape = for (structs) |candidate| {
        if (std.mem.eql(u8, candidate.name, ty)) break candidate;
    } else return error.UnsupportedGcSyncType;
    for (shape.fields) |field| {
        const field_name = try std.fmt.allocPrint(allocator, "{[base]s}.{[field]s}", .{
            .base = base_name,
            .field = public_decl_name(field.name),
        });
        defer allocator.free(field_name);
        if (is_inline_scalar_struct_type(structs, field.ty)) {
            try append_inline_scalar_param_signature(allocator, out, tokens, structs, field_name, field.ty);
            continue;
        }
        const wasm_ty = gc_scalar_slot_wasm_type(tokens, field.ty) orelse return error.UnsupportedGcSyncType;
        try append_fmt(allocator, out, " (param ${[name]s} {[wasm_ty]s})", .{ .name = field_name, .wasm_ty = wasm_ty });
    }
}

fn append_inline_scalar_param_locals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    structs: []const gc_representation.StructShape,
    locals: *LocalSet,
    base_name: []const u8,
    ty: []const u8,
) !void {
    const shape = for (structs) |candidate| {
        if (std.mem.eql(u8, candidate.name, ty)) break candidate;
    } else return error.UnsupportedGcSyncType;
    _ = try locals.append_struct_local_with_origin(allocator, base_name, ty, false, .param_or_import);
    for (shape.fields) |field| {
        const field_name = try std.fmt.allocPrint(allocator, "{[base]s}.{[field]s}", .{
            .base = base_name,
            .field = public_decl_name(field.name),
        });
        try locals.owned_names.append(allocator, field_name);
        if (is_inline_scalar_struct_type(structs, field.ty)) {
            try append_inline_scalar_param_locals(allocator, tokens, structs, locals, field_name, field.ty);
        } else if (gc_scalar_slot_wasm_type(tokens, field.ty) != null) {
            try locals.append_borrowed_local_with_origin(allocator, field_name, field.ty, false, .param_or_import);
        } else {
            return error.UnsupportedGcSyncType;
        }
    }
}

fn append_func_params(
    allocator: std.mem.Allocator,
    func: FuncDecl,
    structs: []const gc_representation.StructShape,
    locals: *LocalSet,
) !void {
    for (func.params) |param| {
        if (param.callback != null) return error.UnsupportedGcSyncCallback;
        const param_ty = func_param_abi_type(param);
        if (is_inline_scalar_struct_type(structs, param_ty)) {
            try append_inline_scalar_param_locals(allocator, func.tokens, structs, locals, param.name, param_ty);
        } else {
            try locals.append_borrowed_local_with_origin(allocator, param.name, param_ty, false, .param_or_import);
        }
    }
}

fn is_gc_union_component_local(locals: *const LocalSet, name: []const u8) bool {
    for (locals.union_locals.items) |union_local| {
        if (!std.mem.startsWith(u8, name, union_local.name)) continue;
        const suffix = name[union_local.name.len..];
        if (std.mem.startsWith(u8, suffix, ".__union_payload_") or std.mem.eql(u8, suffix, ".__union_tag")) return true;
    }
    return false;
}

fn is_gc_scalar_union_component_local(tokens: []const lexer.Token, locals: *const LocalSet, name: []const u8) bool {
    for (locals.union_locals.items) |union_local| {
        if (!is_gc_scalar_union_layout(tokens, union_local.layout)) continue;
        if (!std.mem.startsWith(u8, name, union_local.name)) continue;
        const suffix = name[union_local.name.len..];
        if (std.mem.startsWith(u8, suffix, ".__union_payload_") or std.mem.eql(u8, suffix, ".__union_tag")) return true;
    }
    return false;
}

fn append_gc_root_locals(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    locals: *const LocalSet,
    structs: []const gc_representation.StructShape,
    layouts: []const gc_layout.GcStructLayout,
    payload_unions: []const gc_layout.GcPayloadUnionLayout,
    managed_arrays: []const gc_layout.GcManagedArrayLayout,
    out: *std.ArrayList(gc_roots.RootLocal),
) !void {
    for (locals.locals.items) |local| {
        if (is_unneeded_compiler_local(local.name)) continue;
        if (is_gc_union_component_local(locals, local.name)) continue;
        if ((!is_supported_type_with_layouts(local.ty, structs, layouts, payload_unions, managed_arrays) and
            !is_gc_scalar_slot_type(tokens, local.ty)) or std.mem.eql(u8, local.ty, "nil")) return error.UnsupportedGcSyncType;
        const rep = (try gc_adapter.classify_admitted_type_with_layouts_and_unions_and_arrays(local.ty, structs, layouts, payload_unions, managed_arrays)).rep;
        try out.append(allocator, .{ .name = local.name, .rep = rep, .bind_at_entry = local.origin == .param_or_import });
    }
    for (locals.union_locals.items) |union_local| {
        if (is_gc_scalar_union_layout(tokens, union_local.layout)) continue;
        const rep = (try gc_adapter.classify_admitted_type_with_layouts_and_unions_and_arrays(union_local.layout.source_ty, structs, layouts, payload_unions, managed_arrays)).rep;
        try out.append(allocator, .{ .name = union_local.name, .rep = rep, .bind_at_entry = union_local.origin == .param_or_import });
    }
}

fn append_gc_locals(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tokens: []const lexer.Token,
    locals: *const LocalSet,
    structs: []const gc_representation.StructShape,
    layouts: []const gc_layout.GcStructLayout,
    payload_unions: []const gc_layout.GcPayloadUnionLayout,
    managed_arrays: []const gc_layout.GcManagedArrayLayout,
    gc_list_temps: GcListTemps,
) !void {
    for (locals.locals.items) |local| {
        const scalar_union_component = is_gc_scalar_union_component_local(tokens, locals, local.name);
        if (is_unneeded_compiler_local(local.name) and !scalar_union_component) continue;
        if (!local.emit_decl) continue;
        if (is_gc_union_component_local(locals, local.name)) {
            var keep_scalar_component = false;
            for (locals.union_locals.items) |union_local| {
                if (!is_gc_scalar_union_layout(tokens, union_local.layout)) continue;
                if (std.mem.startsWith(u8, local.name, union_local.name)) {
                    keep_scalar_component = true;
                    break;
                }
            }
            if (!keep_scalar_component) continue;
        }
        if ((!is_supported_type_with_layouts(local.ty, structs, layouts, payload_unions, managed_arrays) and
            !is_gc_scalar_slot_type(tokens, local.ty)) or std.mem.eql(u8, local.ty, "nil")) return error.UnsupportedGcSyncType;
        try append_fmt(allocator, out, INDENT ++ "(local ${[name]s} ", .{ .name = local.name });
        if (gc_scalar_slot_wasm_type(tokens, local.ty)) |wasm_ty| {
            try out.appendSlice(allocator, wasm_ty);
        } else {
            try append_wasm_type(allocator, out, local.ty, structs, layouts, payload_unions, managed_arrays);
        }
        try out.appendSlice(allocator, ")\n");
    }
    for (locals.union_locals.items) |union_local| {
        if (is_gc_scalar_union_layout(tokens, union_local.layout)) continue;
        if (!is_supported_type_with_layouts(union_local.layout.source_ty, structs, layouts, payload_unions, managed_arrays)) return error.UnsupportedGcSyncType;
        try append_fmt(allocator, out, INDENT ++ "(local ${[name]s} ", .{ .name = union_local.name });
        try append_wasm_type(allocator, out, union_local.layout.source_ty, structs, layouts, payload_unions, managed_arrays);
        try out.appendSlice(allocator, ")\n");
    }
    for (layouts) |layout| {
        if (is_inline_gc_layout(layout)) continue;
        try out.appendSlice(allocator, INDENT ++ "(local $__gc_nested_");
        for (layout.name) |ch| try out.append(allocator, std.ascii.toLower(ch));
        try out.appendSlice(allocator, " (ref null $");
        for (layout.name) |ch| try out.append(allocator, std.ascii.toLower(ch));
        try out.appendSlice(allocator, "))\n");
    }
    try append_fmt(allocator, out, "    (local ${[bytes_next_name]s} (ref null $do_bytes))\n", .{ .bytes_next_name = gc_list_temps.bytes_next_name });
    for (gc_layout.scalar_array_specs, 0..) |spec, index| {
        if (gc_list_temps.has_scalar_arrays[index]) {
            try append_fmt(allocator, out, "    (local ${[index]s} (ref null {[array_name]s}))\n", .{ .index = gc_list_temps.scalar_next_names[index], .array_name = spec.array_name });
        }
    }
    for (managed_arrays, 0..) |managed_array, index| {
        try append_fmt(allocator, out, "    (local ${[index]s} (ref null {[array_name]s}))\n", .{ .index = gc_list_temps.managed_next_names[index], .array_name = managed_array.array_name });
    }
    try append_fmt(allocator, out, "    (local ${[length_name]s} i32)\n", .{ .length_name = gc_list_temps.length_name });
}

fn is_inline_gc_layout(layout: gc_layout.GcStructLayout) bool {
    if (layout.fields.len == 0) return false;
    for (layout.fields) |field| {
        if (field.rep != .inline_value) return false;
    }
    return true;
}

fn is_unneeded_compiler_local(name: []const u8) bool {
    // The shared body collector still reserves legacy storage/packing temps.
    // GC emission does not use them, but collection-loop locals are emitted by
    // the GC body emitter and must remain declared here.
    return codegen_context.is_compiler_local_name(name) and
        !std.mem.startsWith(u8, name, "__loop_") and
        !std.mem.startsWith(u8, name, "__field_");
}

fn choose_gc_list_temps(
    allocator: std.mem.Allocator,
    locals: []const codegen_model.Local,
    scalar_arrays: [gc_layout.scalar_array_specs.len]bool,
    managed_arrays: []const gc_layout.GcManagedArrayLayout,
) !GcListTemps {
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
        const managed_next_names = try allocator.alloc([]u8, managed_arrays.len);
        var managed_allocated: usize = 0;
        errdefer {
            for (managed_next_names[0..managed_allocated]) |name| allocator.free(name);
            allocator.free(managed_next_names);
        }
        for (managed_arrays, 0..) |_, index| {
            managed_next_names[index] = if (suffix == 0)
                try std.fmt.allocPrint(allocator, "__gc_managed_list_next_{d}", .{index})
            else
                try std.fmt.allocPrint(allocator, "__gc_managed_list_next_{d}_{d}", .{ index, suffix });
            managed_allocated += 1;
        }
        const length_name = if (suffix == 0)
            try allocator.dupe(u8, "__gc_list_length")
        else
            try std.fmt.allocPrint(allocator, "__gc_list_length_{d}", .{suffix});
        errdefer allocator.free(length_name);
        var collision = has_wat_local_name(locals, bytes_next_name) or has_wat_local_name(locals, length_name);
        for (scalar_next_names) |name| collision = collision or has_wat_local_name(locals, name);
        for (managed_next_names) |name| collision = collision or has_wat_local_name(locals, name);
        if (!collision) {
            return .{ .bytes_next_name = bytes_next_name, .scalar_next_names = scalar_next_names, .has_scalar_arrays = scalar_arrays, .managed_next_names = managed_next_names, .length_name = length_name };
        }
        allocator.free(bytes_next_name);
        for (scalar_next_names) |name| allocator.free(name);
        for (managed_next_names) |name| allocator.free(name);
        allocator.free(managed_next_names);
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
    managed_arrays: []const gc_layout.GcManagedArrayLayout,
    scalar_arrays: [gc_layout.scalar_array_specs.len]bool,
    gc_host_route: ?*const GcSyncHostWitRoute,
) !void {
    try append_function_signature(allocator, out, func, gc_structs, gc_layouts, payload_unions, managed_arrays);
    var func_ctx = base_ctx;
    func_ctx.type_bindings = func.type_bindings;
    func_ctx.callback_bindings = func.callback_bindings;
    var locals = LocalSet{};
    defer locals.deinit(allocator);
    try append_func_params(allocator, func, gc_structs, &locals);
    try codegen_body.collect_body_locals(allocator, func.tokens, func.body_start, func.body_end, func_ctx, &locals);
    const gc_list_temps = try choose_gc_list_temps(allocator, locals.locals.items, scalar_arrays, managed_arrays);
    defer gc_list_temps.deinit(allocator);

    var root_locals = std.ArrayList(gc_roots.RootLocal).empty;
    defer root_locals.deinit(allocator);
    try append_gc_root_locals(allocator, func.tokens, &locals, gc_structs, gc_layouts, payload_unions, managed_arrays, &root_locals);
    const root_plan = try gc_roots.build_root_plan(allocator, root_locals.items, .synchronous);
    defer gc_roots.deinit_root_plan(allocator, root_plan);

    try append_gc_locals(allocator, out, func.tokens, &locals, gc_structs, gc_layouts, payload_unions, managed_arrays, gc_list_temps);
    for (root_plan.slots) |slot| {
        if (slot.bind_at_entry) try append_fmt(allocator, out, "    ;; gc-root {[point]s} ${[name]s}\n", .{ .point = append_root_point_name(slot.point), .name = slot.name });
    }

    var loop_stack = std.ArrayList(GcLoopFrame).empty;
    defer loop_stack.deinit(allocator);
    var emitter = BodyEmitter{ .allocator = allocator, .tokens = func.tokens, .functions = functions, .gc_structs = gc_structs, .gc_layouts = gc_layouts, .gc_payload_unions = payload_unions, .gc_managed_arrays = managed_arrays, .locals = &locals, .result_tys = func.results, .result_items = func.result_items, .result_struct = func.result_struct, .ctx = func_ctx, .out = out, .gc_list_temps = gc_list_temps, .loop_stack = &loop_stack, .gc_host_route = gc_host_route };
    var deferred = std.ArrayList(DeferredCall).empty;
    defer deferred.deinit(allocator);
    if (func.arrow) {
        if (emitter.scalar_union_result_layout()) |union_layout| {
            try emitter.emit_scalar_union_result_values(func.body_start, func.body_end, union_layout);
            try out.appendSlice(allocator, "    return\n");
        } else if (emitter.has_inline_scalar_struct_result()) {
            try emitter.emit_inline_struct_result_values(func.body_start, func.body_end, func.result_struct.?);
            try out.appendSlice(allocator, "    return\n");
        } else if (func.results.len > 1) {
            try emitter.emit_multi_result_return(func.body_start, func.body_end);
        } else {
            if (func.results.len != 1) return error.UnsupportedGcSyncResult;
            _ = try emitter.emit_expr(func.body_start, func.body_end, func.results[0]);
            try out.appendSlice(allocator, "    return\n");
        }
    } else {
        const result_ty = if (func.result_union) |union_layout| union_layout.source_ty else if (func.results.len == 1) func.results[0] else null;
        const saw_return = try emitter.emit_body(func.body_start, func.body_end, result_ty, &deferred);
        if (result_ty != null and !saw_return) try out.appendSlice(allocator, "    unreachable\n");
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
    managed_arrays: []const gc_layout.GcManagedArrayLayout,
    scalar_arrays: [gc_layout.scalar_array_specs.len]bool,
    gc_host_route: ?*const GcSyncHostWitRoute,
) !void {
    try wat_function_body.emit_compiled_test_open(allocator, out, index, test_decl.name_lexeme);

    var locals = LocalSet{};
    defer locals.deinit(allocator);
    try codegen_body.collect_body_locals(allocator, tokens, test_decl.body_start, test_decl.body_end, base_ctx, &locals);
    const gc_list_temps = try choose_gc_list_temps(allocator, locals.locals.items, scalar_arrays, managed_arrays);
    defer gc_list_temps.deinit(allocator);

    var root_locals = std.ArrayList(gc_roots.RootLocal).empty;
    defer root_locals.deinit(allocator);
    try append_gc_root_locals(allocator, tokens, &locals, gc_structs, gc_layouts, payload_unions, managed_arrays, &root_locals);
    const root_plan = try gc_roots.build_root_plan(allocator, root_locals.items, .synchronous);
    defer gc_roots.deinit_root_plan(allocator, root_plan);

    try append_gc_locals(allocator, out, tokens, &locals, gc_structs, gc_layouts, payload_unions, managed_arrays, gc_list_temps);
    for (root_plan.slots) |slot| {
        if (slot.bind_at_entry) try append_fmt(allocator, out, "    ;; gc-root {[point]s} ${[name]s}\n", .{ .point = append_root_point_name(slot.point), .name = slot.name });
    }

    var loop_stack = std.ArrayList(GcLoopFrame).empty;
    defer loop_stack.deinit(allocator);
    var emitter = BodyEmitter{
        .allocator = allocator,
        .tokens = tokens,
        .functions = functions,
        .gc_structs = gc_structs,
        .gc_layouts = gc_layouts,
        .gc_payload_unions = payload_unions,
        .gc_managed_arrays = managed_arrays,
        .locals = &locals,
        .result_tys = &.{},
        .result_items = &.{},
        .result_struct = null,
        .ctx = base_ctx,
        .out = out,
        .gc_list_temps = gc_list_temps,
        .loop_stack = &loop_stack,
        .gc_host_route = gc_host_route,
    };
    var deferred = std.ArrayList(DeferredCall).empty;
    defer deferred.deinit(allocator);
    _ = try emitter.emit_body(test_decl.body_start, test_decl.body_end, null, &deferred);
    try out.appendSlice(allocator, "    unreachable\n");
    try wat_function_body.emit_func_close(allocator, out);
    try wat_function_body.emit_compiled_test_export(allocator, out, index);
}

fn emit_start(allocator: std.mem.Allocator, out: *std.ArrayList(u8), tokens: []const lexer.Token, functions: []const FuncDecl, base_ctx: CodegenContext, gc_structs: []const gc_representation.StructShape, gc_layouts: []const gc_layout.GcStructLayout, payload_unions: []const gc_layout.GcPayloadUnionLayout, managed_arrays: []const gc_layout.GcManagedArrayLayout, scalar_arrays: [gc_layout.scalar_array_specs.len]bool, gc_host_route: ?*const GcSyncHostWitRoute) !void {
    const start_idx = find_start_func(tokens) orelse return;
    const close_params = try find_matching(tokens, start_idx + 1, "(", ")");
    const open_body = find_top_level_block_open(tokens, close_params + 1, tokens.len) orelse return error.UnsupportedGcSyncControl;
    const close_body = try find_matching(tokens, open_body, "{", "}");

    var locals = LocalSet{};
    defer locals.deinit(allocator);
    try codegen_body.collect_body_locals(allocator, tokens, open_body + 1, close_body, base_ctx, &locals);
    const gc_list_temps = try choose_gc_list_temps(allocator, locals.locals.items, scalar_arrays, managed_arrays);
    defer gc_list_temps.deinit(allocator);
    var root_locals = std.ArrayList(gc_roots.RootLocal).empty;
    defer root_locals.deinit(allocator);
    try append_gc_root_locals(allocator, tokens, &locals, gc_structs, gc_layouts, payload_unions, managed_arrays, &root_locals);
    const root_plan = try gc_roots.build_root_plan(allocator, root_locals.items, .synchronous);
    defer gc_roots.deinit_root_plan(allocator, root_plan);

    try out.appendSlice(allocator, "  (func $_start\n");
    try append_gc_locals(allocator, out, tokens, &locals, gc_structs, gc_layouts, payload_unions, managed_arrays, gc_list_temps);
    for (root_plan.slots) |slot| if (slot.bind_at_entry) try append_fmt(allocator, out, "    ;; gc-root {[point]s} ${[name]s}\n", .{ .point = append_root_point_name(slot.point), .name = slot.name });
    var loop_stack = std.ArrayList(GcLoopFrame).empty;
    defer loop_stack.deinit(allocator);
    var emitter = BodyEmitter{ .allocator = allocator, .tokens = tokens, .functions = functions, .gc_structs = gc_structs, .gc_layouts = gc_layouts, .gc_payload_unions = payload_unions, .gc_managed_arrays = managed_arrays, .locals = &locals, .result_tys = &.{}, .result_items = &.{}, .result_struct = null, .ctx = base_ctx, .out = out, .gc_list_temps = gc_list_temps, .loop_stack = &loop_stack, .gc_host_route = gc_host_route };
    var deferred = std.ArrayList(DeferredCall).empty;
    defer deferred.deinit(allocator);
    _ = try emitter.emit_body(open_body + 1, close_body, null, &deferred);
    try generated_text.append_block(allocator, out, 2,
        \\  )
        \\  (export "_start" (func $_start))
        \\
        );
}

fn emit_gc_wat_for_supported_program_with_tests(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
    test_decls: []const TestDecl,
    gc_host_route: ?*const GcSyncHostWitRoute,
) ![]u8 {
    if (tokens.len == 0) return error.UnsupportedGcSyncProgram;
    if (module_graph) |graph| {
        // Component/WIT and host bindings need their canonical ABI marshalling
        // path. Keep the parsed GC route fail-closed until that boundary is
        // wired; plain synchronous @lib imports remain admitted below.
        if (graph_has_host_or_wit_binding(graph) and gc_host_route == null) return error.UnsupportedGcSyncModuleGraph;
    }
    if (gc_host_route != null and !tokens_have_host_func_binding(tokens)) return error.UnsupportedGcSyncModuleGraph;

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
    var managed_arrays = std.ArrayList(gc_layout.GcManagedArrayLayout).empty;
    defer managed_arrays.deinit(allocator);
    defer gc_layout.deinit_managed_array_layouts(allocator, managed_arrays.items);
    try collect_gc_managed_array_layouts(allocator, tokens, functions.items, gc_structs, gc_layouts.items, &managed_arrays);
    for (functions.items) |func| {
        if (!func.is_generic_template and func.type_bindings.len != 0) {
            try validate_gc_sync_generic_bindings(func, gc_structs, gc_layouts.items, resource_names.items, payload_enums.items, managed_arrays.items);
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
    for (functions.items) |func| {
        if (func.result_union) |union_layout| {
            if (collect_inline_payload_union_layout(union_layout)) |payload_union| {
                var already_present = false;
                for (payload_unions.items) |existing| {
                    if (std.mem.eql(u8, existing.source_ty, payload_union.source_ty)) {
                        already_present = true;
                        break;
                    }
                    if (std.mem.eql(u8, existing.name, payload_union.name)) return error.UnsupportedGcSyncUnionArms;
                }
                if (!already_present) try payload_unions.append(allocator, payload_union);
            }
        }
    }
    for (functions.items, 0..) |func, idx| {
        if (func.is_generic_template) continue;
        for (functions.items[0..idx]) |previous| {
            if (std.mem.eql(u8, previous.name, func.name)) return error.UnsupportedGcSyncOverload;
        }
        if (func.is_async or func.contains_await) return error.UnsupportedGcSyncAsync;
        for (func.params) |param| {
            if (is_tuple_storage_type(param.ty)) return error.UnsupportedGcSyncTupleStorage;
            if (std.mem.eql(u8, param.ty, "nil") or
                (!is_supported_type_with_layouts(param.ty, gc_structs, gc_layouts.items, payload_unions.items, managed_arrays.items) and
                    !is_gc_scalar_slot_type(func.tokens, param.ty))) return error.UnsupportedGcSyncType;
        }
        for (func.results) |result| {
            if (is_tuple_storage_type(result)) return error.UnsupportedGcSyncTupleStorage;
            if (std.mem.eql(u8, result, "nil") or
                (!is_supported_type_with_layouts(result, gc_structs, gc_layouts.items, payload_unions.items, managed_arrays.items) and
                    !is_gc_scalar_slot_type(func.tokens, result))) return error.UnsupportedGcSyncType;
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
        .host_imports = if (gc_host_route) |route| @as([]const codegen_model.HostImport, &.{route.host_import}) else &.{},
        .wasi_imports = &.{},
        .string_data = &string_data,
        .entry_tokens = tokens,
        .modules = if (module_graph) |graph| @as([]const imports.ModuleRecord, graph.modules) else &.{},
        .imported_alias_ctx = imported_alias_ctx,
        .gc_sync = true,
    };

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, "(module\n");
    try append_fmt(allocator, &out, "  ;; gc-sync source_len={[source_len]d} token_count={[token_count]d}\n", .{ .source_len = program.source_len, .token_count = program.token_count });
    const has_tuple_text_bytes = has_gc_sync_tuple_text_bytes(functions.items) or test_decls.len != 0;
    var scalar_arrays = has_gc_sync_scalar_arrays(tokens, functions.items, gc_layouts.items);
    if (test_decls.len != 0) scalar_arrays = [_]bool{true} ** gc_layout.scalar_array_specs.len;
    try runtime_gc_prelude.emit_gc_sync_prelude(allocator, &out, gc_layouts.items, payload_unions.items, has_tuple_text_bytes, scalar_arrays, managed_arrays.items);
    if (gc_host_route) |route| try emit_gc_host_support(allocator, &out, route);
    for (functions.items) |func| {
        if (!func.is_generic_template) {
            try emit_func(allocator, &out, func, functions.items, base_ctx, gc_structs, gc_layouts.items, payload_unions.items, managed_arrays.items, scalar_arrays, gc_host_route);
        }
    }
    if (test_decls.len != 0) {
        for (test_decls, 0..) |test_decl, index| {
            try emit_test_func(allocator, &out, test_decl, index, tokens, functions.items, base_ctx, gc_structs, gc_layouts.items, payload_unions.items, managed_arrays.items, scalar_arrays, gc_host_route);
        }
        try wat_function_body.emit_test_start_func(allocator, &out, test_decls.len);
    } else {
        try emit_start(allocator, &out, tokens, functions.items, base_ctx, gc_structs, gc_layouts.items, payload_unions.items, managed_arrays.items, scalar_arrays, gc_host_route);
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
    return emit_gc_wat_for_supported_program_with_tests(allocator, program, tokens, module_graph, &.{}, null);
}

pub fn emit_gc_wat_for_supported_program_with_host_route(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
    gc_host_route: *const GcSyncHostWitRoute,
) ![]u8 {
    return emit_gc_wat_for_supported_program_with_tests(allocator, program, tokens, module_graph, &.{}, gc_host_route);
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
    return emit_gc_wat_for_supported_program_with_tests(allocator, program, tokens, module_graph, test_decls, null);
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
    managed_arrays: []const gc_layout.GcManagedArrayLayout,
) !void {
    for (func.type_bindings) |binding| {
        for (resource_names) |resource_name| {
            if (std.mem.eql(u8, resource_name, binding.ty)) return error.UnsupportedGcSyncGenericResource;
        }
        var is_payload_union = false;
        for (payload_enums) |payload_enum| {
            if (!std.mem.eql(u8, payload_enum.name, binding.ty)) continue;
            _ = gc_layout.collect_payload_union_layout(payload_enum.name, payload_enum.cases) catch return error.UnsupportedGcSyncGenericUnion;
            is_payload_union = true;
            break;
        }
        if (is_payload_union) continue;
        if (!is_supported_type_with_layouts(binding.ty, gc_structs, gc_layouts, &.{}, managed_arrays)) return error.UnsupportedGcSyncGenericUnresolved;
    }
}

fn has_gc_sync_tuple_text_bytes(functions: []const FuncDecl) bool {
    for (functions) |func| {
        for (func.params) |param| if (gc_adapter.is_gc_sync_tuple_text_bytes(param.ty)) return true;
        for (func.results) |result| if (gc_adapter.is_gc_sync_tuple_text_bytes(result)) return true;
    }
    return false;
}

fn has_gc_sync_scalar_arrays(
    tokens: []const lexer.Token,
    functions: []const FuncDecl,
    layouts: []const gc_layout.GcStructLayout,
) [gc_layout.scalar_array_specs.len]bool {
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
        var token_index: usize = 0;
        while (token_index + 2 < tokens.len) : (token_index += 1) {
            if (tok_eq(tokens[token_index], "[") and
                tokens[token_index + 1].kind == .ident and
                std.mem.eql(u8, tokens[token_index + 1].lexeme, spec.elem_ty) and
                tok_eq(tokens[token_index + 2], "]"))
            {
                result[index] = true;
                break;
            }
        }
    }
    return result;
}

fn collect_gc_managed_array_layouts(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    functions: []const FuncDecl,
    structs: []const gc_representation.StructShape,
    layouts: []const gc_layout.GcStructLayout,
    out: *std.ArrayList(gc_layout.GcManagedArrayLayout),
) !void {
    for (layouts) |struct_layout| {
        for (struct_layout.fields) |field| {
            try collect_gc_managed_array_layout(allocator, field.ty, structs, out);
        }
    }
    for (functions) |func| {
        for (func.params) |param| try collect_gc_managed_array_layout(allocator, param.ty, structs, out);
        for (func.results) |result| try collect_gc_managed_array_layout(allocator, result, structs, out);
    }

    // Local declarations are collected from the token stream because they are
    // not part of FuncDecl signatures. Reconstruct complete bracketed type
    // ranges so nested managed lists receive both outer and inner layouts.
    var index: usize = 0;
    while (index + 2 < tokens.len) : (index += 1) {
        if (!tok_eq(tokens[index], "[")) continue;
        const close_idx = codegen_tokens.find_matching_in_range(tokens, index, "[", "]", tokens.len) catch continue;
        if (close_idx <= index + 1) continue;
        var list_ty = std.ArrayList(u8).empty;
        defer list_ty.deinit(allocator);
        for (tokens[index .. close_idx + 1]) |token| try list_ty.appendSlice(allocator, token.lexeme);
        try collect_gc_managed_array_layout(allocator, list_ty.items, structs, out);
        index = close_idx;
    }
}

fn collect_gc_managed_array_layout(
    allocator: std.mem.Allocator,
    list_ty: []const u8,
    structs: []const gc_representation.StructShape,
    out: *std.ArrayList(gc_layout.GcManagedArrayLayout),
) !void {
    if (!gc_adapter.is_managed_list_type(list_ty, structs)) return;
    const elem_ty = type_name.storage_elem_type_from_name(list_ty) orelse return error.UnsupportedGcSyncType;
    if (type_name.is_storage_type_name(elem_ty)) try collect_gc_managed_array_layout(allocator, elem_ty, structs, out);
    for (out.items) |existing| {
        if (std.mem.eql(u8, existing.list_ty, list_ty)) return;
    }

    const owned_list_ty = try allocator.dupe(u8, list_ty);
    errdefer allocator.free(owned_list_ty);
    const owned_elem_ty = try allocator.dupe(u8, elem_ty);
    errdefer allocator.free(owned_elem_ty);
    const array_name = try gc_layout.alloc_managed_array_type_name(allocator, elem_ty);
    errdefer allocator.free(array_name);
    for (out.items) |existing| {
        if (std.mem.eql(u8, existing.array_name, array_name)) return error.UnsupportedGcSyncType;
    }
    try out.append(allocator, .{ .list_ty = owned_list_ty, .elem_ty = owned_elem_ty, .array_name = array_name });
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

fn emit_compiled_test_source(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);
    var program = try parser.parse_program(allocator, tokens, source.len);
    defer program.deinit(allocator);
    return emit_gc_wat_for_supported_tests(allocator, program, tokens, null);
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
    codegen_callbacks.install_collect_body_locals(codegen_body.collect_body_locals);
    codegen_callbacks.install_collect_body_locals_with_mode(codegen_body.collect_body_locals_with_mode);
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
    codegen_callbacks.install_collect_body_locals(codegen_body.collect_body_locals);
    codegen_callbacks.install_collect_body_locals_with_mode(codegen_body.collect_body_locals_with_mode);
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

test "GC sync lowers a managed struct multi-result carrier" {
    const source =
        \\Box {
        \\    value [u8]
        \\}
        \\make_boxes() -> Box, Box {
        \\    left_text [u8] = "left"
        \\    right_text [u8] = "right"
        \\    left Box = Box{value = left_text}
        \\    right Box = Box{value = right_text}
        \\    return left, right
        \\}
        \\start() {
        \\    first_text [u8] = "first"
        \\    second_text [u8] = "second"
        \\    first Box = Box{value = first_text}
        \\    second Box = Box{value = second_text}
        \\    first, second = make_boxes()
        \\    return
        \\}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $make_boxes (result (ref null $box) (ref null $box))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $make_boxes\n    local.set $second\n    local.set $first") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync lowers a managed list put through a typed GC array" {
    const source =
        \\Box {
        \\    value [u8]
        \\    tag i32
        \\}
        \\append(boxes [Box], next Box) -> [Box] {
        \\    return @put(boxes, next)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_default $do_list_box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.copy $do_list_box $do_list_box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_list_box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync lowers a nested byte-list put through typed GC arrays" {
    const source =
        \\append(rows [[u8]], row [u8]) -> [[u8]] {
        \\    return @put(rows, row)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_list_list_u8 (array (mut (ref null $do_bytes)))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_default $do_list_list_u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.copy $do_list_list_u8 $do_list_list_u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_list_list_u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync rejects nested call-produced managed field replacement" {
    const source =
        \\Box {
        \\    value [u8]
        \\}
        \\seed() -> [u8] {
        \\    return .{1, 2}
        \\}
        \\make(value [u8]) -> [u8] {
        \\    return value
        \\}
        \\replace(box Box) -> Box {
        \\    return @set(box, .value, make(seed()))
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.UnsupportedGcSyncProducer, emit_test_source(std.testing.allocator, source));
}

test "GC sync rejects a multi-result managed field producer" {
    const source =
        \\Box {
        \\    value [u8]
        \\}
        \\make() -> [u8], i32 {
        \\    return .{1, 2}, 7
        \\}
        \\replace(box Box) -> Box {
        \\    return @set(box, .value, make())
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.UnsupportedGcSyncProducer, emit_test_source(std.testing.allocator, source));
}

test "GC sync rejects a mismatched managed field producer" {
    const source =
        \\Box {
        \\    value [u8]
        \\}
        \\make() -> text {
        \\    return "value"
        \\}
        \\replace(box Box) -> Box {
        \\    return @set(box, .value, make())
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.UnsupportedGcSyncProducer, emit_test_source(std.testing.allocator, source));
}

test "GC sync lowers a direct call-produced managed field replacement" {
    const source =
        \\Box {
        \\    value [u8]
        \\    tag i32
        \\}
        \\make() -> [u8] {
        \\    return .{1, 2}
        \\}
        \\replace(box Box) -> Box {
        \\    return @set(box, .value, make())
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $make") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-root call_result") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync lowers a direct call-produced managed text field replacement" {
    const source =
        \\Box {
        \\    value text
        \\    tag i32
        \\}
        \\make_text() -> text {
        \\    return "fresh"
        \\}
        \\replace(box Box) -> Box {
        \\    return @set(box, .value, make_text())
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $make_text") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-root call_result") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync lowers a direct managed field getter producer" {
    const source =
        \\Box {
        \\    value [u8]
        \\}
        \\replace(box Box, other Box) -> Box {
        \\    return @set(box, .value, @get(other, .value))
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $box $value") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
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

test "GC sync lowers an anonymous managed union call compared with nil" {
    const source =
        \\LoadError error = Bad
        \\maybe(data [u8], ok bool) -> [u8] | LoadError | nil {
        \\    if ok return data
        \\    return nil
        \\}
        \\start() {
        \\    data [u8] = "abc"
        \\    if @eq(maybe(data, false), nil) return
        \\    return
        \\}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_union") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(field $bytes (ref null $do_bytes))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "ref.is_null") == null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync lowers a payload-union result through a typed local" {
    const source =
        \\Message = Empty | Bytes([u8])
        \\make(value [u8]) -> Message {
        \\    return Bytes(value)
        \\}
        \\forward(value [u8]) -> Message {
        \\    out Message = make(value)
        \\    return out
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(local $out (ref null $message))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $make\n    ;; gc-root call_result\n    local.set $out") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.get $out\n    return") != null);
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

test "GC sync lowers an inferred text body binding with a local root" {
    const source =
        \\make() -> text {
        \\    value = "hello"
        \\    return value
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(local $value (ref null $do_text))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.set $value\n    ;; gc-root local_bind $value") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "local.get $value\n    return") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync lowers an inferred text compiled-test binding" {
    const source =
        \\test "inferred text" {
        \\    value = "hello"
        \\    return
        \\}
    ;
    const wat = try emit_compiled_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(local $value (ref null $do_text))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "gc-root local_bind $value") != null);
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

test "GC sync lowers a guard return with an expression" {
    const source =
        \\identity(value [u8]) -> [u8] {
        \\    return value
        \\}
        \\choose(value [u8], ok bool) -> [u8] {
        \\    if ok return identity(value)
        \\    return value
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $choose") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "    if\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $identity") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync lowers scalar add and sub intrinsics" {
    const source =
        \\adjust(value i32) -> i32 {
        \\    next i32 = @add(value, 1)
        \\    return @sub(next, 1)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.add") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.sub") != null);
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

test "GC sync lowers a managed struct constructor with a byte-list field" {
    const source =
        \\Box {
        \\    value [u8]
        \\}
        \\make(bytes [u8]) -> Box {
        \\    return Box{value = bytes}
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync lowers recursive managed struct calls with inferred construction" {
    const source =
        \\Box {
        \\    data [u8]
        \\}
        \\step_box(n i32, box Box) -> Box {
        \\    if @eq(n, 0) return box
        \\    next i32 = @sub(n, 1)
        \\    return step_box(next, box)
        \\}
        \\start() {
        \\    box Box = .{data = "a"}
        \\    out Box = step_box(2, box)
        \\    return
        \\}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $step_box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync lowers scalar collection loops through typed GC arrays" {
    const source =
        \\take(xs [i32]) -> i32 {
        \\    return @len(xs)
        \\}
        \\start() {
        \\    xs [i32] = .{1, 2}
        \\    loop value, index = xs {
        \\        n i32 = take(xs)
        \\        if @eq(index, 0) break
        \\    }
        \\    return
        \\}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, ";; gc-loop-collection") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.len") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.get $do_i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync lowers managed-element collection loops through typed GC arrays" {
    const source =
        \\Box {
        \\    value [u8]
        \\}
        \\take(box Box) -> i32 {
        \\    value [u8] = @get(box, .value)
        \\    return @len(value)
        \\}
        \\start() {
        \\    bytes [u8] = "abc"
        \\    one Box = Box{value = bytes}
        \\    boxes [Box] = .{one}
        \\    count i32 = @len(boxes)
        \\    first Box = @get(boxes, 0)
        \\    loop item, index = boxes {
        \\        n i32 = take(item)
        \\        if @eq(index, 0) break
        \\    }
        \\    return
        \\}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_list_box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_fixed $do_list_box 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.get $do_list_box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync lowers a text-element list through a typed GC array" {
    const source =
        \\make_texts() -> [text] {
        \\    first text = "a"
        \\    texts [text] = .{first, "bc"}
        \\    count usize = @len(texts)
        \\    selected text = @get(texts, 0)
        \\    loop item, index = texts {
        \\        if @eq(index, 0) break
        \\    }
        \\    return texts
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_list_text") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_fixed $do_list_text 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.get $do_list_text") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync lowers a nested byte-list through typed GC arrays" {
    const source =
        \\make_nested() -> [[u8]] {
        \\    first [u8] = .{1, 2, 3}
        \\    nested [[u8]] = .{first}
        \\    count i32 = @len(nested)
        \\    row [u8] = @get(nested, 0)
        \\    loop item, index = nested {
        \\        size i32 = @len(item)
        \\        if @eq(index, 0) break
        \\    }
        \\    return nested
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_list_list_u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(type $do_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.get $do_list_list_u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync lowers a pure scalar struct error union" {
    const source =
        \\LoadError error = Bad
        \\Point {
        \\    x usize
        \\    y usize
        \\}
        \\make(data [u8]) -> Point | LoadError {
        \\    n usize = @len(data)
        \\    point Point = Point{x = n, y = n}
        \\    return point
        \\}
        \\pass(data [u8]) -> Point | LoadError {
        \\    return make(data)
        \\}
        \\start() {
        \\    result = pass("abc")
        \\    if @is(result, LoadError) return
        \\    if @is(result, Point) return
        \\    return
        \\}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $make (param $data (ref null $do_bytes)) (result i32 i32 i32 i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $make") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 2\n    i32.eq") != null);
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

test "GC sync lowers an exact nested byte-list update inside a struct field" {
    const source =
        \\Box {
        \\    value [u8]
        \\    tag i32
        \\}
        \\rewrite(box Box, index usize, scalar u8) -> Box {
        \\    return @set(box, .value, @set(@get(box, .value), index, scalar))
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $box $value") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.copy $do_bytes $do_bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.set $do_bytes") != null);
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

test "GC sync lowers a one-level nested managed field getter" {
    const source =
        \\Inner {
        \\    value [u8]
        \\    tag i32
        \\}
        \\Outer {
        \\    inner Inner
        \\    id i32
        \\}
        \\read_tag(outer Outer) -> i32 {
        \\    return @get(outer, .inner, .tag)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $outer $inner") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $inner $tag") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync lowers static field reflection getter through typed struct access" {
    const source =
        \\User {
        \\    name text
        \\}
        \\take_name(user User) -> text {
        \\    loop field = fields(User) {
        \\        if @eq(@field_name(field), "name") {
        \\            return @field_get(user, field)
        \\        }
        \\    }
        \\    return ""
        \\}
        \\start() {
        \\    user User = User{name = "amy"}
        \\    name text = take_name(user)
        \\    return
        \\}
    ;
    codegen_callbacks.install_collect_body_locals(codegen_body.collect_body_locals);
    codegen_callbacks.install_collect_body_locals_with_mode(codegen_body.collect_body_locals_with_mode);
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(param $user (ref null $user))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $user $name") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "field-reflect-gc type=User") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync lowers an inferred live-source field reflection getter" {
    const source =
        \\User {
        \\    name text
        \\    id i32
        \\}
        \\take_name(user User) -> text {
        \\    loop field = fields(User) {
        \\        if @eq(@field_name(field), "name") {
        \\            got = @field_get(user, field)
        \\            id i32 = @get(user, .id)
        \\            if @eq(id, 0) return ""
        \\            return got
        \\        }
        \\    }
        \\    return ""
        \\}
        \\start() {}
    ;
    codegen_callbacks.install_collect_body_locals(codegen_body.collect_body_locals);
    codegen_callbacks.install_collect_body_locals_with_mode(codegen_body.collect_body_locals_with_mode);
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(local $__field_23_0_got (ref null $do_text))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "gc-root overwrite $__field_23_0_got") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $user $name") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "field-reflect-gc type=User") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync rebuilds a one-level nested managed scalar field" {
    const source =
        \\Inner {
        \\    value [u8]
        \\    tag i32
        \\}
        \\Outer {
        \\    inner Inner
        \\    id i32
        \\}
        \\update(outer Outer) -> Outer {
        \\    return @set(outer, .inner, .tag, 9)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $inner") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $outer") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync keeps direct scalar field setters on the single-level path" {
    const source =
        \\Box {
        \\    tag i32
        \\    value [u8]
        \\}
        \\update(box Box) -> Box {
        \\    return @set(box, .tag, 9)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $box $value") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $box") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync rejects paths deeper than five nested managed fields" {
    const source =
        \\Stem {
        \\    value [u8]
        \\    tag i32
        \\}
        \\Core {
        \\    stem Stem
        \\    tag i32
        \\}
        \\Bud {
        \\    core Core
        \\    tag i32
        \\}
        \\Twig {
        \\    bud Bud
        \\    tag i32
        \\}
        \\Leaf {
        \\    twig Twig
        \\    tag i32
        \\}
        \\Inner {
        \\    leaf Leaf
        \\    tag i32
        \\}
        \\Outer {
        \\    inner Inner
        \\    tag i32
        \\}
        \\read_value(outer Outer) -> i32 {
        \\    return @get(outer, .inner, .leaf, .twig, .bud, .core, .stem, .tag)
        \\}
        \\start() {}
    ;
    try std.testing.expectError(error.UnsupportedGcSyncExpression, emit_test_source(std.testing.allocator, source));
}

test "GC sync generic nested path records the bounded link capacity" {
    var path = std.mem.zeroes(GenericNestedFieldPath);
    path.managed_depth = max_nested_managed_segments;
    try std.testing.expectEqual(@as(usize, 5), path.managed_depth);
    try std.testing.expectEqual(@as(usize, 6), path.layouts.len);
    try std.testing.expectEqual(@as(usize, 5), path.managed_fields.len);
}

test "GC sync lowers a five-level nested managed scalar field" {
    const source =
        \\Core {
        \\    value [u8]
        \\    tag i32
        \\}
        \\Leaf {
        \\    core Core
        \\    tag i32
        \\}
        \\Middle {
        \\    leaf Leaf
        \\    tag i32
        \\}
        \\Inner {
        \\    middle Middle
        \\    tag i32
        \\}
        \\Outer {
        \\    inner Inner
        \\    tag i32
        \\}
        \\Top {
        \\    outer Outer
        \\    tag i32
        \\}
        \\update(top Top) -> Top {
        \\    return @set(top, .outer, .inner, .middle, .leaf, .core, .tag, 13)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $top $outer") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $outer $inner") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $inner $middle") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $middle $leaf") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $leaf $core") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $core") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $leaf") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $middle") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $inner") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $outer") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $top") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync gets a five-level nested managed scalar field" {
    const source =
        \\Core {
        \\    value [u8]
        \\    tag i32
        \\}
        \\Leaf {
        \\    core Core
        \\    tag i32
        \\}
        \\Middle {
        \\    leaf Leaf
        \\    tag i32
        \\}
        \\Inner {
        \\    middle Middle
        \\    tag i32
        \\}
        \\Outer {
        \\    inner Inner
        \\    tag i32
        \\}
        \\Top {
        \\    outer Outer
        \\    tag i32
        \\}
        \\read_value(top Top) -> i32 {
        \\    return @get(top, .outer, .inner, .middle, .leaf, .core, .tag)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $top $outer") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $outer $inner") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $inner $middle") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $middle $leaf") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $leaf $core") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $core $tag") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync lowers a two-level nested managed scalar field" {
    const source =
        \\Leaf {
        \\    value [u8]
        \\    tag i32
        \\}
        \\Inner {
        \\    leaf Leaf
        \\    tag i32
        \\}
        \\Outer {
        \\    inner Inner
        \\    tag i32
        \\}
        \\update(outer Outer) -> Outer {
        \\    return @set(outer, .inner, .leaf, .tag, 9)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $outer $inner") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $inner $leaf") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $leaf $value") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $leaf") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $inner") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $outer") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync gets a two-level nested managed field" {
    const source =
        \\Leaf {
        \\    value [u8]
        \\}
        \\Inner {
        \\    leaf Leaf
        \\}
        \\Outer {
        \\    inner Inner
        \\}
        \\read_value(outer Outer) -> [u8] {
        \\    return @get(outer, .inner, .leaf, .value)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $outer $inner") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $inner $leaf") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $leaf $value") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync lowers a three-level nested managed field" {
    const source =
        \\Leaf {
        \\    value [u8]
        \\    tag i32
        \\}
        \\Middle {
        \\    leaf Leaf
        \\}
        \\Inner {
        \\    middle Middle
        \\}
        \\Outer {
        \\    inner Inner
        \\}
        \\update(outer Outer) -> Outer {
        \\    return @set(outer, .inner, .middle, .leaf, .tag, 9)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $outer $inner") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $inner $middle") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $middle $leaf") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $leaf $value") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $leaf") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $middle") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $inner") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $outer") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync gets a three-level nested managed field" {
    const source =
        \\Leaf {
        \\    value [u8]
        \\}
        \\Middle {
        \\    leaf Leaf
        \\}
        \\Inner {
        \\    middle Middle
        \\}
        \\Outer {
        \\    inner Inner
        \\}
        \\read_value(outer Outer) -> [u8] {
        \\    return @get(outer, .inner, .middle, .leaf, .value)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $outer $inner") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $inner $middle") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $middle $leaf") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.get $leaf $value") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
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

test "GC sync lowers a string literal in a byte-list result context" {
    const source =
        \\make() -> [u8] {
        \\    return "abc"
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(result (ref null $do_bytes))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.new_fixed $do_bytes 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "struct.new $do_text") == null);
}

test "GC sync lowers scalar-list get through a typed GC array" {
    const source =
        \\first(xs [i32]) -> i32 {
        \\    return @get(xs, 0)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "array.get $do_i32") != null);
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

test "GC sync lowers a resolved generic payload-union identity" {
    const source =
        \\Choice = Empty | Bytes([u8])
        \\#T
        \\identity(value T) -> T {
        \\    return value
        \\}
        \\relay(value Choice) -> Choice {
        \\    return identity(value)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(func $identity__Choice (param $value (ref null $choice)) (result (ref null $choice))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $identity__Choice") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "__arc_") == null);
}

test "GC sync lowers a resolved generic payload-union typed local" {
    const source =
        \\Choice = Empty | Bytes([u8])
        \\#T
        \\identity(value T) -> T {
        \\    out T = value
        \\    return out
        \\}
        \\relay(value Choice) -> Choice {
        \\    return identity(value)
        \\}
        \\start() {}
    ;
    const wat = try emit_test_source(std.testing.allocator, source);
    defer std.testing.allocator.free(wat);
    try std.testing.expect(std.mem.indexOf(u8, wat, "(local $out (ref null $choice))") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "call $identity__Choice") != null);
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
