//! Collect domain — func (extracted from codegen_collect).
const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const test_runner = @import("test_runner.zig");
const type_util = @import("type_name.zig");
const codegen_tokens = @import("codegen_tokens.zig");
const codegen_names = @import("codegen_names.zig");
const model = @import("codegen_model.zig");
const codegen_union_layout = @import("codegen_union_layout.zig");
const codegen_imports = @import("codegen_imports.zig");
const codegen_wasi_registry = @import("codegen_wasi_registry.zig");
const codegen_collect_util = @import("codegen_collect_util.zig");
const append_tuple_leaf_types = codegen_collect_util.append_tuple_leaf_types;
const error_nil_alias_target = codegen_collect_util.error_nil_alias_target;
const find_struct_decl = codegen_collect_util.find_struct_decl;
const find_struct_layout = codegen_collect_util.find_struct_layout;
const has_top_level_token = codegen_collect_util.has_top_level_token;
const has_type_param_name = codegen_collect_util.has_type_param_name;
const is_error_enum_type = codegen_collect_util.is_error_enum_type;
const is_error_like_type = codegen_collect_util.is_error_like_type;
const is_top_level_struct_decl_start = codegen_collect_util.is_top_level_struct_decl_start;
const parse_codegen_type_expr = codegen_collect_util.parse_codegen_type_expr;
const parse_func_body_shape = codegen_collect_util.parse_func_body_shape;
const parse_generic_inline_union_layout = codegen_collect_util.parse_generic_inline_union_layout;
const parse_struct_error_result_type = codegen_collect_util.parse_struct_error_result_type;
const parse_union_type_layout = codegen_collect_util.parse_union_type_layout;

const compactTokenText = codegen_tokens.compact_token_text;
const find_arg_end = codegen_tokens.find_arg_end;
const find_line_end = codegen_tokens.find_line_end;
const findLineStart = codegen_tokens.find_line_start;
const find_matching = codegen_tokens.find_matching;
const is_core_wasm_scalar = codegen_names.is_core_wasm_scalar;
const is_line_start = codegen_tokens.is_line_start;
const isUserFuncDeclStart = codegen_tokens.is_user_func_decl_start;
const moduleScopedSymbolName = codegen_names.module_scoped_symbol_name;
const module_tokens_equal = codegen_tokens.module_tokens_equal;
const publicDeclName = codegen_names.public_decl_name;
const tok_eq = codegen_tokens.tok_eq;
const find_codegen_import_by_alias = codegen_imports.find_codegen_import_by_alias;
const collect_start_body_calls = codegen_imports.collect_start_body_calls;
const collect_test_body_calls = codegen_imports.collect_test_body_calls;
const collect_all_function_body_calls = codegen_imports.collect_all_function_body_calls;
const collect_function_body_calls = codegen_imports.collect_function_body_calls;
const find_imported_module_index = codegen_imports.find_imported_module_index;
const find_root_module_index = codegen_imports.find_root_module_index;
const has_reach_visit = codegen_imports.has_reach_visit;
const is_tuple_type_name = type_util.is_tuple_type_name;
const managed_payload_elem_type_from_name = type_util.managed_payload_elem_type_from_name;
const tuple_arity = type_util.tuple_arity;
const FuncDecl = model.FuncDecl;
const FuncParam = model.FuncParam;
const FuncResultItem = model.FuncResultItem;
const FuncResultParse = model.FuncResultParse;
const ImportedAliasContext = model.ImportedAliasContext;
const OwnedFuncTypeShape = model.OwnedFuncTypeShape;
const ParsedCodegenType = model.ParsedCodegenType;
const ReachVisit = model.ReachVisit;
const StructDecl = model.StructDecl;
const StructLayout = model.StructLayout;

fn free_func_param_list(allocator: std.mem.Allocator, params: *std.ArrayList(FuncParam)) void {
    for (params.items) |param| {
        if (param.callback) |callback| {
            if (callback.owned) allocator.free(callback.shape.param_types);
        }
    }
    params.deinit(allocator);
}

pub fn parse_func_param_type_expr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    owned_types: *std.ArrayList([]const u8),
) !?ParsedCodegenType {
    if (start_idx >= end_idx) return null;
    if (has_top_level_token(tokens, start_idx, end_idx, "|")) {
        const ty = try compactTokenText(allocator, tokens, start_idx, end_idx);
        errdefer allocator.free(ty);
        try owned_types.append(allocator, ty);
        return .{ .ty = ty, .next_idx = end_idx };
    }
    return parse_codegen_type_expr(allocator, tokens, start_idx, end_idx, owned_types);
}

