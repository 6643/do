const std = @import("std");
const lexer = @import("lexer.zig");
const sema_tokens = @import("sema_tokens.zig");

const find_line_end_idx = sema_tokens.find_line_end_idx;
const find_loop_block_open = sema_tokens.find_loop_block_open;
const find_matching = sema_tokens.find_matching;
const mark_error_at = sema_tokens.mark_error_at;
const tok_eq = sema_tokens.tok_eq;

pub const LeaseError = error{
    AlreadyFinalized,
    InvalidState,
    JoinConflict,
    Unfinalized,
    InvalidDeferTransfer,
    InvalidLeaseIndex,
};

pub const LeaseState = enum {
    owned,
    owned_deferred,
    moved,
    finalized,
    maybe,
};

pub const LeaseEvent = union(enum) {
    write: u32,
    transfer: struct { source: u32, target: u32 },
    helper_transfer: u32,
    finalize: u32,
    register_defer: u32,
};

pub const LeaseEnv = struct {
    states: []LeaseState,

    pub fn apply(self: *LeaseEnv, event: LeaseEvent) LeaseError!void {
        return switch (event) {
            .write => |id| self.require_writable(id),
            .transfer => |transfer| self.transfer_owner(transfer.source, transfer.target),
            .helper_transfer => |id| self.consume_for_helper(id),
            .finalize => |id| self.finalize_owner(id),
            .register_defer => |id| self.register_defer(id),
        };
    }

    pub fn join(allocator: std.mem.Allocator, left: LeaseEnv, right: LeaseEnv) !LeaseEnv {
        if (left.states.len != right.states.len) return error.JoinConflict;
        const states = try allocator.alloc(LeaseState, left.states.len);
        errdefer allocator.free(states);
        for (left.states, right.states, 0..) |left_state, right_state, idx| {
            states[idx] = if (left_state == right_state) left_state else .maybe;
        }
        return .{ .states = states };
    }

    pub fn can_exit(self: *const LeaseEnv) LeaseError!void {
        for (self.states) |item_state| {
            switch (item_state) {
                .owned => return error.Unfinalized,
                .maybe => return error.JoinConflict,
                .owned_deferred, .moved, .finalized => {},
            }
        }
    }

    pub fn deinit(self: *LeaseEnv, allocator: std.mem.Allocator) void {
        allocator.free(self.states);
        self.states = &.{};
    }

    fn state(self: *const LeaseEnv, id: u32) LeaseError!LeaseState {
        if (id >= self.states.len) return error.InvalidLeaseIndex;
        return self.states[id];
    }

    fn require_writable(self: *const LeaseEnv, id: u32) LeaseError!void {
        switch (try self.state(id)) {
            .owned, .owned_deferred => {},
            .moved, .finalized => return error.AlreadyFinalized,
            .maybe => return error.InvalidState,
        }
    }

    fn require_owned(self: *const LeaseEnv, id: u32) LeaseError!void {
        switch (try self.state(id)) {
            .owned => {},
            .owned_deferred => return error.InvalidDeferTransfer,
            .moved, .finalized => return error.AlreadyFinalized,
            .maybe => return error.InvalidState,
        }
    }

    fn transfer_owner(self: *LeaseEnv, source: u32, target: u32) LeaseError!void {
        try self.require_owned(source);
        if (target >= self.states.len) return error.InvalidLeaseIndex;
        self.states[source] = .moved;
        self.states[target] = .owned;
    }

    fn consume_for_helper(self: *LeaseEnv, id: u32) LeaseError!void {
        try self.require_owned(id);
        self.states[id] = .moved;
    }

    fn finalize_owner(self: *LeaseEnv, id: u32) LeaseError!void {
        try self.require_owned(id);
        self.states[id] = .finalized;
    }

    fn register_defer(self: *LeaseEnv, id: u32) LeaseError!void {
        try self.require_owned(id);
        self.states[id] = .owned_deferred;
    }
};

pub const HelperTransferFn = *const fn (
    tokens: []const lexer.Token,
    future_idx: usize,
    end_idx: usize,
    writer_idx: usize,
    element_type_start: usize,
    element_type_end: usize,
) bool;

const WriterBinding = struct {
    name: []const u8,
    decl_idx: usize,
    element_type_start: usize,
    element_type_end: usize,
    initially_owned: bool,
};

