const std = @import("std");
const model = @import("codegen_model.zig");
const context = @import("codegen_context.zig");
const host_fields = @import("codegen_host_abi_fields.zig");

pub fn validate_func(allocator: std.mem.Allocator, func: model.FuncDecl, ctx: context.CodegenContext) !void {
    for (func.params) |param| {
        // Public exports use only concrete value ABI; callbacks stay guest-private static ids.
        if (param.callback != null) return error.HostExportCallbackParamUnsupported;
        var types = std.ArrayList([]const u8).empty;
        defer types.deinit(allocator);
        try append_param_wasm_types(allocator, &types, param, func.tokens, ctx);
    }
}

pub fn append_param_wasm_types(
    allocator: std.mem.Allocator,
    out: *std.ArrayList([]const u8),
    param: model.FuncParam,
    tokens: []const @import("lexer.zig").Token,
    ctx: context.CodegenContext,
) !void {
    if (param.callback != null) return error.HostExportCallbackParamUnsupported;
    var fields = host_fields.AbiParamList.init(allocator);
    defer fields.deinit();
    try fields.collect_param(param, tokens, ctx);
    for (fields.items.items) |field| {
        try out.append(allocator, field.wasm_type);
    }
}

test "host exports reject callback parameters" {
    const callback = model.OwnedFuncTypeShape{
        .shape = .{ .param_types = &.{}, .return_type = null },
        .owned = false,
    };
    const params = [_]model.FuncParam{.{
        .name = "callback",
        .ty = "F",
        .callback = callback,
    }};
    const func = model.FuncDecl{
        .name = "apply",
        .params = &params,
        .result = null,
        .results = &.{},
        .result_items = &.{},
        .result_struct = null,
        .result_union = null,
        .tokens = &.{},
        .start_idx = 0,
        .arrow = false,
        .body_start = 0,
        .body_end = 0,
    };

    try std.testing.expectError(
        error.HostExportCallbackParamUnsupported,
        validate_func(std.testing.allocator, func, undefined),
    );
}

test "host exports expand concrete generic struct fields" {
    const fields = [_]model.StructField{.{ .name = "value", .ty = "T" }};
    const structs = [_]model.StructDecl{.{
        .name = "Box",
        .type_params = &.{"T"},
        .fields = &fields,
        .layout_source = null,
        .tokens = &.{},
    }};
    var string_data = context.StringDataContext{};
    defer string_data.deinit(std.testing.allocator);
    const ctx = context.CodegenContext{
        .functions = &.{},
        .structs = &structs,
        .value_enums = &.{},
        .struct_layouts = &.{},
        .host_imports = &.{},
        .wasi_imports = &.{},
        .string_data = &string_data,
        .entry_tokens = &.{},
        .modules = &.{},
    };
    const param = model.FuncParam{ .name = "box", .ty = "Box<i32>" };
    var wasm_types = std.ArrayList([]const u8).empty;
    defer wasm_types.deinit(std.testing.allocator);

    try append_param_wasm_types(std.testing.allocator, &wasm_types, param, &.{}, ctx);
    try std.testing.expectEqual(@as(usize, 1), wasm_types.items.len);
    try std.testing.expectEqualStrings("i32", wasm_types.items[0]);
}