pub fn is_return_arrow_at(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 1 < tokens.len and tok_eq(tokens[idx], "-") and tok_eq(tokens[idx + 1], ">");
}

pub fn find_constraint_block_start_before(tokens: []const lexer.Token, decl_start_idx: usize) ?usize {
    if (decl_start_idx == 0 or decl_start_idx >= tokens.len) return null;

    var scan_idx = decl_start_idx;
    var expected_line = tokens[decl_start_idx].line;
    var block_start: ?usize = null;
    while (scan_idx > 0) {
        const prev_idx = scan_idx - 1;
        const prev_line = tokens[prev_idx].line;
        if (prev_line + 1 != expected_line) break;

        const line_start = findLineStart(tokens, prev_idx);
        if (!tok_eq(tokens[line_start], "#")) break;

        block_start = line_start;
        scan_idx = line_start;
        expected_line = prev_line;
    }
    return block_start;
}

pub fn find_line_end_idx(tokens: []const lexer.Token, start_idx: usize) usize {
    return find_line_end(tokens, start_idx);
}

pub fn find_top_level_assign_eq_on_line(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tok_eq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tok_eq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
        if (depth_paren == 0 and depth_brace == 0 and depth_angle == 0 and tok_eq(tokens[i], "=")) return i;
    }
    return null;
}

pub fn simple_type_name(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    if (start_idx + 1 != end_idx) return null;
    if (tokens[start_idx].kind != .ident) return null;
    return tokens[start_idx].lexeme;
}

pub fn is_top_level_comma_any(tokens: []const lexer.Token, idx: usize, start_idx: usize, end_idx: usize) bool {
    if (!tok_eq(tokens[idx], ",")) return false;

    var depth_paren: usize = 0;
    var depth_brace: usize = 0;
    var depth_angle: usize = 0;
    var i = start_idx;
    while (i < idx and i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "(")) {
            depth_paren += 1;
            continue;
        }
        if (tok_eq(tokens[i], ")")) {
            if (depth_paren > 0) depth_paren -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "<")) {
            depth_angle += 1;
            continue;
        }
        if (tok_eq(tokens[i], ">")) {
            if (depth_angle > 0) depth_angle -= 1;
            continue;
        }
    }
    return depth_paren == 0 and depth_brace == 0 and depth_angle == 0;
}

pub fn parse_type_name_list(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) ![]?[]const u8 {
    var out = std.ArrayList(?[]const u8).empty;
    errdefer out.deinit(allocator);

    var seg_start = start_idx;
    var i = start_idx;
    while (i <= end_idx) : (i += 1) {
        if (i < end_idx and !is_top_level_comma_any(tokens, i, start_idx, end_idx)) continue;
        if (seg_start < i) {
            try out.append(allocator, simple_type_name(tokens, seg_start, i));
        }
        seg_start = i + 1;
    }
    return out.toOwnedSlice(allocator);
}

pub fn parse_func_type_constraint_shape(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    func_start_idx: usize,
    constraint_name: []const u8,
) !?OwnedFuncTypeShape {
    const block_start = find_constraint_block_start_before(tokens, func_start_idx) orelse return null;

    var i = block_start;
    while (i < func_start_idx) {
        if (!tok_eq(tokens[i], "#")) {
            i += 1;
            continue;
        }
        const line_end = find_line_end_idx(tokens, i);
        const is_func_constraint = i + 2 < line_end and tok_eq(tokens[i + 2], "(");
        if (is_func_constraint or i + 1 >= line_end or !std.mem.eql(u8, tokens[i + 1].lexeme, constraint_name)) {
            i = line_end;
            continue;
        }

        const eq_idx = find_top_level_assign_eq_on_line(tokens, i + 2, line_end) orelse return null;
        if (!is_func_type_range(tokens, eq_idx + 1, line_end)) return null;
        const close_params = find_matching(tokens, eq_idx + 1, "(", ")") catch return null;
        const param_types = try parse_type_name_list(allocator, tokens, eq_idx + 2, close_params);
        return .{
            .shape = .{
                .param_types = param_types,
                .return_type = simple_type_name(tokens, close_params + 3, line_end),
            },
            .owned = true,
        };
    }
    return null;
}

pub fn is_func_type_range(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx >= end_idx or !tok_eq(tokens[start_idx], "(")) return false;
    const close_idx = find_matching(tokens, start_idx, "(", ")") catch return false;
    return close_idx + 2 < end_idx and is_return_arrow_at(tokens, close_idx + 1);
}

