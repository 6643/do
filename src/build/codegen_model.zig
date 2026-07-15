//! Immutable codegen declarations, shape records, and ownership helpers.
const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const runtime_prelude_wat = @import("runtime_prelude_wat.zig");
const codegen_union_layout = @import("codegen_union_layout.zig");

const freeUnionLayout = codegen_union_layout.free_union_layout;
const UnionLayout = codegen_union_layout.UnionLayout;
const UnionBranch = codegen_union_layout.UnionBranch;
const unionLayoutsEqual = codegen_union_layout.union_layouts_equal;

pub const SourceOrigin = enum {
    unknown,
    fresh_local,
    param_or_import,
    helper_shared,
    collection_value,
    recv_value,
    loop_source,
    union_payload,
    compiler_temp,
};

pub const Local = struct {
    name: []const u8,
    source_name: ?[]const u8 = null,
    ty: []const u8,
    origin: SourceOrigin = .unknown,
    emit_decl: bool = true,
    release_on_scope_exit: bool = true,
};

pub const StructField = struct {
    name: []const u8,
    ty: []const u8,
    default_start: ?usize = null,
    default_end: usize = 0,
};

pub const StructDecl = struct {
    name: []const u8,
    type_params: []const []const u8 = &.{},
    fields: []const StructField,
    layout_source: ?[]const u8,
    owned_types: []const []const u8 = &.{},
    tokens: []const lexer.Token,
};

pub const ValueEnumBranch = struct {
    name: []const u8,
    value: []const u8,
};

pub const ValueEnumDecl = struct {
    name: []const u8,
    source_name: []const u8,
    carrier: []const u8,
    branches: []const ValueEnumBranch,
    owned_name: bool = false,
};

/// L1 payload enum: `Message = Quit | Text([u8]) | Binary([u8])`.
/// Tags are by case name order (0..); payload slots use max-payload overlap.
pub const PayloadEnumCase = struct {
    name: []const u8,
    /// null = unit case (no payload).
    payload_ty: ?[]const u8,
};

pub const PayloadEnumDecl = struct {
    name: []const u8,
    cases: []const PayloadEnumCase,
    /// Owned type strings for non-ident payload type exprs (none in L1 simple forms usually).
    owned_payload_tys: []const []const u8 = &.{},
    owned_name: bool = false,
};

pub const ManagedFieldOffset = runtime_prelude_wat.ManagedFieldOffset;
pub const StructLayout = runtime_prelude_wat.StructLayout;

pub const StructLocal = struct {
    name: []const u8,
    source_name: ?[]const u8 = null,
    ty: []const u8,
    origin: SourceOrigin = .unknown,
};

pub const TypedStructBinding = struct {
    decl: StructDecl,
    ty: []const u8,
};

pub const StorageLocal = struct {
    name: []const u8,
    source_name: ?[]const u8 = null,
    ty: []const u8,
    elem_ty: []const u8,
    origin: SourceOrigin = .unknown,
};

pub const UnionLocal = struct {
    name: []const u8,
    source_name: ?[]const u8 = null,
    layout: UnionLayout,
    owns_layout: bool = false,
    origin: SourceOrigin = .unknown,
};

pub const InferredUnionBinding = struct {
    layout: UnionLayout,
    owns_layout: bool,
};

pub const NarrowedUnionLocal = struct {
    name: []const u8,
    source_name: ?[]const u8 = null,
    ty: []const u8,
};

pub const FieldMetaLocal = struct {
    name: []const u8,
    struct_name: []const u8,
    decl_index: usize,
    visible_index: usize,
};

pub const EmitOptions = struct {
    component_core: bool = false,
};

pub const NumericSelectTemps = struct {
    left: []const u8,
    right: []const u8,
};
pub const FuncParam = struct {
    name: []const u8,
    ty: []const u8,
    abi_ty: ?[]const u8 = null,
    variadic: bool = false,
    callback: ?OwnedFuncTypeShape = null,
};

pub const GenericTypeBinding = struct {
    name: []const u8,
    ty: []const u8,
};

