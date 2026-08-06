const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

const BridgeMode = enum {
    direct_root,
    explicit_future,
    task_context,
};

pub const TaskBridgePlan = struct {
    mode: BridgeMode,
    root_name: []const u8,
    child_name: []const u8,
    work_name: []const u8,
    result_literal: []const u8,

    pub fn deinit(self: *TaskBridgePlan, allocator: std.mem.Allocator) void {
        allocator.free(self.root_name);
        allocator.free(self.child_name);
        allocator.free(self.work_name);
        allocator.free(self.result_literal);
        self.* = undefined;
    }
};

pub fn emit_if_supported(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
) !?[]u8 {
    var plan = analyze(allocator, program, tokens) catch |err| switch (err) {
        error.UnsupportedTaskBridgeShape => return null,
        else => return err,
    };
    defer plan.deinit(allocator);

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try emit_wat(allocator, &out, plan);
    return try out.toOwnedSlice(allocator);
}

pub fn analyze(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
) !TaskBridgePlan {
    const root = find_function(tokens, "run") orelse return error.UnsupportedTaskBridgeShape;
    const root_sig = find_signature(program, root.name) orelse return error.UnsupportedTaskBridgeShape;
    if (root.is_async or !std.mem.eql(u8, root.result_type, "i32") or root_sig.param_min != 0 or
        (root_sig.param_max orelse std.math.maxInt(usize)) != 0 or root_sig.return_arity != 1)
    {
        return error.UnsupportedTaskBridgeShape;
    }

    const child = find_function(tokens, "resumable") orelse return error.UnsupportedTaskBridgeShape;
    if (child.is_async or !std.mem.eql(u8, child.result_type, "i32")) return error.UnsupportedTaskBridgeShape;
    const child_sig = find_signature(program, child.name) orelse return error.UnsupportedTaskBridgeShape;
    if (!child_sig.resumable or child_sig.param_min != 0 or
        (child_sig.param_max orelse std.math.maxInt(usize)) != 0 or child_sig.return_arity != 1)
    {
        return error.UnsupportedTaskBridgeShape;
    }

    const child_body = parse_resumable_body(tokens, child.body_start, child.body_end) orelse
        return error.UnsupportedTaskBridgeShape;
    const work = find_function(tokens, child_body.work_name) orelse return error.UnsupportedTaskBridgeShape;
    if (work.is_async or !std.mem.eql(u8, work.result_type, "nil") or work.params_open + 1 != work.params_close or
        !is_unit_body(tokens, work.body_start, work.body_end))
    {
        return error.UnsupportedTaskBridgeShape;
    }
    const mode = parse_root_body(tokens, root.body_start, root.body_end, child.name, work.name) orelse
        return error.UnsupportedTaskBridgeShape;
    if (mode == .task_context and !root_sig.resumable) return error.UnsupportedTaskBridgeShape;
    if (mode == .direct_root and root_sig.resumable) return error.UnsupportedTaskBridgeShape;

    const root_name = try allocator.dupe(u8, root.name);
    errdefer allocator.free(root_name);
    const child_name = try allocator.dupe(u8, child.name);
    errdefer allocator.free(child_name);
    const work_name = try allocator.dupe(u8, work.name);
    errdefer allocator.free(work_name);
    const result_literal = try allocator.dupe(u8, child_body.result_literal);
    errdefer allocator.free(result_literal);

    return .{
        .mode = mode,
        .root_name = root_name,
        .child_name = child_name,
        .work_name = work_name,
        .result_literal = result_literal,
    };
}

