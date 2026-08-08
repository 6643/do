const std = @import("std");
const lexer = @import("lexer.zig");
const sema_tokens = @import("sema_tokens.zig");
const sema_stream_lease = @import("sema_stream_lease.zig");

const tok_eq = sema_tokens.tok_eq;
const find_matching = sema_tokens.find_matching;
const mark_error_at = sema_tokens.mark_error_at;
const is_func_decl_start = sema_tokens.is_func_decl_start;
const is_top_level_decl_head = sema_tokens.is_top_level_decl_head;
const string_token_body = sema_tokens.string_token_body;

const FutureBinding = struct {
    name: []const u8,
    decl_idx: usize,
    consumed: bool = false,
};

const StreamReaderBinding = struct {
    name: []const u8,
    element_type_start: usize,
    element_type_end: usize,
    consumed: bool = false,
};

const StreamWriterBinding = struct {
    name: []const u8,
    decl_idx: usize,
    element_type_start: usize,
    element_type_end: usize,
    active: bool = true,
};

pub fn check_await_context(tokens: []const lexer.Token) !void {
    for (tokens, 0..) |token, idx| {
        if (is_stream_next_call_head(tokens, idx)) {
            if (stream_next_operand_idx(tokens, idx, tokens.len) == null or
                (!is_inside_async_body(tokens, idx) and !is_inside_colorless_body(tokens, idx)))
            {
                return mark_error_at(tokens, idx, error.InvalidStreamReaderRead);
            }
            continue;
        }
        if (is_cancel_call_head(tokens, idx)) {
            if (!is_inside_async_body(tokens, idx) and !is_inside_colorless_body(tokens, idx)) {
                return mark_error_at(tokens, idx, error.InvalidAwaitContext);
            }
            continue;
        }
        if (tok_eq(token, "await")) {
            if (await_operand_idx(tokens, idx, tokens.len) == null or
                (!is_inside_async_body(tokens, idx) and !is_inside_colorless_body(tokens, idx)))
            {
                return mark_error_at(tokens, idx, error.InvalidAwaitContext);
            }
            continue;
        }
        if (!is_aggregate_await_name(token)) continue;
        if (aggregate_await_operands(tokens, idx, tokens.len) == null or
            (!is_inside_async_body(tokens, idx) and !is_inside_colorless_body(tokens, idx)))
        {
            return mark_error_at(tokens, idx, error.InvalidAwaitContext);
        }
    }
    for (tokens, 0..) |token, idx| {
        if (!is_stream_writer_finalizer_name(token)) continue;
        if (!is_inside_async_body(tokens, idx) and !is_inside_colorless_body(tokens, idx)) {
            return mark_error_at(tokens, idx, error.InvalidStreamWriterFinalization);
        }
    }
}

fn is_cancel_call_head(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 2 < tokens.len and
        tok_eq(tokens[idx], "@") and
        tok_eq(tokens[idx + 1], "cancel") and
        tok_eq(tokens[idx + 2], "(");
}

fn is_stream_next_call_head(tokens: []const lexer.Token, idx: usize) bool {
    return idx + 2 < tokens.len and
        tok_eq(tokens[idx], "@") and
        tok_eq(tokens[idx + 1], "next") and
        tok_eq(tokens[idx + 2], "(");
}

pub fn check_async_ownership(allocator: std.mem.Allocator, tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        const head = function_head_at(tokens, i) orelse continue;
        const close_params = head.close_params;
        const body_open = head.body_open;
        const body_close = find_matching(tokens, body_open, "{", "}") catch continue;
        if (head.is_async or function_signature_contains_stream(tokens, head.open_params + 1, close_params) or
            body_contains_async_operation(tokens, body_open + 1, body_close))
        {
            try check_async_body(allocator, tokens, head.open_params + 1, close_params, body_open + 1, body_close);
        }
        i = body_close;
    }
}

fn function_signature_contains_stream(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i + 1 < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "StreamReader") or tok_eq(tokens[i], "StreamWriter") or tok_eq(tokens[i], "Stream")) return true;
    }
    return false;
}

/// A Future is a task handle, not an alternate return type. Ordinary calls
/// therefore need the explicit `@async(call)` boundary. Registered host/WIT
/// bindings and the built-in stream operations are already Future-producing
/// boundaries and remain direct calls.
pub fn check_implicit_future_creation(tokens: []const lexer.Token) !void {
    var i: usize = 0;
    while (i + 1 < tokens.len) : (i += 1) {
        const head = function_head_at(tokens, i) orelse continue;
        const body_close = find_matching(tokens, head.body_open, "{", "}") catch continue;
        if (head.is_async) {
            i = body_close;
            continue;
        }

        var cursor = head.body_open + 1;
        while (cursor < body_close) : (cursor += 1) {
            if (!is_future_binding(tokens, cursor, body_close)) continue;
            const future_close = find_matching(tokens, cursor + 2, "<", ">") catch continue;
            if (future_close + 2 >= body_close or !tok_eq(tokens[future_close + 1], "=")) continue;
            const rhs_idx = future_close + 2;
            if (is_explicit_future_expr(tokens, rhs_idx, body_close)) continue;
            if (tokens[rhs_idx].kind != .ident or !tok_eq(tokens[rhs_idx + 1], "(")) continue;
            const name = tokens[rhs_idx].lexeme;
            if (is_host_binding_name(tokens, name) or is_generated_wit_binding_name(tokens, name) or
                is_stream_writer_name(tokens, head.open_params + 1, head.close_params, name) or
                is_stream_writer_name(tokens, head.body_open + 1, cursor, name)) continue;
            return mark_error_at(tokens, rhs_idx, error.ImplicitFutureCreation);
        }
        i = body_close;
    }
}

fn is_explicit_future_expr(tokens: []const lexer.Token, idx: usize, end_idx: usize) bool {
    if (idx + 3 >= end_idx or !tok_eq(tokens[idx], "@") or tokens[idx + 1].kind != .ident) return false;
    const name = tokens[idx + 1].lexeme;
    return (std.mem.eql(u8, name, "async") or std.mem.eql(u8, name, "next")) and tok_eq(tokens[idx + 2], "(");
}

fn is_stream_writer_name(tokens: []const lexer.Token, start_idx: usize, end_idx: usize, name: []const u8) bool {
    var i = start_idx;
    while (i + 2 < end_idx) : (i += 1) {
        if (tokens[i].kind != .ident or !std.mem.eql(u8, tokens[i].lexeme, name) or
            !tok_eq(tokens[i + 1], "StreamWriter") or !tok_eq(tokens[i + 2], "<")) continue;
        return true;
    }
    return false;
}

const FunctionHead = struct {
    open_params: usize,
    close_params: usize,
    body_open: usize,
    is_async: bool,
};