fn append_one_func_param(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    param_idx: usize,
    close_params: usize,
    type_params: []const []const u8,
    constraint_search_idx: usize,
    owned_types: *std.ArrayList([]const u8),
    params: *std.ArrayList(FuncParam),
) !usize {
    if (tokens[param_idx].kind != .ident) return error.InvalidParamName;
    const param_end = find_arg_end(tokens, param_idx, close_params);
    if (param_end == param_idx + 1) {
        if (type_params.len == 0) return error.InvalidParamName;
        try params.append(allocator, .{
            .name = tokens[param_idx].lexeme,
            .ty = "",
        });
        var next = param_end;
        if (next < close_params and tok_eq(tokens[next], ",")) next += 1;
        return next;
    }
    var type_start = param_idx + 1;
    var variadic = false;
    if (type_start < close_params and tok_eq(tokens[type_start], "...")) {
        variadic = true;
        type_start += 1;
    }
    const parsed_ty = (try parse_func_param_type_expr(allocator, tokens, type_start, param_end, owned_types)) orelse return error.InvalidParamName;
    const callback = try parse_func_type_constraint_shape(allocator, tokens, constraint_search_idx, parsed_ty.ty);
    try params.append(allocator, .{
        .name = tokens[param_idx].lexeme,
        .ty = parsed_ty.ty,
        .variadic = variadic,
        .callback = callback,
    });
    var next = parsed_ty.next_idx;
    if (next < close_params and tok_eq(tokens[next], ",")) next += 1;
    return next;
}

pub fn collect_func_decls(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    imported_alias_ctx: ?ImportedAliasContext,
    out: *std.ArrayList(FuncDecl),
) !void {
    var depth_brace: usize = 0;
    var pending_type_params = std.ArrayList([]const u8).empty;
    defer pending_type_params.deinit(allocator);
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (is_line_start(tokens, i) and tok_eq(tokens[i], "#")) {
            const line_end = find_line_end(tokens, i);
            if (line_end == i + 2 and tokens[i + 1].kind == .ident) {
                try pending_type_params.append(allocator, tokens[i + 1].lexeme);
            }
            i = line_end - 1;
            continue;
        }
        if (is_top_level_struct_decl_start(tokens, i)) {
            pending_type_params.clearRetainingCapacity();
            i = (find_matching(tokens, i + 1, "{", "}") catch i);
            continue;
        }
        if (!isUserFuncDeclStart(tokens, i)) continue;

        const open_params = i + 1;
        const close_params = try find_matching(tokens, open_params, "(", ")");
        const body = parse_func_body_shape(tokens, close_params) catch continue;
        var owned_types = std.ArrayList([]const u8).empty;
        errdefer {
            for (owned_types.items) |owned| allocator.free(owned);
            owned_types.deinit(allocator);
        }
        const type_params = if (pending_type_params.items.len == 0)
            &[_][]const u8{}
        else
            try allocator.dupe([]const u8, pending_type_params.items);
        var type_params_owned = pending_type_params.items.len != 0;
        errdefer if (type_params_owned) allocator.free(type_params);
        const parsed_results = (try parse_func_decl_result_types(
            allocator,
            tokens,
            body.result_start,
            body.result_end,
            type_params,
            structs,
            struct_layouts,
            imported_alias_ctx,
            &owned_types,
        )) orelse continue;
        const results = parsed_results.types;
        var results_owned = true;
        errdefer if (results_owned) allocator.free(results);
        const result_items = parsed_results.items;
        var result_items_owned = parsed_results.owns_items;
        errdefer if (result_items_owned) allocator.free(result_items);

        var params = std.ArrayList(FuncParam).empty;
        errdefer free_func_param_list(allocator, &params);
        var param_idx = open_params + 1;
        while (param_idx < close_params) {
            if (tok_eq(tokens[param_idx], ",")) {
                param_idx += 1;
                continue;
            }
            param_idx = try append_one_func_param(
                allocator,
                tokens,
                param_idx,
                close_params,
                type_params,
                i,
                &owned_types,
                &params,
            );
        }

        try out.append(allocator, .{
            .name = publicDeclName(tokens[i].lexeme),
            .source_name = publicDeclName(tokens[i].lexeme),
            .params = try params.toOwnedSlice(allocator),
            .result = if (results.len == 1) results[0] else null,
            .results = results,
            .result_items = result_items,
            .result_struct = parsed_results.result_struct,
            .result_union = parsed_results.result_union,
            .type_params = type_params,
            .is_generic_template = type_params.len != 0,
            .owned_types = try owned_types.toOwnedSlice(allocator),
            .tokens = tokens,
            .start_idx = i,
            .arrow = body.arrow,
            .body_start = body.body_start,
            .body_end = body.body_end,
        });
        results_owned = false;
        result_items_owned = false;
        type_params_owned = false;
        pending_type_params.clearRetainingCapacity();
        i = body.next_idx;
    }
}

