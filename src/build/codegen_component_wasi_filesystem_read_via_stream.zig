const std = @import("std");
const generated_text = @import("codegen_text.zig");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const p3_async_manifest = @import("p3_async_manifest.zig");
const sema_tokens = @import("sema_tokens.zig");

const compact_token_range_equals = sema_tokens.compact_token_range_equals;
const find_matching = sema_tokens.find_matching;
const string_token_body = sema_tokens.string_token_body;
const tok_eq = sema_tokens.tok_eq;

pub const Error = error{UnsupportedP3WasiReadViaStreamComponent};

const locator = "wasi:filesystem/types@0.3.0-rc-2025-09-16";
const member = "descriptor.read-via-stream";
const handles_type = "Tuple<Stream<u8>,Future<Result<nil,FileError>>>";
const completion_type = "Future<Result<nil,FileError>>";
const item_future_type = "Future<Result<u8,nil>>";
const item_result_type = "Result<u8,nil>";
pub const max_read_via_stream_reads: usize = 3;

pub const ReadViaStreamPlan = struct {
    export_name: []const u8,
    descriptor: p3_async_manifest.Descriptor,
    file_name: []const u8,
    offset_name: []const u8,
    read_count: usize,

    pub fn analyze(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) Error!ReadViaStreamPlan {
        const host = find_host(tokens, registry) orelse return error.UnsupportedP3WasiReadViaStreamComponent;
        const function = find_run_function(tokens) orelse return error.UnsupportedP3WasiReadViaStreamComponent;
        if (!find_cancel_function(tokens)) return error.UnsupportedP3WasiReadViaStreamComponent;
        var pos = function.body_start;

        const handles = parse_handle_acquisition(tokens, pos, function.body_end, host.name, function.file_name, function.offset_name) orelse
            return error.UnsupportedP3WasiReadViaStreamComponent;
        pos = handles.next_idx;
        const reader = parse_tuple_element(tokens, pos, function.body_end, "Stream<u8>", handles.name, "0") orelse
            return error.UnsupportedP3WasiReadViaStreamComponent;
        pos = reader.next_idx;
        const completion = parse_tuple_element(tokens, pos, function.body_end, completion_type, handles.name, "1") orelse
            return error.UnsupportedP3WasiReadViaStreamComponent;
        pos = completion.next_idx;

        var read_count: usize = 0;
        while (parse_next(tokens, pos, function.body_end, reader.name)) |pending| {
            if (read_count >= max_read_via_stream_reads) return error.UnsupportedP3WasiReadViaStreamComponent;
            pos = pending.next_idx;
            const item = parse_await(tokens, pos, function.body_end, item_result_type, pending.name) orelse
                return error.UnsupportedP3WasiReadViaStreamComponent;
            pos = parse_discard(tokens, item.next_idx, function.body_end, item.name) orelse
                return error.UnsupportedP3WasiReadViaStreamComponent;
            read_count += 1;
        }
        if (read_count == 0) return error.UnsupportedP3WasiReadViaStreamComponent;

        const completed = parse_await(tokens, pos, function.body_end, "Result<nil,FileError>", completion.name) orelse
            return error.UnsupportedP3WasiReadViaStreamComponent;
        pos = parse_discard(tokens, completed.next_idx, function.body_end, completed.name) orelse
            return error.UnsupportedP3WasiReadViaStreamComponent;
        if (pos + 1 != function.body_end or !tok_eq(tokens[pos], "return")) return error.UnsupportedP3WasiReadViaStreamComponent;

        return .{
            .export_name = function.name,
            .descriptor = host.descriptor,
            .file_name = function.file_name,
            .offset_name = function.offset_name,
            .read_count = read_count,
        };
    }
};

