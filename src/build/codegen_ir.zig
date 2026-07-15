const std = @import("std");

pub const ValueId = struct {
    index: usize,
};

const ValueName = struct {
    id: ValueId,
    name: []const u8,
};

pub const BlockId = struct {
    index: usize,
};

pub const ScalarType = enum {
    i32,
    i64,
    f32,
    f64,
};

pub const ConstValue = union(enum) {
    i32: i32,
    i64: i64,
    f32: f32,
    f64: f64,
};

pub const NumericOp = enum {
    add,
    sub,
    mul,
    div_s,
    div_u,
    rem_s,
    rem_u,
    and_,
    or_,
    xor,
    shl,
    shr_s,
    shr_u,
};

pub const CompareOp = enum {
    eq,
    ne,
    lt_s,
    lt_u,
    gt_s,
    gt_u,
    le_s,
    le_u,
    ge_s,
    ge_u,
};

pub const NumericInstr = struct {
    ty: ScalarType,
    op: NumericOp,
};

pub const CompareInstr = struct {
    ty: ScalarType,
    op: CompareOp,
};

pub const ConditionalBranch = struct {
    condition: ValueId,
    then_block: BlockId,
    else_block: BlockId,
};

pub const Instr = union(enum) {
    const_i32: i32,
    const_value: ConstValue,
    local_get: ValueId,
    local_set: ValueId,
    local_tee: ValueId,
    numeric: NumericInstr,
    compare: CompareInstr,
    call: []const u8,
};

pub const Terminator = union(enum) {
    ret,
    ret_value: ValueId,
    br: BlockId,
    br_if: ConditionalBranch,
};

pub const Block = struct {
    id: BlockId,
    instrs: std.ArrayList(Instr) = .empty,
    terminator: ?Terminator = null,

    fn deinit(self: *Block, allocator: std.mem.Allocator) void {
        self.instrs.deinit(allocator);
    }
};