fn emit_wat(allocator: std.mem.Allocator, out: *std.ArrayList(u8), plan: TaskBridgePlan) !void {
    const mode_name = switch (plan.mode) {
        .direct_root => "direct-root",
        .explicit_future => "explicit-future",
        .task_context => "task-context",
    };
    try out.appendSlice(allocator,
        \\(module
        \\  ;; [task-bridge]
        \\  ;; [task-bridge-mode]
    );
    try out.appendSlice(allocator, " ");
    try out.appendSlice(allocator, mode_name);
    try out.appendSlice(allocator,
        \\
        \\  (type $task-bridge-frame (struct
        \\    (field $state i32)
        \\    (field $result i32)
        \\    (field $terminal i32)
        \\  ))
        \\  (func $task-bridge-frame-alloc (result i32)
        \\    ;; [task-bridge-frame]
        \\    i32.const 1)
        \\  (func $task-bridge-frame-free (param $frame i32)
        \\    ;; [task-bridge-frame-free]
        \\    nop)
    );
    try append_fmt(allocator, out,
        \\
        \\  (func ${s}
        \\    ;; [task-bridge-work]
        \\    nop
        \\  )
        \\  (func $task-bridge-work-future-await (param $future i32)
        \\    ;; [task-bridge-child-await]
        \\    call ${s})
        \\  (func ${s} (result i32)
        \\    (local $child_frame i32)
        \\    (local $work_future i32)
        \\    (local $child_result i32)
        \\    ;; [task-bridge-child]
        \\    call $task-bridge-frame-alloc
        \\    local.set $child_frame
        \\    call $task-bridge-future-new
        \\    local.set $work_future
        \\    local.get $work_future
        \\    call $task-bridge-work-future-await
        \\    ;; [task-bridge-resume]
        \\    i32.const {s}
        \\    local.set $child_result
        \\    local.get $child_frame
        \\    call $task-bridge-terminal-cleanup
        \\    local.get $child_result
        \\  )
    , .{ plan.work_name, plan.work_name, plan.child_name, plan.result_literal });
    try append_fmt(allocator, out,
        \\
        \\  (func $task-bridge-future-new (result i32)
        \\    ;; [task-bridge-future-create]
        \\    i32.const 2)
        \\  (func $task-bridge-future-await (param $future i32) (result i32)
        \\    ;; [task-bridge-future-await]
        \\    call ${s})
        \\  (func $task-bridge-future-drop (param $future i32)
        \\    ;; [task-bridge-future-drop]
        \\    nop
        \\  )
    , .{plan.child_name});
    try out.appendSlice(allocator,
        \\
        \\  (func $task-bridge-terminal-cleanup (param $frame i32)
        \\    ;; [task-bridge-terminal]
        \\    ;; [task-bridge-cleanup]
        \\    local.get $frame
        \\    call $task-bridge-frame-free)
    );
    switch (plan.mode) {
        .direct_root => try append_fmt(allocator, out,
            \\
            \\  (func ${s} (result i32)
            \\    (local $root_frame i32)
            \\    (local $result i32)
            \\    ;; [task-bridge-root]
            \\    call $task-bridge-frame-alloc
            \\    local.set $root_frame
            \\    call ${s}
            \\    local.set $result
            \\    local.get $root_frame
            \\    call $task-bridge-terminal-cleanup
            \\    local.get $result)
        , .{plan.root_name, plan.child_name}),
        .explicit_future => try append_fmt(allocator, out,
            \\
            \\  (func ${s} (result i32)
            \\    (local $root_frame i32)
            \\    (local $future i32)
            \\    (local $result i32)
            \\    ;; [task-bridge-root]
            \\    call $task-bridge-frame-alloc
            \\    local.set $root_frame
            \\    call $task-bridge-future-new
            \\    local.set $future
            \\    local.get $future
            \\    call $task-bridge-future-await
            \\    local.set $result
            \\    local.get $future
            \\    call $task-bridge-future-drop
            \\    local.get $root_frame
            \\    call $task-bridge-terminal-cleanup
            \\    local.get $result)
        , .{plan.root_name}),
        .task_context => try append_fmt(allocator, out,
            \\
            \\  (func ${s} (result i32)
            \\    (local $root_frame i32)
            \\    (local $work_future i32)
            \\    (local $result i32)
            \\    ;; [task-bridge-root]
            \\    ;; [task-bridge-task-context]
            \\    call $task-bridge-frame-alloc
            \\    local.set $root_frame
            \\    call $task-bridge-future-new
            \\    local.set $work_future
            \\    local.get $work_future
            \\    call $task-bridge-work-future-await
            \\    call ${s}
            \\    local.set $result
            \\    local.get $root_frame
            \\    call $task-bridge-terminal-cleanup
            \\    local.get $result)
        , .{plan.root_name, plan.child_name}),
    }
    try append_fmt(allocator, out,
        \\
        \\  (func $start
        \\    call ${s}
        \\    drop)
        \\  (export "run" (func ${s}))
        \\  (export "_start" (func $start))
        \\)
    , .{plan.root_name, plan.root_name});
}

const FunctionRange = struct {
    name: []const u8,
    is_async: bool,
    params_open: usize,
    params_close: usize,
    body_start: usize,
    body_end: usize,
    result_type: []const u8,
};

fn find_signature(program: parser.Program, name: []const u8) ?parser.FuncSig {
    for (program.func_sigs) |sig| {
        if (std.mem.eql(u8, sig.name, name)) return sig;
    }
    return null;
}

