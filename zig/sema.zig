const std = @import("std");
const ast = @import("ast.zig");

pub const SemaError = error{
    InvalidAssignmentLHS,
    ImmutableVariableModified,
    UndefinedVariable,
    FieldNotFound,
    TypeMismatch,
    OutOfMemory,
    DuplicateVariant,
    InvalidPattern,
    NoSpaceLeft,
};

pub const FieldInfo = struct {
    name: []const u8,
    offset: u32,
    size: u32,
    type_name: []const u8,
};

pub const VariantInfo = struct {
    tag_value: i32,
    payload_type: ?[]const u8, // type name, null if no payload
};

pub const TypeInfo = struct {
    id: u32,
    name: []const u8,
    total_size: u32,
    fields: std.StringHashMap(FieldInfo),
    variants: std.StringHashMap(VariantInfo),
    is_enum: bool = false,
    is_tuple: bool = false,
};

pub const Symbol = struct {
    name: []const u8,
    node_idx: ast.NodeIndex,
    is_immutable: bool,
    is_private: bool,
    local_index: u32 = 0,
    last_use_node: ?ast.NodeIndex = null,
    type_info: ?*TypeInfo = null,
    variant_tag: ?i32 = null, // If set, this symbol is an enum variant constructor/value
};

pub const Scope = struct {
    parent: ?*Scope,
    symbols: std.StringHashMap(Symbol),
    next_local_index: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, parent: ?*Scope) Scope {
        return .{
            .parent = parent,
            .symbols = std.StringHashMap(Symbol).init(allocator),
            .next_local_index = if (parent) |p| p.next_local_index else 0,
        };
    }

    pub fn deinit(self: *Scope) void {
        self.symbols.deinit();
    }

    pub fn define(self: *Scope, sym: Symbol) !void {
        try self.symbols.put(sym.name, sym);
    }

    pub fn lookupPtr(self: *Scope, name: []const u8) ?*Symbol {
        if (self.symbols.getPtr(name)) |sym| return sym;
        if (self.parent) |p| return p.lookupPtr(name);
        return null;
    }
};

