const std = @import("std");
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

pub fn value_eq(a: Value, b: Value) bool {
    if (a == .unknown or b == .unknown) return false;
    if (a == .nil and b == .nil) return true;
    if (a == .bool and b == .bool) return a.bool == b.bool;
    if (a == .int and b == .int) return a.int == b.int;
    if (a == .text and b == .text) return std.mem.eql(u8, a.text, b.text);
    if (a == .error_branch and b == .error_branch) return std.mem.eql(u8, a.error_branch.name, b.error_branch.name) and std.mem.eql(u8, a.error_branch.type_name, b.error_branch.type_name);
    if (a == .object and b == .object) return object_eq(a.object, b.object);
    return false;
}
pub fn object_eq(a: []const FieldValue, b: []const FieldValue) bool {
    if (a.len != b.len) return false;
    for (a, 0..) |field, idx| {
        if (!std.mem.eql(u8, field.name, b[idx].name)) return false;
        if (!value_eq(field.value, b[idx].value)) return false;
    }
    return true;
}

pub fn lookup_binding(bindings: []const Binding, name: []const u8) ?Value {
    var i = bindings.len;
    while (i > 0) {
        i -= 1;
        if (std.mem.eql(u8, bindings[i].name, name)) return bindings[i].value;
    }
    return null;
}

pub fn set_binding(allocator: std.mem.Allocator, bindings: *std.ArrayList(Binding), name: []const u8, value: Value) !void {
    var i = bindings.items.len;
    while (i > 0) {
        i -= 1;
        if (!std.mem.eql(u8, bindings.items[i].name, name)) continue;
        free_value(allocator, bindings.items[i].value);
        bindings.items[i].value = value;
        return;
    }
    try bindings.append(allocator, .{ .name = name, .value = value });
}

pub fn free_bindings(allocator: std.mem.Allocator, bindings: []Binding) void {
    for (bindings) |binding| free_value(allocator, binding.value);
}

pub fn free_values(allocator: std.mem.Allocator, values: []const Value) void {
    for (values) |value| free_value(allocator, value);
}

pub fn free_value(allocator: std.mem.Allocator, value: Value) void {
    switch (value) {
        .text => |text| allocator.free(text),
        .object => |fields| {
            for (fields) |field| free_value(allocator, field.value);
            allocator.free(fields);
        },
        else => {},
    }
}

pub fn clone_value(allocator: std.mem.Allocator, value: Value) std.mem.Allocator.Error!Value {
    return switch (value) {
        .text => |text| .{ .text = try allocator.dupe(u8, text) },
        .object => |fields| .{ .object = try clone_fields(allocator, fields) },
        else => value,
    };
}

pub fn clone_fields(allocator: std.mem.Allocator, fields: []const FieldValue) std.mem.Allocator.Error![]FieldValue {
    const out = try allocator.alloc(FieldValue, fields.len);
    errdefer allocator.free(out);
    var idx: usize = 0;
    errdefer {
        for (out[0..idx]) |field| free_value(allocator, field.value);
    }
    for (fields, 0..) |field, i| {
        out[i] = .{ .name = field.name, .value = try clone_value(allocator, field.value) };
        idx += 1;
    }
    return out;
}

pub fn get_object_field(value: Value, name: []const u8) ?Value {
    if (value != .object) return null;
    for (value.object) |field| {
        if (std.mem.eql(u8, field.name, name)) return field.value;
    }
    return null;
}

pub fn set_object_field(allocator: std.mem.Allocator, fields: []const FieldValue, name: []const u8, new_value: Value) !Value {
    const out = try allocator.alloc(FieldValue, fields.len);
    errdefer allocator.free(out);
    var idx: usize = 0;
    errdefer {
        for (out[0..idx]) |field| free_value(allocator, field.value);
    }
    for (fields, 0..) |field, i| {
        out[i].name = field.name;
        out[i].value = if (std.mem.eql(u8, field.name, name))
            new_value
        else
            try clone_value(allocator, field.value);
        idx += 1;
    }
    return .{ .object = out };
}
