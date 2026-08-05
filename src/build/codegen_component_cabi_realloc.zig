const std = @import("std");

pub const Error = error{
    MissingMemoryExport,
    MissingReallocType,
};

pub fn rewrite(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    if (std.mem.indexOf(u8, input, "(type $cabi-realloc") == null) return error.MissingReallocType;

    var output = try allocator.dupe(u8, input);
    errdefer allocator.free(output);

    if (std.mem.indexOf(u8, output, "[cabi-budget-runtime]") != null) {
        output = try replace_all(allocator, output, "[cabi-budget-runtime]", budget_runtime);
    } else {
        if (std.mem.indexOf(u8, output, "(func $async-byte-budget-reserve") == null) {
            const next = try insert_after_memory(allocator, output, budget_helpers);
            allocator.free(output);
            output = next;
        }
        if (std.mem.indexOf(u8, output, "(global $heap-next") == null) {
            const next = try insert_after_memory(allocator, output, heap_global);
            allocator.free(output);
            output = next;
        }
        const next = try replace_realloc(allocator, output);
        allocator.free(output);
        output = next;
    }
    return output;
}

fn insert_after_memory(allocator: std.mem.Allocator, input: []const u8, insertion: []const u8) ![]u8 {
    const memory_start = std.mem.indexOf(u8, input, "(memory (export \"memory\")") orelse return error.MissingMemoryExport;
    const line_end = std.mem.indexOfPos(u8, input, memory_start, "\n") orelse return error.MissingMemoryExport;
    return std.fmt.allocPrint(allocator, "{s}{s}\n{s}", .{ input[0 .. line_end + 1], insertion, input[line_end + 1 ..] });
}

fn replace_realloc(allocator: std.mem.Allocator, input: []u8) ![]u8 {
    const start = std.mem.indexOf(u8, input, "  (func (export \"cabi_realloc\")") orelse return allocator.dupe(u8, input);
    const end = find_form_end(input, start) orelse return allocator.dupe(u8, input);
    return std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ input[0..start], realloc_func, input[end..] });
}

fn find_form_end(input: []const u8, start: usize) ?usize {
    var depth: usize = 0;
    var index = start;
    var in_string = false;
    var escaped = false;
    var line_comment = false;
    var block_comment_depth: usize = 0;

    while (index < input.len) {
        const byte = input[index];
        if (line_comment) {
            if (byte == '\n') line_comment = false;
            index += 1;
            continue;
        }
        if (block_comment_depth != 0) {
            if (byte == '(' and index + 1 < input.len and input[index + 1] == ';') {
                block_comment_depth += 1;
                index += 2;
                continue;
            }
            if (byte == ';' and index + 1 < input.len and input[index + 1] == ')') {
                block_comment_depth -= 1;
                index += 2;
                continue;
            }
            index += 1;
            continue;
        }
        if (in_string) {
            if (escaped) {
                escaped = false;
            } else if (byte == '\\') {
                escaped = true;
            } else if (byte == '"') {
                in_string = false;
            }
            index += 1;
            continue;
        }
        if (byte == '"') {
            in_string = true;
            index += 1;
            continue;
        }
        if (byte == ';' and index + 1 < input.len and input[index + 1] == ';') {
            line_comment = true;
            index += 2;
            continue;
        }
        if (byte == '(' and index + 1 < input.len and input[index + 1] == ';') {
            block_comment_depth = 1;
            index += 2;
            continue;
        }
        if (byte == '(') {
            depth += 1;
        } else if (byte == ')') {
            if (depth == 0) return null;
            depth -= 1;
            if (depth == 0) return index + 1;
        }
        index += 1;
    }
    return null;
}

fn replace_all(allocator: std.mem.Allocator, input: []u8, needle: []const u8, replacement: []const u8) ![]u8 {
    var output = std.ArrayList(u8).empty;
    errdefer output.deinit(allocator);
    var remainder = input;
    while (std.mem.indexOf(u8, remainder, needle)) |index| {
        try output.appendSlice(allocator, remainder[0..index]);
        try output.appendSlice(allocator, replacement);
        remainder = remainder[index + needle.len ..];
    }
    try output.appendSlice(allocator, remainder);
    allocator.free(input);
    return output.toOwnedSlice(allocator);
}

const heap_global =
    \\  (global $heap-next (mut i32) (i32.const 65536))
;

const budget_helpers =
    \\  ;; [async-byte-budget-limit] -1
    \\  (global $async-byte-budget-used (mut i64) (i64.const 0))
    \\  (global $async-byte-budget-limit (mut i64) (i64.const -1))
    \\  (func $async-byte-budget-limit (export "[async-config]byte-budget-limit") (param $limit i64) (result i32)
    \\    local.get $limit
    \\    i64.const -1
    \\    i64.eq
    \\    if (result i32)
    \\      local.get $limit
    \\      global.set $async-byte-budget-limit
    \\      i32.const 1
    \\    else
    \\      local.get $limit
    \\      i64.const 0
    \\      i64.lt_s
    \\      if (result i32)
    \\        i32.const 0
    \\      else
    \\        global.get $async-byte-budget-used
    \\        local.get $limit
    \\        i64.gt_u
    \\        if (result i32)
    \\          i32.const 0
    \\        else
    \\          local.get $limit
    \\          global.set $async-byte-budget-limit
    \\          i32.const 1
    \\        end
    \\      end
    \\    end
    \\  )
    \\  (func (export "byte-budget-limit") (param $limit i64) (result i32)
    \\    local.get $limit
    \\    call $async-byte-budget-limit)
    \\  (func $async-byte-budget-reserve (param $bytes i64) (result i32)
    \\    (local $next i64)
    \\    global.get $async-byte-budget-used
    \\    local.get $bytes
    \\    i64.add
    \\    local.tee $next
    \\    global.get $async-byte-budget-used
    \\    i64.lt_u
    \\    if (result i32)
    \\      i32.const 0
    \\    else
    \\      global.get $async-byte-budget-limit
    \\      i64.const -1
    \\      i64.eq
    \\      if (result i32)
    \\        i32.const 1
    \\      else
    \\        local.get $next
    \\        global.get $async-byte-budget-limit
    \\        i64.le_u
    \\      end
    \\      if (result i32)
    \\        local.get $next
    \\        global.set $async-byte-budget-used
    \\        i32.const 1
    \\      else
    \\        i32.const 0
    \\      end
    \\    end
    \\  )
    \\  (func $async-byte-budget-release (param $bytes i64)
    \\    global.get $async-byte-budget-used
    \\    local.get $bytes
    \\    i64.lt_u
    \\    if unreachable end
    \\    global.get $async-byte-budget-used
    \\    local.get $bytes
    \\    i64.sub
    \\    global.set $async-byte-budget-used
    \\  )