pub fn emit_component_wat(
    allocator: std.mem.Allocator,
    program: parser.Program,
    tokens: []const lexer.Token,
    module_graph: ?*const imports.ModuleGraph,
) anyerror![]u8 {
    _ = program;
    _ = module_graph;
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    const plan = try ReadViaStreamPlan.analyze(tokens, registry);
    var wat = try generated_text.alloc_block(allocator, 0, core_wat);
    errdefer allocator.free(wat);
    const read_count = try generated_text.alloc_fmt(allocator, "{[count]d}", .{ .count = plan.read_count });
    defer allocator.free(read_count);
    const shape = switch (p3_async_manifest.lowering_shape(plan.descriptor) orelse return error.UnsupportedP3WasiReadViaStreamComponent) {
        .filesystem_byte_stream_reader => |value| value,
        else => return error.UnsupportedP3WasiReadViaStreamComponent,
    };
    const stream_cancel_read_name = try async_cancel_import_name(allocator, shape.stream.cancel_read.import_name);
    defer allocator.free(stream_cancel_read_name);
    const future_cancel_read_name = try async_cancel_import_name(allocator, shape.future.cancel_read.?.import_name);
    defer allocator.free(future_cancel_read_name);
    const replacements = [_][2][]const u8{
        .{ "[method-module]", plan.descriptor.canonical.async_import_module },
        .{ "[method-name]", shape.method.import_name },
        .{ "[stream-cancel-read-name]", stream_cancel_read_name },
        .{ "[stream-read-name]", shape.stream.read.import_name },
        .{ "[future-cancel-read-name]", future_cancel_read_name },
        .{ "[stream-drop-name]", shape.stream.drop_readable.import_name },
        .{ "[future-read-name]", shape.future.read.?.import_name },
        .{ "[future-drop-name]", shape.future.drop_readable.import_name },
        .{ "[read-count]", read_count },
    };
    for (replacements) |replacement| wat = try replace_and_free(allocator, wat, replacement[0], replacement[1]);
    return wat;
}

pub fn emit_component_wit(allocator: std.mem.Allocator, tokens: []const lexer.Token) anyerror![]u8 {
    var registry = try p3_async_manifest.Registry.load(allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(allocator);
    _ = try ReadViaStreamPlan.analyze(tokens, registry);
    return generated_text.alloc_block(allocator, 0, component_wit);
}

const Host = struct {
    name: []const u8,
    descriptor: p3_async_manifest.Descriptor,
};

const Function = struct {
    name: []const u8,
    file_name: []const u8,
    offset_name: []const u8,
    body_start: usize,
    body_end: usize,
};

const Binding = struct {
    name: []const u8,
    next_idx: usize,
};

fn find_host(tokens: []const lexer.Token, registry: p3_async_manifest.Registry) ?Host {
    var found: ?Host = null;
    var idx: usize = 0;
    while (idx + 33 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "=") or !tok_eq(tokens[idx + 2], "@") or
            !tok_eq(tokens[idx + 3], "host_func") or !tok_eq(tokens[idx + 4], "(") or
            tokens[idx + 5].kind != .string or !tok_eq(tokens[idx + 6], ",") or tokens[idx + 7].kind != .string or
            !tok_eq(tokens[idx + 8], ",") or !tok_eq(tokens[idx + 9], "(") or !tok_eq(tokens[idx + 10], "File") or
            !tok_eq(tokens[idx + 11], ",") or !tok_eq(tokens[idx + 12], "u64") or !tok_eq(tokens[idx + 13], ")") or
            !tok_eq(tokens[idx + 14], "-") or !tok_eq(tokens[idx + 15], ">") or !tok_eq(tokens[idx + 16], "Tuple") or
            !tok_eq(tokens[idx + 17], "<") or !tok_eq(tokens[idx + 18], "Stream") or !tok_eq(tokens[idx + 19], "<") or
            !tok_eq(tokens[idx + 20], "u8") or !tok_eq(tokens[idx + 21], ">") or !tok_eq(tokens[idx + 22], ",") or
            !tok_eq(tokens[idx + 23], "Future") or !tok_eq(tokens[idx + 24], "<") or !tok_eq(tokens[idx + 25], "Result") or
            !tok_eq(tokens[idx + 26], "<") or !tok_eq(tokens[idx + 27], "nil") or !tok_eq(tokens[idx + 28], ",") or
            !tok_eq(tokens[idx + 29], "FileError") or !tok_eq(tokens[idx + 30], ">") or !tok_eq(tokens[idx + 31], ">") or
            !tok_eq(tokens[idx + 32], ">") or !tok_eq(tokens[idx + 33], ")")) continue;
        const host_locator = string_token_body(tokens[idx + 5].lexeme) orelse continue;
        const host_member = string_token_body(tokens[idx + 7].lexeme) orelse continue;
        if (!std.mem.eql(u8, host_locator, locator) or !std.mem.eql(u8, host_member, member)) continue;
        const descriptor = registry.find(host_locator, host_member) orelse continue;
        switch (p3_async_manifest.lowering_shape(descriptor) orelse continue) {
            .filesystem_byte_stream_reader => {},
            else => continue,
        }
        if (found != null) return null;
        found = .{ .name = tokens[idx].lexeme, .descriptor = descriptor };
    }
    return found;
}