const Finalization = struct {
    operand_idx: usize,
    close_idx: usize,
};

const WriterCall = struct {
    callee_idx: usize,
    writer_arg_idx: ?usize,
    call_close: usize,
};

const Context = struct {
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    bindings: []const WriterBinding,
    helper_transfer: HelperTransferFn,
};

const BreakCollector = struct {
    items: *std.ArrayList(LeaseEnv),
};

pub fn check_async_writer_body(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    params_start: usize,
    params_end: usize,
    body_start: usize,
    body_end: usize,
    helper_transfer: HelperTransferFn,
) !bool {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const work = arena.allocator();

    var binding_list = std.ArrayList(WriterBinding).empty;
    defer binding_list.deinit(work);
    try collect_bindings(work, tokens, params_start, params_end, body_start, body_end, &binding_list);
    if (binding_list.items.len == 0) return false;

    var states = try work.alloc(LeaseState, binding_list.items.len);
    for (binding_list.items, 0..) |binding, idx| {
        states[idx] = if (binding.initially_owned) .owned else .moved;
    }

    var context = Context{
        .allocator = work,
        .tokens = tokens,
        .bindings = binding_list.items,
        .helper_transfer = helper_transfer,
    };
    const initial = LeaseEnv{ .states = states };
    const result = try analyze_block(&context, body_start, body_end, initial, true, null);
    if (result) |env| {
        try check_exit(&context, env, body_start);
    }
    return true;
}

fn collect_bindings(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    params_start: usize,
    params_end: usize,
    body_start: usize,
    body_end: usize,
    out: *std.ArrayList(WriterBinding),
) !void {
    var i = params_start;
    while (i + 2 < params_end) : (i += 1) {
        if (tokens[i].kind != .ident or !tok_eq(tokens[i + 1], "StreamWriter") or !tok_eq(tokens[i + 2], "<")) continue;
        const close_angle = find_matching(tokens, i + 2, "<", ">") catch continue;
        if (close_angle >= params_end) continue;
        try out.append(allocator, .{
            .name = tokens[i].lexeme,
            .decl_idx = i,
            .element_type_start = i + 3,
            .element_type_end = close_angle,
            .initially_owned = true,
        });
        i = close_angle;
    }

    i = body_start;
    while (i + 2 < body_end) : (i += 1) {
        if (tokens[i].kind != .ident or !tok_eq(tokens[i + 1], "StreamWriter") or !tok_eq(tokens[i + 2], "<")) continue;
        const close_angle = find_matching(tokens, i + 2, "<", ">") catch continue;
        if (close_angle >= body_end) continue;
        try out.append(allocator, .{
            .name = tokens[i].lexeme,
            .decl_idx = i,
            .element_type_start = i + 3,
            .element_type_end = close_angle,
            .initially_owned = line_contains_new_stream(tokens, i, body_end),
        });
        i = close_angle;
    }
}

fn line_contains_new_stream(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    const line_end = @min(find_line_end_idx(tokens, start_idx), end_idx);
    for (tokens[start_idx..line_end]) |token| {
        if (tok_eq(token, "new_stream")) return true;
    }
    return false;
}

