//! Collect domain — struct (extracted from gen_collect).
const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const test_runner = @import("test_runner.zig");
const type_util = @import("type_name.zig");
const codegen_tokens = @import("codegen_tokens.zig");
const codegen_names = @import("codegen_names.zig");
const model = @import("codegen_model.zig");
const constants = @import("codegen_constants.zig");
const codegen_union_layout = @import("codegen_union_layout.zig");
const codegen_imports = @import("codegen_imports.zig");
const codegen_wasi_registry = @import("codegen_wasi_registry.zig");
const gen_collect_util = @import("gen_collect_util.zig");
const appendTupleLeafTypes = gen_collect_util.appendTupleLeafTypes;
const appendTupleLeafTypesWithStructs = gen_collect_util.appendTupleLeafTypesWithStructs;
const appendUnionBranchPayloadTypes = gen_collect_util.appendUnionBranchPayloadTypes;
const bindGenericType = gen_collect_util.bindGenericType;
const findStructDecl = gen_collect_util.findStructDecl;
const findStructLayout = gen_collect_util.findStructLayout;
const funcParamAbiType = gen_collect_util.funcParamAbiType;
const genericTypeArgsRange = gen_collect_util.genericTypeArgsRange;
const hasTopLevelToken = gen_collect_util.hasTopLevelToken;
const isTopLevelStructDeclStart = gen_collect_util.isTopLevelStructDeclStart;
const parseCodegenTypeExpr = gen_collect_util.parseCodegenTypeExpr;
const parseFuncBodyShape = gen_collect_util.parseFuncBodyShape;
const structDeclHasManagedField = gen_collect_util.structDeclHasManagedField;
const substituteGenericTypeOwned = gen_collect_util.substituteGenericTypeOwned;
const tuplePackWidthWithStructs = gen_collect_util.tuplePackWidthWithStructs;

const alignUp = codegen_tokens.align_up;
const compactTokenText = codegen_tokens.compact_token_text;
const findLineEnd = codegen_tokens.find_line_end;
const findMatching = codegen_tokens.find_matching;
const findMatchingInRange = codegen_tokens.find_matching_in_range;
const findTopLevelToken = codegen_tokens.find_top_level_token;
const isLineStart = codegen_tokens.is_line_start;
const isUserFuncDeclStart = codegen_tokens.is_user_func_decl_start;
const publicDeclName = codegen_names.public_decl_name;
const tokEq = codegen_tokens.tok_eq;
const findTopLevelTypeSeparator = codegen_tokens.find_top_level_type_separator;
const findTopLevelTypeSeparatorFrom = codegen_tokens.find_top_level_type_separator_from;
const freeStructDecl = model.freeStructDecl;
const findImportedModuleIndex = codegen_imports.findImportedModuleIndex;
const findRootModuleIndex = codegen_imports.findRootModuleIndex;
const parseCodegenImport = codegen_imports.parseCodegenImport;
const isManagedPayloadType = type_util.isManagedPayloadType;
const isTupleTypeName = type_util.isTupleTypeName;
const isTuplePackableLeafType = type_util.isTuplePackableLeafType;
const managedPayloadElemTypeFromName = type_util.managedPayloadElemTypeFromName;
const tupleScalarLeafStorageByteWidth = type_util.tupleScalarLeafStorageByteWidth;
const typeBaseName = type_util.typeBaseName;
const typePayloadAlignment = type_util.typePayloadAlignment;
const typePayloadBytes = type_util.typePayloadBytes;
const FuncDecl = model.FuncDecl;
const GenericTypeBinding = model.GenericTypeBinding;
const ManagedFieldOffset = model.ManagedFieldOffset;
const StructDecl = model.StructDecl;
const StructField = model.StructField;
const StructLayout = model.StructLayout;
const TYPE_ID_FIRST_STRUCT = constants.TYPE_ID_FIRST_STRUCT;
const UnionBranch = codegen_union_layout.UnionBranch;
const UnionLayout = codegen_union_layout.UnionLayout;
const WasiHostImport = codegen_wasi_registry.WasiHostImport;