fn find_run_function(tokens: []const lexer.Token) ?Function {
    var found: ?Function = null;
    var idx: usize = 0;
    while (idx + 10 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "(") or (idx > 0 and tok_eq(tokens[idx - 1], "async"))) continue;
        if (tokens[idx + 2].kind != .ident or !tok_eq(tokens[idx + 3], "File") or !tok_eq(tokens[idx + 4], ",") or
            tokens[idx + 5].kind != .ident or !tok_eq(tokens[idx + 6], "u64") or !tok_eq(tokens[idx + 7], ")") or
            !tok_eq(tokens[idx + 8], "-") or !tok_eq(tokens[idx + 9], ">") or !tok_eq(tokens[idx + 10], "nil")) continue;
        var body_open = idx + 11;
        while (body_open < tokens.len and !tok_eq(tokens[body_open], "{")) : (body_open += 1) {}
        if (body_open >= tokens.len) return null;
        const body_end = find_matching(tokens, body_open, "{", "}") catch return null;
        if (found != null) return null;
        found = .{
            .name = tokens[idx].lexeme,
            .file_name = tokens[idx + 2].lexeme,
            .offset_name = tokens[idx + 5].lexeme,
            .body_start = body_open + 1,
            .body_end = body_end,
        };
        idx = body_end;
    }
    return found;
}

fn find_cancel_function(tokens: []const lexer.Token) bool {
    var idx: usize = 0;
    while (idx + 7 < tokens.len) : (idx += 1) {
        if (tokens[idx].kind != .ident or !std.mem.eql(u8, tokens[idx].lexeme, "cancel_probe") or
            !tok_eq(tokens[idx + 1], "(") or !tok_eq(tokens[idx + 2], ")") or
            !tok_eq(tokens[idx + 3], "-") or !tok_eq(tokens[idx + 4], ">") or
            !tok_eq(tokens[idx + 5], "nil") or !tok_eq(tokens[idx + 6], "{")) continue;
        const body_end = find_matching(tokens, idx + 6, "{", "}") catch return false;
        if (body_end == idx + 7) return true;
    }
    return false;
}