fn function_head_at(tokens: []const lexer.Token, idx: usize) ?FunctionHead {
    var open_params: usize = undefined;
    var is_async = false;
    if (idx + 2 < tokens.len and tok_eq(tokens[idx], "async") and
        tokens[idx + 1].kind == .ident and tok_eq(tokens[idx + 2], "(") and
        is_top_level_decl_head(tokens, idx))
    {
        open_params = idx + 2;
        is_async = true;
    } else if (is_func_decl_start(tokens, idx) and is_top_level_decl_head(tokens, idx)) {
        open_params = idx + 1;
    } else {
        return null;
    }

    const close_params = find_matching(tokens, open_params, "(", ")") catch return null;
    const body_open = find_body_open(tokens, close_params + 1) orelse return null;
    return .{
        .open_params = open_params,
        .close_params = close_params,
        .body_open = body_open,
        .is_async = is_async,
    };
}

fn body_contains_async_operation(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "Future") or tok_eq(tokens[i], "StreamReader") or
            tok_eq(tokens[i], "StreamWriter") or tok_eq(tokens[i], "await") or
            tok_eq(tokens[i], "await_all") or tok_eq(tokens[i], "await_any") or
            tok_eq(tokens[i], "close") or tok_eq(tokens[i], "abort")) return true;
        if (i + 1 < end_idx and tok_eq(tokens[i], "@") and
            (tok_eq(tokens[i + 1], "async") or tok_eq(tokens[i + 1], "await") or
                tok_eq(tokens[i + 1], "cancel") or tok_eq(tokens[i + 1], "next"))) return true;
    }
    return false;
}

fn is_inside_async_body(tokens: []const lexer.Token, idx: usize) bool {
    var candidate: ?usize = null;
    var i: usize = 0;
    while (i + 3 < tokens.len and i < idx) : (i += 1) {
        if (!tok_eq(tokens[i], "async") or !tok_eq(tokens[i + 2], "(")) continue;
        const close_params = find_matching(tokens, i + 2, "(", ")") catch continue;
        const body_open = find_body_open(tokens, close_params + 1) orelse continue;
        const body_close = find_matching(tokens, body_open, "{", "}") catch continue;
        if (body_open < idx and idx < body_close) candidate = body_open;
    }
    return candidate != null;
}

fn is_inside_colorless_body(tokens: []const lexer.Token, idx: usize) bool {
    var i: usize = 0;
    while (i + 2 < idx and i + 2 < tokens.len) : (i += 1) {
        if (!is_func_decl_start(tokens, i)) continue;
        const close_params = find_matching(tokens, i + 1, "(", ")") catch continue;
        if (close_params >= tokens.len or close_params + 1 >= tokens.len) continue;
        const body_open = find_body_open(tokens, close_params + 1) orelse continue;
        const body_close = find_matching(tokens, body_open, "{", "}") catch continue;
        if (!(body_open < idx and idx < body_close)) continue;
        // A colorless function is resumable when its body contains any
        // explicit Future/async operation. This includes argument-bearing WIT
        // host calls and the canonical @await/@cancel forms.
        if (body_contains_async_operation(tokens, body_open + 1, body_close)) return true;
    }
    return false;
}

fn has_direct_host_future_binding(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var idx = start_idx;
    while (idx + 5 < end_idx) : (idx += 1) {
        if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Future") or !tok_eq(tokens[idx + 2], "<")) continue;
        const type_close = find_matching(tokens, idx + 2, "<", ">") catch continue;
        if (type_close + 4 >= end_idx or !tok_eq(tokens[type_close + 1], "=") or
            tokens[type_close + 2].kind != .ident or !tok_eq(tokens[type_close + 3], "(") or
            !tok_eq(tokens[type_close + 4], ")")) continue;
        if (is_host_binding_name(tokens, tokens[type_close + 2].lexeme) or
            is_generated_wit_binding_name(tokens, tokens[type_close + 2].lexeme)) return true;
    }
    return false;
}

fn is_host_binding_name(tokens: []const lexer.Token, name: []const u8) bool {
    var idx: usize = 0;
    while (idx + 4 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !std.mem.eql(u8, tokens[idx].lexeme, name) or
            !tok_eq(tokens[idx + 1], "=") or !tok_eq(tokens[idx + 2], "@") or
            (!tok_eq(tokens[idx + 3], "host_func") and !tok_eq(tokens[idx + 3], "host_async_func"))) continue;
        return true;
    }
    return false;
}

fn is_generated_wit_binding_name(tokens: []const lexer.Token, name: []const u8) bool {
    // Generated bindings live under the project-root `wit/` directory. Their
    // manifest is validated by `do wit check`; the frontend only needs the
    // locator shape here to recognize a direct Future-producing import.
    var idx: usize = 0;
    while (idx + 8 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !std.mem.eql(u8, tokens[idx].lexeme, name) or
            !tok_eq(tokens[idx + 1], "=") or !tok_eq(tokens[idx + 2], "@") or
            !tok_eq(tokens[idx + 3], "lib") or !tok_eq(tokens[idx + 4], "(")) continue;
        const path = string_token_body(tokens[idx + 5].lexeme) orelse continue;
        if (std.mem.startsWith(u8, path, "./wit/") or std.mem.startsWith(u8, path, "wit/")) return true;
    }
    return false;
}

