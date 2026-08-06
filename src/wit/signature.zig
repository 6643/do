const std = @import("std");
const model = @import("model.zig");

pub const Error = error{InvalidTypeArity};

pub fn render(
    allocator: std.mem.Allocator,
    interface_name: []const u8,
    function: model.FunctionDecl,
) (Error || std.mem.Allocator.Error)![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try append(&out, allocator, interface_name, function);
    return out.toOwnedSlice(allocator);
}

pub fn append(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    interface_name: []const u8,
    function: model.FunctionDecl,
) (Error || std.mem.Allocator.Error)!void {
    try out.append(allocator, '(');
    for (function.params, 0..) |param, index| {
        if (index != 0) try out.appendSlice(allocator, ", ");
        try append_type(out, allocator, param.type_ref, interface_name);
    }
    try out.appendSlice(allocator, ") -> ");
    if (function.is_async) try out.appendSlice(allocator, "Future<");
    if (function.result) |result| {
        try append_type(out, allocator, result, interface_name);
    } else {
        try out.appendSlice(allocator, "nil");
    }
    if (function.is_async) try out.append(allocator, '>');
}

pub fn append_type(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    type_ref: *const model.TypeRef,
    error_alias: []const u8,
) (Error || std.mem.Allocator.Error)!void {
    switch (type_ref.kind) {
        .bool => try out.appendSlice(allocator, "bool"),
        .s8 => try out.appendSlice(allocator, "i8"),
        .u8 => try out.appendSlice(allocator, "u8"),
        .s16 => try out.appendSlice(allocator, "i16"),
        .u16 => try out.appendSlice(allocator, "u16"),
        .s32 => try out.appendSlice(allocator, "i32"),
        .u32 => try out.appendSlice(allocator, "u32"),
        .s64 => try out.appendSlice(allocator, "i64"),
        .u64 => try out.appendSlice(allocator, "u64"),
        .f32 => try out.appendSlice(allocator, "f32"),
        .f64 => try out.appendSlice(allocator, "f64"),
        .char => try out.appendSlice(allocator, "u32"),
        .string => try out.appendSlice(allocator, "text"),
        .unit => try out.appendSlice(allocator, "nil"),
        .named => if (std.mem.eql(u8, type_ref.name, "error"))
            try append_pascal(out, allocator, error_alias, "Error")
        else
            try append_pascal(out, allocator, type_ref.name, null),
        .list => {
            if (type_ref.args.len != 1) return error.InvalidTypeArity;
            try out.append(allocator, '[');
            try append_type(out, allocator, type_ref.args[0], error_alias);
            try out.append(allocator, ']');
        },
        .option => {
            if (type_ref.args.len != 1) return error.InvalidTypeArity;
            try append_type(out, allocator, type_ref.args[0], error_alias);
            try out.appendSlice(allocator, " | nil");
        },
        .result => {
            if (type_ref.args.len != 2) return error.InvalidTypeArity;
            try append_type(out, allocator, type_ref.args[0], error_alias);
            try out.appendSlice(allocator, " | ");
            try append_type(out, allocator, type_ref.args[1], error_alias);
        },
        .future => {
            if (type_ref.args.len != 1) return error.InvalidTypeArity;
            try out.appendSlice(allocator, "Future<");
            try append_type(out, allocator, type_ref.args[0], error_alias);
            try out.append(allocator, '>');
        },
        .stream => {
            if (type_ref.args.len != 1) return error.InvalidTypeArity;
            try out.appendSlice(allocator, "Stream<");
            try append_type(out, allocator, type_ref.args[0], error_alias);
            try out.append(allocator, '>');
        },
        .tuple => {
            if (type_ref.args.len < 2) return error.InvalidTypeArity;
            try out.appendSlice(allocator, "Tuple<");
            for (type_ref.args, 0..) |arg, index| {
                if (index != 0) try out.appendSlice(allocator, ", ");
                try append_type(out, allocator, arg, error_alias);
            }
            try out.append(allocator, '>');
        },
        .own, .borrow => {
            if (type_ref.args.len != 1) return error.InvalidTypeArity;
            try append_type(out, allocator, type_ref.args[0], error_alias);
        },
    }
}

fn append_pascal(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    name: []const u8,
    suffix: ?[]const u8,
) !void {
    var upper = true;
    for (name) |ch| {
        if (ch == '-' or ch == '_' or ch == '.') {
            upper = true;
            continue;
        }
        if (upper) {
            try out.append(allocator, std.ascii.toUpper(ch));
            upper = false;
        } else {
            try out.append(allocator, ch);
        }
    }
    if (suffix) |text| try out.appendSlice(allocator, text);
}
