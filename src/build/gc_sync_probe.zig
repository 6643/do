//! Test-only executable wrapper for the non-CLI synchronous GC emitter.
const std = @import("std");
const codegen_gc_sync = @import("codegen_gc_sync.zig");
const codegen_collect_functions = @import("codegen_collect_functions.zig");
const codegen_collect_declarations = @import("codegen_collect_declarations.zig");
const codegen_collect_structs = @import("codegen_collect_structs.zig");
const codegen_model = @import("codegen_model.zig");
const codegen_gc_layout = @import("codegen_gc_layout.zig");
const codegen_names = @import("codegen_names.zig");
const type_name = @import("type_name.zig");
const imports = @import("imports.zig");
const codegen_tokens = @import("codegen_tokens.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

const FuncDecl = codegen_model.FuncDecl;
const StructDecl = codegen_model.StructDecl;
const StructLayout = codegen_model.StructLayout;
const PayloadEnumDecl = codegen_model.PayloadEnumDecl;
const public_decl_name = codegen_names.public_decl_name;
const find_arg_end = codegen_tokens.find_arg_end;
const find_matching_in_range = codegen_tokens.find_matching_in_range;
const tok_eq = codegen_tokens.tok_eq;

const ManagedStructPayloadProbe = struct {
    function_name: []const u8,
    struct_name: []const u8,
    managed_field_name: []const u8,
    scalar_field_name: []const u8,
    managed_field_first: bool,
    managed_field_type: []const u8,
    scalar_field_type: []const u8,
};

const ManagedStructCallPayloadProbe = struct {
    function_name: []const u8,
    producer_name: []const u8,
    struct_name: []const u8,
    managed_field_name: []const u8,
    scalar_field_name: []const u8,
    managed_field_first: bool,
};

const ManagedStructCallTextProbe = struct {
    function_name: []const u8,
    producer_name: []const u8,
    struct_name: []const u8,
    managed_field_name: []const u8,
    scalar_field_name: []const u8,
    managed_field_first: bool,
};

const ManagedScalarArrayFieldProbe = struct {
    function_name: []const u8,
    struct_name: []const u8,
    managed_field_name: []const u8,
    scalar_field_name: []const u8,
    managed_field_first: bool,
    managed_field_type: []const u8,
    managed_array_name: []const u8,
};

const NestedManagedStructProbe = struct {
    function_name: []const u8,
    outer_name: []const u8,
    outer_child_field_name: []const u8,
    outer_scalar_field_name: []const u8,
    outer_child_first: bool,
    inner_name: []const u8,
    inner_payload_field_name: []const u8,
};

const NestedManagedScalarFieldProbe = struct {
    function_name: []const u8,
    outer_name: []const u8,
    outer_child_field_name: []const u8,
    outer_scalar_field_name: []const u8,
    outer_child_first: bool,
    inner_name: []const u8,
    inner_scalar_field_name: []const u8,
    inner_payload_field_name: []const u8,
};

const TwoLevelNestedManagedScalarFieldProbe = struct {
    function_name: []const u8,
    outer_name: []const u8,
    outer_child_field_name: []const u8,
    outer_scalar_field_name: []const u8,
    outer_child_first: bool,
    middle_name: []const u8,
    middle_child_field_name: []const u8,
    middle_scalar_field_name: []const u8,
    middle_child_first: bool,
    inner_name: []const u8,
    inner_scalar_field_name: []const u8,
    inner_payload_field_name: []const u8,
    inner_payload_first: bool,
};

const ThreeLevelNestedManagedScalarFieldProbe = struct {
    function_name: []const u8,
    outer_name: []const u8,
    outer_child_field_name: []const u8,
    outer_scalar_field_name: []const u8,
    outer_child_first: bool,
    middle_name: []const u8,
    middle_child_field_name: []const u8,
    middle_scalar_field_name: []const u8,
    middle_child_first: bool,
    inner_name: []const u8,
    inner_child_field_name: []const u8,
    inner_scalar_field_name: []const u8,
    inner_child_first: bool,
    leaf_name: []const u8,
    leaf_scalar_field_name: []const u8,
    leaf_payload_field_name: []const u8,
    leaf_scalar_first: bool,
};

const ManagedTupleTextBytesProbe = struct {
    function_name: []const u8,
};

const PayloadUnionProbe = struct {
    function_name: []const u8,
    union_name: []const u8,
    unit_case: []const u8,
    managed_case: []const u8,
    unit_tag: u32,
    managed_tag: u32,
};

const ManagedTextBranchProbe = struct {
    function_name: []const u8,
};

const ManagedTextIdentityProbe = struct {
    function_name: []const u8,
    parameter_name: []const u8,
};

const U32ListLiteralProbe = struct {
    function_name: []const u8,
};

const U32ListUpdateProbe = struct {
    function_name: []const u8,
};

const BoolListUpdateProbe = struct {
    function_name: []const u8,
};

const I16ListLiteralProbe = struct {
    function_name: []const u8,
};

const I16ListUpdateProbe = struct {
    function_name: []const u8,
};

const I32ListLiteralProbe = struct {
    function_name: []const u8,
};

const I32ListUpdateProbe = struct {
    function_name: []const u8,
};

const I64ListLiteralProbe = struct {
    function_name: []const u8,
};

const I64ListUpdateProbe = struct {
    function_name: []const u8,
};

const ScalarListProbe = struct {
    function_name: []const u8,
    elem_ty: []const u8,
    list_ty: []const u8,
    array_name: []const u8,
};

const ScalarListPutProbe = struct {
    function_name: []const u8,
    elem_ty: []const u8,
    array_name: []const u8,
};

const FloatListLiteralProbe = struct {
    function_name: []const u8,
    elem_ty: []const u8,
    array_name: []const u8,
};

const FloatListUpdateProbe = struct {
    function_name: []const u8,
    elem_ty: []const u8,
    array_name: []const u8,
};

const ManagedStructListProbe = struct {
    function_name: []const u8,
    struct_name: []const u8,
    managed_field_name: []const u8,
    scalar_field_name: []const u8,
};

const TextListProbe = struct {
    function_name: []const u8,
};

const TextListPutProbe = struct {
    function_name: []const u8,
};

const NestedByteListProbe = struct {
    function_name: []const u8,
};

const NestedByteListPutProbe = struct {
    function_name: []const u8,
};

const ProbeCallShape = union(enum) {
    byte_list_literal,
    byte_list_put,
    fixed_list_update,
    parameterized_list_update,
    managed_struct_payload_update: ManagedStructPayloadProbe,
    managed_struct_call_payload_update: ManagedStructCallPayloadProbe,
    managed_struct_call_text_update: ManagedStructCallTextProbe,
    managed_scalar_array_field_update: ManagedScalarArrayFieldProbe,
    nested_managed_struct_update: NestedManagedStructProbe,
    nested_managed_scalar_field_update: NestedManagedScalarFieldProbe,
    two_level_nested_managed_scalar_field_update: TwoLevelNestedManagedScalarFieldProbe,
    three_level_nested_managed_scalar_field_update: ThreeLevelNestedManagedScalarFieldProbe,
    managed_tuple_text_bytes_update: ManagedTupleTextBytesProbe,
    payload_union_update: PayloadUnionProbe,
    managed_text_branch: ManagedTextBranchProbe,
    managed_text_identity: ManagedTextIdentityProbe,
    managed_text_call_identity: ManagedTextIdentityProbe,
    u32_list_literal: U32ListLiteralProbe,
    u32_list_update: U32ListUpdateProbe,
    bool_list_update: BoolListUpdateProbe,
    i16_list_literal: I16ListLiteralProbe,
    i16_list_update: I16ListUpdateProbe,
    i32_list_literal: I32ListLiteralProbe,
    i32_list_update: I32ListUpdateProbe,
    i64_list_literal: I64ListLiteralProbe,
    i64_list_update: I64ListUpdateProbe,
    scalar_list_literal: ScalarListProbe,
    scalar_list_update: ScalarListProbe,
    scalar_list_put: ScalarListPutProbe,
    float_list_literal: FloatListLiteralProbe,
    float_list_update: FloatListUpdateProbe,
    managed_struct_list_literal: ManagedStructListProbe,
    managed_struct_list_put: ManagedStructListProbe,
    text_list_literal: TextListProbe,
    text_list_put: TextListPutProbe,
    nested_byte_list_literal: NestedByteListProbe,
    nested_byte_list_put: NestedByteListPutProbe,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 4) return error.InvalidGcSyncProbeArgs;
    if (!is_wat_identifier(args[3])) return error.InvalidGcSyncProbeFunction;

    const source = try std.Io.Dir.cwd().readFileAlloc(io, args[1], allocator, .limited(16 * 1024 * 1024));
    defer allocator.free(source);
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);
    var program = try parser.parse_program(allocator, tokens, source.len);
    defer program.deinit(allocator);

    var module_graph = try imports.check_and_load(io, allocator, args[1], tokens, "");
    defer module_graph.deinit();

    var structs = std.ArrayList(StructDecl).empty;
    defer {
        codegen_model.free_struct_decls(allocator, structs.items);
        structs.deinit(allocator);
    }
    try codegen_collect_structs.collect_struct_decls(allocator, tokens, &structs);

    var payload_enums = std.ArrayList(PayloadEnumDecl).empty;
    defer {
        codegen_model.free_payload_enum_decls(allocator, payload_enums.items);
        payload_enums.deinit(allocator);
    }
    try codegen_collect_declarations.collect_payload_enum_decls(allocator, tokens, &payload_enums);

    var struct_layouts = std.ArrayList(StructLayout).empty;
    defer {
        codegen_model.free_struct_layouts(allocator, struct_layouts.items);
        struct_layouts.deinit(allocator);
    }
    try codegen_collect_structs.collect_struct_layouts(allocator, structs.items, &struct_layouts);

    var functions = std.ArrayList(FuncDecl).empty;
    defer {
        codegen_model.free_func_decls(allocator, functions.items);
        functions.deinit(allocator);
    }
    try codegen_collect_functions.collect_gc_sync_func_decls(allocator, tokens, structs.items, struct_layouts.items, payload_enums.items, null, &functions);

    const call_shape = try find_probe_call_shape(functions.items, structs.items, payload_enums.items, args[3]);
    const wat = try codegen_gc_sync.emit_gc_wat_for_supported_program(allocator, program, tokens, &module_graph);
    defer allocator.free(wat);

    var probe_wat = std.ArrayList(u8).empty;
    defer probe_wat.deinit(allocator);
    try append_byte_list_probe(allocator, &probe_wat, wat, args[3], call_shape);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = args[2], .data = probe_wat.items });
}

fn find_probe_call_shape(functions: []const FuncDecl, structs: []const StructDecl, payload_enums: []const PayloadEnumDecl, function_name: []const u8) !ProbeCallShape {
    for (functions) |func| {
        const matches_internal = std.mem.eql(u8, func.name, function_name);
        const matches_public = std.mem.eql(u8, public_decl_name(func.name), public_decl_name(function_name));
        const matches_source = std.mem.eql(u8, func.source_name, function_name) or
            std.mem.eql(u8, public_decl_name(func.source_name), public_decl_name(function_name));
        if (!matches_internal and !matches_public and !matches_source) continue;
        return probe_call_shape(func, structs, payload_enums);
    }
    return error.GcSyncProbeFunctionNotFound;
}

fn probe_call_shape(func: FuncDecl, structs: []const StructDecl, payload_enums: []const PayloadEnumDecl) !ProbeCallShape {
    if (func.results.len != 1) return error.UnsupportedGcSyncProbeSignature;
    if (func.params.len == 0 and std.mem.eql(u8, func.results[0], "[u8]") and is_byte_list_literal_body(func)) return .byte_list_literal;
    if (func.params.len == 1 and
        std.mem.eql(u8, func.params[0].ty, "[u8]") and
        std.mem.eql(u8, func.results[0], "[u8]") and is_fixed_list_update_body(func)) return .fixed_list_update;
    if (func.params.len == 2 and
        std.mem.eql(u8, func.params[0].ty, "[u8]") and
        std.mem.eql(u8, func.params[1].ty, "u8") and
        std.mem.eql(u8, func.results[0], "[u8]") and is_byte_list_put_body(func)) return .byte_list_put;
    if (func.params.len == 3 and
        std.mem.eql(u8, func.params[0].ty, "[u8]") and
        std.mem.eql(u8, func.params[1].ty, "usize") and
        std.mem.eql(u8, func.params[2].ty, "u8") and
        std.mem.eql(u8, func.results[0], "[u8]") and is_parameterized_list_update_body(func)) return .parameterized_list_update;
    if (func.params.len == 2) {
        if (try find_managed_scalar_array_field_probe(func, structs)) |probe| {
            return .{ .managed_scalar_array_field_update = probe };
        }
        if (try find_managed_struct_payload_probe(func, structs)) |probe| {
            return .{ .managed_struct_payload_update = probe };
        }
        if (try find_nested_managed_struct_probe(func, structs)) |probe| {
            return .{ .nested_managed_struct_update = probe };
        }
    }
    if (try find_managed_struct_call_payload_probe(func, structs)) |probe| {
        return .{ .managed_struct_call_payload_update = probe };
    }
    if (try find_managed_struct_call_text_probe(func, structs)) |probe| {
        return .{ .managed_struct_call_text_update = probe };
    }
    if (try find_three_level_nested_managed_scalar_field_probe(func, structs)) |probe| {
        return .{ .three_level_nested_managed_scalar_field_update = probe };
    }
    if (try find_two_level_nested_managed_scalar_field_probe(func, structs)) |probe| {
        return .{ .two_level_nested_managed_scalar_field_update = probe };
    }
    if (try find_nested_managed_scalar_field_probe(func, structs)) |probe| {
        return .{ .nested_managed_scalar_field_update = probe };
    }
    if (find_managed_tuple_text_bytes_probe(func)) |probe| return .{ .managed_tuple_text_bytes_update = probe };
    if (try find_payload_union_probe(func, payload_enums)) |probe| return .{ .payload_union_update = probe };
    if (find_managed_text_branch_probe(func)) |probe| return .{ .managed_text_branch = probe };
    if (find_managed_text_identity_probe(func)) |probe| return .{ .managed_text_identity = probe };
    if (find_managed_text_call_identity_probe(func)) |probe| return .{ .managed_text_call_identity = probe };
    if (find_u32_list_literal_probe(func)) |probe| return .{ .u32_list_literal = probe };
    if (find_u32_list_update_probe(func)) |probe| return .{ .u32_list_update = probe };
    if (find_bool_list_update_probe(func)) |probe| return .{ .bool_list_update = probe };
    if (find_i16_list_literal_probe(func)) |probe| return .{ .i16_list_literal = probe };
    if (find_i16_list_update_probe(func)) |probe| return .{ .i16_list_update = probe };
    if (find_i32_list_literal_probe(func)) |probe| return .{ .i32_list_literal = probe };
    if (find_i32_list_update_probe(func)) |probe| return .{ .i32_list_update = probe };
    if (find_i64_list_literal_probe(func)) |probe| return .{ .i64_list_literal = probe };
    if (find_i64_list_update_probe(func)) |probe| return .{ .i64_list_update = probe };
    if (find_scalar_list_literal_probe(func)) |probe| return .{ .scalar_list_literal = probe };
    if (find_scalar_list_update_probe(func)) |probe| return .{ .scalar_list_update = probe };
    if (find_scalar_list_put_probe(func)) |probe| return .{ .scalar_list_put = probe };
    if (find_float_list_literal_probe(func)) |probe| return .{ .float_list_literal = probe };
    if (find_float_list_update_probe(func)) |probe| return .{ .float_list_update = probe };
    if (try find_managed_struct_list_put_probe(func, structs)) |probe| return .{ .managed_struct_list_put = probe };
    if (try find_managed_struct_list_probe(func, structs)) |probe| return .{ .managed_struct_list_literal = probe };
    if (find_text_list_put_probe(func)) |probe| return .{ .text_list_put = probe };
    if (find_nested_byte_list_put_probe(func)) |probe| return .{ .nested_byte_list_put = probe };
    if (find_text_list_probe(func)) |probe| return .{ .text_list_literal = probe };
    if (find_nested_byte_list_probe(func)) |probe| return .{ .nested_byte_list_literal = probe };
    return error.UnsupportedGcSyncProbeSignature;
}

fn find_text_list_probe(func: FuncDecl) ?TextListProbe {
    if (func.params.len != 0 or func.results.len != 1 or !std.mem.eql(u8, func.results[0], "[text]")) return null;
    if (!is_managed_list_collection_body(func)) return null;
    return .{ .function_name = func.name };
}

fn find_text_list_put_probe(func: FuncDecl) ?TextListPutProbe {
    if (func.params.len != 2 or func.results.len != 1 or
        !std.mem.eql(u8, func.params[0].ty, "[text]") or
        !std.mem.eql(u8, func.params[1].ty, "text") or
        !std.mem.eql(u8, func.results[0], "[text]")) return null;
    if (!is_scalar_list_put_body(func)) return null;
    return .{ .function_name = func.name };
}

fn find_nested_byte_list_probe(func: FuncDecl) ?NestedByteListProbe {
    if (func.params.len != 0 or func.results.len != 1 or !std.mem.eql(u8, func.results[0], "[[u8]]")) return null;
    var has_nested_literal = false;
    var has_len = false;
    var has_get = false;
    var has_loop = false;
    var index = func.body_start;
    while (index + 1 < func.body_end) : (index += 1) {
        if (tok_eq(func.tokens[index], "[") and index + 4 < func.body_end and
            tok_eq(func.tokens[index + 1], "[") and tok_eq(func.tokens[index + 2], "u8") and
            tok_eq(func.tokens[index + 3], "]") and tok_eq(func.tokens[index + 4], "]")) has_nested_literal = true;
        if (tok_eq(func.tokens[index], "@") and index + 1 < func.body_end and tok_eq(func.tokens[index + 1], "len")) has_len = true;
        if (tok_eq(func.tokens[index], "@") and index + 1 < func.body_end and tok_eq(func.tokens[index + 1], "get")) has_get = true;
        if (tok_eq(func.tokens[index], "loop")) has_loop = true;
    }
    if (!has_nested_literal or !has_len or !has_get or !has_loop) return null;
    return .{ .function_name = func.name };
}

fn find_nested_byte_list_put_probe(func: FuncDecl) ?NestedByteListPutProbe {
    if (func.params.len != 2 or func.results.len != 1 or
        !std.mem.eql(u8, func.params[0].ty, "[[u8]]") or
        !std.mem.eql(u8, func.params[1].ty, "[u8]") or
        !std.mem.eql(u8, func.results[0], "[[u8]]")) return null;
    if (!is_scalar_list_put_body(func)) return null;
    return .{ .function_name = func.name };
}

fn find_managed_struct_list_probe(func: FuncDecl, structs: []const StructDecl) !?ManagedStructListProbe {
    if (func.params.len != 0 or func.results.len != 1) return null;
    const elem_ty = type_name.storage_elem_type_from_name(func.results[0]) orelse return null;
    var struct_decl: ?StructDecl = null;
    for (structs) |decl| {
        if (std.mem.eql(u8, decl.name, elem_ty)) {
            struct_decl = decl;
            break;
        }
    }
    const decl = struct_decl orelse return null;
    var managed_field_name: ?[]const u8 = null;
    var scalar_field_name: ?[]const u8 = null;
    for (decl.fields) |field| {
        if (std.mem.eql(u8, field.ty, "[u8]")) {
            if (managed_field_name != null) return null;
            managed_field_name = field.name;
        } else if (std.mem.eql(u8, field.ty, "i32")) {
            if (scalar_field_name != null) return null;
            scalar_field_name = field.name;
        } else return null;
    }
    const managed_name = managed_field_name orelse return null;
    const scalar_name = scalar_field_name orelse return null;
    if (!is_single_managed_struct_list_literal_body(func)) return null;
    return .{
        .function_name = func.name,
        .struct_name = elem_ty,
        .managed_field_name = managed_name,
        .scalar_field_name = scalar_name,
    };
}

fn find_managed_struct_list_put_probe(func: FuncDecl, structs: []const StructDecl) !?ManagedStructListProbe {
    if (func.params.len != 2 or func.results.len != 1) return null;
    const elem_ty = type_name.storage_elem_type_from_name(func.results[0]) orelse return null;
    if (!std.mem.eql(u8, func.params[0].ty, func.results[0]) or !std.mem.eql(u8, func.params[1].ty, elem_ty)) return null;
    var struct_decl: ?StructDecl = null;
    for (structs) |decl| {
        if (std.mem.eql(u8, decl.name, elem_ty)) {
            struct_decl = decl;
            break;
        }
    }
    const decl = struct_decl orelse return null;
    var managed_field_name: ?[]const u8 = null;
    var scalar_field_name: ?[]const u8 = null;
    for (decl.fields) |field| {
        if (std.mem.eql(u8, field.ty, "[u8]")) {
            if (managed_field_name != null) return null;
            managed_field_name = field.name;
        } else if (std.mem.eql(u8, field.ty, "i32")) {
            if (scalar_field_name != null) return null;
            scalar_field_name = field.name;
        } else return null;
    }
    const managed_name = managed_field_name orelse return null;
    const scalar_name = scalar_field_name orelse return null;
    if (!is_scalar_list_put_body(func)) return null;
    return .{
        .function_name = func.name,
        .struct_name = elem_ty,
        .managed_field_name = managed_name,
        .scalar_field_name = scalar_name,
    };
}