pub const Function = struct {
    name: []const u8,
    blocks: std.ArrayList(Block) = .empty,
    value_names: std.ArrayList(ValueName) = .empty,
    next_value_id: usize = 0,
    next_block_id: usize = 0,

    pub fn deinit(self: *Function, allocator: std.mem.Allocator) void {
        for (self.blocks.items) |*block| block.deinit(allocator);
        self.blocks.deinit(allocator);
        self.value_names.deinit(allocator);
    }

    pub fn create(allocator: std.mem.Allocator, name: []const u8) !Function {
        _ = allocator;
        return .{ .name = name };
    }

    pub fn alloc_value(self: *Function) ValueId {
        defer self.next_value_id += 1;
        return .{ .index = self.next_value_id };
    }

    pub fn set_value_name(self: *Function, allocator: std.mem.Allocator, id: ValueId, name: []const u8) !void {
        for (self.value_names.items) |*entry| {
            if (entry.id.index == id.index) {
                entry.name = name;
                return;
            }
        }
        try self.value_names.append(allocator, .{ .id = id, .name = name });
    }

    pub fn add_block(self: *Function, allocator: std.mem.Allocator) !*Block {
        const id = try self.add_block_id(allocator);
        return try self.get_block(id);
    }

    pub fn add_block_id(self: *Function, allocator: std.mem.Allocator) !BlockId {
        const id = BlockId{ .index = self.next_block_id };
        self.next_block_id += 1;
        try self.blocks.append(allocator, .{
            .id = id,
        });
        return id;
    }

    pub fn append_instr(self: *Function, allocator: std.mem.Allocator, block_id: BlockId, instr: Instr) !void {
        const block = try self.get_block(block_id);
        try block.instrs.append(allocator, instr);
    }

    pub fn set_terminator(self: *Function, block_id: BlockId, terminator: Terminator) !void {
        const block = try self.get_block(block_id);
        block.terminator = terminator;
    }

    pub fn get_block(self: *Function, id: BlockId) !*Block {
        for (self.blocks.items) |*block| {
            if (block.id.index == id.index) return block;
        }
        return error.InvalidBlockId;
    }

    fn value_name(self: *const Function, id: ValueId) ?[]const u8 {
        for (self.value_names.items) |entry| {
            if (entry.id.index == id.index) return entry.name;
        }
        return null;
    }

    pub fn fold_empty_branch_blocks(self: *Function, allocator: std.mem.Allocator) !void {
        if (self.blocks.items.len < 3) return;

        for (self.blocks.items) |*block| {
            self.fold_terminator_branch_targets(block);
        }

        var i = self.blocks.items.len;
        while (i > 0) {
            i -= 1;
            const block = self.blocks.items[i];
            if (!is_foldable_empty_branch_block(block)) continue;
            if (i == 0) continue;
            var removed = self.blocks.orderedRemove(i);
            removed.deinit(allocator);
        }
    }

    fn fold_terminator_branch_targets(self: *Function, block: *Block) void {
        const term = block.terminator orelse return;
        switch (term) {
            .br => |target| {
                block.terminator = .{ .br = self.resolve_branch_target(target) };
            },
            .br_if => |branch| {
                block.terminator = .{ .br_if = .{
                    .condition = branch.condition,
                    .then_block = self.resolve_branch_target(branch.then_block),
                    .else_block = self.resolve_branch_target(branch.else_block),
                } };
            },
            else => {},
        }
    }

    fn resolve_branch_target(self: *const Function, start: BlockId) BlockId {
        var current = start;
        while (true) {
            const block = self.find_block(current) orelse return current;
            if (!is_foldable_empty_branch_block(block.*)) return current;
            current = block.terminator.?.br;
        }
    }

    fn find_block(self: *const Function, id: BlockId) ?*const Block {
        for (self.blocks.items) |*block| {
            if (block.id.index == id.index) return block;
        }
        return null;
    }

    pub fn fold_redundant_local_copies(self: *Function) void {
        for (self.blocks.items) |*block| {
            var i: usize = 0;
            while (i + 1 < block.instrs.items.len) {
                const first = block.instrs.items[i];
                const second = block.instrs.items[i + 1];
                if (first == .local_get and second == .local_set and first.local_get.index == second.local_set.index) {
                    _ = block.instrs.orderedRemove(i + 1);
                    _ = block.instrs.orderedRemove(i);
                    continue;
                }
                i += 1;
            }
        }
    }

    pub fn fold_constant_numeric_ops(self: *Function) void {
        for (self.blocks.items) |*block| {
            var i: usize = 0;
            while (i + 2 < block.instrs.items.len) {
                const left = instr_i32_const(block.instrs.items[i]) orelse {
                    i += 1;
                    continue;
                };
                const right = instr_i32_const(block.instrs.items[i + 1]) orelse {
                    i += 1;
                    continue;
                };
                const numeric = block.instrs.items[i + 2];
                if (numeric != .numeric or numeric.numeric.ty != .i32) {
                    i += 1;
                    continue;
                }
                const folded = fold_i32_numeric(left, right, numeric.numeric.op) orelse {
                    i += 1;
                    continue;
                };
                block.instrs.items[i] = .{ .const_value = .{ .i32 = folded } };
                _ = block.instrs.orderedRemove(i + 2);
                _ = block.instrs.orderedRemove(i + 1);
            }
        }
    }
};