fn analyze_block(
    context: *const Context,
    start_idx: usize,
    end_idx: usize,
    input: LeaseEnv,
    is_root: bool,
    breaks: ?*BreakCollector,
) anyerror!?LeaseEnv {
    var env = input;
    var deferred = std.ArrayList(u32).empty;
    defer deferred.deinit(context.allocator);

    var i = start_idx;
    while (i < end_idx) {
        if (tok_eq(context.tokens[i], "if")) {
            const branch = try analyze_if(context, i, end_idx, env, breaks);
            if (branch == null) return null;
            env = branch.?;
            i = branch_after_idx(context.tokens, i, end_idx) orelse return env;
            continue;
        }

        if (tok_eq(context.tokens[i], "loop")) {
            const loop = try analyze_loop(context, i, end_idx, env, breaks);
            if (loop == null) return null;
            env = loop.?;
            i = loop_after_idx(context.tokens, i, end_idx) orelse return env;
            continue;
        }

        if (tok_eq(context.tokens[i], "return")) {
            try check_exit_with_defers(context, &env, deferred.items, i);
            return null;
        }

        if (tok_eq(context.tokens[i], "break")) {
            if (breaks) |collector| {
                try apply_scope_defers(context, &env, deferred.items, i);
                try collector.items.append(context.allocator, try clone_env(context.allocator, env));
            } else {
                try check_exit_with_defers(context, &env, deferred.items, i);
            }
            return null;
        }

        if (tok_eq(context.tokens[i], "continue")) {
            try apply_scope_defers(context, &env, deferred.items, i);
            return null;
        }

        if (tok_eq(context.tokens[i], "defer")) {
            if (parse_deferred_close(context.tokens, i, end_idx)) |finalization| {
                const id = find_binding(context.bindings, context.tokens[finalization.operand_idx].lexeme, finalization.operand_idx) orelse {
                    i = find_line_end_idx(context.tokens, i);
                    continue;
                };
                try apply_event(context, &env, .{ .register_defer = @intCast(id) }, finalization.operand_idx);
                try deferred.append(context.allocator, @intCast(id));
            }
            i = find_line_end_idx(context.tokens, i);
            continue;
        }

        if (is_stream_writer_finalizer(context.tokens, i, end_idx)) |finalization| {
            const id = find_binding(context.bindings, context.tokens[finalization.operand_idx].lexeme, finalization.operand_idx) orelse {
                i = find_line_end_idx(context.tokens, i);
                continue;
            };
            try apply_event(context, &env, .{ .finalize = @intCast(id) }, finalization.operand_idx);
            i = finalization.close_idx + 1;
            continue;
        }

        if (is_stream_writer_transfer(context.tokens, i, end_idx)) |transfer| {
            const source_id = find_binding(context.bindings, context.tokens[transfer.source_idx].lexeme, transfer.source_idx) orelse {
                i = find_line_end_idx(context.tokens, i);
                continue;
            };
            const target_id = find_binding(context.bindings, context.tokens[i].lexeme, i) orelse {
                i = find_line_end_idx(context.tokens, i);
                continue;
            };
            if (!same_type(context.tokens, context.bindings[source_id], transfer.element_type_start, transfer.element_type_end)) {
                return mark_error_at(context.tokens, i + 1, error.StreamWriterTypeMismatch);
            }
            try apply_event(context, &env, .{ .transfer = .{ .source = @intCast(source_id), .target = @intCast(target_id) } }, transfer.source_idx);
            i = find_line_end_idx(context.tokens, i);
            continue;
        }

        if (is_future_binding(context.tokens, i, end_idx, context.bindings)) |call| {
            if (find_binding(context.bindings, context.tokens[call.callee_idx].lexeme, call.callee_idx)) |writer_id| {
                try apply_event(context, &env, .{ .write = @intCast(writer_id) }, call.callee_idx);
            }
            if (call.writer_arg_idx) |writer_arg_idx| {
                if (find_binding(context.bindings, context.tokens[writer_arg_idx].lexeme, writer_arg_idx)) |writer_id| {
                    const binding = context.bindings[writer_id];
                    if (writer_arg_idx != call.callee_idx and context.helper_transfer(
                        context.tokens,
                        i,
                        end_idx,
                        writer_arg_idx,
                        binding.element_type_start,
                        binding.element_type_end,
                    )) {
                        try apply_event(context, &env, .{ .helper_transfer = @intCast(writer_id) }, writer_arg_idx);
                    }
                }
            }
            i = call.call_close + 1;
            continue;
        }

        i = find_line_end_idx(context.tokens, i);
    }

    if (!is_root) try apply_scope_defers(context, &env, deferred.items, start_idx);
    return env;
}

fn analyze_if(
    context: *const Context,
    if_idx: usize,
    end_idx: usize,
    input: LeaseEnv,
    breaks: ?*BreakCollector,
) anyerror!?LeaseEnv {
    const then_open = find_block_open(context.tokens, if_idx + 1, end_idx) orelse return input;
    const then_close = find_matching(context.tokens, then_open, "{", "}") catch return input;
    const then_input = try clone_env(context.allocator, input);
    const then_env = try analyze_block(context, then_open + 1, then_close, then_input, false, breaks);

    var cursor = then_close + 1;
    var else_env: ?LeaseEnv = null;
    if (cursor < end_idx and tok_eq(context.tokens[cursor], "else")) {
        if (cursor + 1 < end_idx and tok_eq(context.tokens[cursor + 1], "if")) {
            const else_input = try clone_env(context.allocator, input);
            else_env = try analyze_if(context, cursor + 1, end_idx, else_input, breaks);
            cursor = branch_after_idx(context.tokens, cursor + 1, end_idx) orelse cursor + 1;
        } else if (cursor + 1 < end_idx and tok_eq(context.tokens[cursor + 1], "{")) {
            const else_close = find_matching(context.tokens, cursor + 1, "{", "}") catch return input;
            const else_input = try clone_env(context.allocator, input);
            else_env = try analyze_block(context, cursor + 2, else_close, else_input, false, breaks);
            cursor = else_close + 1;
        }
    } else {
        else_env = try clone_env(context.allocator, input);
    }

    if (then_env == null) return else_env;
    if (else_env == null) return then_env;
    return try LeaseEnv.join(context.allocator, then_env.?, else_env.?);
}