fn find_managed_text_branch_probe(func: FuncDecl) ?ManagedTextBranchProbe {
    if (func.params.len != 3 or func.results.len != 1) return null;
    if (!std.mem.eql(u8, func.params[0].ty, "bool") or
        !std.mem.eql(u8, func.params[1].ty, "text") or
        !std.mem.eql(u8, func.params[2].ty, "text") or
        !std.mem.eql(u8, func.results[0], "text")) return null;
    const tokens = func.tokens;
    if (func.body_start >= func.body_end or !tok_eq(tokens[func.body_start], "if")) return null;
    const open_idx = codegen_tokens.find_top_level_block_open(tokens, func.body_start + 1, func.body_end) orelse return null;
    const close_idx = find_matching_in_range(tokens, open_idx, "{", "}", func.body_end) catch return null;
    if (close_idx + 1 >= func.body_end or !tok_eq(tokens[close_idx + 1], "return")) return null;
    return .{ .function_name = func.name };
}

fn find_managed_text_identity_probe(func: FuncDecl) ?ManagedTextIdentityProbe {
    if (func.params.len != 1 or func.results.len != 1) return null;
    if (!std.mem.eql(u8, func.params[0].ty, "text") or !std.mem.eql(u8, func.results[0], "text")) return null;
    const range = body_expr_range(func) orelse return null;
    if (range.start + 1 != range.end or func.tokens[range.start].kind != .ident or
        !std.mem.eql(u8, func.tokens[range.start].lexeme, func.params[0].name)) return null;
    return .{ .function_name = func.name, .parameter_name = func.params[0].name };
}

fn find_managed_text_call_identity_probe(func: FuncDecl) ?ManagedTextIdentityProbe {
    if (func.params.len != 1 or func.results.len != 1 or
        !std.mem.eql(u8, func.params[0].ty, "text") or !std.mem.eql(u8, func.results[0], "text")) return null;
    const range = body_expr_range(func) orelse return null;
    if (range.start + 3 >= range.end or func.tokens[range.start].kind != .ident or
        !tok_eq(func.tokens[range.start + 1], "(")) return null;
    const close_idx = find_matching_in_range(func.tokens, range.start + 1, "(", ")", range.end) catch return null;
    if (close_idx + 1 != range.end) return null;
    const arg_end = find_arg_end(func.tokens, range.start + 2, close_idx);
    if (arg_end != close_idx or range.start + 3 != close_idx) return null;
    if (func.tokens[range.start + 2].kind != .ident or
        !std.mem.eql(u8, func.tokens[range.start + 2].lexeme, func.params[0].name)) return null;
    return .{ .function_name = func.name, .parameter_name = func.params[0].name };
}

fn find_u32_list_literal_probe(func: FuncDecl) ?U32ListLiteralProbe {
    if (func.params.len != 0 or func.results.len != 1 or !std.mem.eql(u8, func.results[0], "[u32]")) return null;
    if (!is_byte_list_literal_body(func)) return null;
    return .{ .function_name = func.name };
}

fn find_u32_list_update_probe(func: FuncDecl) ?U32ListUpdateProbe {
    if (func.params.len != 1 or func.results.len != 1 or
        !std.mem.eql(u8, func.params[0].ty, "[u32]") or !std.mem.eql(u8, func.results[0], "[u32]")) return null;
    if (!is_set_call_body(func, func.params[0].name, "1", "65")) return null;
    return .{ .function_name = func.name };
}

fn find_bool_list_update_probe(func: FuncDecl) ?BoolListUpdateProbe {
    if (func.params.len != 1 or func.results.len != 1 or
        !std.mem.eql(u8, func.params[0].ty, "[bool]") or !std.mem.eql(u8, func.results[0], "[bool]")) return null;
    if (!is_set_call_body(func, func.params[0].name, "1", "true")) return null;
    return .{ .function_name = func.name };
}

fn find_i16_list_literal_probe(func: FuncDecl) ?I16ListLiteralProbe {
    if (func.params.len != 0 or func.results.len != 1 or !std.mem.eql(u8, func.results[0], "[i16]")) return null;
    if (!is_byte_list_literal_body(func)) return null;
    return .{ .function_name = func.name };
}

fn find_i16_list_update_probe(func: FuncDecl) ?I16ListUpdateProbe {
    if (func.params.len != 1 or func.results.len != 1 or
        !std.mem.eql(u8, func.params[0].ty, "[i16]") or !std.mem.eql(u8, func.results[0], "[i16]")) return null;
    if (!is_set_call_body(func, func.params[0].name, "1", "65")) return null;
    return .{ .function_name = func.name };
}

fn find_i32_list_literal_probe(func: FuncDecl) ?I32ListLiteralProbe {
    if (func.params.len != 0 or func.results.len != 1 or !std.mem.eql(u8, func.results[0], "[i32]")) return null;
    if (!is_byte_list_literal_body(func)) return null;
    return .{ .function_name = func.name };
}

fn find_i32_list_update_probe(func: FuncDecl) ?I32ListUpdateProbe {
    if (func.params.len != 1 or func.results.len != 1 or
        !std.mem.eql(u8, func.params[0].ty, "[i32]") or !std.mem.eql(u8, func.results[0], "[i32]")) return null;
    if (!is_set_call_body(func, func.params[0].name, "1", "65")) return null;
    return .{ .function_name = func.name };
}

fn find_i64_list_literal_probe(func: FuncDecl) ?I64ListLiteralProbe {
    if (func.params.len != 0 or func.results.len != 1 or !std.mem.eql(u8, func.results[0], "[i64]")) return null;
    if (!is_byte_list_literal_body(func)) return null;
    return .{ .function_name = func.name };
}

fn find_i64_list_update_probe(func: FuncDecl) ?I64ListUpdateProbe {
    if (func.params.len != 1 or func.results.len != 1 or
        !std.mem.eql(u8, func.params[0].ty, "[i64]") or !std.mem.eql(u8, func.results[0], "[i64]")) return null;
    if (!is_set_call_body(func, func.params[0].name, "1", "65")) return null;
    return .{ .function_name = func.name };
}

fn find_scalar_list_literal_probe(func: FuncDecl) ?ScalarListProbe {
    if (func.params.len != 0 or func.results.len != 1 or !is_byte_list_literal_body(func)) return null;
    const spec = codegen_gc_layout.scalar_array_spec_for_type(func.results[0]) orelse return null;
    if (std.mem.eql(u8, spec.list_ty, "[bool]") or
        std.mem.eql(u8, spec.list_ty, "[i16]") or
        std.mem.eql(u8, spec.list_ty, "[i32]") or
        std.mem.eql(u8, spec.list_ty, "[i64]") or
        std.mem.eql(u8, spec.list_ty, "[u32]") or
        std.mem.eql(u8, spec.list_ty, "[f32]") or
        std.mem.eql(u8, spec.list_ty, "[f64]")) return null;
    return .{ .function_name = func.name, .elem_ty = spec.elem_ty, .list_ty = spec.list_ty, .array_name = spec.array_name };
}

fn find_scalar_list_update_probe(func: FuncDecl) ?ScalarListProbe {
    if (func.params.len != 1 or func.results.len != 1 or
        !std.mem.eql(u8, func.params[0].ty, func.results[0]) or
        !is_set_call_body(func, func.params[0].name, "1", "65")) return null;
    const spec = codegen_gc_layout.scalar_array_spec_for_type(func.results[0]) orelse return null;
    if (std.mem.eql(u8, spec.list_ty, "[bool]") or
        std.mem.eql(u8, spec.list_ty, "[i16]") or
        std.mem.eql(u8, spec.list_ty, "[i32]") or
        std.mem.eql(u8, spec.list_ty, "[i64]") or
        std.mem.eql(u8, spec.list_ty, "[u32]") or
        std.mem.eql(u8, spec.list_ty, "[f32]") or
        std.mem.eql(u8, spec.list_ty, "[f64]")) return null;
    return .{ .function_name = func.name, .elem_ty = spec.elem_ty, .list_ty = spec.list_ty, .array_name = spec.array_name };
}

fn find_scalar_list_put_probe(func: FuncDecl) ?ScalarListPutProbe {
    if (func.params.len != 2 or func.results.len != 1 or
        !std.mem.eql(u8, func.params[0].ty, func.results[0]) or
        !is_scalar_list_put_body(func)) return null;
    const spec = codegen_gc_layout.scalar_array_spec_for_type(func.results[0]) orelse return null;
    if (!std.mem.eql(u8, func.params[1].ty, spec.elem_ty)) return null;
    return .{ .function_name = func.name, .elem_ty = spec.elem_ty, .array_name = spec.array_name };
}

fn find_float_list_literal_probe(func: FuncDecl) ?FloatListLiteralProbe {
    if (func.params.len != 0 or func.results.len != 1 or !is_byte_list_literal_body(func)) return null;
    if (std.mem.eql(u8, func.results[0], "[f32]")) {
        return .{ .function_name = func.name, .elem_ty = "f32", .array_name = "$do_f32" };
    }
    if (std.mem.eql(u8, func.results[0], "[f64]")) {
        return .{ .function_name = func.name, .elem_ty = "f64", .array_name = "$do_f64" };
    }
    return null;
}

fn find_float_list_update_probe(func: FuncDecl) ?FloatListUpdateProbe {
    if (func.params.len != 1 or func.results.len != 1 or !is_set_call_body(func, func.params[0].name, "1", "3.5")) return null;
    if (std.mem.eql(u8, func.params[0].ty, "[f32]") and std.mem.eql(u8, func.results[0], "[f32]")) {
        return .{ .function_name = func.name, .elem_ty = "f32", .array_name = "$do_f32" };
    }
    if (std.mem.eql(u8, func.params[0].ty, "[f64]") and std.mem.eql(u8, func.results[0], "[f64]")) {
        return .{ .function_name = func.name, .elem_ty = "f64", .array_name = "$do_f64" };
    }
    return null;
}

fn find_managed_tuple_text_bytes_probe(func: FuncDecl) ?ManagedTupleTextBytesProbe {
    if (func.params.len != 1 or func.results.len != 1) return null;
    if (!std.mem.eql(u8, func.params[0].ty, "Tuple<text,[u8]>") or !std.mem.eql(u8, func.results[0], "Tuple<text,[u8]>")) return null;
    const range = body_expr_range(func) orelse return null;
    const tokens = func.tokens;
    if (range.start + 8 >= range.end or !tok_eq(tokens[range.start], "Tuple") or !tok_eq(tokens[range.start + 1], "<")) return null;
    const close_angle = find_matching_in_range(tokens, range.start + 1, "<", ">", range.end) catch return null;
    if (close_angle != range.start + 7 or !tok_eq(tokens[range.start + 2], "text") or !tok_eq(tokens[range.start + 3], ",") or !tok_eq(tokens[range.start + 4], "[") or !tok_eq(tokens[range.start + 5], "u8") or !tok_eq(tokens[range.start + 6], "]")) return null;
    if (close_angle + 1 >= range.end or !tok_eq(tokens[close_angle + 1], "{")) return null;
    const close_brace = find_matching_in_range(tokens, close_angle + 1, "{", "}", range.end) catch return null;
    if (close_brace + 1 != range.end) return null;
    const first_end = find_arg_end(tokens, close_angle + 2, close_brace);
    if (first_end >= close_brace or !tok_eq(tokens[first_end], ",")) return null;
    if (!is_tuple_get_body_expr(func, close_angle + 2, first_end, "0")) return null;
    const second_start = first_end + 1;
    if (!is_tuple_bytes_set_body_expr(func, second_start, close_brace)) return null;
    return .{ .function_name = func.name };
}

fn find_payload_union_probe(func: FuncDecl, payload_enums: []const PayloadEnumDecl) !?PayloadUnionProbe {
    if (func.params.len != 2 or func.results.len != 1) return null;
    if (!std.mem.eql(u8, func.params[1].ty, "[u8]") or !std.mem.eql(u8, func.results[0], func.params[0].ty)) return null;

    var enum_decl: ?PayloadEnumDecl = null;
    for (payload_enums) |decl| {
        if (std.mem.eql(u8, decl.name, func.params[0].ty)) {
            enum_decl = decl;
            break;
        }
    }
    const decl = enum_decl orelse return null;
    const layout = codegen_gc_layout.collect_payload_union_layout(decl.name, decl.cases) catch return error.UnsupportedGcSyncProbeSignature;
    const range = body_expr_range(func) orelse return null;
    const tokens = func.tokens;
    if (range.start + 3 >= range.end or tokens[range.start].kind != .ident or
        !std.mem.eql(u8, tokens[range.start].lexeme, layout.managed_case) or
        !tok_eq(tokens[range.start + 1], "(") or tokens[range.start + 2].kind != .ident or
        !std.mem.eql(u8, tokens[range.start + 2].lexeme, func.params[1].name)) return null;
    const close_idx = find_matching_in_range(tokens, range.start + 1, "(", ")", range.end) catch return null;
    if (close_idx + 1 != range.end) return null;
    return .{
        .function_name = func.name,
        .union_name = layout.name,
        .unit_case = layout.unit_case,
        .managed_case = layout.managed_case,
        .unit_tag = layout.unit_tag,
        .managed_tag = layout.managed_tag,
    };
}

fn is_tuple_get_body_expr(func: FuncDecl, start_idx: usize, end_idx: usize, index: []const u8) bool {
    const tokens = func.tokens;
    if (start_idx + 3 >= end_idx or !tok_eq(tokens[start_idx], "@") or !tok_eq(tokens[start_idx + 1], "get") or !tok_eq(tokens[start_idx + 2], "(")) return false;
    const close_idx = find_matching_in_range(tokens, start_idx + 2, "(", ")", end_idx) catch return false;
    if (close_idx + 1 != end_idx) return false;
    return tok_eq(tokens[start_idx + 3], func.params[0].name) and tok_eq(tokens[start_idx + 4], ",") and tok_eq(tokens[start_idx + 5], index) and tok_eq(tokens[start_idx + 6], ")");
}

fn is_tuple_bytes_set_body_expr(func: FuncDecl, start_idx: usize, end_idx: usize) bool {
    const tokens = func.tokens;
    if (start_idx + 5 >= end_idx or !tok_eq(tokens[start_idx], "@") or !tok_eq(tokens[start_idx + 1], "set") or !tok_eq(tokens[start_idx + 2], "(")) return false;
    const close_idx = find_matching_in_range(tokens, start_idx + 2, "(", ")", end_idx) catch return false;
    if (close_idx + 1 != end_idx) return false;
    const receiver_end = find_arg_end(tokens, start_idx + 3, close_idx);
    if (!is_tuple_get_body_expr(func, start_idx + 3, receiver_end, "1")) return false;
    const index_start = receiver_end + 1;
    const index_end = find_arg_end(tokens, index_start, close_idx);
    const value_start = index_end + 1;
    return index_end < close_idx and tok_eq(tokens[index_end], ",") and value_start + 1 == close_idx and tok_eq(tokens[index_start], "0") and tok_eq(tokens[value_start], "65");
}

fn find_nested_managed_struct_probe(func: FuncDecl, structs: []const StructDecl) !?NestedManagedStructProbe {
    if (func.params.len != 2 or !std.mem.eql(u8, func.results[0], func.params[0].ty)) return null;
    const outer = find_struct_decl(structs, func.params[0].ty) orelse return null;
    const inner = find_struct_decl(structs, func.params[1].ty) orelse return null;
    if (outer.fields.len != 2 or inner.fields.len != 1 or !std.mem.eql(u8, inner.fields[0].ty, "[u8]")) return null;

    var child_field_name: ?[]const u8 = null;
    var scalar_field_name: ?[]const u8 = null;
    for (outer.fields) |field| {
        if (std.mem.eql(u8, field.ty, inner.name)) {
            if (child_field_name != null) return null;
            child_field_name = public_decl_name(field.name);
            continue;
        }
        if (std.mem.eql(u8, field.ty, "i32")) {
            if (scalar_field_name != null) return null;
            scalar_field_name = public_decl_name(field.name);
            continue;
        }
        return null;
    }
    const child_name = child_field_name orelse return null;
    const scalar_name = scalar_field_name orelse return null;
    if (!is_direct_managed_payload_set(func, child_name)) return null;
    return .{
        .function_name = func.name,
        .outer_name = outer.name,
        .outer_child_field_name = child_name,
        .outer_scalar_field_name = scalar_name,
        .outer_child_first = std.mem.eql(u8, public_decl_name(outer.fields[0].name), child_name),
        .inner_name = inner.name,
        .inner_payload_field_name = public_decl_name(inner.fields[0].name),
    };
}

fn find_three_level_nested_managed_scalar_field_probe(func: FuncDecl, structs: []const StructDecl) !?ThreeLevelNestedManagedScalarFieldProbe {
    if (func.params.len != 1 or func.results.len != 1 or !std.mem.eql(u8, func.results[0], func.params[0].ty)) return null;
    const outer = find_struct_decl(structs, func.params[0].ty) orelse return null;
    if (outer.fields.len != 2) return null;

    var middle_decl: ?StructDecl = null;
    var outer_child_field_name: ?[]const u8 = null;
    var outer_scalar_field_name: ?[]const u8 = null;
    for (outer.fields) |field| {
        if (find_struct_decl(structs, field.ty)) |candidate| {
            if (middle_decl != null) return null;
            middle_decl = candidate;
            outer_child_field_name = public_decl_name(field.name);
            continue;
        }
        if (std.mem.eql(u8, field.ty, "i32")) {
            if (outer_scalar_field_name != null) return null;
            outer_scalar_field_name = public_decl_name(field.name);
            continue;
        }
        return null;
    }

    const middle = middle_decl orelse return null;
    if (middle.fields.len != 2) return null;
    var inner_decl: ?StructDecl = null;
    var middle_child_field_name: ?[]const u8 = null;
    var middle_scalar_field_name: ?[]const u8 = null;
    for (middle.fields) |field| {
        if (find_struct_decl(structs, field.ty)) |candidate| {
            if (inner_decl != null) return null;
            inner_decl = candidate;
            middle_child_field_name = public_decl_name(field.name);
            continue;
        }
        if (std.mem.eql(u8, field.ty, "i32")) {
            if (middle_scalar_field_name != null) return null;
            middle_scalar_field_name = public_decl_name(field.name);
            continue;
        }
        return null;
    }

    const inner = inner_decl orelse return null;
    if (inner.fields.len != 2) return null;
    var leaf_decl: ?StructDecl = null;
    var inner_child_field_name: ?[]const u8 = null;
    var inner_scalar_field_name: ?[]const u8 = null;
    for (inner.fields) |field| {
        if (find_struct_decl(structs, field.ty)) |candidate| {
            if (leaf_decl != null) return null;
            leaf_decl = candidate;
            inner_child_field_name = public_decl_name(field.name);
            continue;
        }
        if (std.mem.eql(u8, field.ty, "i32")) {
            if (inner_scalar_field_name != null) return null;
            inner_scalar_field_name = public_decl_name(field.name);
            continue;
        }
        return null;
    }

    const leaf = leaf_decl orelse return null;
    if (leaf.fields.len != 2) return null;
    var leaf_scalar_field_name: ?[]const u8 = null;
    var leaf_payload_field_name: ?[]const u8 = null;
    for (leaf.fields) |field| {
        if (std.mem.eql(u8, field.ty, "i32")) {
            if (leaf_scalar_field_name != null) return null;
            leaf_scalar_field_name = public_decl_name(field.name);
            continue;
        }
        if (std.mem.eql(u8, field.ty, "[u8]")) {
            if (leaf_payload_field_name != null) return null;
            leaf_payload_field_name = public_decl_name(field.name);
            continue;
        }
        return null;
    }

    const outer_child_name = outer_child_field_name orelse return null;
    const outer_scalar_name = outer_scalar_field_name orelse return null;
    const middle_child_name = middle_child_field_name orelse return null;
    const middle_scalar_name = middle_scalar_field_name orelse return null;
    const inner_child_name = inner_child_field_name orelse return null;
    const inner_scalar_name = inner_scalar_field_name orelse return null;
    const leaf_scalar_name = leaf_scalar_field_name orelse return null;
    const leaf_payload_name = leaf_payload_field_name orelse return null;
    if (!is_three_level_nested_scalar_set_body(func, outer_child_name, middle_child_name, inner_child_name, leaf_scalar_name)) return null;
    return .{
        .function_name = func.name,
        .outer_name = outer.name,
        .outer_child_field_name = outer_child_name,
        .outer_scalar_field_name = outer_scalar_name,
        .outer_child_first = std.mem.eql(u8, public_decl_name(outer.fields[0].name), outer_child_name),
        .middle_name = middle.name,
        .middle_child_field_name = middle_child_name,
        .middle_scalar_field_name = middle_scalar_name,
        .middle_child_first = std.mem.eql(u8, public_decl_name(middle.fields[0].name), middle_child_name),
        .inner_name = inner.name,
        .inner_child_field_name = inner_child_name,
        .inner_scalar_field_name = inner_scalar_name,
        .inner_child_first = std.mem.eql(u8, public_decl_name(inner.fields[0].name), inner_child_name),
        .leaf_name = leaf.name,
        .leaf_scalar_field_name = leaf_scalar_name,
        .leaf_payload_field_name = leaf_payload_name,
        .leaf_scalar_first = std.mem.eql(u8, public_decl_name(leaf.fields[0].name), leaf_scalar_name),
    };
}

