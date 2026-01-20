const std = @import("std");
const ast = @import("ast.zig");
const sema = @import("sema.zig");

pub const CodegenWat = struct {
    allocator: std.mem.Allocator,
    tree: *ast.Tree,
    sema_instance: *sema.Sema,
    output: std.ArrayListUnmanaged(u8),
    internal_functions: std.ArrayListUnmanaged(ast.NodeIndex),

    const VARIANT_TAG_MASK: u32 = 0x80000000;

    pub fn init(allocator: std.mem.Allocator, tree: *ast.Tree, s: *sema.Sema) CodegenWat {
        return .{ 
            .allocator = allocator,
            .tree = tree,
            .sema_instance = s,
            .output = . {},
            .internal_functions = . {},
        };
    }

    pub fn deinit(self: *CodegenWat) void {
        self.output.deinit(self.allocator);
        self.internal_functions.deinit(self.allocator);
    }

    pub fn generateModule(self: *CodegenWat, root_idx: ast.NodeIndex) ![]u8 {
        try self.collectFunctions(root_idx);
        
        try self.emit("(module\n");
        try self.emitImportSection();
        try self.emitMemorySection();
        try self.emitExportSection();
        
        for (self.internal_functions.items) |fn_idx| {
            try self.emitFunction(fn_idx);
        }
        
        try self.emitMainFunction(root_idx);
        try self.emit(")\n");
        return self.output.toOwnedSlice(self.allocator);
    }

    fn collectFunctions(self: *CodegenWat, root_idx: ast.NodeIndex) !void {
        const root = self.tree.nodes.items[root_idx];
        for (root.data.root.children) |child_idx| {
            if (self.tree.nodes.items[child_idx].tag == .fn_def) {
                try self.internal_functions.append(self.allocator, child_idx);
            }
        }
    }

    fn emit(self: *CodegenWat, str: []const u8) anyerror!void {
        try self.output.appendSlice(self.allocator, str);
    }

    fn emitFormatted(self: *CodegenWat, comptime fmt: []const u8, args: anytype) anyerror!void {
        var buf: [512]u8 = undefined;
        const s = try std.fmt.bufPrint(&buf, fmt, args);
        try self.emit(s);
    }

    fn emitIndent(self: *CodegenWat, indent: usize) anyerror!void {
        var i: usize = 0;
        while (i < indent) : (i += 1) try self.emit("  ");
    }

    fn emitImportSection(self: *CodegenWat) anyerror!void {
        for (self.sema_instance.ffi_decls.items) |node_idx| {
            const ffi = self.tree.nodes.items[node_idx].data.ffi_decl;
            try self.emitFormatted("  (import \"{s}\" \"{s}\" (func ${s}", .{ ffi.module_name, ffi.fn_name, ffi.name });
            if (std.mem.eql(u8, ffi.fn_name, "fd_write")) {
                try self.emit(" (param i32 i32 i32 i32) (result i32))\n");
            } else {
                try self.emit(" (result i32))\n");
            }
        }
    }

    fn emitMemorySection(self: *CodegenWat) anyerror!void {
        try self.emit("  (memory 1)\n");
    }

    fn emitExportSection(self: *CodegenWat) anyerror!void {
        try self.emit("  (export \"memory\" (memory 0))\n");
        try self.emit("  (export \"main\" (func $main))\n");
    }

    fn emitFunction(self: *CodegenWat, fn_idx: ast.NodeIndex) anyerror!void {
        const node = self.tree.nodes.items[fn_idx];
        const fn_info = &node.data.fn_def;
        
        try self.emitFormatted("  (func ${s} (result i32)\n", .{fn_info.name});
        try self.emit("    (local $tmp_ptr i32) (local $rc_ptr i32) (local $tag i32)\n");
        var i: usize = 0;
        while (i < 16) : (i += 1) try self.emitFormatted("    (local $l{d}_i32 i32)\n", .{i});
        
        try self.emitNode(fn_info.body, 2);
        
        if (self.sema_instance.fn_locals.get(fn_idx)) |locals| {
            try self.emit("    ;; --- RC Cleanup ---\n");
            for (locals.items) |local| try self.emitDecRC(local.index, local.name, 4);
        }
        
        try self.emit("    i32.const 0\n");
        try self.emit("  )\n");
    }

    fn emitMainFunction(self: *CodegenWat, root_idx: ast.NodeIndex) anyerror!void {
        try self.emit("  (func $main (result i32)\n");
        try self.emit("    (local $tmp_ptr i32) (local $rc_ptr i32) (local $tag i32)\n");
        var i: usize = 0;
        while (i < 16) : (i += 1) try self.emitFormatted("    (local $l{d}_i32 i32)\n", .{i});

        const root = self.tree.nodes.items[root_idx];
        for (root.data.root.children) |child_idx| {
            const child = self.tree.nodes.items[child_idx];
            if (child.tag != .fn_def and child.tag != .struct_def and child.tag != .union_def and child.tag != .ffi_decl) {
                try self.emitNode(child_idx, 2);
            }
        }

        if (self.sema_instance.fn_locals.get(root_idx)) |locals| {
            try self.emit("    ;; --- Automatic Scope Exit ---\n");
            for (locals.items) |local| try self.emitDecRC(local.index, local.name, 4);
        }

        try self.emit("    i32.const 0\n");
        try self.emit("  )\n");
    }

    fn emitNode(self: *CodegenWat, node_idx: ast.NodeIndex, indent: usize) anyerror!void {
        if (node_idx == 0) return;
        const node = self.tree.nodes.items[node_idx];
        switch (node.tag) {
            .root => { for (node.data.root.children) |child| try self.emitNode(child, indent); },
            .literal_int, .literal_float, .literal_text => try self.emitLiteral(node_idx, indent),
            .identifier => try self.emitIdentifier(node_idx, indent),
            .assign, .assign_init => try self.emitAssign(node_idx, indent),
            .binary_op => try self.emitBinaryOp(node_idx, indent),
            .call => try self.emitCall(node_idx, indent),
            .if_expr => try self.emitIf(node_idx, indent),
            .loop_expr => try self.emitLoop(node_idx, indent),
            .return_expr => try self.emitReturn(node_idx, indent),
            .match_expr => try self.emitMatch(node_idx, indent),
            .tuple_literal => try self.emitTupleLiteral(node_idx, indent),
            .array_literal => try self.emitArrayLiteral(node_idx, indent),
            .struct_init => try self.emitStructInit(node_idx, indent),
            .path_get => try self.emitFieldAccess(node_idx, indent),
            else => {},
        }
    }

    fn emitLiteral(self: *CodegenWat, node_idx: ast.NodeIndex, indent: usize) anyerror!void {
        const node = self.tree.nodes.items[node_idx];
        try self.emitIndent(indent);
        switch (node.tag) {
            .literal_int => try self.emitFormatted("i32.const {d}\n", .{node.data.literal_int}),
            .literal_float => try self.emitFormatted("f64.const {d}\n", .{node.data.literal_float}),
            .literal_text => {
                const type_info = self.sema_instance.node_types.get(node_idx).?;
                try self.emitFormatted(";; Literal Text: \"{s}\"\n", .{node.data.literal_text});
                try self.emitAlloc(16, indent);
                try self.emitIndent(indent); try self.emit("local.set $tmp_ptr\n");
                try self.emitIndent(indent); try self.emit("local.get $tmp_ptr i32.const 1 i32.store offset=0 ;; RC\n");
                try self.emitIndent(indent); try self.emitFormatted("local.get $tmp_ptr i32.const {d} i32.store offset=4 ;; ID\n", .{type_info.id});
                try self.emitIndent(indent); try self.emit("local.get $tmp_ptr\n");
            },
            else => unreachable,
        }
    }

    fn emitIdentifier(self: *CodegenWat, node_idx: ast.NodeIndex, indent: usize) anyerror!void {
        const node = self.tree.nodes.items[node_idx];
        const type_info = self.sema_instance.node_types.get(node_idx);
        
        if ((node.resolved_index & VARIANT_TAG_MASK) != 0) {
            const tag = node.resolved_index & ~VARIANT_TAG_MASK;
            try self.emitIndent(indent);
            try self.emitFormatted(";; Construct Variant (Tag {d})\n", .{tag});
            try self.emitAlloc(type_info.?.total_size, indent);
            try self.emitIndent(indent); try self.emit("local.set $tmp_ptr\n");
            try self.emitIndent(indent); try self.emit("local.get $tmp_ptr i32.const 1 i32.store offset=0 ;; RC\n");
            try self.emitIndent(indent); try self.emitFormatted("local.get $tmp_ptr i32.const {d} i32.store offset=4 ;; Tag\n", .{tag});
            try self.emitIndent(indent); try self.emit("local.get $tmp_ptr\n");
        } else {
            try self.emitIndent(indent);
            try self.emitFormatted("local.get {d} ;; {s}\n", .{ node.resolved_index, node.data.identifier.name });
            if (!node.is_last_use and type_info != null and type_info.?.total_size > 0) {
                try self.emitIndent(indent); try self.emit(";; IncRC\n");
                try self.emitIndent(indent); try self.emitFormatted("local.set $rc_ptr (local.get {d})\n", .{node.resolved_index});
                try self.emitIndent(indent); try self.emit("local.get $rc_ptr (local.get $rc_ptr (i32.load) (i32.const 1) (i32.add)) (i32.store)\n");
            }
        }
    }

    fn emitAssign(self: *CodegenWat, node_idx: ast.NodeIndex, indent: usize) anyerror!void {
        const node = self.tree.nodes.items[node_idx];
        const lhs_idx = if (node.tag == .assign) node.data.assign.lhs else node.data.assign_init.lhs;
        const rhs_idx = if (node.tag == .assign) node.data.assign.rhs else node.data.assign_init.rhs;
        try self.emitNode(rhs_idx, indent);
        try self.emitIndent(indent);
        try self.emitFormatted("local.set {d}\n", .{self.tree.nodes.items[lhs_idx].resolved_index});
    }

    fn emitBinaryOp(self: *CodegenWat, node_idx: ast.NodeIndex, indent: usize) anyerror!void {
        const node = self.tree.nodes.items[node_idx];
        try self.emitNode(node.data.binary_op.lhs, indent);
        try self.emitNode(node.data.binary_op.rhs, indent);
        try self.emitIndent(indent);
        const op = self.tree.tokens[node.main_token].tag;
        const s = switch (op) {
            .plus => "i32.add", .minus => "i32.sub", .asterisk => "i32.mul",
            .equal_equal => "i32.eq", .not_equal => "i32.ne",
            else => "i32.unknown",
        };
        try self.emitFormatted("{s}\n", .{s});
    }

    fn emitCall(self: *CodegenWat, node_idx: ast.NodeIndex, indent: usize) anyerror!void {
        const node = self.tree.nodes.items[node_idx];
        const target_node = self.tree.nodes.items[node.data.call.base_node];
        const args = node.data.call.args;
        
        if (target_node.tag == .identifier) {
            const name = target_node.data.identifier.name;
            if (std.mem.eql(u8, name, "get")) {
                try self.emitNode(args[0], indent);
                try self.emitIndent(indent); try self.emit("local.set $tmp_ptr\n");
                const target_type = self.sema_instance.node_types.get(args[0]).?;
                const field_idx = self.tree.nodes.items[args[1]].data.literal_int;
                
                try self.emitIndent(indent);
                if (std.mem.eql(u8, target_type.name, "Text")) {
                    try self.emitFormatted("local.get $tmp_ptr i32.load offset={d}\n", .{ if (field_idx == 0) @as(u32, 8) else 12 });
                } else {
                    try self.emit("i32.load offset=8 ;; TODO: non-text get\n");
                }
                return;
            }
            if (std.mem.eql(u8, name, "i32_load")) {
                try self.emitNode(args[0], indent);
                try self.emitIndent(indent); try self.emit("i32.load\n");
                return;
            }
            if (self.sema_instance.current_scope.lookupPtr(name)) |_| {
                for (args) |arg| try self.emitNode(arg, indent);
                try self.emitIndent(indent);
                try self.emitFormatted("call ${s}\n", .{name});
                return;
            }
        }
        
        if ((node.resolved_index & VARIANT_TAG_MASK) != 0) {
            const tag = node.resolved_index & ~VARIANT_TAG_MASK;
            try self.emitIndent(indent); try self.emitFormatted(";; Construct Variant {d}\n", .{tag});
            try self.emitAlloc(8, indent); 
            try self.emitIndent(indent); try self.emit("local.get 0 i32.store offset=4\n");
        }
    }

    fn emitMatch(self: *CodegenWat, node_idx: ast.NodeIndex, indent: usize) anyerror!void {
        const node = self.tree.nodes.items[node_idx];
        const match_info = &node.data.match_expr;
        
        try self.emitNode(match_info.target, indent);
        try self.emitIndent(indent); try self.emit("local.set $tmp_ptr\n");
        try self.emitIndent(indent); try self.emit("local.get $tmp_ptr (i32.load offset=4) local.set $tag\n");
        
        for (match_info.branches) |branch_idx| {
            const branch = self.tree.nodes.items[branch_idx];
            const pattern = self.tree.nodes.items[branch.data.match_branch.pattern];
            const tag = pattern.resolved_index & ~VARIANT_TAG_MASK;
            
            try self.emitIndent(indent);
            try self.emitFormatted("local.get $tag i32.const {d} i32.eq (if (then\n", .{tag});
            try self.emitNode(branch.data.match_branch.body, indent + 1);
            try self.emitIndent(indent); try self.emit(") (else\n");
        }
        try self.emitIndent(indent); try self.emit("i32.const 0\n");
        for (match_info.branches) |_| { try self.emitIndent(indent); try self.emit("))\n"); }
    }

    fn emitStructInit(self: *CodegenWat, node_idx: ast.NodeIndex, indent: usize) anyerror!void {
        const info = self.sema_instance.node_types.get(node_idx).?;
        try self.emitIndent(indent); try self.emitFormatted(";; Struct Init {s}\n", .{info.name});
        try self.emitAlloc(info.total_size, indent);
        try self.emitIndent(indent); try self.emit("local.set $tmp_ptr\n");
        try self.emitIndent(indent); try self.emitFormatted("local.get $tmp_ptr i32.const {d} i32.store offset=4\n", .{info.id});
        try self.emitIndent(indent); try self.emit("local.get $tmp_ptr\n");
    }

    fn emitFieldAccess(self: *CodegenWat, node_idx: ast.NodeIndex, indent: usize) anyerror!void {
        const node = self.tree.nodes.items[node_idx];
        const target_idx = node.data.path_get.target;
        try self.emitNode(target_idx, indent);
        try self.emitIndent(indent); try self.emit("i32.load offset=8 ;; TODO: Actual offset\n");
    }

    fn emitIf(self: *CodegenWat, node_idx: ast.NodeIndex, indent: usize) anyerror!void {
        const node = self.tree.nodes.items[node_idx];
        try self.emitNode(node.data.if_expr.cond, indent);
        try self.emitIndent(indent); try self.emit("(if (then\n");
        try self.emitNode(node.data.if_expr.then_body, indent + 1);
        if (node.data.if_expr.else_body != 0) {
            try self.emitIndent(indent); try self.emit(") (else\n");
            try self.emitNode(node.data.if_expr.else_body, indent + 1);
        }
        try self.emitIndent(indent); try self.emit("))\n");
    }

    fn emitLoop(self: *CodegenWat, node_idx: ast.NodeIndex, indent: usize) anyerror!void {
        try self.emitIndent(indent); try self.emit("(loop\n");
        try self.emitNode(self.tree.nodes.items[node_idx].data.loop_expr.body, indent + 1);
        try self.emitIndent(indent); try self.emit(")\n");
    }

    fn emitReturn(self: *CodegenWat, node_idx: ast.NodeIndex, indent: usize) anyerror!void {
        try self.emitNode(self.tree.nodes.items[node_idx].data.return_expr.value, indent);
        try self.emitIndent(indent); try self.emit("return\n");
    }

    fn emitTupleLiteral(self: *CodegenWat, node_idx: ast.NodeIndex, indent: usize) anyerror!void {
        _ = self; _ = node_idx; _ = indent;
    }

    fn emitArrayLiteral(self: *CodegenWat, node_idx: ast.NodeIndex, indent: usize) anyerror!void {
        _ = self; _ = node_idx; _ = indent;
    }

    fn emitDecRC(self: *CodegenWat, local_idx: u32, name: []const u8, indent: usize) anyerror!void {
        try self.emitIndent(indent);
        try self.emitFormatted(";; DecRC for {s}\n", .{name});
        try self.emitIndent(indent);
        try self.emitFormatted("local.get {d} local.set $rc_ptr\n", .{local_idx});
        try self.emitIndent(indent);
        try self.emit("local.get $rc_ptr (i32.load offset=0) (i32.const 1) i32.sub i32.store offset=0\n");
    }

    fn emitAlloc(self: *CodegenWat, size: u32, indent: usize) anyerror!void {
        try self.emitIndent(indent);
        try self.emitFormatted("i32.const {d} call $malloc\n", .{size});
    }
};