fn analyze_loop(
    context: *const Context,
    loop_idx: usize,
    end_idx: usize,
    input: LeaseEnv,
    outer_breaks: ?*BreakCollector,
) anyerror!?LeaseEnv {
    _ = end_idx;
    const open = find_loop_block_open(context.tokens, loop_idx) orelse return input;
    const close = find_matching(context.tokens, open, "{", "}") catch return input;
    const body_input = try clone_env(context.allocator, input);
    var break_items = std.ArrayList(LeaseEnv).empty;
    defer break_items.deinit(context.allocator);
    var collector = BreakCollector{ .items = &break_items };
    _ = try analyze_block(context, open + 1, close, body_input, false, &collector);
    if (break_items.items.len == 0) return input;

    var result = try clone_env(context.allocator, input);
    for (break_items.items) |break_env| {
        result = try LeaseEnv.join(context.allocator, result, break_env);
    }
    _ = outer_breaks;
    return result;
}

fn apply_scope_defers(context: *const Context, env: *LeaseEnv, ids: []const u32, source_idx: usize) !void {
    for (ids) |id| {
        if (id >= env.states.len) return mark_error_at(context.tokens, source_idx, error.StreamWriterLeasePathConflict);
        switch (env.states[id]) {
            .owned_deferred => env.states[id] = .finalized,
            .maybe => return mark_error_at(context.tokens, source_idx, error.StreamWriterLeasePathConflict),
            .owned => return mark_error_at(context.tokens, source_idx, error.StreamWriterLeaseDropped),
            .moved, .finalized => return mark_error_at(context.tokens, source_idx, error.StreamWriterDeferredTransfer),
        }
    }
}

fn check_exit_with_defers(context: *const Context, env: *LeaseEnv, ids: []const u32, source_idx: usize) !void {
    try apply_scope_defers(context, env, ids, source_idx);
    try check_exit(context, env.*, source_idx);
}

fn check_exit(context: *const Context, env: LeaseEnv, source_idx: usize) !void {
    for (env.states, 0..) |state, idx| {
        switch (state) {
            .owned => return mark_error_at(context.tokens, context.bindings[idx].decl_idx, error.StreamWriterLeaseDropped),
            .maybe => return mark_error_at(context.tokens, context.bindings[idx].decl_idx, error.StreamWriterLeasePathConflict),
            .owned_deferred, .moved, .finalized => {},
        }
    }
    _ = source_idx;
}

fn apply_event(context: *const Context, env: *LeaseEnv, event: LeaseEvent, source_idx: usize) !void {
    env.apply(event) catch |err| return mark_error_at(context.tokens, source_idx, map_lease_error(err));
}

fn map_lease_error(err: LeaseError) anyerror {
    return switch (err) {
        error.AlreadyFinalized => error.StreamWriterAlreadyFinalized,
        error.InvalidDeferTransfer => error.StreamWriterDeferredTransfer,
        error.InvalidState, error.JoinConflict => error.StreamWriterLeasePathConflict,
        error.Unfinalized => error.StreamWriterLeaseDropped,
        error.InvalidLeaseIndex => error.StreamWriterLeasePathConflict,
    };
}

fn clone_env(allocator: std.mem.Allocator, env: LeaseEnv) !LeaseEnv {
    return .{ .states = try allocator.dupe(LeaseState, env.states) };
}

fn find_binding(bindings: []const WriterBinding, name: []const u8, before_idx: usize) ?usize {
    var idx = bindings.len;
    while (idx > 0) {
        idx -= 1;
        if (bindings[idx].decl_idx <= before_idx and std.mem.eql(u8, bindings[idx].name, name)) return idx;
    }
    return null;
}