pub fn collect_direct_imported_func_decls(
    allocator: std.mem.Allocator,
    entry_tokens: []const lexer.Token,
    graph: *const imports.ModuleGraph,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    out: *std.ArrayList(FuncDecl),
) !void {
    const root_idx = find_root_module_index(graph.modules, entry_tokens) orelse return;

    var stack = std.ArrayList(ReachVisit).empty;
    defer stack.deinit(allocator);

    var visited = std.ArrayList(ReachVisit).empty;
    defer visited.deinit(allocator);

    try collect_start_body_calls(allocator, graph.modules[root_idx].tokens, root_idx, &stack);
    try collect_all_function_body_calls(allocator, graph.modules[root_idx].tokens, root_idx, &stack);
    while (stack.items.len != 0) {
        const visit = stack.pop().?;
        if (has_reach_visit(visited.items, visit)) continue;
        try visited.append(allocator, visit);

        const module = graph.modules[visit.module_idx];
        if (find_codegen_import_by_alias(module.tokens, visit.name)) |import_ref| {
            const child_idx = find_imported_module_index(allocator, graph, visit.module_idx, import_ref) orelse continue;
            if (find_func_decl(out.items, import_ref.alias) == null) {
                _ = try collect_func_decl_by_name_as(
                    allocator,
                    graph.modules[child_idx].tokens,
                    structs,
                    struct_layouts,
                    .{ .graph = graph, .module_idx = child_idx },
                    import_ref.target,
                    import_ref.alias,
                    false,
                    out,
                );
            }
            try collect_function_body_calls(allocator, graph.modules[child_idx].tokens, child_idx, import_ref.target, &stack);
            continue;
        }

        if (visit.module_idx != root_idx and find_func_decl_by_source_for_tokens(out.items, module.tokens, publicDeclName(visit.name)) == null) {
            const emit_name = try moduleScopedSymbolName(allocator, visit.module_idx, publicDeclName(visit.name));
            defer allocator.free(emit_name);
            _ = try collect_func_decl_by_name_as(
                allocator,
                module.tokens,
                structs,
                struct_layouts,
                .{ .graph = graph, .module_idx = visit.module_idx },
                publicDeclName(visit.name),
                emit_name,
                true,
                out,
            );
        }
        try collect_function_body_calls(allocator, module.tokens, visit.module_idx, visit.name, &stack);
    }
}

pub fn collect_direct_imported_func_decls_from_tests(
    allocator: std.mem.Allocator,
    entry_tokens: []const lexer.Token,
    graph: *const imports.ModuleGraph,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    out: *std.ArrayList(FuncDecl),
) !void {
    const root_idx = find_root_module_index(graph.modules, entry_tokens) orelse return;

    var stack = std.ArrayList(ReachVisit).empty;
    defer stack.deinit(allocator);

    var visited = std.ArrayList(ReachVisit).empty;
    defer visited.deinit(allocator);

    try collect_test_body_calls(allocator, graph.modules[root_idx].tokens, root_idx, &stack);
    try collect_all_function_body_calls(allocator, graph.modules[root_idx].tokens, root_idx, &stack);
    while (stack.items.len != 0) {
        const visit = stack.pop().?;
        if (has_reach_visit(visited.items, visit)) continue;
        try visited.append(allocator, visit);

        const module = graph.modules[visit.module_idx];
        if (find_codegen_import_by_alias(module.tokens, visit.name)) |import_ref| {
            const child_idx = find_imported_module_index(allocator, graph, visit.module_idx, import_ref) orelse continue;
            if (find_func_decl(out.items, import_ref.alias) == null) {
                _ = try collect_func_decl_by_name_as(
                    allocator,
                    graph.modules[child_idx].tokens,
                    structs,
                    struct_layouts,
                    .{ .graph = graph, .module_idx = child_idx },
                    import_ref.target,
                    import_ref.alias,
                    false,
                    out,
                );
            }
            try collect_function_body_calls(allocator, graph.modules[child_idx].tokens, child_idx, import_ref.target, &stack);
            continue;
        }

        if (visit.module_idx != root_idx and find_func_decl_by_source_for_tokens(out.items, module.tokens, publicDeclName(visit.name)) == null) {
            const emit_name = try moduleScopedSymbolName(allocator, visit.module_idx, publicDeclName(visit.name));
            defer allocator.free(emit_name);
            _ = try collect_func_decl_by_name_as(
                allocator,
                module.tokens,
                structs,
                struct_layouts,
                .{ .graph = graph, .module_idx = visit.module_idx },
                publicDeclName(visit.name),
                emit_name,
                true,
                out,
            );
        }
        try collect_function_body_calls(allocator, module.tokens, visit.module_idx, visit.name, &stack);
    }
}