pub fn collect_struct_decls(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    out: *std.ArrayList(StructDecl),
) !void {
    var depth_brace: usize = 0;
    var pending_type_params = std.ArrayList([]const u8).empty;
    defer pending_type_params.deinit(allocator);
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (isLineStart(tokens, i) and tokEq(tokens[i], "#")) {
            const line_end = findLineEnd(tokens, i);
            if (line_end == i + 2 and tokens[i + 1].kind == .ident) {
                try pending_type_params.append(allocator, tokens[i + 1].lexeme);
            }
            i = line_end - 1;
            continue;
        }
        if (isUserFuncDeclStart(tokens, i)) {
            pending_type_params.clearRetainingCapacity();
            const close_params = findMatching(tokens, i + 1, "(", ")") catch continue;
            const body = parseFuncBodyShape(tokens, close_params) catch continue;
            i = body.next_idx;
            continue;
        }
        // Declarative: Name = @wasi_resource|wasi_record("…", { fields })
        if (is_wasi_struct_binding_struct_start(tokens, i)) {
            const close_call = findMatching(tokens, i + 4, "(", ")") catch continue;
            const open_brace = codegen_tokens.find_token(tokens, i + 5, close_call, "{") orelse continue;
            const close_brace = findMatching(tokens, open_brace, "{", "}") catch continue;
            var fields = std.ArrayList(StructField).empty;
            var owned_types = std.ArrayList([]const u8).empty;
            errdefer {
                for (owned_types.items) |owned| allocator.free(owned);
                owned_types.deinit(allocator);
                fields.deinit(allocator);
            }
            try append_struct_fields_in_brace_range(allocator, tokens, open_brace, close_brace, &fields, &owned_types);
            try out.append(allocator, .{
                .name = tokens[i].lexeme,
                .type_params = &[_][]const u8{},
                .fields = try fields.toOwnedSlice(allocator),
                .layout_source = null,
                .owned_types = try owned_types.toOwnedSlice(allocator),
                .tokens = tokens,
            });
            pending_type_params.clearRetainingCapacity();
            i = close_call;
            continue;
        }
        if (!isTopLevelStructDeclStart(tokens, i)) continue;

        const open_brace = i + 1;
        const close_brace = try findMatching(tokens, open_brace, "{", "}");
        const type_params = if (pending_type_params.items.len == 0)
            &[_][]const u8{}
        else
            try allocator.dupe([]const u8, pending_type_params.items);
        var type_params_owned = pending_type_params.items.len != 0;
        errdefer if (type_params_owned) allocator.free(type_params);
        var fields = std.ArrayList(StructField).empty;
        var owned_types = std.ArrayList([]const u8).empty;
        errdefer {
            for (owned_types.items) |owned| allocator.free(owned);
            owned_types.deinit(allocator);
            fields.deinit(allocator);
        }

        try append_struct_fields_in_brace_range(allocator, tokens, open_brace, close_brace, &fields, &owned_types);

        try out.append(allocator, .{
            .name = tokens[i].lexeme,
            .type_params = type_params,
            .fields = try fields.toOwnedSlice(allocator),
            .layout_source = null,
            .owned_types = try owned_types.toOwnedSlice(allocator),
            .tokens = tokens,
        });
        type_params_owned = false;
        pending_type_params.clearRetainingCapacity();
        i = close_brace;
    }
}

pub fn is_wasi_struct_binding_struct_start(tokens: []const lexer.Token, idx: usize) bool {
    if (idx + 5 >= tokens.len) return false;
    if (!isLineStart(tokens, idx)) return false;
    if (tokens[idx].kind != .ident) return false;
    if (!tokEq(tokens[idx + 1], "=")) return false;
    if (!tokEq(tokens[idx + 2], "@")) return false;
    if (tokens[idx + 3].kind != .ident) return false;
    const kind = tokens[idx + 3].lexeme;
    if (!std.mem.eql(u8, kind, "wasi_resource") and !std.mem.eql(u8, kind, "wasi_record")) return false;
    return tokEq(tokens[idx + 4], "(");
}