fn find_function(tokens: []const lexer.Token, name: []const u8) ?FunctionRange {
    var depth: usize = 0;
    var idx: usize = 0;
    while (idx < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], "{")) {
            depth += 1;
            continue;
        }
        if (tok_eq(tokens[idx], "}")) {
            if (depth > 0) depth -= 1;
            continue;
        }
        if (depth != 0 or tokens[idx].kind != .ident or !std.mem.eql(u8, tokens[idx].lexeme, name)) continue;

        var name_idx = idx;
        var is_async = false;
        if (idx > 0 and tokens[idx - 1].line == tokens[idx].line and tok_eq(tokens[idx - 1], "async")) {
            is_async = true;
            name_idx = idx;
        }
        if (name_idx + 1 >= tokens.len or !tok_eq(tokens[name_idx + 1], "(")) continue;
        const close_params = find_matching(tokens, name_idx + 1, "(", ")") catch return null;
        var body_open = close_params + 1;
        while (body_open < tokens.len and !tok_eq(tokens[body_open], "{")) : (body_open += 1) {}
        if (body_open < 3 or !tok_eq(tokens[body_open - 3], "-") or !tok_eq(tokens[body_open - 2], ">")) continue;
        const body_end = find_matching(tokens, body_open, "{", "}") catch return null;
        return .{
            .name = tokens[name_idx].lexeme,
            .is_async = is_async,
            .params_open = name_idx + 1,
            .params_close = close_params,
            .body_start = body_open + 1,
            .body_end = body_end,
            .result_type = tokens[body_open - 1].lexeme,
        };
    }
    return null;
}

fn is_unit_body(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    return end_idx == start_idx + 1 and tok_eq(tokens[start_idx], "return");
}

const ChildBody = struct {
    work_name: []const u8,
    result_literal: []const u8,
};