fn check_async_body(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    params_start: usize,
    params_end: usize,
    start_idx: usize,
    end_idx: usize,
) !void {
    var future_bindings = try std.ArrayList(FutureBinding).initCapacity(allocator, 0);
    defer future_bindings.deinit(allocator);
    var reader_bindings = try std.ArrayList(StreamReaderBinding).initCapacity(allocator, 0);
    defer reader_bindings.deinit(allocator);
    var writer_bindings = try std.ArrayList(StreamWriterBinding).initCapacity(allocator, 0);
    defer writer_bindings.deinit(allocator);

    try collect_stream_reader_params(&reader_bindings, allocator, tokens, params_start, params_end);
    try collect_stream_writer_params(&writer_bindings, allocator, tokens, params_start, params_end);
    const lease_checked = try sema_stream_lease.check_async_writer_body(
        allocator,
        tokens,
        params_start,
        params_end,
        start_idx,
        end_idx,
        stream_writer_helper_transfer_for_lease,
    );

    var i = start_idx;
    var block_depth: usize = 0;
    var has_prior_return = false;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "{")) {
            block_depth += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (block_depth > 0) block_depth -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "return")) {
            has_prior_return = true;
        }
        if (stream_next_binding(tokens, i, end_idx)) |binding| {
            try validate_stream_next(&reader_bindings, tokens, binding);
            try future_bindings.append(allocator, .{ .name = tokens[i].lexeme, .decl_idx = i });
            continue;
        }
        if (is_future_binding(tokens, i, end_idx)) {
            const future_idx = i;
            const future_name = tokens[i].lexeme;
            if (stream_writer_helper_call(tokens, i, end_idx, &writer_bindings)) |call| {
                if (block_depth != 0 or has_prior_return) {
                    return mark_error_at(tokens, call.source_idx, error.InvalidStreamWriterWrite);
                }
                try transfer_stream_writer_to_helper(&writer_bindings, tokens, call.source_idx);
            }
            if (stream_writer_call_in_future(tokens, i, end_idx)) |call| {
                if (find_stream_writer_binding(writer_bindings.items, tokens[call.writer_idx].lexeme) != null) {
                    try validate_stream_writer_write(&writer_bindings, tokens, params_start, i, call);
                    i = call.value_end;
                }
            }
            try future_bindings.append(allocator, .{ .name = future_name, .decl_idx = future_idx });
            continue;
        }
        if (block_depth == 0) {
            if (stream_new_binding(tokens, i, end_idx)) |binding| {
                try reader_bindings.append(allocator, .{
                    .name = tokens[binding.reader_idx].lexeme,
                    .element_type_start = binding.element_type_start,
                    .element_type_end = binding.element_type_end,
                });
                try writer_bindings.append(allocator, .{
                    .name = tokens[binding.writer_idx].lexeme,
                    .decl_idx = binding.writer_idx,
                    .element_type_start = binding.element_type_start,
                    .element_type_end = binding.element_type_end,
                });
                continue;
            }
            if (stream_reader_tuple_extract(tokens, i, end_idx)) |extract| {
                if (has_stream_completion_tuple_binding(tokens, start_idx, i, tokens[extract.source_idx].lexeme, extract.element_type_start, extract.element_type_end)) {
                    try reader_bindings.append(allocator, .{
                        .name = tokens[i].lexeme,
                        .element_type_start = extract.element_type_start,
                        .element_type_end = extract.element_type_end,
                    });
                }
                continue;
            }
        }
        if (stream_reader_transfer(tokens, i, end_idx)) |transfer| {
            try transfer_stream_reader(&reader_bindings, allocator, tokens, i, transfer);
            continue;
        }
        if (is_stream_writer_finalizer_name(tokens[i])) {
            const finalization = stream_writer_finalization(tokens, i, end_idx) orelse
                return mark_error_at(tokens, i, error.InvalidStreamWriterFinalization);
            if (find_stream_writer_binding(writer_bindings.items, tokens[finalization.operand_idx].lexeme) == null) {
                return mark_error_at(tokens, finalization.operand_idx, error.InvalidStreamWriterFinalization);
            }
            if (!finalization.valid) return mark_error_at(tokens, i, error.InvalidCallArgList);
            const deferred_close = i > start_idx and tok_eq(tokens[i - 1], "defer") and tok_eq(tokens[i], "close");
            if (block_depth == 0 and !has_prior_return and !deferred_close) {
                try finalize_stream_writer(&writer_bindings, tokens, finalization.operand_idx);
            }
            continue;
        }
        if (tokens[i].kind == .ident and i + 1 < end_idx and tok_eq(tokens[i + 1], "(") and
            find_stream_writer_binding(writer_bindings.items, tokens[i].lexeme) != null)
        {
            return mark_error_at(tokens, i, error.InvalidStreamWriterWrite);
        }
        if (block_depth == 0 and !has_prior_return) {
            if (stream_writer_transfer(tokens, i, end_idx)) |transfer| {
                try transfer_stream_writer(&writer_bindings, allocator, tokens, i, transfer);
                continue;
            }
        }
        if (cancel_operand_idx(tokens, i, end_idx)) |operand_idx| {
            if (find_future_binding(future_bindings.items, tokens[operand_idx].lexeme) == null and
                has_typed_local_binding(tokens, tokens[operand_idx].lexeme, start_idx, end_idx)) continue;
            try consume_future(&future_bindings, tokens, operand_idx);
            continue;
        }
        if (aggregate_await_operands(tokens, i, end_idx)) |operands| {
            var operand_idx = operands.first_idx;
            while (operand_idx < operands.close_idx) : (operand_idx += 2) {
                if (find_future_binding(future_bindings.items, tokens[operand_idx].lexeme) == null and
                    has_typed_local_binding(tokens, tokens[operand_idx].lexeme, start_idx, end_idx)) continue;
                try consume_future(&future_bindings, tokens, operand_idx);
            }
            continue;
        }
        if (!tok_eq(tokens[i], "await")) continue;
        const operand_idx = await_operand_idx(tokens, i, end_idx) orelse return mark_error_at(tokens, i, error.InvalidAwaitContext);
        if (find_future_binding(future_bindings.items, tokens[operand_idx].lexeme) == null and
            has_typed_local_binding(tokens, tokens[operand_idx].lexeme, start_idx, end_idx)) continue;
        try consume_future(&future_bindings, tokens, operand_idx);
    }

    for (future_bindings.items) |binding| {
        if (!binding.consumed) return mark_error_at(tokens, binding.decl_idx, error.FutureDropped);
    }
    for (writer_bindings.items) |binding| {
        if (binding.active and !lease_checked) return mark_error_at(tokens, binding.decl_idx, error.StreamWriterLeaseDropped);
    }
}

fn collect_stream_reader_params(
    bindings: *std.ArrayList(StreamReaderBinding),
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) !void {
    var i = start_idx;
    while (i + 2 < end_idx) : (i += 1) {
        if (tokens[i].kind != .ident or !is_stream_reader_type(tokens[i + 1]) or !tok_eq(tokens[i + 2], "<")) continue;
        const close_angle = find_matching(tokens, i + 2, "<", ">") catch continue;
        if (close_angle >= end_idx) continue;
        try bindings.append(allocator, .{
            .name = tokens[i].lexeme,
            .element_type_start = i + 3,
            .element_type_end = close_angle,
        });
    }
}

fn collect_stream_writer_params(
    bindings: *std.ArrayList(StreamWriterBinding),
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    start_idx: usize,
    end_idx: usize,
) !void {
    var i = start_idx;
    while (i + 2 < end_idx) : (i += 1) {
        if (tokens[i].kind != .ident or !tok_eq(tokens[i + 1], "StreamWriter") or !tok_eq(tokens[i + 2], "<")) continue;
        const close_angle = find_matching(tokens, i + 2, "<", ">") catch continue;
        if (close_angle >= end_idx) continue;
        try bindings.append(allocator, .{
            .name = tokens[i].lexeme,
            .decl_idx = i,
            .element_type_start = i + 3,
            .element_type_end = close_angle,
        });
    }
}

const StreamReaderTransfer = struct {
    source_idx: usize,
    element_type_start: usize,
    element_type_end: usize,
};

fn stream_reader_transfer(tokens: []const lexer.Token, idx: usize, end_idx: usize) ?StreamReaderTransfer {
    if (idx + 4 >= end_idx or tokens[idx].kind != .ident or !is_stream_reader_type(tokens[idx + 1]) or !tok_eq(tokens[idx + 2], "<")) return null;
    const close_angle = find_matching(tokens, idx + 2, "<", ">") catch return null;
    if (close_angle + 2 >= end_idx or !tok_eq(tokens[close_angle + 1], "=") or tokens[close_angle + 2].kind != .ident) return null;
    return .{
        .source_idx = close_angle + 2,
        .element_type_start = idx + 3,
        .element_type_end = close_angle,
    };
}