fn find_two_level_nested_managed_scalar_field_probe(func: FuncDecl, structs: []const StructDecl) !?TwoLevelNestedManagedScalarFieldProbe {
    if (func.params.len != 1 or func.results.len != 1 or !std.mem.eql(u8, func.results[0], func.params[0].ty)) return null;
    const outer = find_struct_decl(structs, func.params[0].ty) orelse return null;
    if (outer.fields.len != 2) return null;

    var middle_decl: ?StructDecl = null;
    var outer_child_field_name: ?[]const u8 = null;
    var outer_scalar_field_name: ?[]const u8 = null;
    for (outer.fields) |field| {
        if (find_struct_decl(structs, field.ty)) |candidate| {
            if (middle_decl != null) return null;
            middle_decl = candidate;
            outer_child_field_name = public_decl_name(field.name);
            continue;
        }
        if (std.mem.eql(u8, field.ty, "i32")) {
            if (outer_scalar_field_name != null) return null;
            outer_scalar_field_name = public_decl_name(field.name);
            continue;
        }
        return null;
    }

    const middle = middle_decl orelse return null;
    if (middle.fields.len != 2) return null;
    var inner_decl: ?StructDecl = null;
    var middle_child_field_name: ?[]const u8 = null;
    var middle_scalar_field_name: ?[]const u8 = null;
    for (middle.fields) |field| {
        if (find_struct_decl(structs, field.ty)) |candidate| {
            if (inner_decl != null) return null;
            inner_decl = candidate;
            middle_child_field_name = public_decl_name(field.name);
            continue;
        }
        if (std.mem.eql(u8, field.ty, "i32")) {
            if (middle_scalar_field_name != null) return null;
            middle_scalar_field_name = public_decl_name(field.name);
            continue;
        }
        return null;
    }

    const inner = inner_decl orelse return null;
    if (inner.fields.len != 2) return null;
    var inner_scalar_field_name: ?[]const u8 = null;
    var inner_payload_field_name: ?[]const u8 = null;
    for (inner.fields) |field| {
        if (std.mem.eql(u8, field.ty, "i32")) {
            if (inner_scalar_field_name != null) return null;
            inner_scalar_field_name = public_decl_name(field.name);
            continue;
        }
        if (std.mem.eql(u8, field.ty, "[u8]")) {
            if (inner_payload_field_name != null) return null;
            inner_payload_field_name = public_decl_name(field.name);
            continue;
        }
        return null;
    }

    const outer_child_name = outer_child_field_name orelse return null;
    const outer_scalar_name = outer_scalar_field_name orelse return null;
    const middle_child_name = middle_child_field_name orelse return null;
    const middle_scalar_name = middle_scalar_field_name orelse return null;
    const inner_scalar_name = inner_scalar_field_name orelse return null;
    const inner_payload_name = inner_payload_field_name orelse return null;
    if (!is_two_level_nested_scalar_set_body(func, outer_child_name, middle_child_name, inner_scalar_name)) return null;
    return .{
        .function_name = func.name,
        .outer_name = outer.name,
        .outer_child_field_name = outer_child_name,
        .outer_scalar_field_name = outer_scalar_name,
        .outer_child_first = std.mem.eql(u8, public_decl_name(outer.fields[0].name), outer_child_name),
        .middle_name = middle.name,
        .middle_child_field_name = middle_child_name,
        .middle_scalar_field_name = middle_scalar_name,
        .middle_child_first = std.mem.eql(u8, public_decl_name(middle.fields[0].name), middle_child_name),
        .inner_name = inner.name,
        .inner_scalar_field_name = inner_scalar_name,
        .inner_payload_field_name = inner_payload_name,
        .inner_payload_first = std.mem.eql(u8, public_decl_name(inner.fields[0].name), inner_payload_name),
    };
}

fn find_nested_managed_scalar_field_probe(func: FuncDecl, structs: []const StructDecl) !?NestedManagedScalarFieldProbe {
    if (func.params.len != 1 or func.results.len != 1 or !std.mem.eql(u8, func.results[0], func.params[0].ty)) return null;
    const outer = find_struct_decl(structs, func.params[0].ty) orelse return null;
    if (outer.fields.len != 2) return null;

    var inner_decl: ?StructDecl = null;
    var child_field_name: ?[]const u8 = null;
    var outer_scalar_field_name: ?[]const u8 = null;
    for (outer.fields) |field| {
        if (find_struct_decl(structs, field.ty)) |candidate| {
            if (inner_decl != null) return null;
            inner_decl = candidate;
            child_field_name = public_decl_name(field.name);
            continue;
        }
        if (std.mem.eql(u8, field.ty, "i32")) {
            if (outer_scalar_field_name != null) return null;
            outer_scalar_field_name = public_decl_name(field.name);
            continue;
        }
        return null;
    }

    const inner = inner_decl orelse return null;
    if (inner.fields.len != 2) return null;
    var inner_scalar_field_name: ?[]const u8 = null;
    var inner_payload_field_name: ?[]const u8 = null;
    for (inner.fields) |field| {
        if (std.mem.eql(u8, field.ty, "i32")) {
            if (inner_scalar_field_name != null) return null;
            inner_scalar_field_name = public_decl_name(field.name);
            continue;
        }
        if (std.mem.eql(u8, field.ty, "[u8]")) {
            if (inner_payload_field_name != null) return null;
            inner_payload_field_name = public_decl_name(field.name);
            continue;
        }
        return null;
    }

    const child_name = child_field_name orelse return null;
    const outer_scalar_name = outer_scalar_field_name orelse return null;
    const inner_scalar_name = inner_scalar_field_name orelse return null;
    const inner_payload_name = inner_payload_field_name orelse return null;
    if (!is_nested_scalar_set_body(func, child_name, inner_scalar_name)) return null;
    return .{
        .function_name = func.name,
        .outer_name = outer.name,
        .outer_child_field_name = child_name,
        .outer_scalar_field_name = outer_scalar_name,
        .outer_child_first = std.mem.eql(u8, public_decl_name(outer.fields[0].name), child_name),
        .inner_name = inner.name,
        .inner_scalar_field_name = inner_scalar_name,
        .inner_payload_field_name = inner_payload_name,
    };
}

fn find_struct_decl(structs: []const StructDecl, name: []const u8) ?StructDecl {
    for (structs) |decl| {
        if (std.mem.eql(u8, decl.name, name)) return decl;
    }
    return null;
}

fn find_managed_struct_call_payload_probe(func: FuncDecl, structs: []const StructDecl) !?ManagedStructCallPayloadProbe {
    if (func.params.len != 1 or func.results.len != 1 or !std.mem.eql(u8, func.results[0], func.params[0].ty)) return null;
    const decl = find_struct_decl(structs, func.params[0].ty) orelse return null;
    if (decl.fields.len != 2) return null;

    var managed_field_name: ?[]const u8 = null;
    var scalar_field_name: ?[]const u8 = null;
    for (decl.fields) |field| {
        if (std.mem.eql(u8, field.ty, "[u8]")) {
            if (managed_field_name != null) return null;
            managed_field_name = public_decl_name(field.name);
        } else if (std.mem.eql(u8, field.ty, "i32")) {
            if (scalar_field_name != null) return null;
            scalar_field_name = public_decl_name(field.name);
        } else return null;
    }
    const managed_name = managed_field_name orelse return null;
    const scalar_name = scalar_field_name orelse return null;
    const range = body_expr_range(func) orelse return null;
    const tokens = func.tokens;
    if (range.start + 3 >= range.end or !tok_eq(tokens[range.start], "@") or
        !tok_eq(tokens[range.start + 1], "set") or !tok_eq(tokens[range.start + 2], "(")) return null;
    const close_idx = find_matching_in_range(tokens, range.start + 2, "(", ")", range.end) catch return null;
    if (close_idx + 1 != range.end) return null;
    const receiver_end = find_arg_end(tokens, range.start + 3, close_idx);
    if (receiver_end >= close_idx or !tok_eq(tokens[receiver_end], ",") or receiver_end != range.start + 4 or
        tokens[range.start + 3].kind != .ident or !std.mem.eql(u8, tokens[range.start + 3].lexeme, func.params[0].name)) return null;
    const field_start = receiver_end + 1;
    const field_end = find_arg_end(tokens, field_start, close_idx);
    if (field_end >= close_idx or !tok_eq(tokens[field_end], ",") or field_end != field_start + 1 or
        !field_token_matches(tokens[field_start], managed_name)) return null;
    const producer_start = field_end + 1;
    const producer_end = find_arg_end(tokens, producer_start, close_idx);
    if (producer_end != close_idx) return null;
    if (producer_start + 2 >= producer_end or tokens[producer_start].kind != .ident or
        !tok_eq(tokens[producer_start + 1], "(")) return null;
    const producer_close = find_matching_in_range(tokens, producer_start + 1, "(", ")", producer_end) catch return null;
    if (producer_close + 1 != producer_end or producer_close != producer_start + 2) return null;
    return .{
        .function_name = func.name,
        .producer_name = tokens[producer_start].lexeme,
        .struct_name = func.params[0].ty,
        .managed_field_name = managed_name,
        .scalar_field_name = scalar_name,
        .managed_field_first = std.mem.eql(u8, public_decl_name(decl.fields[0].name), managed_name),
    };
}

fn find_managed_struct_call_text_probe(func: FuncDecl, structs: []const StructDecl) !?ManagedStructCallTextProbe {
    if (func.params.len != 1 or func.results.len != 1 or !std.mem.eql(u8, func.results[0], func.params[0].ty)) return null;
    const decl = find_struct_decl(structs, func.params[0].ty) orelse return null;
    if (decl.fields.len != 2) return null;

    var managed_field_name: ?[]const u8 = null;
    var scalar_field_name: ?[]const u8 = null;
    for (decl.fields) |field| {
        if (std.mem.eql(u8, field.ty, "text")) {
            if (managed_field_name != null) return null;
            managed_field_name = public_decl_name(field.name);
        } else if (std.mem.eql(u8, field.ty, "i32")) {
            if (scalar_field_name != null) return null;
            scalar_field_name = public_decl_name(field.name);
        } else return null;
    }
    const managed_name = managed_field_name orelse return null;
    const scalar_name = scalar_field_name orelse return null;
    const range = body_expr_range(func) orelse return null;
    const tokens = func.tokens;
    if (range.start + 3 >= range.end or !tok_eq(tokens[range.start], "@") or
        !tok_eq(tokens[range.start + 1], "set") or !tok_eq(tokens[range.start + 2], "(")) return null;
    const close_idx = find_matching_in_range(tokens, range.start + 2, "(", ")", range.end) catch return null;
    if (close_idx + 1 != range.end) return null;
    const receiver_end = find_arg_end(tokens, range.start + 3, close_idx);
    if (receiver_end >= close_idx or !tok_eq(tokens[receiver_end], ",") or receiver_end != range.start + 4 or
        tokens[range.start + 3].kind != .ident or !std.mem.eql(u8, tokens[range.start + 3].lexeme, func.params[0].name)) return null;
    const field_start = receiver_end + 1;
    const field_end = find_arg_end(tokens, field_start, close_idx);
    if (field_end >= close_idx or !tok_eq(tokens[field_end], ",") or field_end != field_start + 1 or
        !field_token_matches(tokens[field_start], managed_name)) return null;
    const producer_start = field_end + 1;
    const producer_end = find_arg_end(tokens, producer_start, close_idx);
    if (producer_end != close_idx or producer_start + 2 >= producer_end or tokens[producer_start].kind != .ident or
        !tok_eq(tokens[producer_start + 1], "(")) return null;
    const producer_close = find_matching_in_range(tokens, producer_start + 1, "(", ")", producer_end) catch return null;
    if (producer_close + 1 != producer_end or producer_close != producer_start + 2) return null;
    return .{
        .function_name = func.name,
        .producer_name = tokens[producer_start].lexeme,
        .struct_name = func.params[0].ty,
        .managed_field_name = managed_name,
        .scalar_field_name = scalar_name,
        .managed_field_first = std.mem.eql(u8, public_decl_name(decl.fields[0].name), managed_name),
    };
}

fn find_managed_struct_payload_probe(func: FuncDecl, structs: []const StructDecl) !?ManagedStructPayloadProbe {
    if (func.params.len != 2 or !std.mem.eql(u8, func.params[1].ty, "[u8]")) return null;
    if (!std.mem.eql(u8, func.results[0], func.params[0].ty)) return null;
    const decl = find_struct_decl(structs, func.params[0].ty) orelse return null;
    if (decl.fields.len != 2) return null;

    var managed_field_name: ?[]const u8 = null;
    var scalar_field_name: ?[]const u8 = null;
    for (decl.fields) |field| {
        if (std.mem.eql(u8, field.ty, "[u8]")) {
            if (managed_field_name != null) return null;
            managed_field_name = public_decl_name(field.name);
            continue;
        }
        if (std.mem.eql(u8, field.ty, "i32")) {
            if (scalar_field_name != null) return null;
            scalar_field_name = public_decl_name(field.name);
            continue;
        }
        return null;
    }
    const managed_name = managed_field_name orelse return null;
    const scalar_name = scalar_field_name orelse return null;
    if (!is_direct_managed_payload_set(func, managed_name) and
        !is_managed_payload_forward_call(func)) return null;
    return .{
        .function_name = func.name,
        .struct_name = func.params[0].ty,
        .managed_field_name = managed_name,
        .scalar_field_name = scalar_name,
        .managed_field_first = std.mem.eql(u8, public_decl_name(decl.fields[0].name), managed_name),
        .managed_field_type = "[u8]",
        .scalar_field_type = "i32",
    };
}

fn find_managed_scalar_array_field_probe(func: FuncDecl, structs: []const StructDecl) !?ManagedScalarArrayFieldProbe {
    if (func.params.len != 2) return null;
    if (!std.mem.eql(u8, func.results[0], func.params[0].ty)) return null;
    const managed_spec = codegen_gc_layout.scalar_array_spec_for_type(func.params[1].ty) orelse return null;
    const decl = find_struct_decl(structs, func.params[0].ty) orelse return null;
    if (decl.fields.len != 2) return null;

    var managed_field_name: ?[]const u8 = null;
    var scalar_field_name: ?[]const u8 = null;
    for (decl.fields) |field| {
        if (std.mem.eql(u8, field.ty, managed_spec.list_ty)) {
            if (managed_field_name != null) return null;
            managed_field_name = public_decl_name(field.name);
            continue;
        }
        if (std.mem.eql(u8, field.ty, "i32")) {
            if (scalar_field_name != null) return null;
            scalar_field_name = public_decl_name(field.name);
            continue;
        }
        return null;
    }
    const managed_name = managed_field_name orelse return null;
    const scalar_name = scalar_field_name orelse return null;
    if (!is_direct_managed_payload_set(func, managed_name)) return null;
    return .{
        .function_name = func.name,
        .struct_name = func.params[0].ty,
        .managed_field_name = managed_name,
        .scalar_field_name = scalar_name,
        .managed_field_first = std.mem.eql(u8, public_decl_name(decl.fields[0].name), managed_name),
        .managed_field_type = managed_spec.list_ty,
        .managed_array_name = managed_spec.array_name,
    };
}

fn is_managed_payload_forward_call(func: FuncDecl) bool {
    const range = body_expr_range(func) orelse return false;
    const tokens = func.tokens;
    if (range.start + 3 >= range.end or tokens[range.start].kind != .ident or
        !tok_eq(tokens[range.start + 1], "(") or
        tokens[range.start + 2].kind != .ident or
        !std.mem.eql(u8, tokens[range.start + 2].lexeme, func.params[0].name)) return false;
    const close_idx = find_matching_in_range(tokens, range.start + 1, "(", ")", range.end) catch return false;
    if (close_idx + 1 != range.end) return false;
    const first_end = find_arg_end(tokens, range.start + 2, close_idx);
    if (first_end >= close_idx or !tok_eq(tokens[first_end], ",")) return false;
    const second_start = first_end + 1;
    return second_start + 1 == close_idx and tokens[second_start].kind == .ident and
        std.mem.eql(u8, tokens[second_start].lexeme, func.params[1].name);
}

fn body_expr_range(func: FuncDecl) ?struct { start: usize, end: usize } {
    var start = func.body_start;
    if (!func.arrow) {
        if (start >= func.body_end or !tok_eq(func.tokens[start], "return")) return null;
        start += 1;
    }
    return .{ .start = start, .end = func.body_end };
}

fn is_single_managed_struct_list_literal_body(func: FuncDecl) bool {
    return is_managed_list_collection_body(func);
}

fn is_managed_list_collection_body(func: FuncDecl) bool {
    const tokens = func.tokens;
    var has_list_literal = false;
    var has_len = false;
    var has_get = false;
    var has_loop = false;
    var index: usize = func.body_start;
    while (index + 1 < func.body_end) : (index += 1) {
        if (tok_eq(tokens[index], "loop")) has_loop = true;
        if (tok_eq(tokens[index], ".") and tok_eq(tokens[index + 1], "{")) has_list_literal = true;
        if (tok_eq(tokens[index], "@") and index + 2 < func.body_end and tok_eq(tokens[index + 1], "len")) has_len = true;
        if (tok_eq(tokens[index], "@") and index + 2 < func.body_end and tok_eq(tokens[index + 1], "get")) has_get = true;
    }
    return has_list_literal and has_len and has_get and has_loop;
}

fn is_byte_list_literal_body(func: FuncDecl) bool {
    const range = body_expr_range(func) orelse return false;
    return range.start + 2 < range.end and tok_eq(func.tokens[range.start], ".") and tok_eq(func.tokens[range.start + 1], "{");
}

fn is_fixed_list_update_body(func: FuncDecl) bool {
    if (func.params.len != 1) return false;
    return is_set_call_body(func, func.params[0].name, "0", "65");
}

fn is_parameterized_list_update_body(func: FuncDecl) bool {
    if (func.params.len != 3) return false;
    return is_set_call_body(func, func.params[0].name, func.params[1].name, func.params[2].name);
}

fn is_byte_list_put_body(func: FuncDecl) bool {
    if (func.params.len != 2) return false;
    const range = body_expr_range(func) orelse return false;
    const tokens = func.tokens;
    if (range.start + 3 >= range.end or !tok_eq(tokens[range.start], "@") or !tok_eq(tokens[range.start + 1], "put") or !tok_eq(tokens[range.start + 2], "(")) return false;
    const close = find_matching_in_range(tokens, range.start + 2, "(", ")", range.end) catch return false;
    if (close + 1 != range.end) return false;
    const first_end = find_arg_end(tokens, range.start + 3, close);
    if (first_end >= close or !tok_eq(tokens[first_end], ",") or first_end != range.start + 4) return false;
    const value_start = first_end + 1;
    const value_end = find_arg_end(tokens, value_start, close);
    return value_end == close and value_end == value_start + 1 and
        tokens[value_start].kind == .ident and std.mem.eql(u8, tokens[value_start].lexeme, func.params[1].name);
}

fn is_scalar_list_put_body(func: FuncDecl) bool {
    if (func.params.len != 2) return false;
    const range = body_expr_range(func) orelse return false;
    const tokens = func.tokens;
    if (range.start + 3 >= range.end or !tok_eq(tokens[range.start], "@") or !tok_eq(tokens[range.start + 1], "put") or !tok_eq(tokens[range.start + 2], "(")) return false;
    const close = find_matching_in_range(tokens, range.start + 2, "(", ")", range.end) catch return false;
    if (close + 1 != range.end) return false;
    const first_end = find_arg_end(tokens, range.start + 3, close);
    if (first_end >= close or !tok_eq(tokens[first_end], ",") or first_end != range.start + 4) return false;
    if (tokens[range.start + 3].kind != .ident or !std.mem.eql(u8, tokens[range.start + 3].lexeme, func.params[0].name)) return false;
    const value_start = first_end + 1;
    const value_end = find_arg_end(tokens, value_start, close);
    return value_end == close and value_end == value_start + 1 and
        tokens[value_start].kind == .ident and std.mem.eql(u8, tokens[value_start].lexeme, func.params[1].name);
}

fn is_set_call_body(func: FuncDecl, receiver_name: []const u8, index_name: []const u8, value_name: []const u8) bool {
    const range = body_expr_range(func) orelse return false;
    const tokens = func.tokens;
    if (range.start + 3 >= range.end or !tok_eq(tokens[range.start], "@") or !tok_eq(tokens[range.start + 1], "set") or !tok_eq(tokens[range.start + 2], "(")) return false;
    const close = find_matching_in_range(tokens, range.start + 2, "(", ")", range.end) catch return false;
    if (close + 1 != range.end) return false;
    const receiver_end = find_arg_end(tokens, range.start + 3, close);
    if (receiver_end >= close or !tok_eq(tokens[receiver_end], ",") or receiver_end != range.start + 4) return false;
    if (tokens[range.start + 3].kind != .ident or !std.mem.eql(u8, tokens[range.start + 3].lexeme, receiver_name)) return false;
    const index_start = receiver_end + 1;
    const index_end = find_arg_end(tokens, index_start, close);
    if (index_end >= close or !tok_eq(tokens[index_end], ",") or index_end != index_start + 1) return false;
    if (tokens[index_start].kind == .number) {
        const expected_number = if (index_name.len > 0 and index_name[0] == '.') index_name[1..] else index_name;
        if (!std.mem.eql(u8, tokens[index_start].lexeme, expected_number)) return false;
    } else if (tokens[index_start].kind != .ident or !std.mem.eql(u8, tokens[index_start].lexeme, index_name)) return false;
    const value_start = index_end + 1;
    const value_end = find_arg_end(tokens, value_start, close);
    const ok = value_end == close and value_end == value_start + 1 and
        ((tokens[value_start].kind == .ident and std.mem.eql(u8, tokens[value_start].lexeme, value_name)) or
            (tokens[value_start].kind == .number and std.mem.eql(u8, tokens[value_start].lexeme, value_name)) or
            tok_eq(tokens[value_start], value_name));
    return ok;
}