fn parse_handle_acquisition(tokens: []const lexer.Token, idx: usize, end_idx: usize, host_name: []const u8, file_name: []const u8, offset_name: []const u8) ?Binding {
    if (idx + 7 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Tuple") or !tok_eq(tokens[idx + 2], "<")) return null;
    const close = find_matching(tokens, idx + 2, "<", ">") catch return null;
    if (!compact_token_range_equals(tokens, idx + 1, close + 1, handles_type) or !tok_eq(tokens[close + 1], "=") or
        tokens[close + 2].kind != .ident or !std.mem.eql(u8, tokens[close + 2].lexeme, host_name) or !tok_eq(tokens[close + 3], "(") or
        tokens[close + 4].kind != .ident or !std.mem.eql(u8, tokens[close + 4].lexeme, file_name) or !tok_eq(tokens[close + 5], ",") or
        tokens[close + 6].kind != .ident or !std.mem.eql(u8, tokens[close + 6].lexeme, offset_name) or !tok_eq(tokens[close + 7], ")")) return null;
    return .{ .name = tokens[idx].lexeme, .next_idx = close + 8 };
}

fn parse_tuple_element(tokens: []const lexer.Token, idx: usize, end_idx: usize, type_name: []const u8, handles_name: []const u8, element_index: []const u8) ?Binding {
    if (idx + 8 >= end_idx or tokens[idx].kind != .ident or tokens[idx + 1].kind != .ident) return null;
    const type_end = find_type_end(tokens, idx + 1, end_idx) orelse return null;
    if (!compact_token_range_equals(tokens, idx + 1, type_end, type_name) or !tok_eq(tokens[type_end], "=") or !tok_eq(tokens[type_end + 1], "@") or
        !tok_eq(tokens[type_end + 2], "get") or !tok_eq(tokens[type_end + 3], "(") or tokens[type_end + 4].kind != .ident or
        !std.mem.eql(u8, tokens[type_end + 4].lexeme, handles_name) or !tok_eq(tokens[type_end + 5], ",") or
        !tok_eq(tokens[type_end + 6], element_index) or !tok_eq(tokens[type_end + 7], ")")) return null;
    return .{ .name = tokens[idx].lexeme, .next_idx = type_end + 8 };
}

fn parse_next(tokens: []const lexer.Token, idx: usize, end_idx: usize, reader_name: []const u8) ?Binding {
    if (idx + 6 >= end_idx or tokens[idx].kind != .ident or !tok_eq(tokens[idx + 1], "Future") or !tok_eq(tokens[idx + 2], "<")) return null;
    const close = find_matching(tokens, idx + 2, "<", ">") catch return null;
    if (!compact_token_range_equals(tokens, idx + 1, close + 1, item_future_type) or !tok_eq(tokens[close + 1], "=") or !tok_eq(tokens[close + 2], "@") or
        !tok_eq(tokens[close + 3], "next") or !tok_eq(tokens[close + 4], "(") or tokens[close + 5].kind != .ident or
        !std.mem.eql(u8, tokens[close + 5].lexeme, reader_name) or !tok_eq(tokens[close + 6], ")")) return null;
    return .{ .name = tokens[idx].lexeme, .next_idx = close + 7 };
}

fn parse_await(tokens: []const lexer.Token, idx: usize, end_idx: usize, type_name: []const u8, pending_name: []const u8) ?Binding {
    if (idx + 5 >= end_idx or tokens[idx].kind != .ident or tokens[idx + 1].kind != .ident) return null;
    const type_end = find_type_end(tokens, idx + 1, end_idx) orelse return null;
    const await_idx = if (tok_eq(tokens[type_end + 1], "@")) type_end + 2 else type_end + 1;
    if (!compact_token_range_equals(tokens, idx + 1, type_end, type_name) or !tok_eq(tokens[type_end], "=") or !tok_eq(tokens[await_idx], "await") or
        !tok_eq(tokens[await_idx + 1], "(") or tokens[await_idx + 2].kind != .ident or !std.mem.eql(u8, tokens[await_idx + 2].lexeme, pending_name) or
        !tok_eq(tokens[await_idx + 3], ")")) return null;
    return .{ .name = tokens[idx].lexeme, .next_idx = await_idx + 4 };
}

fn parse_discard(tokens: []const lexer.Token, idx: usize, end_idx: usize, name: []const u8) ?usize {
    if (idx + 2 >= end_idx or !tok_eq(tokens[idx], "_") or !tok_eq(tokens[idx + 1], "=") or tokens[idx + 2].kind != .ident or
        !std.mem.eql(u8, tokens[idx + 2].lexeme, name)) return null;
    return idx + 3;
}

fn find_type_end(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) ?usize {
    if (start_idx >= end_idx) return null;
    if (start_idx + 1 < end_idx and tok_eq(tokens[start_idx + 1], "<")) {
        const close = find_matching(tokens, start_idx + 1, "<", ">") catch return null;
        return if (close < end_idx) close + 1 else null;
    }
    return start_idx + 1;
}

fn replace_and_free(allocator: std.mem.Allocator, input: []u8, needle: []const u8, replacement: []const u8) ![]u8 {
    const output = try replace_all(allocator, input, needle, replacement);
    allocator.free(input);
    return output;
}

fn async_cancel_import_name(allocator: std.mem.Allocator, import_name: []const u8) ![]u8 {
    if (std.mem.startsWith(u8, import_name, "[async-lower]")) return allocator.dupe(u8, import_name);
    return generated_text.alloc_fmt(allocator, "[async-lower]{[name]s}", .{ .name = import_name });
}

fn replace_all(allocator: std.mem.Allocator, input: []const u8, needle: []const u8, replacement: []const u8) ![]u8 {
    if (needle.len == 0) return allocator.dupe(u8, input);
    var count: usize = 0;
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, input, cursor, needle)) |index| {
        count += 1;
        cursor = index + needle.len;
    }
    if (count == 0) return allocator.dupe(u8, input);
    const output_len = input.len - count * needle.len + count * replacement.len;
    var output = try allocator.alloc(u8, output_len);
    var input_cursor: usize = 0;
    var output_cursor: usize = 0;
    while (std.mem.indexOfPos(u8, input, input_cursor, needle)) |index| {
        const prefix = input[input_cursor..index];
        @memcpy(output[output_cursor .. output_cursor + prefix.len], prefix);
        output_cursor += prefix.len;
        @memcpy(output[output_cursor .. output_cursor + replacement.len], replacement);
        output_cursor += replacement.len;
        input_cursor = index + needle.len;
    }
    const suffix = input[input_cursor..];
    @memcpy(output[output_cursor .. output_cursor + suffix.len], suffix);
    return output;
}

