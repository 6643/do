//! Shared semantic-analysis shape types.
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

pub const CallArgInfo = struct {
    name: []const u8,
    arg_index: usize,
    arg_count: usize,
};

pub const LocalImportPrefix = enum {
    local,
    dep,
    std,
};

pub const LambdaArgShape = struct {
    arg_index: usize,
    param_count: usize,
    param_types: []?[]const u8,
    return_type: ?[]const u8,
};

pub const FuncParamShape = union(enum) {
    other,
    value: ?[]const u8,
    variadic: ?[]const u8,
    func: FuncTypeShape,
};

pub const FuncTypeShape = struct {
    param_count: usize,
    param_types: []?[]const u8,
    return_type: ?[]const u8,
};

pub const FuncShape = struct {
    name: []const u8,
    start_idx: usize,
    param_shapes: []FuncParamShape,
    param_min: usize,
    param_max: ?usize,
    return_type: ?[]const u8,
};

pub const CallArgShape = union(enum) {
    other,
    lambda: LambdaArgShape,
    ident: []const u8,
    spread: usize,
};

pub const StructFieldInfo = struct {
    name: []const u8,
    ty: ?[]const u8,
    has_default: bool,
};

pub const StructInfo = struct {
    name: []const u8,
    fields: []const StructFieldInfo,
};

pub const KnownWasiRecordField = struct {
    name: []const u8,
    ty: []const u8,
};

pub const DirectCallSite = struct {
    call: parser.FuncCallRef,
    start_tok_idx: usize,
};

pub const KnownBool = enum {
    yes,
    no,
    unknown,
    no_matching_call,
};

pub const ResolvedFuncTypeShape = struct {
    shape: FuncTypeShape,
    owned: bool,
};

pub const SigTypeParamPair = struct {
    a: []const u8,
    b: []const u8,
};

pub const CallShape = struct {
    name: []const u8,
    start_idx: usize,
    has_explicit_type_args: bool = false,
    arg_shapes: []CallArgShape,
};

pub const ReturnArityResolve = union(enum) {
    unknown,
    arity: usize,
    ambiguous,
};