;

const realloc_func =
    \\  (func (export "cabi_realloc") (type $cabi-realloc) (param $old i32) (param $old-size i32) (param $align i32) (param $size i32) (result i32)
    \\    (local $ptr i32)
    \\    (local $end i32)
    \\    (local $budget-delta i64)
    \\    local.get $size
    \\    local.get $old-size
    \\    i32.gt_u
    \\    if
    \\      local.get $size
    \\      local.get $old-size
    \\      i32.sub
    \\      i64.extend_i32_u
    \\      local.tee $budget-delta
    \\      call $async-byte-budget-reserve
    \\      i32.eqz
    \\      if unreachable end
    \\    else
    \\      local.get $old-size
    \\      local.get $size
    \\      i32.gt_u
    \\      if
    \\        local.get $old-size
    \\        local.get $size
    \\        i32.sub
    \\        i64.extend_i32_u
    \\        call $async-byte-budget-release
    \\      end
    \\    end
    \\    global.get $heap-next
    \\    local.set $ptr
    \\    local.get $ptr
    \\    local.get $size
    \\    i32.add
    \\    local.set $end
    \\    local.get $end
    \\    memory.size
    \\    i32.const 16
    \\    i32.shl
    \\    i32.gt_u
    \\    if
    \\      local.get $end
    \\      i32.const 65535
    \\      i32.add
    \\      i32.const 16
    \\      i32.shr_u
    \\      memory.size
    \\      i32.sub
    \\      memory.grow
    \\      i32.const -1
    \\      i32.eq
    \\      if
    \\        local.get $budget-delta
    \\        call $async-byte-budget-release
    \\        unreachable
    \\      end
    \\    end
    \\    local.get $end
    \\    global.set $heap-next
    \\    local.get $ptr
    \\  )
;

const budget_runtime = budget_helpers ++ heap_global ++ realloc_func;

test "cabi realloc rewrite adds transactional budget owner" {
    const source =
        \\(module
        \\  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
        \\  (memory (export "memory") 1)
        \\  (func (export "cabi_realloc") (type $cabi-realloc) unreachable)
        \\  (func (export "_initialize"))
        \\)
    ;
    const rewritten = try rewrite(std.testing.allocator, source);
    defer std.testing.allocator.free(rewritten);

    try std.testing.expect(std.mem.indexOf(u8, rewritten, "global $async-byte-budget-used") != null);
    try std.testing.expect(std.mem.indexOf(u8, rewritten, "global $heap-next") != null);
    try std.testing.expect(std.mem.indexOf(u8, rewritten, "(func (export \"byte-budget-limit\") (param $limit i64) (result i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, rewritten, "call $async-byte-budget-reserve") != null);
    try std.testing.expect(std.mem.indexOf(u8, rewritten, "call $async-byte-budget-release") != null);
    try std.testing.expect(std.mem.indexOf(u8, rewritten, "memory.grow") != null);
    try std.testing.expect(std.mem.indexOf(u8, rewritten, "cabi_realloc\") (type $cabi-realloc) unreachable") == null);
}

test "cabi realloc rewrite does not duplicate an existing budget owner" {
    const source =
        \\(module
        \\  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
        \\  (memory (export "memory") 1)
        \\  (global $async-byte-budget-used (mut i64) (i64.const 0))
        \\  (global $async-byte-budget-limit (mut i64) (i64.const -1))
        \\  (func $async-byte-budget-reserve (param i64) (result i32) i32.const 1)
        \\  (func $async-byte-budget-release (param i64))
        \\  (global $heap-next (mut i32) (i32.const 65536))
        \\  (func (export "cabi_realloc") (type $cabi-realloc) unreachable)
        \\  (func (export "_initialize"))
        \\)
    ;
    const rewritten = try rewrite(std.testing.allocator, source);
    defer std.testing.allocator.free(rewritten);

    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, rewritten, "global $async-byte-budget-used"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, rewritten, "global $heap-next"));
    try std.testing.expect(std.mem.indexOf(u8, rewritten, "memory.grow") != null);
}

test "cabi realloc rewrite preserves functions after the allocator" {
    const source =
        \\(module
        \\  (type $cabi-realloc (func (param i32 i32 i32 i32) (result i32)))
        \\  (memory (export "memory") 1)
        \\  (func (export "cabi_realloc") (type $cabi-realloc) unreachable)
        \\  (func (export "async_lift") (result i32) i32.const 7)
        \\  (func (export "_initialize"))
        \\)
    ;
    const rewritten = try rewrite(std.testing.allocator, source);
    defer std.testing.allocator.free(rewritten);

    try std.testing.expect(std.mem.indexOf(u8, rewritten, "(func (export \"async_lift\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, rewritten, "i32.const 7") != null);
}