pub const Module = struct {
    functions: std.ArrayList(Function) = .empty,

    pub fn deinit(self: *Module, allocator: std.mem.Allocator) void {
        for (self.functions.items) |*func| func.deinit(allocator);
        self.functions.deinit(allocator);
    }

    pub fn add_function(self: *Module, allocator: std.mem.Allocator, func: Function) !void {
        try self.functions.append(allocator, func);
    }

    pub fn inline_trivial_const_calls(self: *Module, allocator: std.mem.Allocator) !void {
        _ = allocator;
        for (self.functions.items) |*caller| {
            for (caller.blocks.items) |*block| {
                self.inline_trivial_const_calls_in_block(block);
            }
        }
    }

    fn inline_trivial_const_calls_in_block(self: *Module, block: *Block) void {
        var i: usize = 0;
        while (i < block.instrs.items.len) : (i += 1) {
            const instr = block.instrs.items[i];
            if (instr != .call) continue;
            const callee = self.find_function(instr.call) orelse continue;
            const value = trivial_const_return(callee) orelse continue;
            block.instrs.items[i] = .{ .const_i32 = value };
        }
    }

    fn find_function(self: *const Module, name: []const u8) ?*Function {
        for (self.functions.items) |*func| {
            if (std.mem.eql(u8, func.name, name)) return func;
        }
        return null;
    }
};

fn trivial_const_return(func: *const Function) ?i32 {
    if (func.blocks.items.len != 1) return null;
    const block = func.blocks.items[0];
    if (block.instrs.items.len != 1) return null;
    const terminator = block.terminator orelse return null;
    if (terminator != .ret) return null;
    const instr = block.instrs.items[0];
    if (instr != .const_i32) return null;
    return instr.const_i32;
}

fn instr_i32_const(instr: Instr) ?i32 {
    return switch (instr) {
        .const_i32 => |value| value,
        .const_value => |value| switch (value) {
            .i32 => |i32_value| i32_value,
            else => null,
        },
        else => null,
    };
}

fn fold_i32_numeric(left: i32, right: i32, op: NumericOp) ?i32 {
    return switch (op) {
        .add => left +% right,
        .sub => left -% right,
        .mul => left *% right,
        else => null,
    };
}

pub fn emit_function_wat(allocator: std.mem.Allocator, func: *const Function) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    try append_fmt(&out, allocator, "  (func ${s}\n", .{func.name});
    try emit_function_body_wat_into(&out, allocator, func);
    try out.appendSlice(allocator, "  )\n");
    return out.toOwnedSlice(allocator);
}

pub fn emit_function_body_wat(allocator: std.mem.Allocator, func: *const Function) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try emit_function_body_wat_into(&out, allocator, func);
    return out.toOwnedSlice(allocator);
}

fn emit_function_body_wat_into(out: *std.ArrayList(u8), allocator: std.mem.Allocator, func: *const Function) !void {
    if (func.blocks.items.len == 1) {
        try emit_return_block_wat(out, allocator, func, &func.blocks.items[0], "    ");
    } else if (func.blocks.items.len == 3) {
        try emit_structured_if_wat(out, allocator, func);
    } else {
        return error.UnsupportedIrWatShape;
    }
}

fn emit_structured_if_wat(out: *std.ArrayList(u8), allocator: std.mem.Allocator, func: *const Function) !void {
    const entry = func.blocks.items[0];
    const term = entry.terminator orelse return error.UnsupportedIrWatShape;
    if (term != .br_if) return error.UnsupportedIrWatShape;
    const branch = term.br_if;
    const then_block = func.find_block(branch.then_block) orelse return error.InvalidBlockId;
    const else_block = func.find_block(branch.else_block) orelse return error.InvalidBlockId;

    if (entry.instrs.items.len == 0) {
        try emit_local_get_wat(out, allocator, func, "    ", branch.condition);
    } else {
        try emit_instrs_wat(out, allocator, func, entry.instrs.items, "    ");
    }
    try out.appendSlice(allocator, "    if\n");
    try emit_return_block_wat(out, allocator, func, then_block, "      ");
    try out.appendSlice(allocator, "    else\n");
    try emit_return_block_wat(out, allocator, func, else_block, "      ");
    try out.appendSlice(allocator, "    end\n");
}