fn is_stream_reader_type(token: lexer.Token) bool {
    return tok_eq(token, "Stream") or tok_eq(token, "StreamReader");
}

const StreamNewBinding = struct {
    reader_idx: usize,
    writer_idx: usize,
    element_type_start: usize,
    element_type_end: usize,
};

fn stream_new_binding(tokens: []const lexer.Token, idx: usize, end_idx: usize) ?StreamNewBinding {
    if (idx + 2 >= end_idx or tokens[idx].kind != .ident or !is_stream_reader_type(tokens[idx + 1]) or !tok_eq(tokens[idx + 2], "<")) return null;
    const reader_close = find_matching(tokens, idx + 2, "<", ">") catch return null;
    if (reader_close + 5 >= end_idx or !tok_eq(tokens[reader_close + 1], ",") or tokens[reader_close + 2].kind != .ident or
        !tok_eq(tokens[reader_close + 3], "StreamWriter") or !tok_eq(tokens[reader_close + 4], "<"))
    {
        return null;
    }
    const writer_close = find_matching(tokens, reader_close + 4, "<", ">") catch return null;
    if (writer_close + 4 >= end_idx or !tok_eq(tokens[writer_close + 1], "=") or !tok_eq(tokens[writer_close + 2], "new_stream") or
        !tok_eq(tokens[writer_close + 3], "<"))
    {
        return null;
    }
    const call_type_close = find_matching(tokens, writer_close + 3, "<", ">") catch return null;
    if (call_type_close + 2 >= end_idx or !tok_eq(tokens[call_type_close + 1], "(")) return null;
    const call_close = find_matching(tokens, call_type_close + 1, "(", ")") catch return null;
    if (call_close >= end_idx or !has_single_call_arg(tokens, call_type_close + 2, call_close) or
        !token_ranges_equal(tokens, idx + 3, reader_close, reader_close + 5, writer_close) or
        !token_ranges_equal(tokens, idx + 3, reader_close, writer_close + 4, call_type_close))
    {
        return null;
    }
    return .{
        .reader_idx = idx,
        .writer_idx = reader_close + 2,
        .element_type_start = idx + 3,
        .element_type_end = reader_close,
    };
}

const StreamReaderTupleExtract = struct {
    source_idx: usize,
    element_type_start: usize,
    element_type_end: usize,
};

fn stream_reader_tuple_extract(tokens: []const lexer.Token, idx: usize, end_idx: usize) ?StreamReaderTupleExtract {
    if (idx + 11 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Stream") or !tok_eq(tokens[idx + 2], "<")) return null;
    const close_angle = find_matching(tokens, idx + 2, "<", ">") catch return null;
    if (close_angle + 9 >= end_idx or
        !tok_eq(tokens[close_angle + 1], "=") or
        !tok_eq(tokens[close_angle + 2], "@") or
        !tok_eq(tokens[close_angle + 3], "get") or
        !tok_eq(tokens[close_angle + 4], "(") or
        tokens[close_angle + 5].kind != .ident or
        !tok_eq(tokens[close_angle + 6], ",") or
        !tok_eq(tokens[close_angle + 7], "0") or
        !tok_eq(tokens[close_angle + 8], ")"))
    {
        return null;
    }
    return .{
        .source_idx = close_angle + 5,
        .element_type_start = idx + 3,
        .element_type_end = close_angle,
    };
}

fn has_stream_completion_tuple_binding(
    tokens: []const lexer.Token,
    body_start: usize,
    before_idx: usize,
    source_name: []const u8,
    element_type_start: usize,
    element_type_end: usize,
) bool {
    var i = body_start;
    while (i + 15 < before_idx) : (i += 1) {
        if (tokens[i].kind != .ident or !std.mem.eql(u8, tokens[i].lexeme, source_name) or
            !tok_eq(tokens[i + 1], "Tuple") or !tok_eq(tokens[i + 2], "<") or
            !tok_eq(tokens[i + 3], "Stream") or !tok_eq(tokens[i + 4], "<"))
        {
            continue;
        }
        const stream_close = find_matching(tokens, i + 4, "<", ">") catch continue;
        if (!token_ranges_equal(tokens, i + 5, stream_close, element_type_start, element_type_end) or
            stream_close + 6 >= before_idx or !tok_eq(tokens[stream_close + 1], ",") or
            !tok_eq(tokens[stream_close + 2], "Future") or !tok_eq(tokens[stream_close + 3], "<") or
            !tok_eq(tokens[stream_close + 4], "Result") or !tok_eq(tokens[stream_close + 5], "<")) continue;
        const result_close = find_matching(tokens, stream_close + 5, "<", ">") catch continue;
        const future_close = find_matching(tokens, stream_close + 3, "<", ">") catch continue;
        if (result_close + 1 != future_close or future_close + 4 >= before_idx or
            !tok_eq(tokens[future_close + 1], ">") or
            !tok_eq(tokens[future_close + 2], "=") or tokens[future_close + 3].kind != .ident or
            !tok_eq(tokens[future_close + 4], "(")) continue;
        // The completion future is an ownership-tracked Result regardless of
        // its payload; descriptor-specific lowering validates its exact shape.
        if (result_close <= stream_close + 6) continue;
        return true;
    }
    return false;
}

const StreamNextBinding = struct {
    item_type_start: usize,
    item_type_end: usize,
    reader_idx: usize,
};

fn stream_next_binding(tokens: []const lexer.Token, idx: usize, end_idx: usize) ?StreamNextBinding {
    if (idx + 10 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Future") or !tok_eq(tokens[idx + 2], "<")) return null;
    const future_close = find_matching(tokens, idx + 2, "<", ">") catch return null;
    if (future_close + 6 >= end_idx or !tok_eq(tokens[idx + 3], "Result") or !tok_eq(tokens[idx + 4], "<")) return null;
    const result_close = find_matching(tokens, idx + 4, "<", ">") catch return null;
    if (result_close + 1 != future_close or future_close + 6 >= end_idx) return null;
    const comma_idx = find_result_item_comma(tokens, idx + 5, result_close) orelse return null;
    if (comma_idx == idx + 5 or comma_idx + 2 != result_close or !tok_eq(tokens[comma_idx + 1], "nil")) return null;
    if (!tok_eq(tokens[future_close + 1], "=") or !tok_eq(tokens[future_close + 2], "@") or !tok_eq(tokens[future_close + 3], "next") or !tok_eq(tokens[future_close + 4], "(") or tokens[future_close + 5].kind != .ident or !tok_eq(tokens[future_close + 6], ")")) return null;
    return .{
        .item_type_start = idx + 5,
        .item_type_end = comma_idx,
        .reader_idx = future_close + 5,
    };
}

fn find_result_item_comma(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    var angle_depth: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "<")) {
            angle_depth += 1;
            continue;
        }
        if (tok_eq(tokens[i], ">")) {
            if (angle_depth == 0) return null;
            angle_depth -= 1;
            continue;
        }
        if (angle_depth == 0 and tok_eq(tokens[i], ",")) return i;
    }
    return null;
}