pub const FuncTypeShape = struct {
    param_types: []const ?[]const u8,
    return_type: ?[]const u8,
};

pub const OwnedFuncTypeShape = struct {
    shape: FuncTypeShape,
    owned: bool,
};

pub const CallbackBindingKind = enum {
    lambda,
    func_ref,
};

pub const CallbackBinding = struct {
    param_name: []const u8,
    shape: FuncTypeShape,
    kind: CallbackBindingKind,
    arg_tokens: []const lexer.Token,
    arg_start: usize,
    arg_end: usize,
    lambda_params: []const []const u8 = &.{},
    body_start: usize = 0,
    body_end: usize = 0,
    func_name: ?[]const u8 = null,
};

pub const LambdaExprShape = struct {
    open_params: usize,
    close_params: usize,
    body_start: usize,
    body_end: usize,
    is_block: bool,
};

pub const CallbackCallArg = struct {
    source_name: []const u8,
    actual_name: ?[]const u8 = null,
    ty: []const u8,
    expr_tokens: []const lexer.Token,
    expr_start: usize,
    expr_end: usize,
};

pub const FuncDecl = struct {
    name: []const u8,
    source_name: []const u8 = "",
    params: []const FuncParam,
    result: ?[]const u8,
    results: []const []const u8,
    result_items: []const FuncResultItem,
    result_struct: ?[]const u8,
    result_union: ?UnionLayout,
    type_params: []const []const u8 = &.{},
    type_bindings: []const GenericTypeBinding = &.{},
    callback_bindings: []const CallbackBinding = &.{},
    is_generic_template: bool = false,
    owned_name: bool = false,
    owned_types: []const []const u8 = &.{},
    tokens: []const lexer.Token,
    start_idx: usize,
    arrow: bool,
    body_start: usize,
    body_end: usize,
};

pub const FuncResultParse = struct {
    types: []const []const u8,
    items: []const FuncResultItem = &.{},
    owns_items: bool = true,
    result_struct: ?[]const u8 = null,
    result_union: ?UnionLayout = null,
};

pub const FuncResultItem = struct {
    ty: []const u8,
    abi_start: usize,
    abi_len: usize,
    union_layout: ?UnionLayout = null,
};

pub const MultiResultLhsKind = enum {
    scalar,
    managed,
    union_value,
    unmanaged_struct,
};

pub const MultiResultLhs = struct {
    name: []const u8,
    ty: []const u8,
    item: FuncResultItem,
    kind: MultiResultLhsKind,
};

pub const NO_RESULT_ITEMS: []const FuncResultItem = &.{};

pub const ParsedCodegenType = struct {
    ty: []const u8,
    next_idx: usize,
};

pub const StructFieldAbiSlot = struct {
    name_suffix: []const u8,
    ty: []const u8,
    offset: usize,
    managed: bool,
};

pub const FuncBodyShape = struct {
    result_start: usize,
    result_end: usize,
    body_start: usize,
    body_end: usize,
    arrow: bool,
    next_idx: usize,
};

pub const StructErrorResult = struct {
    struct_name: []const u8,
    error_name: []const u8,
};

pub const ImportedAliasContext = struct {
    graph: *const imports.ModuleGraph,
    module_idx: usize,
};

pub const UnionStructPayload = struct {
    branch: UnionBranch,
    decl: StructDecl,
};

pub const NilComparisonNarrowing = struct {
    union_local: UnionLocal,
    payload_ty: []const u8,
    non_nil_when_true: bool,
};

pub const IsComparisonNarrowing = struct {
    union_local: UnionLocal,
    payload_ty: []const u8,
};

pub const CodegenError = anyerror;

pub const HostImport = struct {
    alias: []const u8,
    source_alias: []const u8,
    field: []const u8,
    params: []const []const u8,
    result: ?[]const u8,
    tokens: []const lexer.Token,
    owned_alias: bool = false,
};

pub const CodegenImportPrefix = enum {
    local,
    dep,
    std,
};