fn is_direct_managed_payload_set(func: FuncDecl, managed_field_name: []const u8) bool {
    var expr_start = func.body_start;
    if (!func.arrow) {
        if (expr_start >= func.body_end or !tok_eq(func.tokens[expr_start], "return")) return false;
        expr_start += 1;
    }
    const end_idx = func.body_end;
    if (expr_start + 3 >= end_idx or !tok_eq(func.tokens[expr_start], "@") or !tok_eq(func.tokens[expr_start + 1], "set") or !tok_eq(func.tokens[expr_start + 2], "(")) return false;
    const close_idx = find_matching_in_range(func.tokens, expr_start + 2, "(", ")", end_idx) catch return false;
    if (close_idx + 1 != end_idx) return false;
    const target_end = find_arg_end(func.tokens, expr_start + 3, close_idx);
    if (target_end >= close_idx or target_end != expr_start + 4 or func.tokens[expr_start + 3].kind != .ident) return false;
    if (!std.mem.eql(u8, func.tokens[expr_start + 3].lexeme, func.params[0].name)) return false;
    const field_start = target_end + 1;
    const field_end = find_arg_end(func.tokens, field_start, close_idx);
    if (field_end != field_start + 1 or func.tokens[field_start].kind != .ident) return false;
    const field_name = func.tokens[field_start].lexeme;
    if (field_name.len < 2 or field_name[0] != '.' or !std.mem.eql(u8, field_name[1..], managed_field_name)) return false;
    if (field_end >= close_idx or !tok_eq(func.tokens[field_end], ",")) return false;
    const value_start = field_end + 1;
    const value_end = find_arg_end(func.tokens, value_start, close_idx);
    return value_end == close_idx and value_end == value_start + 1 and
        func.tokens[value_start].kind == .ident and
        std.mem.eql(u8, func.tokens[value_start].lexeme, func.params[1].name);
}

fn is_nested_scalar_set_body(func: FuncDecl, child_field_name: []const u8, scalar_field_name: []const u8) bool {
    const range = body_expr_range(func) orelse return false;
    const tokens = func.tokens;
    if (range.start + 3 >= range.end or !tok_eq(tokens[range.start], "@") or
        !tok_eq(tokens[range.start + 1], "set") or !tok_eq(tokens[range.start + 2], "(")) return false;
    const close_idx = find_matching_in_range(tokens, range.start + 2, "(", ")", range.end) catch return false;
    if (close_idx + 1 != range.end) return false;

    const root_end = find_arg_end(tokens, range.start + 3, close_idx);
    if (root_end >= close_idx or !tok_eq(tokens[root_end], ",") or root_end != range.start + 4 or
        tokens[range.start + 3].kind != .ident or !std.mem.eql(u8, tokens[range.start + 3].lexeme, func.params[0].name)) return false;
    const child_start = root_end + 1;
    const child_end = find_arg_end(tokens, child_start, close_idx);
    if (child_end >= close_idx or !tok_eq(tokens[child_end], ",") or child_end != child_start + 1 or
        !field_token_matches(tokens[child_start], child_field_name)) return false;
    const scalar_start = child_end + 1;
    const scalar_end = find_arg_end(tokens, scalar_start, close_idx);
    if (scalar_end >= close_idx or !tok_eq(tokens[scalar_end], ",") or scalar_end != scalar_start + 1 or
        !field_token_matches(tokens[scalar_start], scalar_field_name)) return false;
    const value_start = scalar_end + 1;
    const value_end = find_arg_end(tokens, value_start, close_idx);
    return value_end == close_idx and value_end == value_start + 1 and
        tokens[value_start].kind == .number and std.mem.eql(u8, tokens[value_start].lexeme, "9");
}

fn is_two_level_nested_scalar_set_body(
    func: FuncDecl,
    outer_child_field_name: []const u8,
    middle_child_field_name: []const u8,
    scalar_field_name: []const u8,
) bool {
    const range = body_expr_range(func) orelse return false;
    const tokens = func.tokens;
    if (range.start + 3 >= range.end or !tok_eq(tokens[range.start], "@") or
        !tok_eq(tokens[range.start + 1], "set") or !tok_eq(tokens[range.start + 2], "(")) return false;
    const close_idx = find_matching_in_range(tokens, range.start + 2, "(", ")", range.end) catch return false;
    if (close_idx + 1 != range.end) return false;

    var segment_start = range.start + 3;
    const root_end = find_arg_end(tokens, segment_start, close_idx);
    if (root_end >= close_idx or !tok_eq(tokens[root_end], ",") or root_end != segment_start + 1 or
        tokens[segment_start].kind != .ident or !std.mem.eql(u8, tokens[segment_start].lexeme, func.params[0].name)) return false;

    segment_start = root_end + 1;
    const outer_child_end = find_arg_end(tokens, segment_start, close_idx);
    if (outer_child_end >= close_idx or !tok_eq(tokens[outer_child_end], ",") or
        !field_token_matches(tokens[segment_start], outer_child_field_name)) return false;

    segment_start = outer_child_end + 1;
    const middle_child_end = find_arg_end(tokens, segment_start, close_idx);
    if (middle_child_end >= close_idx or !tok_eq(tokens[middle_child_end], ",") or
        !field_token_matches(tokens[segment_start], middle_child_field_name)) return false;

    segment_start = middle_child_end + 1;
    const scalar_end = find_arg_end(tokens, segment_start, close_idx);
    if (scalar_end >= close_idx or !tok_eq(tokens[scalar_end], ",") or
        !field_token_matches(tokens[segment_start], scalar_field_name)) return false;

    const value_start = scalar_end + 1;
    const value_end = find_arg_end(tokens, value_start, close_idx);
    return value_end == close_idx and value_end == value_start + 1 and
        tokens[value_start].kind == .number and std.mem.eql(u8, tokens[value_start].lexeme, "9");
}

fn is_three_level_nested_scalar_set_body(
    func: FuncDecl,
    outer_child_field_name: []const u8,
    middle_child_field_name: []const u8,
    inner_child_field_name: []const u8,
    scalar_field_name: []const u8,
) bool {
    const range = body_expr_range(func) orelse return false;
    const tokens = func.tokens;
    if (range.start + 3 >= range.end or !tok_eq(tokens[range.start], "@") or
        !tok_eq(tokens[range.start + 1], "set") or !tok_eq(tokens[range.start + 2], "(")) return false;
    const close_idx = find_matching_in_range(tokens, range.start + 2, "(", ")", range.end) catch return false;
    if (close_idx + 1 != range.end) return false;

    var segment_start = range.start + 3;
    const root_end = find_arg_end(tokens, segment_start, close_idx);
    if (root_end >= close_idx or !tok_eq(tokens[root_end], ",") or root_end != segment_start + 1 or
        tokens[segment_start].kind != .ident or !std.mem.eql(u8, tokens[segment_start].lexeme, func.params[0].name)) return false;

    segment_start = root_end + 1;
    const outer_child_end = find_arg_end(tokens, segment_start, close_idx);
    if (outer_child_end >= close_idx or !tok_eq(tokens[outer_child_end], ",") or
        !field_token_matches(tokens[segment_start], outer_child_field_name)) return false;

    segment_start = outer_child_end + 1;
    const middle_child_end = find_arg_end(tokens, segment_start, close_idx);
    if (middle_child_end >= close_idx or !tok_eq(tokens[middle_child_end], ",") or
        !field_token_matches(tokens[segment_start], middle_child_field_name)) return false;

    segment_start = middle_child_end + 1;
    const inner_child_end = find_arg_end(tokens, segment_start, close_idx);
    if (inner_child_end >= close_idx or !tok_eq(tokens[inner_child_end], ",") or
        !field_token_matches(tokens[segment_start], inner_child_field_name)) return false;

    segment_start = inner_child_end + 1;
    const scalar_end = find_arg_end(tokens, segment_start, close_idx);
    if (scalar_end >= close_idx or !tok_eq(tokens[scalar_end], ",") or
        !field_token_matches(tokens[segment_start], scalar_field_name)) return false;

    const value_start = scalar_end + 1;
    const value_end = find_arg_end(tokens, value_start, close_idx);
    return value_end == close_idx and value_end == value_start + 1 and
        tokens[value_start].kind == .number and std.mem.eql(u8, tokens[value_start].lexeme, "9");
}

fn field_token_matches(token: lexer.Token, field_name: []const u8) bool {
    return token.kind == .ident and token.lexeme.len == field_name.len + 1 and token.lexeme[0] == '.' and
        std.mem.eql(u8, token.lexeme[1..], field_name);
}

fn append_byte_list_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    function_name: []const u8,
    call_shape: ProbeCallShape,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    if (call_shape == .byte_list_literal) {
        return append_byte_list_literal_probe(allocator, out, wat, function_name);
    }
    if (call_shape == .byte_list_put) {
        return append_byte_list_put_probe(allocator, out, wat, function_name);
    }
    switch (call_shape) {
        .managed_struct_payload_update => |probe| {
            return append_managed_struct_payload_probe(allocator, out, wat, probe);
        },
        .managed_struct_call_payload_update => |probe| {
            return append_managed_struct_call_payload_probe(allocator, out, wat, probe);
        },
        .managed_struct_call_text_update => |probe| {
            return append_managed_struct_call_text_probe(allocator, out, wat, probe);
        },
        .managed_scalar_array_field_update => |probe| {
            return append_managed_scalar_array_field_probe(allocator, out, wat, probe);
        },
        .nested_managed_struct_update => |probe| {
            return append_nested_managed_struct_probe(allocator, out, wat, probe);
        },
        .nested_managed_scalar_field_update => |probe| {
            return append_nested_managed_scalar_field_probe(allocator, out, wat, probe);
        },
        .two_level_nested_managed_scalar_field_update => |probe| {
            return append_two_level_nested_managed_scalar_field_probe(allocator, out, wat, probe);
        },
        .three_level_nested_managed_scalar_field_update => |probe| {
            return append_three_level_nested_managed_scalar_field_probe(allocator, out, wat, probe);
        },
        .managed_tuple_text_bytes_update => |probe| {
            return append_managed_tuple_text_bytes_probe(allocator, out, wat, probe);
        },
        .payload_union_update => |probe| {
            return append_payload_union_probe(allocator, out, wat, probe);
        },
        .managed_text_branch => |probe| {
            return append_managed_text_branch_probe(allocator, out, wat, probe);
        },
        .managed_text_identity => |probe| {
            return append_managed_text_identity_probe(allocator, out, wat, probe);
        },
        .managed_text_call_identity => |probe| {
            return append_managed_text_identity_probe(allocator, out, wat, probe);
        },
        .u32_list_literal => |probe| {
            return append_u32_list_literal_probe(allocator, out, wat, probe);
        },
        .u32_list_update => |probe| {
            return append_u32_list_update_probe(allocator, out, wat, probe);
        },
        .bool_list_update => |probe| {
            return append_bool_list_update_probe(allocator, out, wat, probe);
        },
        .i16_list_literal => |probe| {
            return append_i16_list_literal_probe(allocator, out, wat, probe);
        },
        .i16_list_update => |probe| {
            return append_i16_list_update_probe(allocator, out, wat, probe);
        },
        .i32_list_literal => |probe| {
            return append_i32_list_literal_probe(allocator, out, wat, probe);
        },
        .i32_list_update => |probe| {
            return append_i32_list_update_probe(allocator, out, wat, probe);
        },
        .i64_list_literal => |probe| {
            return append_i64_list_literal_probe(allocator, out, wat, probe);
        },
        .i64_list_update => |probe| {
            return append_i64_list_update_probe(allocator, out, wat, probe);
        },
        .scalar_list_literal => |probe| {
            return append_scalar_list_literal_probe(allocator, out, wat, probe);
        },
        .scalar_list_update => |probe| {
            return append_scalar_list_update_probe(allocator, out, wat, probe);
        },
        .scalar_list_put => |probe| {
            return append_scalar_list_put_probe(allocator, out, wat, probe);
        },
        .float_list_literal => |probe| {
            return append_float_list_literal_probe(allocator, out, wat, probe);
        },
        .float_list_update => |probe| {
            return append_float_list_update_probe(allocator, out, wat, probe);
        },
        .managed_struct_list_literal => |probe| {
            return append_managed_struct_list_literal_probe(allocator, out, wat, probe);
        },
        .managed_struct_list_put => |probe| {
            return append_managed_struct_list_put_probe(allocator, out, wat, probe);
        },
        .text_list_literal => |probe| {
            return append_text_list_literal_probe(allocator, out, wat, probe);
        },
        .text_list_put => |probe| {
            return append_text_list_put_probe(allocator, out, wat, probe);
        },
        .nested_byte_list_literal => |probe| {
            return append_nested_byte_list_probe(allocator, out, wat, probe);
        },
        .nested_byte_list_put => |probe| {
            return append_nested_byte_list_put_probe(allocator, out, wat, probe);
        },
        else => {},
    }
    try out.appendSlice(allocator, wat[0..module_end]);
    const update_index: u32 = switch (call_shape) {
        .byte_list_literal => unreachable,
        .byte_list_put => unreachable,
        .fixed_list_update => 0,
        .parameterized_list_update => 1,
        .managed_struct_payload_update => unreachable,
        .managed_struct_call_payload_update => unreachable,
        .managed_struct_call_text_update => unreachable,
        .managed_scalar_array_field_update => unreachable,
        .nested_managed_struct_update => unreachable,
        .nested_managed_scalar_field_update => unreachable,
        .two_level_nested_managed_scalar_field_update => unreachable,
        .three_level_nested_managed_scalar_field_update => unreachable,
        .managed_tuple_text_bytes_update => unreachable,
        .payload_union_update => unreachable,
        .managed_text_branch => unreachable,
        .managed_text_identity => unreachable,
        .managed_text_call_identity => unreachable,
        .u32_list_literal => unreachable,
        .u32_list_update => unreachable,
        .bool_list_update => unreachable,
        .i16_list_literal => unreachable,
        .i16_list_update => unreachable,
        .i32_list_literal => unreachable,
        .i32_list_update => unreachable,
        .i64_list_literal => unreachable,
        .i64_list_update => unreachable,
        .scalar_list_literal => unreachable,
        .scalar_list_update => unreachable,
        .scalar_list_put => unreachable,
        .float_list_literal => unreachable,
        .float_list_update => unreachable,
        .managed_struct_list_literal => unreachable,
        .managed_struct_list_put => unreachable,
        .text_list_literal => unreachable,
        .text_list_put => unreachable,
        .nested_byte_list_literal => unreachable,
        .nested_byte_list_put => unreachable,
    };
    const original_value: u32 = switch (call_shape) {
        .byte_list_literal => unreachable,
        .byte_list_put => unreachable,
        .fixed_list_update => 1,
        .parameterized_list_update => 2,
        .managed_struct_payload_update => unreachable,
        .managed_struct_call_payload_update => unreachable,
        .managed_struct_call_text_update => unreachable,
        .managed_scalar_array_field_update => unreachable,
        .nested_managed_struct_update => unreachable,
        .nested_managed_scalar_field_update => unreachable,
        .two_level_nested_managed_scalar_field_update => unreachable,
        .three_level_nested_managed_scalar_field_update => unreachable,
        .managed_tuple_text_bytes_update => unreachable,
        .payload_union_update => unreachable,
        .managed_text_branch => unreachable,
        .managed_text_identity => unreachable,
        .managed_text_call_identity => unreachable,
        .u32_list_literal => unreachable,
        .u32_list_update => unreachable,
        .bool_list_update => unreachable,
        .i16_list_literal => unreachable,
        .i16_list_update => unreachable,
        .i32_list_literal => unreachable,
        .i32_list_update => unreachable,
        .i64_list_literal => unreachable,
        .i64_list_update => unreachable,
        .scalar_list_literal => unreachable,
        .scalar_list_update => unreachable,
        .scalar_list_put => unreachable,
        .float_list_literal => unreachable,
        .float_list_update => unreachable,
        .managed_struct_list_literal => unreachable,
        .managed_struct_list_put => unreachable,
        .text_list_literal => unreachable,
        .text_list_put => unreachable,
        .nested_byte_list_literal => unreachable,
        .nested_byte_list_put => unreachable,
    };
    try append_fmt(
        allocator,
        out,
        "  (func (export \"probe\") (result i32)\n" ++
            "    (local $original (ref $do_bytes))\n" ++
            "    (local $updated (ref null $do_bytes))\n" ++
            "    i32.const 1\n" ++
            "    i32.const 2\n" ++
            "    i32.const 3\n" ++
            "    array.new_fixed $do_bytes 3\n" ++
            "    local.tee $original\n",
        .{},
    );
    if (call_shape == .parameterized_list_update) {
        try out.appendSlice(allocator, "    i32.const 1\n    i32.const 65\n");
    }
    try append_fmt(
        allocator,
        out,
        "    call ${s}\n" ++
            "    local.set $updated\n" ++
            "    local.get $original\n" ++
            "    i32.const {d}\n" ++
            "    array.get_s $do_bytes\n" ++
            "    i32.const {d}\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    local.get $updated\n" ++
            "    ref.as_non_null\n" ++
            "    i32.const {d}\n" ++
            "    array.get_s $do_bytes\n" ++
            "    i32.const 65\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    i32.const 27815)\n" ++
            ")\n",
        .{ function_name, update_index, original_value, update_index },
    );
}

fn append_managed_text_branch_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: ManagedTextBranchProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $left (ref $do_text))\n" ++
        "    (local $right (ref $do_text))\n" ++
        "    (local $selected (ref null $do_text))\n" ++
        "    i32.const 1\n" ++
        "    i32.const 97\n" ++
        "    array.new_fixed $do_bytes 1\n" ++
        "    struct.new $do_text\n" ++
        "    local.set $left\n" ++
        "    i32.const 1\n" ++
        "    i32.const 98\n" ++
        "    array.new_fixed $do_bytes 1\n" ++
        "    struct.new $do_text\n" ++
        "    local.set $right\n" ++
        "    i32.const 1\n" ++
        "    local.get $left\n" ++
        "    local.get $right\n" ++
        "    call ${s}\n" ++
        "    local.tee $selected\n" ++
        "    ref.as_non_null\n" ++
        "    local.get $left\n" ++
        "    ref.eq\n" ++
        "    i32.eqz\n" ++
        "    if unreachable end\n" ++
        "    i32.const 0\n" ++
        "    local.get $left\n" ++
        "    local.get $right\n" ++
        "    call ${s}\n" ++
        "    local.tee $selected\n" ++
        "    ref.as_non_null\n" ++
        "    local.get $right\n" ++
        "    ref.eq\n" ++
        "    i32.eqz\n" ++
        "    if unreachable end\n" ++
        "    i32.const 27815)\n" ++
        ")\n", .{ probe.function_name, probe.function_name });
}

fn append_managed_struct_list_literal_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: ManagedStructListProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    const struct_name = try lowered_wat_name(allocator, probe.struct_name);
    defer allocator.free(struct_name);
    const managed_field_name = try lowered_wat_name(allocator, probe.managed_field_name);
    defer allocator.free(managed_field_name);
    const scalar_field_name = try lowered_wat_name(allocator, probe.scalar_field_name);
    defer allocator.free(scalar_field_name);
    const list_array_name = try std.fmt.allocPrint(allocator, "$do_list_{s}", .{struct_name});
    defer allocator.free(list_array_name);

    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $result (ref null {s}))\n" ++
        "    (local $element (ref null ${s}))\n" ++
        "    call ${s}\n" ++
        "    local.tee $result\n" ++
        "    ref.as_non_null\n" ++
        "    array.len\n" ++
        "    i32.const 1\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $result\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 0\n" ++
        "    array.get {s}\n" ++
        "    local.set $element\n" ++
        "    local.get $element\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} ${s}\n" ++
        "    i32.const 7\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $element\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} ${s}\n" ++
        "    ref.as_non_null\n" ++
        "    array.len\n" ++
        "    i32.const 3\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n", .{ list_array_name, struct_name, probe.function_name, list_array_name, struct_name, scalar_field_name, struct_name, managed_field_name });
    const values = [_]u32{ 7, 12, 17 };
    for (values, 0..) |value, index| {
        try append_fmt(allocator, out, "    local.get $element\n" ++
            "    ref.as_non_null\n" ++
            "    struct.get ${s} ${s}\n" ++
            "    ref.as_non_null\n" ++
            "    i32.const {d}\n" ++
            "    array.get_s $do_bytes\n" ++
            "    i32.const {d}\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n", .{ struct_name, managed_field_name, index, value });
    }
    try out.appendSlice(allocator, "    i32.const 27815)\n)\n");
}

fn append_managed_struct_list_put_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: ManagedStructListProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    const struct_name = try lowered_wat_name(allocator, probe.struct_name);
    defer allocator.free(struct_name);
    const managed_field_name = try lowered_wat_name(allocator, probe.managed_field_name);
    defer allocator.free(managed_field_name);
    const scalar_field_name = try lowered_wat_name(allocator, probe.scalar_field_name);
    defer allocator.free(scalar_field_name);
    const list_array_name = try std.fmt.allocPrint(allocator, "$do_list_{s}", .{struct_name});
    defer allocator.free(list_array_name);

    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $original (ref null {s}))\n" ++
        "    (local $updated (ref null {s}))\n" ++
        "    (local $original_element (ref null ${s}))\n" ++
        "    (local $updated_first (ref null ${s}))\n" ++
        "    (local $updated_second (ref null ${s}))\n" ++
        "    (local $value (ref null ${s}))\n" ++
        "    i32.const 7\n" ++
        "    i32.const 12\n" ++
        "    i32.const 17\n" ++
        "    array.new_fixed $do_bytes 3\n" ++
        "    i32.const 7\n" ++
        "    struct.new ${s}\n" ++
        "    array.new_fixed {s} 1\n" ++
        "    local.set $original\n" ++
        "    i32.const 42\n" ++
        "    array.new_fixed $do_bytes 1\n" ++
        "    i32.const 9\n" ++
        "    struct.new ${s}\n" ++
        "    local.set $value\n" ++
        "    local.get $original\n" ++
        "    local.get $value\n" ++
        "    call ${s}\n" ++
        "    local.set $updated\n" ++
        "    local.get $original\n" ++
        "    ref.as_non_null\n" ++
        "    array.len\n" ++
        "    i32.const 1\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $original\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 0\n" ++
        "    array.get {s}\n" ++
        "    local.set $original_element\n" ++
        "    local.get $original_element\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} ${s}\n" ++
        "    i32.const 7\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $original_element\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} ${s}\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 0\n" ++
        "    array.get_s $do_bytes\n" ++
        "    i32.const 7\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    array.len\n" ++
        "    i32.const 2\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 0\n" ++
        "    array.get {s}\n" ++
        "    local.set $updated_first\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 1\n" ++
        "    array.get {s}\n" ++
        "    local.set $updated_second\n" ++
        "    local.get $updated_first\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} ${s}\n" ++
        "    i32.const 7\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated_second\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} ${s}\n" ++
        "    i32.const 9\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated_second\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} ${s}\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 0\n" ++
        "    array.get_s $do_bytes\n" ++
        "    i32.const 42\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    i32.const 27815)\n" ++
        ")\n", .{
        list_array_name,
        list_array_name,
        struct_name,
        struct_name,
        struct_name,
        struct_name,
        struct_name,
        list_array_name,
        struct_name,
        probe.function_name,
        list_array_name,
        struct_name,
        scalar_field_name,
        struct_name,
        managed_field_name,
        list_array_name,
        list_array_name,
        struct_name,
        scalar_field_name,
        struct_name,
        scalar_field_name,
        struct_name,
        managed_field_name,
    });
}