fn validate_stream_next(bindings: *const std.ArrayList(StreamReaderBinding), tokens: []const lexer.Token, binding: StreamNextBinding) !void {
    const binding_idx = find_stream_reader_binding(bindings.items, tokens[binding.reader_idx].lexeme) orelse
        return mark_error_at(tokens, binding.reader_idx, error.InvalidStreamReaderRead);
    const reader = bindings.items[binding_idx];
    if (reader.consumed) return mark_error_at(tokens, binding.reader_idx, error.StreamReaderAlreadyConsumed);
    if (!token_ranges_equal(tokens, reader.element_type_start, reader.element_type_end, binding.item_type_start, binding.item_type_end)) {
        return mark_error_at(tokens, binding.reader_idx, error.InvalidStreamReaderRead);
    }
}

const StreamWriterTransfer = struct {
    source_idx: usize,
    element_type_start: usize,
    element_type_end: usize,
};

const StreamWriterCall = struct {
    writer_idx: usize,
    value_start: usize,
    value_end: usize,
};

const StreamWriterHelperCall = struct {
    source_idx: usize,
};

fn stream_writer_helper_call(
    tokens: []const lexer.Token,
    idx: usize,
    end_idx: usize,
    bindings: *const std.ArrayList(StreamWriterBinding),
) ?StreamWriterHelperCall {
    if (!is_future_binding(tokens, idx, end_idx)) return null;
    const future_close = find_matching(tokens, idx + 2, "<", ">") catch return null;
    if (future_close + 5 >= end_idx or !tok_eq(tokens[future_close + 1], "=")) return null;
    var name_idx = future_close + 2;
    var open_idx = future_close + 3;
    if (tok_eq(tokens[name_idx], "@") and tok_eq(tokens[name_idx + 1], "async") and tok_eq(tokens[name_idx + 2], "(")) {
        name_idx += 3;
        open_idx += 3;
    }
    if (tokens[name_idx].kind != .ident or !tok_eq(tokens[open_idx], "(") or name_idx + 1 >= end_idx or
        tokens[name_idx + 1].kind != .ident) return null;
    const call_close = find_matching(tokens, open_idx, "(", ")") catch return null;
    const helper_name = tokens[name_idx].lexeme;
    var writer_arg_idx: usize = undefined;
    const first_arg_idx = name_idx + 2;
    if (call_close == first_arg_idx + 1) {
        const source_idx = find_stream_writer_binding(bindings.items, tokens[first_arg_idx].lexeme) orelse return null;
        const element_type_start = bindings.items[source_idx].element_type_start;
        const element_type_end = bindings.items[source_idx].element_type_end;
        if (!async_stream_writer_helper_accepts(tokens, helper_name, element_type_start, element_type_end)) return null;
        writer_arg_idx = first_arg_idx;
    } else {
        var source_idx: ?usize = null;
        var argument_idx = first_arg_idx;
        while (argument_idx < call_close) : (argument_idx += 1) {
            if (tokens[argument_idx].kind != .ident) continue;
            if (find_stream_writer_binding(bindings.items, tokens[argument_idx].lexeme)) |candidate| {
                source_idx = candidate;
                break;
            }
        }
        const writer_source_idx = source_idx orelse return null;
        const element_type_start = bindings.items[writer_source_idx].element_type_start;
        const element_type_end = bindings.items[writer_source_idx].element_type_end;
        writer_arg_idx = async_parameterized_stream_writer_helper_accepts(
            tokens,
            helper_name,
            first_arg_idx,
            call_close,
            element_type_start,
            element_type_end,
        ) orelse return null;
    }
    if (tokens[writer_arg_idx].kind != .ident) return null;
    if (find_stream_writer_binding(bindings.items, tokens[writer_arg_idx].lexeme) == null) return null;
    return .{ .source_idx = writer_arg_idx };
}

fn stream_writer_helper_transfer_for_lease(
    tokens: []const lexer.Token,
    future_idx: usize,
    end_idx: usize,
    writer_idx: usize,
    element_type_start: usize,
    element_type_end: usize,
) bool {
    if (!is_future_binding(tokens, future_idx, end_idx)) return false;
    const future_close = find_matching(tokens, future_idx + 2, "<", ">") catch return false;
    if (future_close + 5 >= end_idx or !tok_eq(tokens[future_close + 1], "=")) return false;
    var name_idx = future_close + 2;
    var open_idx = future_close + 3;
    if (tok_eq(tokens[name_idx], "@") and tok_eq(tokens[name_idx + 1], "async") and tok_eq(tokens[name_idx + 2], "(")) {
        name_idx += 3;
        open_idx += 3;
    }
    if (tokens[name_idx].kind != .ident or !tok_eq(tokens[open_idx], "(")) return false;
    const call_close = find_matching(tokens, open_idx, "(", ")") catch return false;
    const helper_name = tokens[name_idx].lexeme;
    const first_arg_idx = name_idx + 2;
    if (call_close == first_arg_idx + 1) {
        if (first_arg_idx != writer_idx) return false;
        return async_stream_writer_helper_accepts(tokens, helper_name, element_type_start, element_type_end);
    }
    const accepted_writer_idx = async_parameterized_stream_writer_helper_accepts(
        tokens,
        helper_name,
        first_arg_idx,
        call_close,
        element_type_start,
        element_type_end,
    ) orelse return false;
    return accepted_writer_idx == writer_idx;
}

fn async_stream_writer_helper_accepts(
    tokens: []const lexer.Token,
    helper_name: []const u8,
    element_type_start: usize,
    element_type_end: usize,
) bool {
    var i: usize = 0;
    while (i + 7 < tokens.len) : (i += 1) {
        const open_params = if (tok_eq(tokens[i], "async") and tokens[i + 1].kind == .ident and
            std.mem.eql(u8, tokens[i + 1].lexeme, helper_name) and tok_eq(tokens[i + 2], "("))
            i + 2
        else if (is_func_decl_start(tokens, i) and std.mem.eql(u8, tokens[i].lexeme, helper_name))
            i + 1
        else
            continue;
        const close_params = find_matching(tokens, open_params, "(", ")") catch continue;
        const first_param = if (tok_eq(tokens[i], "async")) i + 3 else i + 2;
        if (first_param + 2 >= close_params or tokens[first_param].kind != .ident or
            !tok_eq(tokens[first_param + 1], "StreamWriter") or !tok_eq(tokens[first_param + 2], "<")) continue;
        const helper_type_close = find_matching(tokens, first_param + 2, "<", ">") catch continue;
        if (helper_type_close + 1 != close_params or
            !token_ranges_equal(tokens, first_param + 3, helper_type_close, element_type_start, element_type_end)) continue;
        return true;
    }
    return false;
}

const AsyncParameterizedParameterKind = enum {
    writer,
    count,
    value,
};

const AsyncParameterizedParameter = struct {
    kind: AsyncParameterizedParameterKind,
    next_idx: usize,
    element_type_start: usize = 0,
    element_type_end: usize = 0,
};

