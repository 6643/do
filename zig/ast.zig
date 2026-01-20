const std = @import("std");

pub const NodeIndex = u32;

pub const NodeTag = enum {
    root,
    identifier,
    literal_int,
    literal_float,
    literal_text,
    binary_op,
    assign,
    assign_init,
    if_expr,
    loop_expr,
    defer_stmt,
    path_get,
    path_set,
    path_sequence,
    set_entry,
    struct_def,
    field_def,
    fn_def,
    struct_init,
    break_expr,
    continue_expr,
    return_expr,
    param,
    generic_param,
    type_apply,
    call,
    array_literal,
    constraint_def,
    union_def,
    variant_def,
    match_expr,
    match_branch,
    union_literal, // .variant
    tuple_literal,
    tuple_type,
    ffi_decl,
};

pub const IdentifierAttr = packed struct {
    is_private: bool = false,
    is_immutable: bool = false,
};

pub const Node = struct {
    tag: NodeTag,
    main_token: u32,
    is_last_use: bool = false,
    resolved_index: u32 = 0, // Assigned by Sema
    data: union(NodeTag) {
        root: struct {
            children: []const NodeIndex,
        },
        identifier: struct {
            name: []const u8,
            attr: IdentifierAttr,
        },
        literal_int: i64,
        literal_float: f64,
        literal_text: []const u8,
        binary_op: struct {
            lhs: NodeIndex,
            rhs: NodeIndex,
        },
        assign: struct {
            lhs: NodeIndex,
            rhs: NodeIndex,
        },
        assign_init: struct {
            lhs: NodeIndex,
            rhs: NodeIndex,
        },
        if_expr: struct {
            cond: NodeIndex,
            then_body: NodeIndex,
            else_body: NodeIndex,
        },
        loop_expr: struct {
            label_token: u32,
            body: NodeIndex,
        },
        defer_stmt: struct {
            expr: NodeIndex,
        },
        path_get: struct {
            target: NodeIndex,
            path: []const NodeIndex,
        },
        path_set: struct {
            target: NodeIndex,
            entries: []const NodeIndex,
        },
        path_sequence: struct {
            segments: []const NodeIndex,
        },
        set_entry: struct {
            path: NodeIndex,
            value: NodeIndex,
        },
        struct_def: struct {
            name: []const u8,
            generic_params: []const NodeIndex,
            fields: []const NodeIndex,
        },
        field_def: struct {
            name: []const u8,
            type_node: NodeIndex,
            attr: IdentifierAttr,
        },
        fn_def: struct {
            name: []const u8,
            generic_params: []const NodeIndex,
            params: []const NodeIndex,
            body: NodeIndex,
        },
        struct_init: struct {
            type_node: NodeIndex,
            entries: []const NodeIndex,
        },
        break_expr: struct {
            label_token: u32,
            value: NodeIndex,
        },
        continue_expr: struct {
            label_token: u32,
        },
        return_expr: struct {
            value: NodeIndex,
        },
        param: struct {
            name: []const u8,
            type_node: NodeIndex,
        },
        generic_param: struct {
            name: []const u8,
            constraints: []const NodeIndex,
        },
        type_apply: struct {
            base_name: []const u8,
            params: []const NodeIndex,
        },
        call: struct {
            base_node: NodeIndex,
            args: []NodeIndex,
        },
        array_literal: struct {
            elements: []NodeIndex,
        },
        constraint_def: struct {
            name: []const u8,
        },
        union_def: struct {
            name: []const u8,
            generic_params: []const NodeIndex,
            variants: []const NodeIndex,
        },
        variant_def: struct {
            name: []const u8,
            payload_type: NodeIndex, // 0 if no payload
            discriminator: NodeIndex, // 0 if no discriminator
        },
        match_expr: struct {
            target: NodeIndex,
            branches: []const NodeIndex,
        },
        match_branch: struct {
            pattern: NodeIndex, // For now, likely just a path_get (e.g. .circle) or call (e.g. .circle(r))
            body: NodeIndex,
        },
        union_literal: []const u8, // name
        tuple_literal: struct {
            elements: []const NodeIndex,
        },
        tuple_type: struct {
            elements: []const NodeIndex,
        },
        ffi_decl: struct {
            name: []const u8,
            module_name: []const u8,
            fn_name: []const u8,
            params: []const NodeIndex,
            return_type: NodeIndex,
        },
    },
};

pub const Tree = struct {
    nodes: std.ArrayListUnmanaged(Node),
    tokens: []const @import("token.zig").Token,
    source: [:0]const u8,

    pub fn init(source: [:0]const u8, tokens: []const @import("token.zig").Token) Tree {
        return .{
            .nodes = .{},
            .tokens = tokens,
            .source = source,
        };
    }

    pub fn deinit(self: *Tree, allocator: std.mem.Allocator) void {
        self.nodes.deinit(allocator);
    }

    pub fn addNode(self: *Tree, allocator: std.mem.Allocator, node: Node) !NodeIndex {
        const idx = @as(u32, @intCast(self.nodes.items.len));
        try self.nodes.append(allocator, node);
        return idx;
    }
};