fn append_text_list_literal_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: TextListProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $result (ref null $do_list_text))\n" ++
        "    (local $first (ref null $do_text))\n" ++
        "    (local $second (ref null $do_text))\n" ++
        "    call ${s}\n" ++
        "    local.tee $result\n" ++
        "    ref.as_non_null\n" ++
        "    array.len\n" ++
        "    i32.const 2\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $result\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 0\n" ++
        "    array.get $do_list_text\n" ++
        "    local.set $first\n" ++
        "    local.get $result\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 1\n" ++
        "    array.get $do_list_text\n" ++
        "    local.set $second\n" ++
        "    local.get $first\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get $do_text $length\n" ++
        "    i32.const 1\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $first\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get $do_text $bytes\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 0\n" ++
        "    array.get_s $do_bytes\n" ++
        "    i32.const 97\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $second\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get $do_text $length\n" ++
        "    i32.const 2\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $second\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get $do_text $bytes\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 0\n" ++
        "    array.get_s $do_bytes\n" ++
        "    i32.const 98\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    i32.const 27815)\n)\n", .{probe.function_name});
}

fn append_text_list_put_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: TextListPutProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $original (ref $do_list_text))\n" ++
        "    (local $updated (ref null $do_list_text))\n" ++
        "    (local $first (ref null $do_text))\n" ++
        "    (local $second (ref null $do_text))\n" ++
        "    (local $original_first (ref null $do_text))\n" ++
        "    (local $updated_first (ref null $do_text))\n" ++
        "    i32.const 1\n" ++
        "    i32.const 97\n" ++
        "    array.new_fixed $do_bytes 1\n" ++
        "    struct.new $do_text\n" ++
        "    local.set $first\n" ++
        "    i32.const 2\n" ++
        "    i32.const 98\n" ++
        "    i32.const 99\n" ++
        "    array.new_fixed $do_bytes 2\n" ++
        "    struct.new $do_text\n" ++
        "    local.set $second\n" ++
        "    local.get $first\n" ++
        "    array.new_fixed $do_list_text 1\n" ++
        "    local.tee $original\n" ++
        "    local.get $second\n" ++
        "    call ${s}\n" ++
        "    local.set $updated\n" ++
        "    local.get $original\n" ++
        "    ref.as_non_null\n" ++
        "    array.len\n" ++
        "    i32.const 1\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    array.len\n" ++
        "    i32.const 2\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $original\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 0\n" ++
        "    array.get $do_list_text\n" ++
        "    local.set $original_first\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 0\n" ++
        "    array.get $do_list_text\n" ++
        "    local.set $updated_first\n" ++
        "    local.get $original_first\n" ++
        "    local.get $updated_first\n" ++
        "    ref.eq\n" ++
        "    i32.eqz\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 1\n" ++
        "    array.get $do_list_text\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get $do_text $length\n" ++
        "    i32.const 2\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 1\n" ++
        "    array.get $do_list_text\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get $do_text $bytes\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 0\n" ++
        "    array.get_s $do_bytes\n" ++
        "    i32.const 98\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    i32.const 27815)\n)\n", .{probe.function_name});
}

fn append_nested_byte_list_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: NestedByteListProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $result (ref null $do_list_list_u8))\n" ++
        "    (local $row (ref null $do_bytes))\n" ++
        "    call ${s}\n" ++
        "    local.tee $result\n" ++
        "    ref.as_non_null\n" ++
        "    array.len\n" ++
        "    i32.const 1\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $result\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 0\n" ++
        "    array.get $do_list_list_u8\n" ++
        "    local.set $row\n" ++
        "    local.get $row\n" ++
        "    ref.as_non_null\n" ++
        "    array.len\n" ++
        "    i32.const 3\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n", .{probe.function_name});
    const values = [_]u32{ 1, 2, 3 };
    for (values, 0..) |value, index| {
        try append_fmt(allocator, out, "    local.get $row\n" ++
            "    ref.as_non_null\n" ++
            "    i32.const {d}\n" ++
            "    array.get_s $do_bytes\n" ++
            "    i32.const {d}\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n", .{ index, value });
    }
    try out.appendSlice(allocator, "    i32.const 27815)\n)\n");
}

fn append_nested_byte_list_put_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: NestedByteListPutProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $original (ref $do_list_list_u8))\n" ++
        "    (local $updated (ref null $do_list_list_u8))\n" ++
        "    (local $row (ref $do_bytes))\n" ++
        "    (local $original_row (ref null $do_bytes))\n" ++
        "    (local $updated_first (ref null $do_bytes))\n" ++
        "    (local $updated_second (ref null $do_bytes))\n" ++
        "    i32.const 1\n" ++
        "    i32.const 2\n" ++
        "    i32.const 3\n" ++
        "    array.new_fixed $do_bytes 3\n" ++
        "    local.tee $row\n" ++
        "    array.new_fixed $do_list_list_u8 1\n" ++
        "    local.tee $original\n" ++
        "    i32.const 4\n" ++
        "    i32.const 5\n" ++
        "    array.new_fixed $do_bytes 2\n" ++
        "    call ${s}\n" ++
        "    local.set $updated\n" ++
        "    local.get $original\n" ++
        "    ref.as_non_null\n" ++
        "    array.len\n" ++
        "    i32.const 1\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    array.len\n" ++
        "    i32.const 2\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $original\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 0\n" ++
        "    array.get $do_list_list_u8\n" ++
        "    local.set $original_row\n" ++
        "    local.get $original_row\n" ++
        "    ref.as_non_null\n" ++
        "    array.len\n" ++
        "    i32.const 3\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $original_row\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 0\n" ++
        "    array.get_s $do_bytes\n" ++
        "    i32.const 1\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 0\n" ++
        "    array.get $do_list_list_u8\n" ++
        "    local.set $updated_first\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 1\n" ++
        "    array.get $do_list_list_u8\n" ++
        "    local.set $updated_second\n" ++
        "    local.get $original_row\n" ++
        "    local.get $updated_first\n" ++
        "    ref.eq\n" ++
        "    i32.eqz\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated_second\n" ++
        "    ref.as_non_null\n" ++
        "    array.len\n" ++
        "    i32.const 2\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated_second\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 0\n" ++
        "    array.get_s $do_bytes\n" ++
        "    i32.const 4\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated_second\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 1\n" ++
        "    array.get_s $do_bytes\n" ++
        "    i32.const 5\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    i32.const 27815)\n)\n", .{probe.function_name});
}

fn append_managed_text_identity_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: ManagedTextIdentityProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $input (ref $do_text))\n" ++
        "    (local $result (ref null $do_text))\n" ++
        "    i32.const 5\n" ++
        "    i32.const 104\n" ++
        "    i32.const 101\n" ++
        "    i32.const 108\n" ++
        "    i32.const 108\n" ++
        "    i32.const 111\n" ++
        "    array.new_fixed $do_bytes 5\n" ++
        "    struct.new $do_text\n" ++
        "    local.tee $input\n" ++
        "    call ${s}\n" ++
        "    local.tee $result\n" ++
        "    ref.as_non_null\n" ++
        "    local.get $input\n" ++
        "    ref.eq\n" ++
        "    i32.eqz\n" ++
        "    if unreachable end\n" ++
        "    local.get $result\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get $do_text $length\n" ++
        "    i32.const 5\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $result\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get $do_text $bytes\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 0\n" ++
        "    array.get_s $do_bytes\n" ++
        "    i32.const 104\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    i32.const 27815)\n" ++
        ")\n", .{probe.function_name});
}

fn append_u32_list_literal_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: U32ListLiteralProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $result (ref null $do_u32))\n" ++
        "    call ${s}\n" ++
        "    local.tee $result\n" ++
        "    ref.as_non_null\n" ++
        "    array.len\n" ++
        "    i32.const 3\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $result\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 1\n" ++
        "    array.get $do_u32\n" ++
        "    i32.const 12\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    i32.const 27815)\n" ++
        ")\n", .{probe.function_name});
}

fn append_u32_list_update_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: U32ListUpdateProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $original (ref $do_u32))\n" ++
        "    (local $updated (ref null $do_u32))\n" ++
        "    i32.const 7\n" ++
        "    i32.const 12\n" ++
        "    i32.const 17\n" ++
        "    array.new_fixed $do_u32 3\n" ++
        "    local.tee $original\n" ++
        "    call ${s}\n" ++
        "    local.set $updated\n" ++
        "    local.get $original\n" ++
        "    i32.const 1\n" ++
        "    array.get $do_u32\n" ++
        "    i32.const 12\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 1\n" ++
        "    array.get $do_u32\n" ++
        "    i32.const 65\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    i32.const 27815)\n" ++
        ")\n", .{probe.function_name});
}

fn append_i16_list_literal_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: I16ListLiteralProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $result (ref null $do_i16))\n" ++
        "    call ${s}\n" ++
        "    local.tee $result\n" ++
        "    ref.as_non_null\n" ++
        "    array.len\n" ++
        "    i32.const 3\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $result\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 1\n" ++
        "    array.get $do_i16\n" ++
        "    i32.const 12\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    i32.const 27815)\n" ++
        ")\n", .{probe.function_name});
}

fn append_float_list_literal_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: FloatListLiteralProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $result (ref null {s}))\n" ++
        "    call ${s}\n" ++
        "    local.tee $result\n" ++
        "    ref.as_non_null\n" ++
        "    array.len\n" ++
        "    i32.const 2\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $result\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 0\n" ++
        "    array.get {s}\n" ++
        "    {s}.const 1.5\n" ++
        "    {s}.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $result\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 1\n" ++
        "    array.get {s}\n" ++
        "    {s}.const 2.25\n" ++
        "    {s}.ne\n" ++
        "    if unreachable end\n" ++
        "    i32.const 27815)\n" ++
        ")\n", .{ probe.array_name, probe.function_name, probe.array_name, probe.elem_ty, probe.elem_ty, probe.array_name, probe.elem_ty, probe.elem_ty });
}

fn append_float_list_update_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: FloatListUpdateProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $original (ref {s}))\n" ++
        "    (local $updated (ref null {s}))\n" ++
        "    {s}.const 1.5\n" ++
        "    {s}.const 2.25\n" ++
        "    {s}.const 4.75\n" ++
        "    array.new_fixed {s} 3\n" ++
        "    local.tee $original\n" ++
        "    call ${s}\n" ++
        "    local.set $updated\n" ++
        "    local.get $original\n" ++
        "    i32.const 1\n" ++
        "    array.get {s}\n" ++
        "    {s}.const 2.25\n" ++
        "    {s}.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 1\n" ++
        "    array.get {s}\n" ++
        "    {s}.const 3.5\n" ++
        "    {s}.ne\n" ++
        "    if unreachable end\n" ++
        "    i32.const 27815)\n" ++
        ")\n", .{
        probe.array_name,
        probe.array_name,
        probe.elem_ty,
        probe.elem_ty,
        probe.elem_ty,
        probe.array_name,
        probe.function_name,
        probe.array_name,
        probe.elem_ty,
        probe.elem_ty,
        probe.array_name,
        probe.elem_ty,
        probe.elem_ty,
    });
}

fn append_bool_list_update_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: BoolListUpdateProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $original (ref $do_bool))\n" ++
        "    (local $updated (ref null $do_bool))\n" ++
        "    i32.const 1\n" ++
        "    i32.const 0\n" ++
        "    i32.const 1\n" ++
        "    array.new_fixed $do_bool 3\n" ++
        "    local.tee $original\n" ++
        "    call ${s}\n" ++
        "    local.set $updated\n" ++
        "    local.get $original\n" ++
        "    i32.const 1\n" ++
        "    array.get $do_bool\n" ++
        "    i32.const 0\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 1\n" ++
        "    array.get $do_bool\n" ++
        "    i32.const 1\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    i32.const 27815)\n" ++
        ")\n", .{probe.function_name});
}

fn append_i16_list_update_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: I16ListUpdateProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $original (ref $do_i16))\n" ++
        "    (local $updated (ref null $do_i16))\n" ++
        "    i32.const 7\n" ++
        "    i32.const 12\n" ++
        "    i32.const 17\n" ++
        "    array.new_fixed $do_i16 3\n" ++
        "    local.tee $original\n" ++
        "    call ${s}\n" ++
        "    local.set $updated\n" ++
        "    local.get $original\n" ++
        "    i32.const 1\n" ++
        "    array.get $do_i16\n" ++
        "    i32.const 12\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 1\n" ++
        "    array.get $do_i16\n" ++
        "    i32.const 65\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    i32.const 27815)\n" ++
        ")\n", .{probe.function_name});
}

fn append_i32_list_literal_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: I32ListLiteralProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $result (ref null $do_i32))\n" ++
        "    call ${s}\n" ++
        "    local.tee $result\n" ++
        "    ref.as_non_null\n" ++
        "    array.len\n" ++
        "    i32.const 3\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $result\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 1\n" ++
        "    array.get $do_i32\n" ++
        "    i32.const 12\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    i32.const 27815)\n" ++
        ")\n", .{probe.function_name});
}

fn append_i32_list_update_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: I32ListUpdateProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $original (ref $do_i32))\n" ++
        "    (local $updated (ref null $do_i32))\n" ++
        "    i32.const 7\n" ++
        "    i32.const 12\n" ++
        "    i32.const 17\n" ++
        "    array.new_fixed $do_i32 3\n" ++
        "    local.tee $original\n" ++
        "    call ${s}\n" ++
        "    local.set $updated\n" ++
        "    local.get $original\n" ++
        "    i32.const 1\n" ++
        "    array.get $do_i32\n" ++
        "    i32.const 12\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 1\n" ++
        "    array.get $do_i32\n" ++
        "    i32.const 65\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    i32.const 27815)\n" ++
        ")\n", .{probe.function_name});
}

fn append_i64_list_literal_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: I64ListLiteralProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $result (ref null $do_i64))\n" ++
        "    call ${s}\n" ++
        "    local.tee $result\n" ++
        "    ref.as_non_null\n" ++
        "    array.len\n" ++
        "    i32.const 3\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $result\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 1\n" ++
        "    array.get $do_i64\n" ++
        "    i64.const 12\n" ++
        "    i64.ne\n" ++
        "    if unreachable end\n" ++
        "    i32.const 27815)\n" ++
        ")\n", .{probe.function_name});
}

fn append_i64_list_update_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: I64ListUpdateProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $original (ref $do_i64))\n" ++
        "    (local $updated (ref null $do_i64))\n" ++
        "    i64.const 7\n" ++
        "    i64.const 12\n" ++
        "    i64.const 17\n" ++
        "    array.new_fixed $do_i64 3\n" ++
        "    local.tee $original\n" ++
        "    call ${s}\n" ++
        "    local.set $updated\n" ++
        "    local.get $original\n" ++
        "    i32.const 1\n" ++
        "    array.get $do_i64\n" ++
        "    i64.const 12\n" ++
        "    i64.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 1\n" ++
        "    array.get $do_i64\n" ++
        "    i64.const 65\n" ++
        "    i64.ne\n" ++
        "    if unreachable end\n" ++
        "    i32.const 27815)\n" ++
        ")\n", .{probe.function_name});
}

fn append_scalar_list_literal_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: ScalarListProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    const wasm_elem_ty = codegen_gc_layout.scalar_array_wasm_elem_type(probe.elem_ty);
    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $result (ref null {s}))\n" ++
        "    call ${s}\n" ++
        "    local.tee $result\n" ++
        "    ref.as_non_null\n" ++
        "    array.len\n" ++
        "    i32.const 3\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $result\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 1\n" ++
        "    array.get {s}\n" ++
        "    {s}.const 12\n" ++
        "    {s}.ne\n" ++
        "    if unreachable end\n" ++
        "    i32.const 27815)\n" ++
        ")\n", .{ probe.array_name, probe.function_name, probe.array_name, wasm_elem_ty, wasm_elem_ty });
}

fn append_scalar_list_update_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: ScalarListProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    const wasm_elem_ty = codegen_gc_layout.scalar_array_wasm_elem_type(probe.elem_ty);
    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $original (ref {s}))\n" ++
        "    (local $updated (ref null {s}))\n" ++
        "    {s}.const 7\n" ++
        "    {s}.const 12\n" ++
        "    {s}.const 17\n" ++
        "    array.new_fixed {s} 3\n" ++
        "    local.tee $original\n" ++
        "    call ${s}\n" ++
        "    local.set $updated\n" ++
        "    local.get $original\n" ++
        "    i32.const 1\n" ++
        "    array.get {s}\n" ++
        "    {s}.const 12\n" ++
        "    {s}.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 1\n" ++
        "    array.get {s}\n" ++
        "    {s}.const 65\n" ++
        "    {s}.ne\n" ++
        "    if unreachable end\n" ++
        "    i32.const 27815)\n" ++
        ")\n", .{
        probe.array_name,
        probe.array_name,
        wasm_elem_ty,
        wasm_elem_ty,
        wasm_elem_ty,
        probe.array_name,
        probe.function_name,
        probe.array_name,
        wasm_elem_ty,
        wasm_elem_ty,
        probe.array_name,
        wasm_elem_ty,
        wasm_elem_ty,
    });
}

fn append_scalar_list_put_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: ScalarListPutProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    const wasm_elem_ty = codegen_gc_layout.scalar_array_wasm_elem_type(probe.elem_ty);
    const wasm_const = if (std.mem.eql(u8, wasm_elem_ty, "i32"))
        "i32.const"
    else if (std.mem.eql(u8, wasm_elem_ty, "i64"))
        "i64.const"
    else if (std.mem.eql(u8, wasm_elem_ty, "f32"))
        "f32.const"
    else
        "f64.const";
    const wasm_ne = if (std.mem.eql(u8, wasm_elem_ty, "i32"))
        "i32.ne"
    else if (std.mem.eql(u8, wasm_elem_ty, "i64"))
        "i64.ne"
    else if (std.mem.eql(u8, wasm_elem_ty, "f32"))
        "f32.ne"
    else
        "f64.ne";
    const value_65 = if (std.mem.eql(u8, wasm_elem_ty, "f32") or std.mem.eql(u8, wasm_elem_ty, "f64")) "65.0" else "65";
    const value_66 = if (std.mem.eql(u8, wasm_elem_ty, "f32") or std.mem.eql(u8, wasm_elem_ty, "f64")) "66.0" else "66";

    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $original (ref {s}))\n" ++
        "    (local $first (ref null {s}))\n" ++
        "    (local $second (ref null {s}))\n" ++
        "    {s} 1\n" ++
        "    {s} 2\n" ++
        "    {s} 3\n" ++
        "    array.new_fixed {s} 3\n" ++
        "    local.tee $original\n" ++
        "    {s} {s}\n" ++
        "    call ${s}\n" ++
        "    local.set $first\n" ++
        "    local.get $original\n" ++
        "    {s} {s}\n" ++
        "    call ${s}\n" ++
        "    local.set $second\n" ++
        "    local.get $first\n" ++
        "    local.get $second\n" ++
        "    ref.eq\n" ++
        "    if unreachable end\n", .{
        probe.array_name,
        probe.array_name,
        probe.array_name,
        wasm_const,
        wasm_const,
        wasm_const,
        probe.array_name,
        wasm_const,
        value_65,
        probe.function_name,
        wasm_const,
        value_66,
        probe.function_name,
    });

    try append_scalar_array_value_check(allocator, out, probe.array_name, "$original", wasm_const, wasm_ne, 0, "1", false);
    try append_scalar_array_value_check(allocator, out, probe.array_name, "$original", wasm_const, wasm_ne, 1, "2", false);
    try append_scalar_array_value_check(allocator, out, probe.array_name, "$original", wasm_const, wasm_ne, 2, "3", false);
    try append_scalar_array_length_check(allocator, out, "$first", 4);
    try append_scalar_array_value_check(allocator, out, probe.array_name, "$first", wasm_const, wasm_ne, 0, "1", true);
    try append_scalar_array_value_check(allocator, out, probe.array_name, "$first", wasm_const, wasm_ne, 1, "2", true);
    try append_scalar_array_value_check(allocator, out, probe.array_name, "$first", wasm_const, wasm_ne, 2, "3", true);
    try append_scalar_array_value_check(allocator, out, probe.array_name, "$first", wasm_const, wasm_ne, 3, value_65, true);
    try append_scalar_array_length_check(allocator, out, "$second", 4);
    try append_scalar_array_value_check(allocator, out, probe.array_name, "$second", wasm_const, wasm_ne, 3, value_66, true);
    try out.appendSlice(allocator, "    i32.const 27815)\n)\n");
}