fn parse_async_parameterized_parameter(tokens: []const lexer.Token, idx: usize, end_idx: usize) ?AsyncParameterizedParameter {
    if (idx >= end_idx or tokens[idx].kind != .ident or idx + 1 >= end_idx) return null;
    if (tok_eq(tokens[idx + 1], "u64")) return .{ .kind = .count, .next_idx = idx + 2 };
    if (tok_eq(tokens[idx + 1], "u8")) return .{ .kind = .value, .next_idx = idx + 2 };
    if (!tok_eq(tokens[idx + 1], "StreamWriter") or idx + 2 >= end_idx or !tok_eq(tokens[idx + 2], "<")) return null;
    const type_close = find_matching(tokens, idx + 2, "<", ">") catch return null;
    if (type_close + 1 >= end_idx) return null;
    return .{
        .kind = .writer,
        .next_idx = type_close + 1,
        .element_type_start = idx + 3,
        .element_type_end = type_close,
    };
}

fn async_parameterized_stream_writer_helper_accepts(
    tokens: []const lexer.Token,
    helper_name: []const u8,
    call_start: usize,
    call_close: usize,
    element_type_start: usize,
    element_type_end: usize,
) ?usize {
    var i: usize = 0;
    while (i + 3 < tokens.len) : (i += 1) {
        const open_params = if (tok_eq(tokens[i], "async") and tokens[i + 1].kind == .ident and
            std.mem.eql(u8, tokens[i + 1].lexeme, helper_name) and tok_eq(tokens[i + 2], "("))
            i + 2
        else if (is_func_decl_start(tokens, i) and std.mem.eql(u8, tokens[i].lexeme, helper_name))
            i + 1
        else
            continue;
        const close_params = find_matching(tokens, open_params, "(", ")") catch continue;
        var parameters: [3]AsyncParameterizedParameter = undefined;
        var seen = [_]bool{false} ** 3;
        var cursor = open_params + 1;
        var parameter_index: usize = 0;
        var valid = true;
        while (parameter_index < parameters.len) : (parameter_index += 1) {
            const parameter = parse_async_parameterized_parameter(tokens, cursor, close_params) orelse {
                valid = false;
                break;
            };
            const kind_index = @intFromEnum(parameter.kind);
            if (seen[kind_index]) {
                valid = false;
                break;
            }
            seen[kind_index] = true;
            parameters[parameter_index] = parameter;
            cursor = parameter.next_idx;
            if (parameter_index + 1 < parameters.len) {
                if (cursor >= close_params or !tok_eq(tokens[cursor], ",")) {
                    valid = false;
                    break;
                }
                cursor += 1;
            }
        }
        if (!valid or cursor != close_params or !seen[@intFromEnum(AsyncParameterizedParameterKind.writer)] or
            !seen[@intFromEnum(AsyncParameterizedParameterKind.count)] or !seen[@intFromEnum(AsyncParameterizedParameterKind.value)]) continue;

        var arg_idx = call_start;
        var writer_arg_idx: ?usize = null;
        for (parameters, 0..) |parameter, index| {
            if (arg_idx >= call_close or tokens[arg_idx].kind != .ident) {
                valid = false;
                break;
            }
            if (parameter.kind == .writer) {
                if (!token_ranges_equal(tokens, parameter.element_type_start, parameter.element_type_end, element_type_start, element_type_end)) {
                    valid = false;
                    break;
                }
                writer_arg_idx = arg_idx;
            }
            arg_idx += 1;
            if (index + 1 < parameters.len) {
                if (arg_idx >= call_close or !tok_eq(tokens[arg_idx], ",")) {
                    valid = false;
                    break;
                }
                arg_idx += 1;
            }
        }
        if (valid and arg_idx == call_close) return writer_arg_idx;
    }
    return null;
}

fn stream_writer_call_in_future(tokens: []const lexer.Token, idx: usize, end_idx: usize) ?StreamWriterCall {
    if (!is_future_binding(tokens, idx, end_idx)) return null;
    const future_close = find_matching(tokens, idx + 2, "<", ">") catch return null;
    if (future_close + 4 >= end_idx or !tok_eq(tokens[future_close + 1], "=") or tokens[future_close + 2].kind != .ident or
        !tok_eq(tokens[future_close + 3], "("))
    {
        return null;
    }
    const call_close = find_matching(tokens, future_close + 3, "(", ")") catch return null;
    if (call_close > end_idx) return null;
    return .{
        .writer_idx = future_close + 2,
        .value_start = future_close + 4,
        .value_end = call_close,
    };
}

fn validate_stream_writer_write(
    bindings: *const std.ArrayList(StreamWriterBinding),
    tokens: []const lexer.Token,
    scope_start: usize,
    future_idx: usize,
    call: StreamWriterCall,
) !void {
    const writer_binding_idx = find_stream_writer_binding(bindings.items, tokens[call.writer_idx].lexeme) orelse
        return mark_error_at(tokens, call.writer_idx, error.InvalidStreamWriterWrite);
    if (!bindings.items[writer_binding_idx].active) {
        return mark_error_at(tokens, call.writer_idx, error.StreamWriterAlreadyFinalized);
    }
    if (!stream_writer_future_result_is_unit_error(tokens, future_idx)) {
        return mark_error_at(tokens, future_idx, error.InvalidStreamWriterWrite);
    }
    const value_ok = has_single_call_arg(tokens, call.value_start, call.value_end) and
        stream_writer_value_matches(tokens, scope_start, call.value_start, call.value_end, bindings.items[writer_binding_idx]);
    if (!value_ok) return mark_error_at(tokens, call.writer_idx, error.InvalidStreamWriterWrite);
}

fn stream_writer_future_result_is_unit_error(tokens: []const lexer.Token, future_idx: usize) bool {
    const future_close = find_matching(tokens, future_idx + 2, "<", ">") catch return false;
    if (future_close != future_idx + 9 or !tok_eq(tokens[future_idx + 3], "Result") or !tok_eq(tokens[future_idx + 4], "<") or
        !tok_eq(tokens[future_idx + 5], "nil") or !tok_eq(tokens[future_idx + 6], ",") or tokens[future_idx + 7].kind != .ident or
        !tok_eq(tokens[future_idx + 8], ">") or !tok_eq(tokens[future_idx + 9], ">"))
    {
        return false;
    }
    return true;
}

fn stream_writer_value_matches(
    tokens: []const lexer.Token,
    scope_start: usize,
    value_start: usize,
    value_end: usize,
    binding: StreamWriterBinding,
) bool {
    if (value_end - value_start != 1) return false;
    const value = tokens[value_start];
    if (token_ranges_equal(tokens, binding.element_type_start, binding.element_type_end, value_start, value_end)) return true;
    if (value.kind == .number) return numeric_literal_matches(tokens, value, binding.element_type_start, binding.element_type_end);
    if (value.kind != .ident) return false;
    return typed_value_binding_before(tokens, scope_start, value_start, value.lexeme, binding.element_type_start, binding.element_type_end);
}