fn emit_return_block_wat(out: *std.ArrayList(u8), allocator: std.mem.Allocator, func: *const Function, block: *const Block, indent: []const u8) !void {
    try emit_instrs_wat(out, allocator, func, block.instrs.items, indent);
    const term = block.terminator orelse return error.UnsupportedIrWatShape;
    switch (term) {
        .ret => try append_fmt(out, allocator, "{s}return\n", .{indent}),
        .ret_value => |value| {
            try emit_local_get_wat(out, allocator, func, indent, value);
            try append_fmt(out, allocator, "{s}return\n", .{indent});
        },
        else => return error.UnsupportedIrWatShape,
    }
}

fn emit_instrs_wat(out: *std.ArrayList(u8), allocator: std.mem.Allocator, func: *const Function, instrs: []const Instr, indent: []const u8) !void {
    for (instrs) |instr| {
        try emit_instr_wat(out, allocator, func, instr, indent);
    }
}

fn emit_instr_wat(out: *std.ArrayList(u8), allocator: std.mem.Allocator, func: *const Function, instr: Instr, indent: []const u8) !void {
    switch (instr) {
        .const_i32 => |value| try append_fmt(out, allocator, "{s}i32.const {d}\n", .{ indent, value }),
        .const_value => |value| try emit_const_value_wat(out, allocator, indent, value),
        .local_get => |value| try emit_local_get_wat(out, allocator, func, indent, value),
        .local_set => |value| try emit_local_write_wat(out, allocator, func, indent, "local.set", value),
        .local_tee => |value| try emit_local_write_wat(out, allocator, func, indent, "local.tee", value),
        .numeric => |op| try append_fmt(out, allocator, "{s}{s}.{s}\n", .{ indent, scalar_wat_prefix(op.ty), numeric_wat_name(op.op) }),
        .compare => |op| try append_fmt(out, allocator, "{s}{s}.{s}\n", .{ indent, scalar_wat_prefix(op.ty), compare_wat_name(op.op) }),
        .call => |name| try append_fmt(out, allocator, "{s}call ${s}\n", .{ indent, name }),
    }
}

fn emit_const_value_wat(out: *std.ArrayList(u8), allocator: std.mem.Allocator, indent: []const u8, value: ConstValue) !void {
    switch (value) {
        .i32 => |v| try append_fmt(out, allocator, "{s}i32.const {d}\n", .{ indent, v }),
        .i64 => |v| try append_fmt(out, allocator, "{s}i64.const {d}\n", .{ indent, v }),
        .f32 => |v| try append_fmt(out, allocator, "{s}f32.const {d}\n", .{ indent, v }),
        .f64 => |v| try append_fmt(out, allocator, "{s}f64.const {d}\n", .{ indent, v }),
    }
}

fn emit_local_get_wat(out: *std.ArrayList(u8), allocator: std.mem.Allocator, func: *const Function, indent: []const u8, value: ValueId) !void {
    try emit_local_write_wat(out, allocator, func, indent, "local.get", value);
}

fn emit_local_write_wat(out: *std.ArrayList(u8), allocator: std.mem.Allocator, func: *const Function, indent: []const u8, op: []const u8, value: ValueId) !void {
    try append_fmt(out, allocator, "{s}{s} $", .{ indent, op });
    if (func.value_name(value)) |name| {
        try out.appendSlice(allocator, name);
    } else {
        try append_fmt(out, allocator, "v{d}", .{value.index});
    }
    try out.appendSlice(allocator, "\n");
}

fn scalar_wat_prefix(ty: ScalarType) []const u8 {
    return switch (ty) {
        .i32 => "i32",
        .i64 => "i64",
        .f32 => "f32",
        .f64 => "f64",
    };
}

fn numeric_wat_name(op: NumericOp) []const u8 {
    return switch (op) {
        .add => "add",
        .sub => "sub",
        .mul => "mul",
        .div_s => "div_s",
        .div_u => "div_u",
        .rem_s => "rem_s",
        .rem_u => "rem_u",
        .and_ => "and",
        .or_ => "or",
        .xor => "xor",
        .shl => "shl",
        .shr_s => "shr_s",
        .shr_u => "shr_u",
    };
}