pub fn same_callable_source_name(left: []const u8, right: []const u8) bool {
    return std.mem.eql(u8, publicDeclName(left), publicDeclName(right));
}

pub fn collect_func_decl_by_name_as(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    imported_alias_ctx: ?ImportedAliasContext,
    target_name: []const u8,
    emit_name: []const u8,
    owned_emit_name: bool,
    out: *std.ArrayList(FuncDecl),
) !bool {
    var depth_brace: usize = 0;
    var pending_type_params = std.ArrayList([]const u8).empty;
    defer pending_type_params.deinit(allocator);
    var collected = false;
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (is_line_start(tokens, i) and tok_eq(tokens[i], "#")) {
            const line_end = find_line_end(tokens, i);
            if (line_end == i + 2 and tokens[i + 1].kind == .ident) {
                try pending_type_params.append(allocator, tokens[i + 1].lexeme);
            }
            i = line_end - 1;
            continue;
        }
        if (is_top_level_struct_decl_start(tokens, i)) {
            pending_type_params.clearRetainingCapacity();
            i = (find_matching(tokens, i + 1, "{", "}") catch i);
            continue;
        }
        if (!isUserFuncDeclStart(tokens, i)) continue;
        const open_params = i + 1;
        const close_params = find_matching(tokens, open_params, "(", ")") catch {
            pending_type_params.clearRetainingCapacity();
            continue;
        };
        const body = parse_func_body_shape(tokens, close_params) catch {
            pending_type_params.clearRetainingCapacity();
            continue;
        };
        if (!std.mem.eql(u8, publicDeclName(tokens[i].lexeme), target_name)) {
            pending_type_params.clearRetainingCapacity();
            i = body.next_idx;
            continue;
        }
        var owned_types = std.ArrayList([]const u8).empty;
        errdefer {
            for (owned_types.items) |owned| allocator.free(owned);
            owned_types.deinit(allocator);
        }
        const type_params = if (pending_type_params.items.len == 0)
            &[_][]const u8{}
        else
            try allocator.dupe([]const u8, pending_type_params.items);
        var type_params_owned = pending_type_params.items.len != 0;
        errdefer if (type_params_owned) allocator.free(type_params);
        const parsed_results = (try parse_func_decl_result_types(
            allocator,
            tokens,
            body.result_start,
            body.result_end,
            type_params,
            structs,
            struct_layouts,
            imported_alias_ctx,
            &owned_types,
        )) orelse return false;
        const results = parsed_results.types;
        var results_owned = true;
        errdefer if (results_owned) allocator.free(results);
        const result_items = parsed_results.items;
        var result_items_owned = parsed_results.owns_items;
        errdefer if (result_items_owned) allocator.free(result_items);

        var params = std.ArrayList(FuncParam).empty;
        errdefer free_func_param_list(allocator, &params);
        var param_idx = open_params + 1;
        while (param_idx < close_params) {
            if (tok_eq(tokens[param_idx], ",")) {
                param_idx += 1;
                continue;
            }
            param_idx = try append_one_func_param(
                allocator,
                tokens,
                param_idx,
                close_params,
                type_params,
                i,
                &owned_types,
                &params,
            );
        }

        const decl_name = if (owned_emit_name) try allocator.dupe(u8, emit_name) else emit_name;
        var decl_name_owned = owned_emit_name;
        errdefer if (decl_name_owned) allocator.free(decl_name);

        try out.append(allocator, .{
            .name = decl_name,
            .source_name = target_name,
            .params = try params.toOwnedSlice(allocator),
            .result = if (results.len == 1) results[0] else null,
            .results = results,
            .result_items = result_items,
            .result_struct = parsed_results.result_struct,
            .result_union = parsed_results.result_union,
            .type_params = type_params,
            .is_generic_template = type_params.len != 0,
            .owned_name = owned_emit_name,
            .owned_types = try owned_types.toOwnedSlice(allocator),
            .tokens = tokens,
            .start_idx = i,
            .arrow = body.arrow,
            .body_start = body.body_start,
            .body_end = body.body_end,
        });
        results_owned = false;
        result_items_owned = false;
        type_params_owned = false;
        decl_name_owned = false;
        collected = true;
        pending_type_params.clearRetainingCapacity();
        i = body.next_idx;
        continue;
    }
    return collected;
}