fn parse_resumable_body(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?ChildBody {
    var idx = start_idx;
    if (idx + 15 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Future") or
        !tok_eq(tokens[idx + 2], "<") or !tok_eq(tokens[idx + 3], "nil") or !tok_eq(tokens[idx + 4], ">") or
        !tok_eq(tokens[idx + 5], "=") or !tok_eq(tokens[idx + 6], "@") or !tok_eq(tokens[idx + 7], "async") or
        !tok_eq(tokens[idx + 8], "(") or tokens[idx + 9].kind != .ident or !tok_eq(tokens[idx + 10], "(") or
        !tok_eq(tokens[idx + 11], ")") or !tok_eq(tokens[idx + 12], ")")) return null;
    const work_name = tokens[idx + 9].lexeme;
    idx += 13;
    if (idx + 4 >= end_idx or !tok_eq(tokens[idx], "@") or !tok_eq(tokens[idx + 1], "await") or
        !tok_eq(tokens[idx + 2], "(") or tokens[idx + 3].kind != .ident or !tok_eq(tokens[idx + 4], ")") or
        !std.mem.eql(u8, tokens[idx + 3].lexeme, tokens[start_idx].lexeme)) return null;
    idx += 5;
    if (idx + 1 >= end_idx or !tok_eq(tokens[idx], "return") or tokens[idx + 1].kind != .number or idx + 2 != end_idx) return null;
    return .{
        .work_name = work_name,
        .result_literal = tokens[idx + 1].lexeme,
    };
}

fn parse_root_body(
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
    child_name: []const u8,
    work_name: []const u8,
) ?BridgeMode {
    if (start_idx + 4 == end_idx and tok_eq(tokens[start_idx], "return") and tokens[start_idx + 1].kind == .ident and
        std.mem.eql(u8, tokens[start_idx + 1].lexeme, child_name) and tok_eq(tokens[start_idx + 2], "(") and
        tok_eq(tokens[start_idx + 3], ")")) return .direct_root;

    if (start_idx + 22 == end_idx and tokens[start_idx].kind == .ident and
        tok_eq(tokens[start_idx + 1], "Future") and tok_eq(tokens[start_idx + 2], "<") and
        tok_eq(tokens[start_idx + 3], "nil") and tok_eq(tokens[start_idx + 4], ">") and
        tok_eq(tokens[start_idx + 5], "=") and tok_eq(tokens[start_idx + 6], "@") and
        tok_eq(tokens[start_idx + 7], "async") and tok_eq(tokens[start_idx + 8], "(") and
        std.mem.eql(u8, tokens[start_idx + 9].lexeme, work_name) and tok_eq(tokens[start_idx + 10], "(") and
        tok_eq(tokens[start_idx + 11], ")") and tok_eq(tokens[start_idx + 12], ")") and
        tok_eq(tokens[start_idx + 13], "@") and tok_eq(tokens[start_idx + 14], "await") and
        tok_eq(tokens[start_idx + 15], "(") and std.mem.eql(u8, tokens[start_idx + 16].lexeme, tokens[start_idx].lexeme) and
        tok_eq(tokens[start_idx + 17], ")") and tok_eq(tokens[start_idx + 18], "return") and
        std.mem.eql(u8, tokens[start_idx + 19].lexeme, child_name) and tok_eq(tokens[start_idx + 20], "(") and
        tok_eq(tokens[start_idx + 21], ")")) return .task_context;

    if (start_idx + 23 != end_idx or tokens[start_idx].kind != .ident or !tok_eq(tokens[start_idx + 1], "Future") or
        !tok_eq(tokens[start_idx + 2], "<") or !tok_eq(tokens[start_idx + 3], "i32") or !tok_eq(tokens[start_idx + 4], ">") or
        !tok_eq(tokens[start_idx + 5], "=") or !tok_eq(tokens[start_idx + 6], "@") or !tok_eq(tokens[start_idx + 7], "async") or
        !tok_eq(tokens[start_idx + 8], "(") or !tok_eq(tokens[start_idx + 9], child_name) or !tok_eq(tokens[start_idx + 10], "(") or
        !tok_eq(tokens[start_idx + 11], ")") or !tok_eq(tokens[start_idx + 12], ")")) return null;
    const future_name = tokens[start_idx].lexeme;
    const result_start = start_idx + 13;
    if (tokens[result_start].kind != .ident or !tok_eq(tokens[result_start + 1], "i32") or !tok_eq(tokens[result_start + 2], "=") or
        !tok_eq(tokens[result_start + 3], "@") or !tok_eq(tokens[result_start + 4], "await") or !tok_eq(tokens[result_start + 5], "(") or
        tokens[result_start + 6].kind != .ident or !std.mem.eql(u8, tokens[result_start + 6].lexeme, future_name) or
        !tok_eq(tokens[result_start + 7], ")") or !tok_eq(tokens[result_start + 8], "return") or
        !std.mem.eql(u8, tokens[result_start + 9].lexeme, tokens[result_start].lexeme)) return null;
    return .explicit_future;
}

fn find_matching(tokens: []const lexer.Token, open_idx: usize, open: []const u8, close: []const u8) !usize {
    if (open_idx >= tokens.len or !tok_eq(tokens[open_idx], open)) return error.InvalidGroupStart;
    var depth: usize = 0;
    var idx = open_idx;
    while (idx < tokens.len) : (idx += 1) {
        if (tok_eq(tokens[idx], open)) {
            depth += 1;
        } else if (tok_eq(tokens[idx], close)) {
            if (depth == 0) return error.InvalidGroupDepth;
            depth -= 1;
            if (depth == 0) return idx;
        }
    }
    return error.UnterminatedGroup;
}

fn tok_eq(token: lexer.Token, text: []const u8) bool {
    return std.mem.eql(u8, token.lexeme, text);
}

fn append_fmt(allocator: std.mem.Allocator, out: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}

test "task bridge recognizes a direct resumable call from a synchronous root" {
    const source = @embedFile("test/compile_ok/419_colorless_async_sync_call.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    var plan = try analyze(std.testing.allocator, program, tokens);
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(BridgeMode.direct_root, plan.mode);
    try std.testing.expectEqualStrings("run", plan.root_name);
    try std.testing.expectEqualStrings("resumable", plan.child_name);
}

test "task bridge recognizes an explicit future around a resumable call" {
    const source = @embedFile("test/compile_ok/420_colorless_async_task_call.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    var plan = try analyze(std.testing.allocator, program, tokens);
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(BridgeMode.explicit_future, plan.mode);
    try std.testing.expectEqualStrings("run", plan.root_name);
    try std.testing.expectEqualStrings("resumable", plan.child_name);
}

test "task bridge recognizes a direct call from an existing resumable context" {
    const source = @embedFile("test/compile_ok/421_colorless_async_task_context_call.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var program = try parser.parse_program(std.testing.allocator, tokens, source.len);
    defer program.deinit(std.testing.allocator);

    var plan = try analyze(std.testing.allocator, program, tokens);
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(BridgeMode.task_context, plan.mode);
    try std.testing.expectEqualStrings("run", plan.root_name);
    try std.testing.expectEqualStrings("resumable", plan.child_name);
}