fn compare_wat_name(op: CompareOp) []const u8 {
    return switch (op) {
        .eq => "eq",
        .ne => "ne",
        .lt_s => "lt_s",
        .lt_u => "lt_u",
        .gt_s => "gt_s",
        .gt_u => "gt_u",
        .le_s => "le_s",
        .le_u => "le_u",
        .ge_s => "ge_s",
        .ge_u => "ge_u",
    };
}

fn append_fmt(out: *std.ArrayList(u8), allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}

fn is_foldable_empty_branch_block(block: Block) bool {
    if (block.instrs.items.len != 0) return false;
    const term = block.terminator orelse return false;
    return switch (term) {
        .br => true,
        else => false,
    };
}

test "backend ir function keeps block and terminator order" {
    const allocator = std.testing.allocator;
    var func = try Function.create(allocator, "sample");
    defer func.deinit(allocator);

    const block = try func.add_block(allocator);
    const v0 = func.alloc_value();
    try block.instrs.append(allocator, .{ .const_i32 = 7 });
    try block.instrs.append(allocator, .{ .local_set = v0 });
    block.terminator = .ret;

    try std.testing.expectEqualStrings("sample", func.name);
    try std.testing.expectEqual(@as(usize, 1), func.blocks.items.len);
    try std.testing.expectEqual(@as(usize, 2), block.instrs.items.len);
    try std.testing.expect(block.terminator != null);
}

test "backend ir allocates distinct value ids" {
    const allocator = std.testing.allocator;
    var func = try Function.create(allocator, "ids");
    defer func.deinit(allocator);

    const a = func.alloc_value();
    const b = func.alloc_value();
    try std.testing.expect(a.index != b.index);
}

test "backend ir represents scalar constants and operators" {
    const allocator = std.testing.allocator;
    var func = try Function.create(allocator, "scalar_ops");
    defer func.deinit(allocator);

    const block = try func.add_block(allocator);
    try block.instrs.append(allocator, .{ .const_value = .{ .i64 = 9 } });
    try block.instrs.append(allocator, .{ .const_value = .{ .i64 = 3 } });
    try block.instrs.append(allocator, .{ .numeric = .{ .ty = .i64, .op = .add } });
    try block.instrs.append(allocator, .{ .const_value = .{ .i64 = 20 } });
    try block.instrs.append(allocator, .{ .compare = .{ .ty = .i64, .op = .lt_s } });
    block.terminator = .ret;

    try std.testing.expectEqual(Instr{ .const_value = .{ .i64 = 9 } }, block.instrs.items[0]);
    try std.testing.expectEqual(Instr{ .numeric = .{ .ty = .i64, .op = .add } }, block.instrs.items[2]);
    try std.testing.expectEqual(Instr{ .compare = .{ .ty = .i64, .op = .lt_s } }, block.instrs.items[4]);
}

test "backend ir represents conditional branch and value return" {
    const allocator = std.testing.allocator;
    var func = try Function.create(allocator, "branch_return");
    defer func.deinit(allocator);

    const entry_id = (try func.add_block(allocator)).id;
    const then_id = (try func.add_block(allocator)).id;
    const else_id = (try func.add_block(allocator)).id;

    const condition = func.alloc_value();
    const result = func.alloc_value();
    const entry = &func.blocks.items[entry_id.index];
    const then_block = &func.blocks.items[then_id.index];
    const else_block = &func.blocks.items[else_id.index];
    entry.terminator = .{ .br_if = .{
        .condition = condition,
        .then_block = then_id,
        .else_block = else_id,
    } };
    then_block.terminator = .{ .ret_value = result };
    else_block.terminator = .ret;

    try std.testing.expectEqual(Terminator{ .br_if = .{
        .condition = condition,
        .then_block = BlockId{ .index = 1 },
        .else_block = BlockId{ .index = 2 },
    } }, entry.terminator.?);
    try std.testing.expectEqual(Terminator{ .ret_value = result }, then_block.terminator.?);
}