fn append_scalar_array_length_check(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    local_name: []const u8,
    expected: u32,
) !void {
    try append_fmt(allocator, out, "    local.get {s}\n    ref.as_non_null\n    array.len\n    i32.const {d}\n    i32.ne\n    if unreachable end\n", .{ local_name, expected });
}

fn append_scalar_array_value_check(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    array_name: []const u8,
    local_name: []const u8,
    wasm_const: []const u8,
    wasm_ne: []const u8,
    index: u32,
    expected: []const u8,
    nullable: bool,
) !void {
    try append_fmt(allocator, out, "    local.get {s}\n", .{local_name});
    if (nullable) try out.appendSlice(allocator, "    ref.as_non_null\n");
    try append_fmt(allocator, out, "    i32.const {d}\n    array.get {s}\n    {s} {s}\n    {s}\n    if unreachable end\n", .{ index, array_name, wasm_const, expected, wasm_ne });
}

fn append_managed_struct_call_payload_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: ManagedStructCallPayloadProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    const struct_name = try lowered_wat_name(allocator, probe.struct_name);
    defer allocator.free(struct_name);
    const managed_field_name = try lowered_wat_name(allocator, probe.managed_field_name);
    defer allocator.free(managed_field_name);
    const scalar_field_name = try lowered_wat_name(allocator, probe.scalar_field_name);
    defer allocator.free(scalar_field_name);

    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $original (ref ${s}))\n" ++
        "    (local $updated (ref null ${s}))\n" ++
        "    (local $original_value (ref null $do_bytes))\n" ++
        "    (local $updated_value (ref null $do_bytes))\n", .{ struct_name, struct_name });
    if (probe.managed_field_first) {
        try out.appendSlice(allocator,
            "    i32.const 1\n" ++
                "    i32.const 2\n" ++
                "    i32.const 3\n" ++
                "    array.new_fixed $do_bytes 3\n" ++
                "    i32.const 7\n",
        );
    } else {
        try out.appendSlice(allocator, "    i32.const 7\n" ++
            "    i32.const 1\n" ++
            "    i32.const 2\n" ++
            "    i32.const 3\n" ++
            "    array.new_fixed $do_bytes 3\n");
    }
    try append_fmt(allocator, out, "    struct.new ${s}\n" ++
        "    local.tee $original\n" ++
        "    call ${s}\n" ++
        "    local.set $updated\n" ++
        "    local.get $original\n" ++
        "    local.get $updated\n" ++
        "    ref.eq\n" ++
        "    if unreachable end\n" ++
        "    local.get $original\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} ${s}\n" ++
        "    local.set $original_value\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} ${s}\n" ++
        "    local.set $updated_value\n", .{
        struct_name,
        probe.function_name,
        struct_name,
        managed_field_name,
        struct_name,
        managed_field_name,
    });
    try out.appendSlice(allocator,
        "    local.get $original_value\n" ++
            "    ref.as_non_null\n" ++
            "    array.len\n" ++
            "    i32.const 3\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    local.get $original_value\n" ++
            "    ref.as_non_null\n" ++
            "    i32.const 0\n" ++
            "    array.get_s $do_bytes\n" ++
            "    i32.const 1\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    local.get $original_value\n" ++
            "    ref.as_non_null\n" ++
            "    i32.const 1\n" ++
            "    array.get_s $do_bytes\n" ++
            "    i32.const 2\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    local.get $original_value\n" ++
            "    ref.as_non_null\n" ++
            "    i32.const 2\n" ++
            "    array.get_s $do_bytes\n" ++
            "    i32.const 3\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    local.get $updated_value\n" ++
            "    ref.as_non_null\n" ++
            "    array.len\n" ++
            "    i32.const 2\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    local.get $updated_value\n" ++
            "    ref.as_non_null\n" ++
            "    i32.const 0\n" ++
            "    array.get_s $do_bytes\n" ++
            "    i32.const 1\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    local.get $updated_value\n" ++
            "    ref.as_non_null\n" ++
            "    i32.const 1\n" ++
            "    array.get_s $do_bytes\n" ++
            "    i32.const 2\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n",
    );
    try append_fmt(allocator, out, "    local.get $original\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} ${s}\n" ++
        "    i32.const 7\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} ${s}\n" ++
        "    i32.const 7\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    i32.const 27815)\n)\n", .{ struct_name, scalar_field_name, struct_name, scalar_field_name });
}

fn append_managed_struct_call_text_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: ManagedStructCallTextProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    const struct_name = try lowered_wat_name(allocator, probe.struct_name);
    defer allocator.free(struct_name);
    const managed_field_name = try lowered_wat_name(allocator, probe.managed_field_name);
    defer allocator.free(managed_field_name);
    const scalar_field_name = try lowered_wat_name(allocator, probe.scalar_field_name);
    defer allocator.free(scalar_field_name);

    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $original (ref ${s}))\n" ++
        "    (local $updated (ref null ${s}))\n" ++
        "    (local $original_value (ref null $do_text))\n" ++
        "    (local $updated_value (ref null $do_text))\n", .{ struct_name, struct_name });
    if (probe.managed_field_first) {
        try out.appendSlice(allocator,
            "    i32.const 3\n" ++
                "    i32.const 111\n" ++
                "    i32.const 108\n" ++
                "    i32.const 100\n" ++
                "    array.new_fixed $do_bytes 3\n" ++
                "    struct.new $do_text\n" ++
                "    i32.const 7\n",
        );
    } else {
        try out.appendSlice(allocator,
            "    i32.const 7\n" ++
                "    i32.const 3\n" ++
                "    i32.const 111\n" ++
                "    i32.const 108\n" ++
                "    i32.const 100\n" ++
                "    array.new_fixed $do_bytes 3\n" ++
                "    struct.new $do_text\n",
        );
    }
    try append_fmt(allocator, out, "    struct.new ${s}\n" ++
        "    local.tee $original\n" ++
        "    call ${s}\n" ++
        "    local.set $updated\n" ++
        "    local.get $original\n" ++
        "    local.get $updated\n" ++
        "    ref.eq\n" ++
        "    if unreachable end\n" ++
        "    local.get $original\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} ${s}\n" ++
        "    local.set $original_value\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} ${s}\n" ++
        "    local.set $updated_value\n", .{
        struct_name,
        probe.function_name,
        struct_name,
        managed_field_name,
        struct_name,
        managed_field_name,
    });
    try out.appendSlice(allocator,
        "    local.get $original_value\n" ++
            "    ref.as_non_null\n" ++
            "    struct.get $do_text $length\n" ++
            "    i32.const 3\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    local.get $updated_value\n" ++
            "    ref.as_non_null\n" ++
            "    struct.get $do_text $length\n" ++
            "    i32.const 5\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    local.get $updated_value\n" ++
            "    ref.as_non_null\n" ++
            "    struct.get $do_text $bytes\n" ++
            "    ref.as_non_null\n" ++
            "    i32.const 0\n" ++
            "    array.get_s $do_bytes\n" ++
            "    i32.const 102\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n",
    );
    try append_fmt(allocator, out, "    local.get $original\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} ${s}\n" ++
        "    i32.const 7\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} ${s}\n" ++
        "    i32.const 7\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    i32.const 27815)\n)\n", .{ struct_name, scalar_field_name, struct_name, scalar_field_name });
}

fn append_managed_struct_payload_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: ManagedStructPayloadProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    const struct_name = try lowered_wat_name(allocator, probe.struct_name);
    defer allocator.free(struct_name);
    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $original (ref ${s}))\n" ++
        "    (local $replacement (ref $do_bytes))\n" ++
        "    (local $updated (ref null ${s}))\n", .{ struct_name, struct_name });
    if (probe.managed_field_first) {
        try out.appendSlice(allocator, "    i32.const 1\n    i32.const 2\n    i32.const 3\n    array.new_fixed $do_bytes 3\n    i32.const 7\n");
    } else {
        try out.appendSlice(allocator, "    i32.const 7\n    i32.const 1\n    i32.const 2\n    i32.const 3\n    array.new_fixed $do_bytes 3\n");
    }
    try append_fmt(allocator, out, "    struct.new ${s}\n" ++
        "    local.tee $original\n" ++
        "    i32.const 65\n" ++
        "    i32.const 66\n" ++
        "    array.new_fixed $do_bytes 2\n" ++
        "    local.tee $replacement\n" ++
        "    call ${s}\n" ++
        "    local.set $updated\n" ++
        "    local.get $original\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    ref.eq\n" ++
        "    if unreachable end\n", .{ struct_name, probe.function_name });
    try append_managed_field_checks(allocator, out, struct_name, probe.managed_field_name, "original", 3, &.{ 1, 2, 3 });
    try append_scalar_field_check(allocator, out, struct_name, probe.scalar_field_name, "original");
    try append_managed_field_checks(allocator, out, struct_name, probe.managed_field_name, "updated", 2, &.{ 65, 66 });
    try append_scalar_field_check(allocator, out, struct_name, probe.scalar_field_name, "updated");
    try out.appendSlice(allocator, "    i32.const 27815)\n)\n");
}

fn append_managed_scalar_array_field_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: ManagedScalarArrayFieldProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    const struct_name = try lowered_wat_name(allocator, probe.struct_name);
    defer allocator.free(struct_name);
    const managed_field_name = try lowered_wat_name(allocator, probe.managed_field_name);
    defer allocator.free(managed_field_name);
    const scalar_field_name = try lowered_wat_name(allocator, probe.scalar_field_name);
    defer allocator.free(scalar_field_name);
    const managed_spec = codegen_gc_layout.scalar_array_spec_for_type(probe.managed_field_type) orelse return error.UnsupportedGcSyncProbeSignature;
    const wasm_elem_type = codegen_gc_layout.scalar_array_wasm_elem_type(managed_spec.elem_ty);
    const wasm_const = if (std.mem.eql(u8, wasm_elem_type, "i32"))
        "i32.const"
    else if (std.mem.eql(u8, wasm_elem_type, "i64"))
        "i64.const"
    else if (std.mem.eql(u8, wasm_elem_type, "f32"))
        "f32.const"
    else
        "f64.const";
    const wasm_ne = if (std.mem.eql(u8, wasm_elem_type, "i32"))
        "i32.ne"
    else if (std.mem.eql(u8, wasm_elem_type, "i64"))
        "i64.ne"
    else if (std.mem.eql(u8, wasm_elem_type, "f32"))
        "f32.ne"
    else
        "f64.ne";
    const original_values: [3][]const u8 = if (std.mem.eql(u8, wasm_elem_type, "i32") or std.mem.eql(u8, wasm_elem_type, "i64"))
        .{ "1", "0", "1" }
    else
        .{ "1.0", "0.0", "1.0" };
    const replacement_values: [2][]const u8 = if (std.mem.eql(u8, wasm_elem_type, "i32") or std.mem.eql(u8, wasm_elem_type, "i64"))
        .{ "0", "1" }
    else
        .{ "0.0", "1.0" };

    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $original (ref ${s}))\n" ++
        "    (local $replacement (ref {s}))\n" ++
        "    (local $updated (ref null ${s}))\n", .{ struct_name, probe.managed_array_name, struct_name });
    if (probe.managed_field_first) {
        for (original_values) |value| try append_fmt(allocator, out, "    {s} {s}\n", .{ wasm_const, value });
        try append_fmt(allocator, out, "    array.new_fixed {s} 3\n    i32.const 7\n", .{probe.managed_array_name});
    } else {
        try out.appendSlice(allocator, "    i32.const 7\n");
        for (original_values) |value| try append_fmt(allocator, out, "    {s} {s}\n", .{ wasm_const, value });
        try append_fmt(allocator, out, "    array.new_fixed {s} 3\n", .{probe.managed_array_name});
    }
    try append_fmt(allocator, out, "    struct.new ${s}\n" ++
        "    local.tee $original\n", .{struct_name});
    for (replacement_values) |value| try append_fmt(allocator, out, "    {s} {s}\n", .{ wasm_const, value });
    try append_fmt(allocator, out, "    array.new_fixed {s} 2\n" ++
        "    local.tee $replacement\n" ++
        "    call ${s}\n" ++
        "    local.set $updated\n" ++
        "    local.get $original\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    ref.eq\n" ++
        "    if unreachable end\n", .{ probe.managed_array_name, probe.function_name });

    try append_fmt(allocator, out, "    local.get $original\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} ${s}\n" ++
        "    ref.as_non_null\n" ++
        "    array.len\n" ++
        "    i32.const 3\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n", .{ struct_name, managed_field_name });
    for (original_values, 0..) |value, index| {
        try append_fmt(allocator, out, "    local.get $original\n" ++
            "    ref.as_non_null\n" ++
            "    struct.get ${s} ${s}\n" ++
            "    ref.as_non_null\n" ++
            "    i32.const {d}\n" ++
            "    array.get {s}\n" ++
            "    {s} {s}\n" ++
            "    {s}\n" ++
            "    if unreachable end\n", .{ struct_name, managed_field_name, index, probe.managed_array_name, wasm_const, value, wasm_ne });
    }
    try append_fmt(allocator, out, "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} ${s}\n" ++
        "    ref.as_non_null\n" ++
        "    array.len\n" ++
        "    i32.const 2\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n", .{ struct_name, managed_field_name });
    for (replacement_values, 0..) |value, index| {
        try append_fmt(allocator, out, "    local.get $updated\n" ++
            "    ref.as_non_null\n" ++
            "    struct.get ${s} ${s}\n" ++
            "    ref.as_non_null\n" ++
            "    i32.const {d}\n" ++
            "    array.get {s}\n" ++
            "    {s} {s}\n" ++
            "    {s}\n" ++
            "    if unreachable end\n", .{ struct_name, managed_field_name, index, probe.managed_array_name, wasm_const, value, wasm_ne });
    }
    try append_fmt(allocator, out, "    local.get $original\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} ${s}\n" ++
        "    i32.const 7\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} ${s}\n" ++
        "    i32.const 7\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    i32.const 27815)\n)\n", .{ struct_name, scalar_field_name, struct_name, scalar_field_name });
}

fn append_nested_managed_struct_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: NestedManagedStructProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    const outer_name = try lowered_wat_name(allocator, probe.outer_name);
    defer allocator.free(outer_name);
    const inner_name = try lowered_wat_name(allocator, probe.inner_name);
    defer allocator.free(inner_name);

    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $original (ref ${s}))\n" ++
        "    (local $old_child (ref ${s}))\n" ++
        "    (local $replacement (ref ${s}))\n" ++
        "    (local $updated (ref null ${s}))\n" ++
        "    i32.const 1\n" ++
        "    i32.const 2\n" ++
        "    i32.const 3\n" ++
        "    array.new_fixed $do_bytes 3\n" ++
        "    struct.new ${s}\n" ++
        "    local.set $old_child\n", .{ outer_name, inner_name, inner_name, outer_name, inner_name });
    if (probe.outer_child_first) {
        try out.appendSlice(allocator, "    local.get $old_child\n    i32.const 7\n");
    } else {
        try out.appendSlice(allocator, "    i32.const 7\n    local.get $old_child\n");
    }
    try append_fmt(allocator, out, "    struct.new ${s}\n" ++
        "    local.tee $original\n" ++
        "    i32.const 65\n" ++
        "    i32.const 66\n" ++
        "    array.new_fixed $do_bytes 2\n" ++
        "    struct.new ${s}\n" ++
        "    local.tee $replacement\n" ++
        "    call ${s}\n" ++
        "    local.set $updated\n" ++
        "    local.get $original\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    ref.eq\n" ++
        "    if unreachable end\n" ++
        "    local.get $original\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} ${s}\n" ++
        "    local.get $old_child\n" ++
        "    ref.eq\n" ++
        "    i32.eqz\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} ${s}\n" ++
        "    local.get $replacement\n" ++
        "    ref.eq\n" ++
        "    i32.eqz\n" ++
        "    if unreachable end\n", .{ outer_name, inner_name, probe.function_name, outer_name, probe.outer_child_field_name, outer_name, probe.outer_child_field_name });
    try append_nested_child_checks(allocator, out, outer_name, probe.outer_child_field_name, inner_name, probe.inner_payload_field_name, "original", 3, &.{ 1, 2, 3 });
    try append_scalar_field_check(allocator, out, outer_name, probe.outer_scalar_field_name, "original");
    try append_nested_child_checks(allocator, out, outer_name, probe.outer_child_field_name, inner_name, probe.inner_payload_field_name, "updated", 2, &.{ 65, 66 });
    try append_scalar_field_check(allocator, out, outer_name, probe.outer_scalar_field_name, "updated");
    try out.appendSlice(allocator, "    i32.const 27815)\n)\n");
}

fn append_nested_managed_scalar_field_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: NestedManagedScalarFieldProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    const outer_name = try lowered_wat_name(allocator, probe.outer_name);
    defer allocator.free(outer_name);
    const inner_name = try lowered_wat_name(allocator, probe.inner_name);
    defer allocator.free(inner_name);

    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $original (ref ${s}))\n" ++
        "    (local $old_child (ref ${s}))\n" ++
        "    (local $updated (ref null ${s}))\n" ++
        "    i32.const 3\n" ++
        "    i32.const 111\n" ++
        "    i32.const 108\n" ++
        "    i32.const 100\n" ++
        "    array.new_fixed $do_bytes 3\n" ++
        "    struct.new ${s}\n" ++
        "    local.set $old_child\n", .{ outer_name, inner_name, outer_name, inner_name });
    if (probe.outer_child_first) {
        try out.appendSlice(allocator, "    local.get $old_child\n    i32.const 7\n");
    } else {
        try out.appendSlice(allocator, "    i32.const 7\n    local.get $old_child\n");
    }
    try append_fmt(allocator, out, "    struct.new ${s}\n" ++
        "    local.tee $original\n" ++
        "    call ${s}\n" ++
        "    local.set $updated\n" ++
        "    local.get $original\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} ${s}\n" ++
        "    local.get $old_child\n" ++
        "    ref.eq\n" ++
        "    i32.eqz\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} ${s}\n" ++
        "    local.get $old_child\n" ++
        "    ref.eq\n" ++
        "    if unreachable end\n", .{
        outer_name,
        probe.function_name,
        outer_name,
        probe.outer_child_field_name,
        outer_name,
        probe.outer_child_field_name,
    });
    try append_nested_scalar_field_check(allocator, out, outer_name, probe.outer_child_field_name, inner_name, probe.inner_scalar_field_name, "original", 3);
    try append_nested_scalar_field_check(allocator, out, outer_name, probe.outer_child_field_name, inner_name, probe.inner_scalar_field_name, "updated", 9);
    try append_nested_child_checks(allocator, out, outer_name, probe.outer_child_field_name, inner_name, probe.inner_payload_field_name, "original", 3, &.{ 111, 108, 100 });
    try append_nested_child_checks(allocator, out, outer_name, probe.outer_child_field_name, inner_name, probe.inner_payload_field_name, "updated", 3, &.{ 111, 108, 100 });
    try append_scalar_field_check(allocator, out, outer_name, probe.outer_scalar_field_name, "original");
    try append_scalar_field_check(allocator, out, outer_name, probe.outer_scalar_field_name, "updated");
    try out.appendSlice(allocator, "    i32.const 27815)\n)\n");
}

fn append_two_level_nested_managed_scalar_field_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: TwoLevelNestedManagedScalarFieldProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    const outer_name = try lowered_wat_name(allocator, probe.outer_name);
    defer allocator.free(outer_name);
    const middle_name = try lowered_wat_name(allocator, probe.middle_name);
    defer allocator.free(middle_name);
    const inner_name = try lowered_wat_name(allocator, probe.inner_name);
    defer allocator.free(inner_name);

    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $original (ref ${s}))\n" ++
        "    (local $old_middle (ref ${s}))\n" ++
        "    (local $old_inner (ref ${s}))\n" ++
        "    (local $updated (ref null ${s}))\n", .{ outer_name, middle_name, inner_name, outer_name });

    if (probe.inner_payload_first) {
        try out.appendSlice(allocator,
            "    i32.const 111\n" ++
                "    i32.const 108\n" ++
                "    i32.const 100\n" ++
                "    array.new_fixed $do_bytes 3\n" ++
                "    i32.const 3\n",
        );
    } else {
        try out.appendSlice(allocator,
            "    i32.const 3\n" ++
                "    i32.const 111\n" ++
                "    i32.const 108\n" ++
                "    i32.const 100\n" ++
                "    array.new_fixed $do_bytes 3\n",
        );
    }
    try append_fmt(allocator, out, "    struct.new ${s}\n    local.set $old_inner\n", .{inner_name});

    if (probe.middle_child_first) {
        try out.appendSlice(allocator, "    local.get $old_inner\n    i32.const 5\n");
    } else {
        try out.appendSlice(allocator, "    i32.const 5\n    local.get $old_inner\n");
    }
    try append_fmt(allocator, out, "    struct.new ${s}\n    local.set $old_middle\n", .{middle_name});

    if (probe.outer_child_first) {
        try out.appendSlice(allocator, "    local.get $old_middle\n    i32.const 7\n");
    } else {
        try out.appendSlice(allocator, "    i32.const 7\n    local.get $old_middle\n");
    }
    try append_fmt(allocator, out, "    struct.new ${s}\n    local.set $original\n    local.get $original\n    call ${s}\n    local.set $updated\n", .{ outer_name, probe.function_name });

    try out.appendSlice(allocator,
        "    local.get $original\n" ++
            "    local.get $updated\n" ++
            "    ref.as_non_null\n" ++
            "    ref.eq\n" ++
            "    if unreachable end\n",
    );
    try append_fmt(allocator, out, "    local.get $updated\n    ref.as_non_null\n    struct.get ${s} ${s}\n    local.get $old_middle\n    ref.eq\n    if unreachable end\n", .{ outer_name, probe.outer_child_field_name });
    try append_fmt(allocator, out, "    local.get $updated\n    ref.as_non_null\n    struct.get ${s} ${s}\n    ref.as_non_null\n    struct.get ${s} ${s}\n    local.get $old_inner\n    ref.eq\n    if unreachable end\n", .{ outer_name, probe.outer_child_field_name, middle_name, probe.middle_child_field_name });

    try append_nested_scalar_chain_check(allocator, out, "original", &.{ outer_name, middle_name, inner_name }, &.{ probe.outer_child_field_name, probe.middle_child_field_name, probe.inner_scalar_field_name }, 3);
    try append_nested_scalar_chain_check(allocator, out, "updated", &.{ outer_name, middle_name, inner_name }, &.{ probe.outer_child_field_name, probe.middle_child_field_name, probe.inner_scalar_field_name }, 9);
    try append_nested_bytes_chain_check(allocator, out, "original", &.{ outer_name, middle_name, inner_name }, &.{ probe.outer_child_field_name, probe.middle_child_field_name, probe.inner_payload_field_name }, 3, &.{ 111, 108, 100 });
    try append_nested_bytes_chain_check(allocator, out, "updated", &.{ outer_name, middle_name, inner_name }, &.{ probe.outer_child_field_name, probe.middle_child_field_name, probe.inner_payload_field_name }, 3, &.{ 111, 108, 100 });
    try append_nested_scalar_chain_check(allocator, out, "original", &.{ outer_name, middle_name }, &.{ probe.outer_child_field_name, probe.middle_scalar_field_name }, 5);
    try append_nested_scalar_chain_check(allocator, out, "original", &.{outer_name}, &.{probe.outer_scalar_field_name}, 7);
    try append_nested_scalar_chain_check(allocator, out, "updated", &.{ outer_name, middle_name }, &.{ probe.outer_child_field_name, probe.middle_scalar_field_name }, 5);
    try append_nested_scalar_chain_check(allocator, out, "updated", &.{outer_name}, &.{probe.outer_scalar_field_name}, 7);
    try out.appendSlice(allocator, "    i32.const 27815)\n)\n");
}

