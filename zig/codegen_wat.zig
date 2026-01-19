const std = @import("std");
const ast = @import("ast.zig");
const sema = @import("sema.zig");

pub const CodegenWat = struct {
    allocator: std.mem.Allocator,
    tree: *ast.Tree,
    sema_instance: *sema.Sema,
    output: std.ArrayListUnmanaged(u8),

    pub fn init(allocator: std.mem.Allocator, tree: *ast.Tree, s: *sema.Sema) CodegenWat {
        return .{
            .allocator = allocator,
            .tree = tree,
            .sema_instance = s,
            .output = .{},
        };
    }

    pub fn deinit(self: *CodegenWat) void {
        self.output.deinit(self.allocator);
    }

    pub fn generateModule(self: *CodegenWat, root_idx: ast.NodeIndex) ![]const u8 {
        try self.emit("(module\n");
        try self.emit("  (memory (export \"mem\") 1)\n");

        const root = self.tree.nodes.items[root_idx];
        const children = root.data.root.children;

        for (children) |child_idx| {
            const child = self.tree.nodes.items[child_idx];
            if (child.tag == .fn_def) {
                try self.genFunction(child_idx);
            }
        }

        try self.emit(")\n");
        return self.output.items;
    }

    fn genFunction(self: *CodegenWat, node_idx: ast.NodeIndex) !void {
        const node = self.tree.nodes.items[node_idx];
        const name = node.data.fn_def.name;
        try self.emitFormatted("  (func ${s} (export \"{s}\") (result i32)\n", .{ name, name });
        try self.emit("    (local $tmp_ptr i32) (local $alloc_ptr i32) (local $res i32)\n");

        try self.emitNode(node.data.fn_def.body, 4);
        try self.emit("    i32.const 0\n");
        try self.emit("  )\n\n");
    }

    fn emitNode(self: *CodegenWat, node_idx: ast.NodeIndex, indent: usize) !void {
        if (node_idx == 0) return;
        const node = self.tree.nodes.items[node_idx];
        const type_info = self.sema_instance.node_types.get(node_idx);

        try self.emitIndent(indent);
        switch (node.tag) {
            .root => {
                for (node.data.root.children) |child| try self.emitNode(child, indent);
            },
            .literal_int => {
                try self.emitFormatted("i32.const {d}\n", .{node.data.literal_int});
            },
            .literal_text => {
                try self.emitFormatted("i32.const 0 ;; Text: \"{s}\"\n", .{node.data.literal_text});
            },
            .identifier => {
                try self.emitFormatted("local.get {d} ;; {s}\n", .{ node.resolved_index, node.data.identifier.name });
                if (!node.is_last_use and type_info != null) {
                    try self.emitIndent(indent);
                    try self.emitFormatted(";; Perceus IncRC on {s}\n", .{node.data.identifier.name});
                    try self.emitIndent(indent);
                    try self.emitFormatted("local.set 15 (local.get {d})\n", .{node.resolved_index});
                    try self.emitIndent(indent);
                    try self.emit("local.get 15 (local.get 15 (i32.load offset=0) (i32.const 1) i32.add) i32.store offset=0\n");
                }
            },
            .assign, .assign_init => {
                const lhs_idx = if (node.tag == .assign) node.data.assign.lhs else node.data.assign_init.lhs;
                const rhs_idx = if (node.tag == .assign) node.data.assign.rhs else node.data.assign_init.rhs;
                const lhs = self.tree.nodes.items[lhs_idx];

                try self.emitNode(rhs_idx, 0); 
                try self.emitFormatted("local.set {d}\n", .{lhs.resolved_index});
            },
            .binary_op => {
                try self.emitNode(node.data.binary_op.lhs, 0);
                try self.emitNode(node.data.binary_op.rhs, 0);
                try self.emit("i32.add\n");
            },
            .path_get => {
                try self.emit(";; Path Get\n");
                try self.emitNode(node.data.path_get.target, indent + 2);

                const target_type_p = self.sema_instance.node_types.get(node.data.path_get.target) orelse return;
                var current_offset: u32 = 0;
                var current_type = target_type_p;
                for (node.data.path_get.path, 0..) |seg_idx, i| {
                    const seg = self.tree.nodes.items[seg_idx];
                    var name: []const u8 = undefined;
                    if (seg.tag == .identifier) {
                        name = seg.data.identifier.name;
                    } else if (seg.tag == .literal_int) {
                        var buf: [16]u8 = undefined;
                        name = try std.fmt.bufPrint(&buf, "{d}", .{seg.data.literal_int});
                    } else {
                        return;
                    }

                    var field_info = current_type.fields.get(name);
                    if (field_info == null and name.len > 1 and name[0] == '.') {
                        field_info = current_type.fields.get(name[1..]);
                    }
                    const field = field_info.?;
                    current_offset += field.offset;
                    if (i + 1 < node.data.path_get.path.len) {
                        current_type = self.sema_instance.type_registry.get(field.type_name).?;
                    }
                }
                try self.emitIndent(indent);
                try self.emitFormatted("i32.load offset={d}\n", .{current_offset});
            },
            .path_set => {
                try self.emit(";; Perceus Path Set (In-place Optimization)\n");
                try self.emitNode(node.data.path_set.target, indent + 2);
                try self.emitIndent(indent + 2);
                try self.emit("local.set 15\n");
                try self.emitIndent(indent + 2);
                try self.emit("local.get 15 (i32.load offset=0) (i32.const 1) i32.eq\n");
                try self.emitIndent(indent + 2);
                try self.emit("(if (result i32)\n");
                try self.emitIndent(indent + 4);
                try self.emit("(then\n");
                for (node.data.path_set.entries) |entry_idx| {
                    const entry = self.tree.nodes.items[entry_idx];
                    const target_t = self.sema_instance.node_types.get(node.data.path_set.target).?;

                    var current_offset: u32 = 0;
                    var current_type = target_t;
                    const path_node = self.tree.nodes.items[entry.data.set_entry.path];
                    const segments = if (path_node.tag == .path_sequence) path_node.data.path_sequence.segments else &[_]u32{entry.data.set_entry.path};

                    for (segments, 0..) |seg_idx, i| {
                        const seg = self.tree.nodes.items[seg_idx];
                        var name: []const u8 = undefined;
                        if (seg.tag == .identifier) {
                            name = seg.data.identifier.name;
                        } else if (seg.tag == .literal_int) {
                            var buf: [16]u8 = undefined;
                            name = try std.fmt.bufPrint(&buf, "{d}", .{seg.data.literal_int});
                        } else {
                            return;
                        }

                        var field_info = current_type.fields.get(name);
                        if (field_info == null and name.len > 1 and name[0] == '.') {
                            field_info = current_type.fields.get(name[1..]);
                        }
                        const field = field_info.?;
                        current_offset += field.offset;
                        if (i + 1 < segments.len) {
                            current_type = self.sema_instance.type_registry.get(field.type_name).?;
                        }
                    }

                    try self.emitIndent(indent + 6);
                    try self.emit("local.get 15\n");
                    try self.emitNode(entry.data.set_entry.value, indent + 6);
                    try self.emitIndent(indent + 6);
                    try self.emitFormatted("i32.store offset={d}\n", .{current_offset});
                }
                try self.emitIndent(indent + 6);
                try self.emit("local.get 15)\n");
                try self.emitIndent(indent + 4);
                try self.emit("(else (i32.const 0) ;; Copy and Update (Fallback)\n");
                try self.emitIndent(indent + 4);
                try self.emit("))\n");
            },
            .defer_stmt => {
                const expr = self.tree.nodes.items[node.data.defer_stmt.expr];
                try self.emitFormatted(";; Defer Stmt: {s}\n", .{@tagName(expr.tag)});
                try self.emitNode(node.data.defer_stmt.expr, indent);
                try self.emitIndent(indent);
                try self.emit("drop\n");
            },
            .loop_expr => {
                try self.emit(";; Loop Expr\n");
                try self.emitIndent(indent);
                try self.emit("(block (result i32)\n");
                try self.emitIndent(indent + 2);
                try self.emit("(loop\n");
                try self.emitNode(node.data.loop_expr.body, indent + 4);
                try self.emitIndent(indent + 4);
                try self.emit("br 0\n");
                try self.emitIndent(indent + 2);
                try self.emit(")\n");
                try self.emitIndent(indent);
                try self.emit(")\n");
            },
            .struct_init => {
                const info = type_info orelse return;
                try self.emitFormatted(";; Struct Init: {s}\n", .{info.name});
                try self.emitIndent(indent);
                try self.emit("i32.const 0 (i32.load offset=0) local.set 14\n");
                try self.emitIndent(indent);
                try self.emitFormatted("i32.const 0 (local.get 14 (i32.const {d}) i32.add) i32.store offset=0\n", .{info.total_size});

                try self.emitIndent(indent);
                try self.emit("local.get 14 (i32.const 1) i32.store offset=0 ;; RC\n");
                try self.emitIndent(indent);
                try self.emitFormatted("local.get 14 (i32.const {d}) i32.store offset=4 ;; ID: {s}\n", .{ info.id, info.name });

                for (node.data.struct_init.entries) |entry_idx| {
                    const entry = self.tree.nodes.items[entry_idx];
                    const seg_node = self.tree.nodes.items[entry.data.set_entry.path];
                    const field = info.fields.get(seg_node.data.identifier.name).?;
                    try self.emitIndent(indent);
                    try self.emit("local.get 14\n");
                    try self.emitNode(entry.data.set_entry.value, 0);
                    try self.emitIndent(indent);
                    try self.emitFormatted("i32.store offset={d}\n", .{field.offset});
                }
                try self.emitIndent(indent);
                try self.emit("local.get 14\n");
            },
            .tuple_literal => {
                const info = type_info orelse return;
                try self.emitFormatted(";; Tuple Init: {s}\n", .{info.name});
                try self.emitIndent(indent);
                try self.emit("i32.const 0 (i32.load offset=0) local.set 14\n");
                try self.emitIndent(indent);
                try self.emitFormatted("i32.const 0 (local.get 14 (i32.const {d}) i32.add) i32.store offset=0\n", .{info.total_size});

                try self.emitIndent(indent);
                try self.emit("local.get 14 (i32.const 1) i32.store offset=0 ;; RC\n");
                try self.emitIndent(indent);
                try self.emitFormatted("local.get 14 (i32.const {d}) i32.store offset=4 ;; ID: {s}\n", .{ info.id, info.name });

                for (node.data.tuple_literal.elements, 0..) |elem_idx, i| {
                    var buf: [16]u8 = undefined;
                    const field_name = try std.fmt.bufPrint(&buf, "{d}", .{i});
                    const field = info.fields.get(field_name).?;
                    try self.emitIndent(indent);
                    try self.emit("local.get 14\n");
                    try self.emitNode(elem_idx, 0);
                    try self.emitIndent(indent);
                    try self.emitFormatted("i32.store offset={d}\n", .{field.offset});
                }
                try self.emitIndent(indent);
                try self.emit("local.get 14\n");
            },
            .return_expr => {
                try self.emitNode(node.data.return_expr.value, 0);
                try self.emit("return\n");
            },
            .if_expr => {
                try self.emitNode(node.data.if_expr.cond, 0);
                try self.emit("(if\n");
                try self.emitIndent(indent + 2);
                try self.emit("(then\n");
                try self.emitNode(node.data.if_expr.then_body, indent + 4);
                try self.emitIndent(indent + 2);
                try self.emit(")\n");
                if (node.data.if_expr.else_body != 0) {
                    try self.emitIndent(indent + 2);
                    try self.emit("(else\n");
                    try self.emitNode(node.data.if_expr.else_body, indent + 4);
                    try self.emitIndent(indent + 2);
                    try self.emit(")\n");
                }
                try self.emitIndent(indent);
                try self.emit(")\n");
            },
            else => {
                try self.emitFormatted(";; TODO: NodeTag {s}\n", .{@tagName(node.tag)});
            },
        }
    }

    fn emitIndent(self: *CodegenWat, count: usize) !void {
        var i: usize = 0;
        while (i < count) : (i += 1) try self.emit(" ");
    }

    fn emit(self: *CodegenWat, text: []const u8) !void {
        try self.output.appendSlice(self.allocator, text);
    }

    fn emitFormatted(self: *CodegenWat, comptime fmt: []const u8, args: anytype) !void {
        try self.output.writer(self.allocator).print(fmt, args);
    }
};