test "backend ir builder appends scalar block by id" {
    const allocator = std.testing.allocator;
    var func = try Function.create(allocator, "builder_scalar");
    defer func.deinit(allocator);

    const entry = try func.add_block_id(allocator);
    const result = func.alloc_value();
    try func.append_instr(allocator, entry, .{ .const_value = .{ .i32 = 1 } });
    try func.append_instr(allocator, entry, .{ .local_set = result });
    try func.set_terminator(entry, .{ .ret_value = result });

    const block = try func.get_block(entry);
    try std.testing.expectEqual(@as(usize, 2), block.instrs.items.len);
    try std.testing.expectEqual(Instr{ .local_set = result }, block.instrs.items[1]);
    try std.testing.expectEqual(Terminator{ .ret_value = result }, block.terminator.?);
}

test "backend ir builder rejects missing block id" {
    const allocator = std.testing.allocator;
    var func = try Function.create(allocator, "builder_missing");
    defer func.deinit(allocator);

    const missing = BlockId{ .index = 99 };
    try std.testing.expectError(error.InvalidBlockId, func.append_instr(allocator, missing, .{ .const_i32 = 1 }));
    try std.testing.expectError(error.InvalidBlockId, func.set_terminator(missing, .ret));
    try std.testing.expectError(error.InvalidBlockId, func.get_block(missing));
}

test "backend ir emits straight line scalar wat" {
    const allocator = std.testing.allocator;
    var func = try Function.create(allocator, "scalar_wat");
    defer func.deinit(allocator);

    const block_id = try func.add_block_id(allocator);
    try func.append_instr(allocator, block_id, .{ .const_value = .{ .i32 = 1 } });
    try func.append_instr(allocator, block_id, .{ .const_value = .{ .i32 = 2 } });
    try func.append_instr(allocator, block_id, .{ .numeric = .{ .ty = .i32, .op = .add } });
    try func.append_instr(allocator, block_id, .{ .const_value = .{ .i32 = 3 } });
    try func.append_instr(allocator, block_id, .{ .compare = .{ .ty = .i32, .op = .eq } });
    try func.set_terminator(block_id, .ret);

    const wat = try emit_function_wat(allocator, &func);
    defer allocator.free(wat);

    try std.testing.expectEqualStrings(
        \\  (func $scalar_wat
        \\    i32.const 1
        \\    i32.const 2
        \\    i32.add
        \\    i32.const 3
        \\    i32.eq
        \\    return
        \\  )
        \\
    , wat);
}

test "backend ir emits structured if wat for two return blocks" {
    const allocator = std.testing.allocator;
    var func = try Function.create(allocator, "branch_wat");
    defer func.deinit(allocator);

    const entry = try func.add_block_id(allocator);
    const then_block = try func.add_block_id(allocator);
    const else_block = try func.add_block_id(allocator);
    const condition = func.alloc_value();
    const result = func.alloc_value();

    try func.append_instr(allocator, entry, .{ .local_get = condition });
    try func.set_terminator(entry, .{ .br_if = .{
        .condition = condition,
        .then_block = then_block,
        .else_block = else_block,
    } });
    try func.append_instr(allocator, then_block, .{ .const_value = .{ .i32 = 1 } });
    try func.set_terminator(then_block, .ret);
    try func.append_instr(allocator, else_block, .{ .local_set = result });
    try func.set_terminator(else_block, .{ .ret_value = result });

    const wat = try emit_function_wat(allocator, &func);
    defer allocator.free(wat);

    try std.testing.expectEqualStrings(
        \\  (func $branch_wat
        \\    local.get $v0
        \\    if
        \\      i32.const 1
        \\      return
        \\    else
        \\      local.set $v1
        \\      local.get $v1
        \\      return
        \\    end
        \\  )
        \\
    , wat);
}