pub const Sema = struct {
    allocator: std.mem.Allocator,
    tree: *ast.Tree,
    current_scope: *Scope,
    type_registry: std.StringHashMap(*TypeInfo),
    node_types: std.AutoHashMap(ast.NodeIndex, *TypeInfo),
    generic_definitions: std.StringHashMap(ast.NodeIndex),
    monomorphized_types: std.StringHashMap(*TypeInfo),
    allocated_names: std.ArrayListUnmanaged([]const u8),
    type_id_counter: u32 = 1,
    header_printed: bool = false,

    pub const VARIANT_TAG_MASK: u32 = 0x80000000;

    pub fn init(allocator: std.mem.Allocator, tree: *ast.Tree) !Sema {
        const root_scope = try allocator.create(Scope);
        root_scope.* = Scope.init(allocator, null);
        return .{
            .allocator = allocator,
            .tree = tree,
            .current_scope = root_scope,
            .type_registry = std.StringHashMap(*TypeInfo).init(allocator),
            .node_types = std.AutoHashMap(ast.NodeIndex, *TypeInfo).init(allocator),
            .generic_definitions = std.StringHashMap(ast.NodeIndex).init(allocator),
            .monomorphized_types = std.StringHashMap(*TypeInfo).init(allocator),
            .allocated_names = std.ArrayListUnmanaged([]const u8){},
        };
    }

    pub fn deinit(self: *Sema) void {
        var it = self.type_registry.valueIterator();
        while (it.next()) |info| {
            info.*.fields.deinit();
            info.*.variants.deinit();
            self.allocator.destroy(info.*);
        }
        self.type_registry.deinit();
        self.node_types.deinit();
        self.generic_definitions.deinit();
        self.monomorphized_types.deinit();
        for (self.allocated_names.items) |name| {
            self.allocator.free(name);
        }
        self.allocated_names.deinit(self.allocator);
        self.current_scope.deinit();
        self.allocator.destroy(self.current_scope);
    }

    pub fn analyze(self: *Sema, node_idx: ast.NodeIndex) SemaError!void {
        if (node_idx == 0) return;
        const node = &self.tree.nodes.items[node_idx];

        if (!self.header_printed) {
            @import("logistics.zig").printHeader(4, 4);
            self.header_printed = true;
        }

        switch (node.tag) {
            .root => {
                for (node.data.root.children) |child_idx| {
                    try self.analyze(child_idx);
                }
            },
            .fn_def => {
                const fn_info = &node.data.fn_def;
                if (fn_info.generic_params.len > 0) {
                    try self.generic_definitions.put(fn_info.name, node_idx);
                } else {
                    const old_scope = self.current_scope;
                    const new_scope = try self.allocator.create(Scope);
                    new_scope.* = Scope.init(self.allocator, old_scope);
                    self.current_scope = new_scope;
                    defer {
                        self.current_scope = old_scope;
                        new_scope.deinit();
                        self.allocator.destroy(new_scope);
                    }

                    for (fn_info.params) |param_idx| {
                        const param_node = &self.tree.nodes.items[param_idx];
                        try self.current_scope.define(.{
                            .name = param_node.data.param.name,
                            .node_idx = param_idx,
                            .is_immutable = true,
                            .is_private = false,
                        });
                    }
                    try old_scope.define(.{
                        .name = fn_info.name,
                        .node_idx = node_idx,
                        .is_immutable = true,
                        .is_private = false,
                    });
                    try self.analyze(fn_info.body);
                }
            },
            .struct_def => try self.analyzeStructDef(node_idx),
            .assign_init => try self.analyzeAssignInit(node_idx),
            .assign => try self.analyzeAssign(node_idx),
            .identifier => try self.analyzeIdentifier(node_idx),
            .defer_stmt => try self.analyze(node.data.defer_stmt.expr),
            .if_expr => {
                try self.analyze(node.data.if_expr.cond);
                try self.analyze(node.data.if_expr.then_body);
                if (node.data.if_expr.else_body != 0) try self.analyze(node.data.if_expr.else_body);
            },
            .loop_expr => try self.analyze(node.data.loop_expr.body),
            .struct_init => try self.analyzeStructInit(node_idx),
            .path_get => try self.analyzePathGet(node_idx),
            .path_set => try self.analyzePathSet(node_idx),
            .call => try self.analyzeCall(node_idx),
            .enum_def => try self.analyzeEnumDef(node_idx),
            .match_expr => try self.analyzeMatchExpr(node_idx),
            .tuple_literal => try self.analyzeTupleLiteral(node_idx),
            .tuple_type => {
                _ = try self.analyzeType(node_idx, null);
            },
            .binary_op => {
                try self.analyze(node.data.binary_op.lhs);
                try self.analyze(node.data.binary_op.rhs);
                if (self.node_types.get(node.data.binary_op.lhs)) |ti| {
                    try self.node_types.put(node_idx, ti);
                }
            },
            .type_apply => {
                _ = try self.analyzeType(node_idx, null);
            },
            .break_expr => if (node.data.break_expr.value != 0) try self.analyze(node.data.break_expr.value),
            .return_expr => if (node.data.return_expr.value != 0) try self.analyze(node.data.return_expr.value),
            .constraint_def, .variant_def, .match_branch, .enum_literal, .literal_int, .literal_float, .literal_text, .continue_expr => {},
            else => {},
        }
    }

    fn analyzeTupleLiteral(self: *Sema, node_idx: ast.NodeIndex) SemaError!void {
        const node = &self.tree.nodes.items[node_idx];
        var element_types = std.ArrayListUnmanaged(*TypeInfo){};
        defer element_types.deinit(self.allocator);

        for (node.data.tuple_literal.elements) |elem_idx| {
            try self.analyze(elem_idx);
            const ti = self.node_types.get(elem_idx) orelse return error.TypeMismatch;
            try element_types.append(self.allocator, ti);
        }

        const info = try self.getOrCreateTupleType(element_types.items);
        try self.node_types.put(node_idx, info);
    }

    fn getOrCreateTupleType(self: *Sema, element_types: []const *TypeInfo) !*TypeInfo {
        var name_buf = std.ArrayListUnmanaged(u8){};
        defer name_buf.deinit(self.allocator);
        try name_buf.appendSlice(self.allocator, "(");
        for (element_types, 0..) |ti, i| {
            if (i > 0) try name_buf.appendSlice(self.allocator, ", ");
            try name_buf.appendSlice(self.allocator, ti.name);
        }
        try name_buf.appendSlice(self.allocator, ")");

        if (self.type_registry.get(name_buf.items)) |ti| return ti;

        const name = try self.allocator.dupe(u8, name_buf.items);
        try self.allocated_names.append(self.allocator, name);

        var info = try self.allocator.create(TypeInfo);
        info.* = .{
            .id = self.type_id_counter,
            .name = name,
            .total_size = 0,
            .fields = std.StringHashMap(FieldInfo).init(self.allocator),
            .variants = std.StringHashMap(VariantInfo).init(self.allocator),
            .is_tuple = true,
        };
        self.type_id_counter += 1;

        var current_offset: u32 = 8; // RC + ID
        for (element_types, 0..) |ti, i| {
            var buf: [16]u8 = undefined;
            const field_name = try std.fmt.bufPrint(&buf, "{d}", .{i});
            const field_name_dupe = try self.allocator.dupe(u8, field_name);
            try self.allocated_names.append(self.allocator, field_name_dupe);

            const f_size = if (ti.total_size > 0) ti.total_size else 4;
            if (f_size >= 4) current_offset = (current_offset + 3) & ~@as(u32, 3);
            
            try info.fields.put(field_name_dupe, .{
                .name = field_name_dupe,
                .offset = current_offset,
                .size = f_size,
                .type_name = ti.name,
            });
            current_offset += f_size;
        }
        info.total_size = (current_offset + 7) & ~@as(u32, 7);
        try self.type_registry.put(name, info);
        @import("logistics.zig").printReport(info.id, name, info.total_size, 4, 4);
        return info;
    }

    fn analyzeEnumDef(self: *Sema, node_idx: ast.NodeIndex) SemaError!void {
        const node = &self.tree.nodes.items[node_idx];
        const name = node.data.enum_def.name;

        if (node.data.enum_def.generic_params.len > 0) {
            try self.generic_definitions.put(name, node_idx);
            return;
        }

        var info = try self.allocator.create(TypeInfo);
        info.* = .{
            .id = self.type_id_counter,
            .name = name,
            .total_size = 4, // Tag (i32)
            .fields = std.StringHashMap(FieldInfo).init(self.allocator),
            .variants = std.StringHashMap(VariantInfo).init(self.allocator),
            .is_enum = true,
        };
        self.type_id_counter += 1;

        var max_payload_size: u32 = 0;
        var tag_counter: i32 = 0;

        for (node.data.enum_def.variants) |v_idx| {
            const v_node = &self.tree.nodes.items[v_idx];
            const v_name = v_node.data.variant_def.name;

            var payload_type_name: ?[]const u8 = null;
            if (v_node.data.variant_def.payload_type != 0) {
                const p_type = try self.analyzeType(v_node.data.variant_def.payload_type, null);
                payload_type_name = p_type.name;
                if (p_type.total_size > max_payload_size) max_payload_size = p_type.total_size;
            }

            var tag_val = tag_counter;
            if (v_node.data.variant_def.discriminator != 0) {
                 const d_node = &self.tree.nodes.items[v_node.data.variant_def.discriminator];
                 if (d_node.tag == .literal_int) {
                     tag_val = @intCast(d_node.data.literal_int);
                     tag_counter = tag_val; 
                 }
            }
            tag_counter += 1;

            if (info.variants.contains(v_name)) return error.DuplicateVariant;
            try info.variants.put(v_name, .{ .tag_value = tag_val, .payload_type = payload_type_name });

            try self.current_scope.define(.{
                .name = v_name,
                .node_idx = v_idx,
                .is_immutable = true,
                .is_private = false,
                .type_info = info,
                .variant_tag = tag_val,
            });
        }

        info.total_size += max_payload_size;
        if (max_payload_size > 0) {
            info.total_size = (info.total_size + 7) & ~@as(u32, 7);
        }

        try self.type_registry.put(name, info);
        try self.current_scope.define(.{
            .name = name,
            .node_idx = node_idx,
            .is_immutable = true,
            .is_private = false,
            .type_info = info,
        });
        @import("logistics.zig").printReport(info.id, name, info.total_size, 4, 4);
    }

    fn analyzeMatchExpr(self: *Sema, node_idx: ast.NodeIndex) SemaError!void {
        const node = &self.tree.nodes.items[node_idx];
        const target_expr = node.data.match_expr.target;
        try self.analyze(target_expr);

        const target_type = self.node_types.get(target_expr) orelse return error.TypeMismatch;
        if (!target_type.is_enum) return error.TypeMismatch;

        var result_type: ?*TypeInfo = null;

        for (node.data.match_expr.branches) |branch_idx| {
             const branch = &self.tree.nodes.items[branch_idx];
             const pattern_node = &self.tree.nodes.items[branch.data.match_branch.pattern];

             const old_scope = self.current_scope;
             const new_scope = try self.allocator.create(Scope);
             new_scope.* = Scope.init(self.allocator, old_scope);
             self.current_scope = new_scope;
             defer {
                 self.current_scope = old_scope;
                 new_scope.deinit();
                 self.allocator.destroy(new_scope);
             }

             var variant_name: []const u8 = undefined;
             var bind_name: ?[]const u8 = null;

             if (pattern_node.tag == .identifier) {
                 variant_name = pattern_node.data.identifier.name;
                 if (!target_type.variants.contains(variant_name)) return error.InvalidPattern;
                 const v_info = target_type.variants.get(variant_name).?;
                 pattern_node.resolved_index = @as(u32, @bitCast(v_info.tag_value)) | VARIANT_TAG_MASK;

             } else if (pattern_node.tag == .call) {
                 const base = &self.tree.nodes.items[pattern_node.data.call.base_node];
                 if (base.tag != .identifier) return error.InvalidPattern;
                 variant_name = base.data.identifier.name;

                 if (!target_type.variants.contains(variant_name)) return error.InvalidPattern;
                 const v_info = target_type.variants.get(variant_name).?;
                 pattern_node.resolved_index = @as(u32, @bitCast(v_info.tag_value)) | VARIANT_TAG_MASK;
                 
                 if (pattern_node.data.call.args.len == 1) {
                     const arg = &self.tree.nodes.items[pattern_node.data.call.args[0]];
                     if (arg.tag == .identifier) {
                         bind_name = arg.data.identifier.name;
                         
                         if (v_info.payload_type) |pt_name| {
                             const pt = self.type_registry.get(pt_name).?;
                             const local_idx = self.current_scope.next_local_index;
                             self.current_scope.next_local_index += 1;
                             try self.current_scope.define(.{
                                 .name = bind_name.?,
                                 .node_idx = pattern_node.data.call.args[0],
                                 .is_immutable = true,
                                 .is_private = false,
                                 .local_index = local_idx,
                                 .type_info = pt,
                             });
                             arg.resolved_index = local_idx;
                             try self.node_types.put(pattern_node.data.call.args[0], pt);
                         } else {
                             return error.TypeMismatch;
                         }
                     }
                 }
             } else {
                 return error.InvalidPattern;
             }

             try self.analyze(branch.data.match_branch.body);
             const body_type = self.node_types.get(branch.data.match_branch.body);
             if (result_type == null) result_type = body_type;
        }

        if (result_type) |rt| {
            try self.node_types.put(node_idx, rt);
        }
    }

    fn analyzeStructDef(self: *Sema, node_idx: ast.NodeIndex) SemaError!void {
        const node = &self.tree.nodes.items[node_idx];
        const name = node.data.struct_def.name;

        if (node.data.struct_def.generic_params.len > 0) {
            try self.generic_definitions.put(name, node_idx);
            return;
        }

        var info = try self.allocator.create(TypeInfo);
        info.* = .{
            .id = self.type_id_counter,
            .name = name,
            .total_size = 0,
            .fields = std.StringHashMap(FieldInfo).init(self.allocator),
            .variants = std.StringHashMap(VariantInfo).init(self.allocator),
        };
        self.type_id_counter += 1;

        var current_offset: u32 = 8; // SlotHeader
        for (node.data.struct_def.fields) |field_idx| {
            const field_node = &self.tree.nodes.items[field_idx];
            const f_name = field_node.data.field_def.name;
            const f_type_info = try self.analyzeType(field_node.data.field_def.type_node, null);

            const f_size = if (f_type_info.total_size > 0) f_type_info.total_size else 4;

            if (f_size >= 4) current_offset = (current_offset + 3) & ~@as(u32, 3);
            try info.fields.put(f_name, .{ .name = f_name, .offset = current_offset, .size = @intCast(f_size), .type_name = f_type_info.name });
            current_offset += @intCast(f_size);
        }
        info.total_size = (current_offset + 7) & ~@as(u32, 7);
        try self.type_registry.put(name, info);
        @import("logistics.zig").printReport(info.id, name, info.total_size, 4, 4);
        try self.current_scope.define(.{ .name = name, .node_idx = node_idx, .is_immutable = true, .is_private = false, .type_info = info });
    }

    fn analyzeStructInit(self: *Sema, node_idx: ast.NodeIndex) SemaError!void {
        const node = &self.tree.nodes.items[node_idx];
        if (node.data.struct_init.type_node == 0) return;

        const info = try self.analyzeType(node.data.struct_init.type_node, null);
        try self.node_types.put(node_idx, info);
        for (node.data.struct_init.entries) |entry_idx| {
            const entry = &self.tree.nodes.items[entry_idx];
            try self.analyze(entry.data.set_entry.value);
        }
    }

    fn analyzeAssignInit(self: *Sema, node_idx: ast.NodeIndex) SemaError!void {
        const node = &self.tree.nodes.items[node_idx];
        const lhs_idx = node.data.assign_init.lhs;
        const rhs_idx = node.data.assign_init.rhs;

        if (self.tree.nodes.items[lhs_idx].tag == .call) {
             try self.analyze(rhs_idx);
             const rhs_type = self.node_types.get(rhs_idx);
             if (rhs_type == null or !rhs_type.?.is_enum) return error.TypeMismatch;

             const lhs_call = &self.tree.nodes.items[lhs_idx];
             const base = &self.tree.nodes.items[lhs_call.data.call.base_node];
             if (base.tag != .identifier) return error.InvalidPattern;
             const variant_name = base.data.identifier.name;
             
             if (!rhs_type.?.variants.contains(variant_name)) return error.InvalidPattern;
             const v_info = rhs_type.?.variants.get(variant_name).?;
             lhs_call.resolved_index = @as(u32, @bitCast(v_info.tag_value)) | VARIANT_TAG_MASK;

             if (lhs_call.data.call.args.len == 1) {
                  const arg = &self.tree.nodes.items[lhs_call.data.call.args[0]];
                  if (arg.tag == .identifier) {
                       const bind_name = arg.data.identifier.name;
                       if (v_info.payload_type) |pt_name| {
                           const pt = self.type_registry.get(pt_name).?;
                           const local_idx = self.current_scope.next_local_index;
                           self.current_scope.next_local_index += 1;
                           try self.current_scope.define(.{
                               .name = bind_name,
                               .node_idx = lhs_call.data.call.args[0],
                               .is_immutable = true,
                               .is_private = false,
                               .local_index = local_idx,
                               .type_info = pt,
                           });
                           arg.resolved_index = local_idx;
                       }
                  }
             }
             return;
        }

        try self.analyze(rhs_idx);

        const lhs = &self.tree.nodes.items[lhs_idx];
        if (lhs.tag != .identifier) return error.InvalidAssignmentLHS;

        const local_idx = self.current_scope.next_local_index;
        self.current_scope.next_local_index += 1;

        const type_info = self.node_types.get(rhs_idx);

        try self.current_scope.define(.{
            .name = lhs.data.identifier.name,
            .node_idx = lhs_idx,
            .is_immutable = lhs.data.identifier.attr.is_immutable,
            .is_private = lhs.data.identifier.attr.is_private,
            .local_index = local_idx,
            .type_info = type_info,
        });
        lhs.resolved_index = local_idx;
        if (type_info) |ti| try self.node_types.put(lhs_idx, ti);
    }

    fn analyzeAssign(self: *Sema, node_idx: ast.NodeIndex) SemaError!void {
        const node = &self.tree.nodes.items[node_idx];
        const lhs_idx = node.data.assign.lhs;
        const rhs_idx = node.data.assign.rhs;

        const lhs_node = &self.tree.nodes.items[lhs_idx];
        if (lhs_node.tag == .tuple_literal) {
            try self.analyze(rhs_idx);
            const rhs_type = self.node_types.get(rhs_idx) orelse return error.TypeMismatch;
            
            // Allow destructuring of Tuples (and potentially Structs later if mapped by index/order?)
            // For now only strict Tuple support or Structs with matching field count? 
            // The request is about Tuple destructuring.
            if (!rhs_type.is_tuple) return error.TypeMismatch;
            
            // Check count
            // Note: tuple types use "0", "1"... as field names.
            // We assume fields are populated.
            if (lhs_node.data.tuple_literal.elements.len != rhs_type.fields.count()) return error.TypeMismatch;

            for (lhs_node.data.tuple_literal.elements, 0..) |elem_idx, i| {
                const elem = &self.tree.nodes.items[elem_idx];
                if (elem.tag != .identifier) return error.InvalidAssignmentLHS;

                var buf: [16]u8 = undefined;
                const field_name = try std.fmt.bufPrint(&buf, "{d}", .{i});
                const field = rhs_type.fields.get(field_name) orelse return error.FieldNotFound;
                const field_type = self.type_registry.get(field.type_name).?;

                const name = elem.data.identifier.name;
                
                // Define or Update? The example `(a, b) = t` looks like definition if they don't exist.
                // Standard `assign` handles both (update existing or define new in `do`).
                
                if (self.current_scope.lookupPtr(name)) |sym| {
                    if (sym.is_immutable) return error.ImmutableVariableModified;
                    elem.resolved_index = sym.local_index;
                    sym.type_info = field_type;
                } else {
                    const local_idx = self.current_scope.next_local_index;
                    self.current_scope.next_local_index += 1;
                    try self.current_scope.define(.{
                        .name = name,
                        .node_idx = elem_idx,
                        .is_immutable = false,
                        .is_private = false,
                        .local_index = local_idx,
                        .type_info = field_type,
                    });
                    elem.resolved_index = local_idx;
                }
                try self.node_types.put(elem_idx, field_type);
            }
            return;
        }

        try self.analyze(rhs_idx);

        const lhs = &self.tree.nodes.items[lhs_idx];
        if (lhs.tag != .identifier) return error.InvalidAssignmentLHS;
        const name = lhs.data.identifier.name;

        const rhs_type = self.node_types.get(rhs_idx);

        if (self.current_scope.lookupPtr(name)) |sym| {
            if (sym.is_immutable) return error.ImmutableVariableModified;
            lhs.resolved_index = sym.local_index;
            sym.type_info = rhs_type;
        } else {
            const local_idx = self.current_scope.next_local_index;
            self.current_scope.next_local_index += 1;
            try self.current_scope.define(.{
                .name = name,
                .node_idx = lhs_idx,
                .is_immutable = lhs.data.identifier.attr.is_immutable,
                .is_private = lhs.data.identifier.attr.is_private,
                .local_index = local_idx,
                .type_info = rhs_type,
            });
            lhs.resolved_index = local_idx;
        }
        if (rhs_type) |ti| try self.node_types.put(lhs_idx, ti);
    }

    fn analyzeIdentifier(self: *Sema, node_idx: ast.NodeIndex) SemaError!void {
        var node = &self.tree.nodes.items[node_idx];
        if (self.current_scope.lookupPtr(node.data.identifier.name)) |sym| {
            if (sym.variant_tag) |tag| {
                node.resolved_index = @as(u32, @bitCast(tag)) | VARIANT_TAG_MASK;
                if (sym.type_info) |ti| try self.node_types.put(node_idx, ti);
            } else {
                if (sym.last_use_node) |prev_idx| {
                    self.tree.nodes.items[prev_idx].is_last_use = false;
                }
                node.is_last_use = true;
                node.resolved_index = sym.local_index;
                sym.last_use_node = node_idx;
                if (sym.type_info) |ti| try self.node_types.put(node_idx, ti);
            }
        } else {
            return error.UndefinedVariable;
        }
    }

    fn analyzePathGet(self: *Sema, node_idx: ast.NodeIndex) SemaError!void {
        const node = &self.tree.nodes.items[node_idx];
        try self.analyze(node.data.path_get.target);

        const type_ptr = self.node_types.get(node.data.path_get.target) orelse return;
        var current_type = type_ptr;

        for (node.data.path_get.path) |segment_idx| {
            const segment = &self.tree.nodes.items[segment_idx];
            var field_name: []const u8 = undefined;
            if (segment.tag == .identifier) {
                field_name = segment.data.identifier.name;
            } else if (segment.tag == .literal_int) {
                var buf: [16]u8 = undefined;
                const name = try std.fmt.bufPrint(&buf, "{d}", .{segment.data.literal_int});
                field_name = try self.allocator.dupe(u8, name);
                try self.allocated_names.append(self.allocator, field_name);
            } else {
                return error.FieldNotFound;
            }

            var field_info = current_type.fields.get(field_name);

            if (field_info == null and field_name.len > 1 and field_name[0] == '.') {
                field_info = current_type.fields.get(field_name[1..]);
            }

            if (field_info) |field| {
                current_type = self.type_registry.get(field.type_name) orelse return;
            } else {
                return error.FieldNotFound;
            }
        }
        try self.node_types.put(node_idx, current_type);
    }

    fn analyzePathSet(self: *Sema, node_idx: ast.NodeIndex) SemaError!void {
        const node = &self.tree.nodes.items[node_idx];
        try self.analyze(node.data.path_set.target);

        const target_type_ptr = self.node_types.get(node.data.path_set.target) orelse return;
        try self.node_types.put(node_idx, target_type_ptr);

        for (node.data.path_set.entries) |entry_idx| {
            const entry = &self.tree.nodes.items[entry_idx];
            try self.analyze(entry.data.set_entry.value);

            var current_type = target_type_ptr;
            const path_node = self.tree.nodes.items[entry.data.set_entry.path];
            const segments = if (path_node.tag == .path_sequence) path_node.data.path_sequence.segments else &[_]u32{entry.data.set_entry.path};

            for (segments) |seg_idx| {
                const seg = &self.tree.nodes.items[seg_idx];
                var field_name: []const u8 = undefined;
                if (seg.tag == .identifier) {
                    field_name = seg.data.identifier.name;
                } else if (seg.tag == .literal_int) {
                    var buf: [16]u8 = undefined;
                    const name = try std.fmt.bufPrint(&buf, "{d}", .{seg.data.literal_int});
                    field_name = try self.allocator.dupe(u8, name);
                    try self.allocated_names.append(self.allocator, field_name);
                } else {
                    return error.FieldNotFound;
                }

                var field_info = current_type.fields.get(field_name);
                if (field_info == null and field_name.len > 1 and field_name[0] == '.') {
                    field_info = current_type.fields.get(field_name[1..]);
                }

                if (field_info) |field| {
                    current_type = self.getOrAnalyzeTypeByName(field.type_name) orelse return;
                } else {
                    return error.FieldNotFound;
                }
            }
        }
    }

    fn analyzeType(self: *Sema, node_idx: ast.NodeIndex, type_mapping: ?std.StringHashMap(*TypeInfo)) SemaError!*TypeInfo {
        const node = &self.tree.nodes.items[node_idx];

        if (node.tag == .tuple_type) {
            var element_types = std.ArrayListUnmanaged(*TypeInfo){};
            defer element_types.deinit(self.allocator);
            for (node.data.tuple_type.elements) |e_idx| {
                try element_types.append(self.allocator, try self.analyzeType(e_idx, type_mapping));
            }
            return try self.getOrCreateTupleType(element_types.items);
        }

        var base_name: []const u8 = undefined;
        var has_params = false;

        if (node.tag == .type_apply) {
            base_name = node.data.type_apply.base_name;
            has_params = node.data.type_apply.params.len > 0;
        } else if (node.tag == .identifier) {
            base_name = node.data.identifier.name;
            has_params = false;
        } else {
            return error.TypeMismatch;
        }

        if (std.mem.eql(u8, base_name, "Tuple") and has_params) {
            var element_types = std.ArrayListUnmanaged(*TypeInfo){};
            defer element_types.deinit(self.allocator);
            for (node.data.type_apply.params) |p_idx| {
                try element_types.append(self.allocator, try self.analyzeType(p_idx, type_mapping));
            }
            return try self.getOrCreateTupleType(element_types.items);
        }

        if (type_mapping) |tm| {
            if (tm.get(base_name)) |ti| return ti;
        }

        if (!has_params) {
            return self.type_registry.get(base_name) orelse {
                if (std.mem.eql(u8, base_name, "i32") or std.mem.eql(u8, base_name, "u32") or std.mem.eql(u8, base_name, "int") or
                    std.mem.eql(u8, base_name, "f32") or std.mem.eql(u8, base_name, "f64") or std.mem.eql(u8, base_name, "i64") or std.mem.eql(u8, base_name, "u64") or
                    std.mem.eql(u8, base_name, "i8") or std.mem.eql(u8, base_name, "u8") or std.mem.eql(u8, base_name, "text"))
                {
                    return self.getPrimitiveType(base_name);
                }
                return error.UndefinedVariable;
            };
        }

        return try self.instantiateType(node_idx, type_mapping);
    }

    fn instantiateType(self: *Sema, node_idx: ast.NodeIndex, type_mapping: ?std.StringHashMap(*TypeInfo)) SemaError!*TypeInfo {
        const node = &self.tree.nodes.items[node_idx];
        const base_name = node.data.type_apply.base_name;

        var full_name = std.ArrayListUnmanaged(u8){};
        defer full_name.deinit(self.allocator);
        try full_name.appendSlice(self.allocator, base_name);

        var param_types = std.ArrayListUnmanaged(*TypeInfo){};
        defer param_types.deinit(self.allocator);

        for (node.data.type_apply.params) |p_idx| {
            const p_type = try self.analyzeType(p_idx, type_mapping);
            try param_types.append(self.allocator, p_type);
            try full_name.append(self.allocator, '_');
            try full_name.appendSlice(self.allocator, p_type.name);
        }

        const m_name = try self.allocator.dupe(u8, full_name.items);
        try self.allocated_names.append(self.allocator, m_name);
        if (self.monomorphized_types.get(m_name)) |ti| return ti;

        const def_idx = self.generic_definitions.get(base_name) orelse return error.UndefinedVariable;
        const def_node = &self.tree.nodes.items[def_idx];

        var info = try self.allocator.create(TypeInfo);
        info.* = .{
            .id = self.type_id_counter,
            .name = m_name,
            .total_size = 0,
            .fields = std.StringHashMap(FieldInfo).init(self.allocator),
            .variants = std.StringHashMap(VariantInfo).init(self.allocator),
        };
        self.type_id_counter += 1;
        try self.monomorphized_types.put(m_name, info);
        try self.type_registry.put(m_name, info);

        var local_mapping = std.StringHashMap(*TypeInfo).init(self.allocator);
        defer local_mapping.deinit();
        for (def_node.data.struct_def.generic_params, 0..) |gp_idx, i| {
            const param_node = &self.tree.nodes.items[gp_idx];
            const gp_name = param_node.data.generic_param.name;
            const p_type = param_types.items[i];
            try local_mapping.put(gp_name, p_type);
        }

        var current_offset: u32 = 8;
        for (def_node.data.struct_def.fields) |field_idx| {
            const field_node = &self.tree.nodes.items[field_idx];
            const f_name = field_node.data.field_def.name;
            const f_type_info = try self.analyzeType(field_node.data.field_def.type_node, local_mapping);

            const f_size = if (f_type_info.total_size > 0) f_type_info.total_size else 4;

            if (f_size >= 4) current_offset = (current_offset + 3) & ~@as(u32, 3);
            try info.fields.put(f_name, .{ .name = f_name, .offset = current_offset, .size = @intCast(f_size), .type_name = f_type_info.name });
            current_offset += @intCast(f_size);
        }
        info.total_size = (current_offset + 7) & ~@as(u32, 7);

        @import("logistics.zig").printReport(info.id, m_name, info.total_size, 4, 4);
        return info;
    }

    fn analyzeCall(self: *Sema, node_idx: ast.NodeIndex) SemaError!void {
        var node = &self.tree.nodes.items[node_idx];
        const target_node_idx = node.data.call.base_node;
        const args = node.data.call.args;

        for (args) |arg_idx| {
            try self.analyze(arg_idx);
        }

        const target = &self.tree.nodes.items[target_node_idx];
        if (target.tag == .identifier) {
            const name = target.data.identifier.name;
            if (self.current_scope.lookupPtr(name)) |sym| {
                 if (sym.variant_tag) |tag| {
                     node.resolved_index = @as(u32, @bitCast(tag)) | VARIANT_TAG_MASK;
                     if (sym.type_info) |ti| try self.node_types.put(node_idx, ti);
                     return;
                 }
            }

            if (self.generic_definitions.get(name)) |def_idx| {
                const def_node = &self.tree.nodes.items[def_idx];
                if (def_node.tag == .fn_def) {
                    return;
                }
            }
            if (std.mem.eql(u8, name, "get") or std.mem.eql(u8, name, "set")) return;
        } else if (target.tag == .type_apply) {
            const base_name = target.data.type_apply.base_name;
            if (std.mem.eql(u8, base_name, "Tuple")) {
                // Change current node to tuple_literal
                var element_types = std.ArrayListUnmanaged(*TypeInfo){};
                defer element_types.deinit(self.allocator);
                for (args) |arg_idx| {
                    const ti = self.node_types.get(arg_idx) orelse return error.TypeMismatch;
                    try element_types.append(self.allocator, ti);
                }
                const info = try self.getOrCreateTupleType(element_types.items);
                
                node.tag = .tuple_literal;
                node.data = .{ .tuple_literal = .{ .elements = try self.allocator.dupe(ast.NodeIndex, args) } };
                try self.node_types.put(node_idx, info);
                return;
            }

            if (self.generic_definitions.get(base_name)) |def_idx| {
                const def_node = &self.tree.nodes.items[def_idx];
                if (def_node.tag == .fn_def) {
                    _ = try self.instantiateFunction(target_node_idx, null);
                    return;
                }
            }
            _ = try self.analyzeType(target_node_idx, null);
        }
    }

    fn instantiateFunction(self: *Sema, apply_node_idx: ast.NodeIndex, type_mapping: ?std.StringHashMap(*TypeInfo)) SemaError!void {
        const apply_node = &self.tree.nodes.items[apply_node_idx];
        const base_name = apply_node.data.type_apply.base_name;

        var param_types = std.ArrayListUnmanaged(*TypeInfo){};
        defer param_types.deinit(self.allocator);
        for (apply_node.data.type_apply.params) |p_idx| {
            try param_types.append(self.allocator, try self.analyzeType(p_idx, type_mapping));
        }

        const def_idx = self.generic_definitions.get(base_name) orelse return error.UndefinedVariable;
        const def_node = &self.tree.nodes.items[def_idx];

        var local_mapping = std.StringHashMap(*TypeInfo).init(self.allocator);
        defer local_mapping.deinit();
        for (def_node.data.fn_def.generic_params, 0..) |gp_idx, i| {
            const param_node = &self.tree.nodes.items[gp_idx];
            const gp_name = param_node.data.generic_param.name;
            const p_type = param_types.items[i];
            try local_mapping.put(gp_name, p_type);
        }

        const old_scope = self.current_scope;
        const new_scope = try self.allocator.create(Scope);
        new_scope.* = Scope.init(self.allocator, old_scope);
        self.current_scope = new_scope;
        defer {
            self.current_scope = old_scope;
            new_scope.deinit();
            self.allocator.destroy(new_scope);
        }

        for (def_node.data.fn_def.params) |param_idx| {
            const param_node = &self.tree.nodes.items[param_idx];
            const p_name = param_node.data.param.name;
            const p_ti = if (param_node.data.param.type_node != 0)
                try self.analyzeType(param_node.data.param.type_node, local_mapping)
            else
                null;
            try self.current_scope.define(.{
                .name = p_name,
                .node_idx = param_idx,
                .is_immutable = true,
                .is_private = false,
                .type_info = p_ti,
            });
        }

        try self.analyze(def_node.data.fn_def.body);
    }

    fn getPrimitiveType(self: *Sema, name: []const u8) *TypeInfo {
        if (self.type_registry.get(name)) |ti| return ti;
        const info = self.allocator.create(TypeInfo) catch unreachable;
        var size: u32 = 4;
        if (std.mem.endsWith(u8, name, "64")) size = 8;
        info.* = .{ .id = 0, .name = name, .total_size = size, .fields = std.StringHashMap(FieldInfo).init(self.allocator), .variants = std.StringHashMap(VariantInfo).init(self.allocator), .is_tuple = false };
        self.type_registry.put(name, info) catch unreachable;
        return info;
    }

    fn getOrAnalyzeTypeByName(self: *Sema, name: []const u8) ?*TypeInfo {
        if (self.type_registry.get(name)) |ti| return ti;
        return null;
    }
};