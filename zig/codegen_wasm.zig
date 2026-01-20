const std = @import("std");
const ast_mod = @import("ast.zig");
const sema = @import("sema.zig");

fn writeUleb128(writer: anytype, value: u32) !void {
    var val = value;
    while (true) {
        const byte = @as(u8, @intCast(val & 0x7f));
        val >>= 7;
        if (val == 0) {
            try writer.writeByte(byte);
            break;
        } else {
            try writer.writeByte(byte | 0x80);
        }
    }
}

fn writeSleb128(writer: anytype, value: i64) !void {
    var val = value;
    while (true) {
        const byte = @as(u8, @intCast(@as(u64, @bitCast(val)) & 0x7f));
        val >>= 7;
        if ((val == 0 and (byte & 0x40) == 0) or (val == -1 and (byte & 0x40) != 0)) {
            try writer.writeByte(byte);
            break;
        } else {
            try writer.writeByte(byte | 0x80);
        }
    }
}

pub const CodegenWasm = struct {
    allocator: std.mem.Allocator,
    tree: *ast_mod.Tree,
    sema_instance: *sema.Sema,
    buffer: std.ArrayListUnmanaged(u8),
    strings: std.ArrayListUnmanaged([]const u8),
    string_offsets: std.StringHashMap(u32),
    internal_functions: std.ArrayListUnmanaged(ast_mod.NodeIndex),

    pub const VARIANT_TAG_MASK: u32 = 0x80000000;

    pub fn init(allocator: std.mem.Allocator, tree: *ast_mod.Tree, s: *sema.Sema) CodegenWasm {
        return .{
            .allocator = allocator,
            .tree = tree,
            .sema_instance = s,
            .buffer = .{},
            .strings = .{},
            .string_offsets = std.StringHashMap(u32).init(allocator),
            .internal_functions = .{},
        };
    }

    pub fn deinit(self: *CodegenWasm) void {
        self.buffer.deinit(self.allocator);
        self.strings.deinit(self.allocator);
        self.string_offsets.deinit();
        self.internal_functions.deinit(self.allocator);
    }

    pub fn generate(self: *CodegenWasm, root_idx: ast_mod.NodeIndex) ![]u8 {
        try self.collectStrings();
        try self.collectFunctions(root_idx);
        
        try self.buffer.appendSlice(self.allocator, &[_]u8{ 0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00 });
        try self.emitTypeSection();
        try self.emitImportSection();
        try self.emitFunctionSection();
        try self.emitMemorySection();
        try self.emitExportSection();
        try self.emitDataSection();
        try self.emitCodeSection(root_idx);
        return self.buffer.toOwnedSlice(self.allocator);
    }

    fn collectStrings(self: *CodegenWasm) anyerror!void {
        for (self.tree.nodes.items) |node| {
            if (node.tag == .literal_text) {
                if (!self.string_offsets.contains(node.data.literal_text)) {
                    try self.strings.append(self.allocator, node.data.literal_text);
                }
            }
        }
    }

    fn collectFunctions(self: *CodegenWasm, root_idx: ast_mod.NodeIndex) anyerror!void {
        const root = self.tree.nodes.items[root_idx];
        for (root.data.root.children) |child_idx| {
            const node = self.tree.nodes.items[child_idx];
            if (node.tag == .fn_def) {
                const ffi_len = self.sema_instance.ffi_decls.items.len;
                self.tree.nodes.items[child_idx].resolved_index = @intCast(ffi_len + self.internal_functions.items.len);
                try self.internal_functions.append(self.allocator, child_idx);
            }
        }
    }

    fn writeSection(self: *CodegenWasm, id: u8, data: []const u8) anyerror!void {
        try self.buffer.append(self.allocator, id);
        try writeUleb128(self.buffer.writer(self.allocator), @as(u32, @intCast(data.len)));
        try self.buffer.appendSlice(self.allocator, data);
    }

    fn emitTypeSection(self: *CodegenWasm) anyerror!void {
        var section = std.ArrayListUnmanaged(u8){};
        defer section.deinit(self.allocator);
        const writer = section.writer(self.allocator);
        const types = [_][]const u8{
            &[_]u8{ 0x60, 0x00, 0x01, 0x7f }, // 0: () -> i32
            &[_]u8{ 0x60, 0x04, 0x7f, 0x7f, 0x7f, 0x7f, 0x01, 0x7f }, // 1: (4 args) -> i32
        };
        try writeUleb128(writer, @intCast(types.len));
        for (types) |t| try section.appendSlice(self.allocator, t);
        try self.writeSection(1, section.items);
    }

    fn emitImportSection(self: *CodegenWasm) anyerror!void {
        if (self.sema_instance.ffi_decls.items.len == 0) return;
        var section = std.ArrayListUnmanaged(u8){};
        defer section.deinit(self.allocator);
        const writer = section.writer(self.allocator);
        try writeUleb128(writer, @intCast(self.sema_instance.ffi_decls.items.len));
        for (self.sema_instance.ffi_decls.items, 0..) |node_idx, i| {
            const node = &self.tree.nodes.items[node_idx];
            const ffi = node.data.ffi_decl;
            try writeUleb128(writer, @intCast(ffi.module_name.len));
            try writer.writeAll(ffi.module_name);
            try writeUleb128(writer, @intCast(ffi.fn_name.len));
            try writer.writeAll(ffi.fn_name);
            try writer.writeByte(0x00);
            const type_idx: u32 = if (std.mem.eql(u8, ffi.fn_name, "fd_write")) 1 else 0;
            try writeUleb128(writer, type_idx);
            node.resolved_index = @intCast(i);
        }
        try self.writeSection(2, section.items);
    }

    fn emitFunctionSection(self: *CodegenWasm) anyerror!void {
        var section = std.ArrayListUnmanaged(u8){};
        defer section.deinit(self.allocator);
        const count = self.internal_functions.items.len + 1; // +1 for main
        try writeUleb128(section.writer(self.allocator), @intCast(count));
        for (0..count) |_| try section.append(self.allocator, 0); // All use Type 0
        try self.writeSection(3, section.items);
    }

    fn emitMemorySection(self: *CodegenWasm) anyerror!void {
        var section = std.ArrayListUnmanaged(u8){};
        defer section.deinit(self.allocator);
        try writeUleb128(section.writer(self.allocator), 1);
        try section.appendSlice(self.allocator, &[_]u8{ 0x00, 0x01 }); // 1 page
        try self.writeSection(5, section.items);
    }

    fn emitExportSection(self: *CodegenWasm) anyerror!void {
        var section = std.ArrayListUnmanaged(u8){};
        defer section.deinit(self.allocator);
        const writer = section.writer(self.allocator);
        const ffi_len = self.sema_instance.ffi_decls.items.len;
        const internal_len = self.internal_functions.items.len;
        try writeUleb128(writer, 2);
        try writeUleb128(writer, 4); try writer.writeAll("main");
        try writer.writeByte(0x00);
        try writeUleb128(writer, @intCast(ffi_len + internal_len)); 
        try writeUleb128(writer, 6); try writer.writeAll("memory");
        try writer.writeByte(0x02); try writeUleb128(writer, 0);
        try self.writeSection(7, section.items);
    }

    fn emitDataSection(self: *CodegenWasm) anyerror!void {
        if (self.strings.items.len == 0) return;
        var section = std.ArrayListUnmanaged(u8){};
        defer section.deinit(self.allocator);
        const writer = section.writer(self.allocator);
        try writeUleb128(writer, 1);
        try writer.writeByte(0x00);
        try writer.writeByte(0x41); try writeSleb128(writer, 1024); try writer.writeByte(0x0b);
        var total_len: u32 = 0;
        for (self.strings.items) |s| total_len += @intCast(s.len);
        try writeUleb128(writer, total_len);
        var current_offset: u32 = 1024;
        for (self.strings.items) |s| {
            try writer.writeAll(s);
            try self.string_offsets.put(s, current_offset);
            current_offset += @intCast(s.len);
        }
        try self.writeSection(11, section.items);
    }

    fn emitCodeSection(self: *CodegenWasm, root_idx: ast_mod.NodeIndex) anyerror!void {
        var section = std.ArrayListUnmanaged(u8){};
        defer section.deinit(self.allocator);
        const writer = section.writer(self.allocator);
        try writeUleb128(writer, @intCast(self.internal_functions.items.len + 1));
        
        for (self.internal_functions.items) |fn_idx| {
            var body = std.ArrayListUnmanaged(u8){};
            defer body.deinit(self.allocator);
            const bw = body.writer(self.allocator);
            try writeUleb128(bw, 2);
            try writeUleb128(bw, 16); try bw.writeByte(0x7f);
            try writeUleb128(bw, 16); try bw.writeByte(0x7c);
            const node = self.tree.nodes.items[fn_idx];
            try self.emitNode(bw, node.data.fn_def.body);
            if (self.sema_instance.fn_locals.get(fn_idx)) |locals| {
                for (locals.items) |local| try self.emitDecRC(bw, local.index, local.type_info);
            }
            try bw.writeByte(0x0b);
            try writeUleb128(writer, @intCast(body.items.len));
            try writer.writeAll(body.items);
        }
        
        var main_body = std.ArrayListUnmanaged(u8){};
        defer main_body.deinit(self.allocator);
        const mw = main_body.writer(self.allocator);
        try writeUleb128(mw, 2);
        try writeUleb128(mw, 16); try mw.writeByte(0x7f);
        try writeUleb128(mw, 16); try mw.writeByte(0x7c);
        const root = self.tree.nodes.items[root_idx];
        for (root.data.root.children) |child_idx| {
            const child = self.tree.nodes.items[child_idx];
            if (child.tag != .fn_def and child.tag != .struct_def and child.tag != .union_def and child.tag != .ffi_decl) {
                try self.emitNode(mw, child_idx);
            }
        }
        if (self.sema_instance.fn_locals.get(root_idx)) |locals| {
            for (locals.items) |local| try self.emitDecRC(mw, local.index, local.type_info);
        }
        try mw.writeByte(0x41); try mw.writeByte(0x00);
        try mw.writeByte(0x0b);
        try writeUleb128(writer, @intCast(main_body.items.len));
        try writer.writeAll(main_body.items);
        try self.writeSection(10, section.items);
    }

    fn emitNode(self: *CodegenWasm, writer: anytype, node_idx: ast_mod.NodeIndex) anyerror!void {
        if (node_idx == 0) return;
        const node = self.tree.nodes.items[node_idx];
        switch (node.tag) {
            .root => { for (node.data.root.children) |child| try self.emitNode(writer, child); },
            .literal_int, .literal_float, .literal_text => try self.emitLiteral(writer, node_idx),
            .identifier => try self.emitIdentifier(writer, node_idx),
            .assign, .assign_init => try self.emitAssign(writer, node_idx),
            .binary_op => try self.emitBinaryOp(writer, node_idx),
            .call => try self.emitCall(writer, node_idx),
            .if_expr => try self.emitIf(writer, node_idx),
            .loop_expr => try self.emitLoop(writer, node_idx),
            .return_expr => try self.emitReturn(writer, node_idx),
            .match_expr => try self.emitMatch(writer, node_idx),
            .tuple_literal => try self.emitTupleLiteral(writer, node_idx),
            .array_literal => try self.emitArrayLiteral(writer, node_idx),
            .struct_init => try self.emitStructInit(writer, node_idx),
            .path_get => try self.emitFieldAccess(writer, node_idx),
            else => {},
        }
    }

    fn emitLiteral(self: *CodegenWasm, writer: anytype, node_idx: ast_mod.NodeIndex) anyerror!void {
        const node = self.tree.nodes.items[node_idx];
        switch (node.tag) {
            .literal_int => { try writer.writeByte(0x41); try writeSleb128(writer, node.data.literal_int); },
            .literal_float => { try writer.writeByte(0x44); try writer.writeAll(std.mem.asBytes(&node.data.literal_float)); },
            .literal_text => {
                const offset = self.string_offsets.get(node.data.literal_text).?;
                const len = node.data.literal_text.len;
                const type_info = self.sema_instance.node_types.get(node_idx).?;

                try self.emitAlloc(writer, 16);
                try writer.writeByte(0x21); try writeUleb128(writer, 14);

                // RC=1
                try writer.writeByte(0x20); try writeUleb128(writer, 14);
                try writer.writeByte(0x41); try writeSleb128(writer, 1);
                try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 0);

                // TypeID
                try writer.writeByte(0x20); try writeUleb128(writer, 14);
                try writer.writeByte(0x41); try writeSleb128(writer, type_info.id);
                try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 4);

                // Ptr
                try writer.writeByte(0x20); try writeUleb128(writer, 14);
                try writer.writeByte(0x41); try writeSleb128(writer, offset);
                try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 8);

                // Len
                try writer.writeByte(0x20); try writeUleb128(writer, 14);
                try writer.writeByte(0x41); try writeSleb128(writer, @as(i64, @intCast(len)));
                try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 12);

                try writer.writeByte(0x20); try writeUleb128(writer, 14);
            },
            else => unreachable,
        }
    }

    fn emitIdentifier(self: *CodegenWasm, writer: anytype, node_idx: ast_mod.NodeIndex) anyerror!void {
        const node = self.tree.nodes.items[node_idx];
        const type_info = self.sema_instance.node_types.get(node_idx);
        if ((node.resolved_index & VARIANT_TAG_MASK) != 0) {
             const tag = node.resolved_index & ~VARIANT_TAG_MASK;
             const info = type_info orelse return;
             try self.emitAlloc(writer, info.total_size);
             try writer.writeByte(0x21); try writeUleb128(writer, 14);
             try writer.writeByte(0x20); try writeUleb128(writer, 14);
             try writer.writeByte(0x41); try writeSleb128(writer, tag);
             try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 4);
             try writer.writeByte(0x20); try writeUleb128(writer, 14);
             try writer.writeByte(0x41); try writeSleb128(writer, 1);
             try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 0);
             try writer.writeByte(0x20); try writeUleb128(writer, 14);
        } else {
            try writer.writeByte(0x20); try writeUleb128(writer, node.resolved_index);
            if (!node.is_last_use) {
                if (type_info) |ti| {
                    if (ti.total_size > 0) {
                        try writer.writeByte(0x21); try writeUleb128(writer, 15);
                        try writer.writeByte(0x20); try writeUleb128(writer, 15);
                        try writer.writeByte(0x20); try writeUleb128(writer, 15);
                        try writer.writeByte(0x28); try writeUleb128(writer, 2); try writeUleb128(writer, 0);
                        try writer.writeByte(0x41); try writeSleb128(writer, 1);
                        try writer.writeByte(0x6a);
                        try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 0);
                        try writer.writeByte(0x20); try writeUleb128(writer, 15);
                    }
                }
            }
        }
    }

    fn emitAssign(self: *CodegenWasm, writer: anytype, node_idx: ast_mod.NodeIndex) anyerror!void {
        const node = self.tree.nodes.items[node_idx];
        const lhs_idx = if (node.tag == .assign) node.data.assign.lhs else node.data.assign_init.lhs;
        const rhs_idx = if (node.tag == .assign) node.data.assign.rhs else node.data.assign_init.rhs;
        const lhs = self.tree.nodes.items[lhs_idx];
        if (lhs.tag == .tuple_literal) {
            try self.emitNode(writer, rhs_idx);
            try writer.writeByte(0x21); try writeUleb128(writer, 14);
            const rhs_type = self.sema_instance.node_types.get(rhs_idx).?;
            for (lhs.data.tuple_literal.elements, 0..) |elem_idx, i| {
                const elem = self.tree.nodes.items[elem_idx];
                var buf: [16]u8 = undefined;
                const field = rhs_type.fields.get(try std.fmt.bufPrint(&buf, "{d}", .{i})).?;
                try writer.writeByte(0x20); try writeUleb128(writer, 14);
                const is_float = std.mem.eql(u8, field.type_name, "f64");
                try writer.writeByte(if (is_float) 0x2b else 0x28);
                try writeUleb128(writer, if (is_float) 3 else 2); try writeUleb128(writer, field.offset);
                try writer.writeByte(0x21); try writeUleb128(writer, elem.resolved_index);
            }
        } else {
            try self.emitNode(writer, rhs_idx);
            try writer.writeByte(0x21); try writeUleb128(writer, lhs.resolved_index);
        }
    }

    fn emitBinaryOp(self: *CodegenWasm, writer: anytype, node_idx: ast_mod.NodeIndex) anyerror!void {
        const node = self.tree.nodes.items[node_idx];
        try self.emitNode(writer, node.data.binary_op.lhs);
        try self.emitNode(writer, node.data.binary_op.rhs);
        
        const lhs_type = self.sema_instance.node_types.get(node.data.binary_op.lhs);
        const is_float = if (lhs_type) |t| std.mem.eql(u8, t.name, "f64") else false;
        const op_token = self.tree.tokens[node.main_token];
        
        if (is_float) {
            switch (op_token.tag) {
                .plus => try writer.writeByte(0xa0), .minus => try writer.writeByte(0xa1),
                .asterisk => try writer.writeByte(0xa2), .slash => try writer.writeByte(0xa3),
                .equal_equal => try writer.writeByte(0x61), .not_equal => try writer.writeByte(0x62),
                .greater => try writer.writeByte(0x65), .less => try writer.writeByte(0x63),
                else => unreachable,
            }
        } else {
            switch (op_token.tag) {
                .plus => try writer.writeByte(0x6a), .minus => try writer.writeByte(0x6b),
                .asterisk => try writer.writeByte(0x6c), .slash => try writer.writeByte(0x6d),
                .equal_equal => try writer.writeByte(0x46), .not_equal => try writer.writeByte(0x47),
                .greater => try writer.writeByte(0x4e), .less => try writer.writeByte(0x48),
                else => unreachable,
            }
        }
    }

    fn emitCall(self: *CodegenWasm, writer: anytype, node_idx: ast_mod.NodeIndex) anyerror!void {
        const node = self.tree.nodes.items[node_idx];
        const target_node = self.tree.nodes.items[node.data.call.base_node];
        const args = node.data.call.args;

        if (target_node.tag == .type_apply) {
            const name = target_node.data.type_apply.base_name;
            if (std.mem.eql(u8, name, "Text")) {
                try self.emitAlloc(writer, 16);
                try writer.writeByte(0x21); try writeUleb128(writer, 14); // tmp ptr

                // RC=1, ID=text_id
                const type_info = self.sema_instance.node_types.get(node_idx).?;
                try writer.writeByte(0x20); try writeUleb128(writer, 14);
                try writer.writeByte(0x41); try writeSleb128(writer, 1);
                try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 0);

                try writer.writeByte(0x20); try writeUleb128(writer, 14);
                try writer.writeByte(0x41); try writeSleb128(writer, type_info.id);
                try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 4);

                // Ptr (arg 0)
                try writer.writeByte(0x20); try writeUleb128(writer, 14);
                try self.emitNode(writer, args[0]);
                try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 8);

                // Len (arg 1)
                try writer.writeByte(0x20); try writeUleb128(writer, 14);
                try self.emitNode(writer, args[1]);
                try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 12);

                try writer.writeByte(0x20); try writeUleb128(writer, 14);
                return;
            }
        }

        if (target_node.tag == .identifier) {
            const name = target_node.data.identifier.name;
            if (try self.emitBuiltinCall(writer, node_idx, name, args)) return;
            if (self.sema_instance.current_scope.lookupPtr(name)) |sym| {
                for (args) |arg| try self.emitNode(writer, arg);
                try writer.writeByte(0x10); try writeUleb128(writer, self.tree.nodes.items[sym.node_idx].resolved_index);
                return;
            }
        }
        if ((node.resolved_index & VARIANT_TAG_MASK) != 0) {
            const tag = node.resolved_index & ~VARIANT_TAG_MASK;
            const info = self.sema_instance.node_types.get(node_idx).?;
            try self.emitAlloc(writer, info.total_size);
            try writer.writeByte(0x21); try writeUleb128(writer, 14);
            try writer.writeByte(0x20); try writeUleb128(writer, 14);
            try writer.writeByte(0x41); try writeSleb128(writer, tag);
            try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 4);
            try writer.writeByte(0x20); try writeUleb128(writer, 14);
            try writer.writeByte(0x41); try writeSleb128(writer, 1);
            try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 0);
            if (args.len == 1) {
                try writer.writeByte(0x20); try writeUleb128(writer, 14);
                try self.emitNode(writer, args[0]);
                try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 8);
            }
            try writer.writeByte(0x20); try writeUleb128(writer, 14);
            return;
        }
    }

    fn emitBuiltinCall(self: *CodegenWasm, writer: anytype, node_idx: ast_mod.NodeIndex, name: []const u8, args: []ast_mod.NodeIndex) anyerror!bool {
        _ = node_idx;
        if (std.mem.eql(u8, name, "i32_load")) {
            try self.emitNode(writer, args[0]);
            try writer.writeByte(0x28); try writeUleb128(writer, 2); try writeUleb128(writer, 0);
            return true;
        }
        if (std.mem.eql(u8, name, "i32_store")) {
            try self.emitNode(writer, args[0]);
            try self.emitNode(writer, args[1]);
            try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 0);
            return true;
        }
        if (std.mem.eql(u8, name, "mem_size")) { try writer.writeAll(&[_]u8{ 0x3f, 0x00 }); return true; }
        if (std.mem.eql(u8, name, "mem_grow")) { try self.emitNode(writer, args[0]); try writer.writeAll(&[_]u8{ 0x40, 0x00 }); return true; }
        if (std.mem.eql(u8, name, "get")) {
            try self.emitNode(writer, args[0]);
            try writer.writeByte(0x21); try writeUleb128(writer, 14);
            const target_type = self.sema_instance.node_types.get(args[0]).?;
            if (target_type.is_tuple) {
                const idx = self.tree.nodes.items[args[1]].data.literal_int;
                var buf: [16]u8 = undefined;
                const field = target_type.fields.get(try std.fmt.bufPrint(&buf, "{d}", .{idx})).?;
                try writer.writeByte(0x20); try writeUleb128(writer, 14);
                const is_float = std.mem.eql(u8, field.type_name, "f64");
                try writer.writeByte(if (is_float) 0x2b else 0x28);
                try writeUleb128(writer, if (is_float) 3 else 2); try writeUleb128(writer, field.offset);
            } else if (std.mem.eql(u8, target_type.name, "text")) {
                const is_len = self.tree.nodes.items[args[1]].data.literal_int == 1;
                try writer.writeByte(0x20); try writeUleb128(writer, 14);
                try writer.writeByte(0x28); try writeUleb128(writer, 2); try writeUleb128(writer, if (is_len) 12 else 8);
            }
            return true;
        }
        return false;
    }

    fn emitIf(self: *CodegenWasm, writer: anytype, node_idx: ast_mod.NodeIndex) anyerror!void {
        const node = self.tree.nodes.items[node_idx];
        try self.emitNode(writer, node.data.if_expr.cond);
        try writer.writeByte(0x04); try writer.writeByte(0x7f);
        try self.emitNode(writer, node.data.if_expr.then_body);
        if (node.data.if_expr.else_body != 0) { try writer.writeByte(0x05); try self.emitNode(writer, node.data.if_expr.else_body); }
        try writer.writeByte(0x0b);
    }

    fn emitLoop(self: *CodegenWasm, writer: anytype, node_idx: ast_mod.NodeIndex) anyerror!void {
        const node = self.tree.nodes.items[node_idx];
        try writer.writeByte(0x03); try writer.writeByte(0x7f);
        try self.emitNode(writer, node.data.loop_expr.body);
        try writer.writeByte(0x0b);
    }

    fn emitReturn(self: *CodegenWasm, writer: anytype, node_idx: ast_mod.NodeIndex) anyerror!void {
        const node = self.tree.nodes.items[node_idx];
        try self.emitNode(writer, node.data.return_expr.value);
        try writer.writeByte(0x0f);
    }

    fn emitMatch(self: *CodegenWasm, writer: anytype, node_idx: ast_mod.NodeIndex) anyerror!void {
        const node = self.tree.nodes.items[node_idx];
        const match_info = &node.data.match_expr;
        try self.emitNode(writer, match_info.target);
        try writer.writeByte(0x21); try writeUleb128(writer, 14);
        try writer.writeByte(0x20); try writeUleb128(writer, 14);
        try writer.writeByte(0x28); try writeUleb128(writer, 2); try writeUleb128(writer, 4);
        try writer.writeByte(0x21); try writeUleb128(writer, 13);
        for (match_info.branches) |branch_idx| {
            const branch = self.tree.nodes.items[branch_idx];
            const pattern = self.tree.nodes.items[branch.data.match_branch.pattern];
            try writer.writeByte(0x20); try writeUleb128(writer, 13);
            try writer.writeByte(0x41); try writeSleb128(writer, @as(i32, @bitCast(pattern.resolved_index & ~VARIANT_TAG_MASK)));
            try writer.writeByte(0x46);
            try writer.writeByte(0x04); try writer.writeByte(0x7f);
            if (pattern.tag == .call and pattern.data.call.args.len == 1) {
                const arg = self.tree.nodes.items[pattern.data.call.args[0]];
                try writer.writeByte(0x20); try writeUleb128(writer, 14);
                try writer.writeByte(0x28); try writeUleb128(writer, 2); try writeUleb128(writer, 8);
                try writer.writeByte(0x21); try writeUleb128(writer, arg.resolved_index);
            }
            try self.emitNode(writer, branch.data.match_branch.body);
            try writer.writeByte(0x05);
        }
        try writer.writeByte(0x41); try writer.writeByte(0x00);
        for (match_info.branches) |_| try writer.writeByte(0x0b);
    }

    fn emitTupleLiteral(self: *CodegenWasm, writer: anytype, node_idx: ast_mod.NodeIndex) anyerror!void {
        const node = self.tree.nodes.items[node_idx];
        const info = self.sema_instance.node_types.get(node_idx).?;
        try self.emitAlloc(writer, info.total_size);
        try writer.writeByte(0x21); try writeUleb128(writer, 14);
        try writer.writeByte(0x20); try writeUleb128(writer, 14);
        try writer.writeByte(0x41); try writeSleb128(writer, 1);
        try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 0);
        try writer.writeByte(0x20); try writeUleb128(writer, 14);
        try writer.writeByte(0x41); try writeSleb128(writer, info.id);
        try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 4);
        for (node.data.tuple_literal.elements, 0..) |elem_idx, i| {
            var buf: [16]u8 = undefined;
            const field = info.fields.get(try std.fmt.bufPrint(&buf, "{d}", .{i})).?;
            try writer.writeByte(0x20); try writeUleb128(writer, 14);
            try self.emitNode(writer, elem_idx);
            const is_float = std.mem.eql(u8, field.type_name, "f64");
            try writer.writeByte(if (is_float) 0x39 else 0x36);
            try writeUleb128(writer, if (is_float) 3 else 2); try writeUleb128(writer, field.offset);
        }
        try writer.writeByte(0x20); try writeUleb128(writer, 14);
    }

    fn emitArrayLiteral(self: *CodegenWasm, writer: anytype, node_idx: ast_mod.NodeIndex) anyerror!void {
        const node = self.tree.nodes.items[node_idx];
        const info = self.sema_instance.node_types.get(node_idx).?;
        try self.emitAlloc(writer, info.total_size);
        try writer.writeByte(0x21); try writeUleb128(writer, 14);
        try writer.writeByte(0x20); try writeUleb128(writer, 14);
        try writer.writeByte(0x41); try writeSleb128(writer, 1);
        try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 0);
        try writer.writeByte(0x20); try writeUleb128(writer, 14);
        try writer.writeByte(0x41); try writeSleb128(writer, info.id);
        try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 4);
        const elem_size = if (info.array_elem_type.?.total_size > 0) info.array_elem_type.?.total_size else 4;
        for (node.data.array_literal.elements, 0..) |elem_idx, i| {
            try writer.writeByte(0x20); try writeUleb128(writer, 14);
            try self.emitNode(writer, elem_idx);
            const is_float = std.mem.eql(u8, info.array_elem_type.?.name, "f64");
            try writer.writeByte(if (is_float) 0x39 else 0x36);
            try writeUleb128(writer, if (is_float) 3 else 2); 
            try writeUleb128(writer, 8 + @as(u32, @intCast(i)) * elem_size);
        }
        try writer.writeByte(0x20); try writeUleb128(writer, 14);
    }

    fn emitStructInit(self: *CodegenWasm, writer: anytype, node_idx: ast_mod.NodeIndex) anyerror!void {
        const node = self.tree.nodes.items[node_idx];
        const info = self.sema_instance.node_types.get(node_idx).?;
        try self.emitAlloc(writer, info.total_size);
        try writer.writeByte(0x21); try writeUleb128(writer, 14);
        try writer.writeByte(0x20); try writeUleb128(writer, 14);
        try writer.writeByte(0x41); try writeSleb128(writer, 1);
        try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 0);
        try writer.writeByte(0x20); try writeUleb128(writer, 14);
        try writer.writeByte(0x41); try writeSleb128(writer, info.id);
        try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 4);
        for (node.data.struct_init.entries) |entry_idx| {
            const entry = self.tree.nodes.items[entry_idx].data.set_entry;
            const field_name = self.tree.nodes.items[entry.path].data.identifier.name;
            const field = info.fields.get(field_name).?;
            try writer.writeByte(0x20); try writeUleb128(writer, 14);
            try self.emitNode(writer, entry.value);
            const is_float = std.mem.eql(u8, field.type_name, "f64");
            try writer.writeByte(if (is_float) 0x39 else 0x36);
            try writeUleb128(writer, if (is_float) 3 else 2); try writeUleb128(writer, field.offset);
        }
        try writer.writeByte(0x20); try writeUleb128(writer, 14);
    }

    fn emitFieldAccess(self: *CodegenWasm, writer: anytype, node_idx: ast_mod.NodeIndex) anyerror!void {
        const node = self.tree.nodes.items[node_idx];
        const target_idx = node.data.path_get.target;
        const target_type = self.sema_instance.node_types.get(target_idx).?;
        try self.emitNode(writer, target_idx);
        try writer.writeByte(0x21); try writeUleb128(writer, 14);
        const field_node = self.tree.nodes.items[node.data.path_get.path[0]];
        const field_name = field_node.data.identifier.name;
        const field = target_type.fields.get(field_name).?;
        try writer.writeByte(0x20); try writeUleb128(writer, 14);
        const is_float = std.mem.eql(u8, field.type_name, "f64");
        try writer.writeByte(if (is_float) 0x2b else 0x28);
        try writeUleb128(writer, if (is_float) 3 else 2); try writeUleb128(writer, field.offset);
    }

    fn emitAlloc(self: *CodegenWasm, writer: anytype, size: u32) anyerror!void {
        try writer.writeByte(0x41); try writeSleb128(writer, @as(i64, @intCast(size)));
        // Assuming 'malloc' is the first internal function after imports
        try writer.writeByte(0x10); try writeUleb128(writer, @intCast(self.sema_instance.ffi_decls.items.len));
    }

    fn emitDecRC(self: *CodegenWasm, writer: anytype, local_idx: u32, type_info: *sema.TypeInfo) anyerror!void {
        _ = self;
        if (type_info.total_size == 0) return;
        try writer.writeByte(0x20); try writeUleb128(writer, local_idx);
        try writer.writeByte(0x21); try writeUleb128(writer, 15);
        try writer.writeByte(0x20); try writeUleb128(writer, 15);
        try writer.writeByte(0x20); try writeUleb128(writer, 15);
        try writer.writeByte(0x28); try writeUleb128(writer, 2); try writeUleb128(writer, 0);
        try writer.writeByte(0x41); try writer.writeByte(0x01);
        try writer.writeByte(0x6b);
        try writer.writeByte(0x36); try writeUleb128(writer, 2); try writeUleb128(writer, 0);
    }
};