fn same_type(tokens: []const lexer.Token, binding: WriterBinding, type_start: usize, type_end: usize) bool {
    if (binding.element_type_end - binding.element_type_start != type_end - type_start) return false;
    for (tokens[binding.element_type_start..binding.element_type_end], tokens[type_start..type_end]) |left, right| {
        if (!std.mem.eql(u8, left.lexeme, right.lexeme)) return false;
    }
    return true;
}

fn find_block_open(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var paren_depth: usize = 0;
    var angle_depth: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "(")) {
            paren_depth += 1;
            continue;
        }
        if (tok_eq(tokens[i], ")")) {
            if (paren_depth > 0) paren_depth -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "<")) {
            angle_depth += 1;
            continue;
        }
        if (tok_eq(tokens[i], ">")) {
            if (angle_depth > 0) angle_depth -= 1;
            continue;
        }
        if (paren_depth == 0 and angle_depth == 0 and tok_eq(tokens[i], "{")) return i;
        if (paren_depth == 0 and angle_depth == 0 and tokens[i].line > tokens[start_idx].line and tok_eq(tokens[i], "return")) return null;
    }
    return null;
}

fn branch_after_idx(tokens: []const lexer.Token, branch_idx: usize, end_idx: usize) ?usize {
    const open = find_block_open(tokens, branch_idx + 1, end_idx) orelse return null;
    const close = find_matching(tokens, open, "{", "}") catch return null;
    var cursor = close + 1;
    if (cursor < end_idx and tok_eq(tokens[cursor], "else")) {
        if (cursor + 1 < end_idx and tok_eq(tokens[cursor + 1], "if")) return branch_after_idx(tokens, cursor + 1, end_idx);
        if (cursor + 1 < end_idx and tok_eq(tokens[cursor + 1], "{")) {
            const else_close = find_matching(tokens, cursor + 1, "{", "}") catch return null;
            cursor = else_close + 1;
        }
    }
    return cursor;
}

fn loop_after_idx(tokens: []const lexer.Token, loop_idx: usize, end_idx: usize) ?usize {
    _ = end_idx;
    const open = find_loop_block_open(tokens, loop_idx) orelse return null;
    const close = find_matching(tokens, open, "{", "}") catch return null;
    return close + 1;
}

fn parse_deferred_close(tokens: []const lexer.Token, idx: usize, end_idx: usize) ?Finalization {
    if (idx + 4 >= end_idx or !tok_eq(tokens[idx + 1], "close") or !tok_eq(tokens[idx + 2], "(") or
        tokens[idx + 3].kind != .ident or !tok_eq(tokens[idx + 4], ")")) return null;
    return .{ .operand_idx = idx + 3, .close_idx = idx + 4 };
}

fn is_stream_writer_finalizer(tokens: []const lexer.Token, idx: usize, end_idx: usize) ?Finalization {
    if (idx + 3 >= end_idx or tokens[idx].kind != .ident or
        (!tok_eq(tokens[idx], "close") and !tok_eq(tokens[idx], "abort")) or
        !tok_eq(tokens[idx + 1], "(") or tokens[idx + 2].kind != .ident) return null;
    const close_idx = find_matching(tokens, idx + 1, "(", ")") catch return null;
    if (close_idx >= end_idx) return null;
    const valid = if (tok_eq(tokens[idx], "close")) close_idx == idx + 3 else close_idx == idx + 5;
    if (!valid) return null;
    return .{ .operand_idx = idx + 2, .close_idx = close_idx };
}

fn is_stream_writer_transfer(tokens: []const lexer.Token, idx: usize, end_idx: usize) ?struct {
    source_idx: usize,
    element_type_start: usize,
    element_type_end: usize,
} {
    if (idx + 4 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "StreamWriter") or !tok_eq(tokens[idx + 2], "<")) return null;
    const close_angle = find_matching(tokens, idx + 2, "<", ">") catch return null;
    if (close_angle + 2 >= end_idx or !tok_eq(tokens[close_angle + 1], "=") or tokens[close_angle + 2].kind != .ident) return null;
    return .{ .source_idx = close_angle + 2, .element_type_start = idx + 3, .element_type_end = close_angle };
}