pub fn parse_func_decl_result_types(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    type_params: []const []const u8,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    imported_alias_ctx: ?ImportedAliasContext,
    owned_types: *std.ArrayList([]const u8),
) !?FuncResultParse {
    if (start_idx == end_idx) {
        return .{
            .types = try allocator.alloc([]const u8, 0),
            .items = try allocator.alloc(FuncResultItem, 0),
        };
    }

    if (type_params.len != 0) {
        const uses_type_param = type_params_appear_in_range(tokens, start_idx, end_idx, type_params);
        if (uses_type_param) {
            return try parse_generic_func_result_types(
                allocator,
                tokens,
                start_idx,
                end_idx,
                type_params,
                structs,
                struct_layouts,
                owned_types,
            );
        }
    }

    if (try parse_func_result_types(allocator, tokens, start_idx, end_idx, structs, struct_layouts, imported_alias_ctx, owned_types)) |parsed| {
        return parsed;
    }
    if (type_params.len != 0) {
        return try parse_generic_func_result_types(
            allocator,
            tokens,
            start_idx,
            end_idx,
            type_params,
            structs,
            struct_layouts,
            owned_types,
        );
    }
    return null;
}

fn parse_single_ident_func_result(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    imported_alias_ctx: ?ImportedAliasContext,
    results: *std.ArrayList([]const u8),
    items: *std.ArrayList(FuncResultItem),
) !?FuncResultParse {
    if (start_idx + 1 != end_idx or tokens[start_idx].kind != .ident) return null;
    const struct_name = tokens[start_idx].lexeme;

    if (find_struct_layout(struct_layouts, struct_name) == null) {
        if (find_struct_decl(structs, struct_name)) |decl| {
            const abi_start = results.items.len;
            for (decl.fields) |field| {
                if (!is_core_wasm_scalar(field.ty)) return null;
                try results.append(allocator, field.ty);
            }
            try items.append(allocator, .{ .ty = struct_name, .abi_start = abi_start, .abi_len = decl.fields.len });
            return .{
                .types = try results.toOwnedSlice(allocator),
                .items = try items.toOwnedSlice(allocator),
                .result_struct = struct_name,
            };
        }
    }
    if (is_error_enum_type(tokens, struct_name)) {
        const abi_start = results.items.len;
        try results.append(allocator, struct_name);
        try items.append(allocator, .{ .ty = struct_name, .abi_start = abi_start, .abi_len = 1 });
        return .{
            .types = try results.toOwnedSlice(allocator),
            .items = try items.toOwnedSlice(allocator),
        };
    }
    if (error_nil_alias_target(tokens, struct_name)) |error_name| {
        const abi_start = results.items.len;
        try results.append(allocator, error_name);
        try items.append(allocator, .{ .ty = error_name, .abi_start = abi_start, .abi_len = 1 });
        return .{
            .types = try results.toOwnedSlice(allocator),
            .items = try items.toOwnedSlice(allocator),
        };
    }
    if (imported_error_nil_alias_target(allocator, imported_alias_ctx, tokens, struct_name)) |error_name| {
        const abi_start = results.items.len;
        try results.append(allocator, error_name);
        try items.append(allocator, .{ .ty = error_name, .abi_start = abi_start, .abi_len = 1 });
        return .{
            .types = try results.toOwnedSlice(allocator),
            .items = try items.toOwnedSlice(allocator),
        };
    }
    return null;
}

