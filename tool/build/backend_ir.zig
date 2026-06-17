const std = @import("std");

pub const ValueId = struct {
    index: usize,
};

pub const BlockId = struct {
    index: usize,
};

pub const Instr = union(enum) {
    const_i32: i32,
    local_get: ValueId,
    local_set: ValueId,
    call: []const u8,
};

pub const Terminator = union(enum) {
    ret,
    br: BlockId,
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
    next_value_id: usize = 0,

    pub fn deinit(self: *Function, allocator: std.mem.Allocator) void {
        for (self.blocks.items) |*block| block.deinit(allocator);
        self.blocks.deinit(allocator);
    }

    pub fn create(allocator: std.mem.Allocator, name: []const u8) !Function {
        _ = allocator;
        return .{ .name = name };
    }

    pub fn allocValue(self: *Function) ValueId {
        defer self.next_value_id += 1;
        return .{ .index = self.next_value_id };
    }

    pub fn addBlock(self: *Function, allocator: std.mem.Allocator) !*Block {
        try self.blocks.append(allocator, .{
            .id = .{ .index = self.blocks.items.len },
        });
        return &self.blocks.items[self.blocks.items.len - 1];
    }

    pub fn foldEmptyBranchBlocks(self: *Function, allocator: std.mem.Allocator) !void {
        if (self.blocks.items.len < 3) return;

        for (self.blocks.items) |*block| {
            if (block.terminator) |term| {
                switch (term) {
                    .br => |target| {
                        block.terminator = .{ .br = self.resolveBranchTarget(target) };
                    },
                    else => {},
                }
            }
        }

        var i = self.blocks.items.len;
        while (i > 0) {
            i -= 1;
            const block = self.blocks.items[i];
            if (!isFoldableEmptyBranchBlock(block)) continue;
            if (i == 0) continue;
            var removed = self.blocks.orderedRemove(i);
            removed.deinit(allocator);
        }
    }

    fn resolveBranchTarget(self: *const Function, start: BlockId) BlockId {
        var current = start;
        while (true) {
            const block = self.findBlock(current) orelse return current;
            if (!isFoldableEmptyBranchBlock(block.*)) return current;
            current = block.terminator.?.br;
        }
    }

    fn findBlock(self: *const Function, id: BlockId) ?*const Block {
        for (self.blocks.items) |*block| {
            if (block.id.index == id.index) return block;
        }
        return null;
    }

    pub fn foldRedundantLocalCopies(self: *Function) void {
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
};

pub const Module = struct {
    functions: std.ArrayList(Function) = .empty,

    pub fn deinit(self: *Module, allocator: std.mem.Allocator) void {
        for (self.functions.items) |*func| func.deinit(allocator);
        self.functions.deinit(allocator);
    }

    pub fn addFunction(self: *Module, allocator: std.mem.Allocator, func: Function) !void {
        try self.functions.append(allocator, func);
    }

    pub fn inlineTrivialConstCalls(self: *Module, allocator: std.mem.Allocator) !void {
        _ = allocator;
        for (self.functions.items) |*caller| {
            for (caller.blocks.items) |*block| {
                var i: usize = 0;
                while (i < block.instrs.items.len) : (i += 1) {
                    const instr = block.instrs.items[i];
                    if (instr != .call) continue;
                    const callee_name = instr.call;
                    if (self.findFunction(callee_name)) |callee| {
                        if (trivialConstReturn(callee)) |value| {
                            block.instrs.items[i] = .{ .const_i32 = value };
                        }
                    }
                }
            }
        }
    }

    fn findFunction(self: *const Module, name: []const u8) ?*Function {
        for (self.functions.items) |*func| {
            if (std.mem.eql(u8, func.name, name)) return func;
        }
        return null;
    }
};

fn trivialConstReturn(func: *const Function) ?i32 {
    if (func.blocks.items.len != 1) return null;
    const block = func.blocks.items[0];
    if (block.instrs.items.len != 1) return null;
    const terminator = block.terminator orelse return null;
    if (terminator != .ret) return null;
    const instr = block.instrs.items[0];
    if (instr != .const_i32) return null;
    return instr.const_i32;
}

fn isFoldableEmptyBranchBlock(block: Block) bool {
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

    const block = try func.addBlock(allocator);
    const v0 = func.allocValue();
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

    const a = func.allocValue();
    const b = func.allocValue();
    try std.testing.expect(a.index != b.index);
}

test "backend ir folds empty branch-only block" {
    const allocator = std.testing.allocator;
    var func = try Function.create(allocator, "cfg");
    defer func.deinit(allocator);

    const entry = try func.addBlock(allocator);
    const middle = try func.addBlock(allocator);
    const exit = try func.addBlock(allocator);

    entry.terminator = .{ .br = middle.id };
    middle.terminator = .{ .br = exit.id };
    exit.terminator = .ret;

    try func.foldEmptyBranchBlocks(allocator);

    try std.testing.expectEqual(@as(usize, 2), func.blocks.items.len);
    try std.testing.expectEqual(BlockId{ .index = 2 }, func.blocks.items[0].terminator.?.br);
}

test "backend ir keeps non-empty branch block" {
    const allocator = std.testing.allocator;
    var func = try Function.create(allocator, "cfg_keep");
    defer func.deinit(allocator);

    const entry = try func.addBlock(allocator);
    const middle = try func.addBlock(allocator);
    const exit = try func.addBlock(allocator);

    try middle.instrs.append(allocator, .{ .const_i32 = 1 });
    entry.terminator = .{ .br = middle.id };
    middle.terminator = .{ .br = exit.id };
    exit.terminator = .ret;

    try func.foldEmptyBranchBlocks(allocator);

    try std.testing.expectEqual(@as(usize, 3), func.blocks.items.len);
    try std.testing.expectEqual(BlockId{ .index = 1 }, func.blocks.items[0].terminator.?.br);
}

test "backend ir folds redundant local_get local_set pair" {
    const allocator = std.testing.allocator;
    var func = try Function.create(allocator, "copy_fold");
    defer func.deinit(allocator);

    const block = try func.addBlock(allocator);
    const v0 = func.allocValue();
    try block.instrs.append(allocator, .{ .local_get = v0 });
    try block.instrs.append(allocator, .{ .local_set = v0 });
    block.terminator = .ret;

    func.foldRedundantLocalCopies();

    try std.testing.expectEqual(@as(usize, 0), block.instrs.items.len);
}

test "backend ir inlines trivial const callee call" {
    const allocator = std.testing.allocator;
    var module = Module{};
    defer module.deinit(allocator);

    var callee = try Function.create(allocator, "callee");
    {
        const block = try callee.addBlock(allocator);
        try block.instrs.append(allocator, .{ .const_i32 = 42 });
        block.terminator = .ret;
    }
    try module.addFunction(allocator, callee);

    var caller = try Function.create(allocator, "caller");
    {
        const block = try caller.addBlock(allocator);
        try block.instrs.append(allocator, .{ .call = "callee" });
        block.terminator = .ret;
    }
    try module.addFunction(allocator, caller);

    try module.inlineTrivialConstCalls(allocator);

    try std.testing.expectEqual(@as(usize, 1), module.functions.items[1].blocks.items[0].instrs.items.len);
    try std.testing.expectEqual(Instr{ .const_i32 = 42 }, module.functions.items[1].blocks.items[0].instrs.items[0]);
}