const component_wit =
    \\package wasi:filesystem@0.3.0-rc-2025-09-16;
    \\
    \\interface types {
    \\  enum error-code { io, no-entry }
    \\  resource descriptor {
    \\    read-via-stream: func(offset: u64) -> tuple<stream<u8>, future<result<_, error-code>>>;
    \\  }
    \\}
    \\
    \\interface probe {
    \\  use types.{descriptor};
    \\  run: async func(file: own<descriptor>, offset: u64);
    \\  cancel: async func();
    \\}
    \\
    \\world read-via-stream-probe {
    \\  import types;
    \\  export probe;
    \\}
    \\
;

const core_wat =
    \\(module
    \\  (type $method (func (param i32 i64 i32)))
    \\  (type $stream-cancel (func (param i32) (result i32)))
    \\  (type $stream-read (func (param i32 i32 i32) (result i32)))
    \\  (type $future-cancel (func (param i32) (result i32)))
    \\  (type $future-read (func (param i32 i32) (result i32)))
    \\  (type $drop (func (param i32)))
    \\  (type $waitable-new (func (result i32)))
    \\  (type $waitable-join (func (param i32 i32)))
    \\  (type $waitable-drop (func (param i32)))
    \\  (type $context-get (func (result i32)))
    \\  (type $context-set (func (param i32)))
    \\  (type $run (func (param i32 i64) (result i32)))
    \\  (type $cancel (func (result i32)))
    \\  (type $callback (func (param i32 i32 i32) (result i32)))
    \\  (type $task-return (func))
    \\  (type $realloc (func (param i32 i32 i32 i32) (result i32)))
    \\  (type $initialize (func))
    \\  (import "[method-module]" "[method-name]" (func $read-via-stream (type $method)))
    \\  (import "[method-module]" "[stream-cancel-read-name]" (func $stream-cancel-read (type $stream-cancel)))
    \\  (import "[method-module]" "[stream-read-name]" (func $stream-read (type $stream-read)))
    \\  (import "[method-module]" "[future-cancel-read-name]" (func $future-cancel-read (type $future-cancel)))
    \\  (import "[method-module]" "[future-read-name]" (func $future-read (type $future-read)))
    \\  (import "[method-module]" "[stream-drop-name]" (func $stream-drop-readable (type $drop)))
    \\  (import "[method-module]" "[future-drop-name]" (func $future-drop-readable (type $drop)))
    \\  (import "[method-module]" "[resource-drop]descriptor" (func $descriptor-drop (type $drop)))
    \\  (import "$root" "[waitable-set-new]" (func $waitable-set-new (type $waitable-new)))
    \\  (import "$root" "[waitable-join]" (func $waitable-join (type $waitable-join)))
    \\  (import "$root" "[waitable-set-drop]" (func $waitable-set-drop (type $waitable-drop)))
    \\  (import "$root" "[context-get-0]" (func $context-get-0 (type $context-get)))
    \\  (import "$root" "[context-set-0]" (func $context-set-0 (type $context-set)))
    \\  (import "[export]$root" "[task-cancel]" (func $task-cancel (type $task-return)))
    \\  (import "[export]wasi:filesystem/probe@0.3.0-rc-2025-09-16" "[task-return]run" (func $task-return (type $task-return)))
    \\  (import "[export]wasi:filesystem/probe@0.3.0-rc-2025-09-16" "[task-return]cancel" (func $task-return-cancel (type $task-return)))
    \\  (memory (export "memory") 2)
    \\  (global $frame-next (mut i32) (i32.const 1024))
    \\  (global $heap-next (mut i32) (i32.const 65536))
    \\  (global $run-frame (mut i32) (i32.const 0))
    \\  (func $frame-alloc (result i32) global.get $frame-next global.get $frame-next i32.const 96 i32.add global.set $frame-next)
    \\  (func $wait (param $frame i32) (param $handle-offset i32) (result i32)
    \\    local.get $frame local.get $handle-offset i32.add i32.load local.get $frame i32.load call $waitable-join
    \\    local.get $frame i32.load i32.const 4 i32.shl i32.const 2 i32.or)
    \\  (func $cleanup (param $frame i32) (param $cancelled i32) (result i32) (local $handle i32)
    \\    local.get $frame i32.const 12 i32.add i32.load local.tee $handle i32.eqz if else local.get $handle call $future-drop-readable local.get $frame i32.const 12 i32.add i32.const 0 i32.store end
    \\    local.get $frame i32.const 8 i32.add i32.load local.tee $handle i32.eqz if else local.get $handle call $stream-drop-readable local.get $frame i32.const 8 i32.add i32.const 0 i32.store end
    \\    local.get $frame i32.const 4 i32.add i32.load local.tee $handle i32.eqz if else local.get $handle call $descriptor-drop local.get $frame i32.const 4 i32.add i32.const 0 i32.store end
    \\    local.get $frame i32.load local.tee $handle i32.eqz if else local.get $handle call $waitable-set-drop local.get $frame i32.const 0 i32.store end
    \\    i32.const 0 call $context-set-0
    \\    local.get $cancelled
    \\    if
    \\      call $task-cancel
    \\    else
    \\      call $task-return
    \\    end
    \\    local.get $frame i32.const 0 i32.store
    \\    global.get $run-frame local.get $frame i32.eq if i32.const 0 global.set $run-frame end
    \\    i32.const 0)
    \\  (func $start-completion (param $frame i32) (result i32) (local $code i32)
    \\    local.get $frame i32.const 20 i32.add i32.const 2 i32.store
    \\    local.get $frame i32.const 12 i32.add i32.load local.get $frame i32.const 80 i32.add call $future-read local.tee $code
    \\    i32.const -1 i32.eq if (result i32) local.get $frame i32.const 12 call $wait else local.get $frame i32.const 0 call $cleanup end)
    \\  (func $accept-stream (param $frame i32) (param $code i32) (result i32) (local $remaining i32)
    \\    local.get $code i32.const 2 i32.eq if (result i32)
    \\      local.get $frame i32.const 0 call $cleanup
    \\    else
    \\      local.get $frame i32.const 20 i32.add i32.const 0 i32.store
    \\      local.get $code i32.const 1 i32.eq if (result i32) local.get $frame call $start-completion else
    \\        local.get $code i32.const 16 i32.ne if unreachable end
    \\        local.get $frame i32.const 16 i32.add i32.load i32.const 1 i32.sub local.set $remaining
    \\        local.get $frame i32.const 16 i32.add local.get $remaining i32.store
    \\        local.get $remaining i32.eqz if (result i32) local.get $frame call $start-completion else local.get $frame call $start-stream end
    \\      end
    \\    end)
    \\  (func $start-stream (param $frame i32) (result i32) (local $code i32)
    \\    local.get $frame i32.const 20 i32.add i32.const 1 i32.store
    \\    local.get $frame i32.const 8 i32.add i32.load local.get $frame i32.const 64 i32.add i32.const 1 call $stream-read local.tee $code
    \\    i32.const -1 i32.eq if (result i32) local.get $frame i32.const 8 call $wait else local.get $frame local.get $code call $accept-stream end)
    \\  (func (export "[async-lift]wasi:filesystem/probe@0.3.0-rc-2025-09-16#run") (type $run) (param $file i32) (param $offset i64) (result i32) (local $frame i32)
    \\    call $frame-alloc local.tee $frame global.set $run-frame local.get $frame call $context-set-0 local.get $frame call $waitable-set-new i32.store
    \\    local.get $frame i32.const 4 i32.add local.get $file i32.store
    \\    local.get $frame i32.const 24 i32.add local.get $offset i64.store
    \\    local.get $file local.get $offset local.get $frame i32.const 32 i32.add call $read-via-stream
    \\    local.get $frame i32.const 8 i32.add local.get $frame i32.const 32 i32.add i32.load i32.store
    \\    local.get $frame i32.const 12 i32.add local.get $frame i32.const 36 i32.add i32.load i32.store
    \\    local.get $frame i32.const 16 i32.add i32.const [read-count] i32.store local.get $frame i32.const 20 i32.add i32.const 0 i32.store local.get $frame call $start-stream)
    \\  (func (export "[async-lift]wasi:filesystem/probe@0.3.0-rc-2025-09-16#cancel") (type $cancel) (result i32) (local $frame i32) (local $phase i32) (local $status i32)
    \\    global.get $run-frame local.set $frame
    \\    local.get $frame i32.eqz if call $task-return-cancel i32.const 0 return end
    \\    local.get $frame i32.const 20 i32.add i32.load local.set $phase
    \\    local.get $phase i32.const 1 i32.eq if
    \\      local.get $frame i32.const 8 i32.add i32.load call $stream-cancel-read local.set $status
    \\    else
    \\      local.get $phase i32.const 2 i32.eq if
    \\        local.get $frame i32.const 12 i32.add i32.load call $future-cancel-read local.set $status
    \\      end
    \\    end
    \\    local.get $status drop
    \\    call $task-return-cancel
    \\    i32.const 0)
    \\  (func (export "[callback][async-lift]wasi:filesystem/probe@0.3.0-rc-2025-09-16#run") (type $callback) (param $event i32) (param $index i32) (param $payload i32) (result i32) (local $frame i32)
    \\    call $context-get-0 local.set $frame local.get $event i32.const 2 i32.eq if (result i32) local.get $frame local.get $payload call $accept-stream else
    \\      local.get $event i32.const 4 i32.eq if (result i32) local.get $frame i32.const 0 call $cleanup else unreachable end end)
    \\  (func (export "[callback][async-lift]wasi:filesystem/probe@0.3.0-rc-2025-09-16#cancel") (type $callback) (param $event i32) (param $index i32) (param $payload i32) (result i32)
    \\    unreachable)
    \\  (func (export "cabi_realloc") (type $realloc) (param $old i32) (param $old-size i32) (param $align i32) (param $size i32) (result i32)
    \\    global.get $heap-next local.get $size i32.add global.set $heap-next global.get $heap-next local.get $size i32.sub)
    \\  (func (export "_initialize") (type $initialize))
    \\)