pub fn collect_imported_struct_decls(
    allocator: std.mem.Allocator,
    entry_tokens: []const lexer.Token,
    graph: *const imports.ModuleGraph,
    out: *std.ArrayList(StructDecl),
) !void {
    const root_idx = findRootModuleIndex(graph.modules, entry_tokens) orelse return;

    var i: usize = 0;
    while (i < entry_tokens.len) : (i += 1) {
        const import_ref = parseCodegenImport(entry_tokens, i) orelse continue;
        defer i = findLineEnd(entry_tokens, i) - 1;

        const child_idx = findImportedModuleIndex(allocator, graph, root_idx, import_ref) orelse continue;
        if (!std.mem.eql(u8, import_ref.alias, import_ref.target) and findStructDecl(out.items, import_ref.target) == null) {
            _ = try collect_struct_decl_by_name_as(
                allocator,
                graph.modules[child_idx].tokens,
                import_ref.target,
                import_ref.target,
                null,
                out,
            );
        }
        if (findStructDecl(out.items, import_ref.alias) != null) continue;
        _ = try collect_struct_decl_by_name_as(
            allocator,
            graph.modules[child_idx].tokens,
            import_ref.target,
            import_ref.alias,
            if (std.mem.eql(u8, import_ref.alias, import_ref.target)) null else import_ref.target,
            out,
        );
    }

    for (graph.modules, 0..) |module, idx| {
        if (idx == root_idx) continue;
        var module_structs = std.ArrayList(StructDecl).empty;
        defer module_structs.deinit(allocator);
        try collect_struct_decls(allocator, module.tokens, &module_structs);
        for (module_structs.items) |decl| {
            if (findStructDecl(out.items, decl.name) != null) {
                freeStructDecl(allocator, decl);
                continue;
            }
            try out.append(allocator, decl);
        }
    }
}

pub fn collect_struct_decl_by_name_as(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    target_name: []const u8,
    emit_name: []const u8,
    layout_source: ?[]const u8,
    out: *std.ArrayList(StructDecl),
) !bool {
    var depth_brace: usize = 0;
    var pending_type_params = std.ArrayList([]const u8).empty;
    defer pending_type_params.deinit(allocator);
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        if (tokEq(tokens[i], "{")) {
            depth_brace += 1;
            continue;
        }
        if (tokEq(tokens[i], "}")) {
            if (depth_brace > 0) depth_brace -= 1;
            continue;
        }
        if (depth_brace != 0) continue;
        if (isLineStart(tokens, i) and tokEq(tokens[i], "#")) {
            const line_end = findLineEnd(tokens, i);
            if (line_end == i + 2 and tokens[i + 1].kind == .ident) {
                try pending_type_params.append(allocator, tokens[i + 1].lexeme);
            }
            i = line_end - 1;
            continue;
        }
        if (isUserFuncDeclStart(tokens, i)) {
            pending_type_params.clearRetainingCapacity();
            const close_params = findMatching(tokens, i + 1, "(", ")") catch continue;
            const body = parseFuncBodyShape(tokens, close_params) catch continue;
            i = body.next_idx;
            continue;
        }
        if (!isTopLevelStructDeclStart(tokens, i)) continue;
        const open_brace = i + 1;
        const close_brace = try findMatching(tokens, open_brace, "{", "}");
        if (!std.mem.eql(u8, publicDeclName(tokens[i].lexeme), target_name)) {
            pending_type_params.clearRetainingCapacity();
            i = close_brace;
            continue;
        }
        const type_params = if (pending_type_params.items.len == 0)
            &[_][]const u8{}
        else
            try allocator.dupe([]const u8, pending_type_params.items);
        var type_params_owned = pending_type_params.items.len != 0;
        errdefer if (type_params_owned) allocator.free(type_params);
        var fields = std.ArrayList(StructField).empty;
        var owned_types = std.ArrayList([]const u8).empty;
        errdefer {
            for (owned_types.items) |owned| allocator.free(owned);
            owned_types.deinit(allocator);
            fields.deinit(allocator);
        }

        try append_struct_fields_in_brace_range(allocator, tokens, open_brace, close_brace, &fields, &owned_types);

        try out.append(allocator, .{
            .name = emit_name,
            .type_params = type_params,
            .fields = try fields.toOwnedSlice(allocator),
            .layout_source = layout_source,
            .owned_types = try owned_types.toOwnedSlice(allocator),
            .tokens = tokens,
        });
        type_params_owned = false;
        return true;
    }
    return false;
}