fn numeric_literal_matches(tokens: []const lexer.Token, value: lexer.Token, type_start: usize, type_end: usize) bool {
    if (type_end != type_start + 1) return false;
    const parsed = std.fmt.parseInt(i64, value.lexeme, 10) catch return false;
    const type_name = tokens[type_start].lexeme;
    if (std.mem.eql(u8, type_name, "u8")) return parsed >= 0 and parsed <= 255;
    if (std.mem.eql(u8, type_name, "i8")) return parsed >= -128 and parsed <= 127;
    if (std.mem.eql(u8, type_name, "u16")) return parsed >= 0 and parsed <= 65535;
    if (std.mem.eql(u8, type_name, "i16")) return parsed >= -32768 and parsed <= 32767;
    if (std.mem.eql(u8, type_name, "u32") or std.mem.eql(u8, type_name, "u64") or
        std.mem.eql(u8, type_name, "usize") or std.mem.eql(u8, type_name, "isize")) return parsed >= 0;
    return std.mem.eql(u8, type_name, "i32") or std.mem.eql(u8, type_name, "i64");
}

fn typed_value_binding_before(
    tokens: []const lexer.Token,
    scope_start: usize,
    before_idx: usize,
    name: []const u8,
    type_start: usize,
    type_end: usize,
) bool {
    var i = scope_start;
    while (i + 2 < before_idx) : (i += 1) {
        if (tokens[i].kind != .ident or !std.mem.eql(u8, tokens[i].lexeme, name)) continue;
        if (!token_ranges_equal(tokens, i + 1, i + 2, type_start, type_end)) continue;
        if (i + 2 < before_idx and (tok_eq(tokens[i + 2], "=") or tok_eq(tokens[i + 2], ",") or tok_eq(tokens[i + 2], ")"))) return true;
    }
    return false;
}

fn stream_writer_transfer(tokens: []const lexer.Token, idx: usize, end_idx: usize) ?StreamWriterTransfer {
    if (idx + 4 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "StreamWriter") or !tok_eq(tokens[idx + 2], "<")) return null;
    const close_angle = find_matching(tokens, idx + 2, "<", ">") catch return null;
    if (close_angle + 2 >= end_idx or !tok_eq(tokens[close_angle + 1], "=") or tokens[close_angle + 2].kind != .ident) return null;
    return .{
        .source_idx = close_angle + 2,
        .element_type_start = idx + 3,
        .element_type_end = close_angle,
    };
}

const StreamWriterFinalization = struct {
    operand_idx: usize,
    valid: bool,
};

fn stream_writer_finalization(tokens: []const lexer.Token, idx: usize, end_idx: usize) ?StreamWriterFinalization {
    if (idx + 3 >= end_idx or tokens[idx].kind != .ident) return null;
    if (!is_stream_writer_finalizer_name(tokens[idx])) return null;
    if (!tok_eq(tokens[idx + 1], "(") or tokens[idx + 2].kind != .ident) return null;
    const close_idx = find_matching(tokens, idx + 1, "(", ")") catch return null;
    if (close_idx >= end_idx) return null;
    if (tok_eq(tokens[idx], "close")) return .{ .operand_idx = idx + 2, .valid = close_idx == idx + 3 };
    return .{ .operand_idx = idx + 2, .valid = has_single_call_arg(tokens, idx + 4, close_idx) };
}

fn is_stream_writer_finalizer_name(token: lexer.Token) bool {
    return tok_eq(token, "close") or tok_eq(token, "abort");
}

fn has_single_call_arg(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx >= end_idx) return false;
    var paren_depth: usize = 0;
    var brace_depth: usize = 0;
    var angle_depth: usize = 0;
    var i = start_idx;
    while (i < end_idx) : (i += 1) {
        if (tok_eq(tokens[i], "(")) {
            paren_depth += 1;
            continue;
        }
        if (tok_eq(tokens[i], ")")) {
            if (paren_depth == 0) return false;
            paren_depth -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "{")) {
            brace_depth += 1;
            continue;
        }
        if (tok_eq(tokens[i], "}")) {
            if (brace_depth == 0) return false;
            brace_depth -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "<")) {
            angle_depth += 1;
            continue;
        }
        if (tok_eq(tokens[i], ">")) {
            if (angle_depth == 0) return false;
            angle_depth -= 1;
            continue;
        }
        if (tok_eq(tokens[i], ",") and paren_depth == 0 and brace_depth == 0 and angle_depth == 0) return false;
    }
    return paren_depth == 0 and brace_depth == 0 and angle_depth == 0;
}

fn transfer_stream_reader(
    bindings: *std.ArrayList(StreamReaderBinding),
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    target_idx: usize,
    transfer: StreamReaderTransfer,
) !void {
    const source_binding_idx = find_stream_reader_binding(bindings.items, tokens[transfer.source_idx].lexeme) orelse return;
    const source = bindings.items[source_binding_idx];
    if (source.consumed) return mark_error_at(tokens, transfer.source_idx, error.StreamReaderAlreadyConsumed);
    if (!token_ranges_equal(tokens, source.element_type_start, source.element_type_end, transfer.element_type_start, transfer.element_type_end)) {
        return mark_error_at(tokens, target_idx + 1, error.StreamReaderTypeMismatch);
    }
    bindings.items[source_binding_idx].consumed = true;
    try bindings.append(allocator, .{
        .name = tokens[target_idx].lexeme,
        .element_type_start = transfer.element_type_start,
        .element_type_end = transfer.element_type_end,
    });
}

fn transfer_stream_writer(
    bindings: *std.ArrayList(StreamWriterBinding),
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    target_idx: usize,
    transfer: StreamWriterTransfer,
) !void {
    const source_binding_idx = find_stream_writer_binding(bindings.items, tokens[transfer.source_idx].lexeme) orelse return;
    const source = bindings.items[source_binding_idx];
    if (!source.active) return mark_error_at(tokens, transfer.source_idx, error.StreamWriterAlreadyFinalized);
    if (!token_ranges_equal(tokens, source.element_type_start, source.element_type_end, transfer.element_type_start, transfer.element_type_end)) {
        return mark_error_at(tokens, target_idx + 1, error.StreamWriterTypeMismatch);
    }
    bindings.items[source_binding_idx].active = false;
    try bindings.append(allocator, .{
        .name = tokens[target_idx].lexeme,
        .decl_idx = target_idx,
        .element_type_start = transfer.element_type_start,
        .element_type_end = transfer.element_type_end,
    });
}

fn transfer_stream_writer_to_helper(
    bindings: *std.ArrayList(StreamWriterBinding),
    tokens: []const lexer.Token,
    source_idx: usize,
) !void {
    const source_binding_idx = find_stream_writer_binding(bindings.items, tokens[source_idx].lexeme) orelse return;
    if (!bindings.items[source_binding_idx].active) {
        return mark_error_at(tokens, source_idx, error.StreamWriterAlreadyFinalized);
    }
    bindings.items[source_binding_idx].active = false;
}