pub fn parse_func_result_types(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    imported_alias_ctx: ?ImportedAliasContext,
    owned_types: *std.ArrayList([]const u8),
) !?FuncResultParse {
    var results = std.ArrayList([]const u8).empty;
    errdefer results.deinit(allocator);
    var items = std.ArrayList(FuncResultItem).empty;
    errdefer items.deinit(allocator);

    if (start_idx + 1 == end_idx and tok_eq(tokens[start_idx], "nil")) {
        return .{
            .types = try results.toOwnedSlice(allocator),
            .items = try items.toOwnedSlice(allocator),
        };
    }

    if (try parse_union_type_layout(allocator, tokens, start_idx, end_idx, structs, struct_layouts, imported_alias_ctx, owned_types)) |layout| {
        const abi_start = results.items.len;
        for (layout.payload_tys) |payload_ty| {
            try results.append(allocator, payload_ty);
        }
        try results.append(allocator, "i32");
        try items.append(allocator, .{
            .ty = layout.source_ty,
            .abi_start = abi_start,
            .abi_len = layout.payload_tys.len + 1,
            .union_layout = layout,
        });
        return .{
            .types = try results.toOwnedSlice(allocator),
            .items = try items.toOwnedSlice(allocator),
            .result_union = layout,
        };
    }

    if (parse_error_nil_result_type(tokens, start_idx, end_idx)) |result_ty| {
        const abi_start = results.items.len;
        try results.append(allocator, result_ty);
        try items.append(allocator, .{ .ty = result_ty, .abi_start = abi_start, .abi_len = 1 });
        return .{
            .types = try results.toOwnedSlice(allocator),
            .items = try items.toOwnedSlice(allocator),
        };
    }

    if (parse_struct_error_result_type(tokens, start_idx, end_idx, structs, struct_layouts)) |parsed| {
        const decl = find_struct_decl(structs, parsed.struct_name) orelse return null;
        const abi_start = results.items.len;
        for (decl.fields) |field| {
            if (!is_core_wasm_scalar(field.ty)) return null;
            try results.append(allocator, field.ty);
        }
        try results.append(allocator, parsed.error_name);
        try items.append(allocator, .{ .ty = parsed.struct_name, .abi_start = abi_start, .abi_len = decl.fields.len + 1 });
        return .{
            .types = try results.toOwnedSlice(allocator),
            .items = try items.toOwnedSlice(allocator),
            .result_struct = parsed.struct_name,
        };
    }

    if (try parse_single_ident_func_result(
        allocator,
        tokens,
        start_idx,
        end_idx,
        structs,
        struct_layouts,
        imported_alias_ctx,
        &results,
        &items,
    )) |parsed| {
        return parsed;
    }

    var i = start_idx;
    while (i < end_idx) {
        if (tok_eq(tokens[i], ",")) {
            i += 1;
            continue;
        }

        if (try parse_union_type_layout(allocator, tokens, i, find_arg_end(tokens, i, end_idx), structs, struct_layouts, imported_alias_ctx, owned_types)) |layout| {
            const item_end = find_arg_end(tokens, i, end_idx);
            if (item_end == i) return null;
            const abi_start = results.items.len;
            for (layout.payload_tys) |payload_ty| {
                try results.append(allocator, payload_ty);
            }
            try results.append(allocator, "i32");
            try items.append(allocator, .{
                .ty = layout.source_ty,
                .abi_start = abi_start,
                .abi_len = layout.payload_tys.len + 1,
                .union_layout = layout,
            });
            i = item_end;
            if (i < end_idx and tok_eq(tokens[i], ",")) i += 1;
            continue;
        }

        const parsed_ty = (try parse_codegen_type_expr(allocator, tokens, i, end_idx, owned_types)) orelse return null;
        const result_ty = parsed_ty.ty;
        if (is_tuple_type_name(result_ty)) {
            const arity = tuple_arity(result_ty) orelse return null;
            if (arity < 2) return null;
            const abi_start = results.items.len;
            const leaf_start = results.items.len;
            try append_tuple_leaf_types(allocator, result_ty, &results);
            if (results.items.len - leaf_start < 2) return null;
            for (results.items[leaf_start..]) |leaf_ty| {
                if (!is_core_wasm_scalar(leaf_ty)) return null;
            }
            try items.append(allocator, .{
                .ty = result_ty,
                .abi_start = abi_start,
                .abi_len = results.items.len - abi_start,
            });
            i = parsed_ty.next_idx;
            if (i < end_idx and tok_eq(tokens[i], ",")) i += 1;
            continue;
        }
        const accepted = is_core_wasm_scalar(result_ty) or
            managed_payload_elem_type_from_name(result_ty) != null or
            find_struct_layout(struct_layouts, result_ty) != null or
            (tokens[i].kind == .ident and error_nil_alias_target(tokens, tokens[i].lexeme) != null) or
            (tokens[i].kind == .ident and imported_error_nil_alias_target(allocator, imported_alias_ctx, tokens, tokens[i].lexeme) != null);
        if (!accepted) return null;

        const abi_start = results.items.len;
        try results.append(allocator, result_ty);
        try items.append(allocator, .{ .ty = result_ty, .abi_start = abi_start, .abi_len = 1 });
        i = parsed_ty.next_idx;
        if (i < end_idx and tok_eq(tokens[i], ",")) i += 1;
    }

    var result_struct: ?[]const u8 = null;
    if (items.items.len == 1 and is_tuple_type_name(items.items[0].ty) and items.items[0].abi_len >= 2) {
        result_struct = items.items[0].ty;
    }

    return .{
        .types = try results.toOwnedSlice(allocator),
        .items = try items.toOwnedSlice(allocator),
        .result_struct = result_struct,
    };
}