/// Collect struct fields inside `{ … }`. Clamps each field span to `close_brace` so
/// single-line bodies like `{ .id i64 }` do not include trailing `}` / `)` in the type span.
/// Collect struct fields inside `{ … }`. Clamps each field span to `close_brace` so
/// single-line bodies like `{ .id i64 }` do not include trailing `}` / `)` in the type span.
pub fn append_struct_fields_in_brace_range(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    open_brace: usize,
    close_brace: usize,
    fields: *std.ArrayList(StructField),
    owned_types: *std.ArrayList([]const u8),
) !void {
    var field_idx = open_brace + 1;
    while (field_idx < close_brace) {
        // Never scan past the closing brace — single-line `{ .id i64 }` would otherwise
        // treat `} )` as part of the field type and drop the field.
        const line_end = @min(findLineEnd(tokens, field_idx), close_brace);
        const default_idx = findTopLevelToken(tokens, field_idx + 1, line_end, "=");
        const type_end = default_idx orelse line_end;
        if (tokens[field_idx].kind == .ident) {
            if (try parse_struct_field_type_expr(allocator, tokens, field_idx + 1, type_end, owned_types)) |parsed_ty| {
                try fields.append(allocator, .{
                    .name = tokens[field_idx].lexeme,
                    .ty = parsed_ty,
                    .default_start = if (default_idx) |idx| idx + 1 else null,
                    .default_end = line_end,
                });
            }
        }
        field_idx = line_end;
    }
}

pub fn collect_struct_layouts(
    allocator: std.mem.Allocator,
    structs: []const StructDecl,
    out: *std.ArrayList(StructLayout),
) !void {
    var next_type_id: usize = TYPE_ID_FIRST_STRUCT;
    for (structs) |decl| {
        if (decl.layout_source) |source_name| {
            const source_layout = findStructLayout(out.items, source_name) orelse continue;
            try out.append(allocator, .{
                .name = decl.name,
                .type_id = source_layout.type_id,
                .payload_bytes = source_layout.payload_bytes,
                .managed_fields = try clone_managed_fields(allocator, source_layout.managed_fields),
            });
            continue;
        }

        var managed_fields = std.ArrayList(ManagedFieldOffset).empty;
        errdefer managed_fields.deinit(allocator);

        var offset: usize = 0;
        for (decl.fields) |field| {
            const field_align = typePayloadAlignment(field.ty);
            offset = alignUp(offset, field_align);
            if (try field_type_has_managed_layout(allocator, structs, field.ty)) {
                try managed_fields.append(allocator, .{
                    .name = publicDeclName(field.name),
                    .offset = offset,
                });
            }
            offset += typePayloadBytes(field.ty);
        }

        if (managed_fields.items.len == 0) {
            managed_fields.deinit(allocator);
            continue;
        }

        try out.append(allocator, .{
            .name = decl.name,
            .type_id = next_type_id,
            .payload_bytes = alignUp(offset, 4),
            .managed_fields = try managed_fields.toOwnedSlice(allocator),
        });
        next_type_id += 1;
    }
}

pub fn collect_concrete_generic_struct_layouts(
    allocator: std.mem.Allocator,
    structs: []const StructDecl,
    functions: []const FuncDecl,
    out: *std.ArrayList(StructLayout),
) !void {
    var next_type_id = next_struct_layout_type_id(out.items);
    for (functions) |func| {
        if (func.is_generic_template) continue;
        for (func.params) |param| {
            try collect_concrete_generic_struct_layout_from_type(allocator, structs, funcParamAbiType(param), out, &next_type_id);
        }
        for (func.results) |result_ty| {
            try collect_concrete_generic_struct_layout_from_type(allocator, structs, result_ty, out, &next_type_id);
        }
        for (func.result_items) |item| {
            try collect_concrete_generic_struct_layout_from_type(allocator, structs, item.ty, out, &next_type_id);
        }
    }
}

/// Register scheme-A packed `[Tuple<...>]` layouts when any leaf is managed payload.
/// Layout name is the element Tuple type; payload_bytes is packed element width; managed offsets relative to element start.
/// Register scheme-A packed `[Tuple<...>]` layouts when any leaf is managed payload.
/// Layout name is the element Tuple type; payload_bytes is packed element width; managed offsets relative to element start.
pub fn collect_storage_pack_layouts_from_tokens(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    structs: []const StructDecl,
    out: *std.ArrayList(StructLayout),
) !void {
    var owned = std.ArrayList([]const u8).empty;
    defer {
        for (owned.items) |n| allocator.free(n);
        owned.deinit(allocator);
    }
    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (!tokEq(tokens[i], "[")) continue;
        const close = findMatchingInRange(tokens, i, "[", "]", tokens.len) catch continue;
        if (close <= i + 1) continue;
        const parsed = (try parseCodegenTypeExpr(allocator, tokens, i + 1, close, &owned)) orelse continue;
        if (parsed.next_idx != close) continue;
        try ensure_storage_pack_layout_with_structs(allocator, parsed.ty, structs, out);
    }
}

