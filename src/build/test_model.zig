const lexer = @import("lexer.zig");

pub const Value = union(enum) {
    unsupported,
    unknown,
    nil,
    bool: bool,
    int: i128,
    text: []const u8,
    error_branch: ErrorBranchValue,
    object: []const FieldValue,
};

pub const ErrorBranchValue = struct {
    name: []const u8,
    type_name: []const u8,
};

pub const Binding = struct {
    name: []const u8,
    value: Value,
};

pub const FieldValue = struct {
    name: []const u8,
    value: Value,
};

pub const FuncDecl = struct {
    name: []const u8,
    params_start: usize,
    params_end: usize,
    param_min: usize,
    param_max: ?usize,
    body_start: usize,
    body_end: usize,
    arrow: bool,
    tokens: []const lexer.Token,
};

pub const TestStatus = enum {
    pass,
    fail,
    skip,
};

pub const TestDecl = struct {
    name_lexeme: []const u8,
    body_start: usize,
    body_end: usize,
    line: usize,
    col: usize,
};
