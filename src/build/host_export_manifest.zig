const std = @import("std");
const lexer = @import("lexer.zig");
const model = @import("codegen_model.zig");
const context = @import("codegen_context.zig");
const collect_util = @import("codegen_collect_util.zig");
const storage_layout = @import("codegen_storage_layout.zig");
const host_abi = @import("host_export_abi.zig");

pub fn emit(allocator: std.mem.Allocator, functions: []const model.FuncDecl, entry_tokens: []const lexer.Token, ctx: ?context.CodegenContext) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, "{\"version\":1,\"abi\":\"core-wasm-v1\",\"exports\":[");
    var first = true;
    for (functions) |func| {
        if (!model.is_host_export_func(func, entry_tokens)) continue;
        if (!first) try out.append(allocator, ',');
        first = false;
        try out.appendSlice(allocator, "{\"source_name\":");
        try append_json_string(allocator, &out, func.source_name);
        try out.appendSlice(allocator, ",\"export_name\":");
        try append_json_string(allocator, &out, func.name);
        try append_source_params(allocator, &out, func);
        try append_wasm_params(allocator, &out, func, ctx);
        try append_source_results(allocator, &out, func);
        try append_wasm_results(allocator, &out, func, ctx);
        try out.append(allocator, '}');
    }
    try out.appendSlice(allocator, "]}\n");
    return out.toOwnedSlice(allocator);
}

fn append_source_params(allocator: std.mem.Allocator, out: *std.ArrayList(u8), func: model.FuncDecl) !void {
    try out.appendSlice(allocator, ",\"source_params\":[");
    for (func.params, 0..) |param, idx| {
        if (idx != 0) try out.append(allocator, ',');
        try append_json_string(allocator, out, param.ty);
    }
    try out.append(allocator, ']');
}

fn append_wasm_params(allocator: std.mem.Allocator, out: *std.ArrayList(u8), func: model.FuncDecl, ctx: ?context.CodegenContext) !void {
    try out.appendSlice(allocator, ",\"wasm_params\":[");
    var first = true;
    for (func.params) |param| {
        if (ctx) |codegen_ctx| {
            var wasm_types = std.ArrayList([]const u8).empty;
            defer wasm_types.deinit(allocator);
            try host_abi.append_param_wasm_types(allocator, &wasm_types, param, func.tokens, codegen_ctx);
            for (wasm_types.items) |ty| {
                if (!first) try out.append(allocator, ',');
                first = false;
                try append_json_string(allocator, out, ty);
            }
            continue;
        }
        if (!first) try out.append(allocator, ',');
        first = false;
        try append_json_string(allocator, out, param.ty);
    }
    try out.append(allocator, ']');
}

fn append_source_results(allocator: std.mem.Allocator, out: *std.ArrayList(u8), func: model.FuncDecl) !void {
    try out.appendSlice(allocator, ",\"source_results\":[");
    for (func.results, 0..) |result, idx| {
        if (idx != 0) try out.append(allocator, ',');
        try append_json_string(allocator, out, result);
    }
    try out.append(allocator, ']');
}

fn append_wasm_results(allocator: std.mem.Allocator, out: *std.ArrayList(u8), func: model.FuncDecl, ctx: ?context.CodegenContext) !void {
    try out.appendSlice(allocator, ",\"wasm_results\":[");
    for (func.results, 0..) |result, idx| {
        if (idx != 0) try out.append(allocator, ',');
        const ty = if (ctx) |codegen_ctx| storage_layout.codegen_wasm_type(codegen_ctx, result) else result;
        try append_json_string(allocator, out, ty);
    }
    try out.append(allocator, ']');
}

fn append_json_string(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    try out.append(allocator, '"');
    for (value) |byte| switch (byte) {
        '"' => try out.appendSlice(allocator, "\\\""),
        '\\' => try out.appendSlice(allocator, "\\\\"),
        '\n' => try out.appendSlice(allocator, "\\n"),
        '\r' => try out.appendSlice(allocator, "\\r"),
        '\t' => try out.appendSlice(allocator, "\\t"),
        else => try out.append(allocator, byte),
    };
    try out.append(allocator, '"');
}

test "manifest exports only concrete root public functions" {
    const allocator = std.testing.allocator;
    const tokens = try lexer.tokenize(allocator,
        \\sum(value i32) -> i32 { return value }
        \\.hidden(value i32) -> i32 { return value }
    );
    defer allocator.free(tokens);
    const public = model.FuncDecl{ .name = "sum", .source_name = "sum", .params = &.{.{ .name = "value", .ty = "i32" }}, .result = "i32", .results = &.{"i32"}, .result_items = &.{}, .result_struct = null, .result_union = null, .tokens = tokens, .start_idx = 0, .arrow = false, .body_start = 7, .body_end = 10 };
    const private = model.FuncDecl{ .name = "hidden", .source_name = "hidden", .params = &.{.{ .name = "value", .ty = "i32" }}, .result = "i32", .results = &.{"i32"}, .result_items = &.{}, .result_struct = null, .result_union = null, .tokens = tokens, .start_idx = 12, .arrow = false, .body_start = 19, .body_end = 22 };
    const text = try emit(allocator, &.{ public, private }, tokens, null);
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"export_name\":\"sum\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "hidden") == null);
}