;

test "read-via-stream plan records the bounded byte reader contract" {
    const source = @embedFile("test/compile_ok/451_wasi_filesystem_read_via_stream_component.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const plan = try ReadViaStreamPlan.analyze(tokens, registry);
    try std.testing.expectEqual(@as(usize, 1), plan.read_count);
    try std.testing.expectEqualStrings("file", plan.file_name);
    try std.testing.expectEqualStrings("offset", plan.offset_name);
}

test "read-via-stream plan rejects a missing completion await" {
    const source =
        \\read_via_stream = @host_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.read-via-stream", (File, u64) -> Tuple<Stream<u8>, Future<Result<nil, FileError>>>)
        \\run(file File, offset u64) -> nil {
        \\    handles Tuple<Stream<u8>, Future<Result<nil, FileError>>> = read_via_stream(file, offset)
        \\    reader Stream<u8> = @get(handles, 0)
        \\    completion Future<Result<nil, FileError>> = @get(handles, 1)
        \\    pending Future<Result<u8, nil>> = @next(reader)
        \\    item Result<u8, nil> = @await(pending)
        \\    _ = item
        \\    return
        \\}
    ;
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var registry = try p3_async_manifest.Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    try std.testing.expectError(error.UnsupportedP3WasiReadViaStreamComponent, ReadViaStreamPlan.analyze(tokens, registry));
}

test "read-via-stream WIT exposes the private cancellation endpoint" {
    const source = @embedFile("test/compile_ok/451_wasi_filesystem_read_via_stream_component.do");
    const tokens = try lexer.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);

    const wit = try emit_component_wit(std.testing.allocator, tokens);
    defer std.testing.allocator.free(wit);
    try std.testing.expect(std.mem.indexOf(u8, wit, "cancel: async func();") != null);
    try std.testing.expect(wit.len > 0);
    try std.testing.expectEqual(@as(u8, '\n'), wit[wit.len - 1]);
}