fn append_three_level_nested_managed_scalar_field_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: ThreeLevelNestedManagedScalarFieldProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    const outer_name = try lowered_wat_name(allocator, probe.outer_name);
    defer allocator.free(outer_name);
    const middle_name = try lowered_wat_name(allocator, probe.middle_name);
    defer allocator.free(middle_name);
    const inner_name = try lowered_wat_name(allocator, probe.inner_name);
    defer allocator.free(inner_name);
    const leaf_name = try lowered_wat_name(allocator, probe.leaf_name);
    defer allocator.free(leaf_name);

    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $original (ref ${s}))\n" ++
        "    (local $old_middle (ref ${s}))\n" ++
        "    (local $old_inner (ref ${s}))\n" ++
        "    (local $old_leaf (ref ${s}))\n" ++
        "    (local $updated (ref null ${s}))\n", .{ outer_name, middle_name, inner_name, leaf_name, outer_name });

    if (probe.leaf_scalar_first) {
        try out.appendSlice(allocator, "    i32.const 3\n    i32.const 111\n    i32.const 108\n    i32.const 100\n    array.new_fixed $do_bytes 3\n");
    } else {
        try out.appendSlice(allocator, "    i32.const 111\n    i32.const 108\n    i32.const 100\n    array.new_fixed $do_bytes 3\n    i32.const 3\n");
    }
    try append_fmt(allocator, out, "    struct.new ${s}\n    local.set $old_leaf\n", .{leaf_name});

    if (probe.inner_child_first) {
        try out.appendSlice(allocator, "    local.get $old_leaf\n    i32.const 5\n");
    } else {
        try out.appendSlice(allocator, "    i32.const 5\n    local.get $old_leaf\n");
    }
    try append_fmt(allocator, out, "    struct.new ${s}\n    local.set $old_inner\n", .{inner_name});

    if (probe.middle_child_first) {
        try out.appendSlice(allocator, "    local.get $old_inner\n    i32.const 7\n");
    } else {
        try out.appendSlice(allocator, "    i32.const 7\n    local.get $old_inner\n");
    }
    try append_fmt(allocator, out, "    struct.new ${s}\n    local.set $old_middle\n", .{middle_name});

    if (probe.outer_child_first) {
        try out.appendSlice(allocator, "    local.get $old_middle\n    i32.const 11\n");
    } else {
        try out.appendSlice(allocator, "    i32.const 11\n    local.get $old_middle\n");
    }
    try append_fmt(allocator, out, "    struct.new ${s}\n    local.tee $original\n    call ${s}\n    local.set $updated\n", .{ outer_name, probe.function_name });

    try out.appendSlice(allocator,
        "    local.get $original\n" ++
            "    local.get $updated\n" ++
            "    ref.as_non_null\n" ++
            "    ref.eq\n" ++
            "    if unreachable end\n",
    );
    try append_nested_scalar_chain_check(allocator, out, "original", &.{ outer_name, middle_name, inner_name, leaf_name }, &.{ probe.outer_child_field_name, probe.middle_child_field_name, probe.inner_child_field_name, probe.leaf_scalar_field_name }, 3);
    try append_nested_scalar_chain_check(allocator, out, "updated", &.{ outer_name, middle_name, inner_name, leaf_name }, &.{ probe.outer_child_field_name, probe.middle_child_field_name, probe.inner_child_field_name, probe.leaf_scalar_field_name }, 9);
    try append_nested_bytes_chain_check(allocator, out, "original", &.{ outer_name, middle_name, inner_name, leaf_name }, &.{ probe.outer_child_field_name, probe.middle_child_field_name, probe.inner_child_field_name, probe.leaf_payload_field_name }, 3, &.{ 111, 108, 100 });
    try append_nested_bytes_chain_check(allocator, out, "updated", &.{ outer_name, middle_name, inner_name, leaf_name }, &.{ probe.outer_child_field_name, probe.middle_child_field_name, probe.inner_child_field_name, probe.leaf_payload_field_name }, 3, &.{ 111, 108, 100 });
    try append_nested_scalar_chain_check(allocator, out, "original", &.{ outer_name, middle_name, inner_name }, &.{ probe.outer_child_field_name, probe.middle_child_field_name, probe.inner_scalar_field_name }, 5);
    try append_nested_scalar_chain_check(allocator, out, "updated", &.{ outer_name, middle_name, inner_name }, &.{ probe.outer_child_field_name, probe.middle_child_field_name, probe.inner_scalar_field_name }, 5);
    try append_nested_scalar_chain_check(allocator, out, "original", &.{ outer_name, middle_name }, &.{ probe.outer_child_field_name, probe.middle_scalar_field_name }, 7);
    try append_nested_scalar_chain_check(allocator, out, "updated", &.{ outer_name, middle_name }, &.{ probe.outer_child_field_name, probe.middle_scalar_field_name }, 7);
    try append_nested_scalar_chain_check(allocator, out, "original", &.{outer_name}, &.{probe.outer_scalar_field_name}, 11);
    try append_nested_scalar_chain_check(allocator, out, "updated", &.{outer_name}, &.{probe.outer_scalar_field_name}, 11);
    try out.appendSlice(allocator, "    i32.const 27815)\n)\n");
}

fn append_nested_scalar_chain_check(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    local_name: []const u8,
    struct_names: []const []const u8,
    field_names: []const []const u8,
    expected: u32,
) !void {
    if (struct_names.len == 0 or struct_names.len != field_names.len) return error.InvalidGcSyncProbeShape;
    try append_fmt(allocator, out, "    local.get ${s}\n", .{local_name});
    for (struct_names, field_names) |struct_name, field_name| {
        try append_fmt(allocator, out, "    ref.as_non_null\n    struct.get ${s} ${s}\n", .{ struct_name, field_name });
    }
    try append_fmt(allocator, out, "    i32.const {d}\n    i32.ne\n    if unreachable end\n", .{expected});
}

fn append_nested_bytes_chain_check(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    local_name: []const u8,
    struct_names: []const []const u8,
    field_names: []const []const u8,
    length: u32,
    values: []const u32,
) !void {
    if (struct_names.len == 0 or struct_names.len != field_names.len) return error.InvalidGcSyncProbeShape;
    try append_fmt(allocator, out, "    local.get ${s}\n", .{local_name});
    for (struct_names, field_names) |struct_name, field_name| {
        try append_fmt(allocator, out, "    ref.as_non_null\n    struct.get ${s} ${s}\n", .{ struct_name, field_name });
    }
    try append_fmt(allocator, out, "    ref.as_non_null\n    array.len\n    i32.const {d}\n    i32.ne\n    if unreachable end\n", .{length});
    for (values, 0..) |value, index| {
        try append_fmt(allocator, out, "    local.get ${s}\n", .{local_name});
        for (struct_names, field_names) |struct_name, field_name| {
            try append_fmt(allocator, out, "    ref.as_non_null\n    struct.get ${s} ${s}\n", .{ struct_name, field_name });
        }
        try append_fmt(allocator, out, "    ref.as_non_null\n    i32.const {d}\n    array.get_s $do_bytes\n    i32.const {d}\n    i32.ne\n    if unreachable end\n", .{ index, value });
    }
}

fn append_managed_tuple_text_bytes_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: ManagedTupleTextBytesProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $original (ref $tuple_text_bytes))\n" ++
        "    (local $updated (ref null $tuple_text_bytes))\n" ++
        "    (local $text (ref $do_text))\n" ++
        "    i32.const 2\n" ++
        "    i32.const 104\n" ++
        "    i32.const 105\n" ++
        "    array.new_fixed $do_bytes 2\n" ++
        "    struct.new $do_text\n" ++
        "    local.tee $text\n" ++
        "    i32.const 1\n" ++
        "    i32.const 2\n" ++
        "    i32.const 3\n" ++
        "    array.new_fixed $do_bytes 3\n" ++
        "    struct.new $tuple_text_bytes\n" ++
        "    local.tee $original\n" ++
        "    call ${s}\n" ++
        "    local.set $updated\n" ++
        "    local.get $original\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    ref.eq\n" ++
        "    if unreachable end\n" ++
        "    local.get $original\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get $tuple_text_bytes $text\n" ++
        "    local.get $text\n" ++
        "    ref.eq\n" ++
        "    i32.eqz\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get $tuple_text_bytes $text\n" ++
        "    local.get $text\n" ++
        "    ref.eq\n" ++
        "    i32.eqz\n" ++
        "    if unreachable end\n" ++
        "    local.get $original\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get $tuple_text_bytes $bytes\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 0\n" ++
        "    array.get_s $do_bytes\n" ++
        "    i32.const 1\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get $tuple_text_bytes $bytes\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 0\n" ++
        "    array.get_s $do_bytes\n" ++
        "    i32.const 65\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    i32.const 27815)\n)\n", .{probe.function_name});
}

fn append_payload_union_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    probe: PayloadUnionProbe,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    const union_name = try lowered_wat_name(allocator, probe.union_name);
    defer allocator.free(union_name);

    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(allocator, out, "  (func (export \"probe\") (result i32)\n" ++
        "    (local $original (ref ${s}))\n" ++
        "    (local $replacement (ref $do_bytes))\n" ++
        "    (local $updated (ref null ${s}))\n" ++
        "    i32.const {d}\n" ++
        "    ref.null $do_bytes\n" ++
        "    struct.new ${s}\n" ++
        "    local.set $original\n" ++
        "    i32.const 1\n" ++
        "    i32.const 2\n" ++
        "    i32.const 3\n" ++
        "    array.new_fixed $do_bytes 3\n" ++
        "    local.set $replacement\n" ++
        "    local.get $original\n" ++
        "    local.get $replacement\n" ++
        "    call ${s}\n" ++
        "    local.set $updated\n" ++
        "    local.get $original\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    ref.eq\n" ++
        "    if unreachable end\n" ++
        "    local.get $original\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} $tag\n" ++
        "    i32.const {d}\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $original\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} $bytes\n" ++
        "    ref.is_null\n" ++
        "    i32.eqz\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} $tag\n" ++
        "    i32.const {d}\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} $bytes\n" ++
        "    local.get $replacement\n" ++
        "    ref.eq\n" ++
        "    i32.eqz\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} $bytes\n" ++
        "    ref.as_non_null\n" ++
        "    array.len\n" ++
        "    i32.const 3\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} $bytes\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 0\n" ++
        "    array.get_s $do_bytes\n" ++
        "    i32.const 1\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} $bytes\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 1\n" ++
        "    array.get_s $do_bytes\n" ++
        "    i32.const 2\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    local.get $updated\n" ++
        "    ref.as_non_null\n" ++
        "    struct.get ${s} $bytes\n" ++
        "    ref.as_non_null\n" ++
        "    i32.const 2\n" ++
        "    array.get_s $do_bytes\n" ++
        "    i32.const 3\n" ++
        "    i32.ne\n" ++
        "    if unreachable end\n" ++
        "    i32.const 27815)\n)\n", .{ union_name, union_name, probe.unit_tag, union_name, probe.function_name, union_name, probe.unit_tag, union_name, union_name, probe.managed_tag, union_name, union_name, union_name, union_name, union_name });
}

fn append_nested_child_checks(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    outer_name: []const u8,
    outer_field_name: []const u8,
    inner_name: []const u8,
    inner_field_name: []const u8,
    local_name: []const u8,
    length: u32,
    values: []const u32,
) !void {
    try append_fmt(allocator, out, "    local.get ${s}\n    ref.as_non_null\n    struct.get ${s} ${s}\n    ref.as_non_null\n    struct.get ${s} ${s}\n    array.len\n    i32.const {d}\n    i32.ne\n    if unreachable end\n", .{ local_name, outer_name, outer_field_name, inner_name, inner_field_name, length });
    for (values, 0..) |value, index| {
        try append_fmt(allocator, out, "    local.get ${s}\n    ref.as_non_null\n    struct.get ${s} ${s}\n    ref.as_non_null\n    struct.get ${s} ${s}\n    i32.const {d}\n    array.get_s $do_bytes\n    i32.const {d}\n    i32.ne\n    if unreachable end\n", .{ local_name, outer_name, outer_field_name, inner_name, inner_field_name, index, value });
    }
}

fn append_nested_scalar_field_check(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    outer_name: []const u8,
    outer_field_name: []const u8,
    inner_name: []const u8,
    inner_field_name: []const u8,
    local_name: []const u8,
    expected: u32,
) !void {
    try append_fmt(allocator, out, "    local.get ${s}\n    ref.as_non_null\n    struct.get ${s} ${s}\n    ref.as_non_null\n    struct.get ${s} ${s}\n    i32.const {d}\n    i32.ne\n    if unreachable end\n", .{ local_name, outer_name, outer_field_name, inner_name, inner_field_name, expected });
}

fn append_managed_field_checks(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    struct_name: []const u8,
    field_name: []const u8,
    local_name: []const u8,
    length: u32,
    values: []const u32,
) !void {
    try append_fmt(allocator, out, "    local.get ${s}\n    ref.as_non_null\n    struct.get ${s} ${s}\n    array.len\n    i32.const {d}\n    i32.ne\n    if unreachable end\n", .{ local_name, struct_name, field_name, length });
    for (values, 0..) |value, index| {
        try append_fmt(allocator, out, "    local.get ${s}\n    ref.as_non_null\n    struct.get ${s} ${s}\n    i32.const {d}\n    array.get_s $do_bytes\n    i32.const {d}\n    i32.ne\n    if unreachable end\n", .{ local_name, struct_name, field_name, index, value });
    }
}

fn append_scalar_field_check(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    struct_name: []const u8,
    field_name: []const u8,
    local_name: []const u8,
) !void {
    try append_fmt(allocator, out, "    local.get ${s}\n    ref.as_non_null\n    struct.get ${s} ${s}\n    i32.const 7\n    i32.ne\n    if unreachable end\n", .{ local_name, struct_name, field_name });
}

fn lowered_wat_name(allocator: std.mem.Allocator, source_name: []const u8) ![]u8 {
    var out = try allocator.alloc(u8, source_name.len);
    for (source_name, 0..) |ch, index| out[index] = std.ascii.toLower(ch);
    return out;
}

fn append_byte_list_put_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    function_name: []const u8,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(
        allocator,
        out,
        "  (func (export \"probe\") (result i32)\n" ++
            "    (local $empty (ref $do_bytes))\n" ++
            "    (local $empty_result (ref null $do_bytes))\n" ++
            "    (local $original (ref $do_bytes))\n" ++
            "    (local $first (ref null $do_bytes))\n" ++
            "    (local $second (ref null $do_bytes))\n" ++
            "    i32.const 0\n" ++
            "    array.new_default $do_bytes\n" ++
            "    local.tee $empty\n" ++
            "    i32.const 42\n" ++
            "    call ${s}\n" ++
            "    local.set $empty_result\n" ++
            "    local.get $empty\n" ++
            "    array.len\n" ++
            "    i32.const 0\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    local.get $empty_result\n" ++
            "    ref.as_non_null\n" ++
            "    array.len\n" ++
            "    i32.const 1\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    local.get $empty_result\n" ++
            "    ref.as_non_null\n" ++
            "    i32.const 0\n" ++
            "    array.get_s $do_bytes\n" ++
            "    i32.const 42\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    i32.const 1\n" ++
            "    i32.const 2\n" ++
            "    i32.const 3\n" ++
            "    array.new_fixed $do_bytes 3\n" ++
            "    local.tee $original\n" ++
            "    i32.const 65\n" ++
            "    call ${s}\n" ++
            "    local.set $first\n" ++
            "    local.get $original\n" ++
            "    i32.const 66\n" ++
            "    call ${s}\n" ++
            "    local.set $second\n" ++
            "    local.get $first\n" ++
            "    local.get $second\n" ++
            "    ref.eq\n" ++
            "    if unreachable end\n" ++
            "    local.get $original\n" ++
            "    array.len\n" ++
            "    i32.const 3\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    local.get $original\n" ++
            "    i32.const 0\n" ++
            "    array.get_s $do_bytes\n" ++
            "    i32.const 1\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    local.get $original\n" ++
            "    i32.const 1\n" ++
            "    array.get_s $do_bytes\n" ++
            "    i32.const 2\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    local.get $original\n" ++
            "    i32.const 2\n" ++
            "    array.get_s $do_bytes\n" ++
            "    i32.const 3\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    local.get $first\n" ++
            "    ref.as_non_null\n" ++
            "    array.len\n" ++
            "    i32.const 4\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    local.get $first\n" ++
            "    ref.as_non_null\n" ++
            "    i32.const 3\n" ++
            "    array.get_s $do_bytes\n" ++
            "    i32.const 65\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    local.get $second\n" ++
            "    ref.as_non_null\n" ++
            "    i32.const 3\n" ++
            "    array.get_s $do_bytes\n" ++
            "    i32.const 66\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    i32.const 27815)\n" ++
            ")\n",
        .{ function_name, function_name, function_name },
    );
}

fn append_byte_list_literal_probe(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    wat: []const u8,
    function_name: []const u8,
) !void {
    const module_end = std.mem.lastIndexOf(u8, wat, ")\n") orelse return error.InvalidGcSyncProbeWat;
    if (module_end + 2 != wat.len) return error.InvalidGcSyncProbeWat;
    try out.appendSlice(allocator, wat[0..module_end]);
    try append_fmt(
        allocator,
        out,
        "  (func (export \"probe\") (result i32)\n" ++
            "    (local $first (ref $do_bytes))\n" ++
            "    (local $second (ref null $do_bytes))\n" ++
            "    call ${s}\n" ++
            "    ref.as_non_null\n" ++
            "    local.set $first\n" ++
            "    call ${s}\n" ++
            "    local.tee $second\n" ++
            "    ref.as_non_null\n" ++
            "    local.get $first\n" ++
            "    ref.eq\n" ++
            "    if unreachable end\n" ++
            "    local.get $first\n" ++
            "    array.len\n" ++
            "    i32.const 3\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    local.get $first\n" ++
            "    i32.const 0\n" ++
            "    array.get_s $do_bytes\n" ++
            "    i32.const 7\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    local.get $first\n" ++
            "    i32.const 1\n" ++
            "    array.get_s $do_bytes\n" ++
            "    i32.const 12\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    local.get $first\n" ++
            "    i32.const 2\n" ++
            "    array.get_s $do_bytes\n" ++
            "    i32.const 17\n" ++
            "    i32.ne\n" ++
            "    if unreachable end\n" ++
            "    i32.const 27815)\n" ++
            ")\n",
        .{ function_name, function_name },
    );
}