pub fn ensure_storage_pack_layout(
    allocator: std.mem.Allocator,
    elem_ty: []const u8,
    out: *std.ArrayList(StructLayout),
) !void {
    // Pure-scalar struct slots need structs table; managed-only path uses type_name flatten.
    try ensure_storage_pack_layout_with_structs(allocator, elem_ty, &.{}, out);
}

/// When any module binds preopens get-directories, register `[Tuple<Dir,text>]` pack layout.
/// When any module binds preopens get-directories, register `[Tuple<Dir,text>]` pack layout.
pub fn ensure_preopen_dir_tuple_storage_pack_layout(
    allocator: std.mem.Allocator,
    wasi_imports: []const WasiHostImport,
    structs: []const StructDecl,
    out: *std.ArrayList(StructLayout),
) !void {
    var needs = false;
    for (wasi_imports) |import| {
        if (std.mem.eql(u8, import.target, "filesystem/preopens/get-directories")) {
            needs = true;
            break;
        }
    }
    if (!needs) return;
    // Dir shell must be visible so pack expands `.id i64` + text handle (12B).
    if (findStructDecl(structs, "Dir") == null) return;
    try ensure_storage_pack_layout_with_structs(allocator, "Tuple<Dir,text>", structs, out);
}

pub fn ensure_storage_pack_layout_with_structs(
    allocator: std.mem.Allocator,
    elem_ty: []const u8,
    structs: []const StructDecl,
    out: *std.ArrayList(StructLayout),
) !void {
    if (!isTupleTypeName(elem_ty)) return;
    const width = if (structs.len != 0)
        tuplePackWidthWithStructs(elem_ty, structs)
    else
        tupleScalarLeafStorageByteWidth(elem_ty);
    const w = width orelse return;

    var leaf_types = std.ArrayList([]const u8).empty;
    defer leaf_types.deinit(allocator);
    if (structs.len != 0) {
        try appendTupleLeafTypesWithStructs(allocator, elem_ty, structs, &leaf_types);
    } else {
        try appendTupleLeafTypes(allocator, elem_ty, &leaf_types);
    }

    var managed_fields = std.ArrayList(ManagedFieldOffset).empty;
    errdefer managed_fields.deinit(allocator);
    var offset: usize = 0;
    var managed_idx: usize = 0;
    for (leaf_types.items) |leaf_ty| {
        const leaf_bytes = leaf_payload_bytes_for_pack(leaf_ty, structs) orelse return;
        if (is_pack_managed_handle_leaf(leaf_ty, structs)) {
            try managed_fields.append(allocator, .{
                .name = managed_leaf_field_name(managed_idx),
                .offset = offset,
            });
            managed_idx += 1;
        }
        offset += leaf_bytes;
    }
    if (managed_fields.items.len == 0) {
        managed_fields.deinit(allocator);
        return;
    }
    if (find_struct_layout_exact(out.items, elem_ty)) |existing| {
        if (existing.is_storage_pack) {
            managed_fields.deinit(allocator);
            return;
        }
    }

    const owned_name = try allocator.dupe(u8, elem_ty);
    errdefer allocator.free(owned_name);
    try out.append(allocator, .{
        .name = owned_name,
        .type_id = next_struct_layout_type_id(out.items),
        .payload_bytes = w,
        .managed_fields = try managed_fields.toOwnedSlice(allocator),
        .owned_name = true,
        .is_storage_pack = true,
    });
}

pub fn managed_leaf_field_name(idx: usize) []const u8 {
    return switch (idx) {
        0 => "m0",
        1 => "m1",
        2 => "m2",
        3 => "m3",
        4 => "m4",
        5 => "m5",
        6 => "m6",
        7 => "m7",
        else => "mN",
    };
}

pub fn next_struct_layout_type_id(layouts: []const StructLayout) usize {
    var next_type_id: usize = TYPE_ID_FIRST_STRUCT;
    for (layouts) |layout| {
        next_type_id = @max(next_type_id, layout.type_id + 1);
    }
    return next_type_id;
}

