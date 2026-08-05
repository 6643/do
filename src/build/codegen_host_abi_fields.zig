const std = @import("std");
const lexer = @import("lexer.zig");
const model = @import("codegen_model.zig");
const context = @import("codegen_context.zig");
const collect_util = @import("codegen_collect_util.zig");
const collect_structs = @import("codegen_collect_structs.zig");
const collect_declarations = @import("codegen_collect_declarations.zig");
const codegen_imports = @import("codegen_imports.zig");
const codegen_names = @import("codegen_names.zig");
const storage_layout = @import("codegen_storage_layout.zig");
const union_layout = @import("codegen_union_layout.zig");

pub const AbiParam = struct {
    name: []const u8,
    wasm_type: []const u8,
};

pub const AbiParamList = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(AbiParam),
    owned_names: std.ArrayList([]const u8),
    owned_types: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) AbiParamList {
        return .{
            .allocator = allocator,
            .items = .empty,
            .owned_names = .empty,
            .owned_types = .empty,
        };
    }

    pub fn deinit(self: *AbiParamList) void {
        for (self.owned_names.items) |name| self.allocator.free(name);
        self.owned_names.deinit(self.allocator);
        for (self.owned_types.items) |ty| self.allocator.free(ty);
        self.owned_types.deinit(self.allocator);
        self.items.deinit(self.allocator);
    }

    pub fn collect_param(
        self: *AbiParamList,
        param: model.FuncParam,
        tokens: []const lexer.Token,
        ctx: context.CodegenContext,
    ) anyerror!void {
        if (param.callback != null) return error.HostExportCallbackParamUnsupported;
        const abi_ty = collect_util.func_param_abi_type(param);
        try self.collect_type(param.name, abi_ty, tokens, ctx);
    }

    fn collect_type(
        self: *AbiParamList,
        base_name: []const u8,
        ty: []const u8,
        tokens: []const lexer.Token,
        ctx: context.CodegenContext,
    ) anyerror!void {
        if (try self.resolve_union_layout(tokens, ty, ctx)) |layout| {
            defer union_layout.free_union_layout(self.allocator, layout);
            for (layout.payload_tys, 0..) |payload_ty, index| {
                const payload_name = try self.owned_name("{s}.__union_payload_{d}", .{ base_name, index });
                try self.items.append(self.allocator, .{
                    .name = payload_name,
                    .wasm_type = storage_layout.codegen_wasm_type(ctx, payload_ty),
                });
            }
            const tag_name = try self.owned_name("{s}.__union_tag", .{base_name});
            try self.items.append(self.allocator, .{ .name = tag_name, .wasm_type = "i32" });
            return;
        }

        if (storage_layout.is_tuple_type_name(ty)) {
            const arity = storage_layout.tuple_arity(ty) orelse return error.UnsupportedLowering;
            for (0..arity) |index| {
                const elem_ty = storage_layout.tuple_element_type_at(ty, index) orelse return error.UnsupportedLowering;
                const elem_name = try self.owned_name("{s}.{d}", .{ base_name, index });
                try self.collect_type(elem_name, elem_ty, tokens, ctx);
            }
            return;
        }

        if (collect_util.find_struct_decl(ctx.structs, ty)) |decl| {
            if (collect_util.find_struct_layout(ctx.struct_layouts, ty) != null) {
                try self.append_scalar(base_name, ctx, ty);
                return;
            }
            if (decl.type_params.len != 0) {
                try self.collect_generic_struct(base_name, ty, decl, tokens, ctx);
                return;
            }
            try self.collect_struct_fields(base_name, decl, &.{}, tokens, ctx);
            return;
        }

        if (collect_util.generic_type_args_range(ty)) |args| {
            const decl = collect_util.find_struct_decl(ctx.structs, args.base) orelse return error.HostExportGenericStructAbiUnsupported;
            if (decl.type_params.len == 0) return error.HostExportGenericStructAbiUnsupported;
            try self.collect_generic_struct(base_name, ty, decl, tokens, ctx);
            return;
        }

        try self.append_scalar(base_name, ctx, ty);
    }

    fn collect_generic_struct(
        self: *AbiParamList,
        base_name: []const u8,
        concrete_ty: []const u8,
        decl: model.StructDecl,
        tokens: []const lexer.Token,
        ctx: context.CodegenContext,
    ) anyerror!void {
        var bindings = std.ArrayList(model.GenericTypeBinding).empty;
        defer bindings.deinit(self.allocator);
        if (!try collect_structs.bind_struct_type_args(self.allocator, decl, concrete_ty, &bindings, &self.owned_types)) {
            return error.HostExportGenericStructAbiUnsupported;
        }
        try self.collect_struct_fields(base_name, decl, bindings.items, tokens, ctx);
    }

    fn collect_struct_fields(
        self: *AbiParamList,
        base_name: []const u8,
        decl: model.StructDecl,
        bindings: []const model.GenericTypeBinding,
        tokens: []const lexer.Token,
        ctx: context.CodegenContext,
    ) anyerror!void {
        for (decl.fields) |field| {
            const field_ty = try collect_util.substitute_generic_type_owned(
                self.allocator,
                field.ty,
                bindings,
                &self.owned_types,
            );
            const field_name = try self.owned_name("{s}.{s}", .{ base_name, codegen_names.public_decl_name(field.name) });
            try self.collect_type(field_name, field_ty, tokens, ctx);
        }
    }

    fn append_scalar(self: *AbiParamList, name: []const u8, ctx: context.CodegenContext, ty: []const u8) !void {
        try self.items.append(self.allocator, .{ .name = name, .wasm_type = storage_layout.codegen_wasm_type(ctx, ty) });
    }

    fn owned_name(self: *AbiParamList, comptime fmt: []const u8, args: anytype) ![]const u8 {
        const name = try std.fmt.allocPrint(self.allocator, fmt, args);
        errdefer self.allocator.free(name);
        try self.owned_names.append(self.allocator, name);
        return name;
    }

    fn resolve_union_layout(
        self: *AbiParamList,
        tokens: []const lexer.Token,
        ty: []const u8,
        ctx: context.CodegenContext,
    ) !?union_layout.UnionLayout {
        if (codegen_imports.find_payload_enum_decl(ctx.payload_enums, ty)) |decl| {
            return try collect_declarations.build_payload_enum_union_layout(
                self.allocator,
                decl,
                tokens,
                ctx.structs,
                ctx.struct_layouts,
                &self.owned_types,
            );
        }
        return try collect_structs.parse_type_union_layout_from_name(
            self.allocator,
            tokens,
            ty,
            ctx.structs,
            ctx.struct_layouts,
            &self.owned_types,
        );
    }
};