fn append_fmt(allocator: std.mem.Allocator, out: *std.ArrayList(u8), comptime format: []const u8, args: anytype) !void {
    const text = try std.fmt.allocPrint(allocator, format, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}

fn is_wat_identifier(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |ch| {
        if (std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '-' or ch == '.') continue;
        return false;
    }
    return true;
}

test "GC sync probe accepts a WAT identifier" {
    try std.testing.expect(is_wat_identifier("replace"));
    try std.testing.expect(is_wat_identifier("rewrite-byte-list"));
    try std.testing.expect(!is_wat_identifier("replace)"));
}

test "GC sync probe classifies fixed and parameterized byte-list updates" {
    const source =
        \\make() -> [u8] {
        \\    return .{1}
        \\}
        \\append(input [u8], value u8) -> [u8] {
        \\    return @put(input, value)
        \\}
        \\update(input [u8]) -> [u8] {
        \\    return @set(input, 0, 65)
        \\}
        \\replace(input [u8], index usize, value u8) -> [u8] {
        \\    return @set(input, index, value)
        \\}
        \\start() {}
    ;
    try std.testing.expectEqual(ProbeCallShape.byte_list_literal, try classify_test_source(source, "make"));
    try std.testing.expectEqual(ProbeCallShape.byte_list_put, try classify_test_source(source, "append"));
    try std.testing.expectEqual(ProbeCallShape.fixed_list_update, try classify_test_source(source, "update"));
    try std.testing.expectEqual(ProbeCallShape.parameterized_list_update, try classify_test_source(source, "replace"));
}

test "GC sync probe classifies a scalar-list put" {
    const source =
        \\append(input [u32], value u32) -> [u32] {
        \\    return @put(input, value)
        \\}
        \\start() {}
    ;
    switch (try classify_test_source(source, "append")) {
        .scalar_list_put => |probe| {
            try std.testing.expectEqualStrings("u32", probe.elem_ty);
            try std.testing.expectEqualStrings("$do_u32", probe.array_name);
        },
        else => return error.TestExpectedEqual,
    }
}

test "GC sync probe classifies a text-list put" {
    const source =
        \\append(input [text], value text) -> [text] {
        \\    return @put(input, value)
        \\}
        \\start() {}
    ;
    switch (try classify_test_source(source, "append")) {
        .text_list_put => |probe| try std.testing.expectEqualStrings("append", probe.function_name),
        else => return error.TestExpectedEqual,
    }
}

test "GC sync probe classifies a managed struct list put" {
    const source =
        \\Box {
        \\    value [u8]
        \\    tag i32
        \\}
        \\append(input [Box], value Box) -> [Box] {
        \\    return @put(input, value)
        \\}
        \\start() {}
    ;
    const shape = try classify_test_source(source, "append");
    switch (shape) {
        .managed_struct_list_put => {},
        else => return error.TestExpectedEqual,
    }
}

test "GC sync probe classifies managed struct payload update" {
    const source =
        \\Box {
        \\    value [u8]
        \\    tag i32
        \\}
        \\update(box Box, value [u8]) -> Box {
        \\    return @set(box, .value, value)
        \\}
        \\start() {}
    ;
    const shape = try classify_test_source(source, "update");
    switch (shape) {
        .managed_struct_payload_update => |probe| {
            try std.testing.expectEqualStrings("Box", probe.struct_name);
            try std.testing.expectEqualStrings("value", probe.managed_field_name);
            try std.testing.expectEqualStrings("tag", probe.scalar_field_name);
        },
        else => return error.TestExpectedEqual,
    }
}

test "GC sync probe classifies a direct call-produced managed payload update" {
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
    switch (try classify_test_source(source, "replace")) {
        .managed_struct_call_payload_update => |probe| {
            try std.testing.expectEqualStrings("replace", probe.function_name);
            try std.testing.expectEqualStrings("make", probe.producer_name);
            try std.testing.expectEqualStrings("Box", probe.struct_name);
            try std.testing.expectEqualStrings("value", probe.managed_field_name);
            try std.testing.expectEqualStrings("tag", probe.scalar_field_name);
        },
        else => return error.TestExpectedEqual,
    }
}

test "GC sync probe classifies a direct call-produced managed text update" {
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
    switch (try classify_test_source(source, "replace")) {
        .managed_struct_call_text_update => |probe| {
            try std.testing.expectEqualStrings("replace", probe.function_name);
            try std.testing.expectEqualStrings("make_text", probe.producer_name);
            try std.testing.expectEqualStrings("Box", probe.struct_name);
            try std.testing.expectEqualStrings("value", probe.managed_field_name);
            try std.testing.expectEqualStrings("tag", probe.scalar_field_name);
        },
        else => return error.TestExpectedEqual,
    }
}

test "GC sync probe classifies nested managed struct update" {
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
    const shape = try classify_test_source(source, "replace");
    switch (shape) {
        .nested_managed_struct_update => |probe| {
            try std.testing.expectEqualStrings("Outer", probe.outer_name);
            try std.testing.expectEqualStrings("inner", probe.outer_child_field_name);
            try std.testing.expectEqualStrings("Inner", probe.inner_name);
            try std.testing.expectEqualStrings("value", probe.inner_payload_field_name);
        },
        else => return error.TestExpectedEqual,
    }
}

test "GC sync probe classifies a two-level nested managed scalar update" {
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
    const shape = try classify_test_source(source, "update");
    switch (shape) {
        .two_level_nested_managed_scalar_field_update => |probe| {
            try std.testing.expectEqualStrings("Outer", probe.outer_name);
            try std.testing.expectEqualStrings("inner", probe.outer_child_field_name);
            try std.testing.expectEqualStrings("Inner", probe.middle_name);
            try std.testing.expectEqualStrings("leaf", probe.middle_child_field_name);
            try std.testing.expectEqualStrings("Leaf", probe.inner_name);
            try std.testing.expectEqualStrings("tag", probe.inner_scalar_field_name);
        },
        else => return error.TestExpectedEqual,
    }
}

test "GC sync probe classifies a three-level nested managed scalar update" {
    const source =
        \\Leaf {
        \\    value [u8]
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
        \\update(outer Outer) -> Outer {
        \\    return @set(outer, .inner, .middle, .leaf, .tag, 9)
        \\}
        \\start() {}
    ;
    const shape = try classify_test_source(source, "update");
    switch (shape) {
        .three_level_nested_managed_scalar_field_update => |probe| {
            try std.testing.expectEqualStrings("Outer", probe.outer_name);
            try std.testing.expectEqualStrings("inner", probe.outer_child_field_name);
            try std.testing.expectEqualStrings("Inner", probe.middle_name);
            try std.testing.expectEqualStrings("middle", probe.middle_child_field_name);
            try std.testing.expectEqualStrings("Middle", probe.inner_name);
            try std.testing.expectEqualStrings("leaf", probe.inner_child_field_name);
            try std.testing.expectEqualStrings("Leaf", probe.leaf_name);
            try std.testing.expectEqualStrings("tag", probe.leaf_scalar_field_name);
        },
        else => return error.TestExpectedEqual,
    }
}

test "GC sync probe classifies managed text byte-list tuple update" {
    const source =
        \\rewrite(pair Tuple<text, [u8]>) -> Tuple<text, [u8]> {
        \\    return Tuple<text, [u8]>{@get(pair, 0), @set(@get(pair, 1), 0, 65)}
        \\}
        \\start() {}
    ;
    const shape = try classify_test_source(source, "rewrite");
    switch (shape) {
        .managed_tuple_text_bytes_update => |probe| try std.testing.expectEqualStrings("rewrite", probe.function_name),
        else => return error.TestExpectedEqual,
    }
}

test "GC sync probe classifies a nested managed byte-list" {
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
    const shape = try classify_test_source(source, "make_nested");
    switch (shape) {
        .nested_byte_list_literal => |probe| try std.testing.expectEqualStrings("make_nested", probe.function_name),
        else => return error.TestExpectedEqual,
    }
}

test "GC sync probe classifies a nested managed byte-list put" {
    const source =
        \\append(rows [[u8]], row [u8]) -> [[u8]] {
        \\    return @put(rows, row)
        \\}
        \\start() {}
    ;
    const shape = try classify_test_source(source, "append");
    switch (shape) {
        .nested_byte_list_put => |probe| try std.testing.expectEqualStrings("append", probe.function_name),
        else => return error.TestExpectedEqual,
    }
}

test "GC sync probe does not classify a scalar field update as managed payload" {
    const source =
        \\Box {
        \\    value [u8]
        \\    tag i32
        \\}
        \\update(box Box, tag i32) -> Box {
        \\    return @set(box, .tag, tag)
        \\}
        \\start() {}
    ;
    try std.testing.expectError(
        error.UnsupportedGcSyncProbeSignature,
        classify_test_source(source, "update"),
    );
}

test "GC sync probe preserves parsed names for a renamed managed payload" {
    const source =
        \\Packet {
        \\    version i32
        \\    bytes [u8]
        \\}
        \\rewrite(packet Packet, next [u8]) -> Packet {
        \\    return @set(packet, .bytes, next)
        \\}
        \\start() {}
    ;
    const shape = try classify_test_source(source, "rewrite");
    switch (shape) {
        .managed_struct_payload_update => |probe| {
            try std.testing.expectEqualStrings("Packet", probe.struct_name);
            try std.testing.expectEqualStrings("bytes", probe.managed_field_name);
            try std.testing.expectEqualStrings("version", probe.scalar_field_name);
            try std.testing.expect(!probe.managed_field_first);
        },
        else => return error.TestExpectedEqual,
    }
}

test "GC sync probe rejects scalar update for a renamed managed payload shape" {
    const source =
        \\Packet {
        \\    version i32
        \\    bytes [u8]
        \\}
        \\rewrite(packet Packet, version i32) -> Packet {
        \\    return @set(packet, .version, version)
        \\}
        \\start() {}
    ;
    try std.testing.expectError(
        error.UnsupportedGcSyncProbeSignature,
        classify_test_source(source, "rewrite"),
    );
}

test "GC sync probe rejects non-direct managed payload producers" {
    const source =
        \\Box {
        \\    value [u8]
        \\    tag i32
        \\}
        \\make() -> [u8] {
        \\    return .{1, 2}
        \\}
        \\update(box Box, value [u8]) -> Box {
        \\    return @set(box, .value, make())
        \\}
        \\start() {}
    ;
    try std.testing.expectError(
        error.UnsupportedGcSyncProbeSignature,
        classify_test_source(source, "update"),
    );
}

test "GC sync probe classifies a parsed payload union update" {
    const source =
        \\Message = Empty | Bytes([u8])
        \\rewrite(value Message, bytes [u8]) -> Message {
        \\    return Bytes(bytes)
        \\}
        \\start() {}
    ;
    const shape = try classify_test_source(source, "rewrite");
    switch (shape) {
        .payload_union_update => |probe| {
            try std.testing.expectEqualStrings("Message", probe.union_name);
            try std.testing.expectEqualStrings("Empty", probe.unit_case);
            try std.testing.expectEqualStrings("Bytes", probe.managed_case);
            try std.testing.expectEqual(@as(u32, 0), probe.unit_tag);
            try std.testing.expectEqual(@as(u32, 1), probe.managed_tag);
        },
        else => return error.TestExpectedEqual,
    }
}

test "GC sync probe classifies a bool list update" {
    const allocator = std.testing.allocator;
    const source =
        \\update(input [bool]) -> [bool] {
        \\    return @set(input, 1, true)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);
    var functions = std.ArrayList(FuncDecl).empty;
    defer {
        codegen_model.free_func_decls(allocator, functions.items);
        functions.deinit(allocator);
    }
    try codegen_collect_functions.collect_gc_sync_func_decls(allocator, tokens, &.{}, &.{}, &.{}, null, &functions);
    const shape = try find_probe_call_shape(functions.items, &.{}, &.{}, "update");
    try std.testing.expect(std.meta.activeTag(shape) == .bool_list_update);
}

test "GC sync probe emits a managed bool array field wrapper" {
    const allocator = std.testing.allocator;
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    const probe = ManagedScalarArrayFieldProbe{
        .function_name = "replace",
        .struct_name = "Box",
        .managed_field_name = "flags",
        .scalar_field_name = "tag",
        .managed_field_first = true,
        .managed_field_type = "[bool]",
        .managed_array_name = "$do_bool",
    };
    try append_managed_scalar_array_field_probe(allocator, &out, "(module)\n", probe);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "array.new_fixed $do_bool 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "array.new_fixed $do_bool 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "call $replace") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "struct.get $box $flags") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "array.get $do_bool") != null);
}

test "GC sync probe classifies a managed bool array field update" {
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
    const shape = try classify_test_source(source, "replace");
    switch (shape) {
        .managed_scalar_array_field_update => |probe| {
            try std.testing.expectEqualStrings("Box", probe.struct_name);
            try std.testing.expectEqualStrings("flags", probe.managed_field_name);
            try std.testing.expectEqualStrings("tag", probe.scalar_field_name);
            try std.testing.expect(probe.managed_field_first);
        },
        else => return error.TestExpectedEqual,
    }
}

test "GC sync probe classifies a managed u32 array field update" {
    const source =
        \\Box {
        \\    values [u32]
        \\    tag i32
        \\}
        \\replace(box Box, values [u32]) -> Box {
        \\    return @set(box, .values, values)
        \\}
        \\start() {}
    ;
    const shape = try classify_test_source(source, "replace");
    switch (shape) {
        .managed_scalar_array_field_update => |probe| {
            try std.testing.expectEqualStrings("Box", probe.struct_name);
            try std.testing.expectEqualStrings("values", probe.managed_field_name);
            try std.testing.expectEqualStrings("tag", probe.scalar_field_name);
            try std.testing.expectEqualStrings("[u32]", probe.managed_field_type);
            try std.testing.expectEqualStrings("$do_u32", probe.managed_array_name);
        },
        else => return error.TestExpectedEqual,
    }
}

test "GC sync probe classifies a managed i16 array field update" {
    const source =
        \\Box {
        \\    values [i16]
        \\    tag i32
        \\}
        \\replace(box Box, values [i16]) -> Box {
        \\    return @set(box, .values, values)
        \\}
        \\start() {}
    ;
    const shape = try classify_test_source(source, "replace");
    switch (shape) {
        .managed_scalar_array_field_update => |probe| {
            try std.testing.expectEqualStrings("Box", probe.struct_name);
            try std.testing.expectEqualStrings("values", probe.managed_field_name);
            try std.testing.expectEqualStrings("[i16]", probe.managed_field_type);
            try std.testing.expectEqualStrings("$do_i16", probe.managed_array_name);
        },
        else => return error.TestExpectedEqual,
    }
}

test "GC sync probe classifies remaining scalar array field updates" {
    const cases = .{
        .{ "i8", "$do_i8" },
        .{ "u16", "$do_u16" },
        .{ "u64", "$do_u64" },
        .{ "isize", "$do_isize" },
        .{ "usize", "$do_usize" },
    };
    inline for (cases) |case| {
        const source = try std.fmt.allocPrint(std.testing.allocator, "Box {{\n    values [{s}]\n    tag i32\n}}\nreplace(box Box, values [{s}]) -> Box {{\n    return @set(box, .values, values)\n}}\nstart() {{}}\n", .{ case[0], case[0] });
        defer std.testing.allocator.free(source);
        const shape = try classify_test_source(source, "replace");
        switch (shape) {
            .managed_scalar_array_field_update => |probe| {
                try std.testing.expectEqualStrings(case[1], probe.managed_array_name);
            },
            else => return error.TestExpectedEqual,
        }
    }
}

test "GC sync probe classifies a managed f32 array field update" {
    const source =
        \\Box {
        \\    values [f32]
        \\    tag i32
        \\}
        \\replace(box Box, values [f32]) -> Box {
        \\    return @set(box, .values, values)
        \\}
        \\start() {}
    ;
    const shape = try classify_test_source(source, "replace");
    switch (shape) {
        .managed_scalar_array_field_update => |probe| {
            try std.testing.expectEqualStrings("Box", probe.struct_name);
            try std.testing.expectEqualStrings("values", probe.managed_field_name);
            try std.testing.expectEqualStrings("[f32]", probe.managed_field_type);
            try std.testing.expectEqualStrings("$do_f32", probe.managed_array_name);
        },
        else => return error.TestExpectedEqual,
    }
}

test "GC sync probe emits a managed f32 array field wrapper" {
    const allocator = std.testing.allocator;
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    const probe = ManagedScalarArrayFieldProbe{
        .function_name = "replace",
        .struct_name = "Box",
        .managed_field_name = "values",
        .scalar_field_name = "tag",
        .managed_field_first = true,
        .managed_field_type = "[f32]",
        .managed_array_name = "$do_f32",
    };
    try append_managed_scalar_array_field_probe(allocator, &out, "(module)\n", probe);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "f32.const 1.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "array.get $do_f32") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "f32.ne") != null);
}

test "GC sync probe classifies a managed f64 array field update" {
    const source =
        \\Box {
        \\    values [f64]
        \\    tag i32
        \\}
        \\replace(box Box, values [f64]) -> Box {
        \\    return @set(box, .values, values)
        \\}
        \\start() {}
    ;
    const shape = try classify_test_source(source, "replace");
    switch (shape) {
        .managed_scalar_array_field_update => |probe| {
            try std.testing.expectEqualStrings("[f64]", probe.managed_field_type);
            try std.testing.expectEqualStrings("$do_f64", probe.managed_array_name);
        },
        else => return error.TestExpectedEqual,
    }
}

test "GC sync probe emits a managed f64 array field wrapper" {
    const allocator = std.testing.allocator;
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    const probe = ManagedScalarArrayFieldProbe{
        .function_name = "replace",
        .struct_name = "Box",
        .managed_field_name = "values",
        .scalar_field_name = "tag",
        .managed_field_first = true,
        .managed_field_type = "[f64]",
        .managed_array_name = "$do_f64",
    };
    try append_managed_scalar_array_field_probe(allocator, &out, "(module)\n", probe);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "f64.const 1.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "array.get $do_f64") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "f64.ne") != null);
}

test "GC sync probe classifies a managed i32 array field update" {
    const source =
        \\Box {
        \\    values [i32]
        \\    tag i32
        \\}
        \\replace(box Box, values [i32]) -> Box {
        \\    return @set(box, .values, values)
        \\}
        \\start() {}
    ;
    const shape = try classify_test_source(source, "replace");
    switch (shape) {
        .managed_scalar_array_field_update => |probe| {
            try std.testing.expectEqualStrings("[i32]", probe.managed_field_type);
            try std.testing.expectEqualStrings("$do_i32", probe.managed_array_name);
        },
        else => return error.TestExpectedEqual,
    }
}

test "GC sync probe classifies an i32 list literal and update" {
    const source =
        \\make() -> [i32] {
        \\    return .{7, 12, 17}
        \\}
        \\update(input [i32]) -> [i32] {
        \\    return @set(input, 1, 65)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var functions = std.ArrayList(FuncDecl).empty;
    defer {
        codegen_model.free_func_decls(std.testing.allocator, functions.items);
        functions.deinit(std.testing.allocator);
    }
    try codegen_collect_functions.collect_gc_sync_func_decls(std.testing.allocator, tokens, &.{}, &.{}, &.{}, null, &functions);
    switch (try find_probe_call_shape(functions.items, &.{}, &.{}, "make")) {
        .i32_list_literal => {},
        else => return error.TestExpectedEqual,
    }
    switch (try find_probe_call_shape(functions.items, &.{}, &.{}, "update")) {
        .i32_list_update => {},
        else => return error.TestExpectedEqual,
    }
}

test "GC sync probe emits a managed i64 array field wrapper" {
    const allocator = std.testing.allocator;
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    const probe = ManagedScalarArrayFieldProbe{
        .function_name = "replace",
        .struct_name = "Box",
        .managed_field_name = "values",
        .scalar_field_name = "tag",
        .managed_field_first = true,
        .managed_field_type = "[i64]",
        .managed_array_name = "$do_i64",
    };
    try append_managed_scalar_array_field_probe(allocator, &out, "(module)\n", probe);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "i64.const 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "array.get $do_i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "i64.ne") != null);
}

test "GC sync probe classifies a managed i64 array field update" {
    const source =
        \\Box {
        \\    values [i64]
        \\    tag i32
        \\}
        \\replace(box Box, values [i64]) -> Box {
        \\    return @set(box, .values, values)
        \\}
        \\start() {}
    ;
    const shape = try classify_test_source(source, "replace");
    switch (shape) {
        .managed_scalar_array_field_update => |probe| {
            try std.testing.expectEqualStrings("[i64]", probe.managed_field_type);
            try std.testing.expectEqualStrings("$do_i64", probe.managed_array_name);
        },
        else => return error.TestExpectedEqual,
    }
}

test "GC sync probe classifies an i64 list literal and update" {
    const source =
        \\make() -> [i64] {
        \\    return .{7, 12, 17}
        \\}
        \\update(input [i64]) -> [i64] {
        \\    return @set(input, 1, 65)
        \\}
        \\start() {}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var functions = std.ArrayList(FuncDecl).empty;
    defer {
        codegen_model.free_func_decls(std.testing.allocator, functions.items);
        functions.deinit(std.testing.allocator);
    }
    try codegen_collect_functions.collect_gc_sync_func_decls(std.testing.allocator, tokens, &.{}, &.{}, &.{}, null, &functions);
    switch (try find_probe_call_shape(functions.items, &.{}, &.{}, "make")) {
        .i64_list_literal => {},
        else => return error.TestExpectedEqual,
    }
    switch (try find_probe_call_shape(functions.items, &.{}, &.{}, "update")) {
        .i64_list_update => {},
        else => return error.TestExpectedEqual,
    }
}

fn classify_test_source(source: []const u8, function_name: []const u8) !ProbeCallShape {
    const allocator = std.testing.allocator;
    const tokens = try lexer.tokenize(allocator, source);
    defer allocator.free(tokens);

    var structs = std.ArrayList(StructDecl).empty;
    defer {
        codegen_model.free_struct_decls(allocator, structs.items);
        structs.deinit(allocator);
    }
    try codegen_collect_structs.collect_struct_decls(allocator, tokens, &structs);

    var layouts = std.ArrayList(StructLayout).empty;
    defer {
        codegen_model.free_struct_layouts(allocator, layouts.items);
        layouts.deinit(allocator);
    }
    try codegen_collect_structs.collect_struct_layouts(allocator, structs.items, &layouts);

    var payload_enums = std.ArrayList(PayloadEnumDecl).empty;
    defer {
        codegen_model.free_payload_enum_decls(allocator, payload_enums.items);
        payload_enums.deinit(allocator);
    }
    try codegen_collect_declarations.collect_payload_enum_decls(allocator, tokens, &payload_enums);

    var functions = std.ArrayList(FuncDecl).empty;
    defer {
        codegen_model.free_func_decls(allocator, functions.items);
        functions.deinit(allocator);
    }
    try codegen_collect_functions.collect_gc_sync_func_decls(allocator, tokens, structs.items, layouts.items, payload_enums.items, null, &functions);
    return find_probe_call_shape(functions.items, structs.items, payload_enums.items, function_name);
}