pub fn collect_concrete_generic_struct_layout_from_type(
    allocator: std.mem.Allocator,
    structs: []const StructDecl,
    ty: []const u8,
    out: *std.ArrayList(StructLayout),
    next_type_id: *usize,
) !void {
    if (managedPayloadElemTypeFromName(ty)) |elem_ty| {
        try collect_concrete_generic_struct_layout_from_type(allocator, structs, elem_ty, out, next_type_id);
        return;
    }

    const args = genericTypeArgsRange(ty) orelse return;
    const decl = findStructDecl(structs, args.base) orelse return;
    if (decl.type_params.len == 0) return;
    if (find_struct_layout_exact(out.items, ty) != null) return;
    if (find_struct_layout_exact(out.items, args.base) != null) return;

    var owned_types = std.ArrayList([]const u8).empty;
    defer {
        for (owned_types.items) |owned| allocator.free(owned);
        owned_types.deinit(allocator);
    }
    var bindings = std.ArrayList(GenericTypeBinding).empty;
    defer bindings.deinit(allocator);
    if (!try bind_struct_type_args(allocator, decl, ty, &bindings, &owned_types)) return;

    var managed_fields = std.ArrayList(ManagedFieldOffset).empty;
    errdefer managed_fields.deinit(allocator);
    var offset: usize = 0;
    for (decl.fields) |field| {
        const field_ty = try substituteGenericTypeOwned(allocator, field.ty, bindings.items, &owned_types);
        try collect_concrete_generic_struct_layout_from_type(allocator, structs, field_ty, out, next_type_id);

        const field_align = typePayloadAlignment(field_ty);
        offset = alignUp(offset, field_align);
        if (field_concrete_type_has_managed_layout(out.items, field_ty)) {
            try managed_fields.append(allocator, .{
                .name = publicDeclName(field.name),
                .offset = offset,
            });
        }
        offset += typePayloadBytes(field_ty);
    }

    if (managed_fields.items.len == 0) {
        managed_fields.deinit(allocator);
        return;
    }

    const owned_name = try allocator.dupe(u8, ty);
    errdefer allocator.free(owned_name);
    try out.append(allocator, .{
        .name = owned_name,
        .type_id = next_type_id.*,
        .payload_bytes = alignUp(offset, 4),
        .managed_fields = try managed_fields.toOwnedSlice(allocator),
        .owned_name = true,
    });
    next_type_id.* += 1;
}

pub fn field_concrete_type_has_managed_layout(layouts: []const StructLayout, ty: []const u8) bool {
    if (isManagedPayloadType(ty)) return true;
    return findStructLayout(layouts, ty) != null;
}

pub fn field_type_has_managed_layout(allocator: std.mem.Allocator, structs: []const StructDecl, ty: []const u8) !bool {
    if (isManagedPayloadType(ty)) return true;
    var stack = std.ArrayList([]const u8).empty;
    defer stack.deinit(allocator);
    return try struct_type_has_managed_layout(allocator, structs, ty, &stack);
}

pub fn struct_type_has_managed_layout(
    allocator: std.mem.Allocator,
    structs: []const StructDecl,
    ty: []const u8,
    stack: *std.ArrayList([]const u8),
) !bool {
    const name = typeBaseName(ty);
    if (has_type_name(stack.items, name)) return true;
    const decl = findStructDecl(structs, name) orelse return false;

    try stack.append(allocator, name);
    defer _ = stack.pop();

    for (decl.fields) |field| {
        if (isManagedPayloadType(field.ty)) return true;
        if (try struct_type_has_managed_layout(allocator, structs, field.ty, stack)) return true;
    }
    return false;
}

pub fn has_type_name(names: []const []const u8, needle: []const u8) bool {
    for (names) |name| {
        if (std.mem.eql(u8, name, needle)) return true;
    }
    return false;
}

pub fn clone_managed_fields(
    allocator: std.mem.Allocator,
    fields: []const ManagedFieldOffset,
) ![]const ManagedFieldOffset {
    const out = try allocator.alloc(ManagedFieldOffset, fields.len);
    @memcpy(out, fields);
    return out;
}

pub fn parse_struct_field_type_expr(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    owned_types: *std.ArrayList([]const u8),
) !?[]const u8 {
    if (start_idx >= end_idx) return null;
    if (hasTopLevelToken(tokens, start_idx, end_idx, "|")) {
        const ty = try compactTokenText(allocator, tokens, start_idx, end_idx);
        errdefer allocator.free(ty);
        try owned_types.append(allocator, ty);
        return ty;
    }
    const parsed = (try parseCodegenTypeExpr(allocator, tokens, start_idx, end_idx, owned_types)) orelse return null;
    if (parsed.next_idx != end_idx) return null;
    return parsed.ty;
}