test "backend ir folds empty branch-only block" {
    const allocator = std.testing.allocator;
    var func = try Function.create(allocator, "cfg");
    defer func.deinit(allocator);

    const entry_id = (try func.add_block(allocator)).id;
    const middle_id = (try func.add_block(allocator)).id;
    const exit_id = (try func.add_block(allocator)).id;

    func.blocks.items[entry_id.index].terminator = .{ .br = middle_id };
    func.blocks.items[middle_id.index].terminator = .{ .br = exit_id };
    func.blocks.items[exit_id.index].terminator = .ret;

    try func.fold_empty_branch_blocks(allocator);

    try std.testing.expectEqual(@as(usize, 2), func.blocks.items.len);
    try std.testing.expectEqual(BlockId{ .index = 2 }, func.blocks.items[0].terminator.?.br);
}

test "backend ir keeps non-empty branch block" {
    const allocator = std.testing.allocator;
    var func = try Function.create(allocator, "cfg_keep");
    defer func.deinit(allocator);

    const entry_id = (try func.add_block(allocator)).id;
    const middle_id = (try func.add_block(allocator)).id;
    const exit_id = (try func.add_block(allocator)).id;

    try func.blocks.items[middle_id.index].instrs.append(allocator, .{ .const_i32 = 1 });
    func.blocks.items[entry_id.index].terminator = .{ .br = middle_id };
    func.blocks.items[middle_id.index].terminator = .{ .br = exit_id };
    func.blocks.items[exit_id.index].terminator = .ret;

    try func.fold_empty_branch_blocks(allocator);

    try std.testing.expectEqual(@as(usize, 3), func.blocks.items.len);
    try std.testing.expectEqual(BlockId{ .index = 1 }, func.blocks.items[0].terminator.?.br);
}

test "backend ir folds redundant local_get local_set pair" {
    const allocator = std.testing.allocator;
    var func = try Function.create(allocator, "copy_fold");
    defer func.deinit(allocator);

    const block = try func.add_block(allocator);
    const v0 = func.alloc_value();
    try block.instrs.append(allocator, .{ .local_get = v0 });
    try block.instrs.append(allocator, .{ .local_set = v0 });
    block.terminator = .ret;

    func.fold_redundant_local_copies();

    try std.testing.expectEqual(@as(usize, 0), block.instrs.items.len);
}

test "backend ir folds constant i32 numeric op" {
    const allocator = std.testing.allocator;
    var func = try Function.create(allocator, "const_fold");
    defer func.deinit(allocator);

    const block = try func.add_block(allocator);
    try block.instrs.append(allocator, .{ .const_value = .{ .i32 = 1 } });
    try block.instrs.append(allocator, .{ .const_value = .{ .i32 = 2 } });
    try block.instrs.append(allocator, .{ .numeric = .{ .ty = .i32, .op = .add } });
    block.terminator = .ret;

    func.fold_constant_numeric_ops();

    try std.testing.expectEqual(@as(usize, 1), block.instrs.items.len);
    try std.testing.expectEqual(Instr{ .const_value = .{ .i32 = 3 } }, block.instrs.items[0]);
}

test "backend ir inlines trivial const callee call" {
    const allocator = std.testing.allocator;
    var module = Module{};
    defer module.deinit(allocator);

    var callee = try Function.create(allocator, "callee");
    {
        const block = try callee.add_block(allocator);
        try block.instrs.append(allocator, .{ .const_i32 = 42 });
        block.terminator = .ret;
    }
    try module.add_function(allocator, callee);

    var caller = try Function.create(allocator, "caller");
    {
        const block = try caller.add_block(allocator);
        try block.instrs.append(allocator, .{ .call = "callee" });
        block.terminator = .ret;
    }
    try module.add_function(allocator, caller);

    try module.inline_trivial_const_calls(allocator);

    try std.testing.expectEqual(@as(usize, 1), module.functions.items[1].blocks.items[0].instrs.items.len);
    try std.testing.expectEqual(Instr{ .const_i32 = 42 }, module.functions.items[1].blocks.items[0].instrs.items[0]);
}