pub fn parse_generic_func_result_types(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    type_params: []const []const u8,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    owned_types: *std.ArrayList([]const u8),
) !?FuncResultParse {
    var results = std.ArrayList([]const u8).empty;
    errdefer results.deinit(allocator);
    var items = std.ArrayList(FuncResultItem).empty;
    errdefer items.deinit(allocator);

    if (start_idx + 1 == end_idx and tok_eq(tokens[start_idx], "nil")) {
        return .{
            .types = try results.toOwnedSlice(allocator),
            .items = try items.toOwnedSlice(allocator),
        };
    }

    if (try parse_generic_inline_union_layout(allocator, tokens, start_idx, end_idx, type_params, structs, struct_layouts, owned_types)) |layout| {
        const abi_start = results.items.len;
        for (layout.payload_tys) |payload_ty| {
            try results.append(allocator, payload_ty);
        }
        try results.append(allocator, "i32");
        try items.append(allocator, .{
            .ty = layout.source_ty,
            .abi_start = abi_start,
            .abi_len = layout.payload_tys.len + 1,
            .union_layout = layout,
        });
        return .{
            .types = try results.toOwnedSlice(allocator),
            .items = try items.toOwnedSlice(allocator),
            .result_union = layout,
        };
    }

    var i = start_idx;
    while (i < end_idx) {
        if (tok_eq(tokens[i], ",")) {
            i += 1;
            continue;
        }

        const parsed_ty = (try parse_codegen_type_expr(allocator, tokens, i, end_idx, owned_types)) orelse return null;
        const result_ty = parsed_ty.ty;
        const accepted = is_core_wasm_scalar(result_ty) or
            has_type_param_name(type_params, result_ty) or
            managed_payload_elem_type_from_name(result_ty) != null or
            find_struct_layout(struct_layouts, result_ty) != null or
            find_struct_decl(structs, result_ty) != null;
        if (!accepted) return null;

        try results.append(allocator, result_ty);
        try items.append(allocator, .{ .ty = result_ty, .abi_start = results.items.len - 1, .abi_len = 1 });
        i = parsed_ty.next_idx;
        if (i < end_idx and tok_eq(tokens[i], ",")) i += 1;
    }

    return .{
        .types = try results.toOwnedSlice(allocator),
        .items = try items.toOwnedSlice(allocator),
    };
}

pub fn type_params_appear_in_range(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    type_params: []const []const u8,
) bool {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tokens[i].kind != .ident) continue;
        if (has_type_param_name(type_params, tokens[i].lexeme)) return true;
    }
    return false;
}

pub fn parse_error_nil_result_type(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?[]const u8 {
    if (start_idx + 3 != end_idx) return null;
    if (!tok_eq(tokens[start_idx + 1], "|")) return null;
    if (tokens[start_idx].kind == .ident and tok_eq(tokens[start_idx + 2], "nil") and is_error_like_type(tokens, tokens[start_idx].lexeme)) {
        return tokens[start_idx].lexeme;
    }
    if (tok_eq(tokens[start_idx], "nil") and tokens[start_idx + 2].kind == .ident and is_error_like_type(tokens, tokens[start_idx + 2].lexeme)) {
        return tokens[start_idx + 2].lexeme;
    }
    return null;
}

pub fn imported_error_nil_alias_target(
    allocator: std.mem.Allocator,
    imported_alias_ctx: ?ImportedAliasContext,
    tokens: []const lexer.Token,
    name: []const u8,
) ?[]const u8 {
    const ctx = imported_alias_ctx orelse return null;
    const import_ref = find_codegen_import_by_alias(tokens, name) orelse return null;
    const child_idx = find_imported_module_index(allocator, ctx.graph, ctx.module_idx, import_ref) orelse return null;
    return error_nil_alias_target(ctx.graph.modules[child_idx].tokens, import_ref.target);
}

pub fn find_func_decl(functions: []const FuncDecl, name: []const u8) ?FuncDecl {
    for (functions) |func| {
        if (std.mem.eql(u8, func.name, name)) return func;
    }
    return null;
}

pub fn find_func_decl_by_source_for_tokens(functions: []const FuncDecl, tokens: []const lexer.Token, source_name: []const u8) ?FuncDecl {
    for (functions) |func| {
        if (!module_tokens_equal(func.tokens, tokens)) continue;
        if (same_callable_source_name(func.source_name, source_name)) return func;
    }
    return null;
}