pub fn bind_struct_type_args(
    allocator: std.mem.Allocator,
    decl: StructDecl,
    concrete_ty: []const u8,
    bindings: *std.ArrayList(GenericTypeBinding),
    owned_types: *std.ArrayList([]const u8),
) !bool {
    if (decl.type_params.len == 0) return true;
    const args = genericTypeArgsRange(concrete_ty) orelse return false;
    if (!std.mem.eql(u8, args.base, decl.name)) return false;

    var arg_start: usize = 0;
    var param_idx: usize = 0;
    while (arg_start < args.args.len) {
        if (param_idx >= decl.type_params.len) return false;
        const arg_end = findTopLevelTypeSeparatorFrom(args.args, arg_start, ',') orelse args.args.len;
        if (arg_start == arg_end) return false;
        if (!try bindGenericType(allocator, bindings, decl.type_params[param_idx], args.args[arg_start..arg_end], owned_types)) return false;
        param_idx += 1;
        arg_start = arg_end;
        if (arg_start < args.args.len) arg_start += 1;
    }
    return param_idx == decl.type_params.len;
}

pub fn find_struct_layout_exact(layouts: []const StructLayout, name: []const u8) ?StructLayout {
    for (layouts) |layout| {
        if (std.mem.eql(u8, layout.name, name)) return layout;
    }
    return null;
}

pub fn is_pack_managed_handle_leaf(ty: []const u8, structs: []const StructDecl) bool {
    if (type_util.isManagedPayloadType(ty)) return true;
    const decl = findStructDecl(structs, ty) orelse return false;
    return structDeclHasManagedField(decl, structs);
}

/// Terminal leaf storeable in scheme-A pack (scalar, managed payload, or managed-struct handle).
/// Terminal leaf storeable in scheme-A pack (scalar, managed payload, or managed-struct handle).
pub fn leaf_payload_bytes_for_pack(leaf_ty: []const u8, structs: []const StructDecl) ?usize {
    if (type_util.isTuplePackableLeafType(leaf_ty)) return typePayloadBytes(leaf_ty);
    if (is_pack_managed_handle_leaf(leaf_ty, structs)) return 4;
    return null;
}

pub fn parse_type_union_layout_from_name(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    ty: []const u8,
    structs: []const StructDecl,
    struct_layouts: []const StructLayout,
    owned_types: *std.ArrayList([]const u8),
) !?UnionLayout {
    if (findTopLevelTypeSeparator(ty, '|') == null) return null;
    var branches = std.ArrayList(UnionBranch).empty;
    errdefer branches.deinit(allocator);
    var payload_tys = std.ArrayList([]const u8).empty;
    errdefer payload_tys.deinit(allocator);

    var next_non_nil_tag: usize = 1;
    var branch_start: usize = 0;
    while (branch_start < ty.len) {
        const branch_end = findTopLevelTypeSeparatorFrom(ty, branch_start, '|') orelse ty.len;
        if (branch_end == branch_start) return error.NoMatchingCall;
        const branch_ty = ty[branch_start..branch_end];
        const payload_start = payload_tys.items.len;
        if (std.mem.eql(u8, branch_ty, "nil")) {
            try branches.append(allocator, .{
                .ty = "nil",
                .tag = 0,
                .payload_start = payload_start,
                .payload_len = 0,
            });
        } else {
            try appendUnionBranchPayloadTypes(allocator, tokens, branch_ty, structs, struct_layouts, &payload_tys);
            try branches.append(allocator, .{
                .ty = branch_ty,
                .tag = next_non_nil_tag,
                .payload_start = payload_start,
                .payload_len = payload_tys.items.len - payload_start,
            });
            next_non_nil_tag += 1;
        }
        branch_start = branch_end + 1;
    }

    if (branches.items.len < 2) return null;
    const source_ty = try allocator.dupe(u8, ty);
    errdefer allocator.free(source_ty);
    try owned_types.append(allocator, source_ty);
    return .{
        .source_ty = source_ty,
        .branches = try branches.toOwnedSlice(allocator),
        .payload_tys = try payload_tys.toOwnedSlice(allocator),
    };
}