test "host ABI collector expands nested concrete generic struct fields" {
    const fields = [_]model.StructField{ .{ .name = "left", .ty = "T" }, .{ .name = "right", .ty = "T" } };
    const pair_fields = fields[0..];
    const box_fields = [_]model.StructField{.{ .name = "value", .ty = "Pair<T>" }};
    const structs = [_]model.StructDecl{
        .{ .name = "Pair", .type_params = &.{"T"}, .fields = pair_fields, .layout_source = null, .tokens = &.{} },
        .{ .name = "Box", .type_params = &.{"T"}, .fields = &box_fields, .layout_source = null, .tokens = &.{} },
    };
    var string_data = context.StringDataContext{};
    defer string_data.deinit(std.testing.allocator);
    const ctx = context.CodegenContext{
        .functions = &.{},
        .structs = &structs,
        .value_enums = &.{},
        .payload_enums = &.{},
        .struct_layouts = &.{},
        .host_imports = &.{},
        .wasi_imports = &.{},
        .string_data = &string_data,
        .entry_tokens = &.{},
        .modules = &.{},
    };
    var params = AbiParamList.init(std.testing.allocator);
    defer params.deinit();
    try params.collect_param(.{ .name = "box", .ty = "Box<i32>" }, &.{}, ctx);
    try std.testing.expectEqual(@as(usize, 2), params.items.items.len);
    try std.testing.expectEqualStrings("box.value.left", params.items.items[0].name);
    try std.testing.expectEqualStrings("i32", params.items.items[0].wasm_type);
    try std.testing.expectEqualStrings("box.value.right", params.items.items[1].name);
    try std.testing.expectEqualStrings("i32", params.items.items[1].wasm_type);
}

test "host ABI collector keeps a concrete managed field as one handle" {
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
        .payload_enums = &.{},
        .struct_layouts = &.{},
        .host_imports = &.{},
        .wasi_imports = &.{},
        .string_data = &string_data,
        .entry_tokens = &.{},
        .modules = &.{},
    };
    var params = AbiParamList.init(std.testing.allocator);
    defer params.deinit();
    try params.collect_param(.{ .name = "box", .ty = "Box<text>" }, &.{}, ctx);
    try std.testing.expectEqual(@as(usize, 1), params.items.items.len);
    try std.testing.expectEqualStrings("box.value", params.items.items[0].name);
    try std.testing.expectEqualStrings("i32", params.items.items[0].wasm_type);
}

test "host ABI collector expands a generic union field with payload and tag" {
    const fields = [_]model.StructField{.{ .name = "value", .ty = "T|nil" }};
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
        .payload_enums = &.{},
        .struct_layouts = &.{},
        .host_imports = &.{},
        .wasi_imports = &.{},
        .string_data = &string_data,
        .entry_tokens = &.{},
        .modules = &.{},
    };
    var params = AbiParamList.init(std.testing.allocator);
    defer params.deinit();
    try params.collect_param(.{ .name = "box", .ty = "Box<i32>" }, &.{}, ctx);
    try std.testing.expectEqual(@as(usize, 2), params.items.items.len);
    try std.testing.expectEqualStrings("box.value.__union_payload_0", params.items.items[0].name);
    try std.testing.expectEqualStrings("i32", params.items.items[0].wasm_type);
    try std.testing.expectEqualStrings("box.value.__union_tag", params.items.items[1].name);
    try std.testing.expectEqualStrings("i32", params.items.items[1].wasm_type);
}

test "host ABI collector rejects an unresolved generic struct" {
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
        .payload_enums = &.{},
        .struct_layouts = &.{},
        .host_imports = &.{},
        .wasi_imports = &.{},
        .string_data = &string_data,
        .entry_tokens = &.{},
        .modules = &.{},
    };
    var params = AbiParamList.init(std.testing.allocator);
    defer params.deinit();
    try std.testing.expectError(
        error.HostExportGenericStructAbiUnsupported,
        params.collect_param(.{ .name = "box", .ty = "Box" }, &.{}, ctx),
    );
}