pub const CodegenImportRef = struct {
    alias: []const u8,
    target: []const u8,
    file_path: []const u8,
    prefix: CodegenImportPrefix,
};

pub const ImportedScalarConst = struct {
    ty: []const u8,
    value: []const u8,
};

pub const ReachVisit = struct {
    module_idx: usize,
    name: []const u8,
    call_idx: ?usize = null,
};

pub const StringData = runtime_prelude_wat.StringData;
// Call-site head parsed from tokens (shared by lower/import).
pub const ExprCallHead = struct {
    name_idx: usize,
    type_args_start: usize = 0,
    type_args_end: usize = 0,
    args_start: usize,
    args_end: usize,
    is_intrinsic: bool,
};

// --- free helpers for owned decl/layout slices ---

pub fn free_callback_bindings(allocator: std.mem.Allocator, bindings: []const CallbackBinding) void {
    for (bindings) |binding| {
        if (binding.lambda_params.len != 0) allocator.free(binding.lambda_params);
    }
    allocator.free(bindings);
}

pub fn free_struct_decls(allocator: std.mem.Allocator, structs: []const StructDecl) void {
    for (structs) |decl| {
        free_struct_decl(allocator, decl);
    }
}

pub fn free_struct_decl(allocator: std.mem.Allocator, decl: StructDecl) void {
    if (decl.type_params.len != 0) allocator.free(decl.type_params);
    for (decl.owned_types) |owned| {
        allocator.free(owned);
    }
    if (decl.owned_types.len != 0) allocator.free(decl.owned_types);
    allocator.free(decl.fields);
}

pub fn free_value_enum_decls(allocator: std.mem.Allocator, value_enums: []const ValueEnumDecl) void {
    for (value_enums) |decl| {
        if (decl.owned_name) allocator.free(decl.name);
        allocator.free(decl.branches);
    }
}

pub fn free_payload_enum_decls(allocator: std.mem.Allocator, payload_enums: []const PayloadEnumDecl) void {
    for (payload_enums) |decl| {
        if (decl.owned_name) allocator.free(decl.name);
        for (decl.owned_payload_tys) |owned| allocator.free(owned);
        if (decl.owned_payload_tys.len != 0) allocator.free(decl.owned_payload_tys);
        allocator.free(decl.cases);
    }
}

pub fn free_struct_layouts(allocator: std.mem.Allocator, layouts: []const StructLayout) void {
    for (layouts) |layout| {
        if (layout.owned_name) allocator.free(layout.name);
        allocator.free(layout.managed_fields);
    }
}

pub fn free_func_params(allocator: std.mem.Allocator, params: []const FuncParam) void {
    for (params) |param| {
        if (param.callback) |callback| {
            if (callback.owned) allocator.free(callback.shape.param_types);
        }
    }
    allocator.free(params);
}

pub fn free_func_decls(allocator: std.mem.Allocator, funcs: []const FuncDecl) void {
    for (funcs) |func| {
        if (func.owned_name) allocator.free(func.name);
        if (func.type_params.len != 0) allocator.free(func.type_params);
        if (func.type_bindings.len != 0) allocator.free(func.type_bindings);
        if (func.callback_bindings.len != 0) free_callback_bindings(allocator, func.callback_bindings);
        free_func_result_items(allocator, func.result_items, func.result_union);
        for (func.owned_types) |owned| {
            allocator.free(owned);
        }
        if (func.owned_types.len != 0) allocator.free(func.owned_types);
        free_func_params(allocator, func.params);
        allocator.free(func.results);
    }
}

pub fn free_func_result_items(allocator: std.mem.Allocator, items: []const FuncResultItem, result_union: ?UnionLayout) void {
    for (items) |item| {
        const layout = item.union_layout orelse continue;
        if (result_union) |single_layout| {
            if (unionLayoutsEqual(layout, single_layout)) continue;
        }
        freeUnionLayout(allocator, layout);
    }
    if (result_union) |layout| freeUnionLayout(allocator, layout);
    allocator.free(items);
}