fn token_ranges_equal(tokens: []const lexer.Token, left_start: usize, left_end: usize, right_start: usize, right_end: usize) bool {
    if (left_end - left_start != right_end - right_start) return false;
    for (tokens[left_start..left_end], tokens[right_start..right_end]) |left, right| {
        if (!std.mem.eql(u8, left.lexeme, right.lexeme)) return false;
    }
    return true;
}

fn finalize_stream_writer(bindings: *std.ArrayList(StreamWriterBinding), tokens: []const lexer.Token, operand_idx: usize) !void {
    const binding_idx = find_stream_writer_binding(bindings.items, tokens[operand_idx].lexeme) orelse return;
    if (!bindings.items[binding_idx].active) return mark_error_at(tokens, operand_idx, error.StreamWriterAlreadyFinalized);
    bindings.items[binding_idx].active = false;
}

fn is_future_binding(tokens: []const lexer.Token, idx: usize, end_idx: usize) bool {
    return idx + 3 < end_idx and
        tokens[idx].kind == .ident and
        tok_eq(tokens[idx + 1], "Future") and
        tok_eq(tokens[idx + 2], "<");
}

fn await_operand_idx(tokens: []const lexer.Token, await_idx: usize, end_idx: usize) ?usize {
    if (await_idx + 3 >= end_idx or !tok_eq(tokens[await_idx + 1], "(")) return null;
    if (tokens[await_idx + 2].kind != .ident) return null;
    if (tok_eq(tokens[await_idx + 3], ")")) return await_idx + 2;
    if (!tok_eq(tokens[await_idx + 3], ",") or !has_single_timeout_expr(tokens, await_idx + 4, end_idx)) return null;
    return await_idx + 2;
}

fn has_single_timeout_expr(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    if (start_idx >= end_idx) return false;
    const close_idx = find_matching(tokens, start_idx - 3, "(", ")") catch return false;
    if (close_idx >= end_idx or close_idx <= start_idx) return false;

    var paren_depth: usize = 0;
    var angle_depth: usize = 0;
    var i = start_idx;
    while (i < close_idx) : (i += 1) {
        if (tok_eq(tokens[i], "(")) {
            paren_depth += 1;
            continue;
        }
        if (tok_eq(tokens[i], ")")) {
            if (paren_depth == 0) return false;
            paren_depth -= 1;
            continue;
        }
        if (tok_eq(tokens[i], "<")) {
            angle_depth += 1;
            continue;
        }
        if (tok_eq(tokens[i], ">")) {
            if (angle_depth == 0) return false;
            angle_depth -= 1;
            continue;
        }
        if (tok_eq(tokens[i], ",") and paren_depth == 0 and angle_depth == 0) return false;
    }
    return paren_depth == 0 and angle_depth == 0;
}

fn is_aggregate_await_name(token: lexer.Token) bool {
    return tok_eq(token, "await_all") or tok_eq(token, "await_any");
}

const AggregateAwaitOperands = struct {
    first_idx: usize,
    close_idx: usize,
};

fn aggregate_await_operands(tokens: []const lexer.Token, await_idx: usize, end_idx: usize) ?AggregateAwaitOperands {
    if (!is_aggregate_await_name(tokens[await_idx]) or await_idx + 5 >= end_idx or !tok_eq(tokens[await_idx + 1], "(")) return null;
    const close_idx = find_matching(tokens, await_idx + 1, "(", ")") catch return null;
    if (close_idx >= end_idx or close_idx <= await_idx + 4) return null;

    var operand_count: usize = 0;
    var i = await_idx + 2;
    while (i < close_idx) : (i += 2) {
        if (tokens[i].kind != .ident) return null;
        operand_count += 1;
        if (i + 1 == close_idx) break;
        if (!tok_eq(tokens[i + 1], ",")) return null;
    }
    if (operand_count < 2) return null;

    return .{ .first_idx = await_idx + 2, .close_idx = close_idx };
}

fn cancel_operand_idx(tokens: []const lexer.Token, cancel_idx: usize, end_idx: usize) ?usize {
    if (cancel_idx + 4 >= end_idx or !tok_eq(tokens[cancel_idx], "@") or !tok_eq(tokens[cancel_idx + 1], "cancel")) return null;
    if (!tok_eq(tokens[cancel_idx + 2], "(") or tokens[cancel_idx + 3].kind != .ident or !tok_eq(tokens[cancel_idx + 4], ")")) return null;
    return cancel_idx + 3;
}

fn stream_next_operand_idx(tokens: []const lexer.Token, next_idx: usize, end_idx: usize) ?usize {
    if (next_idx + 4 >= end_idx or !is_stream_next_call_head(tokens, next_idx)) return null;
    if (tokens[next_idx + 3].kind != .ident or !tok_eq(tokens[next_idx + 4], ")")) return null;
    return next_idx + 3;
}

fn consume_future(bindings: *std.ArrayList(FutureBinding), tokens: []const lexer.Token, operand_idx: usize) !void {
    const binding_idx = find_future_binding(bindings.items, tokens[operand_idx].lexeme) orelse
        return mark_error_at(tokens, operand_idx, error.InvalidAwaitContext);
    if (bindings.items[binding_idx].consumed) return mark_error_at(tokens, operand_idx, error.FutureAlreadyConsumed);
    bindings.items[binding_idx].consumed = true;
}

fn find_future_binding(bindings: []const FutureBinding, name: []const u8) ?usize {
    for (bindings, 0..) |binding, idx| {
        if (std.mem.eql(u8, binding.name, name)) return idx;
    }
    return null;
}

fn has_typed_local_binding(tokens: []const lexer.Token, name: []const u8, start_idx: usize, end_idx: usize) bool {
    var i = start_idx;
    while (i + 2 < end_idx) : (i += 1) {
        if (tokens[i].kind != .ident or !std.mem.eql(u8, tokens[i].lexeme, name)) continue;
        if (tokens[i + 1].kind != .ident) continue;
        if (tok_eq(tokens[i + 2], "=") or tok_eq(tokens[i + 2], "<")) return true;
    }
    return false;
}

fn find_stream_reader_binding(bindings: []const StreamReaderBinding, name: []const u8) ?usize {
    for (bindings, 0..) |binding, idx| {
        if (std.mem.eql(u8, binding.name, name)) return idx;
    }
    return null;
}

fn find_stream_writer_binding(bindings: []const StreamWriterBinding, name: []const u8) ?usize {
    var idx = bindings.len;
    while (idx > 0) {
        idx -= 1;
        if (std.mem.eql(u8, bindings[idx].name, name)) return idx;
    }
    return null;
}

fn find_body_open(tokens: []const lexer.Token, start_idx: usize) ?usize {
    var i = start_idx;
    while (i < tokens.len) : (i += 1) {
        if (tok_eq(tokens[i], "{")) return i;
        if (tokens[i].line != tokens[start_idx - 1].line and i > start_idx) return null;
    }
    return null;
}