fn is_future_binding(
    tokens: []const lexer.Token,
    idx: usize,
    end_idx: usize,
    bindings: []const WriterBinding,
) ?WriterCall {
    if (idx + 3 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Future") or !tok_eq(tokens[idx + 2], "<")) return null;
    const future_close = find_matching(tokens, idx + 2, "<", ">") catch return null;
    if (future_close + 4 >= end_idx or !tok_eq(tokens[future_close + 1], "=")) return null;
    var callee_idx = future_close + 2;
    var open_idx = future_close + 3;
    if (tok_eq(tokens[callee_idx], "@") and tok_eq(tokens[callee_idx + 1], "async") and tok_eq(tokens[callee_idx + 2], "(")) {
        callee_idx += 3;
        open_idx += 3;
    }
    if (tokens[callee_idx].kind != .ident or !tok_eq(tokens[open_idx], "(")) return null;
    const call_close = find_matching(tokens, open_idx, "(", ")") catch return null;
    if (call_close >= end_idx) return null;
    var writer_arg_idx: ?usize = null;
    var arg_idx = callee_idx + 2;
    while (arg_idx < call_close) : (arg_idx += 1) {
        if (tokens[arg_idx].kind == .ident and writer_arg_idx == null and
            find_binding(bindings, tokens[arg_idx].lexeme, arg_idx) != null)
        {
            writer_arg_idx = arg_idx;
        }
    }
    return .{ .callee_idx = callee_idx, .writer_arg_idx = writer_arg_idx, .call_close = call_close };
}

test "future binding resolves a reordered helper writer argument" {
    const source =
        \\async forward_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
        \\    pending Future<Result<nil, ProbeError>> = finish_stream(value, writer, count)
        \\    return await(pending)
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    var future_idx: ?usize = null;
    var writer_decl_idx: ?usize = null;
    for (tokens, 0..) |token, idx| {
        if (tok_eq(token, "pending") and future_idx == null) future_idx = idx;
        if (tok_eq(token, "writer") and writer_decl_idx == null) writer_decl_idx = idx;
    }
    try std.testing.expect(future_idx != null);
    try std.testing.expect(writer_decl_idx != null);

    const bindings = [_]WriterBinding{.{
        .name = "writer",
        .decl_idx = writer_decl_idx.?,
        .element_type_start = 0,
        .element_type_end = 0,
        .initially_owned = true,
    }};
    const call = is_future_binding(tokens, future_idx.?, tokens.len, &bindings) orelse return error.TestUnexpectedResult;
    try std.testing.expect(call.writer_arg_idx != null);
    try std.testing.expectEqualStrings("writer", tokens[call.writer_arg_idx.?].lexeme);
}

test "writer lease transfer consumes only the source" {
    var states = [_]LeaseState{ .owned, .finalized };
    var env = LeaseEnv{ .states = &states };
    try env.apply(.{ .transfer = .{ .source = 0, .target = 1 } });
    try std.testing.expectEqual(LeaseState.moved, env.states[0]);
    try std.testing.expectEqual(LeaseState.owned, env.states[1]);
}

test "writer lease finalization is exactly once" {
    var states = [_]LeaseState{.owned};
    var env = LeaseEnv{ .states = &states };
    try env.apply(.{ .finalize = 0 });
    try std.testing.expectError(error.AlreadyFinalized, env.apply(.{ .finalize = 0 }));
}

test "deferred owner remains writable before scope exit" {
    var states = [_]LeaseState{.owned};
    var env = LeaseEnv{ .states = &states };
    try env.apply(.{ .register_defer = 0 });
    try env.apply(.{ .write = 0 });
}

test "join rejects one-sided finalization" {
    var left_states = [_]LeaseState{.finalized};
    var right_states = [_]LeaseState{.owned};
    const joined = try LeaseEnv.join(std.testing.allocator, .{ .states = &left_states }, .{ .states = &right_states });
    var owned_join = joined;
    defer owned_join.deinit(std.testing.allocator);
    try std.testing.expectEqual(LeaseState.maybe, owned_join.states[0]);
}

test "join accepts equal finalized branches" {
    var left_states = [_]LeaseState{.finalized};
    var right_states = [_]LeaseState{.finalized};
    const joined = try LeaseEnv.join(std.testing.allocator, .{ .states = &left_states }, .{ .states = &right_states });
    var owned_join = joined;
    defer owned_join.deinit(std.testing.allocator);
    try std.testing.expectEqual(LeaseState.finalized, owned_join.states[0]);
}
