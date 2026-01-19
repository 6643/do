const std = @import("std");
const ast_mod = @import("ast.zig");
const sema = @import("sema.zig");

pub const CodegenWasm = struct {
    allocator: std.mem.Allocator,
    tree: *ast_mod.Tree,
    sema_instance: *sema.Sema,
    buffer: std.ArrayListUnmanaged(u8),

    const VARIANT_TAG_MASK: u32 = 0x80000000;

    pub fn init(allocator: std.mem.Allocator, tree: *ast_mod.Tree, s: *sema.Sema) CodegenWasm {
        return .{
            .allocator = allocator,
            .tree = tree,
            .sema_instance = s,
            .buffer = .{},
        };
    }

    pub fn deinit(self: *CodegenWasm) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn generate(self: *CodegenWasm, root_idx: ast_mod.NodeIndex) ![]u8 {
        try self.buffer.appendSlice(self.allocator, &[_]u8{ 0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00 });

        var type_sec = std.ArrayListUnmanaged(u8){};
        defer type_sec.deinit(self.allocator);
        try writeUleb128(type_sec.writer(self.allocator), 1);
        try type_sec.appendSlice(self.allocator, &[_]u8{ 0x60, 0x00, 0x01, 0x7f });
        try self.writeSection(1, type_sec.items);

        var func_sec = std.ArrayListUnmanaged(u8){};
        defer func_sec.deinit(self.allocator);
        try writeUleb128(func_sec.writer(self.allocator), 1);
        try writeUleb128(func_sec.writer(self.allocator), 0);
        try self.writeSection(3, func_sec.items);

        var mem_sec = std.ArrayListUnmanaged(u8){};
        defer mem_sec.deinit(self.allocator);
        try writeUleb128(mem_sec.writer(self.allocator), 1);
        try mem_sec.append(self.allocator, 0x00);
        try writeUleb128(mem_sec.writer(self.allocator), 1);
        try self.writeSection(5, mem_sec.items);

        var exp_sec = std.ArrayListUnmanaged(u8){};
        defer exp_sec.deinit(self.allocator);
        try writeUleb128(exp_sec.writer(self.allocator), 1);
        try self.writeString(exp_sec.writer(self.allocator), "_start");
        try exp_sec.append(self.allocator, 0x00);
        try writeUleb128(exp_sec.writer(self.allocator), 0);
        try self.writeSection(7, exp_sec.items);

        var code_sec = std.ArrayListUnmanaged(u8){};
        defer code_sec.deinit(self.allocator);
        try writeUleb128(code_sec.writer(self.allocator), 1);

        var body = std.ArrayListUnmanaged(u8){};
        defer body.deinit(self.allocator);
        try writeUleb128(body.writer(self.allocator), 1);
        try writeUleb128(body.writer(self.allocator), 16); // Locals 0-15
        try body.append(self.allocator, 0x7f); // i32

        try self.emitNode(body.writer(self.allocator), root_idx);

        try body.append(self.allocator, 0x41);
        try body.append(self.allocator, 0x00);
        try body.append(self.allocator, 0x0b);

        try writeUleb128(code_sec.writer(self.allocator), @as(u32, @intCast(body.items.len)));
        try code_sec.appendSlice(self.allocator, body.items);
        try self.writeSection(10, code_sec.items);

        return self.buffer.toOwnedSlice(self.allocator);
    }

    fn emitNode(self: *CodegenWasm, writer: anytype, node_idx: ast_mod.NodeIndex) !void {
        if (node_idx == 0) return;
        const node = self.tree.nodes.items[node_idx];
        const type_info = self.sema_instance.node_types.get(node_idx);

        switch (node.tag) {
            .root => {
                for (node.data.root.children) |child| try self.emitNode(writer, child);
            },
            .literal_int => {
                try writer.writeByte(0x41);
                try writeSleb128(writer, node.data.literal_int);
            },
            .literal_text => {
                try writer.writeByte(0x41);
                try writeSleb128(writer, 0); 
            },
            .identifier => {
                if ((node.resolved_index & VARIANT_TAG_MASK) != 0) {
                     const tag = node.resolved_index & ~VARIANT_TAG_MASK;
                     const info = type_info orelse return;
                     
                     try self.emitAlloc(writer, info.total_size);
                     try writer.writeByte(0x21); // local.set 14
                     try writeUleb128(writer, 14);

                     // Write Tag
                     try writer.writeByte(0x20); try writeUleb128(writer, 14);
                     try writer.writeByte(0x41); try writeSleb128(writer, tag);
                     try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 4);

                     // Write RC=1
                     try writer.writeByte(0x20); try writeUleb128(writer, 14);
                     try writer.writeByte(0x41); try writeSleb128(writer, 1);
                     try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 0);

                     try writer.writeByte(0x20); try writeUleb128(writer, 14);
                } else {
                    try writer.writeByte(0x20); // local.get
                    try writeUleb128(writer, node.resolved_index);

                    if (!node.is_last_use and type_info != null) {
                        try writer.writeByte(0x21); try writeUleb128(writer, 15);
                        try writer.writeByte(0x20); try writeUleb128(writer, 15);
                        try writer.writeByte(0x20); try writeUleb128(writer, 15); // ptr
                        try writer.writeByte(0x20); try writeUleb128(writer, 15); // ptr
                        try writer.writeByte(0x28); try writeUleb128(writer, 2); try writeUleb128(writer, 0); // load RC
                        try writer.writeByte(0x41); try writer.writeByte(0x01);
                        try writer.writeByte(0x6a); // add
                        try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 0); // store
                        try writer.writeByte(0x20); try writeUleb128(writer, 15);
                    }
                }
            },
            .call => {
                if ((node.resolved_index & VARIANT_TAG_MASK) != 0) {
                     const tag = node.resolved_index & ~VARIANT_TAG_MASK;
                     const info = type_info orelse return;

                     try self.emitAlloc(writer, info.total_size);
                     try writer.writeByte(0x21); try writeUleb128(writer, 14);

                     // Tag
                     try writer.writeByte(0x20); try writeUleb128(writer, 14);
                     try writer.writeByte(0x41); try writeSleb128(writer, tag);
                     try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 4);

                     // RC
                     try writer.writeByte(0x20); try writeUleb128(writer, 14);
                     try writer.writeByte(0x41); try writeSleb128(writer, 1);
                     try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 0);

                     // Payload
                     if (node.data.call.args.len > 0) {
                         try writer.writeByte(0x20); try writeUleb128(writer, 14);
                         try self.emitNode(writer, node.data.call.args[0]);
                         try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 8);
                     }

                     try writer.writeByte(0x20); try writeUleb128(writer, 14);

                } else {
                     // TODO: Standard Call
                }
            },
            .match_expr => {
                try self.emitNode(writer, node.data.match_expr.target);
                try writer.writeByte(0x21); try writeUleb128(writer, 13); // target

                try writer.writeByte(0x20); try writeUleb128(writer, 13);
                try writer.writeByte(0x28); try writeUleb128(writer, 2); try writeUleb128(writer, 4);
                try writer.writeByte(0x21); try writeUleb128(writer, 12); // tag

                var else_count: u32 = 0;
                for (node.data.match_expr.branches) |branch_idx| {
                    const branch = self.tree.nodes.items[branch_idx];
                    const pattern_node = self.tree.nodes.items[branch.data.match_branch.pattern];
                    const tag_val = pattern_node.resolved_index & ~VARIANT_TAG_MASK;

                    try writer.writeByte(0x20); try writeUleb128(writer, 12);
                    try writer.writeByte(0x41); try writeSleb128(writer, tag_val);
                    try writer.writeByte(0x46); // eq

                    try writer.writeByte(0x04); // if
                    try writer.writeByte(0x7f); // result
                    
                    if (pattern_node.tag == .call and pattern_node.data.call.args.len > 0) {
                        const arg = self.tree.nodes.items[pattern_node.data.call.args[0]];
                        try writer.writeByte(0x20); try writeUleb128(writer, 13);
                        try writer.writeByte(0x28); try writeUleb128(writer, 2); try writeUleb128(writer, 8);
                        try writer.writeByte(0x21); try writeUleb128(writer, arg.resolved_index);
                    }

                    try self.emitNode(writer, branch.data.match_branch.body);
                    
                    try writer.writeByte(0x05); // else
                    else_count += 1;
                }
                
                try writer.writeByte(0x41); try writeSleb128(writer, 0); 
                while (else_count > 0) {
                    try writer.writeByte(0x0b);
                    else_count -= 1;
                }
            },
            .assign, .assign_init => {
                const lhs_idx = if (node.tag == .assign) node.data.assign.lhs else node.data.assign_init.lhs;
                const rhs_idx = if (node.tag == .assign) node.data.assign.rhs else node.data.assign_init.rhs;
                const lhs = self.tree.nodes.items[lhs_idx];

                if (lhs.tag == .tuple_literal) {
                    try self.emitNode(writer, rhs_idx);
                    try writer.writeByte(0x21); try writeUleb128(writer, 13); // Store tuple ptr in temp 13

                    const rhs_type = self.sema_instance.node_types.get(rhs_idx).?;

                    for (lhs.data.tuple_literal.elements, 0..) |elem_idx, i| {
                        const elem = self.tree.nodes.items[elem_idx];
                        
                        var buf: [16]u8 = undefined;
                        const field_name = try std.fmt.bufPrint(&buf, "{d}", .{i});
                        const field = rhs_type.fields.get(field_name).?;

                        try writer.writeByte(0x20); try writeUleb128(writer, 13); // get tuple ptr
                        try writer.writeByte(0x28); try writeUleb128(writer, 2); try writeUleb128(writer, field.offset); // load field
                        try writer.writeByte(0x21); try writeUleb128(writer, elem.resolved_index); // set local
                    }
                    // No return value for assignment? (Or void)
                } else if (lhs.tag == .call) {
                     try self.emitNode(writer, rhs_idx);
                     try writer.writeByte(0x21); try writeUleb128(writer, 13);

                     try writer.writeByte(0x20); try writeUleb128(writer, 13);
                     try writer.writeByte(0x28); try writeUleb128(writer, 2); try writeUleb128(writer, 4);
                     
                     const expected_tag = lhs.resolved_index & ~VARIANT_TAG_MASK;
                     try writer.writeByte(0x41); try writeSleb128(writer, expected_tag);
                     try writer.writeByte(0x46); // eq

                     try writer.writeByte(0x04); // if
                     try writer.writeByte(0x40);

                     if (lhs.data.call.args.len > 0) {
                         const arg = self.tree.nodes.items[lhs.data.call.args[0]];
                         if (arg.tag == .identifier) {
                             try writer.writeByte(0x20); try writeUleb128(writer, 13);
                             try writer.writeByte(0x28); try writeUleb128(writer, 2); try writeUleb128(writer, 8);
                             try writer.writeByte(0x21); try writeUleb128(writer, arg.resolved_index);
                         }
                     }
                     try writer.writeByte(0x0b);
                } else {
                    try self.emitNode(writer, rhs_idx);
                    try writer.writeByte(0x21); 
                    try writeUleb128(writer, lhs.resolved_index);
                }
            },
            .binary_op => {
                try self.emitNode(writer, node.data.binary_op.lhs);
                try self.emitNode(writer, node.data.binary_op.rhs);
                try writer.writeByte(0x6a); // add
            },
            .struct_init => {
                const info = type_info orelse return;
                try self.emitAlloc(writer, info.total_size);
                try writer.writeByte(0x21); try writeUleb128(writer, 14);

                try writer.writeByte(0x20); try writeUleb128(writer, 14);
                try writer.writeByte(0x41); try writeSleb128(writer, 1);
                try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 0);

                try writer.writeByte(0x20); try writeUleb128(writer, 14);
                try writer.writeByte(0x41); try writeSleb128(writer, info.id);
                try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 4);

                for (node.data.struct_init.entries) |entry_idx| {
                    const entry = self.tree.nodes.items[entry_idx];
                    const seg_node = self.tree.nodes.items[entry.data.set_entry.path];
                    const name = seg_node.data.identifier.name;
                    var field_info = info.fields.get(name);
                    if (field_info == null and name.len > 1 and name[0] == '.') {
                       field_info = info.fields.get(name[1..]);
                    }
                    const field = field_info.?;

                    try writer.writeByte(0x20); try writeUleb128(writer, 14);
                    try self.emitNode(writer, entry.data.set_entry.value);
                    try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, field.offset);
                }
                try writer.writeByte(0x20); try writeUleb128(writer, 14);
            },
            .tuple_literal => {
                const info = type_info orelse return;
                try self.emitAlloc(writer, info.total_size);
                try writer.writeByte(0x21); try writeUleb128(writer, 14);

                // RC=1, ID
                try writer.writeByte(0x20); try writeUleb128(writer, 14);
                try writer.writeByte(0x41); try writeSleb128(writer, 1);
                try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 0);

                try writer.writeByte(0x20); try writeUleb128(writer, 14);
                try writer.writeByte(0x41); try writeSleb128(writer, info.id);
                try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 4);

                for (node.data.tuple_literal.elements, 0..) |elem_idx, i| {
                    var buf: [16]u8 = undefined;
                    const field_name = try std.fmt.bufPrint(&buf, "{d}", .{i});
                    const field = info.fields.get(field_name).?;

                    try writer.writeByte(0x20); try writeUleb128(writer, 14);
                    try self.emitNode(writer, elem_idx);
                    try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, field.offset);
                }
                try writer.writeByte(0x20); try writeUleb128(writer, 14);
            },
            .if_expr => {
                try self.emitNode(writer, node.data.if_expr.cond);
                try writer.writeByte(0x04);
                try writer.writeByte(0x40);
                try self.emitNode(writer, node.data.if_expr.then_body);
                if (node.data.if_expr.else_body != 0) {
                    try writer.writeByte(0x05);
                    try self.emitNode(writer, node.data.if_expr.else_body);
                }
                try writer.writeByte(0x0b);
            },
            .loop_expr => {
                try writer.writeByte(0x02);
                try writer.writeByte(0x7f);
                try writer.writeByte(0x03);
                try writer.writeByte(0x40);
                try self.emitNode(writer, node.data.loop_expr.body);
                try writer.writeByte(0x0c);
                try writeUleb128(writer, 0);
                try writer.writeByte(0x0b);
                try writer.writeByte(0x0b);
            },
            .path_get => {
                try self.emitNode(writer, node.data.path_get.target);
                const target_type = self.sema_instance.node_types.get(node.data.path_get.target) orelse return;
                var current_offset: u32 = 0;
                var current_type = target_type;
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
                try writer.writeByte(0x28); try writeUleb128(writer, 2); try writeUleb128(writer, current_offset);
            },
            .path_set => {
                try self.emitNode(writer, node.data.path_set.target);
                try writer.writeByte(0x21); try writeUleb128(writer, 15);

                try writer.writeByte(0x20); try writeUleb128(writer, 15);
                try writer.writeByte(0x28); try writeUleb128(writer, 2); try writeUleb128(writer, 0);
                try writer.writeByte(0x41); try writer.writeByte(0x01);
                try writer.writeByte(0x46);

                try writer.writeByte(0x04); try writer.writeByte(0x7f);
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
                    try writer.writeByte(0x20); try writeUleb128(writer, 15);
                    try self.emitNode(writer, entry.data.set_entry.value);
                    try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, current_offset);
                }
                try writer.writeByte(0x20); try writeUleb128(writer, 15);
                try writer.writeByte(0x05);
                try writer.writeByte(0x41); try writer.writeByte(0x00);
                try writer.writeByte(0x0b);
            },
            .fn_def => try self.emitNode(writer, node.data.fn_def.body),
            .return_expr => {
                try self.emitNode(writer, node.data.return_expr.value);
                try writer.writeByte(0x0f);
            },
            .break_expr => {
                if (node.data.break_expr.value != 0) try self.emitNode(writer, node.data.break_expr.value);
                try writer.writeByte(0x0c); try writeUleb128(writer, 1);
            },
            .continue_expr => {
                try writer.writeByte(0x0c); try writeUleb128(writer, 0);
            },
            .defer_stmt => {
                try self.emitNode(writer, node.data.defer_stmt.expr);
                try writer.writeByte(0x1a);
            },
            else => {},
        }
    }

    fn emitAlloc(self: *CodegenWasm, writer: anytype, size: u32) !void {
         _ = self;
         try writer.writeByte(0x41); try writeSleb128(writer, 0);
         try writer.writeByte(0x28); try writeUleb128(writer, 2); try writeUleb128(writer, 0);
         try writer.writeByte(0x21); try writeUleb128(writer, 14);

         try writer.writeByte(0x41); try writeSleb128(writer, 0);
         try writer.writeByte(0x20); try writeUleb128(writer, 14);
         try writer.writeByte(0x41); try writeSleb128(writer, size);
         try writer.writeByte(0x6a);
         try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 0);
    }

    fn writeSection(self: *CodegenWasm, id: u8, data: []const u8) !void {
        try self.buffer.append(self.allocator, id);
        try writeUleb128(self.buffer.writer(self.allocator), @as(u32, @intCast(data.len)));
        try self.buffer.appendSlice(self.allocator, data);
    }

    fn writeString(self: *CodegenWasm, writer: anytype, str: []const u8) !void {
        _ = self;
        try writeUleb128(writer, @as(u32, @intCast(str.len)));
        try writer.writeAll(str);
    }
};

pub fn writeUleb128(writer: anytype, value: u32) !void {
    var v = value;
    while (true) {
        const byte = @as(u8, @intCast(v & 0x7f));
        v >>= 7;
        if (v != 0) {
            try writer.writeByte(byte | 0x80);
        } else {
            try writer.writeByte(byte);
            break;
        }
    }
}

pub fn writeSleb128(writer: anytype, value: i64) !void {
    var v = value;
    while (true) {
        const byte = @as(u8, @intCast(@as(u64, @bitCast(v)) & 0x7f));
        v >>= 7;
        if ((v == 0 and (byte & 0x40) == 0) or (v == -1 and (byte & 0x40) != 0)) {
            try writer.writeByte(byte);
            break;
        } else {
            try writer.writeByte(byte | 0x80);
        }
    }
}
